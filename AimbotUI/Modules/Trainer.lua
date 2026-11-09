--[[
  Aimbot UI - Spell Trainer module  (replaces the What's Training? addon)

  The spell list comes from the What's Training? addon by Sveng (MIT license, see
  Data\LICENSE-WhatsTraining.txt): the "Forever" class data - which spell each class can
  train at which level, what it costs, which earlier rank or talent it needs, the spells that
  are quest rewards, and the weapon skills with their trainer cities. That data is bundled in
  Data\, so the tab works anywhere - you do not have to visit a trainer first.

  Known spells are read live from your spellbook.
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Spell Trainer",
    group = "Tools",
    desc = "Shows which spells you can train now and at upcoming levels, with costs, quest spells and "
        .. "weapon skills. Uses the Forever spell data from What's Training?",
    defaults = {
        enabled      = true,
        hideLearned  = true,
        levelsAhead  = 6,      -- 0 = show everything
        notifyLevel  = true,
        showWeapons  = true,
        showIgnored  = false,
        showCost     = true,
        ignored      = {},     -- spellId -> true (right-click a spell to ignore it)
        colors       = {
            available = { 0.30, 1.00, 0.30, 1 },
            reqs      = { 1.00, 0.60, 0.20, 1 },
            talent    = { 0.72, 0.52, 1.00, 1 },
            soon      = { 1.00, 0.85, 0.30, 1 },
            later     = { 0.78, 0.78, 0.84, 1 },
            known     = { 0.50, 0.50, 0.50, 1 },
            weapon    = { 0.40, 0.80, 1.00, 1 },
            ignored   = { 0.45, 0.45, 0.45, 1 },
        },
    },
}
NS.RegisterModule("trainer", M)

local function S() return NS.db.mod.trainer end

----------------------------------------------------------------------
-- Player and spell helpers
----------------------------------------------------------------------
local function PlayerInfo()
    local _, class = UnitClass("player")
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    local race = select(3, UnitRace("player"))
    return class, faction, race
end

local infoCache = {}
local unresolved = {}      -- spellId -> true while the client has not given us the name yet

local function InfoFor(id)
    local c = infoCache[id]
    if c then return c end
    local name, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, i = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(i) == "table" then name, icon = i.name, i.iconID or i.originalIconID end
    elseif GetSpellInfo then
        local ok, n, _, ic = pcall(GetSpellInfo, id)
        if ok then name, icon = n, ic end
    end
    if type(name) ~= "string" or name == "" then
        unresolved[id] = true
        if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, id) end
        return nil
    end
    unresolved[id] = nil
    local rank = ""
    local sub = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
    if sub then
        local ok, r = pcall(sub, id)
        if ok and type(r) == "string" then rank = r end
    end
    c = { name = name, icon = icon, rank = rank }
    infoCache[id] = c
    return c
end

local function SpellLink(id)
    local f = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
    if not f then return end
    local ok, link = pcall(f, id)
    if ok and type(link) == "string" then return link end
end

local function BankPlayer()
    return Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
end

local function KnownDirect(id)
    local bank = BankPlayer()
    if C_SpellBook and bank then
        if C_SpellBook.IsSpellKnown then
            local ok, v = pcall(C_SpellBook.IsSpellKnown, id, bank)
            if ok and v == true then return true end
        end
        if C_SpellBook.IsSpellInSpellBook then
            local ok, v = pcall(C_SpellBook.IsSpellInSpellBook, id, bank, false)
            if ok and v == true then return true end
        end
    end
    if IsPlayerSpell then
        local ok, v = pcall(IsPlayerSpell, id)
        if ok and v == true then return true end
    end
    if IsSpellKnown then
        local ok, v = pcall(IsSpellKnown, id)
        if ok and v == true then return true end
    end
    return false
end

local overriddenMap       -- spellId -> ordered list of ranks (a later rank replaces an earlier one)
local function BuildOverridden(class)
    overriddenMap = {}
    local data = NS.ClassData and NS.ClassData[class]
    if not (data and data.overriddenGroups) then return end
    for _, ids in ipairs(data.overriddenGroups) do
        for _, id in ipairs(ids) do overriddenMap[id] = ids end
    end
