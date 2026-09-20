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

-- Build locale-independent patterns from GlobalStrings.
-- Guarded against a missing/renamed GlobalString: a nil value here must never
-- throw, since a top-level error would abort the rest of this file (event
-- registration, DisplayLoot, RunTest -- everything below this point).
local function MakePattern(str)
    if type(str) ~= "string" then return nil end
    return str
        :gsub("([%(%)%.%+%-%*%?%[%^%$%%])", "%%%1")
        :gsub("%%%%s", "(.+)")
        :gsub("%%%%d", "(%%d+)")
end

local LOOT_ITEM_PATTERN            = MakePattern(LOOT_ITEM)
local LOOT_ITEM_MULTI_PATTERN      = MakePattern(LOOT_ITEM_MULTIPLE)
local LOOT_ITEM_SELF_PATTERN       = MakePattern(LOOT_ITEM_SELF)
local LOOT_ITEM_SELF_MULTI_PATTERN = MakePattern(LOOT_ITEM_SELF_MULTIPLE)

if not LOOT_ITEM_PATTERN then
    print("|cffff0000LootMirror:|r Could not build the loot-message pattern (LOOT_ITEM GlobalString missing or changed). Loot detection may not work; please report this.")
end

LootMirror.SavePosition = function()
    local f = LootMirror.MainFrame
    local point, _, _, x, y = f:GetPoint()
    LootMirrorDB = LootMirrorDB or {}
    LootMirrorDB.point = point
    LootMirrorDB.x     = x
    LootMirrorDB.y     = y
end

function LootMirror.RefreshFontSize()
    local size = (LootMirrorDB and LootMirrorDB.fontSize) or 11
    for _, row in ipairs(activeRows) do
        LootMirror.ApplyFontSizeToRow(row, size)
    end
end

-- Applies bar texture + border width, and background/border tint, to a row.
-- Covers everything under Options > Bar Style.
function LootMirror.RefreshTexture()
    local db = LootMirrorDB or {}
    local texture = db.texture or "Blizzard"
    local borderWidth = db.borderWidth or 1
    local bg = db.bgColor or {}
    local bc = db.borderColor or {}
    for _, row in ipairs(activeRows) do
        LootMirror.ApplyTextureToRow(row, texture, borderWidth)
        LootMirror.ApplyColorsToRow(row,
            bg.r or 0, bg.g or 0, bg.b or 0, db.bgOpacity or 0.85,
            bc.r or 0.4, bc.g or 0.4, bc.b or 0.5)
    end
end

local ROW_HEIGHT = 52 -- must match CreateLootRow's SetSize height in LootFrame.lua

local function UpdateRowPositions()
    local growUp = LootMirrorDB and LootMirrorDB.growUp
    local scale = (LootMirrorDB and LootMirrorDB.barScale) or 1
    local gap = (LootMirrorDB and LootMirrorDB.barSpacing) or 4
    -- NOTE: do not multiply by `scale` here. row:SetPoint()'s offset is already
    -- interpreted in the row's own coordinate space and gets multiplied by the
    -- row's effective scale automatically (since row:SetScale(scale) below).
    -- Multiplying here too made the gap grow with scale^2 instead of scale,
    -- so "0px spacing" only touched exactly at scale=1 and drifted apart/
    -- overlapped everywhere else.
    local spacing = ROW_HEIGHT + gap
    for i, row in ipairs(activeRows) do
        row:ClearAllPoints()
        if growUp then
            row:SetPoint("BOTTOM", LootMirror.MainFrame, "TOP", 0, (i - 1) * spacing)
        else
            row:SetPoint("TOP", LootMirror.MainFrame, "BOTTOM", 0, -(i - 1) * spacing)
        end
        row:SetScale(scale)
    end
end

function LootMirror.RefreshLayout()
    UpdateRowPositions()
end

local function IsFiltered(quality)
    local fq = LootMirrorDB and LootMirrorDB.filterQuality
    return fq and fq[quality or 1] == false
end

-- LootMirror is scoped to gear, not a general loot log -- equipment (weapons/
-- armor/profession tools) is the only category it ever shows, hardcoded
-- rather than a togglable filter, since that's the whole point of the addon.
local EQUIPMENT_CLASS_IDS = { [2] = true, [4] = true, [19] = true } -- Weapon, Armor, Profession equipment

-- Poor-quality items are always junk, never worth flagging -- hardcoded out
-- alongside the equipment-only check rather than a Quality checkbox.
local function ShouldFilterLoot(quality, itemClassID)
    if quality == 0 then return true end
    if not EQUIPMENT_CLASS_IDS[itemClassID] then return true end
    return IsFiltered(quality)
end

-- Applies item data to a row; accepts pre-fetched data or fetches it on demand.
-- Returns the quality on success, false if not cached yet.
local function ApplyItemData(row, itemLink, count, itemName, quality, itemTexture)
    if not itemName then
        itemName, _, quality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemLink)
    end
    if not itemName then return false end

    LootMirror.SetRowItem(row, itemName, quality, itemTexture, count)
    return quality
end

