--[[
  Aimbot UI - Spell Coefficients (2.26.0)
  Adds a spell's spell power coefficient to its tooltip (spellbook, action bars, chat links), and
  how much damage your current spell power adds to it:

      Spell power coefficient   81.4%
      +163 damage from your 200 Frost spell power

  Data: every damaging Mage spell, rank by rank, from the WoW Forever client (beta build 1.60.1)
  as published by RankedBoost (rankedboost.com/world-of-warcraft/forever, Nov 2026). Values are
  the share of spell power one cast adds; for spells with a damage-over-time part (Fireball,
  Pyroblast, Frostfire Bolt) the figure is for the whole cast. Two are marked as not certain:
    * Ice Lance - the client stores no coefficient (the server sets it); ~0.10 was measured from
      beta combat logs (ElliotWood/Forever simulator, PR #726).
    * Arcane Blast - the listed 42.9% may be from before the 15 Oct 2026 change that cut its
      damage and coefficient by 40%.
  Spells are matched by name and the rank the game reports, so no spell IDs are needed. Ranks
  far below your level get less from spell power in Forever; the size of that cut isn't known,
  so it isn't applied.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Spell Coefficients",
    group = "QoL",
    desc = "Shows each spell's spell power coefficient in its tooltip, and how much damage your spell "
        .. "power adds to it. Covers every damaging Mage spell, rank by rank.",
    defaults = {
        enabled = true,
        bonus   = true,      -- "+N damage from your spell power"
        notes   = true,      -- "whole cast incl. damage over time", "not certain" ...
        color   = { 0.45, 0.80, 1.00, 1 },
    },
}
NS.RegisterModule("spellcoeffs", M)

local function S() return NS.db.mod.spellcoeffs end
local IsSecret = NS.IsSecret

-- school index for GetSpellBonusDamage: 3 fire, 5 frost, 7 arcane
local FIRE, FROST, ARCANE = 3, 5, 7
local SCHOOL_NAME = { [FIRE] = "Fire", [FROST] = "Frost", [ARCANE] = "Arcane" }

local function Ranks(...) return { ... } end
local function Same(n, v) local t = {} for i = 1, n do t[i] = v end return t end

-- name -> { coef = {by rank} or number, school = index or {list}, note = kind, unsure = text }
local DATA = {
    ["Fireball"]         = { coef = Ranks(0.429, 0.571, 0.714, 0.857, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000),
                             school = FIRE, note = "dot" },
    ["Frostbolt"]        = { coef = Ranks(0.407, 0.489, 0.597, 0.706, 0.814, 0.814, 0.814, 0.814, 0.814, 0.814, 0.814),
                             school = FROST },
    ["Fire Blast"]       = { coef = Same(7, 0.429), school = FIRE },
    ["Scorch"]           = { coef = Same(7, 0.429), school = FIRE },
    ["Arcane Missiles"]  = { coef = Ranks(0.858, 1.144, 1.430, 1.430, 1.430, 1.430, 1.430, 1.430),
                             school = ARCANE, note = "channel" },
    ["Arcane Explosion"] = { coef = Same(6, 0.143), school = ARCANE, note = "aoe" },
    ["Frostfire Bolt"]   = { coef = Same(3, 0.814), school = { FIRE, FROST }, note = "dot" },
    ["Flamestrike"]      = { coef = Same(6, 0.285), school = FIRE, note = "flamestrike" },
    ["Blizzard"]         = { coef = Same(6, 0.336), school = FROST, note = "channelaoe" },
    ["Frost Nova"]       = { coef = Same(4, 0.029), school = FROST, note = "aoe" },
    ["Cone of Cold"]     = { coef = Same(5, 0.129), school = FROST, note = "aoe" },
    ["Arcane Blast"]     = { coef = Same(5, 0.429), school = ARCANE,
                             unsure = "may be lower: its damage and coefficient were cut 40% on 15 Oct" },
    ["Arcane Wrath"]     = { coef = Same(4, 1.000), school = ARCANE },
    ["Blast Wave"]       = { coef = Same(5, 0.129), school = FIRE, note = "aoe" },
    ["Pyroblast"]        = { coef = Same(8, 1.600), school = FIRE, note = "dot" },
    ["Ice Lance"]        = { coef = Same(6, 0.10), school = FROST,
                             unsure = "measured from combat logs (~0.10); the client has no value" },
}
M.DATA = DATA

local NOTES = {
    dot         = "whole cast, including the damage over time",
    channel     = "whole channel",
    channelaoe  = "whole channel, per target",
    aoe         = "per target",
    flamestrike = "first hit, per target (the burn after isn't listed)",
}

M.stats = { hook = "none", shown = 0, last = nil, secret = 0 }

-- "Rank 5" -> 5 (English client)
local function RankOf(spellID)
    local sub
    if C_Spell and C_Spell.GetSpellSubtext then
        local ok, v = pcall(C_Spell.GetSpellSubtext, spellID)
        if ok then sub = v end
    end
    if sub == nil and GetSpellSubtext then
        local ok, v = pcall(GetSpellSubtext, spellID)
        if ok then sub = v end
    end
    if type(sub) ~= "string" or IsSecret(sub) then return nil end
    local n = sub:match("(%d+)")
    return n and tonumber(n) or nil
end

local function NameOf(spellID)
    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, v = pcall(C_Spell.GetSpellName, spellID)
        if ok then name = v end
    end
    if name == nil and GetSpellInfo then
        local ok, v = pcall(GetSpellInfo, spellID)
        if ok then name = v end
    end
    if type(name) ~= "string" or IsSecret(name) then return nil end
    return name
end

-- The coefficient for a name and rank: number, or lo, hi when the rank is unknown and ranks differ.
local function Coef(entry, rank)
    local c = entry.coef
    if type(c) == "number" then return c end
    if rank and c[rank] then return c[rank] end
    local lo, hi = math.huge, -math.huge
    for _, v in ipairs(c) do lo = math.min(lo, v); hi = math.max(hi, v) end
    if lo == hi then return lo end
    return nil, lo, hi
end
M._t_Coef = Coef

-- Your spell power for the spell's school (the higher of two for Frostfire Bolt). nil if hidden.
local function SpellPower(school)
    if not GetSpellBonusDamage then return nil end
    local list = type(school) == "table" and school or { school }
    local best, bestSchool
    for _, sc in ipairs(list) do
        local ok, v = pcall(GetSpellBonusDamage, sc)
        if ok and type(v) == "number" then
            if IsSecret(v) then M.stats.secret = M.stats.secret + 1; return nil end
            if not best or v > best then best, bestSchool = v, sc end
        end
    end
    return best, bestSchool
end

local function Pct(v) return string.format("%.1f%%", v * 100) end

-- The lines to add for a spell ID (a list of { left, right, r, g, b }), or nil.
local function LinesFor(spellID)
    if type(spellID) ~= "number" or IsSecret(spellID) then return nil end
    local name = NameOf(spellID)
    local entry = name and DATA[name]
    if not entry then return nil end
    local s = S()
    local c = s.color
    local rank = RankOf(spellID)
    local coef, lo, hi = Coef(entry, rank)
    local lines = {}
    local value = coef and Pct(coef) or (Pct(lo) .. " - " .. Pct(hi))
    lines[#lines + 1] = { "Spell power coefficient", value, c[1], c[2], c[3] }
    if s.bonus and coef then
        local sp, sc = SpellPower(entry.school)
        if sp and sp > 0 then
            lines[#lines + 1] = { string.format("+%d damage from your %d %s spell power",
                math.floor(sp * coef + 0.5), math.floor(sp + 0.5), SCHOOL_NAME[sc] or ""), nil, 0.85, 0.85, 0.85 }
        end
    end
    if s.notes then
        if entry.note and NOTES[entry.note] then
            lines[#lines + 1] = { "  " .. NOTES[entry.note], nil, 0.6, 0.6, 0.6 }
        end
        if not coef then
            lines[#lines + 1] = { "  depends on the rank (rank not reported)", nil, 0.6, 0.6, 0.6 }
        end
        if entry.unsure then
            lines[#lines + 1] = { "  not certain: " .. entry.unsure, nil, 1, 0.75, 0.3 }
        end
    end
    M.stats.last = name .. (rank and (" r" .. rank) or "") .. " = " .. value
    return lines
end
M._t_LinesFor = LinesFor

local added = setmetatable({}, { __mode = "k" })    -- tooltip -> spellID already added this show

local function AddTo(tooltip, spellID)
    if not S().enabled or not tooltip or not tooltip.AddLine then return end
    if added[tooltip] == spellID then return end     -- two hooks can fire for one tooltip
    local lines = LinesFor(spellID)
    if not lines then return end
    added[tooltip] = spellID
    for _, l in ipairs(lines) do
        if l[2] then
            tooltip:AddDoubleLine(l[1], l[2], l[3], l[4], l[5], 1, 1, 1)
        else
            tooltip:AddLine(l[1], l[3], l[4], l[5], true)
        end
    end
    M.stats.shown = M.stats.shown + 1
    pcall(tooltip.Show, tooltip)                       -- resize to fit the new lines
end
M._t_AddTo = AddTo

local hooked = false
local function Hook()
    if hooked then return end
    hooked = true
    -- modern clients: one callback for every spell tooltip (spellbook, action bars, links)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
        and Enum.TooltipDataType.Spell then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
            local id = data and data.id
            local ok, err = pcall(AddTo, tooltip, id)
            if not ok then NS.ReportError("Spell Coefficients", err) end
        end)
        M.stats.hook = "tooltip data"
    end
    -- older path, and a backup: ask the tooltip which spell it shows after it's filled
    if GameTooltip and GameTooltip.HookScript then
        local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetSpell", function(tt)
            if not tt.GetSpell then return end
            local ok2, _, id = pcall(tt.GetSpell, tt)
            if ok2 then
                local ok3, err = pcall(AddTo, tt, id)
                if not ok3 then NS.ReportError("Spell Coefficients", err) end
            end
        end)
        if ok then M.stats.hook = (M.stats.hook == "none" and "" or M.stats.hook .. " + ") .. "set-spell" end
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipCleared", function(tt) added[tt] = nil end)
        pcall(GameTooltip.HookScript, GameTooltip, "OnHide", function(tt) added[tt] = nil end)
    end
end

function M:Init() Hook() end
function M:Apply() Hook() end

function M.Build(page)
    page:Section("Tooltip", "What's added to spell tooltips")
    page:Check("Show how much damage your spell power adds", function() return S().bonus end,
        function(v) S().bonus = v end)
    page:Check("Show notes (damage over time, per target, not certain)", function() return S().notes end,
        function(v) S().notes = v end)
    page:Color("Coefficient colour", function() return S().color end,
        function(r, g, b) local c = S().color; c[1], c[2], c[3] = r, g, b end)
    page:Note("Covers every damaging Mage spell, rank by rank: Fireball, Frostbolt, Frostfire Bolt, Fire Blast, "
        .. "Scorch, Pyroblast, Flamestrike, Blast Wave, Arcane Missiles, Arcane Explosion, Arcane Blast, Arcane "
        .. "Wrath, Blizzard, Cone of Cold, Frost Nova and Ice Lance. Data from the WoW Forever client (beta build "
        .. "1.60.1). Ice Lance (no value in the client) and Arcane Blast (cut by 40% in October) are marked as not "
        .. "certain. Shields such as Ice Barrier and Mana Shield have no published value yet.")
    page:Note("Ranks far below your level get less from spell power in Forever. The size of that cut isn't "
        .. "known, so the damage shown is for a rank at or near your level.")
end

function M:Diagnose()
    local st = M.stats
    local n = 0
    for _ in pairs(DATA) do n = n + 1 end
    NS.Print(string.format("  hook %s   spells in table %d   tooltips added %d   last %s   secret spell power %d",
        tostring(st.hook), n, st.shown, tostring(st.last or "-"), st.secret))
end
