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
M.SIZE = { w = 110, h = 140 }

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
    if db.mascot.npc == nil and db.mascot.display == nil then db.mascot.npc = M.DEFAULT_NPC end
    return db.mascot
end

-- Try the saved look first, then the fallbacks. Each call is guarded:
-- the client may lack a method, or the id may be unknown to it.
function M:Load()
    local model = self.model
    if not model then return end
    local s = settings()
    local tried = {}
    local function try(label, fn)
        local ok = pcall(fn)
        tried[#tried + 1] = label .. (ok and "" or " (refused)")
        if not ok then return false end
        -- an unknown model leaves no file behind
        if model.GetModelFileID then
            local okF, id = pcall(model.GetModelFileID, model)
            if okF and not id then return false end
        end
        return true
    end
    local shown = false
    if s.display then shown = try("display " .. s.display, function() model:SetDisplayInfo(s.display) end) end
    if not shown and s.npc then shown = try("npc " .. s.npc, function() model:SetCreature(s.npc) end) end
    if not shown and s.npc ~= M.DEFAULT_NPC then
        shown = try("npc " .. M.DEFAULT_NPC, function() model:SetCreature(M.DEFAULT_NPC) end)
    end
    if not shown then shown = try("player", function() model:SetUnit("player") end) end
    self.loaded = shown
    pcall(function()
        model:SetPosition(0, 0, s.z or -0.1)
        model:SetFacing(s.facing or 0.35)
        if model.SetModelScale then model:SetModelScale(s.scale or 1) end
        if model.SetCamera then model:SetCamera(0) end
    end)
    self.tried = tried
    self:Play("stand")
    return shown
end

function M:Create(parent, anchor)
    if self.model or not parent then return end
    local model = CreateFrame("PlayerModel", "GnomishPachinkoMascot", parent)
    model:SetSize(self.SIZE.w, self.SIZE.h)
    model:SetPoint("TOPRIGHT", anchor or parent, "TOPRIGHT", -4, -4)
    if model.SetFrameLevel and parent.GetFrameLevel then model:SetFrameLevel(parent:GetFrameLevel() + 3) end
    model:EnableMouse(false)
    self.model = model
    self:Load()
    if settings().hide then model:Hide() end
    return model
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
        s.npc, s.display = tonumber(npc), nil
        self:Load()
        GP:Print(("Mascot set to creature %s%s."):format(npc, self.loaded and "" or " (the client could not show it; the fallback is up)"))
    elseif args:match("^id%s+%d+") then
        s.display, s.npc = tonumber(args:match("%d+")), nil
        self:Load()
        GP:Print(("Mascot set to display id %d%s."):format(s.display, self.loaded and "" or " (not shown; fallback up)"))
    elseif args:match("^npc%s+%d+") then
        s.npc, s.display = tonumber(args:match("%d+")), nil
        self:Load()
        GP:Print(("Mascot set to creature %d%s."):format(s.npc, self.loaded and "" or " (not shown; fallback up)"))
    elseif args:match("^scale%s+[%d%.]+") then
        s.scale = tonumber(args:match("[%d%.]+"))
        self:Load()
        GP:Print("Mascot scale " .. s.scale .. ".")
    elseif args:match("^face%s+[%-%d%.]+") then
        s.facing = tonumber(args:match("[%-%d%.]+"))
        self:Load()
        GP:Print("Mascot facing " .. s.facing .. ".")
    elseif args:match("^z%s+[%-%d%.]+") then
        s.z = tonumber(args:match("[%-%d%.]+"))
        self:Load()
        GP:Print("Mascot height " .. s.z .. ".")
    elseif args == "reset" then
        GP:GetDB().mascot = nil
        settings()
        self:Load()
        if self.model then self.model:Show() end
        GP:Print("Mascot back to Tinkmaster Overspark.")
    elseif args:match("^play%s+%a+") then
        local name = args:match("^play%s+(%a+)")
        if self.ANIM[name] then self:Play(name) else GP:Print("Unknown animation. Try: " .. table.concat((function() local t = {} for k in pairs(self.ANIM) do t[#t + 1] = k end table.sort(t) return t end)(), ", ")) end
    else
        GP:Print("/pachinko mascot - show or hide. mascot target - use the targeted creature. mascot npc <id> / id <display id>. mascot scale <n>, face <radians>, z <n>, play <animation>, reset.")
    end
end
