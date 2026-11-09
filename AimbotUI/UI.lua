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

local SIDEBAR_W = 190
local HEADER_H  = 84

local texts   = setmetatable({}, { __mode = "k" })  -- fontstring -> size offset
local accents = setmetatable({}, { __mode = "k" })  -- texture    -> alpha multiplier
local roles   = setmetatable({}, { __mode = "k" })  -- fontstring -> "body" | "muted" (follows the text colors)
local pages   = {}
local tabs    = {}
local tabList = {}
local win, content, sidebar, titleBar, titleBG, bgTex, sideBG, grip
local borderEdges = {}
local currentTab

local function W() return NS.db.window end

----------------------------------------------------------------------
-- Primitives
----------------------------------------------------------------------
function UI.Text(parent, text, offset, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local size = (NS.db and W().fontSize or 12) + (offset or 0)
    fs:SetFont(FONT, size, "")
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

function UI.Accent(tex, mult)
    accents[tex] = mult or 1
    local c = W().accent
    tex:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * (mult or 1))
end

local function RestyleTexts()
    local base = W().fontSize
    local body, muted = W().text, W().muted
    for fs, offset in pairs(texts) do
        fs:SetFont(FONT, base + offset, "")
        local role = roles[fs]
        if role == "body" then fs:SetTextColor(body[1], body[2], body[3])
        elseif role == "muted" then fs:SetTextColor(muted[1], muted[2], muted[3]) end
    end
end

local function RestyleAccents()
    local c = W().accent
    for tex, mult in pairs(accents) do
        tex:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * mult)
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

function UI.MakeButton(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, height or 22)
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0.30, 0.30, 0.34, 1)
    local fill = b:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(0.14, 0.14, 0.16, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    UI.Accent(hl, 0.22)
    local fs = UI.Text(b, label)
    fs:SetPoint("CENTER")
    fs:SetJustifyH("CENTER")
    b.label = fs
    b:SetScript("OnMouseDown", function() fill:SetColorTexture(0.10, 0.10, 0.12, 1) end)
    b:SetScript("OnMouseUp",   function() fill:SetColorTexture(0.14, 0.14, 0.16, 1) end)
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
local function MakeSwitch(parent, get, set)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(40, 20)
    local track = sw:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    local knob = sw:CreateTexture(nil, "ARTWORK")
    knob:SetSize(16, 16)
    knob:SetColorTexture(0.96, 0.96, 0.98, 1)
    local hl = sw:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)

    function sw.Refresh()
        local on = get() and true or false
        knob:ClearAllPoints()
        if on then
            local c = W().accent
            track:SetColorTexture(c[1], c[2], c[3], 0.95)
            knob:SetPoint("RIGHT", sw, "RIGHT", -2, 0)
        else
            track:SetColorTexture(0.26, 0.26, 0.29, 1)
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

----------------------------------------------------------------------
-- Page: a scrollable column of cards
----------------------------------------------------------------------
local Page = {}
Page.__index = Page

local function MakeScrollbar(parent, sf)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(6)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -4)
    bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 4)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.04)
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(6)
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
    local iy = card.title and 40 or 12
    local innerW = cw - 8 - 32
    for _, row in ipairs(card.rows) do
        local h = row.height(innerW)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", card.frame, "TOPLEFT", 16, -iy)
        row.frame:SetPoint("TOPRIGHT", card.frame, "TOPRIGHT", -16, -iy)
        row.frame:SetHeight(h)
        iy = iy + h + 6
    end
    card.frame:SetHeight(iy + 8)
    return iy + 8 + 12
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
    bg:SetColorTexture(1, 1, 1, 0.035)
    Edges(f, 1, 1, 1, 0.07, "BORDER")
    local card = { frame = f, rows = {}, title = title, desc = desc,
        pinned = (type(opts) == "table" and opts.pinned) and true or false,
        openFirst = (type(opts) == "table" and opts.open) and true or false }
    if title then
        local accent = f:CreateTexture(nil, "ARTWORK")
        accent:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        accent:SetSize(3, 24)
        UI.Accent(accent, 1)
        local fs = UI.Text(f, title, 1, 1, 1, 1)
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -11)
        card.titleText = fs
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
    local sw = MakeSwitch(f, get, set)
    sw:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    local fs = UI.Text(f, label)
    fs:SetPoint("LEFT", f, "LEFT", 0, 0)
    fs:SetPoint("RIGHT", sw, "LEFT", -12, 0)
    fs:SetWordWrap(false)
    if type(desc) == "string" then Tip(sw, label, desc) end
    table.insert(self.refreshers, sw.Refresh)
    self:Reflow()
    return sw
end

