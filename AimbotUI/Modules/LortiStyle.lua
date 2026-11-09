--[[
  Aimbot UI - Lorti Style
  A port of "Lorti UI Classic" (Lorti, Chordsy, Macumba, Knall, Jozh, Xyz, Arrone,
  Redskin) to the Retail-style frames that WoW Forever uses.

  The original addon targets Classic Era's old frame layout, which Forever does not
  have, so the logic is re-done against the Retail layout. Lorti's real artwork is
  bundled in the media folder and used as-is: gloss borders, outer shadow, pushed /
  hover / checked / flash textures, flat bar texture and class portraits.

  Safety rules this module follows (Midnight-era clients are strict):
    * never writes custom fields onto Blizzard frames (that taints them)
    * never reads health/power numbers, only colors, alpha, textures and fonts
    * creates new frames only out of combat
  Every lookup is guarded: a frame that doesn't exist on this client is skipped
  and listed in "Run diagnostics" instead of causing an error.
]]

local ADDON_NAME, NS = ...

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"
local TEX = {
    gloss   = MEDIA .. "gloss",
    gloss3  = MEDIA .. "gloss3",
    flash   = MEDIA .. "flash",
    hover   = MEDIA .. "hover",
    pushed  = MEDIA .. "pushed",
    checked = MEDIA .. "checked",
    shadow  = MEDIA .. "outer_shadow",
    back    = MEDIA .. "button_background",
    flat    = MEDIA .. "flat",
    classes = MEDIA .. "classes\\",
}
local CLASS_FILES = {
    DEATHKNIGHT = true, DRUID = true, HUNTER = true, MAGE = true, PALADIN = true,
    PRIEST = true, ROGUE = true, SHAMAN = true, WARLOCK = true, WARRIOR = true,
}

local M = {
    name  = "Lorti Style",
    group = "Style",
    desc  = "The LortiUI look on Forever's frames: glossy dark action buttons with a shadow, "
        .. "darkened unit frames and windows, class colors, class portraits, flat bars and cleaner buffs.",
    defaults = {
        enabled = true,

        -- action bars
        buttons      = true,
        gloss        = false,
        shadow       = true,
        slotBack     = true,
        iconCrop     = true,
        borderTint   = { 1, 1, 1, 1 },
        classBorder  = false,
        edge         = true,               -- solid edge that hides stray icon pixels at the corners
        edgeSize     = 2,
        edgeColor    = { 0, 0, 0, 1 },
        hideHotkeys  = false,
        hideMacro    = false,
        hotkeyFont   = 12,
        macroFont    = 12,
        countFont    = 12,
        hideBarArt   = false,
        customText   = false,
        macroColor   = { 1, 1, 1, 1 },
        countColor   = { 1, 1, 1, 1 },

        -- unit frames
        darkFrames   = true,
        frameShade   = 0.12,
        solidNames   = true,               -- solid bar behind unit names instead of the faded art
        artShade     = 0.35,
        classBars    = false,
        reactionBars = true,
        classPortraits = false,
        flatBars     = false,
        customHealth = false,
        healthColor  = { 0.20, 0.85, 0.30, 1 },
        customMana   = false,
        manaColor    = { 0.30, 0.50, 1.00, 1 },
        hideHit      = true,

        -- buffs / debuffs
        auras        = true,

        -- windows
        darkWindows  = true,

        -- interface
        minimapZoom  = true,
        hideZoomBtns = true,
        hideErrors   = true,
    },
}
NS.RegisterModule("lorti", M)

local function S() return NS.db.mod.lorti end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function Shade(paths, v)
    for _, p in ipairs(paths) do
        local t = NS.Resolve(p)
        if t and t.SetVertexColor then t:SetVertexColor(v, v, v) end
    end
end

local function SetAlphaOf(paths, a)
    for _, p in ipairs(paths) do
        local f = NS.Resolve(p)
        if f and f.SetAlpha then f:SetAlpha(a) end
    end
end

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    if not class then return end
    if class == "SHAMAN" then return 0, 0.44, 0.87 end   -- Lorti's shaman blue
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
end

local needsCombatPass = false

----------------------------------------------------------------------
-- Action buttons
----------------------------------------------------------------------
local styled  = {}   -- button -> { border, shadow, back }   (local table: no fields on Blizzard frames)
local hooked  = {}   -- button -> true

