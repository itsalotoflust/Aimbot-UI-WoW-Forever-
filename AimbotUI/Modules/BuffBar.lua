--[[
  Aimbot UI - Buff Bar (2.29.0)
  A row of clickable buttons, one per buff consumable in your bags: food, elixirs, flasks,
  scrolls, weapon oils and sharpening stones (potions and other buff items optional).
  Click a button to use the item. Weapon oils and stones: left-click puts it on the main hand,
  right-click on the off hand.

  The bar fills itself from your bags and starts at the top centre of the screen. Unlock it in
  the settings to drag it anywhere.

  Buttons whose buff is already on you are dimmed (or hidden, or left alone: your choice), with
  the time left when the game shows it. Stacks at or under the low-stock number turn red.

  Combat: the buttons are secure action buttons, so the game won't let an addon add, remove,
  move or re-point them in combat. They keep working in combat; any change to which items are
  on the bar waits until combat ends. Counts, dimming, timers and cooldowns update any time.

  Every value read from the game is checked with NS.IsSecret; a secret value counts as unknown
  (a buff we can't read is shown as missing, never dimmed by guesswork).
]]

local ADDON_NAME, NS = ...

local BAR_NAME = "AimbotUIBuffBar"
local BUTTON_PREFIX = "AimbotUIBuffBarButton"
local MAX_BUTTONS = 24
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"

local M = {
    name = "Buff Bar",
    group = "QoL",
    desc = "A bar of buttons for the buff items in your bags (food, elixirs, flasks, scrolls, "
        .. "weapon oils and stones). Click one to use it. Starts at the top centre; unlock it to move it.",
    defaults = {
        enabled    = true,
        locked     = false,
        point      = { "TOP", "TOP", 0, -40 },
        size       = 36,
        spacing    = 4,
        perRow     = 12,
        vertical   = false,
        maxButtons = 16,
        food       = true,
        elixirs    = true,          -- elixirs, flasks and scrolls
        weapon     = true,          -- weapon oils, sharpening stones, weightstones
        potions    = false,         -- most potions are heals, not buffs
        other      = true,          -- other consumables with a "Use:" effect
        onlyBuffs  = true,          -- 2.29.1: only items whose effect lasts (reads the tooltip)
        activeMode = "dim",         -- buff already on you: "dim", "hide" or "normal"
        timeLeft   = true,
        lowStock   = 3,             -- count at or under this turns red (0 = off)
        fade       = false,         -- faded until the mouse is over the bar
        pinned     = {},            -- list of itemIDs, always shown first (greyed at 0)
        ignore     = {},            -- itemID -> true: never shown
    },
}
NS.RegisterModule("buffbar", M)

local function S() return NS.db.mod.buffbar end
local IsSecret = NS.IsSecret

M.stats = { scans = 0, found = 0, layouts = 0, pending = false, secret = 0, clicks = 0,
    cats = {}, auraHow = "-", lastError = nil, noBuff = 0, unknown = 0, textHow = "-", noText = false }

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function Clean(v)
    if v == nil then return nil end
    if IsSecret(v) then M.stats.secret = M.stats.secret + 1; return nil end
    return v
end

----------------------------------------------------------------------
-- Which items go on the bar
----------------------------------------------------------------------
-- Temporary weapon enhancements that some clients file under Trade Goods instead of
-- Consumable > Item Enhancement. Item IDs from memory; an ID that doesn't exist on this client
-- simply never matches. Anything missing can be pinned by hand.
local WEAPON_IDS = {
    [2862] = true, [2863] = true, [2871] = true, [7964] = true, [12404] = true,   -- sharpening stones
    [18262] = true, [23122] = true,                                             -- elemental, consecrated
    [3239] = true, [3240] = true, [3241] = true, [7965] = true, [12643] = true,   -- weightstones
    [20744] = true, [20746] = true, [20750] = true, [20749] = true, [23123] = true, -- wizard oils
    [20745] = true, [20747] = true, [20748] = true,                             -- mana oils
    [3824] = true, [3829] = true,                                               -- shadow, frost oil
}
M._t_WEAPON_IDS = WEAPON_IDS

local CAT_ORDER = { food = 1, elixirs = 2, weapon = 3, potions = 4, other = 5 }

-- Consumable (class 0) sub-classes: 1 potion, 2 elixir, 3 flask, 4 scroll, 5 food & drink,
-- 6 item enhancement, 7 bandage, 8 other, 0 generic. Returns the category or nil.
local function Classify(classID, subClassID, itemID, hasSpell)
    if itemID and WEAPON_IDS[itemID] then return "weapon" end
    if classID ~= 0 then return nil end
    if subClassID == 5 then return "food" end
    if subClassID == 2 or subClassID == 3 or subClassID == 4 then return "elixirs" end
    if subClassID == 6 then return "weapon" end
    if subClassID == 1 then return "potions" end
    if (subClassID == 0 or subClassID == 8) and hasSpell then return "other" end
    return nil
end
M._t_Classify = Classify

local function ContainerInfo(bag, slot)
    if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and type(info) == "table" then return info end
    return nil
end

local function NumSlots(bag)
    if not (C_Container and C_Container.GetContainerNumSlots) then return 0 end
    local ok, v = pcall(C_Container.GetContainerNumSlots, bag)
    if ok and type(v) == "number" and not IsSecret(v) then return v end
    return 0
end

-- icon, classID, subClassID for an item ID (works without the item being cached)
local function ItemBasics(itemID)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return nil end
    local ok, _, _, _, _, icon, classID, subClassID = pcall(f, itemID)
    if not ok then return nil end
    return Clean(icon), Clean(classID), Clean(subClassID)
end

-- name and spell ID of the item's "Use:" effect (nil until the item is cached)
local function ItemSpell(itemID)
    local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not f then return nil end
    local ok, name, spellID = pcall(f, itemID)
    if not ok then return nil end
    name, spellID = Clean(name), Clean(spellID)
    if type(name) ~= "string" or name == "" then name = nil end
    if type(spellID) ~= "number" then spellID = nil end
    return name, spellID
end

local function ItemCount(itemID)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, itemID)
    n = ok and Clean(n) or nil
    return type(n) == "number" and n or 0
