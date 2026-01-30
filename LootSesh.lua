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
    
    -- Restore sort settings
    addon.currentSortMode = addon:GetSetting("ui.sortMode") or "value"
    addon.sortAscending = addon:GetSetting("ui.sortAscending") or false
    
    -- Show welcome message if enabled
    if addon:GetSetting("features.showWelcome") then
        local ahStatus = addon.hasAuctionator and "|cff00ff00Auctionator detected|r" or "|cffff9900Auctionator not found (using vendor prices)|r"
        addon:Print("Loot tracking active! " .. ahStatus)
        addon:Print("Type /farmer for commands.")
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
            itemID = itemID,
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

-- Create a styled backdrop
local function CreateStyledBackdrop(frame, alpha)
    alpha = alpha or 0.9
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    frame:SetBackdropColor(0.08, 0.08, 0.12, alpha)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
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

-- Create a separator line
local function CreateSeparator(parent, yOffset)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", 12, 0)
    line:SetPoint("RIGHT", -12, 0)
    line:SetPoint("TOP", 0, yOffset)
    line:SetColorTexture(0.4, 0.4, 0.45, 0.5)
    return line
end

-- Create a stat row
local function CreateStatRow(parent, label, yOffset)
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("TOPLEFT", 14, yOffset)
    labelText:SetTextColor(0.7, 0.7, 0.7)
    labelText:SetText(label)
    
    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("TOPRIGHT", -14, yOffset)
    valueText:SetTextColor(1, 1, 1)
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

-- Create styled button
local function CreateStyledButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 70, height or 20)
    
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(0.9, 0.9, 0.9)
    btn.label = label
    
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.35, 1)
        self:SetBackdropBorderColor(0.5, 0.7, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        self:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    end)
    
    return btn
end

-- Create dropdown menu for sorting
local function CreateSortDropdown(parent)
    local dropdown = CreateFrame("Frame", "FarmerSortDropdown", parent, "BackdropTemplate")
    dropdown:SetSize(90, 22)
    
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    dropdown:SetBackdropColor(0.12, 0.12, 0.16, 1)
    dropdown:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    
    local text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 8, 0)
    text:SetTextColor(0.9, 0.9, 0.9)
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
    arrow:SetText("▼")
    arrow:SetTextColor(0.6, 0.6, 0.6)
    
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
    menu:SetBackdropColor(0.1, 0.1, 0.14, 0.98)
    menu:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    
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
        itemText:SetTextColor(0.8, 0.8, 0.8)
        item.text = itemText
        
        local highlight = item:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.3, 0.5, 0.8, 0.3)
        
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
        self:SetBackdropBorderColor(0.5, 0.7, 1, 1)
    end)
    dropdown:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    end)
    
    -- Close menu when clicking elsewhere
    menu:SetScript("OnShow", function()
        menu:SetPropagateKeyboardInput(true)
    end)
    
    return dropdown
end

