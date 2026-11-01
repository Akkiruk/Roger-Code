-- games/stud/rules.lua
-- Seven Card Stud for 2 to 8 players, fixed limit. Pure: no screen, no sound, no money.
--
-- A hand: everyone antes and gets two cards down and one up. The lowest up-card opens with the bring-in, or completes to the small
-- bet. Then a card up on fourth, fifth and sixth street, and one down on seventh, with a betting round after each. Third and fourth
-- street bet the small bet, the rest the big bet. A round allows a bet and three raises, and a completion counts as the bet.
-- After third street the best board acts first. Ties go to the first left of the button.
--
-- Eight players can want 56 cards. When the deck cannot give every live player a seventh card, one card goes face up in the middle
-- and it is everyone's seventh. Nobody is ever short of a card before that: 8 players use 48 by sixth street.
--
-- Chips work as Poker Table's do, with its pots and award: stack behind, bet this street, total in the pot. Side pots come from the
-- totals at showdown. A raise too short to be a full raise is allowed as an all-in. Half a bet or more counts as a raise, and less only
-- sets a new price: it uses up none of the bets, and anyone who has already acted may call or fold but not raise. An odd chip goes to the
-- owner (group/rounding.lua). With fewer than two players able to bet, the cards still play out, and only what someone really
-- bet has to be matched. Down-cards stay down until the showdown.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")
local rounding = require("lib.casino.group.rounding")
local table5 = require("pokertable_rules")

local M = {
  ANTE = 2,
  BRING_IN = 5,
  SMALL = 10,
  BIG = 20,
  MAX_BETS = 4,     -- a bet and three raises, each street
  MAX_SEATS = 8,
}

M.STREETS = { [3] = "3RD STREET", [4] = "4TH STREET", [5] = "5TH STREET", [6] = "6TH STREET", [7] = "7TH STREET" }

local function canAct(player)
  return not player.folded and not player.allin
end

local function isLive(player)
  return not player.folded
end

--- The first player left of position from who passes the test, as a position.
local function leftOf(state, from, test)
  local total = #state.players
  for step = 1, total do
    local index = (from + step - 1) % total + 1
    if test(state.players[index]) then return index end
  end
  return nil
end

local function count(state, test)
  local total = 0
  for _, player in ipairs(state.players) do
    if test(player) then total = total + 1 end
  end
  return total
end

local function find(state, seat)
  for index, player in ipairs(state.players) do
    if player.seat == seat then return player, index end
  end
  return nil
end

--- Move chips from a stack to the pot. A short stack puts in what it has and is all-in.
local function put(player, amount)
  local paid = math.min(amount, player.stack)
  player.stack = player.stack - paid
  player.bet = player.bet + paid
  player.total = player.total + paid
  if player.stack == 0 then player.allin = true end
  return paid
end

local function potTotal(state)
  local total = 0
  for _, player in ipairs(state.players) do total = total + player.total end
  return total
end

-- ------------------------------------------------------------------ what a board shows

