-- games/cribbage/rules.lua
-- Six-card cribbage for two, one game to 121 for a stake. Pure, as Games/BigTable/games/README.md asks. The engine's round is the whole
-- game: hands follow each other inside one state, and the tokens move once at the end.
--
--   The cut: each cuts a card and low deals, with aces low and suits not counting. A tie cuts again. The crib alternates from there.
--   The deal: six cards each. Both throw two to the dealer's crib at the same time, so waitingOn holds both seats until each is done.
--   The starter: a jack pays the dealer 2 for his heels.
--   Pegging: the player who did not deal leads. Fifteen 2, thirty-one 2, pairs 2, 6, 12, runs in any order, go 1, last card 1. A go is
--   said by itself when a player has no card that fits, so a turn is only ever a choice.
--   The show: the player who did not deal, then the dealer, then the crib, one step at a time, by the computer. Scoring is automatic.
--
-- 121 ends the game on the spot, mid-count or mid-show, and anything not yet counted or played never is, and stays unseen. A loser under
-- 91 is skunked and pays double. A game moves the stake, or twice it, held to the shorter stack so nobody loses past what they declared.

local deck = require("lib.casino.deck")
local scoring = require("games.cribbage.scoring")

local M = {}

M.TARGET = 121
M.SKUNK = 91
M.HAND = 6
M.KEEP = 4
M.LIMIT = scoring.THIRTY_ONE
M.HEELS = 2
M.STEPS = 3        -- the show: the other player's hand, the dealer's, then the crib

local function find(state, seat)
  for index, player in ipairs(state.players) do
    if player.seat == seat then return player, index end
  end
  return nil
end

local function has(list, card)
  for index, held in ipairs(list) do
    if held == card then return index end
  end
  return nil
end

local function copy(list)
  local out = {}
  for index, item in ipairs(list) do out[index] = item end
  return out
end

local function sorted(list)
  local out = copy(list)
  table.sort(out, function(a, b)
    if scoring.low(a) ~= scoring.low(b) then return scoring.low(a) < scoring.low(b) end
    return a < b
  end)
  return out
end

--- The count a next card lands on: a closed count is still on the table to read, but the next card starts a new one.
local function countNow(state)
  return state.closed and 0 or state.count
end

local function fits(state, card)
  return countNow(state) + scoring.value(card) <= M.LIMIT
end

local function canPlay(state, player)
  for _, card in ipairs(player.hand) do
    if fits(state, card) then return true end
  end
  return false
end

--- Whoever reaches 121 has won, right now. Every award comes through here.
local function finishGame(state, index)
  local winner, loser = state.players[index], state.players[3 - index]
  local skunk = loser.score < M.SKUNK
  local owed = state.stake * (skunk and 2 or 1)
  local amount = math.min(owed, state.cap)
  winner.net, loser.net = amount, -amount
  state.phase = "over"
  state.outcome = { winner = winner.seat, skunk = skunk, amount = amount, capped = owed > amount }
end

