--[[
  Aimbot UI - Diminish (diminishing returns tracker)

  Shows how far each crowd-control category is diminished, as small icons next to your
  target and focus frames, on enemy nameplates, and for yourself. Border colour = what the
  NEXT crowd control of that kind will do:  green 50%   yellow 25%   red immune.
  The timer counts down until that category resets.

  Idea and look inspired by the Diminish addon by Wardz (MIT licence). This is new code
  written for Aimbot UI; no code was copied.

  Where the information comes from (WoW Forever is a Midnight 12.0-style client, and the
  combat log that the original Diminish used is closed to addons there):
    1. "game"  - the game's own DR event UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED.
                 Its exact data on Forever is not known yet, so the reader is defensive and
                 every payload shape it sees is recorded for /aimbot diag. If the values are
                 secret, they are passed straight to the icon widgets (no comparisons).
    2. "auras" - crowd-control debuffs the client lets us read on target / focus /
                 nameplates / you (Data\DRSpells.lua), with the classic rules:
                 18 s reset, 100% -> 50% -> 25% -> immune.
  "Auto" uses the game event when it gives usable data for that category, else auras.

  Nothing here touches Blizzard frames: our own frames are only anchored to them.
  Every game call is wrapped in pcall, every value is checked with NS.IsSecret.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Diminish",
    group = "Combat",
    desc = "Diminishing returns icons on your target, focus, enemy nameplates and yourself. "
        .. "Border colour shows what the next crowd control will do (green 50%, yellow 25%, red immune), "
        .. "the timer shows when it resets.",
    defaults = {
        enabled     = true,
        source      = "auto",                  -- "auto", "game" or "auras"
        target      = true,
        focus       = true,
        nameplates  = true,
        player      = true,
        friendly    = false,                   -- also track friendly players (target / focus)
        pve         = false,                   -- also track NPCs
        cats = { stun = true, incapacitate = true, disorient = true, root = true, silence = true, disarm = false },
        resetTime   = 18,
        stages      = 3,                       -- 3 = 50% / 25% / immune (classic), 2 = 50% / immune
        iconSize    = 26,
        plateSize   = 20,
        spacing     = 3,
        showTimer   = true,
        showStage   = true,
        swipe       = true,
        colorHalf    = { 0.20, 1.00, 0.20, 1 },
        colorQuarter = { 1.00, 0.85, 0.10, 1 },
        colorImmune  = { 1.00, 0.15, 0.15, 1 },
        pos = {
            target = { side = "right", x = 4,  y = 0 },
            focus  = { side = "right", x = 4,  y = 0 },
            player = { side = "bottom", x = 0, y = -4 },
            plate  = { side = "top",   x = 0,  y = 4 },
        },
        samples     = {},                      -- recorded shapes of the game's DR event (no values)
    },
}
NS.RegisterModule("diminish", M)

local function S() return NS.db.mod.diminish end
local issecret = NS.IsSecret
local function Secret(v) return issecret(v) end
local function IsStr(v) return type(v) == "string" and not Secret(v) end
local function Num(v) if type(v) == "number" and not Secret(v) then return v end end
local function Now() return GetTime and GetTime() or 0 end

----------------------------------------------------------------------
-- Categories
----------------------------------------------------------------------
local CATS = { "stun", "incapacitate", "disorient", "root", "silence", "disarm" }
local CAT_LABEL = {
    stun = "Stuns", incapacitate = "Incapacitates (Polymorph, Sap ...)", disorient = "Disorients (Fear, Blind ...)",
    root = "Roots", silence = "Silences", disarm = "Disarms",
}
local CAT_ICON = {
    stun = "Interface\\Icons\\Ability_Rogue_KidneyShot",
    incapacitate = "Interface\\Icons\\Spell_Nature_Polymorph",
    disorient = "Interface\\Icons\\Spell_Shadow_Possession",
    root = "Interface\\Icons\\Spell_Frost_FrostNova",
    silence = "Interface\\Icons\\Spell_Shadow_ImpPhaseShift",
    disarm = "Interface\\Icons\\Ability_Warrior_Disarm",
}
local CAT_ORDER = {}
for i, c in ipairs(CATS) do CAT_ORDER[c] = i end

-- Game enum number -> our key. Built from Enum.SpellDiminishCategory when present.
local ENUM_TO_CAT = { [0] = "root", [2] = "stun", [4] = "incapacitate", [5] = "disorient", [6] = "silence", [7] = "disarm" }
local function BuildEnumMap()
    local E = _G.Enum and _G.Enum.SpellDiminishCategory
    if type(E) ~= "table" then return end
    local byName = { Root = "root", Stun = "stun", Incapacitate = "incapacitate", Disorient = "disorient",
        Silence = "silence", Disarm = "disarm" }
    local map = {}
    for name, v in pairs(E) do
        local key = byName[name]
        if key and Num(v) then map[v] = key end
    end
    if next(map) then ENUM_TO_CAT = map end
end

local NAME_TO_CAT = {}
local function BuildSpellMap()
    NAME_TO_CAT = {}
    for cat, list in pairs(NS.DRSpells or {}) do
        for _, name in ipairs(list) do NAME_TO_CAT[name] = cat end
    end
end

----------------------------------------------------------------------
-- State
--   tracks[key][cat] = { stage, ccUp, ccExpire, ccDur, resetAt, icon, src,
--                        gStart, gDur, gImmune }
--   key = the unit's GUID when it can be read, else the unit token.
----------------------------------------------------------------------
local tracks = {}
local secretRecs = {}          -- [key] = { { cat, start, dur, immune, at }, ... } (values may be secret)
local stats = { scans = 0, ccSeen = 0, events = 0, eventsSecret = 0, eventsUsed = 0, eventsNoUnit = 0,
                renderErrors = 0 }
local test = { untilT = 0 }

local function KeyFor(unit)
    if not IsStr(unit) then return nil end
    if UnitGUID then
        local ok, g = pcall(UnitGUID, unit)
        if ok and IsStr(g) and g ~= "" then return g end
    end
    return unit
end

local function Rec(key, cat, create)
    local t = tracks[key]
    if not t then
        if not create then return nil end
        t = {}; tracks[key] = t
    end
    local r = t[cat]
    if not r and create then r = { stage = 0 }; t[cat] = r end
    return r
end

local function GameActive(r, now)
    return r and r.src == "game" and r.gStart and r.gDur and now < r.gStart + r.gDur
end

local function Active(r, now)
    if not r then return false end
    if GameActive(r, now) then return true end
    if r.ccUp then return true end
    return r.resetAt ~= nil and now < r.resetAt
end

-- What the next crowd control of this kind will do: "half", "quarter" or "immune".
local function Severity(r)
    if r.src == "game" and r.gImmune then return "immune" end
    local n, max = r.stage or 1, S().stages == 2 and 2 or 3
    if n >= max then return "immune" end
    if n == 2 then return "quarter" end
    return "half"
end

-- Timer: when the category resets, and how long the whole window is (for the swipe).
local function Window(r, now)
    local reset = S().resetTime or 18
    if GameActive(r, now) then return r.gStart + r.gDur, r.gDur end
    if r.ccUp then
        local exp = r.ccExpire or now
        return exp + reset, (r.ccDur or 0) + reset
    end
    if r.resetAt then return r.resetAt, reset end
end

----------------------------------------------------------------------
-- Source 2: debuffs
----------------------------------------------------------------------
local function GetAura(unit, i)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
        if not ok then return false end
        if type(d) ~= "table" then return nil end
        return true, d.name, d.icon, d.duration, d.expirationTime
    end
    local fn = UnitDebuff or UnitAura
    if not fn then return nil end
    local ok, name, icon, _, _, duration, expiration = pcall(fn, unit, i, "HARMFUL")
    if not ok then return false end
    if name == nil then return nil end
    return true, name, icon, duration, expiration
end

local function Tracked(unit)
    if unit == "player" then return true end
    local s = S()
    local ok, exists = pcall(UnitExists, unit)
    if not ok or Secret(exists) or not exists then return false end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if okP and not Secret(isPlayer) and not isPlayer and not s.pve then return false end
    if not s.friendly then
        local okA, can = pcall(UnitCanAttack, "player", unit)
        if okA and not Secret(can) and not can then return false end
    end
    return true
end

-- Records a crowd control application / removal in one category. Used by the aura scan
-- and by the offline tests.
local function AuraState(key, cat, present, expire, dur, icon, now)
    local r = Rec(key, cat, present)
    if not r then return end
    if S().source ~= "auras" and GameActive(r, now) then return end   -- the game knows better
    if present then
        if not r.ccUp then
            if r.resetAt and now < r.resetAt then r.stage = (r.stage or 0) + 1 else r.stage = 1 end
            stats.ccSeen = stats.ccSeen + 1
        end
        r.ccUp, r.src = true, "aura"
        r.ccExpire = (expire and expire > 0) and expire or nil
        r.ccDur = (dur and dur > 0) and dur or nil
        if icon then r.icon = icon end
    elseif r.ccUp then
        r.ccUp = false
        r.resetAt = now + (S().resetTime or 18)
    end
end

local function ScanUnit(unit)
    local s = S()
    if s.source == "game" then return end
    if not Tracked(unit) then return end
    local key = KeyFor(unit)
    if not key then return end
    stats.scans = stats.scans + 1
    local present = {}
    for i = 1, 40 do
        local ok, name, icon, dur, expire = GetAura(unit, i)
        if not ok then break end
        if IsStr(name) then
            local cat = NAME_TO_CAT[name]
            if cat and s.cats[cat] then
                local e = Num(expire)
                local p = present[cat]
                if not p or (e and (not p.expire or e > p.expire)) then
                    present[cat] = { expire = e, dur = Num(dur), icon = (not Secret(icon)) and icon or nil }
                end
            end
        end
    end
    local now = Now()
    for _, cat in ipairs(CATS) do
        if s.cats[cat] then
            local p = present[cat]
            if p then AuraState(key, cat, true, p.expire, p.dur, p.icon, now)
            else AuraState(key, cat, false, nil, nil, nil, now) end
        end
    end
end

----------------------------------------------------------------------
-- Source 1: the game's DR event
----------------------------------------------------------------------
local function Shape(v)
    if Secret(v) then return "secret" end
    local t = type(v)
    if t == "string" then return "string(" .. v:sub(1, 20) .. ")" end
    if t == "number" or t == "boolean" then return t .. "(" .. tostring(v) .. ")" end
    return t
end

local function RecordSample(...)
    local s = S()
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        local d = Shape(v)
        if type(v) == "table" and not Secret(v) then
            local f = {}
            for k, fv in pairs(v) do
                if #f < 12 then f[#f + 1] = tostring(k) .. "=" .. Shape(fv) end
            end
            table.sort(f)
            d = "{" .. table.concat(f, ", ") .. "}"
        end
        parts[#parts + 1] = d
    end
    local line = table.concat(parts, " | ")
    local list = s.samples
    for _, old in ipairs(list) do if old == line then return end end
    table.insert(list, 1, line)
    while #list > 8 do table.remove(list) end
end

-- Pulls category / start / duration / immune out of the payload, whatever its shape.
-- Returns unit, fields (fields may be secret values).
local function ParseEvent(...)
    local unit, info, nums = nil, nil, {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if unit == nil and type(v) == "string" and not Secret(v) then unit = v
        elseif type(v) == "table" and not Secret(v) and not info then info = v
        elseif type(v) == "number" or Secret(v) then nums[#nums + 1] = v end
    end
    local f = {}
    if info then
        f.category = info.category or info.categoryID or info.diminishCategory
        f.start = info.startTime or info.start
        f.dur = info.duration
        f.immune = info.isImmune
        if f.immune == nil then f.immune = info.immune end
        f.show = info.showCountdown
        f.level = info.diminishLevel or info.level or info.stacks or info.count
    else
        f.category, f.start, f.dur = nums[1], nums[2], nums[3]
    end
    return unit, f
end

local function OnDREvent(...)
    stats.events = stats.events + 1
    pcall(RecordSample, ...)
    local s = S()
    if not s.enabled or s.source == "auras" then return end
    local unit, f = ParseEvent(...)
    if not unit then stats.eventsNoUnit = stats.eventsNoUnit + 1; return end
    local key = KeyFor(unit)
    if not key then return end

    local cat = Num(f.category) and ENUM_TO_CAT[f.category] or nil
    local start, dur = Num(f.start), Num(f.dur)
    local plain = cat and (f.start == nil or start) and (f.dur == nil or dur)
        and not Secret(f.immune) and not Secret(f.show) and not Secret(f.level)
    if not plain then
        -- Secret data: keep it only to hand straight to the icon widgets.
        stats.eventsSecret = stats.eventsSecret + 1
        local list = secretRecs[key] or {}
        secretRecs[key] = list
        table.insert(list, 1, { cat = f.category, start = f.start, dur = f.dur, immune = f.immune, at = Now() })
        while #list > 3 do table.remove(list) end
        return
    end
    if not s.cats[cat] then return end
    stats.eventsUsed = stats.eventsUsed + 1
    local r = Rec(key, cat, true)
    if (dur and dur <= 0) or f.show == false then
        r.src, r.gStart, r.gDur, r.gImmune = "game", nil, nil, nil
        return
    end
    local now = Now()
    local level = Num(f.level)
    if level then
        r.stage = level
    elseif not (GameActive(r, now) and r.gStart == start) then
        if GameActive(r, now) or (r.resetAt and now < r.resetAt) or r.ccUp then r.stage = (r.stage or 0) + 1
        else r.stage = 1 end
    end
    r.src = "game"
    r.gStart = start or now
    r.gDur = dur or (s.resetTime or 18)
    r.gImmune = f.immune and true or false
    if r.gImmune then r.stage = math.max(r.stage or 1, s.stages == 2 and 2 or 3) end
end

----------------------------------------------------------------------
-- Icons
----------------------------------------------------------------------
local containers = {}          -- name -> container ("target", "focus", "player", or a nameplate unit)

local function MakeIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.border:SetColorTexture(0, 0, 0, 1)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 2, -2)
    b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.tex)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
    b.cd:SetReverse(true)
    b.overlay = CreateFrame("Frame", nil, b)
    b.overlay:SetAllPoints()
    b.overlay:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.timer = b.overlay:CreateFontString(nil, "OVERLAY")
    b.timer:SetPoint("CENTER", 0, 0)
    b.stage = b.overlay:CreateFontString(nil, "OVERLAY")
    b.stage:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
    return b
end

local function GetContainer(name)
    local c = containers[name]
    if c then return c end
    c = CreateFrame("Frame", nil, UIParent)
    c:SetSize(1, 1)
    c:SetFrameStrata("MEDIUM")
    c.icons = {}
    c.name = name
    c:Hide()
    containers[name] = c
    return c
end

local FRAMES = { target = { "TargetFrame" }, focus = { "FocusFrame" }, player = { "PlayerFrame" } }
local SIDE = {
    right  = { "LEFT", "RIGHT" },  left = { "RIGHT", "LEFT" },
    top    = { "BOTTOM", "TOP" },  bottom = { "TOP", "BOTTOM" },
}

local function Position(c, anchorFrame, p)
    local sp = SIDE[p.side] or SIDE.right
    c:ClearAllPoints()
    local ok = anchorFrame and pcall(c.SetPoint, c, sp[1], anchorFrame, sp[2], p.x or 0, p.y or 0)
    if not ok then c:SetPoint("CENTER", UIParent, "CENTER", p.x or 0, (p.y or 0) - 150) end
end

local function PositionFixed(name)
    local c = GetContainer(name)
    local f = NS.ResolveFirst(FRAMES[name])
    Position(c, f, S().pos[name])
    c.anchorFound = f ~= nil
end

local function ApplyIconLook(b, size)
    b:SetSize(size, size)
    local font = STANDARD_TEXT_FONT
    b.timer:SetFont(font, math.max(8, math.floor(size * 0.46)), "OUTLINE")
    b.stage:SetFont(font, math.max(7, math.floor(size * 0.32)), "OUTLINE")
end

local STAGE_TEXT = { half = "50%", quarter = "25%", immune = "0%" }

local function Paint(b, sev)
    local s = S()
    local col = sev == "immune" and s.colorImmune or sev == "quarter" and s.colorQuarter or s.colorHalf
    b.border:SetColorTexture(col[1], col[2], col[3], 1)
    b.border:SetVertexColor(1, 1, 1, 1)
    b.stage:SetText(s.showStage and STAGE_TEXT[sev] or "")
    b.stage:SetTextColor(col[1], col[2], col[3])
end

local function Entries(key, now)
    local list = {}
    local t = key and tracks[key]
    if t then
        for cat, r in pairs(t) do
            if S().cats[cat] and Active(r, now) then list[#list + 1] = { cat = cat, r = r } end
        end
    end
    table.sort(list, function(a, b) return CAT_ORDER[a.cat] < CAT_ORDER[b.cat] end)
    return list
end

local TEST = {
    { cat = "stun", r = { stage = 1, src = "test" } },
    { cat = "incapacitate", r = { stage = 2, src = "test" } },
    { cat = "disorient", r = { stage = 3, src = "test" } },
}

local function FmtTime(sec)
    if sec >= 10 then return tostring(math.floor(sec + 0.5)) end
    return string.format("%.0f", math.ceil(sec))
end

-- Fills container c with the entries for key (plus any secret records), size = icon size.
local function Fill(c, key, size, now)
    local s = S()
    local list = (now < test.untilT) and TEST or Entries(key, now)
    local sec = (now >= test.untilT) and key and secretRecs[key] or nil
    local n, sp = 0, s.spacing or 3
    local function Slot()
        n = n + 1
        local b = c.icons[n]
        if not b then b = MakeIcon(c); c.icons[n] = b end
        ApplyIconLook(b, size)
        b:ClearAllPoints()
        b:SetPoint("LEFT", c, "LEFT", (n - 1) * (size + sp), 0)
        b:Show()
        return b
    end
    for _, e in ipairs(list) do
        local b = Slot()
        local r = e.r
        b.cdSecret = nil
        b.tex:SetTexture(r.icon or CAT_ICON[e.cat])
        Paint(b, r.src == "test" and (r.stage >= 3 and "immune" or r.stage == 2 and "quarter" or "half") or Severity(r))
        local endT, total
        if r.src == "test" then endT, total = test.untilT, 30 else endT, total = Window(r, now) end
        local left = endT and (endT - now) or nil
        b.timer:SetText((s.showTimer and left and left > 0) and FmtTime(left) or "")
        if s.swipe and endT and total and total > 0 then
            if b.cdEnd ~= endT then b.cdEnd = endT; pcall(b.cd.SetCooldown, b.cd, endT - total, total) end
            b.cd:Show()
        else
            b.cdEnd = nil; b.cd:Hide()
        end
    end
    if sec then
        for i = #sec, 1, -1 do
            local e = sec[i]
            if now - e.at > 40 then table.remove(sec, i) end
        end
        for _, e in ipairs(sec) do
            local b = Slot()
            b.cdEnd = nil
            b.border:SetColorTexture(0.6, 0.6, 0.6, 1)
            b.border:SetVertexColor(1, 1, 1, 1)
            b.timer:SetText("")
            b.stage:SetText("")
            local okT = false
            if C_SpellDiminish and C_SpellDiminish.GetSpellDiminishCategoryInfo then
                local ok, info = pcall(C_SpellDiminish.GetSpellDiminishCategoryInfo, e.cat)
                if ok and type(info) == "table" and info.icon ~= nil then
                    okT = pcall(b.tex.SetTexture, b.tex, info.icon)
                end
            end
            if not okT then b.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
            if e.start ~= nil and e.dur ~= nil then
                if b.cdSecret ~= e then
                    b.cdSecret = e
                    if not pcall(b.cd.SetCooldown, b.cd, e.start, e.dur) then stats.renderErrors = stats.renderErrors + 1 end
                end
                b.cd:Show()
            else
                b.cd:Hide()
            end
            if e.immune ~= nil and b.border.SetVertexColorFromBoolean and CreateColor then
                b.border:SetColorTexture(1, 1, 1, 1)
                local cI, cH = s.colorImmune, s.colorHalf
                pcall(b.border.SetVertexColorFromBoolean, b.border, e.immune,
                    CreateColor(cI[1], cI[2], cI[3], 1), CreateColor(cH[1], cH[2], cH[3], 1))
            end
        end
    end
    for i = n + 1, #c.icons do c.icons[i]:Hide() end
    if n > 0 then
        c:SetSize(n * (size + sp) - sp, size)
        c:Show()
    else
        c:Hide()
    end
    return n
end

local function UnitShown(unit)
    local ok, e = pcall(UnitExists, unit)
    return ok and not Secret(e) and e and true or false
end

local function RefreshFixed(name, now)
    local s = S()
    local c = GetContainer(name)
    if not (s.enabled and s[name]) then c:Hide(); return end
    if now < test.untilT then Fill(c, nil, s.iconSize, now); return end
    if not UnitShown(name) or not Tracked(name) then c:Hide(); return end
    Fill(c, KeyFor(name), s.iconSize, now)
end

local plateUnits = {}

local function PositionPlate(unit)
    local c = GetContainer(unit)
    local plate
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok then plate = p end
    end
    if not plate then c:Hide(); c.plate = nil; return false end
    c.plate = plate
    local p = S().pos.plate
    local sp = SIDE[p.side] or SIDE.top
    c:ClearAllPoints()
    if not pcall(c.SetPoint, c, sp[1], plate, sp[2], p.x or 0, p.y or 0) then c.plate = nil; c:Hide(); return false end
    return true
end

local function RefreshPlate(unit, now)
    local s = S()
    local c = containers[unit]
    if not c then return end
    if not (s.enabled and s.nameplates) or not c.plate then c:Hide(); return end
    if unit == "player" then return end
    local okF, isFriend = pcall(UnitIsUnit, unit, "player")
    if okF and not Secret(isFriend) and isFriend then c:Hide(); return end
    if now >= test.untilT and not Tracked(unit) then c:Hide(); return end
    Fill(c, (now < test.untilT) and nil or KeyFor(unit), s.plateSize, now)
end

----------------------------------------------------------------------
-- Driver
----------------------------------------------------------------------
local dirty = {}
local driver

local function Expire(now)
    local reset = S().resetTime or 18
    for key, t in pairs(tracks) do
        local any = false
        for cat, r in pairs(t) do
            if r.ccUp and r.ccExpire and now > r.ccExpire + 1 then
                r.ccUp = false
                r.resetAt = r.ccExpire + reset
            end
            if Active(r, now) then any = true
            elseif r.resetAt and now > r.resetAt + 60 then t[cat] = nil end
        end
        if not any and not next(t) then tracks[key] = nil end
    end
end

local function Tick()
    local s = S()
    if not s.enabled then return end
    for unit in pairs(dirty) do
        dirty[unit] = nil
        local ok, err = pcall(ScanUnit, unit)
        if not ok then NS.ReportError("Diminish scan", err) end
    end
    local now = Now()
    Expire(now)
    RefreshFixed("target", now)
    RefreshFixed("focus", now)
    RefreshFixed("player", now)
    for unit in pairs(plateUnits) do RefreshPlate(unit, now) end
end

local function WatchedUnit(unit)
    if unit == "target" or unit == "focus" or unit == "player" then return true end
    return plateUnits[unit] ~= nil
end

local function ApplyPositions()
    PositionFixed("target")
    PositionFixed("focus")
    PositionFixed("player")
    for unit in pairs(plateUnits) do PositionPlate(unit) end
end

local function HideAll()
    for _, c in pairs(containers) do c:Hide() end
end

function M:Apply()
    BuildEnumMap()
    BuildSpellMap()
    if not S().enabled then HideAll(); return end
    ApplyPositions()
    dirty.target, dirty.focus, dirty.player = true, true, true
    for unit in pairs(plateUnits) do dirty[unit] = true end
end

function M:Init()
    BuildEnumMap()
    BuildSpellMap()
    driver = CreateFrame("Frame")
    local acc = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.1 then return end
        acc = 0
        local ok, err = pcall(Tick)
        if not ok then NS.ReportError("Diminish", err) end
    end)

    M.gameEvent = NS.On("UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED", function(_, ...)
        local ok, err = pcall(OnDREvent, ...)
        if not ok then NS.ReportError("Diminish game event", err) end
    end)
    NS.On("UNIT_AURA", function(_, unit)
        if IsStr(unit) and WatchedUnit(unit) then dirty[unit] = true end
    end)
    NS.On("PLAYER_TARGET_CHANGED", function() dirty.target = true end)
    NS.On("PLAYER_FOCUS_CHANGED", function() dirty.focus = true end)
    NS.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
        if not IsStr(unit) then return end
        plateUnits[unit] = true
        pcall(PositionPlate, unit)
        dirty[unit] = true
    end)
    NS.On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
        if not IsStr(unit) then return end
        plateUnits[unit] = nil
        local c = containers[unit]
        if c then c:Hide(); c.plate = nil end
    end)
    NS.On("PLAYER_ENTERING_WORLD", function()
        tracks, secretRecs = {}, {}
        pcall(ApplyPositions)
    end)
