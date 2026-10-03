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
local EDGE, LEFT_W, GAP, SIDE_W, TOP_H = 84, 140, 16, 240, 270   -- EDGE: content keeps this far from the window's edge, past the riveted band and the brass corners
local PAD = EDGE
local PORTRAIT = 2 * (E.LAUNCH_R - 12)      -- the host's box: the launcher slides round its rim
local BARREL_W, BARREL_L = 38, 76           -- the bore is half the barrel's width: room for the ball
local TUBE_LIP = 4                           -- the Fever tubes' front lip, this far below their tops (the flare's rim in the art)
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
-- A tough piece wears what it has left: gold with three hits to go, steel
-- with two, nothing with one (a plain piece). A gold piece knocked down to
-- steel shows the crack too.
local function toughLook(hp, maxhp)
    if (maxhp or 1) <= 1 or hp <= 1 then return nil, false end
    return (hp >= 3) and RIM_HEAVY or RIM, hp < maxhp
end
-- the peg colour a kind is painted in (the per-colour art set)
local COLOR_OF = { blue = "blue", orange = "orange", green = "green", purple = "purple" }

local function fmtBig(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function powerName(id)
    if id == "guide" and GP:GetDB().crazyGuide then
        return "Crazy Guide", ("See the bounce path through %d bounces, for three shots."):format(E.GUIDE_BOUNCES.crazy)
    end
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
    -- every button wears the logo's plate (words in gold on it) unless it
    -- has a picture of its own
    local plate = not nodeSkin or nodeSkin == "btn_logo"
    if plate then nodeSkin = "btn_logo" end
    btn.nodeSkin = nodeSkin
    if plate then
        btn.skin = ART:NewPlate(btn, "BACKGROUND", h)
    else
        btn.skin = ART:NewSkin(btn, nodeSkin, "BACKGROUND", 0)
    end
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)
    if plate then
        btn.text:SetFont("Fonts\\FRIZQT__.TTF", (h >= 40) and 16 or 13, "OUTLINE")
        btn.text:SetTextColor(1, 0.86, 0.35)
    end
    btn:SetScript("OnEnter", function(self) if self:IsEnabled() then hoverButton(self, true) end end)
    btn:SetScript("OnLeave", function(self) if self:IsEnabled() then hoverButton(self, false) end end)
    -- a real press: the plate darkens and its words and icon sink a little
    -- while held, and a soft click sounds when it is let go over the button
    btn:SetScript("OnMouseDown", function(self)
        if not self:IsEnabled() or self.pressed then return end
        self.pressed = true
        ART:TintSkin(self.skin, 0.68, 0.62, 0.55, 1)
        UI.PressShift(self, 1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        if not self.pressed then return end
        self.pressed = nil
        UI.PressShift(self, -1)
        if self:IsEnabled() then
            local over = self.IsMouseOver and self:IsMouseOver()
            if over then hoverButton(self, true) else ART:TintSkin(self.skin, 1, 1, 1, self.enabledAlpha or 1) end
            if over and not self.noClickSound then GP:PlaySfx("click_soft.ogg") end
        end
    end)
    return btn
end

-- Pressed buttons: the words (and an icon) sink by PRESS_X, PRESS_Y.
UI.PRESS_X, UI.PRESS_Y = 1, -2
function UI.PressShift(btn, dir)
    for _, r in ipairs({ btn.text, btn.icon }) do
        if r and r.AdjustPointsOffset then pcall(r.AdjustPointsOffset, r, UI.PRESS_X * dir, UI.PRESS_Y * dir) end
    end
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

-- A button in the logo's style: the blank logo plate (9-slice, so its cog
-- ends keep their shape at any width) with the words in gold over it.
local function logoButton(parent, w, h, text, size)
    local b = makeButton(parent, w, h, text or "", nil)
    b.text:SetFont("Fonts\\FRIZQT__.TTF", size or 16, "OUTLINE")
    b.text:SetTextColor(1, 0.86, 0.35)
    b.logo = true
    return b
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
    if k == "bumper" then return p.balloon and "fever_balloon" or "bumper" end
    if k == "web" then return "web" end
    if k == "block" then
        if p.lock then return p.silver and "cage_silver" or "cage_gold" end
        return (p.shape == "brick") and "rail" or "block"
    end
    local color = COLOR_OF[k] or "blue"
    if p.shape == "brick" then return ART:Brick(color, state) end
    return ART:Peg(color, state)
end

UI.MakeButton, UI.PieceSlot, UI.ToughLook = makeButton, pieceSlot, toughLook

-- The star marks for the level in play: two stars, three stars, and the
-- first star's mark if the level sets one (an editor level being tested has
-- its own, not its number's).
local function starMarks(st)
    if st and st.stars then return st.stars[1], st.stars[2], st.stars[3] end
    return L:StarScores(st and st.level or 1)
end
UI.StarMarks = starMarks

