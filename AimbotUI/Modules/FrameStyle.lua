--[[
  Aimbot UI - Frame Style (2.32.0)
  Restyles the game's own player, target and target-of-target frames into a compact look:
  the name above a big health bar with the health number in the middle, a thin power bar
  under it, both with a black border, and a round portrait beside them (class icon for
  players, red ring while that unit is in combat). The frame art and the name strip are
  hidden.

  Restyle only: the game's frames stay the game's frames (right-click menus, focus, Edit Mode,
  clicking to target all keep working). Everything here is method calls on the game's frames
  and post-hooks (hooksecurefunc / HookScript); no field is ever written on a game frame, and
  every extra texture lives in this file's own tables.

  The game moves its bars and portraits back when it redraws a frame (vehicle, classification,
  art changes), so the layout is put back from post-hooks on those, and on target changes.

  Values the client hides (other players' health can be a secret value) are never compared or
  used in arithmetic: secret health is handed straight to SetText, or the text is left empty.
  Bar masks removed while the style is on come back on the next /reload when it is turned off.
]]

local ADDON_NAME, NS = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"

local M = {
    name = "Frame Style",
    group = "Style",
    desc = "Restyles the game's player, target and target-of-target frames: name above a big health bar "
        .. "with the number, a thin power bar, black borders and a round portrait.",
    defaults = {
        enabled      = true,
        player       = true,
        target       = true,
        tot          = true,
        classHealth  = true,      -- players' health bars in class colour (NPCs: reaction colour)
        classIcons   = true,      -- players' portraits as class icons
        combatRing   = true,      -- portrait ring turns red while that unit is in combat
        healthText   = "value",   -- "value", "percent", "both" or "none"
        powerText    = true,
        showLevel    = false,
        border       = 2,         -- black border thickness in pixels
        healthWidth  = 130,
        healthHeight = 24,
        powerHeight  = 8,
        portraitSize = 54,
        fontSize     = 16,
    },
}
NS.RegisterModule("framestyle", M)

-- Lets the Lorti module step aside on the frames restyled here (unit: "player", "target",
-- "targettarget" ...).
local UNIT_KEY = { player = "player", target = "target", targettarget = "tot" }
function NS.FrameStyleOwns(unit)
    local s = NS.db and NS.db.mod and NS.db.mod.framestyle
    local key = UNIT_KEY[unit]
    return (s and s.enabled and key and s[key]) and true or false
end

local function S() return NS.db.mod.framestyle end
local IsSecret = NS.IsSecret
local function On() local s = S(); return s and s.enabled end
M._t_On = On

M.stats = { found = {}, layouts = 0, secretText = 0, errors = 0, lastError = nil }

local function Clean(v)
    if v == nil or IsSecret(v) then return nil end
    return v
end

local CLASS_FILES = {
    DEATHKNIGHT = true, DRUID = true, HUNTER = true, MAGE = true, PALADIN = true,
    PRIEST = true, ROGUE = true, SHAMAN = true, WARLOCK = true, WARRIOR = true,
}

----------------------------------------------------------------------
-- Where the parts of each frame live (modern names first, classic names as fallback)
----------------------------------------------------------------------
local UNITS = {
    player = {
        unit = "player", key = "player", small = false,
        frame    = { "PlayerFrame" },
        health   = { "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar",
                     "PlayerFrameHealthBar" },
        power    = { "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar",
                     "PlayerFrameManaBar" },
        portrait = { "PlayerFrame.PlayerFrameContainer.PlayerPortrait", "PlayerPortrait" },
        name     = { "PlayerName", "PlayerFrame.name" },
        level    = { "PlayerLevelText", "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.LevelText" },
        art      = { "PlayerFrame.PlayerFrameContainer.FrameTexture", "PlayerFrameTexture",
                     "PlayerFrame.PlayerFrameContainer.FrameFlash", "PlayerFrameFlash",
                     "PlayerFrame.PlayerFrameContainer.PlayerPortraitMask",
                     "PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon",
                     "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ReputationColor",
                     "PlayerFrameBackground" },
    },
    target = {
        unit = "target", key = "target", small = false,
        frame    = { "TargetFrame" },
        health   = { "TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar",
                     "TargetFrameHealthBar" },
        power    = { "TargetFrame.TargetFrameContent.TargetFrameContentMain.ManaBar",
                     "TargetFrame.TargetFrameContent.TargetFrameContentMain.ManaBarArea.ManaBar",
                     "TargetFrameManaBar" },
        portrait = { "TargetFrame.TargetFrameContainer.Portrait", "TargetFramePortrait" },
        name     = { "TargetFrame.TargetFrameContent.TargetFrameContentMain.Name", "TargetFrame.name",
                     "TargetFrameTextureFrameName" },
        level    = { "TargetFrame.TargetFrameContent.TargetFrameContentMain.LevelText",
                     "TargetFrameTextureFrameLevelText" },
        art      = { "TargetFrame.TargetFrameContainer.FrameTexture", "TargetFrameTextureFrameTexture",
                     "TargetFrame.TargetFrameContainer.Flash", "TargetFrameFlash",
                     "TargetFrame.TargetFrameContainer.PortraitMask",
                     "TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor",
                     "TargetFrameNameBackground", "TargetFrameBackground" },
    },
    tot = {
        unit = "targettarget", key = "tot", small = true,
        frame    = { "TargetFrameToT", "TargetFrame.totFrame" },
        health   = { "TargetFrameToT.HealthBar", "TargetFrame.totFrame.HealthBar", "TargetFrameToTHealthBar" },
        power    = { "TargetFrameToT.ManaBar", "TargetFrame.totFrame.ManaBar", "TargetFrameToTManaBar" },
        portrait = { "TargetFrameToT.Portrait", "TargetFrame.totFrame.Portrait", "TargetFrameToTPortrait" },
        name     = { "TargetFrameToT.Name", "TargetFrame.totFrame.Name", "TargetFrameToTTextureFrameName" },
        level    = {},
        art      = { "TargetFrameToT.FrameTexture", "TargetFrame.totFrame.FrameTexture",
                     "TargetFrameToTTextureFrameTexture", "TargetFrameToTBackground" },
    },
}
M._t_UNITS = UNITS

-- Bar texts the game draws itself; hidden while the style shows its own.
local BAR_TEXTS = { "TextString", "LeftText", "RightText" }

----------------------------------------------------------------------
-- Our own pieces (kept in local tables, keyed by the game's object)
----------------------------------------------------------------------
local parts = {}            -- key -> { frame, health, power, portrait, name, level, ... our textures }
local deco = {}             -- game statusbar -> { bg, edges, text, kind, unit }
local ringOf = {}           -- game portrait texture -> { ring, mask }
local hookedBar, hookedPortraitFn, hookedLayoutFns = {}, false, false

local function SetAlphaSafe(obj, a) if obj and obj.SetAlpha then pcall(obj.SetAlpha, obj, a) end end

local function Find(key)
    local d = UNITS[key]
    local p = parts[key] or {}
    parts[key] = p
    p.frame = NS.ResolveFirst(d.frame)
    p.health = NS.ResolveFirst(d.health)
    p.power = NS.ResolveFirst(d.power)
    p.portrait = NS.ResolveFirst(d.portrait)
    p.name = NS.ResolveFirst(d.name)
    p.level = NS.ResolveFirst(d.level)
    M.stats.found[key] = string.format("frame %s, health %s, power %s, portrait %s, name %s",
        tostring(p.frame ~= nil), tostring(p.health ~= nil), tostring(p.power ~= nil),
        tostring(p.portrait ~= nil), tostring(p.name ~= nil))
    return p
end
M._t_Find = Find

----------------------------------------------------------------------
-- Colours and text
----------------------------------------------------------------------
local function ClassColor(unit)
    local okC, _, class = pcall(UnitClass, unit)
    class = okC and Clean(class) or nil
    if not class then return nil end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
end

local function HealthColor(unit)
    if not UnitExists or not UnitExists(unit) then return nil end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    isPlayer = okP and Clean(isPlayer)
    if isPlayer and S().classHealth then
        local r, g, b = ClassColor(unit)
        if r then return r, g, b end
    end
    if UnitIsTapDenied then
        local okT, denied = pcall(UnitIsTapDenied, unit)
        local okC, controlled = pcall(UnitPlayerControlled, unit)
        if okT and Clean(denied) and not (okC and Clean(controlled)) then return 0.5, 0.5, 0.5 end
    end
    if UnitSelectionColor then
        local okS, r, g = pcall(UnitSelectionColor, unit)
        r, g = okS and Clean(r), okS and Clean(g)
        if type(r) == "number" and type(g) == "number" then
            if r == 0 then return 0, 1, 0 end
            if g == 0 then return 1, 0, 0 end
            return 1, 1, 0
        end
    end
    return nil
end
M._t_HealthColor = HealthColor

-- Text for a value / max pair. Secret values: the raw value goes to SetText (allowed), no maths.
local function FormatNumber(v)
    if v >= 1e7 then return string.format("%.1fm", v / 1e6) end
    return tostring(math.floor(v + 0.5))
end

local function HealthString(unit, mode)
    if mode == "none" then return "" end
    local okH, cur = pcall(UnitHealth, unit)
    local okM, max = pcall(UnitHealthMax, unit)
    if not okH then return "" end
    if IsSecret(cur) or (okM and IsSecret(max)) then
        M.stats.secretText = M.stats.secretText + 1
        if mode == "percent" then return "" end
        return cur, true        -- the caller hands the secret value straight to SetText
    end
    if type(cur) ~= "number" then return "" end
    local pct = (okM and type(max) == "number" and max > 0) and math.floor(cur / max * 100 + 0.5) or nil
    if UnitIsDeadOrGhost then
        local okD, dead = pcall(UnitIsDeadOrGhost, unit)
        if okD and Clean(dead) then return DEAD or "Dead" end
    end
    if mode == "percent" then return pct and (pct .. "%") or FormatNumber(cur) end
    if mode == "both" and pct then return FormatNumber(cur) .. "  " .. pct .. "%" end
    return FormatNumber(cur)
end
M._t_HealthString = HealthString

local function PowerString(unit)
    local okP, cur = pcall(UnitPower, unit)
    if not okP then return "" end
    if IsSecret(cur) then return cur, true end
    local okM, max = pcall(UnitPowerMax, unit)
    if okM and type(max) == "number" and not IsSecret(max) and max == 0 then return "" end
    if type(cur) ~= "number" then return "" end
    return FormatNumber(cur)
end
M._t_PowerString = PowerString

local function SetTextSafe(fs, text, secret)
    if secret then
        if not pcall(fs.SetText, fs, text) then fs:SetText("") end
    else
        fs:SetText(text or "")
    end
end

----------------------------------------------------------------------
-- Bar decoration: black background, black border, our own text
----------------------------------------------------------------------
local function RemoveMasks(tex)
    if not (tex and tex.GetNumMaskTextures and tex.GetMaskTexture and tex.RemoveMaskTexture) then return end
    local okN, n = pcall(tex.GetNumMaskTextures, tex)
    if not okN or type(n) ~= "number" or IsSecret(n) then return end
    for i = n, 1, -1 do
        local okG, mask = pcall(tex.GetMaskTexture, tex, i)
        if okG and mask then pcall(tex.RemoveMaskTexture, tex, mask) end
    end
end
M._t_RemoveMasks = RemoveMasks

local function Decorate(bar, kind, unit, small)
    local d = deco[bar]
    if not d then
        d = { kind = kind, unit = unit, edges = {} }
        deco[bar] = d
        local okB, bg = pcall(bar.CreateTexture, bar, nil, "BACKGROUND", nil, -7)
        if okB and bg then
            d.bg = bg
            bg:SetAllPoints(bar)
            bg:SetColorTexture(0, 0, 0, 0.75)
        end
        local holder = CreateFrame("Frame", nil, bar)
        holder:SetAllPoints(bar)
        holder:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 1) + 4)
        d.holder = holder
        for i = 1, 4 do
            local e = holder:CreateTexture(nil, "OVERLAY", nil, 7)
            e:SetColorTexture(0, 0, 0, 1)
            d.edges[i] = e
        end
        d.text = holder:CreateFontString(nil, "OVERLAY")
        d.text:SetPoint("CENTER", holder, "CENTER", 0, 0)
        d.text:SetTextColor(1, 1, 1)
    end
    d.kind, d.unit, d.small = kind, unit, small
    return d
