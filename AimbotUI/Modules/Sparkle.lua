--[[
  Aimbot UI - Button Sparkle module   (modelled on jButtonFlash, Retail API)

  jButtonFlash in one sentence: when an action button is pressed, one white
  star pops to 1.5x the button, then shrinks to nothing while spinning 90
  degrees over 0.3 seconds. The default settings here reproduce exactly that.

  On top of it you get: more shapes, extra layers (burst, ring, flying stars),
  colors (custom / class / random), timing and size, layering, trigger choice
  (press or release, keyboard and/or mouse), third-party bar support, presets
  and a live preview.

  The module only looks at which button was pressed; it never reads combat data.
]]

local ADDON_NAME, NS = ...

local MEDIA = "Interface\\AddOns\\AimbotUI\\media\\sparkle\\"

local M = {
    name = "Button Sparkle",
    group = "Combat",
    desc = "A flash on your action buttons when you press them, like jButtonFlash. "
        .. "Presets, shapes, colors, timing and a live preview.   Quick toggle: /sparkle   |   test: /sparkle test",
    defaults = {
        enabled     = true,

        -- when / where
        when        = "down",     -- "down" = pressed, "up" = released
        keys        = true,       -- keybind presses
        mouse       = true,       -- mouse clicks
        thirdParty  = true,       -- Bartender4 / Dominos / ElvUI buttons
        skipEmpty   = true,
        onlyCombat  = false,

        -- look (all layers)
        colorMode   = "custom",   -- "custom" / "class" / "random"
        color       = { 1, 1, 1, 1 },
        opacity     = 1.0,
        size        = 1.0,
        speed       = 1.0,        -- duration multiplier (higher = slower)
        padding     = 3,          -- pixels added around the button (main flash)
        strata      = "TOOLTIP",
        blend       = "ADD",
        ease        = "NONE",     -- "NONE" = linear, "OUT" = eased

        -- main flash (the jButtonFlash star)
        main        = true,
        mainTex     = "star4",
        mainStart   = 1.5,
        mainEnd     = 0,
        mainSpin    = 90,
        mainTime    = 0.3,
        mainFade    = false,

        -- center burst
        burst       = false,
        burstTex    = "starburst",
        burstStart  = 0.5,
        burstEnd    = 1.3,
        burstSpin   = 45,
        burstTime   = 0.35,
        burstFade   = true,

        -- expanding ring
        ring        = false,
        ringTex     = "ping4",
        ringStart   = 0.4,
        ringEnd     = 1.5,
        ringSpin    = 0,
        ringTime    = 0.3,
        ringFade    = true,

        -- flying stars
        stars       = false,
        starTex     = "star4",
        starCount   = 6,
        starDist    = 1.0,
        starSize    = 0.4,
        starEnd     = 0.2,
        starSpin    = 120,
        starTime    = 0.5,
    },
}
NS.RegisterModule("sparkle", M)

local function S() return NS.db.mod.sparkle end

M.stats = { played = 0, byKind = {}, skip = {}, recent = {} }

