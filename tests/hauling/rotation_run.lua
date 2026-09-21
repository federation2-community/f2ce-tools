-- Real persistence and queue code, isolated IO/JSON stand-ins; no live profiles.
local root = tostring(arg and arg[1] or ".")
local files, encoded, serial, fault, home, output, catalog, reviews, trips, stopped
local passed, failed = 0, 0
local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}; for k,v in pairs(t) do out[k] = copy(v) end; return out
end
local function eq(a,b) assert(a==b, "expected "..tostring(b)..", got "..tostring(a)) end
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed=passed+1; print("PASS "..name)
    else failed=failed+1; print("FAIL "..name..": "..tostring(err)) end
end
function getMudletHomeDir() return home end
function f2t_get_all_commodities() return catalog end
function f2t_get_highest_base_commodities(limit)
    local selected = {}; for i=1,limit do selected[i]=catalog[i] end; return selected
end
function cecho(s) output[#output+1]=s end
function f2t_debug_log() end
function f2t_settings_get(_, key) if key == "excluded_commodities" then return "" end return 0 end
function f2t_price_get_all_data(callback) callback(reviews) end
function f2t_hauling_stop() f2t_hauling_do_stop() end
function f2t_hauling_do_stop() stopped=stopped+1; F2T_HAULING_STATE.active=false end
local function reload()
    dofile(root.."/src/scripts/hauling/exchange_rotation.lua")
    dofile(root.."/src/scripts/hauling/exchange_phases.lua")
    function f2t_hauling_get_commodity_details(name) trips[#trips+1]=name end
end
local function state()
    F2T_HAULING_STATE={active=true,paused=false,queue_index=1,commodity_queue={},commodity_history={}}
end
local function reset()
    files,encoded,serial,fault,home,output,catalog,reviews,trips,stopped={},{},0,{},"profile-a",{},{},{},{},0
    for i=1,67 do
        catalog[i]="C"..i
        reviews[i]={commodity=catalog[i],profit=1000-i,top_buy={{price=200}},top_sell={{price=100}}}
    end
    yajl={to_string=function(t) serial=serial+1; local key="JSON"..serial; encoded[key]=copy(t); return key end,
        to_value=function(s) return assert(copy(encoded[s]),"invalid JSON") end}
    io={open=function(p, mode)
        if fault.open or (mode=="wb" and fault.write_open) then return nil,"denied",13 end
        if mode=="rb" and not files[p] then return nil,"missing",2 end
        if mode=="wb" then files[p]="" end
        return {read=function(_, n) return type(n)=="number" and files[p]:sub(1,n) or files[p] end,
            write=function(_,s)
                if fault.write then files[p]="partial"; return nil end
                files[p]=s; return true
            end,
            close=function() return not fault.close end}
    end}
    reload(); state()
end
local function queue() return f2t_hauling_rotation_queue(reviews,{}) end
local function p(slot) return home.."/f2ce-hauling-rotation-v1-"..slot..".json" end

test("initial review queues all 67 rather than five",function()
    reset(); local rows,round,total=queue(); eq(#rows,67); eq(round,1); eq(total,67)
    eq(files[p("a")],files[p("b")]); eq(#trips,0)
end)
test("67 unique attempts across repeated stops reconnects and package reloads",function()
    reset()
    for i=1,67 do
        state(); reload(); f2t_hauling_phase_analyze()
        eq(trips[i],"C"..i); eq(#F2T_HAULING_STATE.commodity_queue,68-i)
        F2T_HAULING_STATE.active=false
    end
    local rows,round=queue(); eq(#rows,67); eq(round,2); eq(#trips,67)
end)
test("claim is durable before any detail request or travel",function()
    reset(); f2t_hauling_phase_analyze(); eq(trips[1],"C1")
    local rows=queue(); eq(#rows,66); eq(rows[1].commodity,"C2")
end)
test("loading or viewing progress cannot resume automation",function()
    reset(); queue(); assert(f2t_hauling_rotation_claim("C1"))
    F2T_HAULING_STATE.active=false; reload(); f2t_hauling_rotation_status()
    eq(F2T_HAULING_STATE.active,false); eq(#trips,0)
    assert(table.concat(output):find("1/67",1,true))
end)
test("rotation is profile isolated",function()
    reset(); queue(); assert(f2t_hauling_rotation_claim("C1"))
    home="profile-b"; eq(#queue(),67); home="profile-a"; eq(#queue(),66)
end)
test("unprofitable unavailable and excluded rows are reviewed without buying",function()
    reset(); reviews[2].profit=0; reviews[3].top_buy={}
    local rows=f2t_hauling_rotation_queue(reviews,{c4=true})
    eq(#rows,64); assert(f2t_hauling_rotation_claim("C1")); eq(#queue(),63)
    eq(f2t_hauling_rotation_claim("C4"),nil)
end)
test("whole catalog review is mandatory before resetting a round",function()
    reset(); queue(); assert(f2t_hauling_rotation_claim("C1"))
    table.remove(reviews); eq(queue(),nil)
    eq(f2t_hauling_rotation_claim("C1"),nil)
end)
test("duplicate review cannot hide a missing commodity",function()
    reset(); reviews[67]=reviews[1]; eq(queue(),nil); eq(next(files),nil)
end)
test("catalog growth is included without resetting existing attempts",function()
    reset(); queue(); assert(f2t_hauling_rotation_claim("C1"))
    catalog[68]="NewCommodity"; reviews[68]={commodity="NewCommodity",profit=1,top_buy={{}},top_sell={{}}}
    local rows,round,total=queue(); eq(#rows,67); eq(round,1); eq(total,68)
end)
test("one corrupt copy recovers latest saved attempts from the other",function()
    reset(); queue(); assert(f2t_hauling_rotation_claim("C1")); files[p("b")]="partial"
    reload(); local rows=queue(); eq(#rows,66); eq(files[p("a")],files[p("b")])
end)
test("both corrupt copies stop rather than silently restart rotation",function()
    reset(); queue(); files[p("a")]="bad"; files[p("b")]="bad"
    f2t_hauling_phase_analyze(); eq(stopped,1); eq(#trips,0)
end)
test("read permissions are not mistaken for an empty new profile",function()
    reset(); fault.open=true; eq(queue(),nil); eq(next(files),nil)
end)
test("failed save prevents first commodity travel",function()
    reset(); fault.write_open=true; f2t_hauling_phase_analyze()
    eq(stopped,1); eq(#trips,0)
end)
test("failed claim write blocks travel and keeps the other checkpoint",function()
    reset(); queue(); F2T_HAULING_STATE.commodity_queue={{commodity="C1",expected_profit=10}}
    fault.write=true; f2t_hauling_next_commodity(); eq(stopped,1); eq(#trips,0)
    fault.write=false; reload(); eq(#queue(),67)
end)
test("failed close cannot authorize travel",function()
    reset(); queue(); fault.close=true
    F2T_HAULING_STATE.commodity_queue={{commodity="C1",expected_profit=10}}
    f2t_hauling_next_commodity(); eq(stopped,1); eq(#trips,0)
end)
test("all-unprofitable catalog stops with no purchase loop",function()
    reset(); for _,row in ipairs(reviews) do row.profit=0 end
    f2t_hauling_phase_analyze(); eq(stopped,1); eq(#trips,0)
end)
test("unknown or invalid schema is not accepted as a new rotation",function()
    reset(); files[p("a")]=yajl.to_string({schema=2,revision=1,round=1,done={}})
    eq(queue(),nil)
end)
test("completed load advances within the same run and saves the next attempt",function()
    reset(); f2t_hauling_phase_analyze(); eq(trips[1],"C1")
    f2t_hauling_finish_remove_commodity(); eq(trips[2],"C2"); eq(#queue(),65)
end)
test("late analysis from a replaced run cannot save or select its queue",function()
    reset(); local original=f2t_price_get_all_data; local callback
    f2t_price_get_all_data=function(cb) callback=cb end
    f2t_hauling_phase_analyze(); state(); callback(reviews)
    eq(#trips,0); eq(next(files),nil); f2t_price_get_all_data=original
end)
test("invalid review objects fail without overwriting existing progress",function()
    reset(); queue(); assert(f2t_hauling_rotation_claim("C1"))
    local before=files[p("a")]; reviews[1]="bad"; eq(queue(),nil); eq(files[p("a")],before)
end)
test("premium rotation visits 21 once across stops reconnects and reloads",function()
    reset()
    for i=1,21 do
        state(); reload(); F2T_HAULING_STATE.rotation="top_base_21"
        f2t_hauling_phase_analyze(); eq(trips[i],"C"..i)
        eq(#F2T_HAULING_STATE.commodity_queue,22-i)
        F2T_HAULING_STATE.active=false
    end
    local rows,round,total=queue(); eq(#rows,21); eq(round,2); eq(total,21)
end)

test("67 to 21 migration preserves selected attempts without requiring the other 46",function()
    reset(); queue(); assert(f2t_hauling_rotation_claim("C1")); assert(f2t_hauling_rotation_claim("C67"))
    reload(); F2T_HAULING_STATE.rotation="top_base_21"
    local rows,round,total=queue(); eq(#rows,20); eq(round,1); eq(total,21)
    for i=2,21 do assert(f2t_hauling_rotation_claim("C"..i)) end
    rows,round=queue(); eq(#rows,21); eq(round,2)
end)

test("premium queues the saved twenty-one without a cycle-start price sweep",function()
    reset(); F2T_HAULING_STATE.rotation="top_base_21"
    local original=f2t_price_get_all_data; local sweeps=0
    f2t_price_get_all_data=function() sweeps=sweeps+1; return false end
    f2t_hauling_phase_analyze(); f2t_price_get_all_data=original
    eq(sweeps,0); eq(#F2T_HAULING_STATE.commodity_queue,21); eq(trips[1],"C1")
    assert(table.concat(output):find("price-scanned only when processed",1,true))
    f2t_hauling_rotation_status(); assert(table.concat(output):find("1/21",1,true))
end)

test("premium advances one commodity at a time without rescanning the batch",function()
    reset(); F2T_HAULING_STATE.rotation="top_base_21"
    local original=f2t_price_get_all_data; local sweeps=0
    f2t_price_get_all_data=function() sweeps=sweeps+1; return false end
    f2t_hauling_phase_analyze(); eq(#trips,1); eq(trips[1],"C1")
    f2t_hauling_finish_remove_commodity(); eq(#trips,2); eq(trips[2],"C2"); eq(sweeps,0)
    f2t_price_get_all_data=original
end)

test("premium exclusions are durably reviewed without a price request",function()
    reset(); F2T_HAULING_STATE.rotation="top_base_21"
    local rows,round,total=f2t_hauling_rotation_queue_catalog({c2=true})
    eq(#rows,20); eq(round,1); eq(total,21); eq(f2t_hauling_rotation_claim("C2"),nil)
    eq(files[p("a")],files[p("b")])
end)

test("regular hauling after premium still includes the other 46",function()
    reset(); F2T_HAULING_STATE.rotation="top_base_21"; queue(); assert(f2t_hauling_rotation_claim("C1"))
    state(); local rows,round,total=queue(); eq(#rows,66); eq(round,1); eq(total,67)
end)

print(string.format("RESULT %d passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end
