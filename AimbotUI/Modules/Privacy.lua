--[[
  Aimbot UI - Privacy (stream mode)

  A private mode for streams and screenshots. While it is ON:
    * other players' names on unit frames, raid frames and nameplates become their
      class ("Mage"), "Player", or nothing
    * your own name shows as a name you choose (optionally in a colour you choose)
    * your BattleTag in the friends window shows as a made-up one
    * chat shows the same swapped names, whispers can be kept out of chat and read later
      in a private inbox, and chat bubbles are hidden
    * the zone name and clock on the minimap can be hidden
    * a Be Right Back screen covers the game with your message and how long you have been away
  Turn it OFF and everything is put back.

  This is original code written for Aimbot UI from the public description of the idea.
  Names are never read back out of anything: replacements are worked out from the unit's
  class, and every value the client marks as secret is treated as "a player".
]]

local ADDON_NAME, NS = ...

local M = {
    name = "Privacy",
    group = "QoL",
    desc = "Stream mode. Swaps other players' names for their class, shows a made-up name and BattleTag for "
        .. "you, keeps whispers out of chat, and has a Be Right Back screen.",
    defaults = {
        enabled     = true,
        startOn     = true,                    -- (kept for old saves) private mode is always on at login
        names       = "class",                 -- "class", "player" or "hidden"
        frames      = true,                    -- unit frames, party and raid frames
        nameplates  = true,
        chat        = true,
        ownNameOn   = true,
        ownName     = "Streamer",
        ownColorOn  = false,
        ownColor    = { 0.30, 0.80, 1.00, 1 },
        tagOn       = true,
        tag         = "Streamer#1234",
        hideWhispers = true,
        allowWhispers = false,                 -- show every whisper untouched (real sender name)
        bubbles     = true,                    -- hide chat bubbles
        headNames   = true,                    -- hide the names the game draws above heads
        friendlyNames = false,                 -- show friendly players above heads, with their Privacy name
        friendlyRange = 60,                    -- nameplate distance (yards) while friendly names are on
        hideZone    = true,
        hideClock   = true,
        indicator   = false,                   -- small "PRIVATE" tag on screen
        brbText     = "Be right back",
        brbTimer    = true,
        inbox       = {},                      -- { { t=, who=, msg=, out= } ... }
        inboxMax    = 100,
        savedBubbles = nil,                    -- the chat-bubble CVars to put back
    },
}
NS.RegisterModule("privacy", M)
NS.Privacy = M

_G.BINDING_HEADER_AIMBOTUI = "Aimbot UI"
_G.BINDING_NAME_AIMBOTUI_PRIVACY = "Toggle private mode"
_G.BINDING_NAME_AIMBOTUI_BRB = "Show / hide Be right back screen"

local function S() return NS.db.mod.privacy end
local issecret = NS.IsSecret

local active = false
M.unread = 0

local function Secret(v) return issecret(v) end
local function IsStr(v) return type(v) == "string" and not Secret(v) end

----------------------------------------------------------------------
-- Working out a replacement name
----------------------------------------------------------------------
local FALLBACK = "Player"

local function ModeLabel(classText)
    local mode = S().names
    if mode == "hidden" then return "" end
    if mode == "player" then return FALLBACK end
    if IsStr(classText) and classText ~= "" then return classText end
    return FALLBACK
end

-- Replacement for a unit token, or nil if the unit should be left alone (NPCs, pets).
local function NameForUnit(unit)
    local s = S()
    if type(unit) ~= "string" then return nil end

    local isPlayer = true
    local ok, v = pcall(UnitIsPlayer, unit)
    if ok and not Secret(v) then isPlayer = v and true or false end
    if not isPlayer then return nil end

    local own = (unit == "player")
    if not own then
        local ok2, same = pcall(UnitIsUnit, unit, "player")
        if ok2 and not Secret(same) and same then own = true end
    end
    if own and s.ownNameOn and IsStr(s.ownName) and s.ownName ~= "" then
        return s.ownName, true
    end

    local class
    local ok3, c = pcall(UnitClass, unit)
    if ok3 and not Secret(c) then class = c end
    return ModeLabel(class), own
end

----------------------------------------------------------------------
-- Text on frames
----------------------------------------------------------------------
local original = setmetatable({}, { __mode = "k" })     -- fontstring -> { r, g, b } before we recoloured it
local tinted = setmetatable({}, { __mode = "k" })       -- fontstring -> true while it carries your name colour
M.colourRestores = 0

local function Near(a, b) return type(a) == "number" and not Secret(a) and math.abs(a - b) < 0.01 end

