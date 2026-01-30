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
            self:Print("  /lootsesh history - List past sessions")
            self:Print("  /lootsesh history <#> - Show details of a past session")
            self:Print("  /lootsesh endsession - End current session and save to history")
            self:Print("  /lootsesh lifetime - Show lifetime stats")
            self:Print("  /lootsesh reset session - Reset session data (saves to history)")
            self:Print("  /lootsesh reset history - Clear all session history")
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
        elseif cmd == "history" then
            local history = self:GetSessionHistory()
            if args and args ~= "" then
                -- Show specific session
                local index = tonumber(args)
                if index and index >= 1 and index <= #history then
                    local session = history[index]
                    local useAH = self:GetSetting("features.useAHPrices")
                    local itemValue = useAH and session.totalAHValue or session.totalVendorValue
                    local priceType = useAH and "AH" or "Vendor"
                    local duration = (session.endTime or session.lastSaveTime) - session.startTime
                    local hours = math.floor(duration / 3600)
                    local minutes = math.floor((duration % 3600) / 60)
                    local durationStr = hours > 0 and string.format("%dh %dm", hours, minutes) or string.format("%dm", minutes)
                    
                    self:Print("|cff00ff00=== Session #" .. index .. " ===")
                    self:Print("Date: " .. date("%Y-%m-%d %H:%M", session.startTime))
                    self:Print("Duration: " .. durationStr)
                    self:Print("Raw Gold: " .. self.utils.FormatMoney(session.rawGoldLooted))
                    self:Print("Items (" .. priceType .. "): " .. self.utils.FormatMoney(itemValue))
                    self:Print("|cffffd700Total: " .. self.utils.FormatMoney(session.rawGoldLooted + itemValue) .. "|r")
                    
                    -- Count items
                    local itemCount = 0
                    for _ in pairs(session.itemsLooted) do
                        itemCount = itemCount + 1
                    end
                    self:Print("Unique Items: " .. itemCount)
                else
                    self:Print("Invalid session number. Use /lootsesh history to see available sessions.")
                end
            else
                -- List all sessions
                if #history == 0 then
                    self:Print("No session history found.")
                else
                    self:Print("|cff9999ff=== Session History (" .. #history .. " sessions) ===")
                    for i, session in ipairs(history) do
                        local useAH = self:GetSetting("features.useAHPrices")
                        local itemValue = useAH and session.totalAHValue or session.totalVendorValue
                        local total = session.rawGoldLooted + itemValue
                        local dateStr = date("%m/%d %H:%M", session.startTime)
                        self:Print(string.format("  #%d - %s - %s", i, dateStr, self.utils.FormatMoney(total)))
                    end
                    self:Print("Use /lootsesh history <#> for details")
                end
            end
        elseif cmd == "endsession" then
            if self:SaveSessionToHistory() then
                self:Print("Current session saved to history.")
                -- Start a new session
                self.charDB.session.startTime = time()
                self.charDB.session.endTime = 0
                self.charDB.session.totalVendorValue = 0
                self.charDB.session.totalAHValue = 0
                self.charDB.session.itemsLooted = {}
                self.charDB.session.rawGoldLooted = 0
                self.charDB.session.lastSaveTime = time()
                self:Print("New session started.")
                self:UpdateMainFrame()
            else
                self:Print("No data in current session to save.")
            end
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
            self:Print("Sessions Recorded: " .. #self:GetSessionHistory())
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
                self:UpdateMainFrame()
            elseif args == "history" then
                self:ClearSessionHistory()
            elseif args == "all" then
                self:ResetCharData()
            else
                self:Print("Usage: /lootsesh reset session|history|all")
            end
        else
            self:Print("Unknown command. Type /lootsesh help for available commands.")
        end
    end
end

-- Export addon to global namespace for debugging (optional)
_G["LootSesh"] = addon