--[[
    Farmer - Farmer.lua
    Main addon file - event handling and initialization
]]

local addonName, addon = ...

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
    -- Initialize session start time
    if addon.charDB.session.startTime == 0 then
        addon.charDB.session.startTime = time()
    end
    
    -- Check for Auctionator
    addon.hasAuctionator = (Auctionator ~= nil) or (AUCTIONATOR_ENABLE ~= nil)
    
    -- Show welcome message if enabled
    if addon:GetSetting("features.showWelcome") then
        local ahStatus = addon.hasAuctionator and "|cff00ff00Auctionator detected|r" or "|cffff9900Auctionator not found (using vendor prices)|r"
        addon:Print("Loot tracking active! " .. ahStatus)
        addon:Print("Type /farmer for commands.")
    end
    
    -- Initialize any UI elements here
    addon:CreateMainFrame()
end

-- PLAYER_LOGOUT: Player is logging out
function eventHandlers:PLAYER_LOGOUT()
    -- Save any data before logout
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
    
    -- Get item info
    local itemName, _, itemQuality, _, _, _, _, _, _, _, vendorPrice, _, _, _, _, _, _ = GetItemInfo(itemLink)
    local itemID = GetItemInfoInstant(itemLink)
    
    if not itemID then
        self:Debug("Could not get itemID for: " .. tostring(itemLink))
        return
    end
    
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
            count = 0,
            vendorValue = 0,
            ahValue = 0,
            name = itemName or "Unknown",
            quality = itemQuality or 1,
            link = itemLink,
        }
    end
    
    local itemData = session.itemsLooted[itemID]
    itemData.count = itemData.count + count
    itemData.vendorValue = itemData.vendorValue + totalVendorValue
    itemData.ahValue = itemData.ahValue + totalAHValue
    
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
        self:Debug(string.format("Looted %dx %s - %s", count, itemLink, valueStr))
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
    UI Creation Example
    Creates a simple movable frame
]]
function addon:CreateMainFrame()
    -- Don't create if already exists
    if self.mainFrame then return end
    
    local frame = CreateFrame("Frame", "FarmerMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(220, 210)
    
    -- Apply saved position or default
    local pos = self:GetSetting("ui.position")
    frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    
    -- Backdrop (border and background)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    
    -- Title text
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Farmer - Loot Tracker")
    
    -- Session header
    local sessionHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionHeader:SetPoint("TOPLEFT", 15, -35)
    sessionHeader:SetText("|cff00ff00Session:|r")
    frame.sessionHeader = sessionHeader
    
    -- Session gold value
    local sessionGold = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionGold:SetPoint("TOPLEFT", 15, -50)
    sessionGold:SetText("Gold: 0g 0s 0c")
    frame.sessionGold = sessionGold
    
    -- Items value (AH or Vendor)
    local itemsValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemsValue:SetPoint("TOPLEFT", 15, -65)
    itemsValue:SetText("Items: 0g 0s 0c")
    frame.itemsValue = itemsValue
    
    -- Total value
    local totalValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    totalValue:SetPoint("TOPLEFT", 15, -85)
    totalValue:SetText("|cffffd700Total: 0g 0s 0c|r")
    frame.totalValue = totalValue
    
    -- Gold per hour
    local gph = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gph:SetPoint("TOPLEFT", 15, -105)
    gph:SetText("GPH: 0g 0s 0c")
    frame.gph = gph
    
    -- Session duration
    local duration = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    duration:SetPoint("TOPLEFT", 15, -120)
    duration:SetText("Duration: 0m")
    frame.duration = duration
    
    -- Lifetime header
    local lifetimeHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lifetimeHeader:SetPoint("TOPLEFT", 15, -145)
    lifetimeHeader:SetText("|cff9999ffLifetime:|r")
    frame.lifetimeHeader = lifetimeHeader
    
    -- Lifetime total
    local lifetimeTotal = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lifetimeTotal:SetPoint("TOPLEFT", 15, -160)
    lifetimeTotal:SetText("Total: 0g 0s 0c")
    frame.lifetimeTotal = lifetimeTotal
    
    -- Items looted count
    local itemCount = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemCount:SetPoint("TOPLEFT", 15, -175)
    itemCount:SetText("Items: 0")
    frame.itemCount = itemCount
    
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
        -- Save position
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        addon:SetSetting("ui.position", {
            point = point,
            relativePoint = relativePoint,
            xOfs = xOfs,
            yOfs = yOfs,
        })
    end)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- Reset session button
    local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetBtn:SetSize(60, 20)
    resetBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    resetBtn:SetText("Reset")
    resetBtn:SetScript("OnClick", function()
        addon:ResetSession()
        addon:UpdateMainFrame()
    end)
    
    -- Apply scale
    frame:SetScale(self:GetSetting("ui.scale"))
    
    -- Start hidden (toggle with slash command or keybind)
    frame:Hide()
    
    self.mainFrame = frame
    
    -- Add toggle to slash command
    local oldHandler = SlashCmdList["FARMER"]
    SlashCmdList["FARMER"] = function(msg)
        local cmd = msg:match("^(%S*)"):lower()
        if cmd == "show" or cmd == "toggle" then
            if frame:IsShown() then
                frame:Hide()
            else
                frame:Show()
            end
        else
            oldHandler(msg)
        end
    end
    
    addon:Debug("Main frame created")
end

-- Update the main frame with current data
function addon:UpdateMainFrame()
    local frame = self.mainFrame
    if not frame then return end
    
    local session = self.charDB.session
    local lifetime = self.charDB.lifetime
    local useAH = self:GetSetting("features.useAHPrices")
    
    -- Session data
    frame.sessionGold:SetText("Gold: " .. self.utils.FormatMoney(session.rawGoldLooted))
    
    local itemValue = useAH and session.totalAHValue or session.totalVendorValue
    local priceType = useAH and "(AH)" or "(Vendor)"
    frame.itemsValue:SetText("Items: " .. self.utils.FormatMoney(itemValue) .. " " .. priceType)
    
    local totalSession = session.rawGoldLooted + itemValue
    frame.totalValue:SetText("|cffffd700Total: " .. self.utils.FormatMoney(totalSession) .. "|r")
    
    -- Gold per hour
    local gph = self:GetGoldPerHour()
    frame.gph:SetText("GPH: " .. self.utils.FormatMoney(gph))
    
    -- Duration
    frame.duration:SetText("Duration: " .. self:GetSessionDuration())
    
    -- Lifetime data
    local lifetimeValue = useAH and lifetime.totalAHValue or lifetime.totalVendorValue
    local lifetimeTotal = lifetime.rawGoldLooted + lifetimeValue
    frame.lifetimeTotal:SetText("Total: " .. self.utils.FormatMoney(lifetimeTotal))
    frame.itemCount:SetText("Items: " .. lifetime.totalItemsLooted)
end

-- Periodic update for duration and GPH display
local updateInterval = 5.0  -- seconds
local timeSinceLastUpdate = 0

eventFrame:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    
    if timeSinceLastUpdate >= updateInterval then
        if addon.mainFrame and addon.mainFrame:IsShown() then
            addon:UpdateMainFrame()
        end
        timeSinceLastUpdate = 0
    end
end)

addon:Debug("Main file loaded")
