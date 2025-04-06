-- Inventory Logger Script
-- Scans for and uses available inventory peripherals

-- Function to get all available inventory sources
local function getInventorySources()
    local sources = {}
    local peripheralNames = peripheral.getNames()
    
    print("Found " .. #peripheralNames .. " peripherals to check...")
    for i, name in ipairs(peripheralNames) do
        print(string.format("Checking peripheral %d/%d: %s", i, #peripheralNames, name))
        local periph = peripheral.wrap(name)
        -- Check if it's an ME Bridge
        if peripheral.hasType(name, "meBridge") then
            print("Found ME Bridge at " .. name)
            sources[#sources + 1] = {
                name = "ME System at " .. name,
                type = "me",
                peripheral = periph,
                listItems = function() 
                    print("Retrieving items from ME System...")
                    return periph.listItems() 
                end
            }
        -- Check if it's a regular inventory
        elseif peripheral.hasType(name, "inventory") then
            print("Found inventory at " .. name)
            sources[#sources + 1] = {
                name = "Inventory at " .. name,
                type = "inventory",
                peripheral = periph,
                listItems = function()
                    local items = {}
                    local size = periph.size()
                    print("Processing inventory with " .. size .. " slots...")
                    local lastProgress = 0
                    for slot = 1, size do
                        local progress = math.floor((slot / size) * 100)
                        if progress % 10 == 0 and progress > lastProgress then
                            print(string.format("Processing slots: %d%% complete", progress))
                            lastProgress = progress
                        end
                        
                        local item = periph.getItemDetail(slot)
                        if item then
                            -- Check if item already exists in our list
                            local found = false
                            for _, existingItem in ipairs(items) do
                                if existingItem.name == item.name then
                                    existingItem.amount = existingItem.amount + item.count
                                    found = true
                                    break
                                end
                            end
                            if not found then
                                items[#items + 1] = {
                                    name = item.name,
                                    amount = item.count
                                }
                            end
                        end
                    end
                    print("Finished processing " .. size .. " slots")
                    return items
                end
            }
        end
    end
    return sources
end

-- Function to get formatted timestamp
local function getTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Function to format numbers with commas
local function formatNumber(num)
    local formatted = tostring(num)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

-- Function to save inventory to log file
local function saveInventoryLog()
    print("Searching for inventory sources...")
    local sources = getInventorySources()
    if #sources == 0 then
        error("No compatible inventory peripherals found. Please connect an ME Bridge or inventory.")
    end
    
    print(string.format("Found %d inventory source(s)", #sources))
    local logFile = fs.open("inventory_log.txt", "w")
    
    -- Write header
    logFile.writeLine("Inventory Log - " .. getTimestamp())
    logFile.writeLine(string.rep("=", 50))
    
    -- Process each inventory source
    for i, source in ipairs(sources) do
        print(string.format("\nProcessing source %d/%d: %s", i, #sources, source.name))
        logFile.writeLine("\nSource: " .. source.name)
        logFile.writeLine(string.rep("-", 30))
        
        local items = source.listItems()
        print("Sorting " .. #items .. " unique items...")
        -- Sort items by amount
        table.sort(items, function(a, b) return a.amount > b.amount end)
        
        -- Write item details
        local totalItems = 0
        print("Writing items to log file...")
        local lastProgress = 0
        for j, item in ipairs(items) do
            local progress = math.floor((j / #items) * 100)
            if progress % 10 == 0 and progress > lastProgress then
                print(string.format("Writing to log: %d%% complete", progress))
                lastProgress = progress
            end
            
            local itemString = string.format("%s x%s", item.name, formatNumber(item.amount))
            logFile.writeLine(itemString)
            totalItems = totalItems + item.amount
        end
        
        -- Write summary for this source
        print("Writing summary...")
        logFile.writeLine(string.rep("-", 30))
        logFile.writeLine(string.format("Total Items: %s", formatNumber(totalItems)))
        logFile.writeLine(string.format("Unique Items: %d", #items))
    end
    
    logFile.close()
    print("\nLog file completed successfully!")
    return "inventory_log.txt"
end

-- Main execution
print("Starting inventory logging process...")
local logFile = saveInventoryLog()
print("\nInventory logged to " .. logFile)
print("Uploading to Pastebin...")

-- Upload to Pastebin
shell.run("pastebin", "put", logFile)