-- group_plugins/highcard.lua
-- The smallest "players" game, used to prove the engine. Not in any registry, so it never ships.
-- Everyone antes and gets one card. Each player then shows or folds, all at once. Showing costs a bet. The best card among those
-- who showed takes everything, ties split, odd chips to the first winner. Cards are set with casino_rig.dat through deck.shuffle.

local deck = require("lib.casino.deck")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local ANTE, BET = 10, 20

local rules = {}

local function find(state, seat)
  for _, player in ipairs(state.players) do
    if player.seat == seat then return player end
  end
  return nil
end

local function finish(state)
  state.over = true
  local best, winners, pot = -1, {}, 0
  for _, player in ipairs(state.players) do
    pot = pot + player.total
    if player.showed then
      local rank = deck.rank(player.card)
      if rank > best then
        best, winners = rank, { player }
      elseif rank == best then
        winners[#winners + 1] = player
      end
    end
  end
  if #winners == 0 then winners = { state.players[1] } end
  local share = math.floor(pot / #winners)
  for _, player in ipairs(state.players) do player.net = -player.total end
  for position, player in ipairs(winners) do
    player.net = player.net + share + (position == 1 and pot - share * #winners or 0)
    player.won = true
  end
end

function rules.new(entries, button, rng, keep)
  local cards = deck.shuffle(deck.fresh(1), rng)
  local players = {}
  for index, entry in ipairs(entries) do
    players[index] = { seat = entry.seat, name = entry.name, stack = entry.stack, card = deck.draw(cards),
      total = math.min(ANTE, entry.stack), acted = false }
  end
  keep.dealt = (keep.dealt or 0) + 1
  return { players = players, button = button, over = false }, { { type = "deal" } }
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
    { id = "fold", label = "FOLD", color = "red" },
    { id = "show", label = "SHOW", color = "win", textColor = "ink", sub = "bet " .. BET, cost = BET },
  }
end

function rules.act(state, seat, id)
  local player = find(state, seat)
  if not player or player.acted or state.over or (id ~= "show" and id ~= "fold") then return {} end
  player.acted = true
  if id == "show" then
    player.showed = true
    player.total = player.total + math.min(BET, player.stack - player.total)
  end
  local events = { { type = "acted", seat = seat, id = id } }
  if #rules.waitingOn(state) == 0 then
    finish(state)
    events[#events + 1] = { type = "reveal" }
  end
  return events
end

function rules.auto()
  return "fold"
end

function rules.viewFor(state, seat)
  local view = { over = state.over, players = {} }
  for index, player in ipairs(state.players) do
    local seen = state.over and player.showed
    view.players[index] = { seat = player.seat, name = player.name, total = player.total, acted = player.acted,
      card = seen and player.card or nil, net = state.over and player.net or nil }
  end
  local own = seat and find(state, seat)
  if own then view.card = own.card end
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
  if not player then return { kind = "push", title = "HAND OVER", detail = "" } end
  if player.net > 0 then return { kind = "win", title = "YOU WIN", detail = "+" .. player.net } end
  if player.net < 0 then return { kind = "lose", title = "YOU LOSE", detail = tostring(player.net) } end
  return { kind = "push", title = "EVEN", detail = "" }
end

function rules.risk(state, seat)
  local player = find(state, seat)
  return player and player.total or 0
end

return {
  id = "highcard", title = "HIGH CARD", kind = "players", minSeats = 2, maxSeats = 8, felt = "green", tagline = "Best card takes all",
  ante = ANTE + BET, minBuy = 100, maxStack = 2500,
  help = function()
    return { "Everyone antes and gets one card. Show for a bet or fold. The best card shown takes the lot.", "",
      { "THE MONEY", "gold" }, "Nothing moves until a hand ends." }
  end,
  event = function(ev) return ev.type == "deal" and 0.2 or 0.05, ev.type == "deal" and "deal" or nil end,
  rules = rules,
  tableView = {
    draw = function(c, view)
      local total = 0
      for _, player in ipairs(view.players) do total = total + player.total end
      c:textCenter(math.floor(c.w / 2), 20, "POT", C.gold)
      c:textCenter(math.floor(c.w / 2), 22, tostring(total), C.gold)
    end,
  },
  seatView = {
    draw = function(c, view) ui.card(c, 30, 12, view.card) end,
    regions = function(view) return view.card and { { id = "show", x = 30, y = 12, w = ui.CARD_W, h = ui.CARD_H } } or {} end,
  },
}
