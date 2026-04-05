local M = {}

local function appendLine(path, message)
  assert(type(path) == "string", "path must be a string")

  local handle = fs.open(path, "a")
  if not handle then
    return false
  end

  handle.writeLine("[" .. os.epoch("local") .. "] " .. tostring(message))
  handle.close()
  return true
end

function M.write(path, message)
  return appendLine(path, message)
end

function M.new(path, echoToTerminal)
  assert(type(path) == "string", "path must be a string")

  local logger = {}

  logger.file = path

  logger.write = function(message)
    appendLine(path, message)
    if echoToTerminal then
      print(tostring(message))
    end
  end

  return logger
end

return M