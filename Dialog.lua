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
local _, ns = ...
ns = ns or {}
local GIFTS = {}     -- the tutorials' gifts, private to this file (filled once SCRIPTS is written)
GP.Dialog = GP.Dialog or {}
local D = GP.Dialog

-- Who speaks: a name, the creature whose model stands in, and the voice.
D.SPEAKERS = {
    tink   = { name = "Tinkmaster Overspark",    npc = 7406, voice = "mumble" },
    mekka  = { name = "High Tinker Mekkatorque", npc = 7937, voice = "mumble" },
    razzle = { name = "Razzle Sprysprocket",     npc = 1269, voice = "mumble" },
    bink   = { name = "Bink",                    npc = 5144, voice = "mumble" },
    -- Cogwhistle, the evil brother: Tinkmaster's own model lit a sickly green
    cog    = { name = "Cogwhistle Overspark", npc = 7406, tint = { 0, 1, 0 }, tintPower = 1.6, voice = "mumble" },
    -- the bosses: `models` are creature ids tried in turn for the board
    -- (the first the client has wins); `npc` is the first, for the dialog box
    drake  = { name = "Tin Drake",    npc = 8615, models = { 8615, 12473, 2678 }, voice = "grumble" },   -- Mithril, Arcanite, Mechanical Dragonling
    golem  = { name = "Bolt Golem",   npc = 6229, models = { 6229 }, voice = "grumble" },               -- Crowd Pummeler 9-60
    spider = { name = "Gyro Spider",  npc = 6235, models = { 6235, 6225 }, voice = "grumble" },         -- Electrocutioner 6000, Mechano-Tank
    boar   = { name = "Mechano-Boar", npc = 4422, models = { 4422 }, voice = "grumble" },               -- Agathelos the Raging, the armored boar
    yeti   = { name = "Cog Yeti",     npc = 7458, models = { 7458, 7457 }, voice = "grumble" },         -- Ice Thistle yetis
}
D.MUMBLES = 6       -- Sounds/mumble1..6.ogg and grumble1..6.ogg

-- Each speaker's framing in the box: z, the height (a share of the
-- window's height); x, a sideways nudge in pixels; scale, the zoom; yaw,
-- its turn; pitch, its tilt; cam, the camera's distance. Set by eye by
-- the user (2026-10-02); a speaker not listed keeps SPEAKER_VIEW.
D.PORTRAIT_W, D.PORTRAIT_H = 110, 120
D.PORTRAIT_CLIP_W = 136      -- the window runs from the box's left edge to just short of the text
D.SPEAKER_VIEW = { z = 0, x = 0, scale = 1, yaw = 0.4, pitch = 0, cam = 1 }
D.SPEAKER_VIEWS = {
    tink   = { z = -0.35, x = 15.81, scale = 2.28, yaw = 0.21,  pitch = 0, cam = 0.98 },
    mekka  = { z = -0.33, x = 14.86, scale = 2.42, yaw = -0.31, pitch = 0, cam = 1 },
    razzle = { z = -0.31, x = 17.71, scale = 1.91, yaw = -0.2,  pitch = 0, cam = 1 },
    bink   = { z = -0.4,  x = 8.19,  scale = 2.11, yaw = 0.4,   pitch = 0, cam = 1 },
    cog    = { z = -0.26, x = 12.95, scale = 4.18, yaw = -0.05, pitch = 0, cam = 2.08 },
    drake  = { yaw = 0.4 - math.pi },       -- turned half round: it faced away
}
function D:SpeakerView(key)
    local fixed = (key and self.SPEAKER_VIEWS[key]) or {}
    local v = {}
    for k, d in pairs(self.SPEAKER_VIEW) do
        if fixed[k] ~= nil then v[k] = fixed[k] else v[k] = d end
    end
    return v
end