function Page:Slider(label, min, max, step, get, set, fmt)
    local f = AddRow(self, 24, label)
    local val = UI.Text(f, "")
    val:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    val:SetWidth(54)
    val:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, f)
    s:SetPoint("RIGHT", val, "LEFT", -10, 0)
    s:SetSize(180, 18)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(0.24, 0.24, 0.27, 1)

    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(10, 16)
    UI.Accent(thumb, 1)

    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)
    UI.Accent(fill, 0.6)

    local fs = UI.Text(f, label)
    fs:SetPoint("LEFT", f, "LEFT", 0, 0)
    fs:SetPoint("RIGHT", s, "LEFT", -12, 0)
    fs:SetWordWrap(false)

    local refreshing = false
    local function show(v) val:SetText(fmt and fmt(v) or tostring(v)) end
    s:SetScript("OnValueChanged", function(_, v)
        if refreshing then return end
        v = math.floor(v / step + 0.5) * step
        v = tonumber(string.format("%.4f", v))
        show(v)
        set(v)
    end)
    local function refresh()
        refreshing = true
        local v = get() or min
        s:SetValue(v)
        show(v)
        refreshing = false
    end
    table.insert(self.refreshers, refresh)
    refresh()
    self:Reflow()
    return s
end

function Page:Color(label, get, set)
    local f = AddRow(self, 24, label)
    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(44, 20)
    btn:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    local edge = btn:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0.55, 0.55, 0.60, 1)
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

-- options = { { "key", "Label" }, ... }
function Page:Cycle(label, options, get, set)
    local f = AddRow(self, 26, label)
    local btn = UI.MakeButton(f, "", 190, 22)
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
        local cur, idx = get(), 1
        for i, o in ipairs(options) do if o[1] == cur then idx = i end end
        idx = idx % #options + 1
        set(options[idx][1])
        refresh()
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
    edge:SetColorTexture(0.30, 0.30, 0.34, 1)
    local fill = holder:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(0.08, 0.08, 0.09, 1)

    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", 7, -2)
    box:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -7, 2)
    box:SetAutoFocus(false)
    box:SetMaxLetters(80)
    box:SetFont(FONT, (NS.db and W().fontSize or 12), "")
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
        edge:SetColorTexture(0.30, 0.30, 0.34, 1)
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

----------------------------------------------------------------------
-- Window-wide refresh
----------------------------------------------------------------------
local function RefreshTabDots()
    for _, t in ipairs(tabList) do
        if t.module then
            local on = NS.Mod(t.key) and NS.Mod(t.key).enabled
            if on then
                local c = W().accent
                t.dot:SetColorTexture(c[1], c[2], c[3], 1)
            else
                t.dot:SetColorTexture(0.32, 0.32, 0.35, 1)
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
    titleBG:SetColorTexture(w.titleBar[1], w.titleBar[2], w.titleBar[3], w.bg[4])
    sideBG:SetColorTexture(w.sidebar[1], w.sidebar[2], w.sidebar[3], w.sidebar[4])
    for _, e in ipairs(borderEdges) do
        e:SetColorTexture(w.border[1], w.border[2], w.border[3], w.border[4])
    end
    RestyleAccents()
    RestyleTexts()
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
        sw = MakeSwitch(h, function() return NS.Mod(key).enabled end,
            function(v) NS.Mod(key).enabled = v; NS.ApplyModule(key) end)
        sw:SetPoint("TOPRIGHT", h, "TOPRIGHT", -14, -14)
        local lbl = UI.Text(h, "Enabled", -1, 0.65, 0.65, 0.70)
        lbl:SetPoint("RIGHT", sw, "LEFT", -8, 0)
        local reset = UI.MakeButton(h, "Reset tab", 84, 20)
        reset:SetPoint("TOPRIGHT", sw, "BOTTOMRIGHT", 0, -8)
        reset:SetScript("OnClick", function() NS.ResetModule(key) end)
        right = 130
    end

    local t = UI.Text(h, title, 6, 1, 1, 1)
    t:SetPoint("TOPLEFT", h, "TOPLEFT", 16, -14)
    local d = UI.Text(h, desc or "", -1, 0.62, 0.62, 0.67)
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
    d:SetPoint("RIGHT", h, "RIGHT", -(right + 16), 0)
    d:SetJustifyV("TOP")
    d:SetWordWrap(true)
    if d.SetMaxLines then d:SetMaxLines(3) end

    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 10, 0)
    line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -10, 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.08)
    return h, sw
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
-- Theme presets. Picking one sets the window colors; any color can be changed afterwards.
local THEMES = {
    { "blue",     "Aimbot Blue",  { 0.07, 0.07, 0.08 }, { 0.30, 0.70, 1.00 } },
    { "crimson",  "Crimson",      { 0.09, 0.06, 0.06 }, { 0.92, 0.27, 0.32 } },
    { "emerald",  "Emerald",      { 0.06, 0.085, 0.07 }, { 0.25, 0.85, 0.52 } },
    { "violet",   "Violet",       { 0.08, 0.06, 0.10 }, { 0.68, 0.42, 1.00 } },
    { "gold",     "Gold",         { 0.09, 0.08, 0.06 }, { 1.00, 0.78, 0.25 } },
    { "orange",   "Ember",        { 0.09, 0.07, 0.06 }, { 1.00, 0.52, 0.20 } },
    { "graphite", "Graphite",     { 0.12, 0.12, 0.13 }, { 0.78, 0.78, 0.84 } },
    { "black",    "Pure black",   { 0.00, 0.00, 0.00 }, { 0.30, 0.70, 1.00 } },
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
    page:Cycle("Color theme", options,
        function() return W().theme end,
        function(v) if v ~= "custom" then ApplyTheme(v) end; W().theme = v; UI.ApplyStyle() end)
    page:Note("Click the button to step through the themes. Changing any color below switches it to Custom.")

    page:Section("Window", "Size, opacity, text size and locking")
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
    page:Button("Reset all window colors", function() ApplyTheme("blue"); UI.ApplyStyle() end, 260)

    page:Section("Modules", "Switch whole modules on or off")
    for _, key in ipairs(NS.moduleOrder) do
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
        .. "/aimbot <tab> on|off  toggles a module.   /sparkle  toggles the button sparkle.   "
        .. "Tabs: lorti, damage, sparkle, mana, range, trainer, double, memory.")
    page:Note("Credits: Lorti UI Classic by Lorti, Chordsy, Macumba, Knall, Jozh, Xyz, Arrone and Redskin. "
        .. "NiceDamage by Montyburns. Their artwork and fonts are used here with the original credit.")
