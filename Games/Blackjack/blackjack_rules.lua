-- blackjack_rules.lua
-- Six-deck blackjack. Pure: no screen, no sound, no money.
-- The shoe lasts across rounds and is only reshuffled between them. Dealer hits soft 17 and peeks, naturals pay 3:2
-- (the win is floored to whole tokens), double on a hard 11 only, one split of equal ranks, no double after a split,
-- split aces get one card each, and 21 stands by itself. No insurance, no surrender.
-- A round with a natural on either side stops at one action, the reveal, so the engine settles it the usual way.

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

--- Two cards making 21. A split hand can do this too, and it is not a natural: see isNaturalHand.
function M.isTwentyOneOnTwo(cards)
  return #cards == 2 and M.total(cards) == 21
end

local function isNaturalHand(hand)
  return not hand.split and M.isTwentyOneOnTwo(hand.cards)
end

M.isNaturalHand = isNaturalHand

--- The biggest net win of a bet: a win on both split hands, or a won double. A natural pays less than either.
function M.maxWin(bet)
  return bet * 2
end

local function naturalWin(bet)
  return math.floor(bet * M.NATURAL_PAYS[1] / M.NATURAL_PAYS[2])
end

local function takeShoe(keep, rng)
  local shoe = keep.shoe
  keep.shoe = nil
  if shoe and #shoe >= M.RESHUFFLE_BELOW then return shoe, false end
  keep.shuffled = true -- the engine keeps this round's seed as the shoe's, secret until the shoe ends
  return deck.shuffle(deck.fresh(M.DECKS), rng), true
end

