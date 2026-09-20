-- Wishlist.lua
-- Per-character list of items to watch for in the group loot feed. Items on
-- the list get a gold border + star badge on their loot bar (see
-- LootMirror.SetRowWishlist in LootFrame.lua and Core.lua's DisplayLootImpl),
-- no matter who in the group loots them.
--
-- The management UI is NOT its own window -- LootMirror.Wishlist.BuildUI(...)
-- below is called once by Options.lua to build it inside that window's
-- "Wishlist" tab, so both live in a single LootMirror frame.

LootMirror.Wishlist = LootMirror.Wishlist or {}

-- Each entry is { id = itemID, link = fullItemLink or nil, source = dungeon/
-- raid name or nil }. The link (with its bonus IDs) is what makes the
-- item's quality/name/icon display exactly as seen in the Adventure Guide --
-- an item's *base* itemID alone often resolves to a different (usually
-- lower) quality than the specific upgraded/bonus-ID'd version that was
-- actually clicked, since the same itemID can exist at multiple qualities
-- depending on those bonus IDs. `id` is still what loot matching
-- (IsWishlisted) keys on, since a dropped item should match regardless of
-- which exact bonus IDs it happened to roll. `source` is only ever set when
-- the item was added from the Adventure Guide (see GetCurrentEJInstanceName
-- further down) -- manually pasted entries have no source and just show
-- without one. Legacy entries saved as a bare number (from before this
-- distinction existed) are still read fine; see EntryID/EntryLink/
-- EntrySource below.

local wishlistSet = {} -- itemID -> true, rebuilt from LootMirrorCharDB.wishlist below

local function EntryID(entry)
    return type(entry) == "table" and entry.id or entry
end

local function EntryLink(entry)
    return type(entry) == "table" and entry.link or nil
end

local function EntrySource(entry)
    return type(entry) == "table" and entry.source or nil
end

local function RebuildWishlistSet()
    wishlistSet = {}
    for _, entry in ipairs(LootMirrorCharDB.wishlist) do
        wishlistSet[EntryID(entry)] = true
    end
end

-- Called from Core.lua's ADDON_LOADED handler, after LootMirrorCharDB exists.
function LootMirror.Wishlist.Init()
    LootMirrorCharDB = LootMirrorCharDB or {}
    LootMirrorCharDB.wishlist = LootMirrorCharDB.wishlist or {}
    RebuildWishlistSet()
end

function LootMirror.Wishlist.IsWishlisted(itemID)
    return itemID ~= nil and wishlistSet[itemID] == true
end

function LootMirror.Wishlist.GetAll()
    return LootMirrorCharDB.wishlist
end

-- Returns true if added, false if it was already on the list. `link` and
-- `source` are optional and only affect how the entry displays in the
-- management list.
function LootMirror.Wishlist.Add(itemID, link, source)
    if not itemID or wishlistSet[itemID] then return false end
    table.insert(LootMirrorCharDB.wishlist, { id = itemID, link = link, source = source })
    wishlistSet[itemID] = true
    return true
end

function LootMirror.Wishlist.Remove(itemID)
    for i, entry in ipairs(LootMirrorCharDB.wishlist) do
        if EntryID(entry) == itemID then
            table.remove(LootMirrorCharDB.wishlist, i)
            wishlistSet[itemID] = nil
            return true
        end
    end
    return false
end

-- Lets other files (Core.lua, on auto-removing a looted wishlist item) ask
-- the management list to redraw if it's currently the visible tab. A no-op
-- if BuildUI hasn't run yet or the Wishlist tab isn't the one showing.
function LootMirror.Wishlist.RefreshUI()
    if wishlistContainer and wishlistContainer:IsShown() and RefreshList then
        RefreshList()
    end
end

--------------------------------------------------------------------------
-- Shared UI palette/helpers for the management list built in BuildUI below.
-- Kept separate from Options.lua's own palette table since the two are
-- edited independently, but the actual color values are meant to match.
--------------------------------------------------------------------------
local C = {
    card    = { 0.10,  0.10,  0.15,  0.55 },
    border  = { 0.18,  0.40,  0.48,  0.55 },
    accent  = { 0.18,  0.72,  0.92 },
    text    = { 0.88,  0.88,  0.92 },
    subtext = { 0.55,  0.55,  0.62 },
    track   = { 0.16,  0.16,  0.22, 1 },
    control = { 0.09,  0.09,  0.13, 0.9 },
}

