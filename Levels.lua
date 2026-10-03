--[[
    Gnomish Pachinko - Levels.lua
    400 levels generated from their number alone. Level n gets a seed,
    a chapter (ten levels each, named after a place in Azeroth), a layout
    family, an objective (classic oranges, eggs, gems or a boss), counts
    and tough pieces that climb with n, and the chapter's power.

    Generators call add(peg) for every piece they want; add rejects pieces
    outside the zone or too close to one already placed, except within the
    same `group` (brick chains touch on purpose).
]]

local GP = GnomishPachinko
local E = GP.Engine
GP.Levels = GP.Levels or {}
local L = GP.Levels

L.COUNT = 400
L.PER_CHAPTER = 10

-- The pictures are drawn in a 600-wide DESIGN space (pegs from y 120 to
-- 500) and mapped into the field as pieces are added: scaled by SX and
-- shifted down by OY, so the patterns keep their shapes on the portrait
-- field and sit in its upper two thirds.
local DW = 600
local W = DW
local SX = E.FIELD_W / DW
local OY = 60
local function mapX(x) return x * SX end
local function mapY(y) return OY + y * SX end
L.DesignW, L.ScaleX, L.OffsetY = DW, SX, OY
local sin, cos, floor, sqrt, pi = math.sin, math.cos, math.floor, math.sqrt, math.pi

L.CHAPTERS = {
    -- forty chapters, every one a place from the original Azeroth
    "Elwynn Forest", "Durotar", "Dun Morogh", "Mulgore", "Teldrassil", "Tirisfal Glades",
    "Westfall", "Loch Modan", "Darkshore", "Silverpine Forest", "The Barrens", "Redridge Mountains",
    "Stonetalon Mountains", "Ashenvale", "Duskwood", "Wetlands", "Hillsbrad Foothills", "Thousand Needles",
    "Alterac Mountains", "Arathi Highlands", "Desolace", "Stranglethorn Vale", "Dustwallow Marsh", "Badlands",
    "Swamp of Sorrows", "Feralas", "The Hinterlands", "Tanaris", "Searing Gorge", "Azshara",
    "Blasted Lands", "Un'Goro Crater", "Felwood", "Burning Steppes", "Western Plaguelands", "Eastern Plaguelands",
    "Winterspring", "Deadwind Pass", "Silithus", "Moonglade",
}

-- ---------------------------------------------------------------------
-- The launcher's reach. The ball starts at the top centre and only ever
-- falls, so the high corners can never be touched. ReachFloor(x) is the
-- highest point (smallest y) any shot's centre passes at that x; a piece
-- above it, by more than a ball and peg radius, is unreachable.
local reachFloor

local function buildReach()
    reachFloor = {}
    local FW = E.FIELD_W
    local cols = floor(FW / 4) + 1
    for c = 0, cols do reachFloor[c] = math.huge end
    for deg = -E.MAX_AIM_DEG, E.MAX_AIM_DEG do
        local a = deg * pi / 180
        local x, y = FW / 2 + sin(a) * E.LAUNCH_R, E.LAUNCH_CY + cos(a) * E.LAUNCH_R
        local vx, vy = sin(a) * E.LAUNCH_SPEED, cos(a) * E.LAUNCH_SPEED
        local dt = E.STEP
        for _ = 1, 600 do
            vy = vy + E.GRAVITY * dt
            x, y = x + vx * dt, y + vy * dt
            if x < E.BALL_R then x = E.BALL_R; vx = -vx * E.RESTITUTION end
            if x > FW - E.BALL_R then x = FW - E.BALL_R; vx = -vx * E.RESTITUTION end
            if y > E.FIELD_H then break end
            local c = floor(x / 4)
            if y < reachFloor[c] then reachFloor[c] = y end
        end
    end
end

function L:ReachFloor(x)
    if not reachFloor then buildReach() end
    local c = floor(x / 4)
    if c < 0 then c = 0 elseif c > #reachFloor then c = #reachFloor end
    return reachFloor[c]
end

function L:Reachable(p)
    local rp = (p.shape == "brick") and (p.h / 2) or (p.r or E.PEG_R)
    return p.y + rp + E.BALL_R >= self:ReachFloor(p.x) - 2
end

-- ---------------------------------------------------------------------
-- Piece factories

local function peg(x, y) return { shape = "peg", x = x, y = y } end
local function brick(x, y, angle, w, h)
    return { shape = "brick", x = x, y = y, angle = angle or 0, w = w or E.BRICK_W, h = h or E.BRICK_H }
end
local function bumper(x, y)
    return { shape = "peg", x = x, y = y, r = E.BUMPER_R, kind = "bumper", bounce = E.BUMPER_BOUNCE }
end
-- a balloon: a soft round bumper of any size, never lights
local function balloon(x, y, r)
    return { shape = "peg", x = x, y = y, r = r, kind = "bumper", balloon = true,
        bounce = E.BALLOON_BOUNCE, kick = E.BALLOON_KICK }
end
-- a loose key: light it and every piece locked to it dissolves
local function key(x, y, id)
    return { shape = "peg", x = x, y = y, r = 10, kind = "key", unlocks = id, special = true }
end
-- one bar of a cage: solid, gold, dissolves with its key
local function cageBar(x, y, angle, w, id)
    local p = brick(x, y, angle, w, 12)
    p.kind = "block"
    p.lock = id
    return p
end
local function barrier(x, y, angle, w)
    local p = brick(x, y, angle, w or 64, 14)
    p.kind = "block"
    return p
end

-- A chain of touching bricks along a curve f(t) -> x, y for t in [0, 1].
local function brickCurve(add, f, count, group, rng, skip, extra)
    local prevx, prevy
    for k = 0, count do
        local t = k / count
        local x, y = f(t)
        if prevx then
            local mx, my = (x + prevx) / 2, (y + prevy) / 2
            local ang = math.atan2 and math.atan2(y - prevy, x - prevx) or math.atan(y - prevy, x - prevx)
            local len = sqrt((x - prevx) ^ 2 + (y - prevy) ^ 2)
            if not (skip and rng() < skip) then
                local b = brick(mx, my, ang, len + 1, E.BRICK_H)
                if extra then for key, v in pairs(extra) do b[key] = v end end
                if b.rail then b.railIdx = k end      -- its place along the rail
                add(b, group)
            end
        end
        prevx, prevy = x, y
    end
end

-- ---------------------------------------------------------------------
-- Layout families. Each gets (rng, add, d, dens): d is difficulty 0..1,
-- dens the density 0..1 of the picture (early levels draw a sparse
-- version of the same picture: fewer rows, fewer structures).

local FAMILIES = {}

-- Drawing primitives. Every family is a deliberate picture: the only
-- randomness is which variant of the picture a level gets.
local L_X0, L_X1 = E.PEG_MARGIN + 6, W - E.PEG_MARGIN - 6
local CX = W / 2

L.BALLOON_SIZES = { 12, 16, 21, 27 }     -- field pixels

-- Balloons from chapter 2: some near the walls for ricochets, some out in
-- the open where they block a route; more and bigger as the levels climb.
function L:BalloonCount(n)
    if n <= 10 then return 0 end
    return 1 + floor(self:Difficulty(n) * 3.5)
end
-- Rails from chapter 2: a small half-pipe bowl or a little spiral, here
-- and there, laid down before the pattern so the pattern fits round them.
-- A ball that meets one from the inside rides it (a Super Slide).
local function railBowl(add, rng, cx, cy, r, id)
    -- the bottom half of a circle: falling in, the ball runs round and flies out the far side
    brickCurve(add, function(t)
        local a = pi * (0.08 + 0.84 * t)
        return cx + r * cos(a), cy + r * sin(a) * 0.85
    end, 10, id, rng, nil, { rail = id, railCx = cx, railCy = cy })
