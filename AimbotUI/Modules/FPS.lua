--[[
  Aimbot UI - FPS / MS counter
  A small, always-on readout at the bottom centre of the screen:
      144 fps  |  23 ms
  Frame rate comes from GetFramerate(); latency from GetNetStats() (home = your
  connection to the realm, world = the game server). Numbers can be coloured by how
  good they are. Unlock the readout to drag it anywhere.
  Nothing here touches Blizzard frames, and secret values are ignored.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "FPS / MS",
    group = "QoL",
    desc = "Shows your frame rate and latency at the bottom centre of the screen. Colours show how good "
        .. "the numbers are. Unlock it to drag it anywhere.",
    defaults = {
        enabled      = true,
        showFPS      = true,
        showMS       = true,
        latency      = "both",                -- "home", "world" or "both"
        colorByValue = true,
        color        = { 1.0, 1.0, 1.0, 1 },  -- used when colour-by-value is off
        size         = 14,
        outline      = true,
        background   = false,
        labels       = true,                  -- the words "fps" and "ms"
        locked       = true,
        point        = { "BOTTOM", "BOTTOM", 0, 14 },
        interval     = 0.5,
    },
}
NS.RegisterModule("fps", M)

local function S() return NS.db.mod.fps end

local frame, text, bg

local function Num(v)
    if type(v) ~= "number" or NS.IsSecret(v) then return nil end
    return v
end

-- Green / yellow / red hex for a value. "Higher is better" for frame rate.
local function Hex(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
local GOOD, OK, BAD = Hex(0.30, 1.00, 0.30), Hex(1.00, 0.85, 0.20), Hex(1.00, 0.35, 0.35)

local function FpsColor(v) if v >= 60 then return GOOD elseif v >= 30 then return OK end return BAD end
local function MsColor(v) if v < 100 then return GOOD elseif v < 200 then return OK end return BAD end

local function Paint(value, colorFn)
    local s = S()
    if s.colorByValue then return colorFn(value) .. value .. "|r" end
    return tostring(value)
end

-- Builds the string shown on screen.
local function Compose(fps, home, world)
    local s = S()
    local parts = {}
    if s.showFPS and fps then
        local f = math.floor(fps + 0.5)
        parts[#parts + 1] = Paint(f, FpsColor) .. (s.labels and " fps" or "")
    end
    if s.showMS then
        local a, b = home and math.floor(home + 0.5), world and math.floor(world + 0.5)
        local str
        if s.latency == "home" and a then
            str = Paint(a, MsColor)
        elseif s.latency == "world" and b then
            str = Paint(b, MsColor)
        elseif s.latency == "both" and a and b then
            str = Paint(a, MsColor) .. " / " .. Paint(b, MsColor)
        elseif a or b then
            str = Paint(a or b, MsColor)
        end
        if str then parts[#parts + 1] = str .. (s.labels and " ms" or "") end
    end
    return table.concat(parts, "   ")
end

local function Update()
    if not frame then return end
    local s = S()
    if not s.enabled then return end
    if not s.locked then return end                     -- the placeholder text is showing
    local fps = GetFramerate and Num(GetFramerate()) or nil
    local home, world
    if GetNetStats then
        local ok, _, _, h, w = pcall(GetNetStats)
        if ok then home, world = Num(h), Num(w) end
    end
    text:SetText(Compose(fps, home, world))
end

local function ApplyPosition()
    if not frame then return end
    local p = S().point
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    if point then
        local p = S().point
        p[1], p[2], p[3], p[4] = point, relPoint, x, y
    end
end

local function ApplyStyle()
    if not frame then return end
    local s = S()
    text:SetFont(STANDARD_TEXT_FONT, s.size, s.outline and "OUTLINE" or "")
    local c = s.color
    text:SetTextColor(c[1], c[2], c[3])
    frame:SetSize(math.max(120, s.size * 11), s.size + 12)
    frame:SetShown(s.enabled)
    frame:EnableMouse(not s.locked)
    bg:SetShown(not s.locked or s.background)
    if s.locked then bg:SetColorTexture(0, 0, 0, 0.35) else bg:SetColorTexture(0.2, 0.6, 1, 0.3) end
    if not s.locked then text:SetText("FPS / MS  (drag me)") end
end

local function Ensure()
    if frame then return end
    frame = CreateFrame("Frame", "AimbotUIFPS", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not S().locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    text:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    ApplyPosition()
    ApplyStyle()

    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < (S().interval or 0.5) then return end
        acc = 0
        local ok, err = pcall(Update)
        if not ok then NS.ReportError("FPS / MS", err) end
    end)
end

function M:Apply()
    Ensure()
    ApplyPosition()
    ApplyStyle()
    Update()
end

function M:Init()
    Ensure()
    Update()
end

function M.Build(page)
    page:Section("What to show", "Frame rate and latency")
    page:Check("Show frame rate (FPS)", function() return S().showFPS end,
        function(v) S().showFPS = v; Update() end)
    page:Check("Show latency (MS)", function() return S().showMS end,
        function(v) S().showMS = v; Update() end)
    page:Cycle("Latency to show", {
            { "both", "Home / World" },
            { "home", "Home only" },
            { "world", "World only" },
        },
        function() return S().latency end,
        function(v) S().latency = v; Update() end)
    page:Note("Home is your connection to the realm (chat, mail, auction house). World is your connection to "
        .. "the game server, and is the one that matters for combat.")
    page:Check("Show the words \"fps\" and \"ms\"", function() return S().labels end,
        function(v) S().labels = v; Update() end)

    page:Section("Look", "Size, colour and outline")
    page:Slider("Text size", 8, 40, 1,
        function() return S().size end,
        function(v) S().size = v; ApplyStyle() end)
    page:Check("Colour the numbers by how good they are", function() return S().colorByValue end,
        function(v) S().colorByValue = v; Update() end)
    page:Note("Green: 60+ fps or under 100 ms. Yellow: 30-59 fps or 100-199 ms. Red: below 30 fps or 200+ ms.")
    page:Color("Text color (when not colouring by value)",
        function() return S().color end,
        function(r, g, b) local c = S().color; c[1], c[2], c[3] = r, g, b; ApplyStyle() end)
    page:Check("Text outline", function() return S().outline end,
        function(v) S().outline = v; ApplyStyle() end)
    page:Check("Dark background behind the text", function() return S().background end,
        function(v) S().background = v; ApplyStyle() end)

    page:Section("Position", "Move the counter")
    page:Check("Lock position", function() return S().locked end,
        function(v) S().locked = v; ApplyStyle(); Update() end)
    page:Note("Unlock to drag the counter anywhere. It starts at the bottom centre of the screen.")
    page:Button("Back to bottom centre", function()
        local p = S().point
        p[1], p[2], p[3], p[4] = "BOTTOM", "BOTTOM", 0, 14
        ApplyPosition()
    end)

    page:Section("Speed", "How often the numbers update")
    page:Slider("Update every (seconds)", 0.1, 2, 0.1,
        function() return S().interval end,
        function(v) S().interval = v end,
        function(v) return string.format("%.1f", v) end)
end

M._t = { Update = Update, Compose = Compose, Frame = function() return frame end, Text = function() return text end }
