--[[
  Aimbot UI - Aura Timers
  Shows the time left as numbers on buff and debuff icons: your DoTs and crowd control on the
  target, focus and enemy nameplates.

  The game already draws these numbers on cooldown swipes (the "countdownForCooldowns" setting),
  but it turns them off for the small aura icons on unit frames and nameplates. This module
  turns them back on for those icons with the Cooldown widget's own SetHideCountdownNumbers,
  and can make the numbers bigger. The game does the counting, so it also works when the client
  hides the real aura times from addons ("secret" values): this module never reads them.

  Only method calls on the aura icons' cooldowns; no fields are written on Blizzard frames.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Aura Timers",
    group = "Combat",
    desc = "Time-left numbers on buff and debuff icons: your DoTs and CC on target, focus and nameplates.",
    defaults = {
        enabled  = true,
        target   = true,
        focus    = true,
        plates   = true,
        resize   = true,
        size     = 12,              -- number size on target / focus icons
        plateSize = 10,             -- number size on nameplate icons
    },
}
NS.RegisterModule("auratimers", M)

local function S() return NS.db.mod.auratimers end
local IsSecret = NS.IsSecret

local CVAR = "countdownForCooldowns"
local touched = setmetatable({}, { __mode = "k" })   -- cooldown -> { font, size, flags } (our own table)
local savedCVar                                        -- the player's value before we changed it
M.stats = { target = 0, focus = 0, plates = 0, cvar = "?" }

----------------------------------------------------------------------
-- Finding the aura cooldowns
----------------------------------------------------------------------
local function IsCooldown(obj)
    if not obj or not obj.IsObjectType then return false end
    local ok, is = pcall(obj.IsObjectType, obj, "Cooldown")
    return ok and not IsSecret(is) and is
end

-- Walks the children of root (a few levels down) and calls fn on every Cooldown found.
local function EachCooldown(root, depth, fn)
    if not root or not root.GetChildren or depth < 0 then return 0 end
    local okK, kids = pcall(function() return { root:GetChildren() } end)
    if not okK then return 0 end
    local n = 0
    for _, kid in ipairs(kids) do
        if IsCooldown(kid) then
            fn(kid); n = n + 1
        else
            n = n + EachCooldown(kid, depth - 1, fn)
        end
    end
    return n
end

-- Unit frames: only cooldowns that sit on an aura icon (the auraPools), not other swipes.
local function UnitFrameAuraCooldowns(frame, fn)
    local pools = frame and frame.auraPools
    local n = 0
    if pools and pools.EnumerateActive then
        local ok = pcall(function()
            for obj in pools:EnumerateActive() do
                local cd = obj.Cooldown or obj.cooldown
                if IsCooldown(cd) then fn(cd); n = n + 1
                else n = n + EachCooldown(obj, 2, fn) end
            end
        end)
        if ok then return n end
    end
    -- older layouts: aura buttons named <Frame>Buff1 / <Frame>Debuff1 with a Cooldown child
    local name = frame and frame.GetName and frame:GetName()
    if name then
        for _, kind in ipairs({ "Buff", "Debuff" }) do
            for i = 1, 40 do
                local cd = _G[name .. kind .. i .. "Cooldown"]
                if not cd then break end
                if IsCooldown(cd) then fn(cd); n = n + 1 end
            end
        end
    end
    return n
end

----------------------------------------------------------------------
-- Showing / hiding the numbers
----------------------------------------------------------------------
local function Show(cd, size)
    if not touched[cd] then
        local rec = {}
        local okF, fs = pcall(cd.GetCountdownFontString, cd)
        if okF and fs and fs.GetFont then
            local okG, font, sz, flags = pcall(fs.GetFont, fs)
            if okG then rec.font, rec.size, rec.flags = font, sz, flags end
        end
        touched[cd] = rec
    end
    pcall(cd.SetHideCountdownNumbers, cd, false)
    local rec = touched[cd]
    if rec.font then
        local okF, fs = pcall(cd.GetCountdownFontString, cd)
        if okF and fs then
            if S().resize then
                pcall(fs.SetFont, fs, rec.font, size, "OUTLINE")
            else
                pcall(fs.SetFont, fs, rec.font, rec.size, rec.flags)
            end
        end
    end
end

local function Restore(cd)
    local rec = touched[cd]
    if not rec then return end
    pcall(cd.SetHideCountdownNumbers, cd, true)
    if rec.font then
        local okF, fs = pcall(cd.GetCountdownFontString, cd)
        if okF and fs then pcall(fs.SetFont, fs, rec.font, rec.size, rec.flags) end
    end
    touched[cd] = nil
end

local function ApplyCVar(on)
    local okG, cur = pcall(GetCVar, CVAR)
    if not okG or cur == nil then M.stats.cvar = "missing"; return end
    if on then
        if cur ~= "1" then
            if savedCVar == nil then savedCVar = cur; S().savedCVar = cur end
            pcall(SetCVar, CVAR, "1")
        end
    else
        local back = savedCVar or S().savedCVar
        if back ~= nil then pcall(SetCVar, CVAR, back) end
        savedCVar, S().savedCVar = nil, nil
    end
    local okR, now = pcall(GetCVar, CVAR)
    M.stats.cvar = okR and tostring(now) or "?"
end

local function DoUnitFrame(key, frame)
    local s = S()
    local on = s.enabled and s[key]
    M.stats[key] = UnitFrameAuraCooldowns(frame, function(cd)
        if on then Show(cd, s.size) else Restore(cd) end
    end)
end

local function DoPlate(unit)
    local s = S()
    local on = s.enabled and s.plates
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return 0 end
    local okP, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not okP or not plate then return 0 end
    local uf = plate.UnitFrame or plate
    return EachCooldown(uf, 5, function(cd)
        if on then Show(cd, s.plateSize) else Restore(cd) end
    end)
end

local function DoAllPlates()
    local n = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, list = pcall(C_NamePlate.GetNamePlates)
        if ok and type(list) == "table" then
            for _, plate in ipairs(list) do
                local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
                if type(unit) == "string" then n = n + DoPlate(unit) end
            end
        end
    end
    M.stats.plates = n
end

----------------------------------------------------------------------
-- Updates: Blizzard rebuilds the icons when auras change, so redo it right after
----------------------------------------------------------------------
local dirty = { target = false, focus = false, plates = {} }
local function Flush()
    if not S().enabled then return end
    if dirty.target then dirty.target = false; DoUnitFrame("target", TargetFrame) end
    if dirty.focus then dirty.focus = false; DoUnitFrame("focus", FocusFrame) end
    for unit in pairs(dirty.plates) do
        dirty.plates[unit] = nil
        DoPlate(unit)
    end
end

M._t = { Flush = Flush, touched = touched, dirty = dirty }

function M:Apply()
    local s = S()
    ApplyCVar(s.enabled)
    DoUnitFrame("target", TargetFrame)
    DoUnitFrame("focus", FocusFrame)
    DoAllPlates()
    if not s.enabled then
        for cd in pairs(touched) do Restore(cd) end
    end
end

function M:Init()
    savedCVar = S().savedCVar
    local runner = CreateFrame("Frame")
    local acc = 0
    runner:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 0.05 then return end
        acc = 0
        local ok, err = pcall(Flush)
        if not ok then NS.ReportError("Aura Timers", err) end
    end)
    NS.On("UNIT_AURA", function(_, unit)
        if type(unit) ~= "string" then return end
        if unit == "target" then dirty.target = true
        elseif unit == "focus" then dirty.focus = true end
        if unit:find("^nameplate") then dirty.plates[unit] = true end
    end)
    NS.On("PLAYER_TARGET_CHANGED", function() dirty.target = true end)
    NS.On("PLAYER_FOCUS_CHANGED", function() dirty.focus = true end)
    NS.On("NAME_PLATE_UNIT_ADDED", function(_, unit) if type(unit) == "string" then dirty.plates[unit] = true end end)
    NS.On("PLAYER_ENTERING_WORLD", function() ApplyCVar(S().enabled) end)