local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROW_HEIGHT = 40 -- tall enough for name + the source (dungeon/raid) subtext line
local SCROLLBAR_WIDTH = 6
local SCROLLBAR_GAP = 6

local wishlistContainer -- the tab panel frame BuildUI was given; set there
local RefreshList        -- forward-declared; assigned inside BuildUI

local function ParseItemID(text)
    if not text then return nil end
    local id = text:match("|Hitem:(%d+)") or text:match("^%s*(%d+)%s*$")
    return id and tonumber(id) or nil
end

-- Shared by the manual input box and the Encounter Journal hook further
-- down: adds an item by ID, pre-caches its info, and refreshes the list if
-- the Wishlist tab happens to be the one currently showing. `link`, if
-- available, is the exact hyperlink the item was picked from (bonus IDs and
-- all) -- passing it keeps the wishlist entry's displayed quality/name/icon
-- matching what was actually clicked instead of the item's bare-itemID
-- default. `source`, if available, is the dungeon/raid name it was added
-- from (see GetCurrentEJInstanceName further down).
local function AddItemToWishlist(itemID, link, source)
    if not itemID then return end
    if LootMirror.Wishlist.Add(itemID, link, source) then
        C_Item.RequestLoadItemDataByID(itemID)
        local itemName = C_Item.GetItemInfo(link or itemID)
        local msg = "Added " .. (itemName or ("item " .. itemID)) .. " to your wishlist."
        if source then msg = msg .. " (" .. source .. ")" end
        print("|cff00ccffLootMirror:|r " .. msg)
        if wishlistContainer and wishlistContainer:IsShown() and RefreshList then RefreshList() end
    else
        print("|cffff9900LootMirror:|r That item is already on your wishlist.")
    end
end

