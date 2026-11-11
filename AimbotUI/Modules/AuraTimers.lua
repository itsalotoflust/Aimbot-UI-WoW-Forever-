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
            perRow   = 5,
            max      = 16,          -- per kind
            x = 0, y = -4,          -- from the bottom left of the frame's mana bar
            timerSize = 0,          -- countdown text size, 0 = fit the icon
            spacing = 3,
            layout = 4,             -- settings version (2: under the mana bar, 3: 5 per row, 4: own tooltips)
            tooltip = true,         -- our own tooltip (on top of the game's hidden icons)
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

-- After a cooldown was given a time: false only when it can be seen that nothing is running
-- (a zero duration). If the client hides the values, it is assumed to be running.
local function Running(cd)
    if cd.GetCooldownDuration then
        local ok, d = pcall(cd.GetCooldownDuration, cd)
        if ok and not IsSecret(d) and type(d) == "number" then return d > 0 end
    end
    if cd.GetCooldownTimes then
        local ok, _, d = pcall(cd.GetCooldownTimes, cd)
        if ok and not IsSecret(d) and type(d) == "number" then return d > 0 end
    end
    return true
end
M._t_Running = Running

-- Returns true when the cooldown was given the aura's time.
local function Feed(cd, unit, auraID)
    local CU = C_UnitAuras
    if not CU then return false end
    if CU.GetAuraDuration and cd.SetCooldownFromDurationObject then
        local ok, dur = pcall(CU.GetAuraDuration, unit, auraID)
        if ok and dur ~= nil and pcall(cd.SetCooldownFromDurationObject, cd, dur) and Running(cd) then
            M.stats.how = "duration object"
            return true
        end
    end
    if not CU.GetAuraDataByAuraInstanceID then return false end
    local ok, a = pcall(CU.GetAuraDataByAuraInstanceID, unit, auraID)
    if not ok or type(a) ~= "table" then return false end
    local exp, dur = a.expirationTime, a.duration
    if exp == nil or dur == nil then return false end
    if cd.SetCooldownFromExpirationTime and pcall(cd.SetCooldownFromExpirationTime, cd, exp, dur) and Running(cd) then
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

-- The row starts under the frame's mana bar, lined up with its left edge.
local function AnchorOf(unit)
    local frame = UnitFrameOf(unit)
    local ok, bar = pcall(function() return frame.TargetFrameContent.TargetFrameContentMain.ManaBar end)
    if ok and type(bar) == "table" and bar.GetObjectType then return bar, true end
    return frame, false
end

local function TimerSize()
    local o = O()
    if o.timerSize and o.timerSize > 0 then return o.timerSize end
    return math.max(6, math.floor(o.iconSize * 0.42 + 0.5))
end

local ShowTip   -- defined below OwnSet
local Shield    -- defined above DoOwn
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
    b:EnableMouse(O().tooltip and true or false)
    b:SetScript("OnEnter", function(self) pcall(ShowTip, self) end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

-- The tooltip of one of our icons: always the aura that icon shows. By the aura's id first; by
-- position only when the icon came from the game's own index order (positions in our list don't
-- match the game's when the aura came from events or your casts); a cast-timed icon shows its spell.
local function TipLines()
    local ok, n = pcall(GameTooltip.NumLines, GameTooltip)
    return ok and not IsSecret(n) and type(n) == "number" and n or 0
end
function ShowTip(self)   -- the local declared above NewIcon
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local done = false
    local id = self.auraID
    if (IsSecret(id) or id ~= nil) and GameTooltip.SetUnitAuraByAuraInstanceID then
        done = pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, self.unit, id) and TipLines() > 0
    end
    if not done and (self.way == "index" or self.way == "nameplate index") and self.index then
        done = pcall(GameTooltip.SetUnitAura, GameTooltip, self.unit, self.index, self.filter) and TipLines() > 0
    end
    local sid = self.spellId
    if not done and not IsSecret(sid) and type(sid) == "number" and GameTooltip.SetSpellByID then
        done = pcall(GameTooltip.SetSpellByID, GameTooltip, sid) and TipLines() > 0
    end
    M.stats.tips = (M.stats.tips or 0) + 1
    if done then GameTooltip:Show() else GameTooltip:Hide() end
end
M._t_ShowTip = function(b) return ShowTip(b) end

local function OwnSet(unit)
    local set = own[unit]
    if set then return set end
    local frame = UnitFrameOf(unit)
    if not frame then return nil end
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(1, 1)
    -- above the game's (hidden but still hoverable) aura icons, so the mouse finds ours first
    local okL, lvl = pcall(frame.GetFrameLevel, frame)
    if okL and not IsSecret(lvl) and type(lvl) == "number" then pcall(holder.SetFrameLevel, holder, lvl + 20) end
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

-- 5th way: the auras the game announces. Every UNIT_AURA event says which auras were added,
-- changed or removed (with their data). On this client the lookups can come back empty for an
-- enemy even while it has your DoTs on it, so what the events said is kept per unit and used
-- when every lookup finds nothing. A full update (new target) clears it.
local seen = { target = {}, focus = {} }    -- unit -> { [auraInstanceID] = aura data }
local seenAt = setmetatable({}, { __mode = "k" })  -- aura data -> when it was announced
local SEEN_MAX = 300   -- an aura whose end time can't be read is dropped after this many seconds
M.stats.seen = { added = 0, removed = 0, full = 0, secretIDs = 0 }

local Learn   -- defined with your-cast tracking below
local function SeenUpdate(unit, info)
    local list = seen[unit]
    if not list then return end
    -- A full update only tells addons to look everything up again. On this client the lookups find
    -- nothing for an enemy, so what the events said is kept (it used to be thrown away here, and
    -- full updates come many times a fight, which left only the game's icons, with no numbers).
    -- A new target / focus clears it; auras whose time ran out are dropped as they're read.
    if type(info) ~= "table" or IsSecret(info.isFullUpdate) or info.isFullUpdate == true then
        M.stats.seen.full = M.stats.seen.full + 1
        if type(info) ~= "table" then return end
    end
    local CU = C_UnitAuras
    if type(info.addedAuras) == "table" then
        for _, a in ipairs(info.addedAuras) do
            local id = type(a) == "table" and a.auraInstanceID
            if IsSecret(id) then
                M.stats.seen.secretIDs = M.stats.seen.secretIDs + 1
            elseif id then
                list[id] = a
                seenAt[a] = GetTime and GetTime() or 0
                pcall(Learn, a)
                M.stats.seen.added = M.stats.seen.added + 1
                local d = a.duration
                local key = IsSecret(d) and "durHidden" or ((type(d) == "number" and d > 0) and "durRead" or "durZero")
                M.stats.seen[key] = (M.stats.seen[key] or 0) + 1
            end
        end
    end
    if type(info.updatedAuraInstanceIDs) == "table" and CU and CU.GetAuraDataByAuraInstanceID then
        for _, id in ipairs(info.updatedAuraInstanceIDs) do
            if not IsSecret(id) and id ~= nil and list[id] then
                local ok, a = pcall(CU.GetAuraDataByAuraInstanceID, unit, id)
                if ok and type(a) == "table" then list[id] = a end
            end
        end
    end
    if type(info.removedAuraInstanceIDs) == "table" then
        for _, id in ipairs(info.removedAuraInstanceIDs) do
            if not IsSecret(id) and id ~= nil and list[id] then
                list[id] = nil
                M.stats.seen.removed = M.stats.seen.removed + 1
            end
        end
    end
end
M._t_SeenUpdate = SeenUpdate
M._t_seen = seen

-- Does this aura pass the filter ("HARMFUL", "HELPFUL", "HARMFUL|PLAYER")? Asks the game first,
-- then the aura's own fields; when neither can tell, a harmful aura is assumed (DoTs are the case
-- this way exists for).
local function PassesFilter(unit, a, filter)
    local CU = C_UnitAuras
    local id = a.auraInstanceID
    if CU and CU.IsAuraFilteredOutByInstanceID and (IsSecret(id) or id ~= nil) then
        local ok, out = pcall(CU.IsAuraFilteredOutByInstanceID, unit, id, filter)
        if ok and type(out) == "boolean" and not IsSecret(out) then return not out end
    end
    local harmful = a.isHarmful
    if IsSecret(harmful) or type(harmful) ~= "boolean" then
        local helpful = a.isHelpful
        if not IsSecret(helpful) and type(helpful) == "boolean" then harmful = not helpful else harmful = nil end
    end
    local wantHarm = filter:find("HARMFUL", 1, true) ~= nil
    if harmful == nil then
        if not wantHarm then return false end
    elseif harmful ~= wantHarm then
        return false
    end
    if filter:find("PLAYER", 1, true) then
        local mine = a.isFromPlayerOrPlayerPet
        if not IsSecret(mine) and type(mine) == "boolean" then return mine end
        local src = a.sourceUnit
        if not IsSecret(src) and type(src) == "string" then return src == "player" or src == "pet" end
    end
    return true
end

-- 6th way: your own casts. On this client most debuffs you put on an enemy arrive only as a "full
-- update" with no data, and every lookup finds nothing, so neither the events nor the lookups know
-- them. What is known: the moment your harmful spell lands (UNIT_SPELLCAST_SUCCEEDED) and how
-- long it lasts, learned from the times the game did announce for that spell (saved), or else
-- read from the spell's description ("over 15 sec", "for 2 min"). Shown for your target only;
-- cleared on a new target or when it dies. A recast restarts the timer.
local casts = {}                  -- spellID -> { start, duration, icon }
local PlateIcons, PlateFrameFor   -- defined with the nameplate reading below
local plateRefreshAt              -- when a nameplate aura icon's countdown was last (re)started
local pending = {}                -- casts waiting to be confirmed by an aura change on the target
local lastTargetAura              -- when the target's auras last changed
local CONFIRM_AFTER = 1.5         -- seconds a cast may wait for its debuff to show up
local CONFIRM_BEFORE = 0.25       -- an aura change this shortly before the cast also counts
M.stats.casts = { seen = 0, used = 0, learned = 0, fromText = 0, unknown = 0, confirmed = 0, missed = 0 }

local function Learned()
    local s = S()
    if type(s.learned) ~= "table" then s.learned = {} end
    return s.learned
end

function Learn(a)   -- the local declared above SeenUpdate
    local id, dur = a.spellId, a.duration
    if IsSecret(id) or IsSecret(dur) or type(id) ~= "number" or type(dur) ~= "number" or dur <= 0 then return end
    local mine = a.isFromPlayerOrPlayerPet
    if IsSecret(mine) or mine ~= true then
        local src = a.sourceUnit
        if IsSecret(src) or (src ~= "player" and src ~= "pet") then return end
    end
    if Learned()[id] ~= dur then
        Learned()[id] = dur
        M.stats.casts.learned = M.stats.casts.learned + 1
    end
end

-- "over 15 sec", "for 2 min", "lasts 30 sec", "for 1.5 sec" (English client)
local function DurationFromText(text)
    if IsSecret(text) or type(text) ~= "string" then return nil end
    local best
    for num, unit in text:gmatch("(%d+%.?%d*)%s*(%a+)") do
        local n = tonumber(num)
        local u = unit:lower()
        local secs
        if u == "sec" or u == "secs" or u == "second" or u == "seconds" then secs = n
        elseif u == "min" or u == "mins" or u == "minute" or u == "minutes" then secs = n and n * 60 end
        if secs and secs > 0 and secs <= 600 then best = best or secs end
    end
    return best
end
M._t_DurationFromText = DurationFromText

local function SpellCall(fnTable, fnName, oldName, id)
    local fn = fnTable and fnTable[fnName]
    if type(fn) == "function" then
        local ok, v = pcall(fn, id)
        if ok and not IsSecret(v) then return v end
    elseif oldName and type(_G[oldName]) == "function" then
        local ok, v = pcall(_G[oldName], id)
        if ok and not IsSecret(v) then return v end
    end
end

-- Lengths of common crowd control, used before the description is read.
local KNOWN_DURATION = { [19577] = 3, [24394] = 3, [19503] = 4, [5116] = 4, [19410] = 3,
    [19386] = 12, [24132] = 12, [24133] = 12,
    [3355] = 10, [14308] = 15, [14309] = 20,                                   -- Freezing Trap Effect
    [13797] = 15, [14298] = 15, [14299] = 15, [14300] = 15, [14301] = 15,      -- Immolation Trap Effect
    [13812] = 20, [14314] = 20, [14315] = 20 }                                 -- Explosive Trap Effect

local function SpellDuration(id)
    local d = Learned()[id]
    if type(d) == "number" and d > 0 then return d, "learned" end
    if KNOWN_DURATION[id] then return KNOWN_DURATION[id], "known" end
    local text = SpellCall(C_Spell, "GetSpellDescription", "GetSpellDescription", id)
    d = DurationFromText(text)
    if d then return d, "text" end
end

local function IsHarmful(id)
    local v = SpellCall(C_Spell, "IsSpellHarmful", "IsHarmfulSpell", id)
    if type(v) == "boolean" then return v end
    return nil
end

-- Spells whose debuff lands a while after the cast: Intimidation stuns on the pet's next hit,
-- traps work when the enemy steps in. They wait this many seconds for the target's auras to
-- change, and their timer starts when that happens, not at the cast.
local DELAYED = {
    [19577] = 6,                                  -- Intimidation (cast), stun on the pet's next hit
}
-- Traps: placing one is not hitting anything. The target's auras change all the time (many
-- "full updates" a fight), so that can't tell when a trap went off; the timer only starts when
-- the game reports the trap's effect itself (the effect spell succeeding, or its aura announced).
-- Placing a trap shows nothing.
local TRAPS = { [1499] = true, [14310] = true, [14311] = true,                 -- Freezing Trap
    [13795] = true, [14302] = true, [14303] = true, [14304] = true, [14305] = true, -- Immolation Trap
    [13813] = true, [14316] = true, [14317] = true,                            -- Explosive Trap
    [13809] = true }                                                           -- Frost Trap
