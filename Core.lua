--[[
    Gnomish Pachinko - Core.lua
    Namespace, saved progress and the slash commands. No gold is ever won:
    this is a game of 400 levels to clear. Losing a level costs one of
    the day's plays (Plays.lua); extra plays can be bought by mail.
]]

GnomishPachinko = GnomishPachinko or {}
local GP = GnomishPachinko
GP.version = "0.7.1"

local ADDON_NAME, ns = ...
ns = ns or {}

local DEFAULTS = {
    unlocked = 1,          -- highest level the player may start
    cleared = {},          -- [level] = true
    best = {},             -- [level] = best score
    stars = {},            -- [level] = best stars (1-3)
    tips = {},             -- first-encounter tips already shown
    lastPower = nil,       -- the power picked on the level card
    current = 1,           -- level the window opens on
    sound = true,          -- sound effects and voices
    music = true,          -- the music (Fever)
    voice = true,          -- the announcer's lines (Sounds/Voice)
    minimap = { hide = false, angle = 220 },
    scale = 1,
}

function GP:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc88ff[Gnomish Pachinko]|r " .. tostring(msg))
end

-- The version comes from the TOC, so the window and the addon list agree.
GP.AUTHOR = "Chairface Chippendale"
GP.VERSION_FALLBACK = "0.7.1"
function GP:Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if get then
        local ok, v = pcall(get, "GnomishPachinko", "Version")
        if ok and type(v) == "string" and v ~= "" then return v end
    end
    return self.VERSION_FALLBACK
end

-- Colorblind mode: a mark on every orange, green and purple piece (blue has
-- none), so the colors never have to be told apart by hue alone.
function GP:ToggleColorblind(on)
    local db = self:GetDB()
    if on == nil then on = not db.colorblind end
    db.colorblind = on and true or false
    self:Print("Colorblind mode " .. (db.colorblind and "on: orange pieces wear a triangle, green a plus, the purple a star." or "off."))
    if self.UI and self.UI.settingBoxes and self.UI.settingBoxes.colorblind then self.UI.settingBoxes.colorblind:SetChecked(db.colorblind) end
    if self.Editor and self.Editor.frame and self.Editor.frame:IsShown() then self.Editor:Redraw() end
    return db.colorblind
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

-- Music: its own switch, apart from the sound effects.
function GP:PlayMusic(file)
    local db = self.db or self:GetDB()
    if db.music == false then return end
    return PlaySoundFile("Interface\\AddOns\\GnomishPachinko\\Sounds\\" .. file, "SFX")
end

function GP:PlaySfx(file)
    local db = self.db or self:GetDB()
    if db.sound == false then return end
    return PlaySoundFile("Interface\\AddOns\\GnomishPachinko\\Sounds\\" .. file, "SFX")
end

-- The announcer. Lines live in Sounds/Voice/<name>.ogg (see ASSETS.md);
-- a line that is not there yet simply does not play.
-- `host` (optional) speaks instead of the level's host: a power is
-- announced by the host it belongs to.
function GP:PlayVoice(name, host)
    local db = self.db or self:GetDB()
    if db.sound == false or db.voice == false then return end
    if self.Dialog and self.Dialog:IsShown() then return end
    self:StopVoice()
    local dir = (host or self:Host()).voiceDir or ""
    local ok, played, handle = pcall(PlaySoundFile, "Interface\\AddOns\\GnomishPachinko\\Sounds\\Voice\\" .. dir .. name .. ".ogg", "Dialog")
    if ok and played then self.voiceHandle = handle end
    return ok and played
end

-- Cuts the announcer's current line off.
function GP:StopVoice()
    if self.voiceHandle and type(StopSound) == "function" then pcall(StopSound, self.voiceHandle, 0) end
    self.voiceHandle = nil
end

-- Progress -------------------------------------------------------------

function GP:IsUnlocked(level)
    return level >= 1 and level <= self.Levels.COUNT and level <= (self:GetDB().unlocked or 1)
