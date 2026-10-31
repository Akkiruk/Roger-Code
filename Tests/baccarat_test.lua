-- baccarat_test.lua
-- Scripted coups against a stacked shoe, then the exact returns of a fresh shoe, enumerated through the rules.
-- The expected figures come from tools/casinotest/baccarat.mjs in craftos-agent, a separate enumeration in JS with its
-- own third-card table, which runs over every ordered six cards of 416.

local deck = require("lib.casino.deck")
local rules = require("baccarat_rules")
local game = require("baccarat_game")
local t = require("testing")

local BANKER_WINS, PLAYER_WINS, TIES = 2292252566437888, 2230518282592256, 475627426473216

--- A round dealt from these cards, in deal order: P, B, P, B, then draws.
local function rigged(names, bet)
  local rng = t.fastRng(9)
  local keep = { shoe = deck.stack(deck.fresh(rules.DECKS), names) }
  local state = rules.new(bet or 100, rng, keep, {})
  return state, rng
end

local function has(state, id)
  for _, action in ipairs(rules.actions(state)) do
    if action.id == id then return action end
  end
  return nil
end

local function coup(names, side, bet)
  local state, rng = rigged(names, bet)
  rules.act(state, side, rng)
  return state
end

t.test("card values and totals", function()
  t.eq(rules.value(deck.parse("AS")), 1)
  t.eq(rules.value(deck.parse("10H")), 0)
  t.eq(rules.value(deck.parse("KD")), 0)
  t.eq(rules.value(deck.parse("9C")), 9)
  t.eq(rules.total({ deck.parse("9C"), deck.parse("8D") }), 7)
end)

t.test("a Player win pays 1:1, and Banker and Tie bets lose on it", function()
  local names = { "9H", "2C", "KD", "3S", "4D", "5H" } -- P 9 natural, B 5
  t.eq(rules.net(coup(names, "player")), 100)
  t.eq(rules.net(coup(names, "banker")), -100)
  t.eq(rules.net(coup(names, "tie")), -100)
end)

t.test("a Banker win pays less 5%, rounded up", function()
  local names = { "2H", "9C", "KD", "KS" } -- B natural 9
  t.eq(rules.net(coup(names, "banker", 100)), 95)
  t.eq(rules.net(coup(names, "banker", 20)), 19)
  t.eq(rules.net(coup(names, "banker", 21)), 19)
  t.eq(rules.net(coup(names, "banker", 40)), 38)
  t.eq(rules.net(coup(names, "banker", 99)), 94)
  t.eq(rules.net(coup(names, "player", 100)), -100)
end)

t.test("the commission is never below 5%", function()
  for bet = rules.MIN_BANKER, 500 do
    t.truthy(rules.commission(bet) >= bet * 0.05, "bet " .. bet)
    t.truthy(rules.commission(bet) % 1 == 0)
    t.truthy(rules.winOn("banker", bet) > 0, "a Banker bet can win")
  end
end)

t.test("a Banker bet below the minimum is not offered or taken", function()
  local state, rng = rigged({ "2H", "9C", "KD", "KS" }, rules.MIN_BANKER - 1)
  t.truthy(not has(state, "banker"))
  t.truthy(has(state, "player"))
  rules.act(state, "banker", rng)
  t.truthy(not rules.done(state), "refused")
  t.truthy(has(rigged({ "2H" }, rules.MIN_BANKER), "banker"))
end)

t.test("a tie pays 8:1 on Tie and pushes the others", function()
  local names = { "9H", "9C", "KD", "KS" }
  t.eq(rules.net(coup(names, "tie")), 800)
  t.eq(rules.net(coup(names, "player")), 0)
  t.eq(rules.net(coup(names, "banker")), 0)
  t.eq(rules.result(coup(names, "player")).kind, "push")
  t.eq(rules.result(coup(names, "tie")).kind, "win")
  t.eq(rules.maxWin(100), 800)
end)

