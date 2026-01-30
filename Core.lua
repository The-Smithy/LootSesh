--[[
    Loot Sesh - Core.lua
    Core functionality and utilities
]]

-- Create addon namespace
local addonName, addon = ...

-- Version info
addon.version = "1.0.0"
addon.name = addonName

-- Utility functions
addon.utils = {}

-- Print a formatted message to chat
function addon:Print(msg)
    print("|cff33ff99" .. self.name .. "|r: " .. tostring(msg))
end

-- Debug print (only when debug mode is enabled)
function addon:Debug(msg)
    if self.db and self.db.debug then
        print("|cffff9933[DEBUG] " .. self.name .. "|r: " .. tostring(msg))
    end
end

-- Format gold/silver/copper
function addon.utils.FormatMoney(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100
    
    if gold > 0 then
        return string.format("%dg %ds %dc", gold, silver, cop)
    elseif silver > 0 then
        return string.format("%ds %dc", silver, cop)
    else
        return string.format("%dc", cop)
    end
end

-- Class color table (TBC colors)
addon.classColors = {
    ["WARRIOR"] = "|cffc79c6e",
    ["PALADIN"] = "|cfff58cba",
    ["HUNTER"] = "|cffabd473",
    ["ROGUE"] = "|cfffff569",
    ["PRIEST"] = "|cffffffff",
    ["SHAMAN"] = "|cff0070de",
    ["MAGE"] = "|cff69ccf0",
    ["WARLOCK"] = "|cff9482c9",
    ["DRUID"] = "|cffff7d0a",
}

-- Get player's class color
function addon.utils.GetClassColor(class)
    return addon.classColors[class] or "|cffffffff"
end

-- Slash command handler
function addon:RegisterSlashCommands()
    SLASH_LOOTSESH1 = "/lootsesh"
    SLASH_LOOTSESH2 = "/ls"
    
    SlashCmdList["LOOTSESH"] = function(msg)
        local cmd, args = msg:match("^(%S*)%s*(.-)$")
        cmd = cmd:lower()
        
        if cmd == "" or cmd == "help" then
            self:Print("Available commands:")
            self:Print("  /lootsesh show - Toggle loot tracker window")
            self:Print("  /lootsesh session - Show session summary")
            self:Print("  /lootsesh lifetime - Show lifetime stats")
            self:Print("  /lootsesh reset session - Reset session data")
            self:Print("  /lootsesh reset all - Reset all character data")
            self:Print("  /lootsesh ah - Toggle AH/Vendor price preference")
            self:Print("  /lootsesh debug - Toggle debug mode")
        elseif cmd == "session" then
            local session = self.charDB.session
            local useAH = self:GetSetting("features.useAHPrices")
            local itemValue = useAH and session.totalAHValue or session.totalVendorValue
            local priceType = useAH and "AH" or "Vendor"
            self:Print("|cff00ff00=== Session Summary ===")
            self:Print("Duration: " .. self:GetSessionDuration())
            self:Print("Raw Gold: " .. self.utils.FormatMoney(session.rawGoldLooted))
            self:Print("Items (" .. priceType .. "): " .. self.utils.FormatMoney(itemValue))
            self:Print("|cffffd700Total: " .. self.utils.FormatMoney(session.rawGoldLooted + itemValue) .. "|r")
            self:Print("Gold/Hour: " .. self.utils.FormatMoney(self:GetGoldPerHour()))
        elseif cmd == "lifetime" then
            local lifetime = self.charDB.lifetime
            local useAH = self:GetSetting("features.useAHPrices")
            local itemValue = useAH and lifetime.totalAHValue or lifetime.totalVendorValue
            local priceType = useAH and "AH" or "Vendor"
            self:Print("|cff9999ff=== Lifetime Stats ===")
            self:Print("Total Items Looted: " .. lifetime.totalItemsLooted)
            self:Print("Raw Gold: " .. self.utils.FormatMoney(lifetime.rawGoldLooted))
            self:Print("Items (" .. priceType .. "): " .. self.utils.FormatMoney(itemValue))
            self:Print("|cffffd700Total: " .. self.utils.FormatMoney(lifetime.rawGoldLooted + itemValue) .. "|r")
        elseif cmd == "ah" then
            local current = self:GetSetting("features.useAHPrices")
            self:SetSetting("features.useAHPrices", not current)
            if not current then
                self:Print("Now using |cff00ff00Auctionator AH prices|r when available")
            else
                self:Print("Now using |cffff9900Vendor prices|r")
            end
            self:UpdateMainFrame()
        elseif cmd == "debug" then
            self.db.debug = not self.db.debug
            self:Print("Debug mode: " .. (self.db.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        elseif cmd == "reset" then
            if args == "session" then
                self:ResetSession()
            elseif args == "all" then
                self:ResetCharData()
            else
                self:Print("Usage: /lootsesh reset session OR /lootsesh reset all")
            end
        else
            self:Print("Unknown command. Type /lootsesh help for available commands.")
        end
    end
end

-- Export addon to global namespace for debugging (optional)
_G["LootSesh"] = addon