-- hilo_test.lua

local deck = require("lib.casino.deck")
local rules = require("hilo_rules")
local t = require("testing")

--- A round whose first cards are these, by name.
local function rigged(names, bet)
  local rng = t.fastRng(9)
  local state = rules.new(bet or 100, rng, {}, {})
  state.cards = deck.stack(deck.fresh(1), names)
  state.current = deck.draw(state.cards)
  state.trail = { state.current }
  return state, rng
end

t.test("a right guess then cash out pays the priced multiple", function()
  local state, rng = rigged({ "5H", "9S" })
  rules.act(state, "higher", rng)
  t.truthy(state.multiple > 1, "multiple rose")
  rules.act(state, "cash", rng)
  t.truthy(rules.done(state))
  t.eq(rules.net(state), math.floor(100 * state.multiple) - 100)
end)

t.test("a wrong guess loses the bet", function()
  local state, rng = rigged({ "5H", "2S" })
  rules.act(state, "higher", rng)
  t.eq(rules.net(state), -100)
  t.eq(rules.result(state).kind, "lose")
end)

t.test("equal ranks lose", function()
  local state, rng = rigged({ "5H", "5S" })
  rules.act(state, "lower", rng)
  t.eq(rules.net(state), -100)
  t.eq(rules.result(state).title, "SAME RANK")
end)

t.test("no cash out before a right guess, and none that pays nothing", function()
  local state = rigged({ "5H", "9S" }, 1)
  for _, action in ipairs(rules.actions(state)) do t.truthy(action.id ~= "cash", "no cash on the first card") end
end)

t.test("an impossible side is not offered", function()
  local state = rigged({ "AH", "2S" })
  for _, action in ipairs(rules.actions(state)) do t.truthy(action.id ~= "higher", "nothing beats an ace") end
end)

t.test("nobody home banks the streak", function()
  local state, rng = rigged({ "5H", "9S" })
  t.truthy(rules.auto(state) == "higher", "takes the likelier side first")
  rules.act(state, "higher", rng)
  t.eq(rules.auto(state), "cash")
end)

t.test("the return is the same whenever you stop", function()
  local function stopAfter(n)
    return function(state)
      if state.guesses >= n then
        for _, action in ipairs(rules.actions(state)) do
          if action.id == "cash" then return "cash" end
        end
      end
      return rules.auto({ guesses = 0, current = state.current, cards = state.cards, multiple = 1, bet = state.bet })
    end
  end
  for _, n in ipairs({ 1, 2, 4 }) do
    t.near(t.simulate(rules, 60000, 1000, stopAfter(n), n), rules.RETURN, 0.02, "stopping after " .. n)
  end
end)
