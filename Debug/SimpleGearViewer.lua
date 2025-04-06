-- SimpleGearViewer.lua
-- A simple script to display vault reader item information
-- Based on functions from GearChecker.lua

local vaultReader = peripheral.wrap("left")
if not vaultReader then error("Vault reader not found on left side!") end
local monitor = peripheral.wrap("right")
if not monitor then error("Monitor not found on right side!") end

-- Set monitor scale
monitor.setTextScale(0.5)
monitor.setCursorPos(1,1)
monitor.clear()

-- Safe function call wrapper
local function safeCall(func, default)
  local ok, res = pcall(func)
  return ok and res or default
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

-- Format modifier names for readability
local function formatModifierName(name)
    if name == "VanillaImmortality" then
        return "Vanilla Immortal"
    end
    
    local formatted = name:gsub("([^A-Z])([A-Z])", "%1 %2")
                         :gsub("([A-Z])([A-Z][^A-Z])", "%1 %2")
    return formatted
end

-- Function to write text with color
local function writeText(text, textColor, bgColor)
    monitor.setTextColor(textColor or colors.white)
    monitor.setBackgroundColor(bgColor or colors.black)
    monitor.write(text)
end

-- Function to print a separator line
local function printSeparator(char)
    local w = monitor.getSize()
    writeText(string.rep(char or "-", w), colors.cyan)
    monitor.setCursorPos(1, select(2, monitor.getCursorPos()) + 1)
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

-- Function to get rarity color
local function getRarityColor(rarity)
    if not rarity then return colors.white end
    
    rarity = string.lower(rarity)
    if rarity == "legendary" then return colors.orange
    elseif rarity == "epic" or rarity == "omega" then return colors.magenta
    elseif rarity == "rare" then return colors.yellow
    elseif rarity == "common" then return colors.white
    elseif rarity == "scrappy" then return colors.lightGray
    else return colors.white end
end

-- Function to print item header info
local function printItemHeader()
    local itemDetail = vaultReader.getItemDetail(1)
    if not itemDetail then
        writeText("No item detected", colors.red)
        return false
    end
    
    local itemName = itemDetail.displayName or "Unknown Item"
    local itemType = detectItemType()
    local itemLevel = safeCall(function() return vaultReader.getItemLevel() end, "N/A")
    local itemRarity = safeCall(function() return vaultReader.getRarity() end, "Unknown")
    
    -- Print item name centered
    local w = monitor.getSize()
    local nameX = math.floor((w - #itemName) / 2)
    monitor.setCursorPos(nameX, 1)
    writeText(itemName, getRarityColor(itemRarity))
    
    -- Print item info line
    monitor.setCursorPos(1, 3)
    writeText(string.format("Type: %s | Level: %s | Rarity: %s", 
        itemType or "Unknown", 
        itemLevel,
        itemRarity), 
        colors.cyan)
    
    printSeparator("=")
    return true
end

-- Function to calculate roll quality percentage
local function calculateRollQuality(value, minRoll, maxRoll)
    if not value or not minRoll or not maxRoll or minRoll == maxRoll then
        return "N/A"
    end
    
    local range = maxRoll - minRoll
    local position = value - minRoll
    local quality = (position / range) * 100
    
    return string.format("%.1f%%", quality)
end

-- Function to print all affixes
local function printAffixes(title, getAffixFunc, getCountFunc)
    monitor.setCursorPos(1, select(2, monitor.getCursorPos()))
    writeText(title, colors.yellow)
    monitor.setCursorPos(1, select(2, monitor.getCursorPos()) + 1)
    
    local count = safeCall(getCountFunc, 0)
    if count == 0 then
        writeText("  None", colors.lightGray)
        monitor.setCursorPos(1, select(2, monitor.getCursorPos()) + 1)
        return
    end
    
    for i = 0, count-1 do
        local affix = safeCall(function() return getAffixFunc(i) end)
        if affix and affix ~= "empty" and affix ~= "null" then
            local name = safeCall(function() return vaultReader.getName(affix) end, "Unknown")
            local value = safeCall(function() return vaultReader.getModifierValue(affix) end)
            local minRoll = safeCall(function() return vaultReader.getMinimumRoll(affix) end)
            local maxRoll = safeCall(function() return vaultReader.getMaximumRoll(affix) end)
            local type = safeCall(function() return vaultReader.getType(affix) end, "normal")
            
            -- Format name and value
            name = formatModifierName(name)
            
            -- Add roll range if available
            local displayValue = formatValue(value)
            if minRoll and maxRoll and minRoll ~= maxRoll then
                displayValue = string.format("%s (%s-%s)", 
                    displayValue, 
                    formatValue(minRoll), 
                    formatValue(maxRoll))
            end
            
            -- Add roll quality if available
            local quality = calculateRollQuality(value, minRoll, maxRoll)
            if quality ~= "N/A" then
                displayValue = displayValue .. " - " .. quality
            end
            
            -- Format and print line
            local lineColor = colors.white
            if type == "legendary" then
                lineColor = colors.orange
            elseif type == "rare" then
                lineColor = colors.yellow
            end
            
            local line = string.format("  %s: %s", name, displayValue)
            writeText(line, lineColor)
            monitor.setCursorPos(1, select(2, monitor.getCursorPos()) + 1)
        end
    end
end

-- Function to print detailed item stats
local function printItemStats()
    local itemType = detectItemType()
    if not itemType then
        return
    end
    
    -- Print item general stats
    if itemType == "gear" then
        local repairSlots = safeCall(function() return vaultReader.getRepairSlots() end, "N/A")
        writeText(string.format("Repair Slots: %s", repairSlots), colors.green)
        monitor.setCursorPos(1, select(2, monitor.getCursorPos()) + 1)
    end

    -- Print all affixes
    printSeparator("-")

    -- Print prefixes if it's gear
    if itemType == "gear" then
        printAffixes("PREFIXES:", vaultReader.getPrefix, function() return vaultReader.getPrefixCount() end)
        printSeparator("-")
    end

    -- Print suffixes (both gear and jewels have these)
    printAffixes("SUFFIXES:", vaultReader.getSuffix, function() return vaultReader.getSuffixCount() end)
    printSeparator("-")

    -- Print implicits
    printAffixes("IMPLICITS:", vaultReader.getImplicit, function() return vaultReader.getImplicitCount() end)

    -- Print details of NBT data if available
    local itemDetail = vaultReader.getItemDetail(1)
    if itemDetail and itemDetail.nbt then
        printSeparator("=")
        writeText("Additional NBT Data:", colors.yellow)
        monitor.setCursorPos(1, select(2, monitor.getCursorPos()) + 1)
        
        for key, value in pairs(itemDetail.nbt) do
            if type(value) ~= "table" then
                writeText(string.format("  %s: %s", key, tostring(value)), colors.white)
                monitor.setCursorPos(1, select(2, monitor.getCursorPos()) + 1)
            end
        end
    end
end

-- Main display function
local function refreshDisplay()
    monitor.clear()
    monitor.setCursorPos(1,1)
    
    if printItemHeader() then
        printItemStats()
    end
end

-- Main loop
while true do
    refreshDisplay()
    sleep(1)
end