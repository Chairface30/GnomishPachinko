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

-- Drawing primitives. Every family is a deliberate picture: the only
-- randomness is which variant of the picture a level gets.
local L_X0, L_X1 = E.PEG_MARGIN + 6, W - E.PEG_MARGIN - 6
local CX = W / 2

local function row(add, y, n, x0, x1)
    x0, x1 = x0 or L_X0, x1 or L_X1
    for k = 0, n - 1 do
        local f = (n == 1) and 0.5 or k / (n - 1)
        add(peg(x0 + (x1 - x0) * f, y))
    end
end

local function column(add, x, y0, y1, n)
    for k = 0, n - 1 do add(peg(x, y0 + (y1 - y0) * k / (n - 1))) end
end

-- pegs along an arc of a circle, angles in radians from the +x axis
local function arc(add, cx, cy, r, a0, a1, n)
    for k = 0, n - 1 do
        local a = a0 + (a1 - a0) * ((n == 1) and 0 or k / (n - 1))
        add(peg(cx + r * cos(a), cy + r * sin(a)))
    end
end

local function ring(add, cx, cy, r, n, spin)
    for k = 0, n - 1 do
        local a = (spin or 0) + 2 * pi * k / n
        add(peg(cx + r * cos(a), cy + r * sin(a)))
    end
end

local function diamond(add, cx, cy, half, perEdge)
    local corners = { { 0, -half }, { half, 0 }, { 0, half }, { -half, 0 } }
    for e = 1, 4 do
        local a, b = corners[e], corners[e % 4 + 1]
        for k = 0, perEdge - 1 do
            local f = k / perEdge
            add(peg(cx + a[1] + (b[1] - a[1]) * f, cy + a[2] + (b[2] - a[2]) * f))
        end
    end
end

local function brickLine(add, x0, y0, x1, y1, group, count)
    brickCurve(add, function(t) return x0 + (x1 - x0) * t, y0 + (y1 - y0) * t end, count, group)
end

-- a smile (or frown) of touching bricks: centre, radius, half-angle
local function brickArc(add, cx, cy, r, spread, group, frown)
    local function f(t)
        local a = pi / 2 - spread + 2 * spread * t
        if frown then return cx + r * cos(a), cy - r * sin(a) end
        return cx + r * cos(a), cy + r * sin(a)
    end
    brickCurve(add, f, math.max(3, floor(r * 2 * spread / 30)), group)
end

-- 1. Brickwork: staggered rows with a lattice of holes
FAMILIES[#FAMILIES + 1] = { name = "Brickwork", build = function(rng, add, d)
    local rows = 7
    local spacing = (L_X1 - L_X0) / 8
    local motif = rng(0, 2)
    for r = 0, rows - 1 do
        local y = 150 + (470 - 150) * r / (rows - 1)
        local offset = (r % 2) * spacing / 2
        local n = (r % 2 == 0) and 9 or 8
        for c = 0, n - 1 do
            local hole = (motif == 0 and (r + c) % 4 == 0 and r > 0 and r < rows - 1)
                or (motif == 1 and c % 3 == 1 and r % 2 == 1)
                or (motif == 2 and math.abs(c - (n - 1) / 2) < 1 and r % 3 == 1)
            if not hole then add(peg(L_X0 + offset + c * spacing, y)) end
        end
    end
end }

-- 2. Rainbow: four concentric arcs under a crown
FAMILIES[#FAMILIES + 1] = { name = "Rainbow", build = function(rng, add, d)
    local cy = 760
    local bricksOn = d > 0.4
    for i, rad in ipairs({ 300, 380, 460, 540 }) do
        local reach = (CX - E.PEG_MARGIN) / rad
        if reach > 1 then reach = 1 end
        local tmax = math.asin(reach)
        if bricksOn and i % 2 == 0 then
            brickCurve(add, function(t)
                local a = -tmax + 2 * tmax * t
                return CX + rad * sin(a), cy - rad * cos(a)
            end, floor(rad * 2 * tmax / 32), "arc" .. i)
        else
            local n = floor(rad * 2 * tmax / 44) + 1
            for k = 0, n - 1 do
                local a = -tmax + 2 * tmax * k / (n - 1)
                add(peg(CX + rad * sin(a), cy - rad * cos(a)))
            end
        end
    end
    row(add, 150, 5, CX - 150, CX + 150)
end }

