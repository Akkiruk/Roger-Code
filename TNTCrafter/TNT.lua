--[[
COMMON ERRORS AND SOLUTIONS:
1. "table expected, got string" - When using bridge.craftItem(), always use a table:
   CORRECT:   bridge.craftItem({id = "minecraft:tnt", amount = 5})
   INCORRECT: bridge.craftItem("minecraft:tnt", 5)

2. "goto is not supported" - ComputerCraft's Lua doesn't support goto statements.
   Use while loops with break/continue logic instead.

3. "attempt to call a nil value" - Always define variables before using them,
   especially when working with peripherals. Check that peripherals are found
   before trying to use them.

4. "expected table" errors with ME Bridge - Always check the Advanced Peripherals
   documentation for correct parameter formats. Most ME Bridge functions expect
   specific table structures.

5. "peripheral not found" - Double check the side/name when wrapping peripherals:
   - Use F3 to see which side is which (north/south/east/west/top/bottom)
   - Or use peripheral.find("type") to automatically find the right peripheral
   - Common sides are: "left", "right", "top", "bottom", "front", "back"

6. "item not found" - Make sure to use full item namespaces:
   - Most vanilla items need "minecraft:" prefix (e.g. "minecraft:diamond")
   - Modded items need their mod prefix (e.g. "thermal:machine_frame")
   - Use /data get entity @p SelectedItem to see the full item ID in-game
--]]

-- ME Bridge Network Test Script
print("Starting ME Bridge diagnostics...")

-- Initialize peripherals
local bridge = peripheral.find("meBridge")
local monitor = nil
local monitorSide = "right"
local lastMonitorTry = 0
local monitorRetryInterval = 5000 -- Try to reconnect monitor every 5 seconds

-- Initialize global variables
local items = {} -- Needed to store ME system items

-- Track crafting jobs to prevent duplicates
local activeCraftingJobs = {
  sand = false,
  gunpowder = false
}

-- Function to safely connect to monitor
local function connectMonitor()
  monitor = peripheral.wrap(monitorSide)
  if monitor then
    monitor.setTextScale(0.5)
    monitor.clear()
    return true
  end
  return false
end

if not bridge then
  print("Error: ME Bridge not found. Please check:")
  print("1. ME Bridge is placed adjacent to the computer")
  print("2. ME Bridge is powered")
  print("3. ComputerCraft and Advanced Peripherals are properly installed")
  return
end

-- Initial monitor connection attempt
connectMonitor()
if not monitor then
  print("Warning: Monitor not found on right side")
  print("Program will continue without display. Connect a monitor to enable display.")
end

-- Function to safely interact with monitor
local function safeMonitorOperation(operation)
  if monitor then
    local success, err = pcall(operation)
    if not success then
      print("Monitor error: " .. tostring(err))
      monitor = nil -- Reset monitor connection on error
      return false
    end
    return true
  end
  return false
end

-- Stats initialization improvements
local function initializeStats()
  return {
    lastGunpowder = 0,
    currentGunpowder = 0,
    lastSand = 0,
    currentSand = 0,
    lastTNT = 0,
    currentTNT = 0,
    -- Use dual window rate tracking for better accuracy
    rates = {
      gunpowder = { current = 0, lastUpdate = 0, lastAmount = 0, shortWindow = {}, longWindow = {} },
      sand = { current = 0, lastUpdate = 0, lastAmount = 0, shortWindow = {}, longWindow = {} },
      tnt = { current = 0, lastUpdate = 0, lastAmount = 0, shortWindow = {}, longWindow = {} }
    },
    tntCraftedTotal = 0,
    lastUpdate = os.epoch("local"),
    lastWindowStart = os.epoch("local"), -- Add missing variable
    -- Improved rate calculation configuration
    shortWindowDuration = 30, -- 30 second window for quick response
    longWindowDuration = 300, -- 5 minute window for stability
    rateWindow = 30, -- Rate calculation window in seconds
    lastCraftAmount = 0,
    isFirstRun = true,
    hasInitializedRates = false,
    initializationStartTime = 0,
    initializationDuration = 60
  }
end

-- Initialize stats object
local stats = initializeStats()

