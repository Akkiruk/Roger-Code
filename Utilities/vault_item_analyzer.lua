-- Vault Item Analyzer: Scans all peripheral inventories and displays vault item data on a monitor
-- Requires: vhcctweaks mod (provides vaultData via getItemDetail)

-- ============================================================
-- Configuration
-- ============================================================
local REFRESH_INTERVAL = 10 -- seconds between full rescans
local LOG_FILE = "vault_analyzer_error.log"
local ITEMS_PER_PAGE = nil -- auto-calculated from monitor height

-- ============================================================
-- Forward declarations
-- ============================================================
local mon = nil
local monW, monH = 1, 1
local allItems = {}
local currentPage = 1
local totalPages = 1
local filterType = nil -- nil = show all, or "Gear", "Jewel", etc.
local sortMode = "slot" -- "slot", "rarity", "level", "type"

-- ============================================================
-- Logging
-- ============================================================
local function logError(msg)
    local f = fs.open(LOG_FILE, "a")
    if f then
        f.writeLine("[" .. os.epoch("local") .. "] " .. tostring(msg))
        f.close()
    end
end

-- ============================================================
-- Safe peripheral call
-- ============================================================
local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, "safeCall: expected function, got " .. type(fn)
    end
    local args = { ... }
    local ok, a, b = pcall(function() return fn(table.unpack(args)) end)
    if not ok then
        logError(tostring(a))
    end
    return ok, a, b
end

-- ============================================================
-- Color helpers
-- ============================================================
local rarityColors = {
    SCRAPPY  = colors.lightGray,
    COMMON   = colors.white,
    RARE     = colors.yellow,
    EPIC     = colors.purple,
    OMEGA    = colors.red,
    UNIQUE   = colors.orange,
    SPECIAL  = colors.magenta,
    CHAOTIC  = colors.red,
}

local typeColors = {
    Gear         = colors.cyan,
    Tool         = colors.brown,
    Jewel        = colors.lime,
    Trinket      = colors.pink,
    Charm        = colors.magenta,
    Inscription  = colors.lightBlue,
    Catalyst     = colors.green,
    VaultCrystal = colors.purple,
    VaultDoll    = colors.orange,
    Card         = colors.yellow,
    Augment      = colors.red,
    Etching      = colors.cyan,
    VaultItem    = colors.lightGray,
}

local rarityOrder = {
    SCRAPPY = 1, COMMON = 2, RARE = 3, EPIC = 4,
    OMEGA = 5, UNIQUE = 6, SPECIAL = 7, CHAOTIC = 8,
}

local function getRarityColor(rarity)
    return rarityColors[rarity] or colors.white
end

local function getTypeColor(itemType)
    return typeColors[itemType] or colors.white
end

-- ============================================================
-- Monitor setup
-- ============================================================
local function findMonitor()
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        if peripheral.getType(name) == "monitor" then
            local m = peripheral.wrap(name)
            if m then
                return m, name
            end
        end
    end
    return nil, nil
end

local function setupMonitor()
    local m, name = findMonitor()
    if not m then
        print("No monitor found! Attach a monitor to continue.")
        return false
    end
    mon = m
    mon.setTextScale(0.5)
    monW, monH = mon.getSize()
    -- Header takes 3 lines, footer takes 2 lines, each item takes 1 line minimum
    ITEMS_PER_PAGE = monH - 5
    if ITEMS_PER_PAGE < 1 then ITEMS_PER_PAGE = 1 end
    print("Monitor: " .. name .. " (" .. monW .. "x" .. monH .. ")")
    print("Items per page: " .. ITEMS_PER_PAGE)
    return true
end

-- ============================================================
-- Inventory scanning
-- ============================================================
local function findInventories()
    local invs = {}
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        local methods = peripheral.getMethods(name)
        if methods then
            local hasList = false
            local hasGetItem = false
            for _, method in ipairs(methods) do
                if method == "list" then hasList = true end
                if method == "getItemDetail" then hasGetItem = true end
            end
            if hasList and hasGetItem then
                local pType = peripheral.getType(name)
                if pType ~= "monitor" and pType ~= "computer" then
                    table.insert(invs, name)
                end
            end
        end
    end
    return invs
end