end

-- Records a finished level. Returns the stars earned this time and the
-- plays left for the day (a lost level spends one).
GP.CHAPTER_REWARDS = { { item = "ring", n = 1 }, { item = "rainbow", n = 1 }, { item = "suction", n = 1 } }

function GP:RecordResult(result)
    -- only a result the engine itself produced counts, and only once
    if not (type(result) == "table" and ns.issued and ns.issued[result]) then
        return 0, self.Plays:Remaining()
    end
    ns.issued[result] = nil
    local db = self:GetDB()
    local n = result.level
    local stars = self.Levels:StarsFor(n, result.score, result.cleared)
    local wasCleared = db.cleared and db.cleared[n]
    if not result.cleared then self.Plays:RecordFail() end
    -- clearing a chapter (its last level, the boss or the duel) gives one of
    -- each special ball, the first time only; everything else is bought with gears
    local rewards = {}
    if result.cleared and n % self.Levels.PER_CHAPTER == 0 and not wasCleared then
        for _, r in ipairs(self.CHAPTER_REWARDS) do
            ns.Secure.AddItem(r.item, r.n)
            rewards[#rewards + 1] = r
        end
    end
    result.rewards = rewards
    -- Tinkmaster's own duel won: the Super Guide becomes the Crazy Guide
    local crazy = result.cleared and n == self.Levels.TINK_DUEL_LEVEL and not db.crazyGuide
    if crazy then result.crazyGuide = true end
    ns.Progress.Record(n, result.cleared, stars, result.score or 0, crazy, self.Levels.COUNT)
    self.Plays:Save()
    return stars, self.Plays:Remaining()
end

-- Debugging (owner characters only): special balls and boosts never run out.
function GP:Unlimited()
    local db = self:GetDB()
    return db.debugUnlimited and self.Plays and self.Plays:IsOwner() or false
end

function GP:ToggleUnlimited()
    if not (self.Plays and self.Plays:IsOwner()) then
        self:Print("Unlimited items are for the owner's characters only.")
        return false
    end
    local db = self:GetDB()
    db.debugUnlimited = not db.debugUnlimited
    self:Print("Unlimited special balls and boosts " .. (db.debugUnlimited and "on" or "off") .. " (testing).")
    if self.UI and self.UI.frame then self.UI:UpdateDisplay() end
    return db.debugUnlimited
end

function GP:ItemCount(item)
    if self:Unlimited() then return 99 end
    return self.Plays:ItemOf(item)
end

function GP:SpendItem(item)
    if self:Unlimited() then return true end
    if self.Plays:ItemOf(item) <= 0 then return false end
    ns.Secure.AddItem(item, -1)
    return true
end

-- The powers unlocked so far: one per chapter reached.
-- The four hosts take the chapters in turn. Each is a gnome with a model
-- from the game, a voice of their own (Sounds/Voice/<voiceDir>) and two
-- powers, the ones on offer while they host.
GP.HOSTS = {
    -- z: the model's height in its ring (a share of the frame); scale: its zoom
    { id = "tink",   name = "Tinkmaster Overspark",    npc = 7406, voiceDir = "",        powers = { "multiball", "guide" },    z = -0.09, scale = 1.02 },
    { id = "mekka",  name = "High Tinker Mekkatorque", npc = 7937, voiceDir = "mekka\\",  powers = { "blast", "lightning" },   z = -0.14, scale = 1.10 },
    { id = "razzle", name = "Razzle Sprysprocket",     npc = 1269, voiceDir = "razzle\\", powers = { "pyramid", "frenzy" },     z = -0.16, scale = 1.16 },
    { id = "bink",   name = "Bink",                    npc = 5144, voiceDir = "bink\\",   powers = { "fireball", "spooky" },    z = -0.31, scale = 1.49 },
}

-- The host a power belongs to.
function GP:HostForPower(power)
    for _, h in ipairs(self.HOSTS) do
        for _, p in ipairs(h.powers) do if p == power then return h end end
    end
end

function GP:HostFor(level)
    local chapter = math.floor(((level or 1) - 1) / 10) + 1
    return self.HOSTS[((chapter - 1) % #self.HOSTS) + 1]
end

-- The host on duty: the level being played, or the one the window opens on.
function GP:Host()
    local st = self.UI and self.UI.state
    return self:HostFor(st and st.level or self:GetDB().current or 1)
end

-- The powers on offer on a level: its host's two.
function GP:UnlockedPowers(level)
    local h = level and self:HostFor(level) or self:Host()
    return { h.powers[1], h.powers[2] }
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
    ns.Progress.UnlockAll(self.Levels.COUNT)
    self.Plays:Save()
    self:Print(("All %d levels unlocked for testing."):format(self.Levels.COUNT))
    if self.UI and self.UI.levelPanel and self.UI.levelPanel:IsShown() then self.UI:LevelPage(self.UI.levelPage) end
    return true
end

function GP:ResetProgress()
    -- keep the settings, wipe the progress; the special balls and green
    -- pegs go back to what a new player starts with (gears and plays stay)
    ns.Secure.ResetItems()
    local keep = GnomishPachinkoDB or {}
    GnomishPachinkoDB = { sound = keep.sound, music = keep.music, voice = keep.voice, minimap = keep.minimap, mascot = keep.mascot }
    self.db = nil
    self:GetDB()
    ns.Progress.FromSettings()
    self.Plays:Save()
    if self.Levels then self.Levels.starCache = nil end
    self:Print("Progress wiped: back to level 1, special balls and green pegs back to a new player's. (Gears and the day's plays are kept.)")
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
    elseif msg == "music" then
        local db = GP:GetDB()
        db.music = db.music == false
        GP:Print("Music " .. (db.music and "on" or "off") .. ".")
        if not db.music and GP.UI and GP.UI.StopFanfare then GP.UI:StopFanfare(true) end
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
        local gears = tonumber(msg:match("%d+")) or GP.Plays.DEFAULT_GEARS_MAIL
        local ok, err = GP.Plays:FillPurchaseMail(gears)
        if not ok then GP:Print(err) end
    elseif msg:match("^shop%s+%a+") then
        local ok, m = GP.Plays:Buy(msg:match("^shop%s+(%a+)"))
        GP:Print(m)
        if ok and GP.UI and GP.UI.frame then GP.UI:UpdateDisplay() end
    elseif msg == "gears" then
        GP:Print(("Golden Gears: %d. Shop: suction (1), green (1), ring (2), rainbow (3), plays (10). /pachinko shop <item>; /pachinko buy <n> fills the mail for n gears."):format(GP.Plays:Gears()))
    elseif msg == "colorblind" or msg == "colourblind" then
        GP:ToggleColorblind()
    elseif msg == "editor" or msg == "edit" then
        GP.Editor:Toggle()
    elseif msg == "reset" then
        GP:ResetProgress()
    elseif msg == "unlockall" then
        GP:UnlockAll()
    elseif msg == "unlimited" then
        GP:ToggleUnlimited()
    else
        GP:Print("/pachinko - open the game. /pachinko levels - level select. /pachinko <n> - play level n. /pachinko editor - the level editor. /pachinko colorblind - marks on the colored pegs. " ..
            "/pachinko plays - plays left and the next daily plays. /pachinko buy [lots] - fill out the mail for more plays at a mailbox. " ..
            "/pachinko sound - toggle sound. /pachinko music - toggle the music. /pachinko voice - toggle the announcer. /pachinko minimap - show or hide the minimap button. /pachinko mascot - Tinkmaster Overspark in the corner (mascot target, npc <id>, scale, play <animation>). /pachinko reset - wipe progress. /pachinko unlockall - open every level (owner characters, for testing). /pachinko unlimited - endless special balls and boosts (owner characters, for testing).")
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
        GP.Plays:StripPlain()       -- the progress lives only in the sealed vault
    end
end)