end

function M.Test()
    test.untilT = Now() + 30
    pcall(ApplyPositions)
    NS.Print("Diminish: showing test icons for 30 seconds (target, focus, you and nameplates).")
end

----------------------------------------------------------------------
-- Diagnostics
----------------------------------------------------------------------
function M:Diagnose()
    local s = S()
    local api = C_SpellDiminish
    local sup = "n/a"
    if api and api.IsSystemSupported then
        local ok, v = pcall(api.IsSystemSupported)
        sup = ok and (Secret(v) and "secret" or tostring(v)) or "error"
    end
    NS.Print(string.format("  source: %s   C_SpellDiminish: %s (supported: %s)   game DR event registered: %s",
        s.source, api and "yes" or "no", sup, tostring(M.gameEvent)))
    local E = _G.Enum and _G.Enum.SpellDiminishCategory
    NS.Print(string.format("  category enum: %s", type(E) == "table" and "yes" or "no"))
    NS.Print(string.format("  game events: %d  (used %d, secret %d, no unit %d)   aura scans: %d   CC seen: %d   render errors: %d",
        stats.events, stats.eventsUsed, stats.eventsSecret, stats.eventsNoUnit, stats.scans, stats.ccSeen, stats.renderErrors))
    local n = 0
    for _ in pairs(tracks) do n = n + 1 end
    local p = 0
    for _ in pairs(plateUnits) do p = p + 1 end
    NS.Print(string.format("  units tracked now: %d   nameplates seen: %d   spells in list: %d", n, p,
        (function() local c = 0; for _ in pairs(NAME_TO_CAT) do c = c + 1 end; return c end)()))
    for _, name in ipairs({ "target", "focus", "player" }) do
        local c = containers[name]
        NS.Print(string.format("  %s icons anchored to its frame: %s", name, tostring(c and c.anchorFound)))
    end
    if #s.samples == 0 then
        NS.Print("  game DR event payloads seen: none yet (get crowd controlled, or CC someone, then run this again)")
    else
        NS.Print("  game DR event payloads seen (shapes, newest first):")
        for i, line in ipairs(s.samples) do NS.Print("    " .. i .. ": " .. line) end
    end
