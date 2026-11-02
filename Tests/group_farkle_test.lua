-- group_farkle_test.lua
-- Farkle on Duel: every scoring pattern, dead dice, the opening, hot dice, the last turn and its tie, the stake, and that a clock left
-- alone always finishes a match.

local kit = require("group_kit")
local testing = require("testing")
local eq, test, truthy = testing.eq, testing.test, testing.truthy

local plugin = kit.plugin("Duel", "farkle")
local rules = plugin.rules

local function entries(stake, stackA, stackB)
  return { { seat = 1, name = "Ann", stack = stackA or 1000, stake = stake or 100 }, { seat = 2, name = "Bea", stack = stackB or 1000, stake = stake or 100 } }
end

--- An rng that gives these faces in order, then falls back on a real one.
local function loaded(faces, seed)
  local list, at = faces, 0
  local fallback = testing.fastRng(seed or 3)
  return { below = function(_, n)
    at = at + 1
    if list[at] then return list[at] - 1 end
    return fallback:below(n)
  end }
end

local function fresh(seed, stake, stackA, stackB, button)
  local state = rules.new(entries(stake, stackA, stackB), button or 1, testing.fastRng(seed or 7), {})
  return state
end

--- A match with the throw done and these dice in front of a seat.
local function table_(seat, dice)
  local state = fresh()
  state.turn, state.phase, state.points, state.aside, state.last = seat or 1, "pick", 0, {}, nil
  state.dice, state.marks = dice, {}
  for index = 1, #dice do state.marks[index] = false end
  return state
end

