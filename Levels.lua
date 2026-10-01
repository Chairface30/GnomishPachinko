--[[
    Gnomish Pachinko - Levels.lua
    1000 levels generated from their number alone. Level n gets a seed,
    a chapter (ten levels each, named after a place in Azeroth), a layout
    family, counts that climb with n, and the chapter's power.

    Generators call add(peg) for every piece they want; add rejects pieces
    outside the zone or too close to one already placed, except within the
    same `group` (brick chains touch on purpose).
]]

local GP = GnomishPachinko
local E = GP.Engine
GP.Levels = GP.Levels or {}
local L = GP.Levels

L.COUNT = 1000
L.PER_CHAPTER = 10

local W = E.FIELD_W
local sin, cos, floor, sqrt, pi = math.sin, math.cos, math.floor, math.sqrt, math.pi

L.CHAPTERS = {
    "Elwynn Forest", "Durotar", "Dun Morogh", "Mulgore", "Teldrassil", "Tirisfal Glades",
    "Westfall", "Loch Modan", "Darkshore", "Silverpine Forest", "The Barrens", "Redridge Mountains",
    "Stonetalon Mountains", "Ashenvale", "Duskwood", "Wetlands", "Hillsbrad Foothills", "Thousand Needles",
    "Alterac Mountains", "Arathi Highlands", "Desolace", "Stranglethorn Vale", "Dustwallow Marsh", "Badlands",
    "Swamp of Sorrows", "Feralas", "The Hinterlands", "Tanaris", "Searing Gorge", "Azshara",
    "Blasted Lands", "Un'Goro Crater", "Felwood", "Burning Steppes", "Western Plaguelands", "Eastern Plaguelands",
    "Winterspring", "Deadwind Pass", "Silithus", "Moonglade", "Hellfire Peninsula", "Zangarmarsh",
    "Terokkar Forest", "Nagrand", "Blade's Edge Mountains", "Netherstorm", "Shadowmoon Valley", "Isle of Quel'Danas",
    "Eversong Woods", "Ghostlands", "Azuremyst Isle", "Bloodmyst Isle", "The Deadmines", "Wailing Caverns",
    "Shadowfang Keep", "Blackfathom Deeps", "The Stockade", "Gnomeregan", "Razorfen Kraul", "Scarlet Monastery",
    "Uldaman", "Zul'Farrak", "Maraudon", "The Sunken Temple", "Blackrock Depths", "Lower Blackrock Spire",
    "Upper Blackrock Spire", "Dire Maul", "Stratholme", "Scholomance", "Molten Core", "Onyxia's Lair",
    "Blackwing Lair", "Zul'Gurub", "Ruins of Ahn'Qiraj", "Temple of Ahn'Qiraj", "Naxxramas", "Hellfire Ramparts",
    "The Blood Furnace", "The Shattered Halls", "The Slave Pens", "The Underbog", "The Steamvault", "Mana-Tombs",
    "Auchenai Crypts", "Sethekk Halls", "Shadow Labyrinth", "The Mechanar", "The Botanica", "The Arcatraz",
    "Old Hillsbrad", "The Black Morass", "Magtheridon's Lair", "Gruul's Lair", "Karazhan", "Serpentshrine Cavern",
    "Tempest Keep", "Mount Hyjal", "Black Temple", "Sunwell Plateau",
}

-- ---------------------------------------------------------------------
-- Piece factories

local function peg(x, y) return { shape = "peg", x = x, y = y } end
local function brick(x, y, angle, w, h)
    return { shape = "brick", x = x, y = y, angle = angle or 0, w = w or E.BRICK_W, h = h or E.BRICK_H }
end

-- A chain of touching bricks along a curve f(t) -> x, y for t in [0, 1].
local function brickCurve(add, f, count, group, rng, skip)
    local prevx, prevy
    for k = 0, count do
        local t = k / count
        local x, y = f(t)
        if prevx then
            local mx, my = (x + prevx) / 2, (y + prevy) / 2
            local ang = math.atan2 and math.atan2(y - prevy, x - prevx) or math.atan(y - prevy, x - prevx)
            local len = sqrt((x - prevx) ^ 2 + (y - prevy) ^ 2)
            if not (skip and rng() < skip) then
                add(brick(mx, my, ang, len + 1, E.BRICK_H), group)
            end
        end
        prevx, prevy = x, y
    end
