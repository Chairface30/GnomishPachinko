--[[
    Gnomish Pachinko - Dialog.lua
    Short conversations before a level: Tinkmaster introduces himself,
    explains each mechanic the first time it turns up, and the
    adversaries (the bosses and his brother Cogwhistle) introduce
    themselves, each as a creature model from the game. Every line is
    spoken (Sounds/Voice/dialog/<script>_<n>.ogg, voiced by
    tools/gen_dialog.py); a line with no clip falls back to a mumble.
    Continue and Skip cut the voice off at once. A conversation is shown
    once (db.dialogs) and the level card follows it.
]]

local GP = GnomishPachinko
GP.Dialog = GP.Dialog or {}
local D = GP.Dialog

-- Who speaks: a name, the creature whose model stands in, and the voice.
D.SPEAKERS = {
    tink   = { name = "Tinkmaster Overspark",    npc = 7406, voice = "mumble" },
    mekka  = { name = "High Tinker Mekkatorque", npc = 7937, voice = "mumble" },
    razzle = { name = "Razzle Sprysprocket",     npc = 1269, voice = "mumble" },
    bink   = { name = "Bink",                    npc = 5144, voice = "mumble" },
    cog    = { name = "Cogwhistle Overspark", npc = 7800, voice = "mumble" },
    drake  = { name = "Tin Drake",            npc = 6235, voice = "grumble" },
    golem  = { name = "Bolt Golem",           npc = 6229, voice = "grumble" },
    spider = { name = "Gyro Spider",          npc = 7361, voice = "grumble" },
    boar   = { name = "Mechano-Boar",         npc = 6228, voice = "grumble" },
    yeti   = { name = "Cog Yeti",             npc = 7079, voice = "grumble" },
}
D.MUMBLES = 6       -- Sounds/mumble1..6.ogg and grumble1..6.ogg

