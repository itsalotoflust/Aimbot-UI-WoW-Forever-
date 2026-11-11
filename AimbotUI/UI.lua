--[[
  Aimbot UI - Window + widgets

  A fully customizable window:
    * drag the title bar to move, drag the bottom-right grip to resize
    * scale, opacity, background / border / accent colors, text size, lock
  Layout
    * grouped sidebar with an on/off dot per module
    * every tab has a pinned header (title, description, enable switch, reset)
    * settings live in cards; rows stretch with the window, so resizing is clean
  Everything is built from plain frames and textures (no Blizzard templates),
  so it can't break when the client changes its templates.
]]

local ADDON_NAME, NS = ...
local UI = {}
NS.UI = UI

local FONT  = STANDARD_TEXT_FONT
local WHITE = "Interface\\Buttons\\WHITE8X8"

local ROUND = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\ui\\circle"

local SIDEBAR_W = 245
local HEADER_H  = 84

local texts   = setmetatable({}, { __mode = "k" })  -- fontstring -> size offset
local accents = setmetatable({}, { __mode = "k" })  -- texture    -> alpha multiplier
local roles   = setmetatable({}, { __mode = "k" })  -- fontstring -> "body" | "muted" (follows the text colors)
local rounds  = setmetatable({}, { __mode = "k" })  -- round textures: coloured with SetVertexColor
local pages   = {}
local tabs    = {}
local tabList = {}
local win, content, sidebar, titleBar, titleBG, bgTex, sideBG, grip
local borderEdges = {}
local edgeVertical = {}     -- border edge texture -> true for the left / right edges
local underlines = {}       -- the short accent lines under each tab title
local currentTab

local function W() return NS.db.window end

-- Window fonts. "default" is the game's own font; the rest are game fonts that every client has,
-- plus the fonts that ship with Aimbot UI.
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\fonts\\"
UI.FONTS = {
    { "default",  "Game default" },
    { "friz",     "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
    { "arial",    "Arial Narrow",  "Fonts\\ARIALN.TTF" },
    { "skurri",   "Skurri",        "Fonts\\skurri.ttf" },
    { "morpheus", "Morpheus",      "Fonts\\MORPHEUS.TTF" },
    { "damage1",  "Pepsi (Aimbot UI)",  MEDIA .. "damage1.ttf" },
    { "damage4",  "Bold (Aimbot UI)",   MEDIA .. "damage4.ttf" },
}
local function Font()
    local id = NS.db and W().font
    for _, f in ipairs(UI.FONTS) do
        if f[1] == id and f[3] then return f[3] end
    end
    return FONT
end
local function Flags()
    local o = NS.db and W().fontOutline
    if o == "OUTLINE" or o == "THICKOUTLINE" then return o end
    return ""
end
-- Sets a font, falling back to the game font if the chosen file can't be used.
local function SetFontSafe(fs, size)
    local ok, done = pcall(fs.SetFont, fs, Font(), size, Flags())
    if not ok or done == false then pcall(fs.SetFont, fs, FONT, size, Flags()) end
    if fs.SetShadowOffset then
        local sh = NS.db and W().textShadow
        pcall(fs.SetShadowOffset, fs, sh and 1 or 0, sh and -1 or 0)
        if fs.SetShadowColor then pcall(fs.SetShadowColor, fs, 0, 0, 0, sh and 1 or 0) end
    end
end
UI.SetFontSafe = SetFontSafe

----------------------------------------------------------------------
-- Primitives
----------------------------------------------------------------------
function UI.Text(parent, text, offset, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local size = (NS.db and W().fontSize or 12) + (offset or 0)
    SetFontSafe(fs, size)
    fs:SetJustifyH("LEFT")
    if r == nil then
        roles[fs] = "body"
        local c = (NS.db and W().text) or { 0.90, 0.90, 0.92 }
        fs:SetTextColor(c[1], c[2], c[3])
    elseif r == 0.62 and g == 0.62 and b == 0.67 then
        roles[fs] = "muted"       -- the standard grey used for notes and descriptions
        local c = (NS.db and W().muted) or { 0.62, 0.62, 0.67 }
        fs:SetTextColor(c[1], c[2], c[3])
    else
        fs:SetTextColor(r, g, b)
    end
    fs:SetText(text or "")
    texts[fs] = offset or 0
    return fs
end

-- Paint a texture with a flat colour. Round textures keep their shape and are tinted instead.
local function Paint(tex, r, g, b, a)
    if rounds[tex] then tex:SetVertexColor(r, g, b, a or 1) else tex:SetColorTexture(r, g, b, a or 1) end
end
UI.Paint = Paint

-- A round (circle) texture. If the image can't be found (it needs a full game restart the
-- first time), it falls back to a plain square so nothing goes missing.
function UI.Round(parent, layer, size)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    local ok, loaded = pcall(t.SetTexture, t, ROUND)
    if ok and loaded ~= false then
        rounds[t] = true
    else
        t:SetColorTexture(1, 1, 1, 1)
    end
    if size then t:SetSize(size, size) end
    return t
end

-- Classic WoW style (set once when the window is built; switching style needs a /reload).
UI.classic = false
local GOLD = { 1, 0.82, 0 }

-- Classic window borders and backgrounds.
local CLASSIC_BORDERS = {
    stone   = { file = "Interface\\DialogFrame\\UI-DialogBox-Border", size = 32, inset = 11, out = 9 },
    gold    = { file = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", size = 32, inset = 11, out = 9 },
    tooltip = { file = "Interface\\Tooltips\\UI-Tooltip-Border", size = 16, inset = 4, out = 3 },
    none    = { file = nil, size = 0, inset = 0, out = 0 },
}
local CLASSIC_BACKS = {
    dark   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    rock   = "Interface\\FrameGeneral\\UI-Background-Rock",
    marble = "Interface\\FrameGeneral\\UI-Background-Marble",
    plain  = WHITE,
}

-- Put a game texture on tex. Returns false (and paints the fallback colour) if it can't load.
local function Art(tex, file, r, g, b, a)
    local ok, loaded = pcall(tex.SetTexture, tex, file)
    if ok and loaded ~= false then return true end
    tex:SetColorTexture(r or 0, g or 0, b or 0, a or 0.6)
    return false
end
UI.Art = Art

-- A frame (or slider) that can take a Blizzard-style backdrop; plain frame if the template is missing.
local function BackdropFrame(kind, parent)
    local ok, f = pcall(CreateFrame, kind or "Frame", nil, parent, "BackdropTemplate")
    if ok and f then return f end
    return CreateFrame(kind or "Frame", nil, parent)
end

local function SetBackdrop(f, def)
    if not (f and f.SetBackdrop) then return false end
    return pcall(f.SetBackdrop, f, def)
end

function UI.Accent(tex, mult)
    accents[tex] = mult or 1
    local c = W().accent
    Paint(tex, c[1], c[2], c[3], (c[4] or 1) * (mult or 1))
end

local function RestyleTexts()
    local base = W().fontSize
    local body, muted = W().text, W().muted
    for fs, offset in pairs(texts) do
        SetFontSafe(fs, base + offset)
        local role = roles[fs]
        if role == "body" then fs:SetTextColor(body[1], body[2], body[3])
        elseif role == "muted" then fs:SetTextColor(muted[1], muted[2], muted[3]) end
    end
end

local function RestyleAccents()
    local c = W().accent
    for tex, mult in pairs(accents) do
        Paint(tex, c[1], c[2], c[3], (c[4] or 1) * mult)
    end
end

-- Four 1px edges around a frame. Returns the list so callers can recolor.
local function Edges(frame, r, g, b, a, layer)
    local list = {}
    local function E(p1, p2, w, h)
        local t = frame:CreateTexture(nil, layer or "BORDER")
        t:SetColorTexture(r, g, b, a)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        table.insert(list, t)
    end
    E("TOPLEFT", "TOPRIGHT", nil, 1)
    E("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    E("TOPLEFT", "BOTTOMLEFT", 1, nil)
    E("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    return list
end

local function Tip(frame, title, text)
    if not text or text == "" then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title or "", 1, 1, 1)
        GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Flat button: soft fill, a faint top light, accent wash on hover.
local function ClassicButton(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, height or 22)
    local function Part(layer, file)
        local t = b:CreateTexture(nil, layer)
        t:SetAllPoints()
        if Art(t, file, 0.45, 0.06, 0.04, 1) then t:SetTexCoord(0, 0.625, 0, 0.6875) end
        return t
    end
    local up = Part("BACKGROUND", "Interface\\Buttons\\UI-Panel-Button-Up")
    local down = Part("BACKGROUND", "Interface\\Buttons\\UI-Panel-Button-Down")
    down:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if Art(hl, "Interface\\Buttons\\UI-Panel-Button-Highlight", 1, 1, 1, 0.12) then
        hl:SetTexCoord(0, 0.625, 0, 0.6875)
        hl:SetBlendMode("ADD")
    end
    local fs = UI.Text(b, label, -1, GOLD[1], GOLD[2], GOLD[3])
    fs:SetPoint("CENTER", 0, 1)
    fs:SetJustifyH("CENTER")
    b.label = fs
    b:SetScript("OnMouseDown", function() up:Hide(); down:Show(); fs:SetPoint("CENTER", 1, 0) end)
    b:SetScript("OnMouseUp", function() down:Hide(); up:Show(); fs:SetPoint("CENTER", 0, 1) end)
    b:HookScript("OnEnter", function() fs:SetTextColor(1, 1, 1) end)
    b:HookScript("OnLeave", function() fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end)
    return b
end

function UI.MakeButton(parent, label, width, height)
    if UI.classic then return ClassicButton(parent, label, width, height) end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, height or 22)
    local fill = b:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(1, 1, 1, 0.07)
    local top = b:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    top:SetHeight(1)
    top:SetColorTexture(1, 1, 1, 0.06)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    UI.Accent(hl, 0.28)
    local fs = UI.Text(b, label, -1)
    fs:SetPoint("CENTER")
    fs:SetJustifyH("CENTER")
    b.label = fs
    b:SetScript("OnMouseDown", function() fill:SetColorTexture(0, 0, 0, 0.25) end)
    b:SetScript("OnMouseUp",   function() fill:SetColorTexture(1, 1, 1, 0.07) end)
    return b
end

----------------------------------------------------------------------
-- Color picker (supports both the new and the old ColorPickerFrame API)
----------------------------------------------------------------------
function UI.PickColor(r, g, b, a, onChange)
    local function Current()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = a
        if ColorPickerFrame.GetColorAlpha then
            na = ColorPickerFrame:GetColorAlpha()
        elseif OpacitySliderFrame and OpacitySliderFrame.GetValue then
            na = 1 - OpacitySliderFrame:GetValue()
        end
        return nr, ng, nb, na
    end
    local function Changed() onChange(Current()) end
    local function Cancelled() onChange(r, g, b, a) end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = a, hasOpacity = true,
            swatchFunc = Changed, opacityFunc = Changed, cancelFunc = Cancelled,
        })
    else
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - a
        ColorPickerFrame.previousValues = { r, g, b, 1 - a }
        ColorPickerFrame.func = Changed
        ColorPickerFrame.opacityFunc = Changed
        ColorPickerFrame.cancelFunc = Cancelled
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

