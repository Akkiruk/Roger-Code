-- group_stud_test.lua
-- Seven Card Stud on Big Table: the bring-in, who acts first, the limits, the shared card, side pots, what each seat may see, and
-- thousands of random hands with their chips added up.

local canvas = require("lib.casino.canvas")
local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")
local kit = require("group_kit")
local t = require("testing")

local plugin = kit.plugin("BigTable", "stud")
local rules = plugin.rules

-- ------------------------------------------------------------------ rigged hands

--- An rng whose shuffle leaves wanted on the top of the deck, first drawn first. deck.lua's shuffle is undone by working out each swap.
local function riggedRng(wanted)
  local used, order = {}, {}
  for _, card in ipairs(wanted) do used[card] = true end
  for card = 0, 51 do
    if not used[card] then order[#order + 1] = card end
  end
  for index = #wanted, 1, -1 do order[#order + 1] = wanted[index] end
  local now = deck.fresh(1)
  local picks = {}
  for i = 52, 2, -1 do
    local j
    for look = 1, i do
      if now[look] == order[i] then j = look end
    end
    picks[#picks + 1] = j - 1
    now[i], now[j] = now[j], now[i]
  end
  local at = 0
  return { below = function(_, n)
    at = at + 1
    t.truthy(picks[at] < n, "a rigged swap is in range")
    return picks[at]
  end }
end

--- Deal a hand from what each position holds: { down, down, up, up, up, up, down } by name, in the order of entries.
-- The button is the last position, so position 1 is dealt first. A missing card is whatever is left.
local function deal(script, stacks, button)
  local count = #script
  button = button or count
  local spare, taken = {}, {}
  for _, cards in ipairs(script) do
    for _, name in pairs(cards) do taken[deck.parse(name)] = true end
  end
  for card = 51, 0, -1 do
    if not taken[card] then spare[#spare + 1] = card end
  end
  local function card(position, slot)
    local name = script[position][slot]
    return name and deck.parse(name) or table.remove(spare)
  end
  local wanted = {}
  for slot = 1, 7 do
    for step = 1, count do
      local position = (button + step - 1) % count + 1
      if slot <= 6 or #wanted < 52 then wanted[#wanted + 1] = card(position, slot) end
    end
  end
  local entries = {}
  for position = 1, count do
    entries[position] = { seat = position, name = "P" .. position, stack = stacks and stacks[position] or 1000 }
  end
  local state, events = rules.new(entries, button, riggedRng(wanted), {})
  return state, events
end

local function player(state, seat)
  for _, each in ipairs(state.players) do
    if each.seat == seat then return each end
  end
end

local function hasAction(state, seat, id)
  for _, action in ipairs(rules.actions(state, seat)) do
    if action.id == id then return action end
  end
  return nil
end

--- Whoever is up does id, which must work.
local function go(state, id)
  local seat = rules.waitingOn(state)[1]
  t.truthy(seat, "somebody is up for " .. id)
  local events = rules.act(state, seat, id)
  t.truthy(#events > 0, id .. " worked for seat " .. seat)
  return seat, events
end

--- Everyone calls or checks through the current street.
local function passive(state, street)
  local guard = 0
  while not rules.done(state) and state.street < street do
    guard = guard + 1
    t.truthy(guard < 200, "the street ended")
    local seat = rules.waitingOn(state)[1]
    local id = hasAction(state, seat, "bringin") and "bringin" or hasAction(state, seat, "check") and "check" or "call"
    t.truthy(#rules.act(state, seat, id) > 0, "a passive move worked")
  end
end

--- A deep copy with stand-ins for what must stay hidden from this viewer. Any stand-in in a view is a leak.
local LEAK_BASE = 9000
local function marked(state, viewer)
  local copy = kit.plain(state)
  local marks = {}
  local function mark(list, index)
    local value = LEAK_BASE + #marks + 1
    marks[#marks + 1] = value
    list[index] = value
  end
  local over = state.phase == "over"
  for _, each in ipairs(copy.players) do
    local revealed = over and not copy.uncontested and not each.folded
    if each.seat ~= viewer and not revealed then
      for index in ipairs(each.down) do mark(each.down, index) end
      if each.folded then
        for index in ipairs(each.up) do mark(each.up, index) end
      end
    end
  end
  for index in ipairs(copy.deck) do mark(copy.deck, index) end
  return copy, marks
end

local function checkSecrets(state, seats)
  local viewers = { false }
  for _, seat in ipairs(seats) do viewers[#viewers + 1] = seat end
  for _, viewer in ipairs(viewers) do
    local seat = viewer or nil
    local copy, marks = marked(state, seat)
    local view = rules.viewFor(copy, seat)
    for _, value in ipairs(marks) do
      if kit.shows(view, value) then error("seat " .. tostring(seat) .. " can see a hidden card", 0) end
    end
    t.eq(view.deck, nil, "a view holds no deck")
    if seat == nil then t.eq(view.me, nil, "the public view is nobody's") end
  end
end

--- Whether a round's moves ever named more than the public record.
local EVENT_KEYS = { type = true, street = true, seat = true, id = true, uncontested = true, community = true }
local function checkEvents(state, events)
  for _, ev in ipairs(events or {}) do
    for key, value in pairs(ev) do
      if not EVENT_KEYS[key] then error("an event carries " .. tostring(key), 0) end
      if key == "community" then t.eq(value, state.community, "the only card in an event is the shared one") end
    end
  end
end

--- This plugin with every act and new checked for what its events give away.
local function watched()
  local copy = {}
  for key, value in pairs(plugin) do copy[key] = value end
  local wrapped = {}
  for key, value in pairs(rules) do wrapped[key] = value end
  wrapped.act = function(state, seat, id, value, rng)
    local events = rules.act(state, seat, id, value, rng)
    checkEvents(state, events)
    return events
  end
  wrapped.new = function(entries, button, rng, keep)
    local state, events = rules.new(entries, button, rng, keep)
    checkEvents(state, events)
    return state, events
  end
  copy.rules = wrapped
  return copy
end

--- Fold now and then, so most hands reach the river.
local function mostlyStay(_, _, actions, rng)
  local list = {}
  for _, action in ipairs(actions) do
    if action.id ~= "fold" then list[#list + 1] = action end
  end
  if #list == 0 or rng:below(12) == 0 then return nil end
  local action = list[rng:below(#list) + 1]
  return action.id, action.value
end

-- ------------------------------------------------------------------ third street

t.test("stud deals two down and one up, and antes everyone", function()
  local state = deal({ {}, {}, {} })
  t.eq(#state.deck, 52 - 9, "cards left")
  for _, each in ipairs(state.players) do
    t.eq(#each.down, 2, "two down")
    t.eq(#each.up, 1, "one up")
    t.eq(each.total, rules.ANTE, "the ante")
  end
end)

t.test("the lowest up-card opens, suit breaking a tie", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } })
  t.eq(rules.waitingOn(state)[1], 2, "the three")
  state = deal({ { nil, nil, "3H" }, { nil, nil, "3C" }, { nil, nil, "3D" } })
  t.eq(rules.waitingOn(state)[1], 2, "clubs are lowest")
end)

t.test("the bring-in can't be folded, costs the bring-in, and can be completed", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } })
  t.eq(#rules.act(state, 2, "fold"), 0, "no folding it")
  t.eq(#rules.act(state, 2, "check"), 0, "no checking it")
  t.eq(hasAction(state, 2, "bringin").cost, rules.BRING_IN, "its cost")
  t.eq(hasAction(state, 2, "raise").cost, rules.SMALL, "completing's cost")
  t.eq(hasAction(state, 2, "raise").sub, "Complete " .. rules.SMALL, "its name")
  go(state, "bringin")
  t.eq(state.current, rules.BRING_IN, "the price")
  t.eq(rules.waitingOn(state)[1], 3, "the turn goes left")
  t.eq(hasAction(state, 3, "call").cost, rules.BRING_IN, "calling it")
  t.eq(hasAction(state, 3, "raise").cost, rules.SMALL, "completing it")
  t.eq(hasAction(state, 3, "raise").sub, "Complete " .. rules.SMALL, "the next player completes, not raises")
  go(state, "raise")
  t.eq(state.current, rules.SMALL, "completed")
  t.eq(state.bets, 1, "a completion is the bet")
  t.eq(hasAction(state, 1, "raise").cost, 2 * rules.SMALL, "a raise on top")
end)

t.test("a street of bring-in and calls gives the bring-in no option", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } })
  go(state, "bringin")
  go(state, "call")
  go(state, "call")
  t.eq(state.street, 4, "next street")
  t.eq(player(state, 2).total, rules.ANTE + rules.BRING_IN, "the bring-in is all they put in")
end)

t.test("the bring-in player gets to answer a completion", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } })
  go(state, "bringin")
  go(state, "raise")
  go(state, "call")
  t.eq(rules.waitingOn(state)[1], 2, "back to the bring-in")
  t.eq(hasAction(state, 2, "call").cost, rules.SMALL - rules.BRING_IN, "the difference")
end)

t.test("a short bring-in goes all-in and the price stays", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } }, { 500, rules.ANTE + 2, 500 })
  t.eq(hasAction(state, 2, "raise"), nil, "nothing to complete with")
  t.eq(hasAction(state, 2, "bringin").cost, 2, "what is left")
  go(state, "bringin")
  t.truthy(player(state, 2).allin, "all-in")
  t.eq(state.current, rules.BRING_IN, "the others still owe the bring-in")
  t.eq(hasAction(state, 3, "call").cost, rules.BRING_IN, "to call")
end)

