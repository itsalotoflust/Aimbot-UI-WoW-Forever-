--[[
  Aimbot UI - Disenchant Helper (2.25.0)
  1. Highlights items in your bags that you can disenchant: a coloured border and a small
     Disenchant icon in the corner. Works with Bagnon and with the default bags.
  2. A Disenchant button: each click (or each press of a key bound to it) disenchants the next
     eligible item in your bags. The game only lets an addon cast a spell from a real click or
     key press, one cast per press, so this is the fastest way the game allows.

  Which items count: green / blue / purple weapons and armour (rings, necks, trinkets and cloaks
  too), never shirts, tabards or cosmetic items. By default only soulbound green items, so
  nothing you could sell goes by accident: Bind on Equip, blue and purple items each need their
  own switch. Right-click the button to skip the next item for this session; Shift+right-click
  to never disenchant that item.

  How it finds bag slots: one post-hook on SetItemButtonQuality, the function both Bagnon and the
  default bags call when they draw an item's border. Only buttons that can say which bag and slot
  they show are used (Bagnon: GetBag / GetID, default bags: GetBagID / GetID). The highlight is our
  own textures created on those buttons; no field is written on any frame that isn't ours.
]]

local ADDON_NAME, NS = ...

local DISENCHANT = 13262
local BUTTON_NAME = "AimbotUIDisenchantButton"

local M = {
    name = "Disenchant Helper",
    group = "QoL",
    desc = "Highlights items in your bags that you can disenchant, and gives you a button (or key) "
        .. "that disenchants the next one each time you press it. Works with Bagnon and the default bags.",
    defaults = {
        enabled     = true,
        highlight   = true,
        border      = true,
        icon        = true,
        color       = { 0.15, 1.00, 0.25, 1 },   -- vibrant green (2.28.1; was purple)
        boe         = false,      -- include Bind on Equip items (they could be sold)
        rare        = false,      -- include blue items
        epic        = false,      -- include purple items
        button      = true,
        locked      = false,
        size        = 40,
        point       = { "CENTER", "CENTER", 260, -120 },
        ignore      = {},         -- itemID -> true: never disenchant or highlight
    },
}
NS.RegisterModule("disenchant", M)

local function S() return NS.db.mod.disenchant end

-- Key Bindings > AddOns > Aimbot UI: a key that presses the Disenchant button (Bindings.xml)
_G["BINDING_NAME_CLICK " .. BUTTON_NAME .. ":LeftButton"] = "Disenchant next item"
local IsSecret = NS.IsSecret

M.stats = { hooked = false, buttons = 0, bagnon = 0, blizzard = 0, eligible = 0, casts = 0,
    skipped = 0, lastError = nil, secret = 0 }

-- forward declarations
local Refresh, UpdateButton, Eligible, NextTarget

----------------------------------------------------------------------
-- Item rules
----------------------------------------------------------------------
local NO_DISENCHANT_SLOT = { INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_NON_EQUIP_IGNORE = true,
    INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true, INVTYPE_THROWN = false }

