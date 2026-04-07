-- Options.lua

local QUALITY_INFO = {
    { id = 0, label = "Poor"      },
    { id = 1, label = "Common"    },
    { id = 2, label = "Uncommon"  },
    { id = 3, label = "Rare"      },
    { id = 4, label = "Epic"      },
    { id = 5, label = "Legendary" },
}

local optFrame = CreateFrame("Frame", "LootMirrorOptionsFrame", UIParent, "BasicFrameTemplate")
optFrame:SetSize(300, 400)
optFrame:SetPoint("CENTER")
optFrame:SetMovable(true)
optFrame:EnableMouse(true)
optFrame:RegisterForDrag("LeftButton")
optFrame:SetScript("OnDragStart", optFrame.StartMoving)
optFrame:SetScript("OnDragStop",  optFrame.StopMovingOrSizing)
optFrame:SetFrameStrata("DIALOG")
optFrame:SetToplevel(true)
optFrame:Hide()

-- Title
local title = optFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOP", optFrame, "TOP", 0, -6)
title:SetText("LootMirror – Options")

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
maxLabel:SetPoint("TOPLEFT", optFrame, "TOPLEFT", 16, -42)
maxLabel:SetText("Maximum Loot Bars")

local maxValueLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
maxValueLabel:SetPoint("TOPRIGHT", optFrame, "TOPRIGHT", -16, -42)

local maxSlider = CreateFrame("Slider", "LootMirrorMaxSlider", optFrame, "OptionsSliderTemplate")
maxSlider:SetPoint("TOPLEFT",  maxLabel, "BOTTOMLEFT",   8, -14)
maxSlider:SetPoint("TOPRIGHT", optFrame, "TOPRIGHT",   -24, -56)
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

-- ── Grow Direction (Radio Buttons) ────────────────────────────────────────────
local dirLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dirLabel:SetPoint("TOPLEFT", durSlider, "BOTTOMLEFT", -8, -26)
dirLabel:SetText("Grow Direction")

local radioDown = CreateFrame("CheckButton", "LootMirrorRadioDown", optFrame, "UIRadioButtonTemplate")
radioDown:SetPoint("TOPLEFT", dirLabel, "BOTTOMLEFT", 0, -6)
radioDown.text:SetText("Grow downward")
radioDown.text:SetFontObject("GameFontNormalSmall")

local radioUp = CreateFrame("CheckButton", "LootMirrorRadioUp", optFrame, "UIRadioButtonTemplate")
radioUp:SetPoint("TOPLEFT", radioDown, "BOTTOMLEFT", 0, -4)
radioUp.text:SetText("Grow upward")
radioUp.text:SetFontObject("GameFontNormalSmall")

radioDown:SetScript("OnClick", function(self) self:SetChecked(true); radioUp:SetChecked(false) end)
radioUp:SetScript("OnClick",   function(self) self:SetChecked(true); radioDown:SetChecked(false) end)

Divider(radioUp)

-- ── Item Quality Filter ───────────────────────────────────────────────────────
local qualLabel = optFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
qualLabel:SetPoint("TOPLEFT", radioUp, "BOTTOMLEFT", 0, -26)
qualLabel:SetText("Displayed Qualities")

-- 6 checkboxes in 3 columns x 2 rows
local qualChecks = {}
local COL_W = 88
local ROW_H = 26

for idx, info in ipairs(QUALITY_INFO) do
    local col = (idx - 1) % 3
    local row = math.floor((idx - 1) / 3)

    local cb = CreateFrame("CheckButton", nil, optFrame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", qualLabel, "BOTTOMLEFT", col * COL_W, -(row * ROW_H) - 6)

    local r, g, b = GetItemQualityColor(info.id)
    cb.text:SetText(string.format("|cff%02x%02x%02x%s|r",
        math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), info.label))
    cb.text:SetFontObject("GameFontNormalSmall")

    qualChecks[info.id] = cb
end

-- ── Save Button ───────────────────────────────────────────────────────────────
local saveBtn = CreateFrame("Button", nil, optFrame, "GameMenuButtonTemplate")
saveBtn:SetSize(140, 28)
saveBtn:SetPoint("BOTTOM", optFrame, "BOTTOM", 0, 14)
saveBtn:SetText("Save & Close")
saveBtn:SetScript("OnClick", function()
    LootMirrorDB.maxRows  = math.floor(maxSlider:GetValue() + 0.5)
    LootMirrorDB.duration = math.floor(durSlider:GetValue() / 5 + 0.5) * 5
    LootMirrorDB.growUp   = radioUp:GetChecked() and true or false
    for id, cb in pairs(qualChecks) do
        LootMirrorDB.filterQuality[id] = cb:GetChecked() and true or false
    end
    optFrame:Hide()
end)

-- Load values from DB when frame is opened
optFrame:SetScript("OnShow", function()
    local db = LootMirrorDB or {}
    maxSlider:SetValue(db.maxRows or 5)
    durSlider:SetValue(db.duration or 15)
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

-- Public API
LootMirror.Options = {}
function LootMirror.Options.Toggle()
    if optFrame:IsShown() then
        optFrame:Hide()
    else
        optFrame:Show()
    end
end