end

local function MakeEntry(itemID, cat, icon)
    local spellName, spellID = ItemSpell(itemID)
    return { itemID = itemID, cat = cat, icon = icon, spellName = spellName, spellID = spellID }
end

----------------------------------------------------------------------
-- Does the item give a buff? (2.29.1)
-- Read from the item's "Use:" tooltip line (or its spell's description): a buff lasts a while,
-- so its text says "for 30 min", "for 1 hour", "for 15 sec" or "well fed". Instant effects and
-- effects over time ("Restores 500 health", "Restores 1344 mana over 18 sec.") don't count.
-- English text only.
----------------------------------------------------------------------
local BUFF_PATTERNS = {
    "for %d[%d%.,]* ?sec", "for %d[%d%.,]* ?min", "for %d[%d%.,]* ?hour", "for %d[%d%.,]* ?hr",
    "well fed",
}
local function GivesBuff(text)
    if type(text) ~= "string" then return nil end
    local t = text:lower()
    for _, pat in ipairs(BUFF_PATTERNS) do
        if t:find(pat) then return true end
    end
    return false
end
M._t_GivesBuff = GivesBuff

-- The item's "Use:" text, and where it came from; nil while the game hasn't loaded it.
local function UseText(itemID, spellID)
    local haveAPI = false
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        haveAPI = true
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok and type(data) == "table" and not IsSecret(data) and type(data.lines) == "table" then
            local trig = ITEM_SPELL_TRIGGER_ONUSE or "Use:"
            if type(trig) ~= "string" or IsSecret(trig) then trig = "Use:" end
            local parts = {}
            for _, line in ipairs(data.lines) do
                local t = type(line) == "table" and Clean(line.leftText) or nil
                if type(t) == "string" and t:find(trig, 1, true) then parts[#parts + 1] = t end
            end
            if #parts > 0 then return table.concat(parts, " "), "tooltip", true end
        end
    end
    local desc = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    if spellID and desc then
        haveAPI = true
        local ok, d = pcall(desc, spellID)
        d = ok and Clean(d) or nil
        if type(d) == "string" and d ~= "" then return d, "spell description", true end
    end
    return nil, nil, haveAPI
end

local buffCache = {}         -- itemID -> true / false once the text was read
-- true / false, or nil while the text isn't loaded yet
local function ItemGivesBuff(itemID, spellID)
    local c = buffCache[itemID]
    if c ~= nil then return c end
    local text, how, haveAPI = UseText(itemID, spellID)
    if not haveAPI then
        M.stats.noText = true
        return true              -- this client can't tell us: show it rather than nothing
    end
    if not text then return nil end
    M.stats.textHow = how
    local v = GivesBuff(text)
    buffCache[itemID] = v
    return v
end
M._t_ItemGivesBuff = ItemGivesBuff
M._t_ClearBuffCache = function() for k in pairs(buffCache) do buffCache[k] = nil end end

-- Forward declaration: is the item's buff on the player? true / false / nil (can't tell).
local IsActive

