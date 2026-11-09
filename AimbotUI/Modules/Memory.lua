--[[
  Aimbot UI - Memory Cleaner module ("Clear Cache")

  What it can do:
    * Run a full garbage collection (frees memory that addons have finished with but
      Lua has not collected yet - this is what most "memory leak" complaints really are).
    * Do that automatically: every N minutes, when a loading screen ends, and after combat
      if memory grew a lot. It never runs in combat.
    * Watch for REAL leaks: after a clean, any addon whose memory is still far above where
      it started is holding on to it. It tells you which addon, so you can reload or update it.

  What it can not do:
    * Free memory an addon still references. That is a genuine leak inside that addon and
      only /reload (or fixing the addon) gets rid of it.
    * Delete the game's Cache folder on disk (the game has to be closed for that).
]]

local ADDON_NAME, NS = ...

local M = {
    name  = "Memory Cleaner",
    group = "QoL",
    desc  = "Clear Cache: frees leftover addon memory and tells you which addon is really leaking.",
    defaults = {
        enabled      = true,
        autoMinutes  = 30,      -- 0 = no timed cleaning
        onLoad       = true,    -- clean when a loading screen ends
        afterCombat  = false,   -- clean after combat when memory grew a lot
        growthMB     = 150,     -- ...by at least this much since the last clean
        cfgVersion   = nil,     -- settings migration marker (set in Init)
        leakWatch    = true,    -- warn about addons that stay big after a clean
        leakMB       = 25,      -- ...by at least this much since the baseline
    },
}
NS.RegisterModule("memory", M)

local function S() return NS.db.mod.memory end

M.stats = { runs = 0, freedKB = 0, lastFreedKB = 0, lastTime = nil, lastMs = nil, lastSeconds = nil }

local function Took(st)
    if st.lastMs then return string.format(" (took %.0f ms)", st.lastMs) end
    if st.lastSeconds then return string.format(" (spread over %.1f s, no stutter)", st.lastSeconds) end
    return ""
end

----------------------------------------------------------------------
-- API wrappers (names moved into C_AddOns in newer clients)
----------------------------------------------------------------------
local function NumAddOns()
    local f = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    return f and f() or 0
end

local function AddOnName(i)
    local f = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not f then return tostring(i) end
    local ok, a = pcall(f, i)
    if not ok then return tostring(i) end
    if type(a) == "table" then return a.name or a.title or tostring(i) end
    return a or tostring(i)
end

local function UpdateUsage()
    local f = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
    if f then pcall(f) end
end

local function UsageOf(i)
    local f = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if not f then return nil end
    local ok, v = pcall(f, i)
    if ok and type(v) == "number" then return v end
end

local function TotalKB()
    if type(collectgarbage) ~= "function" then return nil end
    local ok, v = pcall(collectgarbage, "count")
    if ok and type(v) == "number" then return v end
end

local function Fmt(kb)
    if not kb then return "?" end
    local sign = kb < 0 and "-" or ""
    kb = math.abs(kb)
    if kb >= 1024 then return string.format("%s%.1f MB", sign, kb / 1024) end
    return string.format("%s%d KB", sign, math.floor(kb + 0.5))
end

local function Idle()
    if InCombatLockdown and InCombatLockdown() then return false end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return false end
    return true
end

----------------------------------------------------------------------
-- Cleaning
----------------------------------------------------------------------
local lastCleanKB          -- total memory right after the last clean

local function Collect()
    if type(collectgarbage) ~= "function" then return nil end
    local before = TotalKB()
    local t0 = debugprofilestop and debugprofilestop()
    pcall(collectgarbage, "collect")
    pcall(collectgarbage, "collect")      -- second pass catches things freed by finalizers
    local after = TotalKB()
    if not (before and after) then return nil end
    local freed = math.max(0, before - after)
    local st = M.stats
    st.runs = st.runs + 1
    st.freedKB = st.freedKB + freed
    st.lastFreedKB = freed
    st.lastTime = GetTime()
    st.lastMs = t0 and (debugprofilestop() - t0) or nil
    st.lastSeconds = nil
    lastCleanKB = after
    return freed, before, after
