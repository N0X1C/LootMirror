-- Options.lua
-- Modern dark options panel for LootMirror.
-- Built entirely from native widget types (Frame/Slider/Button/ScrollFrame +
-- BackdropTemplate) instead of legacy XML templates (UIDropDownMenuTemplate,
-- OptionsSliderTemplate, UIRadioButtonTemplate, GameMenuButtonTemplate, or a
-- Blizzard scroll template), which may error out or be gone on newer clients
-- -- an error there would previously abort the rest of this file and
-- silently break the "/lm" toggle.

--------------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------------
-- Accent colors pulled from the NOXIC logo (blue + green), replacing the
-- earlier purple/cyan scheme. Border alpha kept low so the thin (1px) edges
-- read as subtle hairlines instead of bold outlines.
local C = {
    bg      = { 0.045, 0.045, 0.065, 0.95 },
    card    = { 0.10,  0.10,  0.15,  0.55 },
    border  = { 0.18,  0.40,  0.48,  0.55 },
    accent  = { 0.18,  0.72,  0.92 },
    header  = { 0.56,  0.82,  0.20 },
    title   = { 1,     0.82,  0.25 },
    text    = { 0.88,  0.88,  0.92 },
    subtext = { 0.55,  0.55,  0.62 },
    track   = { 0.16,  0.16,  0.22, 1 },
    control = { 0.09,  0.09,  0.13, 0.9 },
}

local WHITE = "Interface\\Buttons\\WHITE8x8"
local PADDING = 20
local WIDTH   = 400
local HEIGHT  = 720 -- fixed window height; content beyond this scrolls (see below)

local SCROLLBAR_WIDTH = 6
local SCROLLBAR_GAP   = 6
local CONTENT_WIDTH   = WIDTH - PADDING * 2 - SCROLLBAR_WIDTH - SCROLLBAR_GAP

local HEADER_HEIGHT = 98  -- title/subtitle/panel-scale slider -- fixed, never scrolls
local FOOTER_HEIGHT = 96  -- Move Anchor/Test/Save buttons -- fixed, never scrolls

--------------------------------------------------------------------------
-- Main frame
--------------------------------------------------------------------------
local optFrame = CreateFrame("Frame", "LootMirrorOptionsFrame", UIParent, "BackdropTemplate")
optFrame:SetSize(WIDTH, HEIGHT)
optFrame:SetMovable(true)
optFrame:EnableMouse(true)
optFrame:RegisterForDrag("LeftButton")
optFrame:SetClampedToScreen(true)
optFrame:SetToplevel(true)
optFrame:SetFrameStrata("DIALOG")
optFrame:SetBackdrop({
    bgFile   = WHITE,
    edgeFile = WHITE,
    edgeSize = 1,
})
optFrame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], (LootMirrorDB and LootMirrorDB.optionsOpacity) or C.bg[4])
optFrame:SetBackdropBorderColor(unpack(C.border))
optFrame:SetScale((LootMirrorDB and LootMirrorDB.optionsScale) or 1)
optFrame:Hide()

optFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
optFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    LootMirrorDB = LootMirrorDB or {}
    LootMirrorDB.optionsPoint = point or "CENTER"
    LootMirrorDB.optionsRelativePoint = relativePoint or point or "CENTER"
    LootMirrorDB.optionsX = x or 0
    LootMirrorDB.optionsY = y or 0
end)

-- Top accent line (two solid halves instead of a gradient -- Texture:SetGradient
-- doesn't reliably render on this client, see the color picker notes below)
local topAccentLeft = optFrame:CreateTexture(nil, "OVERLAY")
topAccentLeft:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 1, -1)
topAccentLeft:SetPoint("BOTTOMRIGHT", optFrame, "TOP", 0, -3)
topAccentLeft:SetColorTexture(unpack(C.accent))

local topAccentRight = optFrame:CreateTexture(nil, "OVERLAY")
topAccentRight:SetPoint("TOPLEFT", optFrame, "TOP", 0, -1)
topAccentRight:SetPoint("BOTTOMRIGHT", optFrame, "TOPRIGHT", -1, -3)
topAccentRight:SetColorTexture(unpack(C.header))

-- Title
local title = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", optFrame, "TOP", 0, -18)
title:SetText("LootMirror")
title:SetTextColor(unpack(C.title))

local subtitle = optFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
subtitle:SetText("Loot Feed Configuration")
subtitle:SetTextColor(unpack(C.subtext))

-- Close button (custom, no template dependency)
local closeBtn = CreateFrame("Button", nil, optFrame)
closeBtn:SetSize(24, 24)
closeBtn:SetPoint("TOPRIGHT", optFrame, "TOPRIGHT", -8, -8)
local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
closeText:SetPoint("CENTER")
closeText:SetText("\195\151") -- ×
closeText:SetTextColor(0.65, 0.65, 0.72, 1)
closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.35, 0.35, 1) end)
closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(0.65, 0.65, 0.72, 1) end)
closeBtn:SetScript("OnClick", function() optFrame:Hide() end)

