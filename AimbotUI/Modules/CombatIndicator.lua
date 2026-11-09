--[[
  Aimbot UI - Combat Indicator
  "+Combat" / "-Combat" in the middle of your screen when you enter and leave combat (size,
  colors and position can be changed, and it can be dragged anywhere), and a small icon next to the target, focus (and optionally player) frame that shows whether
  that unit is in combat: crossed swords while fighting, a "Zzz" while out of combat (handy
  to see who can still be sapped, who is drinking, or who has reset).

  Our own frames are anchored next to the unit frames; nothing on Blizzard frames is changed.
  If the client hides a unit's combat state (a "secret" value), the icons use the game's
  SetAlphaFromBoolean so they still work without the addon ever reading the value.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Combat Indicator",
    group = "Combat",
    desc = "+Combat / -Combat in the middle of your screen when you enter and leave combat, and icons "
        .. "showing whether your target and focus are in combat.",
    defaults = {
        enabled  = true,
        target   = true,
        focus    = true,
        player   = false,
        showIn   = true,       -- icon while in combat
        showOut  = true,       -- icon while out of combat
        playersOnly = false,   -- only for player characters
        size     = 22,
        x        = -4,
        y        = 0,
        -- "+Combat" / "-Combat" text for yourself
        text     = {
            enabled  = true,
            showEnter = true,
            showLeave = true,
            enterColor = { 1, 0.2, 0.2, 1 },
            leaveColor = { 0.3, 1, 0.3, 1 },
            size     = 26,
            duration = 1.5,
            color    = { 1, 1, 1, 1 },     -- the text carries its own colors; this is the base
            locked   = true,
            point    = { "CENTER", "CENTER", 0, 60 },
        },
    },
}
NS.RegisterModule("combatind", M)

local function S() return NS.db.mod.combatind end
local IsSecret = NS.IsSecret

local STATE_TEX = "Interface\\CharacterFrame\\UI-StateIcon"
local UNITS = {
    { unit = "target", key = "target", frames = { "TargetFrame" } },
    { unit = "focus",  key = "focus",  frames = { "FocusFrame" } },
    { unit = "player", key = "player", frames = { "PlayerFrame" } },
}
local icons = {}       -- unit -> our frame
M.stats = { secret = 0, ticks = 0 }

local function Anchor(info)
    for _, n in ipairs(info.frames) do
        local f = _G[n]
        if f then return f end
    end
end

local function Ensure(info)
    local f = icons[info.unit]
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(50)
    f.inTex = f:CreateTexture(nil, "OVERLAY")
    f.inTex:SetAllPoints()
    f.inTex:SetTexture(STATE_TEX)
    f.inTex:SetTexCoord(0.5, 1, 0, 0.484375)
    f.outTex = f:CreateTexture(nil, "OVERLAY")
    f.outTex:SetAllPoints()
    f.outTex:SetTexture(STATE_TEX)
    f.outTex:SetTexCoord(0, 0.5, 0, 0.421875)
    icons[info.unit] = f
    return f
end

local function Place(info, f)
    local s = S()
    local anchor = Anchor(info)
    f:SetSize(s.size, s.size)
    f:ClearAllPoints()
    if anchor then
        -- target/focus: to the right of the frame; player: to the left
        if info.unit == "player" then
            f:SetPoint("RIGHT", anchor, "LEFT", -s.x, s.y)
        else
            f:SetPoint("LEFT", anchor, "RIGHT", s.x, s.y)
        end
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    end
end

local function UpdateUnit(info)
    local s = S()
    local f = icons[info.unit]
    local want = s.enabled and s[info.key]
    if not want then if f then f:Hide() end return end
    local okE, exists = pcall(UnitExists, info.unit)
    if not okE or IsSecret(exists) or not exists then if f then f:Hide() end return end
    if s.playersOnly and info.unit ~= "player" then
        local okP, isPlayer = pcall(UnitIsPlayer, info.unit)
        if okP and not IsSecret(isPlayer) and not isPlayer then if f then f:Hide() end return end
    end
    f = f or Ensure(info)
    local ok, inCombat = pcall(UnitAffectingCombat, info.unit)
    if not ok then f:Hide(); return end
    f:Show()
    if IsSecret(inCombat) then
        M.stats.secret = M.stats.secret + 1
        if f.inTex.SetAlphaFromBoolean then
            pcall(f.inTex.SetAlphaFromBoolean, f.inTex, inCombat, s.showIn and 1 or 0, 0)
            pcall(f.outTex.SetAlphaFromBoolean, f.outTex, inCombat, 0, s.showOut and 1 or 0)
            f.inTex:Show(); f.outTex:Show()
        else
            f:Hide()
        end
        return
    end
    f.inTex:SetAlpha(1); f.outTex:SetAlpha(1)
    f.inTex:SetShown(inCombat and s.showIn and true or false)
    f.outTex:SetShown((not inCombat) and s.showOut and true or false)
end

local function UpdateAll()
    M.stats.ticks = M.stats.ticks + 1
    for _, info in ipairs(UNITS) do
        local ok, err = pcall(UpdateUnit, info)
        if not ok then NS.ReportError("Combat Indicator", err) end
    end
end

local function PlaceAll()
    for _, info in ipairs(UNITS) do
        if icons[info.unit] then Place(info, icons[info.unit]) end
    end
end

----------------------------------------------------------------------
-- "+Combat" / "-Combat" text
----------------------------------------------------------------------
local function T() return S().text end
local textAlert
local function TextAlert()
    if not textAlert then textAlert = NS.CreateAlertText("AimbotUICombatText", T, "+Combat") end
    return textAlert
end

local function Hex(c)
    local function B(v) return math.floor((v or 1) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", B(c[1]), B(c[2]), B(c[3]))
end

local function CombatText(entering)
    local s, t = S(), T()
    if not (s.enabled and t.enabled) then return end
    if entering and not t.showEnter then return end
    if not entering and not t.showLeave then return end
    local msg = entering and (Hex(t.enterColor) .. "+Combat|r") or (Hex(t.leaveColor) .. "-Combat|r")
    TextAlert():Show(msg)
end

M._t = { UpdateAll = UpdateAll, icons = icons, CombatText = CombatText }

local ticker
function M:Apply()
    if textAlert or not T().locked then TextAlert():Layout() end
    if not (S().enabled and T().enabled) and textAlert then textAlert:Hide() end
    for _, info in ipairs(UNITS) do
        if S().enabled and S()[info.key] then Place(info, Ensure(info)) end
    end
    UpdateAll()
end

function M:Init()
    NS.On("PLAYER_REGEN_DISABLED", function() CombatText(true) end)
    NS.On("PLAYER_REGEN_ENABLED", function() CombatText(false) end)
    -- combat state has no event for every unit, so a light poll keeps it current
    ticker = CreateFrame("Frame")
    local acc = 0
    ticker:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 0.2 then return end
        acc = 0
        if S().enabled then UpdateAll() end
    end)
    for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "UNIT_FLAGS" }) do
        NS.On(ev, function() if S().enabled then UpdateAll() end end)
    end
