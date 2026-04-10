-- taskmaster_simplified.lua
-- manifest-entrypoint: true
-- manifest-category: Utilities
-- A stateless, anonymous item exchange kiosk for ComputerCraft

-- Configuration
local TURN_IN_CHEST_SIDE = "top"
local FRONT_CHEST_SIDE = "front"  -- Added front chest configuration
local REWARD_CHEST_SIDE = "bottom"
local CONSUMED_CHEST_SIDE = nil -- Optional dedicated storage for accepted turn-ins
local MONITOR_SIDE = nil -- nil means any connected monitor

-- UI_LINES_PER_TASK and other UI constants remain unchanged
local UI_LINES_PER_TASK = 2
local UI_HEADER_LINES = 3 -- Categories + blank line
local UI_FOOTER_LINES = 2 -- Scroll buttons + page info
local UI_MIN_CONTENT_LINES = 5 -- Minimum lines for task display area
local monitorScale = require("lib.monitor_scale")

-- Peripherals
local turn_in_chest = nil
local front_chest = nil  -- Added front chest peripheral
local reward_chest = nil
local consumed_chest = nil
local monitor = nil

-- Peripheral setup for speaker, chat box, and player detector
local speaker = peripheral.find("speaker")
local chatBox = peripheral.find("chatBox") or peripheral.find("chat_box")
local playerDetector = peripheral.find("playerDetector") or peripheral.find("player_detector")

-- Sound constants (from blackjack.lua and Trinkets.lua)
local SOUND_SUCCESS = "the_vault:puzzle_completion_major"
local SOUND_ERROR = "the_vault:mob_trap"
local SOUND_INFO = "minecraft:block.note_block.chime"

-- Helper: Get nearest player name (Blackjack-style, robust)
local function getNearestPlayerName()
    local playerName = nil
    pcall(function()
        for _, side in ipairs(peripheral.getNames()) do
            if peripheral.getType(side) == "playerDetector" then
                local detector = peripheral.wrap(side)
                local players = detector.getPlayersInRange and detector.getPlayersInRange(5) or {}
                if #players > 0 then
                    -- If detector supports getPlayerPos, sort by true distance
                    if detector.getPlayerPos then
                        table.sort(players, function(a, b)
                            local posA = detector.getPlayerPos(a)
                            local posB = detector.getPlayerPos(b)
                            if posA and posB then
                                local distA = math.sqrt(posA.x^2 + posA.y^2 + posA.z^2)
                                local distB = math.sqrt(posB.x^2 + posB.y^2 + posB.z^2)
                                return distA < distB
                            end
                            return false
                        end)
                    end
                    playerName = players[1]
                    break
                end
            end
        end
    end)
    return playerName or "Unknown"
end

-- Helper: Play a sound on the speaker
local function playKioskSound(sound, volume)
    if speaker and sound then
        pcall(function() speaker.playSound(sound, volume or 1.0) end)
    end
end

-- Helper: Announce trade in chat (now with color and style)
local function announceTrade(playerName, taskName, amount)
    if chatBox and chatBox.sendMessage then
        -- Use Minecraft color codes (e.g., §b for aqua, §e for yellow, §d for pink, §a for green, §6 for gold, §l for bold)
        local msg = string.format("§b§l%s§r §ejust turned in §d§l%d %s§r §afor the §6§lDecoPop event!§r", playerName, amount, taskName)
        pcall(function() chatBox.sendMessage(msg) end)
    end
end

-- UI State
local currentPage = 1
local itemsPerPage = 0
local selectedCategory = nil
local totalPages = 1
local calculateOptimalTextScale = nil

-- Task Definitions with slot IDs
-- The "slot" field defines which slot in the reward chest contains this task's reward
local DISPLAY_CATEGORIES = {
    "All Categories", -- Added for the "ALL" filter
    "Gems",
    "Resources",
    "Artifacts",
    "Consumables",
    "Scrolls",
    "Rotten Items"
}

-- Initialize selectedCategory to the first display category
selectedCategory = DISPLAY_CATEGORIES[1]