local function ButtonList()
    local list = {}
    NS.ForEachButton(function(btn) list[#list + 1] = btn end)
    for i = 1, 10 do
        local p = _G["PetActionButton" .. i]; if p then list[#list + 1] = p end
        local s = _G["StanceButton" .. i];    if s then list[#list + 1] = s end
    end
    for i = 1, 2 do
        local p = _G["PossessButton" .. i];   if p then list[#list + 1] = p end
    end
    return list
end

local function MakeShadow(btn)
    if not (CreateFrame and BackdropTemplateMixin) then return end
    local ok, bg = pcall(CreateFrame, "Frame", nil, btn, "BackdropTemplate")
    if not ok or not bg then return end
    bg:EnableMouse(false)
    bg:SetPoint("TOPLEFT", btn, "TOPLEFT", -4, 4)
    bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 4, -4)
    bg:SetFrameLevel(math.max(0, btn:GetFrameLevel() - 1))
    bg:SetBackdrop({
        edgeFile = TEX.shadow, edgeSize = 4.85, tile = false,
        insets = { left = 4.85, right = 4.85, top = 4.85, bottom = 4.85 },
    })
    bg:SetBackdropBorderColor(0.05, 0.05, 0.05, 1)
    return bg
end

local function StyleButton(btn)
    local s = S()
    local on = s.enabled and s.buttons and true or false
    local st = styled[btn]

    if not st then
        if not on then return end
        if InCombatLockdown() then needsCombatPass = true; return end
        st = {}
        styled[btn] = st
        st.border = btn:CreateTexture(nil, "ARTWORK", nil, 3)
        st.border:SetAllPoints(btn)
        st.back = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
        st.back:SetAllPoints(btn)
        st.back:SetTexture(TEX.back)
        st.shadow = MakeShadow(btn)
        -- Solid frame on top of the gloss. The gloss art has see-through corners, so
        -- the corner pixels of the icon (often bright) peeked out as white/colored dots.
        st.edges = {}
        for i = 1, 4 do
            local e = btn:CreateTexture(nil, "ARTWORK", nil, 5)
            e:SetColorTexture(0, 0, 0, 1)
            st.edges[i] = e
        end
    end

    -- Lorti border + slot background + outer shadow
    st.border:SetTexture(s.gloss and TEX.gloss3 or TEX.gloss)
    st.border:SetTexCoord(0, 1, 0, 1)
    local r, g, b, a = s.borderTint[1], s.borderTint[2], s.borderTint[3], s.borderTint[4] or 1
    if s.classBorder then
        local cr, cg, cb = ClassColor("player")
        if cr then r, g, b = cr, cg, cb end
    end
    st.border:SetVertexColor(r, g, b, a)
    st.border:SetShown(on)
    st.back:SetShown(on and s.slotBack and true or false)

    -- solid edge: top, bottom, left, right
    do
        local show = on and s.edge and true or false
        local sz = math.max(1, s.edgeSize or 2)
        local c = s.edgeColor or { 0, 0, 0, 1 }
        local e = st.edges
        if e then
            e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0); e[1]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0); e[1]:SetHeight(sz)
            e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0); e[2]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0); e[2]:SetHeight(sz)
            e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0); e[3]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0); e[3]:SetWidth(sz)
            e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0); e[4]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0); e[4]:SetWidth(sz)
            for i = 1, 4 do
                e[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
                e[i]:SetShown(show)
            end
        end
    end
    st.back:SetVertexColor(0.2, 0.2, 0.2, 0.55)
    if st.shadow then st.shadow:SetShown(on and s.shadow and true or false) end

    -- Blizzard's own button art
    local nt = btn.NormalTexture or (btn.GetNormalTexture and btn:GetNormalTexture())
    if nt and nt.SetAlpha then nt:SetAlpha(on and 0 or 1) end
    for _, key in ipairs({ "SlotBackground", "SlotArt", "FlyoutBorder", "FlyoutBorderShadow" }) do
        local part = btn[key]
        if part and part.SetAlpha then part:SetAlpha(on and 0 or 1) end
    end

    -- icon: square crop, no rounded mask
    local icon = btn.icon or btn.Icon
    if icon and icon.SetTexCoord then
        local crop = on and s.iconCrop
        if crop then icon:SetTexCoord(0.1, 0.9, 0.1, 0.9) else icon:SetTexCoord(0, 1, 0, 1) end
        if btn.IconMask and icon.RemoveMaskTexture and icon.AddMaskTexture then
            if on then pcall(icon.RemoveMaskTexture, icon, btn.IconMask)
            else pcall(icon.AddMaskTexture, icon, btn.IconMask) end
        end
    end

    -- Lorti's pushed / hover / checked / flash textures
    if on then
        local pt = btn.GetPushedTexture and btn:GetPushedTexture()
        if pt and pt.SetTexture then pt:SetTexture(TEX.pushed); pt:SetAllPoints(btn) end
        local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()
        if ht and ht.SetTexture then ht:SetTexture(TEX.hover); ht:SetAllPoints(btn); ht:SetBlendMode("ADD") end
        local ct = btn.GetCheckedTexture and btn:GetCheckedTexture()
        if ct and ct.SetTexture then ct:SetTexture(TEX.checked); ct:SetAllPoints(btn) end
        if btn.Flash and btn.Flash.SetTexture then btn.Flash:SetTexture(TEX.flash) end
    end

    -- text
    local hk = btn.HotKey
    if hk and hk.SetAlpha then
        hk:SetAlpha((on and s.hideHotkeys) and 0 or 1)
        if on and not s.hideHotkeys then
            hk:SetFont(STANDARD_TEXT_FONT, s.hotkeyFont, "OUTLINE")
            hk:ClearAllPoints()
            hk:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -3)
            hk:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -3)
            hk:SetJustifyH("RIGHT")
        end
    end
    local nm = btn.Name
    if nm and nm.SetAlpha then
        nm:SetAlpha((on and s.hideMacro) and 0 or 1)
        if on and not s.hideMacro then
            nm:SetFont(STANDARD_TEXT_FONT, s.macroFont, "OUTLINE")
            local mc = s.customText and s.macroColor or { 1, 1, 1 }
            nm:SetTextColor(mc[1], mc[2], mc[3])
            nm:ClearAllPoints()
            nm:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
            nm:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        end
    end
    local co = btn.Count
    if co and co.SetFont and on then
        co:SetFont(STANDARD_TEXT_FONT, s.countFont, "OUTLINE")
        local cc = s.customText and s.countColor or { 1, 1, 1 }
        co:SetTextColor(cc[1], cc[2], cc[3])
        co:ClearAllPoints()
        co:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end
