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
        totalVendorValue = 0,
        totalAHValue = 0,
        itemsLooted = {},  -- [itemID] = { count, vendorValue, ahValue, name, quality }
        rawGoldLooted = 0,
    },
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
function addon:ResetSession()
    self.charDB.session = DeepCopy(charDefaults.session)
    self.charDB.session.startTime = time()
    self:Print("Session data has been reset.")
end

-- Reset all character data
function addon:ResetCharData()
    LootSeshCharDB = DeepCopy(charDefaults)
    self.charDB = LootSeshCharDB
    self.charDB.session.startTime = time()
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
