--[[
  Aimbot UI - Interrupt Ready
  While an enemy casts, your own interrupt (Kick, Pummel, Counterspell, Earth Shock, Spell
  Lock...) shows next to their cast bar: bright with a green edge when it is ready, grey with a
  cooldown sweep when it is not. Works on enemy nameplates and the target and focus cast bars.

  Our own icon frames are anchored to the cast bars; Blizzard frames are only read.
  Values the client marks as secret are never compared: the cooldown sweep is handed to the
  game's own Cooldown widget, and an unknown "can it be interrupted" counts as yes.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Interrupt Ready",
    group = "Combat",
    desc = "Shows your interrupt next to enemy cast bars: green when it's ready, greyed out with a timer when it isn't.",
    defaults = {
        enabled  = true,
        plates   = true,
        target   = true,
        focus    = true,
        size     = 20,
        hideUninterruptible = true,
        onlyReady = false,      -- show the icon only while the interrupt is ready
    },
}
NS.RegisterModule("interrupt", M)

local function S() return NS.db.mod.interrupt end
local IsSecret = NS.IsSecret

-- Interrupts per class, first known one wins (lower ranks and pet spells included).
local INTERRUPTS = {
    ROGUE   = { 1766, 1767, 1768, 1769, 38768 },
    WARRIOR = { 6552, 6554, 72, 1671, 1672, 29704 },
    MAGE    = { 2139 },
    SHAMAN  = { 57994, 8042, 8044, 8045, 8046, 10412, 10413, 10414, 25454 },
    PRIEST  = { 15487 },
    WARLOCK = { 19647, 19244, 119910, 132409 },   -- Felhunter's Spell Lock (pet)
    DRUID   = { 106839, 16979, 80964, 80965 },    -- Skull Bash / Feral Charge (bear)
    PALADIN = { 96231 },
    HUNTER  = { 147362, 187707 },
    DEATHKNIGHT = { 47528 },
}

local spellID, spellTex, isPet
M.stats = { shown = 0, casts = 0 }

local function Known(id)
    if IsPlayerSpell then
        local ok, k = pcall(IsPlayerSpell, id)
        if ok and not IsSecret(k) and k then return true, false end
    end
    if IsSpellKnown then
        local ok, k = pcall(IsSpellKnown, id)
        if ok and not IsSecret(k) and k then return true, false end
        local okp, kp = pcall(IsSpellKnown, id, true)
        if okp and not IsSecret(kp) and kp then return true, true end
    end
    return false
end

local function Texture(id)
    local fn = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    if not fn then return nil end
    local ok, t = pcall(fn, id)
    if ok and not IsSecret(t) then return t end
end

local function FindInterrupt()
    spellID, spellTex, isPet = nil, nil, nil
    local ok, _, classFile = pcall(UnitClass, "player")
    if not ok or IsSecret(classFile) then return end
    for _, id in ipairs(INTERRUPTS[classFile] or {}) do
        local known, pet = Known(id)
        if known then
            spellID, isPet = id, pet
            spellTex = Texture(id)
            return
        end
    end
end

-- start, duration of the interrupt's cooldown (may be secret values; only the widget sees those)
local function Cooldown()
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and type(info) == "table" then return info.startTime, info.duration end
    end
    if GetSpellCooldown then
        local ok, start, dur = pcall(GetSpellCooldown, spellID)
        if ok then return start, dur end
    end
end

-- true = ready, false = cooling down, nil = unknown (secret)
local function Ready()
    local start, dur = Cooldown()
    if start == nil or IsSecret(start) or IsSecret(dur) then return nil, start, dur end
    if not dur or dur <= 1.5 then return true, start, dur end      -- 1.5 s or less is the global cooldown
    return (start + dur - GetTime()) <= 0, start, dur
end

----------------------------------------------------------------------
-- Icons
----------------------------------------------------------------------
local icons = setmetatable({}, { __mode = "k" })    -- cast bar -> our icon frame
local watched = {}                                    -- unit -> cast bar (while that unit casts)

local function Icon(bar)
    local f = icons[bar]
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f.edge = f:CreateTexture(nil, "BACKGROUND")
    f.edge:SetPoint("TOPLEFT", -2, 2)
    f.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
    if ok and cd then
        cd:SetAllPoints()
        if cd.SetHideCountdownNumbers then pcall(cd.SetHideCountdownNumbers, cd, false) end
        f.cd = cd
    end
    f:Hide()
    icons[bar] = f
    return f
end

local function BarFor(unit)
    if unit == "target" then return _G.TargetFrameSpellBar or (_G.TargetFrame and _G.TargetFrame.spellbar) end
    if unit == "focus" then return _G.FocusFrameSpellBar or (_G.FocusFrame and _G.FocusFrame.spellbar) end
    if unit:find("^nameplate") and C_NamePlate then
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        local uf = ok and plate and plate.UnitFrame
        return uf and (uf.castBar or uf.CastBar)
    end
end

local function UnitWanted(unit)
    local s = S()
    if unit == "target" then return s.target end
    if unit == "focus" then return s.focus end
    return s.plates and unit:find("^nameplate") ~= nil
end

-- is the unit casting, and can it be interrupted? (nil = can't tell)
local function CastState(unit)
    local ok, name, _, _, _, _, _, _, notInt = pcall(UnitCastingInfo, unit)
    if ok and (IsSecret(name) or name ~= nil) then return true, notInt end
    local okc, cname, _, _, _, _, _, cnotInt = pcall(UnitChannelInfo, unit)
    if okc and (IsSecret(cname) or cname ~= nil) then return true, cnotInt end
    return false
end

local function HideUnit(unit)
    local bar = watched[unit]
    watched[unit] = nil
    if bar and icons[bar] then
        -- the same bar may be shown for another unit token (e.g. target and its nameplate are separate bars)
        icons[bar]:Hide()
    end
end

local function UpdateIcon(unit)
    local bar = watched[unit]
    local f = bar and icons[bar]
    if not f then return end
    local s = S()
    local ready, start, dur = Ready()
    if s.onlyReady and ready == false then f:Hide(); return end
    f:Show()
    f.tex:SetDesaturated(ready == false)
    f.tex:SetAlpha(ready == false and 0.6 or 1)
    if ready == false then f.edge:SetColorTexture(0, 0, 0, 0.9)
    else f.edge:SetColorTexture(0.2, 1, 0.3, 0.95) end
    if f.cd and start ~= nil then pcall(f.cd.SetCooldown, f.cd, start, dur) end
end

local function Check(unit)
    if type(unit) ~= "string" then return end
    local s = S()
    if not (s.enabled and spellID and UnitWanted(unit)) then HideUnit(unit); return end
    local okA, enemy = pcall(UnitCanAttack, "player", unit)
    if not okA or (not IsSecret(enemy) and not enemy) then HideUnit(unit); return end
    local casting, notInt = CastState(unit)
    if not casting then HideUnit(unit); return end
    if s.hideUninterruptible and not IsSecret(notInt) and notInt then HideUnit(unit); return end
    local bar = BarFor(unit)
    if not bar then HideUnit(unit); return end
    local f = Icon(bar)
    f:SetSize(s.size, s.size)
    f:ClearAllPoints()
    f:SetPoint("LEFT", bar, "RIGHT", 4, 0)
    f.tex:SetTexture(spellTex)
    if watched[unit] ~= bar then M.stats.casts = M.stats.casts + 1 end
    watched[unit] = bar
    UpdateIcon(unit)
end

local function CheckAll()
    for unit in pairs(watched) do pcall(Check, unit) end
    pcall(Check, "target"); pcall(Check, "focus")
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do
                local u = plate.namePlateUnitToken
                if type(u) == "string" then pcall(Check, u) end
            end
        end
    end
end

M._t = { Check = Check, CheckAll = CheckAll, FindInterrupt = FindInterrupt, watched = watched, icons = icons,
    Spell = function() return spellID, isPet end }

function M:Apply()
    FindInterrupt()
    if not S().enabled then for u in pairs(watched) do HideUnit(u) end return end
    CheckAll()
end

function M:Init()
    FindInterrupt()
    for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_EMPOWER_START",
        "UNIT_SPELLCAST_EMPOWER_STOP" }) do
        NS.On(ev, function(_, unit) if S().enabled then pcall(Check, unit) end end)
    end
    NS.On("NAME_PLATE_UNIT_REMOVED", function(_, unit) HideUnit(unit) end)
    NS.On("NAME_PLATE_UNIT_ADDED", function(_, unit) if S().enabled then pcall(Check, unit) end end)
    NS.On("PLAYER_TARGET_CHANGED", function() if S().enabled then pcall(Check, "target") end end)
    NS.On("PLAYER_FOCUS_CHANGED", function() if S().enabled then pcall(Check, "focus") end end)
    for _, ev in ipairs({ "SPELLS_CHANGED", "UNIT_PET", "PLAYER_TALENT_UPDATE", "LEARNED_SPELL_IN_TAB" }) do
        NS.On(ev, function() FindInterrupt() end)
    end
    -- keep ready / cooling down current while icons are up
    local tick = CreateFrame("Frame")
    local acc = 0
    tick:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 0.1 then return end
        acc = 0
        if not next(watched) then return end
        for unit in pairs(watched) do
            local ok, err = pcall(Check, unit)
            if not ok then NS.ReportError("Interrupt Ready", err) end
        end
    end)
