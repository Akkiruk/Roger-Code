-- games/gin/rules.lua
-- Gin Rummy at a stake per point, one hand per deal, settled by the hand. Pure, as Games/BigTable/games/README.md asks.
--
-- 10 cards each and one card up. On a turn take the stock or the discard, then throw one. A hand with 10 or less deadwood after the
-- throw can knock. No deadwood is gin. The stock stops at two cards and that hand is a wash.
--   Knock: the knocker scores the difference, after the other player lays off on the knocker's melds.
--   Undercut: if the other player is level or lower they score the difference plus 25.
--   Gin: 25 plus the other player's deadwood, with no laying off.
-- A point is worth the stake, and a hand can never move more than the table maximum: POINT_CAP stakes, held to the smaller stack, so
-- nobody can lose past what they declared. Taking the top discard and throwing it straight back is not allowed. There is no first-turn
-- pass: the player after the dealer takes the up card or draws, like any turn.

local deck = require("lib.casino.deck")
local melds = require("games.gin.melds")

local M = {}

M.HAND = 10
M.KNOCK = 10
M.BONUS = 25
M.POINT_CAP = 100
M.STOCK_LEFT = 2

local function find(state, seat)
  for index, player in ipairs(state.players) do
    if player.seat == seat then return player, index end
  end
  return nil
end

local function current(state)
  return state.players[state.turn]
end

local function other(state, index)
  return state.players[3 - index]
end