local TRAP_EFFECT = { [3355] = true, [14308] = true, [14309] = true,           -- Freezing Trap Effect
    [13797] = true, [14298] = true, [14299] = true, [14300] = true, [14301] = true, -- Immolation Trap Effect
    [13812] = true, [14314] = true, [14315] = true }                           -- Explosive Trap Effect
M.stats.traps = { placed = 0, effects = 0, caught = 0 }
-- How long each trap's effect lasts, and which nameplate row shows it when it catches something.
local TRAP_DURATION = { [1499] = 10, [14310] = 15, [14311] = 20,
    [13795] = 15, [14302] = 15, [14303] = 15, [14304] = 15, [14305] = 15,
    [13813] = 20, [14316] = 20, [14317] = 20 }
local TRAP_ROW = { [1499] = "cc", [14310] = "cc", [14311] = "cc" }   -- the others land as debuffs
local TRAP_WINDOW = 60                                               -- a trap lasts a minute
-- Known crowd control / debuffs that count even when the client calls them "not harmful"
-- (Intimidation is cast on your pet, for example).
local FORCE = {
    [19577] = true, [24394] = true,               -- Intimidation, its stun
    [19503] = true,                               -- Scatter Shot
    [5116] = true,                                -- Concussive Shot
    [1513] = true, [14326] = true, [14327] = true, -- Scare Beast
    [19386] = true, [24132] = true, [24133] = true, -- Wyvern Sting
    [3034] = true, [14279] = true, [14280] = true, -- Viper Sting
    [3043] = true, [14275] = true, [14276] = true, [14277] = true, -- Scorpid Sting
    [19306] = true, [20909] = true, [20910] = true, -- Counterattack
    [2974] = true, [14267] = true, [14268] = true, -- Wing Clip
    [19410] = true,                               -- Improved Concussive Shot stun
}
for id in pairs(DELAYED) do FORCE[id] = true end
for id in pairs(TRAP_EFFECT) do FORCE[id] = true end
M._t_DELAYED, M._t_FORCE = DELAYED, FORCE

