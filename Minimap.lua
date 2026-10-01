--[[
    Gnomish Pachinko - Minimap.lua
    A round "GP" button on the minimap: left-click opens the game,
    right-click the level select, drag it round the ring to move it. Its
    angle and hidden state live in the saved settings (db.minimap).
]]

local GP = GnomishPachinko
GP.Minimap = GP.Minimap or {}
local M = GP.Minimap

local TEX = "Interface\\AddOns\\GnomishPachinko\\Textures\\"
local atan2 = math.atan2 or math.atan

local function settings()
    local db = GP:GetDB()
    db.minimap = db.minimap or { hide = false, angle = 220 }
    return db.minimap
end

function M:Position()
    local btn = self.button
    if not btn or not Minimap then return end
    local angle = (settings().angle or 220) * math.pi / 180
    local w = (Minimap.GetWidth and Minimap:GetWidth()) or 140
    local radius = w / 2 + 6
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- While dragging, the button follows the cursor round the ring.
function M:FollowCursor()
    if not Minimap or not GetCursorPosition then return end
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    if not cx then return end
    cx, cy = cx / scale, cy / scale
    settings().angle = atan2(cy - my, cx - mx) * 180 / math.pi
    self:Position()
end

function M:Create()
    if self.button or not Minimap then return end
    local btn = CreateFrame("Button", "GnomishPachinkoMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local disc = btn:CreateTexture(nil, "BACKGROUND")
    disc:SetSize(26, 26)
    disc:SetPoint("CENTER")
    disc:SetTexture(TEX .. "peg")
    disc:SetVertexColor(0.36, 0.20, 0.52, 1)
    btn.disc = disc
    local ring = btn:CreateTexture(nil, "BORDER")
    ring:SetSize(33, 33)
    ring:SetPoint("CENTER")
    ring:SetTexture(TEX .. "rim")
    ring:SetVertexColor(0.85, 0.70, 1.00, 1)
    btn.ring = ring
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", 0, 0)
    label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    label:SetText("GP")
    label:SetTextColor(1, 0.85, 0.2)
    btn.label = label

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            GP.UI:Show()
            GP.UI:ShowLevelSelect()
        else
            GP.UI:Toggle()
        end
    end)
    btn:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function() M:FollowCursor() end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
    end)
    btn:SetScript("OnEnter", function(self)
        self.ring:SetVertexColor(1, 0.9, 1, 1)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffffd700Gnomish Pachinko|r")
        local db = GP:GetDB()
        GameTooltip:AddLine(("Level %d  -  %d of %d cleared  -  %d stars"):format(db.current or 1, GP:ClearedCount(), GP.Levels.COUNT, GP:TotalStars()), 0.9, 0.9, 1)
        GameTooltip:AddLine(GP.Plays:StatusText(), 0.8, 0.8, 0.9, true)
        GameTooltip:AddLine("Left-click: play.  Right-click: level select.  Drag: move.", 0.6, 0.6, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self.ring:SetVertexColor(0.85, 0.70, 1.00, 1)
        if GameTooltip then GameTooltip:Hide() end
    end)

    self.button = btn
    self:Position()
    if settings().hide then btn:Hide() end
end

function M:Toggle()
    local s = settings()
    s.hide = not s.hide
    if self.button then
        if s.hide then self.button:Hide() else self.button:Show() end
    end
    GP:Print("Minimap button " .. (s.hide and "hidden" or "shown") .. ".")
end
