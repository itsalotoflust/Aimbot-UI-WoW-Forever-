--[[
  Aimbot UI - Core
  Shared namespace, saved variables, module registry, event hub and helpers.
  Every module runs inside pcall so one failing module can never break the rest.
]]

local ADDON_NAME, NS = ...
_G.AimbotUI = NS

NS.version = "2.18.2"
NS.modules = {}
NS.moduleOrder = {}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
-- While NS.capture is a table, every printed line is also stored there (used by /aimbot diag).
function NS.Print(msg)
    print("|cff4db8ffAimbot UI|r: " .. tostring(msg))
    local cap = NS.capture
    if cap then
        local plain = tostring(msg):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        cap[#cap + 1] = plain
    end
end

-- True if a value is a Midnight-style "secret value" (can't be compared/branched on).
local issecret = _G.issecretvalue or function() return false end
NS.IsSecret = issecret

-- Walk a "A.B.C" path from _G; returns nil if any step is missing.
function NS.Resolve(path)
    local obj = _G
    for key in path:gmatch("[^%.]+") do
        if type(obj) ~= "table" then return nil end
        obj = obj[key]
        if obj == nil then return nil end
    end
    return obj
end

function NS.ResolveFirst(paths)
    for _, p in ipairs(paths) do
        local o = NS.Resolve(p)
        if o then return o, p end
    end
end

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = DeepCopy(v) end
    return out
end
NS.DeepCopy = DeepCopy

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

----------------------------------------------------------------------
-- Movable on-screen alert text (Party Death Alert, Durability Alert, Talent Point Alert)
-- S() returns the module's settings: size, color, duration, locked, point.
-- A:Show(msg, hold, pulse) shows the text; it fades out after s.duration seconds unless hold
-- is true (then it stays until A:Hide()). pulse makes it fade in and out while it is up.
----------------------------------------------------------------------
function NS.CreateAlertText(globalName, S, sample)
    local A = {}
    local f = CreateFrame("Frame", globalName, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.6, 1, 0.25)
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    fs:SetFont(STANDARD_TEXT_FONT, 24, "THICKOUTLINE")
    A.frame, A.text = f, fs
    local hideAt, current, pulsing = nil, nil, false

    local function Fit()
        local s = S()
        local w = fs:GetStringWidth() or 0
        f:SetSize(math.max(200, w + 24), s.size + 16)
    end
    local function Paint()
        local c = S().color
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end

    f:SetScript("OnDragStart", function(self) if not S().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if point then local p = S().point; p[1], p[2], p[3], p[4] = point, relPoint, x, y end
    end)
    f:SetScript("OnUpdate", function(self)
        if not current then return end
        if not S().locked then self:SetAlpha(1); return end
        local now = GetTime()
        if hideAt then
            local left = hideAt - now
            if left <= 0 then
                hideAt, current, pulsing = nil, nil, false
                self:Hide()
                return
            elseif left < 1 then
                self:SetAlpha(left)
                return
            end
        end
        if pulsing then
            -- smooth fade between 35% and 100% once every ~1.2 seconds
            self:SetAlpha(0.35 + 0.65 * (0.5 + 0.5 * math.cos(now * 5.2)))
        else
            self:SetAlpha(1)
        end
    end)
    f:Hide()

    function A:Layout()
        local s = S()
        local p = s.point
        f:ClearAllPoints()
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        fs:SetFont(STANDARD_TEXT_FONT, s.size, "THICKOUTLINE")
        Paint()
        f:EnableMouse(not s.locked)
        bg:SetShown(not s.locked)
        if not s.locked then
            -- unlocked: always show (a sample if nothing is up) so it can be dragged
            fs:SetText(current or (sample .. "  (drag me)"))
            f:SetAlpha(1)
            f:Show()
        elseif not current then
            f:Hide()
        end
        Fit()
    end

    function A:Show(msg, hold, pulse)
        -- the same held message again (modules re-check often): leave it running smoothly
        if hold and msg == current and not hideAt and f:IsShown() and pulsing == (pulse and true or false) then
            return
        end
        current = msg
        pulsing = pulse and true or false
        fs:SetText(msg)
        Paint()
        Fit()
        f:SetAlpha(1)
        f:Show()
        hideAt = (not hold) and (GetTime() + math.max(0.5, S().duration or 4)) or nil
    end

    function A:Hide()
        current, hideAt, pulsing = nil, nil, false
        if S().locked then f:Hide() else A:Layout() end
    end

    function A:IsShowing() return current ~= nil end
    -- give the frame its position and font now: a frame with no position is never drawn, so
    -- without this the first alert stayed invisible until a setting was changed
    A:Layout()
    return A
end

----------------------------------------------------------------------
-- Action bar helpers (shared by several modules)
----------------------------------------------------------------------
NS.BAR_PREFIXES = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton",
    "MultiBar5Button",
    "MultiBar6Button",
    "MultiBar7Button",
}
NS.BUTTONS_PER_BAR = 12

function NS.ForEachButton(fn)
    for _, prefix in ipairs(NS.BAR_PREFIXES) do
        for i = 1, NS.BUTTONS_PER_BAR do
            local btn = _G[prefix .. i]
            if btn then fn(btn, prefix, i) end
        end
    end
end

function NS.GetAction(btn)
    local action = btn.action
    if type(action) ~= "number" and btn.GetAttribute then
        local ok, a = pcall(btn.GetAttribute, btn, "action")
        if ok then action = a end
    end
    if type(action) == "number" and action > 0 then return action end
end

-- Returns spellID for an action slot (spell or macro-with-spell), else nil.
function NS.SpellForAction(action)
    if not action or not GetActionInfo then return nil end
    local ok, kind, id = pcall(GetActionInfo, action)
    if not ok or issecret(kind) or issecret(id) then return nil end
    if kind == "spell" then
        return id
    elseif kind == "macro" and id then
        local fn = GetMacroSpell or (C_Macro and C_Macro.GetMacroSpell)
        if fn then
            local ok2, sid = pcall(fn, id)
            if ok2 and not issecret(sid) then return sid end
        end
    end
end

----------------------------------------------------------------------
-- Event hub:  NS.On("EVENT", function(event, ...) end)
----------------------------------------------------------------------
local handlers = {}
local hub = CreateFrame("Frame")
hub:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then NS.ReportError("event " .. event, err) end
    end
end)