local function dealTo(state, hand, index, events)
  local card = deck.draw(state.cards)
  hand.cards[#hand.cards + 1] = card
  events[#events + 1] = { type = "deal", who = "player", hand = index, card = card }
end

--- Deal the round. The hole card goes out face down: no event ever carries it until the reveal.
function M.new(bet, rng, keep, _)
  local shoe, fresh = takeShoe(keep or {}, rng)
  local state = {
    bet = bet, cards = shoe, active = 1, dealer = {},
    hands = { { cards = {}, bet = bet } },
  }
  local events = { { type = "start", fresh = fresh } }
  local hand = state.hands[1]

  dealTo(state, hand, 1, events)
  state.dealer[1] = deck.draw(shoe)
  events[#events + 1] = { type = "deal", who = "dealer", card = state.dealer[1] }
  dealTo(state, hand, 1, events)
  state.dealer[2] = deck.draw(shoe)
  events[#events + 1] = { type = "deal", who = "dealer", hole = true }

  local up = math.min(deck.rank(state.dealer[1]), 10)
  local peeks = deck.rank(state.dealer[1]) == deck.ACE or up == 10
  if peeks then events[#events + 1] = { type = "peek" } end
  if isNaturalHand(hand) or (peeks and M.isTwentyOneOnTwo(state.dealer)) then state.hold = true end
  return state, events
end

local function canDouble(state)
  local hand = state.hands[state.active]
  local total, soft = M.total(hand.cards)
  return #state.hands == 1 and #hand.cards == 2 and total == M.DOUBLE_ON and not soft
end

local function canSplit(state)
  local hand = state.hands[state.active]
  return #state.hands < M.MAX_HANDS and #hand.cards == 2 and deck.rank(hand.cards[1]) == deck.rank(hand.cards[2])
end

function M.actions(state)
  if state.over then return {} end
  if state.hold then
    return { { id = "stand", label = "REVEAL", color = "gold", textColor = "ink" } }
  end
  local bet = state.hands[state.active].bet
  local list = {
    { id = "hit", label = "HIT", color = "win", textColor = "ink" },
    { id = "stand", label = "STAND", color = "red" },
  }
  if canDouble(state) then
    list[#list + 1] = { id = "double", label = "DOUBLE", color = "gold", textColor = "ink", cost = bet, sub = "+" .. bet }
  end
  if canSplit(state) then
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
  local dealerNatural = M.isTwentyOneOnTwo(state.dealer)
  if total > 21 then return "bust", -hand.bet end
  if isNaturalHand(hand) then
    if dealerNatural then return "push", 0 end
    return "blackjack", naturalWin(hand.bet)
  end
  if dealerNatural then return "lose", -hand.bet end
  if dealer > 21 or total > dealer then return "win", hand.bet end
  if total == dealer then return "push", 0 end
  return "lose", -hand.bet
end

--- The player is finished: turn the hole card, draw if anything is still in play, and judge every hand.
local function finishRound(state, events)
  state.over = true
  state.hold = nil
  events[#events + 1] = { type = "reveal", card = state.dealer[2] }
  local drawing = not M.isTwentyOneOnTwo(state.dealer)
  local alive = false
  for _, hand in ipairs(state.hands) do
    if M.total(hand.cards) <= 21 then alive = true end
    if isNaturalHand(hand) then drawing = false end
  end
  if drawing and alive then
    while dealerShouldHit(state.dealer) do
      local card = deck.draw(state.cards)
      state.dealer[#state.dealer + 1] = card
      events[#events + 1] = { type = "deal", who = "dealer", card = card }
    end
  end
  local outcomes = {}
  for i, hand in ipairs(state.hands) do
    hand.result, hand.net = judge(state, hand)
    outcomes[i] = { result = hand.result, net = hand.net }
  end
  events[#events + 1] = { type = "outcome", hands = outcomes }
end

--- Move to the next hand still waiting, or finish the round.
local function advance(state, events)
  for i = state.active, #state.hands do
    if not state.hands[i].done then
      if i ~= state.active then
        state.active = i
        events[#events + 1] = { type = "turn", hand = i }
      end
      return
    end
  end
  finishRound(state, events)
end

local function hit(state, events)
  local hand = state.hands[state.active]
  dealTo(state, hand, state.active, events)
  if M.total(hand.cards) >= 21 then
    hand.done = true
    advance(state, events)
  end
end

local function double(state, events)
  local hand = state.hands[state.active]
  hand.bet = hand.bet * 2
  hand.doubled = true
  events[#events + 1] = { type = "double", hand = state.active, bet = hand.bet }
  dealTo(state, hand, state.active, events)
  hand.done = true
  advance(state, events)
end

--- Each hand gets its second card at once, so both stay on the table as whole hands.
local function split(state, events)
  local first = state.hands[1]
  local second = { cards = { table.remove(first.cards) }, bet = first.bet, split = true }
  first.split = true
  state.hands[2] = second
  events[#events + 1] = { type = "split" }
  dealTo(state, first, 1, events)
  dealTo(state, second, 2, events)
  local aces = deck.rank(first.cards[1]) == deck.ACE
  for _, hand in ipairs(state.hands) do
    if aces or M.total(hand.cards) >= 21 then hand.done = true end
  end
  advance(state, events)
end

function M.act(state, id, _)
  local events = {}
  if state.over then return events end
  if state.hold then
    finishRound(state, events)
  elseif id == "hit" then
    hit(state, events)
  elseif id == "stand" then
    state.hands[state.active].done = true
    advance(state, events)
  elseif id == "double" and canDouble(state) then
    double(state, events)
  elseif id == "split" and canSplit(state) then
    split(state, events)
  end
  return events
end

--- Nobody at the table: stand. That is also the way past a reveal.
function M.auto()
  return "stand"
end

local function offeredBy(state)
  local offered = {}
  for _, action in ipairs(M.actions(state)) do offered[action.id] = true end
  return offered
end

local function shouldSplit(rank, up)
  if rank == deck.ACE or rank == 8 then return true end
  if rank == 9 then return up ~= 7 and up < 10 end
  if rank == 7 then return up <= 7 end
  if rank == 6 then return up >= 3 and up <= 6 end
  if rank == 2 or rank == 3 then return up >= 4 and up <= 7 end
  return false
end

--- Basic strategy for these rules, from what the player can see: the hand and the up card, never the hole card or the shoe.
-- offered is what the table really has on its buttons, so a double the balance cannot cover is played as the next best thing;
-- left out, it is whatever the rules allow. Tests/blackjack_test.lua plays it for the return, and hint-oracle.mjs in
-- craftos-agent's tools/casinotest checks every cell against the exact expected values.
function M.basic(state, offered)
  if state.hold then return "stand" end
  offered = offered or offeredBy(state)
  local hand = state.hands[state.active]
  local up = deck.rank(state.dealer[1]) == deck.ACE and 11 or math.min(deck.rank(state.dealer[1]), 10)
  local total, soft = M.total(hand.cards)

  if offered.split and shouldSplit(deck.rank(hand.cards[1]), up) then return "split" end
  if soft then
    if total >= 19 or (total == 18 and up <= 8) then return "stand" end
    return "hit"
  end
  if offered.double then return "double" end
  if total >= 17 then return "stand" end
  if total >= 13 and up <= 6 then return "stand" end
  if total == 12 and up >= 4 and up <= 6 then return "stand" end
  return "hit"
end

local HINT_WORDS = { hit = "Hit on", stand = "Stand on", double = "Double on" }

--- The HINT button's advice for this decision.
function M.hint(state, offered)
  local id = M.basic(state, offered)
  local total, soft = M.total(state.hands[state.active].cards)
  local up = deck.rankName(state.dealer[1])
  if id == "split" then return { ids = { id }, text = "Split the pair against a dealer " .. up } end
  return { ids = { id }, text = ("%s %s %d against a dealer %s"):format(HINT_WORDS[id], soft and "soft" or "hard", total, up) }
end

function M.done(state)
  return state.over == true
end

--- Everything staked so far, so a double or split can only be taken if the balance can cover it too.
function M.risk(state)
  local total = 0
  for _, hand in ipairs(state.hands) do total = total + hand.bet end
  return total
end

function M.net(state)
  local total = 0
  for _, hand in ipairs(state.hands) do total = total + (hand.net or 0) end
  return total
end

local WORDS = { blackjack = "blackjack", win = "wins", push = "pushes", lose = "loses", bust = "busts" }

local function splitResult(state)
  local net = M.net(state)
  local parts = {}
  for i, hand in ipairs(state.hands) do parts[i] = ("Hand %d %s"):format(i, WORDS[hand.result]) end
  local detail = table.concat(parts, ", ")
  if net > 0 then return { kind = "win", title = "SPLIT WON", detail = detail } end
  if net < 0 then return { kind = "lose", title = "SPLIT LOST", detail = detail } end
  return { kind = "push", title = "SPLIT EVEN", detail = detail }
end

function M.result(state)
  if #state.hands > 1 then return splitResult(state) end
  local hand = state.hands[1]
  local total, dealer = M.total(hand.cards), M.total(state.dealer)
  local dealerNatural = M.isTwentyOneOnTwo(state.dealer)
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

--- Hand the shoe to the next round. It leaves the state, so the two never share a table.
function M.finish(state, keep)
  keep.shoe = state.cards
  state.left = #state.cards
  state.cards = {}
end

return M