local TASKS = {
  {need = 15000, name = "Vault Scrap", category = "Resources", enabled = true, slot = 1},
  {need = 1000,  name = "Mod Box", category = "Resources", enabled = true, slot = 2},
  {need = 5000,  name = "Mystery Egg", category = "Resources", enabled = true, slot = 3},
  {need = 400,   name = "Iskallium Gem", category = "Gems", enabled = true, slot = 4, aliases = {"Vaultium Gem"}},
  {need = 400,   name = "Sparkletine Gem", category = "Gems", enabled = true, slot = 5},
  {need = 400,   name = "Ashium Gem", category = "Gems", enabled = true, slot = 6},
  {need = 400,   name = "Tubium Gem", category = "Gems", enabled = true, slot = 7},
  {need = 400,   name = "Petezanite Gem", category = "Gems", enabled = true, slot = 8},
  {need = 400,   name = "Gorginite Gem", category = "Gems", enabled = true, slot = 9},
  {need = 400,   name = "Upaline Gem", category = "Gems", enabled = true, slot = 10},
  {need = 400,   name = "Bomignite Gem", category = "Gems", enabled = true, slot = 11},
  {need = 400,   name = "Xeenium Gem", category = "Gems", enabled = true, slot = 12},  
  {need = 100000,name = "Benitoite", category = "Gems", enabled = true, slot = 13, aliases = {"Benitoite Gem"}},
  {need = 200,   name = "Resource Booster Pack", category = "Consumables", enabled = true, slot = 14},
  {need = 100,   name = "Arcane Booster Pack", category = "Consumables", enabled = true, slot = 15},
  {need = 300,   name = "Wild Booster Pack", category = "Consumables", enabled = true, slot = 16},
  {need = 250,   name = "Mixed Booster Pack", category = "Consumables", enabled = true, slot = 17},
  {need = 200,   name = "Stat Booster Pack", category = "Consumables", enabled = true, slot = 18},
  {need = 2000,  name = "Catalyst Fragment", category = "Resources", enabled = true, slot = 19},
  {need = 5000,  name = "Jewel Pouch", category = "Resources", enabled = true, slot = 20},
  {need = 200,   name = "Knowledge Star", category = "Consumables", enabled = true, slot = 21},
  {need = 30,    name = "Artifact Fragment", category = "Artifacts", enabled = true, slot = 22},
  {need = 500,   name = "Inscription Piece", category = "Resources", enabled = true, slot = 23},
  {need = 500,   name = "Wooden Chest Scroll", category = "Scrolls", enabled = true, slot = 24},
  {need = 300,   name = "Ornate Scroll", category = "Scrolls", enabled = true, slot = 25, aliases = {"Ornate Chest Scroll"}},
  {need = 300,   name = "Living Scroll", category = "Scrolls", enabled = true, slot = 26, aliases = {"Living Chest Scroll"}},
  {need = 300,   name = "Gilded Scroll", category = "Scrolls", enabled = true, slot = 27, aliases = {"Gilded Chest Scroll"}},
  {need = 20000, name = "Chromatic Iron Ore", category = "Resources", enabled = true, slot = 28},
  {need = 30,    name = "Spicy Hearty Burger", category = "Consumables", enabled = true, slot = 29},
  {need = 200,   name = "Mango", category = "Consumables", enabled = true, slot = 30},
  {need = 5,     name = "Vault Artifact", category = "Artifacts", enabled = true, slot = 31},
  {need = 400,   name = "Vault Loot Statue", category = "Resources", enabled = true, slot = 32},
  {need = 400,   name = "Gift Loot Statue", category = "Resources", enabled = true, slot = 33},
  {need = 500000,name = "Soul Shard", category = "Resources", enabled = true, slot = 34},
  {need = 1500,  name = "Packed Vault Meat Block", category = "Resources", enabled = true, slot = 35},
  {need = 500,   name = "Juicy Grape", category = "Consumables", enabled = true, slot = 36, aliases = {"Juicy Grapes"}},
  {need = 20000, name = "Vault Plating", category = "Resources", enabled = true, slot = 37},
  {need = 1,     name = "Mumbo Golden Tooth", category = "Artifacts", enabled = true, slot = 38, aliases = {"Golden Tooth"}},
  {need = 10000, name = "Dreamstone", category = "Resources", enabled = true, slot = 39},
  {need = 5000,  name = "Rotten Blood Vial", category = "Rotten Items", enabled = true, slot = 40},
  {need = 5000,  name = "Rotten Green Mob Essence", category = "Rotten Items", enabled = true, slot = 41},
  {need = 3000,  name = "Rotten Black Mob Essence", category = "Rotten Items", enabled = true, slot = 42},
  {need = 500,   name = "Rotten Empty Jar", category = "Rotten Items", enabled = true, slot = 43},
  {need = 500,   name = "Rotten Red Scroll", category = "Rotten Items", enabled = true, slot = 44},
  {need = 1000,  name = "Rotten Purple Mob Essence", category = "Rotten Items", enabled = true, slot = 45},
  {need = 2000,  name = "Rotten Skeleton Wishbone", category = "Rotten Items", enabled = true, slot = 46},
  {need = 20000, name = "Rotten Meat", category = "Rotten Items", enabled = true, slot = 47}
}

local MAX_REWARD_SLOT = 0
for _, task in ipairs(TASKS) do
    if task.slot > MAX_REWARD_SLOT then
        MAX_REWARD_SLOT = task.slot
    end
end

-- Fuzzy matching helpers
local function normalize(str)
    str = string.lower(str or "")
    str = str:gsub("_", " ")
    str = str:gsub(" chest", "") -- Remove 'chest' for scrolls
    str = str:gsub("%s+", " ")
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    return str
end

