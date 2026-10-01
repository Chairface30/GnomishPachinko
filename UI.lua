--[[
    Gnomish Pachinko - UI.lua
    The game window: the field (pegs, bricks, ball, bucket, Fever bins,
    aim guide), the side panel, the level select. Reads the mouse for
    aiming, launches on click, pumps the engine from OnUpdate.
]]

local GP = GnomishPachinko
local E = GP.Engine
local L = GP.Levels
GP.UI = GP.UI or {}
local UI = GP.UI

local TEX = "Interface\\AddOns\\GnomishPachinko\\Textures\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"

local PAD, SIDE_W, TOP_H = 16, 200, 44

local COLORS = {
    blue   = { base = { 0.30, 0.58, 1.00 }, lit = { 0.78, 0.92, 1.00 }, glow = { 0.55, 0.80, 1.00 } },
    orange = { base = { 1.00, 0.50, 0.08 }, lit = { 1.00, 0.90, 0.50 }, glow = { 1.00, 0.70, 0.25 } },
    green  = { base = { 0.22, 0.88, 0.32 }, lit = { 0.78, 1.00, 0.78 }, glow = { 0.50, 1.00, 0.55 } },
    purple = { base = { 0.75, 0.35, 1.00 }, lit = { 0.95, 0.80, 1.00 }, glow = { 0.85, 0.55, 1.00 } },
}
local BIN_COLORS = { [10000] = { 0.25, 0.45, 0.85 }, [50000] = { 0.95, 0.55, 0.15 }, [100000] = { 1.00, 0.85, 0.20 } }