local SAME_AS = { [24394] = 19577 }   -- the pet's stun is the Intimidation you cast: one icon

local function CastLanded(spellID, byPet)
    if IsSecret(spellID) or type(spellID) ~= "number" or spellID == 75 then return end
    if SAME_AS[spellID] then casts[SAME_AS[spellID]] = nil; pending[SAME_AS[spellID]] = nil end
    if TRAPS[spellID] then
        -- placing isn't hitting: the trap waits for a new icon in the matching row of the target's
        -- nameplate (crowd control for Freezing Trap, debuffs for the fire traps), and its timer
        -- starts then
        M.stats.traps.placed = M.stats.traps.placed + 1
        local d = TRAP_DURATION[spellID]
        if d then
            pending[spellID] = { start = GetTime(), duration = d, window = TRAP_WINDOW, delayed = true, trap = true,
                need = TRAP_ROW[spellID] or "debuff",
                icon = SpellCall(C_Spell, "GetSpellTexture", "GetSpellTexture", spellID) }
        end
        return
    end
    local trapHit = TRAP_EFFECT[spellID]
    if trapHit then M.stats.traps.effects = M.stats.traps.effects + 1 end
    local okE, enemy = pcall(UnitCanAttack, "player", "target")
    if not okE or IsSecret(enemy) or enemy ~= true then return end
    -- only spells known to leave a debuff: learned from an announced aura, or harmful with a
    -- duration in their description
    local learned = Learned()[spellID]
    if byPet and not learned and not FORCE[spellID] then return end   -- pet: known debuffs only
    if not learned and not FORCE[spellID] then
        local harmful = IsHarmful(spellID)
        if harmful == false then return end
        if harmful == nil then
            -- the client can't say: a helpful spell is skipped, otherwise the description must
            -- speak of the target / enemy (keeps self buffs like Rapid Fire out)
            local helpful = SpellCall(C_Spell, "IsSpellHelpful", "IsHelpfulSpell", spellID)
            if helpful == true then return end
            local text = SpellCall(C_Spell, "GetSpellDescription", "GetSpellDescription", spellID)
            if type(text) ~= "string" then return end
            local lower = text:lower()
            if not (lower:find("target", 1, true) or lower:find("enemy", 1, true)) then return end
        end
    end
    local dur, from = SpellDuration(spellID)
    if not dur then M.stats.casts.unknown = M.stats.casts.unknown + 1; return end
    if from == "text" then M.stats.casts.fromText = M.stats.casts.fromText + 1 end
    local icon = SpellCall(C_Spell, "GetSpellTexture", "GetSpellTexture", spellID)
    local entry = { start = GetTime(), duration = dur, icon = icon,
        window = DELAYED[spellID] or CONFIRM_AFTER, delayed = DELAYED[spellID] ~= nil,
        need = DELAYED[spellID] and "cc" or nil,
        refresh = casts[spellID] ~= nil and GetTime() < casts[spellID].start + casts[spellID].duration }
    M.stats.casts.seen = M.stats.casts.seen + 1
    -- A cast that "succeeded" can still miss (or be resisted, dodged, parried). Addons aren't told,
    -- but a debuff that lands makes the game update the target's auras. So the cast only counts
    -- once the target's auras change right around it; otherwise it is dropped as a miss.
    if trapHit then
        -- the game itself says the trap went off: start now (it is caught by the enemy that
        -- stepped in, which is assumed to be your target)
        casts[spellID] = entry
        M.stats.casts.confirmed = M.stats.casts.confirmed + 1
    elseif not entry.delayed and not PlateFrameFor("target") and lastTargetAura and entry.start - lastTargetAura <= CONFIRM_BEFORE then
        casts[spellID] = entry
        M.stats.casts.confirmed = M.stats.casts.confirmed + 1
    else
        pending[spellID] = entry
    end
end

-- Something new showed up on the target: casts waiting for it are confirmed.
-- row = "debuff" / "cc": a new icon in that row of the target's nameplate (reliable);
-- row = nil: no nameplate, only "the target's auras changed" (traps never count on that).
local function TargetAuraChanged(row)
    local now = GetTime()
    lastTargetAura = now
    for sid, entry in pairs(pending) do
        local fits
        if row == nil then fits = not entry.trap
        elseif row == "refresh" then fits = entry.refresh == true
        else fits = entry.need == nil or entry.need == row end
        if fits and now - entry.start <= (entry.window or CONFIRM_AFTER) then
            if entry.trap then M.stats.traps.caught = M.stats.traps.caught + 1 end
            if entry.delayed then entry.start = now end   -- the debuff starts now, not at the cast
            casts[sid] = entry
            M.stats.casts.confirmed = M.stats.casts.confirmed + 1
            pending[sid] = nil
        end
    end
end