local function singularize(str)
    if str:sub(-1) == "s" then
        return str:sub(1, -2)
    end
    return str
end

local function fuzzyMatch(itemName, taskDef)
    local nItem = normalize(itemName)
    local nTask = normalize(taskDef.name)
    if nItem == nTask or singularize(nItem) == nTask or nItem == singularize(nTask) then
        return true
    end
    if taskDef.aliases then
        for _, alias in ipairs(taskDef.aliases) do
            local nAlias = normalize(alias)
            if nItem == nAlias or singularize(nItem) == nAlias or nItem == singularize(nAlias) then
                return true
            end
        end
    end
    return false
end

-- Create an indexed lookup table for faster item matching
local taskNameLookup = {}
local currentProgress = {} -- Track item counts for each task
local emptySlots = {} -- Track which reward slots are empty (checked once at startup)

local function setupPeripherals()
    turn_in_chest = peripheral.wrap(TURN_IN_CHEST_SIDE)
    if not turn_in_chest then
        print("Error: Turn-in chest (" .. TURN_IN_CHEST_SIDE .. ") not found.")
    end

    front_chest = peripheral.wrap(FRONT_CHEST_SIDE)
    if not front_chest then
        print("Warning: Front chest (" .. FRONT_CHEST_SIDE .. ") not found.")
    end

    reward_chest = peripheral.wrap(REWARD_CHEST_SIDE)
    if not reward_chest then
        print("Error: Reward chest (" .. REWARD_CHEST_SIDE .. ") not found.")
    end

    if CONSUMED_CHEST_SIDE then
        consumed_chest = peripheral.wrap(CONSUMED_CHEST_SIDE)
        if not consumed_chest then
            print("Warning: Consumed-items chest (" .. CONSUMED_CHEST_SIDE .. ") not found.")
        end
    end

    if MONITOR_SIDE then
        monitor = peripheral.wrap(MONITOR_SIDE)
    else
        monitor = peripheral.find("monitor")
    end

    if not monitor then
        print("Error: Monitor not found.")
        return false
    end

    monitor.setTextScale(calculateOptimalTextScale(monitor, UI_HEADER_LINES + UI_FOOTER_LINES + UI_MIN_CONTENT_LINES))

    -- Monitor found, calculate screen dimensions and itemsPerPage
    local w, h = monitor.getSize()
    screenWidth = w
    screenHeight = h
    local termProfile = monitorScale.forTerminal(screenWidth, screenHeight)
    local availableLinesForTasks = screenHeight - UI_HEADER_LINES - UI_FOOTER_LINES
    if availableLinesForTasks < UI_MIN_CONTENT_LINES then -- Check based on minimum content lines directly
        print("Monitor too small for meaningful task display. Need at least " .. UI_MIN_CONTENT_LINES .. " lines for tasks.")
        itemsPerPage = 0 -- Or handle error more gracefully / prevent script run
    else
        itemsPerPage = termProfile:listCapacity(UI_HEADER_LINES, UI_FOOTER_LINES, UI_LINES_PER_TASK)
    end
    print("Screen: " .. screenWidth .. "x" .. screenHeight .. ", ItemsPerPage: " .. itemsPerPage) -- Diagnostic

    return true
end

local function updateTaskNameLookup()
    taskNameLookup = {}
    for _, taskDefinition in ipairs(TASKS) do
        if taskDefinition.enabled then
            local taskNameLower = string.lower(taskDefinition.name)
            taskNameLookup[taskNameLower] = {
                slot = taskDefinition.slot,
                taskDefinition = taskDefinition
            }
            currentProgress[taskDefinition.slot] = 0 -- Initialize/reset progress for all enabled tasks
        end
    end
end

local function checkEmptyRewardSlots()
    emptySlots = {}
    
    if not reward_chest then
        for _, task in ipairs(TASKS) do
            emptySlots[task.slot] = true
        end
        return
    end
    
    for _, task in ipairs(TASKS) do
        local slot = task.slot
        local item = reward_chest.getItemDetail(slot)
        if not item or item.count <= 0 then
            emptySlots[slot] = true
        else
            emptySlots[slot] = false
        end
    end
end

