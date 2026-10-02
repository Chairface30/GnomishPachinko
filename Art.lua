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

-- How many per-world backdrops exist (field_bg_1.., map_bg_1..). A world
-- is ten chapters; worlds past the count wrap round.
ART.FIELD_BG_COUNT = 4      -- forest, canyon, cavern, snow
ART.MAP_BG_COUNT = 4

ART.PEG_COLORS = { "blue", "orange", "green", "purple" }
ART.PIECE_STATES = { "", "_lit", "_gone" }
ART.BALL_KINDS = { "ball", "ball_fire", "ball_electric", "ball_rainbow", "ball_wing", "ball_spooky" }
ART.BOSS_IDS = { "drake", "golem", "spider", "boar", "yeti" }
ART.POWER_IDS = { "multiball", "guide", "blast", "fireball", "spooky", "pyramid", "lightning", "frenzy" }
ART.ITEM_IDS = { "ring", "rainbow", "green" }
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
slot("crack",   64, 64,  { tint = true, note = "white crack lines, transparent elsewhere, over a damaged piece" })
slot("dot",     32, 32,  { tint = true, note = "a soft dot: aim guide, lightning bolt, map path" })
slot("star",    32, 32,  { tint = true, note = "a five-point star, gold when earned, grey when not" })
slot("blast",   128, 128, { tint = true, note = "a soft radial burst with ragged spikes: Space Blast, Ring of Fire" })
slot("pyramid", 256, 32, { note = "the golden trapezoid ramp of the Pyramid power" })
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
for i = 1, 4 do slot("bucket_splash" .. i, 128, 128, { note = "a catch: splash frame " .. i .. " of 4, drawn over the bucket" }) end
slot("fever_bucket",     128, 32, { note = "one Fever cup; the game writes the letter and value on it" })
slot("fever_bucket_lit", 128, 32, { note = "a Fever cup already scored" })
slot("fever_post",       32, 96,  { note = "a divider between two Fever cups: a brass post from the floor to the rim with a domed cap, drawn 18 by 41" })

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
for i = 1, ART.MAP_BG_COUNT do slot("map_bg_" .. i, 256, 512, { free = true, note = "map backdrop for world " .. i }) end
for i = 1, ART.FIELD_BG_COUNT do slot("field_bg_" .. i, 256, 512, { free = true, note = "board backdrop for world " .. i }) end
slot("minimap", 64, 64, { note = "the minimap button" })

section("Effects")
for i = 1, 4 do slot("spark" .. i, 64, 64, { tint = true, note = "sparkle burst frame " .. i .. " of 4" }) end
slot("confetti",  64, 64,   { note = "a few bits of confetti" })
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
    local map = { classic = "orange", eggs = "egg", gems = "gem", boss = "boss", duel = "duel", longshots = "longshot" }
    return "goal_" .. (map[objective] or "orange")
end
function ART:World(level)
    local chapter = math.floor(((level or 1) - 1) / 10) + 1
    return math.floor((chapter - 1) / 10) + 1
end
function ART:FieldBackdrop(level) return "field_bg_" .. (((self:World(level) - 1) % self.FIELD_BG_COUNT) + 1) end
function ART:MapBackdrop(chapter)
    local world = math.floor((chapter - 1) / 10) + 1
    return "map_bg_" .. (((world - 1) % self.MAP_BG_COUNT) + 1)
end
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

function ART:TintSkin(s, r, g, b, a)
    for _, t in ipairs(s.pieces) do t:SetVertexColor(r, g, b, a or 1) end
end

function ART:ShowSkin(s, shown)
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