end

local function LayoutDeco(d, s)
    local b = math.max(0, math.floor(s.border or 2))
    local e = d.edges
    local h = d.holder
    for i = 1, 4 do e[i]:ClearAllPoints(); e[i]:SetShown(b > 0) end
    if b > 0 then
        e[1]:SetPoint("TOPLEFT", h, "TOPLEFT", -b, b); e[1]:SetPoint("TOPRIGHT", h, "TOPRIGHT", b, b); e[1]:SetHeight(b)
        e[2]:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", -b, -b); e[2]:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", b, -b); e[2]:SetHeight(b)
        e[3]:SetPoint("TOPLEFT", h, "TOPLEFT", -b, 0); e[3]:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", -b, 0); e[3]:SetWidth(b)
        e[4]:SetPoint("TOPRIGHT", h, "TOPRIGHT", b, 0); e[4]:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", b, 0); e[4]:SetWidth(b)
    end
    local size
    if d.kind == "health" then size = d.small and 9 or (s.fontSize or 16)
    else size = d.small and 7 or math.max(8, math.floor((s.fontSize or 16) * 0.6)) end
    pcall(d.text.SetFont, d.text, STANDARD_TEXT_FONT, size, "OUTLINE")
end

local function ShowDeco(d, on)
    if d.holder then d.holder:SetShown(on) end
    if d.bg then d.bg:SetShown(on) end