local function updateCurrentProgress()
    for slot, _ in pairs(currentProgress) do
        currentProgress[slot] = 0
    end
    
    local function scanChest(chest)
        if not chest then return end
        
        local chestSize = chest.size()
        for slotIdx = 1, chestSize do
            local itemDetails = chest.getItemDetail(slotIdx)
            if itemDetails and itemDetails.count > 0 then
                local matchedTask = nil
                for _, taskDef in ipairs(TASKS) do
                    if taskDef.enabled and fuzzyMatch(itemDetails.displayName or itemDetails.name, taskDef) then
                        matchedTask = taskDef
                        break
                    end
                end
                if not matchedTask then
                    for _, taskDef in ipairs(TASKS) do
                        if taskDef.enabled and fuzzyMatch(itemDetails.name, taskDef) then
                            matchedTask = taskDef
                            break
                        end
                    end
                end
                if matchedTask then
                    local taskSlot = matchedTask.slot
                    if currentProgress[taskSlot] then
                        currentProgress[taskSlot] = currentProgress[taskSlot] + itemDetails.count
                    else
                        print("Warning: Task slot " .. taskSlot .. " for item '" .. (itemDetails.displayName or itemDetails.name) .. "' not initialized in currentProgress.")
                        currentProgress[taskSlot] = itemDetails.count
                    end
                end
            end
            if chestSize > 27 and slotIdx % 10 == 0 then -- Add a small sleep for very large chests
                os.sleep(0.01) -- Reduced from 0.05 to be less intrusive during scan
            end
        end
    end
    
    scanChest(turn_in_chest)
    scanChest(front_chest)
end

local function getItemMaxCount(itemDetails)
    return tonumber(itemDetails and itemDetails.maxCount) or 64
end

local function makeItemKey(itemDetails)
    if not itemDetails then
        return nil
    end
    return table.concat({
        tostring(itemDetails.name or ""),
        tostring(itemDetails.damage or 0),
        tostring(itemDetails.nbt or ""),
    }, "|")
end

local function getConsumedStorageTarget()
    if consumed_chest then
        local consumedName = peripheral.getName(consumed_chest)
        local rewardName = reward_chest and peripheral.getName(reward_chest) or nil
        local slotStart = 1
        if rewardName and consumedName == rewardName then
            slotStart = MAX_REWARD_SLOT + 1
        end
        return {
            inventory = consumed_chest,
            name = consumedName,
            slotStart = slotStart,
            slotEnd = consumed_chest.size(),
            label = "consumed-items chest",
        }
    end

    if not reward_chest then
        return nil
    end

    local rewardSize = reward_chest.size()
    if rewardSize <= MAX_REWARD_SLOT then
        return nil
    end

    return {
        inventory = reward_chest,
        name = peripheral.getName(reward_chest),
        slotStart = MAX_REWARD_SLOT + 1,
        slotEnd = rewardSize,
        label = "reward chest sink area",
    }
end

local function buildStorageSlots(storageTarget)
    local slots = {}
    for slot = storageTarget.slotStart, storageTarget.slotEnd do
        local item = storageTarget.inventory.getItemDetail(slot)
        table.insert(slots, {
            slot = slot,
            key = makeItemKey(item),
            count = item and item.count or 0,
            maxCount = item and getItemMaxCount(item) or nil,
        })
    end
    return slots
end

local function allocateIntoStorage(storageSlots, itemDetails, amount)
    local allocations = {}
    local remaining = amount
    local itemKey = makeItemKey(itemDetails)
    local itemMaxCount = getItemMaxCount(itemDetails)

    for _, slotState in ipairs(storageSlots) do
        if remaining <= 0 then
            break
        end
        if slotState.key == itemKey and slotState.count < slotState.maxCount then
            local free = slotState.maxCount - slotState.count
            local take = math.min(free, remaining)
            if take > 0 then
                slotState.count = slotState.count + take
                table.insert(allocations, { toSlot = slotState.slot, amount = take })
                remaining = remaining - take
            end
        end
    end

    for _, slotState in ipairs(storageSlots) do
        if remaining <= 0 then
            break
        end
        if not slotState.key then
            local take = math.min(itemMaxCount, remaining)
            slotState.key = itemKey
            slotState.count = take
            slotState.maxCount = itemMaxCount
            table.insert(allocations, { toSlot = slotState.slot, amount = take })
            remaining = remaining - take
        end
    end

    return allocations, remaining
end

local function buildTaskConsumptionPlan(taskDefForMatch, amountToConsume, storageTarget)
    if amountToConsume <= 0 then
        return {}, nil
    end

    local storageSlots = buildStorageSlots(storageTarget)
    local remaining = amountToConsume
    local plan = {}

    local function scanChest(chestInstance)
        if not chestInstance or remaining <= 0 then
            return true
        end

        for slotIdx = 1, chestInstance.size() do
            if remaining <= 0 then
                break
            end

            local itemDetails = chestInstance.getItemDetail(slotIdx)
            if itemDetails and itemDetails.count > 0 then
                if fuzzyMatch(itemDetails.displayName or itemDetails.name, taskDefForMatch)
                    or fuzzyMatch(itemDetails.name, taskDefForMatch) then
                    local plannedAmount = math.min(remaining, itemDetails.count)
                    local allocations, unallocated = allocateIntoStorage(storageSlots, itemDetails, plannedAmount)
                    if unallocated > 0 then
                        return false, "Not enough safe storage space for accepted items."
                    end

                    table.insert(plan, {
                        chest = chestInstance,
                        chestName = peripheral.getName(chestInstance),
                        slot = slotIdx,
                        amount = plannedAmount,
                        allocations = allocations,
                        item = itemDetails,
                    })
                    remaining = remaining - plannedAmount
                end
            end

            if slotIdx % 10 == 0 then
                os.sleep(0)
            end
        end

        return true
    end

    local ok, err = scanChest(turn_in_chest)
    if not ok then
        return nil, err
    end

    ok, err = scanChest(front_chest)
    if not ok then
        return nil, err
    end

    if remaining > 0 then
        return nil, string.format("Not enough %s found. Needed: %d more.", taskDefForMatch.name, remaining)
    end

    return plan, nil