end

local function HookButton(btn)
    if hooked[btn] then return end
    hooked[btn] = true
    -- Blizzard re-applies its art from these; re-skin right after.
    for _, method in ipairs({ "UpdateButtonArt", "UpdateHotkeys" }) do
        if type(btn[method]) == "function" then
            pcall(hooksecurefunc, btn, method, function() StyleButton(btn) end)
        end
    end
end

local function ApplyButtons()
    for _, btn in ipairs(ButtonList()) do
        StyleButton(btn)
        if styled[btn] then HookButton(btn) end
    end
end

----------------------------------------------------------------------
-- Action bar background / gryphons
----------------------------------------------------------------------
local BAR_ART = {
    "MainActionBar.BorderArt", "MainMenuBar.BorderArt",
    "MainActionBar.Background", "MainMenuBar.Background",
    "MainActionBar.EndCaps", "MainMenuBar.EndCaps",
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
    "StanceBar.Background", "PetActionBar.Background",
}

local function ApplyBarArt()
    local s = S()
    SetAlphaOf(BAR_ART, (s.enabled and s.hideBarArt) and 0 or 1)
end

----------------------------------------------------------------------
-- Unit frames: dark art
----------------------------------------------------------------------
local FRAME_ART = {
    "PlayerFrame.PlayerFrameContainer.FrameTexture",
    "PlayerFrame.PlayerFrameContainer.VehicleFrameTexture",
    "PlayerFrame.PlayerFrameContainer.AlternatePowerFrameTexture",
    "PlayerFrameTexture",
    "TargetFrame.TargetFrameContainer.FrameTexture",
    "TargetFrameTextureFrameTexture",
    "FocusFrame.TargetFrameContainer.FrameTexture",
    "FocusFrameTextureFrameTexture",
    "PetFrameTexture", "PetFrame.FrameTexture",
    "TargetFrameToT.FrameTexture", "TargetFrame.totFrame.FrameTexture",
    "FocusFrameToT.FrameTexture", "FocusFrame.totFrame.FrameTexture",
}
local OTHER_ART = {
    "MainActionBar.BorderArt", "MainMenuBar.BorderArt",
    "MinimapCompassTexture", "MinimapCluster.BorderTop",
}

-- The colored strip behind the unit name (hostile red, neutral yellow, friendly green).
-- The game's art for it fades out toward the edge. Swapping the art for a solid texture
-- doesn't work, because the art only fills part of its box (it ran under the portrait).
-- So the game's strip is faded to alpha 0 and our own solid bar is drawn exactly over the
-- health bar's width, at the strip's height, in the color the game gave the strip.
local NAME_BG_PATHS = {
    { strip = "TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor", unit = "target" },
    { strip = "FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor",  unit = "focus" },
    { strip = "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ReputationColor", unit = "player" },
}
local SOLID = "Interface\\Buttons\\WHITE8X8"
local nameBars = setmetatable({}, { __mode = "k" })   -- game strip -> our texture (our own table)

local function ApplyFrameArt()
    local s = S()
    local dark = s.enabled and s.darkFrames
    Shade(FRAME_ART, dark and s.frameShade or 1)
    Shade(OTHER_ART, dark and s.artShade or 1)
end

