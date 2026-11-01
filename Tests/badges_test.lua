-- badges_test.lua
-- Badges, the hub's floor badge and the player card, without a table. tools/casinotest/badges.mjs plays them on a real one.
-- Every game's own badges are read off a round its real rules finished, so a test that reads the wrong field fails here.
-- The disk is a table in memory, which also refuses a function the way textutils.serialize does.

local badges = require("lib.casino.badges")
local board = require("lib.casino.board")
local canvas = require("lib.casino.canvas")
local chat = require("lib.casino.chat")
local deck = require("lib.casino.deck")
local journal = require("lib.casino.journal")
local net = require("lib.casino.net")
local playercard = require("lib.casino.playercard")
local stats = require("lib.casino.stats")
local theme = require("lib.casino.theme")
local hub = require("casino_hub_rules")
local t = require("testing")

local C = theme.C
local GAMES = { "baccarat_game", "blackjack_game", "crazyeights_game", "hilo_game", "horseracing_game", "roulette_game",
  "slots_game", "threecard_game", "holdem_game", "videopoker_game" }

-- Plain Lua has none of these. Under ComputerCraft they stay the real ones.
if not rawget(_G, "fs") then rawset(_G, "fs", { exists = function() return false end }) end
os.epoch = os.epoch or function() return os.time() * 1000 end
os.getComputerID = os.getComputerID or function() return 1 end

local function copy(value)
  if type(value) == "function" then error("cannot serialize a function", 0) end
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

