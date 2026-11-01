-- games/blackjack/rules.lua
-- Blackjack for up to eight seats against one dealer hand and one shoe. Pure: no screen, no sound, no money.
-- The table is Games/Blackjack's, card for card. Six decks that last across rounds, dealer hits soft 17 and peeks, naturals pay 3:2
-- (the win is floored to whole tokens), double on a hard 11 only, one split of equal ranks, no double after a split, split aces get
-- one card each, and 21 stands by itself. No insurance, no surrender.
-- blackjack_rules.lua is not installed on Big Table, so its numbers and sums are repeated here. Tests/group_blackjack_test.lua plays
-- this file against it hand for hand: with one seat the two must agree on every button, card and net.
--
-- Every card a seat holds is face up, as on a real shoe table, so the only secrets are the hole card and the shoe.
-- The dealer's whole turn is one move, the last of the round, so the hole card turns over after the money has moved.

local deck = require("lib.casino.deck")

local M = {
  DECKS = 6,
  RESHUFFLE_BELOW = 156,   -- cards left in the shoe below which a new round starts on a fresh one
  NATURAL_PAYS = { 3, 2 },
  DEALER_HITS_SOFT = 17,
  DOUBLE_ON = 11,
  MAX_HANDS = 2,
}

--- A hand's total, and whether an ace is still counting as eleven.
function M.total(cards)
  local total, aces = 0, 0
  for _, card in ipairs(cards) do
    local rank = deck.rank(card)
    if rank == deck.ACE then
      total, aces = total + 1, aces + 1
    else
      total = total + math.min(rank, 10)
    end
  end
  if aces > 0 and total + 10 <= 21 then return total + 10, true end
  return total, false
end

local function twentyOneOnTwo(cards)
  return #cards == 2 and M.total(cards) == 21
end

--- A split hand can make two-card 21 too, and it is not a natural.
local function isNatural(hand)
  return not hand.split and twentyOneOnTwo(hand.cards)
end

local function naturalWin(bet)
  return math.floor(bet * M.NATURAL_PAYS[1] / M.NATURAL_PAYS[2])
end

--- The biggest net win of a bet: a win on both split hands, or a won double. A natural pays less than either.
function M.maxWin(entry)
  return entry.bet * 2
end

local function takeShoe(keep, rng)
  local shoe = keep.shoe
  keep.shoe = nil
  if shoe and #shoe >= M.RESHUFFLE_BELOW then return shoe, false end
  keep.shuffled = true -- the engine keeps this round's seed as the shoe's, secret until the shoe ends
  return deck.shuffle(deck.fresh(M.DECKS), rng), true
end

local function find(state, seat)
  for _, player in ipairs(state.players) do
    if player.seat == seat then return player end
  end
  return nil
end

--- Whoever may act now, or nil.
local function current(state)
  if state.phase ~= "play" then return nil end
  return state.players[state.turn]
end

