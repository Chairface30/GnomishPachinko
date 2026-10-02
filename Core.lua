--[[
    Gnomish Pachinko - Core.lua
    Namespace, saved progress and the slash commands. No gold is ever won:
    this is a game of 400 levels to clear. Losing a level costs one of
    the day's plays (Plays.lua); extra plays can be bought by mail.
]]

GnomishPachinko = GnomishPachinko or {}
local GP = GnomishPachinko
GP.version = "1.1.0"

local ADDON_NAME = ...

local DEFAULTS = {
    unlocked = 1,          -- highest level the player may start
    cleared = {},          -- [level] = true
    best = {},             -- [level] = best score
    stars = {},            -- [level] = best stars (1-3)
    items = { ring = 2, rainbow = 0, green = 1 },   -- power-ups and boosts earned
    tips = {},             -- first-encounter tips already shown
    lastPower = nil,       -- the power picked on the level card
    current = 1,           -- level the window opens on
    sound = true,
    voice = true,          -- the announcer's lines (Sounds/Voice)
    minimap = { hide = false, angle = 220 },
    scale = 1,
}

function GP:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc88ff[Gnomish Pachinko]|r " .. tostring(msg))
end

function GP:GetDB()
    GnomishPachinkoDB = GnomishPachinkoDB or {}
    local db = GnomishPachinkoDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then
                db[k] = {}
                for kk, vv in pairs(v) do db[k][kk] = vv end
            else
                db[k] = v
            end
        elseif type(v) == "table" and type(db[k]) == "table" then
            -- new keys inside a saved table (the items list grows)
            for kk, vv in pairs(v) do if db[k][kk] == nil and type(vv) ~= "table" then db[k][kk] = vv end end
        end
    end
    self.db = db
    return db
end

function GP:PlaySfx(file)
    local db = self.db or self:GetDB()
    if db.sound == false then return end
    return PlaySoundFile("Interface\\AddOns\\GnomishPachinko\\Sounds\\" .. file, "SFX")
end

-- The announcer. Lines live in Sounds/Voice/<name>.ogg (see ASSETS.md);
-- a line that is not there yet simply does not play.
function GP:PlayVoice(name)
    local db = self.db or self:GetDB()
    if db.sound == false or db.voice == false then return end
    local ok, played = pcall(PlaySoundFile, "Interface\\AddOns\\GnomishPachinko\\Sounds\\Voice\\" .. name .. ".ogg", "Dialog")
    return ok and played
end

-- Progress -------------------------------------------------------------

function GP:IsUnlocked(level)
    return level >= 1 and level <= self.Levels.COUNT and level <= (self:GetDB().unlocked or 1)
end