----------------------------------------------------------------------
-- Unit frames: bar colors, flat bars
----------------------------------------------------------------------
local HEALTH_BARS = {
    { unit = "player", paths = {
        "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar",
        "PlayerFrameHealthBar" } },
    { unit = "target", paths = {
        "TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar",
        "TargetFrameHealthBar" } },
    { unit = "focus", paths = {
        "FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar",
        "FocusFrameHealthBar" } },
    { unit = "targettarget", paths = {
        "TargetFrameToT.HealthBar", "TargetFrame.totFrame.HealthBar", "TargetFrameToTHealthBar" } },
    { unit = "pet", paths = { "PetFrame.HealthBar", "PetFrameHealthBar" } },
}
local MANA_BARS = {
    { unit = "player", paths = {
        "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar",
        "PlayerFrameManaBar" } },
    { unit = "target", paths = {
        "TargetFrame.TargetFrameContent.TargetFrameContentMain.ManaBar",
        "TargetFrame.TargetFrameContent.TargetFrameContentMain.ManaBarArea.ManaBar",
        "TargetFrameManaBar" } },
    { unit = "focus", paths = {
        "FocusFrame.TargetFrameContent.TargetFrameContentMain.ManaBar",
        "FocusFrame.TargetFrameContent.TargetFrameContentMain.ManaBarArea.ManaBar",
        "FocusFrameManaBar" } },
    { unit = "pet", paths = { "PetFrame.ManaBar", "PetFrameManaBar" } },
}

local function HealthPathsFor(unit)
    for _, e in ipairs(HEALTH_BARS) do if e.unit == unit then return e.paths end end
end

local function NameBarOff(strip)
    local bar = nameBars[strip]
    if bar then bar:Hide() end
    pcall(strip.SetAlpha, strip, 1)
end

local function NameBarOn(strip, health)
    local bar = nameBars[strip]
    if not bar then
        local parent = strip:GetParent()
        local okL, layer, sub = pcall(strip.GetDrawLayer, strip)
        bar = parent:CreateTexture(nil, okL and layer or "BACKGROUND", nil, okL and sub or 0)
        bar:SetTexture(SOLID)
        nameBars[strip] = bar
    end
    -- same height and vertical place as the game's strip, same width as the health bar
    local h = strip:GetHeight()
    if not h or NS.IsSecret(h) or h <= 0 then h = 18 end
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 0, 0)
    bar:SetHeight(h)
    local okC, r, g, b = pcall(strip.GetVertexColor, strip)
    if okC and r and not NS.IsSecret(r) and not NS.IsSecret(g) and not NS.IsSecret(b) then
        bar:SetVertexColor(r, g, b, 1)
    end
    local okS, shown = pcall(strip.IsShown, strip)
    bar:SetShown(not okS or NS.IsSecret(shown) or shown and true or false)
    pcall(strip.SetAlpha, strip, 0)
end

local function ApplyNameBars()
    local s = S()
    local on = s.enabled and s.solidNames
    for _, e in ipairs(NAME_BG_PATHS) do
        local strip = NS.Resolve(e.strip)
        if strip and strip.SetAlpha then
            local health = on and NS.ResolveFirst(HealthPathsFor(e.unit) or {})
            if on and health then NameBarOn(strip, health) else NameBarOff(strip) end
        end
    end
end

local barInfo = {}      -- statusbar -> { unit, kind }   (local table: nothing written to Blizzard frames)
local barHooked = {}

-- Lorti's colour(): class color, tap-denied gray, or reaction green / yellow / red.
local function HealthColor(unit)
    local s = S()
    if not UnitExists(unit) then return end
    if s.classBars and UnitIsPlayer(unit) then
        local r, g, b = ClassColor(unit)
        if r then return r, g, b end
    end
    if UnitIsTapDenied and not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) then
        return 0.5, 0.5, 0.5
    end
    if s.reactionBars then
        local r, g = UnitSelectionColor(unit)
        if r == nil or g == nil or NS.IsSecret(r) or NS.IsSecret(g) then return end
        if r == 0 then return 0, 1, 0 end
        if g == 0 then return 1, 0, 0 end
        return 1, 1, 0
    end
end

local function ManaColor(unit)
    local _, token = UnitPowerType(unit)
    local info = token and PowerBarColor and PowerBarColor[token]
    if info then return info.r, info.g, info.b end
end

local function Recolor(bar, info)
    local s = S()
    if not s.enabled then return end
    if info.kind == "health" then
        if s.customHealth then
            local c = s.healthColor
            bar:SetStatusBarColor(c[1], c[2], c[3])
        elseif s.classBars or s.reactionBars then
            local r, g, b = HealthColor(info.unit)
            if r then bar:SetStatusBarColor(r, g, b) end
        end
    elseif s.customMana then
        local c = s.manaColor
        bar:SetStatusBarColor(c[1], c[2], c[3])
    elseif s.flatBars then
        local r, g, b = ManaColor(info.unit)
        if r then bar:SetStatusBarColor(r, g, b) end
    end
end

local function SetFlat(bar, on)
    if not on then return end
    bar:SetStatusBarTexture(TEX.flat)
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local mask = bar.Mask or bar.HealthBarMask or bar.ManaBarMask
    if tex and mask and tex.AddMaskTexture then pcall(tex.AddMaskTexture, tex, mask) end
end

