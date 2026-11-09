--[[
  Aimbot UI - Loss of Control
  When you are stunned, feared, silenced, rooted, disarmed or otherwise crowd controlled, shows
  a big icon in the middle of your screen with the effect's name and a countdown of the time
  left. Only you see it. Icon size, text sizes and position can be changed, and it can be
  dragged anywhere.

  Reads the game's own loss of control data (C_LossOfControl), the same the default alert uses.
  The times go straight to a Cooldown widget, which does the counting, so it also works when the
  client hides the real times from addons ("secret" values): they are never compared or added.
  The game's own alert can be hidden so it doesn't show twice; only our own frames are created.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Loss of Control",
    group = "Combat",
    desc = "A big icon with a countdown in the middle of your screen while you are stunned, feared, silenced...",
    defaults = {
        enabled   = true,
        showName  = true,           -- "Stunned", "Feared"...
        swipe     = true,           -- dark sweep over the icon
        hideGame  = true,           -- hide the game's own loss of control alert
        sound     = false,
        iconSize  = 64,
        numberSize = 26,
        nameSize  = 20,
        nameColor = { 1, 0.82, 0, 1 },
        locked    = true,
        point     = { "CENTER", "CENTER", 0, 60 },
    },
}
NS.RegisterModule("lossofcontrol", M)

local function S() return NS.db.mod.lossofcontrol end
local IsSecret = NS.IsSecret

M.stats = { events = 0, shown = 0, secret = 0, last = "none", api = "none", err = nil }

----------------------------------------------------------------------
-- Reading the game's loss of control data (new and old names of the API)
----------------------------------------------------------------------
local function Count()
    local L = C_LossOfControl
    if not L then return 0 end
    local fn = L.GetActiveLossOfControlDataCount or L.GetNumEvents
    if not fn then return 0 end
    local ok, n = pcall(fn)
    if not ok or IsSecret(n) or type(n) ~= "number" then
        if ok and IsSecret(n) then M.stats.secret = M.stats.secret + 1 end
        return 0
    end
    return n
end

-- Returns a table { icon, text, start, duration } for entry i, or nil.
local function Entry(i)
    local L = C_LossOfControl
    if not L then return nil end
    if L.GetActiveLossOfControlData then
        local ok, d = pcall(L.GetActiveLossOfControlData, i)
        if ok and type(d) == "table" then
            M.stats.api = "GetActiveLossOfControlData"
            return { icon = d.iconTexture, text = d.displayText, start = d.startTime, duration = d.duration,
                     displayType = d.displayType }
        end
    end
    if L.GetEventInfo then
        local ok, locType, spellID, text, icon, start, left, duration, school, prio, displayType = pcall(L.GetEventInfo, i)
        if ok and locType ~= nil then
            M.stats.api = "GetEventInfo"
            return { icon = icon, text = text, start = start, duration = duration, displayType = displayType }
        end
    end
    return nil
end

-- The entry to show: the first one the game wants displayed (display type 0 = "don't show").
local function Current()
    local n = Count()
    for i = 1, n do
        local e = Entry(i)
        if e then
            local dt = e.displayType
            if IsSecret(dt) or dt == nil or dt ~= 0 then return e end
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Our frame
----------------------------------------------------------------------
local frame, icon, cd, nameText, bg
local testUntil = 0

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "AimbotUILossOfControl", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -8, 8)
    bg:SetPoint("BOTTOMRIGHT", 8, -8)
    bg:SetColorTexture(0.2, 0.6, 1, 0.25)
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 1)
    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    pcall(cd.SetDrawEdge, cd, false)
    pcall(cd.SetDrawBling, cd, false)
    pcall(cd.SetHideCountdownNumbers, cd, false)
    nameText = frame:CreateFontString(nil, "OVERLAY")
    nameText:SetPoint("TOP", frame, "BOTTOM", 0, -6)
    nameText:SetFont(STANDARD_TEXT_FONT, 20, "THICKOUTLINE")
    frame:SetScript("OnDragStart", function(self) if not S().locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        if p then local t = S().point; t[1], t[2], t[3], t[4] = p, rp, x, y end
    end)
    frame:Hide()
end

local SAMPLE_ICON = 132298      -- a stun icon, for the sample shown while unlocked

local function Layout()
    Build()
    local s = S()
    local p = s.point
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    frame:SetSize(s.iconSize, s.iconSize)
    nameText:SetFont(STANDARD_TEXT_FONT, s.nameSize, "THICKOUTLINE")
    local c = s.nameColor
    nameText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    nameText:SetShown(s.showName)
    pcall(cd.SetDrawSwipe, cd, s.swipe)
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if fs then
        local okF, font = pcall(fs.GetFont, fs)
        pcall(fs.SetFont, fs, (okF and font) or STANDARD_TEXT_FONT, s.numberSize, "THICKOUTLINE")
    end
    frame:EnableMouse(not s.locked)
    bg:SetShown(not s.locked)
end

local function ShowEntry(e)
    Build()
    pcall(icon.SetTexture, icon, e.icon)
    pcall(nameText.SetText, nameText, e.text or "")
    local fed = false
    if e.start ~= nil and e.duration ~= nil then
        fed = pcall(cd.SetCooldown, cd, e.start, e.duration)
    end
    if not fed then pcall(cd.Clear, cd) end
    M.stats.timer = fed and "yes" or "no"
    frame:Show()
end

