-- Options.lua

local QUALITY_INFO = {
    { id = 0, label = "Poor"      },
    { id = 1, label = "Common"    },
    { id = 2, label = "Uncommon"  },
    { id = 3, label = "Rare"      },
    { id = 4, label = "Epic"      },
    { id = 5, label = "Legendary" },
}

local optFrame = CreateFrame("Frame", "LootMirrorOptionsFrame", UIParent)
optFrame:SetSize(400, 570)

local function Divider(anchorFrame, yOffset)
    local d = optFrame:CreateTexture(nil, "ARTWORK")
    d:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    d:SetHeight(1)
    d:SetPoint("TOPLEFT",  anchorFrame, "BOTTOMLEFT",  -4, yOffset or -10)
    d:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT",  4, yOffset or -10)
    return d
end

-- ── Max Bars ─────────────────────────────────────────────────────────────────
local maxLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
maxLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 16, -16)
maxLabel:SetText("Maximum Loot Bars")

local maxValueLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
maxValueLabel:SetPoint("TOPRIGHT", optFrame, "TOPRIGHT", -16, -16)

local maxSlider = CreateFrame("Slider", "LootMirrorMaxSlider", optFrame, "OptionsSliderTemplate")
maxSlider:SetPoint("TOPLEFT",  maxLabel, "BOTTOMLEFT",   8, -14)
maxSlider:SetPoint("TOPRIGHT", optFrame, "TOPRIGHT",   -24, -30)
maxSlider:SetMinMaxValues(1, 10)
maxSlider:SetValueStep(1)
maxSlider:SetObeyStepOnDrag(true)
maxSlider.Low:SetText("1")
maxSlider.High:SetText("10")
local maxSliderText = _G[maxSlider:GetName() .. "Text"]
if maxSliderText then maxSliderText:SetText("") end
maxSlider:SetScript("OnValueChanged", function(self, val)
    maxValueLabel:SetText(math.floor(val + 0.5))
    if maxSliderText then maxSliderText:SetText("") end
end)

Divider(maxSlider)

-- ── Display Duration ──────────────────────────────────────────────────────────
local durLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
durLabel:SetPoint("TOPLEFT", maxSlider, "BOTTOMLEFT", -8, -26)
durLabel:SetText("Display Duration")

local durValueLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
durValueLabel:SetPoint("TOP",      durLabel, "TOP")
durValueLabel:SetPoint("TOPRIGHT", optFrame, "TOPRIGHT", -16, 0)

local durSlider = CreateFrame("Slider", "LootMirrorDurSlider", optFrame, "OptionsSliderTemplate")
durSlider:SetPoint("TOPLEFT",  durLabel, "BOTTOMLEFT",   8, -14)
durSlider:SetPoint("TOPRIGHT", optFrame, "TOPRIGHT",   -24, 0)
durSlider:SetPoint("TOP",      durLabel, "BOTTOM",        0, -14)
durSlider:SetMinMaxValues(5, 60)
durSlider:SetValueStep(5)
durSlider:SetObeyStepOnDrag(true)
durSlider.Low:SetText("5s")
durSlider.High:SetText("60s")
local durSliderText = _G[durSlider:GetName() .. "Text"]
if durSliderText then durSliderText:SetText("") end
durSlider:SetScript("OnValueChanged", function(self, val)
    local v = math.floor(val / 5 + 0.5) * 5
    durValueLabel:SetText(v .. "s")
    if durSliderText then durSliderText:SetText("") end
end)

Divider(durSlider)

-- ── Font Size ─────────────────────────────────────────────────────────────────
local fontLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fontLabel:SetPoint("TOPLEFT", durSlider, "BOTTOMLEFT", -8, -26)
fontLabel:SetText("Font Size")

local fontValueLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
fontValueLabel:SetPoint("TOP",      fontLabel, "TOP")
fontValueLabel:SetPoint("TOPRIGHT", optFrame,  "TOPRIGHT", -16, 0)