t.test("somebody all-in on the ante does not bring it in", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } }, { 500, rules.ANTE, 500 })
  t.eq(rules.waitingOn(state)[1], 1, "the next lowest who can bet")
end)

-- ------------------------------------------------------------------ who acts

t.test("the best board acts first on later streets", function()
  local state = deal({ { nil, nil, "9S", "KD" }, { nil, nil, "3S", "4D" }, { nil, nil, "AD", "2C" } })
  passive(state, 4)
  t.eq(rules.waitingOn(state)[1], 3, "ace high beats king high")

  state = deal({ { nil, nil, "9S", "9D" }, { nil, nil, "3S", "4D" }, { nil, nil, "AD", "KC" } })
  passive(state, 4)
  t.eq(rules.waitingOn(state)[1], 1, "a pair beats ace king")

  state = deal({ { nil, nil, "9S", "9D", "2C" }, { nil, nil, "3S", "3D", "3C" }, { nil, nil, "AD", "KC", "QD" } })
  passive(state, 5)
  t.eq(rules.waitingOn(state)[1], 2, "trips beat a pair")

  state = deal({ { nil, nil, "9S", "9D", "AC" }, { nil, nil, "9H", "9C", "KC" }, { nil, nil, "2D", "3H", "4S" } })
  passive(state, 5)
  t.eq(rules.waitingOn(state)[1], 1, "the kicker on a board")
end)

