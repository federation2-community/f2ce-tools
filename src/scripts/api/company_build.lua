-- One explicitly confirmed factory, at the current exchange. No navigation,
-- retries or automatic growth loop. Consumer authorization must durably record
-- intent when company.factory.buy is requested immediately before the send.
local API,S=F2CE.API.v1,F2CE.API.v1.services
local COST=2000000
-- BuyDepot -> AddDepot immediately charges 7 * minimum wage 40 * 16.
local DEPOT_COST,DEPOT_WORKERS=1004480,7
API.company.factorySiteVersion=1
API.company.factoryPriceReviewVersion=1
API.company.factoryAutomationVersion=1
API.company.factoryCompetitionVersion=1
local limits={Industrialist=8,Manufacturer=15}
local function norm(v) return type(v)=="string" and v:lower() or "" end
local function integer(v,lo,hi) return type(v)=="number" and v==math.floor(v) and v>=lo and v<=hi end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end; return true
end
local function failure(message) return S.error("E_FACTORY_BUILD",message) end
local function location(options)
    local room=API.data.get("room")
    if type(room)~="table" or norm(room.area)~=norm(options.planet) or norm(room.system)~=norm(options.system)
        or not integer(tonumber(room.num),0,99999999) or type(room.flags)~="table" then return nil end
    local exchange=false
    for k,v in pairs(room.flags) do
        if v=="space" or (k=="space" and v==true) then return nil end
        if v=="exchange" or (k=="exchange" and v==true) then exchange=true end
    end
    return exchange and norm(room.system).."\0"..norm(room.area).."\0"..room.num or nil
end
local function snapshot(options)
    local company,why=API.company.snapshot(); if not company then return nil,why end
    local vitals=API.data.get("vitals") or {}; local limit=limits[vitals.rank]
    local where=location(options)
    if not limit or not where then return nil,failure("Industrialist/Manufacturer at the selected exchange required") end
    if not integer(company.cash,0,10000000000) then return nil,failure("company cash unavailable") end
    local roster,slot,count,local_factory,local_count={},nil,0,false,0
    for _,f in pairs(company.factories) do
        if type(f)~="table" or not integer(f.number,1,limit) or roster[f.number]
            or not S.name(f.planet,true) or not S.name(f.output) then return nil,failure("invalid company factory roster") end
        roster[f.number]={number=f.number,planet=f.planet,output=f.output}
        count=count+1; local_factory=local_factory or norm(f.planet)==norm(options.planet)
        if norm(f.planet)==norm(options.planet) then local_count=local_count+1 end
    end
    for i=1,limit do if not roster[i] then slot=i; break end end
    if count>=math.min(limit,options.factory_limit or limit) then slot=nil end
    local depots,depot_count={},0
    if options.require_depot then
        if type(company.depots)~="table" then return nil,failure("owned depot roster unavailable") end
        for _,planet in pairs(company.depots) do
            if not S.name(planet,true) or depots[norm(planet)] then return nil,failure("invalid owned depot roster") end
            depots[norm(planet)]=true; depot_count=depot_count+1
        end
    end
    return {owner=company.name,ceo=company.ceo,rank=vitals.rank,location=where,roster=roster,slot=slot,cash=company.cash,
        depots=depots,depot_count=depot_count,local_factory=local_factory,local_count=local_count}