-- Function to save stats with improved error handling
local function saveStats()
  if not fs.exists("TNTCrafter") then
    fs.makeDir("TNTCrafter")
  end
  
  local statsToSave = {
    tntCraftedTotal = stats.tntCraftedTotal,
    gunpowderRate = stats.rates.gunpowder.current,
    sandRate = stats.rates.sand.current,
    tntRate = stats.rates.tnt.current,
    windowStats = stats.windowStats,
    lastUpdate = stats.lastUpdate,
    hasInitializedRates = stats.hasInitializedRates
  }
  
  local success, err = pcall(function()
    local file = fs.open("TNTCrafter/stats.txt", "w")
    if file then
      file.write(textutils.serialize(statsToSave))
      file.close()
    else
      error("Could not open stats file for writing")
    end
  end)
  
  if not success then
    print("Failed to save stats: " .. tostring(err))
  end
end

-- Function to load stats with improved validation
local function loadStats()
  if not fs.exists("TNTCrafter/stats.txt") then
    print("No previous stats file found")
    return
  end
  
  local success, err = pcall(function()
    local file = fs.open("TNTCrafter/stats.txt", "r")
    if file then
      local content = file.readAll()
      file.close()
      
      local loaded = textutils.unserialize(content)
      if loaded then
        -- Validate and load each stat individually
        if type(loaded.tntCraftedTotal) == "number" then
          stats.tntCraftedTotal = loaded.tntCraftedTotal
        end
        
        -- Load rates with validation
        for _, stat in ipairs({"gunpowderRate", "sandRate", "tntRate"}) do
          if type(loaded[stat]) == "number" and loaded[stat] >= 0 then
            local itemKey = stat:sub(1, -5)  -- Remove 'Rate' suffix
            stats.rates[itemKey].current = loaded[stat]
            -- Initialize lastAmount to prevent arithmetic on nil value errors
            stats.rates[itemKey].lastAmount = 0
          end
        end
        
        -- Load window stats if they exist
        if type(loaded.windowStats) == "table" then
          stats.windowStats = loaded.windowStats
        end
        
        -- Load initialization state
        stats.hasInitializedRates = loaded.hasInitializedRates or false
        
        print("Loaded previous stats - Total TNT crafted: " .. stats.tntCraftedTotal)
      end
    end
  end)
  
  if not success then
    print("Failed to load stats: " .. tostring(err))
  end
end

-- Load previous stats
loadStats()

-- Function to calculate rate with dual window system
local function updateRate(item, newAmount, craftImpact)
  local now = os.epoch("local")
  local rate = stats.rates[item]
  
  -- Initialize lastAmount and lastUpdate if they don't exist
  if not rate.lastUpdate then
    rate.lastUpdate = now
    rate.lastAmount = newAmount or 0
    return 0
  end
  
  -- Make sure lastAmount is initialized
  rate.lastAmount = rate.lastAmount or 0
  
  local timeElapsed = (now - rate.lastUpdate) / 1000 -- Convert to seconds
  if timeElapsed < 0.1 then return rate.current end -- Avoid ultra-short updates
  
  local change = newAmount - rate.lastAmount
  if craftImpact then
    change = change + craftImpact
  end
  
  -- Add to both windows
  table.insert(rate.shortWindow, {
    time = now,
    change = change,
    elapsed = timeElapsed
  })
  table.insert(rate.longWindow, {
    time = now,
    change = change,
    elapsed = timeElapsed
  })
  
  -- Prune old entries
  local function pruneWindow(window, duration)
    while #window > 0 and (now - window[1].time) > duration * 1000 do
      table.remove(window, 1)
    end
  end
  
  pruneWindow(rate.shortWindow, stats.shortWindowDuration)
  pruneWindow(rate.longWindow, stats.longWindowDuration)
  
  -- Calculate rates from both windows
  local function calculateWindowRate(window)
    local totalChange = 0
    local totalTime = 0
    for _, entry in ipairs(window) do
      totalChange = totalChange + entry.change
      totalTime = totalTime + entry.elapsed
    end
    return totalTime > 0 and (totalChange / totalTime) * 60 or 0 -- Convert to per minute
  end
  
  local shortRate = calculateWindowRate(rate.shortWindow)
  local longRate = calculateWindowRate(rate.longWindow)
  
  -- Use short window for quick changes, long window for stability
  rate.current = math.abs(shortRate) > math.abs(longRate) * 1.5 
    and shortRate -- Use short window if significantly different
    or longRate -- Otherwise use more stable long window
  
  rate.lastUpdate = now
  rate.lastAmount = newAmount
  
  return rate.current
