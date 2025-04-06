-- Vault Item Reader Interface (Cards, Trinkets, Gear, Jewels)
local vaultReader = peripheral.wrap("left")
if not vaultReader then error("Vault reader not found on left side!") end
local monitor = peripheral.wrap("right")
if not monitor then error("Monitor not found on right side!") end
local router = peripheral.wrap("top")
if not router then error("Modular router not found on top!") end

-- File paths and data storage
local DATA_PATHS = {
    trinket = "trinket_log.json",
    card = "card_log.json",
    gear = "gear_log.json",
    jewel = "jewel_log.json"
}
local debugLogPath = "vault_reader_debug.txt"

-- Initialize debug logging
local function debugLog(message)
    local file = fs.open(debugLogPath, "a")
    if file then
        file.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. ": " .. tostring(message))
        file.close()
    end
end

-- Safe call wrapper function
local function safeCall(func, default)
    if not func then return default end
    local success, result = pcall(func)
    if success then
        return result
    else
        debugLog("Error: " .. tostring(result))
        return default
    end
end

-- Color theme
local theme = {
    background = colors.black,
    header = colors.cyan,
    headerText = colors.black,
    buttonArea = colors.gray,
    buttonNormal = colors.lightGray,
    buttonSelected = colors.cyan,
    buttonHover = colors.white,
    contentArea = colors.black,
    text = colors.white,
    highlight = colors.cyan,
    separator = colors.white,
    itemColors = {
        COMMON = colors.white,
        RARE = colors.yellow,
        EPIC = colors.magenta,
        OMEGA = colors.red,
        SCRAPPY = colors.lightGray
    },
    scrollIndicator = colors.cyan,
    divider = "="
}

-- Function to detect item type
local function detectItemType()
    local itemDetail = safeCall(function() return vaultReader.getItemDetail(1) end)
    if not itemDetail then return nil end
    
    -- Check for cards first (they might not have "Vault" in the name)
    local cardName = safeCall(function() return vaultReader.getCardName() end)
    if cardName then
        return "card"
    end
    
    -- Check for trinkets (they might not have "Vault" in the name)
    local isTrinket = safeCall(function() return vaultReader.isTrinket() end, false)
    if isTrinket then
        return "trinket"
    end
    
    -- For gear and jewels, validate that this is a vault item
    local displayName = itemDetail.displayName or ""
    if not displayName:match("Vault") then
        return nil
    end
    
    -- Check for jewel by looking at first implicit (Size modifier)
    local implicitCount = safeCall(function() return vaultReader.getImplicitCount() end, 0)
    if implicitCount > 0 then
        local firstImplicit = safeCall(function() return vaultReader.getImplicit(0) end)
        if firstImplicit and firstImplicit ~= "null" then
            local implicitName = safeCall(function() return vaultReader.getName(firstImplicit) end)
            if implicitName == "Size" then
                return "jewel"
            end
        end
    end
    
    -- If it has any affixes but isn't a jewel, it's gear
    local prefixCount = safeCall(function() return vaultReader.getPrefixCount() end, 0)
    local suffixCount = safeCall(function() return vaultReader.getSuffixCount() end, 0)
    if prefixCount > 0 or suffixCount > 0 then
        return "gear"
    end
    
    return nil
end

-- Move item from vault reader to router
local function moveItemToRouter()
    -- Extract from vault reader
    local itemDetails = safeCall(function() return vaultReader.getItemDetail(1) end)
    if not itemDetails then return false end
    
    -- Push to router on top
    local success = false
    for i = 1, 27 do -- Try all router slots
        success = safeCall(function() 
            return vaultReader.pushItems("top", 1, 1, i)
        end, 0) > 0
        if success then break end
    end
    
    if not success then
        debugLog("Failed to move item to router - router might be full")
    end
    return success
end

-- Format modifier names for readability
local function formatModifierName(name)
    if not name then return "Unknown" end
    if name == "VanillaImmortality" then
        return "Vanilla Immortal"
    end
    
    -- Normal formatting for other names
    local formatted = name:gsub("([^A-Z])([A-Z])", "%1 %2")
                         :gsub("([A-Z])([A-Z][^A-Z])", "%1 %2")
    return formatted
end

-- Format values nicely
local function formatValue(value)
    if type(value) == "number" then
        if value % 1 == 0 then
            return tostring(value)
        else
            return string.format("%.2f", value)
        end
    end
    return tostring(value)
end

-- Format table for display
local function formatTable(t)
    if type(t) ~= "table" then return tostring(t) end
    return table.concat(t, ", ")
end

-- Create a hash for item to prevent duplicate saves
local function generateItemHash(item)
    if not item then return nil end
    
    local hashParts = {}
    
    if item.type == "card" then
        -- Card hash based on name, tier, color, model and types
        table.insert(hashParts, item.name or "")
        table.insert(hashParts, tostring(item.tier or 0))
        table.insert(hashParts, item.color or "")
        table.insert(hashParts, item.model or "")
        if item.types then
            table.sort(item.types)
            table.insert(hashParts, table.concat(item.types, "-"))
        end
    elseif item.type == "trinket" then
        -- Trinket hash based on effect, total uses, and slot (but not remaining uses)
        table.insert(hashParts, item.effect or "")
        table.insert(hashParts, tostring(item.totalUses or 0))
        table.insert(hashParts, item.slot or "")
    elseif item.type == "gear" then
        -- Gear hash based on permanent properties: name, rarity, level, repair slots, plus affixes
        table.insert(hashParts, item.name or "")
        table.insert(hashParts, item.rarity or "")
        table.insert(hashParts, tostring(item.itemLevel or 0))
        table.insert(hashParts, tostring(item.repairSlots or 0))
        
        -- Process modifier collections with a helper function
        local function addModifierInfo(modifiers)
            local info = {}
            for _, mod in ipairs(modifiers or {}) do
                table.insert(info, (mod.name or "") .. ":" .. tostring(mod.value or 0) .. ":" .. (mod.type or "normal"))
            end
            table.sort(info)
            table.insert(hashParts, table.concat(info, ";"))
        end
        
        -- Add prefix, suffix and implicit info
        addModifierInfo(item.prefixes)
        addModifierInfo(item.suffixes)
        addModifierInfo(item.implicits)
    elseif item.type == "jewel" then
        -- Jewel hash based on name, size, level, rarity plus suffixes
        table.insert(hashParts, item.name or "")
        table.insert(hashParts, tostring(item.size or 0))
        table.insert(hashParts, tostring(item.itemLevel or 0))
        table.insert(hashParts, item.rarity or "")
        
        -- Add suffix info
        local suffixInfo = {}
        for _, suffix in ipairs(item.suffixes or {}) do
            table.insert(suffixInfo, (suffix.name or "") .. ":" .. tostring(suffix.value or 0) .. ":" .. (suffix.type or "normal"))
        end
        table.sort(suffixInfo)
        table.insert(hashParts, table.concat(suffixInfo, ";"))
    end
    
    -- Join all hash parts and compute a simple hash
    local combined = table.concat(hashParts, "|")
    
    -- Simple string hashing function using djb2 algorithm without bit operations
    local function hashString(str)
        local hash = 0
        for i = 1, #str do
            hash = (hash * 33 + str:byte(i)) % 4294967296 -- 2^32
        end
        return tostring(hash)
    end
    
    return hashString(combined)