local sessionSkip = {}            -- "bag:slot:itemID" -> true (right-click / too-low skill)
local cantDisenchant = {}         -- itemID -> true (the game said it can't be disenchanted)

local function Clean(v)
    if v == nil then return nil end
    if IsSecret(v) then M.stats.secret = M.stats.secret + 1; return nil end
    return v
end

local function ContainerInfo(bag, slot)
    if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and type(info) == "table" then return info end
    return nil
end

local function ItemClass(itemID)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return nil end
    local ok, _, _, _, equipLoc, _, classID, subClassID = pcall(f, itemID)
    if not ok then return nil end
    return Clean(classID), Clean(subClassID), Clean(equipLoc)
end

-- Can this item be disenchanted by our rules? Returns true/false, and why not (for diag).
-- Pure on its inputs: quality, bound, classID, subClassID, equipLoc, itemID.
function Eligible(quality, bound, classID, subClassID, equipLoc, itemID)
    local s = S()
    if not itemID then return false, "empty" end
    if s.ignore[itemID] or cantDisenchant[itemID] then return false, "ignored" end
    if type(quality) ~= "number" then return false, "no quality" end
    if quality == 2 then
        -- green: always allowed
    elseif quality == 3 then
        if not s.rare then return false, "blue off" end
    elseif quality == 4 then
        if not s.epic then return false, "purple off" end
    else
        return false, "quality"
    end
    if classID ~= 2 and classID ~= 4 then return false, "not gear" end
    if classID == 4 and subClassID == 5 then return false, "cosmetic" end
    if equipLoc == nil or equipLoc == "" or NO_DISENCHANT_SLOT[equipLoc] then return false, "slot" end
    if not bound and not s.boe then return false, "bind on equip" end
    return true
end

local function SlotEligible(bag, slot)
    local info = ContainerInfo(bag, slot)
    if not info then return false end
    local itemID = Clean(info.itemID)
    if not itemID then return false end
    if Clean(info.isLocked) then return false end
    local classID, subClassID, equipLoc = ItemClass(itemID)
    return Eligible(Clean(info.quality), Clean(info.isBound), classID, subClassID, equipLoc, itemID), itemID, info
end
M._t_SlotEligible = SlotEligible

local function Bags()
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    return 0, last
end

local function KnowsDisenchant()
    if IsPlayerSpell then
        local ok, v = pcall(IsPlayerSpell, DISENCHANT)
        if ok and not IsSecret(v) then return v and true or false end
    end
    if IsSpellKnown then
        local ok, v = pcall(IsSpellKnown, DISENCHANT)
        if ok and not IsSecret(v) then return v and true or false end
    end
    return false
end

local function SpellName()
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, DISENCHANT)
        if ok and type(n) == "string" and not IsSecret(n) then return n end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, DISENCHANT)
        if ok and type(n) == "string" and not IsSecret(n) then return n end
    end
    return "Disenchant"
end

local function SpellIcon()
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, DISENCHANT)
        if ok and t and not IsSecret(t) then return t end
    end
    return "Interface\\Icons\\INV_Enchant_Disenchant"
end

-- First eligible slot in bag order that isn't skipped. Returns bag, slot, itemID, count.
function NextTarget()
    local first, last = Bags()
    local found, count
    count = 0
    for bag = first, last do
        local n = 0
        if C_Container and C_Container.GetContainerNumSlots then
            local ok, v = pcall(C_Container.GetContainerNumSlots, bag)
            if ok and type(v) == "number" and not IsSecret(v) then n = v end
        end
        for slot = 1, n do
            local ok, itemID = SlotEligible(bag, slot)
            if ok then
                count = count + 1
                if not found and not sessionSkip[bag .. ":" .. slot .. ":" .. itemID] then
                    found = { bag, slot, itemID }
                end
            end
        end
    end
    M.stats.eligible = count
    if found then return found[1], found[2], found[3], count end
    return nil, nil, nil, count
end
M._t_NextTarget = NextTarget

----------------------------------------------------------------------
-- Highlights on bag buttons
----------------------------------------------------------------------
local overlays = setmetatable({}, { __mode = "k" })    -- item button -> our overlay
local known = setmetatable({}, { __mode = "k" })       -- item button -> "bagnon" / "blizzard"

-- Which bag / slot an item button shows, or nil. Never writes to the button.
local function ButtonSlot(btn)
    if type(btn) ~= "table" then return nil end
    local bag, slot, kind
    if type(btn.GetBag) == "function" then
        local ok, v = pcall(btn.GetBag, btn)
        if ok and v ~= nil then
            bag, kind = v, "bagnon"
            if type(btn.IsCached) == "function" then
                local ok2, cached = pcall(btn.IsCached, btn)
                if ok2 and cached and not IsSecret(cached) then return nil end  -- another character / offline bank
            end
        end
    end
    if bag == nil and type(btn.GetBagID) == "function" then
        local ok, v = pcall(btn.GetBagID, btn)
        if ok then bag = v end
        kind = "blizzard"
    end
    if bag == nil or IsSecret(bag) or type(bag) ~= "number" then return nil end
    local first, last = Bags()
    if bag < first or bag > last then return nil end      -- bank and others: not disenchantable from here
    if type(btn.GetID) ~= "function" then return nil end
    local ok, id = pcall(btn.GetID, btn)
    if not ok or IsSecret(id) or type(id) ~= "number" or id < 1 then return nil end
    slot = id
    return bag, slot, kind
end
M._t_ButtonSlot = ButtonSlot