--- Move to the next hand still waiting, this seat's or a later one's, or hand over to the dealer.
local function advance(state, events)
  for position = state.turn, #state.players do
    local player = state.players[position]
    for index = player.active, #player.hands do
      if not player.hands[index].done then
        local moved = position ~= state.turn or index ~= player.active
        state.turn, player.active = position, index
        if moved then events[#events + 1] = { type = "turn", seat = player.seat, hand = index } end
        return
      end
    end
  end
  state.phase = "dealer"
end

--- Deal the round: a card to each seat, the up card, a card to each seat, the hole card. No event says what any card is, and step is
-- how many of these cards are down so far, which is how a view deals them out one by one.
function M.new(entries, _, rng, keep)
  local shoe, fresh = takeShoe(keep or {}, rng)
  local state = { cards = shoe, dealer = {}, players = {}, turn = 1, phase = "play" }
  for index, entry in ipairs(entries) do
    state.players[index] = { seat = entry.seat, name = entry.name, bet = entry.bet, active = 1, hands = { { cards = {}, bet = entry.bet } } }
  end
  local events, step = { { type = "start", fresh = fresh, step = 0 } }, 0
  for _ = 1, 2 do
    for _, player in ipairs(state.players) do
      local hand = player.hands[1]
      hand.cards[#hand.cards + 1] = deck.draw(shoe)
      step = step + 1
      events[#events + 1] = { type = "deal", step = step }
    end
    state.dealer[#state.dealer + 1] = deck.draw(shoe)
    step = step + 1
    events[#events + 1] = { type = "deal", step = step }
  end

  local up = deck.rank(state.dealer[1])
  if up == deck.ACE or up >= 10 then events[#events + 1] = { type = "peek" } end
  for _, player in ipairs(state.players) do
    if isNatural(player.hands[1]) then player.hands[1].done = true end
  end
  if twentyOneOnTwo(state.dealer) then
    -- The peek found it. Nobody gets to act, whether or not they hold a natural
    state.phase = "dealer"
  else
    advance(state, events)
  end
  return state, events
end

function M.waitingOn(state)
  local player = current(state)
  return player and { player.seat } or {}
end

local function canDouble(player)
  local hand = player.hands[player.active]
  local total, soft = M.total(hand.cards)
  return #player.hands == 1 and #hand.cards == 2 and total == M.DOUBLE_ON and not soft
end

local function canSplit(player)
  local hand = player.hands[player.active]
  return #player.hands < M.MAX_HANDS and #hand.cards == 2 and deck.rank(hand.cards[1]) == deck.rank(hand.cards[2])
end

function M.actions(state, seat)
  local player = current(state)
  if not player or player.seat ~= seat then return {} end
  local bet = player.hands[player.active].bet
  local list = {
    { id = "hit", label = "HIT", color = "win", textColor = "ink" },
    { id = "stand", label = "STAND", color = "red" },
  }
  if canDouble(player) then
    list[#list + 1] = { id = "double", label = "DOUBLE", color = "gold", textColor = "ink", cost = bet, sub = "+" .. bet }
  end
  if canSplit(player) then
    list[#list + 1] = { id = "split", label = "SPLIT", color = "blue", cost = bet, sub = "+" .. bet }
  end
  return list
end

local function dealerShouldHit(cards)
  local total, soft = M.total(cards)
  return total < M.DEALER_HITS_SOFT or (total == M.DEALER_HITS_SOFT and soft)
end

--- What one finished hand earns against the dealer.
local function judge(state, hand)
  local total = M.total(hand.cards)
  local dealer = M.total(state.dealer)
  local dealerNatural = twentyOneOnTwo(state.dealer)
  if total > 21 then return "bust", -hand.bet end
  if isNatural(hand) then
    if dealerNatural then return "push", 0 end
    return "blackjack", naturalWin(hand.bet)
  end
  if dealerNatural then return "lose", -hand.bet end
  if dealer > 21 or total > dealer then return "win", hand.bet end
  if total == dealer then return "push", 0 end
  return "lose", -hand.bet
end

--- Whether any hand still needs the dealer to make a total. A bust has lost and a natural has won.
local function anyoneInPlay(state)
  if twentyOneOnTwo(state.dealer) then return false end
  for _, player in ipairs(state.players) do
    for _, hand in ipairs(player.hands) do
      if M.total(hand.cards) <= 21 and not isNatural(hand) then return true end
    end
  end
  return false
end

--- Turn the hole card, draw if anything is still in play, and judge every hand. shown is how many dealer cards are up after each event.
local function dealerTurn(state, events)
  state.phase = "over"
  events[#events + 1] = { type = "reveal", shown = 2 }
  if anyoneInPlay(state) then
    while dealerShouldHit(state.dealer) do
      state.dealer[#state.dealer + 1] = deck.draw(state.cards)
      events[#events + 1] = { type = "draw", shown = #state.dealer }
    end
  end
  for _, player in ipairs(state.players) do
    for _, hand in ipairs(player.hands) do hand.result, hand.net = judge(state, hand) end
  end
  events[#events + 1] = { type = "outcome" }
end

local function hit(state, player, events)
  local hand = player.hands[player.active]
  hand.cards[#hand.cards + 1] = deck.draw(state.cards)
  events[#events + 1] = { type = "hit", seat = player.seat, hand = player.active }
  if M.total(hand.cards) >= 21 then
    hand.done = true
    advance(state, events)
  end
end

local function double(state, player, events)
  local hand = player.hands[player.active]
  hand.bet = hand.bet * 2
  hand.doubled = true
  hand.cards[#hand.cards + 1] = deck.draw(state.cards)
  events[#events + 1] = { type = "double", seat = player.seat, hand = player.active }
  hand.done = true
  advance(state, events)
end

--- Each hand gets its second card at once, so both stay on the table as whole hands.
local function split(state, player, events)
  local first = player.hands[1]
  local second = { cards = { table.remove(first.cards) }, bet = first.bet, split = true }
  first.split = true
  player.hands[2] = second
  first.cards[2] = deck.draw(state.cards)
  second.cards[2] = deck.draw(state.cards)
  events[#events + 1] = { type = "split", seat = player.seat }
  local aces = deck.rank(first.cards[1]) == deck.ACE
  for _, hand in ipairs(player.hands) do
    if aces or M.total(hand.cards) >= 21 then hand.done = true end
  end
  advance(state, events)
end

function M.act(state, seat, id)
  local events = {}
  if seat == nil then
    if id == "dealer" and state.phase == "dealer" then dealerTurn(state, events) end
    return events
  end
  local player = current(state)
  if not player or player.seat ~= seat then return events end
  if id == "hit" then
    hit(state, player, events)
  elseif id == "stand" then
    player.hands[player.active].done = true
    events[#events + 1] = { type = "stand", seat = seat, hand = player.active }
    advance(state, events)
  elseif id == "double" and canDouble(player) then
    double(state, player, events)
  elseif id == "split" and canSplit(player) then
    split(state, player, events)
  end
  return events
end

--- A missing player stands. With seat nil it is the dealer's own turn.
function M.auto(_, seat)
  if seat == nil then return "dealer" end
  return "stand"
end

local function copy(list)
  local out = {}
  for index, value in ipairs(list) do out[index] = value end
  return out
end

--- One hand as anyone may see it. All of a seat's cards are face up.
local function handView(hand, over)
  local total, soft = M.total(hand.cards)
  local view = { cards = copy(hand.cards), bet = hand.bet, total = total, soft = soft, natural = isNatural(hand),
    doubled = hand.doubled == true, split = hand.split == true }
  if over then view.result, view.net = hand.result, hand.net end
  return view
end

--- What this seat may know. It is the public view and which seat is theirs: the hole card and the shoe stay out until the round is over.
function M.viewFor(state, seat)
  local over = state.phase == "over"
  local shown = over and state.dealer or { state.dealer[1] }
  local view = { phase = state.phase, down = not over, dealer = copy(shown), runs = {}, seats = {},
    left = state.left or #state.cards, turn = false, turnHand = false, turnName = false, me = false }
  -- The dealer's total after each card up, so a view can count them over as they turn
  for count = 1, #shown do
    view.runs[count] = M.total({ unpack(shown, 1, count) })
  end
  for index, player in ipairs(state.players) do
    local hands = {}
    for number, hand in ipairs(player.hands) do hands[number] = handView(hand, over) end
    view.seats[index] = { seat = player.seat, name = player.name, active = player.active, hands = hands }
  end
  local acting = current(state)
  if acting then view.turn, view.turnHand, view.turnName = acting.seat, acting.active, acting.name end
  if seat ~= nil and find(state, seat) then view.me = seat end
  return view
end

function M.done(state)
  return state.phase == "over"
end

function M.nets(state)
  local nets = {}
  for _, player in ipairs(state.players) do
    local net = 0
    for _, hand in ipairs(player.hands) do net = net + (hand.net or 0) end
    nets[player.seat] = net
  end
  return nets
end

--- Everything this seat staked, doubles and splits included.
function M.risk(state, seat)
  local player = find(state, seat)
  if not player then return 0 end
  local total = 0
  for _, hand in ipairs(player.hands) do total = total + hand.bet end
  return total
end

local WORDS = { blackjack = "blackjack", win = "wins", push = "pushes", lose = "loses", bust = "busts" }

local function splitResult(player, net)
  local parts = {}
  for index, hand in ipairs(player.hands) do parts[index] = ("Hand %d %s"):format(index, WORDS[hand.result]) end
  local detail = table.concat(parts, ", ")
  if net > 0 then return { kind = "win", title = "SPLIT WON", detail = detail } end
  if net < 0 then return { kind = "lose", title = "SPLIT LOST", detail = detail } end
  return { kind = "push", title = "SPLIT EVEN", detail = detail }
end

local function seatResult(state, player)
  local net = M.nets(state)[player.seat]
  if #player.hands > 1 then return splitResult(player, net) end
  local hand = player.hands[1]
  local total, dealer = M.total(hand.cards), M.total(state.dealer)
  local dealerNatural = twentyOneOnTwo(state.dealer)
  local doubled = hand.doubled and " on a double" or ""
  if hand.result == "blackjack" then
    return { kind = "win", title = "BLACKJACK", detail = ("Pays %d to %d"):format(M.NATURAL_PAYS[1], M.NATURAL_PAYS[2]) }
  elseif hand.result == "bust" then
    return { kind = "lose", title = "BUST", detail = "Over 21 with " .. total .. doubled }
  elseif hand.result == "push" then
    return { kind = "push", title = "PUSH", detail = dealerNatural and "Both have blackjack" or ("Both have " .. total) }
  elseif hand.result == "win" then
    if dealer > 21 then return { kind = "win", title = "DEALER BUST", detail = "Dealer went over with " .. dealer .. doubled } end
    return { kind = "win", title = "YOU WIN", detail = total .. " beats " .. dealer .. doubled }
  end
  if dealerNatural then return { kind = "lose", title = "DEALER BLACKJACK", detail = "The hole card made 21" } end
  return { kind = "lose", title = "DEALER WINS", detail = dealer .. " beats " .. total .. doubled }
end

--- The table's line: what the dealer made and how the seats did.
local function tableResult(state)
  local won, pushed, lost = 0, 0, 0
  for _, net in pairs(M.nets(state)) do
    if net > 0 then won = won + 1 elseif net < 0 then lost = lost + 1 else pushed = pushed + 1 end
  end
  local dealer = M.total(state.dealer)
  local title = "DEALER HAS " .. dealer
  if twentyOneOnTwo(state.dealer) then title = "DEALER BLACKJACK" elseif dealer > 21 then title = "DEALER BUST" end
  local parts = {}
  if won > 0 then parts[#parts + 1] = won .. " won" end
  if pushed > 0 then parts[#parts + 1] = pushed .. " pushed" end
  if lost > 0 then parts[#parts + 1] = lost .. " lost" end
  return { kind = won > 0 and "win" or (lost > 0 and "lose" or "push"), title = title, detail = table.concat(parts, ", ") }
end

function M.result(state, seat)
  if state.phase ~= "over" then return { kind = "push", title = "ROUND OVER", detail = "" } end
  if seat == nil then return tableResult(state) end
  local player = find(state, seat)
  if not player then return { kind = "push", title = "ROUND OVER", detail = "" } end
  return seatResult(state, player)
end

--- Hand the shoe to the next round. It leaves the state, so the two never share a table.
function M.finish(state, keep)
  keep.shoe = state.cards
  state.left = #state.cards
  state.cards = {}
end

return M