--------------------------------------------------------------------------
-- Slider builder: a single reusable widget, usable both in the fixed header
-- (Panel Scale) and in the scrollable content area (all other sliders).
-- BuildSliderRow does the actual construction at an explicit (parent, y);
-- CreateModernSlider is a thin wrapper for content-area use that advances
-- the shared `currentY` cursor.
--------------------------------------------------------------------------
-- leftX/rightX (inset from the parent's left/right edges) default to the full
-- content width, but can be narrowed so two sliders fit side by side in a row
-- (used for the fixed header's Panel Scale / Panel Opacity pair below).
local function BuildSliderRow(parent, topY, labelText, minV, maxV, stepV, defaultV, formatter, leftX, rightX)
    leftX = leftX or PADDING
    rightX = rightX or PADDING

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", leftX, -topY)
    label:SetText(labelText)
    label:SetTextColor(unpack(C.text))

    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -rightX, -topY)
    valueText:SetTextColor(unpack(C.accent))

    -- Flat, borderless hairline track (no backdrop edge) with a round "pill"
    -- dot for a thumb instead of a chunky rectangle -- CircleMaskScalable is
    -- a plain white circle-on-transparent shipped with the client (also used
    -- by Blizzard for round icon masks), so it works as a normal colored
    -- texture here without needing a custom art asset.
    local trackY = topY + 20
    local track = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    track:SetHeight(2)
    track:SetPoint("TOPLEFT", parent, "TOPLEFT", leftX, -trackY)
    track:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -rightX, -trackY)
    track:SetBackdrop({ bgFile = WHITE })
    track:SetBackdropColor(unpack(C.track))

    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(unpack(C.accent))
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)
    fill:SetWidth(1)

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(16)
    slider:SetPoint("LEFT", track, "LEFT", 0, 0)
    slider:SetPoint("RIGHT", track, "RIGHT", 0, 0)
    slider:EnableMouse(true)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(stepV)
    slider:SetObeyStepOnDrag(true)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Masks\\CircleMaskScalable")
    thumb:SetSize(12, 12)
    thumb:SetVertexColor(unpack(C.accent))
    slider:SetThumbTexture(thumb)

    local function Refresh(val)
        local pct = (val - minV) / (maxV - minV)
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        fill:SetWidth(math.max(track:GetWidth() * pct, 1))
        valueText:SetText(formatter(val))
    end

    slider:SetScript("OnValueChanged", function(self, val) Refresh(val) end)
    slider:SetScript("OnShow", function(self) Refresh(self:GetValue()) end)
    slider:SetScript("OnEnter", function() thumb:SetVertexColor(1, 1, 1, 1) end)
    slider:SetScript("OnLeave", function() thumb:SetVertexColor(unpack(C.accent)) end)

    slider:SetValue(defaultV)
    Refresh(defaultV)

    return slider
end

-- Panel Scale: lives in the fixed header, always visible. Not gated behind
-- Save (it only affects this window, not addon behavior) -- but the actual
-- optFrame:SetScale() only fires on mouse-up, not on every OnValueChanged
-- tick while dragging, since rescaling the whole window on every 5% step
-- mid-drag caused a visible flicker/jump. The slider's own fill/label still
-- update immediately (that's just BuildSliderRow's internal Refresh).
local function ApplyPanelScale(val)
    optFrame:SetScale(val)
    LootMirrorDB = LootMirrorDB or {}
    LootMirrorDB.optionsScale = val
end

-- Panel Opacity sits next to Panel Scale in the same header row -- unlike
-- scale, changing alpha has no layout/flicker cost, so it applies live on
-- every OnValueChanged tick instead of waiting for mouse-up.
local function ApplyPanelOpacity(val)
    optFrame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], val)
    LootMirrorDB = LootMirrorDB or {}
    LootMirrorDB.optionsOpacity = val
end

local HEADER_COL_GAP   = 16
local HEADER_COL_WIDTH = (WIDTH - PADDING * 2 - HEADER_COL_GAP) / 2

local panelScaleSlider = BuildSliderRow(optFrame, 58, "Panel Scale", 0.7, 1.3, 0.05, 1, function(v)
    return tostring(math.floor(v * 100 + 0.5)) .. "%"
end, PADDING, WIDTH - PADDING - HEADER_COL_WIDTH)
panelScaleSlider:HookScript("OnMouseUp", function(self)
    ApplyPanelScale(self:GetValue())
end)

local panelOpacitySlider = BuildSliderRow(optFrame, 58, "Panel Opacity", 0.3, 1, 0.05, 0.95, function(v)
    return tostring(math.floor(v * 100 + 0.5)) .. "%"
end, PADDING + HEADER_COL_WIDTH + HEADER_COL_GAP, PADDING)
panelOpacitySlider:HookScript("OnValueChanged", function(self, val)
    ApplyPanelOpacity(val)
end)

--------------------------------------------------------------------------
-- Scrollable content area
--------------------------------------------------------------------------
local scrollFrame = CreateFrame("ScrollFrame", nil, optFrame)
scrollFrame:SetPoint("TOPLEFT", optFrame, "TOPLEFT", PADDING, -HEADER_HEIGHT)
scrollFrame:SetPoint("BOTTOMRIGHT", optFrame, "BOTTOMRIGHT", -(PADDING + SCROLLBAR_WIDTH + SCROLLBAR_GAP), FOOTER_HEIGHT)
scrollFrame:EnableMouseWheel(true)

-- Scroll children must be sized explicitly (SetWidth/SetHeight) with a single
-- anchor point -- the ScrollFrame manages the child's position internally to
-- implement scrolling, and a second competing anchor (e.g. also anchoring
-- TOPRIGHT to the scroll frame) fights that, which is why every child of
-- `content` rendered as empty/invisible in the first version of this panel.
local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(CONTENT_WIDTH, 1) -- height corrected once total content height is known, near the bottom of this file
scrollFrame:SetScrollChild(content)
content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)

-- Custom scrollbar (track + thumb): flat and borderless, same treatment as
-- the sliders/cards -- a thin translucent track with a slim accent-colored
-- thumb inset 1px inside it, instead of a bordered box.
local scrollbarTrack = CreateFrame("Frame", nil, optFrame, "BackdropTemplate")
scrollbarTrack:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", SCROLLBAR_GAP, 0)
scrollbarTrack:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", SCROLLBAR_GAP + SCROLLBAR_WIDTH, 0)
scrollbarTrack:SetBackdrop({ bgFile = WHITE })
scrollbarTrack:SetBackdropColor(C.track[1], C.track[2], C.track[3], 0.5)

