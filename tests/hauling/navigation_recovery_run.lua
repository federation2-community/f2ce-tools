-- Real exchange phases, recovery worker and lifecycle; synthetic transport only.
local root=arg[1] or "."
local sent,timers,handlers,routes,queries,output,price_reply,nav_mode,deferred
local passed,failed=0,0
local function eq(a,b) assert(a==b,"expected "..tostring(b)..", got "..tostring(a)) end
local function test(name,fn)
    local ok,why=pcall(fn)
    if ok then passed=passed+1; print("PASS "..name) else failed=failed+1; print("FAIL "..name..": "..tostring(why)) end
end
function cecho(s) output[#output+1]=s end
function f2t_debug_log() end
function tempTimer(delay,fn) local id={delay=delay,fn=fn}; timers[id]=true; return id end
function killTimer(id) timers[id]=nil end
function registerAnonymousEventHandler(event,fn) local id={event=event,fn=fn}; handlers[id]=true; return id end
function killAnonymousEventHandler(id) handlers[id]=nil end
function send(s) sent[#sent+1]=s end
function f2t_map_brief_hold_release() end
function f2t_map_brief_hold_acquire() end
function f2t_map_set_nav_owner() end
function f2t_map_speedwalk_stop() F2T_SPEEDWALK_ACTIVE=false; F2T_SPEEDWALK_LAST_RESULT="stopped" end
function f2t_map_navigate_ok(s) return s=="walking" or s=="arrived" end
function f2t_has_value(t,v) for _,value in pairs(t) do if value==v then return true end end; return false end
local function event(name)
    local ids={}; for id in pairs(handlers) do if id.event==name then ids[#ids+1]=id end end
    for _,id in ipairs(ids) do if handlers[id] then id.fn(name) end end
end
raiseEvent=event
local function run(delay)
    local ids={}; for id in pairs(timers) do if id.delay==delay then ids[#ids+1]=id end end
    for _,id in ipairs(ids) do if timers[id] then timers[id]=nil; id.fn() end end
end
local function row(planet,price) return {planet=planet,system="System",price=price,quantity=10000} end
local function prices()
    local a={top_buy={row("Origin",999),row("Buyer A",900),row("Buyer B",10),row("Buyer C",5)},top_sell={row("Seller A",1),row("Seller B",2)},profit=899}
    return {buy=a.top_buy,sell=a.top_sell},a
end
local function reset(side,loaded)
    if f2t_hauling_navigation_recovery_cancel then f2t_hauling_navigation_recovery_cancel(true) end
    sent,timers,handlers,routes,output={},{},{},{},{}
    queries,price_reply,nav_mode,deferred=0,nil,"failed",false
    F2T_SPEEDWALK_ACTIVE,F2T_SPEEDWALK_WAITING_FOR_MOVE,F2T_SPEEDWALK_CUSTOMS_PENDING=false,false,false
    F2T_SPEEDWALK_LAST_RESULT,F2T_SPEEDWALK_PAUSED_FOR_DISCONNECT=nil,false
    F2T_MAP_EXPLORE_STATE,F2T_MAP_CIRCUIT_STATE,F2T_BULK_STATE=nil,nil,{active=false}
    F2T_DEATH_STATE,F2T_STAMINA_STATE=nil,nil
    f2t_map_brief_hold_release=function() end
    f2t_map_brief_hold_acquire=function() end
    f2t_map_speedwalk_stop=function() F2T_SPEEDWALK_ACTIVE=false; F2T_SPEEDWALK_LAST_RESULT="stopped" end
    f2t_hauling_teleport_busy,f2t_hauling_teleport_uncertain=nil,nil
    f2t_hauling_teleport_try,f2t_hauling_teleport_cancel=nil,nil
    f2t_hauling_customs_system_blocked=nil
    gmcp={char={vitals={name="Test Pilot"},ship={cargo={},hold={max=225,cur=225}}},room={info={num=1,area="Origin",system="System",flags={}}}}
    if loaded then
        gmcp.char.ship.cargo={{commodity="Woods",cost=100,origin="Origin"},{commodity="Woods",cost=100,origin="Origin"}}
        gmcp.char.ship.hold.cur=75
    end
    F2T_HAULING_STATE={active=true,paused=false,mode="exchange",rotation="top_base_21",current_commodity="Woods",
        current_phase="navigating_to_"..side,buy_location=row("Seller A",1),sell_location=row("Buyer A",900),
        margin_threshold_pct=0,current_commodity_stats={lots_bought=loaded and 2 or 0,lots_sold=0,total_cost=loaded and 15000 or 0,total_revenue=0},
        exchange_market={commodity="Woods",buy={row("Seller A",1),row("Seller B",2)},sell={row("Buyer A",900)},rejected={buy={},sell={}}}}
    dofile(root.."/src/scripts/hauling/state_machine.lua")
    dofile(root.."/src/scripts/hauling/exchange_recovery.lua")
    dofile(root.."/src/scripts/hauling/exchange_navigation_recovery.lua")
    dofile(root.."/src/scripts/hauling/exchange_phases.lua")
    f2t_hauling_do_stop=function()
        f2t_hauling_navigation_recovery_cancel(true); F2T_HAULING_STATE.active=false
        F2T_HAULING_STATE.exchange_market=nil; F2T_HAULING_STATE.exchange_route=nil
    end
    f2t_map_navigate=function(destination,opts)
        local status=nav_mode; routes[#routes+1]={destination=destination,opts=opts}
        if status=="walking" then F2T_SPEEDWALK_ACTIVE=true end
        tempTimer(0,function() opts.on_result(status~="failed",status) end)
        return status
    end
    f2t_price_check_commodity=function(commodity,cb)
        eq(commodity,"Woods"); queries=queries+1; price_reply=cb
        if not deferred then local p,a=prices(); cb(commodity,p,a) end
    end
    f2t_exchange_register_handlers()
end
local function start(side)
    if side=="sell" then f2t_hauling_phase_navigate_to_sell() else f2t_hauling_phase_navigate_to_buy() end
    run(0); run(0.25)
end
local function fresh_ship() nav_mode="walking"; event("gmcp.char.ship") end
test("failed buyer route waits for fresh hold then fresh prices and routes off-world below purchase cost",function()
    reset("sell",true); start("sell"); eq(#sent,1); eq(sent[1],"status"); eq(queries,0); eq(#routes,1)
    fresh_ship(); eq(queries,1); eq(#routes,2); eq(routes[2].destination,"Buyer B exchange")
    eq(#sent,1); eq(#gmcp.char.ship.cargo,2); eq(F2T_HAULING_STATE.current_commodity_stats.total_cost,15000)
end)
test("cargo found on failed seller leg chooses a buyer, never another bulk buy",function()
    reset("buy",true); start("buy"); fresh_ship(); eq(queries,1); eq(routes[2].destination,"Buyer A exchange"); eq(#sent,1)
end)
test("empty seller failure advances supplier without a buyer scan",function()
    reset("buy",false); start("buy"); fresh_ship(); eq(queries,0); eq(routes[2].destination,"Seller B exchange"); eq(#sent,1)
end)
test("each failed buyer is excluded even when the fresh scan still ranks it first",function()
    reset("sell",true); start("sell"); fresh_ship(); run(0)
    F2T_SPEEDWALK_ACTIVE=false; F2T_SPEEDWALK_LAST_RESULT="failed"; event("f2tMapNavigationStateChanged"); run(0.25)
    eq(sent[2],"status"); fresh_ship(); eq(queries,2); eq(routes[3].destination,"Buyer C exchange")
end)
test("real speedwalk timeout emits a terminal event and recovers without room GMCP",function()
    reset("sell",true); dofile(root.."/src/scripts/map/speedwalk.lua"); nav_mode="walking"
    start("sell"); eq(queries,0); f2t_map_speedwalk_fail("blocked fixture"); run(0); run(0.25)
    eq(sent[1],"status"); fresh_ship(); eq(routes[2].destination,"Buyer B exchange")
end)
test("missing fresh ship receipt pauses after eight seconds without another route",function()
    reset("sell",true); start("sell"); run(8); eq(F2T_HAULING_STATE.paused,true); eq(queries,0); eq(#routes,1)
    event("gmcp.char.ship"); eq(queries,0)
end)
test("inconsistent, foreign, missing and unexpected cargo never authorizes recovery",function()
    for _,kind in ipairs({"hold","commodity","missing","ledger","origin","empty"}) do
        reset("sell",true); start("sell")
        if kind=="hold" then gmcp.char.ship.hold.cur=225
        elseif kind=="commodity" then gmcp.char.ship.cargo[1].commodity="Gold"
        elseif kind=="missing" then gmcp.char.ship.cargo=nil
        elseif kind=="ledger" then F2T_HAULING_STATE.current_commodity_stats.lots_bought=1
        elseif kind=="origin" then gmcp.char.ship.cargo[1].origin=nil
        else gmcp.char.ship.cargo={}; gmcp.char.ship.hold.cur=225 end
        fresh_ship(); eq(F2T_HAULING_STATE.paused,true); eq(queries,0); eq(#routes,1)
    end
end)
test("manual pause stop terminate and disconnect revoke pending recovery",function()
    for _,action in ipairs({"pause","stop","terminate","disconnect"}) do
        reset("sell",true); start("sell")
        if action=="pause" then f2t_hauling_pause()
        elseif action=="stop" then f2t_hauling_stop()
        elseif action=="terminate" then f2t_hauling_terminate()
        else event("sysDisconnectionEvent") end
        fresh_ship(); run(8); eq(queries,0); eq(#routes,1)
    end
end)
test("protection or unfinished trade blocks automatic recovery",function()
    for _,kind in ipairs({"death","stamina","bulk","purchase","teleport"}) do
        reset("sell",true)
        if kind=="death" then F2T_DEATH_STATE={active=true}
        elseif kind=="stamina" then F2T_STAMINA_STATE={current_phase="eating"}
        elseif kind=="bulk" then F2T_BULK_STATE.active=true
        elseif kind=="purchase" then F2T_HAULING_STATE.purchase_settlement={}
        else f2t_hauling_teleport_uncertain=function() return true end end
        start("sell"); eq(F2T_HAULING_STATE.paused,true); eq(#sent,0); eq(queries,0)
    end
end)
test("changed cargo while prices are pending pauses without selecting a buyer",function()
    reset("sell",true); deferred=true; start("sell"); fresh_ship(); eq(queries,1)
    gmcp.char.ship.cargo[1].cost=101
    local p,a=prices(); price_reply("Woods",p,a); eq(#routes,1); eq(F2T_HAULING_STATE.paused,true)
end)
test("late price response after stop cannot navigate or restart",function()
    reset("sell",true); deferred=true; start("sell"); fresh_ship(); f2t_hauling_stop()
    local p,a=prices(); price_reply("Woods",p,a); eq(#routes,1); eq(F2T_HAULING_STATE.active,false)
end)
test("stale route callbacks cannot interrupt a newer buyer route",function()
    reset("sell",true); start("sell"); local old=routes[1].opts.on_result; fresh_ship()
    old(false,"failed"); run(0.25); eq(#sent,1); eq(#routes,2); eq(F2T_HAULING_STATE.current_phase,"navigating_to_sell")
end)
test("ordinary nonpremium hauling retains its explicit pause behavior",function()
    reset("sell",true); F2T_HAULING_STATE.rotation=nil; start("sell")
    eq(F2T_HAULING_STATE.paused,true); eq(#sent,0); eq(queries,0)
end)
test("explicit resume after ship timeout starts a new fresh cargo check",function()
    reset("sell",true); start("sell"); run(8); f2t_hauling_resume(); run(0.25)
    eq(#sent,2); fresh_ship(); eq(queries,1); eq(#routes,2)
end)
test("navigation ownership must settle before status; an unending operation pauses",function()
    reset("sell",true); F2T_MAP_EXPLORE_STATE={active=true}; start("sell"); eq(#sent,0)
    for _=1,40 do run(0.25) end
    eq(F2T_HAULING_STATE.paused,true); eq(#sent,0); eq(queries,0)
end)
test("changed identity or missing room during recovery pauses instead of silently stalling",function()
    for _,stage in ipairs({"before_status","ship","timeout","room"}) do
        reset("sell",true)
        f2t_hauling_phase_navigate_to_sell(); run(0)
        if stage~="before_status" then run(0.25) end
        if stage=="room" then gmcp.room.info=nil else gmcp.char.vitals.name="Other Pilot" end
        if stage=="before_status" then run(0.25)
        elseif stage=="timeout" then run(8) else fresh_ship() end
        eq(F2T_HAULING_STATE.paused,true); eq(queries,0)
    end
end)
test("disconnect during buyer refresh revokes the late response",function()
    reset("sell",true); deferred=true; start("sell"); fresh_ship(); event("sysDisconnectionEvent")
    local p,a=prices(); price_reply("Woods",p,a)
    eq(F2T_HAULING_STATE.paused,true); eq(#routes,1); eq(#sent,1)
end)
test("no eligible buyer stops with cargo preserved without retrying the failed exchange",function()
    reset("sell",true); deferred=true; start("sell"); fresh_ship()
    local rows={row("Origin",999),row("Buyer A",900)}
    price_reply("Woods",{buy=rows,sell={}},{top_buy=rows,top_sell={}})
    eq(F2T_HAULING_STATE.active,false); eq(#routes,1); eq(#gmcp.char.ship.cargo,2); eq(queries,1)
end)
test("fresh buyer selection continues to honor the customs blacklist",function()
    reset("sell",true); deferred=true; start("sell"); fresh_ship()
    f2t_hauling_customs_system_blocked=function(system) return system=="Blocked" end
    local p,a=prices(); p.buy[3].system="Blocked"; price_reply("Woods",p,a)
    eq(routes[2].destination,"Buyer C exchange")
end)
test("recovery resume does not restart a stale paused speedwalk",function()
    reset("sell",true); start("sell"); F2T_SPEEDWALK_ACTIVE=true; F2T_SPEEDWALK_DESTINATION_ROOM_ID=999
    fresh_ship(); eq(F2T_HAULING_STATE.paused,true); eq(F2T_HAULING_STATE.paused_speedwalk_destination,nil)
    f2t_hauling_resume(); run(0.25); eq(#sent,2); eq(#routes,1)
end)
test("pending navigation ignores an earlier failure and can settle already-arrived once",function()
    for _,side in ipairs({"buy","sell"}) do
        reset(side,side=="sell"); F2T_SPEEDWALK_LAST_RESULT="failed"
        f2t_map_navigate=function(destination,opts) routes[#routes+1]={opts=opts}; return "pending" end
        start(side); event("f2tMapNavigationStateChanged"); eq(#sent,0)
        local transitions=0
        f2t_hauling_transition=function(phase)
            eq(phase,side=="sell" and "selling" or "buying"); transitions=transitions+1
            F2T_HAULING_STATE.current_phase=phase
        end
        routes[1].opts.on_result(true,"arrived"); run(0.5); eq(transitions,1); eq(#sent,0)
        routes[1].opts.on_result(true,"arrived"); run(0.5); eq(transitions,1)
    end
end)
test("old cargo-check timeout cannot cancel a new recovery after explicit resume",function()
    reset("sell",true); start("sell")
    local old; for id in pairs(timers) do if id.delay==8 then old=id.fn end end
    f2t_hauling_pause(); f2t_hauling_resume(); run(0.25); old(); fresh_ship()
    eq(#sent,2); eq(queries,1); eq(#routes,2); eq(F2T_HAULING_STATE.paused,false)
end)
test("old already-arrived timer cannot advance a replaced route",function()
    reset("sell",true); nav_mode="arrived"; start("sell")
    local old; for id in pairs(timers) do if id.delay==0.5 then old=id.fn end end
    F2T_HAULING_STATE.sell_location=row("Buyer B",10); nav_mode="walking"; f2t_hauling_phase_navigate_to_sell()
    old(); eq(F2T_HAULING_STATE.current_phase,"navigating_to_sell"); eq(#sent,0)
end)
print(string.format("RESULT %d passed, %d failed",passed,failed)); if failed>0 then os.exit(1) end
