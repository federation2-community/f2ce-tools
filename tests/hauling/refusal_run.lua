-- Exercise real bulk callbacks, refusal trigger bodies and exchange phases.
local root = tostring(arg and arg[1] or ".")
local sent, timers, navigated, output, queries, removed, stopped, completed, analysis, parsed, deferred, pending
local passed, failed = 0, 0
local function equal(actual, expected, label)
    if actual ~= expected then error((label or "value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual), 2) end
end
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed=passed+1; print("PASS " .. name)
    else failed=failed+1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
function f2t_debug_log() end
function f2t_settings_register() end
function f2t_register_help() end
function cecho(message) output[#output+1] = message end
function send(command) sent[#sent+1] = command end
function tempTimer(seconds, callback)
    local timer = {seconds=seconds, callback=callback}
    timers[timer] = true
    return timer
end
function killTimer(timer) timers[timer] = nil end
function f2t_resolve_commodity(value) return value, false end
function f2t_has_value(values, wanted)
    for _, value in ipairs(values) do if value == wanted then return true end end
    return false
end
function f2t_map_brief_hold_release() end
function f2t_price_check_commodity(commodity, callback)
    queries = queries + 1
    if deferred then pending=callback else callback(commodity, parsed, analysis) end
end
dofile(root .. "/src/scripts/commodities/init.lua")
dofile(root .. "/src/scripts/commodities/bulk_buy.lua")
dofile(root .. "/src/scripts/commodities/bulk_sell.lua")
dofile(root .. "/src/scripts/hauling/state_machine.lua")
dofile(root .. "/src/scripts/hauling/exchange_recovery.lua")
dofile(root .. "/src/scripts/hauling/exchange_phases.lua")
local real_complete_cycle = f2t_hauling_complete_commodity_cycle
local real_do_stop = f2t_hauling_do_stop
function f2t_hauling_do_stop()
    stopped=stopped+1
    F2T_HAULING_STATE.active=false
    F2T_HAULING_STATE.exchange_market=nil
end
function f2t_hauling_stop() f2t_hauling_do_stop() end
function f2t_hauling_remove_current_commodity() removed=removed+1 end
function f2t_hauling_complete_commodity_cycle() completed=completed+1 end
function f2t_hauling_phase_navigate_to_buy()
    navigated[#navigated+1]=F2T_HAULING_STATE.buy_location.planet
end
function f2t_hauling_phase_navigate_to_sell()
    navigated[#navigated+1]=F2T_HAULING_STATE.sell_location.planet
end
local function row(planet, price, system) return {planet=planet, price=price, system=system or "System"} end
local function cargo(count)
    gmcp.char.ship.cargo={}
    for _=1,count do table.insert(gmcp.char.ship.cargo, {commodity="NanoFabrics", cost=100, origin="Supplier A"}) end
    gmcp.char.ship.hold={cur=225-count*75, max=225}
end
local function reset()
    sent, timers, navigated, output, queries, removed, stopped = {}, {}, {}, {}, 0, 0, 0
    deferred, pending=false, nil
    completed=0
    parsed={}
    analysis={top_sell={row("Supplier A",100),row("Supplier B",105)},
        top_buy={row("Buyer A",200),row("Buyer B",190)}, profit=100}
    F2T_BULK_STATE={active=false}
    F2T_HAULING_STATE={active=true, paused=false, current_commodity="NanoFabrics",
        current_phase="buying", margin_threshold_pct=40, commodity_cycles=0, sell_attempts=0,
        actual_cost=100, current_commodity_stats={lots_bought=0,total_cost=0,lots_sold=0,total_revenue=0}}
    gmcp={room={info={flags={"exchange"}}},char={ship={}}}
    cargo(0)
    f2t_hauling_get_commodity_details("NanoFabrics")
    equal(queries,1,"initial market query")
    navigated={}
end
local function trigger(name) dofile(root .. "/src/triggers/commodities/" .. name .. ".lua") end
local function buy() F2T_HAULING_STATE.current_phase="buying"; f2t_hauling_phase_buy() end
-- Sale-only fixtures model a load already purchased by this run.
local function seed_load_receipts()
    local stats=F2T_HAULING_STATE.current_commodity_stats
    if stats.lots_bought==0 and #gmcp.char.ship.cargo>0 then
        stats.lots_bought=#gmcp.char.ship.cargo
        for _,lot in ipairs(gmcp.char.ship.cargo) do stats.total_cost=stats.total_cost+lot.cost*75 end
    end
end
local function local_quote(bid, kind)
    seed_load_receipts()
    local destination=F2T_HAULING_STATE.sell_location
    gmcp.room.info={flags={"exchange"},num=1,area=destination.planet,system=destination.system}
    local commodity=F2T_HAULING_STATE.current_commodity
    gmcp.exchange={commodities={[commodity]={buy=bid}},commodity={name=commodity,buy=bid}}
    f2t_hauling_recovery_observe(kind or "full")
end
local function sell()
    local_quote(F2T_HAULING_STATE.sell_location.price)
    F2T_HAULING_STATE.current_phase="selling"; f2t_hauling_phase_sell()
end
local function no_timer() equal(next(timers),nil,"watchdog cancelled") end

test("unavailable supplier advances immediately without another price poll", function()
    reset(); buy(); trigger("buy_error_not_selling")
    equal(navigated[1],"Supplier B"); equal(queries,1); equal(stopped,0)
    equal(sent[1],"buy nanofabrics 3"); equal(#sent,1); no_timer()
end)
test("not-buying refusal advances immediately without reselecting first buyer", function()
    reset(); cargo(3); sell(); trigger("sell_error_not_buying")
    equal(navigated[1],"Buyer B"); equal(queries,1); equal(#sent,1)
    equal(sent[1],"sell nanofabrics 1"); equal(#gmcp.char.ship.cargo,3); no_timer()
end)
test("Galactic Administration refusal bypasses the watchdog", function()
    reset(); cargo(3); sell(); trigger("sell_error_restricted")
    equal(navigated[1],"Buyer B"); equal(queries,1); equal(stopped,0); no_timer()
end)
test("partial buy followed by refusal delivers its confirmed cargo", function()
    reset(); buy(); cargo(1); f2t_bulk_buy_success(7500); trigger("buy_error_not_selling")
    equal(navigated[1],"Buyer A"); equal(#sent,1)
    equal(F2T_HAULING_STATE.current_commodity_stats.lots_bought,1)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_cost,7500); no_timer()
end)
test("partial sale followed by restriction keeps remainder and records sold lots", function()
    reset(); cargo(3); sell(); cargo(2); f2t_bulk_sell_success("NanoFabrics",200,15000)
    local_quote(200,"tick") -- next guarded bay, which is then refused
    trigger("sell_error_restricted")
    equal(navigated[1],"Buyer B"); equal(#gmcp.char.ship.cargo,2)
    equal(F2T_HAULING_STATE.current_commodity_stats.lots_sold,1)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue,15000); no_timer()
end)
test("reordered refreshed prices never revisit either rejected buyer", function()
    reset(); cargo(3); sell(); trigger("sell_error_not_buying")
    analysis.top_buy={row("buyer b",210),row("Buyer A",200),row("Buyer C",180)}
    sell(); trigger("sell_error_not_buying")
    equal(queries,2); equal(#navigated,2); equal(navigated[2],"Buyer C"); no_timer()
end)
test("exhausted suppliers skip commodity after just one refresh", function()
    reset(); buy(); trigger("buy_error_not_selling"); buy(); trigger("buy_error_not_selling")
    equal(queries,2); equal(removed,1); equal(stopped,0); equal(#navigated,1); no_timer()
end)
test("exhausted buyers stop with cargo intact rather than retry or jettison", function()
    reset(); cargo(3); sell(); trigger("sell_error_not_buying"); sell(); trigger("sell_error_restricted")
    equal(queries,2); equal(stopped,1); equal(removed,0); equal(#gmcp.char.ship.cargo,3)
    equal(#sent,2); no_timer()
end)
test("alternative supplier still has to meet the configured margin", function()
    reset(); F2T_HAULING_STATE.exchange_market.buy[2].price=180
    analysis.top_sell[2].price=180
    buy(); trigger("buy_error_not_selling")
    equal(#navigated,0); equal(removed,1); equal(queries,2)
end)
test("owned cargo may clear below new-purchase margin without a loss", function()
    reset(); F2T_HAULING_STATE.exchange_market.sell[2].price=110
    analysis.top_buy[2].price=110
    cargo(3); sell(); trigger("sell_error_restricted")
    equal(navigated[1],"Buyer B"); equal(stopped,0); equal(#gmcp.char.ship.cargo,3)
    equal(F2T_HAULING_STATE.sell_recovery,true)
end)
test("invalid price response stops cleanly instead of indexing nil", function()
    reset(); analysis=nil
    f2t_hauling_get_commodity_details("NanoFabrics")
    equal(stopped,1); equal(#navigated,0)
end)
test("refused supplier remains excluded during repeat commodity details", function()
    reset(); buy(); trigger("buy_error_not_selling")
    f2t_hauling_get_commodity_details("NanoFabrics")
    equal(F2T_HAULING_STATE.buy_location.planet,"Supplier B")
end)
test("empty refreshed side cannot retain old commodity locations", function()
    reset(); analysis.top_sell={}
    f2t_hauling_get_commodity_details("NanoFabrics")
    equal(F2T_HAULING_STATE.buy_location,nil); equal(removed,1); equal(#navigated,0)
end)
test("late alternative-price reply cannot resume a stopped run", function()
    reset(); cargo(3); sell(); trigger("sell_error_not_buying")
    deferred=true; sell(); trigger("sell_error_restricted"); local reply=pending
    f2t_hauling_do_stop(); F2T_HAULING_STATE.active=true
    analysis.top_buy={row("Buyer C",200)}; reply("NanoFabrics",{},analysis)
    equal(#navigated,1); equal(#sent,2)
end)
test("pause requested at refusal prevents navigation until explicit resume", function()
    reset(); buy(); F2T_HAULING_STATE.pause_requested=true; trigger("buy_error_not_selling")
    equal(F2T_HAULING_STATE.paused,true); equal(#navigated,0)
    equal(F2T_HAULING_STATE.current_phase,"navigating_to_buy")
    F2T_HAULING_STATE.paused=false; f2t_hauling_transition(F2T_HAULING_STATE.current_phase)
    equal(navigated[1],"Supplier B")
end)
test("paused alternative refresh resumes without repeating rejected purchase", function()
    reset(); buy(); trigger("buy_error_not_selling")
    deferred=true; buy(); trigger("buy_error_not_selling")
    F2T_HAULING_STATE.paused=true
    analysis.top_sell={row("Supplier C",105)}; pending("NanoFabrics",{},analysis)
    equal(#navigated,1); equal(F2T_HAULING_STATE.current_phase,"finding_buy")
    deferred=false; F2T_HAULING_STATE.paused=false
    f2t_hauling_transition("finding_buy"); equal(navigated[2],"Supplier C"); equal(#sent,2)
end)
test("graceful stop never starts another supplier trip", function()
    reset(); buy(); F2T_HAULING_STATE.stopping=true; trigger("buy_error_not_selling")
    equal(stopped,1); equal(#navigated,0); equal(queries,1)
end)
test("timed-out partial buy stops without treating partial results as permission", function()
    reset(); buy(); cargo(1); f2t_bulk_buy_success()
    local timer=F2T_BULK_STATE.watchdogTimerId; timers[timer]=nil; timer.callback()
    equal(stopped,1); equal(#navigated,0); equal(#sent,1); equal(#gmcp.char.ship.cargo,1)
end)
test("timed-out sell stops without attempting another buyer", function()
    reset(); cargo(3); sell()
    local timer=F2T_BULK_STATE.watchdogTimerId; timers[timer]=nil; timer.callback()
    equal(stopped,1); equal(#navigated,0); equal(#sent,1); equal(#gmcp.char.ship.cargo,3)
end)
test("mixed-cargo watchdog aborts queue without sending its next sale", function()
    reset(); cargo(2); gmcp.char.ship.cargo[2].commodity="Woods"
    local result
    f2t_bulk_sell_start(nil,nil,function(_,_,status,reason,code) result={status,reason,code} end)
    local timer=F2T_BULK_STATE.watchdogTimerId; timers[timer]=nil; timer.callback()
    equal(#sent,1); equal(result[1],"error"); equal(result[3],"timeout")
end)
test("manual bulk callbacks retain refusal reason and reset before reentry", function()
    reset(); local result
    f2t_bulk_buy_start("NanoFabrics",1,function(_,lots,status,reason,code)
        result={lots,status,reason,code}
        equal(F2T_BULK_STATE.active,false)
        f2t_bulk_buy_start("Woods",1,function() end)
    end)
    trigger("buy_error_not_selling")
    equal(result[1],0); equal(result[2],"failed"); equal(result[4],"not_selling")
    equal(F2T_BULK_STATE.error_code,nil); equal(F2T_BULK_STATE.commodity,"Woods")
end)
test("unsolicited refusal cannot move inactive automation", function()
    reset(); F2T_HAULING_STATE.active=false
    trigger("buy_error_not_selling"); trigger("sell_error_not_buying"); trigger("sell_error_restricted")
    equal(#sent,0); equal(#navigated,0)
end)
test("commodity change does not blacklist the planet for other goods", function()
    reset(); buy(); trigger("buy_error_not_selling")
    F2T_HAULING_STATE.current_commodity="Woods"
    f2t_hauling_get_commodity_details("Woods")
    equal(F2T_HAULING_STATE.buy_location.planet,"Supplier A")
end)
test("same planet name in a different system is a distinct alternative", function()
    reset(); F2T_HAULING_STATE.exchange_market.buy={row("Supplier A",100),row("Supplier A",100,"Other")}
    buy(); trigger("buy_error_not_selling")
    equal(F2T_HAULING_STATE.buy_location.system,"Other"); equal(queries,1)
end)
test("late reply for the previous commodity cannot overwrite new route", function()
    reset(); deferred=true; f2t_hauling_get_commodity_details("NanoFabrics"); local reply=pending
    F2T_HAULING_STATE.current_commodity="Woods"; deferred=false
    f2t_hauling_get_commodity_details("Woods"); local before=#navigated
    reply("NanoFabrics",{},{top_sell={row("Stale",100)},top_buy={row("Stale Buyer",200)}})
    equal(#navigated,before); equal(F2T_HAULING_STATE.buy_location.planet,"Supplier A")
end)
test("unexpected existing cargo stops before any unguarded clearing sale", function()
    reset(); cargo(3); buy(); trigger("sell_error_restricted")
    equal(stopped,1); equal(#sent,0); equal(#gmcp.char.ship.cargo,3)
end)
test("dump watchdog cannot navigate or jettison uncertain cargo", function()
    reset(); cargo(3); local_quote(200); f2t_hauling_phase_dump_cargo()
    local timer=F2T_BULK_STATE.watchdogTimerId; timers[timer]=nil; timer.callback()
    equal(stopped,1); equal(#navigated,0); equal(#sent,1); equal(#gmcp.char.ship.cargo,3)
end)
test("uses the twenty-first premium buyer instead of stopping at the UI limit", function()
    reset(); parsed={buy={}, sell={row("Supplier A",100)}}; analysis.top_buy={}
    for index=1,21 do
        local candidate=row("Buyer " .. index,201-index)
        parsed.buy[index]=candidate
        if index <= 20 then analysis.top_buy[index]=candidate end
    end
    f2t_hauling_get_commodity_details("NanoFabrics"); navigated={}; cargo(3)
    for index=1,20 do sell(); trigger("sell_error_not_buying") end
    equal(navigated[20],"Buyer 21"); equal(#navigated,20); equal(queries,2)
    equal(stopped,0); equal(#analysis.top_buy,20,"UI list unchanged")
end)
test("refresh also finds buyers beyond a refused premium shortlist", function()
    reset(); cargo(3); sell(); trigger("sell_error_not_buying")
    parsed={buy={row("Buyer A",200),row("Buyer B",190),row("Buyer C",180)},sell=analysis.top_sell}
    sell(); trigger("sell_error_not_buying")
    equal(navigated[2],"Buyer C"); equal(stopped,0); equal(queries,2)
end)
test("native display result limit does not hide remaining suppliers", function()
    reset(); analysis.top_sell={row("Supplier A",100)}
    parsed={buy=analysis.top_buy,sell={row("Supplier A",100),row("Supplier B",105)}}
    f2t_hauling_get_commodity_details("NanoFabrics"); navigated={}
    buy(); trigger("buy_error_not_selling")
    equal(navigated[1],"Supplier B"); equal(queries,2); equal(#analysis.top_sell,1)
end)
test("explicitly empty full market cannot resurrect stale shortlist entries", function()
    reset(); parsed={buy={},sell={row("Supplier A",100)}}
    f2t_hauling_get_commodity_details("NanoFabrics")
    equal(removed,1); equal(#navigated,0)
end)
test("partially malformed parsed market fails closed", function()
    reset(); parsed={buy={row("Buyer A",200)}}
    f2t_hauling_get_commodity_details("NanoFabrics")
    equal(stopped,1); equal(#navigated,0)
end)
test("buyer exhaustion explains candidates below the cargo purchase cost", function()
    reset(); F2T_HAULING_STATE.exchange_market.sell[2].price=95; analysis.top_buy[2].price=95
    cargo(3); sell(); trigger("sell_error_not_buying")
    local messages=table.concat(output)
    equal(messages:find("2 quoted, 1 untried",1,true) ~= nil,true)
    equal(messages:find("95ig/ton, whole-load minimum net bid 100.01ig/ton",1,true) ~= nil,true)
end)
test("recovery uses whole-load cost instead of the most expensive remaining bay", function()
    reset(); cargo(3); gmcp.char.ship.cargo[3].cost=195
    sell(); trigger("sell_error_not_buying")
    equal(stopped,0); equal(navigated[1],"Buyer B"); equal(#gmcp.char.ship.cargo,3)
end)
test("zero-profit candidate is not eligible under the greater-than-one-groat policy", function()
    reset(); F2T_HAULING_STATE.exchange_market.sell[2].price=100; analysis.top_buy[2].price=100
    cargo(3); sell(); trigger("sell_error_not_buying")
    equal(#navigated,0); equal(stopped,1)
end)
local function recovery(bid)
    reset(); cargo(3); sell(); trigger("sell_error_not_buying")
    F2T_HAULING_STATE.sell_location.price=bid
    local_quote(bid)
    F2T_HAULING_STATE.current_phase="selling"; f2t_hauling_phase_sell()
end
test("recovery sends one bay and waits for a new commodity quote", function()
    recovery(110); equal(sent[2],"sell nanofabrics 1"); equal(#sent,2)
    cargo(2); f2t_bulk_sell_success("NanoFabrics",109,8175)
    equal(#sent,2); equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue,8175)
    local_quote(108,"tick"); equal(#sent,3); equal(sent[3],"sell nanofabrics 1")
end)
test("a falling next-bay bid cannot drain remaining cargo below cost", function()
    recovery(101); cargo(2); f2t_bulk_sell_success("NanoFabrics",100,7500)
    local_quote(99,"tick")
    equal(#sent,2); equal(#gmcp.char.ship.cargo,2); equal(stopped,1)
end)
test("below-cost arrival quote sends no recovery order", function()
    recovery(99)
    equal(#sent,1); equal(stopped,1); equal(#gmcp.char.ship.cargo,3)
end)
test("recovery requires a real current-room commodity receipt", function()
    reset(); cargo(3); sell(); trigger("sell_error_not_buying")
    gmcp.exchange={commodities={NanoFabrics={buy=200}}}
    F2T_HAULING_STATE.current_phase="selling"; f2t_hauling_phase_sell()
    equal(#sent,1)
    local_quote(110); equal(#sent,2)
end)
test("unrelated commodity tick cannot authorize another recovery bay", function()
    recovery(110); cargo(2); f2t_bulk_sell_success("NanoFabrics",110,8250)
    gmcp.exchange.commodity={name="Woods",buy=999}; f2t_hauling_recovery_observe("tick")
    equal(#sent,2)
end)
test("room change invalidates local recovery quotes", function()
    recovery(110); cargo(2); f2t_bulk_sell_success("NanoFabrics",110,8250)
    gmcp.room.info.area="Other Planet"; f2t_hauling_recovery_observe("room")
    gmcp.exchange.commodity={name="NanoFabrics",buy=200}; f2t_hauling_recovery_observe("tick")
    equal(#sent,2)
end)
test("recovery waits for cargo reconciliation as well as a price tick", function()
    recovery(110); f2t_bulk_sell_success("NanoFabrics",110,8250)
    local_quote(109,"tick"); equal(#sent,2)
    cargo(2); f2t_hauling_recovery_observe("cargo"); equal(#sent,3)
end)
test("recovery empties hold and advances commodity exactly once", function()
    recovery(110)
    for remaining=2,0,-1 do
        cargo(remaining); f2t_bulk_sell_success("NanoFabrics",110,8250)
        if remaining > 0 then local_quote(110,"tick") end
    end
    equal(#sent,4); equal(sent[4],"sell cargo"); equal(completed,1); equal(removed,1)
    equal(F2T_HAULING_STATE.sell_recovery,nil)
    equal(F2T_HAULING_STATE.current_commodity_stats.lots_sold,3)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue,24750)
    local_quote(110,"tick"); equal(completed,1); no_timer()
end)
test("deferred pause prevents the next recovery bay and resume revalidates", function()
    recovery(110); F2T_HAULING_STATE.pause_requested=true
    cargo(2); f2t_bulk_sell_success("NanoFabrics",110,8250); local_quote(105,"tick")
    equal(F2T_HAULING_STATE.paused,true); equal(#sent,2)
    F2T_HAULING_STATE.paused=false; f2t_hauling_transition("selling")
    equal(#sent,3)
end)
test("recovery cleanup prevents late ticks and timers from sending orders", function()
    recovery(110); cargo(2); f2t_bulk_sell_success("NanoFabrics",110,8250)
    local old_timer=F2T_HAULING_STATE.recovery_watch.timer
    f2t_hauling_recovery_cleanup(); old_timer.callback(); local_quote(110,"tick")
    equal(#sent,2); equal(stopped,0)
end)
test("missing follow-up quote skips the buyer but never retries an unpriced bay", function()
    recovery(110); cargo(2); f2t_bulk_sell_success("NanoFabrics",110,8250)
    local timer=F2T_HAULING_STATE.recovery_watch.timer; timers[timer]=nil; timer.callback()
    equal(#sent,2); equal(stopped,1); equal(#gmcp.char.ship.cargo,2)
end)
test("forced pause keeps the final receipt and completes only on resume", function()
    reset(); cargo(1); sell(); trigger("sell_error_not_buying"); local_quote(110)
    f2t_hauling_phase_sell(); F2T_HAULING_STATE.paused=true
    cargo(0); f2t_bulk_sell_success("NanoFabrics",110,8250)
    equal(completed,0); equal(F2T_HAULING_STATE.recovery_expected_lots,0)
    F2T_HAULING_STATE.paused=false; f2t_hauling_transition("waiting_sell_quote")
    equal(completed,1); equal(removed,1); equal(#sent,2); no_timer()
end)
test("server-side price race credits the receipt then rechecks the remaining load", function()
    recovery(101); cargo(2); f2t_bulk_sell_success("NanoFabrics",99,7425)
    equal(stopped,0); equal(#sent,2); equal(#gmcp.char.ship.cargo,2)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue,7425)
    local_quote(102,"tick"); equal(#sent,3); equal(stopped,0)
end)
test("cargo mismatch after a receipt times out without another order", function()
    recovery(110); f2t_bulk_sell_success("NanoFabrics",110,8250)
    local timer=F2T_HAULING_STATE.recovery_watch.timer; timers[timer]=nil; timer.callback()
    equal(stopped,1); equal(#sent,2); equal(F2T_HAULING_STATE.recovery_watch,nil)
end)
test("exchange lifecycle registers and removes parent ship and quote handlers", function()
    reset(); local handlers={}; local serial=0
    function registerAnonymousEventHandler(event,callback)
        serial=serial+1; handlers[serial]={event=event,callback=callback}; return serial
    end
    function killAnonymousEventHandler(id) handlers[id]=nil end
    local id=f2t_exchange_register_handlers()
    local events={}; for _,handler in pairs(handlers) do events[handler.event]=true end
    equal(events["gmcp.char.ship"],true)
    equal(events["gmcp.exchange.commodities"],true); equal(events["gmcp.exchange.commodity"],true)
    f2t_exchange_cleanup_handlers(id); equal(next(handlers),nil)
    equal(F2T_HAULING_STATE.recovery_watch,nil)
end)
test("reloaded state cannot be mutated by the old recovery timer", function()
    recovery(110); cargo(2); f2t_bulk_sell_success("NanoFabrics",110,8250)
    local timer=F2T_HAULING_STATE.recovery_watch.timer
    F2T_HAULING_STATE={active=true,current_commodity="Woods",current_phase="buying"}
    timer.callback(); equal(#sent,2); equal(stopped,0)
    equal(F2T_HAULING_STATE.current_phase,"buying")
end)
test("initial buyer quote below actual cost sends no sale", function()
    reset(); cargo(3); local_quote(99); f2t_hauling_phase_sell()
    equal(#sent,0); equal(navigated[1],"Buyer B"); equal(#gmcp.char.ship.cargo,3)
end)

test("normal buyer records actual revenue not a stale remote quote", function()
    reset(); cargo(2); local_quote(180); f2t_hauling_phase_sell()
    cargo(1); f2t_bulk_sell_success("NanoFabrics",175,13125)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue,13125)
    equal(#sent,1); local_quote(174,"tick"); equal(#sent,2)
end)

test("normal profitable load advances after once rather than buying same commodity", function()
    reset(); cargo(1); local_quote(200); f2t_hauling_phase_sell()
    cargo(0); f2t_bulk_sell_success("NanoFabrics",195,14625)
    equal(completed,1); equal(removed,1); equal(queries,1); equal(#sent,1)
end)

test("post-order quote before text receipt is retained for the next bay", function()
    reset(); cargo(2); sell(); local_quote(190,"tick"); cargo(1)
    f2t_bulk_sell_success("NanoFabrics",200,15000)
    equal(#sent,2); equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue,15000)
end)

test("changing purchase prices sum real receipt costs", function()
    reset(); buy(); cargo(1); matches={"", "NanoFabrics", "7,500"}; trigger("buy_success")
    cargo(2); matches={"", "NanoFabrics", "7,650"}; trigger("buy_success")
    cargo(3); matches={"", "NanoFabrics", "7,800"}; trigger("buy_success")
    equal(F2T_HAULING_STATE.current_commodity_stats.total_cost,22950)
    equal(F2T_HAULING_STATE.actual_cost,102); equal(navigated[1],"Buyer A")
    equal(#sent,1,"counted bulk purchase preserved")
end)

test("premium scans once to buy then refreshes buyers after confirmed purchase cost", function()
    reset(); F2T_HAULING_STATE.rotation="top_base_21"; buy()
    analysis.top_buy={row("Fresh Buyer",180),row("Backup Buyer",170)}
    for i=1,3 do cargo(i); f2t_bulk_buy_success(7500) end
    equal(queries,2,"one supplier scan plus one post-purchase buyer scan")
    equal(navigated[1],"Fresh Buyer"); equal(#navigated,1)
    equal(F2T_HAULING_STATE.current_phase,"navigating_to_sell")
    equal(#sent,1,"bulk purchase command remains counted")
end)

test("premium post-purchase scan rejects buyers below the confirmed whole-load cost", function()
    reset(); F2T_HAULING_STATE.rotation="top_base_21"; buy()
    analysis.top_buy={row("Stale Buyer",101),row("Lower Buyer",99)}
    cargo(1); f2t_bulk_buy_success(7500)
    cargo(2); f2t_bulk_buy_success(7650)
    cargo(3); f2t_bulk_buy_success(7800)
    equal(queries,2); equal(stopped,1); equal(#navigated,0)
    equal(#gmcp.char.ship.cargo,3,"cargo preserved")
    equal(table.concat(output):find("using confirmed load cost",1,true)~=nil,true)
end)

test("premium buyer failure exhausts retained alternatives then refreshes once with bays remaining", function()
    reset(); F2T_HAULING_STATE.rotation="top_base_21"; buy()
    analysis.top_buy={row("Fresh Buyer",180),row("Backup Buyer",170)}
    for i=1,3 do cargo(i); f2t_bulk_buy_success(7500) end
    equal(queries,2); equal(navigated[1],"Fresh Buyer")
    sell(); trigger("sell_error_not_buying")
    equal(navigated[2],"Backup Buyer"); equal(queries,2,"retained buyer needs no poll")
    analysis.top_buy={row("Fresh Buyer",180),row("Backup Buyer",170),row("Rescan Buyer",160)}
    sell(); trigger("sell_error_not_buying")
    equal(queries,3,"only exhausted retained buyers trigger the extra scan")
    equal(navigated[3],"Rescan Buyer"); equal(stopped,0)
    equal(#gmcp.char.ship.cargo,3,"remaining bays retained throughout")
end)

test("premium pause after purchase defers the buyer refresh until explicit resume", function()
    reset(); F2T_HAULING_STATE.rotation="top_base_21"; buy()
    analysis.top_buy={row("Fresh Buyer",180)}
    F2T_HAULING_STATE.paused=true
    for i=1,3 do cargo(i); f2t_bulk_buy_success(7500) end
    equal(queries,1); equal(#navigated,0)
    equal(F2T_HAULING_STATE.current_phase,"selecting_sell")
    F2T_HAULING_STATE.paused=false
    f2t_hauling_transition("selecting_sell")
    equal(queries,2); equal(navigated[1],"Fresh Buyer")
end)

test("unverifiable purchase receipts stop instead of estimating first-bay cost", function()
    reset(); buy(); cargo(1); f2t_bulk_buy_success(); trigger("buy_error_not_selling")
    equal(stopped,1); equal(#navigated,0); equal(F2T_HAULING_STATE.current_commodity_stats.total_cost,0)
end)

test("forced pause records purchase cost and holds navigation for resume", function()
    reset(); buy(); cargo(1); F2T_HAULING_STATE.paused=true
    f2t_bulk_buy_success(7500); trigger("buy_error_not_selling")
    equal(F2T_HAULING_STATE.current_commodity_stats.total_cost,7500)
    equal(#navigated,0); equal(F2T_HAULING_STATE.current_phase,"navigating_to_sell")
end)

test("completed session profit equals actual purchase and sale receipts", function()
    reset(); buy()
    for i=1,3 do cargo(i); f2t_bulk_buy_success(7350+i*150) end
    local saved_complete=f2t_hauling_complete_commodity_cycle
    f2t_hauling_complete_commodity_cycle=real_complete_cycle
    function f2t_is_rank_exactly() return false end
    F2T_HAULING_STATE.session_profit=0; F2T_HAULING_STATE.commodity_total_profit=0
    F2T_HAULING_STATE.total_cycles=0
    sell()
    for remaining=2,0,-1 do
        cargo(remaining); matches={"", "NanoFabrics", tostring(13500+remaining*750)}
        trigger("sell_success")
        if remaining>0 then local_quote(180+remaining*10,"tick") end
    end
    equal(F2T_HAULING_STATE.session_profit,19800)
    equal(F2T_HAULING_STATE.total_cycles,1); equal(removed,1)
    f2t_hauling_complete_commodity_cycle=saved_complete
end)

test("forced pause at a zero-fill refusal resumes with another supplier", function()
    reset(); buy(); F2T_HAULING_STATE.paused=true; trigger("buy_error_not_selling")
    equal(#navigated,0); equal(F2T_HAULING_STATE.current_phase,"finding_buy")
    F2T_HAULING_STATE.paused=false; f2t_hauling_transition("finding_buy")
    equal(navigated[1],"Supplier B"); equal(#sent,1)
end)

test("fourteen-bay full GMCP ahead of text waits for the final receipt", function()
    reset(); gmcp.char.ship.hold={cur=1050,max=1050}; buy()
    cargo(14); gmcp.char.ship.hold={cur=0,max=1050}
    for i=1,13 do
        f2t_bulk_buy_success(7500+75*i)
        equal(stopped,0); equal(#navigated,0); equal(F2T_BULK_STATE.active,true)
    end
    f2t_bulk_buy_success(8550)
    equal(navigated[1],"Buyer A"); equal(#navigated,1); equal(stopped,0)
    equal(F2T_HAULING_STATE.current_commodity_stats.lots_bought,14)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_cost,112875)
    equal(sent[1],"buy nanofabrics 14"); equal(#sent,1); no_timer()
end)

test("complete receipts wait for delayed cargo then navigate only once", function()
    reset(); buy()
    for i=1,3 do f2t_bulk_buy_success(7500+75*i) end
    equal(stopped,0); equal(#navigated,0); equal(F2T_HAULING_STATE.current_phase,"waiting_buy_cargo")
    cargo(2); f2t_hauling_purchase_observe(); equal(#navigated,0)
    cargo(3); f2t_hauling_purchase_observe(); f2t_hauling_purchase_observe()
    equal(#navigated,1); equal(F2T_HAULING_STATE.current_commodity_stats.total_cost,22950)
    equal(#sent,1); no_timer()
end)

test("partial refusal waits for its purchased cargo without trying another supplier", function()
    reset(); buy(); f2t_bulk_buy_success(7575); trigger("buy_error_not_selling")
    equal(stopped,0); equal(#navigated,0); equal(F2T_HAULING_STATE.current_phase,"waiting_buy_cargo")
    cargo(1); f2t_hauling_purchase_observe()
    equal(navigated[1],"Buyer A"); equal(#sent,1)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_cost,7575); no_timer()
end)

test("repeated buying transition preserves pending cargo settlement without replay", function()
    reset(); buy(); for i=1,3 do f2t_bulk_buy_success(7500) end
    f2t_hauling_transition("buying")
    equal(F2T_HAULING_STATE.current_phase,"waiting_buy_cargo"); equal(#sent,1)
    cargo(3); f2t_hauling_purchase_observe()
    equal(#navigated,1); equal(stopped,0); equal(#sent,1); no_timer()
end)

test("missing post-receipt cargo has a bounded stop without duplicate purchases", function()
    reset(); buy(); for i=1,3 do f2t_bulk_buy_success(7500) end
    local timer=F2T_HAULING_STATE.purchase_settlement.timer
    equal(timer.seconds,5); timers[timer]=nil; timer.callback()
    equal(stopped,1); equal(#navigated,0); equal(#sent,1)
    equal(F2T_HAULING_STATE.purchase_settlement,nil)
    cargo(3); f2t_hauling_purchase_observe(); equal(#navigated,0); no_timer()
end)

test("full cargo cannot replace missing text receipts at watchdog expiry", function()
    reset(); buy(); cargo(3); f2t_bulk_buy_success(7500)
    equal(stopped,0); equal(#navigated,0)
    local timer=F2T_BULK_STATE.watchdogTimerId; timers[timer]=nil; timer.callback()
    equal(stopped,1); equal(#navigated,0); equal(#sent,1); equal(#gmcp.char.ship.cargo,3)
end)

test("resuming while counted replies are in flight never repeats the buy", function()
    reset(); buy(); f2t_bulk_buy_success(7500)
    F2T_HAULING_STATE.paused=true; F2T_HAULING_STATE.paused=false
    f2t_hauling_transition("buying"); equal(#sent,1)
    cargo(3); f2t_bulk_buy_success(7500); f2t_bulk_buy_success(7500)
    equal(#sent,1); equal(#navigated,1); equal(stopped,0); no_timer()
end)

test("forced pause during cargo settlement records costs but holds navigation", function()
    reset(); buy(); for i=1,3 do f2t_bulk_buy_success(7500) end
    F2T_HAULING_STATE.paused=true; cargo(3); f2t_hauling_purchase_observe()
    equal(F2T_HAULING_STATE.current_commodity_stats.total_cost,22500)
    equal(#navigated,0); equal(F2T_HAULING_STATE.current_phase,"navigating_to_sell")
    F2T_HAULING_STATE.paused=false; f2t_hauling_transition("navigating_to_sell")
    equal(#navigated,1); equal(#sent,1); no_timer()
end)

test("deferred stamina pause occurs after receipt and cargo reconciliation", function()
    reset(); buy(); F2T_HAULING_STATE.pause_requested=true
    for i=1,3 do f2t_bulk_buy_success(7500) end
    equal(F2T_HAULING_STATE.paused,false); equal(#navigated,0)
    cargo(3); f2t_hauling_purchase_observe()
    equal(F2T_HAULING_STATE.paused,true); equal(#navigated,0)
    equal(F2T_HAULING_STATE.current_phase,"navigating_to_sell"); equal(#sent,1); no_timer()
end)

test("cleanup and state replacement invalidate old purchase settlement callbacks", function()
    reset(); buy(); for i=1,3 do f2t_bulk_buy_success(7500) end
    local timer=F2T_HAULING_STATE.purchase_settlement.timer
    f2t_hauling_purchase_cleanup(); cargo(3); timer.callback(); f2t_hauling_purchase_observe()
    equal(#navigated,0); equal(stopped,0); no_timer()
    F2T_HAULING_STATE={active=true,current_commodity="Woods",current_phase="buying"}
    timer.callback(); equal(#sent,1); equal(stopped,0)
end)

test("real parent ship event settles and handler cleanup removes the wait", function()
    reset(); local handlers={}; local serial=0
    function registerAnonymousEventHandler(event,callback)
        serial=serial+1; handlers[serial]={event=event,callback=callback}; return serial
    end
    function killAnonymousEventHandler(id) handlers[id]=nil end
    local id=f2t_exchange_register_handlers()
    buy(); for i=1,3 do f2t_bulk_buy_success(7500) end
    cargo(3)
    for _,handler in pairs(handlers) do if handler.event=="gmcp.char.ship" then handler.callback() end end
    equal(#navigated,1); equal(#sent,1); no_timer()
    f2t_exchange_cleanup_handlers(id); equal(next(handlers),nil)
    equal(F2T_HAULING_STATE.purchase_settlement,nil)
end)

local function library_cargo(count, cost)
    cargo(count)
    for _,lot in ipairs(gmcp.char.ship.cargo) do lot.commodity="Libraries"; lot.cost=cost or 400 end
end
local function library_quote()
    seed_load_receipts()
    gmcp.room.info={flags={"exchange"},num=1,area="Bio",system="Candy"}
    gmcp.exchange={commodities={Libraries={buy=659}}}
    f2t_hauling_recovery_observe("full")
end
local function library_receipt()
    matches={"The Candy cartel deducts 11,430ig customs from the 49,425ig sale proceeds, leaving 37,995ig net."}
    trigger("sell_customs")
    matches={"75 tons of Libraries sold for 49425ig from your ship","Libraries","49425"}
    trigger("sell_success")
end
local function library_sale(cost)
    reset(); F2T_HAULING_STATE.current_commodity="Libraries"
    F2T_HAULING_STATE.sell_location={planet="Bio",system="Candy",price=659}
    library_cargo(3,cost); library_quote(); f2t_hauling_phase_sell()
end

test("reported taxed ship sales reconcile once and continue to the next commodity", function()
    library_sale()
    for remaining=2,0,-1 do
        library_cargo(remaining); library_receipt()
        equal(stopped,0,"successful sale does not stop hauling")
        if remaining>0 then library_quote() end
    end
    equal(#sent,3); equal(sent[1],"sell libraries 1"); equal(sent[3],"sell cargo")
    equal(F2T_HAULING_STATE.current_commodity_stats.lots_sold,3)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue,113985)
    equal(completed,1); equal(removed,1); no_timer()
end)

test("taxed text receipt before cargo waits without retry and accepts a preceding price update", function()
    library_sale(); library_quote(); library_receipt()
    equal(#sent,1); equal(stopped,0)
    library_cargo(2); f2t_hauling_recovery_observe("cargo")
    equal(#sent,2,"one new bay after settled first sale")
    equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue,37995)
end)

test("customs making net proceeds below cost preserves remaining cargo and records net", function()
    library_sale(600); library_cargo(2,600); library_receipt()
    equal(stopped,0); equal(#sent,1); equal(#gmcp.char.ship.cargo,2)
    equal(F2T_HAULING_STATE.current_commodity_stats.lots_sold,1)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue,37995)
    library_quote()
    equal(stopped,1,"no remaining buyer meets whole-load target"); equal(#sent,1)
    equal(table.concat(output):find("whole load",1,true)~=nil,true)
    no_timer()
end)

test("reported thirteen-lot Crystals load clears at 803 despite its 830-cost bay", function()
    reset(); F2T_HAULING_STATE.current_commodity="Crystals"
    F2T_HAULING_STATE.exchange_market.commodity="Crystals"
    F2T_HAULING_STATE.sell_location={planet="P10",system="System",price=803}
    gmcp.char.ship.hold={cur=1050,max=1050}; buy()
    gmcp.char.ship.cargo={}
    for i=1,13 do
        local cost=i<=11 and 740 or (i==12 and 722 or 830)
        gmcp.char.ship.cargo[i]={commodity="Crystals",cost=cost,origin="Supplier A"}
        f2t_bulk_buy_success(cost*75)
    end
    trigger("buy_error_not_selling")
    equal(F2T_HAULING_STATE.current_commodity_stats.total_cost,726900)
    equal(navigated[1],"P10"); equal(#sent,1); equal(sent[1],"buy crystals 14")
    sell()
    for remaining=12,0,-1 do
        table.remove(gmcp.char.ship.cargo,1)
        matches={"75 tons of Crystals sold for 60225ig from your ship","Crystals","60225"}
        trigger("sell_success")
        equal(stopped,0,"no per-bay cost veto")
        if remaining>0 then local_quote(803,"tick") end
    end
    local stats=F2T_HAULING_STATE.current_commodity_stats
    equal(stats.lots_sold,13); equal(stats.total_revenue,782925)
    equal(stats.total_revenue-stats.total_cost,56025)
    equal(#sent,14,"one counted buy and thirteen guarded sales")
    equal(completed,1); equal(removed,1); no_timer()
end)

test("completed sales fund later below-individual-cost bays within the same load", function()
    reset(); cargo(2)
    for _,lot in ipairs(gmcp.char.ship.cargo) do lot.cost=830 end
    F2T_HAULING_STATE.current_commodity_stats={lots_bought=3,lots_sold=1,total_cost=180000,total_revenue=100000}
    local_quote(600); f2t_hauling_phase_sell()
    equal(#sent,1)
    cargo(1); gmcp.char.ship.cargo[1].cost=830
    f2t_bulk_sell_success("NanoFabrics",600,45000); local_quote(500,"tick")
    equal(#sent,2); equal(stopped,0)
    cargo(0); f2t_bulk_sell_success("NanoFabrics",500,37500)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue-180000,2500)
    equal(completed,1); no_timer()
end)

test("whole-load target accepts two groats but not one groat or zero", function()
    for _,profit in ipairs({0,1,2}) do
        reset(); cargo(1); local_quote(100)
        F2T_HAULING_STATE.current_commodity_stats.total_cost=7500-profit
        f2t_hauling_phase_sell()
        equal(#sent,profit>1 and 1 or 0,"whole-load profit "..profit)
    end
end)

test("previous sessions or cycles cannot subsidize a losing current load", function()
    reset(); cargo(1); local_quote(99)
    F2T_HAULING_STATE.session_profit=1000000000
    F2T_HAULING_STATE.commodity_total_profit=1000000000
    equal(f2t_hauling_cargo_floor()>100,true)
    f2t_hauling_phase_sell(); equal(#sent,0)
end)

test("missing or inconsistent receipt ledger cannot fall back to a cheap bay", function()
    for _,kind in ipairs({"missing","count","nan"}) do
        reset(); cargo(2); local_quote(200)
        if kind=="missing" then F2T_HAULING_STATE.current_commodity_stats=nil
        elseif kind=="count" then F2T_HAULING_STATE.current_commodity_stats.lots_bought=3
        else F2T_HAULING_STATE.current_commodity_stats.total_cost=0/0 end
        f2t_hauling_phase_sell(); equal(#sent,0); equal(stopped,1)
    end
end)

test("a fully recovered purchase cost permits any positive remaining bid", function()
    reset(); cargo(1)
    F2T_HAULING_STATE.current_commodity_stats={lots_bought=2,lots_sold=1,total_cost=15000,total_revenue=15002}
    local_quote(1); f2t_hauling_phase_sell(); equal(#sent,1)
    cargo(0); f2t_bulk_sell_success("NanoFabrics",1,75)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue-15000,77)
    equal(completed,1); equal(stopped,0); no_timer()
end)

test("known customs is scoped to the buyer and deducted from future projections", function()
    library_sale(600); library_cargo(2,600); library_receipt()
    local without_customs=f2t_hauling_cargo_floor()
    equal(f2t_hauling_buyer_floor(F2T_HAULING_STATE.sell_location)>659,true)
    equal(f2t_hauling_buyer_floor({planet="Other",system="Candy"}),without_customs)
    equal(f2t_hauling_buyer_floor({planet="Bio",system="Other"}),without_customs)
    equal(math.floor((f2t_hauling_buyer_floor(F2T_HAULING_STATE.sell_location)-without_customs)*75+0.5),11430)
end)

test("safe-room stop invalidates settlement and still-arriving bulk callbacks immediately", function()
    local saved_settings, saved_navigate = f2t_settings_get, f2t_map_navigate
    function f2t_settings_get(_, name)
        if name=="use_safe_room" then return true end
        if name=="safe_room" then return "Safe room" end
    end
    local safe_trips=0
    function f2t_map_navigate() safe_trips=safe_trips+1 end
    local ok, err=pcall(function()
        reset(); buy(); for i=1,3 do f2t_bulk_buy_success(7500) end
        local settlement_timer=F2T_HAULING_STATE.purchase_settlement.timer
        real_do_stop()
        equal(F2T_HAULING_STATE.purchase_settlement,nil); equal(timers[settlement_timer],nil)
        cargo(3); f2t_hauling_purchase_observe(); settlement_timer.callback()
        equal(#navigated,0); equal(#sent,1); equal(safe_trips,1)

        reset(); buy(); f2t_bulk_buy_success(7500); real_do_stop()
        cargo(3); f2t_bulk_buy_success(7500); f2t_bulk_buy_success(7500)
        equal(F2T_HAULING_STATE.purchase_settlement,nil)
        equal(#navigated,0); equal(#sent,1); equal(safe_trips,2)
    end)
    f2t_settings_get, f2t_map_navigate = saved_settings, saved_navigate
    if not ok then error(err) end
end)

print(string.format("RESULT %d passed, %d failed",passed,failed))
if failed > 0 then os.exit(1) end
