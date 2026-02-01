--[[
    Farmer - Farmer.lua
    Main addon file - event handling and initialization
]]

local addonName, addon = ...

-- Session timeout in seconds (5 minutes) - if more time has passed since last save, start new session
local SESSION_TIMEOUT = 300

-- Create main event frame
local eventFrame = CreateFrame("Frame", "FarmerFrame", UIParent)

-- Events to register
local events = {
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_LOGOUT",
    "PLAYER_ENTERING_WORLD",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_MONEY",
    "UNIT_SPELLCAST_SENT",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "LOOT_OPENED",
    "LOOT_CLOSED",
    -- Honor tracking events
    "HONOR_XP_UPDATE",
    "CHAT_MSG_COMBAT_HONOR_GAIN",
    "PLAYER_PVP_KILLS_CHANGED",
}

-- Register all events
for _, event in ipairs(events) do
    eventFrame:RegisterEvent(event)
end

-- Event handlers table
local eventHandlers = {}

-- ADDON_LOADED: Initialize when our addon loads
function eventHandlers:ADDON_LOADED(loadedAddon)
    if loadedAddon ~= addonName then return end
    
    -- Initialize saved variables
    addon:InitDB()
    
    -- Register slash commands
    addon:RegisterSlashCommands()
    
    addon:Debug("Addon loaded successfully")
end

-- PLAYER_LOGIN: Player has logged in
function eventHandlers:PLAYER_LOGIN()
    local currentTime = time()
    local session = addon.charDB.session
    
    -- Determine if this is a UI reload or a new session
    -- If lastSaveTime exists and is within SESSION_TIMEOUT, this is likely a reload
    local isReloadSession = session.lastSaveTime > 0 and 
                            (currentTime - session.lastSaveTime) < SESSION_TIMEOUT
    
    if isReloadSession then
        -- This is a UI reload - keep existing session data
        addon:Debug("UI reload detected - preserving session data")
    else
        -- This is a new login or session timed out
        -- Save the previous session to history if it has data
        addon:SaveSessionToHistory()
        
        -- Start fresh session
        addon:Debug("New session started")
        session.startTime = currentTime
        session.endTime = 0
        session.totalVendorValue = 0
        session.totalAHValue = 0
        session.itemsLooted = {}
        session.rawGoldLooted = 0
        session.honorGained = 0
        session.honorableKills = 0
    end
    
    -- Update last save time
    session.lastSaveTime = currentTime
    
    -- Check for Auctionator
    addon.hasAuctionator = (Auctionator ~= nil) or (AUCTIONATOR_ENABLE ~= nil)
    
    -- Restore sort settings
    addon.currentSortMode = addon:GetSetting("ui.sortMode") or "value"
    addon.sortAscending = addon:GetSetting("ui.sortAscending") or false
    
    -- Show welcome message if enabled
    if addon:GetSetting("features.showWelcome") then
        local ahStatus = addon.hasAuctionator and "|cff00ff00Auctionator detected|r" or "|cffff9900Auctionator not found (using vendor prices)|r"
        addon:Print("Loot tracking active! " .. ahStatus)
        addon:Print("Type /lootsesh for commands.")
    end
    
    -- Initialize any UI elements here
    addon:CreateMainFrame()
    
    -- Restore UI visibility
    if addon:GetSetting("ui.visible") then
        addon.mainFrame:Show()
        addon:UpdateMainFrame()
    end
end

-- PLAYER_LOGOUT: Player is logging out
function eventHandlers:PLAYER_LOGOUT()
    -- Save visibility state before logout/reload
    if addon.mainFrame then
        addon:SetSetting("ui.visible", addon.mainFrame:IsShown())
    end
    
    -- Update last save time so we can detect reloads
    addon.charDB.session.lastSaveTime = time()
    
    addon:Debug("Saving data before logout")
end

-- PLAYER_ENTERING_WORLD: Fires on login, reloads, and zone changes
function eventHandlers:PLAYER_ENTERING_WORLD(isLogin, isReload)
    if isLogin then
        addon:Debug("Initial login detected")
    elseif isReload then
        addon:Debug("UI reload detected")
    end
end

-- Gathering spell IDs and names for detection
local gatheringSpells = {
    -- Mining
    [2575] = "gathering",   -- Mining (Apprentice)
    [2576] = "gathering",   -- Mining (Journeyman)
    [3564] = "gathering",   -- Mining (Expert)
    [10248] = "gathering",  -- Mining (Artisan)
    [29354] = "gathering",  -- Mining (Master)
    [50310] = "gathering",  -- Mining (Grand Master)
    [74517] = "gathering",  -- Mining (Illustrious)
    [102161] = "gathering", -- Mining (Zen Master)
    [158754] = "gathering", -- Mining (Draenor)
    [195122] = "gathering", -- Mining (Legion)
    [253337] = "gathering", -- Mining (Kul Tiran/Zandalari)
    [366260] = "gathering", -- Mining (Dragon Isles)
    -- Herbalism
    [2366] = "gathering",   -- Herb Gathering (Apprentice)
    [2368] = "gathering",   -- Herb Gathering (Journeyman)
    [3570] = "gathering",   -- Herb Gathering (Expert)
    [11993] = "gathering",  -- Herb Gathering (Artisan)
    [28695] = "gathering",  -- Herb Gathering (Master)
    [50300] = "gathering",  -- Herb Gathering (Grand Master)
    [74519] = "gathering",  -- Herb Gathering (Illustrious)
    [110413] = "gathering", -- Herb Gathering (Zen Master)
    [158756] = "gathering", -- Herb Gathering (Draenor)
    [195114] = "gathering", -- Herb Gathering (Legion)
    [253340] = "gathering", -- Herb Gathering (Kul Tiran/Zandalari)
    [366252] = "gathering", -- Herb Gathering (Dragon Isles)
    -- Skinning
    [8613] = "gathering",   -- Skinning (Apprentice)
    [8617] = "gathering",   -- Skinning (Journeyman)
    [8618] = "gathering",   -- Skinning (Expert)
    [10768] = "gathering",  -- Skinning (Artisan)
    [32678] = "gathering",  -- Skinning (Master)
    [50305] = "gathering",  -- Skinning (Grand Master)
    [74522] = "gathering",  -- Skinning (Illustrious)
    [102216] = "gathering", -- Skinning (Zen Master)
    [158758] = "gathering", -- Skinning (Draenor)
    [195125] = "gathering", -- Skinning (Legion)
    [253343] = "gathering", -- Skinning (Kul Tiran/Zandalari)
    [366264] = "gathering", -- Skinning (Dragon Isles)
}

-- Gathering spell names (fallback for localization)
local gatheringSpellNames = {
    ["Mining"] = true,
    ["Herb Gathering"] = true,
    ["Skinning"] = true,
    ["Smelting"] = false,  -- Not gathering
}

-- Track current loot source
addon.currentLootSource = "pickup"  -- "pickup" or "gathered"
addon.lastGatheringTime = 0
local GATHERING_TIMEOUT = 5  -- seconds to consider loot as gathered after casting

-- UNIT_SPELLCAST_SENT: Detect when player starts casting a gathering spell
function eventHandlers:UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    
    if gatheringSpells[spellID] then
        addon.currentLootSource = "gathered"
        addon.lastGatheringTime = GetTime()
        addon:Debug("Gathering spell detected: " .. (GetSpellInfo(spellID) or spellID))
    end
end

-- UNIT_SPELLCAST_SUCCEEDED: Confirm gathering spell completed
function eventHandlers:UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
    if unit ~= "player" then return end
    
    if gatheringSpells[spellID] then
        addon.currentLootSource = "gathered"
        addon.lastGatheringTime = GetTime()
        addon:Debug("Gathering spell succeeded")
    end
end

-- UNIT_SPELLCAST_FAILED/INTERRUPTED: Reset if gathering was cancelled
function eventHandlers:UNIT_SPELLCAST_FAILED(unit, castGUID, spellID)
    if unit ~= "player" then return end
    
    if gatheringSpells[spellID] then
        -- Only reset if no recent successful gathering
        if GetTime() - addon.lastGatheringTime > GATHERING_TIMEOUT then
            addon.currentLootSource = "pickup"
        end
    end
end

function eventHandlers:UNIT_SPELLCAST_INTERRUPTED(unit, castGUID, spellID)
    eventHandlers:UNIT_SPELLCAST_FAILED(unit, castGUID, spellID)
end

-- LOOT_OPENED: Loot window opened - check if this is from gathering
function eventHandlers:LOOT_OPENED(autoLoot)
    -- Check if we recently cast a gathering spell
    if GetTime() - addon.lastGatheringTime <= GATHERING_TIMEOUT then
        addon.currentLootSource = "gathered"
        addon:Debug("Loot window opened - source: gathered")
    else
        addon.currentLootSource = "pickup"
        addon:Debug("Loot window opened - source: pickup")
    end
end

-- LOOT_CLOSED: Reset loot source after a short delay
function eventHandlers:LOOT_CLOSED()
    -- Keep the source for items being processed, reset after delay
    C_Timer.After(0.5, function()
        if GetTime() - addon.lastGatheringTime > GATHERING_TIMEOUT then
            addon.currentLootSource = "pickup"
        end
    end)
end

-- CHAT_MSG_LOOT: Fires when items are looted
function eventHandlers:CHAT_MSG_LOOT(msg)
    -- Check if this is the player's loot
    local playerName = UnitName("player")
    
    -- Match patterns for loot messages
    -- "You receive loot: [Item Name]x5"
    -- "You receive loot: [Item Name]"
    local itemLink, count = msg:match("You receive loot: (|c.-|r)x?(%d*)")
    
    if not itemLink then
        -- Try alternate pattern
        itemLink, count = msg:match("You receive item: (|c.-|r)x?(%d*)")
    end
    
    if itemLink then
        count = tonumber(count) or 1
        addon:ProcessLootedItem(itemLink, count)
    end
end

-- CHAT_MSG_MONEY: Fires when money is looted
function eventHandlers:CHAT_MSG_MONEY(msg)
    local copper = addon:ParseMoneyString(msg)
    if copper and copper > 0 then
        addon.charDB.session.rawGoldLooted = addon.charDB.session.rawGoldLooted + copper
        addon.charDB.lifetime.rawGoldLooted = addon.charDB.lifetime.rawGoldLooted + copper
        addon:Debug("Looted money: " .. addon.utils.FormatMoney(copper))
        addon:UpdateMainFrame()
    end
end

-- HONOR_XP_UPDATE: Fires when honor is gained (retail/modern clients)
function eventHandlers:HONOR_XP_UPDATE(unitTarget, currentHonor, maxHonor)
    -- This is mainly for modern WoW, may not fire in Classic
    addon:Debug("Honor XP update detected")
end

