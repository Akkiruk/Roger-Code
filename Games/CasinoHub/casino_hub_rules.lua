-- casino_hub_rules.lua
-- What the casino's hub knows, built up from what tables send it. Pure: no screen, no rednet, no wallet.
-- The hub owns no tokens and moves none. It keeps leaderboards, each game's measured return and the shared jackpot pool.
--
-- The pool has one owner, so one pot cannot be paid twice. A table about to pay sends a claim and pays what comes back:
-- the smaller of what it asked and what the pool holds. The pool then resets, so a table with a stale figure gets the
-- fresh pool and not the one just paid. Claims are remembered by table and id, so a retry after a reboot gets the same
-- answer and resets nothing. That is also what makes a slow answer safe: a table that gave up waiting paid the seed, keeps
-- asking, and pays the rest when this answers it.
--
-- Anyone on the network can send anything. Messages are only checked for the right shape and a believable size.

local contest = require("casino_hub_contest")

local M = {
  SEED = 1000,            -- the pool starts here and returns here after every win
  MAX_POT = 1e7,          -- the pool stops growing here (net.lua has the same figure)
  MAX_POT_SHARE = 1e5,    -- 1% of a bet far beyond anything a table takes
  MAX_TOKENS = 1e9,       -- no one amount can honestly be this big
  MAX_NAME = 32,
  TOP = 8,                -- rows on a leaderboard
  KEPT_WINS = 8,          -- biggest and latest wins kept
  CLAIMS_KEPT = 40,
  STATE_MS = 10000,       -- how often the hub tells the floor where things stand
  QUIET_MS = 60000,       -- a table not heard from for this long is shown as quiet
  SMALL_SAMPLE = 100,     -- rounds below which a measured return means little
  ARCADE_PROTOCOL = "arcade.v1",  -- the Arcade's own, from Games/Arcade/arcade_net.lua. It only ever sends
  ARCADE_KEPT = 8,        -- Arcade results kept, which is what its page has room for
  MAX_MOVES = 100000,     -- longer than any game the Arcade could finish
}

-- Targets come from each game's own rules, or a test that proves them. A game with no stated target has none here.
-- Baccarat is the Banker bet, and Slots is its paytable before the jackpot.
-- Measured returns divide by everything wagered, raises included, so the two poker games with raises state theirs that way:
-- the loss per Ante is the same, over more tokens. Three Card: 3.37% of the Ante over 1 + 0.6742 Antes. Hold'em: 2.43% of the
-- Ante over 2 + 2.1636 Antes. Both are worked from threecard-oracle.mjs and holdem-oracle.mjs in craftos-agent, without side bets.
M.GAMES = {
  baccarat = { name = "Baccarat", target = 0.9894 },
  blackjack = { name = "Blackjack" },
  crazyeights = { name = "Crazy Eights" },
  hilo = { name = "Hi-Lo", target = 0.96 },
  ["horse-racing"] = { name = "Horse Racing", target = 0.96 },
  pokertable = { name = "Poker Table", target = 1 },
  roulette = { name = "Roulette", target = 36 / 37 },
  slots = { name = "Slots", target = 133610 / 140608 },
  ["three-card-poker"] = { name = "Three Card Poker", target = 0.9799 },
  ["ultimate-holdem"] = { name = "Ultimate Holdem", target = 0.9942 },
  videopoker = { name = "Video Poker", target = 0.98373 },
}

local function isNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isTokens(value)
  return isNumber(value) and math.abs(value) <= M.MAX_TOKENS
end

local function isName(value)
  return type(value) == "string" and value ~= "" and #value <= M.MAX_NAME
end

local function isId(value)
  return isName(value) or isNumber(value)
end

function M.new()
  return {
    jackpot = M.SEED,
    jackpotsPaid = 0,
    players = {},
    games = {},
    tables = {},
    biggest = {},
    latest = {},
    claims = {},
    claimOrder = {},
    arcade = {},
    contest = contest.new(),
  }
end

--- Everything a saved hub should have, so an older save still loads.
function M.restore(saved)
  local data = M.new()
  if type(saved) ~= "table" then return data end
  for key, value in pairs(saved) do
    if type(data[key]) == type(value) then data[key] = value end
  end
  return data
