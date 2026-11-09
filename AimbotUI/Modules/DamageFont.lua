--[[
  Aimbot UI - Damage Font
  Integrates NiceDamage (by Montyburns): swaps the font used for the floating
  combat text (the damage / healing numbers that fly up over targets).

  The original addon makes you rename font files by hand. Here you just pick a
  font in the settings and see a live preview. The 8 fonts come from NiceDamage.

  IMPORTANT: the game reads this font once per login, so a change only takes effect
  after you log out to the CHARACTER SELECT screen and back in (or restart the game).
  /reload is not enough. The tab tells you what is active right now and what will be
  active next login.

  Other addons that set the same global (the standalone NiceDamage, ElvUI, ...) can
  overwrite it after we do, so the font is re-asserted whenever any addon finishes
  loading and again at login.
]]

local ADDON_NAME, NS = ...

local FONT_DIR = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\fonts\\"

-- id 0 = leave Blizzard's font alone
local FONTS = {
    { 0, "Default (Blizzard)" },
    { 1, "Pepsi" },
    { 2, "Zombie" },
    { 3, "Basket of Hammers" },
    { 4, "College" },
    { 5, "Galaxy" },
    { 6, "Elite  (PARRY / MISS text breaks)" },
    { 7, "Stentiga" },
    { 8, "Skratch Punk" },
}

local M = {
    name  = "Damage Font",
    group = "Style",
    desc  = "Change the font of the floating damage and healing numbers (NiceDamage). "
        .. "Pick a font below. It applies after you log out to the character select screen and back in.",
    defaults = {
        enabled = true,
        font    = 1,
    },
}
NS.RegisterModule("damage", M)

local function S() return NS.db.mod.damage end

local blizzardFont = _G.DAMAGE_TEXT_FONT   -- remembered so "Default" and "off" can restore it
local activeAtLoad                          -- font id that was applied when the game started

local function PathFor(id)
    if id and id > 0 then return FONT_DIR .. "damage" .. id .. ".ttf" end
    return blizzardFont or STANDARD_TEXT_FONT
end

local function Wanted()
    local s = S()
    if not s.enabled then return 0 end
    return s.font or 0
end

local overwritten = false    -- true when another addon changed the global after we set it
local fileMissing = false    -- true when the client says it does not know our font file

-- Midnight clients only use font files they have registered. A file copied into the
-- AddOns folder while the game was running is not registered until the game is restarted.
-- Returns true / false, or nil when the client has no way to tell.
local function FileKnown(path)
    local A = _G.C_UIFileAsset
    if type(A) ~= "table" then return nil end
    local answered, known = false, false
    for _, fn in ipairs({ "IsLooseFile", "IsKnownFile" }) do
        if type(A[fn]) == "function" then
            local ok, v = pcall(A[fn], path)
            if ok and type(v) == "boolean" then
                answered = true
                if v then known = true end
            end
        end
    end
    if not answered then return nil end
    return known
end

local function SetGlobalFont()
    local id = Wanted()
    local want = PathFor(id)
    fileMissing = false
    if id > 0 and FileKnown(want) == false then
        -- do not point the game at a font it cannot load
        fileMissing = true
        want = blizzardFont or STANDARD_TEXT_FONT
    end
    local cur = _G.DAMAGE_TEXT_FONT
    if activeAtLoad == nil then
        activeAtLoad = fileMissing and 0 or id
    elseif cur ~= want and cur ~= blizzardFont then
        overwritten = true
    end
    if cur ~= want then _G.DAMAGE_TEXT_FONT = want end
end

local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
local OTHER_FONT_ADDONS = { "NiceDamage", "NiceDamage_Reloaded", "ElvUI", "MikScrollingCombatText", "Parrot",
    "xCT", "xCT+", "ScrollingCombatText", "SimpleCombatFont", "ClassicFCT", "BetterDamage" }