-- CHAT_MSG_COMBAT_HONOR_GAIN: Fires when honor is gained from kills
function eventHandlers:CHAT_MSG_COMBAT_HONOR_GAIN(msg)
    -- Parse honor from message like "PlayerName dies, honorable kill Rank: Private (123 Honor Points)"
    -- Or simpler: "You have been awarded 123 honor points"
    local honor = msg:match("(%d+) [Hh]onor")
    if honor then
        honor = tonumber(honor) or 0
        if honor > 0 then
            addon.charDB.session.honorGained = (addon.charDB.session.honorGained or 0) + honor
            addon.charDB.session.honorableKills = (addon.charDB.session.honorableKills or 0) + 1
            addon.charDB.lifetime.honorGained = (addon.charDB.lifetime.honorGained or 0) + honor
            addon.charDB.lifetime.honorableKills = (addon.charDB.lifetime.honorableKills or 0) + 1
            addon:Debug("Honor gained: " .. honor .. " points")
            addon:UpdateHonorTab()
        end
    end
end

-- PLAYER_PVP_KILLS_CHANGED: Fires when PvP kills change
function eventHandlers:PLAYER_PVP_KILLS_CHANGED(numKills)
    addon:Debug("PvP kills changed: " .. tostring(numKills))
end

-- Main event dispatcher
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if eventHandlers[event] then
        eventHandlers[event](self, ...)
    end
end)

--[[
    Loot Processing Functions
]]

-- Parse money string from chat message to copper value
function addon:ParseMoneyString(msg)
    local gold = msg:match("(%d+) Gold") or 0
    local silver = msg:match("(%d+) Silver") or 0
    local copper = msg:match("(%d+) Copper") or 0
    
    return (tonumber(gold) or 0) * 10000 + (tonumber(silver) or 0) * 100 + (tonumber(copper) or 0)
end

-- Get item price from Auctionator
function addon:GetAuctionatorPrice(itemID)
    if not self.hasAuctionator then return nil end
    
    -- Auctionator API varies by version, try multiple methods
    if Auctionator and Auctionator.API and Auctionator.API.v1 then
        -- Modern Auctionator API
        local success, price = pcall(function()
            return Auctionator.API.v1.GetAuctionPriceByItemID(addonName, itemID)
        end)
        if success and price and price > 0 then
            return price
        end
    end
    
    -- Try legacy Auctionator functions
    if Atr_GetAuctionBuyout then
        local price = Atr_GetAuctionBuyout(itemID)
        if price and price > 0 then
            return price
        end
    end
    
    -- Try GetAuctionPrice if available
    if GetAuctionPrice then
        local price = GetAuctionPrice(itemID)
        if price and price > 0 then
            return price
        end
    end
    
    return nil
end

-- Process a looted item
function addon:ProcessLootedItem(itemLink, count)
    if not itemLink then return end
    
    count = count or 1
    
    -- Determine loot source
    local lootSource = self.currentLootSource or "pickup"
    
    -- Get item info
    local itemName, _, itemQuality, _, _, itemType, itemSubType, _, _, itemTexture, vendorPrice, _, _, _, _, _, _ = GetItemInfo(itemLink)
    local itemID = GetItemInfoInstant(itemLink)
    
    if not itemID then
        self:Debug("Could not get itemID for: " .. tostring(itemLink))
        return
    end
    
    -- Additional heuristic: Check item type for gathering materials
    -- Trade Goods that are commonly gathered
    if itemType == "Tradeskill" or itemType == "Trade Goods" then
        -- Check subtype for gathering materials
        local gatheringSubTypes = {
            ["Metal & Stone"] = true,
            ["Herb"] = true,
            ["Leather"] = true,
            ["Cloth"] = false,  -- Cloth is looted, not gathered
            ["Elemental"] = true,
            ["Ore"] = true,
            ["Herbalism"] = true,
            ["Mining"] = true,
            ["Skinning"] = true,
        }
        -- If we recently gathered and this is a gathering material, confirm source
        if gatheringSubTypes[itemSubType] and GetTime() - self.lastGatheringTime <= 5 then
            lootSource = "gathered"
        end
    end
    
    -- Check filter settings - skip item if filtered out
    local showPickup = self:GetSetting("filters.showPickup")
    local showGathered = self:GetSetting("filters.showGathered")
    
    -- Default to true if setting doesn't exist
    if showPickup == nil then showPickup = true end
    if showGathered == nil then showGathered = true end
    
    -- Skip if this source type is filtered out (but still track for totals)
    local shouldDisplay = (lootSource == "pickup" and showPickup) or (lootSource == "gathered" and showGathered)
    
    -- Get vendor price (per item)
    vendorPrice = vendorPrice or 0
    local totalVendorValue = vendorPrice * count
    
    -- Get AH price from Auctionator
    local ahPrice = self:GetAuctionatorPrice(itemID)
    local totalAHValue = ahPrice and (ahPrice * count) or 0
    
    -- Update session data
    local session = self.charDB.session
    session.totalVendorValue = session.totalVendorValue + totalVendorValue
    session.totalAHValue = session.totalAHValue + totalAHValue
    
    -- Track individual items
    if not session.itemsLooted[itemID] then
        session.itemsLooted[itemID] = {
            itemID = itemID,
            count = 0,
            vendorValue = 0,
            ahValue = 0,
            name = itemName or "Unknown",
            quality = itemQuality or 1,
            link = itemLink,
            texture = itemTexture,
            lootSource = lootSource,  -- Track source type
        }
    end
    
    local itemData = session.itemsLooted[itemID]
    itemData.count = itemData.count + count
    itemData.vendorValue = itemData.vendorValue + totalVendorValue
    itemData.ahValue = itemData.ahValue + totalAHValue
    -- Update source if this is a new source type (item can come from both)
    if itemData.lootSource ~= lootSource then
        itemData.lootSource = "both"
    end
    
    -- Update lifetime data
    local lifetime = self.charDB.lifetime
    lifetime.totalVendorValue = lifetime.totalVendorValue + totalVendorValue
    lifetime.totalAHValue = lifetime.totalAHValue + totalAHValue
    lifetime.totalItemsLooted = lifetime.totalItemsLooted + count
    
    -- Show loot message if enabled
    if self:GetSetting("features.showLootMessages") then
        local valueStr
        if ahPrice and ahPrice > 0 and self:GetSetting("features.useAHPrices") then
            valueStr = self.utils.FormatMoney(totalAHValue) .. " (AH)"
        elseif totalVendorValue > 0 then
            valueStr = self.utils.FormatMoney(totalVendorValue) .. " (Vendor)"
        else
            valueStr = "No value"
        end
        local sourceStr = lootSource == "gathered" and " [Gathered]" or " [Pickup]"
        self:Debug(string.format("Looted %dx %s - %s%s", count, itemLink, valueStr, sourceStr))
    end
    
    -- Update UI
    self:UpdateMainFrame()
end

-- Get session duration as formatted string
function addon:GetSessionDuration()
    local startTime = self.charDB.session.startTime
    if startTime == 0 then return "0m" end
    
    local duration = time() - startTime
    local hours = math.floor(duration / 3600)
    local minutes = math.floor((duration % 3600) / 60)
    
    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", minutes)
    end
end

-- Get gold per hour calculation
function addon:GetGoldPerHour()
    local startTime = self.charDB.session.startTime
    if startTime == 0 then return 0 end
    
    local duration = time() - startTime
    if duration < 60 then return 0 end  -- Need at least 1 minute
    
    local session = self.charDB.session
    local totalValue = session.rawGoldLooted
    
    if self:GetSetting("features.useAHPrices") and session.totalAHValue > 0 then
        totalValue = totalValue + session.totalAHValue
    else
        totalValue = totalValue + session.totalVendorValue
    end
    
    -- Calculate per hour
    return math.floor(totalValue * 3600 / duration)
end

--[[
    UI Creation - Clean Modern Design with Sorting
]]

-- Quality colors for items
local QUALITY_COLORS = {
    [0] = {0.62, 0.62, 0.62},  -- Poor (gray)
    [1] = {1.00, 1.00, 1.00},  -- Common (white)
    [2] = {0.12, 1.00, 0.00},  -- Uncommon (green)
    [3] = {0.00, 0.44, 0.87},  -- Rare (blue)
    [4] = {0.64, 0.21, 0.93},  -- Epic (purple)
    [5] = {1.00, 0.50, 0.00},  -- Legendary (orange)
}

-- Sort modes
addon.sortModes = {
    { id = "value", name = "Value", desc = "Sort by total value (highest first)" },
    { id = "count", name = "Count", desc = "Sort by quantity (highest first)" },
    { id = "name", name = "Name", desc = "Sort alphabetically by name" },
    { id = "quality", name = "Quality", desc = "Sort by item quality (best first)" },
    { id = "recent", name = "Recent", desc = "Sort by most recently looted" },
}
addon.currentSortMode = "value"
addon.sortAscending = false

-- Create a styled backdrop (theme-aware)
local function CreateStyledBackdrop(frame, alpha, isSection)
    local theme = addon:GetCurrentTheme()
    alpha = alpha or 0.9
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    
    local bg = isSection and theme.sectionBg or theme.background
    local border = theme.border
    frame:SetBackdropColor(bg.r, bg.g, bg.b, alpha)
    frame:SetBackdropBorderColor(border.r, border.g, border.b, border.a)
end

-- Create a highlight backdrop
local function CreateHighlightBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = nil,
        tile = false,
    })
    frame:SetBackdropColor(1, 1, 1, 0.05)
end

-- Create a separator line (theme-aware)
local function CreateSeparator(parent, yOffset)
    local theme = addon:GetCurrentTheme()
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", 12, 0)
    line:SetPoint("RIGHT", -12, 0)
    line:SetPoint("TOP", 0, yOffset)
    line:SetColorTexture(theme.separator.r, theme.separator.g, theme.separator.b, theme.separator.a)
    return line
end

-- Create a stat row (theme-aware)
local function CreateStatRow(parent, label, yOffset)
    local theme = addon:GetCurrentTheme()
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("TOPLEFT", 14, yOffset)
    labelText:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    labelText:SetText(label)
    
    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("TOPRIGHT", -14, yOffset)
    valueText:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
    valueText:SetJustifyH("RIGHT")
    
    return labelText, valueText
end

-- Create custom close button
local function CreateCloseButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(16, 16)
    btn:SetPoint("TOPRIGHT", -8, -8)
    
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Buttons\\UI-StopButton")
    tex:SetVertexColor(0.7, 0.7, 0.7)
    btn.tex = tex
    
    btn:SetScript("OnEnter", function(self)
        self.tex:SetVertexColor(1, 0.3, 0.3)
    end)
    btn:SetScript("OnLeave", function(self)
        self.tex:SetVertexColor(0.7, 0.7, 0.7)
    end)
    
    return btn
end

-- Create styled button (theme-aware)
local function CreateStyledButton(parent, text, width, height)
    local theme = addon:GetCurrentTheme()
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 70, height or 20)
    
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(theme.buttonBg.r, theme.buttonBg.g, theme.buttonBg.b, theme.buttonBg.a)
    btn:SetBackdropBorderColor(theme.buttonBorder.r, theme.buttonBorder.g, theme.buttonBorder.b, theme.buttonBorder.a)
    
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
    btn.label = label
    
    btn:SetScript("OnEnter", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropColor(t.buttonHoverBg.r, t.buttonHoverBg.g, t.buttonHoverBg.b, t.buttonHoverBg.a)
        self:SetBackdropBorderColor(t.buttonHoverBorder.r, t.buttonHoverBorder.g, t.buttonHoverBorder.b, t.buttonHoverBorder.a)
    end)
    btn:SetScript("OnLeave", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropColor(t.buttonBg.r, t.buttonBg.g, t.buttonBg.b, t.buttonBg.a)
        self:SetBackdropBorderColor(t.buttonBorder.r, t.buttonBorder.g, t.buttonBorder.b, t.buttonBorder.a)
    end)
    
    return btn