-- The conversations. `when` decides whether one belongs to a level's state.
D.SCRIPTS = {
    { key = "intro", when = function(st) return st.level == 1 end, lines = {
        { "tink", "Well hello there! Tinkmaster Overspark, chief engineer of Tinker Town, at your service." },
        { "tink", "This is my finest invention: the Gnomish Pachinko! Point with the mouse, click to shoot." },
        { "tink", "Light every orange peg and the board is yours. Ten balls a level." },
        { "tink", "Hit a green peg and you get my power: Multiball, or my Super Guide. Pick one on the level card. Off you go!" },
    } },
    { key = "host_mekka", when = function(st) return GP:HostFor(st.level).id == "mekka" end, lines = {
        { "mekka", "High Tinker Mekkatorque, at your service. Tinkmaster tells me you're rather good at this." },
        { "mekka", "While I host, the green pegs give you my inventions: Space Blast, or Chain Lightning. Choose wisely!" },
    } },
    { key = "host_razzle", when = function(st) return GP:HostFor(st.level).id == "razzle" end, lines = {
        { "razzle", "Razzle Sprysprocket here! I've got the fun toys this chapter." },
        { "razzle", "My Pyramid bounces your ball back up from the bottom, and Free Ball Frenzy hands you three extra balls. Have at it!" },
    } },
    { key = "host_bink", when = function(st) return GP:HostFor(st.level).id == "bink" end, lines = {
        { "bink", "Hello hello! Bink, apprentice extraordinaire. It's my turn to run the machine!" },
        { "bink", "My powers are a little magical: a Fireball that burns straight through pegs, and a Spooky Ball that comes back from the bottom." },
    } },
    { key = "bricks", when = function(st) for _, p in ipairs(st.pegs) do if p.shape == "brick" and not p.cradle then return true end end end, lines = {
        { "host", "Bricks! They light up just like pegs, and they make lovely ramps." },
    } },
    { key = "slide", when = function(st) return st.level == 8 end, lines = {
        { "host", "Now this is a beauty: a spiral of bricks." },
        { "host", "It's a rail! Drop the ball into its mouth on the left and it runs along the inside like a road, all the way round. That's a Super Slide!" },
        { "host", "Hold the right mouse button to zoom in and line the shot up with the mouth. Go on, clear the whole spiral in one shot." },
    } },
    { key = "items", when = function(st) return st.level == 2 end, lines = {
        { "host", "See the buttons to the left of the board? Those are my special balls." },
        { "host", "Ring of Fire burns a small circle, Rainbow Ball a big one, and the Suction Tube pulls a falling ball into the bucket. Click one before you shoot." },
    } },
    { key = "balloons", when = function(st) for _, p in ipairs(st.pegs) do if p.balloon and not p.post then return true end end end, lines = {
        { "host", "Balloons! They never light, but they bounce the ball off at whatever angle it strikes them." },
        { "host", "Use them for a ricochet, or curse them when they're in the way." },
    } },
    { key = "tough", when = function(st) for _, p in ipairs(st.pegs) do if (p.maxhp or 1) > 1 and p.kind ~= "egg" and p.kind ~= "boss" then return true end end end, lines = {
        { "host", "Steel-rimmed pieces take two hits, gold-rimmed three. They crack first, so keep at them." },
    } },
    { key = "eggs", when = function(st) return st.objective == "eggs" or st.objective == "mixed_eggs" end, lines = {
        { "host", "Phoenix eggs! Two hits hatch one, and the phoenix bursts straight up through everything above it." },
        { "host", "But mind the bricks holding them. Knock a cradle away and the egg falls. Catch it in the bucket, or the level is lost!" },
    } },
    { key = "gems", when = function(st) return st.objective == "gems" or st.objective == "mixed_gems" end, lines = {
        { "host", "Gems on ledges. Hitting a gem only shoves it: knock out the bricks under it and let it drop off the bottom." },
        { "host", "One that lands in the bucket is a Bucket Drop bonus!" },
    } },
    { key = "mixed", when = function(st) return st.objective == "mixed_eggs" or st.objective == "mixed_gems" end, lines = {
        { "host", "Two jobs at once from here on: the orange pegs and the eggs or gems. Both, or no clear!" },
    } },
    { key = "keys", when = function(st) for _, p in ipairs(st.pegs) do if p.kind == "key" then return true end end end, lines = {
        { "host", "A key! Light it and its cage falls away. Sometimes the key is locked behind another cage." },
    } },
    { key = "longshots", when = function(st) return st.objective == "longshots" end, lines = {
        { "host", "Long Shots! Light two orange pegs far apart in one shot. Bank it off a wall and let it fly across." },
    } },
    { key = "nobucket", when = function(st) return st.noBucket end, lines = {
        { "host", "No bucket on this one. The only free balls are the score marks, so make every ball count." },
    } },
    { key = "gimmick", when = function(st) return st.gimmick ~= nil end, lines = {
        { "host", "Moving parts! Time your shot, or use them to bank the ball where you want it." },
    } },
    -- the adversaries, the first time each one turns up
    { key = "boss_drake", when = function(st) return st.boss and st.boss.ability == "drake" end, lines = {
        { "drake", "Intruder. Tin Drake online. Speed increases as damage accumulates." },
        { "host", "A rogue drake from the workshop! Get the ball down past the pegs and keep hitting it." },
    } },
    { key = "boss_golem", when = function(st) return st.boss and st.boss.ability == "golem" end, lines = {
        { "golem", "BOLT GOLEM. SHIELD CYCLE ARMED." },
        { "host", "It raises a shield every third shot. Two hits break it. And watch for the scrap it throws!" },
    } },
    { key = "boss_spider", when = function(st) return st.boss and st.boss.ability == "spider" end, lines = {
        { "spider", "Skitter skitter. You will never pin the Gyro Spider down." },
        { "host", "It jumps when you hit it. Keep the ball low and keep it busy." },
    } },
    { key = "boss_boar", when = function(st) return st.boss and st.boss.ability == "boar" end, lines = {
        { "boar", "SNORT. CHARGE. SNORT." },
        { "host", "The Mechano-Boar turns tail every time it's hit. Learn its charge and lead your shots." },
    } },
    { key = "boss_yeti", when = function(st) return st.boss and st.boss.ability == "yeti" end, lines = {
        { "yeti", "Cog Yeti repairs. Cog Yeti always repairs." },
        { "host", "Miss it and it heals. Every shot has to count!" },
    } },
    { key = "duel", when = function(st) return st.objective == "duel" end, lines = {
        { "cog", "Well, well. My brother's little peg machine. Still playing, I see." },
        { "host", "Cogwhistle Overspark, Tinkmaster's brother! Clear this board first, friend, then he'll want a duel. Five balls each." },
        { "cog", "And every shot that lights no orange costs you five hundred. Do try to keep up." },
    } },
}

local function db()
    local d = GP:GetDB()
    d.dialogs = d.dialogs or {}
    return d.dialogs
end

