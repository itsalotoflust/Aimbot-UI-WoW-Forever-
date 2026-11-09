--[[
  Aimbot UI - Nameplate Icons
  Small icons on nameplates:
    * Friendly players: their class icon above the head (easier to read at a distance than a
      name, and it pairs with Privacy's "friendly names above heads"). The name can be hidden
      so only the icon shows.
    * Healers: a healer icon on healers. Enemy healers are known in arenas (the game tells
      addons the enemy specs there) and are also learned when a player casts a healer-only
      spell. Friendly healers come from the group roles.
    * Enemy players: the icon of their PvP racial (Will of the Forsaken, Every Man for
      Himself, Stoneform...), so you know what they can break out of.

  Our own icon frame is created as a child of each nameplate; Blizzard fields are only read.
  The only change to a Blizzard object is the name text's alpha (a method call) when
  "hide the name" is on, and that is put back when the plate goes away or the option is off.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Nameplate Icons",
    group = "Combat",
    desc = "Class icons above friendly players, healer icons on healers, and enemy players' "
        .. "PvP racial on their nameplate.",
    defaults = {
        enabled        = true,
        friendlyClass  = true,      -- class icon above friendly players
        friendlyHideName = false,   -- show only the icon, not the name
        friendlyOnlyPrivate = false,-- only while Privacy's private mode is on
        classSize      = 22,
        healer         = true,
        healerFriendly = true,      -- also mark healers in your own group
        healerSize     = 18,
        racial         = true,
        racialSize     = 20,
    },
}
NS.RegisterModule("plateicons", M)

local function S() return NS.db.mod.plateicons end
local IsSecret = NS.IsSecret

local CLASS_MEDIA = "Interface\\AddOns\\AimbotUI\\media\\classes\\"
local ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"

-- PvP racials by race file name. The first spell this client knows is used.
local RACIALS = {
    Human    = { 59752, 20600 },     -- Every Man for Himself / Perception
    Scourge  = { 7744 },             -- Will of the Forsaken
    Dwarf    = { 20594 },            -- Stoneform
    Gnome    = { 20589 },            -- Escape Artist
    NightElf = { 58984, 20580 },     -- Shadowmeld
    Orc      = { 20572, 33697, 33702 }, -- Blood Fury
    Troll    = { 26297, 20554 },     -- Berserking
    Tauren   = { 20549 },            -- War Stomp
    BloodElf = { 28730, 25046, 50613, 69179, 80483 }, -- Arcane Torrent
    Draenei  = { 28880, 59542, 59543, 59544, 59545, 59547, 59548 }, -- Gift of the Naaru
}

-- Spells only a healing spec casts. Matched by name, so every rank counts.
local HEALER_SPELL_IDS = {
    20473,  -- Holy Shock
    20216,  -- Divine Favor
    53563,  -- Beacon of Light
    18562,  -- Swiftmend
    17116,  -- Nature's Swiftness (druid)
    33891,  -- Tree of Life
    48438,  -- Wild Growth
    16188,  -- Nature's Swiftness (shaman)
    16190,  -- Mana Tide Totem
    974,    -- Earth Shield
    61295,  -- Riptide
    10060,  -- Power Infusion
    724,    -- Lightwell
    33206,  -- Pain Suppression
    34861,  -- Circle of Healing
    47540,  -- Penance
}

----------------------------------------------------------------------
-- Safe API helpers (a secret or failed result counts as "unknown")
----------------------------------------------------------------------
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok or IsSecret(a) then return nil end
    return a, (not IsSecret(b)) and b or nil
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local n = Call(C_Spell.GetSpellName, id)
        if n then return n end
    end
    if GetSpellInfo then return (Call(GetSpellInfo, id)) end
end

local function SpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local t = Call(C_Spell.GetSpellTexture, id)
        if t then return t end
    end
    if GetSpellTexture then return (Call(GetSpellTexture, id)) end
end

local healerNames
local function HealerNames()
    if healerNames then return healerNames end
    healerNames = {}
    for _, id in ipairs(HEALER_SPELL_IDS) do
        local n = SpellName(id)
        if type(n) == "string" and n ~= "" then healerNames[n] = true end
    end
    return healerNames
end

local racialTex = {}
local function RacialTexture(raceFile)
    if racialTex[raceFile] ~= nil then return racialTex[raceFile] or nil end
    local tex = false
    for _, id in ipairs(RACIALS[raceFile] or {}) do
        local t = SpellTexture(id)
        if t then tex = t; break end
    end
    racialTex[raceFile] = tex
    return tex or nil
end

----------------------------------------------------------------------
-- Who is a healer
----------------------------------------------------------------------
local learned = {}           -- GUID -> true (cast a healer-only spell)
M.stats = { learned = 0, arenaHealers = 0, icons = 0 }

local function UnitGUIDSafe(unit) return (Call(UnitGUID, unit)) end

local function ArenaHealer(unit)
    if not GetArenaOpponentSpec then return nil end
    for i = 1, 5 do
        local same = Call(UnitIsUnit, unit, "arena" .. i)
        if same then
            local spec = Call(GetArenaOpponentSpec, i)
            if spec and spec > 0 and GetSpecializationInfoByID then
                local ok, _, _, _, _, role = pcall(GetSpecializationInfoByID, spec)
                if ok and not IsSecret(role) then return role == "HEALER" end
            end
            return nil
        end
    end
    return nil
end

local function IsHealer(unit, friendly)
    if friendly then
        local role = Call(UnitGroupRolesAssigned, unit)
        if role == "HEALER" then return true end
    else
        if ArenaHealer(unit) then return true end
    end
    local guid = UnitGUIDSafe(unit)
    return guid and learned[guid] or false
end

----------------------------------------------------------------------
-- Icons on a plate
----------------------------------------------------------------------
local holders = setmetatable({}, { __mode = "k" })    -- plate -> our frame
local hiddenNames = setmetatable({}, { __mode = "k" })-- name FontString -> true while we hide it

local function Holder(plate)
    local h = holders[plate]
    if h then return h end
    h = CreateFrame("Frame", nil, plate)
    h:SetSize(1, 1)
    h:SetPoint("CENTER", plate, "CENTER", 0, 0)
    h:SetFrameLevel((plate:GetFrameLevel() or 0) + 20)
    h.class = h:CreateTexture(nil, "OVERLAY")
    h.heal = h:CreateTexture(nil, "OVERLAY")
    h.heal:SetTexture(ROLE_TEX)
    h.heal:SetTexCoord(20 / 64, 39 / 64, 1 / 64, 20 / 64)
    h.race = h:CreateTexture(nil, "OVERLAY")
    h.race:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    h.raceBorder = h:CreateTexture(nil, "ARTWORK")
    h.raceBorder:SetColorTexture(0, 0, 0, 0.9)
    holders[plate] = h
    return h
end

local function ShowName(fs)
    if fs and hiddenNames[fs] then
        hiddenNames[fs] = nil
        pcall(fs.SetAlpha, fs, 1)
    end
end

local function HideAll(h)
    h.class:Hide(); h.heal:Hide(); h.race:Hide(); h.raceBorder:Hide()
end

local function Visible(region)
    if not region then return false end
    local ok, shown = pcall(region.IsShown, region)
    return ok and not IsSecret(shown) and shown
end

local function PrivacyOn()
    local p = NS.modules.privacy
    return p and p.IsActive and p.IsActive() or false
end

local function Refresh(unit)
    if type(unit) ~= "string" or not C_NamePlate then return end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate then return end
    local uf = plate.UnitFrame
    local nameFS = uf and uf.name
    local health = uf and (uf.healthBar or uf.HealthBar)
    local h = Holder(plate)
    HideAll(h)
    local s = S()
    if not s.enabled then ShowName(nameFS); return end

    local isPlayer = Call(UnitIsPlayer, unit)
    local enemy = Call(UnitCanAttack, "player", unit)
    local isMe = Call(UnitIsUnit, unit, "player")
    if not isPlayer or isMe then ShowName(nameFS); return end

    local friendly = not enemy
    local nameShown = nameFS and Visible(nameFS)
    local top = nameShown and nameFS or (Visible(health) and health) or nil

    -- friendly class icon
    local classShown = false
    if friendly and s.friendlyClass and (not s.friendlyOnlyPrivate or PrivacyOn()) then
        local _, classFile = Call(UnitClass, unit)
        if type(classFile) == "string" then
            h.class:SetTexture(CLASS_MEDIA .. classFile)
            h.class:SetSize(s.classSize, s.classSize)
            h.class:ClearAllPoints()
            if top then h.class:SetPoint("BOTTOM", top, "TOP", 0, 2)
            else h.class:SetPoint("BOTTOM", plate, "CENTER", 0, 4) end
            h.class:Show()
            classShown = true
        end
    end
    if friendly and classShown and s.friendlyHideName and nameFS then
        if not hiddenNames[nameFS] then hiddenNames[nameFS] = true end
        pcall(nameFS.SetAlpha, nameFS, 0)
        -- the icon takes the name's place
        h.class:ClearAllPoints()
        h.class:SetPoint("CENTER", nameFS, "CENTER", 0, 0)
    else
        ShowName(nameFS)
    end

    -- healer icon
    if s.healer and (not friendly or s.healerFriendly) and IsHealer(unit, friendly) then
        h.heal:SetSize(s.healerSize, s.healerSize)
        h.heal:ClearAllPoints()
        if classShown then h.heal:SetPoint("LEFT", h.class, "RIGHT", 2, 0)
        elseif top then h.heal:SetPoint("BOTTOM", top, "TOP", 0, 2)
        else h.heal:SetPoint("BOTTOM", plate, "CENTER", 0, 4) end
        h.heal:Show()
    end

    -- enemy racial
    if enemy and s.racial then
        local _, raceFile = Call(UnitRace, unit)
        local tex = type(raceFile) == "string" and RacialTexture(raceFile)
        if tex then
            h.race:SetTexture(tex)
            h.race:SetSize(s.racialSize, s.racialSize)
            h.race:ClearAllPoints()
            local anchor = (Visible(health) and health) or top
            if anchor then h.race:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
            else h.race:SetPoint("LEFT", plate, "CENTER", 30, 0) end
            h.raceBorder:ClearAllPoints()
            h.raceBorder:SetPoint("TOPLEFT", h.race, "TOPLEFT", -1, 1)
            h.raceBorder:SetPoint("BOTTOMRIGHT", h.race, "BOTTOMRIGHT", 1, -1)
            h.race:Show(); h.raceBorder:Show()
        end
    end
end

local function RefreshAll()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    local n = 0
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if type(unit) == "string" then pcall(Refresh, unit); n = n + 1 end
    end
    M.stats.icons = n
end

local function Removed(unit)
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate then return end
    local h = holders[plate]
    if h then HideAll(h) end
    local uf = plate.UnitFrame
    ShowName(uf and uf.name)
end

local function Learn(unit, spellID)
    if type(unit) ~= "string" or IsSecret(spellID) or type(spellID) ~= "number" then return end
    if not (unit:find("^nameplate") or unit:find("^arena") or unit == "target" or unit == "focus") then return end
    local name = SpellName(spellID)
    if not (name and HealerNames()[name]) then return end
    if not Call(UnitIsPlayer, unit) then return end
    local guid = UnitGUIDSafe(unit)
    if guid and not learned[guid] then
        learned[guid] = true
        M.stats.learned = M.stats.learned + 1
        if unit:find("^nameplate") then pcall(Refresh, unit) else RefreshAll() end
    end
end

M._t = { Refresh = Refresh, RefreshAll = RefreshAll, Learn = Learn, learned = learned, holders = holders,
    hiddenNames = hiddenNames }

function M:Apply()
    RefreshAll()
end

function M:Init()
    NS.On("NAME_PLATE_UNIT_ADDED", function(_, unit) pcall(Refresh, unit) end)
    NS.On("NAME_PLATE_UNIT_REMOVED", function(_, unit) pcall(Removed, unit) end)
    for _, ev in ipairs({ "ARENA_OPPONENT_UPDATE", "ARENA_PREP_OPPONENT_SPECIALIZATIONS", "GROUP_ROSTER_UPDATE",
        "PLAYER_ROLES_ASSIGNED", "UNIT_FACTION" }) do
        NS.On(ev, function() RefreshAll() end)
    end
    NS.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
        if S().enabled and S().healer then pcall(Learn, unit, spellID) end
    end)
    NS.On("PLAYER_ENTERING_WORLD", function()
        for k in pairs(learned) do learned[k] = nil end
        RefreshAll()
    end)
    -- Privacy's private mode and plate visibility change on their own: a light refresh keeps up.
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(1, function() if S().enabled then RefreshAll() end end)
    end
end

function M:Diagnose()
    local n = 0
    for _ in pairs(HealerNames()) do n = n + 1 end
    local races = {}
    for race in pairs(RACIALS) do races[#races + 1] = race .. (RacialTexture(race) and "" or "(none)") end
    table.sort(races)
    NS.Print(string.format("  plates refreshed: %d   healers learned from spells: %d   healer spells known to client: %d/%d",
        M.stats.icons, M.stats.learned, n, #HEALER_SPELL_IDS))
    NS.Print("  racials: " .. table.concat(races, " "))
end

function M.Build(page)
    page:Section("Friendly players", "Class icon above their heads")
    page:Check("Class icon above friendly players", function() return S().friendlyClass end,
        function(v) S().friendlyClass = v; RefreshAll() end)
    page:Check("Show only the icon (hide their name)", function() return S().friendlyHideName end,
        function(v) S().friendlyHideName = v; RefreshAll() end)
    page:Check("Only while Privacy's private mode is on", function() return S().friendlyOnlyPrivate end,
        function(v) S().friendlyOnlyPrivate = v; RefreshAll() end)
    page:Slider("Class icon size", 12, 48, 1, function() return S().classSize end,
        function(v) S().classSize = v; RefreshAll() end)
    page:Note("Friendly players need friendly nameplates turned on. Privacy's \"Show friendly players' names above "
        .. "heads\" does that for you, or turn them on in the game's options (Interface > Nameplates).")

    page:Section("Healers", "Mark healers on their nameplate")
    page:Check("Healer icon on healers", function() return S().healer end,
        function(v) S().healer = v; RefreshAll() end)
    page:Check("Also on healers in my group", function() return S().healerFriendly end,
        function(v) S().healerFriendly = v; RefreshAll() end)
    page:Slider("Healer icon size", 10, 40, 1, function() return S().healerSize end,
        function(v) S().healerSize = v; RefreshAll() end)
    page:Note("Enemy healers are known in arenas, where the game tells addons the enemy specs. Anywhere else an enemy "
        .. "is marked once you see them cast a healer-only spell (Holy Shock, Swiftmend, Earth Shield, Penance...).")

    page:Section("Enemy racials", "Their PvP racial next to the health bar")
    page:Check("Show enemy players' racial", function() return S().racial end,
        function(v) S().racial = v; RefreshAll() end)
    page:Slider("Racial icon size", 10, 40, 1, function() return S().racialSize end,
        function(v) S().racialSize = v; RefreshAll() end)
    page:Note("Shows what they can break out of or use: Will of the Forsaken, Every Man for Himself, Stoneform, "
        .. "Escape Artist, Shadowmeld, War Stomp and so on. Races without a racial in this list show nothing.")
end