-- With a nameplate, a cast is confirmed when its row of the plate gets a new icon (every tick).
-- The plate only shows what really landed, so a miss never confirms.
local plateCount, plateCC, lastRefreshSeen
local function PlateCheck()
    local icons = PlateIcons("target", 40)
    if not icons then plateCount, plateCC = nil, nil; return false, false end
    local nd, nc = 0, 0
    for _, e in ipairs(icons) do if e.data.cc then nc = nc + 1 else nd = nd + 1 end end
    local grewD = plateCount ~= nil and nd > plateCount
    local grewC = plateCC ~= nil and nc > plateCC
    local changed = plateCount ~= nd or plateCC ~= nc
    plateCount, plateCC = nd, nc
    if grewC then TargetAuraChanged("cc") end
    if grewD then TargetAuraChanged("debuff") end
    -- a recast on a debuff that's still up adds no icon, but the game restarts its countdown
    if plateRefreshAt and plateRefreshAt ~= lastRefreshSeen then
        lastRefreshSeen = plateRefreshAt
        TargetAuraChanged("refresh")
    end
    return true, changed
end
M._t_PlateCheck = PlateCheck

local function DropUnconfirmed()
    local now = GetTime()
    for sid, entry in pairs(pending) do
        if now - entry.start > (entry.window or CONFIRM_AFTER) then
            pending[sid] = nil
            M.stats.casts.missed = M.stats.casts.missed + 1
        end
    end
end
M._t_casts = casts
M._t_pending = pending
M._t_DropUnconfirmed = DropUnconfirmed