end

-- Automatic cleans are done in small slices spread over a few seconds instead of one big
-- collection, so they never cause a visible stutter. Only the button / /aimbot clean does the
-- full, instant collection (you asked for it, so a short freeze is expected).
local gentleRunning = false

local function GentleCollect(onDone)
    if gentleRunning or type(collectgarbage) ~= "function" then return end
    local before = TotalKB()
    local t0 = GetTime()
    local slices = 0
    gentleRunning = true

    local function Finish(complete)
        gentleRunning = false
        local after = TotalKB()
        if before and after then
            local st = M.stats
            st.runs = st.runs + 1
            local freed = math.max(0, before - after)
            st.freedKB = st.freedKB + freed
            st.lastFreedKB = freed
            st.lastTime = GetTime()
            st.lastMs = nil
            st.lastSeconds = GetTime() - t0
            lastCleanKB = after
        end
        if complete and onDone then onDone() end
        if M.Refresh then M.Refresh() end
    end

    local function Slice()
        if not gentleRunning then return end
        if not Idle() then Finish(false); return end         -- combat started: stop at once
        local ok, finished = pcall(collectgarbage, "step", 400)
        slices = slices + 1
        if not ok then Finish(false); return end
        if finished or slices >= 500 then Finish(true); return end
        C_Timer.After(0.05, Slice)
    end
    Slice()
end

----------------------------------------------------------------------
-- Per-addon scan and leak detection
----------------------------------------------------------------------
local scan = {}            -- sorted list of { name, kb }
local baseline            -- name -> kb at the time the baseline was set
local warned = {}         -- name -> true once we have warned about it