local fontSlider = CreateFrame("Slider", "LootMirrorFontSlider", optFrame, "OptionsSliderTemplate")
fontSlider:SetPoint("TOPLEFT",  fontLabel, "BOTTOMLEFT",   8, -14)
fontSlider:SetPoint("TOPRIGHT", optFrame,  "TOPRIGHT",   -24, 0)
fontSlider:SetPoint("TOP",      fontLabel, "BOTTOM",        0, -14)
fontSlider:SetMinMaxValues(8, 18)
fontSlider:SetValueStep(1)
fontSlider:SetObeyStepOnDrag(true)
fontSlider.Low:SetText("8")
fontSlider.High:SetText("18")
local fontSliderText = _G[fontSlider:GetName() .. "Text"]
if fontSliderText then fontSliderText:SetText("") end
fontSlider:SetScript("OnValueChanged", function(self, val)
    local v = math.floor(val + 0.5)
    fontValueLabel:SetText(v)
    if fontSliderText then fontSliderText:SetText("") end
end)

Divider(fontSlider)

-- ── Bar Texture ───────────────────────────────────────────────────────────────
local textureLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
textureLabel:SetPoint("TOPLEFT", fontSlider, "BOTTOMLEFT", -8, -26)
textureLabel:SetText("Bar Texture")

local radioTooltip = CreateFrame("CheckButton", "LootMirrorRadioTooltip", optFrame, "UIRadioButtonTemplate")
radioTooltip:SetPoint("TOPLEFT", textureLabel, "BOTTOMLEFT", 0, -6)
radioTooltip.text:SetText("Blizzard")
radioTooltip.text:SetFontObject("GameFontNormal")

local radioFlat = CreateFrame("CheckButton", "LootMirrorRadioFlat", optFrame, "UIRadioButtonTemplate")
radioFlat:SetPoint("TOPLEFT", radioTooltip, "BOTTOMLEFT", 0, -4)
radioFlat.text:SetText("Flat")
radioFlat.text:SetFontObject("GameFontNormal")

radioTooltip:SetScript("OnClick", function(self) self:SetChecked(true); radioFlat:SetChecked(false) end)
radioFlat:SetScript("OnClick",    function(self) self:SetChecked(true); radioTooltip:SetChecked(false) end)

Divider(radioFlat)

-- ── Grow Direction (Radio Buttons) ────────────────────────────────────────────
local dirLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dirLabel:SetPoint("TOPLEFT", radioFlat, "BOTTOMLEFT", 0, -16)
dirLabel:SetText("Grow Direction")

local radioUp = CreateFrame("CheckButton", "LootMirrorRadioUp", optFrame, "UIRadioButtonTemplate")
radioUp:SetPoint("TOPLEFT", dirLabel, "BOTTOMLEFT", 0, -6)
radioUp.text:SetText("Grow upward")
radioUp.text:SetFontObject("GameFontNormal")

local radioDown = CreateFrame("CheckButton", "LootMirrorRadioDown", optFrame, "UIRadioButtonTemplate")
radioDown:SetPoint("TOPLEFT", radioUp, "BOTTOMLEFT", 0, -4)
radioDown.text:SetText("Grow downward")
radioDown.text:SetFontObject("GameFontNormal")

radioUp:SetScript("OnClick",   function(self) self:SetChecked(true); radioDown:SetChecked(false) end)
radioDown:SetScript("OnClick", function(self) self:SetChecked(true); radioUp:SetChecked(false) end)

Divider(radioDown)

-- ── Item Quality Filter ───────────────────────────────────────────────────────
local qualLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
qualLabel:SetPoint("TOPLEFT", radioDown, "BOTTOMLEFT", 0, -26)
qualLabel:SetText("Displayed Qualities")

local qualChecks = {}
local COL_W = 88
local ROW_H = 26
local lastQualCheck

for idx, info in ipairs(QUALITY_INFO) do
    local col = (idx - 1) % 3
    local row = math.floor((idx - 1) / 3)

    local cb = CreateFrame("CheckButton", nil, optFrame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", qualLabel, "BOTTOMLEFT", col * COL_W, -(row * ROW_H) - 6)

    local r, g, b = GetItemQualityColor(info.id)
    cb.text:SetText(string.format("|cff%02x%02x%02x%s|r",
        math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), info.label))
    cb.text:SetFontObject("GameFontNormal")

    qualChecks[info.id] = cb
    if col == 0 then lastQualCheck = cb end
end