local scrollThumb = CreateFrame("Button", nil, scrollbarTrack, "BackdropTemplate")
scrollThumb:SetPoint("TOPLEFT", scrollbarTrack, "TOPLEFT", 1, -1)
scrollThumb:SetPoint("TOPRIGHT", scrollbarTrack, "TOPRIGHT", -1, -1)
scrollThumb:SetBackdrop({ bgFile = WHITE })
scrollThumb:SetBackdropColor(unpack(C.accent))
scrollThumb:SetScript("OnEnter", function(self) self:SetBackdropColor(1, 1, 1, 1) end)
scrollThumb:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(C.accent)) end)

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
-- running every frame for the lifetime of the options window.
scrollThumb:SetScript("OnMouseDown", function(self)
    self:SetScript("OnUpdate", ScrollThumbOnUpdate)
end)
scrollThumb:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
end)

scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(content:GetHeight() - self:GetHeight(), 0)
    if maxScroll <= 0 then return end
    local newScroll = self:GetVerticalScroll() - delta * 40
    newScroll = math.min(math.max(newScroll, 0), maxScroll)
    self:SetVerticalScroll(newScroll)
    UpdateScrollbar()
end)

scrollFrame:SetScript("OnSizeChanged", UpdateScrollbar)

--------------------------------------------------------------------------
-- Layout helpers for the scrollable content area
--------------------------------------------------------------------------
local currentY = 12

local function AddSectionHeader(text)
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING, -currentY)
    fs:SetText(text:upper())
    fs:SetTextColor(unpack(C.header))

    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(C.border))
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", content, "RIGHT", -PADDING, 0)

    currentY = currentY + 22
end

-- Decorative card panel drawn *behind* a block of controls.
-- FrameLevel is pinned to the parent's own level so it renders behind
-- sibling controls (which default to parent level + 1).
local function AddCardPanel(startY, height)
    local panel = CreateFrame("Frame", nil, content, "BackdropTemplate")
    panel:SetFrameLevel(content:GetFrameLevel())
    panel:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING - 6, -startY)
    panel:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(PADDING - 6), -startY)
    panel:SetHeight(height)
    panel:SetBackdrop({ bgFile = WHITE })
    panel:SetBackdropColor(unpack(C.card))
    return panel
end

local function CreateModernSlider(labelText, minV, maxV, stepV, defaultV, formatter)
    currentY = currentY + 10
    local slider = BuildSliderRow(content, currentY, labelText, minV, maxV, stepV, defaultV, formatter)
    currentY = currentY + 20 + 22
    return slider
end

--------------------------------------------------------------------------
-- Custom dropdown (self-contained, no UIDropDownMenu dependency).
-- The popup menu list is parented to optFrame (not content) and positioned
-- via SetPoint against the dropdown box -- otherwise the ScrollFrame would
-- clip the open menu the moment it extends past the visible scroll area.
--------------------------------------------------------------------------
local openMenus = {}
local function CloseAllMenus(except)
    for _, m in ipairs(openMenus) do
        if m ~= except then m:Hide() end
    end
end

local function CreateModernDropdown(labelText, options)
    currentY = currentY + 10
    local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING, -currentY)
    label:SetText(labelText)
    label:SetTextColor(unpack(C.text))
    currentY = currentY + 20

    local box = CreateFrame("Button", nil, content, "BackdropTemplate")
    box:SetHeight(26)
    box:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING, -currentY)
    box:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PADDING, -currentY)
    box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    box:SetBackdropColor(unpack(C.control))
    box:SetBackdropBorderColor(unpack(C.border))

    local selectedText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    selectedText:SetPoint("LEFT", box, "LEFT", 10, 0)
    selectedText:SetTextColor(unpack(C.text))

    local arrow = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow:SetPoint("RIGHT", box, "RIGHT", -10, 0)
    arrow:SetText("v")
    arrow:SetTextColor(unpack(C.accent))

    box:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    box:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)

    local optionHeight = 24
    local menu = CreateFrame("Frame", nil, optFrame, "BackdropTemplate")
    menu:SetFrameLevel(optFrame:GetFrameLevel() + 50)
    menu:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
    menu:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
    menu:SetHeight(#options * optionHeight + 4)
    menu:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    menu:SetBackdropColor(0.05, 0.05, 0.08, 0.98)
    menu:SetBackdropBorderColor(unpack(C.accent))
    menu:Hide()
    table.insert(openMenus, menu)

    local control = { value = options[1] and options[1].value }

    local function SetValue(value)
        for _, e in ipairs(options) do
            if e.value == value then
                selectedText:SetText(e.text)
                control.value = value
                return
            end
        end
    end

    for i, entry in ipairs(options) do
        local optBtn = CreateFrame("Button", nil, menu)
        optBtn:SetHeight(optionHeight)
        optBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -2 - (i - 1) * optionHeight)
        optBtn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, -2 - (i - 1) * optionHeight)

        local hl = optBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetColorTexture(unpack(C.accent))
        hl:SetAllPoints()
        hl:SetAlpha(0.2)

        local optText = optBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        optText:SetPoint("LEFT", optBtn, "LEFT", 8, 0)
        optText:SetText(entry.text)
        optText:SetTextColor(unpack(C.text))

        optBtn:SetScript("OnClick", function()
            SetValue(entry.value)
            menu:Hide()
        end)
    end

    box:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            CloseAllMenus(menu)
            menu:Show()
        end
    end)

    control.SetValue = SetValue
    control.GetValue = function() return control.value end
    SetValue(control.value)

    currentY = currentY + 26 + 10
    return control
end

optFrame:HookScript("OnHide", function() CloseAllMenus() end)

--------------------------------------------------------------------------
-- Quality filter checkbox (self-contained, matches the dark theme)
--------------------------------------------------------------------------
local QUALITY_LABELS = {
    [1] = _G.ITEM_QUALITY1_DESC or "Common",
    [2] = _G.ITEM_QUALITY2_DESC or "Uncommon",
    [3] = _G.ITEM_QUALITY3_DESC or "Rare",
    [4] = _G.ITEM_QUALITY4_DESC or "Epic",
    [5] = _G.ITEM_QUALITY5_DESC or "Legendary",
}

