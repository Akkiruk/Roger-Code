-- group_community_test.lua
-- Fixed limit Hold'em and Omaha on Big Table, and Hold'em on Duel. lib/casino/group/community.lua is the rules and the pictures.

local canvas = require("lib.casino.canvas")
local community = require("lib.casino.group.community")
local deck = require("lib.casino.deck")
local kit = require("group_kit")
local poker = require("lib.casino.poker")
local testing = require("testing")

local holdem = kit.plugin("BigTable", "holdem")
local omaha = kit.plugin("BigTable", "omaha")
local duel = kit.plugin("Duel", "holdem")
local rules = holdem.rules

local function falsy(value, what)
  if value then error((what or "value") .. " should be false", 2) end
end

local function cards(text)
  local list = {}
  for name in text:gmatch("%S+") do list[#list + 1] = deck.parse(name) end
  return list
end

--- A hand of count players with these stacks, button first in the list unless button says so.
local function hand(plugin, stacks, button, seed)
  local entries = {}
  for index, stack in ipairs(stacks) do entries[index] = { seat = index, name = "P" .. index, stack = stack } end
  local state, events = plugin.rules.new(entries, button or 1, testing.fastRng(seed or 7), {})
  return state, events
end

--- The deck's next cards, in the order they will be dealt.
local function stack(state, text)
  local list = cards(text)
  state.deck = {}
  for index = #list, 1, -1 do state.deck[#state.deck + 1] = list[index] end
end

local function press(plugin, state, seat, id)
  local events = plugin.rules.act(state, seat, id)
  testing.truthy(events and #events > 0, id .. " by seat " .. tostring(seat) .. " should work")
  return events
end

local function offered(plugin, state, seat)
  local ids = {}
  for _, action in ipairs(plugin.rules.actions(state, seat)) do ids[action.id] = action end
  return ids
end

local function turnSeat(plugin, state)
  return plugin.rules.waitingOn(state)[1]
end

-- ------------------------------------------------------------------ the order of play

testing.test("three players: blinds left of the button, first to act left of the big blind", function()
  local state = hand(holdem, { 500, 500, 500 }, 1)
  testing.eq(state.players[2].total, 5)
  testing.eq(state.players[3].total, 10)
  testing.eq(state.players[1].total, 0)
  testing.eq(turnSeat(holdem, state), 1)
  press(holdem, state, 1, "call")
  testing.eq(turnSeat(holdem, state), 2)
  press(holdem, state, 2, "call")
  testing.eq(turnSeat(holdem, state), 3, "the big blind has an option")
  testing.truthy(offered(holdem, state, 3).check and offered(holdem, state, 3).raise)
  press(holdem, state, 3, "check")
  testing.eq(state.phase, "flop")
  testing.eq(#state.board, 3)
  testing.eq(turnSeat(holdem, state), 2, "the first live seat left of the button opens after the flop")
end)

testing.test("heads-up: the button posts the small blind, acts first pre-flop and last after", function()
  for button = 1, 2 do
    local other = 3 - button
    local state = hand(duel, { 500, 500 }, button)
    testing.eq(state.players[button].total, 5)
    testing.eq(state.players[other].total, 10)
    testing.eq(turnSeat(duel, state), button)
    press(duel, state, button, "call")
    testing.eq(turnSeat(duel, state), other)
    press(duel, state, other, "check")
    testing.eq(state.phase, "flop")
    testing.eq(turnSeat(duel, state), other)
    press(duel, state, other, "check")
    testing.eq(turnSeat(duel, state), button)
  end
end)

testing.test("the bet is 10 until the turn, then 20", function()
  local state = hand(holdem, { 500, 500 }, 1)
  testing.eq(offered(holdem, state, 1).raise.cost, 15, "call 5 and raise 10")
  press(holdem, state, 1, "call")
  press(holdem, state, 2, "check")
  testing.eq(offered(holdem, state, 2).raise.cost, 10)
  testing.eq(offered(holdem, state, 2).raise.label, "BET")
  press(holdem, state, 2, "check")
  press(holdem, state, 1, "check")
  testing.eq(state.phase, "turn")
  testing.eq(offered(holdem, state, 2).raise.cost, 20)
  press(holdem, state, 2, "check")
  press(holdem, state, 1, "check")
  testing.eq(state.phase, "river")
  testing.eq(offered(holdem, state, 2).raise.cost, 20)
end)

testing.test("the big blind counts as the bet, so three raises close a round pre-flop", function()
  local state = hand(holdem, { 500, 500, 500 }, 1)
  press(holdem, state, 1, "raise")
  press(holdem, state, 2, "raise")
  press(holdem, state, 3, "raise")
  falsy(offered(holdem, state, 1).raise, "that is the cap")
  testing.eq(#rules.act(state, 1, "raise"), 0)
  testing.eq(state.current, 40)
  press(holdem, state, 1, "call")
  press(holdem, state, 2, "call")
  testing.eq(state.phase, "flop")
  for _, player in ipairs(state.players) do testing.eq(player.total, 40) end
end)

testing.test("a bet and three raises on the flop", function()
  local state = hand(holdem, { 500, 500 }, 1)
  press(holdem, state, 1, "call")
  press(holdem, state, 2, "check")
  press(holdem, state, 2, "raise")
  press(holdem, state, 1, "raise")
  press(holdem, state, 2, "raise")
  press(holdem, state, 1, "raise")
  falsy(offered(holdem, state, 2).raise)
  testing.eq(state.current, 40)
end)

-- ------------------------------------------------------------------ the deal

testing.test("hole cards and the board never repeat a card", function()
  local rng = testing.fastRng(3)
  for _ = 1, 200 do
    local entries = {}
    for index = 1, 8 do entries[index] = { seat = index, name = "P" .. index, stack = 500 } end
    local state = omaha.rules.new(entries, 1, rng, {})
    local seen = {}
    for _, player in ipairs(state.players) do
      testing.eq(#player.hole, 4)
      for _, card in ipairs(player.hole) do
        falsy(seen[card])
        seen[card] = true
      end
    end
    for _, card in ipairs(state.deck) do
      falsy(seen[card])
      seen[card] = true
    end
    local total = 0
    for _ in pairs(seen) do total = total + 1 end
    testing.eq(total, 52)
  end
end)

-- ------------------------------------------------------------------ what a hand is worth

testing.test("Omaha must use exactly two hole cards and three from the board", function()
  -- Four to the royal on the board and one spade in the hand is not a flush in Omaha, and is a royal in Hold'em
  local board = cards("AS KS QS JS 2D")
  local hole = cards("10S 3C 4C 5C")
  testing.eq(poker.category(community.score("holdem", hole, board)), poker.ROYAL)
  testing.truthy(poker.category(community.score("omaha", hole, board)) < poker.FLUSH)

  -- Two pair on the board and a pair in the hand: the board's pairs cannot both play
  local paired = community.omahaScore(cards("KC KD 3C 4D"), cards("AS AH QC QD 2S"))
  testing.eq(poker.category(paired), poker.TWO_PAIR)

  -- Trips in the hand play only as a pair
  local trips = community.omahaScore(cards("7C 7D 7H 2C"), cards("AS KD QH 9C 4D"))
  testing.eq(poker.category(trips), poker.PAIR)

  -- A hand of four aces cannot use three of them
  local aces = community.omahaScore(cards("AC AD AH AS"), cards("KS QD 9H 5C 2D"))
  testing.eq(poker.category(aces), poker.PAIR)

  -- A straight flush with two in hand
  local flush = community.omahaScore(cards("9H 8H 2C 2D"), cards("7H 6H 5H AS KD"))
  testing.eq(poker.category(flush), poker.STRAIGHT_FLUSH)
end)

testing.test("Omaha's best equals a brute force over every legal five", function()
  local rng = testing.fastRng(11)
  for _ = 1, 400 do
    local pack = deck.shuffle(deck.fresh(1), rng)
    local hole = { pack[1], pack[2], pack[3], pack[4] }
    local board = { pack[5], pack[6], pack[7], pack[8], pack[9] }
    local best = -1
    for a = 1, 3 do
      for b = a + 1, 4 do
        for x = 1, 3 do
          for y = x + 1, 4 do
            for z = y + 1, 5 do
              best = math.max(best, (poker.evaluate({ hole[a], hole[b], board[x], board[y], board[z] })))
            end
          end
        end
      end
    end
    testing.eq(community.omahaScore(hole, board), best)
  end
end)

testing.test("Omaha pays the two-and-three hand at showdown, not the one a Hold'em eye reads", function()
  local state = hand(omaha, { 500, 500 }, 1)
  state.players[1].hole = cards("10S 3C 4C 5C")     -- plays a pair of tens at best on this board
  state.players[2].hole = cards("AH KH 8D 8C")      -- two pair, aces and kings
  stack(state, "AS KS QS JS 2D")
  while not omaha.rules.done(state) do
    local seat = turnSeat(omaha, state)
    press(omaha, state, seat, offered(omaha, state, seat).check and "check" or "call")
  end
  testing.truthy(omaha.rules.nets(state)[2] > 0)
end)

-- ------------------------------------------------------------------ side pots, short stacks and uncalled chips

testing.test("a short stack wins only the main pot and the side pot goes on", function()
  local state = hand(holdem, { 500, 25, 500 }, 3)
  -- Button 3, so seat 1 is the small blind, seat 2 the big blind, seat 3 first
  state.players[1].hole = cards("KC KD")
  state.players[2].hole = cards("AC AD")
  state.players[3].hole = cards("QC QD")
  stack(state, "2S 7H 9D 3C 5S")
  press(holdem, state, 3, "raise")     -- 20
  press(holdem, state, 1, "raise")     -- 30
  press(holdem, state, 2, "call")      -- all-in for 25 of 30
  press(holdem, state, 3, "call")
  while not rules.done(state) do
    local seat = turnSeat(holdem, state)
    press(holdem, state, seat, offered(holdem, state, seat).check and "check" or "call")
  end
  local nets = rules.nets(state)
  testing.eq(nets[2], 50, "the aces take 25 from each")
  testing.eq(nets[1], -25 + 5, "the kings pay the aces and take the 5 side pot from the queens")
  testing.eq(nets[3], -30)
end)

testing.test("a big blind all-in for less: the small blind owes nothing and the extra comes back", function()
  local state = hand(duel, { 500, 3 }, 1)
  testing.truthy(duel.rules.done(state), "nobody has anyone to bet against")
  testing.eq(#state.board, 5)
  local nets = duel.rules.nets(state)
  testing.eq(nets[1] + nets[2], 0)
  testing.truthy(math.abs(nets[1]) <= 3, "only 3 can change hands")
end)

testing.test("a big blind short of the blind still leaves the caller the amount really bet", function()
  local state = hand(duel, { 500, 7 }, 1)
  testing.eq(turnSeat(duel, state), 1)
  testing.eq(offered(duel, state, 1).call.cost, 2, "5 is in, and 7 is all there is to match")
  falsy(offered(duel, state, 1).raise, "nobody left to raise")
  press(duel, state, 1, "call")
  testing.truthy(duel.rules.done(state))
  testing.eq(state.players[1].total, 7)
end)

testing.test("a small blind short of the blind runs out against the big blind with no action", function()
  local state = hand(duel, { 3, 500 }, 1)
  testing.truthy(duel.rules.done(state))
  testing.truthy(math.abs(duel.rules.nets(state)[1]) <= 3)
end)

testing.test("an all-in of half a bet or more counts as a raise and reopens the betting", function()
  local state = hand(holdem, { 500, 500, 15 }, 3)
  -- Seat 3 is the button and first. 15 is 5 over the 10 to call, short of a full raise and half of one
  testing.eq(offered(holdem, state, 3).raise.label, "ALL-IN")
  press(holdem, state, 3, "raise")
  testing.eq(state.current, 15)
  testing.eq(state.bets, 2)
  testing.eq(offered(holdem, state, 1).call.cost, 10)
end)

testing.test("an all-in under half a bet sets the price, uses up no bet and does not reopen the betting", function()
  -- Seat 1 is the button and first, seat 2 the small blind, seat 3 the big blind with 21
  local state = hand(holdem, { 200, 200, 21 }, 1)
  press(holdem, state, 1, "raise")
  press(holdem, state, 2, "call")
  testing.eq(state.bets, 2, "the blind and a raise")
  press(holdem, state, 3, "raise")
  testing.eq(state.current, 21, "one chip over")
  testing.eq(state.bets, 2, "it does not count")
  testing.eq(offered(holdem, state, 1).call.cost, 1, "the raiser owes the chip")
  falsy(offered(holdem, state, 1).raise, "and has no raise")
  press(holdem, state, 1, "call")
  falsy(offered(holdem, state, 2).raise, "nor has the caller")
end)

testing.test("everyone folds to a raise: no board, no reveal, the winner keeps the blinds", function()
  local state = hand(holdem, { 500, 500, 500 }, 1)
  press(holdem, state, 1, "raise")
  press(holdem, state, 2, "fold")
  press(holdem, state, 3, "fold")
  testing.truthy(rules.done(state))
  testing.eq(#state.board, 0)
  testing.eq(rules.nets(state)[1], 15)
  for _, player in ipairs(rules.viewFor(state, nil).players) do testing.eq(player.hole, nil) end
  testing.eq(rules.result(state, 1).kind, "win")
  testing.eq(rules.result(state, 2).kind, "lose")
end)

testing.test("a split's odd chip goes to the owner", function()
  local state = hand(holdem, { 500, 500, 500 }, 1)
  state.players[1].hole = cards("2C 3D")
  state.players[2].hole = cards("4C 4D")
  state.players[3].hole = cards("2D 3C")
  stack(state, "AH KH QS JD 10C")   -- the board plays for both
  press(holdem, state, 1, "call")
  press(holdem, state, 2, "fold")   -- the 5 stays in: a pot of 25 between two
  press(holdem, state, 3, "check")
  while not rules.done(state) do
    press(holdem, state, turnSeat(holdem, state), "check")
  end
  testing.eq(state.players[3].won, 12)
  testing.eq(state.players[1].won, 12)
  testing.eq(state.kept, 1, "one chip left over")
  local nets = rules.nets(state)
  testing.eq(nets[1] + nets[2] + nets[3], -1, "the owner keeps it")
end)

-- ------------------------------------------------------------------ illegal input

testing.test("illegal input does nothing", function()
  local rng = testing.fastRng(5)
  for _ = 1, 100 do
    local state = hand(holdem, { 500, 500, 500 }, 1 + rng:below(3), 1 + rng:below(100000))
    local steps = 0
    while not rules.done(state) and steps < 100 do
      steps = steps + 1
      local before = kit.plain(state)
      local seat = turnSeat(holdem, state)
      local wrongSeat = seat % 3 + 1
      for _, id in ipairs({ "fold", "call", "check", "raise" }) do
        testing.eq(#rules.act(state, wrongSeat, id), 0, "out of turn")
        testing.eq(#rules.act(state, nil, id), 0, "no seat")
        testing.eq(#rules.act(state, 99, id), 0, "no such seat")
      end
      for _, id in ipairs({ "", "bet", "FOLD", "fold ", 7, {}, false }) do
        testing.eq(#rules.act(state, seat, id), 0, "no such move")
      end
      local have = offered(holdem, state, seat)
      for _, id in ipairs({ "fold", "call", "check", "raise" }) do
        if not have[id] then testing.eq(#rules.act(state, seat, id), 0, "not offered: " .. id) end
      end
      testing.truthy(kit.same(before, state), "the state did not change")
      local list = {}
      for id in pairs(have) do list[#list + 1] = id end
      table.sort(list)
      press(holdem, state, seat, list[rng:below(#list) + 1])
    end
    local final = kit.plain(state)
    for _, id in ipairs({ "fold", "call", "check", "raise" }) do testing.eq(#rules.act(state, 1, id), 0, "the hand is over") end
    testing.truthy(kit.same(final, state))
  end
end)

testing.test("auto checks when it is free and folds when it is not", function()
  local state = hand(holdem, { 500, 500 }, 1)
  testing.eq(rules.auto(state, 1), "fold")
  press(holdem, state, 1, "call")
  testing.eq(rules.auto(state, 2), "check")
end)

-- ------------------------------------------------------------------ secrets

local VIEW_KEYS = {
  variant = true, holes = true, phase = true, over = true, uncontested = true, board = true, pot = true, current = true, size = true,
  bets = true, button = true, turn = true, players = true, seat = true, hole = true, hand = true, toCall = true,
}
local PLAYER_KEYS = {
  seat = true, name = true, stack = true, bet = true, total = true, folded = true, allin = true, last = true, blind = true,
  hole = true, handName = true, net = true,
}
local EVENT_KEYS = { type = true, phase = true, shown = true, count = true, seat = true, id = true, amount = true, uncontested = true }

--- Every view of this state, against what that viewer may know.
local function checkViews(plugin, state)
  local viewers = { false }
  for _, player in ipairs(state.players) do viewers[#viewers + 1] = player.seat end
  for _, viewer in ipairs(viewers) do
    local seat = viewer or nil
    local view = plugin.rules.viewFor(state, seat)
    for key in pairs(view) do testing.truthy(VIEW_KEYS[key], "a view carries " .. tostring(key)) end
    testing.eq(view.deck, nil)
    if seat then
      local own
      for _, player in ipairs(state.players) do
        if player.seat == seat then own = player end
      end
      testing.truthy(kit.same(view.hole, own.hole))
    else
      testing.eq(view.hole, nil)
      testing.eq(view.hand, nil)
      testing.eq(view.toCall, nil)
    end
    testing.eq(#view.board, #state.board)
    for index, shown in ipairs(view.players) do
      for key in pairs(shown) do testing.truthy(PLAYER_KEYS[key], "a player's view carries " .. tostring(key)) end
      local real = state.players[index]
      if state.phase ~= "over" or real.folded or state.uncontested then
        testing.eq(shown.hole, nil, "a hand stayed hidden")
        testing.eq(shown.handName, nil, "and its name")
      else
        testing.truthy(kit.same(shown.hole, real.hole), "what reached a showdown is turned over")
      end
    end
  end
end

local function checkEvents(events)
  for _, ev in ipairs(events or {}) do
    for key in pairs(ev) do testing.truthy(EVENT_KEYS[key], "an event carries " .. tostring(key)) end
  end
end

testing.test("no view shows another seat's cards, at any step of any hand", function()
  local rng = testing.fastRng(21)
  for round = 1, 300 do
    local plugin = round % 2 == 0 and omaha or holdem
    local stacks = {}
    for index = 1, 2 + rng:below(7) do stacks[index] = 30 + rng:below(300) end
    local state, events = hand(plugin, stacks, 1 + rng:below(#stacks), 1 + rng:below(1000000))
    checkEvents(events)
    checkViews(plugin, state)
    while not plugin.rules.done(state) do
      local seat = turnSeat(plugin, state)
      local list = plugin.rules.actions(state, seat)
      checkEvents(press(plugin, state, seat, list[rng:below(#list) + 1].id))
      checkViews(plugin, state)
    end
    if round % 50 == 0 then testing.breathe() end
  end
end)

-- ------------------------------------------------------------------ the money, in random hands

--- Random stacks, some short, so all-ins and side pots turn up all the time.
local function randomStacks(rng, seats)
  local stacks = {}
  for index = 1, seats do
    local roll = rng:below(4)
    if roll == 0 then
      stacks[index] = 1 + rng:below(30)
    elseif roll == 1 then
      stacks[index] = 10 + rng:below(120)
    else
      stacks[index] = 100 + rng:below(900)
    end
  end
  return stacks
end

local function simulate(plugin, rounds, seatsFrom, seatsTo, seed)
  local rng = testing.fastRng(seed)
  local sidePots, showdowns = 0, 0
  for round = 1, rounds do
    local stacks = randomStacks(rng, seatsFrom + rng:below(seatsTo - seatsFrom + 1))
    local state = hand(plugin, stacks, 1 + rng:below(#stacks), 1 + rng:below(2000000))
    local steps = 0
    while not plugin.rules.done(state) do
      steps = steps + 1
      testing.truthy(steps < 200, "a hand ended")
      local seat = turnSeat(plugin, state)
      local list = plugin.rules.actions(state, seat)
      testing.truthy(#list > 0, "whoever is up has a move")
      -- Passive enough to reach showdowns: fold rarely
      local pick = list[rng:below(#list) + 1]
      if pick.id == "fold" and rng:below(4) > 0 then pick = list[2] end
      press(plugin, state, seat, pick.id)
    end
    local nets, total, pot, paid = plugin.rules.nets(state), 0, 0, 0
    for index, player in ipairs(state.players) do
      local net = nets[player.seat]
      testing.truthy(net == math.floor(net), "whole")
      testing.truthy(net >= -stacks[index], "never more than the stack")
      testing.eq(player.stack, stacks[index] + net)
      testing.truthy(player.stack >= 0)
      total = total + net
      pot = pot + player.total
      paid = paid + player.won
      if player.folded then testing.truthy(net <= 0, "a folded hand wins nothing") end
    end
    testing.eq(total, -(state.kept or 0), "players' nets sum to zero, less the owner's odd chips")
    testing.eq(pot, paid + (state.kept or 0), "the pot is paid out whole")
    if not state.uncontested then
      showdowns = showdowns + 1
      testing.eq(#state.board, 5)
      if #state.pots > 1 then sidePots = sidePots + 1 end
    end
    if round % 200 == 0 then testing.breathe() end
  end
  return sidePots, showdowns
end

testing.test("2500 random Hold'em hands: nets sum to zero and the pot is paid whole", function()
  local sidePots, showdowns = simulate(holdem, 2500, 2, 8, 101)
  testing.truthy(sidePots > 100, "side pots came up: " .. sidePots)
  testing.truthy(showdowns > 500, "showdowns came up: " .. showdowns)
end)

testing.test("1500 random Omaha hands: nets sum to zero and the pot is paid whole", function()
  local sidePots = simulate(omaha, 1500, 2, 8, 202)
  testing.truthy(sidePots > 100, "side pots came up: " .. sidePots)
end)

testing.test("1000 random heads-up hands: nets sum to zero", function()
  simulate(duel, 1000, 2, 2, 303)
end)

-- ------------------------------------------------------------------ the whole contract

testing.test("Hold'em keeps the contract", function()
  kit.fuzz(holdem, { rounds = 300, seats = { 2, 3, 5, 8 }, stack = 500, absent = 15 })
  kit.fuzz(holdem, { rounds = 150, seats = { 2, 4, 8 }, stack = 25, absent = 5, seed = 9 })
end)

testing.test("Omaha keeps the contract", function()
  kit.fuzz(omaha, { rounds = 200, seats = { 2, 3, 5, 8 }, stack = 500, absent = 15 })
  kit.fuzz(omaha, { rounds = 100, seats = { 2, 8 }, stack = 25, absent = 5, seed = 9 })
end)

testing.test("Heads-Up Hold'em keeps the contract", function()
  kit.fuzz(duel, { rounds = 300, seats = { 2 }, stack = 500, absent = 15 })
  kit.fuzz(duel, { rounds = 100, seats = { 2 }, stack = 12, absent = 5, seed = 9 })
end)

testing.test("every state goes through textutils and comes back the same", function()
  if not textutils then return end -- plain Lua has no textutils: kit.plain already proved the state is plain data
  local rng = testing.fastRng(31)
  for round = 1, 60 do
    local plugin = round % 2 == 0 and omaha or holdem
    local stacks = randomStacks(rng, 2 + rng:below(7))
    local state = hand(plugin, stacks, 1, 1 + rng:below(100000))
    while true do
      local back = textutils.unserialize(textutils.serialize(state))
      testing.truthy(kit.same(back, state), "the state came back")
      local view = plugin.rules.viewFor(state, state.players[1].seat)
      testing.truthy(kit.same(textutils.unserialize(textutils.serialize(view)), view), "the view came back")
      if plugin.rules.done(state) then break end
      state = back
      local seat = turnSeat(plugin, state)
      local list = plugin.rules.actions(state, seat)
      press(plugin, state, seat, list[rng:below(#list) + 1].id)
    end
    if round % 20 == 0 then testing.breathe() end
  end
end)

-- ------------------------------------------------------------------ the pictures

--- A canvas that fails on text past its edge, so a layout that runs off the wall is a test failure.
local function strictCanvas(w, h)
  local c = canvas.new(nil, w, h)
  local text = c.text
  c.text = function(self, x, y, str, fg, bg)
    str = tostring(str)
    if x < 1 or x + #str - 1 > w or y < 1 or y > h then error("text off the wall at " .. x .. "," .. y .. ": " .. str, 2) end
    return text(self, x, y, str, fg, bg)
  end
  return c
end

local function drawAll(plugin, state, w, h, seats)
  local c = strictCanvas(w, h)
  if plugin.tableView then plugin.tableView.draw(c, plugin.rules.viewFor(state, nil), nil, { waiting = {}, seats = {} }) end
  local seatCanvas = strictCanvas(seats, 52)
  if plugin.tableView then
    for _, player in ipairs(state.players) do
      plugin.seatView.draw(seatCanvas, plugin.rules.viewFor(state, player.seat), nil, { seat = player.seat, name = player.name })
    end
    plugin.seatView.draw(seatCanvas, plugin.rules.viewFor(state, nil), nil, {})
  else
    for _, player in ipairs(state.players) do
      plugin.seatView.draw(strictCanvas(w, h), plugin.rules.viewFor(state, player.seat), nil, { seat = player.seat, name = player.name })
    end
    plugin.seatView.draw(strictCanvas(w, h), plugin.rules.viewFor(state, nil), nil, {})
  end
end

testing.test("the pictures draw every step with long names, in bounds", function()
  local rng = testing.fastRng(41)
  for round = 1, 45 do
    local plugin = ({ holdem, omaha, duel })[round % 3 + 1]
    local count = plugin == duel and 2 or 2 + rng:below(7)
    local entries = {}
    for index = 1, count do
      entries[index] = { seat = index, name = "AVeryLongPlayerName" .. index, stack = 20 + rng:below(2000) }
    end
    local state = plugin.rules.new(entries, 1, rng, {})
    while true do
      drawAll(plugin, state, 121, 81, 78)
      if plugin.rules.done(state) then break end
      local seat = turnSeat(plugin, state)
      local list = plugin.rules.actions(state, seat)
      press(plugin, state, seat, list[rng:below(#list) + 1].id)
    end
  end
end)

testing.test("a picture holds a street's cards back while the event plays", function()
  local state = hand(holdem, { 500, 500 }, 1)
  press(holdem, state, 1, "call")
  local events = press(holdem, state, 2, "check")
  local street
  for _, ev in ipairs(events) do
    if ev.type == "street" then street = ev end
    testing.eq(type(ev.shown), "number", "every event says how much of the board is out")
  end
  testing.eq(street.shown, 3)
  testing.eq(street.count, 3)
end)

testing.test("results fit and name no hidden hand", function()
  local state = hand(holdem, { 500, 500, 500 }, 1)
  press(holdem, state, 1, "raise")
  press(holdem, state, 2, "call")
  press(holdem, state, 3, "fold")
  while not rules.done(state) do
    local seat = turnSeat(holdem, state)
    press(holdem, state, seat, offered(holdem, state, seat).check and "check" or "call")
  end
  testing.eq(rules.result(state, 3).detail, "-10  You folded")
  local shared = rules.result(state, nil)
  testing.eq(type(shared.title), "string")
  testing.eq(rules.risk(state, 3), 10)
end)

testing.test("the plugins declare what the cabinets expect", function()
  testing.eq(holdem.id, "holdem")
  testing.eq(omaha.id, "omaha")
  testing.eq(duel.id, "holdem")
  testing.eq(holdem.maxSeats, 8)
  testing.eq(duel.maxSeats, 2)
  testing.eq(duel.tableView, nil)
  testing.truthy(#holdem.help() > 3 and #omaha.help() > 3)
end)