local function fmtBig(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function powerName(id)
    for _, p in ipairs(E.POWERS) do if p.id == id then return p.name, p.blurb end end
    return id or "", ""
end

local function styleButton(btn, enabled, r, g, b)
    if enabled then
        btn:SetBackdropColor(r, g, b, 0.9)
        btn:SetBackdropBorderColor(1, 1, 1, 0.9)
        btn:Enable()
    else
        btn:SetBackdropColor(r * 0.35, g * 0.35, b * 0.35, 0.8)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        btn:Disable()
    end
end

local function makeButton(parent, w, h, text)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    return b
end

function UI:Initialize()
    if self.frame then return end
    self:CreateFrame()
end

function UI:CreateFrame()
    local FW, FH = E.FIELD_W, E.FIELD_H
    local FRAME_W = PAD + FW + PAD + SIDE_W + PAD
    local FRAME_H = TOP_H + FH + PAD

    local frame = CreateFrame("Frame", "GnomishPachinkoFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    frame:SetBackdropColor(0.08, 0.05, 0.16, 0.97)
    frame:SetBackdropBorderColor(0.75, 0.55, 0.95, 1)
    frame:Hide()
    self.frame = frame
    if UISpecialFrames then tinsert(UISpecialFrames, "GnomishPachinkoFrame") end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cffffd700Gnomish Pachinko|r")
    title:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() UI:Hide() end)

    -- ===== field =====
    local field = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    field:SetSize(FW, FH)
    field:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP_H)
    field:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    field:SetBackdropColor(0.03, 0.04, 0.14, 1)
    field:SetBackdropBorderColor(0.45, 0.35, 0.70, 1)
    field:EnableMouse(true)
    field:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then UI:OnFieldClick() end
    end)
    self.field = field

    for _ = 1, 48 do
        local s = field:CreateTexture(nil, "BACKGROUND", nil, 1)
        local size = 1 + math.random() * 2
        s:SetSize(size, size)
        s:SetTexture(WHITE)
        s:SetVertexColor(0.8, 0.85, 1, 0.15 + math.random() * 0.35)
        s:SetPoint("CENTER", field, "TOPLEFT", 6 + math.random() * (FW - 12), -(6 + math.random() * (FH - 12)))
    end

    local barrel = field:CreateTexture(nil, "ARTWORK", nil, 2)
    barrel:SetSize(12, 30)
    barrel:SetTexture(WHITE)
    barrel:SetVertexColor(0.70, 0.72, 0.80, 1)
    self.barrel = barrel
    local hub = field:CreateTexture(nil, "ARTWORK", nil, 3)
    hub:SetSize(26, 26)
    hub:SetTexture(TEX .. "peg")
    hub:SetVertexColor(0.55, 0.58, 0.68, 1)
    hub:SetPoint("CENTER", field, "TOPLEFT", FW / 2, -E.LAUNCHER_Y)

    self.guideDots = {}
    for i = 1, 64 do
        local d = field:CreateTexture(nil, "ARTWORK", nil, 1)
        d:SetSize(6, 6)
        d:SetTexture(TEX .. "dot")
        d:Hide()
        self.guideDots[i] = d
    end

    self.pegTex = {}

    self.ballTex = {}
    for i = 1, 8 do
        local b = field:CreateTexture(nil, "OVERLAY", nil, 2)
        b:SetSize(E.BALL_R * 2 + 2, E.BALL_R * 2 + 2)
        b:SetTexture(TEX .. "ball")
        b:Hide()
        self.ballTex[i] = b
    end

    local bucket = field:CreateTexture(nil, "OVERLAY", nil, 1)
    bucket:SetSize(E.BUCKET_W + 8, (E.BUCKET_W + 8) / 4)
    bucket:SetTexture(TEX .. "bucket")
    self.bucket = bucket

    self.bins = {}
    local binW = FW / #E.FEVER_BINS
    for i, pts in ipairs(E.FEVER_BINS) do
        local bin = CreateFrame("Frame", nil, field, "BackdropTemplate")
        bin:SetSize(binW - 2, 28)
        bin:SetPoint("BOTTOMLEFT", field, "BOTTOMLEFT", (i - 1) * binW + 1, 2)
        bin:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        local c = BIN_COLORS[pts] or BIN_COLORS[10000]
        bin:SetBackdropColor(c[1], c[2], c[3], 0.35)
        bin:SetBackdropBorderColor(c[1], c[2], c[3], 0.9)
        bin.label = bin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bin.label:SetPoint("CENTER")
        bin.label:SetText(fmtBig(pts))
        bin:Hide()
        self.bins[i] = bin
    end

    local banner = field:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    banner:SetPoint("CENTER", field, "CENTER", 0, 40)
    banner:SetFont("Fonts\\FRIZQT__.TTF", 26, "OUTLINE")
    self.banner = banner
    local sub = field:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sub:SetPoint("TOP", banner, "BOTTOM", 0, -6)
    self.bannerSub = sub

    self.popups = {}
    for i = 1, 10 do
        local p = field:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        p:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        p:Hide()
        self.popups[i] = p
    end

    -- ===== side panel =====
    local side = CreateFrame("Frame", nil, frame)
    side:SetSize(SIDE_W, FH)
    side:SetPoint("TOPLEFT", field, "TOPRIGHT", PAD, 0)
    self.side = side

    local function label(text, y, template)
        local fs = side:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", side, "TOPLEFT", 0, y)
        fs:SetText(text)
        return fs
    end
    local function value(y, template)
        local fs = side:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
        fs:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, y)
        fs:SetJustifyH("RIGHT")
        return fs
    end

    self.levelText = label("", 0, "GameFontNormalLarge")
    self.levelText:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    self.levelText:SetTextColor(1, 0.85, 0.2)
    self.chapterText = label("", -26, "GameFontNormal")
    self.chapterText:SetWidth(SIDE_W)
    self.chapterText:SetJustifyH("LEFT")
    self.layoutText = label("", -42)
    self.layoutText:SetTextColor(0.6, 0.55, 0.75)

    local div = side:CreateTexture(nil, "ARTWORK")
    div:SetSize(SIDE_W, 1)
    div:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -60)
    div:SetTexture(WHITE)
    div:SetVertexColor(0.5, 0.4, 0.7, 0.6)

    label("|cff88ff88Power|r", -68, "GameFontNormal")
    self.powerText = value(-68, "GameFontHighlight")
    self.powerBlurb = label("", -86)
    self.powerBlurb:SetWidth(SIDE_W)
    self.powerBlurb:SetJustifyH("LEFT")
    self.powerBlurb:SetTextColor(0.7, 0.7, 0.8)
    self.powerStatus = label("", -112)
    self.powerStatus:SetTextColor(0.6, 1, 0.6)

    label("Balls", -134, "GameFontNormal")
    self.ballsText = value(-134, "GameFontHighlightLarge")
    label("Orange pegs left", -158, "GameFontNormal")
    self.orangeText = value(-158, "GameFontHighlightLarge")
    label("Score", -182, "GameFontNormal")
    self.scoreText = value(-182, "GameFontHighlight")
    label("Multiplier", -200)
    self.multText = value(-200, "GameFontHighlightSmall")
    label("Best on this level", -216)
    self.bestText = value(-216, "GameFontHighlightSmall")
    label("Next free ball at", -232)
    self.freeBallText = value(-232, "GameFontHighlightSmall")

    local div2 = side:CreateTexture(nil, "ARTWORK")
    div2:SetSize(SIDE_W, 1)
    div2:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -254)
    div2:SetTexture(WHITE)
    div2:SetVertexColor(0.5, 0.4, 0.7, 0.6)

    self.nextBtn = makeButton(side, SIDE_W, 32, "NEXT LEVEL")
    self.nextBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -264)
    self.nextBtn:SetScript("OnClick", function() UI:NextLevel() end)
    self.retryBtn = makeButton(side, SIDE_W, 26, "Restart level")
    self.retryBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -302)
    self.retryBtn:SetScript("OnClick", function() UI:StartLevel(UI.state and UI.state.level or GP:GetDB().current) end)
    self.levelsBtn = makeButton(side, SIDE_W, 26, "Level select")
    self.levelsBtn:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -332)
    self.levelsBtn:SetScript("OnClick", function() UI:ShowLevelSelect() end)

    self.progressText = label("", -370)
    self.progressText:SetWidth(SIDE_W)
    self.progressText:SetJustifyH("LEFT")
    self.progressText:SetTextColor(0.8, 0.8, 0.9)

    local tip = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tip:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -400)
    tip:SetWidth(SIDE_W)
    tip:SetJustifyH("LEFT")
    tip:SetJustifyV("TOP")
    tip:SetTextColor(0.65, 0.65, 0.78)
    tip:SetText("Point with the mouse, click the field to shoot. Light every orange peg. " ..
        "Blue pegs and bricks are points, the purple one is worth 500, green pegs fire the level's power. " ..
        "The bucket gives the ball back. Points at 25k, 75k and 125k earn a free ball.")

    frame:SetScript("OnUpdate", function(_, dt) UI:OnUpdate(dt) end)
    frame:SetScript("OnShow", function() UI.lastHitSound = 0 end)

    self:CreateLevelSelect()
    self.events = {}