end

local function Create()
    local w = W()
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

    local function Edge(p1, p2, width, height)
        local t = win:CreateTexture(nil, "BORDER")
        t:SetPoint(p1); t:SetPoint(p2)
        if width then t:SetWidth(width) end
        if height then t:SetHeight(height) end
        table.insert(borderEdges, t)
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 1)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

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
    title:SetPoint("LEFT", mark, "RIGHT", 8, 0)
    local ver = UI.Text(tb, "v" .. NS.version, -2, 0.50, 0.50, 0.56)
    ver:SetPoint("LEFT", title, "RIGHT", 8, -1)

    local close = UI.MakeButton(tb, "X", 24, 22)
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() win:Hide() end)

    local tline = tb:CreateTexture(nil, "ARTWORK")
    tline:SetPoint("BOTTOMLEFT", tb, "BOTTOMLEFT", 0, 0)
    tline:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", 0, 0)
    tline:SetHeight(1)
    UI.Accent(tline, 0.55)

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
    sEdge:SetColorTexture(0.30, 0.30, 0.34, 1)
    local sFill = sHolder:CreateTexture(nil, "BORDER")
    sFill:SetPoint("TOPLEFT", 1, -1)
    sFill:SetPoint("BOTTOMRIGHT", -1, 1)
    sFill:SetColorTexture(0.08, 0.08, 0.09, 1)
    searchBox = CreateFrame("EditBox", nil, sHolder)
    searchBox:SetPoint("TOPLEFT", sHolder, "TOPLEFT", 8, -2)
    searchBox:SetPoint("BOTTOMRIGHT", sHolder, "BOTTOMRIGHT", -24, 2)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchBox:SetFont(FONT, W().fontSize, "")
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
        sEdge:SetColorTexture(0.30, 0.30, 0.34, 1)
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
                y = y - 8
                e.group:ClearAllPoints()
                e.group:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 16, y)
                y = y - 16
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
            local g = UI.Text(sideChild, string.upper(mod.group), -2, 0.45, 0.45, 0.50)
            sideEntries[#sideEntries + 1] = { group = g }
        end

        local btn = CreateFrame("Button", nil, sideChild)
        btn:SetHeight(28)

        local sel = btn:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        UI.Accent(sel, 0.16)
        sel:Hide()
        local selBar = btn:CreateTexture(nil, "ARTWORK")
        selBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        selBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        selBar:SetWidth(3)
        UI.Accent(selBar, 1)
        selBar:Hide()
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)

        local dot
        local fs = UI.Text(btn, label)
        if mod then
            dot = btn:CreateTexture(nil, "ARTWORK")
            dot:SetSize(7, 7)
            dot:SetPoint("LEFT", btn, "LEFT", 12, 0)
            fs:SetPoint("LEFT", dot, "RIGHT", 9, 0)
        else
            fs:SetPoint("LEFT", btn, "LEFT", 14, 0)
        end
        local arrow = UI.Text(btn, "+", 3, 0.62, 0.62, 0.68)
        arrow:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
        fs:SetPoint("RIGHT", arrow, "LEFT", -6, 0)
        fs:SetWordWrap(false)
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
            fs:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        end
    end

    NewTab("general", "General", BuildGeneral, nil)
    for _, key in ipairs(NS.moduleOrder) do
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
    sparkle = "sparkle",
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
    general = "general", window = "general",
}

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
        NS.Print("unknown tab '" .. a .. "'. Try: general, lorti, damage, sparkle, mana, range, trainer, double, memory, mute, fps, privacy, dr  (or /aimbot clean)")
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
    NS.Print("Button sparkle " .. (m.enabled and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
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
