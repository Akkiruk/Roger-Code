local storage = {}

local function ensureParent(path)
  local parent = fs.getDir(path)
  if parent and parent ~= "" and not fs.exists(parent) then
    fs.makeDir(parent)
  end
end

function storage.load(path, defaultValue)
  if not fs.exists(path) then
    return defaultValue
  end

  local handle = fs.open(path, "r")
  if not handle then
    return defaultValue
  end

  local raw = handle.readAll()
  handle.close()

  local ok, value = pcall(textutils.unserialize, raw)
  if ok and value ~= nil then
    return value
  end

  return defaultValue
end

function storage.save(path, value)
  ensureParent(path)

  local handle = fs.open(path, "w")
  if not handle then
    return false
  end

  handle.write(textutils.serialize(value))
  handle.close()
  return true
end

return storage
