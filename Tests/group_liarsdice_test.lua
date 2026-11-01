-- group_liarsdice_test.lua
-- Liar's Dice on Duel: the bidding ladder, wild ones, who loses a die, the stake, and that a seat learns nothing of the other's dice.

local kit = require("group_kit")
local testing = require("testing")
local eq, test, truthy = testing.eq, testing.test, testing.truthy

local plugin = kit.plugin("Duel", "liarsdice")
local rules = plugin.rules

local function entries(stake, stackA, stackB)
  return { { seat = 1, name = "Ann", stack = stackA or 1000, stake = stake or 100 }, { seat = 2, name = "Bea", stack = stackB or 1000, stake = stake or 100 } }
end

local function fresh(seed, stake, stackA, stackB, button)
  local state = rules.new(entries(stake, stackA, stackB), button or 1, testing.fastRng(seed or 7), {})
  return state
end

--- Put a bid on the table through the draft, as a player does.
local function bid(state, seat, count, face)
  state.draft = { count = count, face = face }
  truthy(#rules.act(state, seat, "bid") > 0, "bid " .. count .. " x " .. face)
end

local function ids(list)
  local out = {}
  for _, action in ipairs(list) do out[action.id] = action end
  return out
end

--- A random move for kit: mostly taps on the picker, so the draft goes everywhere it can.
local function picker(state, seat, actions, rng)
  local view = rules.viewFor(state, seat)
  if view.draft and rng:below(3) > 0 then
    if rng:below(2) == 0 then
      local live = {}
      for count, ok in ipairs(view.counts) do if ok then live[#live + 1] = count end end
      if #live > 0 then return "count", live[rng:below(#live) + 1] end
    else
      local live = {}
      for face, ok in ipairs(view.faces) do if ok then live[#live + 1] = face end end
      if #live > 0 then return "face", live[rng:below(#live) + 1] end
    end
  end
  return nil
end

--- Anything with a dice field in it, anywhere but where this seat may see.
local function foreignDice(view, seat)
  if view.phase == "reveal" or view.over then return false end
  for _, player in ipairs(view.players) do
    if player.dice then return true end
  end
  return seat == nil and view.mine ~= nil
end

test("five dice each, sorted, hidden and in play", function()
  local state = fresh(3)
  eq(#state.players[1].dice, 5, "first")
  eq(#state.players[2].dice, 5, "second")
  for index = 2, 5 do truthy(state.players[1].dice[index - 1] <= state.players[1].dice[index], "sorted") end
  eq(rules.viewFor(state, nil).total, 10, "in play")
  eq(rules.waitingOn(state)[1], 1, "the button opens")
  eq(rules.waitingOn(fresh(3, 100, 1000, 1000, 2))[1], 2, "the other button opens")
end)

test("a bid goes up by count, or by face within a count, and ones rank top", function()
  local b = { count = 3, face = 4 }
  truthy(rules.raises(nil, 1, 2), "anything opens")
  truthy(rules.raises(b, 3, 5), "same count, higher face")
  truthy(rules.raises(b, 3, 1), "same count, ones are above sixes")
  truthy(rules.raises(b, 4, 2), "higher count, lower face")
  truthy(not rules.raises(b, 3, 4), "the same bid")
  truthy(not rules.raises(b, 3, 3), "same count, lower face")
  truthy(not rules.raises(b, 2, 6), "lower count")
  truthy(not rules.raises({ count = 3, face = 1 }, 3, 6), "nothing on that count beats ones")
end)

test("ones are wild unless ones are bid", function()
  local state = fresh()
  state.players[1].dice = { 1, 1, 2, 5, 5 }
  state.players[2].dice = { 1, 3, 3, 5, 6 }
  eq(rules.counted(state, 5), 6, "three fives and three ones")
  eq(rules.counted(state, 3), 5, "two threes and three ones")
  eq(rules.counted(state, 1), 3, "ones only count as ones")
end)

test("a true bid costs the caller a die, and the caller opens next", function()
  local state = fresh()
  state.players[1].dice = { 1, 1, 2, 5, 5 }
  state.players[2].dice = { 1, 3, 3, 5, 6 }
  bid(state, 1, 6, 5)
  truthy(#rules.act(state, 2, "liar") > 0, "called")
  eq(state.last.actual, 6, "counted")
  eq(state.last.loser, 2, "the bid was exact, so it stands")
  eq(state.players[2].left, 4, "Bea lost one")
  eq(state.players[1].left, 5, "Ann did not")
  eq(#rules.waitingOn(state), 0, "the computer rolls next")
  local id, value = rules.auto(state, nil)
  local rng = testing.fastRng(5)
  truthy(#rules.act(state, nil, id, value, rng) > 0, "rolled")
  eq(state.round, 2, "round")
  eq(#state.players[2].dice, 4, "Bea rolls four")
  eq(rules.waitingOn(state)[1], 2, "the loser opens")
  eq(state.bid, nil, "the bid is gone")
end)

test("a short bid costs the bidder a die", function()
  local state = fresh()
  state.players[1].dice = { 2, 2, 2, 2, 2 }
  state.players[2].dice = { 3, 3, 3, 3, 3 }
  bid(state, 1, 1, 6)
  rules.act(state, 2, "liar")
  eq(state.last.loser, 1, "no sixes at all")
  eq(state.players[1].left, 4, "Ann lost one")
end)

test("a bid of ones does not count anything else", function()
  local state = fresh()
  state.players[1].dice = { 1, 2, 2, 2, 2 }
  state.players[2].dice = { 3, 3, 3, 3, 3 }
  bid(state, 1, 2, 1)
  rules.act(state, 2, "liar")
  eq(state.last.actual, 1, "one one")
  eq(state.last.loser, 1, "short")
end)

test("the last with dice takes the stake and only the stake", function()
  local state = fresh(9, 250)
  state.players[1].left, state.players[2].left = 1, 3
  state.players[1].dice, state.players[2].dice = { 2 }, { 3, 3, 3 }
  bid(state, 1, 4, 6)
  rules.act(state, 2, "liar")
  truthy(rules.done(state), "over")
  local nets = rules.nets(state)
  eq(nets[1], -250, "Ann pays")
  eq(nets[2], 250, "Bea takes")
  eq(rules.result(state, 2).kind, "win", "Bea won")
  eq(rules.result(state, 1).kind, "lose", "Ann lost")
  eq(rules.risk(state, 1), 250, "risk")
  truthy(rules.result(state, nil).title:find("Bea", 1, true), "the table's line")
  eq(#rules.waitingOn(state), 0, "nothing waits")
end)

test("the stake never passes the shorter stack", function()
  local state = fresh(4, 500, 120, 900)
  eq(state.stake, 120, "capped")
end)

test("the top bid can only be called", function()
  local state = fresh()
  bid(state, 1, 10, 1)
  local actions = ids(rules.actions(state, 2))
  eq(actions.bid, nil, "no bid is left")
  truthy(actions.liar, "LIAR is")
  eq(rules.viewFor(state, 2).draft, nil, "no draft")
  eq(#rules.act(state, 2, "bid"), 0, "a press does nothing")
  eq(#rules.act(state, 2, "count", 10), 0, "nor a tap")
  eq(rules.auto(state, 2), "liar", "auto calls")
end)

test("the first bid cannot be called", function()
  local state = fresh()
  eq(ids(rules.actions(state, 1)).liar, nil, "no LIAR offered")
  local before = kit.plain(state)
  eq(#rules.act(state, 1, "liar"), 0, "no effect")
  truthy(kit.same(before, state), "unchanged")
  eq(rules.auto(state, 1), "bid", "auto opens")
end)

test("the draft stays legal whatever is tapped", function()
  local state = fresh()
  bid(state, 1, 3, 4)
  eq(state.draft.count, 3, "lowest raise count")
  eq(state.draft.face, 5, "lowest raise face")
  truthy(#rules.act(state, 2, "face", 2) > 0, "a low face")
  eq(state.draft.count, 4, "the count goes up to fit")
  eq(state.draft.face, 2, "the face stays")
  truthy(#rules.act(state, 2, "count", 3) > 0, "back down")
  eq(state.draft.count, 3, "count")
  truthy(rules.raises(state.bid, state.draft.count, state.draft.face), "still a raise")
  eq(#rules.act(state, 2, "count", 2), 0, "below the table does nothing")
  eq(state.draft.count, 3, "unchanged")

  local top = fresh()
  bid(top, 1, 10, 5)
  eq(#rules.act(top, 2, "face", 2), 0, "no count left to go up to")
  truthy(#rules.act(top, 2, "face", 6) > 0, "a higher face is fine")
  truthy(#rules.act(top, 2, "face", 1) > 0, "as are ones")
  bid(top, 2, 10, 1)
  eq(#rules.actions(top, 1), 1, "just LIAR")
end)

test("nobody moves out of turn and junk changes nothing", function()
  local state = fresh()
  local before = kit.plain(state)
  local rng = testing.fastRng(1)
  local junk = { { 2, "bid" }, { 2, "liar" }, { 2, "count", 2 }, { 2, "face", 3 }, { 3, "bid" }, { 1, "count", 0 }, { 1, "count", 11 },
    { 1, "count", 1.5 }, { 1, "count", "2" }, { 1, "count", {} }, { 1, "count" }, { 1, "face", 0 }, { 1, "face", 7 }, { 1, "face", "x" },
    { 1, "face", 0 / 0 }, { 1, "face", 1 / 0 }, { 1, "roll" }, { 1, "pick" }, { 1, 42 }, { nil, "bid" }, { nil, "liar" }, { nil, "roll" } }
  for index, press in ipairs(junk) do
    eq(#rules.act(state, press[1], press[2], press[3], rng), 0, "junk " .. index)
    truthy(kit.same(before, state), "junk " .. index .. " changed the state")
  end
end)

test("players' nets are zero in 2000 random matches, with half the turns absent at times", function()
  kit.fuzz(plugin, { rounds = 1000, seats = { 2 }, stake = 100, stack = 500, pick = picker })
  kit.fuzz(plugin, { rounds = 500, seats = { 2 }, stake = 25, stack = 25, absent = 50, pick = picker, seed = 99 })
  kit.fuzz(plugin, { rounds = 500, seats = { 2 }, stake = 500, stack = 300, absent = 15, seed = 7 })
end)

test("auto alone finishes a match", function()
  for seed = 1, 100 do
    local state = kit.playRound(plugin, { seed = seed, stake = 50, stack = 50, absent = 100 })
    kit.checkEnd(plugin, state, kit.entries(plugin, 2, { stake = 50, stack = 50 }))
  end
end)

test("a seat never sees the other's dice, and nothing moves with them", function()
  local games = 0
  local check = function(state)
    games = games + 1
    local before = {}
    for _, seat in ipairs({ 1, 2 }) do before[seat] = rules.viewFor(state, seat) end
    local public = rules.viewFor(state, nil)
    truthy(not foreignDice(public, nil), "the public view has dice")
    eq(public.draft, nil, "the public view has a draft")
    for _, seat in ipairs({ 1, 2 }) do
      local view = before[seat]
      truthy(not foreignDice(view, seat), "seat " .. seat .. " can see dice")
      if seat ~= state.turn then eq(view.draft, nil, "the other's draft") end
    end
    if state.phase == "bid" then
      -- Non-interference: give each player other dice. The other's view must not change at all, nor the public one
      for position, player in ipairs(state.players) do
        local saved, draft = player.dice, state.draft
        local swapped = {}
        for index, die in ipairs(saved) do swapped[index] = die % 6 + 1 end
        player.dice = swapped
        local watcher = state.players[3 - position].seat
        truthy(kit.same(before[watcher], rules.viewFor(state, watcher)), "seat " .. watcher .. "'s view moved with the other's dice")
        truthy(kit.same(public, rules.viewFor(state, nil)), "the public view moved with the dice")
        player.dice = saved
        if watcher ~= state.turn and draft then
          state.draft = { count = draft.count, face = draft.face == 6 and 5 or 6 }
          truthy(kit.same(before[watcher], rules.viewFor(state, watcher)), "seat " .. watcher .. "'s view moved with the other's draft")
          state.draft = draft
        end
      end
    end
  end
  kit.fuzz(plugin, { rounds = 300, seats = { 2 }, stake = 100, stack = 500, pick = picker, check = check })
  truthy(games > 1000, "the check ran")
end)

test("events carry no dice", function()
  local rng = testing.fastRng(11)
  local state, events = rules.new(entries(), 1, rng, {})
  local function clean(list)
    for _, ev in ipairs(list) do
      truthy(type(ev.type) == "string", "typed")
      for key, value in pairs(ev) do
        truthy(key ~= "dice" and type(value) ~= "table", "event " .. ev.type .. " holds " .. tostring(key))
      end
    end
  end
  clean(events)
  for _ = 1, 500 do
    if rules.done(state) then break end
    local waiting = rules.waitingOn(state)
    local id, value = rules.auto(state, waiting[1])
    clean(rules.act(state, waiting[1], id, value, rng))
  end
  truthy(rules.done(state), "over")
end)

test("the dice show once a call is made, and the last call shows at the end", function()
  local state = fresh()
  bid(state, 1, 2, 6)
  rules.act(state, 2, "liar")
  local view = rules.viewFor(state, nil)
  eq(#view.players[1].dice, 5, "first hand")
  eq(#view.players[2].dice, 5, "second hand")
  eq(view.last.count, 2, "what was called")
  rules.act(state, nil, "roll", nil, testing.fastRng(3))
  view = rules.viewFor(state, nil)
  eq(view.players[1].dice, nil, "hidden again")
  eq(view.last.count, 2, "the last call is still on the wall")
end)

test("every state survives textutils and a journal", function()
  if not textutils then return end
  local rng = testing.fastRng(21)
  local state = rules.new(entries(), 1, rng, {})
  for _ = 1, 500 do
    state = textutils.unserialize(textutils.serialize(state))
    for _, seat in ipairs({ 1, 2 }) do
      local view = rules.viewFor(state, seat)
      truthy(kit.same(view, textutils.unserialize(textutils.serialize(view))), "the view")
    end
    if rules.done(state) then break end
    local waiting = rules.waitingOn(state)
    local id, value = rules.auto(state, waiting[1])
    truthy(#rules.act(state, waiting[1], id, value, rng) > 0, "moved")
  end
  truthy(rules.done(state), "over")
end)

test("regions match the picker and sit on the wall", function()
  local state = fresh()
  bid(state, 1, 3, 4)
  local view = rules.viewFor(state, 2)
  local regions = plugin.seatView.regions(view)
  truthy(#regions > 0, "regions")
  for _, region in ipairs(regions) do
    truthy(region.x >= 1 and region.x + region.w - 1 <= 121, "inside the wall's width")
    truthy(region.y >= 10 and region.y + region.h - 1 <= 68, "inside the game's rows")
    local copy = kit.plain(state)
    truthy(#rules.act(copy, 2, region.id, region.value) > 0, "a live tile does something: " .. region.id .. " " .. tostring(region.value))
  end
  eq(#plugin.seatView.regions(rules.viewFor(state, nil)), 0, "a public view has none")
  eq(#plugin.seatView.regions(rules.viewFor(state, 1)), 0, "nor the player waiting")
end)

test("every view draws on a screenless wall, seat and table", function()
  local canvas = require("lib.casino.canvas")
  local function draws(state)
    for _, seat in ipairs({ 1, 2, false }) do
      local view = rules.viewFor(state, seat or nil)
      local c = canvas.new(nil, 121, 81)
      plugin.seatView.draw(c, view, nil, { seat = seat or 1, name = "Ann" })
      plugin.seatView.draw(c, view, { ev = { type = "reveal" }, t = 0.4 }, { seat = seat or 1 })
      plugin.seatView.draw(c, view, { ev = { type = "liar" }, t = 0.4 }, { seat = seat or 1 })
      plugin.tableView.draw(c, view, nil, { waiting = {}, seats = {} })
    end
  end
  for seed = 1, 20 do
    kit.playRound(plugin, { seed = seed, stake = 25, stack = 100, pick = picker, check = draws })
  end
end)

test("help and the plugin are in order", function()
  eq(plugin.id, "liarsdice", "id")
  eq(plugin.kind, "players", "kind")
  eq(plugin.minSeats, 2, "min")
  eq(plugin.maxSeats, 2, "max")
  truthy(#plugin.help() > 0, "help")
  truthy(plugin.stakes[1] > 0, "stakes")
  truthy(plugin.tableView.draw and plugin.seatView.draw, "pictures")
end)
