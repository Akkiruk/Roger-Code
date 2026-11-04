-- uno_test.lua
-- UNO on Game Night: the deck, dealing and the first discard, every card's effect (Reverse with two players too), no stacking of
-- draws, naming a wild's colour, drawing then playing, saying UNO and being caught (and when a catch is too late), scoring to the
-- goal, the clock, the computer players always playing legally, whole computer games ending, the group contract, what each seat may
-- see, both pictures drawing at every stage, and the free table never touching money.
--   node tools/casinotest/unit.mjs uno        (in craftos-agent)

local kit = require("group_kit")
local testing = require("testing")
local eq, test, truthy = testing.eq, testing.test, testing.truthy

local plugin = kit.plugin("GameNight", "uno")
local rules = plugin.rules

local function gameModule(name)
  local saved = package.path
  local root = "."
  for part in package.path:gmatch("[^;]+") do
    root = part:match("^(.*)[/\\]Tests[/\\]%?%.lua$") or root
  end
  package.path = root .. "/Games/GameNight/?.lua;" .. saved
  local mod = require("games.uno." .. name)
  package.path = saved
  return mod
end
local cards = gameModule("cards")
local bot = gameModule("bot")

local function humans(n)
  local list = {}
  for i = 1, n do list[i] = { seat = i, name = "P" .. i, stack = 0 } end
  return list
end

local function fresh(n, seed)
  return (rules.new(humans(n or 0), 1, testing.fastRng(seed or 1), {}))
end

local function count(list, value)
  local n = 0
  for _, item in ipairs(list) do
    if item == value then n = n + 1 end
  end
  return n
end

local function has(list, value)
  return count(list, value) > 0
end

local function totalCards(state)
  local n = #state.deck + #state.pile
  for _, player in ipairs(state.players) do n = n + #player.hand end
  return n
end

--- A table of n people (all people, no computer) in the middle of a hand: player 1 to play on a red 5, hands as given, and a deck
-- whose next cards are drawFirst (the last in the list is drawn first).
local function table_(n, hands, opts)
  opts = opts or {}
  local state = rules.new(humans(math.max(n, 4)), 1, testing.fastRng(opts.seed or 3), {})
  rules.act(state, state.chooserSeat, "goal", opts.goal or 500, testing.fastRng(4))
  if n < #state.players then
    local keep = {}
    for i = 1, n do keep[i] = state.players[i] end
    state.players = keep
  end
  -- Seats in the order of the players, so seat p is player p
  for p, player in ipairs(state.players) do
    player.seat, player.name, player.bot, player.idle, player.carry = p, "P" .. p, false, 0, false
    player.hand = cards.sort(hands and hands[p] and { unpack(hands[p]) } or { "g1", "g2", "g3", "y4", "y5", "y6", "b7" })
    player.ui = { page = 1, pick = false, armed = false }
    player.said = false
  end
  state.chooserSeat = 1
  state.deck = opts.deck or { "g9", "y8", "b2", "g7", "y3", "b4", "g6", "y2", "b9", "g4" }
  state.pile = { opts.top or "r5" }
  state.color = opts.color or cards.color(state.pile[1])
  state.turn, state.dir, state.phase, state.window, state.drawn = 1, 1, "play", false, false
  state.handTurns, state.recent = 1, {}
  return state
end

local function act(state, p, id, value, seed)
  return rules.act(state, p, id, value, testing.fastRng(seed or 7))
end

local function evOf(events, kind)
  for _, ev in ipairs(events or {}) do
    if ev.type == kind then return ev end
  end
  return nil
end

-- ------------------------------------------------------------------ the deck

