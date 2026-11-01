-- group_roulette_test.lua
-- Shared-wheel Roulette on Big Table. The return is proved by counting all 37 pockets, in whole numbers, through the same act a real
-- spin runs. Random rounds go through group_kit, and the geometry and the pictures are checked against a canvas that records.

local kit = require("group_kit")
local t = require("testing")
local original = require("roulette_rules")

local plugin = kit.plugin("BigTable", "roulette")
local rules = plugin.rules

-- group_kit forgets games.*, so these load the same way the plugin did
local saved = package.path
for part in saved:gmatch("[^;]+") do
  local root = part:match("^(.*)[/\\]Tests[/\\]%?%.lua$")
  if root then package.path = root .. "/Games/BigTable/?.lua;" .. saved end
end
local wheel = require("games.roulette.wheel")
local board = require("games.roulette.board")
local seatView = require("games.roulette.seatView")
local tableView = require("games.roulette.tableView")
local seatui = require("lib.casino.group.seatui")
package.path = saved
for name in pairs(package.loaded) do
  if name:find("^games%.") then package.loaded[name] = nil end
end

--- A generator that always gives this number.
local function fixed(n)
  return { below = function() return n end }
end

local function open(seats, bet, keep)
  local entries = {}
  for i, seat in ipairs(seats) do entries[i] = { seat = seat, name = "P" .. seat, bet = bet } end
  return (rules.new(entries, 1, fixed(0), keep or {}))
end

--- Every seat done and the wheel spun on this number.
local function spin(state, number)
  for _, seat in ipairs(rules.waitingOn(state)) do rules.act(state, seat, "done") end
  return rules.act(state, nil, "spin", nil, fixed(number))
end

--- A state with this wager laid on seat 1, ready to spin.
local function laid(wager, budget)
  local state = open({ 1 }, budget or 1000000)
  state.players[1].spots = wheel.copyWager(wager)
  return state
end

-- ------------------------------------------------------------------ the same table as Games/Roulette

