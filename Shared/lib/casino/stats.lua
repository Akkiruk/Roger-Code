-- stats.lua
-- Each table's own record of its players, kept on disk. The hub keeps the casino-wide version.
-- Written the way the journal writes, so a reboot mid-write cannot lose the record. A file that cannot be read at all is
-- set aside before anything replaces it.

local journal = require("lib.casino.journal")

local M = {}

local FILE = "casino_stats.dat"
local DAMAGED_FILE = "casino_stats_damaged.dat"
local SEEN_KEPT = 24   -- rounds remembered, so one replayed after a reboot is not counted twice
local SITTING_GAP_MS = 5 * 60000 -- a player's rounds closer than this are one sitting, timed from round to round
local FIRST_ROUND_MS = 60000     -- and a sitting's first round counts as this long

local function load()
  local value = journal.load(FILE)
  if type(value) == "table" and type(value.players) == "table" and type(value.total) == "table" then return value end
  if fs.exists(FILE) and not fs.exists(DAMAGED_FILE) then pcall(fs.copy, FILE, DAMAGED_FILE) end
  return { players = {}, total = { rounds = 0, wagered = 0, net = 0 } }
end

local function save(data)
  return journal.save(FILE, data)
end

--- Whether this tag has been recorded, and if not, note it.
local function firstTime(data, tag)
  if not tag then return true end
  data.seen = data.seen or {}
  for _, seen in ipairs(data.seen) do
    if seen == tag then return false end
  end
  table.insert(data.seen, tag)
  while #data.seen > SEEN_KEPT do table.remove(data.seen, 1) end
  return true
end

--- Add a round to a player's record. A tag makes this safe to repeat: the note and the record land in one write.
function M.record(name, wagered, net, tag)
  local data = load()
  if not firstTime(data, tag) then return nil end
  local player = data.players[name] or { rounds = 0, wagered = 0, net = 0, best = 0 }
  player.rounds = player.rounds + 1
  player.wagered = player.wagered + wagered
  player.net = player.net + net
  player.best = math.max(player.best, net)
  -- time at the table, for the play tracker: a round adds the gap since the last, or a minute to start a new sitting
  local at = os.epoch("utc")
  local gap = player.last and at - player.last
  if not gap or gap < 0 or gap > SITTING_GAP_MS then
    player.sessions = (player.sessions or 0) + 1
    player.ms = (player.ms or 0) + FIRST_ROUND_MS
  else
    player.ms = (player.ms or 0) + gap
  end
  player.last = at
  data.players[name] = player
  data.total.rounds = data.total.rounds + 1
  data.total.wagered = data.total.wagered + wagered
  data.total.net = data.total.net + net
  save(data)
  return player
end

--- Every player's record at this table, for a play tracker.
function M.all()
  return load().players
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