end

local function executeTaskConsumptionPlan(plan, storageTarget)
    local totalMoved = 0

    for _, entry in ipairs(plan) do
        local movedForEntry = 0
        for _, allocation in ipairs(entry.allocations) do
            local moved = entry.chest.pushItems(storageTarget.name, entry.slot, allocation.amount, allocation.toSlot)
            if moved ~= allocation.amount then
                return false, totalMoved + (moved or 0)
            end
            movedForEntry = movedForEntry + moved
            totalMoved = totalMoved + moved
        end
        if movedForEntry ~= entry.amount then
            return false, totalMoved
        end
    end

    return true, totalMoved
end

local function getRewardDestinationNames(plan)
    local names = {}
    local seen = {}

    for _, entry in ipairs(plan) do
        if entry.chestName and not seen[entry.chestName] then
            table.insert(names, entry.chestName)
            seen[entry.chestName] = true
        end
    end

    if turn_in_chest then
        local name = peripheral.getName(turn_in_chest)
        if name and not seen[name] then
            table.insert(names, name)
            seen[name] = true
        end
    end

    if front_chest then
        local name = peripheral.getName(front_chest)
        if name and not seen[name] then
            table.insert(names, name)
            seen[name] = true
        end
    end

    return names
end

local function describeRewardDestination(destinationName)
    if turn_in_chest and destinationName == peripheral.getName(turn_in_chest) then
        return "your chest"
    end
    if front_chest and destinationName == peripheral.getName(front_chest) then
        return "the front chest"
    end
    return destinationName or "the output chest"
end

calculateOptimalTextScale = function(mon, linesNeeded)
    local scale = monitorScale.pickTextScaleForLines(mon, linesNeeded, 30, {
        maxScale = 2,
        fallback = 0.5,
    })
    return scale
end

local function getFilteredTasks()
    local filtered = {}
    for i, task in ipairs(TASKS) do
        if task.enabled and (selectedCategory == DISPLAY_CATEGORIES[1] or task.category == selectedCategory) then
            table.insert(filtered, task)
        end
    end
    return filtered
end

local function getRewardStockStatus(slot)
    if not reward_chest then 
        return "No Reward Chest" 
    end
    
    if emptySlots[slot] then
        return "Out of Stock"
    else
        return "Available"
    end
end

-- Drawing Functions
local screenWidth, screenHeight
local categoryButtonRegions = {}
local scrollUpRegion, scrollDownRegion, taskClickRegions, turnInTasksRegion