end

-- Create dropdown menu for sorting (theme-aware)
local function CreateSortDropdown(parent)
    local theme = addon:GetCurrentTheme()
    local dropdown = CreateFrame("Frame", "FarmerSortDropdown", parent, "BackdropTemplate")
    dropdown:SetSize(90, 22)
    
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    dropdown:SetBackdropColor(theme.dropdownBg.r, theme.dropdownBg.g, theme.dropdownBg.b, theme.dropdownBg.a)
    dropdown:SetBackdropBorderColor(theme.dropdownBorder.r, theme.dropdownBorder.g, theme.dropdownBorder.b, theme.dropdownBorder.a)
    
    local text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 8, 0)
    text:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
    -- Set initial text based on current sort mode
    local sortModeName = "Value"
    for _, mode in ipairs(addon.sortModes) do
        if mode.id == addon.currentSortMode then
            sortModeName = mode.name
            break
        end
    end
    text:SetText(sortModeName)
    dropdown.text = text
    
    local arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")
    arrow:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
    
    -- Dropdown menu frame
    local menu = CreateFrame("Frame", "FarmerSortMenu", dropdown, "BackdropTemplate")
    menu:SetPoint("TOP", dropdown, "BOTTOM", 0, -2)
    menu:SetSize(90, 5)
    menu:SetFrameStrata("DIALOG")
    menu:Hide()
    
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    menu:SetBackdropColor(theme.dropdownMenuBg.r, theme.dropdownMenuBg.g, theme.dropdownMenuBg.b, theme.dropdownMenuBg.a)
    menu:SetBackdropBorderColor(theme.dropdownBorder.r, theme.dropdownBorder.g, theme.dropdownBorder.b, theme.dropdownBorder.a)
    
    dropdown.menu = menu
    dropdown.options = {}
    
    -- Create menu items
    local yOffset = -4
    for i, sortMode in ipairs(addon.sortModes) do
        local item = CreateFrame("Button", nil, menu)
        item:SetSize(82, 18)
        item:SetPoint("TOP", 0, yOffset)
        
        local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemText:SetPoint("LEFT", 6, 0)
        itemText:SetText(sortMode.name)
        itemText:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
        item.text = itemText
        
        local highlight = item:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(theme.dropdownHighlight.r, theme.dropdownHighlight.g, theme.dropdownHighlight.b, theme.dropdownHighlight.a)
        
        item:SetScript("OnClick", function()
            addon.currentSortMode = sortMode.id
            addon:SetSetting("ui.sortMode", sortMode.id)
            dropdown.text:SetText(sortMode.name)
            menu:Hide()
            addon:UpdateItemList()
        end)
        
        item:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(sortMode.desc, 1, 1, 1)
            GameTooltip:Show()
        end)
        item:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        dropdown.options[i] = item
        yOffset = yOffset - 18
    end
    
    menu:SetHeight(-yOffset + 4)
    
    -- Toggle menu
    dropdown:EnableMouse(true)
    dropdown:SetScript("OnMouseDown", function()
        if menu:IsShown() then
            menu:Hide()
        else
            menu:Show()
        end
    end)
    
    dropdown:SetScript("OnEnter", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropBorderColor(t.buttonHoverBorder.r, t.buttonHoverBorder.g, t.buttonHoverBorder.b, t.buttonHoverBorder.a)
    end)
    dropdown:SetScript("OnLeave", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropBorderColor(t.dropdownBorder.r, t.dropdownBorder.g, t.dropdownBorder.b, t.dropdownBorder.a)
    end)
    
    -- Close menu when clicking elsewhere
    menu:SetScript("OnShow", function()
        menu:SetPropagateKeyboardInput(true)
    end)
    
    return dropdown
end

-- Create item row for the scroll list (theme-aware)
local function CreateItemRow(parent, index)
    local theme = addon:GetCurrentTheme()
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(parent:GetWidth() - 4, 28)
    
    -- Alternating row colors
    if index % 2 == 0 then
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        row:SetBackdropColor(theme.rowAltBg.r, theme.rowAltBg.g, theme.rowAltBg.b, theme.rowAltBg.a)
    end
    
    -- Item icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon
    
    -- Item name
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -70, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name
    
    -- Count
    local count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("RIGHT", row, "RIGHT", -50, 0)
    count:SetWidth(25)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    row.count = count
    
    -- Value
    local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    value:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    value:SetWidth(42)
    value:SetJustifyH("RIGHT")
    value:SetTextColor(theme.goldColor.r, theme.goldColor.g, theme.goldColor.b)
    row.value = value
    
    -- Highlight effect
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(theme.rowHighlight.r, theme.rowHighlight.g, theme.rowHighlight.b, theme.rowHighlight.a)
    
    -- Tooltip handling
    row:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Click to link item in chat
    row:SetScript("OnClick", function(self)
        if self.itemLink and IsShiftKeyDown() then
            ChatEdit_InsertLink(self.itemLink)
        end
    end)
    
    return row
end