--- Run fn with an empty disk and a chat box that writes down what it is told.
local function withDisk(fn, box)
  local disk, said = {}, {}
  local load, save, log = journal.load, journal.save, journal.log
  local available, tell = chat.available, chat.tell
  local logged = {}
  journal.load = function(path) return copy(disk[path]) end
  journal.save = function(path, value)
    if disk.full then return false end
    disk[path] = copy(value)
    return true
  end
  journal.log = function(line) logged[#logged + 1] = line end
  chat.available = function() return box ~= false end
  chat.tell = function(player, text)
    said[#said + 1] = { player = player, text = text }
    return true
  end
  local ok, err = pcall(fn, disk, said, logged)
  journal.load, journal.save, journal.log = load, save, log
  chat.available, chat.tell = available, tell
  if not ok then error(err, 0) end
end

local nextId = 0

--- Finish a round the way Table:finishRound does. Returns what badges.award returned.
local function play(game, name, net_, stake, state, result)
  nextId = nextId + 1
  local round = { id = "r" .. nextId, player = name, net = net_, stake = stake or 10, state = state or {} }
  stats.record(name, round.stake, net_, round.id)
  return badges.award(game, round, result or { kind = net_ > 0 and "win" or net_ < 0 and "lose" or "push" }), round
end

local function has(names, wanted)
  for _, name in ipairs(names or {}) do
    if name == wanted then return true end
  end
  return false
end

local PLAIN = { id = "plain", title = "PLAIN" }

t.test("the first win is granted once", function()
  withDisk(function()
    t.truthy(has(play(PLAIN, "Ann", -5), "First Win") == false, "not on a loss")
    t.truthy(has(play(PLAIN, "Ann", 0), "First Win") == false, "not on a push")
    t.truthy(has(play(PLAIN, "Ann", 5), "First Win"), "on a win")
    t.eq(#play(PLAIN, "Ann", 5), 0, "nothing the second time")
    t.truthy(badges.player("Ann").have.first_win, "held")
  end)
end)

t.test("one player's badge is not another's", function()
  withDisk(function()
    play(PLAIN, "Ann", 5)
    t.eq(badges.player("Bob").have.first_win, nil)
    t.truthy(has(play(PLAIN, "Bob", 5), "First Win"), "Bob earns his own")
  end)
end)

t.test("the same round again counts for nothing", function()
  withDisk(function()
    local _, round = play(PLAIN, "Ann", 5)
    t.eq(badges.award(PLAIN, round, { kind = "win" }), nil, "the replay changes nothing")
    local shown = badges.player("Ann")
    t.eq(shown.wins, 1, "one win")
    t.eq(shown.form, "W", "one mark")
  end)
end)

t.test("five wins running: a push leaves the run alone and a loss ends it", function()
  withDisk(function()
    for _ = 1, 4 do play(PLAIN, "Ann", 5) end
    play(PLAIN, "Ann", 0)
    t.eq(badges.streak("Ann"), 4, "a push keeps it")
    play(PLAIN, "Ann", -5)
    t.eq(badges.streak("Ann"), -1, "a loss turns it")
    for _ = 1, 4 do t.eq(has(play(PLAIN, "Ann", 5), "Five Running"), false, "not yet") end
    t.truthy(has(play(PLAIN, "Ann", 5), "Five Running"), "the fifth")
    t.eq(badges.streak("Ann"), 5)
    t.eq(has(play(PLAIN, "Ann", 5), "Five Running"), false, "and once")
  end)
end)

t.test("25 rounds counts the table's whole record, from before badges", function()
  withDisk(function()
    for i = 1, 24 do stats.record("Ann", 1, -1, "old" .. i) end
    t.truthy(has(play(PLAIN, "Ann", -1), "Regular"), "the 25th")
    t.eq(badges.player("Ann").rounds, 25)
  end)
end)

t.test("a big win is ten times the stake, and goes by the same figure as the lamp", function()
  withDisk(function()
    t.eq(badges.BIG_WIN_TIMES, 10)
    t.eq(has(play(PLAIN, "Ann", 99, 10), "Big Win"), false, "9.9 times")
    t.truthy(has(play(PLAIN, "Ann", 100, 10), "Big Win"), "10 times")
  end)
end)

t.test("the form keeps the last dozen, oldest first", function()
  withDisk(function()
    for i = 1, 15 do play(PLAIN, "Ann", i % 3 == 0 and 0 or i % 2 == 0 and -1 or 1) end
    local shown = badges.player("Ann")
    t.eq(#shown.form, badges.FORM_KEPT)
    t.eq(shown.form, "LWPWLPLWPWLP", "rounds 4 to 15")
  end)
end)

t.test("a test that errors earns nothing, is logged, and takes nothing else with it", function()
  withDisk(function(_, _, logged)
    local game = { id = "x", title = "X", badges = {
      boom = { name = "Boom", text = "", test = function() error("broken") end },
      fine = { name = "Fine", text = "", test = function() return true end },
      nothing = { name = "Nothing", text = "" },
    } }
    local names = play(game, "Ann", 5)
    t.truthy(has(names, "First Win"), "common")
    t.truthy(has(names, "Fine"), "the other game badge")
    t.eq(has(names, "Boom"), false)
    t.eq(has(names, "Nothing"), false)
    t.eq(#logged, 1, "logged")
    t.truthy(logged[1]:find("boom", 1, true), "by name")
  end)
end)

t.test("a test gets a copy, so it cannot change the record", function()
  withDisk(function()
    local game = { id = "x", title = "X", badges = {
      vandal = { name = "V", text = "", test = function(_, player) player.wins = 99; player.streak = 99 end },
    } }
    play(game, "Ann", 5)
    t.eq(badges.player("Ann").wins, 1)
    t.eq(badges.streak("Ann"), 1)
  end)
end)

t.test("a badge that cannot be written is not claimed, and is still there to earn", function()
  withDisk(function(disk)
    disk.full = true
    t.eq(play(PLAIN, "Ann", 5), nil, "nothing to show")
    disk.full = nil
    t.truthy(has(play(PLAIN, "Ann", 5), "First Win"), "earned once the disk has room")
  end)
end)

t.test("award returns names alone, because a round goes to disk with them", function()
  withDisk(function()
    local game = { id = "x", title = "X", badges = { fine = { name = "Fine", text = "", test = function() return true end } } }
    for _, name in ipairs(play(game, "Ann", 5)) do t.eq(type(name), "string") end
  end)
end)

t.test("a whisper is said once, to its player and nobody else", function()
  withDisk(function(_, said)
    play(PLAIN, "Ann", 5)
    t.eq(#said, 0, "not before it is asked for: the reveal may still be playing")
    t.eq(badges.sayAll(PLAIN), 1)
    t.eq(said[1].player, "Ann")
    t.eq(said[1].text, "Badge at PLAIN: First Win")
    t.eq(badges.sayAll(PLAIN), 0, "once")
    t.eq(#said, 1)
  end)
end)

t.test("with no chat box a badge stays untold", function()
  withDisk(function()
    play(PLAIN, "Ann", 5)
    t.eq(badges.sayAll(PLAIN), 0)
    t.truthy(badges.player("Ann").have.first_win, "still held")
  end, false)
end)

t.test("one added later still gets to say it", function()
  withDisk(function(disk)
    local before = chat.available
    chat.available = function() return false end
    play(PLAIN, "Ann", 5)
    t.eq(badges.sayAll(PLAIN), 0)
    chat.available = before
    t.eq(badges.sayAll(PLAIN), 1)
    t.truthy(disk["casino_badges.dat"], "on disk")
  end)
end)

t.test("a whisper that cannot be noted is not said, so it can never be said twice", function()
  withDisk(function(disk, said)
    play(PLAIN, "Ann", 5)
    disk.full = true
    t.eq(badges.sayAll(PLAIN), 0)
    t.eq(#said, 0)
    disk.full = nil
    t.eq(badges.sayAll(PLAIN), 1)
    t.eq(#said, 1)
  end)
end)

-- ------------------------------------------------------------------ every game's own, from rounds its rules really finished

local function rig(stops)
  local rng = {}
  function rng.below(_, n)
    if n == 2 then return 1 end
    return stops
  end
  return rng
end

local function earnedBy(file, state, net_, stake)
  local game = require(file)
  local result = game.rules.result(state)
  local list = {}
  withDisk(function()
    list = play(game, "Ann", net_, stake, state, result)
  end)
  return list
end

local function finished(file, wager, keep, stream, shape)
  local rules = require(file).rules
  local state = rules.new(wager, stream or t.fastRng(9), keep or {}, {})
  shape(state, rules)
  return state, rules.net(state), type(wager) == "number" and wager or 100
end

t.test("Video Poker: a royal flush earns it, and only a royal earns it", function()
  local function hand(cards)
    return finished("videopoker_game", 10, nil, nil, function(state, rules)
      for i, name in ipairs(cards) do
        state.hand[i] = deck.parse(name)
        state.held[i] = true
      end
      rules.act(state, "draw")
    end)
  end
  t.truthy(has(earnedBy("videopoker_game", hand({ "AS", "KS", "QS", "JS", "10S" })), "Royal Flush"), "royal")
  t.truthy(has(earnedBy("videopoker_game", hand({ "9S", "KS", "QS", "JS", "10S" })), "Straight Flush"), "straight flush")
  local names = earnedBy("videopoker_game", hand({ "9S", "9D", "9H", "9C", "10S" }))
  t.truthy(has(names, "Four Of A Kind"), "quads")
  t.eq(has(names, "Royal Flush"), false)
end)

t.test("Blackjack: a natural, a doubled win and a clean split", function()
  local function round(shape)
    return finished("blackjack_game", 10, nil, nil, function(state, rules)
      state.dealer = { deck.parse("10H"), deck.parse("7D") }
      state.hold = nil
      shape(state, rules)
    end)
  end
  t.truthy(has(earnedBy("blackjack_game", round(function(state, rules)
    state.hands[1].cards = { deck.parse("AS"), deck.parse("KS") }
    state.hold = true
    rules.act(state, "stand")
  end)), "Natural"), "a natural")

  t.truthy(has(earnedBy("blackjack_game", round(function(state, rules)
    state.hands[1].cards = { deck.parse("5S"), deck.parse(rules.DOUBLE_ON - 5 .. "C") }
    deck.stack(state.cards, { "KD" })
    rules.act(state, "double")
  end)), "Double Down"), "a double that won")

  local state, net_ = round(function(s, rules)
    s.hands[1].cards = { deck.parse("8S"), deck.parse("8C") }
    deck.stack(s.cards, { "KD", "KH" })
    rules.act(s, "split")
    rules.act(s, "stand")
    rules.act(s, "stand")
  end)
  t.truthy(has(earnedBy("blackjack_game", state, net_), "Split Sweep"), "both hands of a split")

  local names = earnedBy("blackjack_game", round(function(s, rules)
    s.hands[1].cards = { deck.parse("KC"), deck.parse("9C") }
    rules.act(s, "stand")
  end))
  t.eq(has(names, "Natural"), false, "a plain win")
  t.truthy(has(names, "First Win"), "still a win")
end)

t.test("Roulette: straight up, the zero, and the number that just landed", function()
  local function spin(number, wager, keep)
    return finished("roulette_game", wager, keep, rig(number), function() end)
  end
  local state, net_ = spin(17, { ["straight:17"] = 10 })
  local names = earnedBy("roulette_game", state, net_, 10)
  t.truthy(has(names, "Straight Up"), "17")
  t.eq(has(names, "Zero Hero"), false)
  t.eq(has(names, "Struck Twice"), false)

  state, net_ = spin(0, { ["straight:0"] = 10 })
  t.truthy(has(earnedBy("roulette_game", state, net_, 10), "Zero Hero"), "the zero")

  state, net_ = spin(17, { ["straight:17"] = 10 }, { recent = { 17, 3 } })
  t.truthy(has(earnedBy("roulette_game", state, net_, 10), "Struck Twice"), "twice")

  state, net_ = spin(17, { black = 10 })
  t.eq(has(earnedBy("roulette_game", state, net_, 10), "Straight Up"), false, "an even chance bet")
end)

t.test("Slots: three 7s, any three, and two flips won", function()
  local game = require("slots_game")
  local rules = game.rules
  local function stopOf(symbol)
    for i, held in ipairs(rules.STRIP) do
      if held == symbol then return i - 1 end
    end
  end
  local state = rules.new(10, rig(stopOf(rules.SEVEN)), {}, {})
  local names = earnedBy("slots_game", state, rules.net(state), 10)
  t.truthy(has(names, "Three Sevens"), "sevens")
  t.truthy(has(names, "Three Alike"), "and three alike")

  local melon = rules.SYMBOLS[7].id == "melon" and 7
  local stream = rig(stopOf(melon))
  state = rules.new(10, stream, {}, {})
  t.eq(state.kind, "triple")
  names = earnedBy("slots_game", state, rules.net(state), 10)
  t.eq(has(names, "Three Sevens"), false, "melons are not sevens")
  rules.act(state, "gamble", stream)
  rules.act(state, "gamble", stream)
  rules.act(state, "collect", stream)
  t.truthy(has(earnedBy("slots_game", state, rules.net(state), 10), "Flip Master"), "two flips")
end)

t.test("Hi-Lo: a long run and the ceiling, and neither on a loss", function()
  local rules = require("hilo_game").rules
  local state = rules.new(10, t.fastRng(3), {}, {})
  state.guesses, state.multiple = 5, 3
  rules.act(state, "cash")
  t.truthy(has(earnedBy("hilo_game", state, rules.net(state), 10), "Long Run"), "five guesses")

  state = rules.new(10, t.fastRng(3), {}, {})
  state.guesses, state.multiple = 6, rules.MAX_MULTIPLE
  rules.act(state, "cash")
  t.truthy(has(earnedBy("hilo_game", state, rules.net(state), 10), "The Ceiling"), "the top")

  state = rules.new(10, t.fastRng(3), {}, {})
  state.guesses, state.multiple, state.over, state.lost = 7, rules.MAX_MULTIPLE, true, true
  local names = earnedBy("hilo_game", state, rules.net(state), 10)
  t.eq(has(names, "Long Run"), false, "lost")
  t.eq(has(names, "The Ceiling"), false, "lost")
end)

t.test("Baccarat: a natural nine and a called tie, and not on the other side", function()
  local function coup(side, cards)
    return finished("baccarat_game", 100, nil, nil, function(state, rules)
      deck.stack(state.cards, cards)
      rules.act(state, side)
    end)
  end
  t.truthy(has(earnedBy("baccarat_game", coup("player", { "9C", "2D", "KC", "3D" })), "Natural Nine"), "player nine")
  t.truthy(has(earnedBy("baccarat_game", coup("banker", { "2D", "9C", "3D", "KC" })), "Natural Nine"), "banker nine")
  t.eq(has(earnedBy("baccarat_game", coup("banker", { "9C", "2D", "KC", "3D" })), "Natural Nine"), false, "backed the loser")
  t.truthy(has(earnedBy("baccarat_game", coup("tie", { "9C", "9D", "KC", "KD" })), "Called The Tie"), "the tie")
  t.eq(has(earnedBy("baccarat_game", coup("player", { "9C", "9D", "KC", "KD" })), "Called The Tie"), false, "a push on a tie")
end)

t.test("3 Card Poker: a straight flush played, and not one folded", function()
  local function hand(cards, action)
    return finished("threecard_game", { ante = 100, side = 0 }, nil, nil, function(state, rules)
      for i, name in ipairs(cards) do state.player[i] = deck.parse(name) end
      rules.act(state, action)
    end)
  end
  t.truthy(has(earnedBy("threecard_game", hand({ "9S", "8S", "7S" }, "play")), "Straight Flush"), "played")
  t.eq(has(earnedBy("threecard_game", hand({ "9S", "8S", "7S" }, "fold")), "Straight Flush"), false, "folded")
  t.truthy(has(earnedBy("threecard_game", hand({ "9S", "9C", "9D" }, "play")), "Three Alike"), "trips")
end)

t.test("Hold'em: a royal on the board and in the hand, and not one folded", function()
  local function hand(hole, flop, action)
    return finished("holdem_game", { ante = 10, side = 0 }, nil, nil, function(state, rules)
      for i, name in ipairs(hole) do state.player[i] = deck.parse(name) end
      for i, name in ipairs(flop) do state.board[i] = deck.parse(name) end
      if action == "fold" then
        rules.act(state, "check")
        rules.act(state, "check")
        rules.act(state, "fold")
      else
        rules.act(state, "raise4")
      end
    end)
  end
  local royal = { "QS", "JS", "10S", "2C", "3D" }
  t.truthy(has(earnedBy("holdem_game", hand({ "AS", "KS" }, royal)), "Royal Flush"), "played")
  t.eq(has(earnedBy("holdem_game", hand({ "AS", "KS" }, royal, "fold")), "Royal Flush"), false, "folded")
  t.truthy(has(earnedBy("holdem_game", hand({ "9S", "KS" }, royal)), "Straight Flush"), "straight flush")
  t.truthy(has(earnedBy("holdem_game", hand({ "2D", "2H" }, { "2S", "2C", "9D", "KC", "4H" })), "Four Of A Kind"), "quads")
end)

t.test("Horse Racing: a long shot, an exacta and a photo", function()
  local race = { strengths = { 10, 10, 10, 10, 60, 60 }, names = { "A", "B", "C", "D", "E", "F" } }
  local game = require("horseracing_game")
  local rules = game.rules
  local function run(bets)
    local state = rules.new({ race = race, bets = bets }, rig(0), {}, {})
    return state, rules.net(state), rules.stake({ bets = bets })
  end
  local state, net_, stake = run({ { kind = "win", a = 1, amount = 10 } })
  t.eq(state.order[1], 1, "the first horse in, with this stream")
  local names = earnedBy("horseracing_game", state, net_, stake)
  t.truthy(has(names, "Long Shot"), "a long price")
  t.truthy(has(names, "Photo Finish"), "a close race")

  state, net_, stake = run({ { kind = "exacta", a = 1, b = 2, amount = 10 } })
  t.truthy(has(earnedBy("horseracing_game", state, net_, stake), "Exacta"), "the exacta")

  state, net_, stake = run({ { kind = "win", a = 5, amount = 10 } })
  names = earnedBy("horseracing_game", state, net_, stake)
  t.eq(has(names, "Long Shot"), false, "a loser")
  t.eq(has(names, "Photo Finish"), false, "not on a losing card")

  race.strengths = { 60, 10, 10, 10, 10, 10 }
  state, net_, stake = run({ { kind = "win", a = 1, amount = 10 } })
  t.eq(has(earnedBy("horseracing_game", state, net_, stake), "Long Shot"), false, "the favourite")
end)

t.test("Crazy Eights: a clean sweep needs the dealer still holding a full hand", function()
  local game = require("crazyeights_game")
  local rules = game.rules
  local function ended(dealerCards)
    local state = rules.new(10, t.fastRng(5), {}, {})
    state.over, state.winner = true, "player"
    while #state.dealer > dealerCards do table.remove(state.dealer) end
    while #state.dealer < dealerCards do state.dealer[#state.dealer + 1] = 0 end
    state.player = {}
    return state
  end
  local state = ended(rules.HAND)
  t.truthy(has(earnedBy("crazyeights_game", state, rules.net(state), 10), "Clean Sweep"), "a full hand")
  state = ended(rules.HAND - 1)
  t.eq(has(earnedBy("crazyeights_game", state, rules.net(state), 10), "Clean Sweep"), false, "one short")
end)

for _, file in ipairs(GAMES) do
  t.test(file .. ": its badges are complete, its whispers fit a line, and its card fits the wall", function()
    local game = require(file)
    t.truthy(game.badges and next(game.badges), "a badge of its own")
    local c = canvas.new(nil, 121, 81)
    local list = badges.list(game)
    t.truthy(#list <= playercard.rowsFree(c) * playercard.COLUMNS, "room on the card")
    local seen = {}
    for _, def in ipairs(list) do
      t.eq(seen[def.id], nil, def.id .. " twice")
      seen[def.id] = true
      t.eq(type(def.name), "string", def.id)
      t.eq(type(def.text), "string", def.id)
      t.truthy(#badges.whisper(game, def.id) <= chat.LINE, badges.whisper(game, def.id))
      t.truthy(#def.name <= 51 and #def.text <= 51, def.id .. " fits a column")
    end
    t.truthy(seen.first_win and seen.five_running and seen.regular and seen.big_win and seen.floor, "the common ones")
  end)
end

-- ------------------------------------------------------------------ the card and the board

local function text(c, y)
  return table.concat(c.ch[y])
end

local function allText(c)
  local lines = {}
  for y = 1, c.h do lines[y] = text(c, y) end
  return table.concat(lines, "\n")
end

local function card(over)
  local p = { name = "Alice", rounds = 0, net = 0, best = 0, wins = 0, losses = 0, pushes = 0, streak = 0, form = "",
    have = {}, list = badges.list(require("videopoker_game")) }
  for key, value in pairs(over or {}) do p[key] = value end
  return p
end

t.test("a card with nothing on it draws, with no sum over nothing", function()
  local c = canvas.new(nil, 121, 81)
  playercard.draw(c, { title = "X", seat = "Alice", balance = 10 }, card())
  t.truthy(allText(c):find("BADGES 0 OF 8", 1, true), "the count")
  t.eq(allText(c):find("% won", 1, true), nil, "no rate with no rounds")
end)

t.test("the form is blocks of the right colour, oldest on the left", function()
  local c = canvas.new(nil, 121, 81)
  playercard.draw(c, { title = "X" }, card({ form = "WLP", wins = 1, losses = 1, pushes = 1, rounds = 3 }))
  local row = c:rowColors(45)
  t.eq(row:sub(5, 5), C.win, "first")
  t.eq(row:sub(14, 14), C.red, "second")
  t.eq(row:sub(23, 23), C.gold, "third")
  t.eq(row:sub(32, 32), C.feltDark, "a round not played yet")
end)

t.test("the bar shares its width between wins, pushes and losses", function()
  local c = canvas.new(nil, 121, 81)
  playercard.draw(c, { title = "X" }, card({ wins = 3, losses = 1, pushes = 0, rounds = 4 }))
  local row = c:rowColors(34)
  local _, wins = row:gsub(C.win, "")
  local _, losses = row:gsub(C.red, "")
  t.eq(wins + losses, 112, "the whole width")
  t.truthy(wins > losses * 2.5, "three quarters")
  t.truthy(allText(c):find("75% won", 1, true), "the rate")
end)

t.test("a badge that is held looks held, and the count says so", function()
  local c = canvas.new(nil, 121, 81)
  playercard.draw(c, { title = "X" }, card({ have = { first_win = 1, royal = 2 } }))
  t.truthy(allText(c):find("BADGES 2 OF 8", 1, true), "the count")
  t.truthy(allText(c):find("Royal Flush", 1, true), "by name")
  t.truthy(allText(c):find("Beat The House", 1, true), "the floor badge is on every card")
end)

t.test("a favourite game shows when there is one", function()
  local c = canvas.new(nil, 121, 81)
  playercard.draw(c, { title = "X" }, card({ fav = "Hi-Lo" }))
  t.truthy(allText(c):find("Favourite game Hi-Lo", 1, true))
  c = canvas.new(nil, 121, 81)
  playercard.draw(c, { title = "X" }, card())
  t.eq(allText(c):find("Favourite", 1, true), nil)
end)

t.test("the biggest numbers and a long name stay on the wall", function()
  local c = canvas.new(nil, 121, 81)
  playercard.draw(c, { title = "X" }, card({ name = "AVeryLongPlayerNme", rounds = 123456, net = -12345678, best = 98765432,
    wins = 100000, losses = 23456, pushes = 0, streak = -123 }))
  t.truthy(allText(c):find("-12,345,678", 1, true), "the net in words, when the big font will not fit")
end)

t.test("the scoreboard shows a run at the top, and on the smallest monitor too", function()
  for _, size in ipairs({ { 29, 24 }, { 15, 10 }, { 8, 6 } }) do
    local c = canvas.new(nil, size[1], size[2])
    board.draw(c, { title = "HI-LO", leaders = {}, streak = "Alice won 5 running" })
    t.truthy(allText(c):find("Alice", 1, true), "on a " .. size[1] .. " wide board")
  end
  local c = canvas.new(nil, 29, 24)
  board.draw(c, { title = "HI-LO", leaders = {} })
  t.eq(allText(c):find("running", 1, true), nil, "and nothing with no run")
end)

-- ------------------------------------------------------------------ the floor badge, on the hub

local function round(game, name, result)
  return { kind = "round", game = game, player = name, wagered = 10, net = result }
end

local function beatAll(data, name, last, sender)
  for id, known in pairs(hub.GAMES) do
    if not known.noHouse and id ~= last then hub.apply(data, sender or 7, round(id, name, 5), 100) end
  end
end

t.test("the hub counts every house game, and Poker Table is not one", function()
  local count = 0
  for _, known in pairs(hub.GAMES) do
    if not known.noHouse then count = count + 1 end
  end
  t.eq(count, 10)
  t.eq(hub.GAMES.pokertable.noHouse, true)
end)

t.test("beating nine games of ten is not beating them all", function()
  local data = hub.new()
  beatAll(data, "Ann", "hilo")
  t.eq(#hub.champions(data), 0)
  hub.apply(data, 21, round("pokertable", "Ann", 50), 200)
  t.eq(#hub.champions(data), 0, "the poker table counts for nothing")
  hub.apply(data, 21, round("hilo", "Ann", 5), 300)
  local list = hub.champions(data)
  t.eq(#list, 1)
  t.eq(list[1].name, "Ann")
  t.eq(list[1].by, 21, "the table that played the last of them")
  t.eq(list[1].at, 300)
end)

t.test("a win that leaves a player behind at that game has not beaten it", function()
  local data = hub.new()
  beatAll(data, "Ann", "hilo")
  hub.apply(data, 21, round("hilo", "Ann", -50), 300)
  hub.apply(data, 21, round("hilo", "Ann", 40), 301)
  t.eq(#hub.champions(data), 0, "still 10 down")
  hub.apply(data, 22, round("hilo", "Ann", 11), 302)
  t.eq(hub.champions(data)[1].by, 22, "now ahead")
end)

t.test("once beaten, a game stays beaten, and the honour is granted once", function()
  local data = hub.new()
  beatAll(data, "Ann", "hilo")
  hub.apply(data, 21, round("hilo", "Ann", 5), 300)
  hub.apply(data, 99, round("hilo", "Ann", -500), 400)
  hub.apply(data, 98, round("hilo", "Ann", 900), 500)
  local list = hub.champions(data)
  t.eq(#list, 1)
  t.eq(list[1].by, 21, "still the first table")
  t.eq(list[1].at, 300, "still the first time")
end)

t.test("a made-up game grows nothing and a save from before badges still works", function()
  local data = hub.new()
  hub.apply(data, 1, round("not-a-game", "Ann", 5), 1)
  t.eq(data.players.Ann.games, nil, "nothing kept")
  local saved = hub.restore({ players = { Old = { rounds = 9, wagered = 90, net = -5, best = 2 } } })
  t.eq(type(saved.champions), "table")
  t.eq(hub.leaders(saved)[1].fav, nil)
  beatAll(saved, "Old", "hilo")
  hub.apply(saved, 3, round("hilo", "Old", 5), 2)
  t.eq(hub.champions(saved)[1].name, "Old")
end)

t.test("the floor list survives a save and goes out in the state, in a shape tables believe", function()
  local data = hub.new()
  beatAll(data, "Ann", "hilo")
  hub.apply(data, 21, round("hilo", "Ann", 5), 300)
  local state = hub.restore(copy(data))
  t.eq(hub.champions(state)[1].name, "Ann")
  local out = hub.state(state)
  t.eq(out.champions[1].by, 21)
  t.truthy(net.validState(out), "a table believes it")
end)

t.test("the list in a state is capped at what a table will believe", function()
  local data = hub.new()
  for i = 1, hub.CHAMPIONS_KEPT + 5 do data.champions["P" .. i] = { at = i, by = 1 } end
  local out = hub.state(data)
  t.eq(#out.champions, hub.CHAMPIONS_KEPT)
  t.eq(out.champions[1].name, "P" .. hub.CHAMPIONS_KEPT + 5, "newest first")
  t.truthy(net.validState(out))
end)

t.test("a hub with no list is still believed, and a broken list is not", function()
  t.truthy(net.validState({ jackpot = 1000, leaders = {} }), "an older hub")
  for _, bad in ipairs({ "x", { "x" }, { { name = "" } }, { { name = "A", at = "1", by = 1 } }, { { name = "A", at = 1 } },
    { a = { name = "A", at = 1, by = 1 } } }) do
    t.eq(net.validState({ jackpot = 1000, leaders = {}, champions = bad }), false)
  end
end)

t.test("a favourite needs more than one game behind it", function()
  local data = hub.new()
  hub.apply(data, 1, round("hilo", "Ann", 5), 1)
  t.eq(hub.leaders(data)[1].fav, nil, "one game")
  hub.apply(data, 1, round("slots", "Ann", 5), 2)
  hub.apply(data, 1, round("slots", "Ann", 5), 3)
  t.eq(hub.leaders(data)[1].fav, "Slots")
end)

t.test("a table's card takes the hub's word, and only the winning table whispers", function()
  withDisk(function(_, said)
    local here = os.getComputerID()
    badges.hear({ { name = "Ann", at = 5, by = here }, { name = "Bob", at = 6, by = here + 1 } })
    t.truthy(badges.player("Ann").have.floor, "Ann")
    t.truthy(badges.player("Bob").have.floor, "Bob too")
    t.eq(badges.sayAll(PLAIN), 1, "only the table that played it")
    t.eq(said[1].player, "Ann")
    t.eq(said[1].text, "Badge at PLAIN: Beat The House")
    t.eq(badges.hear({ { name = "Ann", at = 5, by = here } }), 0, "heard again")
    t.eq(badges.sayAll(PLAIN), 0, "said once")
  end)
end)

t.test("hearing nothing costs nothing", function()
  withDisk(function(disk)
    t.eq(badges.hear(nil), 0)
    t.eq(badges.hear({}), 0)
    t.eq(disk["casino_badges.dat"], nil, "no file")
  end)
end)
