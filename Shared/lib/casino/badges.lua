-- badges.lua
-- Badges, and what a player's card needs that the stats do not keep: wins, losses, the streak and the last dozen rounds.
-- Each table keeps its own file, beside the stats, written the way the journal writes. The stats stay the record of tokens.
--
-- A game adds its own with game.badges: id -> { name, text, test = function(result, player, round) }.
--   result  rules.result(state): kind, title, detail
--   player  a copy of what the card shows, after this round: rounds, net, best, wins, losses, pushes, streak, form
--   round   the round: net, stake, state. Read it and nothing else
-- A test that errors earns nothing and is logged, and the other tests still run.
--
-- A badge comes after the money and never reaches it: nothing here touches a token, and Table:awardBadges catches anything
-- that goes wrong in here, so a round always finishes. A badge is granted once, and the round's tag lands in the same write
-- as the grant, so a round finished again after a reboot adds nothing.
--
-- "Beat the house at every game" takes more than one table knows, so the hub decides it from the rounds every table already
-- sends, and says who has done it in its state. M.hear puts that on this table's card. Only the table that played the winning
-- round whispers it, so a player hears it once however many tables there are.
--
-- A whisper waits for M.sayAll, because a badge is earned when the money moves, before the reveal, and the whisper would give
-- the result away. See Table:badgeNews. With no chat box it stays untold, so one added later still gets to say it.

local chat = require("lib.casino.chat")
local journal = require("lib.casino.journal")
local stats = require("lib.casino.stats")

local M = {}

M.FORM_KEPT = 12       -- rounds on a player's card
M.BIG_WIN_TIMES = 10   -- a big win: this many times the stake. The table's lamp goes by this too
M.RUN = 5
M.REGULAR = 25
M.FLOOR = "floor"

local FILE = "casino_badges.dat"
local DAMAGED_FILE = "casino_badges_damaged.dat"
local SEEN_KEPT = 24   -- rounds remembered, so one replayed after a reboot is not counted twice

local COMMON = {
  { id = "first_win", name = "First Win", text = "Win a round",
    test = function(_, _, round) return round.net > 0 end },
  { id = "five_running", name = "Five Running", text = "Win " .. M.RUN .. " rounds in a row",
    test = function(_, player) return player.streak >= M.RUN end },
  { id = "regular", name = "Regular", text = "Play " .. M.REGULAR .. " rounds here",
    test = function(_, player) return player.rounds >= M.REGULAR end },
  { id = "big_win", name = "Big Win", text = "Win " .. M.BIG_WIN_TIMES .. " times your stake",
    test = function(result, _, round) return result.kind == "win" and round.net >= round.stake * M.BIG_WIN_TIMES end },
}

local FLOOR_BADGE = { id = M.FLOOR, name = "Beat The House", text = "Get ahead at every house game" }

local function load()
  local value = journal.load(FILE)
  if type(value) == "table" and type(value.players) == "table" then return value end
  if fs.exists(FILE) and not fs.exists(DAMAGED_FILE) then pcall(fs.copy, FILE, DAMAGED_FILE) end
  return { players = {} }
end

local function save(data)
  return journal.save(FILE, data)
end

local function entry(data, name)
  local player = data.players[name] or { wins = 0, losses = 0, pushes = 0, streak = 0, form = "", have = {}, untold = {} }
  data.players[name] = player
  return player
end

--- Whether this tag has been counted, and if not, note it.
local function firstTime(data, tag)
  data.seen = data.seen or {}
  for _, seen in ipairs(data.seen) do
    if seen == tag then return false end
  end
  table.insert(data.seen, tag)
  while #data.seen > SEEN_KEPT do table.remove(data.seen, 1) end
  return true
end

--- A push is neither: it does not end a streak or add to one.
local function count(player, net)
  local mark = net > 0 and "W" or net < 0 and "L" or "P"
  if mark == "W" then
    player.wins = player.wins + 1
    player.streak = math.max(player.streak, 0) + 1
  elseif mark == "L" then
    player.losses = player.losses + 1
    player.streak = math.min(player.streak, 0) - 1
  else
    player.pushes = player.pushes + 1
  end
  player.form = (player.form .. mark):sub(-M.FORM_KEPT)
