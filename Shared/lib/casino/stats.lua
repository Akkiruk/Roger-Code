-- stats.lua
-- Each table's own record of its players, kept on disk. The hub keeps the casino-wide version.

local M = {}

local FILE = "casino_stats.dat"

local function load()
  if fs.exists(FILE) then
    local handle = fs.open(FILE, "r")
    if handle then
      local value = textutils.unserialize(handle.readAll() or "")
      handle.close()
      if type(value) == "table" then return value end
    end
  end
  return { players = {}, total = { rounds = 0, wagered = 0, net = 0 } }
end

local function save(data)
  local handle = fs.open(FILE, "w")
  if handle then
    handle.write(textutils.serialize(data, { compact = true }))
    handle.close()
  end
end

function M.record(name, wagered, net)
  local data = load()
  local player = data.players[name] or { rounds = 0, wagered = 0, net = 0, best = 0 }
  player.rounds = player.rounds + 1
  player.wagered = player.wagered + wagered
  player.net = player.net + net
  player.best = math.max(player.best, net)
  data.players[name] = player
  data.total.rounds = data.total.rounds + 1
  data.total.wagered = data.total.wagered + wagered
  data.total.net = data.total.net + net
  save(data)
  return player
end

function M.player(name)
  return load().players[name] or { rounds = 0, wagered = 0, net = 0, best = 0 }
end

--- The top players by net winnings at this table.
function M.leaders(limit)
  local list = {}
  for name, player in pairs(load().players) do
    list[#list + 1] = { name = name, net = player.net, best = player.best, rounds = player.rounds }
  end
  table.sort(list, function(a, b) return a.net > b.net end)
  while #list > (limit or 5) do table.remove(list) end
  return list
end

return M
