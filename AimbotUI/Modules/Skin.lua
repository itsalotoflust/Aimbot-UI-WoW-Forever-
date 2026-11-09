--[[
  Aimbot UI - Interface Skin module (LortiUI-style)
  Flat dark action buttons, short keybind text, class-colored health bars,
  darkened frame art, hidden gryphons. Only touches colors / alpha / textures,
  never protected state, so it is safe in combat.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Interface Skin",
    desc = "Dark, minimal look in the style of LortiUI: flat action buttons, class-colored "
        .. "health bars, darkened frames, no gryphons.",
    defaults = {
        enabled        = true,
        skinButtons    = true,
        borderColor    = { 0, 0, 0, 1 },
        bgAlpha        = 0.6,
        iconCrop       = 0.07,
        shortHotkeys   = true,
        hideMacroNames = true,
        classColorBars = true,
        darkFrames     = true,
        tint           = 0.25,
        hideGryphons   = true,
    },
}
NS.RegisterModule("skin", M)

local function S() return NS.db.mod.skin end

local skinned = {}       -- btn -> { border, edges, bg }
local hookedButtons = {} -- btn -> true
local hookedBars = {}    -- bar -> true

----------------------------------------------------------------------
-- Keybind text
----------------------------------------------------------------------
local HOTKEY_REPLACEMENTS = {
    { "Mouse Wheel Up", "MwU" }, { "Mouse Wheel Down", "MwD" },
    { "Middle Mouse", "MM" },    { "Mouse Button ", "M" },
    { "Num Pad ", "N" },         { "Numpad ", "N" },
    { "Page Up", "PU" },         { "Page Down", "PD" },
    { "Spacebar", "Sp" },        { "Insert", "Ins" },
    { "Delete", "Del" },         { "Home", "Hm" },
    { "End", "En" },
    { "Shift%-", "S" }, { "Ctrl%-", "C" }, { "Alt%-", "A" },
    { "SHIFT%-", "S" }, { "CTRL%-", "C" }, { "ALT%-", "A" },
    { "s%-", "S" },     { "c%-", "C" },    { "a%-", "A" },
}

local function ShortenHotkey(btn)
    local s = S()
    if not (s.enabled and s.shortHotkeys) then return end
    local hk = btn.HotKey
    if not hk and btn.GetName and btn:GetName() then hk = _G[btn:GetName() .. "HotKey"] end
    if not hk or not hk.GetText then return end
    local text = hk:GetText()
    if type(text) ~= "string" or NS.IsSecret(text) or text == "" or text == RANGE_INDICATOR then return end
    local out = text
    for _, r in ipairs(HOTKEY_REPLACEMENTS) do
        out = out:gsub(r[1], r[2])
    end
    if out ~= text then hk:SetText(out) end
end

----------------------------------------------------------------------
-- Action buttons
----------------------------------------------------------------------
local function MakeBorder(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 3)
    f:EnableMouse(false)
    local edges = {}
    local function Edge(p1, p2, w, h)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        table.insert(edges, t)
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 1)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    return f, edges
end