end

-- ---------------------------------------------------------------------
-- Level select overlay (covers the field)

function UI:CreateLevelSelect()
    local FW, FH = E.FIELD_W, E.FIELD_H
    local panel = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    panel:SetSize(FW, FH)
    panel:SetPoint("TOPLEFT", self.field, "TOPLEFT", 0, 0)
    panel:SetFrameLevel(self.field:GetFrameLevel() + 10)
    panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    panel:SetBackdropColor(0.05, 0.04, 0.12, 0.98)
    panel:SetBackdropBorderColor(0.75, 0.55, 0.95, 1)
    panel:EnableMouse(true)
    panel:Hide()
    self.levelPanel = panel

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOP", 0, -14)

    panel.prev = makeButton(panel, 60, 24, "< Prev")
    panel.prev:SetPoint("TOPLEFT", 14, -12)
    panel.prev:SetScript("OnClick", function() UI:LevelPage(UI.levelPage - 1) end)
    panel.next = makeButton(panel, 60, 24, "Next >")
    panel.next:SetPoint("TOPRIGHT", -14, -12)
    panel.next:SetScript("OnClick", function() UI:LevelPage(UI.levelPage + 1) end)

    panel.cells = {}
    local cols, rows = 10, 10
    local cw, ch = 46, 40
    local gx = (FW - cols * cw) / (cols + 1)
    local top = 56
    for i = 1, cols * rows do
        local c = makeButton(panel, cw, ch, "")
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        c:SetPoint("TOPLEFT", panel, "TOPLEFT", gx + col * (cw + gx), -(top + row * (ch + 6)))
        c.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        c.best = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        c.best:SetPoint("BOTTOM", 0, 3)
        c.best:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
        c:SetScript("OnClick", function(self)
            if self.level and GP:IsUnlocked(self.level) then
                UI:HideLevelSelect()
                UI:StartLevel(self.level)
            end
        end)
        panel.cells[i] = c
    end

    panel.back = makeButton(panel, 120, 26, "Back to the game")
    panel.back:SetPoint("BOTTOM", 0, 10)
    panel.back:SetScript("OnClick", function() UI:HideLevelSelect() end)
    panel.legend = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.legend:SetPoint("BOTTOMLEFT", 14, 14)
    panel.legend:SetText("|cff66ff66green|r cleared   |cffffd700gold|r open   |cff777777gray|r locked")
