--[[
  Aimbot UI - Boot
  Loads saved variables, initializes modules, applies everything, and adds a
  small entry in Esc > Options > AddOns that opens the main window.
]]

local ADDON_NAME, NS = ...

local function RegisterSettingsEntry()
    local panel = CreateFrame("Frame")
    panel.name = "Aimbot UI"
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Aimbot UI")
    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    note:SetText("All settings live in the Aimbot UI window.")
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(180, 26)
    btn:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
    btn:SetText("Open Aimbot UI")
    btn:SetScript("OnClick", function()
        if HideUIPanel and SettingsPanel then pcall(HideUIPanel, SettingsPanel) end
        NS.UI.Show()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(cat)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

NS.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    NS.InitDB()
    NS.InitModules()
    local ok, err = pcall(RegisterSettingsEntry)
    if not ok then NS.ReportError("settings entry", err) end
end)

NS.On("PLAYER_LOGIN", function()
    if not NS.db then return end
    NS.ApplyAll()
    NS.Print("loaded. Type |cff4db8ff/aimbot|r to open the settings window.")
end)

NS.On("PLAYER_ENTERING_WORLD", function()
    if not NS.db then return end
    NS.ApplyAll()
    C_Timer.After(1.5, NS.ApplyAll)   -- catch Blizzard art that finishes building late
end)