end

local function UpdateText(bar)
    local d = deco[bar]
    if not d or not On() then return end
    local s = S()
    if d.kind == "health" then
        if d.small then d.text:SetText(""); return end
        local t, secret = HealthString(d.unit, s.healthText)
        SetTextSafe(d.text, t, secret)
    else
        if d.small or not s.powerText then d.text:SetText(""); return end
        local t, secret = PowerString(d.unit)
        SetTextSafe(d.text, t, secret)
    end
end
M._t_UpdateText = UpdateText

local function Recolor(bar)
    local d = deco[bar]
    if not d or d.kind ~= "health" or not On() then return end
    local r, g, b = HealthColor(d.unit)
    if r then pcall(bar.SetStatusBarColor, bar, r, g, b) end
end

local function HookBar(bar)
    if hookedBar[bar] or not bar.HookScript then return end
    hookedBar[bar] = true
    -- the value argument may be secret; the handler re-reads the unit instead
    pcall(bar.HookScript, bar, "OnValueChanged", function(self)
        local ok, err = pcall(function() Recolor(self); UpdateText(self) end)
        if not ok then M.stats.errors = M.stats.errors + 1; M.stats.lastError = tostring(err) end
    end)
end

----------------------------------------------------------------------
-- Portrait: round, ring, class icon
----------------------------------------------------------------------
local function ClassIcon(tex, unit)
    if not (tex and tex.SetTexture and UnitExists and UnitExists(unit)) then return end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if not (okP and Clean(isPlayer)) then return end
    local okC, _, class = pcall(UnitClass, unit)
    class = okC and Clean(class) or nil
    if class and CLASS_FILES[class] then
        pcall(tex.SetTexture, tex, MEDIA .. "classes\\" .. class)
        pcall(tex.SetTexCoord, tex, 0, 1, 0, 1)
    end
