--[[
  Aimbot UI - Range Alert module
  * Action buttons turn red while your target is out of range of that spell,
    and go back to normal as soon as you are in range. The whole button icon is
    tinted (the same look Bartender uses), instead of a see-through overlay.
  * Optional "Whole bar" mode: a bar turns red only when the target is out of
    range of EVERY ranged spell on that bar.
  * Optional distance readout (an estimate built from the ranges of the spells
    on your bars, e.g. "8-30 yd").

  Uses C_ActionBar.IsActionInRange. Results the client flags as secret values
  are ignored (treated as "unknown"), so nothing here can error in combat.
  Only the icon's colour is changed (a method call, never a field write), so
  Blizzard's button code stays untainted.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Range Alert",
    group = "Combat",
    desc = "Turns your action buttons red when your target is out of range, and clears it when you "
        .. "get in range. Also shows an estimated distance to your target.",
    defaults = {
        enabled      = true,
        mode         = "button",              -- "button" or "bar"
        tint         = { 0.8, 0.1, 0.1 },       -- icon colour while out of range
        hostileOnly  = true,
        showReadout  = true,
        readoutSize  = 18,
        readoutLocked = true,
        readoutPoint = { "TOP", "TOP", 0, -160 },
        interval     = 0.15,
        goodColor    = { 0.30, 1.00, 0.30, 1 },     -- readout text when in range
        badColor     = { 1.00, 0.35, 0.35, 1 },     -- readout text when out of range
        readoutOutline = true,
    },
}
NS.RegisterModule("range", M)

local function S() return NS.db.mod.range end

local tinted = {}         -- btn -> true while we are holding it red
local rangeCache = {}    -- spellID -> { max, min }
local readout, readoutText, readoutBG

----------------------------------------------------------------------
-- Red icon on a button
----------------------------------------------------------------------
local function IconOf(btn)
    local icon = btn.icon or btn.Icon
    if not icon and btn.GetName then
        local n = btn:GetName()
        if n then icon = _G[n .. "Icon"] end
    end
    if icon and icon.SetVertexColor then return icon end
end

-- Back to the colour the game would normally give the icon.
local function RestoreIcon(btn, icon)
    local r, g, b = 1, 1, 1
    local action = NS.GetAction(btn)
    local fn = action and ((C_ActionBar and C_ActionBar.IsUsableAction) or IsUsableAction)
    if fn then
        local ok, usable, noMana = pcall(fn, action)
        if ok and not NS.IsSecret(usable) and not NS.IsSecret(noMana) and not usable then
            if noMana then r, g, b = 0.5, 0.5, 1.0 else r, g, b = 0.4, 0.4, 0.4 end
        end
    end
    icon:SetVertexColor(r, g, b)
end

local function SetRed(btn, on)
    local icon = IconOf(btn)
    if not icon then return end
    if on then
        local c = S().tint
        icon:SetVertexColor(c[1], c[2], c[3])       -- every tick: the game re-colours icons on its own updates
        tinted[btn] = true
    elseif tinted[btn] then
        tinted[btn] = nil
        RestoreIcon(btn, icon)
    end
end

local function ClearAll()
    for btn in pairs(tinted) do SetRed(btn, false) end
end

----------------------------------------------------------------------
-- Range checks
----------------------------------------------------------------------
-- returns true (in range) / false (out of range) / nil (unknown or n/a)
local function InRange(action)
    local fn = (C_ActionBar and C_ActionBar.IsActionInRange) or IsActionInRange
    if not fn then return nil end
    local ok, r = pcall(fn, action, "target")
    if not ok or r == nil or NS.IsSecret(r) then return nil end
    if r == true or r == 1 then return true end
    if r == false or r == 0 then return false end
    return nil
end

local function SpellRange(spellID)
    local c = rangeCache[spellID]
    if c then return c[1], c[2] end
    local maxR, minR = 0, 0
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then
            if type(info.maxRange) == "number" and not NS.IsSecret(info.maxRange) then maxR = info.maxRange end
            if type(info.minRange) == "number" and not NS.IsSecret(info.minRange) then minR = info.minRange end
        end
    end
    rangeCache[spellID] = { maxR, minR }
    return maxR, minR
end

local function TargetValid()
    local s = S()
    if not UnitExists("target") then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("target") then return false end
    if s.hostileOnly and not UnitCanAttack("player", "target") then return false end
    return true
end

----------------------------------------------------------------------
-- Readout frame
----------------------------------------------------------------------
local function ApplyReadoutPosition()
    if not readout then return end
    local p = S().readoutPoint
    readout:ClearAllPoints()
    readout:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function SaveReadoutPosition()
    local point, _, relPoint, x, y = readout:GetPoint()
    if point then
        local p = S().readoutPoint
        p[1], p[2], p[3], p[4] = point, relPoint, x, y
    end
end

local function ApplyReadoutStyle()
    if not readout then return end
    local s = S()
    readoutText:SetFont(STANDARD_TEXT_FONT, s.readoutSize, s.readoutOutline and "OUTLINE" or "")
    readout:SetSize(160, s.readoutSize + 10)
    readout:SetShown(s.enabled and s.showReadout)
    readout:EnableMouse(not s.readoutLocked)
    readoutBG:SetShown(not s.readoutLocked)
    if not s.readoutLocked then readoutText:SetText("Range readout (drag me)") end
end

local function EnsureReadout()
    if readout then return end
    readout = CreateFrame("Frame", "AimbotUIRangeReadout", UIParent)
    readout:SetFrameStrata("HIGH")
    readout:SetMovable(true)
    readout:SetClampedToScreen(true)
    readout:RegisterForDrag("LeftButton")
    readout:SetScript("OnDragStart", function(self) if not S().readoutLocked then self:StartMoving() end end)
    readout:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveReadoutPosition() end)
    readoutBG = readout:CreateTexture(nil, "BACKGROUND")
    readoutBG:SetAllPoints()
    readoutBG:SetColorTexture(0.2, 0.6, 1, 0.3)
    readoutText = readout:CreateFontString(nil, "OVERLAY")
    readoutText:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE")
    readoutText:SetPoint("CENTER")
    ApplyReadoutPosition()
    ApplyReadoutStyle()