local function Overlay(btn)
    local o = overlays[btn]
    if o then return o end
    o = {}
    local function Edge(p1, p2, w, h)
        local t = btn:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetPoint(p1, btn, p1, 0, 0)
        t:SetPoint(p2, btn, p2, 0, 0)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    o.edges = {
        Edge("TOPLEFT", "TOPRIGHT", nil, 2), Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2),
        Edge("TOPLEFT", "BOTTOMLEFT", 2, nil), Edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil),
    }
    o.icon = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    o.icon:SetSize(14, 14)
    o.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    o.icon:SetTexture(SpellIcon())
    pcall(o.icon.SetTexCoord, o.icon, 0.08, 0.92, 0.08, 0.92)
    overlays[btn] = o
    M.stats.buttons = M.stats.buttons + 1
    return o
end

local function ShowOverlay(btn, on)
    local o = overlays[btn]
    if not on then
        if o then
            for _, e in ipairs(o.edges) do e:Hide() end
            o.icon:Hide()
        end
        return
    end
    o = Overlay(btn)
    local s, c = S(), S().color
    for _, e in ipairs(o.edges) do
        e:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        e:SetShown(s.border)
    end
    o.icon:SetShown(s.icon)
end

local function UpdateItemButton(btn)
    local bag, slot, kind = ButtonSlot(btn)
    if not bag then
        if overlays[btn] then ShowOverlay(btn, false) end
        return
    end
    if not known[btn] then
        known[btn] = kind
        M.stats[kind] = (M.stats[kind] or 0) + 1
    end
    local s = S()
    local on = s.enabled and s.highlight and KnowsDisenchant() and SlotEligible(bag, slot) or false
    ShowOverlay(btn, on and true or false)
end
M._t_UpdateItemButton = UpdateItemButton

local function HookButtons()
    if M.stats.hooked then return end
    if type(SetItemButtonQuality) ~= "function" then return end
    hooksecurefunc("SetItemButtonQuality", function(btn)
        local ok, err = pcall(UpdateItemButton, btn)
        if not ok then NS.ReportError("Disenchant Helper", err) end
    end)
    M.stats.hooked = true
end

-- Re-check every bag button we've seen (bag contents, settings or skill changed).
local function RefreshHighlights()
    for btn in pairs(known) do
        local ok, err = pcall(UpdateItemButton, btn)
        if not ok then NS.ReportError("Disenchant Helper", err) end
    end
end

----------------------------------------------------------------------
-- The Disenchant button (secure: a real click or key press casts)
----------------------------------------------------------------------
local button, icon, countText, bg
local current            -- { bag, slot, itemID } the button will disenchant next
local pendingAttr = false

local function SetClicks()
    if not button then return end
    -- keys bound with /click or a binding arrive as "down" when the game is set to act on key
    -- down; mouse clicks arrive as "up" otherwise. Registering just one avoids two casts per press.
    local down = false
    if GetCVarBool then
        local ok, v = pcall(GetCVarBool, "ActionButtonUseKeyDown")
        if ok and not IsSecret(v) then down = v and true or false end
    end
    button:RegisterForClicks(down and "AnyDown" or "AnyUp")
    M.stats.clicks = down and "down" or "up"
end

-- Point the secure button at the next item. Out of combat only (the game forbids it in combat).
function UpdateButton()
    if not button then return end
    local bag, slot, itemID, count = NextTarget()
    current = bag and { bag, slot, itemID } or nil
    local s = S()
    local can = s.enabled and s.button and KnowsDisenchant()
    if InCombatLockdown and InCombatLockdown() then
        pendingAttr = true
    else
        pendingAttr = false
        if bag and can then
            button:SetAttribute("type1", "macro")
            button:SetAttribute("macrotext1", "/cast " .. SpellName() .. "\n/use " .. bag .. " " .. slot)
        else
            button:SetAttribute("type1", nil)
            button:SetAttribute("macrotext1", nil)
        end
        button:SetShown(can and true or false)
    end
    if bag then
        local info = ContainerInfo(bag, slot)
        local tex = info and Clean(info.iconFileID)
        icon:SetTexture(tex or SpellIcon())
        icon:SetDesaturated(false)
    else
        icon:SetTexture(SpellIcon())
        icon:SetDesaturated(true)
    end
    countText:SetText(count and count > 0 and tostring(count) or "")
end
M._t_UpdateButton = UpdateButton

function Refresh()
    RefreshHighlights()
    UpdateButton()
end

local function SavePosition()
    local point, _, relPoint, x, y = button:GetPoint()
    if point then
        local p = S().point
        p[1], p[2], p[3], p[4] = point, relPoint, x, y
    end
end

local function ApplyButton()
    if not button then return end
    local s = S()
    if not (InCombatLockdown and InCombatLockdown()) then
        button:SetSize(s.size, s.size)
        button:ClearAllPoints()
        local p = s.point
        button:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    bg:SetColorTexture(0, 0, 0, s.locked and 0.6 or 0.8)
    button.unlockTint:SetShown(not s.locked)