end

-- Function to draw a loading bar
local function drawLoadingBar(x, y, width, progress, color)
  if not monitor then return end
  
  monitor.setCursorPos(x, y)
  monitor.setTextColor(color)
  local filled = math.floor(progress * width)
  monitor.write(string.rep("=", filled) .. string.rep("-", width - filled))
end

-- Function to create a box border (using simple ASCII)
local function drawBox(x, y, width, height)
  if not monitor then return end
  
  monitor.setTextColor(colors.lightGray)
  -- Top border
  monitor.setCursorPos(x, y)
  monitor.write("+" .. string.rep("-", width-2) .. "+")
  
  -- Sides
  for i = 1, height-2 do
    monitor.setCursorPos(x, y+i)
    monitor.write("|")
    monitor.setCursorPos(x+width-1, y+i)
    monitor.write("|")
  end
  
  -- Bottom border
  monitor.setCursorPos(x, y+height-1)
  monitor.write("+" .. string.rep("-", width-2) .. "+")
end

-- Function to calculate UI dimensions and set appropriate text scale
local function calculateDimensions()
  if not monitor then return 0, 0 end
  
  local success, width, height = pcall(function()
    return monitor.getSize()
  end)
  
  if not success then
    monitor = nil
    return 0, 0
  end
  
  -- Adjust text scale based on monitor size
  local scale = 0.5
  if width < 30 or height < 16 then
    scale = 1
  end
  
  safeMonitorOperation(function()
    monitor.setTextScale(scale)
    width, height = monitor.getSize()
  end)
  
  return width, height
end

-- Add animation frames for indicators
local craftingAnimation = {"|", "/", "-", "\\"}
local animationFrame = 1

-- Function to format large numbers with commas
local function formatNumber(num)
  local formatted = tostring(num)
  local k
  while true do  
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if (k==0) then break end
  end
  return formatted
end