t.test("flushes and straights mean nothing on a board", function()
  local state = deal({
    { nil, nil, "2S", "4S", "6S", "8S" },
    { nil, nil, "5C", "6C", "7D", "8H" },
    { nil, nil, "3D", "3H", "9C", "JD" },
  })
  passive(state, 6)
  t.eq(rules.waitingOn(state)[1], 3, "a pair beats four to a flush or a straight")
end)

t.test("a tied board goes to the first left of the button", function()
  local state = deal({ { nil, nil, "KS", "2D" }, { nil, nil, "KH", "2H" }, { nil, nil, "3C", "4C" } })
  passive(state, 4)
  t.eq(rules.waitingOn(state)[1], 1, "position 1 is left of the button")
end)

t.test("an all-in best board passes the action left", function()
  local state = deal({ { nil, nil, "AS", "AD" }, { nil, nil, "4S", "5D" }, { nil, nil, "KC", "9H" } }, { rules.ANTE + rules.BRING_IN + 0, 500, 500 })
  passive(state, 4)
  t.truthy(player(state, 1).allin, "the aces are all-in")
  t.eq(rules.waitingOn(state)[1], 2, "next left who can bet")
end)

t.test("nobody left to bet against plays the cards out", function()
  local state = deal({ {}, {} }, { rules.ANTE, rules.ANTE })
  t.truthy(rules.done(state), "both all-in on the ante, the hand is over as it is dealt")
  t.eq(#player(state, 1).up + #player(state, 1).down, 7, "seven cards")
  local total = rules.nets(state)[1] + rules.nets(state)[2]
  t.eq(total, 0, "still sums to zero")
end)

-- ------------------------------------------------------------------ limits

t.test("small bet on third and fourth, big bet after", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } })
  for street = 3, 7 do
    passive(state, street)
    t.eq(state.street, street, "reached the street")
    t.eq(state.size, street <= 4 and rules.SMALL or rules.BIG, "the size on " .. street)
    if street >= 4 then
      local seat = rules.waitingOn(state)[1]
      t.eq(hasAction(state, seat, "raise").cost, state.size, "the bet")
      t.eq(hasAction(state, seat, "raise").label, "BET", "the word")
    end
  end