local function ApplyBarList(list, kind)
    local s = S()
    for _, entry in ipairs(list) do
        local bar = NS.ResolveFirst(entry.paths)
        if bar and bar.SetStatusBarColor then
            barInfo[bar] = { unit = entry.unit, kind = kind }
            if not barHooked[bar] and bar.HookScript then
                barHooked[bar] = true
                -- value arguments may be secret values; the handler ignores them.
                pcall(bar.HookScript, bar, "OnValueChanged", function()
                    local info = barInfo[bar]
                    if info then pcall(Recolor, bar, info) end
                end)
            end
            if s.enabled and s.flatBars then SetFlat(bar, true) end
            Recolor(bar, barInfo[bar])
        end
    end
end

local function ApplyBars()
    ApplyBarList(HEALTH_BARS, "health")
    ApplyBarList(MANA_BARS, "mana")
    -- NEVER call Blizzard's own UnitFrameHealthBar_Update (or any other Blizzard Lua function)
    -- from here to "repaint" the bars. Code that runs from an addon is tainted, and a tainted
    -- call leaves the health bar's stored values tainted for good: every later health update
    -- then fails with "attempt to compare a secret number value (execution tainted by ...)".
    -- When the color options are turned off, Blizzard's colors come back on the next /reload.
end

----------------------------------------------------------------------
-- Class portraits (target / focus, like Lorti: player and pet keep their own)
----------------------------------------------------------------------
local PORTRAITS = {
    { unit = "target", paths = { "TargetFrame.TargetFrameContainer.Portrait", "TargetFramePortrait" } },
    { unit = "focus",  paths = { "FocusFrame.TargetFrameContainer.Portrait",  "FocusFramePortrait" } },
}

local function ClassPortrait(tex, unit)
    if not (tex and tex.SetTexture and UnitExists(unit) and UnitIsPlayer(unit)) then return end
    local _, class = UnitClass(unit)
    if class and CLASS_FILES[class] then
        tex:SetTexture(TEX.classes .. class)
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function ApplyPortraits()
    local s = S()
    for _, entry in ipairs(PORTRAITS) do
        local tex = NS.ResolveFirst(entry.paths)
        if tex then
            if s.enabled and s.classPortraits then
                ClassPortrait(tex, entry.unit)
            elseif SetPortraitTexture and UnitExists(entry.unit) then
                pcall(SetPortraitTexture, tex, entry.unit)
            end
        end
    end
end

----------------------------------------------------------------------
-- Player hit indicator (the floating damage numbers on the portrait)
----------------------------------------------------------------------
local HIT_FRAMES = {
    "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator",
    "PlayerHitIndicator", "PetHitIndicator",
}
local hitHooked = {}

local function ApplyHit()
    local s = S()
    for _, path in ipairs(HIT_FRAMES) do
        local f = NS.Resolve(path)
        if f and f.Hide and f.Show then
            if not hitHooked[f] then
                hitHooked[f] = true
                pcall(hooksecurefunc, f, "Show", function(self)
                    local ss = S()
                    if ss.enabled and ss.hideHit then self:Hide() end
                end)
            end
            if s.enabled and s.hideHit then f:Hide() end
        end
    end
end

----------------------------------------------------------------------
-- Buffs / debuffs
----------------------------------------------------------------------
local auraStyled = {}

local function SkinAura(btn, isDebuff)
    if not btn or not btn.CreateTexture then return end
    local s = S()
    local st = auraStyled[btn]
    if not st then
        if not (s.enabled and s.auras) then return end
        if InCombatLockdown() then needsCombatPass = true; return end
        st = {}
        auraStyled[btn] = st
        if not isDebuff then
            st.border = btn:CreateTexture(nil, "ARTWORK", nil, 3)
            st.border:SetAllPoints(btn)
            st.border:SetTexture(TEX.gloss)
            st.border:SetVertexColor(0.4, 0.35, 0.35)
        end
        st.shadow = MakeShadow(btn)
    end
    local on = s.enabled and s.auras
    if st.border then st.border:SetShown(on and true or false) end
    if st.shadow then st.shadow:SetShown(on and s.shadow and true or false) end
    local icon = btn.Icon or btn.icon
    if icon and icon.SetTexCoord then
        if on then icon:SetTexCoord(0.1, 0.9, 0.1, 0.9) else icon:SetTexCoord(0, 1, 0, 1) end
    end
end

local function SkinFrameAuras(frame, isDebuff)
    local list = frame and frame.auraFrames
    if type(list) == "table" then
        for _, btn in ipairs(list) do SkinAura(btn, isDebuff) end
    end
end

local function SkinUnitAuras(unitFrame)
    local pools = unitFrame and unitFrame.auraPools
    if pools and pools.EnumerateActive then
        for obj in pools:EnumerateActive() do
            if type(obj) == "table" and obj.CreateTexture then
                local isDebuff = (obj.DebuffBorder ~= nil) or (obj.Border ~= nil and obj.Symbol ~= nil)
                SkinAura(obj, isDebuff)
            end
        end
    end
end

local function ApplyAuras()
    SkinFrameAuras(BuffFrame, false)
    SkinFrameAuras(DebuffFrame, true)
    SkinUnitAuras(TargetFrame)
    SkinUnitAuras(FocusFrame)
end

