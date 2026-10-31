-- pokertable_rules.lua
-- Five-card draw for 2 to 6 players, fixed limit. Pure: no screen, no sound, no money.
--
-- A hand: everyone antes, five cards each, a betting round at the small bet, one draw, a betting round at the big bet,
-- showdown. A round allows a bet and three raises. A player may draw up to 3 cards, or 4 when the card they keep is an ace.
-- With at most four aces, six players can never draw more than the 22 cards left in the deck.
-- A raise too short to be a full raise is allowed as an all-in, and counts as a raise.
--
-- Chips are tracked per player: stack behind, bet this round, total in the pot. Side pots are worked out from the totals
-- at showdown, so an all-in of any size needs no special handling while the hand runs.
-- Odd chips in a split go to the first winner left of the button.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")

local M = {
  ANTE = 5,
  SMALL = 10,
  BIG = 20,
  MAX_BETS = 4,         -- a bet and three raises, each betting round
  MAX_DISCARD = 3,
  MAX_DISCARD_ACE = 4,  -- keeping an ace
  HAND_SIZE = 5,
  MAX_SEATS = 6,
  MIN_PLAYERS = 2,
  MIN_BUY = 100,
  MAX_STACK = 5000,
}

local function canAct(player)
  return not player.folded and not player.allin
end

local function isLive(player)
  return not player.folded
end

--- The first player left of `from` (clockwise, by list order) who passes the test.
local function leftOf(state, from, test)
  local count = #state.players
  for step = 1, count do
    local index = (from + step - 1) % count + 1
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

--- Move chips from a stack to the pot. A short stack puts in what it has and is all-in.
local function put(player, amount)
  local paid = math.min(amount, player.stack)
  player.stack = player.stack - paid
  player.bet = player.bet + paid
  player.total = player.total + paid
  if player.stack == 0 then player.allin = true end
  return paid
end

-- ------------------------------------------------------------------ pots