----------------------------------------------------------------------
-- Switch (on/off pill). Used by every checkbox-style setting.
----------------------------------------------------------------------
-- Toggle switch: a pill-shaped track (two round ends and a middle) with a round knob.
local function MakeSwitch(parent, get, set)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(36, 18)
    local capL = UI.Round(sw, "BACKGROUND", 18)
    capL:SetPoint("LEFT", sw, "LEFT", 0, 0)
    local capR = UI.Round(sw, "BACKGROUND", 18)
    capR:SetPoint("RIGHT", sw, "RIGHT", 0, 0)
    local mid = sw:CreateTexture(nil, "BACKGROUND")
    mid:SetPoint("TOPLEFT", sw, "TOPLEFT", 9, 0)
    mid:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", -9, 0)
    local knob = UI.Round(sw, "ARTWORK", 14)
    local glow = UI.Round(sw, "HIGHLIGHT", 22)
    glow:SetPoint("CENTER", knob, "CENTER", 0, 0)
    Paint(glow, 1, 1, 1, 0.10)

    local function Track(r, g, b, a)
        Paint(capL, r, g, b, a); Paint(capR, r, g, b, a); Paint(mid, r, g, b, a)
    end
    function sw.Refresh()
        local on = get() and true or false
        knob:ClearAllPoints()
        if on then
            local c = W().accent
            Track(c[1], c[2], c[3], 1)
            Paint(knob, 1, 1, 1, 1)
            knob:SetPoint("RIGHT", sw, "RIGHT", -2, 0)
        else
            Track(0.22, 0.22, 0.25, 1)
            Paint(knob, 0.62, 0.62, 0.66, 1)
            knob:SetPoint("LEFT", sw, "LEFT", 2, 0)
        end
    end
    sw:SetScript("OnClick", function()
        set(not get())
        UI.RefreshAll()
    end)
    sw.Refresh()
    return sw
end

-- Blizzard checkbox (classic style). Same interface as a switch: .Refresh().
local function MakeCheck(parent, get, set)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(24, 24)
    local up = cb:CreateTexture(nil, "ARTWORK")
    up:SetAllPoints()
    if not Art(up, "Interface\\Buttons\\UI-CheckBox-Up", 0, 0, 0, 0.6) then
        up:ClearAllPoints(); up:SetPoint("CENTER"); up:SetSize(16, 16)
    end
    local hl = cb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if Art(hl, "Interface\\Buttons\\UI-CheckBox-Highlight", 1, 1, 1, 0.12) then hl:SetBlendMode("ADD") end
    local chk = cb:CreateTexture(nil, "OVERLAY")
    chk:SetAllPoints()
    if not Art(chk, "Interface\\Buttons\\UI-CheckBox-Check", GOLD[1], GOLD[2], GOLD[3], 1) then
        chk:ClearAllPoints(); chk:SetPoint("CENTER"); chk:SetSize(10, 10)
    end
    function cb.Refresh() chk:SetShown(get() and true or false) end
    cb:SetScript("OnClick", function()
        set(not get())
        UI.RefreshAll()
    end)
    cb.Refresh()
    return cb
end

local function Toggle(parent, get, set)
    if UI.classic then return MakeCheck(parent, get, set) end
    return MakeSwitch(parent, get, set)
end

----------------------------------------------------------------------
-- Page: a scrollable column of cards
----------------------------------------------------------------------
local Page = {}
Page.__index = Page

local function MakeScrollbar(parent, sf)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(4)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -3, -4)
    bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 4)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.03)
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(4)
    local tex = thumb:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    UI.Accent(tex, 0.55)
    bar.thumb = thumb
    bar:Hide()

    local dragging, startY, startScroll
    local function Update()
        local range = sf:GetVerticalScrollRange() or 0
        local vis = sf:GetHeight() or 1
        if range < 1 then bar:Hide(); return end
        bar:Show()
        local total = vis + range
        local th = math.max(28, vis * vis / total)
        local free = math.max(1, bar:GetHeight() - th)
        local pos = (sf:GetVerticalScroll() / range) * free
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -pos)
    end
    bar.Update = Update

    thumb:SetScript("OnMouseDown", function()
        dragging = true
        startY = select(2, GetCursorPosition()) / sf:GetEffectiveScale()
        startScroll = sf:GetVerticalScroll()
    end)
    thumb:SetScript("OnMouseUp", function() dragging = false end)
    thumb:SetScript("OnUpdate", function()
        if not dragging then return end
        local range = sf:GetVerticalScrollRange() or 0
        local free = math.max(1, bar:GetHeight() - thumb:GetHeight())
        local y = select(2, GetCursorPosition()) / sf:GetEffectiveScale()
        local v = startScroll + (startY - y) / free * range
        sf:SetVerticalScroll(math.max(0, math.min(range, v)))
    end)
    return bar
end

function UI.NewPage(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 0)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(500, 10)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:Hide()

    local p = setmetatable({
        frame = sf, child = child, cards = {}, refreshers = {},
    }, Page)
    p.bar = MakeScrollbar(parent, sf)
    p.bar:Hide()

    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 56)))
    end)
    sf:SetScript("OnVerticalScroll", function() p.bar.Update() end)
    sf:SetScript("OnScrollRangeChanged", function() p.bar.Update() end)
    sf:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then child:SetWidth(w) end
        p:Reflow()
    end)

    table.insert(pages, p)
    return p
end

-- A page with three or more sections shows one area at a time, chosen from the side menu
-- dropdown. "Pinned" sections (previews) stay on screen.

local function CardShown(self, card)
    if card.pinned or not self.menuMode then return true end
    return self.view == card
end

local function LayoutCard(self, card, y, cw)
    card.frame:Show()
    card.frame:ClearAllPoints()
    card.frame:SetPoint("TOPLEFT", self.child, "TOPLEFT", 4, -y)
    card.frame:SetPoint("TOPRIGHT", self.child, "TOPRIGHT", -4, -y)
    local iy = card.title and (card.descText and (UI.classic and 62 or 60) or (UI.classic and 46 or 44)) or 14
    local innerW = cw - 8 - 32
    for _, row in ipairs(card.rows) do
        local h = row.height(innerW)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", card.frame, "TOPLEFT", 16, -iy)
        row.frame:SetPoint("TOPRIGHT", card.frame, "TOPRIGHT", -16, -iy)
        row.frame:SetHeight(h)
        iy = iy + h + 8
    end
    card.frame:SetHeight(iy + 8)
    return iy + 8 + 14
end

function Page:Reflow()
    local menu = self.menuMode
    -- visibility first, so it is right even before the window has a width
    for _, card in ipairs(self.cards) do
        if not CardShown(self, card) then card.frame:Hide() end
    end

    local cw = self.child:GetWidth()
    if not cw or cw < 80 then return end
    local y = 4

    -- pinned sections first, then the rest
    for pass = 1, 2 do
        for _, card in ipairs(self.cards) do
            if (pass == 1) == (card.pinned and true or false) then
                if CardShown(self, card) then
                    y = y + LayoutCard(self, card, y, cw)
                else
                    card.frame:Hide()
                end
            end
        end
    end

    self.child:SetHeight(y + 4)
    if self.bar then self.bar.Update() end
end

function Page:Open(card)
    self.view = card
    if self.frame.SetVerticalScroll then self.frame:SetVerticalScroll(0) end
    self:Reflow()
    if UI.LayoutSidebar then UI.LayoutSidebar() end
end

function Page:Back() end     -- kept so older calls do nothing harmful; the side menu dropdown replaced it

-- Called once after a module's Build(): decides whether this page gets the area list.
function Page:Finish()
    local areas = {}
    for _, card in ipairs(self.cards) do
        if card.title and not card.pinned and #card.rows > 0 then areas[#areas + 1] = card end
    end
    if #areas < 3 then self.menuMode = false; return end
    self.menuMode = true
    self.areas = areas

    -- No separate list of areas any more: the side menu dropdown does that job.
    -- The page always shows one area; the one marked { open = true } (or the first) to begin with.
    local first = areas[1]
    for _, card in ipairs(areas) do
        if card.openFirst then first = card; break end
    end
    self:Open(first)
end

function Page:Section(title, desc, opts)
    local f = CreateFrame("Frame", nil, self.child)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if UI.classic then
        bg:SetColorTexture(0, 0, 0, 0.22)
        Edges(f, 1, 1, 1, 0.06, "BORDER")
    else
        bg:SetColorTexture(1, 1, 1, 0.03)
        Edges(f, 1, 1, 1, 0.055, "BORDER")
        local shine = f:CreateTexture(nil, "BORDER")     -- faint light along the top edge
        shine:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        shine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        shine:SetHeight(1)
        shine:SetColorTexture(1, 1, 1, 0.05)
    end
    local card = { frame = f, rows = {}, title = title, desc = desc,
        pinned = (type(opts) == "table" and opts.pinned) and true or false,
        openFirst = (type(opts) == "table" and opts.open) and true or false }
    if title then
        local dot = UI.Round(f, "ARTWORK", 7)
        dot:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -17)
        UI.Accent(dot, 1)
        local fs = UI.Text(f, title, UI.classic and 4 or 2, 1, 1, 1)
        fs:SetPoint("LEFT", dot, "RIGHT", 9, 0)
        card.titleText = fs
        if UI.classic then
            -- Blizzard-style divider under the title
            local div = f:CreateTexture(nil, "ARTWORK")
            div:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -26)
            div:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -26)
            div:SetHeight(8)
            if not Art(div, "Interface\\Common\\UI-TooltipDivider-Transparent", GOLD[1], GOLD[2], GOLD[3], 0.25) then
                div:SetHeight(1)
            end
        end
        if type(desc) == "string" and desc ~= "" then
            local d = UI.Text(f, desc, -1, 0.62, 0.62, 0.67)
            d:SetPoint("TOPLEFT", f, "TOPLEFT", 32, UI.classic and -36 or -32)
            d:SetPoint("RIGHT", f, "RIGHT", -16, 0)
            d:SetWordWrap(false)
            card.descText = d
        end
    end
    table.insert(self.cards, card)
    self.current = card
    return card
end
Page.Header = Page.Section   -- older modules call Header()

local function AddRow(self, height, label)
    local card = self.current or self:Section(nil)
    local f = CreateFrame("Frame", nil, card.frame)
    local row = {
        frame = f, label = type(label) == "string" and label or nil,
        height = (type(height) == "function") and height or function() return height end,
    }
    table.insert(card.rows, row)
    return f, row
end

function Page:Note(text)
    local f, row = AddRow(self, 14)
    row.note = type(text) == "string" and text or nil          -- searchable, but ranks below real settings
    local fs = UI.Text(f, text, -1, 0.62, 0.62, 0.67)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    row.height = function(w)
        if w and w > 20 then fs:SetWidth(w) end
        local h = fs:GetStringHeight()
        if not h or h < 12 then h = 14 end
        return h + 2
    end
    self:Reflow()
    return fs
end