test("uno: the deck is 108 cards: one 0, two of 1-9 and of each action per colour, four wilds and four draw fours", function()
  local deck = cards.deck()
  eq(#deck, 108, "cards")
  for _, c in ipairs(cards.COLORS) do
    eq(count(deck, c .. "0"), 1, c .. " zero")
    for n = 1, 9 do eq(count(deck, c .. n), 2, c .. n) end
    for _, k in ipairs({ "S", "R", "D" }) do eq(count(deck, c .. k), 2, c .. k) end
  end
  eq(count(deck, "wW"), 4, "wilds")
  eq(count(deck, "wF"), 4, "wild draw fours")
  local points = 0
  for _, card in ipairs(deck) do points = points + cards.points(card) end
  -- 4 x (45 x 2) numbers, 24 actions at 20, 8 wilds at 50
  eq(points, 4 * 90 + 24 * 20 + 8 * 50, "points in a deck")
  eq(cards.points("b7"), 7, "a number is its face")
  eq(cards.points("gS"), 20, "an action is 20")
  eq(cards.points("wF"), 50, "a wild is 50")
end)

test("uno: what may be played on what", function()
  truthy(cards.playable("r9", "r5", "r"), "same colour")
  truthy(cards.playable("b5", "r5", "r"), "same number")
  truthy(cards.playable("bS", "rS", "r"), "same symbol")
  truthy(not cards.playable("b6", "r5", "r"), "nothing in common")
  truthy(cards.playable("wW", "r5", "r"), "a wild anytime")
  truthy(cards.playable("wF", "r5", "r"), "a wild draw four anytime")
  truthy(cards.playable("g2", "wW", "g"), "the colour named for a wild")
  truthy(not cards.playable("r2", "wW", "g"), "not another colour on a wild")
  truthy(not cards.playable("rD", "wF", "g"), "a draw four's symbol is no match for a draw two")
end)

-- ------------------------------------------------------------------ dealing

test("uno: the computer fills the table to four, up to eight people play, and the first seat picks the length", function()
  for n = 0, 8 do
    local state = fresh(n, 5 + n)
    eq(#state.players, math.max(n, 4), n .. " people")
    local people = 0
    for _, player in ipairs(state.players) do
      if not player.bot then people = people + 1 end
    end
    eq(people, n, "people at the table")
    if n > 0 then
      eq(state.phase, "goal", "a person picks how long")
      local waiting = rules.waitingOn(state)
      eq(#waiting, 1, "one chooser")
      eq(waiting[1], 1, "the first seat chooses")
      local actions = rules.actions(state, 1)
      eq(#actions, 3, "three lengths")
      if n > 1 then eq(#rules.actions(state, 2), 0, "only the chooser") end
    else
      eq(state.phase == "play" or state.phase == "color", true, "with nobody the hand is dealt at once")
    end
  end
  local nine = rules.new(humans(9), 1, testing.fastRng(1), {})
  eq(#nine.players, 8, "never more than eight")
end)

test("uno: seven cards each, a first discard that is never a Wild Draw Four, every card somewhere", function()
  for seed = 1, 120 do
    local state = fresh(0, seed)
    eq(totalCards(state), 108, "all 108 cards")
    truthy(state.pile[1] ~= "wF", "no Wild Draw Four to start")
    eq(#state.pile, 1, "one discard")
    local extra = cards.kind(state.pile[1]) == "D" and 2 or 0
    local dealt = 0
    for _, player in ipairs(state.players) do dealt = dealt + #player.hand end
    eq(dealt, 7 * #state.players + extra, "seven each")
    if seed % 40 == 0 then testing.breathe() end
  end
end)

test("uno: the first discard does what the rules say: skip, reverse, draw two, wild", function()
  local seen = {}
  for seed = 1, 600 do
    local state = fresh(0, seed)
    local first = state.pile[1]
    local kind = cards.kind(first)
    local dealer = state.dealer
    local leader = (dealer % #state.players) + 1
    if kind == "S" then
      eq(state.turn, (leader % #state.players) + 1, "a skip skips the first player")
      eq(state.dir, 1, "play goes on as usual")
    elseif kind == "R" then
      eq(state.dir, -1, "a reverse turns play round")
      eq(state.turn, dealer, "and the dealer goes first")
    elseif kind == "D" then
      eq(#state.players[leader].hand, 9, "the first player draws two")
      eq(state.turn, (leader % #state.players) + 1, "and misses their turn")
    elseif kind == "W" then
      eq(state.phase, "color", "the first player names the colour")
      eq(state.turn, leader, "the first player")
      eq(state.color, false, "no colour yet")
    else
      eq(state.turn, leader, "the player after the dealer goes first")
      eq(state.color, cards.color(first), "its colour is in play")
    end
    seen[kind] = true
    if seen.S and seen.R and seen.D and seen.W then break end
    if seed % 60 == 0 then testing.breathe() end
  end
  truthy(seen.S and seen.R and seen.D and seen.W, "every kind of first card came up")
end)

test("uno: picking the length, and a chooser who never picks gets 500", function()
  local state = fresh(2, 9)
  local ev = act(state, 2, "goal", 200)
  eq(ev, nil, "only the first seat picks")
  eq(act(state, 1, "goal", 333), nil, "only a length on offer")
  ev = act(state, 1, "goal", 200)
  truthy(evOf(ev, "goal") and evOf(ev, "deal"), "picked and dealt")
  eq(state.goal, 200, "to 200")
  local other = fresh(1, 9)
  ev = act(other, 1, rules.auto(other, 1))
  truthy(ev and #ev > 0, "the clock picks")
  eq(other.goal, 500, "500 when nobody picks")
  eq(rules.turnMs(fresh(1, 2), 1), rules.GOAL_MS, "a short clock to pick")
end)

-- ------------------------------------------------------------------ the cards

test("uno: a number passes the turn on, and a card that does not match does nothing", function()
  local state = table_(4, { { "r7", "b6", "g1" } })
  local before = kit.plain(state)
  eq(act(state, 1, "play", "b6"), nil, "a blue 6 on a red 5")
  truthy(kit.same(before, state), "nothing changed")
  eq(act(state, 1, "play", "y9"), nil, "a card not held")
  eq(act(state, 2, "play", "g1"), nil, "not their turn")
  local ev = act(state, 1, "play", "r7")
  truthy(evOf(ev, "play"), "played")
  eq(state.pile[#state.pile], "r7", "on top")
  eq(state.color, "r", "red")
  eq(state.turn, 2, "next player")
  eq(#state.players[1].hand, 2, "one fewer")
  -- The same number in another colour changes the colour
  act(state, 2, "draw")
  state.turn, state.phase = 3, "play"
  state.players[3].hand = { "b7", "g2" }
  act(state, 3, "play", "b7")
  eq(state.color, "b", "a blue 7 on a red 7 makes it blue")
end)

test("uno: skip, reverse, draw two and wild draw four, and draws never stack", function()
  local state = table_(4, { { "rS", "g1", "g2" } })
  local ev = act(state, 1, "play", "rS")
  truthy(evOf(ev, "skip"), "a skip")
  eq(evOf(ev, "skip").victim, 2, "player 2 is the one skipped")
  eq(state.turn, 3, "player 2 is skipped")

  state = table_(4, { { "rR", "g1", "g2" } })
  act(state, 1, "play", "rR")
  eq(state.dir, -1, "play turns round")
  eq(state.turn, 4, "back to the player before")
  state.players[4].hand = { "r3", "g5" }
  act(state, 4, "play", "r3")
  eq(state.turn, 3, "and goes on backwards")

  state = table_(4, { { "rD", "g1", "g2" } }, { deck = { "b1", "b2", "b3", "b4", "b5" } })
  ev = act(state, 1, "play", "rD")
  truthy(evOf(ev, "draw2"), "a draw two")
  eq(#state.players[2].hand, 9, "player 2 draws two")
  truthy(has(state.players[2].hand, "b5") and has(state.players[2].hand, "b4"), "from the top of the deck")
  eq(state.turn, 3, "and misses their turn: no chance to stack one back")

  state = table_(4, { { "wF", "g1", "g2" } })
  state.players[2].hand = { "yD", "wF", "b1" }
  ev = act(state, 1, "play", "wF")
  truthy(evOf(ev, "pick"), "a wild asks for a colour first")
  eq(state.turn, 1, "still their turn")
  ev = act(state, 1, "color", "g")
  truthy(evOf(ev, "draw4"), "a wild draw four")
  eq(state.color, "g", "green named")
  eq(#state.players[2].hand, 7, "the next player draws four")
  eq(state.turn, 3, "and is skipped, holding a draw four of their own")
end)

test("uno: a reverse with two players is a skip", function()
  local state = table_(2, { { "rR", "r1", "g2" }, { "r1", "r2" } })
  local ev = act(state, 1, "play", "rR")
  truthy(evOf(ev, "reverse"), "a reverse")
  eq(evOf(ev, "reverse").victim, 2, "the other player misses out")
  eq(state.turn, 1, "the same player goes again")
  act(state, 1, "play", "r1")
  eq(state.turn, 2, "then the other")
  -- A skip with two does the same
  state = table_(2, { { "rS", "g1" }, { "r1", "r2" } })
  act(state, 1, "play", "rS")
  eq(state.turn, 1, "a skip with two: again")
end)

test("uno: a wild names any colour, BACK changes your mind, and the colour must be one of the four", function()
  local state = table_(4, { { "wW", "b2", "g4" } })
  act(state, 1, "play", "wW")
  eq(state.players[1].ui.pick, "wW", "asking for a colour")
  local actions = rules.actions(state, 1)
  eq(#actions, 5, "four colours and BACK")
  eq(act(state, 1, "draw"), nil, "no drawing while picking")
  eq(act(state, 1, "color", "x"), nil, "not a colour")
  truthy(act(state, 1, "back"), "back")
  eq(state.players[1].ui.pick, false, "no longer picking")
  eq(#state.players[1].hand, 3, "the wild is still held")
  act(state, 1, "play", "wW")
  local ev = act(state, 1, "color", "b")
  truthy(evOf(ev, "wild"), "played")
  eq(state.color, "b", "blue")
  eq(state.turn, 2, "next")
  state.players[2].hand = { "b9", "r1" }
  local playable = rules.playable(state, 2)
  eq(#playable, 1, "only blue goes on it")
  eq(playable[1], "b9", "the blue nine")
end)

test("uno: draw one, then play it if it can go, keep it, or pass at once when it cannot", function()
  local state = table_(4, { { "g1", "b2" } }, { deck = { "y3", "r9" } })
  local ev = act(state, 1, "draw")
  truthy(evOf(ev, "draw"), "drew")
  eq(state.phase, "drawn", "a playable card waits")
  eq(state.drawn, "r9", "the red 9")
  eq(state.turn, 1, "still their turn")
  eq(act(state, 1, "play", "g1"), nil, "only the drawn card can be played now")
  eq(act(state, 1, "draw"), nil, "no second draw")
  act(state, 1, "play", "r9")
  eq(state.pile[#state.pile], "r9", "played the drawn card")
  eq(state.turn, 2, "and the turn passed")

  state = table_(4, { { "g1", "b2" } }, { deck = { "y3", "r9" } })
  act(state, 1, "draw")
  ev = act(state, 1, "keep")
  truthy(evOf(ev, "pass"), "kept")
  eq(#state.players[1].hand, 3, "kept the card")
  eq(state.turn, 2, "the turn passed")

  state = table_(4, { { "g1", "b2" } }, { deck = { "r9", "y3" } })
  act(state, 1, "draw")
  eq(state.phase, "play", "an unplayable card passes the turn at once")
  eq(state.turn, 2, "next player")
  -- Drawing is allowed even with a card that could be played
  state = table_(4, { { "r1", "b2" } }, { deck = { "y3", "g8" } })
  truthy(act(state, 1, "draw"), "may draw instead of playing")
end)

test("uno: an empty deck is the discards shuffled, keeping the top card", function()
  local state = table_(4, { { "g1", "b2" } }, { deck = {} })
  state.pile = { "y1", "y2", "b3", "r5" }
  local ev = act(state, 1, "draw")
  truthy(evOf(ev, "shuffle"), "shuffled")
  eq(#state.pile, 1, "only the top card stays")
  eq(state.pile[1], "r5", "the top card")
  eq(#state.players[1].hand + #state.deck, 5, "the three discards went in the deck and one came out")
end)

-- ------------------------------------------------------------------ UNO

test("uno: saying UNO first, then playing, leaves nobody able to catch", function()
  local state = table_(4, { { "r7", "g2" } })
  local actions = rules.actions(state, 1)
  local uno
  for _, a in ipairs(actions) do
    if a.id == "uno" then uno = a end
  end
  truthy(uno and not uno.disabled, "UNO! is offered with two cards")
  local ev = act(state, 1, "uno")
  truthy(evOf(ev, "uno"), "said")
  eq(act(state, 1, "uno"), nil, "once is enough")
  act(state, 1, "play", "r7")
  truthy(state.players[1].said, "said UNO")
  eq(state.window, false, "nothing to catch")
  eq(act(state, 2, "catch"), nil, "a catch does nothing")
  local view = rules.viewFor(state, nil)
  truthy(view.players[1].said, "the wall shows UNO")
  -- Three cards: no UNO button
  state = table_(4, { { "r7", "g2", "g3" } })
  for _, a in ipairs(rules.actions(state, 1)) do truthy(a.id ~= "uno", "no UNO with three cards") end
  eq(act(state, 1, "uno"), nil, "and pressing it anyway does nothing")
end)

test("uno: forgetting UNO can be caught by the next player or anyone else, until the next player moves", function()
  local saved = rules.BOT_NOTICES
  rules.BOT_NOTICES = 0
  local state = table_(4, { { "r7", "g2" } })
  act(state, 1, "play", "r7")
  truthy(state.window, "the window is open")
  eq(state.window.p, 1, "on player 1")
  local waiting = rules.waitingOn(state)
  eq(#waiting, 3, "the next player and the two others can catch")
  eq(rules.turnMs(state, 3), rules.CATCH_MS, "a few seconds to catch")
  eq(rules.turnMs(state, 2), rules.TURN_MS, "the next player has their turn's clock")
  eq(act(state, 1, "catch"), nil, "nobody catches themselves")
  local ev = act(state, 3, "catch")
  truthy(evOf(ev, "catch"), "caught by a player who is not next")
  eq(#state.players[1].hand, 3, "two cards for the one caught")
  eq(state.window, false, "the window closes")
  eq(act(state, 4, "catch"), nil, "nobody can catch twice")
  eq(state.turn, 2, "the turn did not change")

  -- The next player can catch too
  state = table_(4, { { "r7", "g2" } })
  act(state, 1, "play", "r7")
  truthy(act(state, 2, "catch"), "the next player catches")
  eq(#state.players[1].hand, 3, "caught")

  -- Once the next player has moved it is too late
  state = table_(4, { { "r7", "g2" } })
  act(state, 1, "play", "r7")
  state.players[2].hand = { "r1", "b1", "b2" }
  act(state, 2, "play", "r1")
  eq(state.window, false, "the window closed when the next player played")
  eq(act(state, 3, "catch"), nil, "too late")
  eq(#state.players[1].hand, 1, "still one card")

  -- The others' few seconds run out
  state = table_(4, { { "r7", "g2" } })
  act(state, 1, "play", "r7")
  ev = act(state, 3, rules.auto(state, 3))
  truthy(evOf(ev, "late"), "player 3 missed it")
  eq(#rules.waitingOn(state), 2, "only player 4 and the next player now")
  eq(state.players[3].idle, 0, "missing a catch is not being away")
  truthy(rules.present(state, 3), "and does not count as away")
  rules.BOT_NOTICES = saved
end)

test("uno: a computer player who spots a missed UNO catches it first", function()
  local saved = rules.BOT_NOTICES
  rules.BOT_NOTICES = 100
  local state = table_(4, { { "r7", "g2" } })
  state.players[3].bot = true
  act(state, 1, "play", "r7")
  eq(state.window.noticed, 3, "the computer saw it")
  eq(#rules.waitingOn(state), 0, "the computer moves first")
  local ev = rules.act(state, nil, "bot", nil, testing.fastRng(3))
  truthy(evOf(ev, "catch"), "it catches")
  eq(evOf(ev, "catch").p, 3, "player 3 caught")
  eq(#state.players[1].hand, 3, "two cards")
  eq(rules.waitingOn(state)[1], 2, "then the next player plays")
  rules.BOT_NOTICES = saved
end)

test("uno: the computer says UNO most of the time, and sometimes forgets", function()
  local said, forgot = 0, 0
  for seed = 1, 300 do
    local state = table_(4, { { "r7", "g2" } }, { seed = seed })
    state.players[1].bot = true
    rules.act(state, nil, "bot", nil, testing.fastRng(seed))
    if state.players[1].said then said = said + 1 elseif state.window then forgot = forgot + 1 end
    if seed % 100 == 0 then testing.breathe() end
  end
  truthy(said > 200, "said it: " .. said)
  truthy(forgot > 5, "forgot sometimes: " .. forgot)
end)

-- ------------------------------------------------------------------ scoring

test("uno: going out scores the others' cards, and a draw two that goes out still counts", function()
  local state = table_(4, { { "r7" }, { "b5", "wW" }, { "gS", "y9" }, { "wF" } }, { goal = 500 })
  local ev = act(state, 1, "play", "r7")
  truthy(evOf(ev, "handwin"), "the hand is won")
  eq(state.players[1].score, 5 + 50 + 20 + 9 + 50, "points from every other hand")
  eq(state.phase, "scored", "scores between hands")
  eq(#rules.waitingOn(state), 4, "everyone reads the scores")
  for seat = 1, 4 do act(state, seat, "next") end
  eq(state.phase == "play" or state.phase == "color", true, "the next hand once all are ready")
  eq(state.handNo, 2, "hand 2")
  eq(state.players[1].score, 134, "scores carry over")

  state = table_(4, { { "rD" }, { "b5" }, { "g1" }, { "y2" } }, { deck = { "b9", "b8", "b7" } })
  act(state, 1, "play", "rD")
  eq(state.players[1].score, 5 + 7 + 8 + 1 + 2, "the two drawn count")
end)

test("uno: the first to the goal wins the game, and one hand is enough when that is the length", function()
  local state = table_(4, { { "r7" }, { "b5", "wW" } }, { goal = 500 })
  state.players[1].score = 450
  local ev = act(state, 1, "play", "r7")
  truthy(evOf(ev, "win"), "the game is won")
  truthy(rules.done(state), "over")
  eq(state.winner, 1, "player 1")
  eq(rules.result(state, 1).kind, "win", "the winner's result")
  eq(rules.result(state, 2).kind, "lose", "another's")
  truthy(rules.result(state, nil).title:find("WINS"), "the wall's")

  state = table_(4, { { "r7" } }, { goal = 0 })
  act(state, 1, "play", "r7")
  truthy(rules.done(state), "one hand ends it")
  eq(state.winner, 1, "the one who went out")
  for _, net in pairs(rules.nets(state)) do eq(net, 0, "free: nothing moves") end
end)

-- ------------------------------------------------------------------ the clock

test("uno: a run-out clock draws and passes, then the clock is short until a tap", function()
  local state = table_(4, { { "r7", "g2" } }, { deck = { "b3" } })
  eq(rules.turnMs(state, 1), rules.TURN_MS, "a whole turn")
  local ev = act(state, 1, rules.auto(state, 1))
  truthy(evOf(ev, "draw"), "drew")
  eq(#state.players[1].hand, 3, "one card")
  eq(state.turn, 2, "and passed")
  eq(state.players[1].idle, 1, "noted")
  truthy(rules.present(state, 1), "once is not away")
  state.turn = 1
  eq(rules.turnMs(state, 1), rules.IDLE_MS, "short until they tap")
  act(state, 1, "play", "r7")
  eq(state.players[1].idle, 0, "a tap brings the full clock back")
  -- A playable card drawn by the clock is not played for them
  state = table_(4, { { "g7", "g2" } }, { deck = { "r3" } })
  act(state, 1, "timeout")
  eq(state.turn, 2, "passed")
  eq(#state.players[1].hand, 3, "the red 3 was kept")
  -- Picking a colour when the clock runs out
  state = table_(4, { { "wW", "g2", "g3" } }, { deck = { "b1" } })
  act(state, 1, "play", "wW")
  act(state, 1, "timeout")
  eq(state.turn, 2, "passed")
  eq(state.players[1].ui.pick, false, "the colour question went away")
  truthy(has(state.players[1].hand, "wW"), "the wild was not played")
end)

test("uno: a turn that starts for someone already waited on first gets its own full clock", function()
  local state = table_(2, { { "rS", "g1", "g2" }, { "r1", "r2" } })
  act(state, 1, "play", "rS")
  eq(state.turn, 1, "the same player again")
  truthy(state.players[1].carry, "the old clock is carried")
  local ev = act(state, 1, "timeout")
  truthy(evOf(ev, "clock"), "the old clock only starts the new one")
  eq(#state.players[1].hand, 2, "nothing drawn")
  eq(state.players[1].idle, 0, "not away")
  ev = act(state, 1, "timeout")
  truthy(evOf(ev, "draw"), "the turn's own clock does draw")
end)

-- ------------------------------------------------------------------ the computer, and whole games

local function legalBotMove(state, rng)
  local p = state.turn
  local top, color = state.pile[#state.pile], state.color
  local window = state.window
  local before = #state.players[p].hand
  local ev = rules.act(state, nil, "bot", nil, rng)
  truthy(ev and #ev > 0, "the computer always moves")
  if window and window.noticed then return ev end
  local drew = false
  for _, e in ipairs(ev) do
    if e.type == "draw" and e.p == p then drew = true end
    if (e.type == "play" or e.type == "skip" or e.type == "reverse" or e.type == "draw2" or e.type == "wild" or e.type == "draw4")
      and e.p == p then
      if not drew then
        truthy(cards.playable(e.card, top, color), "a legal card: " .. e.card .. " on " .. tostring(top) .. " " .. tostring(color))
      else
        truthy(cards.playable(e.card, top, color), "the drawn card was playable")
      end
      if cards.isWild(e.card) then truthy(cards.isColor(e.color), "a wild names a colour") end
    end
  end
  truthy(before > 0, "had cards")
  return ev
end

test("uno: whole games played by the computer always play legal cards and end with a winner on 500", function()
  local hands = 0
  for seed = 1, 8 do
    local state = fresh(0, seed * 11)
    local rng = testing.fastRng(seed)
    local steps = 0
    while not rules.done(state) do
      steps = steps + 1
      truthy(steps < 20000, "seed " .. seed .. " never ended")
      eq(#rules.waitingOn(state), 0, "nobody is waited on with only the computer")
      if state.phase == "play" or state.phase == "color" then
        legalBotMove(state, rng)
      else
        truthy(rules.act(state, nil, "bot", nil, rng), "the computer deals")
      end
      eq(totalCards(state), 108, "every card is somewhere")
      if steps % 200 == 0 then testing.breathe() end
    end
    truthy(state.winner > 0, "a winner")
    truthy(state.players[state.winner].score >= 500, "seed " .. seed .. ": the winner has 500")
    hands = hands + state.handNo
    testing.breathe()
  end
  truthy(hands / 8 < 20, "games take a sensible number of hands: " .. hands / 8)
end)

test("uno: the computer keeps its wilds and saves draws for a player about to go out", function()
  local state = table_(4, { { "r7", "wW", "r2" } })
  state.players[1].bot = true
  local card = bot.choose(state, 1)
  truthy(card ~= "wW", "a plain red rather than a wild")
  state = table_(4, { { "rD", "r9", "g1" } })
  state.players[2].hand = { "b1", "b2" }
  card = bot.choose(state, 1)
  eq(card, "rD", "a draw two on a player with two cards")
  state = table_(4, { { "wW", "g1" } })
  local wild, color = bot.choose(state, 1)
  eq(wild, "wW", "a wild when nothing else goes")
  eq(color, "g", "naming the colour it holds")
end)

--- Steer a person the way the computer would, mostly, and press at random the rest of the time.
local function sensible(state, seat, actions, rng)
  if rng:below(100) < 15 then return nil end
  local p = rules.playerOfSeat(state, seat)
  local live = {}
  for _, action in ipairs(actions) do
    if not action.disabled then live[action.id .. ":" .. tostring(action.value)] = action end
  end
  local function can(id, value) return live[id .. ":" .. tostring(value)] ~= nil end
  if state.phase == "goal" then
    if rng:below(10) < 7 then return "goal", 0 end
    return "goal", 200
  end
  if can("next", nil) then return "next" end
  if can("catch", nil) and rng:below(2) == 0 then return "catch" end
  if state.turn == p and (state.players[p].ui.pick or state.phase == "color") then
    return "color", cards.bestColor(state.players[p].hand)
  end
  if can("uno", nil) and rng:below(10) < 8 then return "uno" end
  local playable = rules.playable(state, p)
  if #playable > 0 and rng:below(10) < 8 then return "play", playable[rng:below(#playable) + 1] end
  if can("keep", nil) then return "keep" end
  if can("draw", nil) then return "draw" end
  return nil
end

test("uno: keeps the group contract with people, the computer and run-out clocks", function()
  kit.fuzz(plugin, { rounds = 8, seats = { 1, 2, 3, 5 }, absent = 6, pick = sensible, steps = 40000 })
end)

test("uno: no seat ever sees another's hand, and the wall sees none", function()
  local state = fresh(3, 21)
  local rng = testing.fastRng(4)
  act(state, 1, "goal", 200)
  for _ = 1, 600 do
    if rules.done(state) then break end
    local waiting = rules.waitingOn(state)
    if #waiting == 0 then
      rules.act(state, nil, "bot", nil, rng)
    else
      local seat = waiting[rng:below(#waiting) + 1]
      local id, value = sensible(state, seat, rules.actions(state, seat), rng)
      if not id or not rules.act(state, seat, id, value, rng) then rules.act(state, seat, rules.auto(state, seat), nil, rng) end
    end
    local public = rules.viewFor(state, nil)
    eq(public.hand, nil, "the wall has no hand")
    eq(public.playable, nil, "the wall has nothing playable")
    eq(public.deckCards, nil, "no deck order")
    for _, player in ipairs(public.players) do
      eq(player.hand, nil, "nobody's hand is in the player list")
      eq(player.ui, nil, "nobody's menu is in the player list")
    end
    for seat = 1, 3 do
      local view = rules.viewFor(state, seat)
      local p = rules.playerOfSeat(state, seat)
      eq(view.me, p, "a seat sees itself")
      truthy(kit.same(view.hand, state.players[p].hand), "its own hand, all of it")
      for _, player in ipairs(view.players) do eq(player.hand, nil, "no other hand") end
      for _, card in ipairs(view.playable) do truthy(has(state.players[p].hand, card), "playable cards are its own") end
    end
  end
end)

-- ------------------------------------------------------------------ pictures

local canvas = require("lib.casino.canvas")
local seatui = require("lib.casino.group.seatui")

local function drawn(c)
  local colors = {}
  for y = 1, c.h do
    for ch in c:rowColors(y):gmatch(".") do colors[ch] = true end
  end
  local n = 0
  for _ in pairs(colors) do n = n + 1 end
  return n
end

test("uno: the wall and a seat draw every stage of a game without a mistake", function()
  local stages = {}
  local function look(state, ev)
    local wall = canvas.new(nil, 121, 81)
    local anim = ev and { ev = ev, t = 0.3 } or nil
    plugin.tableView.draw(wall, rules.viewFor(state, nil), anim, { waiting = {}, seats = {}, clocks = { [1] = { left = 20000, total = 60000 } } })
    truthy(drawn(wall) >= 5, "the wall has a picture in " .. tostring(state.phase) .. ": " .. drawn(wall))
    for seat = 1, 3 do
      local c = canvas.new(nil, seatui.W, seatui.H)
      local view = rules.viewFor(state, seat)
      plugin.seatView.draw(c, view, anim, { seat = seat, name = "P" .. seat })
      truthy(drawn(c) >= 2, "seat " .. seat .. " has a picture in " .. tostring(state.phase) .. ": " .. drawn(c))
      for _, r in ipairs(plugin.seatView.regions(view)) do
        truthy(r.x >= 1 and r.y >= seatui.TOP and r.x + r.w - 1 <= seatui.W and r.y + r.h - 1 <= 39, "a region stays in the game's area")
        truthy(r.id == "play" or r.id == "color", "a region is a card or a colour")
      end
    end
    local watcher = canvas.new(nil, seatui.W, seatui.H)
    plugin.seatView.draw(watcher, rules.viewFor(state, nil), anim, { seat = 8 })
    stages[state.phase] = true
  end
  for seed = 1, 3 do
    local state = fresh(3, 30 + seed)
    local rng = testing.fastRng(8 + seed)
    look(state)
    for _ = 1, 1500 do
      if rules.done(state) then break end
      local waiting = rules.waitingOn(state)
      local ev
      if #waiting == 0 then
        ev = rules.act(state, nil, "bot", nil, rng)
      else
        local seat = waiting[rng:below(#waiting) + 1]
        local id, value = sensible(state, seat, rules.actions(state, seat), rng)
        if state.phase == "goal" then id, value = "goal", 200 end
        ev = id and rules.act(state, seat, id, value, rng)
        if not ev then ev = rules.act(state, seat, rules.auto(state, seat), nil, rng) end
      end
      look(state, ev and ev[#ev])
    end
    look(state)
    testing.breathe()
  end
  -- A seat holding many cards pages through them
  local state = table_(4, { { "r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9", "y1", "y2", "y3", "y4", "y5", "y6", "y7", "g1" } })
  local view = rules.viewFor(state, 1)
  eq(view.pages, 2, "two pages")
  local pager
  for _, a in ipairs(rules.actions(state, 1)) do
    if a.id == "page" and a.value == 1 then pager = a end
  end
  truthy(pager and not pager.disabled, "a > button")
  act(state, 1, "page", 1)
  view = rules.viewFor(state, 1)
  eq(view.page, 2, "page two")
  local places = plugin.seatView.layout(view)
  eq(#places, 3, "the last three cards")
  look(state)
  for _, phase in ipairs({ "goal", "play", "scored", "over" }) do truthy(stages[phase], "drew the " .. phase .. " stage") end
end)

-- ------------------------------------------------------------------ free play

test("game night: UNO is on the free table and nothing in it touches money", function()
  local saved = package.path
  local root = "."
  for part in package.path:gmatch("[^;]+") do
    root = part:match("^(.*)[/\\]Tests[/\\]%?%.lua$") or root
  end
  package.path = root .. "/Games/GameNight/?.lua;" .. saved
  package.loaded["games.registry"] = nil
  local registry = require("games.registry")
  package.loaded["games.registry"] = nil
  package.path = saved
  eq(registry.free, true, "Game Night is a free cabinet")
  truthy(registry.find("uno"), "with UNO on it")
  eq(registry.list[1].id, "catan", "Catan first")
  eq(registry.list[2].id, "uno", "UNO after it")
  -- No button costs anything, ever, and every net is nought
  local state = fresh(4, 2)
  local rng = testing.fastRng(2)
  act(state, 1, "goal", 0)
  for _ = 1, 400 do
    if rules.done(state) then break end
    for seat = 1, 4 do
      for _, a in ipairs(rules.actions(state, seat)) do eq(a.cost, nil, "no button costs anything") end
    end
    local waiting = rules.waitingOn(state)
    if #waiting == 0 then rules.act(state, nil, "bot", nil, rng) else rules.act(state, waiting[1], "timeout", nil, rng) end
  end
  for _, net in pairs(rules.nets(state)) do eq(net, 0, "a free game's net is nought") end
  local free = require("lib.casino.group.free")
  local wallet = free.wallet({ livePlayer = function() return "Ann" end, hostName = function() return "Owner" end })
  for _, name in ipairs({ "balance", "send", "hostBalance" }) do
    truthy(not pcall(function() return wallet[name]("Ann", 10) end), "wallet." .. name .. " refuses")
  end
end)