local function CreateQualityCheckbox(qualityIndex, x, y)
    local r, g, b = GetItemQualityColor(qualityIndex)

    local box = CreateFrame("Button", nil, content, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    box:SetBackdropColor(unpack(C.control))
    box:SetBackdropBorderColor(r, g, b, 1)

    local fill = box:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
    fill:SetColorTexture(r, g, b, 1)

    local label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    label:SetText(QUALITY_LABELS[qualityIndex] or ("Quality " .. qualityIndex))
    label:SetTextColor(r, g, b)

    local checked = true
    local function Refresh() fill:SetShown(checked) end

    box:SetScript("OnClick", function()
        checked = not checked
        Refresh()
    end)
    box:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 1, 1, 1) end)
    box:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(r, g, b, 1) end)

    Refresh()

    return {
        GetChecked = function() return checked end,
        SetChecked = function(v) checked = (v ~= false); Refresh() end,
    }
end

--------------------------------------------------------------------------
-- Custom color picker popup: SV square + vertical hue bar + New/Prev swatch
-- + hex input (matches the ElvUI-style layout), built entirely from plain
-- colored textures so it matches the dark theme. Deliberately not Blizzard's
-- ColorPickerFrame: that's a single shared frame used by every addon and
-- Blizzard system, so reskinning it would change its look everywhere, not
-- just here -- and its internal structure has changed across expansions, so
-- guessing sub-frame names to reskin risks silently doing nothing (or
-- erroring) on a client version we can't test against.
-- Parented directly to optFrame (not content) so it's never clipped by the
-- ScrollFrame, same reasoning as the dropdown menus above.
--------------------------------------------------------------------------
local function HSVtoRGB(h, s, v)
    local c = v * s
    local x = c * (1 - math.abs(((h / 60) % 2) - 1))
    local m = v - c
    local r, g, b
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x
    end
    return r + m, g + m, b + m
end

local function RGBtoHSV(r, g, b)
    local maxc, minc = math.max(r, g, b), math.min(r, g, b)
    local v = maxc
    local d = maxc - minc
    local s = (maxc == 0) and 0 or (d / maxc)
    local h
    if d == 0 then
        h = 0
    elseif maxc == r then
        h = 60 * (((g - b) / d) % 6)
    elseif maxc == g then
        h = 60 * (((b - r) / d) + 2)
    else
        h = 60 * (((r - g) / d) + 4)
    end
    return h, s, v
end

local SV_WIDTH      = 140
local SV_HEIGHT     = 110
local HUE_BAR_WIDTH = 16

local colorPopup = CreateFrame("Frame", nil, optFrame, "BackdropTemplate")
colorPopup:SetSize(270, 210)
colorPopup:SetFrameLevel(optFrame:GetFrameLevel() + 50)
colorPopup:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
colorPopup:SetBackdropColor(0.05, 0.05, 0.08, 0.98)
colorPopup:SetBackdropBorderColor(unpack(C.accent))
colorPopup:Hide()
table.insert(openMenus, colorPopup) -- closed by CloseAllMenus, same as dropdown menus

local colorPopupTitle = colorPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
colorPopupTitle:SetPoint("TOP", colorPopup, "TOP", 0, -10)
colorPopupTitle:SetTextColor(unpack(C.header))

-- Saturation/Value square: a grid of solid-colored cells, each cell's color
-- computed directly from HSV (hue, s-for-this-column, v-for-this-row) via
-- SetColorTexture. NOTE: this deliberately avoids Texture:SetGradient --
-- on this client, SetGradient calls silently do nothing (texture stays
-- blank), which is why the first version of this popup showed a flat color
-- instead of a saturation/value fade. SetColorTexture is what every other
-- solid swatch in this file already uses successfully, so the grid is built
-- from that instead of trusting gradients.
local SV_COLS = 35
local SV_ROWS = 28

local svSquare = CreateFrame("Frame", nil, colorPopup, "BackdropTemplate")
svSquare:SetSize(SV_WIDTH, SV_HEIGHT)
svSquare:SetPoint("TOPLEFT", colorPopup, "TOPLEFT", 14, -32)
svSquare:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
svSquare:SetBackdropBorderColor(unpack(C.border))
svSquare:EnableMouse(true)

local svCellW = (SV_WIDTH - 2) / SV_COLS
local svCellH = (SV_HEIGHT - 2) / SV_ROWS
local svCells = {}
for row = 0, SV_ROWS - 1 do
    svCells[row] = {}
    for col = 0, SV_COLS - 1 do
        local cell = svSquare:CreateTexture(nil, "ARTWORK")
        cell:SetSize(svCellW + 0.5, svCellH + 0.5) -- tiny overlap so there are no seam lines
        cell:SetPoint("TOPLEFT", svSquare, "TOPLEFT", 1 + col * svCellW, -1 - row * svCellH)
        svCells[row][col] = cell
    end
end

-- Marker is a black+white double cross so it stays visible over both light
-- and dark cells (a plain white marker disappears over the pale top-left area).
local svMarkerHOuter = svSquare:CreateTexture(nil, "OVERLAY")
svMarkerHOuter:SetSize(10, 3)
svMarkerHOuter:SetColorTexture(0, 0, 0, 1)
local svMarkerVOuter = svSquare:CreateTexture(nil, "OVERLAY")
svMarkerVOuter:SetSize(3, 10)
svMarkerVOuter:SetColorTexture(0, 0, 0, 1)
local svMarkerH = svSquare:CreateTexture(nil, "OVERLAY")
svMarkerH:SetSize(8, 1)
svMarkerH:SetColorTexture(1, 1, 1, 1)
local svMarkerV = svSquare:CreateTexture(nil, "OVERLAY")
svMarkerV:SetSize(1, 8)
svMarkerV:SetColorTexture(1, 1, 1, 1)

local function RepaintSVGrid(hue)
    for row = 0, SV_ROWS - 1 do
        local v = 1 - (row / (SV_ROWS - 1))
        for col = 0, SV_COLS - 1 do
            local s = col / (SV_COLS - 1)
            local r, g, b = HSVtoRGB(hue, s, v)
            svCells[row][col]:SetColorTexture(r, g, b, 1)
        end
    end
end

