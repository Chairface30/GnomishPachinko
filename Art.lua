--[[
    Gnomish Pachinko - Art.lua
    The one list of everything the game draws. Every picture is a named
    slot with its file in Textures/, its size, and whether the game tints
    it. The window never names a file itself: it asks here, so a finished
    sprite dropped into Textures/ under the slot's name is used with no
    code change. tools/make_textures.py writes a placeholder for every
    slot, tools/cut_sheet.py slices a sprite sheet into them, and
    tests/engine_test.py checks the folder against this list.

    Slot fields:
      file   the file name without .tga (defaults to the slot name)
      w, h   the texture's size (power of two)
      tint   true: painted in white and greys, the game multiplies in a
             colour. Otherwise full colour and drawn as painted.
      fill   for pieces: the share of the canvas the body fills (0.7),
             so halos and shards in the lit and gone states have room.
             The game draws the texture at piece size / fill.
      inset  a 9-slice skin: the border's width in the texture, and
      edge   how wide that border is drawn on screen
      free   any power-of-two size is fine (backdrops)
      source only read by the tools (never drawn): a white base the
             per-colour set is derived from
]]

local GP = GnomishPachinko
GP.Art = GP.Art or {}
local ART = GP.Art

ART.PATH = "Interface\\AddOns\\GnomishPachinko\\Textures\\"
ART.WHITE = "Interface\\Buttons\\WHITE8x8"

-- Every chapter has its own map backdrop, board backdrop and boss arena,
-- painted for its zone (map_bg_<chapter>, field_bg_<chapter>, field_boss_<chapter>).
ART.CHAPTERS = 40

ART.PEG_COLORS = { "blue", "orange", "green", "purple" }
ART.PIECE_STATES = { "", "_lit", "_gone" }
ART.BALL_KINDS = { "ball", "ball_fire", "ball_electric", "ball_rainbow", "ball_wing", "ball_spooky" }
ART.BOSS_IDS = { "drake", "golem", "spider", "boar", "yeti" }
ART.POWER_IDS = { "multiball", "guide", "blast", "fireball", "spooky", "pyramid", "lightning", "frenzy" }
ART.ITEM_IDS = { "ring", "rainbow", "green", "suction" }
ART.GOAL_IDS = { "orange", "egg", "gem", "boss", "duel", "longshot" }
ART.BUTTON_SKINS = { "green", "orange", "grey" }

ART.SLOTS = {}
ART.ORDER = {}
ART.GROUPS = {}