-- Create item row for the scroll list
local function CreateItemRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(parent:GetWidth() - 4, 28)
    
    -- Alternating row colors
    if index % 2 == 0 then
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        row:SetBackdropColor(1, 1, 1, 0.03)
    end
    
    -- Item icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon
    
    -- Quality border for icon
    local iconBorder = row:CreateTexture(nil, "OVERLAY")
    iconBorder:SetSize(24, 24)
    iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconBorder:SetTexture("Interface\\Buttons\\WHITE8x8")
    iconBorder:SetVertexColor(0.3, 0.3, 0.3, 0.8)
    row.iconBorder = iconBorder
    
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
    count:SetTextColor(0.7, 0.7, 0.7)
    row.count = count
    
    -- Value
    local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    value:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    value:SetWidth(42)
    value:SetJustifyH("RIGHT")
    value:SetTextColor(1, 0.82, 0)
    row.value = value
    
    -- Highlight effect
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    
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
    headerGradient:SetColorTexture(0.15, 0.4, 0.6, 0.15)
    headerGradient:SetGradient("VERTICAL", CreateColor(0.15, 0.4, 0.6, 0), CreateColor(0.15, 0.4, 0.6, 0.2))
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("|cff5ca8e0FARMER|r")
    title:SetFont(title:GetFont(), 14, "OUTLINE")
    
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 6, 0)
    subtitle:SetText("Loot Tracker")
    subtitle:SetTextColor(0.6, 0.6, 0.6)
    
    -- Close button
    local closeBtn = CreateCloseButton(frame)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
        addon:SetSetting("ui.visible", false)
    end)
    
    -- Stats section
    local statsSection = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    statsSection:SetPoint("TOPLEFT", 10, -35)
    statsSection:SetPoint("TOPRIGHT", -10, -35)
    statsSection:SetHeight(105)
    CreateStyledBackdrop(statsSection, 0.5)
    
    -- Total value (big display with both vendor and AH)
    local totalLabel = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalLabel:SetPoint("TOPLEFT", 12, -6)
    totalLabel:SetText("SESSION TOTAL")
    totalLabel:SetTextColor(0.5, 0.5, 0.5)
    totalLabel:SetFont(totalLabel:GetFont(), 8)
    
    -- Vendor total line
    local vendorLabel = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    vendorLabel:SetPoint("TOPLEFT", 12, -17)
    vendorLabel:SetTextColor(0.6, 0.6, 0.6)
    vendorLabel:SetFont(vendorLabel:GetFont(), 8)
    vendorLabel:SetText("Vendor:")
    
    local vendorValue = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    vendorValue:SetPoint("LEFT", vendorLabel, "RIGHT", 4, 0)
    vendorValue:SetTextColor(1, 0.82, 0)
    vendorValue:SetFont(vendorValue:GetFont(), 13)
    vendorValue:SetText("0g 0s 0c")
    frame.vendorTotalValue = vendorValue
    
    -- AH total line
    local ahLabel = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ahLabel:SetPoint("TOPLEFT", 12, -32)
    ahLabel:SetTextColor(0.6, 0.6, 0.6)
    ahLabel:SetFont(ahLabel:GetFont(), 8)
    ahLabel:SetText("AH:")
    
    local ahValue = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ahValue:SetPoint("LEFT", ahLabel, "RIGHT", 4, 0)
    ahValue:SetTextColor(0.3, 0.8, 1)
    ahValue:SetFont(ahValue:GetFont(), 13)
    ahValue:SetText("0g 0s 0c")
    frame.ahTotalValue = ahValue
    
    CreateSeparator(statsSection, -45)
    
    -- Stats grid
    local _, goldValue = CreateStatRow(statsSection, "Raw Gold", -55)
    frame.sessionGold = goldValue
    
    local _, itemsValue = CreateStatRow(statsSection, "Items Value", -70)
    frame.itemsValue = itemsValue
    
    local _, gphValue = CreateStatRow(statsSection, "Gold/Hour", -85)
    frame.gph = gphValue
    
    -- Duration and lifetime on right side
    local durationLabel = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationLabel:SetPoint("TOPRIGHT", -14, -8)
    durationLabel:SetTextColor(0.5, 0.5, 0.5)
    durationLabel:SetFont(durationLabel:GetFont(), 9)
    durationLabel:SetText("DURATION")
    
    local durationValue = statsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationValue:SetPoint("TOPRIGHT", -14, -20)
    durationValue:SetTextColor(1, 1, 1)
    durationValue:SetText("0m")
    frame.duration = durationValue
    
    -- Items section header
    local itemsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemsHeader:SetPoint("TOPLEFT", 14, -150)
    itemsHeader:SetText("LOOTED ITEMS")
    itemsHeader:SetTextColor(0.5, 0.5, 0.5)
    itemsHeader:SetFont(itemsHeader:GetFont(), 9)
    
    -- Item count
    local itemCountText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemCountText:SetPoint("LEFT", itemsHeader, "RIGHT", 6, 0)
    itemCountText:SetTextColor(0.4, 0.4, 0.4)
    itemCountText:SetText("(0)")
    frame.itemCountText = itemCountText
    
    -- Sort controls
    local sortLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sortLabel:SetPoint("TOPRIGHT", -105, -150)
    sortLabel:SetText("Sort:")
    sortLabel:SetTextColor(0.5, 0.5, 0.5)
    
    local sortDropdown = CreateSortDropdown(frame)
    sortDropdown:SetPoint("TOPRIGHT", -10, -147)
    frame.sortDropdown = sortDropdown
    
    -- Sort direction button
    local sortDirBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    sortDirBtn:SetSize(22, 22)
    sortDirBtn:SetPoint("RIGHT", sortDropdown, "LEFT", -4, 0)
    sortDirBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
    })
    sortDirBtn:SetBackdropColor(0.12, 0.12, 0.16, 1)
    sortDirBtn:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    
    local sortDirText = sortDirBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sortDirText:SetPoint("CENTER", 0, 0)
    sortDirText:SetText(addon.sortAscending and "▲" or "▼")
    sortDirText:SetTextColor(0.7, 0.7, 0.7)
    frame.sortDirText = sortDirText
    
    sortDirBtn:SetScript("OnClick", function()
        addon.sortAscending = not addon.sortAscending
        addon:SetSetting("ui.sortAscending", addon.sortAscending)
        sortDirText:SetText(addon.sortAscending and "▲" or "▼")
        addon:UpdateItemList()
    end)
    sortDirBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.5, 0.7, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(addon.sortAscending and "Ascending" or "Descending", 1, 1, 1)
        GameTooltip:Show()
    end)
    sortDirBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
        GameTooltip:Hide()
    end)
    
    -- Column headers
    local headerRow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    headerRow:SetPoint("TOPLEFT", 10, -172)
    headerRow:SetPoint("TOPRIGHT", -10, -172)
    headerRow:SetHeight(18)
    headerRow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    headerRow:SetBackdropColor(0.15, 0.15, 0.2, 0.8)
    
    local colItem = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colItem:SetPoint("LEFT", 30, 0)
    colItem:SetText("Item")
    colItem:SetTextColor(0.6, 0.6, 0.6)
    colItem:SetFont(colItem:GetFont(), 9)
    
    local colQty = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colQty:SetPoint("RIGHT", -52, 0)
    colQty:SetText("Qty")
    colQty:SetTextColor(0.6, 0.6, 0.6)
    colQty:SetFont(colQty:GetFont(), 9)
    
    local colValue = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colValue:SetPoint("RIGHT", -8, 0)
    colValue:SetText("Value")
    colValue:SetTextColor(0.6, 0.6, 0.6)
    colValue:SetFont(colValue:GetFont(), 9)
    
    -- Scrollable item list
    local scrollFrame = CreateFrame("ScrollFrame", "FarmerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -192)
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
    
    -- Bottom section with buttons
    local bottomSection = CreateFrame("Frame", nil, frame)
    bottomSection:SetPoint("BOTTOMLEFT", 10, 10)
    bottomSection:SetPoint("BOTTOMRIGHT", -10, 10)
    bottomSection:SetHeight(32)
    
    -- Toggle AH/Vendor button
    local togglePriceBtn = CreateStyledButton(bottomSection, "AH Prices", 70, 24)
    togglePriceBtn:SetPoint("LEFT", 0, 0)
    togglePriceBtn:SetScript("OnClick", function()
        local current = addon:GetSetting("features.useAHPrices")
        addon:SetSetting("features.useAHPrices", not current)
        addon:UpdateMainFrame()
    end)
    togglePriceBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.35, 1)
        self:SetBackdropBorderColor(0.5, 0.7, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Toggle between AH and Vendor prices", 1, 1, 1)
        GameTooltip:Show()
    end)
    togglePriceBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        self:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
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
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        self:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
        GameTooltip:Hide()
    end)
    
    -- Lifetime stats button
    local lifetimeBtn = CreateStyledButton(bottomSection, "Lifetime", 60, 24)
    lifetimeBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)
    lifetimeBtn:SetScript("OnClick", function()
        addon:ShowLifetimePopup()
    end)
    lifetimeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.35, 1)
        self:SetBackdropBorderColor(0.5, 0.7, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("View lifetime statistics", 1, 1, 1)
        GameTooltip:Show()
    end)
    lifetimeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        self:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
        GameTooltip:Hide()
    end)
    
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
    local oldHandler = SlashCmdList["FARMER"]
    SlashCmdList["FARMER"] = function(msg)
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

-- Sort items based on current mode
function addon:GetSortedItems()
    local session = self.charDB.session
    local useAH = self:GetSetting("features.useAHPrices")
    local items = {}
    
    -- Convert to array for sorting
    local itemOrder = 0
    for itemID, data in pairs(session.itemsLooted) do
        itemOrder = itemOrder + 1
        table.insert(items, {
            id = itemID,
            name = data.name,
            count = data.count,
            quality = data.quality or 1,
            link = data.link,
            value = useAH and data.ahValue or data.vendorValue,
            order = itemOrder,  -- Track insertion order for "recent" sorting
        })
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
        local itemTexture = GetItemIcon(itemData.id)
        row.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        
        -- Set quality border color
        local qualityColor = QUALITY_COLORS[itemData.quality] or QUALITY_COLORS[1]
        row.iconBorder:SetVertexColor(qualityColor[1], qualityColor[2], qualityColor[3], 0.8)
        
        -- Set name with quality color
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
        end
        timeSinceLastUpdate = 0
    end
end)

addon:Debug("Main file loaded")