-- Hue bar: many thin solid-colored strips (one per fine hue step), same
-- SetColorTexture approach as the SV grid above -- no SetGradient involved.
local HUE_STRIPS = 72

local hueBar = CreateFrame("Frame", nil, colorPopup, "BackdropTemplate")
hueBar:SetSize(HUE_BAR_WIDTH, SV_HEIGHT)
hueBar:SetPoint("LEFT", svSquare, "RIGHT", 10, 0)
hueBar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
hueBar:SetBackdropBorderColor(unpack(C.border))
hueBar:EnableMouse(true)

local hueStripH = (SV_HEIGHT - 2) / HUE_STRIPS
for i = 0, HUE_STRIPS - 1 do
    local hue = (i / HUE_STRIPS) * 360
    local r, g, b = HSVtoRGB(hue, 1, 1)
    local strip = hueBar:CreateTexture(nil, "ARTWORK")
    strip:SetSize(HUE_BAR_WIDTH - 2, hueStripH + 0.5) -- tiny overlap so there are no seam lines
    strip:SetPoint("TOP", hueBar, "TOP", 0, -1 - i * hueStripH)
    strip:SetColorTexture(r, g, b, 1)
end

local hueMarker = hueBar:CreateTexture(nil, "OVERLAY")
hueMarker:SetSize(HUE_BAR_WIDTH + 4, 2)
hueMarker:SetColorTexture(1, 1, 1, 1)

-- New / Prev swatches + hex input, stacked to the right of the hue bar
local function CreateSmallLabel(anchorTo, anchorPoint, x, y, text)
    local fs = colorPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", anchorTo, anchorPoint, x, y)
    fs:SetText(text)
    fs:SetTextColor(unpack(C.subtext))
    return fs
end

local rightColX = 14 + SV_WIDTH + 10 + HUE_BAR_WIDTH + 10

local newLabel = CreateSmallLabel(colorPopup, "TOPLEFT", rightColX, -32, "New")
local newSwatch = CreateFrame("Frame", nil, colorPopup, "BackdropTemplate")
newSwatch:SetSize(60, 22)
newSwatch:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 0, -2)
newSwatch:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
newSwatch:SetBackdropBorderColor(unpack(C.border))

local prevLabel = CreateSmallLabel(newSwatch, "BOTTOMLEFT", 0, -8, "Prev")
local prevSwatch = CreateFrame("Button", nil, colorPopup, "BackdropTemplate")
prevSwatch:SetSize(60, 22)
prevSwatch:SetPoint("TOPLEFT", prevLabel, "BOTTOMLEFT", 0, -2)
prevSwatch:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
prevSwatch:SetBackdropBorderColor(unpack(C.border))

local hexLabel = CreateSmallLabel(prevSwatch, "BOTTOMLEFT", 0, -8, "Hex#")
local hexBox = CreateFrame("EditBox", nil, colorPopup, "BackdropTemplate")
hexBox:SetSize(60, 20)
hexBox:SetPoint("TOPLEFT", hexLabel, "BOTTOMLEFT", 0, -2)
hexBox:SetAutoFocus(false)
hexBox:SetFontObject(GameFontHighlightSmall)
hexBox:SetMaxLetters(6)
hexBox:SetJustifyH("CENTER")
hexBox:SetTextInsets(2, 2, 0, 0)
hexBox:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
hexBox:SetBackdropColor(unpack(C.control))
hexBox:SetBackdropBorderColor(unpack(C.border))

-- Cancel / OK buttons
local function CreatePopupButton(text, width)
    local btn = CreateFrame("Button", nil, colorPopup, "BackdropTemplate")
    btn:SetSize(width, 22)
    btn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    btn:SetBackdropColor(unpack(C.control))
    btn:SetBackdropBorderColor(unpack(C.border))
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(unpack(C.text))
    btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
    return btn
end

local cancelBtn = CreatePopupButton("Cancel", 70)
cancelBtn:SetPoint("BOTTOMLEFT", colorPopup, "BOTTOMLEFT", 55, 12)

local okBtn = CreatePopupButton("OK", 70)
okBtn:SetPoint("LEFT", cancelBtn, "RIGHT", 10, 0)

local colorState = { h = 0, s = 1, v = 1 }
local prevState  = { h = 0, s = 1, v = 1 }
local colorPopupApplyLive -- callback set each time the popup opens for a swatch

local function RefreshColorPopup()
    local r, g, b = HSVtoRGB(colorState.h, colorState.s, colorState.v)
    newSwatch:SetBackdropColor(r, g, b, 1)

    RepaintSVGrid(colorState.h)

    local huePct = colorState.h / 360
    hueMarker:ClearAllPoints()
    hueMarker:SetPoint("TOP", hueBar, "TOP", 0, -huePct * SV_HEIGHT)

    svMarkerH:ClearAllPoints()
    svMarkerV:ClearAllPoints()
    svMarkerHOuter:ClearAllPoints()
    svMarkerVOuter:ClearAllPoints()
    local mx = 1 + colorState.s * (SV_WIDTH - 2)
    local my = -1 - (1 - colorState.v) * (SV_HEIGHT - 2)
    svMarkerH:SetPoint("CENTER", svSquare, "TOPLEFT", mx, my)
    svMarkerV:SetPoint("CENTER", svSquare, "TOPLEFT", mx, my)
    svMarkerHOuter:SetPoint("CENTER", svSquare, "TOPLEFT", mx, my)
    svMarkerVOuter:SetPoint("CENTER", svSquare, "TOPLEFT", mx, my)

    if not hexBox:HasFocus() then
        hexBox:SetText(string.format("%02X%02X%02X",
            math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)))
    end

    if colorPopupApplyLive then colorPopupApplyLive(r, g, b) end
end

local function UpdateSVFromCursor()
    local scale = svSquare:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx, my = mx / scale, my / scale
    local left, top = svSquare:GetLeft(), svSquare:GetTop()
    colorState.s = math.min(math.max((mx - left) / SV_WIDTH, 0), 1)
    colorState.v = math.min(math.max(1 - (top - my) / SV_HEIGHT, 0), 1)
    RefreshColorPopup()