function Page:Check(label, get, set, desc)
    local f = AddRow(self, 24, label)
    local sw = Toggle(f, get, set)
    local fs = UI.Text(f, label)
    if UI.classic then
        sw:SetPoint("LEFT", f, "LEFT", -4, 0)
        fs:SetPoint("LEFT", sw, "RIGHT", 2, 1)
        fs:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    else
        sw:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        fs:SetPoint("LEFT", f, "LEFT", 0, 0)
        fs:SetPoint("RIGHT", sw, "LEFT", -12, 0)
    end
    fs:SetWordWrap(false)
    if type(desc) == "string" then Tip(sw, label, desc) end
    table.insert(self.refreshers, sw.Refresh)
    self:Reflow()
    return sw
end

-- The number on the right of a slider is a small text box: click it, type a value and press
-- Enter (Escape or clicking away puts the old value back). Typed values are kept inside the
-- slider's range and rounded to its step.
local function ParseNumber(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub(",", "."):gsub("[^%d%.%-]", "")
    return tonumber(text)
end

function Page:Slider(label, min, max, step, get, set, fmt)
    local f = AddRow(self, 24, label)
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    holder:SetSize(58, 20)
    local edge = holder:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(1, 1, 1, 0.10)
    local inner = holder:CreateTexture(nil, "BORDER")
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.05, 0.05, 0.06, 1)

    local val = CreateFrame("EditBox", nil, holder)
    val:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -1)
    val:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -4, 1)
    val:SetAutoFocus(false)
    val:SetMaxLetters(12)
    val:SetJustifyH("CENTER")
    SetFontSafe(val, (NS.db and W().fontSize or 12))
    texts[val] = 0
    roles[val] = "body"
    local tc = (NS.db and W().text) or { 0.90, 0.90, 0.92 }
    val:SetTextColor(tc[1], tc[2], tc[3])
    Tip(val, label, string.format("Click and type a value, then press Enter (%s to %s).",
        fmt and fmt(min) or tostring(min), fmt and fmt(max) or tostring(max)))

    local s = UI.classic and BackdropFrame("Slider", f) or CreateFrame("Slider", nil, f)
    s:SetPoint("RIGHT", holder, "LEFT", -10, 0)
    s:SetSize(180, UI.classic and 17 or 18)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(1, 1, 1, 0.10)

    local classicBar = UI.classic and SetBackdrop(s, {
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    local thumb
    if classicBar then
        track:Hide()
        local okT = pcall(s.SetThumbTexture, s, "Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        if not okT then s:SetThumbTexture(WHITE) end
        thumb = s:GetThumbTexture()
        thumb:SetSize(32, 32)
        if not okT then thumb:SetSize(10, 16); UI.Accent(thumb, 1) end
    else
        local thumbOK = pcall(s.SetThumbTexture, s, ROUND)
        if not thumbOK then s:SetThumbTexture(WHITE) end
        thumb = s:GetThumbTexture()
        if thumbOK then rounds[thumb] = true end
        thumb:SetSize(14, 14)
        UI.Accent(thumb, 1)
        local fill = s:CreateTexture(nil, "ARTWORK")
        fill:SetHeight(4)
        fill:SetPoint("LEFT", track, "LEFT", 0, 0)
        fill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)
        UI.Accent(fill, 0.6)
    end

    local fs = UI.Text(f, label)
    fs:SetPoint("LEFT", f, "LEFT", 0, 0)
    fs:SetPoint("RIGHT", s, "LEFT", -12, 0)
    fs:SetWordWrap(false)

    local refreshing = false
    local function show(v) val:SetText(fmt and fmt(v) or tostring(v)) end
    local function snap(v)
        v = math.floor(v / step + 0.5) * step
        return tonumber(string.format("%.4f", v))
    end
    s:SetScript("OnValueChanged", function(_, v)
        if refreshing then return end
        v = snap(v)
        show(v)
        set(v)
    end)
    local function refresh()
        refreshing = true
        local v = get() or min
        s:SetValue(v)
        if not val:HasFocus() then show(v) end
        refreshing = false
    end

    local function commit()
        local v = ParseNumber(val:GetText())
        if v then
            v = snap(math.max(min, math.min(max, v)))
            refreshing = true
            s:SetValue(v)
            refreshing = false
            set(v)
            show(v)
        else
            show(get() or min)
        end
        val:ClearFocus()
    end
    val:SetScript("OnEnterPressed", commit)
    val:SetScript("OnEscapePressed", function() show(get() or min); val:ClearFocus() end)
    val:SetScript("OnEditFocusGained", function()
        local a = W().accent
        edge:SetColorTexture(a[1], a[2], a[3], 1)
        val:HighlightText()
    end)
    val:SetScript("OnEditFocusLost", function()
        edge:SetColorTexture(1, 1, 1, 0.10)
        val:HighlightText(0, 0)
        show(get() or min)
    end)
    table.insert(self.refreshers, refresh)
    refresh()
    self:Reflow()
    return s
end

function Page:Color(label, get, set)
    local f = AddRow(self, 24, label)
    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(40, 18)
    btn:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    local edge = btn:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(1, 1, 1, 0.25)
    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 1, -1)
    swatch:SetPoint("BOTTOMRIGHT", -1, 1)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)

    local fs = UI.Text(f, label)
    fs:SetPoint("LEFT", f, "LEFT", 0, 0)
    fs:SetPoint("RIGHT", btn, "LEFT", -12, 0)
    fs:SetWordWrap(false)

    local function refresh()
        local c = get()
        swatch:SetColorTexture(c[1], c[2], c[3], 1)
    end
    btn:SetScript("OnClick", function()
        local c = get()
        UI.PickColor(c[1], c[2], c[3], c[4] or 1, function(r, g, b, a)
            set(r, g, b, a)
            refresh()
        end)
    end)
    table.insert(self.refreshers, refresh)
    refresh()
    self:Reflow()
    return btn
end

-- One shared drop-down list: opens under a box, one row per option, closes on pick,
-- on a second click, or when the mouse leaves it for a moment.
local dropList, dropOwner
local function DropList()
    if dropList then return dropList end
    local l = BackdropFrame("Frame", UIParent)
    l:SetFrameStrata("FULLSCREEN_DIALOG")
    l:SetClampedToScreen(true)
    l:EnableMouse(true)
    l:Hide()
    if not SetBackdrop(l, {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    }) then
        local bg = l:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.06, 0.07, 0.97)
        Edges(l, 1, 1, 1, 0.15)
    elseif l.SetBackdropColor then
        pcall(l.SetBackdropColor, l, 0.04, 0.04, 0.05, 0.96)
    end
    l.rows = {}
    local away = 0
    l:SetScript("OnUpdate", function(self, dt)
        if self:IsMouseOver() or (dropOwner and dropOwner:IsMouseOver()) then away = 0; return end
        away = away + (dt or 0)
        if away > 1.2 then self:Hide() end
    end)
    l:SetScript("OnHide", function() dropOwner = nil; away = 0 end)
    dropList = l
    return l
end

local function OpenDropList(owner, options, cur, onPick)
    local l = DropList()
    if l:IsShown() and dropOwner == owner then l:Hide(); return end
    dropOwner = owner
    local ROW = 20
    for i, o in ipairs(options) do
        local r = l.rows[i]
        if not r then
            r = CreateFrame("Button", nil, l)
            r:SetHeight(ROW)
            local hl = r:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            UI.Accent(hl, 0.25)
            r.mark = r:CreateTexture(nil, "ARTWORK")
            r.mark:SetSize(5, 5)
            r.mark:SetPoint("LEFT", r, "LEFT", 8, 0)
            UI.Accent(r.mark, 1)
            r.text = UI.Text(r, "", -1)
            r.text:SetPoint("LEFT", r, "LEFT", 20, 0)
            r.text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.text:SetWordWrap(false)
            l.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", l, "TOPLEFT", 4, -4 - (i - 1) * ROW)
        r:SetPoint("TOPRIGHT", l, "TOPRIGHT", -4, -4 - (i - 1) * ROW)
        r.text:SetText(o[2])
        r.mark:SetShown(o[1] == cur)
        r:SetScript("OnClick", function() l:Hide(); onPick(o[1]) end)
        r:Show()
    end
    for i = #options + 1, #l.rows do l.rows[i]:Hide() end
    l:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    l:SetWidth(math.max(160, owner:GetWidth()))
    l:SetHeight(#options * ROW + 8)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    l:Show()
end

-- The box that opens the list: looks like a game drop-down in the classic style.
local function MakeDropBox(parent, width, height)
    if not UI.classic then
        local b = UI.MakeButton(parent, "", width, height)
        local arrow = UI.Text(b, "v", -2, 0.62, 0.62, 0.67)
        arrow:SetPoint("RIGHT", b, "RIGHT", -8, 0)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", b, "LEFT", 10, 0)
        b.label:SetPoint("RIGHT", arrow, "LEFT", -6, 0)
        b.label:SetJustifyH("LEFT")
        b.label:SetWordWrap(false)
        return b
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0.42, 0.42, 0.45, 1)
    local fill = b:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(0.02, 0.02, 0.03, 0.92)
    local arrow = b:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(height - 2, height - 2)
    arrow:SetPoint("RIGHT", b, "RIGHT", -1, 0)
    if not Art(arrow, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", GOLD[1], GOLD[2], GOLD[3], 0.8) then
        arrow:SetSize(8, 8)
    end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 1, 1, 0.06)
    local fs = UI.Text(b, "", -1, 1, 1, 1)
    fs:SetPoint("LEFT", b, "LEFT", 8, 0)
    fs:SetPoint("RIGHT", arrow, "LEFT", -2, 0)
    fs:SetWordWrap(false)
    b.label = fs
    return b
end

-- options = { { "key", "Label" }, ... }
function Page:Cycle(label, options, get, set)
    local f = AddRow(self, 26, label)
    local btn = MakeDropBox(f, 190, 22)
    btn:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    local fs = UI.Text(f, label)
    fs:SetPoint("LEFT", f, "LEFT", 0, 0)
    fs:SetPoint("RIGHT", btn, "LEFT", -12, 0)
    fs:SetWordWrap(false)

    local function refresh()
        local cur = get()
        for _, o in ipairs(options) do
            if o[1] == cur then btn.label:SetText(o[2]); return end
        end
        btn.label:SetText(tostring(cur))
    end
    btn:SetScript("OnClick", function()
        OpenDropList(btn, options, get(), function(v)
            set(v)
            refresh()
        end)
    end)
    table.insert(self.refreshers, refresh)
    refresh()
    self:Reflow()
    return btn
end

function Page:Button(label, onClick, width)
    local f = AddRow(self, 28, label)
    local b = UI.MakeButton(f, label, width or 220, 24)
    b:SetPoint("LEFT", f, "LEFT", 0, 0)
    b:SetScript("OnClick", onClick)
    self:Reflow()
    return b
end

local function Trim(s)
    s = tostring(s or ""):gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

