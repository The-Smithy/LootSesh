--[[
    Loot Sesh - Config.lua
    Saved variables and configuration management
]]

local addonName, addon = ...

-- Default settings
local defaults = {
    enabled = true,
    debug = false,
    
    -- UI settings
    ui = {
        scale = 1.0,
        locked = false,
        visible = false,
        theme = "auto",  -- "horde", "alliance", or "dark", "auto" = based on player faction
        position = {
            point = "CENTER",
            relativePoint = "CENTER",
            xOfs = 0,
            yOfs = 0,
        },
        size = {
            width = 320,
            height = 420,
        },
        sortMode = "value",
        sortAscending = false,
    },
    
    -- Feature toggles
    features = {
        showWelcome = true,
        useAHPrices = true,  -- Prefer AH prices over vendor when available
        showLootMessages = true,  -- Show chat messages when looting
    },
    
    -- Loot source filters
    filters = {
        showPickup = true,      -- Show items looted from mobs/containers
        showGathered = true,    -- Show items from mining/herbalism/skinning
    },
}

-- Per-character defaults (for loot tracking)
local charDefaults = {
    session = {
        startTime = 0,
        endTime = 0,
        lastSaveTime = 0,  -- Used to detect UI reloads vs new sessions
        totalVendorValue = 0,
        totalAHValue = 0,
        itemsLooted = {},  -- [itemID] = { count, vendorValue, ahValue, name, quality, lootSource }
        rawGoldLooted = 0,
    },
    sessionHistory = {},  -- Array of past sessions
    lifetime = {
        totalVendorValue = 0,
        totalAHValue = 0,
        totalItemsLooted = 0,
        rawGoldLooted = 0,
    },
}

