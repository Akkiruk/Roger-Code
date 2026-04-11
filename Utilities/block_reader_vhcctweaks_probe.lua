-- manifest-name: Block Reader vhcctweaks Probe
-- manifest-description: Probes an Advanced Peripherals Block Reader and reports whether vhcctweaks is blocking it.
-- Probes an Advanced Peripherals Block Reader and reports whether vhcctweaks is blocking it.

local SCRIPT_NAME = "block_reader_vhcctweaks_probe"
local LOG_FILE = SCRIPT_NAME .. ".log"
local ERROR_LOG_FILE = SCRIPT_NAME .. "_error.log"
local BLOCK_READER_METHODS = { "getBlockName", "getBlockData" }

local function nowMs()
    return os.epoch("local")
end

local function initLog(path)
    local handle = fs.open(path, "w")
    if handle then
        handle.writeLine("[" .. nowMs() .. "] initialized")
        handle.close()
    end
end

local function appendLog(path, message)
    local handle = fs.open(path, "a")
    if handle then
        handle.writeLine("[" .. nowMs() .. "] " .. tostring(message))
        handle.close()
    end
end

local function logInfo(message)
    appendLog(LOG_FILE, message)
end

local function logError(message)
    appendLog(ERROR_LOG_FILE, message)
    appendLog(LOG_FILE, "ERROR | " .. tostring(message))
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        local message = "safeCall expected function, got " .. type(fn)
        logError(message)
        return false, message
    end

    local args = { ... }
    local ok, first, second, third = pcall(function()
        return fn(unpack(args))
    end)

    if not ok then
        logError(first)
    end

    return ok, first, second, third
end

local function setTextColor(color)
    if term.isColor and term.isColor() then
        term.setTextColor(color)
    end
end

local function resetTextColor()
    if term.isColor and term.isColor() then
        term.setTextColor(colors.white)
    end
end

local function printRule()
    local width = term.getSize()
    print(string.rep("=", width))
end

local function printHeader(title)
    term.clear()
    term.setCursorPos(1, 1)
    printRule()
    print(title)
    printRule()
    print("")
end