end
M._t_ClassIcon = ClassIcon

local function DecoratePortrait(tex)
    local r = ringOf[tex]
    if r then return r end
    r = {}
    ringOf[tex] = r
    local parent = tex.GetParent and tex:GetParent()
    if parent and parent.CreateTexture then
        -- a black disc a little larger than the portrait, behind it: reads as a ring
        local okR, ring = pcall(parent.CreateTexture, parent, nil, "BACKGROUND", nil, -8)
        if okR and ring then
            ring:SetTexture(MEDIA .. "ui\\circle")
            ring:SetVertexColor(0, 0, 0, 1)
            r.ring = ring
        end
    end
    return r
end

local function RingColor(r, unit)
    if not r.ring then return end
    local red = false
    if S().combatRing and UnitAffectingCombat then
        local okA, inCombat = pcall(UnitAffectingCombat, unit)
        red = okA and Clean(inCombat) and true or false
    end
    if red then r.ring:SetVertexColor(0.8, 0.05, 0.05, 1) else r.ring:SetVertexColor(0, 0, 0, 1) end
end

----------------------------------------------------------------------
-- Layout (offsets from the frame's top-left corner)
----------------------------------------------------------------------
-- Big frames: bars on the left, round portrait on the right, name above the health bar.
-- Small (target of target): portrait on the left, short bars to its right, name under them.
local function Geometry(s, small)
    if small then
        return { hx = 40, hy = -8, hw = 64, hh = 10, ph = 4, px = 4, py = -2, ps = 34, gap = 2 }
    end
    local hw, hh, ph, ps = s.healthWidth, s.healthHeight, s.powerHeight, s.portraitSize
    local hx, hy = 24, -30
    local block = hh + 3 + ph
    return { hx = hx, hy = hy, hw = hw, hh = hh, ph = ph, gap = 3,
             px = hx + hw + 8, py = hy + (ps - block) / 2, ps = ps }
end
M._t_Geometry = Geometry

-- In combat the game blocks addons from moving protected frames. Anything protected is left
-- alone until combat ends (PLAYER_REGEN_ENABLED puts the layout back); the rest moves at once.
local blockedInCombat = false
local function CanMove(obj)
    if not (InCombatLockdown and InCombatLockdown()) then return true end
    if obj and obj.IsProtected then
        local okP, prot = pcall(obj.IsProtected, obj)
        if okP and prot and not IsSecret(prot) then blockedInCombat = true; return false end
    end
    return true
end
M._t_CanMove = CanMove
M._t_Blocked = function() return blockedInCombat end

local function PlaceRegion(obj, point, rel, relPoint, x, y)
    if not obj or not CanMove(obj) then return end
    pcall(obj.ClearAllPoints, obj)
    pcall(obj.SetPoint, obj, point, rel, relPoint, x, y)
end

local function SizeRegion(obj, w, h)
    if not obj or not CanMove(obj) then return end
    pcall(obj.SetSize, obj, w, h)
end

local function ApplyUnit(key)
    local s = S()
    local d = UNITS[key]
    local p = Find(key)
    local want = s.enabled and s[key]
    if not p.frame then return end
    -- art and the name strip
    for _, path in ipairs(d.art) do
        local a = NS.Resolve(path)
        if a then SetAlphaSafe(a, want and 0 or 1) end
    end
    if p.level then SetAlphaSafe(p.level, (want and not s.showLevel) and 0 or 1) end
    -- the game's own bar texts
    for _, bar in ipairs({ p.health, p.power }) do
        for _, k in ipairs(BAR_TEXTS) do
            local t = bar and bar[k]
            if t then SetAlphaSafe(t, want and 0 or 1) end
        end
    end
    if not want then
        for _, bar in ipairs({ p.health, p.power }) do
            if bar and deco[bar] then ShowDeco(deco[bar], false) end
        end
        if p.portrait and ringOf[p.portrait] and ringOf[p.portrait].ring then ringOf[p.portrait].ring:Hide() end
        return
    end
    M.stats.layouts = M.stats.layouts + 1
    local g = Geometry(s, d.small)
    local f = p.frame
    if p.health then
        local hd = Decorate(p.health, "health", d.unit, d.small)
        LayoutDeco(hd, s); ShowDeco(hd, true)
        PlaceRegion(p.health, "TOPLEFT", f, "TOPLEFT", g.hx, g.hy)
        SizeRegion(p.health, g.hw, g.hh)
        RemoveMasks(p.health.GetStatusBarTexture and p.health:GetStatusBarTexture())
        HookBar(p.health)
        Recolor(p.health); UpdateText(p.health)
    end
    if p.power then
        local pd = Decorate(p.power, "power", d.unit, d.small)
        LayoutDeco(pd, s); ShowDeco(pd, true)
        if p.health then
            PlaceRegion(p.power, "TOPLEFT", p.health, "BOTTOMLEFT", 0, -(g.gap + (s.border or 2)))
        else
            PlaceRegion(p.power, "TOPLEFT", f, "TOPLEFT", g.hx, g.hy - g.hh - g.gap)
        end
        SizeRegion(p.power, g.hw, g.ph)
        RemoveMasks(p.power.GetStatusBarTexture and p.power:GetStatusBarTexture())
        HookBar(p.power)
        UpdateText(p.power)
    end
    if p.portrait then
        local r = DecoratePortrait(p.portrait)
        PlaceRegion(p.portrait, "TOPLEFT", f, "TOPLEFT", g.px, g.py)
        SizeRegion(p.portrait, g.ps, g.ps)
        if r.ring then
            r.ring:ClearAllPoints()
            r.ring:SetPoint("CENTER", p.portrait, "CENTER", 0, 0)
            r.ring:SetSize(g.ps + 2 * math.max(2, s.border or 2), g.ps + 2 * math.max(2, s.border or 2))
            r.ring:Show()
            RingColor(r, d.unit)
        end
        if s.classIcons then ClassIcon(p.portrait, d.unit) end
    end
    if p.name and p.health then
        if d.small then
            PlaceRegion(p.name, "TOPLEFT", p.power or p.health, "BOTTOMLEFT", 0, -3)
        else
            PlaceRegion(p.name, "BOTTOM", p.health, "TOP", 0, 3 + (s.border or 2))
        end
        if p.name.SetJustifyH then pcall(p.name.SetJustifyH, p.name, d.small and "LEFT" or "CENTER") end
        pcall(p.name.SetTextColor, p.name, 1, 0.82, 0)
    end
end
M._t_ApplyUnit = ApplyUnit

local function ApplyAll()
    blockedInCombat = false
    for key in pairs(UNITS) do
        local ok, err = pcall(ApplyUnit, key)
        if not ok then M.stats.errors = M.stats.errors + 1; M.stats.lastError = tostring(err) end
    end
end
M._t_ApplyAll = ApplyAll

-- after the game redraws a frame, put the layout back (once per frame tick is plenty)
local queued = false
local function Reapply()
    if not On() or queued then return end
    queued = true
    local function run() queued = false; ApplyAll() end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end
M._t_Reapply = Reapply

local function HookGame()
    if hookedLayoutFns then return end
    hookedLayoutFns = true
    for _, fn in ipairs({ "PlayerFrame_UpdateArt", "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt",
        "TargetFrame_CheckClassification", "TargetFrame_Update", "UnitFrame_Update" }) do
        if type(_G[fn]) == "function" then pcall(hooksecurefunc, fn, Reapply) end
    end
    for _, path in ipairs({ "TargetFrame", "PlayerFrame" }) do
        local f = _G[path]
        if f then
            for _, m in ipairs({ "CheckClassification", "Update", "UpdateArt" }) do
                if type(f[m]) == "function" then pcall(hooksecurefunc, f, m, Reapply) end
            end
        end
    end
    if type(_G.UnitFramePortrait_Update) == "function" and not hookedPortraitFn then
        hookedPortraitFn = true
        hooksecurefunc("UnitFramePortrait_Update", function(frame)
            if not (On() and S().classIcons) then return end
            for key, d in pairs(UNITS) do
                local p = parts[key]
                if p and p.frame == frame and S()[key] and p.portrait then pcall(ClassIcon, p.portrait, d.unit) end
            end
        end)
    end
end

function M:Init()
    NS.On("PLAYER_ENTERING_WORLD", function() HookGame(); Reapply() end)
    NS.On("PLAYER_TARGET_CHANGED", Reapply)
    NS.On("UNIT_TARGET", function(_, unit) if unit == "target" then Reapply() end end)
    NS.On("UNIT_FLAGS", function(_, unit)
        for key, d in pairs(UNITS) do
            local p = parts[key]
            if d.unit == unit and p and p.portrait and ringOf[p.portrait] then RingColor(ringOf[p.portrait], unit) end
        end
    end)
    for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_DISPLAYPOWER" }) do
        NS.On(ev, Reapply)
    end
end

function M:Apply()
    HookGame()
    ApplyAll()
end

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
function M.Build(page)
    local function Re() ApplyAll() end
    page:Section("Frames", "Which of the game's frames to restyle")
    page:Note("Name above a big health bar with the number, a thin power bar, black borders and a round "
        .. "portrait. The game's frames stay the game's frames: right-click menus and clicking to target keep "
        .. "working. Turning a frame off puts most of it back at once; a /reload restores it fully.")
    page:Check("Player", function() return S().player end, function(v) S().player = v; Re() end)
    page:Check("Target", function() return S().target end, function(v) S().target = v; Re() end)
    page:Check("Target of target", function() return S().tot end, function(v) S().tot = v; Re() end)

    page:Section("Look", "Colours, text and size")
    page:Check("Class-coloured health for players", function() return S().classHealth end,
        function(v) S().classHealth = v; Re() end)
    page:Check("Class icons as players' portraits", function() return S().classIcons end,
        function(v) S().classIcons = v; Re() end)
    page:Check("Red portrait ring while in combat", function() return S().combatRing end,
        function(v) S().combatRing = v; Re() end)
    page:Cycle("Health text", { { "value", "Number" }, { "percent", "Percent" }, { "both", "Number and percent" },
        { "none", "None" } }, function() return S().healthText end, function(v) S().healthText = v; Re() end)
    page:Check("Power number on the power bar", function() return S().powerText end,
        function(v) S().powerText = v; Re() end)
    page:Check("Show level", function() return S().showLevel end, function(v) S().showLevel = v; Re() end)
    page:Slider("Border thickness", 0, 4, 1, function() return S().border end, function(v) S().border = v; Re() end)
    page:Slider("Health bar width", 90, 180, 2, function() return S().healthWidth end,
        function(v) S().healthWidth = v; Re() end)
    page:Slider("Health bar height", 14, 34, 1, function() return S().healthHeight end,
        function(v) S().healthHeight = v; Re() end)
    page:Slider("Power bar height", 4, 14, 1, function() return S().powerHeight end,
        function(v) S().powerHeight = v; Re() end)
    page:Slider("Portrait size", 36, 70, 2, function() return S().portraitSize end,
        function(v) S().portraitSize = v; Re() end)
    page:Slider("Health text size", 10, 22, 1, function() return S().fontSize end,
        function(v) S().fontSize = v; Re() end)
end

function M:Diagnose()
    local st = M.stats
    for key in pairs(UNITS) do
        NS.Print(string.format("  %s: %s", key, tostring(st.found[key] or "not looked up yet")))
    end
    NS.Print(string.format("  layouts %d   secret health shown raw %d   errors %d   last error %s",
        st.layouts, st.secretText, st.errors, tostring(st.lastError or "-")))
end
