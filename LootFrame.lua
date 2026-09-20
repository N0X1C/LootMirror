LootMirror = {}

-- Slash command registration (SLASH_LOOTMIRROR1/2 + SlashCmdList["LOOTMIRROR"])
-- lives solely in Options.lua, which loads after this file and owns the
-- actual handler (it needs LootMirror.Options.Toggle, defined there).

local framePool = {}

-- Wishlist highlight: overrides the row's configured border color while
-- row.isWishlisted is true, restored via row.lastBorderColor (stashed by
-- ApplyColorsToRow) once it's cleared. See LootMirror.SetRowWishlist below.
local WISHLIST_BORDER = { 1, 0.82, 0.1 }

-- Anchor bar palette -- kept in sync with the dark theme in Options.lua
-- (accent = logo blue). Border matches the main window's own outer edge:
-- solid black, full opacity.
local ANCHOR_BG      = { 0.06,  0.06,  0.09,  0.95 }
local ANCHOR_BORDER  = { 0, 0, 0, 1 }
local ANCHOR_ACCENT  = { 0.18,  0.72,  0.92 }
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

local anchorTitle = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
anchorTitle:SetPoint("TOP", anchor, "TOP", 0, -7)
anchorTitle:SetText("LootMirror")
anchorTitle:SetTextColor(unpack(ANCHOR_ACCENT))

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

--------------------------------------------------------------------------
-- Shared scrollable list: a ScrollFrame + its scroll-child `content` frame,
-- plus a thin custom scrollbar (track+thumb) wired up for mouse-wheel and
-- drag-to-scroll. Used by both Options.lua's settings list and Wishlist.lua's
-- item list so the mechanics/look can't drift between them the way two
-- separately hand-rolled copies eventually would.
--
-- opts:
--   anchorFn(scrollFrame, scrollbarWidth, scrollbarGap) -- required; sets
--     the scrollFrame's own TOPLEFT/BOTTOMRIGHT anchors. Takes the reserved
--     scrollbar width/gap so it can leave room for scrollbarTrack on the
--     right -- how much space is available/who it's anchored to differs
--     per caller.
--   contentWidth -- required; sizes `content` up front, since it needs a
--     width before the scrollFrame itself has a measured one to read.
--   wheelStep -- optional, default 40; pixels scrolled per wheel notch.
--   scrollbarWidth / scrollbarGap -- optional, default 6 / 6.
--
-- Returns { scrollFrame, content, scrollbarTrack, UpdateScrollbar, SetScrollPct }.
function LootMirror.CreateScrollList(parent, opts)
    local scrollbarWidth = opts.scrollbarWidth or 6
    local scrollbarGap   = opts.scrollbarGap or 6
    local wheelStep       = opts.wheelStep or 40
    local WHITE = "Interface\\Buttons\\WHITE8x8"

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:EnableMouseWheel(true)
    opts.anchorFn(scrollFrame, scrollbarWidth, scrollbarGap)

    -- See Options.lua's original comment on this pattern: scroll children
    -- need an explicit size and a single anchor point -- the ScrollFrame
    -- manages the child's position internally to implement scrolling, and a
    -- second competing anchor (e.g. also anchoring TOPRIGHT) fights that.
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(opts.contentWidth, 1) -- height corrected by the caller once it's known
    scrollFrame:SetScrollChild(content)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)

    local scrollbarTrack = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    scrollbarTrack:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", scrollbarGap, 0)
    scrollbarTrack:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", scrollbarGap + scrollbarWidth, 0)
    scrollbarTrack:SetBackdrop({ bgFile = WHITE })
    scrollbarTrack:SetBackdropColor(0.16, 0.16, 0.22, 0.5)

    local scrollThumb = CreateFrame("Button", nil, scrollbarTrack, "BackdropTemplate")
    scrollThumb:SetPoint("TOPLEFT", scrollbarTrack, "TOPLEFT", 1, -1)
    scrollThumb:SetPoint("TOPRIGHT", scrollbarTrack, "TOPRIGHT", -1, -1)
    scrollThumb:SetBackdrop({ bgFile = WHITE })
    scrollThumb:SetBackdropColor(0.18, 0.72, 0.92)
    scrollThumb:SetScript("OnEnter", function(self) self:SetBackdropColor(1, 1, 1, 1) end)
    scrollThumb:SetScript("OnLeave", function(self) self:SetBackdropColor(0.18, 0.72, 0.92) end)

    local function UpdateScrollbar()
        local visibleH = scrollFrame:GetHeight()
        local contentH = content:GetHeight()
        local maxScroll = math.max(contentH - visibleH, 0)
        local trackH = scrollbarTrack:GetHeight() - 2
        if maxScroll <= 0 or trackH <= 0 then
            scrollThumb:Hide()
            return
        end
        scrollThumb:Show()
        local thumbH = math.min(math.max((visibleH / contentH) * trackH, 20), trackH)
        scrollThumb:SetHeight(thumbH)
        local scrollPct = scrollFrame:GetVerticalScroll() / maxScroll
        local travel = trackH - thumbH
        scrollThumb:ClearAllPoints()
        scrollThumb:SetPoint("TOPLEFT", scrollbarTrack, "TOPLEFT", 1, -1 - scrollPct * travel)
        scrollThumb:SetPoint("TOPRIGHT", scrollbarTrack, "TOPRIGHT", -1, -1 - scrollPct * travel)
    end

    local function SetScrollPct(pct)
        pct = math.min(math.max(pct, 0), 1)
        local maxScroll = math.max(content:GetHeight() - scrollFrame:GetHeight(), 0)
        scrollFrame:SetVerticalScroll(pct * maxScroll)
        UpdateScrollbar()
    end

    local function ScrollThumbOnUpdate(self)
        local scale = scrollbarTrack:GetEffectiveScale()
        local _, my = GetCursorPosition()
        my = my / scale
        local top = scrollbarTrack:GetTop()
        local trackH = scrollbarTrack:GetHeight() - 2
        local thumbH = self:GetHeight()
        local travel = trackH - thumbH
        if travel <= 0 then return end
        local pct = (top - 1 - thumbH / 2 - my) / travel
        SetScrollPct(pct)
    end

    -- OnUpdate is only attached while a drag is actually happening, not left
    -- running every frame for the lifetime of the containing window.
    scrollThumb:SetScript("OnMouseDown", function(self)
        self:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    scrollThumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(content:GetHeight() - self:GetHeight(), 0)
        if maxScroll <= 0 then return end
        local newScroll = self:GetVerticalScroll() - delta * wheelStep
        newScroll = math.min(math.max(newScroll, 0), maxScroll)
        self:SetVerticalScroll(newScroll)
        UpdateScrollbar()
    end)

    scrollFrame:SetScript("OnSizeChanged", UpdateScrollbar)

    return {
        scrollFrame = scrollFrame,
        content = content,
        scrollbarTrack = scrollbarTrack,
        UpdateScrollbar = UpdateScrollbar,
        SetScrollPct = SetScrollPct,
    }
