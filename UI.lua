--[[
    Gnomish Pachinko - UI.lua
    The game window: the field (pegs, bricks, eggs, gems, the boss, the
    ball, bucket, Fever bins, aim guide, effects), the side panel, the
    level select and the out-of-plays panel. Reads the mouse for aiming,
    launches on click, pumps the engine from OnUpdate.
]]

local GP = GnomishPachinko
local E = GP.Engine
local L = GP.Levels
local ART = GP.Art
GP.UI = GP.UI or {}
local UI = GP.UI

-- Every picture comes from Art.lua's slots (ART:Set); WHITE is the one
-- plain fill left, for bars and the field's border.
local WHITE = ART.WHITE

-- The window, after the mockup: the logo centred at the top with the host's
-- box under it straddling the board's top edge; a column left of the board
-- for the special-ball buttons; a column right of it with the info block at
-- the top and the level and plays buttons at the bottom.
local EDGE, LEFT_W, GAP, SIDE_W, TOP_H = 84, 110, 16, 240, 270   -- EDGE: content keeps this far from the window's edge, past the riveted band and the brass corners
local PAD = EDGE
local PORTRAIT = 2 * (E.LAUNCH_R - 12)      -- the host's box: the launcher slides round its rim
local BARREL_W, BARREL_L = 38, 76           -- the bore is half the barrel's width: room for the ball
local FANFARE_SECS = 8.0     -- length of Sounds/fever_music.ogg; it loops while Fever lasts and stops when the last ball lands
local FX_POOL = 48           -- sparkle, confetti and glow textures in flight at once
local TRAIL_LEN = 14         -- segments of the ball's ribbon
local FLASH_SECS = 0.12      -- the muzzle flash
local SPLASH_SECS = 0.4      -- the bucket's catch splash (four frames)

-- Glow and popup colours per piece kind (the pieces themselves are full-colour art).
local COLORS = {
    blue   = { base = { 0.30, 0.58, 1.00 }, lit = { 0.78, 0.92, 1.00 }, glow = { 0.55, 0.80, 1.00 } },
    orange = { base = { 1.00, 0.50, 0.08 }, lit = { 1.00, 0.90, 0.50 }, glow = { 1.00, 0.70, 0.25 } },
    green  = { base = { 0.22, 0.88, 0.32 }, lit = { 0.78, 1.00, 0.78 }, glow = { 0.50, 1.00, 0.55 } },
    purple = { base = { 0.75, 0.35, 1.00 }, lit = { 0.95, 0.80, 1.00 }, glow = { 0.85, 0.55, 1.00 } },
    egg    = { base = { 0.98, 0.93, 0.80 }, lit = { 1.00, 1.00, 0.90 }, glow = { 1.00, 0.95, 0.60 } },
    gem    = { base = { 0.35, 0.95, 1.00 }, lit = { 0.85, 1.00, 1.00 }, glow = { 0.60, 1.00, 1.00 } },
    boss   = { base = { 1.00, 1.00, 1.00 }, lit = { 1.00, 1.00, 1.00 }, glow = { 1.00, 0.60, 0.60 } },
    key    = { base = { 1.00, 0.85, 0.30 }, lit = { 1.00, 1.00, 0.80 }, glow = { 1.00, 0.95, 0.60 } },
    cage   = { base = { 0.85, 0.68, 0.25 }, lit = { 0.85, 0.68, 0.25 }, glow = { 1.00, 0.90, 0.50 } },
    silver = { base = { 0.72, 0.78, 0.88 }, lit = { 0.72, 0.78, 0.88 }, glow = { 0.9, 0.95, 1.0 } },
    silverkey = { base = { 0.80, 0.88, 1.00 }, lit = { 1, 1, 1 }, glow = { 0.9, 0.95, 1.0 } },
    block  = { base = { 0.42, 0.42, 0.48 }, lit = { 0.42, 0.42, 0.48 }, glow = { 0.42, 0.42, 0.48 } },
    bumper = { base = { 1.00, 0.35, 0.60 }, lit = { 1.00, 0.35, 0.60 }, glow = { 1.00, 0.70, 0.85 } },
}
local RIM = { 0.78, 0.80, 0.86 }
local RIM_HEAVY = { 1.00, 0.84, 0.35 }
-- the peg colour a kind is painted in (the per-colour art set)
local COLOR_OF = { blue = "blue", orange = "orange", green = "green", purple = "purple" }

local function fmtBig(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function powerName(id)
    for _, p in ipairs(E.POWERS) do if p.id == id then return p.name, p.blurb end end
    return id or "", ""
end

-- Buttons wear a skin (button_green / orange / grey, pressed variants);
-- the old colour the caller asks for picks the skin. A node skin
-- (map_node...) is one stretched picture instead.
local function hoverButton(btn, on)
    if not btn.skin then return end
    if on then ART:TintSkin(btn.skin, 1, 0.95, 0.75, 1) else ART:TintSkin(btn.skin, 1, 1, 1, btn.enabledAlpha or 1) end
end

local function styleButton(btn, enabled, r, g, b)
    btn.skinColor = btn.nodeSkin or ("button_" .. ART:ButtonSkin(r, g, b))
    if enabled then
        btn.enabledAlpha = 1
        ART:SetSkin(btn.skin, btn.skinColor)
        ART:TintSkin(btn.skin, 1, 1, 1, 1)
        btn:Enable()
    else
        btn.enabledAlpha = 0.55
        ART:SetSkin(btn.skin, btn.nodeSkin or "button_grey")
        ART:TintSkin(btn.skin, 0.8, 0.8, 0.8, 0.55)
        btn:Disable()
    end
end

local function makeButton(parent, w, h, text, nodeSkin)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    btn.nodeSkin = nodeSkin
    btn.skin = ART:NewSkin(btn, nodeSkin or "button_grey", "BACKGROUND", 0)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)
    btn:SetScript("OnEnter", function(self) if self:IsEnabled() then hoverButton(self, true) end end)
    btn:SetScript("OnLeave", function(self) if self:IsEnabled() then hoverButton(self, false) end end)
    btn:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() and not self.nodeSkin and ART.SLOTS[self.skinColor .. "_down"] then ART:SetSkin(self.skin, self.skinColor .. "_down") end
    end)
    btn:SetScript("OnMouseUp", function(self)
        if self:IsEnabled() and not self.nodeSkin then ART:SetSkin(self.skin, self.skinColor or "button_grey") end
    end)
    return btn
end

-- An icon on the left of a button, with the text pushed right of it.
local function buttonIcon(btn, slot, size)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint("LEFT", btn, "LEFT", 6, 0)
    ART:Set(icon, slot)
    btn.icon = icon
    btn.text:ClearAllPoints()
    btn.text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    btn.text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    return icon
end

local function makeStars(parent, size, gap, layer)
    local stars = {}
    for i = 1, 3 do
        local s = parent:CreateTexture(nil, layer or "OVERLAY")
        s:SetSize(size, size)
        ART:Set(s, "star", 1, 0.85, 0.2)
        stars[i] = s
    end
    return stars
end

-- The picture a piece wears right now: by kind, colour and state
-- ("", "_lit" or "_gone").
local function pieceSlot(p, state)
    local k = p.kind
    if k == "boss" then return ART:Boss(p.ability) end
    if k == "egg" then
        if state ~= "" then return "egg_hatched" end
        return ((p.hp or 1) < (p.maxhp or 1)) and "egg_cracked" or "egg"
    end
    if k == "gem" then return "gem" end
    if k == "key" then return p.silver and "key_silver" or "key_gold" end
    if k == "bumper" then return "bumper" end
    if k == "block" then
        if p.lock then return p.silver and "cage_silver" or "cage_gold" end
        return (p.shape == "brick") and "rail" or "block"
    end
    local color = COLOR_OF[k] or "blue"
    if p.shape == "brick" then return ART:Brick(color, state) end
    return ART:Peg(color, state)
end

-- The ball's picture: fire, rainbow, spooky, electric, winged in Fever.
local function ballSlot(ball, st, now, electricUntil)
    if ball.fire or ball.item == "ring" then return "ball_fire" end
    if ball.item == "rainbow" then return "ball_rainbow" end
    if (ball.spooky or 0) > 0 then return "ball_spooky" end
    if electricUntil and now < electricUntil then return "ball_electric" end
    return "ball"
end

local function setStars(stars, earned, bright)
    for i, s in ipairs(stars) do
        if i <= (earned or 0) then s:SetVertexColor(1, 0.85, 0.2, bright or 1)
        else s:SetVertexColor(0.3, 0.3, 0.38, 0.8) end
    end
end

-- The level's objective as a sentence, with the counts filled in.
function UI:ObjectiveText(st)
    if not st then return "" end
    local o = st.objective
    if o == "eggs" then return ("Hatch all %d eggs (two hits each). An egg that falls off the board is the level lost"):format(st.goalTotal) end
    if o == "gems" then return ("Knock all %d gems loose and drop them off the bottom"):format(st.goalTotal) end
    if o == "mixed_eggs" or o == "mixed_gems" then
        local oranges, specials = 0, 0
        for _, p in ipairs(st.pegs) do
            if p.goal then if p.kind == "orange" then oranges = oranges + 1 else specials = specials + 1 end end
        end
        if o == "mixed_eggs" then return ("Light all %d orange pegs and hatch all %d eggs"):format(oranges, specials) end
        return ("Light all %d orange pegs and drop all %d gems"):format(oranges, specials)
    end
    if o == "longshots" then return ("Make %d Long Shots: two orange pegs far apart in one shot"):format(st.goalTotal) end
    local text
    if o == "boss" and st.boss then text = ("Beat the %s (%d health)"):format(st.boss.bossName or "boss", st.boss.maxhp)
    elseif o == "duel" and st.duel and st.duel.stage == 2 then text = ("Duel with %s: five balls each, turn and turn about, highest score wins. A shot that lights no orange costs a quarter of your score"):format(st.duel.name)
    elseif o == "duel" and st.duel then text = ("Stage 1: light all %d orange pegs. Then a duel with %s"):format(st.goalTotal, st.duel.name)
    else text = ("Light all %d orange pegs"):format(st.goalTotal) end
    if st.noBucket then text = text .. ". No bucket on this level" end
    return text
end

local GOAL_LABEL = { classic = "Orange pegs left", eggs = "Eggs left", gems = "Gems to drop", boss = "Boss health", duel = "Orange pegs left", longshots = "Long Shots left",
    mixed_eggs = "Goals left", mixed_gems = "Goals left" }

-- First-encounter tips, shown once each on the level card, in Tinkmaster's voice.
local TIPS = {
    { key = "start",     when = function(st) return st.level == 1 end, text = "Tinkmaster: \"Point with the mouse, click to shoot. Light every orange peg and the board is yours!\"" },
    { key = "bricks",    when = function(st) for _, p in ipairs(st.pegs) do if p.shape == "brick" then return true end end end, text = "Tinkmaster: \"Bricks are pegs too! Catch the inside of a curve and the ball rides it, lighting the lot.\"" },
    { key = "boss",      when = function(st) return st.objective == "boss" end, text = "Tinkmaster: \"A boss! It slides along the bottom under the pegs. Get the ball down there and keep hitting it.\"" },
    { key = "eggs",      when = function(st) return st.objective == "eggs" or st.objective == "mixed_eggs" end, text = "Tinkmaster: \"Eggs! Two hits to hatch. Handle with care: knock away the nest under one and it falls. Catch it in the bucket, or lose the level.\"" },
    { key = "gems",      when = function(st) return st.objective == "gems" or st.objective == "mixed_gems" end, text = "Tinkmaster: \"Gems! Knock them loose and drop them off the bottom. One in the bucket is a Bucket Drop bonus.\"" },
    { key = "duel",      when = function(st) return st.objective == "duel" end, text = "Tinkmaster: \"My brother Cogwhistle again. Clear the board, then it's a duel: five balls each, and hit an orange every shot or he docks your score.\"" },
    { key = "longshots", when = function(st) return st.objective == "longshots" end, text = "Tinkmaster: \"Long Shots! Light two orange pegs far apart in one shot. Bounce it off the far wall and watch.\"" },
    { key = "tough",     when = function(st) for _, p in ipairs(st.pegs) do if (p.maxhp or 1) > 1 and p.kind ~= "egg" and p.kind ~= "boss" then return true end end end, text = "Tinkmaster: \"Steel-rimmed pieces take two hits, gold-rimmed three. They crack first.\"" },
    { key = "nobucket",  when = function(st) return st.noBucket end, text = "Tinkmaster: \"No bucket on this one. The only free balls are the score marks, so make every ball count.\"" },
    { key = "keys",      when = function(st) for _, p in ipairs(st.pegs) do if p.kind == "key" then return true end end end, text = "Tinkmaster: \"A key! Light it and its cage falls away. Sometimes the key is behind another lock.\"" },
    { key = "items",     when = function(st) return st.level == 2 end, text = "Tinkmaster: \"Two slots at the bottom-left: Ring of Fire and Rainbow Ball. Click one to arm it for your next shot. You earn more by clearing levels.\"" },
    { key = "gimmick",   when = function(st) return st.gimmick ~= nil end, text = "Tinkmaster: \"Moving parts! Time your shot with the pieces, or use them to bank the ball where you want it.\"" },
}


function UI:Initialize()
    if self.frame then return end
    self:CreateFrame()
end