local wasShowing = false
local function Update()
    if not frame and not S().enabled then return end
    if GetTime() < testUntil then return end
    local s = S()
    if not s.enabled then
        if frame then frame:Hide() end
        wasShowing = false
        return
    end
    local e = Current()
    if e then
        if not wasShowing then
            M.stats.shown = M.stats.shown + 1
            if not IsSecret(e.text) and type(e.text) == "string" then M.stats.last = e.text end
            if s.sound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master") end
        end
        wasShowing = true
        Layout()
        ShowEntry(e)
    else
        wasShowing = false
        if not frame then return end
        if not s.locked then
            -- unlocked: a sample so it can be dragged
            Layout()
            pcall(icon.SetTexture, icon, SAMPLE_ICON)
            nameText:SetText("Stunned  (drag me)")
            pcall(cd.Clear, cd)
            frame:Show()
        else
            frame:Hide()
        end
    end
end
M._t = { Update = Update, Current = Current }

local function SafeUpdate()
    local ok, err = pcall(Update)
    if not ok then M.stats.err = tostring(err); NS.ReportError("Loss of Control", err) end
end

----------------------------------------------------------------------
-- The game's own alert: hidden while ours is on (method calls only)
----------------------------------------------------------------------
local hooked = false
local function GameFrame() return _G.LossOfControlFrame end
local function HideGame()
    local g = GameFrame()
    if not g then return end
    if S().enabled and S().hideGame then pcall(g.SetAlpha, g, 0) else pcall(g.SetAlpha, g, 1) end
end
local function HookGame()
    local g = GameFrame()
    if hooked or not g then return end
    hooked = true
    -- the game fades its alert in with an animation, so set the alpha again each time it shows
    pcall(hooksecurefunc, g, "Show", function() pcall(HideGame) end)
    if g.HookScript then pcall(g.HookScript, g, "OnShow", function() pcall(HideGame) end) end
end

function M:Apply()
    HookGame()
    HideGame()
    if frame or not S().locked then Layout() end
    SafeUpdate()
end

function M:Init()
    for _, ev in ipairs({ "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "PLAYER_CONTROL_LOST",
        "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD" }) do
        NS.On(ev, function()
            M.stats.events = M.stats.events + 1
            SafeUpdate()
        end)
    end
    -- a light check as a backup (also hides it as soon as the effect ends)
    local acc = 0
    local poll = CreateFrame("Frame")
    poll:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 0.1 then return end
        acc = 0
        if S().enabled and (wasShowing or Count() > 0) then SafeUpdate() end
    end)
end

function M:Diagnose()
    local L = C_LossOfControl
    local st = M.stats
    NS.Print(string.format("  API: C_LossOfControl=%s  data=%s  old=%s   active now: %d   read with: %s",
        tostring(L ~= nil), tostring(L and L.GetActiveLossOfControlData ~= nil), tostring(L and L.GetEventInfo ~= nil),
        Count(), st.api))
    NS.Print(string.format("  events seen: %d   times shown: %d   last: %s   countdown given: %s   secret reads: %d   game alert found: %s   last error: %s",
        st.events, st.shown, tostring(st.last), tostring(st.timer or "-"), st.secret, tostring(GameFrame() ~= nil), tostring(st.err or "none")))
end

function M.Build(page)
    page:Section("Show", "What the alert shows")
    page:Check("Name of the effect (Stunned, Feared...)", function() return S().showName end,
        function(v) S().showName = v; NS.ApplyModule("lossofcontrol") end)
    page:Check("Dark sweep over the icon", function() return S().swipe end,
        function(v) S().swipe = v; NS.ApplyModule("lossofcontrol") end)
    page:Check("Hide the game's own loss of control alert", function() return S().hideGame end,
        function(v) S().hideGame = v; NS.ApplyModule("lossofcontrol") end)
    page:Check("Play a sound", function() return S().sound end, function(v) S().sound = v end)
    page:Note("Shows while you are stunned, feared, silenced, rooted, disarmed or interrupted. Only you see it.")
    page:Button("Test (5 seconds)", function()
        if not S().enabled then NS.Print("Loss of Control is off: turn it on at the top of this tab first."); return end
        Layout()
        ShowEntry({ icon = SAMPLE_ICON, text = "Stunned", start = GetTime(), duration = 5 })
        testUntil = GetTime() + 5
        C_Timer.After(5.05, SafeUpdate)
    end)

    page:Section("Size and position", "How big and where")
    page:Slider("Icon size", 24, 160, 2, function() return S().iconSize end,
        function(v) S().iconSize = v; NS.ApplyModule("lossofcontrol") end)
    page:Slider("Countdown number size", 10, 64, 1, function() return S().numberSize end,
        function(v) S().numberSize = v; NS.ApplyModule("lossofcontrol") end)
    page:Slider("Name text size", 10, 48, 1, function() return S().nameSize end,
        function(v) S().nameSize = v; NS.ApplyModule("lossofcontrol") end)
    page:Color("Name text color", function() return S().nameColor end,
        function(r, g, b, a) local c = S().nameColor; c[1], c[2], c[3], c[4] = r, g, b, a or 1; NS.ApplyModule("lossofcontrol") end)
    page:Check("Lock position", function() return S().locked end,
        function(v) S().locked = v; NS.ApplyModule("lossofcontrol") end)
    page:Note("Untick \"Lock position\" to show a sample and drag it anywhere, then lock it again.")
    page:Button("Reset position", function()
        local p = S().point; p[1], p[2], p[3], p[4] = "CENTER", "CENTER", 0, 60
        NS.ApplyModule("lossofcontrol")
    end)
end
