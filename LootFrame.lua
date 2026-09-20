LootMirror = {}

-- Slash command registration (SLASH_LOOTMIRROR1/2 + SlashCmdList["LOOTMIRROR"])
-- lives solely in Options.lua, which loads after this file and owns the
-- actual handler (it needs LootMirror.Options.Toggle, defined there).

local framePool = {}

-- Anchor bar palette -- kept in sync with the dark theme in Options.lua
-- (accent = logo blue, border = the same low-alpha blue-tinted hairline).
local ANCHOR_BG      = { 0.06,  0.06,  0.09,  0.95 }
local ANCHOR_BORDER  = { 0.18,  0.40,  0.48,  0.55 }
local ANCHOR_ACCENT  = { 0.18,  0.72,  0.92 }
local ANCHOR_HEADER  = { 0.56,  0.82,  0.20 }
local ANCHOR_TITLE   = { 1,     0.82,  0.25 }
local ANCHOR_SUBTEXT = { 0.65,  0.65,  0.72 }

-- Anchor bar: marks the feed start point
local anchor = CreateFrame("Frame", "LootMirrorAnchor", UIParent, "BackdropTemplate")
anchor:SetSize(300, 38)
anchor:SetMovable(true)
anchor:EnableMouse(true)
anchor:RegisterForDrag("LeftButton")
anchor:SetFrameStrata("FULLSCREEN")
anchor:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
anchor:SetBackdropColor(unpack(ANCHOR_BG))
anchor:SetBackdropBorderColor(unpack(ANCHOR_BORDER))
anchor:Hide()

-- Top accent line (two solid halves instead of a gradient -- Texture:SetGradient
-- doesn't reliably render on this client, see Options.lua's color picker notes)
local anchorAccentLeft = anchor:CreateTexture(nil, "OVERLAY")
anchorAccentLeft:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
anchorAccentLeft:SetPoint("BOTTOMRIGHT", anchor, "TOP", 0, -3)
anchorAccentLeft:SetColorTexture(unpack(ANCHOR_ACCENT))

local anchorAccentRight = anchor:CreateTexture(nil, "OVERLAY")
anchorAccentRight:SetPoint("TOPLEFT", anchor, "TOP", 0, -1)
anchorAccentRight:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -1, -3)
anchorAccentRight:SetColorTexture(unpack(ANCHOR_HEADER))

local anchorTitle = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
anchorTitle:SetPoint("TOP", anchor, "TOP", 0, -7)
anchorTitle:SetText("LootMirror")
anchorTitle:SetTextColor(unpack(ANCHOR_TITLE))

local anchorSubtext = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
anchorSubtext:SetPoint("TOP", anchorTitle, "BOTTOM", 0, -2)
anchorSubtext:SetText("Drag to move")
anchorSubtext:SetTextColor(unpack(ANCHOR_SUBTEXT))

anchor:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(ANCHOR_ACCENT)) end)
anchor:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(ANCHOR_BORDER)) end)

anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if LootMirror.SavePosition then LootMirror.SavePosition() end
end)

-- Loot row (backdrop is applied by AcquireRow)
local function CreateLootRow()
    local row = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    row:SetSize(300, 52)
    row:SetFrameStrata("FULLSCREEN")

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

    -- Item comparison is gated behind Shift (WoW's usual modifier for it)
    -- instead of following the client's "always compare items" CVar, so it
    -- behaves the same regardless of that global setting. While the row is
    -- hovered, an OnUpdate poll toggles the comparison panels the moment
    -- Shift is pressed/released, without needing to re-hover the row.
    row:SetScript("OnEnter", function(self)
        if not self.itemLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(self.itemLink)

        self.compareShown = IsShiftKeyDown() and true or false
        if self.compareShown and GameTooltip_ShowCompareItem then
            GameTooltip_ShowCompareItem(GameTooltip)
        end

        self:SetScript("OnUpdate", function(rowSelf)
            local shiftDown = IsShiftKeyDown() and true or false
            if shiftDown ~= rowSelf.compareShown then
                rowSelf.compareShown = shiftDown
                if shiftDown then
                    if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
                elseif GameTooltip_HideShoppingTooltips then
                    GameTooltip_HideShoppingTooltips(GameTooltip)
                end
            end
        end)
    end)
    row:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
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

-- textureName picks the backdrop art; borderWidth (px) only applies to "Flat"
-- since "Blizzard" is a fixed tooltip-art skin that distorts at odd widths.
-- Colors are NOT set here -- see ApplyColorsToRow, called separately so the
-- two can be refreshed independently (e.g. live-updating a color swatch
-- shouldn't need to rebuild the whole backdrop).
function LootMirror.ApplyTextureToRow(row, textureName, borderWidth)
    if textureName == "Flat" then
        row:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = borderWidth or 1,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 },
        })
    else -- "Blizzard" (default)
        row:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
    end
end

-- Tints the row's background/border (set via ApplyTextureToRow above).
-- bgA is the background opacity (0-1); border is always drawn fully opaque.
function LootMirror.ApplyColorsToRow(row, bgR, bgG, bgB, bgA, borderR, borderG, borderB)
    row:SetBackdropColor(bgR or 0, bgG or 0, bgB or 0, bgA or 0.85)
    row:SetBackdropBorderColor(borderR or 0.4, borderG or 0.4, borderB or 0.5, 1)
end

-- Row content helpers: the single place that formats colored text onto a row.
-- Shared by real loot events (Core.lua) and the /lm test command, so both
-- paths render identically.
function LootMirror.SetRowLoading(row)
    row.IconBorder:SetBackdropBorderColor(1, 1, 1, 0.4)
    row.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.ItemText:SetText("|cffaaaaaaLoading...|r")
    row.Count:SetText("")
end

function LootMirror.SetRowPlayer(row, playerName, r, g, b)
    local hex = string.format("ff%02x%02x%02x",
        math.floor((r or 1) * 255), math.floor((g or 1) * 255), math.floor((b or 1) * 255))
    row.PlayerText:SetText("|c" .. hex .. (playerName:match("^([^%-]+)") or playerName) .. "|r")
end

function LootMirror.SetRowItem(row, itemName, quality, itemTexture, count)
    local r, g, b = GetItemQualityColor(quality or 1)
    local hex = string.format("ff%02x%02x%02x",
        math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    row.IconBorder:SetBackdropBorderColor(r, g, b, 1)
    row.Icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.ItemText:SetText("|c" .. hex .. itemName .. "|r")
    row.Count:SetText((count and count > 1) and tostring(count) or "")
end

function LootMirror.AcquireRow()
    local row = table.remove(framePool) or CreateLootRow()
    local db = LootMirrorDB or {}
    local bg = db.bgColor or {}
    local bc = db.borderColor or {}
    LootMirror.ApplyFontSizeToRow(row, db.fontSize or 11)
    LootMirror.ApplyTextureToRow(row, db.texture or "Blizzard", db.borderWidth or 1)
    LootMirror.ApplyColorsToRow(row,
        bg.r or 0, bg.g or 0, bg.b or 0, db.bgOpacity or 0.85,
        bc.r or 0.4, bc.g or 0.4, bc.b or 0.5)
    row:SetScale(db.barScale or 1)
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
