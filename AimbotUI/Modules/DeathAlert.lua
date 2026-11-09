--[[
  Aimbot UI - Party Death Alert
  When someone in your party dies, shows "<Name> died" in the middle of your screen (only you
  see it; nothing is sent to chat). Size, color, how long it stays and where it sits can all be
  changed, and the text can be dragged anywhere.

  Deaths are spotted by watching each party member go from alive to dead. Someone who is
  already dead when you join, log in or /reload is not announced. Feign Death is ignored.
  Only our own frame is created; no Blizzard frame is touched.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Party Death Alert",
    group = "Combat",
    desc = "Shows in the middle of your screen when a party member dies. Only you see it.",
    defaults = {
        enabled   = true,
        raid      = false,          -- also raid members while in a raid
        classColor = true,          -- color the name by class
        sound     = true,
        size      = 32,
        color     = { 1, 0.25, 0.25, 1 },
        duration  = 4,
        locked    = true,
        point     = { "CENTER", "CENTER", 0, 200 },
    },
}
NS.RegisterModule("deathalert", M)

local function S() return NS.db.mod.deathalert end
local IsSecret = NS.IsSecret

local alert
local state = {}            -- key -> true (dead) / false (alive)
M.stats = { deaths = 0, secret = 0, last = nil }

local function Alert()
    if not alert then alert = NS.CreateAlertText("AimbotUIDeathAlert", S, "Party member died") end
    return alert
end

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or IsSecret(v) then return nil end
    return v
end

local function Units()
    local list = {}
    local inRaid = IsInRaid and IsInRaid()
    if inRaid and S().raid then
        for i = 1, 40 do list[#list + 1] = "raid" .. i end
    else
        for i = 1, 4 do list[#list + 1] = "party" .. i end
    end
    return list
end

local function ColoredName(unit)
    local name = SafeCall(UnitName, unit)
    local class, classFile
    local ok, a, b = pcall(UnitClass, unit)
    if ok and not IsSecret(a) and not IsSecret(b) then class, classFile = a, b end
    -- Privacy mode hides other players' names: say the class instead
    local priv = NS.modules.privacy
    if priv and priv.IsActive and priv.IsActive() then
        name = class and ("Party member (" .. class .. ")") or "Party member"
    end
    name = name or "Party member"
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if S().classColor and c then
        local function B(v) return math.floor(v * 255 + 0.5) end
        return string.format("|cff%02x%02x%02x%s|r", B(c.r), B(c.g), B(c.b), name)
    end
    return name
end

local function Announce(unit)
    local s = S()
    local msg = ColoredName(unit) .. " died"
    M.stats.deaths = M.stats.deaths + 1
    M.stats.last = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    Alert():Show(msg)
    if s.sound then
        local id = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
        pcall(PlaySound, id, "Master")
    end
end

local function Scan(silent)
    if not S().enabled then return end
    local seen = {}
    for _, unit in ipairs(Units()) do
        if SafeCall(UnitExists, unit) then
            local guid = SafeCall(UnitGUID, unit)
            local key = guid or unit
            local ok, dead = pcall(UnitIsDeadOrGhost, unit)
            if ok and IsSecret(dead) then
                M.stats.secret = M.stats.secret + 1
            elseif ok then
                if dead and UnitIsFeignDeath and SafeCall(UnitIsFeignDeath, unit) then dead = false end
                dead = dead and true or false
                if dead and state[key] == false and not silent then Announce(unit) end
                state[key] = dead
                seen[key] = true
            end
        end
    end
    for k in pairs(state) do if not seen[k] then state[k] = nil end end
end

M._t = { Scan = Scan, state = state }

function M:Apply()
    if alert or not S().locked then Alert():Layout() end
    if not S().enabled then
        for k in pairs(state) do state[k] = nil end
        if alert then alert:Hide() end
    else
        Scan(true)
    end
end

function M:Init()
    local function Safe(silent)
        local ok, err = pcall(Scan, silent)
        if not ok then NS.ReportError("Party Death Alert", err) end
    end
    NS.On("UNIT_HEALTH", function(_, unit)
        if type(unit) == "string" and (unit:find("^party") or unit:find("^raid")) then Safe(false) end
    end)
    NS.On("UNIT_FLAGS", function() Safe(false) end)
    NS.On("GROUP_ROSTER_UPDATE", function() Safe(true) end)
    NS.On("PLAYER_ENTERING_WORLD", function() for k in pairs(state) do state[k] = nil end; Safe(true) end)
    -- a light poll as a backup for clients that don't send every health event
    local acc = 0
    local poll = CreateFrame("Frame")
    poll:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 0.5 then return end
        acc = 0
        if S().enabled then Safe(false) end
    end)
end

function M:Diagnose()
    local n = 0
    for _ in pairs(state) do n = n + 1 end
    NS.Print(string.format("  watching %d members   deaths shown: %d   last: %s   secret reads: %d",
        n, M.stats.deaths, tostring(M.stats.last or "none"), M.stats.secret))
end

function M.Build(page)
    page:Section("Who", "Which deaths are shown")
    page:Check("Also raid members while in a raid", function() return S().raid end,
        function(v) S().raid = v; NS.ApplyModule("deathalert") end)
    page:Check("Color the name by class", function() return S().classColor end,
        function(v) S().classColor = v end)
    page:Check("Play a sound", function() return S().sound end, function(v) S().sound = v end)
    page:Note("Only you see this; nothing is sent to chat. With Privacy's private mode on, the class is shown instead of the name.")
    page:Button("Test", function()
        if not S().enabled then NS.Print("Party Death Alert is off: turn it on at the top of this tab first."); return end
        Alert():Show((S().classColor and "|cfffff468Party member|r" or "Party member") .. " died")
    end)

    page:Section("Text", "Size, color, position and how long it stays")
    page:Slider("Text size", 14, 72, 1, function() return S().size end,
        function(v) S().size = v; Alert():Layout() end)
    page:Color("Text color", function() return S().color end,
        function(r, g, b, a) local c = S().color; c[1], c[2], c[3], c[4] = r, g, b, a or 1; Alert():Layout() end)
    page:Slider("Stays on screen (seconds)", 1, 15, 1, function() return S().duration end,
        function(v) S().duration = v end)
    page:Check("Lock position", function() return S().locked end,
        function(v) S().locked = v; Alert():Layout() end)
    page:Note("Untick \"Lock position\" to show the text and drag it anywhere, then lock it again.")
    page:Button("Reset position", function()
        local p = S().point; p[1], p[2], p[3], p[4] = "CENTER", "CENTER", 0, 200
        Alert():Layout()
    end)
end