function addon:CreateMainFrame()
    if self.mainFrame then return end
    
    local theme = self:GetCurrentTheme()
    
    -- Main frame
    local frame = CreateFrame("Frame", "FarmerMainFrame", UIParent, "BackdropTemplate")
    
    -- Get saved size or use defaults
    local savedSize = self:GetSetting("ui.size") or { width = 320, height = 420 }
    frame:SetSize(savedSize.width, savedSize.height)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    
    -- Make frame resizable
    frame:SetResizable(true)
    frame:SetResizeBounds(280, 300, 500, 700)  -- min/max width/height
    
    local pos = self:GetSetting("ui.position")
    frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    
    CreateStyledBackdrop(frame, 0.95)
    
    -- Add subtle gradient at top
    local headerGradient = frame:CreateTexture(nil, "ARTWORK")
    headerGradient:SetHeight(50)
    headerGradient:SetPoint("TOPLEFT", 1, -1)
    headerGradient:SetPoint("TOPRIGHT", -1, -1)
    headerGradient:SetColorTexture(theme.headerGradient.r, theme.headerGradient.g, theme.headerGradient.b, theme.headerGradient.a)
    headerGradient:SetGradient("VERTICAL", CreateColor(theme.headerGradient.r, theme.headerGradient.g, theme.headerGradient.b, 0), CreateColor(theme.headerGradient.r, theme.headerGradient.g, theme.headerGradient.b, theme.headerGradient.a))
    frame.headerGradient = headerGradient
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(theme.titleColor .. theme.titleText .. "|r")
    title:SetFont(title:GetFont(), 14, "OUTLINE")
    frame.title = title
    
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 6, 0)
    subtitle:SetText("Loot Tracker")
    subtitle:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
    frame.subtitle = subtitle
    
    -- Collapse/expand toggle button for items section (in title bar)
    local collapseBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    local isCollapsed = addon:GetSetting("ui.itemsCollapsed") or false
    collapseBtn:SetSize(18, 18)
    collapseBtn:SetPoint("LEFT", subtitle, "RIGHT", 6, 0)
    collapseBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
    })
    collapseBtn:SetBackdropColor(theme.buttonBg.r, theme.buttonBg.g, theme.buttonBg.b, 0.5)
    collapseBtn:SetBackdropBorderColor(theme.buttonBorder.r, theme.buttonBorder.g, theme.buttonBorder.b, 0.5)
    
    local collapseText = collapseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    collapseText:SetPoint("CENTER", 0, 1)
    collapseText:SetFont(collapseText:GetFont(), 14, "OUTLINE")
    collapseText:SetText(isCollapsed and "+" or "-")
    collapseText:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
    collapseBtn.text = collapseText
    frame.collapseBtn = collapseBtn
    frame.collapseText = collapseText
    
    collapseBtn:SetScript("OnEnter", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropColor(t.buttonHoverBg.r, t.buttonHoverBg.g, t.buttonHoverBg.b, 0.7)
        self:SetBackdropBorderColor(t.buttonHoverBorder.r, t.buttonHoverBorder.g, t.buttonHoverBorder.b, 0.7)
        self.text:SetTextColor(t.valueColor.r, t.valueColor.g, t.valueColor.b)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local collapsed = addon:GetSetting("ui.itemsCollapsed") or false
        GameTooltip:SetText(collapsed and "Show looted items" or "Hide looted items", 1, 1, 1)
        GameTooltip:Show()
    end)
    collapseBtn:SetScript("OnLeave", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropColor(t.buttonBg.r, t.buttonBg.g, t.buttonBg.b, 0.5)
        self:SetBackdropBorderColor(t.buttonBorder.r, t.buttonBorder.g, t.buttonBorder.b, 0.5)
        self.text:SetTextColor(t.mutedColor.r, t.mutedColor.g, t.mutedColor.b)
        GameTooltip:Hide()
    end)
    collapseBtn:SetScript("OnClick", function()
        local collapsed = addon:GetSetting("ui.itemsCollapsed") or false
        addon:SetSetting("ui.itemsCollapsed", not collapsed)
        addon:UpdateItemsCollapsedState()
    end)
    
    -- Close button
    local closeBtn = CreateCloseButton(frame)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
        addon:SetSetting("ui.visible", false)
    end)
    
    -- Tab buttons
    local tabHeight = 22
    local activeTab = addon:GetSetting("ui.activeTab") or "loot"
    
    -- Helper function to create tab button
    local function CreateTabButton(parent, text, tabId, xOffset)
        local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
        tab:SetSize(60, tabHeight)
        tab:SetPoint("TOPLEFT", xOffset, -30)
        tab.tabId = tabId
        
        tab:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false,
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        
        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER", 0, 0)
        label:SetText(text)
        tab.label = label
        
        return tab
    end
    
    local lootTab = CreateTabButton(frame, "Loot", "loot", 10)
    local honorTab = CreateTabButton(frame, "Honor", "honor", 72)
    frame.lootTab = lootTab
    frame.honorTab = honorTab
    
    -- Tab styling function
    local function UpdateTabStyles()
        local t = addon:GetCurrentTheme()
        local currentTab = addon:GetSetting("ui.activeTab") or "loot"
        
        -- Loot tab
        if currentTab == "loot" then
            lootTab:SetBackdropColor(t.sectionBg.r, t.sectionBg.g, t.sectionBg.b, 0.8)
            lootTab:SetBackdropBorderColor(t.border.r, t.border.g, t.border.b, 1)
            lootTab.label:SetTextColor(t.valueColor.r, t.valueColor.g, t.valueColor.b)
        else
            lootTab:SetBackdropColor(t.buttonBg.r, t.buttonBg.g, t.buttonBg.b, 0.5)
            lootTab:SetBackdropBorderColor(t.buttonBorder.r, t.buttonBorder.g, t.buttonBorder.b, 0.5)
            lootTab.label:SetTextColor(t.mutedColor.r, t.mutedColor.g, t.mutedColor.b)
        end
        
        -- Honor tab
        if currentTab == "honor" then
            honorTab:SetBackdropColor(t.sectionBg.r, t.sectionBg.g, t.sectionBg.b, 0.8)
            honorTab:SetBackdropBorderColor(t.border.r, t.border.g, t.border.b, 1)
            honorTab.label:SetTextColor(t.valueColor.r, t.valueColor.g, t.valueColor.b)
        else
            honorTab:SetBackdropColor(t.buttonBg.r, t.buttonBg.g, t.buttonBg.b, 0.5)
            honorTab:SetBackdropBorderColor(t.buttonBorder.r, t.buttonBorder.g, t.buttonBorder.b, 0.5)
            honorTab.label:SetTextColor(t.mutedColor.r, t.mutedColor.g, t.mutedColor.b)
        end
    end
    frame.UpdateTabStyles = UpdateTabStyles
    
    -- Tab click handlers
    local function SwitchToTab(tabId)
        addon:SetSetting("ui.activeTab", tabId)
        UpdateTabStyles()
        
        -- Show/hide content frames
        if frame.lootContent then frame.lootContent:SetShown(tabId == "loot") end
        if frame.honorContent then frame.honorContent:SetShown(tabId == "honor") end
        
        -- Update subtitle and collapse button visibility
        if tabId == "loot" then
            frame.subtitle:SetText("Loot Tracker")
            frame.collapseBtn:Show()
            frame.togglePriceBtn:Show()
            frame.lifetimeBtn:Show()
            -- Restore collapsed state for loot tab
            addon:UpdateItemsCollapsedState()
        else
            frame.subtitle:SetText("Honor Tracker")
            frame.collapseBtn:Hide()
            frame.togglePriceBtn:Hide()
            frame.lifetimeBtn:Hide()
            -- Honor tab uses fixed compact height to prevent overlap
            local honorHeight = 220
            frame:SetHeight(honorHeight)
            frame:SetResizeBounds(280, 220, 500, 220)  -- Lock height for honor tab
        end
    end
    frame.SwitchToTab = SwitchToTab
    
    lootTab:SetScript("OnClick", function() SwitchToTab("loot") end)
    honorTab:SetScript("OnClick", function() SwitchToTab("honor") end)
    
    lootTab:SetScript("OnEnter", function(self)
        if addon:GetSetting("ui.activeTab") ~= "loot" then
            local t = addon:GetCurrentTheme()
            self:SetBackdropColor(t.buttonHoverBg.r, t.buttonHoverBg.g, t.buttonHoverBg.b, 0.7)
        end
    end)
    lootTab:SetScript("OnLeave", function(self) UpdateTabStyles() end)
    
    honorTab:SetScript("OnEnter", function(self)
        if addon:GetSetting("ui.activeTab") ~= "honor" then
            local t = addon:GetCurrentTheme()
            self:SetBackdropColor(t.buttonHoverBg.r, t.buttonHoverBg.g, t.buttonHoverBg.b, 0.7)
        end
    end)
    honorTab:SetScript("OnLeave", function(self) UpdateTabStyles() end)
    
    -- Initialize tab styles
    UpdateTabStyles()
    
    --[[ LOOT TAB CONTENT ]]--
    local lootContent = CreateFrame("Frame", nil, frame)
    lootContent:SetPoint("TOPLEFT", 0, -52)
    lootContent:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.lootContent = lootContent
    
    -- Stats section (now parented to lootContent)
    local statsSection = CreateFrame("Frame", nil, lootContent, "BackdropTemplate")
    statsSection:SetPoint("TOPLEFT", 10, 0)
    statsSection:SetPoint("TOPRIGHT", -10, 0)
    statsSection:SetHeight(105)
    CreateStyledBackdrop(statsSection, 0.5, true)
    frame.statsSection = statsSection
    
    -- Total value (big display with both vendor and AH)
    local totalLabel = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalLabel:SetPoint("TOPLEFT", 12, -6)
    totalLabel:SetText("SESSION TOTAL")
    totalLabel:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
    totalLabel:SetFont(totalLabel:GetFont(), 8)
    frame.totalLabel = totalLabel
    
    -- Vendor total line
    local vendorLabel = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    vendorLabel:SetPoint("TOPLEFT", 12, -17)
    vendorLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    vendorLabel:SetFont(vendorLabel:GetFont(), 8)
    vendorLabel:SetText("Vendor:")
    frame.vendorLabel = vendorLabel
    
    local vendorValue = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    vendorValue:SetPoint("LEFT", vendorLabel, "RIGHT", 4, 0)
    vendorValue:SetTextColor(theme.goldColor.r, theme.goldColor.g, theme.goldColor.b)
    vendorValue:SetFont(vendorValue:GetFont(), 13)
    vendorValue:SetText("0g 0s 0c")
    frame.vendorTotalValue = vendorValue
    
    -- AH total line
    local ahLabel = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ahLabel:SetPoint("TOPLEFT", 12, -32)
    ahLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    ahLabel:SetFont(ahLabel:GetFont(), 8)
    ahLabel:SetText("AH:")
    frame.ahLabel = ahLabel
    
    local ahValue = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ahValue:SetPoint("LEFT", ahLabel, "RIGHT", 4, 0)
    ahValue:SetTextColor(theme.ahColor.r, theme.ahColor.g, theme.ahColor.b)
    ahValue:SetFont(ahValue:GetFont(), 13)
    ahValue:SetText("0g 0s 0c")
    frame.ahTotalValue = ahValue
    
    local separator = CreateSeparator(statsSection, -45)
    frame.separator = separator
    
    -- Stats grid
    local goldLabel, goldValue = CreateStatRow(statsSection, "Raw Gold", -55)
    frame.sessionGoldLabel = goldLabel
    frame.sessionGold = goldValue
    
    local itemsLabel, itemsValue = CreateStatRow(statsSection, "Items Value", -70)
    frame.itemsValueLabel = itemsLabel
    frame.itemsValue = itemsValue
    
    local gphLabel, gphValue = CreateStatRow(statsSection, "Gold/Hour", -85)
    frame.gphLabel = gphLabel
    frame.gph = gphValue
    
    -- Duration and lifetime on right side
    local durationLabel = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationLabel:SetPoint("TOPRIGHT", -14, -8)
    durationLabel:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
    durationLabel:SetFont(durationLabel:GetFont(), 9)
    durationLabel:SetText("DURATION")
    frame.durationLabel = durationLabel
    
    local durationValue = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationValue:SetPoint("TOPRIGHT", -14, -20)
    durationValue:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
    durationValue:SetText("0m")
    frame.duration = durationValue
    
    -- Items section header
    local itemsHeader = lootContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemsHeader:SetPoint("TOPLEFT", 14, -115)
    itemsHeader:SetText("LOOTED ITEMS")
    itemsHeader:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
    itemsHeader:SetFont(itemsHeader:GetFont(), 9)
    frame.itemsHeader = itemsHeader
    
    -- Item count (anchored after header text)
    local itemCountText = lootContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemCountText:SetPoint("LEFT", itemsHeader, "RIGHT", 4, 0)
    itemCountText:SetTextColor(theme.mutedColor.r - 0.1, theme.mutedColor.g - 0.1, theme.mutedColor.b - 0.1)
    itemCountText:SetText("(0)")
    frame.itemCountText = itemCountText
    
    -- Controls row on the right side (anchored from right, relative to each other)
    -- Order from right to left: [Sort Dir] [Sort Dropdown] [Filter Dropdown]
    
    -- Sort direction button (rightmost)
    local sortDirBtn = CreateFrame("Button", nil, lootContent, "BackdropTemplate")
    sortDirBtn:SetSize(20, 18)
    sortDirBtn:SetPoint("TOPRIGHT", -10, -113)
    sortDirBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
    })
    sortDirBtn:SetBackdropColor(theme.dropdownBg.r, theme.dropdownBg.g, theme.dropdownBg.b, theme.dropdownBg.a)
    sortDirBtn:SetBackdropBorderColor(theme.dropdownBorder.r, theme.dropdownBorder.g, theme.dropdownBorder.b, theme.dropdownBorder.a)
    
    local sortDirText = sortDirBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sortDirText:SetPoint("CENTER", 0, 0)
    sortDirText:SetText(addon.sortAscending and "^" or "v")
    sortDirText:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    frame.sortDirText = sortDirText
    frame.sortDirBtn = sortDirBtn
    
    sortDirBtn:SetScript("OnClick", function()
        addon.sortAscending = not addon.sortAscending
        addon:SetSetting("ui.sortAscending", addon.sortAscending)
        sortDirText:SetText(addon.sortAscending and "^" or "v")
        addon:UpdateItemList()
    end)
    sortDirBtn:SetScript("OnEnter", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropBorderColor(t.buttonHoverBorder.r, t.buttonHoverBorder.g, t.buttonHoverBorder.b, t.buttonHoverBorder.a)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(addon.sortAscending and "Ascending" or "Descending", 1, 1, 1)
        GameTooltip:Show()
    end)
    sortDirBtn:SetScript("OnLeave", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropBorderColor(t.dropdownBorder.r, t.dropdownBorder.g, t.dropdownBorder.b, t.dropdownBorder.a)
        GameTooltip:Hide()
    end)
    
    -- Sort dropdown (anchored to left of sort direction button)
    local sortDropdown = CreateSortDropdown(lootContent)
    sortDropdown:SetPoint("RIGHT", sortDirBtn, "LEFT", -3, 0)
    frame.sortDropdown = sortDropdown
    
    -- Filter dropdown button (anchored to left of sort dropdown)
    local filterBtn = CreateFrame("Button", nil, lootContent, "BackdropTemplate")
    filterBtn:SetSize(50, 18)
    filterBtn:SetPoint("RIGHT", sortDropdown, "LEFT", -3, 0)
    filterBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
    })
    filterBtn:SetBackdropColor(theme.dropdownBg.r, theme.dropdownBg.g, theme.dropdownBg.b, theme.dropdownBg.a)
    filterBtn:SetBackdropBorderColor(theme.dropdownBorder.r, theme.dropdownBorder.g, theme.dropdownBorder.b, theme.dropdownBorder.a)
    
    local filterBtnText = filterBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterBtnText:SetPoint("LEFT", 6, 0)
    filterBtnText:SetText("Filter")
    filterBtnText:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
    filterBtn.text = filterBtnText
    
    local filterArrow = filterBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterArrow:SetPoint("RIGHT", -4, 0)
    filterArrow:SetText("v")
    filterArrow:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
    filterBtn.arrow = filterArrow
    
    frame.filterBtn = filterBtn
    
    -- Filter dropdown menu
    local filterMenu = CreateFrame("Frame", "FarmerFilterMenu", filterBtn, "BackdropTemplate")
    filterMenu:SetPoint("TOP", filterBtn, "BOTTOM", 0, -2)
    filterMenu:SetSize(160, 90)
    filterMenu:SetFrameStrata("DIALOG")
    filterMenu:Hide()
    
    filterMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
    })
    filterMenu:SetBackdropColor(theme.dropdownMenuBg.r, theme.dropdownMenuBg.g, theme.dropdownMenuBg.b, theme.dropdownMenuBg.a)
    filterMenu:SetBackdropBorderColor(theme.dropdownBorder.r, theme.dropdownBorder.g, theme.dropdownBorder.b, theme.dropdownBorder.a)
    
    frame.filterMenu = filterMenu
    
    -- Helper function to create checkbox items
    local function CreateFilterCheckbox(parent, label, filterKey, yOffset, iconTexture)
        local checkFrame = CreateFrame("Button", nil, parent)
        checkFrame:SetSize(150, 18)
        checkFrame:SetPoint("TOPLEFT", 5, yOffset)
        checkFrame.filterKey = filterKey
        
        -- Checkbox box (background)
        local checkBorder = checkFrame:CreateTexture(nil, "BACKGROUND")
        checkBorder:SetSize(14, 14)
        checkBorder:SetPoint("LEFT", 2, 0)
        checkBorder:SetColorTexture(theme.buttonBorder.r, theme.buttonBorder.g, theme.buttonBorder.b, 1)
        checkFrame.checkBorder = checkBorder
        
        local checkbox = checkFrame:CreateTexture(nil, "ARTWORK")
        checkbox:SetSize(12, 12)
        checkbox:SetPoint("CENTER", checkBorder, "CENTER", 0, 0)
        checkbox:SetColorTexture(theme.buttonBg.r, theme.buttonBg.g, theme.buttonBg.b, 1)
        checkFrame.checkbox = checkbox
        
        -- Checkmark (using a texture instead of unicode)
        local checkmark = checkFrame:CreateTexture(nil, "OVERLAY")
        checkmark:SetSize(10, 10)
        checkmark:SetPoint("CENTER", checkbox, "CENTER", 0, 0)
        checkmark:SetTexture("Interface\\BUTTONS\\UI-CheckBox-Check")
        checkmark:SetVertexColor(0.2, 1, 0.2)
        checkFrame.checkmark = checkmark
        
        -- Icon texture
        local iconTex = checkFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(14, 14)
        iconTex:SetPoint("LEFT", checkBorder, "RIGHT", 4, 0)
        iconTex:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        checkFrame.iconTex = iconTex
        
        -- Label
        local labelText = checkFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelText:SetPoint("LEFT", iconTex, "RIGHT", 4, 0)
        labelText:SetText(label)
        labelText:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
        checkFrame.label = labelText
        
        -- Highlight
        local highlight = checkFrame:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(theme.dropdownHighlight.r, theme.dropdownHighlight.g, theme.dropdownHighlight.b, theme.dropdownHighlight.a)
        
        -- Update visual state
        local function UpdateCheckState()
            local enabled = addon:GetSetting("filters." .. filterKey)
            if enabled == nil then enabled = true end
            checkFrame.checkmark:SetShown(enabled)
        end
        checkFrame.UpdateCheckState = UpdateCheckState
        UpdateCheckState()
        
        -- Click handler
        checkFrame:SetScript("OnClick", function(self)
            local current = addon:GetSetting("filters." .. self.filterKey)
            if current == nil then current = true end
            addon:SetSetting("filters." .. self.filterKey, not current)
            UpdateCheckState()
            addon:UpdateFilterDropdown()
            addon:UpdateMainFrame()
        end)
        
        return checkFrame
    end
    
    -- Helper function to create section headers
    local function CreateSectionHeader(parent, text, yOffset)
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", 8, yOffset)
        header:SetText(text)
        header:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
        header:SetFont(header:GetFont(), 8, "OUTLINE")
        return header
    end
    
    -- Source filters header
    local sourceHeader = CreateSectionHeader(filterMenu, "LOOT SOURCE", -6)
    filterMenu.sourceHeader = sourceHeader
    
    -- Separator line after header
    local headerLine = filterMenu:CreateTexture(nil, "ARTWORK")
    headerLine:SetHeight(1)
    headerLine:SetPoint("TOPLEFT", 6, -18)
    headerLine:SetPoint("TOPRIGHT", -6, -18)
    headerLine:SetColorTexture(theme.separator.r, theme.separator.g, theme.separator.b, theme.separator.a)
    filterMenu.headerLine = headerLine
    
    -- Pickup checkbox (sword icon)
    local pickupCheck = CreateFilterCheckbox(filterMenu, "Pickup (mobs/chests)", "showPickup", -24, "Interface\\Icons\\INV_Sword_04")
    filterMenu.pickupCheck = pickupCheck
    
    -- Gathered checkbox (mining pick icon)
    local gatheredCheck = CreateFilterCheckbox(filterMenu, "Gathered (nodes)", "showGathered", -44, "Interface\\Icons\\Trade_Mining")
    filterMenu.gatheredCheck = gatheredCheck
    
    -- Separator before quick actions
    local actionLine = filterMenu:CreateTexture(nil, "ARTWORK")
    actionLine:SetHeight(1)
    actionLine:SetPoint("TOPLEFT", 6, -66)
    actionLine:SetPoint("TOPRIGHT", -6, -66)
    actionLine:SetColorTexture(theme.separator.r, theme.separator.g, theme.separator.b, theme.separator.a)
    filterMenu.actionLine = actionLine
    
    -- Show All / Hide All buttons
    local showAllBtn = CreateFrame("Button", nil, filterMenu)
    showAllBtn:SetSize(70, 16)
    showAllBtn:SetPoint("TOPLEFT", 6, -72)
    local showAllText = showAllBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showAllText:SetPoint("LEFT", 2, 0)
    showAllText:SetText("Show All")
    showAllText:SetTextColor(0.4, 0.8, 0.4)
    local showAllHighlight = showAllBtn:CreateTexture(nil, "HIGHLIGHT")
    showAllHighlight:SetAllPoints()
    showAllHighlight:SetColorTexture(theme.dropdownHighlight.r, theme.dropdownHighlight.g, theme.dropdownHighlight.b, theme.dropdownHighlight.a)
    showAllBtn:SetScript("OnClick", function()
        addon:SetSetting("filters.showPickup", true)
        addon:SetSetting("filters.showGathered", true)
        pickupCheck:UpdateCheckState()
        gatheredCheck:UpdateCheckState()
        addon:UpdateFilterDropdown()
        addon:UpdateMainFrame()
    end)
    
    local hideAllBtn = CreateFrame("Button", nil, filterMenu)
    hideAllBtn:SetSize(70, 16)
    hideAllBtn:SetPoint("TOPRIGHT", -6, -72)
    local hideAllText = hideAllBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideAllText:SetPoint("RIGHT", -2, 0)
    hideAllText:SetText("Hide All")
    hideAllText:SetTextColor(0.8, 0.4, 0.4)
    local hideAllHighlight = hideAllBtn:CreateTexture(nil, "HIGHLIGHT")
    hideAllHighlight:SetAllPoints()
    hideAllHighlight:SetColorTexture(theme.dropdownHighlight.r, theme.dropdownHighlight.g, theme.dropdownHighlight.b, theme.dropdownHighlight.a)
    hideAllBtn:SetScript("OnClick", function()
        addon:SetSetting("filters.showPickup", false)
        addon:SetSetting("filters.showGathered", false)
        pickupCheck:UpdateCheckState()
        gatheredCheck:UpdateCheckState()
        addon:UpdateFilterDropdown()
        addon:UpdateMainFrame()
    end)
    
    -- Toggle menu visibility
    filterBtn:SetScript("OnClick", function()
        if filterMenu:IsShown() then
            filterMenu:Hide()
        else
            filterMenu:Show()
        end
    end)
    
    filterBtn:SetScript("OnEnter", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropBorderColor(t.buttonHoverBorder.r, t.buttonHoverBorder.g, t.buttonHoverBorder.b, t.buttonHoverBorder.a)
    end)
    
    filterBtn:SetScript("OnLeave", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropBorderColor(t.dropdownBorder.r, t.dropdownBorder.g, t.dropdownBorder.b, t.dropdownBorder.a)
    end)
    
    -- Close menu when clicking outside
    filterMenu:SetScript("OnShow", function(self)
        self:SetPropagateKeyboardInput(true)
    end)
    
    -- Column headers
    local headerRow = CreateFrame("Frame", nil, lootContent, "BackdropTemplate")
    headerRow:SetPoint("TOPLEFT", 10, -135)
    headerRow:SetPoint("TOPRIGHT", -10, -135)
    headerRow:SetHeight(18)
    headerRow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    headerRow:SetBackdropColor(theme.headerRowBg.r, theme.headerRowBg.g, theme.headerRowBg.b, theme.headerRowBg.a)
    frame.headerRow = headerRow
    
    local colItem = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colItem:SetPoint("LEFT", 30, 0)
    colItem:SetText("Item")
    colItem:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    colItem:SetFont(colItem:GetFont(), 9)
    frame.colItem = colItem
    
    local colQty = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colQty:SetPoint("RIGHT", -52, 0)
    colQty:SetText("Qty")
    colQty:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    colQty:SetFont(colQty:GetFont(), 9)
    frame.colQty = colQty
    
    local colValue = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colValue:SetPoint("RIGHT", -8, 0)
    colValue:SetText("Value")
    colValue:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    colValue:SetFont(colValue:GetFont(), 9)
    frame.colValue = colValue
    
    -- Scrollable item list
    local scrollFrame = CreateFrame("ScrollFrame", "FarmerScrollFrame", lootContent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -155)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 50)
    
    -- Style the scroll bar
    local scrollBar = _G["FarmerScrollFrameScrollBar"]
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 2, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 2, 16)
    end
    
    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollContent)
    frame.scrollContent = scrollContent
    frame.scrollFrame = scrollFrame
    
    -- Item rows pool
    frame.itemRows = {}
    
    --[[ HONOR TAB CONTENT ]]--
    local honorContent = CreateFrame("Frame", nil, frame)
    honorContent:SetPoint("TOPLEFT", 0, -52)
    honorContent:SetPoint("BOTTOMRIGHT", 0, 0)
    honorContent:Hide()  -- Start hidden
    frame.honorContent = honorContent
    
    -- Honor stats section
    local honorStatsSection = CreateFrame("Frame", nil, honorContent, "BackdropTemplate")
    honorStatsSection:SetPoint("TOPLEFT", 10, 0)
    honorStatsSection:SetPoint("TOPRIGHT", -10, 0)
    honorStatsSection:SetHeight(115)
    CreateStyledBackdrop(honorStatsSection, 0.5, true)
    frame.honorStatsSection = honorStatsSection
    
    -- Session Honor Header
    local honorSessionLabel = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    honorSessionLabel:SetPoint("TOPLEFT", 12, -6)
    honorSessionLabel:SetText("SESSION")
    honorSessionLabel:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
    honorSessionLabel:SetFont(honorSessionLabel:GetFont(), 8)
    frame.honorSessionLabel = honorSessionLabel
    
    -- Session Honor Gained
    local honorGainedLabel = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    honorGainedLabel:SetPoint("TOPLEFT", 12, -18)
    honorGainedLabel:SetText("Honor:")
    honorGainedLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    frame.honorGainedLabel = honorGainedLabel
    
    local honorGainedValue = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    honorGainedValue:SetPoint("LEFT", honorGainedLabel, "RIGHT", 4, 0)
    honorGainedValue:SetTextColor(0.8, 0.2, 0.8)  -- Purple for honor
    honorGainedValue:SetFont(honorGainedValue:GetFont(), 13)
    honorGainedValue:SetText("0")
    frame.honorGainedValue = honorGainedValue
    
    -- Session HKs
    local hksLabel = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hksLabel:SetPoint("TOPLEFT", 12, -34)
    hksLabel:SetText("HKs:")
    hksLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    frame.hksLabel = hksLabel
    
    local hksValue = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hksValue:SetPoint("LEFT", hksLabel, "RIGHT", 4, 0)
    hksValue:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
    hksValue:SetFont(hksValue:GetFont(), 12)
    hksValue:SetText("0")
    frame.hksValue = hksValue
    
    -- Honor per hour
    local hphLabel = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hphLabel:SetPoint("TOPLEFT", 12, -50)
    hphLabel:SetText("Honor/hr:")
    hphLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    frame.hphLabel = hphLabel
    
    local hphValue = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hphValue:SetPoint("LEFT", hphLabel, "RIGHT", 4, 0)
    hphValue:SetTextColor(0.8, 0.2, 0.8)
    hphValue:SetFont(hphValue:GetFont(), 12)
    hphValue:SetText("0")
    frame.hphValue = hphValue
    
    -- Separator
    local honorSeparator = honorStatsSection:CreateTexture(nil, "ARTWORK")
    honorSeparator:SetHeight(1)
    honorSeparator:SetPoint("LEFT", 12, 0)
    honorSeparator:SetPoint("RIGHT", -12, 0)
    honorSeparator:SetPoint("TOP", 0, -66)
    honorSeparator:SetColorTexture(theme.separator.r, theme.separator.g, theme.separator.b, theme.separator.a)
    frame.honorSeparator = honorSeparator
    
    -- Character Honor Header
    local honorLifetimeLabel = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    honorLifetimeLabel:SetPoint("TOPLEFT", 12, -72)
    honorLifetimeLabel:SetText("CHARACTER")
    honorLifetimeLabel:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
    honorLifetimeLabel:SetFont(honorLifetimeLabel:GetFont(), 8)
    frame.honorLifetimeLabel = honorLifetimeLabel
    
    -- Character Current Honor
    local lifetimeHonorLabel = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lifetimeHonorLabel:SetPoint("TOPLEFT", 12, -84)
    lifetimeHonorLabel:SetText("Honor:")
    lifetimeHonorLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    frame.lifetimeHonorLabel = lifetimeHonorLabel
    
    local lifetimeHonorValue = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lifetimeHonorValue:SetPoint("LEFT", lifetimeHonorLabel, "RIGHT", 4, 0)
    lifetimeHonorValue:SetTextColor(0.8, 0.2, 0.8)
    lifetimeHonorValue:SetText("0")
    frame.lifetimeHonorValue = lifetimeHonorValue
    
    -- Character Total HKs
    local lifetimeHksLabel = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lifetimeHksLabel:SetPoint("TOPLEFT", 12, -100)
    lifetimeHksLabel:SetText("Total HKs:")
    lifetimeHksLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b)
    frame.lifetimeHksLabel = lifetimeHksLabel
    
    local lifetimeHksValue = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lifetimeHksValue:SetPoint("LEFT", lifetimeHksLabel, "RIGHT", 4, 0)
    lifetimeHksValue:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
    lifetimeHksValue:SetText("0")
    frame.lifetimeHksValue = lifetimeHksValue
    
    -- Duration display on right side of honor tab
    local honorDurationLabel = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    honorDurationLabel:SetPoint("TOPRIGHT", -14, -6)
    honorDurationLabel:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
    honorDurationLabel:SetFont(honorDurationLabel:GetFont(), 8)
    honorDurationLabel:SetText("DURATION")
    frame.honorDurationLabel = honorDurationLabel
    
    local honorDurationValue = honorStatsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    honorDurationValue:SetPoint("TOPRIGHT", -14, -18)
    honorDurationValue:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
    honorDurationValue:SetText("0m")
    frame.honorDuration = honorDurationValue
    
    -- Show correct tab on load
    local currentTab = addon:GetSetting("ui.activeTab") or "loot"
    lootContent:SetShown(currentTab == "loot")
    honorContent:SetShown(currentTab == "honor")
    if currentTab == "honor" then
        frame.subtitle:SetText("Honor Tracker")
        frame.collapseBtn:Hide()
    end
    
    -- Bottom section with buttons
    local bottomSection = CreateFrame("Frame", nil, frame)
    bottomSection:SetPoint("BOTTOMLEFT", 10, 10)
    bottomSection:SetPoint("BOTTOMRIGHT", -10, 10)
    bottomSection:SetHeight(32)
    
    -- Theme button
    local themeBtn = CreateStyledButton(bottomSection, "Theme", 55, 24)
    themeBtn:SetPoint("LEFT", 0, 0)
    themeBtn:SetScript("OnClick", function()
        addon:CycleTheme()
        addon:ApplyTheme()
    end)
    themeBtn:SetScript("OnEnter", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropColor(t.buttonHoverBg.r, t.buttonHoverBg.g, t.buttonHoverBg.b, t.buttonHoverBg.a)
        self:SetBackdropBorderColor(t.buttonHoverBorder.r, t.buttonHoverBorder.g, t.buttonHoverBorder.b, t.buttonHoverBorder.a)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local themeSetting = addon:GetSetting("ui.theme") or "auto"
        local themeNames = { auto = "Auto (Faction)", horde = "Horde", alliance = "Alliance", dark = "Dark" }
        GameTooltip:SetText("Current: " .. themeNames[themeSetting] .. "\nClick to cycle themes", 1, 1, 1)
        GameTooltip:Show()
    end)
    themeBtn:SetScript("OnLeave", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropColor(t.buttonBg.r, t.buttonBg.g, t.buttonBg.b, t.buttonBg.a)
        self:SetBackdropBorderColor(t.buttonBorder.r, t.buttonBorder.g, t.buttonBorder.b, t.buttonBorder.a)
        GameTooltip:Hide()
    end)
    frame.themeBtn = themeBtn
    
    -- Toggle AH/Vendor button
    local togglePriceBtn = CreateStyledButton(bottomSection, "AH Prices", 70, 24)
    togglePriceBtn:SetPoint("LEFT", themeBtn, "RIGHT", 6, 0)
    togglePriceBtn:SetScript("OnClick", function()
        local current = addon:GetSetting("features.useAHPrices")
        addon:SetSetting("features.useAHPrices", not current)
        addon:UpdateMainFrame()
    end)
    togglePriceBtn:SetScript("OnEnter", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropColor(t.buttonHoverBg.r, t.buttonHoverBg.g, t.buttonHoverBg.b, t.buttonHoverBg.a)
        self:SetBackdropBorderColor(t.buttonHoverBorder.r, t.buttonHoverBorder.g, t.buttonHoverBorder.b, t.buttonHoverBorder.a)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Toggle between AH and Vendor prices", 1, 1, 1)
        GameTooltip:Show()
    end)
    togglePriceBtn:SetScript("OnLeave", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropColor(t.buttonBg.r, t.buttonBg.g, t.buttonBg.b, t.buttonBg.a)
        self:SetBackdropBorderColor(t.buttonBorder.r, t.buttonBorder.g, t.buttonBorder.b, t.buttonBorder.a)
        GameTooltip:Hide()
    end)
    frame.togglePriceBtn = togglePriceBtn
    
    -- Reset session button
    local resetBtn = CreateStyledButton(bottomSection, "Reset", 55, 24)
    resetBtn:SetPoint("RIGHT", 0, 0)
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("FARMER_RESET_CONFIRM")
    end)
    resetBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.35, 0.15, 0.15, 1)
        self:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset session data", 1, 1, 1)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropColor(t.buttonBg.r, t.buttonBg.g, t.buttonBg.b, t.buttonBg.a)
        self:SetBackdropBorderColor(t.buttonBorder.r, t.buttonBorder.g, t.buttonBorder.b, t.buttonBorder.a)
        GameTooltip:Hide()
    end)
    frame.resetBtn = resetBtn
    
    -- Lifetime stats button
    local lifetimeBtn = CreateStyledButton(bottomSection, "Lifetime", 60, 24)
    lifetimeBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)
    lifetimeBtn:SetScript("OnClick", function()
        addon:ShowLifetimePopup()
    end)
    lifetimeBtn:SetScript("OnEnter", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropColor(t.buttonHoverBg.r, t.buttonHoverBg.g, t.buttonHoverBg.b, t.buttonHoverBg.a)
        self:SetBackdropBorderColor(t.buttonHoverBorder.r, t.buttonHoverBorder.g, t.buttonHoverBorder.b, t.buttonHoverBorder.a)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("View lifetime statistics", 1, 1, 1)
        GameTooltip:Show()
    end)
    lifetimeBtn:SetScript("OnLeave", function(self)
        local t = addon:GetCurrentTheme()
        self:SetBackdropColor(t.buttonBg.r, t.buttonBg.g, t.buttonBg.b, t.buttonBg.a)
        self:SetBackdropBorderColor(t.buttonBorder.r, t.buttonBorder.g, t.buttonBorder.b, t.buttonBorder.a)
        GameTooltip:Hide()
    end)
    frame.lifetimeBtn = lifetimeBtn
    
    -- Make frame movable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    
    frame:SetScript("OnDragStart", function(self)
        if not addon:GetSetting("ui.locked") then
            self:StartMoving()
        end
    end)
    
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        addon:SetSetting("ui.position", {
            point = point,
            relativePoint = relativePoint,
            xOfs = xOfs,
            yOfs = yOfs,
        })
    end)
    
    -- Create resize handle
    local resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    
    resizeHandle:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not addon:GetSetting("ui.locked") then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    
    resizeHandle:SetScript("OnMouseUp", function(self, button)
        frame:StopMovingOrSizing()
        -- Save new size
        local width, height = frame:GetSize()
        addon:SetSetting("ui.size", {
            width = math.floor(width),
            height = math.floor(height),
        })
        -- Update scroll content width
        if frame.scrollContent then
            frame.scrollContent:SetWidth(frame.scrollFrame:GetWidth())
        end
    end)
    
    frame.resizeHandle = resizeHandle
    
    -- Apply scale
    frame:SetScale(self:GetSetting("ui.scale"))
    
    -- Start hidden
    frame:Hide()
    
    self.mainFrame = frame
    
    -- Apply initial collapsed state
    self:UpdateItemsCollapsedState()
    
    -- Create reset confirmation dialog
    StaticPopupDialogs["FARMER_RESET_CONFIRM"] = {
        text = "Reset session data? This cannot be undone.",
        button1 = "Reset",
        button2 = "Cancel",
        OnAccept = function()
            addon:ResetSession()
            addon:UpdateMainFrame()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    -- Override slash command
    local oldHandler = SlashCmdList["LOOTSESH"]
    SlashCmdList["LOOTSESH"] = function(msg)
        local cmd = msg:match("^(%S*)"):lower()
        if cmd == "show" or cmd == "toggle" or cmd == "" then
            if cmd == "" then
                -- Default action: show/hide the frame
            end
            if frame:IsShown() then
                frame:Hide()
                addon:SetSetting("ui.visible", false)
            else
                frame:Show()
                addon:SetSetting("ui.visible", true)
                addon:UpdateMainFrame()
            end
        else
            oldHandler(msg)
        end
    end
    
    addon:Debug("Enhanced main frame created")
end

-- Show lifetime stats popup
function addon:ShowLifetimePopup()
    local lifetime = self.charDB.lifetime
    local useAH = self:GetSetting("features.useAHPrices")
    local itemValue = useAH and lifetime.totalAHValue or lifetime.totalVendorValue
    local priceType = useAH and "AH" or "Vendor"
    local total = lifetime.rawGoldLooted + itemValue
    
    local msg = string.format(
        "|cff9999ff=== Lifetime Statistics ===|r\n\n" ..
        "Total Items Looted: |cffffffff%d|r\n" ..
        "Raw Gold: |cffffd700%s|r\n" ..
        "Items (%s): |cffffd700%s|r\n\n" ..
        "|cffffd700Total: %s|r",
        lifetime.totalItemsLooted,
        self.utils.FormatMoney(lifetime.rawGoldLooted),
        priceType,
        self.utils.FormatMoney(itemValue),
        self.utils.FormatMoney(total)
    )
    
    -- Simple message display
    message(msg)
end

-- Update filter dropdown visual states
function addon:UpdateFilterDropdown()
    local frame = self.mainFrame
    if not frame or not frame.filterBtn then return end
    
    local theme = self:GetCurrentTheme()
    
    -- Count active filters
    local showPickup = self:GetSetting("filters.showPickup")
    local showGathered = self:GetSetting("filters.showGathered")
    if showPickup == nil then showPickup = true end
    if showGathered == nil then showGathered = true end
    
    local activeCount = 0
    if showPickup then activeCount = activeCount + 1 end
    if showGathered then activeCount = activeCount + 1 end
    
    -- Update button text to show filter status
    local filterText = "Filter"
    if activeCount == 0 then
        filterText = "Filter (0)"
        frame.filterBtn.text:SetTextColor(0.8, 0.4, 0.4)
    elseif activeCount < 2 then
        filterText = "Filter (" .. activeCount .. ")"
        frame.filterBtn.text:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
    else
        filterText = "Filter"
        frame.filterBtn.text:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
    end
    frame.filterBtn.text:SetText(filterText)
    
    -- Update checkbox states if menu exists
    if frame.filterMenu then
        if frame.filterMenu.pickupCheck and frame.filterMenu.pickupCheck.UpdateCheckState then
            frame.filterMenu.pickupCheck:UpdateCheckState()
        end
        if frame.filterMenu.gatheredCheck and frame.filterMenu.gatheredCheck.UpdateCheckState then
            frame.filterMenu.gatheredCheck:UpdateCheckState()
        end
    end
end

-- Legacy function for compatibility
function addon:UpdateFilterButtons()
    self:UpdateFilterDropdown()
end

-- Update items section collapsed state
function addon:UpdateItemsCollapsedState()
    local frame = self.mainFrame
    if not frame then return end
    
    local theme = self:GetCurrentTheme()
    local collapsed = self:GetSetting("ui.itemsCollapsed") or false
    local activeTab = self:GetSetting("ui.activeTab") or "loot"
    
    -- Update collapse button text
    if frame.collapseText then
        frame.collapseText:SetText(collapsed and "+" or "-")
    end
    
    -- Show/hide entire items section (header, count, controls, list)
    if frame.itemsHeader then frame.itemsHeader:SetShown(not collapsed) end
    if frame.itemCountText then frame.itemCountText:SetShown(not collapsed) end
    if frame.filterBtn then frame.filterBtn:SetShown(not collapsed) end
    if frame.sortDropdown then frame.sortDropdown:SetShown(not collapsed) end
    if frame.sortDirBtn then frame.sortDirBtn:SetShown(not collapsed) end
    if frame.headerRow then frame.headerRow:SetShown(not collapsed) end
    if frame.scrollFrame then frame.scrollFrame:SetShown(not collapsed) end
    
    -- Close any open menus when collapsing
    if collapsed then
        if frame.filterMenu then frame.filterMenu:Hide() end
        if frame.sortDropdown and frame.sortDropdown.menu then frame.sortDropdown.menu:Hide() end
    end
    
    -- Only adjust frame size if we're on the loot tab
    if activeTab == "loot" then
        -- Get saved size for expanded state
        local savedSize = self:GetSetting("ui.size") or { width = 320, height = 420 }
        
        -- Adjust frame size based on collapsed state
        if collapsed then
            -- Collapsed: compact height just showing stats + expand button + bottom buttons
            local collapsedHeight = 210  -- Title + tabs + Stats + padding + buttons + margins
            frame:SetHeight(collapsedHeight)
            frame:SetResizeBounds(280, collapsedHeight, 500, collapsedHeight)  -- Lock height when collapsed
        else
            -- Expanded: restore saved size and normal resize bounds
            frame:SetHeight(savedSize.height)
            frame:SetResizeBounds(280, 300, 500, 700)
        end
    end
end

-- Apply theme to all UI elements
function addon:ApplyTheme()
    local frame = self.mainFrame
    if not frame then return end
    
    local theme = self:GetCurrentTheme()
    
    -- Main frame background and border
    frame:SetBackdropColor(theme.background.r, theme.background.g, theme.background.b, theme.background.a)
    frame:SetBackdropBorderColor(theme.border.r, theme.border.g, theme.border.b, theme.border.a)
    
    -- Header gradient
    if frame.headerGradient then
        frame.headerGradient:SetColorTexture(theme.headerGradient.r, theme.headerGradient.g, theme.headerGradient.b, theme.headerGradient.a)
        frame.headerGradient:SetGradient("VERTICAL", CreateColor(theme.headerGradient.r, theme.headerGradient.g, theme.headerGradient.b, 0), CreateColor(theme.headerGradient.r, theme.headerGradient.g, theme.headerGradient.b, theme.headerGradient.a))
    end
    
    -- Title
    if frame.title then
        frame.title:SetText(theme.titleColor .. theme.titleText .. "|r")
    end
    if frame.subtitle then
        frame.subtitle:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
    end
    
    -- Stats section
    if frame.statsSection then
        frame.statsSection:SetBackdropColor(theme.sectionBg.r, theme.sectionBg.g, theme.sectionBg.b, theme.sectionBg.a)
        frame.statsSection:SetBackdropBorderColor(theme.border.r, theme.border.g, theme.border.b, theme.border.a)
    end
    
    -- Labels and values
    if frame.totalLabel then frame.totalLabel:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b) end
    if frame.vendorLabel then frame.vendorLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.vendorTotalValue then frame.vendorTotalValue:SetTextColor(theme.goldColor.r, theme.goldColor.g, theme.goldColor.b) end
    if frame.ahLabel then frame.ahLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.ahTotalValue then frame.ahTotalValue:SetTextColor(theme.ahColor.r, theme.ahColor.g, theme.ahColor.b) end
    
    -- Stat row labels and values
    if frame.sessionGoldLabel then frame.sessionGoldLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.sessionGold then frame.sessionGold:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b) end
    if frame.itemsValueLabel then frame.itemsValueLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.itemsValue then frame.itemsValue:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b) end
    if frame.gphLabel then frame.gphLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.gph then frame.gph:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b) end
    
    -- Separator
    if frame.separator then
        frame.separator:SetColorTexture(theme.separator.r, theme.separator.g, theme.separator.b, theme.separator.a)
    end
    
    -- Duration
    if frame.durationLabel then frame.durationLabel:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b) end
    if frame.duration then frame.duration:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b) end
    
    -- Items header
    if frame.itemsHeader then frame.itemsHeader:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b) end
    if frame.itemCountText then frame.itemCountText:SetTextColor(theme.mutedColor.r - 0.1, theme.mutedColor.g - 0.1, theme.mutedColor.b - 0.1) end
    if frame.sortLabel then frame.sortLabel:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b) end
    
    -- Collapse button
    if frame.collapseBtn then
        frame.collapseBtn:SetBackdropColor(theme.buttonBg.r, theme.buttonBg.g, theme.buttonBg.b, 0.5)
        frame.collapseBtn:SetBackdropBorderColor(theme.buttonBorder.r, theme.buttonBorder.g, theme.buttonBorder.b, 0.5)
    end
    if frame.collapseText then frame.collapseText:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b) end
    
    -- Filter dropdown
    if frame.filterBtn then
        frame.filterBtn:SetBackdropColor(theme.dropdownBg.r, theme.dropdownBg.g, theme.dropdownBg.b, theme.dropdownBg.a)
        frame.filterBtn:SetBackdropBorderColor(theme.dropdownBorder.r, theme.dropdownBorder.g, theme.dropdownBorder.b, theme.dropdownBorder.a)
        if frame.filterBtn.arrow then
            frame.filterBtn.arrow:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
        end
    end
    if frame.filterMenu then
        frame.filterMenu:SetBackdropColor(theme.dropdownMenuBg.r, theme.dropdownMenuBg.g, theme.dropdownMenuBg.b, theme.dropdownMenuBg.a)
        frame.filterMenu:SetBackdropBorderColor(theme.dropdownBorder.r, theme.dropdownBorder.g, theme.dropdownBorder.b, theme.dropdownBorder.a)
        if frame.filterMenu.sourceHeader then
            frame.filterMenu.sourceHeader:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b)
        end
        if frame.filterMenu.headerLine then
            frame.filterMenu.headerLine:SetColorTexture(theme.separator.r, theme.separator.g, theme.separator.b, theme.separator.a)
        end
        if frame.filterMenu.actionLine then
            frame.filterMenu.actionLine:SetColorTexture(theme.separator.r, theme.separator.g, theme.separator.b, theme.separator.a)
        end
    end
    self:UpdateFilterDropdown()
    
    -- Sort dropdown
    if frame.sortDropdown then
        frame.sortDropdown:SetBackdropColor(theme.dropdownBg.r, theme.dropdownBg.g, theme.dropdownBg.b, theme.dropdownBg.a)
        frame.sortDropdown:SetBackdropBorderColor(theme.dropdownBorder.r, theme.dropdownBorder.g, theme.dropdownBorder.b, theme.dropdownBorder.a)
        if frame.sortDropdown.text then
            frame.sortDropdown.text:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
        end
        if frame.sortDropdown.menu then
            frame.sortDropdown.menu:SetBackdropColor(theme.dropdownMenuBg.r, theme.dropdownMenuBg.g, theme.dropdownMenuBg.b, theme.dropdownMenuBg.a)
            frame.sortDropdown.menu:SetBackdropBorderColor(theme.dropdownBorder.r, theme.dropdownBorder.g, theme.dropdownBorder.b, theme.dropdownBorder.a)
        end
    end
    
    -- Sort direction button
    if frame.sortDirBtn then
        frame.sortDirBtn:SetBackdropColor(theme.dropdownBg.r, theme.dropdownBg.g, theme.dropdownBg.b, theme.dropdownBg.a)
        frame.sortDirBtn:SetBackdropBorderColor(theme.dropdownBorder.r, theme.dropdownBorder.g, theme.dropdownBorder.b, theme.dropdownBorder.a)
    end
    if frame.sortDirText then frame.sortDirText:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    
    -- Column headers
    if frame.headerRow then
        frame.headerRow:SetBackdropColor(theme.headerRowBg.r, theme.headerRowBg.g, theme.headerRowBg.b, theme.headerRowBg.a)
    end
    if frame.colItem then frame.colItem:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.colQty then frame.colQty:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.colValue then frame.colValue:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    
    -- Buttons
    local buttons = { frame.themeBtn, frame.togglePriceBtn, frame.lifetimeBtn, frame.resetBtn }
    for _, btn in ipairs(buttons) do
        if btn then
            btn:SetBackdropColor(theme.buttonBg.r, theme.buttonBg.g, theme.buttonBg.b, theme.buttonBg.a)
            btn:SetBackdropBorderColor(theme.buttonBorder.r, theme.buttonBorder.g, theme.buttonBorder.b, theme.buttonBorder.a)
            if btn.label then
                btn.label:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b)
            end
        end
    end
    
    -- Clear and rebuild item rows with new theme
    for _, row in ipairs(frame.itemRows) do
        row:Hide()
    end
    frame.itemRows = {}
    
    -- Update the item list to apply theme to rows
    self:UpdateItemList()
    
    -- Restore collapsed state after theme change
    self:UpdateItemsCollapsedState()
    
    -- Update tab styles
    if frame.UpdateTabStyles then
        frame.UpdateTabStyles()
    end
    
    -- Honor tab theming
    if frame.honorStatsSection then
        frame.honorStatsSection:SetBackdropColor(theme.sectionBg.r, theme.sectionBg.g, theme.sectionBg.b, theme.sectionBg.a)
        frame.honorStatsSection:SetBackdropBorderColor(theme.border.r, theme.border.g, theme.border.b, theme.border.a)
    end
    if frame.honorSessionLabel then frame.honorSessionLabel:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b) end
    if frame.honorGainedLabel then frame.honorGainedLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.hksLabel then frame.hksLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.hksValue then frame.hksValue:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b) end
    if frame.hphLabel then frame.hphLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.honorSeparator then frame.honorSeparator:SetColorTexture(theme.separator.r, theme.separator.g, theme.separator.b, theme.separator.a) end
    if frame.honorLifetimeLabel then frame.honorLifetimeLabel:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b) end
    if frame.lifetimeHonorLabel then frame.lifetimeHonorLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.lifetimeHksLabel then frame.lifetimeHksLabel:SetTextColor(theme.labelColor.r, theme.labelColor.g, theme.labelColor.b) end
    if frame.lifetimeHksValue then frame.lifetimeHksValue:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b) end
    if frame.honorDurationLabel then frame.honorDurationLabel:SetTextColor(theme.mutedColor.r, theme.mutedColor.g, theme.mutedColor.b) end
    if frame.honorDuration then frame.honorDuration:SetTextColor(theme.valueColor.r, theme.valueColor.g, theme.valueColor.b) end
    
    -- Update honor tab
    self:UpdateHonorTab()