end

function UI:ShowLevelSelect()
    self:Initialize()
    local current = (self.state and self.state.level) or GP:GetDB().current or 1
    self.levelPage = math.floor((current - 1) / 100) + 1
    self:LevelPage(self.levelPage)
    self.levelPanel:Show()
end

function UI:HideLevelSelect()
    if self.levelPanel then self.levelPanel:Hide() end
end

function UI:LevelPage(page)
    local pages = math.ceil(L.COUNT / 100)
    if page < 1 then page = 1 elseif page > pages then page = pages end
    self.levelPage = page
    local panel = self.levelPanel
    local first = (page - 1) * 100
    panel.title:SetText(("|cffffd700Levels %d - %d|r"):format(first + 1, math.min(L.COUNT, first + 100)))
    styleButton(panel.prev, page > 1, 0.3, 0.3, 0.45)
    styleButton(panel.next, page < pages, 0.3, 0.3, 0.45)
    local db = GP:GetDB()
    for i, c in ipairs(panel.cells) do
        local n = first + i
        if n > L.COUNT then
            c:Hide()
        else
            c:Show()
            c.level = n
            c.text:SetText(tostring(n))
            local best = db.best[n]
            c.best:SetText(best and (best >= 1000 and (math.floor(best / 1000) .. "k") or tostring(best)) or "")
            if db.cleared[n] then
                c:SetBackdropColor(0.1, 0.4, 0.15, 0.9)
                c:SetBackdropBorderColor(0.4, 1, 0.5, 1)
                c.text:SetTextColor(0.7, 1, 0.7)
                c:Enable()
            elseif GP:IsUnlocked(n) then
                c:SetBackdropColor(0.45, 0.35, 0.1, 0.9)
                c:SetBackdropBorderColor(1, 0.85, 0.2, 1)
                c.text:SetTextColor(1, 0.9, 0.5)
                c:Enable()
            else
                c:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
                c:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
                c.text:SetTextColor(0.45, 0.45, 0.5)
                c:Disable()
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Level flow

function UI:StartLevel(n)
    self:Initialize()
    if not GP:IsUnlocked(n) then n = GP:GetDB().unlocked or 1 end
    local spec = L:Build(n)
    self.state = E:NewLevel(spec)
    GP:GetDB().current = n
    self.guideAim = nil
    self:LayoutPegs()
    for _, bin in ipairs(self.bins) do bin:Hide() end
    self.bucket:Show()
    self:HideGuide()
    self:ShowBanner(("|cffffd700Level %d|r"):format(n), spec.name .. "  -  " .. spec.layout, 2.5)
    self:UpdateDisplay()
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
    if not E:CanLaunch(st) then return end
    self:AimAtCursor()
    if E:Launch(st) then
        self:HideGuide()
        GP:PlaySfx("launch.ogg")
        self:UpdateDisplay()
    end
end

-- ---------------------------------------------------------------------
-- Field drawing

