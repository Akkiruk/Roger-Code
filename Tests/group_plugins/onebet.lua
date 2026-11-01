-- group_plugins/onebet.lua
-- The smallest "house" game, used to prove the engine. Not in any registry, so it never ships.
-- Each player bets and says GO or DOUBLE, then the computer draws for the table with nobody to press anything. A card of eight or
-- better wins even money.

local deck = require("lib.casino.deck")
local theme = require("lib.casino.theme")

local C = theme.C
local rules = {}

local function find(state, seat)
  for _, player in ipairs(state.players) do
    if player.seat == seat then return player end
  end
  return nil
end

function rules.new(entries, _, rng)
  local cards = deck.shuffle(deck.fresh(1), rng)
  local players = {}
  for index, entry in ipairs(entries) do
    players[index] = { seat = entry.seat, name = entry.name, bet = entry.bet, card = deck.draw(cards), acted = false, net = 0 }
  end
  return { players = players, over = false }, { { type = "deal" } }
end

function rules.waitingOn(state)
  local list = {}
  if state.over then return list end
  for _, player in ipairs(state.players) do
    if not player.acted then list[#list + 1] = player.seat end
  end
  return list
end

function rules.actions(state, seat)
  local player = find(state, seat)
  if not player or player.acted or state.over then return {} end
  return {
    { id = "go", label = "GO", color = "win", textColor = "ink" },
    { id = "double", label = "DOUBLE", color = "gold", textColor = "ink", cost = player.bet },
  }
end

function rules.act(state, seat, id)
  -- With everyone done the game waits on nobody, which is the computer's move: seat is nil here
  if seat == nil then
    if id ~= "draw" or state.over or #rules.waitingOn(state) > 0 then return {} end
    state.over = true
    for _, each in ipairs(state.players) do
      each.net = deck.rank(each.card) >= 8 and each.bet or -each.bet
    end
    return { { type = "reveal" } }
  end
  local player = find(state, seat)
  if not player or player.acted or state.over or (id ~= "go" and id ~= "double") then return {} end
  player.acted = true
  if id == "double" then player.bet = player.bet * 2 end
  return { { type = "acted", seat = seat } }
end

function rules.auto(_, seat)
  if not seat then return "draw" end
  return "go"
end

function rules.viewFor(state, seat)
  local view = { over = state.over, bets = {} }
  for index, player in ipairs(state.players) do
    view.bets[index] = { seat = player.seat, bet = player.bet, card = state.over and player.card or nil }
  end
  local own = seat and find(state, seat)
  if own then view.bet = own.bet end
  return view
end

function rules.done(state)
  return state.over
end

function rules.nets(state)
  local nets = {}
  for _, player in ipairs(state.players) do nets[player.seat] = player.net end
  return nets
end

function rules.result(state, seat)
  local player = seat and find(state, seat)
  if not player then return { kind = "push", title = "ROUND OVER", detail = "" } end
  return { kind = player.net > 0 and "win" or "lose", title = player.net > 0 and "WIN" or "LOSE", detail = tostring(player.net) }
end

function rules.maxWin(entry)
  return entry.bet * 2
end

function rules.risk(state, seat)
  local player = find(state, seat)
  return player and player.bet or 0
end

return {
  id = "onebet", title = "ONE BET", kind = "house", minSeats = 1, maxSeats = 8, felt = "blue", tagline = "Even money",
  minBet = 10, maxBet = 2000,
  help = function() return { "Bet, then GO. Eight or better wins even money." } end,
  event = function() return 0.05 end,
  rules = rules,
  tableView = { draw = function(c) c:textCenter(math.floor(c.w / 2), 20, "ONE BET", C.gold) end },
  seatView = { draw = function(c, view) c:textCenter(math.floor(c.w / 2), 20, "Bet " .. tostring(view.bet or 0), C.gold) end },
}