-- A text box with an Add button on one row. onSubmit(text) runs on Enter or on the
-- button; the box is cleared afterwards unless onSubmit returns false.
function Page:Input(placeholder, onSubmit, buttonText)
    local f = AddRow(self, 28, placeholder)
    local btn = UI.MakeButton(f, buttonText or "Add", 72, 24)
    btn:SetPoint("RIGHT", f, "RIGHT", 0, 0)

    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("LEFT", f, "LEFT", 0, 0)
    holder:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    holder:SetHeight(24)
    local edge = holder:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(1, 1, 1, 0.10)
    local fill = holder:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(0.05, 0.05, 0.06, 1)

    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", 7, -2)
    box:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -7, 2)
    box:SetAutoFocus(false)
    box:SetMaxLetters(80)
    SetFontSafe(box, (NS.db and W().fontSize or 12))
    texts[box] = 0
    roles[box] = "body"
    local c = (NS.db and W().text) or { 0.90, 0.90, 0.92 }
    box:SetTextColor(c[1], c[2], c[3])

    local hint = UI.Text(holder, placeholder or "", -1, 0.62, 0.62, 0.67)
    hint:SetPoint("LEFT", holder, "LEFT", 8, 0)
    hint:SetPoint("RIGHT", holder, "RIGHT", -8, 0)
    hint:SetWordWrap(false)

    local function showHint()
        hint:SetShown((box:GetText() or "") == "" and not box:HasFocus())
    end
    local function submit()
        local text = Trim(box:GetText())
        if text == "" then box:ClearFocus(); return end
        local keep = onSubmit(text)
        if keep ~= false then box:SetText("") end
        box:ClearFocus()
        showHint()
    end
    box:SetScript("OnEnterPressed", submit)
    box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
    box:SetScript("OnTextChanged", showHint)
    box:SetScript("OnEditFocusGained", function()
        local a = W().accent
        edge:SetColorTexture(a[1], a[2], a[3], 1)
        showHint()
    end)
    box:SetScript("OnEditFocusLost", function()
        edge:SetColorTexture(1, 1, 1, 0.10)
        showHint()
    end)
    btn:SetScript("OnClick", submit)
    showHint()
    self:Reflow()
    return box, btn
end

-- A free-form area (used by the trainer list). The owner calls
-- container:SetContentHeight(h) whenever its content changes size.
function Page:Container()
    local f, row = AddRow(self, 10)
    local page = self
    f.contentHeight = 10
    row.height = function() return f.contentHeight end
    function f:SetContentHeight(h)
        self.contentHeight = math.max(1, h)
        page:Reflow()
    end
    self:Reflow()
    return f
end

