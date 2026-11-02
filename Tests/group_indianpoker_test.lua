-- group_indianpoker_test.lua
-- Indian Poker on Duel: the fixed-limit betting, folds, splits, short stacks and the button, and above all that a seat never learns its
-- own card. Cards are small numbers that a stack or a pot could equal, so a value search proves little. The secrecy here swaps the
-- hidden card for another and demands that nothing a player is told changes.

local deck = require("lib.casino.deck")
local kit = require("group_kit")
local picks = require("lib.sound_picks")
local testing = require("testing")
local eq, test, truthy = testing.eq, testing.test, testing.truthy

local plugin = kit.plugin("Duel", "indianpoker")
local rules = plugin.rules

local ANTE, BET = 10, 20
local FAKE_A, FAKE_B = 1001, 1002   -- no real card, stack or pot is ever these

local function falsy(value, what)
  if value then error((what or "value") .. " should be false", 2) end
end

local function entries(stackA, stackB)
  return { { seat = 1, name = "Ann", stack = stackA or 1000 }, { seat = 2, name = "Bea", stack = stackB or 1000 } }
end

--- A hand with these cards. Seat 1 has the button unless button says so.
local function hand(cardA, cardB, stackA, stackB, button)
  local state, events = rules.new(entries(stackA, stackB), button or 1, testing.fastRng(7), {})
  state.players[1].card = deck.parse(cardA or "9S")
  state.players[2].card = deck.parse(cardB or "4D")
  return state, events
end