--- Add points and say so in events. Returns true if that ended the game.
local function award(state, index, points, events)
  local player = state.players[index]
  player.back = player.score
  player.score = math.min(M.TARGET, player.score + points)
  if player.score < M.TARGET then return false end
  finishGame(state, index)
  events[#events + 1] = { type = "win", seat = player.seat, skunk = state.outcome.skunk }
  return true
end

--- One line of what a player just scored, for the wall.
local function call(state, index, words, points)
  state.called[#state.called + 1] = { seat = state.players[index].seat, words = words, points = points }
end

local function cutCards(state)
  local first, second = state.players[1], state.players[2]
  first.cut, second.cut = deck.draw(state.deck), deck.draw(state.deck)
  local lowFirst, lowSecond = scoring.low(first.cut), scoring.low(second.cut)
  if lowFirst == lowSecond then
    state.dealer = nil
  else
    state.dealer = lowFirst < lowSecond and 1 or 2
  end
  return { { type = "cut", tie = state.dealer == nil } }
end

local function startHand(state, rng)
  state.hand = state.hand + 1
  state.deck = deck.shuffle(deck.fresh(1), rng)
  local dealer, pone = state.players[state.dealer], state.players[3 - state.dealer]
  for _, player in ipairs(state.players) do
    player.cut, player.hand, player.picks, player.threw, player.played, player.thrown = nil, {}, {}, {}, {}, false
  end
  for _ = 1, M.HAND do
    table.insert(pone.hand, deck.draw(state.deck))
    table.insert(dealer.hand, deck.draw(state.deck))
  end
  pone.hand, dealer.hand = sorted(pone.hand), sorted(dealer.hand)
  state.phase, state.crib, state.starter, state.turn = "discard", {}, nil, 3 - state.dealer
  state.count, state.run, state.closed, state.last, state.saidGo = 0, {}, false, nil, nil
  state.called, state.step, state.shown, state.tally = {}, 0, nil, {}
  return { { type = "deal", seat = dealer.seat } }
end

--- Two cards go to the crib, and the second player to do so brings the starter on.
local function throwCards(state, player)
  for _, card in ipairs(player.picks) do
    table.remove(player.hand, has(player.hand, card))
    state.crib[#state.crib + 1] = card
  end
  player.threw, player.picks, player.thrown = player.picks, {}, true
  if state.players[1].thrown and state.players[2].thrown then state.phase = "starter" end
  return { { type = "discard", seat = player.seat } }
end

--- What to throw for someone away: whatever they picked, and the rest so the four left are worth the most as they stand.
local function fillPicks(player)
  if #player.picks >= 2 then return end
  local best, bestPoints = nil, -1
  for first = 1, #player.hand - 1 do
    for second = first + 1, #player.hand do
      local a, b = player.hand[first], player.hand[second]
      local wanted = true
      for _, card in ipairs(player.picks) do wanted = wanted and (card == a or card == b) end
      if wanted then
        local rest = {}
        for _, card in ipairs(player.hand) do
          if card ~= a and card ~= b then rest[#rest + 1] = card end
        end
        local points = scoring.hand(rest)
        if points > bestPoints then best, bestPoints = { a, b }, points end
      end
    end
  end
  player.picks = best
end

local function startShow(state, events)
  state.phase, state.step = "show", 0
  events[#events + 1] = { type = "pegged" }
end

--- A count has closed, on thirty-one or a go. The player who did not play last leads the next, if they have a card to lead.
-- Returns true if that was the end of the pegging.
local function nextCount(state, events)
  local lastIndex = state.last
  state.closed, state.saidGo = true, nil
  local nextIndex = 3 - lastIndex
  if #state.players[nextIndex].hand == 0 then nextIndex = lastIndex end
  if #state.players[nextIndex].hand == 0 then
    startShow(state, events)
    return true
  end
  state.turn = nextIndex
  return false
end

--- After a card: whose turn it is, and any go that comes of it.
local function advance(state, events)
  local lastIndex = state.last
  if state.count == M.LIMIT then
    nextCount(state, events)
    return
  end
  local nextIndex = 3 - lastIndex
  local nextPlayer, lastPlayer = state.players[nextIndex], state.players[lastIndex]
  if canPlay(state, nextPlayer) then
    state.turn = nextIndex
    return
  end
  if canPlay(state, lastPlayer) then
    -- Saying go once is enough, and someone out of cards has nothing to say
    if #nextPlayer.hand > 0 and state.saidGo ~= nextPlayer.seat then
      state.saidGo = nextPlayer.seat
      events[#events + 1] = { type = "go", seat = nextPlayer.seat }
    end
    state.turn = lastIndex
    return
  end
  -- Nobody can play: a point for the last card down, whichever word that takes
  local final = #nextPlayer.hand == 0 and #lastPlayer.hand == 0
  if #nextPlayer.hand > 0 and state.saidGo ~= nextPlayer.seat then events[#events + 1] = { type = "go", seat = nextPlayer.seat } end
  call(state, lastIndex, final and "Last card" or "Go", 1)
  events[#events + 1] = { type = "point", seat = lastPlayer.seat, points = 1, final = final }
  if award(state, lastIndex, 1, events) then return end
  nextCount(state, events)
end

local function play(state, index, card)
  local player = state.players[index]
  if state.closed then state.count, state.run, state.closed = 0, {}, false end
  table.remove(player.hand, has(player.hand, card))
  player.played[#player.played + 1] = card
  state.run[#state.run + 1] = { card = card, seat = player.seat }
  state.count = state.count + scoring.value(card)
  state.last, state.called = index, {}
  local cards = {}
  for at, item in ipairs(state.run) do cards[at] = item.card end
  local points, items = scoring.peg(cards)
  for _, item in ipairs(items) do call(state, index, item.label, item.points) end
  local events = { { type = "peg", seat = player.seat, card = card, count = state.count, points = points } }
  if points > 0 and award(state, index, points, events) then return events end
  advance(state, events)
  return events
end

local function starter(state)
  local card = deck.draw(state.deck)
  state.starter = card
  state.called = {}
  local events = { { type = "starter", card = card } }
  if deck.rank(card) == 11 then
    call(state, state.dealer, "His heels", M.HEELS)
    events[2] = { type = "heels", seat = state.players[state.dealer].seat, points = M.HEELS }
    if award(state, state.dealer, M.HEELS, events) then return events end
  end
  state.phase = "peg"
  return events
end

--- One step of the show. The hand counted is left up for the wall, and anything after it is not looked at if the game ends here.
local function showStep(state)
  state.step = state.step + 1
  local dealer = state.dealer
  local index = state.step == 1 and 3 - dealer or dealer
  local isCrib = state.step == 3
  local player = state.players[index]
  local cards = sorted(isCrib and state.crib or player.played)
  local points, items = scoring.hand(cards, state.starter, isCrib)
  local what = isCrib and "crib" or "hand"
  state.shown = { seat = player.seat, what = what, cards = cards, points = points, items = items }
  state.tally[state.step] = { seat = player.seat, what = what, points = points }
  local events = { { type = "show", seat = player.seat, what = what, points = points } }
  if points > 0 then award(state, index, points, events) end
  return events
end

function M.new(entries, _, rng)
  local players, stake, cap = {}, 1, nil
  for index, entry in ipairs(entries) do
    players[index] = { seat = entry.seat, name = entry.name, stack = entry.stack, score = 0, back = 0, hand = {}, picks = {}, threw = {},
      played = {}, thrown = false, net = 0 }
    if entry.stake then stake = entry.stake end
    cap = math.min(cap or entry.stack, entry.stack)
  end
  local state = { players = players, stake = stake, cap = cap, phase = "cut", hand = 0, deck = deck.shuffle(deck.fresh(1), rng), crib = {},
    count = 0, run = {}, closed = false, called = {}, step = 0, tally = {} }
  return state, cutCards(state)
end

function M.waitingOn(state)
  if state.phase == "discard" then
    local list = {}
    for _, player in ipairs(state.players) do
      if not player.thrown then list[#list + 1] = player.seat end
    end
    return list
  end
  if state.phase == "peg" then return { state.players[state.turn].seat } end
  return {}
end

--- The buttons. The cards themselves are regions on the wall, and in pegging a card has a button too.
function M.actions(state, seat)
  local player, index = find(state, seat)
  if not player then return {} end
  if state.phase == "discard" and not player.thrown then
    if #player.picks == 2 then
      return { { id = "discard", label = "THROW " .. deck.name(player.picks[1]) .. " " .. deck.name(player.picks[2]), color = "win", textColor = "ink",
        sub = "to the crib" } }
    end
    return { { id = "discard", label = "PICK 2 CARDS", color = "panel2", disabled = true, sub = #player.picks .. " of 2" } }
  end
  if state.phase == "peg" and state.turn == index then
    local list = {}
    for _, card in ipairs(player.hand) do
      if fits(state, card) then
        list[#list + 1] = { id = "play", value = card, label = deck.name(card), color = "accent", textColor = "ink",
          sub = "count " .. countNow(state) + scoring.value(card) }
      end
    end
    return list
  end
  return {}
end

local function computerMove(state, id, rng)
  if id == "recut" and state.phase == "cut" and state.dealer == nil then
    state.deck = deck.shuffle(deck.fresh(1), rng)
    return cutCards(state)
  elseif id == "deal" and state.phase == "cut" and state.dealer ~= nil then
    return startHand(state, rng)
  elseif id == "starter" and state.phase == "starter" then
    return starter(state)
  elseif id == "count" and state.phase == "show" and state.step < M.STEPS then
    return showStep(state)
  elseif id == "next" and state.phase == "show" and state.step == M.STEPS then
    state.dealer = 3 - state.dealer
    return startHand(state, rng)
  end
  return {}
end

function M.act(state, seat, id, value, rng)
  if state.phase == "over" then return {} end
  if seat == nil then return computerMove(state, id, rng) end
  local player, index = find(state, seat)
  if not player then return {} end
  if state.phase == "discard" and not player.thrown then
    if id == "pick" then
      if type(value) ~= "number" or not has(player.hand, value) then return {} end
      local at = has(player.picks, value)
      if at then
        table.remove(player.picks, at)
      else
        -- A third card takes the place of the first, so changing your mind is one tap
        if #player.picks == 2 then table.remove(player.picks, 1) end
        player.picks[#player.picks + 1] = value
      end
      return { { type = "pick", seat = seat } }
    elseif id == "discard" and #player.picks == 2 then
      return throwCards(state, player)
    elseif id == "timeup" then
      fillPicks(player)
      return throwCards(state, player)
    end
    return {}
  end
  if state.phase == "peg" and state.turn == index and id == "play" then
    if type(value) ~= "number" or not has(player.hand, value) or not fits(state, value) then return {} end
    return play(state, index, value)
  end
  return {}
end

--- The lowest card that fits, and a tie on value goes to the lower rank. A king and a ten are both 10.
local function lowestCard(state, player)
  local best = nil
  for _, card in ipairs(player.hand) do
    if fits(state, card) and (not best or scoring.value(card) < scoring.value(best)
      or (scoring.value(card) == scoring.value(best) and scoring.low(card) < scoring.low(best))) then
      best = card
    end
  end
  return best
end

--- A seat's clock ran out, or with seat nil the computer's own step.
function M.auto(state, seat)
  if seat == nil then
    if state.phase == "cut" then return state.dealer and "deal" or "recut" end
    if state.phase == "starter" then return "starter" end
    if state.phase == "show" then return state.step < M.STEPS and "count" or "next" end
    return nil
  end
  if state.phase == "discard" then return "timeup" end
  if state.phase == "peg" then
    local player = find(state, seat)
    return "play", player and lowestCard(state, player)
  end
  return nil
end

--- Only what is face up, and for a seat their own cards. Built by hand: the deck, the crib and the other hand are not anywhere in here,
-- and nor is which cards a player has picked. A hand or a crib turns over only at its step of the show.
function M.viewFor(state, seat)
  local view = { phase = state.phase, over = state.phase == "over", hand = state.hand, target = M.TARGET, skunk = M.SKUNK, stake = state.stake,
    cap = state.cap, count = state.count, closed = state.closed, cribCards = #state.crib, starter = state.starter, step = state.step, saidGo = state.saidGo,
    run = {}, called = {}, tally = {}, players = {} }
  if state.dealer then view.dealer = state.players[state.dealer].seat end
  if state.phase == "peg" then view.turn = state.players[state.turn].seat end
  for index, player in ipairs(state.players) do
    view.players[index] = { seat = player.seat, name = player.name, score = player.score, back = player.back, left = #player.hand,
      played = copy(player.played), thrown = player.thrown, cut = player.cut, net = state.phase == "over" and player.net or nil }
  end
  for index, item in ipairs(state.run) do view.run[index] = { card = item.card, seat = item.seat } end
  for index, item in ipairs(state.called) do view.called[index] = { seat = item.seat, words = item.words, points = item.points } end
  for index, item in pairs(state.tally) do view.tally[index] = { seat = item.seat, what = item.what, points = item.points } end
  if state.shown then
    local shown = state.shown
    view.shown = { seat = shown.seat, what = shown.what, cards = copy(shown.cards), points = shown.points, items = {} }
    for index, item in ipairs(shown.items) do view.shown.items[index] = { label = item.label, points = item.points } end
  end
  if state.outcome then
    local outcome = state.outcome
    view.outcome = { winner = outcome.winner, skunk = outcome.skunk, amount = outcome.amount, capped = outcome.capped }
  end
  local own = seat and find(state, seat)
  if own then
    view.mine = { cards = copy(own.hand), picks = copy(own.picks), threw = copy(own.threw), thrown = own.thrown }
    if state.phase == "peg" and state.players[state.turn] == own then
      view.mine.live = {}
      for _, card in ipairs(own.hand) do
        if fits(state, card) then view.mine.live[#view.mine.live + 1] = card end
      end
    end
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
  local winner, loser = find(state, outcome.winner)
  loser = state.players[3 - loser]
  local text = winner.score .. " to " .. loser.score
  if outcome.skunk then text = text .. ", a skunk pays double" end
  if outcome.capped then text = text .. ", held to the shorter stack" end
  return text
end

function M.result(state, seat)
  local outcome = state.outcome
  if not outcome then return { kind = "push", title = "GAME OVER", detail = "" } end
  local winner = find(state, outcome.winner)
  local player = seat and find(state, seat)
  if not player then return { kind = "win", title = winner.name .. " WINS", detail = howItEnded(state) .. ": " .. outcome.amount } end
  local word = outcome.skunk and "SKUNK  " or ""
  if player == winner then
    return { kind = "win", title = word .. "YOU WIN", detail = "+" .. outcome.amount .. ". " .. howItEnded(state) }
  end
  return { kind = "lose", title = word .. "YOU LOSE", detail = "-" .. outcome.amount .. ". " .. howItEnded(state) }
end

--- For the stats: what the game really risked is what it moved.
function M.risk(state, seat)
  local player = find(state, seat)
  return player and math.abs(player.net) or 0
end

return M