-- Side menu order: groups in a fixed order, modules A-Z inside each group.
local GROUP_ORDER = { Style = 1, Combat = 2, Tools = 3, QoL = 4 }
local GROUP_LABEL = { Style = "LOOK", Combat = "COMBAT", Tools = "TOOLS", QoL = "QUALITY OF LIFE" }
local function SortedModules()
    local list = {}
    for i, key in ipairs(NS.moduleOrder) do list[#list + 1] = { key = key, i = i } end
    table.sort(list, function(a, b)
        local ma, mb = NS.modules[a.key], NS.modules[b.key]
        local ga, gb = GROUP_ORDER[ma.group or ""] or 9, GROUP_ORDER[mb.group or ""] or 9
        if ga ~= gb then return ga < gb end
        local na, nb = string.lower(ma.name or a.key), string.lower(mb.name or b.key)
        if na ~= nb then return na < nb end
        return a.i < b.i
    end)
    for i, e in ipairs(list) do list[i] = e.key end
    return list
end
UI.SortedModules = SortedModules

----------------------------------------------------------------------
-- Window-wide refresh
----------------------------------------------------------------------
local function RefreshTabDots()
    for _, t in ipairs(tabList) do
        if t.module then
            local on = NS.Mod(t.key) and NS.Mod(t.key).enabled
            if on then
                local c = W().accent
                Paint(t.dot, c[1], c[2], c[3], 1)
            else
                Paint(t.dot, 0.32, 0.32, 0.35, 1)
            end
        end
    end
end

function UI.RefreshAll()
    for _, p in ipairs(pages) do
        for _, fn in ipairs(p.refreshers) do fn() end
    end
    for _, t in ipairs(tabList) do
        if t.switch then t.switch.Refresh() end
    end
    RefreshTabDots()
end

function UI.ApplyStyle()
    if not win then return end
    local w = W()
    win:SetScale(w.scale)
    bgTex:SetColorTexture(w.bg[1], w.bg[2], w.bg[3], w.bg[4])
    if UI.classic and UI._deco then
        local bd = CLASSIC_BORDERS[w.classicBorder or "stone"] or CLASSIC_BORDERS.stone
        local back = CLASSIC_BACKS[w.classicBack or "dark"] or CLASSIC_BACKS.dark
        local deco = UI._deco
        deco:ClearAllPoints()
        deco:SetPoint("TOPLEFT", win, "TOPLEFT", -bd.out, bd.out)
        deco:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", bd.out, -bd.out)
        local ok = SetBackdrop(deco, {
            bgFile = back, edgeFile = bd.file, tile = true, tileSize = (back == WHITE) and 8 or 256,
            edgeSize = bd.size, insets = { left = bd.inset, right = bd.inset, top = bd.inset, bottom = bd.inset },
        })
        if ok and deco.SetBackdropColor then
            if back == WHITE then
                pcall(deco.SetBackdropColor, deco, w.bg[1], w.bg[2], w.bg[3], w.bg[4])
            else
                pcall(deco.SetBackdropColor, deco, 1, 1, 1, w.bg[4])
            end
            bgTex:SetColorTexture(0, 0, 0, 0)            -- the backdrop is the background now
        end
    end
    titleBG:SetColorTexture(w.titleBar[1], w.titleBar[2], w.titleBar[3], w.bg[4])
    sideBG:SetColorTexture(w.sidebar[1], w.sidebar[2], w.sidebar[3], w.sidebar[4])
    local bs = math.max(1, math.min(4, math.floor((w.borderSize or 1) + 0.5)))
    for _, e in ipairs(borderEdges) do
        e:SetColorTexture(w.border[1], w.border[2], w.border[3], UI.classic and 0 or w.border[4])
        if edgeVertical[e] then e:SetWidth(bs) else e:SetHeight(bs) end
    end
    RestyleAccents()
    RestyleTexts()
    -- title bar: title colour, version text, accent mark and line
    if UI._title then
        local tc = w.titleColorOn and w.titleColor or (UI.classic and GOLD) or { 1, 1, 1 }
        UI._title:SetTextColor(tc[1], tc[2], tc[3])
    end
    if UI._ver then UI._ver:SetShown(w.showVersion ~= false) end
    if UI._mark then
        UI._mark:SetShown(w.titleMark ~= false)
        UI._title:ClearAllPoints()
        if w.titleMark ~= false then UI._title:SetPoint("LEFT", UI._mark, "RIGHT", 8, 0)
        else UI._title:SetPoint("LEFT", titleBar, "LEFT", 12, 0) end
    end
    if UI._tline then UI._tline:SetShown(w.titleLine ~= false) end
    for _, u in ipairs(underlines) do u:SetShown(w.underlines ~= false) end
    grip:SetShown(not w.locked)
    for _, p in ipairs(pages) do p:Reflow() end
    UI.RefreshAll()
end

local function SavePosition()
    local point, _, relPoint, x, y = win:GetPoint()
    if point then W().point = { point, relPoint, x, y } end
end

local function SaveSize()
    W().w, W().h = math.floor(win:GetWidth() + 0.5), math.floor(win:GetHeight() + 0.5)
end

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------
local function SelectTab(key)
    currentTab = key
    for k, t in pairs(tabs) do
        local on = (k == key)
        t.expanded = on and t.page.menuMode and true or false     -- one dropdown open at a time
        t.page.frame:SetShown(on)
        t.header:SetShown(on)
        t.sel:SetShown(on)
        t.selBar:SetShown(on)
        if on then t.page:Reflow() end
    end
    if UI.LayoutSidebar then UI.LayoutSidebar(true) end
end

-- Pinned header: title, description, and (for modules) the enable switch + reset.
local function BuildHeader(parent, title, desc, key)
    local h = CreateFrame("Frame", nil, parent)
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    h:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    h:SetHeight(HEADER_H)
    h:Hide()

    local right = 0
    local sw
    if key then
        sw = Toggle(h, function() return NS.Mod(key).enabled end,
            function(v) NS.Mod(key).enabled = v; NS.ApplyModule(key) end)
        sw:SetPoint("TOPRIGHT", h, "TOPRIGHT", -16, -18)
        local lbl = UI.Text(h, "Enabled", -1, 0.65, 0.65, 0.70)
        lbl:SetPoint("RIGHT", sw, "LEFT", -8, 0)
        local refreshSwitch = sw.Refresh
        function sw.Refresh()
            refreshSwitch()
            local on = NS.Mod(key) and NS.Mod(key).enabled
            lbl:SetText(on and "On" or "Off")
        end
        local reset = UI.MakeButton(h, "Reset tab", 84, 20)
        reset:SetPoint("TOPRIGHT", sw, "BOTTOMRIGHT", 0, -8)
        reset:SetScript("OnClick", function() NS.ResetModule(key) end)
        right = 130
    end

    local t = UI.Text(h, title, 8, 1, 1, 1)
    t:SetPoint("TOPLEFT", h, "TOPLEFT", 18, -16)
    local d = UI.Text(h, desc or "", -1, 0.62, 0.62, 0.67)
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
    d:SetPoint("RIGHT", h, "RIGHT", -(right + 16), 0)
    d:SetJustifyV("TOP")
    d:SetWordWrap(true)
    if d.SetMaxLines then d:SetMaxLines(3) end

    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 18, 0)
    line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -18, 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.06)
    local under = h:CreateTexture(nil, "ARTWORK", nil, 1)   -- short accent underline below the title area
    under:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 18, 0)
    under:SetSize(36, 2)
    UI.Accent(under, 1)
    underlines[#underlines + 1] = under
    return h, sw
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
-- Theme presets. Picking one sets the window colors; any color can be changed afterwards.
-- Theme presets. Modern themes: { id, name, background, accent }. Classic themes use the
-- Blizzard-style window (stone or gold border, gold labels, checkboxes, red buttons) and also
-- pick a border and a background. Any color can be changed afterwards (it becomes Custom).
local THEMES = {
    { "blue",     "Modern: Aimbot Blue",  { 0.07, 0.07, 0.08 }, { 0.30, 0.70, 1.00 } },
    { "crimson",  "Modern: Crimson",      { 0.09, 0.06, 0.06 }, { 0.92, 0.27, 0.32 } },
    { "emerald",  "Modern: Emerald",      { 0.06, 0.085, 0.07 }, { 0.25, 0.85, 0.52 } },
    { "violet",   "Modern: Violet",       { 0.08, 0.06, 0.10 }, { 0.68, 0.42, 1.00 } },
    { "gold",     "Modern: Gold",         { 0.09, 0.08, 0.06 }, { 1.00, 0.78, 0.25 } },
    { "orange",   "Modern: Ember",        { 0.09, 0.07, 0.06 }, { 1.00, 0.52, 0.20 } },
    { "frost",    "Modern: Frost",        { 0.05, 0.07, 0.10 }, { 0.45, 0.88, 1.00 } },
    { "fel",      "Modern: Fel",          { 0.05, 0.07, 0.04 }, { 0.62, 1.00, 0.22 } },
    { "rose",     "Modern: Rose",         { 0.09, 0.06, 0.08 }, { 1.00, 0.45, 0.70 } },
    { "graphite", "Modern: Graphite",     { 0.12, 0.12, 0.13 }, { 0.78, 0.78, 0.84 } },
    { "black",    "Modern: Pure black",   { 0.00, 0.00, 0.00 }, { 0.30, 0.70, 1.00 } },
    { "midnight", "Modern: Midnight",     { 0.04, 0.05, 0.09 }, { 0.52, 0.56, 1.00 } },
    { "ocean",    "Modern: Ocean",        { 0.04, 0.08, 0.09 }, { 0.20, 0.82, 0.78 } },
    { "sand",     "Modern: Sand",         { 0.10, 0.09, 0.07 }, { 0.90, 0.72, 0.50 } },
    { "blood",    "Modern: Blood",        { 0.05, 0.02, 0.02 }, { 0.75, 0.08, 0.10 } },
    { "mono",     "Modern: Mono",         { 0.06, 0.06, 0.06 }, { 1.00, 1.00, 1.00 } },
    { "c_stone",  "Classic: Stone",       { 0, 0, 0 }, { 1.00, 0.82, 0.00 }, classic = true, border = "stone",   back = "dark" },
    { "c_gold",   "Classic: Gold trim",   { 0, 0, 0 }, { 1.00, 0.82, 0.00 }, classic = true, border = "gold",    back = "dark" },
    { "c_rock",   "Classic: Rock",        { 0, 0, 0 }, { 1.00, 0.82, 0.00 }, classic = true, border = "stone",   back = "rock" },
    { "c_marble", "Classic: Marble",      { 0, 0, 0 }, { 1.00, 0.82, 0.00 }, classic = true, border = "gold",    back = "marble" },
    { "c_tip",    "Classic: Tooltip",     { 0.03, 0.03, 0.05 }, { 1.00, 0.82, 0.00 }, classic = true, border = "tooltip", back = "plain" },
    { "c_horde",  "Classic: Horde",       { 0.10, 0.02, 0.02 }, { 1.00, 0.30, 0.20 }, classic = true, border = "stone", back = "plain" },
    { "c_ally",   "Classic: Alliance",    { 0.02, 0.04, 0.11 }, { 0.40, 0.65, 1.00 }, classic = true, border = "gold",  back = "plain" },
}


local function ApplyTheme(id)
    for _, t in ipairs(THEMES) do
        if t[1] == id then
            local w = W()
            local bg, ac = t[3], t[4]
            w.bg[1], w.bg[2], w.bg[3] = bg[1], bg[2], bg[3]
            w.border[1], w.border[2], w.border[3], w.border[4] = 0, 0, 0, 1
            w.accent[1], w.accent[2], w.accent[3] = ac[1], ac[2], ac[3]
            w.titleBar[1], w.titleBar[2], w.titleBar[3] = math.min(1, bg[1] + 0.05), math.min(1, bg[2] + 0.05), math.min(1, bg[3] + 0.05)
            w.sidebar[1], w.sidebar[2], w.sidebar[3], w.sidebar[4] = 0, 0, 0, 0.28
            w.text[1], w.text[2], w.text[3] = 0.90, 0.90, 0.92
            w.muted[1], w.muted[2], w.muted[3] = 0.62, 0.62, 0.67
            w.skin = t.classic and "classic" or "modern"
            if t.classic then
                -- gold labels, white titles, light grey notes, like the game's own option panels
                w.text[1], w.text[2], w.text[3] = 1.00, 0.82, 0.00
                w.muted[1], w.muted[2], w.muted[3] = 0.78, 0.78, 0.78
                w.titleBar[1], w.titleBar[2], w.titleBar[3] = 0, 0, 0
                w.sidebar[1], w.sidebar[2], w.sidebar[3], w.sidebar[4] = 0, 0, 0, 0.30
                w.classicBorder = t.border or "stone"
                w.classicBack = t.back or "dark"
            end
            w.theme = id
            return
        end
    end
end

local function BuildGeneral(page)
    local function Custom() W().theme = "custom"; UI.ApplyStyle() end
    local function ColorRow(label, key)
        page:Color(label,
            function() return W()[key] end,
            function(r, g, b) local c = W()[key]; c[1], c[2], c[3] = r, g, b; Custom() end)
    end

    page:Section("Theme", "Pick a ready-made look for this window")
    local options = { { "custom", "Custom" } }
    for _, t in ipairs(THEMES) do options[#options + 1] = { t[1], t[2] } end
    page:Cycle("Theme", options,
        function() return W().theme end,
        function(v) if v ~= "custom" then ApplyTheme(v) end; W().theme = v; UI.ApplyStyle() end)
    page:Cycle("Style", { { "classic", "Classic (game style)" }, { "modern", "Modern (flat)" } },
        function() return W().skin end,
        function(v) W().skin = v; UI.RefreshAll() end)
    local styleNote = page:Note("")
    table.insert(page.refreshers, function()
        if W().skin ~= UI.builtSkin then
            styleNote:SetText("|cffff8040The style changes after a reload.|r Click \"Reload now\" below (or type /reload).")
        else
            styleNote:SetText("Classic themes use the game's own look: stone or gold border, gold labels, checkboxes "
                .. "and red buttons. Modern themes are flat with round switches. Changing any color below makes it Custom.")
        end
    end)
    page:Cycle("Classic border", { { "stone", "Stone" }, { "gold", "Gold trim" }, { "tooltip", "Thin (tooltip)" }, { "none", "None" } },
        function() return W().classicBorder or "stone" end,
        function(v) W().classicBorder = v; UI.ApplyStyle() end)
    page:Cycle("Classic background", { { "dark", "Dark" }, { "rock", "Rock" }, { "marble", "Marble" }, { "plain", "Plain color" } },
        function() return W().classicBack or "dark" end,
        function(v) W().classicBack = v; UI.ApplyStyle() end)
    page:Button("Reload now", function() if ReloadUI then ReloadUI() end end, 160)

    page:Section("Look", "Font, outline, border and title bar details")
    local fontOpts = {}
    for _, f in ipairs(UI.FONTS) do fontOpts[#fontOpts + 1] = { f[1], f[2] } end
    page:Cycle("Font", fontOpts,
        function() return W().font or "default" end,
        function(v) W().font = v; UI.ApplyStyle() end)
    page:Cycle("Text outline", { { "none", "None" }, { "OUTLINE", "Thin" }, { "THICKOUTLINE", "Thick" } },
        function() return W().fontOutline or "none" end,
        function(v) W().fontOutline = v; UI.ApplyStyle() end)
    page:Check("Text shadow", function() return W().textShadow end,
        function(v) W().textShadow = v; UI.ApplyStyle() end)
    page:Slider("Border thickness (modern style)", 1, 4, 1,
        function() return W().borderSize or 1 end,
        function(v) W().borderSize = v; UI.ApplyStyle() end)
    page:Check("Show the version number in the title bar", function() return W().showVersion ~= false end,
        function(v) W().showVersion = v; UI.ApplyStyle() end)
    page:Check("Show the coloured mark before the title", function() return W().titleMark ~= false end,
        function(v) W().titleMark = v; UI.ApplyStyle() end)
    page:Check("Show the coloured line under the title bar", function() return W().titleLine ~= false end,
        function(v) W().titleLine = v; UI.ApplyStyle() end)
    page:Check("Show the coloured underline under each tab title", function() return W().underlines ~= false end,
        function(v) W().underlines = v; UI.ApplyStyle() end)

    page:Section("Window", "Size, opacity, text size and locking")
    page:Check("Show an \"Aimbot UI\" button on the Escape menu", function() return W().menuButton ~= false end,
        function(v) W().menuButton = v; UI.UpdateMenuButton() end)
    page:Slider("Window scale", 0.6, 1.6, 0.05,
        function() return W().scale end,
        function(v) W().scale = v; UI.ApplyStyle() end,
        function(v) return string.format("%.2f", v) end)
    page:Slider("Window opacity", 0.3, 1, 0.02,
        function() return W().bg[4] end,
        function(v) W().bg[4] = v; UI.ApplyStyle() end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
    page:Slider("Side menu opacity", 0, 1, 0.02,
        function() return W().sidebar[4] end,
        function(v) W().sidebar[4] = v; UI.ApplyStyle() end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
    page:Slider("Text size", 9, 18, 1,
        function() return W().fontSize end,
        function(v) W().fontSize = v; UI.ApplyStyle() end)
    page:Check("Lock window position and size",
        function() return W().locked end,
        function(v) W().locked = v; UI.ApplyStyle() end)
    page:Button("Reset window position and size", function()
        W().point = nil
        W().w, W().h = NS.WINDOW_DEFAULTS.w, NS.WINDOW_DEFAULTS.h
        win:ClearAllPoints()
        win:SetPoint("CENTER")
        win:SetSize(W().w, W().h)
    end, 260)

    page:Section("Colors", "Background, border, highlight and text colors")
    ColorRow("Window background", "bg")
    ColorRow("Title bar", "titleBar")
    ColorRow("Side menu", "sidebar")
    page:Color("Border",
        function() return W().border end,
        function(r, g, b) W().border[1], W().border[2], W().border[3] = r, g, b; Custom() end)
    page:Color("Highlight color (switches, sliders, selection)",
        function() return W().accent end,
        function(r, g, b) W().accent[1], W().accent[2], W().accent[3] = r, g, b; Custom() end)
    ColorRow("Text", "text")
    ColorRow("Small grey text (descriptions, notes)", "muted")
    page:Slider("Highlight strength", 0.2, 1, 0.05,
        function() return W().accent[4] or 1 end,
        function(v) W().accent[4] = v; UI.ApplyStyle() end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
    page:Check("Use my own title colour", function() return W().titleColorOn end,
        function(v) W().titleColorOn = v; UI.ApplyStyle() end)
    page:Color("Title colour (\"AIMBOT UI\")",
        function() return W().titleColor end,
        function(r, g, b) local c = W().titleColor; c[1], c[2], c[3] = r, g, b; W().titleColorOn = true; UI.ApplyStyle() end)
    page:Button("Reset all window colors", function()
        local cur = W().theme
        if cur == "custom" or not cur then cur = UI.classic and "c_stone" or "blue" end
        ApplyTheme(cur); UI.ApplyStyle()
    end, 260)

    page:Section("Modules", "Switch whole modules on or off")
    for _, key in ipairs(SortedModules()) do
        local m = NS.modules[key]
        page:Check(m.name or key,
            function() return NS.Mod(key).enabled end,
            function(v) NS.Mod(key).enabled = v; NS.ApplyModule(key) end)
    end

    page:Section("Maintenance", "Reset everything or print diagnostics")
    StaticPopupDialogs["AIMBOTUI_RESET_ALL"] = {
        text = "Reset ALL Aimbot UI settings to defaults?",
        button1 = YES, button2 = NO,
        OnAccept = function() NS.ResetAll() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    page:Button("Reset ALL settings to default", function()
        StaticPopup_Show("AIMBOTUI_RESET_ALL")
    end, 260)
    page:Button("Run diagnostics (opens a copy window)", function()
        if NS.Diagnose then NS.Diagnose() end
    end, 260)

    page:Section("Help", "Commands, controls and credits")
    page:Note("Drag the title bar to move the window and the bottom-right corner to resize it. "
        .. "Each tab opens a list of areas: click one to see its options, then click \"All areas\" (or the tab name again) to go back. "
        .. "Every tab has its own Enabled switch and a Reset tab button.")
    page:Note("Commands:  /aimbot  opens the window.   /aimbot <tab>  opens a tab.   "
        .. "/aimbot <tab> on|off  toggles a module.   /sparkle  toggles Button Flash.   "
        .. "Tabs: lorti, damage, flash, mana, range, trainer, double, memory, mute, fps, privacy, dr, queue, plates, combat, kick, death, repair, talent, timers, loc, autoshot.")
    page:Note("Credits: Lorti UI Classic by Lorti, Chordsy, Macumba, Knall, Jozh, Xyz, Arrone and Redskin. "
        .. "NiceDamage by Montyburns. Their artwork and fonts are used here with the original credit.")
end


local function Create()
    local w = W()
    -- One time: switch to the classic (game-style) look introduced in 2.8.13.
    if w.styleV ~= 1 then
        w.styleV = 1
        ApplyTheme("c_stone")
    end
    UI.classic = (w.skin == "classic")
    UI.builtSkin = w.skin
    win = CreateFrame("Frame", "AimbotUIWindow", UIParent)
    win:SetFrameStrata("MEDIUM")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:SetResizable(true)
    if win.SetResizeBounds then
        win:SetResizeBounds(620, 400, 1200, 960)
    elseif win.SetMinResize then
        win:SetMinResize(620, 400)
    end
    win:SetSize(w.w, w.h)
    if w.point then
        win:SetPoint(w.point[1], UIParent, w.point[2], w.point[3], w.point[4])
    else
        win:SetPoint("CENTER")
    end
    table.insert(UISpecialFrames, "AimbotUIWindow")

    bgTex = win:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()

    -- Classic style: a Blizzard dialog border and background around the window.
    if UI.classic then
        local deco = BackdropFrame("Frame", win)
        deco:SetFrameLevel(win:GetFrameLevel())
        UI._deco = deco
    end

    local function Edge(p1, p2, width, height)
        local t = win:CreateTexture(nil, "BORDER")
        t:SetPoint(p1); t:SetPoint(p2)
        if width then t:SetWidth(width); edgeVertical[t] = true end
        if height then t:SetHeight(height) end
        table.insert(borderEdges, t)
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 1)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

    -- Soft drop shadow: three faint rings just outside the window edge (modern style).
    for i, a in ipairs(UI.classic and {} or { 0.30, 0.16, 0.07 }) do
        local o, prev = i * 2, (i - 1) * 2
        local function S(p1, x1, y1, p2, x2, y2)
            local t = win:CreateTexture(nil, "BACKGROUND", nil, -8)
            t:SetColorTexture(0, 0, 0, a)
            t:SetPoint(p1, win, p1, x1, y1)
            t:SetPoint(p2, win, p2, x2, y2)
        end
        S("TOPLEFT", -o, o, "TOPRIGHT", o, prev)              -- top band
        S("BOTTOMLEFT", -o, -prev, "BOTTOMRIGHT", o, -o)       -- bottom band
        S("TOPLEFT", -o, prev, "BOTTOMLEFT", -prev, -prev)     -- left band
        S("TOPRIGHT", prev, prev, "BOTTOMRIGHT", o, -prev)     -- right band
    end

    -- Title bar
    local tb = CreateFrame("Frame", nil, win)
    tb:SetPoint("TOPLEFT", 1, -1)
    tb:SetPoint("TOPRIGHT", -1, -1)
    tb:SetHeight(34)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    titleBG = tb:CreateTexture(nil, "BACKGROUND")
    titleBG:SetAllPoints()
    titleBar = tb
    tb:SetScript("OnDragStart", function() if not W().locked then win:StartMoving() end end)
    tb:SetScript("OnDragStop", function() win:StopMovingOrSizing(); SavePosition() end)

    local mark = tb:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("LEFT", 12, 0)
    mark:SetSize(4, 16)
    UI.Accent(mark, 1)
    local title = UI.Text(tb, "AIMBOT UI", 3, 1, 1, 1)
    if UI.classic then title:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    title:SetPoint("LEFT", mark, "RIGHT", 8, 0)
    -- the version: plain small text in the notes colour, no box behind it
    local ver = UI.Text(tb, "v" .. NS.version, -3, 0.62, 0.62, 0.67)
    ver:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
    UI._title, UI._ver, UI._mark = title, ver, mark

    local close = CreateFrame("Button", nil, tb)
    close:SetSize(28, 24)
    close:SetPoint("RIGHT", -5, 0)
    local closeHL = close:CreateTexture(nil, "HIGHLIGHT")
    closeHL:SetAllPoints()
    closeHL:SetColorTexture(0.85, 0.22, 0.25, 0.85)
    local closeX = UI.Text(close, "X", 0, 0.70, 0.70, 0.75)
    closeX:SetPoint("CENTER", 0, 0)
    close:SetScript("OnEnter", function() closeX:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function() closeX:SetTextColor(0.70, 0.70, 0.75) end)
    close:SetScript("OnClick", function() win:Hide() end)

    local tline = tb:CreateTexture(nil, "ARTWORK")
    tline:SetPoint("BOTTOMLEFT", tb, "BOTTOMLEFT", 0, 0)
    tline:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", 0, 0)
    tline:SetHeight(1)
    UI.Accent(tline, 0.55)
    UI._tline = tline

    -- Sidebar
    sidebar = CreateFrame("Frame", nil, win)
    sidebar:SetPoint("TOPLEFT", 1, -35)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR_W)
    sideBG = sidebar:CreateTexture(nil, "BACKGROUND")
    sideBG:SetAllPoints()
    local sline = sidebar:CreateTexture(nil, "ARTWORK")
    sline:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sline:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sline:SetWidth(1)
    sline:SetColorTexture(1, 1, 1, 0.06)

    -- The side menu scrolls, because an open dropdown can be taller than the window.
    local sideScroll = CreateFrame("ScrollFrame", nil, sidebar)
    sideScroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -40)
    sideScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, 0)
    local sideChild = CreateFrame("Frame", nil, sideScroll)
    sideChild:SetSize(SIDEBAR_W - 1, 10)
    sideScroll:SetScrollChild(sideChild)
    sideScroll:EnableMouseWheel(true)
    sideScroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
    end)

    ----------------------------------------------------------------
    -- Search box: finds any setting by name, in every tab
    ----------------------------------------------------------------
    local resultsChild = CreateFrame("Frame", nil, sideScroll)
    resultsChild:SetSize(SIDEBAR_W - 1, 10)
    resultsChild:Hide()
    local resultButtons, searchBox, searchResults = {}, nil, {}
    local RESULT_H = 40
    local flash, flashTex, flashToken = nil, nil, 0

    local sHolder = CreateFrame("Frame", nil, sidebar)
    sHolder:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, -8)
    sHolder:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -9, -8)
    sHolder:SetHeight(26)
    local sEdge = sHolder:CreateTexture(nil, "BACKGROUND")
    sEdge:SetAllPoints()
    sEdge:SetColorTexture(1, 1, 1, 0.10)
    local sFill = sHolder:CreateTexture(nil, "BORDER")
    sFill:SetPoint("TOPLEFT", 1, -1)
    sFill:SetPoint("BOTTOMRIGHT", -1, 1)
    sFill:SetColorTexture(0.05, 0.05, 0.06, 1)
    searchBox = CreateFrame("EditBox", nil, sHolder)
    searchBox:SetPoint("TOPLEFT", sHolder, "TOPLEFT", 8, -2)
    searchBox:SetPoint("BOTTOMRIGHT", sHolder, "BOTTOMRIGHT", -24, 2)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    SetFontSafe(searchBox, W().fontSize)
    texts[searchBox] = 0
    roles[searchBox] = "body"
    searchBox:SetTextColor(W().text[1], W().text[2], W().text[3])
    local sHint = UI.Text(sHolder, "Search settings...", -1, 0.62, 0.62, 0.67)
    sHint:SetPoint("LEFT", sHolder, "LEFT", 9, 0)
    sHint:SetPoint("RIGHT", sHolder, "RIGHT", -24, 0)
    sHint:SetWordWrap(false)
    local sClear = CreateFrame("Button", nil, sHolder)
    sClear:SetSize(20, 22)
    sClear:SetPoint("RIGHT", sHolder, "RIGHT", -2, 0)
    local sx = UI.Text(sClear, "x", 1, 0.62, 0.62, 0.67)
    sx:SetPoint("CENTER")
    sClear:Hide()

    local function QueryText()
        local q = searchBox:GetText()
        if type(q) ~= "string" then return "" end
        return (q:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function LeaveSearch()
        resultsChild:Hide()
        sideChild:Show()
        sideScroll:SetScrollChild(sideChild)
        UI.LayoutSidebar(true)
    end

    -- Finds settings. Every word typed must appear in the setting's name, its area or its tab.
    function UI.Search(query)
        local words = {}
        for w in tostring(query or ""):lower():gmatch("%S+") do words[#words + 1] = w end
        local found = {}
        if #words == 0 then return found end
        local function hit(hay)
            for _, w in ipairs(words) do
                if not hay:find(w, 1, true) then return false end
            end
            return true
        end
        local phrase = table.concat(words, " ")
        local function closeness(text)       -- 0 exact, 1 starts with it, 2 contains it, 3 only the words
            local l = text:lower()
            if l == phrase then return 0 end
            local at = l:find(phrase, 1, true)
            if at == 1 then return 1 end
            return at and 2 or 3
        end
        local function anyIn(hay)
            for _, w in ipairs(words) do
                if hay:find(w, 1, true) then return true end
            end
            return false
        end
        for order, t in ipairs(tabList) do
            local tabName = t.label or t.key
            if hit(tabName:lower()) then
                found[#found + 1] = { text = tabName, where = "Tab", t = t, rank = 0, order = order, close = closeness(tabName) }
            end
            for _, card in ipairs(t.page.cards) do
                local area = card.title
                local base = (tabName .. " " .. (area or "")):lower()
                if area and hit(base) then
                    found[#found + 1] = { text = area, where = tabName, t = t, card = card, rank = 3, order = order, area = true, close = closeness(area) }
                end
                for _, row in ipairs(card.rows) do
                    local label = row.label and row.label:lower()
                    local where = tabName .. (area and (" > " .. area) or "")
                    if label and anyIn(label) and hit(label .. " " .. base) then
                        found[#found + 1] = { text = row.label, where = where, t = t, card = card, row = row,
                            rank = hit(label) and 1 or 2, order = order, close = closeness(row.label) }
                    elseif row.note and hit(row.note:lower()) then
                        found[#found + 1] = { text = (row.note:gsub("%s+", " ")), where = where,
                            t = t, card = card, row = row, rank = 4, order = order, note = true, close = 3 }
                    end
                end
            end
        end
        table.sort(found, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            if a.close ~= b.close then return a.close < b.close end
            if #a.text ~= #b.text then return #a.text < #b.text end
            return a.order < b.order
        end)
        while #found > 40 do found[#found] = nil end
        return found
    end

    -- Brief glow on the setting you jumped to, and scroll it into view.
    local function Reveal(row)
        if not row or not row.frame then return end
        if not flash then
            flash = CreateFrame("Frame", nil, UIParent)
            flashTex = flash:CreateTexture(nil, "OVERLAY")
            flashTex:SetAllPoints()
            flash:EnableMouse(false)
            flash:Hide()
        end
        flash:SetParent(row.frame)
        flash:ClearAllPoints()
        flash:SetPoint("TOPLEFT", row.frame, "TOPLEFT", -6, 2)
        flash:SetPoint("BOTTOMRIGHT", row.frame, "BOTTOMRIGHT", 6, -2)
        local c = W().accent
        flashTex:SetColorTexture(c[1], c[2], c[3], 0.30)
        flash:Show()
        flashToken = flashToken + 1
        local mine = flashToken
        C_Timer.After(1.8, function() if flashToken == mine then flash:Hide() end end)
    end

    local function ScrollTo(page, row)
        local ok = pcall(function()
            local top, ctop = row.frame:GetTop(), page.child:GetTop()
            if type(top) == "number" and type(ctop) == "number" then
                local range = page.frame:GetVerticalScrollRange() or 0
                page.frame:SetVerticalScroll(math.max(0, math.min(range, ctop - top - 40)))
            end
        end)
        return ok
    end

    local function GoTo(r)
        if currentTab ~= r.t.key then SelectTab(r.t.key) end
        local page = r.t.page
        if page.menuMode and r.card and not r.card.pinned then page:Open(r.card) end
        searchBox:SetText("")
        searchBox:ClearFocus()
        LeaveSearch()
        if r.row then
            Reveal(r.row)
            C_Timer.After(0, function() ScrollTo(page, r.row) end)
        end
    end

    local function ShowResults(list)
        searchResults = list
        sideChild:Hide()
        resultsChild:Show()
        sideScroll:SetScrollChild(resultsChild)
        sideScroll:SetVerticalScroll(0)
        for i, r in ipairs(list) do
            local b = resultButtons[i]
            if not b then
                b = CreateFrame("Button", nil, resultsChild)
                b:SetHeight(RESULT_H)
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.06)
                local ln = b:CreateTexture(nil, "BORDER")
                ln:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 10, 0)
                ln:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 0)
                ln:SetHeight(1)
                ln:SetColorTexture(1, 1, 1, 0.06)
                b.main = UI.Text(b, "", 0)
                b.main:SetPoint("TOPLEFT", b, "TOPLEFT", 12, -5)
                b.main:SetPoint("RIGHT", b, "RIGHT", -8, 0)
                b.main:SetWordWrap(false)
                b.sub = UI.Text(b, "", -2, 0.62, 0.62, 0.67)
                b.sub:SetPoint("TOPLEFT", b.main, "BOTTOMLEFT", 0, -3)
                b.sub:SetPoint("RIGHT", b, "RIGHT", -8, 0)
                b.sub:SetWordWrap(false)
                resultButtons[i] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", resultsChild, "TOPLEFT", 0, -4 - (i - 1) * RESULT_H)
            b:SetPoint("TOPRIGHT", resultsChild, "TOPRIGHT", -2, -4 - (i - 1) * RESULT_H)
            b.main:SetText(r.text)
            b.sub:SetText(r.where)
            b:SetScript("OnClick", function() GoTo(r) end)
            b:Show()
        end
        for i = #list + 1, #resultButtons do resultButtons[i]:Hide() end
        if not resultButtons.none then
            resultButtons.none = UI.Text(resultsChild, "Nothing matches that.", -1, 0.62, 0.62, 0.67)
            resultButtons.none:SetPoint("TOPLEFT", resultsChild, "TOPLEFT", 14, -12)
        end
        resultButtons.none:SetShown(#list == 0)
        resultsChild:SetHeight(math.max(30, #list * RESULT_H + 12))
    end

    local function Refresh()
        local q = QueryText()
        sHint:SetShown(q == "" and not searchBox:HasFocus())
        sClear:SetShown(q ~= "")
        if q == "" then
            if resultsChild:IsShown() then LeaveSearch() end
        else
            ShowResults(UI.Search(q))
        end
    end
    searchBox:SetScript("OnTextChanged", Refresh)
    searchBox:SetScript("OnEditFocusGained", function()
        local a = W().accent
        sEdge:SetColorTexture(a[1], a[2], a[3], 1)
        Refresh()
    end)
    searchBox:SetScript("OnEditFocusLost", function()
        sEdge:SetColorTexture(1, 1, 1, 0.10)
        Refresh()
    end)
    searchBox:SetScript("OnEnterPressed", function()
        if searchResults[1] and QueryText() ~= "" then GoTo(searchResults[1]) else searchBox:ClearFocus() end
    end)
    searchBox:SetScript("OnEscapePressed", function()
        if QueryText() ~= "" then searchBox:SetText("") else searchBox:ClearFocus() end
    end)
    sClear:SetScript("OnClick", function() searchBox:SetText(""); searchBox:ClearFocus() end)
    UI._searchBox = searchBox

    content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, 20)

    -- Resize grip + footer
    grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    for i, size in ipairs({ 12, 8, 4 }) do
        local g = grip:CreateTexture(nil, "OVERLAY")
        g:SetPoint("BOTTOMRIGHT", 0, (i - 1) * 5)
        g:SetSize(size, 3)
        UI.Accent(g, 0.7)
    end
    grip:SetScript("OnMouseDown", function() if not W().locked then win:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing(); SaveSize(); SavePosition() end)

    local foot = UI.Text(win, "Type /aimbot to open or close", -2, 0.40, 0.40, 0.45)
    foot:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 14, 5)

    -- Tabs ----------------------------------------------------------
    local lastGroup2
    local sideEntries = {}        -- { group = fontstring } or { tab = t }
    local SUB_H = 26

    -- Places every group label, tab and (for the open tab) its dropdown rows.
    function UI.LayoutSidebar(resetScroll)
        local y = -10
        for _, e in ipairs(sideEntries) do
            if e.group then
                y = y - 14
                e.group:ClearAllPoints()
                e.group:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 14, y)
                if e.line then
                    e.line:ClearAllPoints()
                    e.line:SetPoint("LEFT", e.group, "RIGHT", 8, 0)
                    e.line:SetPoint("RIGHT", sideChild, "RIGHT", -12, 0)
                end
                y = y - 20
            else
                local t = e.tab
                t.btn:ClearAllPoints()
                t.btn:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 6, y)
                t.btn:SetPoint("TOPRIGHT", sideChild, "TOPRIGHT", -7, y)
                y = y - 30
                if t.arrow then t.arrow:SetText(t.expanded and "-" or "+") end
                for i, sub in ipairs(t.subs or {}) do
                    if t.expanded then
                        sub.btn:ClearAllPoints()
                        sub.btn:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 20, y)
                        sub.btn:SetPoint("TOPRIGHT", sideChild, "TOPRIGHT", -7, y)
                        sub.btn:Show()
                        local on = currentTab == t.key and t.page.view == sub.card
                        sub.sel:SetShown(on)
                        sub.bar:SetShown(on)
                        y = y - SUB_H
                    else
                        sub.btn:Hide()
                    end
                end
                if t.expanded and t.subs and #t.subs > 0 then y = y - 4 end
            end
        end
        sideChild:SetHeight(-y + 10)
        if resetScroll then sideScroll:SetVerticalScroll(0) end
    end

    local function NewTab(key, label, buildFn, mod)
        if mod and mod.group and mod.group ~= lastGroup2 then
            lastGroup2 = mod.group
            local g = UI.Text(sideChild, GROUP_LABEL[mod.group] or string.upper(mod.group), -2, 0.50, 0.50, 0.56)
            local line = sideChild:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetColorTexture(1, 1, 1, 0.07)
            sideEntries[#sideEntries + 1] = { group = g, line = line }
        end

        local btn = CreateFrame("Button", nil, sideChild)
        btn:SetHeight(28)

        local sel = btn:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        UI.Accent(sel, 0.13)
        sel:Hide()
        local selBar = btn:CreateTexture(nil, "ARTWORK")
        selBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -6)
        selBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 6)
        selBar:SetWidth(3)
        UI.Accent(selBar, 1)
        selBar:Hide()
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)

        local dot
        -- A "(...)" note at the end of a name is drawn smaller and grey so long names fit
        local main, note = label:match("^(.-)%s*(%b())$")
        if not main or main == "" then main, note = label, nil end
        local fs = UI.Text(btn, main)
        fs:SetWordWrap(false)
        local noteFs
        if note then
            noteFs = UI.Text(btn, note, -3, 0.62, 0.62, 0.67)
            noteFs:SetPoint("LEFT", fs, "RIGHT", 4, 0)
            noteFs:SetWordWrap(false)
        end
        local function LabelRight(anchor, rel, x)
            if noteFs then noteFs:SetPoint("RIGHT", anchor, rel, x, 0)
            else fs:SetPoint("RIGHT", anchor, rel, x, 0) end
        end
        if mod then
            dot = UI.Round(btn, "ARTWORK", 7)
            dot:SetPoint("LEFT", btn, "LEFT", 12, 0)
            fs:SetPoint("LEFT", dot, "RIGHT", 9, 0)
        else
            fs:SetPoint("LEFT", btn, "LEFT", 14, 0)
        end
        local arrow = UI.Text(btn, "+", 1, 0.50, 0.50, 0.56)
        arrow:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
        LabelRight(arrow, "LEFT", -6)
        btn:SetScript("OnClick", function()
            local t = tabs[key]
            if currentTab == key and t and t.page.menuMode then
                -- already here: the + / - opens and closes its dropdown
                t.expanded = not t.expanded
                UI.LayoutSidebar(true)
            else
                SelectTab(key)
            end
        end)

        local header, sw = BuildHeader(content, label, mod and mod.desc or "Window look, module switches and maintenance.",
            mod and key or nil)
        local holder = CreateFrame("Frame", nil, content)
        holder:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -HEADER_H - 6)
        holder:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -2, 4)
        local page = UI.NewPage(holder)
        local ok, err = pcall(buildFn, page)
        if not ok then NS.ReportError("tab " .. label, err) end
        local ok2, err2 = pcall(page.Finish, page)
        if not ok2 then NS.ReportError("tab " .. label .. " menu", err2) end
        page:Reflow()

        local t = { key = key, label = label, btn = btn, page = page, sel = sel, selBar = selBar,
            header = header, switch = sw, dot = dot, module = mod and true or false }
        tabs[key] = t
        table.insert(tabList, t)
        sideEntries[#sideEntries + 1] = { tab = t }

        -- the dropdown: one row per area of this tab
        if page.menuMode and page.areas then
            arrow:Show()
            t.arrow = arrow
            t.subs = {}
            for _, card in ipairs(page.areas) do
                local sb = CreateFrame("Button", nil, sideChild)
                sb:SetHeight(SUB_H)
                sb:Hide()
                local guide = sb:CreateTexture(nil, "BORDER")        -- thin vertical guide line, joins up between rows
                guide:SetPoint("TOPLEFT", sb, "TOPLEFT", 4, 0)
                guide:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 4, 0)
                guide:SetWidth(1)
                guide:SetColorTexture(1, 1, 1, 0.10)
                local ssel = sb:CreateTexture(nil, "BACKGROUND")
                ssel:SetPoint("TOPLEFT", sb, "TOPLEFT", 4, 0)
                ssel:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
                UI.Accent(ssel, 0.22)
                ssel:Hide()
                local sbar = sb:CreateTexture(nil, "ARTWORK")
                sbar:SetPoint("TOPLEFT", sb, "TOPLEFT", 3, 0)
                sbar:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 3, 0)
                sbar:SetWidth(2)
                UI.Accent(sbar, 1)
                sbar:Hide()
                local shl = sb:CreateTexture(nil, "HIGHLIGHT")
                shl:SetPoint("TOPLEFT", sb, "TOPLEFT", 4, 0)
                shl:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
                shl:SetColorTexture(1, 1, 1, 0.06)
                local sfs = UI.Text(sb, (card.title:gsub("%s*%b()", "")), -1, 0.80, 0.80, 0.85)   -- side label drops "(...)" notes
                sfs:SetPoint("LEFT", sb, "LEFT", 16, 0)
                sfs:SetPoint("RIGHT", sb, "RIGHT", -6, 0)
                sfs:SetWordWrap(false)
                sb:SetScript("OnClick", function()
                    if currentTab ~= key then SelectTab(key) end
                    t.expanded = true
                    t.page:Open(card)
                end)
                t.subs[#t.subs + 1] = { btn = sb, sel = ssel, bar = sbar, card = card }
            end
        else
            arrow:Hide()
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", btn, "LEFT", dot and 28 or 14, 0)
            if noteFs then noteFs:ClearAllPoints(); noteFs:SetPoint("LEFT", fs, "RIGHT", 4, 0) end
            LabelRight(btn, "RIGHT", -6)
        end
    end

    NewTab("general", "General", BuildGeneral, nil)
    for _, key in ipairs(SortedModules()) do
        local m = NS.modules[key]
        NewTab(key, m.name or key, function(page)
            if m.Build then m.Build(page) end
        end, m)
    end

    UI.ApplyStyle()
    SelectTab("general")
    win:Hide()
end

function UI.Show(tabKey)
    if not win then Create() end
    win:Show()
    UI.RefreshAll()
    if tabKey and tabs[tabKey] then SelectTab(tabKey) end
end

function UI.Toggle(tabKey)
    if not win then Create() end
    if win:IsShown() and (not tabKey or currentTab == tabKey) then
        win:Hide()
    else
        UI.Show(tabKey)
    end
end

function UI.GetPage(key)
    return tabs[key] and tabs[key].page or nil
end

UI._tabs = tabs

function UI.HasTab(key)
    return key == "general" or NS.modules[key] ~= nil
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
local ALIASES = {
    lorti = "lorti", skin = "lorti", ui = "lorti", style = "lorti",
    damage = "damage", font = "damage", fonts = "damage", nicedamage = "damage",
    sparkle = "sparkle", flash = "sparkle", buttonflash = "sparkle",
    mana = "manacost", cost = "manacost", costs = "manacost", manacost = "manacost",
    range = "range",
    train = "trainer", training = "trainer", trainer = "trainer",
    double = "doublepress", doublepress = "doublepress", dp = "doublepress", ahk = "doublepress",
    qol = "doublepress", autohotkey = "doublepress",
    memory = "memory", mem = "memory", cache = "memory", leak = "memory", leaks = "memory",
    mute = "mute", chat = "mute", chatmute = "mute", silence = "mute", ignore = "mute",
    fps = "fps", ms = "fps", latency = "fps", ping = "fps", counter = "fps",
    privacy = "privacy", stream = "privacy", streamer = "privacy", incognito = "privacy", private = "privacy",
    diminish = "diminish", dr = "diminish", drs = "diminish", diminishing = "diminish",
    queue = "queuetimer", queuetimer = "queuetimer", pop = "queuetimer",
    plates = "plateicons", icons = "plateicons", plateicons = "plateicons", healer = "plateicons", racial = "plateicons",
    combat = "combatind", combatind = "combatind", incombat = "combatind",
    kick = "interrupt", interrupt = "interrupt", interrupts = "interrupt",
    death = "deathalert", deaths = "deathalert", died = "deathalert", deathalert = "deathalert",
    repair = "durability", dura = "durability", durability = "durability",
    timers = "auratimers", auratimers = "auratimers", dots = "auratimers", auras = "auratimers", duration = "auratimers",
    talent = "talentalert", talents = "talentalert", points = "talentalert", talentalert = "talentalert",
    autoshot = "autoshot", ast = "autoshot", shot = "autoshot", hunter = "autoshot", swing = "autoshot",
    loc = "lossofcontrol", lossofcontrol = "lossofcontrol", control = "lossofcontrol", stun = "lossofcontrol",
    stuns = "lossofcontrol", ccme = "lossofcontrol", losecontrol = "lossofcontrol",
    general = "general", window = "general",
}

----------------------------------------------------------------------
-- Escape menu button
-- Our own button, shown just above the game's Escape menu while it is open. Nothing is added to the
-- game's own menu or its button list (that list also holds Log Out / Exit Game, and changing it
-- from an addon can get those blocked). Clicking closes the menu and opens the settings window.
----------------------------------------------------------------------
local menuButton
function UI.UpdateMenuButton()
    if not menuButton then return end
    local gm = _G.GameMenuFrame
    local want = NS.db and W().menuButton ~= false
    local shown = false
    if gm then
        local ok, v = pcall(gm.IsShown, gm)
        shown = ok and not NS.IsSecret(v) and v == true
    end
    menuButton:SetShown(want and shown and true or false)
