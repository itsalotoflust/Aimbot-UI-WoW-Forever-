--[[
  Aimbot UI - Queue Timer
  When a dungeon, battleground or arena queue pops, shows a bar counting down the seconds you
  have left to accept, plays a sound (through the Master channel, so you hear it even with
  game sounds turned down) and can flash the game's taskbar icon.

  Battlegrounds and arenas report the real time left (GetBattlefieldPortExpiration). The
  dungeon finder popup doesn't, so it counts down from the usual 40 seconds.
  Only our own frame is created; no Blizzard frame is touched.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Queue Timer",
    group = "QoL",
    desc = "A countdown bar and sound when a dungeon, battleground or arena queue pops, so you never "
        .. "miss the accept window.",
    defaults = {
        enabled   = true,
        sound     = true,          -- sound when the queue pops
        tick      = true,          -- a short tick every second in the last few seconds
        warnAt    = 10,            -- seconds left when the ticks start and the bar turns red
        flash     = true,          -- flash the game's taskbar icon
        width     = 260,
        height    = 22,
        locked    = true,
        point     = { "TOP", "TOP", 0, -140 },
    },
}
NS.RegisterModule("queuetimer", M)

local function S() return NS.db.mod.queuetimer end

local LFG_SECONDS = 40
local bar, barText, barFill, barBG
local timers = {}         -- key -> { label, expires, warned }
M.stats = { pops = 0, last = nil }

----------------------------------------------------------------------
-- Sounds
----------------------------------------------------------------------
local function Play(kitName, fallback)
    local id = (SOUNDKIT and SOUNDKIT[kitName]) or fallback
    if id and PlaySound then pcall(PlaySound, id, "Master") end
end

local function PopAlert()
    local s = S()
    if s.sound then Play("READY_CHECK", 8960) end
    if s.flash and FlashClientIcon then pcall(FlashClientIcon) end
end

----------------------------------------------------------------------
-- Bar
----------------------------------------------------------------------
local function SavePosition()
    local point, _, relPoint, x, y = bar:GetPoint()
    if point then
        local p = S().point
        p[1], p[2], p[3], p[4] = point, relPoint, x, y
    end
end

local function ApplyLayout()
    if not bar then return end
    local s = S()
    local p = s.point
    bar:ClearAllPoints()
    bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    bar:SetSize(s.width, s.height)
    barText:SetFont(STANDARD_TEXT_FONT, math.max(10, math.floor(s.height * 0.6)), "OUTLINE")
    bar:EnableMouse(not s.locked)
end

local function EnsureBar()
    if bar then return bar end
    bar = CreateFrame("Frame", "AimbotUIQueueTimer", UIParent)
    bar:SetFrameStrata("DIALOG")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not S().locked then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)

    barBG = bar:CreateTexture(nil, "BACKGROUND")
    barBG:SetAllPoints()
    barBG:SetColorTexture(0, 0, 0, 0.65)
    barFill = bar:CreateTexture(nil, "ARTWORK")
    barFill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    barFill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
    barFill:SetColorTexture(0.2, 0.8, 0.3, 0.9)
    barText = bar:CreateFontString(nil, "OVERLAY")
    barText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    barText:SetPoint("CENTER")

    local acc = 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.05 then return end
        acc = 0
        local ok, err = pcall(M.Update)
        if not ok then NS.ReportError("Queue Timer", err) end
    end)
    bar:Hide()
    ApplyLayout()
    return bar
end

-- The timer that runs out soonest is the one shown.
local function Soonest()
    local best
    for _, t in pairs(timers) do
        if not best or t.expires < best.expires then best = t end
    end
    return best
end