local function Scan()
    UpdateUsage()
    wipe(scan)
    for i = 1, NumAddOns() do
        local kb = UsageOf(i)
        if kb and kb > 0 then scan[#scan + 1] = { name = AddOnName(i), kb = kb } end
    end
    table.sort(scan, function(a, b) return a.kb > b.kb end)
end

local function SetBaseline()
    baseline = {}
    for _, e in ipairs(scan) do baseline[e.name] = e.kb end
    wipe(warned)
end

local function Growth(e)
    if not baseline then return nil end
    return e.kb - (baseline[e.name] or 0)
end

local function CheckLeaks()
    local s = S()
    if not (s.leakWatch and baseline) then return end
    local limit = s.leakMB * 1024
    for _, e in ipairs(scan) do
        local g = Growth(e)
        if g and g >= limit and not warned[e.name] then
            warned[e.name] = true
            NS.Print(string.format("|cffffa040%s|r is using %s more memory than at the start, and cleaning does not free it. "
                .. "That is a leak inside that addon. Type /reload to reset it.", e.name, Fmt(g)))
        end
    end
end

----------------------------------------------------------------------
-- Public actions
----------------------------------------------------------------------
function M:CleanNow(report)
    local freed, before, after = Collect()
    if report then
        if freed then
            NS.Print(string.format("memory cleaned: %s -> %s  (freed %s)", Fmt(before), Fmt(after), Fmt(freed)))
        else
            NS.Print("this client does not let addons run a garbage collection.")
        end
    end
    if M.Refresh then M.Refresh() end
    return freed
end

M._gentle = GentleCollect      -- exposed for the test harness

-- Never more than one automatic clean every few minutes, however many triggers fire.
local MIN_GAP = 300
local lastAutoAt = -1e9
local lastCombatEnd = -1e9

local function AutoClean()
    local now = GetTime()
    if now - lastAutoAt < MIN_GAP then return end
    lastAutoAt = now
    GentleCollect()
end

-- Reading every addon's memory is the expensive part (the game walks all addons), so it
-- runs rarely, only when you are idle, and never right after combat.
local function LeakScan(firstBaseline)
    GentleCollect(function()
        if not Idle() then return end
        Scan()
        if firstBaseline or not baseline then SetBaseline() else CheckLeaks() end
        if M.Refresh then M.Refresh() end
    end)
end

----------------------------------------------------------------------
-- Scheduler
----------------------------------------------------------------------
local nextAuto                 -- GetTime() when the next timed clean is due
local nextLeakScan
local needBaseline = true
local baselineAt                -- GetTime() after which the first baseline may be taken

local function ScheduleNext()
    local m = S().autoMinutes or 0
    nextAuto = (m > 0) and (GetTime() + m * 60) or nil
end

local function Tick()
    local s = S()
    if not s.enabled or not Idle() then return end
    local now = GetTime()

    if needBaseline and baselineAt and now >= baselineAt and now - lastCombatEnd > 20 then
        needBaseline = false
        nextLeakScan = now + 20 * 60
        if s.leakWatch then LeakScan(true) end
        return
    end

    if nextAuto and now >= nextAuto then
        AutoClean()
        ScheduleNext()
    end

    if s.leakWatch and nextLeakScan and now >= nextLeakScan and now - lastCombatEnd > 20 then
        nextLeakScan = now + 20 * 60
        LeakScan(false)
    end
end

local function AfterCombat()
    lastCombatEnd = GetTime()
    local s = S()
    if not (s.enabled and s.afterCombat) then return end
    C_Timer.After(5, function()
        if not Idle() then return end
        local total = TotalKB()
        if total and lastCleanKB and (total - lastCleanKB) >= S().growthMB * 1024 then
            AutoClean()
        end
    end)
end

local function OnLoadingDone(_, isLogin, isReload)
    local s = S()
    if not s.enabled then return end
    if isLogin or isReload then
        baselineAt = GetTime() + 90      -- let every addon finish loading first
        needBaseline = true
    end
    if s.onLoad then
        C_Timer.After(4, function()
            if S().enabled and Idle() then AutoClean() end
        end)
    end
end

function M:Apply()
    ScheduleNext()
    if M.Refresh then M.Refresh() end
end

function M:Init()
    -- 2.4.1: the first version cleaned after every fight and could stutter on busy setups.
    local s = S()
    if s.cfgVersion ~= 2 then
        s.cfgVersion = 2
        s.afterCombat = false
        if (s.growthMB or 0) < 150 then s.growthMB = 150 end
        if (s.autoMinutes or 0) > 0 and s.autoMinutes < 30 then s.autoMinutes = 30 end
    end
    lastCleanKB = TotalKB()
    baselineAt = GetTime() + 120
    ScheduleNext()
    NS.On("PLAYER_ENTERING_WORLD", OnLoadingDone)
    NS.On("PLAYER_REGEN_ENABLED", AfterCombat)
    C_Timer.NewTicker(30, function()
        local ok, err = pcall(Tick)
        if not ok then NS.ReportError("memory tick", err) end
    end)
end

function M:Diagnose()
    NS.Print("  collectgarbage available: " .. tostring(type(collectgarbage) == "function"))
    NS.Print("  addon memory API: " .. tostring(((C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage) ~= nil))
    NS.Print("  Lua memory in use: " .. Fmt(TotalKB()))
    local st = M.stats
    NS.Print(string.format("  cleans this session: %d, freed %s in total, last freed %s%s",
        st.runs, Fmt(st.freedKB), Fmt(st.lastFreedKB), Took(st)))
    NS.Print("  baseline set: " .. tostring(baseline ~= nil) .. "   addons scanned: " .. #scan)
end

----------------------------------------------------------------------
-- Settings page
----------------------------------------------------------------------
local INTERVALS = {
    { 0, "Off" }, { 5, "Every 5 minutes" }, { 10, "Every 10 minutes" },
    { 15, "Every 15 minutes" }, { 30, "Every 30 minutes" }, { 60, "Every hour" },
}
local MAX_ROWS = 15

function M.Build(page)
    page:Section("Memory right now", "Current use and a Clean memory now button")
    local info = page:Note("")
    local info2 = page:Note("")
    page:Button("Clean memory now", function() M:CleanNow(true) end, 220)
    page:Note("This runs a full garbage collection. It frees memory addons have finished with. "
        .. "It may freeze the game for a moment, so do it out of combat.")

    page:Section("Clean automatically", "Timed cleaning, after loading screens and after combat")
    page:Cycle("Timed clean", INTERVALS,
        function() return S().autoMinutes end,
        function(v) S().autoMinutes = v; ScheduleNext() end)
    page:Check("Clean when a loading screen ends", function() return S().onLoad end,
        function(v) S().onLoad = v end)
    page:Check("Clean after combat if memory grew a lot", function() return S().afterCombat end,
        function(v) S().afterCombat = v end)
    page:Slider("...grew by at least", 50, 500, 10,
        function() return S().growthMB end,
        function(v) S().growthMB = v end,
        function(v) return string.format("%d MB", math.floor(v + 0.5)) end)
    page:Note("Automatic cleans are spread over a few seconds in tiny slices so they don't cause stutter, they stop "
        .. "the moment combat starts, and there is never more than one every 5 minutes. "
        .. "Only the \"Clean memory now\" button does a full instant clean. Turn the whole module off with the switch at the top if you don't want it.")

    page:Section("Leak watch", "Find addons that keep growing after a clean")
    page:Check("Warn me when an addon keeps growing after a clean", function() return S().leakWatch end,
        function(v) S().leakWatch = v end)
    page:Slider("Warn when it is this much bigger", 5, 100, 5,
        function() return S().leakMB end,
        function(v) S().leakMB = v end,
        function(v) return string.format("%d MB", math.floor(v + 0.5)) end)

    page:Note("The addon scan is the heavy part (the game has to measure every addon), so it runs only on this button "
        .. "and about every 20 minutes while you are idle.")
    page:Button("Scan addon memory", function()
        Collect()
        Scan()
        if not baseline then SetBaseline() end
        CheckLeaks()
        M.Refresh()
    end, 220)
    page:Button("Use the current numbers as the new starting point", function()
        Collect()
        Scan()
        SetBaseline()
        M.Refresh()
    end, 360)

    local box = page:Container()
    local head = box:CreateFontString(nil, "OVERLAY")
    head:SetFont(STANDARD_TEXT_FONT, 11, "")
    head:SetTextColor(0.55, 0.55, 0.60)
    head:SetPoint("TOPLEFT", box, "TOPLEFT", 4, 0)
    head:SetText("Addon")
    local headMem = box:CreateFontString(nil, "OVERLAY")
    headMem:SetFont(STANDARD_TEXT_FONT, 11, "")
    headMem:SetTextColor(0.55, 0.55, 0.60)
    headMem:SetPoint("TOPRIGHT", box, "TOPRIGHT", -120, 0)
    headMem:SetWidth(90); headMem:SetJustifyH("RIGHT")
    headMem:SetText("Memory")
    local headGrow = box:CreateFontString(nil, "OVERLAY")
    headGrow:SetFont(STANDARD_TEXT_FONT, 11, "")
    headGrow:SetTextColor(0.55, 0.55, 0.60)
    headGrow:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, 0)
    headGrow:SetWidth(110); headGrow:SetJustifyH("RIGHT")
    headGrow:SetText("Since start")

    local rows = {}
    for i = 1, MAX_ROWS do
        local y = -(i * 16)
        local n = box:CreateFontString(nil, "OVERLAY")
        n:SetFont(STANDARD_TEXT_FONT, 12, "")
        n:SetPoint("TOPLEFT", box, "TOPLEFT", 4, y)
        n:SetPoint("TOPRIGHT", box, "TOPRIGHT", -220, y)
        n:SetJustifyH("LEFT"); n:SetWordWrap(false)
        local m = box:CreateFontString(nil, "OVERLAY")
        m:SetFont(STANDARD_TEXT_FONT, 12, "")
        m:SetPoint("TOPRIGHT", box, "TOPRIGHT", -120, y)
        m:SetWidth(90); m:SetJustifyH("RIGHT")
        local g = box:CreateFontString(nil, "OVERLAY")
        g:SetFont(STANDARD_TEXT_FONT, 12, "")
        g:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, y)
        g:SetWidth(110); g:SetJustifyH("RIGHT")
        rows[i] = { n, m, g }
    end
    local empty = box:CreateFontString(nil, "OVERLAY")
    empty:SetFont(STANDARD_TEXT_FONT, 12, "")
    empty:SetTextColor(0.62, 0.62, 0.67)
    empty:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -20)
    empty:SetText("Press \"Scan addon memory\" to list the biggest addons.")
    box:SetContentHeight((MAX_ROWS + 1) * 16 + 6)

    page:Note("\"Since start\" compares each addon with the numbers taken about 90 seconds after you logged in "
        .. "(after a clean). An addon that is far above its starting size even after a clean is leaking.")
    page:Button("Reload UI (resets all addon memory)", function() ReloadUI() end, 300)

    page:Section("What this can and can't do", "Honest limits of cleaning")
    page:Note("Cleaning frees memory that nothing uses any more. It can not free memory an addon is still holding on to - "
        .. "that is a real leak inside the addon, and only a /reload or an addon update fixes it.")
    page:Note("The game's Cache folder on disk can't be deleted from inside the game. Close WoW and delete the Cache folder "
        .. "in the WoW install folder if you want that.")
    page:Note("Quick command:  /aimbot clean")

    function M.Refresh()
        local s = S()
        local total = TotalKB()
        local st = M.stats
        info:SetText("All addons together are using " .. Fmt(total) .. " of Lua memory.")
        local ago = ""
        if st.lastTime then
            local secs = math.floor(GetTime() - st.lastTime)
            ago = secs < 90 and (secs .. " seconds ago") or (math.floor(secs / 60) .. " minutes ago")
        end
        if st.runs > 0 then
            info2:SetText(string.format("Last clean: freed %s %s%s.  This session: %d cleans, %s freed.",
                Fmt(st.lastFreedKB), ago, Took(st), st.runs, Fmt(st.freedKB)))
        else
            info2:SetText("Nothing cleaned yet this session.")
        end

        empty:SetShown(#scan == 0)
        local limit = s.leakMB * 1024
        for i = 1, MAX_ROWS do
            local r, e = rows[i], scan[i]
            if e then
                local g = Growth(e)
                r[1]:SetText(e.name)
                r[2]:SetText(Fmt(e.kb))
                if g then
                    r[3]:SetText((g >= 0 and "+" or "") .. Fmt(g))
                    if g >= limit then
                        r[1]:SetTextColor(1, 0.63, 0.25); r[3]:SetTextColor(1, 0.63, 0.25)
                    else
                        r[1]:SetTextColor(0.9, 0.9, 0.92); r[3]:SetTextColor(0.62, 0.62, 0.67)
                    end
                else
                    r[3]:SetText("-")
                    r[1]:SetTextColor(0.9, 0.9, 0.92); r[3]:SetTextColor(0.62, 0.62, 0.67)
                end
                r[2]:SetTextColor(0.9, 0.9, 0.92)
            else
                r[1]:SetText(""); r[2]:SetText(""); r[3]:SetText("")
            end
        end
        page:Reflow()
    end
    table.insert(page.refreshers, M.Refresh)
    M.Refresh()

    -- keep the live number fresh while the tab is on screen
    C_Timer.NewTicker(2, function()
        if box:IsVisible() then
            local total = TotalKB()
            if total then info:SetText("All addons together are using " .. Fmt(total) .. " of Lua memory.") end
        end
    end)
end
