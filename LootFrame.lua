LootMirror = {}

local framePool = {}

-- Anchor bar: marks the feed start point
local anchor = CreateFrame("Frame", "LootMirrorAnchor", UIParent, "BackdropTemplate")
anchor:SetSize(300, 20)
anchor:SetMovable(true)
anchor:EnableMouse(true)
anchor:RegisterForDrag("LeftButton")
anchor:SetFrameStrata("HIGH")
anchor:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
})
anchor:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
anchor:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
anchor:Hide()

local anchorText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
anchorText:SetPoint("CENTER")
anchorText:SetText("LootMirror – Drag to move")

anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if LootMirror.SavePosition then LootMirror.SavePosition() end
end)

-- Loot row (backdrop is applied by AcquireRow)
local function CreateLootRow()
    local row = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    row:SetSize(300, 52)
    row:SetFrameStrata("MEDIUM")

    -- Icon border with quality-colored 1px edge (set by Core)
    local iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
    iconBorder:SetSize(40, 40)
    iconBorder:SetPoint("LEFT", row, "LEFT", 9, 0)
    iconBorder:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    iconBorder:SetBackdropColor(0, 0, 0, 1)
    iconBorder:SetBackdropBorderColor(1, 1, 1, 1) -- overwritten per quality
    row.IconBorder = iconBorder

    row.Icon = iconBorder:CreateTexture(nil, "ARTWORK")
    row.Icon:SetPoint("TOPLEFT",     iconBorder, "TOPLEFT",     1, -1)
    row.Icon:SetPoint("BOTTOMRIGHT", iconBorder, "BOTTOMRIGHT", -1, 1)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim icon edges (standard WoW style)

    -- Stack count badge on icon (bottom-right, like WoW inventory)
    row.Count = iconBorder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    row.Count:SetPoint("BOTTOMRIGHT", iconBorder, "BOTTOMRIGHT", 1, 1)
    row.Count:SetText("")

    -- Player name (top, in class color)
    row.PlayerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.PlayerText:SetPoint("TOPLEFT",  iconBorder, "TOPRIGHT",  8, -3)
    row.PlayerText:SetPoint("RIGHT",    row,         "RIGHT",    -9,  0)
    row.PlayerText:SetJustifyH("LEFT")
    row.PlayerText:SetWordWrap(false)

    -- Item name (bottom, in quality color)
    row.ItemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.ItemText:SetPoint("TOPLEFT", row.PlayerText, "BOTTOMLEFT", 0, -3)
    row.ItemText:SetPoint("RIGHT",   row,             "RIGHT",     -9,  0)
    row.ItemText:SetJustifyH("LEFT")
    row.ItemText:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        if not self.itemLink then return end
        -- Choose anchor based on screen position so tooltip is never clipped
        local anchor = (self:GetRight() or 0) > GetScreenWidth() * 0.65
            and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
        GameTooltip:SetOwner(self, anchor)
        GameTooltip:SetHyperlink(self.itemLink)
        if GameTooltip_ShowCompareItem then
            GameTooltip_ShowCompareItem(GameTooltip)
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if GameTooltip_HideShoppingTooltips then
            GameTooltip_HideShoppingTooltips(GameTooltip)
        end
    end)

    return row
end

function LootMirror.ApplyFontSizeToRow(row, size)
    local path, _, flags = GameFontNormalSmall:GetFont()
    row.PlayerText:SetFont(path, size, flags)
    row.ItemText:SetFont(path, size, flags)
end

function LootMirror.ApplyTextureToRow(row, textureName)
    if textureName == "Flat" then
        row:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        row:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
        row:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
    else -- "Blizzard" (default)
        row:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        row:SetBackdropColor(0, 0, 0, 0.85)
        row:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.85)
    end
end

function LootMirror.AcquireRow()
    local row = table.remove(framePool) or CreateLootRow()
    LootMirror.ApplyFontSizeToRow(row, (LootMirrorDB and LootMirrorDB.fontSize) or 11)
    LootMirror.ApplyTextureToRow(row, LootMirrorDB and LootMirrorDB.texture or "Blizzard")
    return row
end

function LootMirror.ReleaseRow(row)
    row:Hide()
    row:ClearAllPoints()
    row.itemLink   = nil
    row.playerName = nil
    row.Count:SetText("")
    table.insert(framePool, row)
end

LootMirror.MainFrame = anchor
