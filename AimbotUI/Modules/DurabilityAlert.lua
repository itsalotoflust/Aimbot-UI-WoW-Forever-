--[[
  Aimbot UI - Durability Alert
  When your gear's durability drops below a set percent (40% by default), a pulsing
  "Repair your gear" message stays in the middle of your screen until you repair. Only you see
  it. Size, color and position can be changed, and the text can be dragged anywhere.

  Reads GetInventoryItemDurability for each equipped slot. Only our own frame is created;
  no Blizzard frame is touched.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Durability Alert",
    group = "QoL",
    desc = "A pulsing message in the middle of your screen while your gear needs repairing.",
    defaults = {
        enabled   = true,
        threshold = 40,             -- percent
        mode      = "lowest",       -- "lowest" item or "average" of all items
        pulse     = true,
        sound     = true,           -- sound when it first drops below
        hideCombat = false,         -- hide while you are in combat
        size      = 28,
        color     = { 1, 0.55, 0.1, 1 },
        locked    = true,
        point     = { "CENTER", "CENTER", 0, 150 },
    },
}
NS.RegisterModule("durability", M)

local function S() return NS.db.mod.durability end
local IsSecret = NS.IsSecret

local alert
local testUntil = 0          -- the Test button's message is left alone until then
local wasLow = false
M.stats = { pct = nil, lowest = nil, average = nil, broken = 0, items = 0, secret = 0 }

local function Alert()
    if not alert then alert = NS.CreateAlertText("AimbotUIDurabilityAlert", S, "Repair your gear: 35%") end
    return alert
end

-- Returns lowest percent, average percent, number of broken items, number of items with durability.
local function Read()
    local lowest, sumCur, sumMax, broken, items = nil, 0, 0, 0, 0
    for slot = 1, 19 do
        local ok, cur, max = pcall(GetInventoryItemDurability, slot)
        if ok and (IsSecret(cur) or IsSecret(max)) then
            M.stats.secret = M.stats.secret + 1
        elseif ok and type(cur) == "number" and type(max) == "number" and max > 0 then
            items = items + 1
            local pct = cur / max * 100
            if not lowest or pct < lowest then lowest = pct end
            sumCur, sumMax = sumCur + cur, sumMax + max
            if cur == 0 then broken = broken + 1 end
        end
    end
    local average = sumMax > 0 and (sumCur / sumMax * 100) or nil
    return lowest, average, broken, items
end

local function Update()
    if GetTime() < testUntil then return end
    local s = S()
    if not s.enabled then
        wasLow = false
        if alert then alert:Hide() end
        return
    end
    local lowest, average, broken, items = Read()
    M.stats.lowest, M.stats.average, M.stats.broken, M.stats.items = lowest, average, broken, items
    local pct = (s.mode == "average") and average or lowest
    M.stats.pct = pct
    local low = pct ~= nil and pct < s.threshold
    if not low then
        wasLow = false
        if alert and alert:IsShowing() then alert:Hide() end
        return
    end
    if not wasLow and s.sound then
        local id = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
        pcall(PlaySound, id, "Master")
    end
    wasLow = true
    if s.hideCombat and InCombatLockdown() then
        if alert and alert:IsShowing() then alert:Hide() end
        return
    end
    local msg = string.format("Repair your gear: %d%%", math.floor(pct + 0.5))
    if broken > 0 then msg = msg .. string.format("  (%d broken)", broken) end
    Alert():Show(msg, true, s.pulse)
end

M._t = { Update = Update, Read = Read }

local function SafeUpdate()
    local ok, err = pcall(Update)
    if not ok then NS.ReportError("Durability Alert", err) end
end

function M:Apply()
    if alert or not S().locked then Alert():Layout() end
    SafeUpdate()
end

function M:Init()
    for _, ev in ipairs({ "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "MERCHANT_CLOSED",
        "MERCHANT_SHOW", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        NS.On(ev, SafeUpdate)
    end
    -- after a loading screen, wait a moment so the message isn't lost behind it
    NS.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, SafeUpdate) end)
end

function M:Diagnose()
    local st = M.stats
    local function P(v) return v and string.format("%d%%", math.floor(v + 0.5)) or "n/a" end
    NS.Print(string.format("  lowest item %s   average %s   broken %d   items read %d   alert at below %d%% (%s)   secret reads %d",
        P(st.lowest), P(st.average), st.broken or 0, st.items or 0, S().threshold, S().mode, st.secret))
end

function M.Build(page)
    page:Section("When", "When the repair message shows")
    page:Slider("Show below (percent)", 5, 90, 5, function() return S().threshold end,
        function(v) S().threshold = v; SafeUpdate() end, function(v) return string.format("%d%%", v) end)
    page:Cycle("Measured by", { { "lowest", "Most damaged item" }, { "average", "Average of all gear" } },
        function() return S().mode end, function(v) S().mode = v; SafeUpdate() end)
    page:Check("Pulse", function() return S().pulse end, function(v) S().pulse = v; SafeUpdate() end)
    page:Check("Play a sound when it first drops below", function() return S().sound end,
        function(v) S().sound = v end)
    page:Check("Hide while in combat", function() return S().hideCombat end,
        function(v) S().hideCombat = v; SafeUpdate() end)
    page:Note("The message stays on screen until you repair. Only you see it.")
    page:Button("Test (5 seconds)", function()
        if not S().enabled then NS.Print("Durability Alert is off: turn it on at the top of this tab first."); return end
        Alert():Show("Repair your gear: 35%", true, S().pulse)
        testUntil = GetTime() + 5
        C_Timer.After(5.05, SafeUpdate)
    end)

    page:Section("Text", "Size, color and position")
    page:Slider("Text size", 14, 72, 1, function() return S().size end,
        function(v) S().size = v; Alert():Layout() end)
    page:Color("Text color", function() return S().color end,
        function(r, g, b, a) local c = S().color; c[1], c[2], c[3], c[4] = r, g, b, a or 1; Alert():Layout() end)
    page:Check("Lock position", function() return S().locked end,
        function(v) S().locked = v; Alert():Layout() end)
    page:Note("Untick \"Lock position\" to show the text and drag it anywhere, then lock it again.")
    page:Button("Reset position", function()
        local p = S().point; p[1], p[2], p[3], p[4] = "CENTER", "CENTER", 0, 150
        Alert():Layout()
    end)
end
