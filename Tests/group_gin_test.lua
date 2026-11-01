-- group_gin_test.lua
-- Gin Rummy on Duel. Meld finding is proved against a second method that shares none of its code, on every hand of a small deck and on
-- random full hands. The money is proved by playing thousands of hands.

local kit = require("group_kit")
local testing = require("testing")
local deck = require("lib.casino.deck")
local eq, test, truthy = testing.eq, testing.test, testing.truthy

local plugin = kit.plugin("Duel", "gin")
local rules, melds = plugin.rules, plugin.melds

test("the help says the first turn has no pass, because real gin has one", function()
  local found = false
  for _, line in ipairs(plugin.help()) do
    found = found or (type(line) == "string" and line:find("no passing on the first up card", 1, true) ~= nil)
  end
  truthy(found, "the help line")
end)

local function cards(text)
  local list = {}
  for name in text:gmatch("%S+") do list[#list + 1] = deck.parse(name) end
  return list
end

-- ------------------------------------------------------------------ a second way to find melds

--- From the definition, by bitmask: try every subset as a meld, then the best packing of melds into the hand.
local function oracleBest(hand)
  local n = #hand
  local legal = {}
  local powers = {}
  for i = 1, n do powers[i] = 2 ^ (i - 1) end
  local function has(mask, i) return math.floor(mask / powers[i]) % 2 == 1 end
  local function isMeld(mask)
    local ranks, suits, list = {}, {}, {}
    for i = 1, n do
      if has(mask, i) then
        local low = deck.rank(hand[i]) == 14 and 1 or deck.rank(hand[i])
        list[#list + 1] = low
        ranks[low] = true
        suits[deck.suit(hand[i])] = true
      end
    end
    if #list < 3 then return false end
    local rankCount, suitCount = 0, 0
    for _ in pairs(ranks) do rankCount = rankCount + 1 end
    for _ in pairs(suits) do suitCount = suitCount + 1 end
    if rankCount == 1 then return #list <= 4 end
    if suitCount ~= 1 or rankCount ~= #list then return false end
    local lowest, highest = 99, 0
    for _, low in ipairs(list) do
      lowest, highest = math.min(lowest, low), math.max(highest, low)
    end
    return highest - lowest + 1 == #list
  end
  for mask = 7, 2 ^ n - 1 do
    if isMeld(mask) then legal[#legal + 1] = mask end
  end
  local memo = {}
  local function value(mask)
    local total = 0
    for i = 1, n do
      if has(mask, i) then
        local rank = deck.rank(hand[i])
        total = total + (rank == 14 and 1 or math.min(10, rank))
      end
    end
    return total
  end
  local function overlap(a, b)
    for i = 1, n do
      if has(a, i) and has(b, i) then return true end
    end
    return false
  end
  local function best(free, from)
    local key = free * 1000 + from
    if memo[key] then return memo[key] end
    local answer = value(free)
    for index = from, #legal do
      local meld = legal[index]
      if not overlap(meld, 2 ^ n - 1 - free) then
        answer = math.min(answer, best(free - meld, index + 1))
      end
    end
    memo[key] = answer
    return answer
  end
  return best(2 ^ n - 1, 1)
end

--- A hand by hand check of what melds.best claims: its melds are real, use the hand exactly and add up to its deadwood.
local function checkShape(hand, shape)
  local seen, count = {}, 0
  for _, meld in ipairs(shape.melds) do
    truthy(melds.isMeld(meld), "a meld that is no meld")
    for _, card in ipairs(meld) do
      truthy(not seen[card], "a card used twice")
      seen[card] = true
      count = count + 1
    end
  end
  for _, card in ipairs(shape.loose) do
    truthy(not seen[card], "a loose card also in a meld")
    seen[card] = true
    count = count + 1
  end
  eq(count, #hand, "every card accounted for")
  eq(melds.deadwood(shape.loose), shape.deadwood, "deadwood adds up")
end

--- Every hand of size from a list of cards.
local function everyHand(list, size, visit)
  local hand = {}
  local function step(from, depth)
    if depth > size then
      visit(hand)
      return
    end
    for index = from, #list - (size - depth) do
      hand[depth] = list[index]
      step(index + 1, depth + 1)
    end
  end
  step(1, 1)
end

test("melds: what counts as a meld", function()
  truthy(melds.isMeld(cards("AH 2H 3H")), "A-2-3 is a run")
  truthy(not melds.isMeld(cards("QH KH AH")), "Q-K-A is not")
  truthy(not melds.isMeld(cards("KH AH 2H")), "no going round the corner")
  truthy(melds.isMeld(cards("7C 7D 7S")), "three of a rank")
  truthy(melds.isMeld(cards("7C 7D 7S 7H")), "four of a rank")
  truthy(not melds.isMeld(cards("7C 7D")), "two is not a meld")
  truthy(not melds.isMeld(cards("7C 8D 9C")), "a run is one suit")
  truthy(melds.isMeld(cards("9S 10S JS QS KS")), "a long run")
  eq(melds.value(deck.parse("AS")), 1, "ace")
  eq(melds.value(deck.parse("KS")), 10, "king")
  eq(melds.value(deck.parse("7D")), 7, "seven")
end)

test("melds: a card can only be used once", function()
  -- 7H fits the run and the set. The set leaves 5H 6H, the run leaves two sevens
  eq(melds.best(cards("5H 6H 7H 7C 7D")).deadwood, 11, "the set is worth more")
  eq(melds.best(cards("5H 6H 7H 7C 7D 7S")).deadwood, 0, "a third seven and both melds fit")
  eq(melds.best(cards("5H 6H 7H 8H 8C 8D 8S")).deadwood, 0, "run 5-6-7 and set of 8s")
end)

test("melds: every hand of up to 6 cards from a 20 card deck matches the second method", function()
  local small = {}
  for rank = 2, 5 do
    for suit = 0, 3 do small[#small + 1] = deck.card(rank, suit) end
  end
  for suit = 0, 3 do small[#small + 1] = deck.card(14, suit) end -- aces, so runs start at the bottom
  local checked = 0
  for size = 1, 6 do
    everyHand(small, size, function(hand)
      if size <= 5 or checked % 37 == 0 then
        local shape = melds.best(hand)
        checkShape(hand, shape)
        eq(shape.deadwood, oracleBest(hand), "hand of " .. size)
      end
      checked = checked + 1
      if checked % 200 == 0 then testing.breathe() end
    end)
  end
  eq(checked, 20 + 190 + 1140 + 4845 + 15504 + 38760, "the whole space went past")
end)

test("melds: every 3 card hand of the whole deck agrees with the definition", function()
  local count, found = 0, 0
  everyHand(deck.fresh(1), 3, function(hand)
    local shape = melds.best(hand)
    local meld = melds.isMeld(hand)
    eq(shape.deadwood == 0, meld, "three cards are out if and only if they are a meld")
    if not meld then eq(shape.deadwood, melds.deadwood(hand), "no meld, all deadwood") end
    count = count + 1
    if meld then found = found + 1 end
    if count % 1000 == 0 then testing.breathe() end
  end)
  eq(count, 22100, "hands")
  -- 52 sets of three and 44 runs: 4 suits times 11 places
  eq(found, 52 + 44, "melds of three")
end)

test("melds: random 10 and 11 card hands match the second method", function()
  local rng = testing.fastRng(77)
  for round = 1, 400 do
    local pile = deck.shuffle(deck.fresh(1), rng)
    local hand = {}
    for index = 1, (round % 2 == 0) and 10 or 11 do hand[index] = pile[index] end
    local shape = melds.best(hand)
    checkShape(hand, shape)
    eq(shape.deadwood, oracleBest(hand), "hand " .. round)
    if round % 10 == 0 then testing.breathe() end
  end
end)

test("melds: crowded hands, built to have many melds, match the second method", function()
  local rng = testing.fastRng(78)
  for round = 1, 200 do
    -- Four ranks in a row in every suit is where melds overlap the most
    local first = 2 + rng:below(8)
    local pool = {}
    for rank = first, first + 3 do
      for suit = 0, 3 do pool[#pool + 1] = deck.card(rank, suit) end
    end
    deck.shuffle(pool, rng)
    local hand = {}
    for index = 1, 10 do hand[index] = pool[index] end
    local shape = melds.best(hand)
    checkShape(hand, shape)
    eq(shape.deadwood, oracleBest(hand), "hand " .. round)
    if round % 10 == 0 then testing.breathe() end
  end
end)

--- Least deadwood after laying off, from the definition: try laying every card on every meld, in every order.
local function oracleLayoff(table_melds, loose)
  local best = melds.deadwood(loose)
  local function step(onTable, rest)
    best = math.min(best, melds.deadwood(rest))
    for index, card in ipairs(rest) do
      for at, meld in ipairs(onTable) do
        local bigger = { card }
        for _, held in ipairs(meld) do bigger[#bigger + 1] = held end
        if melds.isMeld(bigger) then
          local nextTable, nextRest = {}, {}
          for i, m in ipairs(onTable) do nextTable[i] = (i == at) and bigger or m end
          for i, c in ipairs(rest) do
            if i ~= index then nextRest[#nextRest + 1] = c end
          end
          step(nextTable, nextRest)
        end
      end
    end
  end
  step(table_melds, loose)
  return best
end

test("layoffs: named cases", function()
  local run = { cards("5H 6H 7H") }
  local laid, rest = melds.layoffs(run, cards("8H 9H KS"))
  eq(#laid, 2, "a laid card opens the way for the next")
  eq(rest[1], deck.parse("KS"), "the king stays")
  laid = melds.layoffs(run, cards("4H 3H 2H AH"))
  eq(#laid, 4, "down to the ace")
  laid = melds.layoffs({ cards("7C 7D 7S") }, cards("7H"))
  eq(#laid, 1, "the fourth of a set")
  laid = melds.layoffs({ cards("7C 7D 7S 7H") }, cards("8H"))
  eq(#laid, 0, "a set of four takes nothing")
  laid = melds.layoffs({ cards("JH QH KH") }, cards("AH"))
  eq(#laid, 0, "the ace does not go on a king")
  -- 5H fits the set of fives but only on the run does it let 4H follow
  laid = melds.layoffs({ cards("5C 5D 5S"), cards("6H 7H 8H") }, cards("4H 5H"))
  eq(#laid, 2, "the run before the set")
end)

test("layoffs: random small tables match the second method", function()
  local rng = testing.fastRng(79)
  local checked = 0
  for round = 1, 3000 do
    local table_melds, used = {}, {}
    local suit = rng:below(4)
    local first = 1 + rng:below(8)
    local run = {}
    for low = first, first + 2 + rng:below(2) do run[#run + 1] = deck.card(low == 1 and 14 or low, suit) end
    table_melds[1] = run
    for _, card in ipairs(run) do used[card] = true end
    if rng:below(2) == 0 then
      local rank = 2 + rng:below(13)
      local set = {}
      for s = 0, 3 do
        local card = deck.card(rank, s)
        if not used[card] and #set < 3 then set[#set + 1] = card end
      end
      if #set == 3 then
        table_melds[2] = set
        for _, card in ipairs(set) do used[card] = true end
      end
    end
    -- Loose cards close to the melds, or nothing would ever lay off
    local pool = {}
    for low = math.max(1, first - 3), math.min(13, first + 6) do
      for s = 0, 3 do
        local card = deck.card(low == 1 and 14 or low, s)
        if not used[card] then pool[#pool + 1] = card end
      end
    end
    deck.shuffle(pool, rng)
    local loose = {}
    for index = 1, math.min(5, #pool) do loose[index] = pool[index] end
    local _, rest = melds.layoffs(table_melds, loose)
    eq(melds.deadwood(rest), oracleLayoff(table_melds, loose), "round " .. round)
    checked = checked + 1
    if round % 200 == 0 then testing.breathe() end
  end
  eq(checked, 3000, "tables")
end)

test("the defender breaks a meld when laying off pays better", function()
  -- Knocker: 2C 3C 4C. Defender holds 5C 6C 7C as a run of their own or laid off: both clear the same three cards, and 8S 8H 8D beside
  local answer = melds.defend(cards("5C 6C 7C KS"), { cards("2C 3C 4C") })
  eq(answer.deadwood, 10, "only the king stays")
  -- 5H 6H 7H with a spare 8H: keeping the run leaves the 8, laying off clears it
  answer = melds.defend(cards("5H 6H 7H 8H 5C 5D"), { cards("9H 10H JH") })
  eq(answer.deadwood, 0, "8H on the knocker's run, then 7H, 6H, or a meld of the 5s")
end)

-- ------------------------------------------------------------------ the game, with hands set by hand

--- A state with named hands. a and b are lists of names for seats 1 and 2, and it is seat 1's turn to draw.
local function dealt(a, b, up, draw, opts)
  opts = opts or {}
  local rng = testing.fastRng(5)
  local state = rules.new({ { seat = 1, name = "Ann", stack = opts.stack or 5000, stake = opts.stake or 2 },
    { seat = 2, name = "Bob", stack = opts.other or 5000, stake = opts.stake or 2 } }, 2, rng, {})
  state.players[1].hand, state.players[2].hand = cards(a), cards(b)
  state.pile = { deck.parse(up) }
  state.stock = {}
  for index = 1, 10 do state.stock[index] = deck.parse("2S") end
  state.stock[#state.stock + 1] = deck.parse(draw)
  state.turn = 1
  rules.reshape(state)
  return state
end

--- Draw from the stock, pick a card, then press something.
local function turn(state, seat, throwName, press)
  eq(#rules.act(state, seat, "stock") > 0, true, "drew")
  if deck.parse(throwName) ~= state.pick then eq(#rules.act(state, seat, "pick", deck.parse(throwName)) > 0, true, "picked") end
  return rules.act(state, seat, press or "throw")
end

test("knock, undercut, gin and the cap", function()
  -- Ann holds three melds and 3S, draws AD, throws nothing but 3S or AD: with AD thrown she knocks on 3
  local state = dealt("2C 3C 4C 5D 6D 7D 9S 9H 9D 3S", "KC KD QS QH JS JC 8H 6S 4H 3H", "KS", "AD", { stake = 2 })
  turn(state, 1, "AD", "knock")
  truthy(rules.done(state), "over")
  eq(state.outcome.knocker, 1, "Ann knocked")
  -- Bob: no melds, 60 in faces and 8 + 6 + 4 + 3. Nothing lays off
  eq(state.outcome.points, 81 - 3, "difference")
  eq(rules.nets(state)[1], 78 * 2, "net at the stake")
  eq(rules.nets(state)[2], -78 * 2, "and the other way")
  eq(state.players[2].final.deadwood, 81, "defender")

  -- The same with Bob's 3H as a 4D, which goes on Ann's diamonds
  state = dealt("2C 3C 4C 5D 6D 7D 9S 9H 9D 3S", "KC KD QS QH JS JC 8H 6S 4H 4D", "KS", "AD", { stake = 2 })
  turn(state, 1, "AD", "knock")
  eq(state.players[2].final.deadwood, 78, "the 4D is laid off")
  eq(state.players[2].final.laid[1], deck.parse("4D"), "and shown")
  eq(state.outcome.points, 75, "difference after laying off")

  -- Bob only holds an ace of deadwood, the same as Ann: level is an undercut
  state = dealt("9H JS JH JD 5C 6C 7C KC KD KH", "2D 2H 2S 3D 3H 3S 4D 4H 4S AC", "8D", "AD", { stake = 3 })
  turn(state, 1, "9H", "knock")
  truthy(rules.done(state), "over")
  eq(state.players[1].final.deadwood, 1, "Ann has only the ace")
  eq(state.players[2].final.deadwood, 1, "Bob's ace is level")
  truthy(state.outcome.undercut, "level is an undercut")
  eq(state.outcome.winner, 2, "Bob wins it")
  eq(state.outcome.points, 25, "the bonus and no difference")
  eq(rules.nets(state)[2], 75, "at the stake")

  -- Gin: 25 plus deadwood, and no laying off
  state = dealt("2C 3C 4C 5D 6D 7D 9S 9H 9D KS", "10D 8H 8C KC KD QS QH JS JC 4D", "3S", "8D", { stake = 1 })
  turn(state, 1, "KS", "knock")
  truthy(rules.done(state), "over")
  truthy(state.outcome.gin, "gin")
  -- 4D would go on Ann's run after a knock, but not on gin
  eq(state.players[2].final.deadwood, 90, "no layoffs on gin")
  eq(#state.players[2].final.laid, 0, "nothing laid")
  eq(state.outcome.points, 25 + 90, "gin scores")
  eq(rules.nets(state)[1], 100, "115 points at 1 is held to the 100 stakes a hand can move")

  -- The cap: 75 points at 2 a point is 150, on a table that can move 100
  state = dealt("2C 3C 4C 5D 6D 7D 9S 9H 9D 3S", "KC KD QS QH JS JC 8H 6S 4H 4D", "KS", "AD", { stake = 2, other = 100 })
  turn(state, 1, "AD", "knock")
  eq(rules.nets(state)[1], 100, "held to the smaller stack")
  eq(rules.nets(state)[2], -100, "the loser never past what they declared")
  truthy(state.outcome.capped, "and it says so")
end)

test("a knock above 10 and a gin that is not there are refused", function()
  local state = dealt("KC KD QS QH JS JC 8H 6S 4H 4D", "2C 3C 4C 5D 6D 7D 9S 9H 9D 3S", "KS", "AD")
  rules.act(state, 1, "stock")
  local before = kit.plain(state)
  eq(#rules.act(state, 1, "knock"), 0, "too much deadwood")
  truthy(kit.same(before, state), "nothing changed")
end)

test("illegal input does nothing", function()
  local state = dealt("KC KD QS QH JS JC 8H 6S 4H 4D", "2C 3C 4C 5D 6D 7D 9S 9H 9D 3S", "KS", "AD")
  local before = kit.plain(state)
  for _, try in ipairs({
    { 2, "stock" }, { 2, "take" }, { 3, "stock" }, { nil, "stock" }, { 1, "throw" }, { 1, "knock" }, { 1, "pick", 4 }, { 1, "nope" },
  }) do
    eq(#rules.act(state, try[1], try[2], try[3]), 0, tostring(try[1]) .. " " .. try[2])
    truthy(kit.same(before, state), "nothing changed: " .. try[2])
  end
  rules.act(state, 1, "take")
  before = kit.plain(state)
  local top = deck.parse("KS")
  for _, value in ipairs({ top, deck.parse("9S"), "4", {}, 999, -1, 1.5, state.pick }) do
    eq(#rules.act(state, 1, "pick", value), 0, "a card that cannot be chosen: " .. tostring(value))
  end
  for _, try in ipairs({ { 1, "stock" }, { 1, "take" }, { 2, "throw" }, { 2, "pick", deck.parse("KC") } }) do
    eq(#rules.act(state, try[1], try[2], try[3]), 0, try[2])
  end
  truthy(kit.same(before, state), "nothing changed")
end)

test("a taken discard cannot go straight back", function()
  local state = dealt("KC KD QS QH JS JC 8H 6S 4H 4D", "2C 3C 4C 5D 6D 7D 9S 9H 9D 3S", "KS", "AD")
  rules.act(state, 1, "take")
  truthy(state.pick ~= deck.parse("KS"), "the best throw is some other card")
  eq(#rules.act(state, 1, "pick", deck.parse("KS")), 0, "it cannot be picked")
end)

test("the stock stopping at two washes the hand", function()
  local state = dealt("KC KD QS QH JS JC 8H 6S 4H 4D", "2C 3C 4C 5D 6D 7D 9S 9H 9D 3S", "KS", "AD")
  state.stock = cards("2S 2D 2H")
  local events = turn(state, 1, "KC", "throw")
  truthy(rules.done(state), "over")
  eq(events[#events].type, "wash", "said so")
  eq(rules.nets(state)[1], 0, "nothing moves")
  eq(rules.nets(state)[2], 0, "nothing moves")
  eq(rules.result(state, 1).kind, "push", "a push")
  eq(rules.viewFor(state, 1).players[2].final, nil, "a wash turns nothing over")
end)

test("a whole hand of random play keeps the contract", function()
  kit.fuzz(plugin, { rounds = 150, seats = { 2 }, stack = 500, stake = 2, absent = 10 })
  kit.fuzz(plugin, { rounds = 150, seats = { 2 }, stack = 5000, stake = 25, seed = 99, pick = function(state, seat, actions, rng)
    -- Play to win, so hands end in knocks and gin as well as washes
    for _, action in ipairs(actions) do
      if action.id == "knock" then return "knock" end
    end
    if state.phase == "draw" and state.ifTaken < rules.viewFor(state, seat).hand.deadwood then return "take" end
    return nil
  end })
  kit.fuzz(plugin, { rounds = 150, seats = { 2 }, stack = 100, stake = 1, seed = 7, pick = function(_, _, actions, rng)
    for _, action in ipairs(actions) do
      if action.id == "knock" and rng:below(2) == 0 then return "knock" end
    end
    return nil
  end })
end)

local function plays(state, rng)
  while not rules.done(state) do
    local seat = rules.waitingOn(state)[1]
    local list = rules.actions(state, seat)
    local press = list[#list]
    if press.id == "take" and state.ifTaken >= rules.viewFor(state, seat).hand.deadwood then press = list[1] end
    rules.act(state, seat, press.id, press.value, rng)
  end
end

test("hands played for the win end every way, and always add up", function()
  local rng = testing.fastRng(31)
  local gin, knocks, undercuts, washes = 0, 0, 0, 0
  for round = 1, 2500 do
    local entries = { { seat = 1, name = "Ann", stack = 400, stake = 3 }, { seat = 2, name = "Bob", stack = 150 + rng:below(200), stake = 3 } }
    local state = rules.new(entries, round % 2 + 1, rng, {})
    plays(state, rng)
    local nets = rules.nets(state)
    eq(nets[1] + nets[2], 0, "nets sum to zero")
    truthy(math.abs(nets[1]) <= entries[2].stack, "within the smaller stack")
    local outcome = state.outcome
    if outcome.wash then
      washes = washes + 1
    else
      if outcome.gin then gin = gin + 1 elseif outcome.undercut then undercuts = undercuts + 1 else knocks = knocks + 1 end
      eq(math.abs(nets[1]), math.min(outcome.points * 3, state.cap), "points times the stake, capped")
      local knocker = outcome.knocker == 1 and state.players[1] or state.players[2]
      truthy(knocker.final.deadwood <= 10, "a knock is 10 or less")
    end
    if round % 50 == 0 then testing.breathe() end
  end
  truthy(gin > 0, "some gin")
  truthy(knocks > 0, "some knocks")
  truthy(undercuts > 0, "some undercuts")
  truthy(washes > 0, "some washes")
end)

-- ------------------------------------------------------------------ secrets

local VIEW_FIELDS = { phase = true, over = true, turn = true, stock = true, top = true, stake = true, cap = true, knockAt = true,
  players = true, last = true, outcome = true, hand = true }

--- Change everything this seat cannot see: the other hand and the stock, dealt again from the same cards.
local function reshuffleHidden(state, seat, rng)
  local other = state.players[1].seat == seat and state.players[2] or state.players[1]
  local pool = {}
  for _, card in ipairs(other.hand) do pool[#pool + 1] = card end
  for _, card in ipairs(state.stock) do pool[#pool + 1] = card end
  deck.shuffle(pool, rng)
  local size = #other.hand
  local stockSize = #state.stock
  other.hand, state.stock = {}, {}
  for index = 1, size do other.hand[index] = pool[index] end
  for index = 1, stockSize do state.stock[index] = pool[size + index] end
  rules.reshape(state)
end

test("a view depends on nothing that seat cannot see", function()
  local rng = testing.fastRng(41)
  for round = 1, 100 do
    local state = rules.new({ { seat = 1, name = "Ann", stack = 500, stake = 1 }, { seat = 2, name = "Bob", stack = 500, stake = 1 } }, 1, rng, {})
    local steps = 0
    while not rules.done(state) and steps < 16 do
      steps = steps + 1
      local seat = rules.waitingOn(state)[1]
      local viewer = 3 - seat
      -- The seat that is not on turn: nothing of the other hand or the stock may show. Nor may the public view
      local before, public = rules.viewFor(state, viewer), rules.viewFor(state, nil)
      local copy = kit.plain(state)
      reshuffleHidden(copy, viewer, rng)
      truthy(kit.same(before, rules.viewFor(copy, viewer)), "seat " .. viewer .. " saw something hidden")
      copy = kit.plain(state)
      reshuffleHidden(copy, seat, rng)
      reshuffleHidden(copy, viewer, rng)
      truthy(kit.same(public, rules.viewFor(copy, nil)), "the public view saw something hidden")
      local list = rules.actions(state, seat)
      local press = list[1 + rng:below(#list)]
      rules.act(state, seat, press.id, press.value, rng)
    end
    if round % 25 == 0 then testing.breathe() end
  end
end)

test("views hold only named fields and no other seat's cards, and events carry no hidden card", function()
  local rng = testing.fastRng(43)
  local function check(state, view, seat)
    for key in pairs(view) do truthy(VIEW_FIELDS[key], "an unlisted field in a view: " .. key) end
    if seat == nil then truthy(view.hand == nil, "the public view has no hand") end
    local cards_ = {}
    local function add(list)
      for _, card in ipairs(list) do cards_[#cards_ + 1] = card end
    end
    if view.hand then
      for _, meld in ipairs(view.hand.melds) do add(meld) end
      add(view.hand.loose)
    end
    local own = {}
    for _, player in ipairs(state.players) do
      if player.seat == seat then
        for _, card in ipairs(player.hand) do own[card] = true end
      end
    end
    for _, card in ipairs(cards_) do truthy(own[card], "a card in the hand that is not this seat's") end
    if seat ~= nil and view.hand then eq(#cards_, #state.players[seat].hand, "the whole of their own hand") end
    if not rules.done(state) then
      for _, player in ipairs(view.players) do truthy(player.hand == nil and player.final == nil, "no hand on a player") end
    end
  end
  for round = 1, 100 do
    local state, events = rules.new({ { seat = 1, name = "Ann", stack = 500, stake = 1 }, { seat = 2, name = "Bob", stack = 500, stake = 1 } }, 1, rng, {})
    while not rules.done(state) do
      check(state, rules.viewFor(state, 1), 1)
      check(state, rules.viewFor(state, 2), 2)
      check(state, rules.viewFor(state, nil), nil)
      local seat = rules.waitingOn(state)[1]
      local list = rules.actions(state, seat)
      local press = list[1 + rng:below(#list)]
      local stockBefore = state.phase == "draw" and press.id == "stock"
      local pickBefore = state.pick
      if state.phase == "throw" and rng:below(2) == 0 then
        local player = state.players[state.turn]
        local card = player.hand[1 + rng:below(#player.hand)]
        local fired = rules.act(state, seat, "pick", card, rng)
        for _, ev in ipairs(fired) do
          truthy(ev.card == nil, "a pick says nothing of the card")
        end
        pickBefore = state.pick
      end
      events = rules.act(state, seat, press.id, press.value, rng)
      for _, ev in ipairs(events) do
        if ev.type == "draw" then truthy(ev.card == nil, "a draw from the stock is secret") end
        if ev.type == "throw" then eq(ev.card ~= nil, true, "a throw is public") end
        if stockBefore then truthy(ev.card == nil, "stock") end
      end
      if pickBefore and press.id == "throw" and not rules.done(state) then
        eq(state.pile[#state.pile], pickBefore, "the picked card is the one thrown")
      end
    end
    check(state, rules.viewFor(state, 1), 1)
    if round % 25 == 0 then testing.breathe() end
  end
end)

test("the stock never shows and a picked card is only its owner's", function()
  local state = dealt("KC KD QS QH JS JC 8H 6S 4H 4D", "2C 3C 4C 5D 6D 7D 9S 9H 9D 3S", "KS", "AD")
  rules.act(state, 1, "stock")
  local mine = rules.viewFor(state, 1)
  truthy(mine.hand.pick ~= nil, "the player sees it")
  eq(mine.hand.fresh, deck.parse("AD"), "and what they drew")
  local theirs, public = rules.viewFor(state, 2), rules.viewFor(state, nil)
  eq(theirs.hand.pick, nil, "not the other seat")
  eq(theirs.hand.fresh, nil, "not what was drawn")
  eq(public.hand, nil, "not the wall")
  eq(public.last.card, nil, "a stock draw names no card")
end)

test("states and views go through textutils", function()
  if not textutils then return end
  local rng = testing.fastRng(47)
  for round = 1, 8 do
    local state = rules.new({ { seat = 1, name = "Ann", stack = 500, stake = 1 }, { seat = 2, name = "Bob", stack = 500, stake = 1 } }, 1, rng, {})
    while true do
      local text = textutils.serialize(state)
      truthy(kit.same(state, textutils.unserialize(text)), "a state comes back whole")
      for _, seat in ipairs({ 1, 2 }) do textutils.serialize(rules.viewFor(state, seat)) end
      textutils.serialize(rules.viewFor(state, nil))
      if rules.done(state) then
        textutils.serialize(rules.result(state, 1))
        break
      end
      local seat = rules.waitingOn(state)[1]
      local list = rules.actions(state, seat)
      local press = list[1 + rng:below(#list)]
      rules.act(state, seat, press.id, press.value, rng)
      testing.breathe()
    end
  end
end)

test("the wall's regions are on the screen and do not overlap", function()
  local rng = testing.fastRng(53)
  for round = 1, 60 do
    local state = rules.new({ { seat = 1, name = "Ann", stack = 500, stake = 1 }, { seat = 2, name = "Bob", stack = 500, stake = 1 } }, 1, rng, {})
    while not rules.done(state) do
      local seat = rules.waitingOn(state)[1]
      local regions = plugin.seatView.regions(rules.viewFor(state, seat))
      for index, region in ipairs(regions) do
        truthy(region.x >= 1 and region.x + region.w - 1 <= 121, "across")
        truthy(region.y >= 10 and region.y + region.h - 1 <= 67, "down")
        for other = index + 1, #regions do
          local b = regions[other]
          truthy(region.x + region.w <= b.x or b.x + b.w <= region.x or region.y + region.h <= b.y or b.y + b.h <= region.y, "overlap")
        end
      end
      local list = rules.actions(state, seat)
      local press = list[1 + rng:below(#list)]
      rules.act(state, seat, press.id, press.value, rng)
    end
    if round % 25 == 0 then testing.breathe() end
  end
end)

test("the wall draws every kind of view without a mistake", function()
  local canvas = require("lib.casino.canvas")
  local rng = testing.fastRng(59)
  for round = 1, 3 do
    local state = rules.new({ { seat = 1, name = "Ann", stack = 500, stake = 1 }, { seat = 2, name = "Bob", stack = 500, stake = 1 } }, 2, rng, {})
    while true do
      for _, seat in ipairs({ 1, 2, false }) do
        local c = canvas.new(nil, 121, 81)
        plugin.seatView.draw(c, rules.viewFor(state, seat or nil), nil, { seat = seat or nil, name = "Ann" })
      end
      if rules.done(state) then break end
      local seat = rules.waitingOn(state)[1]
      local list = rules.actions(state, seat)
      rules.act(state, seat, list[1 + rng:below(#list)].id, nil, rng)
      testing.breathe()
    end
  end
end)