-- 3. Diamonds: three hollow diamonds, a crown and a floor
FAMILIES[#FAMILIES + 1] = { name = "Diamonds", build = function(rng, add, d)
    local wide = rng() < 0.5
    diamond(add, wide and 100 or 120, 330, 85, 3)
    diamond(add, CX, 250, 100, 4)
    diamond(add, wide and W - 100 or W - 120, 330, 85, 3)
    add(peg(CX, 410))
    add(peg(CX, 250))
    row(add, 150, 3, CX - 120, CX + 120)
    row(add, 480, 7, 60, W - 60)
end }

-- 4. Rings: two rings in the middle, columns down each side, a floor
FAMILIES[#FAMILIES + 1] = { name = "Rings", build = function(rng, add, d)
    local cy = 300
    local spin = rng(0, 1) * pi / 16
    ring(add, CX, cy, 125, 16, spin)
    ring(add, CX, cy, 62, 8, spin + pi / 8)
    add(peg(CX, cy))
    column(add, L_X0 + 8, 150, 480, 7)
    column(add, L_X1 - 8, 150, 480, 7)
    row(add, 480, 6, 100, W - 100)
    row(add, 140, 4, CX - 90, CX + 90)
end }

-- 5. Zigzag: five full shelves, alternating slope
FAMILIES[#FAMILIES + 1] = { name = "Zigzag", build = function(rng, add, d)
    for s = 0, 4 do
        local y0 = 140 + s * 80
        local leftToRight = (s % 2 == 0)
        if d > 0.5 and s % 2 == 1 then
            brickCurve(add, function(t)
                return L_X0 + 10 + t * (L_X1 - L_X0 - 20), y0 + (leftToRight and t or (1 - t)) * 46
            end, 12, "shelf" .. s)
        else
            for k = 0, 8 do
                local f = k / 8
                add(peg(L_X0 + 10 + f * (L_X1 - L_X0 - 20), y0 + (leftToRight and f or (1 - f)) * 46))
            end
        end
    end
end }

-- 6. Brick Arcs: three smiles of bricks with pegs in their bowls
FAMILIES[#FAMILIES + 1] = { name = "Brick Arcs", build = function(rng, add, d)
    local frown = rng() < 0.3
    brickArc(add, CX, 200, 120, 0.9, "mid", frown)
    brickArc(add, 120, 380, 80, 1.0, "left", frown)
    brickArc(add, W - 120, 380, 80, 1.0, "right", frown)
    ring(add, CX, 200, 55, 6, pi / 6)
    add(peg(120, 380))
    add(peg(W - 120, 380))
    row(add, 150, 2, 70, W - 70)
    row(add, 470, 5, CX - 120, CX + 120)
    row(add, 300, 3, CX - 60, CX + 60)
    column(add, 50, 160, 470, 5)
    column(add, W - 50, 160, 470, 5)
    row(add, 330, 2, CX - 150, CX + 150)
end }

-- 7. Brick Walls: platform rows whose gap wanders, pegs in the gaps
FAMILIES[#FAMILIES + 1] = { name = "Brick Walls", build = function(rng, add, d)
    local rows = 5
    local gaps = (rng() < 0.5) and { 1, 3, 5, 3, 1 } or { 3, 1, 5, 1, 3 }
    for r = 0, rows - 1 do
        local y = 160 + r * (330 / (rows - 1))
        local gapAt = gaps[r + 1]
        for seg = 1, 5 do
            local x = L_X0 + 10 + (seg - 1) * 94 + 35
            if seg ~= gapAt then
                add(brick(x, y, 0, 70, E.BRICK_H), "wall" .. r)
            else
                add(peg(x, y))
            end
        end
    end
    for r = 0, rows - 2 do
        local y = 160 + (r + 0.5) * (330 / (rows - 1))
        row(add, y, 4, L_X0 + 60, L_X1 - 60)
    end
end }

-- 8. Spiral: one long spiral under a crown
FAMILIES[#FAMILIES + 1] = { name = "Spiral", build = function(rng, add, d)
    local cx, cy = CX, 315
    local turns = 2.5
    local n = 44
    local dir = (rng() < 0.5) and 1 or -1
    for k = 0, n - 1 do
        local t = k / (n - 1)
        local a = dir * t * turns * 2 * pi
        local rad = 22 + t * 172
        add(peg(cx + rad * cos(a), cy + rad * sin(a) * 0.95))
    end
    row(add, 140, 5, 80, W - 80)
end }