-- A name text we tinted with your colour that now shows someone else (the target frame keeps the
-- same text when you switch from yourself to an enemy, and the game doesn't recolour it), so the
-- colour goes back to what it was. If the game has already given it a colour of its own (nameplates
-- do), that colour is left alone.
local function Untint(fs)
    if not tinted[fs] then return end
    tinted[fs] = nil
    local o = original[fs]
    original[fs] = nil
    if not (fs.SetTextColor and fs.GetTextColor) then return end
    local ok, r, g, b = pcall(fs.GetTextColor, fs)
    local c = S().ownColor
    local stillOurs = ok and Near(r, c[1]) and Near(g, c[2]) and Near(b, c[3])
    if not stillOurs then return end
    if not o then
        local n = NORMAL_FONT_COLOR
        if type(n) == "table" and type(n.r) == "number" then o = { n.r, n.g, n.b } else o = { 1, 0.82, 0 } end
    end
    pcall(fs.SetTextColor, fs, o[1], o[2], o[3])
    M.colourRestores = M.colourRestores + 1
end

local function SetName(fs, unit, wasOwn)
    if not (fs and fs.SetText) then return end
    local label, own = NameForUnit(unit)
    local s = S()
    if not (own and s.ownColorOn) then Untint(fs) end
    if label == nil then return end
    local okT, cur = pcall(fs.GetText, fs)
    if not (okT and IsStr(cur) and cur == label) then pcall(fs.SetText, fs, label) end
    if own and s.ownColorOn and fs.SetTextColor then
        if not tinted[fs] and fs.GetTextColor then
            local ok, r, g, b = pcall(fs.GetTextColor, fs)
            if ok and type(r) == "number" and not Secret(r) then original[fs] = { r, g, b } end
        end
        local c = s.ownColor
        pcall(fs.SetTextColor, fs, c[1], c[2], c[3])
        tinted[fs] = true
    end
end

local function RestoreName(fs, unit)
    if not (fs and fs.SetText) then return end
    local ok, real = pcall(UnitName, unit)
    if ok and IsStr(real) then pcall(fs.SetText, fs, real) end
    Untint(fs)
end

local function ResolveFS(paths)
    local obj = NS.ResolveFirst(paths)
    if obj and obj.SetText then return obj end
end

-- Finding name texts by what they say. Unit frames differ between clients and are restyled by
-- other addons, so instead of trusting a fixed path we look through the unit frame for any text
-- that is currently showing the unit's real name, and remember it.
local bound = {}            -- unit -> { [fontstring] = true }
local scanCount = 0

local function Scan(root, name, found, budget, depth)
    if budget.n <= 0 or depth > 6 then return end
    budget.n = budget.n - 1
    local ok, regions = pcall(function() return { root:GetRegions() } end)
    if ok then
        for _, r in ipairs(regions) do
            local okT, kind = pcall(r.GetObjectType, r)
            if okT and kind == "FontString" then
                local okX, txt = pcall(r.GetText, r)
                if okX and IsStr(txt) and txt == name then found[#found + 1] = r end
            end
        end
    end
    local okC, kids = pcall(function() return { root:GetChildren() } end)
    if okC then
        for _, k in ipairs(kids) do Scan(k, name, found, budget, depth + 1) end
    end
end

local ROOTS = {
    player = { "PlayerFrame" },
    target = { "TargetFrame" },
    focus = { "FocusFrame" },
    targettarget = { "TargetFrameToT", "TargetFrame.totFrame" },
}
for i = 1, 4 do ROOTS["party" .. i] = { "PartyFrame.MemberFrame" .. i, "PartyMemberFrame" .. i } end

local function Discover()
    scanCount = scanCount + 1
    for unit, paths in pairs(ROOTS) do
        local ok, real = pcall(UnitName, unit)
        if ok and IsStr(real) and real ~= "" then
            local root = NS.ResolveFirst(paths)
            if root and root.GetRegions then
                local found = {}
                Scan(root, real, found, { n = 400 }, 0)
                if #found > 0 then
                    bound[unit] = bound[unit] or {}
                    for _, fs in ipairs(found) do bound[unit][fs] = true end
                end
            end
        end
    end
end

local FIXED = {
    player = { "PlayerName", "PlayerFrame.name", "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.Name" },
    target = { "TargetFrameTextureFrameName", "TargetFrame.name",
        "TargetFrame.TargetFrameContent.TargetFrameContentMain.Name" },
    focus = { "FocusFrameTextureFrameName", "FocusFrame.name",
        "FocusFrame.TargetFrameContent.TargetFrameContentMain.Name" },
    targettarget = { "TargetFrameToTTextureFrameName", "TargetFrameToT.name",
        "TargetFrame.totFrame.Name" },
}

-- The name text of each fixed frame is looked up once and remembered, so fixing a name the
-- instant the game redraws it costs a couple of SetText calls and nothing else.
local fixedFS = {}
local function FixedFS(unit)
    local fs = fixedFS[unit]
    if not fs and FIXED[unit] then
        fs = ResolveFS(FIXED[unit])
        fixedFS[unit] = fs
    end
    return fs
end

-- Fix one unit's name texts right now (same frame as the game's redraw, so no flash).
M.instantFixes = 0
local function FixUnit(unit)
    if not (active and S().enabled and S().frames) then return end
    M.instantFixes = M.instantFixes + 1
    local fs = FixedFS(unit)
    if fs then SetName(fs, unit) end
    local set = bound[unit]
    if set then
        for f in pairs(set) do if f ~= fs then SetName(f, unit) end end
    end
end

-- Every name text we manage: a list of { fs = FontString, unit = "target" }.
local function CollectTargets()
    local list, s = {}, S()

    if s.frames then
        local have = {}
        for unit in pairs(FIXED) do
            local fs = FixedFS(unit)
            if fs then list[#list + 1] = { fs = fs, unit = unit }; have[fs] = true end
        end
        for unit, set in pairs(bound) do
            for fs in pairs(set) do
                if not have[fs] then list[#list + 1] = { fs = fs, unit = unit }; have[fs] = true end
            end
        end
        for i = 1, 4 do
            local fs = ResolveFS({ "PartyFrame.MemberFrame" .. i .. ".Name", "PartyFrame.MemberFrame" .. i .. ".name",
                "PartyMemberFrame" .. i .. "Name" })
            if fs then list[#list + 1] = { fs = fs, unit = "party" .. i } end
        end
        local function Compact(frame)
            if frame and frame.name and frame.name.SetText then
                local unit = frame.displayedUnit or frame.unit
                if type(unit) == "string" then list[#list + 1] = { fs = frame.name, unit = unit } end
            end
        end
        for i = 1, 40 do Compact(_G["CompactRaidFrame" .. i]) end
        for i = 1, 5 do Compact(_G["CompactPartyFrameMember" .. i]) end
        for g = 1, 8 do
            for i = 1, 5 do Compact(_G["CompactRaidGroup" .. g .. "Member" .. i]) end
        end
    end

    if (s.nameplates or s.friendlyNames) and C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do
                local uf = plate.UnitFrame
                local unit = plate.namePlateUnitToken or (uf and uf.unit)
                if uf and uf.name and uf.name.SetText and type(unit) == "string" then
                    list[#list + 1] = { fs = uf.name, unit = unit }
                end
            end
        end
    end
    return list
end

local function Sweep(discover)
    local on = active and S().enabled
    if on and discover and S().frames then pcall(Discover) end
    for _, t in ipairs(CollectTargets()) do
        if on then SetName(t.fs, t.unit) else RestoreName(t.fs, t.unit) end
    end
end

-- Friends window: your BattleTag
-- Clients differ: older ones draw the tag in FriendsFrame's Battle.net box, Forever draws it in the
-- social window (SocialUIFrame.BattleNetBar...PersonalBattleTagDisplay.DisplayText, seen with
-- /fstack) and keeps the old FriendsFrame text hidden. So the known paths are tried and the BattleTag
-- boxes are also searched for texts that show your tag; what is found is remembered and kept
-- swapped for as long as either window is open, so a redraw by the game is put right in a moment.
local TAG_FIXED = {
    "SocialUIFrame.BattleNetBar.ControlsContainer.PersonalBattleTagDisplay.DisplayText",
    "FriendsFrameBattlenetFrame.Tag", "FriendsFrame.BattlenetFrame.Tag",
}
-- Boxes that hold only your own BattleTag (text hidden from addons in here can only be your tag).
local TAG_BOXES = { "SocialUIFrame.BattleNetBar", "FriendsFrameBattlenetFrame", "FriendsFrame.BattlenetFrame" }
-- Whole windows: searched for readable texts only, with the friend lists skipped.
local TAG_WINDOWS = { "FriendsFrame" }
local TAG_SHOWN = { "SocialUIFrame", "FriendsFrame" }
-- Panels of the friends window that list other people: never touched.
local TAG_SKIP = { "FriendsListFrame", "IgnoreListFrame", "WhoFrame", "QuickJoinFrame", "RaidFrame",
    "RecruitAFriendFrame", "FriendsFrameFriendsScrollFrame", "FriendsListFrameScrollFrame",
    "FriendsListFrame.ScrollBox", "FriendsTooltip" }

local tagBound = {}         -- fontstring -> "full" | "name" | "num"
local tagOrder = {}         -- the bound fontstrings, in the order found
local tagOrig = {}          -- fontstring -> { text } as it was before we changed it
M.tagStats = { scans = 0, secret = 0, applied = 0 }

local function Plain(t)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    return t
end

local function TagFS()
    return ResolveFS(TAG_FIXED)
end

-- Your real BattleTag split in two ("Name", "#1234"), or nil when the client hides it from addons.
local function RealTag()
    if not BNGetInfo then return end
    local ok, _, tag = pcall(BNGetInfo)
    if ok and IsStr(tag) and tag ~= "" then
        local name, num = tag:match("^(.-)(#%d+)$")
        return tag, name or tag, num
    end
end

-- What kind of BattleTag text this is: "full", "name", "num" or nil.
local function TagKind(text, realTag, realName, realNum)
    local p = Plain(text)
    if p == "" then return end
    if realTag then
        if p == realTag or p:find(realTag, 1, true) then return "full" end
        if p == realName then return "name" end
        if realNum and p == realNum then return "num" end
        return
    end
    if p:match("^[^#%s]+#%d%d%d+$") then return "full" end
    if p:match("^#%d%d%d+$") then return "num" end
end

local function Bind(fs, kind)
    if tagBound[fs] then return end
    tagBound[fs] = kind
    tagOrder[#tagOrder + 1] = fs
end

local function Skipped()
    local set = {}
    for _, p in ipairs(TAG_SKIP) do
        local o = NS.Resolve(p)
        if o then set[o] = true end
    end
    return set
end

local function ScanTag(root, skip, real, budget, depth, secrets)
    if budget.n <= 0 or depth > 7 or skip[root] then return end
    budget.n = budget.n - 1
    local ok, regions = pcall(function() return { root:GetRegions() } end)
    if ok then
        local texts, numFS = {}, nil
        for _, r in ipairs(regions) do
            local okT, kind = pcall(r.GetObjectType, r)
            if okT and kind == "FontString" then
                local okX, txt = pcall(r.GetText, r)
                if okX and Secret(txt) then
                    M.tagStats.secret = M.tagStats.secret + 1
                    if secrets then secrets[#secrets + 1] = r end
                elseif okX and type(txt) == "string" then
                    local k = TagKind(txt, real[1], real[2], real[3])
                    if k then Bind(r, k) end
                    if k or tagBound[r] then budget.hits = (budget.hits or 0) + 1 end
                    if k == "num" then numFS = r end
                    texts[#texts + 1] = { r, txt }
                end
            end
        end
        -- Name and "#1234" drawn as two texts side by side, with the real tag unknown: the
        -- one-word text next to the number is the name.
        if numFS and not real[1] then
            for _, t in ipairs(texts) do
                local p = Plain(t[2])
                if t[1] ~= numFS and not tagBound[t[1]] and p:match("^[^#%s]+$") then Bind(t[1], "name") end
            end
        end
    end
    local okC, kids = pcall(function() return { root:GetChildren() } end)
    if okC then
        for _, k in ipairs(kids) do
            -- a copyable tag can be an edit box rather than a plain text
            local okT, kind = pcall(k.GetObjectType, k)
            if okT and kind == "EditBox" and not skip[k] then
                local okX, txt = pcall(k.GetText, k)
                if okX and Secret(txt) then
                    M.tagStats.secret = M.tagStats.secret + 1
                    if secrets then secrets[#secrets + 1] = k end
                elseif okX and type(txt) == "string" then
                    local tk = TagKind(txt, real[1], real[2], real[3])
                    if tk then Bind(k, tk) end
                    if tk or tagBound[k] then budget.hits = (budget.hits or 0) + 1 end
                end
            end
            ScanTag(k, skip, real, budget, depth + 1, secrets)
        end
    end
end

local function DiscoverTag()
    M.tagStats.scans = M.tagStats.scans + 1
    M.tagStats.secret = 0
    local real = { RealTag() }
    local skip = Skipped()
    -- The known paths first: a whole tag there, or text the client hides from addons, is your tag.
    for _, p in ipairs(TAG_FIXED) do
        local o = NS.Resolve(p)
        if type(o) == "table" and o.SetText and o.GetText and not tagBound[o] then
            local okX, txt = pcall(o.GetText, o)
            if okX and Secret(txt) then
                Bind(o, "full")
            elseif okX and IsStr(txt) then
                local k = TagKind(txt, real[1], real[2], real[3])
                if k then Bind(o, k) end
            end
        end
    end
    local seen = {}
    for _, p in ipairs(TAG_BOXES) do
        local root = NS.Resolve(p)
        if type(root) == "table" and root.GetRegions and not seen[root] then
            seen[root] = true
            local budget, secrets = { n = 300, hits = 0 }, {}
            ScanTag(root, skip, real, budget, 0, secrets)
            -- Nothing readable in this box shows (or was swapped from) a BattleTag, but it holds
            -- hidden text: that text can only be your tag, so it is swapped as a whole.
            if budget.hits == 0 then
                for _, r in ipairs(secrets) do Bind(r, "full") end
            end
        end
    end
    for _, p in ipairs(TAG_WINDOWS) do
        local root = NS.Resolve(p)
        if type(root) == "table" and root.GetRegions and not seen[root] then
            seen[root] = true
            ScanTag(root, skip, real, { n = 300 }, 0, nil)
        end
    end
end

local function FakeParts()
    local tag = S().tag
    if not IsStr(tag) or tag == "" then tag = "Streamer#1234" end
    local name, num = tag:match("^(.-)(#%d+)$")
    return tag, name or tag, num or ""
end

local function TagOn()
    local s = S()
    return active and s.enabled and s.tagOn
end

local function SweepTag(discover)
    if TagOn() and (discover or #tagOrder == 0) then pcall(DiscoverTag) end
    local on = TagOn()
    local full, name, num = FakeParts()
    for _, fs in ipairs(tagOrder) do
        local kind = tagBound[fs]
        if on then
            local want = (kind == "name" and name) or (kind == "num" and num) or full
            local okX, cur = pcall(fs.GetText, fs)
            local same = okX and IsStr(cur) and cur == want
            if not same then
                if not tagOrig[fs] and okX and (IsStr(cur) or Secret(cur)) then tagOrig[fs] = { cur } end
                if pcall(fs.SetText, fs, want) then M.tagStats.applied = M.tagStats.applied + 1 end
            end
        elseif tagOrig[fs] then
            pcall(fs.SetText, fs, tagOrig[fs][1])
            tagOrig[fs] = nil
        end
    end
    -- Nothing remembered and private mode off: put the real tag back on the fixed text if we can.
    if not on and #tagOrder == 0 then
        local fs = TagFS()
        local tag = RealTag()
        if fs and tag then pcall(fs.SetText, fs, tag) end
    end
end

-- While the friends window is open: re-apply ~6 times a second, look for new texts once a second.
local tagDriver = CreateFrame("Frame")
local tagAcc, tagScanAcc = 0, 0
tagDriver:SetScript("OnUpdate", function(_, dt)
    if not TagOn() then return end
    local open = false
    for _, p in ipairs(TAG_SHOWN) do
        local w = NS.Resolve(p)
        if type(w) == "table" and w.IsShown then
            local ok, shown = pcall(w.IsShown, w)
            if ok and not Secret(shown) and shown then open = true; break end
        end
    end
    if not open then return end
    dt = dt or 0
    tagAcc, tagScanAcc = tagAcc + dt, tagScanAcc + dt
    if tagAcc < 0.15 then return end
    tagAcc = 0
    local discover = tagScanAcc >= 1
    if discover then tagScanAcc = 0 end
    pcall(SweepTag, discover)
end)

local tagHooked = {}
local function HookTag()
    -- The social window may load later than us: called again on ADDON_LOADED, each frame hooked once.
    for _, p in ipairs({ "SocialUIFrame", "FriendsFrame",
        "SocialUIFrame.BattleNetBar.ControlsContainer.PersonalBattleTagDisplay" }) do
        local w = NS.Resolve(p)
        if type(w) == "table" and w.HookScript and not tagHooked[w] then
            tagHooked[w] = true
            pcall(w.HookScript, w, "OnShow", function() if TagOn() then pcall(SweepTag, true) end end)
        end
    end
    if tagHooked.funcs then return end
    tagHooked.funcs = true
    for _, fn in ipairs({ "FriendsFrame_Update", "FriendsList_Update", "FriendsFrame_UpdateBattlenetFrame",
        "FriendsFrameBattlenetFrame_Update" }) do
        if type(_G[fn]) == "function" then
            pcall(hooksecurefunc, fn, function() if TagOn() then pcall(SweepTag, false) end end)
        end
    end
end

-- Minimap zone name and clock
local hidden = setmetatable({}, { __mode = "k" })       -- frame -> its alpha before
local function Hide(frame, on)
    if not (frame and frame.SetAlpha) then return end
    if on then
        if hidden[frame] == nil then
            local ok, a = pcall(frame.GetAlpha, frame)
            hidden[frame] = (ok and type(a) == "number" and not Secret(a)) and a or 1
        end
        frame:SetAlpha(0)
    elseif hidden[frame] ~= nil then
        frame:SetAlpha(hidden[frame])
        hidden[frame] = nil
    end
end

local function SweepWhere()
    local s = S()
    local on = active and s.enabled
    local zone = NS.ResolveFirst({ "MinimapCluster.ZoneTextButton", "MinimapZoneTextButton", "MinimapZoneText" })
    local clock = NS.ResolveFirst({ "TimeManagerClockButton", "MinimapCluster.Clock" })
    Hide(zone, on and s.hideZone)
    Hide(clock, on and s.hideClock)
end

----------------------------------------------------------------------
-- Chat bubbles
----------------------------------------------------------------------
local BUBBLE_CVARS = { "chatBubbles", "chatBubblesParty" }
-- "Friendly names above heads": friendly nameplates in names-only mode (no health bar), friendly
-- NPC plates off, so only players get a name, and that name is swapped like every other plate.
-- Both the older names and the newer (Midnight-style) names are listed; a setting the client
-- doesn't have reads back as nil and is skipped, so whichever set exists is used.
local FRIENDLY_CVARS = {
    -- older clients
    nameplateShowFriends = "1", nameplateShowOnlyNames = "1",
    -- newer clients: friendly players on, names only, no friendly NPC / pet / totem plates
    nameplateShowFriendlyPlayers = "1", nameplateShowOnlyNameForFriendlyPlayerUnits = "1",
    nameplateShowFriendlyNpcs = "0",
    nameplateShowFriendlyPlayerPets = "0", nameplateShowFriendlyPlayerGuardians = "0",
    nameplateShowFriendlyPlayerMinions = "0", nameplateShowFriendlyPlayerTotems = "0",
}

-- Friendly nameplates inside dungeons and raids are locked by the game: an addon can't change
-- their text, so the real names would show. There we leave friendly plates off.
local function FriendlyPlatesAllowed()
    local ok, inside, kind = pcall(IsInInstance)
    if ok and inside and (kind == "party" or kind == "raid") then return false end
    return true
end
M.friendlyBlocked = nil
local HEAD_CVARS = {
    "UnitNameOwn", "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName",
    "UnitNameFriendlyPetName", "UnitNameEnemyPetName", "UnitNamePlayerGuild", "UnitNamePlayerPVPTitle",
}

-- Settings we turn off while private are remembered in saved variables and put back afterwards.
local function RestoreBubbles()
    local saved = S().savedBubbles
    if type(saved) ~= "table" then return end
    for cvar, value in pairs(saved) do pcall(SetCVar, cvar, value) end
    S().savedBubbles = nil
end

local function SweepBubbles()
    local s = S()
    -- Nameplate settings can't be changed in combat: try again when combat ends.
    if InCombatLockdown and InCombatLockdown() then M.cvarPending = true; return end
    M.cvarPending = false
    local want = {}                       -- cvar -> value we want while private
    if active and s.enabled then
        if s.bubbles then for _, c in ipairs(BUBBLE_CVARS) do want[c] = "0" end end
        if s.headNames then for _, c in ipairs(HEAD_CVARS) do want[c] = "0" end end
        if s.friendlyNames then
            if FriendlyPlatesAllowed() then
                for c, v in pairs(FRIENDLY_CVARS) do want[c] = v end
                -- how far away plates (and so friendly names) show; the game caps it at its own max
                local r = tonumber(s.friendlyRange)
                if r and r > 0 then want.nameplateMaxDistance = tostring(math.floor(r)) end
                M.friendlyBlocked = false
            else
                M.friendlyBlocked = true
            end
        end
    end
    local saved = s.savedBubbles or {}
    for cvar, value in pairs(want) do
        if saved[cvar] == nil then
            local ok, v = pcall(GetCVar, cvar)
            if ok and v ~= nil then saved[cvar] = v end
        end
        if saved[cvar] ~= nil then pcall(SetCVar, cvar, value) end
    end
    for cvar, value in pairs(saved) do
        if not want[cvar] then pcall(SetCVar, cvar, value); saved[cvar] = nil end
    end
    s.savedBubbles = next(saved) and saved or nil
end

----------------------------------------------------------------------
-- Chat
----------------------------------------------------------------------
local WHISPER = {
    CHAT_MSG_WHISPER = false, CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = false, CHAT_MSG_BN_WHISPER_INFORM = true,
}
local EMOTE = { CHAT_MSG_EMOTE = true, CHAT_MSG_TEXT_EMOTE = true }
local EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_BATTLEGROUND", "CHAT_MSG_BATTLEGROUND_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
}

local seen, seenOrder = {}, {}
local function FirstTime(lineID)
    if type(lineID) ~= "number" or Secret(lineID) then return true end
    if seen[lineID] then return false end
    seen[lineID] = true
    seenOrder[#seenOrder + 1] = lineID
    if #seenOrder > 200 then seen[table.remove(seenOrder, 1)] = nil end
    return true
end

local function Short(name)
    if Ambiguate then
        local ok, v = pcall(Ambiguate, name, "none")
        if ok and IsStr(v) then return v end
    end
    return (name:gsub("%-.*$", ""))
end

local function ChatLabel(author, guid)
    local s = S()
    local own = false
    if IsStr(guid) and UnitGUID then
        local ok, mine = pcall(UnitGUID, "player")
        if ok and IsStr(mine) and mine == guid then own = true end
    end
    if not own then
        local ok, me = pcall(UnitName, "player")
        if ok and IsStr(me) and Short(author) == me then own = true end
    end
    if own and s.ownNameOn and IsStr(s.ownName) and s.ownName ~= "" then return s.ownName end

    local class
    if IsStr(guid) and GetPlayerInfoByGUID then
        local ok, c = pcall(GetPlayerInfoByGUID, guid)
        if ok and not Secret(c) then class = c end
    end
    local label = ModeLabel(class)
    if label == "" then label = "Hidden" end
    return label
end

local function PlainReplace(text, from, to)
    if from == "" then return text end
    local out, i = {}, 1
    while true do
        local a, b = text:find(from, i, true)
        if not a then out[#out + 1] = text:sub(i); break end
        out[#out + 1] = text:sub(i, a - 1)
        out[#out + 1] = to
        i = b + 1
    end
    return table.concat(out)
end

function M.AddInbox(who, msg, out)
    local s = S()
    local box = s.inbox
    box[#box + 1] = { t = time and time() or 0, who = who, msg = msg, out = out and true or false }
    while #box > (s.inboxMax or 100) do table.remove(box, 1) end
    if not out then M.unread = M.unread + 1 end
    if M.RefreshInbox then M.RefreshInbox() end
end

local function Announce()
    local n = M.unread
    if n > 0 and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff4db8ffAimbot UI|r: %d whisper%s waiting in your private inbox (/aprivacy inbox).",
            n, n == 1 and "" or "s"))
    end
end

local function ChatFilter(frame, event, msg, author, lang, chan, target, flags, zoneID, chanIdx, chanBase, unused, lineID, guid, ...)
    local s = S()
    if not (active and s.enabled and s.chat) then return false end
    if Secret(msg) or Secret(author) or type(msg) ~= "string" or type(author) ~= "string" then return false end

    if WHISPER[event] ~= nil and s.allowWhispers then
        -- Leave whispers (character and Battle.net, sent and received) exactly as the game
        -- sends them, so the real name shows and R / clicking the name replies to the right person.
        return false
    end

    if WHISPER[event] ~= nil and s.hideWhispers then
        if FirstTime(lineID) then
            M.AddInbox(Short(author), msg, WHISPER[event])
            if not WHISPER[event] then Announce() end
        end
        return true
    end

    if author == "" then return false end
    local label = ChatLabel(author, guid)
    local newMsg = msg
    if EMOTE[event] then newMsg = PlainReplace(msg, Short(author), label) end
    return false, newMsg, label, lang, chan, target, flags, zoneID, chanIdx, chanBase, unused, lineID, guid, ...
end

----------------------------------------------------------------------
-- Be right back screen
----------------------------------------------------------------------
local brb, brbSince
local function FmtElapsed(sec)
    sec = math.max(0, math.floor(sec))
    local h, m, s2 = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s2) end
    return string.format("%d:%02d", m, s2)
end

local function EnsureBRB()
    if brb then return brb end
    local f = CreateFrame("Frame", "AimbotUIPrivacyBRB", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:EnableMouse(true)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.02, 0.03, 1)
    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(STANDARD_TEXT_FONT, 46, "OUTLINE")
    f.title:SetPoint("CENTER", f, "CENTER", 0, 30)
    f.timer = f:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE")
    f.timer:SetPoint("TOP", f.title, "BOTTOM", 0, -18)
    f.timer:SetTextColor(0.7, 0.75, 0.85)
    f.hint = f:CreateFontString(nil, "OVERLAY")
    f.hint:SetFont(STANDARD_TEXT_FONT, 12, "")
    f.hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 24)
    f.hint:SetTextColor(0.4, 0.4, 0.45)
    f.hint:SetText("Click, or press the Be right back key again, to come back")
    f:SetScript("OnMouseDown", function() M.SetBRB(false) end)
    local acc = 0
    f:SetScript("OnUpdate", function(self, dt)
        acc = acc + (dt or 0)
        if acc < 0.5 then return end
        acc = 0
        if S().brbTimer and brbSince then
            self.timer:SetText("Away for " .. FmtElapsed(GetTime() - brbSince))
        else
            self.timer:SetText("")
        end
    end)
    brb = f
    return f
end

function M.SetBRB(on)
    local f = EnsureBRB()
    if on == nil then on = not f:IsShown() end
    if on then
        brbSince = GetTime()
        f.title:SetText(S().brbText or "Be right back")
        f.timer:SetText(S().brbTimer and "Away for 0:00" or "")
        f:Show()
    else
        f:Hide()
        brbSince = nil
    end
end

function M.ToggleBRB() M.SetBRB() end
_G.AimbotUI_ToggleBRB = M.ToggleBRB

----------------------------------------------------------------------
-- The on-screen tag
----------------------------------------------------------------------
local tag
local function SweepIndicator()
    local show = active and S().enabled and S().indicator
    if show then
        if not tag then
            tag = CreateFrame("Frame", "AimbotUIPrivacyTag", UIParent)
            tag:SetSize(110, 20)
            tag:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 8, -8)
            tag:SetFrameStrata("HIGH")
            local bg = tag:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.7, 0.1, 0.1, 0.8)
            local t = tag:CreateFontString(nil, "OVERLAY")
            t:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
            t:SetPoint("CENTER")
            t:SetText("PRIVATE MODE")
        end
        tag:Show()
    elseif tag then
        tag:Hide()
    end
end

----------------------------------------------------------------------
-- Turning it on and off
----------------------------------------------------------------------
local ticker
local function ApplyAll()
    pcall(Sweep, true)
    pcall(SweepTag, true)
    pcall(SweepWhere)
    pcall(SweepBubbles)
    pcall(SweepIndicator)
end
M.ApplyAll = ApplyAll

function M.IsActive() return active and S().enabled end

function M.SetActive(on, quiet)
    on = on and true or false
    if on and not S().enabled then
        NS.Print("Privacy is switched off for this tab. Turn the module on first.")
        return
    end
    active = on
    ApplyAll()
    if not quiet then
        NS.Print("Private mode is " .. (on and "|cffff6666ON|r" or "|cff00ff00OFF|r") .. ".")
    end
    if NS.UI and NS.UI.RefreshAll then pcall(NS.UI.RefreshAll) end
end

function M.Toggle() M.SetActive(not active) end

-- Light safety net, once a second: re-check the name texts we already know about. The heavy work
-- (searching frames for name texts, CVars, minimap, indicator) only runs when something changes.
local tickCount = 0
local function Tick()
    if not (active and S().enabled) then return end
    tickCount = tickCount + 1
    pcall(Sweep, tickCount % 10 == 0)
end

-- Many redraws in one moment are folded into a single pass (at most ~10 per second).
local dirty, dirtyDiscover, dirtyAcc = false, false, 0
local pump = CreateFrame("Frame")
pump:SetScript("OnUpdate", function(_, dt)
    if not dirty then return end
    dirtyAcc = dirtyAcc + (dt or 0)
    if dirtyAcc < 0.1 then return end
    dirtyAcc = 0
    dirty = false
    local d = dirtyDiscover
    dirtyDiscover = false
    if active and S().enabled then pcall(Sweep, d) end
end)
local function MarkDirty(discover)
    dirty = true
    if discover then dirtyDiscover = true end
end

----------------------------------------------------------------------
-- Slash command
----------------------------------------------------------------------
local function OpenInbox()
    M.unread = 0
    if NS.UI and NS.UI.Show then NS.UI.Show("privacy") end
end

local function Slash(msg)
    local a = (msg or ""):lower():match("^%s*(%S*)") or ""
    if a == "on" then M.SetActive(true)
    elseif a == "off" then M.SetActive(false)
    elseif a == "" or a == "toggle" then M.Toggle()
    elseif a == "inbox" then OpenInbox()
    elseif a == "brb" then M.SetBRB()
    elseif a == "status" then
        NS.Print(string.format("Private mode: %s   whispers waiting: %d   Be right back: %s",
            active and "ON" or "off", M.unread, (brb and brb:IsShown()) and "showing" or "off"))
    else
        NS.Print("/aprivacy  (on | off | toggle | inbox | brb | status)")
    end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
local function HookNames()
    -- Re-apply the moment the game redraws a name, so the real one never shows for a frame.
    -- The game just redrew a frame: fix that frame's name in the same moment, then let the
    -- light pass catch anything else.
    local function Quick(frame)
        if not (active and S().enabled) then return end
        local unit
        if type(frame) == "table" then
            local ok, u = pcall(function() return frame.unit end)
            if ok and IsStr(u) then unit = u end
        end
        if unit and (FIXED[unit] or bound[unit]) then
            pcall(FixUnit, unit)
            if unit == "target" then pcall(FixUnit, "targettarget") end
        end
        MarkDirty(false)
    end
    local function Try(target, method)
        local obj = target
        if type(target) == "string" then obj = _G[target] end
        if obj and type(obj[method]) == "function" then pcall(hooksecurefunc, obj, method, Quick) end
    end
    -- Raid frames and nameplates redraw their name through this: fix only that one frame, right away.
    if type(_G.CompactUnitFrame_UpdateName) == "function" then
        pcall(hooksecurefunc, "CompactUnitFrame_UpdateName", function(frame)
            if not (active and S().enabled) then return end
            local fs = frame and frame.name
            if not (fs and fs.SetText) then return end
            local unit = frame.displayedUnit or frame.unit
            if type(unit) ~= "string" then return end
            local isPlate = unit:find("^nameplate")
            if (isPlate and (S().nameplates or S().friendlyNames)) or (not isPlate and S().frames) then pcall(SetName, fs, unit) end
        end)
    end
    Try(_G, "UnitFrame_Update")
    for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PartyFrame" }) do
        Try(name, "Update")
        Try(name, "UpdateName")
    end
end

function M:Apply()
    if not S().enabled then
        if active then M.SetActive(false, true) end
        if brb and brb:IsShown() then M.SetBRB(false) end
        return
    end
    ApplyAll()
end

function M:Init()
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if add then
        for _, ev in ipairs(EVENTS) do pcall(add, ev, ChatFilter) end
        M.filtersAdded = true
    end
    pcall(HookNames)
    pcall(HookTag)
    NS.On("ADDON_LOADED", function() pcall(HookTag) end)

    for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE",
        "UNIT_NAME_UPDATE" }) do
        NS.On(ev, function() if active and S().enabled then MarkDirty(true) end end)
    end
    -- New target or focus: fix the name straight away instead of waiting for the next pass.
    NS.On("PLAYER_TARGET_CHANGED", function()
        pcall(FixUnit, "target"); pcall(FixUnit, "targettarget")
    end)
    NS.On("PLAYER_FOCUS_CHANGED", function() pcall(FixUnit, "focus") end)
    NS.On("PLAYER_ENTERING_WORLD", function()
        if active and S().enabled then pcall(ApplyAll) end
    end)
    -- Entering or leaving a dungeon changes whether friendly names can be shown.
    NS.On("ZONE_CHANGED_NEW_AREA", function()
        if active and S().enabled and S().friendlyNames then pcall(SweepBubbles) end
    end)
    NS.On("PLAYER_REGEN_ENABLED", function()
        if M.cvarPending then pcall(SweepBubbles) end
    end)
    -- A new nameplate: fix just that plate.
    NS.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
        if not (active and S().enabled and (S().nameplates or S().friendlyNames)) or type(unit) ~= "string" then return end
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        local uf = ok and plate and plate.UnitFrame
        if uf and uf.name and uf.name.SetText then pcall(SetName, uf.name, unit) end
    end)
    NS.On("PLAYER_LOGOUT", function()
        if active then
            active = false
            ApplyAll()           -- put everything back so nothing stays hidden after logout
        end
    end)

    -- Crash safety: if the game closed while private mode had the bubbles off, put them back.

    if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, Tick) end

    _G.SLASH_AIMBOTPRIVACY1 = "/aprivacy"
    _G.SlashCmdList["AIMBOTPRIVACY"] = Slash

    -- Private mode always starts ON at login / reload (turn the whole Privacy module off to disable it).
    if S().enabled then
        C_Timer.After(1, function() M.SetActive(true, true) end)
    end
end

function M:Diagnose()
    local s = S()
    NS.Print(string.format("  private mode: %s   chat filters: %s   whispers in inbox: %d (%d unread)",
        active and "ON" or "off", tostring(M.filtersAdded), #s.inbox, M.unread))
    NS.Print(string.format("  whispers: %s", s.allowWhispers and "allowed from everyone (real names)"
        or (s.hideWhispers and "kept in the inbox" or "shown with the sender's name hidden")))
    NS.Print(string.format("  name texts found: %d   scans: %d", #CollectTargets(), scanCount))
    if active and s.enabled and s.tagOn then pcall(SweepTag, true) end
    local realTag = RealTag()
    NS.Print(string.format("  BattleTag: %s   fixed text found: %s   real tag readable: %s   texts swapped: %d"
        .. "   unreadable texts in the header: %d   scans: %d   swaps: %d",
        s.tagOn and "on" or "off", tostring(TagFS() ~= nil), tostring(realTag ~= nil), #tagOrder,
        M.tagStats.secret, M.tagStats.scans, M.tagStats.applied))
    for _, fs in ipairs(tagOrder) do
        local okN, nm = pcall(fs.GetDebugName, fs)
        local okX, txt = pcall(fs.GetText, fs)
        local shown = okX and IsStr(txt) and txt or "?"
        if realTag and IsStr(shown) and Plain(shown):find(realTag, 1, true) then shown = "(your real tag)" end
        NS.Print(string.format("    %s [%s] -> showing \"%s\"", okN and IsStr(nm) and nm or "?", tagBound[fs], shown))
    end
    NS.Print(string.format("  instant name fixes (target/focus redraws): %d", M.instantFixes or 0))
    local nt = 0
    for _ in pairs(tinted) do nt = nt + 1 end
    NS.Print(string.format("  your name colour: %s   texts tinted now: %d   colours put back on other names: %d",
        s.ownColorOn and "on" or "off", nt, M.colourRestores))
    for _, t in ipairs(CollectTargets()) do
        local ok, txt = pcall(t.fs.GetText, t.fs)
        NS.Print(string.format("    %s -> showing \"%s\"", t.unit, ok and IsStr(txt) and txt or "?"))
    end
    local ok, mine = pcall(UnitName, "player")
    NS.Print("  your real name: " .. (ok and IsStr(mine) and mine or "?")
        .. "   PlayerFrame found: " .. tostring(_G.PlayerFrame ~= nil))
    local heads = {}
    for _, c in ipairs(HEAD_CVARS) do
        local okc, v = pcall(GetCVar, c)
        heads[#heads + 1] = c .. "=" .. tostring(okc and v or "n/a")
    end
    NS.Print("  head-name settings: " .. table.concat(heads, " "))
    local fp = {}
    for c in pairs(FRIENDLY_CVARS) do
        local okc, v = pcall(GetCVar, c)
        if okc and v ~= nil then fp[#fp + 1] = c .. "=" .. tostring(v) end
    end
    if #fp == 0 then fp[1] = "(this client has none of the friendly nameplate settings)" end
    local okd, dist = pcall(GetCVar, "nameplateMaxDistance")
    fp[#fp + 1] = "nameplateMaxDistance=" .. tostring(okd and dist or "n/a") .. " (asked for " .. tostring(S().friendlyRange) .. ")"
    NS.Print(string.format("  friendly names: %s%s   %s", S().friendlyNames and "on" or "off",
        M.friendlyBlocked and " (off in this dungeon/raid)" or "", table.concat(fp, " ")))
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if loaded and loaded("ForeverEnhancedPrivacy") then
        NS.Print("  |cffff9944ForeverEnhancedPrivacy is also loaded|r - turn one of the two off so they don't both swap names.")
    end
end

----------------------------------------------------------------------
-- Settings page
----------------------------------------------------------------------
local function MaskedCount(n) return n == 1 and "1 whisper" or (n .. " whispers") end

function M.Build(page)
    page:Section("Private mode", "On or off right now", { pinned = true })
    page:Check("Private mode is ON", function() return active end,
        function(v) M.SetActive(v, true) end)
    local state = page:Note("")
    table.insert(page.refreshers, function()
        state:SetText(active and (S().allowWhispers
                and "|cffff6666Names and location details are hidden.|r |cffffd100Whispers are allowed (real names).|r"
                or "|cffff6666Names, whispers and location details are hidden.|r")
            or "Everything is showing normally. Turn it on before you go live.")
    end)
    page:Note("Set a key under Game Menu > Options > Key Bindings > Aimbot UI, or type /aprivacy. "
        .. "/aprivacy brb shows the Be right back screen.")

    page:Section("Names", "What other players are called while private")
    page:Cycle("Other players' names become", {
            { "class", "Their class" },
            { "player", "\"Player\"" },
            { "hidden", "Nothing" },
        },
        function() return S().names end,
        function(v) S().names = v; ApplyAll() end)
    page:Check("Unit, party and raid frames", function() return S().frames end,
        function(v) S().frames = v; ApplyAll() end)
    page:Check("Nameplates above heads", function() return S().nameplates end,
        function(v) S().nameplates = v; ApplyAll() end)
    page:Check("Chat names", function() return S().chat end,
        function(v) S().chat = v end)
    page:Check("Hide the names the game draws above heads (including yours)", function() return S().headNames end,
        function(v) S().headNames = v; ApplyAll() end)
    page:Note("This is the game's own \"names above heads\" setting. It is put back when you turn private mode off, "
        .. "log out or reload.")
    page:Check("Show friendly players' names above heads (as their Privacy name)", function() return S().friendlyNames end,
        function(v) S().friendlyNames = v; ApplyAll() end,
        "Turns on the game's friendly nameplates in names-only mode (no health bar) while private mode is on, "
        .. "and swaps each name for the Privacy name you picked above (class, \"Player\" or nothing). "
        .. "Your own name is not shown. Friendly NPC plates stay off. Your nameplate settings are put back "
        .. "when private mode is turned off.")
    page:Slider("Friendly name range (yards)", 20, 100, 1, function() return S().friendlyRange or 60 end,
        function(v) S().friendlyRange = v; ApplyAll() end)
    local rangeNote = page:Note("")
    table.insert(page.refreshers, function()
        local ok, d = pcall(GetCVar, "nameplateMaxDistance")
        rangeNote:SetText("How far away nameplates show while this is on (enemy plates too). The game has its own "
            .. "maximum and uses the lower of the two. The game is using: |cffffffff" .. tostring(ok and d or "?")
            .. "|r yards. Your own range is put back when private mode is turned off.")
    end)
    local fnNote = page:Note("")
    table.insert(page.refreshers, function()
        fnNote:SetText(S().friendlyNames and M.friendlyBlocked
            and "|cffff9944You are in a dungeon or raid:|r the game locks friendly nameplates there, so they stay off until you leave."
            or "In dungeons and raids the game locks friendly nameplates, so they stay off there (names would show).")
    end)
    page:Note("NPCs, pets and creatures keep their names. Names in tooltips and some game menus can't be changed "
        .. "by an addon: see Good to know.")

    page:Section("Your name and BattleTag", "What you show as while private")
    page:Check("Show a name of my choice for me", function() return S().ownNameOn end,
        function(v) S().ownNameOn = v; ApplyAll() end)
    local ownNote = page:Note("")
    table.insert(page.refreshers, function() ownNote:SetText("Your name now shows as: |cffffffff" .. tostring(S().ownName) .. "|r") end)
    page:Input("Type a name and press Enter", function(text)
        S().ownName = text:sub(1, 24)
        ApplyAll()
        if NS.UI.RefreshAll then NS.UI.RefreshAll() end
    end, "Set name")
    page:Check("Show my name in a colour", function() return S().ownColorOn end,
        function(v) S().ownColorOn = v; ApplyAll() end)
    page:Color("My name colour", function() return S().ownColor end,
        function(r, g, b) local c = S().ownColor; c[1], c[2], c[3] = r, g, b; ApplyAll() end)
    page:Check("Show a made-up BattleTag in the friends window", function() return S().tagOn end,
        function(v) S().tagOn = v; ApplyAll() end)
    local tagNote = page:Note("")
    table.insert(page.refreshers, function() tagNote:SetText("Your BattleTag now shows as: |cffffffff" .. tostring(S().tag) .. "|r") end)
    page:Input("Type a BattleTag (like Name#1234) and press Enter", function(text)
        S().tag = text:sub(1, 32)
        ApplyAll()
        if NS.UI.RefreshAll then NS.UI.RefreshAll() end
    end, "Set tag")

    page:Section("Chat", "Whispers and bubbles")
    page:Check("Allow whispers from everyone (real names)", function() return S().allowWhispers end,
        function(v) S().allowWhispers = v; if NS.UI.RefreshAll then NS.UI.RefreshAll() end end,
        "Whispers from everyone (characters and Battle.net friends) show in chat exactly as normal, "
        .. "with the sender's real name, so you can see who it is and reply with R. "
        .. "Their names WILL be visible on stream. Turn this off to hide them again.")
    local allowNote = page:Note("")
    table.insert(page.refreshers, function()
        allowNote:SetText(S().allowWhispers
            and "|cffffd100Whispers are allowed: everyone's whispers show normally, real names included (visible on stream).|r"
            or "Whispers follow the settings below (kept in the inbox, or shown with the sender's name hidden).")
    end)
    page:Check("Keep whispers out of chat (read them later in the inbox)", function() return S().hideWhispers end,
        function(v) S().hideWhispers = v end)
    page:Check("Hide chat bubbles", function() return S().bubbles end,
        function(v) S().bubbles = v; ApplyAll() end)
    page:Note("\"Allow whispers from everyone\" wins over \"Keep whispers out of chat\". "
        .. "Chat only tells you how many whispers are waiting. Your bubble settings are put back when you "
        .. "turn private mode off, log out or reload.")

    page:Section("Whisper inbox", "Hidden whispers wait here")
    local box = page:Container()
    local text = NS.UI.Text(box, "", -1)
    text:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    text:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    function M.RefreshInbox()
        local inbox = S().inbox
        if #inbox == 0 then
            text:SetText("No hidden whispers yet.")
        else
            local lines = {}
            for i = math.max(1, #inbox - 24), #inbox do
                local e = inbox[i]
                local stamp = (date and e.t and e.t > 0) and date("%H:%M", e.t) or "--:--"
                lines[#lines + 1] = string.format("|cff8a8a92%s|r  %s|cffffffff%s|r: %s",
                    stamp, e.out and "to " or "", tostring(e.who), tostring(e.msg))
            end
            text:SetText(table.concat(lines, "\n"))
        end
        local h = text:GetStringHeight()
        box:SetContentHeight((type(h) == "number" and h or 14) + 6)
    end
    table.insert(page.refreshers, M.RefreshInbox)
    M.RefreshInbox()
    page:Button("Clear the inbox", function()
        S().inbox = {}
        M.unread = 0
        M.RefreshInbox()
    end, 160)

    page:Section("Where you are", "Minimap details")
    page:Check("Hide the zone name on the minimap", function() return S().hideZone end,
        function(v) S().hideZone = v; ApplyAll() end)
    page:Check("Hide the clock", function() return S().hideClock end,
        function(v) S().hideClock = v; ApplyAll() end)
    page:Check("Show a small PRIVATE MODE tag on screen", function() return S().indicator end,
        function(v) S().indicator = v; ApplyAll() end)
    page:Note("The tag is a reminder for you, but it will be visible on stream too.")

    page:Section("Be right back", "Cover the whole screen while you step away")
    page:Input("Type your message and press Enter", function(text2)
        S().brbText = text2:sub(1, 60)
        if brb and brb:IsShown() then brb.title:SetText(S().brbText) end
        if NS.UI.RefreshAll then NS.UI.RefreshAll() end
    end, "Set message")
    local brbNote = page:Note("")
    table.insert(page.refreshers, function() brbNote:SetText("Message: |cffffffff" .. tostring(S().brbText) .. "|r") end)
    page:Check("Show how long I've been away", function() return S().brbTimer end,
        function(v) S().brbTimer = v end)
    page:Button("Show / hide the Be right back screen", function() M.SetBRB() end, 280)

    page:Section("Good to know", "Limits")
    page:Note("Things the game does not let an addon change: names in tooltips, the titles of some right-click "
        .. "menus, and some boxes in the friends and guild windows. Cover those with the Be right back screen "
        .. "or keep the windows closed on stream.")
    page:Note("When you type /w and a name, the letters you type show until the chat box switches over.")
    page:Note("Screenshots: the game's own screenshot key does not wait for this addon, so turn private mode "
        .. "on first.")
    page:Note("Changing names on screen is a courtesy for your viewers. It is not a security tool.")
end

M._t = { NameForUnit = NameForUnit, ChatFilter = ChatFilter, Sweep = Sweep, SweepTag = SweepTag,
    DiscoverTag = DiscoverTag, TagKind = TagKind, TagBound = tagBound, TagDriver = tagDriver,
    SweepWhere = SweepWhere, SweepBubbles = SweepBubbles, Slash = Slash, Short = Short,
    PlainReplace = PlainReplace, CollectTargets = CollectTargets, FmtElapsed = FmtElapsed }
