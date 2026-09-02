-- Muxlet capture Transform for player rank-promotion broadcast lines (see
-- full.lua's "Promotion" capture). The game's promotion announcements are not
-- one consistent template - each rank transition in fed2-community's
-- player.cc phrases its broadcast differently ("has reached Trader rank!",
-- "has been acclaimed as Founder of...", "has gained promotion to
-- Gengineer!", etc.) - so this matches each known shape explicitly rather
-- than guessing at a single generic pattern, then colors the name by the
-- rank just reached and turns it into a player-card link, the same
-- rank-color + click-to-card convention as chat.lua/spynet_capture.lua.
--
-- Registered as an ordinary Muxlet action (Settings → Muxlet → Actions still
-- lists it, read-only) so any capture's Transform dropdown can pick it by name;
-- no Muxlet-side change is needed to add more of these later.

-- One entry per distinct broadcast shape. Every promotion that is actually
-- broadcast live (via SpynetNotice) to all online players is covered; a few
-- top-end ranks (Financier, Plutocrat, Syndicrat) only post to the review
-- board in fed2-community and never appear as a live console line, so there
-- is nothing for a console capture to catch for those.
local RANK_SHAPES = {
    "^(%S+) has (promoted to Commander)!$",
    "^(%S+) has (earned membership in the Adventurer's Guild and become an? Adventurer)!$",
    "^(%S+) has (earned membership in the Adventurer's Guild and become an? Adventuress)!$",
    "^(%S+) has (joined the Galactic Trading Guild and become a Merchant)!$",
    "^(%S+) has (reached Trader rank)!$",
    "^(%S+) has (become CEO of .+ and has promoted to Industrialist)!$",
    "^(%S+) has (launched an IPO for .+ and promoted to Manufacturer)!$",
    "^(%S+) has (been acclaimed as Founder of .+ in the .+ system)!$",
    "^(%S+) has (gained promotion to Gengineer)!$",
}
for _, rank in ipairs({ "Engineer", "Mogul", "Technocrat", "Magnate" }) do
    RANK_SHAPES[#RANK_SHAPES + 1] =
        "^(%S+) has (promoted .+ in the .+ system to .+ level and gained the rank of " .. rank .. ")!$"
end

-- The rank actually reached is always the last capitalized rank-shaped word
-- in the captured clause (matches F2T_RANK_COLORS' key spelling exactly).
local function achievedRank(clause)
    local rank
    for word in clause:gmatch("%u%l+") do
        if F2T_RANK_COLORS and F2T_RANK_COLORS[word] then rank = word end
    end
    return rank
end

local function promotionTransform(ctx)
    local mc   = ctx and ctx.console
    local text = ctx and ctx.value
    if not (mc and text) then return end

    local name, clause
    for _, pat in ipairs(RANK_SHAPES) do
        name, clause = text:match(pat)
        if name then break end
    end
    if not name then return end   -- unrecognized shape: let the caller fall back to a verbatim copy

    local rank = achievedRank(clause)
    local rc   = (rank and f2t_rank_color_decho and f2t_rank_color_decho(rank)) or "<200,200,200>"

    mc:dechoLink(rc .. "<b>" .. name .. "</b><r>", function()
        if f2tPlayerCardShowOrRaiseByName then f2tPlayerCardShowOrRaiseByName(name) end
    end, "Open player card for " .. name, true)
    mc:echo(" has " .. clause .. "!\n")

    return true
end

function f2tRegisterPromotionCaptureTransform()
    if not (Mux and Mux.registerAction) then
        if f2t_debug_log then f2t_debug_log("[promotion_capture] Muxlet action API unavailable; skipping") end
        return
    end
    Mux.registerAction("f2t.captureTransform.promotion", {
        name = "Promotion (color + card link)", group = "Capture Transform", icon = "🎖️", readOnly = true,
        desc = "For the Capture content: colors a player rank-promotion broadcast line by the rank just "
            .. "reached and makes their name open the player card. Pick it from a capture's Transform dropdown.",
        run = promotionTransform,
    })
    if f2t_debug_log then f2t_debug_log("[promotion_capture] registered f2t.captureTransform.promotion action") end
end
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterPromotionCaptureTransform)