-- Helper functions for display
local function drawSection(title, y, width, color)
    if not monitor then return y + 2 end
    
    monitor.setCursorPos(2, y)
    monitor.setTextColor(colors.lightGray)
    monitor.write(string.rep("=", width-4))
    
    -- Center the title
    local titleText = "[ " .. title .. " ]"
    monitor.setCursorPos(math.floor(width/2 - #titleText/2), y)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(color or colors.white)
    monitor.write(titleText)
    monitor.setBackgroundColor(colors.black)
    
    return y + 2  -- Return next line position
end

local function drawResourceStats(name, current, threshold, rate, y, width)
    if not monitor then return y + 4 end
    
    -- Storage info
    monitor.setCursorPos(3, y)
    monitor.setTextColor(colors.white)
    monitor.write("Storage: " .. formatNumber(current))
    
    -- Rate display
    monitor.setCursorPos(width - 20, y)
    if not stats.hasInitializedRates then
        monitor.setTextColor(colors.gray)
        monitor.write("Waiting...")
    elseif rate > 0 then
        monitor.setTextColor(colors.lime)
        monitor.write("+" .. formatNumber(rate) .. "/min")
    else
        monitor.setTextColor(colors.red)
        monitor.write(formatNumber(rate) .. "/min")
    end
    
    -- Threshold info
    monitor.setCursorPos(3, y + 1)
    monitor.setTextColor(colors.lightGray)
    monitor.write("TNT Craft Threshold: " .. formatNumber(threshold))
    
    -- Progress bar
    local barWidth = math.min(width - 20, 25)
    local progress = math.min(current / threshold, 1)
    monitor.setCursorPos(3, y + 2)
    monitor.setTextColor(colors.white)
    monitor.write("Progress: ")
    drawLoadingBar(13, y + 2, barWidth, progress, colors.lime)
    monitor.setCursorPos(14 + barWidth, y + 2)
    monitor.write(" " .. math.floor(progress * 100) .. "%")
    
    -- Remaining/excess
    monitor.setCursorPos(3, y + 3)
    if current < threshold then
        monitor.setTextColor(colors.orange)
        monitor.write("Needed: " .. formatNumber(threshold - current))
    else
        monitor.setTextColor(colors.lime)
        monitor.write("Excess: " .. formatNumber(current - threshold))
    end
    
    return y + 4  -- Return next line position
end

-- Update the display function to use these helpers
local function updateDisplay()
    -- Check if we need to try reconnecting monitor
    local currentTime = os.epoch("local")
    if not monitor and currentTime - lastMonitorTry >= monitorRetryInterval then
        if connectMonitor() then
            print("Monitor reconnected!")
        end
        lastMonitorTry = currentTime
    end
    
    if not monitor then return end -- Skip display update if no monitor
    
    safeMonitorOperation(function()
        monitor.clear()
        
        -- Get monitor dimensions
        local width, height = calculateDimensions()
        if width == 0 or height == 0 then return end -- Skip if dimensions invalid
        
        -- Minimum size check with graceful fallback
        if width < 20 or height < 12 then
            monitor.clear()
            monitor.setCursorPos(1, 1)
            monitor.setTextColor(colors.red)
            monitor.write("Monitor too small!")
            monitor.setCursorPos(1, 2)
            monitor.write("Need: 20x12")
            monitor.setCursorPos(1, 3)
            monitor.write("Has: " .. width .. "x" .. height)
            return
        end
        
        -- Calculate rates (items per minute)
        local timeElapsed = (os.epoch("local") - stats.lastUpdate) / 60000
        
        -- Handle initialization timing
        if stats.isFirstRun and stats.initializationStartTime == 0 then
            stats.initializationStartTime = os.epoch("local") / 1000  -- Convert to seconds
        end
        
        -- Skip rate calculation on first run or if time elapsed is too small
        if timeElapsed > 0 and not stats.isFirstRun then
            local gpDiff = stats.currentGunpowder - stats.lastGunpowder
            local sandDiff = stats.currentSand - stats.lastSand
            local tntDiff = stats.currentTNT - stats.lastTNT
            
            -- If we just started monitoring, initialize rates more gradually
            if not stats.hasInitializedRates then
                local initTimeElapsed = (os.epoch("local") / 1000) - stats.initializationStartTime
                if initTimeElapsed >= stats.initializationDuration then
                    stats.hasInitializedRates = true
                else
                    gpDiff = 0
                    sandDiff = 0
                    tntDiff = 0
                end
            end
            
            -- If resources decreased due to crafting, adjust the differences
            if stats.lastCraftAmount > 0 then
                if gpDiff < 0 then
                    gpDiff = gpDiff + (stats.lastCraftAmount * 5)  -- 5 gunpowder per TNT
                end
                if sandDiff < 0 then
                    sandDiff = sandDiff + (stats.lastCraftAmount * 4)  -- 4 sand per TNT
                end
            end
            
            -- Only update rates if we have meaningful changes
            if math.abs(gpDiff) > 0 then
                stats.rates.gunpowder.current = updateRate("gunpowder", stats.currentGunpowder)
            end
            if math.abs(sandDiff) > 0 then
                stats.rates.sand.current = updateRate("sand", stats.currentSand)
            end
            if math.abs(tntDiff) > 0 then
                stats.rates.tnt.current = updateRate("tnt", stats.currentTNT)
            end
        end

        -- Calculate section heights and positions
        local sectionHeight = math.min(6, math.floor(height * 0.3))  -- Reduced from 7 to 6
        local gpSectionEnd = sectionHeight + 2
        local sandSectionStart = gpSectionEnd + 1
        local sandSectionEnd = sandSectionStart + (sectionHeight - 1)  -- Reduced sand section height by 1
        local tntSectionStart = sandSectionEnd + 2  -- Added 1 more line of spacing before TNT section

        -- Draw main box
        drawBox(1, 1, width, height)
        
        -- Title
        local title = "[ TNT Factory Monitor ]"
        monitor.setCursorPos(math.floor((width - #title) / 2), 1)
        monitor.setTextColor(colors.yellow)
        monitor.write(title)
        
        -- Function to draw initialization progress bar
        local function drawInitProgress()
            if not stats.hasInitializedRates then
                local initTimeElapsed = (os.epoch("local") / 1000) - stats.initializationStartTime
                local progress = math.min(initTimeElapsed / stats.initializationDuration, 1)
                local timeLeft = math.max(0, math.ceil(stats.initializationDuration - initTimeElapsed))
                
                -- Draw progress bar just below title
                monitor.setCursorPos(2, 2)
                monitor.setTextColor(colors.yellow)
                monitor.write("Initializing [")
                drawLoadingBar(19, 2, 15, progress, colors.yellow)
                monitor.setCursorPos(35, 2)
                monitor.write("] " .. timeLeft .. "s")
            end
        end

        -- Draw initialization progress at the very top if still initializing
        drawInitProgress()
        
        -- Gunpowder Section Header (start at line 3 regardless of initialization state)
        monitor.setCursorPos(2, 3)
        monitor.setTextColor(colors.lightGray)
        monitor.write(string.rep("=", width-4))  -- Stronger separator
        monitor.setCursorPos(math.floor(width/2 - 5), 3)
        monitor.setBackgroundColor(colors.black)  -- Clear background for header
        monitor.setTextColor(colors.white)
        monitor.write("[ GUNPOWDER ]")
        
        -- Gunpowder stats
        monitor.setCursorPos(3, 5)  -- Moved down one line
        monitor.setTextColor(colors.white)
        monitor.write("Storage: " .. formatNumber(stats.currentGunpowder))
        
        -- Production rate displays
        monitor.setCursorPos(width - 20, 5)
        if not stats.hasInitializedRates then
            monitor.setTextColor(colors.gray)
            monitor.write("Waiting...")
        elseif stats.rates.gunpowder.current > 0 then
            monitor.setTextColor(colors.lime)
            monitor.write("+" .. formatNumber(stats.rates.gunpowder.current) .. "/min")
        else
            monitor.setTextColor(colors.red)
            monitor.write("0/min")
        end
        
        -- Crafting threshold info
        monitor.setCursorPos(3, 6)
        monitor.setTextColor(colors.lightGray)
        monitor.write("TNT Craft Threshold: 20,000")
        
        -- Progress bar with remaining amount and percentage
        local barWidth = math.min(width - 20, 25)
        local gpProgress = math.min(stats.currentGunpowder / 20000, 1)
        monitor.setCursorPos(3, 7)
        monitor.setTextColor(colors.white)
        monitor.write("Progress: ")
        drawLoadingBar(13, 7, barWidth, gpProgress, colors.lime)
        monitor.setCursorPos(14 + barWidth, 7)
        monitor.write(" " .. math.floor(gpProgress * 100) .. "%")
        
        -- Show remaining or excess
        monitor.setCursorPos(3, 8)
        if stats.currentGunpowder < 20000 then
            monitor.setTextColor(colors.orange)
            monitor.write("Needed: " .. formatNumber(20000 - stats.currentGunpowder))
        else
            monitor.setTextColor(colors.lime)
            monitor.write("Excess: " .. formatNumber(stats.currentGunpowder - 20000))
        end
        
        -- Sand Section
        monitor.setCursorPos(2, sandSectionStart)
        monitor.setTextColor(colors.lightGray)
        monitor.write(string.rep("=", width-4))
        monitor.setCursorPos(math.floor(width/2 - 3), sandSectionStart)
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.white)
        monitor.write("[ SAND ]")
        
        -- Sand stats
        monitor.setCursorPos(3, sandSectionStart + 1)  -- Moved up one line
        monitor.setTextColor(colors.white)
        monitor.write("Storage: " .. formatNumber(stats.currentSand))
        
        -- Production rate for sand
        monitor.setCursorPos(width - 20, sandSectionStart + 1)
        if not stats.hasInitializedRates then
            monitor.setTextColor(colors.gray)
            monitor.write("Waiting...")
        elseif stats.rates.sand.current > 0 then
            monitor.setTextColor(colors.lime)
            monitor.write("+" .. formatNumber(stats.rates.sand.current) .. "/min")
        else
            monitor.setTextColor(colors.red)
            monitor.write("0/min")
        end
        
        -- Crafting threshold info
        monitor.setCursorPos(3, sandSectionStart + 2)  -- Moved up one line
        monitor.setTextColor(colors.lightGray)
        monitor.write("TNT Craft Threshold: 16,000")
        
        -- Progress bar
        local barWidth = math.min(width - 20, 25)
        local sandProgress = math.min(stats.currentSand / 16000, 1)
        monitor.setCursorPos(3, sandSectionStart + 3)  -- Moved up one line
        monitor.setTextColor(colors.white)
        monitor.write("Progress: ")
        drawLoadingBar(13, sandSectionStart + 3, barWidth, sandProgress, colors.yellow)  -- Moved up one line
        monitor.setCursorPos(14 + barWidth, sandSectionStart + 3)  -- Moved up one line
        monitor.write(" " .. math.floor(sandProgress * 100) .. "%")
        
        -- Show remaining or excess sand
        monitor.setCursorPos(3, sandSectionStart + 4)  -- Moved up one line
        if stats.currentSand < 16000 then
            monitor.setTextColor(colors.orange)
            monitor.write("Needed: " .. formatNumber(16000 - stats.currentSand))
        else
            monitor.setTextColor(colors.lime)
            monitor.write("Excess: " .. formatNumber(stats.currentSand - 16000))
        end

        -- Display active crafting jobs
        if activeCraftingJobs.sand then
            monitor.setCursorPos(width - 15, sandSectionStart + 4)
            monitor.setTextColor(colors.lime)
            monitor.write("[Crafting...]")
        end
        if activeCraftingJobs.gunpowder then
            monitor.setCursorPos(width - 15, 8)
            monitor.setTextColor(colors.lime)
            monitor.write("[Crafting...]")
        end

        -- TNT Section Header
        monitor.setCursorPos(2, tntSectionStart)
        monitor.setTextColor(colors.lightGray)
        monitor.write(string.rep("=", width-4))  -- Stronger separator
        monitor.setCursorPos(math.floor(width/2 - 2), tntSectionStart)
        monitor.setBackgroundColor(colors.black)  -- Clear background for header
        monitor.setTextColor(colors.orange)
        monitor.write("[ TNT ]")
        monitor.setBackgroundColor(colors.black)  -- Reset background color
        
        -- TNT stats
        monitor.setCursorPos(3, tntSectionStart + 2)
        monitor.setTextColor(colors.orange)
        monitor.write("Total Crafted: " .. formatNumber(stats.tntCraftedTotal))
        
        -- Current stock on same line
        monitor.setCursorPos(width - 20, tntSectionStart + 2)
        monitor.setTextColor(colors.red)
        monitor.write("Stock: " .. formatNumber(stats.currentTNT))
        
        -- TNT production rate
        monitor.setCursorPos(3, tntSectionStart + 3)
        monitor.setTextColor(colors.lightGray)
        monitor.write("Production: ")
        if not stats.hasInitializedRates then
            monitor.setTextColor(colors.gray)
            monitor.write("Waiting...")
        elseif stats.rates.tnt.current > 0 then
            monitor.setTextColor(colors.orange)
            monitor.write("+" .. formatNumber(stats.rates.tnt.current) .. "/min")
        else
            monitor.setTextColor(colors.red)
            monitor.write(formatNumber(stats.rates.tnt.current) .. "/min")
        end
        
        -- Status line at bottom with separator
        if height > 10 then
            monitor.setCursorPos(2, height-2)
            monitor.setTextColor(colors.lightGray)
            monitor.write(string.rep("-", width-4))
            
            monitor.setCursorPos(3, height-1)
            if stats.currentGunpowder > 20000 and stats.currentSand > 16000 then
                local craftAmount = math.floor((stats.currentGunpowder - 20000) / 5)
                monitor.setTextColor(colors.lime)
                local animChar = craftingAnimation[animationFrame]
                monitor.write(animChar .. " ACTIVE: Crafting " .. formatNumber(craftAmount) .. " TNT")
                animationFrame = animationFrame + 1
                if animationFrame > #craftingAnimation then
                    animationFrame = 1
                end
            else
                monitor.setTextColor(colors.gray)
                monitor.write("* IDLE: Waiting for resources...")
            end
        end
    end)
end

-- Function to safely craft items and track active jobs
local function craftItem(itemType, amount)
    -- If there's already a crafting job for this item type, skip
    if activeCraftingJobs[itemType] then
        return false
    end
    
    -- Start tracking this crafting job
    activeCraftingJobs[itemType] = true
    
    -- Create the crafting request
    local request = {
        name = "minecraft:" .. itemType,
        amount = amount
    }
    
    -- Attempt to craft the item
    local success = pcall(function() 
        return bridge.craftItem(request)
    end)
    
    -- If crafting failed, reset the active job tracking
    if not success then
        activeCraftingJobs[itemType] = false
    end
    
    -- Return the crafting job status
    return success
end

print("ME Bridge peripheral found!")
print("TNT Crafter running. Press Ctrl+T to terminate.")

-- Main loop optimization
local lastDisplayUpdate = 0
local displayUpdateInterval = 500 -- Update display every 500ms
local lastCraftingJobCheck = 0
local craftingJobCheckInterval = 10000 -- Check crafting job status every 10 seconds

-- Main update function
local function updateRates()
  -- Refresh items from ME system
  local success, result = pcall(function() return bridge.listItems() end)
  if not success or type(result) ~= "table" then
    print("Failed to get items from ME system")
    items = {}
    sleep(1)
    return
  end
  
  items = result
  
  local currentTime = os.epoch("local")
  
  -- Store previous values for rate calculation
  stats.lastGunpowder = stats.currentGunpowder
  stats.lastSand = stats.currentSand
  stats.lastTNT = stats.currentTNT
  
  -- Check for resources
  stats.currentGunpowder = 0
  stats.currentSand = 0
  stats.currentTNT = 0
  
  -- Optimize item lookup with a table
  local itemLookup = {
    ["minecraft:gunpowder"] = function(amount) stats.currentGunpowder = amount end,
    ["minecraft:sand"] = function(amount) stats.currentSand = amount end,
    ["minecraft:tnt"] = function(amount) stats.currentTNT = amount end
  }
  
  for _, item in ipairs(items) do
    local handler = itemLookup[item.name]
    if handler then
      handler(item.amount)
    end
  end
  
  -- Periodically check and reset crafting jobs if needed
  if currentTime - lastCraftingJobCheck > craftingJobCheckInterval then
    -- Reset crafting jobs if they've been running too long
    -- This helps prevent stuck jobs from blocking future crafting
    activeCraftingJobs.sand = false
    activeCraftingJobs.gunpowder = false
    lastCraftingJobCheck = currentTime
  end
  
  -- Auto-order sand and gunpowder when below threshold
  if stats.currentSand < 16500 and not activeCraftingJobs.sand then
    craftItem("sand", 1000)
  end
  
  if stats.currentGunpowder < 16500 and not activeCraftingJobs.gunpowder then
    craftItem("gunpowder", 1000)
  end
  
  -- Reset job status if resources have increased, suggesting the job finished
  if stats.currentSand > stats.lastSand and activeCraftingJobs.sand then
    activeCraftingJobs.sand = false
  end
  
  if stats.currentGunpowder > stats.lastGunpowder and activeCraftingJobs.gunpowder then
    activeCraftingJobs.gunpowder = false
  end
  
  -- If we have enough resources, craft TNT
  if stats.currentGunpowder > 20000 and stats.currentSand > 16000 then
    local craftAmountGunpowder = math.floor((stats.currentGunpowder - 20000) / 5)
    local craftAmountSand = math.floor((stats.currentSand - 16000) / 4)
    local craftAmount = math.min(craftAmountGunpowder, craftAmountSand)
    
    if craftAmount > 0 then
      local request = {
        name = "minecraft:tnt",
        amount = craftAmount
      }
      local craftSuccess = pcall(function() return bridge.craftItem(request) end)
      if craftSuccess then
        stats.tntCraftedTotal = stats.tntCraftedTotal + craftAmount
        stats.lastCraftAmount = craftAmount
        saveStats() -- Save after successful craft
      else
        stats.lastCraftAmount = 0
      end
    end
  else
    stats.lastCraftAmount = 0
  end
  
  -- Update display only if enough time has passed
  if currentTime - lastDisplayUpdate >= displayUpdateInterval then
    -- Wrap display update in pcall for additional safety
    local success, err = pcall(updateDisplay)
    if not success then
      print("Display update error: " .. tostring(err))
      monitor = nil -- Reset monitor connection on error
    end
    lastDisplayUpdate = currentTime
  end
  
  stats.lastUpdate = currentTime
  
  -- After first successful update, set isFirstRun to false
  if stats.isFirstRun then
    stats.isFirstRun = false
    saveStats() -- Save initial state
  end
  
  -- Reduced sleep time for more responsive updates
  sleep(0.1)
end

-- Main loop
while true do
  -- Use pcall to catch any errors in the main loop
  local success, err = pcall(updateRates)
  if not success then
    print("Error in update cycle: " .. tostring(err))
    sleep(1) -- Wait a bit before trying again
  end
end