local function scanInventories()
    local items = {}
    local inventories = findInventories()

    for _, invName in ipairs(inventories) do
        local inv = peripheral.wrap(invName)
        if inv then
            local ok, slotList = safeCall(inv.list)
            if ok and slotList then
                for slot, basic in pairs(slotList) do
                    local dok, detail = safeCall(inv.getItemDetail, slot)
                    if dok and detail then
                        local entry = {
                            invName = invName,
                            slot = slot,
                            name = detail.displayName or detail.name or "Unknown",
                            count = basic.count or 1,
                            mcName = basic.name or "",
                            vaultData = detail.vaultData,
                        }
                        table.insert(items, entry)
                    end
                    os.sleep(0) -- yield between detail calls
                end
            end
        end
    end

    return items
end

-- ============================================================
-- Filtering & sorting
-- ============================================================
local function getFilteredItems()
    if not filterType then
        -- Show only vault items when no filter (non-vault items aren't interesting)
        local filtered = {}
        for _, item in ipairs(allItems) do
            if item.vaultData then
                table.insert(filtered, item)
            end
        end
        return filtered
    end

    local filtered = {}
    for _, item in ipairs(allItems) do
        if item.vaultData and item.vaultData.itemType == filterType then
            table.insert(filtered, item)
        end
    end
    return filtered
end

local function sortItems(items)
    if sortMode == "rarity" then
        table.sort(items, function(a, b)
            local ar = (a.vaultData and a.vaultData.rarity) or ""
            local br = (b.vaultData and b.vaultData.rarity) or ""
            local ao = rarityOrder[ar] or 0
            local bo = rarityOrder[br] or 0
            if ao ~= bo then return ao > bo end
            return a.name < b.name
        end)
    elseif sortMode == "level" then
        table.sort(items, function(a, b)
            local al = (a.vaultData and a.vaultData.level) or 0
            local bl = (b.vaultData and b.vaultData.level) or 0
            if al ~= bl then return al > bl end
            return a.name < b.name
        end)
    elseif sortMode == "type" then
        table.sort(items, function(a, b)
            local at = (a.vaultData and a.vaultData.itemType) or ""
            local bt = (b.vaultData and b.vaultData.itemType) or ""
            if at ~= bt then return at < bt end
            return a.name < b.name
        end)
    else -- "slot" - sort by inventory name then slot
        table.sort(items, function(a, b)
            if a.invName ~= b.invName then return a.invName < b.invName end
            return a.slot < b.slot
        end)
    end
    return items
end

-- ============================================================
-- Drawing helpers
-- ============================================================
local function clearMon()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
end

local function writeAt(x, y, text, fg, bg)
    mon.setCursorPos(x, y)
    if fg then mon.setTextColor(fg) end
    if bg then mon.setBackgroundColor(bg) end
    mon.write(text)
end

local function centerText(y, text, fg, bg)
    local x = math.floor((monW - #text) / 2) + 1
    if x < 1 then x = 1 end
    writeAt(x, y, text, fg, bg)
end

local function drawHLine(y, color)
    mon.setCursorPos(1, y)
    mon.setTextColor(color or colors.gray)
    mon.write(string.rep("-", monW))
end

local function truncate(str, maxLen)
    if #str <= maxLen then return str end
    return string.sub(str, 1, maxLen - 2) .. ".."
end

local function padRight(str, len)
    if #str >= len then return string.sub(str, 1, len) end
    return str .. string.rep(" ", len - #str)
end

-- ============================================================
-- Format modifier details for expanded view
-- ============================================================
local function formatModifier(mod)
    local parts = {}
    table.insert(parts, mod.name or "???")

    if mod.tier then
        table.insert(parts, "T" .. mod.tier)
    end
    if mod.min and mod.max then
        table.insert(parts, "(" .. mod.min .. "-" .. mod.max .. ")")
    end

    local flags = {}
    if mod.legendary then table.insert(flags, "LEG") end
    if mod.crafted then table.insert(flags, "CRAFT") end
    if mod.frozen then table.insert(flags, "FROZEN") end
    if mod.greater then table.insert(flags, "GREAT") end
    if mod.abyssal then table.insert(flags, "ABYSS") end
    if mod.corrupted then table.insert(flags, "CORR") end
    if mod.imbued then table.insert(flags, "IMBU") end
    if mod.abilityEnhancement then table.insert(flags, "ABIL") end
    if #flags > 0 then
        table.insert(parts, "[" .. table.concat(flags, ",") .. "]")
    end

    return table.concat(parts, " ")
end

-- ============================================================
-- Draw item list page
-- ============================================================
local selectedItem = nil

local function drawItemList()
    clearMon()

    -- Header
    local filterLabel = filterType or "Vault Items"
    local sortLabel = "Sort:" .. sortMode
    local header = " " .. filterLabel .. " | " .. sortLabel .. " | Page " .. currentPage .. "/" .. totalPages
    writeAt(1, 1, padRight(header, monW), colors.white, colors.blue)

    -- Column headers
    local colHeader = padRight(" Slot", 6)
        .. padRight("Type", 13)
        .. padRight("Rarity", 9)
        .. padRight("Lv", 5)
        .. "Name"
    writeAt(1, 2, padRight(colHeader, monW), colors.yellow, colors.gray)

    drawHLine(3, colors.gray)

    -- Items
    local filtered = getFilteredItems()
    filtered = sortItems(filtered)
    totalPages = math.max(1, math.ceil(#filtered / ITEMS_PER_PAGE))
    if currentPage > totalPages then currentPage = totalPages end

    local startIdx = (currentPage - 1) * ITEMS_PER_PAGE + 1
    local endIdx = math.min(startIdx + ITEMS_PER_PAGE - 1, #filtered)

    if #filtered == 0 then
        centerText(math.floor(monH / 2), "No vault items found", colors.gray)
    end

    for i = startIdx, endIdx do
        local item = filtered[i]
        local y = 4 + (i - startIdx)
        local vd = item.vaultData

        if vd then
            local slotStr = padRight(" " .. tostring(item.slot), 6)
            local typeStr = padRight(vd.itemType or "?", 13)
            local rarStr = padRight(vd.rarity or "-", 9)
            local lvlStr = padRight(vd.level and tostring(vd.level) or "-", 5)
            local nameStr = truncate(vd.name or item.name, monW - 33)

            mon.setBackgroundColor(colors.black)
            writeAt(1, y, slotStr, colors.lightGray)
            writeAt(7, y, typeStr, getTypeColor(vd.itemType))
            writeAt(20, y, rarStr, getRarityColor(vd.rarity or ""))
            writeAt(29, y, lvlStr, colors.white)
            writeAt(34, y, nameStr, colors.white)
        end
    end

    -- Footer
    local footerY = monH - 1
    drawHLine(footerY, colors.gray)
    local footer = " [<] Prev  [>] Next  [F] Filter  [S] Sort  [I] Inspect  [R] Refresh"
    writeAt(1, monH, padRight(truncate(footer, monW), monW), colors.lightGray, colors.gray)
end

-- ============================================================
-- Draw item detail view
-- ============================================================
local detailScroll = 0

local function buildDetailLines(item)
    local lines = {}
    local vd = item.vaultData
    if not vd then
        table.insert(lines, { text = "No vault data available", color = colors.gray })
        return lines
    end

    -- Basic info
    table.insert(lines, { text = "=== " .. (vd.name or item.name) .. " ===", color = colors.white })
    table.insert(lines, { text = "Type: " .. (vd.itemType or "Unknown"), color = getTypeColor(vd.itemType) })
    table.insert(lines, { text = "Inventory: " .. item.invName .. " [slot " .. item.slot .. "]", color = colors.lightGray })
    table.insert(lines, { text = "", color = colors.black })

    if vd.rarity then
        table.insert(lines, { text = "Rarity: " .. vd.rarity, color = getRarityColor(vd.rarity) })
    end
    if vd.level then
        table.insert(lines, { text = "Level: " .. vd.level, color = colors.white })
    end
    if vd.state then
        table.insert(lines, { text = "State: " .. vd.state, color = colors.white })
    end
    if vd.gearType then
        table.insert(lines, { text = "Gear Type: " .. vd.gearType, color = colors.white })
    end
    if vd.equipmentSlot then
        table.insert(lines, { text = "Equip Slot: " .. vd.equipmentSlot, color = colors.white })
    end

    -- Gear-specific
    if vd.durability then
        table.insert(lines, { text = "Durability: " .. vd.durability.current .. "/" .. vd.durability.total, color = colors.white })
    end
    if vd.repairSlots then
        table.insert(lines, { text = "Repair Slots: " .. vd.repairSlots.used .. "/" .. vd.repairSlots.total, color = colors.white })
    end
    if vd.craftingPotential then
        local cp = vd.craftingPotential
        table.insert(lines, { text = "Crafting Potential: " .. (cp.current or "?") .. "/" .. (cp.max or "?"), color = colors.lime })
    end
    if vd.prefixSlots then
        table.insert(lines, { text = "Prefix Slots: " .. vd.prefixSlots, color = colors.white })
    end
    if vd.suffixSlots then
        table.insert(lines, { text = "Suffix Slots: " .. vd.suffixSlots, color = colors.white })
    end
    if vd.isLegendary then
        table.insert(lines, { text = "** LEGENDARY **", color = colors.orange })
    end
    if vd.isSoulbound then
        table.insert(lines, { text = "** SOULBOUND **", color = colors.red })
    end
    if vd.model then
        table.insert(lines, { text = "Model: " .. vd.model, color = colors.lightGray })
    end
    if vd.uniqueKey then
        table.insert(lines, { text = "Unique: " .. vd.uniqueKey, color = colors.orange })
    end

    -- Trinket-specific
    if vd.uses then
        table.insert(lines, { text = "Uses: " .. vd.uses, color = colors.white })
    end
    if vd.slot then
        table.insert(lines, { text = "Slot: " .. vd.slot, color = colors.white })
    end
    if vd.effect then
        table.insert(lines, { text = "Effect: " .. vd.effect, color = colors.lime })
    end

    -- Charm-specific
    if vd.god then
        table.insert(lines, { text = "God: " .. vd.god, color = colors.yellow })
    end
    if vd.godReputation then
        table.insert(lines, { text = "God Reputation: " .. vd.godReputation, color = colors.yellow })
    end

    -- Crystal-specific
    if vd.objective then
        table.insert(lines, { text = "Objective: " .. vd.objective, color = colors.white })
    end
    if vd.theme then
        table.insert(lines, { text = "Theme: " .. vd.theme, color = colors.white })
    end
    if vd.layout then
        table.insert(lines, { text = "Layout: " .. vd.layout, color = colors.white })
    end
    if vd.time then
        local mins = math.floor(vd.time / 20 / 60)
        local secs = math.floor(vd.time / 20) % 60
        table.insert(lines, { text = "Time: " .. mins .. "m " .. secs .. "s (" .. vd.time .. " ticks)", color = colors.white })
    end
    if vd.instability then
        table.insert(lines, { text = "Instability: " .. string.format("%.1f%%", vd.instability * 100), color = colors.red })
    end
    if vd.capacity then
        table.insert(lines, { text = "Capacity: " .. vd.capacity, color = colors.white })
    end

    -- Inscription-specific
    if vd.size then
        table.insert(lines, { text = "Size: " .. vd.size, color = colors.white })
    end
    if vd.rooms then
        table.insert(lines, { text = "Rooms:", color = colors.lightBlue })
        for _, room in ipairs(vd.rooms) do
            table.insert(lines, { text = "  - " .. room, color = colors.white })
        end
    end

    -- Catalyst-specific
    if vd.isSuper ~= nil then
        table.insert(lines, { text = "Super Catalyst: " .. tostring(vd.isSuper), color = vd.isSuper and colors.orange or colors.white })
    end

    -- Doll-specific
    if vd.playerName then
        table.insert(lines, { text = "Player: " .. vd.playerName, color = colors.white })
    end
    if vd.experience then
        table.insert(lines, { text = "Experience: " .. vd.experience, color = colors.lime })
    end

    -- Augment/Card
    if vd.cardData then
        table.insert(lines, { text = "Card Data: " .. vd.cardData, color = colors.white })
    end

    -- Modifiers
    local function addMods(label, mods, color)
        if not mods or #mods == 0 then return end
        table.insert(lines, { text = "", color = colors.black })
        table.insert(lines, { text = "--- " .. label .. " ---", color = color })
        for _, mod in ipairs(mods) do
            table.insert(lines, { text = "  " .. formatModifier(mod), color = colors.white })
        end
    end

    addMods("Implicits", vd.implicits, colors.lightGray)
    addMods("Prefixes", vd.prefixes, colors.cyan)
    addMods("Suffixes", vd.suffixes, colors.lime)

    -- Crystal modifiers
    if vd.modifiers and vd.itemType == "VaultCrystal" then
        table.insert(lines, { text = "", color = colors.black })
        table.insert(lines, { text = "--- Crystal Modifiers ---", color = colors.purple })
        for _, mod in ipairs(vd.modifiers) do
            local txt = "  " .. (mod.id or "?")
            if mod.count then txt = txt .. " x" .. mod.count end
            table.insert(lines, { text = txt, color = colors.white })
        end
    end

    -- Generic attributes
    if vd.attributes and #vd.attributes > 0 then
        table.insert(lines, { text = "", color = colors.black })
        table.insert(lines, { text = "--- Attributes ---", color = colors.yellow })
        for _, attr in ipairs(vd.attributes) do
            table.insert(lines, { text = "  " .. attr.name .. " = " .. tostring(attr.value), color = colors.white })
        end
    end

    return lines
end

local function drawDetailView(item)
    clearMon()

    local detailLines = buildDetailLines(item)
    local maxScroll = math.max(0, #detailLines - (monH - 3))
    if detailScroll > maxScroll then detailScroll = maxScroll end
    if detailScroll < 0 then detailScroll = 0 end

    -- Header
    writeAt(1, 1, padRight(" Item Detail (" .. (detailScroll + 1) .. "-" .. math.min(detailScroll + monH - 3, #detailLines) .. "/" .. #detailLines .. ")", monW), colors.white, colors.blue)

    -- Content
    for i = 1, monH - 3 do
        local lineIdx = i + detailScroll
        if lineIdx <= #detailLines then
            local line = detailLines[lineIdx]
            writeAt(1, i + 1, padRight(truncate(line.text, monW), monW), line.color, colors.black)
        end
    end

    -- Footer
    drawHLine(monH - 1, colors.gray)
    writeAt(1, monH, padRight(" [B] Back  [Up/Down] Scroll", monW), colors.lightGray, colors.gray)
end

-- ============================================================
-- Type filter cycling
-- ============================================================
local allTypes = { nil, "Gear", "Tool", "Jewel", "Trinket", "Charm", "Inscription", "Catalyst", "VaultCrystal", "VaultDoll", "Card", "Augment", "Etching" }

local function cycleFilter()
    local currentIdx = 1
    for i, t in ipairs(allTypes) do
        if t == filterType then
            currentIdx = i
            break
        end
    end
    currentIdx = currentIdx + 1
    if currentIdx > #allTypes then currentIdx = 1 end
    filterType = allTypes[currentIdx]
    currentPage = 1
end

local function cycleSortMode()
    local modes = { "slot", "rarity", "level", "type" }
    local currentIdx = 1
    for i, m in ipairs(modes) do
        if m == sortMode then
            currentIdx = i
            break
        end
    end
    currentIdx = currentIdx + 1
    if currentIdx > #modes then currentIdx = 1 end
    sortMode = modes[currentIdx]
end

-- ============================================================
-- Main loop
-- ============================================================
local viewMode = "list" -- "list" or "detail"

local function doScan()
    print("Scanning inventories...")
    local startTime = os.epoch("local")
    allItems = scanInventories()
    local elapsed = os.epoch("local") - startTime

    local vaultCount = 0
    for _, item in ipairs(allItems) do
        if item.vaultData then vaultCount = vaultCount + 1 end
    end
    print("Found " .. #allItems .. " items (" .. vaultCount .. " vault) in " .. math.floor(elapsed) .. "ms")
end

local function getSelectedItemFromPage()
    local filtered = getFilteredItems()
    filtered = sortItems(filtered)
    local startIdx = (currentPage - 1) * ITEMS_PER_PAGE + 1
    -- Return first item on page as default selection
    if startIdx <= #filtered then
        return filtered[startIdx]
    end
    return nil
end

local function handleListTouch(x, y)
    -- Check if touch is on an item row (rows 4 through 4 + ITEMS_PER_PAGE - 1)
    if y >= 4 and y < 4 + ITEMS_PER_PAGE then
        local filtered = getFilteredItems()
        filtered = sortItems(filtered)
        local idx = (currentPage - 1) * ITEMS_PER_PAGE + (y - 3)
        if idx <= #filtered then
            selectedItem = filtered[idx]
            viewMode = "detail"
            detailScroll = 0
            return true
        end
    end
    return false
end

local function main()
    -- Setup
    if not setupMonitor() then
        print("Waiting for monitor...")
        while not setupMonitor() do
            os.sleep(2)
        end
    end

    -- Initial scan
    doScan()

    -- Refresh timer
    local refreshTimer = os.startTimer(REFRESH_INTERVAL)

    while true do
        -- Draw current view
        if viewMode == "list" then
            drawItemList()
        elseif viewMode == "detail" and selectedItem then
            drawDetailView(selectedItem)
        end

        -- Wait for event
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" then
            local tx, ty = p2, p3

            if viewMode == "list" then
                -- Touch on item row = inspect
                if not handleListTouch(tx, ty) then
                    -- Touch on footer area = controls
                    if ty == monH then
                        if tx <= 10 then
                            -- Prev page
                            if currentPage > 1 then currentPage = currentPage - 1 end
                        elseif tx <= 20 then
                            -- Next page
                            if currentPage < totalPages then currentPage = currentPage + 1 end
                        elseif tx <= 32 then
                            cycleFilter()
                        elseif tx <= 42 then
                            cycleSortMode()
                        end
                    end
                end
            elseif viewMode == "detail" then
                -- Touch top half = scroll up, bottom half = scroll down, footer = back
                if ty == monH then
                    viewMode = "list"
                elseif ty < monH / 2 then
                    detailScroll = math.max(0, detailScroll - 5)
                else
                    detailScroll = detailScroll + 5
                end
            end

        elseif event == "key" then
            local key = p1

            if viewMode == "list" then
                if key == keys.left then
                    if currentPage > 1 then currentPage = currentPage - 1 end
                elseif key == keys.right then
                    if currentPage < totalPages then currentPage = currentPage + 1 end
                elseif key == keys.f then
                    cycleFilter()
                elseif key == keys.s then
                    cycleSortMode()
                elseif key == keys.r then
                    doScan()
                elseif key == keys.i then
                    local item = getSelectedItemFromPage()
                    if item then
                        selectedItem = item
                        viewMode = "detail"
                        detailScroll = 0
                    end
                elseif key == keys.q then
                    mon.clear()
                    print("Analyzer stopped.")
                    return
                end
            elseif viewMode == "detail" then
                if key == keys.b or key == keys.backspace then
                    viewMode = "list"
                elseif key == keys.up then
                    detailScroll = math.max(0, detailScroll - 1)
                elseif key == keys.down then
                    detailScroll = detailScroll + 1
                elseif key == keys.pageUp then
                    detailScroll = math.max(0, detailScroll - (monH - 3))
                elseif key == keys.pageDown then
                    detailScroll = detailScroll + (monH - 3)
                elseif key == keys.q then
                    viewMode = "list"
                end
            end

        elseif event == "timer" and p1 == refreshTimer then
            if viewMode == "list" then
                doScan()
            end
            os.cancelTimer(refreshTimer)
            refreshTimer = os.startTimer(REFRESH_INTERVAL)

        elseif event == "peripheral" or event == "peripheral_detach" then
            -- Monitor may have changed
            setupMonitor()
        end

        os.sleep(0)
    end
end

-- ============================================================
-- Entry point with error handling
-- ============================================================
local ok, err = pcall(main)
if not ok then
    logError("FATAL: " .. tostring(err))
    if mon then
        pcall(function()
            mon.setBackgroundColor(colors.black)
            mon.setTextColor(colors.red)
            mon.clear()
            mon.setCursorPos(1, 1)
            mon.write("ERROR: " .. tostring(err))
        end)
    end
    printError("Vault Analyzer crashed: " .. tostring(err))
    printError("See " .. LOG_FILE .. " for details")
end