end
-- Most spirals open like level 8's: the mouth on the upper flank with the
-- outer arm running down from it, so a falling ball can be laid into it
-- and ride it round; the mouth sits somewhere between the side and the
-- top. One in L.SPIRAL_HARD opens the other way (the arm climbing from the
-- mouth), only to be ridden by a ball coming up from below.
L.SPIRAL_HARD = 0.2
local function railSpiral(add, rng, cx, cy, r1, id)
    local dir = (rng() < 0.5) and 1 or -1
    local a0
    if rng() < L.SPIRAL_HARD then
        a0 = (dir > 0) and -0.15 or (pi + 0.15)
    else
        -- dir 1 winds with falling angles: the mouth on the left, arm going down
        local lift = 0.14 + rng() * 0.6
        a0 = (dir > 0) and (-pi + lift) or (-lift)
    end
    brickCurve(add, function(t)
        local a = a0 - dir * t * 1.15 * 2 * pi
        local r = r1 - (r1 - r1 * 0.32) * t
        return cx + r * cos(a), cy + r * sin(a) * 0.9
    end, 16, id, rng, nil, { rail = id, railCx = cx, railCy = cy })
end
function L:RailCount(n)
    if n <= 10 then return 0 end
    local r = (self:Seed(n) % 100) / 100
    if r < 0.45 then return 0 end
    return (n > 150 and r > 0.85) and 2 or 1
end
local function placeRails(rng, add, n, count)
    for k = 1, count do
        local kind = (rng() < 0.55) and "bowl" or "spiral"
        local r = (kind == "bowl") and (60 + rng() * 30) or (70 + rng() * 35)
        local cx = 140 + rng() * (W - 280)
        local cy = 200 + rng() * 170
        if kind == "bowl" then railBowl(add, rng, cx, cy, r, "rail" .. k)
        else railSpiral(add, rng, cx, cy, r, "rail" .. k) end
    end
end

