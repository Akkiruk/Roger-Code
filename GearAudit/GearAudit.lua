---------------------------------------------------
-- CONFIGURATION
---------------------------------------------------
local NEW_SALE_PULSE_SIDE = "back"       -- Redstone pulse side for new sales
local DUPLICATE_PULSE_SIDE = "bottom"      -- Redstone pulse side for duplicate & 3+ sales

-- File paths on the floppy (assumed mount "disk")
local SALES_DATA_FILE = "disk/sales_data.txt"              -- Minimal sales data: each line "hash count"
local DUPLICATE_LOG_FILE = "disk/duplicate_sales_log.txt"    -- Logs 3+ sale events (timestamp and hash)
local ERROR_LOG_FILE = "disk/error_log.txt"                -- Error log
local STORAGE_DELETION_LOG = "disk/storage_deletion_log.txt" -- Log for storage cleanups

-- Floppy disk size thresholds (in bytes)
local MAX_TOTAL_SIZE = 120 * 1024   -- 120 KB maximum allowed
local TARGET_TOTAL_SIZE = 90 * 1024 -- Cleanup until size is below 90 KB

---------------------------------------------------
-- GLOBAL STATISTICS
---------------------------------------------------
local newSalesCount = 0
local duplicateSalesCount = 0  -- second sale events
local triplePlusSalesCount = 0 -- for any sale where count >= 3
local lastErrorTime = nil

---------------------------------------------------
-- MINIMAL SALES DATA FILE HANDLING
---------------------------------------------------
local function loadMinimalSalesData()
  local data = {}
  if fs.exists(SALES_DATA_FILE) then
    local file = fs.open(SALES_DATA_FILE, "r")
    if file then
      for line in file.readLine, "" do
        if line then
          local hash, countStr = line:match("^(%S+)%s+(%d+)$")
          if hash and countStr then
            data[hash] = tonumber(countStr)
          end
        end
      end
      file.close()
    end
  end
  return data
end

local function saveMinimalSalesData(data)
  ensureLogDirectory(SALES_DATA_FILE)
  checkAndFreeSpace()  -- ensure we have room before saving
  local file = fs.open(SALES_DATA_FILE, "w")
  if file then
    for hash, count in pairs(data) do
      file.writeLine(hash .. " " .. count)
    end
    file.close()
  else
    print("Failed to open " .. SALES_DATA_FILE .. " for writing!")
  end
end

---------------------------------------------------
-- FLOPPY SPACE MANAGEMENT FUNCTIONS
---------------------------------------------------
local function getTotalSize(path)
  local total = 0
  for _, file in ipairs(fs.list(path)) do
    local fullPath = fs.combine(path, file)
    if not fs.isDir(fullPath) then
      total = total + fs.getSize(fullPath)
    end
  end
  return total
end

local function checkAndFreeSpace()
  local total = getTotalSize("disk")
  if total <= MAX_TOTAL_SIZE then return end

  print("Floppy usage (" .. total .. " bytes) exceeds " .. MAX_TOTAL_SIZE .. ". Initiating cleanup...")

  if fs.exists(ERROR_LOG_FILE) then
    fs.delete(ERROR_LOG_FILE)
    print("Deleted error log to free space.")
  end

  total = getTotalSize("disk")
  if fs.exists(SALES_DATA_FILE) then
    local newName = SALES_DATA_FILE .. ".old_" .. os.epoch("utc")
    fs.move(SALES_DATA_FILE, newName)
    print("Rotated sales data log to " .. newName)
  end

  total = getTotalSize("disk")
  local deletable = {}
  for _, file in ipairs(fs.list("disk")) do
    local lowerFile = string.lower(file)
    if lowerFile ~= string.lower(fs.getName(DUPLICATE_LOG_FILE))
       and lowerFile ~= string.lower(fs.getName(STORAGE_DELETION_LOG)) then
      table.insert(deletable, file)
    end
  end

  table.sort(deletable, function(a, b)
    local ta = string.match(a, "%.old_(%d+)$") or "0"
    local tb = string.match(b, "%.old_(%d+)$") or "0"
    return tonumber(ta) < tonumber(tb)
  end)

  while total > TARGET_TOTAL_SIZE and #deletable > 0 do
    local fileToDelete = table.remove(deletable, 1)
    local fullPath = fs.combine("disk", fileToDelete)
    fs.delete(fullPath)
    print("Deleted file " .. fileToDelete .. " to free space.")
    total = getTotalSize("disk")
  end

  local file = fs.open(STORAGE_DELETION_LOG, "a")
  if file then
    file.writeLine("Cleanup at " .. os.date("%Y-%m-%d %H:%M:%S") .. "; size after: " .. total .. " bytes.")
    file.close()
  end
end

---------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------
local function ensureLogDirectory(filePath)
  local dir = fs.getDir(filePath)
  if not fs.exists(dir) then fs.makeDir(dir) end
end

local function logError(err)
  ensureLogDirectory(ERROR_LOG_FILE)
  checkAndFreeSpace()
  local file = fs.open(ERROR_LOG_FILE, "a")
  if file then
    local msg = os.date("[%Y-%m-%d %H:%M:%S] ") .. "ERROR: " .. tostring(err)
    file.writeLine(msg)
    file.close()
    lastErrorTime = os.time()
  else
    print("Failed to log error to " .. ERROR_LOG_FILE)
  end
end

