--[[
  Aimbot UI - Auto Shot Timer (Hunter)
  A bar that counts down to your next Auto Shot, with a marker where the shot's wind-up starts
  (stand still from there, or the shot is pushed back). Optional hybrid mode switches the bar to
  your main-hand swing while the target is in melee range.

  How it keeps time on Forever:
    * the game reports every shot and swing with PLAYER_SWING (its length and which weapon);
      a successful Auto Shot cast is the backup when that report is missing
    * Auto Shot on/off comes from START_AUTOREPEAT_SPELL / STOP_AUTOREPEAT_SPELL
    * the wind-up (0.5 s before haste by default) is held while you move, jump, cast something
      that stops Auto Shot, or the target is out of range
    * range comes from the game's swing range checks (C_SwingTimer and PLAYER_SWING_RANGE_UPDATE),
      with Auto Shot / Wing Clip spell range as the backup
  Reaching zero only means the next shot can go: the bar waits there until the game reports it.

  Idea from AutoShotTimer Forever by Antigravity and Gornax_ (GPL-3.0). This is new code written
  for Aimbot UI; no code from that addon was copied. Only our own frames are created.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Auto Shot Timer",
    group = "Combat",
    desc = "Hunter: a bar counting down to your next Auto Shot, with a marker where you have to stand "
        .. "still. Can switch to your melee swing when the target is in melee range.",
    defaults = {
        enabled      = true,
        locked       = true,
        outOfCombat  = false,       -- show while not in combat too
        hybrid       = false,       -- melee swing timer while the target is in melee range
        width        = 250,
        height       = 18,
        point        = { "CENTER", "CENTER", 0, -220 },
        windup       = 0.5,         -- Auto Shot wind-up before haste, in seconds
        colorMode    = "range",     -- "range", "class" or "custom"
        custom       = { 0.67, 0.83, 0.45, 1 },
        colors = {
            ranged  = { 0.67, 0.83, 0.45, 1 },
            melee   = { 0.20, 0.45, 1.00, 1 },
            blocked = { 0.95, 0.15, 0.10, 1 },
            unknown = { 0.60, 0.60, 0.60, 1 },
        },
        texture      = "smooth",
        background   = 0.55,        -- background opacity
        border       = 1,           -- border thickness in pixels (0 = none)
        showTick     = true,
        showSpark    = true,
        showText     = true,
        fontSize     = 12,
    },
}
NS.RegisterModule("autoshot", M)

local function S() return NS.db.mod.autoshot end
local function IsSecret(v) return NS.IsSecret(v) end

local AUTO_SHOT, WING_CLIP = 75, 2974
local RANGED = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.Ranged) or 2
local MAIN   = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand) or 0

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"
M.TEXTURES = {
    { "smooth",  "Smooth (game status bar)", "Interface\\TargetingFrame\\UI-StatusBar" },
    { "flat",    "Flat",                     "Interface\\Buttons\\WHITE8X8" },
    { "lorti",   "Lorti flat",               MEDIA .. "flat" },
    { "cast",    "Cast bar",                 "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}

-- Spells that don't stop Auto Shot's wind-up (Auto Shot itself, Aimed Shot, Multi-Shot ranks).
local KEEPS_WINDUP = { [75] = true,
    [19434] = true, [20900] = true, [20901] = true, [20902] = true, [20903] = true, [20904] = true,
    [2643] = true, [14288] = true, [14289] = true, [14290] = true, [25294] = true }
local keepNames = {}
local function LearnKeepNames()
    local get = C_Spell and C_Spell.GetSpellInfo
    for id in pairs(KEEPS_WINDUP) do
        local name
        if get then
            local ok, info = pcall(get, id)
            if ok and type(info) == "table" then name = info.name end
        elseif GetSpellInfo then
            local ok, n = pcall(GetSpellInfo, id)
            if ok then name = n end
        end
        if type(name) == "string" and not IsSecret(name) then keepNames[name] = true end
    end
end

local function KeepsWindup(spellID, name)
    if not IsSecret(spellID) and type(spellID) == "number" and KEEPS_WINDUP[spellID] then return true end
    return not IsSecret(name) and type(name) == "string" and keepNames[name] == true
end

local function Num(v)
    if IsSecret(v) or type(v) ~= "number" or v ~= v or v <= 0 or v >= math.huge then return nil end
    return v
end

local function Bool(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok and not IsSecret(v) and type(v) == "boolean" then return v end
    if ok and not IsSecret(v) and (v == 1 or v == 0) then return v == 1 end
    return nil
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local st = {
    hunter    = false,
    shooting  = false,      -- Auto Shot switched on
    stopped   = false,      -- STOP_AUTOREPEAT_SPELL seen (a late shot may still be reported)
    ends      = nil,        -- when the current shot cycle ends
    reported  = nil,        -- the last end time the game itself reported
    length    = 3.0,        -- length of the current cycle
    speed     = 3.0,        -- ranged weapon speed
    haste     = 1,          -- ranged haste multiplier
    moving    = false,
    falling   = false,
    casting   = false,
    castGUID  = nil,
    lastSwing = nil,        -- when PLAYER_SWING last reported a ranged shot
    melee     = nil,        -- { ends, length }
    meleeSpeed = nil,
    range     = {},         -- swing type -> { value = true/false/"unknown", at = time }
    preview   = nil,        -- end time of the test preview
}
M.state = st
M.stats = { shots = 0, backupShots = 0, swings = 0, rangeEvents = 0, holds = 0, secret = 0 }

local function Windup()
    local base = S().windup or 0.5
    return math.max(0.05, base / (st.haste or 1))
end

local function ReadHaste()
    st.haste = 1
    if type(GetRangedHaste) ~= "function" then return end
    local ok, a, b = pcall(GetRangedHaste)
    if not ok or IsSecret(a) or IsSecret(b) then M.stats.secret = M.stats.secret + 1; return end
    local total = (type(a) == "number" and a or 0) + (type(b) == "number" and b or 0)
    if total ~= total or total <= -90 or total > 1000 then return end
    st.haste = 1 + total / 100
end

local function ReadSpeed()
    ReadHaste()
    local speed
    if type(UnitRangedDamage) == "function" then
        local ok, v = pcall(UnitRangedDamage, "player")
        if ok then speed = Num(v) end
    end
    if type(UnitAttackSpeed) == "function" then
        -- Forever: main hand, off hand, ranged
        local ok, main, _, ranged = pcall(UnitAttackSpeed, "player")
        if ok then
            st.meleeSpeed = Num(main) or st.meleeSpeed
            speed = speed or Num(ranged)
        end
    end
    if speed then st.speed = math.max(speed, Windup()) end
end

local function HasEnemy()
    return Bool(UnitExists, "target") == true and Bool(UnitCanAttack, "player", "target") == true
        and Bool(UnitIsDeadOrGhost, "target") ~= true
end

local function InCombat()
    return Bool(UnitAffectingCombat, "player") == true
end

----------------------------------------------------------------------
-- Range
----------------------------------------------------------------------
local function EnableRangeChecks()
    if C_SwingTimer and type(C_SwingTimer.EnableRangeCheck) == "function" then
        pcall(C_SwingTimer.EnableRangeCheck, RANGED, true)
        pcall(C_SwingTimer.EnableRangeCheck, MAIN, true)
    end
end

-- true / false / nil (unknown) for one swing type
local function SwingInRange(kind)
    local ev = st.range[kind]
    local now = GetTime()
    if ev and now - ev.at <= 0.3 then
        if type(ev.value) == "boolean" then return ev.value end
        return nil
    end
    local v = Bool(C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange, kind)
    if v ~= nil then return v end
    if ev and type(ev.value) == "boolean" then return ev.value end
    return nil
end

-- "melee", "ranged", "blocked" (out of range) or "unknown"
local function RangeState()
    if not HasEnemy() then return "unknown" end
    local ranged, melee = SwingInRange(RANGED), SwingInRange(MAIN)
    local nativeMelee = melee
    local spell = C_Spell and C_Spell.IsSpellInRange or IsSpellInRange
    if ranged == nil then ranged = Bool(spell, AUTO_SHOT, "target") end
    if melee == nil then melee = Bool(spell, WING_CLIP, "target") end
    if nativeMelee == true then return "melee", ranged end
    if ranged == true then return "ranged", true end
    if melee == true then return "melee", ranged end
    if ranged == false then return "blocked", false end
    return "unknown", nil
end
M.RangeState = RangeState

----------------------------------------------------------------------
-- Timing
----------------------------------------------------------------------
local function ShotReported(length)
    local now = GetTime()
    st.length = math.max(length, Windup())
    st.ends = now + length
    st.reported = st.ends
    if not st.stopped then st.shooting = true end
end

local function StartShooting()
    ReadSpeed()
    local now = GetTime()
    st.shooting, st.stopped = true, false
    -- only a cooldown the game reported carries over; otherwise a fresh wind-up
    st.ends = math.max(st.reported or now, now + Windup())
    st.length = math.max(st.length or st.speed, st.speed)
end

local function Reset(keepRepeat)
    st.ends, st.reported, st.casting, st.castGUID = nil, nil, false, nil
    if not keepRepeat then st.shooting, st.stopped = false, false end
end

-- Moving, casting or out of range during the wind-up: the shot can't start, the wind-up waits.
local function Hold(now)
    local w = Windup()
    if st.shooting and st.ends and st.ends - now <= w then
        st.ends = now + w
        M.stats.holds = M.stats.holds + 1
        return true
    end
    return false
end

----------------------------------------------------------------------
-- Bar
----------------------------------------------------------------------
local bar, fill, bg, spark, tick, text
local edges = {}

local function TexturePath()
    local id = S().texture
    for _, t in ipairs(M.TEXTURES) do if t[1] == id then return t[3] end end
    return M.TEXTURES[1][3]
end

local function SavePosition()
    local point, _, rel, x, y = bar:GetPoint()
    if point then local p = S().point; p[1], p[2], p[3], p[4] = point, rel, x, y end
end

local function Layout()
    if not bar then return end
    local s = S()
    local p = s.point
    bar:ClearAllPoints()
    bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    bar:SetSize(s.width, s.height)
    bar:EnableMouse(not s.locked)
    pcall(fill.SetStatusBarTexture, fill, TexturePath())
    bg:SetColorTexture(0, 0, 0, s.background or 0.55)
    local b = math.max(0, math.floor(s.border or 1))
    for i, e in ipairs(edges) do
        e:SetShown(b > 0)
        if i <= 2 then e:SetHeight(math.max(1, b)) else e:SetWidth(math.max(1, b)) end
    end
    spark:SetSize(12, s.height * 2.2)
    tick:SetSize(2, s.height)
    local ok = pcall(text.SetFont, text, STANDARD_TEXT_FONT, s.fontSize or 12, "OUTLINE")
    if not ok then text:SetFontObject(GameFontHighlightSmall) end
end

local function EnsureBar()
    if bar then return bar end
    bar = CreateFrame("Frame", "AimbotUIAutoShot", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not S().locked then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)

    bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    fill = CreateFrame("StatusBar", nil, bar)
    fill:SetAllPoints()
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    local function Edge(p1, p2)
        local t = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetColorTexture(0, 0, 0, 1)
        t:SetPoint(p1, bar, p1); t:SetPoint(p2, bar, p2)
        edges[#edges + 1] = t
    end
    Edge("TOPLEFT", "TOPRIGHT"); Edge("BOTTOMLEFT", "BOTTOMRIGHT")
    Edge("TOPLEFT", "BOTTOMLEFT"); Edge("TOPRIGHT", "BOTTOMRIGHT")

    local over = CreateFrame("Frame", nil, bar)
    over:SetAllPoints()
    over:SetFrameLevel(fill:GetFrameLevel() + 2)
    spark = over:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    tick = over:CreateTexture(nil, "OVERLAY", nil, 2)
    tick:SetColorTexture(1, 1, 1, 0.9)
    text = over:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    bar:Hide()
    Layout()
    return bar
end

local function ColorFor(kind)
    local s = S()
    if s.colorMode == "custom" then return s.custom end
    if s.colorMode == "class" then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS.HUNTER
        if kind == "melee" then return s.colors.melee end
        if c then return { c.r, c.g, c.b, 1 } end
        return s.colors.ranged
    end
    return s.colors[kind] or s.colors.unknown
end

-- progress 0..1 (1 = ready), seconds left, cycle length, colour kind, show the wind-up marker
local function Draw(progress, left, length, kind, showTick, label)
    local s = S()
    progress = math.max(0, math.min(1, progress))
    fill:SetValue(progress)
    local c = ColorFor(kind)
    fill:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    local w = s.width
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", bar, "LEFT", w * progress, 0)
    spark:SetShown(s.showSpark and progress > 0 and progress < 1)
    local windup = Windup()
    if s.showTick and showTick and length and length > windup then
        tick:ClearAllPoints()
        tick:SetPoint("CENTER", bar, "LEFT", w * (1 - windup / length), 0)
        tick:Show()
    else
        tick:Hide()
    end
    text:SetShown(s.showText or label ~= nil)
    text:SetText(label or string.format("%.1f", math.max(0, left)))
    M.last = { progress = progress, left = left, kind = kind, tick = tick:IsShown() }
    bar:Show()
end

local function HideBar()
    if bar then bar:Hide() end
    M.last = nil
end

----------------------------------------------------------------------
-- Tick
----------------------------------------------------------------------
function M.Update()
    local s = S()
    if not s.enabled then HideBar(); return end
    local now = GetTime()

    if st.preview then
        if now > st.preview then st.preview = nil
        else
            EnsureBar()
            local cycle = 2.8
            local t = (now % cycle)
            local kind = (math.floor(now / (cycle * 2)) % 2 == 0) and "ranged" or "melee"
            Draw(t / cycle, cycle - t, cycle, kind, kind == "ranged")
            return
        end
    end
    if not s.locked then
        EnsureBar()
        Draw(0.6, 1.2, 3, "ranged", true, "Auto Shot (drag me)")
        return
    end
    if not st.hunter then HideBar(); return end
    if Bool(UnitIsDeadOrGhost, "player") == true then Reset(); HideBar(); return end
    local fighting = InCombat()
    if not fighting and not s.outOfCombat and not st.shooting then Reset(true); HideBar(); return end

    local enemy = HasEnemy()
    local state, rangedOK = RangeState()
    EnsureBar()

    -- hybrid: main-hand swing while the target is in melee range
    if s.hybrid and state == "melee" then
        local m = st.melee
        local length = (m and m.length) or st.meleeSpeed or 2
        local left = m and math.max(0, m.ends - now) or 0
        Draw(1 - left / length, left, length, "melee", false)
        return
    end

    if not st.shooting or not st.ends then
        -- idle: show the wind-up guide (or the rest of a reported cooldown)
        local left = st.ends and math.max(0, st.ends - now) or 0
        left = math.max(Windup(), math.min(st.speed, left))
        Draw(1 - left / st.speed, left, st.speed, enemy and state or "unknown", true)
        return
    end

    local moving = Bool(IsPlayerMoving)
    if moving ~= nil then
        if st.moving ~= moving then Hold(now) end
        st.moving = moving
    end
    local falling = Bool(IsFalling)
    if falling ~= nil then
        if st.falling ~= falling then Hold(now) end
        st.falling = falling
    end

    local blocked = st.moving or st.falling or st.casting or rangedOK == false
    if blocked then Hold(now) end
    local left = math.max(0, math.min(st.length, st.ends - now))
    local kind = state
    if blocked and left <= Windup() then kind = "blocked" end
    if kind == "melee" then kind = "blocked" end         -- can't shoot in melee range
    Draw(1 - left / st.length, left, st.length, kind, true)
end

local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.02 then return end
    acc = 0
    local ok, err = pcall(M.Update)
    if not ok then NS.ReportError("Auto Shot Timer", err) end
end)

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local function Me(unit) return not IsSecret(unit) and unit == "player" end

local H = {}
function H.PLAYER_SWING(duration, kind)
    if IsSecret(kind) then M.stats.secret = M.stats.secret + 1; return end
    local d = Num(duration)
    if not d then return end
    st.preview = nil
    if kind == RANGED then
        M.stats.shots = M.stats.shots + 1
        st.lastSwing = GetTime()
        ShotReported(d)
    elseif kind == MAIN then
        M.stats.swings = M.stats.swings + 1
        st.melee = { ends = GetTime() + d, length = d }
        st.meleeSpeed = d
    end
end
function H.PLAYER_SWING_RANGE_UPDATE(kind, inRange, checks)
    if IsSecret(kind) or (kind ~= RANGED and kind ~= MAIN) then return end
    M.stats.rangeEvents = M.stats.rangeEvents + 1
    local value = "unknown"
    if not IsSecret(checks) and checks == true and not IsSecret(inRange) and type(inRange) == "boolean" then
        value = inRange
    end
    st.range[kind] = { value = value, at = GetTime() }
end
function H.START_AUTOREPEAT_SPELL() st.preview = nil; StartShooting() end
function H.STOP_AUTOREPEAT_SPELL() st.shooting = false; st.stopped = true end
function H.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    if not Me(unit) or IsSecret(spellID) or spellID ~= AUTO_SHOT then return end
    -- backup for a shot the game didn't report with PLAYER_SWING
    if not st.lastSwing or GetTime() - st.lastSwing > 0.5 then
        M.stats.backupShots = M.stats.backupShots + 1
        ReadSpeed()
        ShotReported(st.speed)
    end
end
function H.UNIT_SPELLCAST_START(unit, guid, spellID)
    if not Me(unit) then return end
    if IsSecret(spellID) or spellID ~= AUTO_SHOT then
        local name
        if type(UnitCastingInfo) == "function" then
            local ok, n = pcall(UnitCastingInfo, "player")
            if ok then name = n end
        end
        st.casting = not KeepsWindup(spellID, name)
        st.castGUID = (not IsSecret(guid) and type(guid) == "string") and guid or nil
        if st.casting then Hold(GetTime()) end
    end
end
function H.UNIT_SPELLCAST_CHANNEL_START(unit, guid)
    if not Me(unit) then return end
    st.casting = true
    st.castGUID = (not IsSecret(guid) and type(guid) == "string") and guid or nil
    Hold(GetTime())
end
function H.UNIT_SPELLCAST_STOP(unit, guid)
    if not Me(unit) then return end
    -- a late stop from an older cast must not end the hold of the current one
    if st.castGUID and not IsSecret(guid) and type(guid) == "string" and guid ~= st.castGUID then return end
    st.casting, st.castGUID = false, nil
end
H.UNIT_SPELLCAST_FAILED = H.UNIT_SPELLCAST_STOP
H.UNIT_SPELLCAST_INTERRUPTED = H.UNIT_SPELLCAST_STOP
H.UNIT_SPELLCAST_CHANNEL_STOP = H.UNIT_SPELLCAST_STOP
function H.PLAYER_STARTED_MOVING() st.moving = true; Hold(GetTime()) end
function H.PLAYER_STOPPED_MOVING() st.moving = false; Hold(GetTime()) end
function H.PLAYER_TARGET_CHANGED()
    st.range = {}
    EnableRangeChecks()
    if not HasEnemy() then Reset(true); st.melee = nil
    elseif st.shooting then StartShooting() end
end
function H.PLAYER_ENTERING_WORLD() Reset(); st.melee = nil; st.range = {}; EnableRangeChecks(); ReadSpeed() end
H.WEAPON_SLOT_CHANGED = H.PLAYER_ENTERING_WORLD
function H.PLAYER_DEAD() Reset(); st.melee = nil end
function H.UNIT_ATTACK_SPEED(unit)
    if not Me(unit) then return end
    local old = st.speed
    ReadSpeed()
    -- haste changed mid-cycle: stretch what is left of a predicted cycle to the new speed
    if st.ends and old and old > 0 and st.speed ~= old then
        local now = GetTime()
        local left = st.ends - now
        if left > Windup() then st.ends = now + math.max(Windup(), left * st.speed / old) end
    end
end
H.UNIT_RANGEDDAMAGE = H.UNIT_ATTACK_SPEED
H.UNIT_SPELL_HASTE = H.UNIT_ATTACK_SPEED
H.UNIT_INVENTORY_CHANGED = H.UNIT_ATTACK_SPEED
function H.UNIT_AURA(unit) if Me(unit) then ReadHaste() end end
function H.SPELLS_CHANGED() LearnKeepNames() end

M._t = { H = H, st = st, Windup = Windup, RangeState = RangeState, Update = function() return M.Update() end }

function M:Init()
    local _, class = UnitClass("player")
    st.hunter = (class == "HUNTER")
    for ev, fn in pairs(H) do
        NS.On(ev, function(_, ...)
            if not st.hunter then return end
            local ok, err = pcall(fn, ...)
            if not ok then NS.ReportError("Auto Shot Timer: " .. ev, err) end
        end)
    end
    if st.hunter then
        LearnKeepNames()
        EnableRangeChecks()
        ReadSpeed()
    end
end

function M:Apply()
    if bar then Layout() end
    if not S().enabled then HideBar() end
end

function M:Diagnose()
    local s = S()
    local now = GetTime()
    NS.Print(string.format("  hunter: %s   Auto Shot on: %s   in combat: %s   preview: %s   locked: %s",
        tostring(st.hunter), tostring(st.shooting), tostring(InCombat()), tostring(st.preview ~= nil), tostring(s.locked)))
    NS.Print(string.format("  weapon speed %.2f   haste x%.2f   wind-up %.2f s (base %.2f)   cycle %.2f   left %.2f",
        st.speed or 0, st.haste or 1, Windup(), s.windup or 0.5, st.length or 0, st.ends and math.max(0, st.ends - now) or 0))
    local state, ranged = RangeState()
    NS.Print(string.format("  range: %s (can shoot: %s)   swing range API: %s   range events: %d",
        state, tostring(ranged), tostring(C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange ~= nil),
        M.stats.rangeEvents))
    NS.Print(string.format("  shots reported: %d   from the cast backup: %d   melee swings: %d   wind-up holds: %d   "
        .. "moving %s  casting %s   secret reads: %d",
        M.stats.shots, M.stats.backupShots, M.stats.swings, M.stats.holds,
        tostring(st.moving), tostring(st.casting), M.stats.secret))
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "AutoShotTimer_Forever")
        if ok and loaded == true then
            NS.Print("  |cffff8040AutoShotTimer_Forever is also loaded: you'll see two bars. Turn one of them off.|r")
        end
    end
end

function M.Build(page)
    local function Re() Layout() end
    page:Section("Auto Shot", "Countdown to your next shot")
    page:Note("For Hunters. The bar fills up to your next Auto Shot. The white marker is where the wind-up "
        .. "starts: from there, moving, jumping or casting pushes the shot back. Zero means the shot can go; "
        .. "the bar waits there until the game reports it.")
    page:Check("Show outside combat", function() return S().outOfCombat end,
        function(v) S().outOfCombat = v end)
    page:Check("Hybrid: show your melee swing while the target is in melee range",
        function() return S().hybrid end, function(v) S().hybrid = v end)
    page:Slider("Wind-up before haste (seconds)", 0.1, 1.5, 0.05,
        function() return S().windup end, function(v) S().windup = v end,
        function(v) return string.format("%.2f", v) end)
    page:Button("Test (10 seconds)", function()
        if not S().enabled then NS.Print("Auto Shot Timer is off: turn it on at the top of this tab first."); return end
        st.preview = GetTime() + 10
    end)

    page:Section("Bar", "Size, position and look")
    page:Check("Lock position", function() return S().locked end,
        function(v) S().locked = v; Re() end)
    page:Note("Unlock to show the bar and drag it anywhere, then lock it again.")
    page:Slider("Width", 80, 600, 5, function() return S().width end, function(v) S().width = v; Re() end)
    page:Slider("Height", 6, 50, 1, function() return S().height end, function(v) S().height = v; Re() end)
    local tex = {}
    for _, t in ipairs(M.TEXTURES) do tex[#tex + 1] = { t[1], t[2] } end
    page:Cycle("Texture", tex, function() return S().texture end, function(v) S().texture = v; Re() end)
    page:Slider("Background opacity", 0, 1, 0.05, function() return S().background end,
        function(v) S().background = v; Re() end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
    page:Slider("Border thickness", 0, 4, 1, function() return S().border end, function(v) S().border = v; Re() end)
    page:Slider("Text size", 8, 24, 1, function() return S().fontSize end, function(v) S().fontSize = v; Re() end)
    page:Check("Show the seconds left", function() return S().showText end, function(v) S().showText = v end)
    page:Check("Show the wind-up marker", function() return S().showTick end, function(v) S().showTick = v end)
    page:Check("Show the spark", function() return S().showSpark end, function(v) S().showSpark = v end)

    page:Section("Colors", "By range, class colour or one colour")
    page:Cycle("Bar colour", { { "range", "By range" }, { "class", "Hunter class colour" }, { "custom", "One colour" } },
        function() return S().colorMode end, function(v) S().colorMode = v end)
    local function C(label, get)
        page:Color(label, get, function(r, g, b) local c = get(); c[1], c[2], c[3] = r, g, b end)
    end
    C("In shooting range", function() return S().colors.ranged end)
    C("Melee (hybrid)", function() return S().colors.melee end)
    C("Out of range / held", function() return S().colors.blocked end)
    C("Range unknown", function() return S().colors.unknown end)
    C("One colour", function() return S().custom end)
end
