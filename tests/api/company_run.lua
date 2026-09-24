-- Synthetic fixture matching Factory::Display's complete protocol; no profile data.
local Mock=dofile("tests/api/mock_adapter.lua")
local root=arg[1] or "."
dofile(root.."/src/scripts/api/v1.lua")
dofile(root.."/src/scripts/api/services.lua")
dofile(root.."/src/scripts/api/company.lua")
dofile(root.."/src/scripts/api/company_system.lua")
dofile(root.."/src/scripts/api/company_build.lua")
dofile(root.."/src/scripts/api/company_depot.lua")
dofile(root.."/src/scripts/api/company_transfer.lua")
dofile(root.."/src/scripts/factory/display_parser.lua")
dofile(root.."/src/scripts/factory/depot_parser.lua")
local API=F2CE.API.v1
local fixture=[[
Sample Ltd: Firewalls Production Facility #1
  Location: Example World  Status: Running
  Finance:
    Working Capital: -1,000ig  Top Up Level: 100,000ig
    Income: 40,000ig  Expenditure: 3,025ig
    Profit last company accounting period: -200ig
  Structure:
    Efficiency: 100/100
    Storage: 750/1500 tons available
  Workers:
    Required: 150  Hired: 150  Wages: 40ig
  Inputs:
    Semiconductors   Required: 20   Available: 5
  Output:
    Stored: 750 tons of Firewalls
    Dispose of Firewalls to exchange where possible
    Next batch is 45% complete
]]
local function lines(text) local out={}; for line in text:gmatch("[^\r\n]+") do out[#out+1]=line end; return out end
local function equal(a,b) assert(a==b,"expected "..tostring(b)..", got "..tostring(a)) end
local function code(err,want) equal(type(err)=="table" and err.code,want) end
local mock, context, observer, adapter
local function reset(rank)
    API:_reload(); mock=Mock.new(); observer=nil
    mock.gmcp={char={vitals={name="TestOwner",rank=rank or "Manufacturer"},
        company={name="Sample Ltd",ceo="TestOwner",cash=7000000,depots={"Example World"},factories={{number=1,output="Firewalls",planet="Example World"}}}}}
    if rank=="Industrialist" then mock.gmcp.char.business=mock.gmcp.char.company; mock.gmcp.char.company=nil end
    mock.gmcp.char.vitals.cash="1000000"; mock.gmcp.char.vitals.stamina={cur=100,max=100}
    mock.gmcp.char.ship={registry="TEST",hold={cur=150,max=150},cargo={}}
    mock.gmcp.room={info={num=1,area="Example World",system="Example",flags={"exchange"}}}
    adapter={name="company-test"}
    for _,name in ipairs({"f2ceVersion","registerEvent","unregisterEvent","timer","cancelTimer",
        "sendCommand","gmcpSnapshot","nativeCommandBlocker","haulingStatus","navState"}) do
        adapter[name]=function(...) return mock[name](mock,...) end
    end
    adapter.observeLine=function(callback) observer=callback; return 1 end
    adapter.unobserveLine=function() observer=nil end
    adapter.parseFactory=f2t_factory_parse_display
    adapter.parseDepot=f2t_depot_parse_display
    adapter.setting=function() return 25 end
    API._install(adapter)
    assert(API.modules.register({id="test.company",version="1.0.0",authorize=function() return true end}))
    context=assert(API.modules.enable("test.company"))
end
local passed,failed=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1; print("PASS "..name) else failed=failed+1; print("FAIL "..name..": "..tostring(err)) end
end
test("complete display preserves inputs and both kinds of profit",function()
    local value=assert(f2t_factory_parse_display(lines(fixture),1))
    equal(value.working_capital,-1000); equal(value.profit,-200); equal(value.current_net,36975)
    equal(value.inputs[1].commodity,"Semiconductors"); equal(value.inputs[1].shortfall,15)
    equal(value.inputs_met,false); equal(value.stored,750)
end)
test("wrapped display and input-free factory",function()
    local text=fixture:gsub("Inputs:\n    Semiconductors   Required: 20   Available: 5","Inputs:\n    None")
        :gsub("Next batch is 45%% complete","Next batch is 45%%\ncomplete")
    local value=assert(f2t_factory_parse_display(lines(text),1))
    equal(#value.inputs,0); equal(value.inputs_met,true)
end)
test("malformed partial duplicate and wrong-slot displays fail closed",function()
    equal(f2t_factory_parse_display(lines(fixture),2),nil)
    for _,text in ipairs({fixture:gsub("Next batch is 45%% complete",""),
        fixture:gsub("Available: 5","Available: 5 Semiconductors Required: 20 Available: 5"),
        fixture:gsub("40,000ig","4,00ig"),fixture:gsub("750 tons of Firewalls","749 tons of Firewalls"),
        (fixture:gsub("Finance:","Warning: incomplete Finance:"))}) do
        equal(f2t_factory_parse_display(lines(text),1),nil)
    end
end)
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test(rank.." refresh waits for an actual GMCP push",function()
    reset(rank); local calls=0
    assert(API.company.refresh(context,function(value,err) assert(value,tostring(err)); equal(err,nil); calls=calls+1 end))
    equal(mock.sent[1].command,rank=="Industrialist" and "di business" or "di company")
    local channel=rank=="Industrialist" and "business" or "company"
    assert(API.commands._lease); API.data.refresh(channel); equal(calls,0)
    mock:fireEvent("gmcp.char."..(channel=="business" and "company" or "business")); equal(calls,0)
    mock:fireEvent("gmcp.char."..channel); equal(calls,1); equal(API.commands._lease,nil)
    local copy=API.company.snapshot(); copy.cash=0; equal(API.company.snapshot().cash,7000000)
end)
end
test("complete factory response releases broker before callback",function()
    reset(); local calls=0
    assert(API.company.inspect(context,1,function(value,err)
        assert(value,tostring(err)); equal(err,nil); equal(API.commands._lease,nil); equal(observer,nil); calls=calls+1
    end))
    equal(mock.sent[1].command,"display factory 1")
    for _,line in ipairs(lines(fixture)) do observer(line) end
    equal(calls,1)
end)
test("partial display timeout cleans observer and ignores late lines",function()
    reset(); local calls=0
    assert(API.company.inspect(context,1,function(value,err) equal(value,nil); code(err,"E_COMPANY_TIMEOUT"); calls=calls+1 end))
    local late=observer; late("Sample Ltd: Firewalls Production Facility #1")
    mock:runTimers(); equal(calls,1); equal(observer,nil); equal(API.commands._lease,nil)
    late(fixture); equal(calls,1)
end)
test("wrong company identity and rank are rejected without sends",function()
    reset("Trader"); local value,err=API.company.refresh(context,function() end)
    equal(value,nil); code(err,"E_COMPANY_RANK"); equal(#mock.sent,0)
    reset(); mock.gmcp.char.company.ceo="SomeoneElse"; mock:fireEvent("gmcp.char.company")
    value,err=API.company.inspect(context,1,function() end)
    equal(value,nil); code(err,"E_COMPANY_DATA"); equal(#mock.sent,0)
end)
test("company switch during capture rejects even a complete old display",function()
    reset(); local calls=0
    assert(API.company.inspect(context,1,function(value,err) equal(value,nil); code(err,"E_COMPANY_IDENTITY"); calls=calls+1 end))
    mock.gmcp.char.vitals.name="SomeoneElse"; mock:fireEvent("gmcp.char.vitals")
    observer(fixture); equal(calls,1); equal(API.commands._lease,nil)
end)
test("cancel and disconnect never complete a stale request",function()
    for _,disconnect in ipairs({false,true}) do
        reset(); local calls=0
        local handle=assert(API.company.inspect(context,1,function() calls=calls+1 end))
        local late=observer
        if disconnect then API._reconnectReset("disconnect") else handle:cancel() end
        equal(observer,nil); equal(API.commands._lease,nil); late(fixture); mock:runTimers(); equal(calls,0)
    end
end)
test("contention unknown slot and injection cannot send a request",function()
    reset()
    for _,number in ipairs({0,16,"1;buy factory",2}) do
        equal(API.company.inspect(context,number,function() end),nil)
    end
    mock.native_blocker={kind="hauling"}
    local value,err=API.company.refresh(context,function() end)
    equal(value,nil); code(err,"E_COMMAND_CONTENTION"); equal(#mock.sent,0)
end)
test("missing factory server reply is an error not an empty valid factory",function()
    reset(); local calls=0
    assert(API.company.inspect(context,1,function(value,err) equal(value,nil); code(err,"E_FACTORY_MISSING"); calls=calls+1 end))
    observer("You don't have a factory with that number!"); equal(calls,1); equal(API.commands._lease,nil)
end)
local depot=[[Location: Example World
 Capacity: 20 cargo bays Workforce: 10 Efficiency: 100%
 Bay # 1 Semiconductors Cost 300ig/ton (Origin Other World, Other System system)
 Bay # 3 Firewalls Cost 1,200ig/ton (Origin Example World, Example System system)
]]
local function fence(rank,summary)
    if rank=="Industrialist" then observer("Sample Ltd registered business - CEO Industrialist TestOwner")
    else
        observer("Company Report for Sample Ltd:")
        observer("Example World - Capacity: 20 bays ("..(summary or 2).." in use) 100% efficiency")
    end
end
test("strict depot parsing handles empty, wrapped, gapped full bays",function()
    local d=assert(f2t_depot_parse_display(lines(depot),"Example World"))
    equal(d.used_bays,2); equal(d.free_bays,18); equal(d.inventory.semiconductors,75); equal(d.bays[2].cost_per_ton,1200)
    equal(assert(f2t_depot_parse_display(lines(depot:gsub("Example System","Example\nSystem")),"Example World")).used_bays,2)
    d=assert(f2t_depot_parse_display({"Location: Example World Capacity: 20 cargo bays Workforce: 10 Efficiency: 100% The depot is empty."},"Example World"))
    equal(d.used_bays,0); equal(d.free_bays,20)
    for _,bad in ipairs({depot:gsub("# 3","# 1"),depot:gsub("# 3","# 21"),depot:gsub("1,200ig","1,20ig"),
        depot:gsub("1,200ig",",120ig"),depot:gsub("Other System system%)","Other System"),depot.."Unexpected text"}) do
        equal(f2t_depot_parse_display(lines(bad),"Example World"),nil)
    end
    equal(f2t_depot_parse_display(lines(depot),"Other World"),nil)
end)
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test(rank.." depot requires ordered owner fence and real rank-specific GMCP",function()
    reset(rank); local calls=0
    assert(API.company.depot(context,"Example World",function(d,err)
        assert(d,tostring(err)); equal(d.owner,"Sample Ltd"); equal(d.used_bays,2); equal(API.commands._lease,nil); calls=calls+1
    end))
    equal(mock.sent[1].command,"display depot Example World")
    equal(mock.sent[2].command,rank=="Industrialist" and "di business" or "di company")
    observer(depot); equal(calls,0); fence(rank); equal(calls,0)
    local channel=rank=="Industrialist" and "business" or "company"
    API.data.refresh(channel); equal(calls,0)
    mock:fireEvent("gmcp.char."..channel); equal(calls,1); equal(observer,nil)
end)
end
test("early GMCP waits for text fence and manufacturer occupancy",function()
    reset(); local calls=0
    assert(API.company.depot(context,"Example World",function(d,err) assert(d,tostring(err)); calls=calls+1 end))
    mock:fireEvent("gmcp.char.company"); equal(calls,0)
    observer(depot); observer("Company Report for Sample Ltd:"); equal(calls,0)
    observer("Example World - Capacity: 20 bays (2 in use) 100% efficiency"); equal(calls,1)
end)
test("depot changed, ownership switch and truncated capture reject",function()
    reset(); local err
    assert(API.company.depot(context,"Example World",function(_,e) err=e end)); observer(depot); fence(nil,3)
    mock:fireEvent("gmcp.char.company"); code(err,"E_DEPOT_CHANGED")
    reset(); err=nil
    assert(API.company.depot(context,"Example World",function(_,e) err=e end)); observer(depot)
    mock.gmcp.char.company.ceo="Other"; mock:fireEvent("gmcp.char.company"); code(err,"E_COMPANY_IDENTITY")
    reset(); err=nil
    assert(API.company.depot(context,"Example World",function(_,e) err=e end)); observer(depot)
    mock:runTimers(); code(err,"E_COMPANY_TIMEOUT"); equal(observer,nil); equal(API.commands._lease,nil)
end)
test("depot missing, unsafe name and contention send nothing",function()
    reset()
    for _,planet in ipairs({"Missing","Example World;quit","Example World\nquit"}) do equal(API.company.depot(context,planet,function() end),nil) end
    equal(#mock.sent,0)
    mock.native_blocker={kind="hauling"}; equal(API.company.depot(context,"Example World",function() end),nil); equal(#mock.sent,0)
end)
test("depot disconnect and OFF reject late response without callback",function()
    for _,disconnect in ipairs({true,false}) do
        reset(); local calls=0
        local h=assert(API.company.depot(context,"Example World",function() calls=calls+1 end)); local late=observer
        if disconnect then API._reconnectReset("disconnect") else h:cancel("OFF") end
        late(depot); mock:runTimers(); equal(calls,0); equal(API.commands._lease,nil); equal(observer,nil)
    end
end)
test("Industrialist never uses a stale company snapshot",function()
    reset("Industrialist"); mock.gmcp.char.business=nil; mock.gmcp.char.company={name="Old Ltd",ceo="TestOwner",factories={}}
    mock:fireEvent("gmcp.char.company"); mock:fireEvent("gmcp.char.business")
    equal(API.company.snapshot(),nil)
end)
local function state_push()
    for _,event in ipairs({"gmcp.room.info","gmcp.char.ship","gmcp.char.vitals.cash","gmcp.char.vitals.stamina"}) do mock:fireEvent(event) end
end
local function depot_push(text,used,rank)
    observer(text); fence(rank,used)
    mock:fireEvent(rank=="Industrialist" and "gmcp.char.business" or "gmcp.char.company")
end
local function options(side)
    return {side=side or "fetch",bay=3,commodity="Semiconductors",planet="Example World",personal_reserve=100000,company_reserve=1000000}
end
local function store_cargo()
    mock.gmcp.char.ship.cargo={{commodity="Semiconductors",origin="Other World",cost=300}}
    mock.gmcp.char.ship.hold.cur=75; mock:fireEvent("gmcp.char.ship")
end
test("transfer preview is read-only, holds broker and expires without a write",function()
    reset(); local result,err
    local h=assert(API.company.prepareTransfer(context,options(),function(v,e) result,err=v,e end))
    equal(mock.sent[1].command,"score"); state_push(); depot_push(depot,2)
    equal(h:status().phase,"ready"); equal(result.value,90000); equal(#mock.sent,3); assert(API.commands._lease)
    mock:runTimers(); code(err,"E_DEPOT_EXPIRED"); equal(API.commands._lease,nil); equal(h:status().sent,false)
end)
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
for _,side in ipairs({"store","fetch"}) do
test(rank.." confirms exactly one "..side.." against ship depot and cash",function()
    reset(rank); if side=="store" then store_cargo() end
    local h=assert(API.company.prepareTransfer(context,options(side),function(v,e) assert(v,tostring(e)) end))
    state_push(); depot_push(depot,2,rank)
    local result,err
    assert(h:confirm(function(v,e) result,err=v,e end)); equal(h:confirm(function() end),nil)
    state_push(); depot_push(depot,2,rank)
    equal(h:status().sent,true); equal(h:status().phase,"settling")
    local co=mock.gmcp.char[rank=="Industrialist" and "business" or "company"]
    local text,used
    if side=="store" then
        mock.gmcp.char.ship.cargo={}; mock.gmcp.char.ship.hold.cur=150
        mock.gmcp.char.vitals.cash="1022500"; co.cash=6977500
        text=depot.."Bay # 2 Semiconductors Cost 300ig/ton (Origin Other World, Other System system)"; used=3
    else
        mock.gmcp.char.ship.cargo={{commodity="Firewalls",origin="Example World",cost=1200}}; mock.gmcp.char.ship.hold.cur=75
        mock.gmcp.char.vitals.cash="910000"; co.cash=7090000
        text=depot:gsub(" Bay # 3[^\n]+\n",""); used=1
    end
    state_push(); depot_push(text,used,rank)
    assert(result,tostring(err)); equal(result.confirmed,true); equal(API.commands._lease,nil); equal(h:status().phase,"confirmed")
    local writes=0; for _,s in ipairs(mock.sent) do if s.command:match("^store ") or s.command:match("^fetch ") then writes=writes+1 end end
    equal(writes,1)
end)
end
end
test("transfer rejects changed inventory between preview and confirmation without a write",function()
    reset(); local err
    local h=assert(API.company.prepareTransfer(context,options(),function() end)); state_push(); depot_push(depot,2)
    assert(h:confirm(function(_,e) err=e end)); store_cargo(); state_push(); depot_push(depot,2)
    code(err,"E_DEPOT_CHANGED"); equal(h:status().sent,false); equal(API.commands._lease,nil)
end)
test("transfer refuses reserves, low stamina, full ship and full depot",function()
    for _,case in ipairs({"cash","company","stamina","ship","depot"}) do
        reset(); local side=(case=="company" or case=="depot") and "store" or "fetch"
        if side=="store" then store_cargo() end
        local o=options(side)
        if case=="cash" then o.personal_reserve=1000000 elseif case=="company" then o.company_reserve=7000000 end
        if case=="stamina" then mock.gmcp.char.vitals.stamina.cur=20 end
        if case=="ship" then mock.gmcp.char.ship.hold={cur=0,max=75}; mock.gmcp.char.ship.cargo={{commodity="Parts",origin="Home",cost=1}} end
        mock:fireEvent("gmcp.char.ship")
        local err; local h=assert(API.company.prepareTransfer(context,o,function(_,e) err=e end)); state_push()
        if case=="depot" then
            local text="Location: Example World Capacity: 1 cargo bays Workforce: 10 Efficiency: 100% Bay #1 Parts Cost 1ig/ton (Origin Home, Example system)"
            observer(text); observer("Company Report for Sample Ltd: Example World - Capacity: 1 bays (1 in use) 100% efficiency"); mock:fireEvent("gmcp.char.company")
        else depot_push(depot,2) end
        assert(err,case); equal(h:status().sent,false); equal(API.commands._lease,nil)
    end
end)
test("unconfirmed transfer never retries or claims success",function()
    reset(); local err
    local h=assert(API.company.prepareTransfer(context,options(),function() end)); state_push(); depot_push(depot,2)
    assert(h:confirm(function(_,e) err=e end)); state_push(); depot_push(depot,2)
    state_push(); depot_push(depot,2) -- server evidence unchanged
    code(err,"E_DEPOT_UNCONFIRMED"); equal(h:status().phase,"unconfirmed"); equal(API.commands._lease,nil)
    local n=#mock.sent; mock:runTimers(); equal(#mock.sent,n); equal(h:confirm(function() end),nil)
end)
test("location changes and pre-send cancellation invalidate transfer authority",function()
    reset(); local err
    local h=assert(API.company.prepareTransfer(context,options(),function(_,e) err=e end))
    mock.gmcp.room.info.num=2; state_push(); code(err,"E_COMPANY_IDENTITY"); equal(h:status().sent,false)
    reset(); h=assert(API.company.prepareTransfer(context,options(),function() error("late callback") end))
    h:cancel("OFF"); local n=#mock.sent; state_push(); mock:runTimers(); equal(#mock.sent,n); equal(API.commands._lease,nil)
end)
test("disconnect after sending leaves an uncertain outcome and cannot replay",function()
    reset(); local h=assert(API.company.prepareTransfer(context,options(),function() end)); state_push(); depot_push(depot,2)
    assert(h:confirm(function() error("late callback") end)); state_push(); depot_push(depot,2)
    API._reconnectReset("disconnect"); equal(h:status().phase,"unconfirmed"); equal(h:status().uncertain,true)
    local n=#mock.sent; state_push(); mock:runTimers(); equal(#mock.sent,n); equal(API.commands._lease,nil)
end)
test("exact ambient exchange ticker does not contaminate depot rows",function()
    reset(); local result,err
    assert(API.company.depot(context,"Example World",function(v,e) result,err=v,e end))
    observer("+++ The exchange display shows the prices for Alloys +++")
    observer("+++ Exchange has 10000 tons for sale +++")
    observer("+++ Offer price is 145ig/ton for first 75 tons +++")
    observer("+++ Exchange will buy 75 tons at 125ig/ton +++")
    depot_push(depot,2); assert(result,tostring(err)); equal(result.used_bays,2)
    reset(); assert(API.company.depot(context,"Example World",function(_,e) err=e end))
    observer("+++ unknown output +++"); observer(depot); observer("Company Report for Sample Ltd:"); code(err,"E_DEPOT_DISPLAY")
end)
local function market_push(rank)
    state_push(); mock:fireEvent("gmcp.exchange.commodities"); mock:fireEvent(rank=="Industrialist" and "gmcp.char.business" or "gmcp.char.company")
end
local function market_options(side)
    return {side=side,planet="Example World",commodity="Semiconductors",personal_reserve=100000,
        company_reserve=1000000,price_limit=side=="buy" and 300 or 500,single_cargo=true}
end
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
for _,side in ipairs({"buy","sell"}) do
test(rank.." market "..side.." requires fresh quote and exactly reconciles one bay",function()
    reset(rank); if side=="sell" then store_cargo() end
    mock.gmcp.exchange={commodities={Semiconductors={stock=5000,sell=300,buy=500}}}
    local proposal,result,err
    local h=assert(API.company.prepareCargo(context,market_options(side),function(v,e) proposal,err=v,e end))
    state_push(); equal(proposal,nil); mock:fireEvent("gmcp.exchange.commodities"); equal(proposal,nil)
    mock:fireEvent(rank=="Industrialist" and "gmcp.char.business" or "gmcp.char.company")
    assert(proposal,tostring(err)); equal(#mock.sent,3)
    equal(mock.sent[1].command,"score"); equal(mock.sent[2].command,"look")
    equal(mock.sent[3].command,rank=="Industrialist" and "di business" or "di company")
    assert(h:confirm(function(v,e) result,err=v,e end)); market_push(rank)
    equal(mock.sent[7].command,side.." Semiconductors 1")
    if side=="buy" then
        mock.gmcp.char.ship.cargo={{commodity="Semiconductors",cost=300,origin="Example World"}}; mock.gmcp.char.ship.hold.cur=75
        mock.gmcp.char.vitals.cash="977500"
    else mock.gmcp.char.ship.cargo={}; mock.gmcp.char.ship.hold.cur=150; mock.gmcp.char.vitals.cash="1037500" end
    market_push(rank); assert(result,tostring(err)); equal(h:status().phase,"confirmed"); equal(API.commands._lease,nil)
    equal(h:confirm(function() end),nil)
end)
end
end
test("market bounds refuse inadequate input stock, bid, cash and mixed cargo",function()
    for _,case in ipairs({"stock","ask","bid","personal","company","mixed","space","origin"}) do
        reset(); local side=(case=="bid" or case=="mixed" or case=="origin") and "sell" or "buy"
        if side=="sell" then store_cargo() end
        mock.gmcp.exchange={commodities={Semiconductors={stock=5000,sell=300,buy=500}}}
        local row=mock.gmcp.exchange.commodities.Semiconductors
        if case=="stock" then row.stock=4999 elseif case=="ask" then row.sell=301 elseif case=="bid" then row.buy=499 end
        local o=market_options(side)
        if case=="personal" then o.personal_reserve=1000000 elseif case=="company" then o.company_reserve=7000000 end
        if case=="mixed" then mock.gmcp.char.ship.cargo[2]={commodity="Parts",origin="Home",cost=1}; mock.gmcp.char.ship.hold.cur=0 end
        if case=="origin" then mock.gmcp.char.ship.cargo[1].origin="example world" end
        local err; local h=assert(API.company.prepareCargo(context,o,function(_,e) err=e end))
        if case=="space" then mock.gmcp.room.info.flags={"space"} end
        market_push(); assert(err,case); equal(h:status().sent,false); equal(API.commands._lease,nil)
    end
end)
test("market reprices before confirmation and refuses an uncertain cash delta without retry",function()
    reset(); mock.gmcp.exchange={commodities={Semiconductors={stock=5000,sell=300,buy=500}}}
    local err; local h=assert(API.company.prepareCargo(context,market_options("buy"),function() end)); market_push()
    assert(h:confirm(function(_,e) err=e end)); mock.gmcp.exchange.commodities.Semiconductors.sell=301; market_push()
    code(err,"E_CARGO_MARKET"); equal(h:status().sent,false)
    local o=market_options("buy"); o.price_limit=301
    h=assert(API.company.prepareCargo(context,o,function() end)); market_push(); assert(h:confirm(function(_,e) err=e end)); market_push()
    market_push(); code(err,"E_DEPOT_UNCONFIRMED"); local n=#mock.sent; mock:runTimers(); equal(#mock.sent,n)
end)
test("depot workflow rejects changed reservation evidence and unexpected ship cargo",function()
    reset(); local o=options(); o.expected_depot={}; local err
    local h=assert(API.company.prepareTransfer(context,o,function(_,e) err=e end)); state_push(); depot_push(depot,2)
    code(err,"E_DEPOT_CHANGED"); equal(h:status().sent,false)
    reset(); store_cargo(); o=options(); o.single_cargo=true
    h=assert(API.company.prepareTransfer(context,o,function(_,e) err=e end)); state_push(); depot_push(depot,2)
    code(err,"E_CARGO_SHIP"); equal(h:status().sent,false)
end)
local system_fixture=[[
System information for the Serenity system:
  Member of the Zork cartel
  Member of the Zork syndicate
Holland, Serenity system, Zork cartel, Zork syndicate
  Owner: Magnate Example
  Economy: Leisure    Workers available: 2500/2500
  Infrastructure built: 436
  Shipyard markup: -10%
  Approval rating: +63
Denmark, Serenity system, Zork cartel, Zork syndicate
  Closed to visitors
  Owner: Magnate Example
  Economy: Technical    Workers available: 0/1800
Serenity Space, Serenity system, Zork cartel
  Owner: Example
  Economy: None
]]
test("system workforce parser joins wrapped headers and reads per-planet availability",function()
    local text=system_fixture:gsub("Holland, Serenity system, Zork cartel","Holland, Serenity system,\n  Zork cartel")
    local row=assert(API.company._parseSystem(text,"Serenity"))
    equal(row.planets.holland.available,2500); equal(row.planets.holland.total,2500)
    equal(row.planets.holland.economy,"Leisure"); equal(row.planets.denmark.available,0)
    equal(row.planets.denmark.closed,true); equal(row.planets["serenity space"].available,nil)
end)
test("system parser rejects partial, duplicated, wrong-system and malformed worker evidence",function()
    equal(API.company._parseSystem(system_fixture,"Elsewhere"),nil)
    for _,text in ipairs({system_fixture:gsub("Workers available: 2500/2500","Workers available: 2501/2500"),
        system_fixture:gsub("Workers available: 2500/2500","Workers available: 2500/2500x"),
        system_fixture:gsub("Workers available: 2500/2500","Workers available: 2,500/2,500"),
        system_fixture:gsub("Workers available: 2500/2500","Workers available: 2500/2500 Workers available: 1/2"),
        system_fixture:gsub("Workers available: 2500/2500",""),system_fixture:gsub("Leisure","FutureTech"),
        system_fixture:gsub("Denmark,","Holland,"),system_fixture:gsub("Denmark, Serenity","Denmark, Elsewhere")}) do
        equal(API.company._parseSystem(text,"Serenity"),nil)
    end
end)
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test("system read holds lease through text and fresh owner fence at "..rank,function()
    reset(rank); local value,calls=nil,0
    local h=assert(API.company.system(context,"Serenity",function(v,e) assert(not e); value=v; calls=calls+1 end))
    equal(mock.sent[1].command,"di system Serenity")
    equal(mock.sent[2].command,rank=="Industrialist" and "di business" or "di company")
    observer(system_fixture); equal(calls,0); assert(API.commands._lease)
    fence(rank); equal(calls,0)
    mock:fireEvent(rank=="Industrialist" and "gmcp.char.business" or "gmcp.char.company")
    equal(calls,1); equal(value.planets.holland.available,2500); assert(value.captured_at)
    equal(API.commands._lease,nil); equal(h:status().active,false); equal(observer,nil)
end)
end
test("system read permits GMCP-before-text fence but never silence, unsafe names or late callbacks",function()
    reset(); local calls=0; local value
    assert(API.company.system(context,"Serenity",function(v,e) assert(not e); value=v; calls=calls+1 end))
    mock:fireEvent("gmcp.char.company"); equal(calls,0)
    observer(system_fixture); equal(calls,0); observer("Company Report for Sample Ltd:"); equal(calls,1); assert(value)
    reset(); local err
    local h=assert(API.company.system(context,"Serenity",function(_,e) err=e end)); local late=observer
    late(system_fixture); mock:runTimers(); code(err,"E_COMPANY_TIMEOUT"); equal(API.commands._lease,nil)
    late("Company Report for Sample Ltd:"); equal(#mock.sent,2)
    local invalid,problem=API.company.system(context,"Serenity;quit",function() end)
    equal(invalid,nil); code(problem,"E_ARGUMENT"); equal(#mock.sent,2); equal(h:status().active,false)
end)
test("system read cancellation, wrong owner and incomplete report release resources",function()
    reset(); local calls=0
    local h=assert(API.company.system(context,"Serenity",function() calls=calls+1 end)); local late=observer
    h:cancel(); late(system_fixture); mock:runTimers(); equal(calls,0); equal(API.commands._lease,nil)
    reset(); local err
    assert(API.company.system(context,"Serenity",function(_,e) err=e end))
    mock.gmcp.char.vitals.rank="Industrialist"; mock:fireEvent("gmcp.char.vitals"); mock:fireEvent("gmcp.char.company")
    code(err,"E_COMPANY_IDENTITY"); equal(API.commands._lease,nil)
    reset(); err=nil; assert(API.company.system(context,"Serenity",function(_,e) err=e end))
    observer("I don't know that system."); observer("Company Report for Sample Ltd:")
    equal(err,nil); mock:runTimers(); code(err,"E_COMPANY_TIMEOUT"); equal(API.commands._lease,nil)
end)
test("system read ignores preceding command text and fences only the requested header",function()
    reset(); local value,calls=nil,0
    assert(API.company.system(context,"Serenity",function(v,e) assert(not e); value=v; calls=calls+1 end))
    observer("Trailing room description."); observer("Company Report for Sample Ltd:")
    observer("System information for the Other system:")
    mock:fireEvent("gmcp.char.company"); equal(calls,0)
    observer(system_fixture); equal(calls,0)
    observer("Company Report for Sample Ltd:"); equal(calls,1); equal(value.planets.holland.available,2500)
    equal(API.commands._lease,nil)
end)
local function build_options()
    return {planet="Example World",system="Example",commodity="Firewalls",company_reserve=1000000,
        labour=150,biological_required=false,output_price_floor=800,
        inputs={{commodity="Semiconductors",required=20,minimum_stock=5000,price_limit=300}}}
end
local function build_reset(rank)
    reset(rank); mock.gmcp.exchange={commodities={Semiconductors={stock=5000,sell=300,buy=200},Firewalls={stock=100,sell=1000,buy=900}}}
    local channel=rank=="Industrialist" and "business" or "company"
    mock.gmcp.char[channel].factories[1].output="Droids"; mock:fireEvent("gmcp.char."..channel)
end
local function build_fresh(rank,workers,economy,commercial)
    mock:fireEvent("gmcp.room.info"); mock:fireEvent("gmcp.char.vitals.stamina"); mock:fireEvent("gmcp.exchange.commodities")
    if not observer then return end
    local prefix=mock.sent[#mock.sent-1].command=="di planet Example World" and "" or "System information for the Example system:\n  Member of the Test cartel\n"
    observer(prefix.."Example World, Example system, Test cartel\n  Owner: Example\n  Economy: "..(economy or "Leisure").."    Workers available: "..(workers or 2500).."/2500\n  Shipyard markup: 10%\n  Approval rating: Satisfactory"..(commercial or ""))
    observer(rank=="Industrialist" and "Sample Ltd registered business - CEO Industrialist TestOwner" or "Company Report for Sample Ltd:")
    mock:fireEvent(rank=="Industrialist" and "gmcp.char.business" or "gmcp.char.company")
end
local function buys()
    local n=0; for _,row in ipairs(mock.sent) do if row.command:match("^buy factory ") then n=n+1 end end; return n
end
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test("factory preview/confirm buys once and reconciles slot plus company debit at "..rank,function()
    build_reset(rank); local proposal,result,err
    local h=assert(API.company.prepareFactory(context,build_options(),function(v,e) proposal,err=v,e end))
    build_fresh(rank); assert(proposal,tostring(err)); equal(proposal.cost,2000000); equal(proposal.slot,2)
    equal(proposal.after_build,5000000); equal(buys(),0); assert(API.commands._lease)
    assert(h:confirm(function(v,e) result,err=v,e end)); build_fresh(rank)
    equal(buys(),1); equal(h:status().phase,"settling"); equal(result,nil)
    local channel=rank=="Industrialist" and "business" or "company"
    mock.gmcp.char[channel].cash=5000000
    mock.gmcp.char[channel].factories[2]={number=2,planet="Example World",output="Firewalls"}
    mock:fireEvent("gmcp.char."..channel)
    assert(result,tostring(err)); equal(result.confirmed,true); equal(result.company_cash,5000000)
    equal(h:status().active,false); equal(API.commands._lease,nil); equal(h:confirm(function() end),nil); equal(buys(),1)
end)
end
test("first factory uses slot one without requiring an owned factory recipe",function()
    build_reset(); mock.gmcp.char.company.factories={}; mock:fireEvent("gmcp.char.company")
    local proposal,result,err
    local h=assert(API.company.prepareFactory(context,build_options(),function(v,e) proposal,err=v,e end))
    build_fresh(); assert(proposal,tostring(err)); equal(proposal.slot,1); equal(buys(),0)
    assert(h:confirm(function(v,e) result,err=v,e end)); build_fresh()
    mock.gmcp.char.company.factories={{number=1,planet="Example World",output="Firewalls"}}
    mock.gmcp.char.company.cash=5000000; mock:fireEvent("gmcp.char.company")
    assert(result,tostring(err)); equal(result.slot,1); equal(buys(),1); equal(API.commands._lease,nil)
end)

test("factory preview refuses missing workers, bad economy, stock, bid, reserves and slots",function()
    for _,case in ipairs({"workers","bio","stock","ask","bid","reserve","slots","stamina"}) do
        build_reset(); local o=build_options(); local err
        if case=="bio" then o.biological_required=true end
        if case=="stock" then mock.gmcp.exchange.commodities.Semiconductors.stock=4999 end
        if case=="ask" then mock.gmcp.exchange.commodities.Semiconductors.sell=301 end
        if case=="bid" then mock.gmcp.exchange.commodities.Firewalls.buy=799 end
        if case=="reserve" then o.company_reserve=5000001 end
        if case=="slots" then for i=2,15 do mock.gmcp.char.company.factories[i]={number=i,planet="Example World",output="Firewalls"} end end
        if case=="stamina" then mock.gmcp.char.vitals.stamina.cur=25 end
        local h=assert(API.company.prepareFactory(context,o,function(_,e) err=e end))
        build_fresh(nil,case=="workers" and 149 or 2500)
        assert(err,case); equal(buys(),0); equal(API.commands._lease,nil); equal(h:status().active,false)
    end
end)
test("price-review preview returns worse live quotes without buying; confirmation uses those exact bounds",function()
    build_reset(); local o=build_options(); o.review_prices=true
    mock.gmcp.exchange.commodities.Firewalls.buy=799
    mock.gmcp.exchange.commodities.Semiconductors.sell=301
    local p,err,result,payload
    API._modules[context.module_id].spec.authorize=function(op,data) if op=="company.factory.buy" then payload=data end; return true end
    local h=assert(API.company.prepareFactory(context,o,function(v,e) p,err=v,e end)); build_fresh()
    assert(p,tostring(err)); equal(p.market_review.required,true); equal(p.market_review.output.previous_price,800)
    equal(p.market_review.output.current_price,799); equal(p.market_review.inputs[1].current_price,301)
    equal(o.output_price_floor,800); equal(o.inputs[1].price_limit,300); equal(buys(),0)
    assert(h:confirm(function(v,e) result,err=v,e end)); build_fresh()
    equal(payload.output_price_floor,799); equal(payload.inputs[1].price_limit,301); equal(buys(),1)
    mock.gmcp.char.company.cash=5000000; mock.gmcp.char.company.factories[2]={number=2,planet="Example World",output="Firewalls"}
    mock:fireEvent("gmcp.char.company"); assert(result,tostring(err)); equal(result.confirmed,true)
end)
test("price review never weakens stock, output demand, workers or reserve checks",function()
    for _,case in ipairs({"stock","demand","workers","reserve"}) do
        build_reset(); local o=build_options(); o.review_prices=true; local err
        mock.gmcp.exchange.commodities.Firewalls.buy=799
        if case=="stock" then mock.gmcp.exchange.commodities.Semiconductors.stock=4999 end
        if case=="demand" then mock.gmcp.exchange.commodities.Firewalls.buy=0 end
        if case=="reserve" then o.company_reserve=5000001 end
        assert(API.company.prepareFactory(context,o,function(_,e) err=e end)); build_fresh(nil,case=="workers" and 149 or 2500)
        assert(err,case); equal(buys(),0); equal(API.commands._lease,nil)
    end
end)
test("price-review opt-in does not rebase a worse quote again at confirmation",function()
    for _,case in ipairs({"bid","ask"}) do
        build_reset(); local o=build_options(); o.review_prices=true; local p,err
        mock.gmcp.exchange.commodities.Firewalls.buy=799
        local h=assert(API.company.prepareFactory(context,o,function(v,e) p,err=v,e end)); build_fresh(); assert(p)
        if case=="bid" then mock.gmcp.exchange.commodities.Firewalls.buy=798 else mock.gmcp.exchange.commodities.Semiconductors.sell=301 end
        assert(h:confirm(function(_,e) err=e end)); build_fresh()
        assert(err,case); equal(buys(),0); equal(API.commands._lease,nil)
    end
end)
test("favourable reviewed prices do not change the original authorized bounds",function()
    build_reset(); local o=build_options(); o.review_prices=true; local p
    mock.gmcp.exchange.commodities.Semiconductors.sell=299
    local h=assert(API.company.prepareFactory(context,o,function(v) p=v end)); build_fresh()
    equal(p.market_review.required,false)
    mock.gmcp.exchange.commodities.Firewalls.buy=800; mock.gmcp.exchange.commodities.Semiconductors.sell=300
    assert(h:confirm(function() end)); build_fresh(); equal(buys(),1)
end)
test("factory refuses Sol, wrong rank/location and injected names before reads",function()
    for _,case in ipairs({"sol","rank","location","commodity","input","reserve"}) do
        build_reset(); local o=build_options()
        if case=="sol" then o.system="Sol" end
        if case=="rank" then mock.gmcp.char.vitals.rank="Financier"; mock:fireEvent("gmcp.char.vitals") end
        if case=="location" then mock.gmcp.room.info.area="Elsewhere"; mock:fireEvent("gmcp.room.info") end
        if case=="commodity" then o.commodity="Firewalls;quit" end
        if case=="input" then o.inputs[2]=o.inputs[1] end
        if case=="reserve" then o.company_reserve=-1 end
        equal(API.company.prepareFactory(context,o,function() end),nil); equal(#mock.sent,0)
    end
end)
test("factory confirmation repeats conditions and refuses changed roster or authorization",function()
    for _,case in ipairs({"roster","workers","ask","cash","authority"}) do
        build_reset(); local err; local h=assert(API.company.prepareFactory(context,build_options(),function() end)); build_fresh()
        if case=="roster" then mock.gmcp.char.company.factories[2]={number=2,planet="Example World",output="Alloys"} end
        if case=="ask" then mock.gmcp.exchange.commodities.Semiconductors.sell=301 end
        if case=="cash" then mock.gmcp.char.company.cash=2999999 end
        if case=="authority" then API._modules[context.module_id].spec.authorize=function(op) return op~="company.factory.buy" end end
        assert(h:confirm(function(_,e) err=e end)); build_fresh(nil,case=="workers" and 0 or 2500)
        assert(err,case); equal(buys(),0); equal(API.commands._lease,nil)
    end
end)
test("factory timeout/expiry/cancel never repeat or claim an uncertain purchase",function()
    for _,stage in ipairs({"reading","ready","settling"}) do
        build_reset(); local err; local h=assert(API.company.prepareFactory(context,build_options(),function(_,e) err=e end))
        if stage~="reading" then build_fresh() end
        if stage=="settling" then assert(h:confirm(function(_,e) err=e end)); build_fresh() end
        mock:runTimers(); assert(err); equal(API.commands._lease,nil); equal(buys(),stage=="settling" and 1 or 0)
        if stage=="settling" then code(err,"E_FACTORY_UNCONFIRMED") end
        mock:runTimers(); equal(buys(),stage=="settling" and 1 or 0)
    end
    build_reset(); local called=false; local h=assert(API.company.prepareFactory(context,build_options(),function() end)); build_fresh()
    assert(h:confirm(function() called=true end)); build_fresh(); h:cancel("OFF")
    mock:fireEvent("gmcp.char.company"); equal(called,false); equal(h:status().uncertain,true); equal(API.commands._lease,nil)
end)
test("factory mismatched confirmation is unresolved, never a retry",function()
    build_reset(); local err; local h=assert(API.company.prepareFactory(context,build_options(),function() end)); build_fresh()
    assert(h:confirm(function(_,e) err=e end)); build_fresh()
    mock.gmcp.char.company.factories[2]={number=2,planet="Example World",output="Alloys"}
    mock.gmcp.char.company.cash=5000000; mock:fireEvent("gmcp.char.company")
    code(err,"E_FACTORY_UNCONFIRMED"); equal(buys(),1); equal(API.commands._lease,nil)
end)
local function site_options(depot_only)
    local o=build_options(); o.require_depot=true; o.factory_limit=8; o.depot_only=depot_only==true
    if depot_only then o.commodity="Depot"; o.labour=0; o.inputs={} end
    return o
end
local function depot_buys()
    local n=0; for _,r in ipairs(mock.sent) do if r.command=="buy depot" then n=n+1 end end; return n
end
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test(rank.." site confirms depot before factory and reconciles 3004480 including initial wages",function()
    build_reset(rank); local channel=rank=="Industrialist" and "business" or "company"
    local c=mock.gmcp.char[channel]; c.depots={}; mock:fireEvent("gmcp.char."..channel)
    local proposal,result,err
    local h=assert(API.company.prepareFactory(context,site_options(),function(v,e) proposal,err=v,e end)); build_fresh(rank,157)
    assert(proposal,tostring(err)); equal(proposal.cost,3004480); equal(proposal.workers_required,157); equal(depot_buys(),0)
    assert(h:confirm(function(v,e) result,err=v,e end)); build_fresh(rank,157)
    equal(depot_buys(),1); equal(buys(),0)
    c.depots={"EXAMPLE WORLD"}; c.cash=5995520; build_fresh(rank,150)
    equal(buys(),1); equal(result,nil)
    c.cash=3995520; c.factories[2]={number=2,planet="Example World",output="Firewalls"}; mock:fireEvent("gmcp.char."..channel)
    assert(result,tostring(err)); equal(result.company_cash,3995520); equal(result.cost,3004480)
    equal(result.depot_needed,true); equal(API.commands._lease,nil)
    mock:runTimers(); equal(buys(),1); equal(depot_buys(),1)
end)
test(rank.." depot-only backfill buys one depot, never a factory, even at eight factories",function()
    build_reset(rank); local channel=rank=="Industrialist" and "business" or "company"
    local c=mock.gmcp.char[channel]; c.depots={}
    for i=2,8 do c.factories[i]={number=i,planet="Example World",output="Firewalls"} end
    mock:fireEvent("gmcp.char."..channel)
    local p,r,e; local h=assert(API.company.prepareFactory(context,site_options(true),function(v,err) p,e=v,err end))
    build_fresh(rank,7); assert(p,tostring(e)); equal(p.cost,1004480); equal(p.slot,0)
    assert(h:confirm(function(v,err) r,e=v,err end)); build_fresh(rank,7)
    c.depots={"Example World"}; c.cash=5995520; build_fresh(rank,0)
    assert(r,tostring(e)); equal(r.confirmed,true); equal(buys(),0); equal(depot_buys(),1)
end)
end
test("site reuses a depot and refuses unknown or duplicate ownership",function()
    build_reset(); local p; assert(API.company.prepareFactory(context,site_options(),function(v) p=v end)); build_fresh()
    equal(p.cost,2000000); equal(p.depot_needed,false); equal(p.workers_required,150)
    for _,depots in ipairs({false,{"Example World","EXAMPLE WORLD"}}) do
        build_reset(); mock.gmcp.char.company.depots=depots; mock:fireEvent("gmcp.char.company")
        equal(API.company.prepareFactory(context,site_options(),function() end),nil); equal(depot_buys(),0)
    end
end)
test("eight-factory cap, depot slots, worker and total cash bounds stop before any purchase",function()
    for _,case in ipairs({"factories","depots","workers","cash","already_depot","no_factory"}) do
        build_reset(); local c=mock.gmcp.char.company; c.depots={}; local o=site_options(); local e
        if case=="factories" then for i=2,8 do c.factories[i]={number=i,planet="Example World",output="Firewalls"} end end
        if case=="depots" then for i=1,15 do c.depots[i]="Planet "..i end end
        if case=="cash" then c.cash=4004479 end
        if case=="already_depot" then c.depots={"Example World"}; o=site_options(true) end
        if case=="no_factory" then c.factories={}; o=site_options(true) end
        mock:fireEvent("gmcp.char.company")
        assert(API.company.prepareFactory(context,o,function(_,err) e=err end)); build_fresh(nil,case=="workers" and 156 or 2500)
        assert(e,case); equal(depot_buys(),0); equal(buys(),0)
    end
end)
test("partial depot outcomes never replay or advance on bad evidence or lost authority",function()
    for _,case in ipairs({"debit","missing","stock","workers","authority","cancel","timeout","price"}) do
        build_reset(); local c=mock.gmcp.char.company; c.depots={}; mock:fireEvent("gmcp.char.company")
        local o=site_options(); o.review_prices=true
        local e; local h=assert(API.company.prepareFactory(context,o,function() end)); build_fresh()
        assert(h:confirm(function(_,err) e=err end)); build_fresh(); equal(depot_buys(),1)
        c.depots=case=="missing" and {} or {"Example World"}; c.cash=case=="debit" and 5995521 or 5995520
        if case=="stock" then mock.gmcp.exchange.commodities.Semiconductors.stock=4999 end
        if case=="price" then mock.gmcp.exchange.commodities.Firewalls.buy=799 end
        if case=="authority" then API._modules[context.module_id].spec.authorize=function(op) return op~="company.factory.continue" end end
        if case=="cancel" then h:cancel("OFF") elseif case=="timeout" then mock:runTimers() else build_fresh(nil,case=="workers" and 149 or 2500) end
        equal(buys(),0); equal(depot_buys(),1); equal(h:status().uncertain,true); equal(API.commands._lease,nil)
        if case~="cancel" then code(e,"E_FACTORY_UNCONFIRMED") end
        mock:runTimers(); equal(buys(),0); equal(depot_buys(),1)
    end
end)
test("new depot appearing between preview and confirm cancels instead of silently changing the order",function()
    build_reset(); local c=mock.gmcp.char.company; c.depots={}; mock:fireEvent("gmcp.char.company")
    local e; local h=assert(API.company.prepareFactory(context,site_options(),function() end)); build_fresh()
    c.depots={"Example World"}; assert(h:confirm(function(_,err) e=err end)); build_fresh()
    assert(e); equal(buys(),0); equal(depot_buys(),0)
end)
local function auto_options()
    local o=site_options(); o.automation=true; o.wages=40; o.planet_limit=2; o.reserved_workers=150; o.review_prices=true
    return o
end
local function wage_commands()
    local n=0; for _,r in ipairs(mock.sent) do if r.command:match("^set factory ") then n=n+1 end end; return n
end
local function wage_reads()
    local n=0; for _,r in ipairs(mock.sent) do if r.command=="display factory 2" then n=n+1 end end; return n
end
local function wage_ack()
    observer("The wages for workers in factory #2 (Firewalls on Example World) have been set to 40.")
end
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test(rank.." automatic build verifies new factory then sets exactly 40 wages once",function()
    build_reset(rank); local proposal,result,err
    local h=assert(API.company.prepareFactory(context,auto_options(),function(v,e) proposal,err=v,e end)); build_fresh(rank)
    assert(proposal,tostring(err)); equal(proposal.wages,40); equal(wage_commands(),0)
    assert(h:confirm(function(v,e) result,err=v,e end)); build_fresh(rank); equal(buys(),1)
    local channel=rank=="Industrialist" and "business" or "company"; local c=mock.gmcp.char[channel]
    c.cash=5000000; c.factories[2]={number=2,planet="Example World",output="Firewalls"}
    mock:fireEvent("gmcp.char."..channel); equal(wage_commands(),1); equal(result,nil)
    equal(h:status().phase,"setting_wages"); equal(mock.sent[#mock.sent].command,"set factory 2 wages 40")
    equal(wage_reads(),0)
    wage_ack(); equal(h:status().phase,"verifying_wages"); equal(wage_reads(),1)
    equal(mock.sent[#mock.sent].command,"display factory 2")
    for _,line in ipairs(lines(fixture:gsub("Facility #1","Facility #2"))) do observer(line) end
    assert(result,tostring(err)); equal(result.wages,40); equal(result.wages_confirmed,true); equal(API.commands._lease,nil)
    equal(h:confirm(function() end),nil); equal(buys(),1); equal(wage_commands(),1)
end)
test(rank.." purchase display cannot finish wage verification before its acknowledgement",function()
    build_reset(rank); local result,err
    local h=assert(API.company.prepareFactory(context,auto_options(),function() end)); build_fresh(rank)
    assert(h:confirm(function(v,e) result,err=v,e end)); build_fresh(rank)
    local channel=rank=="Industrialist" and "business" or "company"; local c=mock.gmcp.char[channel]
    c.cash=5000000; c.factories[2]={number=2,planet="Example World",output="Firewalls"}
    mock:fireEvent("gmcp.char."..channel)
    local early=fixture:gsub("Facility #1","Facility #2"):gsub("Wages: 40ig","Wages: 0ig")
    local callback=observer
    for _,line in ipairs(lines(early)) do callback(line) end
    assert(not err,"the initial 0ig purchase display is not a failed wage verification: "..tostring(err))
    equal(result,nil); equal(h:status().active,true); equal(wage_reads(),0)
    -- Even a complete pre-ack display claiming 40 is not fresh requested evidence.
    for _,line in ipairs(lines(early:gsub("Wages: 0ig","Wages: 40ig"))) do callback(line) end
    equal(result,nil); equal(wage_reads(),0)
    wage_ack(); equal(wage_reads(),1)
    for _,line in ipairs(lines(early:gsub("Wages: 0ig","Wages: 40ig"))) do callback(line) end
    assert(result,tostring(err)); equal(result.wages_confirmed,true)
    equal(buys(),1); equal(wage_commands(),1); equal(API.commands._lease,nil)
end)
end
test("automatic two-per-planet, reserved workforce and positive-after-wages gates",function()
    for _,case in ipairs({"planet","workers","margin","input_margin","invalid_wages"}) do
        build_reset(); local o=auto_options(); local err
        if case=="planet" then mock.gmcp.char.company.factories[2]={number=2,planet="Example World",output="Firewalls"}; mock:fireEvent("gmcp.char.company") end
        if case=="margin" then mock.gmcp.exchange.commodities.Firewalls.buy=100 end
        if case=="input_margin" then mock.gmcp.exchange.commodities.Semiconductors.sell=10000 end
        if case=="invalid_wages" then o.wages=0 end
        local h,e=API.company.prepareFactory(context,o,function(_,why) err=why end)
        if h then build_fresh(nil,case=="workers" and 299 or 2500); assert(err,case) else assert(e,case) end
        equal(buys(),0); equal(depot_buys(),0); equal(wage_commands(),0)
    end
end)
test("wage failure cancellation and lost authority retain uncertain purchase without retry",function()
    for _,case in ipairs({"wrong_wage","wrong_factory","ack_timeout","timeout","cancel","authority"}) do
        build_reset(); local err,result
        local h=assert(API.company.prepareFactory(context,auto_options(),function() end)); build_fresh()
        assert(h:confirm(function(v,e) result,err=v,e end)); build_fresh()
        if case=="authority" then API._modules[context.module_id].spec.authorize=function(op) return op~="company.factory.wages" end end
        local c=mock.gmcp.char.company; c.cash=5000000; c.factories[2]={number=2,planet="Example World",output="Firewalls"}
        mock:fireEvent("gmcp.char.company")
        if case~="ack_timeout" and case~="cancel" and case~="authority" then wage_ack() end
        if case=="cancel" then h:cancel("OFF")
        elseif case=="timeout" or case=="ack_timeout" then mock:runTimers()
        elseif case~="authority" then
            local text=fixture:gsub("Facility #1","Facility #2")
            if case=="wrong_wage" then text=text:gsub("Wages: 40ig","Wages: 0ig") else text=text:gsub("Location: Example World","Location: Elsewhere") end
            for _,line in ipairs(lines(text)) do if observer then observer(line) end end
        end
        equal(result,nil); equal(h:status().uncertain,true); equal(API.commands._lease,nil); equal(buys(),1)
        if case~="cancel" then code(err,"E_FACTORY_UNCONFIRMED") end
        equal(h:confirm(function() end),nil); mock:runTimers(); equal(buys(),1); equal(wage_commands(),case=="authority" and 0 or 1)
    end
end)
local function pending_wages(rank,with_depot)
    build_reset(rank)
    local channel=rank=="Industrialist" and "business" or "company"
    local c=mock.gmcp.char[channel]
    if with_depot then c.depots={}; mock:fireEvent("gmcp.char."..channel) end
    local completed={}
    local h=assert(API.company.prepareFactory(context,auto_options(),function() end)); build_fresh(rank)
    assert(h:confirm(function(v,e) completed.value,completed.error=v,e end)); build_fresh(rank)
    if with_depot then c.depots={"Example World"}; c.cash=5995520; build_fresh(rank) end
    c.cash=with_depot and 3995520 or 5000000
    c.factories[2]={number=2,planet="Example World",output="Firewalls"}
    mock:fireEvent("gmcp.char."..channel)
    equal(h:status().phase,"setting_wages"); equal(wage_commands(),1); equal(wage_reads(),0)
    return h,completed,c
end
test("only exact bounded wage acknowledgement unlocks the requested display",function()
    local h,done=pending_wages()
    local ack="The wages for workers in factory #2 (Firewalls on Example World) have been set to 40."
    for _,wrong in ipairs({ack:gsub("#2","#3"),ack:gsub("Firewalls","Droids"),
        ack:gsub("Example World","Elsewhere"),ack:gsub("40%.","41."),"Someone says: "..ack,
        ack.." extra text"}) do observer(wrong); equal(wage_reads(),0) end
    observer("The wages for workers in factory #2")
    for _=1,9 do observer("malformed acknowledgement continuation") end
    observer("The wages"..string.rep("x",1100)); equal(wage_reads(),0)
    -- Client wrapping and color sequences are allowed without widening identity.
    observer("\27[32mThe wages for workers in factory #2 (Firewalls on\27[0m")
    observer("Example World) have been set to 40.")
    equal(h:status().phase,"verifying_wages"); equal(wage_reads(),1); equal(done.value,nil)
    wage_ack(); wage_ack(); equal(wage_reads(),1)
    local callback=observer
    for _,line in ipairs(lines(fixture:gsub("Facility #1","Facility #2"))) do callback(line) end
    assert(done.value,tostring(done.error)); equal(done.value.wages_confirmed,true)
    callback(ack); equal(wage_reads(),1); equal(wage_commands(),1)
end)
test("missing or partial acknowledgement times out without display or replay",function()
    local h,done=pending_wages(); local late=observer
    late("The wages for workers in factory #2 (Firewalls on")
    mock:runTimers()
    code(done.error,"E_FACTORY_UNCONFIRMED"); assert(tostring(done.error):find("acknowledgement timed out",1,true))
    equal(done.value,nil); equal(h:status().uncertain,true); equal(API.commands._lease,nil)
    late("Example World) have been set to 40.")
    late("The wages for workers in factory #2 (Firewalls on Example World) have been set to 40.")
    equal(wage_reads(),0); equal(wage_commands(),1); equal(buys(),1)
end)
test("cancellation and module teardown reject late wage acknowledgements and displays",function()
    for _,acknowledged in ipairs({false,true}) do for _,how in ipairs({"cancel","disable"}) do
        local h,done=pending_wages(); local late=observer
        if acknowledged then wage_ack() end
        local sends=#mock.sent
        if how=="cancel" then h:cancel("user stopped") else API.modules.disable(context.module_id) end
        late("The wages for workers in factory #2 (Firewalls on Example World) have been set to 40.")
        for _,line in ipairs(lines(fixture:gsub("Facility #1","Facility #2"))) do late(line) end
        mock:runTimers(); equal(#mock.sent,sends); equal(done.value,nil)
        equal(h:status().uncertain,true); equal(API.commands._lease,nil)
    end end
end)
test("acknowledged identity changes and rejected verification sends stop without replay",function()
    for _,how in ipairs({"identity","send"}) do
        local h,done,c=pending_wages()
        if how=="identity" then c.factories[2].planet="Elsewhere"; mock:fireEvent("gmcp.char.company")
        else local original=adapter.sendCommand
            adapter.sendCommand=function(command,options)
                if command=="display factory 2" then return false,"verification send denied" end
                return original(command,options)
            end
        end
        wage_ack(); code(done.error,"E_FACTORY_UNCONFIRMED"); equal(done.value,nil)
        equal(h:status().uncertain,true); equal(API.commands._lease,nil)
        equal(wage_commands(),1); equal(buys(),1)
    end
end)
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test(rank.." depot plus factory automatic display is fenced before verified 40ig completion",function()
    local h,done=pending_wages(rank,true)
    local display=fixture:gsub("Facility #1","Facility #2")
    for _,line in ipairs(lines(display:gsub("Wages: 40ig","Wages: 0ig"))) do observer(line) end
    equal(done.error,nil); equal(wage_reads(),0); equal(depot_buys(),1)
    wage_ack()
    for _,line in ipairs(lines(display)) do observer(line) end
    assert(done.value,tostring(done.error)); equal(done.value.company_cash,3995520)
    equal(done.value.cost,3004480); equal(done.value.wages_confirmed,true)
    equal(h:status().phase,"confirmed"); equal(depot_buys(),1); equal(buys(),1); equal(wage_commands(),1)
    equal(h:status().active,false); equal(h:status().uncertain,false)
    assert(h:cancel("late consumer cleanup")); mock:runTimers()
    equal(h:status().phase,"confirmed"); equal(h:status().uncertain,false)
    equal(depot_buys(),1); equal(buys(),1); equal(wage_commands(),1)
end)
end
local planet_fixture=[[Example World, Example system, Test cartel, Test syndicate
  Owner: Magnate Example
  Economy: Leisure    Workers available: 2500/2500
  Shipyard markup: -10%
  Approval rating: +50
]]
local competing="\nCommercial Activities:\n  No warehouses\n  Factories:\n    Foreign Holdings #7 plant producing firewalls\n"
test("public planet parser reads ALL companies, wrapped rows and a complete empty list",function()
    local r=assert(API.company._parsePlanet(planet_fixture,"Example World","Example"))
    equal(r.planets["example world"].factories_verified,true); equal(#r.planets["example world"].factories,0)
    r=assert(API.company._parsePlanet(planet_fixture..competing.."    Another\n    Company #1 plant producing Droids\n","Example World","Example"))
    local fs=r.planets["example world"].factories; equal(#fs,2)
    equal(fs[1].owner,"Foreign Holdings"); equal(fs[1].output,"firewalls"); equal(fs[2].owner,"Another Company")
    equal(API.company._parsePlanet(planet_fixture,"Elsewhere","Example"),nil)
    equal(API.company._parsePlanet(planet_fixture,"Example World","Elsewhere"),nil)
end)
test("public factory absence is never inferred from malformed or partial records",function()
    for _,body in ipairs({planet_fixture:gsub("Approval rating:","Missing:"),
        planet_fixture:gsub("Workers available:","Missing:"),planet_fixture..competing..competing,
        planet_fixture..competing.."    Foreign Holdings #7 plant producing Firewalls\n",
        planet_fixture.."\nCommercial Activities:\n  Factories:\n",
        planet_fixture.."\n    Foreign Holdings #7 plant producing Firewalls\n",
        planet_fixture..competing:gsub("producing firewalls","producing")}) do
        equal(API.company._parsePlanet(body,"Example World","Example"),nil)
    end
end)
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test(rank.." public planet read requires the complete text AND owned company fence",function()
    build_reset(rank); local result,err
    local h=assert(API.company.planet(context,"Example World","Example",function(v,e) result,err=v,e end))
    equal(mock.sent[#mock.sent-1].command,"di planet Example World")
    mock:fireEvent("gmcp.char."..(rank=="Industrialist" and "business" or "company"))
    observer(planet_fixture..competing); equal(result,nil); assert(API.commands._lease)
    observer(rank=="Industrialist" and "Sample Ltd registered business - CEO Industrialist TestOwner" or "Company Report for Sample Ltd:")
    assert(result,tostring(err)); equal(#result.planets["example world"].factories,1)
    equal(h:status().active,false); equal(API.commands._lease,nil)
end)
test(rank.." all-company duplicate commodity blocks preview and fresh pre-purchase validation",function()
    for _,stage in ipairs({"preview","confirm","after_depot","owned_roster"}) do
        build_reset(rank); local o=site_options(); o.exclude_existing_commodity=true
        local c=mock.gmcp.char[rank=="Industrialist" and "business" or "company"]
        if stage=="after_depot" then c.depots={} end
        if stage=="owned_roster" then c.factories[1].output="FIREWALLS" end
        mock:fireEvent("gmcp.char."..(rank=="Industrialist" and "business" or "company"))
        local result,err
        local h=assert(API.company.prepareFactory(context,o,function(v,e) result,err=v,e end))
        build_fresh(rank,nil,nil,stage=="preview" and competing or nil)
        if stage=="confirm" or stage=="after_depot" then
            assert(result,tostring(err)); result=nil
            assert(h:confirm(function(v,e) result,err=v,e end))
            build_fresh(rank,nil,nil,stage=="confirm" and competing or nil)
            if stage=="after_depot" then
                equal(depot_buys(),1); c.depots={"Example World"}; c.cash=5995520
                build_fresh(rank,nil,nil,competing)
            end
        end
        assert(err,stage); assert(tostring(err):find("already has a Firewalls factory",1,true),tostring(err))
        equal(result,nil); equal(buys(),0); equal(depot_buys(),stage=="after_depot" and 1 or 0)
        equal(wage_commands(),0); equal(API.commands._lease,nil)
        equal(h:status().uncertain,stage=="after_depot"); mock:runTimers(); equal(buys(),0)
    end
end)
end
test("public planet timeout cancellation and late responses never mean no competition",function()
    build_reset()
    local invalid,why=API.company.planet(context,nil,"Example",function() end)
    equal(invalid,nil); code(why,"E_ARGUMENT"); equal(#mock.sent,0)
    invalid,why=API.company.planet(context,"Example;quit","Example",function() end)
    equal(invalid,nil); code(why,"E_ARGUMENT"); equal(#mock.sent,0)
    for _,how in ipairs({"timeout","cancel","disable","identity"}) do
        build_reset(); local result,err
        local h=assert(API.company.planet(context,"Example World","Example",function(v,e) result,err=v,e end))
        local late=observer
        if how=="cancel" then h:cancel() elseif how=="disable" then API.modules.disable(context.module_id)
        elseif how=="identity" then mock.gmcp.char.vitals.name="Another"; mock:fireEvent("gmcp.char.vitals"); mock:fireEvent("gmcp.char.company")
        else late(planet_fixture); mock:runTimers() end
        equal(result,nil); equal(API.commands._lease,nil)
        if how=="timeout" or how=="identity" then assert(err) end
        late(planet_fixture); late("Company Report for Sample Ltd:"); equal(result,nil)
    end
end)
test("a different existing commodity permits one new factory, never a duplicate",function()
    build_reset(); local o=auto_options(); local result,err
    local h=assert(API.company.prepareFactory(context,o,function(v,e) result,err=v,e end))
    local different=competing:gsub("firewalls","Droids")
    build_fresh(nil,nil,nil,different); assert(result,tostring(err))
    assert(h:confirm(function(v,e) result,err=v,e end)); build_fresh(nil,nil,nil,different)
    equal(buys(),1); h:cancel("test complete"); equal(API.commands._lease,nil)
end)
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test(rank.." 100 planning planets share one final report without bursting commands",function()
    build_reset(rank); local result,err; local targets={}
    for i=1,100 do targets[i]={planet="World "..i,system="Example"} end
    local h=assert(API.company.planets(context,targets,function(v,e) result,err=v,e end))
    equal(#mock.sent,1); equal(mock.sent[1].command,"di planet World 1")
    local channel=rank=="Industrialist" and "business" or "company"
    -- Earlier GMCP must not count as the final ordered fence.
    mock:fireEvent("gmcp.char."..channel)
    for i=1,100 do
        observer(planet_fixture:gsub("Example World","World "..i)..(i==50 and competing or ""))
        equal(#mock.sent,i+1); equal(result,nil)
        if i<100 then equal(mock.sent[#mock.sent].command,"di planet World "..(i+1)) end
    end
    equal(mock.sent[101].command,rank=="Industrialist" and "di business" or "di company")
    observer(rank=="Industrialist" and "Sample Ltd registered business - CEO Industrialist TestOwner" or "Company Report for Sample Ltd:")
    equal(result,nil); assert(API.commands._lease)
    mock:fireEvent("gmcp.char."..channel)
    assert(result,tostring(err)); equal(#result.reports,100)
    equal(#result.reports[50].planets["world 50"].factories,1)
    equal(#result.reports[51].planets["world 51"].factories,0)
    equal(h:status().active,false); equal(API.commands._lease,nil)
    mock:runTimers(); equal(#mock.sent,101)
end)
test(rank.." batch final GMCP can precede text but never replaces the text fence",function()
    build_reset(rank); local result,err
    local h=assert(API.company.planets(context,{{planet="Example World",system="Example"}},function(v,e) result,err=v,e end))
    observer(planet_fixture)
    mock:fireEvent("gmcp.char."..(rank=="Industrialist" and "business" or "company"))
    equal(result,nil)
    observer(rank=="Industrialist" and "Sample Ltd registered business - CEO Industrialist TestOwner" or "Company Report for Sample Ltd:")
    assert(result,tostring(err)); equal(#result.reports,1); equal(h:status().active,false)
end)
end
test("planet batch rejects invalid duplicate and oversized target lists before sending",function()
    for _,targets in ipairs({{},{{planet="bad;quit",system="Example"}},
        {{planet="A",system="One"},{planet="a",system="Two"}}}) do
        build_reset(); local h,e=API.company.planets(context,targets,function() end)
        equal(h,nil); code(e,"E_ARGUMENT"); equal(#mock.sent,0)
    end
    build_reset(); local targets={}; for i=1,101 do targets[i]={planet="World "..i,system="Example"} end
    local h,e=API.company.planets(context,targets,function() end)
    equal(h,nil); code(e,"E_ARGUMENT"); equal(#mock.sent,0)
end)
test("incomplete or out-of-order batch reports never imply an empty public factory list",function()
    for _,how in ipairs({"truncated","out_of_order","early_fence"}) do
        build_reset(); local result,err
        local h=assert(API.company.planets(context,{{planet="Example World",system="Example"},
            {planet="Next",system="Example"}},function(v,e) result,err=v,e end))
        observer(how=="truncated" and planet_fixture:gsub("Approval rating:","Missing:") or planet_fixture)
        if how=="out_of_order" then observer(planet_fixture:gsub("Example World","Unexpected")) end
        if how~="early_fence" then observer(planet_fixture:gsub("Example World","Next")) end
        if observer then observer("Company Report for Sample Ltd:") end
        mock:fireEvent("gmcp.char.company")
        assert(err); equal(result,nil); equal(h:status().active,false); equal(API.commands._lease,nil)
        equal(buys(),0)
    end
end)
test("batch timeout stop identity change and disabled authority cancel the command chain",function()
    for _,how in ipairs({"timeout","cancel","disable","identity"}) do
        build_reset(); local result,err
        local h=assert(API.company.planets(context,{{planet="Example World",system="Example"},
            {planet="Next",system="Example"}},function(v,e) result,err=v,e end))
        local late=observer
        if how=="cancel" then h:cancel()
        elseif how=="disable" then API.modules.disable(context.module_id)
        elseif how=="identity" then mock.gmcp.char.vitals.name="Another"; mock:fireEvent("gmcp.char.vitals"); late(planet_fixture)
        else mock:runTimers() end
        equal(result,nil); equal(API.commands._lease,nil); equal(h:status().active,false)
        late(planet_fixture); late("Company Report for Sample Ltd:"); mock:fireEvent("gmcp.char.company")
        equal(#mock.sent,1); equal(result,nil)
    end
end)
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test(rank.." TQuarks can follow foreign NanoFabrics or one verified owned TQuarks",function()
    for _,own in ipairs({false,true}) do
        build_reset(rank); local channel=rank=="Industrialist" and "business" or "company"
        local c=mock.gmcp.char[channel]; c.factories=own and {{number=1,planet="Example World",output="TQuarks"}} or {}
        mock:fireEvent("gmcp.char."..channel)
        mock.gmcp.exchange.commodities={TQuarks={buy=900},Lasers={stock=6000,sell=100},Droids={stock=6000,sell=100}}
        local o=auto_options(); o.commodity="TQuarks"; o.labour=30; o.reserved_workers=own and 30 or 0
        o.exclude_existing_commodity=true; o.allow_owned_commodity=true
        o.inputs={{commodity="Lasers",required=20,minimum_stock=5000,price_limit=100},
            {commodity="Droids",required=20,minimum_stock=5000,price_limit=100}}
        local commercial="\nCommercial Activities:\n  Factories:\n    "..(own and "sAmPlE lTd #1 plant producing tQuArKs" or "Foreign Holdings #1 plant producing NanoFabrics").."\n"
        local result,err
        local h=assert(API.company.prepareFactory(context,o,function(v,e) result,err=v,e end))
        build_fresh(rank,own and 60 or 30,nil,commercial); assert(result,tostring(err))
        equal(result.workers_required,own and 60 or 30); equal(buys(),0)
        assert(h:confirm(function(v,e) result,err=v,e end)); build_fresh(rank,own and 60 or 30,nil,commercial)
        equal(buys(),1)
        local command; for _,sent in ipairs(mock.sent) do if sent.command:match("^buy factory ") then command=sent.command end end
        equal(command,"buy factory TQuarks")
        h:cancel("synthetic purchase boundary checked")
    end
end)
test(rank.." owned-commodity permission never bypasses competition, cap or fresh resource checks",function()
    for _,how in ipairs({"foreign","third","workers","stock","bid","wrong_slot","missing_public","confirm_competitor"}) do
        build_reset(rank); local channel=rank=="Industrialist" and "business" or "company"
        local c=mock.gmcp.char[channel]; c.factories={{number=1,planet="Example World",output="Firewalls"}}
        if how=="third" then c.factories[2]={number=2,planet="Example World",output="Firewalls"} end
        mock:fireEvent("gmcp.char."..channel)
        local o=auto_options(); o.allow_owned_commodity=true; o.exclude_existing_commodity=true
        local commercial="\nCommercial Activities:\n  Factories:\n    Sample Ltd #1 plant producing Firewalls\n"
        if how=="foreign" then commercial=commercial.."    Foreign Holdings #1 plant producing Firewalls\n"
        elseif how=="stock" then mock.gmcp.exchange.commodities.Semiconductors.stock=4999
        elseif how=="bid" then mock.gmcp.exchange.commodities.Firewalls.buy=nil
        elseif how=="wrong_slot" then commercial=commercial:gsub("#1","#7")
        elseif how=="missing_public" then commercial="" end
        local result,err
        local h=assert(API.company.prepareFactory(context,o,function(v,e) result,err=v,e end))
        build_fresh(rank,how=="workers" and 299 or 2500,nil,commercial)
        if how=="confirm_competitor" then
            assert(result,tostring(err)); result=nil
            assert(h:confirm(function(v,e) result,err=v,e end))
            build_fresh(rank,nil,nil,commercial.."    Foreign Holdings #2 plant producing Firewalls\n")
        end
        assert(err,how); equal(result,nil); equal(buys(),0); equal(API.commands._lease,nil)
    end
end)
end

test("owned-commodity exemption requires explicit exclusion policy and a boolean",function()
    for _,value in ipairs({true,"yes",2}) do
        build_reset(); local o=site_options(); o.allow_owned_commodity=value
        local h,err=API.company.prepareFactory(context,o,function() end)
        equal(h,nil); code(err,"E_ARGUMENT"); equal(#mock.sent,0)
    end
end)
print(string.format("RESULT %d passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end
