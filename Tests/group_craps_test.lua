-- group_craps_test.lua
-- Shared Craps. The returns are proved by enumeration: every roll of the real rules, weighted exactly, with no sampling. A roll that
-- changes nothing is a loop and is solved as one, so a point that could go on for ever is still an exact sum.

local canvas = require("lib.casino.canvas")
local kit = require("group_kit")
local t = require("testing")

local plugin = kit.plugin("BigTable", "craps")
local rules = plugin.rules

local NUMBERS = { 4, 5, 6, 8, 9, 10 }
local ONE = { [2] = 1, [3] = 2, [4] = 3, [5] = 4, [6] = 5, [7] = 6, [8] = 5, [9] = 4, [10] = 3, [11] = 2, [12] = 1 }

--- A generator that gives these dice, as the two faces in order.
local function scripted(...)
  local faces, index = { ... }, 0
  return { below = function()
    index = index + 1
    return faces[index] - 1
  end }
end

--- A pair of faces that makes this total.
local function pair(total)
  if total <= 7 then return 1, total - 1 end
  return 6, total - 6
end

--- Seats, each { pass, dont, field }, with seat numbers from 1.
local function deal(list, button, keep)
  local entries = {}
  for index, bets in ipairs(list) do
    local total = 0
    for _, amount in pairs(bets) do total = total + amount end
    entries[index] = { seat = index, name = "P" .. index, bet = total, bets = bets }
  end
  return rules.new(entries, button or 1, nil, keep or {}), entries
end

local function solo(bets)
  return (deal({ bets }))
end

local function player(state, seat)
  return state.players[seat or 1]
end