-- Deep copy a table
local function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Theme definitions
addon.themes = {
    horde = {
        name = "Horde",
        -- Main frame colors
        background = { r = 0.12, g = 0.06, b = 0.06, a = 0.95 },
        border = { r = 0.5, g = 0.2, b = 0.2, a = 1 },
        -- Header gradient
        headerGradient = { r = 0.6, g = 0.15, b = 0.15, a = 0.2 },
        -- Title color (hex for text)
        titleColor = "|cffcc3333",
        titleText = "LOOT SESH",
        -- Section background
        sectionBg = { r = 0.15, g = 0.08, b = 0.08, a = 0.5 },
        -- Separator line
        separator = { r = 0.5, g = 0.25, b = 0.25, a = 0.5 },
        -- Text colors
        labelColor = { r = 0.6, g = 0.5, b = 0.5 },
        valueColor = { r = 1, g = 0.85, b = 0.7 },
        mutedColor = { r = 0.5, g = 0.4, b = 0.4 },
        -- Button colors
        buttonBg = { r = 0.2, g = 0.1, b = 0.1, a = 1 },
        buttonBorder = { r = 0.5, g = 0.3, b = 0.3, a = 1 },
        buttonHoverBg = { r = 0.35, g = 0.15, b = 0.15, a = 1 },
        buttonHoverBorder = { r = 0.8, g = 0.4, b = 0.4, a = 1 },
        -- Dropdown colors
        dropdownBg = { r = 0.15, g = 0.08, b = 0.08, a = 1 },
        dropdownBorder = { r = 0.5, g = 0.3, b = 0.3, a = 1 },
        dropdownMenuBg = { r = 0.12, g = 0.06, b = 0.06, a = 0.98 },
        dropdownHighlight = { r = 0.6, g = 0.2, b = 0.2, a = 0.3 },
        -- Row colors
        rowAltBg = { r = 0.8, g = 0.6, b = 0.6, a = 0.03 },
        rowHighlight = { r = 1, g = 0.8, b = 0.8, a = 0.08 },
        -- Header row
        headerRowBg = { r = 0.25, g = 0.1, b = 0.1, a = 0.8 },
        -- Gold colors
        goldColor = { r = 1, g = 0.82, b = 0 },
        ahColor = { r = 0.9, g = 0.5, b = 0.5 },
        -- Accent for hover
        accentColor = { r = 0.8, g = 0.3, b = 0.3 },
    },
    
    alliance = {
        name = "Alliance",
        -- Main frame colors
        background = { r = 0.05, g = 0.08, b = 0.14, a = 0.95 },
        border = { r = 0.2, g = 0.35, b = 0.55, a = 1 },
        -- Header gradient
        headerGradient = { r = 0.15, g = 0.3, b = 0.6, a = 0.2 },
        -- Title color (hex for text)
        titleColor = "|cff3399ff",
        titleText = "LOOT SESH",
        -- Section background
        sectionBg = { r = 0.06, g = 0.1, b = 0.18, a = 0.5 },
        -- Separator line
        separator = { r = 0.25, g = 0.4, b = 0.6, a = 0.5 },
        -- Text colors
        labelColor = { r = 0.5, g = 0.6, b = 0.7 },
        valueColor = { r = 0.8, g = 0.9, b = 1 },
        mutedColor = { r = 0.4, g = 0.5, b = 0.6 },
        -- Button colors
        buttonBg = { r = 0.1, g = 0.15, b = 0.25, a = 1 },
        buttonBorder = { r = 0.3, g = 0.45, b = 0.6, a = 1 },
        buttonHoverBg = { r = 0.15, g = 0.25, b = 0.4, a = 1 },
        buttonHoverBorder = { r = 0.4, g = 0.6, b = 0.9, a = 1 },
        -- Dropdown colors
        dropdownBg = { r = 0.08, g = 0.12, b = 0.2, a = 1 },
        dropdownBorder = { r = 0.3, g = 0.45, b = 0.6, a = 1 },
        dropdownMenuBg = { r = 0.06, g = 0.1, b = 0.18, a = 0.98 },
        dropdownHighlight = { r = 0.2, g = 0.4, b = 0.7, a = 0.3 },
        -- Row colors
        rowAltBg = { r = 0.6, g = 0.7, b = 0.9, a = 0.03 },
        rowHighlight = { r = 0.7, g = 0.8, b = 1, a = 0.08 },
        -- Header row
        headerRowBg = { r = 0.1, g = 0.18, b = 0.3, a = 0.8 },
        -- Gold colors
        goldColor = { r = 1, g = 0.85, b = 0.3 },
        ahColor = { r = 0.4, g = 0.75, b = 1 },
        -- Accent for hover
        accentColor = { r = 0.4, g = 0.6, b = 1 },
    },
    
    dark = {
        name = "Dark",
        -- Main frame colors
        background = { r = 0.08, g = 0.08, b = 0.1, a = 0.95 },
        border = { r = 0.25, g = 0.25, b = 0.3, a = 1 },
        -- Header gradient
        headerGradient = { r = 0.2, g = 0.2, b = 0.25, a = 0.15 },
        -- Title color (hex for text)
        titleColor = "|cff9999aa",
        titleText = "LOOT SESH",
        -- Section background
        sectionBg = { r = 0.1, g = 0.1, b = 0.12, a = 0.5 },
        -- Separator line
        separator = { r = 0.3, g = 0.3, b = 0.35, a = 0.5 },
        -- Text colors
        labelColor = { r = 0.55, g = 0.55, b = 0.6 },
        valueColor = { r = 0.85, g = 0.85, b = 0.9 },
        mutedColor = { r = 0.45, g = 0.45, b = 0.5 },
        -- Button colors
        buttonBg = { r = 0.12, g = 0.12, b = 0.15, a = 1 },
        buttonBorder = { r = 0.35, g = 0.35, b = 0.4, a = 1 },
        buttonHoverBg = { r = 0.2, g = 0.2, b = 0.25, a = 1 },
        buttonHoverBorder = { r = 0.5, g = 0.5, b = 0.6, a = 1 },
        -- Dropdown colors
        dropdownBg = { r = 0.1, g = 0.1, b = 0.13, a = 1 },
        dropdownBorder = { r = 0.35, g = 0.35, b = 0.4, a = 1 },
        dropdownMenuBg = { r = 0.08, g = 0.08, b = 0.1, a = 0.98 },
        dropdownHighlight = { r = 0.4, g = 0.4, b = 0.5, a = 0.3 },
        -- Row colors
        rowAltBg = { r = 0.8, g = 0.8, b = 0.85, a = 0.03 },
        rowHighlight = { r = 1, g = 1, b = 1, a = 0.06 },
        -- Header row
        headerRowBg = { r = 0.15, g = 0.15, b = 0.18, a = 0.8 },
        -- Gold colors
        goldColor = { r = 0.9, g = 0.8, b = 0.4 },
        ahColor = { r = 0.5, g = 0.7, b = 0.8 },
        -- Accent for hover
        accentColor = { r = 0.6, g = 0.6, b = 0.7 },
    },
}