-- Reads a unit's auras for one filter. The usual lookup returns nothing for enemy debuffs on this
-- client, so every way the game offers is tried in turn; the first that returns any aura is used.
-- Returns a list of aura tables and the name of the way that worked.
M.stats.ways = {}
local function Reads(unit, filter, max)
    local CU = C_UnitAuras
    local list
    -- 1. by index
    if CU and CU.GetAuraDataByIndex then
        list = {}
        for i = 1, max do
            local ok, a = pcall(CU.GetAuraDataByIndex, unit, i, filter)
            if not ok or type(a) ~= "table" then break end
            a = { data = a, index = i }; list[#list + 1] = a
        end
        M.stats.ways[filter .. " index"] = #list
        if #list > 0 then return list, "index" end
    end
    -- 2. all at once
    if CU and CU.GetUnitAuras then
        local ok, all = pcall(CU.GetUnitAuras, unit, filter, max)
        list = {}
        if ok and type(all) == "table" then
            for i, a in ipairs(all) do
                if type(a) == "table" then list[#list + 1] = { data = a, index = i } end
            end
        end
        M.stats.ways[filter .. " list"] = #list
        if #list > 0 then return list, "list" end
    end
    -- 3. by slot
    if CU and CU.GetAuraSlots and CU.GetAuraDataBySlot then
        local ok, res = pcall(function() return { CU.GetAuraSlots(unit, filter, max) } end)
        list = {}
        if ok and type(res) == "table" then
            for k = 2, #res do
                local slot = res[k]
                if slot ~= nil then
                    local okA, a = pcall(CU.GetAuraDataBySlot, unit, slot)
                    if okA and type(a) == "table" then list[#list + 1] = { data = a, index = #list + 1 } end
                end
            end
        end
        M.stats.ways[filter .. " slots"] = #list
        if #list > 0 then return list, "slots" end
    end
    -- 4. the old UnitAura
    if UnitAura then
        list = {}
        for i = 1, max do
            local ok, name, icon, count, _, duration, expires = pcall(UnitAura, unit, i, filter)
            if not ok or name == nil then break end
            list[#list + 1] = { data = { icon = icon, applications = count, duration = duration, expirationTime = expires }, index = i }
        end
        M.stats.ways[filter .. " UnitAura"] = #list
        if #list > 0 then return list, "UnitAura" end
    end
    return {}, "none"
end

-- The nameplate token showing the same unit (the game may share more about a nameplate's auras).
local function Same(a, b)
    local ok, same = pcall(UnitIsUnit, a, b)
    return ok and not IsSecret(same) and same == true
end

-- The nameplate frame showing a unit (or nil).
function PlateFrameFor(unit)   -- the local declared above
    if not C_NamePlate then return end
    if C_NamePlate.GetNamePlateForUnit then
        local ok, pf = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok and type(pf) == "table" then return pf end
    end
end

local function PlateFor(unit)
    -- 1. the plate frame's own unit token
    local pf = PlateFrameFor(unit)
    if pf then
        for _, t in ipairs({ rawget(pf, "namePlateUnitToken"), rawget(pf, "UnitFrame") and rawget(pf.UnitFrame, "unit") }) do
            if not IsSecret(t) and type(t) == "string" and Same(t, unit) then return t end
        end
    end
    -- 2. any nameplate token that is the same unit
    for i = 1, 40 do
        local t = "nameplate" .. i
        if Same(t, unit) then return t end
    end
end
M._t_PlateFor = PlateFor

-- What the unit's nameplate itself draws: its debuff and crowd-control icons. On this client these
-- frames are visible to addons (2.16.10 diag) even though the aura lookups find nothing, and the
-- game puts exactly your debuffs and crowd control on them, the moment they land. So when the
-- target has a nameplate, these icons decide what is shown: a missed spell never gets an icon,
-- and a trap shows when it catches something. Icons and countdowns are copied as the game sets
-- them (secret values are passed straight through, never read).
local PLATE_LISTS = { "CrowdControlListFrame", "DebuffListFrame" }
-- 2.17.0 showed the plate's icons themselves, but their countdowns can't be copied on this client,
-- so the icons lost their numbers. The icons shown are your landed casts again (with their timers);
-- the plate is used to tell which casts landed.
local SHOW_PLATE_ICONS = false
M._t_ShowPlateIcons = function(v) SHOW_PLATE_ICONS = v end
local cdSeen = setmetatable({}, { __mode = "k" })   -- game cooldown -> { how, a, b } as last set
local cdHooked = setmetatable({}, { __mode = "k" })
M.stats.plate = { found = 0, icons = 0, mirrored = 0, byID = 0, byTimes = 0, byCast = 0, noTimer = 0 }

-- Every countdown the game starts is noted (for all cooldown widgets, through their shared
-- methods), so a nameplate icon's timer is known even when the icon was set up before Aura Timers
-- first looked at it. 2.17.0 only watched icons it had already seen, and the game sets a new
-- icon's timer the moment it creates it, so most icons were missed ("none" in the diag).
local allHooked = false
local CD_METHODS = { "SetCooldown", "SetCooldownFromDurationObject", "SetCooldownFromExpirationTime", "SetCooldownDuration" }
local plateCDs = setmetatable({}, { __mode = "k" })   -- countdowns that belong to nameplate aura icons
local function Record(cd, m, a, b)
    if plateCDs[cd] and GetTime then plateRefreshAt = GetTime() end
    local t = cdSeen[cd]
    if not t then t = {}; cdSeen[cd] = t end
    t[1], t[2], t[3] = m, a, b
end
local function HookAllCooldowns()
    if allHooked then return end
    local ok, probe = pcall(CreateFrame, "Cooldown")
    if not ok or not probe then return end
    local mt = getmetatable(probe)
    local idx = mt and mt.__index
    if type(idx) ~= "table" then return end
    local n = 0
    for _, m in ipairs(CD_METHODS) do
        if type(idx[m]) == "function" then
            if pcall(hooksecurefunc, idx, m, function(self, a, b) Record(self, m, a, b) end) then n = n + 1 end
        end
    end
    if type(idx.Clear) == "function" then
        pcall(hooksecurefunc, idx, "Clear", function(self) cdSeen[self] = nil end)
    end
    allHooked = n > 0
    M.stats.cdHookAll = allHooked
end
M._t_HookAllCooldowns = HookAllCooldowns

local function HookCooldown(cd)
    if allHooked then return end
    if cdHooked[cd] or type(cd) ~= "table" then return end
    cdHooked[cd] = true
    for _, m in ipairs({ "SetCooldown", "SetCooldownFromDurationObject", "SetCooldownFromExpirationTime", "SetCooldownDuration" }) do
        if type(cd[m]) == "function" then
            pcall(hooksecurefunc, cd, m, function(_, a, b) Record(cd, m, a, b) end)
        end
    end
    if type(cd.Clear) == "function" then pcall(hooksecurefunc, cd, "Clear", function() cdSeen[cd] = nil end) end
end

local function CooldownOf(f)
    local cd = rawget(f, "Cooldown") or rawget(f, "cooldown")
    if type(cd) == "table" then return cd end
    local ok, kids = pcall(function() return { f:GetChildren() } end)
    if ok then
        for _, k in ipairs(kids) do
            local okT, kind = pcall(k.GetObjectType, k)
            if okT and kind == "Cooldown" then return k end
        end
    end
end

local function Shown(f)
    local ok, v = pcall(f.IsShown, f)
    return ok and not IsSecret(v) and v == true
end

-- Returns nil when there is no nameplate, else the list of icons it shows (may be empty).
function PlateIcons(unit, max)   -- the local declared above
    local pf = PlateFrameFor(unit)
    if not pf then return nil end
    local uf = rawget(pf, "UnitFrame") or pf
    local af = rawget(uf, "AurasFrame")
    if type(af) ~= "table" then return nil end
    local token = PlateFor(unit)
    M.stats.plate.found = M.stats.plate.found + 1
    local out = {}
    for _, listName in ipairs(PLATE_LISTS) do
        local lf = rawget(af, listName)
        if type(lf) == "table" then
            local ok, kids = pcall(function() return { lf:GetChildren() } end)
            if ok then
                local shown = {}
                for _, f in ipairs(kids) do
                    -- hook every icon's countdown early, so its next timer is caught
                    local hcd = CooldownOf(f)
                    if hcd then HookCooldown(hcd); plateCDs[hcd] = true end
                    local icon = rawget(f, "Icon") or rawget(f, "icon")
                    if type(icon) == "table" and icon.GetTexture and Shown(f) then
                        local li = rawget(f, "layoutIndex")
                        shown[#shown + 1] = { f = f, icon = icon, order = (not IsSecret(li) and type(li) == "number") and li or #shown }
                    end
                end
                table.sort(shown, function(x, y) return x.order < y.order end)
                for _, sf in ipairs(shown) do
                    if #out >= max then break end
                    local okX, tex = pcall(sf.icon.GetTexture, sf.icon)
                    local cd = CooldownOf(sf.f)
                    if cd then HookCooldown(cd) end
                    local id = rawget(sf.f, "auraInstanceID")
                    local sid = rawget(sf.f, "spellID") or rawget(sf.f, "spellId")
                    out[#out + 1] = { unit = token, index = #out + 1, data = {
                        icon = okX and tex or nil, auraInstanceID = id, spellId = sid, isHarmful = true,
                        plateCD = cd, plateFrame = sf.f, cc = (listName == "CrowdControlListFrame"),
                        useADT = rawget(sf.f, "useAuraDisplayTime") } }
                end
            end
        end
    end
    M.stats.plate.icons = #out
    return out
end
M._t_PlateIcons = PlateIcons

local function Gather(unit, filter, max)
    local list, way = Reads(unit, filter, max)
    if #list > 0 then return list, way end
    -- the nameplate's own icons: when the unit has a nameplate they are what the game shows for
    -- your debuffs and crowd control, so they decide (an empty plate means none of yours)
    if SHOW_PLATE_ICONS and (unit == "target" or unit == "focus") and filter:find("HARMFUL", 1, true) then
        local icons = PlateIcons(unit, max)
        if icons then
            M.stats.ways[filter .. " plate icons"] = #icons
            return icons, "nameplate icons"
        end
    end
    -- the same unit through its nameplate
    if unit == "target" or unit == "focus" then
        local plate = PlateFor(unit)
        if plate then
            list, way = Reads(plate, filter, max)
            M.stats.ways[filter .. " plate"] = #list
            if #list > 0 then
                for _, e in ipairs(list) do e.unit = plate end
                return list, "nameplate " .. way
            end
        end
    end
    list = nil
    -- 5. what the game's aura events said
    if seen[unit] then
        list = {}
        local now = GetTime and GetTime() or 0
        for id, a in pairs(seen[unit]) do
            local exp = a.expirationTime
            local expired = not IsSecret(exp) and type(exp) == "number" and exp > 0 and exp < now
            if not expired and (IsSecret(exp) or type(exp) ~= "number" or exp <= 0) then
                local at = seenAt[a]
                expired = at ~= nil and now - at > SEEN_MAX and (IsSecret(exp) or type(exp) ~= "number")
            end
            if expired then
                seen[unit][id] = nil
            elseif #list < max and PassesFilter(unit, a, filter) then
                list[#list + 1] = { data = a, index = #list + 1 }
            end
        end
        table.sort(list, function(x, y) return x.data.auraInstanceID < y.data.auraInstanceID end)
        for i, e in ipairs(list) do e.index = i end
        M.stats.ways[filter .. " events"] = #list
    end
    -- 6. your own casts on your target (spells the events above didn't already cover)
    list = list or {}
    local fromEvents = #list
    if unit == "target" and filter:find("HARMFUL", 1, true) then
        local have = {}
        for _, e in ipairs(list) do
            local sid = e.data.spellId
            if not IsSecret(sid) and type(sid) == "number" then have[sid] = true end
        end
        local now = GetTime and GetTime() or 0
        local ids = {}
        for sid in pairs(casts) do ids[#ids + 1] = sid end
        table.sort(ids)
        for _, sid in ipairs(ids) do
            local c = casts[sid]
            if now >= c.start + c.duration then
                casts[sid] = nil
            elseif not have[sid] and #list < max then
                list[#list + 1] = { data = { spellId = sid, icon = c.icon, duration = c.duration,
                    expirationTime = c.start + c.duration, isHarmful = true, isFromPlayerOrPlayerPet = true },
                    index = #list + 1 }
                M.stats.casts.used = M.stats.casts.used + 1
            end
        end
        M.stats.ways[filter .. " casts"] = #list - fromEvents
    end
    if #list > 0 then return list, (#list > fromEvents and fromEvents > 0) and "events+casts"
        or (fromEvents > 0 and "events" or "casts") end
    return {}, "none"
end

-- Gives an icon's cooldown the aura's time (from its id, or its own times for the old API).
-- Each try is checked: a time that turns out to be zero (seen on enemy auras on this client) counts
-- as failed and the next way is tried, instead of leaving the icon without numbers.
M.stats.timer = { data = 0, id = 0, secret = 0, none = 0 }
local function MirrorPlate(cd, unit, a)
    local P = M.stats.plate
    local src = a.plateCD
    -- 1. exactly what the game last gave its own icon's countdown. The game's icon keeps its time
    -- in "aura display time" (useAuraDisplayTime), so ours is switched the same way first. The
    -- values are hidden from addons; if the widget won't take them straight, they are wrapped in a
    -- duration object, which is the form hidden times are meant to travel in.
    local seenCD = src and cdSeen[src]
    if seenCD then
        local useADT = a.useADT
        if cd.SetUseAuraDisplayTime and not IsSecret(useADT) then pcall(cd.SetUseAuraDisplayTime, cd, useADT == true) end
        local m, x, y = seenCD[1], seenCD[2], seenCD[3]
        P.lastArgs = string.format("%s(%s, %s)", tostring(m), IsSecret(x) and "secret" or type(x), IsSecret(y) and "secret" or type(y))
        if type(cd[m]) == "function" then
            local ok, err = pcall(cd[m], cd, x, y)
            if ok then P.mirrored = P.mirrored + 1; P.how = "direct"; return true end
            P.lastError = tostring(err)
        end
        if m == "SetCooldown" and C_DurationUtil and C_DurationUtil.CreateDuration and cd.SetCooldownFromDurationObject then
            local okD, d = pcall(C_DurationUtil.CreateDuration)
            if okD and d then
                for _, fn in ipairs({ "SetTimeFromStart", "SetTimeSpan", "SetStartAndDuration" }) do
                    if type(d[fn]) == "function" and pcall(d[fn], d, x, y)
                        and pcall(cd.SetCooldownFromDurationObject, cd, d) then
                        P.mirrored = P.mirrored + 1; P.how = "duration object (" .. fn .. ")"; return true
                    end
                end
            end
        end
        if m == "SetCooldown" and cd.SetCooldownFromExpirationTime then
            -- last try: some clients take (start, duration) here too
            local ok = pcall(cd.SetCooldownFromExpirationTime, cd, x, y)
            if ok then P.mirrored = P.mirrored + 1; P.how = "from expiration time"; return true end
        end
    end
    -- 2. by the aura id the icon carries
    local id = a.auraInstanceID
    if (IsSecret(id) or id ~= nil) and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local ok, dur = pcall(C_UnitAuras.GetAuraDuration, unit or "target", id)
        if ok and dur ~= nil and pcall(cd.SetCooldownFromDurationObject, cd, dur) then P.byID = P.byID + 1; return true end
    end
    -- 3. the game's countdown times, when they can be read
    if src and src.GetCooldownTimes then
        local ok, st, du = pcall(src.GetCooldownTimes, src)
        if ok and not IsSecret(st) and not IsSecret(du) and type(st) == "number" and type(du) == "number" and du > 0 then
            cd:SetCooldown(st / 1000, du / 1000)
            P.byTimes = P.byTimes + 1
            return true
        end
    end
    -- 4. your cast of the spell with this icon
    local tex = a.icon
    if not IsSecret(tex) and tex ~= nil then
        local now = GetTime()
        for _, c in pairs(casts) do
            if c.icon ~= nil and not IsSecret(c.icon) and c.icon == tex and now < c.start + c.duration then
                cd:SetCooldown(c.start, c.duration)
                P.byCast = P.byCast + 1
                return true
            end
        end
    end
    P.noTimer = P.noTimer + 1
    return false
end

local function FeedData(cd, unit, a)
    if a.plateFrame then return MirrorPlate(cd, unit, a) end
    local T = M.stats.timer
    local exp, dur = a.expirationTime, a.duration
    local plain = not IsSecret(exp) and not IsSecret(dur) and type(dur) == "number" and type(exp) == "number"
    -- 1. the aura's own times, when they can be read and are real
    if plain and dur > 0 and exp > 0 then
        cd:SetCooldown(exp - dur, dur)
        T.data = T.data + 1
        return true
    end
    -- 2. by the aura's id (duration object, or the times looked up again)
    local id = a.auraInstanceID
    if (IsSecret(id) or id ~= nil) and Feed(cd, unit, id) then
        T.id = T.id + 1
        return true
    end
    -- 3. hidden times handed straight to the cooldown
    if not plain and exp ~= nil and dur ~= nil and cd.SetCooldownFromExpirationTime
        and pcall(cd.SetCooldownFromExpirationTime, cd, exp, dur) and Running(cd) then
        T.secret = T.secret + 1
        return true
    end
    T.none = T.none + 1
    return false
end

-- Fills one kind (buffs or debuffs) and returns how many icons were shown and the rows used.
local function FillKind(unit, set, kind, startRow, skip)
    local o = O()
    local list = set[kind]
    local filter = (kind == "buffs") and "HELPFUL" or (o.onlyMine and "HARMFUL|PLAYER" or "HARMFUL")
    local on = ((kind == "buffs") and o.buffs or o.debuffs) and not skip
    local size, perRow = o.iconSize, math.max(1, o.perRow)
    local n = 0
    if on then
        local auras, way = Gather(unit, filter, o.max)
        M.stats["way_" .. kind] = way
        for _, e in ipairs(auras) do
            local a = e.data
            n = n + 1
            local b = list[n]
            if not b then
                b = NewIcon(set.holder); list[n] = b
                local okL, lvl = pcall(set.holder.GetFrameLevel, set.holder)
                if okL and not IsSecret(lvl) and type(lvl) == "number" then pcall(b.SetFrameLevel, b, lvl + 2) end
            end
            local ru = e.unit or unit
            b.unit, b.index, b.filter, b.auraID = ru, e.index, filter, a.auraInstanceID
            b.way, b.spellId = way, a.spellId
            b:EnableMouse(o.tooltip and true or false)
            b:SetSize(size, size)
            b:ClearAllPoints()
            local col, row = (n - 1) % perRow, startRow + math.floor((n - 1) / perRow)
            local gap = o.spacing or 3
            b:SetPoint("TOPLEFT", set.holder, "TOPLEFT", col * (size + gap), -row * (size + gap))
            pcall(b.tex.SetTexture, b.tex, a.icon)
            if kind == "debuffs" then b.bg:SetColorTexture(0.8, 0.1, 0.1, 1) else b.bg:SetColorTexture(0, 0, 0, 1) end
            pcall(b.count.SetText, b.count, StackText(ru, a))
            local fs = b.cd.GetCountdownFontString and b.cd:GetCountdownFontString()
            if fs then
                local okF, font = pcall(fs.GetFont, fs)
                pcall(fs.SetFont, fs, (okF and font) or STANDARD_TEXT_FONT, TimerSize(), "OUTLINE")
            end
            if not FeedData(b.cd, ru, a) then pcall(b.cd.Clear, b.cd) end
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

-- A mouse cover over the whole icon area, under our icons and above the game's hidden icons.
-- Without it the gaps between our icons (and the space past them) let the mouse reach a hidden
-- game icon, whose tooltip is some other aura. It only takes mouse movement (clicks pass
-- through) and shows no tooltip. It reaches as wide as the unit frame and one row lower than ours,
-- since the game lays out its own icons in a different size and row length.
local SHIELD_MIN_WIDTH = 190
function Shield(unit, set, count, rows)   -- the local declared above NewIcon
    local o = O()
    local sh = set.shield
    if not sh then
        sh = CreateFrame("Frame", nil, set.holder)
        pcall(sh.SetMouseClickEnabled, sh, false)
        pcall(sh.SetMouseMotionEnabled, sh, true)
        sh:SetScript("OnEnter", function() if GameTooltip then GameTooltip:Hide() end end)
        set.shield = sh
        -- our icons go above it
        local okL, lvl = pcall(set.holder.GetFrameLevel, set.holder)
        if okL and not IsSecret(lvl) and type(lvl) == "number" then
            pcall(sh.SetFrameLevel, sh, lvl)
            for _, k in ipairs({ "buffs", "debuffs" }) do
                for _, b in ipairs(set[k]) do pcall(b.SetFrameLevel, b, lvl + 2) end
            end
        end
    end
    if not (o.tooltip and o.hideGame) or count == 0 then sh:Hide(); M.stats.shield = nil; return end
    local size, gap = o.iconSize, o.spacing or 3
    local perRow = math.max(1, o.perRow)
    local w = math.max(SHIELD_MIN_WIDTH, perRow * (size + gap))
    local h = (math.max(1, rows) + 1) * (size + gap)
    sh:ClearAllPoints()
    sh:SetPoint("TOPLEFT", set.holder, "TOPLEFT", -gap, gap)
    sh:SetSize(w + gap, h + gap)
    sh:Show()
    M.stats.shield = string.format("%dx%d", w + gap, h + gap)
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
    local anchor, isBar = AnchorOf(unit)
    if isBar then
        set.holder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", o.x, o.y)
    else
        set.holder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", o.x + 5, o.y + 36)
    end
    set.holder:Show()
    local nb, rb = FillKind(unit, set, "buffs", 0)
    local nd, rd = FillKind(unit, set, "debuffs", rb)
    M.stats.ownShown[unit] = nb + nd
    Shield(unit, set, nb + nd, (rb or 0) + (rd or 0))
    -- On an enemy where nothing at all could be read (no buffs, no debuffs, by any way), the game's
    -- own icons are shown instead: no timers, but your debuffs stay visible. If the enemy really
    -- has no auras the game shows nothing either, and an enemy with readable buffs keeps ours.
    local okC, enemy = pcall(UnitCanAttack, "player", unit)
    enemy = okC and not IsSecret(enemy) and enemy == true
    M.stats.fallback = M.stats.fallback or {}
    if enemy and o.hideGame and nb + nd == 0 then
        M.stats.fallback[unit] = true
        HideGame(unit, false)
    else
        M.stats.fallback[unit] = false
    end
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
    pcall(HookAllCooldowns)
    savedCVar = S().savedCVar
    if type(S().own) ~= "table" then S().own = {} end
    local o = S().own
    if o.layout == nil then
        -- 2.13.0 placed the row from the frame corner (5, 32): move it under the mana bar
        if o.x == 5 and o.y == 32 then o.x, o.y = 0, -4 end
        o.layout = 2
    end
    if o.layout < 4 then
        -- 2.16.7: our icons show their own tooltip again and sit above the game's hidden icons
        -- (with ours mouse-transparent, hovering hit the hidden game icon underneath, which is
        -- laid out differently, so the tooltip showed another aura)
        o.tooltip = true
    end
    if o.layout < 3 then
        -- 2.16.2: 5 icons per row (the old 8 ran far past the frame); a changed value is kept
        if o.perRow == nil or o.perRow == 8 then o.perRow = 5 end
        o.layout = 3
    end
    if o.layout < 4 then o.layout = 4 end
    for k, v in pairs(M.defaults.own) do if o[k] == nil then o[k] = v end end
    local runner = CreateFrame("Frame")
    local acc = 0
    runner:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 0.05 then return end
        acc = 0
        local okP, hasPlate, changed = pcall(PlateCheck)
        if okP and changed then dirty.target = true end
        if next(pending) then pcall(DropUnconfirmed) end
        if next(casts) then
            local now = GetTime()
            local okD, dead = pcall(UnitIsDead, "target")
            if okD and not IsSecret(dead) and dead == true then
                for k in pairs(casts) do casts[k] = nil end
                dirty.target = true
            else
                for _, c in pairs(casts) do
                    if now >= c.start + c.duration then dirty.target = true; break end
                end
            end
        end
        local ok, err = pcall(Flush)
        if not ok then NS.ReportError("Aura Timers", err) end
    end)
    NS.On("UNIT_AURA", function(_, unit, info)
        if type(unit) ~= "string" then return end
        if unit == "target" or unit == "focus" then pcall(SeenUpdate, unit, info) end
        -- with a nameplate, only a new icon on it confirms a cast (PlateCheck); the target's
        -- auras "change" far too often on this client to tell anything
        if unit == "target" and not PlateFrameFor("target") then pcall(TargetAuraChanged, nil) end
        if unit:find("^nameplate") then
            -- the target's / focus's nameplate: its announcements count for them too
            for _, u in ipairs({ "target", "focus" }) do
                local okU, same = pcall(UnitIsUnit, unit, u)
                if okU and not IsSecret(same) and same == true then
                    M.stats.plateEvents = (M.stats.plateEvents or 0) + 1
                    pcall(SeenUpdate, u, info)
                    dirty[u] = true
                end
            end
        end
        if unit == "target" then dirty.target = true
        elseif unit == "focus" then dirty.focus = true end
        if unit:find("^nameplate") then dirty.plates[unit] = true end
    end)
    NS.On("PLAYER_TARGET_CHANGED", function()
        seen.target = {}
        for k in pairs(casts) do casts[k] = nil end
        for k in pairs(pending) do pending[k] = nil end
        plateCount, plateCC = nil, nil
        dirty.target = true
    end)
    NS.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
        if IsSecret(unit) or (unit ~= "player" and unit ~= "pet") then return end
        local ok = pcall(CastLanded, spellID, unit == "pet")
        if ok then dirty.target = true end
    end)
    NS.On("PLAYER_FOCUS_CHANGED", function() seen.focus = {}; dirty.focus = true end)
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
    local ways = {}
    for k, v in pairs(st.ways) do ways[#ways + 1] = k .. "=" .. v end
    table.sort(ways)
    NS.Print("  aura reads (last target/focus update): " .. (#ways > 0 and table.concat(ways, "  ") or "none yet"))
    NS.Print(string.format("  read with: buffs %s, debuffs %s   game icons used instead on enemy: target %s, focus %s",
        tostring(st.way_buffs or "-"), tostring(st.way_debuffs or "-"),
        tostring(st.fallback and st.fallback.target), tostring(st.fallback and st.fallback.focus)))
    local sc = 0
    for _ in pairs(seen.target) do sc = sc + 1 end
    NS.Print(string.format("  aura events: added %d  removed %d  full updates %d  hidden ids %d   held for target now: %d",
        st.seen.added, st.seen.removed, st.seen.full, st.seen.secretIDs, sc))
    local nl = 0
    for _ in pairs(Learned()) do nl = nl + 1 end
    local cs = st.casts
    NS.Print(string.format("  your casts: tracked %d  landed %d  missed %d  shown %d   durations known: %d spells (learned %d this session, from description %d, unknown %d)",
        cs.seen, cs.confirmed, cs.missed, cs.used, nl, cs.learned, cs.fromText, cs.unknown))
    NS.Print(string.format("  traps: placed %d   caught something (seen on the nameplate) %d   effect reported by the game %d",
        st.traps.placed, st.traps.caught, st.traps.effects))
    local plate = PlateFor("target")
    local pr = "no nameplate"
    if plate then
        local hb = Reads(plate, "HARMFUL", 16)
        local hp = Reads(plate, "HELPFUL", 16)
        pr = string.format("%s: debuffs read %d, buffs read %d", plate, #hb, #hp)
    end
    NS.Print(string.format("  target's nameplate: %s   nameplate aura events used: %d", pr, st.plateEvents or 0))
    local P = st.plate
    local icons = PlateIcons("target", 40)
    NS.Print(string.format("  nameplate icons used: %s   timers from: the game's countdown %d, aura id %d, readable times %d, your cast %d, none %d",
        icons and (#icons .. " showing now") or "no nameplate", P.mirrored, P.byID, P.byTimes, P.byCast, P.noTimer))
    NS.Print(string.format("    copying: last seen %s   worked with: %s   last error: %s   duration objects: %s",
        tostring(P.lastArgs or "-"), tostring(P.how or "-"), tostring(P.lastError or "none"),
        tostring(C_DurationUtil ~= nil and C_DurationUtil.CreateDuration ~= nil)))
    -- what the target's nameplate draws itself (its own aura icons): can addons see them?
    local okP, pf = pcall(function() return C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target") end)
    if not okP or type(pf) ~= "table" then
        NS.Print("  target's nameplate icons: no nameplate for your target (turn enemy nameplates on)")
    else
        local c = { frames = 0, icons = 0, iconsShown = 0, texRead = 0, texHidden = 0, texEmpty = 0, cds = 0, cdsShown = 0, ex = {} }
        local function Shown(f) local ok, v = pcall(f.IsShown, f); return ok and not IsSecret(v) and v == true end
        local function Num(v) return (not IsSecret(v) and type(v) == "number") and string.format("%.0f", v) or "?" end
        local function Walk(f, depth, path)
            if c.frames > 400 or depth > 7 then return end
            c.frames = c.frames + 1
            local okT, kind = pcall(f.GetObjectType, f)
            if okT and kind == "Cooldown" then
                c.cds = c.cds + 1
                if Shown(f) then c.cdsShown = c.cdsShown + 1 end
            end
            local icon = rawget(f, "Icon") or rawget(f, "icon")
            if type(icon) == "table" and icon.GetTexture then
                c.icons = c.icons + 1
                if Shown(f) then
                    c.iconsShown = c.iconsShown + 1
                    local okX, tex = pcall(icon.GetTexture, icon)
                    if okX and IsSecret(tex) then c.texHidden = c.texHidden + 1
                    elseif okX and tex ~= nil then c.texRead = c.texRead + 1
                    else c.texEmpty = c.texEmpty + 1 end
                    if #c.ex < 3 then
                        local okW, w = pcall(f.GetWidth, f)
                        c.ex[#c.ex + 1] = string.format("%s %sx%s", path, okW and Num(w) or "?", okW and Num(w) or "?")
                    end
                end
            end
            local okC, kids = pcall(function() return { f:GetChildren() } end)
            if okC then
                for i, k in ipairs(kids) do
                    local nm = "#" .. i
                    pcall(function()
                        for key, v in pairs(f) do
                            if type(key) == "string" and not IsSecret(v) and rawequal(v, k) then nm = key; break end
                        end
                    end)
                    Walk(k, depth + 1, path .. "." .. nm)
                end
            end
        end
        pcall(Walk, rawget(pf, "UnitFrame") or pf, 0, "plate")
        NS.Print(string.format("  target's nameplate icons: frames looked at %d   icon frames %d (shown %d: icon readable %d, hidden %d, empty %d)   cooldowns %d (shown %d)",
            c.frames, c.icons, c.iconsShown, c.texRead, c.texHidden, c.texEmpty, c.cds, c.cdsShown))
        if #c.ex > 0 then NS.Print("    e.g. " .. table.concat(c.ex, "   ")) end
        -- the fields the game keeps on its first shown plate icon (to find its aura id)
        local icons = PlateIcons("target", 40)
        if icons and icons[1] and icons[1].data.plateFrame then
            local f = icons[1].data.plateFrame
            local keys = {}
            pcall(function()
                for k, v in pairs(f) do
                    if type(k) == "string" and k ~= "0" then
                        local tv = IsSecret(v) and "secret" or type(v)
                        if tv ~= "function" and tv ~= "userdata" then keys[#keys + 1] = k .. "=" .. tv end
                    end
                end
            end)
            table.sort(keys)
            NS.Print("    first plate icon fields: " .. table.concat(keys, " ", 1, math.min(#keys, 30)))
            local okS, sc = pcall(function() return cdSeen[icons[1].data.plateCD] end)
            NS.Print(string.format("    its countdown seen: %s   all countdowns watched: %s",
                (okS and sc and tostring(sc[1])) or "no", tostring(M.stats.cdHookAll)))
        end
    end
    NS.Print(string.format("  event durations: readable %d  hidden %d  zero/missing %d   timers given from: aura times %d, aura id %d, hidden times %d, none %d",
        st.seen.durRead or 0, st.seen.durHidden or 0, st.seen.durZero or 0,
        st.timer.data, st.timer.id, st.timer.secret, st.timer.none))
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
    page:Check("My icons show their own tooltip", function() return O().tooltip end,
        function(v) O().tooltip = v; A() end)
    page:Note("Our icons sit on top of the game's hidden icons, so hovering one shows the aura it really "
        .. "shows. Turned off, the mouse goes through to the game's hidden icon underneath, which can be a "
        .. "different aura.")
    page:Slider("Icon size", 14, 40, 1, function() return O().iconSize end, function(v) O().iconSize = v; A() end)
    page:Slider("Time text size (0 = fit the icon)", 0, 24, 1, function() return O().timerSize end,
        function(v) O().timerSize = v; A() end)
    page:Slider("Space between icons", 0, 10, 1, function() return O().spacing end, function(v) O().spacing = v; A() end)
    page:Slider("Icons per row", 3, 16, 1, function() return O().perRow end, function(v) O().perRow = v; A() end)
    page:Slider("Most icons of each kind", 4, 32, 1, function() return O().max end, function(v) O().max = v; A() end)
    page:Slider("Move left / right", -150, 150, 1, function() return O().x end, function(v) O().x = v; A() end)
    page:Slider("Move up / down", -150, 150, 1, function() return O().y end, function(v) O().y = v; A() end)
    page:Button("Reset position", function() O().x, O().y = 0, -4; A() end)
    page:Note("This client keeps its own target aura icons out of reach of addons, so Aimbot UI draws its "
        .. "own under the mana bar: buffs first, debuffs (red border) below.")

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
