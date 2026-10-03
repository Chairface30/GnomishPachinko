--[[
    Gnomish Pachinko - Editor.lua
    The level editor, open to every player: build a board piece by piece,
    select pieces (click, shift-click, drag a box) and move, rotate,
    mirror, copy or delete them as a group, set tough pieces, pinned
    oranges, rails, keys and cages and moving parts, and test-play it.
    Levels are saved on the account (GnomishPachinkoDB.editor.levels) and
    exported as a text code to share. The owner's characters can also
    import a code and approve a level for a level number; tools/import_levels.py
    writes approved levels into CustomLevels.lua, where they replace the
    generated level for everyone. The level data is described in Levels.lua.
]]

local GP = GnomishPachinko
local E, L, ART = GP.Engine, GP.Levels, GP.Art
local ED = {}
GP.Editor = ED

local W, H = E.FIELD_W, E.FIELD_H
local sin, cos, floor, sqrt, abs, pi = math.sin, math.cos, math.floor, math.sqrt, math.abs, math.pi
local atan2 = math.atan2 or math.atan
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- where pieces may go: the pattern zone with a little room either side
ED.ZONE = { x0 = E.PEG_MARGIN - 6, x1 = W - E.PEG_MARGIN + 6, y0 = E.PEG_TOP - 30, y1 = E.PEG_BOTTOM + 70 }
ED.MAX_PIECES = 500
ED.MAX_MOVERS = 20
ED.UNDO_MAX = 60
ED.SNAPS = { 0, 5, 10, 20 }
ED.TOOLS = { "select", "slide", "arc", "circle", "peg", "brick", "block", "rblock", "balloon", "bumper", "key", "cage", "egg", "gem" }
ED.TOOL_NAMES = { select = "Select / move", slide = "Super Slide", arc = "Slide arc", circle = "Slide circle" }
-- Bricks come in standard sizes: a full brick and a half one. A row or a
-- Super Slide is laid in full bricks end to end along the path, and the
-- last one is cut to fit.
ED.BRICK_SIZES = { E.BRICK_W / 2, E.BRICK_W }
ED.SLIDE_STEP = E.BRICK_W
ED.MIN_CUT = 6              -- a cut end shorter than this is left off
ED.CODE_PREFIX = "GPL1"

-- ---------------------------------------------------------------------
-- Saved data

function ED:DB()
    local db = GP:GetDB()
    if type(db.editor) ~= "table" then db.editor = {} end
    local e = db.editor
    if type(e.levels) ~= "table" then e.levels = {} end
    if type(e.approved) ~= "table" then e.approved = {} end
    return e
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end
ED.Copy = copy

function ED:IsOwner()
    return GP.Plays and GP.Plays.IsOwner and GP.Plays:IsOwner() or false
end

local function playerName()
    if not UnitName then return "Someone" end
    local first, last = UnitName("player")
    local ok = pcall(function() return (first or "") .. "" end)
    if not ok or not first then return "Someone" end
    if last and last ~= "" then return first .. " " .. last end
    return first
end

-- ---------------------------------------------------------------------
-- Checking a level: everything from a code or the saved variables goes
-- through here before the editor or the game touches it.

local function num(v, lo, hi, def)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return def end
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end
local function str(v, maxLen, pattern)
    if type(v) ~= "string" then return nil end
    v = v:gsub("[%c|]", "")
    if pattern then v = v:gsub(pattern, "") end
    if #v > maxLen then v = v:sub(1, maxLen) end
    return v
end