-- The whole model (no portrait camera, which crops to the head), framed
-- by its view.
function D:PoseSpeaker()
    local m = self.model
    if not m then return end
    local v = self:SpeakerView(self.speakerKey)
    m:SetSize(self.PORTRAIT_W * v.scale, self.PORTRAIT_H * v.scale)
    m:ClearAllPoints()
    m:SetPoint("CENTER", self.portraitClip, "CENTER", v.x, v.z * self.PORTRAIT_H)
    pcall(function()
        if m.SetPortraitZoom then m:SetPortraitZoom(0) end
        if m.SetCamDistanceScale then m:SetCamDistanceScale(v.cam) end
        m:SetPosition(0, 0, 0)
        m:SetFacing(v.yaw)
    end)
    if m.SetPitch then pcall(m.SetPitch, m, v.pitch) end
end

-- Lights a model in one colour: a coloured ambient and a coloured
-- light from the front, so the whole model takes the tint. Both forms of
-- SetLight are tried (a table of values in newer clients, a long list of
-- numbers in older ones).
function D:TintModel(m, c, power)
    if not (m and m.SetLight) then return false end
    local r, g, b = c[1], c[2], c[3]
    local amb, dif = 0.8 * (power or 1), 1.0 * (power or 1)
    local ok = false
    if CreateColor and CreateVector3D then
        ok = pcall(m.SetLight, m, true, {
            omnidirectional = false,
            point = CreateVector3D(0, 1, -0.5),
            ambientIntensity = amb, ambientColor = CreateColor(r, g, b),
            diffuseIntensity = dif, diffuseColor = CreateColor(r, g, b),
        })
    end
    if not ok then
        ok = pcall(m.SetLight, m, true, false, 0, 1, -0.5, amb, r, g, b, dif, r, g, b)
    end
    return ok
end