end

local function HideReadout()
    if readout and S().readoutLocked then readoutText:SetText("") end
end

----------------------------------------------------------------------
-- Main tick
----------------------------------------------------------------------
local function Tick()
    local s = S()
    if not s.enabled or not TargetValid() then
        ClearAll()
        HideReadout()
        return
    end

    local states = {}     -- btn -> true/false/nil
    local bars = {}       -- prefix -> { n, inRange }
    local lower, upper = 0, math.huge
    local seen = {}

    NS.ForEachButton(function(btn, prefix)
        local action = NS.GetAction(btn)
        local r
        if action and HasAction(action) then
            r = InRange(action)
            if r ~= nil then
                local spellID = NS.SpellForAction(action)
                if spellID and not seen[spellID] then
                    seen[spellID] = true
                    local maxR, minR = SpellRange(spellID)
                    if minR == 0 then
                        local reach = (maxR > 0) and maxR or 5   -- 0 = melee (~5 yd)
                        if r then
                            if reach < upper then upper = reach end
                        else
                            if reach > lower then lower = reach end
                        end
                    end
                end
            end
        end
        states[btn] = r
        local b = bars[prefix]
        if not b then b = { n = 0, inRange = 0 }; bars[prefix] = b end
        if r ~= nil then
            b.n = b.n + 1
            if r then b.inRange = b.inRange + 1 end
        end
    end)

    NS.ForEachButton(function(btn, prefix)
        if s.mode == "bar" then
            local b = bars[prefix]
            SetRed(btn, b and b.n > 0 and b.inRange == 0)
        else
            SetRed(btn, states[btn] == false)
        end
    end)

    if s.showReadout then
        EnsureReadout()
        local text, good
        if upper < math.huge and lower > 0 then
            text = string.format("%d-%d yd", math.floor(lower), math.floor(upper)); good = true
        elseif upper < math.huge then
            text = string.format("< %d yd", math.floor(upper)); good = true
        elseif lower > 0 then
            text = string.format("> %d yd", math.floor(lower)); good = false
        end
        if s.readoutLocked then
            readoutText:SetText(text or "")
        end
        local c = good and s.goodColor or s.badColor
        readoutText:SetTextColor(c[1], c[2], c[3])
    else
        HideReadout()
    end