end

function M:Diagnose()
    local name = spellID and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
        or (GetSpellInfo and GetSpellInfo(spellID)))
    local n = 0
    for _ in pairs(watched) do n = n + 1 end
    local ready = Ready()
    NS.Print(string.format("  your interrupt: %s%s   ready: %s   casts seen: %d   showing now: %d",
        spellID and (tostring(name) .. " (" .. spellID .. ")") or "none found for your class",
        isPet and " [pet]" or "", tostring(ready), M.stats.casts, n))
end

function M.Build(page)
    page:Section("Where", "Which cast bars get your interrupt icon")
    page:Check("Enemy nameplates", function() return S().plates end,
        function(v) S().plates = v; NS.ApplyModule("interrupt") end)
    page:Check("Target cast bar", function() return S().target end,
        function(v) S().target = v; NS.ApplyModule("interrupt") end)
    page:Check("Focus cast bar", function() return S().focus end,
        function(v) S().focus = v; NS.ApplyModule("interrupt") end)

    page:Section("How", "Look and when it shows")
    page:Slider("Icon size", 12, 40, 1, function() return S().size end,
        function(v) S().size = v; NS.ApplyModule("interrupt") end)
    page:Check("Hide on casts that can't be interrupted", function() return S().hideUninterruptible end,
        function(v) S().hideUninterruptible = v; NS.ApplyModule("interrupt") end)
    page:Check("Only show when my interrupt is ready", function() return S().onlyReady end,
        function(v) S().onlyReady = v; NS.ApplyModule("interrupt") end)
    page:Note("Green edge = ready to use. Grey with a timer = still on cooldown. Your interrupt is found from your "
        .. "spellbook (Kick, Pummel, Shield Bash, Counterspell, Earth Shock, Silence, Spell Lock, Feral Charge...). "
        .. "Warlocks need the Felhunter out. /aimbot diag shows which spell it picked.")
end
