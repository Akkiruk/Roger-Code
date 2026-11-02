-- group_backgammon_test.lua
-- Backgammon on Duel: the hard rules of a move, the cube, what a game pays, the clock, and that no view can tell the next roll.
-- A brute force written apart from the rules checks what they call legal, all the way through random games.

local kit = require("group_kit")
local testing = require("testing")
local eq, test, truthy = testing.eq, testing.test, testing.truthy

local plugin = kit.plugin("Duel", "backgammon")
local rules = plugin.rules

local function entries(stake, stackA, stackB)
  return { { seat = 1, name = "Ann", stack = stackA or 1000, stake = stake or 100 }, { seat = 2, name = "Bea", stack = stackB or 1000, stake = stake or 100 } }
end

--- An rng that gives these dice in turn.
local function dice(...)
  local list, at = { ... }, 0
  return { below = function(_, n)
    at = at + 1
    eq(n, 6, "dice have six faces")
    truthy(list[at], "more dice were asked for than the test gave")
    return list[at] - 1
  end }
end

local function fresh(stake, stackA, stackB, rng)
  local state = rules.new(entries(stake, stackA, stackB), 1, rng or dice(6, 1), {})
  return state
end

--- Put a side's checkers down: a map of point to count, in that side's own numbering. Whatever is not placed is borne off.
local function setSide(player, map, bar)
  local used = bar or 0
  for point = 1, rules.POINTS do
    player.points[point] = map[point] or 0
    used = used + player.points[point]
  end
  player.bar, player.off = bar or 0, rules.CHECKERS - used
end

--- A game at this position with Ann to roll.
local function position(mine, theirs, barMine, barTheirs, stake, stackA, stackB)
  local state = fresh(stake, stackA, stackB)
  setSide(state.players[1], mine, barMine)
  setSide(state.players[2], theirs, barTheirs)
  state.turn, state.phase, state.dice, state.left, state.played, state.legal, state.draft = 1, "roll", nil, nil, nil, nil, nil
  return state
end