end

local function UpdateHueFromCursor()
    local scale = hueBar:GetEffectiveScale()
    local _, my = GetCursorPosition()
    my = my / scale
    local top = hueBar:GetTop()
    local pct = math.min(math.max((top - my) / SV_HEIGHT, 0), 1)
    colorState.h = math.min(pct * 360, 359.999)
    RefreshColorPopup()
end

-- OnUpdate attached only while the mouse button is actually held, same
-- reasoning as the scrollbar thumb above -- no per-frame work while idle.
svSquare:SetScript("OnMouseDown", function(self)
    UpdateSVFromCursor()
    self:SetScript("OnUpdate", UpdateSVFromCursor)
end)
svSquare:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
end)

hueBar:SetScript("OnMouseDown", function(self)
    UpdateHueFromCursor()
    self:SetScript("OnUpdate", UpdateHueFromCursor)
end)
hueBar:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
end)

hexBox:SetScript("OnEnterPressed", function(self)
    local num = tonumber((self:GetText():gsub("^#", "")), 16)
    if num then
        local r = math.floor(num / 65536) % 256
        local g = math.floor(num / 256) % 256
        local b = num % 256
        colorState.h, colorState.s, colorState.v = RGBtoHSV(r / 255, g / 255, b / 255)
        RefreshColorPopup()
    end
    self:ClearFocus()
end)
hexBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

prevSwatch:SetScript("OnClick", function()
    colorState.h, colorState.s, colorState.v = prevState.h, prevState.s, prevState.v
    RefreshColorPopup()
end)

cancelBtn:SetScript("OnClick", function()
    colorState.h, colorState.s, colorState.v = prevState.h, prevState.s, prevState.v
    RefreshColorPopup()
    colorPopup:Hide()
end)
okBtn:SetScript("OnClick", function() colorPopup:Hide() end)

local function OpenColorPopup(anchorFrame, title, r, g, b, applyLiveFn)
    colorPopupTitle:SetText(title)
    colorPopupApplyLive = nil -- don't fire the callback while we set the initial state below
    colorState.h, colorState.s, colorState.v = RGBtoHSV(r, g, b)
    prevState.h, prevState.s, prevState.v = colorState.h, colorState.s, colorState.v
    prevSwatch:SetBackdropColor(r, g, b, 1)
    RefreshColorPopup()
    colorPopupApplyLive = applyLiveFn

    colorPopup:ClearAllPoints()
    colorPopup:SetPoint("TOPLEFT", anchorFrame, "BOTTOMRIGHT", -260, -4)
    CloseAllMenus(colorPopup)
    colorPopup:Show()
end

--------------------------------------------------------------------------
-- Color swatch row: label left, clickable color box right. Opens the custom
-- color picker popup above, anchored under the swatch.
--------------------------------------------------------------------------
local function CreateColorSwatchRow(labelText, defaultR, defaultG, defaultB)
    currentY = currentY + 10
    local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING, -currentY)
    label:SetText(labelText)
    label:SetTextColor(unpack(C.text))

    local swatch = CreateFrame("Button", nil, content, "BackdropTemplate")
    swatch:SetSize(40, 18)
    swatch:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PADDING, -currentY + 1)
    swatch:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    swatch:SetBackdropBorderColor(unpack(C.border))

    local state = { r = defaultR, g = defaultG, b = defaultB }
    local function Refresh()
        swatch:SetBackdropColor(state.r, state.g, state.b, 1)
    end
    Refresh()

    swatch:SetScript("OnClick", function()
        OpenColorPopup(swatch, labelText, state.r, state.g, state.b, function(r, g, b)
            state.r, state.g, state.b = r, g, b
            Refresh()
        end)
    end)
    swatch:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    swatch:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)

    currentY = currentY + 22
    return {
        GetColor = function() return state.r, state.g, state.b end,
        SetColor = function(r, g, b)
            state.r, state.g, state.b = r or 0, g or 0, b or 0
            Refresh()
        end,
    }
end

--------------------------------------------------------------------------
-- Content: Display section
--------------------------------------------------------------------------
local displaySectionStart = currentY
AddSectionHeader("Display")

local maxSlider = CreateModernSlider("Max Loot Bars", 1, 10, 1, 5, function(v)
    return tostring(math.floor(v + 0.5))
end)

local durSlider = CreateModernSlider("Display Duration", 5, 60, 5, 15, function(v)
    return tostring(math.floor(v / 5 + 0.5) * 5) .. "s"
end)

local fontSlider = CreateModernSlider("Font Size", 8, 18, 1, 11, function(v)
    return tostring(math.floor(v + 0.5))
end)

local barScaleSlider = CreateModernSlider("Bar Scale", 0.8, 1.6, 0.05, 1, function(v)
    return string.format("%.2fx", v)
end)

local spacingSlider = CreateModernSlider("Bar Spacing", 0, 20, 1, 4, function(v)
    return tostring(math.floor(v + 0.5)) .. "px"
end)

AddCardPanel(displaySectionStart - 4, currentY - displaySectionStart + 4)

--------------------------------------------------------------------------
-- Content: Appearance section
--------------------------------------------------------------------------
currentY = currentY + 12
local appearanceSectionStart = currentY
AddSectionHeader("Appearance")

local textureDropdown = CreateModernDropdown("Bar Texture", {
    { text = "Blizzard", value = "Blizzard" },
    { text = "Flat",     value = "Flat" },
})

local growDropdown = CreateModernDropdown("Grow Direction", {
    { text = "Grow Down", value = false },
    { text = "Grow Up",   value = true },
})

AddCardPanel(appearanceSectionStart - 4, currentY - appearanceSectionStart + 4)

--------------------------------------------------------------------------
-- Content: Bar Style section (border width/color, background color/opacity)
--------------------------------------------------------------------------
currentY = currentY + 12
local barStyleSectionStart = currentY
AddSectionHeader("Bar Style")