end

function UI.SetupMenuButton()
    local gm = _G.GameMenuFrame
    if menuButton or not gm then return end
    local ok, b = pcall(CreateFrame, "Button", "AimbotUIGameMenuButton", UIParent, "UIPanelButtonTemplate")
    if not ok or not b then ok, b = pcall(CreateFrame, "Button", "AimbotUIGameMenuButton", UIParent) end
    if not ok or not b then return end
    menuButton = b
    b:SetSize(160, 28)
    b:SetFrameStrata("DIALOG")
    -- above the menu, clear of its "Game Menu" title, which sticks out over the top edge
    b:SetPoint("BOTTOM", gm, "TOP", 0, 24)
    b:SetText("Aimbot UI")
    local fs = b.GetFontString and b:GetFontString()
    if fs then pcall(fs.SetTextColor, fs, 0.30, 0.72, 1.00) end
    b:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            -- the Escape menu can't be closed for you in combat; open the window on top of it
            UI.Show()
            return
        end
        pcall(HideUIPanel, gm)
        UI.Show()
    end)
    b:Hide()
    pcall(gm.HookScript, gm, "OnShow", function() pcall(UI.UpdateMenuButton) end)
    pcall(gm.HookScript, gm, "OnHide", function() if menuButton then menuButton:Hide() end end)
    UI.UpdateMenuButton()
