--[[
    Gnomish Pachinko - Mascot.lua
    Tinkmaster Overspark in person: the gnome engineer of Tinker Town as
    his own 3D model from the game,
    shown in a PlayerModel frame in the field's top corner (the launcher
    can never reach the high corners, so nothing is hidden there). The
    game's own animations do the acting: he points when you fire, cheers
    a free ball, dances through Fever, cries when the balls run out.

    Which gnome: db.mascot.npc (a creature id shown with SetCreature; the
    default is Tinkmaster Overspark, the gnome engineer of Tinker Town),
    or db.mascot.display (a display id, SetDisplayInfo). Target any NPC
    and /pachinko mascot target makes him the mascot; the id comes from
    the target's GUID, so the client can show him again next session once
    it has seen him. If none of that works the model falls back to you.
]]

local GP = GnomishPachinko
GP.Mascot = GP.Mascot or {}
local M = GP.Mascot

M.DEFAULT_NPC = 7406            -- Tinkmaster Overspark
M.SIZE = { w = 90, h = 112 }

-- The game's animation ids used here.
M.ANIM = {
    stand = 0, talk = 60, work = 62, talkExclaim = 64, talkQuestion = 65, bow = 66, wave = 67,
    cheer = 68, dance = 69, laugh = 70, roar = 74, kneel = 75, cry = 77, beg = 79,
    applaud = 80, shout = 81, flex = 82, shy = 83, point = 84,
}

-- What he does when. `hold` animations loop until something else happens.
M.REACTIONS = {
    start        = { anim = "wave" },
    launch       = { anim = "point" },
    bucket       = { anim = "cheer" },
    freeball     = { anim = "cheer" },
    power        = { anim = "flex" },
    combo        = { anim = "laugh" },
    style        = { anim = "applaud" },
    total_miss   = { anim = "shy" },
    last_peg     = { anim = "kneel" },
    fever        = { anim = "dance", hold = true },
    gnome_bonus  = { anim = "roar" },
    cleared      = { anim = "cheer", thenHold = "dance" },
    failed       = { anim = "cry", hold = true },
    two_left     = { anim = "talkQuestion" },
    last_ball    = { anim = "beg" },
    boss_hit     = { anim = "flex" },
    boss_down    = { anim = "roar" },
    boss_turn    = { anim = "talkExclaim" },
    hatched      = { anim = "laugh" },
    gem          = { anim = "applaud" },
    unlock       = { anim = "applaud" },
    idle         = { anim = "stand" },
}

local function settings()
    local db = GP:GetDB()
    db.mascot = db.mascot or {}
    return db.mascot
end

