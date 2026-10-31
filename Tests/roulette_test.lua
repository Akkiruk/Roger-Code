-- roulette_test.lua

local rules = require("roulette_rules")
local view = require("roulette_view")
local t = require("testing")

--- A generator that always gives this number.
local function fixed(n)
  return { below = function() return n end }
end

local function spin(wager, n)
  return rules.new(wager, fixed(n), {}, {})
end

--- Numbers the spot should cover, worked out here from the layout and not from the rules' own tables.
local REDS = { 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36 }

local function expected(spot, n)
  local kind = spot.kind
  if kind == "red" or kind == "black" then
    local red = false
    for _, value in ipairs(REDS) do red = red or value == n end
    return n ~= 0 and red == (kind == "red")
  elseif kind == "odd" then return n % 2 == 1
  elseif kind == "even" then return n ~= 0 and n % 2 == 0
  elseif kind == "low" then return n >= 1 and n <= 18
  elseif kind == "high" then return n >= 19
  elseif kind == "dozen" then
    local d = tonumber(spot.id:match("%d$"))
    return n >= 1 and math.ceil(n / 12) == d
  elseif kind == "column" then
    local row = tonumber(spot.id:match("%d$"))
    return n ~= 0 and (n - 1) % 3 + 1 == row
  end
  for number in spot.id:match(":(.*)$"):gmatch("%d+") do
    if tonumber(number) == n then return true end
  end
  return false
end

t.test("the table offers every bet there is", function()
  local counts = {}
  for _, spot in ipairs(rules.SPOTS) do counts[spot.kind] = (counts[spot.kind] or 0) + 1 end
  t.eq(counts.straight, 37, "straights")
  t.eq(counts.split, 60, "splits, three with zero")
  t.eq(counts.street, 14, "streets and two trios")
  t.eq(counts.corner, 23, "corners and the first four")
  t.eq(counts.line, 11, "lines")
  t.eq(counts.dozen, 3, "dozens")
  t.eq(counts.column, 3, "columns")
  for _, kind in ipairs({ "red", "black", "odd", "even", "low", "high" }) do t.eq(counts[kind], 1, kind) end
end)

