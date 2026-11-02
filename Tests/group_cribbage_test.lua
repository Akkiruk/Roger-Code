-- group_cribbage_test.lua
-- Cribbage on Duel. Scoring is pinned to hands every player knows, then proved against a second method that shares none of its code. The
-- pegging is walked card by card, the money by playing whole games, and the secrets by changing what a seat cannot see and showing that
-- nothing it was sent changes.

local kit = require("group_kit")
local testing = require("testing")
local deck = require("lib.casino.deck")
local eq, test, truthy = testing.eq, testing.test, testing.truthy

local plugin = kit.plugin("Duel", "cribbage")
local rules, scoring = plugin.rules, plugin.scoring

local function cards(text)
  local list = {}
  for name in text:gmatch("%S+") do list[#list + 1] = deck.parse(name) end
  return list
end

local function card(name)
  return deck.parse(name)
end

local function labels(items)
  local list = {}
  for index, item in ipairs(items) do list[index] = item.label .. " " .. item.points end
  return table.concat(list, ", ")
end

--- The total of a hand of names, and that its breakdown adds up to it.
local function worth(hand, starter, isCrib)
  local points, items = scoring.hand(cards(hand), starter and card(starter), isCrib)
  local sum = 0
  for _, item in ipairs(items) do sum = sum + item.points end
  eq(sum, points, "the breakdown adds up")
  return points, labels(items)
end

--- What the last card of a count scores, from names in the order played.
local function pegged(text)
  return scoring.peg(cards(text))
end

-- ------------------------------------------------------------------ a state set by hand

local function entries(a, b, stake)
  return { { seat = 1, name = "Ann", stack = a or 5000, stake = stake or 25 }, { seat = 2, name = "Bob", stack = b or 5000, stake = stake or 25 } }
end

--- A game in pegging with named hands. Seat 2 dealt, so seat 1 leads. opts: stack, other, stake, scores { a, b }, starter, crib.
local function pegging(a, b, opts)
  opts = opts or {}
  local state = rules.new(entries(opts.stack, opts.other, opts.stake), 1, testing.fastRng(5))
  state.dealer, state.turn, state.phase, state.hand = opts.dealer or 2, 3 - (opts.dealer or 2), "peg", 1
  state.players[1].cut, state.players[2].cut = nil, nil
  state.players[1].hand, state.players[2].hand = cards(a), cards(b)
  state.players[1].thrown, state.players[2].thrown = true, true
  state.crib = cards(opts.crib or "2C 3C 4C 5C")
  state.starter = card(opts.starter or "KD")
  state.deck = cards("9D")
  if opts.scores then state.players[1].score, state.players[2].score = opts.scores[1], opts.scores[2] end
  return state
end

--- Lay cards by name, each by whoever's turn it is, and check it is whose it should be. Returns the last events.
local function lay(state, list)
  local events
  for name in list:gmatch("%S+") do
    local seat = rules.waitingOn(state)[1]
    events = rules.act(state, seat, "play", card(name), testing.fastRng(1))
    truthy(#events > 0, "laid " .. name .. " for seat " .. tostring(seat))
  end
  return events
end

local function typesOf(events)
  local list = {}
  for index, ev in ipairs(events) do list[index] = ev.type end
  return table.concat(list, " ")
end

local function computer(state)
  local id, value = rules.auto(state, nil)
  return rules.act(state, nil, id, value, testing.fastRng(9))
end

-- ------------------------------------------------------------------ scoring: hands everyone knows

test("the 29 hand", function()
  local points, said = worth("5C 5D 5S JH", "5H")
  eq(points, 29, "the best hand there is")
  eq(said, "Fifteens x8 16, Four 5s 12, Nobs 1", "and how it counts")
end)

test("a 28 without the nobs, a 24, and the hands that come to nothing", function()
  eq(worth("5C 5D 5S 5H", "JD"), 28, "four fives and a jack")
  eq(worth("7C 7D 8H 8S", "9D"), 24, "the 24: four fifteens, two pairs and four runs of 3")
  eq(worth("4C 4D 5H 6S", "6D"), 24, "the same shape: 4+5+6 four ways, two pairs, four runs of 3")
  eq(worth("2C 4D 6H 8S", "KC"), 0, "all even, so no fifteen, and no run")
  eq(worth("2C 6D 7H KS", "QC"), 2, "one fifteen")
  eq(worth("2C 7D 9H KS", "QC"), 0, "nineteen in the old joke")
end)

test("a double run counts the pair and both runs", function()
  local points, said = worth("3C 4D 4H 5S", "KD")
  eq(points, 10, "a fifteen, a pair, two runs of 3")
  eq(said, "Fifteen 2, Pair of 4s 2, Run of 3 x2 6", "and how it counts")
  eq(select(1, worth("3C 3D 3H 4S", "5D")), 21, "a triple run: 3 runs 9, three of a kind 6, 3+3+4+5 three ways 6")
  eq(select(2, worth("AC 2D 3H 3S", "4D")), "Pair of 3s 2, Run of 4 x2 8", "a double run of 4 from the ace, and 13 in all makes no fifteen")
end)

test("runs stop at the ends: ace is low, and Q K A is no run", function()
  eq(select(2, worth("QC KD AH 8S", "7D")), "Fifteen 2", "no run, and only 8 7 makes fifteen")
  eq(worth("AC 2D 3H 9S", "KD"), 3 + 2 * 2, "A 2 3 is a run, and two fifteens: 2 3 K, and 9 2 3 A")
end)

test("a flush in the hand is 4 or 5, and in the crib only 5", function()
  local hand = "2H 4H 6H 10H"
  eq(worth(hand, "KC"), 4, "four in the hand, and all even so no fifteen")
  eq(select(2, worth(hand, "KC")):find("Flush of 4", 1, true) ~= nil, true, "four in the hand")
  eq(select(2, worth(hand, "KH")):find("Flush of 5", 1, true) ~= nil, true, "five with the starter")
  eq(select(2, worth(hand, "KC", true)):find("Flush", 1, true), nil, "a crib with four of a suit has no flush")
  eq(select(2, worth(hand, "KH", true)):find("Flush of 5", 1, true) ~= nil, true, "a crib with all five does")
  eq(select(2, worth("2H 4H 6H 10D", "KH")):find("Flush", 1, true), nil, "the starter never makes four into a flush")
end)

test("nobs is a jack in the hand of the starter's suit", function()
  eq(select(2, worth("JD 3C 7H 9S", "KD")):find("Nobs 1", 1, true) ~= nil, true, "the jack of the starter's suit")
  eq(select(2, worth("JC 3C 7H 9S", "KD")):find("Nobs", 1, true), nil, "a jack of another suit")
  eq(select(2, worth("3C 7H 9S KD", "JD")):find("Nobs", 1, true), nil, "the starter being a jack is heels, not nobs")
end)

-- ------------------------------------------------------------------ scoring: a second method

--- From the definition, with shared code for nothing: every subset of the five cards, and a run is any subset of ranks in a row with
-- no longer such subset around it.
local function oracle(ranks)
  local n = #ranks
  local points = 0
  local runs = { [3] = 0, [4] = 0, [5] = 0 }
  for mask = 1, 2 ^ n - 1 do
    local chosen = {}
    local bits = mask
    for index = 1, n do
      if bits % 2 == 1 then chosen[#chosen + 1] = ranks[index] end
      bits = math.floor(bits / 2)
    end
    local sum = 0
    for _, rank in ipairs(chosen) do sum = sum + math.min(rank, 10) end
    if sum == 15 then points = points + 2 end
    if #chosen == 2 and chosen[1] == chosen[2] then points = points + 2 end
    if #chosen >= 3 then
      table.sort(chosen)
      local inRow = true
      for index = 2, #chosen do inRow = inRow and chosen[index] == chosen[index - 1] + 1 end
      if inRow then runs[#chosen] = runs[#chosen] + 1 end
    end
  end
  if runs[5] > 0 then return points + 5 * runs[5] end
  if runs[4] > 0 then return points + 4 * runs[4] end
  return points + 3 * runs[3]
end

test("every set of five ranks scores what the definition says", function()
  local checked, best = 0, 0
  local ranks = {}
  local function step(depth, from)
    if depth > 5 then
      -- The first card of a rank is a club, the next a diamond and so on. Suits are the other tests' business, so they come off here
      local used, hand = {}, {}
      for index, rank in ipairs(ranks) do
        hand[index] = deck.card(rank == 1 and 14 or rank, used[rank] or 0)
        used[rank] = (used[rank] or 0) + 1
      end
      local starter = table.remove(hand)
      local _, items = scoring.hand(hand, starter)
      local points = 0
      for _, item in ipairs(items) do
        if not item.label:find("Flush", 1, true) and item.label ~= "Nobs" then points = points + item.points end
      end
      eq(points, oracle(ranks), "ranks " .. table.concat(ranks, " "))
      best = math.max(best, points)
      checked = checked + 1
      if checked % 300 == 0 then testing.breathe() end
      return
    end
    for rank = from, 13 do
      local count = 0
      for index = 1, depth - 1 do
        if ranks[index] == rank then count = count + 1 end
      end
      if count < 4 then
        ranks[depth] = rank
        step(depth + 1, rank)
      end
    end
    ranks[depth] = nil
  end
  step(1, 1)
  -- Five from 13 ranks with repeats, less the 13 hands of five alike
  eq(checked, 6188 - 13, "every set of ranks went past")
  eq(best, 28, "the most without nobs")
end)

test("flushes and nobs on random deals match the definition", function()
  local rng = testing.fastRng(21)
  local seen = {}
  for round = 1, 4000 do
    local pile = deck.shuffle(deck.fresh(1), rng)
    -- A narrow pile so flushes turn up
    local suit = rng:below(4)
    local hand, starter = {}, nil
    for _, pick in ipairs(pile) do
      if #hand < 4 and (deck.suit(pick) == suit or rng:below(5) == 0) then
        hand[#hand + 1] = pick
      elseif #hand == 4 and not starter then
        starter = pick
      end
    end
    local isCrib = rng:below(2) == 0
    local _, items = scoring.hand(hand, starter, isCrib)
    local all, nobs = true, false
    for _, held in ipairs(hand) do
      all = all and deck.suit(held) == deck.suit(hand[1])
      nobs = nobs or (deck.rank(held) == 11 and deck.suit(held) == deck.suit(starter))
    end
    local five = all and deck.suit(starter) == deck.suit(hand[1])
    local expect = (five and "Flush of 5") or ((all and not isCrib) and "Flush of 4") or nil
    local found, hasNobs = nil, false
    for _, item in ipairs(items) do
      if item.label:find("Flush", 1, true) then found = item.label end
      hasNobs = hasNobs or item.label == "Nobs"
    end
    eq(found, expect, "the flush")
    eq(hasNobs, nobs, "nobs")
    if found then seen[found] = true end
    if nobs then seen.nobs = true end
    if round % 500 == 0 then testing.breathe() end
  end
  truthy(seen["Flush of 4"] and seen["Flush of 5"] and seen.nobs, "all three came up")
end)

-- ------------------------------------------------------------------ pegging, card by card

test("what a pegged card scores", function()
  eq(pegged("7C 8D"), 2, "fifteen")
  eq(pegged("KC QD JH AC"), 2, "thirty-one")
  eq(pegged("KC QD JH AC"), 2, "thirty-one with no other reason")
  eq(pegged("7C 7D"), 2, "a pair")
  eq(pegged("7C 7D 7H"), 6, "three")
  eq(pegged("3C 3D 3H 3S"), 12, "four")
  eq(pegged("5C 5D 5H"), 8, "three of a kind on fifteen")
  eq(pegged("7C 7D 8H"), 0, "a pair broken by another card is nothing")
  eq(pegged("9C 7D 8H"), 3, "a run, out of order")
  eq(pegged("3C 5D 4H"), 3, "and low")
  eq(pegged("3C 5D 4H 6S"), 4, "a run of 4 out of order")
  eq(pegged("2C 4D 3H 6S 5D"), 5, "a run of 5 out of order, with one more on the end")
  eq(pegged("4C 2D 3H 5S AD"), 5 + 2, "five in a row, 15 on the way")
  eq(pegged("3C 4D 5H 3S"), 3 + 2, "the last three cards are a run, and the count is fifteen")
  eq(pegged("6C 3D 4H 5S 3C"), 3, "a run of the last three, the 6 and the first 3 out of it")
  eq(pegged("3C 4D 4H 5S"), 0, "a repeat inside breaks a run in pegging")
  eq(pegged("QC KD AH"), 0, "Q K A is no run")
  eq(pegged("AC 2D 3H"), 3, "A 2 3 is")
end)

test("a run in pegging out of order, played through the rules", function()
  local state = pegging("4C 2D AS KH", "3H 5D KC QC")
  lay(state, "4C 3H 2D")
  eq(state.players[1].score, 3, "2 onto 4 and 3 is a run of 3")
  lay(state, "5D")
  eq(state.players[2].score, 4, "5 makes it 2-3-4-5, and the count is 14, so no fifteen")
  eq(state.count, 14, "the count")
  lay(state, "AS")
  eq(state.players[1].score, 3 + 5 + 2, "A makes a run of 5 and fifteen")
end)

test("go and last card", function()
  -- 10 + 10 + 10 is 30, and nobody holds an ace: Bob says go and Ann, who laid last, takes the point
  local state = pegging("KC QD 9H 9S", "KD 8C 8D 8H")
  local events = lay(state, "KC KD")
  eq(state.count, 20, "twenty")
  events = lay(state, "QD")
  eq(state.count, 30, "thirty")
  eq(typesOf(events), "peg go point", "Bob goes, Ann takes the point and the next count opens")
  eq(state.players[1].score, 1, "a go is 1")
  eq(events[2].seat, 2, "Bob said go")
  eq(events[3].points, 1, "and a point to Ann")
  eq(state.closed, true, "the count is closed")
  eq(rules.viewFor(state, nil).count, 30, "and still on the table to read")
  eq(rules.waitingOn(state)[1], 2, "Bob leads the next count, as he did not play last")
  lay(state, "8C")
  eq(state.count, 8, "a fresh count")
  eq(#state.run, 1, "with one card in it")
  lay(state, "9H")
  eq(state.count, 17, "seventeen")
  events = lay(state, "8D") -- 25, and neither remaining card fits
  eq(typesOf(events), "peg go point", "Ann goes, the point to Bob")
  eq(state.players[2].score, 2 + 1, "his pair of kings and this go")
  lay(state, "9S") -- Ann did not play last, so she leads
  eq(state.count, 9, "a fresh count")
  events = lay(state, "8H")
  eq(typesOf(events), "peg point pegged", "the last card, then the show")
  eq(state.players[2].score, 2 + 1 + 1, "and a last card")
  eq(state.players[1].score, 1, "Ann kept her one")
end)

test("the player with a card left plays on alone after a go", function()
  local state = pegging("AC 2D KC QD", "KD 9S 7C 6C")
  lay(state, "KC KD QD") -- 30, and Bob has nothing that fits
  eq(rules.waitingOn(state)[1], 1, "Ann plays on")
  eq(state.saidGo, 2, "Bob has said go")
  eq(state.closed, false, "the count is still open")
  lay(state, "AC") -- 31
  eq(state.players[1].score, 2, "thirty-one is 2 and the go is in it, nothing more")
  eq(state.closed, true, "and it closes")
  eq(rules.waitingOn(state)[1], 2, "Bob leads")
end)

test("thirty-one on the last card scores no last card as well", function()
  local state = pegging("KC 10D", "QD AC")
  state.players[1].played, state.players[2].played = cards("2C 3C"), cards("4C 5C")
  local events = lay(state, "KC QD 10D")
  eq(state.count, 30, "thirty")
  eq(state.players[1].score, 0, "nothing yet")
  events = lay(state, "AC")
  eq(state.players[2].score, 2, "thirty-one only")
  eq(typesOf(events), "peg pegged", "and on to the show")
  eq(state.phase, "show", "the show")
end)

test("the last card pays 1", function()
  local state = pegging("2C", "3D")
  local events = lay(state, "2C 3D")
  eq(state.players[2].score, 1, "last card")
  eq(typesOf(events), "peg point pegged", "then the show")
  eq(events[2].final, true, "the last card, not a go")
  eq(rules.viewFor(state, nil).called[1].words, "Last card", "said so on the wall")
end)

test("no card fits and a clock's card is the lowest legal one", function()
  local state = pegging("KC 2D 9S 5H", "KD 8C 8D 8H")
  eq(select(2, rules.auto(state, 1)), card("2D"), "the lowest of all")
  lay(state, "KC KD 9S")
  eq(state.count, 29, "twenty-nine")
  eq(rules.waitingOn(state)[1], 1, "Bob has no 2, so Ann plays on")
  local _, value = rules.auto(state, 1)
  eq(value, card("2D"), "the 2 is all that fits")
  state = pegging("KC 10D JH QS", "KD 8C 8D 8H")
  lay(state, "QS")
  eq(state.count, 10, "ten")
  eq(select(2, rules.auto(state, 2)), card("8C"), "lowest value first")
  state = pegging("KC 10D JH QS", "KD 8C 8D 8H")
  eq(select(2, rules.auto(state, 1)), card("10D"), "of tens, the lowest rank")
end)

test("a card past 31 is refused", function()
  local state = pegging("KC QD AH 3S", "KD 8C 8D 8H")
  lay(state, "KC KD QD")
  eq(state.count, 30, "thirty")
  eq(rules.waitingOn(state)[1], 1, "Ann has an ace to play on")
  local before = kit.plain(state)
  eq(#rules.act(state, 1, "play", card("3S"), testing.fastRng(1)), 0, "33")
  truthy(kit.same(before, state), "nothing changed")
  local offered = rules.actions(state, 1)
  eq(#offered, 1, "only the ace is offered")
  eq(offered[1].value, card("AH"), "the ace")
end)

-- ------------------------------------------------------------------ the deal, the crib and the show

--- A new game on to the discards.
local function atDiscards(opts)
  opts = opts or {}
  local state = rules.new(entries(opts.a, opts.b, opts.stake), 1, testing.fastRng(opts.seed or 11))
  while state.phase == "cut" do computer(state) end
  return state
end

test("low card deals, a tie cuts again, and the crib alternates", function()
  local rng = testing.fastRng(61)
  local ties, firsts = 0, { 0, 0 }
  for _ = 1, 800 do
    local state = rules.new(entries(), 1, rng)
    local steps = 0
    while state.phase == "cut" do
      steps = steps + 1
      local a, b = scoring.low(state.players[1].cut), scoring.low(state.players[2].cut)
      if a == b then
        eq(state.dealer, nil, "a tie has no dealer yet")
        eq(rules.auto(state, nil), "recut", "and cuts again")
        ties = ties + 1
      else
        eq(state.dealer, a < b and 1 or 2, "low deals")
        eq(rules.auto(state, nil), "deal", "and the deal comes")
        firsts[state.dealer] = firsts[state.dealer] + 1
      end
      eq(rules.viewFor(state, nil).players[1].cut, state.players[1].cut, "the cut is face up")
      local id = rules.auto(state, nil)
      truthy(#rules.act(state, nil, id, nil, rng) > 0, "the cut moves on")
      truthy(steps < 40, "a run of ties ends")
    end
    eq(state.phase, "discard", "the first hand")
    eq(#state.players[1].hand, 6, "six cards")
    eq(#state.players[2].hand, 6, "six each")
  end
  truthy(ties > 0, "some ties")
  truthy(firsts[1] > 250 and firsts[2] > 250, "either can deal")

  -- The crib moves at the end of every show
  local state = pegging("2C", "3D")
  lay(state, "2C 3D")
  for _ = 1, 3 do computer(state) end
  eq(state.step, 3, "three steps")
  eq(rules.auto(state, nil), "next", "then the next hand")
  computer(state)
  eq(state.dealer, 1, "the crib moved")
  eq(state.hand, 2, "the second hand")
  eq(state.turn, 2, "Bob is pone and leads")
  eq(#state.crib, 0, "an empty crib")
  eq(state.starter, nil, "no starter yet")
end)

test("discards are simultaneous, kept in the state, and a third tap replaces the first", function()
  local state = atDiscards()
  local list = rules.waitingOn(state)
  eq(#list, 2, "both seats are waited on")
  local hand = state.players[1].hand
  local a, b, c = hand[1], hand[2], hand[3]
  eq(rules.actions(state, 1)[1].disabled, true, "no throw yet")
  eq(#rules.act(state, 1, "pick", a), 1, "picked")
  rules.act(state, 1, "pick", b)
  eq(state.players[1].picks[2], b, "both held in the state")
  eq(rules.actions(state, 1)[1].disabled, nil, "a throw now")
  rules.act(state, 1, "pick", c)
  eq(state.players[1].picks[1], b, "the first gave way")
  eq(state.players[1].picks[2], c, "to the third")
  rules.act(state, 1, "pick", b)
  eq(#state.players[1].picks, 1, "a second tap takes it back")
  rules.act(state, 1, "pick", a)
  eq(#rules.act(state, 1, "pick", state.players[2].hand[1]), 0, "not a card of theirs")
  local events = rules.act(state, 1, "discard")
  eq(events[1].type, "discard", "thrown")
  eq(events[1].card, nil, "and the event names no card")
  eq(#state.players[1].hand, 4, "four left")
  eq(rules.waitingOn(state)[1], 2, "only Bob now")
  eq(#rules.waitingOn(state), 1, "only Bob")
  eq(rules.viewFor(state, 2).players[1].thrown, true, "Bob can see Ann has thrown")
  eq(rules.viewFor(state, 2).mine.thrown, false, "and he has not")
  eq(#rules.act(state, 1, "discard"), 0, "she cannot throw twice")
  rules.act(state, 2, "timeup")
  eq(state.phase, "starter", "both done")
  eq(#state.crib, 4, "a crib of four")
  eq(#rules.waitingOn(state), 0, "the computer cuts")
end)

test("a clock's discard is legal, keeps what was picked and makes progress from any picks", function()
  for picks = 0, 2 do
    local state = atDiscards({ seed = 20 + picks })
    local hand = state.players[1].hand
    local chosen = {}
    for index = 1, picks do
      chosen[index] = hand[index + 2]
      rules.act(state, 1, "pick", chosen[index])
    end
    eq(rules.auto(state, 1), "timeup", "the clock's move")
    truthy(#rules.act(state, 1, "timeup") > 0, "it moves")
    eq(#state.players[1].hand, 4, "two gone")
    eq(#state.crib, 2, "to the crib")
    for _, wanted in ipairs(chosen) do truthy(state.crib[1] == wanted or state.crib[2] == wanted, "what was picked goes") end
  end
  -- Left to itself it keeps the best four
  local state = atDiscards()
  state.players[1].hand = cards("5C 5D 5H JS 3C 8D")
  rules.act(state, 1, "timeup")
  eq(state.crib[1], card("3C"), "the 3 goes")
  eq(state.crib[2], card("8D"), "and the 8, keeping three fives and the jack")
end)

test("his heels pays the dealer 2 and nobody else, and a heels at 119 wins", function()
  local state = atDiscards()
  rules.act(state, 1, "timeup")
  rules.act(state, 2, "timeup")
  state.deck[#state.deck + 1] = card("JD")
  local dealer = state.dealer
  local events = computer(state)
  eq(typesOf(events), "starter heels", "a jack")
  eq(events[1].card, card("JD"), "the starter is public")
  eq(state.players[dealer].score, 2, "the dealer")
  eq(state.players[3 - dealer].score, 0, "not the other")
  eq(state.phase, "peg", "and on")

  state = atDiscards()
  rules.act(state, 1, "timeup")
  rules.act(state, 2, "timeup")
  state.deck[#state.deck + 1] = card("JH")
  state.players[state.dealer].score = 119
  events = computer(state)
  truthy(rules.done(state), "over on the cut")
  eq(typesOf(events), "starter heels win", "said so")

  state = atDiscards()
  rules.act(state, 1, "timeup")
  rules.act(state, 2, "timeup")
  state.deck[#state.deck + 1] = card("QD")
  eq(typesOf(computer(state)), "starter", "a queen is nothing")
end)

--- A game at the show, with hands set: a is the pone's, b the dealer's, as they were pegged.
local function atShow(a, b, crib, starter, opts)
  opts = opts or {}
  local state = pegging("", "", { starter = starter, crib = crib, scores = opts.scores, stake = opts.stake, stack = opts.stack, other = opts.other })
  state.players[1].played, state.players[2].played = cards(a), cards(b)
  state.phase, state.step = "show", 0
  return state
end

test("the show goes pone, dealer, crib, with a breakdown for each, one step at a time", function()
  local state = atShow("5C 5D 5S JH", "2C 4D 6H 8S", "3C 3D 9H 9S", "5H")
  eq(#rules.waitingOn(state), 0, "the computer counts")
  local events = computer(state)
  eq(events[1].seat, 1, "pone first")
  eq(events[1].what, "hand", "a hand")
  eq(events[1].points, 29, "the 29")
  eq(state.players[1].score, 29, "pegged")
  eq(rules.viewFor(state, 1).shown.items[3].label, "Nobs", "with its breakdown")
  events = computer(state)
  eq(events[1].seat, 2, "then the dealer")
  local dealerPoints = state.players[2].score
  events = computer(state)
  eq(events[1].what, "crib", "then the crib")
  eq(events[1].seat, 2, "the dealer's crib")
  eq(state.players[2].score, dealerPoints + events[1].points, "pegged to the dealer")
  local view = rules.viewFor(state, nil)
  eq(view.tally[1].points, 29, "the tally holds")
  eq(#view.tally, 3, "all three")
end)

-- ------------------------------------------------------------------ the end of a game

test("121 ends it at once in pegging, with the rest unseen", function()
  local state = pegging("7C 2D 3H 4S", "8D 9C 10D JH", { scores = { 90, 119 } })
  local events = lay(state, "7C 8D") -- fifteen for Bob, and that is the game
  truthy(rules.done(state), "over on the card")
  eq(typesOf(events), "peg win", "said at once")
  eq(state.players[2].score, 121, "on 121")
  eq(rules.result(state, 2).kind, "win", "Bob wins")
  eq(rules.result(state, 1).kind, "lose", "Ann loses")
  eq(rules.nets(state)[2], 50, "Ann is on 90, so a skunk, double the stake")
end)

test("a skunk pays double, at 90 and not at 91", function()
  local state = pegging("7C 2D 3H 4S", "8D 9C 10D JH", { scores = { 90, 119 } })
  lay(state, "7C 8D")
  truthy(state.outcome.skunk, "90 is a skunk")
  eq(rules.nets(state)[2], 50, "double")
  eq(rules.nets(state)[1], -50, "and the other way")
  truthy(rules.result(state, 1).title:find("SKUNK", 1, true) ~= nil, "it says so")

  state = pegging("7C 2D 3H 4S", "8D 9C 10D JH", { scores = { 91, 119 } })
  lay(state, "7C 8D")
  truthy(not state.outcome.skunk, "91 is safe")
  eq(rules.nets(state)[2], 25, "single")

  -- Far under 61 is still only double: there is no double skunk
  state = pegging("7C 2D 3H 4S", "8D 9C 10D JH", { scores = { 3, 119 } })
  lay(state, "7C 8D")
  eq(rules.nets(state)[2], 50, "no double skunk")
end)

test("the first to 121 in the show wins, before anyone else counts", function()
  local state = atShow("5C 5D 5S JH", "2C 4D 6H 8S", "3C 3D 9H 9S", "5H", { scores = { 100, 120 } })
  local events = computer(state)
  truthy(rules.done(state), "pone counts first and gets there")
  eq(typesOf(events), "show win", "at once")
  eq(state.players[2].score, 120, "the dealer on 120 never counts")
  eq(rules.viewFor(state, nil).tally[2], nil, "nor is shown")
  eq(rules.viewFor(state, nil).shown.seat, 1, "the hand that won stays up")
  eq(rules.nets(state)[1], 25, "the stake")
end)

test("the cap holds a net to the shorter stack, skunk or not", function()
  local state = pegging("7C 2D 3H 4S", "8D 9C 10D JH", { scores = { 3, 119 }, stake = 100, stack = 150, other = 5000 })
  lay(state, "7C 8D")
  eq(rules.nets(state)[2], 150, "a skunk of 200 held to 150")
  eq(rules.nets(state)[1], -150, "the loser never past what they declared")
  truthy(state.outcome.capped, "it says so")
  truthy(rules.result(state, 2).detail:find("shorter stack", 1, true) ~= nil, "on the banner")

  state = pegging("7C 2D 3H 4S", "8D 9C 10D JH", { scores = { 100, 119 }, stake = 100, stack = 5000, other = 150 })
  lay(state, "7C 8D")
  eq(rules.nets(state)[2], 100, "no cap reached")
  truthy(not state.outcome.capped, "and none said")

  state = pegging("7C 2D 3H 4S", "8D 9C 10D JH", { scores = { 3, 119 }, stake = 100, stack = 5000, other = 60 })
  lay(state, "7C 8D")
  eq(rules.nets(state)[2], 60, "a winner on a short stack is held to it too")

  local found = false
  for _, line in ipairs(plugin.help()) do
    found = found or (type(line) == "string" and line:find("shorter stack", 1, true) ~= nil)
  end
  truthy(found, "the help says so")
end)

-- ------------------------------------------------------------------ illegal input

test("illegal input does nothing", function()
  local rng = testing.fastRng(3)
  local function refused(state, tries)
    local before = kit.plain(state)
    for _, try in ipairs(tries) do
      local events = rules.act(state, try[1], try[2], try[3], rng)
      eq(#events, 0, tostring(try[1]) .. " " .. tostring(try[2]))
      truthy(kit.same(before, state), "nothing changed: " .. tostring(try[2]))
    end
  end
  local state = rules.new(entries(), 1, rng)
  refused(state, { { 1, "deal" }, { 2, "recut" }, { 1, "pick", 4 }, { 3, "play", 1 }, { nil, "pick", 1 }, { nil, "starter" }, { nil, "next" } })
  state = atDiscards()
  refused(state, { { 1, "discard" }, { 1, "play", state.players[1].hand[1] }, { 1, "pick", "x" }, { 1, "pick", 999 }, { 1, "pick", {} }, { 1, "pick", -1 },
    { 1, "pick", 1.5 }, { 3, "pick", 4 }, { nil, "count" }, { nil, "starter" }, { nil, "play", 1 } })
  state = pegging("KC 2D", "KD 8C")
  refused(state, { { 2, "play", card("KD") }, { 1, "play", card("KD") }, { 1, "play", "2D" }, { 1, "pick", card("KC") }, { 1, "discard" }, { 1, "timeup" },
    { nil, "play", card("KC") }, { nil, "next" }, { nil, "count" } })
  state = atShow("5C 5D 5S JH", "2C 4D 6H 8S", "3C 3D 9H 9S", "5H")
  refused(state, { { 1, "count" }, { nil, "next" }, { 1, "next" }, { nil, "starter" } })
end)

-- ------------------------------------------------------------------ whole games

--- Throw at random: a card tap or two, then the button.
local function pickSome(state, seat, actions, rng)
  if state.phase == "discard" then
    local player = state.players[seat]
    if actions[1] and not actions[1].disabled and rng:below(3) > 0 then return "discard" end
    return "pick", player.hand[1 + rng:below(#player.hand)]
  end
  return nil
end

--- A play that scores when it can, so the fuzz meets high scores and skunks.
local function greedy(state, seat, actions, rng)
  if state.phase ~= "peg" then return pickSome(state, seat, actions, rng) end
  local best, bestPoints = nil, -1
  for _, action in ipairs(actions) do
    local run = {}
    if not state.closed then
      for index, item in ipairs(state.run) do run[index] = item.card end
    end
    run[#run + 1] = action.value
    local points = scoring.peg(run)
    if points > bestPoints then best, bestPoints = action, points end
  end
  return best and best.id, best and best.value
end

--- Every seat's and the public view, and every action, against what must stay hidden at this step.
local function secrets(state)
  local deckCards = {}
  for _, held in ipairs(state.deck) do deckCards[held] = true end
  local function cardsIn(view)
    local list = {}
    local function add(items)
      for _, item in ipairs(items or {}) do list[#list + 1] = type(item) == "table" and item.card or item end
    end
    for _, player in ipairs(view.players) do
      add(player.played)
      if player.cut then list[#list + 1] = player.cut end
    end
    add(view.run)
    if view.starter then list[#list + 1] = view.starter end
    if view.shown then add(view.shown.cards) end
    return list
  end
  local crib = {}
  for _, held in ipairs(state.crib) do crib[held] = true end
  local function checkPublic(view, seat)
    for _, seen in ipairs(cardsIn(view)) do
      if state.phase ~= "cut" then truthy(not deckCards[seen] or seen == state.starter, "a card of the deck on seat " .. tostring(seat)) end
      if view.shown == nil or view.shown.what ~= "crib" then truthy(not crib[seen], "a crib card on seat " .. tostring(seat)) end
      for _, player in ipairs(state.players) do
        for _, held in ipairs(player.hand) do truthy(seen ~= held, "an unplayed card on seat " .. tostring(seat)) end
      end
    end
  end
  local public = rules.viewFor(state, nil)
  eq(public.mine, nil, "no private field on the wall")
  eq(public.crib, nil, "the crib is only a count")
  eq(public.deck, nil, "no deck")
  checkPublic(public, nil)
  for _, player in ipairs(state.players) do
    local view = rules.viewFor(state, player.seat)
    checkPublic(view, player.seat)
    eq(view.deck, nil, "no deck")
    eq(#view.mine.cards, #player.hand, "their own cards")
    local other = state.players[1] == player and state.players[2] or state.players[1]
    local mineCards = {}
    for _, held in ipairs(view.mine.cards) do mineCards[held] = true end
    for _, held in ipairs(other.hand) do truthy(not mineCards[held], "the other hand in mine") end
    for _, held in ipairs(view.mine.threw) do
      local ok = false
      for _, thrown in ipairs(player.threw) do ok = ok or thrown == held end
      truthy(ok, "threw holds only their own")
    end
    for _, item in ipairs(view.players) do truthy(item.hand == nil and item.picks == nil and item.threw == nil, "no cards on a player") end
  end
end

test("whole games at random keep the contract, with secrets checked at every step", function()
  kit.fuzz(plugin, { rounds = 120, seats = { 2 }, stack = 500, stake = 25, absent = 10, pick = pickSome, check = secrets })
  kit.fuzz(plugin, { rounds = 120, seats = { 2 }, stack = 5000, stake = 250, seed = 99, pick = greedy, check = secrets })
  kit.fuzz(plugin, { rounds = 60, seats = { 2 }, stack = 30, stake = 25, seed = 7, absent = 100, check = secrets })
end)

test("games played by clock and by hand end every way, and always add up", function()
  local rng = testing.fastRng(31)
  local skunks, plain, capped, midPeg, inShow = 0, 0, 0, 0, 0
  for round = 1, 400 do
    local list = { { seat = 1, name = "Ann", stack = 400, stake = 100 }, { seat = 2, name = "Bob", stack = 60 + rng:below(200), stake = 100 } }
    local state = rules.new(list, 1, rng)
    local before
    while not rules.done(state) do
      before = state.phase
      local seat = rules.waitingOn(state)[1]
      if seat then
        local id, value = rules.auto(state, seat)
        if rng:below(3) == 0 and state.phase == "peg" then
          local actions = rules.actions(state, seat)
          local action = actions[1 + rng:below(#actions)]
          id, value = action.id, action.value
        end
        truthy(#rules.act(state, seat, id, value, rng) > 0, "a move")
      else
        local id, value = rules.auto(state, nil)
        truthy(#rules.act(state, nil, id, value, rng) > 0, "a computer's move")
      end
    end
    local nets = rules.nets(state)
    eq(nets[1] + nets[2], 0, "nets sum to zero")
    local cap = math.min(list[1].stack, list[2].stack)
    truthy(math.abs(nets[1]) <= cap, "within the shorter stack")
    local outcome = state.outcome
    local loser = state.players[1].seat == outcome.winner and state.players[2] or state.players[1]
    eq(outcome.skunk, loser.score < 91, "a skunk is under 91")
    eq(math.abs(nets[1]), math.min(100 * (outcome.skunk and 2 or 1), cap), "the stake, doubled, capped")
    eq(state.players[outcome.winner].score, 121, "the winner is on 121 and no more")
    if outcome.skunk then skunks = skunks + 1 else plain = plain + 1 end
    if outcome.capped then capped = capped + 1 end
    if before == "peg" then midPeg = midPeg + 1 elseif before == "show" then inShow = inShow + 1 end
    if round % 40 == 0 then testing.breathe() end
  end
  truthy(skunks > 0 and plain > 0, "skunks and plain wins")
  truthy(capped > 0, "some capped")
  truthy(midPeg > 0 and inShow > 0, "games ended in the pegging and in the show")
end)

-- ------------------------------------------------------------------ secrets

local VIEW_FIELDS = { phase = true, over = true, hand = true, target = true, skunk = true, stake = true, cap = true, count = true, closed = true,
  cribCards = true, starter = true, step = true, saidGo = true, run = true, called = true, tally = true, players = true, dealer = true, turn = true,
  shown = true, outcome = true, mine = true }

--- Change everything this seat cannot see: the other seat's unplayed cards and throw, the deck, and what the other has picked.
local function reshuffleHidden(state, seat, rng)
  local other = state.players[1].seat == seat and state.players[2] or state.players[1]
  local own = other == state.players[1] and state.players[2] or state.players[1]
  if state.phase == "show" or state.phase == "over" then
    -- The show has turned everything but the crib over, and the crib only at its step
    if state.step >= 3 or #state.crib == 0 then return end
  end
  local pool = {}
  for _, held in ipairs(other.hand) do pool[#pool + 1] = held end
  for _, held in ipairs(other.threw) do pool[#pool + 1] = held end
  for _, held in ipairs(state.deck) do pool[#pool + 1] = held end
  deck.shuffle(pool, rng)
  local at = 0
  local function take()
    at = at + 1
    return pool[at]
  end
  for index = 1, #other.hand do other.hand[index] = take() end
  for index = 1, #other.threw do other.threw[index] = take() end
  for index = 1, #state.deck do state.deck[index] = take() end
  state.crib = {}
  for _, held in ipairs(own.threw) do state.crib[#state.crib + 1] = held end
  for _, held in ipairs(other.threw) do state.crib[#state.crib + 1] = held end
  other.picks = {}
  if #other.hand > 1 and state.phase == "discard" and rng:below(2) == 0 then other.picks = { other.hand[1] } end
end

test("a view depends on nothing that seat cannot see", function()
  local rng = testing.fastRng(41)
  for round = 1, 30 do
    local state = rules.new(entries(), 1, rng)
    local steps = 0
    while not rules.done(state) and steps < 120 do
      steps = steps + 1
      for _, viewer in ipairs({ 1, 2 }) do
        if state.phase ~= "cut" then
          local before = rules.viewFor(state, viewer)
          local copied = kit.plain(state)
          reshuffleHidden(copied, viewer, rng)
          truthy(kit.same(before, rules.viewFor(copied, viewer)), "seat " .. viewer .. " saw something hidden in " .. state.phase)
        end
      end
      if state.phase ~= "cut" then
        local public = rules.viewFor(state, nil)
        local copied = kit.plain(state)
        reshuffleHidden(copied, 1, rng)
        truthy(kit.same(public, rules.viewFor(copied, nil)), "the public view saw something hidden")
      end
      local seat = rules.waitingOn(state)[1]
      if seat then
        local id, value = rules.auto(state, seat)
        rules.act(state, seat, id, value, rng)
      else
        local id = rules.auto(state, nil)
        rules.act(state, nil, id, nil, rng)
      end
    end
    if round % 5 == 0 then testing.breathe() end
  end
end)

test("views hold only named fields, and events carry no hidden card", function()
  local rng = testing.fastRng(43)
  local seenCard = {}
  for round = 1, 60 do
    local state, events = rules.new(entries(), 1, rng)
    local function check(list)
      for _, ev in ipairs(list) do
        if ev.card ~= nil then
          truthy(ev.type == "peg" or ev.type == "starter", "only a played card or the starter is named: " .. ev.type)
          seenCard[ev.type] = true
        end
        eq(ev.cards, nil, "no list of cards")
        eq(ev.hand, nil, "no hand")
      end
    end
    check(events)
    while not rules.done(state) do
      for _, seat in ipairs({ 1, 2, false }) do
        for key in pairs(rules.viewFor(state, seat or nil)) do truthy(VIEW_FIELDS[key], "an unlisted field in a view: " .. key) end
      end
      local seat = rules.waitingOn(state)[1]
      if state.phase == "discard" and rng:below(2) == 0 then
        local player = state.players[seat]
        check(rules.act(state, seat, "pick", player.hand[1 + rng:below(#player.hand)], rng))
      end
      local id, value = rules.auto(state, seat)
      check(rules.act(state, seat, id, value, rng))
    end
    if round % 10 == 0 then testing.breathe() end
  end
  truthy(seenCard.peg and seenCard.starter, "both kinds of public card came up")
end)

test("what the other seat picked and threw is theirs, and the wall sees neither", function()
  local state = atDiscards()
  local hand = state.players[1].hand
  rules.act(state, 1, "pick", hand[1])
  rules.act(state, 1, "pick", hand[2])
  eq(#rules.viewFor(state, 1).mine.picks, 2, "the player sees their picks")
  eq(rules.viewFor(state, 2).players[1].picks, nil, "not the other seat")
  eq(rules.viewFor(state, nil).mine, nil, "not the wall")
  local threw = { hand[1], hand[2] }
  rules.act(state, 1, "discard")
  eq(#rules.viewFor(state, 1).mine.threw, 2, "the player remembers what they threw")
  eq(#rules.viewFor(state, 2).mine.threw, 0, "the other does not see it")
  local view = rules.viewFor(state, 2)
  eq(view.cribCards, 2, "only how many")
  for _, field in ipairs({ view.players[1].played, view.run, view.mine.cards }) do
    for _, seen in ipairs(field) do truthy(seen ~= threw[1] and seen ~= threw[2], "not on the other wall") end
  end
end)

test("the crib turns over only at its own step, and the hands at theirs", function()
  local state = atShow("5C 5D 5S JH", "2C 4D 6H 8S", "3C 3D 9H 9S", "5H")
  local crib = card("9S")
  local function shows()
    local view = rules.viewFor(state, 1)
    return view.shown and kit.shows(view.shown.cards, crib)
  end
  truthy(not shows(), "nothing up")
  computer(state)
  truthy(not shows(), "pone's hand")
  eq(rules.viewFor(state, nil).shown.what, "hand", "a hand")
  computer(state)
  truthy(not shows(), "the dealer's hand")
  computer(state)
  truthy(shows(), "and now the crib")
  eq(rules.viewFor(state, nil).shown.what, "crib", "the wall sees it too")
end)

test("a game won mid-pegging turns nothing else over", function()
  local state = pegging("7C 2D 3H 4S", "8D 9C 10D JH", { scores = { 90, 119 } })
  lay(state, "7C 8D")
  local view = rules.viewFor(state, 2)
  eq(view.shown, nil, "no show")
  eq(view.players[1].left, 3, "Ann's cards stay in her hand")
  for _, held in ipairs(cards("2D 3H 4S 2C 3C 4C 5C")) do
    truthy(not kit.shows(view.players[1].played, held), "nothing more of hers on Bob's wall")
    truthy(not kit.shows(view.mine.cards, held), "nor among his own")
    for _, item in ipairs(view.run) do truthy(item.card ~= held, "nor in the count") end
  end
end)

-- ------------------------------------------------------------------ states, pictures and sounds

test("states and views go through textutils", function()
  if not textutils then return end
  local rng = testing.fastRng(47)
  for _ = 1, 4 do
    local state = rules.new(entries(), 1, rng)
    while true do
      truthy(kit.same(state, textutils.unserialize(textutils.serialize(state))), "a state comes back whole")
      for _, seat in ipairs({ 1, 2 }) do textutils.serialize(rules.viewFor(state, seat)) end
      textutils.serialize(rules.viewFor(state, nil))
      if rules.done(state) then
        textutils.serialize(rules.result(state, 1))
        break
      end
      local seat = rules.waitingOn(state)[1]
      local id, value = rules.auto(state, seat)
      rules.act(state, seat, id, value, rng)
      testing.breathe()
    end
  end
end)

test("the wall's regions are on the screen and do not overlap, and only real moves are live", function()
  local rng = testing.fastRng(53)
  for round = 1, 40 do
    local state = rules.new(entries(), 1, rng)
    while not rules.done(state) do
      for _, seat in ipairs(rules.waitingOn(state)) do
        local regions = plugin.seatView.regions(rules.viewFor(state, seat))
        truthy(#regions > 0, "a seat with a move has something to tap")
        for index, region in ipairs(regions) do
          truthy(region.x >= 1 and region.x + region.w - 1 <= 121, "across")
          truthy(region.y >= 10 and region.y + region.h - 1 <= 67, "down")
          for other = index + 1, #regions do
            local b = regions[other]
            truthy(region.x + region.w <= b.x or b.x + b.w <= region.x or region.y + region.h <= b.y or b.y + b.h <= region.y, "overlap")
          end
          local copied = kit.plain(state)
          truthy(#rules.act(copied, seat, region.id, region.value, testing.fastRng(1)) > 0, "a region does something")
        end
      end
      eq(#plugin.seatView.regions(rules.viewFor(state, nil)), 0, "nothing to tap on the public view")
      local seat = rules.waitingOn(state)[1]
      local id, value = rules.auto(state, seat)
      rules.act(state, seat, id, value, rng)
    end
    if round % 5 == 0 then testing.breathe() end
  end
end)

test("the wall draws every kind of view without a mistake", function()
  local canvas = require("lib.casino.canvas")
  local rng = testing.fastRng(59)
  for round = 1, 2 do
    local state = rules.new({ { seat = 1, name = "A very long name in", stack = 500, stake = 25 }, { seat = 2, name = "Bob", stack = 500, stake = 25 } }, 1, rng)
    while true do
      for _, seat in ipairs({ 1, 2, false }) do
        local c = canvas.new(nil, 121, 81)
        plugin.seatView.draw(c, rules.viewFor(state, seat or nil), nil, { seat = seat or nil, name = "Ann" })
      end
      if rules.done(state) then break end
      local seat = rules.waitingOn(state)[1]
      local id, value = rules.auto(state, seat)
      rules.act(state, seat, id, value, rng)
      testing.breathe()
    end
  end
end)

test("every event has a length and a sound that exists", function()
  local audio = require("lib.casino.audio")
  local picks = require("lib.sound_picks")
  local known = { tap = true, chip = true, chipBig = true, error = true, deal = true, flip = true, start = true, tick = true, spin = true, stop = true, win = true,
    bigWin = true, lose = true, push = true, warn = true }
  truthy(audio.play, "the sound library")
  for _, ev in ipairs({
    { type = "cut", tie = true }, { type = "cut", tie = false }, { type = "deal" }, { type = "pick" }, { type = "discard" }, { type = "starter" }, { type = "heels" },
    { type = "peg", points = 0, count = 8 }, { type = "peg", points = 2, count = 15 }, { type = "peg", points = 2, count = 31 }, { type = "go" }, { type = "point" },
    { type = "show", points = 0 }, { type = "show", points = 8 }, { type = "show", points = 24 }, { type = "win", skunk = true }, { type = "win", skunk = false },
  }) do
    local seconds, sound = plugin.event(ev)
    truthy(type(seconds) == "number" and seconds > 0, "a length for " .. ev.type)
    truthy(sound ~= nil and (known[sound] or picks[sound]), "a sound for " .. ev.type .. ": " .. tostring(sound))
  end
  truthy(plugin.event({ type = "pegged" }) > 0, "the end of pegging has a length")
  truthy(plugin.event({ type = "nothing we know" }) > 0, "and so does anything else")
  truthy(plugin.event({ type = "show", points = 2 }) >= 5, "a step of the show stays up to be read")
end)
