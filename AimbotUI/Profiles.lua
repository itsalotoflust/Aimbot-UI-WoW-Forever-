--[[
  Aimbot UI - Export / Import (2.33.0)
  Turns all Aimbot UI settings into one line of text you can copy, share or paste into another
  account, and reads such a line back.

  What goes in: every module's settings and the settings window's look, saved as the
  differences from the defaults (so the string stays short). What never goes in: logs,
  caches and things the addon remembers by itself (the whisper inbox, the 60 fps log, saved
  game settings to put back, the mute cache), and the settings window's position. Your own
  lists and names (muted players, guilds and words, the never-mute lists, your Privacy name
  and BattleTag stand-in) only go in when you tick "Include my lists and names", which is
  meant for your own other account, not for sharing.

  Importing replaces your settings with the imported ones (anything the string doesn't
  mention goes back to its default), but keeps your own lists and names unless the string
  carries them, and never touches logs or caches. A /reload afterwards finishes the job.

  The text is "!AUI1!" + base64 of a small serializer's output + "!" + an Adler-32 checksum.
  Reading it back uses a strict parser of our own (no loadstring), with size and depth limits.
]]

local ADDON_NAME, NS = ...
local P = {}
NS.Profiles = P

local PREFIX = "!AUI1!"
local MAX_TEXT = 600000
local MAX_DEPTH = 20

----------------------------------------------------------------------
-- What is left out
----------------------------------------------------------------------
-- never exported, never overwritten by an import
local RUNTIME = {
    fps        = { log60 = true },
    mute       = { cache = true, total = true, allowUntil = true },
    privacy    = { inbox = true, savedBubbles = true },
    auratimers = { savedCVar = true },
    framestyle = { sizeVersion = true },
}
-- only with "Include my lists and names"; kept on import unless the string carries them
local PERSONAL = {
    mute    = { players = true, guilds = true, words = true, keepPlayers = true, keepGuilds = true },
    privacy = { ownName = true, tag = true },
}
local WINDOW_SKIP = { point = true }
P._RUNTIME, P._PERSONAL = RUNTIME, PERSONAL

local function Skip(modKey, k, includePersonal)
    if RUNTIME[modKey] and RUNTIME[modKey][k] then return true end
    if not includePersonal and PERSONAL[modKey] and PERSONAL[modKey][k] then return true end
    return false
end

----------------------------------------------------------------------
-- Differences from the defaults
----------------------------------------------------------------------
local function IsList(t)
    if type(t) ~= "table" then return false end
    if t[1] ~= nil then return true end
    return next(t) == nil
end

local function DeepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not DeepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
P._DeepEqual = DeepEqual

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

-- what in `saved` differs from `def` (lists and colours compared whole)
local function Diff(saved, def)
    local out = {}
    for k, v in pairs(saved) do
        local d = def and def[k]
        if type(v) == "table" and type(d) == "table" and not IsList(v) and not IsList(d) then
            local sub = Diff(v, d)
            if next(sub) ~= nil then out[k] = sub end
        elseif not DeepEqual(v, d) then
            out[k] = Copy(v)
        end
    end
    return out
end
P._Diff = Diff

-- defaults with the differences laid on top
local function Overlay(base, diff)
    for k, v in pairs(diff) do
        if type(v) == "table" and type(base[k]) == "table" and not IsList(v) and not IsList(base[k]) then
            Overlay(base[k], v)
        else
            base[k] = Copy(v)
        end
    end
    return base
end
P._Overlay = Overlay