-- The looks to try, in order: the saved display id, the saved creature,
-- Tinkmaster himself, and only then the player. A creature's model loads
-- a moment after SetCreature on this client, so each step is judged
-- after a short wait (GetModelFileID still nil = the client does not
-- have that model), not on the spot.
function M:Candidates()
    local s = settings()
    local list = {}
    -- a look the player chose with /pachinko mascot wins; otherwise the chapter's host
    if s.custom and s.display then list[#list + 1] = { label = "display " .. s.display, fn = function(m) m:SetDisplayInfo(s.display) end } end
    if s.custom and s.npc then list[#list + 1] = { label = "npc " .. s.npc, fn = function(m) m:SetCreature(s.npc) end } end
    local host = self.hostNpc or M.DEFAULT_NPC
    list[#list + 1] = { label = "host " .. host, fn = function(m) m:SetCreature(host) end }
    if host ~= M.DEFAULT_NPC then list[#list + 1] = { label = "npc " .. M.DEFAULT_NPC, fn = function(m) m:SetCreature(M.DEFAULT_NPC) end } end
    list[#list + 1] = { label = "player", fn = function(m) m:SetUnit("player") end }
    return list
end

-- The host's own framing (some models stand taller than others) unless the
-- player has tuned it with /pachinko mascot z / scale.
-- The client re-centres a model when it loads and when the camera is set,
-- so the height is applied by moving the model's frame (z is a share of
-- the frame's height, negative = lower), which nothing undoes; the scale
-- and facing are applied after the camera, and again once the model loads.
function M:Pose()
    local model, s = self.model, settings()
    if not model then return end
    local h = (not s.custom) and self.hostPose or {}
    -- TEMPORARY: the tuning panel's per-host values, read back and
    -- hardcoded into GP.HOSTS once the user has set them
    local tune = (not s.custom) and s.tune and h.id and s.tune[h.id] or {}
    local z = tune.z or s.z or h.z or 0
    local scale = tune.scale or s.scale or h.scale or 1
    -- the zoom is the frame's size too: the client refits the model to its
    -- frame on load and on every camera change, undoing SetModelScale
    if self.anchor and self.baseW then
        model:SetSize(self.baseW * scale, self.baseH * scale)
        model:ClearAllPoints()
        model:SetPoint("CENTER", self.anchor, "CENTER", 0, z * self.baseH)
    end
    pcall(function()
        if model.SetCamera then model:SetCamera(0) end
        model:SetPosition(0, 0, 0)
        model:SetFacing(s.facing or 0.35)
        if model.SetModelScale then model:SetModelScale(1) end
    end)
end

function M:HasModel()
    local model = self.model
    if not model or not model.GetModelFileID then return true end     -- cannot tell: assume yes
    local ok, id = pcall(model.GetModelFileID, model)
    return (not ok) or id ~= nil
end

function M:Load()
    local model = self.model
    if not model then return end
    self.loadToken = (self.loadToken or 0) + 1
    local token = self.loadToken
    local list = self:Candidates()
    self.tried = {}
    local function attempt(i)
        if token ~= self.loadToken then return end
        local c = list[i]
        if not c then self.loaded = false return end
        local ok = pcall(c.fn, model)
        self.tried[#self.tried + 1] = c.label .. (ok and "" or " (refused)")
        if not ok then return attempt(i + 1) end
        self:Pose()
        self:Play("stand")
        self.loaded = c.label
        if i >= #list then return end
        -- give the model time to arrive before judging it
        local check = function()
            if token ~= self.loadToken then return end
            if not self:HasModel() then
                self.tried[#self.tried] = c.label .. " (no model)"
                attempt(i + 1)
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(1.5, check) else check() end
    end
    attempt(1)
    return true
end

-- parent: the frame the model lives in. With a size given it fills the
-- parent's centre (the portrait box); otherwise it sits in the corner.
-- A model is clipped only by rectangles, so a round window is built from
-- strips: `strips` (optional) is a list of clip frames shaped to the circle,
-- each holding a copy of the model, all driven together through one proxy
-- (any call on M.model goes to every copy; the first copy's answer comes back).
local function proxyOf(copies)
    return setmetatable({ copies = copies }, { __index = function(t, k)
        local first = copies[1][k]
        if type(first) ~= "function" then return first end
        local f = function(_, ...)
            local a, b, c, d
            for i, m in ipairs(copies) do
                local fn = m[k]
                if fn then
                    if i == 1 then a, b, c, d = fn(m, ...) else fn(m, ...) end
                end
            end
            return a, b, c, d
        end
        rawset(t, k, f)
        return f
    end })
end

function M:Create(parent, anchor, w, h, strips)
    if self.model or not parent then return end
    if strips and #strips > 0 then
        local copies = {}
        for i, clip in ipairs(strips) do
            local m = CreateFrame("PlayerModel", i == 1 and "GnomishPachinkoMascot" or nil, clip)
            copies[i] = m
        end
        local model = proxyOf(copies)
        model:SetSize(w, h)
        self.baseW, self.baseH = w, h
        self.anchor = anchor or parent
        model:SetPoint("CENTER", self.anchor, "CENTER", 0, 0)
        for _, m in ipairs(copies) do
            if m.SetFrameLevel and m:GetParent() and m:GetParent().GetFrameLevel then m:SetFrameLevel(m:GetParent():GetFrameLevel() + 3) end
        end
        model:EnableMouse(false)
        -- each copy re-poses as it loads; the animation restarts on all at
        -- once so the strips stay in step
        model:SetScript("OnModelLoaded", function()
            M:Pose()
            if M.current then M:Play(M.current) end
        end)
        self.model = model
        self.copies = copies
        self:Load()
        if settings().hide then model:Hide() end
        return model
    end
    local model = CreateFrame("PlayerModel", "GnomishPachinkoMascot", parent)
    model:SetSize(w or self.SIZE.w, h or self.SIZE.h)
    self.baseW, self.baseH = w, h
    if w then
        self.anchor = anchor or parent
        model:SetPoint("CENTER", self.anchor, "CENTER", 0, 0)
    else model:SetPoint("TOPRIGHT", anchor or parent, "TOPRIGHT", -4, -4) end
    if model.SetFrameLevel and parent.GetFrameLevel then model:SetFrameLevel(parent:GetFrameLevel() + 3) end
    model:EnableMouse(false)
    -- the client re-centres a model as it finishes loading: pose it again then
    model:SetScript("OnModelLoaded", function() M:Pose() end)
    self.model = model
    self:Load()
    if settings().hide then model:Hide() end
    return model
end

-- The chapter's host takes the box (unless the player picked a look).
function M:SetHost(npc, pose)
    if self.hostNpc == npc then return end
    self.hostNpc = npc
    self.hostPose = pose
    if self.model and not settings().custom then self:Load() end
end

function M:Play(name)
    local model = self.model
    if not model then return end
    local id = self.ANIM[name] or self.ANIM.stand
    local ok = pcall(model.SetAnimation, model, id)
    if ok then self.current = name end
    return ok
end

-- A reaction by name (the keys of REACTIONS). One-shot emotes return to
-- the held animation (dance through Fever, cry after a loss) or to idle.
function M:React(name)
    local r = self.REACTIONS[name]
    if not r or not self.model or not self.model:IsShown() then return end
    self.lastReaction = name
    if r.hold then
        self.held = r.anim
        self:Play(r.anim)
        return
    end
    if r.thenHold then self.held = r.thenHold end
    if name == "start" or name == "idle" then self.held = nil end
    self:Play(r.anim)
    self.returnAt = GetTime() + 2.2
end

-- Called from the window's OnUpdate: after a one-shot emote, back to the
-- held animation or to standing.
function M:Tick(now)
    if self.returnAt and now >= self.returnAt then
        self.returnAt = nil
        self:Play(self.held or "stand")
    end
end

function M:Toggle()
    local s = settings()
    s.hide = not s.hide
    if self.model then
        if s.hide then self.model:Hide() else self.model:Show() end
    end
    GP:Print("Mascot " .. (s.hide and "hidden" or "shown") .. ".")
end

-- /pachinko mascot <...>
function M:Command(args)
    args = (args or ""):match("^%s*(.-)%s*$")
    local s = settings()
    if args == "" then
        self:Toggle()
    elseif args == "target" then
        local guid
        pcall(function() guid = UnitGUID("target") end)
        local okG, text = pcall(function() return "" .. tostring(guid) end)
        local npc = okG and text:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
        if not npc then
            GP:Print("Target a creature first; its id becomes the mascot.")
            return
        end
        s.npc, s.display, s.custom = tonumber(npc), nil, true
        self:Load()
        GP:Print(("Mascot set to creature %s."):format(npc))
    elseif args:match("^id%s+%d+") then
        s.display, s.npc, s.custom = tonumber(args:match("%d+")), nil, true
        self:Load()
        GP:Print(("Mascot set to display id %d."):format(s.display))
    elseif args:match("^npc%s+%d+") then
        s.npc, s.display, s.custom = tonumber(args:match("%d+")), nil, true
        self:Load()
        GP:Print(("Mascot set to creature %d."):format(s.npc))
    elseif args:match("^scale%s+[%d%.]+") then
        s.scale = tonumber(args:match("[%d%.]+"))
        self:Pose()
        GP:Print("Mascot scale " .. s.scale .. ".")
    elseif args:match("^face%s+[%-%d%.]+") then
        s.facing = tonumber(args:match("[%-%d%.]+"))
        self:Pose()
        GP:Print("Mascot facing " .. s.facing .. ".")
    elseif args:match("^z%s+[%-%d%.]+") then
        s.z = tonumber(args:match("[%-%d%.]+"))
        self:Pose()
        GP:Print("Mascot height " .. s.z .. ".")
    elseif args == "status" then
        GP:Print("Mascot tried: " .. table.concat(self.tried or {}, ", ") .. ". Showing: " .. tostring(self.loaded) .. ".")
    elseif args == "reset" then
        GP:GetDB().mascot = nil
        settings()
        self:Load()
        if self.model then self.model:Show() end
        GP:Print("Mascot back to the chapter's host.")
    elseif args:match("^play%s+%a+") then
        local name = args:match("^play%s+(%a+)")
        if self.ANIM[name] then self:Play(name) else GP:Print("Unknown animation. Try: " .. table.concat((function() local t = {} for k in pairs(self.ANIM) do t[#t + 1] = k end table.sort(t) return t end)(), ", ")) end
    else
        GP:Print("/pachinko mascot - show or hide. mascot target - use the targeted creature. mascot npc <id> / id <display id>. mascot scale <n>, face <radians>, z <n>, play <animation>, status, reset.")
    end
end
