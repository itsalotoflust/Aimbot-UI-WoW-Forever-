--[[
  Aimbot UI - Double Press   (the "Wannabe AutoHotKey" feature from RougeUI, ported)

  Every keybind that is bound to an action button presses TWICE: once when you push
  the key down and once when you let go. It works by putting an invisible secure
  click-button in front of each action button and moving the key binding onto it
  (override bindings), exactly like RougeUI does.

  Things you don't want doubled - toggles, /cancelaura macros, mounts - can be left
  alone in two ways:
    * add the key to the "never double" list (type it in with "Add a key")
    * macros that contain a /cancel... command are skipped automatically

  Safety: all binding changes happen out of combat only. If you change something
  while in combat it is applied the moment combat ends.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Double Press",
    group = "QoL",
    desc = "Every action bar keybind presses twice (on key down and key up), like AutoHotKey. "
        .. "Pick keys or macros that should stay single, such as a /cancelaura macro.",
    defaults = {
        enabled    = false,     -- changes how every key behaves, so it starts off
        skipCancel = true,      -- leave macros that use /cancelaura, /cancelform... alone
        matchMods  = false,     -- excluding "F" also excludes SHIFT-F, CTRL-F...
        excluded   = {},        -- list of key strings, e.g. "SHIFT-F", "BUTTON4"
    },
}
NS.RegisterModule("doublepress", M)

local function S() return NS.db.mod.doublepress end
local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

----------------------------------------------------------------------
-- Which keys to double
----------------------------------------------------------------------
local MODS = { "META-", "ALT-", "CTRL-", "SHIFT-" }

local function BaseKey(key)
    local changed = true
    while changed do
        changed = false
        for _, m in ipairs(MODS) do
            if #key > #m and key:sub(1, #m) == m then key = key:sub(#m + 1); changed = true end
        end
    end
    return key
end

local function KeyExcluded(key)
    local cfg = S()
    for _, k in ipairs(cfg.excluded) do
        if k == key then return true end
        if cfg.matchMods and BaseKey(key) == BaseKey(k) then return true end
    end
    return false
end

-- Returns the macro's name when the button holds a macro that uses /cancel...
local function CancelMacro(btn)
    local action = NS.GetAction(btn)
    if not action or not GetActionInfo then return nil end
    local ok, kind, id = pcall(GetActionInfo, action)
    if not ok or kind ~= "macro" or NS.IsSecret(kind) or NS.IsSecret(id) or not id then return nil end
    local ok2, name, _, body = pcall(GetMacroInfo, id)
    if not ok2 then return nil end
    if (type(body) ~= "string" or NS.IsSecret(body)) and GetMacroBody then
        local ok3, b = pcall(GetMacroBody, id)
        if ok3 then body = b end
    end
    if type(body) ~= "string" or NS.IsSecret(body) then return nil end
    if body:lower():find("/cancel%a*") then
        return (type(name) == "string" and not NS.IsSecret(name) and name ~= "") and name or "macro"
    end
    return nil
end

local defaultButtons = {
    ACTIONBUTTON = "ActionButton",
    MULTIACTIONBAR1BUTTON = "MultiBarBottomLeftButton",
    MULTIACTIONBAR2BUTTON = "MultiBarBottomRightButton",
    MULTIACTIONBAR3BUTTON = "MultiBarRightButton",
    MULTIACTIONBAR4BUTTON = "MultiBarLeftButton",
    MULTIACTIONBAR5BUTTON = "MultiBar5Button",
    MULTIACTIONBAR6BUTTON = "MultiBar6Button",
    MULTIACTIONBAR7BUTTON = "MultiBar7Button",
}

local function BindingByKey(key)
    local fn = (C_KeyBindings and C_KeyBindings.GetBindingByKey) or GetBindingByKey
    if fn then
        local ok, cmd = pcall(fn, key)
        if ok then return cmd end
    end
end

local OWN_PREFIX = "AimbotUIDP_"

-- button name -> { keys }
local function GetAllBindings()
    local realBtn, seen = {}, {}

    local function Handle(key, fallback)
        if not key or seen[key] then return end
        seen[key] = true
        local command = BindingByKey(key) or fallback
        if type(command) ~= "string" then return end

        local btnName = command
        if command:match("^CLICK") then
            btnName = command:match("CLICK (.-):") or command:match("CLICK (.-)$")
        end
        if not btnName then return end

        -- Our own bindings point at our proxy buttons ("AimbotUIDP_ActionButton1"). Read through
        -- them to the real button, otherwise every rescan wraps the proxy in another proxy and the
        -- sparkle ends up on a button nobody can see.
        while btnName:sub(1, #OWN_PREFIX) == OWN_PREFIX do btnName = btnName:sub(#OWN_PREFIX + 1) end
        if btnName == "" then return end

        local cleanBtn = btnName:match("^(.*%d)")
        if not cleanBtn then return end
        local base, id = cleanBtn:match("^(.-)(%d+)$")
        if base and id then
            local blizzBtn = defaultButtons[base:upper()]
            if blizzBtn then cleanBtn = blizzBtn .. id end
        end
        realBtn[cleanBtn] = realBtn[cleanBtn] or {}
        table.insert(realBtn[cleanBtn], key)
    end

    for i = 1, (GetNumBindings and GetNumBindings() or 0) do
        local command, _, key1, key2 = GetBinding(i)
        Handle(key1, command)
        Handle(key2, command)
    end
    return realBtn
end

-- The full picture: every key on an action button and what will happen to it.
-- entry = { key, button, macro, reason = nil | "excluded" | "macro" }
local function ComputePlan()
    local plan = {}
    for btnName, keys in pairs(GetAllBindings()) do
        local btn = _G[btnName]
        if btn then
            local macro = S().skipCancel and CancelMacro(btn) or nil
            for _, key in ipairs(keys) do
                local e = { key = key, button = btnName, macro = macro }
                if KeyExcluded(key) then e.reason = "excluded"
                elseif macro then e.reason = "macro" end
                plan[#plan + 1] = e
            end
        end
    end
    table.sort(plan, function(a, b)
        if a.button ~= b.button then return a.button < b.button end
        return a.key < b.key
    end)
    return plan
end

----------------------------------------------------------------------
-- Secure machinery (same design as RougeUI's XYZ.lua)
----------------------------------------------------------------------
local PREFIX = "AimbotUIDP_"

local SECURE_APPLY_BINDINGS = [[
	local state = self:GetAttribute("dp_override_state") or "normal"
	local useOverride = state == "override"
	local count = self:GetAttribute("dp_count") or 0

	self:ClearBindings()

	for i = 1, count do
		local key = self:GetAttribute("dp_key" .. i)
		local normal = self:GetAttribute("dp_normal" .. i)
		local override = self:GetAttribute("dp_override" .. i)

		if override == "" then
			override = nil
		end

		local btn = normal

		if useOverride and override then
			btn = override
		end

		if key and btn then
			self:SetBindingClick(true, key, btn, "LeftButton")
		end
	end
]]

local SECURE_ONSTATE = [[
	self:SetAttribute("dp_override_state", newstate)
]] .. SECURE_APPLY_BINDINGS

local header, binder
local proxies = {}
local wrapped = {}
local applied = false
local lastSig
local pendingUpdate, needsUpdate, forceNext = false, false, false

M.active, M.skipped = {}, {}

local function EnsureSecure()
    if header then return true end
    if InCombatLockdown() then return false end
    header = CreateFrame("Frame", nil, nil, "SecureHandlerBaseTemplate")
    binder = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
    return true
end

local function GetProxy(buttonName, btn, isOverride)
    local p = proxies[buttonName]
    if p then return p end

    p = CreateFrame("Button", PREFIX .. buttonName, nil, "SecureActionButtonTemplate")

    if IsLoaded("Bartender4") then
        btn:SetAttribute("pressAndHoldAction", true)
        btn:SetAttribute("typerelease", btn._state_type)
        if not wrapped[btn] then
            wrapped[btn] = true
            SecureHandlerWrapScript(btn, "OnAttributeChanged", header, [[
                if name == "pressandholdaction" then
                    if self:GetAttribute("pressAndHoldAction") ~= true then
                        self:SetAttribute("pressAndHoldAction", true)
                        local type = self:GetAttribute("type") or "action"
                        self:SetAttribute("typerelease", type)
                    end
                end
            ]])
        end
    end

    p:RegisterForClicks("AnyDown", "AnyUp")
    p:SetAttribute("type", "click")
    if not isOverride then
        p:SetAttribute("typerelease", "click")
        p:SetAttribute("pressAndHoldAction", true)
    end
    p:SetAttribute("clickbutton", btn)

    -- A key bound to this proxy never goes through Blizzard's ActionButtonDown/Up, so
    -- tell the sparkle module directly. PreClick runs for every key press and release.
    p:SetScript("PreClick", function(_, _, down)
        local fire = NS.SparkleKey
        if fire and btn:IsVisible() then pcall(fire, btn, down and true or false) end
    end)

    -- keep the real button looking pressed (other modules hook this)
    p:SetScript("OnMouseDown", function()
        if btn:IsVisible() then btn:SetButtonState("PUSHED") end
    end)
    p:SetScript("OnMouseUp", function()
        if btn:IsVisible() then btn:SetButtonState("NORMAL") end
    end)
    p:SetScript("PostClick", function(_, _, down)
        if btn:IsVisible() and not down then btn:SetButtonState("NORMAL") end
        local fire = NS.SparkleKey      -- backup path; the sparkle's debounce drops the duplicate
        if fire and btn:IsVisible() then pcall(fire, btn, down and true or false) end
    end)

    proxies[buttonName] = p
    return p
end

local function ClearBindings()
    if not binder then return end
    ClearOverrideBindings(binder)
    UnregisterStateDriver(binder, "overridebutton")
    binder:SetAttribute("_onstate-overridebutton", nil)
    binder:SetAttribute("dp_override_state", "normal")
    binder:SetAttribute("dp_count", 0)
    applied = false
    lastSig = nil
end

----------------------------------------------------------------------
-- Sparkle hand-off, second path: watch the keys themselves
--
-- The proxy buttons tell Button Sparkle about every press (PreClick/PostClick above),
-- but that relies on the client calling those scripts for a key bound to a hidden
-- secure button. To make the flash dependable this invisible frame also listens to the
-- raw key down / key up of every doubled key and hands the real button to the sparkle.
-- It lets every key carry on to the game (propagate), so bindings are never blocked,
-- and the sparkle's own debounce drops the duplicate when both paths fire.
----------------------------------------------------------------------
M.keyStats = { down = 0, up = 0, sparkled = 0 }
local keyWatch
local keyMap = {}       -- "SHIFT-F" -> "ActionButton3"
local keyHeld = {}      -- raw key -> button name, so the release goes to the same button

local WATCH_IGNORE = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true,
}

local function RebuildKeyMap()
    keyMap = {}
    for _, e in ipairs(M.active or {}) do keyMap[e.key:upper()] = e.button end
end

local function WatchModPrefix()
    local p = ""
    if IsMetaKeyDown and IsMetaKeyDown() then p = p .. "META-" end
    if IsAltKeyDown() then p = p .. "ALT-" end
    if IsControlKeyDown() then p = p .. "CTRL-" end
    if IsShiftKeyDown() then p = p .. "SHIFT-" end
    return p
end

local function Hand(name, down)
    local btn = _G[name]
    local fire = NS.SparkleKey
    if btn and fire and btn:IsVisible() then
        M.keyStats.sparkled = M.keyStats.sparkled + 1
        pcall(fire, btn, down)
    end
end

local function EnsureKeyWatch()
    if keyWatch then return keyWatch end
    local f = CreateFrame("Frame", "AimbotUIDoublePressKeys", UIParent)
    f:SetSize(1, 1)
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    f:EnableKeyboard(true)
    pcall(f.SetPropagateKeyboardInput, f, true)
    -- Propagation is set once here (out of combat) and sticks. It must NOT be set
    -- again inside the key handlers: the game blocks that call during combat.
    f:SetScript("OnKeyDown", function(self, key)
        if WATCH_IGNORE[key] then return end                      -- ignore modifiers
        local now = GetTime()
        local held = keyHeld[key]
        if held and (now - held.t) < 0.6 then held.t = now; return end   -- key auto-repeat
        local name = keyMap[WatchModPrefix() .. key]
        if not name then return end
        keyHeld[key] = { name = name, t = now }
        M.keyStats.down = M.keyStats.down + 1
        Hand(name, true)
    end)
    f:SetScript("OnKeyUp", function(self, key)
        local held = keyHeld[key]
        if not held then return end
        local name = held.name
        keyHeld[key] = nil
        M.keyStats.up = M.keyStats.up + 1
        Hand(name, false)
    end)
    keyWatch = f
    return f
end

local function UpdateBindings(force)
    local cfg = S()

    if InCombatLockdown() then
        needsUpdate = true
        return
    end
    needsUpdate = false

    if not cfg.enabled and not M.page then
        if applied then ClearBindings() end
        if keyWatch then keyWatch:Hide(); keyHeld = {} end
        return
    end

    local plan = ComputePlan()
    M.active, M.skipped = {}, {}
    local byButton, order = {}, {}
    local sigParts = {}

    if cfg.enabled then
        for _, e in ipairs(plan) do
            if e.reason then
                M.skipped[#M.skipped + 1] = e
            else
                M.active[#M.active + 1] = e
                if not byButton[e.button] then byButton[e.button] = {}; order[#order + 1] = e.button end
                table.insert(byButton[e.button], e.key)
                sigParts[#sigParts + 1] = e.key .. ">" .. e.button
            end
        end
    else
        for _, e in ipairs(plan) do M.skipped[#M.skipped + 1] = e end
    end
    M.plan = plan
    RebuildKeyMap()
    if cfg.enabled then
        local kw = EnsureKeyWatch()
        pcall(kw.SetPropagateKeyboardInput, kw, true)     -- out of combat only (checked above)
        kw:Show()
    elseif keyWatch then keyWatch:Hide(); keyHeld = {} end

    if not cfg.enabled then
        if applied then ClearBindings() end
        if M.Refresh then M:Refresh() end
        return
    end

    local sig = table.concat(sigParts, ";")
    if not force and applied and sig == lastSig then
        if M.Refresh then M:Refresh() end
        return
    end
    if not EnsureSecure() then needsUpdate = true; return end

    ClearBindings()
    local index = 0
    for _, btnName in ipairs(order) do
        local btn = _G[btnName]
        if btn then
            local normal = GetProxy(btnName, btn)
            local overrideName = ""
            local num = tonumber(btnName:match("^ActionButton(%d+)$"))
            local overrideBtn = num and _G["OverrideActionBarButton" .. num]
            if num and num <= 6 and overrideBtn then
                overrideName = GetProxy(btnName .. "_override", overrideBtn, true):GetName()
            end
            for _, key in ipairs(byButton[btnName]) do
                index = index + 1
                binder:SetAttribute("dp_key" .. index, key)
                binder:SetAttribute("dp_normal" .. index, normal:GetName())
                binder:SetAttribute("dp_override" .. index, overrideName)
            end
        end
    end
    binder:SetAttribute("dp_count", index)

    if index > 0 then
        binder:SetAttribute("_onstate-overridebutton", SECURE_ONSTATE)
        RegisterStateDriver(binder, "overridebutton", "[overridebar] override; [vehicleui] override; normal")
        binder:Execute(SECURE_APPLY_BINDINGS)
        applied = true
        lastSig = sig
    end
    if M.Refresh then M:Refresh() end
end

local function UpdateSoon(force)
    if force then forceNext = true end
    if pendingUpdate then return end
    pendingUpdate = true
    C_Timer.After(0.5, function()
        pendingUpdate = false
        local f = forceNext
        forceNext = false
        local ok, err = pcall(UpdateBindings, f)
        if not ok then NS.ReportError("Double Press", err) end
    end)
end

----------------------------------------------------------------------
-- Exclude list helpers
----------------------------------------------------------------------
function M.AddExcluded(key)
    key = key:upper()
    local list = S().excluded
    for _, k in ipairs(list) do if k == key then return false end end
    table.insert(list, key)
    UpdateSoon()
    return true
end

function M.RemoveExcluded(key)
    local list = S().excluded
    for i = #list, 1, -1 do
        if list[i] == key then table.remove(list, i) end
    end
    UpdateSoon()
end

----------------------------------------------------------------------
-- "Press the key" capture
----------------------------------------------------------------------
local capture
local IGNORE = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true,
}

local function ModPrefix()
    local p = ""
    if IsMetaKeyDown and IsMetaKeyDown() then p = p .. "META-" end
    if IsAltKeyDown() then p = p .. "ALT-" end
    if IsControlKeyDown() then p = p .. "CTRL-" end
    if IsShiftKeyDown() then p = p .. "SHIFT-" end
    return p
end

local MOUSE_NAMES = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function Captured(key)
    if capture then capture:Hide() end
    if M.AddExcluded(key) then
        NS.Print("Double Press: |cff4db8ff" .. key .. "|r will stay a single press.")
    else
        NS.Print("Double Press: " .. key .. " is already on the list.")
    end
    if M.Refresh then M:Refresh() end
end

local function EnsureCapture()
    if capture then return capture end
    local f = CreateFrame("Frame", "AimbotUIDoublePressCapture", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetAllPoints(UIParent)
    f:EnableKeyboard(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.65)

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE")
    text:SetPoint("CENTER", f, "CENTER", 0, 30)
    text:SetText("Press the key or mouse button that should NOT double press")
    local sub = f:CreateFontString(nil, "OVERLAY")
    sub:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    sub:SetPoint("TOP", text, "BOTTOM", 0, -8)
    sub:SetTextColor(0.7, 0.7, 0.75)
    sub:SetText("Hold Shift, Ctrl or Alt first if the binding uses them.   Esc cancels.")

    local cancel = NS.UI.MakeButton(f, "Cancel", 110, 26)
    cancel:SetPoint("TOP", sub, "BOTTOM", 0, -18)
    cancel:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnShow", function(self)
        if not InCombatLockdown() then pcall(self.SetPropagateKeyboardInput, self, false) end
    end)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then self:Hide(); return end
        if IGNORE[key] then return end
        Captured(ModPrefix() .. key)
    end)
    f:SetScript("OnMouseDown", function(self, button)
        local name = MOUSE_NAMES[button]
        if name then Captured(ModPrefix() .. name) end
    end)
    f:SetScript("OnMouseWheel", function(self, delta)
        Captured(ModPrefix() .. (delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
    end)
    capture = f
    return f
end

function M:StartCapture()
    if InCombatLockdown() then NS.Print("Double Press: finish combat first."); return end
    EnsureCapture():Show()
end

----------------------------------------------------------------------
-- Settings page
----------------------------------------------------------------------
local rows = {}
local function GetRow(i, parent)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, parent)
    r:SetHeight(24)
    r.key = NS.UI.Text(r, "", 0, 1, 1, 1)
    r.key:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.key:SetWidth(130)
    r.key:SetJustifyH("LEFT")
    r.btn = NS.UI.MakeButton(r, "", 110, 20)
    r.btn:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.info = NS.UI.Text(r, "", -1, 0.62, 0.62, 0.67)
    r.info:SetPoint("LEFT", r.key, "RIGHT", 6, 0)
    r.info:SetPoint("RIGHT", r.btn, "LEFT", -8, 0)
    r.info:SetJustifyH("LEFT")
    r.info:SetWordWrap(false)
    rows[i] = r
    return r
end

local function RowLabel(r, key, info, btnText, onClick, r1, g1, b1)
    r.key:SetText(key)
    r.key:SetTextColor(r1 or 1, g1 or 1, b1 or 1)
    r.info:SetText(info or "")
    r.btn.label:SetText(btnText)
    r.btn:SetScript("OnClick", onClick)
    r.btn:Show()
end

function M:Refresh()
    if not self.list or not self.page then return end
    local cfg = S()
    local y, idx = 0, 0
    for _, r in ipairs(rows) do r:Hide() end

    local function Place(r)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", 0, -y)
        r:Show()
        y = y + 26
    end

    local plan = M.plan or {}
    local shown = {}
    for _, e in ipairs(plan) do
        shown[e.key] = true
        idx = idx + 1
        local r = GetRow(idx, self.list)
        local what = e.button:gsub("Button", " ")
        if e.reason == "macro" then
            RowLabel(r, e.key, (e.macro or "macro") .. "  (cancel macro, skipped)", "Skipped",
                function() NS.Print("Turn off \"Skip macros that use /cancel...\" above to double this macro.") end,
                0.6, 0.6, 0.65)
        elseif e.reason == "excluded" then
            RowLabel(r, e.key, what, "Single press", function() M.RemoveExcluded(e.key); M:Refresh() end,
                1, 0.82, 0.3)
        else
            RowLabel(r, e.key, what .. (cfg.enabled and "" or "  (module off)"), cfg.enabled and "Double press" or "Would double",
                function() M.AddExcluded(e.key); M:Refresh() end, 0.4, 1, 0.5)
        end
        Place(r)
    end
    -- excluded keys that aren't currently bound to an action button
    for _, key in ipairs(cfg.excluded) do
        if not shown[key] then
            idx = idx + 1
            local r = GetRow(idx, self.list)
            RowLabel(r, key, "not on an action button right now", "Remove",
                function() M.RemoveExcluded(key); M:Refresh() end, 1, 0.82, 0.3)
            Place(r)
        end
    end
    if idx == 0 then
        idx = 1
        local r = GetRow(1, self.list)
        RowLabel(r, "No keybinds found", "", "", function() end, 0.7, 0.7, 0.75)
        r.btn:Hide()
        Place(r)
    end
    if self.status then
        local n, s = #M.active, #M.skipped
        if cfg.enabled then
            self.status:SetText(string.format("Doubling %d key(s).  Left as single press: %d.%s",
                n, s, needsUpdate and "  A change is waiting for combat to end." or ""))
        else
            self.status:SetText("Off. Turn on the Enabled switch at the top of this tab to start doubling.")
        end
    end
    self.list:SetContentHeight(y + 4)
end

function M.Build(page)
    M.page = page

    page:Section("How it works", "What Double Press does and its limits")
    page:Note("When on, each key bound to an action button presses twice: once when you press it down "
        .. "and once when you release it (RougeUI's \"Wannabe AutoHotKey\"). Works with the default bars, "
        .. "Dominos and Bartender4. Changes are made out of combat only.")
    M.warn = page:Note("")
    if IsLoaded("RougeUI") then
        M.warn:SetText("RougeUI is loaded. If its \"Wannabe AutoHotKey\" option is also on, the two will fight "
            .. "over your keys. Turn that option off in RougeUI.")
        M.warn:SetTextColor(1, 0.6, 0.3)
        page:Reflow()
    end

    page:Section("Options", "Which bars it covers and how it behaves")
    page:Check("Skip macros that use /cancelaura, /cancelform or any /cancel... command",
        function() return S().skipCancel end,
        function(v) S().skipCancel = v; UpdateSoon(true) end,
        "Those macros stay a single press so they can't toggle themselves off again.")
    page:Check("Excluding a key also excludes it with Shift / Ctrl / Alt",
        function() return S().matchMods end,
        function(v) S().matchMods = v; UpdateSoon(true) end,
        "On: excluding F also leaves SHIFT-F and CTRL-F alone. Off: only the exact key.")

    page:Section("Your keys", "Leave single keys (for example a cancelaura macro) un-doubled")
    page:Note("Click a green key to make it a single press, or click a yellow one to double it again. "
        .. "Use the button below to add a key by pressing it.")
    page:Button("Add a key to leave single (then press it)", function() M:StartCapture() end, 300)
    M.list = page:Container()
    M.status = page:Note("")
    page:Button("Rescan keybinds now", function() UpdateSoon(true) end, 220)
    M:Refresh()
    UpdateSoon()
end

----------------------------------------------------------------------
function M:Diagnose()
    local cfg = S()
    NS.Print(string.format("  secure frames created: %s   bindings applied: %s   proxies: %d",
        tostring(header ~= nil), tostring(applied), (function() local n = 0 for _ in pairs(proxies) do n = n + 1 end return n end)()))
    NS.Print(string.format("  API: GetBinding=%s GetNumBindings=%s GetBindingByKey=%s",
        tostring(type(GetBinding) == "function"), tostring(type(GetNumBindings) == "function"),
        tostring((C_KeyBindings and C_KeyBindings.GetBindingByKey ~= nil) or type(GetBindingByKey) == "function")))
    local a, s = {}, {}
    for _, e in ipairs(M.active or {}) do a[#a + 1] = e.key end
    for _, e in ipairs(M.skipped or {}) do s[#s + 1] = e.key .. "(" .. (e.reason or "off") .. ")" end
    NS.Print(string.format("  key watcher (sparkle hand-off): %s   key downs seen: %d   key ups seen: %d   handed to sparkle: %d",
        keyWatch and (keyWatch:IsShown() and "on" or "off") or "not created",
        M.keyStats.down, M.keyStats.up, M.keyStats.sparkled))
    NS.Print("  doubled: " .. (#a > 0 and table.concat(a, " ") or "none"))
    NS.Print("  single: " .. (#s > 0 and table.concat(s, " ") or "none"))
    NS.Print("  excluded list: " .. (#cfg.excluded > 0 and table.concat(cfg.excluded, " ") or "empty"))
    if IsLoaded("RougeUI") then NS.Print("  |cffff9944RougeUI is loaded|r - make sure its AutoHotKey option is off") end
end

function M:Apply()
    UpdateSoon(true)
end

function M:Init()
    for _, ev in ipairs({
        "PLAYER_LOGIN", "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS",
        "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
    }) do
        NS.On(ev, function() UpdateSoon() end)
    end
    NS.On("PLAYER_REGEN_ENABLED", function()
        if needsUpdate then UpdateSoon(true) end
    end)
end
