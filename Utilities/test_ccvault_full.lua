-- test_ccvault_full.lua
-- Guided vhcctweaks smoke test with step-by-step instructions.
-- Run in-game on a CC:Tweaked computer with vhcctweaks installed.
-- Best full-pass setup: be the owner of the computer and place a chest or barrel
-- touching this computer with at least one Vault Hunters item inside.

local LOG_FILE = "vhcctweaks_smoke_test.log"
local ERROR_LOG_FILE = "vhcctweaks_smoke_test_error.log"
local AUTH_TIMEOUT_MS = 120000
local AUTH_POLL_SECONDS = 0.5
local TEST_REASON = "vhcctweaks smoke test"
local VHCC_TEST_DIR = "smoke_test"
local VHCC_TEST_FILE = VHCC_TEST_DIR .. "/probe.txt"
local VHCC_COPY_FILE = VHCC_TEST_DIR .. "/probe_copy.txt"
local VHCC_MOVED_FILE = VHCC_TEST_DIR .. "/probe_done.txt"

local CCVAULT_METHODS = {
    "isAvailable",
    "requestAuth",
    "isAuthenticated",
    "getBalance",
    "getPlayerBalance",
    "transfer",
    "getPlayerName",
    "getHostName",
    "claimHost",
    "getComputerId",
    "getSessionInfo",
    "transferSelf",
    "verifyTransaction",
    "getTransactionHistory",
}

local VHCC_METHODS = {
    "isAvailable",
    "getBasePath",
    "write",
    "append",
    "read",
    "exists",
    "isDir",
    "getSize",
    "list",
    "makeDir",
    "delete",
    "move",
    "copy",
}

local passCount = 0
local failCount = 0
local skipCount = 0
local results = {}
local logLines = {}

local function nowMs()
    return os.epoch("local")
end

