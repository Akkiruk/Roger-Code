local M = {}

local function ensureParent(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

function M.load(path, defaultValue)
  assert(type(path) == "string", "path must be a string")

  if not fs.exists(path) then
    return defaultValue
  end

  local handle = fs.open(path, "r")
  if not handle then
    return defaultValue, "open_failed"
  end

  local contents = handle.readAll()
  handle.close()

  local decoded = textutils.unserialize(contents)
  if decoded == nil then
    return defaultValue, "decode_failed"
  end

  return decoded
end

function M.save(path, value)
  assert(type(path) == "string", "path must be a string")

  local serialized = textutils.serialize(value)
  if not serialized then
    return false, "serialize_failed"
  end

  ensureParent(path)

  local tempPath = path .. ".tmp"
  local backupPath = path .. ".bak"
  local handle = fs.open(tempPath, "w")

  if not handle then
    return false, "open_failed"
  end

  handle.write(serialized)
  handle.close()

  if fs.exists(backupPath) then
    fs.delete(backupPath)
  end

  if fs.exists(path) then
    fs.move(path, backupPath)
  end

  fs.move(tempPath, path)
  return true
end

function M.delete(path)
  assert(type(path) == "string", "path must be a string")

  local suffixes = { "", ".tmp", ".bak" }
  local deleted = false
  local index = 1

  while suffixes[index] do
    local target = path .. suffixes[index]
    if fs.exists(target) then
      fs.delete(target)
      deleted = true
    end
    index = index + 1
  end

  return deleted
end

return M