local borderWidthSlider = CreateModernSlider("Border Width", 1, 6, 1, 1, function(v)
    return tostring(math.floor(v + 0.5)) .. "px"
end)

local borderColorSwatch = CreateColorSwatchRow("Border Color", 0.4, 0.4, 0.5)
local bgColorSwatch = CreateColorSwatchRow("Background Color", 0, 0, 0)

local bgOpacitySlider = CreateModernSlider("Background Opacity", 0, 100, 5, 85, function(v)
    return tostring(math.floor(v + 0.5)) .. "%"
end)

AddCardPanel(barStyleSectionStart - 4, currentY - barStyleSectionStart + 4)

--------------------------------------------------------------------------
-- Content: Displayed Qualities section (2-column checkbox grid)
--------------------------------------------------------------------------
currentY = currentY + 12
local qualitySectionStart = currentY
AddSectionHeader("Displayed Qualities")
currentY = currentY + 6

-- Poor isn't listed -- LootMirror only ever shows equipment, and Poor-quality
-- gear is never worth flagging, so it's hardcoded out rather than a toggle
-- (see ShouldFilterLoot in Core.lua).
local QUALITY_ORDER = { 1, 2, 3, 4, 5 }
local qualityCheckboxes = {}
local qualityColWidth = (CONTENT_WIDTH - PADDING * 2) / 2
for pos, q in ipairs(QUALITY_ORDER) do
    local col = (pos - 1) % 2
    local row = math.floor((pos - 1) / 2)
    local x = PADDING + col * qualityColWidth
    local y = currentY + row * 24
    qualityCheckboxes[q] = CreateQualityCheckbox(q, x, y)
end
currentY = currentY + 3 * 24 + 6

AddCardPanel(qualitySectionStart - 4, currentY - qualitySectionStart + 4)

currentY = currentY + 16

-- Finalize the scrollable content area now that its total height is known.
-- Add more sections above this line; everything below just needs `currentY`
-- to reflect the true bottom of the content.
content:SetHeight(currentY)
UpdateScrollbar()

--------------------------------------------------------------------------
-- Settings application
--------------------------------------------------------------------------
local function ApplySettings()
    LootMirrorDB = LootMirrorDB or {}
    LootMirrorDB.maxRows    = math.floor(maxSlider:GetValue() + 0.5)
    LootMirrorDB.duration   = math.floor(durSlider:GetValue() / 5 + 0.5) * 5
    LootMirrorDB.fontSize   = math.floor(fontSlider:GetValue() + 0.5)
    LootMirrorDB.barScale   = barScaleSlider:GetValue()
    LootMirrorDB.barSpacing = math.floor(spacingSlider:GetValue() + 0.5)
    LootMirrorDB.texture    = textureDropdown.GetValue() or "Blizzard"
    LootMirrorDB.growUp     = growDropdown.GetValue() and true or false

    LootMirrorDB.borderWidth = math.floor(borderWidthSlider:GetValue() + 0.5)
    LootMirrorDB.bgOpacity   = bgOpacitySlider:GetValue() / 100
    do
        local r, g, b = borderColorSwatch.GetColor()
        LootMirrorDB.borderColor = { r = r, g = g, b = b }
    end
    do
        local r, g, b = bgColorSwatch.GetColor()
        LootMirrorDB.bgColor = { r = r, g = g, b = b }
    end

    LootMirrorDB.filterQuality = LootMirrorDB.filterQuality or {}
    for _, q in ipairs(QUALITY_ORDER) do
        LootMirrorDB.filterQuality[q] = qualityCheckboxes[q].GetChecked()
    end

    if LootMirror.RefreshFontSize then LootMirror.RefreshFontSize() end
    if LootMirror.RefreshTexture then LootMirror.RefreshTexture() end
    -- Covers Bar Scale and Bar Spacing in one pass -- UpdateRowPositions
    -- (inside RefreshLayout) re-applies both to every row together.
    if LootMirror.RefreshLayout then LootMirror.RefreshLayout() end
end

--------------------------------------------------------------------------
-- Footer buttons: fixed at the bottom of optFrame, outside the scroll area.
--------------------------------------------------------------------------
-- Blends color c1 toward c2 by t (0-1); used for hover tints below instead of
-- swapping border color, since these buttons are borderless/flat now.
local function MixColor(c1, c2, t)
    return c1[1] + (c2[1] - c1[1]) * t,
           c1[2] + (c2[2] - c1[2]) * t,
           c1[3] + (c2[3] - c1[3]) * t
end

-- Secondary buttons (Move Anchor / Test) sit visibly above the window
-- background -- but well below Save's solid accent fill -- by brightening
-- C.control toward C.border (the same muted blue-green hue already used for
-- card/hairline edges throughout the panel), not toward plain white/gray.
local SECONDARY_BG = { MixColor(C.control, C.border, 0.5) }