---------------------------------------------------
-- DUPLICATE LOGGING (for 3+ sales)
---------------------------------------------------
local function appendDuplicateLog(textLine)
  ensureLogDirectory(DUPLICATE_LOG_FILE)
  checkAndFreeSpace()
  local file = fs.open(DUPLICATE_LOG_FILE, "a")
  if file then
    file.writeLine(textLine)
    file.close()
  else
    print("Failed to open " .. DUPLICATE_LOG_FILE .. " for logging!")
  end
end

---------------------------------------------------
-- VERIFIED REDSTONE PULSE FUNCTION
---------------------------------------------------
local function sendVerifiedPulse(side)
  local attempts = 0
  while true do
    attempts = attempts + 1
    redstone.setOutput(side, true)
    sleep(0.1)
    if redstone.getOutput(side) then
      redstone.setOutput(side, false)
      break
    end
    redstone.setOutput(side, false)
    sleep(0.1)
    if attempts >= 10 then
      logError("Pulse not verified on side " .. side .. " after " .. attempts .. " attempts.")
      break
    end
  end
  sleep(0.1)
end

---------------------------------------------------
-- HASH GENERATION (Double FNV-1a 64-bit)
---------------------------------------------------
local function doubleFNV1a(input)
  local function fnv1a32(str, seed)
    local h = seed
    for i = 1, #str do
      h = bit32.bxor(h, string.byte(str, i))
      h = (h * 16777619) % 4294967296
    end
    return h
  end
  local s1, s2 = 0x811C9DC5, 0xDEADBEEF
  local h1 = fnv1a32(input, s1)
  local h2 = fnv1a32(input, s2)
  return string.format("%08x%08x", h1, h2)
end

---------------------------------------------------
-- GEAR DATA HANDLING
---------------------------------------------------
local function readGearData(vaultReader)
  if not vaultReader then return nil end
  local item = vaultReader.getItemDetail(1)
  if not item then return nil end

  -- We only need the attributes required for a unique hash.
  return {
    itemLevel = vaultReader.getItemLevel(),
    rarity = vaultReader.getRarity(),
    repairSlots = vaultReader.getRepairSlots(),
    usedRepairSlots = vaultReader.getUsedRepairSlots()
  }
end

local function generateSignature(gearData)
  local parts = {
    tostring(gearData.itemLevel),
    gearData.rarity,
    tostring(gearData.repairSlots),
    tostring(gearData.usedRepairSlots)
  }
  local s = table.concat(parts, ":")
  return doubleFNV1a(s)
end

---------------------------------------------------
-- PERIPHERAL DISCOVERY
---------------------------------------------------
local function safeWrap(name)
  local ok, wrapped = pcall(peripheral.wrap, name)
  return ok and wrapped or nil
end

local function findPeripheral(keyword)
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if t and string.find(string.lower(t), string.lower(keyword)) then
      return safeWrap(name)
    end
  end
  return nil
end

local function discoverVaultReader()
  return findPeripheral("vault")
end

---------------------------------------------------
-- CORE SALE PROCESSING
---------------------------------------------------
-- Minimal sales_data format: sales[hash] = count
local function processSale(vaultReader)
  local gearData = readGearData(vaultReader)
  if not gearData then return nil end

  local hash = generateSignature(gearData)
  local now = os.time()
  local sales = loadMinimalSalesData()
  local eventType = nil  -- "new", "dup", or "3+"

  if sales[hash] then
    sales[hash] = sales[hash] + 1
    if sales[hash] == 2 then
      eventType = "dup"  -- second sale
      duplicateSalesCount = duplicateSalesCount + 1
    else
      eventType = "3+"
      triplePlusSalesCount = triplePlusSalesCount + 1
      -- Log the event with a timestamp (only for 3+ sales)
      appendDuplicateLog(os.date("[%Y-%m-%d %H:%M:%S] ") .. "3+ Sale: " .. hash)
    end
  else
    sales[hash] = 1
    eventType = "new"
    newSalesCount = newSalesCount + 1
  end

  saveMinimalSalesData(sales)
  return {
    event = eventType,
    hash = hash,
    count = sales[hash],
    time = now
  }
end

---------------------------------------------------
-- MAIN LOOP WITH USER TERMINATION SUPPORT
---------------------------------------------------
local function mainLoop()
  local vaultReader = discoverVaultReader()
  if not vaultReader then error("No vault reader found!") end

  print("Ultimate Shop Tracker Running. Awaiting gear scan...")
  local prevItem = false
  while true do
    -- Check for termination (Ctrl+T) via os.pullEventRaw("terminate")
    local e, p = os.pullEventRaw(0.05)
    if e == "terminate" then
      print("Terminated by user.")
      return
    end

    local itemPresent = (vaultReader.getItemDetail(1) ~= nil)
    if itemPresent and not prevItem then
      local res = processSale(vaultReader)
      if res then
        if res.event == "dup" or res.event == "3+" then
          print(res.event .. " sale: " .. res.hash .. " (" .. res.count .. ")")
          sendVerifiedPulse(DUPLICATE_PULSE_SIDE)
        else
          print("New sale: " .. res.hash)
          sendVerifiedPulse(NEW_SALE_PULSE_SIDE)
        end
      end
    end
    prevItem = itemPresent
  end
end

---------------------------------------------------
-- RUNNING THE PROGRAM WITH TERMINATION SUPPORT
---------------------------------------------------
local function run()
  parallel.waitForAny(mainLoop, function()
    while true do
      local e = os.pullEventRaw("terminate")
      if e then
        print("Termination signal received. Exiting...")
        return
      end
    end
  end)
end

run()
