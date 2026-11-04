-- games/catan/rules.lua
-- Settlers of Catan for three or four, on Game Night. One round is one whole game. The people seated play, and the computer fills
-- the table to four, so one person can play three computer players. Free: nets are always nought.
--
-- The game: a random fair island each time (no 6 or 8 side by side), two settlements and two roads each in snake order, the second
-- settlement's land paying out at once. Then turns: roll, everyone collects, a 7 makes anyone holding more than seven give up half
-- and the roller moves the robber and robs someone beside it. Build roads, settlements and cities, buy development cards and play
-- one a turn (never the one just bought), trade four for one with the bank or better at a harbour, or offer a trade to the table.
-- Longest road (5 or more) and largest army (3 or more knights) are worth 2 each. First to 10 points on their own turn wins.
--
-- What a seat does is in each player's ui: which menu is up, the spot picked on the board, a trade being made. It lives in the
-- state, because every press goes through the dealer and a reboot must come back to the same screen. Only that seat sees it.
--
-- The clock: the whole turn shares one clock (rules.turnMs), and when it runs out the turn is played out for them: roll if they
-- have not, then end the turn. A player whose clock has run out gets a short clock until they press something again.

local board = require("games.catan.board")
local bot = require("games.catan.bot")
local core = require("games.catan.core")

local M = {}

M.PLAYERS = 4
M.TURN_MS = 180000       -- a whole turn: the roll, building, trading
M.PLACE_MS = 90000       -- a setup placement, the robber, road building after a 7 or a card
M.DISCARD_MS = 60000
M.ANSWER_MS = 45000      -- answering someone else's trade
M.IDLE_MS = 20000        -- anything at all, for someone whose clock has run out and who has not pressed since
M.MAX_TURNS = 400        -- a game this long ends with the most points winning, so a table can never play for ever
M.LOG = 6

local BOT_NAMES = { "Ada", "Hal", "Max", "Ivy" }
local COLORS = { "red", "blue", "white", "orange" }

local function event(kind, fields)
  local ev = fields or {}
  ev.type = kind
  return ev
end

local function shuffle(list, rng)
  for i = #list, 2, -1 do
    local j = rng:below(i) + 1
    list[i], list[j] = list[j], list[i]
  end
  return list
end

local function copyList(list)
  local out = {}
  for i, item in ipairs(list) do out[i] = item end
  return out
end