end

-- ---------------------------------------------------------------------
-- Layout families. Each gets (rng, add, d) where d is difficulty 0..1.

local FAMILIES = {}

FAMILIES[#FAMILIES + 1] = { name = "Brickwork", build = function(rng, add, d)
    local rows = 6 + floor(d * 2)
    local cols = 9
    local spacing = (W - 2 * E.PEG_MARGIN) / (cols - 1)
    for r = 0, rows - 1 do
        local y = 150 + (470 - 150) * r / (rows - 1)
        local offset = (r % 2) * spacing / 2
        local n = (r % 2 == 0) and cols or cols - 1
        for c = 0, n - 1 do
            if rng() > 0.12 then add(peg(E.PEG_MARGIN + offset + c * spacing, y)) end
        end
    end
end }

FAMILIES[#FAMILIES + 1] = { name = "Rainbow", build = function(rng, add, d)
    local cx, cy = W / 2, 760
    local radii = { 300, 380, 460, 540 }
    for i, rad in ipairs(radii) do
        local reach = (W / 2 - E.PEG_MARGIN) / rad
        if reach > 1 then reach = 1 end
        local tmax = math.asin(reach)
        if d > 0.4 and i % 2 == 0 then
            -- outer arcs as brick curves on harder levels
            local function f(t)
                local a = -tmax + 2 * tmax * t
                return cx + rad * sin(a), cy - rad * cos(a)
            end
            brickCurve(add, f, floor(rad * 2 * tmax / 32), "arc" .. i, rng, 0.15)
        else
            local n = floor(rad * 2 * tmax / 44) + 1
            for k = 0, n - 1 do
                local a = -tmax + 2 * tmax * k / (n - 1)
                add(peg(cx + rad * sin(a), cy - rad * cos(a)))
            end
        end
    end
    for _, x in ipairs({ W / 2 - 110, W / 2, W / 2 + 110 }) do add(peg(x, 160)) end
end }

FAMILIES[#FAMILIES + 1] = { name = "Diamonds", build = function(rng, add, d)
    local function diamond(cx, cy, half, perEdge)
        local corners = { { 0, -half }, { half, 0 }, { 0, half }, { -half, 0 } }
        for e = 1, 4 do
            local a, b = corners[e], corners[e % 4 + 1]
            for k = 0, perEdge - 1 do
                local f = k / perEdge
                add(peg(cx + a[1] + (b[1] - a[1]) * f, cy + a[2] + (b[2] - a[2]) * f))
            end
        end
    end
    diamond(110, 330, 85, 3)
    diamond(W / 2, 250, 100, 4)
    diamond(W - 110, 330, 85, 3)
    for c = 0, 6 do add(peg(60 + c * (W - 120) / 6, 475)) end
    add(peg(W / 2, 410))
end }

FAMILIES[#FAMILIES + 1] = { name = "Rings", build = function(rng, add, d)
    local cx, cy = W / 2, 300
    for _, ring in ipairs({ { r = 125, n = 16 }, { r = 62, n = 8 } }) do
        local spin = rng() * pi
        for k = 0, ring.n - 1 do
            local a = spin + 2 * pi * k / ring.n
            add(peg(cx + ring.r * cos(a), cy + ring.r * sin(a)))
        end
    end
    add(peg(cx, cy))
    for r = 0, 6 do
        local y = 150 + r * 55
        add(peg(E.PEG_MARGIN + 8, y))
        add(peg(W - E.PEG_MARGIN - 8, y))
    end
    for c = 0, 5 do add(peg(100 + c * (W - 200) / 5, 480)) end
end }

FAMILIES[#FAMILIES + 1] = { name = "Zigzag", build = function(rng, add, d)
    local shelves = 5
    for s = 0, shelves - 1 do
        local y0 = 140 + s * 80
        local leftToRight = (s % 2 == 0)
        if d > 0.5 and s % 2 == 1 then
            local function f(t)
                local x = E.PEG_MARGIN + 10 + t * (W - 2 * E.PEG_MARGIN - 20)
                return x, y0 + (leftToRight and t or (1 - t)) * 46
            end
            brickCurve(add, f, 12, "shelf" .. s, rng, 0.2)
        else
            local n = 9
            for k = 0, n - 1 do
                local f = k / (n - 1)
                local x = E.PEG_MARGIN + 10 + f * (W - 2 * E.PEG_MARGIN - 20)
                add(peg(x, y0 + (leftToRight and f or (1 - f)) * 46))
            end
        end
    end
end }