end

-- Update honor tab display
function addon:UpdateHonorTab()
    local frame = self.mainFrame
    if not frame then return end
    
    local session = self.charDB.session
    local lifetime = self.charDB.lifetime
    
    -- Session honor
    local sessionHonor = session.honorGained or 0
    local sessionHKs = session.honorableKills or 0
    
    if frame.honorGainedValue then
        frame.honorGainedValue:SetText(tostring(sessionHonor))
    end
    if frame.hksValue then
        frame.hksValue:SetText(tostring(sessionHKs))
    end
    
    -- Honor per hour calculation
    local startTime = session.startTime
    if startTime and startTime > 0 then
        local duration = time() - startTime
        if duration >= 60 then
            local hph = math.floor(sessionHonor * 3600 / duration)
            if frame.hphValue then
                frame.hphValue:SetText(tostring(hph))
            end
        else
            if frame.hphValue then frame.hphValue:SetText("0") end
        end
    else
        if frame.hphValue then frame.hphValue:SetText("0") end
    end
    
    -- Character stats from game API
    local currentHonor = 0
    -- Try different APIs for honor (varies by game version)
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local honorInfo = C_CurrencyInfo.GetCurrencyInfo(1901)  -- Honor currency ID
        if honorInfo then
            currentHonor = honorInfo.quantity or 0
        end
    elseif GetHonorCurrency then
        currentHonor = GetHonorCurrency() or 0
    elseif UnitHonor then
        currentHonor = UnitHonor("player") or 0
    end
    
    local totalHKs = 0
    if GetPVPLifetimeStats then
        totalHKs = GetPVPLifetimeStats() or 0
    end
    
    if frame.lifetimeHonorValue then
        frame.lifetimeHonorValue:SetText(tostring(currentHonor))
    end
    if frame.lifetimeHksValue then
        frame.lifetimeHksValue:SetText(tostring(totalHKs))
    end
    
    -- Duration
    if frame.honorDuration then
        frame.honorDuration:SetText(self:GetSessionDuration())
    end