end)

t.test("a bet and three raises, then no more", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } })
  go(state, "raise")   -- the completion
  go(state, "raise")
  go(state, "raise")
  go(state, "raise")
  t.eq(state.current, 4 * rules.SMALL, "capped")
  local seat = rules.waitingOn(state)[1]
  t.eq(hasAction(state, seat, "raise"), nil, "no fifth bet")
  t.eq(#rules.act(state, seat, "raise"), 0, "and pressing it does nothing")
end)

t.test("a short all-in raise counts and reopens the betting", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } }, { 500, 500, rules.ANTE + 25 })
  go(state, "bringin")
  go(state, "raise")      -- seat 3 completes to 10
  go(state, "raise")      -- seat 1 raises to 20
  go(state, "call")       -- seat 2 calls
  t.eq(rules.waitingOn(state)[1], 3, "back to the short stack")
  t.eq(hasAction(state, 3, "raise").label, "ALL-IN", "they have 15 left and a full raise is 20")
  go(state, "raise")
  t.truthy(player(state, 3).allin, "all-in")
  t.eq(player(state, 3).bet, 25, "short of a full raise")
  t.eq(state.bets, 3, "it counts")
  t.eq(rules.waitingOn(state)[1], 1, "and the others must answer it")
  t.eq(hasAction(state, 1, "call").cost, 5, "the difference")
end)

-- ------------------------------------------------------------------ the shared card

local function eightStayed()
  local script = {}
  for position = 1, 8 do script[position] = {} end
  return deal(script)
end

