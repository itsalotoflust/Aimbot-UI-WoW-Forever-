--[[
  Aimbot UI - Talent Point Alert
  While you have unspent talent points, a pulsing "Unspent talent point" message stays in the
  middle of your screen until you spend them. Only you see it. Size, color and position can be
  changed, and the text can be dragged anywhere.

  The count is read from whichever the client offers: UnitCharacterPoints / GetUnspentTalentPoints
  (classic style talents) or the talent tree currency (C_Traits). Only our own frame is created;
  no Blizzard frame is touched.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Talent Point Alert",
    group = "QoL",
    desc = "A pulsing message in the middle of your screen while you have unspent talent points.",
    defaults = {
        enabled    = true,
        pulse      = true,
        sound      = true,          -- sound when you get a new point
        hideCombat = true,          -- hide while you are in combat
        hideOpen   = true,          -- hide while the talent window is open
        size       = 28,
        color      = { 0.3, 0.85, 1, 1 },
        locked     = true,
        point      = { "CENTER", "CENTER", 0, 100 },
    },
}
NS.RegisterModule("talentalert", M)

local function S() return NS.db.mod.talentalert end
local IsSecret = NS.IsSecret

local alert
local testUntil = 0          -- the Test button's message is left alone until then
local lastCount = 0
M.stats = { count = nil, source = "none", secret = 0 }

local function Alert()
    if not alert then alert = NS.CreateAlertText("AimbotUITalentAlert", S, "1 unspent talent point") end
    return alert
end

local function Num(v)
    if IsSecret(v) then M.stats.secret = M.stats.secret + 1; return nil end
    return type(v) == "number" and v or nil
end

-- Returns the number of unspent talent points and where it was read from.
local function Count()
    if UnitCharacterPoints then
        local ok, n = pcall(UnitCharacterPoints, "player")
        n = ok and Num(n)
        if n then return n, "UnitCharacterPoints" end
    end
    if GetUnspentTalentPoints then
        local ok, n = pcall(GetUnspentTalentPoints)
        n = ok and Num(n)
        if n then return n, "GetUnspentTalentPoints" end
    end
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
        and C_Traits.GetTreeCurrencyInfo then
        local okC, configID = pcall(C_ClassTalents.GetActiveConfigID)
        configID = okC and Num(configID)
        if configID then
            local okI, info = pcall(C_Traits.GetConfigInfo, configID)
            if okI and type(info) == "table" and type(info.treeIDs) == "table" then
                local total = 0
                for _, treeID in ipairs(info.treeIDs) do
                    local okT, list = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
                    if okT and type(list) == "table" then
                        for _, c in ipairs(list) do total = total + (Num(c.quantity) or 0) end
                    end
                end
                return total, "C_Traits"
            end
        end
    end
    return nil, "none"
end

local TALENT_FRAMES = { "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame", "TalentFrame" }
local function TalentWindowOpen()
    for _, n in ipairs(TALENT_FRAMES) do
        local f = _G[n]
        if f and f.IsShown then
            local ok, shown = pcall(f.IsShown, f)
            if ok and not IsSecret(shown) and shown then return true end
        end
    end
    return false
end

local function Update()
    if GetTime() < testUntil then return end
    local s = S()
    if not s.enabled then
        if alert then alert:Hide() end
        return
    end
    local n, source = Count()
    M.stats.count, M.stats.source = n, source
    n = n or 0
    if n > lastCount and s.sound then
        local id = (SOUNDKIT and SOUNDKIT.LEVELUPSOUND) or 888
        pcall(PlaySound, id, "Master")
    end
    lastCount = n
    if n <= 0 or (s.hideCombat and InCombatLockdown()) or (s.hideOpen and TalentWindowOpen()) then
        if alert and alert:IsShowing() then alert:Hide() end
        return
    end
    local msg = (n == 1) and "1 unspent talent point" or string.format("%d unspent talent points", n)
    Alert():Show(msg, true, s.pulse)
end

M._t = { Update = Update, Count = Count }

local function SafeUpdate()
    local ok, err = pcall(Update)
    if not ok then NS.ReportError("Talent Point Alert", err) end
end

function M:Apply()
    if alert or not S().locked then Alert():Layout() end
    SafeUpdate()
end

function M:Init()
    for _, ev in ipairs({ "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
        "TRAIT_CONFIG_UPDATED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
        "TRAIT_NODE_CHANGED", "PLAYER_LEVEL_CHANGED", "UNIT_LEVEL" }) do
        NS.On(ev, SafeUpdate)
    end
    NS.On("PLAYER_ENTERING_WORLD", function()
        -- don't play the sound for points you already had when logging in
        local n = Count()
        lastCount = n or 0
        C_Timer.After(3, SafeUpdate)
    end)
    -- a light check once a second, so it hides as soon as the talent window opens
    local acc = 0
    local poll = CreateFrame("Frame")
    poll:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 1 then return end
        acc = 0
        if S().enabled then SafeUpdate() end
    end)
end

function M:Diagnose()
    NS.Print(string.format("  unspent points: %s   read from: %s   talent window open: %s   secret reads: %d",
        tostring(M.stats.count), M.stats.source, tostring(TalentWindowOpen()), M.stats.secret))
    -- every source, so the quickest one on this client can be seen
    local function Try(fn, ...)
        if not fn then return "missing" end
        local ok, v = pcall(fn, ...)
        if not ok then return "error" end
        if IsSecret(v) then return "secret" end
        return tostring(v)
    end
    NS.Print(string.format("  sources: UnitCharacterPoints=%s  GetUnspentTalentPoints=%s  level=%s",
        Try(UnitCharacterPoints, "player"), Try(GetUnspentTalentPoints), Try(UnitLevel, "player")))
end

function M.Build(page)
    page:Section("When", "While you have points to spend")
    page:Check("Pulse", function() return S().pulse end, function(v) S().pulse = v; SafeUpdate() end)
    page:Check("Play a sound when you get a new point", function() return S().sound end,
        function(v) S().sound = v end)
    page:Check("Hide while in combat", function() return S().hideCombat end,
        function(v) S().hideCombat = v; SafeUpdate() end)
    page:Check("Hide while the talent window is open", function() return S().hideOpen end,
        function(v) S().hideOpen = v; SafeUpdate() end)
    page:Note("The message stays on screen until you spend your points. Only you see it.")
    page:Button("Test (5 seconds)", function()
        if not S().enabled then NS.Print("Talent Point Alert is off: turn it on at the top of this tab first."); return end
        Alert():Show("1 unspent talent point", true, S().pulse)
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
        local p = S().point; p[1], p[2], p[3], p[4] = "CENTER", "CENTER", 0, 100
        Alert():Layout()
    end)
end
