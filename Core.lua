--[[
    Gnomish Pachinko - Core.lua
    Namespace, saved progress and the slash commands. No gold is ever won:
    this is a game of 1000 levels to clear. Losing a level costs one of
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
    current = 1,           -- level the window opens on
    sound = true,
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
            if type(v) == "table" then db[k] = {} else db[k] = v end
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
    return stars, self.Plays:Remaining()
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
    elseif msg == "plays" then
        GP:Print(GP.Plays:StatusText())
    elseif msg:match("^buy") then
        local lots = tonumber(msg:match("%d+")) or 1
        local ok, err = GP.Plays:FillPurchaseMail(lots)
        if not ok then GP:Print(err) end
    elseif msg == "reset" then
        GnomishPachinkoDB = nil
        GP.db = nil
        GP:GetDB()
        GP:Print("Progress wiped. Back to level 1. (The day's plays are not reset.)")
        if GP.UI.frame then GP.UI:StartLevel(1) end
    else
        GP:Print("/pachinko - open the game. /pachinko levels - level select. /pachinko <n> - play level n. " ..
            "/pachinko plays - plays left today. /pachinko buy [lots] - fill out the mail for more plays at a mailbox. " ..
            "/pachinko sound - toggle sound. /pachinko reset - wipe progress.")
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
    elseif event == "PLAYER_LOGOUT" then
        GP.Plays:Save()
    end
end)
