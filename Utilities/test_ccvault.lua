-- test_ccvault.lua — quick diagnostic for the ccvault API
local log = {}
local function L(msg)
  local line = "[" .. os.epoch("local") .. "] " .. tostring(msg)
  log[#log + 1] = line
  print(line)
end

L("=== ccvault diagnostic ===")

-- 1. Does the global exist?
L("ccvault type: " .. type(ccvault))

if type(ccvault) ~= "table" then
  L("FATAL: ccvault global is not a table — API not loaded")
else
  -- 2. List every key in the table
  L("--- ccvault keys ---")
  for k, v in pairs(ccvault) do
    L("  " .. tostring(k) .. " = " .. type(v))
  end

  -- 3. isAvailable
  L("--- isAvailable ---")
  local okA, resA = pcall(function() return ccvault.isAvailable() end)
  L("pcall ok: " .. tostring(okA) .. "  result: " .. tostring(resA))

  -- 4. isAuthenticated
  L("--- isAuthenticated ---")
  local okB, resB = pcall(function() return ccvault.isAuthenticated() end)
  L("pcall ok: " .. tostring(okB) .. "  result: " .. tostring(resB))

  -- 5. getPlayerName
  L("--- getPlayerName ---")
  local okC, resC = pcall(function() return ccvault.getPlayerName() end)
  L("pcall ok: " .. tostring(okC) .. "  result: " .. tostring(resC))

  -- 6. getHostName
  L("--- getHostName ---")
  local okD, resD = pcall(function() return ccvault.getHostName() end)
  L("pcall ok: " .. tostring(okD) .. "  result: " .. tostring(resD))

  -- 7. getComputerId
  L("--- getComputerId ---")
  local okE, resE = pcall(function() return ccvault.getComputerId() end)
  L("pcall ok: " .. tostring(okE) .. "  result: " .. tostring(resE))

  -- 8. getSessionInfo
  if type(ccvault.getSessionInfo) == "function" then
    L("--- getSessionInfo ---")
    local okF, resF = pcall(function() return ccvault.getSessionInfo() end)
    L("pcall ok: " .. tostring(okF) .. "  result type: " .. type(resF))
    if type(resF) == "table" then
      for k, v in pairs(resF) do
        L("  session." .. tostring(k) .. " = " .. tostring(v))
      end
    else
      L("  value: " .. tostring(resF))
    end
  else
    L("getSessionInfo: not a function (" .. type(ccvault.getSessionInfo) .. ")")
  end

  -- 9. requestAuth (only if not already authenticated)
  if okB and resB == true then
    L("Already authenticated — skipping requestAuth")
  else
    L("--- requestAuth ---")
    local okG, resG, errG = pcall(function() return ccvault.requestAuth() end)
    L("pcall ok: " .. tostring(okG) .. "  result: " .. tostring(resG) .. "  err: " .. tostring(errG))
  end
end

-- Also check vhcc (file API)
L("")
L("=== vhcc diagnostic ===")
L("vhcc type: " .. type(vhcc))
if type(vhcc) == "table" then
  for k, v in pairs(vhcc) do
    L("  " .. tostring(k) .. " = " .. type(v))
  end
end

-- Write log to file
L("")
L("=== done ===")
local h = fs.open("ccvault_test.log", "w")
if h then
  for _, line in ipairs(log) do
    h.writeLine(line)
  end
  h.close()
  print("Log written to ccvault_test.log")
else
  print("ERROR: could not open log file")
end
