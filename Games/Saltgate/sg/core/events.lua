-- core/events.lua
-- The event bus: how SALTGATE's parts talk without reaching into each other. Pure.
--
--   local bus = events.new()
--   local token = bus:on("crime", function(data) ... end, "my_plugin")
--   bus:emit("crime", { kind = "carjack", level = 1 })
--   bus:off(token)        bus:offOwner("my_plugin")
--
-- Handlers run in the order they were added. A handler may add or remove handlers; the change counts from the next
-- emit. Every event name used anywhere is listed in M.NAMES with the fields it carries: emitting an unlisted name is an
-- error, so a typo fails a test instead of going quiet.

local M = {}
local Bus = {}
Bus.__index = Bus

-- name = what its data table holds
M.NAMES = {
  -- the player
  vehicle_enter = "vehicle (entity or car table), stolen (bool)",
  vehicle_exit = "vehicle",
  district_enter = "district (gilt|lantern|cinder|brine|mid|...), previous",
  player_hurt = "amount, by (string)",
  player_down = "kind ('nabbed'|'ko')",
  respawn = "place (name)",
  -- money and things
  money = "amount (signed), reason (string), total",
  pickup = "kind, id, value",
  -- the law
  crime = "kind (string), level (levels added)",
  heat_changed = "level, previous",
  -- story and progress
  mission_start = "id",
  mission_end = "id, result ('pass'|'fail'), reason",
  checkpoint = "id, name",
  choice = "id, key, pick",
  achievement = "id",
  jump = "id, distance, landed (bool)",
  -- the world
  time_of_day = "hour (0-24, fractional), phase ('dawn'|'day'|'dusk'|'night')",
  weather = "kind ('clear'|'overcast'|'rain'|'fog'|'storm'), previous",
  chunk_loaded = "cx, cz, lod",
  chunk_unloaded = "cx, cz",
  interior_enter = "id",
  interior_exit = "id",
  -- the app
  screen_push = "name",
  screen_pop = "name",
  save = "data (the v2 save about to be written; sections may add to it)",
  load = "data (the v2 save just read)",
  quality = "level (0 best .. 3 lightest), previous",
}

function M.new(opts)
  opts = opts or {}
  return setmetatable({ handlers = {}, nextToken = 0, strict = opts.strict ~= false }, Bus)
end

--- Listen for name. owner (a plugin name) lets offOwner drop them all at once. Returns a token for off.
function Bus:on(name, fn, owner)
  if self.strict and not M.NAMES[name] then error("unknown event '" .. tostring(name) .. "' (add it to events.NAMES)", 2) end
  if type(fn) ~= "function" then error("events:on needs a function for '" .. tostring(name) .. "'", 2) end
  self.nextToken = self.nextToken + 1
  local list = self.handlers[name]
  if not list then
    list = {}
    self.handlers[name] = list
  end
  list[#list + 1] = { fn = fn, owner = owner, token = self.nextToken }
  return self.nextToken
end

function Bus:off(token)
  for _, list in pairs(self.handlers) do
    for i = #list, 1, -1 do
      if list[i].token == token then table.remove(list, i) return true end
    end
  end
  return false
end

function Bus:offOwner(owner)
  local n = 0
  for _, list in pairs(self.handlers) do
    for i = #list, 1, -1 do
      if list[i].owner == owner then
        table.remove(list, i)
        n = n + 1
      end
    end
  end
  return n
end

--- Tell everyone listening. Returns how many handlers ran.
function Bus:emit(name, data)
  if self.strict and not M.NAMES[name] then error("unknown event '" .. tostring(name) .. "' (add it to events.NAMES)", 2) end
  local list = self.handlers[name]
  if not list then return 0 end
  local snapshot = {}
  for i = 1, #list do snapshot[i] = list[i].fn end
  for i = 1, #snapshot do snapshot[i](data or {}) end
  return #snapshot
end

return M