local function printSection(title)
    print("")
    print(title)
    print(string.rep("-", #title))
end

local function printStatus(label, status, detail)
    local color = colors.yellow
    if status == "PASS" then
        color = colors.lime
    elseif status == "FAIL" then
        color = colors.red
    elseif status == "INFO" then
        color = colors.lightBlue
    end

    setTextColor(color)
    print("[" .. status .. "] " .. label)
    resetTextColor()

    if detail and detail ~= "" then
        print("    " .. detail)
    end

    logInfo(status .. " | " .. label .. " | " .. tostring(detail or ""))
end

local function askYesNo(question, defaultAnswer)
    local suffix = " [y/N] "
    local defaultValue = false
    if defaultAnswer == true then
        suffix = " [Y/n] "
        defaultValue = true
    end

    write(question .. suffix)
    local answer = read()
    if not answer or answer == "" then
        return defaultValue
    end

    answer = string.lower(answer)
    return answer == "y" or answer == "yes"
end

local function hasMethod(methods, methodName)
    if type(methods) ~= "table" then
        return false
    end

    for _, currentMethod in ipairs(methods) do
        if currentMethod == methodName then
            return true
        end
    end

    return false
end

local function joinList(values)
    if type(values) ~= "table" or #values == 0 then
        return "(none)"
    end

    local parts = {}
    for _, value in ipairs(values) do
        parts[#parts + 1] = tostring(value)
    end
    return table.concat(parts, ", ")
end

local function serializeValue(value)
    local ok, serialized = safeCall(function()
        return textutils.serialize(value)
    end)
    if ok then
        return serialized
    end
    return tostring(value)
end

local function describeType(name)
    if type(peripheral.hasType) == "function" and peripheral.hasType(name, "blockReader") then
        return "blockReader"
    end

    local peripheralType = peripheral.getType(name)
    if type(peripheralType) == "string" and peripheralType ~= "" then
        return peripheralType
    end

    return "unknown"
end

local function findBlockReaderCandidates()
    local candidates = {}
    local names = peripheral.getNames() or {}

    for _, name in ipairs(names) do
        local methods = peripheral.getMethods(name) or {}
        local peripheralType = describeType(name)
        local typeMatches = string.find(string.lower(peripheralType), "block") ~= nil
        local methodMatches = hasMethod(methods, "getBlockName") and hasMethod(methods, "getBlockData")

        if typeMatches or methodMatches then
            candidates[#candidates + 1] = {
                name = name,
                peripheralType = peripheralType,
                methods = methods,
                methodMatches = methodMatches,
            }
        end
    end

    return candidates
end

local function probeCandidate(candidate)
    local wrapped = peripheral.wrap(candidate.name)
    if not wrapped then
        return false, "Could not wrap peripheral '" .. candidate.name .. "'", nil, nil
    end

    if type(wrapped.getBlockName) ~= "function" or type(wrapped.getBlockData) ~= "function" then
        return false, "Peripheral '" .. candidate.name .. "' is missing getBlockName/getBlockData", nil, nil
    end

    local okName, blockName = safeCall(function()
        return wrapped.getBlockName()
    end)
    local okData, blockData = safeCall(function()
        return wrapped.getBlockData()
    end)

    if okName then
        logInfo(candidate.name .. " getBlockName => " .. tostring(blockName))
    else
        logError(candidate.name .. " getBlockName failed => " .. tostring(blockName))
    end

    if okData then
        logInfo(candidate.name .. " getBlockData => " .. serializeValue(blockData))
    else
        logError(candidate.name .. " getBlockData failed => " .. tostring(blockData))
    end

    if okName and okData then
        return true, "Block Reader calls succeeded", blockName, blockData
    end

    return false, "One or more Block Reader calls failed", blockName, blockData
end

local function printScenario()
    printHeader("Block Reader vhcctweaks Probe")
    print("Recommended test scenario:")
    print("1. Run this on a CC:Tweaked computer outside a vault.")
    print("2. Place an Advanced Peripherals Block Reader directly adjacent to the computer, or on the same wired modem network.")
    print("3. Point the Block Reader at a simple known block first.")
    print("4. For the altar-specific test, point it at a Vault Altar with a raw crystal inserted.")
    print("5. This script will scan peripherals, try getBlockName/getBlockData, and print a verdict.")
    print("")
    print("The clearest 'blocked by vhcctweaks' signal is:")
    print("- you confirm a Block Reader is definitely attached, but no Block Reader peripheral is detected at all.")
    print("")
end

local function run()
    initLog(LOG_FILE)
    initLog(ERROR_LOG_FILE)
    logInfo("Starting probe")

    printScenario()

    local confirmedAttached = askYesNo("Did you definitely place and wire up a Block Reader for this test?", false)
    local candidates = findBlockReaderCandidates()

    printSection("Detection")
    printStatus("Attached peripherals", "INFO", joinList(peripheral.getNames() or {}))

    if #candidates == 0 then
        printStatus("Block Reader candidate", "FAIL", "No peripheral exposing Block Reader methods was found")

        printSection("Verdict")
        if confirmedAttached then
            printStatus("VERDICT: LIKELY BLOCKED BY VHCCTWEAKS", "FAIL", "A Block Reader was expected, but no Block Reader peripheral was detected. This matches vhcctweaks forcing enableBlockReader = false in Advanced Peripherals config.")
        else
            printStatus("VERDICT: INCONCLUSIVE", "WARN", "No Block Reader was detected, but you did not confirm that one is attached. Place one first, then rerun the probe.")
        end

        print("")
        print("Logs saved to " .. LOG_FILE .. " and " .. ERROR_LOG_FILE)
        return
    end

    for index, candidate in ipairs(candidates) do
        printStatus("Candidate " .. tostring(index), "INFO", candidate.name .. " type=" .. candidate.peripheralType .. " methods=" .. joinList(candidate.methods))
    end

    printSection("Probe")
    local successfulCandidate = nil
    local lastFailure = nil
    local lastBlockName = nil

    for _, candidate in ipairs(candidates) do
        local ok, detail, blockName = probeCandidate(candidate)
        if ok then
            successfulCandidate = candidate
            lastBlockName = blockName
            printStatus("Probe " .. candidate.name, "PASS", detail .. "; target block=" .. tostring(blockName))
            break
        end

        lastFailure = detail
        printStatus("Probe " .. candidate.name, "FAIL", detail)
    end

    printSection("Verdict")
    if successfulCandidate then
        printStatus("VERDICT: NOT BLOCKED BY VHCCTWEAKS", "PASS", "Block Reader peripheral '" .. successfulCandidate.name .. "' responded to getBlockName/getBlockData. Target block: " .. tostring(lastBlockName))
    else
        printStatus("VERDICT: NOT BLOCKED BY VHCCTWEAKS", "WARN", "A Block Reader-like peripheral was detected, so the normal vhcctweaks block path is not what failed here. The peripheral exists, but the probe calls did not succeed: " .. tostring(lastFailure))
    end

    print("")
    print("Logs saved to " .. LOG_FILE .. " and " .. ERROR_LOG_FILE)
end

local ok, err = pcall(run)
if not ok then
    logError(err)
    setTextColor(colors.red)
    print("FATAL: " .. tostring(err))
    resetTextColor()
    print("See " .. ERROR_LOG_FILE)
end