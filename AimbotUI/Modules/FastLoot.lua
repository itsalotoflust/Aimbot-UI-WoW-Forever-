--[[
  Aimbot UI - Fast Loot (2.28.0)
  1. Fast loot: when a corpse opens with auto loot on (your Auto Loot setting, or Shift held to
     flip it), every slot is taken the moment the loot is ready, and the loot window is kept
     invisible (alpha 0) so it doesn't flash. It's made visible again whenever something is
     left: an item that needs a Bind on Pickup confirmation, full bags, a locked slot (a roll in
     progress, master loot) or anything the game refused. The window is never moved or changed,
     only its alpha, through a method call.
  2. Auto greed: when a group loot roll starts for a green item (blue too, if switched on), it
     rolls Greed for you, or Disenchant when that's offered and you prefer it. Bind on Pickup
     items are left for you unless switched on. Every roll is written to chat.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Fast Loot",
    group = "QoL",
    desc = "Loots corpses instantly without the loot window flashing up, and can roll Greed for you on "
        .. "green (and optionally blue) items in group loot.",
    defaults = {
        enabled   = true,
        fast      = true,       -- take everything at once when auto loot is on
        hide      = true,       -- keep the loot window invisible while doing it
        greed     = true,       -- auto roll on group loot
        quality   = 2,          -- highest quality to auto roll: 2 green, 3 blue
        bop       = false,      -- also roll on Bind on Pickup items
        disenchant = false,     -- roll Disenchant instead of Greed when offered
        announce  = true,       -- write each auto roll to chat
    },
}
NS.RegisterModule("fastloot", M)

local function S() return NS.db.mod.fastloot end
local IsSecret = NS.IsSecret

M.stats = { corpses = 0, taken = 0, left = 0, shown = 0, rolls = 0, greed = 0, de = 0, skipped = 0,
    lastLeft = nil, lastRoll = nil, secret = 0, errors = 0 }

local function Clean(v)
    if v == nil then return nil end
    if IsSecret(v) then M.stats.secret = M.stats.secret + 1; return nil end
    return v
end

----------------------------------------------------------------------
-- Fast loot
----------------------------------------------------------------------
local hidden = false          -- we set the loot window's alpha to 0
local lastPass = 0

local function LootWindow() return LootFrame end

local function SetWindowVisible(v)
    local f = LootWindow()
    if not f then return end
    if v then
        if hidden then
            pcall(f.SetAlpha, f, 1)
            hidden = false
            M.stats.shown = M.stats.shown + 1
        end
    else
        pcall(f.SetAlpha, f, 0)
        hidden = true
    end
end
M._t_SetWindowVisible = SetWindowVisible

-- Is auto loot on for this corpse? The event says so; otherwise the setting, flipped by Shift.
local function AutoLootOn(fromEvent)
    if fromEvent ~= nil and not IsSecret(fromEvent) then return fromEvent and true or false end
    local on = false
    if GetCVarBool then
        local ok, v = pcall(GetCVarBool, "autoLootDefault")
        if ok and not IsSecret(v) then on = v and true or false end
    end
    if IsModifiedClick then
        local ok, v = pcall(IsModifiedClick, "AUTOLOOTTOGGLE")
        if ok and not IsSecret(v) and v then on = not on end
    end
    return on
end
M._t_AutoLootOn = AutoLootOn

-- Take every slot that can be taken. Returns how many were left behind.
local function TakeAll()
    local n = 0
    if GetNumLootItems then
        local ok, v = pcall(GetNumLootItems)
        if ok and type(v) == "number" and not IsSecret(v) then n = v end
    end
    local left = 0
    for slot = n, 1, -1 do
        local locked = false
        if GetLootSlotInfo then
            local ok, _, _, _, _, _, isLocked = pcall(GetLootSlotInfo, slot)
            if ok then locked = Clean(isLocked) and true or false end
        end
        if locked then
            left = left + 1
        else
            local ok = pcall(LootSlot, slot)
            if ok then M.stats.taken = M.stats.taken + 1 else left = left + 1 end
        end
    end
    return left, n
end
M._t_TakeAll = TakeAll

local function OnLootReady(_, autoLoot)
    local s = S()
    if not (s.enabled and s.fast) then return end
    if not AutoLootOn(autoLoot) then return end
    local now = GetTime and GetTime() or 0
    if now - lastPass < 0.2 then return end           -- LOOT_READY and LOOT_OPENED both come
    lastPass = now
    M.stats.corpses = M.stats.corpses + 1
    if s.hide then SetWindowVisible(false) end
    local left = TakeAll()
    if left > 0 then
        M.stats.left = M.stats.left + left
        M.stats.lastLeft = left .. " slot(s) locked or refused"
        SetWindowVisible(true)                         -- you need to see what's left
    end
end
M._t_OnLootReady = OnLootReady

local function NeedWindow(why)
    M.stats.lastLeft = why
    SetWindowVisible(true)
end

----------------------------------------------------------------------
-- Auto greed
----------------------------------------------------------------------
local ROLL_GREED, ROLL_DE = 2, 3

local function RollInfo(rollID)
    if not GetLootRollItemInfo then return nil end
    local ok, texture, name, count, quality, bop, canNeed, canGreed, canDE = pcall(GetLootRollItemInfo, rollID)
    if not ok then return nil end
    return { name = Clean(name), quality = Clean(quality), bop = Clean(bop), canGreed = Clean(canGreed),
        canDE = Clean(canDE) }
end

local function ItemText(rollID, info)
    if GetLootRollItemLink then
        local ok, link = pcall(GetLootRollItemLink, rollID)
        if ok and type(link) == "string" and not IsSecret(link) then return link end
    end
    return info.name or "item"
end

-- Decide what to roll: ROLL_GREED, ROLL_DE, or nil (leave it to you) and why.
local function Decide(info)
    local s = S()
    if type(info.quality) ~= "number" then return nil, "quality unknown" end
    if info.quality < 2 then return nil, "below green" end
    if info.quality > s.quality then return nil, "above your auto roll quality" end
    if info.bop and not s.bop then return nil, "Bind on Pickup" end
    if s.disenchant and info.canDE then return ROLL_DE, "disenchant" end
    if info.canGreed == false then return nil, "greed not allowed" end
    return ROLL_GREED, "greed"
end
M._t_Decide = Decide

local pendingConfirm = {}      -- rollID -> roll type we chose (Bind on Pickup asks to confirm)

local function OnStartRoll(_, rollID)
    local s = S()
    if not (s.enabled and s.greed) then return end
    if type(rollID) ~= "number" or IsSecret(rollID) then return end
    local info = RollInfo(rollID)
    if not info then return end
    local roll, why = Decide(info)
    if not roll then
        M.stats.skipped = M.stats.skipped + 1
        M.stats.lastRoll = "left to you (" .. why .. ")"
        return
    end
    pendingConfirm[rollID] = roll
    local ok, err = pcall(RollOnLoot, rollID, roll)
    if not ok then
        M.stats.errors = M.stats.errors + 1
        M.stats.lastRoll = "roll failed: " .. tostring(err)
        return
    end
    M.stats.rolls = M.stats.rolls + 1
    if roll == ROLL_DE then M.stats.de = M.stats.de + 1 else M.stats.greed = M.stats.greed + 1 end
    local text = ItemText(rollID, info)
    M.stats.lastRoll = (roll == ROLL_DE and "Disenchant" or "Greed") .. " on " .. text
    if s.announce then
        NS.Print("Fast Loot: rolled " .. (roll == ROLL_DE and "Disenchant" or "Greed") .. " on " .. text)
    end
end
M._t_OnStartRoll = OnStartRoll

-- Bind on Pickup rolls ask for a confirmation; confirm only the rolls we made ourselves.
local function OnConfirmRoll(_, rollID, rollType)
    if IsSecret(rollID) or IsSecret(rollType) then return end
    local mine = pendingConfirm[rollID]
    if mine and mine == rollType and S().bop then
        pcall(ConfirmLootRoll, rollID, rollType)
        if StaticPopup_Hide then pcall(StaticPopup_Hide, "CONFIRM_LOOT_ROLL") end
    end
end

----------------------------------------------------------------------
-- Events and settings
----------------------------------------------------------------------
local hooked = false
function M:Init()
    if hooked then return end
    hooked = true
    NS.On("LOOT_READY", OnLootReady)
    NS.On("LOOT_OPENED", OnLootReady)
    NS.On("LOOT_CLOSED", function() SetWindowVisible(true) end)
    NS.On("LOOT_BIND_CONFIRM", function() NeedWindow("Bind on Pickup item needs your confirmation") end)
    NS.On("UI_ERROR_MESSAGE", function(_, _, msg)
        if not hidden or type(msg) ~= "string" or IsSecret(msg) then return end
        -- full bags, unique items and the like: show what's left
        NeedWindow("game said: " .. msg)
    end)
    NS.On("START_LOOT_ROLL", OnStartRoll)
    NS.On("CONFIRM_LOOT_ROLL", OnConfirmRoll)
    NS.On("CANCEL_LOOT_ROLL", function(_, rollID) if not IsSecret(rollID) then pendingConfirm[rollID] = nil end end)
end

function M:Apply()
    if not (S().enabled and S().fast and S().hide) then SetWindowVisible(true) end
end

function M.Build(page)
    page:Section("Fast loot", "Corpses")
    page:Check("Take everything instantly when auto loot is on", function() return S().fast end,
        function(v) S().fast = v end)
    page:Check("Keep the loot window from showing", function() return S().hide end,
        function(v) S().hide = v; M:Apply() end)
    page:Note("Works with the game's Auto Loot setting (Interface > Controls), or Shift held while you loot "
        .. "when it's off. The window still shows when something is left: a Bind on Pickup item to confirm, "
        .. "full bags, or a slot that's locked by a group roll or master loot.")

    page:Section("Auto greed", "Group loot rolls")
    page:Check("Roll automatically on group loot", function() return S().greed end,
        function(v) S().greed = v end)
    page:Cycle("Auto roll on", { { 2, "Green items" }, { 3, "Green and blue items" } },
        function() return S().quality end, function(v) S().quality = v end)
    page:Check("Roll Disenchant instead of Greed when it's offered", function() return S().disenchant end,
        function(v) S().disenchant = v end)
    page:Check("Also roll on Bind on Pickup items (confirms for you)", function() return S().bop end,
        function(v) S().bop = v end)
    page:Check("Write each roll to chat", function() return S().announce end,
        function(v) S().announce = v end)
    page:Note("Never rolls Need. Purple and better items, and anything below green, are always left to you.")
end

function M:Diagnose()
    local st = M.stats
    NS.Print(string.format("  corpses looted %d   items taken %d   left behind %d   window shown again %d   last left %s   hidden now %s",
        st.corpses, st.taken, st.left, st.shown, tostring(st.lastLeft or "-"), tostring(hidden)))
    NS.Print(string.format("  auto rolls %d (greed %d, disenchant %d)   left to you %d   failed %d   last %s   auto loot on now %s   secret reads %d",
        st.rolls, st.greed, st.de, st.skipped, st.errors, tostring(st.lastRoll or "-"), tostring(AutoLootOn(nil)), st.secret))
end