local function ApplyButton(btn)
    local s = S()
    local on = s.enabled and s.skinButtons
    local st = skinned[btn]

    if not st then
        if not on then return end
        st = {}
        skinned[btn] = st
        st.border, st.edges = MakeBorder(btn)
        st.bg = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
        st.bg:SetAllPoints(btn)
    end

    local bc = s.borderColor
    for _, e in ipairs(st.edges) do e:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 1) end
    st.bg:SetColorTexture(0.05, 0.05, 0.05, s.bgAlpha)
    st.border:SetShown(on and true or false)
    st.bg:SetShown(on and true or false)

    local icon = btn.icon or btn.Icon
    if not icon and btn.GetName and btn:GetName() then icon = _G[btn:GetName() .. "Icon"] end
    if icon and icon.SetTexCoord then
        if on then
            local c = s.iconCrop
            icon:SetTexCoord(c, 1 - c, c, 1 - c)
            if btn.IconMask and icon.RemoveMaskTexture then
                pcall(icon.RemoveMaskTexture, icon, btn.IconMask)
            end
        else
            icon:SetTexCoord(0, 1, 0, 1)
            if btn.IconMask and icon.AddMaskTexture then
                pcall(icon.AddMaskTexture, icon, btn.IconMask)
            end
        end
    end

    local nt = btn.NormalTexture or (btn.GetNormalTexture and btn:GetNormalTexture())
    if nt and nt.SetAlpha then nt:SetAlpha(on and 0 or 1) end
    if btn.SlotArt and btn.SlotArt.SetAlpha then btn.SlotArt:SetAlpha(on and 0 or 1) end
    if btn.SlotBackground and btn.SlotBackground.SetAlpha then btn.SlotBackground:SetAlpha(on and 0 or 1) end

    if btn.Name and btn.Name.SetAlpha then
        btn.Name:SetAlpha((s.enabled and s.hideMacroNames) and 0 or 1)
    end

    ShortenHotkey(btn)
end

local function HookButtonUpdates(btn)
    if hookedButtons[btn] then return end
    hookedButtons[btn] = true
    for _, method in ipairs({ "Update", "UpdateButtonArt", "UpdateHotkeys" }) do
        if type(btn[method]) == "function" then
            hooksecurefunc(btn, method, function() ApplyButton(btn) end)
        end
    end
end

local function ApplyButtons()
    NS.ForEachButton(function(btn)
        ApplyButton(btn)
        if skinned[btn] then HookButtonUpdates(btn) end
    end)
end

----------------------------------------------------------------------
-- Class-colored health bars
----------------------------------------------------------------------
local HEALTHBARS = {
    { unit = "player", paths = {
        "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar",
        "PlayerFrameHealthBar" } },
    { unit = "target", paths = {
        "TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar",
        "TargetFrameHealthBar" } },
    { unit = "focus", paths = {
        "FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar",
        "FocusFrameHealthBar" } },
}

local function ColorBar(bar, unit)
    if not bar or not bar.SetStatusBarColor then return end
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then bar:SetStatusBarColor(c.r, c.g, c.b) end
end

local function ColorBars()
    local s = S()
    if not (s.enabled and s.classColorBars) then return end
    for _, entry in ipairs(HEALTHBARS) do
        local bar = NS.ResolveFirst(entry.paths)
        if bar then
            ColorBar(bar, entry.unit)
            if not hookedBars[bar] and bar.HookScript then
                hookedBars[bar] = true
                -- Arguments (health values) may be secret; we ignore them entirely.
                pcall(bar.HookScript, bar, "OnValueChanged", function()
                    local ss = S()
                    if ss.enabled and ss.classColorBars then ColorBar(bar, entry.unit) end
                end)
            end
        end
    end
end

----------------------------------------------------------------------
-- Dark frame art + gryphons
----------------------------------------------------------------------
local FRAME_ART = {
    "PlayerFrame.PlayerFrameContainer.FrameTexture", "PlayerFrameTexture",
    "TargetFrame.TargetFrameContainer.FrameTexture", "TargetFrameTextureFrameTexture",
    "FocusFrame.TargetFrameContainer.FrameTexture",  "FocusFrameTextureFrameTexture",
    "PetFrame.PetFrameContainer.FrameTexture",       "PetFrameTexture",
    "MainActionBar.BorderArt", "MainMenuBar.BorderArt",
}
local GRYPHONS = {
    "MainActionBar.EndCaps", "MainMenuBar.EndCaps",
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
}

local function ApplyDarkFrames()
    local s = S()
    local v = (s.enabled and s.darkFrames) and s.tint or 1
    for _, path in ipairs(FRAME_ART) do
        local t = NS.Resolve(path)
        if t and t.SetVertexColor then t:SetVertexColor(v, v, v) end
    end
end