end

function M:Diagnose()
    local parts = {}
    for _, info in ipairs(UNITS) do
        local f = icons[info.unit]
        parts[#parts + 1] = info.unit .. "=" .. (f and (f:IsShown() and "shown" or "hidden") or "none")
            .. (Anchor(info) and "" or " (frame missing)")
    end
    NS.Print("  " .. table.concat(parts, "   ") .. "   secret reads: " .. M.stats.secret)
end

function M.Build(page)
    page:Section("+Combat / -Combat", "Text in the middle of your screen when you enter and leave combat")
    page:Check("Show +Combat / -Combat", function() return T().enabled end,
        function(v) T().enabled = v; NS.ApplyModule("combatind") end)
    page:Check("+Combat when you enter combat", function() return T().showEnter end,
        function(v) T().showEnter = v end)
    page:Check("-Combat when you leave combat", function() return T().showLeave end,
        function(v) T().showLeave = v end)
    page:Color("+Combat color", function() return T().enterColor end,
        function(r, g, b) local c = T().enterColor; c[1], c[2], c[3] = r, g, b end)
    page:Color("-Combat color", function() return T().leaveColor end,
        function(r, g, b) local c = T().leaveColor; c[1], c[2], c[3] = r, g, b end)
    page:Slider("Text size", 12, 72, 1, function() return T().size end,
        function(v) T().size = v; TextAlert():Layout() end)
    page:Slider("Stays on screen (seconds)", 0.5, 5, 0.5, function() return T().duration end,
        function(v) T().duration = v end, function(v) return string.format("%.1f s", v) end)
    page:Check("Lock position", function() return T().locked end,
        function(v) T().locked = v; TextAlert():Layout() end)
    page:Note("Untick \"Lock position\" to show the text and drag it anywhere, then lock it again.")
    page:Button("Test", function()
        if not (S().enabled and T().enabled) then NS.Print("Turn on Combat Indicator and \"Show +Combat / -Combat\" first."); return end
        CombatText(true)
        C_Timer.After(T().duration + 0.3, function() CombatText(false) end)
    end)
    page:Button("Reset position", function()
        local p = T().point; p[1], p[2], p[3], p[4] = "CENTER", "CENTER", 0, 60
        TextAlert():Layout()
    end)

    page:Section("Which frames", "Where the combat icon shows")
    page:Check("Target", function() return S().target end, function(v) S().target = v; NS.ApplyModule("combatind") end)
    page:Check("Focus", function() return S().focus end, function(v) S().focus = v; NS.ApplyModule("combatind") end)
    page:Check("Player (yourself)", function() return S().player end,
        function(v) S().player = v; NS.ApplyModule("combatind") end)
    page:Check("Only for players (not NPCs)", function() return S().playersOnly end,
        function(v) S().playersOnly = v; UpdateAll() end)

    page:Section("What it shows", "In combat, out of combat or both")
    page:Check("Swords while in combat", function() return S().showIn end, function(v) S().showIn = v; UpdateAll() end)
    page:Check("Zzz while out of combat", function() return S().showOut end, function(v) S().showOut = v; UpdateAll() end)

    page:Section("Size and position", "Next to the unit frame")
    page:Slider("Icon size", 12, 48, 1, function() return S().size end,
        function(v) S().size = v; PlaceAll() end)
    page:Slider("Move left / right", -200, 200, 1, function() return S().x end,
        function(v) S().x = v; PlaceAll() end)
    page:Slider("Move up / down", -200, 200, 1, function() return S().y end,
        function(v) S().y = v; PlaceAll() end)
end
