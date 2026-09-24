-- Real seller phases/resolver/teleport worker with deterministic Mudlet events.
local root = arg[1] or "."
local timers, handlers, triggers, sent, nav, transitions, output, mapped, hash, locked, paused, skipped, buys
local passed, failed, clock = 0, 0, 1000
os.time = function() return clock end
local function eq(a,b,n) if a~=b then error((n or "value")..": "..tostring(a).." ~= "..tostring(b),2) end end
local function ok(v,n) if not v then error(n or "assertion",2) end end
local function test(name,fn)
    local success,err=pcall(fn)
    if success then passed=passed+1; print("PASS "..name)
    else failed=failed+1; print("FAIL "..name..": "..tostring(err)) end
end
function f2t_debug_log() end
function cecho(text) output[#output+1]=text end
function send(text) sent[#sent+1]=text end
function tempTimer(delay,fn) local id={delay=delay,fn=fn}; timers[id]=true; return id end
function killTimer(id) timers[id]=nil end
function registerAnonymousEventHandler(event,fn) local id={event=event,fn=fn}; handlers[id]=true; return id end
function killAnonymousEventHandler(id) handlers[id]=nil end
function tempRegexTrigger(_,fn) local id={fn=fn}; triggers[id]=true; return id end
function killTrigger(id) triggers[id]=nil end
function f2t_map_resolve_location() return mapped and 5702 or nil end
function f2t_map_room_has_flag() return true end
function getRoomHashByID() return hash end
function getRoomUserData(_,key) return ({fed2_system="Sol",fed2_area="The Lattice",fed2_num="1637"})[key] end
function roomLocked() return locked end
local normal_navigate=function(destination) nav[#nav+1]=destination; F2T_SPEEDWALK_ACTIVE=true; return "walking" end
f2t_map_navigate=normal_navigate
function f2t_map_navigate_ok(value) return value=="walking" or value=="arrived" end
function f2t_hauling_pause()
    paused=paused+1; F2T_HAULING_STATE.paused=true; f2t_hauling_teleport_cancel()
end
function f2t_hauling_transition(phase) transitions[#transitions+1]=phase; F2T_HAULING_STATE.current_phase=phase end
function f2t_bulk_buy_start() buys=buys+1 end
local function dispatch(items,filter)
    local copy={}; for id in pairs(items) do copy[#copy+1]=id end
    for _,id in ipairs(copy) do if items[id] and filter(id) then id.fn() end end
end
local function event(name) dispatch(handlers,function(id) return id.event==name end) end
local function text(value) line=value; dispatch(triggers,function() return true end) end
local function timeout(delay)
    local count=0
    dispatch(timers,function(id) if id.delay==delay then timers[id]=nil; count=count+1; return true end end)
    ok(count>0,"expected timer "..delay)
end
local function reset()
    if f2t_hauling_teleport_reset then f2t_hauling_teleport_reset() end
    timers,handlers,triggers,sent,nav,transitions,output={},{},{},{},{},{},{}
    mapped,hash,locked,paused,skipped,buys=true,"Sol.The Lattice.1637",false,0,0,0
    F2T_SPEEDWALK_ACTIVE,F2T_SPEEDWALK_WAITING_FOR_MOVE,F2T_SPEEDWALK_CUSTOMS_PENDING=false,false,false
    F2T_BULK_STATE,F2T_DEATH_STATE,F2T_STAMINA_STATE=nil,nil,nil
    f2t_hauling_customs_system_blocked=nil
    f2t_map_navigate=normal_navigate
    gmcp={room={info={num=1,system="Elsewhere",area="Origin",flags={"exchange"}}},
        char={vitals={name="Test Pilot"},ship={cargo={},hold={max=525,cur=525}}},exchange={commodities={}}}
    F2T_HAULING_STATE={active=true,current_phase="navigating_to_buy",mode="exchange",current_commodity="Woods",
        buy_location={system="Sol",planet="The Lattice"},session_policy={teleport_to_seller=true}}
    dofile(root.."/src/scripts/map/teleport.lua")
    dofile(root.."/src/scripts/hauling/exchange_teleport.lua")
    dofile(root.."/src/scripts/hauling/exchange_phases.lua")
    f2t_hauling_retry_exchange=function(side) eq(side,"buy"); skipped=skipped+1 end
end
local function start() f2t_hauling_phase_navigate_to_buy() end
local function owned(days)
    text("You check out your personal kit - a comm unit, an Mk1 teleporter control ("..(days or 31).." days until expiry),")
    text("a ship permit, and that seems to be it.")
end
local function port() start(); owned(); event("gmcp.char.ship"); eq(sent[3],"tp Sol.The Lattice") end
local function arrive(num,flags)
    gmcp.room.info={system="Sol",area="The Lattice",num=num or 1637,flags=flags or {"exchange"}}
    event("gmcp.room.info")
end
local function clean() eq(next(timers),nil,"timers cleaned"); eq(next(triggers),nil,"trigger cleaned"); eq(f2t_hauling_teleport_busy(),false) end
local function seller_arrival()
    port(); arrive(1600,{"shuttlepad"}); event("gmcp.char.ship"); arrive()
end

test("disabled feature leaves ordinary navigation unchanged",function()
    reset(); F2T_HAULING_STATE.session_policy.teleport_to_seller=false; start()
    eq(#sent,0); eq(#nav,1); clean()
end)
test("unmapped exchange uses normal navigation/discovery without inventing an address",function()
    reset(); mapped=false; start(); eq(#nav,1); eq(#sent,0); clean()
end)
test("teleport uses System.Planet without Mudlet ID or server room suffix",function()
    reset(); port(); eq(sent[3],"tp Sol.The Lattice"); eq(#nav,0)
end)
test("mismatched, malformed, injected and locked map hashes fall back",function()
    for _,value in ipairs({"Sol.Other.1637","Other.The Lattice.1637","Sol.The Lattice.9","5702","Sol.The Lattice.1637;buy woods"}) do
        reset(); hash=value; start(); eq(#sent,0); eq(#nav,1)
    end
    reset(); locked=true; start(); eq(#sent,0); eq(#nav,1)
end)
test("partial inventory cannot authorize teleport and times out to ordinary navigation",function()
    reset(); start(); text("You check out your personal kit - an Mk1 teleporter control (31 days until expiry),")
    eq(#sent,1); event("gmcp.char.ship"); eq(#sent,1); timeout(8); eq(#nav,1); clean()
end)
test("unrelated quoted inventory text does not authorize teleport",function()
    reset(); start(); text("Someone says: You check out your personal kit - an Mk1 teleporter control (31 days until expiry), and that seems to be it.")
    eq(#sent,1); timeout(8); eq(#nav,1)
end)
test("absent or expired control falls back and does not rent",function()
    reset(); start(); text("You check out your personal kit - a comm unit, and that seems to be it.")
    eq(#sent,1); eq(#nav,1); clean()
    reset(); start(); owned(0); eq(#sent,1); eq(#nav,1)
end)
test("wrapped inventory accepts ANSI and waits for fresh ship GMCP",function()
    reset(); start(); text("You check out your personal kit - a comm unit, an Mk1 teleporter control")
    text("\27[36m(31 days until expiry)\27[0m, and that seems to be it.")
    eq(sent[2],"status"); eq(#sent,2); eq(#nav,0); event("gmcp.char.ship"); eq(#sent,3)
end)
test("nonempty or unknown hold cannot teleport",function()
    for _,kind in ipairs({"loaded","missing","inconsistent"}) do
        reset()
        if kind=="loaded" then gmcp.char.ship.cargo={{commodity="Woods"}}
        elseif kind=="missing" then gmcp.char.ship.cargo=nil else gmcp.char.ship.hold.cur=450 end
        start(); eq(#sent,0); eq(#nav,1)
    end
end)
test("cargo appearing in fresh ship update pauses without teleport or purchase",function()
    reset(); start(); owned(); gmcp.char.ship.cargo={{commodity="Woods"}}; event("gmcp.char.ship")
    eq(#sent,2); eq(paused,1); eq(#nav,0); clean()
end)
test("missing fresh ship update falls back without teleport",function()
    reset(); start(); owned(); timeout(8); eq(#sent,2); eq(#nav,1); clean()
end)
test("map changes or manual movement during preflight prevent teleport",function()
    reset(); start(); owned(); hash="Sol.The Lattice.1638"; event("gmcp.char.ship"); eq(#sent,2); eq(#nav,1)
    reset(); start(); owned(); gmcp.room.info.num=2; event("gmcp.char.ship"); eq(#sent,2); eq(#nav,1)
end)
test("old speedwalk completion cannot advance while teleport worker is pending",function()
    reset(); start(); F2T_SPEEDWALK_LAST_RESULT="completed"; f2t_hauling_check_nav_to_buy_complete()
    f2t_hauling_phase_buy(); eq(#transitions,0); eq(buys,0)
end)
test("two verified hops and fresh seller ship data allow bulk purchase without exchange GMCP",function()
    reset(); port(); event("gmcp.exchange.commodities"); eq(#transitions,0)
    arrive(1600,{"shuttlepad"}); eq(sent[4],"status"); eq(#nav,0); eq(#transitions,0)
    event("gmcp.exchange.commodities"); eq(#transitions,0)
    event("gmcp.char.ship"); eq(sent[5],"tp 1637"); eq(#transitions,0)
    gmcp.exchange=nil -- Local teleport and look need not send any commodity snapshot.
    arrive(); eq(sent[6],"status"); eq(#transitions,0)
    event("gmcp.char.ship"); eq(transitions[1],"buying"); eq(paused,0); clean()
    f2t_hauling_phase_buy(); eq(buys,1)
    eq(#sent,6); eq(#nav,0)
end)
test("local teleport refusal uses normal local exchange navigation",function()
    reset(); port(); arrive(1600,{"shuttlepad"}); event("gmcp.char.ship")
    text("The location you are trying to access is teleport shielded!")
    eq(#nav,1); eq(nav[1],"The Lattice exchange"); eq(#transitions,0); clean()
end)
test("wrong room pauses without retry or buy",function()
    reset(); port(); arrive(999,{"exchange"}); eq(paused,1); eq(#nav,0); ok(f2t_hauling_teleport_uncertain()); clean()
end)
test("unanswered teleport latches uncertainty even on resume",function()
    reset(); port(); timeout(15); eq(paused,1); clean(); eq(#nav,0)
    F2T_HAULING_STATE.paused=false; start(); eq(paused,2); eq(#sent,3); eq(#nav,0)
end)
test("an exchange-only teleport arrival is not accepted as a shuttle pad",function()
    reset(); port(); arrive(); eq(paused,1); eq(buys,0); eq(#nav,0)
    ok(f2t_hauling_teleport_uncertain()); clean()
end)
test("shield, in-ship, expired and wrapped object refusals fall back once",function()
    for _,reply in ipairs({"You don't have a teleporter!","You can't teleport while you are in your spaceship.",
        "Your destination planet is teleport shielded!","The location you are trying to access is teleport shielded!"}) do
        reset(); port(); text(reply); eq(#nav,1); eq(#transitions,0); clean()
    end
    reset(); port(); text("Your ship is carrying at least one object that interferes with")
    text("teleport transmissions!"); eq(#nav,1); clean()
end)
test("unknown planet refusal safely uses ship navigation",function()
    reset(); port(); text("I can't find a planet called The Lattice in a star system called Sol!")
    eq(#nav,1); eq(#sent,3); clean()
end)
test("cargo and exile refusals do not start a fallback journey",function()
    for _,reply in ipairs({"You cannot teleport while your ship is carrying cargo!","You are exiled from this system! As you materialise"}) do
        reset(); port(); text(reply); eq(paused,1); eq(#nav,0); clean()
    end
end)
test("closed seller system is skipped without navigating into it",function()
    reset(); port(); text("I'm afraid the Sol system is closed to visitors at the moment.")
    eq(skipped,1); eq(#nav,0); clean()
end)
test("stop/cancel ignores delayed responses and marks in-flight movement uncertain",function()
    reset(); port(); F2T_HAULING_STATE.active=false; f2t_hauling_teleport_cancel()
    arrive(); event("gmcp.exchange.commodities"); eq(#transitions,0); eq(#sent,3); ok(f2t_hauling_teleport_uncertain()); clean()
end)
test("pause before teleport kills pending inventory work",function()
    reset(); start(); f2t_hauling_pause(true); owned(); event("gmcp.char.ship")
    eq(#sent,1); eq(f2t_hauling_teleport_uncertain(),false); clean()
end)
test("reconnect invalidates inventory ownership",function()
    reset(); port(); text("Your destination planet is teleport shielded!"); event("sysDisconnectionEvent")
    F2T_SPEEDWALK_ACTIVE=false; start(); eq(sent[4],"inv")
end)
test("one complete inventory per session reused until conservative expiry",function()
    reset(); port(); text("Your destination planet is teleport shielded!"); F2T_SPEEDWALK_ACTIVE=false
    start(); eq(sent[4],"status"); f2t_hauling_teleport_cancel(); clock=clock+3601
    start(); eq(sent[5],"inv")
end)
test("new hauling run always discards the old inventory",function()
    reset(); port(); text("Your destination planet is teleport shielded!"); F2T_SPEEDWALK_ACTIVE=false
    f2t_hauling_teleport_reset(); start(); eq(sent[4],"inv")
end)
test("death and stamina recovery have priority before teleport",function()
    reset(); F2T_DEATH_STATE={active=true}; start(); eq(paused,1); eq(#sent,0)
    reset(); start(); owned(); F2T_STAMINA_STATE={current_phase="navigating_to_food"}; event("gmcp.char.ship")
    eq(paused,1); eq(#sent,2); clean()
end)
test("new customs exclusion prevents teleport and skips supplier",function()
    reset(); start(); owned(); f2t_hauling_customs_system_blocked=function() return true end; event("gmcp.char.ship")
    eq(skipped,1); eq(#sent,2); clean()
end)
test("fallback may not buy at a different exchange",function()
    reset(); mapped=false; start(); f2t_hauling_phase_buy(); eq(buys,0); eq(paused,1)
end)
test("pending unmapped discovery ignores old room-completion events",function()
    reset(); mapped=false; local done
    f2t_map_navigate=function(_,options) done=options.on_result; return "pending" end
    start(); F2T_SPEEDWALK_LAST_RESULT="completed"; f2t_hauling_check_nav_to_buy_complete()
    eq(#transitions,0); eq(paused,0); eq(skipped,0)
    arrive(); done(true); eq(transitions[1],"buying")
end)
test("failed discovery skips supplier once and ignores a stale callback",function()
    reset(); mapped=false; local done
    f2t_map_navigate=function(_,options) done=options.on_result; return "pending" end
    start(); done(false); eq(skipped,1); done(false); eq(skipped,1); eq(#transitions,0)
end)
test("old navigation callback cannot revive a changed supplier",function()
    reset(); mapped=false; local done
    f2t_map_navigate=function(_,options) done=options.on_result; return "pending" end
    start(); F2T_HAULING_STATE.buy_location={system="Elsewhere",planet="Different"}
    done(true); eq(#transitions,0); eq(skipped,0)
end)
test("loaded seller-to-buyer travel never invokes the teleport worker",function()
    reset(); gmcp.char.ship.cargo={{commodity="Woods"}}; F2T_HAULING_STATE.current_phase="navigating_to_sell"
    F2T_HAULING_STATE.sell_location={system="Far",planet="Buyer"}
    f2t_hauling_phase_navigate_to_sell(); eq(#sent,0); eq(nav[1],"Buyer exchange")
end)
test("discovery already-arrived status overrides stale failed speedwalk",function()
    reset(); mapped=false; local done
    f2t_map_navigate=function(_,options) done=options.on_result; return "pending" end
    start(); F2T_SPEEDWALK_LAST_RESULT="failed"; arrive(); done(true,"arrived")
    eq(transitions[1],"buying"); eq(skipped,0)
end)
test("partial ship event cannot authorize a teleport",function()
    reset(); start(); owned()
    for id in pairs(handlers) do if id.event=="gmcp.char.ship" then id.fn("gmcp.char.ship.fuel") end end
    eq(#sent,2); event("gmcp.char.ship"); eq(#sent,3)
end)
test("protection appearing on arrival prevents bulk buying",function()
    reset(); port(); F2T_DEATH_STATE={active=true}; arrive(1600,{"shuttlepad"})
    eq(#transitions,0); eq(buys,0); eq(paused,1); clean()
end)
test("shuttle pad on another planet cannot authorize local navigation",function()
    reset(); port(); gmcp.room.info={system="Sol",area="Wrong Planet",num=1600,flags={"shuttlepad"}}
    event("gmcp.room.info"); eq(#nav,0); eq(paused,1); eq(buys,0); clean()
end)
test("repeated shuttle arrival cannot duplicate status or the local teleport",function()
    reset(); port(); arrive(1600,{"shuttlepad"}); arrive(1600,{"shuttlepad"})
    eq(#nav,0); eq(#sent,4); eq(sent[4],"status"); eq(#transitions,0)
    event("gmcp.char.ship"); event("gmcp.char.ship"); eq(#sent,5); eq(sent[5],"tp 1637")
end)
test("cargo change during teleport pauses before starting local navigation",function()
    reset(); port(); gmcp.char.ship.cargo={{commodity="Woods"}}; arrive(1600,{"shuttlepad"})
    eq(#nav,0); eq(paused,1); eq(buys,0); clean()
end)
test("missing Mudlet hash reader falls back without throwing",function()
    reset(); local reader=getRoomHashByID; getRoomHashByID=nil
    local success,err=pcall(start); getRoomHashByID=reader
    ok(success,err); eq(#sent,0); eq(#nav,1)
end)
test("already on seller planet sends only the room number teleport",function()
    reset(); gmcp.room.info={system="Sol",area="The Lattice",num=1600,flags={"shuttlepad"}}
    start(); owned(); event("gmcp.char.ship"); eq(sent[3],"tp 1637"); eq(#sent,3)
end)
test("second-hop fresh cargo check prevents local teleport",function()
    reset(); port(); arrive(1600,{"shuttlepad"}); gmcp.char.ship.cargo={{commodity="Woods"}}
    event("gmcp.char.ship"); eq(#sent,4); eq(#nav,0); eq(paused,1); clean()
end)
test("second-hop ship timeout falls back locally without repeating the planetary hop",function()
    reset(); port(); arrive(1600,{"shuttlepad"}); timeout(8)
    eq(#sent,4); eq(#nav,1); eq(f2t_hauling_teleport_uncertain(),false); clean()
end)
test("second-hop timeout remains uncertain and never auto-walks or buys",function()
    reset(); port(); arrive(1600,{"shuttlepad"}); event("gmcp.char.ship"); timeout(15)
    eq(#sent,5); eq(#nav,0); eq(buys,0); eq(paused,1); ok(f2t_hauling_teleport_uncertain()); clean()
end)
test("stop between hops cannot send the local teleport from late ship GMCP",function()
    reset(); port(); arrive(1600,{"shuttlepad"}); F2T_HAULING_STATE.active=false; f2t_hauling_teleport_cancel()
    event("gmcp.char.ship"); eq(#sent,4); eq(#nav,0); eq(f2t_hauling_teleport_uncertain(),false); clean()
end)
test("missing seller ship response pauses rather than buying from cached empty hold",function()
    reset(); seller_arrival(); eq(sent[6],"status"); timeout(8)
    eq(paused,1); eq(buys,0); eq(f2t_hauling_teleport_uncertain(),false); clean()
end)

test("commodity snapshot and partial ship event cannot replace final full ship confirmation",function()
    reset(); seller_arrival(); event("gmcp.exchange.commodities"); eq(#transitions,0)
    for id in pairs(handlers) do if id.event=="gmcp.char.ship" then id.fn("gmcp.char.ship.fuel") end end
    eq(#transitions,0); event("gmcp.char.ship"); eq(transitions[1],"buying"); clean()
end)

test("repeated seller arrival and late events cannot duplicate the final status or purchase transition",function()
    reset(); seller_arrival(); arrive(); arrive(); eq(#sent,6); eq(sent[6],"status")
    event("gmcp.char.ship"); arrive(); event("gmcp.char.ship"); event("gmcp.exchange.commodities")
    eq(#transitions,1); eq(transitions[1],"buying"); eq(#sent,6); eq(#nav,0); clean()
end)

test("fresh final cargo must be empty and internally consistent",function()
    for _,kind in ipairs({"loaded","missing","inconsistent"}) do
        reset(); seller_arrival()
        if kind=="loaded" then gmcp.char.ship.cargo={{commodity="Woods"}}
        elseif kind=="missing" then gmcp.char.ship.cargo=nil else gmcp.char.ship.hold.cur=450 end
        event("gmcp.char.ship"); eq(paused,1); eq(#transitions,0); eq(#nav,0); clean()
    end
end)

test("protection recovery at the final exchange blocks purchasing",function()
    for _,when in ipairs({"arrival","ship"}) do
        reset(); port(); arrive(1600,{"shuttlepad"}); event("gmcp.char.ship")
        if when=="arrival" then F2T_DEATH_STATE={active=true} end
        arrive()
        if when=="ship" then F2T_STAMINA_STATE={current_phase="navigating_to_food"} end
        event("gmcp.char.ship"); eq(paused,1); eq(#transitions,0); eq(#nav,0); clean()
    end
end)

test("changed final room or missing exchange flag cannot authorize buying",function()
    for _,kind in ipairs({"room","system","planet","flag"}) do
        reset(); seller_arrival()
        if kind=="room" then gmcp.room.info.num=999
        elseif kind=="system" then gmcp.room.info.system="Other"
        elseif kind=="planet" then gmcp.room.info.area="Other"
        else gmcp.room.info.flags={} end
        event("gmcp.char.ship"); eq(paused,1); eq(#transitions,0); eq(#nav,0); clean()
    end
end)

test("room movement while awaiting seller ship data pauses with no movement uncertainty",function()
    reset(); seller_arrival(); arrive(999,{"exchange"}); event("gmcp.char.ship")
    eq(paused,1); eq(#transitions,0); eq(#nav,0); eq(f2t_hauling_teleport_uncertain(),false); clean()
end)

test("final seller map and customs policy are rechecked before buying",function()
    reset(); seller_arrival(); hash="Sol.The Lattice.999"; event("gmcp.char.ship")
    eq(paused,1); eq(#transitions,0); eq(#nav,0); clean()
    reset(); seller_arrival(); f2t_hauling_customs_system_blocked=function() return true end
    event("gmcp.char.ship"); eq(skipped,1); eq(#transitions,0); eq(#nav,0); clean()
end)

test("stop pause disconnect and reload discard final seller ship callbacks",function()
    for _,kind in ipairs({"stop","pause","disconnect","reload"}) do
        reset(); seller_arrival()
        if kind=="stop" then F2T_HAULING_STATE.active=false; f2t_hauling_teleport_cancel()
        elseif kind=="pause" then f2t_hauling_pause(true)
        elseif kind=="disconnect" then event("sysDisconnectionEvent")
        else dofile(root.."/src/scripts/hauling/exchange_teleport.lua") end
        event("gmcp.char.ship"); arrive(); eq(#transitions,0); eq(#sent,6)
        eq(f2t_hauling_teleport_uncertain(),false); clean()
    end
end)

test("changed supplier or character cannot consume a late final ship response",function()
    for _,kind in ipairs({"supplier","character"}) do
        reset(); seller_arrival()
        if kind=="supplier" then F2T_HAULING_STATE.buy_location={system="Elsewhere",planet="Other"}
        else gmcp.char.vitals.name="Another Pilot" end
        event("gmcp.char.ship"); eq(#transitions,0); timeout(8); eq(paused,0); clean()
    end
end)

test("same planet local-only teleport also buys without a commodity snapshot",function()
    reset(); gmcp.room.info={system="Sol",area="The Lattice",num=1600,flags={"shuttlepad"}}
    start(); owned(); event("gmcp.char.ship"); arrive(); eq(sent[4],"status")
    gmcp.exchange=nil; event("gmcp.char.ship"); eq(transitions[1],"buying"); eq(#sent,4); clean()
end)
test("wrong second-hop exchange cannot authorize a purchase",function()
    reset(); port(); arrive(1600,{"shuttlepad"}); event("gmcp.char.ship"); arrive(1234,{"exchange"})
    eq(#nav,0); eq(buys,0); eq(paused,1); ok(f2t_hauling_teleport_uncertain()); clean()
end)

test("real bulk buyer sends one counted seven-bay order after final ship confirmation without market data",function()
    reset(); seller_arrival(); gmcp.exchange=nil
    F2T_BULK_STATE={}
    f2t_resolve_commodity=function(value) return value,false end
    f2t_has_value=function(values,wanted)
        for _,value in pairs(values) do if value==wanted then return true end end
        return false
    end
    f2t_bulk_watchdog_start=function() end
    dofile(root.."/src/scripts/commodities/bulk_buy.lua")
    event("gmcp.char.ship"); eq(transitions[1],"buying"); clean()
    f2t_hauling_phase_buy(); eq(sent[7],"buy woods 7"); eq(#sent,7)
    event("gmcp.char.ship"); arrive(); event("gmcp.exchange.commodities"); f2t_hauling_phase_buy()
    eq(#sent,7); eq(#transitions,1); eq(#nav,0); eq(paused,0)
    eq(F2T_BULK_STATE.active,true); eq(F2T_BULK_STATE.batched,true)
end)
print(string.format("Teleport hauling: %d passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end