end

local function ShowTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if current then
        local info = ContainerInfo(current[1], current[2])
        local link = info and Clean(info.hyperlink)
        GameTooltip:AddLine(SpellName(), 0.7, 0.35, 1)
        GameTooltip:AddLine(link or "next item", 1, 1, 1)
    else
        GameTooltip:AddLine(SpellName(), 0.7, 0.35, 1)
        GameTooltip:AddLine("Nothing to disenchant in your bags.", 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("Click: disenchant it", 0.6, 0.9, 0.6)
    GameTooltip:AddLine("Right-click: skip it this session", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Shift+right-click: never disenchant this item", 0.6, 0.6, 0.6)
    if not S().locked then GameTooltip:AddLine("Drag to move (lock it in the settings)", 0.4, 0.7, 1) end
    GameTooltip:Show()
end

local function Ensure()
    if button then return end
    button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        if not S().locked and not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
    end)
    button:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -2, 2)
    bg:SetPoint("BOTTOMRIGHT", 2, -2)
    icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    button.unlockTint = button:CreateTexture(nil, "OVERLAY")
    button.unlockTint:SetAllPoints()
    button.unlockTint:SetColorTexture(0.2, 0.6, 1, 0.3)
    countText = button:CreateFontString(nil, "OVERLAY")
    countText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    countText:SetPoint("BOTTOMRIGHT", -2, 2)
    SetClicks()
    -- right-click is handled here (insecure is fine: it only changes our own skip lists)
    button:SetScript("PostClick", function(_, mouse)
        if mouse == "RightButton" and current then
            if IsShiftKeyDown and IsShiftKeyDown() then
                S().ignore[current[3]] = true
                NS.Print("Disenchant Helper: this item will never be disenchanted (clear the list in the settings).")
            else
                sessionSkip[current[1] .. ":" .. current[2] .. ":" .. current[3]] = true
                M.stats.skipped = M.stats.skipped + 1
            end
            Refresh()
        elseif mouse ~= "RightButton" and current then
            M.stats.casts = M.stats.casts + 1
            M.lastTry = { current[1], current[2], current[3], GetTime() }
        end
        if GameTooltip:IsOwned(button) then ShowTip(button) end
    end)
    button:SetScript("OnEnter", ShowTip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ApplyButton()
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local refreshQueued = false
local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        local ok, err = pcall(Refresh)
        if not ok then NS.ReportError("Disenchant Helper", err) end
    end)
end

local function OnError(_, _, msg)
    -- the game refused the last disenchant: skip that item so the next press moves on
    if type(msg) ~= "string" or IsSecret(msg) or not M.lastTry then return end
    if GetTime() - M.lastTry[4] > 2 then return end
    local key = M.lastTry[1] .. ":" .. M.lastTry[2] .. ":" .. M.lastTry[3]
    if SPELL_FAILED_CANT_BE_DISENCHANTED and msg == SPELL_FAILED_CANT_BE_DISENCHANTED then
        cantDisenchant[M.lastTry[3]] = true
        M.stats.lastError = "can't be disenchanted"
        QueueRefresh()
    elseif (SPELL_FAILED_LOW_CASTLEVEL and msg == SPELL_FAILED_LOW_CASTLEVEL)
        or (SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL and msg == SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL) then
        sessionSkip[key] = true
        M.stats.lastError = "skill too low"
        QueueRefresh()
    end
end