----------------------------------------------------------------------
-- Windows (Lorti darkens the Blizzard windows too)
----------------------------------------------------------------------
local WINDOWS = {
    "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "TalentFrame", "QuestFrame",
    "GossipFrame", "MerchantFrame", "MailFrame", "FriendsFrame", "CommunitiesFrame",
    "PVEFrame", "WorldMapFrame", "CollectionsJournal", "AchievementFrame", "GameMenuFrame",
    "ChatConfigFrame", "HelpFrame", "TradeFrame", "TaxiFrame", "BankFrame", "LootFrame",
    "ProfessionsFrame", "InspectFrame", "MacroFrame", "AddonList", "TabardFrame",
    "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6", "ClassTrainerFrame",
    "TradeSkillFrame", "CraftFrame", "ItemTextFrame", "StackSplitFrame", "DressUpFrame",
}

local function ShadeRegions(owner, v)
    if not (owner and owner.GetRegions) then return end
    for _, region in ipairs({ owner:GetRegions() }) do
        if region and region.SetVertexColor and region.IsObjectType and region:IsObjectType("Texture") then
            region:SetVertexColor(v, v, v)
        end
    end
end

local function ApplyWindows()
    local s = S()
    local v = (s.enabled and s.darkWindows) and s.artShade or 1
    for _, name in ipairs(WINDOWS) do
        local f = _G[name]
        if f then
            if f.NineSlice then ShadeRegions(f.NineSlice, v) end
            if f.TopTileStreaks and f.TopTileStreaks.SetVertexColor then f.TopTileStreaks:SetVertexColor(v, v, v) end
            if f.Border then ShadeRegions(f.Border, v) end
        end
    end
end

----------------------------------------------------------------------
-- Minimap
----------------------------------------------------------------------
local wheelInstalled = false

local function ApplyMinimap()
    local s = S()
    if not Minimap then return end
    if s.enabled and s.minimapZoom and not wheelInstalled
        and not (Minimap.IsMouseWheelEnabled and Minimap:IsMouseWheelEnabled()) then
        wheelInstalled = true
        Minimap:EnableMouseWheel(true)
        Minimap:SetScript("OnMouseWheel", function(mp, delta)
            local zoom = mp:GetZoom()
            local levels = (mp.GetZoomLevels and mp:GetZoomLevels()) or 5
            if delta > 0 and zoom < levels - 1 then mp:SetZoom(zoom + 1)
            elseif delta < 0 and zoom > 0 then mp:SetZoom(zoom - 1) end
        end)
    end
    local hide = s.enabled and s.hideZoomBtns
    for _, key in ipairs({ "ZoomIn", "ZoomOut" }) do
        local b = Minimap[key]
        if b and b.SetAlpha then b:SetAlpha(hide and 0 or 1) end
    end
end