end

--- The table's record and this file's, as one, for a test or the card. Nothing that reads it can change either.
local function joined(name, player)
  local record = stats.player(name)
  return { rounds = record.rounds, wagered = record.wagered, net = record.net, best = record.best,
    wins = player.wins, losses = player.losses, pushes = player.pushes, streak = player.streak, form = player.form }
end

--- Every badge this game offers, in the order the card shows them: the common ones, its own by id, then the floor's.
function M.list(game)
  local list = {}
  local taken = {}
  for _, def in ipairs(COMMON) do
    list[#list + 1] = def
    taken[def.id] = true
  end
  local own = {}
  for id in pairs(type(game.badges) == "table" and game.badges or {}) do
    if not taken[id] and id ~= M.FLOOR then own[#own + 1] = id end
  end
  table.sort(own)
  for _, id in ipairs(own) do
    local def = game.badges[id]
    list[#list + 1] = { id = id, name = def.name, text = def.text, test = def.test }
  end
  list[#list + 1] = FLOOR_BADGE
  return list
end

local function earned(def, result, player, round)
  if type(def.test) ~= "function" then return false end
  local ok, value = pcall(def.test, result, player, round)
  if ok then return value and true or false end
  journal.log("badge " .. def.id .. " failed: " .. tostring(value))
  return false
end

--- Count a finished round and grant what it earned. The same round again changes nothing.
-- Only for a round with a bet that stood. stats.record comes first, so a test sees this round in the totals.
-- @return table|nil  the names of the badges it unlocked, or nil if it changed nothing
function M.award(game, round, result)
  local data = load()
  if not firstTime(data, round.id) then return nil end
  local player = entry(data, round.player)
  count(player, round.net)
  local seen = joined(round.player, player)
  local names = {}
  for _, def in ipairs(M.list(game)) do
    if not player.have[def.id] and earned(def, result, seen, round) then
      player.have[def.id] = os.epoch("utc")
      player.untold[#player.untold + 1] = def.id
      names[#names + 1] = def.name
    end
  end
  if not save(data) then return nil end
  return names
end

--- Take in who the hub says has beaten every game. Returns how many were new here.
-- @param champions table|nil  { { name, at, by } }, by being the computer that played the winning round
function M.hear(champions)
  if type(champions) ~= "table" or #champions == 0 then return 0 end
  local data = load()
  local fresh = 0
  for _, champion in ipairs(champions) do
    local player = entry(data, champion.name)
    if not player.have[M.FLOOR] then
      player.have[M.FLOOR] = champion.at
      if champion.by == os.getComputerID() then player.untold[#player.untold + 1] = M.FLOOR end
      fresh = fresh + 1
    end
  end
  -- Most of the time nobody is new, and this runs every few seconds
  if fresh > 0 then save(data) end
  return fresh
end

--- "Badge at HI-LO: First Win". Inside chat.LINE, which Tests/badges_test.lua holds every game to.
function M.whisper(game, id)
  local name = id
  for _, def in ipairs(M.list(game)) do
    if def.id == id then name = def.name end
  end
  return ("Badge at %s: %s"):format(game.title, name)
end

--- Whisper every badge nobody has been told of. Each is noted before it is said, so none can be said twice.
function M.sayAll(game)
  if not chat.available() then return 0 end
  local data = load()
  local said = {}
  for name, player in pairs(data.players) do
    for _, id in ipairs(player.untold) do said[#said + 1] = { name = name, text = M.whisper(game, id) } end
    player.untold = {}
  end
  if #said == 0 or not save(data) then return 0 end
  for _, line in ipairs(said) do chat.tell(line.name, line.text) end
  return #said
end

--- What a player's card shows. Nothing here writes.
function M.player(name)
  local player = entry(load(), name)
  local shown = joined(name, player)
  shown.have = player.have
  return shown
end

--- Rounds running: positive for wins, negative for losses.
function M.streak(name)
  local player = load().players[name]
  return player and player.streak or 0
end

return M