local function log(state, text)
  local lines = state.log
  lines[#lines + 1] = text
  while #lines > M.LOG do table.remove(lines, 1) end
end

local function nameOf(state, p)
  return state.players[p].name
end

local function resText(list)
  local parts = {}
  for i = 1, 5 do
    if (list[i] or 0) > 0 then parts[#parts + 1] = list[i] .. " " .. board.RES_NAME[i] end
  end
  if #parts == 0 then return "nothing" end
  return table.concat(parts, " ")
end
M.resText = resText

-- ------------------------------------------------------------------ the island

--- Numbers on every hex but the desert, with no 6 or 8 beside another 6 or 8, and the same number side by side avoided when it can be.
local function placeNumbers(terrain, rng)
  local land = {}
  for h, t in ipairs(terrain) do
    if t ~= 0 then land[#land + 1] = h end
  end
  local number = {}
  for attempt = 1, 4000 do
    for h = 1, #terrain do number[h] = 0 end
    local tokens = shuffle(copyList(board.NUMBERS), rng)
    for i, h in ipairs(land) do number[h] = tokens[i] end
    local ok = true
    for h = 1, #terrain do
      for _, n in ipairs(board.hexes[h].near) do
        local a, b = number[h], number[n]
        local red = (a == 6 or a == 8) and (b == 6 or b == 8)
        if red or (attempt <= 800 and a ~= 0 and a == b) then ok = false end
      end
    end
    if ok then return number end
  end
  error("no fair island")
end

local function newBoard(state, rng)
  local terrain = shuffle(copyList(board.TERRAINS), rng)
  state.terrain = terrain
  state.number = placeNumbers(terrain, rng)
  for h, t in ipairs(terrain) do
    if t == 0 then state.robber = h end
  end
  local kinds = shuffle(copyList(board.HARBORS), rng)
  state.harbors = {}
  for i, e in ipairs(board.harborSides) do state.harbors[i] = { edge = e, res = kinds[i] } end
  state.owner, state.city, state.road = {}, {}, {}
  for v = 1, #board.vertices do
    state.owner[v] = 0
    state.city[v] = false
  end
  for e = 1, #board.edges do state.road[e] = 0 end
  local deck = {}
  for _, kind in ipairs(board.DEV_ORDER) do
    for _ = 1, board.DEV[kind] do deck[#deck + 1] = kind end
  end
  state.devDeck = shuffle(deck, rng)
  state.bank = { board.BANK, board.BANK, board.BANK, board.BANK, board.BANK }
end

-- ------------------------------------------------------------------ who is who

local function current(state)
  if state.phase == "setup" then return state.setup.order[state.setup.at] end
  return state.turn
end
M.current = current

local function playerOfSeat(state, seat)
  if seat == nil then return nil end
  for p, player in ipairs(state.players) do
    if player.seat == seat then return p end
  end
  return nil
end
M.playerOfSeat = playerOfSeat

local function isBot(state, p)
  return state.players[p].bot
end

local function mainUi()
  return { mode = "main" }
end

function M.new(entries, button, rng, keep)
  local players = {}
  for _, entry in ipairs(entries) do
    if #players < M.PLAYERS then players[#players + 1] = { seat = entry.seat, name = entry.name, bot = false } end
  end
  local names = shuffle(copyList(BOT_NAMES), rng)
  local n = 1
  while #players < M.PLAYERS do
    players[#players + 1] = { seat = false, name = names[n], bot = true }
    n = n + 1
  end
  shuffle(players, rng)
  for p, player in ipairs(players) do
    player.color = COLORS[p]
    player.res = core.zero()
    player.dev = {}
    player.knights = 0
    player.roadLength = 0
    player.idle = 0
    player.gain = core.zero()
    player.note = false
    player.ui = mainUi()
  end
  local state = {
    players = players, phase = "setup", turn = 1, turnNo = 0, dice = false, longest = 0, army = 0, winner = 0,
    devPlayed = false, steps = 0, freeRoads = 0, offer = false, discard = {}, log = {}, afterRobber = "main", game = 1,
  }
  for p = 1, #players do state.discard[p] = 0 end
  newBoard(state, rng)
  local order = {}
  for p = 1, #players do order[#order + 1] = p end
  for p = #players, 1, -1 do order[#order + 1] = p end
  state.setup = { order = order, at = 1, need = "town", town = 0 }
  log(state, "A new island. " .. nameOf(state, 1) .. " places first")
  return state, { event("start", { p = 1 }) }
end

-- ------------------------------------------------------------------ the clock, and who is waited on

function M.waitingOn(state)
  if state.phase == "over" then return {} end
  local list = {}
  if state.phase == "discard" then
    for p, player in ipairs(state.players) do
      if state.discard[p] > 0 and not player.bot then list[#list + 1] = player.seat end
    end
    return list
  end
  local p = current(state)
  if not isBot(state, p) then list[#list + 1] = state.players[p].seat end
  if state.offer then
    for q, answer in ipairs(state.offer.answers) do
      if answer == "wait" and not isBot(state, q) then list[#list + 1] = state.players[q].seat end
    end
  end
  return list
end

function M.turnMs(state, seat)
  local p = playerOfSeat(state, seat)
  if not p then return nil end
  if state.players[p].idle > 0 then return M.IDLE_MS end
  if state.phase == "discard" then return M.DISCARD_MS end
  if current(state) ~= p then return M.ANSWER_MS end
  if state.phase == "setup" then return M.PLACE_MS end
  if state.phase == "robber" or state.phase == "steal" or state.phase == "roads" then return M.PLACE_MS end
  return M.TURN_MS
end

--- A clock that ran out once is no missed turn: a player only counts as away from the second in a row.
function M.present(state, seat)
  local p = playerOfSeat(state, seat)
  return p ~= nil and state.players[p].idle < 2
end

-- ------------------------------------------------------------------ the spots on the board a player picks from

--- The places for a kind of piece, best first, so the spot already picked for a new player is a good one.
function M.spots(state, p, kind)
  local list
  local function byValue()
    local value = {}
    for _, v in ipairs(list) do value[v] = core.townValue(state, p, v) end
    table.sort(list, function(a, b)
      if value[a] ~= value[b] then return value[a] > value[b] end
      return a < b
    end)
  end
  if kind == "town" then
    list = core.townSpots(state, p, state.phase == "setup")
    byValue()
  elseif kind == "city" then
    list = core.citySpots(state, p)
    byValue()
  elseif kind == "road" then
    local from = state.phase == "setup" and state.setup.town or nil
    list = core.roadSpots(state, p, from)
    local first = from and bot.setupRoad(state, p, from) or bot.roadTarget(state, p)
    if first then
      for i, e in ipairs(list) do
        if e == first then
          table.remove(list, i)
          table.insert(list, 1, e)
          break
        end
      end
    end
  elseif kind == "robber" then
    list = core.robberSpots(state)
    local pick = bot.robber(state, p)
    for i, h in ipairs(list) do
      if h == pick then
        table.remove(list, i)
        table.insert(list, 1, h)
        break
      end
    end
  else
    list = {}
  end
  return list
end

--- What a player is placing now, if anything: the phase can call for it, or their own menu.
local function placing(state, p)
  if current(state) ~= p or state.offer then return nil end
  if state.phase == "setup" then return state.setup.need end
  if state.phase == "robber" then return "robber" end
  if state.phase == "roads" then return "road" end
  if state.phase == "main" and state.players[p].ui.mode == "place" then return state.players[p].ui.kind end
  return nil
end
M.placing = placing

--- The spot picked, kept good: a pick that is no longer legal falls back to the best one.
local function selected(state, p, kind, spots)
  local ui = state.players[p].ui
  if ui.kind == kind and ui.sel then
    for _, spot in ipairs(spots) do
      if spot == ui.sel then return spot end
    end
  end
  return spots[1]
end

local function setPick(state, p, kind, spot)
  local ui = state.players[p].ui
  ui.kind, ui.sel = kind, spot
end

-- ------------------------------------------------------------------ doing things

local function checkWin(state, p, events)
  if state.phase == "over" then return true end
  if current(state) ~= p or state.phase == "setup" then return false end
  if core.points(state, p) >= board.WIN then
    state.phase, state.winner = "over", p
    state.offer = false
    log(state, nameOf(state, p) .. " wins with " .. core.points(state, p) .. " points!")
    events[#events + 1] = event("win", { p = p })
    return true
  end
  return false
end

local function awards(state, events)
  local before = state.longest
  core.updateLongest(state)
  if state.longest ~= before then
    if state.longest ~= 0 then
      log(state, nameOf(state, state.longest) .. " has the longest road")
      events[#events + 1] = event("longest", { p = state.longest })
    else
      log(state, "Nobody holds the longest road now")
      events[#events + 1] = event("longest", { p = 0 })
    end
  end
end

local function startTurn(state, p, events)
  state.turn = p
  state.turnNo = state.turnNo + 1
  state.phase = "roll"
  state.devPlayed, state.steps, state.freeRoads, state.offer = false, 0, 0, false
  for _, player in ipairs(state.players) do player.ui = mainUi() end
  events[#events + 1] = event("turn", { p = p })
  checkWin(state, p, events)
end

local function endTurn(state, p, events)
  state.offer = false
  state.players[p].ui = mainUi()
  events[#events + 1] = event("end", { p = p })
  if state.turnNo >= M.MAX_TURNS then
    -- A table that has played this long has had its game: the most points wins
    local top, winner = -1, 1
    for q = 1, #state.players do
      local points = core.points(state, q)
      if points > top then top, winner = points, q end
    end
    state.phase, state.winner = "over", winner
    log(state, "Time is up: " .. nameOf(state, winner) .. " wins with " .. top .. " points")
    events[#events + 1] = event("win", { p = winner })
    return
  end
  startTurn(state, p % #state.players + 1, events)
end

--- Setup: a settlement, then its road, in snake order. The second settlement's land pays out.
local function setupPlace(state, p, spot, events)
  local setup = state.setup
  if setup.need == "town" then
    local ok = false
    for _, v in ipairs(core.townSpots(state, p, true)) do ok = ok or v == spot end
    if not ok then return false end
    state.owner[spot] = p
    setup.town = spot
    setup.need = "road"
    events[#events + 1] = event("town", { p = p, v = spot })
    if setup.at > #state.players then
      local got = core.zero()
      for _, h in ipairs(board.vertices[spot].hexes) do
        local t = state.terrain[h]
        if t > 0 and state.bank[t] > 0 then
          got[t] = got[t] + 1
          state.bank[t] = state.bank[t] - 1
          state.players[p].res[t] = state.players[p].res[t] + 1
        end
      end
      state.players[p].gain = got
      log(state, nameOf(state, p) .. " settles and takes " .. resText(got))
    else
      log(state, nameOf(state, p) .. " settles")
    end
    state.players[p].ui = mainUi()
    return true
  end
  local ok = false
  for _, e in ipairs(core.roadSpots(state, p, setup.town)) do ok = ok or e == spot end
  if not ok then return false end
  state.road[spot] = p
  events[#events + 1] = event("road", { p = p, e = spot })
  state.players[p].ui = mainUi()
  setup.at = setup.at + 1
  setup.need, setup.town = "town", 0
  if setup.at > #setup.order then
    awards(state, events)
    log(state, "Setup done. " .. nameOf(state, 1) .. " rolls first")
    state.turnNo = 0
    startTurn(state, 1, events)
  end
  return true
end

--- Everyone with a building on a hex with this number collects, unless the bank runs short of something two or more are owed.
local function produce(state, total, events)
  local owed = {}
  for p = 1, #state.players do
    owed[p] = core.zero()
    state.players[p].gain = core.zero()
  end
  for h = 1, #board.hexes do
    if state.number[h] == total and state.robber ~= h then
      local t = state.terrain[h]
      for _, v in ipairs(board.hexes[h].corners) do
        local owner = state.owner[v]
        if owner ~= 0 then owed[owner][t] = owed[owner][t] + (state.city[v] and 2 or 1) end
      end
    end
  end
  for t = 1, 5 do
    local want, takers, only = 0, 0, 0
    for p = 1, #state.players do
      if owed[p][t] > 0 then
        want = want + owed[p][t]
        takers = takers + 1
        only = p
      end
    end
    if want > 0 then
      if want <= state.bank[t] then
        for p = 1, #state.players do
          state.players[p].res[t] = state.players[p].res[t] + owed[p][t]
          state.players[p].gain[t] = owed[p][t]
        end
        state.bank[t] = state.bank[t] - want
      elseif takers == 1 then
        local give = state.bank[t]
        state.players[only].res[t] = state.players[only].res[t] + give
        state.players[only].gain[t] = give
        state.bank[t] = 0
      else
        log(state, "The bank is short of " .. board.RES_NAME[t] .. ": nobody gets any")
      end
    end
  end
  local parts = {}
  for p, player in ipairs(state.players) do
    if core.total(player.gain) > 0 then parts[#parts + 1] = player.name .. " " .. resText(player.gain) end
  end
  if #parts > 0 then
    log(state, table.concat(parts, ", "))
    events[#events + 1] = event("produce", {})
  end
end

local function botDiscards(state)
  for p, player in ipairs(state.players) do
    if player.bot and state.discard[p] > 0 then
      local give = bot.discard(state, p, state.discard[p])
      for i = 1, 5 do
        player.res[i] = player.res[i] - give[i]
        state.bank[i] = state.bank[i] + give[i]
      end
      log(state, player.name .. " gives up " .. state.discard[p] .. " cards")
      state.discard[p] = 0
    end
  end
end

local function afterDiscards(state)
  for p = 1, #state.players do
    if state.discard[p] > 0 then return end
  end
  state.phase = "robber"
end

local function roll(state, p, rng, events)
  local a, b = rng:below(6) + 1, rng:below(6) + 1
  local total = a + b
  state.dice = { a, b }
  for _, player in ipairs(state.players) do player.gain = core.zero() end
  events[#events + 1] = event("roll", { p = p, a = a, b = b })
  log(state, nameOf(state, p) .. " rolls " .. total)
  if total ~= 7 then
    produce(state, total, events)
    state.phase = "main"
    return
  end
  state.afterRobber = "main"
  local any = false
  for q, player in ipairs(state.players) do
    local count = core.total(player.res)
    state.discard[q] = count > 7 and math.floor(count / 2) or 0
    if state.discard[q] > 0 then
      any = true
      player.ui = { mode = "discard", pick = core.zero() }
    end
  end
  events[#events + 1] = event("seven", { p = p })
  if any then
    botDiscards(state)
    state.phase = "discard"
    afterDiscards(state)
  else
    state.phase = "robber"
  end
end

local function steal(state, p, victim, rng, events)
  local res = state.players[victim].res
  local count = core.total(res)
  if count > 0 then
    local n = rng:below(count) + 1
    for i = 1, 5 do
      if n > 0 and n <= res[i] then
        res[i] = res[i] - 1
        state.players[p].res[i] = state.players[p].res[i] + 1
        state.players[p].note = "You took " .. board.RES_NAME[i] .. " from " .. nameOf(state, victim)
        state.players[victim].note = nameOf(state, p) .. " took your " .. board.RES_NAME[i]
        n = 0
      else
        n = n - res[i]
      end
    end
    log(state, nameOf(state, p) .. " robs " .. nameOf(state, victim))
    events[#events + 1] = event("steal", { p = p, from = victim })
  end
  state.phase = state.afterRobber
end

local function moveRobber(state, p, h, victim, rng, events)
  if h == state.robber or not board.hexes[h] then return false end
  state.robber = h
  log(state, nameOf(state, p) .. " moves the robber to " .. board.TERRAIN_NAME[state.terrain[h]] ..
    (state.number[h] > 0 and (" " .. state.number[h]) or ""))
  events[#events + 1] = event("robber", { p = p, h = h })
  local victims = core.victims(state, p, h)
  if #victims == 0 then
    state.phase = state.afterRobber
  elseif #victims == 1 then
    steal(state, p, victims[1], rng, events)
  elseif victim then
    local ok = false
    for _, q in ipairs(victims) do ok = ok or q == victim end
    steal(state, p, ok and victim or victims[1], rng, events)
  else
    state.phase = "steal"
  end
  return true
end

local function build(state, p, kind, spot, events)
  local player = state.players[p]
  local townsLeft, citiesLeft, roadsLeft = core.piecesLeft(state, p)
  local free = kind == "road" and state.phase == "roads"
  if not free and not core.canAfford(player.res, board.COST[kind]) then return false end
  local ok = false
  if kind == "road" then
    if roadsLeft <= 0 then return false end
    for _, e in ipairs(core.roadSpots(state, p)) do ok = ok or e == spot end
  elseif kind == "town" then
    if townsLeft <= 0 then return false end
    for _, v in ipairs(core.townSpots(state, p, false)) do ok = ok or v == spot end
  elseif kind == "city" then
    if citiesLeft <= 0 then return false end
    for _, v in ipairs(core.citySpots(state, p)) do ok = ok or v == spot end
  end
  if not ok then return false end
  if not free then core.pay(state, p, board.COST[kind]) end
  if kind == "road" then
    state.road[spot] = p
    log(state, nameOf(state, p) .. " builds a road")
    events[#events + 1] = event("road", { p = p, e = spot })
  elseif kind == "town" then
    state.owner[spot] = p
    log(state, nameOf(state, p) .. " builds a settlement")
    events[#events + 1] = event("town", { p = p, v = spot })
  else
    state.city[spot] = true
    log(state, nameOf(state, p) .. " builds a city")
    events[#events + 1] = event("city", { p = p, v = spot })
  end
  awards(state, events)
  if free then
    state.freeRoads = state.freeRoads - 1
    local _, _, left = core.piecesLeft(state, p)
    if state.freeRoads <= 0 or left <= 0 or #core.roadSpots(state, p) == 0 then
      state.freeRoads = 0
      state.phase = "main"
    end
  end
  player.ui = mainUi()
  checkWin(state, p, events)
  return true
end

local function buyDev(state, p, events)
  local player = state.players[p]
  if #state.devDeck == 0 or not core.canAfford(player.res, board.COST.dev) then return false end
  core.pay(state, p, board.COST.dev)
  local card = table.remove(state.devDeck)
  player.dev[#player.dev + 1] = { k = card, t = state.turnNo }
  player.note = "You drew " .. board.DEV_NAME[card]
  log(state, nameOf(state, p) .. " buys a development card")
  events[#events + 1] = event("buy", { p = p })
  player.ui = mainUi()
  checkWin(state, p, events)
  return true
end

--- A card this player may play now: held since before this turn, and none played yet this turn.
local function playable(state, p, kind)
  if state.devPlayed or kind == "vp" then return nil end
  local player = state.players[p]
  if kind == "knight" then
    if state.phase ~= "roll" and state.phase ~= "main" then return nil end
  elseif state.phase ~= "main" then
    return nil
  end
  for i, card in ipairs(player.dev) do
    if card.k == kind and card.t < state.turnNo then return i end
  end
  return nil
end
M.playable = playable

local function playDev(state, p, kind, extra, rng, events)
  local index = playable(state, p, kind)
  if not index then return false end
  local player = state.players[p]
  if kind == "plenty" then
    if type(extra) ~= "table" or #extra ~= 2 then return false end
    local want = core.zero()
    for _, r in ipairs(extra) do
      if type(r) ~= "number" or not board.RES[r] then return false end
      want[r] = want[r] + 1
    end
    for i = 1, 5 do
      if want[i] > state.bank[i] then return false end
    end
    for i = 1, 5 do
      state.bank[i] = state.bank[i] - want[i]
      player.res[i] = player.res[i] + want[i]
    end
    log(state, nameOf(state, p) .. " plays Year of Plenty: " .. resText(want))
  elseif kind == "monopoly" then
    if type(extra) ~= "number" or not board.RES[extra] then return false end
    local taken = 0
    for q, other in ipairs(state.players) do
      if q ~= p then
        taken = taken + other.res[extra]
        if other.res[extra] > 0 then other.note = nameOf(state, p) .. "'s monopoly took " .. other.res[extra] .. " " .. board.RES_NAME[extra] end
        other.res[extra] = 0
      end
    end
    player.res[extra] = player.res[extra] + taken
    log(state, nameOf(state, p) .. " plays Monopoly on " .. board.RES_NAME[extra] .. " and takes " .. taken)
  elseif kind == "roads" then
    local _, _, left = core.piecesLeft(state, p)
    if left <= 0 or #core.roadSpots(state, p) == 0 then return false end
    state.freeRoads = math.min(2, left)
    state.phase = "roads"
    log(state, nameOf(state, p) .. " plays Road Building")
  elseif kind == "knight" then
    player.knights = player.knights + 1
    state.afterRobber = state.phase
    state.phase = "robber"
    log(state, nameOf(state, p) .. " plays a knight")
    local holder = state.army
    if player.knights >= 3 and holder ~= p and (holder == 0 or player.knights > state.players[holder].knights) then
      state.army = p
      log(state, nameOf(state, p) .. " has the largest army")
      events[#events + 1] = event("army", { p = p })
    end
  end
  table.remove(player.dev, index)
  state.devPlayed = true
  events[#events + 1] = event("play", { p = p, k = kind })
  player.ui = mainUi()
  checkWin(state, p, events)
  return true
end

local function bankTrade(state, p, give, get, events)
  if not core.bankTradeOk(state, p, give, get) then return false end
  local player = state.players[p]
  for i = 1, 5 do
    player.res[i] = player.res[i] - give[i] + get[i]
    state.bank[i] = state.bank[i] + give[i] - get[i]
  end
  log(state, nameOf(state, p) .. " trades " .. resText(give) .. " to the bank for " .. resText(get))
  events[#events + 1] = event("bank", { p = p })
  player.ui = mainUi()
  return true
end

local function closeOffer(state, events, why)
  if why then log(state, why) end
  state.offer = false
  events[#events + 1] = event("offerClosed", {})
end

--- The offer settles itself once nobody is left to answer: with nobody saying yes it is withdrawn.
local function offerCheck(state, events)
  local offer = state.offer
  if not offer then return end
  local waiting, yes = false, false
  for q, answer in ipairs(offer.answers) do
    if answer == "wait" then waiting = true end
    if answer == "yes" then yes = true end
    if q ~= offer.from and answer == "yes" and not core.canAfford(state.players[q].res, offer.get) then offer.answers[q] = "no" end
  end
  if not waiting and not yes then closeOffer(state, events, "Nobody takes " .. nameOf(state, offer.from) .. "'s trade") end
end

local function makeOffer(state, p, give, get, events)
  local player = state.players[p]
  if core.total(give) == 0 or core.total(get) == 0 or not core.canAfford(player.res, give) then return false end
  for i = 1, 5 do
    if give[i] > 0 and get[i] > 0 then return false end
  end
  local offer = { from = p, give = core.copy(give), get = core.copy(get), answers = {} }
  for q, other in ipairs(state.players) do
    if q == p then
      offer.answers[q] = "-"
    elseif not core.canAfford(other.res, get) then
      offer.answers[q] = "no"
    elseif other.bot then
      offer.answers[q] = bot.accepts(state, q, offer) and "yes" or "no"
    else
      offer.answers[q] = "wait"
    end
  end
  state.offer = offer
  state.offers = (state.offers or 0) + 1
  log(state, nameOf(state, p) .. " offers " .. resText(give) .. " for " .. resText(get))
  events[#events + 1] = event("offer", { p = p })
  offerCheck(state, events)
  return true
end

local function tradeWith(state, p, q, events)
  local offer = state.offer
  if not offer or offer.from ~= p or offer.answers[q] ~= "yes" then return false end
  local mine, theirs = state.players[p].res, state.players[q].res
  if not core.canAfford(mine, offer.give) or not core.canAfford(theirs, offer.get) then
    offer.answers[q] = "no"
    offerCheck(state, events)
    events[#events + 1] = event("offerClosed", {})
    return true
  end
  for i = 1, 5 do
    mine[i] = mine[i] - offer.give[i] + offer.get[i]
    theirs[i] = theirs[i] + offer.give[i] - offer.get[i]
  end
  state.players[q].note = "You traded with " .. nameOf(state, p)
  log(state, nameOf(state, p) .. " trades " .. resText(offer.give) .. " to " .. nameOf(state, q) .. " for " .. resText(offer.get))
  state.offer = false
  state.players[p].ui = mainUi()
  events[#events + 1] = event("trade", { p = p, q = q })
  return true
end

local function discardNow(state, p, give, events)
  if state.phase ~= "discard" or state.discard[p] <= 0 then return false end
  if core.total(give) ~= state.discard[p] or not core.canAfford(state.players[p].res, give) then return false end
  local player = state.players[p]
  for i = 1, 5 do
    player.res[i] = player.res[i] - give[i]
    state.bank[i] = state.bank[i] + give[i]
  end
  log(state, player.name .. " gives up " .. state.discard[p] .. " cards")
  state.discard[p] = 0
  player.ui = mainUi()
  events[#events + 1] = event("discard", { p = p })
  afterDiscards(state)
  return true
end

-- ------------------------------------------------------------------ the computer

--- One computer player's move. Something always happens.
local function botMove(state, rng)
  local events = {}
  local p = current(state)
  if not isBot(state, p) then return nil end
  local phase = state.phase
  state.steps = (state.steps or 0) + 1
  if phase == "setup" then
    local spot
    if state.setup.need == "town" then spot = bot.setupTown(state, p) else spot = bot.setupRoad(state, p, state.setup.town) end
    setupPlace(state, p, spot, events)
  elseif phase == "roll" then
    if bot.devPlay(state, p, true) == "knight" and playDev(state, p, "knight", nil, rng, events) then
      local h, victim = bot.robber(state, p)
      moveRobber(state, p, h, victim, rng, events)
    else
      roll(state, p, rng, events)
    end
  elseif phase == "robber" then
    local h, victim = bot.robber(state, p)
    moveRobber(state, p, h, victim, rng, events)
  elseif phase == "steal" then
    steal(state, p, bot.victim(state, p, core.victims(state, p, state.robber)), rng, events)
  elseif phase == "roads" then
    local e = bot.anyRoad(state, p)
    if not (e and build(state, p, "road", e, events)) then
      state.freeRoads, state.phase = 0, "main"
      events[#events + 1] = event("pass", { p = p })
    end
  elseif phase == "main" then
    local command = bot.step(state, p)
    local kind = command[1]
    local done = false
    if kind == "city" or kind == "town" or kind == "road" then
      done = build(state, p, kind, command[2], events)
    elseif kind == "dev" then
      done = buyDev(state, p, events)
    elseif kind == "play" then
      done = playDev(state, p, command[2], command[3], rng, events)
      if done and command[2] == "knight" then
        local h, victim = bot.robber(state, p)
        moveRobber(state, p, h, victim, rng, events)
      end
    elseif kind == "bank" then
      done = bankTrade(state, p, command[2], command[3], events)
    end
    if not done then endTurn(state, p, events) end
  end
  if #events == 0 then
    -- Nothing it wanted could happen. The turn moves on rather than the table stalling
    if state.phase == "main" then endTurn(state, p, events) else events[#events + 1] = event("pass", { p = p }) end
  end
  return events
end

--- A seat's clock ran out: play out what it was waiting for, as the computer would, and in the main part of a turn end it.
local function timeout(state, p, rng)
  local events = {}
  local player = state.players[p]
  player.idle = player.idle + 1
  if state.phase == "discard" and state.discard[p] > 0 then
    discardNow(state, p, bot.discard(state, p, state.discard[p]), events)
    return events
  end
  local offer = state.offer
  if offer and offer.from ~= p and offer.answers[p] == "wait" then
    offer.answers[p] = "no"
    events[#events + 1] = event("answer", { p = p, yes = false })
    offerCheck(state, events)
    return events
  end
  if current(state) ~= p then return nil end
  if offer then closeOffer(state, events, nil) end
  local phase = state.phase
  if phase == "setup" then
    local spot
    if state.setup.need == "town" then spot = bot.setupTown(state, p) else spot = bot.setupRoad(state, p, state.setup.town) end
    setupPlace(state, p, spot, events)
    log(state, player.name .. " ran out of time, so the computer placed for them")
  elseif phase == "roll" then
    roll(state, p, rng, events)
    if state.phase == "main" then endTurn(state, p, events) end
  elseif phase == "robber" then
    local h, victim = bot.robber(state, p)
    moveRobber(state, p, h, victim, rng, events)
  elseif phase == "steal" then
    steal(state, p, bot.victim(state, p, core.victims(state, p, state.robber)), rng, events)
  elseif phase == "roads" then
    state.freeRoads, state.phase = 0, "main"
    endTurn(state, p, events)
  elseif phase == "main" then
    endTurn(state, p, events)
  end
  if #events == 0 then return nil end
  return events
end

-- ------------------------------------------------------------------ a person's presses

local MODES = { main = true, build = true, trade = true, dev = true }

--- Presses while placing a piece or the robber: pick a spot, step through them, place it.
local function placePress(state, p, kind, id, value, rng, events)
  local spots = M.spots(state, p, kind)
  if #spots == 0 then return false end
  local sel = selected(state, p, kind, spots)
  if id == "spot" then
    for _, spot in ipairs(spots) do
      if spot == value then
        setPick(state, p, kind, spot)
        events[#events + 1] = event("pick", { p = p })
        return true
      end
    end
    return false
  elseif id == "next" or id == "prev" then
    local at = 1
    for i, spot in ipairs(spots) do
      if spot == sel then at = i end
    end
    at = (at - 1 + (id == "next" and 1 or -1)) % #spots + 1
    setPick(state, p, kind, spots[at])
    events[#events + 1] = event("pick", { p = p })
    return true
  elseif id == "place" then
    if state.phase == "setup" then return setupPlace(state, p, sel, events) end
    if kind == "robber" then
      if moveRobber(state, p, sel, nil, rng, events) then
        state.players[p].ui = mainUi()
        return true
      end
      return false
    end
    return build(state, p, kind, sel, events)
  end
  return false
end

--- Tiles on a resource row: a number 1-5, or a string "give3", "get1".
local function resIndex(value)
  local n = tonumber(value)
  if n and board.RES[n] then return n end
  return nil
end

local function mainPress(state, p, id, value, rng, events)
  local player = state.players[p]
  local ui = player.ui
  if id == "menu" then
    if not MODES[value] then return false end
    if value == "trade" then
      player.ui = { mode = "trade", give = core.zero(), get = core.zero() }
    else
      player.ui = { mode = value }
    end
    events[#events + 1] = event("menu", { p = p })
    return true
  elseif id == "back" then
    if ui.mode == "main" then return false end
    player.ui = mainUi()
    events[#events + 1] = event("menu", { p = p })
    return true
  elseif id == "end" then
    endTurn(state, p, events)
    return true
  elseif id == "build" then
    if value ~= "road" and value ~= "town" and value ~= "city" then return false end
    if not core.canAfford(player.res, board.COST[value]) then return false end
    local spots = M.spots(state, p, value)
    if #spots == 0 then return false end
    player.ui = { mode = "place", kind = value, sel = spots[1] }
    events[#events + 1] = event("menu", { p = p })
    return true
  elseif id == "buydev" then
    return buyDev(state, p, events)
  elseif id == "play" then
    if not playable(state, p, value) then return false end
    if value == "plenty" or value == "monopoly" then
      player.ui = { mode = value, pick = core.zero() }
      events[#events + 1] = event("menu", { p = p })
      return true
    end
    return playDev(state, p, value, nil, rng, events)
  end
  if ui.mode == "place" then return placePress(state, p, ui.kind, id, value, rng, events) end
  if ui.mode == "trade" then
    if id == "give" or id == "get" then
      local r = resIndex(value)
      if not r then return false end
      local list = ui[id]
      if id == "give" and list[r] >= player.res[r] then return false end
      if id == "get" and list[r] >= 19 then return false end
      list[r] = list[r] + 1
      -- One resource cannot be on both sides
      local other = id == "give" and ui.get or ui.give
      other[r] = 0
      events[#events + 1] = event("pick", { p = p })
      return true
    elseif id == "clear" then
      ui.give, ui.get = core.zero(), core.zero()
      events[#events + 1] = event("pick", { p = p })
      return true
    elseif id == "bank" then
      return bankTrade(state, p, ui.give, ui.get, events)
    elseif id == "offer" then
      return makeOffer(state, p, ui.give, ui.get, events)
    end
    return false
  end
  if ui.mode == "plenty" or ui.mode == "monopoly" then
    if id == "pick" then
      local r = resIndex(value)
      if not r then return false end
      if ui.mode == "monopoly" then
        ui.pick = core.zero()
        ui.pick[r] = 1
      else
        if core.total(ui.pick) >= 2 then ui.pick = core.zero() end
        if ui.pick[r] + 1 > state.bank[r] then return false end
        ui.pick[r] = ui.pick[r] + 1
      end
      events[#events + 1] = event("pick", { p = p })
      return true
    elseif id == "confirm" then
      if ui.mode == "monopoly" then
        for i = 1, 5 do
          if ui.pick[i] > 0 then return playDev(state, p, "monopoly", i, rng, events) end
        end
        return false
      end
      local list = {}
      for i = 1, 5 do
        for _ = 1, ui.pick[i] do list[#list + 1] = i end
      end
      return playDev(state, p, "plenty", list, rng, events)
    end
  end
  return false
end

local function press(state, p, id, value, rng)
  local events = {}
  local player = state.players[p]
  local phase = state.phase
  -- Giving up cards after a 7: anyone who has to, at the same time
  if phase == "discard" then
    if state.discard[p] <= 0 then return nil end
    local ui = player.ui
    if ui.mode ~= "discard" or not ui.pick then return nil end
    if id == "pick" then
      local r = resIndex(value)
      if not r or ui.pick[r] >= player.res[r] or core.total(ui.pick) >= state.discard[p] then return nil end
      ui.pick[r] = ui.pick[r] + 1
      events[#events + 1] = event("pick", { p = p })
      return events
    elseif id == "clear" then
      ui.pick = core.zero()
      events[#events + 1] = event("pick", { p = p })
      return events
    elseif id == "confirm" then
      if discardNow(state, p, ui.pick, events) then return events end
    end
    return nil
  end
  local offer = state.offer
  if offer and offer.from ~= p then
    if offer.answers[p] ~= "wait" then return nil end
    if id == "accept" and core.canAfford(player.res, offer.get) then
      offer.answers[p] = "yes"
    elseif id == "decline" then
      offer.answers[p] = "no"
    else
      return nil
    end
    events[#events + 1] = event("answer", { p = p, yes = id == "accept" })
    offerCheck(state, events)
    return events
  end
  if current(state) ~= p then return nil end
  if offer then
    if id == "cancel" then
      closeOffer(state, events, nameOf(state, p) .. " withdraws the offer")
      return events
    elseif id == "with" then
      local q = tonumber(value)
      if q and tradeWith(state, p, q, events) then return events end
    end
    return nil
  end
  if phase == "setup" then
    if placePress(state, p, state.setup.need, id, value, rng, events) then return events end
    return nil
  elseif phase == "robber" then
    if placePress(state, p, "robber", id, value, rng, events) then return events end
    return nil
  elseif phase == "steal" then
    local q = tonumber(value)
    if id ~= "steal" or not q then return nil end
    for _, victim in ipairs(core.victims(state, p, state.robber)) do
      if victim == q then
        steal(state, p, q, rng, events)
        return events
      end
    end
    return nil
  elseif phase == "roads" then
    if id == "done" then
      state.freeRoads, state.phase = 0, "main"
      events[#events + 1] = event("pass", { p = p })
      return events
    end
    if placePress(state, p, "road", id, value, rng, events) then return events end
    return nil
  elseif phase == "roll" then
    if id == "roll" then
      roll(state, p, rng, events)
      return events
    elseif id == "play" and value == "knight" then
      if playDev(state, p, "knight", nil, rng, events) then return events end
    end
    return nil
  elseif phase == "main" then
    if mainPress(state, p, id, value, rng, events) then return events end
  end
  return nil
end

function M.act(state, seat, id, value, rng)
  if state.phase == "over" then return nil end
  if seat == nil then
    if id ~= "bot" then return nil end
    return botMove(state, rng)
  end
  local p = playerOfSeat(state, seat)
  if not p then return nil end
  if id == "timeout" then return timeout(state, p, rng) end
  local events = press(state, p, id, value, rng)
  if events and #events > 0 then
    state.players[p].idle = 0
    return events
  end
  return nil
end

function M.auto(state, seat)
  if seat == nil then return "bot", nil end
  return "timeout", nil
end

-- ------------------------------------------------------------------ the buttons

local function button(id, label, color, extra)
  local b = { id = id, label = label, color = color or "panel2" }
  if color == "win" or color == "gold" or color == "accent" then b.textColor = "ink" end
  for key, value in pairs(extra or {}) do b[key] = value end
  return b
end

local function placeButtons(list, spots, back)
  list[#list + 1] = button("prev", "<", "blue", { disabled = #spots < 2 })
  list[#list + 1] = button("next", ">", "blue", { disabled = #spots < 2 })
  if back then list[#list + 1] = button(back.id, back.label, "red") end
  list[#list + 1] = button("place", "PLACE", "win", { disabled = #spots == 0 })
  return list
end

local function costText(cost)
  local parts = {}
  for i = 1, 5 do
    if cost[i] > 0 then parts[#parts + 1] = cost[i] .. board.RES_SHORT[i] end
  end
  return table.concat(parts, " ")
end

function M.actions(state, seat)
  local p = playerOfSeat(state, seat)
  if not p or state.phase == "over" then return {} end
  local player = state.players[p]
  local list = {}
  if state.phase == "discard" then
    if state.discard[p] <= 0 then return {} end
    local pick = player.ui.pick or core.zero()
    list[#list + 1] = button("clear", "CLEAR", "panel2")
    list[#list + 1] = button("confirm", "GIVE UP " .. state.discard[p], "win", { disabled = core.total(pick) ~= state.discard[p] })
    return list
  end
  local offer = state.offer
  if offer and offer.from ~= p then
    if offer.answers[p] ~= "wait" then return {} end
    list[#list + 1] = button("decline", "NO", "red")
    list[#list + 1] = button("accept", "ACCEPT", "win", { disabled = not core.canAfford(player.res, offer.get) })
    return list
  end
  if current(state) ~= p then return {} end
  if offer then
    list[#list + 1] = button("cancel", "CANCEL", "red")
    for q, answer in ipairs(offer.answers) do
      if answer == "yes" then list[#list + 1] = button("with", state.players[q].name:sub(1, 8), "win", { value = q }) end
    end
    return list
  end
  local phase = state.phase
  if phase == "setup" then
    return placeButtons(list, M.spots(state, p, state.setup.need), nil)
  elseif phase == "robber" then
    return placeButtons(list, M.spots(state, p, "robber"), nil)
  elseif phase == "roads" then
    return placeButtons(list, M.spots(state, p, "road"), { id = "done", label = "STOP" })
  elseif phase == "steal" then
    for _, q in ipairs(core.victims(state, p, state.robber)) do
      list[#list + 1] = button("steal", state.players[q].name:sub(1, 8), "gold", { value = q })
    end
    return list
  elseif phase == "roll" then
    if playable(state, p, "knight") then list[#list + 1] = button("play", "KNIGHT", "blue", { value = "knight" }) end
    list[#list + 1] = button("roll", "ROLL", "win")
    return list
  end
  -- The main part of the turn
  local ui = player.ui
  local mode = ui.mode
  if mode == "build" then
    local townsLeft, citiesLeft, roadsLeft = core.piecesLeft(state, p)
    local function can(kind, left)
      return left > 0 and core.canAfford(player.res, board.COST[kind]) and #M.spots(state, p, kind) > 0
    end
    list[#list + 1] = button("back", "BACK", "red")
    list[#list + 1] = button("build", "ROAD", "accent", { value = "road", sub = costText(board.COST.road), disabled = not can("road", roadsLeft) })
    list[#list + 1] = button("build", "TOWN", "accent", { value = "town", sub = costText(board.COST.town), disabled = not can("town", townsLeft) })
    list[#list + 1] = button("build", "CITY", "accent", { value = "city", sub = costText(board.COST.city), disabled = not can("city", citiesLeft) })
    list[#list + 1] = button("buydev", "CARD", "accent", { sub = costText(board.COST.dev),
      disabled = #state.devDeck == 0 or not core.canAfford(player.res, board.COST.dev) })
    return list
  elseif mode == "place" then
    return placeButtons(list, M.spots(state, p, ui.kind), { id = "back", label = "BACK" })
  elseif mode == "trade" then
    list[#list + 1] = button("back", "BACK", "red")
    list[#list + 1] = button("clear", "CLEAR", "panel2")
    local give, get = ui.give or core.zero(), ui.get or core.zero()
    local ready = core.total(give) > 0 and core.total(get) > 0
    list[#list + 1] = button("bank", "BANK", "gold", { disabled = not core.bankTradeOk(state, p, give, get) })
    list[#list + 1] = button("offer", "OFFER", "win", { disabled = not ready or not core.canAfford(player.res, give) })
    return list
  elseif mode == "dev" then
    list[#list + 1] = button("back", "BACK", "red")
    for _, kind in ipairs({ "knight", "roads", "plenty", "monopoly" }) do
      local label = ({ knight = "KNIGHT", roads = "ROADS", plenty = "PLENTY", monopoly = "MONOPOLY" })[kind]
      list[#list + 1] = button("play", label, "blue", { value = kind, disabled = not playable(state, p, kind) })
    end
    return list
  elseif mode == "plenty" or mode == "monopoly" then
    local pick = ui.pick or core.zero()
    list[#list + 1] = button("back", "BACK", "red")
    local ready = mode == "monopoly" and core.total(pick) == 1 or core.total(pick) == 2
    list[#list + 1] = button("confirm", mode == "monopoly" and "TAKE ALL" or "TAKE 2", "win", { disabled = not ready })
    return list
  end
  list[#list + 1] = button("menu", "BUILD", "accent", { value = "build" })
  list[#list + 1] = button("menu", "TRADE", "gold", { value = "trade" })
  list[#list + 1] = button("menu", "CARDS", "blue", { value = "dev" })
  list[#list + 1] = button("end", "END", "red")
  return list
end

-- ------------------------------------------------------------------ what each seat may see

local function publicPlayers(state)
  local out = {}
  for p, player in ipairs(state.players) do
    local towns, cities, roads = core.countPieces(state, p)
    out[p] = {
      name = player.name, color = player.color, bot = player.bot, seat = player.seat or false,
      points = core.publicPoints(state, p), cards = core.total(player.res), devs = #player.dev, knights = player.knights,
      road = player.roadLength, towns = towns, cities = cities, roads = roads, gain = core.copy(player.gain),
      discard = state.discard[p] or 0, idle = player.idle,
    }
    if state.phase == "over" then out[p].total = core.points(state, p) end
  end
  return out
end

local function listCopy(list)
  local out = {}
  for i, value in ipairs(list) do out[i] = value end
  return out
end

--- What the table shows: everything on the board, card counts, never a card.
local function publicView(state)
  local view = {
    terrain = listCopy(state.terrain), number = listCopy(state.number), robber = state.robber,
    owner = listCopy(state.owner), city = listCopy(state.city), road = listCopy(state.road),
    harbors = {}, players = publicPlayers(state), phase = state.phase, turn = current(state), turnNo = state.turnNo,
    dice = state.dice and { state.dice[1], state.dice[2] } or false, longest = state.longest, army = state.army,
    winner = state.winner, deck = #state.devDeck, bank = listCopy(state.bank), log = listCopy(state.log),
    offer = false, placing = false,
  }
  for i, harbor in ipairs(state.harbors) do view.harbors[i] = { edge = harbor.edge, res = harbor.res } end
  if state.phase == "setup" then view.setupRound = state.setup.at > #state.players and 2 or 1 end
  local offer = state.offer
  if offer then
    view.offer = { from = offer.from, give = core.copy(offer.give), get = core.copy(offer.get), answers = listCopy(offer.answers) }
  end
  local p = current(state)
  local kind = placing(state, p)
  if kind then
    local spots = M.spots(state, p, kind)
    view.placing = { kind = kind, spots = spots, sel = selected(state, p, kind, spots) or false, p = p }
  end
  return view
end

function M.viewFor(state, seat)
  local view = publicView(state)
  local p = playerOfSeat(state, seat)
  if not p then return view end
  local player = state.players[p]
  view.me = p
  view.hand = core.copy(player.res)
  view.note = player.note or false
  view.dev = {}
  for i, card in ipairs(player.dev) do view.dev[i] = { k = card.k, new = card.t >= state.turnNo } end
  view.hidden = core.hiddenPoints(state, p)
  view.ratios = core.ratios(state, p)
  view.mode = player.ui.mode
  view.pick = player.ui.pick and core.copy(player.ui.pick) or false
  view.give = player.ui.give and core.copy(player.ui.give) or false
  view.get = player.ui.get and core.copy(player.ui.get) or false
  view.mustDiscard = state.discard[p] or 0
  view.canPlay = {}
  for _, kind in ipairs({ "knight", "roads", "plenty", "monopoly" }) do view.canPlay[kind] = playable(state, p, kind) ~= nil end
  if state.phase == "steal" and current(state) == p then view.victims = core.victims(state, p, state.robber) end
  local townsLeft, citiesLeft, roadsLeft = core.piecesLeft(state, p)
  view.left = { town = townsLeft, city = citiesLeft, road = roadsLeft }
  return view
end

function M.done(state)
  return state.phase == "over"
end

function M.nets(state)
  local out = {}
  for _, player in ipairs(state.players) do
    if player.seat then out[player.seat] = 0 end
  end
  return out
end

local function scoreLine(state, p)
  local towns, cities = core.countPieces(state, p)
  local parts = {}
  if cities > 0 then parts[#parts + 1] = cities .. (cities == 1 and " city" or " cities") end
  if towns > 0 then parts[#parts + 1] = towns .. (towns == 1 and " settlement" or " settlements") end
  if state.longest == p then parts[#parts + 1] = "longest road" end
  if state.army == p then parts[#parts + 1] = "largest army" end
  local hidden = core.hiddenPoints(state, p)
  if hidden > 0 then parts[#parts + 1] = hidden .. " VP card" .. (hidden == 1 and "" or "s") end
  return core.points(state, p) .. " points: " .. table.concat(parts, ", ")
end

function M.result(state, seat)
  local winner = state.winner
  if winner == 0 then return { kind = "push", title = "NO WINNER", detail = "The game ended early" } end
  local name = nameOf(state, winner)
  local p = playerOfSeat(state, seat)
  if p == winner then return { kind = "win", title = "YOU WIN!", detail = scoreLine(state, winner) } end
  if p then return { kind = "lose", title = string.upper(name) .. " WINS", detail = "You had " .. core.points(state, p) .. " points" } end
  return { kind = "win", title = string.upper(name) .. " WINS", detail = scoreLine(state, winner) }
end

return M
