-- threecard_test.lua
-- Exact returns over every deal are proved by tools/casinotest/threecard-oracle.mjs. Here the rules play real rounds.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")
local rules = require("threecard_rules")
local t = require("testing")

--- A round with these hands, by name.
local function rigged(mine, theirs, ante, side)
  local rng = t.fastRng(3)
  local state = rules.new({ ante = ante or 100, side = side or 0 }, rng, {}, {})
  local names = {}
  for name in (mine .. " " .. theirs):gmatch("%S+") do names[#names + 1] = name end
  for i = 1, 3 do
    state.player[i] = deck.parse(names[i])
    state.dealer[i] = deck.parse(names[i + 3])
  end
  return state, rng
end

local function netOf(mine, theirs, action, side)
  local state, rng = rigged(mine, theirs, 100, side)
  rules.act(state, action or "play", rng)
  t.truthy(rules.done(state), "the hand is over")
  return rules.net(state), state
end

t.test("a dealer without Queen high pays the Ante and pushes Play", function()
  t.eq(netOf("2C 3D 7H", "JC 9D 4H"), 100)
  local state = select(2, netOf("2C 3D 7H", "JC 9D 4H"))
  t.eq(state.outcome.play, 0)
  t.eq(rules.result(state).title, "DEALER PASSES")
end)

t.test("Queen high qualifies", function()
  t.eq(netOf("AC 3D 7H", "QC 9D 4H"), 200, "ante and play both pay")
end)

t.test("a better hand wins Ante and Play 1 to 1", function()
  t.eq(netOf("KC KD 7H", "QC QD 4H"), 200)
end)

t.test("a worse hand loses both", function()
  t.eq(netOf("JC 9D 7H", "QC 9S 4H"), -200)
end)

t.test("an exact tie pushes", function()
  t.eq(netOf("QC 9D 4H", "QD 9S 4C"), 0)
  t.eq(rules.result(select(2, netOf("QC 9D 4H", "QD 9S 4C"))).kind, "push")
end)

t.test("a fold loses the Ante and nothing else", function()
  t.eq(netOf("2C 3D 7H", "QC 9D 4H", "fold"), -100)
end)

t.test("the Ante Bonus pays whatever the dealer holds", function()
  t.eq(netOf("2C 3D 4H", "3S 4C 5D"), -100, "a straight loses to a straight but still gets 1")
  t.eq(netOf("9C 9D 9H", "2S 5C 7D"), 100 + 400, "trips against a dealer who does not qualify")
  t.eq(netOf("5C 6C 7C", "2S 2C 7D"), 200 + 500, "a straight flush beats a pair")
  t.eq(netOf("5C 6C 7C", "8S 9S 10S"), -200 + 500, "a straight flush beaten by a better one")
end)

t.test("no Ante Bonus on a flush, a pair or a fold", function()
  t.eq(netOf("2C 6C 9C", "2S 2D 7D"), 200, "flush")
  t.eq(netOf("AC AD 9C", "2S 2D 7D"), 200, "pair")
  t.eq(netOf("5C 6D 7H", "2S 2D 7D", "fold"), -100, "the straight went in the muck")
end)

t.test("Pair Plus pays on the hand alone", function()
  local mine = {
    { "2C 2D 9H", 100 }, { "2C 6C 9C", 300 }, { "5C 6D 7H", 600 }, { "9C 9D 9H", 3000 }, { "5C 6C 7C", 4000 },
  }
  for _, case in ipairs(mine) do
    local net, state = netOf(case[1], "3S 4S 8D", "fold", 100)
    t.eq(state.outcome.side, case[2], case[1])
    t.eq(net, case[2] - 100, "folded: the Ante goes but the side bet stands")
  end
end)

t.test("Pair Plus loses on less than a pair", function()
  local net, state = netOf("AC KD 9H", "3S 4S 8D", "play", 100)
  t.eq(state.outcome.side, -100)
  t.eq(net, 100 - 100)
end)

t.test("Play is marked with its cost, and risk counts the stake", function()
  local state = rigged("AC KD 9H", "3S 4S 8D", 100, 50)
  local costed = false
  for _, action in ipairs(rules.actions(state)) do
    if action.id == "play" then costed = action.cost == 100 end
  end
  t.truthy(costed, "play costs the Ante")
  t.eq(rules.risk(state), 150)
end)

t.test("maxWin covers the best hand there is", function()
  t.eq(rules.maxWin({ ante = 100, side = 100 }), 200 + 500 + 4000)
  local net = netOf("QC KC AC", "2S 2D 7D", "play", 100)
  t.eq(net, rules.maxWin({ ante = 100, side = 100 }))
  t.eq(rules.maxWin(1), 47, "a plain number is one token with the side bet on")
end)

t.test("nobody home plays Queen-6-4 or better and folds the rest", function()
  t.eq(rules.auto(rigged("QC 6D 4H", "3S 4S 8D")), "play", "the line itself")
  t.eq(rules.auto(rigged("QC 6D 3H", "3S 4S 8D")), "fold", "just under")
  t.eq(rules.auto(rigged("QC 5D 4H", "3S 4S 8D")), "fold", "just under")
  t.eq(rules.auto(rigged("JC 10D 8H", "3S 4S 8D")), "fold", "Jack high")
  t.eq(rules.auto(rigged("2C 2D 3H", "3S 4S 8D")), "play", "any pair")
end)

t.test("the deal uses six different cards", function()
  local rng = t.fastRng(4)
  local state = rules.new({ ante = 10, side = 0 }, rng, {}, {})
  local seen = {}
  for _, hand in ipairs({ state.player, state.dealer, state.cards }) do
    for _, card in ipairs(hand) do
      t.truthy(not seen[card], "unique")
      seen[card] = true
    end
  end
end)

t.test("the Pair Plus return, exactly, over every hand", function()
  local total, hands = 0, 0
  local hand = {}
  for a = 0, 49 do
    hand[1] = a
    for b = a + 1, 50 do
      hand[2] = b
      for c = b + 1, 51 do
        hand[3] = c
        local _, category = poker.three(hand)
        total = total + rules.pays(rules.PAIR_PLUS, category) + (rules.pays(rules.PAIR_PLUS, category) > 0 and 1 or 0)
        hands = hands + 1
      end
    end
  end
  t.near(total / hands, rules.SIDE_RETURN, 0.00006, "Pair Plus")
end)

t.test("the Ante return by simulation matches the exact figure", function()
  local value = t.simulate(rules, 200000, { ante = 10, side = 0 }, rules.auto, 11, function(w) return w.ante end)
  print(("     Ante return %.3f%%, exact %.3f%%"):format(value * 100, rules.ANTE_RETURN * 100))
  t.near(value, rules.ANTE_RETURN, 0.012, "Ante")
end)