function M.Update()
    local t = Soonest()
    local now = GetTime()
    if not t then
        if bar and S().locked then bar:Hide() end
        if bar and not S().locked then
            barText:SetText("Queue timer (drag me)")
            barFill:SetWidth(math.max(1, S().width - 2))
            barFill:SetColorTexture(0.2, 0.6, 1, 0.6)
        end
        return
    end
    local left = t.expires - now
    if left <= 0 then
        for k, v in pairs(timers) do if v == t then timers[k] = nil end end
        return M.Update()
    end
    local s = S()
    local frac = math.min(1, left / t.total)
    barFill:SetWidth(math.max(1, (s.width - 2) * frac))
    if left <= s.warnAt then
        barFill:SetColorTexture(0.9, 0.15, 0.15, 0.95)
    elseif frac < 0.5 then
        barFill:SetColorTexture(0.95, 0.75, 0.1, 0.95)
    else
        barFill:SetColorTexture(0.2, 0.8, 0.3, 0.9)
    end
    barText:SetText(string.format("%s  %d", t.label, math.ceil(left)))
    -- one tick per whole second in the warning window
    local sec = math.ceil(left)
    if s.tick and left <= s.warnAt and t.lastTick ~= sec then
        t.lastTick = sec
        Play("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
    end
end

local function Start(key, label, seconds)
    if not S().enabled or not seconds or seconds <= 0 then return end
    local old = timers[key]
    local expires = GetTime() + seconds
    -- the same pop reported again (status events repeat): keep the original, don't re-alert
    if old and math.abs(old.expires - expires) < 2 then return end
    timers[key] = { label = label, expires = expires, total = math.max(seconds, 1) }
    M.stats.pops = M.stats.pops + 1
    M.stats.last = label .. " (" .. math.floor(seconds) .. " s)"
    EnsureBar():Show()
    if not old then PopAlert() end
    M.Update()
end

local function Stop(key)
    timers[key] = nil
    if bar then M.Update() end
end

----------------------------------------------------------------------
-- Queue events
----------------------------------------------------------------------
local function ScanBattlefields()
    local max = (GetMaxBattlefieldID and GetMaxBattlefieldID()) or 3
    local seen = {}
    for i = 1, max do
        local ok, status, mapName = pcall(GetBattlefieldStatus, i)
        if ok and status == "confirm" and not NS.IsSecret(status) then
            local okE, exp = pcall(GetBattlefieldPortExpiration, i)
            local secs = okE and type(exp) == "number" and not NS.IsSecret(exp) and exp or nil
            if secs and secs > 1000 then secs = secs / 1000 end     -- some clients report milliseconds
            local label = (type(mapName) == "string" and not NS.IsSecret(mapName) and mapName ~= "") and mapName
                or "Battleground"
            Start("bg" .. i, label .. " ready", secs or 90)
            seen["bg" .. i] = true
        end
    end
    for k in pairs(timers) do
        if k:find("^bg") and not seen[k] then Stop(k) end
    end
end

M._t = { Start = Start, Stop = Stop, ScanBattlefields = ScanBattlefields, timers = timers }

function M:Apply()
    if bar then ApplyLayout() end
    local s = S()
    if not s.enabled then
        for k in pairs(timers) do timers[k] = nil end
        if bar then bar:Hide() end
        return
    end
    if not s.locked then EnsureBar():Show(); M.Update()
    elseif bar and not Soonest() then bar:Hide() end
end

function M:Init()
    NS.On("LFG_PROPOSAL_SHOW", function() Start("lfg", "Dungeon ready", LFG_SECONDS) end)
    for _, ev in ipairs({ "LFG_PROPOSAL_FAILED", "LFG_PROPOSAL_SUCCEEDED", "LFG_PROPOSAL_DONE" }) do
        NS.On(ev, function() Stop("lfg") end)
    end
    NS.On("UPDATE_BATTLEFIELD_STATUS", function() if S().enabled then ScanBattlefields() end end)
    NS.On("PLAYER_ENTERING_WORLD", function() for k in pairs(timers) do timers[k] = nil end
        if bar then M.Update() end end)
end

function M:Diagnose()
    local s = S()
    local n = 0
    for _ in pairs(timers) do n = n + 1 end
    NS.Print(string.format("  queue pops seen: %d   last: %s   running timers: %d   sound %s, ticks %s, flash %s",
        M.stats.pops, tostring(M.stats.last or "none"), n, tostring(s.sound), tostring(s.tick), tostring(s.flash)))
end

function M.Build(page)
    page:Section("When a queue pops", "Countdown, sound and taskbar flash")
    page:Check("Play a sound when a queue pops", function() return S().sound end,
        function(v) S().sound = v end)
    page:Check("Tick every second near the end", function() return S().tick end,
        function(v) S().tick = v end)
    page:Slider("Warning starts at (seconds left)", 3, 30, 1,
        function() return S().warnAt end, function(v) S().warnAt = v end)
    page:Check("Flash the game's taskbar icon", function() return S().flash end,
        function(v) S().flash = v end)
    page:Note("Sounds play through the Master channel, so you hear them even with game sounds turned down. "
        .. "Battlegrounds and arenas show the real time left; the dungeon finder counts down from 40 seconds.")
    page:Button("Test (15 seconds)", function()
        if not S().enabled then NS.Print("Queue Timer is off: turn it on at the top of this tab first."); return end
        timers.test = nil
        Start("test", "Test queue", 15)
    end)

    page:Section("Bar", "Size and position")
    page:Slider("Width", 120, 500, 10, function() return S().width end,
        function(v) S().width = v; ApplyLayout() end)
    page:Slider("Height", 14, 40, 1, function() return S().height end,
        function(v) S().height = v; ApplyLayout() end)
    page:Check("Lock position", function() return S().locked end,
        function(v) S().locked = v; NS.ApplyModule("queuetimer") end)
    page:Note("Unlock to show the bar and drag it anywhere, then lock it again.")
end