end

-- Sort items based on current mode
function addon:GetSortedItems()
    local session = self.charDB.session
    local useAH = self:GetSetting("features.useAHPrices")
    local items = {}
    
    -- Get filter settings
    local showPickup = self:GetSetting("filters.showPickup")
    local showGathered = self:GetSetting("filters.showGathered")
    
    -- Default to true if setting doesn't exist
    if showPickup == nil then showPickup = true end
    if showGathered == nil then showGathered = true end
    
    -- Convert to array for sorting, applying filters
    local itemOrder = 0
    for itemID, data in pairs(session.itemsLooted) do
        itemOrder = itemOrder + 1
        
        -- Apply source filter
        local lootSource = data.lootSource or "pickup"
        local shouldShow = false
        
        if lootSource == "both" then
            -- Item came from both sources, show if either filter is enabled
            shouldShow = showPickup or showGathered
        elseif lootSource == "gathered" then
            shouldShow = showGathered
        else  -- "pickup"
            shouldShow = showPickup
        end
        
        if shouldShow then
            table.insert(items, {
                id = itemID,
                name = data.name,
                count = data.count,
                quality = data.quality or 1,
                link = data.link,
                texture = data.texture,
                value = useAH and data.ahValue or data.vendorValue,
                order = itemOrder,  -- Track insertion order for "recent" sorting
                lootSource = lootSource,
            })
        end
    end
    
    -- Sort based on current mode
    local mode = self.currentSortMode
    local ascending = self.sortAscending
    
    table.sort(items, function(a, b)
        local result
        if mode == "value" then
            result = a.value > b.value
        elseif mode == "count" then
            result = a.count > b.count
        elseif mode == "name" then
            result = a.name < b.name
        elseif mode == "quality" then
            if a.quality == b.quality then
                result = a.value > b.value
            else
                result = a.quality > b.quality
            end
        elseif mode == "recent" then
            result = a.order > b.order
        else
            result = a.value > b.value
        end
        
        if ascending then
            return not result
        end
        return result
    end)
    
    return items
