--[[
    Gnomish Pachinko - Plays.lua
    The day's plays. Losing a level (out of balls) spends one play; you get
    FAILS_PER_DAY free plays in any rolling 24 hours, and more can be
    bought by mailing gold to the casino banker (the same banker, mail
    hook and purchase flow as Chairface's Casino: PRICE_COPPER buys
    PLAYS_PER_LOT plays that last 24 hours). Clearing a level never costs
    a play.

    THE PLAYS VAULT
    The record of fails and bought plays is encrypted, checksummed and
    written to several places at once, none of them in the addon folder:
      - GnomishPachinkoSaved   (account-wide SavedVariables, WTF/Account/...)
      - GnomishPachinkoChar    (per-character SavedVariables)
      - ScryingCache           (the LibScrying satellite's file, when present)
      - a client CVar          (Config.wtf, when the client lets addons register one)
    Reinstalling the addon touches none of these. At login every copy is
    read and MERGED (the union of fails, the least generous view of bought
    plays), so deleting one copy changes nothing. A copy that fails its
    checksum means someone edited it: the vault then locks for a full day.
    Time comes from the server when the client offers it.
]]

local GP = GnomishPachinko
GP.Plays = GP.Plays or {}
local P = GP.Plays

P.FAILS_PER_DAY  = 5
P.WINDOW         = 24 * 60 * 60
P.PLAYS_PER_LOT  = 5
P.CVAR           = "gnomishPachinkoCache"

-- Golden Gears: mailed gold to the banker becomes gears, one gear a gold.
-- Gears buy special balls and plays; they are the only way to buy plays.
P.GEAR_COPPER    = 10000        -- 1g a gear
P.SUBJECT        = "pachinko golden gears"
P.DEFAULT_GEARS_MAIL = 10
P.SHOP = {
    suction = { cost = 1,  n = 3, label = "3 Suction Tubes" },
    ring    = { cost = 2,  n = 3, label = "3 Rings of Fire" },
    rainbow = { cost = 3,  n = 3, label = "3 Rainbow Balls" },
    plays   = { cost = 10, n = 5, label = "5 plays" },
}
P.SHOP_ORDER = { "suction", "ring", "rainbow", "plays" }
P.START_ITEMS = { ring = 2, rainbow = 0, green = 1, suction = 1 }

-- Everything that is worth cheating at lives in the vault, sealed: the
-- gears, the special balls, the plays and the progress. These keys of the
-- saved settings are filled from the vault at login and taken back out of
-- the plain file at logout.
P.SEALED = { "unlocked", "cleared", "best", "stars", "current", "lastPower", "tips", "dialogs" }

local floor = math.floor

-- byte xor without the bit library (Forever's Lua may lack it)
local function bx(a, b)
    local r, c = 0, 1
    for _ = 0, 7 do
        local ba, bb = a % 2, b % 2
        if ba ~= bb then r = r + c end
        a, b, c = floor(a / 2), floor(b / 2), c * 2
    end
    return r
end
local function bv(s)
    local r = ""
    for i = 1, #s do r = r .. string.char(bx(string.byte(s, i), 42)) end
    return r
end

-- The banker, obfuscated the same way as in the casino. Every name on
-- Forever has a surname, so the whole "first last" is the recipient.
local BANKER = bv("IBKCXLKIO") .. bv("\10IBCZZODNKFO")
function P:BankerName()
    return (BANKER:gsub("%f[%a]%l", string.upper))
end

-- The owner's characters, encoded the same way as the casino's debug
-- allow-list: these buy a lot of plays for free from a button of their own.
local OWNERS = { [bv("iBKCXLKIO\10iBCZZODNKFO")] = 1, [bv("bCMBFOS\10xOMKXNON")] = 1, [bv("dE^^O\10y_XO")] = 1 }

-- "First Last" as the client gives it (two values on Forever).
function P:MyName()
    if type(UnitName) ~= "function" then return nil end
    local ok, first, last = pcall(UnitName, "player")
    if not ok or type(first) ~= "string" then return nil end
    local okL, lastName = pcall(function() return (type(last) == "string" and last ~= "") and ("" .. last) or nil end)
    if okL and lastName then return first .. " " .. lastName end
    return first
end

function P:IsOwner()
    local name = self:MyName()
    if not name then return false end
    if OWNERS[name] == 1 then return true end
    local lower = name:lower()
    for k in pairs(OWNERS) do if k:lower() == lower then return true end end
    return false
end

-- The owner's free top-up: a lot of plays, no mail.
function P:GrantFree()
    if not self:IsOwner() then return false, "Not available on this character" end
    local left = self:AddLots(1)
    GP:Print(("|cff00ff00Owner top-up:|r %d free plays, good for 24 hours. Plays left: |cffffd700%d|r"):format(self.PLAYS_PER_LOT, left))
    GP:PlaySfx("free_ball.ogg")
    if GP.UI and GP.UI.OnPlaysChanged then GP.UI:OnPlaysChanged() end
    return true
end

function P:PriceText(gears)
    return tostring(floor((gears or 1) * self.GEAR_COPPER / 10000)) .. "g"
end

-- Server time when the client gives it, the clock otherwise.
local function now()
    if type(GetServerTime) == "function" then
        local ok, t = pcall(GetServerTime)
        if ok and type(t) == "number" and t > 1000000000 then return t end
    end
    return time()
end
P.Now = now

-- ---------------------------------------------------------------------
-- Encryption: a keyed stream cipher over the record, a keyed checksum
-- inside it, base64 outside.

local SECRET = bv("ADEGCYB\10ZKIBCDAE\10ZFKSY\10\27\27\31")   -- decoded at load, never a plain string in the source

local function hash(s, seed)
    local h = seed or 5381
    for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 2147483647 end
    return h
end

local function crypt(data, key)
    local s = hash(key, 7919)
    local out = {}
    for i = 1, #data do
        s = (s * 48271) % 2147483647
        out[i] = string.char(bx(string.byte(data, i), s % 256))
    end
    return table.concat(out)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = string.byte(data, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = floor(n / 262144) % 64
        local c2 = floor(n / 4096) % 64
        local c3 = floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local B64REV
local function b64decode(text)
    if not B64REV then
        B64REV = {}
        for i = 1, 64 do B64REV[B64:sub(i, i)] = i - 1 end
    end
    local out = {}
    text = text:gsub("[^%w%+/=]", "")
    for i = 1, #text, 4 do
        local chunk = text:sub(i, i + 3)
        local vals, pad = {}, 0
        for k = 1, 4 do
            local ch = chunk:sub(k, k)
            if ch == "=" or ch == "" then pad = pad + 1; vals[k] = 0
            else
                local v = B64REV[ch]
                if not v then return nil end
                vals[k] = v
            end
        end
        local n = vals[1] * 262144 + vals[2] * 4096 + vals[3] * 64 + vals[4]
        local a, b, c = floor(n / 65536) % 256, floor(n / 256) % 256, n % 256
        if pad == 0 then out[#out + 1] = string.char(a, b, c)
        elseif pad == 1 then out[#out + 1] = string.char(a, b)
        else out[#out + 1] = string.char(a) end
    end
    return table.concat(out)
end

-- record: { fails = { ts, ... }, lots = { { ts = , left = }, ... }, ts = }
local function serialize(rec)
    local fails = {}
    for i, t in ipairs(rec.fails) do fails[i] = tostring(floor(t)) end
    local lots = {}
    for i, l in ipairs(rec.lots) do lots[i] = floor(l.ts) .. ":" .. floor(l.left) end
    local body = "1|" .. table.concat(fails, ",") .. "|" .. table.concat(lots, ";") .. "|" .. floor(rec.ts or now())
    return body .. "|" .. hash(SECRET .. body)
end

local function deserialize(body)
    local v, fails, lots, ts, sum = body:match("^(%d+)|([%d,]*)|([%d:;]*)|(%d+)|(%d+)$")
    if not v then return nil end
    local plain = v .. "|" .. fails .. "|" .. lots .. "|" .. ts
    if tonumber(sum) ~= hash(SECRET .. plain) then return nil end
    local rec = { fails = {}, lots = {}, ts = tonumber(ts) }
    for t in fails:gmatch("%d+") do rec.fails[#rec.fails + 1] = tonumber(t) end
    for t, left in lots:gmatch("(%d+):(%d+)") do rec.lots[#rec.lots + 1] = { ts = tonumber(t), left = tonumber(left) } end
    return rec
end

-- The whole record, packed: numbers, strings, booleans and tables of them.
local function pack(v, out)
    local t = type(v)
    if t == "number" then out[#out + 1] = "n" .. tostring(v) .. ";"
    elseif t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            return a < b
        end)
        for _, k in ipairs(keys) do
            if type(k) == "number" or type(k) == "string" then
                local vt = type(v[k])
                if vt == "number" or vt == "string" or vt == "boolean" or vt == "table" then
                    pack(k, out)
                    pack(v[k], out)
                end
            end
        end
        out[#out + 1] = "}"
    else out[#out + 1] = "F" end
end

local function unpackAt(s, i)
    local c = s:sub(i, i)
    if c == "n" then
        local j = s:find(";", i, true)
        if not j then return nil end
        return tonumber(s:sub(i + 1, j - 1)), j + 1
    elseif c == "s" then
        local j = s:find(":", i, true)
        if not j then return nil end
        local len = tonumber(s:sub(i + 1, j - 1))
        if not len then return nil end
        return s:sub(j + 1, j + len), j + 1 + len
    elseif c == "T" then return true, i + 1
    elseif c == "F" then return false, i + 1
    elseif c == "{" then
        local t = {}
        i = i + 1
        while s:sub(i, i) ~= "}" do
            if i > #s then return nil end
            local k, v
            k, i = unpackAt(s, i)
            if k == nil or not i then return nil end
            v, i = unpackAt(s, i)
            if not i then return nil end
            t[k] = v
        end
        return t, i + 1
    end
    return nil
end

function P:Encode(rec)
    local out = {}
    pack(rec, out)
    local body = table.concat(out)
    return "GPV2:" .. b64encode(crypt(body .. "|" .. hash(SECRET .. body), SECRET))
end

-- nil for nothing stored, false for a copy that does not check out.
function P:Decode(text)
    if text == nil or text == "" then return nil end
    if type(text) ~= "string" then return false end
    if text:sub(1, 5) == "GPV2:" then
        local raw = b64decode(text:sub(6))
        if not raw then return false end
        local plain = crypt(raw, SECRET)
        local body, sum = plain:match("^(.*)|(%d+)$")
        if not body or tonumber(sum) ~= hash(SECRET .. body) then return false end
        local rec = unpackAt(body, 1)
        if type(rec) ~= "table" or type(rec.fails) ~= "table" or type(rec.lots) ~= "table" then return false end
        return rec
    end
    if text:sub(1, 4) ~= "GPV:" then return false end
    -- the first version: fails and lots only
    local raw = b64decode(text:sub(5))
    if not raw then return false end
    local rec = deserialize(crypt(raw, SECRET))
    return rec or false
end

-- ---------------------------------------------------------------------
-- The mirrors

local function mirrors()
    GnomishPachinkoSaved = GnomishPachinkoSaved or {}
    GnomishPachinkoChar = GnomishPachinkoChar or {}
    local list = {
        { get = function() return GnomishPachinkoSaved.plays end, set = function(v) GnomishPachinkoSaved.plays = v end },
        { get = function() return GnomishPachinkoChar.plays end, set = function(v) GnomishPachinkoChar.plays = v end },
    }
    if type(ScryingCache) == "table" then
        list[#list + 1] = { get = function() return ScryingCache.gp end, set = function(v) ScryingCache.gp = v end }
    end
    if type(C_CVar) == "table" and type(C_CVar.RegisterCVar) == "function" then
        list[#list + 1] = {
            get = function()
                local ok, v = pcall(C_CVar.GetCVar, P.CVAR)
                if ok and type(v) == "string" and v ~= "" then return v end
                return nil
            end,
            set = function(v) pcall(C_CVar.SetCVar, P.CVAR, v) end,
        }
    end
    return list
end

local function prune(rec, t)
    local keep = {}
    for _, f in ipairs(rec.fails) do
        if f > t - P.WINDOW and f <= t + 3600 then keep[#keep + 1] = f end
    end
    table.sort(keep)
    rec.fails = keep
    local lots = {}
    for _, l in ipairs(rec.lots) do
        if l.ts > t - P.WINDOW and l.left > 0 then lots[#lots + 1] = l end
    end
    table.sort(lots, function(a, b) return a.ts < b.ts end)
    rec.lots = lots
end

-- The union of every copy: every fail any copy knows (several losses can
-- share one second, so each timestamp keeps the most any copy counts),
-- every bought lot any copy knows with the fewest plays any copy still
-- gives it.
local function merge(records)
    local fails, lots = {}, {}
    local failCount, lotByTs = {}, {}
    for _, rec in ipairs(records) do
        local mine = {}
        for _, f in ipairs(rec.fails) do mine[f] = (mine[f] or 0) + 1 end
        for f, n in pairs(mine) do
            if n > (failCount[f] or 0) then failCount[f] = n end
        end
        for _, l in ipairs(rec.lots) do
            local cur = lotByTs[l.ts]
            if not cur then
                cur = { ts = l.ts, left = l.left }
                lotByTs[l.ts] = cur
                lots[#lots + 1] = cur
            elseif l.left < cur.left then
                cur.left = l.left
            end
        end
    end
    for f, n in pairs(failCount) do
        for _ = 1, n do fails[#fails + 1] = f end
    end
    -- the gears, the special balls and the progress: from the copy with the
    -- highest revision (each save counts it up, so an old copy put back
    -- cannot restore spent gears)
    local newest
    for _, rec in ipairs(records) do
        if (rec.rev or 0) > ((newest and newest.rev) or -1) then newest = rec end
    end
    newest = newest or {}
    return { fails = fails, lots = lots, ts = now(), rev = newest.rev or 0,
        gears = newest.gears, items = newest.items, prog = newest.prog }
end

function P:Load()
    local t = now()
    local records, tampered = {}, false
    for _, m in ipairs(mirrors()) do
        local rec = self:Decode(m.get())
        if rec then records[#records + 1] = rec
        elseif rec == false then tampered = true end
    end
    local rec = merge(records)
    if tampered then
        -- an edited copy: the day's plays are gone
        rec.fails = {}
        for _ = 1, self.FAILS_PER_DAY do rec.fails[#rec.fails + 1] = t end
        rec.lots = {}
        self.tampered = true
    end
    prune(rec, t)
    self.rec = rec
    self.loaded = true
    self:Unseal()
    self:Save()
    return rec
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

-- The vault's progress into the settings (or, the first time, the plain
-- settings into the vault: the progress from before it was sealed).
function P:Unseal()
    local db = GP:GetDB()
    local r = self.rec
    r.gears = math.max(0, floor(tonumber(r.gears) or 0))
    if type(r.items) ~= "table" then
        r.items = copy(type(db.items) == "table" and db.items or self.START_ITEMS)
    end
    for k, v in pairs(self.START_ITEMS) do if r.items[k] == nil then r.items[k] = 0 end end
    db.items = nil
    if type(r.prog) == "table" then
        for _, k in ipairs(self.SEALED) do
            if r.prog[k] ~= nil then db[k] = copy(r.prog[k]) end
        end
    end
    GP:GetDB()      -- defaults for anything missing
    db.items = nil
end

-- The settings' progress into the vault.
function P:Seal()
    local db = GP.db or GP:GetDB()
    local r = self.rec
    r.prog = r.prog or {}
    for _, k in ipairs(self.SEALED) do r.prog[k] = copy(db[k]) end
end

-- At logout the sealed keys leave the plain file: only the vault has them.
function P:StripPlain()
    local db = GnomishPachinkoDB
    if type(db) ~= "table" then return end
    for _, k in ipairs(self.SEALED) do db[k] = nil end
    db.items = nil
end

function P:Save()
    if not self.rec then return end
    self:Seal()
    self.rec.ts = now()
    self.rec.rev = (self.rec.rev or 0) + 1
    local text = self:Encode(self.rec)
    for _, m in ipairs(mirrors()) do m.set(text) end
    if type(C_CVar) == "table" and type(C_CVar.RegisterCVar) == "function" then
        pcall(C_CVar.RegisterCVar, self.CVAR, "")
    end
end

local function rec(self)
    if not self.rec then self:Load() end
    prune(self.rec, now())
    return self.rec
end

function P:FreeLeft()
    return math.max(0, self.FAILS_PER_DAY - #rec(self).fails)
end

function P:BoughtLeft()
    local n = 0
    for _, l in ipairs(rec(self).lots) do n = n + l.left end
    return n
end

function P:Remaining()
    return self:FreeLeft() + self:BoughtLeft()
end

function P:CanPlay()
    return self:Remaining() > 0
end

-- Seconds until the next free play comes back (the oldest fail expires).
function P:NextFreeIn()
    local r = rec(self)
    if #r.fails < self.FAILS_PER_DAY then return 0 end
    return math.max(0, r.fails[1] + self.WINDOW - now())
end

-- A lost level: a free play first, then the oldest bought lot.
function P:RecordFail()
    local r = rec(self)
    if #r.fails < self.FAILS_PER_DAY then
        r.fails[#r.fails + 1] = now()
    elseif r.lots[1] then
        r.lots[1].left = r.lots[1].left - 1
        if r.lots[1].left <= 0 then table.remove(r.lots, 1) end
    end
    self:Save()
    return self:Remaining()
end

function P:AddLots(lots)
    local r = rec(self)
    r.lots[#r.lots + 1] = { ts = now(), left = lots * self.PLAYS_PER_LOT }
    self:Save()
    return self:Remaining()
end

function P:Gears()
    return floor(rec(self).gears or 0)
end

function P:AddGears(n)
    local r = rec(self)
    r.gears = math.max(0, floor((r.gears or 0) + n))
    self:Save()
    return r.gears
end

function P:Items()
    local r = rec(self)
    if type(r.items) ~= "table" then r.items = copy(self.START_ITEMS) end
    return r.items
end

function P:AddItem(item, n)
    local items = self:Items()
    items[item] = math.max(0, (items[item] or 0) + n)
    self:Save()
    return items[item]
end

-- Spends gears in the shop. Returns ok, message.
function P:Buy(what)
    local offer = self.SHOP[what]
    if not offer then return false, "Nothing like that in the shop" end
    local have = self:Gears()
    if have < offer.cost then
        return false, ("%s cost %d Golden Gears; you have %d. Mail gold to %s to get more (1g a gear)."):format(offer.label, offer.cost, have, self:BankerName())
    end
    local r = rec(self)
    r.gears = have - offer.cost
    if what == "plays" then
        r.lots[#r.lots + 1] = { ts = now(), left = offer.n }
    else
        local items = self:Items()
        items[what] = (items[what] or 0) + offer.n
    end
    self:Save()
    if GP.UI and GP.UI.OnPlaysChanged then GP.UI:OnPlaysChanged() end
    return true, ("Bought %s for %d Golden Gears (%d left)."):format(offer.label, offer.cost, r.gears)
end

function P:FormatWait(secs)
    secs = floor(secs or 0)
    if secs <= 0 then return "now" end
    local h, m = floor(secs / 3600), floor((secs % 3600) / 60)
    if h > 0 then return h .. "h " .. m .. "m" end
    return math.max(1, m) .. "m"
end

function P:StatusText()
    local free, bought = self:FreeLeft(), self:BoughtLeft()
    local s = "Plays left today: |cffffd700" .. (free + bought) .. "|r (" .. free .. " of " .. self.FAILS_PER_DAY .. " free"
    if bought > 0 then s = s .. ", " .. bought .. " bought" end
    s = s .. ")."
    if free == 0 then s = s .. " Next free play in " .. self:FormatWait(self:NextFreeIn()) .. "." end
    s = s .. " Golden Gears: |cffffd700" .. self:Gears() .. "|r (5 plays cost 10; gears are 1g each by mail to " .. self:BankerName() .. ")."
    return s
end

-- ---------------------------------------------------------------------
-- Buying plays by mail. Same flow as the casino: at an open mailbox the
-- Send Mail form is filled out (the player presses Send); the sender's
-- own SendMail call is hooked, and MAIL_SEND_SUCCESS confirms it. Only
-- mail to the banker with "pachinko" in its subject counts, so a casino
-- credit purchase is never mistaken for one.

local function fieldTry(failed, label, fn)
    local ok = pcall(fn)
    if not ok then failed[#failed + 1] = label end
end

function P:ApplyPendingFill()
    local p = self.pendingFill
    if not p then return end
    self.pendingFill = nil
    local failed = {}
    local banker = self:BankerName()
    fieldTry(failed, "recipient", function() SendMailNameEditBox:SetText(banker) end)
    fieldTry(failed, "subject", function() SendMailSubjectEditBox:SetText(self.SUBJECT) end)
    fieldTry(failed, "message", function()
        SendMailBodyEditBox:SetText(string.format("Buying %d Gnomish Pachinko Golden Gears for %s.", p.gears, self:PriceText(p.gears)))
    end)
    fieldTry(failed, "money", function() MoneyInputFrame_SetCopper(SendMailMoney, p.copper) end)
    local okMoney, copper = pcall(MoneyInputFrame_GetCopper, SendMailMoney)
    if not (okMoney and copper == p.copper) then
        local seen = false
        for _, label in ipairs(failed) do if label == "money" then seen = true end end
        if not seen then failed[#failed + 1] = "money" end
    end
    local price = self:PriceText(p.gears)
    if #failed == 0 then
        GP:Print("Mail filled out: " .. price .. " to " .. banker .. " for |cffffd700" .. p.gears .. "|r Golden Gears. Press Send to complete.")
    else
        GP:Print("|cffff8800Could not fill in: " .. table.concat(failed, ", ") .. ".|r Send " .. price .. " to " .. banker ..
            " with \"" .. self.SUBJECT .. "\" as the subject for |cffffd700" .. p.gears .. "|r Golden Gears.")
    end
end

-- Fills out the mail for some Golden Gears (1g each).
function P:FillPurchaseMail(gears)
    gears = floor(tonumber(gears) or self.DEFAULT_GEARS_MAIL)
    if gears < 1 then return false, "Buy at least one Golden Gear (1g)" end
    if not (MailFrame and MailFrame:IsShown()) then
        return false, "Visit a mailbox first: the helper fills the mail out there. Golden Gears are 1g each, sent to " ..
            self:BankerName() .. " with \"" .. self.SUBJECT .. "\" as the subject."
    end
    local copper = gears * self.GEAR_COPPER
    if GetMoney and GetMoney() < copper then
        return false, "You do not have " .. self:PriceText(gears) .. " on you"
    end
    self.pendingFill = { gears = gears, copper = copper }
    if SendMailFrame and SendMailFrame:IsShown() then
        self:ApplyPendingFill()
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            if self.pendingFill then GP:Print("Open the mailbox's |cffffd700Send Mail|r tab and the purchase fills in.") end
        end)
    end
    return true
end

-- Credits a confirmed purchase (also what the mail hook calls): a gear a gold.
function P:OnPurchase(copper)
    local gears = floor(copper / self.GEAR_COPPER)
    if gears <= 0 then return 0 end
    local total = self:AddGears(gears)
    GP:Print(string.format("|cff00ff00Golden Gears!|r %s mailed to the banker: |cffffd700%d|r gears. You have |cffffd700%d|r.",
        self:PriceText(gears), gears, total))
    GP:PlaySfx("free_ball.ogg")
    if GP.UI and GP.UI.OnPlaysChanged then GP.UI:OnPlaysChanged() end
    return gears
end

-- The mailbox button sits under the casino's "Buy Casino Credits" button
-- when that one is there and showing; otherwise it takes its place.
function P:AnchorMailButton()
    local btn = self.mailHelperButton
    if not btn or not MailFrame then return end
    local casino = ChairfacesCasino and ChairfacesCasino.Arcade and ChairfacesCasino.Arcade.mailHelperButton
    btn:ClearAllPoints()
    if casino and casino:IsShown() then
        btn:SetPoint("TOP", casino, "BOTTOM", 0, -2)
        btn:SetWidth(casino:GetWidth() or 130)
    else
        btn:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", -4, -2)
        btn:SetWidth(130)
    end
end

if MailFrame then
    local mailBtn = CreateFrame("Button", nil, MailFrame, "UIPanelButtonTemplate")
    mailBtn:SetSize(130, 22)
    mailBtn:SetText("Buy Golden Gears")
    mailBtn:SetScript("OnClick", function()
        local ok, err = P:FillPurchaseMail(P.DEFAULT_GEARS_MAIL)
        if not ok then GP:Print(err) end
    end)
    mailBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Gnomish Pachinko: Golden Gears")
        GameTooltip:AddLine("1g = 1 Golden Gear. Gears buy special balls and plays (5 plays for 10).", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(P:StatusText(), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    mailBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    P.mailHelperButton = mailBtn
    P:AnchorMailButton()
    -- the casino may load after us, or hide its button from its settings
    MailFrame:HookScript("OnShow", function() P:AnchorMailButton() end)
    if SendMailFrame then
        SendMailFrame:HookScript("OnShow", function()
            if P.pendingFill and C_Timer and C_Timer.After then
                C_Timer.After(0.1, function() P:ApplyPendingFill() end)
            end
        end)
    end
    MailFrame:HookScript("OnHide", function() P.pendingFill = nil end)
end

do
    local pendingPurchase
    if type(SendMail) == "function" and type(hooksecurefunc) == "function" then
        hooksecurefunc("SendMail", function(recipient, subject)
            pendingPurchase = nil
            local money = GetSendMailMoney and GetSendMailMoney() or 0
            local okR, r = pcall(function() return "" .. tostring(recipient) end)
            local okS, s = pcall(function() return "" .. tostring(subject) end)
            if not okR then return end
            local short = (r:match("^([^-]+)") or r):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
            if short:lower() == BANKER and money >= P.GEAR_COPPER and okS and s:lower():find("pachinko", 1, true) then
                pendingPurchase = { money = money }
            end
        end)
    end
    local mailRx = CreateFrame("Frame")
    mailRx:RegisterEvent("MAIL_SEND_SUCCESS")
    mailRx:SetScript("OnEvent", function()
        if not pendingPurchase then return end
        local money = pendingPurchase.money
        pendingPurchase = nil
        P:OnPurchase(money)
    end)
end