local function drawScreen()
    if not monitor then 
        return 
    end

    local currentTerm = term.current()
    term.redirect(monitor)
    monitor.clear()

    monitor.setCursorPos(1, 1)
    local xPos = 1
    categoryButtonRegions = {} 
    local catDisplayLine = 1

    for idx, catName in ipairs(DISPLAY_CATEGORIES) do
        local buttonText = " " .. catName .. " "
        local buttonWidth = string.len(buttonText)

        if xPos > 1 and (xPos + buttonWidth - 1 > screenWidth) then
            catDisplayLine = catDisplayLine + 1
            monitor.setCursorPos(1, catDisplayLine)
            xPos = 1
        end
        
        if catDisplayLine >= UI_HEADER_LINES then 
            break 
        end

        if catName == selectedCategory then
            monitor.setTextColor(colors.black)
            monitor.setBackgroundColor(colors.lightGray)
        else
            monitor.setTextColor(colors.white)
            monitor.setBackgroundColor(colors.gray)
        end
        
        monitor.write(buttonText)
        
        categoryButtonRegions[catName] = {
            x1 = xPos, y1 = catDisplayLine,
            x2 = xPos + buttonWidth - 1, y2 = catDisplayLine
        }
        xPos = xPos + buttonWidth
        
        monitor.setTextColor(colors.white)
        monitor.setBackgroundColor(colors.black)

        if xPos < screenWidth then 
            monitor.write(" ") 
            xPos = xPos + 1
        end
    end

    monitor.setTextColor(colors.white)
    monitor.setBackgroundColor(colors.black)

    local currentTaskLine = UI_HEADER_LINES
    monitor.setCursorPos(1, currentTaskLine)

    taskClickRegions = {}
    local tasksToDisplay = getFilteredTasks()
    totalPages = math.max(1, math.ceil(#tasksToDisplay / itemsPerPage))
    currentPage = math.min(currentPage, totalPages)

    local startIndex = (currentPage - 1) * itemsPerPage + 1
    local endIndex = math.min(startIndex + itemsPerPage - 1, #tasksToDisplay)

    for i = startIndex, endIndex do
        if currentTaskLine > (screenHeight - UI_FOOTER_LINES) then
            break
        end

        local task = tasksToDisplay[i]
        local taskSlot = task.slot

        monitor.setCursorPos(1, currentTaskLine)
        monitor.setTextColor(colors.yellow)
        
        local reqText
        reqText = string.format("%d %s -> 1 Doll", task.need, task.name)
        
        if string.len(reqText) > screenWidth then
            reqText = string.sub(reqText, 1, screenWidth - 3) .. "..."
        end
        monitor.write(reqText)

        taskClickRegions[taskSlot] = { 
            x1 = 1, y1 = currentTaskLine, 
            x2 = screenWidth, y2 = currentTaskLine, 
            task = task
        }

        currentTaskLine = currentTaskLine + 1
        if currentTaskLine > (screenHeight - UI_FOOTER_LINES) then
            break
        end
        monitor.setCursorPos(1, currentTaskLine)

        local stockStatus = getRewardStockStatus(taskSlot)
        local statusColor = colors.green
        
        if stockStatus == "Out of Stock" or stockStatus == "No Reward Chest" then 
            statusColor = colors.red
        end
        
        local stockText = "Status: " .. stockStatus
        local stockTextXPos = screenWidth - string.len(stockText) + 1
        
        monitor.write(string.rep(" ", screenWidth))
        monitor.setCursorPos(stockTextXPos, currentTaskLine)
        monitor.setTextColor(statusColor)
        monitor.write(stockText)
        monitor.setTextColor(colors.white)
        
        currentTaskLine = currentTaskLine + 1
    end

    local footerY = screenHeight
    monitor.setCursorPos(1, footerY)
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.white)
    monitor.write(string.rep(" ", screenWidth))

    local xPos = 1
    local buttonPadding = 1

    local scrollUpText = "[  Up  ]"
    monitor.setCursorPos(xPos, footerY)
    monitor.write(scrollUpText)
    scrollUpRegion = { x1 = xPos, y1 = footerY, x2 = xPos + string.len(scrollUpText) - 1, y2 = footerY }
    xPos = xPos + string.len(scrollUpText) + buttonPadding

    -- Enhanced Turn In button
    local turnInText = "<< Turn In >>"
    local turnInButtonWidth = string.len(turnInText)
    monitor.setCursorPos(xPos, footerY)
    monitor.setBackgroundColor(colors.green) -- Bright background
    monitor.setTextColor(colors.black)       -- Contrasting text
    monitor.write(turnInText)
    monitor.setBackgroundColor(colors.gray) -- Reset for other elements if any
    monitor.setTextColor(colors.white)
    turnInTasksRegion = { x1 = xPos, y1 = footerY, x2 = xPos + turnInButtonWidth - 1, y2 = footerY }
    xPos = xPos + turnInButtonWidth + buttonPadding
    
    local pageInfo = "Page " .. currentPage .. "/" .. totalPages
    local pageInfoWidth = string.len(pageInfo)
    
    local scrollDownText = "[ Down ]"
    local scrollDownWidth = string.len(scrollDownText)
    
    local remainingWidthForPageAndDown = screenWidth - xPos + 1

    if remainingWidthForPageAndDown >= pageInfoWidth + buttonPadding + scrollDownWidth then
        monitor.setCursorPos(xPos, footerY)
        monitor.write(pageInfo)
        xPos = xPos + pageInfoWidth + buttonPadding

        local finalDownX = screenWidth - scrollDownWidth + 1
        monitor.setCursorPos(finalDownX, footerY)
        monitor.write(scrollDownText)
        scrollDownRegion = { x1 = finalDownX, y1 = footerY, x2 = screenWidth, y2 = footerY }
    elseif remainingWidthForPageAndDown >= pageInfoWidth then
        monitor.setCursorPos(xPos, footerY)
        monitor.write(pageInfo)
        scrollDownRegion = nil
    else
        scrollDownRegion = nil
    end
    
    monitor.setBackgroundColor(colors.black)
    term.redirect(currentTerm)
end

local function displayFeedbackOnMonitor(messages)
    if not monitor then return end
    local currentTerm = term.current()
    term.redirect(monitor)
    monitor.clear()
    monitor.setCursorPos(1,1)
    monitor.setTextColor(colors.yellow)
    monitor.write("Exchange Summary")
    monitor.setCursorPos(1,2)
    monitor.setTextColor(colors.white)

    local function sanitize(str)
        -- Remove or replace non-ASCII characters (ComputerCraft safe)
        return (str:gsub("[^%w%p%s]", ""))
    end

    local lineNum = 3
    for _, msg in ipairs(messages) do
        if lineNum > screenHeight -1 then -- Leave space for "Touch to continue"
            monitor.setCursorPos(1, lineNum)
            monitor.write("...more (see console)...")
            break
        end
        monitor.setCursorPos(1, lineNum)
        monitor.write(sanitize(msg))
        lineNum = lineNum + 1
    end

    monitor.setCursorPos(1, screenHeight)
    monitor.setBackgroundColor(colors.blue)
    monitor.setTextColor(colors.white)
    local continueMsg = "Touch monitor to continue"
    monitor.write(string.rep(" ", math.floor((screenWidth - string.len(continueMsg)) / 2)) .. continueMsg)
    monitor.setBackgroundColor(colors.black)
    
    term.redirect(currentTerm)

    while true do
        local event, p1, p2, p3 = os.pullEvent("monitor_touch")
        local side_or_name = p1
        local ourMonitorPeripheralName = monitor and peripheral.getName(monitor)
        if type(side_or_name) == "string" then
            if side_or_name == ourMonitorPeripheralName then
                break
            end
        end
    end
end

local function performAllPossibleTaskTurnIns()
    local feedbackMessages = {}
    table.insert(feedbackMessages, "Thank you for turning in your items!")

    if not monitor then
        print("Error: Monitor not found for feedback.")
    else
        local currentTerm = term.current()
        term.redirect(monitor)
        monitor.clear()
        monitor.setCursorPos(1,1)
        monitor.setTextColor(colors.orange)
        monitor.write("Processing your exchange...")
        term.redirect(currentTerm)
    end

    if not reward_chest then 
        table.insert(feedbackMessages, "Warning: the reward chest is missing. Please contact an admin.")
        playKioskSound(SOUND_ERROR)
        displayFeedbackOnMonitor(feedbackMessages)
        return 
    end

    if not front_chest then
        front_chest = peripheral.wrap(FRONT_CHEST_SIDE)
        if front_chest then
            table.insert(feedbackMessages, "(Front chest connected.)")
        else
            table.insert(feedbackMessages, "(Front chest not found. Only top chest will be used.)")
        end
    end
    
    local hasAnInputChest = turn_in_chest or front_chest
    if not hasAnInputChest then 
        table.insert(feedbackMessages, "Warning: No input chests found. Please check the setup.")
        playKioskSound(SOUND_ERROR)
        displayFeedbackOnMonitor(feedbackMessages)
        return 
    end

    local storageTarget = getConsumedStorageTarget()
    if not storageTarget or not storageTarget.name or storageTarget.slotStart > storageTarget.slotEnd then
        table.insert(feedbackMessages, "Warning: no safe storage was found for accepted turn-ins.")
        table.insert(feedbackMessages, "Set CONSUMED_CHEST_SIDE or reserve extra sink slots after the reward stock.")
        playKioskSound(SOUND_ERROR)
        displayFeedbackOnMonitor(feedbackMessages)
        return
    end

    updateCurrentProgress()

    local overallExchangeMade = false
    local playerName = getNearestPlayerName()

    for _, taskDef in ipairs(TASKS) do
        if taskDef.enabled then
            local currentTaskProgress = currentProgress[taskDef.slot] or 0
            if currentTaskProgress >= taskDef.need then
                if emptySlots[taskDef.slot] then
                    table.insert(feedbackMessages, string.format("Task %s: Out of rewards. Please try again later.", taskDef.name))
                    playKioskSound(SOUND_ERROR)
                else
                    table.insert(feedbackMessages, string.format("%d %s accepted!", taskDef.need, taskDef.name))
                    local itemsRequiredForTask = taskDef.need
                    local plan, planErr = buildTaskConsumptionPlan(taskDef, itemsRequiredForTask, storageTarget)
                    if not plan then
                        table.insert(feedbackMessages, "Task " .. taskDef.name .. ": " .. tostring(planErr))
                        playKioskSound(SOUND_ERROR)
                    else
                        local consumedOk, totalActuallyConsumedForTask = executeTaskConsumptionPlan(plan, storageTarget)
                        if consumedOk and totalActuallyConsumedForTask >= itemsRequiredForTask then
                            local rewardPushedAmount = 0
                            local rewardPushedTo = ""

                            for _, rewardDestinationName in ipairs(getRewardDestinationNames(plan)) do
                                rewardPushedAmount = reward_chest.pushItems(rewardDestinationName, taskDef.slot, 1)
                                if rewardPushedAmount > 0 then
                                    rewardPushedTo = describeRewardDestination(rewardDestinationName)
                                    break
                                end
                            end

                            if rewardPushedAmount > 0 then
                                table.insert(feedbackMessages, string.format("Reward delivered to %s!", rewardPushedTo))
                                overallExchangeMade = true
                                local item = reward_chest.getItemDetail(taskDef.slot)
                                if not item or item.count <= 0 then
                                    emptySlots[taskDef.slot] = true
                                end
                                -- Play success sound and announce in chat for rare trade
                                playKioskSound(SOUND_SUCCESS)
                                announceTrade(playerName, taskDef.name, itemsRequiredForTask)
                            else
                                table.insert(feedbackMessages, "Reward delivery failed after items were stored safely.")
                                table.insert(feedbackMessages, "Please contact an admin so they can complete the exchange.")
                                playKioskSound(SOUND_ERROR)
                            end
                        else
                            table.insert(feedbackMessages, "Storage move failed before the reward could be delivered.")
                            table.insert(feedbackMessages, "Please contact an admin to review the stored items.")
                            playKioskSound(SOUND_ERROR)
                        end
                    end
                end
            end
        end
        os.sleep(0)
    end

    if overallExchangeMade then
        table.insert(feedbackMessages, "All done! Enjoy your reward(s).")
    else
        table.insert(feedbackMessages, "No exchanges could be completed this time.")
    end
    checkEmptyRewardSlots()
    updateCurrentProgress()
    displayFeedbackOnMonitor(feedbackMessages)
end

-- Event Handlers
local function handleTouch(x, y)
    local changed = false
    for catName, region in pairs(categoryButtonRegions) do
        if x >= region.x1 and x <= region.x2 and y >= region.y1 and y <= region.y2 then
            if selectedCategory ~= catName then
                selectedCategory = catName
                currentPage = 1
                changed = true
            end
            return changed
        end
    end

    if turnInTasksRegion and x >= turnInTasksRegion.x1 and x <= turnInTasksRegion.x2 and y >= turnInTasksRegion.y1 and y <= turnInTasksRegion.y2 then
        performAllPossibleTaskTurnIns()
        changed = true
        return changed
    end

    if scrollUpRegion and x >= scrollUpRegion.x1 and x <= scrollUpRegion.x2 and y >= scrollUpRegion.y1 and y <= scrollUpRegion.y2 then
        if currentPage > 1 then 
            currentPage = currentPage - 1
            changed = true
        end
        return changed
    end
    if scrollDownRegion and x >= scrollDownRegion.x1 and x <= scrollDownRegion.x2 and y >= scrollDownRegion.y1 and y <= scrollDownRegion.y2 then
        if currentPage < totalPages then 
            currentPage = currentPage + 1
            changed = true
        end
        return changed
    end

    for taskIdx, region in pairs(taskClickRegions) do
        if x >= region.x1 and x <= region.x2 and y >= region.y1 and y <= region.y2 then
            return false
        end
    end

    return changed
end

-- Main protected loop: restart computer on any error
local function main()
    if not setupPeripherals() then
        return
    end

    updateTaskNameLookup()
    checkEmptyRewardSlots()

    monitor.setTextScale(calculateOptimalTextScale(monitor, UI_HEADER_LINES + UI_FOOTER_LINES + UI_MIN_CONTENT_LINES))
    screenWidth, screenHeight = monitor.getSize()
    local termProfile = monitorScale.forTerminal(screenWidth, screenHeight)
    itemsPerPage = termProfile:listCapacity(UI_HEADER_LINES, UI_FOOTER_LINES, UI_LINES_PER_TASK)

    local changed = true

    while true do
        if changed then
            drawScreen()
            changed = false
        end

        local event, p1, p2, p3, p4 = os.pullEventRaw()

        if event == "terminate" then
            break
        elseif event == "monitor_touch" then
            local side_or_name, x, y = p1, p2, p3
            local ourMonitorPeripheralName = monitor and peripheral.getName(monitor)
            
            local touchedOurMonitor = false
            if type(side_or_name) == "string" then
                if side_or_name == ourMonitorPeripheralName then
                    touchedOurMonitor = true
                else
                    local wrappedSide = peripheral.wrap(side_or_name)
                    if wrappedSide and peripheral.getName(wrappedSide) == ourMonitorPeripheralName then
                        touchedOurMonitor = true
                    end
                end
            end

            if touchedOurMonitor then
                if handleTouch(x, y) then
                    changed = true
                end
            end
        end
        os.sleep(0.05) -- Yield for a bit longer in the main loop
    end

    local currentTermTarget = term.current()
    if monitor and currentTermTarget and type(currentTermTarget.getPaletteColor) == "function" then
        term.redirect(term.native())
        monitor.clear()
    end
end

-- Crash protection: restart computer on any error
while true do
    local ok, err = pcall(main)
    if not ok then
        if term then term.setCursorPos(1,1) term.clear() end
        print("Script crashed! Restarting computer in 2 seconds...")
        os.sleep(2)
        os.reboot()
    else
        break
    end
end
