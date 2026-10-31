-- crazyeights_rules.lua
-- One hand of Crazy Eights against the dealer. Pure: no screen, no sound, no money.
-- Every rule the table plays by is a number or a line here, and the help is written from them.
--
-- The dealer plays from what it can see: its own hand, the discard pile, how many cards you hold, and the suits you
-- drew on rather than played. It never looks at your hand or the stock, and think() is the proof: it reads nothing else.

local deck = require("lib.casino.deck")

local M = {
  HAND = 7,            -- cards dealt to each side
  PENALTY = 2,         -- what a 2 makes the next player draw
  CAP = 6,             -- the most a stack of 2s can reach
  PAY = 1.88,          -- tokens back per token on a win: the strongest plan found wins 51.8%, a return of 97.4%
  MAX_TURNS = 120,     -- a hand this long is called, and the shorter hand wins
  PAGE = 11,           -- cards shown at a time; a longer hand pages
  SUIT_NAMES = { [0] = "CLUBS", [1] = "DIAMONDS", [2] = "HEARTS", [3] = "SPADES" },
}

local WILD, DRAW_RANK = 8, 2

-- How the dealer weighs a move. See score().
M.AI = {
  stuck = 1.5,        -- leaving you nothing to play
  follow = 0.3,       -- cards of ours that can go next
  spread = 0.2,       -- suits still in hand
  eight = 6.0,        -- the price of spending a wild
  two = 2.0,          -- making you draw
  keepTwo = 0.25,     -- a 2 held back answers yours
  pressure = 6.5,     -- how much more leaving you stuck is worth when you are nearly out
  holdWild = 6,       -- with only a wild to play, draw instead while holding this many cards or more
}

-- ------------------------------------------------------------------ the rules of play

