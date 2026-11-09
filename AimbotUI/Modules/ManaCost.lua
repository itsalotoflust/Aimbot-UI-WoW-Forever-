--[[
  Aimbot UI - Mana Costs module
  Shows the resource cost (mana / rage / energy / focus...) of each spell on
  your action buttons. Reads costs with C_Spell.GetSpellPowerCost and skips
  anything the client marks as a secret value.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Mana Costs",
    group = "Combat",
    desc = "Shows what each action bar spell costs, right on the button.",
    defaults = {
        enabled     = true,
        showMana    = true,
        showOther   = true,     -- rage, energy, focus, runic power...
        colorByType = true,
        redIfShort  = true,     -- turn red when you can't afford it
        anchor      = "TOPLEFT",
        offsetX     = 0,
        offsetY     = 0,
        fontSize    = 11,
        outline     = true,
        color       = { 0.45, 0.65, 1.0, 1 },   -- used when "color by type" is off
        fontFace    = "default",
        opacity     = 1,
        lowColor    = { 1.0, 0.15, 0.15, 1 },   -- "can't afford it" color
        colors      = {                          -- per resource, used when "color by type" is on
            mana   = { 0.45, 0.65, 1.00, 1 },
            rage   = { 1.00, 0.30, 0.30, 1 },
            focus  = { 1.00, 0.60, 0.20, 1 },
            energy = { 1.00, 0.95, 0.30, 1 },
            combo  = { 1.00, 0.85, 0.20, 1 },
            runic  = { 0.20, 0.85, 0.95, 1 },
        },
    },
}
NS.RegisterModule("manacost", M)

local function S() return NS.db.mod.manacost end

local POWER_KEYS = { [0] = "mana", [1] = "rage", [2] = "focus", [3] = "energy", [4] = "combo", [6] = "runic" }
local POWER_NAMES = {
    { "mana", "Mana" }, { "rage", "Rage" }, { "focus", "Focus" },
    { "energy", "Energy" }, { "combo", "Combo points" }, { "runic", "Runic power" },
}
local FACES = {
    { "default", "Game default" },
    { "Fonts\\FRIZQT__.TTF", "Friz Quadrata" },
    { "Fonts\\ARIALN.TTF", "Arial Narrow" },
    { "Fonts\\SKURRI.TTF", "Skurri (bold)" },
    { "Fonts\\MORPHEUS.TTF", "Morpheus (fancy)" },
}

local ANCHORS = {
    { "TOPLEFT", "Top left corner" }, { "TOP", "Top" }, { "TOPRIGHT", "Top right corner" },
    { "BOTTOMLEFT", "Bottom left corner" }, { "BOTTOM", "Bottom" }, { "BOTTOMRIGHT", "Bottom right corner" },
    { "CENTER", "Center" },
}

local labels = {}   -- btn -> { frame, fs }

local function GetLabel(btn)
    local t = labels[btn]
    if t then return t end
    local f = CreateFrame("Frame", nil, btn)
    f:SetAllPoints(btn)
    f:SetFrameLevel(btn:GetFrameLevel() + 6)
    f:EnableMouse(false)
    local fs = f:CreateFontString(nil, "OVERLAY")
    t = { frame = f, fs = fs }
    labels[btn] = t
    return t
end

local function Style(t)
    local s = S()
    local face = (s.fontFace ~= "default" and s.fontFace) or STANDARD_TEXT_FONT
    local flags = s.outline and "OUTLINE" or ""
    if t.fs:SetFont(face, s.fontSize, flags) == false then t.fs:SetFont(STANDARD_TEXT_FONT, s.fontSize, flags) end
    t.fs:SetAlpha(s.opacity or 1)
    t.fs:ClearAllPoints()
    local x = s.anchor:find("LEFT") and 2 or (s.anchor:find("RIGHT") and -2 or 0)
    local y = s.anchor:find("TOP") and -2 or (s.anchor:find("BOTTOM") and 2 or 0)
    t.fs:SetPoint(s.anchor, t.frame, s.anchor, x + (s.offsetX or 0), y + (s.offsetY or 0))
end

local function CostFor(spellID)
    local fn = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    if not fn then return end
    local ok, costs = pcall(fn, spellID)
    if not ok or type(costs) ~= "table" then return end
    for _, c in ipairs(costs) do
        local cost = c.cost
        if cost and not NS.IsSecret(cost) and cost > 0 then
            return cost, c.type
        end
    end
end

local function Unaffordable(action)
    if not IsUsableAction then return false end
    local ok, usable, noMana = pcall(IsUsableAction, action)
    if not ok or NS.IsSecret(noMana) then return false end
    return noMana and true or false
end

local function UpdateButton(btn)
    local s = S()
    local t = labels[btn]

    if not s.enabled then
        if t then t.fs:SetText("") end
        return
    end

    local action = NS.GetAction(btn)
    local spellID = action and NS.SpellForAction(action)
    local cost, ptype
    if spellID then cost, ptype = CostFor(spellID) end

    if cost and ptype ~= nil then
        local isMana = (ptype == 0)
        if (isMana and not s.showMana) or (not isMana and not s.showOther) then cost = nil end
    end

    if not cost then
        if t then t.fs:SetText("") end
        return
    end

    t = GetLabel(btn)
    Style(t)
    t.fs:SetText(tostring(cost))

    local r, g, b
    if s.redIfShort and Unaffordable(action) then
        local c = s.lowColor
        r, g, b = c[1], c[2], c[3]
    elseif s.colorByType then
        local key = POWER_KEYS[ptype]
        local c = (key and s.colors[key]) or { 1, 1, 1 }
        r, g, b = c[1], c[2], c[3]
    else
        r, g, b = s.color[1], s.color[2], s.color[3]
    end
    t.fs:SetTextColor(r, g, b)
end

local function UpdateAll()
    NS.ForEachButton(UpdateButton)
end

local pending = false
local function UpdateSoon()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function() pending = false; UpdateAll() end)
end

