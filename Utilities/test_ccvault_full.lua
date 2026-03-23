-- test_ccvault_full.lua
-- Comprehensive step-by-step integration test for the CCVault economy API.
-- Validates every @LuaFunction in CCVaultAPI.java against the real mod.
--
-- Run on a CC:Tweaked computer in-game with vhcctweaks loaded.
-- The player running the test should be the computer's owner (self-play)
-- so that transferSelf and escrow flows can be exercised.
--
-- Usage:  Right-click computer, then:  test_ccvault_full

-- ============================================================
--  CONSTANTS & CONFIG
-- ============================================================

local LOG_FILE     = "ccvault_test_full.log"
local MAX_REASON   = 64     -- CCVaultAPI.MAX_REASON_LENGTH
local AUTH_TIMEOUT = 120    -- seconds to wait for player to click [APPROVE]
local AUTH_POLL    = 0.5    -- poll interval for auth check

-- All 16 @LuaFunction methods from CCVaultAPI.java
local EXPECTED_METHODS = {
    "isAvailable",
    "requestAuth",
    "isAuthenticated",
    "getBalance",
    "transfer",
    "getPlayerName",
    "getHostName",
    "getComputerId",
    "getSessionInfo",
    "transferSelf",
    "verifyTransaction",
    "getTransactionHistory",
    "escrow",
    "resolveEscrow",
    "cancelEscrow",
    "getEscrowInfo",
}

-- ============================================================
--  TEST FRAMEWORK
-- ============================================================

local results  = {}   -- { {name, passed, detail}, ... }
local logLines = {}
local passCount, failCount, skipCount = 0, 0, 0

local function ts()
    return os.epoch("local")
end