local group
local function slot(name, w, h, opts)
    local def = opts or {}
    def.name = name
    def.file = def.file or name
    def.w, def.h = w, h
    def.group = group
    ART.SLOTS[name] = def
    ART.ORDER[#ART.ORDER + 1] = name
    return def
end
local function section(title)
    group = title
    ART.GROUPS[#ART.GROUPS + 1] = title
end

-- ===== tinted base pieces and the tool's sources =====
section("Base pieces (tinted)")
slot("peg",     64, 64,  { tint = true, fill = 0.7, source = true, note = "a white domed disc: the per-colour pegs are derived from it" })
slot("brick",   64, 32,  { tint = true, fill = 0.9, source = true, note = "a white rounded bar lit from the top; stretches to any length" })
slot("key",     64, 64,  { tint = true, fill = 0.8, source = true, note = "a white key, bow at the top" })
slot("boss",    64, 64,  { tint = true, fill = 0.7, source = true, note = "a white round mechanical face with gear teeth" })
slot("ring",    64, 64,  { tint = true, note = "the soft glow halo a lit piece wears" })
slot("rim",     64, 64,  { tint = true, note = "a thin metal band at the edge: steel and gold tough pieces, the boss's shield, the minimap ring" })
slot("boss_shield", 128, 64, { tint = true, note = "a glowing half dome, open side down: the Bolt Golem's shield over the top of its body" })
slot("crack",   64, 64,  { tint = true, note = "white crack lines, transparent elsewhere, over a damaged piece" })
slot("word_objective", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_power", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_balls", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_score", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_multiplier", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_combo", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_best", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_next_free_ball", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_stars", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_goal_classic", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_goal_eggs", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_goal_gems", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_goal_boss", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_goal_longshots", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_goal_mixed", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("word_shop", 512, 64, { note = "side panel heading in brass word-art (tools/word_art.py): cog for O, piston for I" })
slot("btn_next",    512, 64, { note = "Next Level: green enamel plate, riveted brass rim, chevrons in a porthole (tools/word_art.py)" })
slot("btn_restart", 512, 64, { note = "Restart: copper-red enamel plate, a turning arrow in a porthole (tools/word_art.py)" })
slot("btn_levels",  512, 64, { note = "Level Select: blue enamel plate, a little map in a porthole (tools/word_art.py)" })
slot("btn_logo",    512, 64, { inset = 28, edge = 16, note = "a blank logo plate (cog end-caps, copper plate) for buttons whose words change; 9-slice so the caps keep their shape at any width (tools/word_art.py)" })
slot("btn_logo_small", 512, 64, { file = "btn_logo", inset = 28, edge = 10, note = "the blank logo plate for short buttons (same picture, narrower ends)" })
slot("star_big",         256, 256, { note = "the result card's middle star, gold and bevelled (tools/word_art.py)" })
slot("star_big_l",       256, 256, { note = "the result card's left star, tipped out (tools/word_art.py)" })
slot("star_big_r",       256, 256, { note = "the result card's right star, tipped out (tools/word_art.py)" })
slot("star_big_empty",   256, 256, { note = "the middle star's empty slate socket (tools/word_art.py)" })
slot("star_big_l_empty", 256, 256, { note = "the left star's empty socket (tools/word_art.py)" })
slot("star_big_r_empty", 256, 256, { note = "the right star's empty socket (tools/word_art.py)" })
slot("word_plays_left", 512, 64, { note = "PLAYS LEFT in brass word-art beside the plays counter (tools/word_art.py)" })
slot("plate_cap", 128, 256, { note = "a plate button's end: the left half of a brass cog, the button's full height; mirrored for the right end (tools/word_art.py)" })
slot("plate_mid", 64, 128,  { note = "a plate button's middle: the logo's copper plate, stretched only sideways (tools/word_art.py)" })
slot("comic_arrow", 256, 128, { note = "a comically fat cartoon arrow pointing right, thick black outline, hot orange (tools/word_art.py); the tutorials turn it to point at buttons" })
slot("play_token",   128, 128, { note = "a play: a brass pachinko token with a cog rim and a silver ball set in it (tools/word_art.py)" })
slot("number_frame", 128, 64,  { note = "a riveted brass frame with a dark window for a number (tools/word_art.py)" })
slot("shop_gear", 128, 128, { note = "the shop button: a shiny golden gear (tools/word_art.py)" })
slot("dot",     32, 32,  { tint = true, note = "a soft dot: aim guide, lightning bolt, map path" })
slot("star",    32, 32,  { tint = true, note = "a five-point star, gold when earned, grey when not" })
slot("blast",   128, 128, { tint = true, note = "a soft radial burst with ragged spikes: Space Blast, Ring of Fire" })
slot("pyramid", 512, 128, { note = "the Pyramid power: a sandstone step pyramid, five tiers under a pointed gold capstone, base across the full width, tip at the top centre" })
for i = 1, 4 do
    slot("pyramid_crumble" .. i, 512, 128, { note = "the step pyramid after " .. i .. " of its 5 strikes: chipped steps and cracks, more broken at each stage" })
end
slot("pyramid_dust", 128, 128, { note = "a billowing cloud of sandstone dust and grit, soft-edged: Pyramid strikes and its collapse" })
slot("icon",    64, 64,  { note = "the addon list icon" })

-- ===== gameplay pieces, one file a look =====
section("Pegs and bricks")
for _, c in ipairs(ART.PEG_COLORS) do
    slot("peg_" .. c,           64, 64, { fill = 0.7, note = c .. " peg" })
    slot("peg_" .. c .. "_lit", 64, 64, { fill = 0.7, note = c .. " peg, hit: brighter with a halo" })
    slot("peg_" .. c .. "_gone", 64, 64, { fill = 0.7, note = c .. " peg vanishing: shards or a burst" })
end
for _, c in ipairs(ART.PEG_COLORS) do
    slot("brick_" .. c,           64, 32, { fill = 0.9, note = c .. " brick, stretched to its length" })
    slot("brick_" .. c .. "_lit", 64, 32, { fill = 0.9, note = c .. " brick, hit" })
    slot("brick_" .. c .. "_gone", 64, 32, { fill = 0.9, note = c .. " brick vanishing" })
end
slot("bumper",      64, 64, { fill = 0.7, note = "a star bumper: throws the ball back harder" })
slot("block",       64, 64, { fill = 0.7, note = "a round solid steel block: never lights" })
slot("boss_platform", 128, 128, { note = "a round gnomish hover platform seen from straight above: a circle with a brass rim, riveted steel deck, a soft blue glow round the edge. The boss's model stands on it" })
slot("web",         64, 64, { fill = 0.7, note = "a round silvery spider web, spokes and rings, the Gyro Spider's: catches a ball" })
slot("rail",        64, 32, { fill = 0.9, note = "a solid grey steel bar with end caps: never lights" })
slot("cage_gold",   64, 32, { fill = 0.9, note = "one gold bar of a key cage, stretched like a brick" })
slot("cage_silver", 64, 32, { fill = 0.9, note = "one silver bar of a key cage" })
slot("key_gold",    64, 64, { fill = 0.8, note = "the gold key" })
slot("key_silver",  64, 64, { fill = 0.8, note = "the silver key" })

section("Eggs, gems and bosses")
slot("egg",         64, 64, { fill = 0.8, note = "a whole egg, slightly pointed top" })
slot("egg_cracked", 64, 64, { fill = 0.8, note = "the egg after a hit" })
slot("egg_hatched", 64, 64, { fill = 0.8, note = "the egg hatching, shown while it fades" })
slot("gem",         64, 64, { fill = 0.8, note = "a faceted cut gem; spins while it falls" })
for _, id in ipairs(ART.BOSS_IDS) do
    slot("boss_" .. id, 64, 64, { fill = 0.7, note = "boss face: " .. id })
end

section("Balls")
slot("ball",          64, 64, { fill = 0.8, note = "the plain chrome ball" })
slot("ball_fire",     64, 64, { fill = 0.8, note = "Fireball and Ring of Fire" })
slot("ball_electric", 64, 64, { fill = 0.8, note = "the ball after Chain Lightning fires" })
slot("ball_rainbow",  64, 64, { fill = 0.8, note = "Rainbow Ball" })
slot("ball_wing",     64, 64, { fill = 0.8, note = "the leftover balls fired in Fever" })
slot("ball_spooky",   64, 64, { fill = 0.8, note = "Spooky Ball" })
slot("ball_small",    32, 32, { note = "one ball of the balls-left strip" })

section("Launcher and bucket")
slot("launcher_barrel", 32, 64, { note = "the cannon nozzle, drawn pointing down; rotates with the aim" })
slot("launcher_hub",    64, 64, { note = "the pivot plate at the top centre" })
slot("launcher_flash",  64, 64, { tint = true, note = "the muzzle flash on launch" })
slot("bucket",          128, 128, { note = "the free-ball bucket (a nest, a pot, whatever the world wants); its rim at the top third" })
slot("bucket_suck", 512, 512, { frames = 16, cols = 4, note = "the tube sucking: a 4 by 4 sheet of 16 frames, played while a Suction Tube ball is in flight" })
for i = 1, 4 do slot("bucket_splash" .. i, 128, 128, { note = "a catch: splash frame " .. i .. " of 4, drawn over the bucket" }) end
slot("fever_tube",       128, 128, { source = true, note = "the mouth of a brass vacuum tube, opening up: the source the five lettered tubes are drawn from" })
for _, letter in ipairs({ "g", "n", "o", "m", "e" }) do
    slot("fever_tube_" .. letter,          128, 128, { note = "the " .. letter:upper() .. " Fever tube, its letter on it" })
    slot("fever_tube_" .. letter .. "_lit", 128, 128, { note = "the " .. letter:upper() .. " Fever tube, scored: lit up" })
end
slot("fever_balloon",    64, 64,  { fill = 0.8, note = "the inflated balloon bumper resting between two Fever cups; it squashes when hit" })

section("Icons")
for _, id in ipairs(ART.POWER_IDS) do slot("power_" .. id, 64, 64, { note = "power icon: " .. id }) end
for _, id in ipairs(ART.ITEM_IDS) do slot("item_" .. id, 64, 64, { note = "power-up icon: " .. id }) end
for _, id in ipairs(ART.GOAL_IDS) do slot("goal_" .. id, 32, 32, { note = "objective icon: " .. id }) end

section("HUD, cards and map")
slot("frame_bg",  512, 512, { inset = 60, edge = 40, note = "the window's copper plate, 9-slice: the painted border is the outer 60 px, drawn 40" })
slot("plate",     256, 64,  { inset = 16, edge = 8, note = "an inset plate behind a readout" })
slot("card",      512, 512, { inset = 60, edge = 36, note = "the card: level start, result, out of plays; 9-slice, border the outer 60 px, drawn 36" })
for _, c in ipairs(ART.BUTTON_SKINS) do
    slot("button_" .. c,           256, 64, { inset = 16, edge = 8, note = c .. " button" })
    slot("button_" .. c .. "_down", 256, 64, { inset = 16, edge = 8, note = c .. " button, pressed" })
end
slot("gauge",      256, 64, { inset = 16, edge = 6, note = "the multiplier bar's trough, 9-slice" })
slot("gauge_fill", 256, 64, { note = "its rainbow fill, a glossy bar; the game clips it left to right by progress" })
slot("logo",       512, 128, { note = "the game's logo, top left of the window" })
slot("portrait_frame", 128, 128, { note = "the round copper frame round Tinkmaster's box at the top centre; hollow middle" })
slot("banner",     512, 64, { note = "a ribbon behind the big callouts" })
slot("callout_fever", 512, 128, { note = "the FEVER! callout graphic (text baked in)" })
slot("map_node",        64, 64, { note = "an open level node" })
slot("map_node_done",   64, 64, { note = "a cleared level node" })
slot("map_node_locked", 64, 64, { note = "a locked level node" })
slot("map_node_boss",   64, 64, { note = "the boss node, larger and ringed" })
for i = 1, ART.CHAPTERS do slot("map_bg_" .. i, 256, 512, { free = true, note = "map backdrop for chapter " .. i }) end
for i = 1, ART.CHAPTERS do slot("field_bg_" .. i, 256, 512, { free = true, note = "board backdrop for chapter " .. i }) end
for i = 1, ART.CHAPTERS do slot("field_boss_" .. i, 256, 512, { free = true, note = "the boss arena of chapter " .. i }) end
slot("minimap", 64, 64, { note = "the minimap button" })

section("Effects")
for i = 1, 4 do slot("spark" .. i, 64, 64, { tint = true, note = "sparkle burst frame " .. i .. " of 4" }) end
slot("confetti",  64, 64,   { note = "a few bits of confetti" })
slot("phoenix",   128, 128, { note = "the phoenix a hatched egg releases, wings spread, flying straight up" })
slot("firework",  128, 128, { tint = true, note = "a burst for the GNOME bonus" })
slot("trail",     64, 16,   { note = "one segment of the ball's rainbow ribbon" })
slot("glow_soft", 128, 128, { tint = true, note = "a soft radial glow: the last-peg zoom, the boss's hit flash" })

-- ---------------------------------------------------------------------

function ART:Def(name)
    return self.SLOTS[name] or error("no art slot " .. tostring(name))
end

function ART:File(name)
    return self.PATH .. self:Def(name).file
end

-- The size to draw a piece of w x h so its body comes out that big.
function ART:Size(name, w, h)
    local f = self:Def(name).fill or 1
    return w / f, (h or w) / f
end

-- Sets a texture to a slot. Tinted slots take the colour; full-colour
-- slots are drawn white (alpha kept). The slot name is remembered on the
-- texture so the tests and a repaint can see it.
function ART:Set(tex, name, r, g, b, a)
    local def = self:Def(name)
    if tex.slot ~= name then
        tex:SetTexture(self.PATH .. def.file)
        tex.slot = name
    end
    if def.tint then tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    else tex:SetVertexColor(1, 1, 1, a or 1) end
end

-- A texture sized for a piece: SetSize from the slot's fill.
function ART:SetPiece(tex, name, w, h, r, g, b, a)
    self:Set(tex, name, r, g, b, a)
    tex:SetSize(self:Size(name, w, h))
end

-- Slot names for the pieces.
function ART:Peg(color, state)
    local name = "peg_" .. (self.SLOTS["peg_" .. color] and color or "blue") .. (state or "")
    return self.SLOTS[name] and name or ("peg_" .. color)
end
function ART:Brick(color, state)
    local name = "brick_" .. (self.SLOTS["brick_" .. color] and color or "blue") .. (state or "")
    return self.SLOTS[name] and name or ("brick_" .. color)
end
function ART:Boss(id) return self.SLOTS["boss_" .. tostring(id)] and ("boss_" .. id) or "boss_drake" end
function ART:Power(id) return self.SLOTS["power_" .. tostring(id)] and ("power_" .. id) or "power_multiball" end
function ART:Item(id) return self.SLOTS["item_" .. tostring(id)] and ("item_" .. id) or "item_ring" end
function ART:Goal(objective)
    local map = { classic = "orange", eggs = "egg", gems = "gem", boss = "boss", duel = "duel", longshots = "longshot",
        mixed_eggs = "egg", mixed_gems = "gem" }
    return "goal_" .. (map[objective] or "orange")
end
function ART:Chapter(level)
    local chapter = math.floor(((level or 1) - 1) / 10) + 1
    return ((chapter - 1) % self.CHAPTERS) + 1
end
-- The board's backdrop: the chapter's, or its boss arena on the tenth level.
function ART:FieldBackdrop(level)
    local chapter = self:Chapter(level)
    if (level or 1) % 10 == 0 then return "field_boss_" .. chapter end
    return "field_bg_" .. chapter
end
function ART:MapBackdrop(chapter) return "map_bg_" .. (((chapter - 1) % self.CHAPTERS) + 1) end
function ART:Frames(prefix, n)
    local list = {}
    for i = 1, n do list[i] = prefix .. i end
    return list
end

-- ---------------------------------------------------------------------
-- Skins: a 9-slice (or one stretched texture) over a frame.

local GRID = {
    { "TOPLEFT", "TOP", "TOPRIGHT" },
    { "LEFT", "CENTER", "RIGHT" },
    { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
}

-- The pieces are created on `parent` and laid out over `anchor` (the
-- parent itself unless given: a plate behind text on the same frame).
function ART:NewSkin(parent, name, layer, sub, anchor)
    local s = { parent = anchor or parent, pieces = {} }
    for i = 1, 9 do s.pieces[i] = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0) end
    self:SetSkin(s, name)
    return s
end

-- Lays the nine pieces out: fixed-size corners, stretching edges and
-- middle. A slot without an inset is one stretched texture.
function ART:SetSkin(s, name, r, g, b, a)
    if s.plate then return end      -- a plate keeps its pieces; only tints change
    local def = self:Def(name)
    local parent = s.parent
    local inset, edge = def.inset or 0, def.edge or def.inset or 0
    local u, v = inset / def.w, inset / def.h
    local cols = { { 0, u }, { u, 1 - u }, { 1 - u, 1 } }
    local rows = { { 0, v }, { v, 1 - v }, { 1 - v, 1 } }
    s.name = name
    local k = 0
    for ri = 1, 3 do
        for ci = 1, 3 do
            k = k + 1
            local t = s.pieces[k]
            t:ClearAllPoints()
            if inset == 0 and k ~= 5 then
                t:Hide()
            else
                t:Show()
                self:Set(t, name, r, g, b, a)
                if inset == 0 then
                    t:SetTexCoord(0, 1, 0, 1)
                    t:SetAllPoints(parent)
                else
                    t:SetTexCoord(cols[ci][1], cols[ci][2], rows[ri][1], rows[ri][2])
                    local corner = (ri ~= 2) and (ci ~= 2)
                    if corner then
                        t:SetSize(edge, edge)
                        t:SetPoint(GRID[ri][ci], parent, GRID[ri][ci], 0, 0)
                    elseif ri == 2 and ci == 2 then
                        t:SetPoint("TOPLEFT", parent, "TOPLEFT", edge, -edge)
                        t:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -edge, edge)
                    elseif ri == 2 then
                        -- left or right edge
                        t:SetWidth(edge)
                        t:SetPoint("TOP" .. GRID[2][ci], parent, "TOP" .. GRID[2][ci], 0, -edge)
                        t:SetPoint("BOTTOM" .. GRID[2][ci], parent, "BOTTOM" .. GRID[2][ci], 0, edge)
                    else
                        -- top or bottom edge
                        t:SetHeight(edge)
                        t:SetPoint(GRID[ri][1], parent, GRID[ri][1], edge, 0)
                        t:SetPoint(GRID[ri][3], parent, GRID[ri][3], -edge, 0)
                    end
                end
            end
        end
    end
end

-- A plate: two half-gear ends that keep their true shape at any height
-- (each as wide as half the button's height) and a copper middle between
-- them that stretches only sideways. It answers to TintSkin like a skin.
function ART:NewPlate(parent, layer, h)
    local s = { parent = parent, pieces = {}, plate = true, name = "btn_logo" }
    local cap = h * 0.5
    local mid = parent:CreateTexture(nil, layer or "BACKGROUND", nil, 0)
    self:Set(mid, "plate_mid")
    mid:SetPoint("TOPLEFT", parent, "TOPLEFT", cap * 0.6, 0)
    mid:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -cap * 0.6, 0)
    local left = parent:CreateTexture(nil, layer or "BACKGROUND", nil, 1)
    self:Set(left, "plate_cap")
    left:SetSize(cap, h)
    left:SetPoint("LEFT", parent, "LEFT", 0, 0)
    local right = parent:CreateTexture(nil, layer or "BACKGROUND", nil, 1)
    self:Set(right, "plate_cap")
    right:SetSize(cap, h)
    right:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    if right.SetTexCoord then right:SetTexCoord(1, 0, 0, 1) end
    s.pieces = { left, mid, right }
    return s
end

function ART:TintSkin(s, r, g, b, a)
    for _, t in ipairs(s.pieces) do t:SetVertexColor(r, g, b, a or 1) end
end

function ART:ShowSkin(s, shown)
    if s.plate then
        for _, t in ipairs(s.pieces) do if shown then t:Show() else t:Hide() end end
        return
    end
    local def = self:Def(s.name)
    for k, t in ipairs(s.pieces) do
        if shown and ((def.inset or 0) > 0 or k == 5) then t:Show() else t:Hide() end
    end
end

-- The button skin for a colour the old code asked for (r, g, b).
function ART:ButtonSkin(r, g, b)
    if g > r and g > b then return "green" end
    if r > g and r > b then return "orange" end
    return "grey"
end

-- Everything, for a report: name, file, size, tint, note.
function ART:List()
    local out = {}
    for _, name in ipairs(self.ORDER) do out[#out + 1] = self.SLOTS[name] end
    return out
end