end
UI._menuButton = function() return menuButton end

SLASH_AIMBOTUI1 = "/aimbot"
SLASH_AIMBOTUI2 = "/aui"
SlashCmdList["AIMBOTUI"] = function(msg)
    if not NS.db then return end
    msg = (msg or ""):lower()
    local a, b = msg:match("^%s*(%S*)%s*(%S*)")
    if a == "" then UI.Toggle(); return end
    if a == "diag" or a == "diagnostics" or a == "check" then
        if NS.Diagnose then NS.Diagnose() end
        return
    end
    if a == "clean" or a == "clear" then
        local mm = NS.modules.memory
        if mm and mm.CleanNow then mm:CleanNow(true) else NS.Print("Memory Cleaner is not loaded.") end
        return
    end
    local key = ALIASES[a] or a
    if not UI.HasTab(key) then
        NS.Print("unknown tab '" .. a .. "'. Try: general, lorti, damage, flash, mana, range, trainer, double, memory, mute, fps, privacy, dr, queue, plates, combat, kick, death, repair, talent, timers, loc, autoshot  (or /aimbot clean)")
        return
    end
    if (b == "on" or b == "off") and NS.modules[key] then
        NS.Mod(key).enabled = (b == "on")
        NS.ApplyModule(key)
        UI.RefreshAll()
        NS.Print(NS.modules[key].name .. " " .. (b == "on" and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
    else
        UI.Toggle(key)
    end
end

SLASH_AIMBOTSPARKLE1 = "/sparkle"
SlashCmdList["AIMBOTSPARKLE"] = function(msg)
    if not NS.db then return end
    local m = NS.Mod("sparkle")
    msg = (msg or ""):lower():match("^%s*(%S*)")
    if msg == "on" then m.enabled = true
    elseif msg == "off" then m.enabled = false
    elseif msg == "test" then
        if NS.modules.sparkle and NS.modules.sparkle.Test then NS.modules.sparkle:Test() end
        return
    else m.enabled = not m.enabled end
    NS.ApplyModule("sparkle")
    if win then UI.RefreshAll() end
    NS.Print("Button Flash " .. (m.enabled and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
end

-- A small window with all the text selected, so it can be copied (Ctrl+C) and pasted anywhere.
function UI.ShowText(title, text)
    local f = UI._textWin
    if not f then
        f = CreateFrame("Frame", "AimbotUITextWindow", UIParent, "BackdropTemplate")
        f:SetSize(620, 380)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            f:SetBackdropColor(0.06, 0.06, 0.07, 0.97)
            f:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
        end
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOPLEFT", 12, -10)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("BOTTOMLEFT", 12, 10)
        hint:SetText("Click the text, press Ctrl+A then Ctrl+C to copy it.")
        local scroll = CreateFrame("ScrollFrame", "AimbotUITextWindowScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -34)
        scroll:SetPoint("BOTTOMRIGHT", -30, 32)
        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal or GameFontHighlight)
        eb:SetWidth(560)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        scroll:SetScrollChild(eb)
        f.edit = eb
        if UISpecialFrames then tinsert(UISpecialFrames, "AimbotUITextWindow") end
        UI._textWin = f
    end
    f.title:SetText(title or "Aimbot UI")
    f.edit:SetText(text or "")
    f.edit:SetCursorPosition(0)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

-- Runs every module's optional Diagnose() so problems can be reported precisely.
-- The report is printed to chat, saved to the settings file (AimbotUIDB.lastDiag, written at
-- /reload or logout) and shown in a copy window.
function NS.Diagnose(quiet)
    local lines = {}
    NS.capture = lines
    local function Run()
        NS.Print("diagnostics (version " .. NS.version .. ", " .. tostring((select(4, GetBuildInfo()))) .. ")")
        for _, key in ipairs(NS.moduleOrder) do
            local m = NS.modules[key]
            NS.Print("|cff4db8ff" .. (m.name or key) .. "|r  " ..
                (NS.Mod(key).enabled and "|cff00ff00on|r" or "|cffff4444off|r"))
            if m.Diagnose then
                local ok, err = pcall(m.Diagnose, m)
                if not ok then NS.ReportError((m.name or key) .. " diagnose", err) end
            end
        end
    end
    local ok, err = pcall(Run)
    NS.capture = nil
    if not ok then NS.ReportError("diagnostics", err) end
    if NS.db then
        NS.db.lastDiag = { version = NS.version, time = date and date("%Y-%m-%d %H:%M:%S") or "", lines = lines }
    end
    if not quiet then
        NS.Print("Saved to your settings file (lastDiag) and shown in a copy window.")
        UI.ShowText("Aimbot UI diagnostics", table.concat(lines, "\n"))
    end
end
