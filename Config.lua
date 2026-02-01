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
        itemsCollapsed = false,  -- Whether the items list is minimized
        activeTab = "loot",  -- Current active tab: "loot" or "honor"
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
        -- Honor tracking
        honorGained = 0,
        honorableKills = 0,
    },
    sessionHistory = {},  -- Array of past sessions
    lifetime = {
        totalVendorValue = 0,
        totalAHValue = 0,
        totalItemsLooted = 0,
        rawGoldLooted = 0,
        -- Lifetime honor stats
        honorGained = 0,
        honorableKills = 0,
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

-- Theme definitions - Modern & Clean with WoW faction homage
addon.themes = {
    horde = {
        name = "Horde",
        -- Main frame colors - deeper, richer tones
        background = { r = 0.08, g = 0.04, b = 0.04, a = 0.97 },
        border = { r = 0.35, g = 0.12, b = 0.10, a = 0.8 },
        -- Subtle inner glow effect
        innerGlow = { r = 0.6, g = 0.15, b = 0.12, a = 0.08 },
        -- Header gradient - refined
        headerGradient = { r = 0.5, g = 0.1, b = 0.08, a = 0.15 },
        -- Title color (hex for text) - warm gold
        titleColor = "|cffd4a056",
        titleText = "LOOT SESH",
        -- Section background - subtle elevation
        sectionBg = { r = 0.10, g = 0.05, b = 0.05, a = 0.6 },
        sectionBorder = { r = 0.25, g = 0.10, b = 0.10, a = 0.4 },
        -- Separator line - subtle
        separator = { r = 0.4, g = 0.15, b = 0.12, a = 0.35 },
        -- Text colors - improved contrast
        labelColor = { r = 0.65, g = 0.55, b = 0.50 },
        valueColor = { r = 0.95, g = 0.90, b = 0.85 },
        mutedColor = { r = 0.50, g = 0.40, b = 0.38 },
        -- Button colors - modern flat style
        buttonBg = { r = 0.18, g = 0.08, b = 0.07, a = 0.9 },
        buttonBorder = { r = 0.35, g = 0.15, b = 0.12, a = 0.6 },
        buttonHoverBg = { r = 0.28, g = 0.10, b = 0.08, a = 0.95 },
        buttonHoverBorder = { r = 0.55, g = 0.20, b = 0.15, a = 0.8 },
        buttonText = { r = 0.90, g = 0.82, b = 0.75 },
        -- Tab colors
        tabActiveBg = { r = 0.20, g = 0.08, b = 0.06, a = 0.95 },
        tabInactiveBg = { r = 0.10, g = 0.05, b = 0.04, a = 0.6 },
        tabBorder = { r = 0.35, g = 0.12, b = 0.10, a = 0.5 },
        -- Dropdown colors
        dropdownBg = { r = 0.12, g = 0.06, b = 0.05, a = 0.98 },
        dropdownBorder = { r = 0.35, g = 0.15, b = 0.12, a = 0.5 },
        dropdownMenuBg = { r = 0.10, g = 0.05, b = 0.04, a = 0.98 },
        dropdownHighlight = { r = 0.5, g = 0.15, b = 0.12, a = 0.25 },
        -- Row colors - subtle zebra
        rowAltBg = { r = 1, g = 0.9, b = 0.85, a = 0.02 },
        rowHighlight = { r = 0.6, g = 0.2, b = 0.15, a = 0.12 },
        -- Header row
        headerRowBg = { r = 0.15, g = 0.06, b = 0.05, a = 0.85 },
        -- Gold colors
        goldColor = { r = 1, g = 0.84, b = 0.40 },
        ahColor = { r = 0.95, g = 0.55, b = 0.45 },
        -- Accent for hover
        accentColor = { r = 0.7, g = 0.25, b = 0.20 },
        -- Honor purple
        honorColor = { r = 0.75, g = 0.40, b = 0.85 },
    },
    
    alliance = {
        name = "Alliance",
        -- Main frame colors - deep navy with subtle warmth
        background = { r = 0.04, g = 0.06, b = 0.10, a = 0.97 },
        border = { r = 0.15, g = 0.28, b = 0.45, a = 0.8 },
        -- Subtle inner glow
        innerGlow = { r = 0.2, g = 0.35, b = 0.6, a = 0.08 },
        -- Header gradient
        headerGradient = { r = 0.12, g = 0.25, b = 0.5, a = 0.15 },
        -- Title color (hex for text) - warm gold
        titleColor = "|cffd4a056",
        titleText = "LOOT SESH",
        -- Section background
        sectionBg = { r = 0.05, g = 0.08, b = 0.14, a = 0.6 },
        sectionBorder = { r = 0.12, g = 0.22, b = 0.35, a = 0.4 },
        -- Separator line
        separator = { r = 0.18, g = 0.32, b = 0.50, a = 0.35 },
        -- Text colors
        labelColor = { r = 0.55, g = 0.65, b = 0.75 },
        valueColor = { r = 0.90, g = 0.94, b = 0.98 },
        mutedColor = { r = 0.40, g = 0.48, b = 0.58 },
        -- Button colors
        buttonBg = { r = 0.08, g = 0.12, b = 0.20, a = 0.9 },
        buttonBorder = { r = 0.18, g = 0.30, b = 0.45, a = 0.6 },
        buttonHoverBg = { r = 0.10, g = 0.18, b = 0.30, a = 0.95 },
        buttonHoverBorder = { r = 0.25, g = 0.45, b = 0.70, a = 0.8 },
        buttonText = { r = 0.82, g = 0.88, b = 0.95 },
        -- Tab colors
        tabActiveBg = { r = 0.08, g = 0.14, b = 0.24, a = 0.95 },
        tabInactiveBg = { r = 0.05, g = 0.08, b = 0.14, a = 0.6 },
        tabBorder = { r = 0.15, g = 0.28, b = 0.45, a = 0.5 },
        -- Dropdown colors
        dropdownBg = { r = 0.06, g = 0.10, b = 0.16, a = 0.98 },
        dropdownBorder = { r = 0.18, g = 0.30, b = 0.45, a = 0.5 },
        dropdownMenuBg = { r = 0.05, g = 0.08, b = 0.14, a = 0.98 },
        dropdownHighlight = { r = 0.15, g = 0.30, b = 0.55, a = 0.25 },
        -- Row colors
        rowAltBg = { r = 0.7, g = 0.8, b = 1, a = 0.02 },
        rowHighlight = { r = 0.25, g = 0.45, b = 0.75, a = 0.12 },
        -- Header row
        headerRowBg = { r = 0.06, g = 0.12, b = 0.22, a = 0.85 },
        -- Gold colors
        goldColor = { r = 1, g = 0.86, b = 0.45 },
        ahColor = { r = 0.50, g = 0.75, b = 1 },
        -- Accent
        accentColor = { r = 0.35, g = 0.55, b = 0.90 },
        -- Honor purple
        honorColor = { r = 0.65, g = 0.45, b = 0.90 },
    },
    
    dark = {
        name = "Dark",
        -- Main frame colors - pure dark with subtle cool tone
        background = { r = 0.06, g = 0.06, b = 0.07, a = 0.97 },
        border = { r = 0.20, g = 0.20, b = 0.22, a = 0.7 },
        -- Subtle inner glow
        innerGlow = { r = 0.3, g = 0.3, b = 0.35, a = 0.06 },
        -- Header gradient
        headerGradient = { r = 0.25, g = 0.25, b = 0.28, a = 0.12 },
        -- Title color (hex for text) - warm gold
        titleColor = "|cffd4a056",
        titleText = "LOOT SESH",
        -- Section background
        sectionBg = { r = 0.08, g = 0.08, b = 0.09, a = 0.6 },
        sectionBorder = { r = 0.18, g = 0.18, b = 0.20, a = 0.4 },
        -- Separator line
        separator = { r = 0.25, g = 0.25, b = 0.28, a = 0.35 },
        -- Text colors
        labelColor = { r = 0.55, g = 0.55, b = 0.58 },
        valueColor = { r = 0.92, g = 0.92, b = 0.94 },
        mutedColor = { r = 0.42, g = 0.42, b = 0.45 },
        -- Button colors
        buttonBg = { r = 0.10, g = 0.10, b = 0.11, a = 0.9 },
        buttonBorder = { r = 0.25, g = 0.25, b = 0.28, a = 0.6 },
        buttonHoverBg = { r = 0.15, g = 0.15, b = 0.17, a = 0.95 },
        buttonHoverBorder = { r = 0.40, g = 0.40, b = 0.45, a = 0.8 },
        buttonText = { r = 0.85, g = 0.85, b = 0.88 },
        -- Tab colors
        tabActiveBg = { r = 0.12, g = 0.12, b = 0.14, a = 0.95 },
        tabInactiveBg = { r = 0.07, g = 0.07, b = 0.08, a = 0.6 },
        tabBorder = { r = 0.20, g = 0.20, b = 0.22, a = 0.5 },
        -- Dropdown colors
        dropdownBg = { r = 0.08, g = 0.08, b = 0.10, a = 0.98 },
        dropdownBorder = { r = 0.25, g = 0.25, b = 0.28, a = 0.5 },
        dropdownMenuBg = { r = 0.06, g = 0.06, b = 0.08, a = 0.98 },
        dropdownHighlight = { r = 0.35, g = 0.35, b = 0.40, a = 0.25 },
        -- Row colors
        rowAltBg = { r = 1, g = 1, b = 1, a = 0.015 },
        rowHighlight = { r = 1, g = 1, b = 1, a = 0.08 },
        -- Header row
        headerRowBg = { r = 0.10, g = 0.10, b = 0.12, a = 0.85 },
        -- Gold colors
        goldColor = { r = 1, g = 0.85, b = 0.45 },
        ahColor = { r = 0.60, g = 0.75, b = 0.85 },
        -- Accent
        accentColor = { r = 0.55, g = 0.55, b = 0.62 },
        -- Honor purple
        honorColor = { r = 0.70, g = 0.50, b = 0.88 },
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