-- Acquires a pooled row (LootMirror.AcquireRow reuses released rows instead of
-- creating new ones -- see LootFrame.lua) and displays one loot entry on it.
-- Wrapped by DisplayLoot below so a bad itemLink/state can never fail silently.
local function DisplayLootImpl(player, itemLink, count, bypassFilter)
    -- Single GetItemInfo call: used for filter check and row population
    local itemName, _, quality, _, _, _, _, _, _, itemTexture, _, itemClassID = C_Item.GetItemInfo(itemLink)
    if quality and not bypassFilter and ShouldFilterLoot(quality, itemClassID) then return end

    local itemID = tonumber(itemLink:match("|Hitem:(%d+)"))

    local row = LootMirror.AcquireRow()
    row.itemLink   = itemLink
    row.playerName = player

    local pr, pg, pb = GetClassColor(player)
    LootMirror.SetRowPlayer(row, player, pr, pg, pb)
    LootMirror.SetRowLoading(row) -- placeholder until item data resolves below/async

    -- Pass pre-fetched data; only queue if still not cached
    if not ApplyItemData(row, itemLink, count, itemName, quality, itemTexture) and itemID then
        if not pendingItems[itemID] then pendingItems[itemID] = {} end
        table.insert(pendingItems[itemID], { row = row, count = count, itemLink = itemLink, bypassFilter = bypassFilter })
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

-- Public entry point: never lets an error pass silently. Without this, a
-- runtime error inside DisplayLootImpl (bad link, nil field, etc.) would just
-- vanish -- the client only prints Lua errors to chat if the player has
-- "Show Lua Errors" enabled, which is off by default.
local function DisplayLoot(player, itemLink, count, bypassFilter)
    local ok, err = pcall(DisplayLootImpl, player, itemLink, count, bypassFilter)
    if not ok then
        print("|cffff0000LootMirror error:|r " .. tostring(err))
    end
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
            LootMirrorDB.barScale = LootMirrorDB.barScale or 1
            LootMirrorDB.texture  = LootMirrorDB.texture  or "Blizzard"
            LootMirrorDB.barSpacing  = LootMirrorDB.barSpacing  or 4
            LootMirrorDB.borderWidth = LootMirrorDB.borderWidth or 1
            LootMirrorDB.bgOpacity   = LootMirrorDB.bgOpacity   or 0.85
            LootMirrorDB.bgColor     = LootMirrorDB.bgColor     or { r = 0,   g = 0,   b = 0 }
            LootMirrorDB.borderColor = LootMirrorDB.borderColor or { r = 0.4, g = 0.4, b = 0.5 }
            LootMirrorDB.optionsPoint = LootMirrorDB.optionsPoint or "CENTER"
            LootMirrorDB.optionsRelativePoint = LootMirrorDB.optionsRelativePoint or "CENTER"
            LootMirrorDB.optionsX = LootMirrorDB.optionsX or 0
            LootMirrorDB.optionsY = LootMirrorDB.optionsY or 0
            LootMirrorDB.optionsScale = LootMirrorDB.optionsScale or 1
            LootMirrorDB.optionsOpacity = LootMirrorDB.optionsOpacity or 0.95
            -- Poor (0) isn't included -- it's hardcoded out in ShouldFilterLoot,
            -- not a togglable quality (LootMirror only ever shows equipment).
            if not LootMirrorDB.filterQuality then
                LootMirrorDB.filterQuality = { [1]=true,[2]=true,[3]=true,[4]=true,[5]=true }
            else
                -- Safety net: if every quality ended up disabled (e.g. leftover
                -- state from before the Options window had a way to see/edit
                -- this), loot would silently never show with no indication why.
                local anyEnabled = false
                for q = 1, 5 do
                    if LootMirrorDB.filterQuality[q] ~= false then anyEnabled = true break end
                end
                if not anyEnabled then
                    print("|cffff9900LootMirror:|r All item qualities are currently disabled under Displayed Qualities (Options). Loot bars won't show until you enable at least one.")
                end
            end
            LootMirror.MainFrame:ClearAllPoints()
            LootMirror.MainFrame:SetPoint(LootMirrorDB.point, UIParent, LootMirrorDB.point, LootMirrorDB.x, LootMirrorDB.y)
            RefreshClassCache()
            print("|cff00ccffLootMirror:|r Loaded. Type |cffff9900/lm|r for options.")
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
        if LOOT_ITEM_PATTERN then
            local p, link = strmatch(msg, LOOT_ITEM_PATTERN)
            if p and link then
                DisplayLoot(p, link, nil)
            end
        end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if not success then return end
        local entries = pendingItems[itemID]
        if not entries then return end
        for _, entry in ipairs(entries) do
            local quality = ApplyItemData(entry.row, entry.itemLink, entry.count)
            local itemClassID = quality and select(12, C_Item.GetItemInfo(entry.itemLink))
            if quality and not entry.bypassFilter and ShouldFilterLoot(quality, itemClassID) then
                -- Filtered out (junk, non-equipment, or a disabled quality): remove the row
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

local function RunLootTest()
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
    if count > #pool then count = #pool end
    count = math.floor(count)

    for _, v in ipairs(pool) do
        if RAID_CLASS_COLORS[v.class] then
            classCache[v.p] = RAID_CLASS_COLORS[v.class]
        end
    end

    for k = 1, count do
        local v = pool[k]
        if v then
            C_Timer.After(k * 0.3, function()
                -- Bypasses quality/equipment filtering: Test is meant to preview
                -- bar layout/appearance, not exercise filter settings, so it
                -- should reliably fill Max Loot Bars regardless of what's
                -- currently checked under Displayed Qualities.
                DisplayLoot(v.p, v.i, v.c, true)
            end)
        end
    end
end

LootMirror.RunTest = RunLootTest