end

----------------------------------------------------------------------
-- Settings page
----------------------------------------------------------------------
local SIDES = { { "right", "Right of the frame" }, { "left", "Left of the frame" },
    { "top", "Above the frame" }, { "bottom", "Below the frame" } }

local function PosRows(page, name, label)
    page:Cycle(label, SIDES, function() return S().pos[name].side end,
        function(v) S().pos[name].side = v; ApplyPositions() end)
    page:Slider(label .. ": move left / right", -200, 200, 1,
        function() return S().pos[name].x end, function(v) S().pos[name].x = v; ApplyPositions() end)
    page:Slider(label .. ": move up / down", -200, 200, 1,
        function() return S().pos[name].y end, function(v) S().pos[name].y = v; ApplyPositions() end)
end

function M.Build(page)
    page:Section("Where to show", "Which frames get DR icons")
    page:Check("Target frame", function() return S().target end, function(v) S().target = v end)
    page:Check("Focus frame", function() return S().focus end, function(v) S().focus = v end)
    page:Check("Enemy nameplates", function() return S().nameplates end, function(v) S().nameplates = v end)
    page:Check("Your own DR (next to your player frame)", function() return S().player end,
        function(v) S().player = v; dirty.player = true end)
    page:Check("Also track friendly players (target / focus)", function() return S().friendly end,
        function(v) S().friendly = v end)
    page:Check("Also track NPCs (PvE)", function() return S().pve end, function(v) S().pve = v end)
    page:Button("Show test icons (30 seconds)", function() M.Test() end, 240)
    page:Note("Test icons show on all four places so you can line them up. Nameplate test icons need a "
        .. "nameplate on screen.")

    page:Section("Categories", "Which kinds of crowd control to track")
    for _, cat in ipairs(CATS) do
        page:Check(CAT_LABEL[cat], function() return S().cats[cat] end,
            function(v) S().cats[cat] = v end)
    end

    page:Section("Tracking", "Where the DR information comes from")
    page:Cycle("Information from", {
            { "auto", "Auto (game, then debuffs)" },
            { "game", "Game's DR event only" },
            { "auras", "Debuffs only" },
        },
        function() return S().source end, function(v) S().source = v end)
    page:Note("Forever closes the combat log to addons, so DR comes from the game's own DR event where it "
        .. "gives usable data, and otherwise from crowd-control debuffs the game lets addons see. "
        .. "Grey icons are from the game event with hidden (secret) details.")
    page:Cycle("DR steps", { { 3, "50% / 25% / immune (classic)" }, { 2, "50% / immune (modern)" } },
        function() return S().stages end, function(v) S().stages = v end)
    page:Slider("Reset time (seconds after the effect ends)", 10, 25, 1,
        function() return S().resetTime end, function(v) S().resetTime = v end)

    page:Section("Look", "Size, text and colours")
    page:Slider("Icon size (target / focus / you)", 14, 48, 1,
        function() return S().iconSize end, function(v) S().iconSize = v end)
    page:Slider("Icon size (nameplates)", 10, 40, 1,
        function() return S().plateSize end, function(v) S().plateSize = v end)
    page:Slider("Space between icons", 0, 12, 1,
        function() return S().spacing end, function(v) S().spacing = v end)
    page:Check("Show the reset timer", function() return S().showTimer end, function(v) S().showTimer = v end)
    page:Check("Show 50% / 25% / 0% on the icon", function() return S().showStage end,
        function(v) S().showStage = v end)
    page:Check("Cooldown swipe", function() return S().swipe end, function(v) S().swipe = v end)
    page:Color("Next CC will be 50%", function() return S().colorHalf end,
        function(r, g, b) local c = S().colorHalf; c[1], c[2], c[3] = r, g, b end)
    page:Color("Next CC will be 25%", function() return S().colorQuarter end,
        function(r, g, b) local c = S().colorQuarter; c[1], c[2], c[3] = r, g, b end)
    page:Color("Immune", function() return S().colorImmune end,
        function(r, g, b) local c = S().colorImmune; c[1], c[2], c[3] = r, g, b end)

    page:Section("Position", "Where the icons sit")
    PosRows(page, "target", "Target icons")
    PosRows(page, "focus", "Focus icons")
    PosRows(page, "player", "Your icons")
    PosRows(page, "plate", "Nameplate icons")
end

-- For the offline tests.
M._t = { AuraState = AuraState, OnDREvent = OnDREvent, ParseEvent = ParseEvent, Entries = Entries,
    Severity = Severity, Window = Window, Expire = Expire, Tracks = function() return tracks end,
    Secret = function() return secretRecs end, Stats = stats, Reset = function() tracks, secretRecs = {}, {} end,
    BuildSpellMap = BuildSpellMap, NameToCat = function() return NAME_TO_CAT end, Tick = Tick, Test = M.Test }