----------------------------------------------------------------------
-- Error text ("Ability is not ready yet" and friends)
----------------------------------------------------------------------
local ERROR_BLOCKS = {
    "Ability is not ready yet", "Another action is in progress", "Can't attack while mounted",
    "Can't do that while moving", "Item is not ready yet", "Not enough", "Nothing to attack",
    "Spell is not ready yet", "You have no target", "You can't do that yet",
}
for _, g in ipairs({ "ERR_ABILITY_COOLDOWN", "ERR_SPELL_COOLDOWN", "ERR_ITEM_COOLDOWN",
    "SPELL_FAILED_SPELL_IN_PROGRESS", "SPELL_FAILED_MOVING", "ERR_NO_ATTACK_TARGET",
    "ERR_GENERIC_NO_TARGET", "SPELL_FAILED_NOT_READY" }) do
    local v = _G[g]
    if type(v) == "string" and v ~= "" then ERROR_BLOCKS[#ERROR_BLOCKS + 1] = (v:gsub("%.$", "")) end
end

-- IMPORTANT: this must stay a hooksecurefunc post-hook. Replacing UIErrorsFrame.AddMessage
-- with our own function (what this module did before) makes Blizzard's secure code run
-- OUR function whenever a spell fails, which taints everything that runs after it in that
-- call chain - cast bars, other addons' secret-value math, etc.
-- The post-hook lets Blizzard add the message, then clears it again in the same Lua
-- execution (before the frame is drawn), so the text never appears.
local errorsHooked = false
local function ApplyErrors()
    local s = S()
    if errorsHooked or not (s.enabled and s.hideErrors) then return end
    if not (UIErrorsFrame and type(UIErrorsFrame.AddMessage) == "function") then return end
    errorsHooked = true
    pcall(hooksecurefunc, UIErrorsFrame, "AddMessage", function(frame, text)
        local cfg = NS.db and S()
        if not (cfg and cfg.enabled and cfg.hideErrors) then return end
        if type(text) ~= "string" or NS.IsSecret(text) then return end
        for _, pattern in ipairs(ERROR_BLOCKS) do
            if text:find(pattern, 1, true) then
                if frame.Clear then frame:Clear() end
                return
            end
        end
    end)
end

----------------------------------------------------------------------
-- Apply / init
----------------------------------------------------------------------
local STEPS = {
    { "action buttons",  ApplyButtons },
    { "bar art",         ApplyBarArt },
    { "frame art",       ApplyFrameArt },
    { "name bars",       ApplyNameBars },
    { "unit bars",       ApplyBars },
    { "portraits",       ApplyPortraits },
    { "hit indicator",   ApplyHit },
    { "buffs",           ApplyAuras },
    { "windows",         ApplyWindows },
    { "minimap",         ApplyMinimap },
    { "error text",      ApplyErrors },
}

function M:Apply()
    for _, step in ipairs(STEPS) do
        local ok, err = pcall(step[2])
        if not ok then NS.ReportError("Lorti Style: " .. step[1], err) end
    end
end

local pending = false
local function ApplySoon()
    if pending then return end
    pending = true
    C_Timer.After(0, function() pending = false; M:Apply() end)
end

function M:Init()
    -- Blizzard recolors / repaints these itself; run right after it.
    if type(_G.UnitFrameHealthBar_Update) == "function" then
        hooksecurefunc("UnitFrameHealthBar_Update", function(bar)
            local info = barInfo[bar]
            if info then pcall(Recolor, bar, info) end
        end)
    end
    if type(_G.UnitFrameManaBar_UpdateType) == "function" then
        hooksecurefunc("UnitFrameManaBar_UpdateType", function(bar)
            local info = barInfo[bar]
            if info and S().enabled and S().flatBars then pcall(SetFlat, bar, true); pcall(Recolor, bar, info) end
        end)
    end
    if type(_G.UnitFramePortrait_Update) == "function" then
        hooksecurefunc("UnitFramePortrait_Update", function(frame)
            local s = S()
            if not (s.enabled and s.classPortraits) then return end
            local unit = frame and frame.unit
            if unit == "player" or unit == "pet" then return end
            if frame.portrait and unit then pcall(ClassPortrait, frame.portrait, unit) end
        end)
    end

    NS.On("PLAYER_ENTERING_WORLD", function()
        ApplySoon()
        C_Timer.After(1.5, function() M:Apply() end)
    end)
    for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_FACTION",
        "UPDATE_SHAPESHIFT_FORMS", "PET_BAR_UPDATE", "ACTIONBAR_PAGE_CHANGED", "GROUP_ROSTER_UPDATE" }) do
        NS.On(ev, ApplySoon)
    end
    NS.On("UNIT_AURA", function(_, unit)
        if unit == "player" or unit == "target" or unit == "focus" then ApplySoon() end
    end)
    NS.On("ADDON_LOADED", function() ApplySoon() end)       -- load-on-demand windows
    NS.On("PLAYER_REGEN_ENABLED", function()
        if needsCombatPass then needsCombatPass = false; ApplySoon() end
    end)
end

----------------------------------------------------------------------
-- Diagnostics
----------------------------------------------------------------------
function M:Diagnose()
    local n = 0
    for _ in pairs(styled) do n = n + 1 end
    NS.Print("  action buttons styled: " .. n)
    local function Found(label, paths)
        local _, p = NS.ResolveFirst(paths)
        NS.Print("  " .. label .. ": " .. (p and ("|cff00ff00" .. p .. "|r") or "|cffff4444not found|r"))
    end
    for _, e in ipairs(HEALTH_BARS) do Found(e.unit .. " health bar", e.paths) end
    for _, e in ipairs(MANA_BARS) do Found(e.unit .. " mana bar", e.paths) end
    for _, e in ipairs(PORTRAITS) do Found(e.unit .. " portrait", e.paths) end
    for _, p in ipairs(FRAME_ART) do
        if NS.Resolve(p) then NS.Print("  frame art: |cff00ff00" .. p .. "|r") end
    end
    for _, e in ipairs(NAME_BG_PATHS) do
        local p = e.strip
        NS.Print("  name bar: " .. (NS.Resolve(p) and ("|cff00ff00" .. p .. "|r") or ("|cffff4444not found|r " .. p)))
    end
    local b = _G["ActionButton1"]
    if b then
        NS.Print(string.format("  ActionButton1 parts: icon=%s NormalTexture=%s HotKey=%s Name=%s Count=%s Flash=%s IconMask=%s",
            tostring(b.icon ~= nil), tostring(b.NormalTexture ~= nil), tostring(b.HotKey ~= nil),
            tostring(b.Name ~= nil), tostring(b.Count ~= nil), tostring(b.Flash ~= nil), tostring(b.IconMask ~= nil)))
    else
        NS.Print("  ActionButton1: |cffff4444not found|r")
    end
    NS.Print("  BuffFrame.auraFrames: " .. tostring(BuffFrame and type(BuffFrame.auraFrames) == "table"))
    NS.Print("  TargetFrame.auraPools: " .. tostring(TargetFrame and TargetFrame.auraPools ~= nil))
end

