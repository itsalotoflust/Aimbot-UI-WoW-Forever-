--[[
  Aimbot UI - Chat Mute

  Hides chat from people (or whole guilds) you choose, and lets them speak again
  during the times you set. Everything happens on your own client: nobody is added
  to your ignore list and nobody is told.

  This is original code. It was written from the public description of the idea
  (hide chat by guild / name / word, decline invites) and is not copied from any
  other addon.

  How it works
    * Chat is filtered with the normal chat message filters (the same hook every
      chat addon uses). The filter never changes a message, it only hides it.
    * The game does not tell us a sender's guild, so we learn it from players you
      target, mouse over, group with, see on nameplates, or find with /who. The
      learned guilds are remembered between sessions.
    * "Speak times": muted people are heard again inside the windows you set (or,
      in the other mode, muted only inside them). "Let them speak for N minutes"
      opens a one-off window.
    * Anything unclear (a secret value, a missing API) lets the message through.
      The filter never hides something it is not sure about.
]]

local ADDON_NAME, NS = ...
local issecret = NS.IsSecret or function() return false end

local M = {
    name  = "Chat Mute",
    group = "QoL",
    desc  = "Hide chat from players and guilds you choose, add word filters, and set the times "
        .. "they are allowed to speak. Client-side only: nobody is ignored or told.",
    defaults = {
        enabled   = true,
        players   = {},      -- { { name = "Name" or "Name-Realm", always = false } }
        guilds    = {},      -- { { name = "Guild name (any part)", always = false } }
        words     = {},      -- { "text", "wild*card" }
        keepPlayers = {},    -- never mute these names
        keepGuilds  = {},    -- never mute these guilds (exact name)
        keepOwnGuild = true,
        keepFriends  = true,
        keepGroup    = false,
        channels = { say = true, yell = true, emote = true, whisper = true, channel = true,
            guild = true, officer = true, party = true, raid = true, instance = true, battleground = true },
        bubbles = true,
        cleanup = true,
        -- speak times
        mode  = "allow",     -- "allow": muted people speak INSIDE the windows; "mute": they are muted ONLY inside them
        windows = {},        -- { { days = { [1..7] = true }, from = minutes, to = minutes } }   (1 = Sunday)
        clock = "local",     -- "local" or "server"
        allowMinutes = 15,
        allowUntil = 0,      -- epoch seconds; "let them speak until"
        notify = true,
        -- content filters (apply to everyone except your never-mute list)
        spam = false,  spamSeconds = 30,
        caps = false,  capsMin = 12,
        links = false,
        strangers = false,   -- public channels only: hide people who are not friends, guild or group
        -- invites
        declineGuild = true, declineGroup = false, declineDuel = false, declineTrade = false,
        warnGroup = true,
        total = 0,
        cache = {},          -- lower-case name -> { g = "Guild", t = epoch }
    },
}
NS.RegisterModule("mute", M)

local function S() return NS.db.mod.mute end
local function V(v) if issecret(v) then return nil end return v end

local CACHE_MAX = 3000
local session = 0
local LOG_MAX, LOG_SECONDS = 50, 900
M.log = {}