function UI:CreateFrame()
    local FW, FH = E.FIELD_W, E.FIELD_H
    local FRAME_W = EDGE + LEFT_W + GAP + FW + GAP + SIDE_W + EDGE
    local FRAME_H = TOP_H + FH + EDGE

    local frame = CreateFrame("Frame", "GnomishPachinkoFrame", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame.skin = ART:NewSkin(frame, "frame_bg", "BACKGROUND", -8)
    frame:Hide()
    self.frame = frame
    if UISpecialFrames then tinsert(UISpecialFrames, "GnomishPachinkoFrame") end

    -- the logo, centred over the board
    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetSize(560, 140)
    logo:SetPoint("TOP", frame, "TOP", (LEFT_W + GAP - GAP - SIDE_W) / 2, -6)
    ART:Set(logo, "logo")
    self.logo = logo

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -12, -12)
    closeBtn:SetScript("OnClick", function() UI:Hide() end)

    -- ===== field =====
    -- The view clips the field so it can zoom in on the last goal piece.
    local view = CreateFrame("Frame", nil, frame)
    view:SetSize(FW, FH)
    view:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE + LEFT_W + GAP, -TOP_H)
    if view.SetClipsChildren then pcall(view.SetClipsChildren, view, true) end
    self.view = view
    local field = CreateFrame("Frame", nil, view, "BackdropTemplate")
    field:SetSize(FW, FH)
    field:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
    self.zoomScale = 1
    field:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    field:SetBackdropColor(0.03, 0.04, 0.14, 1)
    field:SetBackdropBorderColor(0.45, 0.35, 0.70, 1)
    -- the world's backdrop behind the pegs (StartLevel picks it)
    local fieldBg = field:CreateTexture(nil, "BACKGROUND", nil, 0)
    fieldBg:SetAllPoints(field)
    ART:Set(fieldBg, "field_bg_1")
    self.fieldBg = fieldBg
    field:EnableMouse(true)
    field:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then UI:OnFieldClick() end
    end)
    -- the keyboard is ours only while the mouse is over the field
    field:SetScript("OnEnter", function() pcall(frame.EnableKeyboard, frame, true) end)
    field:SetScript("OnLeave", function() pcall(frame.EnableKeyboard, frame, false) end)
    frame:SetScript("OnKeyDown", function(f, key) UI:OnKey(key) end)
    pcall(frame.EnableKeyboard, frame, false)
    self.field = field

    for _ = 1, 48 do
        local s = field:CreateTexture(nil, "BACKGROUND", nil, 1)
        local size = 1 + math.random() * 2
        s:SetSize(size, size)
        s:SetTexture(WHITE)
        s:SetVertexColor(0.8, 0.85, 1, 0.15 + math.random() * 0.35)
        s:SetPoint("CENTER", field, "TOPLEFT", 6 + math.random() * (FW - 12), -(6 + math.random() * (FH - 12)))
    end

    -- the barrel and its flash are made with the host's box below: they ride its rim

    local ghost = field:CreateTexture(nil, "ARTWORK", nil, 2)
    ART:SetPiece(ghost, "ball", E.BALL_R * 2 + 2)
    ghost:SetAlpha(0.55)
    ghost:Hide()
    self.guideBall = ghost
    self.guideDots = {}
    for i = 1, 64 do
        local d = field:CreateTexture(nil, "ARTWORK", nil, 1)
        d:SetSize(6, 6)
        ART:Set(d, "dot")
        d:Hide()
        self.guideDots[i] = d
    end

    -- lightning bolts
    self.boltDots = {}
    for i = 1, 40 do
        local d = field:CreateTexture(nil, "OVERLAY", nil, 3)
        d:SetSize(8, 8)
        ART:Set(d, "dot", 0.8, 0.9, 1)
        d:Hide()
        self.boltDots[i] = d
    end

    -- the Space Blast burst
    local blast = field:CreateTexture(nil, "OVERLAY", nil, 4)
    ART:Set(blast, "blast", 1, 0.75, 0.3)
    blast:Hide()
    self.blastTex = blast
    local blastRing = field:CreateTexture(nil, "OVERLAY", nil, 4)
    ART:Set(blastRing, "ring", 1, 0.95, 0.7)
    blastRing:Hide()
    self.blastRing = blastRing

    -- the Pyramid bar
    local pyr = field:CreateTexture(nil, "ARTWORK", nil, 3)
    ART:Set(pyr, "pyramid")
    pyr:SetSize(E.PYRAMID_W + 20, 40)
    pyr:SetPoint("CENTER", field, "TOPLEFT", FW / 2, -(E.PYRAMID_Y + 6))
    pyr:Hide()
    self.pyramidTex = pyr

    self.pegTex = {}

    self.ballTex = {}
    for i = 1, 8 do
        local b = field:CreateTexture(nil, "OVERLAY", nil, 2)
        ART:SetPiece(b, "ball", E.BALL_R * 2 + 2)
        b:Hide()
        self.ballTex[i] = b
    end

    -- the ball's ribbon in Fever and with the Rainbow Ball
    self.trail = {}
    for i = 1, TRAIL_LEN do
        local t = field:CreateTexture(nil, "OVERLAY", nil, 1)
        ART:Set(t, "trail")
        t:Hide()
        self.trail[i] = t
    end
    self.trailPts = {}

    -- sparkles, confetti, fireworks and glows
    self.fx = {}
    for i = 1, FX_POOL do
        local t = field:CreateTexture(nil, "OVERLAY", nil, 7)
        t:Hide()
        self.fx[i] = t
    end
    -- the soft glow on the last goal piece while time slows
    local lastGlow = field:CreateTexture(nil, "ARTWORK", nil, 0)
    ART:Set(lastGlow, "glow_soft", 1, 0.95, 0.7)
    lastGlow:Hide()
    self.lastGlow = lastGlow

    -- balls left: a column of balls down the left column, off the board
    self.ballStrip = {}
    for i = 1, 10 do
        local b = frame:CreateTexture(nil, "OVERLAY", nil, 2)
        b:SetSize(26, 26)
        ART:Set(b, "ball_small")
        b:SetPoint("TOP", frame, "TOPLEFT", EDGE + LEFT_W / 2, -(TOP_H + 4 + (i - 1) * 30))
        b:Hide()
        self.ballStrip[i] = b
    end
    self.ballStripMore = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.ballStripMore:SetPoint("TOP", self.ballStrip[10], "BOTTOM", 0, -4)
    self.ballStripMore:SetText("")

    -- the boss's health bar and name
    local bossBg = field:CreateTexture(nil, "OVERLAY", nil, 5)
    bossBg:SetSize(72, 7)
    bossBg:SetTexture(WHITE)
    bossBg:SetVertexColor(0.1, 0.1, 0.12, 0.9)
    bossBg:Hide()
    self.bossBg = bossBg
    local bossFill = field:CreateTexture(nil, "OVERLAY", nil, 6)
    bossFill:SetSize(70, 5)
    bossFill:SetTexture(WHITE)
    bossFill:SetVertexColor(0.9, 0.2, 0.2, 1)
    bossFill:Hide()
    self.bossFill = bossFill
    local bossName = field:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bossName:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    bossName:Hide()
    self.bossName = bossName

    local bucket = field:CreateTexture(nil, "OVERLAY", nil, 1)
    bucket:SetSize(E.BUCKET_W + 16, E.BUCKET_W + 16)
    ART:Set(bucket, "bucket")
    self.bucket = bucket
    -- the catch: four splash frames over the bucket
    local splash = field:CreateTexture(nil, "OVERLAY", nil, 3)
    splash:SetSize(E.BUCKET_W + 16, E.BUCKET_W + 16)
    ART:Set(splash, "bucket_splash1")
    splash:Hide()
    self.splashTex = splash

    -- the balloons between the Fever cups (the engine adds them as bumpers);
    -- each squashes for a moment when a ball strikes it
    self.postTex = {}
    for i = 0, #E.FEVER_BINS do
        local t = field:CreateTexture(nil, "OVERLAY", nil, 2)
        ART:SetPiece(t, "fever_balloon", E.FEVER_BALLOON_R * 2)
        t.x, t.y = i * FW / #E.FEVER_BINS, E.FEVER_POST_Y
        t:SetPoint("CENTER", field, "TOPLEFT", t.x, -t.y)
        t:Hide()
        self.postTex[#self.postTex + 1] = t
    end
    self.bins = {}
    local binW = FW / #E.FEVER_BINS
    for i, pts in ipairs(E.FEVER_BINS) do
        local bin = CreateFrame("Frame", nil, field)
        bin:SetSize(binW - 2 * E.FEVER_BALLOON_R, 40)
        bin:SetPoint("BOTTOMLEFT", field, "BOTTOMLEFT", (i - 1) * binW + E.FEVER_BALLOON_R, 0)
        bin.letter = (E.FEVER_LETTERS[i] or "g"):lower()
        bin.tube = bin:CreateTexture(nil, "BACKGROUND")
        bin.tube:SetAllPoints(bin)
        ART:Set(bin.tube, "fever_tube_" .. bin.letter)
        -- the points it pays, under the board
        bin.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bin.label:SetPoint("TOP", field, "BOTTOMLEFT", (i - 0.5) * binW, -4)
        bin.label:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        bin.label:SetText("|cffffd700" .. fmtBig(pts) .. "|r")
        bin.label:Hide()
        bin:SetScript("OnShow", function(self) self.label:Show() end)
        bin:SetScript("OnHide", function(self) self.label:Hide() end)
        bin:Hide()
        self.bins[i] = bin
    end

    -- the big callouts: a ribbon behind the text, or a drawn callout
    local ribbon = field:CreateTexture(nil, "OVERLAY", nil, 0)
    ribbon:SetSize(FW - 20, 52)
    ribbon:SetPoint("CENTER", field, "CENTER", 0, 40)
    ART:Set(ribbon, "banner")
    ribbon:Hide()
    self.bannerRibbon = ribbon
    local callout = field:CreateTexture(nil, "OVERLAY", nil, 1)
    callout:SetSize(FW - 40, (FW - 40) / 4)
    callout:SetPoint("CENTER", field, "CENTER", 0, 40)
    ART:Set(callout, "callout_fever")
    callout:Hide()
    self.calloutTex = callout
    local banner = field:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    banner:SetPoint("CENTER", field, "CENTER", 0, 40)
    banner:SetFont("Fonts\\FRIZQT__.TTF", 26, "OUTLINE")
    self.banner = banner
    local sub = field:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sub:SetPoint("TOP", banner, "BOTTOM", 0, -6)
    sub:SetWidth(FW - 60)
    sub:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    -- a dark plate behind the line under the ribbon, so it reads on any backdrop
    local subBg = field:CreateTexture(nil, "OVERLAY", nil, 0)
    subBg:SetPoint("TOPLEFT", sub, "TOPLEFT", -12, 6)
    subBg:SetPoint("BOTTOMRIGHT", sub, "BOTTOMRIGHT", 12, -6)
    subBg:SetTexture(WHITE)
    subBg:SetVertexColor(0, 0, 0, 0.7)
    subBg:Hide()
    self.bannerSubBg = subBg
    self.bannerSub = sub
    -- power-up slots: armed for the next shot
    self.itemSlots = {}
    for i, id in ipairs({ "ring", "rainbow", "suction" }) do
        local b = makeButton(frame, LEFT_W, 30, "")
        b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", EDGE, EDGE + (i - 1) * 36)
        b.item = id
        buttonIcon(b, ART:Item(id), 20)
        b:SetScript("OnClick", function(self) UI:ToggleItem(self.item) end)
        b:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(E.ITEMS[self.item].name)
            GameTooltip:AddLine(E.ITEMS[self.item].blurb, 0.8, 0.8, 0.9, true)
            GameTooltip:AddLine("Earned by clearing levels. Click to arm for the next shot.", 0.6, 0.6, 0.7, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            if GameTooltip then GameTooltip:Hide() end
            if self:IsEnabled() then hoverButton(self, false) end
        end)
        self.itemSlots[i] = b
    end

    -- the duel's two score boxes, in the left column (the balls column gives way to them)
    self.duelYou = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.duelYou:SetPoint("TOP", frame, "TOPLEFT", EDGE + LEFT_W / 2, -(TOP_H + 4))
    self.duelYou:SetWidth(LEFT_W)
    self.duelYou:SetJustifyH("CENTER")
    self.duelYou:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    self.duelYou:Hide()
    self.duelRival = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.duelRival:SetPoint("TOP", self.duelYou, "BOTTOM", 0, -18)
    self.duelRival:SetWidth(LEFT_W)
    self.duelRival:SetJustifyH("CENTER")
    self.duelRival:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    self.duelRival:Hide()

    local shot = field:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    shot:SetPoint("BOTTOM", field, "BOTTOM", 0, 40)
    shot:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    shot:SetTextColor(1, 0.95, 0.7)
    self.shotText = shot
    self.bannerStars = makeStars(field, 28, 4)
    for i, s in ipairs(self.bannerStars) do
        s:SetPoint("TOP", sub, "BOTTOM", (i - 2) * 34, -8)
        s:Hide()
    end

    self.popups = {}
    for i = 1, 12 do
        local p = field:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        p:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        p:Hide()
        self.popups[i] = p
    end

    -- ===== side panel =====
    local side = CreateFrame("Frame", nil, frame)
    side:SetSize(SIDE_W, FH)
    side:SetPoint("TOPLEFT", view, "TOPRIGHT", GAP, 0)
    self.side = side

    local function label(text, y, template)
        local fs = side:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", side, "TOPLEFT", 6, y)
        fs:SetText(text)
        return fs
    end
    local function value(y, template)
        local fs = side:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
        fs:SetPoint("TOPRIGHT", side, "TOPRIGHT", -6, y)
        fs:SetJustifyH("RIGHT")
        return fs
    end
    local function divider(y)
        local div = side:CreateTexture(nil, "ARTWORK")
        div:SetSize(SIDE_W, 1)
        div:SetPoint("TOPLEFT", side, "TOPLEFT", 0, y)
        div:SetTexture(WHITE)
        div:SetVertexColor(0.5, 0.4, 0.7, 0.6)
    end
    -- an inset plate behind a readout row (its pieces live on the side
    -- panel itself, under the text)
    local function plate(y, h)
        local anchor = CreateFrame("Frame", nil, side)
        anchor:SetSize(SIDE_W + 8, h)
        anchor:SetPoint("TOPLEFT", side, "TOPLEFT", -4, y)
        return ART:NewSkin(side, "plate", "BACKGROUND", 0, anchor)
    end
    local function icon(x, y, size, slot)
        local t = side:CreateTexture(nil, "ARTWORK")
        t:SetSize(size, size)
        t:SetPoint("TOPLEFT", side, "TOPLEFT", x, y)
        ART:Set(t, slot)
        return t
    end

    self.levelText = label("", 0, "GameFontNormalLarge")
    self.levelText:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    self.levelText:SetTextColor(1, 0.85, 0.2)
    self.chapterText = label("", -26, "GameFontNormal")
    self.chapterText:SetWidth(SIDE_W)
    self.chapterText:SetJustifyH("LEFT")
    self.layoutText = label("", -42)
    self.layoutText:SetTextColor(0.6, 0.55, 0.75)
    divider(-60)

    label("|cffffd700Objective|r", -68, "GameFontNormal")
    self.objectiveText = label("", -84)
    self.objectiveText:SetWidth(SIDE_W)
    self.objectiveText:SetJustifyH("LEFT")
    self.objectiveText:SetJustifyV("TOP")
    self.objectiveText:SetHeight(26)
    self.objectiveText:SetTextColor(0.9, 0.9, 1)

    self.powerIcon = icon(0, -110, 18, "power_multiball")
    local powerLabel = label("|cff88ff88Power|r", -112, "GameFontNormal")
    powerLabel:ClearAllPoints()
    powerLabel:SetPoint("TOPLEFT", side, "TOPLEFT", 22, -112)
    self.powerText = value(-112, "GameFontHighlight")
    self.powerBlurb = label("", -128)
    self.powerBlurb:SetWidth(SIDE_W)
    self.powerBlurb:SetJustifyH("LEFT")
    self.powerBlurb:SetJustifyV("TOP")
    self.powerBlurb:SetHeight(26)
    self.powerBlurb:SetTextColor(0.7, 0.7, 0.8)
    self.powerStatus = label("", -154)
    self.powerStatus:SetTextColor(0.6, 1, 0.6)

    label("Balls", -172, "GameFontNormal")
    self.ballsText = value(-172, "GameFontHighlightLarge")
    self.goalIcon = icon(0, -194, 18, "goal_orange")
    self.goalLabel = label("Orange pegs left", -196, "GameFontNormal")
    self.goalLabel:ClearAllPoints()
    self.goalLabel:SetPoint("TOPLEFT", side, "TOPLEFT", 22, -196)
    self.goalText = value(-196, "GameFontHighlightLarge")
    label("Score", -220, "GameFontNormal")
    self.scoreText = value(-220, "GameFontHighlight")
    label("Multiplier", -238)
    self.multText = value(-238, "GameFontHighlightSmall")
    label("Combo (this shot / best)", -274)
    self.comboText = value(-274, "GameFontHighlightSmall")
    label("Best on this level", -290)
    self.bestText = value(-290, "GameFontHighlightSmall")
    label("Next free ball at", -306)
    self.freeBallText = value(-306, "GameFontHighlightSmall")
    local function bar(y, r, g, b)
        local f = CreateFrame("StatusBar", nil, side)
        f:SetSize(SIDE_W, 5)
        f:SetPoint("TOPLEFT", side, "TOPLEFT", 0, y)
        f:SetStatusBarTexture(WHITE)
        f:SetStatusBarColor(r, g, b, 0.9)
        f:SetMinMaxValues(0, 1)
        f:SetValue(0)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(WHITE)
        bg:SetVertexColor(0.1, 0.1, 0.14, 0.9)
        return f
    end
    self.freeBallBar = bar(-320, 0.4, 0.7, 1)
    -- the multiplier: a horizontal trough with a rainbow bar clipped by progress
    local trough = CreateFrame("Frame", nil, side)
    trough:SetSize(SIDE_W, 16)
    trough:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -254)
    local gauge = { skin = ART:NewSkin(side, "gauge", "ARTWORK", 0, trough), fill = side:CreateTexture(nil, "ARTWORK", nil, 2), w = SIDE_W - 8 }
    gauge.fill:SetPoint("LEFT", trough, "LEFT", 4, 0)
    gauge.fill:SetSize(gauge.w, 10)
    ART:Set(gauge.fill, "gauge_fill")
    function gauge:SetValue(f)
        f = math.max(0.01, math.min(1, f or 0))
        self.fill:SetTexCoord(0, f, 0, 1)
        self.fill:SetWidth(self.w * f)
    end
    gauge:SetValue(0)
    self.multBar = gauge
    label("Stars on this level", -330)
    self.sideStars = makeStars(side, 12, 2)
    for i, s in ipairs(self.sideStars) do s:SetPoint("TOPRIGHT", side, "TOPRIGHT", -(3 - i) * 14, -330) end
    self.starNeedText = label("", -346)
    self.starNeedText:SetWidth(SIDE_W)
    self.starNeedText:SetJustifyH("LEFT")
    self.starNeedText:SetTextColor(0.65, 0.65, 0.78)
    divider(-366)

    self.nextBtn = makeButton(side, SIDE_W, 32, "NEXT LEVEL")
    self.nextBtn:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 158)
    self.nextBtn:SetScript("OnClick", function() UI:NextLevel() end)
    self.retryBtn = makeButton(side, SIDE_W, 26, "Restart level")
    self.retryBtn:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 126)
    self.retryBtn:SetScript("OnClick", function() UI:StartLevel(UI.state and UI.state.level or GP:GetDB().current, true) end)
    self.levelsBtn = makeButton(side, SIDE_W, 26, "Level select")
    self.levelsBtn:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 96)
    self.levelsBtn:SetScript("OnClick", function() UI:ShowLevelSelect() end)

    self.playsText = label("", 0, "GameFontNormal")
    self.playsText:ClearAllPoints()
    self.playsText:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 60)
    self.playsText:SetWidth(SIDE_W)
    self.playsText:SetHeight(30)
    self.playsText:SetJustifyH("CENTER")
    self.playsText:SetJustifyV("TOP")
    self.buyBtn = makeButton(side, SIDE_W, 24, "Buy " .. GP.Plays.PLAYS_PER_LOT .. " plays (" .. GP.Plays:PriceText(1) .. ")")
    self.buyBtn:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 30)
    self.buyBtn:SetScript("OnClick", function() UI:BuyPlays() end)
    -- the owner's characters top up for free
    self.freeBtn = makeButton(side, SIDE_W, 24, "Owner: " .. GP.Plays.PLAYS_PER_LOT .. " free plays")
    self.freeBtn:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 0)
    self.freeBtn:SetScript("OnClick", function() UI:ClaimFreePlays() end)
    self.freeBtn:Hide()


    frame:SetScript("OnUpdate", function(_, dt) UI:OnUpdate(dt) end)
    frame:SetScript("OnShow", function() UI.lastHitSound = 0 end)

    self:CreateLevelSelect()
    self:CreatePlaysPanel()
    self:CreateCard()
    if GP.Dialog then GP.Dialog:Create(frame, view, field:GetFrameLevel() + 30) end
    -- the host's box: a round frame centred over the field's top edge, the model inside it
    local box = CreateFrame("Frame", nil, frame)
    box:SetSize(PORTRAIT, PORTRAIT)
    box:SetPoint("CENTER", view, "TOP", 0, -E.LAUNCH_CY)
    box:SetFrameLevel(field:GetFrameLevel() + 12)
    local boxBg = box:CreateTexture(nil, "BACKGROUND")
    boxBg:SetSize(PORTRAIT - 10, PORTRAIT - 10)
    boxBg:SetPoint("CENTER")
    ART:Set(boxBg, "dot", 0.03, 0.04, 0.14)   -- a dark disc behind the host
    self.portraitBox = box
    -- the host at full size, clipped at the ring's inner bottom edge so his
    -- feet never show below it (the ring's band covers the cut)
    local clip = CreateFrame("Frame", nil, box)
    local innerR = math.floor(PORTRAIT / 2 * 0.8)
    clip:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    clip:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    clip:SetHeight(PORTRAIT / 2 + innerR)
    if clip.SetClipsChildren then pcall(clip.SetClipsChildren, clip, true) end
    self.portraitClip = clip
    if GP.Mascot then GP.Mascot:Create(clip, box, PORTRAIT - 16, PORTRAIT - 16) end
    local ringFrame = CreateFrame("Frame", nil, frame)
    ringFrame:SetSize(PORTRAIT, PORTRAIT)
    ringFrame:SetPoint("CENTER", box, "CENTER", 0, 0)
    ringFrame:SetFrameLevel(box:GetFrameLevel() + 8)
    local ring = ringFrame:CreateTexture(nil, "ARTWORK")
    ring:SetAllPoints(ringFrame)
    ART:Set(ring, "portrait_frame")
    self.portraitRing = ring
    self.portraitRingFrame = ringFrame
    -- the cannon slides round the box's rim, pointing the way the ball goes
    local barrelFrame = CreateFrame("Frame", nil, frame)
    barrelFrame:SetAllPoints(field)
    barrelFrame:SetFrameLevel(box:GetFrameLevel() + 6)     -- over the host (box + 4), under the ring (box + 8)
    self.barrelFrame = barrelFrame
    local barrel = barrelFrame:CreateTexture(nil, "ARTWORK")
    barrel:SetSize(BARREL_W, BARREL_L)
    ART:Set(barrel, "launcher_barrel")
    self.barrel = barrel
    local flash = ringFrame:CreateTexture(nil, "OVERLAY", nil, 5)
    flash:SetSize(34, 34)
    ART:Set(flash, "launcher_flash", 1, 0.9, 0.6)
    flash:Hide()
    self.flashTex = flash
    self.events = {}
end

-- ---------------------------------------------------------------------
-- The card over the field: before a level (number, name, objective, star
-- marks, Play) and after it (stars earned, score, Retry / Next / Map).

function UI:CreateCard()
    local FW, FH = E.FIELD_W, E.FIELD_H
    local card = CreateFrame("Frame", nil, self.frame)
    card:SetSize(430, 430)
    card:SetPoint("CENTER", self.view, "CENTER", 0, 10)
    card:SetFrameLevel(self.field:GetFrameLevel() + 6)
    card.skin = ART:NewSkin(card, "card", "BACKGROUND", 0)
    card:EnableMouse(true)
    card:Hide()
    self.card = card
    -- a see-through sheet behind it eats clicks on the field
    local sheet = CreateFrame("Frame", nil, self.frame)
    sheet:SetSize(FW, FH)
    sheet:SetPoint("TOPLEFT", self.view, "TOPLEFT", 0, 0)
    sheet:SetFrameLevel(self.field:GetFrameLevel() + 5)
    sheet:EnableMouse(true)
    sheet:Hide()
    self.cardSheet = sheet

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.title:SetPoint("TOP", 0, -56)
    card.title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    card.title:SetWidth(340)
    card.stars = makeStars(card, 30, 4)
    for i, s in ipairs(card.stars) do s:SetPoint("TOP", card, "TOP", (i - 2) * 36, -90) end
    card.line1 = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.line1:SetPoint("TOP", 0, -132)
    card.line1:SetWidth(330)
    card.line2 = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.line2:SetPoint("TOP", card.line1, "BOTTOM", 0, -8)
    card.line2:SetWidth(330)
    card.line3 = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.line3:SetPoint("TOP", card.line2, "BOTTOM", 0, -8)
    card.line3:SetWidth(330)
    card.line3:SetTextColor(0.75, 0.75, 0.85)
    -- the master selector: any power unlocked so far
    card.powerPrev = makeButton(card, 46, 34, "<")
    card.powerPrev:SetPoint("TOP", card.line3, "BOTTOM", -150, -6)
    card.powerPrev.text:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    card.powerNext = makeButton(card, 46, 34, ">")
    card.powerNext:SetPoint("TOP", card.line3, "BOTTOM", 150, -6)
    card.powerNext.text:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    card.powerText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.powerText:SetPoint("TOP", card.line3, "BOTTOM", 0, -12)
    card.powerText:SetWidth(230)
    card.powerPrev:SetScript("OnClick", function() UI:CyclePower(-1) end)
    card.powerNext:SetScript("OnClick", function() UI:CyclePower(1) end)
    -- the Extra Green Peg boost
    card.boost = makeButton(card, 300, 26, "")
    card.boost:SetPoint("TOP", card.powerText, "BOTTOM", 0, -10)
    card.boost:SetScript("OnClick", function() UI:ToggleGreenBoost() end)
    card.main = makeButton(card, 150, 32, "PLAY")
    card.main:SetPoint("BOTTOM", 0, 92)
    card.left = makeButton(card, 110, 26, "Map")
    card.left:SetPoint("BOTTOMLEFT", 30, 32)
    card.right = makeButton(card, 110, 26, "Retry")
    card.right:SetPoint("BOTTOMRIGHT", -30, 32)
end

function UI:HideCard()
    self.card:Hide()
    self.cardSheet:Hide()
    self.cardAt = nil
end

-- Before the level: the player presses Play.
function UI:ShowStartCard()
    local st = self.state
    local card = self.card
    card.title:SetText(("|cffffd700%d. %s|r"):format(st.level, st.title or ""))
    setStars(card.stars, GP:GetDB().stars[st.level] or 0)
    card.line1:SetText(self:ObjectiveText(st))
    local s2, s3 = L:StarScores(st.level)
    card.line2:SetText(("|cffffd7002 stars|r at %s   |cffffd7003 stars|r at %s"):format(fmtBig(s2), fmtBig(s3)))
    local extra = {}
    if st.gimmick then extra[#extra + 1] = st.gimmick end
    if st.duel then extra[#extra + 1] = st.duel.blurb end
    local best = GP:GetDB().best[st.level]
    if best then extra[#extra + 1] = "Best " .. fmtBig(best) end
    self.cardTip = nil
    card.line3:SetText(table.concat(extra, "  -  "))
    card.main.text:SetText("PLAY")
    card.main:SetScript("OnClick", function() UI:PlayFromCard() end)
    styleButton(card.main, true, 0.2, 0.55, 0.25)
    card.main:Show()         -- the result card may have hidden it
    card.left.text:SetText("Map")
    card.left:SetScript("OnClick", function() UI:HideCard(); UI:ShowLevelSelect() end)
    styleButton(card.left, true, 0.35, 0.3, 0.45)
    card.right:Hide()
    card.left:ClearAllPoints()
    card.left:SetPoint("BOTTOM", card, "BOTTOM", 0, 52)       -- alone: centred
    self.greenBoost = false
    self:RefreshCardChoices()
    card.powerPrev:Show(); card.powerNext:Show(); card.powerText:Show(); card.boost:Show()
    self.cardSheet:Show()
    card:Show()
end

function UI:RefreshCardChoices()
    local st, card = self.state, self.card
    local name, blurb = powerName(st.power)
    card.powerText:SetText(("Power: |cff88ff88%s|r"):format(name))
    local many = #GP:UnlockedPowers() > 1
    styleButton(card.powerPrev, many, 0.3, 0.3, 0.45)
    styleButton(card.powerNext, many, 0.3, 0.3, 0.45)
    local n = GP:ItemCount("green")
    card.boost.text:SetText(("Extra Green Peg (%d): %s"):format(n, self.greenBoost and "|cff88ff88ON|r" or "off"))
    styleButton(card.boost, n > 0 or self.greenBoost, 0.25, 0.4, 0.25)
end

function UI:CyclePower(dir)
    local st = self.state
    local list = GP:UnlockedPowers()
    if #list < 2 then return end
    local idx = 1
    for i, id in ipairs(list) do if id == st.power then idx = i end end
    idx = ((idx - 1 + dir) % #list) + 1
    st.power = list[idx]
    GP:GetDB().lastPower = st.power
    self:RefreshCardChoices()
    self:UpdateDisplay()
end

function UI:ToggleGreenBoost()
    if not self.greenBoost and GP:ItemCount("green") <= 0 then return end
    self.greenBoost = not self.greenBoost
    self:RefreshCardChoices()
end

function UI:PlayFromCard()
    local st = self.state
    if self.cardTip then GP:GetDB().tips[self.cardTip] = true; self.cardTip = nil end
    if self.greenBoost and GP:SpendItem("green") then
        local p = E:AddGreen(st)
        if p then
            self:LayoutPegs()
            self:Popup(p.x, p.y - 16, "EXTRA GREEN", 0.6, 1, 0.6)
        end
    end
    self.greenBoost = false
    self:HideCard()
    GP:PlaySfx("start.ogg")
    self:UpdateDisplay()
end

-- After the level: stars, score, what happened, and where to go next.
function UI:ShowResultCard(result, stars)
    local st = self.state
    local card = self.card
    local cleared = result.cleared
    if result.duel then
        card.title:SetText(cleared and "|cffffd700YOU WON!|r" or ("|cffff6060" .. result.duel.name:upper() .. " WON|r"))
    else
        card.title:SetText(cleared and "|cffffd700LEVEL CLEARED!|r" or "|cffff6060OUT OF BALLS|r")
    end
    setStars(card.stars, cleared and stars or 0)
    local def = E.OBJECTIVES[result.objective] or E.OBJECTIVES.classic
    local goalLine
    if result.duel then goalLine = ("YOU %s  -  %s %s"):format(fmtBig(result.duel.you), result.duel.name, fmtBig(result.duel.rival))
    elseif result.objective == "boss" then goalLine = cleared and "Boss beaten" or "The boss survived"
    else goalLine = ("%d of %d %s"):format(result.goals, result.goalTotal, def.goalWord) end
    card.line1:SetText(("Score |cffffd700%s|r"):format(fmtBig(result.score)))
    card.line2:SetText((cleared and "|cff66ff66done|r  " or "|cffff6060missed|r  ") .. goalLine)
    local s2, s3 = L:StarScores(st.level)
    local third = ("Fever %s  -  best combo %d  -  2 stars at %s, 3 at %s"):format(
        fmtBig(result.feverTotal or 0), result.bestCombo or 0, fmtBig(s2), fmtBig(s3))
    if not cleared then third = third .. ("  -  plays left today: %d"):format(GP.Plays:Remaining()) end
    card.line3:SetText(third)
    if cleared and st.level < L.COUNT and GP:IsUnlocked(st.level + 1) then
        card.main.text:SetText("NEXT LEVEL")
        card.main:SetScript("OnClick", function() UI:HideCard(); UI:NextLevel() end)
        styleButton(card.main, true, 0.2, 0.55, 0.25)
        card.main:Show()
    elseif self.pendingFail then
        card.main.text:SetText(("PLAY ON  (+%d balls, 1 play)"):format(E.PLAY_ON_BALLS))
        card.main:SetScript("OnClick", function() UI:PlayOn() end)
        styleButton(card.main, GP.Plays:CanPlay(), 0.2, 0.55, 0.25)
        card.main:Show()
    else
        card.main:Hide()
    end
    card.left.text:SetText(self.pendingFail and "End level" or "Map")
    card.left:SetScript("OnClick", function() UI:SettlePendingFail(); UI:HideCard(); UI:ShowLevelSelect(); if not GP.Plays:CanPlay() then UI:ShowOutOfPlays() end end)
    styleButton(card.left, true, 0.35, 0.3, 0.45)
    card.right.text:SetText("Retry")
    card.right:SetScript("OnClick", function() UI:SettlePendingFail(); UI:HideCard(); UI:StartLevel(st.level, true) end)
    styleButton(card.right, GP.Plays:Remaining() >= (self.pendingFail and 2 or 1), 0.45, 0.3, 0.2)
    card.right:Show()
    card.left:ClearAllPoints()                                -- the pair, centred as a group
    card.left:SetPoint("BOTTOM", card, "BOTTOM", -66, 52)
    card.right:ClearAllPoints()
    card.right:SetPoint("BOTTOM", card, "BOTTOM", 66, 52)
    card.powerPrev:Hide(); card.powerNext:Hide(); card.boost:Hide()
    if result.rewards and #result.rewards > 0 then
        local parts = {}
        for _, r in ipairs(result.rewards) do parts[#parts + 1] = ("+%d %s"):format(r.n, E.ITEMS[r.item].name) end
        card.powerText:SetText("|cffffd700Rewards:|r " .. table.concat(parts, ", "))
        card.powerText:Show()
    else
        card.powerText:Hide()
    end
    self.cardSheet:Show()
    card:Show()
end

-- ---------------------------------------------------------------------
-- The level map (covers the field): one chapter a page, its ten levels
-- climbing a winding path from the bottom left to the boss at the top,
-- stars under every node. Prev/Next step a chapter, << and >> ten.

-- The ten nodes climb from the bottom to the boss at the top along a path
-- that winds differently in every chapter (seeded by the chapter number).
local function nodePath(chapter)
    local rng = E.NewRng((chapter or 1) * 7919 + 13)
    local freq = 0.85 + rng() * 0.5
    local phase = rng() * math.pi * 2
    local swing = E.FIELD_W / 2 - 70
    local path = {}
    for i = 1, 10 do
        local t = (i - 1) / 9
        local x = E.FIELD_W / 2 + swing * math.sin((i - 1) * freq + phase) + (rng() - 0.5) * 40
        if x < 60 then x = 60 elseif x > E.FIELD_W - 60 then x = E.FIELD_W - 60 end
        path[i] = { x = x, y = (E.FIELD_H - 90) - t * (E.FIELD_H - 220) + (rng() - 0.5) * 16 }
    end
    return path
end
local NODE_PATH = nodePath(1)

function UI:CreateLevelSelect()
    local FW, FH = E.FIELD_W, E.FIELD_H
    local panel = CreateFrame("Frame", nil, self.frame)
    panel:SetSize(FW, FH)
    panel:SetPoint("TOPLEFT", self.view, "TOPLEFT", 0, 0)
    panel:SetFrameLevel(self.field:GetFrameLevel() + 10)
    panel.mapBg = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
    panel.mapBg:SetAllPoints(panel)
    ART:Set(panel.mapBg, "map_bg_1")
    local edge = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    edge:SetAllPoints(panel)
    edge:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
    edge:SetBackdropBorderColor(0.45, 0.35, 0.70, 1)
    panel:EnableMouse(true)
    panel:Hide()
    self.levelPanel = panel

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOP", 0, -14)
    panel.title:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.subtitle:SetPoint("TOP", panel.title, "BOTTOM", 0, -4)
    panel.subtitle:SetTextColor(0.7, 0.7, 0.85)

    panel.prev10 = makeButton(panel, 36, 24, "<<")
    panel.prev10:SetPoint("TOPLEFT", 10, -10)
    panel.prev10:SetScript("OnClick", function() UI:LevelPage(UI.levelPage - 10) end)
    panel.prev = makeButton(panel, 60, 24, "< Prev")
    panel.prev:SetPoint("LEFT", panel.prev10, "RIGHT", 4, 0)
    panel.prev:SetScript("OnClick", function() UI:LevelPage(UI.levelPage - 1) end)
    panel.next10 = makeButton(panel, 36, 24, ">>")
    panel.next10:SetPoint("TOPRIGHT", -10, -10)
    panel.next10:SetScript("OnClick", function() UI:LevelPage(UI.levelPage + 10) end)
    panel.next = makeButton(panel, 60, 24, "Next >")
    panel.next:SetPoint("RIGHT", panel.next10, "LEFT", -4, 0)
    panel.next:SetScript("OnClick", function() UI:LevelPage(UI.levelPage + 1) end)

    -- the path: dots between the nodes
    panel.pathDots = {}
    for i = 1, 9 * 7 do
        local d = panel:CreateTexture(nil, "ARTWORK")
        d:SetSize(5, 5)
        ART:Set(d, "dot", 0.6, 0.5, 0.8, 0.6)
        panel.pathDots[i] = d
    end
    -- lays the nodes and the dots along a chapter's path
    function panel:LayPath(chapter)
        local path = nodePath(chapter)
        for i, c in ipairs(self.nodes) do
            c:ClearAllPoints()
            c:SetPoint("CENTER", self, "TOPLEFT", path[i].x, -path[i].y)
        end
        for i, d in ipairs(self.pathDots) do
            local seg, k = math.floor((i - 1) / 7) + 1, ((i - 1) % 7 + 1) / 8
            local a, b = path[seg], path[seg + 1]
            d:ClearAllPoints()
            d:SetPoint("CENTER", self, "TOPLEFT", a.x + (b.x - a.x) * k, -(a.y + (b.y - a.y) * k))
        end
    end

    panel.nodes = {}
    for i = 1, 10 do
        local size = (i == 10) and 58 or 44
        local c = makeButton(panel, size, size, "", (i == 10) and "map_node_boss" or "map_node")
        c:SetPoint("CENTER", panel, "TOPLEFT", NODE_PATH[i].x, -NODE_PATH[i].y)
        c.text:ClearAllPoints()
        c.text:SetPoint("CENTER", 0, 3)
        c.text:SetFont("Fonts\\FRIZQT__.TTF", (i == 10) and 14 or 12, "OUTLINE")
        c.best = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        c.best:SetPoint("TOP", c, "BOTTOM", 0, 12)
        c.best:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
        c.stars = makeStars(c, 10, 1)
        for k, st in ipairs(c.stars) do st:SetPoint("TOP", c, "BOTTOM", (k - 2) * 12, 2) end
        -- the objective's icon in the corner
        c.kindMark = c:CreateTexture(nil, "OVERLAY")
        c.kindMark:SetSize(14, 14)
        ART:Set(c.kindMark, "goal_orange")
        c.kindMark:SetPoint("TOPRIGHT", 0, 0)
        c.bossMark = c:CreateTexture(nil, "BACKGROUND", nil, -1)
        c.bossMark:SetSize(size + 14, size + 14)
        c.bossMark:SetPoint("CENTER")
        ART:Set(c.bossMark, "rim", 1, 0.3, 0.3, 0.9)
        if i ~= 10 then c.bossMark:Hide() end
        c:SetScript("OnClick", function(self)
            if self.level and GP:IsUnlocked(self.level) then
                UI:HideLevelSelect()
                UI:StartLevel(self.level)
            end
        end)
        c:SetScript("OnEnter", function(self)
            if not self.level or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local kind = L:Objective(self.level)
            GameTooltip:AddLine("Level " .. self.level)
            local def = E.OBJECTIVES[kind] or E.OBJECTIVES.classic
            if kind == "boss" then
                local bossDef = L:BossFor(self.level)
                GameTooltip:AddLine("Boss: " .. bossDef.name .. " - " .. bossDef.blurb, 1, 0.5, 0.5, true)
            elseif kind == "duel" then
                local duelDef = L:DuelFor(self.level)
                GameTooltip:AddLine(("Duel with %s - %s"):format(duelDef.name, duelDef.blurb), 1, 0.5, 0.5, true)
            else
                GameTooltip:AddLine(def.name .. " level: " .. def.text, 0.9, 0.9, 1, true)
            end
            if L:NoBucket(self.level) then GameTooltip:AddLine("No bucket on this level", 1, 0.8, 0.4) end
            if GP:IsUnlocked(self.level) then
                local s2, s3 = L:StarScores(self.level)
                GameTooltip:AddLine("2 stars at " .. fmtBig(s2) .. ", 3 stars at " .. fmtBig(s3), 0.7, 0.7, 0.8)
            else
                GameTooltip:AddLine("Locked: clear the level before it", 0.6, 0.6, 0.6)
            end
            local db = GP:GetDB()
            if db.best[self.level] then GameTooltip:AddLine("Best " .. fmtBig(db.best[self.level]), 1, 0.85, 0.2) end
            GameTooltip:Show()
            hoverButton(self, true)
        end)
        c:SetScript("OnLeave", function(self)
            if GameTooltip then GameTooltip:Hide() end
            if self:IsEnabled() then hoverButton(self, false) end
        end)
        panel.nodes[i] = c
    end
    panel.cells = panel.nodes
    panel:LayPath(1)

    panel.back = makeButton(panel, 120, 26, "Back to the game")
    panel.back:SetPoint("BOTTOM", -66, 10)
    panel.back:SetScript("OnClick", function() UI:HideLevelSelect() end)
    -- wipes progress after a second click within a few seconds
    panel.reset = makeButton(panel, 120, 26, "Reset progress")
    panel.reset:SetPoint("BOTTOM", 66, 10)
    panel.reset:SetScript("OnClick", function(self)
        if self.armedUntil and GetTime() < self.armedUntil then
            self.armedUntil = nil
            self.text:SetText("Reset progress")
            GP:ResetProgress()
        else
            self.armedUntil = GetTime() + 6
            self.text:SetText("|cffff6060Really? Click again|r")
            GP:Print("Reset progress: click the button again within six seconds to wipe every level, star and best score. The day's plays are kept.")
        end
    end)
    -- the owner's characters can open every level for testing
    panel.unlock = makeButton(panel, 150, 24, "Unlock all (testing)")
    panel.unlock:SetPoint("BOTTOM", 0, 40)
    panel.unlock:SetScript("OnClick", function() GP:UnlockAll() end)
    panel.unlock:Hide()
    panel.reset:SetScript("OnLeave", function(self)
        if GameTooltip then GameTooltip:Hide() end
        if self:IsEnabled() then hoverButton(self, false) end
    end)
end

-- The board's chrome: the host's box, the balls-left strip, the special-ball
-- buttons and the bucket. Hidden while the map or the out-of-plays panel covers the board.
function UI:SetBoardChrome(shown)
    local function set(obj) if obj then if shown then obj:Show() else obj:Hide() end end end
    set(self.portraitBox); set(self.portraitRingFrame); set(self.barrelFrame)
    for _, b in ipairs(self.ballStrip or {}) do if shown then b:Show() else b:Hide() end end
    if not shown then self.ballStripMore:SetText("") end
    for _, b in ipairs(self.itemSlots or {}) do set(b) end
    if shown then
        if self.state and not self.state.noBucket and self.state.phase ~= E.PHASE.FEVER then self.bucket:Show() end
        self:UpdateCounters()
    else
        self.bucket:Hide()
        self.splashTex:Hide()
    end
end

function UI:ShowLevelSelect()
    self:Initialize()
    local current = (self.state and self.state.level) or GP:GetDB().current or 1
    self.levelPage = math.floor((current - 1) / L.PER_CHAPTER) + 1
    self:LevelPage(self.levelPage)
    self.levelPanel:Show()
    self:SetBoardChrome(false)
end

function UI:HideLevelSelect()
    if self.levelPanel then self.levelPanel:Hide() end
    if self.playsPanel and not self.playsPanel:IsShown() then self:SetBoardChrome(true) end
end

-- page = chapter
function UI:LevelPage(page)
    local pages = math.ceil(L.COUNT / L.PER_CHAPTER)
    if page < 1 then page = 1 elseif page > pages then page = pages end
    self.levelPage = page
    local panel = self.levelPanel
    local first = (page - 1) * L.PER_CHAPTER
    ART:Set(panel.mapBg, ART:MapBackdrop(page))
    panel:LayPath(page)
    panel.title:SetText(("|cffffd700Chapter %d  -  %s|r"):format(page, L:ChapterName(page)))
    panel.subtitle:SetText(("Levels %d - %d"):format(first + 1, math.min(L.COUNT, first + L.PER_CHAPTER)))
    styleButton(panel.prev, page > 1, 0.3, 0.3, 0.45)
    styleButton(panel.prev10, page > 1, 0.3, 0.3, 0.45)
    styleButton(panel.next, page < pages, 0.3, 0.3, 0.45)
    styleButton(panel.next10, page < pages, 0.3, 0.3, 0.45)
    styleButton(panel.back, true, 0.35, 0.3, 0.45)
    styleButton(panel.reset, true, 0.45, 0.2, 0.2)
    if GP.Plays:IsOwner() then
        styleButton(panel.unlock, true, 0.2, 0.5, 0.25)
        panel.unlock:Show()
    else
        panel.unlock:Hide()
    end
    if panel.reset.armedUntil and GetTime() >= panel.reset.armedUntil then
        panel.reset.armedUntil = nil
        panel.reset.text:SetText("Reset progress")
    end
    local db = GP:GetDB()
    local current = (self.state and self.state.level) or db.current or 1
    for i, c in ipairs(panel.nodes) do
        local n = first + i
        if n > L.COUNT then
            c:Hide()
        else
            c:Show()
            c.level = n
            c.text:SetText(tostring(n))
            local best = db.best[n]
            c.best:SetText(best and (best >= 1000 and (math.floor(best / 1000) .. "k") or tostring(best)) or "")
            setStars(c.stars, db.stars[n] or 0)
            ART:Set(c.kindMark, ART:Goal(L:Objective(n)))
            local boss = (i == 10)
            if db.cleared[n] then
                ART:SetSkin(c.skin, "map_node_done")
                c.text:SetTextColor(0.85, 1, 0.85)
                c:Enable()
            elseif GP:IsUnlocked(n) then
                ART:SetSkin(c.skin, boss and "map_node_boss" or "map_node")
                c.text:SetTextColor(1, 0.95, 0.7)
                c:Enable()
            else
                ART:SetSkin(c.skin, "map_node_locked")
                c.text:SetTextColor(0.55, 0.55, 0.6)
                c:Disable()
            end
            c.enabledAlpha = 1
            ART:TintSkin(c.skin, 1, 1, 1, c:IsEnabled() and 1 or 0.7)
            if n == current then ART:TintSkin(c.skin, 1, 1, 0.8, 1) end
        end
    end
    local pathOn = 0
    for n = first + 1, first + L.PER_CHAPTER - 1 do if db.cleared[n] then pathOn = n - first end end
    for i, d in ipairs(panel.pathDots) do
        local seg = math.floor((i - 1) / 7) + 1
        if seg <= pathOn then d:SetVertexColor(0.5, 1, 0.6, 0.9) else d:SetVertexColor(0.6, 0.5, 0.8, 0.5) end
    end
    local chapterStars = 0
    for n = first + 1, first + L.PER_CHAPTER do chapterStars = chapterStars + (db.stars[n] or 0) end
end

-- ---------------------------------------------------------------------
-- Out-of-plays panel (covers the field)

function UI:CreatePlaysPanel()
    local FW, FH = E.FIELD_W, E.FIELD_H
    local panel = CreateFrame("Frame", nil, self.frame)
    panel:SetSize(FW, FH)
    panel:SetPoint("TOPLEFT", self.view, "TOPLEFT", 0, 0)
    panel:SetFrameLevel(self.field:GetFrameLevel() + 8)
    panel.skin = ART:NewSkin(panel, "frame_bg", "BACKGROUND", -8)
    ART:TintSkin(panel.skin, 1, 0.75, 0.75, 1)
    panel:EnableMouse(true)
    panel:Hide()
    self.playsPanel = panel

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    panel.title:SetPoint("TOP", 0, -200)
    panel.title:SetFont("Fonts\\FRIZQT__.TTF", 28, "OUTLINE")
    panel.title:SetText("|cffff6060OUT OF PLAYS|r")
    panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.text:SetPoint("TOP", panel.title, "BOTTOM", 0, -16)
    panel.text:SetWidth(FW - 100)
    panel.text:SetJustifyH("CENTER")
    panel.wait = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    panel.wait:SetPoint("TOP", panel.text, "BOTTOM", 0, -14)
    panel.buy = makeButton(panel, 220, 30, "Buy " .. GP.Plays.PLAYS_PER_LOT .. " plays for " .. GP.Plays:PriceText(1))
    panel.buy:SetPoint("TOP", panel.wait, "BOTTOM", 0, -24)
    panel.buy:SetScript("OnClick", function() UI:BuyPlays() end)
    panel.free = makeButton(panel, 220, 30, "Owner: " .. GP.Plays.PLAYS_PER_LOT .. " free plays")
    panel.free:SetPoint("TOP", panel.buy, "BOTTOM", 0, -8)
    panel.free:SetScript("OnClick", function() UI:ClaimFreePlays() end)
    panel.free:Hide()
    panel.how = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.how:SetPoint("TOP", panel.free, "BOTTOM", 0, -10)
    panel.how:SetWidth(FW - 120)
    panel.how:SetTextColor(0.75, 0.75, 0.85)
    panel.levels = makeButton(panel, 140, 26, "Level select")
    panel.levels:SetPoint("BOTTOM", 0, 52)
    panel.levels:SetScript("OnClick", function() UI:ShowLevelSelect() end)
end

function UI:ShowOutOfPlays(reason)
    local P = GP.Plays
    local panel = self.playsPanel
    panel.text:SetText((reason and (reason .. "\n") or "") ..
        ("You have used all %d free plays for the day."):format(P.FAILS_PER_DAY))
    panel.how:SetText(("Mail %s to %s with \"%s\" as the subject, or press the button at a mailbox and it fills in. Bought plays last 24 hours."):format(
        P:PriceText(1), P:BankerName(), P.SUBJECT))
    styleButton(panel.buy, true, 0.55, 0.4, 0.1)
    styleButton(panel.levels, true, 0.35, 0.3, 0.45)
    if P:IsOwner() then
        styleButton(panel.free, true, 0.2, 0.5, 0.25)
        panel.free:Show()
        panel.how:ClearAllPoints()
        panel.how:SetPoint("TOP", panel.free, "BOTTOM", 0, -10)
    else
        panel.free:Hide()
        panel.how:ClearAllPoints()
        panel.how:SetPoint("TOP", panel.buy, "BOTTOM", 0, -10)
    end
    self.playsPanel:Show()
    self:SetBoardChrome(false)
    self:UpdatePlaysPanel()
end

function UI:UpdatePlaysPanel()
    local P = GP.Plays
    if P:CanPlay() then
        self.playsPanel:Hide()
        if not (self.levelPanel and self.levelPanel:IsShown()) then self:SetBoardChrome(true) end
        if not self.state or self.state.phase == E.PHASE.OVER then
            self:StartLevel(GP:GetDB().current or 1)
        end
        return
    end
    self.playsPanel.wait:SetText("Next free play in |cffffd700" .. P:FormatWait(P:NextFreeIn()) .. "|r")
end

function UI:BuyPlays()
    local ok, err = GP.Plays:FillPurchaseMail(1)
    if not ok then GP:Print(err) end
end

function UI:ClaimFreePlays()
    local ok, err = GP.Plays:GrantFree()
    if not ok then GP:Print(err) end
end

function UI:OnPlaysChanged()
    if not self.frame then return end
    if self.playsPanel:IsShown() then self:UpdatePlaysPanel() end
    self:UpdateDisplay()
end

-- ---------------------------------------------------------------------
-- Level flow

-- retry=true deals the colours again (oranges land on other pegs).
function UI:StartLevel(n, retry)
    self:Initialize()
    self:SettlePendingFail()
    if not GP:IsUnlocked(n) then n = GP:GetDB().unlocked or 1 end
    if not GP.Plays:CanPlay() then
        self:ShowOutOfPlays()
        self:UpdateDisplay()
        return false
    end
    self.attempts = self.attempts or {}
    if retry then self.attempts[n] = (self.attempts[n] or 0) + 1 else self.attempts[n] = 0 end
    local spec = L:Build(n, self.attempts[n])
    local last = GP:GetDB().lastPower
    if last then
        for _, id in ipairs(GP:UnlockedPowers()) do if id == last then spec.power = last end end
    end
    self.state = E:NewLevel(spec)
    if self.card then self:HideCard() end
    if self.shotText then self.shotText:SetText("") end
    self.duelStartAt, self.duelTurnAt, self.rivalShotAt = nil, nil, nil
    self.paused = false
    if self.duelYou then self:UpdateDuelHud() end
    GP:GetDB().current = n
    self.guideAim = nil
    self:LayoutPegs()
    for i, bin in ipairs(self.bins) do
        bin:Hide()
        bin.label:SetText("|cffffd700" .. fmtBig(E.FEVER_BINS[i]) .. "|r")
    end
    for _, s in ipairs(self.bannerStars) do s:Hide() end
    self.bucket:Show()
    self.pyramidTex:Hide()
    self.blastTex:Hide()
    self.blastRing:Hide()
    for _, d in ipairs(self.boltDots) do d:Hide() end
    if self.state.noBucket then self.bucket:Hide() end
    ART:Set(self.fieldBg, ART:FieldBackdrop(n))
    for _, bin in ipairs(self.bins) do
        bin.litShown = false
        ART:Set(bin.tube, "fever_tube_" .. bin.letter)
    end
    for _, t in ipairs(self.postTex) do t:Hide() end
    self.splashAt, self.flashAt, self.electricUntil, self.calloutUntil = nil, nil, nil, nil
    self.splashTex:Hide(); self.flashTex:Hide(); self.calloutTex:Hide(); self.lastGlow:Hide()
    self:ClearFx()
    self:StopFanfare()
    self:HideGuide()
    self:ShowBanner(("|cffffd700%d. %s|r"):format(n, spec.title or ""), self:ObjectiveText(self.state), 3)
    GP:PlayVoice(spec.objective == "boss" and "boss_start" or (spec.objective == "duel" and "duel_start" or "level_start"))
    GP.Mascot:React("start")
    self:UpdateDisplay()
    local talk = GP.Dialog and GP.Dialog:For(self.state) or {}
    if #talk > 0 then
        self.cardSheet:Show()
        GP.Dialog:Play(talk, function() UI:ShowStartCard() end)
    else
        self:ShowStartCard()
    end
    return true
end

function UI:NextLevel()
    local st = self.state
    local n = st and st.level or GP:GetDB().current or 1
    if n + 1 <= L.COUNT and GP:IsUnlocked(n + 1) then
        self:StartLevel(n + 1)
    end
end

function UI:OnFieldClick()
    local st = self.state
    if not st then return end
    if st.duel and st.duel.stage == 2 and st.duel.turn == "rival" then return end
    if not E:CanLaunch(st) then return end
    self:AimAtCursor()
    if E:Launch(st, self.events) then
        self:HideGuide()
        self.flashAt = GetTime()
        GP:PlaySfx("launch.ogg")
        GP.Mascot:React("launch")
        self:UpdateDisplay()
    end
end

-- ---------------------------------------------------------------------
-- Power-ups

function UI:ToggleItem(item)
    local st = self.state
    if not st or st.phase ~= E.PHASE.AIM then return end
    if st.armed == item then
        E:Arm(st, nil)
    elseif GP:ItemCount(item) > 0 then
        E:Arm(st, item)
    end
    self:UpdateItemSlots()
end

function UI:UpdateItemSlots()
    local st = self.state
    for _, b in ipairs(self.itemSlots or {}) do
        local n = GP:ItemCount(b.item)
        local armed = st and st.armed == b.item
        b.text:SetText(("x%d%s"):format(n, armed and " |cff88ff88ARMED|r" or ""))
        styleButton(b, (n > 0 or armed) and st ~= nil, armed and 0.2 or 0.35, armed and 0.5 or 0.3, 0.25)
    end
end

-- ---------------------------------------------------------------------
-- The duel

function UI:UpdateDuelHud()
    local st = self.state
    if not (st and st.duel and st.duel.stage == 2) then
        self.duelYou:Hide()
        self.duelRival:Hide()
        return
    end
    local d = st.duel
    local yb = (d.turn == "you") and st.ballsLeft or d.balls.you
    local rb = (d.turn == "rival") and st.ballsLeft or d.balls.rival
    local function balls(n) return string.rep("o", math.max(0, n)) end
    self.duelYou:SetText(("%sYOU\n%s\n%s|r"):format(d.turn == "you" and "|cff88ff88" or "|cffcccccc", fmtBig(d.scores.you), balls(yb)))
    self.duelRival:SetText(("%s%s\n%s\n%s|r"):format(d.turn == "rival" and "|cffff8080" or "|cffcccccc", d.name:upper(), fmtBig(d.scores.rival), balls(rb)))
    self.duelYou:Show()
    self.duelRival:Show()
end

function UI:OnDuelTurn(turn, now)
    local st = self.state
    if turn == "rival" then
        self:ShowBanner(("|cffff8080%s'S TURN|r"):format(st.duel.name:upper()), "", 1.6)
        GP:PlaySfx("boss_turn.ogg")
        GP:PlayVoice("boss_turn")
        GP.Mascot:React("boss_turn")
        st.aim = E:RivalAim(st)
        self.guideDirty = true
        self.rivalShotAt = now + E.RIVAL_THINK
    else
        self:ShowBanner("|cff88ff88YOUR TURN|r", "", 1.4)
        self.rivalShotAt = nil
    end
    self:UpdateDuelHud()
end

-- Stage one is clear: build the shared board and flip the coin.
function UI:BeginDuel(now)
    local st = self.state
    local spec2 = L:Build(st.level, (self.attempts and self.attempts[st.level] or 0) * 7 + 50, { stage2 = true })
    self.state = E:StartDuel(st, spec2)
    st = self.state
    self:LayoutPegs()
    self.bucket:Show()
    for _, bin in ipairs(self.bins) do bin:Hide() end
    for _, t in ipairs(self.postTex) do t:Hide() end
    self:HideGuide()
    self.zoomScale = 1
    self:ShowBanner("|cffffd700COIN FLIP|r", (st.duel.turn == "you") and "You shoot first" or (st.duel.name .. " shoots first"), 2)
    GP:PlaySfx("free_ball.ogg")
    self:UpdateDuelHud()
    self:UpdateDisplay()
    self.duelTurnAt = now + 2.1
end

-- ---------------------------------------------------------------------
-- Field drawing

local function placeAt(tex, field, x, y)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", field, "TOPLEFT", x, -y)
end

function UI:LayoutPegs(midLevel)
    local st = self.state
    local field = self.field
    self.pegIndex = {}
    if not midLevel and (not self.introAt or GetTime() - self.introAt > 2) then self.introAt = GetTime() end
    for i, p in ipairs(st.pegs) do
        local t = self.pegTex[i]
        if t then t.sweepAt = nil end
        if not t then
            t = {}
            t.ring = field:CreateTexture(nil, "ARTWORK", nil, 0)
            t.rim = field:CreateTexture(nil, "ARTWORK", nil, 0)
            t.disc = field:CreateTexture(nil, "ARTWORK", nil, 1)
            t.crack = field:CreateTexture(nil, "ARTWORK", nil, 2)
            ART:Set(t.crack, "crack")
            self.pegTex[i] = t
        end
        local base = pieceSlot(p, "")
        ART:Set(t.disc, base)
        t.slotState = ""
        if p.shape == "brick" then
            t.disc:SetSize(ART:Size(base, p.w, p.h))
            ART:Set(t.ring, "brick", 1, 1, 1)
            t.ring:SetSize(p.w + 12, p.h + 12)
            ART:Set(t.rim, "brick", 1, 1, 1)
            t.rim:SetSize(p.w + 5, p.h + 5)
            t.crack:SetSize(p.w, p.h)
            if t.disc.SetRotation then
                t.disc:SetRotation(-p.angle)
                t.ring:SetRotation(-p.angle)
                t.rim:SetRotation(-p.angle)
                t.crack:SetRotation(-p.angle)
            end
        else
            local r = p.r or E.PEG_R
            t.disc:SetSize(ART:Size(base, r * 2 + 2))
            ART:Set(t.ring, "ring", 1, 1, 1)
            t.ring:SetSize(r * 2 + 18, r * 2 + 18)
            ART:Set(t.rim, "rim", 1, 1, 1)
            t.rim:SetSize(r * 2 + 8, r * 2 + 8)
            t.crack:SetSize(r * 2 + 2, r * 2 + 2)
            if t.disc.SetRotation then
                t.disc:SetRotation(0)
                t.ring:SetRotation(0)
                t.rim:SetRotation(0)
                t.crack:SetRotation(0)
            end
        end
        t.x0 = p.x      -- a loose piece rolls: its turn comes from how far it has moved
        for _, tex in ipairs({ t.disc, t.ring, t.rim, t.crack }) do placeAt(tex, field, p.x, p.y) end
        -- the boss sits behind the pegs, everything else in front of it
        if t.disc.SetDrawLayer then
            local boss = p.kind == "boss"
            pcall(t.ring.SetDrawLayer, t.ring, boss and "BACKGROUND" or "ARTWORK", boss and 4 or 0)
            pcall(t.rim.SetDrawLayer, t.rim, boss and "BACKGROUND" or "ARTWORK", boss and 4 or 0)
            pcall(t.disc.SetDrawLayer, t.disc, boss and "BACKGROUND" or "ARTWORK", boss and 5 or 1)
            pcall(t.crack.SetDrawLayer, t.crack, boss and "BACKGROUND" or "ARTWORK", boss and 6 or 2)
        end
        t.disc:SetAlpha(1)
        t.disc:Show()
        t.ring:Hide()
        t.crack:Hide()
        if (p.maxhp or 1) > 1 and p.kind ~= "egg" and p.kind ~= "boss" then
            local c = (p.maxhp >= 3) and RIM_HEAVY or RIM
            t.rim:SetVertexColor(c[1], c[2], c[3], 1)
            t.rim:SetAlpha(1)
            t.rim:Show()
        else
            t.rim:Hide()
        end
        t.shown = nil
        t.kind = nil
        t.flashUntil = nil
        t.crackHp = nil
        t.hpShown = nil
        t.sweepSparked = nil
        self.pegIndex[p] = i
    end
    for i = #st.pegs + 1, #self.pegTex do
        local t = self.pegTex[i]
        t.disc:Hide(); t.ring:Hide(); t.rim:Hide(); t.crack:Hide()
        t.shown = "gone"
    end
    if st.boss then
        self.bossName:SetText(st.boss.bossName or "Boss")
        self.bossBg:Show(); self.bossFill:Show(); self.bossName:Show()
    else
        self.bossBg:Hide(); self.bossFill:Hide(); self.bossName:Hide()
    end
end

function UI:HideGuide()
    for _, d in ipairs(self.guideDots) do d:Hide() end
    if self.guideBall then self.guideBall:Hide() end
    self.guideAim = nil
end

function UI:DrawGuide()
    local st = self.state
    local pts, hit, hx, hy
    local super = st.superGuide > 0
    if super then pts = E:Simulate(st) else pts, hit, hx, hy = E:Guide(st) end
    -- the ball drawn where it first meets a piece (walls do not count)
    if hit and hx then
        placeAt(self.guideBall, self.field, hx, hy)
        self.guideBall:Show()
    else
        self.guideBall:Hide()
    end
    for i, d in ipairs(self.guideDots) do
        local p = pts[i]
        if p then
            placeAt(d, self.field, p.x, p.y)
            if st.duel and st.duel.stage == 2 and st.duel.turn == "rival" then
                d:SetVertexColor(1, 0.5, 0.5, 1)
                d:SetAlpha(0.9 - 0.5 * (i / math.max(1, #pts)))
            elseif super then
                -- the rainbow laser
                local h = (i * 0.09) % 1
                local r, g, b = math.abs(h * 6 - 3) - 1, 2 - math.abs(h * 6 - 2), 2 - math.abs(h * 6 - 4)
                d:SetVertexColor(math.max(0, math.min(1, r)), math.max(0, math.min(1, g)), math.max(0, math.min(1, b)), 1)
                d:SetAlpha(0.95)
            else
                d:SetVertexColor(1, 1, 1, 1)
                d:SetAlpha(0.85 - 0.6 * (i / #self.guideDots))
            end
            d:Show()
        else
            d:Hide()
        end
    end
end

function UI:CursorField()
    if not GetCursorPosition then return nil end
    local field = self.field
    local scale = field:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    if not cx then return nil end
    local left, top = field:GetLeft(), field:GetTop()
    if not left or not top then return nil end
    return cx / scale - left, top - cy / scale
end

-- Left/Right nudge the aim by a quarter of a degree, Space pauses. Other keys pass
-- through to the game where the client allows it.
function UI:OnKey(key)
    local st = self.state
    local handled = false
    if key == "LEFT" or key == "RIGHT" then
        if st and st.phase == E.PHASE.AIM then
            local step = 0.25 * math.pi / 180
            st.aim = math.max(-E.MAX_AIM_DEG * math.pi / 180, math.min(E.MAX_AIM_DEG * math.pi / 180, (st.aim or 0) + (key == "LEFT" and -step or step)))
            self.keyAimUntil = GetTime() + 2
            self.keyAimCursor = { self:CursorField() }
            self.guideDirty = true
        end
        handled = true
    elseif key == "SPACE" then
        self:TogglePause()
        handled = true
    end
    if self.frame.SetPropagateKeyboardInput then pcall(self.frame.SetPropagateKeyboardInput, self.frame, not handled) end
end

function UI:TogglePause()
    self.paused = not self.paused
    if self.paused then self:ShowBanner("|cffffd700PAUSED|r", "Space to carry on", 0) else self:ShowBanner("", "", 0) end
end

-- The launcher swings toward the cursor rather than snapping (dt nil = snap).
function UI:AimAtCursor(dt)
    local st = self.state
    if not st then return end
    if st.duel and st.duel.stage == 2 and st.duel.turn == "rival" then return end
    local fx, fy = self:CursorField()
    if not fx then return end
    -- after an arrow-key nudge the cursor only takes over once it moves
    if self.keyAimUntil then
        local c = self.keyAimCursor
        if GetTime() < self.keyAimUntil and c and c[1] and math.abs(c[1] - fx) < 3 and math.abs(c[2] - fy) < 3 then return end
        self.keyAimUntil = nil
    end
    if fx < -120 or fx > E.FIELD_W + 120 or fy < -60 or fy > E.FIELD_H + 120 then return end
    local target = E:AimAngle(fx, fy)
    if not target then return end
    st.aim = target
end

function UI:ShowBanner(text, subText, secs)
    self.banner:SetText(text or "")
    self.bannerSub:SetText(subText or "")
    self.bannerUntil = (secs and secs > 0) and (GetTime() + secs) or nil
end

function UI:Popup(x, y, text, r, g, b)
    local p
    for _, cand in ipairs(self.popups) do
        if not cand:IsShown() then p = cand break end
    end
    if not p then p = self.popups[1] end
    -- never under the host's box
    local boxR = E.LAUNCH_R + 20
    local dx, dy = x - E.FIELD_W / 2, y - E.LAUNCH_CY
    if dx * dx + dy * dy < boxR * boxR then
        y = E.LAUNCH_CY + math.sqrt(math.max(0, boxR * boxR - dx * dx)) + 4
    end
    placeAt(p, self.field, x, y)
    p:SetText(text)
    p:SetTextColor(r or 1, g or 1, b or 1)
    p:SetAlpha(1)
    p.born = GetTime()
    p.x, p.y = x, y
    p:Show()
end

-- ---------------------------------------------------------------------
-- Effects: a pool of textures for sparkles, confetti, fireworks and
-- glows; the ball's ribbon; the callout graphic.

-- spec: slot or frames (a list of slots played over the life), x, y,
-- size, life, r/g/b tint, vx/vy, grav, grow (size multiplier at the end),
-- spin (radians a second), fade (alpha to zero over the life)
function UI:Spawn(spec)
    local tex
    for _, cand in ipairs(self.fx) do
        if not cand:IsShown() then tex = cand break end
    end
    if not tex then return end
    tex.spec = spec
    tex.born = GetTime()
    tex.x, tex.y = spec.x, spec.y
    tex.vx, tex.vy = spec.vx or 0, spec.vy or 0
    tex.frame = nil
    local first = spec.frames and spec.frames[1] or spec.slot
    ART:Set(tex, first, spec.r or 1, spec.g or 1, spec.b or 1, 1)
    tex:SetSize(spec.size, spec.size)
    tex:SetAlpha(1)
    if tex.SetRotation then tex:SetRotation(0) end
    placeAt(tex, self.field, spec.x, spec.y)
    tex:Show()
end

function UI:ClearFx()
    for _, t in ipairs(self.fx or {}) do t:Hide() end
    for _, t in ipairs(self.trail or {}) do t:Hide() end
    self.trailPts = {}
end

function UI:UpdateFx(now, dt)
    for _, t in ipairs(self.fx) do
        if t:IsShown() then
            local s = t.spec
            local age = now - t.born
            if age >= s.life then
                t:Hide()
            else
                local f = age / s.life
                if s.frames then
                    local idx = math.min(#s.frames, math.floor(f * #s.frames) + 1)
                    if t.frame ~= idx then
                        t.frame = idx
                        ART:Set(t, s.frames[idx], s.r or 1, s.g or 1, s.b or 1, 1)
                    end
                end
                if s.grav then t.vy = t.vy + s.grav * dt end
                t.x, t.y = t.x + t.vx * dt, t.y + t.vy * dt
                local size = s.size * (1 + ((s.grow or 1) - 1) * f)
                t:SetSize(size, size)
                if s.fade then t:SetAlpha(1 - f) end
                if s.spin and t.SetRotation then t:SetRotation(s.spin * age) end
                placeAt(t, self.field, t.x, t.y)
            end
        end
    end
end

-- A sparkle burst at a point, in a colour.
function UI:Sparks(x, y, c, n, size)
    c = c or { 1, 1, 1 }
    for k = 1, n or 3 do
        local a = math.random() * math.pi * 2
        local sp = 30 + math.random() * 60
        self:Spawn({ frames = ART:Frames("spark", 4), x = x, y = y, size = size or 18, life = 0.3 + math.random() * 0.15,
            r = c[1], g = c[2], b = c[3], vx = math.cos(a) * sp, vy = math.sin(a) * sp, grow = 1.6, fade = true })
    end
end

-- Confetti and fireworks: the GNOME bonus and a three-star clear.
function UI:Celebrate(x, y)
    x, y = x or E.FIELD_W / 2, y or E.FIELD_H / 3
    for _ = 1, 3 do
        local hx, hy = x + (math.random() - 0.5) * 200, y + (math.random() - 0.5) * 120
        self:Spawn({ slot = "firework", x = hx, y = hy, size = 30, life = 0.7, grow = 5,
            r = 0.6 + math.random() * 0.4, g = 0.6 + math.random() * 0.4, b = 0.6 + math.random() * 0.4, fade = true })
    end
    for _ = 1, 14 do
        self:Spawn({ slot = "confetti", x = x + (math.random() - 0.5) * 160, y = y, size = 22 + math.random() * 14, life = 1.3 + math.random() * 0.5,
            vx = (math.random() - 0.5) * 220, vy = -180 - math.random() * 160, grav = 420, spin = (math.random() - 0.5) * 8, fade = true })
    end
end

-- The ribbon behind the first ball: a segment between each pair of
-- recent positions, fading toward the tail.
function UI:UpdateTrail(ball, now)
    local pts = self.trailPts
    if not ball then
        if #pts > 0 then
            for _, t in ipairs(self.trail) do t:Hide() end
            self.trailPts = {}
        end
        return
    end
    local last = pts[#pts]
    if not last or (math.abs(last.x - ball.x) + math.abs(last.y - ball.y)) > 4 then
        pts[#pts + 1] = { x = ball.x, y = ball.y }
        if #pts > TRAIL_LEN + 1 then table.remove(pts, 1) end
    end
    for i, t in ipairs(self.trail) do
        local a, b = pts[#pts - i], pts[#pts - i + 1]
        if a and b then
            local dx, dy = b.x - a.x, b.y - a.y
            local len = math.sqrt(dx * dx + dy * dy)
            t:SetSize(math.max(4, len + 2), 10)
            if t.SetRotation then t:SetRotation(-(math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx))) end
            t:SetAlpha(0.9 * (1 - (i - 1) / TRAIL_LEN))
            placeAt(t, self.field, (a.x + b.x) / 2, (a.y + b.y) / 2)
            t:Show()
        else
            t:Hide()
        end
    end
end

-- A drawn callout (FEVER!) over the banner text for a moment.
function UI:ShowCallout(slot, secs)
    ART:Set(self.calloutTex, slot)
    self.calloutTex:Show()
    self.calloutUntil = GetTime() + (secs or 2)
end

function UI:UpdatePopups(now)
    for _, p in ipairs(self.popups) do
        if p:IsShown() then
            local age = now - (p.born or now)
            if age > 0.9 then
                p:Hide()
            else
                placeAt(p, self.field, p.x, p.y - age * 36)
                p:SetAlpha(1 - age / 0.9)
            end
        end
    end
end

-- The clearing fanfare: starts when the last goal piece lights, loops
-- while the leftover balls fly, stops when the level is over.
function UI:StartFanfare(now)
    local _, handle = GP:PlaySfx("fever_music.ogg")
    self.fanfareHandle = handle
    self.fanfareAt = now
end

function UI:StopFanfare(instant)
    if self.fanfareHandle and type(StopSound) == "function" then pcall(StopSound, self.fanfareHandle, instant and 0 or 600) end
    self.fanfareHandle = nil
    self.fanfareAt = nil
end

function UI:UpdateFanfare(now)
    local st = self.state
    if not self.fanfareAt then return end
    if not st or st.phase ~= E.PHASE.FEVER then
        self:StopFanfare()
    elseif now - self.fanfareAt >= FANFARE_SECS - 0.05 then
        self:StartFanfare(now)
    end
end

-- A lightning bolt: dots along the path for a moment.
function UI:ShowBolt(path, now)
    local k = 0
    for i = 2, #path do
        local a, b = path[i - 1], path[i]
        local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
        local n = math.max(2, math.floor(len / 12))
        for s = 0, n do
            k = k + 1
            local d = self.boltDots[k]
            if not d then break end
            local f = s / n
            local jitter = (s > 0 and s < n) and ((math.random() - 0.5) * 8) or 0
            placeAt(d, self.field, a.x + (b.x - a.x) * f + jitter, a.y + (b.y - a.y) * f + jitter)
            d:SetAlpha(1)
            d:Show()
        end
    end
    for i = k + 1, #self.boltDots do self.boltDots[i]:Hide() end
    self.boltUntil = now + 0.5
end

function UI:ShowBlast(x, y, now, radius)
    self.blastAt = now
    self.blastRadius = radius or E.BLAST_RADIUS
    self.blastX, self.blastY = x, y
    self.blastTex:Show()
    self.blastRing:Show()
end

local POWER_BANNERS = {
    multiball = "|cff88ff88MULTIBALL!|r", guide = "|cff88ff88SUPER GUIDE!|r", blast = "|cffffaa44SPACE BLAST!|r", frenzy = "|cffffd700FREE BALL FRENZY!|r",
    fireball = "|cffff8844FIREBALL!|r", spooky = "|cffaaffaaSPOOKY BALL!|r", pyramid = "|cffffd700PYRAMID!|r",
    lightning = "|cffaaddffCHAIN LIGHTNING!|r",
}

local MASCOT_REACTIONS = {
    bucket = "bucket", freeball_score = "freeball", power = "power", combo = "combo", style = "style",
    total_miss = "total_miss", last_peg = "last_peg", fever = "fever", gnome_bonus = "gnome_bonus",
    crack = "boss_hit", boss_down = "boss_down", boss_turn = "boss_turn", unlock = "unlock",
    gem_caught = "gem", gem_dropped = "gem",
}

function UI:HandleEvents(now)
    local st = self.state
    for _, ev in ipairs(self.events) do
        local t = ev.type
        local reaction = MASCOT_REACTIONS[t]
        if reaction and not (t == "crack" and ev.peg.kind ~= "boss") and not (t == "last_peg" and ev.again) then
            GP.Mascot:React(reaction)
        end
        if t == "bounce" then
            -- a knock on something already lit, or a barrier: a soft click
            if ev.speed > 60 and now - (self.lastHitSound or 0) > 0.08 then
                self.lastHitSound = now
                GP:PlaySfx("peg" .. math.random(3) .. ".ogg")
            end
        elseif t == "bumper" then
            GP:PlaySfx("bumper.ogg")
            if ev.peg.balloon then
                for _, b in ipairs(self.postTex) do
                    if math.abs(b.x - ev.peg.x) < 1 then b.squashAt = now end
                end
            end
            local idx = self.pegIndex and self.pegIndex[ev.peg]
            local tx = idx and self.pegTex[idx]
            if tx then tx.flashUntil = now + 0.2 end
        elseif t == "crack" then
            local idx = self.pegIndex and self.pegIndex[ev.peg]
            local tx = idx and self.pegTex[idx]
            if tx then tx.flashUntil = now + 0.15 end
            if ev.peg.kind == "boss" then
                GP:PlaySfx("boss_hit.ogg")
                self:Popup(ev.x, ev.y - 30, "+" .. ev.points, 1, 0.5, 0.5)
            elseif ev.peg.kind == "egg" then
                GP:PlaySfx("crack.ogg")
                self:Popup(ev.x, ev.y - 16, "crack!", 1, 0.95, 0.7)
            elseif not ev.quiet then
                GP:PlaySfx("clink.ogg")
            end
        elseif t == "shield" then
            GP:PlaySfx("shield.ogg")
            self:Popup(ev.x, ev.y - 30, "BLOCKED", 0.6, 0.8, 1)
        elseif t == "boss_shield" then
            self:ShowBanner("|cff88ccffSHIELD UP|r", "The boss blocks the next two hits", 1.4)
            GP:PlayVoice("boss_shield")
        elseif t == "boss_hop" then
            GP:PlaySfx("hop.ogg")
            self:Popup(ev.x, ev.y - 30, "!", 1, 1, 0.5)
        elseif t == "boss_scrap" then
            self:LayoutPegs(true)
            GP:PlaySfx("clink.ogg")
            self:Popup(ev.x, ev.y - 40, "SCRAP!", 1, 0.6, 0.3)
        elseif t == "boss_heal" then
            GP:PlaySfx("heal.ogg")
            self:Popup(ev.x, ev.y - 30, "+1", 1, 0.4, 0.4)
        elseif t == "boss_down" then
            GP:PlaySfx("boss_down.ogg")
            GP:PlayVoice("boss_down")
        elseif t == "stage_clear" then
            self:ShowBanner("|cffffd700BOARD CLEARED!|r", (st.duel and st.duel.name or "The rival") .. " refuses to accept it. A duel!", 2.5)
            GP:PlaySfx("clear.ogg")
            GP:PlayVoice("duel_start")
            self.duelStartAt = now + 2.6
        elseif t == "duel_turn" then
            self:OnDuelTurn(ev.turn, now)
        elseif t == "duel_penalty" then
            if ev.side == "you" then
                self:ShowBanner("|cffff6060MISS PENALTY|r", ("No orange lit: -%s"):format(fmtBig(ev.lost)), 1.8)
                GP:PlaySfx("lost.ogg")
            else
                self:ShowBanner("|cff88ff88HE MISSED!|r", ("%s loses %s"):format(st.duel.name, fmtBig(ev.lost)), 1.8)
            end
            self:UpdateDuelHud()
        elseif t == "phoenix" then
            GP:PlaySfx("hatch.ogg")
            self:Sparks(ev.x, ev.y, { 1, 0.6, 0.2 }, 8, 28)
        elseif t == "gem_free" then
            GP:PlaySfx("gem_free.ogg")
            self:Sparks(ev.x, ev.y, COLORS.gem.glow, 4, 22)
        elseif t == "gem_caught" then
            self:ShowBanner("|cff88ffffBUCKET DROP!|r", "+" .. fmtBig(ev.bonus or 0), 1.6)
            self:Popup(ev.x, ev.y - 10, "GEM!", 0.6, 1, 1)
            self.splashAt = now
            GP:PlaySfx("gem.ogg")
            GP:PlaySfx("bucket.ogg")
            GP:PlayVoice("gem")
        elseif t == "egg_fall" then
            self:ShowBanner("|cffff9060THE EGG!|r", "Catch it in the bucket!", 1.5)
            GP:PlaySfx("crack.ogg")
            GP.Mascot:React("two_left")
        elseif t == "egg_saved" then
            self:ShowBanner("|cffffd700PHOENIX HATCH!|r", "+" .. fmtBig(ev.bonus), 2)
            self:Popup(ev.x, ev.y - 10, "SAVED!", 1, 0.95, 0.6)
            self.splashAt = now
            self:Sparks(ev.x, ev.y, COLORS.egg.glow, 6, 24)
            GP:PlaySfx("hatch.ogg")
            GP:PlayVoice("hatched")
            GP.Mascot:React("hatched")
        elseif t == "egg_lost" then
            self:Popup(ev.x, E.FIELD_H - 30, "LOST", 1, 0.4, 0.4)
            GP:PlaySfx("fail.ogg")
        elseif t == "longshot_goal" then
            self:Popup(E.FIELD_W / 2, 120, ("LONG SHOT! %d to go"):format(ev.left), 1, 0.9, 0.4)
        elseif t == "gem_dropped" then
            self:Popup(ev.x, ev.y, "GEM!", 0.6, 1, 1)
            GP:PlaySfx("gem.ogg")
            GP:PlayVoice("gem")
        elseif t == "item_used" then
            GP:SpendItem(ev.item)
            self:UpdateItemSlots()
        elseif t == "ring" then
            self:ShowBlast(ev.x, ev.y, now, ev.radius)
            GP:PlaySfx(ev.item == "rainbow" and "blast.ogg" or "power_fireball.ogg")
            self:ShowBanner(ev.item == "rainbow" and "|cffff88ffRAINBOW BALL!|r" or "|cffff8844RING OF FIRE!|r", "", 1.2)
        elseif t == "unlock" then
            self:ShowBanner("|cffffd700UNLOCKED!|r", "The cage falls away", 1.5)
            self:Popup(ev.x, ev.y - 16, "KEY!", 1, 0.9, 0.4)
            GP:PlaySfx("unlock.ogg")
        elseif t == "style" then
            self:ShowBanner(("|cff88ff88+%s STYLE POINTS|r"):format(fmtBig(ev.points)), ev.name, 1.8)
            self:Sparks(ev.x, ev.y, { 1, 0.9, 0.4 }, 6, 26)
            GP:PlaySfx("combo.ogg")
            GP:PlayVoice("style")
        elseif t == "shot_summary" then
            if ev.pegs > 0 then
                self.shotText:SetText(("%s x %d PEG%s = %s"):format(fmtBig(ev.avg), ev.pegs, ev.pegs == 1 and "" or "S", fmtBig(ev.points)))
                self.shotTextUntil = now + 2.2
            end
        elseif t == "total_miss" then
            self:ShowBanner("|cffff8080TOTAL MISS!|r", "", 1.6)
            GP:PlaySfx("lost.ogg")
            GP:PlayVoice("total_miss")
        elseif t == "gnome_bonus" then
            self:ShowBanner("|cffffd700G-N-O-M-E BONUS!|r", "+" .. fmtBig(ev.points) .. "  -  every bucket is worth " .. fmtBig(E.GNOME_BUCKET) .. " now", 3)
            self:Celebrate()
            GP:PlaySfx("combo.ogg")
            GP:PlayVoice("gnome_bonus")
            for _, bin in ipairs(self.bins) do bin.label:SetText("|cffffd700" .. fmtBig(E.GNOME_BUCKET) .. "|r") end
        elseif t == "gem_lost" then
            self:Popup(ev.x, E.FIELD_H - 30, "missed", 0.7, 0.7, 0.8)
        elseif t == "last_peg" then
            if not ev.again then
                GP:PlaySfx("slowmo.ogg")
                GP:PlayVoice("last_one")
            end
        elseif t == "rim" then
            -- the ceramic lip of the bucket
            if now - (self.lastRimSound or 0) > 0.1 then
                self.lastRimSound = now
                GP:PlaySfx("rim.ogg")
            end
        elseif t == "pyramid" then
            GP:PlaySfx("pyramid.ogg")
        elseif t == "lost" then
            if st.phase ~= E.PHASE.FEVER then GP:PlaySfx("lost.ogg") end
        elseif t == "zap" then
            self:ShowBolt(ev.path, now)
            self.electricUntil = now + 1.2
            GP:PlaySfx("zap.ogg")
        elseif t == "peg" then
            -- every piece lit in a shot rings one note higher
            if not ev.quiet then GP:PlaySfx("note" .. math.min(16, ev.combo or 1) .. ".ogg") end
            local k = ev.peg.kind
            local glow = (COLORS[k] or COLORS.blue).glow
            self:Sparks(ev.x, ev.y, glow, (k == "orange" or k == "green" or k == "purple") and 4 or 2)
            if k == "orange" then
                self:Popup(ev.x, ev.y - 14, "+" .. ev.points, 1, 0.8, 0.3)
            elseif k == "purple" then
                self:Popup(ev.x, ev.y - 14, "POINT BOOST +" .. ev.points, 0.9, 0.6, 1)
            elseif k == "green" then
                self:Popup(ev.x, ev.y - 14, "+" .. ev.points, 0.6, 1, 0.6)
            elseif k == "egg" then
                self:Popup(ev.x, ev.y - 18, "HATCHED! +" .. ev.points, 1, 0.95, 0.6)
                GP:PlaySfx("hatch.ogg")
                GP:PlayVoice("hatched")
                GP.Mascot:React("hatched")
            elseif k == "gem" then
                self:Popup(ev.x, ev.y - 26, "+" .. ev.points, 0.6, 1, 1)
            elseif k == "boss" then
                self:ShowBanner("|cffff6060BOSS DOWN!|r", "+" .. fmtBig(ev.points), 2)
            elseif (ev.combo or 0) >= 5 then
                self:Popup(ev.x, ev.y - 14, "+" .. ev.points, 0.8, 0.9, 1)
            end
        elseif t == "combo" then
            self:ShowBanner(("|cffffd700COMBO %d!|r"):format(ev.combo), "+" .. fmtBig(ev.bonus), 1.6)
            self:Popup(ev.x, ev.y - 30, "+" .. fmtBig(ev.bonus), 1, 0.9, 0.3)
            GP:PlaySfx("combo.ogg")
            GP:PlayVoice(ev.combo >= 20 and "combo_huge" or "combo")
        elseif t == "power" then
            self:ShowBanner(POWER_BANNERS[ev.power] or "POWER!", "", 1.4)
            GP:PlayVoice("power_" .. ev.power)
            if ev.power == "blast" then
                self:ShowBlast(ev.x, ev.y, now)
                GP:PlaySfx("blast.ogg")
            elseif ev.power == "lightning" then
                GP:PlaySfx("power_lightning.ogg")
            else
                GP:PlaySfx("power_" .. ev.power .. ".ogg")
            end
        elseif t == "fever" then
            self:ShowBanner("", "", 0)
            self:ShowCallout("callout_fever", 3)
            GP:PlaySfx("fever.ogg")
            self:StartFanfare(now)
            GP:PlayVoice("fever")
            self.bucket:Hide()
            for _, bin in ipairs(self.bins) do bin:Show() end
            for _, t in ipairs(self.postTex) do t:Show() end
        elseif t == "bucket" then
            self:ShowBanner("|cff88ccffFREE BALL!|r", "", 1.5)
            self.splashAt = now
            GP:PlaySfx("bucket.ogg")
            self:Popup(ev.x, E.BucketTop() - 16, "FREE BALL", 0.6, 0.85, 1)
            GP:PlayVoice("free_ball")
        elseif t == "freeball_score" then
            self:ShowBanner("|cff88ccffFREE BALL!|r", fmtBig(ev.score) .. " points", 1.5)
            GP:PlaySfx("free_ball.ogg")
            GP:PlayVoice("free_ball")
        elseif t == "fever_shot" then
            self.flashAt = now
            GP:PlaySfx("launch.ogg")
        elseif t == "spooky" then
            GP:PlaySfx("spooky.ogg")
            self:Popup(ev.x, 30, "BOO", 0.7, 1, 0.7)
        elseif t == "bin" then
            GP:PlaySfx("bin.ogg")
            -- the last ball home: the music stops dead
            if st.ballsLeft <= 0 and #st.balls <= 1 then self:StopFanfare(true) end
            self:Popup(ev.x, E.FIELD_H - 44, "+" .. fmtBig(ev.points), 1, 0.9, 0.4)
        elseif t == "ready" then
            if st.ballsLeft == 2 then self:ShowBanner("|cffff9060 2 BALLS LEFT|r", "", 1.5); GP.Mascot:React("two_left")
            elseif st.ballsLeft == 1 then self:ShowBanner("|cffff6060LAST BALL|r", "", 1.5); GP.Mascot:React("last_ball")
            elseif st.ballsLeft > 0 and not self.bannerUntil then self:ShowBanner("", "", 0) end
        elseif t == "level_over" then
            self:StopFanfare()
            if not (st.stageClear and not st.result) then self:OnLevelOver(ev.result) end
        end
    end
    for i = #self.events, 1, -1 do self.events[i] = nil end
end

-- A loss is recorded when the player gives up on it (Retry, Map, End
-- Level, or starting something else); Play On carries the level on first.
function UI:SettlePendingFail()
    if not self.pendingFail then return end
    local result = self.pendingFail
    self.pendingFail = nil
    GP:RecordResult(result)
    self:UpdateDisplay()
end

function UI:PlayOn()
    local st = self.state
    if not st or not self.pendingFail then return end
    if not GP.Plays:CanPlay() then return end
    if not E:PlayOn(st) then return end
    GP.Plays:RecordFail()          -- the continue costs a play
    self.pendingFail = nil
    self:HideCard()
    self:ShowBanner("|cff88ff88PLAY ON!|r", ("%d more balls"):format(E.PLAY_ON_BALLS), 2)
    GP:PlaySfx("free_ball.ogg")
    GP:PlayVoice("free_ball")
    GP.Mascot:React("start")
    self:UpdateDisplay()
end

function UI:OnLevelOver(result)
    local db = GP:GetDB()
    local prevBest = db.best[result.level] or 0
    local stars, playsLeft
    local canPlayOn = not result.cleared and not result.duel and not result.eggLost
    if canPlayOn then
        -- not recorded yet: the card offers Play On
        self.pendingFail = result
        stars, playsLeft = 0, GP.Plays:Remaining()
    else
        stars, playsLeft = GP:RecordResult(result)
    end
    GP.Mascot:React(result.cleared and "cleared" or "failed")
    self.cardAt = GetTime() + 1.8
    self.cardResult, self.cardStars = result, stars
    if result.cleared then
        -- the win sweep: whatever is left on the board sparkles away, one by one
        local k = 0
        for i, p in ipairs(self.state.pegs) do
            local t = self.pegTex[i]
            if t and not p.gone then
                k = k + 1
                t.sweepAt = GetTime() + 0.4 + k * 0.03
            end
        end
        local extra = result.score > prevBest and prevBest > 0 and "  |cff88ff88New best!|r" or ""
        self:ShowBanner("|cffffd700LEVEL CLEARED!|r",
            ("%d of 3 stars  -  Score %s  (bins %s)%s"):format(stars, fmtBig(result.score), fmtBig(result.feverTotal or 0), extra), 0)
        setStars(self.bannerStars, stars)
        for _, s in ipairs(self.bannerStars) do s:Show() end
        if stars >= 3 then self:Celebrate() end
        GP:PlaySfx("clear.ogg")
        GP:PlayVoice(result.duel and "duel_won" or (stars >= 3 and "three_stars" or "level_cleared"))
        if result.level == L.COUNT then
            self:ShowBanner(("|cffffd700ALL %d LEVELS CLEARED!|r"):format(L.COUNT), "Score " .. fmtBig(result.score) .. ". You conquered Azeroth.", 0)
        end
    else
        local goalWord = (E.OBJECTIVES[result.objective] or E.OBJECTIVES.classic).goalWord
        local progress
        if result.eggLost then progress = "An egg fell off the board."
        elseif result.duel then progress = ("%s won the duel, %s to %s."):format(result.duel.name, fmtBig(result.duel.rival), fmtBig(result.duel.you))
        elseif result.objective == "boss" then progress = "The boss survived."
        else progress = ("%d of %d %s."):format(result.goals, result.goalTotal, goalWord) end
        self:ShowBanner(result.eggLost and "|cffff6060EGG LOST|r" or "|cffff6060OUT OF BALLS|r",
            progress .. ("  Plays left today: %d."):format(playsLeft), 0)
        GP:PlaySfx("fail.ogg")
        GP:PlayVoice(playsLeft <= 0 and "out_of_plays" or (result.duel and "duel_lost" or "out_of_balls"))
        if playsLeft <= 0 and not self.pendingFail then
            self:ShowOutOfPlays(("You ran out of balls on level %d."):format(result.level))
        end
    end
    self:HideGuide()
    self:UpdateDisplay()
end

function UI:OnUpdate(dt)
    local now = GetTime()
    local st = self.state
    self:UpdatePopups(now)
    if self.bannerUntil and now >= self.bannerUntil then
        self.bannerUntil = nil
        self.banner:SetText("")
        self.bannerSub:SetText("")
    end
    if self.calloutUntil and now >= self.calloutUntil then
        self.calloutUntil = nil
        self.calloutTex:Hide()
    end
    -- the ribbon sits behind any banner text (not behind a drawn callout)
    local bannerText = self.banner:GetText()
    if bannerText and bannerText ~= "" and not self.calloutUntil then self.bannerRibbon:Show() else self.bannerRibbon:Hide() end
    local subText = self.bannerSub:GetText()
    if subText and subText ~= "" then self.bannerSubBg:Show() else self.bannerSubBg:Hide() end
    self:UpdateFx(now, dt)
    if self.playsPanel and self.playsPanel:IsShown() then
        if now - (self.playsTick or 0) > 1 then
            self.playsTick = now
            self:UpdatePlaysPanel()
        end
    end
    GP.Mascot:Tick(now)
    if self.duelStartAt and now >= self.duelStartAt then
        self.duelStartAt = nil
        self:BeginDuel(now)
    end
    if self.duelTurnAt and now >= self.duelTurnAt then
        self.duelTurnAt = nil
        if self.state and self.state.duel then self:OnDuelTurn(self.state.duel.turn, now) end
    end
    if self.shotTextUntil and now >= self.shotTextUntil then
        self.shotTextUntil = nil
        self.shotText:SetText("")
    end
    if self.cardAt and now >= self.cardAt then
        self.cardAt = nil
        if self.cardResult and not (self.playsPanel and self.playsPanel:IsShown()) then
            self:ShowResultCard(self.cardResult, self.cardStars)
        end
        self.cardResult = nil
    end
    if not st then return end
    if self.levelPanel and self.levelPanel:IsShown() then return end

    if st.phase == E.PHASE.AIM then
        self:AimAtCursor(dt)
        -- the rival fires once his aim has been on show for a moment
        if st.duel and st.duel.stage == 2 and st.duel.turn == "rival" and self.rivalShotAt and now >= self.rivalShotAt then
            self.rivalShotAt = nil
            if E:Launch(st, self.events) then
                self:HideGuide()
                self.flashAt = now
                GP:PlaySfx("launch.ogg")
            end
        end
        if self.guideAim ~= st.aim or self.guideDirty then
            self.guideAim = st.aim
            self.guideDirty = nil
            self:DrawGuide()
        end
    end

    if self.paused then self:Render(now) return end
    E:Step(st, dt, self.events)
    if #self.events > 0 then
        self.guideDirty = true
        self:HandleEvents(now)
        self:UpdateCounters()
    end
    self:UpdateZoom(dt)
    self:UpdateFanfare(now)
    self:Render(now)
end

-- The field zooms in while time is slowed, centred on the ball closing on
-- the last goal piece and following it; after the hit it eases back out
-- from where the ball was. The field scales inside its clipping view; the
-- anchor offset keeps that point where it was on screen.
function UI:UpdateZoom(dt)
    local st = self.state
    local now = GetTime()
    local slow = st and st.lastSlow and st.lastPeg
    if slow then self.slowSeenAt = now end
    -- a short hold after the slow-mo lets go, so a brief gap between two
    -- stretches of it never reverses the zoom mid-way
    local hold = self.slowSeenAt and (now - self.slowSeenAt) < 0.25 and st and st.phase == E.PHASE.FLIGHT
    local target = (slow or hold) and E.LAST_ZOOM or 1
    local cur = self.zoomScale or 1
    if math.abs(target - cur) < 0.002 then
        if cur == 1 and self.zoomApplied == 1 then return end
        cur = target
    else
        -- snaps in quickly, eases out more gently
        cur = cur + (target - cur) * math.min(1, dt * (target > cur and 10 or 4))
    end
    self.zoomScale = cur
    local field = self.field
    local FW, FH = E.FIELD_W, E.FIELD_H
    -- the ball nearest the piece is the centre; keep the last one seen once it is gone
    if st and st.lastPeg and #st.balls > 0 then
        local best, bd = nil, math.huge
        for _, b in ipairs(st.balls) do
            local dx, dy = b.x - st.lastPeg.x, b.y - st.lastPeg.y
            local d = dx * dx + dy * dy
            if d < bd then best, bd = b, d end
        end
        if self.zoomX then
            -- glide after the ball rather than snapping to it
            local k = math.min(1, dt * 14)
            self.zoomX = self.zoomX + (best.x - self.zoomX) * k
            self.zoomY = self.zoomY + (best.y - self.zoomY) * k
        else
            self.zoomX, self.zoomY = best.x, best.y
        end
    elseif not self.zoomX then
        self.zoomX, self.zoomY = FW / 2, FH / 2
    end
    local zx, zy = self.zoomX, self.zoomY
    local ox = zx * (1 / cur - 1)
    local oy = zy * (1 / cur - 1)
    local minO = FW / cur - FW
    if ox < minO then ox = minO elseif ox > 0 then ox = 0 end
    local minOy = FH / cur - FH
    if oy < minOy then oy = minOy elseif oy > 0 then oy = 0 end
    if field.SetScale then field:SetScale(cur) end
    field:ClearAllPoints()
    field:SetPoint("TOPLEFT", self.view, "TOPLEFT", ox, -oy)
    self.zoomApplied = cur
    if cur == 1 then self.zoomX, self.zoomY = nil, nil end
end

function UI:Render(now)
    local st = self.state
    local field = self.field

    local a = st.aim or 0
    local cx, cy = E.FIELD_W / 2, E.LAUNCH_CY
    -- the barrel's mouth sits just past the muzzle point, its breech under the ring
    local mid = E.LAUNCH_R + 14 - BARREL_L / 2
    placeAt(self.barrel, field, cx + math.sin(a) * mid, cy + math.cos(a) * mid)
    if self.barrel.SetRotation then self.barrel:SetRotation(a) end
    -- the muzzle flash
    if self.flashAt then
        if now - self.flashAt > FLASH_SECS then
            self.flashAt = nil
            self.flashTex:Hide()
        else
            placeAt(self.flashTex, field, cx + math.sin(a) * (E.LAUNCH_R + 8), cy + math.cos(a) * (E.LAUNCH_R + 8))
            if self.flashTex.SetRotation then self.flashTex:SetRotation(a) end
            self.flashTex:SetAlpha(1 - (now - self.flashAt) / FLASH_SECS)
            self.flashTex:Show()
        end
    end

    local pulse = 0.55 + 0.35 * math.sin(now * 9)
    local intro = self.introAt and (now - self.introAt) or 99
    for i, p in ipairs(st.pegs) do
        local t = self.pegTex[i]
        if t then
            if t.sweepAt then
                -- the win sweep
                local a = 1 - (now - t.sweepAt) / 0.35
                if a <= 0 then
                    if t.shown ~= "gone" then t.disc:Hide(); t.ring:Hide(); t.rim:Hide(); t.crack:Hide(); t.shown = "gone" end
                elseif now >= t.sweepAt then
                    if not t.sweepSparked then
                        t.sweepSparked = true
                        self:Sparks(p.x, p.y, { 1, 0.9, 0.5 }, 2, 16)
                    end
                    t.disc:SetAlpha(a); t.rim:SetAlpha(a); t.ring:SetAlpha(a); t.ring:Show()
                end
            elseif p.gone then
                local age = p.goneAt and (st.time - p.goneAt) or 1
                local alpha = 1 - age / 0.35
                if alpha <= 0 then
                    if t.shown ~= "gone" then
                        t.disc:Hide(); t.ring:Hide(); t.rim:Hide(); t.crack:Hide()
                        t.shown = "gone"
                    end
                else
                    if t.shown ~= "fading" then
                        ART:Set(t.disc, pieceSlot(p, "_gone"))
                        t.shown = "fading"
                    end
                    t.disc:SetAlpha(alpha)
                    t.ring:SetAlpha(alpha * 0.8)
                    t.rim:SetAlpha(alpha)
                    t.crack:SetAlpha(alpha)
                end
            else
                if t.shown == "gone" then
                    t.disc:SetAlpha(1)
                    t.disc:Show()
                    t.shown = nil
                end
                local flashing = t.flashUntil and now < t.flashUntil
                if p.kind == "bumper" then
                    if t.shown ~= "base" then
                        local c = COLORS.bumper
                        ART:Set(t.disc, "bumper")
                        t.ring:SetVertexColor(c.glow[1], c.glow[2], c.glow[3], 1)
                        t.kind = p.kind
                        t.shown = "base"
                    end
                    if flashing then t.ring:SetAlpha(1); t.ring:Show() else t.ring:Hide() end
                elseif p.kind == "boss" then
                    ART:Set(t.disc, ART:Boss(p.ability))
                    if p.lit then t.disc:SetVertexColor(0.4, 0.4, 0.4, 1) else t.disc:SetVertexColor(1, 1, 1, 1) end
                    if flashing and not t.flashed then
                        -- a hit flash: a soft glow over the face
                        t.flashed = true
                        self:Spawn({ slot = "glow_soft", x = p.x, y = p.y, size = (p.r or E.BOSS_R) * 3.2, life = 0.25, r = 1, g = 0.7, b = 0.6, fade = true })
                    elseif not flashing then
                        t.flashed = nil
                    end
                    if (p.shield or 0) > 0 then
                        t.rim:SetVertexColor(0.5, 0.8, 1, 1)
                        t.rim:SetAlpha(0.6 + 0.4 * pulse)
                        t.rim:Show()
                    else
                        t.rim:Hide()
                    end
                    t.ring:SetVertexColor(1, 0.5, 0.5, 1)
                    if flashing then t.ring:SetAlpha(1); t.ring:Show() else t.ring:Hide() end
                    t.shown = "boss"
                elseif p.lit then
                    local c = COLORS[p.kind] or COLORS.blue
                    if t.shown ~= "lit" then
                        ART:Set(t.disc, pieceSlot(p, "_lit"))
                        t.ring:SetVertexColor(c.glow[1], c.glow[2], c.glow[3], 1)
                        t.ring:Show()
                        t.crack:Hide()
                        t.shown = "lit"
                    end
                    t.ring:SetAlpha(pulse)
                else
                    -- unlit: the purple peg hops around and an egg cracks, so
                    -- the picture follows the kind and the hits left; a hit
                    -- flash shows the lit picture for a moment
                    local want = flashing and "flash" or "base"
                    if t.kind ~= p.kind or t.shown ~= want or t.hpShown ~= p.hp then
                        ART:Set(t.disc, pieceSlot(p, flashing and "_lit" or ""))
                        t.kind = p.kind
                        t.shown = want
                        t.hpShown = p.hp
                    end
                end
                -- cracks on a damaged piece
                if (p.maxhp or 1) > 1 and p.hp < p.maxhp and not p.lit then
                    if t.crackHp ~= p.hp then
                        t.crackHp = p.hp
                        t.crack:SetVertexColor(1, 1, 1, 1)
                        t.crack:SetAlpha(p.hp <= 1 and 1 or 0.6)
                        t.crack:Show()
                    end
                elseif t.crackHp then
                    t.crackHp = nil
                    t.crack:Hide()
                end
            end
            -- the level intro: pieces fade in one after another
            if intro < 1.8 and not p.gone then
                local a = (intro - i * 0.012) / 0.2
                if a < 0 then a = 0 elseif a > 1 then a = 1 end
                t.disc:SetAlpha(a)
                if t.rim:IsShown() then t.rim:SetAlpha(a) end
                t.introDirty = true
            elseif t.introDirty then
                t.introDirty = nil
                if not p.gone then t.disc:SetAlpha(1); t.rim:SetAlpha(1) end
            end
            -- gimmick pieces move and loose pieces roll: follow them
            if (p.moving or p.loose) and not p.gone then
                placeAt(t.disc, field, p.x, p.y)
                placeAt(t.ring, field, p.x, p.y)
                placeAt(t.rim, field, p.x, p.y)
                placeAt(t.crack, field, p.x, p.y)
                if p.shape == "brick" and t.disc.SetRotation then
                    t.disc:SetRotation(-p.angle)
                    t.ring:SetRotation(-p.angle)
                    t.rim:SetRotation(-p.angle)
                    t.crack:SetRotation(-p.angle)
                elseif p.loose and t.disc.SetRotation then
                    -- it turns as far as it has rolled
                    t.disc:SetRotation(-(p.x - (t.x0 or p.x)) / (p.r or E.PEG_R))
                end
            end
        end
    end

    -- the glow on the last goal piece while time slows
    if st.lastSlow and st.lastPeg and not st.lastPeg.gone then
        self.lastGlow:SetSize(90 + 20 * pulse, 90 + 20 * pulse)
        self.lastGlow:SetAlpha(0.5 + 0.3 * pulse)
        placeAt(self.lastGlow, field, st.lastPeg.x, st.lastPeg.y)
        self.lastGlow:Show()
    elseif self.lastGlow:IsShown() then
        self.lastGlow:Hide()
    end

    -- the boss's bar follows it
    local b = st.boss
    if b and not b.gone then
        local y = b.y - E.BOSS_R - 12
        placeAt(self.bossBg, field, b.x, y)
        self.bossFill:ClearAllPoints()
        self.bossFill:SetPoint("LEFT", self.bossBg, "LEFT", 1, 0)
        self.bossFill:SetWidth(math.max(1, 70 * math.max(0, b.hp) / b.maxhp))
        self.bossName:ClearAllPoints()
        self.bossName:SetPoint("BOTTOM", self.bossBg, "TOP", 0, 1)
    elseif b and self.bossBg:IsShown() then
        self.bossBg:Hide(); self.bossFill:Hide(); self.bossName:Hide()
    end

    self.ballAura = self.ballAura or {}
    for i, tex in ipairs(self.ballTex) do
        local ball = st.balls[i]
        local aura = self.ballAura[i]
        if not aura then
            aura = field:CreateTexture(nil, "OVERLAY", nil, 1)
            ART:Set(aura, "ring")
            aura:SetSize(E.BALL_R * 5, E.BALL_R * 5)
            self.ballAura[i] = aura
        end
        if ball then
            placeAt(tex, field, ball.x, ball.y)
            ART:Set(tex, ballSlot(ball, st, now, self.electricUntil))
            tex:Show()
            if st.phase == E.PHASE.FEVER then
                local h = (now * 0.8 + i * 0.17) % 1
                local r, g, b = math.abs(h * 6 - 3) - 1, 2 - math.abs(h * 6 - 2), 2 - math.abs(h * 6 - 4)
                aura:SetVertexColor(math.max(0, math.min(1, r)), math.max(0, math.min(1, g)), math.max(0, math.min(1, b)), 0.95)
                placeAt(aura, field, ball.x, ball.y)
                aura:Show()
            else
                aura:Hide()
            end
        else
            tex:Hide()
            aura:Hide()
        end
    end
    -- the phoenixes climbing out of hatched eggs
    self.phoenixTex = self.phoenixTex or {}
    local fl = st.phoenixes or {}
    for i = 1, math.max(#fl, #self.phoenixTex) do
        local t = self.phoenixTex[i]
        local f = fl[i]
        if f and not t then
            t = field:CreateTexture(nil, "OVERLAY", nil, 6)
            ART:Set(t, "phoenix")
            t:SetSize(E.PHOENIX_HALF * 2 + 16, E.PHOENIX_HALF * 2 + 16)
            self.phoenixTex[i] = t
        end
        if t then
            if f then
                placeAt(t, field, f.x, f.y)
                t:SetAlpha(0.85 + 0.15 * math.sin(now * 20))
                t:Show()
            else
                t:Hide()
            end
        end
    end
    -- the ribbon: in Fever, and behind a Rainbow Ball
    local lead = st.balls[1]
    self:UpdateTrail((lead and (st.phase == E.PHASE.FEVER or lead.item == "rainbow")) and lead or nil, now)

    -- a struck balloon squashes and springs back over a fifth of a second
    for _, b in ipairs(self.postTex) do
        if b.squashAt then
            local f = (now - b.squashAt) / 0.2
            local base = ART:Size("fever_balloon", E.FEVER_BALLOON_R * 2)
            if f >= 1 then
                b.squashAt = nil
                b:SetSize(base, base)
            else
                local k = math.sin(f * math.pi) * 0.22
                b:SetSize(base * (1 + k), base * (1 - k))
            end
            b:ClearAllPoints()
            b:SetPoint("CENTER", field, "TOPLEFT", b.x, -b.y)
        end
    end
    -- the Fever cups light as they score
    if st.phase == E.PHASE.FEVER then
        for i, bin in ipairs(self.bins) do
            local lit = st.binsLit[i] and true or false
            if bin.litShown ~= lit then
                bin.litShown = lit
                ART:Set(bin.tube, "fever_tube_" .. bin.letter .. (lit and "_lit" or ""))
            end
        end
    end

    if st.pyramidBounces > 0 and st.phase == E.PHASE.FLIGHT then
        self.pyramidTex:SetAlpha(0.55 + 0.45 * st.pyramidBounces / E.PYRAMID_BOUNCES)
        self.pyramidTex:Show()
    else
        self.pyramidTex:Hide()
    end

    if self.boltUntil then
        if now >= self.boltUntil then
            self.boltUntil = nil
            for _, d in ipairs(self.boltDots) do d:Hide() end
        else
            local f = (self.boltUntil - now) / 0.5
            for _, d in ipairs(self.boltDots) do if d:IsShown() then d:SetAlpha(f) end end
        end
    end

    if self.blastAt then
        local age = now - self.blastAt
        if age > 0.6 then
            self.blastAt = nil
            self.blastTex:Hide()
            self.blastRing:Hide()
        else
            local f = age / 0.6
            local radius = self.blastRadius or E.BLAST_RADIUS
            local size = 40 + (radius * 2.2 - 40) * math.sqrt(f)
            self.blastTex:SetSize(size, size)
            self.blastTex:SetAlpha(1 - f)
            placeAt(self.blastTex, field, self.blastX, self.blastY)
            local rs = 20 + (radius * 2) * f
            self.blastRing:SetSize(rs, rs)
            self.blastRing:SetAlpha(1 - f)
            placeAt(self.blastRing, field, self.blastX, self.blastY)
        end
    end

    if st.phase ~= E.PHASE.FEVER and st.phase ~= E.PHASE.OVER and not st.noBucket then
        self.bucket:ClearAllPoints()
        self.bucket:SetPoint("TOP", field, "TOPLEFT", st.bucket.x, -(E.BucketTop() - 22))
    end
    -- the catch splash plays its four frames over the bucket
    if self.splashAt then
        local age = now - self.splashAt
        if age > SPLASH_SECS or st.noBucket then
            self.splashAt = nil
            self.splashTex:Hide()
        else
            local idx = math.min(4, math.floor(age / SPLASH_SECS * 4) + 1)
            ART:Set(self.splashTex, "bucket_splash" .. idx)
            self.splashTex:ClearAllPoints()
            self.splashTex:SetPoint("CENTER", self.bucket, "CENTER", 0, 0)
            self.splashTex:Show()
        end
    end
end

-- ---------------------------------------------------------------------
-- Readouts

function UI:UpdateCounters()
    local st = self.state
    if not st then return end
    self.ballsText:SetText(tostring(st.ballsLeft + #st.balls))
    -- the strip of little balls still to fire (hidden during a duel's turns)
    local strip = (st.duel and st.duel.stage == 2) and 0 or st.ballsLeft
    if (self.levelPanel and self.levelPanel:IsShown()) or (self.playsPanel and self.playsPanel:IsShown()) then strip = 0 end
    for i, b in ipairs(self.ballStrip) do
        if i <= strip then b:Show() else b:Hide() end
    end
    self.ballStripMore:SetText(strip > 10 and ("+" .. (strip - 10)) or "")
    ART:Set(self.goalIcon, ART:Goal(st.objective))
    if st.boss then
        self.goalText:SetText(math.max(0, st.boss.hp) .. " / " .. st.boss.maxhp)
    else
        self.goalText:SetText(st.goalLeft .. " / " .. st.goalTotal)
    end
    if st.duel and st.duel.stage == 2 then
        self.objectiveText:SetText(("Duel: YOU %s  -  %s %s"):format(fmtBig(st.duel.scores.you), st.duel.name, fmtBig(st.duel.scores.rival)))
    end
    self:UpdateDuelHud()
    self.scoreText:SetText(fmtBig(st.score))
    self.multText:SetText("x" .. E:ScoreMultiplier(E:Progress(st)))
    self.comboText:SetText(st.combo .. " / " .. st.bestCombo)
    local nextFree = E.FREE_BALL_SCORES[st.freeBallIdx]
    self.freeBallText:SetText(nextFree and fmtBig(nextFree) or "-")
    if self.freeBallBar then
        local prev = E.FREE_BALL_SCORES[st.freeBallIdx - 1] or 0
        self.freeBallBar:SetValue(nextFree and math.max(0, math.min(1, (st.score - prev) / (nextFree - prev))) or 1)
        self.multBar:SetValue(math.max(0, math.min(1, E:Progress(st))))
    end
    local status = ""
    if st.power == "guide" and st.superGuide > 0 then
        status = "Super Guide: " .. st.superGuide .. " shot" .. (st.superGuide == 1 and "" or "s") .. " left"
    elseif st.power == "pyramid" and (st.pyramidShots > 0 or st.pyramidBounces > 0) then
        status = "Pyramid: this shot" .. (st.pyramidShots > 0 and (" and " .. st.pyramidShots .. " more") or "")
    end
    self.powerStatus:SetText(status)
    local s2, s3 = L:StarScores(st.level)
    local live = L:StarsFor(st.level, st.score, true)
    setStars(self.sideStars, live, st.phase == E.PHASE.OVER and 1 or 0.6)
    self.starNeedText:SetText(("2 stars at %s, 3 at %s"):format(fmtBig(s2), fmtBig(s3)))
end

function UI:UpdateDisplay()
    local db = GP:GetDB()
    local st = self.state
    if st then
        self.levelText:SetText(("Level %d / %d"):format(st.level, L.COUNT))
        self.chapterText:SetText("|cffaaddff" .. (st.name or "") .. "|r")
        self.layoutText:SetText(("Chapter %d  -  %s%s"):format(st.chapter, st.layout or "",
            st.gimmick and ("  +  " .. st.gimmick) or ""))
        local objective = self:ObjectiveText(st)
        if st.boss then
            local def
            for _, d in ipairs(E.BOSSES) do if d.id == st.boss.ability then def = d end end
            if def then objective = objective .. "\n" .. def.blurb end
        end
        self.objectiveText:SetText(objective)
        self.goalLabel:SetText(GOAL_LABEL[st.objective] or GOAL_LABEL.classic)
    self.chapterText:SetText("|cffaaddff" .. (st.title or st.name or "") .. "|r")
        local name, blurb = powerName(st.power)
        self.powerText:SetText("|cff88ff88" .. name .. "|r")
        self.powerBlurb:SetText(blurb)
        ART:Set(self.powerIcon, ART:Power(st.power))
        self.bestText:SetText(fmtBig(db.best[st.level] or 0))
        self:UpdateCounters()
        local over = st.phase == E.PHASE.OVER
        local cleared = over and st.result and st.result.cleared
        if cleared and st.level < L.COUNT then self.nextBtn:Show() else self.nextBtn:Hide() end
        styleButton(self.nextBtn, true, 0.2, 0.55, 0.25)
        styleButton(self.retryBtn, GP.Plays:CanPlay(), 0.35, 0.3, 0.45)
    else
        self.levelText:SetText("Gnomish Pachinko")
        self.nextBtn:Hide()
        styleButton(self.retryBtn, false, 0.35, 0.3, 0.45)
    end
    styleButton(self.levelsBtn, true, 0.35, 0.3, 0.45)
    self:UpdateItemSlots()
    local P = GP.Plays
    local free, bought = P:FreeLeft(), P:BoughtLeft()
    local plays = ("Plays left today: |cffffd700%d|r"):format(free + bought)
    if bought > 0 then plays = plays .. (" (%d bought)"):format(bought) end
    if free == 0 and bought == 0 then plays = plays .. "\n|cffff8080Next free play in " .. P:FormatWait(P:NextFreeIn()) .. "|r" end
    self.playsText:SetText(plays)
    styleButton(self.buyBtn, true, 0.5, 0.38, 0.1)
    if P:IsOwner() then
        styleButton(self.freeBtn, true, 0.2, 0.5, 0.25)
        self.freeBtn:Show()
    else
        self.freeBtn:Hide()
    end
end

function UI:Show()
    self:Initialize()
    if not self.state then
        self:StartLevel(GP:GetDB().current or 1)
    else
        self:UpdateDisplay()
    end
    self.frame:Show()
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

function UI:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end