----------------------------------------------------------------------
-- Textures
----------------------------------------------------------------------
local TEXTURES = {
    star4       = "Interface\\Cooldown\\star4",
    starburst   = "Interface\\Cooldown\\starburst",
    ping4       = "Interface\\Cooldown\\ping4",
    flare       = MEDIA .. "flare",
    spark8      = MEDIA .. "spark8",
    glow        = MEDIA .. "glow",
    squareglow  = MEDIA .. "squareglow",
}
local TEXTURE_OPTIONS = {
    { "star4",      "Star (jButtonFlash)" },
    { "starburst",  "Starburst" },
    { "ping4",      "Ring" },
    { "flare",      "Flare cross" },
    { "spark8",     "Eight-point sparkle" },
    { "glow",       "Soft glow" },
    { "squareglow", "Button outline glow" },
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function HSV(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

local function PickColor(cfg)
    if cfg.colorMode == "class" then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    elseif cfg.colorMode == "random" then
        return HSV(math.random(), 0.65, 1)
    end
    local c = cfg.color
    return c[1], c[2], c[3]
end

----------------------------------------------------------------------
-- Building the effect on a button
----------------------------------------------------------------------
local overlays = {}       -- button -> overlay state
local lastFire = {}       -- button -> time of last flash

local function NewLayer(frame)
    local L = {}
    local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetPoint("CENTER", frame, "CENTER", 0, 0)
    t:SetAlpha(0)
    L.tex = t

    local g = t:CreateAnimationGroup()
    L.group = g
    -- whatever the engine does with animated alpha, a finished or stopped layer is invisible
    g:SetScript("OnFinished", function() t:SetAlpha(0) end)
    g:SetScript("OnStop", function() t:SetAlpha(0) end)

    -- order 1: happens instantly (this is the jButtonFlash "pop")
    L.alphaIn = g:CreateAnimation("Alpha")
    L.alphaIn:SetFromAlpha(0); L.alphaIn:SetToAlpha(1)
    L.alphaIn:SetDuration(0); L.alphaIn:SetOrder(1)

    L.scaleIn = g:CreateAnimation("Scale")
    L.scaleIn:SetDuration(0); L.scaleIn:SetOrder(1)

    -- order 2: the visible motion
    L.scaleOut = g:CreateAnimation("Scale")
    L.scaleOut:SetOrder(2)

    L.rot = g:CreateAnimation("Rotation")
    L.rot:SetOrder(2)

    L.fade = g:CreateAnimation("Alpha")
    L.fade:SetOrder(2)
    return L
end

local function NewOverlay(btn)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:EnableMouse(false)
    f:SetSize(36, 36)
    return { frame = f, layers = {}, stars = {} }
end

local function Overlay(btn)
    local s = overlays[btn]
    if not s then
        s = NewOverlay(btn)
        overlays[btn] = s
    end
    return s
end

local function EnsureLayer(s, name)
    local L = s.layers[name]
    if not L then
        L = NewLayer(s.frame)
        s.layers[name] = L
    end
    return L
end

local function EnsureStar(s, i)
    local L = s.stars[i]
    if not L then
        L = NewLayer(s.frame)
        L.trans = L.group:CreateAnimation("Translation")
        L.trans:SetOrder(2)
        s.stars[i] = L
    end
    return L
end

-- Configure one layer for this flash. p = { tex, size, start, stop, spin, time, fade }
local function Setup(L, cfg, r, g, b, p, curve)
    local speed = cfg.speed
    local st = math.max(p.start * cfg.size, 0.001)
    local en = math.max(p.stop * cfg.size, 0.001)
    local dur = math.max(p.time * speed, 0.02)

    L.group:Stop()
    L.tex:SetTexture(TEXTURES[p.tex] or TEXTURES.star4)
    L.tex:SetBlendMode(cfg.blend == "ADD" and "ADD" or "BLEND")
    L.tex:SetVertexColor(r, g, b, cfg.opacity)
    L.tex:SetSize(p.size, p.size)

    if L.scaleIn.SetScaleFrom then
        L.scaleIn:SetScaleFrom(1, 1);  L.scaleIn:SetScaleTo(st, st)
        L.scaleOut:SetScaleFrom(st, st); L.scaleOut:SetScaleTo(en, en)
    else
        L.scaleIn:SetScale(st, st)
        L.scaleOut:SetScale(en / st, en / st)
    end
    L.scaleOut:SetDuration(dur)
    L.scaleOut:SetSmoothing(curve)

    L.rot:SetDegrees(p.spin)
    L.rot:SetDuration(dur)
    L.rot:SetSmoothing(curve)

    L.fade:SetFromAlpha(1)
    L.fade:SetToAlpha(p.fade and 0 or 1)
    L.fade:SetDuration(dur)
    L.fade:SetSmoothing(p.fade and "IN" or "NONE")
end

----------------------------------------------------------------------
-- Play
----------------------------------------------------------------------
local DEBOUNCE = 0.06
local sizeCache = {}

-- Hard stop: guarantees an overlay never stays on screen, even if an animation
-- group were to hang. Each flash gets a token so a newer flash isn't cut short.
local function HardStop(s)
    for _, L in pairs(s.layers) do L.group:Stop(); L.tex:SetAlpha(0) end
    for _, L in ipairs(s.stars) do L.group:Stop(); L.tex:SetAlpha(0) end
    s.frame:Hide()
end

local function TotalTime(cfg)
    local m = 0
    if cfg.main  then m = math.max(m, cfg.mainTime) end
    if cfg.burst then m = math.max(m, cfg.burstTime) end
    if cfg.ring  then m = math.max(m, cfg.ringTime) end
    if cfg.stars then m = math.max(m, cfg.starTime) end
    return m * cfg.speed
end

local function ButtonHasAction(btn)
    local action = NS.GetAction(btn)
    if action and HasAction then
        local ok, has = pcall(HasAction, action)
        if ok and not NS.IsSecret(has) then return has and true or false end
    end
    return true
end

local function Play(btn, force)
    local cfg = S()
    local skip = M.stats.skip
    if not force then
        if not cfg.enabled then skip.off = (skip.off or 0) + 1; return end
        if cfg.onlyCombat and not UnitAffectingCombat("player") then skip.combat = (skip.combat or 0) + 1; return end
    end
    if not btn or not btn.IsVisible or not btn:IsVisible() then skip.hidden = (skip.hidden or 0) + 1; return end

    local now = GetTime()
    local last = lastFire[btn]
    if last and (now - last) < DEBOUNCE then skip.debounce = (skip.debounce or 0) + 1; return end
    lastFire[btn] = now

    if not force and cfg.skipEmpty and not ButtonHasAction(btn) then skip.empty = (skip.empty or 0) + 1; return end

    local s = Overlay(btn)
    local f = s.frame

    -- size of the button, expressed in the overlay's own units
    -- In combat the client can hand back secret numbers for a protected button's geometry;
    -- comparing one would throw and kill the flash, so only trust real numbers and
    -- fall back to the last good size.
    local function Num(v) if type(v) == "number" and not NS.IsSecret(v) then return v end end
    local okSize, bw, bh = pcall(btn.GetSize, btn)
    bw, bh = Num(okSize and bw or nil), Num(okSize and bh or nil)
    if bw and bh and bw >= 8 then
        sizeCache[btn] = { bw, bh }
    else
        local c = sizeCache[btn]
        if c then bw, bh = c[1], c[2] else bw, bh = 36, 36 end
    end
    local okS, bsRaw = pcall(btn.GetEffectiveScale, btn)
    local bs, fs = Num(okS and bsRaw or nil), Num(f:GetEffectiveScale())
    local ratio = 1
    if bs and fs and bs > 0 and fs > 0 then ratio = bs / fs end
    local w, h = bw * ratio, bh * ratio
    local m = math.max(w, h)

    f:ClearAllPoints()
    f:SetPoint("CENTER", btn, "CENTER", 0, 0)
    f:SetSize(w, h)
    f:SetFrameStrata(force == "preview" and "TOOLTIP" or cfg.strata)
    f:Show()
    s.token = (s.token or 0) + 1
    local token = s.token
    C_Timer.After(TotalTime(cfg) + 0.15, function()
        if s.token == token then HardStop(s) end
    end)

    local r, g, b = PickColor(cfg)
    local curve = cfg.ease == "OUT" and "OUT" or "NONE"

    if cfg.main then
        local L = EnsureLayer(s, "main")
        Setup(L, cfg, r, g, b, {
            tex = cfg.mainTex, size = m + cfg.padding * 2, start = cfg.mainStart, stop = cfg.mainEnd,
            spin = cfg.mainSpin, time = cfg.mainTime, fade = cfg.mainFade,
        }, curve)
        L.group:Play()
    end
    if cfg.burst then
        local L = EnsureLayer(s, "burst")
        Setup(L, cfg, r, g, b, {
            tex = cfg.burstTex, size = m * 1.5, start = cfg.burstStart, stop = cfg.burstEnd,
            spin = cfg.burstSpin, time = cfg.burstTime, fade = cfg.burstFade,
        }, curve)
        L.group:Play()
    end
    if cfg.ring then
        local L = EnsureLayer(s, "ring")
        Setup(L, cfg, r, g, b, {
            tex = cfg.ringTex, size = m * 1.2, start = cfg.ringStart, stop = cfg.ringEnd,
            spin = cfg.ringSpin, time = cfg.ringTime, fade = cfg.ringFade,
        }, curve)
        L.group:Play()
    end
    if cfg.stars then
        local n = math.floor(cfg.starCount + 0.5)
        local radius = m * 0.75 * cfg.starDist * cfg.size
        local base = math.random() * 360
        for i = 1, n do
            local L = EnsureStar(s, i)
            Setup(L, cfg, r, g, b, {
                tex = cfg.starTex, size = m * cfg.starSize, start = 1 / cfg.size, stop = cfg.starEnd / cfg.size,
                spin = cfg.starSpin, time = cfg.starTime, fade = true,
            }, "OUT")
            local ang = math.rad(base + (i - 1) * (360 / n) + math.random(-15, 15))
            local dist = radius * (0.8 + math.random() * 0.5)
            L.trans:SetOffset(math.cos(ang) * dist, math.sin(ang) * dist)
            L.trans:SetDuration(math.max(cfg.starTime * cfg.speed, 0.02))
            L.trans:SetSmoothing("OUT")
            L.group:Play()
        end
        -- extra stars left over from a higher earlier count must not keep playing
        for i = n + 1, #s.stars do s.stars[i].group:Stop() end
    end

    M.stats.played = M.stats.played + 1
end

local function Fire(btn, kind)
    local cfg = S()
    if not cfg.enabled then return end
    if kind == "key" and not cfg.keys then return end
    if kind == "mouse" and not cfg.mouse then return end
    M.stats.byKind[kind] = (M.stats.byKind[kind] or 0) + 1
    local rec = M.stats.recent
    rec[#rec + 1] = string.format("%s %s", tostring(kind), (btn.GetName and btn:GetName()) or "?")
    if #rec > 8 then table.remove(rec, 1) end
    local ok, err = pcall(Play, btn)
    if not ok then
        M.stats.errors = (M.stats.errors or 0) + 1
        M.stats.lastError = tostring(err)
    end
end

----------------------------------------------------------------------
-- Preview / test
----------------------------------------------------------------------
local previewPending = false
function M:Preview()
    if previewPending then return end
    previewPending = true
    C_Timer.After(0.15, function()
        previewPending = false
        if M.previewBtn and M.previewBtn:IsVisible() then
            lastFire[M.previewBtn] = nil
            Play(M.previewBtn, "preview")
        end
        local real = _G["ActionButton1"]
        if real and M.page and M.page.frame and M.page.frame:IsShown() then
            lastFire[real] = nil
            Play(real, true)
        end
    end)
end

function M:Test()
    local b = _G["ActionButton1"]
    if b then
        lastFire[b] = nil
        Play(b, true)
    else
        NS.Print("ActionButton1 not found")
    end
end

function M:TestAll()
    NS.ForEachButton(function(btn)
        if btn:IsVisible() and ButtonHasAction(btn) then lastFire[btn] = nil; Play(btn, true) end
    end)
end

----------------------------------------------------------------------
-- Hooks
----------------------------------------------------------------------
local hooked, pushed, thirdSet = {}, {}, {}
local globalHooksDone = false
local hookedGlobals = {}

local THIRD_PARTY = {}
do
    for i = 1, 180 do THIRD_PARTY[#THIRD_PARTY + 1] = "BT4Button" .. i end
    for i = 1, 168 do THIRD_PARTY[#THIRD_PARTY + 1] = "DominosActionButton" .. i end
    for bar = 1, 15 do
        for i = 1, 12 do THIRD_PARTY[#THIRD_PARTY + 1] = "ElvUI_Bar" .. bar .. "Button" .. i end
    end
end

local function MouseIsDownOn(btn)
    if not (btn.IsMouseOver and IsMouseButtonDown) then return false end
    local ok, over = pcall(btn.IsMouseOver, btn)
    if not ok or not over then return false end
    return IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
end

local function HookButton(btn, isThird)
    if hooked[btn] then return end
    hooked[btn] = true
    if isThird then thirdSet[btn] = true end

    -- mouse
    if btn.HookScript then
        pcall(btn.HookScript, btn, "OnMouseDown", function(self)
            if S().when == "down" and not (thirdSet[self] and not S().thirdParty) then Fire(self, "mouse") end
        end)
        pcall(btn.HookScript, btn, "OnMouseUp", function(self)
            if S().when == "up" and not (thirdSet[self] and not S().thirdParty) then Fire(self, "mouse") end
        end)
    end

    -- clicks: a Double Press proxy "clicks" the real button, which runs its PreClick/PostClick
    -- scripts whatever key was used, so this catches presses the key hooks never see.
    if btn.HookScript then
        pcall(btn.HookScript, btn, "PreClick", function(self, _, down)
            if thirdSet[self] and not S().thirdParty then return end
            M.stats.click = (M.stats.click or 0) + 1
            if MouseIsDownOn(self) then return end         -- real mouse clicks are handled above
            if (down and S().when == "down") or (not down and S().when == "up") then Fire(self, "key") end
        end)
    end

    -- keybinds: Blizzard (and most addons) drive the pushed look through SetButtonState
    local function OnState(self, state)
        if thirdSet[self] and not S().thirdParty then return end
        if state == "PUSHED" then
            pushed[self] = true
            if S().when == "down" then
                Fire(self, MouseIsDownOn(self) and "mouse" or "key")
            end
        elseif state == "NORMAL" and pushed[self] then
            pushed[self] = nil
            if S().when == "up" then
                local over = self.IsMouseOver and self:IsMouseOver()
                Fire(self, over and "mouse" or "key")
            end
        end
    end
    if type(btn.SetButtonState) == "function" then pcall(hooksecurefunc, btn, "SetButtonState", OnState) end
    if type(btn.SetButtonStateBase) == "function" then pcall(hooksecurefunc, btn, "SetButtonStateBase", OnState) end
end

local function ButtonForID(id)
    local b = (type(_G.GetActionButtonForID) == "function") and _G.GetActionButtonForID(id) or nil
    return b or _G["ActionButton" .. tostring(id)]
end

local function HookGlobals()
    if globalHooksDone then return end
    globalHooksDone = true
    local function Try(name, fn)
        if type(_G[name]) == "function" then
            hookedGlobals[name] = pcall(hooksecurefunc, name, fn)
        else
            hookedGlobals[name] = false
        end
    end
    Try("ActionButtonDown", function(id)
        if S().when == "down" then local b = ButtonForID(id); if b then Fire(b, "key") end end
    end)
    Try("ActionButtonUp", function(id)
        if S().when == "up" then local b = ButtonForID(id); if b then Fire(b, "key") end end
    end)
    Try("MultiActionButtonDown", function(bar, id)
        if S().when == "down" then local b = _G[tostring(bar) .. "Button" .. tostring(id)]; if b then Fire(b, "key") end end
    end)
    Try("MultiActionButtonUp", function(bar, id)
        if S().when == "up" then local b = _G[tostring(bar) .. "Button" .. tostring(id)]; if b then Fire(b, "key") end end
    end)
end

-- Called by the Double Press module: its proxy buttons take over the keybinds, so the
-- usual key hooks above never see those presses.
function NS.SparkleKey(btn, down)
    M.stats.proxy = (M.stats.proxy or 0) + 1
    local cfg = S()
    if thirdSet[btn] and not cfg.thirdParty then return end
    if (down and cfg.when == "down") or (not down and cfg.when == "up") then
        Fire(btn, "key")
    end
end

local function HookAll()
    NS.ForEachButton(function(btn) HookButton(btn, false) end)
    if S().thirdParty then
        for _, name in ipairs(THIRD_PARTY) do
            local b = _G[name]
            if b then HookButton(b, true) end
        end
    end
    HookGlobals()
end

function M:Diagnose()
    local n, t = 0, 0
    for b in pairs(hooked) do n = n + 1; if thirdSet[b] then t = t + 1 end end
    NS.Print(string.format("  buttons hooked: %d (%d from other bar addons)", n, t))
    local parts = {}
    for _, name in ipairs({ "ActionButtonDown", "ActionButtonUp", "MultiActionButtonDown", "MultiActionButtonUp" }) do
        parts[#parts + 1] = name .. "=" .. (hookedGlobals[name] and "|cff00ff00hooked|r" or "|cffff4444missing|r")
    end
    NS.Print("  " .. table.concat(parts, "  "))
    NS.Print("  GetActionButtonForID: " .. tostring(type(_G.GetActionButtonForID) == "function"))
    local k = {}
    for kind, c in pairs(M.stats.byKind) do k[#k + 1] = kind .. "=" .. c end
    NS.Print("  flashes played this session: " .. M.stats.played .. (#k > 0 and ("  (" .. table.concat(k, ", ") .. ")") or ""))
    NS.Print("  presses seen from Double Press buttons: " .. tostring(M.stats.proxy or 0)
        .. "   errors while playing: " .. tostring(M.stats.errors or 0))
    local sk = {}
    for reason, c in pairs(M.stats.skip) do sk[#sk + 1] = reason .. "=" .. c end
    NS.Print("  real-button clicks seen: " .. tostring(M.stats.click or 0)
        .. "   flashes dropped: " .. (#sk > 0 and table.concat(sk, ", ") or "none")
        .. "   when=" .. tostring(S().when) .. " keys=" .. tostring(S().keys))
    if #M.stats.recent > 0 then NS.Print("  last triggers: " .. table.concat(M.stats.recent, " | ")) end
    if M.stats.lastError then NS.Print("  last error: |cffff6666" .. M.stats.lastError .. "|r") end
    NS.Print("  Press some buttons, then run this again: key/mouse counts show which paths work on Forever.")
end

----------------------------------------------------------------------
-- Presets
----------------------------------------------------------------------
-- Settings that describe behaviour (not looks) are kept when a preset is loaded.
local CFG_VERSION = 2
local KEEP = {
    enabled = true, cfgVersion = true, when = true, keys = true, mouse = true,
    thirdParty = true, skipEmpty = true, onlyCombat = true, strata = true,
}

local PRESETS = {
    { "Classic jButtonFlash", {} },
    { "Fireworks", {
        color = { 1.0, 0.88, 0.45, 1 }, mainStart = 1.2, mainTime = 0.3,
        burst = true, ring = true, stars = true, ease = "OUT",
    } },
    { "Soft pulse", {
        color = { 0.45, 0.8, 1.0, 1 }, mainTex = "squareglow", mainStart = 0.95, mainEnd = 1.6,
        mainSpin = 0, mainTime = 0.4, mainFade = true, ease = "OUT",
    } },
    { "Razor flare", {
        mainTex = "flare", mainStart = 0.4, mainEnd = 2.4, mainSpin = 0, mainTime = 0.35, mainFade = true,
        ease = "OUT",
    } },
    { "Star shower", {
        color = { 1.0, 0.88, 0.45, 1 }, main = false, stars = true, starCount = 10, starDist = 1.3,
        starSize = 0.35, starSpin = 180, starTime = 0.6,
    } },
    { "Rainbow sparkle", {
        colorMode = "random", mainTex = "spark8", mainStart = 1.8, mainSpin = 180, mainTime = 0.35,
        ring = true, ringTex = "glow", ringEnd = 1.8, ease = "OUT",
    } },
}

function M.ApplyPreset(index)
    local p = PRESETS[index]
    if not p then return end
    local cfg = S()
    for k, v in pairs(M.defaults) do
        if not KEEP[k] then cfg[k] = Copy(v) end
    end
    for k, v in pairs(p[2]) do cfg[k] = Copy(v) end
    if NS.UI and NS.UI.RefreshAll then NS.UI.RefreshAll() end
    M:Preview()
end

----------------------------------------------------------------------
-- Settings page
----------------------------------------------------------------------
local function Changed() M:Preview() end

local function Bind(key)
    return function() return S()[key] end,
           function(v) S()[key] = v; Changed() end
end

function M.Build(page)
    M.page = page

    local function Check(label, key, desc)
        local g, s = Bind(key)
        return page:Check(label, g, s, desc)
    end
    local function Slide(label, min, max, step, key, fmt)
        local g, s = Bind(key)
        return page:Slider(label, min, max, step, g, s, fmt)
    end
    local function Cycle(label, options, key)
        local g, s = Bind(key)
        return page:Cycle(label, options, g, s)
    end
    local function X(v) return string.format("%.1fx", v) end
    local function Deg(v) return string.format("%d\194\176", math.floor(v + 0.5)) end
    local function Sec(v) return string.format("%.2fs", v) end
    local function Num(v) return string.format("%d", math.floor(v + 0.5)) end

    ------------------------------------------------------------------
    page:Section("Preview", "Live preview of the flash", { pinned = true })
    local box = page:Container()
    box:SetContentHeight(64)
    local dummy = CreateFrame("Button", nil, box)
    dummy:SetSize(44, 44)
    dummy:SetPoint("LEFT", box, "LEFT", 8, 0)
    local bg = dummy:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    local icon = dummy:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexture("Interface\\Icons\\Spell_Fire_FlameBolt")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dummy:SetScript("OnClick", function() lastFire[dummy] = nil; Play(dummy, "preview") end)
    M.previewBtn = dummy
    local play = NS.UI.MakeButton(box, "Play", 90, 24)
    play:SetPoint("LEFT", dummy, "RIGHT", 18, 0)
    play:SetScript("OnClick", function() lastFire[dummy] = nil; Play(dummy, "preview"); M:Test() end)
    local hint = NS.UI.Text(box, "Click the icon or Play. Any change also plays on your real action bar 1.", -1, 0.62, 0.62, 0.67)
    hint:SetPoint("LEFT", play, "RIGHT", 14, 0)
    hint:SetPoint("RIGHT", box, "RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")

    page:Button("Play on every visible action button", function() M:TestAll() end, 260)

    ------------------------------------------------------------------
    page:Section("Presets", "Ready-made looks, including the classic jButtonFlash")
    page:Note("Loads a complete look. Your trigger settings (below) are kept. "
        .. "Everything can still be fine-tuned afterwards.")
    for i, p in ipairs(PRESETS) do
        page:Button(p[1], function() M.ApplyPreset(i) end, 260)
    end

    ------------------------------------------------------------------
    page:Section("When it plays", "Which presses make it flash: keys, mouse, down or up")
    Cycle("Trigger", {
        { "down", "When pressed (like jButtonFlash)" },
        { "up",   "When released" },
    }, "when")
    Check("Keybind presses", "keys")
    Check("Mouse clicks", "mouse")
    Check("Skip empty buttons", "skipEmpty")
    Check("Only while in combat", "onlyCombat")
    Check("Bartender4, Dominos and ElvUI buttons", "thirdParty",
        "Also flashes buttons from those bar addons if you use them. Takes effect after /reload when switched on.")

    ------------------------------------------------------------------
    page:Section("Color", "Flash color, opacity, class color or random colors")
    Cycle("Color mode", {
        { "custom", "Custom color" },
        { "class",  "My class color" },
        { "random", "Random each press" },
    }, "colorMode")
    page:Color("Custom color",
        function() return S().color end,
        function(r, g, b, a) local c = S().color; c[1], c[2], c[3] = r, g, b; Changed() end)
    Slide("Opacity", 0.1, 1, 0.05, "opacity", function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
    Cycle("Blend", {
        { "ADD",   "Additive glow (jButtonFlash)" },
        { "BLEND", "Normal" },
    }, "blend")

    ------------------------------------------------------------------
    page:Section("Size, speed and layering", "Overall size and speed, and what it is drawn over")
    Slide("Overall size", 0.3, 3, 0.1, "size", X)
    Slide("Overall duration (higher = slower)", 0.3, 4, 0.1, "speed", X)
    Slide("Extra pixels around the button", 0, 30, 1, "padding", Num)
    Cycle("Motion", {
        { "NONE", "Linear (jButtonFlash)" },
        { "OUT",  "Eased out" },
    }, "ease")
    Cycle("Draw above", {
        { "TOOLTIP", "Everything (jButtonFlash)" },
        { "FULLSCREEN_DIALOG", "Windows" },
        { "HIGH", "Other bars and frames" },
        { "MEDIUM", "Normal frames" },
    }, "strata")

    ------------------------------------------------------------------
    local function LayerSection(title, desc, enableKey, prefix)
        page:Section(title, desc)
        Check("Enabled", enableKey)
        Cycle("Shape", TEXTURE_OPTIONS, prefix .. "Tex")
        Slide("Start size", 0, 4, 0.1, prefix .. "Start", X)
        Slide("End size", 0, 4, 0.1, prefix .. "End", X)
        Slide("Spin", -720, 720, 15, prefix .. "Spin", Deg)
        Slide("Duration", 0.05, 1.5, 0.05, prefix .. "Time", Sec)
        Check("Fade out", prefix .. "Fade")
    end
    LayerSection("Main flash (the jButtonFlash star)", "The star that pops on the button", "main", "main")
    LayerSection("Center burst", "A soft flash in the middle of the button", "burst", "burst")
    LayerSection("Expanding ring", "A ring that grows outward from the button", "ring", "ring")

    page:Section("Flying stars", "Little stars that fly off the button")
    Check("Enabled", "stars")
    Cycle("Shape", TEXTURE_OPTIONS, "starTex")
    Slide("How many", 1, 16, 1, "starCount", Num)
    Slide("Distance", 0.3, 3, 0.1, "starDist", X)
    Slide("Star size", 0.1, 1.5, 0.05, "starSize", function(v) return string.format("%.2f", v) end)
    Slide("End size", 0, 2, 0.1, "starEnd", X)
    Slide("Spin", -720, 720, 15, "starSpin", Deg)
    Slide("Duration", 0.1, 2, 0.05, "starTime", Sec)

    page:Section("Notes", "How the defaults were chosen")
    page:Note("The defaults match jButtonFlash: one white star that pops to 1.5x and shrinks away while "
        .. "spinning 90 degrees in 0.3 seconds. Load the \"Classic jButtonFlash\" preset to get back to it. "
        .. "If keybind presses don't flash, run /aimbot diag and send me the Button Sparkle lines.")
end

----------------------------------------------------------------------
function M:Apply()
    if S().cfgVersion == nil then S().cfgVersion = CFG_VERSION end   -- e.g. after "Reset tab"
    HookAll()
end

function M:Init()
    -- Settings saved by the first version of this module (gold, random burst/ring/stars)
    -- are replaced once with the classic jButtonFlash look.
    local cfg = S()
    if (cfg.cfgVersion or 0) < CFG_VERSION then
        for k, v in pairs(M.defaults) do
            if not KEEP[k] then cfg[k] = Copy(v) end
        end
        cfg.cfgVersion = CFG_VERSION
    end
    HookAll()
end