end

local function Known(id)
    if KnownDirect(id) then return true end
    local group = overriddenMap and overriddenMap[id]
    if group then
        local mine, best = 0, 0
        for i, other in ipairs(group) do
            if other == id then mine = i end
            if KnownDirect(other) then best = i end
        end
        return mine <= best
    end
    return false
end

----------------------------------------------------------------------
-- Building the list of everything the class can learn
----------------------------------------------------------------------
local static, staticKey      -- cached list for the current class / faction / race

local function Allowed(spell, faction, race)
    if spell.faction ~= nil and spell.faction ~= faction then return false end
    if spell.race == nil and spell.races == nil then return true end
    if spell.races == nil then return spell.race == race end
    return spell.races[1] == race or spell.races[2] == race
end

local function Contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

local function BuildStatic()
    local class, faction, race = PlayerInfo()
    local key = tostring(class) .. "|" .. tostring(faction) .. "|" .. tostring(race)
    if static and staticKey == key then return static end
    staticKey = key
    static = { spells = {}, weapons = {}, hasData = false, class = class }
    BuildOverridden(class)

    local data = NS.ClassData and NS.ClassData[class]
    if data and data.spellsByLevel then
        static.hasData = true
        for level, list in pairs(data.spellsByLevel) do
            for _, spell in ipairs(list) do
                if Allowed(spell, faction, race) then
                    static.spells[#static.spells + 1] = {
                        id = spell.id, level = level, cost = spell.cost,
                        requiredIds = spell.requiredIds, requiredTalentId = spell.requiredTalentId,
                    }
                end
            end
        end
    end

    -- spells that are quest rewards instead of trainer spells
    local quests = NS.QuestSpells and NS.QuestSpells[class]
    if quests then
        static.hasData = true
        for id, entries in pairs(quests) do
            for _, entry in ipairs(entries) do
                if Contains(entry.races, race) then
                    static.spells[#static.spells + 1] = {
                        id = id, level = entry.level, cost = 0,
                        quest = { areas = entry.areas or { entry.area }, quests = entry.quests },
                    }
                    break
                end
            end
        end
    end

    -- weapon skills
    for id, w in pairs(NS.WeaponSkills or {}) do
        if w.classes and w.classes[class] then
            static.weapons[#static.weapons + 1] = {
                id = id, level = w.level or 1, cost = w.cost, order = w.orderIndex or 99,
                trainers = w.trainers and w.trainers[faction] or nil, weapon = true,
            }
        end
    end
    return static
end

----------------------------------------------------------------------
-- Sorting spells into groups
----------------------------------------------------------------------
local function ByLevelThenName(a, b)
    if a.level ~= b.level then return a.level < b.level end
    if (a.quest == nil) ~= (b.quest == nil) then return b.quest ~= nil end
    return (a.name or "") < (b.name or "")
end