----------------------------------------------------------------------
-- Small helpers (Lua 5.1 safe: no //, no goto, no bit ops)
----------------------------------------------------------------------
local function Trim(s)
    s = tostring(s or ""):gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

local function Lower(s) return (tostring(s or ""):lower()) end

local function SplitAuthor(author)
    local l = Lower(author)
    local n, r = l:match("^([^%-]+)%-(.+)$")
    if n then return n, (r:gsub("%s+", "")) end
    return l, nil
end

local function KeyFor(name, realm)
    local k = Lower(name)
    if type(realm) == "string" and realm ~= "" then k = k .. "-" .. (Lower(realm):gsub("%s+", "")) end
    return k
end

local function KeyFromAuthor(author)
    local n, r = SplitAuthor(author)
    return r and (n .. "-" .. r) or n
end

local function Pretty(name)
    name = Trim(name)
    if name == "" then return name end
    return name:sub(1, 1):upper() .. name:sub(2)
end

local function FmtDur(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%dh %02dm", h, m) end
    if m > 0 then return string.format("%dm %02ds", m, s) end
    return string.format("%ds", s)
end

----------------------------------------------------------------------
-- Speak-time windows: parsing and display
----------------------------------------------------------------------
local DAY_SHORT = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local DAY_BY_NAME = {
    sun = 1, sunday = 1, mon = 2, monday = 2, tue = 3, tues = 3, tuesday = 3,
    wed = 4, weds = 4, wednesday = 4, thu = 5, thur = 5, thurs = 5, thursday = 5,
    fri = 6, friday = 6, sat = 7, saturday = 7,
}
local WEEK_ORDER = { 2, 3, 4, 5, 6, 7, 1 }   -- display Monday first

-- "18:00", "6pm", "6:30 pm", "1800", "18" -> minutes since midnight (0..1440)
local function ParseTime(str)
    str = Lower(Trim(str)):gsub("%s+", "")
    local h, m, ap = str:match("^(%d%d?):(%d%d)([ap]?m?)$")
    if not h then
        h, ap = str:match("^(%d%d?)([ap]m?)$"); m = "0"
    end
    if not h then
        h = str:match("^(%d%d?)$"); m = "0"; ap = ""
    end
    if not h then
        h, m = str:match("^(%d%d)(%d%d)$"); ap = ""
    end
    if not h then return nil, "I can't read '" .. str .. "' as a time. Try 18:00 or 6pm." end
    h, m = tonumber(h), tonumber(m)
    if m > 59 then return nil, "Minutes must be 00-59 in '" .. str .. "'." end
    ap = ap or ""
    if ap ~= "" then
        if h < 1 or h > 12 then return nil, "With am/pm the hour must be 1-12 ('" .. str .. "')." end
        if ap:sub(1, 1) == "a" then if h == 12 then h = 0 end
        else if h < 12 then h = h + 12 end end
    else
        if h > 24 or (h == 24 and m > 0) then return nil, "Hours go from 0 to 24 ('" .. str .. "')." end
    end
    return h * 60 + m
end

local function ParseDays(text)
    text = Lower(Trim(text))
    local days = {}
    local any = false
    local function Add(i) days[i] = true; any = true end
    text = text:gsub("every%s+day", "daily"):gsub("%f[%a]and%f[%A]", " ")
    for tok in text:gmatch("[^,%s/&]+") do
        if tok == "daily" or tok == "everyday" or tok == "every" or tok == "all" or tok == "always" or tok == "day" or tok == "days" then
            for i = 1, 7 do Add(i) end
        elseif tok == "weekdays" or tok == "weekday" then
            for i = 2, 6 do Add(i) end
        elseif tok == "weekends" or tok == "weekend" then
            Add(7); Add(1)
        else
            local a, b = tok:match("^(%a+)%-(%a+)$")
            if a then
                local da, db = DAY_BY_NAME[a], DAY_BY_NAME[b]
                if not da or not db then return nil, "I don't know the days '" .. tok .. "'." end
                local i = da
                for _ = 1, 7 do
                    Add(i)
                    if i == db then break end
                    i = i % 7 + 1
                end
            else
                local d = DAY_BY_NAME[tok]
                if not d then return nil, "I don't know the day '" .. tok .. "'. Use mon, tue, wed... or weekdays." end
                Add(d)
            end
        end
    end
    if not any then for i = 1, 7 do days[i] = true end end   -- no days given = every day
    return days
end

-- "18:00-20:00", "mon-fri 9am-5pm", "sat,sun 14:00 to 18:00", "weekdays 22:00-02:00"
local function ParseWindow(text)
    text = Trim(text):gsub("\226\128\147", "-"):gsub("\226\128\148", "-")   -- en / em dash
    text = text:gsub("%s+[Tt][Oo]%s+", " - ")
    local daysPart, t1, t2 = text:match("^(.-)%s*([%d:]+%s*[AaPp]?[Mm]?)%s*%-%s*([%d:]+%s*[AaPp]?[Mm]?)%s*$")
    if not t1 then
        return nil, "Use a start and an end time, like 18:00-20:00 or mon-fri 9am-5pm."
    end
    local from, e1 = ParseTime(t1)
    if not from then return nil, e1 end
    local to, e2 = ParseTime(t2)
    if not to then return nil, e2 end
    local days, e3 = ParseDays(daysPart or "")
    if not days then return nil, e3 end
    return { days = days, from = from, to = to }
end

local function FmtClock(mins)
    mins = mins % 1440
    return string.format("%02d:%02d", math.floor(mins / 60), mins % 60)
end

local function FmtDays(days)
    local all = true
    for i = 1, 7 do if not days[i] then all = false end end
    if all then return "Every day" end
    -- compress runs (Monday first)
    local out, run = {}, {}
    local function Flush()
        if #run == 0 then return end
        if #run >= 3 then out[#out + 1] = DAY_SHORT[run[1]] .. "-" .. DAY_SHORT[run[#run]]
        else for _, d in ipairs(run) do out[#out + 1] = DAY_SHORT[d] end end
        run = {}
    end
    for _, d in ipairs(WEEK_ORDER) do
        if days[d] then run[#run + 1] = d else Flush() end
    end
    Flush()
    return #out > 0 and table.concat(out, ", ") or "No days"
end

local function FmtWindow(w)
    local to = (w.to == 1440) and "24:00" or FmtClock(w.to)
    local span = (w.from == w.to) and "all day" or (FmtClock(w.from) .. " - " .. to)
    return FmtDays(w.days) .. "  " .. span
end

----------------------------------------------------------------------
-- Rebuilt lookup tables (cheap to read from inside the chat filter)
----------------------------------------------------------------------
local idx = { players = {}, guilds = {}, words = {}, keepPlayers = {}, keepGuilds = {}, windows = {} }
local ownGuild, playerLower          -- lower-case

local function Rebuild()
    local s = S()
    idx.players, idx.guilds, idx.words, idx.keepPlayers, idx.keepGuilds, idx.windows = {}, {}, {}, {}, {}, {}
    for _, e in ipairs(s.players) do
        if type(e) == "table" and type(e.name) == "string" and e.name ~= "" then
            local n, r = SplitAuthor(e.name)
            idx.players[#idx.players + 1] = { n = n, r = r, always = e.always and true or false }
        end
    end
    for _, e in ipairs(s.guilds) do
        if type(e) == "table" and type(e.name) == "string" and Trim(e.name) ~= "" then
            idx.guilds[#idx.guilds + 1] = { t = Lower(Trim(e.name)), always = e.always and true or false }
        end
    end
    for _, w in ipairs(s.words) do
        if type(w) == "string" and Trim(w) ~= "" then
            local l = Lower(Trim(w))
            if l:find("*", 1, true) then
                local pat = l:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*")
                idx.words[#idx.words + 1] = { pat = pat }
            else
                idx.words[#idx.words + 1] = { t = l }
            end
        end
    end
    for _, p in ipairs(s.keepPlayers) do
        if type(p) == "string" and p ~= "" then
            local n, r = SplitAuthor(p)
            idx.keepPlayers[#idx.keepPlayers + 1] = { n = n, r = r }
        end
    end
    for _, g in ipairs(s.keepGuilds) do
        if type(g) == "string" and g ~= "" then idx.keepGuilds[#idx.keepGuilds + 1] = Lower(Trim(g)) end
    end
    for _, w in ipairs(s.windows) do
        if type(w) == "table" and type(w.days) == "table" and type(w.from) == "number" and type(w.to) == "number" then
            idx.windows[#idx.windows + 1] = w
        end
    end
end

----------------------------------------------------------------------
-- Time and the speak-time state
----------------------------------------------------------------------
-- Returns weekday (1 = Sunday) and minutes since midnight, local or server time.
local function ClockNow()
    if M._clock then return M._clock() end
    if S().clock == "server" and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
        local ok, t = pcall(C_DateAndTime.GetCurrentCalendarTime)
        if ok and type(t) == "table" and type(t.weekday) == "number" and type(t.hour) == "number" then
            return t.weekday, t.hour * 60 + (t.minute or 0)
        end
    end
    local t = date("*t")
    return t.wday, t.hour * 60 + t.min
end

local function InWindow(w, wday, mins)
    local from, to = w.from, w.to
    if from == to then return w.days[wday] and true or false end        -- same time twice = the whole day
    if from < to then return (w.days[wday] and mins >= from and mins < to) and true or false end
    -- crosses midnight: the part after midnight belongs to the day before
    if mins >= from then return w.days[wday] and true or false end
    if mins < to then return w.days[(wday + 5) % 7 + 1] and true or false end
    return false
end

-- What the schedule alone says (no manual override): can muted people speak?
local function SpeakAt(wday, mins)
    local inside = false
    for _, w in ipairs(idx.windows) do
        if InWindow(w, wday, mins) then inside = true; break end
    end
    if S().mode == "mute" then return not inside end
    return inside
end

local stateSec, stateSpeak, stateWhy
local function State()
    local now = time()
    if now == stateSec then return stateSpeak, stateWhy end
    local s = S()
    local speak, why
    if (s.allowUntil or 0) > now then
        speak, why = true, "manual"
    else
        local wday, mins = ClockNow()
        speak = SpeakAt(wday, mins)
        if #idx.windows == 0 then
            why = (s.mode == "mute") and "nowindows-mute" or "nowindows-allow"
        elseif s.mode == "mute" then
            why = speak and "outside" or "inside"
        else
            why = speak and "inside" or "outside"
        end
    end
    stateSec, stateSpeak, stateWhy = now, speak, why
    return speak, why
end

-- Minutes until the schedule next flips (ignores the manual override). Returns steps, weekday, minute.
local function NextChange()
    if #idx.windows == 0 then return nil end
    local wday, mins = ClockNow()
    local cur = SpeakAt(wday, mins)
    for step = 1, 7 * 24 * 60 do
        mins = mins + 1
        if mins >= 1440 then mins = 0; wday = wday % 7 + 1 end
        if SpeakAt(wday, mins) ~= cur then return step, wday, mins end
    end
end

----------------------------------------------------------------------
-- Guild knowledge
----------------------------------------------------------------------
local function CacheCount()
    local n = 0
    for _ in pairs(S().cache) do n = n + 1 end
    return n
end

local function Prune()
    local c = S().cache
    local list = {}
    for k, e in pairs(c) do list[#list + 1] = { k = k, t = type(e) == "table" and e.t or 0 } end
    if #list <= CACHE_MAX then return end
    table.sort(list, function(a, b) return a.t > b.t end)
    for i = CACHE_MAX - math.floor(CACHE_MAX / 5) + 1, #list do c[list[i].k] = nil end
end

local storedSincePrune = 0
-- Returns true when this was new or changed.
local function Store(key, guild)
    local c = S().cache
    local e = c[key]
    local now = time()
    if e and e.g == guild then
        if now - (e.t or 0) > 86400 then e.t = now end
        return false
    end
    c[key] = { g = guild, t = now }
    storedSincePrune = storedSincePrune + 1
    if storedSincePrune >= 200 then storedSincePrune = 0; Prune() end
    return true
end

local function GuildFor(an, ar)
    local c = S().cache
    local e = (ar and c[an .. "-" .. ar]) or c[an]
    if e then return e.g end
end

----------------------------------------------------------------------
-- Who is muted?
----------------------------------------------------------------------
local function SamePerson(entry, an, ar)
    return entry.n == an and (entry.r == nil or ar == nil or entry.r == ar)
end

-- Returns the rule that matches this person (a player or a guild entry), and its kind.
local function PersonRule(an, ar, guild)
    for _, p in ipairs(idx.players) do
        if SamePerson(p, an, ar) then return p, "player" end
    end
    if guild and guild ~= "" then
        local gl = Lower(guild)
        for _, g in ipairs(idx.guilds) do
            if gl:find(g.t, 1, true) then return g, "guild" end
        end
    end
end

local function InGroupName(name)
    if type(name) ~= "string" or name == "" then return false end
    -- Chat names are stored lowercase; the game's own spelling is Capitalised.
    local cap = name:sub(1, 1):upper() .. name:sub(2)
    for _, fn in ipairs({ UnitInParty, UnitInRaid }) do
        if fn then
            for _, nm in ipairs({ cap, name }) do
                local ok, v = pcall(fn, nm)
                if ok and not issecret(v) and v then return true end
            end
        end
    end
    -- Fall back to reading the roster, which does not care about spelling.
    local count = GetNumGroupMembers and V(GetNumGroupMembers()) or 0
    if type(count) == "number" and count > 0 then
        local raid = IsInRaid and V(IsInRaid())
        for i = 1, math.min(count, 40) do
            local unit = raid and ("raid" .. i) or (i < count and ("party" .. i) or nil)
            if unit then
                local ok, n = pcall(UnitName, unit)
                n = ok and V(n) or nil
                if type(n) == "string" and Lower(n) == name then return true end
            end
        end
    end
    return false
end

local function IsFriendGuid(guid)
    if C_FriendList and C_FriendList.IsFriend then
        local ok, v = pcall(C_FriendList.IsFriend, guid)
        if ok and not issecret(v) and v == true then return true end
    end
    if C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
        local ok, v = pcall(C_BattleNet.GetAccountInfoByGUID, guid)
        if ok and not issecret(v) and type(v) == "table" then return true end
    end
    return false
end

-- "Someone I know": friend, guild mate or group member. Unknown cases count as known.
local function IsKnown(an, guid)
    if not guid then return true end
    if IsFriendGuid(guid) then return true end
    if IsGuildMember then
        local ok, v = pcall(IsGuildMember, guid)
        if ok and not issecret(v) and v then return true end
    end
    if InGroupName(an) then return true end
    return false
end

local function IsKept(an, ar, guid, guild)
    local s = S()
    for _, k in ipairs(idx.keepPlayers) do
        if SamePerson(k, an, ar) then return true end
    end
    if guild and guild ~= "" then
        local gl = Lower(Trim(guild))
        for _, g in ipairs(idx.keepGuilds) do
            if g == gl then return true end
        end
        if s.keepOwnGuild and ownGuild and gl == ownGuild then return true end
    end
    if s.keepFriends and guid and IsFriendGuid(guid) then return true end
    if s.keepGroup and InGroupName(an) then return true end
    return false
end

----------------------------------------------------------------------
-- Content filters
----------------------------------------------------------------------
local function Plain(msg)
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    return msg
end

local TLDS = { "com", "net", "org", "gg", "io", "tv", "ru", "cn", "xyz", "shop", "store" }
local function HasLink(plain)
    local l = plain:lower()
    if l:find("https?://") or l:find("www%.") then return true end
    for _, t in ipairs(TLDS) do
        if l:find("[%w%-]%." .. t .. "%f[%A]") then return true end
    end
    return false
end

local function IsShouting(plain, minLetters)
    local letters, upper = 0, 0
    for c in plain:gmatch("%a") do
        letters = letters + 1
        if c:upper() == c then upper = upper + 1 end
    end
    return letters >= minLetters and upper / letters >= 0.7
end

local seen, seenCount = {}, 0
local function IsRepeat(an, lmsg, seconds)
    local now = GetTime()
    local key = an .. "\1" .. lmsg
    local t = seen[key]
    seen[key] = now
    if not t then
        seenCount = seenCount + 1
        if seenCount > 400 then
            for k, v in pairs(seen) do if now - v > seconds then seen[k] = nil end end
            seenCount = 0
            for _ in pairs(seen) do seenCount = seenCount + 1 end
        end
        return false
    end
    return (now - t) < seconds
end

local PUBLIC = { say = true, yell = true, emote = true, channel = true }

----------------------------------------------------------------------
-- The decision
----------------------------------------------------------------------
-- Returns hide (boolean) and why ("player", "guild", "word", "spam", "caps", "link", "stranger").
local function Decide(cat, msg, author, guid)
    local s = S()
    local an, ar = SplitAuthor(author)
    if playerLower and an == playerLower then return false end
    local guild = GuildFor(an, ar)
    local why

    local rule, kind = PersonRule(an, ar, guild)
    if rule and (rule.always or not (State())) then why = kind end

    if not why and #idx.words > 0 then
        local lmsg = msg:lower()
        for _, w in ipairs(idx.words) do
            if (w.pat and lmsg:find(w.pat)) or (w.t and lmsg:find(w.t, 1, true)) then why = "word"; break end
        end
    end
    if not why and (s.links or s.caps) then
        local plain = Plain(msg)
        if s.links and HasLink(plain) then why = "link"
        elseif s.caps and IsShouting(plain, s.capsMin or 12) then why = "caps" end
    end
    if not why and s.spam and IsRepeat(an, msg:lower(), s.spamSeconds or 30) then why = "spam" end
    if not why and s.strangers and PUBLIC[cat] and not IsKnown(an, guid) then why = "stranger" end

    if why and IsKept(an, ar, guid, guild) then return false end
    return why ~= nil, why
end

----------------------------------------------------------------------
-- Chat bubbles (open world only; instance bubbles are secret)
----------------------------------------------------------------------
local bubbleNotes, bubbleHidden, bubbleTicker = {}, setmetatable({}, { __mode = "k" }), nil

local function BubbleText(b)
    local ok, text = pcall(function()
        for _, kid in ipairs({ b:GetChildren() }) do
            if kid.GetRegions then
                for _, r in ipairs({ kid:GetRegions() }) do
                    if r.GetText then
                        local t = r:GetText()
                        if type(t) == "string" then return t end
                    end
                end
            end
        end
    end)
    if ok and type(text) == "string" and not issecret(text) then return text end
end

local function RestoreBubbles()
    for b in pairs(bubbleHidden) do pcall(b.SetAlpha, b, 1); bubbleHidden[b] = nil end
end

local function ScanBubbles()
    local now = GetTime()
    for i = #bubbleNotes, 1, -1 do
        if now - bubbleNotes[i].t > 15 then table.remove(bubbleNotes, i) end
    end
    local get = C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles
    if get and #bubbleNotes > 0 then
        local ok, list = pcall(get)
        if ok and type(list) == "table" then
            for _, b in ipairs(list) do
                local text = BubbleText(b)
                local hit = false
                if text then
                    for _, n in ipairs(bubbleNotes) do
                        if text == n.msg or text:find(n.msg, 1, true) then hit = true; break end
                    end
                end
                if hit then
                    bubbleHidden[b] = true
                    pcall(b.SetAlpha, b, 0)
                elseif bubbleHidden[b] then
                    bubbleHidden[b] = nil
                    pcall(b.SetAlpha, b, 1)
                end
            end
        end
    end
    if #bubbleNotes == 0 then
        RestoreBubbles()
        if bubbleTicker then bubbleTicker:Cancel(); bubbleTicker = nil end
    end
end

local function NoteBubble(msg)
    bubbleNotes[#bubbleNotes + 1] = { msg = msg, t = GetTime() }
    if not bubbleTicker and C_Timer and C_Timer.NewTicker then
        bubbleTicker = C_Timer.NewTicker(0.1, ScanBubbles)
    end
end

----------------------------------------------------------------------
-- Removing a newly identified player's earlier lines
----------------------------------------------------------------------
local pendingClean, cleanScheduled = {}, false
local function RunCleanup()
    cleanScheduled = false
    local set = pendingClean
    pendingClean = {}
    if next(set) == nil then return end
    local function pred(message)
        if type(message) ~= "string" or issecret(message) then return false end
        local l = message:lower()
        for name in pairs(set) do
            local a, e = l:find("|hplayer:" .. name, 1, true)
            if a then
                local nx = l:sub(e + 1, e + 1)
                if nx == ":" or nx == "-" then return true end
            end
        end
        return false
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f and f.RemoveMessagesByPredicate then pcall(f.RemoveMessagesByPredicate, f, pred) end
    end
end

local function QueueCleanup(an)
    if not S().cleanup then return end
    pendingClean[an] = true
    if not cleanScheduled and C_Timer and C_Timer.After then
        cleanScheduled = true
        C_Timer.After(0.4, RunCleanup)
    end
end

----------------------------------------------------------------------
-- The chat filter
----------------------------------------------------------------------
local EVENT_CAT = {
    CHAT_MSG_SAY = "say", CHAT_MSG_YELL = "yell",
    CHAT_MSG_EMOTE = "emote", CHAT_MSG_TEXT_EMOTE = "emote",
    CHAT_MSG_WHISPER = "whisper",
    CHAT_MSG_CHANNEL = "channel",
    CHAT_MSG_GUILD = "guild", CHAT_MSG_OFFICER = "officer",
    CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid", CHAT_MSG_RAID_WARNING = "raid",
    CHAT_MSG_INSTANCE_CHAT = "instance", CHAT_MSG_INSTANCE_CHAT_LEADER = "instance",
    CHAT_MSG_BATTLEGROUND = "battleground", CHAT_MSG_BATTLEGROUND_LEADER = "battleground",
}

local function AddLog(author, msg, why)
    local now = time()
    local log = M.log
    log[#log + 1] = { t = now, who = author, text = msg, why = why }
    while #log > LOG_MAX or (log[1] and now - log[1].t > LOG_SECONDS) do table.remove(log, 1) end
end

local lastLine, lastHide
local function ChatFilter(_, event, msg, author, _, _, _, _, _, _, _, _, lineID, guid)
    if not NS.db then return false end
    local s = S()
    if not s.enabled then return false end
    local cat = EVENT_CAT[event]
    if not cat or not s.channels[cat] then return false end
    if type(msg) ~= "string" or type(author) ~= "string" or issecret(msg) or issecret(author) or author == "" then
        return false
    end
    local line = (type(lineID) == "number" and not issecret(lineID)) and lineID or nil
    if line and line == lastLine then return lastHide end          -- same message, another chat tab
    if type(guid) ~= "string" or issecret(guid) then guid = nil end

    local ok, hide, why = pcall(Decide, cat, msg, author, guid)
    if not ok then
        NS.ReportError("Chat Mute filter", hide)
        hide = false
    end
    hide = hide and true or false
    if line then lastLine, lastHide = line, hide end
    if hide then
        session = session + 1
        s.total = (s.total or 0) + 1
        AddLog(author, msg, why)
        if s.bubbles and (cat == "say" or cat == "yell") then NoteBubble(msg) end
    end
    return hide
end

----------------------------------------------------------------------
-- Learning guilds
----------------------------------------------------------------------
local function AfterLearn(name, realm, guild)
    local an, ar = Lower(name), realm and (Lower(realm):gsub("%s+", "")) or nil
    if ar == "" then ar = nil end
    local rule = PersonRule(an, ar, guild)
    if rule and not IsKept(an, ar, nil, guild) and (rule.always or not (State())) then
        QueueCleanup(an)
    end
end

local function LearnUnit(unit)
    local s = S()
    if not s.enabled then return end
    if not V(UnitExists(unit)) or not V(UnitIsPlayer(unit)) then return end
    if V(UnitIsUnit(unit, "player")) then return end
    local name, realm = UnitName(unit)
    name, realm = V(name), V(realm)
    if type(name) ~= "string" or name == "" then return end
    local guild = V(GetGuildInfo(unit))
    if type(guild) ~= "string" or guild == "" then return end      -- unknown is not "no guild"
    if Store(KeyFor(name, realm), guild) then AfterLearn(name, realm, guild) end
end

local function LearnWho()
    local fl = C_FriendList
    if not (fl and fl.GetNumWhoResults and fl.GetWhoInfo) then return end
    local okn, n = pcall(fl.GetNumWhoResults)
    n = okn and V(n) or 0
    if type(n) ~= "number" then return end
    for i = 1, math.min(n, 50) do
        local ok, info = pcall(fl.GetWhoInfo, i)
        if ok and type(info) == "table" and not issecret(info) then
            local full, guild = V(info.fullName), V(info.fullGuildName)
            if type(full) == "string" and full ~= "" and type(guild) == "string" then
                local an, ar = SplitAuthor(full)
                if an ~= playerLower then
                    local key = ar and (an .. "-" .. ar) or an
                    if guild == "" then
                        S().cache[key] = nil            -- they left their guild: no longer muted by guild
                    elseif Store(key, guild) then
                        AfterLearn(an, ar, guild)
                    end
                end
            end
        end
    end
end

local warned = {}
local function LearnGroup()
    local s = S()
    if not s.enabled then return end
    local count = GetNumGroupMembers and V(GetNumGroupMembers()) or 0
    if type(count) ~= "number" or count == 0 then
        for k in pairs(warned) do warned[k] = nil end
        return
    end
    local raid = IsInRaid and V(IsInRaid())
    local units = {}
    if raid then
        for i = 1, math.min(count, 40) do units[#units + 1] = "raid" .. i end
    else
        for i = 1, math.min(count - 1, 4) do units[#units + 1] = "party" .. i end
    end
    for _, u in ipairs(units) do
        LearnUnit(u)
        if s.warnGroup and V(UnitExists(u)) then
            local name, realm = UnitName(u)
            name, realm = V(name), V(realm)
            if type(name) == "string" and name ~= "" then
                local an = Lower(name)
                local ar = (type(realm) == "string" and realm ~= "") and (Lower(realm):gsub("%s+", "")) or nil
                local key = KeyFor(name, realm)
                local guild = GuildFor(an, ar)
                local rule, kind = PersonRule(an, ar, guild)
                if rule and not warned[key] and not IsKept(an, ar, nil, guild) then
                    warned[key] = true
                    NS.Print(string.format("Chat Mute: |cffffaa33%s|r%s is in your group and is on your mute list.",
                        name, (kind == "guild" and guild) and (" <" .. guild .. ">") or ""))
                end
            end
        end
    end
end

local function RefreshOwn()
    local n = V(UnitName("player"))
    if type(n) == "string" then playerLower = Lower(n) end
    local g = V(GetGuildInfo("player"))
    ownGuild = (type(g) == "string" and g ~= "") and Lower(Trim(g)) or nil
end

----------------------------------------------------------------------
-- Invites
----------------------------------------------------------------------
local function Muted(name, guild)
    local s = S()
    if not s.enabled then return false end
    name, guild = V(name), V(guild)
    if type(name) ~= "string" then name = nil end
    if type(guild) ~= "string" then guild = nil end
    local an, ar
    if name then
        an, ar = SplitAuthor(name)
        guild = guild or GuildFor(an, ar)
    end
    local rule
    if an then rule = PersonRule(an, ar, guild)
    elseif guild then
        local gl = Lower(guild)
        for _, g in ipairs(idx.guilds) do
            if gl:find(g.t, 1, true) then rule = g; break end
        end
    end
    if not rule then return false end
    if an and IsKept(an, ar, nil, guild) then return false end
    return true
end

local function Hide(which) if StaticPopup_Hide then pcall(StaticPopup_Hide, which) end end

local function OnInvite(event, ...)
    local s = S()
    if not s.enabled then return end
    if event == "PARTY_INVITE_REQUEST" and s.declineGroup then
        local name, guid = ...
        guid = select(8, ...)
        if Muted(name) then
            if DeclineGroup then pcall(DeclineGroup)
            elseif C_PartyInfo and C_PartyInfo.DeclineInvite then pcall(C_PartyInfo.DeclineInvite, V(guid)) end
            Hide("PARTY_INVITE")
        end
    elseif event == "GUILD_INVITE_REQUEST" and s.declineGuild then
        local inviter, guildName = ...
        if Muted(inviter, guildName) or Muted(nil, guildName) then
            if DeclineGuild then pcall(DeclineGuild) end
            Hide("GUILD_INVITE")
        end
    elseif event == "DUEL_REQUESTED" and s.declineDuel then
        if Muted((...)) then
            if CancelDuel then pcall(CancelDuel) end
            Hide("DUEL_REQUESTED")
        end
    elseif event == "TRADE_REQUEST" and s.declineTrade then
        if Muted((...)) then
            if CancelTrade then pcall(CancelTrade) end
            Hide("TRADE")
        end
    end
end

----------------------------------------------------------------------
-- Editing the lists
----------------------------------------------------------------------
local function Msg(text) NS.Print("Chat Mute: " .. text) end
local function Changed()
    stateSec = nil
    Rebuild()
    if M.RefreshPage then M.RefreshPage() end
end

local function IndexOfName(list, name)
    local l = Lower(name)
    for i, e in ipairs(list) do
        local n = type(e) == "table" and e.name or e
        if type(n) == "string" and Lower(n) == l then return i end
    end
end

function M.AddPlayer(text)
    text = Trim(text)
    if text == "" or text:find("%s") then
        Msg("type one player name, like Name or Name-Realm."); return false
    end
    if #text < 2 then Msg("that name is too short."); return false end
    local s = S()
    if IndexOfName(s.players, text) then Msg(Pretty(text) .. " is already muted."); return true end
    s.players[#s.players + 1] = { name = Pretty(text), always = false }
    Changed()
    local an, ar = SplitAuthor(text)
    QueueCleanup(an)
    Msg(Pretty(text) .. " muted.")
    return true
end

function M.AddGuild(text)
    text = Trim(text)
    text = text:gsub("^<", ""):gsub(">$", "")
    text = Trim(text)
    if #text < 2 then Msg("type at least two letters of the guild name."); return false end
    local s = S()
    if IndexOfName(s.guilds, text) then Msg("that guild is already on the list."); return true end
    s.guilds[#s.guilds + 1] = { name = text, always = false }
    Changed()
    Msg("guild '" .. text .. "' muted (any guild whose name contains it).")
    return true
end

function M.AddWord(text)
    text = Trim(text)
    if #text < 2 then Msg("type a word or phrase (use * as a wildcard)."); return false end
    local s = S()
    if IndexOfName(s.words, text) then Msg("that word is already on the list."); return true end
    s.words[#s.words + 1] = text
    Changed()
    return true
end

function M.AddKeepPlayer(text)
    text = Trim(text)
    if text == "" or text:find("%s") then Msg("type one player name."); return false end
    local s = S()
    if IndexOfName(s.keepPlayers, text) then return true end
    s.keepPlayers[#s.keepPlayers + 1] = Pretty(text)
    Changed()
    return true
end

function M.AddKeepGuild(text)
    text = Trim(text):gsub("^<", ""):gsub(">$", "")
    text = Trim(text)
    if #text < 2 then Msg("type the exact guild name."); return false end
    local s = S()
    if IndexOfName(s.keepGuilds, text) then return true end
    s.keepGuilds[#s.keepGuilds + 1] = text
    Changed()
    return true
end

function M.AddWindow(text)
    local w, err = ParseWindow(text)
    if not w then
        if M.winErr then M.winErr:SetText(err) end
        Msg(err)
        return false
    end
    if M.winErr then M.winErr:SetText("") end
    local s = S()
    s.windows[#s.windows + 1] = w
    Changed()
    Msg("speak time added: " .. FmtWindow(w))
    return true
end

local function TargetPlayer()
    if not V(UnitExists("target")) or not V(UnitIsPlayer("target")) then
        Msg("target a player first."); return nil
    end
    local name, realm = UnitName("target")
    name, realm = V(name), V(realm)
    if type(name) ~= "string" or name == "" then Msg("can't read the target's name right now."); return nil end
    return name, realm
end

function M.MuteTarget()
    local name, realm = TargetPlayer()
    if not name then return end
    if V(UnitIsUnit("target", "player")) then Msg("that's you."); return end
    M.AddPlayer(name .. ((type(realm) == "string" and realm ~= "") and ("-" .. realm:gsub("%s+", "")) or ""))
end

function M.MuteTargetGuild()
    local name = TargetPlayer()
    if not name then return end
    local guild = V(GetGuildInfo("target"))
    if type(guild) ~= "string" or guild == "" then Msg(name .. " has no guild (or it hasn't loaded yet)."); return end
    if ownGuild and Lower(guild) == ownGuild then Msg("that's your own guild."); return end
    M.AddGuild(guild)
end

function M.ImportIgnores()
    local fl = C_FriendList
    local getN = (fl and fl.GetNumIgnores) or GetNumIgnores
    local getName = (fl and fl.GetIgnoreName) or GetIgnoreName
    if not (getN and getName) then Msg("can't read your ignore list on this client."); return end
    local added = 0
    local ok, n = pcall(getN)
    n = ok and V(n) or 0
    for i = 1, (type(n) == "number" and n or 0) do
        local ok2, name = pcall(getName, i)
        name = ok2 and V(name) or nil
        if type(name) == "string" and name ~= "" and not IndexOfName(S().players, name) then
            S().players[#S().players + 1] = { name = Pretty(name), always = true }
            added = added + 1
        end
    end
    Changed()
    Msg(string.format("added %d player(s) from your ignore list (they stay muted at all times).", added))
end

function M.AllowFor(minutes)
    minutes = math.max(1, math.floor(tonumber(minutes) or S().allowMinutes or 15))
    S().allowUntil = time() + minutes * 60
    stateSec = nil
    Msg(string.format("muted people can speak for %d minute(s).", minutes))
    if M.RefreshPage then M.RefreshPage() end
end

function M.StopAllow()
    S().allowUntil = 0
    stateSec = nil
    Msg("muted people are muted again.")
    if M.RefreshPage then M.RefreshPage() end
end

function M.ForgetGuilds()
    S().cache = {}
    Changed()
    Msg("forgot every learned guild. They will be learned again as you meet people.")
end

----------------------------------------------------------------------
-- Slash command  /amute
----------------------------------------------------------------------
local function Slash(msg)
    if not NS.db then return end
    msg = Trim(msg)
    local a, rest = msg:match("^(%S*)%s*(.*)$")
    a = Lower(a)
    if a == "" then NS.UI.Show("mute"); return end
    if a == "target" or a == "t" then M.MuteTarget()
    elseif a == "guild" or a == "g" then M.MuteTargetGuild()
    elseif a == "allow" or a == "speak" then M.AllowFor(tonumber(rest))
    elseif a == "stop" or a == "mute" then M.StopAllow()
    elseif a == "on" then S().enabled = true; NS.ApplyModule("mute"); Msg("ON")
    elseif a == "off" then S().enabled = false; NS.ApplyModule("mute"); Msg("OFF")
    elseif a == "status" then
        for line in M.StatusText():gmatch("[^\n]+") do NS.Print(line) end
    elseif a == "unmute" or a == "remove" then
        local i = IndexOfName(S().players, rest)
        if i then table.remove(S().players, i); Changed(); Msg(Pretty(rest) .. " unmuted.")
        else Msg(rest .. " is not on the player list.") end
    else
        M.AddPlayer(msg)
    end
    if NS.UI and NS.UI.RefreshAll then NS.UI.RefreshAll() end
end

----------------------------------------------------------------------
-- Status text
----------------------------------------------------------------------
local function WhyText(why, s)
    if why == "manual" then
        return string.format("(you allowed it, %s left)", FmtDur((s.allowUntil or 0) - time()))
    elseif why == "inside" then
        return s.mode == "mute" and "(inside a mute time)" or "(inside a speak time)"
    elseif why == "outside" then
        return s.mode == "mute" and "(outside your mute times)" or "(outside your speak times)"
    elseif why == "nowindows-allow" then
        return "(no speak times set, so they stay muted)"
    elseif why == "nowindows-mute" then
        return "(no mute times set, so nobody is muted)"
    end
    return ""
end

function M.StatusText()
    local s = S()
    if not s.enabled then return "Chat Mute is OFF. Turn on the switch at the top of this tab." end
    stateSec = nil
    local speak, why = State()
    local lines = {}
    local people = #idx.players + #idx.guilds
    if people == 0 then
        lines[1] = "Nobody is on your mute lists yet. Add a player or a guild in the areas below."
    elseif speak then
        lines[1] = "|cff55ff55Muted people can speak right now|r  " .. WhyText(why, s)
    else
        lines[1] = "|cffff6666Muted people are muted right now|r  " .. WhyText(why, s)
    end
    if people > 0 then
        if why == "manual" then
            lines[2] = "Your one-off allowance ends in " .. FmtDur(s.allowUntil - time()) .. ", then the speak times apply again."
        else
            local steps, wday, mins = NextChange()
            if steps then
                lines[2] = string.format("Next change: %s %s  (in %s)", DAY_SHORT[wday], FmtClock(mins), FmtDur(steps * 60))
            end
        end
    end
    lines[#lines + 1] = string.format("Hidden this session: %d     all time: %d     learned guilds: %d",
        session, s.total or 0, CacheCount())
    return table.concat(lines, "\n")
end

----------------------------------------------------------------------
-- Module hooks
----------------------------------------------------------------------
local lastNotified
local function Tick()
    if not NS.db then return end
    local s = S()
    if not s.enabled then lastNotified = nil; return end
    local speak = State()
    if lastNotified ~= nil and speak ~= lastNotified and s.notify and (#idx.players + #idx.guilds) > 0 then
        Msg(speak and "muted people can speak now." or "muted people are muted again.")
        if M.RefreshPage then M.RefreshPage() end
    end
    lastNotified = speak
end

function M:Apply()
    stateSec = nil
    Rebuild()
    RefreshOwn()
    if not S().enabled then RestoreBubbles() end
    if M.RefreshPage then M.RefreshPage() end
end

function M:Init()
    Rebuild()
    RefreshOwn()

    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if add then
        for event in pairs(EVENT_CAT) do pcall(add, event, ChatFilter) end
        M.filtersAdded = true
    end

    NS.On("PLAYER_TARGET_CHANGED", function() LearnUnit("target") end)
    NS.On("PLAYER_FOCUS_CHANGED", function() LearnUnit("focus") end)
    NS.On("UPDATE_MOUSEOVER_UNIT", function() LearnUnit("mouseover") end)
    NS.On("NAME_PLATE_UNIT_ADDED", function(_, unit) if type(unit) == "string" then LearnUnit(unit) end end)
    NS.On("GROUP_ROSTER_UPDATE", LearnGroup)
    NS.On("WHO_LIST_UPDATE", function() if S().enabled then LearnWho() end end)
    NS.On("PLAYER_LOGIN", function() RefreshOwn(); stateSec = nil end)
    NS.On("PLAYER_GUILD_UPDATE", RefreshOwn)
    NS.On("PLAYER_ENTERING_WORLD", RefreshOwn)
    for _, ev in ipairs({ "PARTY_INVITE_REQUEST", "GUILD_INVITE_REQUEST", "DUEL_REQUESTED", "TRADE_REQUEST" }) do
        NS.On(ev, OnInvite)
    end

    SLASH_AIMBOTMUTE1 = "/amute"
    SlashCmdList["AIMBOTMUTE"] = Slash

    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(10, Tick) end
end

function M:Diagnose()
    local s = S()
    NS.Print(string.format("  filters registered: %s   enabled: %s", tostring(M.filtersAdded), tostring(s.enabled)))
    NS.Print(string.format("  muted players: %d   muted guilds: %d   words: %d   never-mute: %d players, %d guilds",
        #idx.players, #idx.guilds, #idx.words, #idx.keepPlayers, #idx.keepGuilds))
    NS.Print(string.format("  speak times: %d   mode: %s   clock: %s", #idx.windows, tostring(s.mode), tostring(s.clock)))
    local speak, why = State()
    NS.Print("  muted people can speak right now: " .. tostring(speak) .. " (" .. tostring(why) .. ")")
    NS.Print(string.format("  learned guilds: %d   hidden this session: %d   all time: %d", CacheCount(), session, s.total or 0))
    NS.Print(string.format("  API: chat bubbles=%s  remove-old-lines=%s  who=%s",
        tostring(C_ChatBubbles ~= nil and C_ChatBubbles.GetAllChatBubbles ~= nil),
        tostring(ChatFrame1 ~= nil and ChatFrame1.RemoveMessagesByPredicate ~= nil),
        tostring(C_FriendList ~= nil and C_FriendList.GetWhoInfo ~= nil)))
    local others = {}
    for _, n in ipairs({ "OlympusMute" }) do
        local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)
        if loaded and loaded(n) then others[#others + 1] = n end
    end
    if #others > 0 then
        NS.Print("  |cffff9944also loaded: " .. table.concat(others, ", ") .. "|r (both will hide chat; that is harmless but redundant)")
    end
end

-- test hooks
M._t = {
    ParseWindow = ParseWindow, ParseTime = ParseTime, ParseDays = ParseDays, FmtWindow = FmtWindow,
    Decide = Decide, Rebuild = Rebuild, State = State, NextChange = NextChange, Store = Store,
    ChatFilter = ChatFilter, LearnUnit = LearnUnit, LearnWho = LearnWho, SpeakAt = SpeakAt,
    ResetState = function() stateSec = nil end, OnInvite = OnInvite, Muted = Muted,
    SetOwn = function(name, guild) playerLower = name and Lower(name); ownGuild = guild and Lower(guild) end,
    Session = function() return session end, RunCleanup = RunCleanup, ScanBubbles = ScanBubbles,
}

----------------------------------------------------------------------
-- Settings page
----------------------------------------------------------------------
-- A list of rows inside one card. cfg: items(), text(e), toggleText(e)?, onToggle(e)?, onRemove(i, e)?, empty
local function MakeList(page, cfg)
    local L = { rows = {} }
    L.box = page:Container()
    L.emptyText = NS.UI.Text(L.box, cfg.empty or "Nothing here yet.", -1, 0.62, 0.62, 0.67)
    L.emptyText:SetPoint("TOPLEFT", L.box, "TOPLEFT", 2, -4)

    local function GetRow(i)
        local r = L.rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, L.box)
        r:SetHeight(24)
        r.rm = NS.UI.MakeButton(r, "Remove", 70, 20)
        r.rm:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.tog = NS.UI.MakeButton(r, "", 120, 20)
        r.tog:SetPoint("RIGHT", r.rm, "LEFT", -6, 0)
        r.text = NS.UI.Text(r, "", 0, 1, 1, 1)
        r.text:SetPoint("LEFT", r, "LEFT", 2, 0)
        r.text:SetPoint("RIGHT", r.tog, "LEFT", -8, 0)
        r.text:SetWordWrap(false)
        L.rows[i] = r
        return r
    end

    function L.Refresh()
        local items = cfg.items()
        for _, r in ipairs(L.rows) do r:Hide() end
        local y = 0
        for i, e in ipairs(items) do
            local r = GetRow(i)
            r.text:SetText(cfg.text(e))
            if cfg.toggleText then
                r.tog.label:SetText(cfg.toggleText(e))
                r.tog:SetScript("OnClick", function() cfg.onToggle(e); L.Refresh() end)
                r.tog:Show()
            else
                r.tog:Hide()
                r.text:ClearAllPoints()
                r.text:SetPoint("LEFT", r, "LEFT", 2, 0)
                r.text:SetPoint("RIGHT", r.rm, "LEFT", -8, 0)
            end
            if cfg.onRemove then
                r.rm:SetScript("OnClick", function()
                    local cur = cfg.items()
                    local at
                    for k, v in ipairs(cur) do if v == e then at = k; break end end
                    if at then cfg.onRemove(at, e); Changed() end
                    L.Refresh()
                end)
                r.rm:Show()
            else
                r.rm:Hide()
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", L.box, "TOPLEFT", 0, -y)
            r:SetPoint("TOPRIGHT", L.box, "TOPRIGHT", 0, -y)
            r:Show()
            y = y + 26
        end
        L.emptyText:SetShown(#items == 0)
        L.box:SetContentHeight(#items == 0 and 24 or (y + 4))
    end
    table.insert(page.refreshers, L.Refresh)
    L.Refresh()
    return L
end

local CHANNEL_LABELS = {
    { "say", "Say" }, { "yell", "Yell" }, { "emote", "Emotes" }, { "whisper", "Whispers" },
    { "channel", "Channels (General, Trade, custom)" }, { "guild", "Guild chat" }, { "officer", "Officer chat" },
    { "party", "Party" }, { "raid", "Raid and raid warnings" }, { "instance", "Instance chat" },
    { "battleground", "Battleground" },
}

function M.Build(page)
    M.page = page

    ------------------------------------------------------------ status (always visible)
    page:Section("Right now", "Whether muted people can speak at this moment", { pinned = true })
    local status = page:Note("")
    local holder = page:Container()
    holder:SetContentHeight(1)
    local acc = 0
    holder:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc >= 1 then acc = 0; M.RefreshStatus() end
    end)
    function M.RefreshStatus()
        status:SetText(M.StatusText())
        page:Reflow()
    end
    function M.RefreshPage()
        M.RefreshStatus()
        for _, fn in ipairs(M.listRefresh or {}) do fn() end
    end
    M.listRefresh = {}
    local function Lst(cfg)
        local L = MakeList(page, cfg)
        table.insert(M.listRefresh, L.Refresh)
        return L
    end
    table.insert(page.refreshers, M.RefreshStatus)

    ------------------------------------------------------------ players
    page:Section("Muted players", "Hide chat from specific people", { open = true })
    page:Note("Type a name (Name, or Name-Realm for another realm) and press Enter. Whispers, say, yell, channels "
        .. "and group chat from them are hidden. 'Follows speak times' people are heard during your speak times; "
        .. "'Always muted' people never are.")
    page:Input("Add a player to mute", M.AddPlayer)
    page:Button("Mute my current target", M.MuteTarget, 200)
    Lst({
        items = function() return S().players end,
        text = function(e)
            local an, ar = SplitAuthor(e.name or "")
            local g = GuildFor(an, ar)
            return (e.name or "?") .. (g and ("  |cff9a9aa3<" .. g .. ">|r") or "")
        end,
        toggleText = function(e) return e.always and "Always muted" or "Follows speak times" end,
        onToggle = function(e) e.always = not e.always; Changed() end,
        onRemove = function(i) table.remove(S().players, i) end,
        empty = "No players muted.",
    })
    page:Button("Add everyone on my WoW ignore list", M.ImportIgnores, 250)

    ------------------------------------------------------------ guilds
    page:Section("Muted guilds", "Hide chat from everyone in a guild")
    page:Note("Type any part of a guild name (for example Olympus). Anyone whose guild name contains it is hidden. "
        .. "The game doesn't tell chat who is in which guild, so guilds are learned when you target, mouse over, "
        .. "group with, see the nameplate of, or /who a player. Players you haven't met yet can't be matched.")
    page:Input("Add a guild name (any part of it)", M.AddGuild)
    page:Button("Mute my target's guild", M.MuteTargetGuild, 200)
    Lst({
        items = function() return S().guilds end,
        text = function(e)
            local n, gl = 0, Lower(e.name or "")
            for _, c in pairs(S().cache) do
                if type(c) == "table" and c.g and Lower(c.g):find(gl, 1, true) then n = n + 1 end
            end
            return (e.name or "?") .. "  |cff9a9aa3" .. n .. " known player" .. (n == 1 and "" or "s") .. "|r"
        end,
        toggleText = function(e) return e.always and "Always muted" or "Follows speak times" end,
        onToggle = function(e) e.always = not e.always; Changed() end,
        onRemove = function(i) table.remove(S().guilds, i) end,
        empty = "No guilds muted.",
    })
    page:Check("Never mute my own guild", function() return S().keepOwnGuild end,
        function(v) S().keepOwnGuild = v end,
        "Protects your own guild even if its name matches something on the list.")
    page:Button("Forget all learned guilds", M.ForgetGuilds, 200)

    ------------------------------------------------------------ speak times
    page:Section("Speak times", "When muted people are allowed to speak")
    page:Note("Set the times muted people may speak. Examples: 18:00-20:00 (every day),  sat,sun 2pm-6pm,  "
        .. "mon-fri 9:00-17:00,  weekdays 22:00-02:00 (past midnight is fine). Several times can be added. "
        .. "'Always muted' people ignore the times.")
    page:Cycle("Mode", { { "allow", "Heard INSIDE the times" }, { "mute", "Muted ONLY inside the times" } },
        function() return S().mode end,
        function(v) S().mode = v; Changed() end)
    page:Cycle("Clock", { { "local", "My computer's time" }, { "server", "Server time" } },
        function() return S().clock end,
        function(v) S().clock = v; Changed() end)
    page:Input("Add a time, like  mon-fri 18:00-20:00", M.AddWindow)
    M.winErr = page:Note("")
    M.winErr:SetTextColor(1, 0.6, 0.3)
    Lst({
        items = function() return S().windows end,
        text = function(w) return FmtWindow(w) end,
        onRemove = function(i) table.remove(S().windows, i) end,
        empty = "No times set.",
    })
    page:Slider("Let them speak for", 1, 240, 1,
        function() return S().allowMinutes end,
        function(v) S().allowMinutes = v end,
        function(v) return v .. " min" end)
    page:Button("Let muted people speak now", function() M.AllowFor(S().allowMinutes) end, 240)
    page:Button("Mute them again now", M.StopAllow, 240)
    page:Check("Tell me in chat when it changes", function() return S().notify end,
        function(v) S().notify = v end)

    ------------------------------------------------------------ words and content
    page:Section("Words and content", "Hide messages by what they say, from anyone")
    page:Note("Words apply to everyone (except your never-mute list) and ignore the speak times. Use * as a wildcard: "
        .. "<*> hides any message with a guild tag in angle brackets, and <*> *recruit* only the ones that mention recruiting.")
    page:Input("Add a word, phrase or pattern", M.AddWord)
    Lst({
        items = function() return S().words end,
        text = function(w) return tostring(w) end,
        onRemove = function(i) table.remove(S().words, i) end,
        empty = "No words filtered.",
    })
    page:Check("Hide repeated messages (spam)", function() return S().spam end,
        function(v) S().spam = v end, "Hides a message when the same person sends the same text again quickly.")
    page:Slider("Repeat window", 5, 120, 1, function() return S().spamSeconds end,
        function(v) S().spamSeconds = v end, function(v) return v .. " s" end)
    page:Check("Hide ALL-CAPS shouting", function() return S().caps end,
        function(v) S().caps = v end, "Hides long messages that are almost entirely capital letters.")
    page:Slider("Shouting needs at least", 6, 40, 1, function() return S().capsMin end,
        function(v) S().capsMin = v end, function(v) return v .. " letters" end)
    page:Check("Hide messages with web addresses", function() return S().links end,
        function(v) S().links = v end)
    page:Check("Public channels: only people I know", function() return S().strangers end,
        function(v) S().strangers = v end,
        "In say, yell, emotes and channels, hides anyone who isn't a friend, guild mate or group member.")

    ------------------------------------------------------------ where
    page:Section("Where it applies", "Which kinds of chat are filtered")
    for _, c in ipairs(CHANNEL_LABELS) do
        page:Check(c[2], function() return S().channels[c[1]] end,
            function(v) S().channels[c[1]] = v end)
    end
    page:Check("Hide their chat bubbles above heads (open world)", function() return S().bubbles end,
        function(v) S().bubbles = v; if not v then RestoreBubbles() end end,
        "Best effort. Bubbles inside dungeons and raids can't be read, so they stay.")
    page:Check("Remove a newly found player's earlier messages", function() return S().cleanup end,
        function(v) S().cleanup = v end,
        "When a guild is learned for someone who already spoke, their old lines disappear from your chat windows.")

    ------------------------------------------------------------ invites
    page:Section("Invites and warnings", "What to do when a muted player asks something of you")
    page:Check("Decline guild invites from muted players or guilds", function() return S().declineGuild end,
        function(v) S().declineGuild = v end)
    page:Check("Decline group invites from muted players", function() return S().declineGroup end,
        function(v) S().declineGroup = v end)
    page:Check("Decline duels from muted players", function() return S().declineDuel end,
        function(v) S().declineDuel = v end)
    page:Check("Decline trades from muted players", function() return S().declineTrade end,
        function(v) S().declineTrade = v end)
    page:Check("Warn me when a muted player is in my group", function() return S().warnGroup end,
        function(v) S().warnGroup = v end)

    ------------------------------------------------------------ never mute
    page:Section("Never mute", "People and guilds that are always heard")
    page:Note("These are never hidden by any filter. Friends and your own guild can be protected with the switches below.")
    page:Input("Add a player who is never muted", M.AddKeepPlayer)
    Lst({
        items = function() return S().keepPlayers end,
        text = function(p) return tostring(p) end,
        onRemove = function(i) table.remove(S().keepPlayers, i) end,
        empty = "No players on the never-mute list.",
    })
    page:Input("Add a guild that is never muted (exact name)", M.AddKeepGuild)
    Lst({
        items = function() return S().keepGuilds end,
        text = function(g) return tostring(g) end,
        onRemove = function(i) table.remove(S().keepGuilds, i) end,
        empty = "No guilds on the never-mute list.",
    })
    page:Check("Never mute my friends (including Battle.net friends)", function() return S().keepFriends end,
        function(v) S().keepFriends = v end)
    page:Check("Never mute people in my group", function() return S().keepGroup end,
        function(v) S().keepGroup = v end, "Muted people are heard while they are in your party or raid.")

    ------------------------------------------------------------ log
    page:Section("Hidden messages", "What was hidden in the last 15 minutes")
    page:Note("Kept in memory only (never saved) and cleared when you log out or reload.")
    local logList = Lst({
        items = function()
            local now, out = time(), {}
            for i = #M.log, 1, -1 do
                if now - M.log[i].t <= LOG_SECONDS then out[#out + 1] = M.log[i] end
            end
            return out
        end,
        text = function(e)
            local text = Plain(tostring(e.text or ""))
            if #text > 90 then text = text:sub(1, 90) .. "..." end
            return string.format("|cffffd24d%s|r  |cff9a9aa3[%s]|r  %s", tostring(e.who), tostring(e.why or "?"), text)
        end,
        empty = "Nothing hidden recently.",
    })
    page:Button("Refresh this list", function() logList.Refresh() end, 160)
    page:Button("Clear the list", function() M.log = {}; logList.Refresh() end, 160)

    M.RefreshStatus()
end