--- Up to four up-cards as one number. Only pairs and better count: straights and flushes do not count on a board.
-- Higher is better. The bring-in has its own test and never comes here.
function M.boardScore(cards)
  local counts = {}
  for _, card in ipairs(cards) do
    local rank = deck.rank(card)
    counts[rank] = (counts[rank] or 0) + 1
  end
  local groups = {}
  for rank, size in pairs(counts) do groups[#groups + 1] = { rank = rank, size = size } end
  table.sort(groups, function(a, b)
    if a.size ~= b.size then return a.size > b.size end
    return a.rank > b.rank
  end)
  local top = groups[1] and groups[1].size or 0
  local kind = 0
  if top == 4 then kind = 4
  elseif top == 3 then kind = 3
  elseif top == 2 and groups[2] and groups[2].size == 2 then kind = 2
  elseif top == 2 then kind = 1 end
  local value = kind
  for position = 1, 4 do
    value = value * 15 + (groups[position] and groups[position].rank or 0)
  end
  return value
end

--- A name for fewer than five cards: "Pair of Kings", "Ace High".
local function partName(cards)
  if #cards == 0 then return "" end
  local value = M.boardScore(cards)
  local kind = math.floor(value / 50625)
  local rank = math.floor(value / 3375) % 15
  if kind == 4 then return "Four of a Kind" end
  if kind == 3 then return "Three of a Kind" end
  if kind == 2 then return "Two Pair" end
  if kind == 1 then return "Pair of " .. poker.rankPlural(rank) end
  return poker.rankWord(rank) .. " High"
end

--- Every card that plays for a player: theirs, and the shared one.
local function cardsOf(state, player)
  local cards = {}
  for _, card in ipairs(player.down) do cards[#cards + 1] = card end
  for _, card in ipairs(player.up) do cards[#cards + 1] = card end
  if state.community then cards[#cards + 1] = state.community end
  return cards
end

local function handName(cards)
  if #cards >= 5 then return poker.describe(poker.evaluate(cards)) end
  return partName(cards)
end

-- ------------------------------------------------------------------ the hand

local nextStreet

local function finishHand(state, events)
  state.phase = "over"
  state.turn = nil
  state.bringin = false
  state.uncontested = count(state, isLive) == 1
  if not state.uncontested then
    for _, player in ipairs(state.players) do
      if isLive(player) then
        player.score = poker.evaluate(cardsOf(state, player))
        player.handName = poker.describe(player.score)
      end
    end
  end
  state.pots = table5.pots(state.players)
  table5.award(state.pots, state.players, state.button)
  for _, player in ipairs(state.players) do
    player.net = player.won - player.total
    player.stack = player.start + player.net
  end
  rounding.take(state)
  events[#events + 1] = { type = "showdown", uncontested = state.uncontested }
end

--- The lowest up-card among those who can bet. Card numbers run by rank then suit, clubs lowest, so no two can tie.
local function lowest(state)
  local low, lowCard = nil, nil
  for index, player in ipairs(state.players) do
    if canAct(player) and (not lowCard or player.up[1] < lowCard) then low, lowCard = index, player.up[1] end
  end
  return low
end

--- Who opens a street after third: the best board, or the next who can bet when that one is all-in.
local function firstToAct(state)
  local best, bestValue = nil, -1
  local total = #state.players
  for step = 1, total do
    local index = (state.button + step - 1) % total + 1
    local player = state.players[index]
    if isLive(player) then
      local value = M.boardScore(player.up)
      if value > bestValue then best, bestValue = index, value end
    end
  end
  return leftOf(state, best - 1, canAct)
end

local function openBetting(state, events)
  state.phase = "bet"
  state.size = state.street <= 4 and state.small or state.big
  state.current = 0
  state.bets = 0
  for _, player in ipairs(state.players) do
    player.bet = 0
    player.acted = false
    player.last = nil
  end
  if count(state, canAct) < 2 then
    -- Nobody is left to bet against: the cards still play out
    return nextStreet(state, events)
  end
  if state.street == 3 then
    state.turn = lowest(state)
    state.bringin = true
  else
    state.turn = firstToAct(state)
  end
end

--- Deal round the table from left of the button, to everyone still in.
local function dealRound(state, give)
  local total = #state.players
  for step = 1, total do
    local player = state.players[(state.button + step - 1) % total + 1]
    if isLive(player) then give(player) end
  end
end

nextStreet = function(state, events)
  if state.street >= 7 then
    finishHand(state, events)
    return
  end
  state.street = state.street + 1
  if state.street < 7 then
    dealRound(state, function(player) player.up[#player.up + 1] = deck.draw(state.deck) end)
    events[#events + 1] = { type = "street", street = state.street }
  elseif #state.deck < count(state, isLive) then
    state.community = deck.draw(state.deck)
    events[#events + 1] = { type = "street", street = state.street, community = state.community }
  else
    dealRound(state, function(player) player.down[#player.down + 1] = deck.draw(state.deck) end)
    events[#events + 1] = { type = "street", street = state.street }
  end
  openBetting(state, events)
end

--- What this player owes the street. With nobody left to bet against, only what someone really bet has to be matched.
local function toCall(state, player)
  local target, others, top = state.current, 0, 0
  for _, other in ipairs(state.players) do
    if other ~= player then
      if canAct(other) then others = others + 1 end
      if isLive(other) then top = math.max(top, other.bet) end
    end
  end
  if others == 0 then target = math.min(target, top) end
  return math.max(0, target - player.bet)
end

--- After a betting action: pass the turn, or close the street.
local function moveOn(state, events)
  if count(state, isLive) == 1 then
    finishHand(state, events)
    return
  end
  local nextUp = leftOf(state, state.turn, function(player)
    return canAct(player) and (not player.acted or toCall(state, player) > 0)
  end)
  if nextUp then
    state.turn = nextUp
  else
    nextStreet(state, events)
  end
end

--- Deal a hand. entries are { seat, name, stack } in seat order, clockwise. button is a position in entries.
function M.new(entries, button, rng)
  local state = {
    players = {}, button = button, deck = deck.shuffle(deck.fresh(1), rng),
    ante = M.ANTE, bring = M.BRING_IN, small = M.SMALL, big = M.BIG, size = M.SMALL,
    phase = "bet", street = 3, current = 0, bets = 0, bringin = false,
  }
  for index, entry in ipairs(entries) do
    state.players[index] = { seat = entry.seat, name = entry.name, start = entry.stack, stack = entry.stack,
      bet = 0, total = 0, down = {}, up = {}, folded = false, allin = false, acted = false }
  end
  for _, player in ipairs(state.players) do put(player, state.ante) end
  dealRound(state, function(player) player.down[1] = deck.draw(state.deck) end)
  dealRound(state, function(player) player.down[2] = deck.draw(state.deck) end)
  dealRound(state, function(player) player.up[1] = deck.draw(state.deck) end)
  local events = { { type = "deal", street = 3 } }
  openBetting(state, events)
  return state, events
end

function M.done(state)
  return state.phase == "over"
end

function M.waitingOn(state)
  local player = state.turn and state.players[state.turn]
  return player and { player.seat } or {}
end

--- The bet a raise would take a player to. The first bet of a street is the size, whatever the bring-in was.
local function raiseTo(state)
  return state.bets == 0 and state.size or state.current + state.size
end

--- The buttons for this seat, on its turn.
function M.actions(state, seat)
  local player, index = find(state, seat)
  if not player or index ~= state.turn then return {} end
  local list = {}
  if state.bringin then
    local cost = math.min(state.bring, player.stack)
    list[1] = { id = "bringin", label = cost == player.stack and "ALL-IN" or "POST", color = "win", textColor = "ink",
      sub = "Bring-in " .. cost, cost = cost }
    if player.stack > state.bring then
      local full = math.min(state.size, player.stack)
      list[2] = { id = "raise", label = full == player.stack and "ALL-IN" or "BET", color = "blue", sub = "Complete " .. full, cost = full }
    end
    return list
  end

  local owes = toCall(state, player)
  if owes > 0 then
    list[#list + 1] = { id = "fold", label = "FOLD", color = "red" }
    local cost = math.min(owes, player.stack)
    list[#list + 1] = { id = "call", label = owes >= player.stack and "ALL-IN" or "CALL", color = "win", textColor = "ink",
      sub = tostring(cost), cost = cost }
  else
    list[#list + 1] = { id = "check", label = "CHECK", color = "win", textColor = "ink" }
  end
  local others = 0
  for position, other in ipairs(state.players) do
    if position ~= index and canAct(other) then others = others + 1 end
  end
  -- Owing more after acting can only come from an all-in too short to reopen the betting
  if state.bets < M.MAX_BETS and player.stack > owes and others > 0 and not (player.acted and owes > 0) then
    local cost = math.min(player.stack, raiseTo(state) - player.bet)
    local completing = state.bets == 0 and state.current > 0
    local word = state.bets == 0 and "BET" or "RAISE"
    list[#list + 1] = { id = "raise", label = cost == player.stack and "ALL-IN" or word, color = "blue",
      sub = (completing and "Complete " or "") .. cost, cost = cost }
  end
  return list
end

local function offered(state, seat, id)
  for _, action in ipairs(M.actions(state, seat)) do
    if action.id == id then return true end
  end
  return false
end

--- Play a seat's turn: bringin, fold, check, call or raise. Anything not on offer does nothing.
function M.act(state, seat, id)
  if seat == nil or not offered(state, seat, id) then return {} end
  local player = find(state, seat)
  local events = {}
  player.acted = true
  if id == "bringin" then
    put(player, state.bring)
    state.current = state.bring    -- a short bring-in still sets the price
    state.bringin = false
    player.last = player.allin and "ALL-IN" or "BRING-IN"
  elseif id == "fold" then
    player.folded = true
    player.last = "FOLD"
  elseif id == "check" then
    player.last = "CHECK"
  elseif id == "call" then
    put(player, toCall(state, player))
    player.last = player.allin and "ALL-IN" or "CALL"
  else
    local first = state.bets == 0
    local word = first and (state.street == 3 and "COMPLETE" or "BET") or "RAISE"
    local price = state.current
    put(player, raiseTo(state) - player.bet)
    state.current = math.max(state.current, player.bet)
    state.bringin = false
    player.last = player.allin and "ALL-IN" or word
    if first or (player.bet - price) * 2 >= state.size then
      state.bets = state.bets + 1
      for _, other in ipairs(state.players) do
        if other ~= player then other.acted = false end
      end
    end
  end
  events[#events + 1] = { type = "action", seat = seat, id = id }
  moveOn(state, events)
  return events
end

--- A player who is away: post the bring-in, check if it is free, or fold.
function M.auto(state, seat)
  if state.bringin then return "bringin" end
  local player = find(state, seat)
  if player and toCall(state, player) > 0 then return "fold" end
  return "check"
end

-- ------------------------------------------------------------------ what each seat may know

local function copy(list)
  local out = {}
  for index, value in ipairs(list) do out[index] = value end
  return out
end

--- Built field by field. Down-cards are shown only at a showdown, and only those still in. Folded cards go in the muck, for everyone
-- but the player who held them.
function M.viewFor(state, seat)
  local over = state.phase == "over"
  local turn = state.turn and state.players[state.turn]
  local view = {
    street = state.street, name = M.STREETS[state.street], over = over, uncontested = over and state.uncontested or false,
    pot = potTotal(state), current = state.current, size = state.size, bets = state.bets, maxBets = M.MAX_BETS,
    bringin = state.bringin, turn = turn and turn.seat or nil, community = state.community, players = {},
  }
  for index, player in ipairs(state.players) do
    local shown = {
      seat = player.seat, name = player.name, stack = player.stack, bet = player.bet, total = player.total,
      folded = player.folded, allin = player.allin, last = player.last, up = {},
      downs = player.folded and 0 or #player.down,
    }
    if not player.folded then
      shown.up = copy(player.up)
      shown.board = partName(player.up)
    end
    if over then
      shown.net = player.net
      if not state.uncontested and isLive(player) then
        shown.down = copy(player.down)
        shown.handName = player.handName
      end
    end
    view.players[index] = shown
  end
  local own = seat and find(state, seat)
  if own then
    view.me = {
      seat = own.seat, down = copy(own.down), up = copy(own.up), folded = own.folded,
      handName = handName(cardsOf(state, own)), toCall = toCall(state, own), stack = own.stack, total = own.total,
    }
  end
  return view
end

function M.nets(state)
  local nets = {}
  for _, player in ipairs(state.players) do nets[player.seat] = player.net or 0 end
  return nets
end

--- The table's line, or a seat's.
function M.result(state, seat)
  if state.phase ~= "over" then return { kind = "push", title = "HAND OVER", detail = "" } end
  local shared = table5.result(state)
  local player = seat and find(state, seat)
  if not player then
    local kind = shared.title == "SPLIT POT" and "push" or "win"
    return { kind = kind, title = shared.title, detail = shared.detail }
  end
  if player.net > 0 then
    return { kind = "win", title = "YOU WIN", detail = "+" .. player.net .. (player.handName and ("  " .. player.handName) or "") }
  end
  if player.net < 0 then
    return { kind = "lose", title = player.folded and "FOLDED" or "YOU LOSE", detail = player.net .. "  " .. shared.title }
  end
  return { kind = "push", title = "EVEN", detail = shared.title }
end

--- All this seat put in, for the stats.
function M.risk(state, seat)
  local player = find(state, seat)
  return player and player.total or 0
end

return M
