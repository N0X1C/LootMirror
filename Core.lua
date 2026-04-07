local activeRows   = {}
local pendingItems = {} -- itemLink -> { row, ... } for items not yet cached
local classCache   = {} -- player name -> RAID_CLASS_COLORS entry

-- Populate class color cache from current group
local function RefreshClassCache()
    local function CacheUnit(unit)
        if not UnitExists(unit) then return end
        local name = UnitName(unit)
        local _, token = UnitClass(unit)
        if name and token and RAID_CLASS_COLORS[token] then
            classCache[name] = RAID_CLASS_COLORS[token]
        end
    end
    for i = 1, 40 do CacheUnit("raid"  .. i) end
    for i = 1, 4  do CacheUnit("party" .. i) end
end

local function GetClassColor(name)
    local shortName = name:match("^([^%-]+)") or name
    local c = classCache[name] or classCache[shortName]
    if not c then
        -- Live lookup: search player directly in current group
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) and UnitName(unit) == shortName then
                local _, token = UnitClass(unit)
                if token and RAID_CLASS_COLORS[token] then
                    c = RAID_CLASS_COLORS[token]
                    classCache[shortName] = c
                    break
                end
            end
        end
        if not c then
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists(unit) and UnitName(unit) == shortName then
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

-- Group/raid loot only (own loot is handled by the default WoW UI)
local LOOT_ITEM_PATTERN       = MakePattern(LOOT_ITEM)
local LOOT_ITEM_MULTI_PATTERN = LOOT_ITEM_MULTIPLE and MakePattern(LOOT_ITEM_MULTIPLE)

LootMirror.SavePosition = function()
    local f = LootMirror.MainFrame
    local point, _, _, x, y = f:GetPoint()
    LootMirrorDB = LootMirrorDB or {}
    LootMirrorDB.point = point
    LootMirrorDB.x     = x
    LootMirrorDB.y     = y
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

-- Applies item data to a row; returns the quality on success, false if not cached yet
local function ApplyItemData(row, itemLink, count)
    local itemName, _, quality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemLink)
    if not itemName then return false end

    local r, g, b = GetItemQualityColor(quality or 1)
    row.IconBorder:SetBackdropBorderColor(r, g, b, 1)
    row.Icon:SetTexture(itemTexture)
    row.ItemText:SetText("|c" .. string.format("ff%02x%02x%02x", math.floor(r*255), math.floor(g*255), math.floor(b*255)) .. itemName .. "|r")
    row.Count:SetText((count and count > 1) and tostring(count) or "")
    return quality
end

local function DisplayLoot(player, itemLink, count)
    -- If item is already cached, check filter immediately
    local _, _, quality = C_Item.GetItemInfo(itemLink)
    if quality and IsFiltered(quality) then return end

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

    if not ApplyItemData(row, itemLink, count) then
        -- Not cached yet: queue for GET_ITEM_INFO_RECEIVED, filter checked on arrival
        if not pendingItems[itemLink] then pendingItems[itemLink] = {} end
        table.insert(pendingItems[itemLink], { row = row, count = count })
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
        local pending = pendingItems[itemLink]
        if pending then
            for i, entry in ipairs(pending) do
                if entry.row == row then
                    table.remove(pending, i)
                    break
                end
            end
            if #pending == 0 then pendingItems[itemLink] = nil end
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
            LootMirrorDB = LootMirrorDB or {}
            LootMirrorDB.point    = LootMirrorDB.point    or "TOP"
            LootMirrorDB.x        = LootMirrorDB.x        or 0
            LootMirrorDB.y        = LootMirrorDB.y        or -100
            LootMirrorDB.maxRows  = LootMirrorDB.maxRows  or 5
            LootMirrorDB.growUp   = LootMirrorDB.growUp   or false
            LootMirrorDB.duration = LootMirrorDB.duration or 15
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
        local msg = ...
        if type(msg) ~= "string" then return end
        -- pcall guards against tainted string values that pass the type check
        -- but fail at the C level inside strmatch
        if LOOT_ITEM_MULTI_PATTERN then
            local ok, p, link, n = pcall(strmatch, msg, LOOT_ITEM_MULTI_PATTERN)
            if ok and p and link then
                DisplayLoot(p, link, tonumber(n))
                return
            end
        end
        local ok, p, link = pcall(strmatch, msg, LOOT_ITEM_PATTERN)
        if ok and p and link then
            DisplayLoot(p, link, nil)
        end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if not success then return end
        local toRemove
        for itemLink, entries in pairs(pendingItems) do
            local linkID = tonumber(itemLink:match("|Hitem:(%d+)"))
            if linkID == itemID then
                for _, entry in ipairs(entries) do
                    local quality = ApplyItemData(entry.row, itemLink, entry.count)
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
                toRemove = itemLink
                break
            end
        end
        if toRemove then pendingItems[toRemove] = nil end
    end
end)

SLASH_LOOTMIRROR1 = "/lm"
SlashCmdList["LOOTMIRROR"] = function(msg)
    if msg == "move" then
        if LootMirror.MainFrame:IsShown() then
            LootMirror.MainFrame:Hide()
            print("LootMirror: Anchor hidden.")
        else
            LootMirror.MainFrame:Show()
            print("LootMirror: Anchor visible – drag the bar to reposition, then /lm move to hide.")
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