-- ── Shared apply logic ────────────────────────────────────────────────────────
local function ApplySettings()
    LootMirrorDB.maxRows  = math.floor(maxSlider:GetValue() + 0.5)
    LootMirrorDB.duration = math.floor(durSlider:GetValue() / 5 + 0.5) * 5
    LootMirrorDB.fontSize = math.floor(fontSlider:GetValue() + 0.5)
    LootMirrorDB.texture  = radioFlat:GetChecked() and "Flat" or "Blizzard"
    LootMirrorDB.growUp   = radioUp:GetChecked() and true or false
    for id, cb in pairs(qualChecks) do
        LootMirrorDB.filterQuality[id] = cb:GetChecked() and true or false
    end
    LootMirror.RefreshFontSize()
    LootMirror.RefreshTexture()
end

-- ── Buttons ───────────────────────────────────────────────────────────────────
local btnDivider = optFrame:CreateTexture(nil, "ARTWORK")
btnDivider:SetColorTexture(0.4, 0.4, 0.4, 0.6)
btnDivider:SetHeight(1)
btnDivider:SetPoint("TOPLEFT",  lastQualCheck, "BOTTOMLEFT",  -4, -12)
btnDivider:SetPoint("TOPRIGHT", optFrame,      "TOPRIGHT",    -12,  0)
btnDivider:SetPoint("TOP",      lastQualCheck, "BOTTOM",       0,  -12)

local moveBtn = CreateFrame("Button", nil, optFrame, "GameMenuButtonTemplate")
moveBtn:SetSize(120, 28)
moveBtn:SetPoint("RIGHT", optFrame, "CENTER", -4, 0)
moveBtn:SetPoint("TOP",   lastQualCheck, "BOTTOM", 0, -36)
moveBtn:SetText("Move Anchor")
moveBtn:SetScript("OnClick", function()
    SlashCmdList["LOOTMIRROR"]("move")
end)

local testBtn = CreateFrame("Button", nil, optFrame, "GameMenuButtonTemplate")
testBtn:SetSize(120, 28)
testBtn:SetPoint("LEFT", optFrame, "CENTER", 4, 0)
testBtn:SetPoint("TOP",  lastQualCheck, "BOTTOM", 0, -36)
testBtn:SetText("Test")
testBtn:SetScript("OnClick", function()
    ApplySettings()
    SlashCmdList["LOOTMIRROR"]("test")
end)

local saveBtn = CreateFrame("Button", nil, optFrame, "GameMenuButtonTemplate")
saveBtn:SetPoint("TOPLEFT",  moveBtn, "BOTTOMLEFT",  0, -8)
saveBtn:SetPoint("TOPRIGHT", testBtn, "BOTTOMRIGHT", 0, -8)
saveBtn:SetHeight(28)
saveBtn:SetText("Save")
saveBtn:SetScript("OnClick", function()
    ApplySettings()
end)

-- Load values from DB when panel is shown
optFrame:SetScript("OnShow", function()
    local db = LootMirrorDB or {}
    maxSlider:SetValue(db.maxRows or 5)
    durSlider:SetValue(db.duration or 15)
    fontSlider:SetValue(db.fontSize or 11)
    if db.texture == "Flat" then
        radioFlat:SetChecked(true);    radioTooltip:SetChecked(false)
    else
        radioTooltip:SetChecked(true); radioFlat:SetChecked(false)
    end
    if db.growUp then
        radioUp:SetChecked(true);  radioDown:SetChecked(false)
    else
        radioDown:SetChecked(true); radioUp:SetChecked(false)
    end
    local fq = db.filterQuality or {}
    for id, cb in pairs(qualChecks) do
        cb:SetChecked(fq[id] ~= false)
    end
end)

-- ── Register in Game Menu → Options → Addons ─────────────────────────────────
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(optFrame, "LootMirror")
    Settings.RegisterAddOnCategory(category)
    LootMirror.optionsCategoryID = category:GetID()
end

-- Public API
LootMirror.Options = {}
function LootMirror.Options.Toggle()
    if LootMirror.optionsCategoryID then
        Settings.OpenToCategory(LootMirror.optionsCategoryID)
    else
        if optFrame:IsShown() then
            optFrame:Hide()
        else
            optFrame:Show()
        end
    end
end