local function CreateModernButton(width, text, isPrimary)
    local btn = CreateFrame("Button", nil, optFrame, "BackdropTemplate")
    btn:SetSize(width, 30)
    btn:SetBackdrop({ bgFile = WHITE })

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(text)

    if isPrimary then
        btn:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        label:SetTextColor(0.05, 0.05, 0.05)
        -- GameFontNormal's default shadow reads as a blurry double-edge when
        -- the text itself is near-black on a bright background; drop it here.
        label:SetShadowOffset(0, 0)
    else
        btn:SetBackdropColor(SECONDARY_BG[1], SECONDARY_BG[2], SECONDARY_BG[3], 1)
        label:SetTextColor(unpack(C.text))
    end

    btn:SetScript("OnEnter", function(self)
        if isPrimary then
            local r, g, b = MixColor(C.accent, { 1, 1, 1 }, 0.35)
            self:SetBackdropColor(r, g, b, 1)
        else
            local r, g, b = MixColor(SECONDARY_BG, C.border, 0.8)
            self:SetBackdropColor(r, g, b, 1)
            label:SetTextColor(1, 1, 1, 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if isPrimary then
            btn:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        else
            btn:SetBackdropColor(SECONDARY_BG[1], SECONDARY_BG[2], SECONDARY_BG[3], 1)
            label:SetTextColor(unpack(C.text))
        end
    end)
    return btn
end

local halfWidth = (WIDTH - PADDING * 2 - 10) / 2

local saveBtn = CreateModernButton(WIDTH - PADDING * 2, "Save", true)
saveBtn:SetPoint("BOTTOM", optFrame, "BOTTOM", 0, 14)
saveBtn:SetScript("OnClick", function()
    ApplySettings()
    optFrame:Hide()
    if LootMirror.MainFrame and LootMirror.MainFrame:IsShown() then
        LootMirror.MainFrame:Hide()
    end
end)

local moveBtn = CreateModernButton(halfWidth, "Move Anchor", false)
moveBtn:SetPoint("BOTTOMLEFT", saveBtn, "TOPLEFT", 0, 10)
moveBtn:SetScript("OnClick", function()
    if SlashCmdList and SlashCmdList["LOOTMIRROR"] then
        SlashCmdList["LOOTMIRROR"]("move")
    end
end)

local testBtn = CreateModernButton(halfWidth, "Test", false)
testBtn:SetPoint("BOTTOMLEFT", moveBtn, "BOTTOMRIGHT", 10, 0)
testBtn:SetScript("OnClick", function()
    ApplySettings()
    if LootMirror and LootMirror.RunTest then
        LootMirror.RunTest()
    end
end)

--------------------------------------------------------------------------
-- Show / position / slash commands
--------------------------------------------------------------------------
local function ApplyFramePosition()
    local db = LootMirrorDB or {}
    local point = db.optionsPoint or "CENTER"
    local relativePoint = db.optionsRelativePoint or point
    local x = db.optionsX or 0
    local y = db.optionsY or 0

    optFrame:ClearAllPoints()
    optFrame:SetPoint(point, UIParent, relativePoint, x, y)
end

optFrame:SetScript("OnShow", function()
    local db = LootMirrorDB or {}
    ApplyPanelScale(db.optionsScale or 1)
    panelScaleSlider:SetValue(db.optionsScale or 1)
    ApplyPanelOpacity(db.optionsOpacity or 0.95)
    panelOpacitySlider:SetValue(db.optionsOpacity or 0.95)
    maxSlider:SetValue(db.maxRows or 5)
    durSlider:SetValue(db.duration or 15)
    fontSlider:SetValue(db.fontSize or 11)
    barScaleSlider:SetValue(db.barScale or 1)
    spacingSlider:SetValue(db.barSpacing or 4)
    textureDropdown.SetValue(db.texture or "Blizzard")
    growDropdown.SetValue(db.growUp and true or false)

    borderWidthSlider:SetValue(db.borderWidth or 1)
    bgOpacitySlider:SetValue((db.bgOpacity or 0.85) * 100)
    local bc = db.borderColor or {}
    borderColorSwatch.SetColor(bc.r or 0.4, bc.g or 0.4, bc.b or 0.5)
    local bg = db.bgColor or {}
    bgColorSwatch.SetColor(bg.r or 0, bg.g or 0, bg.b or 0)

    local fq = db.filterQuality or {}
    for _, q in ipairs(QUALITY_ORDER) do
        qualityCheckboxes[q].SetChecked(fq[q] ~= false)
    end

    SetScrollPct(0)
end)

ApplyFramePosition()

LootMirror.Options = LootMirror.Options or {}
function LootMirror.Options.Toggle()
    if optFrame:IsShown() then
        optFrame:Hide()
    else
        optFrame:Show()
    end
end

SLASH_LOOTMIRROR1 = "/lm"
SLASH_LOOTMIRROR2 = "/lootmirror"

local function HandleLootMirrorSlash(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "move" then
        if LootMirror.MainFrame and LootMirror.MainFrame:IsShown() then
            LootMirror.MainFrame:Hide()
        elseif LootMirror.MainFrame then
            LootMirror.MainFrame:Show()
        end
        return
    end

    if msg == "test" then
        if LootMirror and LootMirror.RunTest then
            LootMirror.RunTest()
        end
        return
    end

    LootMirror.Options.Toggle()
end

SlashCmdList["LOOTMIRROR"] = HandleLootMirrorSlash

--------------------------------------------------------------------------
-- Game Menu -> Options -> AddOns entry. This is a separate, minimal canvas
-- (name/version/slash-command + an "Open Options" button) rather than
-- embedding optFrame itself -- optFrame is a free-floating, draggable,
-- custom-scrolled window sized to its own content, and stuffing that into
-- the Blizzard settings canvas (which controls its own size/scroll) would
-- fight it on both counts.
--------------------------------------------------------------------------
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = CreateFrame("Frame", "LootMirrorAddonCategory", UIParent)
    category.name = "LootMirror"

    local catTitle = category:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    catTitle:SetPoint("TOPLEFT", 16, -16)
    catTitle:SetText("LootMirror")

    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local version = (getMeta and getMeta("LootMirror", "Version")) or "?"
    local catVersion = category:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    catVersion:SetPoint("TOPLEFT", catTitle, "BOTTOMLEFT", 0, -8)
    catVersion:SetText("Version: " .. version)

    local catSlash = category:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    catSlash:SetPoint("TOPLEFT", catVersion, "BOTTOMLEFT", 0, -4)
    catSlash:SetText("Access options with |cffffd200/lm|r or |cffffd200/lootmirror|r")

    local openBtn = CreateFrame("Button", nil, category, "UIPanelButtonTemplate")
    openBtn:SetSize(160, 26)
    openBtn:SetPoint("TOPLEFT", catSlash, "BOTTOMLEFT", 0, -16)
    openBtn:SetText("Open Options")
    openBtn:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then
            SettingsPanel:Hide()
        end
        optFrame:Show()
    end)

    local settingsCategory = Settings.RegisterCanvasLayoutCategory(category, category.name)
    Settings.RegisterAddOnCategory(settingsCategory)
end