t.test("eight to the river share one card", function()
  local state = eightStayed()
  passive(state, 6)
  t.eq(#state.deck, 4, "four left for eight players")
  passive(state, 7)
  t.truthy(state.community ~= nil, "one card goes in the middle")
  t.eq(#state.deck, 3, "only one is used")
  for _, each in ipairs(state.players) do t.eq(#each.down, 2, "no third down-card") end
  t.eq(rules.viewFor(state, nil).community, state.community, "everyone can see it")
  passive(state, 8)
  t.truthy(rules.done(state), "a hand plays out")
  local sum = 0
  for _, each in ipairs(state.players) do
    local cards = { each.down[1], each.down[2], each.up[1], each.up[2], each.up[3], each.up[4], state.community }
    t.eq(each.score, poker.evaluate(cards), "the shared card plays for everyone")
    sum = sum + each.net
  end
  t.eq(sum, 0, "nets add up")
end)

t.test("as many cards as players left means no shared card", function()
  local state = eightStayed()
  passive(state, 6)
  t.eq(#state.deck, 4, "four left")
  -- Bet, and four players fold to it
  go(state, "raise")
  for _ = 1, 4 do go(state, "fold") end
  while state.street == 6 do go(state, "call") end
  t.eq(state.street, 7, "the river")
  t.eq(state.community, nil, "a card each")
  t.eq(#state.deck, 0, "the deck ran out exactly")
  for _, each in ipairs(state.players) do
    if not each.folded then t.eq(#each.down, 3, "their own last card") end
  end
end)

t.test("five left with four cards share one", function()
  local state = eightStayed()
  passive(state, 6)
  go(state, "raise")
  for _ = 1, 3 do go(state, "fold") end
  while state.street == 6 do go(state, "call") end
  t.truthy(state.community ~= nil, "not enough for a card each")
end)

t.test("two left of four take their own river", function()
  local state = deal({ {}, {}, {}, {} })
  passive(state, 7)
  t.eq(state.community, nil, "plenty of cards")
end)

-- ------------------------------------------------------------------ the end

t.test("a showdown pays the best seven-card hand", function()
  local state = deal({
    { "AS", "AD", "2C", "7D", "9C", "JS", "KH" },
    { "KS", "KD", "3C", "8D", "10C", "QS", "2H" },
  })
  passive(state, 8)
  t.truthy(rules.done(state), "over")
  t.truthy(rules.nets(state)[1] > 0, "aces beat kings")
  t.eq(rules.nets(state)[1] + rules.nets(state)[2], 0, "zero sum")
  t.eq(rules.result(state, 1).kind, "win", "the winner's line")
  t.eq(rules.result(state, 2).kind, "lose", "the loser's line")
  t.truthy(rules.result(state, 1).detail:find("Pair of Aces"), "it names the hand")
  t.truthy(rules.result(state, nil).title:find("P1 WINS"), "the table's line")
end)

t.test("a tie splits and the odd chip goes to the owner, wherever the button is", function()
  for _, order in ipairs({ { 1, 2 }, { 2, 1 } }) do
    local spade, heart = order[1], order[2]
    local script = { {}, {}, { "4S", "5D", "7C", "9S", "JH", "KH", "2C" } }
    script[spade] = { "AS", "KD", "QC", "JD", "10C", "2S", "3H" }
    script[heart] = { "AH", "KC", "QD", "JS", "10D", "2H", "3D" }
    local state = deal(script)
    passive(state, 4)
    t.eq(rules.waitingOn(state)[1], 1, "a tied board, left of the button")
    go(state, "raise")
    go(state, "call")
    go(state, "fold")
    passive(state, 8)
    t.truthy(rules.done(state), "over")
    local nets = rules.nets(state)
    t.eq(state.kept, 1, "one odd chip")
    t.eq(nets[1] + nets[2] + nets[3], -1, "the owner keeps it")
    t.eq(nets[spade], nets[heart], "the two winners get the same")
  end
end)

t.test("a short bring-in with nobody left to bet against prices only what it really bet", function()
  local state = deal({ { nil, nil, "3S" }, { nil, nil, "KD" } }, { rules.ANTE + 3, 100 })
  t.eq(hasAction(state, 1, "bringin").cost, 3, "all it has")
  go(state, "bringin")
  t.truthy(player(state, 1).allin, "all-in")
  t.eq(hasAction(state, 2, "call").cost, 3, "the last player matches 3, not the full bring-in")
  go(state, "call")
  t.truthy(rules.done(state), "the cards play out and it ends, with nobody asked to act again")
  local nets = rules.nets(state)
  t.eq(nets[1] + nets[2], 0, "zero sum")
  t.eq(math.abs(nets[1]), 5, "the ante and the bring-in")
end)

t.test("an all-in under half a bet is no raise: it uses up no bet and does not reopen the betting", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } }, { 500, 500, rules.ANTE + 24 })
  go(state, "bringin")
  go(state, "raise")      -- seat 3 completes to 10
  go(state, "raise")      -- seat 1 raises to 20
  go(state, "call")       -- seat 2 calls
  go(state, "raise")      -- seat 3 is all-in for 24, 4 over, and half a bet is 5
  t.eq(state.current, 24, "the new price")
  t.eq(state.bets, 2, "it does not count")
  t.eq(hasAction(state, 1, "call").cost, 4, "seat 1 owes the difference")
  t.eq(hasAction(state, 1, "raise"), nil, "and may not raise")
  go(state, "call")
  t.eq(hasAction(state, 2, "raise"), nil, "nor may seat 2")
end)

t.test("side pots stop at what a short stack put in", function()
  local state = deal({
    { "AS", "AD", "AC", "7D", "9C", "JS", "KH" },
    { "KS", "KD", "3C", "8D", "10C", "QS", "2H" },
    { "4S", "4D", "5C", "6D", "9D", "JD", "2C" },
  }, { 30, 1000, 1000 })
  local guard = 0
  while not rules.done(state) do
    guard = guard + 1
    t.truthy(guard < 100, "it ended")
    local seat = rules.waitingOn(state)[1]
    if hasAction(state, seat, "bringin") then rules.act(state, seat, "bringin")
    elseif hasAction(state, seat, "raise") and state.bets < 2 then rules.act(state, seat, "raise")
    elseif hasAction(state, seat, "call") then rules.act(state, seat, "call")
    else rules.act(state, seat, "check") end
  end
  local nets = rules.nets(state)
  t.eq(nets[1] + nets[2] + nets[3], 0, "zero sum")
  t.eq(nets[1], 2 * 30, "the short stack wins from each what it put in")
  t.eq(nets[2] > 0, true, "the kings win the side pot")
  t.eq(player(state, 1).stack, 90, "the stack afterwards")
end)

t.test("everyone folding ends it with nothing shown", function()
  local state = deal({ { "AS", "AD" }, { "KS", "KD", "2C" }, { "QS", "QD", "9H" } })
  go(state, "bringin")
  go(state, "fold")
  t.eq(rules.done(state), false, "two left")
  go(state, "raise")
  go(state, "fold")
  t.truthy(rules.done(state), "over")
  local view = rules.viewFor(state, nil)
  t.truthy(view.uncontested, "uncontested")
  for _, shown in ipairs(view.players) do
    t.eq(shown.down, nil, "nobody turns over")
    t.eq(shown.handName, nil, "and no hand is named")
  end
  t.eq(rules.result(state, nil).detail, "Everyone else folded", "the table's line")
end)

t.test("only those still in are shown at a showdown", function()
  local state = deal({ { "AS", "AD" }, { "KS", "KD", "2C" }, { "QS", "QD", "9H" } })
  go(state, "bringin")
  go(state, "fold")
  go(state, "call")
  passive(state, 8)
  t.truthy(rules.done(state), "over")
  for _, viewer in ipairs({ 1, 2, 3, false }) do
    local view = rules.viewFor(state, viewer or nil)
    for _, shown in ipairs(view.players) do
      if shown.folded then
        t.eq(shown.down, nil, "folded cards stay down")
        t.eq(#shown.up, 0, "and the up-cards go in the muck")
      else
        t.eq(#shown.down, 2 + (state.community and 0 or 1), "the live hands turn over")
        t.truthy(shown.handName, "named")
      end
    end
  end
end)

t.test("a folded player keeps their own cards on their own screen only", function()
  local state = deal({ { "AS", "AD" }, { "KS", "KD", "2C" }, { "QS", "QD", "9H" } })
  go(state, "bringin")
  go(state, "fold")
  local view = rules.viewFor(state, 3)
  t.truthy(view.me.folded, "folded")
  t.eq(view.me.down[1], deck.parse("QS"), "their own card")
  t.eq(#view.me.up, 1, "their own up-card")
  t.eq(#rules.viewFor(state, 1).players[3].up, 0, "not for anyone else")
end)

t.test("own hand name grows with the street", function()
  local state = deal({ { "AS", "AD", "2C", "7D", "9C", "JS", "KH" }, { "KS", "KD", "3C", "8D", "10C", "QS", "2H" } })
  t.eq(rules.viewFor(state, 1).me.handName, "Pair of Aces", "three cards")
  t.eq(rules.viewFor(state, 2).players[1].board, "Two High", "the board says only what is up")
  passive(state, 5)
  t.eq(rules.viewFor(state, 1).me.handName, "Pair of Aces", "five cards")
end)

-- ------------------------------------------------------------------ illegal input

t.test("illegal input does nothing", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } })
  local before = kit.plain(state)
  local tries = {
    { 1, "bringin" }, { 3, "raise" }, { 2, "fold" }, { 2, "check" }, { 2, "call" }, { nil, "bringin" }, { 9, "bringin" }, { "2", "bringin" },
    { 2, nil }, { 2, {} }, { 2, 7 }, { {}, "fold" }, { 2, "draw125" },
  }
  for index, try in ipairs(tries) do
    local events = rules.act(state, try[1], try[2], 999999)
    t.eq(#events, 0, "try " .. index)
    t.truthy(kit.same(before, state), "try " .. index .. " left the state alone")
  end
  while not rules.done(state) do rules.act(state, rules.waitingOn(state)[1], rules.auto(state, rules.waitingOn(state)[1])) end
  before = kit.plain(state)
  t.eq(#rules.act(state, 1, "check"), 0, "nothing after the end")
  t.truthy(kit.same(before, state), "the end stays the end")
end)

t.test("auto is a bring-in, a check or a fold", function()
  local state = deal({ { nil, nil, "9S" }, { nil, nil, "3S" }, { nil, nil, "KD" } })
  t.eq(rules.auto(state, 2), "bringin", "the bring-in is forced")
  go(state, "bringin")
  t.eq(rules.auto(state, 3), "fold", "owing")
  go(state, "call")
  go(state, "call")
  t.eq(rules.auto(state, rules.waitingOn(state)[1]), "check", "free")
end)

-- ------------------------------------------------------------------ random hands

-- kit.fuzz copies the whole state at every step, so it gets a few hundred hands, and the thousands below run bare
t.test("stud keeps the contract over random hands", function()
  kit.fuzz(watched(), { rounds = 300, seats = { 2, 3, 4, 5, 6, 7, 8 }, stack = 1000, absent = 10, pick = mostlyStay, seed = 7 })
end)

t.test("stud keeps the contract with short stacks", function()
  kit.fuzz(watched(), { rounds = 100, seats = { 2, 5, 8 }, stack = 25, absent = 5, pick = mostlyStay, seed = 21 })
  kit.fuzz(watched(), { rounds = 50, seats = { 2, 8 }, stack = rules.ANTE + 1, seed = 22 })
  kit.fuzz(watched(), { rounds = 50, seats = { 3, 8 }, stack = 1, seed = 23 })
end)

--- A whole hand with no copying. After each step check runs, if there is one.
local function quickHand(entries, button, rng, check)
  local state = rules.new(entries, button, rng, {})
  local steps = 0
  while not rules.done(state) do
    steps = steps + 1
    if steps > 500 then error("the hand never ended", 0) end
    if check then check(state) end
    local seat = rules.waitingOn(state)[1]
    local id
    if rng:below(20) == 0 then
      id = rules.auto(state, seat)
    else
      id = mostlyStay(state, seat, rules.actions(state, seat), rng) or rules.actions(state, seat)[1].id
    end
    if #rules.act(state, seat, id) == 0 then error("a move did nothing: " .. tostring(id), 0) end
  end
  return state
end

t.test("mixed stacks add up over 2500 random hands, and no view leaks", function()
  local rng = t.fastRng(99)
  local reached, shared = 0, 0
  for round = 1, 2500 do
    local count = rng:below(7) + 2
    local entries, seats, seatNumbers = {}, {}, {}
    for index = 1, 8 do seatNumbers[index] = index end
    deck.shuffle(seatNumbers, rng)
    for index = 1, count do seats[index] = seatNumbers[index] end
    table.sort(seats)
    for index = 1, count do
      local sizes = { 3, 12, 40, 95, 300, 1000, 1000, 1000 }
      entries[index] = { seat = seats[index], name = "P" .. seats[index], stack = sizes[rng:below(#sizes) + 1] }
    end
    local state = quickHand(entries, rng:below(count) + 1, rng, round % 10 == 0 and function(now) checkSecrets(now, seats) end or nil)
    kit.checkEnd(plugin, state, entries)
    checkSecrets(state, seats)
    if not state.uncontested then reached = reached + 1 end
    if state.community then shared = shared + 1 end
    local sum = 0
    for _, each in ipairs(state.players) do
      t.eq(each.stack, each.start + each.net, "the stack at the end")
      t.truthy(each.total <= each.start, "never in for more than they had")
      sum = sum + each.net
    end
    t.eq(sum, -(state.kept or 0), "nets, less the owner's odd chips")
    if round % 50 == 0 then t.breathe() end
  end
  print("     stud: " .. reached .. " of 2500 hands reached a showdown, " .. shared .. " used the shared card")
  t.truthy(reached > 500, "plenty reached a showdown: " .. reached)
  t.truthy(shared > 0, "the shared card came up: " .. shared)
end)

t.test("every state and view goes through textutils", function()
  local serialize = rawget(_G, "textutils")
  if not serialize then return end -- only on a computer
  local rng = t.fastRng(5)
  local state = rules.new(kit.entries(plugin, 8, { stack = 1000 }), 3, rng, {})
  local steps = 0
  while true do
    steps = steps + 1
    t.truthy(steps < 500, "it ended")
    local back = serialize.unserialize(serialize.serialize(state))
    t.truthy(kit.same(back, state), "state came back the same")
    t.truthy(kit.same(serialize.unserialize(serialize.serialize(rules.viewFor(state, nil))), rules.viewFor(state, nil)), "the public view")
    t.truthy(kit.same(serialize.unserialize(serialize.serialize(rules.viewFor(state, 2))), rules.viewFor(state, 2)), "a seat's view")
    if rules.done(state) then break end
    state = back
    local seat = rules.waitingOn(state)[1]
    local list = rules.actions(state, seat)
    rules.act(state, seat, list[#list].id)
  end
end)

-- ------------------------------------------------------------------ pictures

t.test("the wall and a seat draw for every table size at every step", function()
  local wall = canvas.new(nil, 121, 81)
  local seatCanvas = canvas.new(nil, 78, 52)
  local rng = t.fastRng(11)
  for count = 2, 8 do
    for _ = 1, 8 do
      local state, entries = kit.playRound(plugin, { seats = count, rng = rng, stack = 300, pick = mostlyStay,
        check = function(now)
          plugin.tableView.draw(wall, rules.viewFor(now, nil), { ev = { type = "street", street = now.street }, t = 0.5 })
          plugin.tableView.draw(wall, rules.viewFor(now, nil))
          plugin.seatView.draw(seatCanvas, rules.viewFor(now, 1))
          plugin.seatView.draw(seatCanvas, rules.viewFor(now, nil))
        end })
      plugin.tableView.draw(wall, rules.viewFor(state, nil))
      plugin.seatView.draw(seatCanvas, rules.viewFor(state, entries[1].seat))
      plugin.seatView.draw(seatCanvas, {})
      plugin.tableView.draw(wall, {})
    end
    t.breathe()
  end
end)

t.test("the plugin says what the README asks", function()
  t.eq(plugin.id, "stud", "id")
  t.eq(plugin.kind, "players", "kind")
  t.eq(plugin.minSeats, 2, "least")
  t.eq(plugin.maxSeats, 8, "most")
  t.truthy(#plugin.help() > 3, "help")
  local seconds = plugin.event({ type = "deal" })
  t.truthy(seconds > 0, "an event's length")
end)
