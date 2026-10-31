-- arcade_replay.lua
-- The last few finished matches of each game, kept to watch again. A match is its seed and actions, the same thing the
-- journal holds, so the rules rebuild it exactly.

local config = require("lib.arcade.constants")

local M = {}

local function path(id) return "arcade_replays_" .. id .. ".dat" end

function M.list(id)
  local file = path(id)
  if not fs.exists(file) then return {} end
  local h = fs.open(file, "r")
  if not h then return {} end
  local ok, value = pcall(textutils.unserialise, h.readAll() or "")
  h.close()
  if ok and type(value) == "table" then return value end
  return {}
end

--- Keep a finished match, dropping the oldest.
function M.add(id, entry)
  local list = M.list(id)
  list[#list + 1] = entry
  while #list > config.REPLAYS_KEPT do table.remove(list, 1) end
  local file = path(id)
  local h = fs.open(file .. ".tmp", "w")
  if not h then return end
  h.write(textutils.serialise(list))
  h.close()
  if fs.exists(file) then fs.delete(file) end
  fs.move(file .. ".tmp", file)
end

--- The longest match kept, which is usually the closest one.
function M.best(id)
  local best
  for _, entry in ipairs(M.list(id)) do
    if not best or #entry.actions >= #best.actions then best = entry end
  end
  return best
end

return M