local function top(state)
  return state.pile[#state.pile]
end
M.top = top

--- May this card be played now?
function M.canPlay(state, card)
  local rank = deck.rank(card)
  if state.pending > 0 then
    return rank == DRAW_RANK and state.pending + M.PENALTY <= M.CAP
  end
  return rank == WILD or deck.suit(card) == state.suit or rank == deck.rank(top(state))
end

--- The cards `who` may play, in hand order.
function M.legal(state, who)
  local list = {}
  for _, card in ipairs(state[who]) do
    if M.canPlay(state, card) then list[#list + 1] = card end
  end
  return list
end

local function removeCard(hand, card)
  for i, held in ipairs(hand) do
    if held == card then
      table.remove(hand, i)
      return true
    end
  end
  return false
end

local function other(who)
  return who == "player" and "dealer" or "player"
end

--- The player's hand in the order it is shown: by suit, then rank, with wilds last.
function M.sorted(hand)
  local list = {}
  for i, card in ipairs(hand) do list[i] = card end
  local function key(card)
    local rank = deck.rank(card)
    if rank == WILD then return 1000 + deck.suit(card) end
    return deck.suit(card) * 100 + rank
  end
  table.sort(list, function(a, b) return key(a) < key(b) end)
  return list
end

local function finishByCount(state, why)
  state.over = true
  state.ended = why
  local mine, theirs = #state.player, #state.dealer
  if mine < theirs then state.winner = "player"
  elseif theirs < mine then state.winner = "dealer"
  else state.winner = "push" end
end

local function noteTurn(state)
  state.turns = state.turns + 1
  if not state.over and state.turns >= M.MAX_TURNS then finishByCount(state, "long") end
end

--- Turn the discards, all but the top card, back into the stock.
local function refill(state, rng, events)
  if #state.stock > 0 or #state.pile < 2 then return end
  local keep = table.remove(state.pile)
  state.stock = deck.shuffle(state.pile, rng)
  state.pile = { keep }
  events[#events + 1] = { type = "reshuffle", left = #state.stock }
end

local function drawOne(state, who, rng, events)
  refill(state, rng, events)
  local card = deck.draw(state.stock)
  if card == nil then return false end
  table.insert(state[who], card)
  -- The dealer's cards stay hidden, even from the event
  events[#events + 1] = { type = "draw", who = who, card = who == "player" and card or nil }
  return true
end

local function playCard(state, who, card, suit, events)
  removeCard(state[who], card)
  state.pile[#state.pile + 1] = card
  state.suit = suit
  if deck.rank(card) == DRAW_RANK then state.pending = state.pending + M.PENALTY end
  state.passes = 0
  state.voids[who][deck.suit(card) + 1] = 0
  events[#events + 1] = { type = "play", who = who, card = card, suit = suit, pending = state.pending }
  if #state[who] == 0 then
    -- The first empty hand wins at once, whatever was just played
    state.over, state.winner = true, who
    state.pending = 0
  end
end

--- Take the stack of 2s, or one card. Either ends the turn.
local function takeCards(state, who, rng, events)
  local wanted = math.max(1, state.pending)
  local stacked = state.pending > 0
  local got = 0
  state.pending = 0
  for _ = 1, wanted do
    if drawOne(state, who, rng, events) then got = got + 1 end
  end
  if got == 0 then
    events[#events + 1] = { type = "pass", who = who }
    state.passes = state.passes + 1
    if state.passes >= 2 then finishByCount(state, "blocked") end
  else
    state.passes = 0
    -- Drawing on an open suit says they had nothing for it
    if not stacked then state.voids[who][state.suit + 1] = 1 end
  end
end

local function canDraw(state)
  return #state.stock > 0 or #state.pile > 1
end

-- ------------------------------------------------------------------ the dealer

--- How many unseen cards there are of each kind, for a player who holds `hand`.
local function unseen(state, hand)
  local known, bySuit, byRank, total = {}, { 0, 0, 0, 0 }, {}, 0
  for _, card in ipairs(hand) do known[card] = true end
  for _, card in ipairs(state.pile) do known[card] = true end
  for card = 0, 51 do
    if not known[card] then
      local suit, rank = deck.suit(card) + 1, deck.rank(card)
      bySuit[suit] = bySuit[suit] + 1
      byRank[rank] = (byRank[rank] or 0) + 1
      total = total + 1
    end
  end
  return { bySuit = bySuit, byRank = byRank, total = total }
end

--- The chance the other side holds nothing to play on suit and rank.
local function chanceStuck(view, suit, rank, voidSuit, holding)
  if view.total == 0 then return 1 end
  local answers = (view.byRank[WILD] or 0)
  local inSuit = view.bySuit[suit + 1]
  if voidSuit then inSuit = inSuit * 0.4 end
  answers = answers + inSuit
  if rank ~= WILD then
    answers = answers + (view.byRank[rank] or 0)
  end
  local miss = math.max(0, 1 - answers / view.total)
  return miss ^ holding
end

--- A move's worth. Bigger is better. card may be a wild, with `suit` the suit it names.
local function score(state, who, card, suit, view, rest)
  local w = M.AI
  local rank = deck.rank(card)
  local holding = #state[other(who)]
  local void = state.voids[other(who)][suit + 1] == 1
  local value = 0

  if rank == DRAW_RANK then
    -- They must answer with a 2 or draw
    local twos = view.byRank[DRAW_RANK] or 0
    local noAnswer = view.total > 0 and (1 - twos / view.total) ^ holding or 1
    value = value + w.two * noAnswer * (1 + w.pressure / holding)
  else
    value = value + w.stuck * chanceStuck(view, suit, rank, void, holding) * (1 + w.pressure / holding)
  end

  local follow, suits, seen, twosLeft = 0, 0, {}, 0
  for _, held in ipairs(rest) do
    local heldRank, heldSuit = deck.rank(held), deck.suit(held)
    if heldRank ~= WILD then
      if heldSuit == suit or heldRank == rank then follow = follow + 1 end
      if not seen[heldSuit] then
        seen[heldSuit] = true
        suits = suits + 1
      end
    end
    if heldRank == DRAW_RANK then twosLeft = twosLeft + 1 end
  end
  value = value + w.follow * math.min(follow, 3) + w.spread * suits

  if rank == DRAW_RANK and twosLeft == 0 then value = value - w.keepTwo end
  if rank == WILD then value = value - w.eight end
  return value
end

--- The suit to name with a wild: the one held most, and failing that the one fewest others can follow.
function M.bestSuit(state, who, card)
  local counts = { 0, 0, 0, 0 }
  for _, held in ipairs(state[who]) do
    if held ~= card and deck.rank(held) ~= WILD then
      local suit = deck.suit(held) + 1
      counts[suit] = counts[suit] + 1
    end
  end
  local view = unseen(state, state[who])
  local best, bestValue = 0, -math.huge
  for suit = 0, 3 do
    local value = counts[suit + 1] * 10 - view.bySuit[suit + 1]
    if state.voids[other(who)][suit + 1] == 1 then value = value + 6 end
    if value > bestValue then best, bestValue = suit, value end
  end
  return best
end

--- Choose a move from what `who` can see. Returns a card and the suit it sets, or nil to draw.
function M.think(state, who)
  local hand = state[who]
  local moves = M.legal(state, who)
  if #moves == 0 then return nil end

  if state.pending > 0 then
    -- Hand the stack back, on the suit we hold most of
    local card = moves[1]
    local counts = { 0, 0, 0, 0 }
    for _, held in ipairs(hand) do
      local suit = deck.suit(held) + 1
      if deck.rank(held) ~= DRAW_RANK then counts[suit] = counts[suit] + 1 end
    end
    for _, candidate in ipairs(moves) do
      if counts[deck.suit(candidate) + 1] > counts[deck.suit(card) + 1] then card = candidate end
    end
    return card, deck.suit(card)
  end

  local view = unseen(state, hand)
  local best, bestSuit, bestValue, plainMove = nil, nil, -math.huge, false
  for _, card in ipairs(moves) do
    local rest = {}
    for _, held in ipairs(hand) do
      if held ~= card then rest[#rest + 1] = held end
    end
    if #rest == 0 then return card, deck.suit(card) end
    local isWild = deck.rank(card) == WILD
    local suit = isWild and M.bestSuit(state, who, card) or deck.suit(card)
    if not isWild then plainMove = true end
    local value = score(state, who, card, suit, view, rest)
    if value > bestValue then best, bestSuit, bestValue = card, suit, value end
  end

  -- Only a wild can go: while the hand is long, keep it for last and draw instead
  if not plainMove and #hand >= M.AI.holdWild and canDraw(state) then return nil end
  return best, bestSuit
end

-- ------------------------------------------------------------------ a hand

local function dealerTurn(state, rng, events)
  events[#events + 1] = { type = "think", pending = state.pending }
  local card, suit = M.think(state, "dealer")
  if card then
    playCard(state, "dealer", card, suit, events)
  else
    takeCards(state, "dealer", rng, events)
  end
  noteTurn(state)
end

--- The dealer answers unless the hand is over, and an ended hand turns the dealer's cards face up.
local function afterPlayer(state, rng, events)
  if not state.over then dealerTurn(state, rng, events) end
  if state.over then
    local shown = {}
    for i, card in ipairs(state.dealer) do shown[i] = card end
    events[#events + 1] = { type = "reveal", cards = shown }
  end
  -- A page can run out when the hand shrinks
  state.page = math.max(0, math.min(math.ceil(#state.player / M.PAGE) - 1, state.page))
end

function M.maxWin(bet)
  return math.floor(bet * (M.PAY - 1) + 1e-6) -- the nudge keeps 87.9999 from a binary 0.88 at 88
end

function M.new(bet, rng, _, _)
  local cards = deck.shuffle(deck.fresh(1), rng)
  local state = {
    bet = bet, stock = cards, pile = {}, player = {}, dealer = {}, pending = 0, passes = 0, turns = 0, page = 0,
    voids = { player = { 0, 0, 0, 0 }, dealer = { 0, 0, 0, 0 } },
  }
  for _ = 1, M.HAND do state.player[#state.player + 1] = deck.draw(cards) end
  for _ = 1, M.HAND do state.dealer[#state.dealer + 1] = deck.draw(cards) end
  -- A wild or a 2 cannot start the pile: it goes under the stock and the next card turns
  local first = deck.draw(cards)
  while deck.rank(first) == WILD or deck.rank(first) == DRAW_RANK do
    table.insert(cards, 1, first)
    first = deck.draw(cards)
  end
  state.pile[1] = first
  state.suit = deck.suit(first)
  local shown = {}
  for i, card in ipairs(state.player) do shown[i] = card end
  return state, { { type = "deal", player = shown, dealer = #state.dealer, top = first, suit = state.suit, stock = #cards } }
end

function M.actions(state)
  if state.choosing then
    return { { id = "back", label = "BACK", color = "panel2" } }
  end
  local list = {}
  if state.pending > 0 then
    list[1] = { id = "draw", label = "TAKE " .. state.pending, color = "red", sub = "ends your turn" }
  elseif canDraw(state) then
    list[1] = { id = "draw", label = "DRAW", color = "blue", sub = "take one, turn ends" }
  else
    list[1] = { id = "draw", label = "PASS", color = "panel2", sub = "nothing left to draw" }
  end
  return list
end

function M.act(state, id, rng)
  local events = {}
  if state.over then return events end

  if id == "pageNext" or id == "pagePrev" then
    local pages = math.ceil(#state.player / M.PAGE)
    state.page = math.max(0, math.min(pages - 1, state.page + (id == "pageNext" and 1 or -1)))
    return events
  end

  if state.choosing then
    local named = tonumber((tostring(id):match("^suit(%d)$")))
    if id == "back" then
      state.choosing = nil
    elseif named and named <= 3 then
      local card = state.choosing
      state.choosing = nil
      playCard(state, "player", card, named, events)
      noteTurn(state)
      afterPlayer(state, rng, events)
    end
    return events
  end

  if id == "draw" then
    takeCards(state, "player", rng, events)
    noteTurn(state)
  else
    local card = tonumber((tostring(id):match("^p(%d+)$")))
    local held = false
    for _, value in ipairs(state.player) do held = held or value == card end
    if not held or not M.canPlay(state, card) then return events end
    if deck.rank(card) == WILD and #state.player > 1 then
      state.choosing = card
      return events
    end
    playCard(state, "player", card, deck.suit(card), events)
    noteTurn(state)
  end
  afterPlayer(state, rng, events)
  return events
end

--- Nobody at the table: play as the dealer would.
function M.auto(state)
  if state.choosing then return "suit" .. M.bestSuit(state, "player", state.choosing) end
  local card = M.think(state, "player")
  if card then return "p" .. card end
  return "draw"
end

function M.done(state)
  return state.over == true
end

function M.risk(state)
  return state.bet
end

function M.net(state)
  if state.winner == "player" then return M.maxWin(state.bet) end
  if state.winner == "dealer" then return -state.bet end
  return 0
end

function M.result(state)
  local dealerLeft = #state.dealer
  local why = state.ended == "blocked" and "Nobody can move. " or state.ended == "long" and "The hand is called. " or ""
  if state.winner == "player" then
    return { kind = "win", title = "YOU WIN", detail = why .. "Dealer left holding " .. dealerLeft .. (dealerLeft == 1 and " card" or " cards") }
  elseif state.winner == "dealer" then
    local left = #state.player
    return { kind = "lose", title = "DEALER WINS", detail = why .. "You were left holding " .. left .. (left == 1 and " card" or " cards") }
  end
  return { kind = "push", title = "PUSH", detail = why .. "Equal hands: your bet comes back" }
end

function M.finish()
end

return M