t.test("no draw against a natural", function()
  local state = coup({ "8H", "2C", "KD", "KS", "9D", "9H" }, "player")
  t.eq(#state.player, 2)
  t.eq(#state.banker, 2)
  state = coup({ "2H", "8C", "KD", "KS", "9D", "9H" }, "banker")
  t.eq(#state.player, 2)
  t.eq(#state.banker, 2)
end)

t.test("Player draws on 0 to 5, stands on 6 and 7", function()
  t.truthy(rules.playerDraws(5))
  t.truthy(rules.playerDraws(0))
  t.truthy(not rules.playerDraws(6))
  t.truthy(not rules.playerDraws(7))
  t.eq(#coup({ "3H", "KC", "2D", "7S", "2C" }, "player").player, 3, "5 draws")
  t.eq(#coup({ "4H", "KC", "2D", "7S", "2C" }, "player").player, 2, "6 stands")
end)

t.test("the third-card table, every total against every third card", function()
  local table_ = {
    [0] = "1111111111", [1] = "1111111111", [2] = "1111111111",
    [3] = "1111111101", [4] = "0011111100", [5] = "0000111100",
    [6] = "0000001100", [7] = "0000000000",
  }
  for total = 0, 7 do
    for third = 0, 9 do
      local expected = table_[total]:sub(third + 1, third + 1) == "1"
      t.eq(rules.bankerDraws(total, third), expected, ("banker %d, third %d"):format(total, third))
    end
  end
  for total = 0, 7 do t.eq(rules.bankerDraws(total, nil), total <= 5, "stood, banker " .. total) end
end)

t.test("the Banker's third card follows the Player's", function()
  local state = coup({ "2H", "2C", "KD", "KS", "9C", "4D" }, "player") -- P 2 draws 9, B 2 draws 4
  t.eq(#state.player, 3)
  t.eq(#state.banker, 3)
  t.eq(rules.total(state.player), 1)
  t.eq(rules.total(state.banker), 6)
  t.eq(rules.net(state), -100)
  state = coup({ "2H", "3C", "KD", "KS", "8C", "4D" }, "player") -- B 3 stands on an 8
  t.eq(#state.banker, 2)
  t.eq(rules.total(state.player), 0)
  t.eq(rules.net(state), -100, "3 beats 0")
  state = coup({ "6H", "3C", "KD", "2S", "9C" }, "player") -- P stood on 6, B 5 draws
  t.eq(#state.player, 2)
  t.eq(#state.banker, 3)
end)

t.test("a resumed or abandoned round costs nothing", function()
  local state, rng = rigged({ "9H", "2C", "KD", "3S" })
  t.eq(rules.auto(state), "cancel")
  rules.act(state, rules.auto(state), rng)
  t.truthy(rules.done(state))
  t.eq(rules.net(state), 0)
  t.eq(rules.result(state).kind, "push")
  t.eq(#state.player, 0, "no card went out")
end)

t.test("nothing is dealt until a side is chosen, and every card has an event", function()
  local state, rng = rigged({ "2H", "2C", "KD", "KS", "9C", "4D" })
  t.eq(#state.player + #state.banker, 0)
  t.eq(#rules.actions(state), 3, "the three sides")
  local events = rules.act(state, "player", rng)
  local deals = 0
  for _, ev in ipairs(events) do
    if ev.type == "deal" then deals = deals + 1 end
  end
  t.eq(deals, #state.player + #state.banker)
  t.eq(events[#events].type, "outcome")
end)

t.test("a state survives serialization", function()
  if not textutils then return end
  local state, rng = rigged({ "9H", "2C", "KD", "3S" })
  local back = textutils.unserialize(textutils.serialize(state, { compact = true }))
  rules.act(back, "player", rng)
  t.eq(rules.net(back), 100)
end)

t.test("the shoe lasts, burns one, and reshuffles below the cut", function()
  local keep = {}
  local rng = t.fastRng(5)
  local state, events = rules.new(100, rng, keep, {})
  t.truthy(events[1].fresh)
  t.eq(#state.cards, 8 * 52 - rules.BURN)
  rules.act(state, "player", rng)
  local left = #state.cards
  t.truthy(left <= 8 * 52 - 5, "cards went out")
  rules.finish(state, keep)
  state, events = rules.new(100, rng, keep, {})
  t.truthy(not events[1].fresh)
  t.eq(#state.cards, left)
  rules.finish(state, keep)

  while #keep.shoe > 30 do table.remove(keep.shoe) end
  state, events = rules.new(100, rng, keep, {})
  t.truthy(not events[1].fresh, "30 left still plays")
  rules.act(state, "player", rng)
  rules.finish(state, keep)
  t.truthy(#keep.shoe < 30)
  state, events = rules.new(100, rng, keep, {})
  t.truthy(events[1].fresh, "below it, a fresh shoe")
  t.eq(#state.cards, 8 * 52 - rules.BURN)
end)

--- Walk every value sequence of a fresh shoe through rules.act, weighted by how many ordered cards give it.
local function enumerate()
  local names = { [0] = "KS", "AS", "2S", "3S", "4S", "5S", "6S", "7S", "8S", "9S" }
  local cardOf = {}
  for value = 0, 9 do cardOf[value] = deck.parse(names[value]) end
  local counts = { [0] = 16 * rules.DECKS }
  for value = 1, 9 do counts[value] = 4 * rules.DECKS end
  local rng = t.fastRng(1)
  local tally = { player = 0, banker = 0, tie = 0 }
  local total = 52 * rules.DECKS

  local function run(seq, n)
    local cards = {}
    for i = 6, 1, -1 do cards[#cards + 1] = cardOf[seq[i] or 0] end
    local state = { bet = 100, cards = cards, player = {}, banker = {} }
    rules.act(state, "player", rng)
    return state.winner, #state.player + #state.banker, n
  end

  local seq = {}
  local steps = 0
  local function walk(depth, weight)
    local winner, used = run(seq, depth)
    if used <= depth then
      tally[winner] = tally[winner] + weight
      return
    end
    for value = 0, 9 do
      local ways = counts[value]
      seq[depth + 1] = value
      counts[value] = ways - 1
      walk(depth + 1, weight * ways / (total - depth))
      counts[value] = ways
    end
    seq[depth + 1] = nil
    steps = steps + 1
    if steps % 2000 == 0 then t.breathe() end
  end

  for a = 0, 9 do
    for b = 0, 9 do
      for c = 0, 9 do
        for d = 0, 9 do
          seq[1], seq[2], seq[3], seq[4] = a, b, c, d
          local weight, n = 1, 0
          for _, value in ipairs(seq) do
            if n < 4 then
              weight = weight * counts[value] / (total - n)
              counts[value] = counts[value] - 1
              n = n + 1
            end
          end
          walk(4, weight)
          for i = 1, 4 do counts[seq[i]] = counts[seq[i]] + 1 end
        end
      end
      t.breathe()
    end
  end
  return tally
end

t.test("exact returns match an independent enumeration of a fresh shoe", function()
  local tally = enumerate()
  local sum = BANKER_WINS + PLAYER_WINS + TIES
  t.near(tally.banker + tally.player + tally.tie, 1, 1e-9, "every coup counted")
  t.near(tally.banker, BANKER_WINS / sum, 1e-10, "Banker wins")
  t.near(tally.player, PLAYER_WINS / sum, 1e-10, "Player wins")
  t.near(tally.tie, TIES / sum, 1e-10, "ties")

  local win = rules.winOn("banker", 100) / 100
  local banker = 1 + tally.banker * win - tally.player
  local player = 1 + tally.player - tally.banker
  local tie = 1 + tally.tie * rules.PAYS.tie - (1 - tally.tie)
  print(("     baccarat banker %.5f player %.5f tie %.5f"):format(banker, player, tie))
  t.near(banker, 0.98942, 0.00002, "Banker return")
  t.near(player, 0.98765, 0.00002, "Player return")
  t.near(tie, 0.85640, 0.00002, "Tie return")
end)

t.test("a simulation of the real shoe agrees", function()
  t.near(t.simulate(rules, 40000, 100, function() return "banker" end, 21), 0.9894, 0.012, "Banker")
end)

t.test("a cancelled round has no bet standing, and a played one has", function()
  local rng = t.fastRng(3)
  local state = rules.new(100, rng, {}, {})
  t.eq(rules.risk(state), 100, "standing until it is called off")
  rules.act(state, "cancel")
  t.eq(rules.risk(state), 0)
  state = rules.new(100, rng, {}, {})
  rules.act(state, "player")
  t.eq(rules.risk(state), 100, "a push still wagered it")
end)

t.test("only a reshuffle tells the engine a new shoe has begun", function()
  local rng = t.fastRng(4)
  local keep = {}
  local state = rules.new(100, rng, keep, {})
  t.truthy(keep.shuffled, "the first shoe")
  keep.shuffled = nil
  rules.act(state, "player")
  rules.finish(state, keep)
  state = rules.new(100, rng, keep, {})
  t.eq(keep.shuffled, nil, "the same shoe carries on")
  rules.act(state, "player")
  rules.finish(state, keep)
  while #keep.shoe >= rules.RESHUFFLE_BELOW do table.remove(keep.shoe) end
  rules.new(100, rng, keep, {})
  t.truthy(keep.shuffled, "a new shoe")
end)

t.test("the help is built from the rules", function()
  local text = table.concat(game.help(), " ")
  t.truthy(text:find(rules.COMMISSION .. "%", 1, true), "commission")
  t.truthy(text:find("pays " .. rules.PAYS.tie .. " to 1", 1, true), "tie odds")
  t.truthy(text:find("push", 1, true), "push on a tie")
  t.truthy(text:find("wins " .. rules.winOn("banker", 100), 1, true), "worked example")
  t.truthy(text:find("smallest Banker bet is " .. rules.MIN_BANKER, 1, true), "minimum")
end)
