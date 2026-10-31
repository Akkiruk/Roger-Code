-- tournament_test.lua
-- Hub tournaments: the hub's rules for a contest, what every table believes, and a table's one entry per player.
-- A whole contest on real tables is proved by tools/casinotest/tournament.mjs in craftos-agent.

local contest = require("casino_hub_contest")
local hub = require("casino_hub_rules")
local journal = require("lib.casino.journal")
local net = require("lib.casino.net")
local pretend = require("lib.casino.pretend")
local tournament = require("lib.casino.tournament")
local t = require("testing")

local START = 1000000
local LONG = 30 * 60000

local function book()
  local b = contest.new()
  t.truthy(contest.start(b, "hilo", 30, "Hosty", START), "started")
  return b
end

local function score(b, player, chips, rounds, extra)
  local message = { kind = "tscore", contest = b.live.id, game = "hilo", player = player, chips = chips, rounds = rounds }
  for key, value in pairs(extra or {}) do message[key] = value end
  return message
end

local function report(b, sender, player, chips, rounds, extra)
  return contest.score(b, sender, score(b, player, chips, rounds, extra), START + 1000)
end

t.test("the owner can start one contest at a time, on a house game, for a length on offer", function()
  local b = contest.new()
  t.eq(contest.start(b, "pokertable", 30, "Hosty", START), nil, "no house at PokerTable")
  t.eq(contest.start(b, "hilo", 7, "Hosty", START), nil, "a length nobody offered")
  local live = contest.start(b, "hilo", 30, "Hosty", START)
  t.eq(live.chips, 1000)
  t.eq(live.ends, START + LONG)
  t.eq(contest.start(b, "slots", 15, "Hosty", START), nil, "one at a time")
end)