----------------------------------------------------------------------
-- Settings page
----------------------------------------------------------------------
function M.Build(page)
    local function Bind(key)
        return function() return S()[key] end,
               function(v) S()[key] = v; NS.ApplyModule("lorti") end
    end
    local function Pct(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
    local function Px(v) return string.format("%d px", math.floor(v + 0.5)) end
    local function ColorRow(label, key)
        page:Color(label,
            function() return S()[key] end,
            function(r, g, b, a) local c = S()[key]; c[1], c[2], c[3], c[4] = r, g, b, a or 1; NS.ApplyModule("lorti") end)
    end
    local function Size(label, key)
        page:Slider(label, 8, 18, 1,
            function() return S()[key] end,
            function(v) S()[key] = v; NS.ApplyModule("lorti") end)
    end

    page:Section("Button style", "Gloss, shadow, square icons and the bar background")
    page:Check("Lorti button style (gloss border, shadow, square icons)", Bind("buttons"))
    page:Check("High gloss border", Bind("gloss"))
    page:Check("Outer shadow", Bind("shadow"))
    page:Check("Dark slot background", Bind("slotBack"))
    page:Check("Crop icons to a square", Bind("iconCrop"))
    page:Check("Hide action bar background and end caps", Bind("hideBarArt"))

    page:Section("Button edge and border", "The solid edge and the color of the border around each button")
    page:Check("Solid edge around every button (hides white corner pixels)", Bind("edge"))
    page:Slider("Edge thickness", 1, 5, 1,
        function() return S().edgeSize end,
        function(v) S().edgeSize = v; NS.ApplyModule("lorti") end, Px)
    page:Color("Edge color",
        function() return S().edgeColor end,
        function(r, g, b, a) local c = S().edgeColor; c[1], c[2], c[3] = r, g, b; c[4] = 1; NS.ApplyModule("lorti") end)
    page:Check("Color the border with my class color (High gloss only)", Bind("classBorder"))
    ColorRow("Border tint (High gloss only)", "borderTint")

    page:Section("Text on buttons", "Keybind, macro name and count text: size, visibility and color")
    page:Check("Hide keybind text", Bind("hideHotkeys"))
    page:Check("Hide macro names", Bind("hideMacro"))
    Size("Keybind text size", "hotkeyFont")
    Size("Macro name size", "macroFont")
    Size("Item count size", "countFont")
    page:Check("Use my own colors for macro names and counts", Bind("customText"))
    ColorRow("Macro name color", "macroColor")
    ColorRow("Item count color", "countColor")
    page:Note("Keybind text keeps Blizzard's own colors, because the game turns it red when you are out of range.")

    page:Section("Frame art and portraits", "Darkened unit frames, class portraits and the player hit numbers")
    page:Check("Darken unit frame art", Bind("darkFrames"))
    page:Slider("Unit frame border brightness", 0, 1, 0.05,
        function() return S().frameShade end,
        function(v) S().frameShade = v; NS.ApplyModule("lorti") end, Pct)
    page:Slider("Other UI art brightness", 0, 1, 0.05,
        function() return S().artShade end,
        function(v) S().artShade = v; NS.ApplyModule("lorti") end, Pct)
    page:Check("Solid name background (no fade)", Bind("solidNames"))
    page:Check("Class portraits on target and focus", Bind("classPortraits"))
    page:Check("Hide hit numbers on the player portrait", Bind("hideHit"))

    page:Section("Health and mana bars", "Bar texture and bar colors: class, hostility or your own")
    page:Check("Flat health and mana bar texture", Bind("flatBars"))
    page:Check("Class colored health bars", Bind("classBars"))
    page:Check("Color health by hostility (green / yellow / red)", Bind("reactionBars"))
    page:Check("Use one color of my own for all health bars", Bind("customHealth"))
    ColorRow("Health bar color", "healthColor")
    page:Check("Use one color of my own for all mana / power bars", Bind("customMana"))
    ColorRow("Mana / power bar color", "manaColor")
    page:Note("A color of your own wins over class and hostility colors. Turning these off again fully "
        .. "restores Blizzard's colors after a /reload.")

    page:Section("Buffs and debuffs", "Borders around buff and debuff icons")
    page:Check("Lorti style borders on buffs and debuffs", Bind("auras"))

    page:Section("Windows and minimap", "Dark Blizzard windows, minimap and error text")
    page:Check("Darken Blizzard windows", Bind("darkWindows"))
    page:Check("Mouse wheel zooms the minimap", Bind("minimapZoom"))
    page:Check("Hide minimap zoom buttons", Bind("hideZoomBtns"))
    page:Check("Hide 'Ability is not ready yet' style error text", Bind("hideErrors"))
    page:Note("Some changes can't be undone live because Blizzard has no way to restore its original art "
        .. "(flat bars, button textures). Type /reload after turning those off.")
    page:Note("Lorti's 'Thick Frames' option is not included: it swaps in Classic Era frame textures "
        .. "that don't fit the Retail-style frames Forever uses. Everything else from LortiUI is here.")
end