function M:Apply() UpdateAll() end

function M:Init()
    for _, ev in ipairs({
        "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED", "ACTIONBAR_UPDATE_USABLE",
        "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "UPDATE_SHAPESHIFT_FORM",
        "UNIT_POWER_UPDATE",
    }) do
        NS.On(ev, function(_, unit)
            if ev == "UNIT_POWER_UPDATE" and unit ~= "player" then return end
            UpdateSoon()
        end)
    end
    NS.On("UNIT_AURA", function(_, unit)
        if unit == "player" then UpdateSoon() end  -- auras can discount costs
    end)
end

function M.Build(page)
    page:Section("What to show", "Which resources get a number on the button")
    page:Check("Mana costs", function() return S().showMana end,
        function(v) S().showMana = v; UpdateAll() end)
    page:Check("Other resources (rage, energy, focus...)", function() return S().showOther end,
        function(v) S().showOther = v; UpdateAll() end)
    page:Check("Turn a different color when I can't afford the spell", function() return S().redIfShort end,
        function(v) S().redIfShort = v; UpdateAll() end)

    page:Section("Position and size", "Where the number sits on the button, its size and font")
    page:Cycle("Position on the button", ANCHORS,
        function() return S().anchor end,
        function(v) S().anchor = v; UpdateAll() end)
    page:Slider("Move text left / right", -15, 15, 1,
        function() return S().offsetX end,
        function(v) S().offsetX = v; UpdateAll() end,
        function(v) return string.format("%d", math.floor(v + 0.5)) end)
    page:Slider("Move text up / down", -15, 15, 1,
        function() return S().offsetY end,
        function(v) S().offsetY = v; UpdateAll() end,
        function(v) return string.format("%d", math.floor(v + 0.5)) end)
    page:Note("Item counts sit in the bottom right corner and macro names along the bottom, so if the cost "
        .. "overlaps them use the two sliders above to nudge it.")
    page:Slider("Text size", 7, 20, 1,
        function() return S().fontSize end,
        function(v) S().fontSize = v; UpdateAll() end)
    page:Cycle("Font", FACES,
        function() return S().fontFace end,
        function(v) S().fontFace = v; UpdateAll() end)
    page:Slider("Text opacity", 0.2, 1, 0.05,
        function() return S().opacity end,
        function(v) S().opacity = v; UpdateAll() end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
    page:Check("Text outline", function() return S().outline end,
        function(v) S().outline = v; UpdateAll() end)

    page:Section("Colors", "One color per resource, plus the can't-afford color")
    page:Check("Color by resource type", function() return S().colorByType end,
        function(v) S().colorByType = v; UpdateAll() end)
    for _, p in ipairs(POWER_NAMES) do
        local key = p[1]
        page:Color(p[2],
            function() return S().colors[key] end,
            function(r, g, b, a) local c = S().colors[key]; c[1], c[2], c[3], c[4] = r, g, b, a or 1; UpdateAll() end)
    end
    page:Color("Can't afford it",
        function() return S().lowColor end,
        function(r, g, b, a) local c = S().lowColor; c[1], c[2], c[3], c[4] = r, g, b, a or 1; UpdateAll() end)
    page:Color("One color for everything (when \"color by resource type\" is off)",
        function() return S().color end,
        function(r, g, b, a) local c = S().color; c[1], c[2], c[3], c[4] = r, g, b, a; UpdateAll() end)
    page:Button("Reset these colors", function()
        local d = M.defaults
        local s = S()
        for k, v in pairs(d.colors) do s.colors[k] = { v[1], v[2], v[3], v[4] } end
        s.lowColor = { d.lowColor[1], d.lowColor[2], d.lowColor[3], d.lowColor[4] }
        s.color = { d.color[1], d.color[2], d.color[3], d.color[4] }
        UpdateAll()
        NS.UI.RefreshAll()
    end, 220)
end