local function press(state, seat, id)
  local events = rules.act(state, seat, id)
  truthy(events and #events > 0, id .. " by seat " .. tostring(seat) .. " should work")
  return events
end

local function offered(state, seat)
  local ids = {}
  for _, action in ipairs(rules.actions(state, seat)) do ids[action.id] = action end
  return ids
end

--- The same hand with other cards in it.
local function withCards(state, cardA, cardB)
  local copy = kit.plain(state)
  copy.players[1].card, copy.players[2].card = cardA, cardB
  return copy
end

local function playerOf(state, seat)
  return state.players[1].seat == seat and state.players[1] or state.players[2]
end

local function otherOf(state, seat)
  return state.players[1].seat == seat and state.players[2] or state.players[1]
end

--- Everything a seat is told before the end, as one table.
local function told(state, seat)
  return { view = rules.viewFor(state, seat), actions = rules.actions(state, seat), waiting = rules.waitingOn(state),
    auto = rules.auto(state, seat), result = rules.result(state, seat), nets = rules.nets(state) }
end

--- The secrecy check, for any state with the hand still in play.
local function secret(state)
  falsy(rules.done(state), "a secrecy check on a hand still in play")
  local fake = withCards(state, FAKE_A, FAKE_B)
  for index, player in ipairs(state.players) do
    local seat = player.seat
    local other = otherOf(state, seat)
    local mine, theirs = FAKE_A, FAKE_B
    if index == 2 then mine, theirs = FAKE_B, FAKE_A end

    -- The value search, with cards nothing else can equal
    local view = rules.viewFor(fake, seat)
    falsy(kit.shows(view, mine), "seat " .. seat .. "'s own card in its view")
    truthy(kit.shows(view, theirs), "the other card in seat " .. seat .. "'s view")
    eq(view.theirs, theirs, "the other card where the wall looks for it")
    eq(rules.viewFor(state, seat).theirs, other.card, "the real other card")

    -- Any other card of its own changes nothing a seat is told
    local changed = kit.plain(state)
    playerOf(changed, seat).card = (player.card + 21) % 52
    truthy(kit.same(told(state, seat), told(changed, seat)), "seat " .. seat .. " can tell its own card from what it is told")
  end
  local public = rules.viewFor(fake, nil)
  falsy(kit.shows(public, FAKE_A), "the first card in the public view")
  falsy(kit.shows(public, FAKE_B), "the second card in the public view")
  truthy(kit.same(told(state, nil), told(withCards(state, (state.players[1].card + 9) % 52, (state.players[2].card + 30) % 52), nil)),
    "the public view changes with the cards")
end

-- ------------------------------------------------------------------ the contract

test("indian poker keeps the contract with deep stacks", function()
  kit.fuzz(plugin, { rounds = 400, stack = 5000, absent = 15, check = function(state) secret(state) end })
end)

test("indian poker keeps the contract with short and uneven stacks", function()
  local seed = 100
  for _, stacks in ipairs({ { 10, 10 }, { 10, 5000 }, { 5000, 10 }, { 11, 12 }, { 15, 40 }, { 30, 31 }, { 25, 70 }, { 45, 1000 }, { 69, 70 },
      { 70, 71 }, { 100, 100 }, { 7, 300 } }) do
    seed = seed + 1
    kit.fuzz(plugin, { rounds = 80, entries = entries(stacks[1], stacks[2]), absent = 10, seed = seed, check = function(state) secret(state) end })
  end
end)

test("seats need not be 1 and 2", function()
  local list = { { seat = 2, name = "Ann", stack = 300 }, { seat = 5, name = "Bea", stack = 45 } }
  kit.fuzz(plugin, { rounds = 80, entries = list, check = function(state) secret(state) end })
end)

test("the plugin is a buy-in game for two", function()
  eq(plugin.kind, "players", "kind")
  eq(plugin.minSeats, 2, "min seats")
  eq(plugin.maxSeats, 2, "max seats")
  eq(plugin.stakes, nil, "no match stake")
  eq(plugin.ante, ANTE, "a stack must hold an ante")
  truthy(plugin.minBuy and plugin.maxStack, "a buy-in panel")
end)

-- ------------------------------------------------------------------ the deal

test("both ante and each gets one card from a fresh deck", function()
  local seen, pairsSeen = {}, 0
  local rng = testing.fastRng(3)
  for _ = 1, 3000 do
    local state = rules.new(entries(), 1, rng, {})
    eq(state.players[1].total, ANTE, "first ante")
    eq(state.players[2].total, ANTE, "second ante")
    eq(state.players[1].stack, 1000 - ANTE, "first stack")
    truthy(state.players[1].card ~= state.players[2].card, "two different cards")
    eq(state.deck, nil, "no deck kept")
    seen[state.players[1].card] = true
    seen[state.players[2].card] = true
    pairsSeen = pairsSeen + 1
  end
  for card = 0, 51 do truthy(seen[card], "card " .. card .. " dealt in 3000 hands") end
  eq(pairsSeen, 3000, "hands")
end)

test("the deal event carries nothing", function()
  local _, events = hand()
  eq(#events, 1, "one event")
  eq(events[1].type, "deal", "a deal")
  for key in pairs(events[1]) do eq(key, "type", "the event's only field") end
end)

-- ------------------------------------------------------------------ the button

test("the player with the button acts first", function()
  eq(rules.waitingOn(hand(nil, nil, 500, 500, 1))[1], 1, "button on the first")
  eq(rules.waitingOn(hand(nil, nil, 500, 500, 2))[1], 2, "button on the second")
  eq(rules.viewFor(hand(nil, nil, 500, 500, 2), nil).button, 2, "the view says where it is")
end)

test("the button's position is an index, not a seat", function()
  local list = { { seat = 3, name = "Ann", stack = 100 }, { seat = 6, name = "Bea", stack = 100 } }
  eq(rules.waitingOn(rules.new(list, 1, testing.fastRng(1), {}))[1], 3, "position 1 is seat 3")
  eq(rules.waitingOn(rules.new(list, 2, testing.fastRng(1), {}))[1], 6, "position 2 is seat 6")
end)

test("the second to act closes the betting", function()
  local state = hand(nil, nil, 500, 500, 2)
  press(state, 2, "check")
  eq(rules.waitingOn(state)[1], 1, "over to the other")
  truthy(offered(state, 1).check, "the other can check too")
  press(state, 1, "check")
  truthy(rules.done(state), "two checks end it")
end)

-- ------------------------------------------------------------------ the betting

test("a bet and two raises, then only call or fold", function()
  local state = hand()
  local first = offered(state, 1)
  truthy(first.check and first.raise, "check or bet")
  eq(first.raise.label, "BET", "the first is a bet")
  eq(first.raise.cost, BET, "a bet's cost")
  falsy(first.fold, "nothing to fold to")
  press(state, 1, "raise")

  local second = offered(state, 2)
  truthy(second.fold and second.call and second.raise, "fold, call or raise")
  eq(second.raise.label, "RAISE", "now a raise")
  eq(second.call.cost, BET, "calling a bet")
  eq(second.raise.cost, 2 * BET, "a raise costs the call and the raise")
  press(state, 2, "raise")

  local third = offered(state, 1)
  eq(third.raise.cost, 2 * BET, "the third wager")
  press(state, 1, "raise")

  local last = offered(state, 2)
  truthy(last.fold and last.call, "fold or call")
  falsy(last.raise, "the fourth wager is not offered")
  eq(#rules.act(state, 2, "raise"), 0, "and does nothing if pressed")
  eq(rules.viewFor(state, 2).bets, 3, "three wagers")
  press(state, 2, "call")
  truthy(rules.done(state), "called")
  eq(state.pot, 2 * (ANTE + 3 * BET), "the most a pot can be")
  eq(rules.nets(state)[1], ANTE + 3 * BET, "the winner's net at the cap")
  eq(rules.nets(state)[2], -(ANTE + 3 * BET), "the loser's net at the cap")
end)

test("a check then a bet comes back round", function()
  local state = hand()
  press(state, 1, "check")
  press(state, 2, "raise")
  eq(rules.waitingOn(state)[1], 1, "back to the one who checked")
  local back = offered(state, 1)
  truthy(back.fold and back.call and back.raise, "all three open")
  press(state, 1, "call")
  truthy(rules.done(state), "the call ends it")
end)

test("illegal input does nothing", function()
  local state = hand()
  local before = kit.plain(state)
  eq(#rules.act(state, 2, "check"), 0, "out of turn")
  eq(#rules.act(state, 1, "call"), 0, "nothing to call")
  eq(#rules.act(state, 1, "fold"), 0, "nothing to fold to")
  eq(#rules.act(state, nil, "check"), 0, "no seat")
  eq(#rules.act(state, 9, "check"), 0, "a stranger")
  truthy(kit.same(before, state), "the state stands")
  press(state, 1, "check")
  press(state, 2, "check")
  local over = kit.plain(state)
  eq(#rules.act(state, 1, "check"), 0, "after the end")
  truthy(kit.same(over, state), "the end stands")
end)

test("what a button costs is what it moves", function()
  local rng = testing.fastRng(11)
  for _ = 1, 300 do
    local state = rules.new(entries(rng:below(90) + 11, rng:below(90) + 11), rng:below(2) + 1, rng, {})
    while not rules.done(state) do
      local seat = rules.waitingOn(state)[1]
      local list = rules.actions(state, seat)
      local action = list[rng:below(#list) + 1]
      local player = playerOf(state, seat)
      local stack = player.stack
      if not (action.id == "fold") then
        rules.act(state, seat, action.id)
        if not rules.done(state) then eq(stack - player.stack, action.cost or 0, action.id .. "'s cost") end
      else
        rules.act(state, seat, action.id)
      end
    end
  end
end)

-- ------------------------------------------------------------------ the end

test("ace is high and suits do not rank", function()
  local state = hand("AC", "KS")
  press(state, 1, "check")
  press(state, 2, "check")
  eq(rules.nets(state)[1], ANTE, "ace over king")
  eq(rules.nets(state)[2], -ANTE, "king under ace")
  local deuce = hand("AC", "2S")
  press(deuce, 1, "check")
  press(deuce, 2, "check")
  eq(rules.nets(deuce)[1], ANTE, "ace over deuce: nothing wraps")
end)

test("equal ranks split the pot whatever the suits", function()
  local state = hand("QS", "QC")
  press(state, 1, "raise")
  press(state, 2, "call")
  truthy(rules.done(state), "over")
  eq(rules.nets(state)[1], 0, "first breaks even")
  eq(rules.nets(state)[2], 0, "second breaks even")
  eq(state.kept, nil, "no odd chip")
  eq(rules.result(state, 1).kind, "push", "a push")
  eq(rules.result(state, nil).title, "SPLIT POT", "the table says so")
end)

test("a split with uneven stacks gives the excess back", function()
  local state = hand("7S", "7C", 500, 25)
  press(state, 1, "raise")
  press(state, 2, "call")
  truthy(rules.done(state), "over")
  eq(rules.nets(state)[1], 0, "nothing moves")
  eq(rules.nets(state)[2], 0, "nothing moves either way")
end)

test("a fold loses what the folder put in and both cards turn over", function()
  local state = hand("AS", "3D")
  press(state, 1, "check")
  press(state, 2, "raise")
  local events = press(state, 1, "fold")
  truthy(rules.done(state), "over")
  eq(rules.nets(state)[1], -ANTE, "the folder loses the ante")
  eq(rules.nets(state)[2], ANTE, "the winner takes it, and the uncalled bet comes back")
  eq(state.pot, 2 * ANTE, "the pot is what was matched")
  eq(events[#events].type, "reveal", "the cards turn")
  for _, seat in ipairs({ 1, 2, false }) do
    local view = rules.viewFor(state, seat or nil)
    eq(view.players[1].card, deck.parse("AS"), "the folder's card is shown")
    eq(view.players[2].card, deck.parse("3D"), "the winner's card is shown")
    truthy(view.over, "over")
  end
  eq(rules.result(state, 1).kind, "lose", "the folder lost")
  truthy(rules.result(state, 1).detail:find("You folded an ACE", 1, true), "the folder is told what they threw away")
  eq(rules.result(state, 2).kind, "win", "the other won")
  truthy(rules.result(state, nil).detail:find("folded an ACE", 1, true), "the table's line says it")
end)

test("a fold after a raise loses all that was called", function()
  local state = hand()
  press(state, 1, "raise")
  press(state, 2, "raise")
  press(state, 1, "fold")
  eq(rules.nets(state)[1], -(ANTE + BET), "the folder's ante and bet")
  eq(rules.nets(state)[2], ANTE + BET, "and the raise comes back")
  eq(rules.risk(state, 1), ANTE + BET, "what was at risk")
end)

test("results read right and say nothing mid-hand", function()
  local state = hand("KS", "9D")
  local mid = rules.result(state, 1)
  eq(mid.title, "HAND IN PLAY", "nothing mid-hand")
  eq(rules.result(state, nil).detail, "", "no detail on the table's line")
  press(state, 1, "raise")
  press(state, 2, "call")
  local won, lost = rules.result(state, 1), rules.result(state, 2)
  eq(won.kind, "win", "win")
  eq(won.title, "YOU WIN", "title")
  truthy(won.detail:find("+30", 1, true), "the net: " .. won.detail)
  truthy(won.detail:find("a KING", 1, true) and won.detail:find("a 9", 1, true), "both cards: " .. won.detail)
  eq(lost.kind, "lose", "lose")
  truthy(lost.detail:find("-30", 1, true), "the net: " .. lost.detail)
  eq(rules.result(state, nil).title, "ANN WINS", "the table's line")
end)

-- ------------------------------------------------------------------ short stacks

test("all-in for less: the rest comes back and only what is matched moves", function()
  local state = hand("KS", "2D", 500, 25)
  press(state, 1, "raise")
  local call = offered(state, 2)
  eq(call.call.label, "ALL-IN", "the short stack's call says so")
  eq(call.call.cost, 15, "what it really costs")
  eq(rules.viewFor(state, 2).toCall, 15, "the wall says the same")
  falsy(call.raise, "it cannot raise")
  press(state, 2, "call")
  truthy(rules.done(state), "over")
  eq(state.pot, 50, "the pot is what both matched")
  eq(rules.nets(state)[1], 25, "the big stack wins the short stack's all")
  eq(rules.nets(state)[2], -25, "the short stack loses its stack and no more")
  eq(state.players[1].stack, 525, "the bigger stack has its bet back")
  eq(state.players[2].stack, 0, "the short stack is out")
end)

test("a short winner wins only what they matched", function()
  local state = hand("2S", "KD", 500, 25)
  press(state, 1, "raise")
  press(state, 2, "call")
  eq(rules.nets(state)[2], 25, "the short stack doubles")
  eq(rules.nets(state)[1], -25, "and no more")
end)

test("an all-in bet for less than a bet still needs an answer", function()
  local state = hand("KS", "2D", 25, 500)
  local bet = offered(state, 1)
  eq(bet.raise.label, "ALL-IN", "the short bet says so")
  eq(bet.raise.cost, 15, "all that is left")
  press(state, 1, "raise")
  local answer = offered(state, 2)
  eq(answer.call.cost, 15, "calling the short bet")
  truthy(answer.fold, "folding to it")
  falsy(answer.raise, "nobody to raise against")
  press(state, 2, "fold")
  eq(rules.nets(state)[2], -ANTE, "the folder pays the ante")
  eq(rules.nets(state)[1], ANTE, "the short bet comes back")
end)

test("an all-in raise too short for a full raise can only be called or folded", function()
  local state = hand("KS", "2D", 500, 40)
  press(state, 1, "raise")
  local short = offered(state, 2)
  eq(short.raise.label, "ALL-IN", "a raise of five for what is left")
  eq(short.raise.cost, 30, "all of it")
  press(state, 2, "raise")
  local back = offered(state, 1)
  eq(back.call.cost, 10, "the short raise's price")
  falsy(back.raise, "no more raising")
  press(state, 1, "call")
  eq(state.pot, 80, "both stacks matched")
  eq(rules.nets(state)[2], -40, "the short stack's all")
end)

test("a stack of one ante is all-in as dealt and the hand plays itself", function()
  local state, events = hand("KS", "2D", 10, 500)
  truthy(rules.done(rules.new(entries(10, 500), 1, testing.fastRng(1), {})), "over as it is dealt")
  eq(#rules.waitingOn(state), 0, "nobody to wait on")
  eq(events[#events].type, "reveal", "the cards turn")
  for _, player in ipairs(rules.viewFor(state, nil).players) do truthy(player.card, "both cards show at once") end
end)

test("a stack that cannot ante posts what it has", function()
  local state = rules.new(entries(7, 500), 1, testing.fastRng(5), {})
  truthy(rules.done(state), "over as it is dealt")
  local nets = rules.nets(state)
  truthy(nets[1] == 7 or nets[1] == -7 or nets[1] == 0, "only what it posted moves: " .. nets[1])
  eq(nets[1] + nets[2], 0, "nets sum to zero")
end)

test("no loser ever pays past their stack", function()
  local rng = testing.fastRng(21)
  for _ = 1, 500 do
    local a, b = rng:below(120) + 1, rng:below(120) + 1
    local state = rules.new(entries(a, b), rng:below(2) + 1, rng, {})
    while not rules.done(state) do
      local seat = rules.waitingOn(state)[1]
      local list = rules.actions(state, seat)
      rules.act(state, seat, list[#list].id) -- always the most aggressive thing on offer
    end
    local nets = rules.nets(state)
    truthy(nets[1] >= -a and nets[2] >= -b, "within the stacks")
    eq(nets[1] + nets[2], 0, "nets sum to zero")
    eq(state.kept, nil, "no odd chip, ever")
  end
end)

-- ------------------------------------------------------------------ the clock

test("a timeout checks if it can and folds otherwise", function()
  local state = hand()
  eq(rules.auto(state, 1), "check", "nothing owed")
  press(state, 1, "check")
  eq(rules.auto(state, 2), "check", "still nothing owed")
  press(state, 2, "raise")
  eq(rules.auto(state, 1), "fold", "a bet to call")
  press(state, 1, rules.auto(state, 1))
  truthy(rules.done(state), "the timeout ended it")
end)

-- ------------------------------------------------------------------ secrets

test("a view is the other way round from what you would expect", function()
  local state = hand("KS", "2D")
  eq(rules.viewFor(state, 1).theirs, deck.parse("2D"), "seat 1 sees seat 2's card")
  eq(rules.viewFor(state, 2).theirs, deck.parse("KS"), "seat 2 sees seat 1's card")
  eq(rules.viewFor(state, nil).theirs, nil, "the public view has no card")
  eq(rules.viewFor(state, 7).theirs, nil, "nor does a stranger")
  for _, seat in ipairs({ 1, 2 }) do
    for _, player in ipairs(rules.viewFor(state, seat).players) do eq(player.card, nil, "no card in the player list") end
  end
end)

test("every step of a scripted hand keeps the secret", function()
  for _, script in ipairs({ { "check", "check" }, { "check", "raise", "call" }, { "raise", "raise", "raise", "call" }, { "raise", "fold" },
      { "check", "raise", "fold" } }) do
    local state = hand("KS", "2D")
    for _, id in ipairs(script) do
      secret(state)
      press(state, rules.waitingOn(state)[1], id)
    end
    truthy(rules.done(state), "the script ends the hand")
    for _, seat in ipairs({ 1, 2, false }) do
      local players = rules.viewFor(state, seat or nil).players
      truthy(players[1].card and players[2].card, "both cards at the end")
    end
  end
end)

test("events are the same whatever the cards", function()
  local rng = testing.fastRng(31)
  for _ = 1, 400 do
    local a = rng:below(90) + 11
    local b = rng:below(90) + 11
    local first = rng:below(2) + 1
    local real = rules.new(entries(a, b), first, testing.fastRng(1), {})
    local twin = withCards(real, (real.players[1].card + 17) % 52, (real.players[2].card + 34) % 52)
    while not rules.done(real) do
      local seat = rules.waitingOn(real)[1]
      local list = rules.actions(real, seat)
      local id = list[rng:below(#list) + 1].id
      truthy(kit.same(rules.act(real, seat, id), rules.act(twin, seat, id)), "an event differs with the cards")
    end
  end
end)

test("the state keeps no deck, and a view no seed", function()
  local state = hand()
  for key, value in pairs(state) do
    truthy(key ~= "deck" and key ~= "seed", "nothing of the shuffle in the state: " .. tostring(key))
    if type(value) == "table" and key ~= "players" then error("unexpected table in the state: " .. key) end
  end
end)

-- ------------------------------------------------------------------ the picture

--- A canvas that writes down what is drawn on it.
local function recorder()
  local c = { w = 121, h = 81, drawn = {}, rows = {} }
  local function note(text, x, y, wide)
    text = tostring(text)
    c.drawn[#c.drawn + 1] = text
    c.rows[#c.rows + 1] = { text = text, x = x, y = y, w = wide or #text }
  end
  function c:rect() end
  function c:frame() end
  function c:panel() end
  function c:text(x, y, text) note(text, x, y) end
  function c:textCenter(cx, y, text) note(text, cx - math.floor(#tostring(text) / 2), y) end
  function c:bigWidth(text, scale) return #tostring(text) * 6 * (scale or 1) end
  function c:big(x, y, text, _, scale) note(text, x, y, c:bigWidth(text, scale)) end
  function c:bigCenter(cx, y, text, _, scale) note(text, cx - math.floor(c:bigWidth(text, scale) / 2), y, c:bigWidth(text, scale)) end
  function c:has(text)
    for _, item in ipairs(self.drawn) do
      if item == text then return true end
    end
    return false
  end
  return c
end

local function draw(view, seat, anim)
  local c = recorder()
  plugin.seatView.draw(c, view, anim, { seat = seat, name = "Ann" })
  return c
end

test("a seat's wall draws the other card and not its own", function()
  local state = hand("KS", "2D")
  local first, second = draw(rules.viewFor(state, 1), 1), draw(rules.viewFor(state, 2), 2)
  truthy(first:has("2"), "seat 1's wall shows the 2")
  falsy(first:has("K"), "and not its own king")
  truthy(second:has("K"), "seat 2's wall shows the king")
  falsy(second:has("2"), "and not its own 2")
end)

test("a wall with no viewer draws no card until the end", function()
  local state = hand("KS", "2D")
  for seat = 1, 2 do
    local c = draw(rules.viewFor(state, nil), seat)
    falsy(c:has("K"), "no king on the public wall")
    falsy(c:has("2"), "no 2 on the public wall")
    truthy(c:has("?"), "two backs")
  end
  press(state, 1, "check")
  press(state, 2, "check")
  local c = draw(rules.viewFor(state, nil), 1)
  truthy(c:has("K") and c:has("2"), "both cards at the end")
end)

test("a wall says its own card is its own and it cannot be seen", function()
  local c = draw(rules.viewFor(hand(), 1), 1)
  truthy(c:has("YOUR CARD"), "named")
  truthy(c:has("This one is yours. You cannot see it"), "and explained")
end)

test("a wall says what it costs to call", function()
  local state = hand()
  press(state, 1, "raise")
  truthy(draw(rules.viewFor(state, 2), 2):has("YOUR TURN: 20 TO CALL"), "the price")
  truthy(draw(rules.viewFor(state, 1), 1):has("WAITING FOR Bea"), "the other wall waits")
end)

test("your own card only turns with the reveal", function()
  local state = hand("KS", "2D")
  press(state, 1, "raise")
  local events = press(state, 2, "call")
  local view = rules.viewFor(state, 1)
  falsy(draw(view, 1, { ev = events[1], t = 0.5 }):has("K"), "not while the chips land")
  falsy(draw(view, 1, { ev = { type = "reveal" }, t = 0.1 }):has("K"), "not as the reveal starts")
  truthy(draw(view, 1, { ev = { type = "reveal" }, t = 0.9 }):has("K"), "as it plays")
  truthy(draw(view, 1):has("K"), "and from then on")
  truthy(draw(view, 1):has("2"), "with the other card still up")
end)

test("a wall with a long name stays on the wall", function()
  local state = rules.new({ { seat = 1, name = "Abcdefghijklmnop", stack = 5000 }, { seat = 2, name = "WWWWWWWWWWWWWWWW", stack = 5000 } }, 1, testing.fastRng(2), {})
  press(state, 1, "raise")
  for _, seat in ipairs({ 1, 2, false }) do
    local c = draw(rules.viewFor(state, seat or nil), seat or 1)
    for _, item in ipairs(c.rows) do
      truthy(item.x >= 1 and item.x + item.w - 1 <= 121, "off the wall: " .. item.text)
    end
  end
end)

test("drawing an empty view does nothing", function()
  draw({}, 1)
  draw({ players = {} }, 1)
end)

-- ------------------------------------------------------------------ help and sounds

test("the help explains the reversal and the honour rule", function()
  local text = {}
  for _, line in ipairs(plugin.help()) do text[#text + 1] = type(line) == "table" and line[1] or line end
  local all = table.concat(text, " ")
  truthy(all:find("never your own", 1, true), "the reversal")
  truthy(all:find("walking round", 1, true), "that you can walk round")
  truthy(all:find("honour", 1, true), "that it is on honour")
  truthy(all:find("not part of the game", 1, true), "that it is not part of the game")
end)

test("every sound is one the casino can play", function()
  local names = { tap = 1, chip = 1, chipBig = 1, error = 1, deal = 1, flip = 1, start = 1, tick = 1, spin = 1, stop = 1, win = 1,
    bigWin = 1, lose = 1, push = 1, warn = 1 }
  local events = { { type = "deal" }, { type = "reveal" }, { type = "chips", amount = 20 }, { type = "chips", amount = 20, raise = true },
    { type = "action", id = "check" }, { type = "action", id = "fold" }, { type = "action", id = "call" }, { type = "action", id = "raise" } }
  local heard = 0
  for _, ev in ipairs(events) do
    local seconds, sound = plugin.event(ev)
    truthy(type(seconds) == "number" and seconds > 0, "a length for " .. ev.type)
    if sound then
      heard = heard + 1
      truthy(names[sound] or picks[sound], "a sound that exists: " .. sound)
    end
  end
  truthy(heard >= 5, "the game makes noise")
end)