FAMILIES[#FAMILIES + 1] = { name = "Brick Arcs", build = function(rng, add, d)
    -- two or three smiles of touching bricks, scatter between
    local arcs = 2 + (d > 0.3 and 1 or 0)
    for i = 1, arcs do
        local cx = W / 2 + (rng() - 0.5) * 200
        local cy = 140 + i * 110 + rng() * 30
        local rad = 90 + rng() * 60
        local spread = 0.5 + rng() * 0.5
        local function f(t)
            local a = pi / 2 - spread * pi / 2 + spread * pi * t
            return cx + rad * cos(a), cy - 60 + rad * sin(a)
        end
        brickCurve(add, f, floor(rad * spread * pi / 31), "arc" .. i, rng, 0.1)
    end
    for k = 1, 10 do
        add(peg(E.PEG_MARGIN + rng() * (W - 2 * E.PEG_MARGIN), 140 + rng() * 340))
    end
end }

FAMILIES[#FAMILIES + 1] = { name = "Brick Walls", build = function(rng, add, d)
    local rows = 4 + (d > 0.5 and 1 or 0)
    for r = 0, rows - 1 do
        local y = 160 + r * (330 / (rows - 1))
        local gapAt = rng(1, 4)
        local x0 = E.PEG_MARGIN + rng() * 30
        for seg = 1, 5 do
            if seg ~= gapAt then
                local len = 70
                local x = x0 + (seg - 1) * 94 + len / 2
                if x + len / 2 <= W - E.PEG_MARGIN then
                    add(brick(x, y, 0, len, E.BRICK_H), "wall" .. r)
                end
            end
        end
    end
    for k = 1, 12 do
        add(peg(E.PEG_MARGIN + rng() * (W - 2 * E.PEG_MARGIN), 130 + rng() * 360))
    end
end }

FAMILIES[#FAMILIES + 1] = { name = "Spiral", build = function(rng, add, d)
    local cx, cy = W / 2, 310
    local turns = 2.2 + d
    local n = floor(28 + d * 16)
    for k = 0, n - 1 do
        local t = k / (n - 1)
        local a = t * turns * 2 * pi + rng() * 0.1
        local rad = 25 + t * 170
        add(peg(cx + rad * cos(a), cy + rad * sin(a) * 0.95))
    end
    for c = 0, 4 do add(peg(80 + c * (W - 160) / 4, 140)) end
end }

FAMILIES[#FAMILIES + 1] = { name = "Waves", build = function(rng, add, d)
    local rows = 4
    local phase = rng() * pi
    for r = 0, rows - 1 do
        local y0 = 170 + r * 100
        local n = 10
        for k = 0, n - 1 do
            local f = k / (n - 1)
            local x = E.PEG_MARGIN + f * (W - 2 * E.PEG_MARGIN)
            local y = y0 + sin(f * 2 * pi + phase + r) * 30
            add(peg(x, y))
        end
    end
end }

FAMILIES[#FAMILIES + 1] = { name = "Hourglass", build = function(rng, add, d)
    local function f1(t) return 70 + t * (W - 140), 150 + t * 320 end
    local function f2(t) return W - 70 - t * (W - 140), 150 + t * 320 end
    brickCurve(add, f1, 11, "x1", rng, 0.12)
    brickCurve(add, f2, 11, "x2", rng, 0.12)
    for k = 1, 14 do
        add(peg(E.PEG_MARGIN + rng() * (W - 2 * E.PEG_MARGIN), 130 + rng() * 360))
    end
end }

FAMILIES[#FAMILIES + 1] = { name = "Honeycomb", build = function(rng, add, d)
    local spacing = 44
    local rowH = spacing * 0.866
    local rows = floor((E.PEG_BOTTOM - E.PEG_TOP - 20) / rowH)
    local holes = 0.3 - d * 0.12
    for r = 0, rows - 1 do
        local y = E.PEG_TOP + 20 + r * rowH
        local offset = (r % 2) * spacing / 2
        for c = 0, floor((W - 2 * E.PEG_MARGIN) / spacing) do
            if rng() > holes then add(peg(E.PEG_MARGIN + offset + c * spacing, y)) end
        end
    end
end }