end

function M:Diagnose()
    local st = M.stats
    local n = 0
    for _ in pairs(touched) do n = n + 1 end
    NS.Print(string.format("  countdownForCooldowns = %s   aura cooldowns found: target %d, focus %d, nameplates %d   showing numbers on %d",
        st.cvar, st.target, st.focus, st.plates, n))
    NS.Print("  TargetFrame.auraPools: " .. tostring(TargetFrame and TargetFrame.auraPools ~= nil))
end

function M.Build(page)
    page:Section("Where", "Which aura icons get time-left numbers")
    page:Check("Target frame", function() return S().target end,
        function(v) S().target = v; NS.ApplyModule("auratimers") end)
    page:Check("Focus frame", function() return S().focus end,
        function(v) S().focus = v; NS.ApplyModule("auratimers") end)
    page:Check("Nameplates", function() return S().plates end,
        function(v) S().plates = v; NS.ApplyModule("auratimers") end)
    page:Note("Numbers show on your DoTs, crowd control and any other aura icon the game draws a cooldown "
        .. "swipe on. Your own buffs at the top right keep the game's own timer setting.")

    page:Section("Number size", "Bigger or smaller numbers")
    page:Check("Use my own number size", function() return S().resize end,
        function(v) S().resize = v; NS.ApplyModule("auratimers") end)
    page:Slider("Target and focus icons", 6, 24, 1, function() return S().size end,
        function(v) S().size = v; NS.ApplyModule("auratimers") end)
    page:Slider("Nameplate icons", 6, 24, 1, function() return S().plateSize end,
        function(v) S().plateSize = v; NS.ApplyModule("auratimers") end)
end