local function topOf(state)
  return state.pile[#state.pile]
end

local function has(hand, card)
  for index, held in ipairs(hand) do
    if held == card then return index end
  end
  return nil
end

--- Work out what a hand is worth, once, so a screen never has to.
local function shape(player)
  local best = melds.best(player.hand)
  player.melds, player.loose, player.deadwood = best.melds, best.loose, best.deadwood
end

--- The start of a turn: what taking the top discard would leave, for the button.
local function startTurn(state)
  local player = current(state)
  state.phase, state.pick, state.left, state.took, state.fresh = "draw", nil, nil, nil, nil
  local hand = {}
  for index, card in ipairs(player.hand) do hand[index] = card end
  hand[#hand + 1] = topOf(state)
  local _, left = melds.bestThrow(hand, topOf(state))
  state.ifTaken = left
end

--- A drawn card is in. The throw starts on the best one, so one press plays a plain turn.
local function startThrow(state, card, locked)
  local player = current(state)
  player.hand[#player.hand + 1] = card
  shape(player)
  state.phase, state.fresh, state.took, state.ifTaken = "throw", card, locked and card or nil, nil
  state.pick, state.left = melds.bestThrow(player.hand, state.took)
end

local function throw(state)
  local player = current(state)
  local card = state.pick
  table.remove(player.hand, has(player.hand, card))
  state.pile[#state.pile + 1] = card
  shape(player)
  return card
end

--- A hand that ends with no knock moves nothing.
local function wash(state)
  state.phase, state.pick, state.left, state.took, state.fresh = "over", nil, nil, nil, nil
  state.outcome = { wash = true, points = 0, amount = 0 }
  state.players[1].net, state.players[2].net = 0, 0
end

local function knock(state)
  local index = state.turn
  local knocker, defender = state.players[index], other(state, index)
  local laidKnock, laidDefend = melds.showdown(knocker.hand, defender.hand)
  knocker.final, defender.final = laidKnock, laidDefend
  local gin = laidKnock.deadwood == 0
  local winner, points, undercut
  if gin then
    winner, points, undercut = index, M.BONUS + laidDefend.deadwood, false
  elseif laidKnock.deadwood < laidDefend.deadwood then
    winner, points, undercut = index, laidDefend.deadwood - laidKnock.deadwood, false
  else
    winner, points, undercut = 3 - index, laidKnock.deadwood - laidDefend.deadwood + M.BONUS, true
  end
  local amount = math.min(points * state.stake, state.cap)
  state.players[winner].net = amount
  state.players[3 - winner].net = -amount
  state.phase, state.pick, state.left, state.took, state.fresh = "over", nil, nil, nil, nil
  state.outcome = { knocker = knocker.seat, winner = state.players[winner].seat, gin = gin, undercut = undercut, points = points,
    amount = amount, capped = points * state.stake > state.cap }
end

function M.new(entries, button, rng, keep)
  local cards = deck.shuffle(deck.fresh(1), rng)
  local dealer = (button == 2) and 2 or 1
  local players, stake, cap = {}, 1, nil
  for index, entry in ipairs(entries) do
    players[index] = { seat = entry.seat, name = entry.name, stack = entry.stack, hand = {}, net = 0 }
    if entry.stake then stake = entry.stake end
    cap = math.min(cap or entry.stack, entry.stack)
  end
  local first = 3 - dealer
  for _ = 1, M.HAND do
    table.insert(players[first].hand, deck.draw(cards))
    table.insert(players[dealer].hand, deck.draw(cards))
  end
  local up = deck.draw(cards)
  shape(players[1])
  shape(players[2])
  local state = { players = players, stock = cards, pile = { up }, stake = stake, cap = math.min(cap, stake * M.POINT_CAP), dealer = dealer,
    turn = first, phase = "draw" }
  startTurn(state)
  return state, { { type = "deal" } }
end

function M.waitingOn(state)
  if state.phase == "over" then return {} end
  return { current(state).seat }
end

--- The buttons of a turn. The cards themselves are regions, on the wall.
function M.actions(state, seat)
  if state.phase == "over" or current(state).seat ~= seat then return {} end
  if state.phase == "draw" then
    return {
      { id = "stock", label = "STOCK", color = "blue", sub = #state.stock .. " left" },
      { id = "take", label = "TAKE " .. deck.name(topOf(state)), color = "accent", textColor = "ink", sub = "best " .. state.ifTaken .. " deadwood" },
    }
  end
  local list = { { id = "throw", label = "THROW " .. deck.name(state.pick), color = "blue", sub = "leaves " .. state.left .. " deadwood" } }
  if state.left == 0 then
    list[2] = { id = "knock", label = "GIN", color = "win", textColor = "ink", sub = "throw " .. deck.name(state.pick) }
  elseif state.left <= M.KNOCK then
    list[2] = { id = "knock", label = "KNOCK", color = "gold", textColor = "ink", sub = "at " .. state.left .. ", throw " .. deck.name(state.pick) }
  end
  return list
end

function M.act(state, seat, id, value)
  if state.phase == "over" or seat == nil or current(state).seat ~= seat then return {} end
  local player = current(state)
  if state.phase == "draw" then
    if id == "stock" then
      startThrow(state, deck.draw(state.stock), false)
      state.last = { seat = seat, what = "stock" }
      return { { type = "draw", seat = seat } }
    elseif id == "take" then
      local card = table.remove(state.pile)
      startThrow(state, card, true)
      state.last = { seat = seat, what = "take", card = card }
      return { { type = "take", seat = seat, card = card } }
    end
    return {}
  end
  if id == "pick" then
    if type(value) ~= "number" or value == state.took or value == state.pick or not has(player.hand, value) then return {} end
    local rest = {}
    for _, card in ipairs(player.hand) do
      if card ~= value then rest[#rest + 1] = card end
    end
    state.pick, state.left = value, melds.best(rest).deadwood
    return { { type = "pick", seat = seat } }
  elseif id == "throw" then
    local card = throw(state)
    state.last = { seat = seat, what = "throw", card = card }
    local events = { { type = "throw", seat = seat, card = card } }
    if #state.stock <= M.STOCK_LEFT then
      wash(state)
      events[2] = { type = "wash" }
    else
      state.turn = 3 - state.turn
      startTurn(state)
    end
    return events
  elseif id == "knock" then
    if state.left > M.KNOCK then return {} end
    local card = throw(state)
    state.last = { seat = seat, what = "knock", card = card }
    knock(state)
    return { { type = "throw", seat = seat, card = card }, { type = state.outcome.gin and "gin" or "knock", seat = seat } }
  end
  return {}
end

--- Someone away draws blind and throws what suits them best. They never knock: that is a decision, and it can lose.
function M.auto(state)
  if state.phase == "draw" then return "stock" end
  if state.phase == "throw" then return "throw" end
  return nil
end

local function laid(final)
  local copy = { deadwood = final.deadwood, melds = {}, laid = {}, loose = {} }
  for index, meld in ipairs(final.melds) do
    copy.melds[index] = {}
    for at, card in ipairs(meld) do copy.melds[index][at] = card end
  end
  for index, card in ipairs(final.laid) do copy.laid[index] = card end
  for index, card in ipairs(final.loose) do copy.loose[index] = card end
  return copy
end

--- Only what a player across the table can see, and for a seat their own cards. Built by hand: the stock and the other hand are not
-- anywhere in here, and which card a player has picked to throw stays theirs until it lands.
function M.viewFor(state, seat)
  local view = { phase = state.phase, over = state.phase == "over", turn = current(state).seat, stock = #state.stock, top = topOf(state),
    stake = state.stake, cap = state.cap, knockAt = M.KNOCK, players = {} }
  for index, player in ipairs(state.players) do
    view.players[index] = { seat = player.seat, name = player.name, count = #player.hand, net = state.phase == "over" and player.net or nil }
  end
  if state.last then view.last = { seat = state.last.seat, what = state.last.what, card = state.last.card } end
  if state.outcome then
    local outcome = state.outcome
    view.outcome = { wash = outcome.wash, knocker = outcome.knocker, winner = outcome.winner, gin = outcome.gin, undercut = outcome.undercut,
      points = outcome.points, amount = outcome.amount, capped = outcome.capped }
    if not outcome.wash then
      -- A knock lays both hands on the table, which is everything the showdown turns over
      for index, player in ipairs(state.players) do view.players[index].final = laid(player.final) end
    end
  end
  local own = seat and find(state, seat)
  if own then
    local hand = { deadwood = own.deadwood, melds = {}, loose = {} }
    for index, meld in ipairs(own.melds) do
      hand.melds[index] = {}
      for at, card in ipairs(meld) do hand.melds[index][at] = card end
    end
    for index, card in ipairs(own.loose) do hand.loose[index] = card end
    if state.phase == "throw" and current(state).seat == seat then
      hand.pick, hand.left, hand.fresh, hand.took = state.pick, state.left, state.fresh, state.took
    end
    view.hand = hand
  end
  return view
end

function M.done(state)
  return state.phase == "over"
end

function M.nets(state)
  local nets = {}
  for _, player in ipairs(state.players) do nets[player.seat] = player.net end
  return nets
end

local function howItEnded(state)
  local outcome = state.outcome
  local word = outcome.gin and "Gin" or (outcome.undercut and "Undercut" or "Knock")
  local text = word .. ", " .. outcome.points .. " points at " .. state.stake
  if outcome.capped then text = text .. ", held to the table maximum" end
  return text
end

function M.result(state, seat)
  local outcome = state.outcome
  if not outcome then return { kind = "push", title = "HAND OVER", detail = "" } end
  if outcome.wash then return { kind = "push", title = "NO HAND", detail = "The stock ran down. Nothing moves" } end
  local winner = find(state, outcome.winner)
  local title = outcome.gin and "GIN" or (outcome.undercut and "UNDERCUT" or "KNOCK")
  local player = seat and find(state, seat)
  if not player then return { kind = "win", title = winner.name .. " WINS", detail = howItEnded(state) .. ": " .. outcome.amount } end
  if player == winner then
    return { kind = "win", title = title .. "  YOU WIN", detail = "+" .. outcome.amount .. ". " .. howItEnded(state) }
  end
  return { kind = "lose", title = title .. "  YOU LOSE", detail = "-" .. outcome.amount .. ". " .. howItEnded(state) }
end

--- For the stats: what the hand really risked is what it moved.
function M.risk(state, seat)
  local player = find(state, seat)
  return player and math.abs(player.net) or 0
end

--- Work out both hands again from their cards. Only tests move cards behind the rules' back.
function M.reshape(state)
  shape(state.players[1])
  shape(state.players[2])
end

return M