function ED:Sanitize(d)
    if type(d) ~= "table" then return nil end
    local out = { v = 1 }
    out.name = str(d.name, 40) or ""
    out.author = str(d.author, 40)
    out.imported = d.imported and true or nil     -- came in as a player's code: its author is credited in the game
    local g = L:CustomGoals(type(d.goals) == "table" and { goals = d.goals } or d)
    out.goals = { oranges = g.oranges and true or nil, longshots = g.longshots and floor(num(g.longshots, 1, 20, 3)) or nil }
    out.oranges = d.oranges and floor(num(d.oranges, 0, 200, 0)) or nil
    out.noBucket = d.noBucket and true or nil
    out.level = floor(num(d.level, 1, L.COUNT, 1))
    out.movers = {}
    if type(d.movers) == "table" then
        for i = 1, math.min(#d.movers, self.MAX_MOVERS) do
            local m = d.movers[i]
            if type(m) == "table" then
                local k = "slide"
                for _, mk in ipairs(L.EDIT_MOVERS) do if m.k == mk then k = mk end end
                local ampHi = (k == "swing") and 1.5 or 200
                out.movers[i] = { k = k, amp = num(m.amp, 0, ampHi, (k == "swing") and 0.6 or 60),
                    speed = num(m.speed, -5, 5, 1), phase = num(m.phase, -10, 10, 0) }
            else
                out.movers[i] = { k = "slide", amp = 60, speed = 1, phase = 0 }
            end
        end
    end
    out.pieces = {}
    if type(d.pieces) == "table" then
        for i = 1, math.min(#d.pieces, self.MAX_PIECES) do
            local p = d.pieces[i]
            if type(p) == "table" and type(p.t) == "string" and L.EDIT_TYPES[p.t] then
                local q = { t = p.t }
                q.x = num(p.x, 0, W, W / 2)
                q.y = num(p.y, 0, H, 300)
                if p.a then q.a = num(p.a, -100, 100, 0) end
                if p.w then q.w = num(p.w, 8, 300, 30) end
                if p.r then q.r = num(p.r, 6, 40, 12) end
                if p.hp then q.hp = floor(num(p.hp, 1, 3, 1)) end
                local c = (p.c == "orange" or p.c == "blue" or p.c == "green") and p.c or (p.o and "orange") or nil
                if c and (q.t == "peg" or q.t == "brick") then q.c = c end
                local no = str(p.no, 3, "[^ogp]")
                if no and no ~= "" and (q.t == "peg" or q.t == "brick") then q.no = no end
                if p.s then q.s = true end
                q.id = str(p.id, 16, "[^%w_]")
                q.rail = str(p.rail, 16, "[^%w_]")
                if q.id == "" then q.id = nil end
                if q.rail == "" then q.rail = nil end
                if p.mv then
                    local mv = floor(num(p.mv, 0, #out.movers, 0))
                    if mv >= 1 then q.mv = mv end
                end
                out.pieces[#out.pieces + 1] = q
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------
-- The text code: a small table syntax (no code is ever run when one is
-- read back), its length and a checksum, so a cut-off paste is caught.

local function fmtNum(v)
    local s
    if v == floor(v) then s = tostring(floor(v)) else s = ("%.3f"):format(v):gsub("0+$", ""):gsub("%.$", "") end
    return s
end

local function ser(v, out, depth)
    local t = type(v)
    if t == "number" then out[#out + 1] = fmtNum(v)
    elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
    elseif t == "string" then out[#out + 1] = '"' .. v:gsub("[%c|\"\\]", "") .. '"'
    elseif t == "table" then
        if depth > 6 then out[#out + 1] = "{}" return end
        out[#out + 1] = "{"
        local n = #v
        for i = 1, n do ser(v[i], out, depth + 1); out[#out + 1] = "," end
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then keys[#keys + 1] = k end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            out[#out + 1] = k .. "="
            ser(v[k], out, depth + 1)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "false"
    end
end

local function checksum(s)
    local sum = 0
    for i = 1, #s do sum = (sum * 31 + s:byte(i)) % 65521 end
    return sum
end

function ED:Encode(data)
    local out = {}
    ser(self:Sanitize(data), out, 0)
    local body = table.concat(out)
    return ("%s:%d:%d:%s"):format(self.CODE_PREFIX, #body, checksum(body), body)
end

-- a tiny reader for what ser writes
local function parse(s)
    local pos, len = 1, #s
    local depth = 0
    local function ws() pos = s:find("[^%s]", pos) or (len + 1) end
    local value
    local function tbl()
        depth = depth + 1
        if depth > 8 then error("too deep") end
        pos = pos + 1
        local t, n = {}, 0
        while true do
            ws()
            local c = s:sub(pos, pos)
            if c == "}" then pos = pos + 1 break end
            if c == "" then error("unfinished") end
            local key = s:match("^([%a_][%w_]*)%s*=", pos)
            if key and key ~= "true" and key ~= "false" then
                pos = s:find("=", pos, true) + 1
                ws()
                t[key] = value()
            else
                n = n + 1
                if n > 2000 then error("too long") end
                t[n] = value()
            end
            ws()
            if s:sub(pos, pos) == "," then pos = pos + 1 end
        end
        depth = depth - 1
        return t
    end
    value = function()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then return tbl() end
        if c == '"' then
            local close = s:find('"', pos + 1, true)
            if not close then error("unfinished text") end
            local v = s:sub(pos + 1, close - 1)
            pos = close + 1
            return v
        end
        if s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true end
        if s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
        local numStr = s:match("^%-?%d+%.?%d*", pos)
        if numStr then
            local ex = s:match("^[eE][%-+]?%d+", pos + #numStr)
            if ex then numStr = numStr .. ex end
            pos = pos + #numStr
            return tonumber(numStr)
        end
        error("bad value at " .. pos)
    end
    local v = value()
    return v
end

-- Returns the level, or nil and why not.
function ED:Decode(code)
    if type(code) ~= "string" then return nil, "No code." end
    code = code:gsub("^%s+", ""):gsub("%s+$", "")
    local prefix, n, sum, body = code:match("^(%w+):(%d+):(%d+):(.*)$")
    if prefix ~= self.CODE_PREFIX then return nil, "That is not a Gnomish Pachinko level code." end
    if #body ~= tonumber(n) then return nil, "The code is cut short or has extra text: copy all of it." end
    if checksum(body) ~= tonumber(sum) then return nil, "The code has been changed or garbled." end
    if #body > 120000 then return nil, "The code is too long." end
    local ok, v = pcall(parse, body)
    if not ok or type(v) ~= "table" then return nil, "The code could not be read." end
    return self:Sanitize(v)
end

-- ---------------------------------------------------------------------
-- Pieces: size, hit test, the pieces in a box

function ED:PieceRadius(pc)
    local t = pc.t
    if t == "rblock" or t == "balloon" then return pc.r or L.EDIT_TYPES[t].r end
    if t == "bumper" then return E.BUMPER_R end
    if t == "key" then return 10 end
    if t == "egg" then return E.EGG_R end
    if t == "gem" then return E.GEM_R end
    return E.PEG_R
end
local function isBar(pc) return pc.t == "brick" or pc.t == "block" or pc.t == "cage" end
ED.IsBar = isBar
function ED:BarSize(pc)
    local h = (pc.t == "brick") and E.BRICK_H or ((pc.t == "cage") and 12 or 14)
    return pc.w or L.EDIT_TYPES[pc.t].w or 30, h
end

function ED:Hit(pc, x, y)
    local dx, dy = x - pc.x, y - pc.y
    if isBar(pc) then
        local w, h = self:BarSize(pc)
        local c, s = cos(pc.a or 0), sin(pc.a or 0)
        local along, across = dx * c + dy * s, -dx * s + dy * c
        return abs(along) <= w / 2 + 3 and abs(across) <= h / 2 + 4
    end
    local r = self:PieceRadius(pc) + 3
    return dx * dx + dy * dy <= r * r
end

function ED:PieceAt(x, y)
    local pieces = self.data.pieces
    for i = #pieces, 1, -1 do
        if self:Hit(pieces[i], x, y) then return i end
    end
end

-- ---------------------------------------------------------------------
-- The level being edited

function ED:NewData()
    return { v = 1, name = "", goals = { oranges = true }, level = 1, pieces = {}, movers = {} }
end

function ED:SetData(d, keepUndo)
    self.data = d or self:NewData()
    self.sel = {}
    if not keepUndo then self.undo = {} end
    self:Refresh()
end

function ED:PushUndo()
    self.undo = self.undo or {}
    self.undo[#self.undo + 1] = copy(self.data)
    if #self.undo > self.UNDO_MAX then table.remove(self.undo, 1) end
    self.dirty = true
end

function ED:Undo()
    if not self.undo or #self.undo == 0 then return self:Status("Nothing to undo.") end
    self.data = table.remove(self.undo)
    self.sel = {}
    self:Refresh()
end

function ED:Selected()
    local list = {}
    for i in pairs(self.sel) do if self.data.pieces[i] then list[#list + 1] = i end end
    table.sort(list)
    return list
end

function ED:SelCount()
    local n = 0
    for i in pairs(self.sel) do if self.data.pieces[i] then n = n + 1 end end
    return n
end

function ED:Centre(list)
    local cx, cy = 0, 0
    for _, i in ipairs(list) do cx, cy = cx + self.data.pieces[i].x, cy + self.data.pieces[i].y end
    return cx / #list, cy / #list
end

local function place(tex, field, x, y)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", field, "TOPLEFT", x, -y)
end

local function clampToZone(pc)
    local z = ED.ZONE
    pc.x = math.max(z.x0, math.min(z.x1, pc.x))
    pc.y = math.max(z.y0, math.min(z.y1, pc.y))
end

function ED:Snap(v)
    local g = self.snap or 0
    if g <= 0 then return v end
    return floor(v / g + 0.5) * g
end

function ED:AddPiece(t, x, y, extra)
    if #self.data.pieces >= self.MAX_PIECES then return self:Status("A level holds at most " .. self.MAX_PIECES .. " pieces.") end
    local pc = { t = t, x = self:Snap(x), y = self:Snap(y) }
    local def = L.EDIT_TYPES[t]
    if def.w then pc.w = def.w end
    if def.r then pc.r = def.r end
    if t == "egg" then pc.hp = 2 end
    if (t == "key" or t == "cage") then pc.id = self.lastLock or "lock1" end
    if extra then for k, v in pairs(extra) do pc[k] = v end end
    clampToZone(pc)
    self.data.pieces[#self.data.pieces + 1] = pc
    return #self.data.pieces
end

function ED:DeleteSelected()
    local list = self:Selected()
    if #list == 0 then return end
    self:PushUndo()
    for k = #list, 1, -1 do table.remove(self.data.pieces, list[k]) end
    self.sel = {}
    self:Refresh()
end

function ED:MoveSelected(dx, dy)
    for _, i in ipairs(self:Selected()) do
        local pc = self.data.pieces[i]
        pc.x, pc.y = pc.x + dx, pc.y + dy
        clampToZone(pc)
    end
end

-- turn the selection round its middle (radians, clockwise on screen)
function ED:RotateSelected(da, cx, cy)
    local list = self:Selected()
    if #list == 0 then return end
    if not cx then cx, cy = self:Centre(list) end
    local c, s = cos(da), sin(da)
    for _, i in ipairs(list) do
        local pc = self.data.pieces[i]
        local dx, dy = pc.x - cx, pc.y - cy
        pc.x, pc.y = cx + dx * c - dy * s, cy + dx * s + dy * c
        if isBar(pc) then pc.a = (pc.a or 0) + da end
        clampToZone(pc)
    end
end

-- the number in the degrees box
function ED:Degrees()
    local v = tonumber(self.degBox and self.degBox:GetText() or "")
    if not v or v ~= v or abs(v) > 3600 then return nil end
    return v
end

function ED:TurnBy(sign)
    local deg = self:Degrees()
    if not deg then return self:Status("Type a number of degrees in the box.") end
    if self:SelCount() == 0 then return self:Status("Select some pieces first.") end
    self:PushUndo()
    self:RotateSelected(sign * deg * pi / 180)
    self:Refresh()
end

function ED:SetAngle()
    local deg = self:Degrees()
    if not deg then return self:Status("Type an angle in degrees in the box.") end
    local any = false
    for _, i in ipairs(self:Selected()) do if isBar(self.data.pieces[i]) then any = true end end
    if not any then return self:Status("Select a brick or bar to set its angle.") end
    self:ForSelected(function(pc) if isBar(pc) then pc.a = deg * pi / 180 end end)
end

function ED:MirrorSelected(vertical)
    local list = self:Selected()
    if #list == 0 then return end
    self:PushUndo()
    local cx, cy = self:Centre(list)
    for _, i in ipairs(list) do
        local pc = self.data.pieces[i]
        if vertical then
            pc.y = 2 * cy - pc.y
            if isBar(pc) then pc.a = -(pc.a or 0) end
        else
            pc.x = 2 * cx - pc.x
            if isBar(pc) then pc.a = pi - (pc.a or 0) end
        end
        clampToZone(pc)
    end
    self:Refresh()
end

-- a mirrored copy across the board's middle line: symmetric boards in one go
function ED:MirrorCopyAcross()
    local list = self:Selected()
    if #list == 0 then return end
    self:PushUndo()
    local new = {}
    for _, i in ipairs(list) do
        local pc = copy(self.data.pieces[i])
        pc.x = W - pc.x
        if isBar(pc) then pc.a = pi - (pc.a or 0) end
        pc.mv = nil
        if #self.data.pieces < self.MAX_PIECES then
            self.data.pieces[#self.data.pieces + 1] = pc
            new[#self.data.pieces] = true
        end
    end
    self.sel = new
    self:Refresh()
end

function ED:DuplicateSelected(dx, dy)
    local list = self:Selected()
    if #list == 0 then return end
    self:PushUndo()
    local new = {}
    for _, i in ipairs(list) do
        local pc = copy(self.data.pieces[i])
        pc.x, pc.y = pc.x + (dx or 20), pc.y + (dy or 20)
        clampToZone(pc)
        if #self.data.pieces < self.MAX_PIECES then
            self.data.pieces[#self.data.pieces + 1] = pc
            new[#self.data.pieces] = true
        end
    end
    self.sel = new
    self:Refresh()
end

function ED:CopySelected()
    local list = self:Selected()
    if #list == 0 then return end
    self.clip = {}
    local cx, cy = self:Centre(list)
    for _, i in ipairs(list) do
        local pc = copy(self.data.pieces[i])
        pc.x, pc.y = pc.x - cx, pc.y - cy
        pc.mv = nil
        self.clip[#self.clip + 1] = pc
    end
    self:Status(("%d piece%s copied."):format(#list, #list == 1 and "" or "s"))
end

function ED:Paste(x, y)
    if not self.clip or #self.clip == 0 then return end
    self:PushUndo()
    x, y = x or W / 2, y or 300
    local new = {}
    for _, src in ipairs(self.clip) do
        if #self.data.pieces >= self.MAX_PIECES then break end
        local pc = copy(src)
        pc.x, pc.y = self:Snap(x + pc.x), self:Snap(y + pc.y)
        clampToZone(pc)
        self.data.pieces[#self.data.pieces + 1] = pc
        new[#self.data.pieces] = true
    end
    self.sel = new
    self:Refresh()
end

-- the selection's settings
function ED:ForSelected(fn, undo)
    local list = self:Selected()
    if #list == 0 then return self:Status("Select some pieces first.") end
    if undo ~= false then self:PushUndo() end
    for _, i in ipairs(list) do fn(self.data.pieces[i], i) end
    self:Refresh()
end

function ED:SetHp(hp)
    self:ForSelected(function(pc)
        if pc.t == "peg" or pc.t == "brick" then pc.hp = (hp > 1) and hp or nil
        elseif pc.t == "egg" then pc.hp = math.max(2, hp) end
    end)
end

-- A peg's or brick's colour: dealt at random (nil), or set for good.
ED.COLORS = { false, "orange", "blue", "green" }
ED.COLOR_NAMES = { orange = "Orange", blue = "Blue", green = "Green" }
function ED:SelColor()
    local c, first = nil, true
    for _, i in ipairs(self:Selected()) do
        local pc = self.data.pieces[i]
        if pc.t == "peg" or pc.t == "brick" then
            local this = pc.c or false
            if first then c, first = this, false elseif c ~= this then return "mixed" end
        end
    end
    if first then return nil end
    return c
end

function ED:CycleColor()
    local cur = self:SelColor()
    if cur == nil then return self:Status("Select pegs or bricks to set their color.") end
    local k = 0
    for i, c in ipairs(self.COLORS) do if c == cur then k = i end end
    local nextC = self.COLORS[(k % #self.COLORS) + 1]
    self:ForSelected(function(pc)
        if pc.t == "peg" or pc.t == "brick" then pc.c = nextC or nil; pc.o = nil end
    end)
end

-- Never dealt this colour on any attempt ("o" orange, "g" green, "p" purple).
function ED:SelExcludes(letter)
    local any, all = false, true
    for _, i in ipairs(self:Selected()) do
        local pc = self.data.pieces[i]
        if pc.t == "peg" or pc.t == "brick" then
            if pc.no and pc.no:find(letter, 1, true) then any = true else all = false end
        end
    end
    return any and all
end

function ED:ToggleExclude(letter)
    local on = not self:SelExcludes(letter)
    self:ForSelected(function(pc)
        if pc.t == "peg" or pc.t == "brick" then
            local no = (pc.no or ""):gsub(letter, "")
            if on then no = no .. letter end
            pc.no = (no ~= "") and no or nil
        end
    end)
end

function ED:Resize(step)
    self:ForSelected(function(pc)
        if pc.t == "brick" then
            -- bricks step through the standard sizes
            local sizes, k = self.BRICK_SIZES, 1
            for j, w in ipairs(sizes) do if (pc.w or E.BRICK_W) >= w - 0.5 then k = j end end
            pc.w = sizes[math.max(1, math.min(#sizes, k + step))]
        elseif isBar(pc) then pc.w = math.max(12, math.min(300, (pc.w or 30) + step * 6))
        elseif pc.t == "balloon" then
            local sizes = L.BALLOON_SIZES
            local k = 1
            for j, r in ipairs(sizes) do if (pc.r or 16) >= r then k = j end end
            pc.r = sizes[math.max(1, math.min(#sizes, k + step))]
        elseif pc.t == "rblock" then pc.r = math.max(6, math.min(30, (pc.r or 11) + step * 2)) end
    end)
end

local function unusedName(prefix, used)
    for k = 1, 999 do
        if not used[prefix .. k] then return prefix .. k end
    end
    return prefix .. "x"
end

function ED:MakeRail()
    local bricks = {}
    for _, i in ipairs(self:Selected()) do if self.data.pieces[i].t == "brick" then bricks[#bricks + 1] = i end end
    if #bricks < 3 then return self:Status("A rail needs at least three bricks selected.") end
    local used = {}
    for _, pc in ipairs(self.data.pieces) do if pc.rail then used[pc.rail] = true end end
    local name = unusedName("rail", used)
    self:PushUndo()
    for _, i in ipairs(bricks) do self.data.pieces[i].rail = name end
    self:Status(("Rail made from %d bricks. A ball meeting it from the inside rides it."):format(#bricks))
    self:Refresh()
end

-- The dragged path, evened out to points SLIDE_STEP apart along it; a
-- brick between each pair, end to end, all one rail.
function ED:SlidePoints(pts)
    if not pts or #pts < 2 then return {} end
    local out = { { pts[1][1], pts[1][2] } }
    local step = self.SLIDE_STEP
    local need = step
    for k = 2, #pts do
        local ax, ay = pts[k - 1][1], pts[k - 1][2]
        local bx, by = pts[k][1], pts[k][2]
        local seg = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        local pos = 0
        while seg - pos >= need do
            pos = pos + need
            local f = pos / seg
            out[#out + 1] = { ax + (bx - ax) * f, ay + (by - ay) * f }
            need = step
        end
        need = need - (seg - pos)
    end
    -- the cut end: what is left of the path after the last full brick
    local last, tail = out[#out], pts[#pts]
    local rest = sqrt((tail[1] - last[1]) ^ 2 + (tail[2] - last[2]) ^ 2)
    if rest >= self.MIN_CUT then out[#out + 1] = { tail[1], tail[2] } end
    return out
end

-- rail: true for a Super Slide; a plain row of bricks otherwise
function ED:AddSlide(pts, plain)
    local even = self:SlidePoints(pts)
    if #even < (plain and 2 or 4) then return nil end
    self:PushUndo()
    local used = {}
    for _, pc in ipairs(self.data.pieces) do if pc.rail then used[pc.rail] = true end end
    local name = (not plain) and unusedName("rail", used) or nil
    local made, new = 0, {}
    for k = 2, #even do
        if #self.data.pieces >= self.MAX_PIECES then break end
        local a, b = even[k - 1], even[k]
        local pc = { t = "brick", x = (a[1] + b[1]) / 2, y = (a[2] + b[2]) / 2,
            a = atan2(b[2] - a[2], b[1] - a[1]), w = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2), rail = name }
        clampToZone(pc)
        self.data.pieces[#self.data.pieces + 1] = pc
        new[#self.data.pieces] = true
        made = made + 1
    end
    self.sel = new
    return made
end

-- Arcs and circles for slides, as fine polylines that AddSlide lays bricks
-- along. An arc runs from (x0, y0) to (x1, y1) through (x2, y2); three
-- points in a line give a straight row.
ED.CIRCLE_MIN_R = 24
function ED:ArcPoints(x0, y0, x1, y1, x2, y2)
    local d = 2 * (x0 * (y1 - y2) + x1 * (y2 - y0) + x2 * (y0 - y1))
    if abs(d) < 1e-6 then return { { x0, y0 }, { x1, y1 } } end
    local s0, s1, s2 = x0 * x0 + y0 * y0, x1 * x1 + y1 * y1, x2 * x2 + y2 * y2
    local cx = (s0 * (y1 - y2) + s1 * (y2 - y0) + s2 * (y0 - y1)) / d
    local cy = (s0 * (x2 - x1) + s1 * (x0 - x2) + s2 * (x1 - x0)) / d
    local r = sqrt((x0 - cx) ^ 2 + (y0 - cy) ^ 2)
    if r > 4000 then return { { x0, y0 }, { x1, y1 } } end
    local a0, a1, a2 = atan2(y0 - cy, x0 - cx), atan2(y1 - cy, x1 - cx), atan2(y2 - cy, x2 - cx)
    local function norm(v) v = v % (2 * pi) return v end
    -- going the way that passes the bend point
    local sweep = norm(a1 - a0)
    if norm(a2 - a0) > sweep then sweep = sweep - 2 * pi end
    local steps = math.max(8, floor(abs(sweep) * r / 3))
    local pts = {}
    for k = 0, steps do
        local a = a0 + sweep * k / steps
        pts[#pts + 1] = { cx + r * cos(a), cy + r * sin(a) }
    end
    return pts
end

-- a ring round (cx, cy), open at the top by about one brick: its mouth
function ED:CirclePoints(cx, cy, r)
    if not r or r < 1 then return {} end
    local gap = math.min(pi / 2, (E.BRICK_W * 1.2) / r)
    local a0 = -pi / 2 + gap / 2
    local sweep = 2 * pi - gap
    local steps = math.max(16, floor(sweep * r / 3))
    local pts = {}
    for k = 0, steps do
        local a = a0 + sweep * k / steps
        pts[#pts + 1] = { cx + r * cos(a), cy + r * sin(a) }
    end
    return pts
end

function ED:CancelArc()
    if self.arc then
        self.arc = nil
        if self.field then self:DrawSlidePath(nil) end
    end
end

function ED:DrawSlidePath(pts)
    self.slideDots = self.slideDots or {}
    local even = pts and self:SlidePoints(pts) or {}
    for i, p in ipairs(even) do
        local d = self.slideDots[i]
        if not d then
            d = self.field:CreateTexture(nil, "OVERLAY", nil, 5)
            d:SetTexture(WHITE)
            d:SetSize(5, 5)
            d:SetVertexColor(0.4, 1, 0.9, 0.9)
            self.slideDots[i] = d
        end
        place(d, self.field, p[1], p[2])
        d:Show()
    end
    for i = #even + 1, #self.slideDots do self.slideDots[i]:Hide() end
end

function ED:ClearRail()
    self:ForSelected(function(pc) pc.rail = nil end)
end

function ED:LinkLock()
    local keys, cages = 0, 0
    for _, i in ipairs(self:Selected()) do
        local t = self.data.pieces[i].t
        if t == "key" then keys = keys + 1 elseif t == "cage" then cages = cages + 1 end
    end
    if keys == 0 or cages == 0 then return self:Status("Select a key and the cage bars it opens.") end
    local used = {}
    for _, pc in ipairs(self.data.pieces) do if pc.id then used[pc.id] = true end end
    local id = unusedName("lock", used)
    self.lastLock = id
    self:ForSelected(function(pc) if pc.t == "key" or pc.t == "cage" then pc.id = id end end)
    self:Status(("Linked: lighting the key opens %d cage bar%s."):format(cages, cages == 1 and "" or "s"))
end

function ED:ToggleSilver()
    self:ForSelected(function(pc) if pc.t == "key" or pc.t == "cage" then pc.s = (not pc.s) or nil end end)
end

-- The selection's mover: one shared by every selected piece, or none.
function ED:SelMover()
    local mv
    for _, i in ipairs(self:Selected()) do
        local m = self.data.pieces[i].mv
        if not m then return nil end
        if mv and mv ~= m then return nil end
        mv = m
    end
    return mv
end

function ED:CycleMover()
    local list = self:Selected()
    if #list == 0 then return self:Status("Select the pieces that should move together.") end
    self:PushUndo()
    local mv = self:SelMover()
    local movers = self.data.movers
    if not mv then
        if #movers >= self.MAX_MOVERS then return self:Status("At most " .. self.MAX_MOVERS .. " moving groups.") end
        movers[#movers + 1] = { k = "slide", amp = 60, speed = 1, phase = 0 }
        mv = #movers
        for _, i in ipairs(list) do self.data.pieces[i].mv = mv end
    else
        local m = movers[mv]
        local nextK
        for j, k in ipairs(L.EDIT_MOVERS) do if k == m.k then nextK = L.EDIT_MOVERS[j + 1] end end
        if nextK then
            m.k = nextK
            if nextK == "swing" then m.amp = 0.6 elseif nextK == "slide" or nextK == "lift" then m.amp = 60 end
        else
            for _, i in ipairs(list) do self.data.pieces[i].mv = nil end
        end
    end
    self:CompactMovers()
    self:Refresh()
end

-- drop movers nothing uses and renumber the rest
function ED:CompactMovers()
    local used, map, new = {}, {}, {}
    for _, pc in ipairs(self.data.pieces) do if pc.mv then used[pc.mv] = true end end
    for i, m in ipairs(self.data.movers) do
        if used[i] then new[#new + 1] = m; map[i] = #new end
    end
    for _, pc in ipairs(self.data.pieces) do if pc.mv then pc.mv = map[pc.mv] end end
    self.data.movers = new
end

function ED:TuneMover(what, step)
    local mv = self:SelMover()
    if not mv then return self:Status("Select a moving group (all its pieces) first.") end
    self:PushUndo()
    local m = self.data.movers[mv]
    if what == "amp" then
        if m.k == "swing" then m.amp = math.max(0.05, math.min(1.5, m.amp + step * 0.1))
        else m.amp = math.max(5, math.min(200, m.amp + step * 10)) end
    elseif what == "speed" then
        local sgn = (m.speed < 0) and -1 or 1
        m.speed = sgn * math.max(0.1, math.min(5, abs(m.speed) + step * 0.2))
    elseif what == "reverse" then
        m.speed = -m.speed
    end
    self:Refresh()
end

-- ---------------------------------------------------------------------
-- From a generated (or approved) level into the editor

function ED:FromSpec(spec)
    local d = self:NewData()
    d.name = ""
    d.level = spec.level or 1
    local o = spec.objective
    d.goals = { oranges = (o ~= "eggs" and o ~= "gems" and o ~= "longshots") or nil,
        longshots = (o == "longshots") and spec.goal or nil }
    if o ~= "eggs" and o ~= "gems" then d.oranges = spec.orange end
    d.noBucket = spec.noBucket
    local index = {}
    for _, p in ipairs(spec.pegs) do
        if not p.cradle and not p.post and p.kind ~= "boss" and p.kind ~= "web" and not p.scrap then
            local x, y, a = p.bx or p.x, p.by or p.y, p.bangle or p.angle
            local pc
            if p.shape == "brick" then
                if p.kind == "block" and p.lock then pc = { t = "cage", w = p.w, id = p.lock, s = p.silver }
                elseif p.kind == "block" then pc = { t = "block", w = p.w }
                else pc = { t = "brick", w = p.w, rail = p.rail, c = p.forceOrange and "orange" or nil } end
                pc.a = a
            elseif p.kind == "block" then pc = { t = "rblock", r = p.r }
            elseif p.kind == "bumper" and p.balloon then pc = { t = "balloon", r = p.r }
            elseif p.kind == "bumper" then pc = { t = "bumper" }
            elseif p.kind == "key" then pc = { t = "key", id = p.unlocks, s = p.silver }
            elseif p.kind == "egg" then pc = { t = "egg", hp = p.maxhp or p.hp }
            elseif p.kind == "gem" then pc = { t = "gem" }
            else pc = { t = "peg", c = p.forceOrange and "orange" or nil } end
            pc.x, pc.y = x, y
            local hp = p.maxhp or p.hp or 1
            if hp > 1 and (pc.t == "peg" or pc.t == "brick") then pc.hp = hp end
            d.pieces[#d.pieces + 1] = pc
            index[p] = #d.pieces
        end
    end
    for _, mv in ipairs(spec.movers or {}) do
        local m = { k = mv.kind, amp = mv.amp or 60, speed = mv.speed or 1, phase = mv.phase or 0 }
        local any = false
        for _, p in ipairs(mv.pegs) do if index[p] then any = true end end
        if any and #d.movers < self.MAX_MOVERS then
            d.movers[#d.movers + 1] = m
            for _, p in ipairs(mv.pegs) do if index[p] then d.pieces[index[p]].mv = #d.movers end end
        end
    end
    return self:Sanitize(d)
end

-- ---------------------------------------------------------------------
-- Saving, loading, sharing

function ED:Status(text)
    if self.statusText then self.statusText:SetText(text or "") end
    self.statusAt = GetTime and GetTime() or 0
end

function ED:Save()
    local name = self.nameBox and self.nameBox:GetText() or self.data.name
    name = str(name, 40) or ""
    if name == "" then return self:Status("Give the level a name first.") end
    self.data.name = name
    self.data.author = self.data.author or playerName()
    self:CompactMovers()
    self:DB().levels[name] = self:Sanitize(self.data)
    self.dirty = false
    self:Status("Saved as \"" .. name .. "\".")
end

function ED:Load(name)
    local d = self:DB().levels[name]
    if not d then return self:Status("No saved level called \"" .. tostring(name) .. "\".") end
    self:SetData(self:Sanitize(d))
    self:Status("Loaded \"" .. name .. "\".")
end

function ED:DeleteSaved(name)
    if not self:DB().levels[name] then return end
    self:DB().levels[name] = nil
    self:Status("Deleted \"" .. name .. "\".")
end

function ED:SavedNames()
    local list = {}
    for name in pairs(self:DB().levels) do list[#list + 1] = name end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    return list
end

function ED:ExportCode()
    self.data.name = (self.nameBox and str(self.nameBox:GetText(), 40)) or self.data.name
    self.data.author = self.data.author or playerName()
    return self:Encode(self.data)
end

-- the owner's characters only: a shared code comes in as a saved level
function ED:Import(code)
    if not self:IsOwner() then return self:Status("Importing levels is for the game's owner.") end
    local d, why = self:Decode(code)
    if not d then return self:Status(why) end
    local base = (d.name ~= "" and d.name or "Imported") .. (d.author and (" (" .. d.author .. ")") or "")
    local name, k = base, 1
    while self:DB().levels[name] do k = k + 1; name = base .. " " .. k end
    d.name = name
    d.imported = true
    self:DB().levels[name] = d
    self:SetData(copy(d))
    self:Status("Imported as \"" .. name .. "\". Test it, then approve it for a level number.")
    return true
end

-- the owner's characters only: this level replaces level n (on the owner's
-- client at once; for everyone once it is written into CustomLevels.lua)
function ED:Approve(n)
    if not self:IsOwner() then return self:Status("Approving levels is for the game's owner.") end
    n = floor(num(n, 1, L.COUNT, 1))
    if #self.data.pieces == 0 then return self:Status("An empty level cannot be approved.") end
    self:CompactMovers()
    local d = self:Sanitize(self.data)
    d.level = n
    -- only a submitted level names its builder; the owner's own carry no credit
    if not d.imported then d.author = nil end
    self:DB().approved[n] = d
    self:Status(("Approved for level %d. It replaces that level on this account now; ask for the approved levels to be imported into the addon to ship it."):format(n))
end

function ED:Unapprove(n)
    if not self:IsOwner() then return end
    n = floor(num(n, 1, L.COUNT, 1))
    if not self:DB().approved[n] then return self:Status(("Level %d has no approved replacement."):format(n)) end
    self:DB().approved[n] = nil
    self:Status(("Level %d is back to its generated layout on this account."):format(n))
end

-- play it on the board; the editor comes back afterwards
function ED:Test()
    if #self.data.pieces == 0 then return self:Status("Put some pieces on the board first.") end
    self:CompactMovers()
    local d = self:Sanitize(self.data)
    self.testing = true
    if self.frame then self.frame:Hide() end
    GP.UI:StartCustom(d, d.level or 1)
end

function ED:ReturnFromTest()
    if not self.testing then return end
    self.testing = nil
    self:Show()
end

-- what is wrong with the level, briefly
function ED:Problems()
    local out = {}
    local pieces = self.data.pieces
    local lit, unreach = 0, 0
    for _, pc in ipairs(pieces) do
        if pc.t == "peg" or pc.t == "brick" then lit = lit + 1 end
        local r = isBar(pc) and select(2, self:BarSize(pc)) / 2 or self:PieceRadius(pc)
        if pc.y + r + E.BALL_R < L:ReachFloor(pc.x) - 2 then unreach = unreach + 1 end
    end
    if unreach > 0 then out[#out + 1] = unreach .. " out of the ball's reach (red)" end
    local goals = self.data.goals or {}
    if (goals.oranges or goals.longshots) and lit < 3 then out[#out + 1] = "needs pegs or bricks to light" end
    local eggs, gems = 0, 0
    for _, pc in ipairs(pieces) do
        if pc.t == "egg" then eggs = eggs + 1 elseif pc.t == "gem" then gems = gems + 1 end
    end
    if not goals.oranges and not goals.longshots and eggs == 0 and gems == 0 then
        out[#out + 1] = "no goal: turn on oranges or Long Shots, or place eggs or gems"
    end
    local keys, cages = {}, {}
    for _, pc in ipairs(pieces) do
        if pc.t == "key" then keys[pc.id or "lock1"] = true elseif pc.t == "cage" then cages[pc.id or "lock1"] = true end
    end
    for id in pairs(cages) do if not keys[id] then out[#out + 1] = "a cage with no key"; break end end
    return out
end

-- ---------------------------------------------------------------------
-- The window

local function button(parent, w, h, text, onClick, tip)
    local b = GP.UI.MakeButton(parent, w, h, text)
    if b.text then b.text:SetFont("Fonts\\FRIZQT__.TTF", (h >= 26) and 12 or 11, "OUTLINE") end
    b:SetScript("OnClick", onClick)
    if tip then
        local enter, leave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
        b:SetScript("OnEnter", function(self)
            if enter then enter(self) end
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function(self)
            if leave then leave(self) end
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    return b
end

local function text(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size or 12, "")
    fs:SetTextColor(r or 1, g or 0.9, b or 0.6)
    fs:SetJustifyH("LEFT")
    return fs
end

local function editBox(parent, w, h)
    local ok, eb = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
    if not ok or not eb then eb = CreateFrame("EditBox", nil, parent) end
    eb:SetSize(w, h)
    eb:SetAutoFocus(false)
    if eb.SetFontObject and ChatFontNormal then eb:SetFontObject(ChatFontNormal) end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

ED.FIELD_X, ED.FIELD_Y = 176, -96
ED.FRAME_W, ED.FRAME_H = 1010, 900

function ED:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "GnomishPachinkoEditor", UIParent)
    frame:SetSize(self.FRAME_W, self.FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(40)
    frame.skin = ART:NewSkin(frame, "frame_bg", "BACKGROUND", -8)
    frame:Hide()
    self.frame = frame
    if UISpecialFrames then tinsert(UISpecialFrames, "GnomishPachinkoEditor") end

    local title = text(frame, 20, 1, 0.85, 0.2)
    title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    title:SetPoint("TOP", 0, -26)
    title:SetText("Level Editor")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() ED:Hide() end)

    -- ===== the board =====
    local field = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    field:SetSize(W, H)
    field:SetPoint("TOPLEFT", frame, "TOPLEFT", self.FIELD_X, self.FIELD_Y)
    if field.SetBackdrop then
        field:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
        field:SetBackdropColor(0.03, 0.04, 0.14, 1)
        field:SetBackdropBorderColor(0.45, 0.35, 0.70, 1)
    end
    local bg = field:CreateTexture(nil, "BACKGROUND", nil, 0)
    bg:SetAllPoints(field)
    bg:SetAlpha(0.55)
    self.fieldBg = bg
    self.field = field
    local function line(x0, y0, x1, y1, r, g, b, a)
        local t = field:CreateTexture(nil, "BACKGROUND", nil, 2)
        t:SetTexture(WHITE)
        t:SetVertexColor(r, g, b, a)
        t:SetPoint("TOPLEFT", field, "TOPLEFT", math.min(x0, x1), -math.min(y0, y1))
        t:SetSize(math.max(1, abs(x1 - x0)), math.max(1, abs(y1 - y0)))
        return t
    end
    local z = self.ZONE
    line(z.x0, z.y0, z.x1, z.y0, 0.6, 0.6, 1, 0.35)
    line(z.x0, z.y1, z.x1, z.y1, 0.6, 0.6, 1, 0.35)
    line(z.x0, z.y0, z.x0, z.y1, 0.6, 0.6, 1, 0.35)
    line(z.x1, z.y0, z.x1, z.y1, 0.6, 0.6, 1, 0.35)
    for y = z.y0, z.y1, 12 do line(W / 2, y, W / 2, y + 5, 1, 1, 1, 0.18) end
    -- the cannon at the top and the bucket at the bottom, for reference
    local cannon = field:CreateTexture(nil, "BACKGROUND", nil, 3)
    ART:Set(cannon, "ball")
    cannon:SetSize(18, 18)
    cannon:SetPoint("CENTER", field, "TOPLEFT", W / 2, -40)
    local bucket = text(field, 11, 0.7, 0.7, 0.9)
    bucket:SetPoint("BOTTOM", field, "BOTTOM", 0, 14)
    bucket:SetText("the bucket slides along down here")
    self.gridTex = {}

    field:EnableMouse(true)
    field:SetScript("OnMouseDown", function(_, btn) ED:OnMouseDown(btn) end)
    field:SetScript("OnMouseUp", function(_, btn) ED:OnMouseUp(btn) end)
    if field.EnableMouseWheel then field:EnableMouseWheel(true) end
    field:SetScript("OnMouseWheel", function(_, delta) ED:OnWheel(delta) end)
    field:SetScript("OnEnter", function() pcall(frame.EnableKeyboard, frame, true) end)
    field:SetScript("OnLeave", function() pcall(frame.EnableKeyboard, frame, false) end)
    frame:SetScript("OnKeyDown", function(_, key) ED:OnKey(key) end)
    pcall(frame.EnableKeyboard, frame, false)
    frame:SetScript("OnUpdate", function() ED:OnUpdate() end)

    self.pieceTex = {}
    -- the box drawn while selecting
    local box = field:CreateTexture(nil, "OVERLAY", nil, 6)
    box:SetTexture(WHITE)
    box:SetVertexColor(0.4, 0.8, 1, 0.18)
    box:Hide()
    self.boxTex = box
    -- the bar being drawn with a bar tool
    local ghost = field:CreateTexture(nil, "OVERLAY", nil, 5)
    ghost:SetTexture(WHITE)
    ghost:SetVertexColor(1, 1, 1, 0.35)
    ghost:Hide()
    self.ghostTex = ghost

    -- ===== the tools, on the left =====
    local tools = text(frame, 13)
    tools:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -96)
    tools:SetText("Tools")
    self.toolBtns = {}
    for i, id in ipairs(self.TOOLS) do
        local name = self.TOOL_NAMES[id] or L.EDIT_TYPES[id].name
        local b = button(frame, 136, 24, name, function() ED:SetTool(id) end)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -114 - (i - 1) * 27)
        b.toolId = id
        self.toolBtns[id] = b
    end
    local y = -114 - #self.TOOLS * 27 - 8
    self.snapBtn = button(frame, 136, 24, "Snap: off", function() ED:CycleSnap() end,
        "Snap new and moved pieces to a grid.")
    self.snapBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, y)
    y = y - 27
    local undo = button(frame, 136, 24, "Undo", function() ED:Undo() end, "Ctrl+Z")
    undo:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, y)
    y = y - 27
    local help = button(frame, 136, 24, "Help", function() ED:ToggleHelp() end)
    help:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, y)
    y = y - 34
    self.countText = text(frame, 11, 0.8, 0.8, 0.95)
    self.countText:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, y)
    self.countText:SetWidth(136)
    self.countText:SetJustifyV("TOP")

    -- ===== the level and the selection, on the right =====
    local rx = self.FIELD_X + W + 16
    local function rtext(yy, s, size)
        local fs = text(frame, size or 12)
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", rx, yy)
        fs:SetText(s or "")
        return fs
    end
    local function rbtn(col, yy, w, label, fn, tip)
        local b = button(frame, w, 22, label, fn, tip)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", rx + col, yy)
        return b
    end
    rtext(-96, "Level", 14)
    rtext(-118, "Name")
    self.nameBox = editBox(frame, 230, 20)
    self.nameBox:SetPoint("TOPLEFT", frame, "TOPLEFT", rx + 50, -114)
    self.nameBox:SetScript("OnTextChanged", function(eb, user) if user then ED.data.name = str(eb:GetText(), 40) or "" end end)
    -- the goals, any mix: oranges, Long Shots, and every egg and gem placed
    self.objBtn = rbtn(0, -142, 96, "Oranges: on", function() ED:ToggleGoal("oranges") end,
        "Lighting every orange is a goal. Eggs and gems on the board are always goals too.")
    self.longBtn = rbtn(100, -142, 96, "Long Shots: off", function() ED:ToggleGoal("longshots") end,
        "Long Shots wanted: off, 1 to 5. A Long Shot is two oranges far apart lit in one shot.")
    self.bucketBtn = rbtn(200, -142, 86, "Bucket: yes", function() ED:ToggleBucket() end)
    self.orangeText = rtext(-170, "")
    rbtn(156, -166, 40, "-", function() ED:Tune("oranges", -1) end)
    rbtn(200, -166, 40, "+", function() ED:Tune("oranges", 1) end)
    rbtn(244, -166, 42, "Auto", function() ED:Tune("oranges", 0) end, "Deal about a third of the pegs and bricks as orange.")
    self.levelText = rtext(-194, "")
    rbtn(156, -190, 40, "-", function() ED:Tune("level", -1) end)
    rbtn(200, -190, 40, "+", function() ED:Tune("level", 1) end)
    rbtn(244, -190, 42, "+10", function() ED:Tune("level", 10) end)
    self.copyBtn = rbtn(0, -216, 286, "Start from this level's layout", function() ED:CopyLevel() end,
        "Replace the board with the layout of the level number above (its pieces, moving parts and goal), to edit.")

    rtext(-250, "Selection", 14)
    self.selText = rtext(-272, "")
    rbtn(0, -292, 92, "Normal", function() ED:SetHp(1) end, "One hit to light.")
    rbtn(97, -292, 92, "Steel", function() ED:SetHp(2) end, "Two hits (an egg: two to hatch).")
    rbtn(194, -292, 92, "Gold", function() ED:SetHp(3) end, "Three hits.")
    self.colorBtn = rbtn(0, -317, 140, "Color: dealt", function() ED:CycleColor() end,
        "Pegs and bricks: dealt at random on every attempt, or set to orange, blue or green for good.")
    rbtn(146, -317, 68, "Smaller", function() ED:Resize(-1) end, "Bars shorter, balloons and studs smaller.")
    rbtn(218, -317, 68, "Bigger", function() ED:Resize(1) end)
    -- turning by an exact number of degrees, or setting a bar's angle outright
    rbtn(0, -342, 40, "-", function() ED:TurnBy(-1) end, "Turn the selection round its middle by the degrees in the box, anticlockwise (Q / E turn 5).")
    self.degBox = editBox(frame, 46, 20)
    self.degBox:SetPoint("TOPLEFT", frame, "TOPLEFT", rx + 50, -343)
    self.degBox:SetText("15")
    if self.degBox.SetJustifyH then self.degBox:SetJustifyH("CENTER") end
    self.degBox:SetScript("OnEnterPressed", function(eb) eb:ClearFocus(); ED:TurnBy(1) end)
    rbtn(102, -342, 40, "+", function() ED:TurnBy(1) end, "Turn the selection by the degrees in the box, clockwise. Enter in the box does the same.")
    rbtn(148, -342, 138, "Set angle", function() ED:SetAngle() end,
        "Set every selected bar (brick, steel bar, cage bar) to the angle in the box, in degrees: 0 is level, 90 upright. Each turns where it stands.")
    rbtn(0, -367, 92, "Flip H", function() ED:MirrorSelected(false) end, "Mirror the selection left to right (M).")
    rbtn(97, -367, 92, "Flip V", function() ED:MirrorSelected(true) end, "Mirror the selection top to bottom.")
    rbtn(194, -367, 92, "Mirror copy", function() ED:MirrorCopyAcross() end, "A mirrored copy on the other side of the middle line.")
    rbtn(0, -392, 92, "Duplicate", function() ED:DuplicateSelected() end, "Ctrl+D")
    rbtn(97, -392, 92, "Delete", function() ED:DeleteSelected() end, "Delete")
    rbtn(194, -392, 92, "Select all", function() ED:SelectAll() end, "Ctrl+A")
    rbtn(0, -417, 140, "Make rail", function() ED:MakeRail() end, "Selected bricks become one rail: a ball meeting it from the inside rides it (a Super Slide).")
    rbtn(146, -417, 140, "Unrail", function() ED:ClearRail() end)
    rbtn(0, -442, 140, "Link key + cage", function() ED:LinkLock() end, "Selected key opens the selected cage bars.")
    rbtn(146, -442, 140, "Silver / gold", function() ED:ToggleSilver() end, "Keys and cage bars: silver or gold.")

    -- colours a dealt piece never gets on any attempt
    self.excludeBtns = {}
    for k, spec in ipairs({ { "o", "Never orange" }, { "g", "Never green" }, { "p", "Never purple" } }) do
        local letter, label = spec[1], spec[2]
        local b = rbtn((k - 1) * 97, -467, 92, label, function() ED:ToggleExclude(letter) end,
            "Pegs and bricks: never dealt this color on any attempt.")
        b.label = label
        self.excludeBtns[letter] = b
    end
    rtext(-499, "Moving parts", 14)
    self.moverText = rtext(-521, "")
    self.moverBtn = rbtn(0, -541, 286, "Make them move", function() ED:CycleMover() end,
        "The selected pieces move together: slide side to side, lift up and down, wheel round their middle, or swing like a pendulum. Click again for the next kind; after Swing they stop moving.")
    rbtn(0, -566, 68, "Range -", function() ED:TuneMover("amp", -1) end)
    rbtn(73, -566, 68, "Range +", function() ED:TuneMover("amp", 1) end)
    rbtn(146, -566, 68, "Speed -", function() ED:TuneMover("speed", -1) end)
    rbtn(218, -566, 68, "Speed +", function() ED:TuneMover("speed", 1) end)
    rbtn(0, -591, 286, "Reverse direction", function() ED:TuneMover("reverse") end)

    rtext(-625, "Files", 14)
    rbtn(0, -647, 92, "New", function() ED:NewLevel() end)
    rbtn(97, -647, 92, "Save", function() ED:Save() end, "Saved on this account, by name.")
    rbtn(194, -647, 92, "Load", function() ED:ShowList() end)
    rbtn(0, -672, 140, "Export code", function() ED:ShowCode(true) end, "A text code of this level to send to the game's owner.")
    self.testBtn = rbtn(146, -672, 140, "Test play", function() ED:Test() end, "Play it on the board. No play is spent and nothing is recorded.")
    self.importBtn = rbtn(0, -697, 140, "Import code", function() ED:ShowCode(false) end, "Owner: read a shared level code.")
    self.approveBtn = rbtn(146, -697, 140, "Approve for level", function() ED:Approve(ED.data.level) end,
        "Owner: this level replaces the level number above.")
    self.unapproveBtn = rbtn(0, -722, 286, "Remove approval for level", function() ED:Unapprove(ED.data.level) end)

    self.statusText = rtext(-755, "", 11)
    self.statusText:SetWidth(286)
    self.statusText:SetJustifyV("TOP")
    self.statusText:SetTextColor(0.75, 1, 0.75)
    self.problemText = rtext(-815, "", 11)
    self.problemText:SetWidth(286)
    self.problemText:SetJustifyV("TOP")
    self.problemText:SetTextColor(1, 0.55, 0.45)

    self:CreateList()
    self:CreateCodePanel()
    self:CreateHelp()
    self.tool = "select"
    self.snap = 0
    self:SetData(self.data or self:NewData())
end

-- the saved levels, a page at a time
ED.LIST_ROWS = 14
function ED:CreateList()
    local p = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    p:SetSize(360, 520)
    p:SetPoint("CENTER", self.field, "CENTER")
    p:SetFrameLevel(self.frame:GetFrameLevel() + 20)
    p.skin = ART:NewSkin(p, "card", "BACKGROUND", 0)
    p:EnableMouse(true)
    p:Hide()
    local t = text(p, 15)
    t:SetPoint("TOP", 0, -18)
    t:SetText("Saved levels")
    p.rows = {}
    for i = 1, self.LIST_ROWS do
        local b = button(p, 230, 24, "", function(self) if self.levelName then ED:Load(self.levelName); p:Hide() end end)
        b:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -46 - (i - 1) * 29)
        local del = button(p, 70, 24, "Delete", function(self)
            if not self.levelName then return end
            if self.armed then ED:DeleteSaved(self.levelName); ED:ListPage(ED.listPage) return end
            self.armed = true
            self.text:SetText("Sure?")
        end)
        del:SetPoint("LEFT", b, "RIGHT", 6, 0)
        b.del = del
        p.rows[i] = b
    end
    p.prev = button(p, 80, 24, "Prev", function() ED:ListPage(ED.listPage - 1) end)
    p.prev:SetPoint("BOTTOMLEFT", 24, 18)
    p.next = button(p, 80, 24, "Next", function() ED:ListPage(ED.listPage + 1) end)
    p.next:SetPoint("BOTTOM", 0, 18)
    local cancel = button(p, 80, 24, "Close", function() p:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT", -24, 18)
    p.empty = text(p, 12, 0.8, 0.8, 0.9)
    p.empty:SetPoint("CENTER")
    p.empty:SetText("Nothing saved yet.")
    self.listPanel = p
end

function ED:ShowList()
    self.codePanel:Hide()
    self:ListPage(1)
    self.listPanel:Show()
end

function ED:ListPage(page)
    local names = self:SavedNames()
    local pages = math.max(1, math.ceil(#names / self.LIST_ROWS))
    page = math.max(1, math.min(pages, page or 1))
    self.listPage = page
    local p = self.listPanel
    for i, b in ipairs(p.rows) do
        local name = names[(page - 1) * self.LIST_ROWS + i]
        b.levelName = name
        b.del.levelName = name
        b.del.armed = nil
        b.del.text:SetText("Delete")
        if name then b.text:SetText(name); b:Show(); b.del:Show() else b:Hide(); b.del:Hide() end
    end
    if #names == 0 then p.empty:Show() else p.empty:Hide() end
    if page > 1 then p.prev:Enable() else p.prev:Disable() end
    if page < pages then p.next:Enable() else p.next:Disable() end
end

-- the code box: export shows this level's code to copy; import takes one
function ED:CreateCodePanel()
    local p = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    p:SetSize(460, 220)
    p:SetPoint("CENTER", self.field, "CENTER")
    p:SetFrameLevel(self.frame:GetFrameLevel() + 20)
    p.skin = ART:NewSkin(p, "card", "BACKGROUND", 0)
    p:EnableMouse(true)
    p:Hide()
    p.title = text(p, 15)
    p.title:SetPoint("TOP", 0, -18)
    p.hint = text(p, 11, 0.85, 0.85, 0.95)
    p.hint:SetPoint("TOP", 0, -44)
    p.hint:SetWidth(400)
    p.hint:SetJustifyH("CENTER")
    local eb = editBox(p, 400, 24)
    eb:SetPoint("CENTER", 0, 4)
    if eb.SetMaxLetters then eb:SetMaxLetters(0) end
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    p.box = eb
    p.go = button(p, 120, 26, "Import", function() if ED:Import(p.box:GetText()) then p:Hide() end end)
    p.go:SetPoint("BOTTOM", -66, 20)
    local close = button(p, 120, 26, "Close", function() p:Hide() end)
    close:SetPoint("BOTTOM", 66, 20)
    self.codePanel = p
end

function ED:ShowCode(export)
    self.listPanel:Hide()
    local p = self.codePanel
    if export then
        if #self.data.pieces == 0 then return self:Status("Nothing to export yet.") end
        p.title:SetText("Level code")
        p.hint:SetText("Press Ctrl+C to copy the whole code, then send it to the game's owner (Discord, mail, a forum post). Chat links are not used.")
        p.box:SetText(self:ExportCode())
        p.go:Hide()
    else
        if not self:IsOwner() then return self:Status("Importing levels is for the game's owner.") end
        p.title:SetText("Import a level code")
        p.hint:SetText("Paste the code with Ctrl+V, then press Import. It is checked and saved as a level here.")
        p.box:SetText("")
        p.go:Show()
    end
    p:Show()
    p.box:SetFocus()
    if export then p.box:HighlightText() end
end

function ED:CreateHelp()
    local p = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    p:SetSize(440, 470)
    p:SetPoint("CENTER", self.field, "CENTER")
    p:SetFrameLevel(self.frame:GetFrameLevel() + 20)
    p.skin = ART:NewSkin(p, "card", "BACKGROUND", 0)
    p:EnableMouse(true)
    p:Hide()
    local t = text(p, 12, 0.92, 0.92, 1)
    t:SetPoint("TOPLEFT", 22, -22)
    t:SetWidth(396)
    t:SetJustifyV("TOP")
    t:SetText(table.concat({
        "|cffffd700Placing|r  Pick a piece on the left and click the board. Bars (bricks, steel bars, cage bars): click for a short one, or drag to draw one from end to end. Super Slide: drag a path and a rail of bricks is laid along it; a ball that meets it from the inside of the curve rides it. Slide arc: click the start, click the end, move to bend it, click to lay it. Slide circle: press at the middle and drag out the size (it opens at the top). Right-click or Escape cancels an arc.",
        "",
        "|cffffd700Selecting|r  With Select: click a piece, Shift+click to add or remove, or drag a box. Drag a selected piece to move the whole selection. Right-drag turns it round its middle; the mouse wheel turns it 5 degrees (Shift: 1).",
        "",
        "|cffffd700Keys|r (mouse over the board)  Delete removes, arrows nudge (Shift: 10), Q / E turn 5 degrees (Shift: 15), M mirrors, Ctrl+D duplicates, Ctrl+C / Ctrl+V copy and paste at the mouse, Ctrl+A selects all, Ctrl+Z undoes, Escape clears the selection.",
        "",
        "|cffffd700Colors|r  Pegs and bricks are dealt orange, green and blue at random on every attempt, as on the normal levels. Color sets a piece to orange, blue or green for good; Never orange / green / purple keeps a dealt piece from ever being that color. Set the number of oranges on the right.",
        "",
        "|cffffd700Goals|r  Any mix: oranges, Long Shots, and every egg and gem you place.",
        "",
        "|cffffd700Red pieces|r  are out of the ball's reach from the cannon.",
        "",
        "|cffffd700Sharing|r  Save keeps a level on this account. Export code gives a text code to send to the game's owner, who can import it, test it and approve it for a level number.",
    }, "\n"))
    local close = button(p, 120, 26, "Close", function() p:Hide() end)
    close:SetPoint("BOTTOM", 0, 18)
    self.helpPanel = p
end

function ED:ToggleHelp()
    if self.helpPanel:IsShown() then self.helpPanel:Hide() else self.helpPanel:Show() end
end

function ED:SetTool(id)
    self.tool = id
    self:CancelArc()
    self:RefreshTools()
    if id == "arc" then self:Status("Slide arc: click where it starts, click where it ends, then move the mouse to bend it and click to lay it.")
    elseif id == "circle" then self:Status("Slide circle: press at the middle and drag out the size. The ring opens at the top.") end
end

function ED:RefreshTools()
    for id, b in pairs(self.toolBtns or {}) do
        if id == self.tool then
            b.text:SetTextColor(0.5, 1, 0.5)
            ART:TintSkin(b.skin, 0.75, 1, 0.75, 1)
        else
            b.text:SetTextColor(1, 0.86, 0.35)
            ART:TintSkin(b.skin, 1, 1, 1, 1)
        end
    end
end

function ED:CycleSnap()
    local k = 1
    for i, g in ipairs(self.SNAPS) do if g == self.snap then k = i end end
    self.snap = self.SNAPS[(k % #self.SNAPS) + 1]
    self.snapBtn.text:SetText(self.snap > 0 and ("Snap: " .. self.snap .. " px") or "Snap: off")
end

local OBJ_NAMES = { classic = "Orange pegs", eggs = "Eggs", gems = "Gems", longshots = "Long Shots" }
function ED:ToggleGoal(which)
    self:PushUndo()
    local g = self.data.goals or {}
    self.data.goals = g
    if which == "oranges" then
        g.oranges = (not g.oranges) or nil
    else
        local n = g.longshots or 0
        n = n + 1
        if n > 5 then n = 0 end
        g.longshots = (n > 0) and n or nil
    end
    self:Refresh()
end

function ED:ToggleBucket()
    self:PushUndo()
    self.data.noBucket = (not self.data.noBucket) or nil
    self:Refresh()
end

function ED:Tune(what, step)
    local d = self.data
    if what == "oranges" then
        if step == 0 then d.oranges = nil
        else d.oranges = math.max(0, math.min(200, (d.oranges or self:AutoOranges()) + step)) end
    elseif what == "level" then
        d.level = math.max(1, math.min(L.COUNT, (d.level or 1) + step))
    end
    self:Refresh()
end

function ED:AutoOranges()
    local n = 0
    for _, pc in ipairs(self.data.pieces) do if pc.t == "peg" or pc.t == "brick" then n = n + 1 end end
    return math.max(1, floor(n * 0.3 + 0.5))
end

function ED:CopyLevel()
    local n = self.data.level or 1
    self:PushUndo()
    local d = self:FromSpec(L:Build(n))
    d.level = n
    self:SetData(d, true)
    self:Status(("Level %d's layout is on the board. Save it under a new name to keep it."):format(n))
end

function ED:NewLevel()
    if #self.data.pieces > 0 then self:PushUndo() end
    local lvl = self.data.level
    self:SetData(self:NewData(), true)
    self.data.level = lvl or 1
    self:Refresh()
    self:Status("A blank board.")
end

function ED:SelectAll()
    self.sel = {}
    for i in ipairs(self.data.pieces) do self.sel[i] = true end
    self:Refresh()
end

-- ---------------------------------------------------------------------
-- Drawing


function ED:TexFor(i)
    local t = self.pieceTex[i]
    if not t then
        local f = self.field
        t = { extra = {} }
        t.rim = f:CreateTexture(nil, "ARTWORK", nil, 0)
        t.body = f:CreateTexture(nil, "ARTWORK", nil, 1)
        t.sel = f:CreateTexture(nil, "OVERLAY", nil, 2)
        t.tag = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t.tag:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        self.pieceTex[i] = t
    end
    return t
end

function ED:ExtraTex(t, k)
    local e = t.extra[k]
    if not e then
        e = self.field:CreateTexture(nil, "ARTWORK", nil, 0)
        t.extra[k] = e
    end
    return e
end

function ED:DrawPiece(i, pc)
    local f = self.field
    local t = self:TexFor(i)
    local made = L:CustomPieces(pc)
    local p = made[1]
    if not p then return end
    p.kind = p.kind or "blue"
    if pc.c then p.kind = pc.c end
    local slot = GP.UI.PieceSlot(p, "")
    ART:Set(t.body, slot)
    local sel = self.sel[i]
    local r, g, b = 1, 1, 1
    local rad = isBar(pc) and select(2, self:BarSize(pc)) / 2 or self:PieceRadius(pc)
    if pc.y + rad + E.BALL_R < L:ReachFloor(pc.x) - 2 then r, g, b = 1, 0.35, 0.35 end
    t.body:SetVertexColor(r, g, b, 1)
    if isBar(pc) then
        local w, h = self:BarSize(pc)
        t.body:SetSize(ART:Size(slot, w, h))
        t.sel:SetTexture(WHITE)
        t.sel:SetSize(w + 8, h + 8)
        if t.body.SetRotation then t.body:SetRotation(-(pc.a or 0)); t.sel:SetRotation(-(pc.a or 0)); t.rim:SetRotation(-(pc.a or 0)) end
        ART:Set(t.rim, "brick", 1, 1, 1)
        t.rim:SetSize(w + 5, h + 5)
    else
        local rr = self:PieceRadius(pc)
        t.body:SetSize(ART:Size(slot, rr * 2 + 2))
        ART:Set(t.sel, "ring", 1, 1, 1)
        t.sel:SetSize(rr * 2 + 14, rr * 2 + 14)
        if t.body.SetRotation then t.body:SetRotation(0); t.sel:SetRotation(0); t.rim:SetRotation(0) end
        ART:Set(t.rim, "rim", 1, 1, 1)
        t.rim:SetSize(rr * 2 + 8, rr * 2 + 8)
    end
    for _, tex in ipairs({ t.body, t.sel, t.rim }) do place(tex, f, pc.x, pc.y) end
    t.body:Show()
    if sel then
        t.sel:SetVertexColor(0.35, 0.9, 1, isBar(pc) and 0.55 or 1)
        t.sel:Show()
    else
        t.sel:Hide()
    end
    local rimColor = GP.UI.ToughLook((pc.t == "peg" or pc.t == "brick") and (pc.hp or 1) or 1, pc.hp or 1)
    if rimColor then
        t.rim:SetVertexColor(rimColor[1], rimColor[2], rimColor[3], 1)
        t.rim:Show()
    else
        t.rim:Hide()
    end
    -- an egg's or gem's cradle, drawn faintly
    local k = 0
    for j = 2, #made do
        local q = made[j]
        k = k + 1
        local e = self:ExtraTex(t, k)
        ART:Set(e, "brick_blue")
        e:SetSize(q.w, q.h)
        if e.SetRotation then e:SetRotation(-(q.angle or 0)) end
        e:SetAlpha(0.6)
        place(e, f, q.x, q.y)
        e:Show()
    end
    for j = k + 1, #t.extra do t.extra[j]:Hide() end
    -- tags: moving group, rail, lock
    local tags = {}
    if pc.mv then
        local m = self.data.movers[pc.mv]
        tags[#tags + 1] = (m and m.k:sub(1, 1):upper() or "M") .. pc.mv
    end
    if pc.rail then tags[#tags + 1] = "R" .. (pc.rail:match("%d+") or "") end
    if (pc.t == "key" or pc.t == "cage") and pc.id then tags[#tags + 1] = "L" .. (pc.id:match("%d+") or "") end
    if #tags > 0 then
        t.tag:SetText(table.concat(tags, " "))
        place(t.tag, f, pc.x, pc.y - rad - 8)
        t.tag:Show()
    else
        t.tag:Hide()
    end
end

function ED:HidePiece(t)
    t.body:Hide(); t.sel:Hide(); t.rim:Hide(); t.tag:Hide()
    for _, e in ipairs(t.extra) do e:Hide() end
end

function ED:Redraw()
    if not self.field then return end
    local pieces = self.data.pieces
    for i, pc in ipairs(pieces) do self:DrawPiece(i, pc) end
    for i = #pieces + 1, #self.pieceTex do self:HidePiece(self.pieceTex[i]) end
end

function ED:Refresh()
    if not self.frame then return end
    local d = self.data
    if self.nameBox and not (self.nameBox.HasFocus and self.nameBox:HasFocus()) then self.nameBox:SetText(d.name or "") end
    local goals = d.goals or {}
    self.objBtn.text:SetText(goals.oranges and "Oranges: on" or "Oranges: off")
    self.longBtn.text:SetText(goals.longshots and ("Long Shots: " .. goals.longshots) or "Long Shots: off")
    self.bucketBtn.text:SetText(d.noBucket and "Bucket: no" or "Bucket: yes")
    self.orangeText:SetText("Oranges dealt: " .. (d.oranges and tostring(d.oranges) or ("auto " .. self:AutoOranges())))
    local approved = self:DB().approved[d.level or 1]
    self.levelText:SetText(("Level number: %d%s"):format(d.level or 1, approved and "  |cff88ff88(approved)|r" or ""))
    ART:Set(self.fieldBg, ART:FieldBackdrop(d.level or 1))
    local n = self:SelCount()
    local list = self:Selected()
    local kinds = {}
    for _, i in ipairs(list) do local t = d.pieces[i].t; kinds[t] = (kinds[t] or 0) + 1 end
    local parts = {}
    for t, c in pairs(kinds) do parts[#parts + 1] = c .. " " .. L.EDIT_TYPES[t].name:lower() end
    table.sort(parts)
    local angle
    for _, i in ipairs(list) do
        local pc = d.pieces[i]
        if isBar(pc) then
            local deg = floor(((pc.a or 0) * 180 / pi) % 360 * 10 + 0.5) / 10
            if angle and angle ~= deg then angle = "mixed" break end
            angle = deg
        end
    end
    local angleText = angle and ((angle == "mixed") and "  (angles differ)" or ("  (angle " .. angle .. ")")) or ""
    self.selText:SetText(n == 0 and "Nothing selected" or (n .. " selected: " .. table.concat(parts, ", ") .. angleText))
    local sc = self:SelColor()
    self.colorBtn.text:SetText(sc == nil and "Color: -" or (sc == "mixed" and "Color: mixed") or
        (sc and ("Color: " .. self.COLOR_NAMES[sc]) or "Color: dealt"))
    for letter, b in pairs(self.excludeBtns or {}) do
        local on = self:SelExcludes(letter)
        b.text:SetText((on and "|cff88ff88" or "") .. b.label .. (on and "|r" or ""))
    end
    local mv = self:SelMover()
    if mv then
        local m = d.movers[mv]
        local range = (m.k == "swing") and ("%d degrees"):format(floor(m.amp * 180 / pi + 0.5)) or
            ((m.k == "wheel") and "a full turn" or (floor(m.amp + 0.5) .. " px"))
        self.moverText:SetText(("Group %d: %s, %s, speed %.1f%s"):format(mv, m.k, range, abs(m.speed), m.speed < 0 and " (reversed)" or ""))
        self.moverBtn.text:SetText("Next kind of movement")
    else
        self.moverText:SetText(n > 0 and "Not moving" or "")
        self.moverBtn.text:SetText("Make them move")
    end
    local counts = {}
    for _, pc in ipairs(d.pieces) do counts[pc.t] = (counts[pc.t] or 0) + 1 end
    local lines = { #d.pieces .. " pieces" }
    for _, t in ipairs(self.TOOLS) do
        if counts[t] then lines[#lines + 1] = counts[t] .. "  " .. L.EDIT_TYPES[t].name end
    end
    self.countText:SetText(table.concat(lines, "\n"))
    local probs = self:Problems()
    self.problemText:SetText(#probs > 0 and ("Check: " .. table.concat(probs, "; ") .. ".") or "")
    local owner = self:IsOwner()
    self.importBtn:SetShown(owner)
    self.approveBtn:SetShown(owner)
    self.unapproveBtn:SetShown(owner and approved and true or false)
    self:RefreshTools()
    self:Redraw()
end

-- ---------------------------------------------------------------------
-- Mouse and keys

function ED:Cursor()
    local f = self.field
    if not (f and GetCursorPosition) then return nil end
    local scale = f:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    local left, top = f:GetLeft(), f:GetTop()
    if not (cx and left and top) then return nil end
    return cx / scale - left, top - cy / scale
end

local function shift() return IsShiftKeyDown and IsShiftKeyDown() end
local function ctrl() return IsControlKeyDown and IsControlKeyDown() end

function ED:OnMouseDown(btn)
    local x, y = self:Cursor()
    if not x then return end
    if btn == "RightButton" and self.arc then
        self:CancelArc()
        return
    end
    if btn == "RightButton" then
        if self:SelCount() == 0 then
            local hit = self:PieceAt(x, y)
            if hit then self.sel = { [hit] = true } end
        end
        if self:SelCount() == 0 then return end
        self:PushUndo()
        local cx, cy = self:Centre(self:Selected())
        self.drag = { mode = "rotate", cx = cx, cy = cy, a0 = atan2(y - cy, x - cx), done = 0 }
        self:Refresh()
        return
    end
    if btn ~= "LeftButton" then return end
    local tool = self.tool
    if tool == "slide" then
        self.drag = { mode = "slide", pts = { { x, y } } }
        return
    end
    if tool == "arc" then
        local px, py = self:Snap(x), self:Snap(y)
        local a = self.arc
        if not a then
            self.arc = { x0 = px, y0 = py }
        elseif not a.x1 then
            if (px - a.x0) ^ 2 + (py - a.y0) ^ 2 < 400 then return end
            a.x1, a.y1 = px, py
        else
            local pts = self:ArcPoints(a.x0, a.y0, a.x1, a.y1, px, py)
            self:CancelArc()
            local made = self:AddSlide(pts)
            self:Status(made and ("A slide arc of %d bricks."):format(made) or "Too short for a slide arc.")
            self:Refresh()
        end
        return
    end
    if tool == "circle" then
        self.drag = { mode = "circle", cx = self:Snap(x), cy = self:Snap(y) }
        return
    end
    if tool ~= "select" then
        local def = L.EDIT_TYPES[tool]
        if def and (tool == "brick" or tool == "block" or tool == "cage") then
            self.drag = { mode = "bar", x0 = self:Snap(x), y0 = self:Snap(y) }
        else
            self:PushUndo()
            local i = self:AddPiece(tool, x, y)
            if i then self.sel = { [i] = true } end
            self:Refresh()
        end
        return
    end
    local hit = self:PieceAt(x, y)
    if hit then
        if shift() then
            self.sel[hit] = (not self.sel[hit]) or nil
            self:Refresh()
            return
        end
        if not self.sel[hit] then self.sel = { [hit] = true } end
        self:PushUndo()
        local orig = {}
        for _, i in ipairs(self:Selected()) do orig[i] = { self.data.pieces[i].x, self.data.pieces[i].y } end
        self.drag = { mode = "move", x0 = x, y0 = y, orig = orig, moved = false }
        self:Refresh()
    else
        if not shift() then self.sel = {} end
        self.drag = { mode = "box", x0 = x, y0 = y, keep = copy(self.sel) }
        self:Refresh()
    end
end

function ED:OnUpdate()
    local a = self.arc
    if a and not self.drag then
        local x, y = self:Cursor()
        if x then
            local px, py = self:Snap(x), self:Snap(y)
            if a.x1 then self:DrawSlidePath(self:ArcPoints(a.x0, a.y0, a.x1, a.y1, px, py))
            else self:DrawSlidePath({ { a.x0, a.y0 }, { px, py } }) end
        end
    end
    local dr = self.drag
    if not dr then return end
    local x, y = self:Cursor()
    if not x then return end
    if dr.mode == "move" then
        local dx, dy = x - dr.x0, y - dr.y0
        if not dr.moved and dx * dx + dy * dy < 9 then return end
        dr.moved = true
        if (self.snap or 0) > 0 then dx, dy = self:Snap(dx), self:Snap(dy) end
        for i, o in pairs(dr.orig) do
            local pc = self.data.pieces[i]
            if pc then pc.x, pc.y = o[1] + dx, o[2] + dy; clampToZone(pc) end
        end
        self:Redraw()
    elseif dr.mode == "rotate" then
        local a = atan2(y - dr.cy, x - dr.cx)
        local da = a - dr.a0
        if da > pi then da = da - 2 * pi elseif da < -pi then da = da + 2 * pi end
        if shift() then
            -- in steps of 15 degrees
            local step = pi / 12
            local want = floor((dr.done + da) / step + 0.5) * step
            da = want - dr.done
        end
        if abs(da) > 0.0001 then
            self:RotateSelected(da, dr.cx, dr.cy)
            dr.done = dr.done + da
            dr.a0 = dr.a0 + da
            self:Redraw()
        end
    elseif dr.mode == "box" then
        local x0, y0 = math.min(dr.x0, x), math.min(dr.y0, y)
        local bw, bh = abs(x - dr.x0), abs(y - dr.y0)
        self.boxTex:ClearAllPoints()
        self.boxTex:SetPoint("TOPLEFT", self.field, "TOPLEFT", x0, -y0)
        self.boxTex:SetSize(math.max(1, bw), math.max(1, bh))
        self.boxTex:Show()
    elseif dr.mode == "circle" then
        local r = sqrt((x - dr.cx) ^ 2 + (y - dr.cy) ^ 2)
        dr.r = self:Snap(r)
        self:DrawSlidePath(self:CirclePoints(dr.cx, dr.cy, dr.r))
    elseif dr.mode == "slide" then
        local last = dr.pts[#dr.pts]
        if (x - last[1]) ^ 2 + (y - last[2]) ^ 2 >= 16 and #dr.pts < 400 then
            dr.pts[#dr.pts + 1] = { x, y }
            self:DrawSlidePath(dr.pts)
        end
    elseif dr.mode == "bar" then
        local x1, y1 = self:Snap(x), self:Snap(y)
        local len = sqrt((x1 - dr.x0) ^ 2 + (y1 - dr.y0) ^ 2)
        if len > 6 then
            local h = (self.tool == "brick") and E.BRICK_H or 14
            self.ghostTex:SetSize(len, h)
            if self.ghostTex.SetRotation then self.ghostTex:SetRotation(-atan2(y1 - dr.y0, x1 - dr.x0)) end
            place(self.ghostTex, self.field, (x1 + dr.x0) / 2, (y1 + dr.y0) / 2)
            self.ghostTex:Show()
        else
            self.ghostTex:Hide()
        end
    end
end

function ED:OnMouseUp(btn)
    local dr = self.drag
    self.drag = nil
    if not dr then return end
    local x, y = self:Cursor()
    if dr.mode == "move" then
        if not dr.moved then table.remove(self.undo) end      -- a click, not a move
        self:Refresh()
    elseif dr.mode == "rotate" then
        if abs(dr.done) < 0.0001 then table.remove(self.undo) end
        self:Refresh()
    elseif dr.mode == "box" then
        self.boxTex:Hide()
        if x then
            local x0, x1 = math.min(dr.x0, x), math.max(dr.x0, x)
            local y0, y1 = math.min(dr.y0, y), math.max(dr.y0, y)
            self.sel = dr.keep or {}
            if x1 - x0 > 3 or y1 - y0 > 3 then
                for i, pc in ipairs(self.data.pieces) do
                    if pc.x >= x0 and pc.x <= x1 and pc.y >= y0 and pc.y <= y1 then self.sel[i] = true end
                end
            end
        end
        self:Refresh()
    elseif dr.mode == "circle" then
        self:DrawSlidePath(nil)
        local made = (dr.r or 0) >= self.CIRCLE_MIN_R and self:AddSlide(self:CirclePoints(dr.cx, dr.cy, dr.r))
        self:Status(made and ("A slide circle of %d bricks, open at the top."):format(made)
            or ("Drag out a bigger circle (at least %d pixels across)."):format(self.CIRCLE_MIN_R * 2))
        self:Refresh()
    elseif dr.mode == "slide" then
        self:DrawSlidePath(nil)
        local made = self:AddSlide(dr.pts)
        if made then
            self:Status(("A Super Slide of %d bricks. A ball meeting it from the inside of its curve rides it."):format(made))
        else
            self:Status("Drag a longer path for a Super Slide (at least three bricks).")
        end
        self:Refresh()
    elseif dr.mode == "bar" then
        self.ghostTex:Hide()
        if not x then return end
        self:PushUndo()
        local x1, y1 = self:Snap(x), self:Snap(y)
        local len = sqrt((x1 - dr.x0) ^ 2 + (y1 - dr.y0) ^ 2)
        local i
        if len > 10 and self.tool == "brick" then
            -- a row of full bricks, the last cut to fit
            table.remove(self.undo)
            self:AddSlide({ { dr.x0, dr.y0 }, { x1, y1 } }, true)
            self:Refresh()
            return
        elseif len > 10 then
            i = self:AddPiece(self.tool, (x1 + dr.x0) / 2, (y1 + dr.y0) / 2,
                { w = math.min(300, len), a = atan2(y1 - dr.y0, x1 - dr.x0) })
        else
            i = self:AddPiece(self.tool, dr.x0, dr.y0)
        end
        if i then self.sel = { [i] = true } end
        self:Refresh()
    end
end

function ED:OnWheel(delta)
    if self:SelCount() == 0 then return end
    self:PushUndo()
    local step = (shift() and 1 or 5) * pi / 180
    self:RotateSelected(-delta * step)
    self:Refresh()
end

function ED:OnKey(key)
    local handled = true
    local n = self:SelCount()
    if key == "DELETE" or key == "BACKSPACE" then
        self:DeleteSelected()
    elseif key == "ESCAPE" and self.arc then
        self:CancelArc()
    elseif key == "ESCAPE" then
        if n > 0 or self.drag then self.sel = {}; self.drag = nil; self:Refresh() else handled = false end
    elseif key == "LEFT" or key == "RIGHT" or key == "UP" or key == "DOWN" then
        if n == 0 then handled = false else
            local s = shift() and 10 or 1
            self:PushUndo()
            self:MoveSelected((key == "LEFT" and -s) or (key == "RIGHT" and s) or 0, (key == "UP" and -s) or (key == "DOWN" and s) or 0)
            self:Refresh()
        end
    elseif key == "Q" or key == "E" then
        if n == 0 then handled = false else
            self:PushUndo()
            local step = (shift() and 15 or 5) * pi / 180
            self:RotateSelected(key == "Q" and -step or step)
            self:Refresh()
        end
    elseif key == "M" then
        self:MirrorSelected(false)
    elseif ctrl() and key == "Z" then
        self:Undo()
    elseif ctrl() and key == "D" then
        self:DuplicateSelected()
    elseif ctrl() and key == "C" then
        self:CopySelected()
    elseif ctrl() and key == "V" then
        local x, y = self:Cursor()
        self:Paste(x, y)
    elseif ctrl() and key == "A" then
        self:SelectAll()
    else
        handled = false
    end
    if self.frame.SetPropagateKeyboardInput then pcall(self.frame.SetPropagateKeyboardInput, self.frame, not handled) end
end

-- ---------------------------------------------------------------------

function ED:Show()
    self:Create()
    self.frame:Show()
    self:Refresh()
end

function ED:Hide()
    if self.frame then self.frame:Hide() end
end

function ED:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end
