local constants = require("lib.vaultgear.constants")

local M = {}

local logPath = constants.LOG_FILE

function M.configure(path)
  if type(path) == "string" and path ~= "" then
    logPath = path
  end
end

function M.write(level, message)
  local handle = fs.open(logPath, "a")
  if not handle then
    return false
  end

  handle.writeLine("[" .. os.epoch("local") .. "] [" .. tostring(level or "INFO") .. "] " .. tostring(message))
  handle.close()
  return true
end

function M.info(message)
  return M.write("INFO", message)
end

function M.error(message)
  return M.write("ERROR", message)
end

return M