--- Side pots from what each player has in. Players carry total and folded. Returns { {amount, eligible = {index...}} },
-- main pot first. Chips above the highest live player's total can only be folded chips: they join the last pot.
function M.pots(players)
  local levels, seen = {}, {}
  for _, player in ipairs(players) do
    if not player.folded and player.total > 0 and not seen[player.total] then
      seen[player.total] = true
      levels[#levels + 1] = player.total
    end
  end
  table.sort(levels)

  local pots, reached = {}, 0
  for _, level in ipairs(levels) do
    local pot = { amount = 0, eligible = {} }
    for index, player in ipairs(players) do
      pot.amount = pot.amount + math.max(0, math.min(player.total, level) - reached)
      if not player.folded and player.total >= level then pot.eligible[#pot.eligible + 1] = index end
    end
    pots[#pots + 1] = pot
    reached = level
  end

  local stray = 0
  for _, player in ipairs(players) do
    stray = stray + math.max(0, player.total - reached)
  end
  if stray > 0 then
    if #pots == 0 then
      local eligible = {}
      for index, player in ipairs(players) do
        if not player.folded then eligible[#eligible + 1] = index end
      end
      pots[1] = { amount = 0, eligible = eligible }
    end
    pots[#pots].amount = pots[#pots].amount + stray
  end
  return pots
end

--- Hand out pots: the best score among those eligible wins, ties split. Sets won on each player and winners, share and
-- odd on each pot. Winners are listed from the button's left, and the first of them takes the odd chips.
function M.award(pots, players, button)
  for _, player in ipairs(players) do player.won = 0 end
  local total = #players
  for _, pot in ipairs(pots) do
    local best = nil
    local inPot = {}
    for _, index in ipairs(pot.eligible) do
      inPot[index] = true
      local score = players[index].score or 0
      if not best or score > best then best = score end
    end
    pot.winners = {}
    for step = 1, total do
      local index = (button + step - 1) % total + 1
      if inPot[index] and (players[index].score or 0) == best then pot.winners[#pot.winners + 1] = index end
    end
    local winners = #pot.winners
    pot.share = math.floor(pot.amount / winners)
    pot.odd = pot.amount - pot.share * winners
    for position, index in ipairs(pot.winners) do
      players[index].won = players[index].won + pot.share + (position == 1 and pot.odd or 0)
    end
  end
end

-- ------------------------------------------------------------------ the hand

local nextStreet

local function finishHand(state, events)
  state.phase = "over"
  state.turn = nil
  state.uncontested = count(state, isLive) == 1
  if not state.uncontested then
    for _, player in ipairs(state.players) do
      if not player.folded then
        player.score = poker.evaluate(player.hand)
        player.handName = poker.describe(player.score)
      end
    end
  end
  state.pots = M.pots(state.players)
  M.award(state.pots, state.players, state.button)
  for _, player in ipairs(state.players) do
    player.net = player.won - player.total
    player.stack = player.start + player.net
  end
  events[#events + 1] = { type = "showdown", uncontested = state.uncontested }
end

local function openBetting(state, events, phase)
  state.phase = phase
  state.size = phase == "bet1" and state.small or state.big
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
  state.turn = leftOf(state, state.button, canAct)
  events[#events + 1] = { type = "street", phase = phase }
end

local function openDraw(state, events)
  state.phase = "draw"
  for _, player in ipairs(state.players) do
    player.acted = false
    player.last = nil
  end
  state.turn = leftOf(state, state.button, isLive)
  events[#events + 1] = { type = "street", phase = "draw" }
end

nextStreet = function(state, events)
  if state.phase == "bet1" then
    openDraw(state, events)
  elseif state.phase == "draw" then
    openBetting(state, events, "bet2")
  else
    finishHand(state, events)
  end
end

--- After a betting action: pass the turn, or close the round.
local function moveOn(state, events)
  if count(state, isLive) == 1 then
    finishHand(state, events)
    return
  end
  local nextUp = leftOf(state, state.turn, function(player)
    return canAct(player) and (not player.acted or player.bet < state.current)
  end)
  if nextUp then
    state.turn = nextUp
  else
    nextStreet(state, events)
  end
end

--- Deal a hand. entries: { {name, stack, seat} } in seat order, clockwise. button: an index into entries.
function M.new(entries, button, rng)
  local state = {
    players = {},
    button = button,
    deck = deck.shuffle(deck.fresh(1), rng),
    ante = M.ANTE,
    small = M.SMALL,
    big = M.BIG,
    current = 0,
    bets = 0,
  }
  for index, entry in ipairs(entries) do
    state.players[index] = {
      name = entry.name, seat = entry.seat, start = entry.stack, stack = entry.stack,
      bet = 0, total = 0, hand = {}, folded = false, allin = false, acted = false,
    }
  end
  for _, player in ipairs(state.players) do
    put(player, state.ante)
  end
  local total = #state.players
  for _ = 1, M.HAND_SIZE do
    for step = 1, total do
      local player = state.players[(button + step - 1) % total + 1]
      player.hand[#player.hand + 1] = deck.draw(state.deck)
    end
  end
  local events = { { type = "deal" } }
  openBetting(state, events, "bet1")
  return state, events
end

function M.done(state)
  return state.phase == "over"
end

--- Whose turn it is, or nil.
function M.actor(state)
  local player = state.turn and state.players[state.turn]
  return player and player.name or nil
end

function M.find(state, name)
  for index, player in ipairs(state.players) do
    if player.name == name then return player, index end
  end
  return nil
end

--- Everything in the pot right now.
function M.potTotal(state)
  local total = 0
  for _, player in ipairs(state.players) do
    total = total + player.total
  end
  return total
end

--- What the player to act must add to stay in.
function M.toCall(state)
  local player = state.players[state.turn]
  return math.max(0, state.current - player.bet)
end

--- The most cards a hand may throw away, given what would be kept.
function M.legalDiscard(hand, discards)
  local thrown, seen = 0, {}
  for _, position in ipairs(discards) do
    if position < 1 or position > #hand or seen[position] then return false end
    seen[position] = true
    thrown = thrown + 1
  end
  if thrown <= M.MAX_DISCARD then return true end
  if thrown > M.MAX_DISCARD_ACE then return false end
  for position, card in ipairs(hand) do
    if not seen[position] and deck.rank(card) == deck.ACE then return true end
  end
  return false
end

--- What the player to act may do. In the draw this is standing pat; the discards are chosen on the cards.
function M.actions(state)
  local list = {}
  if not state.turn then return list end
  if state.phase == "draw" then
    list[1] = { id = "draw", label = "STAND PAT", color = "blue" }
    return list
  end
  local player = state.players[state.turn]
  local toCall = M.toCall(state)
  if toCall > 0 then
    list[#list + 1] = { id = "fold", label = "FOLD", color = "red" }
    local allIn = toCall >= player.stack
    list[#list + 1] = { id = "call", label = allIn and "ALL-IN" or "CALL", color = "win", textColor = "ink",
      sub = tostring(math.min(toCall, player.stack)) }
  else
    list[#list + 1] = { id = "check", label = "CHECK", color = "win", textColor = "ink" }
  end
  local others = 0
  for index, other in ipairs(state.players) do
    if index ~= state.turn and canAct(other) then others = others + 1 end
  end
  if state.bets < M.MAX_BETS and player.stack > toCall and others > 0 then
    local cost = math.min(player.stack, toCall + state.size)
    local word = state.current == 0 and "BET" or "RAISE"
    list[#list + 1] = { id = "raise", label = cost == player.stack and "ALL-IN" or word, color = "blue",
      sub = tostring(cost) }
  end
  return list
end

local function isAllowed(state, id)
  for _, action in ipairs(M.actions(state)) do
    if action.id == id then return true end
  end
  return false
end

local function drawCards(state, player, digits, events)
  local positions = {}
  for digit in digits:gmatch("%d") do positions[#positions + 1] = tonumber(digit) end
  if not M.legalDiscard(player.hand, positions) then return false end
  for _, position in ipairs(positions) do
    player.hand[position] = deck.draw(state.deck)
  end
  player.drew = #positions
  player.last = #positions == 0 and "PAT" or ("DREW " .. #positions)
  player.acted = true
  events[#events + 1] = { type = "draw", who = player.name, count = #positions }
  return true
end

--- Play the turn. id: fold, check, call, raise, or "draw" followed by the card positions, such as draw125.
-- Anything not allowed right now does nothing.
function M.act(state, id)
  local events = {}
  if not state.turn then return events end
  local player = state.players[state.turn]

  if state.phase == "draw" then
    local digits = tostring(id):match("^draw(%d*)$")
    if not digits or not drawCards(state, player, digits, events) then return {} end
    local nextUp = leftOf(state, state.turn, function(other) return isLive(other) and not other.acted end)
    if nextUp then
      state.turn = nextUp
    else
      nextStreet(state, events)
    end
    return events
  end

  if not isAllowed(state, id) then return events end
  player.acted = true
  if id == "fold" then
    player.folded = true
    player.last = "FOLD"
  elseif id == "check" then
    player.last = "CHECK"
  elseif id == "call" then
    local paid = put(player, M.toCall(state))
    player.last = player.allin and "ALL-IN" or "CALL"
    events[#events + 1] = { type = "chips", who = player.name, amount = paid }
  else
    local paid = put(player, M.toCall(state) + state.size)
    state.current = math.max(state.current, player.bet)
    state.bets = state.bets + 1
    player.last = player.allin and "ALL-IN" or (state.bets == 1 and "BET" or "RAISE")
    for _, other in ipairs(state.players) do
      if other ~= player then other.acted = false end
    end
    events[#events + 1] = { type = "chips", who = player.name, amount = paid }
  end
  events[#events + 1] = { type = "action", who = player.name, id = id }
  moveOn(state, events)
  return events
end

--- A player who is away: check if it is free, fold if not, stand pat in the draw.
function M.auto(state)
  if state.phase == "draw" then return "draw" end
  if M.toCall(state) == 0 then return "check" end
  return "fold"
end

--- Each player's result for the hand. Always adds up to zero.
function M.nets(state)
  local nets = {}
  for _, player in ipairs(state.players) do
    nets[player.name] = player.net or 0
  end
  return nets
end

--- How the hand ended, for the banner.
function M.result(state)
  local up, last = {}, nil
  for _, player in ipairs(state.players) do
    if player.net > 0 then
      up[#up + 1] = player
      last = player
    end
  end
  local pot = M.potTotal(state)
  if state.uncontested then
    return { title = (last and last.name or "NOBODY") .. " WINS", detail = "Everyone else folded", pot = pot }
  end

  -- A pot with one player eligible is only an uncalled bet coming back, so it is not something anybody won
  local contested = {}
  for _, entry in ipairs(state.pots) do
    if #entry.eligible > 1 then contested[#contested + 1] = entry end
  end
  if #contested > 1 then
    local parts = {}
    for _, entry in ipairs(contested) do
      local names = {}
      for _, index in ipairs(entry.winners) do names[#names + 1] = state.players[index].name end
      parts[#parts + 1] = table.concat(names, " & ") .. " " .. entry.amount
    end
    return { title = "SIDE POTS", detail = table.concat(parts, "   "), pot = pot }
  end

  if #up == 1 then
    local amount = contested[1] and contested[1].amount or pot
    return { title = last.name .. " WINS", detail = last.handName .. " takes a pot of " .. amount, pot = pot }
  end
  if #up == 0 then return { title = "SPLIT POT", detail = "Everyone gets their chips back", pot = pot } end
  local parts = {}
  for _, player in ipairs(up) do
    parts[#parts + 1] = player.name .. " +" .. player.net
  end
  return { title = "POT SPLIT", detail = table.concat(parts, "   "), pot = pot }
end

-- ------------------------------------------------------------------ settlement

--- What the host is holding for players: the sum of everything owed. Every hand's nets add up to zero, so when nothing
-- is owed the host is exactly even, and this is how far ahead of even the host is right now. It can never go below
-- zero, because a payout is never bigger than this.
function M.holding(owed)
  local total = 0
  for _, amount in pairs(owed) do
    total = total + amount
  end
  return total
end

--- Settle what is owed, for the named players, in the order that keeps the host safe:
--   1. Collect from each player who owes, by name, taking what they have.
--   2. Pay each player who is owed, biggest first, never more than the host is holding from step 1 and before.
-- A winner whose loser could not pay is paid what was collected and keeps the rest owed. It comes when the loser pays.
-- move(name, amount) tries to move tokens, to the player when positive and from them when negative, and returns what
-- moved. owed is updated in place.
function M.settle(owed, names, move)
  local wanted = {}
  for _, name in ipairs(names) do wanted[name] = true end

  local function apply(name, amount)
    local moved = move(name, amount) or 0
    local left = owed[name] - moved
    owed[name] = left ~= 0 and left or nil
  end

  local debtors, creditors = {}, {}
  for name, amount in pairs(owed) do
    if wanted[name] and amount < 0 then debtors[#debtors + 1] = name end
    if wanted[name] and amount > 0 then creditors[#creditors + 1] = name end
  end
  table.sort(debtors)
  table.sort(creditors, function(a, b)
    if owed[a] ~= owed[b] then return owed[a] > owed[b] end
    return a < b
  end)

  for _, name in ipairs(debtors) do
    apply(name, owed[name])
  end
  for _, name in ipairs(creditors) do
    local room = math.min(owed[name], M.holding(owed))
    if room > 0 then apply(name, room) end
  end
end

return M
