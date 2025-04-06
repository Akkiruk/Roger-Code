Below is a comprehensive guide for Advanced Peripherals that mirrors the style and detail of your ComputerCraft (CC: Tweaked) training document. This guide covers a range of peripherals provided by the mod—including integration with ME networks, player detection, geological scanning, inventory management, and block reading—each with self-contained code examples.

---

# Advanced Peripherals API and Add-On Mods – Example Functions

This document provides an exhaustive list of APIs and functions for the Advanced Peripherals mod along with sample code for each call. The examples are written as they would appear in a working program. They are designed to be completely self-contained so that you can reference them directly when building your ComputerCraft projects.

---

## 1. ChatBox Peripheral

The **ChatBox** peripheral enables you to send and receive messages to players in your Minecraft world.

### 1.1. `chatBox.getMessages()`
Returns an array of messages logged by the ChatBox.

**Example:**
```lua
local chatBox = peripheral.wrap("left") -- assume the ChatBox is attached on the left
local messages = chatBox.getMessages()

for i, msg in ipairs(messages) do
    print("Message " .. i .. ": " .. msg)
end
```

### 1.2. `chatBox.sendMessage(message)`
Sends a message to all players via the ChatBox.

**Example:**
```lua
local chatBox = peripheral.wrap("left")
chatBox.sendMessage("Hello, Minecraft world!")
print("Message sent!")
```

### 1.3. `chatBox.clearMessages()`
Clears all stored messages from the ChatBox.

**Example:**
```lua
local chatBox = peripheral.wrap("left")
chatBox.clearMessages()
print("Chat messages cleared.")
```

---

## 2. ME Bridge Peripheral

The **ME Bridge** integrates your ComputerCraft system with an Applied Energistics (or similar ME) network, allowing you to list, request, and store items.

### 2.1. `meBridge.listItems()`
Lists all stored items in the connected ME network.

**Example:**
```lua
local meBridge = peripheral.wrap("right") -- assume ME Bridge is on the right
local items = meBridge.listItems()

for slot, item in pairs(items) do
    print("Slot " .. slot .. ": " .. item.name .. " x" .. item.amount)
end
```

### 2.2. `meBridge.getItemDetail(slot)`
Returns detailed information about a specific item in the ME network.

**Example:**
```lua
local meBridge = peripheral.wrap("right")
local detail = meBridge.getItemDetail(1)
if detail then
    print("Item in slot 1: " .. detail.name)
else
    print("No item found in slot 1.")
end
```

### 2.3. `meBridge.requestItem(itemName, quantity)`
Requests a specific quantity of an item from the ME network.

**Example:**
```lua
local meBridge = peripheral.wrap("right")
local success = meBridge.requestItem("minecraft:diamond", 5)
if success then
    print("Requested 5 diamonds.")
else
    print("Failed to request diamonds.")
end
```

### 2.4. `meBridge.storeItem(itemName, quantity)`
Stores items into the ME network (if supported by your setup).

**Example:**
```lua
local meBridge = peripheral.wrap("right")
local success = meBridge.storeItem("minecraft:iron_ingot", 10)
if success then
    print("Stored 10 iron ingots into the ME network.")
else
    print("Failed to store items.")
end
```

---

## 3. Player Detector Peripheral

The **Player Detector** peripheral helps you monitor players in the vicinity of your computer.

### 3.1. `playerDetector.getOnlinePlayers()`
Returns a list of online players detected by the peripheral.

**Example:**
```lua
local playerDetector = peripheral.wrap("back") -- assume the detector is on the back
local players = playerDetector.getOnlinePlayers()

for _, player in ipairs(players) do
    print("Detected player: " .. player)
end
```

### 3.2. `playerDetector.getPlayerCount()`
Returns the number of players currently detected.

**Example:**
```lua
local playerDetector = peripheral.wrap("back")
local count = playerDetector.getPlayerCount()
print("Number of players detected: " .. count)
```

---

## 4. GeoScanner Peripheral

The **GeoScanner** allows you to scan a defined area for geological or block data.

### 4.1. `geoScanner.scanArea(x1, y1, z1, x2, y2, z2)`
Scans the area defined by two opposite corners and returns a table of block information.

**Example:**
```lua
local geoScanner = peripheral.wrap("top") -- assume the scanner is on the top
local scanData = geoScanner.scanArea(0, 0, 0, 10, 5, 10)

for _, block in ipairs(scanData) do
    print("Block at (" .. block.x .. ", " .. block.y .. ", " .. block.z .. "): " .. block.name)
end
```

### 4.2. `geoScanner.getBlockInfo(x, y, z)`
Returns detailed information about the block at the specified coordinates.

**Example:**
```lua
local geoScanner = peripheral.wrap("top")
local blockInfo = geoScanner.getBlockInfo(5, 3, 5)
if blockInfo then
    print("Block at (5,3,5): " .. blockInfo.name)
else
    print("No block found at the specified location.")
end
```

---

## 5. Inventory Manager Peripheral

The **Inventory Manager** peripheral provides advanced control over connected inventories such as chests.

### 5.1. `inventoryManager.listInventories()`
Returns a table listing all connected inventories.

**Example:**
```lua
local invManager = peripheral.wrap("left") -- assume the inventory manager is on the left
local inventories = invManager.listInventories()

for id, inv in pairs(inventories) do
    print("Inventory " .. id .. ": " .. inv.name)
end
```

### 5.2. `inventoryManager.getInventoryItems(inventoryId)`
Returns a table of items for a specified inventory.

**Example:**
```lua
local invManager = peripheral.wrap("left")
local items = invManager.getInventoryItems("chest1")
for slot, item in pairs(items) do
    print("Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
end
```

### 5.3. `inventoryManager.transferItem(fromInv, toInv, slot, count)`
Transfers a number of items from one inventory to another.

**Example:**
```lua
local invManager = peripheral.wrap("left")
local success = invManager.transferItem("chest1", "chest2", 1, 5)
if success then
    print("Transferred 5 items from chest1 to chest2.")
else
    print("Item transfer failed.")
end
```

---

## 6. Block Reader Peripheral

The **Block Reader** peripheral reads detailed data from blocks (or tile entities) it is attached to.

### 6.1. `blockReader.getBlockData()`
Returns detailed data from the block the reader is attached to.

**Example:**
```lua
local blockReader = peripheral.wrap("right")
local data = blockReader.getBlockData()

for key, value in pairs(data) do
    print(key .. ": " .. tostring(value))
end
```

---

## 7. Additional Utilities

Advanced Peripherals also extends the standard ComputerCraft peripheral API. These include:

### 7.1. `peripheral.call(side, method, args...)`
Calls a method on an advanced peripheral, just like in vanilla CC: Tweaked.

**Example:**
```lua
local result = peripheral.call("left", "customMethod", "arg1", 42)
print("Custom method result: " .. tostring(result))
```

### 7.2. `peripheral.getType(side)`
Returns the type of the attached advanced peripheral, which can help you identify its capabilities.

**Example:**
```lua
local pType = peripheral.getType("left")
print("Peripheral on left is: " .. pType)
```

---

# Final Notes

This guide provides a comprehensive overview of potential API calls for Advanced Peripherals in a ComputerCraft environment. Each peripheral section includes common functions and complete code examples for practical usage. Note that the actual functions available may vary with mod versions or custom configurations, so it’s always a good idea to refer to the latest documentation for your setup.

Feel free to expand or modify this guide based on the specific peripherals you are using in your projects!

