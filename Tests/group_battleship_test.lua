-- group_battleship_test.lua
-- Battleship for a stake, on Duel. kit.fuzz holds it to the whole contract. The rest is what that cannot know: the rules of the game,
-- that a view never says where a ship is, and that every way a match can end is a whole stake one way or nothing at all.

local canvas = require("lib.casino.canvas")
local kit = require("group_kit")
local testing = require("testing")

local plugin = kit.plugin("Duel", "battleship")
local rules = plugin.rules
local SIZE = rules.SIZE

local function entries(stake, seats)
  seats = seats or { 1, 2 }
  return {
    { seat = seats[1], name = "Alice", stack = 5000, stake = stake or 100 },
    { seat = seats[2], name = "Bob", stack = 3000, stake = stake or 100 },
  }
end

local function start(stake, seats, button)
  return (rules.new(entries(stake, seats), button or 1, testing.fastRng(9), {}))
end

--- Each ship in a row of its own, from the left edge: rows 1, 3, 5, 7, 9. row shifts them all down one.
local function placeInRows(state, seat, rng, shift)
  if rules.actions(state, seat)[1].label ~= "ACROSS" then rules.act(state, seat, "rotate", nil, rng) end
  for n = 1, 5 do
    local events = rules.act(state, seat, "place", rules.cell(1, n * 2 - 1 + (shift or 0)), rng)
    testing.truthy(#events > 0, "ship " .. n .. " placed")
  end
end

--- Both fleets down in rows, so the shooting has started.
local function battle(stake, seats)
  local state = start(stake, seats)
  local rng = testing.fastRng(3)
  placeInRows(state, state.players[1].seat, rng)
  placeInRows(state, state.players[2].seat, rng)
  return state, rng
end

local function player(state, seat)
  for _, p in ipairs(state.players) do
    if p.seat == seat then return p end
  end
end

--- Whether two views are the same but for the seals, which do depend on the fleet.
local function sameButSeals(a, b)
  a, b = kit.plain(a), kit.plain(b)
  for _, view in ipairs({ a, b }) do
    for _, p in ipairs(view.players) do p.seal = nil end
  end
  return kit.same(a, b)
end

--- Only these may be in a view while a match is on.
local PUBLIC = { seat = 1, name = 1, placed = 1, ready = 1, late = 1, sunk = 1, lost = 1, shots = 1, last = 1, seal = 1 }

local function checkView(state, seat)
  local view = rules.viewFor(state, seat)
  for _, p in ipairs(view.players) do
    for key in pairs(p) do testing.truthy(PUBLIC[key], "a player's view holds " .. tostring(key)) end
  end
  if seat then
    testing.truthy(view.you ~= nil, "a player sees their own water")
    testing.truthy(kit.same(view.you.grid, player(state, seat).grid), "and it is really theirs")
  else
    testing.truthy(view.you == nil, "nobody's water is public")
  end
  -- Every square marked on a shots grid was fired at, and nothing in it says what lies under an unfired one
  for _, p in ipairs(state.players) do
    local shown
    for _, q in ipairs(view.players) do
      if q.seat == p.seat then shown = q.shots end
    end
    testing.truthy(kit.same(shown, p.shots), "shots are as they are")
  end
end

local function fuzzPick(state, seat, actions, rng)
  local p = player(state, seat)
  if p.confirm then return actions[rng:below(#actions) + 1].id end
  local roll = rng:below(100)
  if state.phase == "setup" then
    if roll < 3 then return "concede" end
    if roll < 15 then return "undo" end
    if roll < 25 then return "rotate" end
    if roll < 35 then return "random" end
    return "place", rng:below(SIZE * SIZE) + 1
  end
  if roll < 2 then return "concede" end
  if roll < 10 then return "lucky" end
  -- A shot at a square not yet tried
  for _ = 1, 400 do
    local value = rng:below(SIZE * SIZE) + 1
    local x, y = rules.square(value)
    if p.shots[y][x] == 0 then return "fire", value end
  end
  return "lucky"
end

-- "place" can land on a ship and "undo" can be out of turn, which do nothing, and kit.fuzz takes that as a broken button. This one
-- only asks for what will really work.
local function legalPick(state, seat, actions, rng)
  for _ = 1, 40 do
    local id, value = fuzzPick(state, seat, actions, rng)
    local trial = kit.plain(state)
    local moved = rules.act(trial, seat, id, value, testing.fastRng(1))
    if moved and #moved > 0 then return id, value end
  end
  return "concede"
end

testing.test("battleship keeps the contract", function()
  kit.fuzz(plugin, { rounds = 120, seats = { 2 }, stack = 500, stake = 100, pick = legalPick, absent = 2, check = function(state)
    checkView(state, 1)
    checkView(state, 2)
    checkView(state, nil)
  end })
end)

testing.test("a tiny stack or a stake past it stays inside the stack", function()
  kit.fuzz(plugin, { rounds = 30, seats = { 2 }, stack = 40, stake = 250, pick = legalPick, absent = 5 })
end)

testing.test("2500 random matches: every one is a whole stake one way or nothing", function()
  local rng = testing.fastRng(2026)
  local ends = { fleet = 0, timeout = 0, concede = 0, void = 0 }
  for round = 1, 2500 do
    local stakes = plugin.stakes
    local stake = stakes[rng:below(#stakes) + 1]
    local list = entries(stake)
    list[1].stack, list[2].stack = 25 + rng:below(1000), 25 + rng:below(1000)
    local state = rules.new(kit.plain(list), rng:below(2) + 1, rng, {})
    local style = rng:below(4)
    local steps = 0
    while not rules.done(state) do
      steps = steps + 1
      if steps > 4000 then error("a match did not end") end
      local waiting = rules.waitingOn(state)
      local seat = waiting[rng:below(#waiting) + 1]
      local roll = rng:below(1000)
      if style == 0 and roll < 8 then
        rules.act(state, seat, rules.auto(state, seat), nil, rng)
      elseif style == 1 and roll < 8 then
        if #rules.act(state, seat, "concede", nil, rng) > 0 then rules.act(state, seat, "concede_yes", nil, rng) end
      elseif style == 2 and state.phase == "setup" then
        rules.act(state, seat, rules.auto(state, seat), nil, rng)
      elseif state.phase == "setup" then
        rules.act(state, seat, "random", nil, rng)
      else
        rules.act(state, seat, "lucky", nil, rng)
      end
    end
    ends[state.how] = ends[state.how] + 1
    local nets = kit.checkEnd(plugin, state, list)
    testing.eq(nets[1] + nets[2], 0, "nets add up")
    local size = math.abs(nets[1])
    if state.how == "void" then
      testing.eq(size, 0, "nobody came, nothing moves")
    else
      testing.eq(size, math.min(stake, list[1].stack, list[2].stack), "the whole stake moves")
      testing.truthy(state.winner ~= 0, "somebody won")
      testing.truthy(nets[state.players[state.winner].seat] > 0, "and it was the winner who got it")
    end
    if round % 100 == 0 then testing.breathe() end
  end
  for how, count in pairs(ends) do testing.truthy(count > 0, how .. " matches happened") end
end)

testing.test("ships go where they are tapped, slide back onto the water, and cannot overlap", function()
  local state = start()
  local rng = testing.fastRng(1)
  local alice = state.players[1]
  testing.truthy(#rules.act(state, 1, "place", rules.cell(9, 3), rng) > 0, "a carrier off the right edge slides back")
  testing.eq(alice.fleet[1].x, 6, "to the last place it fits")
  testing.eq(alice.grid[3][10], 1, "and reaches the edge")
  local before = kit.plain(state)
  testing.eq(#rules.act(state, 1, "place", rules.cell(7, 3), rng), 0, "on the carrier")
  testing.truthy(kit.same(before, state), "changes nothing")
  rules.act(state, 1, "rotate", nil, rng)
  rules.act(state, 1, "place", rules.cell(1, 10), rng)
  testing.eq(alice.fleet[2].y, 7, "a ship running down slides up")
  testing.eq(alice.grid[10][1], 2, "and reaches the bottom")
end)

testing.test("undo takes back the last ship, and a whole fleet is final", function()
  local state = start()
  local rng = testing.fastRng(1)
  testing.eq(#rules.act(state, 1, "undo", nil, rng), 0, "nothing to take back")
  rules.act(state, 1, "place", rules.cell(1, 1), rng)
  rules.act(state, 1, "place", rules.cell(1, 2), rng)
  testing.truthy(#rules.act(state, 1, "undo", nil, rng) > 0, "undo")
  testing.eq(state.players[1].placed, 1, "one left")
  testing.eq(state.players[1].grid[2][1], 0, "the square is free")
  testing.eq(state.players[1].grid[1][1], 1, "the first ship stayed")
  rules.act(state, 2, "random", nil, rng)
  testing.truthy(state.players[2].ready, "Bob is ready")
  testing.eq(state.phase, "setup", "the shooting waits for both")
  testing.eq(#rules.act(state, 2, "undo", nil, rng), 0, "a finished fleet stays")
  testing.truthy(kit.same(rules.waitingOn(state), { 1 }), "only Alice is waited on")
end)

testing.test("both players place at once, and the button shoots first", function()
  local state = start(100, { 1, 2 }, 2)
  testing.truthy(kit.same(rules.waitingOn(state), { 1, 2 }), "both are waited on")
  local rng = testing.fastRng(1)
  rules.act(state, 1, "random", nil, rng)
  rules.act(state, 2, "random", nil, rng)
  testing.eq(state.phase, "fire", "shooting")
  testing.truthy(kit.same(rules.waitingOn(state), { 2 }), "Bob first")
  testing.eq(#rules.actions(state, 1), 0, "Alice has nothing to press")
end)

testing.test("hits, sinking and the win, with seats that are not 1 and 2", function()
  local state, rng = battle(250, { 2, 7 })
  local events = rules.act(state, 2, "fire", rules.cell(10, 1), rng)
  testing.eq(events[1].hit, false, "water")
  testing.eq(state.players[1].shots[1][10], rules.MISS, "marked a miss")
  testing.eq(#rules.act(state, 2, "fire", rules.cell(1, 1), rng), 0, "not your turn twice")
  local hit = rules.act(state, 7, "fire", rules.cell(1, 1), rng)
  testing.eq(hit[1].hit, true, "a hit")
  testing.eq(#rules.act(state, 2, "fire", rules.cell(10, 1), rng), 0, "the same square twice")
  rules.act(state, 2, "fire", rules.cell(9, 1), rng)

  -- Bob sinks everything, with Alice shooting at empty water in between
  local wasted = { 2 }
  local lens = { 5, 4, 3, 3, 2 }
  for n, len in ipairs(lens) do
    for x = 1, len do
      if not (n == 1 and x == 1) then
        local last = n == 5 and x == len
        local shot = rules.act(state, 7, "fire", rules.cell(x, n * 2 - 1), rng)
        testing.eq(shot[1].hit, true, "ship " .. n .. " hit")
        if x == len then testing.eq(shot[1].sunk, rules.SHIPS[n].name, "ship " .. n .. " sank") end
        if not last then
          wasted[1] = wasted[1] + 1
          rules.act(state, 2, "fire", rules.cell((wasted[1] % 10) + 1, 2 + 2 * math.floor(wasted[1] / 10)), rng)
        end
      end
    end
  end
  testing.truthy(rules.done(state), "over")
  testing.eq(state.how, "fleet", "by sinking")
  testing.eq(state.players[2].shots[1][1], rules.SUNK, "a sunk ship is marked")
  local nets = rules.nets(state)
  testing.eq(nets[7], 250, "Bob won the stake")
  testing.eq(nets[2], -250, "Alice lost it")
  testing.eq(rules.result(state, 7).kind, "win", "Bob is told")
  testing.eq(rules.result(state, 2).kind, "lose", "Alice is told")
  testing.eq(rules.risk(state, 2), 250, "the stake was at risk")
  testing.eq(#rules.act(state, 7, "fire", rules.cell(9, 9), rng), 0, "nothing after the end")
end)

testing.test("running out of time on a shot forfeits the stake", function()
  local state, rng = battle(50)
  local seat = rules.waitingOn(state)[1]
  rules.act(state, seat, rules.auto(state, seat), nil, rng)
  testing.truthy(rules.done(state), "over")
  testing.eq(state.how, "timeout", "by the clock")
  testing.eq(rules.nets(state)[seat], -50, "the missing player pays")
  testing.eq(rules.nets(state)[3 - seat], 50, "the one who stayed is paid")
  testing.truthy(rules.result(state, nil).detail:find("ran out of time"), "the table is told")
end)

testing.test("running out of time while placing loses to a player who finishes, and to one already finished", function()
  local rng = testing.fastRng(1)
  local state = start(100)
  rules.act(state, 2, "random", nil, rng)
  rules.act(state, 1, rules.auto(state, 1), nil, rng)
  testing.truthy(rules.done(state), "Bob had finished")
  testing.eq(rules.nets(state)[1], -100, "Alice pays")

  state = start(100)
  rules.act(state, 1, rules.auto(state, 1), nil, rng)
  testing.truthy(not rules.done(state), "Bob may still finish")
  testing.truthy(kit.same(rules.waitingOn(state), { 2 }), "only Bob is waited on")
  testing.eq(#rules.actions(state, 1), 0, "Alice can do nothing now")
  testing.eq(#rules.act(state, 1, "random", nil, rng), 0, "and nothing she tries counts")
  rules.act(state, 2, "random", nil, rng)
  testing.truthy(rules.done(state), "Bob finished")
  testing.eq(rules.nets(state)[2], 100, "Bob wins")
end)

testing.test("if neither player places a fleet in time, nothing moves", function()
  local rng = testing.fastRng(1)
  local state = start(500)
  rules.act(state, 1, rules.auto(state, 1), nil, rng)
  rules.act(state, 2, rules.auto(state, 2), nil, rng)
  testing.truthy(rules.done(state), "over")
  testing.eq(state.how, "void", "void")
  testing.eq(rules.nets(state)[1], 0, "Alice owes nothing")
  testing.eq(rules.nets(state)[2], 0, "Bob owes nothing")
  testing.eq(rules.result(state, 1).kind, "push", "a push")
  testing.eq(rules.risk(state, 1), 500, "the risk stands")
end)

testing.test("giving up asks first", function()
  local state, rng = battle(100)
  local seat = rules.waitingOn(state)[1]
  testing.eq(#rules.act(state, seat, "concede_yes", nil, rng), 0, "not without asking")
  rules.act(state, seat, "concede", nil, rng)
  testing.truthy(not rules.done(state), "one press is not enough")
  testing.eq(rules.actions(state, seat)[1].id, "keep", "the safe button is first")
  testing.eq(#rules.act(state, seat, "fire", rules.cell(10, 10), rng), 0, "no shots while asked")
  rules.act(state, seat, "keep", nil, rng)
  testing.eq(rules.actions(state, seat)[1].id, "lucky", "back to shooting")
  rules.act(state, seat, "concede", nil, rng)
  rules.act(state, seat, "concede_yes", nil, rng)
  testing.truthy(rules.done(state), "given up")
  testing.eq(rules.nets(state)[seat], -100, "and it costs the stake")
end)

testing.test("illegal input does nothing", function()
  local rng = testing.fastRng(1)
  local junk = { 0, 101, -1, 1.5, "5", true, {}, 1e300 }
  local function refuses(state, seat, id, value, what)
    local before = kit.plain(state)
    local events = rules.act(state, seat, id, value, rng)
    testing.truthy(not events or #events == 0, what .. " returned events")
    testing.truthy(kit.same(before, state), what .. " changed the state")
  end
  local state = start()
  for _, value in ipairs(junk) do refuses(state, 1, "place", value, "placing on junk") end
  refuses(state, 1, "place", nil, "placing nowhere")
  refuses(state, 1, "fire", 5, "firing while placing")
  refuses(state, 1, "lucky", nil, "a lucky shot while placing")
  refuses(state, 1, "keep", nil, "keep with nothing asked")
  refuses(state, 1, "concede_yes", nil, "giving up with nothing asked")
  refuses(state, 3, "random", nil, "a seat not in the match")
  refuses(state, nil, "random", nil, "no seat")
  refuses(state, 1, 42, nil, "an id that is no string")
  refuses(state, 1, nil, nil, "no id")

  state, rng = battle()
  local seat = rules.waitingOn(state)[1]
  for _, value in ipairs(junk) do refuses(state, seat, "fire", value, "firing at junk") end
  refuses(state, seat, "fire", nil, "firing nowhere")
  refuses(state, 3 - seat, "fire", 50, "firing out of turn")
  refuses(state, 3 - seat, "lucky", nil, "a lucky shot out of turn")
  refuses(state, 3 - seat, "timeout", nil, "the wrong seat's clock")
  refuses(state, 3 - seat, "concede", nil, "giving up out of turn")
  refuses(state, seat, "place", 50, "placing while shooting")
  refuses(state, seat, "rotate", nil, "turning a ship while shooting")
  refuses(state, seat, "undo", nil, "undo while shooting")
  rules.act(state, seat, "timeout", nil, rng)
  refuses(state, seat, "fire", 50, "firing after the end")
  refuses(state, seat, "timeout", nil, "the clock after the end")
  refuses(state, nil, "lucky", nil, "the computer after the end")
end)

testing.test("a view never says where the other fleet is", function()
  -- The same match with Bob's ships in other rows: all Alice is shown must be the same, shot for shot
  local a, rngA = battle(100)
  local b = start(100)
  local rngB = testing.fastRng(3)
  placeInRows(b, 1, rngB)
  placeInRows(b, 2, rngB, 1)
  testing.truthy(sameButSeals(rules.viewFor(a, 1), rules.viewFor(b, 1)), "Alice cannot tell Bob's fleets apart")
  testing.truthy(not sameButSeals(rules.viewFor(a, 2), rules.viewFor(b, 2)), "while Bob can, so this test can fail")

  -- Column 10 is empty in both, so these shots miss either way
  for y = 1, 10 do
    local turn = rules.waitingOn(a)[1]
    rules.act(a, turn, "fire", rules.cell(10, y), rngA)
    rules.act(b, turn, "fire", rules.cell(10, y), rngB)
    testing.truthy(sameButSeals(rules.viewFor(a, 1), rules.viewFor(b, 1)), "Alice cannot tell them apart at step " .. y)
    testing.truthy(sameButSeals(rules.viewFor(a, nil), rules.viewFor(b, nil)), "nor can anyone watching")
  end

  -- While placing, where a ship went is no different from another square, and only the count shows
  local c, d = start(100), start(100)
  rules.act(c, 2, "place", rules.cell(1, 1), testing.fastRng(1))
  rules.act(d, 2, "place", rules.cell(4, 4), testing.fastRng(1))
  testing.truthy(kit.same(rules.viewFor(c, 1), rules.viewFor(d, 1)), "Bob's first ship cannot be seen")
  testing.truthy(kit.same(rules.viewFor(c, nil), rules.viewFor(d, nil)), "by anyone")
end)

testing.test("no event says where a ship is, and the seal is what it claims", function()
  local state = start()
  local rng = testing.fastRng(5)
  local events = {}
  local function keep(list)
    for _, ev in ipairs(list) do events[#events + 1] = ev end
  end
  keep(rules.act(state, 1, "place", rules.cell(3, 3), rng))
  keep(rules.act(state, 1, "rotate", nil, rng))
  keep(rules.act(state, 1, "random", nil, rng))
  keep(rules.act(state, 2, "random", nil, rng))
  for _, ev in ipairs(events) do
    testing.truthy(ev.x == nil and ev.y == nil and ev.value == nil, ev.type .. " says where")
  end
  local view = rules.viewFor(state, 2)
  for _, p in ipairs(view.players) do testing.truthy(p.proof == nil and p.salt == nil, "no salt before the end") end
  testing.eq(#view.players[1].seal, 10, "the seal is up")
  while not rules.done(state) do
    rules.act(state, rules.waitingOn(state)[1], "lucky", nil, rng)
  end
  local hash = require("lib.casino.rng")
  local final = rules.viewFor(state, nil)
  for _, p in ipairs(final.players) do
    testing.truthy(p.grid ~= nil, "the end shows both fleets")
    testing.eq(hash.sha256(p.proof):sub(1, 10), p.seal, "and the seal matches")
  end
end)

testing.test("a covered wall draws and offers nothing private", function()
  local state, rng = battle()
  rules.act(state, 1, "fire", rules.cell(1, 1), rng)
  local public = rules.viewFor(state, nil)
  testing.truthy(public.you == nil, "no private fields")
  testing.eq(#plugin.seatView.regions(public), 0, "no squares to tap")
  local seat = rules.waitingOn(state)[1]
  testing.eq(#plugin.seatView.regions(rules.viewFor(state, seat)), 99 + (seat == 1 and 0 or 1), "the turn's player has every open square")
  testing.eq(#plugin.seatView.regions(rules.viewFor(state, 3 - seat)), 0, "the other has none")
end)

testing.test("every picture draws, inside the wall, at every stage", function()
  local rng = testing.fastRng(4)
  local function drawAll(state, anim)
    for _, seat in ipairs({ 1, 2, false }) do
      local view = kit.plain(rules.viewFor(state, seat or nil))
      local c = canvas.new(nil, 121, 81)
      plugin.seatView.draw(c, view, anim, { seat = seat or nil, name = "Alice" })
      for _, region in ipairs(plugin.seatView.regions(view)) do
        testing.truthy(region.x >= 1 and region.x + region.w - 1 <= 121 and region.y >= 10 and region.y + region.h - 1 <= 67, "a square in the game's area")
      end
      plugin.tableView.draw(c, view, anim)
    end
  end
  local state = start()
  drawAll(state)
  rules.act(state, 1, "place", 11, rng)
  rules.act(state, 1, "rotate", nil, rng)
  drawAll(state)
  rules.act(state, 1, "concede", nil, rng)
  drawAll(state)
  rules.act(state, 1, "keep", nil, rng)
  rules.act(state, 1, "random", nil, rng)
  drawAll(state)
  rules.act(state, 2, "random", nil, rng)
  while not rules.done(state) do
    local events = rules.act(state, rules.waitingOn(state)[1], "lucky", nil, rng)
    drawAll(state, { ev = events[1], t = 0.3 })
  end
  drawAll(state)
  local void = start()
  rules.act(void, 1, "timeout", nil, rng)
  drawAll(void)
  rules.act(void, 2, "timeout", nil, rng)
  drawAll(void)
end)

testing.test("states and views survive being written down", function()
  local rng = testing.fastRng(8)
  local state = start()
  rules.act(state, 1, "random", nil, rng)
  rules.act(state, 2, "random", nil, rng)
  for _ = 1, 30 do rules.act(state, rules.waitingOn(state)[1], "lucky", nil, rng) end
  local list = { state, rules.viewFor(state, 1), rules.viewFor(state, 2), rules.viewFor(state, nil) }
  for _, value in ipairs(list) do
    kit.plain(value)
    if textutils then
      testing.truthy(kit.same(value, textutils.unserialize(textutils.serialize(value))), "comes back the same")
    end
  end
  -- A reboot lands here, so a state read back must play on
  local back = kit.plain(state)
  rules.act(back, rules.waitingOn(back)[1], "lucky", nil, rng)
  testing.eq(back.moves, 31, "a state read back plays on")
end)

testing.test("the plugin is what the engine wants", function()
  testing.eq(plugin.id, "battleship", "id")
  testing.eq(plugin.kind, "players", "kind")
  testing.eq(plugin.minSeats, 2, "two seats")
  testing.eq(plugin.maxSeats, 2, "two seats")
  testing.truthy(#plugin.stakes > 0 and plugin.tableView and plugin.seatView and plugin.help(), "whole")
  for _, line in ipairs(plugin.help()) do
    testing.truthy(type(line) == "string" or type(line[1]) == "string", "a help line")
  end
  testing.eq((plugin.event({ type = "shot", hit = true })), 0.6, "a shot has a length")
  testing.truthy(plugin.event({ type = "nothing we know" }) > 0, "and so does anything else")
end)