-- 9. Waves: four sine rows in step, posts at the edges
FAMILIES[#FAMILIES + 1] = { name = "Waves", build = function(rng, add, d)
    local phase = rng(0, 3) * pi / 2
    for r = 0, 3 do
        local y0 = 170 + r * 100
        for k = 0, 9 do
            local f = k / 9
            add(peg(L_X0 + f * (L_X1 - L_X0), y0 + sin(f * 2 * pi + phase + r * pi / 2) * 30))
        end
    end
    row(add, 480, 6, 100, W - 100)
end }

-- 10. Hourglass: a brick X with peg rows above, below and at the waist
FAMILIES[#FAMILIES + 1] = { name = "Hourglass", build = function(rng, add, d)
    brickLine(add, 70, 150, W - 70, 470, "x1", 11)
    brickLine(add, W - 70, 150, 70, 470, "x2", 11)
    row(add, 130, 5, 100, W - 100)
    row(add, 490, 5, 100, W - 100)
    row(add, 310, 2, 60, W - 60)
    column(add, 60, 200, 420, 4)
    column(add, W - 60, 200, 420, 4)
end }

-- 11. Honeycomb: a full hex grid with a shape cut out of the middle
FAMILIES[#FAMILIES + 1] = { name = "Honeycomb", build = function(rng, add, d)
    local spacing = 44
    local rowH = spacing * 0.866
    local rows = floor((E.PEG_BOTTOM - E.PEG_TOP - 20) / rowH)
    local shape = rng(0, 2)
    local cy = (E.PEG_TOP + E.PEG_BOTTOM) / 2
    for r = 0, rows - 1 do
        local y = E.PEG_TOP + 20 + r * rowH
        local offset = (r % 2) * spacing / 2
        for c = 0, floor((W - 2 * E.PEG_MARGIN) / spacing) do
            local x = E.PEG_MARGIN + offset + c * spacing
            local cut
            if shape == 0 then cut = math.abs(x - CX) / 110 + math.abs(y - cy) / 110 < 1
            elseif shape == 1 then cut = (x - CX) ^ 2 + (y - cy) ^ 2 < 100 ^ 2
            else cut = math.abs(x - CX) < 60 or math.abs(y - cy) < 40 end
            if not cut then add(peg(x, y)) end
        end
    end
end }

-- 12. Pillars: four brick columns with peg rows between
FAMILIES[#FAMILIES + 1] = { name = "Pillars", build = function(rng, add, d)
    local cols = 4
    local tall = rng() < 0.5
    for c = 1, cols do
        local x = L_X0 + 40 + (c - 1) * (L_X1 - L_X0 - 80) / (cols - 1)
        local y0 = tall and 150 or (c % 2 == 0 and 150 or 260)
        local len = tall and 220 or 160
        brickLine(add, x, y0, x, y0 + len, "pillar" .. c, floor(len / 30))
    end
    for r = 0, 5 do
        local y = 150 + r * 64
        for c = 0, cols - 2 do
            add(peg(L_X0 + 40 + (c + 0.5) * (L_X1 - L_X0 - 80) / (cols - 1), y))
        end
    end
    row(add, 490, 7, 60, W - 60)
end }

-- 13. Chevrons: nested V rows pointing down, or up
FAMILIES[#FAMILIES + 1] = { name = "Chevrons", build = function(rng, add, d)
    local up = rng() < 0.4
    for r = 0, 3 do
        local y0 = 150 + r * 85
        for k = 0, 8 do
            local f = k / 8
            local dip = 60 * (1 - math.abs(f - 0.5) * 2)
            add(peg(L_X0 + f * (L_X1 - L_X0), y0 + (up and -dip + 60 or dip)))
        end
    end
    row(add, 490, 3, CX - 100, CX + 100)
end }

