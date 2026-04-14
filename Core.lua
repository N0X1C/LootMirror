local activeRows   = {}
local pendingItems = {} -- itemID -> { {row, count, itemLink}, ... }
local classCache   = {} -- player name -> RAID_CLASS_COLORS entry

-- Safely extract a string value, skipping tainted values via issecretvalue()
local hasIsSecretValue = type(issecretvalue) == "function"
local function SafeString(value)
    if type(value) ~= "string" then return nil end
    if hasIsSecretValue and issecretvalue(value) then return nil end
    return value
end

-- Populate class color cache from current group (including self)
local function RefreshClassCache()
    -- Always cache the player's own class
    local selfName = UnitName("player")
    local _, selfToken = UnitClass("player")
    if selfName and selfToken and RAID_CLASS_COLORS[selfToken] then
        classCache[selfName] = RAID_CLASS_COLORS[selfToken]
    end

    local inRaid = IsInRaid()
    local count  = GetNumGroupMembers()
    local prefix = inRaid and "raid" or "party"
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) then
            local name = UnitName(unit)
            local _, token = UnitClass(unit)
            if name and token and RAID_CLASS_COLORS[token] then
                classCache[name] = RAID_CLASS_COLORS[token]
            end
        end
    end
end

local function GetClassColor(name)
    local shortName = name:match("^([^%-]+)") or name
    local c = classCache[name] or classCache[shortName]
    if not c then
        -- Live lookup: only iterate the units actually present
        local inRaid = IsInRaid()
        local count  = GetNumGroupMembers()
        local prefix = inRaid and "raid" or "party"
        for i = 1, count do
            local unit = prefix .. i
            if UnitExists(unit) then
                local uName = UnitName(unit)
                if uName == shortName or uName == name then
                    local _, token = UnitClass(unit)
                    if token and RAID_CLASS_COLORS[token] then
                        c = RAID_CLASS_COLORS[token]
                        classCache[shortName] = c
                        break
                    end
                end
            end
        end
    end
    return c and c.r or 1, c and c.g or 1, c and c.b or 1
end

-- Build locale-independent patterns from GlobalStrings
local function MakePattern(str)
    return str
        :gsub("([%(%)%.%+%-%*%?%[%^%$%%])", "%%%1")
        :gsub("%%%%s", "(.+)")
        :gsub("%%%%d", "(%%d+)")
end

local LOOT_ITEM_PATTERN            = MakePattern(LOOT_ITEM)
local LOOT_ITEM_MULTI_PATTERN      = LOOT_ITEM_MULTIPLE and MakePattern(LOOT_ITEM_MULTIPLE)
local LOOT_ITEM_SELF_PATTERN       = LOOT_ITEM_SELF and MakePattern(LOOT_ITEM_SELF)
local LOOT_ITEM_SELF_MULTI_PATTERN = LOOT_ITEM_SELF_MULTIPLE and MakePattern(LOOT_ITEM_SELF_MULTIPLE)

LootMirror.SavePosition = function()
    local f = LootMirror.MainFrame
    local point, _, _, x, y = f:GetPoint()
    LootMirrorDB = LootMirrorDB or {}
    LootMirrorDB.point = point
    LootMirrorDB.x     = x
    LootMirrorDB.y     = y
end

function LootMirror.ClearFeed()
    for i = #activeRows, 1, -1 do
        LootMirror.ReleaseRow(activeRows[i])
        activeRows[i] = nil
    end
end

function LootMirror.RefreshFontSize()
    local size = (LootMirrorDB and LootMirrorDB.fontSize) or 11
    for _, row in ipairs(activeRows) do
        LootMirror.ApplyFontSizeToRow(row, size)
    end
end

function LootMirror.RefreshTexture()
    local texture = (LootMirrorDB and LootMirrorDB.texture) or "tooltip"
    for _, row in ipairs(activeRows) do
        LootMirror.ApplyTextureToRow(row, texture)
    end
end

local function UpdateRowPositions()
    local growUp = LootMirrorDB and LootMirrorDB.growUp
    for i, row in ipairs(activeRows) do
        row:ClearAllPoints()
        if growUp then
            row:SetPoint("BOTTOM", LootMirror.MainFrame, "TOP", 0, (i - 1) * 56)
        else
            row:SetPoint("TOP", LootMirror.MainFrame, "BOTTOM", 0, -(i - 1) * 56)
        end
    end
end