-- The conversations. `when` decides whether one belongs to a level's state.
D.SCRIPTS = {
    -- Tinkmaster's own duel with his brother, and what winning it earns
    { key = "tink_duel", when = function(st) return st.level == GP.Levels.TINK_DUEL_LEVEL end, lines = {
        { "cog", "Well, well. Little brother. Still hiding behind your helpers?" },
        { "tink", "No helpers this time, Cogwhistle. This one is between you and me." },
        { "cog", "Clear the board, then five balls each, and the last orange takes it. Try not to cry." },
        { "tink", "Win this one for me, friend, and I will show you something special. My Crazy Guide!" },
    } },
    { key = "crazy_guide", when = function() return false end, lines = {
        { "tink", "You did it! Did you see his face? As promised: my Super Guide is now the Crazy Guide." },
        { "tink", "Five bounces of the path, every time you earn it. Don't tell Cogwhistle how it works!" },
    } },
    -- not tied to a level: played the first time Get Golden Gears is pressed away from a mailbox
    { key = "gears_help", when = function() return false end, lines = {
        { "tink", "Golden Gears, is it? They're the pachinko's own coin. One gold buys one gear." },
        { "tink", "Walk up to any mailbox and press Get Golden Gears again. I'll fill the mail out for you: gold to Chairface Chippendale, with pachinko golden gears as the subject." },
        { "tink", "But mind this: I will not, and I cannot, press Send for you. The Blizzard... ahem, the Gnomish Regulators forbid it! That last button is yours to press." },
        { "tink", "Send it off, and your gears turn up as soon as the gold arrives. Spend them in the shop on special balls, or on more plays!" },
    } },
    -- the very first thing a new player hears
    { key = "welcome", when = function(st) return st.level == 1 end, lines = {
        { "tink", "Well hello there! Tinkmaster Overspark, chief engineer of Tinker Town, at your service." },
        { "tink", "This is my finest invention: the Gnomish Pachinko Machine! Point with the mouse, click to shoot." },
        { "tink", "Light every orange peg and the board is yours. Ten balls a level." },
        { "tink", "Hit a green peg and you get my power: Multiball, or my Super Guide. Pick one on the level card before you start." },
    } },
    { key = "intro", when = function(st) return st.level == 1 end, lines = {
        { "tink", "Fair warning: the bosses are still a work in progress. They may change completely in a later version." },
        { "tink", "Got ideas? New gnome hosts with new powers, new obstacles, new bosses? Send them in on the Gnomish Pachinko page on CurseForge!" },
        { "tink", "Now, enough chatter! Step right up, grab the lever, and give her a whirl. Go on, off you go, and mind the sparks!" },
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
    -- the special balls, and one of each as a gift to try them out
    { key = "items", when = function(st) return st.level >= 2 end, gift = { ring = 1, rainbow = 1, suction = 1 }, lines = {
        { "host", "See the buttons to the left of the board? Those are my special balls.", highlight = { "ring", "rainbow", "suction" } },
        { "host", "Ring of Fire burns a small circle, Rainbow Ball a big one, and the Suction Tube pulls a falling ball into the bucket. Click one before you shoot.",
            highlight = { "ring", "rainbow", "suction" },
            cues = { { "Ring of Fire", "ring" }, { "Rainbow Ball", "rainbow" }, { "Suction Tube", "suction" }, { "Click one", "ring", "rainbow", "suction" } } },
        { "host", "Here's one of each, on the house. Go on, give them a try!", highlight = { "ring", "rainbow", "suction" }, givesGift = true },
    } },
    -- the Extra Green Peg, the level after the special balls
    { key = "green_peg", when = function(st) return st.level >= 3 end, gift = { green = 1 }, lines = {
        { "host", "One more toy for you: the Extra Green Peg. It's the new button under the special balls.",
            cues = { { "Extra Green Peg", "green" } } },
        { "host", "Click it on the level card, before you press Play, and the board gets one more green peg. Here's one to try!", highlight = { "green" }, givesGift = true },
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
        { "drake", "Hssss! Intruder! Tin Drake online. Dent me, and I only fly faster!" },
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
    { key = "duel", when = function(st) return st.objective == "duel" and st.level ~= GP.Levels.TINK_DUEL_LEVEL end, lines = {
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

-- Plays one conversation by key if it has not been shown yet (and nothing
-- else is talking). Returns true if it started.
function D:PlayOnce(key, done)
    if db()[key] or self:IsShown() then return false end
    for _, sc in ipairs(self.SCRIPTS) do
        if sc.key == key then return self:Play({ sc }, done) end
    end
    return false
end

-- The tutorials' gifts as this file wrote them, copied when it loaded: a
-- script added or changed later gives nothing.
do
    local gifts = {}
    for _, sc in ipairs(D.SCRIPTS) do
        if type(sc.gift) == "table" then
            local g = {}
            for k, v in pairs(sc.gift) do g[k] = v end
            gifts[sc.key] = g
        end
    end
    GIFTS = gifts
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

    -- the speaker, whole, in a window on the left that runs out to the box's
    -- edges: the fancy border is drawn again on a layer over the model, so
    -- the model sits behind it. Zoom and height move and size the model's
    -- frame (the client refits a model to its frame, undoing SetModelScale).
    local base = panel:GetFrameLevel()
    local clip = CreateFrame("Frame", nil, panel)
    clip:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
    clip:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 4)
    clip:SetWidth(D.PORTRAIT_CLIP_W)
    if clip.SetClipsChildren then pcall(clip.SetClipsChildren, clip, true) end
    if clip.SetFrameLevel then clip:SetFrameLevel(base + 1) end
    self.portraitClip = clip
    -- two model frames: one in the client's own light, one lit in a
    -- speaker's colour (a light set on a model frame stays on it, so the
    -- tinted speakers get a frame of their own)
    local function makeModel()
        local m = CreateFrame("PlayerModel", nil, clip)
        m:SetSize(D.PORTRAIT_W, D.PORTRAIT_H)
        m:SetPoint("CENTER", clip, "CENTER", 0, 0)
        if m.SetFrameLevel then m:SetFrameLevel(base + 2) end
        m:SetScript("OnModelLoaded", function() D:PoseSpeaker() end)
        m:SetScript("OnAnimFinished", function(self)
            if panel:IsShown() then pcall(self.SetAnimation, self, D.TALK_ANIM) end
        end)
        return m
    end
    local portrait = makeModel()
    self.plainModel = portrait
    self.tintModel = makeModel()
    self.tintModel:Hide()
    -- the border again, over the model (its middle left out)
    local rim = CreateFrame("Frame", nil, panel)
    rim:SetAllPoints(panel)
    if rim.SetFrameLevel then rim:SetFrameLevel(base + 3) end
    rim.skin = ART:NewSkin(rim, "card", "ARTWORK", 0, panel)
    if rim.skin.pieces[5] then rim.skin.pieces[5]:Hide() end
    self.rim = rim
    self.model = portrait
    -- the speaker keeps talking for as long as the box is open: the talk
    -- animation is restarted whenever it ends (and every few seconds, in
    -- case the client does not report the end)
    D.TALK_ANIM = 60
    panel:SetScript("OnUpdate", function(_, elapsed)
        D:UpdateCues()
        D.talkClock = (D.talkClock or 0) + elapsed
        if D.talkClock >= 2.5 then
            D.talkClock = 0
            pcall(D.model.SetAnimation, D.model, D.TALK_ANIM)
        end
    end)

    -- the name and the line, on a layer over the border copy (which would
    -- otherwise cover the top of the name)
    local words = CreateFrame("Frame", nil, panel)
    words:SetAllPoints(panel)
    if words.SetFrameLevel then words:SetFrameLevel(base + 4) end
    panel.words = words
    panel.name = words:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.name:SetPoint("TOPLEFT", panel, "TOPLEFT", 146, -30)
    panel.name:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    panel.text = words:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.text:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -8)
    panel.text:SetWidth(260)
    panel.text:SetJustifyH("LEFT")
    panel.text:SetJustifyV("TOP")

    local nextBtn = CreateFrame("Button", nil, panel)
    nextBtn:SetSize(110, 26)
    nextBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 26)
    nextBtn.skin = ART:NewPlate(nextBtn, "BACKGROUND", 26)
    nextBtn.text = nextBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nextBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    nextBtn.text:SetTextColor(1, 0.86, 0.35)
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
    -- the buttons stay above the border layer
    if nextBtn.SetFrameLevel then nextBtn:SetFrameLevel(base + 4); skip:SetFrameLevel(base + 4) end
end

-- Plays a list of conversations, then calls done().
function D:Play(list, done)
    if not self.panel or #list == 0 then
        if done then done() end
        return false
    end
    self.queue = {}
    for _, sc in ipairs(list) do
        -- a tutorial's gift comes with it, once per player: the gifts are the
        -- ones written in this file, kept apart, and the vault remembers them
        -- a gift is handed over on the line that says so ("Here's one of
        -- each"); skipped before then, it is handed over as the talk closes
        if GIFTS[sc.key] then
            self.pendingGifts = self.pendingGifts or {}
            self.pendingGifts[sc.key] = true
        end
        db()[sc.key] = true
        if sc.gift and GP.UI and GP.UI.UpdateItemSlots then pcall(GP.UI.UpdateItemSlots, GP.UI) end
        for n, line in ipairs(sc.lines) do
            local who, clip = line[1], sc.key .. "_" .. n
            if who == "host" then
                who = GP:Host().id
                clip = clip .. "_" .. who
            end
            self.queue[#self.queue + 1] = { who, line[2], clip = clip, highlight = line.highlight, cues = line.cues,
                giftKey = line.givesGift and sc.key or nil }
        end
    end
    self.done = done
    self.index = 0
    self.panel:Show()
    self:Advance()
    return true
end

-- Highlights: a line may light up buttons in the left column while it is
-- spoken (`highlight`, a list of item ids), and may move the light as each
-- name is said (`cues`: { word, item, ... }, timed from where the word sits
-- in the line at an even speaking pace).
-- characters a second each voice speaks at (measured from the recordings)
D.SPEAK_CPS = { tink = 15.2, mekka = 14.6, razzle = 17.4, bink = 16.9 }
D.SPEAK_CPS_DEFAULT = 15.5
function D:SetHighlight(items)
    if GP.UI and GP.UI.HighlightItems then GP.UI:HighlightItems(items) end
end

function D:StartCues(line)
    self.cueLine = nil
    self:SetHighlight(line.highlight)
    if not line.cues then return end
    local list = {}
    for _, c in ipairs(line.cues) do
        local at = line[2]:find(c[1], 1, true)
        if at then
            local items = {}
            for i = 2, #c do items[#items + 1] = c[i] end
            local cps = self.SPEAK_CPS[line[1]] or self.SPEAK_CPS_DEFAULT
            list[#list + 1] = { t = (at - 1) / cps, items = items }
        end
    end
    self.cueLine = { start = GetTime(), list = list, next = 1 }
end

function D:UpdateCues()
    local c = self.cueLine
    if not c then return end
    local e = GetTime() - c.start
    while c.list[c.next] and e >= c.list[c.next].t do
        self:SetHighlight(c.list[c.next].items)
        c.next = c.next + 1
    end
    if not c.list[c.next] then self.cueLine = nil end
end

-- Hands over a talk's gift (once: the vault remembers it).
function D:GiveGift(key)
    if not (self.pendingGifts and self.pendingGifts[key]) then return end
    self.pendingGifts[key] = nil
    if ns.Secure and ns.Secure.Gift(key, GIFTS[key]) then
        if GP.UI and GP.UI.UpdateCounters and GP.UI.state then pcall(GP.UI.UpdateCounters, GP.UI) end
        if GP.UI and GP.UI.UpdateItemSlots then pcall(GP.UI.UpdateItemSlots, GP.UI) end
        GP:PlaySfx("free_ball.ogg")
    end
end

function D:Show(line)
    if line.giftKey then self:GiveGift(line.giftKey) end
    self:StartCues(line)
    local sp = self.SPEAKERS[line[1]] or self.SPEAKERS.tink
    self.panel.name:SetText("|cffffd700" .. sp.name .. "|r")
    self.panel.text:SetText(line[2])
    if self.speaker ~= line[1] then
        self.speaker = line[1]
        self:ShowSpeaker(sp, line[1])
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

-- The speaker's model. The old one is cleared first, so the box never
-- shows the last speaker while the new model loads; a creature the client
-- has not cached yet loads a moment later, so the call is repeated until
-- the model is there (or the speaker changes).
function D:ShowSpeaker(sp, key)
    -- a tinted speaker goes in the tinted frame, lit in its colour
    if self.tintModel then
        local want = sp.tint and self.tintModel or self.plainModel
        local other = sp.tint and self.plainModel or self.tintModel
        other:Hide()
        if other.ClearModel then pcall(other.ClearModel, other) end
        want:Show()
        self.model = want
        if sp.tint then self:TintModel(want, sp.tint, sp.tintPower) end
    end
    local m = self.model
    self.speakerKey = key
    if m.ClearModel then pcall(m.ClearModel, m) end
    self.loadToken = (self.loadToken or 0) + 1
    local token = self.loadToken
    local function try(left)
        if token ~= self.loadToken then return end
        pcall(m.SetCreature, m, sp.npc)
        self:PoseSpeaker()
        if m.SetAnimation then pcall(m.SetAnimation, m, self.TALK_ANIM or 60) end
        local has = true
        if m.GetModelFileID then
            local ok, id = pcall(m.GetModelFileID, m)
            has = ok and id ~= nil
        end
        if not has and left > 0 and C_Timer and C_Timer.After then
            C_Timer.After(0.25, function() try(left - 1) end)
        end
    end
    try(12)
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
    -- a talk skipped before its gift line still hands the gift over
    for key in pairs(self.pendingGifts or {}) do self:GiveGift(key) end
    self.cueLine = nil
    self:SetHighlight(nil)
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