--- Tap these dice, by position.
local function tap(state, seat, ...)
  for _, index in ipairs({ ... }) do truthy(#rules.act(state, seat, "die", index) > 0, "tapped die " .. index) end
end

local function ids(list)
  local out = {}
  for _, action in ipairs(list) do out[action.id] = action end
  return out
end

--- A player's move for kit: tap a scoring die now and then, a dead one sometimes, or press what is live.
local function player(state, seat, actions, rng)
  local view = rules.viewFor(state, seat)
  if view.phase ~= "pick" then return nil end
  local live = {}
  for _, action in ipairs(actions) do
    if not action.disabled then live[#live + 1] = action end
  end
  if #live > 0 and rng:below(3) > 0 then
    local action = live[rng:below(#live) + 1]
    return action.id, action.value
  end
  if rng:below(5) > 0 then
    for index, scores in ipairs(view.scoring) do
      if scores and not view.marks[index] then return "die", index end
    end
  end
  return "die", rng:below(#view.dice) + 1
end

test("every scoring pattern", function()
  local cases = {
    { { 1 }, 100, "a one" }, { { 5 }, 50, "a five" }, { { 1, 1 }, 200, "two ones" }, { { 5, 5 }, 100, "two fives" }, { { 1, 5 }, 150, "a one and a five" },
    { { 2, 2, 2 }, 200, "three twos" }, { { 3, 3, 3 }, 300, "three threes" }, { { 4, 4, 4 }, 400, "three fours" },
    { { 5, 5, 5 }, 500, "three fives" }, { { 6, 6, 6 }, 600, "three sixes" }, { { 1, 1, 1 }, 1000, "three ones" },
    { { 2, 2, 2, 2 }, 1000, "four of a kind" }, { { 6, 6, 6, 6 }, 1000, "four sixes" }, { { 5, 5, 5, 5 }, 1000, "four fives" },
    { { 3, 3, 3, 3, 3 }, 2000, "five of a kind" }, { { 5, 5, 5, 5, 5 }, 2000, "five fives" }, { { 1, 1, 1, 1, 1 }, 2000, "five ones" },
    { { 4, 4, 4, 4, 4, 4 }, 3000, "six of a kind" }, { { 1, 1, 1, 1, 1, 1 }, 3000, "six ones" },
    { { 1, 2, 3, 4, 5, 6 }, 1500, "a straight" }, { { 6, 3, 1, 5, 2, 4 }, 1500, "a straight in any order" },
    { { 2, 2, 3, 3, 4, 4 }, 1500, "three pairs" }, { { 1, 1, 5, 5, 6, 6 }, 1500, "three pairs with ones and fives" },
    { { 2, 2, 2, 3, 3, 3 }, 2500, "two triples" }, { { 1, 1, 1, 5, 5, 5 }, 2500, "two triples of ones and fives" },
    { { 1, 1, 1, 1 }, 1100, "four ones are three ones and a one, the better reading" },
    { { 2, 2, 2, 1 }, 300, "three twos and a one" }, { { 4, 4, 4, 5, 5 }, 500, "three fours and two fives" },
    { { 3, 3, 3, 3, 1, 5 }, 1150, "four of a kind and two singles" }, { { 6, 6, 6, 6, 6, 1 }, 2100, "five of a kind and a one" },
    { { 5, 5, 5, 5, 1, 1 }, 1200, "four fives and two ones" },
  }
  for _, case in ipairs(cases) do eq(rules.score(case[1]), case[2], case[3]) end
end)

test("a set with any die that does not score has no score", function()
  local dead = {
    { 2 }, { 3 }, { 4 }, { 6 }, { 2, 2 }, { 6, 6 }, { 1, 2 }, { 5, 3 }, { 2, 2, 2, 3 }, { 1, 1, 1, 2 }, { 1, 2, 3, 4, 5 }, { 2, 2, 3, 3 },
    { 2, 2, 3, 3, 4 }, { 2, 2, 2, 2, 3, 3 }, { 2, 2, 2, 3, 3, 4 }, { 3, 3, 3, 3, 3, 4 }, {},
  }
  for index, faces in ipairs(dead) do eq(rules.score(faces), nil, "set " .. index) end
end)

test("the best selection takes everything that scores, and a roll with none is a farkle", function()
  local _, points = rules.best({ 1, 2, 2, 3, 4, 5 })
  eq(points, 150, "the one and the five")
  local marks, top = rules.best({ 1, 1, 1, 1, 5, 6 })
  eq(top, 1150, "four ones and a five")
  eq(marks[6], false, "the six stays")
  eq(marks[1] and marks[2] and marks[3] and marks[4] and marks[5], true, "the rest go")
  local _, none = rules.best({ 2, 2, 3, 4, 6, 6 })
  eq(none, 0, "nothing scores")
  local _, straight = rules.best({ 1, 2, 3, 4, 5, 6 })
  eq(straight, 1500, "a straight beats a one and a five")
  local _, pairsOf = rules.best({ 2, 2, 3, 3, 6, 6 })
  eq(pairsOf, 1500, "three pairs")
end)

test("the best selection agrees with trying every selection, for every roll of one to six dice", function()
  local function each(dice, low, left, visit)
    if left == 0 then return visit(dice) end
    for face = low, 6 do
      dice[#dice + 1] = face
      each(dice, face, left - 1, visit)
      dice[#dice] = nil
    end
  end
  local rolls = 0
  local function check(dice)
    local top = 0
    for mask = 1, 2 ^ #dice - 1 do
      local faces = {}
      for index = 1, #dice do
        if math.floor(mask / 2 ^ (index - 1)) % 2 == 1 then faces[#faces + 1] = dice[index] end
      end
      top = math.max(top, rules.score(faces) or 0)
    end
    local marks, points = rules.best(dice)
    eq(points, top, "the points of " .. table.concat(dice, " "))
    local faces = {}
    for index, die in ipairs(dice) do
      if marks[index] then faces[#faces + 1] = die end
    end
    eq(rules.score(faces) or 0, top, "the marks of " .. table.concat(dice, " "))
    rolls = rolls + 1
    if rolls % 40 == 0 then testing.breathe() end
  end
  for count = 1, 6 do each({}, 1, count, check) end
  eq(rolls, 923, "every roll, sorted")
end)

test("a selection with a dead die in it cannot roll or bank", function()
  local state = table_(1, { 1, 2, 3, 4, 6, 6 })
  tap(state, 1, 1, 2)
  local before = kit.plain(state)
  local rng = testing.fastRng(1)
  eq(#rules.act(state, 1, "roll", nil, rng), 0, "no roll")
  eq(#rules.act(state, 1, "bank", nil, rng), 0, "no bank")
  truthy(kit.same(before, state), "nothing changed")
  local actions = ids(rules.actions(state, 1))
  truthy(actions.roll.disabled and actions.bank.disabled, "both grey")
  eq(rules.viewFor(state, nil).dead, true, "the wall says so")
  eq(rules.viewFor(state, nil).picked, 0, "and scores it nothing")
  tap(state, 1, 2)
  eq(rules.viewFor(state, nil).picked, 100, "take it back and it scores")
  truthy(#rules.act(state, 1, "roll", nil, rng) > 0, "and rolls")
end)

test("nothing marked cannot roll or bank", function()
  local state = table_(1, { 1, 2, 3, 4, 6, 6 })
  local rng = testing.fastRng(1)
  eq(#rules.act(state, 1, "roll", nil, rng), 0, "no roll")
  eq(#rules.act(state, 1, "bank", nil, rng), 0, "no bank")
  truthy(ids(rules.actions(state, 1)).roll.disabled, "grey")
end)

test("a set is built one tap at a time and is scored live", function()
  local state = table_(1, { 2, 2, 2, 3, 4, 6 })
  tap(state, 1, 1, 2)
  eq(rules.viewFor(state, 1).dead, true, "two of three is not yet a score")
  tap(state, 1, 3)
  local view = rules.viewFor(state, 1)
  eq(view.dead, false, "three is")
  eq(view.picked, 200, "scored")
  eq(view.running, 200, "running")
  local actions = ids(rules.actions(state, 1))
  eq(actions.roll.label, "ROLL 3 DICE", "the button says how many")
  eq(actions.bank.label, "BANK 200", "and how much")
end)

test("the turn's points grow across rolls, and only dice of one roll combine", function()
  local state = table_(1, { 1, 2, 3, 4, 6, 6 })
  tap(state, 1, 1)
  local events = rules.act(state, 1, "roll", nil, loaded({ 1, 1, 3, 4, 6 }))
  eq(events[1].type, "roll", "rolled")
  eq(events[1].count, 5, "five dice")
  eq(state.points, 100, "the turn holds the one")
  eq(#state.dice, 5, "five on the table")
  eq(#state.aside, 1, "one aside")
  -- A third one, with one set aside already, makes no three of a kind: 100 + 200 and not 1000
  tap(state, 1, 1, 2)
  eq(rules.viewFor(state, 1).running, 300, "two more ones are 200")
  eq(ids(rules.actions(state, 1)).roll.label, "ROLL 3 DICE", "three left")
end)

test("rolling one die says so", function()
  local state = table_(1, { 1, 1, 1, 1, 1, 3 })
  tap(state, 1, 1, 2, 3, 4, 5)
  eq(ids(rules.actions(state, 1)).roll.label, "ROLL 1 DIE", "one die")
end)

test("a farkle loses the turn's points and passes the dice", function()
  local state = table_(1, { 1, 2, 3, 4, 6, 6 })
  state.players[1].score, state.players[1].opened = 700, true
  state.points = 400
  tap(state, 1, 1)
  local events = rules.act(state, 1, "roll", nil, loaded({ 2, 3, 3, 4, 6 }))
  eq(events[2].type, "farkle", "farkle")
  eq(events[2].lost, 500, "what went")
  eq(state.players[1].score, 700, "the score stands")
  eq(state.points, 0, "the turn is gone")
  eq(state.turn, 2, "the dice pass")
  eq(state.phase, "throw", "the computer throws")
  eq(#rules.waitingOn(state), 0, "nobody to wait on")
  eq(#state.dice, 5, "the farkle stays on the wall")
  local id, value = rules.auto(state, nil)
  truthy(#rules.act(state, nil, id, value, loaded({ 1, 2, 3, 4, 6, 6 })) > 0, "thrown")
  eq(#state.dice, 6, "six for the next player")
  eq(rules.waitingOn(state)[1], 2, "their turn")
end)

test("a first roll can farkle, and the match goes on", function()
  local state, events = rules.new(entries(), 1, loaded({ 2, 2, 3, 3, 4, 6 }), {})
  eq(events[2].type, "farkle", "at once")
  eq(state.turn, 2, "next player")
  eq(state.phase, "throw", "the computer throws")
end)

test("the first bank needs 500 and after that any amount will do", function()
  local state = table_(1, { 1, 1, 5, 2, 3, 4 })
  tap(state, 1, 1, 2, 3)
  eq(rules.viewFor(state, 1).running, 250, "250")
  local bank = ids(rules.actions(state, 1)).bank
  truthy(bank.disabled, "grey")
  eq(bank.label, "BANK 250", "still says what it would be")
  eq(#rules.act(state, 1, "bank"), 0, "refused")
  state.points = 250
  eq(ids(rules.actions(state, 1)).bank.disabled, nil, "exactly 500 is enough")
  local events = rules.act(state, 1, "bank")
  eq(events[1].type, "bank", "banked")
  eq(state.players[1].score, 500, "scored")
  eq(state.players[1].opened, true, "opened")
  eq(state.turn, 2, "passed")

  rules.act(state, nil, "roll", nil, loaded({ 1, 2, 3, 4, 6, 6 }))
  tap(state, 2, 1)
  truthy(ids(rules.actions(state, 2)).bank.disabled, "Bea has not opened")
  local again = table_(1, { 5, 2, 3, 4, 6, 6 })
  again.players[1].opened, again.players[1].score = true, 500
  tap(again, 1, 1)
  truthy(#rules.act(again, 1, "bank") > 0, "50 will do once open")
  eq(again.players[1].score, 550, "banked")
end)

test("all six scoring is hot dice: six more and the points stay", function()
  local state = table_(1, { 1, 2, 3, 4, 5, 6 })
  state.points = 300
  tap(state, 1, 1, 2, 3, 4, 5, 6)
  eq(ids(rules.actions(state, 1)).roll.label, "ROLL 6 DICE", "all six go again")
  local events = rules.act(state, 1, "roll", nil, loaded({ 1, 2, 3, 3, 4, 6 }))
  eq(events[1].type, "hot", "hot first")
  eq(events[2].type, "roll", "then the roll")
  eq(events[2].count, 6, "six")
  eq(state.points, 1800, "the straight on top")
  eq(#state.dice, 6, "six out")
  eq(#state.aside, 0, "nothing aside")
  eq(rules.waitingOn(state)[1], 1, "still their turn")
end)

test("hot dice can be banked instead", function()
  local state = table_(1, { 1, 2, 3, 4, 5, 6 })
  tap(state, 1, 1, 2, 3, 4, 5, 6)
  truthy(#rules.act(state, 1, "bank") > 0, "banked")
  eq(state.players[1].score, 1500, "the straight")
end)

test("hot dice build up across rolls, a die at a time", function()
  local state = table_(1, { 1, 2, 3, 4, 6, 6 })
  tap(state, 1, 1)
  rules.act(state, 1, "roll", nil, loaded({ 1, 2, 2, 2, 5 }))
  tap(state, 1, 1, 2, 3, 4, 5)
  local events = rules.act(state, 1, "roll", nil, loaded({ 1, 3, 3, 4, 4, 6 }))
  eq(events[1].type, "hot", "the sixth die to score makes them hot")
  eq(state.points, 450, "100 + 100 + 200 + 50")
end)

test("hot dice that farkle lose everything", function()
  local state = table_(1, { 1, 2, 3, 4, 5, 6 })
  tap(state, 1, 1, 2, 3, 4, 5, 6)
  local events = rules.act(state, 1, "roll", nil, loaded({ 2, 2, 3, 3, 4, 6 }))
  eq(events[3].type, "farkle", "gone")
  eq(state.players[1].score, 0, "nothing")
  eq(state.turn, 2, "passed")
end)

--- Ann at 4800 banks 400, which leaves Bea on her last turn at the score given.
local function closing(chaser)
  local state = table_(1, { 1, 1, 1, 2, 3, 4 })
  state.players[1].score, state.players[1].opened = 4800, true
  state.players[2].score, state.players[2].opened = chaser, true
  state.points = 300
  tap(state, 1, 1)
  local events = rules.act(state, 1, "bank")
  eq(events[2].type, "lastturn", "the last turn is called")
  eq(events[2].seat, 2, "for Bea")
  eq(state.players[1].score, 5200, "Ann's score")
  truthy(not rules.done(state), "not over")
  eq(state.closing.leader, 1, "Ann got there first")
  eq(state.phase, "throw", "Bea is thrown for")
  return state
end

--- Bea's last turn, with these dice and these points in hand.
local function chaserHas(state, dice, points)
  rules.act(state, nil, "roll", nil, loaded(dice))
  state.points = points
end

test("bank past 5,000 and the other gets one last turn, and winning it ends the match", function()
  local state = closing(4900)
  chaserHas(state, { 1, 2, 3, 4, 6, 6 }, 300)
  tap(state, 2, 1)
  eq(ids(rules.actions(state, 2)).bank.sub, "Wins the match", "the button says so")
  truthy(#rules.act(state, 2, "bank") > 0, "banked")
  truthy(rules.done(state), "over at once")
  eq(state.players[2].score, 5300, "Bea's score")
  eq(state.winner, 2, "the higher score")
  eq(rules.nets(state)[2], 100, "Bea takes it")
  eq(rules.nets(state)[1], -100, "Ann pays")
  eq(#rules.waitingOn(state), 0, "nothing waits")
end)

test("the last turn tying goes to who reached 5,000 first", function()
  local state = closing(4900)
  chaserHas(state, { 1, 2, 3, 4, 6, 6 }, 200)
  tap(state, 2, 1)
  eq(ids(rules.actions(state, 2)).bank.sub, "A tie, and you lose", "the button warns")
  rules.act(state, 2, "bank")
  truthy(rules.done(state), "over")
  eq(state.players[2].score, state.players[1].score, "tied")
  eq(state.winner, 1, "Ann got there first")
  eq(rules.nets(state)[1], 100, "and takes the stake")
  eq(rules.nets(state)[2], -100, "a match cannot tie")
  truthy(rules.result(state, 2).detail:find("first", 1, true), "the result says why")
  eq(rules.result(state, 1).kind, "win", "Ann")
  eq(rules.result(state, 2).kind, "lose", "Bea")
end)

test("the tie goes the other way when the other seat was first", function()
  local state = table_(2, { 1, 2, 3, 4, 6, 6 })
  state.players[2].score, state.players[2].opened = 4900, true
  state.players[1].score, state.players[1].opened = 4800, true
  state.points = 100
  tap(state, 2, 1)
  rules.act(state, 2, "bank")
  eq(state.players[2].score, 5100, "Bea there first")
  rules.act(state, nil, "roll", nil, loaded({ 1, 2, 3, 4, 6, 6 }))
  state.points = 200
  tap(state, 1, 1)
  rules.act(state, 1, "bank")
  eq(state.players[1].score, 5100, "Ann ties")
  eq(state.winner, 2, "Bea wins it")
end)

test("a short bank or a farkle on the last turn loses it", function()
  local short = closing(1000)
  chaserHas(short, { 1, 2, 3, 4, 6, 6 }, 0)
  tap(short, 2, 1)
  eq(ids(rules.actions(short, 2)).bank.sub, "Short, and you lose", "the button warns")
  rules.act(short, 2, "bank")
  truthy(rules.done(short), "over")
  eq(short.winner, 1, "Ann")

  local farkled = closing(4900)
  farkled.phase = "throw"
  local events = rules.act(farkled, nil, "roll", nil, loaded({ 2, 2, 3, 3, 4, 6 }))
  eq(events[2].type, "farkle", "farkle")
  truthy(rules.done(farkled), "over")
  eq(farkled.winner, 1, "Ann")
  eq(farkled.players[2].score, 4900, "Bea's score stands")
end)

test("a last turn past 5,000 gets no reply", function()
  local state = closing(4000)
  chaserHas(state, { 1, 2, 3, 4, 6, 6 }, 1200)
  tap(state, 2, 1)
  rules.act(state, 2, "bank")
  truthy(rules.done(state), "no turn comes back to Ann")
  eq(state.winner, 2, "Bea")
end)

test("the view knows nothing the rng does", function()
  local state = fresh(9)
  local view = kit.plain(rules.viewFor(state, 1))
  for key in pairs(state) do truthy(key ~= "rng" and key ~= "seed" and key ~= "stream", "the state keeps " .. key) end
  -- The same state with a different rng ahead of it: views cannot tell them apart, and the throw comes from the rng alone
  local twin = kit.plain(state)
  truthy(kit.same(view, rules.viewFor(twin, 1)), "the same view")
  tap(state, 1)
  local marks = rules.best(state.dice)
  state.marks, twin.marks = marks, kit.plain(marks)
  local counts = 0
  for index = 1, #state.dice do if marks[index] then counts = counts + 1 end end
  if counts < 6 then
    rules.act(state, 1, "roll", nil, loaded({ 1, 1, 1, 1, 1, 1 }))
    rules.act(twin, 1, "roll", nil, loaded({ 5, 5, 5, 5, 5, 5 }))
    truthy(state.dice[1] ~= twin.dice[1], "the rng decides")
  end
end)

test("the stake never passes the shorter stack", function()
  eq(fresh(4, 500, 120, 900).stake, 120, "capped")
  eq(fresh(4, 500, 900, 120).stake, 120, "either way")
  eq(fresh(4, 25, 900, 900).stake, 25, "the stake as named")
end)

test("the button opens, and a match nets the stake and only that", function()
  eq(fresh(3, 100, 1000, 1000, 2).turn, 2, "the other button")
  for seed = 1, 40 do
    local state, list = kit.playRound(plugin, { seed = seed, stake = 250, stack = 250, absent = 100 })
    local nets = kit.checkEnd(plugin, state, list)
    eq(nets[1] + nets[2], 0, "zero sum")
    eq(math.abs(nets[1]), 250, "the stake")
    eq(rules.risk(state, 1), 250, "risk")
  end
  truthy(rules.result(fresh(), nil).title, "a match on has a line")
end)

test("the higher score always wins, in 150 played matches", function()
  for seed = 1, 150 do
    local state = kit.playRound(plugin, { seed = seed, stake = 25, stack = 25, absent = 50, pick = player })
    local leader = rules.nets(state)
    local a, b = state.players[1], state.players[2]
    if a.score ~= b.score then
      eq(a.score > b.score and a.seat or b.seat, state.winner, "seed " .. seed)
    else
      eq(state.winner, state.closing.leader, "seed " .. seed .. "'s tie")
    end
    truthy(a.score >= rules.TARGET or b.score >= rules.TARGET, "someone reached it")
    truthy(leader[state.winner] > 0, "and was paid")
    testing.breathe()
  end
end)

test("the clock takes the best, banks if it may, and otherwise rolls", function()
  local state = table_(1, { 1, 5, 2, 3, 6, 6 })
  state.players[1].opened = true
  state.points = 100
  tap(state, 1, 3)
  local id, value = rules.auto(state, 1)
  local events = rules.act(state, 1, id, value, testing.fastRng(1))
  eq(events[1].type, "bank", "banks, leaving the player's dead mark behind")
  eq(state.players[1].score, 250, "the one, the five and the turn")

  local closed = table_(1, { 1, 5, 2, 3, 6, 6 })
  id, value = rules.auto(closed, 1)
  events = rules.act(closed, 1, id, value, loaded({ 1, 2, 3, 3, 4 }))
  eq(events[1].type, "roll", "150 cannot open, so it rolls")
  eq(events[1].count, 4, "the other four")
  eq(closed.points, 150, "keeps them")
  eq(rules.waitingOn(closed)[1], 1, "still on")

  local hot = table_(1, { 1, 1, 2, 2, 5, 5 })
  id, value = rules.auto(hot, 1)
  events = rules.act(hot, 1, id, value, testing.fastRng(1))
  eq(events[1].type, "bank", "three pairs open by themselves")
  eq(hot.players[1].score, 1500, "the best reading")

  local cold = table_(1, { 5 })
  cold.points, cold.aside = 200, { 1, 1, 2, 2, 2 }
  id, value = rules.auto(cold, 1)
  events = rules.act(cold, 1, id, value, loaded({ 1, 3, 3, 4, 4, 6 }))
  eq(events[1].type, "hot", "250 cannot open and the last die was the sixth to score, so it rolls all six")
  eq(cold.points, 250, "keeps them")
end)

test("the computer's throw and the clock need an rng and change nothing without one", function()
  local state = table_(1, { 1, 5, 2, 3, 6, 6 })
  local before = kit.plain(state)
  eq(#rules.act(state, 1, "clock"), 0, "no clock")
  truthy(kit.same(before, state), "unchanged")
  state.phase = "throw"
  eq(#rules.act(state, nil, "roll"), 0, "no throw")
end)

test("auto alone always ends a match, and matches do not run forever", function()
  local matches, turns, decisions, longest, ties, leaderWins = 500, 0, 0, 0, 0, 0
  for seed = 1, matches do
    local count, clocks = 0, 0
    local state = kit.playRound(plugin, { seed = seed, stake = 50, stack = 50, absent = 100, steps = 2000, check = function(s)
      if #rules.waitingOn(s) == 0 then count = count + 1 else clocks = clocks + 1 end
    end })
    kit.checkEnd(plugin, state, kit.entries(plugin, 2, { stake = 50, stack = 50 }))
    turns, decisions = turns + count, decisions + clocks
    longest = math.max(longest, clocks)
    if state.players[1].score == state.players[2].score then ties = ties + 1 end
    if state.winner == state.closing.leader then leaderWins = leaderWins + 1 end
    if seed % 50 == 0 then testing.breathe() end
  end
  print(("     all-auto: %d matches, %.1f turns and %.1f clocks a match, longest %d clocks, first to 5,000 won %d, tied %d"):format(matches, turns / matches, decisions / matches, longest, leaderWins, ties))
  truthy(longest < 200, "a match of clocks ran to " .. longest)
end)

test("players' nets are zero in 600 random matches, with half the turns absent at times", function()
  -- kit.fuzz only breathes every 50 rounds, and on a computer a match of tapping is long
  local steps = 0
  local function breather()
    steps = steps + 1
    if steps % 400 == 0 then testing.breathe() end
  end
  kit.fuzz(plugin, { rounds = 300, seats = { 2 }, stake = 100, stack = 500, pick = player, check = breather })
  kit.fuzz(plugin, { rounds = 200, seats = { 2 }, stake = 25, stack = 25, absent = 50, pick = player, seed = 99, check = breather })
  kit.fuzz(plugin, { rounds = 100, seats = { 2 }, stake = 500, stack = 300, absent = 15, seed = 7, check = breather })
end)

test("nobody moves out of turn and junk changes nothing", function()
  local state = table_(1, { 1, 5, 2, 3, 6, 6 })
  local before = kit.plain(state)
  local rng = testing.fastRng(1)
  local junk = { { 2, "die", 1 }, { 2, "roll" }, { 2, "bank" }, { 2, "clock" }, { 3, "die", 1 }, { 1, "die", 0 }, { 1, "die", 7 },
    { 1, "die", 1.5 }, { 1, "die", "2" }, { 1, "die", {} }, { 1, "die" }, { 1, "die", 0 / 0 }, { 1, "die", 1 / 0 }, { 1, "roll" }, { 1, "bank" },
    { 1, 42 }, { 1, "pick" }, { nil, "die", 1 }, { nil, "bank" }, { nil, "roll" }, { nil, "clock" } }
  for index, press in ipairs(junk) do
    eq(#rules.act(state, press[1], press[2], press[3], rng), 0, "junk " .. index)
    truthy(kit.same(before, state), "junk " .. index .. " changed the state")
  end
  local over = closing(0)
  rules.act(over, nil, "roll", nil, loaded({ 1, 2, 3, 4, 6, 6 }))
  tap(over, 2, 1)
  rules.act(over, 2, "bank")
  truthy(rules.done(over), "over")
  eq(#rules.act(over, nil, "roll", nil, rng), 0, "nothing after the end")
  eq(#rules.act(over, 1, "die", 1), 0, "nor a tap")
  eq(#rules.actions(over, 1), 0, "no buttons")
end)

test("a view is a view: public and private match, and the marks are in both", function()
  local state = table_(1, { 1, 5, 2, 3, 6, 6 })
  tap(state, 1, 1)
  local public, mine, theirs = rules.viewFor(state, nil), rules.viewFor(state, 1), rules.viewFor(state, 2)
  eq(public.me, nil, "nobody's")
  eq(mine.me, 1, "mine")
  eq(theirs.me, 2, "theirs")
  public.me, mine.me, theirs.me = nil, nil, nil
  truthy(kit.same(public, mine), "the same game")
  truthy(kit.same(public, theirs), "on both walls")
end)

test("events are small and name what the walls need", function()
  local rng = testing.fastRng(11)
  local state, events = rules.new(entries(), 1, rng, {})
  local function clean(list)
    for _, ev in ipairs(list) do
      truthy(type(ev.type) == "string", "typed")
      for key, value in pairs(ev) do truthy(type(value) ~= "table", "event " .. ev.type .. " holds " .. tostring(key)) end
      local seconds, sound = plugin.event(ev)
      truthy(type(seconds) == "number" and seconds > 0, "timed")
      if ev.type ~= "pick" then truthy(sound, ev.type .. " has a sound") end
    end
  end
  clean(events)
  for _ = 1, 2000 do
    if rules.done(state) then break end
    local waiting = rules.waitingOn(state)
    local id, value = rules.auto(state, waiting[1])
    clean(rules.act(state, waiting[1], id, value, rng))
  end
  truthy(rules.done(state), "over")
end)

test("every sound is one the owner picked or audio.lua names", function()
  local picks = require("lib.sound_picks")
  local named = { tap = true, chip = true, chipBig = true, warn = true }
  for _, ev in ipairs({ "roll", "pick", "bank", "farkle", "hot", "lastturn" }) do
    local _, sound = plugin.event({ type = ev })
    truthy(sound and (picks[sound] or named[sound]), ev .. " plays " .. tostring(sound))
  end
  local _, roll = plugin.event({ type = "roll" })
  eq(roll, "dice", "dice for a roll")
end)

test("every state survives textutils and a journal, marks and all", function()
  if not textutils then return end
  local rng = testing.fastRng(21)
  local state = rules.new(entries(), 1, rng, {})
  for _ = 1, 2000 do
    state = textutils.unserialize(textutils.serialize(state))
    for _, seat in ipairs({ 1, 2 }) do
      local view = rules.viewFor(state, seat)
      truthy(kit.same(view, textutils.unserialize(textutils.serialize(view))), "the view")
    end
    if rules.done(state) then break end
    local waiting = rules.waitingOn(state)
    if waiting[1] then rules.act(state, waiting[1], "die", 1) end
    state = textutils.unserialize(textutils.serialize(state))
    local id, value = rules.auto(state, waiting[1])
    truthy(#rules.act(state, waiting[1], id, value, rng) > 0, "moved")
  end
  truthy(rules.done(state), "over")
end)

test("a tapped die's region sits on the die, and only the thrower's wall has any", function()
  local state = table_(1, { 1, 5, 2, 3, 6, 6 })
  local view = rules.viewFor(state, 1)
  local regions = plugin.seatView.regions(view)
  eq(#regions, 6, "six dice")
  for index, region in ipairs(regions) do
    truthy(region.x >= 1 and region.x + region.w - 1 <= 121, "inside the wall's width")
    truthy(region.y >= 10 and region.y + region.h - 1 <= 53, "above the result")
    truthy(region.w >= 16 and region.h >= 10, "a big target")
    eq(region.id, "die", "taps a die")
    eq(region.value, index, "that die")
    local copy = kit.plain(state)
    truthy(#rules.act(copy, 1, region.id, region.value) > 0, "a tap does something")
    for other = index + 1, #regions do truthy(region.x + region.w <= regions[other].x, "no two overlap") end
  end
  eq(#plugin.seatView.regions(rules.viewFor(state, nil)), 0, "a public view has none")
  eq(#plugin.seatView.regions(rules.viewFor(state, 2)), 0, "nor the player waiting")
  state.phase = "throw"
  eq(#plugin.seatView.regions(rules.viewFor(state, 1)), 0, "nor between turns")
end)

test("every view draws on a screenless wall, seat and table", function()
  local canvas = require("lib.casino.canvas")
  local step = 0
  local function draws(state)
    step = step + 1
    if step % 7 ~= 0 then return end
    testing.breathe()
    for _, seat in ipairs({ 1, 2, false }) do
      local view = rules.viewFor(state, seat or nil)
      local c = canvas.new(nil, 121, 81)
      plugin.seatView.draw(c, view, nil, { seat = seat or 1, name = "Ann" })
      for _, t in ipairs({ 0, 0.5, 1 }) do
        plugin.seatView.draw(c, view, { ev = { type = "roll", seat = 1, count = #view.dice, running = 50 }, t = t }, { seat = seat or 1 })
      end
      for _, kind in ipairs({ "farkle", "hot", "bank", "lastturn", "pick" }) do
        plugin.seatView.draw(c, view, { ev = { type = kind, seat = 1, points = 300, lost = 300 }, t = 0.4 }, { seat = seat or 1 })
      end
      plugin.tableView.draw(c, view, nil, { waiting = {}, seats = {} })
    end
  end
  for seed = 1, 20 do
    kit.playRound(plugin, { seed = seed, stake = 25, stack = 100, pick = player, check = draws })
  end
  truthy(step > 1000, "the check ran")
end)

test("the help has the scoring table and fits the engine's one page", function()
  local ui = require("lib.casino.ui")
  local text, rows = {}, 0
  for _, line in ipairs(plugin.help()) do
    local words = type(line) == "table" and line[1] or line
    text[#text + 1] = words
    rows = rows + (words == "" and 1 or #ui.wrap(words, 115))
  end
  -- A page has no scrolling. Row 11 down to row 68 on a 121x81 wall, each wrapped at the wall less six
  truthy(rows <= 58, "the help runs to " .. rows .. " rows")
  local all = table.concat(text, " ")
  for _, needle in ipairs({ "100", "50", "1000", "2000", "3000", "1500", "2500", "500", "5,000", "straight", "Three pairs", "Two triples", "hot" }) do
    truthy(all:find(needle, 1, true), "the help has " .. needle)
  end
end)

test("help and the plugin are in order", function()
  eq(plugin.id, "farkle", "id")
  eq(plugin.kind, "players", "kind")
  eq(plugin.minSeats, 2, "min")
  eq(plugin.maxSeats, 2, "max")
  truthy(plugin.stakes[1] > 0, "stakes")
  truthy(plugin.tableView.draw and plugin.seatView.draw, "pictures")
end)