local function IsFiltered(quality)
    local fq = LootMirrorDB and LootMirrorDB.filterQuality
    return fq and fq[quality or 1] == false
end

-- Applies item data to a row; accepts pre-fetched data or fetches it on demand.
-- Returns the quality on success, false if not cached yet.
local function ApplyItemData(row, itemLink, count, itemName, quality, itemTexture)
    if not itemName then
        itemName, _, quality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemLink)
    end
    if not itemName then return false end

    local r, g, b = GetItemQualityColor(quality or 1)
    row.IconBorder:SetBackdropBorderColor(r, g, b, 1)
    row.Icon:SetTexture(itemTexture)
    row.ItemText:SetText("|c" .. string.format("ff%02x%02x%02x", math.floor(r*255), math.floor(g*255), math.floor(b*255)) .. itemName .. "|r")
    row.Count:SetText((count and count > 1) and tostring(count) or "")
    return quality
end

local function DisplayLoot(player, itemLink, count)
    -- Single GetItemInfo call: used for filter check and row population
    local itemName, _, quality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemLink)
    if quality and IsFiltered(quality) then return end

    local itemID = tonumber(itemLink:match("|Hitem:(%d+)"))

    local row = LootMirror.AcquireRow()
    row.itemLink   = itemLink
    row.playerName = player

    -- Player name in class color
    local pr, pg, pb = GetClassColor(player)
    row.PlayerText:SetText("|c" .. string.format("ff%02x%02x%02x", math.floor(pr*255), math.floor(pg*255), math.floor(pb*255)) .. (player:match("^([^%-]+)") or player) .. "|r")

    -- Placeholder until item data is loaded
    row.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.IconBorder:SetBackdropBorderColor(1, 1, 1, 0.4)
    row.ItemText:SetText("|cffaaaaaaLoading...|r")
    row.Count:SetText("")

    -- Pass pre-fetched data; only queue if still not cached
    if not ApplyItemData(row, itemLink, count, itemName, quality, itemTexture) and itemID then
        if not pendingItems[itemID] then pendingItems[itemID] = {} end
        table.insert(pendingItems[itemID], { row = row, count = count, itemLink = itemLink })
    end

    table.insert(activeRows, 1, row)
    local maxRows = LootMirrorDB and LootMirrorDB.maxRows or 5
    if #activeRows > maxRows then
        LootMirror.ReleaseRow(table.remove(activeRows))
    end

    UpdateRowPositions()
    row:Show()

    C_Timer.After(LootMirrorDB and LootMirrorDB.duration or 15, function()
        for i, activeRow in ipairs(activeRows) do
            if activeRow == row then
                table.remove(activeRows, i)
                LootMirror.ReleaseRow(row)
                UpdateRowPositions()
                break
            end
        end
        -- Clean up pending entry
        if itemID then
            local pending = pendingItems[itemID]
            if pending then
                for i, entry in ipairs(pending) do
                    if entry.row == row then
                        table.remove(pending, i)
                        break
                    end
                end
                if #pending == 0 then pendingItems[itemID] = nil end
            end
        end
    end)
end

local core = CreateFrame("Frame")
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("CHAT_MSG_LOOT")
core:RegisterEvent("GET_ITEM_INFO_RECEIVED")
core:RegisterEvent("GROUP_ROSTER_UPDATE")

core:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "LootMirror" then
            self:UnregisterEvent("ADDON_LOADED")
            LootMirrorDB = LootMirrorDB or {}
            LootMirrorDB.point    = LootMirrorDB.point    or "TOP"
            LootMirrorDB.x        = LootMirrorDB.x        or 0
            LootMirrorDB.y        = LootMirrorDB.y        or -100
            LootMirrorDB.maxRows  = LootMirrorDB.maxRows  or 5
            LootMirrorDB.growUp   = LootMirrorDB.growUp   or false
            LootMirrorDB.duration = LootMirrorDB.duration or 15
            LootMirrorDB.fontSize = LootMirrorDB.fontSize or 11
            LootMirrorDB.texture  = LootMirrorDB.texture  or "Blizzard Tooltip"
            if not LootMirrorDB.filterQuality then
                LootMirrorDB.filterQuality = { [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true }
            end
            LootMirror.MainFrame:ClearAllPoints()
            LootMirror.MainFrame:SetPoint(LootMirrorDB.point, UIParent, LootMirrorDB.point, LootMirrorDB.x, LootMirrorDB.y)
            RefreshClassCache()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        RefreshClassCache()

    elseif event == "CHAT_MSG_LOOT" then
        local msg = SafeString(...)
        if not msg then return end
        -- Own loot (multi)
        if LOOT_ITEM_SELF_MULTI_PATTERN then
            local link, n = strmatch(msg, LOOT_ITEM_SELF_MULTI_PATTERN)
            if link then
                DisplayLoot(UnitName("player"), link, tonumber(n))
                return
            end
        end
        -- Own loot (single)
        if LOOT_ITEM_SELF_PATTERN then
            local link = strmatch(msg, LOOT_ITEM_SELF_PATTERN)
            if link then
                DisplayLoot(UnitName("player"), link, nil)
                return
            end
        end
        -- Group/raid loot (multi)
        if LOOT_ITEM_MULTI_PATTERN then
            local p, link, n = strmatch(msg, LOOT_ITEM_MULTI_PATTERN)
            if p and link then
                DisplayLoot(p, link, tonumber(n))
                return
            end
        end
        -- Group/raid loot (single)
        local p, link = strmatch(msg, LOOT_ITEM_PATTERN)
        if p and link then
            DisplayLoot(p, link, nil)
        end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if not success then return end
        local entries = pendingItems[itemID]
        if not entries then return end
        for _, entry in ipairs(entries) do
            local quality = ApplyItemData(entry.row, entry.itemLink, entry.count)
            if quality and IsFiltered(quality) then
                -- Quality is filtered out: remove the row
                for i, r in ipairs(activeRows) do
                    if r == entry.row then
                        table.remove(activeRows, i)
                        break
                    end
                end
                LootMirror.ReleaseRow(entry.row)
                UpdateRowPositions()
            end
        end
        pendingItems[itemID] = nil
    end
end)

SLASH_LOOTMIRROR1 = "/lm"
SlashCmdList["LOOTMIRROR"] = function(msg)
    if msg == "move" then
        if LootMirror.MainFrame:IsShown() then
            LootMirror.MainFrame:Hide()
        else
            LootMirror.MainFrame:Show()
        end

    elseif msg == "test" then
        local pool = {
            { p = "Sylvanas",  class = "HUNTER",      i = "|cffa335ee|Hitem:18803::::::::70:::::|h[Ashbringer]|h|r" },
            { p = "Arthas",    class = "DEATHKNIGHT",  i = "|cffff8000|Hitem:20928::::::::70:::::|h[Death's Sting]|h|r" },
            { p = "Anduin",    class = "PRIEST",       i = "|cffa335ee|Hitem:9449::::::::70:::::|h[Cord of the Earth]|h|r", c = 3 },
            { p = "Thrall",    class = "SHAMAN",       i = "|cff0070dd|Hitem:17182::::::::70:::::|h[Sulfuras]|h|r" },
            { p = "Jaina",     class = "MAGE",         i = "|cffa335ee|Hitem:19019::::::::70:::::|h[Atiesh]|h|r" },
            { p = "Varian",    class = "WARRIOR",      i = "|cff0070dd|Hitem:11815::::::::70:::::|h[Frostblade]|h|r" },
            { p = "Malfurion", class = "DRUID",        i = "|cffa335ee|Hitem:21178::::::::70:::::|h[Staff of Nature]|h|r" },
            { p = "Illidan",   class = "DEMONHUNTER",  i = "|cffff8000|Hitem:32837::::::::70:::::|h[Warglaive]|h|r" },
            { p = "Garrosh",   class = "WARRIOR",      i = "|cffa335ee|Hitem:12797::::::::70:::::|h[Gorehowl]|h|r" },
            { p = "Tyrande",   class = "PRIEST",       i = "|cff1eff00|Hitem:18814::::::::70:::::|h[Benediction]|h|r" },
        }
        local count = LootMirrorDB and LootMirrorDB.maxRows or 5
        for _, v in ipairs(pool) do
            if RAID_CLASS_COLORS[v.class] then
                classCache[v.p] = RAID_CLASS_COLORS[v.class]
            end
        end
        for k = 1, count do
            local v = pool[k]
            C_Timer.After(k * 0.5, function() DisplayLoot(v.p, v.i, v.c) end)
        end

    else
        -- No or unknown argument: open options
        if LootMirror.Options.Toggle then
            LootMirror.Options.Toggle()
        end
    end
end