local function ByOrder(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return (a.name or "") < (b.name or "")
end

local function Classify(item, plevel, ignored)
    if Known(item.id) then return "known" end
    if ignored[item.id] then return "ignored" end
    if item.requiredTalentId and not Known(item.requiredTalentId) then return "talent" end
    if item.level > plevel then
        return item.level <= plevel + 2 and "soon" or "later"
    end
    if item.requiredIds then
        for _, req in ipairs(item.requiredIds) do
            if not Known(req) then return "reqs" end
        end
    end
    return "available"
end

local function Compute(plevel)
    local st = BuildStatic()
    local s = S()
    local g = { available = {}, reqs = {}, talent = {}, soon = {}, later = {}, known = {}, ignored = {},
        weapon = {}, totalCost = 0, hasData = st.hasData }

    for _, base in ipairs(st.spells) do
        local info = InfoFor(base.id)
        local item = {
            id = base.id, level = base.level, cost = base.cost, quest = base.quest,
            requiredIds = base.requiredIds, requiredTalentId = base.requiredTalentId,
            name = info and info.name or ("Spell " .. base.id), rank = info and info.rank or "",
            icon = info and info.icon, resolved = info ~= nil,
        }
        item.cat = Classify(item, plevel, s.ignored)
        local bucket = g[item.cat]
        if bucket then bucket[#bucket + 1] = item end
        if item.cat == "available" and item.cost then g.totalCost = g.totalCost + item.cost end
    end

    if s.showWeapons then
        for _, base in ipairs(st.weapons) do
            local info = InfoFor(base.id)
            local item = {
                id = base.id, level = base.level, cost = base.cost, order = base.order, weapon = true,
                trainers = base.trainers, name = info and info.name or ("Skill " .. base.id), rank = "",
                icon = info and info.icon, resolved = info ~= nil,
            }
            item.cat = Classify(item, plevel, s.ignored)
            if item.cat ~= "known" or not s.hideLearned then
                if item.cat ~= "ignored" or s.showIgnored then g.weapon[#g.weapon + 1] = item end
            end
        end
    end

    for _, key in ipairs({ "available", "reqs", "talent", "soon", "later", "known", "ignored" }) do
        table.sort(g[key], ByLevelThenName)
    end
    table.sort(g.weapon, ByOrder)
    return g
end

----------------------------------------------------------------------
-- Text helpers
----------------------------------------------------------------------
local function Money(copper)
    if not copper or copper <= 0 then return "" end
    if GetCoinTextureString then
        local ok, text = pcall(GetCoinTextureString, copper)
        if ok and type(text) == "string" then return text end
    end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if cop > 0 or #parts == 0 then parts[#parts + 1] = cop .. "c" end
    return table.concat(parts, " ")
end

local function AreaName(id)
    if not id then return nil end
    local f = (C_Map and C_Map.GetAreaInfo) or GetAreaInfo
    if not f then return nil end
    local ok, name = pcall(f, id)
    if ok and type(name) == "string" then return name end
end

local function QuestTitle(id)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
        if ok and type(t) == "string" then return t end
    end
end

local function TrainerCities(item)
    local names, seen = {}, {}
    for _, t in ipairs(item.trainers or {}) do
        local n = AreaName(t.zone)
        if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
    return names
end

local function ColorFor(item)
    local c = S().colors
    return c[item.cat] or c.later
end

----------------------------------------------------------------------
-- Page UI
----------------------------------------------------------------------
local rows = {}
local dirty = false

local function RowTip(self)
    local item = self.item
    if type(item) ~= "table" or type(item.id) ~= "number" then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = false
    pcall(function() shown = GameTooltip:SetSpellByID(item.id) end)
    if not shown or GameTooltip:NumLines() == 0 then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(item.name, 1, 1, 1)
        if item.rank ~= "" then GameTooltip:AddLine(item.rank, 0.8, 0.8, 0.8) end
    end
    GameTooltip:AddLine(" ")
    if not item.weapon then
        GameTooltip:AddDoubleLine("Learn at level", tostring(item.level), 0.7, 0.7, 0.75, 1, 1, 1)
    elseif item.level > 1 then
        GameTooltip:AddDoubleLine("Needs level", tostring(item.level), 0.7, 0.7, 0.75, 1, 1, 1)
    end
    if item.cost and item.cost > 0 then
        GameTooltip:AddDoubleLine("Training cost", Money(item.cost), 0.7, 0.7, 0.75, 1, 1, 1)
    end
    if item.requiredIds and (item.cat == "reqs") then
        local missing = {}
        for _, req in ipairs(item.requiredIds) do
            if not Known(req) then
                local ri = InfoFor(req)
                missing[#missing + 1] = ri and (ri.name .. (ri.rank ~= "" and (" (" .. ri.rank .. ")") or "")) or ("Spell " .. req)
            end
        end
        if #missing > 0 then
            GameTooltip:AddLine("Needs first: " .. table.concat(missing, ", "), 1, 0.6, 0.2, true)
        end
    end
    if item.requiredTalentId then
        local ti = InfoFor(item.requiredTalentId)
        local known = Known(item.requiredTalentId)
        GameTooltip:AddLine("Talent: " .. (ti and ti.name or ("Spell " .. item.requiredTalentId)) .. (known and "  (have it)" or "  (missing)"),
            known and 0.5 or 0.72, known and 1 or 0.52, known and 0.5 or 1, true)
    end
    if item.quest then
        GameTooltip:AddLine("Quest reward", 0.33, 0.67, 1)
        for _, qid in ipairs(item.quest.quests or {}) do
            GameTooltip:AddLine("  " .. (QuestTitle(qid) or ("Quest " .. qid)), 0.8, 0.8, 0.85)
        end
        local zones = {}
        for _, a in ipairs(item.quest.areas or {}) do
            local n = AreaName(a)
            if n then zones[#zones + 1] = n end
        end
        if #zones > 0 then GameTooltip:AddLine("  Where: " .. table.concat(zones, ", "), 0.6, 0.6, 0.65, true) end
    end
    if item.weapon then
        local cities = TrainerCities(item)
        if #cities > 0 then
            GameTooltip:AddLine("Weapon masters: " .. table.concat(cities, ", "), 0.4, 0.8, 1, true)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click: " .. (S().ignored[item.id] and "stop ignoring" or "ignore") .. " this spell", 0.5, 0.5, 0.55)
    GameTooltip:AddLine("Shift-click: link in chat", 0.5, 0.5, 0.55)
    GameTooltip:Show()
end

local function GetRow(i, parent)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, parent)
    r:SetHeight(22)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = NS.UI.Text(r, "", 0, 1, 1, 1)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetWordWrap(false)
    r.lvl = NS.UI.Text(r, "", 0, 1, 1, 1)
    r.lvl:SetPoint("RIGHT", -4, 0)
    r.lvl:SetJustifyH("RIGHT")
    r.lvl:SetWidth(210)
    r.lvl:SetWordWrap(false)
    r.text:SetPoint("RIGHT", r.lvl, "LEFT", -8, 0)
    r:SetScript("OnEnter", RowTip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, button)
        local item = self.item
        if type(item) ~= "table" or type(item.id) ~= "number" then return end
        if button == "RightButton" then
            local ig = S().ignored
            ig[item.id] = (not ig[item.id]) or nil
            M:Refresh()
        elseif IsShiftKeyDown and IsShiftKeyDown() then
            local link = SpellLink(item.id)
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        end
    end)
    rows[i] = r
    return r
end

local function RowHeader(r, text)
    r.item = nil
    r.icon:SetTexture(nil)
    r.text:SetText(text)
    r.text:SetTextColor(1, 1, 1)
    r.lvl:SetText("")
end

local function RowItem(r, item)
    r.item = item
    r.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local label = item.name
    if item.rank ~= "" then label = label .. "  |cff909090" .. item.rank .. "|r" end
    if item.quest then label = label .. "  |cff55aaff[quest]|r" end
    r.text:SetText(label)
    local c = item.weapon and S().colors.weapon or ColorFor(item)
    if item.weapon and (item.cat == "known" or item.cat == "ignored") then c = S().colors[item.cat] end
    r.text:SetTextColor(c[1], c[2], c[3])

    local right
    if item.cat == "known" then
        right = "learned"
    elseif item.weapon then
        local cities = TrainerCities(item)
        right = cities[1] and (#cities > 1 and (cities[1] .. " +" .. (#cities - 1)) or cities[1]) or ""
        if item.level > 1 then right = "level " .. item.level .. "   " .. right end
    else
        right = "level " .. item.level
        if S().showCost and item.cost and item.cost > 0 then right = right .. "   " .. Money(item.cost) end
    end
    r.lvl:SetText(right)
    r.lvl:SetTextColor(c[1], c[2], c[3])
end

local function Lines(g, plevel)
    local s = S()
    local lines = {}
    local function Head(text) lines[#lines + 1] = { header = text } end
    local function Items(list) for _, it in ipairs(list) do lines[#lines + 1] = { item = it } end end
    local function ByLevel(list)
        local last
        for _, it in ipairs(list) do
            if it.level ~= last then last = it.level; Head("Level " .. it.level) end
            lines[#lines + 1] = { item = it }
        end
    end

    if #g.available > 0 then
        Head(string.format("Can train now (%d)%s", #g.available,
            (g.totalCost > 0 and s.showCost) and ("   -   total " .. Money(g.totalCost)) or ""))
        Items(g.available)
    end
    if #g.reqs > 0 then Head(string.format("Needs an earlier rank first (%d)", #g.reqs)); Items(g.reqs) end
    if #g.talent > 0 then Head(string.format("Needs a talent (%d)", #g.talent)); Items(g.talent) end
    if #g.soon > 0 then Head(string.format("Coming soon - next 2 levels (%d)", #g.soon)); ByLevel(g.soon) end

    local later = {}
    for _, it in ipairs(g.later) do
        if s.levelsAhead == 0 or it.level <= plevel + s.levelsAhead then later[#later + 1] = it end
    end
    if #later > 0 then Head(string.format("Later (%d)", #later)); ByLevel(later) end

    if #g.weapon > 0 then Head(string.format("Weapon skills (%d)", #g.weapon)); Items(g.weapon) end
    if not s.hideLearned and #g.known > 0 then Head(string.format("Already known (%d)", #g.known)); Items(g.known) end
    if s.showIgnored and #g.ignored > 0 then Head(string.format("Ignored (%d)", #g.ignored)); Items(g.ignored) end
    return lines
end

local retryScheduled = false
function M:Refresh()
    if not self.list or not self.page then return end
    if not self.list:IsVisible() then dirty = true; return end
    dirty = false

    local plevel = UnitLevel("player") or 1
    local g = Compute(plevel)
    local container = self.list
    for _, r in ipairs(rows) do r:Hide(); r.item = nil end

    local y, idx = 0, 0
    local function Place(r)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -y)
        r:Show()
        y = y + 22
    end

    if not g.hasData then
        idx = idx + 1
        local r = GetRow(idx, container)
        RowHeader(r, "No built-in spell data for this class on this client.")
        Place(r)
    else
        local lines = Lines(g, plevel)
        if #lines == 0 then
            idx = idx + 1
            local r = GetRow(idx, container)
            RowHeader(r, "Nothing to train in the selected range.")
            Place(r)
        end
        for _, line in ipairs(lines) do
            idx = idx + 1
            local r = GetRow(idx, container)
            if line.header then RowHeader(r, line.header) else RowItem(r, line.item) end
            Place(r)
        end
    end
    container:SetContentHeight(y + 4)

    if self.status then
        local class = select(2, UnitClass("player")) or "?"
        local n = #g.available
        if not g.hasData then
            self.status:SetText("Level " .. plevel .. " " .. class .. ". There is no spell data for this class.")
        elseif n > 0 then
            self.status:SetText(string.format("Level %d %s: %d spell%s ready to train%s.", plevel, class, n, n == 1 and "" or "s",
                (g.totalCost > 0 and S().showCost) and (" for " .. Money(g.totalCost)) or ""))
        else
            self.status:SetText(string.format("Level %d %s: nothing to train right now.", plevel, class))
        end
    end

    -- names the client has not delivered yet: look again shortly
    if next(unresolved) and not retryScheduled then
        retryScheduled = true
        C_Timer.After(1.5, function()
            retryScheduled = false
            if next(unresolved) then M:Refresh() end
        end)
    end
end

local pending = false
local function RefreshSoon()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        M:Refresh()
    end)
end

local COLOR_ROWS = {
    { "available", "Ready to train now" },
    { "reqs", "Needs an earlier rank first" },
    { "talent", "Needs a talent" },
    { "soon", "Coming soon (next 2 levels)" },
    { "later", "Later levels" },
    { "weapon", "Weapon skills" },
    { "known", "Already known" },
    { "ignored", "Ignored" },
}

function M.Build(page)
    M.page = page

    page:Section("Spells", "What you can train now and what is coming", { open = true })
    M.status = page:Note("")
    M.list = page:Container()
    M.list:SetScript("OnShow", function() if dirty then M:Refresh() end end)
    M:Refresh()
    page:Note("Hover a spell for details. Right-click to ignore it, shift-click to link it in chat.")

    page:Section("What to show", "Known spells, weapon skills, ignored spells, levels ahead")
    page:Check("Hide spells I already know",
        function() return S().hideLearned end,
        function(v) S().hideLearned = v; M:Refresh() end)
    page:Check("Show weapon skills",
        function() return S().showWeapons end,
        function(v) S().showWeapons = v; M:Refresh() end)
    page:Check("Show training costs",
        function() return S().showCost end,
        function(v) S().showCost = v; M:Refresh() end)
    page:Check("Show spells I have ignored",
        function() return S().showIgnored end,
        function(v) S().showIgnored = v; M:Refresh() end)
    page:Slider("Show upcoming levels ahead (0 = all)", 0, 30, 1,
        function() return S().levelsAhead end,
        function(v) S().levelsAhead = v; M:Refresh() end)
    page:Check("Tell me in chat when I level up and can train spells",
        function() return S().notifyLevel end,
        function(v) S().notifyLevel = v end)
    page:Button("Forget all ignored spells", function() wipe(S().ignored); M:Refresh() end, 240)

    page:Section("Colors", "The color of each kind of spell in the list")
    for _, row in ipairs(COLOR_ROWS) do
        local key = row[1]
        page:Color(row[2],
            function() return S().colors[key] end,
            function(r, g, b, a) local c = S().colors[key]; c[1], c[2], c[3], c[4] = r, g, b, a or 1; M:Refresh() end)
    end
    page:Button("Reset these colors", function()
        for k, v in pairs(M.defaults.colors) do S().colors[k] = { v[1], v[2], v[3], v[4] } end
        M:Refresh()
        NS.UI.RefreshAll()
    end, 220)

    page:Section("About the data", "Where the spell list comes from")
    page:Note("The spell list, costs, required ranks, talents, quest spells and weapon trainers come from the "
        .. "What's Training? addon by Sveng (Forever data, MIT license). It is built into Aimbot UI, so you don't "
        .. "have to visit a trainer first. Which spells you already know is read from your spellbook.")
    page:Note("Not included: hunter pet abilities and warlock demon tomes, and profession recipes.")
end

----------------------------------------------------------------------
function M:Apply()
    BuildStatic()
    if self.list then self:Refresh() end
end

function M:Diagnose()
    local st = BuildStatic()
    local class, faction, race = PlayerInfo()
    NS.Print(string.format("  class %s, faction %s, race id %s", tostring(class), tostring(faction), tostring(race)))
    NS.Print(string.format("  built-in data: %s   trainer spells+quests: %d   weapon skills: %d",
        tostring(st.hasData), #st.spells, #st.weapons))
    local known, total = 0, #st.spells
    for _, sp in ipairs(st.spells) do if Known(sp.id) then known = known + 1 end end
    local un = 0
    for _ in pairs(unresolved) do un = un + 1 end
    NS.Print(string.format("  known from the list: %d of %d   names still loading: %d", known, total, un))
    NS.Print("  spellbook API: " .. tostring(C_SpellBook ~= nil and BankPlayer() ~= nil))
end

function M:Init()
    for _, ev in ipairs({
        "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE", "LEARNED_SPELL_IN_TAB",
        "TRAINER_UPDATE", "SPELL_DATA_LOAD_RESULT", "PLAYER_LEVEL_UP", "ACTIVE_TALENT_GROUP_CHANGED",
    }) do
        pcall(NS.On, ev, function(event, newLevel)
            if event == "PLAYER_LEVEL_UP" then
                local s = S()
                if s.enabled and s.notifyLevel then
                    local lvl = tonumber(newLevel) or UnitLevel("player") or 1
                    local g = Compute(lvl)
                    local n = #g.available
                    if n > 0 then
                        NS.Print(string.format("You can train |cff00ff00%d|r spell%s%s. Type /aimbot trainer to see them.",
                            n, n == 1 and "" or "s",
                            (g.totalCost > 0 and s.showCost) and (" (" .. Money(g.totalCost) .. ")") or ""))
                    end
                end
            end
            RefreshSoon()
        end)
    end
end