FAMILIES[#FAMILIES + 1] = { name = "Pillars", build = function(rng, add, d)
    local cols = 4
    for c = 1, cols do
        local x = E.PEG_MARGIN + 40 + (c - 1) * (W - 2 * E.PEG_MARGIN - 80) / (cols - 1)
        local y0 = 150 + rng() * 60
        local len = 120 + rng() * 120
        local function f(t) return x, y0 + t * len end
        brickCurve(add, f, floor(len / 30), "pillar" .. c, rng, 0.1)
    end
    for r = 0, 5 do
        for c = 0, cols - 2 do
            local x = E.PEG_MARGIN + 40 + (c + 0.5) * (W - 2 * E.PEG_MARGIN - 80) / (cols - 1)
            add(peg(x + (rng() - 0.5) * 30, 150 + r * 64 + (rng() - 0.5) * 20))
        end
    end
end }

L.FAMILIES = FAMILIES

-- ---------------------------------------------------------------------

function L:Seed(n) return n * 7919 + 12345 end

function L:ChapterName(chapter)
    return self.CHAPTERS[((chapter - 1) % #self.CHAPTERS) + 1]
end

function L:PowerFor(chapter)
    local n = #E.POWERS
    return E.POWERS[((chapter - 1) % n) + 1].id
end

function L:Difficulty(n)
    return (n - 1) / (self.COUNT - 1)
end

-- Counts that climb with the level: oranges 15 -> 30, pieces 50 -> 85.
function L:Counts(n)
    local d = self:Difficulty(n)
    return floor(15 + d * 15 + 0.5), floor(50 + d * 35 + 0.5)
end

function L:Build(n)
    n = math.max(1, math.min(self.COUNT, floor(n)))
    local seed = self:Seed(n)
    local rng = E.NewRng(seed)
    local chapter = floor((n - 1) / self.PER_CHAPTER) + 1
    local d = self:Difficulty(n)
    local orange, target = self:Counts(n)
    local family = FAMILIES[((n + chapter) % #FAMILIES) + 1]

    local pegs = {}
    local function clearOf(p, group)
        local rp = E.PegRadius(p)
        for _, q in ipairs(pegs) do
            if not (group and q.group == group) then
                local need = rp + E.PegRadius(q) + 2 * E.BALL_R + 8
                local dx, dy = p.x - q.x, p.y - q.y
                if dx * dx + dy * dy < need * need then return false end
            end
        end
        return true
    end
    local function add(p, group)
        local rp = E.PegRadius(p)
        if p.x - rp < E.PEG_MARGIN - 6 or p.x + rp > W - E.PEG_MARGIN + 6 then return false end
        if p.y - rp < E.PEG_TOP or p.y + rp > E.PEG_BOTTOM then return false end
        if not clearOf(p, group) then return false end
        p.group = group
        pegs[#pegs + 1] = p
        return true
    end

    family.build(rng, add, d)

    local tries = 0
    while #pegs < target and tries < 2500 do
        tries = tries + 1
        add(peg(E.PEG_MARGIN + rng() * (W - 2 * E.PEG_MARGIN),
            E.PEG_TOP + 12 + rng() * (E.PEG_BOTTOM - E.PEG_TOP - 24)))
    end
    while #pegs > target + 12 do table.remove(pegs, rng(1, #pegs)) end

    if orange > #pegs - 3 then orange = #pegs - 3 end
    local order = {}
    for i = 1, #pegs do order[i] = i end
    for i = #order, 2, -1 do
        local j = rng(1, i)
        order[i], order[j] = order[j], order[i]
    end
    local greens = 2
    for k, idx in ipairs(order) do
        local p = pegs[idx]
        if k <= orange then p.kind = "orange"
        elseif k <= orange + greens then p.kind = "green"
        else p.kind = "blue" end
        p.lit, p.gone = false, false
    end

    return {
        level = n,
        chapter = chapter,
        name = self:ChapterName(chapter),
        seed = seed,
        layout = family.name,
        pegs = pegs,
        orange = orange,
        balls = E.BALLS,
        power = self:PowerFor(chapter),
    }
end