local function OtherAddons()
    local found = {}
    if not IsLoaded then return found end
    for _, name in ipairs(OTHER_FONT_ADDONS) do
        local ok, loaded = pcall(IsLoaded, name)
        if ok and loaded then found[#found + 1] = name end
    end
    return found
end

local function CVarValue(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not get then return nil end
    local ok, v = pcall(get, name)
    if ok then return v end
end

local function TurnNumbersOn()
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not set then return end
    for _, name in ipairs({ "floatingCombatTextCombatDamage", "floatingCombatTextCombatHealing" }) do
        pcall(set, name, "1")
    end
end

local function NameOf(id)
    for _, f in ipairs(FONTS) do
        if f[1] == id then return f[2] end
    end
    return "Default (Blizzard)"
end

function M:Apply()
    SetGlobalFont()
    if M.Refresh then M.Refresh() end
end

-- Runs at ADDON_LOADED, which is early enough for the engine to pick the font up.
function M:Init()
    SetGlobalFont()
    -- Re-assert after every other addon has loaded (a standalone NiceDamage sorts after
    -- "AimbotUI" and would otherwise win), and again right before the world loads.
    NS.On("ADDON_LOADED", SetGlobalFont)
    NS.On("PLAYER_LOGIN", SetGlobalFont)
    NS.On("PLAYER_ENTERING_WORLD", SetGlobalFont)
end

function M:Diagnose()
    NS.Print("  font id active since login: " .. NameOf(activeAtLoad or 0))
    NS.Print("  font id selected: " .. NameOf(Wanted()))
    NS.Print("  DAMAGE_TEXT_FONT = " .. tostring(_G.DAMAGE_TEXT_FONT))
    local path = PathFor(Wanted())
    local known = FileKnown(path)
    NS.Print("  game knows the font file: " .. (known == nil and "can't tell (no file API)" or tostring(known))
        .. (fileMissing and "   |cffff6666(so the default font was kept)|r" or ""))
    NS.Print("  file API present: " .. tostring(type(_G.C_UIFileAsset) == "table"))
    NS.Print("  another addon overwrote it during login: " .. tostring(overwritten))
    local others = OtherAddons()
    NS.Print("  other combat text / font addons loaded: " .. (#others > 0 and table.concat(others, ", ") or "none"))
    NS.Print("  floatingCombatTextCombatDamage = " .. tostring(CVarValue("floatingCombatTextCombatDamage"))
        .. "   floatingCombatTextCombatHealing = " .. tostring(CVarValue("floatingCombatTextCombatHealing")))
end

----------------------------------------------------------------------
-- Settings page
----------------------------------------------------------------------
function M.Build(page)
    local options = {}
    for _, f in ipairs(FONTS) do options[#options + 1] = { f[1], f[2] } end

    page:Section("Font", "Pick the damage number font")
    page:Cycle("Damage text font", options,
        function() return S().font end,
        function(v) S().font = v; NS.ApplyModule("damage") end)

    page:Section("Preview", "How it looks", { pinned = true })
    local box = page:Container()
    box:SetContentHeight(78)
    local sample = box:CreateFontString(nil, "OVERLAY")
    sample:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
    sample:SetTextColor(1, 0.82, 0.2)
    local sample2 = box:CreateFontString(nil, "OVERLAY")
    sample2:SetPoint("TOPLEFT", sample, "BOTTOMLEFT", 0, -6)
    sample2:SetTextColor(1, 0.25, 0.25)

    local status = page:Note("")
    local warn = page:Note("")
    warn:SetTextColor(1, 0.6, 0.3)
    local numbers = page:Note("")
    page:Button("Turn floating damage and healing numbers on", function()
        TurnNumbersOn()
        M.Refresh()
    end, 300)

    function M.Refresh()
        local id = S().font or 0
        local path = PathFor(id)
        local ok = sample:SetFont(path, 30, "OUTLINE")
        if ok == false then sample:SetFont(STANDARD_TEXT_FONT, 30, "OUTLINE") end
        ok = sample2:SetFont(path, 24, "OUTLINE")
        if ok == false then sample2:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE") end
        sample:SetText("1,234   5,678!   Crit 9,999")
        sample2:SetText("Fireball  -  Parry  -  Miss  -  Dodge")

        local active = NameOf(activeAtLoad or 0)
        local nextOne = NameOf(Wanted())
        if (activeAtLoad or 0) == Wanted() then
            status:SetText("Active since you logged in: " .. active .. ".  Nothing more to do.")
        else
            status:SetText("Active since you logged in: " .. active .. ".  Selected: " .. nextOne
                .. ".  Log out to the character select screen and back in to apply it (/reload is not enough).")
        end
        local others = OtherAddons()
        if fileMissing then
            warn:SetText("The game does not recognise the font file yet, so the default font was kept. "
                .. "Fully quit World of Warcraft (not just log out) and start it again once - "
                .. "files copied in while the game was running are only registered on a fresh start.")
        elseif #others > 0 then
            warn:SetText("These addons also change combat text and can override this font: "
                .. table.concat(others, ", ") .. ". Disable them (or their font option) if the font doesn't change.")
        else
            warn:SetText("")
        end
        local dmg = CVarValue("floatingCombatTextCombatDamage")
        numbers:SetText("Floating damage numbers in the game options: "
            .. ((dmg == "1" or dmg == 1) and "ON" or ((dmg == nil) and "unknown" or "OFF"))
            .. ".  The font only matters if they are on.")
        page:Reflow()
    end
    table.insert(page.refreshers, M.Refresh)
    M.Refresh()

    page:Section("Notes", "How to apply a new font")
    page:Note("How to apply a new font: pick it here, then log out to the character select screen and log back in. "
        .. "A /reload does not work because the game reads the font once per login. "
        .. "If you also have the standalone NiceDamage addon installed, remove it - this tab replaces it.")
    page:Note("Font #6 (Elite) has no characters for words like PARRY, MISS and DODGE, so those show up "
        .. "garbled. The fonts only contain standard English letters, so other languages may look wrong. "
        .. "If the numbers ever look wrong, pick Default (Blizzard) and restart.")
end