end

-- Update the item list
function addon:UpdateItemList()
    local frame = self.mainFrame
    if not frame then return end
    
    local scrollContent = frame.scrollContent
    local items = self:GetSortedItems()
    
    -- Hide existing rows
    for _, row in ipairs(frame.itemRows) do
        row:Hide()
    end
    
    -- Create/update rows
    local yOffset = 0
    for i, itemData in ipairs(items) do
        local row = frame.itemRows[i]
        if not row then
            row = CreateItemRow(scrollContent, i)
            frame.itemRows[i] = row
        end
        
        row:SetPoint("TOPLEFT", 2, yOffset)
        row:SetWidth(scrollContent:GetWidth() - 4)
        
        -- Set icon
        local itemTexture = itemData.texture or GetItemIcon(itemData.id)
        row.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        
        -- Set name with quality color
        local qualityColor = QUALITY_COLORS[itemData.quality] or QUALITY_COLORS[1]
        local r, g, b = qualityColor[1], qualityColor[2], qualityColor[3]
        row.name:SetText(itemData.name)
        row.name:SetTextColor(r, g, b)
        
        -- Set count
        row.count:SetText("x" .. itemData.count)
        
        -- Set value (shortened format)
        local valueText = self:FormatMoneyShort(itemData.value)
        row.value:SetText(valueText)
        
        row.itemLink = itemData.link
        row:Show()
        
        yOffset = yOffset - 28
    end
    
    -- Update scroll content height
    scrollContent:SetHeight(math.max(1, #items * 28))
end

-- Short money format for item list
function addon:FormatMoneyShort(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    
    if gold >= 1000 then
        return string.format("%.1fk", gold / 1000)
    elseif gold > 0 then
        return string.format("%dg%d", gold, silver)
    elseif silver > 0 then
        return string.format("%ds", silver)
    else
        return string.format("%dc", copper % 100)
    end
end

-- Update the main frame with current data
function addon:UpdateMainFrame()
    local frame = self.mainFrame
    if not frame then return end
    
    local session = self.charDB.session
    local useAH = self:GetSetting("features.useAHPrices")
    
    -- Update price mode button
    frame.togglePriceBtn.label:SetText(useAH and "Vendor" or "AH Prices")
    
    -- Session data
    frame.sessionGold:SetText(self.utils.FormatMoney(session.rawGoldLooted))
    
    local itemValue = useAH and session.totalAHValue or session.totalVendorValue
    frame.itemsValue:SetText(self.utils.FormatMoney(itemValue))
    
    -- Update both vendor and AH totals
    local totalVendorSession = session.rawGoldLooted + session.totalVendorValue
    local totalAHSession = session.rawGoldLooted + session.totalAHValue
    frame.vendorTotalValue:SetText(self.utils.FormatMoney(totalVendorSession))
    frame.ahTotalValue:SetText(self.utils.FormatMoney(totalAHSession))
    
    -- Gold per hour
    local gph = self:GetGoldPerHour()
    frame.gph:SetText(self.utils.FormatMoney(gph))
    
    -- Duration
    frame.duration:SetText(self:GetSessionDuration())
    
    -- Update item count
    local itemCount = 0
    for _ in pairs(session.itemsLooted) do
        itemCount = itemCount + 1
    end
    frame.itemCountText:SetText("(" .. itemCount .. ")")
    
    -- Update item list
    self:UpdateItemList()
end

-- Periodic update for duration and GPH display
local updateInterval = 5.0  -- seconds
local timeSinceLastUpdate = 0

eventFrame:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    
    if timeSinceLastUpdate >= updateInterval then
        if addon.mainFrame and addon.mainFrame:IsShown() then
            addon:UpdateMainFrame()
            addon:UpdateHonorTab()
        end
        timeSinceLastUpdate = 0
    end
end)

addon:Debug("Main file loaded")