----------------------------------------------------------------------
-- Serializer (strings, numbers, booleans, nested tables)
----------------------------------------------------------------------
local function Ser(v, out, depth)
    if depth > MAX_DEPTH then error("too deeply nested") end
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then error("bad number") end
        if v == math.floor(v) and math.abs(v) < 2 ^ 53 then
            out[#out + 1] = "n" .. string.format("%d", v) .. ";"
        else
            out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
        end
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        -- sorted keys: the same settings always give the same string
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        for _, k in ipairs(keys) do
            local x = v[k]
            local tx = type(x)
            if tx == "string" or tx == "number" or tx == "boolean" or tx == "table" then
                Ser(k, out, depth + 1)
                Ser(x, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    end
end

function P.Serialize(v)
    local out = {}
    Ser(v, out, 0)
    return table.concat(out)
end

-- strict reader; returns value or nil, error
function P.Deserialize(s)
    if type(s) ~= "string" or #s > MAX_TEXT then return nil, "too long" end
    local pos = 1
    local function Read(depth)
        if depth > MAX_DEPTH then error("too deeply nested") end
        local c = s:sub(pos, pos)
        if c == "s" then
            local len, colon = s:match("^(%d+)():", pos + 1)
            if not len then error("bad string") end
            len = tonumber(len)
            local start = colon + 1
            local v = s:sub(start, start + len - 1)
            if #v ~= len then error("string cut short") end
            pos = start + len
            return v
        elseif c == "n" then
            local num, after = s:match("^([%-%+%d%.eE]+);()", pos + 1)
            local v = num and tonumber(num)
            if not v or v ~= v or v == math.huge or v == -math.huge then error("bad number") end
            pos = after
            return v
        elseif c == "T" then pos = pos + 1; return true
        elseif c == "F" then pos = pos + 1; return false
        elseif c == "{" then
            pos = pos + 1
            local t = {}
            while true do
                local ch = s:sub(pos, pos)
                if ch == "}" then pos = pos + 1; return t end
                if ch == "" then error("table not closed") end
                local k = Read(depth + 1)
                if type(k) ~= "string" and type(k) ~= "number" then error("bad key") end
                t[k] = Read(depth + 1)
            end
        end
        error("unexpected '" .. c .. "' at " .. pos)
    end
    local ok, v = pcall(Read, 0)
    if not ok then return nil, tostring(v):gsub("^.-:%d+: ", "") end
    if pos ~= #s + 1 then return nil, "extra text at the end" end
    return v
end

----------------------------------------------------------------------
-- Base64 and checksum (pure Lua 5.1, no bit library needed)
----------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64I = {}
for i = 1, 64 do B64I[B64:sub(i, i)] = i - 1 end

function P.Encode64(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

function P.Decode64(s)
    s = s:gsub("[^%w%+/=]", "")
    if #s % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #s, 4 do
        local q = s:sub(i, i + 3)
        local pad = select(2, q:gsub("=", ""))
        q = q:gsub("=", "A")
        local n = 0
        for j = 1, 4 do
            local v = B64I[q:sub(j, j)]
            if not v then return nil end
            n = n * 64 + v
        end
        local a, b, c = math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
        if pad == 0 then out[#out + 1] = string.char(a, b, c)
        elseif pad == 1 then out[#out + 1] = string.char(a, b)
        else out[#out + 1] = string.char(a) end
    end
    return table.concat(out)
end

function P.Adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

----------------------------------------------------------------------
-- Export / import
----------------------------------------------------------------------
-- the settings as a payload table
function P.BuildPayload(includePersonal)
    local db = NS.db
    local payload = { v = 1, addon = NS.version, personal = includePersonal and true or false,
        window = {}, mod = {} }
    local win = {}
    for k, v in pairs(db.window or {}) do if not WINDOW_SKIP[k] then win[k] = v end end
    payload.window = Diff(win, NS.WINDOW_DEFAULTS or {})
    for _, key in ipairs(NS.moduleOrder) do
        local m = NS.modules[key]
        local saved = db.mod[key] or {}
        local keep = {}
        for k, v in pairs(saved) do if not Skip(key, k, includePersonal) then keep[k] = v end end
        payload.mod[key] = Diff(keep, m.defaults or {})
    end
    return payload
end

function P.Export(includePersonal)
    local body = P.Serialize(P.BuildPayload(includePersonal))
    return PREFIX .. P.Encode64(body) .. "!" .. P.Adler32(body)
end

-- text -> payload table, or nil and a reason in plain words
function P.Decode(text)
    if type(text) ~= "string" then return nil, "nothing to import" end
    text = text:gsub("%s+", "")
    if text == "" then return nil, "nothing to import: paste an Aimbot UI export string first" end
    if #text > MAX_TEXT then return nil, "that text is far too long to be an Aimbot UI export" end
    local b64, sum = text:match("^" .. PREFIX:gsub("!", "%%!") .. "([%w%+/=]+)!(%x+)$")
    if not b64 then return nil, "that isn't an Aimbot UI export string (it should start with " .. PREFIX .. ")" end
    local body = P.Decode64(b64)
    if not body then return nil, "the string is damaged (it may have been cut off when copying)" end
    if P.Adler32(body) ~= sum:lower() then
        return nil, "the string is damaged (checksum doesn't match: it may have been cut off or changed)"
    end
    local payload, err = P.Deserialize(body)
    if type(payload) ~= "table" then return nil, "the string couldn't be read (" .. tostring(err) .. ")" end
    if type(payload.mod) ~= "table" then return nil, "the string has no settings in it" end
    return payload
end

-- a short description of what the string holds
function P.Describe(payload)
    local changed, total = 0, 0
    for key, diff in pairs(payload.mod) do
        if NS.modules[key] then
            total = total + 1
            if type(diff) == "table" and next(diff) ~= nil then changed = changed + 1 end
        end
    end
    return string.format("from Aimbot UI %s: %d module(s) with changed settings out of %d%s",
        tostring(payload.addon or "?"), changed, total, payload.personal and ", includes lists and names" or "")
end

-- replace the current settings with the payload's
function P.Apply(payload)
    local db = NS.db
    local applied, unknown = 0, 0
    if type(payload.window) == "table" then
        local point = db.window and db.window.point
        db.window = Overlay(Copy(NS.WINDOW_DEFAULTS or {}), payload.window)
        db.window.point = point
    end
    for key, diff in pairs(payload.mod) do
        local m = NS.modules[key]
        if m and type(diff) == "table" then
            local cur = db.mod[key] or {}
            local new = Overlay(Copy(m.defaults or {}), diff)
            -- logs and caches stay as they are; own lists and names stay unless the string has them
            for k, v in pairs(cur) do
                local runtime = RUNTIME[key] and RUNTIME[key][k]
                local personal = PERSONAL[key] and PERSONAL[key][k]
                if runtime or (personal and diff[k] == nil) then new[k] = v end
            end
            db.mod[key] = new
            applied = applied + 1
        elseif not m then
            unknown = unknown + 1
        end
    end
    -- modules the string doesn't mention (it is from an older version) keep their settings
    if NS.ApplyAll then NS.ApplyAll() end
    if NS.UI and NS.UI.ApplyStyle then pcall(NS.UI.ApplyStyle) end
    if NS.UI and NS.UI.RefreshAll then pcall(NS.UI.RefreshAll) end
    return applied, unknown
end

function P.Import(text)
    local payload, err = P.Decode(text)
    if not payload then return nil, err end
    local applied, unknown = P.Apply(payload)
    return applied, unknown, payload
end
