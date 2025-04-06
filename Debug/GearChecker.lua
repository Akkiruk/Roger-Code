-- Enhanced Vault Reader Display Interface with Basalt integration
local basalt = require("basalt")
local vaultReader = peripheral.wrap("left")
if not vaultReader then error("Vault reader not found on left side!") end
local monitor = peripheral.wrap("right")
if not monitor then error("Monitor not found on right side!") end

-- File paths and data storage
local logFilePath = "item_log.txt"
local debugLogPath = "card_shop_debug.txt"

-- Initialize debug logging first
local function debugLog(message)
    local file = fs.open(debugLogPath, "a")
    if file then
        file.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. ": " .. tostring(message))
        file.close()
    end
end

-- Load historical items function (simplified and more robust)
local function loadHistoricalItems()
    if not fs.exists(logFilePath) then
        debugLog("Creating new log file")
        local file = fs.open(logFilePath, "w")
        if file then
            file.close()
        end
        return {}
    end
    
    local items = {}
    local file = fs.open(logFilePath, "r")
    if not file then
        debugLog("Could not open log file for reading")
        return {}
    end
    
    while true do
        local line = file.readLine()
        if not line then break end
        
        local success, item = pcall(textutils.unserialize, line)
        if success and item and type(item) == "table" then
            table.insert(items, item)
            debugLog("Loaded item: " .. (item.name or "unknown"))
        else
            debugLog("Failed to load item from line: " .. tostring(line))
        end
    end
    
    file.close()
    debugLog("Loaded " .. #items .. " items from history")
    return items
end

-- Load historical items immediately
local historicalItems = loadHistoricalItems()
debugLog("Initial history load complete. Items loaded: " .. #historicalItems)

-- Current view state and theme
local currentView = "history"
local scrollOffset = 0
local currentItemType = nil
local hoveredButton = nil
local selectedHistoryIndex = 1
local historySortField = "type"
local historySortDesc = false
local viewingHistoricalItem = nil

-- Color theme
local theme = {
    background = colors.black,
    header = colors.cyan,             -- Modern cyan header
    headerText = colors.black,        -- Black text on cyan for contrast
    buttonArea = colors.gray,         -- Dark gray button area
    buttonNormal = colors.lightGray,  -- Light gray buttons
    buttonSelected = colors.cyan,     -- Cyan for selected
    buttonHover = colors.white,       -- White hover for pop
    contentArea = colors.black,       -- Pure black background
    text = colors.white,             -- White text
    highlight = colors.cyan,         -- Cyan highlights
    separator = colors.white,        -- White separator
    legendary = colors.orange,       -- Keep distinctive colors
    rare = colors.yellow,
    normal = colors.white,
    scrollIndicator = colors.cyan,   -- Cyan scroll indicators
    divider = "="
}

-- UI constants that scale with screen size
local function getScaledUI()
    local w, h = monitor.getSize()
    return {
        buttonWidth = math.min(25, math.floor(w * 0.3)), -- Increased width for longer names
        contentStartX = math.min(27, math.floor(w * 0.32)) + 3, -- Adjusted to match new button width
        buttonSpacing = math.max(1, math.floor(h * 0.05)),
        headerHeight = 3,
    }
end

-- Helper function for safe calls
local function safeCall(func, default)
  local ok, res = pcall(func)
  return ok and res or default
end

-- Function to format values nicely
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

-- Function to add spaces between capital letters
local function formatModifierName(name)
    -- Special case for Vanilla Immortality
    if name == "VanillaImmortality" then
        return "Vanilla Immortal"
    end
    
    -- Normal formatting for other names
    local formatted = name:gsub("([^A-Z])([A-Z])", "%1 %2")
                         :gsub("([A-Z])([A-Z][^A-Z])", "%1 %2")
    return formatted
end

-- Function to detect item type
local function detectItemType()
    local itemDetail = vaultReader.getItemDetail(1)
    if not itemDetail then return nil end
    
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
    
    -- If it has affixes but isn't a jewel, it's gear
    local prefixCount = safeCall(function() return vaultReader.getPrefixCount() end, 0)
    local suffixCount = safeCall(function() return vaultReader.getSuffixCount() end, 0)
    if prefixCount > 0 or suffixCount > 0 then
        return "gear"
    end
    
    return nil
end

-- Updated rarity weights to be more balanced
local RARITY_WEIGHTS = {
    scrappy = 0.85,  -- Less penalty for low rarity
    common = 1.0,    -- Baseline
    rare = 1.15,     -- Slight boost
    epic = 1.3,      -- Moderate boost
    omega = 1.5      -- Significant boost but not overwhelming
}

-- Weights for different modifier types in gear
local GEAR_TYPE_WEIGHTS = {
    legendary = 0.45,  -- 45% of total score
    implicit = 0.25,   -- 25% of total score
    prefix = 0.15,     -- 15% of total score
    suffix = 0.15      -- 15% of total score
}

-- Weights for jewel evaluation
local JEWEL_WEIGHTS = {
    legendary = 0.35,  -- 35% of total score
    rolls = 0.65       -- 65% of total score - rolls are much more important for jewels
}

-- Function to get suffix details for jewel buttons
local function getJewelSuffixDetails()
    local suffixes = {}
    local count = safeCall(function() return vaultReader.getSuffixCount() end, 0)
    
    for i = 0, count-1 do
        local suffix = safeCall(function() return vaultReader.getSuffix(i) end)
        if suffix and suffix ~= "empty" and suffix ~= "null" then
            local name = safeCall(function() return vaultReader.getName(suffix) end, "Unknown")
            local type = safeCall(function() return vaultReader.getType(suffix) end, "normal")
            table.insert(suffixes, {
                name = formatModifierName(name), -- Format the name with spaces
                type = type,
                index = i,
                view = "suffix_" .. i
            })
        end
    end
    return suffixes
end

-- Modified getContextButtons to handle individual jewel suffixes
local function getContextButtons()
    if not currentItemType and not viewingHistoricalItem then
        -- No buttons when showing history list
        return {}
    end
    
    local buttons = {{label = "Overview", view = "main"}}
    
    if currentItemType == "gear" or (viewingHistoricalItem and viewingHistoricalItem.type == "gear") then
        table.insert(buttons, {label = "Prefixes", view = "prefixes"})
        table.insert(buttons, {label = "Suffixes", view = "suffixes"})
        table.insert(buttons, {label = "Implicits", view = "implicits"})
    elseif currentItemType == "jewel" or (viewingHistoricalItem and viewingHistoricalItem.type == "jewel") then
        local suffixes
        if viewingHistoricalItem then
            suffixes = viewingHistoricalItem.suffixes
        else
            suffixes = getJewelSuffixDetails()
        end
        for _, suffix in ipairs(suffixes or {}) do
            table.insert(buttons, {
                label = suffix.name,
                view = "suffix_" .. (suffix.index or 0),
                suffixIndex = suffix.index,
                type = suffix.type
            })
        end
    end
    
    table.insert(buttons, {label = "Details", view = "details"})
    if viewingHistoricalItem then
        table.insert(buttons, {label = "Back to History", view = "history"})
    end
    
    return buttons
end

-- Draw vertical navigation buttons with dynamic sizing
local function drawNavButtons()
    local w, h = monitor.getSize()
    local ui = getScaledUI()
    local buttons = getContextButtons()
    
    -- Draw button area background first
    for y = ui.headerHeight + 1, h-1 do
        monitor.setCursorPos(1, y)
        monitor.setBackgroundColor(theme.buttonArea)
        monitor.write(string.rep(" ", ui.buttonWidth + 2))
    end
    
    for i, btn in ipairs(buttons) do
        local y = ui.headerHeight + 1 + (i-1) * (ui.buttonSpacing + 1)
        monitor.setCursorPos(1, y)
        
        -- Determine button background color based on state
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
        
        -- Draw button with a border effect
        local padding = math.floor((ui.buttonWidth - #btn.label) / 2)
        monitor.write(" " .. string.rep(" ", padding-1) .. btn.label .. string.rep(" ", ui.buttonWidth - #btn.label - padding) .. " ")
        
        btn.x1 = 1
        btn.x2 = ui.buttonWidth
        btn.y = y
    end
    
    -- Draw vertical separator line
    local separatorX = ui.buttonWidth + 2
    for y = ui.headerHeight + 1, h-1 do
        monitor.setCursorPos(separatorX, y)
        monitor.setTextColor(theme.separator)
        monitor.write("|")
    end
    
    return buttons, ui.contentStartX
end

-- Function to draw content area background (simplified)
local function drawContentArea(startX, startY)
    local w, h = monitor.getSize()
    monitor.setBackgroundColor(theme.contentArea)
    for y = startY, h-1 do
        monitor.setCursorPos(startX, y)
        monitor.write(string.rep(" ", w - startX))
    end
end

-- Function to draw stats in a formatted table with dynamic width
local function drawStatsTable(stats, startX, startY)
    local w, h = monitor.getSize()
    local y = startY
    local maxDisplayLines = h - startY - 1
    
    for i = scrollOffset + 1, math.min(#stats, scrollOffset + maxDisplayLines) do
        local stat = stats[i]
        if y >= h-1 then break end
        
        -- Draw stat name (no background)
        monitor.setCursorPos(startX, y)
        monitor.setTextColor(theme.highlight)
        monitor.setBackgroundColor(stat.highlighted and theme.buttonSelected or theme.contentArea)
        local name = stat.name .. ":"
        monitor.write(name)
        
        -- Draw stat value (right-aligned)
        local value = formatValue(stat.value)
        local valueX = w - #value - 2
        monitor.setCursorPos(valueX, y)
        
        -- Color coding for special values
        if stat.rarity then
            monitor.setTextColor(stat.rarity == "legendary" and theme.legendary or
                               stat.rarity == "rare" and theme.rare or theme.normal)
        else
            monitor.setTextColor(theme.text)
        end
        
        monitor.write(value)
        y = y + 1
    end
    
    -- Draw scroll indicators if needed
    if #stats > maxDisplayLines then
        monitor.setCursorPos(w-1, startY)
        monitor.setTextColor(theme.scrollIndicator)
        monitor.setBackgroundColor(theme.contentArea)
        monitor.write("▲")
        monitor.setCursorPos(w-1, h-2)
        monitor.write("▼")
    end
end

-- Function to get formatted affix stats 
local function getAffixStats(getAffixFunc, getCountFunc)
  local stats = {}
  local count = safeCall(getCountFunc, 0)
  for i = 0, count-1 do
    local affix = safeCall(function() return getAffixFunc(i) end)
    if affix and affix ~= "empty" and affix ~= "null" then
      local name = safeCall(function() return vaultReader.getName(affix) end, "Unknown")
      local value = safeCall(function() return vaultReader.getModifierValue(affix) end)
      local rarity = safeCall(function() return vaultReader.getType(affix) end, "normal")
      local minRoll = safeCall(function() return vaultReader.getMinimumRoll(affix) end)
      local maxRoll = safeCall(function() return vaultReader.getMaximumRoll(affix) end)
      
      -- Format display value based on available data
      local displayValue = tostring(value)
      if minRoll and maxRoll and minRoll ~= maxRoll then
        displayValue = string.format("%s (%s-%s)", displayValue, formatValue(minRoll), formatValue(maxRoll))
      end
      
      table.insert(stats, {
        name = formatModifierName(name), -- Format the name with spaces
        value = displayValue,
        rarity = rarity,
        numericalValue = value -- Store raw value for sorting
      })
    end
  end
  
  -- Sort by rarity (legendary first) then by value
  table.sort(stats, function(a, b)
    if a.rarity == b.rarity then
      return (a.numericalValue or 0) > (b.numericalValue or 0)
    end
    return a.rarity == "legendary" or (a.rarity == "crafted" and b.rarity == "regular")
  end)
  
  return stats
end

-- Function to calculate ranking for a single modifier
local function calculateModifierRanking(value, minRoll, maxRoll, modType)
    if not value or not minRoll or not maxRoll or minRoll == maxRoll then
        return nil
    end
    
    -- Calculate base percentage within range
    local range = maxRoll - minRoll
    local position = value - minRoll
    local baseRanking = (position / range) * 100
    
    -- Legendary modifiers get special treatment
    if modType == "legendary" then
        -- Legendary mods get minimum 90%, but still scale up to 100%
        return math.max(90, 90 + (baseRanking * 0.1))
    end
    
    return baseRanking
end

-- Function to calculate gear ranking with new weighting system
local function calculateGearRanking()
    local scores = {
        legendary = 0,
        implicit = 0,
        prefix = 0,
        suffix = 0
    }
    local counts = {
        legendary = 0,
        implicit = 0,
        prefix = 0,
        suffix = 0
    }
    
    -- Helper function to process modifiers
    local function processModifiers(getFunc, getCountFunc, modType)
        local count = safeCall(getCountFunc, 0)
        for i = 0, count-1 do
            local mod = safeCall(function() return getFunc(i) end)
            if mod and mod ~= "empty" and mod ~= "null" then
                local value = safeCall(function() return vaultReader.getModifierValue(mod) end)
                local minRoll = safeCall(function() return vaultReader.getMinimumRoll(mod) end)
                local maxRoll = safeCall(function() return vaultReader.getMaximumRoll(mod) end)
                local type = safeCall(function() return vaultReader.getType(mod) end)
                
                local ranking = calculateModifierRanking(value, minRoll, maxRoll, type)
                if ranking then
                    if type == "legendary" then
                        scores.legendary = scores.legendary + ranking
                        counts.legendary = counts.legendary + 1
                    else
                        scores[modType] = scores[modType] + ranking
                        counts[modType] = counts[modType] + 1
                    end
                end
            end
        end
    end
    
    -- Process all modifier types
    processModifiers(vaultReader.getImplicit, function() return vaultReader.getImplicitCount() end, "implicit")
    processModifiers(vaultReader.getPrefix, function() return vaultReader.getPrefixCount() end, "prefix")
    processModifiers(vaultReader.getSuffix, function() return vaultReader.getSuffixCount() end, "suffix")
    
    -- Calculate weighted average for each type
    local finalScore = 0
    for type, weight in pairs(GEAR_TYPE_WEIGHTS) do
        if counts[type] > 0 then
            finalScore = finalScore + ((scores[type] / counts[type]) * weight)
        end
    end
    
    -- Apply rarity modifier
    local itemRarity = string.lower(safeCall(function() return vaultReader.getRarity() end, "common"))
    local rarityWeight = RARITY_WEIGHTS[itemRarity] or 1.0
    
    -- Special case: if item has legendary mods, boost the final score more significantly
    if counts.legendary > 0 then
        finalScore = finalScore * 1.2  -- 20% boost for having any legendary mod
    end
    
    return math.min(100, math.floor(finalScore * rarityWeight))
end

-- Function to calculate jewel ranking with new weighting system
local function calculateJewelRanking()
    local legendaryScore = 0
    local rollScore = 0
    local legendaryCount = 0
    local totalMods = 0
    
    local count = safeCall(function() return vaultReader.getSuffixCount() end, 0)
    for i = 0, count-1 do
        local suffix = safeCall(function() return vaultReader.getSuffix(i) end)
        if suffix and suffix ~= "empty" and suffix ~= "null" then
            local value = safeCall(function() return vaultReader.getModifierValue(suffix) end)
            local minRoll = safeCall(function() return vaultReader.getMinimumRoll(suffix) end)
            local maxRoll = safeCall(function() return vaultReader.getMaximumRoll(suffix) end)
            local type = safeCall(function() return vaultReader.getType(suffix) end)
            
            local ranking = calculateModifierRanking(value, minRoll, maxRoll, type)
            if ranking then
                if type == "legendary" then
                    legendaryScore = legendaryScore + ranking
                    legendaryCount = legendaryCount + 1
                end
                rollScore = rollScore + ranking
                totalMods = totalMods + 1
            end
        end
    end
    
    -- Calculate weighted score
    local finalScore = 0
    if legendaryCount > 0 then
        finalScore = finalScore + ((legendaryScore / legendaryCount) * JEWEL_WEIGHTS.legendary)
    end
    if totalMods > 0 then
        finalScore = finalScore + ((rollScore / totalMods) * JEWEL_WEIGHTS.rolls)
    end
    
    -- Apply rarity modifier (only positive boosts for jewels)
    local itemRarity = string.lower(safeCall(function() return vaultReader.getRarity() end, "common"))
    local rarityMod = RARITY_WEIGHTS[itemRarity] or 1.0
    if rarityMod < 1.0 then rarityMod = 1.0 end  -- No penalties for low rarity jewels
    
    -- Special boost for legendary mods on jewels
    if legendaryCount > 0 then
        finalScore = finalScore * 1.25  -- 25% boost for having any legendary mod on a jewel
    end
    
    return math.min(100, math.floor(finalScore * rarityMod))
end

-- Update the main ranking calculation function
local function calculateOverallRanking()
    if currentItemType == "gear" then
        return calculateGearRanking()
    elseif currentItemType == "jewel" then
        return calculateJewelRanking()
    end
    return nil
end

-- Update the calculateAffixesRanking function to use the new system
local function calculateAffixesRanking(getAffixFunc, getCountFunc)
    local totalScore = 0
    local validCount = 0
    local hasLegendary = false
    
    local count = safeCall(getCountFunc, 0)
    for i = 0, count-1 do
        local affix = safeCall(function() return getAffixFunc(i) end)
        if affix and affix ~= "empty" and affix ~= "null" then
            local value = safeCall(function() return vaultReader.getModifierValue(affix) end)
            local minRoll = safeCall(function() return vaultReader.getMinimumRoll(affix) end)
            local maxRoll = safeCall(function() return vaultReader.getMaximumRoll(affix) end)
            local type = safeCall(function() return vaultReader.getType(affix) end)
            
            if type == "legendary" then
                hasLegendary = true
            end
            
            local ranking = calculateModifierRanking(value, minRoll, maxRoll, type)
            if ranking then
                totalScore = totalScore + ranking
                validCount = validCount + 1
            end
        end
    end
    
    if validCount == 0 then return nil end
    
    local score = totalScore / validCount
    
    -- Apply legendary bonus if present
    if hasLegendary then
        score = score * 1.2
    end
    
    return math.min(100, math.floor(score))
end

-- Function to display ranking header (adjusted position)
local function displayRanking(text, ranking, startX)
    if not ranking then return end
    
    local w = monitor.getSize()
    local rankText = string.format("%s Rank: %d/100", text, ranking)
    
    -- Position text one line higher
    monitor.setCursorPos(startX, 6)
    monitor.setTextColor(theme.highlight)
    monitor.setBackgroundColor(theme.contentArea)
    monitor.write(rankText)
    
    -- Bar below text
    local barLength = w - startX - 4
    local filledLength = math.floor((ranking / 100) * barLength)
    
    monitor.setCursorPos(startX, 7)
    monitor.setBackgroundColor(theme.contentArea)
    monitor.write("[")
    
    -- Determine color based on ranking
    local barColor
    if ranking >= 75 then
        barColor = colors.lime
    elseif ranking >= 50 then
        barColor = colors.yellow
    elseif ranking >= 25 then
        barColor = colors.orange
    else
        barColor = colors.red
    end
    
    monitor.setBackgroundColor(barColor)
    monitor.write(string.rep(" ", filledLength))
    monitor.setBackgroundColor(theme.buttonArea)
    monitor.write(string.rep(" ", barLength - filledLength))
    monitor.setBackgroundColor(theme.contentArea)
    monitor.write("]")
end

-- Function to draw the UI layout with dynamic sizing
local function drawUI()
    local w, h = monitor.getSize()
    local ui = getScaledUI()
    monitor.setBackgroundColor(theme.background)
    monitor.clear()
    
    -- Detect item type
    currentItemType = detectItemType()
    
    -- Draw full-width header background
    for i = 1, 2 do
        monitor.setCursorPos(1, i)
        monitor.setBackgroundColor(theme.header)
        monitor.write(string.rep(" ", w))
    end
    
    -- Header with dynamic width
    local headerText = "Vault Item Browser"
    local headerX = math.floor((w - #headerText) / 2) + 1
    monitor.setCursorPos(headerX, 1)
    monitor.setBackgroundColor(theme.header)
    monitor.setTextColor(theme.headerText)
    monitor.write(headerText)
    
    -- Item name/type under header (moved down one line)
    local itemDetail = vaultReader.getItemDetail(1)
    if itemDetail then
        local name = itemDetail.displayName or "Unknown Item"
        if #name > w - 4 then
            name = name:sub(1, w - 7) .. "..."
        end
        
        -- Draw item name background (moved down)
        monitor.setCursorPos(1, 4)
        monitor.setBackgroundColor(theme.contentArea)
        monitor.write(string.rep(" ", w))
        
        -- Center and write the item name
        local nameX = math.floor((w - #name) / 2) + 1
        monitor.setCursorPos(nameX, 4)
        monitor.setBackgroundColor(theme.contentArea)
        monitor.setTextColor(theme.highlight)
        monitor.write(name)
    end
    
    -- Draw content background
    local contentStart = 5  -- Adjusted to account for moved item name
    for y = contentStart, h do
        monitor.setCursorPos(1, y)
        monitor.setBackgroundColor(theme.background)
        monitor.write(string.rep(" ", w))
    end
end

-- Function to display section header with proper separators (simplified)
local function displaySectionHeader(text, startX)
    local w = monitor.getSize()
    
    -- Draw content area background first
    drawContentArea(startX, 6)
    
    -- Draw header text
    monitor.setCursorPos(startX, 6)
    monitor.setTextColor(theme.headerText)
    monitor.setBackgroundColor(theme.contentArea)
    monitor.write(text)
    
    -- Draw the divider
    monitor.setCursorPos(startX, 8)
    monitor.setTextColor(theme.separator)
    monitor.write(string.rep(theme.divider, w - startX))
end

-- Update displayMainView to use the new overall ranking system
local function displayMainView(startX, historicalItem)
    displaySectionHeader("Item Overview", startX)
    local stats = {}
    local item = historicalItem or {
        itemLevel = safeCall(function() return vaultReader.getItemLevel() end, "N/A"),
        rarity = safeCall(function() return vaultReader.getRarity() end, "N/A"),
        type = currentItemType,
        ranking = calculateOverallRanking()
    }
    
    if item.ranking then
        displayRanking("Overall", item.ranking, startX)
    end
    
    table.insert(stats, {name = "Item Level", value = item.itemLevel})
    table.insert(stats, {name = "Rarity", value = item.rarity})
    
    if item.type == "jewel" then
        table.insert(stats, {name = "Jewel Size", value = "10"})
        table.insert(stats, {name = "Suffix Count", value = #(item.suffixes or {})})
    else
        -- Gear stats
        table.insert(stats, {name = "Repair Slots", value = item.repairSlots})
        table.insert(stats, {name = "Prefix Count", value = item.prefixCount or 0})
        table.insert(stats, {name = "Suffix Count", value = item.suffixCount or 0})
        table.insert(stats, {name = "Implicit Count", value = item.implicitCount or 0})
    end
    
    drawStatsTable(stats, startX, 9)
end

-- Modify the affix display views to include rankings
local function displayAffixView(title, getAffixFunc, getCountFunc, startX)
    displaySectionHeader(title, startX)
    
    -- Calculate and display ranking
    local ranking = calculateAffixesRanking(getAffixFunc, getCountFunc)
    if ranking then
        displayRanking(title, ranking, startX)
    end
    
    local stats = getAffixStats(getAffixFunc, getCountFunc)
    drawStatsTable(stats, startX, 9)
end

-- New function to display individual suffix view
local function displaySuffixView(suffixIndex, startX)
    local suffix = safeCall(function() return vaultReader.getSuffix(suffixIndex) end)
    if not suffix or suffix == "empty" or suffix == "null" then return end
    
    local name = safeCall(function() return vaultReader.getName(suffix) end, "Unknown")
    displaySectionHeader(name, startX)
    
    -- Calculate and display ranking for this specific suffix
    local value = safeCall(function() return vaultReader.getModifierValue(suffix) end)
    local minRoll = safeCall(function() return vaultReader.getMinimumRoll(suffix) end)
    local maxRoll = safeCall(function() return vaultReader.getMaximumRoll(suffix) end)
    local modType = safeCall(function() return vaultReader.getType(suffix) end)
    
    local ranking = calculateModifierRanking(value, minRoll, maxRoll, modType)
    if ranking then
        displayRanking(name, ranking, startX)
    end
    
    -- Display suffix details
    local stats = {
        {name = "Current Value", value = value},
        {name = "Minimum Roll", value = minRoll},
        {name = "Maximum Roll", value = maxRoll},
        {name = "Modifier Type", value = modType}
    }
    
    drawStatsTable(stats, startX, 10)  -- Adjusted for new ranking display
end

-- Add sorting functionality
local function sortHistoricalItems()
    local function compareItems(a, b)
        local aValue = a[historySortField]
        local bValue = b[historySortField]
        
        -- Handle numeric fields
        if type(aValue) == "number" and type(bValue) == "number" then
            return historySortDesc and aValue > bValue or aValue < bValue
        end
        
        -- Handle string fields
        aValue = tostring(aValue)
        bValue = tostring(bValue)
        return historySortDesc and aValue > bValue or aValue < bValue
    end
    
    table.sort(historicalItems, compareItems)
end

-- Update the logging functions to fix saving issues
local function logItemData()
    local itemDetail = vaultReader.getItemDetail(1)
    if not itemDetail then 
        debugLog("No item detail found")
        return false 
    end
    
    -- Only proceed if we can identify the item type
    local itemType = detectItemType()
    if not itemType then 
        debugLog("Could not detect item type")
        return false 
    end

    debugLog("Processing item: " .. (itemDetail.displayName or "Unknown"))

    -- Get item data
    local data = {
        timestamp = os.epoch("utc"),
        name = itemDetail.displayName or "Unknown Item",
        itemLevel = safeCall(function() return vaultReader.getItemLevel() end, "N/A"),
        rarity = safeCall(function() return vaultReader.getRarity() end, "N/A"),
        type = itemType,
        id = tostring(os.epoch("utc")),
        ranking = calculateOverallRanking()
    }

    debugLog("Created base item data")

    -- Add type-specific data
    if itemType == "gear" then
        -- Get all prefix data
        local prefixes = {}
        local prefixCount = safeCall(function() return vaultReader.getPrefixCount() end, 0)
        for i = 0, prefixCount - 1 do
            local prefix = safeCall(function() return vaultReader.getPrefix(i) end)
            if prefix and prefix ~= "empty" and prefix ~= "null" then
                local name = safeCall(function() return vaultReader.getName(prefix) end, "Unknown")
                local value = safeCall(function() return vaultReader.getModifierValue(prefix) end)
                local type = safeCall(function() return vaultReader.getType(prefix) end, "normal")
                table.insert(prefixes, {name = name, value = value, type = type})
            end
        end
        data.prefixes = prefixes
        data.prefixCount = #prefixes

        -- Get all suffix data
        local suffixes = {}
        local suffixCount = safeCall(function() return vaultReader.getSuffixCount() end, 0)
        for i = 0, suffixCount - 1 do
            local suffix = safeCall(function() return vaultReader.getSuffix(i) end)
            if suffix and suffix ~= "empty" and suffix ~= "null" then
                local name = safeCall(function() return vaultReader.getName(suffix) end, "Unknown")
                local value = safeCall(function() return vaultReader.getModifierValue(suffix) end)
                local type = safeCall(function() return vaultReader.getType(suffix) end, "normal")
                table.insert(suffixes, {name = name, value = value, type = type})
            end
        end
        data.suffixes = suffixes
        data.suffixCount = #suffixes

        -- Get all implicit data
        local implicits = {}
        local implicitCount = safeCall(function() return vaultReader.getImplicitCount() end, 0)
        for i = 0, implicitCount - 1 do
            local implicit = safeCall(function() return vaultReader.getImplicit(i) end)
            if implicit and implicit ~= "empty" and implicit ~= "null" then
                local name = safeCall(function() return vaultReader.getName(implicit) end, "Unknown")
                local value = safeCall(function() return vaultReader.getModifierValue(implicit) end)
                local type = safeCall(function() return vaultReader.getType(implicit) end, "normal")
                table.insert(implicits, {name = name, value = value, type = type})
            end
        end
        data.implicits = implicits
        data.implicitCount = #implicits
        
        data.repairSlots = safeCall(function() return vaultReader.getRepairSlots() end, "N/A")
    elseif itemType == "jewel" then
        -- Get all suffix data for jewel
        local suffixes = {}
        local suffixCount = safeCall(function() return vaultReader.getSuffixCount() end, 0)
        for i = 0, suffixCount - 1 do
            local suffix = safeCall(function() return vaultReader.getSuffix(i) end)
            if suffix and suffix ~= "empty" and suffix ~= "null" then
                local name = safeCall(function() return vaultReader.getName(suffix) end, "Unknown")
                local value = safeCall(function() return vaultReader.getModifierValue(suffix) end)
                local type = safeCall(function() return vaultReader.getType(suffix) end, "normal")
                table.insert(suffixes, {name = name, value = value, type = type})
            end
        end
        data.suffixes = suffixes
        data.suffixCount = #suffixes
    end

    debugLog("Collected all item data, attempting to save")

    -- Save to log file
    local success = false
    local file = fs.open(logFilePath, "a")
    if file then
        file.writeLine(textutils.serialize(data))
        file.close()
        success = true
        debugLog("Successfully saved to log file")
    else
        debugLog("Failed to open log file for writing")
    end

    -- Only update in-memory list if save was successful
    if success then
        table.insert(historicalItems, data)
        sortHistoricalItems()
        debugLog("Updated in-memory list, new size: " .. #historicalItems)
    end
    
    return success
end

-- Update displayHistoryView to include sorting and better formatting
local function displayHistoryView(startX)
    displaySectionHeader("Item History", startX)
    
    -- Draw content area background first
    drawContentArea(startX, 6)
    
    local w, h = monitor.getSize()
    if #historicalItems == 0 then
        monitor.setCursorPos(startX, 9)
        monitor.setTextColor(theme.text)
        monitor.write("No items in history")
        debugLog("History is empty")
        return
    end
    
    -- Display total count
    monitor.setCursorPos(startX, 9)
    monitor.setTextColor(theme.text)
    monitor.write(string.format("Total items: %d", #historicalItems))
    
    -- Display items starting from line 10
    local displayY = 10
    for i = 1, math.min(#historicalItems, h - displayY) do
        local item = historicalItems[i]
        monitor.setCursorPos(startX, displayY + i - 1)
        monitor.setTextColor(theme.text)
        
        -- Format display string
        local type = string.upper(string.sub(item.type or "?", 1, 1))
        local name = item.name or "Unknown"
        if #name > 30 then name = name:sub(1, 27) .. "..." end
        local ranking = item.ranking or "N/A"
        local rarity = item.rarity or "normal"
        
        -- Format the line with fixed widths
        local line = string.format("[%s] %-30s (%3s) %s", type, name, ranking, rarity)
        monitor.write(line)
        
        debugLog(string.format("Displayed item %d: %s", i, line))
    end
end

-- Main loop with view handling, dynamic resizing, and live updates
while true do
    drawUI()
    local buttons, contentStartX = drawNavButtons()
    
    -- Always try to load historical items at the start of each loop
    historicalItems = loadHistoricalItems()
    
    -- Display current view
    if currentView == "history" or (not currentItemType and not viewingHistoricalItem) then
        displayHistoryView(contentStartX)
    elseif viewingHistoricalItem then
        -- Display historical item views
        if currentView == "main" then
            displayMainView(contentStartX, viewingHistoricalItem)
        elseif currentView == "prefixes" and viewingHistoricalItem.type == "gear" then
            displayHistoricalAffixView("Prefix Modifiers", viewingHistoricalItem.prefixes, contentStartX)
        elseif currentView == "suffixes" then
            displayHistoricalAffixView("Suffix Modifiers", viewingHistoricalItem.suffixes, contentStartX)
        elseif currentView == "implicits" and viewingHistoricalItem.type == "gear" then
            displayHistoricalAffixView("Implicit Modifiers", viewingHistoricalItem.implicits, contentStartX)
        elseif currentView == "details" then
            displayHistoricalDetailsView(viewingHistoricalItem, contentStartX)
        end
    else
        -- Normal item display logic
        if currentView == "main" then
            displayMainView(contentStartX)
        elseif currentView == "prefixes" and currentItemType == "gear" then
            displayAffixView("Prefix Modifiers", vaultReader.getPrefix, function() return vaultReader.getPrefixCount() end, contentStartX)
        elseif currentView == "suffixes" then
            displayAffixView("Suffix Modifiers", vaultReader.getSuffix, function() return vaultReader.getSuffixCount() end, contentStartX)
        elseif currentView == "implicits" and currentItemType == "gear" then
            displayAffixView("Implicit Modifiers", vaultReader.getImplicit, function() return vaultReader.getImplicitCount() end, contentStartX)
        elseif string.match(currentView, "^suffix_%d+$") and currentItemType == "jewel" then
            local suffixIndex = tonumber(string.match(currentView, "%d+"))
            displaySuffixView(suffixIndex, contentStartX)
        elseif currentView == "details" then
            displayDetailsView(contentStartX)
        end
    end
    
    -- Handle input events
    local timer = os.startTimer(0.5)
    local event, param1, x, y = os.pullEvent()
    
    if event == "monitor_touch" then
        hoveredButton = nil
        
        -- Handle history list clicks
        if currentView == "history" and y >= 10 then
            local clickedIndex = y - 10 + scrollOffset
            if historicalItems[clickedIndex] then
                viewingHistoricalItem = historicalItems[clickedIndex]
                currentView = "main"
                scrollOffset = 0
            end
        end
        
        -- Handle navigation buttons
        for _, btn in ipairs(buttons) do
            if x >= btn.x1 and x <= btn.x2 and y == btn.y then
                currentView = btn.view
                scrollOffset = 0
                if btn.view == "history" then
                    viewingHistoricalItem = nil
                end
                break
            end
        end
        
        -- Handle scroll indicators
        local w, h = monitor.getSize()
        if x == w-1 then
            if y == 7 and scrollOffset > 0 then
                scrollOffset = scrollOffset - 1
            elseif y == h-2 then
                scrollOffset = scrollOffset + 1
            end
        end
    elseif event == "timer" and param1 == timer then
        local newType = detectItemType()
        if newType ~= currentItemType then
            if newType then
                local success = logItemData()
                debugLog("Item logged: " .. tostring(success))
            end
            currentItemType = newType
            if not newType then
                currentView = "history"
            else
                currentView = "main"
            end
            viewingHistoricalItem = nil
            scrollOffset = 0
        end
    end
end

-- Add these helper functions for displaying historical items
local function displayHistoricalDetailsView(item, startX)
    displaySectionHeader("Item Details", startX)
    local stats = {}
    for k, v in pairs(item) do
        if type(v) ~= "table" and k ~= "id" and k ~= "timestamp" then
            table.insert(stats, {name = k, value = v})
        end
    end
    table.sort(stats, function(a, b) return a.name < b.name end)
    drawStatsTable(stats, startX, 9)
end

local function displayHistoricalAffixView(title, affixes, startX)
    displaySectionHeader(title, startX)
    local stats = {}
    for _, affix in ipairs(affixes or {}) do
        table.insert(stats, {
            name = formatModifierName(affix.name),
            value = affix.value,
            rarity = affix.type
        })
    end
    drawStatsTable(stats, startX, 9)
end

local function displayHistoricalSuffixView(suffixIndex, item, startX)
    if not item.suffixes or not item.suffixes[suffixIndex + 1] then return end
    local suffix = item.suffixes[suffixIndex + 1]
    
    displaySectionHeader(formatModifierName(suffix.name), startX)
    local stats = {
        {name = "Current Value", value = suffix.value},
        {name = "Modifier Type", value = suffix.type}
    }
    drawStatsTable(stats, startX, 9)
end

-- Update displayHistoryView to be more compact
local function displayHistoryView(startX)
    displaySectionHeader("Item History", startX)
    
    local w, h = monitor.getSize()
    local stats = {}
    local maxDisplayItems = h - 11
    
    -- Sort options
    local sortOptions = {
        {field = "type", label = "Type"},
        {field = "name", label = "Name"},
        {field = "rarity", label = "Rarity"},
        {field = "ranking", label = "Rank"}
    }
    
    -- Display sort controls
    monitor.setCursorPos(startX, 7)
    monitor.setTextColor(theme.highlight)
    monitor.write("Sort by: ")
    local sortX = startX + 9
    
    for i, opt in ipairs(sortOptions) do
        local isSelected = historySortField == opt.field
        monitor.setTextColor(isSelected and theme.buttonSelected or theme.text)
        monitor.write(opt.label)
        opt.x1 = sortX
        opt.x2 = sortX + #opt.label - 1
        sortX = sortX + #opt.label + 2
        if i < #sortOptions then
            monitor.setTextColor(theme.separator)
            monitor.write(" | ")
            sortX = sortX + 3
        end
    end
    
    -- Draw items
    for i, item in ipairs(historicalItems) do
        local typeStr = item.type and string.upper(item.type:sub(1,1)) or "-"
        local rankStr = item.ranking and string.format("%3d", item.ranking) or "N/A"
        local displayStr = string.format("[%s] %-30s %5s %s", 
            typeStr,
            item.name:sub(1, 30),
            rankStr,
            item.rarity or "Unknown")
        
        table.insert(stats, {
            id = item.id,
            name = tostring(i),
            value = displayStr,
            rarity = string.lower(item.rarity or "normal")
        })
    end
    
    if #stats == 0 then
        monitor.setCursorPos(startX, 9)
        monitor.setTextColor(theme.text)
        monitor.write("No items in history")
    else
        drawStatsTable(stats, startX, 9)
    end
end

-- Load historical items at startup
historicalItems = loadHistoricalItems()

-- Add this function with the other display functions
local function displayDetailsView(startX)
    displaySectionHeader("Item Details", startX)
    local itemDetail = vaultReader.getItemDetail(1)
    local stats = {}
    
    if itemDetail then
        for k, v in pairs(itemDetail) do
            if type(v) ~= "table" then
                table.insert(stats, {name = k, value = v})
            end
        end
        table.sort(stats, function(a, b) return a.name < b.name end)
    end
    
    drawStatsTable(stats, startX, 9)
end