t.test("every house game is on the hub's list, and has a name", function()
  for _, id in ipairs(contest.GAMES) do t.truthy(hub.GAMES[id], id) end
  t.eq(#contest.GAMES, 10)
end)

t.test("a report puts a player on the board, best chips first", function()
  local b = book()
  t.eq(report(b, 11, "Ann", 1200, 3), true)
  t.eq(report(b, 12, "Bob", 1500, 3), true)
  t.eq(report(b, 11, "Cat", 800, 5), true)
  local list = contest.standings(b.live)
  t.eq(list[1].name, "Bob")
  t.eq(list[2].name, "Ann")
  t.eq(list[3].name, "Cat")
end)

t.test("a tie goes to whoever took fewer rounds, then by name, so the order never flickers", function()
  local b = book()
  report(b, 11, "Zed", 1200, 3)
  report(b, 12, "Ann", 1200, 9)
  report(b, 13, "Bob", 1200, 3)
  local list = contest.standings(b.live)
  t.eq(list[1].name, "Bob")
  t.eq(list[2].name, "Zed")
  t.eq(list[3].name, "Ann")
end)

t.test("a score is accepted once: a repeat or a replay changes nothing", function()
  local b = book()
  t.eq(report(b, 11, "Ann", 5000, 3), true)
  t.eq(report(b, 11, "Ann", 300, 7), true, "a bad run")
  t.eq(report(b, 11, "Ann", 300, 7), false, "the same report again")
  t.eq(report(b, 11, "Ann", 5000, 3), false, "an old report replayed")
  t.eq(report(b, 11, "Ann", 9000, 7), false, "the same round, a different figure")
  t.eq(b.live.entries.Ann.chips, 300)
  t.eq(b.live.entries.Ann.rounds, 7)
end)

t.test("a final report ends an entry for good", function()
  local b = book()
  t.eq(report(b, 11, "Ann", 0, 4, { final = true }), true)
  t.eq(report(b, 11, "Ann", 9000, 5), false, "a stack that is out cannot come back")
  t.eq(b.live.entries.Ann.chips, 0)
  t.eq(b.live.entries.Ann.final, true)
end)

t.test("one stack, one table: another table cannot add to an entry", function()
  local b = book()
  report(b, 11, "Ann", 1200, 3)
  t.eq(report(b, 12, "Ann", 9000, 9), false)
  t.eq(b.live.entries.Ann.table, 11)
end)

t.test("nonsense gets nowhere", function()
  local b = book()
  local bad = {
    { contest = "other" }, { game = "slots" }, { player = "" }, { player = 7 }, { player = ("x"):rep(33) },
    { chips = -1 }, { chips = 1.5 }, { chips = "lots" }, { chips = 1e12 }, { chips = 0 / 0 }, { chips = math.huge },
    { rounds = 0 }, { rounds = -2 }, { rounds = 1.5 }, { rounds = 1e9 }, { final = "yes" },
  }
  for i, change in ipairs(bad) do
    local message = score(b, "Ann", 1200, 3, change)
    t.eq(contest.score(b, 11, message, START + 1000), false, "case " .. i)
  end
  t.eq(next(b.live.entries), nil, "nothing on the board")
  t.eq(contest.score(contest.new(), 11, { contest = "x" }, START), false, "no contest running")
end)

t.test("no flood of names can grow the save or shut out a better stack", function()
  local b = book()
  for i = 1, contest.MAX_ENTRIES + 20 do report(b, 11, "n" .. i, 100, 1) end
  t.eq(#contest.standings(b.live), contest.MAX_ENTRIES, "capped")
  t.eq(report(b, 12, "Ann", 90, 1), false, "no better than the rest")
  t.eq(report(b, 12, "Ann", 5000, 1), true, "better")
  t.eq(#contest.standings(b.live), contest.MAX_ENTRIES, "still capped")
end)

t.test("the hub takes a score through its usual door and hears the table, moving nothing else", function()
  local data = hub.new()
  contest.start(data.contest, "hilo", 30, "Hosty", START)
  local changed = hub.apply(data, 11, score(data.contest, "Ann", 1200, 1), START + 10)
  t.eq(changed, true)
  t.eq(data.tables[11].game, "hilo")
  t.eq(hub.totals(data).rounds, 0, "not a round")
  t.eq(#hub.leaders(data), 0, "not the leaderboard")
  t.eq(data.jackpot, hub.SEED, "not the pot")
end)

t.test("a saved hub keeps its contest, and an older save loads", function()
  local data = hub.new()
  contest.start(data.contest, "hilo", 30, "Hosty", START)
  t.eq(hub.restore(data).contest.live.game, "hilo")
  t.eq(#hub.restore({ jackpot = 1500 }).contest.past, 0)
end)

t.test("scores still count in the grace after the end, and not after it", function()
  local b = book()
  local ends = b.live.ends
  t.eq(contest.running(b.live, ends), false, "the clock is up")
  t.eq(contest.score(b, 11, score(b, "Ann", 1200, 1), ends + 1000), true, "a round that was playing")
  t.eq(contest.score(b, 11, score(b, "Ann", 1500, 2), ends + contest.GRACE_MS), false, "too late")
end)

t.test("ending a contest puts the standings on the books and whispers the top three", function()
  local b = book()
  for i, chips in ipairs({ 1200, 1500, 800, 700 }) do report(b, 11, "p" .. i, chips, 2) end
  t.eq(contest.tick(b, b.live.ends), nil, "not until the grace is over")
  local record = contest.tick(b, b.live.ends + contest.GRACE_MS)
  t.eq(b.live, nil)
  t.eq(b.past[1], record)
  t.eq(record.top[1].name, "p2")
  local lines = contest.whispers(record, "Hi-Lo")
  t.eq(#lines, 3)
  t.eq(lines[1].player, "p2")
  t.eq(lines[1].text, "Hi-Lo tournament: you came 1st with 1500 chips")
  t.eq(lines[3].player, "p3")
end)

t.test("the owner can stop a contest early, and the last rounds still get the grace", function()
  local b = book()
  t.eq(contest.stop(b, START + 5000), true)
  t.eq(contest.running(b.live, START + 5000), false)
  t.eq(contest.stop(b, START + 6000), false, "already stopped")
  t.eq(contest.score(b, 11, score(b, "Ann", 1200, 1), START + 6000), true)
end)

t.test("a contest nobody played leaves nothing, and past winners stop at the limit", function()
  local b = contest.new()
  contest.start(b, "hilo", 15, "Hosty", START)
  t.eq(contest.tick(b, START + 900000 + contest.GRACE_MS), nil)
  t.eq(#b.past, 0)
  for i = 1, contest.PAST_KEPT + 3 do
    local at = START + i * 2000000
    contest.start(b, "hilo", 15, "Hosty", at)
    contest.score(b, 11, score(b, "Ann", i, 1), at + 1)
    contest.tick(b, at + 900000 + contest.GRACE_MS)
  end
  t.eq(#b.past, contest.PAST_KEPT)
  t.eq(b.past[1].top[1].chips, contest.PAST_KEPT + 3, "newest first")
end)

t.test("what the hub broadcasts is what a table believes", function()
  local b = book()
  report(b, 11, "Ann", 1200, 2)
  t.eq(net.validContest(contest.broadcast(b, START + 1000)), true)
  report(b, 11, "Bob", 0, 2, { final = true })
  t.eq(net.validContest(contest.broadcast(b, b.live.ends + 5)), true, "with an entry finished, past the end")
  t.eq(contest.broadcast(b, b.live.ends + 5).open, false)
  t.eq(contest.broadcast(contest.new(), START), nil, "nothing to say")
end)

t.test("a full board still fits what a table will believe", function()
  local b = book()
  for i = 1, contest.MAX_ENTRIES do report(b, 11, "n" .. i, 100 + i, 1) end
  t.eq(net.validContest(contest.broadcast(b, START + 1000)), true)
end)

t.test("a table turns away a contest that is not in good order", function()
  local good = function(change)
    local message = { id = "a1", game = "hilo", chips = 1000, remaining = 5000, open = true, board = {} }
    for key, value in pairs(change) do message[key] = value end
    return message
  end
  t.eq(net.validContest(good({})), true)
  for i, change in ipairs({
    { id = {} }, { game = 7 }, { game = "" }, { chips = 0 }, { chips = 1e12 }, { chips = 0 / 0 }, { remaining = -1 }, { remaining = 1e12 },
    { open = "yes" }, { board = 5 }, { board = { "x" } }, { board = { one = { name = "a", chips = 1, rounds = 1, table = 1 } } },
    { board = { { name = "", chips = 1, rounds = 1, table = 1 } } }, { board = { { name = "a", chips = -1, rounds = 1, table = 1 } } },
    { board = { { name = "a", chips = 1, rounds = 1 } } }, { board = { { name = "a", chips = 1, rounds = 1, table = 1, final = 3 } } },
  }) do
    t.eq(net.validContest(good(change)), false, "case " .. i)
  end
end)

-- ------------------------------------------------------------------ a table's side, with its file in memory

local disk, sent
local realSave, realLoad, realSend, realContest, realLog = journal.save, journal.load, net.send, net.contest, journal.log

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, inner in pairs(value) do out[key] = copy(inner) end
  return out
end

local function withTable(fn)
  disk, sent = nil, {}
  journal.save = function(_, value) disk = copy(value) return true end
  journal.load = function() return copy(disk) end
  journal.log = function() end
  net.send = function(kind, payload) sent[#sent + 1] = { kind = kind, payload = payload } end
  net.contest = function() return nil end
  local realId = os.getComputerID
  os.getComputerID = function() return 11 end
  local ok, err = pcall(fn)
  journal.save, journal.load, net.send, net.contest, journal.log = realSave, realLoad, realSend, realContest, realLog
  os.getComputerID = realId
  if not ok then error(err, 0) end
end

local function offered(board)
  return { id = "c1", game = "hilo", chips = 1000, open = true, ends = START + LONG, board = board or {} }
end

t.test("a table offers only a contest that is open, on its own game, with time left", function()
  withTable(function()
    net.contest = function() return offered() end
    t.truthy(tournament.offer("hilo", START))
    t.eq(tournament.offer("slots", START), nil, "another game")
    t.eq(tournament.offer("hilo", START + LONG), nil, "time up")
    net.contest = function() return nil end
    t.eq(tournament.offer("hilo", START), nil, "a hub gone quiet")
  end)
end)

t.test("everyone gets the same chips, once", function()
  withTable(function()
    local entry = tournament.enter(offered(), "Ann")
    t.eq(entry.chips, 1000)
    t.eq(tournament.enter(offered(), "Bob").chips, 1000)
    t.eq(disk.players.Ann.chips, 1000, "on disk at once")
  end)
end)

t.test("coming back carries on the same stack, not a fresh one", function()
  withTable(function()
    tournament.enter(offered(), "Ann")
    local hooks = tournament.hooks("Ann")
    hooks.opened(100)
    hooks.settled(-400, 600)
    t.eq(tournament.enter(offered(), "Ann").chips, 600)
  end)
end)

t.test("a stack that has run out cannot enter again", function()
  withTable(function()
    tournament.enter(offered(), "Ann")
    tournament.hooks("Ann").settled(-1000, 0)
    local entry, title = tournament.enter(offered(), "Ann")
    t.eq(entry, nil)
    t.eq(title, "ONE ENTRY EACH")
    t.eq(sent[#sent].payload.final, true, "and the hub is told it is final")
  end)
end)

t.test("a reboot in the middle of a round costs what was staked, and never gives a fresh stack", function()
  withTable(function()
    tournament.enter(offered(), "Ann")
    tournament.hooks("Ann").opened(300)
    t.eq(disk.players.Ann.risk, 300, "on disk as the round opens")
    tournament.boot()
    t.eq(disk.players.Ann.chips, 700)
    t.eq(disk.players.Ann.risk, nil)
    t.eq(disk.players.Ann.rounds, 1, "a report the hub will take")
    tournament.boot()
    t.eq(disk.players.Ann.chips, 700, "charged once")
    t.eq(tournament.enter(offered(), "Ann").chips, 700)
  end)
end)

t.test("a reboot between rounds costs nothing", function()
  withTable(function()
    tournament.enter(offered(), "Ann")
    local hooks = tournament.hooks("Ann")
    hooks.opened(300)
    hooks.settled(300, 1300)
    tournament.boot()
    t.eq(disk.players.Ann.chips, 1300)
  end)
end)

t.test("an entry at another table is turned away", function()
  withTable(function()
    local entry, title, detail = tournament.enter(offered({ { name = "Ann", chips = 900, rounds = 2, table = 12 } }), "Ann")
    t.eq(entry, nil)
    t.eq(title, "ONE ENTRY EACH")
    t.truthy(detail:find("#12", 1, true), detail)
  end)
end)

t.test("a file that has gone falls back on the hub's word, not a fresh stack", function()
  withTable(function()
    t.eq(tournament.enter(offered({ { name = "Ann", chips = 150, rounds = 6, table = 11 } }), "Ann").chips, 150)
    t.eq(disk.players.Ann.rounds, 6)
    disk = nil
    local entry = tournament.enter(offered({ { name = "Ann", chips = 0, rounds = 8, table = 11, final = true } }), "Ann")
    t.eq(entry, nil, "out, by the hub's word")
  end)
end)

t.test("a new contest starts a new file", function()
  withTable(function()
    tournament.enter(offered(), "Ann")
    tournament.hooks("Ann").settled(-1000, 0)
    local later = offered()
    later.id = "c2"
    t.eq(tournament.enter(later, "Ann").chips, 1000)
    t.eq(disk.id, "c2")
  end)
end)

t.test("scores are said again until the hub's grace is over, and the hub's end is followed", function()
  withTable(function()
    tournament.enter(offered(), "Ann")
    tournament.hooks("Ann").settled(200, 1200)
    sent = {}
    tournament.tick(START + 100000)
    t.eq(#sent, 1)
    t.eq(sent[1].kind, "tscore")
    t.eq(sent[1].payload.chips, 1200)
    sent = {}
    tournament.tick(START + 100001)
    t.eq(#sent, 0, "not every frame")

    local stopped = offered()
    stopped.ends = START + 200000
    net.contest = function() return stopped end
    tournament.tick(START + 150000)
    t.eq(disk.ends, START + 200000, "stopped early")
    t.eq(tournament.hooks("Ann").ends(), START + 200000)
    sent = {}
    tournament.tick(START + 200000 + tournament.GRACE_MS + 1)
    t.eq(#sent, 0, "after the grace there is nobody to tell")
  end)
end)

t.test("a seat in a tournament is the same pretend seat, with its entry behind it", function()
  withTable(function()
    tournament.enter(offered(), "Ann")
    local sitter = pretend.new({ kind = "tournament", title = "TOURNAMENT", name = "Ann", chips = 1000, at = START,
      hooks = tournament.hooks("Ann") })
    sitter.stands.journal.saveRound({ phase = "open", stake = 250, state = {} })
    t.eq(disk.players.Ann.risk, 250)
    sitter.stands.books.move("Ann", -250, "x")
    t.eq(disk.players.Ann.chips, 750)
    t.eq(disk.players.Ann.risk, nil)
    t.eq(sent[#sent].payload.rounds, 1)
  end)
end)

t.test("the clock ends a seat on the bet screen, and a round that overruns it forfeits", function()
  withTable(function()
    tournament.enter(offered(), "Ann")
    local ends = START + LONG
    local sitter = pretend.new({ kind = "tournament", chips = 1000, at = START, name = "Ann", hooks = tournament.hooks("Ann") })
    sitter:touch(ends - 1)
    t.eq(sitter:over(ends - 1, { name = "bet" }), nil)
    t.eq(sitter:over(ends, { name = "bet" }), "time")
    sitter.stands.journal.saveRound({ phase = "open", stake = 100, state = {} })
    sitter:touch(ends + 1000)
    t.eq(sitter:over(ends + 1000, { name = "play" }), nil, "a round playing at the buzzer finishes")
    t.eq(sitter:over(ends + pretend.OVERTIME_MS, { name = "play" }), "time")
    sitter:ended()
    t.eq(disk.players.Ann.chips, 900, "stalling cannot save a losing round")
  end)
end)

t.test("a tournament round is never ended by the idle clock, because the entry is at stake", function()
  withTable(function()
    tournament.enter(offered(), "Ann")
    local sitter = pretend.new({ kind = "tournament", chips = 1000, at = START, name = "Ann", hooks = tournament.hooks("Ann") })
    sitter.stands.journal.saveRound({ phase = "open", stake = 100, state = {} })
    sitter:wanted()
    t.eq(sitter:over(START + 100000, { name = "play" }), nil)
  end)
end)