end

----------------------------------------------------------------------
local ticker
local function EnsureTicker()
    if ticker then return end
    ticker = CreateFrame("Frame")
    local acc = 0
    ticker:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < (S().interval or 0.15) then return end
        acc = 0
        local ok, err = pcall(Tick)
        if not ok then NS.ReportError("Range Alert", err) end
    end)
end

function M:Apply()
    EnsureTicker()
    if S().showReadout then EnsureReadout() end
    ApplyReadoutPosition()
    ApplyReadoutStyle()
    if not S().enabled then
        ClearAll()
        if readout then readoutText:SetText("") end
    end
end

M._t = { Tick = Tick, ClearAll = ClearAll }

function M:Init()
    EnsureTicker()
    NS.On("PLAYER_TARGET_CHANGED", function()
        if not UnitExists("target") then ClearAll(); HideReadout() end
    end)
end

function M.Build(page)
    page:Section("Out-of-range warning", "Turn buttons red when your target is too far")
    page:Cycle("Red mode", {
            { "button", "Per button" },
            { "bar", "Whole bar" },
        },
        function() return S().mode end,
        function(v) S().mode = v end)
    page:Note("The whole button icon turns red. Per button: each spell turns red when your target is out of its range. "
        .. "Whole bar: a bar turns red only when the target is out of range of every ranged spell on it.")
    page:Color("Red color",
        function() return S().tint end,
        function(r, g, b) local c = S().tint; c[1], c[2], c[3] = r, g, b end)
    page:Check("Only for enemies I can attack", function() return S().hostileOnly end,
        function(v) S().hostileOnly = v end)

    page:Section("Distance readout", "The distance number: show, size, place")
    page:Check("Show estimated distance to target", function() return S().showReadout end,
        function(v) S().showReadout = v; NS.ApplyModule("range") end)
    page:Slider("Readout text size", 10, 40, 1,
        function() return S().readoutSize end,
        function(v) S().readoutSize = v; ApplyReadoutStyle() end)
    page:Check("Lock readout position", function() return S().readoutLocked end,
        function(v) S().readoutLocked = v; NS.ApplyModule("range") end)
    page:Note("Unlock to drag the readout anywhere. The distance is an estimate worked out from the "
        .. "ranges of the spells on your bars, so it needs a few ranged or melee spells on them.")
    page:Section("Readout colors", "Text colors and outline of the distance number")
    page:Color("In range",
        function() return S().goodColor end,
        function(r, g, b, a) local c = S().goodColor; c[1], c[2], c[3], c[4] = r, g, b, a or 1 end)
    page:Color("Out of range",
        function() return S().badColor end,
        function(r, g, b, a) local c = S().badColor; c[1], c[2], c[3], c[4] = r, g, b, a or 1 end)
    page:Check("Text outline", function() return S().readoutOutline end,
        function(v) S().readoutOutline = v; ApplyReadoutStyle() end)

    page:Section("Speed", "How often the range is checked")
    page:Slider("Check interval (seconds)", 0.05, 0.5, 0.05,
        function() return S().interval end,
        function(v) S().interval = v end,
        function(v) return string.format("%.2f", v) end)
end