-- The ordered list of entries the bar should show. Pure on the game APIs it calls.
local function BuildList()
    local s = S()
    M.stats.scans = M.stats.scans + 1
    M.stats.noBuff, M.stats.unknown = 0, 0
    local found, cats = {}, {}
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
        for slot = 1, NumSlots(bag) do
            local info = ContainerInfo(bag, slot)
            local itemID = info and Clean(info.itemID)
            if type(itemID) == "number" and found[itemID] == nil then
                found[itemID] = false
                local icon, classID, subClassID = ItemBasics(itemID)
                local spellName, spellID = ItemSpell(itemID)
                local cat = Classify(classID, subClassID, itemID, spellName ~= nil)
                local buff = true
                if cat and s[cat] and not s.ignore[itemID] and s.onlyBuffs then
                    buff = ItemGivesBuff(itemID, spellID)
                    if buff == nil then
                        M.stats.unknown = M.stats.unknown + 1
                    elseif buff == false then
                        M.stats.noBuff = M.stats.noBuff + 1
                    end
                end
                if cat and s[cat] and not s.ignore[itemID] and buff == true then
                    found[itemID] = MakeEntry(itemID, cat, Clean(info.iconFileID) or icon)
                    cats[cat] = (cats[cat] or 0) + 1
                end
            end
        end
    end
    M.stats.cats = cats

    local list, used = {}, {}
    for _, id in ipairs(s.pinned) do
        if type(id) == "number" and not used[id] then
            used[id] = true
            local e = found[id]
            if not e then
                local icon, classID, subClassID = ItemBasics(id)
                local cat = Classify(classID, subClassID, id, ItemSpell(id) ~= nil) or "other"
                e = MakeEntry(id, cat, icon)
            end
            e.pinned = true
            list[#list + 1] = e
        end
    end
    local rest = {}
    for id, e in pairs(found) do
        if e and not used[id] then rest[#rest + 1] = e end
    end
    table.sort(rest, function(a, b)
        local ca, cb = CAT_ORDER[a.cat] or 9, CAT_ORDER[b.cat] or 9
        if ca ~= cb then return ca < cb end
        return a.itemID < b.itemID
    end)
    for _, e in ipairs(rest) do list[#list + 1] = e end

    -- counts, then drop empty unpinned stacks, buffs already on (hide mode), and the overflow
    local out = {}
    local cap = math.max(1, math.min(MAX_BUTTONS, s.maxButtons or 16))
    for _, e in ipairs(list) do
        e.count = ItemCount(e.itemID)
        local keep = e.pinned or e.count > 0
        if keep and s.activeMode == "hide" and IsActive(e) == true then keep = false end
        if keep and #out < cap then out[#out + 1] = e end
    end
    M.stats.found = #out
    return out
end
M._t_BuildList = BuildList

----------------------------------------------------------------------
-- Is the buff on?
----------------------------------------------------------------------
local nameCache = {}
local function SpellNameOf(spellID)
    if nameCache[spellID] ~= nil then return nameCache[spellID] or nil end
    local n
    if C_Spell and C_Spell.GetSpellName then
        local ok, v = pcall(C_Spell.GetSpellName, spellID)
        if ok then n = Clean(v) end
    end
    if not n and GetSpellInfo then
        local ok, v = pcall(GetSpellInfo, spellID)
        if ok then n = Clean(v) end
    end
    if type(n) ~= "string" then n = nil end
    nameCache[spellID] = n or false
    return n
end

local WELL_FED, DRINK = 19705, 430      -- "Well Fed" and "Drink", read in the game's language
local function WellFedName() return SpellNameOf(WELL_FED) or "Well Fed" end
local function DrinkName() return SpellNameOf(DRINK) or "Drink" end

-- The player's aura with this spell ID (or name), as a table, or nil.
local function PlayerAura(spellID, name)
    local CU = C_UnitAuras
    if not CU then return nil end
    if spellID and CU.GetPlayerAuraBySpellID then
        local ok, a = pcall(CU.GetPlayerAuraBySpellID, spellID)
        if ok and a ~= nil and not IsSecret(a) and type(a) == "table" then
            M.stats.auraHow = "spell ID"
            return a
        elseif ok and IsSecret(a) then
            M.stats.secret = M.stats.secret + 1
        end
    end
    if name and CU.GetAuraDataBySpellName then
        local ok, a = pcall(CU.GetAuraDataBySpellName, "player", name, "HELPFUL")
        if ok and a ~= nil and not IsSecret(a) and type(a) == "table" then
            M.stats.auraHow = "name"
            return a
        end
    end
    return nil
end

local function WeaponEnchant()
    if not GetWeaponEnchantInfo then return nil end
    local ok, hasMain, mainExp = pcall(GetWeaponEnchantInfo)
    if not ok then return nil end
    hasMain, mainExp = Clean(hasMain), Clean(mainExp)
    if hasMain == nil then return nil end
    return hasMain and true or false, type(mainExp) == "number" and mainExp / 1000 or nil
end

local function Now() return (GetTime and GetTime()) or 0 end

local function AuraLeft(a)
    if not a then return nil end
    local exp = Clean(a.expirationTime)
    if type(exp) == "number" and exp > 0 then
        local left = exp - Now()
        if left > 0 then return left end
    end
    return nil
end

-- true / false / nil (unknown), plus seconds left when the game shows it.
function IsActive(e)
    if not e then return nil end
    if e.cat == "weapon" then
        return WeaponEnchant()
    end
    local a = e.spellID and PlayerAura(e.spellID) or nil
    if not a and e.cat == "food" and e.spellName ~= DrinkName() then
        a = PlayerAura(nil, WellFedName())
    end
    if not a and (e.cat == "elixirs" or e.cat == "other" or e.cat == "potions") and e.spellName then
        a = PlayerAura(nil, e.spellName)
    end
    if a then return true, AuraLeft(a) end
    return false
end
M._t_IsActive = IsActive

local function FormatLeft(sec)
    if type(sec) ~= "number" or sec <= 0 then return "" end
    if sec >= 3600 then return math.floor(sec / 3600 + 0.5) .. "h" end
    if sec >= 60 then return math.floor(sec / 60 + 0.5) .. "m" end
    return math.floor(sec) .. "s"
end
M._t_FormatLeft = FormatLeft

----------------------------------------------------------------------
-- Layout maths (pure)
----------------------------------------------------------------------
local function Grid(n, s)
    local per = math.max(1, math.floor(s.perRow or 12))
    local cols = math.min(math.max(n, 1), per)
    local rows = math.max(1, math.ceil(n / per))
    if s.vertical then cols, rows = rows, cols end
    return cols, rows
end

-- top-left offset of button i (1-based) inside the bar
local function ButtonPos(i, s)
    local per = math.max(1, math.floor(s.perRow or 12))
    local idx = i - 1
    local col, row = idx % per, math.floor(idx / per)
    if s.vertical then col, row = row, col end
    local step = s.size + s.spacing
    return col * step, -row * step
end
M._t_ButtonPos = ButtonPos

local function BarSize(n, s)
    local cols, rows = Grid(n, s)
    return cols * s.size + (cols - 1) * s.spacing, rows * s.size + (rows - 1) * s.spacing
end
M._t_BarSize = BarSize

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------
local bar, label, tint
local buttons = {}
local shown = {}             -- entries currently on the buttons (in order)
local pending = false        -- a layout change is waiting for combat to end
local testUntil = nil

local function SavePosition()
    local point, _, relPoint, x, y = bar:GetPoint()
    if point then
        local p = S().point
        p[1], p[2], p[3], p[4] = point, relPoint, x, y
    end
end

local function SetClicks(b)
    local down = false
    if GetCVarBool then
        local ok, v = pcall(GetCVarBool, "ActionButtonUseKeyDown")
        if ok and not IsSecret(v) then down = v and true or false end
    end
    b:RegisterForClicks(down and "AnyDown" or "AnyUp")
end

local SECURE_KEYS = { "type1", "item1", "macrotext1", "type2", "macrotext2", "shift-type2", "ctrl-type2" }

-- Point a button at an entry. Out of combat only (the caller checks).
local function SetSecure(b, e)
    for _, k in ipairs(SECURE_KEYS) do b:SetAttribute(k, nil) end
    if not e or e.test then return end
    local id = e.itemID
    if e.cat == "weapon" then
        -- the item puts the cursor in targeting mode; "/use 16" / "/use 17" picks the weapon
        b:SetAttribute("type1", "macro")
        b:SetAttribute("macrotext1", "/use item:" .. id .. "\n/use 16")
        b:SetAttribute("type2", "macro")
        b:SetAttribute("macrotext2", "/use item:" .. id .. "\n/use 17")
        -- Shift / Ctrl + right-click are ours (hide / pin), so they mustn't use the item
        b:SetAttribute("shift-type2", "noop")
        b:SetAttribute("ctrl-type2", "noop")
    else
        b:SetAttribute("type1", "item")
        b:SetAttribute("item1", "item:" .. id)
    end
end
M._t_SetSecure = SetSecure

local function LortiOn()
    local l = NS.db and NS.db.mod and NS.db.mod.lorti
    return l and l.enabled and l.buttons and true or false
end

local Refresh, UpdateVisuals, RetryUnknown

local function IsPinned(id)
    for _, v in ipairs(S().pinned) do if v == id then return true end end
    return false
end

local function TogglePin(id)
    local p = S().pinned
    for i, v in ipairs(p) do
        if v == id then table.remove(p, i); return false end
    end
    p[#p + 1] = id
    S().ignore[id] = nil
    return true
end
M._t_TogglePin = TogglePin

local function ShowTip(b)
    local e = b.entry
    if not e then return end
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
    if e.test then
        GameTooltip:AddLine("Buff Bar test icon", 1, 1, 1)
    else
        local ok = GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, e.itemID)
        if not ok then GameTooltip:AddLine("item " .. e.itemID, 1, 1, 1) end
        if e.cat == "weapon" then
            GameTooltip:AddLine("Click: main hand   Right-click: off hand", 0.6, 0.9, 0.6)
        else
            GameTooltip:AddLine("Click: use it", 0.6, 0.9, 0.6)
        end
        GameTooltip:AddLine("Shift+right-click: hide this item", 0.6, 0.6, 0.6)
        GameTooltip:AddLine(e.pinned and "Ctrl+right-click: unpin" or "Ctrl+right-click: pin (always shown first)",
            0.6, 0.6, 0.6)
    end
    if not S().locked then GameTooltip:AddLine("Drag to move (lock it in the settings)", 0.4, 0.7, 1) end
    GameTooltip:Show()
end

local function StartDrag()
    if not S().locked and not InCombat() then bar:StartMoving() end
end
local function StopDrag()
    bar:StopMovingOrSizing()
    SavePosition()
end

local function MakeButton(i)
    local b = CreateFrame("Button", BUTTON_PREFIX .. i, bar, "SecureActionButtonTemplate")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", StartDrag)
    b:SetScript("OnDragStop", StopDrag)
    b.back = b:CreateTexture(nil, "BACKGROUND")
    b.back:SetPoint("TOPLEFT", -1, 1)
    b.back:SetPoint("BOTTOMRIGHT", 1, -1)
    b.back:SetColorTexture(0, 0, 0, 0.9)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    pcall(b.icon.SetTexCoord, b.icon, 0.08, 0.92, 0.08, 0.92)
    b.gloss = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.gloss:SetPoint("TOPLEFT", -2, 2)
    b.gloss:SetPoint("BOTTOMRIGHT", 2, -2)
    b.gloss:SetTexture(MEDIA .. "gloss")
    b.gloss:SetVertexColor(0.3, 0.3, 0.3, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    local okCD, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    if okCD and cd then
        cd:SetAllPoints()
        b.cd = cd
    end
    -- texts sit on their own frame so the cooldown swipe never covers them
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints()
    top:SetFrameLevel(b:GetFrameLevel() + 3)
    b.count = top:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.time = top:CreateFontString(nil, "OVERLAY")
    b.time:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    b.time:SetPoint("TOP", 0, -2)
    b.time:SetTextColor(1, 0.9, 0.3)
    SetClicks(b)
    b:SetScript("PostClick", function(self, mouse)
        local e = self.entry
        if not e or e.test then return end
        if mouse == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
            S().ignore[e.itemID] = true
            local p = S().pinned
            for k = #p, 1, -1 do if p[k] == e.itemID then table.remove(p, k) end end
            NS.Print("Buff Bar: item hidden (show it again in the settings).")
            Refresh()
        elseif mouse == "RightButton" and IsControlKeyDown and IsControlKeyDown() then
            local on = TogglePin(e.itemID)
            NS.Print(on and "Buff Bar: item pinned. It stays on the bar, first, even when you run out."
                or "Buff Bar: item unpinned.")
            Refresh()
        elseif mouse ~= "RightButton" or e.cat == "weapon" then
            M.stats.clicks = M.stats.clicks + 1
            if NS.SparkleOwnButton then pcall(NS.SparkleOwnButton, self) end
        end
        if GameTooltip:IsOwned(self) then ShowTip(self) end
    end)
    b:SetScript("OnEnter", ShowTip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    buttons[i] = b
    return b
end

local fadeElapsed = 0
local function FadeTick(self, elapsed)
    fadeElapsed = fadeElapsed + (elapsed or 0)
    if fadeElapsed < 0.1 then return end
    fadeElapsed = 0
    local s = S()
    if not s.fade or not s.locked then self:SetAlpha(1); return end
    local ok, over = pcall(self.IsMouseOver, self)
    over = ok and not IsSecret(over) and over
    self:SetAlpha(over and 1 or 0.25)
end

local function Ensure()
    if bar then return true end
    if InCombat() then return false end
    bar = CreateFrame("Frame", BAR_NAME, UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", StartDrag)
    bar:SetScript("OnDragStop", StopDrag)
    bar:SetScript("OnUpdate", FadeTick)
    tint = bar:CreateTexture(nil, "BACKGROUND")
    tint:SetPoint("TOPLEFT", -4, 4)
    tint:SetPoint("BOTTOMRIGHT", 4, -4)
    tint:SetColorTexture(0.2, 0.6, 1, 0.25)
    label = bar:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    label:SetPoint("BOTTOM", bar, "TOP", 0, 6)
    label:SetText("Buff Bar (drag me)")
    bar:Hide()
    return true
end

local function SameItems(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i].itemID ~= b[i].itemID or (a[i].pinned and true or false) ~= (b[i].pinned and true or false)
            or a[i].test ~= b[i].test then
            return false
        end
    end
    return true
end
M._t_SameItems = SameItems

-- Place the bar and its buttons for this list. Out of combat only.
local function Layout(list)
    local s = S()
    M.stats.layouts = M.stats.layouts + 1
    local n = #list
    bar:ClearAllPoints()
    local p = s.point
    bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    local w, h = BarSize(n, s)
    bar:SetSize(w, h)
    for i = 1, math.max(#buttons, n) do
        local b = buttons[i] or (i <= n and MakeButton(i))
        if b then
            local e = list[i]
            if e then
                b.entry = e
                b:SetSize(s.size, s.size)
                b:ClearAllPoints()
                local x, y = ButtonPos(i, s)
                b:SetPoint("TOPLEFT", bar, "TOPLEFT", x, y)
                SetSecure(b, e)
                b.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                b:Show()
            else
                b.entry = nil
                SetSecure(b, nil)
                b:Hide()
            end
        end
    end
    shown = list
    bar:EnableMouse(not s.locked)
    tint:SetShown(not s.locked)
    label:SetShown(not s.locked)
    local visible = s.enabled and (n > 0 or not s.locked)
    bar:SetShown(visible and true or false)
    pending = false
    M.stats.pending = false
end

function UpdateVisuals()
    if not bar then return end
    local s = S()
    for i, e in ipairs(shown) do
        local b = buttons[i]
        if b and b.entry == e then
            local count = e.test and e.count or ItemCount(e.itemID)
            e.count = count
            b.count:SetText(((count > 1) or e.pinned or e.test) and tostring(count) or "")
            if s.lowStock > 0 and count <= s.lowStock then
                b.count:SetTextColor(1, 0.25, 0.25)
            else
                b.count:SetTextColor(1, 1, 1)
            end
            local active, left = false, nil
            if e.test then active, left = e.active, e.left
            else active, left = IsActive(e) end
            local dim = (active == true and s.activeMode == "dim") or count == 0
            b.icon:SetDesaturated(dim and true or false)
            b.icon:SetAlpha(dim and 0.45 or 1)
            b.time:SetText((s.timeLeft and active == true) and FormatLeft(left) or "")
            b.gloss:SetShown(LortiOn())
            if b.cd and not e.test then
                local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
                local okC, start, dur = false, nil, nil
                if f then okC, start, dur = pcall(f, e.itemID) end
                start, dur = Clean(start), Clean(dur)
                if okC and type(start) == "number" and type(dur) == "number" and dur > 1.5 and start > 0 then
                    pcall(b.cd.SetCooldown, b.cd, start, dur)
                else
                    pcall(b.cd.Clear, b.cd)
                end
            end
        end
    end
end
M._t_UpdateVisuals = UpdateVisuals

-- Item text that wasn't loaded yet: look again shortly (a few times, then wait for bag changes).
local retries = 0
local QueueRefresh
function RetryUnknown()
    if (M.stats.unknown or 0) == 0 then retries = 0; return end
    if retries >= 5 or not (C_Timer and C_Timer.After) then return end
    retries = retries + 1
    C_Timer.After(2, function() if QueueRefresh then QueueRefresh() end end)
end

local TEST_ICONS = {
    "Interface\\Icons\\INV_Misc_Fish_02", "Interface\\Icons\\INV_Potion_32", "Interface\\Icons\\INV_Potion_61",
    "Interface\\Icons\\INV_Stone_02", "Interface\\Icons\\INV_Scroll_03", "Interface\\Icons\\INV_Drink_07",
}

function Refresh()
    if not NS.db then return end
    local s = S()
    if not bar and not Ensure() then pending = true; M.stats.pending = true; return end
    local list
    if not s.enabled then
        list = {}
    elseif testUntil and Now() < testUntil then
        list = {}
        for i, tex in ipairs(TEST_ICONS) do
            list[i] = { itemID = -i, test = true, icon = tex, cat = "other", count = (i * 7) % 23,
                active = (i % 3 == 0), left = (i % 3 == 0) and 600 or nil }
        end
    else
        testUntil = nil
        list = BuildList()
        RetryUnknown()
    end
    if InCombat() then
        -- the buttons can't change in combat: keep them, update what we can, finish after combat
        if not SameItems(list, shown) then pending = true; M.stats.pending = true end
    else
        Layout(list)
    end
    UpdateVisuals()
end
M._t_Refresh = Refresh
M._t_Shown = function() return shown end
M._t_Pending = function() return pending end
M._t_Buttons = function() return buttons end
M._t_Bar = function() return bar end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local queued = false
function QueueRefresh()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        local ok, err = pcall(Refresh)
        if not ok then M.stats.lastError = tostring(err); NS.ReportError("Buff Bar", err) end
    end)
end

local function OnAura(_, unit)
    if unit ~= "player" then return end
    if S().activeMode == "hide" then QueueRefresh() else pcall(UpdateVisuals) end
end

local hooked, ticker = false, nil
function M:Init()
    if not hooked then
        hooked = true
        NS.On("BAG_UPDATE_DELAYED", QueueRefresh)
        NS.On("GET_ITEM_INFO_RECEIVED", QueueRefresh)
        NS.On("PLAYER_REGEN_ENABLED", function() if pending then QueueRefresh() end end)
        NS.On("UNIT_AURA", OnAura)
        NS.On("UNIT_INVENTORY_CHANGED", OnAura)
        NS.On("BAG_UPDATE_COOLDOWN", function() pcall(UpdateVisuals) end)
        NS.On("CVAR_UPDATE", function()
            if InCombat() then return end
            for _, b in ipairs(buttons) do SetClicks(b) end
        end)
    end
    if not ticker and C_Timer and C_Timer.NewTicker then
        -- time-left text and test expiry; cheap: only the buttons on screen
        ticker = C_Timer.NewTicker(1, function()
            if testUntil and Now() >= testUntil then QueueRefresh() end
            if bar and bar:IsShown() then pcall(UpdateVisuals) end
        end)
    end
    QueueRefresh()
end

function M:Apply()
    Refresh()
end

function M.Test()
    if InCombat() then NS.Print("Buff Bar: the test can't run in combat."); return end
    testUntil = Now() + 15
    Refresh()
    NS.Print("Buff Bar: showing 6 sample icons for 15 seconds.")
end

local function ParseItem(text)
    text = tostring(text or "")
    local id = text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$")
    if id then return tonumber(id) end
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local name = text:gsub("^%s+", ""):gsub("%s+$", "")
    if f and name ~= "" then
        local ok, v = pcall(f, name)
        if ok and type(v) == "number" and not IsSecret(v) then return v end
    end
    return nil
end
M._t_ParseItem = ParseItem

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
local function Changed() Refresh() end

function M.Build(page)
    page:Section("Items", "What goes on the bar")
    page:Note("The bar fills itself from your bags. Click a button to use the item. Weapon oils and "
        .. "stones: click for the main hand, right-click for the off hand. Shift+right-click hides an "
        .. "item; Ctrl+right-click pins it (always shown first, even at 0).")
    page:Check("Food and drink", function() return S().food end, function(v) S().food = v; Changed() end)
    page:Check("Elixirs, flasks and scrolls", function() return S().elixirs end,
        function(v) S().elixirs = v; Changed() end)
    page:Check("Weapon oils, sharpening stones and weightstones", function() return S().weapon end,
        function(v) S().weapon = v; Changed() end)
    page:Check("Potions (most are heals, so off by default)", function() return S().potions end,
        function(v) S().potions = v; Changed() end)
    page:Check("Other usable consumables (Juju, firewater and the like)", function() return S().other end,
        function(v) S().other = v; Changed() end)
    page:Check("Only items that give a buff (reads the item's tooltip)", function() return S().onlyBuffs end,
        function(v) S().onlyBuffs = v; Changed() end)
    page:Note("An item counts when its \"Use:\" text says how long the effect lasts (\"for 30 min\", "
        .. "\"well fed\"). Instant heals and plain food and drink are left out. Pin anything it misses.")
    page:Input("Pin an item: name or item ID", function(text)
        local id = ParseItem(text)
        if not id then NS.Print("Buff Bar: couldn't find that item. Try its item ID."); return false end
        if not IsPinned(id) then TogglePin(id) end
        NS.Print("Buff Bar: pinned item " .. id .. ".")
        Changed()
    end, "Pin")
    page:Button("Clear pinned items", function()
        local p = S().pinned
        for k = #p, 1, -1 do p[k] = nil end
        Changed()
    end)
    page:Button("Show hidden items again", function()
        local n = 0
        for k in pairs(S().ignore) do S().ignore[k] = nil; n = n + 1 end
        NS.Print("Buff Bar: " .. n .. " hidden item(s) shown again.")
        Changed()
    end)

    page:Section("Look", "Size, layout and buff status")
    page:Cycle("When the buff is already on you", {
        { "dim", "Dim the button" }, { "hide", "Hide the button" }, { "normal", "Leave it as is" },
    }, function() return S().activeMode end, function(v) S().activeMode = v; Changed() end)
    page:Check("Show time left on active buffs", function() return S().timeLeft end,
        function(v) S().timeLeft = v; Changed() end)
    page:Slider("Low stock: red count at or under (0 = off)", 0, 20, 1, function() return S().lowStock end,
        function(v) S().lowStock = v; Changed() end)
    page:Slider("Button size", 24, 64, 2, function() return S().size end, function(v) S().size = v; Changed() end)
    page:Slider("Spacing", 0, 12, 1, function() return S().spacing end, function(v) S().spacing = v; Changed() end)
    page:Slider("Buttons per row", 1, 24, 1, function() return S().perRow end,
        function(v) S().perRow = v; Changed() end)
    page:Slider("Most buttons shown", 1, MAX_BUTTONS, 1, function() return S().maxButtons end,
        function(v) S().maxButtons = v; Changed() end)
    page:Check("Vertical (rows become columns)", function() return S().vertical end,
        function(v) S().vertical = v; Changed() end)
    page:Check("Fade until the mouse is over it", function() return S().fade end,
        function(v) S().fade = v; Changed() end)
    page:Note("Changes made in combat show once combat ends; the game doesn't let addons move "
        .. "clickable buttons in combat.")

    page:Section("Position", "Where the bar sits")
    page:Check("Lock position", function() return S().locked end, function(v) S().locked = v; Changed() end)
    page:Button("Move it back to the top centre", function()
        local p = S().point
        p[1], p[2], p[3], p[4] = "TOP", "TOP", 0, -40
        Changed()
    end, 240)
    page:Button("Test: fill the bar with sample icons", function() M.Test() end)
end

function M:Diagnose()
    local st = M.stats
    local c = st.cats or {}
    NS.Print(string.format("  on bar %d   found: food %d, elixirs %d, weapon %d, potions %d, other %d   pinned %d",
        st.found, c.food or 0, c.elixirs or 0, c.weapon or 0, c.potions or 0, c.other or 0, #S().pinned))
    NS.Print(string.format("  only buffs %s   left out (no buff) %d   text not loaded yet %d   text from %s   client gives no text %s",
        tostring(S().onlyBuffs), st.noBuff or 0, st.unknown or 0, tostring(st.textHow), tostring(st.noText)))
    NS.Print(string.format("  scans %d   layouts %d   waiting for combat to end %s   clicks %d   aura read by %s   secret reads %d   last error %s",
        st.scans, st.layouts, tostring(pending), st.clicks, tostring(st.auraHow), st.secret,
        tostring(st.lastError or "-")))
end