function UI:LayoutPegs()
    local st = self.state
    local field = self.field
    for i, p in ipairs(st.pegs) do
        local t = self.pegTex[i]
        if not t then
            t = {}
            t.ring = field:CreateTexture(nil, "ARTWORK", nil, 0)
            t.disc = field:CreateTexture(nil, "ARTWORK", nil, 1)
            self.pegTex[i] = t
        end
        if p.shape == "brick" then
            t.disc:SetTexture(TEX .. "brick")
            t.disc:SetSize(p.w, p.h)
            t.ring:SetTexture(TEX .. "brick")
            t.ring:SetSize(p.w + 12, p.h + 12)
            if t.disc.SetRotation then
                t.disc:SetRotation(-p.angle)
                t.ring:SetRotation(-p.angle)
            end
        else
            t.disc:SetTexture(TEX .. "peg")
            t.disc:SetSize(E.PEG_R * 2 + 2, E.PEG_R * 2 + 2)
            t.ring:SetTexture(TEX .. "ring")
            t.ring:SetSize(E.PEG_R * 2 + 18, E.PEG_R * 2 + 18)
            if t.disc.SetRotation then
                t.disc:SetRotation(0)
                t.ring:SetRotation(0)
            end
        end
        t.disc:ClearAllPoints()
        t.disc:SetPoint("CENTER", field, "TOPLEFT", p.x, -p.y)
        t.ring:ClearAllPoints()
        t.ring:SetPoint("CENTER", field, "TOPLEFT", p.x, -p.y)
        t.disc:SetAlpha(1)
        t.disc:Show()
        t.ring:Hide()
        t.shown = nil
        t.kind = nil
    end
    for i = #st.pegs + 1, #self.pegTex do
        self.pegTex[i].disc:Hide()
        self.pegTex[i].ring:Hide()
        self.pegTex[i].shown = "gone"
    end
end

function UI:HideGuide()
    for _, d in ipairs(self.guideDots) do d:Hide() end
    self.guideAim = nil
end

