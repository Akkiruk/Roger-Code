-- casino_hub_contest.lua
-- Tournaments, as the hub sees them. Pure: no screen, no rednet, no wallet. No tokens move in a contest, and nothing here or at
-- a table can make them. The owner starts one from the wall. Every table of that game then offers it, each player gets the same
-- chips, and the best chips when it ends wins.
--
-- One entry for each player in each contest: one stack, at the table that first reported it. A report counts only if it comes
-- from that table and is further on than the last one, so a repeat, a replay of a better moment and a second table are all
-- turned away, and a final report ends the entry for good. There is no signing, so a forged report can fake a leaderboard
-- line, which is accepted: it is a line on a wall, and no tokens hang on it.
--
-- The book, data.contest: { live = a contest or nil, past = finished ones, newest first }.
-- A contest: { id, game, chips, minutes, by, ends, entries = name -> { chips, rounds, table, final } }.

local M = {
  CHIPS = 1000,           -- what every player starts with
  LENGTHS = { 15, 30, 60 },  -- minutes the owner can choose from
  GRACE_MS = 60000,       -- how long after the end a score still counts, for rounds that were playing (tournament.lua too)
  FINAL_SHOW_MS = 600000, -- the final standings stay up this long, and then the page lists past winners
  MAX_CHIPS = 1e9,        -- no stack can honestly be this big (net.lua has the same figure)
  MAX_ROUNDS = 1e6,
  MAX_NAME = 32,
  MAX_ENTRIES = 64,       -- a flood of forged names cannot grow the save past this
  BOARD = 32,             -- rows every table hears (net.lua's limit)
  TOP = 8,                -- rows on the wall, and kept for a finished contest
  PAST_KEPT = 8,
  WHISPERED = 3,
}

-- House tables only: PokerTable has no house and no engine round to play
M.GAMES = { "baccarat", "blackjack", "crazyeights", "hilo", "horse-racing", "roulette", "slots", "three-card-poker",
  "ultimate-holdem", "videopoker" }

local function isNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isName(value)
  return type(value) == "string" and value ~= "" and #value <= M.MAX_NAME
end

local function isId(value)
  return isName(value) or isNumber(value)
end

local function isCount(value, limit)
  return isNumber(value) and value >= 0 and value <= limit and value == math.floor(value)
end

local function listed(list, value)
  for _, item in ipairs(list) do
    if item == value then return true end
  end
  return false
end

function M.new()
  return { past = {} }
end

--- Whether scores can still be earned: the clock has not run out.
function M.running(contest, at)
  return contest ~= nil and at < contest.ends
end

--- Start a contest. Only one runs at a time. Returns it, or nil.
function M.start(book, game, minutes, by, at)
  if book.live or not listed(M.GAMES, game) or not listed(M.LENGTHS, minutes) then return nil end
  book.live = { id = ("%x"):format(at % 268435456), game = game, chips = M.CHIPS, minutes = minutes, by = by,
    ends = at + minutes * 60000, entries = {} }
  return book.live
end

--- End the clock now. Rounds already playing still get the grace.
function M.stop(book, at)
  if not M.running(book.live, at) then return false end
  book.live.ends = at
  return true
end

--- The players in order, best chips first. Fewer rounds to get there wins a tie.
function M.standings(contest, limit)
  local list = {}
  for name, entry in pairs(contest.entries) do
    list[#list + 1] = { name = name, chips = entry.chips, rounds = entry.rounds, table = entry.table, final = entry.final }
  end
  table.sort(list, function(a, b)
    if a.chips ~= b.chips then return a.chips > b.chips end
    if a.rounds ~= b.rounds then return a.rounds < b.rounds end
    return a.name < b.name
  end)
  while limit and #list > limit do table.remove(list) end
  return list
end

--- A flood must not grow the save, and must not shut anyone out: a better stack takes the worst one's place.
local function room(contest, chips)
  local list = M.standings(contest)
  if #list < M.MAX_ENTRIES then return true end
  local worst = list[#list]
  if chips <= worst.chips then return false end
  contest.entries[worst.name] = nil
  return true
end

--- A table's report. Returns whether it changed anything.
function M.score(book, sender, message, at)
  local contest = book.live
  if not contest or at >= contest.ends + M.GRACE_MS then return false end
  if message.contest ~= contest.id or message.game ~= contest.game or not isId(sender) then return false end
  local name, chips, rounds = message.player, message.chips, message.rounds
  if not isName(name) or not isCount(chips, M.MAX_CHIPS) or not isCount(rounds, M.MAX_ROUNDS) or rounds < 1 then return false end
  if message.final ~= nil and type(message.final) ~= "boolean" then return false end

  local entry = contest.entries[name]
  if entry then
    if entry.table ~= sender or entry.final or rounds <= entry.rounds then return false end
  elseif not room(contest, chips) then
    return false
  end
  contest.entries[name] = { chips = chips, rounds = rounds, table = sender, final = message.final == true or nil }
  return true
end

--- Close a contest whose grace is over. Returns what goes on the books, or nil. A contest nobody played leaves nothing.
function M.tick(book, at)
  local contest = book.live
  if not contest or at < contest.ends + M.GRACE_MS then return nil end
  book.live = nil
  local top = M.standings(contest, M.TOP)
  if #top == 0 then return nil end
  local record = { id = contest.id, game = contest.game, minutes = contest.minutes, at = at, top = top }
  table.insert(book.past, 1, record)
  while #book.past > M.PAST_KEPT do table.remove(book.past) end
  return record
end

--- What every table hears while a contest is on, grace included. Time is sent as what is left, so clocks need not agree.
function M.broadcast(book, at)
  local contest = book.live
  if not contest then return nil end
  return { id = contest.id, game = contest.game, chips = contest.chips, open = M.running(contest, at),
    remaining = math.max(0, contest.ends - at), board = M.standings(contest, M.BOARD) }
end

--- Whether the contest page should be on the wall more than the others.
function M.showing(book, at)
  if book.live then return true end
  local last = book.past[1]
  return last ~= nil and at - last.at < M.FINAL_SHOW_MS
end

local ORDINAL = { "1st", "2nd", "3rd" }

--- What each of the top three is told, for the hub's chat box. gameName is the game's name for people.
function M.whispers(record, gameName)
  local list = {}
  for i, row in ipairs(record.top) do
    if i > M.WHISPERED then break end
    list[i] = { player = row.name, text = ("%s tournament: you came %s with %d chips"):format(gameName, ORDINAL[i], row.chips) }
  end
  return list
end

return M