local function logLine(message)
    logLines[#logLines + 1] = "[" .. nowMs() .. "] " .. tostring(message)
end

local function flushLog()
    local handle = fs.open(LOG_FILE, "w")
    if handle then
        for _, line in ipairs(logLines) do
            handle.writeLine(line)
        end
        handle.close()
    end
end

local function writeErrorLine(message)
    local handle = fs.open(ERROR_LOG_FILE, "a")
    if handle then
        handle.writeLine("[" .. nowMs() .. "] " .. tostring(message))
        handle.close()
    end
end

local function recordResult(name, status, detail)
    local normalizedDetail = detail or ""
    results[#results + 1] = {
        name = name,
        status = status,
        detail = normalizedDetail,
    }

    if status == "PASS" then
        passCount = passCount + 1
    elseif status == "FAIL" then
        failCount = failCount + 1
    else
        skipCount = skipCount + 1
    end

    logLine(status .. " | " .. name .. " | " .. normalizedDetail)
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        local message = "safeCall expected function, got " .. type(fn)
        writeErrorLine(message)
        return false, message
    end

    local args = { ... }
    local ok, first, second, third = pcall(function()
        return fn(unpack(args))
    end)

    if not ok then
        writeErrorLine(first)
    end

    return ok, first, second, third
end

local function setColor(color)
    if term.isColor and term.isColor() then
        term.setTextColor(color)
    end
end

local function resetColor()
    if term.isColor and term.isColor() then
        term.setTextColor(colors.white)
    end
end

local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

local function rule()
    local width = term.getSize()
    print(string.rep("=", width))
end

local function section(title)
    clearScreen()
    rule()
    print(title)
    rule()
    print("")
    logLine("SECTION | " .. title)
end

local function say(message)
    print(message)
    logLine("INFO | " .. message)
end

local function statusLine(status, label, detail)
    if status == "PASS" then
        setColor(colors.lime)
    elseif status == "FAIL" then
        setColor(colors.red)
    else
        setColor(colors.yellow)
    end

    print("[" .. status .. "] " .. label)
    resetColor()

    if detail and detail ~= "" then
        print("    " .. detail)
    end

    recordResult(label, status, detail)
end

local function waitForEnter(prompt)
    print("")
    setColor(colors.lightGray)
    print(prompt or "Press Enter to continue.")
    resetColor()
    read()
end

local function checkMethodTable(apiTable, apiName, methods)
    if type(apiTable) ~= "table" then
        statusLine("FAIL", apiName .. " global exists", "Got " .. type(apiTable) .. " instead of table")
        return false
    end

    statusLine("PASS", apiName .. " global exists", "Found a table")

    local missing = {}
    for _, methodName in ipairs(methods) do
        if type(apiTable[methodName]) ~= "function" then
            missing[#missing + 1] = methodName
        end
    end

    if #missing == 0 then
        statusLine("PASS", apiName .. " methods exist", table.concat(methods, ", "))
        return true
    end

    statusLine("FAIL", apiName .. " methods exist", "Missing: " .. table.concat(missing, ", "))
    return false
end

local function runStructureChecks()
    section("STEP 1 OF 5 - BASIC API CHECK")
    say("This first part checks that the mod actually loaded its Lua APIs.")
    say("If this part fails, stop here. The mod is not wired in correctly.")
    print("")

    local ccvaultOk = checkMethodTable(ccvault, "ccvault", CCVAULT_METHODS)
    local vhccOk = checkMethodTable(vhcc, "vhcc", VHCC_METHODS)
    return ccvaultOk and vhccOk
end

local function runVhccSmokeTest()
    section("STEP 2 OF 5 - VHCC FILE TEST")
    say("This part proves the vhcc file API can write, read, list, copy, move, and clean up files.")
    print("")

    local okAvailable, isAvailable = safeCall(function()
        return vhcc.isAvailable()
    end)
    if not okAvailable then
        statusLine("FAIL", "vhcc.isAvailable()", tostring(isAvailable))
        return false
    end
    if isAvailable ~= true then
        statusLine("FAIL", "vhcc.isAvailable()", "Returned " .. tostring(isAvailable))
        return false
    end
    statusLine("PASS", "vhcc.isAvailable()", "The sandbox file API is online")

    local okBase, basePath = safeCall(function()
        return vhcc.getBasePath()
    end)
    if not okBase or type(basePath) ~= "string" then
        statusLine("FAIL", "vhcc.getBasePath()", tostring(basePath))
        return false
    end
    statusLine("PASS", "vhcc.getBasePath()", "Using folder: " .. basePath)

    local contentA = "computer=" .. tostring(os.getComputerID())
    local contentB = "\ntime=" .. tostring(nowMs())

    local okMk, mkResult = safeCall(function()
        return vhcc.makeDir(VHCC_TEST_DIR)
    end)
    if not okMk or mkResult ~= true then
        statusLine("FAIL", "vhcc.makeDir()", tostring(mkResult))
        return false
    end
    statusLine("PASS", "vhcc.makeDir()", VHCC_TEST_DIR)

    local okWrite, writeResult = safeCall(function()
        return vhcc.write(VHCC_TEST_FILE, contentA)
    end)
    if not okWrite or writeResult ~= true then
        statusLine("FAIL", "vhcc.write()", tostring(writeResult))
        return false
    end
    statusLine("PASS", "vhcc.write()", VHCC_TEST_FILE)

    local okAppend, appendResult = safeCall(function()
        return vhcc.append(VHCC_TEST_FILE, contentB)
    end)
    if not okAppend or appendResult ~= true then
        statusLine("FAIL", "vhcc.append()", tostring(appendResult))
        return false
    end
    statusLine("PASS", "vhcc.append()", "Added a second line")

    local okRead, fileText = safeCall(function()
        return vhcc.read(VHCC_TEST_FILE)
    end)
    if not okRead or type(fileText) ~= "string" then
        statusLine("FAIL", "vhcc.read()", tostring(fileText))
        return false
    end
    if fileText ~= contentA .. contentB then
        statusLine("FAIL", "vhcc.read()", "Read back unexpected content")
        return false
    end
    statusLine("PASS", "vhcc.read()", "Read back the exact probe text")

    local okExists, existsResult = safeCall(function()
        return vhcc.exists(VHCC_TEST_FILE)
    end)
    if not okExists or existsResult ~= true then
        statusLine("FAIL", "vhcc.exists()", tostring(existsResult))
        return false
    end
    statusLine("PASS", "vhcc.exists()", VHCC_TEST_FILE .. " exists")

    local okSize, fileSize = safeCall(function()
        return vhcc.getSize(VHCC_TEST_FILE)
    end)
    if not okSize or type(fileSize) ~= "number" or fileSize <= 0 then
        statusLine("FAIL", "vhcc.getSize()", tostring(fileSize))
        return false
    end
    statusLine("PASS", "vhcc.getSize()", tostring(fileSize) .. " bytes")

    local okList, listResult = safeCall(function()
        return vhcc.list(VHCC_TEST_DIR)
    end)
    if not okList or type(listResult) ~= "table" then
        statusLine("FAIL", "vhcc.list()", tostring(listResult))
        return false
    end
    local sawProbe = false
    for _, name in pairs(listResult) do
        if name == "probe.txt" then
            sawProbe = true
        end
    end
    if not sawProbe then
        statusLine("FAIL", "vhcc.list()", "probe.txt not found in list output")
        return false
    end
    statusLine("PASS", "vhcc.list()", "probe.txt was listed")

    local okCopy, copyResult = safeCall(function()
        return vhcc.copy(VHCC_TEST_FILE, VHCC_COPY_FILE)
    end)
    if not okCopy or copyResult ~= true then
        statusLine("FAIL", "vhcc.copy()", tostring(copyResult))
        return false
    end
    statusLine("PASS", "vhcc.copy()", VHCC_COPY_FILE)

    local okMove, moveResult = safeCall(function()
        return vhcc.move(VHCC_COPY_FILE, VHCC_MOVED_FILE)
    end)
    if not okMove or moveResult ~= true then
        statusLine("FAIL", "vhcc.move()", tostring(moveResult))
        return false
    end
    statusLine("PASS", "vhcc.move()", VHCC_MOVED_FILE)

    local okDeleteMoved, deleteMovedResult = safeCall(function()
        return vhcc.delete(VHCC_MOVED_FILE)
    end)
    if not okDeleteMoved or deleteMovedResult ~= true then
        statusLine("FAIL", "vhcc.delete() moved copy", tostring(deleteMovedResult))
        return false
    end
    statusLine("PASS", "vhcc.delete() moved copy", "Cleanup worked")

    local okDeleteMain, deleteMainResult = safeCall(function()
        return vhcc.delete(VHCC_TEST_FILE)
    end)
    if not okDeleteMain or deleteMainResult ~= true then
        statusLine("FAIL", "vhcc.delete() main probe", tostring(deleteMainResult))
        return false
    end
    statusLine("PASS", "vhcc.delete() main probe", "Main file removed")

    local okDeleteDir, deleteDirResult = safeCall(function()
        return vhcc.delete(VHCC_TEST_DIR)
    end)
    if not okDeleteDir or deleteDirResult ~= true then
        statusLine("FAIL", "vhcc.delete() test dir", tostring(deleteDirResult))
        return false
    end
    statusLine("PASS", "vhcc.delete() test dir", "Temporary folder removed")

    return true
end

local function waitForPlayerInteraction()
    local attempts = 0
    while attempts < 3 do
        local okName, playerName = safeCall(function()
            return ccvault.getPlayerName()
        end)
        if okName and type(playerName) == "string" and playerName ~= "" then
            return true, playerName
        end

        attempts = attempts + 1
        os.sleep(0.25)
    end

    return false, nil
end

local function runCcvaultPreAuthChecks()
    section("STEP 3 OF 5 - CCVAULT PRECHECK")
    say("This part checks the economy API before any money-moving test happens.")
    print("")

    local okAvailable, available = safeCall(function()
        return ccvault.isAvailable()
    end)
    if not okAvailable then
        statusLine("FAIL", "ccvault.isAvailable()", tostring(available))
        return false, nil
    end
    if type(available) ~= "boolean" then
        statusLine("FAIL", "ccvault.isAvailable()", "Expected boolean, got " .. type(available))
        return false, nil
    end
    if available ~= true then
        statusLine("FAIL", "ccvault.isAvailable()", "Economy backend is offline")
        return false, nil
    end
    statusLine("PASS", "ccvault.isAvailable()", "Economy backend is online")

    local okPlayer, playerName = waitForPlayerInteraction()
    if not okPlayer then
        statusLine("FAIL", "Player detected on terminal", "No active player session was visible to ccvault")
        say("Close this script, right-click the computer again, and rerun it immediately.")
        return false, nil
    end
    statusLine("PASS", "Player detected on terminal", playerName)

    local okComputer, computerId = safeCall(function()
        return ccvault.getComputerId()
    end)
    if not okComputer or type(computerId) ~= "number" then
        statusLine("FAIL", "ccvault.getComputerId()", tostring(computerId))
        return false, nil
    end
    if computerId ~= os.getComputerID() then
        statusLine("FAIL", "ccvault.getComputerId()", "Returned " .. tostring(computerId) .. " but computer is " .. tostring(os.getComputerID()))
        return false, nil
    end
    statusLine("PASS", "ccvault.getComputerId()", "Computer id matches: " .. tostring(computerId))

    local okSession, sessionInfo = safeCall(function()
        return ccvault.getSessionInfo()
    end)
    if not okSession or type(sessionInfo) ~= "table" then
        statusLine("FAIL", "ccvault.getSessionInfo()", tostring(sessionInfo))
        return false, nil
    end

    local sessionGood = true
    if sessionInfo.computerId ~= os.getComputerID() then
        sessionGood = false
    end
    if type(sessionInfo.isSelfPlay) ~= "boolean" then
        sessionGood = false
    end
    if type(sessionInfo.authenticated) ~= "boolean" then
        sessionGood = false
    end

    if not sessionGood then
        statusLine("FAIL", "ccvault.getSessionInfo()", textutils.serialize(sessionInfo))
        return false, nil
    end
    statusLine("PASS", "ccvault.getSessionInfo()", textutils.serialize(sessionInfo))

    local okHost, hostName, hostError = safeCall(function()
        return ccvault.getHostName()
    end)
    if not okHost then
        statusLine("FAIL", "ccvault.getHostName()", tostring(hostName))
        return false, nil
    end
    statusLine("PASS", "ccvault.getHostName()", tostring(hostName) .. (hostError and (" | " .. tostring(hostError)) or ""))

    local okPlayerBalance, namedBalance, namedBalanceError = safeCall(function()
        return ccvault.getPlayerBalance(playerName)
    end)
    if not okPlayerBalance then
        statusLine("FAIL", "ccvault.getPlayerBalance(player)", tostring(namedBalance))
        return false, nil
    end
    if type(namedBalance) ~= "number" then
        statusLine("FAIL", "ccvault.getPlayerBalance(player)", tostring(namedBalanceError or namedBalance))
        return false, nil
    end
    statusLine("PASS", "ccvault.getPlayerBalance(player)", playerName .. " has " .. tostring(namedBalance) .. " tokens")

    return true, sessionInfo
end

local function runAuthenticationAndMoneyChecks(sessionInfo)
    section("STEP 4 OF 5 - AUTH AND MONEY TEST")
    say("This part proves auth works and then does the safest real money-path test available.")
    say("If you are the computer owner, it will use transferSelf so no balance actually changes.")
    say("If you are not the owner, it will stop before moving real money.")
    print("")

    local okAuthed, isAuthed = safeCall(function()
        return ccvault.isAuthenticated()
    end)
    if not okAuthed then
        statusLine("FAIL", "ccvault.isAuthenticated()", tostring(isAuthed))
        return false
    end

    if isAuthed == true then
        statusLine("PASS", "Authentication status", "Already authenticated")
    else
        say("You should now get a clickable APPROVE message in Minecraft chat.")
        say("If you do not see it, look at chat carefully.")

        local okRequest, requestResult, requestError = safeCall(function()
            return ccvault.requestAuth()
        end)
        if not okRequest then
            statusLine("FAIL", "ccvault.requestAuth()", tostring(requestResult))
            return false
        end

        if requestResult == true then
            statusLine("PASS", "ccvault.requestAuth()", tostring(requestError or "Prompt sent"))
        elseif requestResult == nil and type(requestError) == "string" then
            statusLine("PASS", "ccvault.requestAuth()", requestError)
        else
            statusLine("FAIL", "ccvault.requestAuth()", "Unexpected return values")
            return false
        end

        say("Now click APPROVE in chat.")
        say("I will wait up to 120 seconds.")

        local deadline = nowMs() + AUTH_TIMEOUT_MS
        local approved = false
        while nowMs() < deadline do
            os.sleep(AUTH_POLL_SECONDS)
            local okPoll, pollResult = safeCall(function()
                return ccvault.isAuthenticated()
            end)
            if okPoll and pollResult == true then
                approved = true
                break
            end
        end

        if not approved then
            statusLine("FAIL", "Authentication approval", "Timed out waiting for APPROVE click")
            return false
        end

        statusLine("PASS", "Authentication approval", "Chat approval was accepted")
    end

    local okPlayerBalance, playerBalance, playerError = safeCall(function()
        return ccvault.getBalance("player")
    end)
    if not okPlayerBalance or type(playerBalance) ~= "number" then
        statusLine("FAIL", "ccvault.getBalance('player')", tostring(playerError or playerBalance))
        return false
    end
    statusLine("PASS", "ccvault.getBalance('player')", tostring(playerBalance) .. " tokens")

    local okHostBalance, hostBalance, hostError = safeCall(function()
        return ccvault.getBalance("host")
    end)
    if not okHostBalance or type(hostBalance) ~= "number" then
        statusLine("FAIL", "ccvault.getBalance('host')", tostring(hostError or hostBalance))
        return false
    end
    statusLine("PASS", "ccvault.getBalance('host')", tostring(hostBalance) .. " tokens")

    if sessionInfo.isSelfPlay ~= true then
        statusLine("SKIP", "Real transfer path", "Not the computer owner, so this script refuses to move real money")
        say("If you want the full green proof for transfer/verify/history, run this again as the owner of the computer.")
        return true
    end

    if playerBalance < 1 then
        statusLine("SKIP", "transferSelf smoke test", "You need at least 1 token for the test-mode transfer")
        return true
    end

    local okTransfer, transferResult, transferError = safeCall(function()
        return ccvault.transferSelf(1, TEST_REASON)
    end)
    if not okTransfer or type(transferResult) ~= "table" then
        statusLine("FAIL", "ccvault.transferSelf()", tostring(transferError or transferResult))
        return false
    end

    if transferResult.success ~= true or transferResult.testMode ~= true or type(transferResult.txId) ~= "string" then
        statusLine("FAIL", "ccvault.transferSelf()", textutils.serialize(transferResult))
        return false
    end
    statusLine("PASS", "ccvault.transferSelf()", "TX " .. transferResult.txId)

    local okVerify, verifyResult = safeCall(function()
        return ccvault.verifyTransaction(transferResult.txId)
    end)
    if not okVerify or type(verifyResult) ~= "table" then
        statusLine("FAIL", "ccvault.verifyTransaction()", tostring(verifyResult))
        return false
    end
    if verifyResult.txId ~= transferResult.txId then
        statusLine("FAIL", "ccvault.verifyTransaction()", "Returned wrong transaction id")
        return false
    end
    statusLine("PASS", "ccvault.verifyTransaction()", textutils.serialize(verifyResult))

    local okHistory, historyResult = safeCall(function()
        return ccvault.getTransactionHistory(5)
    end)
    if not okHistory or type(historyResult) ~= "table" then
        statusLine("FAIL", "ccvault.getTransactionHistory()", tostring(historyResult))
        return false
    end

    local historyEntry = historyResult[1]
    if type(historyEntry) ~= "table" then
        statusLine("FAIL", "ccvault.getTransactionHistory()", "No history entries came back")
        return false
    end

    statusLine("PASS", "ccvault.getTransactionHistory()", textutils.serialize(historyEntry))

    local okBalanceAfter, balanceAfter, balanceAfterError = safeCall(function()
        return ccvault.getBalance("player")
    end)
    if not okBalanceAfter or type(balanceAfter) ~= "number" then
        statusLine("FAIL", "Balance after transferSelf", tostring(balanceAfterError or balanceAfter))
        return false
    end

    if balanceAfter ~= playerBalance then
        statusLine("FAIL", "Balance after transferSelf", "Before: " .. tostring(playerBalance) .. " | After: " .. tostring(balanceAfter))
        return false
    end
    statusLine("PASS", "Balance after transferSelf", "Balance stayed the same, so test mode behaved correctly")

    return true
end

local function findVaultItem()
    local names = peripheral.getNames()

    for _, side in ipairs(names) do
        local wrapped = peripheral.wrap(side)
        if type(wrapped) == "table" and type(wrapped.list) == "function" and type(wrapped.getItemDetail) == "function" then
            local okList, items = safeCall(function()
                return wrapped.list()
            end)
            if okList and type(items) == "table" then
                for slot, basic in pairs(items) do
                    if type(basic) == "table" and type(basic.name) == "string" then
                        if string.find(basic.name, "the_vault:", 1, true) == 1 then
                            local okDetail, detail = safeCall(function()
                                return wrapped.getItemDetail(slot)
                            end)
                            if okDetail and type(detail) == "table" then
                                return {
                                    side = side,
                                    slot = slot,
                                    basic = basic,
                                    detail = detail,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function runVaultItemCheck()
    section("STEP 5 OF 5 - VAULT ITEM DETAIL TEST")
    say("This part proves getItemDetail() is being enriched with vaultData by vhcctweaks.")
    say("For this to pass, put any Vault Hunters item in a chest or barrel touching this computer.")
    print("")

    local found = findVaultItem()
    if found then
        statusLine("PASS", "Vault item found", found.basic.name .. " on " .. found.side .. " slot " .. tostring(found.slot))

        if type(found.detail.vaultData) ~= "table" then
            statusLine("FAIL", "detail.vaultData exists", "Found a Vault item but getItemDetail() had no vaultData")
            return false
        end

        if type(found.detail.vaultData.itemType) ~= "string" then
            statusLine("FAIL", "detail.vaultData.itemType", textutils.serialize(found.detail.vaultData))
            return false
        end

        statusLine("PASS", "detail.vaultData exists", textutils.serialize(found.detail.vaultData))
        return true
    end

    statusLine("SKIP", "Vault item detail test", "No attached inventory with a Vault item was found")
    say("Set that up first, then rerun this script if you want the vaultData proof too.")
    return true
end

local function printSummary()
    section("FINAL RESULT")
    for _, entry in ipairs(results) do
        if entry.status == "PASS" then
            setColor(colors.lime)
        elseif entry.status == "FAIL" then
            setColor(colors.red)
        else
            setColor(colors.yellow)
        end

        print("[" .. entry.status .. "] " .. entry.name)
        resetColor()
        if entry.detail ~= "" then
            print("    " .. entry.detail)
        end
    end

    print("")
    rule()
    local total = passCount + failCount + skipCount
    if failCount == 0 then
        setColor(colors.lime)
        print("PASSING RUN")
    else
        setColor(colors.red)
        print("FAILING RUN")
    end
    resetColor()
    print("Total checks: " .. tostring(total))
    print("Pass: " .. tostring(passCount))
    print("Fail: " .. tostring(failCount))
    print("Skip: " .. tostring(skipCount))
    print("")
    print("Proof log written to: " .. LOG_FILE)
    print("Crash log written to: " .. ERROR_LOG_FILE)
    rule()
    flushLog()
end

local function intro()
    section("VH CCTWEAKS EASY SMOKE TEST")
    say("This script is the dumbed-down proof check.")
    say("It walks you through the important stuff in plain English.")
    print("")
    say("What this script proves when it passes:")
    say("1. The ccvault API loaded")
    say("2. The vhcc file API loaded and really works")
    say("3. Chat approval/auth works")
    say("4. Balance reads work")
    say("5. Safe self-transfer test mode works if you are the owner")
    say("6. Vault item detail enrichment works if you give it a Vault item to inspect")
    print("")
    say("Best setup before you continue:")
    say("- Be standing at the computer that will run this")
    say("- Be the OWNER of that computer if you want the full money-path proof")
    say("- Put any Vault Hunters item in a chest or barrel touching this computer")
    print("")
    waitForEnter("If that all makes sense, press Enter to start.")
end

local function main()
    intro()

    local structureOk = runStructureChecks()
    if not structureOk then
        printSummary()
        return
    end

    local vhccOk = runVhccSmokeTest()
    if not vhccOk then
        printSummary()
        return
    end

    local preAuthOk, sessionInfo = runCcvaultPreAuthChecks()
    if not preAuthOk then
        printSummary()
        return
    end

    local moneyOk = runAuthenticationAndMoneyChecks(sessionInfo)
    if not moneyOk then
        printSummary()
        return
    end

    runVaultItemCheck()
    printSummary()
end

local ok, err = pcall(main)
if not ok then
    local crashMessage = "CRASH: " .. tostring(err)
    print("")
    setColor(colors.red)
    print(crashMessage)
    resetColor()
    logLine(crashMessage)
    writeErrorLine(crashMessage)
    flushLog()
end