-- Colorblind mode's marks: the slot for a piece's colour (blue has none).
local CB_SLOT = { orange = "cb_orange", green = "cb_green", purple = "cb_purple" }
UI.CB_SLOT = CB_SLOT

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
    if o == "mixed" then
        -- an editor level's mix of goals, each with its count
        local oranges, eggs, gems = 0, 0, 0
        for _, p in ipairs(st.pegs) do
            if p.goal then
                if p.kind == "egg" then eggs = eggs + 1 elseif p.kind == "gem" then gems = gems + 1 else oranges = oranges + 1 end
            end
        end
        local parts = {}
        if oranges > 0 then parts[#parts + 1] = ("light all %d orange pegs"):format(oranges) end
        if eggs > 0 then parts[#parts + 1] = ("hatch all %d eggs"):format(eggs) end
        if gems > 0 then parts[#parts + 1] = ("drop all %d gems"):format(gems) end
        local ls = st.longShotsLeft and (st.goalTotal - oranges - eggs - gems) or 0
        if ls > 0 then parts[#parts + 1] = ("make %d Long Shots"):format(ls) end
        local text = table.concat(parts, ", ")
        text = text:gsub(", ([^,]*)$", " and %1")
        return (text:gsub("^%l", string.upper))
    end
    local text
    if o == "boss" and st.boss then text = ("Beat the %s (%d health)"):format(st.boss.bossName or "boss", st.boss.maxhp)
    elseif o == "duel" and st.duel and st.duel.stage == 2 then text = ("Duel with %s: five balls each, turn and turn about, highest score wins. A shot that lights no orange costs a quarter of your score"):format(st.duel.name)
    elseif o == "duel" and st.duel then text = ("Stage 1: light all %d orange pegs. Then a duel with %s"):format(st.goalTotal, st.duel.name)
    else text = ("Light all %d orange pegs"):format(st.goalTotal) end
    if st.noBucket then text = text .. ". No bucket on this level" end
    return text
end

local GOAL_WORD = { classic = "word_goal_classic", eggs = "word_goal_eggs", gems = "word_goal_gems", boss = "word_goal_boss",
    duel = "word_goal_classic", longshots = "word_goal_longshots", mixed_eggs = "word_goal_mixed", mixed_gems = "word_goal_mixed", mixed = "word_goal_mixed" }
local GOAL_LABEL = { classic = "Orange pegs left", eggs = "Eggs left", gems = "Gems to drop", boss = "Boss health", duel = "Orange pegs left", longshots = "Long Shots left",
    mixed_eggs = "Goals left", mixed_gems = "Goals left", mixed = "Goals left" }

-- First-encounter tips, shown once each on the level card, in Tinkmaster's voice.
local TIPS = {
    { key = "start",     when = function(st) return st.level == 1 end, text = "Tinkmaster: \"Point with the mouse, click to shoot. Light every orange peg and the board is yours!\"" },
    { key = "bricks",    when = function(st) for _, p in ipairs(st.pegs) do if p.shape == "brick" then return true end end end, text = "Tinkmaster: \"Bricks are pegs too! Catch the inside of a curve and the ball rides it, lighting the lot.\"" },
    { key = "boss",      when = function(st) return st.objective == "boss" end, text = "Tinkmaster: \"A boss! It slides along the bottom under the pegs. Get the ball down there and keep hitting it.\"" },
    { key = "eggs",      when = function(st) return st.objective == "eggs" or st.objective == "mixed_eggs" end, text = "Tinkmaster: \"Eggs! Two hits to hatch. Handle with care: knock away the nest under one and it falls. Catch it in the bucket, or lose the level.\"" },
    { key = "gems",      when = function(st) return st.objective == "gems" or st.objective == "mixed_gems" end, text = "Tinkmaster: \"Gems! Knock them loose and drop them off the bottom. One in the bucket is a Bucket Drop bonus.\"" },
    { key = "duel",      when = function(st) return st.objective == "duel" end, text = "Tinkmaster: \"My brother Cogwhistle again. Clear the board, then it's a duel: five balls each, and hit an orange every shot or he docks your score.\"" },
    { key = "longshots", when = function(st) return st.objective == "longshots" end, text = "Tinkmaster: \"Long Shots! Light two orange pegs far apart in one shot. Bounce it off the far wall and watch.\"" },
    { key = "tough",     when = function(st) for _, p in ipairs(st.pegs) do if (p.maxhp or 1) > 1 and p.kind ~= "egg" and p.kind ~= "boss" then return true end end end, text = "Tinkmaster: \"Steel-rimmed pieces take two hits, gold-rimmed three. Each hit strips a layer: gold to steel, steel to a plain piece.\"" },
    { key = "webs",      when = function(st) return st.boss and st.boss.ability == "spider" end, text = "Tinkmaster: \"Lit oranges only charge the Gyro Spider. Strike it with the ball in the same shot and the charge hits it, or it fizzles. It spins two webs every time you light an orange. Touch one and the ball is caught, web and all. A fireball burns them away.\"" },
    { key = "nobucket",  when = function(st) return st.noBucket end, text = "Tinkmaster: \"No bucket on this one. The only free balls are the score marks, so make every ball count.\"" },
    { key = "keys",      when = function(st) for _, p in ipairs(st.pegs) do if p.kind == "key" then return true end end end, text = "Tinkmaster: \"A key! Light it and its cage falls away. Sometimes the key is behind another lock.\"" },
    { key = "items",     when = function(st) return st.level == 2 end, text = "Tinkmaster: \"The slots at the bottom-left hold the special balls: Ring of Fire, Rainbow Ball and Suction Tube. Click one to arm it for your next shot. Here's one of each to try; bosses give more.\"" },
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

    -- the author and the version, along the bottom
    local credit = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    credit:SetFont(UI.FONT, 11, "OUTLINE")
    credit:SetTextColor(0.95, 0.82, 0.5)
    credit:SetPoint("BOTTOM", frame, "BOTTOM", (LEFT_W + GAP - GAP - SIDE_W) / 2, 40)     -- centred under the board
    credit:SetText(("Gnomish Pachinko v%s  -  by %s"):format(GP:Version(), GP.AUTHOR))
    self.creditText = credit

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
        if button == "LeftButton" then UI:OnFieldClick()
        elseif button == "RightButton" then UI:StartFineAim() end
    end)
    field:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then UI:StopFineAim() end
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
    for i = 1, 110 do
        local d = field:CreateTexture(nil, "ARTWORK", nil, 1)
        d:SetSize(6, 6)
        ART:Set(d, "dot")
        d:Hide()
        self.guideDots[i] = d
    end

    -- Chain Lightning: a jagged bolt that leaps piece to piece, a bright
    -- core over a blue glow, flickering, with a flash on each piece it meets
    self.boltLines = {}
    if field.CreateLine then
        for i = 1, 72 do
            local glow = field:CreateLine(nil, "OVERLAY", nil, 3)
            glow:SetThickness(7)
            glow:SetColorTexture(0.45, 0.7, 1, 0.5)
            if glow.SetBlendMode then glow:SetBlendMode("ADD") end
            local core = field:CreateLine(nil, "OVERLAY", nil, 4)
            core:SetThickness(2.5)
            core:SetColorTexture(0.92, 0.97, 1, 1)
            glow:Hide(); core:Hide()
            self.boltLines[i] = { glow = glow, core = core }
        end
    end
    self.boltDots = {}
    for i = 1, 12 do
        local d = field:CreateTexture(nil, "OVERLAY", nil, 5)
        d:SetSize(20, 20)
        ART:Set(d, "dot", 0.75, 0.9, 1)
        if d.SetBlendMode then d:SetBlendMode("ADD") end
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

    -- the Pyramid: a step pyramid over the bucket, crumbling strike by strike
    local pyr = field:CreateTexture(nil, "ARTWORK", nil, 3)
    ART:Set(pyr, "pyramid")
    pyr:SetSize(E.PYRAMID_W, E.PYRAMID_H)
    pyr:SetPoint("BOTTOM", field, "TOPLEFT", FW / 2, -E.PYRAMID_BASE)
    pyr:Hide()
    self.pyramidTex = pyr
    -- its dust: a puff at each strike, a cloud when it falls
    self.pyramidPuffs = {}
    for i = 1, 4 do
        local d = field:CreateTexture(nil, "OVERLAY", nil, 3)
        ART:Set(d, "pyramid_dust")
        d:Hide()
        self.pyramidPuffs[i] = d
    end

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

    -- balls left: two columns of five big balls down the left column, off
    -- the board (the second column empties first)
    self.ballStrip = {}
    local BS = UI.BALL_STRIP_SIZE
    for i = 1, 10 do
        local b = frame:CreateTexture(nil, "OVERLAY", nil, 2)
        b:SetSize(BS, BS)
        ART:Set(b, "ball_small")
        local col, row = math.floor((i - 1) / 5), (i - 1) % 5
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE + (LEFT_W - 2 * BS - 6) / 2 + col * (BS + 6), -(TOP_H + 4 + row * (BS + 5)))
        b:Hide()
        self.ballStrip[i] = b
    end
    -- more than ten: one extra ball over the top of the left column, with
    -- the whole count written in it; gone again at ten or fewer
    local extra = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    extra:SetSize(BS, BS)
    ART:Set(extra, "ball_small")
    extra:SetPoint("BOTTOMLEFT", self.ballStrip[1], "TOPLEFT", 0, 5)
    extra:Hide()
    self.ballExtra = extra
    self.ballStripMore = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.ballStripMore:SetPoint("CENTER", extra, "CENTER", 0, 0)
    self.ballStripMore:SetFont("Fonts\\FRIZQT__.TTF", 22, "THICKOUTLINE")
    self.ballStripMore:SetTextColor(1, 0.95, 0.6)
    self.ballStripMore:SetText("")

    -- the boss in 3D: its creature model riding a round hover platform that
    -- slides with it. The flat face stays as the picture until the model has
    -- loaded (and for good if the client has no such model).
    local plat = field:CreateTexture(nil, "ARTWORK", nil, 0)
    ART:Set(plat, "boss_platform")
    plat:SetSize(E.BOSS_R * 3, E.BOSS_R * 3)
    plat:Hide()
    self.bossPlatform = plat
    local bm = CreateFrame("PlayerModel", nil, field)
    bm:SetSize(E.BOSS_R * 3.2, E.BOSS_R * 3.2)
    if bm.EnableMouse then bm:EnableMouse(false) end
    bm:Hide()
    bm:SetScript("OnModelLoaded", function() UI:PoseBossModel() end)
    self.bossModel = bm

    -- the boss's health bar, on a frame over the boss's model (a model
    -- frame draws over its parent's textures); no name on the board
    local barFrame = CreateFrame("Frame", nil, field)
    barFrame:SetAllPoints(field)
    if barFrame.SetFrameLevel then barFrame:SetFrameLevel((bm.GetFrameLevel and bm:GetFrameLevel() or 1) + 2) end
    self.bossBarFrame = barFrame
    local bossBg = barFrame:CreateTexture(nil, "OVERLAY", nil, 5)
    bossBg:SetSize(72, 7)
    bossBg:SetTexture(WHITE)
    bossBg:SetVertexColor(0.1, 0.1, 0.12, 0.9)
    bossBg:Hide()
    self.bossBg = bossBg
    local bossFill = barFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    bossFill:SetSize(70, 5)
    bossFill:SetTexture(WHITE)
    bossFill:SetVertexColor(0.9, 0.2, 0.2, 1)
    bossFill:Hide()
    self.bossFill = bossFill
    local bossName = field:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bossName:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    bossName:Hide()
    self.bossName = bossName
    -- the Gyro Spider's stored lightning, over its body
    local bossCharge = barFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bossCharge:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    bossCharge:SetTextColor(0.55, 0.85, 1)
    bossCharge:Hide()
    self.bossCharge = bossCharge
    -- the Bolt Golem's shield: a half dome over the top of its body, the side
    -- the ball and the bolts come from
    local bossShield = barFrame:CreateTexture(nil, "OVERLAY", nil, 4)
    ART:Set(bossShield, "boss_shield", 0.5, 0.8, 1, 1)
    bossShield:SetSize(E.BOSS_R * 2 + 24, E.BOSS_R + 12)
    bossShield:Hide()
    self.bossShield = bossShield

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
        -- the tube's flare reaches under the balloons either side, so no gap shows
        local tuck = math.floor(E.FEVER_BALLOON_R * 0.6)
        bin:SetSize(binW - 2 * E.FEVER_BALLOON_R + 2 * tuck, E.FEVER_TUBE_H + 6)
        bin:SetPoint("BOTTOM", field, "BOTTOMLEFT", (i - 0.5) * binW, 0)
        bin:SetFrameLevel(field:GetFrameLevel() + 1)
        bin.letter = (E.FEVER_LETTERS[i] or "g"):lower()
        bin.tube = bin:CreateTexture(nil, "BACKGROUND", nil, 1)
        bin.tube:SetAllPoints(bin)
        ART:Set(bin.tube, "fever_tube_" .. bin.letter)
        -- a scored tube glows: a halo behind it and a shine over its letter
        bin.halo = bin:CreateTexture(nil, "BACKGROUND", nil, 0)
        bin.halo:SetSize(bin:GetWidth() * 1.5, (E.FEVER_TUBE_H + 6) * 1.5)
        bin.halo:SetPoint("CENTER", bin, "CENTER", 0, 0)
        ART:Set(bin.halo, "glow_soft", 1, 0.85, 0.3)
        if bin.halo.SetBlendMode then bin.halo:SetBlendMode("ADD") end
        bin.halo:Hide()
        bin.shine = bin:CreateTexture(nil, "ARTWORK", nil, 1)
        bin.shine:SetSize(bin:GetWidth() * 0.8, bin:GetWidth() * 0.8)
        bin.shine:SetPoint("CENTER", bin, "CENTER", 0, -6)
        ART:Set(bin.shine, "glow_soft", 1, 0.95, 0.6)
        if bin.shine.SetBlendMode then bin.shine:SetBlendMode("ADD") end
        bin.shine:Hide()
        -- the points it pays, under the board
        bin.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bin.label:SetPoint("TOP", field, "BOTTOMLEFT", (i - 0.5) * binW, -4)
        bin.label:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        bin.label:SetText(fmtBig(pts))
        bin.label:SetTextColor(1, 0.84, 0)
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
    for i, id in ipairs({ "ring", "rainbow", "suction", "green" }) do
        local b = logoButton(frame, LEFT_W, UI.ITEM_H, "", 16)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE, -(TOP_H + UI.ITEMS_Y + (i - 1) * (UI.ITEM_H + 6)))
        b.item = id
        -- the tutorial's light: a gold glow behind the button, pulsing
        b.hl = frame:CreateTexture(nil, "BORDER")
        b.hl:SetPoint("TOPLEFT", b, "TOPLEFT", -12, 12)
        b.hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 12, -12)
        ART:Set(b.hl, "glow_soft", 1, 0.85, 0.3)
        if b.hl.SetBlendMode then b.hl:SetBlendMode("ADD") end
        b.hl:Hide()
        -- a "+n" that floats up off it when it is handed more
        b.plus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        b.plus:SetFont("Fonts\\FRIZQT__.TTF", 22, "THICKOUTLINE")
        b.plus:SetTextColor(1, 0.9, 0.3)
        b.plus:Hide()
        -- and a comically fat arrow jabbing at it from a silly angle
        local arrowFrame = CreateFrame("Frame", nil, frame)
        arrowFrame:SetAllPoints(frame)
        arrowFrame:SetFrameLevel(frame:GetFrameLevel() + 120)
        b.arrow = arrowFrame:CreateTexture(nil, "OVERLAY")
        ART:Set(b.arrow, "comic_arrow")
        b.arrow:SetSize(UI.ARROW_W, UI.ARROW_W / 2)
        b.arrow:Hide()
        b.arrowAngle = UI.ARROW_ANGLES[id] or 0.4
        buttonIcon(b, ART:Item(id), UI.ITEM_H - 8)
        b.icon:ClearAllPoints()
        b.icon:SetPoint("LEFT", b, "LEFT", 10, 0)
        b:SetScript("OnClick", function(self) UI:ToggleItem(self.item) end)
        b:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(E.ITEMS[self.item].name)
            GameTooltip:AddLine(E.ITEMS[self.item].blurb, 0.8, 0.8, 0.9, true)
            GameTooltip:AddLine(self.item == "green" and "Before a level: click to add it when you press Play. During a level: click to add a green peg now."
                or "Earned from bosses or bought with Golden Gears. Click to arm for the next shot.", 0.6, 0.6, 0.7, true)
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
    -- the settings: sound and music, each with its own box
    self.settingBoxes = {}
    local function settingBox(key, text, y, onChange, offByDefault)
        local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", y, -2)
        local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        label:SetText(text)
        cb.label = label
        cb.key = key
        local function isOn() local v = GP:GetDB()[key]; if offByDefault then return v == true end return v ~= false end
        cb:SetScript("OnShow", function(self) self:SetChecked(isOn()) end)
        cb:SetScript("OnClick", function(self)
            local on = self:GetChecked() and true or false
            GP:GetDB()[self.key] = on
            if onChange then onChange(on) end
        end)
        cb:SetChecked(isOn())
        self.settingBoxes[key] = cb
        return cb
    end
    settingBox("sound", "Sound", -4, function(on)
        if not on then
            GP:StopVoice()
            if UI.ahhHandle then UI:StopAhh(false) end
        end
    end)
    settingBox("music", "Music", 70, function(on)
        if not on then UI:StopFanfare(true)
        elseif UI.state and UI.state.phase == E.PHASE.FEVER then UI:StartFanfare(GetTime()) end
    end)
    settingBox("colorblind", "Colorblind", 140, function(on)
        if GP.Editor and GP.Editor.frame and GP.Editor.frame:IsShown() then GP.Editor:Redraw() end
    end, true)
    self.side = side
    -- the info (level, objective, host and power, balls, score, stars) lives
    -- on a frame of its own; the Golden Gear shop takes the same space when
    -- the player goes shopping
    local info = CreateFrame("Frame", nil, side)
    info:SetAllPoints(side)
    self.infoPanel = info

    local function label(text, y, template)
        local fs = info:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", side, "TOPLEFT", 6, y)
        fs:SetText(text)
        return fs
    end
    -- a heading in brass word-art (512 x 64, left-aligned), h pixels tall
    local function word(slot, x, y, h)
        local t = info:CreateTexture(nil, "ARTWORK")
        ART:Set(t, slot)
        t:SetSize(h * 8, h)
        t:SetPoint("TOPLEFT", side, "TOPLEFT", x, y)
        return t
    end
    local function value(y, template)
        local fs = info:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
        fs:SetPoint("TOPRIGHT", side, "TOPRIGHT", -6, y)
        fs:SetJustifyH("RIGHT")
        return fs
    end
    local function divider(y)
        local div = info:CreateTexture(nil, "ARTWORK")
        div:SetSize(SIDE_W, 1)
        div:SetPoint("TOPLEFT", side, "TOPLEFT", 0, y)
        div:SetTexture(WHITE)
        div:SetVertexColor(0.5, 0.4, 0.7, 0.6)
    end
    -- an inset plate behind a readout row (its pieces live on the side
    -- panel itself, under the text)
    local function plate(y, h)
        local anchor = CreateFrame("Frame", nil, info)
        anchor:SetSize(SIDE_W + 8, h)
        anchor:SetPoint("TOPLEFT", side, "TOPLEFT", -4, y)
        return ART:NewSkin(info, "plate", "BACKGROUND", 0, anchor)
    end
    local function icon(x, y, size, slot)
        local t = info:CreateTexture(nil, "ARTWORK")
        t:SetSize(size, size)
        t:SetPoint("TOPLEFT", side, "TOPLEFT", x, y)
        ART:Set(t, slot)
        return t
    end

    -- one text size for everything (the level's name aside), and the info
    -- spread over the column's height so nothing is cramped
    local function body(fs, size, color)
        fs:SetFont(UI.FONT, size or UI.TEXT_SIZE, "")
        if color then fs:SetTextColor(color[1], color[2], color[3]) end
        return fs
    end
    local function num(fs, size)
        fs:SetFont(UI.FONT, size or UI.VALUE_SIZE, "OUTLINE")
        return fs
    end
    local H = UI.HEAD_H

    self.levelText = label("", 0, "GameFontNormalLarge")
    self.levelText:SetFont(UI.FONT, 20, "OUTLINE")
    self.levelText:SetTextColor(1, 0.85, 0.2)
    self.chapterText = body(label("", -24))
    self.chapterText:SetWidth(SIDE_W)
    self.chapterText:SetJustifyH("LEFT")
    self.layoutText = body(label("", -40), nil, { 0.7, 0.65, 0.85 })
    divider(-58)

    word("word_objective", 2, -64, H)
    self.objectiveText = body(label("", -86), nil, { 0.92, 0.92, 1 })
    self.objectiveText:SetWidth(SIDE_W)
    self.objectiveText:SetJustifyH("LEFT")
    self.objectiveText:SetJustifyV("TOP")
    self.objectiveText:SetHeight(34)

    self.hostText = body(label("", -122))
    self.hostText:SetWidth(SIDE_W)
    self.hostText:SetJustifyH("LEFT")
    self.powerIcon = icon(0, -142, H, "power_multiball")
    word("word_power", 24, -142, H)
    self.powerText = num(value(-144))
    self.powerBlurb = body(label("", -164), nil, { 0.78, 0.78, 0.88 })
    self.powerBlurb:SetWidth(SIDE_W)
    self.powerBlurb:SetJustifyH("LEFT")
    self.powerBlurb:SetJustifyV("TOP")
    self.powerBlurb:SetHeight(30)
    self.powerStatus = body(label("", -196), nil, { 0.6, 1, 0.6 })

    word("word_balls", 2, -214, H)
    self.ballsText = num(value(-215), UI.VALUE_SIZE + 2)
    self.goalIcon = icon(0, -238, H, "goal_orange")
    self.goalLabel = word("word_goal_classic", 24, -238, H)
    self.goalText = num(value(-239), UI.VALUE_SIZE + 2)
    word("word_score", 2, -262, H)
    self.scoreText = num(value(-263))
    word("word_multiplier", 2, -286, H)
    self.multText = num(value(-287))
    local function bar(y, r, g, b)
        local f = CreateFrame("StatusBar", nil, info)
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
    -- the multiplier: a horizontal trough with a rainbow bar clipped by progress
    local trough = CreateFrame("Frame", nil, info)
    trough:SetSize(SIDE_W, 16)
    trough:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -308)
    local gauge = { skin = ART:NewSkin(info, "gauge", "ARTWORK", 0, trough), fill = info:CreateTexture(nil, "ARTWORK", nil, 2), w = SIDE_W - 8 }
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
    word("word_combo", 2, -330, H)
    self.comboText = num(value(-331))
    word("word_best", 2, -352, H)
    self.bestText = num(value(-353))
    word("word_next_free_ball", 2, -374, H)
    self.freeBallText = num(value(-375))
    self.freeBallBar = bar(-396, 0.4, 0.7, 1)
    word("word_stars", 2, -406, H)
    self.sideStars = makeStars(info, 18, 2)
    for i, s in ipairs(self.sideStars) do s:SetPoint("TOPRIGHT", side, "TOPRIGHT", -(3 - i) * 20, -406) end
    self.starNeedText = body(label("", -428), nil, { 0.72, 0.72, 0.85 })
    self.starNeedText:SetWidth(SIDE_W)
    self.starNeedText:SetJustifyH("LEFT")
    divider(-448)

    -- the level buttons are whole pictures: enamelled gnomish plates
    self.nextBtn = makeButton(side, SIDE_W, 30, "", "btn_next")
    self.nextBtn:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 124)
    self.nextBtn:SetScript("OnClick", function() UI:NextLevel() end)
    self.retryBtn = makeButton(side, SIDE_W, 30, "", "btn_restart")
    self.retryBtn:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 92)
    self.retryBtn:SetScript("OnClick", function() UI:Retry() end)
    self.levelsBtn = makeButton(side, SIDE_W, 30, "", "btn_levels")
    self.levelsBtn:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 60)
    self.levelsBtn:SetScript("OnClick", function() UI:ShowLevelSelect() end)

    self.playsText = label("", 0, "GameFontNormal")
    if self.playsText.SetParent then self.playsText:SetParent(side) end
    -- the plays left: a brass play token, the number in a riveted frame,
    -- and a short note beside them
    local token = side:CreateTexture(nil, "ARTWORK")
    token:SetSize(34, 34)
    token:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 2, 26)
    ART:Set(token, "play_token")
    self.playsToken = token
    local frameTex = side:CreateTexture(nil, "ARTWORK")
    frameTex:SetSize(62, 31)
    frameTex:SetPoint("LEFT", token, "RIGHT", 4, 0)
    ART:Set(frameTex, "number_frame")
    self.playsFrame = frameTex
    self.playsNum = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.playsNum:SetPoint("CENTER", frameTex, "CENTER", 0, 0)
    self.playsNum:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    self.playsNum:SetTextColor(1, 0.9, 0.5)
    local playsWord = side:CreateTexture(nil, "ARTWORK")
    ART:Set(playsWord, "word_plays_left")
    playsWord:SetSize(18 * 8, 18)
    playsWord:SetPoint("LEFT", frameTex, "RIGHT", 6, 0)
    self.playsWord = playsWord
    self.playsText:ClearAllPoints()
    self.playsText:SetPoint("LEFT", frameTex, "RIGHT", 8, 0)
    self.playsText:Hide()        -- the word says it
    self.buyBtn = makeButton(side, SIDE_W, 48, "Get Golden Gears\n1g each")   -- placed in the shop below
    self.buyBtn.text:SetWidth(SIDE_W - 16)
    self.buyBtn.text:SetWordWrap(true)
    self.buyBtn:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 28)
    self.buyBtn:SetScript("OnClick", function() UI:BuyGears() end)
    -- the Golden Gear shop
    -- the way in: a fat button at the bottom of the info
    local gearBtn = CreateFrame("Button", nil, info)
    gearBtn:SetSize(SIDE_W, 58)
    gearBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -456)
    gearBtn.tex = gearBtn:CreateTexture(nil, "ARTWORK")
    gearBtn.tex:SetSize(56, 56)
    gearBtn.tex:SetPoint("LEFT", gearBtn, "LEFT", 4, 0)
    -- the header that says what it is
    gearBtn.word = gearBtn:CreateTexture(nil, "ARTWORK")
    ART:Set(gearBtn.word, "word_shop")
    gearBtn.word:SetSize(172, 172 / 8)
    gearBtn.word:SetPoint("LEFT", gearBtn.tex, "RIGHT", 6, 0)
    ART:Set(gearBtn.tex, "shop_gear")
    gearBtn.glow = gearBtn:CreateTexture(nil, "BACKGROUND")
    gearBtn.glow:SetSize(88, 88)
    gearBtn.glow:SetPoint("CENTER", gearBtn.tex, "CENTER", 0, 0)
    ART:Set(gearBtn.glow, "glow_soft", 1, 0.85, 0.3)
    if gearBtn.glow.SetBlendMode then gearBtn.glow:SetBlendMode("ADD") end
    gearBtn.glow:SetAlpha(0.35)
    gearBtn:SetScript("OnEnter", function(self)
        self.hover = true
        self.glow:SetAlpha(0.8)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Golden Gear Shop")
            GameTooltip:AddLine("Special balls, Extra Green Pegs and plays, for Golden Gears.", 0.8, 0.8, 0.9, true)
            GameTooltip:Show()
        end
    end)
    gearBtn:SetScript("OnLeave", function(self)
        self.hover = nil
        self.glow:SetAlpha(0.35)
        if self.tex.SetRotation then self.tex:SetRotation(0) end
        if GameTooltip then GameTooltip:Hide() end
    end)
    -- it turns while the mouse is on it
    gearBtn:SetScript("OnUpdate", function(self, elapsed)
        if self.hover and self.tex.SetRotation then
            self.angle = ((self.angle or 0) - elapsed * 1.5) % (2 * math.pi)
            self.tex:SetRotation(self.angle)
        end
    end)
    gearBtn:SetScript("OnClick", function() UI:ShowShop(true) end)
    self.shopOpenBtn = gearBtn
    -- the Golden Gear shop, in the info's place
    local shop = CreateFrame("Frame", nil, side)
    shop:SetAllPoints(side)
    shop:Hide()
    self.shopPanel = shop
    local shopTitle = shop:CreateTexture(nil, "ARTWORK")
    ART:Set(shopTitle, "word_shop")
    shopTitle:SetSize(SIDE_W, SIDE_W / 8)
    shopTitle:SetPoint("TOP", side, "TOP", 0, 0)
    self.gearsText = shop:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    self.gearsText:SetPoint("TOP", side, "TOP", 0, -30)
    self.gearsText:SetWidth(SIDE_W)
    self.gearsText:SetJustifyH("CENTER")
    self.shopBtns = {}
    for i, what in ipairs(GP.Plays.SHOP_ORDER) do
        local offer = GP.Plays.SHOP[what]
        local b = makeButton(shop, SIDE_W, 40, ("%s  -  %d gear%s"):format(offer.label, offer.cost, offer.cost == 1 and "" or "s"))
        b:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -62 - (i - 1) * 48)
        b.what = what
        b:SetScript("OnClick", function(self) UI:ShopBuy(self.what) end)
        self.shopBtns[i] = b
    end
    -- the way to get gears, in the shop
    if self.buyBtn.SetParent then self.buyBtn:SetParent(shop) end
    self.buyBtn:ClearAllPoints()
    self.buyBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -62 - #GP.Plays.SHOP_ORDER * 48 - 4)
    self.shopLeaveBtn = makeButton(shop, SIDE_W, 40, "Leave shop")
    self.shopLeaveBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -464)
    self.shopLeaveBtn:SetScript("OnClick", function() UI:ShowShop(false) end)
    self.shopLeaveBtn.noClickSound = true      -- ShowShop clicks
    -- the owner's characters top up for free (in the shop, under the mail button)
    self.freeBtn = makeButton(self.shopPanel, SIDE_W, 24, "Owner: +" .. GP.Plays.OWNER_GEARS .. " Golden Gears")
    self.freeBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -62 - #GP.Plays.SHOP_ORDER * 48 - 56)
    self.freeBtn:SetScript("OnClick", function() UI:ClaimFreePlays() end)
    self.freeBtn:Hide()


    frame:SetScript("OnUpdate", function(_, dt) UI:OnUpdate(dt) end)
    frame:SetScript("OnShow", function() UI.lastHitSound = 0 end)

    self:CreateLevelSelect()
    self:CreatePlaysPanel()
    self:CreateCard()
    self:CreateTestFlyout(frame)
    -- the talk box over everything, the cards (and their big stars) included
    if GP.Dialog then GP.Dialog:Create(frame, view, field:GetFrameLevel() + UI.CARD_LEVEL + 30) end
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
    -- the host, clipped to the ring's round window however far he is zoomed:
    -- a model clips only to rectangles, so the circle is built from strips,
    -- each as wide as the circle at its inner edge (the ring's band covers
    -- the steps), each with its own copy of the model
    local innerR = math.floor(PORTRAIT / 2 * 0.8)
    local clipR = (UI.PORTRAIT_STRIPS == 1) and (math.floor(PORTRAIT / 2 / math.sqrt(2)) - 1) or (innerR + 3)
    local strips = {}
    local N = UI.PORTRAIT_STRIPS
    local hStrip = 2 * clipR / N
    for k = 1, N do
        local top = clipR - (k - 1) * hStrip
        local bottom = top - hStrip
        local near = (top > 0 and bottom < 0) and 0 or math.min(math.abs(top), math.abs(bottom))
        local half = math.sqrt(math.max(0, clipR * clipR - near * near))
        local clip = CreateFrame("Frame", nil, box)
        clip:SetSize(2 * half, hStrip + 0.5)
        clip:SetPoint("CENTER", box, "CENTER", 0, (top + bottom) / 2)
        if clip.SetClipsChildren then pcall(clip.SetClipsChildren, clip, true) end
        strips[k] = clip
    end
    self.portraitClips = strips
    if GP.Mascot then GP.Mascot:Create(strips[1], box, PORTRAIT - 16, PORTRAIT - 16, strips) end
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
    card:SetSize(UI.CARD_W, UI.CARD_H)
    card:SetPoint("CENTER", self.view, "CENTER", 0, 10)
    card:SetFrameLevel(self.field:GetFrameLevel() + UI.CARD_LEVEL)
    card.skin = ART:NewSkin(card, "card", "BACKGROUND", 0)
    card:EnableMouse(true)
    card:Hide()
    self.card = card
    -- a see-through sheet behind it eats clicks on the field
    local sheet = CreateFrame("Frame", nil, self.frame)
    sheet:SetSize(FW, FH)
    sheet:SetPoint("TOPLEFT", self.view, "TOPLEFT", 0, 0)
    sheet:SetFrameLevel(self.field:GetFrameLevel() + UI.CARD_LEVEL - 1)
    sheet:EnableMouse(true)
    sheet:Hide()
    self.cardSheet = sheet

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.title:SetPoint("TOP", 0, -46)
    card.title:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
    card.title:SetWidth(UI.CARD_W - 60)
    -- three big stars; on the result card each fills with gold from left
    -- to right as the score counts up past its mark
    card.stars = makeStars(card, UI.CARD_STAR, 4)
    for i, s in ipairs(card.stars) do
        -- spread out, each with the score it takes written under it
        s:SetPoint("TOP", card, "TOP", (i - 2) * UI.CARD_STAR_GAP, -84)
        local sub = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sub:SetPoint("TOP", s, "BOTTOM", 0, -2)
        sub:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        sub:SetTextColor(1, 0.85, 0.3)
        s.sub = sub
        local f = card:CreateTexture(nil, "OVERLAY", nil, 2)
        ART:Set(f, "star", 1, 0.85, 0.2)
        f:SetPoint("LEFT", s, "LEFT", 0, 0)
        f:SetSize(UI.CARD_STAR, UI.CARD_STAR)
        f:Hide()
        s.fill = f
    end
    -- the result card: three big stars across the whole card, over even its
    -- border, the middle one bigger and higher; the score big beneath them
    local sf = CreateFrame("Frame", nil, card)
    sf:SetAllPoints(card)
    sf:SetFrameLevel(card:GetFrameLevel() + 12)
    sf:Hide()
    card.starFrame = sf
    card.bigStars = {}
    for i, spec in ipairs(UI.BIG_STARS) do
        local base = sf:CreateTexture(nil, "ARTWORK", nil, spec.layer)
        base:SetSize(spec.size, spec.size)
        base:SetPoint("CENTER", card, "TOP", spec.x, spec.y)
        ART:Set(base, spec.slot .. "_empty")
        local fill = sf:CreateTexture(nil, "ARTWORK", nil, spec.layer + 1)
        fill:SetPoint("LEFT", base, "LEFT", 0, 0)
        fill:SetSize(spec.size, spec.size)
        ART:Set(fill, spec.slot)
        fill:Hide()
        -- a burst of light behind it when it pops
        local glow = sf:CreateTexture(nil, "ARTWORK", nil, spec.layer - 1)
        glow:SetPoint("CENTER", base, "CENTER", 0, 0)
        glow:SetSize(spec.size * 1.6, spec.size * 1.6)
        ART:Set(glow, "glow_soft", 1, 0.9, 0.45)
        if glow.SetBlendMode then glow:SetBlendMode("ADD") end
        glow:Hide()
        card.bigStars[i] = { base = base, fill = fill, glow = glow, size = spec.size, x = spec.x, y = spec.y }
    end
    card.sparks = {}
    for i = 1, UI.STAR_ROCKETS do
        local t = sf:CreateTexture(nil, "OVERLAY", nil, 6)
        ART:Set(t, "star", 1, 0.9, 0.35)
        if t.SetBlendMode then t:SetBlendMode("ADD") end
        t:Hide()
        card.sparks[i] = t
    end
    card.bigScore = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    card.bigScore:SetPoint("TOP", card, "TOP", 0, UI.BIG_SCORE_Y)
    card.bigScore:SetFont("Fonts\\FRIZQT__.TTF", 40, "THICKOUTLINE")
    card.bigScore:SetTextColor(1, 0.96, 0.74)
    card.line1 = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.line1:SetPoint("TOP", 22, -144)
    card.line1:SetWidth(UI.CARD_W - 110)
    card.line1:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    card.goalIcon = card:CreateTexture(nil, "ARTWORK")
    card.goalIcon:SetSize(44, 44)
    card.goalIcon:SetPoint("RIGHT", card.line1, "LEFT", -6, 0)
    ART:Set(card.goalIcon, "goal_orange")
    card.goalIcon:Hide()
    card.line2 = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.line2:SetPoint("TOP", card.line1, "BOTTOM", -22, -10)
    card.line2:SetWidth(UI.CARD_W - 60)
    card.line2:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
    -- the best score on this level, big
    card.best = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.best:SetPoint("TOP", card.line2, "BOTTOM", 0, -10)
    card.best:SetWidth(UI.CARD_W - 60)
    card.best:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    card.line3 = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.line3:SetPoint("TOP", card.best, "BOTTOM", 0, -10)
    card.line3:SetWidth(UI.CARD_W - 60)
    card.line3:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    card.line3:SetTextColor(0.8, 0.8, 0.9)
    -- the master selector: any power unlocked so far, with its icon and what it does
    card.powerPrev = logoButton(card, 74, 46, "<", 24)
    card.powerPrev:SetPoint("TOPLEFT", card, "TOPLEFT", 30, -UI.CARD_POWER_Y)
    card.powerNext = logoButton(card, 74, 46, ">", 24)
    card.powerNext:SetPoint("TOPRIGHT", card, "TOPRIGHT", -30, -UI.CARD_POWER_Y)
    card.powerIcon = card:CreateTexture(nil, "ARTWORK")
    card.powerIcon:SetSize(44, 44)
    card.powerIcon:SetPoint("TOPLEFT", card, "TOPLEFT", 112, -UI.CARD_POWER_Y)
    ART:Set(card.powerIcon, "power_multiball")
    card.powerText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.powerText:SetPoint("TOPLEFT", card.powerIcon, "TOPRIGHT", 8, -2)
    card.powerText:SetPoint("RIGHT", card.powerNext, "LEFT", -6, 0)
    card.powerText:SetJustifyH("LEFT")
    card.powerText:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")
    card.powerBlurb = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.powerBlurb:SetPoint("TOPLEFT", card.powerPrev, "BOTTOMLEFT", 0, -8)
    card.powerBlurb:SetPoint("TOPRIGHT", card.powerNext, "BOTTOMRIGHT", 0, -8)
    card.powerBlurb:SetJustifyH("CENTER")
    card.powerBlurb:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    card.powerBlurb:SetTextColor(0.85, 0.85, 0.95)
    card.powerPrev:SetScript("OnClick", function() UI:CyclePower(-1) end)
    card.powerNext:SetScript("OnClick", function() UI:CyclePower(1) end)
    -- the Extra Green Peg lives in the left column now; a stand-in keeps old calls safe
    card.boost = CreateFrame("Frame", nil, card)
    card.boost:Hide()
    card.main = logoButton(card, 260, 58, "PLAY", 26)
    card.main:SetPoint("BOTTOM", 0, 92)
    card.left = logoButton(card, 180, 46, "Map", 18)
    card.left:SetPoint("BOTTOMLEFT", 30, 34)
    card.right = logoButton(card, 180, 46, "Retry", 18)
    card.right:SetPoint("BOTTOMRIGHT", -30, 34)