function UI:DrawGuide()
    local st = self.state
    local pts
    local super = st.superGuide > 0
    if super then pts = E:Simulate(st) else pts = E:Guide(st) end
    for i, d in ipairs(self.guideDots) do
        local p = pts[i]
        if p then
            d:ClearAllPoints()
            d:SetPoint("CENTER", self.field, "TOPLEFT", p.x, -p.y)
            if super then
                d:SetVertexColor(0.6, 1, 0.6, 1)
                d:SetAlpha(0.9 - 0.5 * (i / #pts))
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

function UI:AimAtCursor()
    local st = self.state
    if not st then return end
    local fx, fy = self:CursorField()
    if not fx then return end
    if fx < -120 or fx > E.FIELD_W + 120 or fy < -60 or fy > E.FIELD_H + 120 then return end
    E:Aim(st, fx, fy)
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
    p:ClearAllPoints()
    p:SetPoint("CENTER", self.field, "TOPLEFT", x, -y)
    p:SetText(text)
    p:SetTextColor(r or 1, g or 1, b or 1)
    p:SetAlpha(1)
    p.born = GetTime()
    p.x, p.y = x, y
    p:Show()
end

function UI:UpdatePopups(now)
    for _, p in ipairs(self.popups) do
        if p:IsShown() then
            local age = now - (p.born or now)
            if age > 0.9 then
                p:Hide()
            else
                p:ClearAllPoints()
                p:SetPoint("CENTER", self.field, "TOPLEFT", p.x, -(p.y - age * 36))
                p:SetAlpha(1 - age / 0.9)
            end
        end
    end
end

local POWER_BANNERS = {
    multiball = "|cff88ff88MULTIBALL!|r", guide = "|cff88ff88SUPER GUIDE!|r", blast = "|cff88ff88SPACE BLAST!|r",
    fireball = "|cffff8844FIREBALL!|r", spooky = "|cffaaffaaSPOOKY BALL!|r",
}

function UI:HandleEvents(now)
    local st = self.state
    for _, ev in ipairs(self.events) do
        local t = ev.type
        if t == "bounce" then
            if ev.speed > 60 and now - (self.lastHitSound or 0) > 0.06 then
                self.lastHitSound = now
                GP:PlaySfx("peg" .. math.random(3) .. ".ogg")
            end
        elseif t == "peg" then
            if ev.peg.kind == "orange" then
                if not ev.quiet then GP:PlaySfx("orange.ogg") end
                self:Popup(ev.x, ev.y - 14, "+" .. ev.points, 1, 0.8, 0.3)
            elseif ev.peg.kind == "purple" then
                self:Popup(ev.x, ev.y - 14, "+" .. ev.points, 0.9, 0.6, 1)
            elseif ev.peg.kind == "green" then
                self:Popup(ev.x, ev.y - 14, "+" .. ev.points, 0.6, 1, 0.6)
            end
        elseif t == "power" then
            self:ShowBanner(POWER_BANNERS[ev.power] or "POWER!", "", 1.4)
            GP:PlaySfx("power.ogg")
        elseif t == "fever" then
            self:ShowBanner("|cffffd700FEVER!|r", "Every orange peg is lit", 3)
            GP:PlaySfx("fever.ogg")
            self.bucket:Hide()
            for _, bin in ipairs(self.bins) do bin:Show() end
        elseif t == "bucket" then
            self:ShowBanner("|cff88ccffFREE BALL!|r", "", 1.5)
            GP:PlaySfx("free_ball.ogg")
            self:Popup(ev.x, E.BucketTop() - 16, "FREE BALL", 0.6, 0.85, 1)
        elseif t == "freeball_score" then
            self:ShowBanner("|cff88ccffFREE BALL!|r", fmtBig(ev.score) .. " points", 1.5)
            GP:PlaySfx("free_ball.ogg")
        elseif t == "spooky" then
            self:Popup(ev.x, 30, "BOO", 0.7, 1, 0.7)
        elseif t == "bin" then
            self:Popup(ev.x, E.FIELD_H - 44, "+" .. fmtBig(ev.points), 1, 0.9, 0.4)
        elseif t == "ready" then
            if st.ballsLeft > 0 then self:ShowBanner("", "", 0) end
        elseif t == "level_over" then
            self:OnLevelOver(ev.result)
        end
    end
    for i = #self.events, 1, -1 do self.events[i] = nil end
end

function UI:OnLevelOver(result)
    local db = GP:GetDB()
    local prevBest = db.best[result.level] or 0
    GP:RecordResult(result)
    if result.cleared then
        local extra = result.score > prevBest and prevBest > 0 and "  |cff88ff88New best!|r" or ""
        self:ShowBanner("|cffffd700LEVEL CLEARED!|r",
            ("Score %s with %d ball%s spare%s"):format(fmtBig(result.score), result.ballsLeft,
                result.ballsLeft == 1 and "" or "s", extra), 0)
        GP:PlaySfx("clear.ogg")
        if result.level == L.COUNT then
            self:ShowBanner("|cffffd700ALL 1000 LEVELS CLEARED!|r", "Score " .. fmtBig(result.score) .. ". You conquered Azeroth.", 0)
        end
    else
        self:ShowBanner("|cffff6060OUT OF BALLS|r",
            ("%d of %d orange pegs. Restart to try again."):format(result.oranges, self.state.orangeTotal), 0)
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
    if not st then return end
    if self.levelPanel and self.levelPanel:IsShown() then return end

    if st.phase == E.PHASE.AIM then
        self:AimAtCursor()
        if self.guideAim ~= st.aim or self.guideDirty then
            self.guideAim = st.aim
            self.guideDirty = nil
            self:DrawGuide()
        end
    end

    E:Step(st, dt, self.events)
    if #self.events > 0 then
        self.guideDirty = true
        self:HandleEvents(now)
        self:UpdateCounters()
    end
    self:Render(now)
end

function UI:Render(now)
    local st = self.state
    local field = self.field

    local a = st.aim or 0
    local half = 15
    self.barrel:ClearAllPoints()
    self.barrel:SetPoint("CENTER", field, "TOPLEFT",
        E.FIELD_W / 2 + math.sin(a) * half, -(E.LAUNCHER_Y + math.cos(a) * half))
    if self.barrel.SetRotation then self.barrel:SetRotation(a) end

    local pulse = 0.55 + 0.35 * math.sin(now * 9)
    for i, p in ipairs(st.pegs) do
        local t = self.pegTex[i]
        if t then
            if p.gone then
                local age = st.time - (p.goneAt or st.time)
                local alpha = 1 - age / 0.35
                if alpha <= 0 then
                    if t.shown ~= "gone" then
                        t.disc:Hide()
                        t.ring:Hide()
                        t.shown = "gone"
                    end
                else
                    t.disc:SetAlpha(alpha)
                    t.ring:SetAlpha(alpha * 0.8)
                    t.shown = "fading"
                end
            elseif p.lit then
                local c = COLORS[p.kind] or COLORS.blue
                if t.shown ~= "lit" then
                    t.disc:SetVertexColor(c.lit[1], c.lit[2], c.lit[3], 1)
                    t.ring:SetVertexColor(c.glow[1], c.glow[2], c.glow[3], 1)
                    t.ring:Show()
                    t.shown = "lit"
                end
                t.ring:SetAlpha(pulse)
            else
                -- unlit: the purple peg hops around, so re-tint when the kind changes
                if t.kind ~= p.kind or t.shown ~= "base" then
                    local c = COLORS[p.kind] or COLORS.blue
                    t.disc:SetVertexColor(c.base[1], c.base[2], c.base[3], 1)
                    t.kind = p.kind
                    t.shown = "base"
                end
            end
        end
    end

    for i, b in ipairs(self.ballTex) do
        local ball = st.balls[i]
        if ball then
            b:ClearAllPoints()
            b:SetPoint("CENTER", field, "TOPLEFT", ball.x, -ball.y)
            if ball.fire then b:SetVertexColor(1, 0.55, 0.2, 1)
            elseif (ball.spooky or 0) > 0 then b:SetVertexColor(0.7, 1, 0.75, 1)
            else b:SetVertexColor(0.92, 0.94, 1.0, 1) end
            b:Show()
        else
            b:Hide()
        end
    end

    if st.phase ~= E.PHASE.FEVER and st.phase ~= E.PHASE.OVER then
        self.bucket:ClearAllPoints()
        self.bucket:SetPoint("TOP", field, "TOPLEFT", st.bucket.x, -(E.BucketTop() - 4))
    end
end

-- ---------------------------------------------------------------------
-- Readouts

function UI:UpdateCounters()
    local st = self.state
    if not st then return end
    self.ballsText:SetText(tostring(st.ballsLeft + #st.balls))
    self.orangeText:SetText(st.orangeLeft .. " / " .. st.orangeTotal)
    self.scoreText:SetText(fmtBig(st.score))
    self.multText:SetText("x" .. E:ScoreMultiplier(st.orangeHit))
    local nextFree = E.FREE_BALL_SCORES[st.freeBallIdx]
    self.freeBallText:SetText(nextFree and fmtBig(nextFree) or "-")
    if st.power == "guide" then
        self.powerStatus:SetText(st.superGuide > 0 and ("Super Guide: " .. st.superGuide .. " shot" ..
            (st.superGuide == 1 and "" or "s") .. " left") or "")
    else
        self.powerStatus:SetText("")
    end
end

function UI:UpdateDisplay()
    local db = GP:GetDB()
    local st = self.state
    if st then
        self.levelText:SetText(("Level %d / %d"):format(st.level, L.COUNT))
        self.chapterText:SetText("|cffaaddff" .. (st.name or "") .. "|r")
        self.layoutText:SetText(("Chapter %d  -  %s"):format(st.chapter, st.layout or ""))
        local name, blurb = powerName(st.power)
        self.powerText:SetText("|cff88ff88" .. name .. "|r")
        self.powerBlurb:SetText(blurb)
        self.bestText:SetText(fmtBig(db.best[st.level] or 0))
        self:UpdateCounters()
        local over = st.phase == E.PHASE.OVER
        local cleared = over and st.result and st.result.cleared
        if cleared and st.level < L.COUNT then self.nextBtn:Show() else self.nextBtn:Hide() end
        styleButton(self.nextBtn, true, 0.2, 0.55, 0.25)
        styleButton(self.retryBtn, true, 0.35, 0.3, 0.45)
    else
        self.levelText:SetText("Gnomish Pachinko")
        self.nextBtn:Hide()
    end
    styleButton(self.levelsBtn, true, 0.35, 0.3, 0.45)
    self.progressText:SetText(("Cleared %d of %d levels\nUnlocked up to level %d"):format(
        GP:ClearedCount(), L.COUNT, db.unlocked or 1))
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