end

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

    -- Wishlist star badge (top-left of icon), shown by LootMirror.SetRowWishlist
    row.WishlistIcon = iconBorder:CreateTexture(nil, "OVERLAY", nil, 1)
    row.WishlistIcon:SetSize(14, 14)
    row.WishlistIcon:SetPoint("CENTER", iconBorder, "TOPLEFT", 1, -1)
    row.WishlistIcon:SetAtlas("auctionhouse-icon-favorite")
    row.WishlistIcon:Hide()

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

local function ApplyRowBorderColor(row, borderR, borderG, borderB)
    if row.isWishlisted then
        row:SetBackdropBorderColor(WISHLIST_BORDER[1], WISHLIST_BORDER[2], WISHLIST_BORDER[3], 1)
    else
        row:SetBackdropBorderColor(borderR or 0.4, borderG or 0.4, borderB or 0.5, 1)
    end
end

-- Tints the row's background/border (set via ApplyTextureToRow above).
-- bgA is the background opacity (0-1); border is always drawn fully opaque.
-- borderR/G/B is stashed on the row so SetRowWishlist can restore it after
-- the wishlist highlight (which overrides the border color) is cleared.
function LootMirror.ApplyColorsToRow(row, bgR, bgG, bgB, bgA, borderR, borderG, borderB)
    row:SetBackdropColor(bgR or 0, bgG or 0, bgB or 0, bgA or 0.85)
    row.lastBorderColor = { borderR, borderG, borderB }
    ApplyRowBorderColor(row, borderR, borderG, borderB)
end

-- Marks/unmarks a row as matching a wishlist entry: gold border + star badge,
-- regardless of who loots it. Called from Core.lua as soon as a row is
-- created (the itemID is known immediately from the loot link, before the
-- item's name/quality may have resolved).
function LootMirror.SetRowWishlist(row, isWishlisted)
    row.isWishlisted = isWishlisted and true or false
    row.WishlistIcon:SetShown(row.isWishlisted)
    local lc = row.lastBorderColor or {}
    ApplyRowBorderColor(row, lc[1], lc[2], lc[3])
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
    row.isWishlisted = false
    row.WishlistIcon:Hide()
    table.insert(framePool, row)
end

LootMirror.MainFrame = anchor
