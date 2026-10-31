-- pokertable_test.lua
-- Five-card draw: side pots, odd chips, betting, the draw, settlement order. Chips and tokens must always add up.

local deck = require("lib.casino.deck")
local rules = require("pokertable_rules")
local t = require("testing")

--- Players for the pot functions: { total, score, folded }.
local function table_(rows)
  local players = {}
  for i, row in ipairs(rows) do
    players[i] = { total = row[1], score = row[2], folded = row[3] == true }
  end
  return players
end

--- Award and return each player's net, checking conservation.
local function settle(rows, button)
  local players = table_(rows)
  local pots = rules.pots(players)
  rules.award(pots, players, button or 1)
  local nets, sum = {}, 0
  for i, player in ipairs(players) do
    nets[i] = player.won - player.total
    sum = sum + nets[i]
  end
  t.eq(sum, 0, "nets add up to zero")
  return nets, pots
end

local function same(actual, expected, what)
  for i = 1, math.max(#actual, #expected) do
    t.eq(actual[i], expected[i], (what or "net") .. " " .. i)
  end
end

t.test("one pot, one winner", function()
  local nets, pots = settle({ { 100, 9 }, { 100, 5 }, { 100, 3 } })
  t.eq(#pots, 1)
  t.eq(pots[1].amount, 300)
  same(nets, { 200, -100, -100 })
end)

t.test("a folded player's chips stay in the pot but cannot win", function()
  local nets = settle({ { 40, 99, true }, { 100, 5 }, { 100, 3 } })
  same(nets, { -40, 140, -100 })
end)

t.test("all-ins of three different sizes make a main pot and two side pots", function()
  -- A 100, B 250, C 400, D 400: main 400, first side 450, second side 300
  local _, pots = settle({ { 100, 1 }, { 250, 2 }, { 400, 3 }, { 400, 4 } })
  t.eq(#pots, 3, "pots")
  t.eq(pots[1].amount, 400)
  t.eq(pots[2].amount, 450)
  t.eq(pots[3].amount, 300)
  t.eq(#pots[1].eligible, 4)
  t.eq(#pots[2].eligible, 3)
  t.eq(#pots[3].eligible, 2)
end)

t.test("the short stack wins only what it could match", function()
  local nets = settle({ { 100, 9 }, { 250, 5 }, { 400, 3 }, { 400, 1 } })
  -- main 400 to A, side 450 to B, top 300 to C
  same(nets, { 300, 200, -100, -400 })
end)

t.test("each pot goes to the best hand that can win it", function()
  -- C best overall takes all above 100; A beats B and D for the main pot only when C is short
  local nets = settle({ { 400, 5 }, { 400, 6 }, { 100, 9 }, { 250, 7 } })
  -- main 400 to C, side (150*3=450) to D, top (150*2=300) to B
  same(nets, { -400, 300 - 400, 400 - 100, 450 - 250 })
end)

t.test("a tie for the main pot, a clear winner for the side pot", function()
  -- A and B tie on the main pot of 300; A alone is in the side pot with C
  local nets = settle({ { 200, 8 }, { 100, 8 }, { 200, 2 } })
  -- main 300: 150 each. side 200: A
  same(nets, { 150 + 200 - 200, 150 - 100, -200 })
end)

t.test("a tie at the top of three all-ins splits every pot it reaches", function()
  local nets = settle({ { 100, 9 }, { 250, 9 }, { 400, 9 }, { 400, 1 } })
  -- main 400 three ways with 1 odd, side 450 two ways... A, B, C all hold 9
  -- pot1 400: 133 each, odd 1 to first left of button (button 1 means B)
  -- pot2 450: B and C 225 each
  -- pot3 300: C alone
  same(nets, { 133 - 100, 134 + 225 - 250, 133 + 225 + 300 - 400, -400 })
end)

t.test("odd chips go to the first winner left of the button", function()
  local nets = settle({ { 25, 7 }, { 25, 7 }, { 25, 1 } }, 3)
  -- 75 split two ways: 37 and 38. Left of seat 3 is seat 1
  same(nets, { 38 - 25, 37 - 25, -25 })
  local other = settle({ { 25, 7 }, { 25, 7 }, { 25, 1 } }, 1)
  same(other, { 37 - 25, 38 - 25, -25 })
end)

t.test("two odd chips both go to the first winner", function()
  local nets, pots = settle({ { 30, 7 }, { 30, 7 }, { 30, 7 }, { 5, 1, true }, { 6, 2, true } }, 2)
  -- 101 three ways: 33 each and 2 odd, left of seat 2 is seat 3
  t.eq(pots[1].odd, 2)
  same(nets, { 33 - 30, 33 - 30, 35 - 30, -5, -6 })
end)

t.test("a fold around the button keeps odd chips to the left of it", function()
  local nets = settle({ { 15, 4, true }, { 15, 4 }, { 15, 4 }, { 16, 4 }, { 2, 1, true } }, 1)
  -- main 15*4+2=62 three ways is 20 each, 2 odd to seat 2; top chip of 1 returns to seat 4
  same(nets, { -15, 22 - 15, 20 - 15, 21 - 16, -2 })
end)

t.test("an uncalled top bet comes straight back", function()
  local nets, pots = settle({ { 300, 1 }, { 100, 9 } })
  t.eq(#pots, 2)
  t.eq(#pots[2].eligible, 1)
  same(nets, { -100, 100 })
end)

t.test("folded chips above every live player join the last pot", function()
  local nets = settle({ { 80, 0, true }, { 50, 3 }, { 50, 2 } })
  same(nets, { -80, 130, -50 })
end)

--- The same pots, worked out one chip level at a time, for comparison with the real thing.
local function oracle(players)
  local top = 0
  for _, player in ipairs(players) do top = math.max(top, player.total) end
  local byKey, order, carry = {}, {}, 0
  for level = top, 1, -1 do
    local amount, eligible = 0, {}
    for i, player in ipairs(players) do
      if player.total >= level then
        amount = amount + 1
        if not player.folded then eligible[#eligible + 1] = i end
      end
    end
    if #eligible == 0 then
      carry = carry + amount
    else
      local key = table.concat(eligible, ",")
      if not byKey[key] then
        byKey[key] = 0
        order[#order + 1] = key
      end
      byKey[key] = byKey[key] + amount + carry
      carry = 0
    end
  end
  return byKey, #order
end

t.test("every small table of totals, folds and ties matches a chip by chip count", function()
  local levels = { 0, 1, 2, 3, 5, 8 }
  local checked = 0

  local function verify(rows, players)
    local live = 0
    for _, player in ipairs(players) do
      if not player.folded and player.total > 0 then live = live + 1 end
    end
    if live == 0 then return end
    local pots = rules.pots(players)
    local byKey, count = oracle(players)
    t.eq(#pots, count, "pot count")
    for _, pot in ipairs(pots) do
      t.eq(pot.amount, byKey[table.concat(pot.eligible, ",")], "pot size")
    end
    for button = 1, #players do
      rules.award(pots, players, button)
      local sum = 0
      for _, player in ipairs(players) do
        sum = sum + player.won - player.total
        t.truthy(player.won >= 0)
        if player.folded then t.eq(player.won, 0, "a folded player wins nothing") end
      end
      t.eq(sum, 0, "conservation")
      for _, pot in ipairs(pots) do
        -- The winners of each pot are the left-most first, and shares never differ by more than the odd chips
        t.eq(pot.share * #pot.winners + pot.odd, pot.amount, "shares add up")
        t.truthy(pot.odd < #pot.winners, "odd chips are fewer than winners")
      end
      checked = checked + 1
    end
    return rows
  end

  for _, size in ipairs({ 2, 3, 4 }) do
    local choices = size == 4 and { 0, 2, 5 } or levels
    local function walk(depth, players)
      if depth > size then
        verify(nil, players)
        return
      end
      if depth % 2 == 0 then t.breathe() end
      for _, total in ipairs(choices) do
        for _, score in ipairs({ 1, 2 }) do
          for _, folded in ipairs({ false, true }) do
            players[depth] = { total = total, score = score, folded = folded }
            walk(depth + 1, players)
          end
        end
      end
      players[depth] = nil
    end
    walk(1, {})
    t.breathe()
  end
  t.truthy(checked > 50000, "checked " .. checked)
end)

-- ------------------------------------------------------------------ playing a hand

--- A hand with these stacks whose deal order is these cards, by name.
local function deal(stacks, button, cards)
  local entries = {}
  for i, stack in ipairs(stacks) do
    entries[i] = { name = "P" .. i, stack = stack, seat = i }
  end
  local rng = t.fastRng(5)
  local realShuffle = deck.shuffle
  if cards then
    deck.shuffle = function(list, r)
      realShuffle(list, r)
      return deck.stack(list, cards)
    end
  end
  local state, events = rules.new(entries, button or #stacks, rng)
  deck.shuffle = realShuffle
  return state, events
end

local function ids(state)
  local list = {}
  for _, action in ipairs(rules.actions(state)) do list[#list + 1] = action.id end
  return table.concat(list, " ")
end

local function play(state, script)
  for word in script:gmatch("%S+") do
    local who = rules.actor(state)
    t.truthy(who, "a turn for " .. word)
    t.truthy(#rules.act(state, word) > 0, word .. " by " .. who .. " in " .. state.phase)
  end
end

t.test("antes go in and the player left of the button acts first", function()
  local state = deal({ 200, 200, 200 }, 3)
  t.eq(rules.potTotal(state), 15)
  t.eq(state.phase, "bet1")
  t.eq(rules.actor(state), "P1")
  t.eq(ids(state), "check raise")
  local turned = deal({ 200, 200, 200 }, 1)
  t.eq(rules.actor(turned), "P2", "the button moves the first turn")
  for _, player in ipairs(state.players) do t.eq(#player.hand, 5, "five cards") end
end)

t.test("the first round bets small and the second big", function()
  local state = deal({ 200, 200 })
  play(state, "raise call draw draw")
  t.eq(state.phase, "bet2")
  t.eq(rules.potTotal(state), 30)
  play(state, "raise")
  t.eq(rules.potTotal(state), 50, "the big bet")
  play(state, "call")
  t.truthy(rules.done(state))
  t.eq(rules.potTotal(state), 70)
end)

t.test("a round stops at a bet and three raises", function()
  local state = deal({ 500, 500 })
  play(state, "raise raise raise raise")
  t.eq(ids(state), "fold call", "no fifth bet")
  t.eq(state.bets, 4)
end)

t.test("everyone gets to answer a raise", function()
  local state = deal({ 500, 500, 500 })
  play(state, "check raise raise")
  t.eq(rules.actor(state), "P1", "the player who checked must answer")
  play(state, "call")
  t.eq(rules.actor(state), "P2", "the turn returns round the table")
  t.eq(rules.toCall(state), 10)
  play(state, "call")
  t.eq(state.phase, "draw")
end)

t.test("checks all round move on to the draw, and folding wins without one", function()
  local state = deal({ 200, 200, 200 })
  play(state, "check check check")
  t.eq(state.phase, "draw")
  local other = deal({ 200, 200, 200 })
  play(other, "raise fold fold")
  t.truthy(rules.done(other))
  t.truthy(other.uncontested)
  t.eq(rules.nets(other).P1, 10, "the winner takes the two antes")
  t.eq(rules.nets(other).P2, -5)
end)

t.test("nothing out of turn order or off the menu changes the hand", function()
  local state = deal({ 200, 200 })
  t.eq(#rules.act(state, "fold"), 0, "no fold when a check is free")
  t.eq(#rules.act(state, "call"), 0)
  t.eq(#rules.act(state, "draw"), 0)
  t.eq(#rules.act(state, "nonsense"), 0)
  t.eq(rules.actor(state), "P1")
end)

t.test("up to three cards are drawn, four with an ace kept", function()
  local hand = { deck.parse("AS"), deck.parse("2C"), deck.parse("3C"), deck.parse("4C"), deck.parse("9D") }
  t.truthy(rules.legalDiscard(hand, {}))
  t.truthy(rules.legalDiscard(hand, { 2, 3, 4 }))
  t.truthy(rules.legalDiscard(hand, { 2, 3, 4, 5 }), "keeps the ace")
  t.truthy(not rules.legalDiscard(hand, { 1, 3, 4, 5 }), "throws the ace")
  t.truthy(not rules.legalDiscard(hand, { 1, 2, 3, 4, 5 }))
  t.truthy(not rules.legalDiscard(hand, { 2, 2 }))
  t.truthy(not rules.legalDiscard(hand, { 6 }))
end)

t.test("a draw swaps the named cards and only those", function()
  local state = deal({ 200, 200 })
  play(state, "check check")
  local before = {}
  local mine = state.players[state.turn]
  for i, card in ipairs(mine.hand) do before[i] = card end
  t.eq(#rules.act(state, "draw123456"), 0, "too many")
  t.eq(#rules.act(state, "draw2244"), 0, "repeats")
  t.truthy(#rules.act(state, "draw24") > 0)
  t.eq(mine.drew, 2)
  t.eq(mine.hand[1], before[1])
  t.eq(mine.hand[3], before[3])
  t.eq(mine.hand[5], before[5])
  t.truthy(mine.hand[2] ~= before[2])
end)

t.test("six players drawing the most they can never run out", function()
  -- Four aces held by four players, who draw four, and two more who draw three: 22 cards, all that is left
  local cards = {}
  local aces = { "AS", "AH", "AD", "AC" }
  for i = 1, 6 do cards[i] = aces[i] or (i + 3 .. "C") end
  for i = 7, 30 do cards[i] = "2" .. ({ "C", "D", "H", "S" })[i % 4 + 1] end
  local state = deal({ 200, 200, 200, 200, 200, 200 }, 6, cards)
  play(state, "check check check check check check")
  t.eq(#state.deck >= 22, true, "cards left")
  local left = #state.deck
  play(state, "draw2345 draw2345 draw2345 draw2345 draw123 draw123")
  t.eq(left - #state.deck, 22)
end)

t.test("the showdown takes the best hand", function()
  -- Dealt round the table from P1: P1 gets pairs, P2 gets nothing
  local state = deal({ 200, 200 }, 2,
    { "KS", "2C", "KD", "4D", "7H", "6S", "8C", "9D", "3S", "JH" })
  play(state, "check check draw draw check check")
  t.truthy(rules.done(state))
  t.eq(rules.nets(state).P1, 5)
  t.eq(rules.nets(state).P2, -5)
  t.eq(state.players[1].handName, "Pair of Kings")
  t.eq(rules.result(state).title, "P1 WINS")
end)

t.test("a split pot hands the odd ante to the left of the button", function()
  -- P1 and P2 hold the same K-Q-9-7-5 in different suits, P3 loses: a pot of 15 splits 8 and 7
  local state = deal({ 200, 200, 200 }, 3,
    { "KS", "KD", "2C", "QS", "QC", "3C", "7H", "7D", "4C", "5H", "5D", "6C", "9S", "9D", "8H" })
  play(state, "check check check draw draw draw check check check")
  t.truthy(rules.done(state))
  t.eq(rules.nets(state).P1, 3, "first left of the button")
  t.eq(rules.nets(state).P2, 2)
  t.eq(rules.nets(state).P3, -5)
end)

t.test("a short call goes all-in and the rest of the bet comes back", function()
  local state = deal({ 200, 12 }, 2,
    { "KS", "2C", "KD", "4D", "7H", "6S", "8C", "9D", "3S", "JH" })
  play(state, "raise")
  t.eq(rules.actions(state)[2].label, "ALL-IN")
  t.eq(rules.actions(state)[2].sub, "7", "all they have left")
  t.eq(#rules.actions(state), 2, "no raise from a stack that cannot call")
  play(state, "call")
  local player = state.players[2]
  t.truthy(player.allin, "the short stack is all-in")
  t.eq(player.total, 12)
  play(state, "draw draw")
  t.truthy(rules.done(state))
  -- P1 put in 15 but only 12 was matched: the winner takes 12 from the short stack
  t.eq(rules.nets(state).P1, 12)
  t.eq(rules.nets(state).P2, -12)
end)

t.test("a short raise is offered as an all-in", function()
  local state = deal({ 200, 200, 27 }, 3)
  play(state, "raise raise")
  t.eq(rules.actor(state), "P3")
  local raise = rules.actions(state)[3]
  t.eq(raise.label, "ALL-IN")
  t.eq(raise.sub, "22", "what is left")
  play(state, "raise")
  t.eq(state.current, 22, "the bet to match is what they put in")
  t.eq(rules.actor(state), "P1")
  t.eq(rules.toCall(state), 12)
end)

t.test("all-ins of three sizes play out to the right side pots", function()
  -- Stacks 30, 60, 500, 500. Deal order P1..P4; P1 best, then P2, then P3
  local state = deal({ 30, 60, 500, 500 }, 4,
    { "AS", "KS", "QS", "2D", "AH", "KH", "QH", "3D", "AD", "KD", "QD", "5C", "AC", "KC", "7H", "6C", "9S", "8S", "9H", "9C" })
  play(state, "raise raise raise raise call call call")
  -- P1 is all-in for 30, everyone else is in for 45 with the round capped
  t.eq(state.players[1].total, 30)
  t.truthy(state.players[1].allin)
  t.eq(state.players[2].total, 45)
  t.eq(state.phase, "draw")
  play(state, "draw draw draw draw")
  t.eq(state.phase, "bet2")
  t.eq(rules.actor(state), "P2", "the all-in player is skipped")
  play(state, "raise raise fold") -- P2 all-in for 60, P3 raises to 80, P4 folds at 45
  t.truthy(rules.done(state))
  t.eq(#state.pots, 3, "pots")
  t.eq(state.pots[1].amount, 120)
  t.eq(state.pots[2].amount, 75)
  t.eq(state.pots[3].amount, 20)
  local nets = rules.nets(state)
  t.eq(nets.P1, 90, "quad aces win only the main pot")
  t.eq(nets.P2, 15, "quad kings win the side pot")
  t.eq(nets.P3, -60, "trips get their unmatched 20 back")
  t.eq(nets.P4, -45)
  local result = rules.result(state)
  t.eq(result.title, "SIDE POTS", "no single winner is claimed")
  t.eq(result.detail, "P1 120   P2 75", "each pot and who won it, and not the unmatched 20")
end)

t.test("a pot with an uncalled bet in it is reported at what was really contested", function()
  local state = deal({ 200, 12 }, 2,
    { "KS", "2C", "KD", "4D", "7H", "6S", "8C", "9D", "3S", "JH" })
  play(state, "raise call draw draw")
  t.eq(rules.result(state).detail, "Pair of Kings takes a pot of 24")
end)

t.test("all-in players still draw, and betting skips when nobody can answer", function()
  local state = deal({ 15, 15 }, 2)
  play(state, "raise call")
  t.eq(state.phase, "draw")
  t.truthy(state.players[1].allin and state.players[2].allin)
  play(state, "draw draw")
  t.truthy(rules.done(state), "no second round of betting")
end)

t.test("a stack smaller than the ante is all-in on the ante", function()
  local state = deal({ 3, 200, 200 }, 3)
  t.truthy(state.players[1].allin)
  t.eq(rules.potTotal(state), 13)
  t.eq(rules.actor(state), "P2")
end)

t.test("nobody home checks when free, folds when not, stands pat in the draw", function()
  local state = deal({ 200, 200 })
  t.eq(rules.auto(state), "check")
  play(state, "raise")
  t.eq(rules.auto(state), "fold")
  play(state, "call")
  t.eq(rules.auto(state), "draw")
end)

--- A hand's state must be plain data, so the journal can keep it.
local function plain(value, depth)
  depth = depth or 0
  t.truthy(depth < 8, "no cycles")
  local kind = type(value)
  t.truthy(kind == "table" or kind == "number" or kind == "string" or kind == "boolean", "plain value, got " .. kind)
  if kind == "table" then
    t.truthy(getmetatable(value) == nil, "no metatables")
    for key, inner in pairs(value) do
      t.truthy(type(key) == "number" or type(key) == "string")
      plain(inner, depth + 1)
    end
  end
end

t.test("thousands of random hands add up, end, and stay plain data", function()
  local rng = t.fastRng(77)
  local deals = 6000
  for round = 1, deals do
    local stacks = {}
    local players = rng:below(5) + 2
    for i = 1, players do stacks[i] = rng:below(3) == 0 and rng:below(30) + 1 or rng:below(300) + 1 end
    local entries = {}
    for i, stack in ipairs(stacks) do entries[i] = { name = "P" .. i, stack = stack, seat = i } end
    local state = rules.new(entries, rng:below(players) + 1, rng)
    local steps = 0
    while not rules.done(state) do
      steps = steps + 1
      t.truthy(steps < 200, "the hand ends")
      local id
      if state.phase == "draw" then
        id = "draw"
        for position = 1, rng:below(4) do id = id .. position end
      else
        local list = rules.actions(state)
        id = list[rng:below(#list) + 1].id
      end
      local events = rules.act(state, id)
      t.truthy(#events > 0, id .. " does something")
      for _, player in ipairs(state.players) do
        t.eq(player.stack + (rules.done(state) and -player.net or player.total), player.start, "chips stay with their player")
        t.truthy(player.stack >= 0, "no negative stacks")
      end
    end
    local sum = 0
    for _, player in ipairs(state.players) do
      sum = sum + player.net
      t.truthy(player.net >= -player.start, "nobody loses more than they sat with")
      t.eq(player.stack, player.start + player.net, "final stack")
    end
    t.eq(sum, 0, "conservation")
    if round % 1000 == 0 then plain(state) end
    if round % 200 == 0 then t.breathe() end
  end
end)

-- ------------------------------------------------------------------ settlement

--- A fake bank: the host starts at zero. fails[name] stops a player's tokens moving; have[name] caps what they can pay.
local function bank(fails, have)
  local host, moves = 0, {}
  local function move(name, amount)
    moves[#moves + 1] = name .. " " .. amount
    if fails[name] then return 0 end
    if amount < 0 then
      local take = math.min(-amount, have[name] or -amount)
      host = host + take
      return -take
    end
    t.truthy(amount <= host, "paid " .. amount .. " with only " .. host .. " collected")
    host = host - amount
    return amount
  end
  return move, function() return host end, moves
end

t.test("losers are collected before any winner is paid", function()
  local owed = { Ann = 100, Bob = -60, Cat = -40 }
  local move, host, moves = bank({}, {})
  rules.settle(owed, { "Ann", "Bob", "Cat" }, move)
  t.eq(moves[1], "Bob -60")
  t.eq(moves[2], "Cat -40")
  t.eq(moves[3], "Ann 100")
  t.eq(next(owed), nil, "nothing left owed")
  t.eq(host(), 0, "the host ends even")
end)

t.test("a loser's failed charge costs the winner only that share, for now", function()
  local owed = { Ann = 100, Bob = -60, Cat = -40 }
  local move, host = bank({ Bob = true }, {})
  rules.settle(owed, { "Ann", "Bob", "Cat" }, move)
  t.eq(owed.Ann, 60, "the rest waits")
  t.eq(owed.Bob, -60)
  t.eq(host(), 0, "the host paid out only what came in")
  -- Bob returns: his tokens go on to Ann without the host's money moving
  local again, hostAgain = bank({}, {})
  rules.settle(owed, { "Bob" }, again)
  t.eq(owed.Bob, nil)
  t.eq(rules.holding(owed), 60, "held for Ann")
  rules.settle(owed, { "Ann" }, function(name, amount)
    t.eq(name, "Ann")
    return amount
  end)
  t.eq(next(owed), nil)
  t.eq(hostAgain(), 60, "Bob's tokens are what paid Ann")
end)

t.test("a winner who cannot be paid leaves the tokens held for them", function()
  local owed = { Ann = 50, Bob = -50 }
  local move, host = bank({ Ann = true }, {})
  rules.settle(owed, { "Ann", "Bob" }, move)
  t.eq(owed.Ann, 50)
  t.eq(host(), 50)
  t.eq(rules.holding(owed), 50)
end)

t.test("a loser short of tokens pays what they have and the rest stays owed", function()
  local owed = { Ann = 100, Bob = -100 }
  local move = bank({}, { Bob = 30 })
  rules.settle(owed, { "Ann", "Bob" }, move)
  t.eq(owed.Bob, -70)
  t.eq(owed.Ann, 70)
end)

t.test("collected tokens pay the biggest winner first", function()
  local owed = { Ann = 20, Bob = -50, Cat = 30 }
  local move, _, moves = bank({}, { Bob = 40 })
  rules.settle(owed, { "Ann", "Bob", "Cat" }, move)
  t.eq(moves[2], "Cat 30")
  t.eq(moves[3], "Ann 10")
  t.eq(owed.Ann, 10)
end)

t.test("the host never goes below even, whatever fails", function()
  local rng = t.fastRng(31)
  local names = { "Ann", "Bob", "Cat", "Dan" }
  for _ = 1, 4000 do
    local owed, sum = {}, 0
    for i = 1, 3 do
      local amount = rng:below(200) - 100
      owed[names[i]] = amount ~= 0 and amount or nil
      sum = sum + amount
    end
    owed.Dan = sum ~= 0 and -sum or nil
    local host = 0
    for _ = 1, 4 do
      local present = {}
      for _, name in ipairs(names) do
        if rng:below(2) == 0 then present[#present + 1] = name end
      end
      rules.settle(owed, present, function(_, amount)
        if rng:below(3) == 0 then return 0 end
        if amount < 0 and rng:below(2) == 0 then amount = math.ceil(amount / 2) end
        host = host - amount
        t.truthy(host >= 0, "host below even: " .. host)
        return amount
      end)
      t.eq(rules.holding(owed), host, "everything owed is what the host holds")
    end
  end
end)