-- Get current theme
function addon:GetCurrentTheme()
    local themeName = self:GetSetting("ui.theme") or "auto"
    
    -- Auto-detect based on faction
    if themeName == "auto" then
        local _, _, raceID = UnitRace("player")
        -- Horde races: Orc(2), Undead(5), Tauren(6), Troll(8), BloodElf(10), Goblin(9)
        local hordeRaces = { [2] = true, [5] = true, [6] = true, [8] = true, [9] = true, [10] = true }
        if hordeRaces[raceID] then
            themeName = "horde"
        else
            themeName = "alliance"
        end
    end
    
    return self.themes[themeName] or self.themes["dark"]
end

-- Cycle through themes
function addon:CycleTheme()
    local current = self:GetSetting("ui.theme") or "auto"
    local themeOrder = { "auto", "horde", "alliance", "dark" }
    local themeNames = { auto = "Auto (Faction)", horde = "Horde", alliance = "Alliance", dark = "Dark" }
    
    local currentIndex = 1
    for i, name in ipairs(themeOrder) do
        if name == current then
            currentIndex = i
            break
        end
    end
    
    local nextIndex = (currentIndex % #themeOrder) + 1
    local nextTheme = themeOrder[nextIndex]
    
    self:SetSetting("ui.theme", nextTheme)
    self:Print("Theme changed to: |cff00ff00" .. themeNames[nextTheme] .. "|r")
    
    return nextTheme
end

-- Merge tables (fills in missing values from defaults)
local function MergeTables(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            MergeTables(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

-- Initialize database
function addon:InitDB()
    -- Create saved variables table if it doesn't exist
    if not LootSeshDB then
        LootSeshDB = DeepCopy(defaults)
    else
        -- Merge with defaults to add any new settings
        MergeTables(LootSeshDB, defaults)
    end
    
    -- Per-character saved variables
    if not LootSeshCharDB then
        LootSeshCharDB = DeepCopy(charDefaults)
    else
        MergeTables(LootSeshCharDB, charDefaults)
    end
    
    self.db = LootSeshDB
    self.charDB = LootSeshCharDB
end

-- Reset database to defaults
function addon:ResetDB()
    LootSeshDB = DeepCopy(defaults)
    self.db = LootSeshDB
end

-- Reset session data
function addon:ResetSession(saveToHistory)
    -- Save current session to history if it has data
    if saveToHistory ~= false then
        self:SaveSessionToHistory()
    end
    
    self.charDB.session = DeepCopy(charDefaults.session)
    self.charDB.session.startTime = time()
    self.charDB.session.lastSaveTime = time()
    self:Print("Session data has been reset.")
end

-- Save current session to history
function addon:SaveSessionToHistory()
    local session = self.charDB.session
    
    -- Only save if there's actual data
    local itemCount = 0
    for _ in pairs(session.itemsLooted) do
        itemCount = itemCount + 1
    end
    
    if itemCount == 0 and session.rawGoldLooted == 0 then
        return false  -- Nothing to save
    end
    
    -- Create a copy of the session for history
    local historicalSession = DeepCopy(session)
    historicalSession.endTime = time()
    
    -- Initialize history if needed
    if not self.charDB.sessionHistory then
        self.charDB.sessionHistory = {}
    end
    
    -- Add to history
    table.insert(self.charDB.sessionHistory, historicalSession)
    
    self:Debug("Session saved to history (" .. #self.charDB.sessionHistory .. " total sessions)")
    return true
end

-- Get session history
function addon:GetSessionHistory()
    return self.charDB.sessionHistory or {}
end

-- Clear session history
function addon:ClearSessionHistory()
    self.charDB.sessionHistory = {}
    self:Print("Session history cleared.")
end

-- Get a specific historical session by index (1 = oldest, #history = newest)
function addon:GetHistoricalSession(index)
    local history = self:GetSessionHistory()
    return history[index]
end

-- Reset all character data
function addon:ResetCharData()
    LootSeshCharDB = DeepCopy(charDefaults)
    self.charDB = LootSeshCharDB
    self.charDB.session.startTime = time()
    self.charDB.session.lastSaveTime = time()
    self:Print("All character data has been reset.")
end

-- Get a setting value
function addon:GetSetting(path)
    local keys = {strsplit(".", path)}
    local value = self.db
    
    for _, key in ipairs(keys) do
        if type(value) ~= "table" then
            return nil
        end
        value = value[key]
    end
    
    return value
end

-- Set a setting value
function addon:SetSetting(path, newValue)
    local keys = {strsplit(".", path)}
    local target = self.db
    
    for i = 1, #keys - 1 do
        local key = keys[i]
        if type(target[key]) ~= "table" then
            target[key] = {}
        end
        target = target[key]
    end
    
    target[keys[#keys]] = newValue
end
