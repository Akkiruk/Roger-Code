-- blackjack_test.lua
-- Scripted rounds against a stacked shoe, then a basic-strategy simulation of the whole game.

local deck = require("lib.casino.deck")
local rules = require("blackjack_rules")
local game = require("blackjack_game")
local t = require("testing")

--- A round dealt from these cards, in deal order: player, dealer up, player, dealer hole, then the draws.
local function rigged(names, bet)
  local rng = t.fastRng(9)
  local keep = { shoe = deck.stack(deck.fresh(rules.DECKS), names) }
  local state, events = rules.new(bet or 100, rng, keep, {})
  return state, rng, events
end

local function has(state, id)
  for _, action in ipairs(rules.actions(state)) do
    if action.id == id then return action end
  end
  return nil
end

local function play(state, rng, ...)
  for _, id in ipairs({ ... }) do rules.act(state, id, rng) end
end

local function eventsOf(events, kind)
  local found = {}
  for _, ev in ipairs(events) do
    if ev.type == kind then found[#found + 1] = ev end
  end
  return found
end

t.test("a natural pays 3:2 and the dealer draws nothing", function()
  local state, rng = rigged({ "AH", "6C", "KD", "9S", "2C" })
  t.truthy(not rules.done(state), "stops at the reveal, so the engine settles it")
  t.eq(#rules.actions(state), 1, "only the reveal")
  t.eq(rules.auto(state), "stand")
  play(state, rng, "stand")
  t.truthy(rules.done(state))
  t.eq(rules.net(state), 150)
  t.eq(#state.dealer, 2, "no draw against a natural")
  t.eq(rules.result(state).title, "BLACKJACK")
end)

t.test("a natural against a dealer natural pushes", function()
  local state, rng = rigged({ "AH", "AC", "KD", "QS" })
  play(state, rng, "stand")
  t.eq(rules.net(state), 0)
  t.eq(rules.result(state).kind, "push")
end)

t.test("a dealer natural ends the round on the peek, for the bet only", function()
  local state, rng = rigged({ "9H", "AC", "9D", "KS" })
  t.eq(#rules.actions(state), 1, "no hit, no double, no split")
  play(state, rng, "stand")
  t.truthy(rules.done(state))
  t.eq(rules.net(state), -100)
  t.eq(rules.result(state).title, "DEALER BLACKJACK")
end)

t.test("the dealer only peeks under an ace or a ten", function()
  local state = rigged({ "9H", "9C", "7D", "AS" })
  t.truthy(has(state, "hit"), "an A under a 9 is not seen")
  state = rigged({ "9H", "KC", "7D", "5S" })
  t.truthy(has(state, "hit"), "a peek that finds nothing carries on")
end)

t.test("stand, hit and bust", function()
  local state, rng = rigged({ "10H", "7C", "9D", "10S" })
  play(state, rng, "stand")
  t.eq(rules.net(state), 100, "19 beats 17")
  state, rng = rigged({ "10H", "10C", "6D", "8S", "3D" })
  play(state, rng, "hit")
  t.truthy(has(state, "stand"), "19 still plays")
  play(state, rng, "stand")
  t.eq(rules.net(state), 100, "19 beats 18")
  state, rng = rigged({ "10H", "10C", "6D", "8S", "KD", "9C" })
  play(state, rng, "hit")
  t.truthy(rules.done(state), "a bust ends the round")
  t.eq(rules.net(state), -100)
  t.eq(#state.dealer, 2, "the dealer draws nothing against a bust")
  t.eq(rules.result(state).title, "BUST")
end)

t.test("the dealer hits soft 17 and stands on hard 17", function()
  local state, rng = rigged({ "10H", "AC", "8D", "6S", "4C", "10D" })
  t.truthy(not state.hold, "A,6 is no natural")
  play(state, rng, "stand")
  t.eq(#state.dealer, 3, "soft 17 drew")
  t.eq(rules.total(state.dealer), 21, "A,6,4")
  t.eq(rules.net(state), -100)

  state, rng = rigged({ "10H", "10C", "8D", "7S", "4C" })
  play(state, rng, "stand")
  t.eq(#state.dealer, 2, "hard 17 stood")
  t.eq(rules.net(state), 100)

  state, rng = rigged({ "10H", "6C", "8D", "AS", "2C", "4D" })
  play(state, rng, "stand")
  t.eq(#state.dealer, 3, "6,A is soft 17: it drew")
  t.eq(rules.total(state.dealer), 19, "soft 19 stands")
end)

t.test("pushes", function()
  local state, rng = rigged({ "10H", "10C", "9D", "9S" })
  play(state, rng, "stand")
  t.eq(rules.net(state), 0)
  t.eq(rules.result(state).kind, "push")
end)

t.test("double on hard 11 only", function()
  t.truthy(has(rigged({ "6H", "5C", "5D", "10S" }), "double"), "6,5")
  t.truthy(not has(rigged({ "6H", "5C", "4D", "10S" }), "double"), "hard 10")
  t.truthy(not has(rigged({ "5H", "5C", "4D", "10S" }), "double"), "hard 9")
  t.truthy(not has(rigged({ "AH", "5C", "7D", "10S" }), "double"), "soft 18")
  t.truthy(not has(rigged({ "AH", "5C", "AD", "10S" }), "double"), "soft 12")
  local state, rng = rigged({ "2H", "5C", "4D", "10S", "5H" })
  t.truthy(not has(state, "double"))
  play(state, rng, "hit")
  t.eq(rules.total(state.hands[1].cards), 11)
  t.truthy(not has(state, "double"), "only on the first two cards")
end)

t.test("a double takes one card and stakes twice the bet", function()
  local state, rng = rigged({ "6H", "10C", "5D", "7S", "9C" })
  local action = has(state, "double")
  t.eq(action.cost, 100, "the extra stake")
  play(state, rng, "double")
  t.truthy(rules.done(state), "one card and the hand stands")
  t.eq(#state.hands[1].cards, 3)
  t.eq(rules.risk(state), 200)
  t.eq(rules.net(state), 200)

  state, rng = rigged({ "6H", "10C", "5D", "9S", "2C" })
  play(state, rng, "double")
  t.eq(rules.net(state), -200, "a lost double loses both")
  t.eq(rules.result(state).kind, "lose")
end)

t.test("split 8s plays two hands for two bets", function()
  local state, rng = rigged({ "8H", "10C", "8D", "7S", "3C", "10D", "10H", "9C" })
  t.eq(has(state, "split").cost, 100, "the extra stake")
  play(state, rng, "split")
  t.eq(#state.hands, 2)
  t.eq(rules.risk(state), 200)
  t.eq(rules.total(state.hands[1].cards), 11, "8 and 3")
  t.eq(rules.total(state.hands[2].cards), 18, "8 and 10")
  t.truthy(not has(state, "double"), "no double after a split")
  play(state, rng, "hit")
  t.eq(rules.total(state.hands[1].cards), 21, "11 and 10")
  t.eq(state.active, 2, "21 stood by itself and play moved on")
  t.truthy(not rules.done(state))
  play(state, rng, "stand")
  t.truthy(rules.done(state))
  t.eq(rules.total(state.dealer), 17)
  t.eq(rules.net(state), 200, "both beat 17")
  t.eq(rules.result(state).title, "SPLIT WON")
end)

t.test("one hand of a split can bust and the other still plays", function()
  local state, rng = rigged({ "8H", "10C", "8D", "7S", "7C", "10D", "9H" })
  play(state, rng, "split", "hit")
  t.eq(state.active, 2, "moved on after the bust")
  play(state, rng, "stand")
  t.eq(state.hands[1].result, "bust")
  t.eq(state.hands[2].result, "win")
  t.eq(rules.net(state), 0)
  t.eq(rules.result(state).title, "SPLIT EVEN")
end)

t.test("both split hands bust and the dealer draws nothing", function()
  local state, rng = rigged({ "8H", "6C", "8D", "10S", "7C", "7D", "9H", "9S", "KD" })
  play(state, rng, "split", "hit", "hit")
  t.truthy(rules.done(state))
  t.eq(#state.dealer, 2)
  t.eq(rules.net(state), -200)
end)

t.test("split aces get one card each and a 21 there is no natural", function()
  local state, rng = rigged({ "AH", "6C", "AD", "10S", "KC", "5D", "3C" })
  play(state, rng, "split")
  t.truthy(rules.done(state), "no choices after split aces")
  t.eq(#state.hands[1].cards, 2)
  t.eq(#state.hands[2].cards, 2)
  t.eq(rules.total(state.dealer), 19)
  t.eq(state.hands[1].result, "win")
  t.eq(state.hands[1].net, 100, "21 on a split pays 1:1, not 3:2")
  t.eq(state.hands[2].result, "lose", "16 against 19")
  t.eq(rules.net(state), 0)
end)

t.test("a split 21 stands by itself", function()
  local state, rng = rigged({ "KH", "6C", "KD", "10S", "AC", "2D", "9C" })
  t.truthy(has(state, "split"), "same rank")
  play(state, rng, "split")
  t.eq(state.active, 2, "K,A stood")
  t.eq(state.hands[1].result, nil)
  t.truthy(not has(state, "split"), "and no re-split")
  play(state, rng, "stand")
  t.eq(state.hands[1].result, "win", "dealer busts on 25")
  t.eq(state.hands[1].net, 100)
end)

t.test("different tens do not split, and there is no re-split", function()
  t.truthy(not has(rigged({ "KH", "7C", "QD", "10S" }), "split"), "K,Q are different ranks")
  local state, rng = rigged({ "8H", "7C", "8D", "10S", "8C", "2D" })
  play(state, rng, "split")
  t.eq(rules.total(state.hands[1].cards), 16, "8 and 8 again")
  t.truthy(not has(state, "split"), "one split")
  t.truthy(not has(state, "double"))
  local before = #state.hands
  play(state, rng, "split")
  t.eq(#state.hands, before, "a stale split does nothing")
end)

t.test("hitting to 21 stands by itself", function()
  local state, rng = rigged({ "10H", "10C", "5D", "7S", "6C" })
  play(state, rng, "hit")
  t.truthy(rules.done(state))
  t.eq(rules.net(state), 100)
end)

t.test("21 against a dealer 21 pushes", function()
  local state, rng = rigged({ "10H", "7C", "5D", "7S", "6C", "7D" })
  play(state, rng, "hit")
  t.eq(rules.total(state.dealer), 21, "7,7,7")
  t.eq(rules.net(state), 0)
end)

t.test("a natural beats a dealer who could reach 21", function()
  local state, rng = rigged({ "AH", "10C", "KD", "6S", "5C" })
  play(state, rng, "stand")
  t.eq(rules.net(state), 150)
end)

t.test("a dealer bust pays every hand still standing", function()
  local state, rng = rigged({ "10H", "6C", "3D", "10S", "10D" })
  play(state, rng, "stand")
  t.eq(rules.total(state.dealer), 26)
  t.eq(rules.net(state), 100)
  t.eq(rules.result(state).title, "DEALER BUST")
end)

t.test("payouts are whole tokens, floored", function()
  for bet, expected in pairs({ [1] = 1, [3] = 4, [5] = 7, [15] = 22, [100] = 150, [101] = 151 }) do
    local state, rng = rigged({ "AH", "6C", "KD", "9S" }, bet)
    play(state, rng, "stand")
    t.eq(rules.net(state), expected, "a natural on " .. bet)
    t.eq(rules.net(state) % 1, 0)
  end
end)

t.test("the worst case stays inside maxWin and risk tracks the stake", function()
  t.eq(rules.maxWin(100), 200)
  local state = rigged({ "10H", "7C", "9D", "10S" })
  t.eq(rules.risk(state), 100)
  t.eq(game.capTokens, 100)
end)

t.test("the hole card is hidden until the player is finished", function()
  local state, rng, events = rigged({ "10H", "7C", "5D", "KS", "2C", "2D", "2H", "2S" })
  local hole = state.dealer[2]
  for _, ev in ipairs(events) do
    if ev.hole then t.eq(ev.card, nil, "the hole card's deal carries no card") end
  end
  t.eq(#eventsOf(events, "reveal"), 0)
  local more = rules.act(state, "hit", rng)
  t.eq(#eventsOf(more, "reveal"), 0, "not on a hit")
  more = rules.act(state, "stand", rng)
  local reveal = eventsOf(more, "reveal")
  t.eq(#reveal, 1)
  t.eq(reveal[1].card, hole)
end)

t.test("the whole dealer draw comes out as events, in order, with the round already over", function()
  local state, rng = rigged({ "10H", "2C", "9D", "3S", "4C", "5D", "6H" })
  local events = rules.act(state, "stand", rng)
  t.truthy(rules.done(state))
  t.eq(events[1].type, "reveal")
  local deals = eventsOf(events, "deal")
  t.eq(#deals + 2, #state.dealer, "every drawn card has its event")
  t.eq(events[#events].type, "outcome")
end)

t.test("a mid-round state survives serialization", function()
  local state, rng = rigged({ "8H", "10C", "8D", "7S", "3C", "10D", "10H", "9C" })
  play(state, rng, "split")
  local text = textutils and textutils.serialize(state, { compact = true }) or nil
  if not text then return end
  local back = textutils.unserialize(text)
  t.eq(back.active, 1)
  t.eq(#back.cards, #state.cards)
  t.eq(#back.hands, 2)
  t.eq(rules.risk(back), 200)
  play(back, rng, "hit", "stand")
  t.truthy(rules.done(back))
  t.eq(rules.net(back), 200)
end)

t.test("a state never shares a table with itself or the keep", function()
  local keep = {}
  local rng = t.fastRng(4)
  local state = rules.new(100, rng, keep, {})
  t.eq(keep.shoe, nil, "the shoe moved into the state")
  local seen = {}
  local function walk(value)
    t.truthy(not seen[value], "a table reached twice")
    seen[value] = true
    for _, inner in pairs(value) do
      t.truthy(type(inner) ~= "function", "plain data only")
      if type(inner) == "table" then walk(inner) end
    end
  end
  walk(state)
  rules.finish(state, keep)
  t.truthy(keep.shoe ~= state.cards, "and moved back out")
  t.eq(#state.cards, 0)
end)

t.test("the shoe lasts between rounds and reshuffles only below the cut", function()
  local keep = {}
  local rng = t.fastRng(5)
  local state, events = rules.new(100, rng, keep, {})
  t.truthy(events[1].fresh, "the first round shuffles")
  t.eq(#state.cards, 6 * 52 - 4)
  rules.act(state, "stand", rng)
  local left = #state.cards
  rules.finish(state, keep)
  state, events = rules.new(100, rng, keep, {})
  t.truthy(not events[1].fresh)
  t.eq(#state.cards, left - 4, "the same shoe")
  rules.act(state, "stand", rng)
  rules.finish(state, keep)

  while #keep.shoe > 156 do table.remove(keep.shoe) end
  state, events = rules.new(100, rng, keep, {})
  t.truthy(not events[1].fresh, "156 left still plays")
  rules.act(state, "stand", rng)
  rules.finish(state, keep)
  t.truthy(#keep.shoe < 156)
  state, events = rules.new(100, rng, keep, {})
  t.truthy(events[1].fresh, "below it, a fresh shoe")
  t.eq(#state.cards, 6 * 52 - 4)
end)

--- Basic strategy for these rules: H17, double on 11 only, one split, no double after it.
local function basic(state)
  if state.hold then return "stand" end
  local hand = state.hands[state.active]
  local up = math.min(deck.rank(state.dealer[1]), 10)
  if deck.rank(state.dealer[1]) == deck.ACE then up = 11 end
  local total, soft = rules.total(hand.cards)

  if has(state, "split") then
    local rank = math.min(deck.rank(hand.cards[1]), 10)
    if deck.rank(hand.cards[1]) == deck.ACE or rank == 8 then return "split" end
    if rank == 9 and up ~= 7 and up < 10 then return "split" end
    if rank == 7 and up <= 7 then return "split" end
    if rank == 6 and up >= 3 and up <= 6 then return "split" end
    if (rank == 2 or rank == 3) and up >= 4 and up <= 7 then return "split" end
  end
  if soft then
    if total >= 19 then return "stand" end
    if total == 18 and up <= 8 then return "stand" end
    return "hit"
  end
  if has(state, "double") then return "double" end
  if total >= 17 then return "stand" end
  if total >= 13 and up <= 6 then return "stand" end
  if total == 12 and up >= 4 and up <= 6 then return "stand" end
  return "hit"
end

t.test("basic strategy returns the modelled 98.5%, within 97.5 to 99.5", function()
  local value = t.simulate(rules, 150000, 100, basic, 11)
  print(("     blackjack return %.4f"):format(value))
  t.truthy(value >= 0.975 and value <= 0.995, "return " .. value)
end)

t.test("a reshuffle tells the engine, and the amount at risk ends as all that was wagered", function()
  local keep = {}
  local rng = t.fastRng(6)
  local state = rules.new(100, rng, keep, {})
  t.truthy(keep.shuffled, "a new shoe")
  state.hands[2] = { cards = {}, bet = 100 }
  t.eq(rules.risk(state), 200, "a split counts both bets")
end)

t.test("the help comes from the rules", function()
  local text = table.concat(game.help(), " ")
  t.truthy(text:find("3 to 2", 1, true), "the payout")
  t.truthy(text:find("soft 17", 1, true), "the dealer's rule")
  t.truthy(text:find("hard 11", 1, true), "the double")
end)
