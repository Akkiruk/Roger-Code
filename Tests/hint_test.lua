-- hint_test.lua
-- What the HINT button advises. tools/casinotest/hint-oracle.mjs checks it against exact values on every deal and every cell;
-- the chart and the deals here keep that result in the suite that stops a deploy. hint.mjs covers the button on a real table.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")
local blackjack = require("blackjack_rules")
local videopoker = require("videopoker_rules")
local golden = require("hint_golden")
local t = require("testing")

-- ------------------------------------------------------------------ blackjack

local UPS = { "2C", "3C", "4C", "5C", "6C", "7C", "8C", "9C", "10C", "AC" } -- the chart's columns
local NAMES = { H = "hit", S = "stand", D = "double", P = "split" }

--- A round dealt these two cards against this up card, from a real shoe, with no dealer natural in the hole.
local function dealt(first, second, up, hole, draws)
  local names = { first, up, second, hole or (up == "AC" and "9S" or "5S") }
  for _, name in ipairs(draws or {}) do names[#names + 1] = name end
  local keep = { shoe = deck.stack(deck.fresh(blackjack.DECKS), names) }
  local state = blackjack.new(100, t.fastRng(9), keep, {})
  return state
end

local function advised(state, offered)
  local advice = blackjack.hint(state, offered)
  t.eq(#advice.ids, 1, "one action")
  return advice.ids[1]
end

local function offers(state, id)
  for _, action in ipairs(blackjack.actions(state)) do
    if action.id == id then return true end
  end
  return false
end

--- Check one row of the chart: hand against every up card in turn.
local function row(what, first, second, chart)
  for i, up in ipairs(UPS) do
    local state = dealt(first, second, up)
    t.truthy(not state.hold, what .. " is a decision")
    local id = advised(state)
    t.eq(id, NAMES[chart:sub(i, i)], what .. " against " .. up)
    t.truthy(offers(state, id), what .. " advises something the table offers")
  end
end

t.test("hard totals follow the chart", function()
  row("hard 5", "2H", "3D", "HHHHHHHHHH")
  row("hard 8", "2H", "6D", "HHHHHHHHHH")
  row("hard 9", "2H", "7D", "HHHHHHHHHH")
  row("hard 10", "3H", "7D", "HHHHHHHHHH") -- no double on 10 here, whatever a printed chart says
  row("hard 11", "5H", "6D", "DDDDDDDDDD")
  row("hard 12", "10H", "2D", "HHSSSHHHHH")
  row("hard 13", "10H", "3D", "SSSSSHHHHH")
  row("hard 14", "10H", "4D", "SSSSSHHHHH")
  row("hard 15", "10H", "5D", "SSSSSHHHHH")
  row("hard 16", "10H", "6D", "SSSSSHHHHH")
  row("hard 17", "10H", "7D", "SSSSSSSSSS")
  row("hard 20", "10H", "QD", "SSSSSSSSSS")
end)

t.test("soft totals follow the chart, with no soft doubles at this table", function()
  row("soft 13", "AH", "2D", "HHHHHHHHHH")
  row("soft 16", "AH", "5D", "HHHHHHHHHH")
  row("soft 17", "AH", "6D", "HHHHHHHHHH")
  row("soft 18", "AH", "7D", "SSSSSSSHHH")
  row("soft 19", "AH", "8D", "SSSSSSSSSS")
  row("soft 20", "AH", "9D", "SSSSSSSSSS")
end)

t.test("pairs follow the chart", function()
  row("aces", "AH", "AD", "PPPPPPPPPP")
  row("tens", "KH", "KD", "SSSSSSSSSS")
  row("nines", "9H", "9D", "PPPPPSPPSS")
  row("eights", "8H", "8D", "PPPPPPPPPP")
  row("sevens", "7H", "7D", "PPPPPPHHHH")
  row("sixes", "6H", "6D", "HPPPPHHHHH")
  row("fives", "5H", "5D", "HHHHHHHHHH")
  row("fours", "4H", "4D", "HHHHHHHHHH")
  row("threes", "3H", "3D", "HHPPPPHHHH")
  row("twos", "2H", "2D", "HHPPPPHHHH")
end)

t.test("a double or a split the balance cannot cover falls to the next best play", function()
  local plain = { hit = true, stand = true }
  t.eq(advised(dealt("6H", "5D", "6C"), plain), "hit", "11 with no double hits")
  t.eq(advised(dealt("8H", "8D", "6C"), plain), "stand", "16 against a 6 stands")
  t.eq(advised(dealt("8H", "8D", "10C"), plain), "hit", "16 against a 10 hits")
  t.eq(advised(dealt("AH", "AD", "6C"), plain), "hit", "soft 12 hits")
  t.eq(advised(dealt("9H", "9D", "6C"), plain), "stand", "18 stands")
  t.eq(advised(dealt("2H", "2D", "6C"), plain), "hit", "hard 4 hits")
end)

t.test("once split, every hand plays on its total with no double and no second split", function()
  local state = dealt("8H", "8D", "6C", nil, { "3C", "8S" }) -- the first hand makes 11, the second another pair of eights
  blackjack.act(state, "split", t.fastRng(1))
  t.eq(blackjack.total(state.hands[1].cards), 11)
  t.eq(advised(state), "hit", "no double after a split")
  blackjack.act(state, "stand", t.fastRng(1))
  t.eq(state.active, 2)
  t.eq(advised(state), "stand", "16 against a 6, not a split")
end)

t.test("the advice never looks past the up card", function()
  for _, up in ipairs(UPS) do
    for _, hand in ipairs({ { "10H", "6D" }, { "10H", "2D" }, { "AH", "7D" }, { "8H", "8D" } }) do
      local seen = nil
      for _, hole in ipairs({ "2S", "5S", "9S" }) do
        local state = dealt(hand[1], hand[2], up, hole)
        local id = advised(state)
        t.truthy(seen == nil or seen == id, "the hole card changed the advice")
        seen = id
      end
    end
  end
end)

t.test("blackjack advice changes nothing in the round", function()
  local state = dealt("8H", "8D", "10C", nil, { "3C", "9D" })
  local before = textutils and textutils.serialize(state, { compact = true }) or nil
  local shoe, active = #state.cards, state.active
  blackjack.hint(state)
  t.eq(#state.cards, shoe, "no card moved")
  t.eq(state.active, active)
  if before then t.eq(textutils.serialize(state, { compact = true }), before) end
end)

t.test("played round after round, the hint is the strategy the return test proves", function()
  local plays = {}
  local value = t.simulate(blackjack, 20000, 100, function(state)
    local id = blackjack.hint(state).ids[1]
    t.eq(id, blackjack.basic(state))
    plays[id] = true
    return id
  end, 77)
  print(("     blackjack by the hint %.3f%%, 20,000 rounds"):format(value * 100))
  t.truthy(value > 0.95 and value < 1.02, "return " .. value)
  for _, id in ipairs({ "hit", "stand", "double", "split" }) do t.truthy(plays[id], "it used " .. id) end
end)

-- ------------------------------------------------------------------ video poker

local function words(text)
  local list = {}
  for word in text:gmatch("%S+") do list[#list + 1] = word end
  return list
end

local function vpState(names)
  local hand, held = {}, {}
  for i, name in ipairs(names) do hand[i], held[i] = deck.parse(name), false end
  return { hand = hand, held = held, bet = 100 }
end

--- The cards rules.hint would keep, as a sorted line.
local function keptBy(state)
  local kept = {}
  for _, id in ipairs(videopoker.hint(state).ids) do
    local slot = tonumber(id:match("^hold(%d)$"))
    if slot then kept[#kept + 1] = deck.name(state.hand[slot]) end
  end
  table.sort(kept)
  return table.concat(kept, " ")
end

local function sortedLine(text)
  local list = words(text)
  table.sort(list)
  return table.concat(list, " ")
end

t.test("every kind of best hold, on its closest clear call", function()
  t.truthy(#golden >= 200, "the deals are there")
  for i, deal in ipairs(golden) do
    t.eq(keptBy(vpState(words(deal[1]))), sortedLine(deal[2]), deal[1])
    if i % 50 == 0 then t.breathe() end
  end
end)

t.test("the order the cards were dealt in makes no difference", function()
  for i = 1, #golden, 3 do
    local names = words(golden[i][1])
    local turned = { names[3], names[5], names[1], names[4], names[2] }
    t.eq(keptBy(vpState(turned)), sortedLine(golden[i][2]), golden[i][1])
  end
end)

t.test("made hands stand, and this paytable's royal is not the 800 of a printed chart", function()
  t.eq(keptBy(vpState({ "10S", "JS", "QS", "KS", "AS" })), sortedLine("10S JS QS KS AS"), "a royal")
  t.eq(keptBy(vpState({ "9C", "9D", "9H", "9S", "2C" })), sortedLine("9C 9D 9H 9S"), "four of a kind, no kicker")
  t.eq(keptBy(vpState({ "9C", "9D", "9H", "2S", "2C" })), sortedLine("9C 9D 9H 2S 2C"), "a full house")
  t.eq(keptBy(vpState({ "JC", "JD", "2H", "7S", "9C" })), sortedLine("JC JD"), "a pair of Jacks")
  t.eq(#videopoker.hint(vpState({ "2C", "3D", "4C", "7D", "9C" })).ids, 1)
  t.eq(videopoker.hint(vpState({ "2C", "3D", "4C", "7D", "9C" })).ids[1], "draw", "nothing worth keeping")
end)

--- Exact, by trying every draw. The hold is a list of cards.
local function exactValue(hand, kept, pays)
  local out = {}
  for card = 0, 51 do
    local mine = false
    for _, held in ipairs(hand) do mine = mine or held == card end
    if not mine then out[#out + 1] = card end
  end
  local cards = {}
  for i, card in ipairs(kept) do cards[i] = card end
  local total, ways = 0, 0
  local function choose(from, depth)
    if depth > 5 then
      local tier = poker.jacksOrBetter(cards)
      ways = ways + 1
      if tier then total = total + pays[tier] end
      return
    end
    for i = from, #out do
      cards[depth] = out[i]
      choose(i + 1, depth + 1)
    end
  end
  choose(1, #kept + 1)
  return total / ways
end

t.test("on random deals no hold of four beats the advice, by trying every draw", function()
  local rng = t.fastRng(31)
  local pays = {}
  for _, line in ipairs(videopoker.PAYS) do pays[line.id] = line.multiple end
  local compared = 0
  for _ = 1, 400 do
    local state = videopoker.new(1, rng, {}, {})
    local kept = {}
    for _, id in ipairs(videopoker.hint(state).ids) do
      local slot = tonumber(id:match("^hold(%d)$"))
      if slot then kept[#kept + 1] = state.hand[slot] end
    end
    if #kept >= 3 then
      compared = compared + 1
      local value = exactValue(state.hand, kept, pays)
      -- Every hold of four: 47 draws each
      for drop = 1, 5 do
        local other = {}
        for i = 1, 5 do
          if i ~= drop then other[#other + 1] = state.hand[i] end
        end
        t.truthy(exactValue(state.hand, other, pays) <= value + 0.001, "a hold of four beat the advice on " .. deck.name(state.hand[1]))
      end
      t.breathe()
    end
  end
  t.truthy(compared > 40, "enough deals were strong enough to compare: " .. compared)
end)

t.test("video poker advice reads only the five cards and changes nothing", function()
  local rng = t.fastRng(8)
  local state = videopoker.new(100, rng, {}, {})
  local before = keptBy(state)
  local left = #state.cards
  state.cards = {} -- the next cards cannot matter, because there are none
  t.eq(keptBy(state), before)
  state.held[1] = true
  t.eq(keptBy(state), before, "what is held already makes no difference to the best hold")
  t.eq(left, 47)
  t.eq(state.over, false)
  t.eq(state.tier, false)
end)

t.test("the advice holds through the real rules and comes close to the exact return", function()
  local value = t.simulate(videopoker, 20000, 1000, function(state)
    local advice = videopoker.hint(state)
    if advice.ids[1] == "draw" then return "draw" end
    local want = {}
    for _, id in ipairs(advice.ids) do want[tonumber(id:match("(%d)$"))] = true end
    for i = 1, videopoker.HAND_SIZE do
      if (want[i] or false) ~= state.held[i] then return "hold" .. i end
    end
    return "draw"
  end, 91)
  print(("     video poker by the hint %.3f%%, 20,000 rounds"):format(value * 100))
  t.truthy(value > 0.93 and value < 1.04, "return " .. value)
end)

t.test("a hint is quick enough to run between two frames, and never needs to yield", function()
  local rng = t.fastRng(12)
  local count = 2000
  local deals = {}
  for i = 1, count do deals[i] = videopoker.new(1, rng, {}, {}) end
  local start = os.clock()
  for i = 1, count do videopoker.hint(deals[i]) end
  local each = (os.clock() - start) / count
  print(("     video poker hint %.3f ms each"):format(each * 1000))
  t.truthy(each < 0.02, "one hint took " .. each .. " seconds")
end)