-- Records a finished level. Returns the stars earned this time and the
-- plays left for the day (a lost level spends one).
function GP:RecordResult(result)
    local db = self:GetDB()
    local n = result.level
    local stars = self.Levels:StarsFor(n, result.score, result.cleared)
    if result.cleared then
        db.cleared[n] = true
        if n + 1 <= self.Levels.COUNT and (db.unlocked or 1) < n + 1 then db.unlocked = n + 1 end
        if stars > (db.stars[n] or 0) then db.stars[n] = stars end
    else
        self.Plays:RecordFail()
    end
    if result.score > (db.best[n] or 0) then db.best[n] = result.score end
    -- rewards: a Ring of Fire for a clear, an Extra Green Peg for three
    -- stars, two Rainbow Balls for a boss or a duel won
    local rewards = {}
    if result.cleared then
        db.items = db.items or { ring = 0, rainbow = 0, green = 0 }
        db.items.ring = (db.items.ring or 0) + 1
        rewards[#rewards + 1] = { item = "ring", n = 1 }
        if stars >= 3 then db.items.green = (db.items.green or 0) + 1; rewards[#rewards + 1] = { item = "green", n = 1 } end
        if result.objective == "boss" or result.duel then db.items.rainbow = (db.items.rainbow or 0) + 2; rewards[#rewards + 1] = { item = "rainbow", n = 2 } end
    end
    result.rewards = rewards
    return stars, self.Plays:Remaining()
end

function GP:ItemCount(item)
    local db = self:GetDB()
    db.items = db.items or { ring = 0, rainbow = 0, green = 0 }
    return db.items[item] or 0
end

function GP:SpendItem(item)
    local db = self:GetDB()
    db.items = db.items or { ring = 0, rainbow = 0, green = 0 }
    if (db.items[item] or 0) <= 0 then return false end
    db.items[item] = db.items[item] - 1
    return true
end

-- The powers unlocked so far: one per chapter reached.
function GP:UnlockedPowers()
    local db = self:GetDB()
    local chapter = math.floor(((db.unlocked or 1) - 1) / self.Levels.PER_CHAPTER) + 1
    local n = math.min(#self.Engine.POWERS, chapter)
    local list = {}
    for i = 1, n do list[i] = self.Engine.POWERS[i].id end
    return list
end

function GP:ClearedCount()
    local n = 0
    for _ in pairs(self:GetDB().cleared) do n = n + 1 end
    return n
end

function GP:TotalStars()
    local n = 0
    for _, s in pairs(self:GetDB().stars) do n = n + (tonumber(s) or 0) end
    return n
end

-- Wipes levels, stars and best scores. The day's plays live in the vault
-- and are not touched.
-- For testing: the owner's characters can open every level on the map.
function GP:UnlockAll()
    if not (self.Plays and self.Plays:IsOwner()) then
        self:Print("Unlock all is for the owner's characters only.")
        return false
    end
    self:GetDB().unlocked = self.Levels.COUNT
    self:Print(("All %d levels unlocked for testing."):format(self.Levels.COUNT))
    if self.UI and self.UI.levelPanel and self.UI.levelPanel:IsShown() then self.UI:LevelPage(self.UI.levelPage) end
    return true
end

function GP:ResetProgress()
    GnomishPachinkoDB = nil
    self.db = nil
    self:GetDB()
    if self.Levels then self.Levels.starCache = nil end
    self:Print("Progress wiped. Back to level 1. (The day's plays are not reset.)")
    if self.UI and self.UI.frame then
        self.UI:HideLevelSelect()
        self.UI:StartLevel(1)
    end
end

-- Slash ----------------------------------------------------------------

SLASH_GNOMISHPACHINKO1 = "/pachinko"
SLASH_GNOMISHPACHINKO2 = "/gp"
SlashCmdList["GNOMISHPACHINKO"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" then
        GP.UI:Toggle()
    elseif msg == "levels" then
        GP.UI:Show()
        GP.UI:ShowLevelSelect()
    elseif msg:match("^level%s+%d+") or msg:match("^%d+$") then
        local n = tonumber(msg:match("(%d+)"))
        if n and GP:IsUnlocked(n) then
            GP.UI:Show()
            GP.UI:StartLevel(n)
        else
            GP:Print("Level " .. tostring(n) .. " is not unlocked yet.")
        end
    elseif msg == "sound" then
        local db = GP:GetDB()
        db.sound = not db.sound
        GP:Print("Sound " .. (db.sound and "on" or "off") .. ".")
    elseif msg == "voice" then
        local db = GP:GetDB()
        db.voice = not db.voice
        GP:Print("Tinkmaster Overspark's voice " .. (db.voice and "on" or "off") .. ".")
    elseif msg == "minimap" then
        GP.Minimap:Toggle()
    elseif msg:match("^mascot") then
        GP.Mascot:Command(msg:match("^mascot%s*(.*)$"))
    elseif msg == "plays" then
        GP:Print(GP.Plays:StatusText())
    elseif msg:match("^buy") then
        local lots = tonumber(msg:match("%d+")) or 1
        local ok, err = GP.Plays:FillPurchaseMail(lots)
        if not ok then GP:Print(err) end
    elseif msg == "reset" then
        GP:ResetProgress()
    elseif msg == "unlockall" then
        GP:UnlockAll()
    else
        GP:Print("/pachinko - open the game. /pachinko levels - level select. /pachinko <n> - play level n. " ..
            "/pachinko plays - plays left today. /pachinko buy [lots] - fill out the mail for more plays at a mailbox. " ..
            "/pachinko sound - toggle sound. /pachinko voice - toggle the announcer. /pachinko minimap - show or hide the minimap button. /pachinko mascot - Tinkmaster Overspark in the corner (mascot target, npc <id>, scale, play <animation>). /pachinko reset - wipe progress. /pachinko unlockall - open every level (owner characters, for testing).")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_LOGOUT")
loader:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        GP:GetDB()
        loader:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        GP.Plays:Load()
        if GP.Minimap then GP.Minimap:Create() end
    elseif event == "PLAYER_LOGOUT" then
        GP.Plays:Save()
    end
end)
