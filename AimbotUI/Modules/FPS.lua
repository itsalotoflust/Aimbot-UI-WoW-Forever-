--[[
  Aimbot UI - FPS / MS counter
  A small, always-on readout at the bottom centre of the screen:
      144 fps  |  23 ms
  Frame rate comes from GetFramerate(); latency from GetNetStats() (home = your
  connection to the realm, world = the game server). Numbers can be coloured by how
  good they are. Unlock the readout to drag it anywhere.
  Nothing here touches Blizzard frames, and secret values are ignored.

  2.32.8: 60 fps watch. When the frame rate sits at 60 (58.5 to 61.5) for 15 seconds while your
  own frame-rate cap is higher, it logs an episode: when it started and ended, how long it
  lasted, the zone, combat, the frame-rate caps (foreground and background), V-Sync, window
  mode, memory, which game settings changed while it lasted, and a guess at the cause (the
  background cap when the rate equals it). Last 30 episodes are kept in the saved settings;
  a short note goes to chat when one starts and ends. Read-only: it never changes a setting.

  2.32.9: frame times. Every frame's length is measured during an episode (average, shortest,
  longest, jitter). Frames all at an even 16.7 ms mean the game is LOCKED to 60 by something
  outside it (Windows' compositor, a 60 Hz monitor, the driver); uneven frames averaging about
  60 mean it is STRUGGLING (the computer is busy). The guess and the log say which.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "FPS / MS",
    group = "QoL",
    desc = "Shows your frame rate and latency at the bottom centre of the screen. Colours show how good "
        .. "the numbers are. Unlock it to drag it anywhere.",
    defaults = {
        enabled      = true,
        showFPS      = true,
        showMS       = true,
        latency      = "both",                -- "home", "world" or "both"
        colorByValue = true,
        color        = { 1.0, 1.0, 1.0, 1 },  -- used when colour-by-value is off
        size         = 14,
        outline      = true,
        background   = false,
        labels       = true,                  -- the words "fps" and "ms"
        locked       = true,
        point        = { "BOTTOM", "BOTTOM", 0, 14 },
        interval     = 0.5,
        watch60      = true,      -- 2.32.8: log the "stuck at 60 fps" episodes
        watchChat    = true,      -- a short note in chat when one starts and ends
        log60        = {},        -- last 30 episodes
    },
}
NS.RegisterModule("fps", M)

local function S() return NS.db.mod.fps end

local frame, text, bg

local function Num(v)
    if type(v) ~= "number" or NS.IsSecret(v) then return nil end
    return v
end

-- Green / yellow / red hex for a value. "Higher is better" for frame rate.
local function Hex(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
local GOOD, OK, BAD = Hex(0.30, 1.00, 0.30), Hex(1.00, 0.85, 0.20), Hex(1.00, 0.35, 0.35)

local function FpsColor(v) if v >= 60 then return GOOD elseif v >= 30 then return OK end return BAD end
local function MsColor(v) if v < 100 then return GOOD elseif v < 200 then return OK end return BAD end

local function Paint(value, colorFn)
    local s = S()
    if s.colorByValue then return colorFn(value) .. value .. "|r" end
    return tostring(value)
end

-- Builds the string shown on screen.
local function Compose(fps, home, world)
    local s = S()
    local parts = {}
    if s.showFPS and fps then
        local f = math.floor(fps + 0.5)
        parts[#parts + 1] = Paint(f, FpsColor) .. (s.labels and " fps" or "")
    end
    if s.showMS then
        local a, b = home and math.floor(home + 0.5), world and math.floor(world + 0.5)
        local str
        if s.latency == "home" and a then
            str = Paint(a, MsColor)
        elseif s.latency == "world" and b then
            str = Paint(b, MsColor)
        elseif s.latency == "both" and a and b then
            str = Paint(a, MsColor) .. " / " .. Paint(b, MsColor)
        elseif a or b then
            str = Paint(a or b, MsColor)
        end
        if str then parts[#parts + 1] = str .. (s.labels and " ms" or "") end
    end
    return table.concat(parts, "   ")
end

local function Update()
    if not frame then return end
    local s = S()
    if not s.enabled then return end
    if not s.locked then return end                     -- the placeholder text is showing
    local fps = GetFramerate and Num(GetFramerate()) or nil
    local home, world
    if GetNetStats then
        local ok, _, _, h, w = pcall(GetNetStats)
        if ok then home, world = Num(h), Num(w) end
    end
    text:SetText(Compose(fps, home, world))
end

local function ApplyPosition()
    if not frame then return end
    local p = S().point
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    if point then
        local p = S().point
        p[1], p[2], p[3], p[4] = point, relPoint, x, y
    end
end

local function ApplyStyle()
    if not frame then return end
    local s = S()
    text:SetFont(STANDARD_TEXT_FONT, s.size, s.outline and "OUTLINE" or "")
    local c = s.color
    text:SetTextColor(c[1], c[2], c[3])
    frame:SetSize(math.max(120, s.size * 11), s.size + 12)
    frame:SetShown(s.enabled)
    frame:EnableMouse(not s.locked)
    bg:SetShown(not s.locked or s.background)
    if s.locked then bg:SetColorTexture(0, 0, 0, 0.35) else bg:SetColorTexture(0.2, 0.6, 1, 0.3) end
    if not s.locked then text:SetText("FPS / MS  (drag me)") end
end

local function Ensure()
    if frame then return end
    frame = CreateFrame("Frame", "AimbotUIFPS", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not S().locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    text:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    ApplyPosition()
    ApplyStyle()

    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < (S().interval or 0.5) then return end
        acc = 0
        local ok, err = pcall(Update)
        if not ok then NS.ReportError("FPS / MS", err) end
    end)
end

function M:Apply()
    Ensure()
    ApplyPosition()
    ApplyStyle()
    Update()
end

function M:Init()
    Ensure()
    Update()
    StartWatch()
end

function M.Build(page)
    page:Section("What to show", "Frame rate and latency")
    page:Check("Show frame rate (FPS)", function() return S().showFPS end,
        function(v) S().showFPS = v; Update() end)
    page:Check("Show latency (MS)", function() return S().showMS end,
        function(v) S().showMS = v; Update() end)
    page:Cycle("Latency to show", {
            { "both", "Home / World" },
            { "home", "Home only" },
            { "world", "World only" },
        },
        function() return S().latency end,
        function(v) S().latency = v; Update() end)
    page:Note("Home is your connection to the realm (chat, mail, auction house). World is your connection to "
        .. "the game server, and is the one that matters for combat.")
    page:Check("Show the words \"fps\" and \"ms\"", function() return S().labels end,
        function(v) S().labels = v; Update() end)

    page:Section("Look", "Size, colour and outline")
    page:Slider("Text size", 8, 40, 1,
        function() return S().size end,
        function(v) S().size = v; ApplyStyle() end)
    page:Check("Colour the numbers by how good they are", function() return S().colorByValue end,
        function(v) S().colorByValue = v; Update() end)
    page:Note("Green: 60+ fps or under 100 ms. Yellow: 30-59 fps or 100-199 ms. Red: below 30 fps or 200+ ms.")
    page:Color("Text color (when not colouring by value)",
        function() return S().color end,
        function(r, g, b) local c = S().color; c[1], c[2], c[3] = r, g, b; ApplyStyle() end)
    page:Check("Text outline", function() return S().outline end,
        function(v) S().outline = v; ApplyStyle() end)
    page:Check("Dark background behind the text", function() return S().background end,
        function(v) S().background = v; ApplyStyle() end)

    page:Section("Position", "Move the counter")
    page:Check("Lock position", function() return S().locked end,
        function(v) S().locked = v; ApplyStyle(); Update() end)
    page:Note("Unlock to drag the counter anywhere. It starts at the bottom centre of the screen.")
    page:Button("Back to bottom centre", function()
        local p = S().point
        p[1], p[2], p[3], p[4] = "BOTTOM", "BOTTOM", 0, 14
        ApplyPosition()
    end)

    page:Section("60 fps watch", "Find out why the frame rate gets stuck at 60")
    page:Check("Log it when the frame rate is stuck at 60", function() return S().watch60 end,
        function(v) S().watch60 = v end)
    page:Check("Tell me in chat when it starts and ends", function() return S().watchChat end,
        function(v) S().watchChat = v end)
    page:Note("When it happens, try clicking into the game window, or alt-tab out and back, and see if it clears. "
        .. "Each episode records the time, zone, frame-rate caps, V-Sync, window mode and what changed. It only reads "
        .. "settings, it never changes them.")
    page:Button("Print the 60 fps log", function() M.Report() end)
    page:Button("Clear the log", function()
        local log = S().log60
        for i = #log, 1, -1 do log[i] = nil end
        NS.Print("FPS watch: log cleared.")
    end)

    page:Section("Speed", "How often the numbers update")
    page:Slider("Update every (seconds)", 0.1, 2, 0.1,
        function() return S().interval end,
        function(v) S().interval = v end,
        function(v) return string.format("%.1f", v) end)
end

----------------------------------------------------------------------
-- 2.32.8: 60 fps watch
----------------------------------------------------------------------
local W = { streak = 0, clear = 0, open = nil }
local NEAR_LO, NEAR_HI = 58.5, 61.5
local START_AFTER, END_AFTER, KEEP = 15, 5, 30

-- every setting that can hold the frame rate at 60 (names differ between clients; missing ones skipped)
local WATCH_CVARS = { "maxFPS", "useMaxFPS", "maxFPSBk", "useMaxFPSBk", "targetFPS", "useTargetFPS",
    "vsync", "gxVSync", "gxMaximize", "gxWindow", "gxRefresh", "gxMonitor", "RenderScale", "graphicsQuality",
    "LowLatencyMode" }
M._t_WATCH_CVARS = WATCH_CVARS

local function CVar(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not get then return nil end
    local ok, v = pcall(get, name)
    if ok and v ~= nil and not NS.IsSecret(v) then return tostring(v) end
    return nil
end

local function Caps()
    local c = {}
    for _, n in ipairs(WATCH_CVARS) do c[n] = CVar(n) end
    return c
end

-- the foreground cap you set yourself (nil = none), and the background cap
local function CapOf(c, valueKey, useKey)
    local v = tonumber(c[valueKey] or "")
    if not v or v <= 0 then return nil end
    if c[useKey] ~= nil and c[useKey] ~= "1" then return nil end   -- capped value present but switched off
    return v
end
M._t_CapOf = CapOf

local function Clock()
    if date then return date("%Y-%m-%d %H:%M:%S") end
    return tostring(GetTime and GetTime() or 0)
end

local function Zone()
    local z = GetRealZoneText and select(2, pcall(GetRealZoneText)) or nil
    if type(z) ~= "string" or NS.IsSecret(z) then return "?" end
    return z
end

local function Snapshot()
    local c = Caps()
    local mem = collectgarbage and math.floor(collectgarbage("count") / 1024 + 0.5) or nil
    local combat = InCombatLockdown and InCombatLockdown() and true or false
    return { at = Clock(), zone = Zone(), combat = combat, caps = c, memMB = mem }
end

-- what is most likely holding it at 60
local function Guess(fps, c, pattern)
    local bk = CapOf(c, "maxFPSBk", "useMaxFPSBk")
    if bk and math.abs(bk - fps) <= 1.5 then
        return "background frame-rate cap (" .. bk .. "): the game thinks it is not the active window"
    end
    if (c.vsync == "1" or c.gxVSync == "1") then
        return "V-Sync is on: the monitor may be running at 60 Hz right now"
    end
    if c.useTargetFPS == "1" then
        return "Target FPS is on (" .. tostring(c.targetFPS) .. ")"
    end
    if pattern == "locked" then
        local windowed = c.gxMaximize == "1" or c.gxWindow == "1"
        return "LOCKED: frames arrive at an even 16.7 ms, so something outside the game is syncing it to 60 Hz"
            .. (windowed and " (windowed / borderless: Windows' compositor follows a 60 Hz monitor or a video playing on another screen)"
                or " (the monitor or driver is running at 60 Hz: refresh-rate switch, G-Sync / FreeSync, driver V-Sync)")
    elseif pattern == "struggling" then
        return "STRUGGLING: frames are uneven and average about 60 fps, so the computer is busy (CPU / GPU load, "
            .. "something running in the background, or heat / power saving)"
    end
    return "no game setting explains it: measuring frame times to tell a lock from a slowdown"
end
M._t_Guess = Guess

-- 2.32.9: frame-time statistics, fed every frame by an OnUpdate on our own frame
local FT = { n = 0, sum = 0, sumsq = 0, min = nil, max = nil }
local function FeedFrame(elapsed)
    if type(elapsed) ~= "number" or elapsed <= 0 or elapsed > 1 then return end
    local ms = elapsed * 1000
    FT.n = FT.n + 1; FT.sum = FT.sum + ms; FT.sumsq = FT.sumsq + ms * ms
    if not FT.min or ms < FT.min then FT.min = ms end
    if not FT.max or ms > FT.max then FT.max = ms end
end
M._t_FeedFrame = FeedFrame

local function TakeStats()
    if FT.n == 0 then return nil end
    local avg = FT.sum / FT.n
    local var = math.max(0, FT.sumsq / FT.n - avg * avg)
    local st = { n = FT.n, avg = avg, jitter = math.sqrt(var), min = FT.min, max = FT.max }
    FT.n, FT.sum, FT.sumsq, FT.min, FT.max = 0, 0, 0, nil, nil
    return st
end
M._t_TakeStats = TakeStats

-- add one second's stats into an episode's running totals
local function Merge(e, st)
    if not st then return end
    local t = e.ft or { n = 0, sum = 0, sumsq = 0, min = nil, max = nil, longFrames = 0 }
    e.ft = t
    t.n = t.n + st.n
    t.sum = t.sum + st.avg * st.n
    t.sumsq = t.sumsq + (st.jitter * st.jitter + st.avg * st.avg) * st.n
    if not t.min or st.min < t.min then t.min = st.min end
    if not t.max or st.max > t.max then t.max = st.max end
    if st.max > 33 then t.longFrames = t.longFrames + 1 end   -- seconds with a hitch (a frame over 33 ms)
end

local function FrameSummary(e)
    local t = e and e.ft
    if not t or t.n == 0 then return nil end
    local avg = t.sum / t.n
    local jitter = math.sqrt(math.max(0, t.sumsq / t.n - avg * avg))
    return { avg = avg, jitter = jitter, min = t.min, max = t.max, longFrames = t.longFrames }
end
M._t_FrameSummary = FrameSummary

-- LOCKED: even frames at about 16.7 ms; STRUGGLING: uneven frames averaging about 60 fps
local function Pattern(sm)
    if not sm then return nil end
    if sm.jitter <= 1.0 and sm.min >= 14.5 and sm.avg >= 16.0 and sm.avg <= 17.4 then return "locked" end
    return "struggling"
end
M._t_Pattern = Pattern

local function Note(msg) if S().watchChat then NS.Print("|cffffd200FPS watch:|r " .. msg) end end

local function Diff(a, b)
    local out = {}
    for k, v in pairs(b or {}) do if a[k] ~= v then out[#out + 1] = k .. " " .. tostring(a[k]) .. " -> " .. tostring(v) end end
    for k, v in pairs(a or {}) do if b[k] == nil and v ~= nil then out[#out + 1] = k .. " " .. tostring(v) .. " -> (gone)" end end
    table.sort(out)
    return out
end

local function OpenEpisode(fps)
    local snap = Snapshot()
    local e = { start = snap, fps = math.floor(fps + 0.5), changed = {}, events = {}, seconds = START_AFTER }
    Merge(e, W.lastStats)
    e.pattern = Pattern(FrameSummary(e))
    e.guess = Guess(fps, snap.caps, e.pattern)
    W.open = e
    Note(string.format("frame rate stuck at %d since %s. Guess: %s. Try clicking into the game window, "
        .. "or alt-tab out and back; I'm logging what clears it.", e.fps, snap.at:sub(12), e.guess))
end

local function CloseEpisode(fps)
    local e = W.open
    if not e then return end
    W.open = nil
    e.finish = Snapshot()
    e.after = math.floor(fps + 0.5)
    e.settingsDiff = Diff(e.start.caps, e.finish.caps)
    local sm = FrameSummary(e)
    if sm then
        e.frames = string.format("avg %.1f ms, shortest %.1f, longest %.1f, jitter %.1f ms, seconds with a hitch %d",
            sm.avg, sm.min, sm.max, sm.jitter, sm.longFrames)
        e.pattern = Pattern(sm)
        e.guess = Guess(e.fps, e.start.caps, e.pattern)
    end
    e.ft = nil
    local log = S().log60
    table.insert(log, 1, e)
    while #log > KEEP do table.remove(log) end
    Note(string.format("back to %d fps after %d min %d s. %s", e.after, math.floor(e.seconds / 60), e.seconds % 60,
        e.pattern and ("It was " .. e.guess) or ""))
end

-- one sample per second (also driven by the tests)
local function Tick()
    local s = S()
    if not s.watch60 then
        if W.open then CloseEpisode(0) end
        W.streak, W.clear = 0, 0
        return
    end
    local fps = GetFramerate and Num(GetFramerate()) or nil
    local st = TakeStats()
    if not fps then return end
    local near = fps >= NEAR_LO and fps <= NEAR_HI
    if near then W.lastStats = st end
    if W.open then
        W.open.seconds = W.open.seconds + 1
        if near then Merge(W.open, st) end
        if near then W.clear = 0 else
            W.clear = W.clear + 1
            if W.clear >= END_AFTER then CloseEpisode(fps); W.clear, W.streak = 0, 0 end
        end
        return
    end
    -- a cap you set yourself at about 60 is not an episode
    local fg = CapOf(Caps(), "maxFPS", "useMaxFPS")
    if near and not (fg and fg <= NEAR_HI) then
        W.streak = W.streak + 1
        if W.streak >= START_AFTER then OpenEpisode(fps); W.streak, W.clear = 0, 0 end
    else
        W.streak = 0
    end
end
M._t_Tick = Tick
M._t_W = W

local function OnCVar(_, name, value)
    local e = W.open
    if not e or type(name) ~= "string" or #e.changed >= 20 then return end
    e.changed[#e.changed + 1] = name .. "=" .. tostring(value)
end

local function OnMark(event)
    local e = W.open
    if e and #e.events < 20 then e.events[#e.events + 1] = event .. " " .. Clock():sub(12) end
end
M._t_OnCVar, M._t_OnMark = OnCVar, OnMark

local watchStarted = false
local feeder
local function StartWatch()
    if watchStarted then return end
    watchStarted = true
    -- our own invisible frame, only to measure frame lengths (cheap: a few additions per frame)
    feeder = CreateFrame("Frame")
    if feeder and feeder.SetScript then
        feeder:SetScript("OnUpdate", function(_, elapsed) if S().watch60 then FeedFrame(elapsed) end end)
    end
    NS.On("CVAR_UPDATE", OnCVar)
    for _, ev in ipairs({ "DISPLAY_SIZE_CHANGED", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CINEMATIC_START", "CINEMATIC_STOP" }) do
        NS.On(ev, OnMark)
    end
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(1, function()
            local ok, err = pcall(Tick)
            if not ok then NS.ReportError("FPS watch", err) end
        end)
    end
end
M._t_StartWatch = StartWatch

local function CapsLine(c)
    local t = {}
    for _, n in ipairs(WATCH_CVARS) do if c[n] ~= nil then t[#t + 1] = n .. "=" .. c[n] end end
    return table.concat(t, " ")
end

function M.Report()
    local log = S().log60
    if #log == 0 then NS.Print("FPS watch: no 60 fps episodes logged yet."); return end
    NS.Print(string.format("FPS watch: %d episode(s), newest first:", #log))
    for i, e in ipairs(log) do
        NS.Print(string.format("%d) %s  %d min %d s at %d fps (then %s), %s%s", i, e.start.at, math.floor(e.seconds / 60),
            e.seconds % 60, e.fps, tostring(e.after), e.start.zone, e.start.combat and ", in combat" or ""))
        NS.Print("   guess: " .. tostring(e.guess))
        if e.frames then NS.Print("   frames: " .. e.frames) end
        NS.Print("   settings: " .. CapsLine(e.start.caps))
        if e.settingsDiff and #e.settingsDiff > 0 then NS.Print("   changed: " .. table.concat(e.settingsDiff, ", ")) end
        if #e.changed > 0 then NS.Print("   settings changed during it: " .. table.concat(e.changed, ", ")) end
        if #e.events > 0 then NS.Print("   events: " .. table.concat(e.events, ", ")) end
        if e.start.memMB then NS.Print("   addon memory: " .. e.start.memMB .. " MB") end
        if i >= 5 then NS.Print("   (older ones are in the saved settings)"); break end
    end
end

function M:Diagnose()
    local log = S().log60
    local c = Caps()
    NS.Print(string.format("  60 fps watch %s   episodes logged %d   happening now %s",
        tostring(S().watch60), #log, W.open and ("yes, since " .. W.open.start.at) or "no"))
    NS.Print("  settings now: " .. CapsLine(c))
    if log[1] then NS.Print("  last: " .. log[1].start.at .. "  guess: " .. tostring(log[1].guess)) end
end

M._t = { Update = Update, Compose = Compose, Frame = function() return frame end, Text = function() return text end }

-- Live preview at the top of this tab (Sharp window style). Drawn on our own frames only.
function M.LivePreview(stage)
    local bg = stage:CreateTexture(nil, "BACKGROUND")
    local fs = stage:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", stage, "CENTER", 0, -4)
    bg:SetPoint("TOPLEFT", fs, "TOPLEFT", -6, 4)
    bg:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 6, -4)
    bg:SetColorTexture(0, 0, 0, 0.5)
    return function()
        local s = S()
        local size = math.max(9, math.min(tonumber(s.size) or 14, 32))
        fs:SetFont(STANDARD_TEXT_FONT, size, s.outline and "OUTLINE" or "")
        local c = s.color or { 1, 1, 1, 1 }
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        local text = Compose(62, 48, 131)
        if text == "" then text = "(nothing to show)" end
        fs:SetText(text)
        bg:SetShown(s.background and true or false)
    end
end