-- The conversations this level brings that have not been shown yet.
function D:For(st)
    local seen = db()
    local list = {}
    for _, sc in ipairs(self.SCRIPTS) do
        if not seen[sc.key] and sc.when(st) then list[#list + 1] = sc end
    end
    return list
end

-- ---------------------------------------------------------------------
-- The window: a panel over the board with the speaker on the left.

function D:Create(parent, anchor, frameLevel)
    if self.panel then return end
    local ART = GP.Art
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(440, 170)
    panel:SetPoint("CENTER", anchor, "CENTER", 0, -40)
    panel:SetFrameLevel(frameLevel)
    panel:EnableMouse(true)
    panel.skin = ART:NewSkin(panel, "card", "BACKGROUND", 0)
    panel:Hide()
    self.panel = panel

    local portrait = CreateFrame("PlayerModel", nil, panel)
    portrait:SetSize(110, 120)
    portrait:SetPoint("LEFT", panel, "LEFT", 26, -4)
    self.model = portrait
    -- the speaker keeps talking for as long as the box is open: the talk
    -- animation is restarted whenever it ends (and every few seconds, in
    -- case the client does not report the end)
    D.TALK_ANIM = 60
    portrait:SetScript("OnAnimFinished", function(m)
        if panel:IsShown() then pcall(m.SetAnimation, m, D.TALK_ANIM) end
    end)
    panel:SetScript("OnUpdate", function(_, elapsed)
        D.talkClock = (D.talkClock or 0) + elapsed
        if D.talkClock >= 2.5 then
            D.talkClock = 0
            pcall(portrait.SetAnimation, portrait, D.TALK_ANIM)
        end
    end)

    panel.name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.name:SetPoint("TOPLEFT", panel, "TOPLEFT", 146, -30)
    panel.name:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.text:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -8)
    panel.text:SetWidth(260)
    panel.text:SetJustifyH("LEFT")
    panel.text:SetJustifyV("TOP")

    local nextBtn = CreateFrame("Button", nil, panel)
    nextBtn:SetSize(110, 26)
    nextBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 26)
    nextBtn.skin = ART:NewSkin(nextBtn, "button_green", "BACKGROUND", 0)
    nextBtn.text = nextBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nextBtn.text:SetPoint("CENTER")
    nextBtn.text:SetText("Continue")
    nextBtn:SetScript("OnClick", function() D:Advance() end)
    panel.next = nextBtn

    local skip = CreateFrame("Button", nil, panel)
    skip:SetSize(70, 22)
    skip:SetPoint("RIGHT", nextBtn, "LEFT", -8, 0)
    skip.text = skip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skip.text:SetPoint("CENTER")
    skip.text:SetText("Skip")
    skip:SetScript("OnClick", function() D:Finish() end)
    panel.skip = skip
end

-- Plays a list of conversations, then calls done().
function D:Play(list, done)
    if not self.panel or #list == 0 then
        if done then done() end
        return false
    end
    self.queue = {}
    for _, sc in ipairs(list) do
        db()[sc.key] = true
        for n, line in ipairs(sc.lines) do
            local who, clip = line[1], sc.key .. "_" .. n
            if who == "host" then
                who = GP:Host().id
                clip = clip .. "_" .. who
            end
            self.queue[#self.queue + 1] = { who, line[2], clip = clip }
        end
    end
    self.done = done
    self.index = 0
    self.panel:Show()
    self:Advance()
    return true
end

function D:Show(line)
    local sp = self.SPEAKERS[line[1]] or self.SPEAKERS.tink
    self.panel.name:SetText("|cffffd700" .. sp.name .. "|r")
    self.panel.text:SetText(line[2])
    if self.speaker ~= line[1] then
        self.speaker = line[1]
        pcall(self.model.SetCreature, self.model, sp.npc)
        pcall(self.model.SetPosition, self.model, 0, 0, 0)
        pcall(self.model.SetFacing, self.model, 0.4)
        if self.model.SetCamera then pcall(self.model.SetCamera, self.model, 0) end
    end
    if self.model.SetAnimation then pcall(self.model.SetAnimation, self.model, self.TALK_ANIM or 60) end   -- talk
    self.talkClock = 0
    self:StopVoice()
    GP:StopVoice()
    local willPlay, handle = self:PlayLine(line.clip)
    if not willPlay then
        willPlay, handle = GP:PlaySfx(sp.voice .. math.random(self.MUMBLES) .. ".ogg")
    end
    self.voiceHandle = handle
end

-- The spoken line, on the Dialog channel (the voice setting can mute it).
function D:PlayLine(clip)
    local db = GP:GetDB()
    if not clip or db.sound == false or db.voice == false then return false end
    local ok, willPlay, handle = pcall(PlaySoundFile, "Interface\\AddOns\\GnomishPachinko\\Sounds\\Voice\\dialog\\" .. clip .. ".ogg", "Dialog")
    if ok then return willPlay, handle end
    return false
end

-- Cuts the current line off at once.
function D:StopVoice()
    if self.voiceHandle and type(StopSound) == "function" then pcall(StopSound, self.voiceHandle, 0) end
    self.voiceHandle = nil
end

function D:Advance()
    self:StopVoice()
    self.index = (self.index or 0) + 1
    local line = self.queue and self.queue[self.index]
    if not line then return self:Finish() end
    self:Show(line)
    self.panel.next.text:SetText(self.index < #self.queue and "Continue" or "Let's go!")
end

function D:Finish()
    self:StopVoice()
    if self.panel then self.panel:Hide() end
    self.queue, self.speaker = nil, nil
    local done = self.done
    self.done = nil
    if done then done() end
end

function D:IsShown()
    return self.panel and self.panel:IsShown() or false
end