end
local function validate_options(o)
    if type(o)~="table" or not S.name(o.planet,true) or not S.name(o.system,true) or norm(o.system)=="sol"
        or type(o.commodity)~="string" or not o.commodity:match("^[%a][%w]*$") or #o.commodity>40
        or not integer(o.company_reserve,0,10000000000) or not integer(o.labour,0,1000000)
        or type(o.biological_required)~="boolean" or not integer(o.output_price_floor,1,1000000)
        or type(o.inputs)~="table" or #o.inputs>6 then return false end
    if o.require_depot~=nil and type(o.require_depot)~="boolean" then return false end
    if o.depot_only~=nil and type(o.depot_only)~="boolean" then return false end
    if o.review_prices~=nil and type(o.review_prices)~="boolean" then return false end
    if o.exclude_existing_commodity~=nil and type(o.exclude_existing_commodity)~="boolean" then return false end
    if o.factory_limit~=nil and not integer(o.factory_limit,1,15) then return false end
    if o.automation then
        if o.automation~=true or not integer(o.wages,1,1000000)
            or not integer(o.planet_limit,1,2) or not integer(o.factory_limit,1,8)
            or o.require_depot~=true or not integer(o.reserved_workers,0,10000000) then return false end
    elseif o.wages~=nil or o.planet_limit~=nil or o.reserved_workers~=nil then return false end
    if o.depot_only and (not o.require_depot or o.labour~=0 or #o.inputs~=0 or o.commodity~="Depot") then return false end
    local seen={}
    for _,input in ipairs(o.inputs) do
        if type(input)~="table" or not S.name(input.commodity) or seen[norm(input.commodity)]
            or not integer(input.required,1,1000000) or not integer(input.price_limit,1,1000000)
            or not integer(input.minimum_stock,5000,1000000000) then return false end
        seen[norm(input.commodity)]=true
    end
    return true
end
local function ready(state,report,o,review_prices)
    local needs_depot=o.require_depot==true and not state.depots[norm(o.planet)]
    if o.depot_only then
        if not state.local_factory or not needs_depot then return nil,failure("depot-only build requires an owned factory and no depot on this planet") end
    elseif not state.slot then return nil,failure("no free factory slot under the configured limit")
    elseif o.automation and state.local_count>=o.planet_limit then return nil,failure("two-factory planet limit reached") end
    if needs_depot and state.depot_count>=(state.rank=="Industrialist" and 16 or 15) then return nil,failure("no free depot slot") end
    local cost=(o.depot_only and 0 or COST)+(needs_depot and DEPOT_COST or 0)
    local labour=o.labour+(needs_depot and DEPOT_WORKERS or 0)+(o.reserved_workers or 0)
    if state.cash-cost<o.company_reserve then return nil,failure("factory/depot construction cost would breach company reserve") end
    local stamina=API.data.get("stamina")
    local threshold=math.max(25,tonumber(API.settings.get("stamina","threshold")) or 0)
    if type(stamina)~="table" or not integer(tonumber(stamina.max),1,1000000)
        or not integer(tonumber(stamina.cur),0,tonumber(stamina.max))
        or tonumber(stamina.cur)*100/tonumber(stamina.max)<=threshold
        or (API.protection and API.protection.isRecovering()) then return nil,failure("recover stamina/death protection before construction") end
    local workers=report and report.planets and report.planets[norm(o.planet)]
    if not o.depot_only and (o.automation or o.exclude_existing_commodity) then
        if not workers or workers.factories_verified~=true or type(workers.factories)~="table" then
            return nil,failure("public planet factory list unavailable; duplicate commodity exclusion cannot be verified")
        end
        for _,f in pairs(state.roster) do
            if norm(f.planet)==norm(o.planet) and norm(f.output)==norm(o.commodity) then
                return nil,failure("planet already has a "..o.commodity.." factory; no duplicate commodity build")
            end
        end
        for _,f in ipairs(workers.factories) do
            if norm(f.output)==norm(o.commodity) then
                return nil,failure("planet already has a "..o.commodity.." factory ("..f.owner.."); no duplicate commodity build")
            end
        end
    end
    if not workers or norm(report.system)~=norm(o.system) or workers.closed
        or not integer(workers.available,0,1000000000) or workers.available<labour
        or workers.economy=="None" or (o.biological_required and workers.economy~="Biological") then
        return nil,failure("workers, economy or visitor access do not qualify")
    end
    local market=API.data.get("commodities"); local normalized={}
    if type(market)~="table" then return nil,failure("local market unavailable") end
    for name,row in pairs(market) do
        local key=norm(name); if normalized[key] then return nil,failure("duplicate local commodity") end
        normalized[key]=row
    end
    local output=normalized[norm(o.commodity)]
    local review
    local contribution=0
    if not o.depot_only then
        if type(output)~="table" or not integer(tonumber(output.buy),1,1000000) then
            return nil,failure("exchange is not buying the factory output")
        end
        local price=tonumber(output.buy)
        contribution=75*price
        if review_prices then
            review={required=price<o.output_price_floor,
                output={commodity=o.commodity,previous_price=o.output_price_floor,current_price=price},inputs={},
                material_before=75*o.output_price_floor,material_now=75*price}
            -- Only a preview may propose worse bounds. They are frozen before
            -- confirmation and included in the consumer authorization payload.
            o.output_price_floor=math.min(o.output_price_floor,price)
        elseif price<o.output_price_floor then
            return nil,failure(string.format("output bid %dig below confirmed minimum %dig; refresh the build preview",price,o.output_price_floor))
        end
    end
    for _,input in ipairs(o.inputs) do
        local row=normalized[norm(input.commodity)]
        if type(row)~="table" or not integer(tonumber(row.stock),input.minimum_stock,1000000000)
            or not integer(tonumber(row.sell),1,1000000) then
            return nil,failure("local input stock/ask unavailable or below required stock: "..input.commodity)
        end
        local price=tonumber(row.sell)
        contribution=contribution-input.required*price
        if review then
            review.required=review.required or price>input.price_limit
            review.inputs[#review.inputs+1]={commodity=input.commodity,previous_price=input.price_limit,current_price=price}
            review.material_before=review.material_before-input.required*input.price_limit
            review.material_now=review.material_now-input.required*price
            input.price_limit=math.max(input.price_limit,price)
        elseif price>input.price_limit then
            return nil,failure(string.format("%s input ask %dig above confirmed maximum %dig; refresh the build preview",input.commodity,price,input.price_limit))
        end
    end
    if o.automation and not o.depot_only and contribution-o.labour*o.wages<=0 then
        return nil,failure("factory no longer has positive material contribution after configured wages")
    end
    return {owner=state.owner,ceo=state.ceo,rank=state.rank,planet=o.planet,system=o.system,commodity=o.commodity,
        slot=o.depot_only and 0 or state.slot,cost=cost,company_cash=state.cash,company_reserve=o.company_reserve,
        depot_needed=needs_depot,depot_only=o.depot_only==true,require_depot=o.require_depot==true,
        after_build=state.cash-cost,workers_available=workers.available,workers_required=labour,economy=workers.economy,
        market_review=review,wages=o.automation and not o.depot_only and o.wages or nil}
end
function API.company.prepareFactory(context,options,callback)
    local o=S.copy(options)
    if not validate_options(o) or type(callback)~="function" then return nil,S.error("E_ARGUMENT","complete bounded construction proposal required") end
    local allowed,why=S.authorize(context,"company.factory.preview",o); if not allowed then return nil,why end
    local initial; initial,why=snapshot(o); if not initial then return nil,why end
    if type(API.company._systemWithLease)~="function" then return nil,S.error("E_CAPABILITY","system workforce API required") end
    local lease; lease,why=API.commands.acquire(context,{service="company.factory.preview"}); if not lease then return nil,why end
    local active,sent,phase=true,false,"reading"
    local token,timer,child,preview,completion,observer
    local subscriptions={}; local epoch=0
    local handle={}
    local function clear()
        epoch=epoch+1
        if timer then API._adapter.cancelTimer(timer); timer=nil end
        if child then child:cancel("build_read_finished"); child=nil end
        if observer then API._adapter.unobserveLine(observer); observer=nil end
        for _,sub in ipairs(subscriptions) do sub:cancel() end; subscriptions={}
    end
    local function cleanup(reason)
        if not active then return false end
        active=false; clear(); lease:release(reason); S.forget(context,token); return true
    end
    function handle:status() return {active=active,phase=phase,sent=sent,uncertain=sent and phase~="confirmed"} end
    function handle:cancel(reason)
        -- Forgetting the owned cleanup token also calls cancel. Do not turn a
        -- settled result back into an uncertain purchase during that cleanup.
        if not active then return true end
        phase=sent and "unconfirmed" or "cancelled"; cleanup(reason or phase); return true
    end
    local function finish(value,err)
        if not active then return end
        phase=value and "confirmed" or (sent and "unconfirmed" or "failed")
        cleanup(phase)
        if err and sent then err=S.error("E_FACTORY_UNCONFIRMED",tostring(err).."; a purchase may have occurred; inspect manually, never retry automatically") end
        if S.live(context) then
            local ok,detail=pcall(completion or callback,value,err)
            if not ok then API.events.emit("api.callback_error",{label="company.factory",error=tostring(detail)}) end
        end
    end
    local function bound(seconds,fn)
        timer=API._adapter.timer(seconds,fn,false)
        if not timer then finish(nil,S.error("E_CAPABILITY","factory timer unavailable")); return false end
        return true
    end
    local function identity(state)
        return state and state.owner==initial.owner and state.ceo==initial.ceo and state.rank==initial.rank and state.location==initial.location
    end
    local function read_all(done)
        clear(); local mine=epoch; local received={}
        local channels={"room","stamina","commodities"}
        local function receive(channel)
            if not active or mine~=epoch then return end
            received[channel]=true
            for _,name in ipairs(channels) do if not received[name] then return end end
            clear()
            local function inspected(report,err)
                child=nil; if not active then return end
                if not report then finish(nil,err); return end
                local state,invalid=snapshot(o)
                if not identity(state) then finish(nil,invalid or failure("owner, rank or exchange changed")); return end
                done(state,report)
            end
            local h,problem
            if not o.depot_only and (o.automation or o.exclude_existing_commodity) then
                if type(API.company._planetWithLease)~="function" then finish(nil,failure("public planet factory inspection unavailable")); return end
                h,problem=API.company._planetWithLease(context,o.planet,o.system,inspected,lease)
            else h,problem=API.company._systemWithLease(context,o.system,inspected,lease) end
            if not h then finish(nil,problem) elseif h:status().active then child=h end
        end
        for _,channel in ipairs(channels) do local name=channel
            subscriptions[#subscriptions+1]=API.events.subscribe("data."..name,function(event) if event.received then receive(name) end end)
        end
        if not bound(15,function() finish(nil,failure("fresh room/stamina/market response timed out")) end) then return end
        for _,command in ipairs({"score","look"}) do
            if not active or epoch~=mine then return end
            local ok,err=lease:send(command,{operation="company.factory.preview",reason="fresh construction state"})
            if not ok then finish(nil,err); return end
        end
    end
    function handle:confirm(done)
        if not active or phase~="ready" or type(done)~="function" then return nil,S.error("E_AUTHORITY","active unexpired factory preview required") end
        completion=done; phase="revalidating"
        read_all(function(before,report)
            local proposal,err=ready(before,report,o)
            if not proposal then finish(nil,err); return end
            if not equal(before.roster,preview.roster) or not equal(before.depots,preview.depots) then finish(nil,failure("factory/depot roster changed since preview")); return end
            -- The explicit consumer authorization records intent durably HERE,
            -- not at preview time. Denial means no purchase is sent.
            local payload=S.copy(o); payload.proposal=proposal
            local allowed,why=S.authorize(context,"company.factory.buy",payload)
            if not allowed then finish(nil,why); return end
            local function set_wages()
                if not o.automation then finish(proposal); return end
                clear(); phase="setting_wages"
                local allowed,why=S.authorize(context,"company.factory.wages",payload)
                if not allowed then finish(nil,why); return end
                if type(API._adapter.observeLine)~="function" or type(API._adapter.parseFactory)~="function" then
                    finish(nil,failure("factory wage verification unavailable")); return
                end
                local rows,started,ack_lines={},false,{}
                local wage_sent=false
                observer=API._adapter.observeLine(function(line)
                    if not active or type(line)~="string" then return end
                    local clean=line:gsub("\27%[[%d;]*m","")
                    if phase=="setting_wages" then
                        -- Buying a factory also prints a complete 0ig-wage
                        -- display. GMCP can arrive before that text is rendered,
                        -- so it is not evidence for the later wage command.
                        -- Fence on its exact, bounded server acknowledgement.
                        if not wage_sent then return end
                        clean=clean:gsub("%s+"," "):match("^%s*(.-)%s*$")
                        if clean:match("^The wages") then ack_lines={clean}
                        elseif #ack_lines>0 then ack_lines[#ack_lines+1]=clean
                        else return end
                        local ack=table.concat(ack_lines," "):gsub("%s+"," ")
                        if #ack_lines>8 or #ack>1024 then ack_lines={}; return end
                        local number,commodity,planet,wages=ack:match(
                            "^The wages for workers in factory #(%d+) %(([%w]+) on (.-)%) have been set to (%d+)%.$")
                        if not number then return end
                        ack_lines={}
                        if tonumber(number)~=proposal.slot or norm(commodity)~=norm(o.commodity)
                            or norm(planet)~=norm(o.planet) or tonumber(wages)~=o.wages then return end
                        local state=snapshot(o)
                        local factory=state and state.roster[proposal.slot]
                        if not identity(state) or not factory or norm(factory.planet)~=norm(o.planet)
                            or norm(factory.output)~=norm(o.commodity) then
                            finish(nil,failure("factory identity changed before wage display request")); return
                        end
                        phase="verifying_wages"; rows,started={},false
                        if timer then API._adapter.cancelTimer(timer); timer=nil end
                        if not bound(15,function()
                            if phase=="verifying_wages" then finish(nil,failure("factory wage display timed out after acknowledgement")) end
                        end) then return end
                        local ok,err=lease:send("display factory "..proposal.slot,
                            {operation="company.factory.preview",reason="verify acknowledged new factory wages"})
                        if not ok then finish(nil,err) end
                        return
                    end
                    if phase~="verifying_wages" then return end
                    if clean:find("Production Facility #",1,true) then
                        if started then finish(nil,failure("multiple factory wage headers")); return end
                        started=true
                    end
                    if not started then return end
                    rows[#rows+1]=clean
                    if #rows>100 then finish(nil,failure("factory wage display too long")); return end
                    if not table.concat(rows," "):gsub("%s+"," "):find("Next batch is %d+%% complete") then return end
                    local record,parse_error=API._adapter.parseFactory(rows,proposal.slot)
                    if not record then finish(nil,failure("invalid factory wage display: "..tostring(parse_error))); return end
                    local state=snapshot(o)
                    local factory=state and state.roster[proposal.slot]
                    if not identity(state) or not factory or norm(factory.planet)~=norm(o.planet)
                        or norm(factory.output)~=norm(o.commodity) or record.owner~=proposal.owner
                        or norm(record.location)~=norm(o.planet) or norm(record.commodity)~=norm(o.commodity)
                        then finish(nil,failure("factory wage display identity did not reconcile")); return end
                    if record.wages~=o.wages then
                        finish(nil,failure("factory wage display reports "..tostring(record.wages).."ig; expected "..o.wages.."ig")); return
                    end
                    proposal.wages_confirmed=true; finish(proposal)
                end)
                if not observer then finish(nil,failure("factory wage observer unavailable")); return end
                if not bound(15,function()
                    if phase=="setting_wages" then finish(nil,failure("factory wage acknowledgement timed out")) end
                end) then return end
                wage_sent=true
                local ok,err=lease:send("set factory "..proposal.slot.." wages "..o.wages,
                    {operation="company.factory.wages",reason="one-click factory wage policy"})
                if not ok then finish(nil,err); return end
            end
            local function buy_factory(base)
            phase,sent="settling",true
            local ok,problem=lease:send("buy factory "..o.commodity,{operation="company.factory.buy",reason="explicit single-factory confirmation"})
            if not ok then finish(nil,problem); return end
            -- Purchase has no replay path. Read the ordered company response
            -- and reconcile one added slot plus exactly the 2m company debit.
            clear(); local mine=epoch
            local channel=initial.rank=="Industrialist" and "business" or "company"
            subscriptions[#subscriptions+1]=API.events.subscribe("data."..channel,function(event)
                if not active or mine~=epoch or not event.received then return end
                local after,invalid=snapshot(o)
                if not identity(after) then finish(nil,invalid or failure("identity changed after purchase")); return end
                local expected=S.copy(base.roster)
                expected[base.slot]={number=base.slot,planet=o.planet,output=o.commodity}
                local actual=S.copy(after.roster)
                for _,f in pairs(actual) do f.planet=norm(f.planet); f.output=norm(f.output) end
                for _,f in pairs(expected) do f.planet=norm(f.planet); f.output=norm(f.output) end
                if not equal(actual,expected) or not equal(after.depots,base.depots) or after.cash~=base.cash-COST then
                    finish(nil,failure("company cash and exact new factory slot did not reconcile")); return
                end
                proposal.confirmed=true; proposal.company_cash=after.cash; set_wages()
            end)
            if not bound(15,function() finish(nil,failure("purchase confirmation timed out")) end) then return end
            local requested,read_error=lease:send(channel=="business" and "di business" or "di company",
                {operation="company.factory.preview",reason="reconcile single factory purchase"})
            if not requested then finish(nil,read_error) end
            end
            if not proposal.depot_needed then buy_factory(before); return end
            -- One confirmation covers this explicitly priced site. The depot
            -- must reconcile first; a partial site never automatically retries.
            phase,sent="settling_depot",true
            local ok,problem=lease:send("buy depot",{operation="company.factory.buy",reason="explicit factory-site depot confirmation"})
            if not ok then finish(nil,problem); return end
            read_all(function(after,report_after)
                local expected=S.copy(before.depots); expected[norm(o.planet)]=true
                if not equal(after.roster,before.roster) or not equal(after.depots,expected) or after.cash~=before.cash-DEPOT_COST then
                    finish(nil,failure("depot roster and exact 1004480ig debit (including initial wages) did not reconcile")); return
                end
                if o.depot_only then
                    proposal.confirmed=true; proposal.company_cash=after.cash; finish(proposal); return
                end
                local checked,invalid=ready(after,report_after,o)
                if not checked or checked.slot~=proposal.slot then finish(nil,invalid or failure("factory slot changed after depot")); return end
                local permitted,denied=S.authorize(context,"company.factory.continue",payload)
                if not permitted then finish(nil,denied); return end
                buy_factory(after)
            end)
        end)
        return true
    end
    token=context:own("company.factory.preview",handle,function(value) value:cancel("module_cleanup") end)
    read_all(function(state,report)
        local proposal,err=ready(state,report,o,o.review_prices==true)
        if not proposal then finish(nil,err); return end
        preview=state; phase="ready"
        if not bound(30,function() finish(nil,failure("factory preview expired")) end) then return end
        proposal.expires_in=30
        local ok,detail=pcall(callback,S.copy(proposal))
        if not ok then handle:cancel("preview_callback_failed"); API.events.emit("api.callback_error",{label="company.factory",error=tostring(detail)}) end
    end)
    return handle
end
