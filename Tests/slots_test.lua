-- slots_test.lua

local rules = require("slots_rules")
local t = require("testing")

--- An rng that gives these numbers, then zeros.
local function scripted(list)
  local i = 0
  return { below = function(_, n)
    i = i + 1
    local value = list[i] or 0
    assert(value < n, "scripted value out of range")
    return value
  end }
end

--- The strip's first stop showing a symbol, as an rng value.
local function roll(symbol)
  for stop, shown in ipairs(rules.STRIP) do
    if shown == symbol then return stop - 1 end
  end
  error("symbol not on the strip")
end

local SEVEN, DIAMOND, BELL, CHERRY, LEMON, MELON = 1, 2, 3, 5, 6, 7

local function spin(a, b, c, bet, pot, flips)
  local list = { roll(a), roll(b), roll(c) }
  for _, value in ipairs(flips or {}) do list[#list + 1] = value end
  local rng = scripted(list)
  local state, events = rules.new(bet or 10, rng, {}, { pot = pot or 1000 })
  return state, rng, events
end

local function ids(state)
  local list = {}
  for _, action in ipairs(rules.actions(state)) do list[action.id] = true end
  return list
end

t.test("the paytable returns exactly 95.02% before the jackpot", function()
  local value, paid, total = rules.exactReturn()
  t.eq(paid, 133610, "weighted pays")
  t.eq(total, 52 * 52 * 52, "outcomes")
  t.eq(math.floor(value * 10000 + 0.5), 9502, "basis points")
end)

t.test("walking all 140,608 stops of the real strip gives the same return", function()
  local paid = 0
  for a = 1, rules.STOPS do
    for b = 1, rules.STOPS do
      for c = 1, rules.STOPS do
        paid = paid + rules.evaluate(rules.STRIP[a], rules.STRIP[b], rules.STRIP[c])
      end
    end
    t.breathe()
  end
  t.eq(paid, 133610, "pays over every stop")
end)

t.test("the strip holds each symbol exactly its weight, 2 3 5 5 9 13 15 of 52", function()
  local counts = {}
  for _, symbol in ipairs(rules.STRIP) do counts[symbol] = (counts[symbol] or 0) + 1 end
  t.eq(#rules.STRIP, 52, "stops")
  for i, weight in ipairs({ 2, 3, 5, 5, 9, 13, 15 }) do
    t.eq(rules.SYMBOLS[i].weight, weight, "weight of " .. rules.SYMBOLS[i].id)
    t.eq(counts[i], weight, "stops of " .. rules.SYMBOLS[i].id)
  end
end)

t.test("the pay table is the agreed one", function()
  local want = { { 100, 10 }, { 45, 6 }, { 16, 1 }, { 8, 1 }, { 5, 2 }, { 3, 1 }, { 2, 2 } }
  for i, pays in ipairs(want) do
    t.eq(rules.SYMBOLS[i].triple, pays[1], "triple " .. i)
    t.eq(rules.SYMBOLS[i].pair, pays[2], "pair " .. i)
  end
end)

t.test("a pair counts in any position", function()
  t.eq(rules.evaluate(CHERRY, CHERRY, BELL), 2)
  t.eq(rules.evaluate(CHERRY, BELL, CHERRY), 2)
  t.eq(rules.evaluate(BELL, CHERRY, CHERRY), 2)
  t.eq(rules.evaluate(LEMON, BELL, CHERRY), 0)
end)

t.test("a miss settles at once and loses the bet", function()
  local state = spin(LEMON, BELL, CHERRY)
  t.truthy(rules.done(state), "nothing to decide")
  t.eq(rules.net(state), -10)
  t.eq(rules.result(state).kind, "lose")
end)

t.test("a x1 pair is a push with nothing to gamble", function()
  local state = spin(LEMON, LEMON, MELON)
  t.truthy(rules.done(state))
  t.eq(rules.net(state), 0)
  t.eq(rules.result(state).kind, "push")
end)

t.test("only three 7s say JACKPOT", function()
  t.eq(rules.result(spin(SEVEN, SEVEN, SEVEN)).title, "JACKPOT")
  for _, symbol in ipairs({ DIAMOND, BELL, CHERRY, LEMON, MELON }) do
    local state = spin(symbol, symbol, symbol)
    t.truthy(rules.result(state).title ~= "JACKPOT", "three " .. symbol)
    t.eq(state.jackpotHit, nil, "no pot for three " .. symbol)
  end
end)

t.test("three 7s pay the pot on top and are never gambled", function()
  local state = spin(SEVEN, SEVEN, SEVEN, 10, 700)
  t.truthy(rules.done(state))
  t.eq(state.jackpotHit, 700)
  t.eq(rules.net(state), 990 + 700)
end)

t.test("the pot is capped by the bet, so maxWin holds at any pot", function()
  local state = spin(SEVEN, SEVEN, SEVEN, 1, 5000)
  t.eq(state.jackpotHit, rules.POT_TIMES, "a small bet takes a small share")
  t.eq(rules.net(state), rules.maxWin(1), "the promise is exact")
  state = spin(SEVEN, SEVEN, SEVEN, 200, 1000000)
  t.eq(rules.net(state), rules.maxWin(200), "and scales")
end)

t.test("no pot means the seed", function()
  local state = rules.new(10, scripted({ roll(SEVEN), roll(SEVEN), roll(SEVEN) }), {}, {})
  t.eq(state.jackpotHit, rules.JACKPOT.seed)
end)

t.test("a gamble won doubles the whole return, and settlement waits for collect", function()
  local state, rng = spin(CHERRY, CHERRY, BELL, 10, 1000, { 1 })
  t.truthy(not rules.done(state), "a decision is open")
  local actions = ids(state)
  t.truthy(actions.collect and actions.gamble, "both offered")
  rules.act(state, "gamble", rng)
  t.truthy(not rules.done(state), "still open after a win")
  t.eq(state.payout, 40)
  rules.act(state, "collect", rng)
  t.truthy(rules.done(state))
  t.eq(rules.net(state), 30)
end)

t.test("a gamble lost ends the round at once and costs the bet", function()
  local state, rng = spin(CHERRY, CHERRY, BELL, 10, 1000, { 0 })
  rules.act(state, "gamble", rng)
  t.truthy(rules.done(state), "over before the reveal plays")
  t.eq(rules.net(state), -10)
  t.eq(rules.result(state).title, "GAMBLE LOST")
end)

t.test("three flips is the end: the third win banks itself", function()
  local state, rng = spin(CHERRY, CHERRY, BELL, 10, 1000, { 1, 1, 1 })
  rules.act(state, "gamble", rng)
  rules.act(state, "gamble", rng)
  t.truthy(not rules.done(state), "one left")
  rules.act(state, "gamble", rng)
  t.truthy(rules.done(state), "banked")
  t.eq(state.payout, 160)
  t.eq(rules.net(state), 150)
end)

t.test("the gamble stops where doubling would pass x100", function()
  local state, rng = spin(DIAMOND, DIAMOND, DIAMOND, 10, 1000, { 1 })
  t.truthy(ids(state).gamble, "45 can become 90")
  rules.act(state, "gamble", rng)
  t.truthy(rules.done(state), "90 cannot become 180")
  t.eq(rules.net(state), 890)
end)

t.test("nobody home collects", function()
  local state, rng = spin(CHERRY, CHERRY, BELL)
  t.eq(rules.auto(state), "collect")
  rules.act(state, rules.auto(state), rng)
  t.truthy(rules.done(state))
  t.eq(rules.net(state), 10)
end)

t.test("the state is plain: it serializes whole at the decision", function()
  local state = spin(CHERRY, CHERRY, BELL)
  local seen = {}
  local function walk(value)
    if type(value) == "table" then
      t.truthy(not seen[value], "no shared table")
      seen[value] = true
      for k, v in pairs(value) do
        t.truthy(type(k) ~= "function" and type(v) ~= "function", "no functions")
        walk(v)
      end
    end
  end
  walk(state)
end)

--- The exact return of a policy by walking every weighted outcome. Flips are split 50/50 as the rules flip them.
local function policyReturn(gambleWhile)
  local function value(state)
    if rules.done(state) then return state.payout end
    local keep = state.payout
    if not gambleWhile(state) then return keep end
    local won = { bet = state.bet, payout = state.payout, gambles = state.gambles }
    rules.act(won, "gamble", scripted({ 1 }))
    return value(won) / 2
  end
  local paid, total = 0, 0
  for a, first in ipairs(rules.SYMBOLS) do
    for b, second in ipairs(rules.SYMBOLS) do
      for c, third in ipairs(rules.SYMBOLS) do
        local ways = first.weight * second.weight * third.weight
        total = total + ways
        local times = rules.evaluate(a, b, c)
        local state = { bet = 1000, payout = 1000 * times, gambles = 0, over = times <= 1 or (times >= 100) }
        paid = paid + ways * value(state) / 1000
      end
    end
  end
  return paid / total
end

t.test("gambling never changes the exact return, whatever the policy", function()
  local base = rules.exactReturn()
  t.near(policyReturn(function() return false end), base, 1e-12, "always collect")
  t.near(policyReturn(function() return true end), base, 1e-12, "always gamble")
  t.near(policyReturn(function(s) return s.gambles < 1 end), base, 1e-12, "gamble once")
end)

t.test("simulated play stays near the exact return, and no round breaks the promise", function()
  local rng = t.fastRng(4242)
  local staked, back = 0, 0
  for i = 1, 40000 do
    local state = rules.new(100, rng, {}, { pot = 0 })
    while not rules.done(state) do
      rules.act(state, i % 2 == 0 and "gamble" or "collect", rng)
    end
    local net = rules.net(state)
    t.truthy(net <= rules.maxWin(100), "within maxWin")
    t.truthy(net >= -100, "never more than the bet")
    staked, back = staked + 100, back + 100 + net
    if i % 2000 == 0 then t.breathe() end
  end
  t.near(back / staked, rules.exactReturn(), 0.06, "return")
end)

t.test("all seven symbols are drawn, every row the same width, and every moment draws", function()
  local canvas = require("lib.casino.canvas")
  local view = require("slots_view")
  for _, symbol in ipairs(rules.SYMBOLS) do
    local rows = view.SPRITES[symbol.id]
    t.eq(#rows, 13, symbol.id .. " rows")
    for j, row in ipairs(rows) do t.eq(#row, 20, symbol.id .. " row " .. j) end
    local mini = view.MINI[symbol.id]
    t.eq(#mini, 5, symbol.id .. " small rows")
    for j, row in ipairs(mini) do t.eq(#row, 9, symbol.id .. " small row " .. j) end
  end
  local c = canvas.new(nil, 121, 81)
  local state, _, events = spin(CHERRY, CHERRY, BELL)
  local model = view.new({ jackpot = 1000 })
  view.sync(model, state)
  for _, ev in ipairs(events) do
    view.event(model, ev)
    for _, at in ipairs({ 0, 0.5, 1 }) do view.draw(c, model, state, { ev = ev, t = at }) end
    view.commit(model, ev)
  end
  view.draw(c, model, state, nil)
  local flip = { type = "flip", won = true, amount = 40 }
  view.event(model, flip)
  for _, at in ipairs({ 0, 0.5, 1 }) do view.draw(c, model, state, { ev = flip, t = at }) end
end)

t.test("the help carries the real numbers", function()
  local help = require("slots_game").help()
  local text = {}
  for _, line in ipairs(help) do text[#text + 1] = type(line) == "table" and line[1] or line end
  text = table.concat(text, " ")
  t.truthy(text:find("95.02%", 1, true), "the return")
  t.truthy(text:find("x100", 1, true), "the top pay")
end)