local function ApplyGryphons()
    local s = S()
    local hide = s.enabled and s.hideGryphons
    for _, path in ipairs(GRYPHONS) do
        local f = NS.Resolve(path)
        if f and f.SetAlpha then f:SetAlpha(hide and 0 or 1) end
    end
end

----------------------------------------------------------------------
function M:Apply()
    ApplyButtons()
    ColorBars()
    ApplyDarkFrames()
    ApplyGryphons()
end

function M:Init()
    if type(_G.ActionButton_UpdateHotkeys) == "function" then
        hooksecurefunc("ActionButton_UpdateHotkeys", function(self)
            if NS.db and self then ShortenHotkey(self) end
        end)
    end
    if type(_G.UnitFrameHealthBar_Update) == "function" then
        hooksecurefunc("UnitFrameHealthBar_Update", function()
            if NS.db then ColorBars() end
        end)
    end
    local function Soon()
        M:Apply()
        if C_Timer and C_Timer.After then C_Timer.After(0, function() M:Apply() end) end
    end
    NS.On("PLAYER_TARGET_CHANGED", Soon)
    NS.On("PLAYER_FOCUS_CHANGED", Soon)
    NS.On("UNIT_FACTION", Soon)
end

----------------------------------------------------------------------
function M.Build(page)
    local function Bind(key)
        return function() return S()[key] end,
               function(v) S()[key] = v; NS.ApplyModule("skin") end
    end
    page:Header("Action buttons")
    page:Check("Flat dark button skin", Bind("skinButtons"))
    page:Color("Border color",
        function() return S().borderColor end,
        function(r, g, b, a) local c = S().borderColor; c[1], c[2], c[3], c[4] = r, g, b, a; NS.ApplyModule("skin") end)
    page:Slider("Slot background opacity", 0, 1, 0.05,
        function() return S().bgAlpha end,
        function(v) S().bgAlpha = v; NS.ApplyModule("skin") end,
        function(v) return string.format("%d%%", v * 100 + 0.5) end)
    page:Slider("Icon crop", 0, 0.15, 0.01,
        function() return S().iconCrop end,
        function(v) S().iconCrop = v; NS.ApplyModule("skin") end,
        function(v) return string.format("%.2f", v) end)
    page:Check("Short keybind text (S1, C2, M4...)", Bind("shortHotkeys"))
    page:Check("Hide macro names", Bind("hideMacroNames"))

    page:Header("Unit frames")
    page:Check("Class-colored health bars (player / target / focus)", Bind("classColorBars"))

    page:Header("Frame art")
    page:Check("Darken frame and action bar art", Bind("darkFrames"))
    page:Slider("Art brightness", 0, 1, 0.05,
        function() return S().tint end,
        function(v) S().tint = v; NS.ApplyModule("skin") end,
        function(v) return string.format("%d%%", v * 100 + 0.5) end)
    page:Check("Hide gryphons / end caps", Bind("hideGryphons"))

    page:Header("Diagnostics")
    page:Button("Report which Blizzard frames were found", function()
        local function R(label, paths)
            local _, found = NS.ResolveFirst(paths)
            NS.Print(label .. ": " .. (found and ("|cff00ff00" .. found .. "|r") or "|cffff4444not found|r"))
        end
        for _, e in ipairs(HEALTHBARS) do R(e.unit .. " health bar", e.paths) end
        for _, p in ipairs(FRAME_ART) do R("art", { p }) end
        for _, p in ipairs(GRYPHONS) do R("gryphon", { p }) end
        local b = _G["ActionButton1"]
        if b then
            NS.Print(string.format("ActionButton1: icon=%s mask=%s hotkey=%s name=%s",
                tostring(b.icon ~= nil), tostring(b.IconMask ~= nil),
                tostring(b.HotKey ~= nil), tostring(b.Name ~= nil)))
        else
            NS.Print("ActionButton1 not found")
        end
    end, 300)
    page:Note("Turning class colors off fully takes effect after /reload.")
end
