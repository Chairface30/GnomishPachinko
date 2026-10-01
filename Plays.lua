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
P.PRICE_COPPER   = 100000       -- 10g a lot
P.PLAYS_PER_LOT  = 5
P.CVAR           = "gnomishPachinkoCache"
P.SUBJECT        = "pachinko plays purchase"

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

function P:PriceText(lots)
    return tostring((lots or 1) * self.PRICE_COPPER / 10000) .. "g"
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

function P:Encode(rec)
    return "GPV:" .. b64encode(crypt(serialize(rec), SECRET))
end

-- nil for nothing stored, false for a copy that does not check out.
function P:Decode(text)
    if text == nil or text == "" then return nil end
    if type(text) ~= "string" or text:sub(1, 4) ~= "GPV:" then return false end
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
    return { fails = fails, lots = lots, ts = now() }
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
    self:Save()
    return rec
end

function P:Save()
    if not self.rec then return end
    self.rec.ts = now()
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
    s = s .. " " .. self.PLAYS_PER_LOT .. " more plays cost " .. self:PriceText(1) .. " by mail to " .. self:BankerName() .. "."
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
        SendMailBodyEditBox:SetText(string.format("Buying %d Gnomish Pachinko plays for %s.", p.plays, self:PriceText(p.lots)))
    end)
    fieldTry(failed, "money", function() MoneyInputFrame_SetCopper(SendMailMoney, p.copper) end)
    local okMoney, copper = pcall(MoneyInputFrame_GetCopper, SendMailMoney)
    if not (okMoney and copper == p.copper) then
        local seen = false
        for _, label in ipairs(failed) do if label == "money" then seen = true end end
        if not seen then failed[#failed + 1] = "money" end
    end
    local price = self:PriceText(p.lots)
    if #failed == 0 then
        GP:Print("Mail filled out: " .. price .. " to " .. banker .. " for |cffffd700" .. p.plays .. "|r plays. Press Send to complete.")
    else
        GP:Print("|cffff8800Could not fill in: " .. table.concat(failed, ", ") .. ".|r Send " .. price .. " to " .. banker ..
            " with \"" .. self.SUBJECT .. "\" as the subject for |cffffd700" .. p.plays .. "|r plays.")
    end
end

function P:FillPurchaseMail(lots)
    lots = floor(tonumber(lots) or 0)
    if lots < 1 then return false, "Buy at least one lot (" .. self:PriceText(1) .. ")" end
    if not (MailFrame and MailFrame:IsShown()) then
        return false, "Visit a mailbox first: the helper fills the mail out there. " .. self.PLAYS_PER_LOT ..
            " plays cost " .. self:PriceText(1) .. ", sent to " .. self:BankerName() .. " with \"" .. self.SUBJECT .. "\" as the subject."
    end
    local copper = lots * self.PRICE_COPPER
    if GetMoney and GetMoney() < copper then
        return false, "You do not have " .. self:PriceText(lots) .. " on you"
    end
    self.pendingFill = { lots = lots, copper = copper, plays = lots * self.PLAYS_PER_LOT }
    if SendMailFrame and SendMailFrame:IsShown() then
        self:ApplyPendingFill()
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            if self.pendingFill then GP:Print("Open the mailbox's |cffffd700Send Mail|r tab and the purchase fills in.") end
        end)
    end
    return true
end

-- Credits a confirmed purchase (also what the mail hook calls).
function P:OnPurchase(copper)
    local lots = floor(copper / self.PRICE_COPPER)
    if lots <= 0 then return 0 end
    local left = self:AddLots(lots)
    GP:Print(string.format("|cff00ff00Plays purchased!|r %s mailed to the banker: |cffffd700%d|r plays, good for 24 hours. Plays left: |cffffd700%d|r",
        self:PriceText(lots), lots * self.PLAYS_PER_LOT, left))
    GP:PlaySfx("free_ball.ogg")
    if GP.UI and GP.UI.OnPlaysChanged then GP.UI:OnPlaysChanged() end
    return lots
end

if MailFrame then
    local mailBtn = CreateFrame("Button", nil, MailFrame, "UIPanelButtonTemplate")
    mailBtn:SetSize(130, 22)
    mailBtn:SetPoint("TOPLEFT", MailFrame, "BOTTOMLEFT", 4, -2)
    mailBtn:SetText("Buy Pachinko Plays")
    mailBtn:SetScript("OnClick", function()
        local ok, err = P:FillPurchaseMail(1)
        if not ok then GP:Print(err) end
    end)
    mailBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Gnomish Pachinko: buy plays for the day")
        GameTooltip:AddLine(P:PriceText(1) .. " = " .. P.PLAYS_PER_LOT .. " plays", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(P:StatusText(), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    mailBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    P.mailHelperButton = mailBtn
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
            if short:lower() == BANKER and money >= P.PRICE_COPPER and okS and s:lower():find("pachinko", 1, true) then
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