--------------------------------------------------------------------------
-- LootMirror.Wishlist.BuildUI(container, containerWidth)
-- Builds the wishlist management UI (instructions, add box, scrollable
-- item list) inside `container`, a frame Options.lua provides sized to its
-- "Wishlist" tab's content area. Called exactly once, from Options.lua.
-- `containerWidth` is that area's pixel width, needed up front to size the
-- scroll child (the ScrollFrame itself has no fixed width to read yet at
-- the point this runs).
--------------------------------------------------------------------------
function LootMirror.Wishlist.BuildUI(container, containerWidth)
    wishlistContainer = container

    local subtitle = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    subtitle:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetWordWrap(true)
    subtitle:SetText("Shift + Right-click a loot item in the Adventure Guide,\nor paste a link/item ID below and press Enter.")
    subtitle:SetTextColor(unpack(C.subtext))

    --------------------------------------------------------------------
    -- Add row: item-link edit box + Add button. NOTE: shift-clicking an
    -- item does NOT insert its link into a plain custom EditBox like this
    -- one -- the client only does that for actual chat edit boxes. So this
    -- box only takes pasted links (Ctrl+V) or a typed item ID; the
    -- Encounter Journal hook further down (Shift + Right-click) is the one
    -- real one-click entry point.
    --------------------------------------------------------------------
    local addBtn = CreateFrame("Button", nil, container, "BackdropTemplate")
    addBtn:SetSize(52, 26)
    addBtn:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -40)
    addBtn:SetBackdrop({ bgFile = WHITE })
    addBtn:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
    local addBtnText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addBtnText:SetPoint("CENTER")
    addBtnText:SetText("Add")
    addBtnText:SetTextColor(0.05, 0.05, 0.05)
    addBtnText:SetShadowOffset(0, 0)
    addBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(1, 1, 1, 1) end)
    addBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 0.9) end)

    local inputBox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    inputBox:SetHeight(26)
    inputBox:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -40)
    inputBox:SetPoint("RIGHT", addBtn, "LEFT", -8, 0)
    inputBox:SetAutoFocus(false)
    inputBox:SetFontObject(GameFontHighlightSmall)
    inputBox:SetTextInsets(8, 8, 0, 0)
    inputBox:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    inputBox:SetBackdropColor(unpack(C.control))
    inputBox:SetBackdropBorderColor(unpack(C.border))
    inputBox:SetScript("OnEnter", function(self)
        if not self:HasFocus() then self:SetBackdropBorderColor(unpack(C.accent)) end
    end)
    inputBox:SetScript("OnLeave", function(self)
        if not self:HasFocus() then self:SetBackdropBorderColor(unpack(C.border)) end
    end)
    inputBox:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    inputBox:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
    inputBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local function TryAddFromInput()
        local text = inputBox:GetText()
        local itemID = ParseItemID(text)
        if not itemID then
            print("|cffff9900LootMirror:|r Paste an item link or type its numeric item ID first.")
        else
            -- A pasted link is the full escape sequence as-is; keep it
            -- verbatim (bonus IDs and all) so the entry displays the right
            -- quality/icon.
            local link = text:find("|Hitem:", 1, true) and text or nil
            AddItemToWishlist(itemID, link)
        end
        inputBox:SetText("")
        inputBox:ClearFocus()
    end

    inputBox:SetScript("OnEnterPressed", TryAddFromInput)
    addBtn:SetScript("OnClick", TryAddFromInput)

    --------------------------------------------------------------------
    -- Scrollable list of current wishlist entries -- see
    -- LootMirror.CreateScrollList in LootFrame.lua, shared with Options.lua.
    --------------------------------------------------------------------
    local wishlistScrollList = LootMirror.CreateScrollList(container, {
        anchorFn = function(sf, sbWidth, sbGap)
            sf:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -78)
            sf:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -(sbWidth + sbGap), 0)
        end,
        contentWidth = containerWidth - SCROLLBAR_WIDTH - SCROLLBAR_GAP,
        scrollbarWidth = SCROLLBAR_WIDTH,
        scrollbarGap = SCROLLBAR_GAP,
        wheelStep = 30,
    })
    local scrollFrame     = wishlistScrollList.scrollFrame
    local content         = wishlistScrollList.content
    local UpdateScrollbar = wishlistScrollList.UpdateScrollbar

    --------------------------------------------------------------------
    -- List rows: pooled like LootFrame.lua's loot rows, since RefreshList
    -- tears down and rebuilds the visible set on every add/remove.
    --------------------------------------------------------------------
    local rowPool = {}
    local activeListRows = {}

    local function AcquireListRow()
        local row = table.remove(rowPool)
        if not row then
            row = CreateFrame("Button", nil, content, "BackdropTemplate")
            row:SetHeight(ROW_HEIGHT)
            row:SetBackdrop({ bgFile = WHITE })
            row:SetBackdropColor(unpack(C.card))

            row.Icon = row:CreateTexture(nil, "ARTWORK")
            row.Icon:SetSize(28, 28)
            row.Icon:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.NameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.NameText:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, -1)
            row.NameText:SetPoint("RIGHT", row, "RIGHT", -38, 0)
            row.NameText:SetJustifyH("LEFT")
            row.NameText:SetWordWrap(false)

            -- Dungeon/raid the item was added from (Adventure Guide adds
            -- only -- manually pasted entries just leave this blank).
            row.SourceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.SourceText:SetPoint("TOPLEFT", row.NameText, "BOTTOMLEFT", 0, -2)
            row.SourceText:SetPoint("RIGHT", row, "RIGHT", -38, 0)
            row.SourceText:SetJustifyH("LEFT")
            row.SourceText:SetWordWrap(false)
            row.SourceText:SetTextColor(unpack(C.subtext))

            row.RemoveBtn = CreateFrame("Button", nil, row)
            row.RemoveBtn:SetSize(32, 32)
            row.RemoveBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.RemoveText = row.RemoveBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.RemoveText:SetPoint("CENTER")
            row.RemoveText:SetText("\195\151") -- ×
            do
                local path, _, flags = row.RemoveText:GetFont()
                row.RemoveText:SetFont(path, 20, flags)
            end
            row.RemoveText:SetTextColor(0.65, 0.65, 0.72, 1)
            row.RemoveBtn:SetScript("OnEnter", function() row.RemoveText:SetTextColor(1, 0.35, 0.35, 1) end)
            row.RemoveBtn:SetScript("OnLeave", function() row.RemoveText:SetTextColor(0.65, 0.65, 0.72, 1) end)

            row:SetScript("OnEnter", function(self)
                self:SetBackdropColor(C.card[1] + 0.05, C.card[2] + 0.05, C.card[3] + 0.08, C.card[4])
                if self.itemLink then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.itemLink)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(self)
                self:SetBackdropColor(unpack(C.card))
                GameTooltip:Hide()
            end)
        end
        return row
    end

    local function ReleaseListRow(row)
        row:Hide()
        row:ClearAllPoints()
        row.itemID = nil
        row.itemLink = nil
        row.SourceText:SetText("")
        row.RemoveBtn:SetScript("OnClick", nil)
        table.insert(rowPool, row)
    end

    local emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    emptyText:SetPoint("RIGHT", content, "RIGHT", -4, 0)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetWordWrap(true)
    emptyText:SetTextColor(unpack(C.subtext))
    emptyText:SetText("No items yet. Shift + Right-click a loot item in the Adventure Guide, or paste a link above.")
    emptyText:Hide()

    RefreshList = function()
        for _, row in ipairs(activeListRows) do
            ReleaseListRow(row)
        end
        wipe(activeListRows)

        local items = LootMirror.Wishlist.GetAll()
        local y = 0
        for _, entry in ipairs(items) do
            local itemID = EntryID(entry)
            local savedLink = EntryLink(entry)
            local savedSource = EntrySource(entry)
            local row = AcquireListRow()
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)

            -- Look up via the saved link (bonus IDs and all) when we have
            -- one, so quality/name/icon match what was actually clicked,
            -- not the bare itemID's default.
            local itemName, itemLink, quality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(savedLink or itemID)
            row.itemID = itemID
            row.itemLink = itemLink or savedLink
            row.SourceText:SetText(savedSource or "")

            if itemName then
                local r, g, b = GetItemQualityColor(quality or 1)
                local hex = string.format("ff%02x%02x%02x",
                    math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
                row.NameText:SetText("|c" .. hex .. itemName .. "|r")
                row.Icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
            else
                row.NameText:SetText("|cffaaaaaaLoading item " .. itemID .. "...|r")
                row.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                C_Item.RequestLoadItemDataByID(itemID)
            end

            row.RemoveBtn:SetScript("OnClick", function()
                LootMirror.Wishlist.Remove(itemID)
                RefreshList()
            end)

            row:Show()
            table.insert(activeListRows, row)
            y = y + ROW_HEIGHT + 4
        end

        emptyText:SetShown(#items == 0)
        content:SetHeight(math.max(y, 1))
        UpdateScrollbar()
    end

    container:SetScript("OnShow", function() RefreshList() end)

    -- Item names/icons/quality can take a moment to arrive from the server
    -- the first time an item is referenced; refresh the visible list once
    -- they do.
    local resolveWatcher = CreateFrame("Frame")
    resolveWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    resolveWatcher:SetScript("OnEvent", function(self, event, itemID, success)
        if not success or not container:IsShown() then return end
        for _, row in ipairs(activeListRows) do
            if row.itemID == itemID then
                RefreshList()
                return
            end
        end
    end)
end

--------------------------------------------------------------------------
-- Encounter Journal (Adventure Guide) integration: Shift + Right-click a
-- loot item anywhere in the Adventure Guide to add it straight to the
-- wishlist, without opening the wishlist tab.
--
-- Shift+Left-click is deliberately NOT used as the trigger -- it's the
-- client's standard "link this item in chat" gesture, used constantly
-- everywhere else in the UI (bags, trade, quest log, ...), so repurposing it
-- would be a disruptive surprise there.
--
-- This does NOT hook any Blizzard function or script. Two earlier attempts
-- did (hooksecurefunc on EncounterJournal_LootItem_OnClick, then HookScript
-- on GameTooltip's OnTooltipSetItem/OnMouseUp), and both broke on this
-- client -- the Adventure Guide's loot lists apparently use button/tooltip
-- setups here that don't tolerate being hooked either of the usual ways.
--
-- Instead, a lightweight OnUpdate (the only per-frame cost, and only while
-- the Encounter Journal is actually open) polls IsMouseButtonDown for the
-- moment Right-click is pressed. On that edge, if Shift is also held and
-- GameTooltip happens to be showing an item (i.e. the mouse is hovering
-- one), that exact item is added. This never calls into or overrides any
-- Blizzard function/script at all, so it cannot break the Encounter Journal
-- no matter how its loot lists are built.
--------------------------------------------------------------------------
local function ItemIDFromLink(link)
    if not link then return nil end
    if type(link) == "number" then return link end
    local id = link:match("|Hitem:(%d+)") or link:match("item:(%d+)") or link:match("^%s*(%d+)%s*$")
    return id and tonumber(id) or nil
end

-- Reads the dungeon/raid name straight off the Adventure Guide's own
-- breadcrumb bar (Home -> Instance -> ...), via /fstack: EJ_GetCurrentInstance
-- doesn't exist on this client (moved into C_EncounterJournal, which has no
-- direct equivalent), so rather than guess further at that API, this reads
-- the second breadcrumb button's label text directly. It's a plain read of
-- an existing FontString -- no hook, no override -- so it can't break the
-- Encounter Journal; the only risk is it silently returning nil if that
-- breadcrumb isn't populated (e.g. nothing drilled into yet).
local function GetCurrentEJInstanceName()
    local ok, text = pcall(function()
        local fs = _G.EncounterJournalNavBarButton2Text
        local t = fs and fs:GetText()
        if t and t ~= "" then return t end
        return nil
    end)
    if ok then return text end
    return nil
end

local function TryAddHoveredEJItem()
    local ok, err = pcall(function()
        if not IsShiftKeyDown() then return end
        if not GameTooltip:IsShown() then return end
        local _, link = GameTooltip:GetItem()
        local itemID = ItemIDFromLink(link)
        if itemID then
            AddItemToWishlist(itemID, link, GetCurrentEJInstanceName())
        end
    end)
    if not ok then
        print("|cffff0000LootMirror error:|r " .. tostring(err))
    end
end

-- The OnUpdate is only ever attached while the Encounter Journal is actually
-- open (toggled via its own OnShow/OnHide below), so it costs nothing at all
-- the rest of the time -- which is most of a play session.
local ejPoller = CreateFrame("Frame")
local rightButtonWasDown = false

local function EJPollOnUpdate()
    local isDown = IsMouseButtonDown("RightButton")
    if isDown and not rightButtonWasDown then
        TryAddHoveredEJItem()
    end
    rightButtonWasDown = isDown
end

local function StartEJPolling()
    rightButtonWasDown = false
    ejPoller:SetScript("OnUpdate", EJPollOnUpdate)
end

local function StopEJPolling()
    ejPoller:SetScript("OnUpdate", nil)
end

-- EncounterJournal is a plain top-level Frame, so hooking its own OnShow/
-- OnHide (unlike the loot-list buttons/tooltips inside it, which turned out
-- not to tolerate hooking on this client) is the same safe, standard pattern
-- already used elsewhere in this addon (see optFrame's OnHide hook in
-- Options.lua). Blizzard_EncounterJournal is lazy-loaded, so this waits for
-- it if it isn't already loaded.
local function HookEncounterJournalVisibility()
    if EncounterJournal:IsShown() then
        StartEJPolling()
    end
    EncounterJournal:HookScript("OnShow", StartEJPolling)
    EncounterJournal:HookScript("OnHide", StopEJPolling)
end

if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
    HookEncounterJournalVisibility()
else
    local ejLoader = CreateFrame("Frame")
    ejLoader:RegisterEvent("ADDON_LOADED")
    ejLoader:SetScript("OnEvent", function(self, event, name)
        if name == "Blizzard_EncounterJournal" then
            self:UnregisterEvent("ADDON_LOADED")
            HookEncounterJournalVisibility()
        end
    end)
end
