-- group_draw_test.lua
-- Five-Card Draw on Big Table. pokertable_test.lua proves the poker. This proves the plugin over it: the marks, what each seat is
-- told, that chips add up across thousands of hands, and that both pictures stay on their screens.

local deck = require("lib.casino.deck")
local five = require("pokertable_rules")
local kit = require("group_kit")
local poker = require("lib.casino.poker")
local testing = require("testing")
local eq, test, truthy = testing.eq, testing.test, testing.truthy

local plugin = kit.plugin("BigTable", "draw")
local rules = plugin.rules

local function hand(...)
  local cards = {}
  for i, name in ipairs({ ... }) do cards[i] = deck.parse(name) end
  return cards
end

--- A table in the draw, seat 1 to act, its hand set by name.
local function atDraw(...)
  local entries = kit.entries(plugin, 2, { stack = 500 })
  local state = rules.new(entries, 2, testing.fastRng(7), {})
  rules.act(state, 1, "check")
  rules.act(state, 2, "check")
  eq(state.phase, "draw", "the draw is open")
  eq(rules.waitingOn(state)[1], 1, "seat 1 draws first")
  if select("#", ...) > 0 then state.players[1].hand = hand(...) end
  return state
end

--- Taps that the state did not take.
local function refused(state, seat, id, value, what)
  local before = kit.plain(state)
  local events = rules.act(state, seat, id, value)
  truthy(not events or #events == 0, what .. " returned events")
  truthy(kit.same(before, state), what .. " changed the state")
end

--- Press at random, marking cards in the draw so the marks are in every test that plays.
local function pick(state, _, _, rng)
  if state.phase ~= "draw" or rng:below(3) == 0 then return nil end
  local position = rng:below(5) + 1
  local player = state.players[state.turn]
  local trial = {}
  for i, marked in ipairs(player.marks) do trial[i] = marked end
  trial[position] = not trial[position]
  local list = {}
  for i, marked in ipairs(trial) do
    if marked then list[#list + 1] = i end
  end
  if five.legalDiscard(player.hand, list) then return "mark", position end
  return "draw"
end

-- ------------------------------------------------------------------ the contract

test("draw keeps the contract at every table size", function()
  kit.fuzz(plugin, { rounds = 300, seats = { 2, 3, 4, 5, 6 }, stack = 500, absent = 15, pick = pick })
end)

test("draw keeps the contract with stacks that run out", function()
  kit.fuzz(plugin, { rounds = 200, seats = { 2, 3, 6 }, stack = 25, absent = 10, pick = pick, seed = 99 })
end)

test("the plugin says what the cabinet needs", function()
  eq(plugin.id, "draw")
  eq(plugin.kind, "players")
  eq(plugin.minSeats, 2)
  eq(plugin.maxSeats, 6)
  eq(plugin.ante, five.ANTE)
  truthy(#plugin.help() > 0, "help")
  eq(select(1, plugin.event({ type = "mark" })), 0, "a mark takes no time")
end)

test("nets add to zero over 2400 hands of uneven stacks and all-ins", function()
  local rng = testing.fastRng(2024)
  local hands, showdowns, walkovers, sidePots = 0, 0, 0, 0
  for round = 1, 2400 do
    local count = rng:below(5) + 2
    local entries = {}
    local seat = rng:below(2) + 1
    for index = 1, count do
      -- Seats need not run in a line, and short stacks make side pots
      local stack = rng:below(4) == 0 and rng:below(100) + 5 or rng:below(1500) + 100
      entries[index] = { seat = seat, name = "P" .. seat, stack = stack }
      seat = seat + 1 + (count < 5 and rng:below(2) or 0)
    end
    local state = kit.playRound(plugin, { entries = entries, rng = rng, button = rng:below(count) + 1, keep = {}, absent = 10, pick = pick })
    local nets = kit.checkEnd(plugin, state, entries)
    local sum = 0
    for _, entry in ipairs(entries) do
      sum = sum + (nets[entry.seat] or 0)
      truthy(entry.stack + (nets[entry.seat] or 0) >= 0, "a stack went below nothing")
    end
    eq(sum, -(state.kept or 0), "hand " .. round .. "'s nets, less the owner's odd chips")
    hands = hands + 1
    if state.uncontested then walkovers = walkovers + 1 else showdowns = showdowns + 1 end
    if #state.pots > 1 then sidePots = sidePots + 1 end
    if round % 50 == 0 then testing.breathe() end
  end
  eq(hands, 2400, "hands played")
  truthy(showdowns > 100, "showdowns " .. showdowns)
  truthy(walkovers > 100, "walkovers " .. walkovers)
  truthy(sidePots > 50, "side pots " .. sidePots)
end)

-- ------------------------------------------------------------------ the draw

test("a tap marks a card and a second tap keeps it", function()
  local state = atDraw("2C", "7D", "9H", "JS", "KC")
  eq(rules.viewFor(state, 1).thrown, 0)
  truthy(#rules.act(state, 1, "mark", 2) > 0, "marked")
  eq(rules.viewFor(state, 1).marks[2], true)
  eq(rules.viewFor(state, 1).thrown, 1)
  truthy(#rules.act(state, 1, "mark", 2) > 0, "unmarked")
  eq(rules.viewFor(state, 1).marks[2], false)
  eq(rules.viewFor(state, 1).thrown, 0)
end)

test("marking a card leaves the buttons as they are, so a quick second tap is not dropped as stale", function()
  local state = atDraw("2C", "7D", "9H", "JS", "KC")
  local before = kit.plain(rules.actions(state, 1))
  rules.act(state, 1, "mark", 1)
  truthy(kit.same(before, rules.actions(state, 1)), "the buttons changed")
end)

test("the draw throws what is marked and nothing else", function()
  local state = atDraw("2C", "7D", "9H", "JS", "KC")
  rules.act(state, 1, "mark", 1)
  rules.act(state, 1, "mark", 4)
  local top = { state.deck[#state.deck], state.deck[#state.deck - 1] }
  truthy(#rules.act(state, 1, "draw") > 0, "drew")
  local cards = state.players[1].hand
  eq(cards[1], top[1], "first card")
  eq(cards[4], top[2], "second card")
  eq(deck.name(cards[2]), deck.name(hand("7D")[1]), "kept")
  eq(deck.name(cards[3]), deck.name(hand("9H")[1]), "kept")
  eq(deck.name(cards[5]), deck.name(hand("KC")[1]), "kept")
  eq(state.players[1].last, "DREW 2")
  eq(rules.waitingOn(state)[1], 2, "the turn moves on")
end)

test("a fourth card needs an ace kept, and a fifth never goes", function()
  local state = atDraw("2C", "7D", "9H", "JS", "KC")
  eq(rules.viewFor(state, 1).mayThrow, 3)
  for i = 1, 3 do rules.act(state, 1, "mark", i) end
  refused(state, 1, "mark", 4, "a fourth card with no ace")

  state = atDraw("AC", "7D", "9H", "JS", "KC")
  eq(rules.viewFor(state, 1).mayThrow, 4)
  for i = 2, 5 do truthy(#rules.act(state, 1, "mark", i) > 0, "card " .. i) end
  refused(state, 1, "mark", 1, "a fifth card")
  eq(rules.viewFor(state, 1).thrown, 4)

  -- Three marked with the ace among them: a fourth would leave no ace
  state = atDraw("AC", "7D", "9H", "JS", "KC")
  for i = 1, 3 do rules.act(state, 1, "mark", i) end
  refused(state, 1, "mark", 4, "throwing the ace as a fourth")
end)

test("running out of time keeps the marks, and with none stands pat", function()
  local state = atDraw("2C", "7D", "9H", "JS", "KC")
  rules.act(state, 1, "mark", 3)
  local id, value = rules.auto(state, 1)
  rules.act(state, 1, id, value)
  eq(state.players[1].last, "DREW 1")
  id, value = rules.auto(state, 2)
  rules.act(state, 2, id, value)
  eq(state.players[2].last == "PAT" or state.phase == "bet2", true)
end)

test("a marked hand survives a journal", function()
  local state = atDraw("2C", "7D", "9H", "JS", "KC")
  rules.act(state, 1, "mark", 5)
  state = kit.plain(state)
  eq(rules.viewFor(state, 1).thrown, 1)
  truthy(#rules.act(state, 1, "draw") > 0, "drew after coming back")
end)

-- ------------------------------------------------------------------ illegal input

test("illegal input does nothing", function()
  local state = atDraw("2C", "7D", "9H", "JS", "KC")
  for _, value in ipairs({ 0, 6, -1, 1.5, "1", true }) do refused(state, 1, "mark", value, "mark " .. tostring(value)) end
  refused(state, 1, "mark", nil, "mark nil")
  refused(state, 1, "mark", {}, "mark a table")
  refused(state, 1, "draw125", nil, "the rules' own draw id off the wire")
  refused(state, 1, "check", nil, "a check in the draw")
  refused(state, 1, "raise", nil, "a raise in the draw")
  refused(state, 1, "no_such", nil, "an unknown id")
end)

test("a seat cannot act out of turn or as nobody", function()
  local state = rules.new(kit.entries(plugin, 3, { stack = 500 }), 1, testing.fastRng(3), {})
  local waiting = rules.waitingOn(state)[1]
  eq(#rules.waitingOn(state), 1, "one seat at a time")
  for seat = 1, 3 do
    if seat ~= waiting then
      eq(#rules.actions(state, seat), 0, "seat " .. seat .. " has no buttons")
      refused(state, seat, "check", nil, "out of turn")
      refused(state, seat, "fold", nil, "out of turn")
    end
  end
  refused(state, nil, "check", nil, "no seat")
  refused(state, 42, "check", nil, "a seat not in the hand")
  refused(state, waiting, "draw", nil, "draw in the betting")
  refused(state, waiting, "mark", 1, "mark in the betting")
  refused(state, waiting, "call", nil, "call with nothing to call")
  refused(state, waiting, 7, nil, "a number for an id")
  refused(state, waiting, {}, nil, "a table for an id")
end)

test("a finished hand takes nothing", function()
  local state = rules.new(kit.entries(plugin, 2, { stack = 500 }), 1, testing.fastRng(3), {})
  rules.act(state, rules.waitingOn(state)[1], "raise")
  rules.act(state, rules.waitingOn(state)[1], "fold")
  truthy(rules.done(state), "over")
  eq(#rules.waitingOn(state), 0)
  for seat = 1, 2 do
    eq(#rules.actions(state, seat), 0)
    refused(state, seat, "check", nil, "after the end")
  end
end)

test("buttons cost what they put at risk", function()
  local state = rules.new(kit.entries(plugin, 2, { stack = 500 }), 1, testing.fastRng(3), {})
  local first = rules.waitingOn(state)[1]
  local raise
  for _, action in ipairs(rules.actions(state, first)) do
    if action.id == "raise" then raise = action end
  end
  eq(raise.cost, five.SMALL, "a bet costs the small bet")
  rules.act(state, first, "raise")
  local second = rules.waitingOn(state)[1]
  local costs = {}
  for _, action in ipairs(rules.actions(state, second)) do costs[action.id] = action.cost end
  eq(costs.call, five.SMALL, "a call")
  eq(costs.raise, five.SMALL * 2, "a raise")
  eq(costs.fold, nil, "a fold is free")
end)

-- ------------------------------------------------------------------ secrets

--- The state with everything a seat must not know changed: other hands and marks, and the deck.
local function scrambled(state, seat, keepShown)
  local copy = kit.plain(state)
  local spare = 0
  for _, player in ipairs(copy.players) do
    local shown = keepShown and not player.folded
    if player.seat ~= seat and not shown then
      for i = 1, #player.hand do
        spare = spare + 1
        player.hand[i] = deck.card(((player.hand[i] + spare) % 13) + 2, spare % 4)
      end
      for i = 1, #player.marks do player.marks[i] = not player.marks[i] end
    end
  end
  for i = 1, math.floor(#copy.deck / 2) do
    local other = #copy.deck - i + 1
    copy.deck[i], copy.deck[other] = copy.deck[other], copy.deck[i]
  end
  return copy
end

local function blind(state, seat, shown, what)
  truthy(kit.same(rules.viewFor(state, seat), rules.viewFor(scrambled(state, seat, shown), seat)), what)
end

test("no seat's view changes with what it may not know", function()
  local checked = 0
  kit.fuzz(plugin, { rounds = 400, seats = { 2, 3, 4, 6 }, stack = 200, absent = 10, pick = pick, seed = 5,
    check = function(state, entries)
      blind(state, nil, false, "the public view")
      for _, entry in ipairs(entries) do
        blind(state, entry.seat, false, "seat " .. entry.seat .. "'s view")
        checked = checked + 1
      end
    end })
  truthy(checked > 1000, "views checked: " .. checked)
end)

test("the scramble really changes the state, so the test above can fail", function()
  local state = atDraw("2C", "7D", "9H", "JS", "KC")
  truthy(not kit.same(state, scrambled(state, 2, false)), "the state moved")
  local seat1 = rules.viewFor(state, 1)
  truthy(not kit.same(seat1, rules.viewFor(scrambled(state, 2, false), 1)), "seat 1's own hand is in seat 1's view")
end)

test("a view names no card but its own until a showdown", function()
  local state = rules.new(kit.entries(plugin, 4, { stack = 500 }), 1, testing.fastRng(11), {})
  local public = rules.viewFor(state, nil)
  eq(public.hand, nil, "the public view has no hand")
  eq(public.marks, nil, "or marks")
  eq(public.deck, nil, "or deck")
  for _, player in ipairs(public.players) do
    eq(player.hand, nil, "or a player's hand")
    eq(player.handName, nil, "or what it is")
  end
  local view = rules.viewFor(state, 2)
  eq(#view.hand, 5, "seat 2 sees five cards")
  for i, card in ipairs(state.players[2].hand) do eq(view.hand[i], card) end
  eq(view.deck, nil)
  for _, player in ipairs(view.players) do eq(player.hand, nil, "another's hand") end
end)

test("marks stay with the seat that made them", function()
  local state = atDraw("2C", "7D", "9H", "JS", "KC")
  rules.act(state, 1, "mark", 2)
  eq(rules.viewFor(state, nil).marks, nil, "public")
  eq(rules.viewFor(state, 2).marks, nil, "the other seat")
  local events = rules.act(state, 1, "mark", 3)
  eq(events[1].type, "mark")
  eq(events[1].value, nil, "the event does not say which card")
  eq(events[1].position, nil, "the event does not say which card")
end)

test("a showdown turns over only the hands still in", function()
  local checkedShow, checkedWalk = 0, 0
  local rng = testing.fastRng(77)
  for _ = 1, 400 do
    local state, entries = kit.playRound(plugin, { seats = 4, stack = 300, rng = rng, keep = {}, absent = 15, pick = pick })
    local public = rules.viewFor(state, nil)
    for index, player in ipairs(public.players) do
      local real = state.players[index]
      if state.uncontested or real.folded then
        eq(player.hand, nil, "hidden hand")
        eq(player.handName, nil, "hidden hand's name")
      else
        eq(#player.hand, 5, "shown hand")
        eq(player.handName, real.handName)
      end
    end
    for _, entry in ipairs(entries) do
      blind(state, entry.seat, not state.uncontested, "a folded hand at the end")
    end
    blind(state, nil, not state.uncontested, "the public view at the end")
    if state.uncontested then checkedWalk = checkedWalk + 1 else checkedShow = checkedShow + 1 end
  end
  truthy(checkedShow > 20, "showdowns " .. checkedShow)
  truthy(checkedWalk > 20, "walkovers " .. checkedWalk)
end)

test("a hand nobody called names nobody's cards in a result", function()
  local state = rules.new(kit.entries(plugin, 2, { stack = 500 }), 1, testing.fastRng(3), {})
  rules.act(state, rules.waitingOn(state)[1], "raise")
  rules.act(state, rules.waitingOn(state)[1], "fold")
  truthy(state.uncontested, "uncontested")
  for _, player in ipairs(state.players) do
    local name = poker.describe(poker.evaluate(player.hand))
    for _, result in ipairs({ rules.result(state, 1), rules.result(state, 2), rules.result(state, nil) }) do
      truthy(not result.detail:find(name, 1, true), "a hand's name in: " .. result.detail)
    end
  end
end)

test("events never carry a card", function()
  local known = { type = true, phase = true, who = true, id = true, amount = true, count = true, uncontested = true }
  local spy = {}
  for key, value in pairs(plugin) do spy[key] = value end
  spy.rules = {}
  for key, value in pairs(rules) do spy.rules[key] = value end
  local seen = 0
  local function look(events)
    for _, ev in ipairs(events or {}) do
      seen = seen + 1
      for key in pairs(ev) do truthy(known[key], "event " .. tostring(ev.type) .. " has " .. tostring(key)) end
    end
  end
  spy.rules.act = function(...)
    local events = rules.act(...)
    look(events)
    return events
  end
  spy.rules.new = function(...)
    local state, events = rules.new(...)
    look(events)
    return state, events
  end
  kit.fuzz(spy, { rounds = 200, seats = { 2, 4, 6 }, stack = 100, pick = pick, seed = 8 })
  truthy(seen > 500, "events seen " .. seen)
end)

-- ------------------------------------------------------------------ what lasts

test("every state and view goes through textutils, if there is one", function()
  if not textutils then return end -- plain Lua has none. kit.plain above has already refused anything a journal could not keep
  kit.fuzz(plugin, { rounds = 60, seats = { 2, 6 }, stack = 200, pick = pick, seed = 21,
    check = function(state, entries)
      truthy(kit.same(state, textutils.unserialize(textutils.serialize(state))), "the state")
      local view = rules.viewFor(state, entries[1].seat)
      truthy(kit.same(view, textutils.unserialize(textutils.serialize(view))), "a seat's view")
    end })
  local state = kit.playRound(plugin, { seats = 3, seed = 4, stack = 200, pick = pick })
  truthy(kit.same(state, textutils.unserialize(textutils.serialize(state))), "a finished state")
end)

-- ------------------------------------------------------------------ results

test("each seat is told how it went, in a line that fits", function()
  local rng = testing.fastRng(31)
  for _ = 1, 300 do
    local entries = kit.entries(plugin, 6, { stack = 200 })
    for _, entry in ipairs(entries) do entry.name = "Sixteen_Letters" .. entry.seat end
    local state = kit.playRound(plugin, { entries = entries, rng = rng, keep = {}, pick = pick })
    for _, entry in ipairs(entries) do
      local result = rules.result(state, entry.seat)
      local net = rules.nets(state)[entry.seat]
      eq(result.kind, net > 0 and "win" or (net < 0 and "lose" or "push"), result.title)
      truthy(#result.detail <= 74, "detail too long: " .. result.detail)
    end
    local line = rules.result(state, nil)
    truthy(#line.title <= 18, "title too long: " .. line.title)
    truthy(#line.detail <= 112, "detail too long: " .. line.detail)
  end
end)

test("rules.risk is everything the seat put in", function()
  local state = rules.new(kit.entries(plugin, 2, { stack = 500 }), 1, testing.fastRng(3), {})
  local first = rules.waitingOn(state)[1]
  rules.act(state, first, "raise")
  rules.act(state, rules.waitingOn(state)[1], "call")
  eq(rules.risk(state, first), five.ANTE + five.SMALL)
end)

-- ------------------------------------------------------------------ the pictures

--- A canvas that records what would leave its screen. Text is only counted to its last visible letter.
local function fakeCanvas(w, h, top, bottom)
  local c = { w = w, h = h, bad = {} }
  local function note(what, x, y, width, high)
    if x < 1 or y < top or x + width - 1 > w or y + high - 1 > bottom then
      c.bad[#c.bad + 1] = what .. " at " .. x .. "," .. y .. " size " .. width .. "x" .. high
    end
  end
  function c:rect(x, y, width, high) note("rect", x, y, width, high) end
  function c:frame(x, y, width, high) note("frame", x, y, width, high) end
  function c:panel(x, y, width, high) note("panel", x, y, width, high) end
  function c:text(x, y, text) note("text '" .. tostring(text) .. "'", x, y, #tostring(text), 1) end
  function c:textCenter(cx, y, text) note("text '" .. tostring(text) .. "'", cx - math.floor(#tostring(text) / 2), y, #tostring(text), 1) end
  function c:bigWidth(text, scale) return #tostring(text) * 6 * (scale or 1) end
  function c:big(x, y, text, _, scale) note("big", x, y, #tostring(text) * 6 * (scale or 1), 6 * (scale or 1)) end
  function c:bigCenter(cx, y, text, color, scale) self:big(cx - math.floor(self:bigWidth(text, scale) / 2), y, text, color, scale) end
  return c
end

--- Both pictures for every seat, in every phase a round goes through.
local function drawAll(state, entries)
  for _, anim in ipairs({ false, { ev = { type = "deal" }, t = 0.5 } }) do
    local wall = fakeCanvas(121, 81, 10, 72)
    plugin.tableView.draw(wall, rules.viewFor(state, nil), anim or nil, {})
    eq(table.concat(wall.bad, "; "), "", "the wall")
    for _, entry in ipairs(entries) do
      local seat = fakeCanvas(78, 52, 10, 39)
      local view = rules.viewFor(state, entry.seat)
      plugin.seatView.draw(seat, view, anim or nil, {})
      eq(table.concat(seat.bad, "; "), "", "seat " .. entry.seat)
      local regions = plugin.seatView.regions(view)
      eq(#regions, view.drawing and 5 or 0, "regions")
      for _, region in ipairs(regions) do
        truthy(region.x >= 1 and region.x + region.w - 1 <= 78, "a region off the side")
        truthy(region.y >= 10 and region.y + region.h - 1 <= 39, "a region off the game's rows")
      end
    end
    local watcher = fakeCanvas(78, 52, 10, 39)
    plugin.seatView.draw(watcher, rules.viewFor(state, nil), anim or nil, {})
    eq(table.concat(watcher.bad, "; "), "", "a seat watching")
  end
end

test("both pictures stay on their screens with long names and a full table", function()
  local rng = testing.fastRng(41)
  for round = 1, 60 do
    local count = rng:below(5) + 2
    local entries = kit.entries(plugin, count, { stack = 5000 })
    for _, entry in ipairs(entries) do entry.name = "Sixteen_Letters" .. entry.seat; entry.stack = 100 + rng:below(4900) end
    local state = kit.playRound(plugin, { entries = entries, rng = rng, keep = {}, pick = pick, check = drawAll })
    drawAll(state, entries)
    if round % 5 == 0 then testing.breathe() end
  end
end)

test("the cards the seat shows stay above the result banner", function()
  local state = atDraw("2C", "7D", "9H", "JS", "KC")
  for i = 1, 3 do rules.act(state, 1, "mark", i) end
  local view = rules.viewFor(state, 1)
  for _, region in ipairs(plugin.seatView.regions(view)) do
    truthy(region.y + region.h - 1 <= 29, "the banner starts at row 30")
  end
end)