-- The balloons follow the picture: always in mirrored pairs (the same
-- size at the same height either side of the middle), with an odd one only
-- ever on the centre line. A level picks one arrangement and keeps to it:
-- ricochets by the walls, a pair on the flanks, or a centre balloon with
-- its pairs beside it. A pair that does not fit tries the next height down;
-- half a pair is never left behind.
L.BALLOON_DESIGNS = {
    walls  = { dx = W / 2 - 80 },
    flanks = { dx = 150 },
    centre = { dx = 120, middle = true },
}
L.BALLOON_DESIGN_ORDER = { "walls", "flanks", "centre" }
local function placeBalloons(rng, add, n, count, pegs)
    if count <= 0 then return 0 end
    local design = L.BALLOON_DESIGNS[L.BALLOON_DESIGN_ORDER[rng(1, #L.BALLOON_DESIGN_ORDER)]]
    local r = L.BALLOON_SIZES[rng(1, #L.BALLOON_SIZES)]
    local placed, k = 0, 0
    local function try(x, y)
        k = k + 1
        return add(balloon(x, y, r), "balloon" .. k)
    end
    local y0 = 200 + rng(0, 3) * 30
    -- the centre one first, if the design has one or the count is odd
    if design.middle or count % 2 == 1 then
        for y = y0, 500, 30 do
            if try(CX, y) then placed = placed + 1 break end
        end
    end
    local y = y0 + (placed > 0 and 0 or 0)
    while count - placed >= 2 and y <= 500 do
        if try(CX - design.dx, y) then
            if try(CX + design.dx, y) then
                placed = placed + 2
                y = y + 110
            else
                pegs[#pegs] = nil          -- no half pairs
                y = y + 30
            end
        else
            y = y + 30
        end
    end
    return placed
end


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
FAMILIES[#FAMILIES + 1] = { name = "Brickwork", build = function(rng, add, d, dens)
    local rows = 3 + floor(4 * dens + 0.5)
    local spacing = (L_X1 - L_X0) / 8
    local motif = rng(0, 2)
    for r = 0, rows - 1 do
        local y = 150 + (470 - 150) * r / 6
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
FAMILIES[#FAMILIES + 1] = { name = "Rainbow", build = function(rng, add, d, dens)
    local cy = 760
    local bricksOn = d > 0.4
    local radii = { 300, 380, 460, 540 }
    for i = #radii - 1 - floor(2 * dens + 0.5), 1, -1 do table.remove(radii, i) end
    for i, rad in ipairs(radii) do
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
    if dens > 0.5 then row(add, 150, 5, CX - 150, CX + 150) end
end }

-- 3. Diamonds: three hollow diamonds, a crown and a floor
FAMILIES[#FAMILIES + 1] = { name = "Diamonds", build = function(rng, add, d, dens)
    -- three whole diamonds: the big one high in the middle, two smaller
    -- ones low at the sides, never touching
    local low = rng() < 0.5
    diamond(add, CX, 240, 100, 4)
    add(peg(CX, 240))
    if dens > 0.35 then
        diamond(add, 118, low and 350 or 330, 84, 3)
        diamond(add, W - 118, low and 350 or 330, 84, 3)
        add(peg(118, low and 350 or 330))
        add(peg(W - 118, low and 350 or 330))
    end
    if dens > 0.7 then
        row(add, 140, 2, CX - 170, CX + 170)
        row(add, 485, 5, CX - 130, CX + 130)
    end
end }

-- 4. Rings: two rings in the middle, columns down each side, a floor
FAMILIES[#FAMILIES + 1] = { name = "Rings", build = function(rng, add, d, dens)
    local cy = 300
    local spin = rng(0, 1) * pi / 16
    ring(add, CX, cy, 125, 10 + floor(6 * dens + 0.5), spin)
    if dens > 0.35 then ring(add, CX, cy, 62, 8, spin + pi / 8) end
    add(peg(CX, cy))
    if dens > 0.6 then
        column(add, L_X0 + 8, 150, 480, 7)
        column(add, L_X1 - 8, 150, 480, 7)
    end
    if dens > 0.8 then
        row(add, 480, 6, 100, W - 100)
        row(add, 140, 4, CX - 90, CX + 90)
    end
end }

-- 5. Zigzag: five full shelves, alternating slope
FAMILIES[#FAMILIES + 1] = { name = "Zigzag", build = function(rng, add, d, dens)
    for s = 0, 1 + floor(3 * dens + 0.5) do
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
FAMILIES[#FAMILIES + 1] = { name = "Brick Arcs", build = function(rng, add, d, dens)
    local frown = rng() < 0.3
    brickArc(add, CX, 200, 120, 0.9, "mid", frown)
    ring(add, CX, 200, 55, 6, pi / 6)
    row(add, 300, 3, CX - 60, CX + 60)
    if dens > 0.35 then
        brickArc(add, 120, 380, 80, 1.0, "left", frown)
        brickArc(add, W - 120, 380, 80, 1.0, "right", frown)
        add(peg(120, 380))
        add(peg(W - 120, 380))
    end
    if dens > 0.6 then
        row(add, 150, 2, 70, W - 70)
        row(add, 470, 5, CX - 120, CX + 120)
    end
    if dens > 0.8 then
        column(add, 50, 160, 470, 5)
        column(add, W - 50, 160, 470, 5)
        row(add, 330, 2, CX - 150, CX + 150)
    end
end }

-- 7. Brick Walls: platform rows whose gap wanders, pegs in the gaps
FAMILIES[#FAMILIES + 1] = { name = "Brick Walls", build = function(rng, add, d, dens)
    local rows = 2 + floor(3 * dens + 0.5)
    local gaps = (rng() < 0.5) and { 1, 3, 5, 3, 1 } or { 3, 1, 5, 1, 3 }
    for r = 0, rows - 1 do
        local y = 160 + r * (330 / 4)
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
        local y = 160 + (r + 0.5) * (330 / 4)
        row(add, y, 4, L_X0 + 60, L_X1 - 60)
    end
end }

-- 8. Spiral: one long spiral under a crown
FAMILIES[#FAMILIES + 1] = { name = "Spiral", build = function(rng, add, d, dens)
    -- pegs every 46px of arc along an Archimedean spiral
    local cx, cy = CX, 315
    local dir = (rng() < 0.5) and 1 or -1
    local b = 172 / (2.5 * 2 * pi)       -- radius grows this much per radian
    local a, rad = 0, 24
    local limit = 96 + 100 * dens
    while rad < limit do
        add(peg(cx + rad * cos(dir * a), cy + rad * sin(dir * a) * 0.95))
        local step = 46 / math.max(rad, 24)
        a = a + step
        rad = 24 + b * a
    end
    if dens > 0.6 then row(add, 140, 5, 80, W - 80) end
end }

-- 9. Waves: four sine rows in step, posts at the edges
FAMILIES[#FAMILIES + 1] = { name = "Waves", build = function(rng, add, d, dens)
    local phase = rng(0, 3) * pi / 2
    for r = 0, 1 + floor(2 * dens + 0.5) do
        local y0 = 170 + r * 100
        for k = 0, 9 do
            local f = k / 9
            add(peg(L_X0 + f * (L_X1 - L_X0), y0 + sin(f * 2 * pi + phase + r * pi / 2) * 30))
        end
    end
    if dens > 0.7 then row(add, 480, 6, 100, W - 100) end
end }

-- 10. Hourglass: a brick X with peg rows above, below and at the waist
FAMILIES[#FAMILIES + 1] = { name = "Hourglass", build = function(rng, add, d, dens)
    -- both arms share a group so they may cross in the middle
    brickLine(add, 70, 150, W - 70, 470, "x", 12)
    brickLine(add, W - 70, 150, 70, 470, "x", 12)
    if dens > 0.35 then
        row(add, 130, 5, 100, W - 100)
        row(add, 490, 5, 100, W - 100)
    end
    if dens > 0.6 then row(add, 310, 2, 60, W - 60) end
    if dens > 0.8 then
        column(add, 60, 200, 420, 4)
        column(add, W - 60, 200, 420, 4)
    end
end }

-- 11. Honeycomb: a full hex grid with a shape cut out of the middle
FAMILIES[#FAMILIES + 1] = { name = "Honeycomb", build = function(rng, add, d, dens)
    local spacing = 44
    local rowH = spacing * 0.866
    local rows = floor((E.PEG_BOTTOM - E.PEG_TOP - 20) / rowH)
    local shape = rng(0, 2)
    local cy = (E.PEG_TOP + E.PEG_BOTTOM) / 2
    -- sparse versions keep the middle rows
    local keep = 3 + floor((rows - 3) * dens + 0.5)
    local r0 = floor((rows - keep) / 2)
    for r = r0, r0 + keep - 1 do
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
FAMILIES[#FAMILIES + 1] = { name = "Pillars", build = function(rng, add, d, dens)
    local cols = 2 + floor(2 * dens + 0.5)
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
    if dens > 0.6 then row(add, 490, 7, 60, W - 60) end
end }

-- 13. Chevrons: nested V rows pointing down, or up
FAMILIES[#FAMILIES + 1] = { name = "Chevrons", build = function(rng, add, d, dens)
    local up = rng() < 0.4
    for r = 0, 1 + floor(2 * dens + 0.5) do
        local y0 = 150 + r * 85
        for k = 0, 8 do
            local f = k / 8
            local dip = 60 * (1 - math.abs(f - 0.5) * 2)
            add(peg(L_X0 + f * (L_X1 - L_X0), y0 + (up and -dip + 60 or dip)))
        end
    end
    if dens > 0.7 then row(add, 490, 3, CX - 100, CX + 100) end
end }

-- 14. Castle: a brick rampart with crenellations, towers at the sides
FAMILIES[#FAMILIES + 1] = { name = "Castle", build = function(rng, add, d, dens)
    -- rampart
    brickLine(add, 90, 330, W - 90, 330, "rampart", 12)
    for k = 0, 5 do add(peg(110 + k * 64, 290)) end
    -- keep
    ring(add, CX, 200, 48, 6, pi / 6)
    add(peg(CX, 200))
    -- towers
    if dens > 0.35 then
        for _, x in ipairs({ 60, W - 60 }) do
            brickLine(add, x, 180, x, 440, "tower" .. x, 8)
            add(peg(x, 150))
            add(peg(x, 475))
        end
    end
    -- courtyard below the wall
    if dens > 0.6 then row(add, 400, 5, 150, W - 150) end
    if dens > 0.8 then row(add, 470, 6, 130, W - 130) end
end }

-- 15. Star: a five-point star of pegs with a ring in its heart
FAMILIES[#FAMILIES + 1] = { name = "Star", build = function(rng, add, d, dens)
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
    if dens > 0.4 then ring(add, cx, cy, 42, 5, spin) end
    if dens > 0.7 then
        column(add, 52, 160, 470, 5)
        column(add, W - 52, 160, 470, 5)
        row(add, 490, 4, 110, W - 110)
    end
end }

L.FAMILIES = FAMILIES

-- ---------------------------------------------------------------------
-- Chapter 1: nine starter pictures, the simplest first. Level 10 is the
-- first boss and uses the last of them.

local STARTERS = {}

STARTERS[1] = { name = "First Steps", build = function(rng, add)
    row(add, 250, 5, CX - 120, CX + 120)
    row(add, 340, 4, CX - 90, CX + 90)
end }

STARTERS[2] = { name = "Two Rows", build = function(rng, add)
    row(add, 240, 7, CX - 180, CX + 180)
    row(add, 330, 6, CX - 150, CX + 150)
end }

STARTERS[3] = { name = "Little Diamond", build = function(rng, add)
    diamond(add, CX, 270, 80, 2)
    add(peg(CX, 270))
    row(add, 430, 5, CX - 120, CX + 120)
end }

STARTERS[4] = { name = "Three Shelves", build = function(rng, add)
    row(add, 220, 7, CX - 180, CX + 180)
    row(add, 310, 6, CX - 150, CX + 150)
    row(add, 400, 7, CX - 180, CX + 180)
end }

STARTERS[5] = { name = "The V", build = function(rng, add)
    for k = 0, 8 do
        local f = k / 8
        add(peg(L_X0 + 20 + f * (L_X1 - L_X0 - 40), 220 + 120 * (1 - math.abs(f - 0.5) * 2)))
    end
    row(add, 440, 4, CX - 90, CX + 90)
end }

STARTERS[6] = { name = "Small Ring", build = function(rng, add)
    ring(add, CX, 290, 85, 12, pi / 12)
    add(peg(CX, 290))
    row(add, 460, 5, CX - 120, CX + 120)
end }

STARTERS[7] = { name = "First Bricks", build = function(rng, add)
    brickLine(add, CX - 150, 230, CX - 30, 230, "shelfL", 4)
    brickLine(add, CX + 30, 230, CX + 150, 230, "shelfR", 4)
    row(add, 320, 5, CX - 120, CX + 120)
    brickLine(add, CX - 60, 410, CX + 60, 410, "shelfM", 4)
    row(add, 470, 4, CX - 150, CX + 150)
end }

-- The level 8 spiral, a rail: it winds anticlockwise and opens at the upper
-- left, where its outer arm runs down and to the left in line with a ball
-- from the cannon, so a shot that grazes the mouth runs along the inside
-- of the arm and round the spiral to its middle.
L.SLIDE_TUTORIAL = 8
-- two-star and three-star marks set by hand (nil keeps the formula's)
L.STAR_MARKS = {
    [8]  = { 300000, 500000 },       -- the Super Slide tutorial: stars for a big ride
    [10] = { 150000, 260000 },       -- the first boss: the formula asked far too much
}
L.SPIRAL8 = { a0 = -3.00, turns = 1.5, r0 = 48, r1 = 175, cy = 330, count = 30 }
STARTERS[8] = { name = "Super Slide", build = function(rng, add)
    local sp = L.SPIRAL8
    brickCurve(add, function(t)
        local a = sp.a0 - t * sp.turns * 2 * pi
        local r = sp.r1 - (sp.r1 - sp.r0) * t
        return CX + r * cos(a), sp.cy + r * sin(a) * 0.9
    end, sp.count, "spiral", rng, nil, { rail = "spiral", railCx = CX, railCy = sp.cy })
    row(add, 530, 4, CX - 150, CX + 150)
end }

STARTERS[9] = { name = "Columns", build = function(rng, add)
    column(add, CX - 150, 200, 400, 4)
    column(add, CX, 240, 440, 4)
    column(add, CX + 150, 200, 400, 4)
    row(add, 480, 4, CX - 90, CX + 90)
end }

STARTERS[10] = { name = "Boss Shelves", build = function(rng, add)
    row(add, 280, 7, CX - 180, CX + 180)
    row(add, 360, 6, CX - 150, CX + 150)
    row(add, 440, 7, CX - 180, CX + 180)
end }

L.STARTERS = STARTERS

-- The Long Shots tutorial (the first Long Shot level): two angled walls of
-- pegs, a V opening to the top, every peg orange. A ball that strikes one
-- wall is thrown across at the other, so the far-apart pairs come easily.
-- Nothing else goes on the board: no gimmick, rail, balloon, green or rim.
L.LONGSHOT_TUTORIAL = 66
L.LONGSHOT_WALLS = { x0 = 70, y0 = 170, x1 = 245, y1 = 470, count = 12 }
local LONGSHOT_WALLS = { name = "Long Shot Walls", build = function(rng, add)
    local w = L.LONGSHOT_WALLS
    for k = 0, w.count - 1 do
        local f = k / (w.count - 1)
        local x, y = w.x0 + (w.x1 - w.x0) * f, w.y0 + (w.y1 - w.y0) * f
        add(peg(x, y))
        add(peg(W - x, y))
    end
end }

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

GIMMICKS[#GIMMICKS + 1] = { name = "Bumpers", build = function(rng, add, mover, exclude, d)
    -- three bumpers in a triangle, point up or point down
    local cy = 250 + rng(0, 2) * 60
    local up = rng() < 0.5
    add(bumper(CX, up and cy or cy + 90))
    add(bumper(CX - 110, up and cy + 90 or cy))
    add(bumper(CX + 110, up and cy + 90 or cy))
end }

GIMMICKS[#GIMMICKS + 1] = { name = "Bumper Gate", build = function(rng, add, mover, exclude, d)
    -- two slanted barriers funnel toward a bumper that throws the ball back out
    local y = 230 + rng(0, 2) * 70
    add(barrier(CX - 120, y, 0.45, 90))
    add(barrier(CX + 120, y, -0.45, 90))
    add(bumper(CX, y + 60))
    add(bumper(70, y + 150))
    add(bumper(W - 70, y + 150))
end }

GIMMICKS[#GIMMICKS + 1] = { name = "Key Gate", build = function(rng, add, mover, exclude, d)
    -- a long solid bar slanted over a cluster of pegs, and the key that
    -- drops it on the other side of the field
    local left = rng() < 0.5
    local cx = left and 150 or (W - 150)
    local cy = 300 + rng() * 60
    local id = "gate" .. floor(cy)
    exclude({ x0 = cx - 120, x1 = cx + 120, y0 = cy - 40, y1 = cy + 110 }, "gate")
    add(cageBar(cx, cy, left and 0.35 or -0.35, 230, id), "gate")
    for k = 0, 2 do
        local p = peg(cx - 40 + k * 40, cy + 60)
        p.forceOrange = true
        add(p, "gate")
    end
    add(peg(cx - 20, cy + 95), "gate")
    add(peg(cx + 20, cy + 95), "gate")
    local kx = left and (W - 110) or 110
    local ky = 190 + rng() * 60
    exclude({ x0 = kx - 30, x1 = kx + 30, y0 = ky - 30, y1 = ky + 30 }, "gkey")
    add(key(kx, ky, id), "gkey")
end }

GIMMICKS[#GIMMICKS + 1] = { name = "Key Cage", build = function(rng, add, mover, exclude, d)
    -- a gold cage of solid bars round three pegs that will be orange, and
    -- the loose key that opens it somewhere up the field
    local cx, cy = W / 2 + (rng() - 0.5) * 200, 330 + rng() * 90
    local hw, hh = 62, 30
    exclude({ x0 = cx - hw - 24, x1 = cx + hw + 24, y0 = cy - hh - 24, y1 = cy + hh + 24 }, "cage")
    local id = "cage" .. floor(cx)
    local bars = {
        cageBar(cx, cy - hh, 0, hw * 2 + 12, id), cageBar(cx, cy + hh, 0, hw * 2 + 12, id),
        cageBar(cx - hw, cy, pi / 2, hh * 2 + 12, id), cageBar(cx + hw, cy, pi / 2, hh * 2 + 12, id),
    }
    for _, b in ipairs(bars) do add(b, "cage") end
    for k = -1, 1 do
        local p = peg(cx + k * 38, cy)
        p.forceOrange = true
        add(p, "cage")
    end
    local kx = cx < W / 2 and (W - 110) or 110
    local ky = 170 + rng() * 60
    if d >= 0.3 then
        -- a chain: the gold key sits in a silver cage, whose key is elsewhere
        local id2 = id .. "s"
        exclude({ x0 = kx - 60, x1 = kx + 60, y0 = ky - 40, y1 = ky + 40 }, "key")
        local bars = {
            cageBar(kx, ky - 24, 0, 60, id2), cageBar(kx, ky + 24, 0, 60, id2),
            cageBar(kx - 28, ky, pi / 2, 48, id2), cageBar(kx + 28, ky, pi / 2, 48, id2),
        }
        for _, b in ipairs(bars) do b.silver = true; add(b, "key") end
        add(key(kx, ky, id), "key")
        local k2x, k2y = W - kx, 150 + rng() * 40
        exclude({ x0 = k2x - 30, x1 = k2x + 30, y0 = k2y - 30, y1 = k2y + 30 }, "key2")
        local k2 = key(k2x, k2y, id2)
        k2.silver = true
        add(k2, "key2")
    else
        exclude({ x0 = kx - 30, x1 = kx + 30, y0 = ky - 30, y1 = ky + 30 }, "key")
        add(key(kx, ky, id), "key")
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

-- The order the gimmicks arrive in: one new one per chapter from chapter
-- 3, each making its debut on the first level of its chapter.
L.GIMMICK_ORDER = { "Slider", "Lifts", "Blocks", "Wheel", "Bumpers", "Pendulum", "Key Cage", "Twin Wheels", "Bumper Gate", "Key Gate", "Sliding Block" }
local function gimmickByName(name)
    for _, g in ipairs(GIMMICKS) do if g.name == name then return g end end
end

-- Which gimmicks a level gets: none before chapter 3 and none on a boss
-- level. The pool grows by one each chapter; a new gimmick always shows
-- on its chapter's first level, otherwise levels draw from the pool more
-- and more often, and from level 300 sometimes twice.
function L:GimmicksFor(n, rng, objective)
    local list = {}
    if n < 21 or objective == "boss" or objective == "duel" then return list end
    local chapter = floor((n - 1) / self.PER_CHAPTER) + 1
    local pool = math.min(#self.GIMMICK_ORDER, chapter - 2)
    local debut = (n % 10 == 1) and chapter - 2 <= #self.GIMMICK_ORDER
    if debut then
        list[1] = gimmickByName(self.GIMMICK_ORDER[pool])
        return list
    end
    if rng() > 0.35 + 0.4 * self:Stage(n) then return list end
    local first = rng(1, pool)
    list[1] = gimmickByName(self.GIMMICK_ORDER[first])
    if n >= 300 and rng() < 0.45 then
        local second = rng(1, pool)
        if second ~= first then list[2] = gimmickByName(self.GIMMICK_ORDER[second]) end
    end
    return list
end

-- ---------------------------------------------------------------------

function L:Seed(n) return n * 7919 + 12345 end

function L:ChapterName(chapter)
    return self.CHAPTERS[((chapter - 1) % #self.CHAPTERS) + 1]
end

-- The chapter's host's powers, the first or the second by turns (the
-- level card lets the player pick either).
function L:PowerFor(chapter)
    local h = GP:HostFor((chapter - 1) * 10 + 1)
    return h.powers[(math.floor((chapter - 1) / #GP.HOSTS) % 2) + 1]
end

function L:Difficulty(n)
    return (n - 1) / (self.COUNT - 1)
end

-- The content ramp of the early game: 0 at level 1, 1 from level 80 on.
function L:Stage(n)
    return math.max(0, math.min(1, (n - 1) / 79))
end

-- How much of a family's picture a level draws: chapter 1 uses its own
-- starter pictures; from level 11 the pictures fill in until level 80.
function L:Density(n)
    if n <= 10 then return 0 end
    return math.min(1, 0.3 + 0.7 * (n - 11) / 69)
end

-- The fewest pieces a pattern may be left with before a gimmick is
-- dropped from the level instead.
function L:MinPieces(n)
    if n <= 10 then return 7 end
    return floor(12 + 16 * self:Density(n))
end

-- What level n asks of you. Every tenth level is a boss, eggs from
-- chapter 2 (levels ending 5) and chapter 4 (ending 7), gems from chapter
-- 3 (ending 3 and 8); the rest are classic orange-peg levels.
-- Tinkmaster hosts the odd chapters, where the bosses are; at the end of
-- his chapter 9 he finally duels his brother himself. Winning it turns
-- his Super Guide into the Crazy Guide.
L.TINK_DUEL_LEVEL = 90
function L:Objective(n)
    if n == self.TINK_DUEL_LEVEL then return "duel" end
    local last = n % 10
    if last == 0 and n >= 10 then
        -- the first boss is a target; from then on even chapters duel
        local chapter = floor((n - 1) / self.PER_CHAPTER) + 1
        return (chapter % 2 == 0) and "duel" or "boss"
    end
    if last == 2 and n >= 141 then
        local chapter = floor((n - 1) / self.PER_CHAPTER) + 1
        return (chapter % 2 == 0) and "mixed_gems" or "mixed_eggs"
    end
    if last == 5 and n >= 11 then return "eggs" end
    if last == 7 and n >= 31 then return "eggs" end
    if last == 6 and n >= 66 then return "longshots" end
    if (last == 3 or last == 8) and n >= 21 then return "gems" end
    return "classic"
end

-- Oranges climb with the level: 3 on level 1, 8 by the end of chapter 1,
-- 15 by level 40, 30 by the last level. Piece counts come from the pattern.
function L:Counts(n)
    if n <= 10 then return 3 + floor((n - 1) * 0.6) end
    if n <= 40 then return 8 + floor((n - 10) * 7 / 30 + 0.5) end
    return floor(15 + 15 * (n - 40) / (self.COUNT - 40) + 0.5)
end

-- Eggs or gems on a level: 3 -> 6.
function L:SpecialCount(n)
    return 3 + floor(self:Difficulty(n) * 3.99)
end

-- Tough pieces (two hits) start in chapter 4 and grow to a third of the
-- board; from level 300 a growing share of them take three hits. Oranges
-- can be tough from chapter 7.
function L:ToughShare(n)
    if n < 31 then return 0 end
    return 0.08 + 0.30 * self:Difficulty(n)
end

function L:HeavyShare(n)
    if n < 300 then return 0 end
    return 0.15 + 0.35 * (n - 300) / 700
end

function L:ToughOrangesFrom() return 61 end

-- Every level has a name for its card.
local STARTER_NAMES = { "Howdy, Gnome!", "Two by Two", "A Little Sparkle", "Shelf Life", "The Big V", "Ring Around",
    "Brick by Brick", "Round and Round", "Standing Tall", "Clockwork Trouble" }
function L:Title(n, objective, family, bossName, duelName)
    if n <= 10 then return STARTER_NAMES[n] or ("Level " .. n) end
    local place = self:ChapterName(floor((n - 1) / self.PER_CHAPTER) + 1)
    if objective == "boss" then return (bossName or "The Boss") .. " of " .. place end
    if objective == "duel" then return "A Duel with " .. (duelName or "the Rival") end
    if objective == "eggs" then return "Nests of " .. place end
    if objective == "longshots" then return "Long Shots over " .. place end
    if objective == "gems" then return "Gems of " .. place end
    return (family or "Pegs") .. " of " .. place
end

-- Levels without the bucket: from chapter 5, levels ending 4 and 9 (never
-- a gem level, the bucket is its goal).
function L:NoBucket(n)
    if self:Objective(n) == "boss" then return true end      -- the boss owns the bottom: no tube
    if n < 41 then return false end
    local last = n % 10
    if last ~= 4 and last ~= 9 then return false end
    local o = self:Objective(n)
    return o ~= "gems" and o ~= "mixed_gems"
end

-- The duel on an even chapter's tenth level: always the rival.
function L:DuelFor(n)
    return E.RIVAL, E.DUEL_BALLS
end

-- The boss for a level: kind by chapter, health climbing from 5 to 21.
-- Bosses take the odd chapters in turn (Tin Drake, Gyro Spider, Cog Yeti,
-- Bolt Golem, Mechano-Boar); Tinkmaster's own duel in chapter 9 takes no
-- turn, so the order runs on unbroken past it.
L.BOSS_ORDER = { 1, 3, 5, 2, 4 }
function L:BossFor(n)
    local chapter = floor((n - 1) / self.PER_CHAPTER) + 1
    local k = floor((chapter + 1) / 2)
    if n > self.TINK_DUEL_LEVEL then k = k - 1 end
    local def = E.BOSSES[self.BOSS_ORDER[((k - 1) % #self.BOSS_ORDER) + 1]]
    return def, self.BOSS_HP[n] or (self.BOSS_HP_BASE + floor(chapter * self.BOSS_HP_STEP))
end
L.BOSS_ZAPPERS_EXTRA = 4     -- a boss level's oranges: its health and this many more
-- set by hand where the formula played too tough
-- Boss health, balanced for oranges that zap (1) and direct hits (2): in
-- simulated play a careful player needs most of a level's balls.
L.BOSS_HP_BASE = 12
L.BOSS_HP_STEP = 0.45
L.BOSS_HP = {}               -- set by hand per level where needed

-- Star marks come from the level itself: what its pieces are worth at a
-- middling multiplier, one Fever bin, and the bins of the balls a good
-- player has to spare. Harder levels (more goal pieces, tough pieces,
-- eggs, gems, a boss) ask for fewer spare balls.
L.STAR_BIN      = 9400       -- the first Fever bucket, on average
L.STAR_BALL     = 9000       -- what a spare ball fired at the buckets is worth, on average
L.STAR_SPARE    = { 3, 6 }   -- spare balls for two and three stars on the easiest level

function L:ParFor(spec)
    local pieces = 0
    local tough, coloured = 0, 0
    for _, p in ipairs(spec.pegs) do
        if not E.IsSolid(p) then
            local hp = p.maxhp or p.hp or 1
            if p.kind == "boss" then
                pieces = pieces + E.PEG_POINTS.boss * 10 + (hp - 1) * E.CHIP_POINTS.boss * 5
            else
                pieces = pieces + (E.PEG_POINTS[p.kind] or 25) * 5 + (hp - 1) * (E.CHIP_POINTS[p.kind] or 10) * 5
                coloured = coloured + 1
                if hp > 1 then tough = tough + 1 end
            end
        end
    end
    local goal = spec.goal or 0
    local hard = 0.5 * math.min(1, goal / 30) + 0.5 * (coloured > 0 and tough / coloured or 0)
    if spec.objective == "eggs" then hard = hard + 0.1
    elseif spec.objective == "gems" then hard = hard + 0.2
    elseif spec.objective == "mixed_eggs" or spec.objective == "mixed_gems" then hard = hard + 0.25
    elseif spec.objective == "boss" then hard = hard + 0.15
    elseif spec.objective == "duel" then hard = hard + 0.15
    elseif spec.objective == "longshots" then hard = hard + 0.15 end
    if spec.noBucket then hard = hard + 0.1 end
    hard = math.max(0, math.min(1, hard))
    local spare2 = self.STAR_SPARE[1] * (1 - 0.5 * hard)
    local spare3 = self.STAR_SPARE[2] * (1 - 0.5 * hard)
    -- the pieces weigh most: a board with more to light asks for more
    local s2 = pieces * 4 + self.STAR_BIN + spare2 * self.STAR_BALL
    local s3 = pieces * 6 + self.STAR_BIN + spare3 * self.STAR_BALL
    return floor(s2 / 1000 + 0.5) * 1000, floor(s3 / 1000 + 0.5) * 1000
end

-- Score needed for two and three stars (one star is the clear itself).
function L:StarScores(n)
    self.starCache = self.starCache or {}
    local c = self.starCache[n]
    if not c then
        local spec = self:Build(n)
        c = spec.stars
        self.starCache[n] = c
    end
    return c[1], c[2]
end

function L:StarsFor(n, score, cleared)
    if not cleared then return 0 end
    local s2, s3 = self:StarScores(n)
    if score >= s3 then return 3 end
    if score >= s2 then return 2 end
    return 1
end

-- Pieces may sit as close as the pattern wants, even touching; only real
-- overlaps are refused. Bricks are measured as the rectangles they are.
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
        return sqrt(dx * dx + dy * dy) - (p.r or E.PEG_R) - (q.r or E.PEG_R)
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
        return pointRectDist(pg.x, pg.y, br) - (pg.r or E.PEG_R)
    end
end
L.SurfaceDist = surfaceDist

-- attempt (0, 1, 2...) reshuffles which pieces are orange, egg or gem on a
-- retry; the picture itself never changes.
-- opts.stage2: the duel's second board, sparser and with fewer oranges.
function L:Build(n, attempt, opts)
    n = math.max(1, math.min(self.COUNT, floor(n)))
    attempt = attempt or 0
    opts = opts or {}
    local seed = self:Seed(n)
    local chapter = floor((n - 1) / self.PER_CHAPTER) + 1
    local d = self:Difficulty(n)
    local objective = self:Objective(n)
    local family = (n <= 10) and STARTERS[n] or FAMILIES[((n + chapter) % #FAMILIES) + 1]
    local lsTutorial = n == self.LONGSHOT_TUTORIAL and not opts.stage2
    if lsTutorial then family = LONGSHOT_WALLS end
    local dens = self:Density(n)
    if opts.stage2 then
        family = FAMILIES[((n + chapter + 3) % #FAMILIES) + 1]
        dens = math.min(dens, 0.6)
    end
    local bossDef, bossHp
    if objective == "boss" then bossDef, bossHp = self:BossFor(n) end
    local duelDef, duelTurns
    if objective == "duel" then duelDef, duelTurns = self:DuelFor(n) end

    -- Assemble the level; a gimmick that would gut the pattern is dropped
    -- and the pattern built alone.
    local function assemble(allowGimmicks)
    local rng = E.NewRng(seed)
    local pegs = {}
    local movers, excludes = {}, {}
    local function mover(mv)
        if mv.cx then mv.cx, mv.cy = mapX(mv.cx), mapY(mv.cy) end
        if mv.kind == "slide" or mv.kind == "lift" then mv.amp = mv.amp * SX end
        movers[#movers + 1] = mv
    end
    local function exclude(rect, group)
        rect.group = group
        rect.x0, rect.x1, rect.y0, rect.y1 = mapX(rect.x0), mapX(rect.x1), mapY(rect.y0), mapY(rect.y1)
        excludes[#excludes + 1] = rect
    end
    local function clearOf(p, group)
        local need = -0.5          -- touching is allowed
        for _, q in ipairs(pegs) do
            if not (group and q.group == group) then
                if surfaceDist(p, q) < need then return false end
            end
        end
        return true
    end
    local function add(p, group)
        -- design space into the field
        if not p.mapped then
            p.x, p.y = mapX(p.x), mapY(p.y)
            if p.bx then p.bx, p.by = mapX(p.bx), mapY(p.by) end
            if p.railCx then p.railCx, p.railCy = mapX(p.railCx), mapY(p.railCy) end
            if p.shape == "brick" then p.w = p.w * SX end
            p.mapped = true
        end
        local rp = E.PegRadius(p)
        if p.x - rp < E.PEG_MARGIN - 6 or p.x + rp > E.FIELD_W - E.PEG_MARGIN + 6 then return false end
        if p.kind ~= "boss" and (p.y - rp < E.PEG_TOP or p.y + rp > E.PEG_BOTTOM) then return false end
        if p.kind == "boss" and p.y + rp > E.FIELD_H - 60 then return false end
        if not L:Reachable(p) then return false end
        for _, r in ipairs(excludes) do
            if r.group ~= group and p.x > r.x0 and p.x < r.x1 and p.y > r.y0 and p.y < r.y1 then return false end
        end
        if not clearOf(p, group) then return false end
        p.group = group
        pegs[#pegs + 1] = p
        return true
    end

    -- the boss first: it owns a band along the bottom that nothing else enters
    if bossDef then
        local band = E.BOSS_BAND
        exclude({ x0 = -1, x1 = W + 1, y0 = band.y0, y1 = band.y1 }, "boss")
        local b = moving(peg(CX, band.y))
        b.r = E.BOSS_R
        b.kind = "boss"
        b.goal = true
        b.special = true
        b.hp = bossHp
        b.bounce = E.BOSS_BOUNCE
        b.ability = bossDef.id
        b.bossName = bossDef.name
        if add(b, "boss") then
            local amp = (bossDef.id == "spider") and 40 or (W / 2 - 90)
            mover({ kind = "slide", pegs = { b }, amp = amp, speed = bossDef.speed * 1.35, phase = 0 })
        end
    end

    local gimmicks = (allowGimmicks and not lsTutorial) and self:GimmicksFor(n, rng, objective) or {}
    local gimmickNames = {}
    for _, g in ipairs(gimmicks) do
        g.build(rng, add, mover, exclude, d)
        gimmickNames[#gimmickNames + 1] = g.name
    end
    if not opts.stage2 and not lsTutorial then placeRails(rng, add, n, self:RailCount(n)) end
    family.build(rng, add, d, dens)
    if not opts.stage2 and not lsTutorial then placeBalloons(rng, add, n, self:BalloonCount(n), pegs) end
    return pegs, movers, gimmickNames, rng
    end

    local pegs, movers, gimmickNames, rng = assemble(true)
    local static = 0
    for _, p in ipairs(pegs) do if not p.moving and not E.IsSolid(p) then static = static + 1 end end
    -- a gimmick that guts the pattern is dropped, except on the level that
    -- introduces it: a debut always shows
    local debut = (n % 10 == 1) and n >= 21 and (chapter - 2) <= #self.GIMMICK_ORDER
    if static < self:MinPieces(n) and #gimmickNames > 0 and not debut then pegs, movers, gimmickNames, rng = assemble(false) end
    -- the eggs' and gems' spots belong to the layout: the level's own stream
    rng = E.NewRng(seed * 31 + 7)

    -- Eggs and gems are loose bodies, much bigger than pegs, each sitting
    -- in a cradle of ordinary bricks built under it: a flat two-brick
    -- ledge for a gem (knock either brick out and it rolls off) and a V
    -- of two bricks for an egg (lose either side and the egg drops). The
    -- body takes the place of a pattern peg, well apart from the others
    -- and (gems) high enough to fall through something; anything it or
    -- its cradle would overlap is removed. Two passes: well spread out
    -- first, then closer together if the pattern has too few spots.
    local CRADLE_REACH = 46     -- how far a cradle's bricks can stick out from the body's centre
    -- a brick whose top face touches the body: `angle` along its length,
    -- `s` shifts the touch point along it (negative toward its start)
    local function cradleBrick(body, angle, w, s)
        local h = E.BRICK_H
        local c, sn = cos(angle), sin(angle)
        local nx, ny = sn, -c                 -- the face normal pointing at the body
        local d = body.r + h / 2 + 0.5
        return { shape = "brick", x = body.x - nx * d + c * s, y = body.y - ny * d + sn * s,
            angle = angle, w = w, h = h, mapped = true, cradle = true }
    end
    local function cradleFor(body, kind)
        local r = body.r
        local pair
        if kind == "gem" then
            local w = r + 12
            pair = { cradleBrick(body, 0, w, -w / 2), cradleBrick(body, 0, w, w / 2) }
        else
            -- an egg's cradle, picked from where it sits (so a level's layout
            -- never changes): a V, a shallow V, a flat ledge, or a cup
            local style = (floor(body.x) * 7 + floor(body.y) * 13) % 4
            if style == 0 then
                local w = r + 18
                pair = { cradleBrick(body, 0.5, w, -w * 0.3), cradleBrick(body, -0.5, w, w * 0.3) }
            elseif style == 1 then
                local w = r + 22
                pair = { cradleBrick(body, 0.28, w, -w * 0.38), cradleBrick(body, -0.28, w, w * 0.38) }
            elseif style == 2 then
                local w = r + 12
                pair = { cradleBrick(body, 0, w, -w / 2), cradleBrick(body, 0, w, w / 2) }
            else
                local w = r + 6
                pair = { cradleBrick(body, 0, w, 0), cradleBrick(body, 1.0, w, 0), cradleBrick(body, -1.0, w, 0) }
            end
        end
        -- the bricks touch end to end, like a brick chain
        local group = ("cradle%d_%d"):format(floor(body.x), floor(body.y))
        for _, b in ipairs(pair) do b.group = group end
        return pair
    end
    local gridTried = false
    local function convert(kind, count, r, spread, lowest)
        spread, lowest = spread or 90, lowest or 420
        local cands = {}
        for _, p in ipairs(pegs) do
            if p.shape == "peg" and not p.moving and not E.IsSolid(p) and not p.goal and not p.special
                and (kind ~= "gem" or p.y < mapY(lowest))
                and p.x - r - 24 >= E.PEG_MARGIN - 6 and p.x + r + 24 <= E.FIELD_W - E.PEG_MARGIN + 6
                and p.y - r >= E.PEG_TOP and p.y + r + 24 <= E.PEG_BOTTOM then
                -- the body and its cradle must not run into a moving piece, a
                -- key or a cage (those stay)
                local probe = { shape = "peg", x = p.x, y = p.y, r = r + CRADLE_REACH }
                local clear = true
                for _, q in ipairs(pegs) do
                    if (q.moving or q.special or q.lock or q.unlocks) and q ~= p and surfaceDist(probe, q) < -0.5 then clear = false break end
                end
                if clear then cands[#cands + 1] = p end
            end
        end
        for i = #cands, 2, -1 do
            local j = rng(1, i)
            cands[i], cands[j] = cands[j], cands[i]
        end
        if kind == "egg" then
            -- low first: a hatching phoenix flies up through the pattern
            table.sort(cands, function(a, b) return floor(a.y / 60) > floor(b.y / 60) end)
        end
        local chosen = {}
        for _, p in ipairs(cands) do
            if #chosen >= count then break end
            local ok = true
            for _, q in ipairs(chosen) do
                local dx, dy = p.x - q.x, p.y - q.y
                if dx * dx + dy * dy < spread * spread then ok = false break end
            end
            if ok then
                -- and its cradle must keep clear of the cradles already placed
                local mine = cradleFor({ x = p.x, y = p.y, r = r }, kind)
                for _, q in ipairs(chosen) do
                    for _, a in ipairs(q.cradlePlan) do
                        for _, b in ipairs(mine) do
                            if surfaceDist(a, b) < 1 then ok = false end
                        end
                    end
                end
                if ok then
                    p.cradlePlan = mine
                    chosen[#chosen + 1] = p
                end
            end
        end
        if #chosen < math.min(count, 3) then
            if spread > 70 then return convert(kind, count, r, 70, 470) end
            if not gridTried then
                -- room made on a grid: virtual spots join the pattern, and whatever
                -- they or their cradles overlap is cleared below
                gridTried = true
                local x0, x1 = E.PEG_MARGIN + r + 24, E.FIELD_W - E.PEG_MARGIN - r - 24
                local y0, y1 = E.PEG_TOP + r, E.PEG_BOTTOM - r - 24
                for gy = y0, y1, 64 do
                    for gx = x0, x1, 72 do
                        pegs[#pegs + 1] = { shape = "peg", x = gx, y = gy, mapped = true, virtual = true }
                    end
                end
                local got = convert(kind, count, r, 70, 470)
                for i = #pegs, 1, -1 do if pegs[i].virtual and not pegs[i].special then table.remove(pegs, i) end end
                return got
            end
            return 0
        end
        local cradles = {}
        for _, p in ipairs(chosen) do
            p.kind = kind
            p.goal = true
            p.r = r
            p.special = true
            p.loose = true
            p.hp = (kind == "egg") and ((n >= 300) and 3 or 2) or 1
            for _, b in ipairs(p.cradlePlan or cradleFor(p, kind)) do cradles[#cradles + 1] = b end
            p.cradlePlan = nil
        end
        if #chosen > 0 then
            -- clear the ground: whatever the body or its cradle overlaps goes
            for i = #pegs, 1, -1 do
                local q = pegs[i]
                if not q.special and not q.moving then
                    local hit = false
                    for _, p in ipairs(chosen) do
                        if surfaceDist(p, q) < -0.5 then hit = true break end
                    end
                    if not hit then
                        for _, b in ipairs(cradles) do
                            if surfaceDist(b, q) < -0.5 then hit = true break end
                        end
                    end
                    if hit then table.remove(pegs, i) end
                end
            end
            for _, b in ipairs(cradles) do pegs[#pegs + 1] = b end
        end
        return #chosen
    end

    local goal = 0
    if objective == "eggs" then
        goal = convert("egg", self:SpecialCount(n), E.EGG_R)
    elseif objective == "gems" then
        goal = convert("gem", self:SpecialCount(n), E.GEM_R)
    elseif objective == "mixed_eggs" then
        goal = convert("egg", 2 + floor(d * 2), E.EGG_R)
    elseif objective == "mixed_gems" then
        goal = convert("gem", 2 + floor(d * 2), E.GEM_R)
    elseif objective == "boss" then
        for _, p in ipairs(pegs) do if p.kind == "boss" then goal = 1 end end
    end
    if goal == 0 and objective ~= "classic" and objective ~= "duel" and objective ~= "longshots" then objective = "classic" end

    -- from here the colours: their own stream, so a retry deals the orange
    -- (and green and purple) pegs again on the very same layout
    rng = E.NewRng(seed * 31 + attempt * 101 + 7)
    -- colours go to everything but the solid and special pieces
    local order = {}
    for i, p in ipairs(pegs) do if not E.IsSolid(p) and not p.special then order[#order + 1] = i end end
    local orange = 0
    if objective == "longshots" then
        goal = 2 + floor(d * 2)
    end
    local mixed = objective == "mixed_eggs" or objective == "mixed_gems"
    if objective == "classic" or objective == "duel" or objective == "longshots" or mixed then
        orange = opts.stage2 and E.DUEL_STAGE2_ORANGES or self:Counts(n)
        if mixed then orange = floor(orange / 2) end
        -- patterns keep at least a quarter of their pieces (and two) blue
        local floorBlue = math.max(2, floor(#order * 0.25))
        if orange > #order - floorBlue then orange = #order - floorBlue end
        if mixed then goal = goal + orange elseif objective ~= "longshots" then goal = orange end
    end
    -- a boss level deals oranges too, not as goals but as zappers: each one
    -- lit zaps the boss, and there are a few more than its health
    if objective == "boss" then
        orange = (bossHp or 8) + L.BOSS_ZAPPERS_EXTRA
        local floorBlue = math.max(2, floor(#order * 0.25))
        if orange > #order - floorBlue then orange = #order - floorBlue end
    end
    for i = #order, 2, -1 do
        local j = rng(1, i)
        order[i], order[j] = order[j], order[i]
    end
    -- a Long Shot level seats its first oranges at both edges of the
    -- board, so there are always pairs far enough apart to make them
    if objective == "longshots" then
        table.sort(order, function(a, b) return pegs[a].x < pegs[b].x end)
        local edged, k = {}, goal + 1
        for i = 1, math.min(k, #order) do edged[#edged + 1] = order[i] end
        for i = #order, math.max(1, #order - k + 1), -1 do edged[#edged + 1] = order[i] end
        local used = {}
        for _, idx in ipairs(edged) do used[idx] = true end
        local rest = {}
        for _, idx in ipairs(order) do if not used[idx] then rest[#rest + 1] = idx end end
        for i = #rest, 2, -1 do
            local j = rng(1, i)
            rest[i], rest[j] = rest[j], rest[i]
        end
        order = {}
        for _, idx in ipairs(edged) do order[#order + 1] = idx end
        for _, idx in ipairs(rest) do order[#order + 1] = idx end
    end
    -- the pegs inside a key cage are orange first, the rest of the oranges
    -- fall where the shuffle put them
    local greens = 2
    local forced = 0
    for _, idx in ipairs(order) do if pegs[idx].forceOrange then forced = forced + 1 end end
    if forced > orange then forced = orange end
    local given, coloured = 0, 0
    for _, idx in ipairs(order) do
        local p = pegs[idx]
        if p.forceOrange and given < forced then p.kind = "orange"; p.goal = objective ~= "longshots" and objective ~= "boss"; given = given + 1 end
    end
    for _, idx in ipairs(order) do
        local p = pegs[idx]
        if not (p.forceOrange and p.kind == "orange") then
            coloured = coloured + 1
            if coloured <= orange - given then p.kind = "orange"; p.goal = objective ~= "longshots" and objective ~= "boss"
            elseif coloured <= orange - given + greens then p.kind = "green"
            else p.kind = "blue" end
        end
    end

    -- the Super Slide tutorial (level 8) is the spiral alone, and no green
    -- goes on it: the ride is never interrupted by a power
    if n == self.SLIDE_TUTORIAL then
        for _, g in ipairs(pegs) do
            if g.rail and g.kind == "green" then g.kind = "blue" end
        end
    end

    -- the Long Shots tutorial's walls are orange from end to end
    if lsTutorial then
        orange = 0
        for _, p in ipairs(pegs) do
            if not E.IsSolid(p) and not p.special then p.kind = "orange"; p.goal = false; orange = orange + 1 end
        end
    end

    -- tough pieces: a steel rim and two (or three) hits to light
    local toughShare, heavyShare = self:ToughShare(n), self:HeavyShare(n)
    if lsTutorial then toughShare = 0 end
    local tough = 0
    if toughShare > 0 then
        for _, idx in ipairs(order) do
            local p = pegs[idx]
            if p.kind == "blue" or (p.kind == "orange" and n >= self:ToughOrangesFrom()) then
                if rng() < toughShare then
                    p.hp = (rng() < heavyShare) and 3 or 2
                    tough = tough + 1
                end
            end
        end
    end

    for _, p in ipairs(pegs) do
        p.lit, p.gone = false, false
        p.hp = p.hp or 1
        p.maxhp = p.hp
    end

    -- a balloon whose twin was cleared away (for an egg's cradle, say)
    -- goes too: balloons only ever stand in mirrored pairs or on the middle
    do
        local mid = E.FIELD_W / 2
        for i = #pegs, 1, -1 do
            local p = pegs[i]
            if p.balloon and not p.post and math.abs(p.x - mid) > 1 then
                local twin = false
                for _, q in ipairs(pegs) do
                    if q ~= p and q.balloon and math.abs((q.x - mid) + (p.x - mid)) < 1.5 and math.abs(q.y - p.y) < 1.5 and q.r == p.r then twin = true break end
                end
                if not twin then table.remove(pegs, i) end
            end
        end
    end
    local spec = {
        level = n,
        chapter = chapter,
        name = self:ChapterName(chapter),
        title = self:Title(n, objective, family.name, bossDef and bossDef.name, duelDef and duelDef.name),
        attempt = attempt,
        seed = seed,
        layout = family.name,
        objective = objective,
        pegs = pegs,
        movers = movers,
        gimmick = (#gimmickNames > 0) and table.concat(gimmickNames, " + ") or nil,
        goal = goal,
        orange = orange,
        tough = tough,
        boss = (objective == "boss") and { id = bossDef.id, name = bossDef.name, blurb = bossDef.blurb, hp = bossHp } or nil,
        duel = (objective == "duel") and { id = duelDef.id, name = duelDef.name, blurb = duelDef.blurb, stage = opts.stage2 and 2 or 1 } or nil,
        noBucket = self:NoBucket(n),
        balls = E.BALLS,
        power = self:PowerFor(chapter),
    }
    spec.stars = { self:ParFor(spec) }
    -- star marks set by hand where the formula misjudged a level
    local mark = self.STAR_MARKS[n]
    if mark then spec.stars = { mark[1] or spec.stars[1], mark[2] or spec.stars[2] } end
    return spec
end