end

-- Function to get modifier data safely
local function getModifierData(getModFunc, index)
    local modifier = safeCall(function() return getModFunc(index) end)
    if not modifier or modifier == "empty" or modifier == "null" then
        return nil
    end
    
    return {
        name = safeCall(function() return vaultReader.getName(modifier) end, "Unknown"),
        value = safeCall(function() return vaultReader.getModifierValue(modifier) end),
        type = safeCall(function() return vaultReader.getType(modifier) end, "normal"),
        minRoll = safeCall(function() return vaultReader.getMinimumRoll(modifier) end),
        maxRoll = safeCall(function() return vaultReader.getMaximumRoll(modifier) end)
    }
end

-- Get modifiers collection (prefixes, suffixes, implicits)
local function getModifiersCollection(type, countFunc, getModFunc)
    local modifiers = {}
    local count = safeCall(countFunc, 0)
    
    for i = 0, count - 1 do
        local modData = getModifierData(getModFunc, i)
        if modData then
            table.insert(modifiers, modData)
        end
    end
    
    return modifiers
end

-- Get current item data functions
local itemDataGetters = {
    trinket = function()
        if not safeCall(function() return vaultReader.isTrinket() end, false) then
            return nil
        end
    
        return {
            timestamp = os.date("%Y-%m-%d %H:%M:%S"),
            id = tostring(os.epoch("utc")),
            effect = safeCall(function() return vaultReader.getTrinketEffect() end, "Unknown"),
            totalUses = safeCall(function() return vaultReader.getTrinketUses() end, 0),
            remainingUses = safeCall(function() return vaultReader.getTrinketRemainingUses() end, 0),
            slot = safeCall(function() return vaultReader.getTrinketSlot() end, "Unknown"),
            description = safeCall(function() return vaultReader.getTrinketDescription() end, "No description"),
            identified = safeCall(function() return vaultReader.isTrinketIdentified() end, false),
            type = "trinket"
        }
    end,
    
    card = function()
        if detectItemType() ~= "card" then return nil end
        
        local isFoil = false
        local groups = safeCall(function() return vaultReader.getCardGroups() end, {})
        if groups then
            isFoil = table.concat(groups):find("Foil") ~= nil
        end
        
        return {
            timestamp = os.date("%Y-%m-%d %H:%M:%S"),
            id = tostring(os.epoch("utc")),
            name = safeCall(function() return vaultReader.getCardName() end, "Unknown Card"),
            tier = safeCall(function() return vaultReader.getCardTier() end, 0),
            color = safeCall(function() return vaultReader.getCardColor() end, "COMMON"),
            groups = groups,
            types = safeCall(function() return vaultReader.getCardTypes() end, {}),
            model = safeCall(function() return vaultReader.getCardModel() end, "unknown"),
            upgradable = safeCall(function() return vaultReader.canCardBeUpgraded() end, false),
            isFoil = isFoil,
            type = "card"
        }
    end,
    
    gear = function()
        if detectItemType() ~= "gear" then return nil end
        
        local itemDetail = safeCall(function() return vaultReader.getItemDetail(1) end)
        if not itemDetail then return nil end
        
        return {
            timestamp = os.date("%Y-%m-%d %H:%M:%S"),
            id = tostring(os.epoch("utc")),
            name = itemDetail.displayName or "Unknown Gear",
            itemLevel = safeCall(function() return vaultReader.getItemLevel() end, 0),
            rarity = safeCall(function() return vaultReader.getRarity() end, "COMMON"),
            repairSlots = safeCall(function() return vaultReader.getRepairSlots() end, 0),
            usedRepairSlots = safeCall(function() return vaultReader.getUsedRepairSlots() end, 0),
            type = "gear",
            prefixes = getModifiersCollection("prefixes", 
                        function() return vaultReader.getPrefixCount() end,
                        function(i) return vaultReader.getPrefix(i) end),
            suffixes = getModifiersCollection("suffixes", 
                        function() return vaultReader.getSuffixCount() end,
                        function(i) return vaultReader.getSuffix(i) end),
            implicits = getModifiersCollection("implicits", 
                         function() return vaultReader.getImplicitCount() end,
                         function(i) return vaultReader.getImplicit(i) end)
        }
    end,
    
    jewel = function()
        if detectItemType() ~= "jewel" then return nil end
        
        local itemDetail = safeCall(function() return vaultReader.getItemDetail(1) end)
        if not itemDetail then return nil end
        
        -- Getting jewel size from first implicit
        local size = 0
        local firstImplicit = safeCall(function() return vaultReader.getImplicit(0) end)
        if firstImplicit and firstImplicit ~= "null" then
            size = safeCall(function() return vaultReader.getModifierValue(firstImplicit) end, 0)
        end
        
        return {
            timestamp = os.date("%Y-%m-%d %H:%M:%S"),
            id = tostring(os.epoch("utc")),
            name = itemDetail.displayName or "Unknown Jewel",
            size = size,
            itemLevel = safeCall(function() return vaultReader.getItemLevel() end, 0),
            rarity = safeCall(function() return vaultReader.getRarity() end, "COMMON"),
            type = "jewel",
            suffixes = getModifiersCollection("suffixes", 
                        function() return vaultReader.getSuffixCount() end,
                        function(i) return vaultReader.getSuffix(i) end)
        }
    end
}