function NS.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        local ok = pcall(hub.RegisterEvent, hub, event)
        if not ok then handlers[event] = nil; return false end
    end
    table.insert(handlers[event], fn)
    return true
end

local reported = {}
function NS.ReportError(where, err)
    local key = where .. tostring(err)
    if reported[key] then return end
    reported[key] = true
    NS.Print("|cffff5555error in " .. where .. "|r: " .. tostring(err))
end

----------------------------------------------------------------------
-- Modules
--   NS.RegisterModule("key", {
--     name, desc, defaults = {enabled=true, ...},
--     Init(self)   -- once, after saved variables load
--     Apply(self)  -- (re)apply settings; must honor settings.enabled
--     Build(page)  -- build the options page
--   })
----------------------------------------------------------------------
function NS.RegisterModule(key, mod)
    mod.key = key
    NS.modules[key] = mod
    table.insert(NS.moduleOrder, key)
end

function NS.Mod(key)
    return NS.db and NS.db.mod and NS.db.mod[key]
end

function NS.ApplyModule(key)
    local m = NS.modules[key]
    if m and m.Apply and NS.db then
        local ok, err = pcall(m.Apply, m)
        if not ok then NS.ReportError(m.name or key, err) end
    end
end

function NS.ApplyAll()
    for _, key in ipairs(NS.moduleOrder) do NS.ApplyModule(key) end
end

----------------------------------------------------------------------
-- Saved variables
----------------------------------------------------------------------
NS.WINDOW_DEFAULTS = {
    scale    = 1.0,
    fontSize = 12,
    locked   = false,
    w        = 780,
    h        = 560,
    bg       = { 0.07, 0.07, 0.08, 0.96 },
    border   = { 0.00, 0.00, 0.00, 1.00 },
    accent   = { 0.30, 0.70, 1.00, 1.00 },
    theme    = "blue",
    sidebar  = { 0.00, 0.00, 0.00, 0.28 },
    titleBar = { 0.12, 0.12, 0.13, 1.00 },
    text     = { 0.90, 0.90, 0.92, 1.00 },
    muted    = { 0.62, 0.62, 0.67, 1.00 },
    skin     = "modern",          -- "classic" (game style) or "modern" (flat); set by the theme
    classicBorder = "stone",
    classicBack   = "dark",
    font        = "default",      -- see UI.FONTS
    fontOutline = "none",         -- "none", "OUTLINE" or "THICKOUTLINE"
    textShadow  = false,
    borderSize  = 1,
    showVersion = true,
    menuButton  = true,           -- "Aimbot UI" button under the Escape menu
    titleMark   = true,
    titleLine   = true,
    underlines  = true,
    titleColorOn = false,
    titleColor  = { 1.00, 1.00, 1.00, 1.00 },
}

function NS.InitDB()
    AimbotUIDB = AimbotUIDB or {}
    local db = AimbotUIDB
    NS.db = db

    db.window = db.window or {}
    Merge(db.window, NS.WINDOW_DEFAULTS)

    db.mod = db.mod or {}
    db.trainerCache = db.trainerCache or {}

    for _, key in ipairs(NS.moduleOrder) do
        local m = NS.modules[key]
        db.mod[key] = db.mod[key] or {}
        Merge(db.mod[key], m.defaults or {})
    end
end

function NS.ResetAll()
    local db = NS.db
    local point = db.window.point
    db.window = DeepCopy(NS.WINDOW_DEFAULTS)
    db.window.point = point
    for _, key in ipairs(NS.moduleOrder) do
        db.mod[key] = DeepCopy(NS.modules[key].defaults or {})
    end
    NS.ApplyAll()
    if NS.UI and NS.UI.ApplyStyle then NS.UI.ApplyStyle(); NS.UI.RefreshAll() end
end

-- Reset a single module (and its tab) back to its defaults.
function NS.ResetModule(key)
    local m = NS.modules[key]
    if not (m and NS.db) then return end
    NS.db.mod[key] = DeepCopy(m.defaults or {})
    NS.ApplyModule(key)
    if NS.UI and NS.UI.RefreshAll then NS.UI.RefreshAll() end
end

function NS.InitModules()
    for _, key in ipairs(NS.moduleOrder) do
        local m = NS.modules[key]
        if m.Init then
            local ok, err = pcall(m.Init, m)
            if not ok then NS.ReportError((m.name or key) .. " init", err) end
        end
    end
end