t.test("the wheel holds each number once, with colours alternating", function()
  local seen = {}
  for i, n in ipairs(rules.WHEEL) do
    t.truthy(not seen[n], "repeat " .. n)
    seen[n] = true
    local nextOne = rules.WHEEL[i + 1]
    if n ~= 0 and nextOne and nextOne ~= 0 then
      t.truthy(rules.color(n) ~= rules.color(nextOne), n .. " next to " .. nextOne)
    end
  end
  t.eq(#rules.WHEEL, 37)
end)

t.test("every number against every bet pays exactly what the kind says", function()
  for _, spot in ipairs(rules.SPOTS) do
    local nums = 0
    for n = 0, 36 do
      local should = expected(spot, n)
      t.eq(rules.covers(spot.id, n), should, spot.id .. " on " .. n)
      local state = spin({ [spot.id] = 10 }, n)
      t.eq(state.number, n)
      t.eq(rules.net(state), should and spot.pay * 10 or -10, spot.id .. " net on " .. n)
      if should then nums = nums + 1 end
    end
    t.eq(nums, #spot.nums, spot.id .. " coverage")
  end
end)

t.test("every inside bet covers numbers that touch on the layout", function()
  local function column(n) return math.ceil(n / 3) end
  for _, spot in ipairs(rules.SPOTS) do
    if spot.kind == "split" and spot.nums[1] ~= 0 then
      local a, b = spot.nums[1], spot.nums[2]
      t.truthy(b - a == 3 or (b - a == 1 and column(a) == column(b)), spot.id)
    elseif spot.kind == "corner" and spot.nums[1] ~= 0 then
      local a, b, c, d = unpack(spot.nums)
      t.truthy(column(a) == column(b) and column(c) == column(d) and c == a + 3 and d == b + 3 and b == a + 1, spot.id)
    elseif spot.kind == "street" and spot.nums[1] ~= 0 then
      t.eq(column(spot.nums[1]), column(spot.nums[3]), spot.id)
    elseif spot.kind == "line" then
      t.eq(spot.nums[6], spot.nums[1] + 5, spot.id)
      t.eq(spot.nums[1] % 3, 1, spot.id)
    end
  end
end)

t.test("every bet returns exactly 97.30 percent", function()
  local kinds = {}
  for _, spot in ipairs(rules.SPOTS) do
    local back = 0
    for n = 0, 36 do
      back = back + 100 + rules.netOn({ [spot.id] = 100 }, n)
    end
    t.eq(back, 3600, spot.id .. " tokens back over all 37 numbers on a 100 stake")
    kinds[spot.kind] = true
    t.near(back / 3700, 36 / 37, 1e-12)
  end
  for _, kind in ipairs(rules.KINDS) do
    t.truthy(kinds[kind.id], kind.id .. " enumerated")
    t.eq(kind.covers * (kind.pay + 1), 36, kind.id .. " price")
  end
end)

t.test("overlapping bets add up on every number", function()
  local wager = { ["straight:17"] = 100, ["split:14-17"] = 50, ["corner:13-14-16-17"] = 25, black = 200, ["dozen:2"] = 10, odd = 40 }
  local state = spin(wager, 17)
  t.eq(rules.net(state), 3500 + 850 + 200 + 200 + 20 + 40)
  t.eq(rules.net(spin(wager, 14)), -100 + 850 + 200 - 200 + 20 - 40)
  t.eq(rules.net(spin(wager, 0)), -425)
  t.eq(#rules.winners(wager, 17), 6)
  t.eq(rules.stakeOf(wager), 425)
end)

t.test("maxWin is the best single number across overlapping bets", function()
  local cases = {
    { ["straight:17"] = 100 },
    { red = 100, black = 100 },
    { red = 100, black = 300 },
    { ["straight:1"] = 10, ["straight:2"] = 10, ["split:1-2"] = 10, ["street:1-2-3"] = 5, ["corner:0-1-2-3"] = 1 },
    { ["dozen:1"] = 100, ["column:1"] = 100, odd = 100, low = 100, red = 100 },
  }
  for _, wager in ipairs(cases) do
    local best, stake = -math.huge, 0
    for id, amount in pairs(wager) do stake = stake + amount; local _ = id end
    for n = 0, 36 do
      local total = 0
      for id, amount in pairs(wager) do
        local spot = rules.spot(id)
        total = total + (expected(spot, n) and amount * spot.pay or -amount)
      end
      best = math.max(best, total)
    end
    t.eq(rules.maxWin(wager), math.max(0, best))
  end
  t.eq(rules.maxWin({ ["straight:17"] = 100 }), 3500)
  t.eq(rules.maxWin({ red = 100, black = 100 }), 0)
end)

t.test("a round is finished as it opens, picks one number, and shares nothing with the wager", function()
  local wager = { red = 5 }
  local keep = { recent = { 1, 2 } }
  local state, events = rules.new(wager, fixed(7), keep, {})
  t.truthy(rules.done(state))
  t.eq(state.number, 7)
  for _, ev in ipairs(events) do t.eq(ev.number, 7, ev.type) end
  t.truthy(state.spots ~= wager, "the wager is copied")
  t.truthy(state.recent ~= keep.recent, "the history is copied")
  wager.red = 500
  t.eq(rules.net(state), 5)
  t.eq(rules.risk(state), 5)
  t.eq(#rules.actions(state), 0)
end)

t.test("the result names the number and its colour", function()
  t.eq(rules.result(spin({ red = 1 }, 1)).title, "1 RED")
  t.eq(rules.result(spin({ red = 1 }, 2)).title, "2 BLACK")
  t.eq(rules.result(spin({ red = 1 }, 0)).kind, "lose")
  t.eq(rules.result(spin({ red = 1 }, 0)).title, "0 GREEN")
  t.eq(rules.result(spin({ red = 1, black = 1 }, 1)).kind, "push")
  t.eq(rules.result(spin({ red = 1 }, 1)).kind, "win")
end)

t.test("recent numbers keep the newest, newest first", function()
  local keep = {}
  for n = 1, 20 do rules.finish(spin({ red = 1 }, n), keep) end
  t.eq(#keep.recent, rules.RECENT_KEPT)
  t.eq(keep.recent[1], 20)
  t.eq(keep.recent[rules.RECENT_KEPT], 20 - rules.RECENT_KEPT + 1)
end)

t.test("the wheel lands on the true number, from every number", function()
  for n = 0, 36 do
    t.eq(view.pocketAt(view.finalRotation(n), view.ballAngle(n, 1)), n, "ball on " .. n)
    t.near(math.sin(view.ballAngle(n, 1)), -1, 1e-9, "stops under the marker")
  end
end)

t.test("every spot on the table has a tap target, and only one in its mode", function()
  local found = {}
  for _, mode in ipairs(view.MODES) do
    local cells = {}
    local targets = view.targets(15, mode)
    for _, target in ipairs(targets) do
      t.truthy(rules.spot(target.value), target.value)
      t.truthy(target.w >= 4 and target.h >= 7, "generous target " .. target.value)
      local kind = rules.spot(target.value).kind
      t.truthy(kind == mode or #rules.spot(target.value).nums >= 12, target.value .. " in " .. mode)
      if found[target.value] == nil or found[target.value] == mode then
        t.truthy(found[target.value] ~= mode or #rules.spot(target.value).nums >= 12, "one target for " .. target.value)
        found[target.value] = mode
      end
      for x = target.x, target.x + target.w - 1 do
        for y = target.y, target.y + target.h - 1 do
          local key = x .. "," .. y
          t.truthy(not cells[key], mode .. " targets overlap at " .. key)
          cells[key] = true
          t.truthy(x >= 1 and x <= 121 and y >= 1 and y <= 81, target.value .. " on the wall")
        end
      end
    end
  end
  for _, spot in ipairs(rules.SPOTS) do t.truthy(found[spot.id], "no target for " .. spot.id) end
end)

t.test("no two stake markers can touch, so every spot's stake can be read at once", function()
  local cells = {}
  for _, spot in ipairs(rules.SPOTS) do
    local x, y = view.chipSpot(spot.id)
    x = math.floor(x)
    for i = 0, 3 do
      local key = (x + i) .. "," .. y
      t.truthy(not cells[key], spot.id .. " overlaps " .. tostring(cells[key]) .. " at " .. key)
      cells[key] = spot.id
    end
    t.truthy(x >= 1 and x + 3 <= 121, spot.id .. " on the wall")
    t.truthy(y >= 0 and y < view.HEIGHT, spot.id .. " on the board")
  end
end)

t.test("stake markers stay short and never overstate", function()
  t.eq(view.short(250), "250")
  t.eq(view.short(1000), "1K")
  t.eq(view.short(1250), "1.2K")
  t.eq(view.short(12500), "12K")
  t.eq(view.short(2500000), "2.5M")
  for _, amount in ipairs({ 1, 999, 1999, 9999, 99999, 999999, 9999999, 123456789 }) do
    t.truthy(#view.short(amount) <= 4, amount .. " fits")
  end
end)