t.test("the wheel is Games/Roulette's, pocket by pocket", function()
  t.eq(#wheel.WHEEL, 37, "pockets")
  for i, n in ipairs(original.WHEEL) do t.eq(wheel.WHEEL[i], n, "pocket " .. i) end
  for n = 0, 36 do t.eq(wheel.color(n), original.color(n), "colour of " .. n) end
end)

t.test("every spot is Games/Roulette's: id, kind, pay and numbers", function()
  t.eq(#wheel.SPOTS, #original.SPOTS, "spots")
  t.eq(#wheel.SPOTS, 157, "the count of bets")
  for i, spot in ipairs(original.SPOTS) do
    local mine = wheel.SPOTS[i]
    t.eq(mine.id, spot.id, "id")
    t.eq(mine.kind, spot.kind, spot.id .. " kind")
    t.eq(mine.pay, spot.pay, spot.id .. " pay")
    t.eq(mine.label, spot.label, spot.id .. " label")
    for n = 0, 36 do t.eq(wheel.covers(spot.id, n), original.covers(spot.id, n), spot.id .. " on " .. n) end
  end
end)

t.test("a net is the same as Games/Roulette's for random wagers", function()
  local rng = t.fastRng(9)
  for _ = 1, 300 do
    local wager = {}
    for _ = 1, 1 + rng:below(6) do
      wager[wheel.SPOTS[rng:below(#wheel.SPOTS) + 1].id] = 1 + rng:below(200)
    end
    for n = 0, 36 do t.eq(wheel.netOn(wager, n), original.netOn(wager, n), "net on " .. n) end
  end
end)

-- ------------------------------------------------------------------ the return, counted exactly

t.test("every spot returns exactly 36/37 (97.30%), through a real spin on each of the 37 pockets", function()
  local stake = 100
  for _, spot in ipairs(wheel.SPOTS) do
    local returned = 0
    for number = 0, 36 do
      local state = laid({ [spot.id] = stake })
      spin(state, number)
      returned = returned + stake + rules.nets(state)[1]
    end
    -- Whole numbers on both sides, so this is the exact fraction and no rounding is involved
    t.eq(returned * 37, 36 * 37 * stake, spot.id)
  end
  t.eq(("%.2f"):format(36 / 37 * 100), "97.30", "the figure the help states")
end)

t.test("a mixed wager on many seats returns exactly 36/37 too", function()
  local rng = t.fastRng(4242)
  for _ = 1, 40 do
    local staked, returned, seats = 0, 0, 1 + rng:below(8)
    local wagers = {}
    for seat = 1, seats do
      wagers[seat] = {}
      for _ = 1, 1 + rng:below(8) do
        wagers[seat][wheel.SPOTS[rng:below(#wheel.SPOTS) + 1].id] = 1 + rng:below(50)
      end
      staked = staked + wheel.stakeOf(wagers[seat])
    end
    for number = 0, 36 do
      local list = {}
      for seat = 1, seats do list[seat] = seat end
      local state = open(list, 100000)
      for seat = 1, seats do state.players[seat].spots = wheel.copyWager(wagers[seat]) end
      spin(state, number)
      local nets = rules.nets(state)
      for seat = 1, seats do returned = returned + wheel.stakeOf(wagers[seat]) + nets[seat] end
    end
    t.eq(returned, 36 * staked, "all 37 pockets paid back 36 stakes")
    t.breathe()
  end
end)

t.test("each seat's result comes from one shared number", function()
  local state = open({ 2, 3, 7 }, 100)
  rules.act(state, 2, "spot", "red")
  rules.act(state, 3, "spot", "black")
  rules.act(state, 7, "spot", "straight:17")
  spin(state, 17)
  local nets = rules.nets(state)
  t.eq(nets[2], -state.players[1].spots.red, "red lost")
  t.eq(nets[3], state.players[2].spots.black, "black won even money")
  t.eq(nets[7], state.players[3].spots["straight:17"] * 35, "the number won 35 to 1")
end)

-- ------------------------------------------------------------------ the contract, played at random

--- Random play that does put chips on the layout, which group_kit cannot reach by itself: spots are regions, not buttons.
local function pick(state, seat, _, rng)
  local roll = rng:below(100)
  if roll < 55 and rules.viewFor(state, seat).me.left > 0 then return "spot", wheel.SPOTS[rng:below(#wheel.SPOTS) + 1].id end
  if roll < 62 then return "mode", wheel.MODES[rng:below(#wheel.MODES) + 1] end
  return nil
end

t.test("2000 random rounds keep the whole contract, from one seat to eight", function()
  local before = {}
  kit.fuzz(plugin, {
    rounds = 2000, seats = { 1, 2, 3, 5, 8 }, bet = 500, absent = 15, pick = pick, seed = 777,
    check = function(state, entries)
      for _, player in ipairs(state.players) do
        local stake = wheel.stakeOf(player.spots)
        if stake > player.budget then error("seat " .. player.seat .. " laid " .. stake .. " of " .. player.budget, 0) end
        for id, amount in pairs(player.spots) do
          if not wheel.spot(id) or amount <= 0 or amount ~= math.floor(amount) then error("a bad bet on " .. tostring(id), 0) end
        end
        if #player.undo > 10 then error("the undo list grew", 0) end
        if rules.risk(state, player.seat) ~= stake then error("risk is not what was laid", 0) end
      end
      if state.number ~= nil then error("the number exists before the spin", 0) end
      before.entries = #entries
    end,
  })
  t.truthy(before.entries ~= nil, "the checks ran")
end)

t.test("over random rounds each net is exactly the wager on the number, and the book balances against the host", function()
  local rng = t.fastRng(31337)
  local wagered, won, rounds = 0, 0, 0
  for round = 1, 500 do
    local seats = {}
    for i = 1, 1 + rng:below(8) do seats[i] = i end
    local state = open(seats, 300)
    for _, seat in ipairs(seats) do
      for _ = 1, rng:below(6) do rules.act(state, seat, "spot", wheel.SPOTS[rng:below(#wheel.SPOTS) + 1].id) end
    end
    for _, seat in ipairs(rules.waitingOn(state)) do rules.act(state, seat, rules.auto(state, seat)) end
    local events = rules.act(state, nil, rules.auto(state, nil), nil, rng)
    t.truthy(#events > 0, "the wheel spun")
    t.truthy(rules.done(state), "one spin ends the round")
    local nets = rules.nets(state)
    for _, player in ipairs(state.players) do
      t.eq(nets[player.seat], wheel.netOn(player.spots, state.number), "the net")
      t.truthy(nets[player.seat] <= rules.maxWin({ bet = player.budget }), "within maxWin")
      t.truthy(nets[player.seat] >= -player.budget, "never past what was declared")
      wagered, won = wagered + wheel.stakeOf(player.spots), won + nets[player.seat]
    end
    rounds = round
    if round % 50 == 0 then t.breathe() end
  end
  t.eq(rounds, 500, "rounds played")
  t.truthy(wagered > 0, "chips went down")
end)

-- ------------------------------------------------------------------ illegal input

local function copy(state)
  return kit.plain(state)
end

local function refused(state, seat, id, value, what)
  local before = copy(state)
  local events = rules.act(state, seat, id, value, fixed(5))
  t.truthy(not events or #events == 0, what .. " must return nothing")
  t.truthy(kit.same(before, state), what .. " must change nothing")
end

t.test("illegal input does nothing", function()
  local state = open({ 2, 5 }, 100)
  refused(state, 1, "spot", "red", "a seat that is not playing")
  refused(state, 3, "done", nil, "another seat that is not playing")
  refused(state, 2, "spot", "straight:37", "a number that does not exist")
  refused(state, 2, "spot", "split:1-3", "a split that does not exist")
  refused(state, 2, "spot", nil, "no spot")
  refused(state, 2, "spot", 5, "a number for a spot")
  refused(state, 2, "spot", true, "a boolean for a spot")
  refused(state, 2, "chip", 7, "a chip that is not offered")
  refused(state, 2, "chip", "10", "a chip as text")
  refused(state, 2, "chip", nil, "no chip")
  refused(state, 2, "chip", 1000000, "a chip past the budget")
  refused(state, 2, "mode", "dozen", "a mode that does not exist")
  refused(state, 2, "mode", nil, "no mode")
  refused(state, 2, "undo", nil, "UNDO with nothing done")
  refused(state, 2, "clear", nil, "CLEAR with nothing down")
  refused(state, 2, "double", nil, "X2 with nothing down")
  refused(state, 2, "again", nil, "REPEAT with nothing to repeat")
  refused(state, 2, "nonsense", "red", "an unknown id")
  refused(state, 2, "spin", nil, "a seat spinning the wheel")
  refused(state, nil, "spin", nil, "a spin while seats are betting")
  refused(state, nil, "spot", "red", "the computer betting")
end)

t.test("a seat cannot lay more than its amount, and the last chip is cut to what is left", function()
  local state = open({ 1 }, 100)
  rules.act(state, 1, "chip", 50)
  t.truthy(#rules.act(state, 1, "spot", "red") > 0, "50")
  t.truthy(#rules.act(state, 1, "spot", "red") > 0, "100")
  refused(state, 1, "spot", "black", "a chip with nothing left")
  t.eq(state.players[1].spots.red, 100, "all of it on red")
  refused(state, 1, "double", nil, "X2 past the amount")

  local short = open({ 1 }, 70)
  rules.act(short, 1, "chip", 50)
  rules.act(short, 1, "spot", "red")
  rules.act(short, 1, "spot", "black")
  t.eq(short.players[1].spots.black, 20, "the rest, not the chip")
end)

t.test("a seat that is done, and a round that is over, take nothing more", function()
  local state = open({ 1, 2 }, 100)
  rules.act(state, 1, "spot", "red")
  rules.act(state, 1, "done")
  refused(state, 1, "spot", "black", "a bet after DONE")
  refused(state, 1, "done", nil, "DONE twice")
  refused(state, 1, "undo", nil, "UNDO after DONE")
  t.eq(#rules.actions(state, 1), 0, "no buttons after DONE")
  rules.act(state, 2, "done")
  refused(state, 2, "spot", "black", "the other seat too")
  t.truthy(#rules.act(state, nil, "spin", nil, fixed(3)) > 0, "the wheel spins")
  refused(state, nil, "spin", nil, "a second spin")
  refused(state, 1, "spot", "red", "a bet after the spin")
  t.eq(state.number, 3, "the number stands")
end)

t.test("every button offered works, and UNDO, CLEAR, X2 and REPEAT do what they say", function()
  local state = open({ 1 }, 1000)
  rules.act(state, 1, "chip", 100)
  rules.act(state, 1, "spot", "red")
  rules.act(state, 1, "spot", "straight:7")
  t.eq(rules.viewFor(state, 1).me.placed, 200, "two chips")
  rules.act(state, 1, "double")
  t.eq(rules.viewFor(state, 1).me.placed, 400, "X2")
  rules.act(state, 1, "undo")
  t.eq(rules.viewFor(state, 1).me.placed, 200, "UNDO takes back X2")
  rules.act(state, 1, "clear")
  t.eq(rules.viewFor(state, 1).me.placed, 0, "CLEAR")
  rules.act(state, 1, "undo")
  t.eq(rules.viewFor(state, 1).me.placed, 200, "UNDO takes back CLEAR")
  for _ = 1, 30 do rules.act(state, 1, "chip", 100); rules.act(state, 1, "double"); rules.act(state, 1, "undo") end
  t.truthy(#state.players[1].undo <= 10, "the list stays short")

  local keep = {}
  local first = open({ 1 }, 500, keep)
  rules.act(first, 1, "chip", 100)
  rules.act(first, 1, "spot", "dozen:2")
  spin(first, 14)
  rules.finish(first, keep)
  local second = open({ 1, 2 }, 500, keep)
  rules.act(second, 1, "again")
  t.eq(rules.viewFor(second, 1).me.spots["dozen:2"], 100, "REPEAT lays the last bet")
  refused(second, 2, "again", nil, "REPEAT for someone with no last bet")
  local poorer = open({ 1 }, 50, keep)
  refused(poorer, 1, "again", nil, "REPEAT past the amount")
  t.eq(rules.viewFor(second, 1).recent[1], 14, "the last number is carried")
end)

t.test("the last numbers stop at fourteen", function()
  local keep = {}
  for i = 1, 30 do
    local state = open({ 1 }, 100, keep)
    spin(state, i % 37)
    rules.finish(state, keep)
  end
  t.eq(#keep.recent, 14, "kept")
  t.eq(keep.recent[1], 30, "newest first")
end)

-- ------------------------------------------------------------------ the clock

t.test("the clock closes betting: chips stay down, and the rest was never bet", function()
  local state = open({ 1, 2 }, 200)
  rules.act(state, 1, "chip", 50)
  rules.act(state, 1, "spot", "red")
  t.truthy(rules.present(state, 1), "a seat with chips down has played")
  t.truthy(not rules.present(state, 2), "a seat with nothing down has not")
  t.truthy(not rules.present(state, 9), "nor a seat that is not here")
  rules.act(state, 1, rules.auto(state, 1))
  rules.act(state, 2, rules.auto(state, 2))
  t.eq(#rules.waitingOn(state), 0, "everyone closed")
  t.truthy(not rules.done(state), "the computer has the last move")
  t.eq(rules.auto(state, nil), "spin", "and it is the spin")
  rules.act(state, nil, "spin", nil, fixed(1))
  local nets = rules.nets(state)
  t.eq(nets[1], 50, "the chips played, and only those")
  t.eq(nets[2], 0, "nothing down, nothing lost")
  t.eq(rules.risk(state, 2), 0, "and nothing wagered")
  t.eq(rules.result(state, 2).kind, "push", "not a loss")
end)

t.test("the host is asked to cover the worst case, and that is exact", function()
  t.eq(rules.maxWin({ bet = 100 }), 3500, "35 to 1")
  local state = open({ 1 }, 100)
  rules.act(state, 1, "chip", 100)
  rules.act(state, 1, "spot", "straight:0")
  spin(state, 0)
  t.eq(rules.nets(state)[1], rules.maxWin({ bet = 100 }), "the whole bet on one number reaches it")
end)

-- ------------------------------------------------------------------ what each seat is told

t.test("no view holds another seat's bets, and nothing holds the number before the spin", function()
  local rng = t.fastRng(11)
  for _ = 1, 300 do
    local state = open({ 1, 4, 8 }, 500)
    local marks = { [1] = "straight:" .. rng:below(12), [4] = "corner:13-14-16-17", [8] = "line:31-32-33-34-35-36" }
    for seat, id in pairs(marks) do rules.act(state, seat, "spot", id) end
    for seat in pairs(marks) do
      local view = rules.viewFor(state, seat)
      t.truthy(view.me.spots[marks[seat]] ~= nil, "a seat sees its own")
      for other, id in pairs(marks) do
        if other ~= seat then
          t.truthy(view.me.spots[id] == nil, "nothing of seat " .. other)
          local found = false
          for key in pairs(view.me.spots) do found = found or key == id end
          t.truthy(not found, "not as a key")
        end
      end
      t.truthy(view.board == nil and view.seats == nil, "the wall's picture is not on a seat")
      t.truthy(view.number == nil, "no number yet")
    end
    local public = rules.viewFor(state, nil)
    t.truthy(public.number == nil, "no number on the wall yet")
    t.truthy(public.me == nil, "nobody's own view on the wall")
    for _, seat in ipairs(public.seats) do
      t.truthy(seat.net == nil, "no result yet")
      t.truthy(seat.budget == nil and seat.spots == nil and seat.undo == nil, "the wall gets totals")
    end
    local events = rules.act(state, 1, "spot", "red")
    for _, ev in ipairs(events) do t.truthy(ev.number == nil and ev.id == nil and ev.value == nil, "an event says only that something happened") end
    t.breathe()
  end
end)

t.test("a spin's events carry no number, and the views only have it once it is drawn", function()
  local state = open({ 1 }, 100)
  rules.act(state, 1, "done")
  local events = rules.act(state, nil, "spin", nil, fixed(23))
  t.eq(#events, 3, "spin, landed, payout")
  for _, ev in ipairs(events) do t.truthy(not kit.shows(ev, 23), "no number in " .. ev.type) end
  t.eq(rules.viewFor(state, 1).number, 23, "on the seat")
  t.eq(rules.viewFor(state, nil).number, 23, "on the wall")
end)

t.test("only the computer's spin touches the rng", function()
  local draws = 0
  local counting = { below = function(_, n) draws = draws + 1; return n - 1 end }
  local state = rules.new({ { seat = 1, name = "A", bet = 100 } }, 1, counting, {})
  rules.act(state, 1, "spot", "red", counting)
  rules.act(state, 1, "done", nil, counting)
  t.eq(draws, 0, "nothing is drawn before the spin")
  rules.act(state, nil, "spin", nil, counting)
  t.eq(draws, 1, "one draw, one number")
  t.eq(state.number, 36, "the top of the range is a pocket")
end)

-- ------------------------------------------------------------------ states survive a journal

t.test("every state and view comes back whole from textutils", function()
  if not textutils then return end -- plain Lua has no textutils. The emulator runs this, and group_kit proves plainness everywhere
  local state = open({ 1, 3 }, 300)
  local function roundTrip()
    local back = textutils.unserialize(textutils.serialize(state))
    t.truthy(kit.same(state, back), "the state")
    for _, seat in ipairs({ 1, 3, false }) do
      local view = rules.viewFor(state, seat or nil)
      t.truthy(kit.same(view, textutils.unserialize(textutils.serialize(view))), "a view")
    end
    state = back
  end
  roundTrip()
  rules.act(state, 1, "spot", "split:14-17")
  roundTrip()
  rules.act(state, 1, "mode", "corner")
  rules.act(state, 3, "spot", "red")
  rules.act(state, 1, "undo")
  roundTrip()
  rules.act(state, 1, "done")
  rules.act(state, 3, "done")
  roundTrip()
  rules.act(state, nil, "spin", nil, fixed(9))
  roundTrip()
  t.eq(rules.nets(state)[3], state.players[2].spots.red, "9 is red")
end)

-- ------------------------------------------------------------------ the layout on a seat

local AREA_RIGHT, AREA_BOTTOM = 77, seatui.TOP + 29 - 1 -- never the last column, and the row above the engine's note

t.test("every bet on the table can be reached by a tap", function()
  local reached = {}
  for _, mode in ipairs(wheel.MODES) do
    for _, target in ipairs(board.targets(14, mode)) do reached[target.value] = true end
  end
  for _, spot in ipairs(wheel.SPOTS) do t.truthy(reached[spot.id], "nothing taps " .. spot.id) end
end)

t.test("the targets of each mode stay on the screen and tile the board with no dead gap", function()
  for _, mode in ipairs(wheel.MODES) do
    local list = board.targets(14, mode)
    for _, target in ipairs(list) do
      t.truthy(target.x >= 1 and target.x + target.w - 1 <= AREA_RIGHT, mode .. " " .. target.value .. " runs off the side")
      t.truthy(target.y >= 14 and target.y + target.h - 1 <= AREA_BOTTOM, mode .. " " .. target.value .. " runs off the bottom")
      t.truthy(wheel.spot(target.value) ~= nil, "a target on a bet that does not exist")
    end
    for y = 14, 28 do
      -- As on Games/Roulette, a line cannot take in the zero, so in that mode the zero is the one part with nothing under it
      for x = mode == "line" and 9 or 2, 76 do
        local hit = false
        for _, target in ipairs(list) do
          hit = hit or (x >= target.x and x < target.x + target.w and y >= target.y and y < target.y + target.h)
        end
        t.truthy(hit, mode .. " has a dead gap at " .. x .. "," .. y)
      end
    end
    t.breathe()
  end
end)

t.test("a tap on a number's cell in straight mode is that number, and a tab is that mode", function()
  local list = board.targets(14, "straight")
  local function at(x, y)
    for i = #list, 1, -1 do
      local b = list[i]
      if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b.value end
    end
    return nil
  end
  t.eq(at(9, 24), "straight:1", "bottom left")
  t.eq(at(9, 14), "straight:3", "top left")
  t.eq(at(66, 14), "straight:36", "top right")
  t.eq(at(4, 20), "straight:0", "the zero")
  t.eq(at(70, 15), "column:3", "2:1 by the top row")
  t.eq(at(9, 29), "dozen:1", "the first dozen")
  t.eq(at(9, 32), "low", "1-18")
end)

t.test("no two inside bets share a mark", function()
  local seen = {}
  for _, spot in ipairs(wheel.SPOTS) do
    if spot.kind == "split" or spot.kind == "street" or spot.kind == "corner" or spot.kind == "line" then
      local x, y = board.markSpot(spot.id)
      local key = x .. "," .. y
      t.truthy(not seen[key], spot.id .. " sits on " .. tostring(seen[key]))
      seen[key] = spot.id
      seen[(x + 1) .. "," .. y] = spot.id
    end
  end
end)

--- A canvas that only records what would fall outside it, or outside the part a view has.
local function recorder(w, h, bottom)
  local bad = {}
  local c = { w = w, h = h }
  local function note(what, x, y, width, height)
    if x < 1 or y < 1 or x + width - 1 > w or y + height - 1 > bottom then
      bad[#bad + 1] = ("%s at %d,%d size %dx%d"):format(what, x, y, width, height)
    end
  end
  function c:rect(x, y, width, height) note("rect", x, y, width, height) end
  function c:frame(x, y, width, height) note("frame", x, y, width, height) end
  function c:text(x, y, str) note("text '" .. tostring(str) .. "'", x, y, #tostring(str), 1) end
  function c:textCenter(cx, y, str) self:text(cx - math.floor(#tostring(str) / 2), y, str) end
  function c:bigWidth(str, scale) return #tostring(str) * 6 * (scale or 1) end
  function c:big(x, y, str, _, scale) note("big '" .. tostring(str) .. "'", x, y, self:bigWidth(str, scale), 6 * (scale or 1)) end
  function c:bigCenter(cx, y, str, color, scale) self:big(cx - math.floor(self:bigWidth(str, scale) / 2), y, str, color, scale) end
  return c, bad
end

local function seatState(mode)
  local names = {}
  for i = 1, 8 do names[i] = { seat = i, name = "AVeryLongPlayerNameOfSixteen" .. i, bet = 1000 } end
  local state = rules.new(names, 1, fixed(0), { recent = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } })
  for _, spot in ipairs(wheel.SPOTS) do
    state.players[1].spots[spot.id] = 1
  end
  state.players[1].budget = 100000
  state.players[1].mode = mode
  state.players[1].lit = "line:31-32-33-34-35-36"
  for i = 2, 8 do state.players[i].spots.red = 999 end
  return state
end

t.test("the seat's picture stays inside its area in every phase, with every spot covered", function()
  for _, mode in ipairs(wheel.MODES) do
    local state = seatState(mode)
    local function check(view, anim, what)
      local c, bad = recorder(78, 52, AREA_BOTTOM)
      seatView.draw(c, view, anim, { seat = 1, name = "A" })
      t.eq(table.concat(bad, "; "), "", what)
    end
    check(rules.viewFor(state, 1), nil, "betting")
    check(rules.viewFor(state, nil), nil, "watching")
    rules.act(state, 1, "done")
    check(rules.viewFor(state, 1), nil, "done")
    for i = 2, 8 do rules.act(state, i, "done") end
    rules.act(state, nil, "spin", nil, fixed(0))
    for _, t0 in ipairs({ 0, 0.3, 0.9, 1 }) do
      check(rules.viewFor(state, 1), { ev = { type = "spin" }, t = t0 }, "spinning")
    end
    check(rules.viewFor(state, 1), { ev = { type = "landed" }, t = 0.5 }, "landed")
    check(rules.viewFor(state, 1), nil, "the end")
    check(rules.viewFor(state, nil), nil, "a watcher at the end")
  end
end)

t.test("the running numbers end on the number that came up", function()
  local state = open({ 1 }, 100)
  spin(state, 19)
  local shown
  local c = recorder(78, 52, 52)
  function c:bigCenter(_, _, str) shown = str end
  seatView.draw(c, rules.viewFor(state, 1), { ev = { type = "spin" }, t = 1 }, {})
  t.eq(shown, "19", "the last number shown")
end)

t.test("a spin gives nothing away on the seat until the ball stops", function()
  local state = open({ 1 }, 100)
  rules.act(state, 1, "spot", "straight:19")
  spin(state, 19)
  local words = {}
  local c = recorder(78, 52, 52)
  function c:text(_, _, str) words[#words + 1] = tostring(str) end
  function c:textCenter(_, _, str) words[#words + 1] = tostring(str) end
  seatView.draw(c, rules.viewFor(state, 1), { ev = { type = "spin" }, t = 0.2 }, {})
  local all = table.concat(words, " ")
  t.truthy(not all:find("19 RED", 1, true), "not the number's name")
  t.truthy(not all:find("NET", 1, true), "no money")
end)

t.test("the wall's picture stays clear of the seats and the banner in every phase", function()
  local _, top, _, h = seatui.tableArea({ w = 121, h = 81 })
  local bottom = top + h - 1
  local state = seatState("straight")
  local info = { waiting = { [1] = true, [2] = true }, seats = {} }
  local function check(view, anim, what)
    local c, bad = recorder(121, 81, bottom)
    tableView.draw(c, view, anim, info)
    t.eq(table.concat(bad, "; "), "", what)
  end
  check(rules.viewFor(state, nil), nil, "betting")
  for i = 1, 8 do rules.act(state, i, "done") end
  info.waiting = {}
  check(rules.viewFor(state, nil), nil, "closed")
  rules.act(state, nil, "spin", nil, fixed(36))
  for _, t0 in ipairs({ 0, 0.2, 0.5, 0.7, 0.9, 1 }) do
    check(rules.viewFor(state, nil), { ev = { type = "spin" }, t = t0 }, "the spin")
  end
  check(rules.viewFor(state, nil), { ev = { type = "landed" }, t = 0.5 }, "landed")
  check(rules.viewFor(state, nil), nil, "the end")
end)

t.test("the wheel keeps above the result banner", function()
  local _, top, _, h = seatui.tableArea({ w = 121, h = 81 })
  local lowest = 0
  local c = recorder(121, 81, 81)
  function c:rect(_, y, _, height) lowest = math.max(lowest, y + height - 1) end
  function c:text() end
  function c:textCenter() end
  function c:bigCenter() end
  function c:frame() end
  local state = open({ 1 }, 100)
  tableView.draw(c, rules.viewFor(state, nil), nil, { waiting = {} })
  t.truthy(lowest < top + h - 15, "the lowest row drawn is " .. lowest)
end)

t.test("the plugin says what the engine needs", function()
  t.eq(plugin.id, "roulette", "id")
  t.eq(plugin.kind, "house", "kind")
  t.eq(plugin.minSeats, 1, "one seat can play")
  t.eq(plugin.maxSeats, 8, "eight can")
  t.truthy(plugin.turnMs + 1000 < 30000, "a player who bet and waited is still inside the bank's touch window")
  t.truthy(plugin.spots == nil, "bets go on this game's own layout")
  local lines = plugin.help()
  t.truthy(#lines > 10, "help")
  local all = {}
  for _, line in ipairs(lines) do all[#all + 1] = type(line) == "table" and line[1] or line end
  t.truthy(table.concat(all, " "):find("97.30", 1, true) ~= nil, "the help states the return")
  for _, kind in ipairs({ "spin", "landed", "payout", "open", "bet", "seat" }) do
    t.truthy(plugin.event({ type = kind }) > 0, kind .. " takes time")
  end
  t.truthy(plugin.event({ type = "bet" }) < 0.1, "a bet holds nothing up")
end)