-- 14. Castle: a brick rampart with crenellations, towers at the sides
FAMILIES[#FAMILIES + 1] = { name = "Castle", build = function(rng, add, d)
    -- rampart
    brickLine(add, 90, 330, W - 90, 330, "rampart", 12)
    for k = 0, 5 do add(peg(110 + k * 64, 290)) end
    -- towers
    for _, x in ipairs({ 60, W - 60 }) do
        brickLine(add, x, 180, x, 440, "tower" .. x, 8)
        add(peg(x, 150))
        add(peg(x, 475))
    end
    -- keep
    ring(add, CX, 200, 48, 6, pi / 6)
    add(peg(CX, 200))
    -- courtyard below the wall
    row(add, 400, 5, 150, W - 150)
    row(add, 470, 6, 130, W - 130)
end }

-- 15. Star: a five-point star of pegs with a ring in its heart
FAMILIES[#FAMILIES + 1] = { name = "Star", build = function(rng, add, d)
    local cx, cy, R, r = CX, 310, 180, 80
    local spin = -pi / 2
    local pts = {}
    for k = 0, 9 do
        local a = spin + k * pi / 5
        local rad = (k % 2 == 0) and R or r
        pts[#pts + 1] = { cx + rad * cos(a), cy + rad * sin(a) * 0.95 }
    end
    for k = 1, 10 do
        local a, b = pts[k], pts[k % 10 + 1]
        for s = 0, 1 do
            local f = s / 2
            add(peg(a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f))
        end
    end
    ring(add, cx, cy, 42, 5, spin)
    column(add, 52, 160, 470, 5)
    column(add, W - 52, 160, 470, 5)
    row(add, 490, 4, 110, W - 110)
end }

L.FAMILIES = FAMILIES

-- ---------------------------------------------------------------------
-- Gimmicks: the moving and solid pieces of later chapters. Each builder
-- gets (rng, add, mover, exclude, d). Moving pieces keep base positions
-- (bx, by, bangle) that Engine:UpdateMovers drives; exclude(rect, group)
-- keeps other pieces out of the travel area.

local GIMMICKS = {}

local function moving(p)
    p.bx, p.by, p.bangle = p.x, p.y, p.angle
    p.moving = true
    return p
end

GIMMICKS[#GIMMICKS + 1] = { name = "Slider", build = function(rng, add, mover, exclude, d)
    local y = 190 + rng() * 220
    local cx = W / 2 + (rng() - 0.5) * 120
    local n, amp = 5, 60 + d * 30
    local pegs = {}
    exclude({ x0 = cx - n * 16 - amp - 24, x1 = cx + n * 16 + amp + 24, y0 = y - 26, y1 = y + 26 }, "slider")
    for k = 0, n - 1 do
        local p = moving(brick(cx + (k - (n - 1) / 2) * 31, y, 0))
        if add(p, "slider") then pegs[#pegs + 1] = p end
    end
    mover({ kind = "slide", pegs = pegs, amp = amp, speed = 0.9 + d * 0.8, phase = 0 })
end }

GIMMICKS[#GIMMICKS + 1] = { name = "Lifts", build = function(rng, add, mover, exclude, d)
    for i, x in ipairs({ W * 0.28, W * 0.72 }) do
        local y0 = 200 + rng() * 60
        local pegs = {}
        exclude({ x0 = x - 30, x1 = x + 30, y0 = y0 - 70, y1 = y0 + 3 * 44 + 70 }, "lift" .. i)
        for k = 0, 3 do
            local p = moving(peg(x, y0 + k * 44))
            if add(p, "lift" .. i) then pegs[#pegs + 1] = p end
        end
        mover({ kind = "lift", pegs = pegs, amp = 45 + d * 20, speed = 1.1 + d * 0.6, phase = (i - 1) * pi })
    end
end }

GIMMICKS[#GIMMICKS + 1] = { name = "Wheel", build = function(rng, add, mover, exclude, d)
    local cx, cy, r = W / 2, 270 + rng() * 60, 62
    local pegs = {}
    exclude({ x0 = cx - r - 34, x1 = cx + r + 34, y0 = cy - r - 34, y1 = cy + r + 34 }, "wheel")
    for k = 0, 7 do
        local a = 2 * pi * k / 8
        local p = moving(peg(cx + r * cos(a), cy + r * sin(a)))
        if add(p, "wheel") then pegs[#pegs + 1] = p end
    end
    for _, a in ipairs({ 0, pi / 2 }) do
        local p = moving(brick(cx, cy, a, 60, E.BRICK_H))
        if add(p, "wheel") then pegs[#pegs + 1] = p end
    end
    mover({ kind = "wheel", pegs = pegs, cx = cx, cy = cy, speed = (rng() < 0.5 and 1 or -1) * (0.6 + d * 0.6), phase = 0 })
end }

GIMMICKS[#GIMMICKS + 1] = { name = "Twin Wheels", build = function(rng, add, mover, exclude, d)
    for i, cx in ipairs({ W * 0.3, W * 0.7 }) do
        local cy, r = 300 + (rng() - 0.5) * 60, 46
        local pegs = {}
        exclude({ x0 = cx - r - 30, x1 = cx + r + 30, y0 = cy - r - 30, y1 = cy + r + 30 }, "twin" .. i)
        for k = 0, 5 do
            local a = 2 * pi * k / 6
            local p = moving(peg(cx + r * cos(a), cy + r * sin(a)))
            if add(p, "twin" .. i) then pegs[#pegs + 1] = p end
        end
        mover({ kind = "wheel", pegs = pegs, cx = cx, cy = cy, speed = (i == 1 and 1 or -1) * (0.8 + d * 0.6), phase = 0 })
    end
end }

GIMMICKS[#GIMMICKS + 1] = { name = "Pendulum", build = function(rng, add, mover, exclude, d)
    local cx, cy = W / 2 + (rng() - 0.5) * 100, 240 + rng() * 80
    local n = 5
    local pegs = {}
    local half = n * 31 / 2 + 24
    exclude({ x0 = cx - half, x1 = cx + half, y0 = cy - half, y1 = cy + half }, "swing")
    for k = 0, n - 1 do
        local p = moving(brick(cx + (k - (n - 1) / 2) * 31, cy, 0))
        if add(p, "swing") then pegs[#pegs + 1] = p end
    end
    mover({ kind = "swing", pegs = pegs, cx = cx, cy = cy, amp = 0.6 + d * 0.3, speed = 1.3 + d * 0.5, phase = 0 })
end }

GIMMICKS[#GIMMICKS + 1] = { name = "Blocks", build = function(rng, add, mover, exclude, d)
    -- three solid bars: a flat one in the middle and two tilted wings,
    -- or the mirror of that
    local flip = (rng() < 0.5) and 1 or -1
    local y = 220 + rng(0, 2) * 90
    for _, spec in ipairs({ { CX, y, 0 }, { 110, y + 70 * flip, 0.5 }, { W - 110, y + 70 * flip, -0.5 } }) do
        local p = brick(spec[1], spec[2], spec[3], 64, 14)
        p.kind = "block"
        add(p)
    end
end }

GIMMICKS[#GIMMICKS + 1] = { name = "Sliding Block", build = function(rng, add, mover, exclude, d)
    local y = 200 + rng() * 200
    local cx = W / 2
    local amp = 90
    exclude({ x0 = cx - 45 - amp - 20, x1 = cx + 45 + amp + 20, y0 = y - 24, y1 = y + 24 }, "sblock")
    local p = moving(brick(cx, y, 0, 90, 14))
    p.kind = "block"
    if add(p, "sblock") then
        mover({ kind = "slide", pegs = { p }, amp = amp, speed = 1.2 + d * 0.6, phase = 0 })
    end
end }

L.GIMMICKS = GIMMICKS

-- Which gimmicks a level gets: none before chapter 3, then most levels
-- carry one and the late game sometimes two.
function L:GimmicksFor(n, rng)
    local list = {}
    if n < 21 then return list end
    if rng() < 0.25 then return list end
    local first = ((n * 5 + floor(n / 10) * 3) % #GIMMICKS) + 1
    list[1] = GIMMICKS[first]
    if n >= 300 and rng() < 0.45 then
        local second = ((first + 2 + rng(0, 2)) % #GIMMICKS) + 1
        if second ~= first then list[2] = GIMMICKS[second] end
    end
    return list
end

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

-- Oranges climb with the level: 15 -> 30. Piece counts come from the pattern.
function L:Counts(n)
    local d = self:Difficulty(n)
    return floor(15 + d * 15 + 0.5)
end

function L:Build(n)
    n = math.max(1, math.min(self.COUNT, floor(n)))
    local seed = self:Seed(n)
    local chapter = floor((n - 1) / self.PER_CHAPTER) + 1
    local d = self:Difficulty(n)
    local orange = self:Counts(n)
    local family = FAMILIES[((n + chapter) % #FAMILIES) + 1]

    -- Assemble the level; a gimmick that would gut the pattern is dropped
    -- and the pattern built alone.
    local function assemble(allowGimmicks)
    local rng = E.NewRng(seed)
    local pegs = {}
    local movers, excludes = {}, {}
    local function mover(mv) movers[#movers + 1] = mv end
    local function exclude(rect, group) rect.group = group; excludes[#excludes + 1] = rect end
    -- surface-to-surface clearance so a ball can pass between pieces;
    -- bricks are measured as the rectangles they are, not as big circles
    local function pointRectDist(px, py, q)
        local c, sn = cos(q.angle), sin(q.angle)
        local dx, dy = px - q.x, py - q.y
        local lx, ly = dx * c + dy * sn, -dx * sn + dy * c
        local ex = math.max(math.abs(lx) - q.w / 2, 0)
        local ey = math.max(math.abs(ly) - q.h / 2, 0)
        return sqrt(ex * ex + ey * ey)
    end
    local function surfaceDist(p, q)
        local pb, qb = p.shape == "brick", q.shape == "brick"
        if not pb and not qb then
            local dx, dy = p.x - q.x, p.y - q.y
            return sqrt(dx * dx + dy * dy) - 2 * E.PEG_R
        elseif pb and qb then
            local best = math.huge
            for _, pair in ipairs({ { p, q }, { q, p } }) do
                local a, b = pair[1], pair[2]
                local c, sn = cos(a.angle), sin(a.angle)
                for _, f in ipairs({ -0.5, 0, 0.5 }) do
                    local d = pointRectDist(a.x + c * a.w * f, a.y + sn * a.w * f, b) - a.h / 2
                    if d < best then best = d end
                end
            end
            return best
        else
            local br, pg = pb and p or q, pb and q or p
            return pointRectDist(pg.x, pg.y, br) - E.PEG_R
        end
    end
    local function clearOf(p, group)
        local need = 2 * E.BALL_R + 6
        for _, q in ipairs(pegs) do
            if not (group and q.group == group) then
                if surfaceDist(p, q) < need then return false end
            end
        end
        return true
    end
    local function add(p, group)
        local rp = E.PegRadius(p)
        if p.x - rp < E.PEG_MARGIN - 6 or p.x + rp > W - E.PEG_MARGIN + 6 then return false end
        if p.y - rp < E.PEG_TOP or p.y + rp > E.PEG_BOTTOM then return false end
        for _, r in ipairs(excludes) do
            if r.group ~= group and p.x > r.x0 and p.x < r.x1 and p.y > r.y0 and p.y < r.y1 then return false end
        end
        if not clearOf(p, group) then return false end
        p.group = group
        pegs[#pegs + 1] = p
        return true
    end

    local gimmicks = allowGimmicks and self:GimmicksFor(n, rng) or {}
    local gimmickNames = {}
    for _, g in ipairs(gimmicks) do
        g.build(rng, add, mover, exclude, d)
        gimmickNames[#gimmickNames + 1] = g.name
    end
    family.build(rng, add, d)
    return pegs, movers, gimmickNames, rng
    end

    local pegs, movers, gimmickNames, rng = assemble(true)
    local static = 0
    for _, p in ipairs(pegs) do if not p.moving and p.kind ~= "block" then static = static + 1 end end
    if static < 28 and #gimmickNames > 0 then pegs, movers, gimmickNames, rng = assemble(false) end

    -- no random fill: the pattern is the level

    -- colours go to everything but the solid blocks
    local order = {}
    for i, p in ipairs(pegs) do if p.kind ~= "block" then order[#order + 1] = i end end
    -- small patterns keep at least six blue pieces
    if orange > #order - 6 then orange = #order - 6 end
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
    end
    for _, p in ipairs(pegs) do p.lit, p.gone = false, false end

    return {
        level = n,
        chapter = chapter,
        name = self:ChapterName(chapter),
        seed = seed,
        layout = family.name,
        pegs = pegs,
        movers = movers,
        gimmick = (#gimmickNames > 0) and table.concat(gimmickNames, " + ") or nil,
        orange = orange,
        balls = E.BALLS,
        power = self:PowerFor(chapter),
    }
end