-- Get current item (auto-detect type)
local function getCurrentItem()
    local itemType = detectItemType()
    if not itemType then return nil end
    
    local getter = itemDataGetters[itemType]
    if getter then return getter() end
    
    return nil
end

-- ==========================================
-- NEW ITEM HISTORY SYSTEM
-- ==========================================

-- Convert old format log file to new JSON format
local function migrateOldLogFile(oldPath, newPath)
    if not fs.exists(oldPath) then return false end
    if fs.exists(newPath) then return true end -- Already migrated
    
    debugLog("Migrating old log file: " .. oldPath .. " to " .. newPath)
    
    local oldFile = fs.open(oldPath, "r")
    if not oldFile then return false end
    
    local content = oldFile.readAll()
    oldFile.close()
    
    if not content or content == "" then
        -- Create empty JSON file
        local newFile = fs.open(newPath, "w")
        newFile.write("{}")
        newFile.close()
        return true
    end
    
    -- Try to parse old format
    local items = {}
    
    -- First try as a single serialized table
    local success, allItems = pcall(function() return textutils.unserialize(content) end)
    
    if success and type(allItems) == "table" then
        items = allItems
    else
        -- Try line-by-line parsing
        for line in string.gmatch(content, "[^\r\n]+") do
            if line:gsub("%s", "") ~= "" then
                local success, item = pcall(function() return textutils.unserialize(line) end)
                if success and type(item) == "table" then
                    table.insert(items, item)
                end
            end
        end
    end
    
    -- Create item index by hash
    local itemsByHash = {}
    for _, item in ipairs(items) do
        local hash = generateItemHash(item)
        if hash then
            itemsByHash[hash] = item
        end
    end
    
    -- Save in new JSON format
    local newFile = fs.open(newPath, "w")
    newFile.write(textutils.serializeJSON(itemsByHash))
    newFile.close()
    
    debugLog("Migration complete: " .. #items .. " items migrated")
    return true
end

-- Load and migrate all item history files
local function migrateAllItemHistory()
    local oldPaths = {
        trinket = "trinket_log.txt",
        card = "card_log.txt",
        gear = "gear_log.txt",
        jewel = "jewel_log.txt"
    }
    
    for itemType, oldPath in pairs(oldPaths) do
        migrateOldLogFile(oldPath, DATA_PATHS[itemType])
    end
end

-- Load items from history file
local function loadHistoricalItems(path)
    -- Create new file if it doesn't exist
    if not fs.exists(path) then
        debugLog("Creating new log file: " .. path)
        local file = fs.open(path, "w")
        if file then
            file.write("{}")
            file.close()
        end
        return {}
    end
    
    -- Read the file
    local file = fs.open(path, "r")
    if not file then
        debugLog("Could not open log file for reading: " .. path)
        return {}
    end
    
    local content = file.readAll()
    file.close()
    
    if not content or content == "" then
        return {}
    end
    
    -- Parse JSON content
    local success, itemsByHash = pcall(function() return textutils.unserializeJSON(content) end)
    if not success or type(itemsByHash) ~= "table" then
        debugLog("Error parsing JSON from " .. path .. ": " .. tostring(itemsByHash))
        return {}
    end
    
    -- Convert hash map to array using a consistent order (by hash key)
    local itemsArray = {}
    local hashKeys = {}
    
    -- First collect all hash keys
    for hash in pairs(itemsByHash) do
        table.insert(hashKeys, hash)
    end
    
    -- Sort hash keys for consistent ordering
    table.sort(hashKeys)
    
    -- Build array in consistent order
    for _, hash in ipairs(hashKeys) do
        table.insert(itemsArray, itemsByHash[hash])
    end
    
    debugLog("Loaded " .. #itemsArray .. " items from " .. path)
    return itemsArray
end

-- Save item to history (with new JSON-based system)
local function saveItemToHistory(item, path)
    if not item or not path then return false end
    
    -- Generate hash for the item
    local itemHash = generateItemHash(item)
    if not itemHash then
        debugLog("Failed to generate hash for item")
        return false
    end
    
    -- Load existing items
    local itemsByHash = {}
    
    if fs.exists(path) then
        local file = fs.open(path, "r")
        if file then
            local content = file.readAll()
            file.close()
            
            if content and content ~= "" then
                local success, data = pcall(function() return textutils.unserializeJSON(content) end)
                if success and type(data) == "table" then
                    itemsByHash = data
                end
            end
        end
    end
    
    -- Check if item already exists
    if itemsByHash[itemHash] then
        debugLog("Item already exists in history, not saving: " .. itemHash)
        return false
    end
    
    -- Add the new item and save
    itemsByHash[itemHash] = item
    
    local file = fs.open(path, "w")
    if not file then
        debugLog("Failed to open log file for writing: " .. path)
        return false
    end
    
    file.write(textutils.serializeJSON(itemsByHash))
    file.close()
    
    debugLog("Saved new item: " .. (item.name or item.effect or "unknown"))
    return true
end

-- Sort items by field
local function sortItems(items)
    -- Create a stable sorting function
    table.sort(items, function(a, b)
        local aValue = a[sortField]
        local bValue = b[sortField]
        
        -- First compare the primary sort field
        if aValue ~= bValue then
            if type(aValue) == "number" and type(bValue) == "number" then
                return sortDesc and aValue > bValue or aValue < bValue
            end
            
            aValue = tostring(aValue or "")
            bValue = tostring(bValue or "")
            return sortDesc and aValue > bValue or aValue < bValue
        end
        
        -- If primary sort field values are equal, use a consistent secondary sort
        -- First try ID
        if a.id ~= b.id then
            return a.id < b.id  -- Always sort by ID in ascending order for ties
        end
        
        -- Then try timestamp
        if a.timestamp ~= b.timestamp then
            return a.timestamp < b.timestamp
        end
        
        -- Final fallback for complete stability
        return tostring(a.name or a.effect or "") < tostring(b.name or b.effect or "")
    end)
end

-- Migrate and load all item history
migrateAllItemHistory()
local historicalItems = {
    trinket = loadHistoricalItems(DATA_PATHS.trinket),
    card = loadHistoricalItems(DATA_PATHS.card),
    gear = loadHistoricalItems(DATA_PATHS.gear),
    jewel = loadHistoricalItems(DATA_PATHS.jewel)
}

-- Add these variables after the historicalItems declaration
local sortedHistoricalItems = {} -- Cached sorted copies
local lastSortConfig = {} -- Remember last sort settings for each item type

-- Replace sortItems function with this version
local function sortItems(items, itemType)
    -- Check if we need to resort (different field or direction than last time)
    local needsResort = lastSortConfig[itemType] == nil or
                       lastSortConfig[itemType].field ~= sortField or
                       lastSortConfig[itemType].desc ~= sortDesc
    
    -- If the sort is unchanged, return the cached sorted list
    if not needsResort and sortedHistoricalItems[itemType] then
        return sortedHistoricalItems[itemType]
    end
    
    -- Create a copy of items to sort (don't modify the original)
    local itemsCopy = {}
    for i, item in ipairs(items) do
        -- Add a stable index to ensure consistent ordering
        local itemCopy = {}
        for k, v in pairs(item) do
            itemCopy[k] = v
        end
        itemCopy._originalIndex = i  -- Add stable index
        table.insert(itemsCopy, itemCopy)
    end
    
    -- Sort the copy
    table.sort(itemsCopy, function(a, b)
        local aValue = a[sortField]
        local bValue = b[sortField]
        
        -- If values are different, sort by the selected field
        if aValue ~= bValue then
            if type(aValue) == "number" and type(bValue) == "number" then
                return sortDesc and aValue > bValue or aValue < bValue
            end
            
            aValue = tostring(aValue or "")
            bValue = tostring(bValue or "")
            return sortDesc and aValue > bValue or aValue < bValue
        end
        
        -- If values are the same, use the original index for stable sorting
        return a._originalIndex < b._originalIndex
    end)
    
    -- Clean up the _originalIndex we added
    for _, item in ipairs(itemsCopy) do
        item._originalIndex = nil
    end
    
    -- Cache the sorted result
    sortedHistoricalItems[itemType] = itemsCopy
    lastSortConfig[itemType] = {field = sortField, desc = sortDesc}
    
    return itemsCopy
end

-- Current state variables
local currentView = "main"  -- main, details, history, etc.
local viewingItem = nil     -- Currently viewing historical item
local sortField = "timestamp"
local sortDesc = true
local hoveredButton = nil
local scrollOffset = 0
local selectedCategory = nil -- For history view

-- UI constants that scale with screen size
local function getUIScaling()
    local w, h = monitor.getSize()
    return {
        buttonWidth = math.min(25, math.floor(w * 0.3)),
        contentStartX = math.min(27, math.floor(w * 0.32)) + 3,
        buttonSpacing = math.max(1, math.floor(h * 0.05)),
        headerHeight = 3,
    }
end

-- Get context buttons based on view
local function getContextButtons()
    local buttons = {{label = "Main View", view = "main"}}
    
    if viewingItem then
        table.insert(buttons, {label = "Details", view = "details"})
        
        -- Add specific views based on item type
        if viewingItem.type == "gear" then
            table.insert(buttons, {label = "Prefixes", view = "prefixes"})
            table.insert(buttons, {label = "Suffixes", view = "suffixes"})
            table.insert(buttons, {label = "Implicits", view = "implicits"})
        elseif viewingItem.type == "jewel" then
            table.insert(buttons, {label = "Suffixes", view = "suffixes"})
        end
        
        table.insert(buttons, {label = "Back", view = viewingItem.type .. "History"})
    else
        local item = getCurrentItem()
        if item then
            table.insert(buttons, {label = "Details", view = "details"})
            
            -- Add specific views based on item type
            if item.type == "gear" then
                table.insert(buttons, {label = "Prefixes", view = "prefixes"})
                table.insert(buttons, {label = "Suffixes", view = "suffixes"})
                table.insert(buttons, {label = "Implicits", view = "implicits"})
            elseif item.type == "jewel" then
                table.insert(buttons, {label = "Suffixes", view = "suffixes"})
            end
        end
        
        table.insert(buttons, {label = "History", view = "history"})
    end
    
    return buttons
end

-- Draw the UI elements (consolidated drawing functions)
local function drawUI()
    local w, h = monitor.getSize()
    local ui = getUIScaling()
    
    -- Clear screen
    monitor.setBackgroundColor(theme.background)
    monitor.clear()
    
    -- Draw header
    for i = 1, 2 do
        monitor.setCursorPos(1, i)
        monitor.setBackgroundColor(theme.header)
        monitor.write(string.rep(" ", w))
    end
    
    -- Set header text
    local itemType = "Item"
    local currentItem = viewingItem or getCurrentItem()
    if currentItem then
        itemType = string.upper(currentItem.type:sub(1,1)) .. currentItem.type:sub(2)
    end
    
    local headerText = "Vault " .. itemType .. " Reader"
    local headerX = math.floor((w - #headerText) / 2) + 1
    monitor.setCursorPos(headerX, 1)
    monitor.setBackgroundColor(theme.header)
    monitor.setTextColor(theme.headerText)
    monitor.write(headerText)
    
    -- Subheader with current view
    local subHeader = "View: " .. currentView:upper()
    monitor.setCursorPos(2, 2)
    monitor.setBackgroundColor(theme.header)
    monitor.setTextColor(theme.headerText)
    monitor.write(subHeader)
    
    -- Draw item name under header
    if currentItem then
        local name = ""
        if currentItem.type == "card" then
            name = currentItem.name
        elseif currentItem.type == "trinket" then
            name = currentItem.effect
        elseif currentItem.type == "gear" or currentItem.type == "jewel" then
            name = currentItem.name
        end
        
        if not name or name == "" then 
            name = "Unknown " .. currentItem.type:gsub("^%l", string.upper)
        end
        
        -- Calculate available space for the title
        local availableWidth = w - (ui.buttonWidth + 4)
        
        -- Truncate if too long
        if #name > availableWidth - 2 then
            name = name:sub(1, availableWidth - 5) .. "..."
        end
        
        -- Clear the title background area
        monitor.setCursorPos(ui.buttonWidth + 4, 4)
        monitor.setBackgroundColor(theme.contentArea)
        monitor.write(string.rep(" ", availableWidth))
        
        -- Center the name in the available space
        local nameX = ui.buttonWidth + 4 + math.floor((availableWidth - #name) / 2)
        monitor.setCursorPos(nameX, 4)
        monitor.setBackgroundColor(theme.contentArea)
        
        -- Use different color based on item rarity
        local itemColor = theme.text
        if currentItem.color then
            itemColor = theme.itemColors[currentItem.color] or theme.highlight
        elseif currentItem.rarity then
            itemColor = theme.itemColors[currentItem.rarity] or theme.highlight
        end
        
        monitor.setTextColor(itemColor)
        monitor.write(name)
    end
    
    -- Draw background for content area
    for y = 5, h do
        monitor.setCursorPos(1, y)
        monitor.setBackgroundColor(theme.background)
        monitor.write(string.rep(" ", w))
    end
end

-- Draw navigation buttons
local function drawNavButtons()
    local w, h = monitor.getSize()
    local ui = getUIScaling()
    local buttons = getContextButtons()
    
    -- Draw button area background
    for y = ui.headerHeight + 1, h-1 do
        monitor.setCursorPos(1, y)
        monitor.setBackgroundColor(theme.buttonArea)
        monitor.write(string.rep(" ", ui.buttonWidth + 2))
    end
    
    -- Draw each button
    for i, btn in ipairs(buttons) do
        local y = ui.headerHeight + 1 + (i-1) * (ui.buttonSpacing + 1)
        monitor.setCursorPos(1, y)
        
        -- Determine button color
        local bgColor
        if btn == hoveredButton then
            bgColor = theme.buttonHover
        elseif btn.view == currentView then
            bgColor = theme.buttonSelected
        else
            bgColor = theme.buttonNormal
        end
        
        monitor.setBackgroundColor(bgColor)
        monitor.setTextColor(theme.headerText)
        
        -- Draw button with centered text
        local padding = math.floor((ui.buttonWidth - #btn.label) / 2)
        monitor.write(" " .. string.rep(" ", padding-1) .. btn.label .. string.rep(" ", ui.buttonWidth - #btn.label - padding) .. " ")
        
        -- Store button coordinates for click detection
        btn.x1 = 1
        btn.x2 = ui.buttonWidth
        btn.y = y
    end
    
    -- Draw vertical separator
    local separatorX = ui.buttonWidth + 2
    for y = ui.headerHeight + 1, h-1 do
        monitor.setCursorPos(separatorX, y)
        monitor.setTextColor(theme.separator)
        monitor.write("|")
    end
    
    return buttons, ui.contentStartX
end

-- Draw content area background
local function drawContentArea(startX, startY)
    local w, h = monitor.getSize()
    monitor.setBackgroundColor(theme.contentArea)
    for y = startY, h-1 do
        monitor.setCursorPos(startX, y)
        monitor.write(string.rep(" ", w - startX))
    end
end

-- Display section header
local function displaySectionHeader(text, startX)
    local w = monitor.getSize()
    
    -- Draw content area background
    drawContentArea(startX, 6)
    
    -- Draw header text
    monitor.setCursorPos(startX, 6)
    monitor.setTextColor(theme.headerText)
    monitor.setBackgroundColor(theme.contentArea)
    monitor.write(text)
    
    -- Draw divider
    monitor.setCursorPos(startX, 8)
    monitor.setTextColor(theme.separator)
    monitor.write(string.rep(theme.divider, w - startX))
end

-- Draw stats table with optional progress bars for roll quality
local function drawStatsTable(stats, startX, startY, drawProgressBars)
    local w, h = monitor.getSize()
    local y = startY
    local maxDisplayLines = h - startY - 1
    
    for i = scrollOffset + 1, math.min(#stats, scrollOffset + maxDisplayLines) do
        local stat = stats[i]
        if y >= h-1 then break end
        
        -- Draw stat name
        monitor.setCursorPos(startX, y)
        monitor.setTextColor(theme.highlight)
        monitor.setBackgroundColor(stat.highlighted and theme.buttonSelected or theme.contentArea)
        local name = stat.name .. ":"
        monitor.write(name)
        
        -- Draw stat value (right-aligned)
        local value = tostring(stat.value)
        local valueX = w - #value - 2
        monitor.setCursorPos(valueX, y)
        
        -- Color coding for values
        if stat.color then
            monitor.setTextColor(theme.itemColors[stat.color] or theme.text)
        else
            monitor.setTextColor(theme.text)
        end
        
        monitor.write(value)
        
        -- Draw progress bar if requested
        if drawProgressBars and stat.rollPercentage and stat.minRoll and stat.maxRoll then
            y = y + 1
            if y >= h-1 then break end
            
            -- Draw progress bar (max width 20 characters)
            local maxBarWidth = 20
            local barWidth = math.min(maxBarWidth, w - startX - 10)
            local filledWidth = math.floor((stat.rollPercentage / 100) * barWidth)
            
            monitor.setCursorPos(startX, y)
            monitor.setTextColor(theme.text)
            monitor.setBackgroundColor(theme.contentArea)
            monitor.write("Quality: ")
            
            -- Bar background
            monitor.setBackgroundColor(colors.gray)
            monitor.write(string.rep(" ", barWidth))
            
            -- Filled portion
            local barColor = colors.red
            if stat.rollPercentage > 90 then
                barColor = colors.lime
            elseif stat.rollPercentage > 75 then
                barColor = colors.green
            elseif stat.rollPercentage > 50 then
                barColor = colors.yellow
            elseif stat.rollPercentage > 25 then
                barColor = colors.orange
            end
            
            monitor.setCursorPos(startX + 9, y)
            monitor.setBackgroundColor(barColor)
            monitor.write(string.rep(" ", filledWidth))
        end
        
        y = y + 1
    end
    
    -- Draw scroll indicators
    if #stats > maxDisplayLines then
        monitor.setCursorPos(w-1, startY)
        monitor.setTextColor(theme.scrollIndicator)
        monitor.setBackgroundColor(theme.contentArea)
        monitor.write("▲")
        monitor.setCursorPos(w-1, h-2)
        monitor.write("▼")
    end
end

-- Sort items by field
local function sortItems(items)
    table.sort(items, function(a, b)
        local aValue = a[sortField]
        local bValue = b[sortField]
        
        if type(aValue) == "number" and type(bValue) == "number" then
            return sortDesc and aValue > bValue or aValue < bValue
        end
        
        aValue = tostring(aValue or "")
        bValue = tostring(bValue or "")
        return sortDesc and aValue > bValue or aValue < bValue
    end)
end

-- Display specific item view (trinket, card, gear, jewel)
local function displayItemView(startX, itemType, item)
    local typeLabels = {
        trinket = "Trinket Overview",
        card = "Card Overview",
        gear = "Gear Overview",
        jewel = "Jewel Overview" 
    }
    
    displaySectionHeader(typeLabels[itemType] or "Item Overview", startX)
    
    -- Get item data
    item = item or (itemDataGetters[itemType] and itemDataGetters[itemType]())
    
    if not item then
        monitor.setCursorPos(startX, 9)
        monitor.setTextColor(theme.text)
        monitor.write("No " .. itemType .. " detected")
        return
    end
    
    -- Build stats table based on item type
    local stats = {}
    
    if itemType == "trinket" then
        stats = {
            {name = "Effect", value = item.effect},
            {name = "Remaining Uses", value = item.remainingUses .. "/" .. item.totalUses},
            {name = "Slot", value = item.slot},
            {name = "Identified", value = item.identified and "Yes" or "No"}
        }
    elseif itemType == "card" then
        local w = monitor.getSize()
        stats = {
            {name = "Card Tier", value = item.tier},
            {name = "Card Color", value = item.color, color = item.color},
            {name = "Foil Card", value = item.isFoil and "Yes" or "No"},
            {name = "Can Upgrade", value = item.upgradable and "Yes" or "No"}
        }
        
        if item.upgradable then
            table.insert(stats, {name = "Upgrades To", value = "Tier " .. (item.tier + 1)})
        end
        
        if item.types and #item.types > 0 then
            local typesText = formatTable(item.types)
            if #typesText > w - startX - 15 then
                typesText = typesText:sub(1, w - startX - 18) .. "..."
            end
            table.insert(stats, {name = "Card Types", value = typesText})
        end
        
        if item.model then
            local modelText = item.model
            if #modelText > w - startX - 15 then
                modelText = modelText:sub(1, w - startX - 18) .. "..."
            end
            table.insert(stats, {name = "Model ID", value = modelText})
        end
    elseif itemType == "gear" then
        stats = {
            {name = "Item Level", value = item.itemLevel},
            {name = "Rarity", value = item.rarity, color = item.rarity},
            {name = "Repair Slots", value = item.repairSlots .. " (" .. item.usedRepairSlots .. " used)"},
            {name = "Prefixes", value = #item.prefixes},
            {name = "Suffixes", value = #item.suffixes},
            {name = "Implicits", value = #item.implicits}
        }
    elseif itemType == "jewel" then
        stats = {
            {name = "Size", value = item.size},
            {name = "Item Level", value = item.itemLevel},
            {name = "Rarity", value = item.rarity, color = item.rarity},
            {name = "Suffixes", value = #item.suffixes}
        }
    end
    
    drawStatsTable(stats, startX, 9)
end

-- Display details view
local function displayDetailsView(startX)
    local item = viewingItem or getCurrentItem()
    if not item then
        displaySectionHeader("No Item Detected", startX)
        return
    end
    
    displaySectionHeader(item.type:gsub("^%l", string.upper) .. " Details", startX)
    
    local stats = {
        {name = "Timestamp", value = item.timestamp},
        {name = "Item ID", value = item.id}
    }
    
    -- Add type-specific details
    if item.type == "card" and item.groups and #item.groups > 0 then
        table.insert(stats, {name = "Groups", value = formatTable(item.groups)})
        table.insert(stats, {name = "Model", value = item.model})
    elseif item.type == "trinket" then
        table.insert(stats, {name = "Description", value = item.description})
    end
    
    drawStatsTable(stats, startX, 9)
end

-- Prepare modifier stats with roll quality calculations
local function prepareModifierStats(modifiers)
    local stats = {}
    
    for _, mod in ipairs(modifiers or {}) do
        local value = mod.value and formatValue(mod.value) or "N/A"
        local displayName = formatModifierName(mod.name)
        local rollQuality = ""
        local rollPercentage = 0
        
        -- Add roll range if available
        if mod.minRoll and mod.maxRoll and mod.minRoll ~= mod.maxRoll then
            local range = " (" .. formatValue(mod.minRoll) .. "-" .. formatValue(mod.maxRoll) .. ")"
            
            -- Calculate roll quality
            if mod.maxRoll > mod.minRoll then
                rollPercentage = ((mod.value - mod.minRoll) / (mod.maxRoll - mod.minRoll)) * 100
                rollPercentage = math.min(100, math.max(0, rollPercentage))
                
                local qualityText
                if rollPercentage > 90 then
                    qualityText = "Perfect"
                elseif rollPercentage > 75 then
                    qualityText = "High"
                elseif rollPercentage > 50 then
                    qualityText = "Average"
                elseif rollPercentage > 25 then
                    qualityText = "Low"
                else
                    qualityText = "Poor"
                end
                
                local percentText = string.format("%.1f%%", rollPercentage)
                rollQuality = " [" .. qualityText .. " - " .. percentText .. "]"
            end
            
            value = value .. range .. rollQuality
        end
        
        table.insert(stats, {
            name = displayName,
            value = value,
            highlighted = mod.type == "legendary",
            color = mod.type == "legendary" and "EPIC" or nil,
            rollPercentage = rollPercentage,
            minRoll = mod.minRoll,
            maxRoll = mod.maxRoll
        })
    end
    
    return stats
end

-- Display modifiers view (prefixes, suffixes or implicits)
local function displayModifiersView(startX, modType)
    local item = viewingItem or getCurrentItem()
    if not item then
        displaySectionHeader("No Item Detected", startX)
        return
    end
    
    local modifiers = {}
    local titles = {
        prefixes = "Prefix Modifiers",
        suffixes = "Suffix Modifiers",
        implicits = "Implicit Modifiers"
    }
    
    displaySectionHeader(titles[modType] or "Modifiers", startX)
    
    if modType == "prefixes" and item.prefixes then
        modifiers = item.prefixes
    elseif modType == "suffixes" and item.suffixes then
        modifiers = item.suffixes
    elseif modType == "implicits" and item.implicits then
        modifiers = item.implicits
    end
    
    if #modifiers == 0 then
        monitor.setCursorPos(startX, 9)
        monitor.setTextColor(theme.text)
        monitor.write("No " .. modType .. " found")
        return
    end
    
    local stats = prepareModifierStats(modifiers)
    drawStatsTable(stats, startX, 9, true) -- true = draw progress bars
end

-- Display history category selection
local function displayHistoryCategorySelect(startX)
    displaySectionHeader("Select Item Type", startX)
    
    local categories = {
        {name = "Cards", count = #historicalItems.card, type = "card"},
        {name = "Trinkets", count = #historicalItems.trinket, type = "trinket"},
        {name = "Gear", count = #historicalItems.gear, type = "gear"},
        {name = "Jewels", count = #historicalItems.jewel, type = "jewel"}
    }
    
    local stats = {}
    for _, cat in ipairs(categories) do
        table.insert(stats, {
            name = cat.name,
            value = cat.count .. " items",
            type = cat.type,
            highlighted = (selectedCategory == cat.type)
        })
    end
    
    drawStatsTable(stats, startX, 9)
end

-- Display history view for a specific item type
local function displayHistoryView(startX, itemType)
    if not itemType then 
        return displayHistoryCategorySelect(startX)
    end
    
    local w, h = monitor.getSize()
    local originalItems = historicalItems[itemType] or {}
    
    -- Define sort options based on item type
    local sortOptions = {
        card = {
            {field = "tier", label = "Tier"},
            {field = "name", label = "Name"},
            {field = "color", label = "Color"},
            {field = "timestamp", label = "Time"}
        },
        trinket = {
            {field = "effect", label = "Effect"},
            {field = "slot", label = "Slot"},
            {field = "timestamp", label = "Time"}
        },
        gear = {
            {field = "itemLevel", label = "Level"},
            {field = "name", label = "Name"},
            {field = "rarity", label = "Rarity"},
            {field = "timestamp", label = "Time"}
        },
        jewel = {
            {field = "size", label = "Size"},
            {field = "name", label = "Name"},
            {field = "rarity", label = "Rarity"},
            {field = "timestamp", label = "Time"}
        }
    }
    
    displaySectionHeader(itemType:gsub("^%l", string.upper) .. " History", startX)
    
    -- Display sort options
    monitor.setCursorPos(startX, 7)
    monitor.setTextColor(theme.text)
    monitor.write("Sort by: ")
    
    local buttonX = startX + 9
    local options = sortOptions[itemType] or {}
    
    for _, option in ipairs(options) do
        local isSelected = (sortField == option.field)
        local buttonText = option.label
        if isSelected then
            buttonText = buttonText .. (sortDesc and " ▼" or " ▲")
        end
        
        monitor.setCursorPos(buttonX, 7)
        monitor.setBackgroundColor(isSelected and theme.buttonSelected or theme.buttonNormal)
        monitor.setTextColor(isSelected and theme.headerText or theme.text)
        monitor.write(" " .. buttonText .. " ")
        
        -- Store button data for click detection
        option.x1 = buttonX
        option.x2 = buttonX + #buttonText + 1
        option.y = 7
        
        buttonX = buttonX + #buttonText + 3
    end
    
    -- Get the sorted items
    local sortedItems = sortItems(originalItems, itemType)
    
    -- Draw items in history
    if #sortedItems == 0 then
        monitor.setCursorPos(startX, 9)
        monitor.setTextColor(theme.text)
        monitor.write("No " .. itemType .. "s in history")
        return options
    end
    
    local stats = {}
    for i, item in ipairs(sortedItems) do
        -- Format display string based on item type
        local displayStr = ""
        
        if itemType == "card" then
            displayStr = string.format("T%d %s", item.tier or 0, item.name or "Unknown Card")
        elseif itemType == "trinket" then
            displayStr = string.format("%s (%s)", 
                item.effect or "Unknown Effect",
                (item.remainingUses or 0) .. "/" .. (item.totalUses or 0))
        elseif itemType == "gear" then
            displayStr = string.format("Lvl %d %s", item.itemLevel or 0, item.name or "Unknown Gear")
        elseif itemType == "jewel" then
            displayStr = string.format("Size %d %s", item.size or 0, item.name or "Unknown Jewel")
        end
        
        -- Truncate if too long
        if #displayStr > w - startX - 10 then
            displayStr = displayStr:sub(1, w - startX - 13) .. "..."
        end
        
        table.insert(stats, {
            id = item.id,
            name = tostring(i),
            value = displayStr,
            color = item.color or item.rarity,
            item = item
        })
    end
    
    drawStatsTable(stats, startX, 9)
    return options
end

-- Save current item
local function saveCurrentItem()
    local item = getCurrentItem()
    if not item then return false end
    
    local path = DATA_PATHS[item.type]
    if not path then return false end
    
    if saveItemToHistory(item, path) then
        -- Reload the specific item type history
        historicalItems[item.type] = loadHistoricalItems(path)
        -- Invalidate the cache for this item type
        sortedHistoricalItems[item.type] = nil
        lastSortConfig[item.type] = nil
        -- Move item to router after successful save
        moveItemToRouter()
        return true
    end
    
    return false
end

-- Main loop
local lastItemHash = nil -- Track last seen item's hash
local lastTouch = {x = -1, y = -1, time = 0} -- Prevent click carryover

while true do
    drawUI()
    local buttons, contentStartX = drawNavButtons()
    
    -- Auto-save new items and handle item movement (only if not viewing historical item)
    if not viewingItem then
        local currentItem = getCurrentItem()
        local itemInReader = safeCall(function() return vaultReader.getItemDetail(1) end) ~= nil
        
        -- Always try to move item if something is in the reader
        if itemInReader then
            if currentItem then
                local currentHash = generateItemHash(currentItem)
                
                if currentHash and currentHash ~= lastItemHash then
                    debugLog("New item detected with hash: " .. currentHash)
                    
                    -- Try to save if it's a valid item
                    local saved = saveCurrentItem()
                    if saved then
                        -- Display saved notification
                        local w = monitor.getSize()
                        monitor.setCursorPos(w-12, 2)
                        monitor.setBackgroundColor(theme.header)
                        monitor.setTextColor(colors.lime)
                        monitor.write("Item Saved!")
                    end
                    lastItemHash = currentHash
                end
            end
            
            -- Always try to move the item, regardless of whether it was saved or even valid
            moveItemToRouter()
        else
            lastItemHash = nil -- Reset hash when no item is present
        end
    end
    
    -- Display current view
    local sortOptions = {}
    if currentView == "main" then
        local item = viewingItem or getCurrentItem()
        if item then
            displayItemView(contentStartX, item.type, item)
        else
            displaySectionHeader("No Item Detected", contentStartX)
            monitor.setCursorPos(contentStartX, 9)
            monitor.setTextColor(theme.text)
            monitor.write("Please insert an item")
        end
    elseif currentView == "details" then
        displayDetailsView(contentStartX)
    elseif currentView == "prefixes" or currentView == "suffixes" or currentView == "implicits" then
        displayModifiersView(contentStartX, currentView)
    elseif currentView == "history" then
        displayHistoryCategorySelect(contentStartX)
    elseif currentView == "cardHistory" then
        sortOptions = displayHistoryView(contentStartX, "card")
    elseif currentView == "trinketHistory" then
        sortOptions = displayHistoryView(contentStartX, "trinket")
    elseif currentView == "gearHistory" then
        sortOptions = displayHistoryView(contentStartX, "gear")
    elseif currentView == "jewelHistory" then
        sortOptions = displayHistoryView(contentStartX, "jewel")
    end
    
    -- Handle input events
    local timer = os.startTimer(0.5)
    local event, param1, x, y = os.pullEvent()
    
    -- Prevent duplicate clicks across views
    local currentTime = os.clock()
    local isDuplicateClick = (event == "monitor_touch" and 
                             x == lastTouch.x and 
                             y == lastTouch.y and 
                             currentTime - lastTouch.time < 0.5)
    
    if event == "monitor_touch" and not isDuplicateClick then
        lastTouch = {x = x, y = y, time = currentTime}
        hoveredButton = nil
        
        -- Handle sort button clicks
        if y == 7 and #sortOptions > 0 then
            local itemType = currentView:match("^(.+)History$")
            for _, sortOpt in ipairs(sortOptions) do
                if x >= sortOpt.x1 and x <= sortOpt.x2 and y == sortOpt.y then
                    if sortField == sortOpt.field then
                        -- Toggle direction if clicking the same field again
                        sortDesc = not sortDesc
                    else
                        -- Set new sort field with default direction (descending)
                        sortField = sortOpt.field
                        sortDesc = true
                    end
                    -- Invalidate cache when changing sort
                    sortedHistoricalItems[itemType] = nil
                    lastSortConfig[itemType] = nil
                    break
                end
            end
        end
        
        -- Handle history category selection
        if currentView == "history" and y >= 9 then
            local clickedIndex = y - 9 + scrollOffset
            local categories = {"card", "trinket", "gear", "jewel"}
            if clickedIndex+1 <= #categories then
                currentView = categories[clickedIndex+1] .. "History"
                scrollOffset = 0
            end
        end
        
        -- Handle history item clicks
        if currentView:find("History$") and y >= 9 then
            local itemType = currentView:match("^(.+)History$")
            if itemType and historicalItems[itemType] then
                local clickedIndex = y - 9 + scrollOffset
                if clickedIndex+1 <= #historicalItems[itemType] then
                    viewingItem = historicalItems[itemType][clickedIndex+1]
                    currentView = "main"
                    scrollOffset = 0
                end
            end
        end
        
        -- Handle navigation buttons
        for _, btn in ipairs(buttons) do
            if x >= btn.x1 and x <= btn.x2 and y == btn.y then
                currentView = btn.view
                scrollOffset = 0
                -- Clear viewingItem when navigating to main or history view
                if btn.view == "main" or btn.view == "history" then
                    viewingItem = nil
                end
                break
            end
        end
        
        -- Handle scroll indicators
        local w, h = monitor.getSize()
        if x == w-1 then
            if y == 9 and scrollOffset > 0 then
                scrollOffset = scrollOffset - 1
            elseif y == h-2 then
                local currentItems = {}
                if currentView:find("History$") then
                    local itemType = currentView:match("^(.+)History$")
                    currentItems = historicalItems[itemType] or {}
                end
                
                if scrollOffset + (h-9-1) < #currentItems then
                    scrollOffset = scrollOffset + 1
                end
            end
        end
    elseif event == "key" then
        -- Keyboard shortcuts
        if param1 == keys.s then
            -- Manual save
            saveCurrentItem()
        elseif param1 == keys.h then
            -- History view
            viewingItem = nil
            currentView = "history"
            scrollOffset = 0
        elseif param1 == keys.m then
            -- Main view
            currentView = "main"
            scrollOffset = 0
        elseif param1 == keys.d then
            -- Details view
            currentView = "details" 
            scrollOffset = 0
        elseif param1 == keys.backspace or param1 == keys.delete then
            -- Clear viewing item
            viewingItem = nil
            currentView = "main"
            scrollOffset = 0
        end
    end
end