--- The same, with Ann's dice rolled.
local function rolled(a, b, mine, theirs, barMine, barTheirs)
  local state = position(mine, theirs, barMine, barTheirs)
  truthy(#rules.act(state, 1, "roll", nil, dice(a, b)) > 0, "rolled")
  return state
end

--- Moves as text, sorted, so a test can say the whole list.
local function legalText(state)
  local list = {}
  for _, move in ipairs(state.legal or {}) do list[#list + 1] = move.from .. ">" .. move.to .. ":" .. move.die end
  table.sort(list)
  return table.concat(list, " ")
end

--- Play a checker the way a player does: a tap on its point, a tap on where it goes.
local function move(state, seat, from, to)
  truthy(#rules.act(state, seat, "from", from) > 0, "picked up " .. from)
  truthy(#rules.act(state, seat, "to", to) > 0, "moved to " .. to)
end

local function ids(list)
  local out = {}
  for _, action in ipairs(list) do out[action.id] = action end
  return out
end

--- A random move for kit, by the same taps a player has.
local function tapper(state, seat, _, rng)
  if state.phase ~= "move" then return nil end
  local view = rules.viewFor(state, seat)
  if view.targets and rng:below(10) > 0 then return "to", view.targets[rng:below(#view.targets) + 1] end
  if view.sources and #view.sources > 0 then return "from", view.sources[rng:below(#view.sources) + 1] end
  return nil
end

--- The same, but it never doubles and always takes, so games run their whole length.
local function longTapper(state, seat, actions, rng)
  if state.phase == "roll" then return "roll" end
  if state.phase == "double" then return "take" end
  return tapper(state, seat, actions, rng)
end

--- A game runs to hundreds of steps, and a computer must yield inside one. Wraps a check for kit so it does.
local function breathing(check)
  local steps = 0
  return function(state, list)
    steps = steps + 1
    if steps % 100 == 0 then testing.breathe() end
    if check then check(state, list) end
  end
end

--- Whole, in range and every checker there.
local function sane(state)
  for _, player in ipairs(state.players) do
    local sum = player.bar + player.off
    for point = 1, rules.POINTS do
      local count = player.points[point]
      truthy(count >= 0 and count == math.floor(count), "a count on point " .. point)
      sum = sum + count
    end
    eq(sum, rules.CHECKERS, "fifteen checkers")
    truthy(player.bar >= 0 and player.off >= 0, "bar and off")
  end
  local first, second = state.players[1], state.players[2]
  for point = 1, rules.POINTS do
    truthy(first.points[point] == 0 or second.points[25 - point] == 0, "two colours on point " .. point)
  end
end

-- ------------------------------------------------------------------ a brute force, sharing no code with the rules

local function cloneSide(side)
  local copy = { bar = side.bar, off = side.off, points = {} }
  for point = 1, 24 do copy.points[point] = side.points[point] end
  return copy
end

--- Every single-die step from here, by reading the rules of the game straight.
local function plainSteps(mine, theirs, die)
  local steps = {}
  local sources = {}
  if mine.bar > 0 then
    sources[1] = 25
  else
    for point = 24, 1, -1 do
      if mine.points[point] > 0 then sources[#sources + 1] = point end
    end
  end
  local outside = mine.bar
  for point = 7, 24 do outside = outside + mine.points[point] end
  local top = 0
  for point = 1, 24 do
    if mine.points[point] > 0 then top = point end
  end
  for _, from in ipairs(sources) do
    local to = from - die
    if to > 0 then
      if theirs.points[25 - to] < 2 then steps[#steps + 1] = { from, to } end
    elseif outside == 0 and (to == 0 or from == top) then
      steps[#steps + 1] = { from, 0 }
    end
  end
  return steps
end

local function plainStep(mine, theirs, from, to)
  local a, b = cloneSide(mine), cloneSide(theirs)
  if from == 25 then a.bar = a.bar - 1 else a.points[from] = a.points[from] - 1 end
  if to == 0 then
    a.off = a.off + 1
  else
    a.points[to] = a.points[to] + 1
    if b.points[25 - to] == 1 then
      b.points[25 - to] = 0
      b.bar = b.bar + 1
    end
  end
  return a, b
end

--- Every whole play of the dice: lists of "from>to:die". A play stops when nothing else can move or the game is won.
local function plays(mine, theirs, left, sofar, out, total)
  local moved, seen = false, {}
  if mine.off < 15 then
    for index, die in ipairs(left) do
      if not seen[die] then
        seen[die] = true
        local rest = {}
        for position_, other in ipairs(left) do
          if position_ ~= index then rest[#rest + 1] = other end
        end
        for _, hop in ipairs(plainSteps(mine, theirs, die)) do
          moved = true
          local a, b = plainStep(mine, theirs, hop[1], hop[2])
          local path = {}
          for at, item in ipairs(sofar) do path[at] = item end
          path[#path + 1] = { hop[1], hop[2], die }
          plays(a, b, rest, path, out, total)
        end
      end
    end
  end
  if not moved then
    -- Winning with dice left over counts as a full play
    out[#out + 1] = { path = sofar, used = mine.off >= 15 and total or #sofar }
  end
end

--- The first moves of every play that uses as many dice as can be used, with the higher die if only one can be.
local function oracle(state)
  local mine, theirs = state.players[1], state.players[2]
  if mine.seat ~= state.turn then mine, theirs = theirs, mine end
  local out = {}
  plays(cloneSide(mine), cloneSide(theirs), state.left, {}, out, #state.left)
  local best = 0
  for _, entry in ipairs(out) do best = math.max(best, entry.used) end
  local high = 0
  if best == 1 and #state.left == 2 and state.left[1] ~= state.left[2] then
    for _, entry in ipairs(out) do high = math.max(high, entry.path[1][3]) end
  end
  local seen, list = {}, {}
  for _, entry in ipairs(out) do
    local first = entry.path[1]
    if entry.used == best and first and first[3] >= high then
      local text = first[1] .. ">" .. first[2] .. ":" .. first[3]
      if not seen[text] then
        seen[text] = true
        list[#list + 1] = text
      end
    end
  end
  table.sort(list)
  return table.concat(list, " ")
end

-- ------------------------------------------------------------------ the tests

test("the board starts right, and each side numbers it from its own end", function()
  local state = fresh()
  sane(state)
  for _, player in ipairs(state.players) do
    eq(player.points[24], 2, "the back two")
    eq(player.points[13], 5, "the mid point")
    eq(player.points[8], 3, "the eight")
    eq(player.points[6], 5, "the six")
    eq(rules.pips(player), 167, "pips")
  end
end)

test("the opening is one die each: the higher starts and plays both", function()
  local state = fresh(100, 1000, 1000, dice(2, 5))
  eq(state.turn, 2, "the higher die starts")
  eq(state.phase, "move", "no roll and no cube on the opening")
  eq(state.dice[1], 5, "both dice")
  eq(state.dice[2], 2, "both dice")
  eq(#state.left, 2, "both to play")
  eq(rules.waitingOn(state)[1], 2, "waiting on the starter")
  eq(state.ties, 0, "no ties")
  local view = rules.viewFor(state, nil)
  eq(view.opening[1].die, 2, "what Ann threw is on the wall")
  eq(view.opening[2].die, 5, "what Bea threw is on the wall")
end)

test("ties on the opening roll again, and never make a double", function()
  local state = fresh(100, 1000, 1000, dice(4, 4, 6, 6, 3, 1))
  eq(state.ties, 2, "two ties")
  eq(state.turn, 1, "Ann starts")
  eq(#state.dice, 2, "two dice, not four")
  eq(state.cube, 1, "no automatic double")
end)

test("the button plays no part in who starts", function()
  for button = 1, 2 do
    local state = rules.new(entries(), button, dice(6, 1), {})
    eq(state.turn, 1, "the dice say")
  end
end)

test("a move lands a die away, and a closed point stops it", function()
  local state = rolled(6, 1, { [24] = 2 }, { [6] = 2 })
  truthy(legalText(state):find("24>18:6", 1, true), "six from the back")
  truthy(legalText(state):find("24>23:1", 1, true), "one from the back")
  local closed = rolled(5, 2, { [24] = 2 }, { [6] = 2, [3] = 2 })
  -- 24-5 is 19, Bea's 6. 24-2 is 22, Bea's 3
  eq(legalText(closed), "", "both closed")
end)

test("a lone checker is hit and goes to the bar, and UNDO puts it back", function()
  local state = rolled(6, 5, { [24] = 2 }, { [7] = 1, [3] = 2 })
  move(state, 1, 24, 18)
  eq(state.players[2].points[7], 0, "Bea's blot is gone")
  eq(state.players[2].bar, 1, "it is on the bar")
  eq(state.played[1].hit, true, "the move says it hit")
  truthy(#rules.act(state, 1, "undo") > 0, "undo")
  eq(state.players[2].points[7], 1, "back")
  eq(state.players[2].bar, 0, "the bar is empty")
  eq(state.players[1].points[24], 2, "Ann's checker is back")
  eq(#state.left, 2, "the die is back")
  eq(state.left[1], 6, "dice stay high first")
  sane(state)
end)

test("a checker on the bar comes in first", function()
  local state = rolled(6, 1, { [13] = 3, [8] = 2 }, { [6] = 2 }, 2)
  -- Bar with a 6 lands on Ann's 19, Bea's 6: closed. With a 1, on 24
  eq(legalText(state), "25>24:1", "only the bar, only the open point")
  eq(#rules.act(state, 1, "from", 13), 0, "nothing else can be picked up")
  move(state, 1, rules.BAR, 24)
  eq(state.players[1].bar, 1, "one more on the bar")
  eq(state.turn, 2, "the six is closed, so the other cannot come in, nothing else may move and the turn ends")
end)

test("all closed against the bar means no move, and the turn passes by itself", function()
  local state = position({ [13] = 2 }, { [6] = 2, [5] = 2 }, 1)
  local events = rules.act(state, 1, "roll", nil, dice(6, 5))
  eq(events[2].type, "blocked", "the wall is told")
  eq(state.turn, 2, "Bea's turn")
  eq(state.phase, "roll", "she rolls")
  eq(#state.last.played, 0, "nothing was played")
  eq(state.last.dice[1], 6, "what was rolled stays on the wall")
end)

test("if only one die can be played it must be the higher", function()
  -- 20 can run 6 or 3, but 11 is closed, so either die stops the other. The ones cannot move
  local state = rolled(6, 3, { [20] = 1, [1] = 14 }, { [14] = 2 })
  eq(legalText(state), "20>14:6", "the six and nothing else")
end)

test("if the higher cannot be played the lower must be", function()
  local state = rolled(6, 3, { [20] = 1, [1] = 14 }, { [14] = 2, [11] = 2 })
  -- 14 of Ann's is Bea's 11, and 11 of Ann's is Bea's 14
  eq(legalText(state), "20>17:3", "the three")
  move(state, 1, 20, 17)
  eq(state.turn, 2, "the six stays unplayed and the turn ends")
  eq(#state.last.played, 1, "one die played")
end)

test("both dice must be used if any order does it", function()
  -- 10-6 lands on 4, and from there nothing can play the 1: the 3 is closed and so is the 19. So 10-6 first is out
  local state = rolled(6, 1, { [20] = 1, [10] = 1, [1] = 13 }, { [6] = 2, [22] = 2 })
  eq(legalText(state), "10>9:1 20>14:6", "only starts of a full play")
end)

test("only the order that fits can be played", function()
  -- 7-5 is closed, but 7-1 then 6-5 runs. Nothing else on the board moves, and the 5 first is not there
  local state = rolled(5, 1, { [7] = 1, [1] = 14 }, { [23] = 2 })
  eq(legalText(state), "7>6:1", "the one comes first")
  move(state, 1, 7, 6)
  eq(legalText(state), "6>1:5", "then the five")
end)

test("doubles play four, or as many as can move", function()
  local state = rolled(3, 3, { [24] = 2, [13] = 2 }, { [6] = 2 })
  eq(#state.dice, 4, "four dice")
  move(state, 1, 24, 21)
  move(state, 1, 21, 18)
  move(state, 1, 13, 10)
  eq(#state.left, 1, "one left")
  move(state, 1, 13, 10)
  eq(#state.last.played, 4, "four played")
  eq(state.turn, 2, "the last die ends the turn")

  -- The 12 can reach the 9, but the 6 is closed and nothing else can move
  local short = rolled(3, 3, { [12] = 1, [1] = 14 }, { [19] = 2 })
  move(short, 1, 12, 9)
  eq(#short.last.played, 1, "one played, and nothing can use the other three")
  eq(short.turn, 2, "so the turn ends")
end)

test("bearing off: an exact die, and a higher die only for the furthest checker", function()
  local state = rolled(6, 4, { [5] = 1, [4] = 1, [2] = 1 }, { [15] = 2 })
  truthy(legalText(state):find("5>0:6", 1, true), "the six takes the furthest")
  truthy(legalText(state):find("4>0:4", 1, true), "the four is exact")
  truthy(not legalText(state):find("4>0:6", 1, true), "the six cannot take the four while the five is there")
  truthy(not legalText(state):find("2>0:6", 1, true), "nor the two")
  truthy(not legalText(state):find("2>0:4", 1, true), "the four cannot take the two")
  truthy(legalText(state):find("5>1:4", 1, true), "the four can move inside instead")
  move(state, 1, 5, rules.OFF)
  eq(state.players[1].off, 13, "off")
  -- Now the four is the furthest, so the four takes it and nothing higher matters
  eq(legalText(state), "4>0:4", "the four is the furthest, exactly")
end)

test("a die above every checker bears off the furthest, and picks the lower of two that can", function()
  local state = rolled(6, 5, { [3] = 2 }, { [24] = 2 })
  eq(legalText(state), "3>0:5 3>0:6", "either die")
  move(state, 1, 3, rules.OFF)
  eq(state.left[1], 6, "the five went first and the six is left")
  move(state, 1, 3, rules.OFF)
  truthy(rules.done(state), "that was the last")
end)

test("no bearing off with a checker outside or on the bar", function()
  local outside = rolled(6, 1, { [7] = 1, [3] = 2 }, { [24] = 2 })
  truthy(not legalText(outside):find(">0:", 1, true), "one is outside")
  local onBar = rolled(6, 1, { [3] = 2 }, { [6] = 2 }, 1)
  eq(legalText(onBar), "25>24:1", "the bar comes first")
end)

test("the last checker off wins at once, and leftover dice do not matter", function()
  local state = rolled(6, 1, { [2] = 1 }, { [1] = 2, [2] = 2 })
  eq(legalText(state), "2>0:6 2>1:1", "the one first or the six to finish")
  move(state, 1, 2, rules.OFF)
  truthy(rules.done(state), "over")
  eq(state.winner, 1, "Ann")
  eq(state.how, "single", "Bea has some off")
  eq(#rules.waitingOn(state), 0, "nothing waits")
  eq(#rules.actions(state, 1), 0, "no buttons")
end)

test("a single game pays the stake", function()
  local state = rolled(6, 5, { [1] = 1 }, { [1] = 2, [6] = 2 })
  move(state, 1, 1, rules.OFF)
  eq(state.how, "single", "single")
  local nets = rules.nets(state)
  eq(nets[1], 100, "win")
  eq(nets[2], -100, "lose")
  eq(rules.result(state, 1).kind, "win", "Ann won")
  eq(rules.result(state, 2).kind, "lose", "Bea lost")
  truthy(rules.result(state, nil).title:find("Ann", 1, true), "the table's line")
end)

test("a gammon pays double", function()
  local full = { [1] = 15 }
  local state = rolled(6, 5, { [1] = 1 }, full)
  move(state, 1, 1, rules.OFF)
  eq(state.how, "gammon", "nothing off")
  eq(rules.nets(state)[1], 200, "double")
  eq(rules.nets(state)[2], -200, "double")
  truthy(rules.result(state, 2).title:find("GAMMON", 1, true), "the banner says it")
end)

test("a backgammon pays triple: a checker on the bar or in the winner's home", function()
  local inHome = rolled(6, 5, { [1] = 1 }, { [1] = 14, [19] = 1 })
  move(inHome, 1, 1, rules.OFF)
  eq(inHome.how, "backgammon", "in my home")
  eq(rules.nets(inHome)[1], 300, "triple")
  local onBar = rolled(6, 5, { [1] = 1 }, { [1] = 14 }, 0, 1)
  move(onBar, 1, 1, rules.OFF)
  eq(onBar.how, "backgammon", "on the bar")
  eq(rules.nets(onBar)[2], -300, "triple")
  local outfield = rolled(6, 5, { [1] = 1 }, { [1] = 14, [18] = 1 })
  move(outfield, 1, 1, rules.OFF)
  eq(outfield.how, "gammon", "the 18 is just outside the winner's home")
end)

test("a checker off saves the gammon even with one in the winner's home", function()
  local state = rolled(6, 5, { [1] = 1 }, { [1] = 13, [24] = 1 })
  move(state, 1, 1, rules.OFF)
  eq(state.how, "single", "one is off")
end)

test("doubling: offer, take, and the cube goes across", function()
  local state = position({ [6] = 2 }, { [6] = 2 })
  local offered = ids(rules.actions(state, 1))
  truthy(offered.double, "the cube is in the middle")
  truthy(offered.roll, "or just roll")
  truthy(#rules.act(state, 1, "double") > 0, "doubled")
  eq(state.phase, "double", "waiting on Bea")
  eq(rules.waitingOn(state)[1], 2, "her turn to answer")
  eq(state.cube, 1, "not until she takes")
  eq(#rules.actions(state, 1), 0, "Ann has nothing to press")
  eq(#rules.act(state, 1, "take"), 0, "and cannot take her own")
  truthy(#rules.act(state, 2, "take") > 0, "taken")
  eq(state.cube, 2, "doubled")
  eq(state.holder, 2, "Bea holds it")
  eq(rules.waitingOn(state)[1], 1, "Ann rolls")
  eq(ids(rules.actions(state, 1)).double, nil, "Ann cannot double again")
  eq(#rules.act(state, 1, "double"), 0, "nor by force")

  -- Bea can redouble from her turn
  truthy(#rules.act(state, 1, "roll", nil, dice(2, 1)) > 0, "Ann rolls")
  rules.act(state, 1, "auto")
  eq(state.turn, 2, "Bea's turn")
  truthy(ids(rules.actions(state, 2)).double, "the holder may double")
  rules.act(state, 2, "double")
  eq(state.offer.cube, 4, "to four")
  rules.act(state, 1, "take")
  eq(state.cube, 4, "four")
  eq(state.holder, 1, "back to Ann")
end)

test("no double once rolled, and none on the first player's opening turn", function()
  local state = fresh()
  eq(ids(rules.actions(state, 1)).double, nil, "the opening is already rolled")
  eq(#rules.act(state, 1, "double"), 0, "no double then")
  local later = rolled(2, 1, { [6] = 2 }, { [6] = 2 })
  eq(ids(rules.actions(later, 1)).double, nil, "nor after a roll")
end)

test("a drop loses the stake times the cube as it stood, and no more", function()
  local state = position({ [6] = 2 }, { [6] = 15 })
  state.cube, state.holder = 4, 1
  rules.act(state, 1, "double")
  truthy(#rules.act(state, 2, "drop") > 0, "dropped")
  truthy(rules.done(state), "over")
  eq(state.how, "drop", "a drop")
  eq(state.winner, 1, "the doubler wins")
  eq(rules.nets(state)[1], 400, "stake times four, not eight, and no gammon")
  eq(rules.nets(state)[2], -400, "the same")
  eq(rules.result(state, 2).kind, "lose", "Bea lost")
  truthy(rules.result(state, 2).title:find("DROP", 1, true), "the banner says it")
end)

test("the cube multiplies a gammon", function()
  local state = rolled(6, 5, { [1] = 1 }, { [1] = 15 })
  state.cube = 4
  move(state, 1, 1, rules.OFF)
  eq(rules.nets(state)[1], 800, "stake, cube, gammon")
  eq(rules.risk(state, 1), 400, "risk is stake times the cube")
end)

test("nets stop at the shorter stack, and the cube stops short of it", function()
  -- Stacks 450 and 1000 at a stake of 100: 200 and 400 are fine, 800 is not
  local state = position({ [1] = 1 }, { [1] = 15 }, 0, 0, 100, 450, 1000)
  eq(state.cap, 450, "the shorter stack")
  truthy(rules.canDouble(state, 1), "to two")
  state.cube = 2
  truthy(rules.canDouble(state, 1), "to four")
  state.cube = 4
  eq(rules.canDouble(state, 1), false, "eight would pass the cap")
  eq(ids(rules.actions(state, 1)).double, nil, "not offered")
  eq(#rules.act(state, 1, "double"), 0, "not by force")
  truthy(#rules.act(state, 1, "roll", nil, dice(6, 5)) > 0, "rolled")
  move(state, 1, 1, rules.OFF)
  eq(state.how, "gammon", "a gammon at four would be 800")
  eq(rules.nets(state)[1], 450, "capped")
  eq(rules.nets(state)[2], -450, "capped")
  truthy(rules.result(state, 1).detail:find("capped", 1, true), "the banner says why")

  local exact = position({ [6] = 2 }, { [6] = 2 }, 0, 0, 100, 400, 1000)
  exact.cube = 2
  truthy(rules.canDouble(exact, 1), "exactly the cap can be paid")
  local none = position({ [6] = 2 }, { [6] = 2 }, 0, 0, 100, 100, 1000)
  eq(rules.canDouble(none, 1), false, "a stake that is the whole stack has no cube")
  eq(rules.viewFor(none, 1).cap, 100, "the wall shows the cap")
end)

test("the stake never passes the shorter stack", function()
  local state = fresh(500, 120, 900)
  eq(state.stake, 120, "capped")
  eq(state.cap, 120, "and the cap with it")
end)

test("a timeout rolls and plays the whole turn, and never doubles", function()
  local state = position({ [24] = 2, [13] = 5, [8] = 3, [6] = 5 }, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 })
  local id = rules.auto(state, 1)
  truthy(ids(rules.actions(state, 1)).double, "a double was on offer")
  local before = state.cube
  truthy(#rules.act(state, 1, id, nil, dice(6, 5)) > 0, "it moved")
  eq(state.cube, before, "no double")
  eq(state.turn, 2, "the whole turn went")
  eq(state.phase, "roll", "Bea rolls")
  eq(#state.last.played, 2, "both dice played")
  sane(state)
end)

test("a timeout finishes a turn already part played, whatever is selected", function()
  local state = rolled(3, 3, { [24] = 2, [13] = 5 }, { [6] = 2 })
  move(state, 1, 24, 21)
  rules.act(state, 1, "from", 13)
  truthy(#rules.act(state, 1, rules.auto(state, 1), nil, dice(1, 1)) > 0, "it moved")
  eq(state.turn, 2, "over to Bea")
  eq(state.draft, nil, "no selection left")
  eq(#state.last.played, 4, "four in all")
end)

test("a timeout drops a double, and can win a game by bearing off", function()
  local state = position({ [6] = 2 }, { [6] = 2 })
  rules.act(state, 1, "double")
  eq(rules.auto(state, 2), "drop", "a double is dropped")
  truthy(#rules.act(state, 2, "drop") > 0, "dropped")
  eq(state.winner, 1, "the doubler")

  local home = position({ [1] = 2 }, { [6] = 2 })
  truthy(#rules.act(home, 1, rules.auto(home, 1), nil, dice(4, 2)) > 0, "played")
  truthy(rules.done(home), "the clock can finish a game")
  eq(home.winner, 1, "Ann")
end)

test("UNDO goes back through a turn until the last die ends it", function()
  local state = rolled(6, 1, { [24] = 2, [13] = 5 }, { [3] = 2 })
  eq(ids(rules.actions(state, 1)).undo, nil, "nothing to undo")
  eq(#rules.act(state, 1, "undo"), 0, "so UNDO does nothing")
  local before = kit.plain(state)
  move(state, 1, 24, 18)
  truthy(ids(rules.actions(state, 1)).undo, "undo is there")
  rules.act(state, 1, "undo")
  truthy(kit.same(before, state), "back where it started")
  move(state, 1, 24, 18)
  move(state, 1, 18, 17)
  eq(state.turn, 2, "the last die ends the turn")
  eq(ids(rules.actions(state, 1)).undo, nil, "and it cannot be taken back")
end)

test("tapping a point selects it, again puts it back, and another moves the selection", function()
  local state = rolled(6, 1, { [24] = 2, [13] = 5 }, { [3] = 2 })
  truthy(#rules.act(state, 1, "from", 24) > 0, "picked up")
  eq(state.draft.from, 24, "the draft is in the state")
  local view = rules.viewFor(state, 1)
  eq(view.draft.from, 24, "the view has it")
  truthy(kit.shows(view.targets, 18) and kit.shows(view.targets, 23), "both targets")
  eq(rules.viewFor(state, 2).draft, nil, "the other wall does not")
  eq(rules.viewFor(state, nil).draft, nil, "nor the public one")
  truthy(#rules.act(state, 1, "from", 13) > 0, "another")
  eq(state.draft.from, 13, "moved")
  truthy(#rules.act(state, 1, "from", 13) > 0, "again")
  eq(state.draft, nil, "put back")
  eq(#rules.act(state, 1, "to", 12), 0, "no destination without a selection")
  eq(#rules.act(state, 1, "from", 8), 0, "nothing on that point")
  eq(#rules.act(state, 1, "from", 2), 0, "nor that")
end)

test("nobody moves out of turn and junk changes nothing", function()
  local state = rolled(6, 1, { [24] = 2, [13] = 5 }, { [3] = 2 })
  local before = kit.plain(state)
  local rng = testing.fastRng(1)
  local junk = { { 2, "from", 24 }, { 2, "to", 18 }, { 2, "roll" }, { 2, "double" }, { 2, "take" }, { 2, "drop" }, { 2, "undo" }, { 2, "auto" },
    { 3, "from", 24 }, { 3, "auto" }, { 1, "from", 0 }, { 1, "from", 26 }, { 1, "from", 1.5 }, { 1, "from", "24" }, { 1, "from", {} }, { 1, "from" },
    { 1, "from", 0 / 0 }, { 1, "from", 1 / 0 }, { 1, "to", 18 }, { 1, "to", 0 / 0 }, { 1, "roll" }, { 1, "double" }, { 1, "take" }, { 1, "drop" }, { 1, "pick" }, { 1, 42 },
    { nil, "roll" }, { nil, "auto" }, { nil, "from", 24 } }
  for index, press in ipairs(junk) do
    eq(#rules.act(state, press[1], press[2], press[3], rng), 0, "junk " .. index)
    truthy(kit.same(before, state), "junk " .. index .. " changed the state")
  end
  rules.act(state, 1, "from", 24)
  local picked = kit.plain(state)
  for _, value in ipairs({ 24, 7, 0, 25, -1, 19, 1.5 }) do
    if value ~= 24 then eq(#rules.act(state, 1, "to", value), 0, "not a target: " .. value) end
    truthy(kit.same(picked, state), "a bad target changed the state")
  end
end)

test("the rules agree with a brute force through whole random games", function()
  local checked = 0
  local check = function(state)
    sane(state)
    if state.phase == "move" and not state.over then
      checked = checked + 1
      eq(legalText(state), oracle(state), "what is legal")
    end
  end
  kit.fuzz(plugin, { rounds = 60, seats = { 2 }, stake = 100, stack = 1000, pick = longTapper, check = breathing(check), seed = 31 })
  truthy(checked > 1000, "the oracle ran: " .. checked)
end)

test("the oracle agrees on the positions that make the hard rules bite", function()
  local cases = {
    { 6, 3, { [20] = 1, [1] = 14 }, { [14] = 2 } },
    { 6, 3, { [20] = 1, [1] = 14 }, { [14] = 2, [11] = 2 } },
    { 6, 1, { [20] = 1, [10] = 1, [1] = 13 }, { [6] = 2, [22] = 2 } },
    { 5, 1, { [7] = 1, [1] = 14 }, { [23] = 2 } },
    { 6, 4, { [5] = 1, [4] = 1, [2] = 1 }, { [24] = 2 } },
    { 6, 1, { [2] = 1 }, { [1] = 2, [2] = 2 } },
    { 3, 3, { [12] = 1, [1] = 14 }, { [19] = 2 } },
  }
  for index, case in ipairs(cases) do
    local state = rolled(case[1], case[2], case[3], case[4])
    eq(legalText(state), oracle(state), "case " .. index)
  end
end)

test("games reach every way of ending, and random play stays in the contract at each stake", function()
  for _, setup in ipairs({ { 25, 25 }, { 25, 5000 }, { 100, 450 }, { 250, 1000 }, { 500, 5000 }, { 500, 300 } }) do
    kit.fuzz(plugin, { rounds = 120, seats = { 2 }, stake = setup[1], stack = setup[2], pick = tapper, seed = setup[2], check = breathing() })
  end
  kit.fuzz(plugin, { rounds = 120, seats = { 2 }, stake = 100, stack = 3000, absent = 50, pick = tapper, seed = 99, check = breathing() })
  kit.fuzz(plugin, { rounds = 80, seats = { 2 }, stake = 50, stack = 800, absent = 15, seed = 7, check = breathing() })

  local seen = {}
  local rng = testing.fastRng(77)
  for _ = 1, 150 do
    local state = kit.playRound(plugin, { rng = rng, stake = 100, stack = 1000, pick = longTapper, check = breathing() })
    seen[state.how] = (seen[state.how] or 0) + 1
    kit.checkEnd(plugin, state, kit.entries(plugin, 2, { stake = 100, stack = 1000 }))
  end
  truthy(seen.single, "singles")
  truthy(seen.gammon, "gammons")
  truthy(seen.backgammon, "backgammons")
end)

test("nets sum to zero and stay under the shorter stack, with stacks that differ", function()
  local stakes = { 25, 50, 100, 250, 500 }
  for index, stake in ipairs(stakes) do
    local list = entries(stake, 600 + index * 700, 400 + index * 90)
    local check = function(state)
      if rules.canDouble(state, state.turn) then truthy(state.stake * state.cube * 2 <= 400 + index * 90, "the cube passed the cap") end
    end
    for seed = 1, 20 do
      local state = kit.playRound(plugin, { seed = seed * 13 + index, entries = list, pick = tapper, check = breathing(check) })
      local nets = kit.checkEnd(plugin, state, list)
      truthy(math.abs(nets[1]) <= 400 + index * 90, "past the shorter stack")
      eq(nets[1] + nets[2], 0, "zero")
    end
  end
end)

test("the clock alone finishes a game", function()
  for seed = 1, 60 do
    local state = kit.playRound(plugin, { seed = seed, stake = 50, stack = 50, absent = 100, check = breathing() })
    kit.checkEnd(plugin, state, kit.entries(plugin, 2, { stake = 50, stack = 50 }))
  end
end)

test("the next roll is nowhere: not in the state, not in a view, and only the rng decides it", function()
  local state = position({ [24] = 2, [13] = 5, [8] = 3, [6] = 5 }, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 })
  local before = { kit.plain(rules.viewFor(state, 1)), kit.plain(rules.viewFor(state, 2)), kit.plain(rules.viewFor(state, nil)) }
  eq(state.dice, nil, "no dice before the roll")
  eq(state.rng, nil, "no rng in the state")
  local a, b = kit.plain(state), kit.plain(state)
  rules.act(a, 1, "roll", nil, dice(6, 5))
  rules.act(b, 1, "roll", nil, dice(2, 1))
  truthy(not kit.same(a.dice, b.dice), "different rngs, different dice")
  truthy(kit.same(before[1], rules.viewFor(state, 1)), "a view before the roll has nothing of it")
  -- Every key the rules hold is a name the game explains, so a seed cannot sit there unnoticed
  local known = { players = 1, stake = 1, cap = 1, cube = 1, over = 1, phase = 1, ties = 1, opening = 1, turn = 1, dice = 1, left = 1, played = 1, legal = 1,
    draft = 1, last = 1, holder = 1, offer = 1, winner = 1, how = 1 }
  local check = function(current)
    for key in pairs(current) do truthy(known[key], "state has a new field: " .. tostring(key)) end
    if current.phase == "roll" then eq(current.dice, nil, "no dice wait in the state") end
  end
  kit.fuzz(plugin, { rounds = 40, seats = { 2 }, stake = 100, stack = 1000, pick = tapper, check = breathing(check), seed = 3 })
end)

test("the opening roll never leaks a tie or a die before it is thrown, and the views agree", function()
  local state = fresh(100, 1000, 1000, dice(2, 5))
  local one, two, public = rules.viewFor(state, 1), rules.viewFor(state, 2), rules.viewFor(state, nil)
  for _, key in ipairs({ "players", "opening", "dice", "left", "cube", "stake" }) do
    truthy(kit.same(one[key], public[key]), "seat 1 and public differ on " .. key)
    truthy(kit.same(two[key], public[key]), "seat 2 and public differ on " .. key)
  end
end)

test("events are plain and small", function()
  local rng = testing.fastRng(11)
  local state, events = rules.new(entries(), 1, rng, {})
  local function clean(list)
    for _, ev in ipairs(list) do
      truthy(type(ev.type) == "string", "typed")
      for key, value in pairs(ev) do truthy(type(value) ~= "table", "event " .. ev.type .. " holds " .. tostring(key)) end
    end
  end
  clean(events)
  for _ = 1, 2000 do
    if rules.done(state) then break end
    local waiting = rules.waitingOn(state)
    clean(rules.act(state, waiting[1], rules.auto(state, waiting[1]), nil, rng))
  end
  truthy(rules.done(state), "over")
end)

test("every event has a length, and a sound that exists", function()
  local audio = require("lib.casino.audio")
  local picks = require("lib.sound_picks")
  local names = { "opening", "roll", "blocked", "double", "take", "drop", "undo", "pick", "turn", "win" }
  local real = {}
  for _, name in ipairs({ "tap", "chip", "chipBig", "error", "deal", "flip", "start", "tick", "spin", "stop", "win", "bigWin", "lose", "push", "warn" }) do real[name] = true end
  local function good(seconds, sound)
    truthy(type(seconds) == "number" and seconds > 0, "a length")
    truthy(sound == nil or real[sound] or picks[sound], "the sound " .. tostring(sound))
  end
  truthy(audio, "audio loads")
  for _, name in ipairs(names) do good(plugin.event({ type = name })) end
  good(plugin.event({ type = "move", to = 5 }))
  good(plugin.event({ type = "move", to = 5, hit = true }))
  good(plugin.event({ type = "move", to = 0 }))
end)

test("every state survives textutils and a journal", function()
  if not textutils then return end
  for seed = 1, 6 do
    local rng = testing.fastRng(21 + seed)
    local state = rules.new(entries(), 1, rng, {})
    for _ = 1, 3000 do
      state = textutils.unserialize(textutils.serialize(state))
      for _, seat in ipairs({ 1, 2 }) do
        local view = rules.viewFor(state, seat)
        truthy(kit.same(view, textutils.unserialize(textutils.serialize(view))), "the view")
      end
      if rules.done(state) then break end
      local waiting = rules.waitingOn(state)[1]
      local id, value = longTapper(state, waiting, rules.actions(state, waiting), rng)
      if not id then id, value = rules.auto(state, waiting) end
      truthy(#rules.act(state, waiting, id, value, rng) > 0, "moved")
      testing.breathe()
    end
    truthy(rules.done(state), "over")
    textutils.serialize(state)
  end
end)

test("regions match what can be tapped, and are big enough", function()
  local state = rolled(6, 1, { [24] = 2, [13] = 5, [8] = 3, [6] = 5 }, { [3] = 2 })
  local function fits(regions)
    for _, region in ipairs(regions) do
      truthy(region.x >= 2 and region.x + region.w - 1 <= 120, "inside the wall's width")
      truthy(region.y >= 10 and region.y + region.h - 1 <= 53, "on the board")
      truthy(region.w >= 7 and region.h >= 20, "big enough to tap")
    end
  end
  local regions = plugin.seatView.regions(rules.viewFor(state, 1))
  truthy(#regions > 0, "regions")
  fits(regions)
  for _, region in ipairs(regions) do
    eq(region.id, "from", "only sources before a selection")
    truthy(#rules.act(kit.plain(state), 1, region.id, region.value) > 0, "a live point does something: " .. region.value)
  end
  rules.act(state, 1, "from", 13)
  regions = plugin.seatView.regions(rules.viewFor(state, 1))
  fits(regions)
  local tos = 0
  for _, region in ipairs(regions) do
    if region.id == "to" then tos = tos + 1 end
    truthy(#rules.act(kit.plain(state), 1, region.id, region.value) > 0, "a live point does something")
  end
  eq(tos, 2, "two destinations")
  eq(#plugin.seatView.regions(rules.viewFor(state, nil)), 0, "a public view has none")
  eq(#plugin.seatView.regions(rules.viewFor(state, 2)), 0, "nor the player waiting")

  -- No two regions overlap, so a tap cannot mean two things
  for i, a in ipairs(regions) do
    for j, b in ipairs(regions) do
      if i ~= j then
        truthy(a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y, "regions overlap")
      end
    end
  end
end)

test("the bar and the tray can be tapped", function()
  local onBar = rolled(6, 1, { [13] = 3, [8] = 2 }, { [6] = 2 }, 2)
  local region = plugin.seatView.regions(rules.viewFor(onBar, 1))[1]
  eq(region.value, rules.BAR, "the bar")
  local home = rolled(6, 5, { [3] = 2 }, { [24] = 2 })
  rules.act(home, 1, "from", 3)
  local found
  for _, each in ipairs(plugin.seatView.regions(rules.viewFor(home, 1))) do
    if each.id == "to" and each.value == rules.OFF then found = each end
  end
  truthy(found, "the tray")
  truthy(found.w >= 7, "wide enough")
end)

test("with a checker selected only its green points and itself can be hit", function()
  local state = rolled(5, 2, { [13] = 5, [8] = 3 }, { [1] = 2 })
  rules.act(state, 1, "from", 13)
  local regions = plugin.seatView.regions(rules.viewFor(state, 1))
  local seen = {}
  for _, region in ipairs(regions) do
    seen[region.id .. region.value] = true
  end
  truthy(seen.to8, "13 down to 8 is a move")
  truthy(not seen.from8, "and not a change of selection")
  truthy(seen.from13, "the selected point puts itself back")
  eq(#regions, 3, "two green points and the selected one")
end)

test("every view draws on a screenless wall, public and private, through every event", function()
  local canvas = require("lib.casino.canvas")
  local function draws(state)
    for _, seat in ipairs({ 1, 2, false }) do
      local view = rules.viewFor(state, seat or nil)
      for wall = 1, 2 do
        local c = canvas.new(nil, 121, 81)
        plugin.seatView.draw(c, view, nil, { seat = wall, name = "Ann" })
        for _, ev in ipairs({ { type = "roll", seat = 1 }, { type = "opening", seat = 1 }, { type = "move", seat = 1, from = 13, to = 8 }, { type = "move", seat = 2, from = 13, to = 0 },
          { type = "move", seat = 2, from = 25, to = 20, hit = true }, { type = "double", seat = 1, cube = 2 } }) do
          plugin.seatView.draw(c, view, { ev = ev, t = 0.4 }, { seat = wall })
        end
      end
    end
    local c = canvas.new(nil, 121, 81)
    plugin.tableView.draw(c, rules.viewFor(state, nil), nil, { waiting = {}, seats = {} })
  end
  for seed = 1, 6 do
    kit.playRound(plugin, { seed = seed, stake = 25, stack = 100, pick = tapper, check = function(state)
      draws(state)
      testing.breathe()
    end })
  end
end)

test("a wall shows its own side: the seat is at the bottom, public or not", function()
  local canvas = require("lib.casino.canvas")
  local theme = require("lib.casino.theme")
  local state = fresh()
  local function cellAt(view, wall, x, y)
    local c = canvas.new(nil, 121, 81)
    plugin.seatView.draw(c, view, nil, { seat = wall })
    return c.bg[y][x]
  end
  -- My six is the first column right of the bar, on the bottom, and five of mine are stacked there: white on every wall
  for _, wall in ipairs({ 1, 2 }) do
    local x = 59 + 2
    eq(cellAt(rules.viewFor(state, wall), wall, x, 50), theme.C.card, "own checkers on wall " .. wall)
    eq(cellAt(rules.viewFor(state, nil), wall, x, 50), theme.C.card, "own checkers on public wall " .. wall)
    -- The other player's five start across at my 12
    eq(cellAt(rules.viewFor(state, wall), wall, 5, 50), theme.C.red, "their checkers on wall " .. wall)
  end
end)

test("help says the cap, and the plugin is in order", function()
  eq(plugin.id, "backgammon", "id")
  eq(plugin.kind, "players", "kind")
  eq(plugin.minSeats, 2, "min")
  eq(plugin.maxSeats, 2, "max")
  truthy(plugin.stakes[1] > 0, "stakes")
  truthy(plugin.tableView.draw and plugin.seatView.draw, "pictures")
  local said = false
  for _, line in ipairs(plugin.help()) do
    local text = type(line) == "table" and line[1] or line
    if text:find("shorter stack", 1, true) and text:find("cube", 1, true) then said = true end
  end
  truthy(said, "the help says the cap")
end)