local function log(msg)
    local line = "[" .. ts() .. "] " .. tostring(msg)
    logLines[#logLines + 1] = line
end

local function flushLog()
    local h = fs.open(LOG_FILE, "w")
    if h then
        for _, line in ipairs(logLines) do
            h.writeLine(line)
        end
        h.close()
    end
end

local function record(name, passed, detail)
    results[#results + 1] = { name = name, passed = passed, detail = detail or "" }
    if passed == true then
        passCount = passCount + 1
        log("PASS  " .. name .. (detail and ("  " .. detail) or ""))
    elseif passed == false then
        failCount = failCount + 1
        log("FAIL  " .. name .. "  " .. tostring(detail))
    else
        skipCount = skipCount + 1
        log("SKIP  " .. name .. "  " .. tostring(detail))
    end
end

-- Safe wrapper — never crashes the test suite
local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, "safeCall: expected function, got " .. type(fn)
    end
    local args = { ... }
    local ok, a, b = pcall(function() return fn(table.unpack(args)) end)
    return ok, a, b
end

-- ============================================================
--  DISPLAY HELPERS
-- ============================================================

local W, H = term.getSize()

local function hr()
    print(string.rep("-", W))
end

local function banner(text)
    hr()
    local pad = math.floor((W - #text) / 2)
    if pad < 0 then pad = 0 end
    print(string.rep(" ", pad) .. text)
    hr()
end

local function colPrint(color, msg)
    local old = term.getTextColor()
    term.setTextColor(color)
    print(msg)
    term.setTextColor(old)
end

local function printResult(name, passed, detail)
    if passed == true then
        colPrint(colors.green, "[PASS] " .. name)
    elseif passed == false then
        colPrint(colors.red,   "[FAIL] " .. name)
        if detail and #detail > 0 then
            colPrint(colors.red, "       " .. detail)
        end
    else
        colPrint(colors.yellow, "[SKIP] " .. name)
        if detail and #detail > 0 then
            colPrint(colors.yellow, "       " .. detail)
        end
    end
end

local function waitKey(msg)
    colPrint(colors.lightGray, msg or "Press any key to continue...")
    os.pullEvent("key")
    os.sleep(0)  -- yield so key_up is consumed
end

-- ============================================================
--  PHASE 0 — GLOBAL EXISTS
-- ============================================================

local function phase0_global()
    banner("PHASE 0: Global Check")

    -- 0.1  ccvault global exists and is a table
    local t = type(ccvault)
    if t ~= "table" then
        record("ccvault global is table", false, "type is " .. t)
        colPrint(colors.red, "FATAL: ccvault global is " .. t .. ", not table.")
        colPrint(colors.red, "Is vhcctweaks loaded? Aborting remaining tests.")
        return false
    end
    record("ccvault global is table", true)

    -- 0.2  Every expected method exists and is a function
    local missing = {}
    for _, name in ipairs(EXPECTED_METHODS) do
        if type(ccvault[name]) ~= "function" then
            missing[#missing + 1] = name
            record("method exists: " .. name, false, "type=" .. type(ccvault[name]))
        else
            record("method exists: " .. name, true)
        end
    end

    if #missing > 0 then
        colPrint(colors.red, "Missing methods: " .. table.concat(missing, ", "))
        colPrint(colors.red, "Some tests will be skipped.")
    else
        colPrint(colors.green, "All 16 expected methods present.")
    end

    -- 0.3  No unexpected keys (informational, not a fail)
    local extras = {}
    local methodSet = {}
    for _, name in ipairs(EXPECTED_METHODS) do methodSet[name] = true end
    for k in pairs(ccvault) do
        if not methodSet[k] then
            extras[#extras + 1] = tostring(k)
        end
    end
    if #extras > 0 then
        log("INFO  extra keys on ccvault: " .. table.concat(extras, ", "))
        print("Extra keys: " .. table.concat(extras, ", "))
    end

    return true
end

-- ============================================================
--  PHASE 1 — PRE-AUTH METHODS (no auth required)
-- ============================================================

local function phase1_preauth()
    banner("PHASE 1: Pre-Auth Methods")

    -- 1.1  isAvailable() returns a boolean
    local ok, val = safeCall(ccvault.isAvailable)
    if not ok then
        record("isAvailable() no throw", false, tostring(val))
    else
        record("isAvailable() no throw", true)
        record("isAvailable() returns boolean", type(val) == "boolean", "got " .. type(val))
        print("  Economy available: " .. tostring(val))
        if not val then
            colPrint(colors.yellow, "  WARNING: Economy unavailable (Dog's PlayerShops not loaded).")
            colPrint(colors.yellow, "  Transfer/balance tests will fail with 'economy system not available'.")
        end
    end

    -- 1.2  getComputerId() returns a number
    local ok2, cid = safeCall(ccvault.getComputerId)
    if not ok2 then
        record("getComputerId() no throw", false, tostring(cid))
    else
        record("getComputerId() no throw", true)
        record("getComputerId() returns number", type(cid) == "number", "got " .. type(cid))
        record("getComputerId() == os.getComputerID()", cid == os.getComputerID(),
            "got " .. tostring(cid) .. " expected " .. tostring(os.getComputerID()))
        print("  Computer ID: " .. tostring(cid))
    end

    -- 1.3  getPlayerName() returns string or nil (no error throw)
    local ok3, pname = safeCall(ccvault.getPlayerName)
    if not ok3 then
        record("getPlayerName() no throw", false, tostring(pname))
    else
        record("getPlayerName() no throw", true)
        local pt = type(pname)
        record("getPlayerName() returns string|nil", pt == "string" or pt == "nil",
            "got " .. pt)
        print("  Player name: " .. tostring(pname))
    end

    -- 1.4  getHostName() returns string, or nil+error
    local ok4, hname, herr = safeCall(ccvault.getHostName)
    if not ok4 then
        record("getHostName() no throw", false, tostring(hname))
    else
        record("getHostName() no throw", true)
        local ht = type(hname)
        record("getHostName() returns string|nil", ht == "string" or ht == "nil",
            "got " .. ht .. " err=" .. tostring(herr))
        print("  Host name: " .. tostring(hname) .. (herr and (" (" .. herr .. ")") or ""))
    end

    -- 1.5  isAuthenticated() returns boolean, no throw
    local ok5, auth = safeCall(ccvault.isAuthenticated)
    if not ok5 then
        record("isAuthenticated() no throw", false, tostring(auth))
    else
        record("isAuthenticated() no throw", true)
        record("isAuthenticated() returns boolean", type(auth) == "boolean",
            "got " .. type(auth))
        print("  Authenticated: " .. tostring(auth))
    end

    -- 1.6  getSessionInfo() returns a table with expected keys
    local ok6, info = safeCall(ccvault.getSessionInfo)
    if not ok6 then
        record("getSessionInfo() no throw", false, tostring(info))
    else
        record("getSessionInfo() no throw", true)
        record("getSessionInfo() returns table", type(info) == "table",
            "got " .. type(info))

        if type(info) == "table" then
            local expectedKeys = {
                "computerId", "playerName", "hostName", "isSelfPlay",
                "authenticated", "transfersRemaining",
                "terminalTransfersRemaining", "playerTransfersRemaining"
            }
            for _, k in ipairs(expectedKeys) do
                local present = info[k] ~= nil
                record("sessionInfo has '" .. k .. "'", present,
                    present and (type(info[k]) .. "=" .. tostring(info[k])) or "missing")
            end

            -- computerId must match
            record("sessionInfo.computerId matches",
                info.computerId == os.getComputerID(),
                tostring(info.computerId) .. " vs " .. tostring(os.getComputerID()))

            -- isSelfPlay must be boolean
            record("sessionInfo.isSelfPlay is boolean",
                type(info.isSelfPlay) == "boolean",
                "got " .. type(info.isSelfPlay))

            -- transfersRemaining must be a number
            record("sessionInfo.transfersRemaining is number",
                type(info.transfersRemaining) == "number",
                "got " .. type(info.transfersRemaining))

            print("  Session info:")
            for k, v in pairs(info) do
                print("    " .. tostring(k) .. " = " .. tostring(v))
            end
        end
    end
end

-- ============================================================
--  PHASE 2 — AUTH ERRORS (calling auth-only methods without auth)
-- ============================================================

local function phase2_noauth_errors()
    banner("PHASE 2: Auth-Required Error Checks")
    print("Testing that auth-gated methods throw when unauthenticated...")

    -- These should all throw "not authenticated ..." or "no player interacting ..."
    local authMethods = {
        { "getBalance('player')",       function() return ccvault.getBalance("player") end },
        { "transfer(...)",              function() return ccvault.transfer("player","host",1,"t") end },
        { "transferSelf(1, 'test')",    function() return ccvault.transferSelf(1, "test") end },
        { "verifyTransaction('fake')",  function() return ccvault.verifyTransaction("fake") end },
        { "getTransactionHistory(5)",   function() return ccvault.getTransactionHistory(5) end },
        { "escrow(1, 'test')",          function() return ccvault.escrow(1, "test") end },
        { "resolveEscrow('x','host','r')", function() return ccvault.resolveEscrow("x","host","r") end },
        { "cancelEscrow('x', 'r')",     function() return ccvault.cancelEscrow("x", "r") end },
        { "getEscrowInfo('x')",         function() return ccvault.getEscrowInfo("x") end },
    }

    for _, entry in ipairs(authMethods) do
        local label, fn = entry[1], entry[2]
        local ok, err = pcall(fn)
        if not ok then
            -- Good: it threw an error
            local errStr = tostring(err)
            local isExpected = errStr:find("not authenticated") or errStr:find("no player interacting")
            record(label .. " throws when unauthed", isExpected ~= nil,
                "error: " .. errStr:sub(1, 80))
        else
            -- Bad: it returned without error (might still return nil, err)
            record(label .. " throws when unauthed", false,
                "did not throw (returned " .. tostring(err) .. ")")
        end
    end
end

-- ============================================================
--  PHASE 3 — AUTHENTICATION FLOW
-- ============================================================

local function phase3_authenticate()
    banner("PHASE 3: Authentication")

    -- Already authed?
    local ok, authed = safeCall(ccvault.isAuthenticated)
    if ok and authed == true then
        colPrint(colors.green, "Already authenticated! Skipping auth flow.")
        record("authentication", true, "already authenticated")
        return true
    end

    -- Check player is interacting
    local ok2, pname = safeCall(ccvault.getPlayerName)
    if not ok2 or pname == nil then
        colPrint(colors.yellow, "No player detected. Right-click the computer first!")
        waitKey("Right-click this computer, then press a key...")
        -- Re-check
        ok2, pname = safeCall(ccvault.getPlayerName)
        if not ok2 or pname == nil then
            record("player detected for auth", false, "still no player after prompt")
            return false
        end
    end
    record("player detected for auth", true, tostring(pname))
    print("  Player: " .. tostring(pname))

    -- Request auth
    local okR, result, rerr = safeCall(ccvault.requestAuth)
    if not okR then
        record("requestAuth() call", false, tostring(result))
        return false
    end

    if result == true then
        record("requestAuth() sent prompt", true)
        colPrint(colors.cyan, "  Auth prompt sent! Click [APPROVE] in chat.")
    elseif result == nil and rerr then
        -- "auth request already pending"
        record("requestAuth() pending response", true, tostring(rerr))
        colPrint(colors.cyan, "  " .. tostring(rerr))
    else
        record("requestAuth() unexpected return", false,
            "result=" .. tostring(result) .. " err=" .. tostring(rerr))
        return false
    end

    -- Poll for auth with timeout
    colPrint(colors.white, "  Waiting up to " .. AUTH_TIMEOUT .. "s for you to click [APPROVE]...")
    local deadline = os.clock() + AUTH_TIMEOUT
    while os.clock() < deadline do
        os.sleep(AUTH_POLL)
        local okA, a = safeCall(ccvault.isAuthenticated)
        if okA and a == true then
            record("authentication approved", true)
            colPrint(colors.green, "  Authenticated!")
            return true
        end
    end

    record("authentication approved", false, "timed out after " .. AUTH_TIMEOUT .. "s")
    colPrint(colors.red, "  Auth timed out. Cannot continue financial tests.")
    return false
end

-- ============================================================
--  PHASE 4 — INPUT VALIDATION (bad args to transfer/escrow)
-- ============================================================

local function phase4_validation()
    banner("PHASE 4: Input Validation")

    -- transfer() validations — these return nil, error (not throw)
    local transferCases = {
        { "transfer: from==to",
            function() return ccvault.transfer("player","player",1,"x") end,
            "cannot transfer to self" },
        { "transfer: amount <= 0",
            function() return ccvault.transfer("player","host",0,"x") end,
            "amount must be positive" },
        { "transfer: negative amount",
            function() return ccvault.transfer("player","host",-5,"x") end,
            "amount must be positive" },
        { "transfer: empty reason",
            function() return ccvault.transfer("player","host",1,"") end,
            "reason is required" },
        { "transfer: reason too long",
            function() return ccvault.transfer("player","host",1,string.rep("A", MAX_REASON + 1)) end,
            "reason too long" },
    }

    for _, tc in ipairs(transferCases) do
        local label, fn, expectErr = tc[1], tc[2], tc[3]
        local ok, val, err = pcall(fn)
        if not ok then
            -- Method threw instead of returning nil, err — still check message
            local errStr = tostring(val)
            local matched = errStr:find(expectErr, 1, true) ~= nil
            record(label, matched, "threw: " .. errStr:sub(1, 80))
        elseif val == nil and type(err) == "string" then
            local matched = err:find(expectErr, 1, true) ~= nil
            record(label, matched, "err: " .. err)
        else
            record(label, false, "expected nil+error, got " .. tostring(val))
        end
    end

    -- transferSelf() validations
    local selfCases = {
        { "transferSelf: amount <= 0",
            function() return ccvault.transferSelf(0, "x") end,
            "amount must be positive" },
        { "transferSelf: empty reason",
            function() return ccvault.transferSelf(1, "") end,
            "reason is required" },
        { "transferSelf: reason too long",
            function() return ccvault.transferSelf(1, string.rep("B", MAX_REASON + 1)) end,
            "reason too long" },
    }

    for _, tc in ipairs(selfCases) do
        local label, fn, expectErr = tc[1], tc[2], tc[3]
        local ok, val, err = pcall(fn)
        if not ok then
            local errStr = tostring(val)
            local matched = errStr:find(expectErr, 1, true) ~= nil
            record(label, matched, "threw: " .. errStr:sub(1, 80))
        elseif val == nil and type(err) == "string" then
            local matched = err:find(expectErr, 1, true) ~= nil
            record(label, matched, "err: " .. err)
        else
            record(label, false, "expected nil+error, got " .. tostring(val))
        end
    end

    -- escrow() validations
    local escrowCases = {
        { "escrow: amount <= 0",
            function() return ccvault.escrow(0, "x") end,
            "amount must be positive" },
        { "escrow: empty reason",
            function() return ccvault.escrow(1, "") end,
            "reason is required" },
        { "escrow: reason too long",
            function() return ccvault.escrow(1, string.rep("C", MAX_REASON + 1)) end,
            "reason too long" },
    }

    for _, tc in ipairs(escrowCases) do
        local label, fn, expectErr = tc[1], tc[2], tc[3]
        local ok, val, err = pcall(fn)
        if not ok then
            local errStr = tostring(val)
            local matched = errStr:find(expectErr, 1, true) ~= nil
            record(label, matched, "threw: " .. errStr:sub(1, 80))
        elseif val == nil and type(err) == "string" then
            local matched = err:find(expectErr, 1, true) ~= nil
            record(label, matched, "err: " .. err)
        else
            record(label, false, "expected nil+error, got " .. tostring(val))
        end
    end

    -- resolveTarget invalid target
    local ok, val, err = pcall(function()
        return ccvault.getBalance("invalidtarget")
    end)
    if not ok then
        local errStr = tostring(val)
        record("getBalance: invalid target throws", errStr:find("invalid target") ~= nil,
            errStr:sub(1, 80))
    else
        record("getBalance: invalid target throws", false,
            "did not throw; got " .. tostring(val) .. ", " .. tostring(err))
    end
end

-- ============================================================
--  PHASE 5 — BALANCE READS
-- ============================================================

local function phase5_balance()
    banner("PHASE 5: Balance Reads")

    -- 5.1  getBalance("player")
    local ok, bal, err = safeCall(ccvault.getBalance, "player")
    if not ok then
        record("getBalance('player') call", false, tostring(bal))
    elseif bal ~= nil then
        record("getBalance('player') returns number", type(bal) == "number",
            "got " .. type(bal) .. "=" .. tostring(bal))
        record("getBalance('player') >= 0", bal >= 0,
            "got " .. tostring(bal))
        print("  Player balance: " .. tostring(bal))
    else
        record("getBalance('player') returned nil", false, "err=" .. tostring(err))
    end

    -- 5.2  getBalance("host")
    local ok2, hbal, herr = safeCall(ccvault.getBalance, "host")
    if not ok2 then
        record("getBalance('host') call", false, tostring(hbal))
    elseif hbal ~= nil then
        record("getBalance('host') returns number", type(hbal) == "number",
            "got " .. type(hbal) .. "=" .. tostring(hbal))
        record("getBalance('host') >= 0", hbal >= 0,
            "got " .. tostring(hbal))
        print("  Host balance: " .. tostring(hbal))
    else
        record("getBalance('host') returned nil", false,
            "err=" .. tostring(herr))
    end

    return bal, hbal
end

-- ============================================================
--  PHASE 6 — SELF-TRANSFER (same-account testing)
-- ============================================================

local function phase6_transferSelf(startBal)
    banner("PHASE 6: transferSelf (Test Mode)")

    local info = ccvault.getSessionInfo()
    if not info.isSelfPlay then
        colPrint(colors.yellow, "Not self-play (player ~= host). Skipping transferSelf.")
        record("transferSelf: self-play check", "skip", "player ~= host")

        -- Verify it errors correctly
        local ok, val, err = safeCall(ccvault.transferSelf, 1, "test")
        if not ok then
            local errStr = tostring(val)
            record("transferSelf: rejects non-self", errStr:find("same-person") ~= nil,
                errStr:sub(1, 80))
        elseif val == nil and type(err) == "string" then
            record("transferSelf: rejects non-self", err:find("same-person") ~= nil,
                "err=" .. err)
        else
            record("transferSelf: rejects non-self", false,
                "expected error, got " .. tostring(val))
        end
        return nil
    end

    -- Execute transferSelf (net-zero on balance)
    local amount = 1
    local ok, result, err = safeCall(ccvault.transferSelf, amount, "integration test")
    if not ok then
        record("transferSelf() call", false, tostring(result))
        return nil
    end

    if result == nil then
        record("transferSelf() returned result", false, "err=" .. tostring(err))
        return nil
    end

    record("transferSelf() returned result", true)
    record("transferSelf result.success == true", result.success == true,
        "got " .. tostring(result.success))
    record("transferSelf result.testMode == true", result.testMode == true,
        "got " .. tostring(result.testMode))
    record("transferSelf result.txId is string", type(result.txId) == "string",
        "got " .. type(result.txId))

    print("  TX ID: " .. tostring(result.txId))
    print("  Test mode: " .. tostring(result.testMode))

    -- Verify balance unchanged (self-transfer is net zero)
    local ok2, balAfter = safeCall(ccvault.getBalance, "player")
    if ok2 and type(balAfter) == "number" and type(startBal) == "number" then
        record("transferSelf balance unchanged", balAfter == startBal,
            "before=" .. startBal .. " after=" .. balAfter)
        print("  Balance after: " .. tostring(balAfter) .. " (was " .. tostring(startBal) .. ")")
    end

    return result.txId
end

-- ============================================================
--  PHASE 7 — TRANSACTION VERIFICATION
-- ============================================================

local function phase7_verify(txId)
    banner("PHASE 7: Transaction Verification")

    if txId == nil then
        colPrint(colors.yellow, "No txId from previous phase. Skipping.")
        record("verifyTransaction: skip", "skip", "no txId available")
        return
    end

    -- 7.1  verifyTransaction with valid ID
    local ok, tx = safeCall(ccvault.verifyTransaction, txId)
    if not ok then
        record("verifyTransaction() call", false, tostring(tx))
        return
    end

    if tx == nil then
        record("verifyTransaction() found tx", false, "returned nil for " .. txId)
        return
    end

    record("verifyTransaction() found tx", true)
    record("tx.txId matches", tx.txId == txId,
        "got " .. tostring(tx.txId) .. " expected " .. txId)
    record("tx.amount is number", type(tx.amount) == "number",
        "got " .. type(tx.amount))
    record("tx.reason is string", type(tx.reason) == "string",
        "got " .. type(tx.reason))
    record("tx.timestamp is string", type(tx.timestamp) == "string",
        "got " .. type(tx.timestamp))
    record("tx.computerId is number", type(tx.computerId) == "number",
        "got " .. type(tx.computerId))

    print("  Verified TX:")
    for k, v in pairs(tx) do
        print("    " .. tostring(k) .. " = " .. tostring(v))
    end

    -- 7.2  verifyTransaction with fake ID returns nil
    local ok2, fake = safeCall(ccvault.verifyTransaction, "nonexistent-tx-id-99999")
    if not ok2 then
        record("verifyTransaction fake returns nil", false, "threw: " .. tostring(fake))
    else
        record("verifyTransaction fake returns nil", fake == nil,
            "got " .. tostring(fake))
    end
end

-- ============================================================
--  PHASE 8 — TRANSACTION HISTORY
-- ============================================================

local function phase8_history()
    banner("PHASE 8: Transaction History")

    -- 8.1  getTransactionHistory(5)
    local ok, hist = safeCall(ccvault.getTransactionHistory, 5)
    if not ok then
        record("getTransactionHistory() call", false, tostring(hist))
        return
    end

    record("getTransactionHistory() returns table", type(hist) == "table",
        "got " .. type(hist))

    if type(hist) ~= "table" then return end

    -- Count entries
    local count = 0
    for _ in pairs(hist) do count = count + 1 end
    record("history has entries", count > 0,
        "count=" .. count)

    print("  History entries: " .. count)

    -- Check first entry structure
    local first = hist[1]
    if first ~= nil then
        record("history[1] is table", type(first) == "table",
            "got " .. type(first))
        if type(first) == "table" then
            local requiredFields = { "txId", "amount", "reason", "timestamp" }
            for _, field in ipairs(requiredFields) do
                record("history[1]." .. field .. " exists",
                    first[field] ~= nil,
                    "val=" .. tostring(first[field]))
            end
            print("  Latest TX: " .. tostring(first.txId))
            print("    amount=" .. tostring(first.amount)
                .. " reason=" .. tostring(first.reason))
        end
    end

    -- 8.2  getTransactionHistory(0) should default to 10 (clamped)
    local ok2, hist2 = safeCall(ccvault.getTransactionHistory, 0)
    if not ok2 then
        record("getTransactionHistory(0) call", false, tostring(hist2))
    else
        record("getTransactionHistory(0) returns table", type(hist2) == "table",
            "got " .. type(hist2))
    end
end

-- ============================================================
--  PHASE 9 — FULL ESCROW LIFECYCLE
-- ============================================================

local function phase9_escrow()
    banner("PHASE 9: Escrow Lifecycle")

    -- Check balance first
    local ok0, bal = safeCall(ccvault.getBalance, "player")
    if not ok0 or bal == nil then
        colPrint(colors.yellow, "Cannot read balance. Skipping escrow tests.")
        record("escrow: balance check", false, tostring(bal))
        return
    end

    if bal < 1 then
        colPrint(colors.yellow, "Insufficient balance (" .. bal .. "). Need at least 1.")
        record("escrow: balance >= 1", false, "bal=" .. bal)
        return
    end

    record("escrow: balance >= 1", true, "bal=" .. bal)

    -- 9.1  Create escrow
    local escrowAmt = 1
    local ok1, result, err1 = safeCall(ccvault.escrow, escrowAmt, "test escrow hold")
    if not ok1 then
        record("escrow() create call", false, tostring(result))
        return
    end
    if result == nil then
        record("escrow() create returned result", false, "err=" .. tostring(err1))
        return
    end

    record("escrow() create returned result", true)
    record("escrow result.success", result.success == true,
        "got " .. tostring(result.success))
    record("escrow result.escrowId is string", type(result.escrowId) == "string",
        "got " .. type(result.escrowId))
    record("escrow result.amount matches", result.amount == escrowAmt,
        "got " .. tostring(result.amount) .. " expected " .. escrowAmt)
    record("escrow result.timeoutSeconds is number", type(result.timeoutSeconds) == "number",
        "got " .. type(result.timeoutSeconds))

    local escrowId = result.escrowId
    print("  Escrow ID: " .. tostring(escrowId))
    print("  Amount: " .. tostring(result.amount))
    print("  Timeout: " .. tostring(result.timeoutSeconds) .. "s")

    -- 9.2  Verify balance decreased
    local ok2, balAfter = safeCall(ccvault.getBalance, "player")
    if ok2 and type(balAfter) == "number" then
        record("escrow deducted from balance", balAfter == bal - escrowAmt,
            "before=" .. bal .. " after=" .. balAfter .. " expected=" .. (bal - escrowAmt))
        print("  Balance: " .. bal .. " -> " .. balAfter)
    end

    -- 9.3  getEscrowInfo
    local ok3, einfo = safeCall(ccvault.getEscrowInfo, escrowId)
    if not ok3 then
        record("getEscrowInfo() call", false, tostring(einfo))
    elseif einfo == nil then
        record("getEscrowInfo() found hold", false, "returned nil")
    else
        record("getEscrowInfo() found hold", true)
        record("escrowInfo.escrowId matches", einfo.escrowId == escrowId,
            "got " .. tostring(einfo.escrowId))
        record("escrowInfo.amount matches", einfo.amount == escrowAmt,
            "got " .. tostring(einfo.amount))
        record("escrowInfo.status == 'HELD'", einfo.status == "HELD",
            "got " .. tostring(einfo.status))
        record("escrowInfo.timeRemaining is number", type(einfo.timeRemaining) == "number",
            "got " .. type(einfo.timeRemaining))
        record("escrowInfo.timeRemaining > 0", (einfo.timeRemaining or 0) > 0,
            "got " .. tostring(einfo.timeRemaining))
        record("escrowInfo.reason is string", type(einfo.reason) == "string",
            "got " .. type(einfo.reason))

        print("  Escrow info:")
        for k, v in pairs(einfo) do
            print("    " .. tostring(k) .. " = " .. tostring(v))
        end
    end

    -- 9.4  getEscrowInfo with fake ID returns nil
    local ok4, fake = safeCall(ccvault.getEscrowInfo, "fake-escrow-id-99999")
    if not ok4 then
        record("getEscrowInfo fake returns nil", false, "threw: " .. tostring(fake))
    else
        record("getEscrowInfo fake returns nil", fake == nil,
            "got " .. tostring(fake))
    end

    -- 9.5  Cancel the escrow (refund tokens)
    local ok5, cancelResult, cerr = safeCall(ccvault.cancelEscrow, escrowId, "test cancel")
    if not ok5 then
        record("cancelEscrow() call", false, tostring(cancelResult))
        return
    end
    if cancelResult == nil then
        record("cancelEscrow() returned result", false, "err=" .. tostring(cerr))
        return
    end

    record("cancelEscrow() returned result", true)
    record("cancelEscrow result.success", cancelResult.success == true,
        "got " .. tostring(cancelResult.success))
    record("cancelEscrow result.txId is string", type(cancelResult.txId) == "string",
        "got " .. type(cancelResult.txId))

    print("  Cancel TX: " .. tostring(cancelResult.txId))

    -- 9.6  Verify balance restored after cancel
    local ok6, balRestored = safeCall(ccvault.getBalance, "player")
    if ok6 and type(balRestored) == "number" then
        record("escrow cancel restored balance", balRestored == bal,
            "restored=" .. balRestored .. " original=" .. bal)
        print("  Balance restored: " .. tostring(balRestored))
    end

    -- 9.7  getEscrowInfo after cancel should return nil
    local ok7, stale = safeCall(ccvault.getEscrowInfo, escrowId)
    if not ok7 then
        record("escrowInfo after cancel is nil", false, "threw: " .. tostring(stale))
    else
        record("escrowInfo after cancel is nil", stale == nil,
            "got " .. tostring(stale))
    end
end

-- ============================================================
--  PHASE 10 — ESCROW RESOLVE (create + resolve to host/player)
-- ============================================================

local function phase10_escrow_resolve()
    banner("PHASE 10: Escrow Resolve")

    local ok0, bal = safeCall(ccvault.getBalance, "player")
    if not ok0 or bal == nil or bal < 1 then
        colPrint(colors.yellow, "Insufficient balance for resolve test. Skipping.")
        record("escrow resolve: balance check", "skip", "bal=" .. tostring(bal))
        return
    end

    local info = ccvault.getSessionInfo()
    local recipient = info.isSelfPlay and "player" or "host"

    -- 10.1  Create escrow
    local ok1, result, err1 = safeCall(ccvault.escrow, 1, "resolve test hold")
    if not ok1 or result == nil then
        record("escrow for resolve: create", false,
            tostring(result) .. " " .. tostring(err1))
        return
    end

    local escrowId = result.escrowId
    record("escrow for resolve: created", true, escrowId)
    print("  Created escrow: " .. escrowId)

    -- 10.2  Resolve it
    local ok2, rResult, rerr = safeCall(ccvault.resolveEscrow,
        escrowId, recipient, "test resolve payout")
    if not ok2 then
        record("resolveEscrow() call", false, tostring(rResult))
        return
    end
    if rResult == nil then
        record("resolveEscrow() returned result", false, "err=" .. tostring(rerr))
        return
    end

    record("resolveEscrow() returned result", true)
    record("resolveEscrow result.success", rResult.success == true,
        "got " .. tostring(rResult.success))
    record("resolveEscrow result.txId is string", type(rResult.txId) == "string",
        "got " .. type(rResult.txId))

    print("  Resolve TX: " .. tostring(rResult.txId))

    -- 10.3  For self-play, balance should be back to original (debit + credit same)
    if info.isSelfPlay then
        local ok3, balAfter = safeCall(ccvault.getBalance, "player")
        if ok3 and type(balAfter) == "number" then
            record("escrow resolve self-play balance unchanged", balAfter == bal,
                "before=" .. bal .. " after=" .. balAfter)
        end
    end

    -- 10.4  Escrow should be gone
    local ok4, stale = safeCall(ccvault.getEscrowInfo, escrowId)
    if not ok4 then
        record("escrowInfo after resolve is nil", false, "threw: " .. tostring(stale))
    else
        record("escrowInfo after resolve is nil", stale == nil,
            "got " .. tostring(stale))
    end
end

-- ============================================================
--  PHASE 11 — CROSS-ACCOUNT TRANSFER (if not self-play)
-- ============================================================

local function phase11_transfer()
    banner("PHASE 11: Cross-Account Transfer")

    local info = ccvault.getSessionInfo()

    if info.isSelfPlay then
        colPrint(colors.yellow, "Self-play mode: transfer() will fail with 'same account'.")
        -- Verify it fails correctly
        local ok, val, err = safeCall(ccvault.transfer, "player", "host", 1, "self-play test")
        if not ok then
            local errStr = tostring(val)
            record("transfer self-play rejected", errStr:find("same account") ~= nil,
                errStr:sub(1, 80))
        elseif val == nil and type(err) == "string" then
            record("transfer self-play rejected", err:find("same account") ~= nil,
                "err=" .. err)
        else
            record("transfer self-play rejected", false,
                "expected error, got " .. tostring(val))
        end
        return
    end

    -- Not self-play — try a real transfer
    local ok0, bal = safeCall(ccvault.getBalance, "player")
    if not ok0 or bal == nil or bal < 2 then
        colPrint(colors.yellow, "Need at least 2 tokens. Skipping real transfer.")
        record("transfer: balance check", "skip", "bal=" .. tostring(bal))
        return
    end

    -- transfer player -> host
    local ok1, result, err1 = safeCall(ccvault.transfer, "player", "host", 1, "test xfer p2h")
    if not ok1 then
        record("transfer player->host call", false, tostring(result))
        return
    end
    if result == nil then
        record("transfer player->host result", false, "err=" .. tostring(err1))
        return
    end

    record("transfer player->host success", result.success == true,
        "got " .. tostring(result.success))
    record("transfer player->host txId", type(result.txId) == "string",
        "got " .. type(result.txId))
    print("  P->H TX: " .. tostring(result.txId))

    -- transfer host -> player (reverse it)
    local ok2, result2, err2 = safeCall(ccvault.transfer, "host", "player", 1, "test xfer h2p")
    if not ok2 then
        record("transfer host->player call", false, tostring(result2))
        return
    end
    if result2 == nil then
        record("transfer host->player result", false, "err=" .. tostring(err2))
        return
    end

    record("transfer host->player success", result2.success == true,
        "got " .. tostring(result2.success))
    print("  H->P TX: " .. tostring(result2.txId))

    -- Verify balance restored
    local ok3, balAfter = safeCall(ccvault.getBalance, "player")
    if ok3 and type(balAfter) == "number" then
        record("transfer round-trip balance unchanged", balAfter == bal,
            "before=" .. bal .. " after=" .. balAfter)
    end
end

-- ============================================================
--  PHASE 12 — RATE LIMIT INFO
-- ============================================================

local function phase12_ratelimit()
    banner("PHASE 12: Rate Limit Info")

    local ok, info = safeCall(ccvault.getSessionInfo)
    if not ok or type(info) ~= "table" then
        record("rate limit: getSessionInfo", false, tostring(info))
        return
    end

    record("transfersRemaining is number",
        type(info.transfersRemaining) == "number",
        "got " .. type(info.transfersRemaining))
    record("terminalTransfersRemaining is number",
        type(info.terminalTransfersRemaining) == "number",
        "got " .. type(info.terminalTransfersRemaining))
    record("playerTransfersRemaining is number",
        type(info.playerTransfersRemaining) == "number",
        "got " .. type(info.playerTransfersRemaining))

    print("  Transfers remaining (min):     " .. tostring(info.transfersRemaining))
    print("  Terminal transfers remaining:   " .. tostring(info.terminalTransfersRemaining))
    print("  Player transfers remaining:     " .. tostring(info.playerTransfersRemaining))

    record("transfersRemaining >= 0", (info.transfersRemaining or -1) >= 0,
        tostring(info.transfersRemaining))
    record("transfersRemaining <= min(terminal, player)",
        info.transfersRemaining <= math.min(
            info.terminalTransfersRemaining or 0,
            info.playerTransfersRemaining or 0),
        tostring(info.transfersRemaining) .. " <= min("
            .. tostring(info.terminalTransfersRemaining) .. ", "
            .. tostring(info.playerTransfersRemaining) .. ")")
end

-- ============================================================
--  SUMMARY
-- ============================================================

local function printSummary()
    banner("TEST RESULTS")

    for _, r in ipairs(results) do
        printResult(r.name, r.passed, r.detail)
    end

    hr()
    local total = passCount + failCount + skipCount
    local summary = string.format(
        "Total: %d  |  PASS: %d  |  FAIL: %d  |  SKIP: %d",
        total, passCount, failCount, skipCount)

    if failCount == 0 then
        colPrint(colors.green, summary)
    else
        colPrint(colors.red, summary)
    end

    -- Write log
    log("")
    log("=== SUMMARY ===")
    log(summary)
    for _, r in ipairs(results) do
        local tag = r.passed == true and "PASS" or (r.passed == false and "FAIL" or "SKIP")
        log(tag .. "  " .. r.name .. "  " .. r.detail)
    end
    flushLog()
    print("")
    print("Full log: " .. LOG_FILE)
end

-- ============================================================
--  MAIN
-- ============================================================

local function main()
    term.clear()
    term.setCursorPos(1, 1)
    banner("CCVault API Integration Test")
    print("This script tests every ccvault API method against")
    print("the real vhcctweaks mod. Reference: CCVaultAPI.java")
    print("")

    -- Phase 0: Global check (abort if ccvault missing)
    if not phase0_global() then
        printSummary()
        return
    end

    -- Phase 1: Pre-auth methods
    phase1_preauth()

    -- Phase 2: Auth-required errors
    phase2_noauth_errors()

    -- Phase 3: Authentication
    local authed = phase3_authenticate()

    if not authed then
        colPrint(colors.red, "Authentication failed. Skipping financial tests.")
        printSummary()
        return
    end

    -- Phases 4-12 require authentication
    phase4_validation()

    local playerBal = phase5_balance()

    local txId = phase6_transferSelf(playerBal)

    phase7_verify(txId)

    phase8_history()

    phase9_escrow()

    phase10_escrow_resolve()

    phase11_transfer()

    phase12_ratelimit()

    printSummary()
end

-- Top-level error handler so crashes get logged
local ok, err = pcall(main)
if not ok then
    local errMsg = "[" .. os.epoch("local") .. "] CRASH: " .. tostring(err)
    print("")
    print(errMsg)
    logLines[#logLines + 1] = errMsg
    flushLog()

    local ef = fs.open("ccvault_test_error.log", "a")
    if ef then
        ef.writeLine(errMsg)
        ef.close()
    end
end
