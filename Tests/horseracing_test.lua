-- horseracing_test.lua

local rules = require("horseracing_rules")
local t = require("testing")

local RACES = 300

local function race(strengths)
  local names = {}
  for i = 1, rules.HORSES do names[i] = "Horse " .. i end
  return { strengths = strengths, names = names }
end

local EVEN = { 20, 20, 20, 20, 20, 20 }
local SKEWED = { 60, 10, 10, 10, 10, 10 }

--- All 720 finishing orders with their exact chance, handed to fn(chance, a, b, d).
local function eachOrder(strengths, fn)
  local total = 0
  for i = 1, rules.HORSES do total = total + strengths[i] end
  local used = {}
  local function walk(depth, left, chance, order)
    if depth > rules.HORSES then
      fn(chance, order[1], order[2], order[3])
      return
    end
    for horse = 1, rules.HORSES do
      if not used[horse] then
        used[horse] = true
        order[depth] = horse
        walk(depth + 1, left - strengths[horse], chance * strengths[horse] / left, order)
        used[horse] = false
      end
    end
  end
  walk(1, total, 1, {})
end

--- Every bet on a card, 100 tokens each.
local function everyBet()
  local bets = {}
  for _, kind in ipairs(rules.KINDS) do
    for horse = 1, rules.HORSES do bets[#bets + 1] = { kind = kind, a = horse, amount = 100 } end
  end
  for a = 1, rules.HORSES do
    for b = 1, rules.HORSES do
      if a ~= b then bets[#bets + 1] = { kind = "exacta", a = a, b = b, amount = 100 } end
    end
  end
  return bets
end

t.test("every bet on every horse returns 95-96% over all 720 orders of " .. RACES .. " races", function()
  local rng = t.fastRng(77)
  local bets = everyBet()
  t.eq(#bets, 48, "bets on the card")
  local lowest, highest, checked = 1, 0, 0
  for n = 1, RACES do
    local card = rules.newRace(rng)
    local prices = rules.prices(card.strengths)
    local back = {}
    local totalChance = 0
    for i = 1, #bets do back[i] = 0 end
    eachOrder(card.strengths, function(chance, a, b, d)
      totalChance = totalChance + chance
      for i, bet in ipairs(bets) do
        if rules.wins(bet, a, b, d) then back[i] = back[i] + chance * rules.payout(bet, prices, a, b, d) end
      end
    end)
    t.near(totalChance, 1, 1e-9, "the orders add to certainty")
    for i, bet in ipairs(bets) do
      local value = back[i] / bet.amount
      t.truthy(value <= 1, "no bet may beat the house")
      t.truthy(value <= rules.RETURN + 1e-9, bet.kind .. " at most the target")
      t.truthy(value >= 0.95 - 1e-9, bet.kind .. " on " .. bet.a .. " returns " .. value)
      if value < lowest then lowest = value end
      if value > highest then highest = value end
      checked = checked + 1
    end
    if n % 10 == 0 then t.breathe() end
  end
  print(("     %d bets: return %.4f to %.4f"):format(checked, lowest, highest))
end)

t.test("the chances agree with the enumeration", function()
  local chance = rules.chances(SKEWED)
  local win, place, show = {}, {}, {}
  for i = 1, rules.HORSES do win[i], place[i], show[i] = 0, 0, 0 end
  eachOrder(SKEWED, function(p, a, b, d)
    win[a] = win[a] + p
    place[a], place[b] = place[a] + p, place[b] + p
    show[a], show[b], show[d] = show[a] + p, show[b] + p, show[d] + p
  end)
  for i = 1, rules.HORSES do
    t.near(chance.win[i], win[i], 1e-12, "win")
    t.near(chance.place[i], place[i], 1e-12, "place")
    t.near(chance.show[i], show[i], 1e-12, "show")
  end
end)

t.test("no price pays less than the stake back, however strong the favourite", function()
  local prices = rules.prices(SKEWED)
  for _, kind in ipairs(rules.KINDS) do
    for horse = 1, rules.HORSES do t.truthy(prices[kind][horse] > 100, kind) end
  end
end)

t.test("payouts round down to whole tokens", function()
  local prices = { win = { 333 } }
  t.eq(rules.payout({ kind = "win", a = 1, amount = 7 }, prices, 1, 2, 3), 23, "7 at x3.33 is 23.31")
end)

t.test("the drawn order follows the strengths", function()
  local rng = t.fastRng(5)
  local strengths = { 60, 30, 20, 10, 10, 10 }
  local chance = rules.chances(strengths)
  local firsts, seconds = {}, {}
  local rounds = 60000
  for i = 1, rules.HORSES do firsts[i], seconds[i] = 0, 0 end
  for i = 1, rounds do
    local order = rules.drawOrder(strengths, rng)
    firsts[order[1]] = firsts[order[1]] + 1
    seconds[order[2]] = seconds[order[2]] + 1
    if i % 2000 == 0 then t.breathe() end
  end
  for i = 1, rules.HORSES do
    t.near(firsts[i] / rounds, chance.win[i], 0.01, "wins for " .. i)
    t.near((firsts[i] + seconds[i]) / rounds, chance.place[i], 0.012, "places for " .. i)
  end
end)

t.test("an order holds each horse once", function()
  local rng = t.fastRng(8)
  for _ = 1, 500 do
    local seen = {}
    for _, horse in ipairs(rules.drawOrder(SKEWED, rng)) do
      t.truthy(not seen[horse], "twice")
      seen[horse] = true
    end
    for i = 1, rules.HORSES do t.truthy(seen[i], "missing") end
  end
end)

t.test("a race is over from the start and pays what the card says", function()
  local wager = { race = race(EVEN), bets = {
    { kind = "win", a = 1, amount = 50 },
    { kind = "show", a = 2, amount = 20 },
    { kind = "exacta", a = 1, b = 3, amount = 10 },
  } }
  local rng = t.fastRng(3)
  local state, events = rules.new(wager, rng, {}, {})
  t.truthy(rules.done(state))
  t.eq(#rules.actions(state), 0, "no decisions")
  t.truthy(#events > 0, "a race to watch")
  local prices = rules.prices(EVEN)
  local first, second, third = state.order[1], state.order[2], state.order[3]
  local want = -80
  for _, bet in ipairs(wager.bets) do want = want + rules.payout(bet, prices, first, second, third) end
  t.eq(rules.net(state), want)
end)

t.test("state shares no tables with the wager", function()
  local wager = { race = race(EVEN), bets = { { kind = "win", a = 1, amount = 5 } } }
  local state = rules.new(wager, t.fastRng(1), {}, {})
  local seen = {}
  local function walk(value)
    if type(value) ~= "table" then return end
    t.truthy(not seen[value], "a shared table")
    seen[value] = true
    for _, v in pairs(value) do walk(v) end
  end
  walk(wager)
  walk(state)
end)

t.test("maxWin is the true best order of the whole card", function()
  local wager = { race = race(EVEN), bets = {
    { kind = "win", a = 1, amount = 50 },
    { kind = "place", a = 1, amount = 50 },
    { kind = "win", a = 2, amount = 50 },
    { kind = "exacta", a = 1, b = 2, amount = 25 },
  } }
  local prices = rules.prices(EVEN)
  local best = -math.huge
  eachOrder(EVEN, function(_, a, b, d)
    local back = -rules.stake(wager)
    for _, bet in ipairs(wager.bets) do back = back + rules.payout(bet, prices, a, b, d) end
    if back > best then best = back end
  end)
  t.eq(rules.maxWin(wager), best)
end)

t.test("no drawn race ever beats maxWin", function()
  local rng = t.fastRng(21)
  for i = 1, 3000 do
    local card = rules.newRace(rng)
    local wager = { race = card, bets = {
      { kind = "win", a = 1 + i % 6, amount = 10 },
      { kind = "show", a = 1 + (i + 1) % 6, amount = 25 },
      { kind = "exacta", a = 1 + i % 6, b = 1 + (i + 2) % 6, amount = 5 },
    } }
    local state = rules.new(wager, rng, {}, {})
    t.truthy(rules.net(state) <= rules.maxWin(wager), "within the promise")
    if i % 200 == 0 then t.breathe() end
  end
end)

t.test("the race on the wall ends on the drawn order, and horses never run backwards", function()
  local rng = t.fastRng(99)
  local changes = 0
  local races = 400
  for n = 1, races do
    local wager = { race = rules.newRace(rng), bets = { { kind = "win", a = 1, amount = 5 } } }
    local state = rules.new(wager, rng, {}, {})
    for rank = 2, rules.HORSES do
      local ahead = rules.position(state, state.order[rank - 1], 1)
      local behind = rules.position(state, state.order[rank], 1)
      t.truthy(ahead > behind + 1, "rank " .. rank .. " behind the one before")
    end
    t.near(rules.position(state, state.order[1], 1), rules.DISTANCE, 1e-9, "the winner reaches the line")
    local leader
    local last = {}
    for step = 0, 200 do
      local at, best, bestAt = step / 200, nil, -1e9
      for horse = 1, rules.HORSES do
        local place = rules.position(state, horse, at)
        t.truthy(place <= rules.DISTANCE + 1e-9, "nobody crosses early")
        t.truthy(place >= (last[horse] or 0) - 1e-9, "no horse goes backwards")
        last[horse] = place
        if place > bestAt then best, bestAt = horse, place end
      end
      if step > 0 and leader and best ~= leader then changes = changes + 1 end
      leader = best
    end
    t.eq(leader, state.order[1], "the winner leads at the end")
    if n % 20 == 0 then t.breathe() end
  end
  t.truthy(changes / races >= 2, "lead changes look natural, averaged " .. changes / races)
end)

t.test("winners are remembered, newest first, eight at most", function()
  local keep = {}
  for i = 1, 10 do
    rules.finish({ order = { 1 + i % 6 } }, keep)
  end
  t.eq(#keep.recent, 8)
  t.eq(keep.recent[1], 1 + 10 % 6)
end)

t.test("every stride of the horse has the same size, and the whole race draws", function()
  local canvas = require("lib.casino.canvas")
  local view = require("horseracing_view")
  for i, frame in ipairs(view.GALLOP) do
    t.eq(#frame, 6, "rows of stride " .. i)
    for j, row in ipairs(frame) do t.eq(#row, 17, "stride " .. i .. " row " .. j) end
  end
  local c = canvas.new(nil, 121, 81)
  local wager = { race = race(EVEN), bets = { { kind = "exacta", a = 1, b = 2, amount = 5 } } }
  local state, events = rules.new(wager, t.fastRng(2), {}, {})
  local model = view.new({})
  view.sync(model, state)
  for _, ev in ipairs(events) do
    view.event(model, ev)
    for step = 0, 10 do view.draw(c, model, state, { ev = ev, t = step / 10 }) end
    view.commit(model, ev)
  end
  view.draw(c, model, state, nil)
end)

t.test("multiples read short at every size", function()
  local view = require("horseracing_view")
  t.eq(view.multipleText(336), "x3.36")
  t.eq(view.multipleText(1344), "x13.4")
  t.eq(view.multipleText(28800), "x288")
end)

t.test("the help carries the real return", function()
  local help = require("horseracing_game").help()
  local text = {}
  for _, line in ipairs(help) do text[#text + 1] = type(line) == "table" and line[1] or line end
  t.truthy(table.concat(text, " "):find("96%", 1, true), "the return")
end)
