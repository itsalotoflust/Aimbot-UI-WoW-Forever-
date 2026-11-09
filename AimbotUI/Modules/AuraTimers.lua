--[[
  Aimbot UI - Aura Timers
  Shows the time left as numbers on buff and debuff icons: your DoTs and crowd control on the
  target, focus and enemy nameplates.

  The game already draws these numbers on cooldown swipes (the "countdownForCooldowns" setting),
  but it turns them off for the small aura icons on unit frames and nameplates. This module
  turns them back on for those icons with the Cooldown widget's own SetHideCountdownNumbers,
  and can make the numbers bigger. The game does the counting, so it also works when the client
  hides the real aura times from addons ("secret" values): this module never reads them.

  Where the game draws no cooldown on an icon at all (enemy players' buffs), a numbers-only
  cooldown of our own is put on the icon and given the aura's time.

  Only method calls on the aura icons' cooldowns; no fields are written on Blizzard frames.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Aura Timers",
    group = "Combat",
    desc = "Time-left numbers on buff and debuff icons: your DoTs and CC on target, focus and nameplates.",
    defaults = {
        enabled  = true,
        target   = true,
        focus    = true,
        plates   = true,
        resize   = true,
        size     = 12,              -- number size on target / focus icons
        plateSize = 10,             -- number size on nameplate icons
        own = {                     -- our own aura icons for target and focus (this client hides its own from addons)
            enabled  = true,
            hideGame = true,        -- hide the game's aura icons so they don't show twice
            buffs    = true,
            debuffs  = true,
            onlyMine = false,       -- debuffs: only the ones you cast
            iconSize = 22,
            perRow   = 8,
            max      = 16,          -- per kind
            x = 5, y = 32,          -- from the frame's bottom left
        },
    },
}
NS.RegisterModule("auratimers", M)

local function S() return NS.db.mod.auratimers end
local IsSecret = NS.IsSecret

local CVAR = "countdownForCooldowns"
local touched = setmetatable({}, { __mode = "k" })   -- cooldown -> { font, size, flags } (our own table)
local savedCVar                                        -- the player's value before we changed it
M.stats = { target = 0, focus = 0, plates = 0, targetOwn = 0, focusOwn = 0, cvar = "?", how = "none" }

----------------------------------------------------------------------
-- Finding the aura cooldowns
----------------------------------------------------------------------
local function IsCooldown(obj)
    if not obj or not obj.IsObjectType then return false end
    local ok, is = pcall(obj.IsObjectType, obj, "Cooldown")
    return ok and not IsSecret(is) and is
end

-- Walks the children of root (a few levels down) and calls fn on every Cooldown found.
local function EachCooldown(root, depth, fn)
    if not root or not root.GetChildren or depth < 0 then return 0 end
    local okK, kids = pcall(function() return { root:GetChildren() } end)
    if not okK then return 0 end
    local n = 0
    for _, kid in ipairs(kids) do
        if IsCooldown(kid) then
            fn(kid); n = n + 1
        else
            n = n + EachCooldown(kid, depth - 1, fn)
        end
    end
    return n
end

-- Unit frames: only cooldowns that sit on an aura icon (the auraPools), not other swipes.
local function UnitFrameAuraCooldowns(frame, fn)
    local pools = frame and frame.auraPools
    local n = 0
    if pools and pools.EnumerateActive then
        local ok = pcall(function()
            for obj in pools:EnumerateActive() do
                local cd = obj.Cooldown or obj.cooldown
                if IsCooldown(cd) then fn(cd); n = n + 1
                else n = n + EachCooldown(obj, 2, fn) end
            end
        end)
        if ok then return n end
    end
    -- older layouts: aura buttons named <Frame>Buff1 / <Frame>Debuff1 with a Cooldown child
    local name = frame and frame.GetName and frame:GetName()
    if name then
        for _, kind in ipairs({ "Buff", "Debuff" }) do
            for i = 1, 40 do
                local cd = _G[name .. kind .. i .. "Cooldown"]
                if not cd then break end
                if IsCooldown(cd) then fn(cd); n = n + 1 end
            end
        end
    end
    return n
end

----------------------------------------------------------------------
-- Showing / hiding the numbers
----------------------------------------------------------------------
local function Show(cd, size)
    if not touched[cd] then
        local rec = {}
        local okF, fs = pcall(cd.GetCountdownFontString, cd)
        if okF and fs and fs.GetFont then
            local okG, font, sz, flags = pcall(fs.GetFont, fs)
            if okG then rec.font, rec.size, rec.flags = font, sz, flags end
        end
        touched[cd] = rec
    end
    pcall(cd.SetHideCountdownNumbers, cd, false)
    local rec = touched[cd]
    if rec.font then
        local okF, fs = pcall(cd.GetCountdownFontString, cd)
        if okF and fs then
            if S().resize then
                pcall(fs.SetFont, fs, rec.font, size, "OUTLINE")
            else
                pcall(fs.SetFont, fs, rec.font, rec.size, rec.flags)
            end
        end
    end
end

local function Restore(cd)
    local rec = touched[cd]
    if not rec then return end
    pcall(cd.SetHideCountdownNumbers, cd, true)
    if rec.font then
        local okF, fs = pcall(cd.GetCountdownFontString, cd)
        if okF and fs then pcall(fs.SetFont, fs, rec.font, rec.size, rec.flags) end
    end
    touched[cd] = nil
end

local function ApplyCVar(on)
    local okG, cur = pcall(GetCVar, CVAR)
    if not okG or cur == nil then M.stats.cvar = "missing"; return end
    if on then
        if cur ~= "1" then
            if savedCVar == nil then savedCVar = cur; S().savedCVar = cur end
            pcall(SetCVar, CVAR, "1")
        end
    else
        local back = savedCVar or S().savedCVar
        if back ~= nil then pcall(SetCVar, CVAR, back) end
        savedCVar, S().savedCVar = nil, nil
    end
    local okR, now = pcall(GetCVar, CVAR)
    M.stats.cvar = okR and tostring(now) or "?"
end

----------------------------------------------------------------------
-- Fallback: icons the game draws no cooldown on (enemy players' buffs on this client) get our
-- own numbers-only cooldown, filled from the aura's own time. It is created as a child of the
-- icon so it shows and hides with it. The time is handed straight to the Cooldown widget
-- (duration object or expiration time), so secret times work and are never read by us.
----------------------------------------------------------------------
local overlays = setmetatable({}, { __mode = "k" })    -- aura icon -> our cooldown (our own table)

local function Overlay(icon)
    local cd = overlays[icon]
    if cd then return cd end
    cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    local art = icon.Icon or icon.icon or icon.Texture or icon.IconTexture
    if not art and icon.GetName then
        local okN, name = pcall(icon.GetName, icon)
        if okN and type(name) == "string" then art = _G[name .. "Icon"] end
    end
    if art and art.GetObjectType then cd:SetAllPoints(art) else cd:SetAllPoints(icon) end
    pcall(cd.SetDrawSwipe, cd, false)
    pcall(cd.SetDrawEdge, cd, false)
    pcall(cd.SetDrawBling, cd, false)
    overlays[icon] = cd
    return cd
end

-- Returns true when the cooldown was given the aura's time.
local function Feed(cd, unit, auraID)
    local CU = C_UnitAuras
    if not CU then return false end
    if CU.GetAuraDuration and cd.SetCooldownFromDurationObject then
        local ok, dur = pcall(CU.GetAuraDuration, unit, auraID)
        if ok and dur ~= nil and pcall(cd.SetCooldownFromDurationObject, cd, dur) then
            M.stats.how = "duration object"
            return true
        end
    end
    if not CU.GetAuraDataByAuraInstanceID then return false end
    local ok, a = pcall(CU.GetAuraDataByAuraInstanceID, unit, auraID)
    if not ok or type(a) ~= "table" then return false end
    local exp, dur = a.expirationTime, a.duration
    if exp == nil or dur == nil then return false end
    if cd.SetCooldownFromExpirationTime and pcall(cd.SetCooldownFromExpirationTime, cd, exp, dur) then
        M.stats.how = "expiration time"
        return true
    end
    if not IsSecret(exp) and not IsSecret(dur) and type(dur) == "number" and dur > 0 and type(exp) == "number" then
        cd:SetCooldown(exp - dur, dur)
        M.stats.how = "SetCooldown"
        return true
    end
    return false
end

local function Shown(obj)
    local ok, v = pcall(obj.IsShown, obj)
    return ok and not IsSecret(v) and v and true or false
end

-- An aura icon: a frame with an aura id, or with a Cooldown plus an icon texture.
local function IsAuraIcon(obj)
    if type(obj) ~= "table" or IsCooldown(obj) then return false end
    local id = rawget(obj, "auraInstanceID")
    if type(id) == "number" and not IsSecret(id) then return true end
    local cd = rawget(obj, "Cooldown") or rawget(obj, "cooldown")
    local art = rawget(obj, "Icon") or rawget(obj, "icon")
    if cd ~= nil and IsCooldown(cd) and art ~= nil then return true end
    -- classic style: named buttons (TargetFrameBuff1) with <name>Icon / <name>Cooldown
    local okN, name = pcall(obj.GetName, obj)
    if okN and type(name) == "string" and (name:find("Buff%d+$") or name:find("Debuff%d+$")) then
        return true
    end
    return false
end

-- The game's cooldown on an icon, by key or by name.
local function IconCooldown(icon)
    local cd = icon.Cooldown or icon.cooldown
    if IsCooldown(cd) then return cd end
    local okN, name = pcall(icon.GetName, icon)
    if okN and type(name) == "string" then
        cd = _G[name .. "Cooldown"]
        if IsCooldown(cd) then return cd end
    end
end

-- The aura's instance id: from the icon, or looked up from its slot number (classic style).
local function IconAuraID(icon, unit)
    local id = icon.auraInstanceID
    if type(id) == "number" and not IsSecret(id) then return id end
    -- some layouts keep the aura's data in a table on the icon
    for _, k in ipairs({ "auraData", "aura", "buttonInfo", "data", "auraInfo", "info" }) do
        local okT, t = pcall(rawget, icon, k)
        if okT and type(t) == "table" then
            local okA, aid = pcall(rawget, t, "auraInstanceID")
            if okA and type(aid) == "number" and not IsSecret(aid) then return aid end
        end
    end
    local okI, index = pcall(icon.GetID, icon)
    if not okI or type(index) ~= "number" or IsSecret(index) or index < 1 then return nil end
    local okN, name = pcall(icon.GetName, icon)
    local harmful = (okN and type(name) == "string" and name:find("Debuff"))
        or icon.isDebuff == true or icon.isHarmful == true
    local filter = harmful and "HARMFUL" or "HELPFUL"
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local okA, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
        if okA and type(a) == "table" then
            local aid = a.auraInstanceID
            if type(aid) == "number" and not IsSecret(aid) then return aid end
        end
    end
    return nil
end

-- Walks the children of root and calls fn on every aura icon found (not inside an icon).
local function WalkIcons(root, depth, fn, seen)
    if not root or not root.GetChildren or depth < 0 then return end
    local okK, kids = pcall(function() return { root:GetChildren() } end)
    if not okK then return end
    for _, kid in ipairs(kids) do
        if not seen[kid] then
            seen[kid] = true
            if IsAuraIcon(kid) then fn(kid) else WalkIcons(kid, depth - 1, fn, seen) end
        end
    end
end

-- Any icon pools kept on the frame under another name (buffPool, debuffPool, ...). Read only.
local function FramePools(frame)
    local list = {}
    local ok = pcall(function()
        for k, v in pairs(frame) do
            if type(k) == "string" and type(v) == "table" and k ~= "auraPools"
                and type(v.EnumerateActive) == "function" then
                list[#list + 1] = { key = k, pool = v }
            end
        end
    end)
    table.sort(list, function(a, b) return a.key < b.key end)
    return ok and list or {}
end
M._t_FramePools = FramePools

-- This client keeps the target / focus aura icons in <Frame>.TargetFrameContent.TargetFrameContentContextual.Auras
local function AurasBox(frame)
    local ok, box = pcall(function()
        return frame.TargetFrameContent.TargetFrameContentContextual.Auras
    end)
    if ok and type(box) == "table" and box.GetChildren then return box end
end
M._t_AurasBox = AurasBox

local function Squareish(obj, lo, hi)
    local okW, w = pcall(obj.GetWidth, obj)
    local okH, h = pcall(obj.GetHeight, obj)
    if not okW or not okH or IsSecret(w) or IsSecret(h) then return false end
    return w >= lo and w <= hi and math.abs(w - h) <= 8
end

M.stats.layout = "none"
local function EachAuraIcon(frame, fn)
    local function Layout(v) if frame == TargetFrame then M.stats.layout = v end end
    local pools = frame and frame.auraPools
    if pools and pools.EnumerateActive then
        local ok = pcall(function()
            for obj in pools:EnumerateActive() do fn(obj) end
        end)
        if ok then Layout("aura pools"); return true end
    end
    if not frame then return false end
    -- pools under another name
    local named = FramePools(frame)
    if #named > 0 then
        local seen, keys = {}, {}
        for _, e in ipairs(named) do
            pcall(function()
                for obj in e.pool:EnumerateActive() do
                    if not seen[obj] and IsAuraIcon(obj) then seen[obj] = true; fn(obj) end
                end
            end)
            keys[#keys + 1] = e.key
        end
        if next(seen) then Layout("pools: " .. table.concat(keys, ",")); return true end
    end
    -- the Auras container: every shown icon-sized frame in it is an aura icon
    local box = AurasBox(frame)
    if box then
        local n = 0
        local okK, kids = pcall(function() return { box:GetChildren() } end)
        if okK then
            for _, kid in ipairs(kids) do
                if not IsCooldown(kid) and Shown(kid) and (IsAuraIcon(kid) or Squareish(kid, 8, 64)) then
                    n = n + 1; fn(kid)
                else
                    -- one level down (an icon inside a holder frame)
                    WalkIcons(kid, 2, function(icon) if Shown(icon) then n = n + 1; fn(icon) end end, {})
                end
            end
        end
        if n > 0 then Layout("Auras container"); return true end
    end
    -- this client keeps the icons elsewhere: look for them among the frame's children
    WalkIcons(frame, 6, function(icon) if Shown(icon) then fn(icon) end end, {})
    Layout("searched children")
    return true
end

local function DoUnitFrame(key, frame)
    local s = S()
    local on = s.enabled and s[key]
    local found, own = 0, 0
    local done = EachAuraIcon(frame, function(icon)
        local bcd = IconCooldown(icon)
        local mine = overlays[icon]
        if not on then
            if bcd then Restore(bcd) end
            if mine then Restore(mine); mine:Hide() end
            return
        end
        found = found + 1
        if bcd and Shown(bcd) then
            -- the game runs a cooldown on this icon: just show its numbers
            Show(bcd, s.size)
            if mine then mine:Hide() end
            return
        end
        local id = IconAuraID(icon, key)
        if not id then
            if mine then mine:Hide() end
            return
        end
        local cd = Overlay(icon)
        if Feed(cd, key, id) then
            cd:Show()
            Show(cd, s.size)
            own = own + 1
        else
            cd:Hide()
        end
    end)
    if not done then
        -- older layouts without aura pools: just the game's cooldowns
        found = UnitFrameAuraCooldowns(frame, function(cd)
            if on then Show(cd, s.size) else Restore(cd) end
        end)
    end
    M.stats[key] = found
    M.stats[key .. "Own"] = own
end

local function DoPlate(unit)
    local s = S()
    local on = s.enabled and s.plates
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return 0 end
    local okP, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not okP or not plate then return 0 end
    local uf = plate.UnitFrame or plate
    local n = EachCooldown(uf, 5, function(cd)
        if on then Show(cd, s.plateSize) else Restore(cd) end
    end)
    -- icons with no running cooldown from the game get our own timer, as on the target frame
    WalkIcons(uf, 6, function(icon)
        local mine = overlays[icon]
        local bcd = IconCooldown(icon)
        local id = on and Shown(icon) and IconAuraID(icon, unit)
        if not on or (bcd and Shown(bcd)) or not Shown(icon) or not id then
            if mine then mine:Hide() end
            return
        end
        local cd = Overlay(icon)
        if Feed(cd, unit, id) then cd:Show(); Show(cd, s.plateSize); n = n + 1 else cd:Hide() end
    end, {})
    return n
end

local function DoAllPlates()
    local n = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, list = pcall(C_NamePlate.GetNamePlates)
        if ok and type(list) == "table" then
            for _, plate in ipairs(list) do
                local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
                if type(unit) == "string" then n = n + DoPlate(unit) end
            end
        end
    end
    M.stats.plates = n
end

----------------------------------------------------------------------
-- Our own aura icons for target and focus. On this client the game's target aura icons can't
-- be seen or changed by addons, so we draw our own row of icons from the aura data, each with a
-- Cooldown that counts down. Times go straight to the Cooldown widget (secret-safe).
-- The game's icons are hidden with SetAlpha on their container (a method call, nothing written).
----------------------------------------------------------------------
local function O() return S().own end
local own = {}                         -- unit -> { holder, buffs = {icons}, debuffs = {icons} }
M.stats.ownShown = { target = 0, focus = 0 }
M.stats.ownErr = nil

local function UnitFrameOf(unit) return unit == "target" and TargetFrame or FocusFrame end

local function NewIcon(holder)
    local b = CreateFrame("Frame", nil, holder)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 1)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.tex)
    pcall(b.cd.SetDrawEdge, b.cd, false)
    pcall(b.cd.SetDrawBling, b.cd, false)
    pcall(b.cd.SetReverse, b.cd, true)
    pcall(b.cd.SetHideCountdownNumbers, b.cd, false)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 2, -1)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        local ok = pcall(GameTooltip.SetUnitAura, GameTooltip, self.unit, self.index, self.filter)
        if ok then GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

local function OwnSet(unit)
    local set = own[unit]
    if set then return set end
    local frame = UnitFrameOf(unit)
    if not frame then return nil end
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(1, 1)
    set = { holder = holder, buffs = {}, debuffs = {} }
    own[unit] = set
    return set
end

local function StackText(unit, a)
    local CU = C_UnitAuras
    if CU and CU.GetAuraApplicationDisplayCount and a.auraInstanceID ~= nil then
        local ok, txt = pcall(CU.GetAuraApplicationDisplayCount, unit, a.auraInstanceID, 2, 99)
        if ok and txt ~= nil then return txt end
    end
    local n = a.applications
    if not IsSecret(n) and type(n) == "number" and n > 1 then return tostring(n) end
    return ""
end

-- Fills one kind (buffs or debuffs) and returns how many icons were shown and the rows used.
local function FillKind(unit, set, kind, startRow)
    local o = O()
    local list = set[kind]
    local filter = (kind == "buffs") and "HELPFUL" or (o.onlyMine and "HARMFUL|PLAYER" or "HARMFUL")
    local on = (kind == "buffs") and o.buffs or o.debuffs
    local size, perRow = o.iconSize, math.max(1, o.perRow)
    local n = 0
    if on and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, o.max do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok or type(a) ~= "table" then break end
            n = n + 1
            local b = list[n]
            if not b then b = NewIcon(set.holder); list[n] = b end
            b.unit, b.index, b.filter = unit, i, filter
            b:SetSize(size, size)
            b:ClearAllPoints()
            local col, row = (n - 1) % perRow, startRow + math.floor((n - 1) / perRow)
            b:SetPoint("TOPLEFT", set.holder, "TOPLEFT", col * (size + 2), -row * (size + 2))
            pcall(b.tex.SetTexture, b.tex, a.icon)
            if kind == "debuffs" then b.bg:SetColorTexture(0.8, 0.1, 0.1, 1) else b.bg:SetColorTexture(0, 0, 0, 1) end
            pcall(b.count.SetText, b.count, StackText(unit, a))
            local fs = b.cd.GetCountdownFontString and b.cd:GetCountdownFontString()
            if fs then
                local okF, font = pcall(fs.GetFont, fs)
                pcall(fs.SetFont, fs, (okF and font) or STANDARD_TEXT_FONT, S().resize and S().size or math.floor(size * 0.5), "OUTLINE")
            end
            if a.auraInstanceID == nil or not Feed(b.cd, unit, a.auraInstanceID) then pcall(b.cd.Clear, b.cd) end
            b:Show()
        end
    end
    for i = n + 1, #list do list[i]:Hide() end
    local rows = (n > 0) and math.ceil(n / perRow) or 0
    return n, rows
end

local function HideGame(unit, hide)
    local box = AurasBox(UnitFrameOf(unit))
    if box then pcall(box.SetAlpha, box, hide and 0 or 1) end
end

local function DoOwn(unit)
    local s, o = S(), O()
    local active = s.enabled and s[unit] and o.enabled
    local set = own[unit]
    HideGame(unit, active and o.hideGame)
    if not active then
        if set then set.holder:Hide() end
        M.stats.ownShown[unit] = 0
        return
    end
    set = OwnSet(unit)
    if not set then return end
    local okE, exists = pcall(UnitExists, unit)
    if not okE or IsSecret(exists) or not exists then set.holder:Hide(); return end
    set.holder:ClearAllPoints()
    set.holder:SetPoint("TOPLEFT", UnitFrameOf(unit), "BOTTOMLEFT", o.x, o.y)
    set.holder:Show()
    local nb, rb = FillKind(unit, set, "buffs", 0)
    local nd = FillKind(unit, set, "debuffs", rb)
    M.stats.ownShown[unit] = nb + nd
end
M._t_DoOwn = DoOwn
M._t_own = own

local function SafeOwn(unit)
    local ok, err = pcall(DoOwn, unit)
    if not ok then M.stats.ownErr = tostring(err); NS.ReportError("Aura Timers", err) end
end

----------------------------------------------------------------------
-- Updates: Blizzard rebuilds the icons when auras change, so redo it right after
----------------------------------------------------------------------
local dirty = { target = false, focus = false, plates = {} }
local function Flush()
    if not S().enabled then return end
    if dirty.target then dirty.target = false; DoUnitFrame("target", TargetFrame); SafeOwn("target") end
    if dirty.focus then dirty.focus = false; DoUnitFrame("focus", FocusFrame); SafeOwn("focus") end
    for unit in pairs(dirty.plates) do
        dirty.plates[unit] = nil
        DoPlate(unit)
    end
end

M._t = { Flush = Flush, touched = touched, dirty = dirty }

function M:Apply()
    local s = S()
    ApplyCVar(s.enabled)
    DoUnitFrame("target", TargetFrame)
    DoUnitFrame("focus", FocusFrame)
    SafeOwn("target")
    SafeOwn("focus")
    DoAllPlates()
    if not s.enabled then
        for cd in pairs(touched) do Restore(cd) end
        for _, cd in pairs(overlays) do cd:Hide() end
    end
end

function M:Init()
    savedCVar = S().savedCVar
    if type(S().own) ~= "table" then S().own = {} end
    for k, v in pairs(M.defaults.own) do if S().own[k] == nil then S().own[k] = v end end
    local runner = CreateFrame("Frame")
    local acc = 0
    runner:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 0.05 then return end
        acc = 0
        local ok, err = pcall(Flush)
        if not ok then NS.ReportError("Aura Timers", err) end
    end)
    NS.On("UNIT_AURA", function(_, unit)
        if type(unit) ~= "string" then return end
        if unit == "target" then dirty.target = true
        elseif unit == "focus" then dirty.focus = true end
        if unit:find("^nameplate") then dirty.plates[unit] = true end
    end)
    NS.On("PLAYER_TARGET_CHANGED", function() dirty.target = true end)
    NS.On("PLAYER_FOCUS_CHANGED", function() dirty.focus = true end)
    NS.On("NAME_PLATE_UNIT_ADDED", function(_, unit) if type(unit) == "string" then dirty.plates[unit] = true end end)
    NS.On("PLAYER_ENTERING_WORLD", function() ApplyCVar(S().enabled) end)
end

-- Lists small square frames under the target frame (where aura icons would be) and their
-- fields, so the layout of this client's aura icons can be seen in the saved report.
local function Probe(frame, label)
    if not frame then NS.Print("  probe " .. label .. ": frame missing"); return end
    local lines, cds = 0, 0
    local function Keys(obj)
        local out = {}
        for k, v in pairs(obj) do
            if type(k) == "string" and type(v) ~= "function" and k ~= "0" then
                local t = type(v)
                if t == "table" and v.GetObjectType then
                    local okT, ot = pcall(v.GetObjectType, v); t = okT and ot or "widget"
                elseif t == "number" or t == "boolean" then
                    t = IsSecret(v) and "secret" or tostring(v)
                end
                out[#out + 1] = k .. "=" .. t
                if #out >= 14 then break end
            end
        end
        table.sort(out)
        return table.concat(out, " ")
    end
    local function Walk(obj, depth, path)
        if depth > 7 or lines >= 14 then return end
        local okK, kids = pcall(function() return { obj:GetChildren() } end)
        if not okK then return end
        for i, kid in ipairs(kids) do
            local okT, ot = pcall(kid.GetObjectType, kid)
            ot = okT and ot or "?"
            if ot == "Cooldown" then cds = cds + 1 end
            local okW, w = pcall(kid.GetWidth, kid)
            local okH, h = pcall(kid.GetHeight, kid)
            w = okW and not IsSecret(w) and w or 0
            h = okH and not IsSecret(h) and h or 0
            local p = path .. "." .. ((kid.GetName and kid:GetName()) or ("#" .. i))
            if ot ~= "Cooldown" and w >= 10 and w <= 48 and math.abs(w - h) <= 6 and Shown(kid) and lines < 14 then
                lines = lines + 1
                NS.Print(string.format("  probe %s %s %s %dx%d: %s", label, p, ot, w, h, Keys(kid)))
            end
            Walk(kid, depth + 1, p)
        end
    end
    Walk(frame, 1, label)
    NS.Print(string.format("  probe %s: %d small square frames listed, %d cooldown widgets inside", label, lines, cds))
end

local function PathOf(obj)
    local parts, cur = {}, obj
    for _ = 1, 8 do
        if not cur then break end
        local okN, n = pcall(cur.GetName, cur)
        if okN and type(n) == "string" then table.insert(parts, 1, n); break end
        local okT, t = pcall(cur.GetObjectType, cur)
        table.insert(parts, 1, "(" .. (okT and t or "?") .. ")")
        local okP, p = pcall(cur.GetParent, cur)
        cur = okP and p or nil
    end
    return table.concat(parts, ".")
end

local function Size(obj)
    local okW, w = pcall(obj.GetWidth, obj)
    local okH, h = pcall(obj.GetHeight, obj)
    w = okW and not IsSecret(w) and w or 0
    h = okH and not IsSecret(h) and h or 0
    return string.format("%dx%d", w, h)
end

-- More digging: how many auras the target really has, every cooldown widget under the target
-- frame, its icon pools, and any frame anywhere that carries an aura id.
local function DeepProbe()
    local P = NS.Print
    -- 1. auras on the target right now
    local help, harm = 0, 0
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HELPFUL")
            if ok and a then help = help + 1 else break end
        end
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL")
            if ok and a then harm = harm + 1 else break end
        end
    end
    P(string.format("  target has %d buffs, %d debuffs right now%s", help, harm,
        (help + harm == 0) and "  (target something with buffs/DoTs and run this again)" or ""))
    -- 2. pools on TargetFrame
    if TargetFrame then
        local names = {}
        for _, e in ipairs(FramePools(TargetFrame)) do
            local n = 0
            pcall(function() for _ in e.pool:EnumerateActive() do n = n + 1 end end)
            names[#names + 1] = e.key .. "(" .. n .. " active)"
        end
        P("  TargetFrame pools: " .. (#names > 0 and table.concat(names, " ") or "none"))
        -- 3. every cooldown widget under the target frame
        local shown = 0
        local function Walk(obj, depth)
            if depth > 8 or shown >= 10 then return end
            local okK, kids = pcall(function() return { obj:GetChildren() } end)
            if not okK then return end
            for _, kid in ipairs(kids) do
                if IsCooldown(kid) and shown < 10 then
                    shown = shown + 1
                    local par = kid:GetParent()
                    local id = par and rawget(par, "auraInstanceID")
                    P(string.format("  cooldown %s %s shown=%s parent %s auraID=%s",
                        PathOf(kid), Size(kid), tostring(Shown(kid)), par and Size(par) or "-",
                        IsSecret(id) and "secret" or tostring(id)))
                end
                Walk(kid, depth + 1)
            end
        end
        Walk(TargetFrame, 1)
    end
    -- 3b. the Auras container itself
    local box = TargetFrame and AurasBox(TargetFrame)
    if not box then
        P("  Auras container: not found")
    else
        local function Fields(obj, max)
            local out = {}
            pcall(function()
                for k, v in pairs(obj) do
                    if type(k) == "string" and k ~= "0" and type(v) ~= "function" then
                        local t = type(v)
                        if t == "table" and v.GetObjectType then
                            local okT, ot = pcall(v.GetObjectType, v); t = okT and ot or "widget"
                        elseif t == "number" or t == "boolean" then
                            t = IsSecret(v) and "secret" or tostring(v)
                        elseif t == "string" then
                            t = '"' .. v:sub(1, 20) .. '"'
                        end
                        out[#out + 1] = k .. "=" .. t
                    end
                end
            end)
            table.sort(out)
            local more = #out > max and (" +" .. (#out - max) .. " more") or ""
            while #out > max do table.remove(out) end
            return table.concat(out, " ") .. more
        end
        local okC, nk = pcall(box.GetNumChildren, box)
        local okR, nr = pcall(box.GetNumRegions, box)
        P(string.format("  Auras container %s shown=%s children=%s regions=%s: %s", Size(box), tostring(Shown(box)),
            tostring(okC and nk), tostring(okR and nr), Fields(box, 30)))
        local okK, kids = pcall(function() return { box:GetChildren() } end)
        if okK then
            for i, kid in ipairs(kids) do
                if i > 12 then P("  ... more children"); break end
                local okT, ot = pcall(kid.GetObjectType, kid)
                local okKC, kc = pcall(kid.GetNumChildren, kid)
                P(string.format("  Auras child #%d %s %s shown=%s kids=%s: %s", i, okT and ot or "?", Size(kid),
                    tostring(Shown(kid)), tostring(okKC and kc), Fields(kid, 20)))
                local okG, grand = pcall(function() return { kid:GetChildren() } end)
                if okG then
                    for j, g in ipairs(grand) do
                        if j > 3 then break end
                        local okGT, gt = pcall(g.GetObjectType, g)
                        P(string.format("    inner #%d %s %s shown=%s: %s", j, okGT and gt or "?", Size(g),
                            tostring(Shown(g)), Fields(g, 14)))
                    end
                end
            end
        end
        local okRg, regs = pcall(function() return { box:GetRegions() } end)
        if okRg then
            local listed = 0
            for _, r in ipairs(regs) do
                if listed >= 8 then break end
                local okT, ot = pcall(r.GetObjectType, r)
                if Shown(r) then
                    listed = listed + 1
                    P(string.format("  Auras region %s %s", okT and ot or "?", Size(r)))
                end
            end
        end
    end
    -- 3c. what the aura functions return for the target with other filters
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local function Count(filter)
            local n = 0
            for i = 1, 40 do
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, filter)
                if ok and a then n = n + 1 else break end
            end
            return n
        end
        P(string.format("  target auras by filter: HARMFUL|PLAYER=%d  HELPFUL|PLAYER=%d   GetUnitAuras=%s GetAuraSlots=%s",
            Count("HARMFUL|PLAYER"), Count("HELPFUL|PLAYER"), tostring(C_UnitAuras.GetUnitAuras ~= nil),
            tostring(C_UnitAuras.GetAuraSlots ~= nil)))
    end
    -- 4. named classic buttons
    local named = {}
    for _, n in ipairs({ "TargetFrameBuff1", "TargetFrameDebuff1", "TargetFrameBuffs", "TargetFrameDebuffs" }) do
        if _G[n] then named[#named + 1] = n end
    end
    P("  named aura frames: " .. (#named > 0 and table.concat(named, " ") or "none"))
    -- 5. any frame anywhere with an aura id
    local found, total = 0, 0
    if EnumerateFrames then
        local f = EnumerateFrames()
        local guard = 0
        while f and guard < 30000 do
            guard = guard + 1
            local okR, id = pcall(rawget, f, "auraInstanceID")
            if okR and id ~= nil then
                total = total + 1
                if found < 8 and Shown(f) then
                    found = found + 1
                    local okU, u = pcall(rawget, f, "unit")
                    P(string.format("  aura frame %s %s unit=%s cooldown=%s",
                        PathOf(f), Size(f), tostring(okU and u or nil), tostring(IconCooldown(f) ~= nil)))
                end
            end
            local okN, nx = pcall(EnumerateFrames, f)
            f = okN and nx or nil
        end
    end
    P(string.format("  frames with an aura id anywhere: %d (%d shown listed)", total, found))
end

function M:Diagnose()
    local st = M.stats
    local n = 0
    for _ in pairs(touched) do n = n + 1 end
    NS.Print(string.format("  countdownForCooldowns = %s   aura icons: target %d (own timer on %d), focus %d (own timer on %d), nameplate cooldowns %d   showing numbers on %d",
        st.cvar, st.target, st.targetOwn, st.focus, st.focusOwn, st.plates, n))
    NS.Print("  own timers filled by: " .. tostring(st.how) .. "   C_UnitAuras.GetAuraDuration: "
        .. tostring(C_UnitAuras and C_UnitAuras.GetAuraDuration ~= nil))
    NS.Print("  TargetFrame.auraPools: " .. tostring(TargetFrame and TargetFrame.auraPools ~= nil)
        .. "   icons found by: " .. tostring(st.layout))
    local o = O()
    NS.Print(string.format("  own icons: %s   target %d   focus %d   hide game icons: %s   last error: %s",
        o.enabled and "on" or "off", st.ownShown.target, st.ownShown.focus, tostring(o.hideGame), tostring(st.ownErr or "none")))
    Probe(TargetFrame, "TargetFrame")
    local ok, err = pcall(DeepProbe)
    if not ok then NS.Print("  deep probe failed: " .. tostring(err)) end
end

function M.Build(page)
    local function A() NS.ApplyModule("auratimers") end
    page:Section("Target and focus aura icons", "Aimbot UI's own buff and debuff icons, with time left")
    page:Check("Draw my own aura icons with timers", function() return O().enabled end,
        function(v) O().enabled = v; A() end)
    page:Check("Hide the game's aura icons", function() return O().hideGame end,
        function(v) O().hideGame = v; A() end)
    page:Check("Show buffs", function() return O().buffs end, function(v) O().buffs = v; A() end)
    page:Check("Show debuffs", function() return O().debuffs end, function(v) O().debuffs = v; A() end)
    page:Check("Debuffs: only the ones I cast", function() return O().onlyMine end,
        function(v) O().onlyMine = v; A() end)
    page:Slider("Icon size", 14, 40, 1, function() return O().iconSize end, function(v) O().iconSize = v; A() end)
    page:Slider("Icons per row", 3, 16, 1, function() return O().perRow end, function(v) O().perRow = v; A() end)
    page:Slider("Most icons of each kind", 4, 32, 1, function() return O().max end, function(v) O().max = v; A() end)
    page:Slider("Move left / right", -150, 150, 1, function() return O().x end, function(v) O().x = v; A() end)
    page:Slider("Move up / down", -150, 150, 1, function() return O().y end, function(v) O().y = v; A() end)
    page:Note("This client keeps its own target aura icons out of reach of addons, so Aimbot UI draws its "
        .. "own: buffs first, debuffs (red border) below. Hover an icon for its tooltip.")

    page:Section("Where", "Which aura icons get time-left numbers")
    page:Check("Target frame", function() return S().target end,
        function(v) S().target = v; NS.ApplyModule("auratimers") end)
    page:Check("Focus frame", function() return S().focus end,
        function(v) S().focus = v; NS.ApplyModule("auratimers") end)
    page:Check("Nameplates", function() return S().plates end,
        function(v) S().plates = v; NS.ApplyModule("auratimers") end)
    page:Note("Numbers show on your DoTs, crowd control and any other aura icon the game draws a cooldown "
        .. "swipe on. Your own buffs at the top right keep the game's own timer setting.")

    page:Section("Number size", "Bigger or smaller numbers")
    page:Check("Use my own number size", function() return S().resize end,
        function(v) S().resize = v; NS.ApplyModule("auratimers") end)
    page:Slider("Target and focus icons", 6, 24, 1, function() return S().size end,
        function(v) S().size = v; NS.ApplyModule("auratimers") end)
    page:Slider("Nameplate icons", 6, 24, 1, function() return S().plateSize end,
        function(v) S().plateSize = v; NS.ApplyModule("auratimers") end)
end
