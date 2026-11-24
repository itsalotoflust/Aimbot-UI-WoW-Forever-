--[[
  Aimbot UI - Cast Bar (2.31.0)
  A classic-style player cast bar in place of the game's modern one: the thin 195 x 13 bar with
  the classic border, spark and flash. Yellow while casting, green while channelling, a green
  flash when the cast finishes, red with "Interrupted" or "Failed" when it doesn't, then a short
  fade. Optional: spell icon, seconds left, latency zone, plain border.

  The game's own player cast bar is hidden with method calls only (SetAlpha in a post-hook on
  Show / OnShow); switching the module or the option off gives it back.

  Every value read from the game is checked with NS.IsSecret. If the cast times are secret, the
  bar shows full with the spell name and no timer until the cast ends (no arithmetic on them).
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Cast Bar",
    group = "Combat",
    desc = "A classic-style cast bar for your own casts, in place of the game's modern one: classic "
        .. "border, spark and flash, yellow casts, green channels, red interrupts.",
    defaults = {
        enabled      = true,
        hideBlizzard = true,
        locked       = true,
        point        = { "BOTTOM", "BOTTOM", 0, 175 },
        width        = 195,          -- classic size
        height       = 13,
        border       = "classic",    -- "classic" (the game's classic art) or "simple" (1 px line)
        showIcon     = false,
        showTimer    = true,
        showLatency  = false,
        showSpark    = true,
        fontSize     = 12,
        textNudge    = 0,            -- 2.31.1: extra pixels up (+) or down (-) for the text
        colors = {
            cast    = { 1.0, 0.7, 0.0 },
            channel = { 0.0, 1.0, 0.0 },
            success = { 0.0, 1.0, 0.0 },
            failed  = { 1.0, 0.0, 0.0 },
        },
    },
}
NS.RegisterModule("castbar", M)

local function S() return NS.db.mod.castbar end
local IsSecret = NS.IsSecret

M.stats = { casts = 0, channels = 0, done = 0, failed = 0, secret = 0, hidden = "-", lastError = nil }

local function Clean(v)
    if v == nil then return nil end
    if IsSecret(v) then M.stats.secret = M.stats.secret + 1; return nil end
    return v
end

local function Now() return (GetTime and GetTime()) or 0 end

local TEX_BAR    = "Interface\\TargetingFrame\\UI-StatusBar"
local TEX_BORDER = "Interface\\CastingBar\\UI-CastingBar-Border"
local TEX_FLASH  = "Interface\\CastingBar\\UI-CastingBar-Flash"
local TEX_SPARK  = "Interface\\CastingBar\\UI-CastingBar-Spark"

local HOLD_FAILED = 1.0      -- seconds the red bar stays before fading
local FADE_TIME   = 0.5      -- seconds to fade out
local FLASH_TIME  = 0.2      -- seconds for the finish flash to come in

----------------------------------------------------------------------
-- State
-- mode: nil (hidden), "cast", "channel", "unknown" (times secret), "done", "failed", "fade"
----------------------------------------------------------------------
local st = { mode = nil }
M._t_State = function() return st end

-- Read the player's current cast or channel. Returns a table or nil.
local function ReadCast(unit)
    unit = unit or "player"
    local kind, name, texture, startMS, endMS, castID, spellID
    if UnitCastingInfo then
        local ok, n, _, tex, s, e, _, cid, _, sid = pcall(UnitCastingInfo, unit)
        if ok and n ~= nil then
            kind, name, texture, startMS, endMS, castID, spellID = "cast", n, tex, s, e, cid, sid
        end
    end
    if not kind and UnitChannelInfo then
        local ok, n, _, tex, s, e, _, _, sid = pcall(UnitChannelInfo, unit)
        if ok and n ~= nil then
            kind, name, texture, startMS, endMS, spellID = "channel", n, tex, s, e, sid
        end
    end
    if not kind then return nil end
    local c = { kind = kind, name = Clean(name), texture = Clean(texture), castID = Clean(castID),
        spellID = Clean(spellID) }
    local s, e = Clean(startMS), Clean(endMS)
    if type(s) == "number" and type(e) == "number" and e > s then
        c.start, c.finish = s / 1000, e / 1000
    end
    return c
end
M._t_ReadCast = ReadCast

local function Latency()
    if not GetNetStats then return nil end
    local ok, _, _, home, world = pcall(GetNetStats)
    if not ok then return nil end
    local ms = Clean(world) or Clean(home)
    if type(ms) == "number" and ms >= 0 then return ms / 1000 end
    return nil
end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------
local bar, bg, border, flash, spark, text, timer, icon, safe, label
local edges = {}

local function Color(key)
    local c = S().colors[key] or M.defaults.colors[key]
    return c[1], c[2], c[3]
end

local function SavePosition()
    local point, _, rel, x, y = bar:GetPoint()
    if point then local p = S().point; p[1], p[2], p[3], p[4] = point, rel, x, y end
end

-- Classic art sizes, scaled to the bar: the 256 x 64 border sits 28 px above a 195 x 13 bar.
local function ArtGeometry(w, h)
    return w * 256 / 195, h * 64 / 13, h * 28 / 13
end
M._t_ArtGeometry = ArtGeometry

-- 2.31.1: how far above the bar's centre the text sits. Letters sit low in their font box, so
-- centred text looks low; the classic bar lifts its text 3.5 px at 13 px high. Scales with the bar.
local function TextOffset(h, nudge)
    return h * 3.5 / 13 + (nudge or 0)
end
M._t_TextOffset = TextOffset

local function Layout()
    if not bar then return end
    local s = S()
    local p = s.point
    bar:ClearAllPoints()
    bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    bar:SetSize(s.width, s.height)
    bar:EnableMouse(not s.locked)
    local bw, bh, by = ArtGeometry(s.width, s.height)
    local classic = s.border ~= "simple"
    border:ClearAllPoints()
    border:SetPoint("TOP", bar, "TOP", 0, by)
    border:SetSize(bw, bh)
    border:SetShown(classic)
    flash:ClearAllPoints()
    flash:SetPoint("TOP", bar, "TOP", 0, by)
    flash:SetSize(bw, bh)
    for _, e in ipairs(edges) do e:SetShown(not classic) end
    spark:SetSize(32 * s.height / 13, 32 * s.height / 13)
    local ok = pcall(text.SetFont, text, STANDARD_TEXT_FONT, s.fontSize or 12, "")
    if not ok then text:SetFontObject(GameFontHighlight) end
    pcall(timer.SetFont, timer, STANDARD_TEXT_FONT, math.max(8, (s.fontSize or 12) - 2), "OUTLINE")
    icon:SetSize(s.height + 6, s.height + 6)
    local ty = TextOffset(s.height, s.textNudge)
    text:ClearAllPoints()
    text:SetPoint("CENTER", bar, "CENTER", 0, ty)
    timer:ClearAllPoints()
    timer:SetPoint("RIGHT", bar, "RIGHT", -3, ty)
    label:SetShown(not s.locked)
end

local function EnsureBar()
    if bar then return bar end
    bar = CreateFrame("StatusBar", "AimbotUICastBar", UIParent)
    bar:SetFrameStrata("HIGH")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not S().locked then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    bar:SetStatusBarTexture(TEX_BAR)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    safe = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    safe:SetColorTexture(1, 0, 0, 0.55)
    safe:Hide()
    border = bar:CreateTexture(nil, "OVERLAY")
    border:SetTexture(TEX_BORDER)
    -- simple border: a 1 px black line just outside the bar
    local function Edge(p1, x1, y1, p2, x2, y2)
        local t = bar:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        t:SetPoint(p1, bar, p1, x1, y1)
        t:SetPoint(p2, bar, p2, x2, y2)
        edges[#edges + 1] = t
        return t
    end
    Edge("TOPLEFT", -1, 1, "TOPRIGHT", 1, 1):SetHeight(1)
    Edge("BOTTOMLEFT", -1, -1, "BOTTOMRIGHT", 1, -1):SetHeight(1)
    Edge("TOPLEFT", -1, 1, "BOTTOMLEFT", -1, -1):SetWidth(1)
    Edge("TOPRIGHT", 1, 1, "BOTTOMRIGHT", 1, -1):SetWidth(1)
    flash = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    flash:SetTexture(TEX_FLASH)
    flash:SetBlendMode("ADD")
    flash:Hide()
    spark = bar:CreateTexture(nil, "OVERLAY", nil, 3)
    spark:SetTexture(TEX_SPARK)
    spark:SetBlendMode("ADD")
    text = bar:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", bar, "CENTER", 0, 1)
    text:SetTextColor(1, 1, 1)
    timer = bar:CreateFontString(nil, "OVERLAY")
    timer:SetPoint("RIGHT", bar, "RIGHT", -3, 1)
    timer:SetTextColor(1, 1, 1)
    icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("RIGHT", bar, "LEFT", -6, 0)
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
    label = bar:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    label:SetPoint("BOTTOM", bar, "TOP", 0, 18)
    label:SetText("Cast Bar (drag me)")
    bar:Hide()
    Layout()
    return bar
end

local function SetFill(key)
    bar:SetStatusBarColor(Color(key))
end

local function FormatLeft(sec)
    if type(sec) ~= "number" or sec < 0 then return "" end
    return string.format("%.1f", sec)
end
M._t_FormatLeft = FormatLeft

-- Latency zone: the end of a cast (or the start of a channel) that the server may already count.
local function SafeZone(c, s)
    if not s.showLatency or not c or not c.start then safe:Hide(); return end
    local lag = Latency()
    local dur = c.finish - c.start
    if not lag or dur <= 0 then safe:Hide(); return end
    local w = math.min(1, lag / dur) * s.width
    if w < 1 then safe:Hide(); return end
    safe:ClearAllPoints()
    if c.kind == "channel" then
        safe:SetPoint("TOPLEFT", bar, "TOPLEFT"); safe:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
    else
        safe:SetPoint("TOPRIGHT", bar, "TOPRIGHT"); safe:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
    end
    safe:SetWidth(w)
    safe:Show()
end

-- Start showing a cast / channel read from the game (or a test one).
local function Begin(c)
    if not S().enabled or not c then return end
    EnsureBar()
    local s = S()
    st.cast = c
    st.mode = c.start and c.kind or "unknown"
    st.holdUntil, st.fadeFrom = nil, nil
    if c.kind == "channel" then M.stats.channels = M.stats.channels + 1 else M.stats.casts = M.stats.casts + 1 end
    SetFill(c.kind == "channel" and "channel" or "cast")
    bar:SetAlpha(1)
    flash:Hide()
    text:SetText(c.name or "")
    timer:SetText("")
    timer:SetShown(s.showTimer and c.start ~= nil)
    icon:SetTexture(c.texture)
    icon:SetShown(s.showIcon and c.texture ~= nil)
    spark:SetShown(s.showSpark and c.start ~= nil)
    SafeZone(c, s)
    if c.start then
        bar:SetMinMaxValues(0, c.finish - c.start)
        bar:SetValue(c.kind == "channel" and (c.finish - c.start) or 0)
    else
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
    end
    bar:Show()
end
M._t_Begin = Begin

-- The cast finished: green flash, then fade.
local function Finish()
    if not bar or not (st.mode == "cast" or st.mode == "unknown") then return end
    M.stats.done = M.stats.done + 1
    st.mode = "done"
    st.fadeFrom = Now()
    local lo, hi = bar:GetMinMaxValues()
    bar:SetValue(hi or 1)
    SetFill("success")
    spark:Hide()
    safe:Hide()
    timer:SetText("")
    flash:SetAlpha(0)
    flash:Show()
end
M._t_Finish = Finish

-- The cast was interrupted or failed: red with the reason, hold, then fade.
local function Fail(reason)
    if not bar or not (st.mode == "cast" or st.mode == "channel" or st.mode == "unknown") then return end
    M.stats.failed = M.stats.failed + 1
    st.mode = "failed"
    st.holdUntil = Now() + HOLD_FAILED
    local lo, hi = bar:GetMinMaxValues()
    bar:SetValue(hi or 1)
    SetFill("failed")
    spark:Hide()
    safe:Hide()
    flash:Hide()
    timer:SetText("")
    text:SetText(reason)
end
M._t_Fail = Fail

-- A channel ended (or a cast stopped without a success event): just fade.
local function FadeOut()
    if not bar or st.mode == nil or st.mode == "failed" or st.mode == "done" or st.mode == "fade" then return end
    st.mode = "fade"
    st.fadeFrom = Now()
    spark:Hide()
    safe:Hide()
end
M._t_FadeOut = FadeOut

local ShowPlaceholder
local function Stop()
    st.mode, st.cast = nil, nil
    if bar then bar:Hide() end
    if ShowPlaceholder then ShowPlaceholder() end
end

-- Per-frame update (also called directly by the tests).
local function Tick()
    if not bar or not bar:IsShown() then return end
    local s = S()
    local now = Now()
    local c = st.cast
    if (st.mode == "cast" or st.mode == "channel") and c and c.start then
        local dur = c.finish - c.start
        local value
        if st.mode == "cast" then
            value = math.min(dur, math.max(0, now - c.start))
        else
            value = math.min(dur, math.max(0, c.finish - now))
        end
        bar:SetValue(value)
        if s.showSpark and dur > 0 then
            spark:ClearAllPoints()
            spark:SetPoint("CENTER", bar, "LEFT", s.width * value / dur, 0)
        end
        if s.showTimer then timer:SetText(FormatLeft(c.finish - now)) end
        if now >= c.finish + 0.5 then
            -- no end event came (rare): treat a cast as done, a channel as over
            if st.mode == "cast" then Finish() else FadeOut() end
        end
    elseif st.mode == "done" then
        local t = now - st.fadeFrom
        if t < FLASH_TIME then
            flash:SetAlpha(t / FLASH_TIME)
        else
            local a = 1 - (t - FLASH_TIME) / FADE_TIME
            if a <= 0 then Stop() else bar:SetAlpha(a); flash:SetAlpha(a) end
        end
    elseif st.mode == "failed" then
        if now >= st.holdUntil then
            local a = 1 - (now - st.holdUntil) / FADE_TIME
            if a <= 0 then Stop() else bar:SetAlpha(a) end
        end
    elseif st.mode == "fade" then
        local a = 1 - (now - st.fadeFrom) / FADE_TIME
        if a <= 0 then Stop() else bar:SetAlpha(a) end
    end
end
M._t_Tick = Tick

-- Unlocked: show the bar so it can be dragged.
function ShowPlaceholder()
    if not bar then return end
    local s = S()
    if s.enabled and not s.locked and st.mode == nil then
        SetFill("cast")
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.6)
        bar:SetAlpha(1)
        text:SetText("Cast Bar")
        timer:SetText("")
        spark:Hide(); safe:Hide(); flash:Hide(); icon:Hide()
        bar:Show()
    elseif st.mode == nil then
        bar:Hide()
    end
end

----------------------------------------------------------------------
-- The game's own player cast bar: hidden with method calls only
----------------------------------------------------------------------
local hookedFrames = {}
local silenced = {}          -- game bars whose events we unregistered (so we can give them back)
local function GameBars()
    local t = {}
    for _, n in ipairs({ "PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame", "CastingBarFrame" }) do
        local f = _G[n]
        local dup = false
        for _, g in ipairs(t) do if g == f then dup = true end end
        if f and not dup then t[#t + 1] = f end
    end
    return t
end

local function HideOn() local s = S(); return s.enabled and s.hideBlizzard end

-- 2.31.2: SetAlpha(0) alone wasn't enough: the game's bar plays its own interrupt / fade
-- animations, and an alpha animation overrides the frame's alpha. Now the bar's events are
-- unregistered (it never starts a cast or an interrupt), it is hidden, and its animations are
-- stopped. Method calls only.
local function StopAnims(f)
    if not f.GetAnimationGroups then return end
    local ok, groups = pcall(function() return { f:GetAnimationGroups() } end)
    if ok and type(groups) == "table" then
        for _, g in ipairs(groups) do pcall(g.Stop, g) end
    end
end

local function SilenceGame(f)
    if f.UnregisterAllEvents and pcall(f.UnregisterAllEvents, f) then silenced[f] = true end
    StopAnims(f)
    pcall(f.SetAlpha, f, 0)
    pcall(f.Hide, f)
end
M._t_SilenceGame = SilenceGame

local function RestoreGame(f)
    pcall(f.SetAlpha, f, 1)
    if silenced[f] then
        silenced[f] = nil
        -- link it to the player again so it gets its events back
        local okU = false
        if type(f.SetUnit) == "function" then
            okU = pcall(f.SetUnit, f, "player", true, true)
        elseif type(CastingBarFrame_SetUnit) == "function" then
            okU = pcall(CastingBarFrame_SetUnit, f, "player", true, true)
        end
        if not okU then M.stats.restoreNote = "type /reload to get the game's cast bar back" end
    end
end

local function ApplyGame(f)
    if HideOn() then SilenceGame(f) else RestoreGame(f) end
end

local function HookGameBars()
    local names = {}
    for _, f in ipairs(GameBars()) do
        if not hookedFrames[f] then
            hookedFrames[f] = true
            -- if the game shows it anyway, hide it again straight away
            pcall(hooksecurefunc, f, "Show", function(self)
                if HideOn() then pcall(self.SetAlpha, self, 0); pcall(self.Hide, self) end
            end)
            if f.HookScript then
                pcall(f.HookScript, f, "OnShow", function(self)
                    if HideOn() then pcall(self.SetAlpha, self, 0); pcall(self.Hide, self) end
                end)
            end
            -- the game links the bar to the player again (Edit Mode, settings): unregister again
            if type(f.SetUnit) == "function" then
                pcall(hooksecurefunc, f, "SetUnit", function(self)
                    if HideOn() then SilenceGame(self) end
                end)
            end
        end
        ApplyGame(f)
        local okN, n = pcall(f.GetName, f)
        names[#names + 1] = okN and tostring(n) or "?"
    end
    M.stats.hidden = #names > 0 and table.concat(names, ", ") or "none found"
end
M._t_HookGameBars = HookGameBars

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local function OnStart(_, unit)
    if unit ~= "player" then return end
    Begin(ReadCast("player"))
end

local function OnUpdateCast(_, unit)
    if unit ~= "player" or not st.cast then return end
    local c = ReadCast("player")
    if c and (st.mode == "cast" or st.mode == "channel" or st.mode == "unknown") then
        -- pushback / channel update: keep the bar, take the new times
        st.cast.start, st.cast.finish = c.start, c.finish
        if c.start then
            st.mode = c.kind
            bar:SetMinMaxValues(0, c.finish - c.start)
            SafeZone(st.cast, S())
        end
    end
end

local function OnFailed(event, unit, castID)
    if unit ~= "player" or st.mode == nil then return end
    if st.mode == "channel" and event == "UNIT_SPELLCAST_FAILED" then return end
    -- a failed cast attempt while a different cast is running isn't this cast failing
    local id = Clean(castID)
    if id and st.cast and st.cast.castID and id ~= st.cast.castID then return end
    Fail(event == "UNIT_SPELLCAST_INTERRUPTED" and (INTERRUPTED or "Interrupted") or (FAILED or "Failed"))
end

local function OnStop(event, unit, castID)
    if unit ~= "player" then return end
    local id = Clean(castID)
    if id and st.cast and st.cast.castID and id ~= st.cast.castID then return end
    local isChannel = st.cast and st.cast.kind == "channel"
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if isChannel and (st.mode == "channel" or st.mode == "unknown") then FadeOut() end
    elseif not isChannel and (st.mode == "cast" or st.mode == "unknown") then
        -- STOP / SUCCEEDED of a normal cast (a channel also sends SUCCEEDED when it starts)
        Finish()
    end
end

M._t_OnStart, M._t_OnStop, M._t_OnFailed, M._t_OnUpdateCast = OnStart, OnStop, OnFailed, OnUpdateCast

local function Safe(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then M.stats.lastError = tostring(err); NS.ReportError("Cast Bar", err) end
    end
end

local hooked = false
function M:Init()
    if hooked then return end
    hooked = true
    NS.On("UNIT_SPELLCAST_START", Safe(OnStart))
    NS.On("UNIT_SPELLCAST_CHANNEL_START", Safe(OnStart))
    NS.On("UNIT_SPELLCAST_DELAYED", Safe(OnUpdateCast))
    NS.On("UNIT_SPELLCAST_CHANNEL_UPDATE", Safe(OnUpdateCast))
    NS.On("UNIT_SPELLCAST_STOP", Safe(OnStop))
    NS.On("UNIT_SPELLCAST_SUCCEEDED", Safe(OnStop))
    NS.On("UNIT_SPELLCAST_CHANNEL_STOP", Safe(OnStop))
    NS.On("UNIT_SPELLCAST_FAILED", Safe(OnFailed))
    NS.On("UNIT_SPELLCAST_INTERRUPTED", Safe(OnFailed))
    NS.On("PLAYER_ENTERING_WORLD", Safe(function()
        HookGameBars()
        local c = ReadCast("player")
        if c then Begin(c) end
    end))
    EnsureBar()
    bar:SetScript("OnUpdate", function()
        local ok, err = pcall(Tick)
        if not ok then M.stats.lastError = tostring(err) end
    end)
end

function M:Apply()
    EnsureBar()
    HookGameBars()
    Layout()
    if not S().enabled then Stop() end
    ShowPlaceholder()
end

function M.Test()
    if not S().enabled then NS.Print("Cast Bar is off: turn it on at the top of its tab first."); return end
    local now = Now()
    Begin({ kind = "cast", name = "Frostbolt", texture = "Interface\\Icons\\Spell_Frost_FrostBolt02",
        start = now, finish = now + 2.5, test = true })
    if C_Timer and C_Timer.After then
        C_Timer.After(2.5, function() if st.cast and st.cast.test then Finish() end end)
    end
end

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
function M.Build(page)
    local function Re() Layout(); ShowPlaceholder() end
    page:Section("Cast Bar", "Classic-style bar for your own casts")
    page:Note("Yellow while casting, green while channelling, a green flash when the cast finishes, red with "
        .. "\"Interrupted\" or \"Failed\" when it doesn't.")
    page:Check("Hide the game's own cast bar", function() return S().hideBlizzard end,
        function(v) S().hideBlizzard = v; HookGameBars() end)
    page:Button("Test: cast a 2.5 second Frostbolt", function() M.Test() end, 260)

    page:Section("Bar", "Size, position and look")
    page:Check("Lock position", function() return S().locked end, function(v) S().locked = v; Re() end)
    page:Note("Unlock to show the bar and drag it anywhere, then lock it again.")
    page:Button("Move it back to the classic spot", function()
        local p = S().point
        p[1], p[2], p[3], p[4] = "BOTTOM", "BOTTOM", 0, 175
        Re()
    end, 260)
    page:Cycle("Border", { { "classic", "Classic (the game's classic art)" }, { "simple", "Simple line" } },
        function() return S().border end, function(v) S().border = v; Re() end)
    page:Slider("Width", 120, 400, 5, function() return S().width end, function(v) S().width = v; Re() end)
    page:Slider("Height", 8, 30, 1, function() return S().height end, function(v) S().height = v; Re() end)
    page:Slider("Text size", 8, 20, 1, function() return S().fontSize end, function(v) S().fontSize = v; Re() end)
    page:Slider("Text up / down (pixels)", -6, 6, 1, function() return S().textNudge end,
        function(v) S().textNudge = v; Re() end)
    page:Check("Show the spell icon", function() return S().showIcon end, function(v) S().showIcon = v end)
    page:Check("Show the seconds left", function() return S().showTimer end, function(v) S().showTimer = v end)
    page:Check("Show the spark", function() return S().showSpark end, function(v) S().showSpark = v end)
    page:Check("Show latency (red zone at the end of the bar)", function() return S().showLatency end,
        function(v) S().showLatency = v end)

    page:Section("Colors", "Classic colours by default")
    local function C(label, key)
        page:Color(label, function() return S().colors[key] end,
            function(r, g, b) local c = S().colors[key]; c[1], c[2], c[3] = r, g, b end)
    end
    C("Casting", "cast")
    C("Channelling", "channel")
    C("Finished", "success")
    C("Interrupted / failed", "failed")
end

function M:Diagnose()
    local st2 = M.stats
    NS.Print(string.format("  casts %d   channels %d   finished %d   interrupted/failed %d   secret reads %d",
        st2.casts, st2.channels, st2.done, st2.failed, st2.secret))
    NS.Print(string.format("  state %s   game bar hidden: %s (%s)   last error %s",
        tostring(st.mode or "idle"), tostring(HideOn()), tostring(st2.hidden), tostring(st2.lastError or "-")))
    if st2.restoreNote then NS.Print("  " .. st2.restoreNote) end
end
