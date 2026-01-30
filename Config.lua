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
}

-- Per-character defaults (for loot tracking)
local charDefaults = {
    session = {
        startTime = 0,
        endTime = 0,
        lastSaveTime = 0,  -- Used to detect UI reloads vs new sessions
        totalVendorValue = 0,
        totalAHValue = 0,
        itemsLooted = {},  -- [itemID] = { count, vendorValue, ahValue, name, quality }
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