end

function M.gameName(id)
  local game = M.GAMES[id]
  return game and game.name or tostring(id)
end

local function hear(data, sender, game, at)
  local entry = data.tables[sender] or { rounds = 0 }
  entry.last = at
  if game then entry.game = game end
  data.tables[sender] = entry
  return entry
end

--- Each list gets its own copy: textutils.serialize refuses a table that appears twice, so sharing one breaks the save.
local function noteWin(data, win)
  local kept = {}
  for key, value in pairs(win) do kept[key] = value end
  table.insert(data.latest, 1, kept)
  while #data.latest > M.KEPT_WINS do table.remove(data.latest) end
  data.biggest[#data.biggest + 1] = win
  table.sort(data.biggest, function(a, b)
    if a.amount ~= b.amount then return a.amount > b.amount end
    return (a.at or 0) > (b.at or 0)
  end)
  while #data.biggest > M.KEPT_WINS do table.remove(data.biggest) end
end

local function onRound(data, sender, message, at)
  local game, name, wagered, result = message.game, message.player, message.wagered, message.net
  if not (isName(game) and isName(name) and isTokens(wagered) and isTokens(result)) or wagered < 0 then return false end
  local seen = hear(data, sender, game, at)
  seen.rounds = seen.rounds + 1

  local player = data.players[name] or { rounds = 0, wagered = 0, net = 0, best = 0 }
  player.rounds = player.rounds + 1
  player.wagered = player.wagered + wagered
  player.net = player.net + result
  player.best = math.max(player.best, result)
  data.players[name] = player

  local entry = data.games[game] or { rounds = 0, wagered = 0, net = 0 }
  entry.rounds = entry.rounds + 1
  entry.wagered = entry.wagered + wagered
  entry.net = entry.net + result
  data.games[game] = entry

  if result > 0 then noteWin(data, { player = name, game = game, amount = result, at = at }) end
  return true
end

local function onPot(data, sender, message, at)
  if not isNumber(message.amount) or message.amount <= 0 or message.amount > M.MAX_POT_SHARE then return false end
  hear(data, sender, nil, at)
  data.jackpot = math.min(M.MAX_POT, data.jackpot + math.floor(message.amount))
  return true
end

local function claimKey(sender, id)
  return tostring(sender) .. ":" .. tostring(id)
end

--- A table asks to pay from the pool. Returns what it may pay.
local function onClaim(data, sender, message, at)
  if not (isId(message.id) and isName(message.game) and isName(message.player) and isTokens(message.amount))
    or message.amount <= 0 then return nil end
  hear(data, sender, message.game, at)
  local key = claimKey(sender, message.id)
  local known = data.claims[key]
  if known then return known end

  local granted = math.min(math.floor(message.amount), data.jackpot)
  data.jackpot = M.SEED
  data.claims[key] = granted
  data.claimOrder[#data.claimOrder + 1] = key
  while #data.claimOrder > M.CLAIMS_KEPT do
    data.claims[table.remove(data.claimOrder, 1)] = nil
  end
  return granted
end

--- A jackpot was paid. A claimed one has already been taken from the pool; one that never asked resets it now. A claim this
-- hub never heard is a table that paid the seed and is still asking, and the pool stays whole for that claim to find.
local function onJackpot(data, sender, message, at)
  if not (isName(message.player) and isName(message.game) and isNumber(message.amount)) then return false end
  if message.amount <= 0 or message.amount > M.MAX_POT then return false end
  if message.claim ~= nil and not isId(message.claim) then return false end
  hear(data, sender, message.game, at)
  if message.claim == nil then data.jackpot = M.SEED end
  data.jackpotsPaid = data.jackpotsPaid + message.amount
  noteWin(data, { player = message.player, game = message.game, amount = message.amount, at = at, jackpot = true })
  return true
end

local function onExposure(data, sender, message, at)
  if not isTokens(message.amount) or message.amount < 0 then return false end
  hear(data, sender, nil, at).exposure = message.amount
  return true
end

--- Take in one message. Returns changed, and for a claim the reply to send.
function M.apply(data, sender, message, at)
  if type(message) ~= "table" then return false end
  local kind = message.kind
  if kind == "round" then return onRound(data, sender, message, at) end
  if kind == "pot" then return onPot(data, sender, message, at) end
  if kind == "jackpot" then return onJackpot(data, sender, message, at) end
  if kind == "exposure" then return onExposure(data, sender, message, at) end
  if kind == "claim" then
    local granted = onClaim(data, sender, message, at)
    if not granted then return false end
    return true, { id = message.id, to = sender, amount = granted }
  end
  if kind == "tscore" then
    if not contest.score(data.contest, sender, message, at) then return false end
    hear(data, sender, message.game, at)
    return true
  end
  return false
end

--- A finished Arcade match, newest first. Display only: no tokens, and nothing here reaches the leaderboards or the pool.
-- Only the fields the page shows are copied, so a message with more in it cannot grow the save. winner: 1 red, 2 blue, 3 a draw.
function M.arcadeResult(data, message, at)
  if type(message) ~= "table" or message.kind ~= "result" then return false end
  local winner, moves = message.winner, message.moves
  if not (isName(message.game) and isName(message.title) and isName(message.red) and isName(message.blue)) then return false end
  if winner ~= 1 and winner ~= 2 and winner ~= 3 then return false end
  if not isNumber(moves) or moves < 0 or moves > M.MAX_MOVES then return false end
  if message.ranked ~= nil and type(message.ranked) ~= "boolean" then return false end
  table.insert(data.arcade, 1, { game = message.game, title = message.title, red = message.red, blue = message.blue,
    winner = winner, moves = math.floor(moves), ranked = message.ranked == true, at = at })
  while #data.arcade > M.ARCADE_KEPT do table.remove(data.arcade) end
  return true
end

--- Players, best first by net winnings, or by key if given.
function M.leaders(data, limit, key)
  key = key or "net"
  local list = {}
  for name, player in pairs(data.players) do
    list[#list + 1] = { name = name, net = player.net, best = player.best, rounds = player.rounds, wagered = player.wagered }
  end
  table.sort(list, function(a, b)
    if a[key] ~= b[key] then return a[key] > b[key] end
    return a.name < b.name
  end)
  while #list > (limit or M.TOP) do table.remove(list) end
  return list
end

--- Each game's totals and real measured return, busiest first. Games with no rounds yet are left out.
function M.games(data)
  local list = {}
  for id, entry in pairs(data.games) do
    local known = M.GAMES[id]
    list[#list + 1] = {
      id = id, name = M.gameName(id), rounds = entry.rounds, wagered = entry.wagered, net = entry.net,
      measured = entry.wagered > 0 and (entry.wagered + entry.net) / entry.wagered or nil,
      target = known and known.target or nil,
    }
  end
  table.sort(list, function(a, b)
    if a.wagered ~= b.wagered then return a.wagered > b.wagered end
    return a.name < b.name
  end)
  return list
end

--- Tables heard from, most recent first.
function M.tables(data, at)
  local list = {}
  for id, entry in pairs(data.tables) do
    local ago = at - entry.last
    list[#list + 1] = { id = id, game = entry.game, name = entry.game and M.gameName(entry.game) or "Table",
      rounds = entry.rounds, ago = ago, live = ago < M.QUIET_MS }
  end
  table.sort(list, function(a, b)
    if a.ago ~= b.ago then return a.ago < b.ago end
    return tostring(a.id) < tostring(b.id)
  end)
  return list
end

--- Casino-wide totals.
function M.totals(data)
  local rounds, wagered, players = 0, 0, 0
  for _, entry in pairs(data.games) do
    rounds = rounds + entry.rounds
    wagered = wagered + entry.wagered
  end
  for _ in pairs(data.players) do players = players + 1 end
  return { rounds = rounds, wagered = wagered, players = players }
end

--- What every table hears: net.lua reads jackpot and leaders.
function M.state(data)
  return { jackpot = data.jackpot, leaders = M.leaders(data, M.TOP) }
end

return M