--- The computer's half of a roll, and the shooter's press before it.
local function roll(state, d1, d2)
  if state.shooter then
    local events = rules.act(state, state.shooter, "roll")
    t.truthy(events and #events > 0, "the shooter can roll")
  end
  local events = rules.act(state, nil, "dice", nil, scripted(d1, d2))
  t.truthy(events and #events > 0, "the computer's throw happened")
  return events
end

local function rollTotal(state, total)
  return roll(state, pair(total))
end

local function press(state, seat, id, value)
  local events = rules.act(state, seat, id, value)
  t.truthy(events and #events > 0, id .. " should be allowed")
end

local function isOffered(state, seat, id, value)
  for _, action in ipairs(rules.actions(state, seat)) do
    if action.id == id and (value == nil or action.value == value) then return action end
  end
  return nil
end

-- ------------------------------------------------------------------ the exact returns

--- Everything that can change what a round is still worth.
local function position(state)
  local parts = { state.stage, tostring(state.point) }
  for _, one in ipairs(state.players) do
    parts[#parts + 1] = table.concat({ one.net, one.pass.bet, one.pass.odds, one.dont.bet, one.dont.odds, one.field, one.comeBox, one.dontBox }, ",")
    for _, number in ipairs(NUMBERS) do
      local come, lay = one.come[number], one.lay[number]
      parts[#parts + 1] = (come and (come.bet .. "+" .. come.odds) or "-") .. "/" .. (lay and (lay.bet .. "+" .. lay.odds) or "-")
    end
  end
  return table.concat(parts, "|")
end

--- What seat 1's round is worth from here, exactly: each of the 36 rolls, with the rolls that change nothing solved out.
local function worth(state, memo)
  memo = memo or {}
  if rules.done(state) then return rules.nets(state)[1] end
  local key = position(state)
  if memo[key] then return memo[key] end
  local sum, loops = 0, 0
  for d1 = 1, 6 do
    for d2 = 1, 6 do
      local copy = kit.plain(state)
      roll(copy, d1, d2)
      if position(copy) == key then loops = loops + 1 else sum = sum + worth(copy, memo) end
    end
  end
  memo[key] = sum / (36 - loops)
  return memo[key]
end

--- A state with this point on and nothing on the line, so a Come bet can be priced by itself.
local function bareAt(number, opening)
  local state = solo({ pass = opening })
  rollTotal(state, number)
  player(state).pass.bet = 0
  return state
end

--- The weighted worth over the point, for what is priced after a come out.
local function overPoints(fn)
  local total, weight = 0, 0
  for _, number in ipairs(NUMBERS) do
    total = total + fn(number) * ONE[number]
    weight = weight + ONE[number]
  end
  return total / weight
end

local returns = {}

function returns.pass()
  return 1 + worth(solo({ pass = 990 })) / 990
end

function returns.dont()
  return 1 + worth(solo({ dont = 990 })) / 990
end

function returns.field()
  return 1 + worth(solo({ field = 990 })) / 990
end

function returns.fieldOnPoint()
  return 1 + overPoints(function(number)
    local state = bareAt(number, 990)
    press(state, 1, "field")
    return worth(state)
  end) / 990
end

function returns.come()
  return 1 + overPoints(function(number)
    local state = bareAt(number, 990)
    press(state, 1, "come")
    return worth(state)
  end) / 990
end

function returns.dontCome()
  return 1 + overPoints(function(number)
    local state = bareAt(number, 990)
    press(state, 1, "dontcome")
    return worth(state)
  end) / 990
end

--- All the odds a bet takes, and what the round is worth with them and without.
local function oddsReturn(start, value)
  local staked, change = 0, 0
  for _, number in ipairs(NUMBERS) do
    local bare, backed = start(number), start(number)
    local added = 0
    while isOffered(backed, backed.shooter, "odds", value(number)) do
      added = added + isOffered(backed, backed.shooter, "odds", value(number)).cost
      press(backed, backed.shooter, "odds", value(number))
    end
    t.truthy(added > 0, "odds were offered on " .. number)
    staked = staked + added * ONE[number]
    change = change + (worth(backed) - worth(bare)) * ONE[number]
  end
  return 1 + change / staked
end

--- The same, over a line bet.
function returns.passOdds()
  return oddsReturn(function(number)
    local state = solo({ pass = 300 })
    rollTotal(state, number)
    return state
  end, function() return "pass" end)
end

function returns.dontOdds()
  return oddsReturn(function(number)
    local state = solo({ dont = 300 })
    rollTotal(state, number)
    return state
  end, function() return "dont" end)
end

--- And over a Come and a Don't Come that have moved to a number, with the point somewhere else.
local function comeStart(id)
  return function(number)
    local point = number == 6 and 8 or 6
    local state = bareAt(point, 300)
    press(state, 1, id)
    rollTotal(state, number)
    return state
  end
end

function returns.comeOdds()
  return oddsReturn(comeStart("come"), function(number) return "c" .. number end)
end

function returns.dontComeOdds()
  return oddsReturn(comeStart("dontcome"), function(number) return "d" .. number end)
end

--- The whole return table against the published figures, to the two places they are given.
local TARGETS = {
  { "pass", 0.9859, 1 - 7 / 495 }, { "dont", 0.9864, 1 - 27 / 1980 }, { "field", 0.9722, 1 - 1 / 36 }, { "fieldOnPoint", 0.9722, 1 - 1 / 36 },
  { "come", 0.9859, 1 - 7 / 495 }, { "dontCome", 0.9864, 1 - 27 / 1980 },
  { "passOdds", 1, 1 }, { "dontOdds", 1, 1 }, { "comeOdds", 1, 1 }, { "dontComeOdds", 1, 1 },
}

local function checkReturns()
  for _, target in ipairs(TARGETS) do
    local value = returns[target[1]]()
    t.near(value, target[2], 0.00005, target[1] .. " to two places")
    t.near(value, target[3], 1e-9, target[1] .. " exactly")
  end
end

t.test("craps returns are exact: Pass 98.59, Don't Pass 98.64, Field 97.22, odds 100", checkReturns)

--- A wrong table must fail the check above, or the check proves nothing.
local function mutant(what, change, restore)
  change()
  local ok = pcall(checkReturns)
  restore()
  t.truthy(not ok, what .. " should have failed the return check")
end

t.test("craps returns fail on a wrong table", function()
  mutant("12 winning on the Don't side, with no bar", function() rules.DONT_FIRST[12] = "win" end, function() rules.DONT_FIRST[12] = "push" end)
  mutant("12 paying 2:1 in the Field", function() rules.FIELD[12] = 2 end, function() rules.FIELD[12] = 3 end)
  mutant("2 paying even money in the Field", function() rules.FIELD[2] = 1 end, function() rules.FIELD[2] = 2 end)
  mutant("11 not winning on the line", function() rules.PASS_FIRST[11] = nil end, function() rules.PASS_FIRST[11] = "win" end)
  mutant("odds on six at 7:5", function() rules.TAKE_ODDS[6] = { 7, 5 } end, function() rules.TAKE_ODDS[6] = { 6, 5 } end)
  mutant("laying five at 3:5", function() rules.LAY_ODDS[5] = { 3, 5 } end, function() rules.LAY_ODDS[5] = { 2, 3 } end)
  checkReturns()
end)

-- ------------------------------------------------------------------ the rules, one roll at a time

t.test("craps the come out", function()
  for total, verdict in pairs({ [7] = 10, [11] = 10, [2] = -10, [3] = -10, [12] = -10 }) do
    local state = solo({ pass = 10 })
    rollTotal(state, total)
    t.truthy(rules.done(state), total .. " ends a round on the line")
    t.eq(rules.nets(state)[1], verdict, "Pass on " .. total)
  end
  for total, verdict in pairs({ [7] = -10, [11] = -10, [2] = 10, [3] = 10, [12] = 0 }) do
    local state = solo({ dont = 10 })
    rollTotal(state, total)
    t.truthy(rules.done(state), total .. " ends a round on the Don't side")
    t.eq(rules.nets(state)[1], verdict, "Don't Pass on " .. total)
  end
  for _, number in ipairs(NUMBERS) do
    local state = solo({ pass = 10 })
    rollTotal(state, number)
    t.eq(state.point, number, "the point")
    t.eq(state.stage, "point")
    t.truthy(not rules.done(state), "a point goes on")
  end
end)

t.test("craps the point: made, seven out, and rolls that do nothing", function()
  local state = solo({ pass = 10 })
  rollTotal(state, 6)
  rollTotal(state, 5)
  rollTotal(state, 11)
  rollTotal(state, 2)
  t.truthy(not rules.done(state), "nothing but the point or a seven ends it")
  rollTotal(state, 6)
  t.truthy(rules.done(state), "the point made")
  t.eq(rules.nets(state)[1], 10)
  state = solo({ dont = 10 })
  rollTotal(state, 6)
  rollTotal(state, 7)
  t.eq(rules.nets(state)[1], 10, "Don't Pass wins a seven out")
  t.truthy(state.sevenOut)
  state = solo({ dont = 10 })
  rollTotal(state, 6)
  rollTotal(state, 6)
  t.eq(rules.nets(state)[1], -10, "Don't Pass loses a made point")
end)

t.test("craps every total in the Field", function()
  local pays = { [2] = 20, [3] = 10, [4] = 10, [5] = -10, [6] = -10, [7] = -10, [8] = -10, [9] = 10, [10] = 10, [11] = 10, [12] = 30 }
  for total, net in pairs(pays) do
    local state = solo({ field = 10 })
    rollTotal(state, total)
    t.truthy(rules.done(state), "Field alone is one roll")
    t.eq(rules.nets(state)[1], net, "Field on " .. total)
  end
end)

t.test("craps Come moves to its number, and rolls out after the point", function()
  local state = solo({ pass = 10 })
  rollTotal(state, 6)
  press(state, 1, "come")
  t.eq(player(state).comeBox, 10)
  rollTotal(state, 9)
  t.eq(player(state).comeBox, 0)
  t.eq(player(state).come[9].bet, 10)
  press(state, 1, "come")
  rollTotal(state, 6)
  t.eq(state.stage, "runout", "the point is made and Come bets remain")
  t.eq(rules.nets(state)[1], 10, "Pass is paid")
  t.eq(player(state).come[6].bet, 10, "the box moved to the number that made the point")
  t.truthy(not isOffered(state, 1, "come") and not isOffered(state, 1, "field") and not isOffered(state, 1, "odds"), "no new bets in a run out")
  rollTotal(state, 9)
  t.eq(rules.nets(state)[1], 20, "Come on nine is paid")
  t.truthy(not rules.done(state))
  rollTotal(state, 7)
  t.truthy(rules.done(state), "a seven ends a run out")
  t.eq(rules.nets(state)[1], 10, "Come on six is lost")
end)

--- Pass 10 with a point of 6, Come 10 moved to 5 with 20 of odds behind it, then the point made: a run out with odds on the Come.
local function backedRunOut()
  local state = solo({ pass = 10 })
  rollTotal(state, 6)
  press(state, 1, "come")
  rollTotal(state, 5)
  press(state, 1, "odds", "c5")
  press(state, 1, "odds", "c5")
  t.eq(player(state).come[5].odds, 20, "the odds behind the Come")
  rollTotal(state, 6)
  t.eq(state.stage, "runout", "the point is made")
  t.eq(rules.nets(state)[1], 10, "Pass is paid")
  return state
end

t.test("craps a seven after the point is made is no seven out: the odds go back and the shooter keeps the dice", function()
  local state = backedRunOut()
  rollTotal(state, 7)
  t.truthy(rules.done(state), "it ends the run out")
  t.eq(rules.nets(state)[1], 0, "the Come's 10 is lost and its 20 of odds go back")
  t.truthy(not state.sevenOut, "this is no seven out")
  t.truthy(state.call ~= "SEVEN OUT", "and the table does not call one")
  local keep = {}
  rules.finish(state, keep)
  t.eq(keep.passDice, false, "the shooter keeps the dice")
end)

t.test("craps odds that are off in a run out win nothing either, so they are no free roll", function()
  local state = backedRunOut()
  rollTotal(state, 5)
  t.truthy(rules.done(state), "the last Come is settled")
  t.eq(rules.nets(state)[1], 20, "Pass 10 and Come 10, and the odds only go back")
end)

t.test("craps a seven out before the point is made still takes the odds and passes the dice", function()
  local state = solo({ pass = 10 })
  rollTotal(state, 6)
  press(state, 1, "come")
  rollTotal(state, 5)
  press(state, 1, "odds", "c5")
  rollTotal(state, 7)
  t.truthy(state.sevenOut, "a seven out")
  t.eq(rules.nets(state)[1], -30, "Pass 10, Come 10 and its 10 of odds")
  local keep = {}
  rules.finish(state, keep)
  t.eq(keep.passDice, true, "the dice pass")
end)

t.test("craps a new Come on a number with one on it: the old one is paid and the new one moves", function()
  local state = solo({ pass = 10 })
  rollTotal(state, 8)
  press(state, 1, "come")
  rollTotal(state, 6)
  press(state, 1, "come")
  rollTotal(state, 6)
  t.eq(rules.nets(state)[1], 10)
  t.eq(player(state).come[6].bet, 10)
end)

t.test("craps Don't Come: first roll, moves, and a seven pays it", function()
  local state = solo({ pass = 10 })
  rollTotal(state, 6)
  press(state, 1, "dontcome")
  rollTotal(state, 12)
  t.eq(rules.nets(state)[1], 0, "12 is barred")
  press(state, 1, "dontcome")
  rollTotal(state, 11)
  t.eq(rules.nets(state)[1], -10, "11 loses a Don't Come on its first roll")
  press(state, 1, "dontcome")
  rollTotal(state, 3)
  t.eq(rules.nets(state)[1], 0, "3 wins it")
  press(state, 1, "dontcome")
  rollTotal(state, 9)
  t.eq(player(state).lay[9].bet, 10)
  rollTotal(state, 7)
  t.truthy(rules.done(state))
  t.eq(rules.nets(state)[1], 0, "the seven loses Pass and pays Don't Come")
end)

t.test("craps a bet in a box on a seven: Come wins, Don't Come loses", function()
  local state = solo({ pass = 10 })
  rollTotal(state, 6)
  press(state, 1, "come")
  rollTotal(state, 7)
  t.eq(rules.nets(state)[1], 0)
  state = solo({ pass = 10 })
  rollTotal(state, 6)
  press(state, 1, "dontcome")
  rollTotal(state, 7)
  t.eq(rules.nets(state)[1], -20)
end)

t.test("craps odds are whole, at most three times the bet, and pay true", function()
  for _, bet in ipairs({ 10, 11, 12, 13, 15, 17, 25, 33, 100, 999 }) do
    for _, number in ipairs(NUMBERS) do
      for _, side in ipairs({ "pass", "dont" }) do
        local state = solo({ [side] = bet })
        rollTotal(state, number)
        local price = (side == "pass" and rules.TAKE_ODDS or rules.LAY_ODDS)[number]
        while isOffered(state, 1, "odds", side) do press(state, 1, "odds", side) end
        local record = player(state)[side]
        t.truthy(record.odds <= bet * 3, "no more than 3x")
        t.eq(record.odds % price[2], 0, "a multiple the price pays whole")
        t.truthy(record.odds > bet * 3 - price[2] - 1 or player(state).cap - rules.ceiling(state, player(state)) < price[2], "as near 3x as whole payouts allow")
        local win = record.odds * price[1] / price[2]
        t.eq(win, math.floor(win), "the payout is whole")
        local made = (side == "pass") and number or 7
        local net = bet + win
        rollTotal(state, made)
        t.eq(rules.nets(state)[1], net, side .. " on " .. number .. " with odds, bet " .. bet)
      end
    end
  end
end)

t.test("craps odds a bet too small to pay whole are not offered", function()
  local state = solo({ dont = 1 })
  rollTotal(state, 6)
  t.truthy(not isOffered(state, 1, "odds", "dont"), "3 cannot lay six at 5:6")
end)

t.test("craps keeps a seat inside what the host covered", function()
  local state, entries = deal({ { pass = 10 } })
  local cap = rules.maxWin(entries[1])
  rollTotal(state, 4)
  for _ = 1, 40 do
    local bets = rules.actions(state, 1)
    if #bets < 2 then break end
    press(state, 1, bets[2].id, bets[2].value)
    t.truthy(rules.ceiling(state, player(state)) <= cap, "the best case stays inside maxWin")
  end
  t.truthy(rules.ceiling(state, player(state)) > 0.7 * cap, "a seat can get near its limit")
  t.truthy(rules.viewFor(state, 1).mine.limit == false or #rules.actions(state, 1) == 1)
end)

t.test("craps the shooter rolls, and a seat without the dice cannot", function()
  local state = deal({ { pass = 10 }, { dont = 10 } }, 2)
  t.eq(state.shooter, 2, "the button shoots first")
  t.eq(#rules.waitingOn(state), 1)
  t.eq(rules.waitingOn(state)[1], 2)
  t.eq(#rules.act(state, 1, "roll"), 0)
  t.eq(state.rolling, false)
end)

t.test("craps between rolls every seat may bet, and the roll waits for nobody", function()
  local state = deal({ { pass = 10 }, { pass = 10 }, { field = 10 } })
  rollTotal(state, 6)
  t.eq(#rules.waitingOn(state), 3, "all three may act")
  t.truthy(isOffered(state, 3, "come"), "a seat with no line bet can still come in")
  press(state, 2, "pass")
  t.eq(#rules.waitingOn(state), 2, "no bet takes that seat off the clock")
  press(state, 1, "roll")
  t.eq(#rules.waitingOn(state), 0, "the press closes betting for everyone, which clears every clock")
  t.eq(#rules.act(state, 3, "come"), 0, "too late")
  local id = rules.auto(state, nil)
  t.eq(#rules.act(state, nil, id, nil, scripted(1, 2)) > 0, true)
  t.eq(#rules.waitingOn(state), 3, "a roll gives everyone a fresh window")
end)

t.test("craps a shooter who times out loses the dice, and an empty table rolls by itself", function()
  local state = deal({ { pass = 10 }, { pass = 10 } })
  rollTotal(state, 6)
  local rng = scripted(1, 2, 2, 3)
  t.eq(rules.auto(state, 2), "pass")
  t.eq(rules.auto(state, 1), "skip")
  t.truthy(#rules.act(state, 1, "skip") > 0)
  t.eq(state.shooter, 2, "the next seat has the dice")
  t.eq(#rules.waitingOn(state), 0, "the throw still happens")
  t.truthy(#rules.act(state, nil, rules.auto(state, nil), nil, rng) > 0)
  t.truthy(#rules.waitingOn(state) >= 1)
  t.truthy(#rules.act(state, 2, "skip") > 0)
  t.eq(state.shooter, nil, "nobody left to shoot")
  t.truthy(#rules.act(state, nil, "dice", nil, rng) > 0)
  t.eq(#rules.waitingOn(state), 0, "the computer rolls with nobody shooting")
  t.truthy(#rules.act(state, nil, "dice", nil, scripted(3, 4)) > 0)
  t.truthy(rules.done(state))
end)

t.test("craps the dice stay until a seven out, then go round the table", function()
  local keep = {}
  local state = deal({ { pass = 10 }, { pass = 10 }, { pass = 10 } }, 2, keep)
  rollTotal(state, 7)
  rules.finish(state, keep)
  state = deal({ { pass = 10 }, { pass = 10 }, { pass = 10 } }, 3, keep)
  t.eq(state.shooter, 2, "a natural keeps the dice, whatever the button says")
  rollTotal(state, 6)
  rollTotal(state, 7)
  rules.finish(state, keep)
  state = deal({ { pass = 10 }, { pass = 10 }, { pass = 10 } }, 1, keep)
  t.eq(state.shooter, 3, "a seven out passes them on")
  rollTotal(state, 6)
  rollTotal(state, 7)
  rules.finish(state, keep)
  state = deal({ { pass = 10 }, { pass = 10 } }, 1, keep)
  t.eq(state.shooter, 1, "and round to the start")
end)

t.test("craps a shooter who has left the round's entries gives way", function()
  local keep = { shooter = 5, passDice = false }
  local state = deal({ { pass = 10 }, { pass = 10 } }, 2, keep)
  t.eq(state.shooter, 1, "seat 5 has no bet, so the seats wrap round")
end)

t.test("craps illegal input does nothing", function()
  local state = deal({ { pass = 10, field = 10 }, { pass = 10 } })
  local function refused(seat, id, value, rng)
    local before = kit.plain(state)
    local events = rules.act(state, seat, id, value, rng or scripted(1, 1))
    t.truthy(not events or #events == 0, tostring(id) .. " should be refused")
    t.truthy(kit.same(before, state), tostring(id) .. " changed the state")
  end
  refused(1, "come")                -- before a point
  refused(1, "odds", "pass")
  refused(1, "field")
  refused(2, "roll")                -- not the shooter
  refused(2, "skip")
  refused(nil, "dice")              -- the shooter has not pressed
  refused(nil, "roll")
  refused(9, "roll")                -- nobody in that seat
  refused(1, "nonsense")
  refused(1, nil)
  rollTotal(state, 5)
  refused(1, "pass")                -- the shooter has no NO BET
  refused(1, "odds", "c6")          -- no such bet
  refused(1, "odds", "dont")
  refused(1, "odds")
  refused(1, "odds", 40)
  refused(2, "roll")
  press(state, 1, "come")
  refused(1, "come")                -- one in the box at a time
  press(state, 1, "field")
  refused(1, "field")
  press(state, 1, "roll")
  refused(1, "roll")                -- already in the air
  refused(2, "come")
  refused(1, "skip")
  t.truthy(#rules.act(state, nil, "dice", nil, scripted(2, 3)) > 0, "the round went on")
  t.truthy(rules.done(state) or state.stage == "runout", "a five made the point")
  if rules.done(state) then refused(1, "roll") end
end)

t.test("craps a pushed line costs nothing and a push is a push", function()
  local state = solo({ dont = 10 })
  rollTotal(state, 12)
  t.eq(rules.result(state, 1).kind, "push")
  state = solo({ pass = 10 })
  rollTotal(state, 7)
  t.eq(rules.result(state, 1).kind, "win")
  state = solo({ pass = 10 })
  rollTotal(state, 2)
  t.eq(rules.result(state, 1).kind, "lose")
  t.eq(rules.result(state, nil).title, "SNAKE EYES")
end)

t.test("craps a round with nothing on a line sets no point", function()
  local state = deal({ { field = 10 }, { field = 25 } })
  rollTotal(state, 5)
  t.truthy(rules.done(state))
  t.eq(state.point, nil)
end)

t.test("craps with no spots named the whole bet goes on Pass", function()
  local state = rules.new({ { seat = 1, name = "A", bet = 50 } }, 1, nil, {})
  t.eq(player(state).pass.bet, 50)
  t.eq(player(state).unit, 50)
end)

t.test("craps a view never shows another seat's own figures, and nothing is copied from state", function()
  local state = deal({ { pass = 13 }, { dont = 17 } })
  state.secret = "HIDDEN"
  player(state, 1).secret = "HIDDEN"
  player(state, 2).secret = "HIDDEN"
  player(state, 2).come[9] = { bet = 41, odds = 0 }
  player(state, 2).net = 777
  player(state, 2).log[1] = { label = "SECRET LOG", amount = 777 }
  player(state, 2).unit = 999
  rollTotal(state, 5)
  player(state, 2).net = 777
  local mine = rules.viewFor(state, 1)
  local public = rules.viewFor(state, nil)
  t.truthy(not kit.shows(mine, "HIDDEN") and not kit.shows(public, "HIDDEN"), "state fields do not ride along")
  t.truthy(not kit.shows(mine, 777), "another seat's running net stays out of a seat's view")
  t.truthy(not kit.shows(mine, 999), "and their unit")
  t.truthy(not kit.shows(mine, "SECRET LOG"), "and their log")
  t.eq(public.mine, nil, "the public view is nobody's")
  t.truthy(not kit.shows(public, 777), "the wall does not show a running net")
  t.truthy(mine.mine.pass.bet == 13 and not kit.shows(mine.mine, 17), "a seat's own figures are its own")
  t.eq(rules.viewFor(state, 7).mine, nil, "a stranger gets the public view")
  -- A roll is public, and the dice not yet thrown exist nowhere
  local stateText = kit.plain(state)
  stateText.players, stateText.secret = nil, nil
  for key in pairs(stateText) do
    t.truthy(not tostring(key):find("seed") and not tostring(key):find("rng"), "the state holds no randomness: " .. tostring(key))
  end
end)

--- A view drawn at each size, for a mistake that would only show as a line on a screen.
local function drawAll(view, seatView)
  local wall = canvas.new(nil, 121, 81)
  local seat = canvas.new(nil, 78, 52)
  plugin.tableView.draw(wall, view, nil, {})
  plugin.seatView.draw(seat, seatView, nil, { seat = 1, name = "P1" })
  local ev = { type = "roll", d1 = 3, d2 = 4, total = 7, call = "SEVEN", point = 6, n = 2 }
  for _, moment in ipairs({ 0, 0.3, 0.79, 0.8, 1 }) do
    plugin.tableView.draw(wall, view, { ev = ev, t = moment }, {})
    plugin.seatView.draw(seat, seatView, { ev = ev, t = moment }, { seat = 1, name = "P1" })
  end
end

t.test("craps every stage draws at the real sizes, with or without a seat", function()
  local state = deal({ { pass = 10 }, { dont = 25 }, { field = 25 } })
  drawAll(rules.viewFor(state, nil), rules.viewFor(state, 1))
  rollTotal(state, 6)
  drawAll(rules.viewFor(state, nil), rules.viewFor(state, 1))
  press(state, 1, "come")
  press(state, 1, "odds", "pass")
  press(state, 2, "dontcome")
  rollTotal(state, 9)
  press(state, 1, "odds", "c9")
  drawAll(rules.viewFor(state, nil), rules.viewFor(state, 1))
  rollTotal(state, 6)
  drawAll(rules.viewFor(state, nil), rules.viewFor(state, 1))
  drawAll(rules.viewFor(state, nil), rules.viewFor(state, nil))
  rollTotal(state, 7)
  t.truthy(rules.done(state))
  drawAll(rules.viewFor(state, nil), rules.viewFor(state, 1))
  plugin.seatView.draw(canvas.new(nil, 78, 52), {}, nil, {})
  plugin.tableView.draw(canvas.new(nil, 121, 81), {}, nil, {})
end)

t.test("craps the help and events are safe to show", function()
  t.truthy(#plugin.help() > 3)
  for _, kind in ipairs({ "comeout", "throw", "roll", "bet", "pass", "shooter", "unknown" }) do
    local seconds = plugin.event({ type = kind })
    t.truthy(seconds > 0, kind .. " has a length")
  end
  local state = solo({ pass = 10 })
  local events = roll(state, 1, 2)
  t.eq(events[1].total, 3)
  t.eq(events[1].type, "roll")
end)

-- ------------------------------------------------------------------ at random

--- Every bet resolved once: nothing is left riding, and no seat lost more than it put down.
local function checkFinished(state)
  for _, one in ipairs(state.players) do
    t.eq(one.pass.bet + one.pass.odds + one.dont.bet + one.dont.odds + one.field + one.comeBox + one.dontBox, 0, "nothing is left on the felt")
    t.truthy(not next(one.come) and not next(one.lay), "nothing is left on a number")
    t.truthy(one.net >= -one.staked, "a seat cannot lose more than it staked")
  end
end

local function inside(state, entries)
  for index, entry in ipairs(entries) do
    local one = state.players[index]
    -- Ten buttons on a 78 wide seat leave 11 cells each
    for _, action in ipairs(rules.actions(state, entry.seat)) do
      t.truthy(#action.label <= 10, "the label fits a small button: " .. action.label)
      t.truthy(#(action.sub or "") <= 8, "the sub fits a small button")
    end
    t.truthy(rules.ceiling(state, one) <= rules.maxWin(entry), "the best case stays inside maxWin")
    t.truthy(one.pass.odds <= 3 * one.pass.bet and one.dont.odds <= 3 * one.dont.bet, "odds stay inside 3x on the line")
    for _, number in ipairs(NUMBERS) do
      local come, lay = one.come[number], one.lay[number]
      t.truthy(not come or come.odds <= 3 * come.bet, "odds stay inside 3x on a Come")
      t.truthy(not lay or lay.odds <= 3 * lay.bet, "odds stay inside 3x on a Don't Come")
    end
  end
end

local OPENINGS = {
  { bet = 10, bets = { pass = 10 } }, { bet = 10, bets = { dont = 10 } }, { bet = 25, bets = { field = 25 } },
  { bet = 60, bets = { pass = 25, field = 35 } }, { bet = 150, bets = { pass = 50, dont = 100 } }, { bet = 37 },
  { bet = 1000, bets = { pass = 700, dont = 200, field = 100 } },
}

t.test("craps keeps the contract through 2100 random rounds", function()
  local rounds = 300
  for index, opening in ipairs(OPENINGS) do
    kit.fuzz(plugin, { rounds = rounds, seats = { 1, 3, 8 }, bet = opening.bet, bets = opening.bets, absent = 15, seed = 1000 + index, check = inside, steps = 40000 })
    t.breathe()
  end
end)

t.test("craps resolves every bet once across random rounds, with everyone away some of the time", function()
  local rng = t.fastRng(4242)
  local keep = {}
  local seen = { over = 0, runout = 0, computer = 0 }
  for round = 1, 400 do
    local opening = OPENINGS[rng:below(#OPENINGS) + 1]
    local absent = ({ 0, 20, 100 })[rng:below(3) + 1]
    local state, entries = kit.playRound(plugin, {
      seats = rng:below(8) + 1, bet = opening.bet, bets = opening.bets, rng = rng, keep = keep, absent = absent, check = function(live, list)
        inside(live, list)
        if live.stage == "runout" then seen.runout = seen.runout + 1 end
        if not live.shooter then seen.computer = seen.computer + 1 end
      end,
    })
    checkFinished(state)
    local nets = kit.checkEnd(plugin, state, entries)
    t.eq(#entries, #state.players)
    for _, one in ipairs(state.players) do t.eq(nets[one.seat], one.net, "nets is the running net") end
    rules.finish(state, keep)
    seen.over = seen.over + 1
    if round % 50 == 0 then t.breathe() end
  end
  t.truthy(seen.runout > 0 and seen.computer > 0, "the run out and the computer's rolls both happened")
end)

t.test("craps a state and its views survive the journal", function()
  local text = rawget(_G, "textutils")
  if not text then return end -- the emulator has textutils, and plain Lua is covered by kit.plain in the rounds above
  local rng = t.fastRng(99)
  for _ = 1, 60 do
    kit.playRound(plugin, { seats = 4, bet = 150, bets = { pass = 50, dont = 100 }, rng = rng, check = function(state)
      local back = text.unserialize(text.serialize(state))
      t.truthy(kit.same(kit.plain(state), back), "the state comes back the same")
      local view = text.unserialize(text.serialize(rules.viewFor(state, 1)))
      t.truthy(kit.same(view, rules.viewFor(state, 1)), "a view comes back the same")
    end })
    t.breathe()
  end
end)

t.test("craps a state resumes from any step", function()
  local state = deal({ { pass = 25 }, { dont = 30 } })
  rollTotal(state, 8)
  press(state, 1, "come")
  press(state, 2, "odds", "dont")
  state = kit.plain(state)
  press(state, 1, "odds", "pass")
  rollTotal(state, 4)
  state = kit.plain(state)
  rollTotal(state, 7)
  t.truthy(rules.done(state))
  checkFinished(state)
end)