end

function UI:HideCard()
    self.startCardUp = nil
    -- everything the card set playing stops with it, the host's line too
    if self.card and self.card:IsShown() then
        self:StopCardSounds()
        GP:StopVoice()
    end
    if self.UpdateItemSlots then self:UpdateItemSlots() end
    self.card:Hide()
    self.cardSheet:Hide()
    self.card.fillAnim = nil
    if self.rampHandle and type(StopSound) == "function" then pcall(StopSound, self.rampHandle, 0) end
    self.rampHandle = nil
    self.cardAt = nil
end

-- Before the level: the player presses Play.
function UI:ShowStartCard()
    local st = self.state
    local card = self.card
    card.title:SetText(("|cffffd700%d. %s|r"):format(st.level, st.title or ""))
    card.fillAnim = nil
    self:CardLayout("start")
    for _, s in ipairs(card.stars) do s.fill:Hide() end
    setStars(card.stars, GP:GetDB().stars[st.level] or 0)
    -- the goal, big and gold, with its icon: most players never read small print
    card.line1:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    card.line1:SetTextColor(1, 0.85, 0.25)
    card.line1:SetText(self:ObjectiveText(st))
    ART:Set(card.goalIcon, ART:Goal(st.objective))
    -- the text centred on the card; its icon just before where the text starts
    local tw = math.min(card.line1:GetStringWidth() or 0, card.line1:GetWidth() or 0)
    card.goalIcon:ClearAllPoints()
    card.goalIcon:SetPoint("RIGHT", card.line1, "CENTER", -tw / 2 - 6, 0)
    card.goalIcon:Show()
    -- what each star takes, under it (the first comes with clearing unless the level sets a score)
    local s2, s3, s1 = starMarks(st)
    card.stars[1].sub:SetText(s1 and fmtBig(s1) or "Clear")
    card.stars[2].sub:SetText(fmtBig(s2))
    card.stars[3].sub:SetText(fmtBig(s3))
    card.line2:SetText("")
    local extra = {}
    if st.author then extra[#extra + 1] = "|cff88ddffLevel by " .. st.author .. "|r" end
    if st.gimmick then extra[#extra + 1] = st.gimmick end
    local best = GP:GetDB().best[st.level]
    card.best:SetText(best and ("Best score  |cffffd700%s|r"):format(fmtBig(best)) or "|cff9999aaNo score yet|r")
    card.best:Show()
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
    card.left:SetPoint("BOTTOM", card, "BOTTOM", 0, 34)       -- alone: centred
    self.greenBoost = false
    self.startCardUp = true
    self:RefreshCardChoices()
    card.powerPrev:Show(); card.powerNext:Show(); card.powerText:Show(); card.powerIcon:Show(); card.powerBlurb:Show()
    self.cardSheet:Show()
    card:Show()
end

function UI:RefreshCardChoices()
    local st, card = self.state, self.card
    local name, blurb = powerName(st.power)
    card.powerText:SetText(("%s's power\n|cff88ff88%s|r"):format(GP:HostFor(st.level).name:match("(%S+)$") or "", name))
    card.powerBlurb:SetText(blurb or "")
    ART:Set(card.powerIcon, ART:Power(st.power))
    local many = #GP:UnlockedPowers(st.level) > 1
    styleButton(card.powerPrev, many, 0.3, 0.3, 0.45)
    styleButton(card.powerNext, many, 0.3, 0.3, 0.45)
    self:UpdateItemSlots()
end

function UI:CyclePower(dir)
    local st = self.state
    local list = GP:UnlockedPowers(st.level)
    if #list < 2 then return end
    local idx = 1
    for i, id in ipairs(list) do if id == st.power then idx = i end end
    idx = ((idx - 1 + dir) % #list) + 1
    st.power = list[idx]
    GP:GetDB().lastPower = st.power
    self:RefreshCardChoices()
    self:UpdateDisplay()
end

-- The Extra Green Peg from the left column: only before a level, while
-- the level card is up, where it is the boost added when Play is pressed.
-- Once the level has started its button stands greyed out.
function UI:GreenPegOpen()
    local st = self.state
    return st and self.startCardUp and st.phase == E.PHASE.AIM and (st.shots or 0) == 0
end

function UI:UseGreenPeg()
    if self:GreenPegOpen() then return self:ToggleGreenBoost() end
end

function UI:ToggleGreenBoost()
    if not self.greenBoost and GP:ItemCount("green") <= 0 then return end
    self.greenBoost = not self.greenBoost
    self:RefreshCardChoices()
end

function UI:PlayFromCard()
    local st = self.state
    if self.cardTip then GP:GetDB().tips[self.cardTip] = true; self.cardTip = nil end
    if self.greenBoost and not self.duelOnly and not self.customTest and GP:SpendItem("green") then
        local p = E:AddGreen(st)
        if p then
            self:LayoutPegs()
            self:Popup(p.x, p.y - 16, "EXTRA GREEN", 0.6, 1, 0.6)
        end
    end
    self.greenBoost = false
    self:HideCard()
    self:ShowBoardContents()
    GP:PlaySfx("start.ogg")
    local carry = self.duelOnly
    if carry then
        -- a duel retry: the cleared board's score carries over, as it did
        self.duelOnly = nil
        st.score, st.freeBallIdx, st.bestCombo = carry.score, carry.freeBallIdx, carry.bestCombo
        self:BeginDuel(GetTime())
    end
    self:UpdateDisplay()
end

-- While a tutorial is spoken the board is still empty, so a sample of the
-- piece it is about is put up on its own, big, in the middle above the talk
-- box: a soft glow behind it and the goofy arrow jabbing and wobbling at it.
-- It is only there for the talk: gone before the level card shows.
UI.SHOWCASE_X = E.FIELD_W / 2
UI.SHOWCASE_Y = 205          -- above the talk box (field pixels from the top)
UI.SHOWCASE_PEG = 64         -- a round piece's sample is drawn this big
UI.SHOWCASE_BRICK = 1.6      -- a brick's sample, this many times its size
UI.SHOWCASE_ANGLE = 0.62         -- the arrow comes in from the upper right (from the upper left near the right wall)
UI.SHOWCASE_DIST = 82
function UI:ShowShowcase(piece)
    if not self.showcase then
        local f = CreateFrame("Frame", nil, self.frame)
        f:SetAllPoints(self.field)
        f:SetFrameLevel(self.field:GetFrameLevel() + UI.CARD_LEVEL + 60)    -- over the talk box
        f.glow = f:CreateTexture(nil, "BACKGROUND")
        ART:Set(f.glow, "glow_soft", 1, 0.9, 0.5)
        if f.glow.SetBlendMode then f.glow:SetBlendMode("ADD") end
        f.piece = f:CreateTexture(nil, "ARTWORK")
        f.arrow = f:CreateTexture(nil, "OVERLAY")
        ART:Set(f.arrow, "comic_arrow")
        f:Hide()
        self.showcase = f
    end
    local f = self.showcase
    -- an ordinary showcase: no tough-piece demo samples
    f.demoN = nil
    f.arrow:Show()
    for _, d in ipairs(f.demoTex or {}) do d.rim:Hide(); d.disc:Hide(); d.crack:Hide(); d.ball:Hide(); if d.bird then d.bird:Hide() end end
    f.piece:Show()
    local slot = pieceSlot(piece, "")
    ART:Set(f.piece, slot)
    if piece.shape == "brick" then
        local w, h = piece.w * self.SHOWCASE_BRICK, piece.h * self.SHOWCASE_BRICK
        f.piece:SetSize(ART:Size(slot, w, h))
        if f.piece.SetRotation then f.piece:SetRotation(0) end      -- shown level, a sample
        f.size = w
    else
        f.piece:SetSize(ART:Size(slot, self.SHOWCASE_PEG))
        if f.piece.SetRotation then f.piece:SetRotation(0) end
        f.size = self.SHOWCASE_PEG
    end
    f.piece:ClearAllPoints()
    f.piece:SetPoint("CENTER", self.field, "TOPLEFT", self.SHOWCASE_X, -self.SHOWCASE_Y)
    f.glow:SetSize(f.size * 3 + 30, f.size * 3 + 30)
    f.glow:ClearAllPoints()
    f.glow:SetPoint("CENTER", f.piece, "CENTER", 0, 0)
    f.x, f.y = self.SHOWCASE_X, self.SHOWCASE_Y
    f.side = 1
    f.startAt = GetTime()
    -- a moving piece is shown moving the way its gimmick moves it
    f.mover = nil
    for _, mv in ipairs((self.state and self.state.movers) or {}) do
        for _, q in ipairs(mv.pegs) do if q == piece then f.mover = mv end end
    end
    f:Show()
end

-- The showcased piece's motion, in showcase pixels: lifts bob, sliders
-- glide, wheels circle, pendulums swing. Returns the offset and the turn.
UI.SHOWCASE_SWAY = 34
function UI:ShowcaseMotion(f, t)
    local mv = f.mover
    if not mv then return 0, 0, 0 end
    local sp = math.max(1.6, math.abs(mv.speed or 1))
    local A = self.SHOWCASE_SWAY
    if mv.kind == "lift" then return 0, A * math.sin(sp * t), 0 end
    if mv.kind == "slide" then return A * math.sin(sp * t), 0, 0 end
    local th
    if mv.kind == "wheel" then th = sp * t * ((mv.speed or 1) < 0 and -1 or 1)
    else th = 0.9 * math.sin(sp * t) end
    -- round a centre just above the piece, as on a wheel's rim or a pendulum's bob
    return A * math.sin(th), A - A * math.cos(th), th
end

function UI:HideShowcase()
    if self.showcase then self.showcase:Hide() end
end

-- The tough pieces' tutorial: sample blue pegs, one per entry of `hits`
-- (2 = steel rim, 3 = gold rim), side by side where the showcase sits. A
-- ball bounces on each again and again: every hit but the last cracks it
-- further, the last lights it, and after a beat it starts over.
-- With hits.kind == "egg" the sample is a phoenix egg: it cracks, hatches
-- on the last hit, and the phoenix rises out of it and away.
UI.DEMO_GAP = 96          -- between the sample pegs
UI.DEMO_HIT_EVERY = 0.85  -- seconds between bounces
UI.DEMO_REST = 1.3        -- lit, before it starts over
UI.DEMO_EGG_REST = 1.8    -- an egg's: the phoenix's climb
function UI:ShowToughDemo(hits)
    self:ShowShowcase({ kind = "blue", shape = "peg", r = E.PEG_R, x = self.SHOWCASE_X, y = self.SHOWCASE_Y })
    local f = self.showcase
    f.piece:Hide()
    f.demoTex = f.demoTex or {}
    local n = #hits
    local egg = hits.kind == "egg"
    f.demoEgg = egg
    -- a demo needs no arrow: it is all there is to look at
    f.arrow:Hide()
    local size = self.SHOWCASE_PEG * (egg and 1.3 or 1)
    f.demoSize = size
    for i, h in ipairs(hits) do
        local d = f.demoTex[i]
        if not d then
            d = {}
            d.rim = f:CreateTexture(nil, "ARTWORK", nil, 0)
            d.disc = f:CreateTexture(nil, "ARTWORK", nil, 1)
            d.crack = f:CreateTexture(nil, "ARTWORK", nil, 2)
            d.ball = f:CreateTexture(nil, "OVERLAY", nil, 1)
            ART:Set(d.rim, "rim", 1, 1, 1)
            ART:Set(d.crack, "crack")
            ART:Set(d.ball, "ball")
            d.bird = f:CreateTexture(nil, "OVERLAY", nil, 2)
            ART:Set(d.bird, "phoenix")
            f.demoTex[i] = d
        end
        d.bird:SetSize(size * 1.6, size * 1.6)
        d.bird:Hide()
        d.hits = h
        d.x = self.SHOWCASE_X + (i - (n + 1) / 2) * self.DEMO_GAP
        d.y = self.SHOWCASE_Y
        local c = (h >= 3) and RIM_HEAVY or RIM
        d.rimColor = c
        d.rim:SetVertexColor(c[1], c[2], c[3], 1)
        d.rim:SetSize(size + 14, size + 14)
        d.crack:SetSize(size, size)
        d.ball:SetSize(size * 0.45, size * 0.45)
        for _, tex in ipairs({ d.rim, d.disc, d.crack }) do
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", self.field, "TOPLEFT", d.x, -d.y)
        end
        d.state = nil
        d.rim:SetShown(not egg); d.disc:Show(); d.crack:Hide(); d.ball:Hide()
    end
    for i = n + 1, #f.demoTex do
        local d = f.demoTex[i]
        d.rim:Hide(); d.disc:Hide(); d.crack:Hide(); d.ball:Hide(); d.bird:Hide()
    end
    f.demoN = n
    -- the arrow and the glow on the first sample
    local first = f.demoTex[1]
    f.x, f.y = first.x, first.y
    f.glow:ClearAllPoints()
    f.glow:SetPoint("CENTER", self.field, "TOPLEFT", (f.demoTex[1].x + f.demoTex[n].x) / 2, -first.y)
    f.glow:SetSize(n * self.DEMO_GAP + size * 2, size * 3)
    self:AnimateToughDemo(GetTime())
end

-- One frame of the demo: hp, cracks, the lit peg, the ball's bounce arc.
function UI:AnimateToughDemo(now)
    local f = self.showcase
    if not (f and f.demoN) then return end
    local t = now - (f.startAt or now)
    local size = f.demoSize or self.SHOWCASE_PEG
    local egg = f.demoEgg
    local rest = egg and self.DEMO_EGG_REST or self.DEMO_REST
    for i = 1, f.demoN do
        local d = f.demoTex[i]
        local cycle = d.hits * self.DEMO_HIT_EVERY + rest
        -- each sample a little behind the one before, so they never bounce in step
        local u = (t + (i - 1) * 0.4) % cycle
        local done = math.floor((u + self.DEMO_HIT_EVERY / 2) / self.DEMO_HIT_EVERY)    -- hits landed so far
        if done > d.hits then done = d.hits end
        local hp = d.hits - done
        local state = (hp <= 0) and "lit" or hp
        if d.state ~= state and egg then
            d.state = state
            ART:Set(d.disc, (hp <= 0) and "egg_hatched" or ((hp < d.hits) and "egg_cracked" or "egg"))
            d.disc:SetSize(ART:Size(d.disc.slot, size))
            d.disc:SetAlpha(1)
            -- a three-hit egg shows its second crack with the crack lines
            if hp > 0 and hp <= 1 and d.hits >= 3 then d.crack:SetAlpha(0.9); d.crack:Show() else d.crack:Hide() end
        elseif d.state ~= state then
            d.state = state
            ART:Set(d.disc, ART:Peg("blue", hp <= 0 and "_lit" or ""))
            d.disc:SetSize(ART:Size(d.disc.slot, size))
            -- each hit sheds a layer: gold to steel (cracked), steel to plain
            local rimColor, cracked = toughLook(hp, d.hits)
            if rimColor then
                d.rim:SetVertexColor(rimColor[1], rimColor[2], rimColor[3], 1)
                d.rim:Show()
            else
                d.rim:Hide()
            end
            d.crack:SetAlpha(0.8)
            d.crack:SetShown(hp > 0 and cracked)
        end
        -- the ball: an arc down onto the peg's top and back up, for each hit
        local k = u / self.DEMO_HIT_EVERY - 0.5     -- hit j lands at k = j - 1
        local j = math.floor(k + 0.5)
        local w = k - j                              -- -0.5 .. 0.5 around a landing
        if j >= 0 and j < d.hits then
            local x = d.x + w * 30
            local y = d.y - size * 0.5 - size * 0.22 - 70 * (4 * w * w)
            d.ball:ClearAllPoints()
            d.ball:SetPoint("CENTER", self.field, "TOPLEFT", x, -y)
            d.ball:Show()
            -- a squash on the peg as the ball lands
            local s = 1 + 0.18 * math.max(0, 1 - math.abs(w) * 8)
            d.disc:SetSize(ART:Size(d.disc.slot, size * s))
        else
            d.ball:Hide()
        end
        -- hatched: the shell fades and the phoenix climbs out and away
        if egg and hp <= 0 then
            local a = (u - (d.hits - 0.5) * self.DEMO_HIT_EVERY) / rest     -- 0 .. 1 since the hatch
            if a < 0 then a = 0 elseif a > 1 then a = 1 end
            d.disc:SetAlpha(1 - a)
            d.bird:ClearAllPoints()
            d.bird:SetPoint("CENTER", self.field, "TOPLEFT", d.x + 6 * math.sin(a * 18), -(d.y - 10 - a * 190))
            d.bird:SetAlpha(a < 0.7 and 1 or (1 - (a - 0.7) / 0.3))
            d.bird:Show()
        else
            d.bird:Hide()
        end
    end
end

function UI:AnimateShowcase(now)
    local f = self.showcase
    if not (f and f:IsShown()) then return end
    local t = now - (f.startAt or now)
    if f.mover then
        local ox, oy, th = self:ShowcaseMotion(f, t)
        f.x, f.y = self.SHOWCASE_X + ox, self.SHOWCASE_Y + oy
        f.piece:ClearAllPoints()
        f.piece:SetPoint("CENTER", self.field, "TOPLEFT", f.x, -f.y)
        if f.piece.SetRotation and f.mover.kind ~= "lift" and f.mover.kind ~= "slide" then f.piece:SetRotation(-th) end
    end
    -- the arrow: in from a slant, jabbing in and out, wobbling, squashing
    local base = (f.side > 0) and self.SHOWCASE_ANGLE or (math.pi - self.SHOWCASE_ANGLE)
    local ang = base + 0.16 * math.sin(t * 5)
    local d = self.SHOWCASE_DIST + f.size * 0.4 + 18 * math.sin(t * 9)
    local ax, ay = f.x + math.cos(ang) * d, f.y - math.sin(ang) * d
    f.arrow:ClearAllPoints()
    f.arrow:SetPoint("CENTER", self.field, "TOPLEFT", ax, -ay)
    if f.arrow.SetRotation then f.arrow:SetRotation(ang + math.pi) end
    local k = 1 + 0.1 * math.sin(t * 9 + 1.2)
    f.arrow:SetSize(self.ARROW_W * k, self.ARROW_W / 2 / k)
    f.glow:SetAlpha(0.55 + 0.35 * math.sin(t * 4))
    if f.demoN then self:AnimateToughDemo(now) end
end

-- The Super Slide tutorial's arrow: the fat cartoon arrow, still, pointing
-- along the spiral's mouth into the inside face of its lead brick, the way
-- a ball should come in to catch the rail. Gone with the first shot.
UI.SPIRAL_ARROW_W = 96
UI.SPIRAL_ARROW_TILT = 0.35      -- how far the way in leans into the brick
function UI:ShowSpiralHint()
    local st = self.state
    if not st then return end
    local list = {}
    for _, p in ipairs(st.pegs) do if p.rail == "spiral" and not p.gone then list[#list + 1] = p end end
    table.sort(list, function(a, b) return (a.railIdx or 0) < (b.railIdx or 0) end)
    local b1, b2 = list[1], list[2]
    if not (b1 and b2) then return end
    -- along the rail, and the inner face's normal (toward the spiral's middle)
    local dx, dy = b2.x - b1.x, b2.y - b1.y
    local L = math.sqrt(dx * dx + dy * dy)
    if L < 0.001 then return end
    dx, dy = dx / L, dy / L
    local nx, ny = -dy, dx
    if ((b1.railCx or b1.x) - b1.x) * nx + ((b1.railCy or b1.y) - b1.y) * ny < 0 then nx, ny = -nx, -ny end
    -- the spot on the inside face, and the way in, leaning into the brick
    local tx, ty = b1.x + nx * (E.BRICK_H / 2 + 4), b1.y + ny * (E.BRICK_H / 2 + 4)
    local wx, wy = dx - nx * self.SPIRAL_ARROW_TILT, dy - ny * self.SPIRAL_ARROW_TILT
    local wl = math.sqrt(wx * wx + wy * wy)
    wx, wy = wx / wl, wy / wl
    if not self.spiralArrow then
        local f = CreateFrame("Frame", nil, self.field)
        f:SetAllPoints(self.field)
        f:SetFrameLevel(self.field:GetFrameLevel() + 20)
        self.spiralArrow = f:CreateTexture(nil, "OVERLAY")
        ART:Set(self.spiralArrow, "comic_arrow")
        self.spiralArrow:SetSize(self.SPIRAL_ARROW_W, self.SPIRAL_ARROW_W / 2)
    end
    local a = self.spiralArrow
    local back = self.SPIRAL_ARROW_W / 2 + 6
    a:ClearAllPoints()
    a:SetPoint("CENTER", self.field, "TOPLEFT", tx - wx * back, -(ty - wy * back))
    if a.SetRotation then a:SetRotation(math.atan2 and math.atan2(-wy, wx) or math.atan(-wy, wx)) end
    a.target = { x = tx, y = ty }
    a.piece = nil
    a.dir = { x = wx, y = wy }
    a.back = back
    a:Show()
end

-- A tutorial's arrow on a piece: in from above at a slant (from the side
-- away from the nearer wall), pointing at it and following it if it moves.
function UI:ShowPieceHint(piece)
    if not self.spiralArrow then
        local f = CreateFrame("Frame", nil, self.field)
        f:SetAllPoints(self.field)
        f:SetFrameLevel(self.field:GetFrameLevel() + 20)
        self.spiralArrow = f:CreateTexture(nil, "OVERLAY")
        ART:Set(self.spiralArrow, "comic_arrow")
        self.spiralArrow:SetSize(self.SPIRAL_ARROW_W, self.SPIRAL_ARROW_W / 2)
    end
    local a = self.spiralArrow
    local dx, dy = -0.62, 0.78                       -- from the upper right, down and to the left
    if piece.x > E.FIELD_W * 0.62 then dx = 0.62 end -- near the right wall: from the upper left
    local L = math.sqrt(dx * dx + dy * dy)
    a.dir = { x = dx / L, y = dy / L }
    a.piece = piece
    a.reach = (piece.r or (piece.h and piece.h / 2) or E.PEG_R) + 4
    a.back = self.SPIRAL_ARROW_W / 2 + 6
    a.target = { x = piece.x - a.dir.x * a.reach, y = piece.y - a.dir.y * a.reach }
    if a.SetRotation then a:SetRotation(math.atan2 and math.atan2(-a.dir.y, a.dir.x) or math.atan(-a.dir.y, a.dir.x)) end
    a:Show()
    self.spiralHintPending = true        -- (gone with the first shot, like the spiral's)
end

-- It slides in and out along the way the ball should come in, angle fixed.
function UI:AnimateSpiralHint(now)
    local a = self.spiralArrow
    if not (a and a:IsShown() and a.dir) then return end
    if a.piece then
        a.target.x = a.piece.x - a.dir.x * a.reach
        a.target.y = a.piece.y - a.dir.y * a.reach
    end
    local pull = a.back + 22 * (0.5 + 0.5 * math.sin(now * 5))
    a:ClearAllPoints()
    a:SetPoint("CENTER", self.field, "TOPLEFT", a.target.x - a.dir.x * pull, -(a.target.y - a.dir.y * pull))
end

-- Until Play is pressed the board stands empty: no pieces, no bucket, no
-- cannon, no boss, no ribbon, no guide; only its painted backdrop.
function UI:HideBoardContents()
    self.boardHidden = true
    for _, t in ipairs(self.pegTex or {}) do t.disc:Hide(); t.ring:Hide(); t.rim:Hide(); t.crack:Hide(); if t.cb then t.cb:Hide() end end
    for _, b in ipairs(self.ballTex or {}) do b:Hide() end
    for _, a in pairs(self.ballAura or {}) do if a.Hide then a:Hide() end end
    for _, t in ipairs(self.trail or {}) do t:Hide() end
    self.bucket:Hide()
    self.splashTex:Hide()
    self:HideGuide()
    if self.bossModel then self.bossModel:Hide(); self.bossPlatform:Hide() end
    self.bossBg:Hide(); self.bossFill:Hide(); self.bossName:Hide()
    self.pyramidTex:Hide()
    if self.barrelFrame then self.barrelFrame:Hide() end
end

-- Play: the board appears, the pieces dropping in as a level always starts.
function UI:ShowBoardContents()
    if not self.boardHidden then return end
    self.boardHidden = nil
    self:LayoutPegs()
    if self.spiralHintPending then self:ShowSpiralHint()
    elseif self.boardHintScript then
        local ok, piece = pcall(self.boardHintScript.point, self.state)
        self.boardHintScript = nil
        if ok and piece then self:ShowPieceHint(piece) end
    end
    if self.state and not self.state.noBucket then self.bucket:Show() end
    if self.barrelFrame then self.barrelFrame:Show() end
end

UI.CARD_STAR = 52            -- the level card's stars ...
UI.CARD_STAR_GAP = 120       -- ... this far apart, centre to centre, each with its score beneath
UI.CARD_LEVEL = 40           -- the cards sit this far over the board: above Tinkmaster's ring and the cannon
-- the result card's big stars: centred on the card's top edge plus (x, y)
UI.BIG_STARS = {
    { slot = "star_big_l", x = -140, y = -74, size = 170, layer = 1 },
    { slot = "star_big",   x = 0,    y = -44, size = 206, layer = 3 },
    { slot = "star_big_r", x = 140,  y = -74, size = 170, layer = 1 },
}
UI.BIG_SCORE_Y = -146        -- the big score's top, under the middle star

-- The two cards share one frame; their layouts differ.
function UI:CardLayout(mode)
    local card = self.card
    local result = mode == "result"
    card.starFrame:SetShown(result)
    for _, s in ipairs(card.stars) do s:SetShown(not result); s.sub:SetShown(not result) end
    card.line1:SetShown(not result)
    card.line2:SetShown(true)
    card.title:ClearAllPoints()
    card.line2:ClearAllPoints()
    card.line3:ClearAllPoints()
    if result then
        card.title:SetPoint("TOP", card, "TOP", 0, -200)
        card.line2:SetPoint("TOP", card.title, "BOTTOM", 0, -14)
        card.best:ClearAllPoints()
        card.best:SetPoint("TOP", card.line2, "BOTTOM", 0, -12)
        card.line3:SetPoint("TOP", card.best, "BOTTOM", 0, -10)
    else
        card.title:SetPoint("TOP", card, "TOP", 0, -46)
        -- the objective front and centre, right over the Play button (a
        -- longer one grows upward); the star scores are under the stars
        card.line1:ClearAllPoints()
        card.line1:SetPoint("BOTTOM", card.main, "TOP", 0, 16)
        if card.line1.SetJustifyH then card.line1:SetJustifyH("CENTER") end
        card.line2:SetPoint("TOP", card, "TOP", 0, -168)
        card.line2:SetShown(false)
        card.best:ClearAllPoints()
        card.best:SetPoint("TOP", card, "TOP", 0, -164)
        -- the level card's own sizes and colours
        card.line2:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
        card.line2:SetTextColor(1, 0.82, 0)
        card.line3:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
        card.line3:SetTextColor(0.8, 0.8, 0.9)
        card.line3:SetPoint("TOP", card.best, "BOTTOM", 0, -10)
    end
end
UI.STAR_FILL_SECS = 4.5      -- the score counts up (and the stars fill) over this long
UI.STAR_POP_SECS = 1.0       -- a star that fills pops up, spins all the way round and drops back, over this long
UI.STAR_POP_LIFT = 70        -- how high it pops, in pixels
UI.STAR_POP_SCALE = 0.25     -- how much it swells at the top
UI.STAR_ROCKETS = 30         -- little stars that shoot out of the three on a three-star clear
UI.ROCKET_GRAVITY = 520

-- The result card's count-up: the score climbs from nothing, and each star
-- fills with gold from left to right as it passes that star's mark (half
-- the two-star mark, the two-star mark, the three-star mark); a cleared
-- level's first star always fills. A chime rises with each full star.
-- A star that has just filled pops: it swells and springs back, with a
-- burst of light behind it that fades.
-- The result card's sounds are remembered, so closing the card stops them.
function UI:CardSound(file)
    local ok, handle = GP:PlaySfx(file)
    if ok and handle then
        self.cardSounds = self.cardSounds or {}
        self.cardSounds[#self.cardSounds + 1] = handle
    end
end

function UI:StopCardSounds()
    if type(StopSound) == "function" then
        for _, h in ipairs(self.cardSounds or {}) do pcall(StopSound, h, 150) end
        if self.rampHandle then pcall(StopSound, self.rampHandle, 0) end
    end
    self.cardSounds, self.rampHandle = nil, nil
end

function UI:UpdateStarPops(now)
    local card = self.card
    if not (card and card.bigStars) then return end
    for _, s in ipairs(card.bigStars) do
        if s.popAt then
            local f = (now - s.popAt) / self.STAR_POP_SECS
            local lift, k, angle = 0, 1, 0
            if f >= 1 then
                s.popAt = nil
                s.glow:Hide()
            else
                -- up fast, a full turn at the top, then down with a little bounce
                if f < 0.3 then
                    local u = f / 0.3
                    lift = self.STAR_POP_LIFT * (1 - (1 - u) * (1 - u))
                elseif f < 0.75 then
                    lift = self.STAR_POP_LIFT
                else
                    local u = (f - 0.75) / 0.25
                    lift = self.STAR_POP_LIFT * (1 - u * u) + math.sin(u * math.pi) * 6 * (1 - u)
                end
                if f > 0.15 and f < 0.8 then
                    local u = (f - 0.15) / 0.65
                    angle = -2 * math.pi * (u * u * (3 - 2 * u))
                end
                k = 1 + self.STAR_POP_SCALE * math.sin(math.min(1, f / 0.8) * math.pi)
                local g = s.size * (1.3 + 1.0 * f)
                s.glow:SetSize(g, g)
                s.glow:SetAlpha(1 - f)
                s.glow:Show()
            end
            s.base:ClearAllPoints()
            s.base:SetPoint("CENTER", card, "TOP", s.x, s.y + lift)
            s.base:SetSize(s.size * k, s.size * k)
            s.fill:SetSize(s.size * k, s.size * k)
            if s.fill.SetTexCoord then s.fill:SetTexCoord(0, 1, 0, 1) end
            if s.base.SetRotation then s.base:SetRotation(angle); s.fill:SetRotation(angle) end
        end
    end
end

-- Three stars: little stars shoot out of the big ones like bottle rockets.
function UI:StarRockets(now)
    local card = self.card
    local n = #card.sparks
    for i, t in ipairs(card.sparks) do
        local s = card.bigStars[((i - 1) % 3) + 1]
        local a = -math.pi / 2 + (math.random() - 0.5) * 2.2
        local sp = 260 + math.random() * 260
        t.rx, t.ry = s.x, s.y + self.STAR_POP_LIFT * 0.5
        t.vx, t.vy = math.cos(a) * sp, -math.sin(a) * sp
        t.born, t.life = now + (i / n) * 0.35, 1.1 + math.random() * 0.5
        t.size = 10 + math.random() * 12
        t.spin = (math.random() - 0.5) * 12
        t.rocket = true
    end
end

function UI:UpdateRockets(now)
    local card = self.card
    if not (card and card.sparks) then return end
    for _, t in ipairs(card.sparks) do
        if t.rocket then
            local e = now - t.born
            if e < 0 then
                t:Hide()
            elseif e >= t.life then
                t.rocket = nil
                t:Hide()
            else
                local x = t.rx + t.vx * e
                local y = t.ry + t.vy * e - 0.5 * self.ROCKET_GRAVITY * e * e
                t:ClearAllPoints()
                t:SetPoint("CENTER", card, "TOP", x, y)
                t:SetSize(t.size, t.size)
                t:SetAlpha(1 - e / t.life)
                if t.SetRotation then t:SetRotation(t.spin * e) end
                t:Show()
            end
        end
    end
end

function UI:UpdateStarFill(now)
    local card = self.card
    self:UpdateStarPops(now)
    self:UpdateRockets(now)
    local a = card and card.fillAnim
    if not a then return end
    local t = math.min(1, (now - a.start) / self.STAR_FILL_SECS)
    local e = t                                      -- an even climb, so each star has its moment
    local shown = a.score * e
    card.bigScore:SetText(fmtBig(math.floor(shown + 0.5)))
    local prev = 0
    for i, s in ipairs(card.bigStars) do
        local lo, hi = prev, a.marks[i]
        prev = hi
        local f = 0
        if a.cleared then
            f = (hi > lo) and (shown - lo) / (hi - lo) or 1
            if i == 1 then f = math.max(f, e) end   -- a clear always earns the first
            if f < 0 then f = 0 elseif f > 1 then f = 1 end
        end
        if f > 0 then
            s.fill:SetWidth(s.size * f)
            if s.fill.SetTexCoord then s.fill:SetTexCoord(0, f, 0, 1) end
            s.fill:Show()
        else
            s.fill:Hide()
        end
        if f >= 1 and not s.filled then
            s.filled = true
            s.popAt = now                            -- it pops to life
            -- a bottle rocket for each of the first two; the full fanfare for the third
            if i < 3 then
                self:CardSound("star_rocket.ogg")
            else
                -- all three: the fanfare, and the shower of little stars
                self:CardSound("star_rocket.ogg")
                self:CardSound("star_fanfare.ogg")
                self:StarRockets(now)
                self:Celebrate()
            end
        end
    end
    if t >= 1 then
        card.bigScore:SetText(fmtBig(a.score))
        card.fillAnim = nil
        if self.rampHandle and type(StopSound) == "function" then pcall(StopSound, self.rampHandle, 300) end
        self.rampHandle = nil
    end
end

UI.FONT = "Fonts\\FRIZQT__.TTF"
UI.TEXT_SIZE = 13            -- every line of text in the side column
UI.VALUE_SIZE = 14           -- the numbers beside the headings
UI.HEAD_H = 20               -- the word-art headings' height

UI.CARD_W, UI.CARD_H = 450, 560   -- the level card
UI.CARD_POWER_Y = 222                 -- the card's power row, from its top (the objective sits low, over Play)
UI.ITEM_H = 48                        -- a special-ball button in the left column
UI.BALL_STRIP_SIZE = 65               -- the balls left, two columns of five
-- the tutorials' arrows: where each comes in from (an angle from the button,
-- in radians, 0 = from the right, counter-clockwise), how far, how big
-- (Rainbow comes in from the left, nearly level, so it cannot be read as
-- pointing at its neighbours; Suction comes in low from the right.)
UI.ARROW_ANGLES = { ring = 0.55, rainbow = math.pi - 0.18, suction = 0.08, green = -0.6 }
UI.ARROW_DIST = 128
UI.ARROW_W = 120
UI.ITEMS_Y = 4 + 5 * (65 + 5) + 26     -- under the balls

-- After the level: stars, score, what happened, and where to go next.
function UI:ShowResultCard(result, stars)
    local st = self.state
    local card = self.card
    local cleared = result.cleared
    local test = self.customTest ~= nil
    if test then
        card.title:SetText(cleared and "|cffffd700TEST CLEARED!|r" or (result.eggLost and "|cffff6060TEST: EGG LOST|r" or "|cffff6060TEST: OUT OF BALLS|r"))
    elseif result.duel then
        card.title:SetText(cleared and "|cffffd700YOU WON!|r" or ("|cffff6060" .. result.duel.name:upper() .. " WON|r"))
    else
        card.title:SetText(cleared and "|cffffd700LEVEL CLEARED!|r" or "|cffff6060OUT OF BALLS|r")
    end
    -- the big stars start empty and fill as the score counts up
    self:CardLayout("result")
    for _, s in ipairs(card.bigStars) do
        s.fill:Hide(); s.filled = nil; s.popAt = nil; s.glow:Hide()
        s.base:SetSize(s.size, s.size); s.fill:SetSize(s.size, s.size)
        s.base:ClearAllPoints(); s.base:SetPoint("CENTER", card, "TOP", s.x, s.y)
        if s.base.SetRotation then s.base:SetRotation(0); s.fill:SetRotation(0) end
    end
    for _, t in ipairs(card.sparks) do t.rocket = nil; t:Hide()
    end
    local m2, m3, m1 = starMarks(st)
    card.fillAnim = { start = GetTime(), score = result.score or 0, cleared = cleared,
        marks = { m1 or m2 * 0.5, m2, m3 }, stars = cleared and stars or 0 }
    -- a rising sound under the count-up
    if self.rampHandle and type(StopSound) == "function" then pcall(StopSound, self.rampHandle, 0) end
    local _, rh = GP:PlaySfx("star_ramp.ogg")
    self.rampHandle = rh
    local def = E.OBJECTIVES[result.objective] or E.OBJECTIVES.classic
    local goalLine
    if result.duel then
        goalLine = ("YOU %s  -  %s %s"):format(fmtBig(result.duel.you), result.duel.name, fmtBig(result.duel.rival))
    elseif result.objective == "boss" then goalLine = cleared and "Boss beaten" or "The boss survived"
    else goalLine = ("%d of %d %s"):format(result.goals, result.goalTotal, def.goalWord) end
    card.goalIcon:Hide()
    card.bigScore:SetText("0")
    -- under the title: what happened, the level's high score, the best combo
    card.line2:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    card.line2:SetTextColor(1, 1, 1)
    card.line2:SetText((cleared and "|cff66ff66Done!|r  " or "|cffff6060Missed:|r  ") .. goalLine)
    local prev = self.cardPrevBest or 0
    local high = math.max(prev, result.score or 0)
    local newBest = (result.score or 0) > prev and prev > 0
    card.best:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    card.best:SetTextColor(1, 0.85, 0.3)
    card.best:SetText(("%s  |cffffffff%s|r%s"):format(test and "Best this test" or "High score", fmtBig(high), newBest and "  |cff88ff88NEW!|r" or ""))
    card.best:Show()
    card.line3:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")
    card.line3:SetTextColor(0.75, 0.9, 1)
    local third = ("Best combo  |cffffffff%d|r"):format(result.bestCombo or 0)
    if not cleared and not test then third = third .. ("\n|cffffb0a0Plays left today: %d|r"):format(GP.Plays:Remaining()) end
    card.line3:SetText(third)
    if cleared and not test and st.level < L.COUNT and GP:IsUnlocked(st.level + 1) then
        card.main.text:SetText("NEXT LEVEL")
        card.main:SetScript("OnClick", function() UI:HideCard(); UI:NextLevel() end)
        styleButton(card.main, true, 0.2, 0.55, 0.25)
        card.main:Show()
    else
        card.main:Hide()
    end
    if test then
        card.left.text:SetText("Back to editor")
        card.left:SetScript("OnClick", function() UI:HideCard(); UI:BackToEditor() end)
    else
        card.left.text:SetText("Map")
        card.left:SetScript("OnClick", function() UI:HideCard(); UI:ShowLevelSelect(); if not GP.Plays:CanPlay() then UI:ShowOutOfPlays() end end)
    end
    styleButton(card.left, true, 0.35, 0.3, 0.45)
    card.right.text:SetText("Retry")
    card.right:SetScript("OnClick", function() UI:Retry() end)
    styleButton(card.right, test or GP.Plays:CanPlay(), 0.45, 0.3, 0.2)
    card.right:Show()
    card.left:ClearAllPoints()                                -- the pair, centred as a group
    local half = card.left:GetWidth() / 2 + 8                 -- a gap between them, whatever their width
    card.left:SetPoint("BOTTOM", card, "BOTTOM", -half, 34)
    card.right:ClearAllPoints()
    card.right:SetPoint("BOTTOM", card, "BOTTOM", half, 34)
    card.powerPrev:Hide(); card.powerNext:Hide(); card.boost:Hide()
    card.powerIcon:Hide(); card.powerBlurb:Hide()
    card.powerText:Hide()
    -- a chapter's rewards are not written on the card: their buttons on the
    -- left flash and count up instead
    for _, r in ipairs(result.rewards or {}) do self:FlashItemSlot(r.item, r.n) end
    self.cardSheet:Show()
    card:Show()
end

-- ---------------------------------------------------------------------
-- The level map (covers the field): one chapter a page, its ten levels
-- climbing a winding path from the bottom left to the boss at the top,
-- stars under every node. Prev/Next step a chapter, << and >> ten.

-- The ten nodes climb from the bottom to the boss at the top along a path
-- that winds differently in every chapter (seeded by the chapter number).
-- A chapter's ten node spots: the owner's own arranging (while it is being
-- done, on the owner's characters), else the hardcoded layout (MapLayout.lua,
-- UI.MAP_PATHS), else a winding path made from the chapter number.
UI.MAP_PATHS = UI.MAP_PATHS or {}
local function nodePath(chapter)
    local db = GnomishPachinkoDB
    local own = db and type(db.mapLayout) == "table" and db.mapLayout[chapter or 1]
    if own and not (GP.Plays and GP.Plays.IsOwner and GP.Plays:IsOwner()) then own = nil end
    local fixed = own or UI.MAP_PATHS[chapter or 1]
    if type(fixed) == "table" and #fixed == 10 then
        local path = {}
        for i = 1, 10 do path[i] = { x = fixed[i].x or fixed[i][1], y = fixed[i].y or fixed[i][2] } end
        return path
    end
    local rng = E.NewRng((chapter or 1) * 7919 + 13)
    local freq = 0.85 + rng() * 0.5
    local phase = rng() * math.pi * 2
    local swing = E.FIELD_W / 2 - 70
    local path = {}
    for i = 1, 10 do
        local t = (i - 1) / 9
        local x = E.FIELD_W / 2 + swing * math.sin((i - 1) * freq + phase) + (rng() - 0.5) * 40
        if x < 60 then x = 60 elseif x > E.FIELD_W - 60 then x = E.FIELD_W - 60 end
        path[i] = { x = x, y = (E.FIELD_H - 120) - t * (E.FIELD_H - 250) + (rng() - 0.5) * 16 }     -- clear of the buttons under the map
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
    -- the chapter's name under the row of buttons, big
    panel.title:SetPoint("TOP", 0, -54)
    panel.title:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
    panel.title:SetWidth(FW - 20)
    panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.subtitle:SetPoint("TOP", panel.title, "BOTTOM", 0, -5)
    panel.subtitle:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    panel.subtitle:SetTextColor(0.85, 0.85, 0.95)

    -- the chapter buttons: tall, with big words
    local function navButton(w, text)
        local b = makeButton(panel, w, 38, text)
        b.text:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")
        return b
    end
    panel.prev10 = navButton(58, "<<")
    panel.prev10:SetPoint("TOPLEFT", 10, -10)
    panel.prev10:SetScript("OnClick", function() UI:LevelPage(UI.levelPage - 10) end)
    panel.prev = navButton(92, "Prev")
    panel.prev:SetPoint("LEFT", panel.prev10, "RIGHT", 4, 0)
    panel.prev:SetScript("OnClick", function() UI:LevelPage(UI.levelPage - 1) end)
    panel.next10 = navButton(58, ">>")
    panel.next10:SetPoint("TOPRIGHT", -10, -10)
    panel.next10:SetScript("OnClick", function() UI:LevelPage(UI.levelPage + 10) end)
    panel.next = navButton(92, "Next")
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
    function panel:LayPath(chapter, path)
        path = path or nodePath(chapter)
        self.path = path
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
            if UI.mapArrange then return end
            if self.level and GP:IsUnlocked(self.level) then
                UI:HideLevelSelect()
                UI:StartLevel(self.level)
            end
        end)
        -- the owner's arranging: press on a node and drag it
        c.nodeIndex = i
        local down, up = c:GetScript("OnMouseDown"), c:GetScript("OnMouseUp")
        c:SetScript("OnMouseDown", function(self, btn)
            if UI.mapArrange then UI:StartNodeDrag(self) return end
            if down then down(self, btn) end
        end)
        c:SetScript("OnMouseUp", function(self, btn)
            if UI.mapArrange then UI:EndNodeDrag() return end
            if up then up(self, btn) end
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

    -- in the window's footer under the map, above the author and version: a
    -- centred pair, the level editor (for everyone) and the way back to the
    -- level in play. They are there only while the map is.
    panel.editor = makeButton(self.frame, 170, 24, "Level editor")
    panel.editor:SetPoint("TOP", self.view, "BOTTOM", -90, -2)
    panel.editor:SetScript("OnClick", function() GP.Editor:Show() end)
    panel.back = makeButton(self.frame, 170, 24, "Return to current level")
    panel.back:SetPoint("TOP", self.view, "BOTTOM", 90, -2)
    panel.back:SetScript("OnClick", function() UI:HideLevelSelect() end)
    panel.editor:Hide(); panel.back:Hide()
    -- while an editor level is being test-played: the way back to the editor,
    -- in the same footer (it steps aside while the map is open)
    local toEditor = makeButton(self.frame, 170, 24, "Back to editor")
    toEditor:SetPoint("TOP", self.view, "BOTTOM", 0, -2)
    toEditor:SetScript("OnClick", function() UI:BackToEditor() end)
    toEditor:Hide()
    self.toEditorBtn = toEditor
    panel:SetScript("OnShow", function() panel.editor:Show(); panel.back:Show(); toEditor:Hide() end)
    panel:SetScript("OnHide", function()
        panel.editor:Hide(); panel.back:Hide()
        if UI.customTest then toEditor:Show() end
    end)
    -- wipes progress after a second click within a few seconds
    panel.reset = makeButton(panel, 150, 24, "Reset progress")
    panel.reset:SetPoint("BOTTOM", 0, 10)
    -- the owner's arranging of the map: drag the nodes where they should be
    panel.arrange = makeButton(panel, 120, 24, "Move levels")
    panel.arrange:SetPoint("BOTTOMLEFT", 10, 10)
    panel.arrange:SetScript("OnClick", function() UI:ToggleMapArrange() end)
    panel.arrange:Hide()
    panel.layoutReset = makeButton(panel, 120, 24, "Reset chapter")
    panel.layoutReset:SetPoint("BOTTOMRIGHT", -10, 10)
    panel.layoutReset:SetScript("OnClick", function() UI:ResetMapLayout() end)
    panel.layoutReset:Hide()
    panel:SetScript("OnUpdate", function() UI:UpdateNodeDrag() end)
    panel.reset:SetScript("OnClick", function(self)
        if self.armedUntil and GetTime() < self.armedUntil then
            self.armedUntil = nil
            self.text:SetText("Reset progress")
            GP:ResetProgress()
        else
            self.armedUntil = GetTime() + 6
            self.text:SetText("|cffff6060Really? Click again|r")
            GP:Print("Reset progress: click the button again within six seconds to wipe every level, star and best score, and put the special balls and green pegs back to a new player's. Gears and the day's plays are kept.")
        end
    end)
    -- the owner's characters can open every level for testing
    panel.unlock = makeButton(panel, 150, 24, "Unlock all (testing)")
    panel.unlock:SetPoint("BOTTOM", -80, 40)
    panel.unlimited = makeButton(panel, 150, 24, "Unlimited items")
    panel.unlimited:SetPoint("BOTTOM", 80, 40)
    panel.unlimited:SetScript("OnClick", function() GP:ToggleUnlimited(); UI:LevelPage(UI.levelPage) end)
    panel.unlimited:Hide()
    panel.unlock:SetScript("OnClick", function() GP:UnlockAll() end)
    panel.unlock:Hide()
    panel.reset:SetScript("OnLeave", function(self)
        if GameTooltip then GameTooltip:Hide() end
        if self:IsEnabled() then hoverButton(self, false) end
    end)
end

-- A puff of Pyramid dust at a field point, growing and fading over dur seconds.
function UI:PyramidPuff(x, y, size, dur, now)
    local pick = self.pyramidPuffs[1]
    for _, d in ipairs(self.pyramidPuffs) do
        if not d.untilT then pick = d break end
        if d.untilT < pick.untilT then pick = d end
    end
    pick.size, pick.dur, pick.untilT = size, dur, now + dur
    pick:SetSize(size * 0.6, size * 0.36)
    pick:SetAlpha(1)
    pick:ClearAllPoints()
    pick:SetPoint("CENTER", self.field, "TOPLEFT", x, -y)
    pick:Show()
end

-- The host's window: one model clipped to a square whose corners just
-- reach the ring's outer edge. The ring's band is wide (its opening is
-- about 0.58 of its radius), so the square's edges and corners all lie
-- under it and the host shows only through the round opening, however far
-- it is zoomed. (Several model copies in strips drifted out of step: each
-- copy picks its own idle fidgets.)
UI.PORTRAIT_STRIPS = 1

UI.TUBE_DIM = 0.38      -- an unscored Fever tube is drawn this dark

-- The testing buttons, for the owner's characters only, in a fly-out on
-- the right side of the window: a tab that opens a panel holding them.
function UI:CreateTestFlyout(frame)
    local tab = makeButton(frame, 96, 30, "Testing")
    tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", -8, -110)
    tab:SetFrameLevel(frame:GetFrameLevel() + 60)
    local fly = CreateFrame("Frame", nil, frame)
    fly:SetSize(204, 20)
    fly:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", 0, -4)
    fly:SetFrameLevel(frame:GetFrameLevel() + 60)
    fly.skin = ART:NewSkin(fly, "card", "BACKGROUND", 0)
    fly:EnableMouse(true)
    fly:Hide()
    local title = fly:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", fly, "TOP", 0, -14)
    title:SetText("|cffffd700Testing (owner only)|r")
    local list = { self.levelPanel.unlock, self.levelPanel.unlimited, self.freeBtn, self.levelPanel.reset }
    for i, b in ipairs(list) do
        if b.SetParent then b:SetParent(fly) end
        b:ClearAllPoints()
        b:SetPoint("TOP", fly, "TOP", 0, -36 - (i - 1) * 34)
        b:SetWidth(180)
        b:SetFrameLevel(fly:GetFrameLevel() + 2)
    end
    fly:SetHeight(36 + #list * 34 + 12)
    tab:SetScript("OnClick", function()
        if fly:IsShown() then fly:Hide() else UI:RefreshTestFlyout(); fly:Show() end
    end)
    self.testTab, self.testFly = tab, fly
    self:RefreshTestFlyout()
end

function UI:RefreshTestFlyout()
    if not self.testTab then return end
    local owner = GP.Plays:IsOwner()
    if owner then self.testTab:Show() else self.testTab:Hide(); self.testFly:Hide() end
    local lp = self.levelPanel
    if owner then
        lp.unlimited.text:SetText(GP:Unlimited() and "Unlimited: on" or "Unlimited: off")
        for _, b in ipairs({ lp.unlock, lp.unlimited, self.freeBtn, lp.reset }) do b:Show() end
    end
end

-- The board's chrome: the host's box, the balls-left strip, the special-ball
-- buttons and the bucket. Hidden while the map or the out-of-plays panel covers the board.
function UI:SetBoardChrome(shown)
    local function set(obj) if obj then if shown then obj:Show() else obj:Hide() end end end
    set(self.portraitBox); set(self.portraitRingFrame)
    if self.boardHidden then self.barrelFrame:Hide() else set(self.barrelFrame) end
    for _, b in ipairs(self.ballStrip or {}) do if shown then b:Show() else b:Hide() end end
    if not shown then self.ballStripMore:SetText(""); self.ballExtra:Hide() end
    for _, b in ipairs(self.itemSlots or {}) do if shown and not self:ItemSlotKnown(b.item) then b:Hide() else set(b) end end
    if shown then
        if self.state and not self.state.noBucket and self.state.phase ~= E.PHASE.FEVER and not self.boardHidden then self.bucket:Show() end
        self:UpdateCounters()
    else
        self.bucket:Hide()
        self.splashTex:Hide()
    end
    if self.bossModel then
        if shown and self.bossModelNpc then
            self.bossModel:Show()
            if (self.bossViewCache or {}).noPlatform then self.bossPlatform:Hide() else self.bossPlatform:Show() end
        else self.bossModel:Hide(); self.bossPlatform:Hide() end
    end
end

function UI:ShowLevelSelect()
    self:Initialize()
    -- a card still up (the level card, or the cleared/failed card) goes
    -- first, whichever button opened the map
    if self.card and self.card:IsShown() then self:HideCard() end
    local current = (self.state and self.state.level) or GP:GetDB().current or 1
    self.levelPage = math.floor((current - 1) / L.PER_CHAPTER) + 1
    self:LevelPage(self.levelPage)
    self.levelPanel:Show()
    self:SetBoardChrome(false)
end

-- The host named on the right: the one for the given level's chapter.
function UI:ShowHostName(level)
    if not self.hostText then return end
    local host = GP:HostFor(level or 1)
    self.hostText:SetText("|cffffd700" .. ((host and host.name) or "Tinkmaster Overspark") .. "|r")
end

function UI:HideLevelSelect()
    if self.levelPanel then self.levelPanel:Hide() end
    self:ShowHostName((self.state and self.state.level) or GP:GetDB().current or 1)
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
    self:ShowHostName(first + 1)
    panel.subtitle:SetText(("Levels %d - %d"):format(first + 1, math.min(L.COUNT, first + L.PER_CHAPTER)))
    styleButton(panel.prev, page > 1, 0.3, 0.3, 0.45)
    styleButton(panel.prev10, page > 1, 0.3, 0.3, 0.45)
    styleButton(panel.next, page < pages, 0.3, 0.3, 0.45)
    styleButton(panel.next10, page < pages, 0.3, 0.3, 0.45)
    styleButton(panel.back, true, 0.35, 0.3, 0.45)
    styleButton(panel.reset, true, 0.45, 0.2, 0.2)
    styleButton(panel.unlock, true, 0.2, 0.5, 0.25)
    styleButton(panel.unlimited, true, 0.2, 0.5, 0.25)
    self:RefreshTestFlyout()
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
    local owner = GP.Plays:IsOwner()
    panel.arrange:SetShown(owner)
    panel.layoutReset:SetShown(owner and self.mapArrange or false)
    if not owner then self.mapArrange = nil end
    if self.mapArrange then for _, c in ipairs(panel.nodes) do c:Enable() end end
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
-- The owner's map arranging: Move levels turns it on; each node is dragged
-- where it should be, the dotted path following; every chapter's spots are
-- saved (GnomishPachinkoDB.mapLayout) for tools/import_map.py to write into
-- MapLayout.lua, where they become every player's map.

function UI:ToggleMapArrange()
    if not GP.Plays:IsOwner() then return end
    self.mapArrange = not self.mapArrange
    self.mapDrag = nil
    local panel = self.levelPanel
    panel.arrange.text:SetText(self.mapArrange and "|cff88ff88Done moving|r" or "Move levels")
    if self.mapArrange then
        GP:Print("Drag each level where it should be. Every chapter is saved as you go; Done moving when finished, then /reload and ask for the map to be imported.")
    end
    self:LevelPage(self.levelPage)
end

-- the cursor in the map's own pixels
function UI:MapCursor()
    local panel = self.levelPanel
    if not (panel and GetCursorPosition) then return nil end
    local scale = panel:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    local left, top = panel:GetLeft(), panel:GetTop()
    if not (cx and left and top) then return nil end
    return cx / scale - left, top - cy / scale
end

function UI:StartNodeDrag(node)
    local panel = self.levelPanel
    local path = {}
    for i, p in ipairs(panel.path or nodePath(self.levelPage)) do path[i] = { x = p.x, y = p.y } end
    self.mapDrag = { node = node, i = node.nodeIndex, path = path }
end

UI.MAP_EDGE = 30            -- nodes are kept this far inside the map
function UI:UpdateNodeDrag()
    local d = self.mapDrag
    if not d then return end
    local x, y = self:MapCursor()
    if not x then return end
    local m = self.MAP_EDGE
    x = math.max(m, math.min(E.FIELD_W - m, x))
    y = math.max(70, math.min(E.FIELD_H - 50, y))
    d.path[d.i] = { x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
    self.levelPanel:LayPath(self.levelPage, d.path)
end

function UI:EndNodeDrag()
    local d = self.mapDrag
    if not d then return end
    self:UpdateNodeDrag()
    self.mapDrag = nil
    local db = GP:GetDB()
    db.mapLayout = type(db.mapLayout) == "table" and db.mapLayout or {}
    local saved = {}
    for i, p in ipairs(d.path) do saved[i] = { x = p.x, y = p.y } end
    db.mapLayout[self.levelPage] = saved
end

function UI:ResetMapLayout()
    local db = GP:GetDB()
    if type(db.mapLayout) == "table" then db.mapLayout[self.levelPage] = nil end
    self.levelPanel:LayPath(self.levelPage)
    GP:Print(("Chapter %d's levels are back where they were."):format(self.levelPage))
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
    panel.buy = makeButton(panel, 260, 30, "Buy 5 plays for 10 Golden Gears")
    panel.buy:SetPoint("TOP", panel.wait, "BOTTOM", 0, -24)
    panel.buy:SetScript("OnClick", function() UI:BuyPlays() end)
    panel.free = makeButton(panel, 220, 30, "Owner: +" .. GP.Plays.OWNER_GEARS .. " Golden Gears")
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
    panel.how:SetText(("You have %d Golden Gears. Gears are 1g each: mail gold to %s with \"%s\" as the subject, or press the button at a mailbox and it fills in; you press Send. " .. P.SEND_NOTE .. " Bought plays last 24 hours."):format(
        P:Gears(), P:BankerName(), P.SUBJECT))
    panel.buy.text:SetText(P:Gears() >= P.SHOP.plays.cost and "Buy 5 plays for 10 Golden Gears" or "Get Golden Gears by mail")
    styleButton(panel.buy, true, 0.55, 0.4, 0.1)
    styleButton(panel.levels, true, 0.35, 0.3, 0.45)
    if false then        -- the owner's gears button lives in the Testing fly-out now
        panel.free:Show()
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

-- The right column shows the info or, while shopping, the Golden Gear shop
-- in the same space.
function UI:ShowShop(on)
    if not self.shopPanel then return end
    if (on and true or false) ~= (self.shopping or false) then GP:PlaySfx("click_soft.ogg") end
    self.shopping = on and true or false
    if on then
        self.infoPanel:Hide()
        self.shopPanel:Show()
    else
        self.shopPanel:Hide()
        self.infoPanel:Show()
    end
    self:UpdateDisplay()
end

-- Plays: with gears, straight from the shop; without, the mail for gears.
function UI:BuyPlays()
    local P = GP.Plays
    if P:Gears() >= P.SHOP.plays.cost then return self:ShopBuy("plays") end
    self:BuyGears()
end

function UI:BuyGears()
    local ok, err = GP.Plays:FillPurchaseMail(GP.Plays.DEFAULT_GEARS_MAIL)
    if ok then return end
    -- away from a mailbox: Tinkmaster explains it, once (heard or skipped)
    if not (MailFrame and MailFrame:IsShown()) and GP.Dialog and GP.Dialog.PlayOnce
        and GP.Dialog:PlayOnce("gears_help") then return end
    GP:Print(err)
end

function UI:ShopBuy(what)
    local ok, msg = GP.Plays:Buy(what)
    GP:Print(msg)
    if ok then GP:PlaySfx("unlock.ogg") end
    self:UpdateDisplay()
    if self.playsPanel and self.playsPanel:IsShown() then self:UpdatePlaysPanel() end
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
-- opts.custom: a level from the editor, test-played: no play spent, no
-- talk, no progress, no special balls, and back to the editor at the end.
function UI:StartLevel(n, retry, opts)
    self:Initialize()
    local custom = opts and opts.custom
    self.customTest = custom
    if self.toEditorBtn then
        if custom and not (self.levelPanel and self.levelPanel:IsShown()) then self.toEditorBtn:Show() else self.toEditorBtn:Hide() end
    end
    if not custom and not GP:IsUnlocked(n) then n = GP:GetDB().unlocked or 1 end
    if not custom and not GP.Plays:CanPlay() then
        self:ShowOutOfPlays()
        self:UpdateDisplay()
        return false
    end
    self.attempts = self.attempts or {}
    local akey = custom and "custom" or n
    if retry then self.attempts[akey] = (self.attempts[akey] or 0) + 1 else self.attempts[akey] = 0 end
    local spec = custom and L:BuildCustom(custom, n, self.attempts[akey]) or L:Build(n, self.attempts[n])
    -- a retry of a duel whose board was already cleared plays only the duel
    self.duelCarry = self.duelCarry or {}
    if not retry then self.duelCarry[n] = nil end
    self.duelOnly = (retry and not custom and spec.objective == "duel") and self.duelCarry[n] or nil
    local last = GP:GetDB().lastPower
    if last then
        for _, id in ipairs(GP:UnlockedPowers(n)) do if id == last then spec.power = last end end
    end
    self.state = E:NewLevel(spec)
    self.state.custom = custom and true or nil
    self.state.crazyGuide = GP:GetDB().crazyGuide and true or nil
    if self.card then self:HideCard() end
    if self.shotText then self.shotText:SetText("") end
    self.duelStartAt, self.duelTurnAt, self.rivalShotAt = nil, nil, nil
    self.paused = false
    if self.duelYou then self:UpdateDuelHud() end
    if not custom then GP:GetDB().current = n end
    self.guideAim = nil
    self:LayoutPegs()
    for i, bin in ipairs(self.bins) do
        bin:Hide()
        bin.label:SetText("|cffffd700" .. fmtBig(E.FEVER_BINS[i]) .. "|r")
    end
    for _, s in ipairs(self.bannerStars) do s:Hide() end
    self.bucket:Show()
    self.pyramidTex:Hide()
    self.bucketUnderPyramid = nil
    for _, d in ipairs(self.pyramidPuffs) do d.untilT = nil; d:Hide() end
    self.blastTex:Hide()
    self.blastRing:Hide()
    self:HideBolt()
    if self.state.noBucket then self.bucket:Hide() end
    ART:Set(self.fieldBg, ART:FieldBackdrop(n))
    for _, bin in ipairs(self.bins) do
        bin.litShown = nil
        ART:Set(bin.tube, "fever_tube_" .. bin.letter)
        bin.halo:Hide(); bin.shine:Hide()
    end
    for _, t in ipairs(self.postTex) do t:Hide() end
    self.splashAt, self.flashAt, self.electricUntil, self.calloutUntil = nil, nil, nil, nil
    self.splashTex:Hide(); self.flashTex:Hide(); self.calloutTex:Hide(); self.lastGlow:Hide()
    self:ClearFx()
    self:StopFanfare()
    self:HideGuide()
    -- (no title banner: the level card shows the title and objective, and a
    -- banner would sit behind the opening talk)
    self:ShowBanner("", "", 0)
    if GP.Mascot.SetHost then GP.Mascot:SetHost(GP:HostFor(n).npc, GP:HostFor(n)) end
    -- nothing is drawn on the board until the player presses Play on the card
    self:HideBoardContents()
    self.startVoice = spec.objective == "boss" and "boss_start" or (spec.objective == "duel" and "duel_start" or "level_start")
    GP.Mascot:React("start")
    self:UpdateDisplay()
    local talk = (not custom and GP.Dialog and GP.Dialog:For(self.state)) or {}
    self.spiralHintPending = nil
    if self.spiralArrow then self.spiralArrow:Hide() end
    self.boardHintScript = nil
    for _, sc in ipairs(talk) do
        if sc.key == "slide" then self.spiralHintPending = true
        elseif sc.point and not self.boardHintScript then self.boardHintScript = sc end
    end
    local voice = self.startVoice
    if #talk > 0 then
        self.cardSheet:Show()
        GP.Dialog:Play(talk, function() UI:ShowStartCard() end)      -- the talk was the welcome: no start line after it
    else
        GP:PlayVoice(voice)
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
    self.fineAim = nil
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
    if self.customTest then return end      -- an editor test keeps the special balls
    if item == "green" then return self:UseGreenPeg() end
    local st = self.state
    if not st or st.phase ~= E.PHASE.AIM then return end
    if st.armed == item then
        E:Arm(st, nil)
    elseif GP:ItemCount(item) > 0 then
        E:Arm(st, item)
    end
    self:UpdateItemSlots()
end

-- The tutorials light up the slots they talk about: a pulsing glow behind
-- each named button (nil puts every light out).
function UI:HighlightItems(items)
    local on = {}
    for _, id in ipairs(items or {}) do on[id] = true end
    self.highlighted = items and on or nil
    for _, b in ipairs(self.itemSlots or {}) do
        if on[b.item] and b:IsShown() then b.hl:Show(); b.arrow:Show() else b.hl:Hide(); b.arrow:Hide() end
    end
end

-- A slot handed more (a chapter's reward): it glows and a "+n" floats up.
UI.FLASH_SECS = 1.8
function UI:FlashItemSlot(item, n)
    for _, b in ipairs(self.itemSlots or {}) do
        if b.item == item then
            b.flashAt = GetTime()
            b.plus:SetText("+" .. tostring(n or 1))
        end
    end
    self:UpdateItemSlots()
end

function UI:UpdateSlotFlashes(now)
    for _, b in ipairs(self.itemSlots or {}) do
        if b.flashAt then
            local f = (now - b.flashAt) / self.FLASH_SECS
            if f >= 1 or not b:IsShown() then
                b.flashAt = nil
                b.plus:Hide()
                if not (self.highlighted and self.highlighted[b.item]) then b.hl:Hide() end
            else
                b.hl:SetAlpha(1 - f * 0.7)
                b.hl:Show()
                b.plus:ClearAllPoints()
                b.plus:SetPoint("BOTTOM", b, "TOP", 0, 2 + 26 * f)
                b.plus:SetAlpha(f < 0.7 and 1 or (1 - (f - 0.7) / 0.3))
                b.plus:Show()
            end
        end
    end
end

function UI:PulseHighlights(now)
    self:UpdateSlotFlashes(now)
    if not self.highlighted then return end
    local a = 0.55 + 0.45 * math.sin(now * 6)
    for i, b in ipairs(self.itemSlots or {}) do
        if self.highlighted[b.item] then
            if b:IsShown() then b.hl:Show(); b.arrow:Show() end
            b.hl:SetAlpha(a)
            -- the arrow jabs in and out at the button and wobbles about its angle
            local ang = b.arrowAngle + 0.12 * math.sin(now * 5 + i)
            local d = self.ARROW_DIST + 16 * math.sin(now * 9 + i * 1.7)
            b.arrow:ClearAllPoints()
            b.arrow:SetPoint("CENTER", b, "CENTER", math.cos(ang) * d, math.sin(ang) * d)
            if b.arrow.SetRotation then b.arrow:SetRotation(ang + math.pi) end
            local k = 1 + 0.08 * math.sin(now * 9 + i * 1.7 + 1.2)
            b.arrow:SetSize(self.ARROW_W * k, self.ARROW_W / 2 / k)
        end
    end
end

-- A slot shows only once Tinkmaster has explained it: the special balls
-- with the "items" talk, the Extra Green Peg with its own.
UI.ITEM_TUTORIAL = { ring = "items", rainbow = "items", suction = "items", green = "green_peg" }
function UI:ItemSlotKnown(item)
    local seen = GP:GetDB().dialogs or {}
    return seen[self.ITEM_TUTORIAL[item] or "items"] and true or false
end

function UI:UpdateItemSlots()
    local st = self.state
    for _, b in ipairs(self.itemSlots or {}) do
        local known = self:ItemSlotKnown(b.item)
        local boardUp = not ((self.levelPanel and self.levelPanel:IsShown()) or (self.playsPanel and self.playsPanel:IsShown()))
        if known and boardUp then b:Show() else b:Hide() end
        local n = GP:ItemCount(b.item)
        local armed = st and ((b.item == "green") and self.greenBoost or st.armed == b.item)
        local usable = (n > 0 or armed) and st ~= nil
        if b.item == "green" then usable = usable and self:GreenPegOpen() end
        b.text:SetText(armed and ("x%d\n|cff88ff88%s|r"):format(n, b.item == "green" and "ON" or "ARMED") or ("x%d"):format(n))
        styleButton(b, usable, 0.35, 0.3, 0.45)
        if armed and b.skin then ART:TintSkin(b.skin, 0.6, 1, 0.6, 1) end
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

-- The goal's word-art heading shrinks to leave room for its count on the
-- right ("ORANGE PEGS LEFT" ran under "20 / 20"), kept level with it.
UI.GOAL_WORD_X, UI.GOAL_WORD_Y = 24, -238
function UI:FitGoalLabel()
    local lbl, txt = self.goalLabel, self.goalText
    if not (lbl and txt) then return end
    local H = UI.HEAD_H
    local room = SIDE_W - 6 - (txt:GetStringWidth() or 0) - 10 - UI.GOAL_WORD_X
    local h = math.max(10, math.min(H, room / 8))
    lbl:SetSize(h * 8, h)
    lbl:ClearAllPoints()
    lbl:SetPoint("TOPLEFT", self.side, "TOPLEFT", UI.GOAL_WORD_X, UI.GOAL_WORD_Y - (H - h) / 2)
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
    -- remembered, so a retry of this level skips straight to the duel
    self.duelCarry = self.duelCarry or {}
    self.duelCarry[st.level] = { score = st.score, freeBallIdx = st.freeBallIdx, bestCombo = st.bestCombo }
    local spec2 = L:Build(st.level, (self.attempts and self.attempts[st.level] or 0) * 7 + 50, { stage2 = true })
    self.state = E:StartDuel(st, spec2, math.random())
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

-- One piece's colorblind mark: shown while it is unlit and on the board,
-- upright even on a turned brick, sized to the piece.
function UI:ColorMark(t, p, on)
    local slot = on and not p.post and not p.lit and not p.gone and not t.sweepAt and t.shown ~= "gone"
        and t.disc:IsShown() and CB_SLOT[p.kind]
    if slot then
        if not t.cb then t.cb = self.field:CreateTexture(nil, "OVERLAY", nil, 3) end
        if t.cbSlot ~= slot then ART:Set(t.cb, slot); t.cbSlot = slot end
        local size = (p.shape == "brick") and math.min(16, p.h + 6) or math.max(11, (p.r or E.PEG_R) * 1.35)
        t.cb:SetSize(size, size)
        placeAt(t.cb, self.field, p.x, p.y)
        t.cb:Show()
    elseif t.cb and t.cb:IsShown() then
        t.cb:Hide()
    end
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
        local rimColor = (p.kind ~= "egg" and p.kind ~= "boss") and toughLook(p.hp or 1, p.maxhp)
        if rimColor then
            t.rim:SetVertexColor(rimColor[1], rimColor[2], rimColor[3], 1)
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
        -- the Fever balloons have pictures of their own (postTex)
        if p.post then
            t.disc:Hide(); t.ring:Hide(); t.rim:Hide(); t.crack:Hide(); if t.cb then t.cb:Hide() end
            t.shown = "post"
        end
    end
    for i = #st.pegs + 1, #self.pegTex do
        local t = self.pegTex[i]
        t.disc:Hide(); t.ring:Hide(); t.rim:Hide(); t.crack:Hide(); if t.cb then t.cb:Hide() end
        t.shown = "gone"
    end
    if st.boss then
        self.bossName:SetText(st.boss.bossName or "Boss")
        self.bossBg:Show(); self.bossFill:Show(); self.bossName:Hide()
        if not midLevel then self:LoadBossModel(st.boss.ability) end
    else
        self.bossBg:Hide(); self.bossFill:Hide(); self.bossName:Hide()
        self:HideBossModel()
    end
end

-- The boss's creature model (the speaker's npc in Dialog.lua). A creature
-- the client has not cached yet loads a moment later, so the call repeats
-- until the model is there.
UI.BOSS_ANIM = { stand = 0, wound = 9, death = 1, dead = 6 }
function UI:LoadBossModel(ability)
    local m = self.bossModel
    local sp = GP.Dialog and GP.Dialog.SPEAKERS and GP.Dialog.SPEAKERS[ability]
    self.bossModelFor = ability
    local list = sp and (sp.models or { sp.npc }) or {}
    self.bossModelNpc = list[1]
    self.bossModelReady = false
    self.bossAnim = nil
    if m.ClearModel then pcall(m.ClearModel, m) end
    if not self.bossModelNpc then return self:HideBossModel() end
    self.bossPlatform:Show()
    m:Show()
    self.bossLoadToken = (self.bossLoadToken or 0) + 1
    local token = self.bossLoadToken
    -- each candidate gets a couple of seconds to load, then the next
    local function try(idx, left)
        if token ~= self.bossLoadToken then return end
        local npc = list[idx]
        if not npc then return end
        self.bossModelNpc = npc
        pcall(m.SetCreature, m, npc)
        self:PoseBossModel()
        if self:BossModelLoaded() or not (C_Timer and C_Timer.After) then return end
        if left > 0 then
            C_Timer.After(0.25, function() try(idx, left - 1) end)
        else
            C_Timer.After(0.05, function() try(idx + 1, 8) end)
        end
    end
    try(1, 8)
end

function UI:BossModelLoaded()
    local m = self.bossModel
    if not m.GetModelFileID then return true end
    local ok, id = pcall(m.GetModelFileID, m)
    return ok and id ~= nil
end

-- The board is seen from above, so the boss is too. Per boss, as the user
-- set them by eye (2026-10-02): view, the camera's angle up over the model
-- (1.55 = straight down on its head); dist, the camera's distance against
-- the client's own framing; yaw, the camera's turn round the model; pitch,
-- the model's own tilt; x, y, the model's offset from the boss's centre in
-- pixels; size, its frame against BOSS_R * 3.2; noPlatform hides the disc.
UI.BOSS_VIEW = { view = 1.2, dist = 1, pitch = 0, yaw = 0, x = 0, y = 0, size = 1 }
UI.BOSS_VIEWS = {
    drake  = { view = 1.55, dist = 1.31, yaw = 3.14, pitch = -0.20, x = 1.14, y = 60,     size = 4, noPlatform = true },
    golem  = { view = 1.48, dist = 1.53, yaw = 3.05, pitch = 0,     x = 24,   y = -29.57, size = 4 },
    spider = { view = 1.2,  dist = 3,    yaw = 3.14, pitch = -0.91, x = 0,    y = -0.29,  size = 3.39 },
    boar   = { view = 1.2,  dist = 3,    yaw = 3.14, pitch = 0,     x = 0,    y = -0.29,  size = 4 },
    yeti   = { view = 1.55, dist = 1.29, yaw = 3.09, pitch = 0.02,  x = 0,    y = 11.14,  size = 4 },
}
function UI:BossView(id)
    local fixed = (id and self.BOSS_VIEWS[id]) or {}
    local v = {}
    for k, d in pairs(self.BOSS_VIEW) do
        if fixed[k] ~= nil then v[k] = fixed[k] else v[k] = d end
    end
    v.noPlatform = fixed.noPlatform
    return v
end

function UI:PoseBossModel()
    local m = self.bossModel
    local v = self:BossView(self.bossModelFor)
    self.bossViewCache = v
    m:SetSize(E.BOSS_R * 3.2 * v.size, E.BOSS_R * 3.2 * v.size)
    if self.bossModelNpc then
        if v.noPlatform then self.bossPlatform:Hide() else self.bossPlatform:Show() end
    end
    pcall(function()
        -- the whole model (camera 0, the portrait camera, crops it)
        if m.SetPortraitZoom then m:SetPortraitZoom(0) end
        if m.SetCamDistanceScale then m:SetCamDistanceScale(1) end
        if m.RefreshCamera then m:RefreshCamera() end
        m:SetPosition(0, 0, 0)
        m:SetFacing(0)
    end)
    if m.SetPitch then pcall(m.SetPitch, m, v.pitch) end
    -- a bird's-eye view: the camera swings up over the model and round it
    -- (the turn); without the custom-camera calls the model itself is
    -- tilted and turned instead
    if not self:BossCamera(v) then
        if m.SetPitch then pcall(m.SetPitch, m, v.pitch + v.view) end
        pcall(m.SetFacing, m, v.yaw)
    end
    self.bossAnim = nil
end

-- The client's own framing of the model (camera 0) is turned into a custom
-- camera and swung up by `view` radians round the point it looks at, at
-- `dist` times its distance, so every model keeps its own fit.
function UI:BossCamera(v)
    local m = self.bossModel
    if not (m.MakeCurrentCameraCustom and m.GetCameraPosition and m.GetCameraTarget and m.SetCameraPosition) then return false end
    local ok = pcall(function()
        m:MakeCurrentCameraCustom()
        local px, py, pz = m:GetCameraPosition()
        local tx, ty, tz = m:GetCameraTarget()
        local dx, dy, dz = px - tx, py - ty, pz - tz
        local R = math.sqrt(dx * dx + dy * dy + dz * dz) * v.dist
        local hl = math.sqrt(dx * dx + dy * dy)
        local hx, hy = 1, 0
        if hl > 0.0001 then hx, hy = dx / hl, dy / hl end
        -- the turn: the camera goes round the model's vertical axis (the
        -- client's own camera turns with the model, so SetFacing shows nothing)
        local cy, sy = math.cos(v.yaw), math.sin(v.yaw)
        hx, hy = hx * cy - hy * sy, hx * sy + hy * cy
        local el = math.min(v.view, 1.55)
        m:SetCameraPosition(tx + hx * R * math.cos(el), ty + hy * R * math.cos(el), tz + R * math.sin(el))
        m:SetCameraTarget(tx, ty, tz)
    end)
    return ok
end

function UI:HideBossModel()
    self.bossLoadToken = (self.bossLoadToken or 0) + 1
    self.bossModelFor, self.bossModelNpc, self.bossModelReady = nil, nil, false
    self.bossModel:Hide()
    self.bossPlatform:Hide()
end

function UI:BossAnim(which)
    if self.bossAnim == which then return end
    self.bossAnim = which
    local m = self.bossModel
    if m.SetAnimation then pcall(m.SetAnimation, m, self.BOSS_ANIM[which] or 0) end
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
    if super then pts = E:Simulate(st, nil, nil, E:GuideBounces(st)) else pts, hit, hx, hy = E:Guide(st) end
    local last = pts[#pts]
    if hx then self.guideEnd = { x = hx, y = hy } elseif last then self.guideEnd = { x = last.x, y = last.y } end
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

-- Fine aim: with the right button held the view zooms in on where the
-- shot will land and the cursor turns the cannon a fiftieth of a degree a
-- pixel, from where it was pointing.
local FINE_RAD_PER_PX = 0.02 * math.pi / 180
local FINE_ZOOM = 3

function UI:StartFineAim()
    local st = self.state
    if not st or st.phase ~= E.PHASE.AIM or not GetCursorPosition then return end
    if st.duel and st.duel.stage == 2 and st.duel.turn == "rival" then return end
    local cx = GetCursorPosition()
    self.fineAim = { x = cx, aim = st.aim or 0 }
end

function UI:StopFineAim()
    self.fineAim = nil
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
    if self.fineAim then
        local cx = GetCursorPosition()
        local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        local lim = E.MAX_AIM_DEG * math.pi / 180
        local a = self.fineAim.aim + (cx - self.fineAim.x) / scale * FINE_RAD_PER_PX
        st.aim = math.max(-lim, math.min(lim, a))
        return
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
    local _, handle = GP:PlayMusic("fever_music.ogg")
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
UI.BOLT_HOP, UI.BOLT_HOLD, UI.BOLT_FADE, UI.BOLT_FLICKER = 0.07, 0.3, 0.3, 0.045

-- The bolt grows link by link from the green peg, each link a zigzag whose
-- kinks are re-thrown every BOLT_FLICKER seconds, then fades.
function UI:ShowBolt(path, now)
    if not path or #path < 2 then return end
    self:HideBolt()
    self.bolt = { path = path, start = now, flick = 0, offs = {} }
end

function UI:HideBolt()
    self.bolt = nil
    for _, l in ipairs(self.boltLines) do l.glow:Hide(); l.core:Hide() end
    for _, d in ipairs(self.boltDots) do d:Hide() end
end

function UI:DrawBolt(now)
    local b = self.bolt
    if not b then return end
    local path, field = b.path, self.field
    local links = #path - 1
    local t = now - b.start
    local grown = links * self.BOLT_HOP
    local over = grown + self.BOLT_HOLD
    if t >= over + self.BOLT_FADE then return self:HideBolt() end
    local alpha = (t > over) and (1 - (t - over) / self.BOLT_FADE) or 1
    if now >= b.flick then
        b.flick = now + self.BOLT_FLICKER
        b.offs = {}
    end
    local k = 0
    for i = 1, links do
        local f = (t - (i - 1) * self.BOLT_HOP) / self.BOLT_HOP
        if f <= 0 then break end
        if f > 1 then f = 1 end
        local a, c = path[i], path[i + 1]
        local dx, dy = c.x - a.x, c.y - a.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.5 then
            local n = math.max(3, math.min(8, math.floor(len / 14)))
            local px, py = -dy / len, dx / len
            local amp = math.min(10, len * 0.12)
            local offs = b.offs[i]
            if not offs then
                offs = {}
                for s = 1, n - 1 do offs[s] = (math.random() - 0.5) * 2 * amp end
                b.offs[i] = offs
            end
            local x0, y0 = a.x, a.y
            local last = math.max(1, math.ceil(n * f))
            for s = 1, last do
                local g = math.min(s / n, f)
                local o = (s < n and g < f) and (offs[s] or 0) or 0
                local x1, y1 = a.x + dx * g + px * o, a.y + dy * g + py * o
                k = k + 1
                local l = self.boltLines[k]
                if l then
                    for _, line in ipairs({ l.glow, l.core }) do
                        line:SetStartPoint("TOPLEFT", field, x0, -y0)
                        line:SetEndPoint("TOPLEFT", field, x1, -y1)
                        line:SetAlpha(alpha)
                        line:Show()
                    end
                end
                x0, y0 = x1, y1
            end
        end
        -- a flash on each piece the bolt has reached
        local d = self.boltDots[i]
        if d then
            local age = t - i * self.BOLT_HOP
            if f >= 1 and age >= 0 then
                local s = 26 - math.min(10, age * 40)
                d:SetSize(s, s)
                placeAt(d, field, c.x, c.y)
                d:SetAlpha(alpha * (0.6 + 0.4 * math.random()))
                d:Show()
            end
        end
    end
    for i = k + 1, #self.boltLines do self.boltLines[i].glow:Hide(); self.boltLines[i].core:Hide() end
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
        -- the last piece is lit: the "ahhh" gives way to the Fever music
        if (t == "fever" or t == "duel_last_orange" or t == "level_over") and self.ahhHandle then self:StopAhh(false) end
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
            self:ShowBanner("|cff88ccffSHIELD UP|r", "The boss blocks the next two hits or bolts", 1.4)
            GP:PlayVoice("boss_shield")
        elseif t == "boss_hop" then
            GP:PlaySfx("hop.ogg")
            self:Popup(ev.x, ev.y - 30, "!", 1, 1, 0.5)
        elseif t == "boss_scrap" then
            self:LayoutPegs(true)
            GP:PlaySfx("clink.ogg")
            self:Popup(ev.x, ev.y - 40, "SCRAP!", 1, 0.6, 0.3)
        elseif t == "boss_webs" then
            self:LayoutPegs(true)
            GP:PlaySfx("web_shoot.ogg")
            self:Popup(ev.x, ev.y - 40, "WEBS!", 0.85, 0.85, 0.95)
        elseif t == "web_catch" then
            self:LayoutPegs(true)
            GP:PlaySfx("web_catch.ogg")
            self:Popup(ev.x, ev.y - 20, "WEBBED!", 0.85, 0.85, 0.95)
        elseif t == "web_burn" then
            self:LayoutPegs(true)
            GP:PlaySfx("web_catch.ogg")
            self:Popup(ev.x, ev.y - 20, "BURNED", 1, 0.55, 0.2)
        elseif t == "boss_heal" then
            GP:PlaySfx("heal.ogg")
            self:Popup(ev.x, ev.y - 30, "+" .. (ev.healed or 1), 1, 0.4, 0.4)
        elseif t == "boss_down" then
            GP:PlaySfx("boss_down.ogg")
            GP:PlayVoice("boss_down")
        elseif t == "stage_clear" then
            self:ShowBanner("|cffffd700BOARD CLEARED!|r", (st.duel and st.duel.name or "The rival") .. " refuses to accept it. A duel!", 2.5)
            GP:PlaySfx("clear.ogg")
            GP:PlayVoice("duel_start")
            self.duelStartAt = now + 2.6
        elseif t == "scrap_zap" then
            -- the Tin Drake's iron took the lightning: a bolt to it, and it bursts
            self:ShowBolt({ { x = ev.x, y = ev.y }, { x = ev.bx, y = ev.by } }, now)
            self:Sparks(ev.bx, ev.by, { 0.7, 0.8, 1 }, 8, 24)
            self:Popup(ev.bx, ev.by - 18, "IRON!", 0.75, 0.85, 1)
            GP:PlaySfx("zap.ogg")
            GP:PlaySfx("clink.ogg")
        elseif t == "boss_zap" then
            -- an orange lit on a boss level: a bolt from it to the boss
            self:ShowBolt({ { x = ev.x, y = ev.y }, { x = ev.bx, y = ev.by } }, now)
            GP:PlaySfx("zap.ogg")
        elseif t == "boss_charge" then
            -- the Gyro Spider soaks the bolt up and stores it
            self:ShowBolt({ { x = ev.x, y = ev.y }, { x = ev.bx, y = ev.by } }, now)
            self:Sparks(ev.bx, ev.by, { 0.55, 0.85, 1 }, 4, 16)
            GP:PlaySfx("zap.ogg")
        elseif t == "boss_discharge" then
            -- a strike lets the stored lightning loose
            self:Sparks(ev.x, ev.y, { 0.55, 0.85, 1 }, 14, 40)
            self:Popup(ev.x, ev.y - 44, "DISCHARGE -" .. ev.damage, 0.55, 0.85, 1)
            GP:PlaySfx("zap.ogg")
        elseif t == "boss_charge_lost" then
            self:Popup(ev.x, ev.y - 44, "FIZZLED", 0.6, 0.6, 0.7)
        elseif t == "full_clear" then
            self:ShowBanner("|cffffd700FULL CLEAR!|r", ("Every piece lit: +%s"):format(fmtBig(ev.points)), 2.6)
            self:Celebrate()
            GP:PlaySfx("star_fanfare.ogg")
        elseif t == "duel_last_orange" then
            self:ShowBanner("|cffffd700NO ORANGES LEFT|r", "The duel ends: the higher score wins.", 2.4)
            GP:PlaySfx("fever.ogg")
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
            if not ev.again then GP:PlaySfx("slowmo.ogg") end
            -- the crowd holds its breath: an "ahhh" that builds until the
            -- last piece lights (and the Fever music cuts in) or the ball misses
            self:StartAhh(now)
        elseif t == "rim" then
            -- the ceramic lip of the bucket
            if now - (self.lastRimSound or 0) > 0.1 then
                self.lastRimSound = now
                GP:PlaySfx("rim.ogg")
            end
        elseif t == "pyramid" then
            GP:PlaySfx("pyramid.ogg")
            if (ev.left or 0) > 0 then GP:PlaySfx("pyramid_crumble.ogg") end
            self:PyramidPuff(ev.x, ev.y, 46, 0.5, now)
        elseif t == "pyramid_dust" then
            GP:PlaySfx("pyramid_dust.ogg")
            self:PyramidPuff(ev.x, ev.y, E.PYRAMID_W * 1.25, 1.2, now)
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
            local banner = POWER_BANNERS[ev.power] or "POWER!"
            if ev.power == "guide" and st.crazyGuide then banner = "|cffff66ffCRAZY GUIDE!|r" end
            self:ShowBanner(banner, "", 1.4)
            GP:PlayVoice("power_" .. ev.power, GP:HostForPower(ev.power))
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
            -- (events are handled after the step, when the landed ball is already gone)
            if st.ballsLeft <= 0 and #st.balls == 0 then self:StopFanfare(true) end
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

-- An editor level, test-played: the score and stars in a banner, then back
-- to the editor. Nothing is recorded.
-- An editor level's test ends like a real level: the sweep, the banner and
-- the cleared (stars filling with the score) or failed card. Nothing is
-- recorded; the card offers Retry and Back to editor.
function UI:OnCustomOver(result)
    local marks = self.customStars or {}
    local stars = result.cleared and L.StarsFromMarks(result.score, marks[1], marks[2], marks[3]) or 0
    self.cardPrevBest = self.customBest or 0
    self.customBest = math.max(self.customBest or 0, result.score or 0)
    self.cardAt = GetTime() + 1.8
    self.cardResult, self.cardStars = result, stars
    if result.cleared then
        local k = 0
        for i, p in ipairs(self.state.pegs) do
            local t = self.pegTex[i]
            if t and not p.gone then
                k = k + 1
                t.sweepAt = GetTime() + 0.4 + k * 0.03
            end
        end
        self:ShowBanner("|cffffd700TEST CLEARED!|r", "", 0)
        GP:PlaySfx("clear.ogg")
        GP:PlayVoice(stars >= 3 and "three_stars" or "level_cleared")
    else
        local goalWord = (E.OBJECTIVES[result.objective] or E.OBJECTIVES.classic).goalWord
        local progress = result.eggLost and "An egg fell off the board." or ("%d of %d %s."):format(result.goals, result.goalTotal, goalWord)
        self:ShowBanner(result.eggLost and "|cffff6060EGG LOST|r" or "|cffff6060OUT OF BALLS|r", progress, 0)
        GP:PlaySfx("fail.ogg")
        GP:PlayVoice("out_of_balls")
    end
    self:HideGuide()
    self:UpdateDisplay()
end

-- Leave a test early (or after it ends) for the editor.
function UI:BackToEditor()
    self.customBackAt = nil
    if self.toEditorBtn then self.toEditorBtn:Hide() end
    if GP.Editor then
        GP.Editor.testing = true
        GP.Editor:ReturnFromTest()
    end
end

-- Test-play an editor level on the board.
function UI:StartCustom(data, n)
    self:Show()
    -- the map (where the editor is opened from) gives way to the board
    if self.levelPanel and self.levelPanel:IsShown() then self:HideLevelSelect() end
    if self.playsPanel and self.playsPanel:IsShown() then self.playsPanel:Hide(); self:SetBoardChrome(true) end
    self.customBest = 0
    local ok = self:StartLevel(n or 1, false, { custom = data })
    self.customStars = self.state and self.state.stars
    return ok
end

-- Retry (the button beside the board, or on the result card): a retry uses
-- a play. A lost level has already paid for its attempt; starting over in
-- the middle of one, or replaying one just cleared, spends a play here.
function UI:Retry()
    local st = self.state
    local n = st and st.level or GP:GetDB().current or 1
    if self.customTest then
        if self.card then self:HideCard() end
        return self:StartLevel(n, true, { custom = self.customTest })
    end
    if not GP.Plays:CanPlay() then
        self:ShowOutOfPlays()
        self:UpdateDisplay()
        return false
    end
    local paid = st and st.result and not st.result.cleared
    if not paid then GP.Plays:RecordFail() end
    if self.card then self:HideCard() end
    return self:StartLevel(n, true)
end

function UI:OnLevelOver(result)
    if self.customTest then return self:OnCustomOver(result) end
    local db = GP:GetDB()
    local prevBest = db.best[result.level] or 0
    self.cardPrevBest = prevBest
    local stars, playsLeft = GP:RecordResult(result)
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
        -- just the banner: the score comes on the result card
        self:ShowBanner("|cffffd700LEVEL CLEARED!|r", "", 0)
        -- the stars are revealed on the card, filling as the score counts up
        GP:PlaySfx("clear.ogg")
        GP:PlayVoice(result.duel and "duel_won" or (stars >= 3 and "three_stars" or "level_cleared"))
        if result.crazyGuide then
            GP:Print("|cffff66ffCrazy Guide unlocked!|r Tinkmaster's Super Guide now shows five bounces.")
            if GP.Dialog and GP.Dialog.PlayOnce then GP.Dialog:PlayOnce("crazy_guide") end
        end
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
        if playsLeft <= 0 then
            self:ShowOutOfPlays(("You ran out of balls on level %d."):format(result.level))
        end
    end
    self:HideGuide()
    self:UpdateDisplay()
end

-- The last-piece "ahhh": started when the slow-mo zoom keys in, cut when
-- the piece lights, turned into a sad "awww" when the ball misses it.
UI.AHH_MISS_GRACE = 0.8     -- the slow-mo has stayed off this long, piece still up: a miss
                            -- (it lets go briefly mid-approach, so a short gap is not one)
function UI:StartAhh(now)
    if self.ahhHandle or (self.awwAt and now - self.awwAt < 1) then return end
    local ok, handle = GP:PlaySfx("last_ahh.ogg")
    self.ahhHandle = ok and (handle or true) or nil
    self.ahhAt = now
    self.ahhSlowOffAt = nil
    self.ahhTarget = self.state and self.state.lastPeg
end

function UI:StopAhh(missed)
    local h = self.ahhHandle
    self.ahhHandle = nil
    if type(h) == "number" and type(StopSound) == "function" then pcall(StopSound, h, missed and 150 or 300) end
    if missed then
        GP:PlaySfx("last_aww.ogg")
        self.awwAt = GetTime()
    end
end

function UI:WatchAhh(now)
    if not self.ahhHandle then return end
    local st = self.state
    local target = self.ahhTarget or (st and st.lastPeg)
    local hit = target and (target.lit or target.gone)
    if not st or st.phase == E.PHASE.FEVER or hit then
        -- the piece is lit: the "ahhh" just ends (Fever's music takes over)
        return self:StopAhh(false)
    end
    if st.phase ~= E.PHASE.FLIGHT then
        -- the shot is over and the piece still stands: that was the miss
        return self:StopAhh(true)
    end
    -- the slow-mo let go and has stayed off: the ball went past
    if st.lastSlow then
        self.ahhSlowOffAt = nil
    else
        self.ahhSlowOffAt = self.ahhSlowOffAt or now
        if now - self.ahhSlowOffAt > self.AHH_MISS_GRACE then self:StopAhh(true) end
    end
end

function UI:OnUpdate(dt)
    local now = GetTime()
    local st = self.state
    self:UpdatePopups(now)
    self:PulseHighlights(now)
    self:AnimateShowcase(now)
    self:WatchAhh(now)
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
    if self.customBackAt and now >= self.customBackAt then
        self:BackToEditor()
    end
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
    self:UpdateStarFill(now)
    if self.cardAt and now >= self.cardAt then
        self.cardAt = nil
        if self.cardResult and not (self.playsPanel and self.playsPanel:IsShown()) then
            self:ShowResultCard(self.cardResult, self.cardStars)
        end
        self.cardResult = nil
    end
    if not st then return end
    if self.levelPanel and self.levelPanel:IsShown() then return end
    if self.boardHidden then return end          -- the level card is up: nothing on the board yet
    if self.spiralHintPending and st and (st.shots or 0) > 0 then
        self.spiralHintPending = nil
        if self.spiralArrow then self.spiralArrow:Hide() end
    end
    self:AnimateSpiralHint(now)

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
        -- with pieces moving the guide changes on its own: drawn again a few times a second
        local moving = #st.movers > 0 and now - (self.guideAt or 0) >= 0.05
        if self.guideAim ~= st.aim or self.guideDirty or moving then
            self.guideAim = st.aim
            self.guideDirty = nil
            self.guideAt = now
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
    local fine = self.fineAim and st and st.phase == E.PHASE.AIM and self.guideEnd
    local target = (slow or hold) and E.LAST_ZOOM or (fine and FINE_ZOOM or 1)
    -- the last gem (or egg) falling: still slowed, but the view eases back
    -- out to the whole board so the bucket can be seen catching it or not
    if st and st.looseSlow and st.lastSlow then target = 1 end
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
    if fine then
        local g = self.guideEnd
        if self.zoomX then
            local k = math.min(1, dt * 16)
            self.zoomX = self.zoomX + (g.x - self.zoomX) * k
            self.zoomY = self.zoomY + (g.y - self.zoomY) * k
        else
            self.zoomX, self.zoomY = g.x, g.y
        end
    elseif st and st.lastPeg and #st.balls > 0 then
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
        if p.post then
            -- a Fever balloon (drawn by postTex): any texture left at this
            -- index from a bigger board stays hidden
            if t and t.shown ~= "post" then
                t.disc:Hide(); t.ring:Hide(); t.rim:Hide(); t.crack:Hide(); if t.cb then t.cb:Hide() end
                t.shown = "post"
            end
        elseif t then
            if t.sweepAt then
                -- the win sweep
                local a = 1 - (now - t.sweepAt) / 0.35
                if a <= 0 then
                    if t.shown ~= "gone" then t.disc:Hide(); t.ring:Hide(); t.rim:Hide(); t.crack:Hide(); if t.cb then t.cb:Hide() end; t.shown = "gone" end
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
                        t.disc:Hide(); t.ring:Hide(); t.rim:Hide(); t.crack:Hide(); if t.cb then t.cb:Hide() end
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
                        ART:Set(t.disc, pieceSlot(p, ""))
                        t.ring:SetVertexColor(c.glow[1], c.glow[2], c.glow[3], 1)
                        t.kind = p.kind
                        t.shown = "base"
                    end
                    if flashing then t.ring:SetAlpha(1); t.ring:Show() else t.ring:Hide() end
                elseif p.kind == "boss" then
                    ART:Set(t.disc, ART:Boss(p.ability))
                    -- the model and its platform ride with the boss
                    if self.bossModelNpc then
                        if not self.bossModelReady and self:BossModelLoaded() then self.bossModelReady = true end
                        self.bossPlatform:ClearAllPoints()
                        self.bossPlatform:SetPoint("CENTER", field, "TOPLEFT", p.x, -p.y)
                        self.bossModel:ClearAllPoints()
                        local view = self.bossViewCache or self:BossView(self.bossModelFor)
                        self.bossModel:SetPoint("CENTER", field, "TOPLEFT", p.x + view.x, -(p.y + view.y))
                        if p.lit then
                            if self.bossAnim ~= "death" and self.bossAnim ~= "dead" then
                                self:BossAnim("death")
                                self.bossDeadAt = now
                            elseif self.bossAnim == "death" and now - (self.bossDeadAt or now) > 1.5 then
                                self:BossAnim("dead")
                            end
                        elseif flashing then
                            self:BossAnim("wound")
                        else
                            self:BossAnim("stand")
                        end
                    end
                    if p.lit then t.disc:SetVertexColor(0.4, 0.4, 0.4, 1) else t.disc:SetVertexColor(1, 1, 1, 1) end
                    if flashing and not t.flashed then
                        -- a hit flash: a soft glow over the face
                        t.flashed = true
                        self:Spawn({ slot = "glow_soft", x = p.x, y = p.y, size = (p.r or E.BOSS_R) * 3.2, life = 0.25, r = 1, g = 0.7, b = 0.6, fade = true })
                    elseif not flashing then
                        t.flashed = nil
                    end
                    t.rim:Hide()     -- the shield is the half dome on the bar frame
                    t.ring:SetVertexColor(1, 0.5, 0.5, 1)
                    if flashing then t.ring:SetAlpha(1); t.ring:Show() else t.ring:Hide() end
                    t.shown = "boss"
                    -- the loaded model replaces the flat face
                    t.disc:SetAlpha(self.bossModelReady and 0 or 1)
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
                -- a damaged tough piece sheds a layer per hit: gold to steel
                -- (cracked), steel to a plain piece. An egg shows its cracks;
                -- the boss's bar shows its damage.
                if (p.maxhp or 1) > 1 and p.hp < p.maxhp and not p.lit and p.kind ~= "boss" then
                    if t.crackHp ~= p.hp then
                        t.crackHp = p.hp
                        local rimColor, cracked = toughLook(p.hp, p.maxhp)
                        if p.kind == "egg" then rimColor, cracked = nil, true end
                        if rimColor then
                            t.rim:SetVertexColor(rimColor[1], rimColor[2], rimColor[3], 1)
                            t.rim:Show()
                        else
                            t.rim:Hide()
                        end
                        t.crack:SetVertexColor(1, 1, 1, 1)
                        t.crack:SetAlpha(p.kind == "egg" and (p.hp <= 1 and 1 or 0.6) or 0.8)
                        t.crack:SetShown(cracked)
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

    -- colorblind mode: a mark on every unlit orange, green and purple piece
    local cbOn = GP:GetDB().colorblind == true
    if cbOn or self.cbShowing then
        self.cbShowing = cbOn
        for i, p in ipairs(st.pegs) do
            local t = self.pegTex[i]
            if t then self:ColorMark(t, p, cbOn) end
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
        -- just below the boss's body, kept on the board
        local y = math.min(b.y + E.BOSS_R + 10, E.FIELD_H - 8)
        placeAt(self.bossBg, field, b.x, y)
        self.bossFill:ClearAllPoints()
        self.bossFill:SetPoint("LEFT", self.bossBg, "LEFT", 1, 0)
        self.bossFill:SetWidth(math.max(1, 70 * math.max(0, b.hp) / b.maxhp))
        self.bossName:ClearAllPoints()
        self.bossName:SetPoint("TOP", self.bossBg, "BOTTOM", 0, -1)
        if (b.shield or 0) > 0 and not b.lit then
            -- its bottom edge across the boss's middle; dimmer with one hit left
            placeAt(self.bossShield, field, b.x, b.y - (E.BOSS_R + 12) / 2 + 2)
            local pulse = 0.5 + 0.5 * math.sin(now * 5)
            self.bossShield:SetAlpha((b.shield >= E.GOLEM_SHIELD and 0.75 or 0.4) + 0.25 * pulse)
            self.bossShield:Show()
        elseif self.bossShield:IsShown() then
            self.bossShield:Hide()
        end
        if (b.charge or 0) > 0 and not b.lit then
            placeAt(self.bossCharge, field, b.x, math.max(b.y - E.BOSS_R - 12, 8))
            self.bossCharge:SetText("CHARGE " .. b.charge)
            self.bossCharge:Show()
        elseif self.bossCharge:IsShown() then
            self.bossCharge:Hide()
        end
    elseif b and self.bossBg:IsShown() then
        self.bossBg:Hide(); self.bossFill:Hide(); self.bossName:Hide(); self.bossCharge:Hide(); self.bossShield:Hide()
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
            ART:Set(tex, ballSlot(ball, st, now, self.electricUntil))
            local size = ART:Size("ball", E.BALL_R * 2 + 2)
            local top = ball.y - size / 2
            -- in Fever a ball going into a tube is cut off at the tube's front lip
            local lip = E.FIELD_H - E.FEVER_TUBE_H + TUBE_LIP
            if st.phase == E.PHASE.FEVER and top + size > lip then
                local shown = lip - top
                if shown <= 0 then
                    tex:Hide()
                else
                    tex:SetSize(size, shown)
                    tex:SetTexCoord(0, 1, 0, shown / size)
                    tex:ClearAllPoints()
                    tex:SetPoint("TOP", field, "TOPLEFT", ball.x, -top)
                    tex:Show()
                end
            else
                if tex.cropped ~= false then
                    tex:SetSize(size, size)
                    tex:SetTexCoord(0, 1, 0, 1)
                end
                placeAt(tex, field, ball.x, ball.y)
                tex:Show()
            end
            tex.cropped = st.phase == E.PHASE.FEVER and top + size > lip
            if st.phase == E.PHASE.FEVER and ball.y < lip then
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
    -- the Fever tubes: unscored ones stand dim, scored ones light up and
    -- glow, so it is plain at a glance which are done
    if st.phase == E.PHASE.FEVER then
        local pulse = 0.65 + 0.35 * math.sin(now * 6)
        for i, bin in ipairs(self.bins) do
            local lit = st.binsLit[i] and true or false
            if bin.litShown ~= lit then
                bin.litShown = lit
                ART:Set(bin.tube, "fever_tube_" .. bin.letter .. (lit and "_lit" or ""))
                if lit then
                    bin.tube:SetVertexColor(1, 1, 1, 1)
                    bin.halo:Show(); bin.shine:Show()
                    bin.label:SetTextColor(1, 1, 1)
                else
                    bin.tube:SetVertexColor(UI.TUBE_DIM, UI.TUBE_DIM, UI.TUBE_DIM + 0.04, 1)
                    bin.halo:Hide(); bin.shine:Hide()
                    bin.label:SetTextColor(0.55, 0.55, 0.6)
                end
            end
            if lit then
                bin.halo:SetAlpha(0.55 + 0.45 * pulse)
                bin.shine:SetAlpha(0.35 * pulse)
            end
        end
    end

    if E.PyramidUp(st) and st.phase ~= E.PHASE.OVER then
        -- whole, then four stages of crumbling, one per strike
        local used = E.PYRAMID_STRIKES - st.pyramidHits
        local stage = math.min(4, math.ceil(used * 4 / E.PYRAMID_STRIKES))
        ART:Set(self.pyramidTex, stage <= 0 and "pyramid" or ("pyramid_crumble" .. stage))
        self.pyramidTex:Show()
        -- the bucket is parked under it, out of sight
        if self.bucket:IsShown() then self.bucket:Hide() end
        self.bucketUnderPyramid = true
    else
        self.pyramidTex:Hide()
        if self.bucketUnderPyramid then
            self.bucketUnderPyramid = nil
            if not st.noBucket and st.phase ~= E.PHASE.FEVER and st.phase ~= E.PHASE.OVER then self.bucket:Show() end
        end
    end
    for _, d in ipairs(self.pyramidPuffs) do
        if d.untilT then
            local f = 1 - (d.untilT - now) / d.dur
            if f >= 1 then
                d.untilT = nil
                d:Hide()
            else
                local s = d.size * (0.6 + 0.6 * f)
                d:SetSize(s, s * 0.6)
                d:SetAlpha(1 - f)
            end
        end
    end

    if self.bolt then self:DrawBolt(now) end

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
    -- a Suction Tube ball in flight: the tube sucks, and whooshes
    -- (from the moment it is armed, until the ball lands or it is disarmed unfired)
    local sucking = false
    if not st.noBucket then
        if st.phase == E.PHASE.AIM and st.armed == "suction" then sucking = true end
        if st.phase == E.PHASE.FLIGHT then
            if st.suctionShot and #st.balls > 0 then sucking = true end
        end
    end
    if sucking then
        local frame = math.floor(now * 28) % 16
        ART:Set(self.bucket, "bucket_suck")
        local c, r = frame % 4, math.floor(frame / 4)
        self.bucket:SetTexCoord(c / 4, (c + 1) / 4, r / 4, (r + 1) / 4)
        -- a big cartoon gulp on top: the tube stretches tall and squashes wide
        local k = 0.22 * math.sin(now * 2 * math.pi * 4.5)
        local size = E.BUCKET_W + 16
        self.bucket:SetSize(size * (1 - k), size * (1 + k))
        if not self.suckUntil or now >= self.suckUntil then
            local _, handle = GP:PlaySfx("suction.ogg")
            self.suckHandle = handle
            self.suckUntil = now + 2.0
        end
    elseif self.bucket.slot == "bucket_suck" then
        ART:Set(self.bucket, "bucket")
        self.bucket:SetTexCoord(0, 1, 0, 1)
        self.bucket:SetSize(E.BUCKET_W + 16, E.BUCKET_W + 16)
        if self.suckHandle and type(StopSound) == "function" then pcall(StopSound, self.suckHandle, 200) end
        self.suckHandle, self.suckUntil = nil, nil
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
    if strip > 10 then
        self.ballExtra:Show()
        self.ballStripMore:SetText(tostring(strip))
    else
        self.ballExtra:Hide()
        self.ballStripMore:SetText("")
    end
    ART:Set(self.goalIcon, ART:Goal(st.objective))
    if st.boss then
        self.goalText:SetText(math.max(0, st.boss.hp) .. " / " .. st.boss.maxhp)
    else
        self.goalText:SetText(st.goalLeft .. " / " .. st.goalTotal)
    end
    self:FitGoalLabel()
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
        status = ("%s (%d bounces): %d shot%s left"):format(st.crazyGuide and "Crazy Guide" or "Super Guide", E:GuideBounces(st), st.superGuide, st.superGuide == 1 and "" or "s")
    elseif st.power == "pyramid" and E.PyramidUp(st) then
        status = ("Pyramid: %d strike%s left"):format(st.pyramidHits, st.pyramidHits == 1 and "" or "s")
    end
    self.powerStatus:SetText(status)
    local s2, s3, s1 = starMarks(st)
    local live = L.StarsFromMarks(st.score, s2, s3, s1)
    setStars(self.sideStars, live, st.phase == E.PHASE.OVER and 1 or 0.6)
    self.starNeedText:SetText((s1 and ("1 star at %s, "):format(fmtBig(s1)) or "") .. ("2 stars at %s, 3 at %s"):format(fmtBig(s2), fmtBig(s3)))
end

function UI:UpdateDisplay()
    local db = GP:GetDB()
    local st = self.state
    if st then
        self.levelText:SetText(("Level %d / %d"):format(st.level, L.COUNT))
        self.chapterText:SetText("|cffaaddff" .. (st.name or "") .. "|r")
        self.layoutText:SetText(("Chapter %d  -  %s%s"):format(st.chapter,
            st.author and ("Level by " .. st.author) or (st.layout or ""), st.gimmick and ("  +  " .. st.gimmick) or ""))
        local objective = self:ObjectiveText(st)
        if st.boss then
            local def
            for _, d in ipairs(E.BOSSES) do if d.id == st.boss.ability then def = d end end
            if def then objective = objective .. "\n" .. def.blurb end
        end
        self.objectiveText:SetText(objective)
        ART:Set(self.goalLabel, GOAL_WORD[st.objective] or "word_goal_classic")
    self.chapterText:SetText("|cffaaddff" .. (st.title or st.name or "") .. "|r")
        local name, blurb = powerName(st.power)
        self.powerText:SetText("|cff88ff88" .. name .. "|r")
        self:ShowHostName(st.level)
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
    self.playsNum:SetText(tostring(free + bought))
    self.playsText:SetText("")
    styleButton(self.buyBtn, true, 0.5, 0.38, 0.1)
    self.gearsText:SetText(("|cffffd700Golden Gears: %d|r"):format(P:Gears()))
    for _, b in ipairs(self.shopBtns) do
        styleButton(b, P:Gears() >= P.SHOP[b.what].cost, 0.5, 0.38, 0.1)
    end
    styleButton(self.freeBtn, true, 0.2, 0.5, 0.25)
    self:RefreshTestFlyout()
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