-- 2.28.1: the default highlight went from purple to vibrant green. Saved settings hold the colour,
-- so a saved colour that is still the old purple default is switched once; a colour you picked
-- yourself is kept. (colorV is not in the defaults, so it's only set here.)
local OLD_PURPLE = { 0.70, 0.35, 1.00 }
local function MigrateColor()
    local s = S()
    if s.colorV then return end
    s.colorV = 1
    local c = s.color
    if type(c) ~= "table" then s.color = { 0.15, 1.00, 0.25, 1 }; return end
    local same = true
    for i = 1, 3 do
        if type(c[i]) ~= "number" or math.abs(c[i] - OLD_PURPLE[i]) > 0.01 then same = false end
    end
    if same then c[1], c[2], c[3] = 0.15, 1.00, 0.25 end
end
M._t_MigrateColor = MigrateColor

local hooked = false
function M:Init()
    MigrateColor()
    Ensure()
    HookButtons()
    if not hooked then
        hooked = true
        NS.On("BAG_UPDATE_DELAYED", QueueRefresh)
        NS.On("PLAYER_REGEN_ENABLED", function() if pendingAttr then QueueRefresh() end end)
        NS.On("LOOT_CLOSED", QueueRefresh)
        NS.On("SPELLS_CHANGED", QueueRefresh)
        NS.On("SKILL_LINES_CHANGED", QueueRefresh)
        NS.On("UI_ERROR_MESSAGE", OnError)
        NS.On("CVAR_UPDATE", function() if not (InCombatLockdown and InCombatLockdown()) then SetClicks() end end)
    end
    QueueRefresh()
end

function M:Apply()
    Ensure()
    HookButtons()
    ApplyButton()
    Refresh()
end

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
function M.Build(page)
    page:Section("Which items", "What counts as disenchantable")
    page:Note("Green weapons and armour (rings, necks, trinkets and cloaks too) that are soulbound. "
        .. "Shirts, tabards and cosmetic items never count.")
    page:Check("Include Bind on Equip items (you could sell these)", function() return S().boe end,
        function(v) S().boe = v; Refresh() end)
    page:Check("Include blue (rare) items", function() return S().rare end,
        function(v) S().rare = v; Refresh() end)
    page:Check("Include purple (epic) items", function() return S().epic end,
        function(v) S().epic = v; Refresh() end)
    page:Button("Clear the never-disenchant list", function()
        local n = 0
        for k in pairs(S().ignore) do S().ignore[k] = nil; n = n + 1 end
        for k in pairs(sessionSkip) do sessionSkip[k] = nil end
        NS.Print("Disenchant Helper: cleared " .. n .. " item(s) from the never list, and this session's skips.")
        Refresh()
    end)

    page:Section("Highlight", "Marks in your bags")
    page:Check("Highlight disenchantable items", function() return S().highlight end,
        function(v) S().highlight = v; Refresh() end)
    page:Check("Coloured border", function() return S().border end,
        function(v) S().border = v; Refresh() end)
    page:Check("Disenchant icon in the corner", function() return S().icon end,
        function(v) S().icon = v; Refresh() end)
    page:Color("Border colour", function() return S().color end,
        function(r, g, b) local c = S().color; c[1], c[2], c[3] = r, g, b; Refresh() end)
    page:Note("Works in Bagnon and in the default bags. Only shows once you know Disenchant.")

    page:Section("Disenchant button", "One press, one item")
    page:Check("Show the Disenchant button", function() return S().button end,
        function(v) S().button = v; Refresh() end)
    page:Note("Each click disenchants the next highlighted item. The game only allows one cast per click "
        .. "or key press, so it can't empty your bags on its own. To use a key, set one in the game's "
        .. "Key Bindings > AddOns > Aimbot UI > \"Disenchant next item\" (or make a macro with /click "
        .. BUTTON_NAME .. "). Turn on Auto Loot so the dust and essences go straight to your bags.")
    page:Slider("Button size", 24, 72, 2, function() return S().size end,
        function(v) S().size = v; ApplyButton() end)
    page:Check("Lock position", function() return S().locked end,
        function(v) S().locked = v; ApplyButton() end)
    page:Button("Move it back", function()
        local p = S().point
        p[1], p[2], p[3], p[4] = "CENTER", "CENTER", 260, -120
        ApplyButton()
    end)
end

function M:Diagnose()
    local st = M.stats
    local s = S()
    local n = 0
    for _ in pairs(s.ignore) do n = n + 1 end
    local attr = button and button:GetAttribute("macrotext1")
    NS.Print(string.format("  knows Disenchant %s   eligible in bags %d   next %s   never-list %d   skipped %d   tries %d   last refusal %s",
        tostring(KnowsDisenchant()), st.eligible or 0,
        current and (current[1] .. "/" .. current[2] .. " item " .. current[3]) or "none",
        n, st.skipped, st.casts, tostring(st.lastError or "-")))
    NS.Print(string.format("  bag hook %s   buttons seen: Bagnon %d, default %d   highlighted so far %d   clicks on key %s   in combat wait %s   secret reads %d",
        tostring(st.hooked), st.bagnon or 0, st.blizzard or 0, st.buttons, tostring(st.clicks),
        tostring(pendingAttr), st.secret))
    NS.Print("  button macro: " .. (attr and attr:gsub("\n", " | ") or "(none)"))
end
