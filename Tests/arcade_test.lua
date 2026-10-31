-- arcade_test.lua
-- The Arcade's rules, in the deploy gate. Pure Lua: move counts against published tables, plus the rules that decide who
-- may do what. The full proof, with independent oracles on every position, is tools/arcadetest in craftos-agent.

local testing = require("testing")
local seats = require("arcade_seats")
local tournament = require("arcade_tournament")
local t, eq, truthy = testing.test, testing.eq, testing.truthy

local function rulesOf(id) return require("games." .. id .. ".rules") end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

--- How many positions lie exactly this many moves ahead. A jump that carries on stays on the same move.
local function perft(rules, s, depth)
  if depth == 0 then return 1 end
  local total = 0
  for _, a in ipairs(rules.legalActions(s)) do
    local c = copy(s)
    assert(rules.step(c, a))
    if c.chain then
      total = total + perft(rules, c, depth)
    else
      total = total + perft(rules, c, depth - 1)
    end
  end
  testing.breathe()
  return total
end

local PUBLISHED = {
  connect4 = { 7, 49, 343, 2401, 16807 },
  reversi = { 4, 12, 56, 244, 1396 },
  checkers = { 7, 49, 302, 1469, 7361 },
}

for id, counts in pairs(PUBLISHED) do
  t("arcade: " .. id .. " has the published number of positions", function()
    local rules = rulesOf(id)
    for depth, want in ipairs(counts) do
      eq(perft(rules, rules.new({ first = 1 }), depth), want, id .. " depth " .. depth)
    end
  end)
end

local function randomGame(rules, seed)
  local s = rules.new({ first = seed % 2 + 1 })
  local n = seed
  local function rng(k)
    n = (n * 16807) % 2147483647
    if k then return n % k + 1 end
    return n / 2147483647
  end
  local guard = 0
  while s.winner == 0 do
    guard = guard + 1
    assert(guard < 2000, "a game never ended")
    local list = rules.legalActions(s)
    assert(#list > 0, "no move in a game still on")
    assert(rules.step(s, list[rng(#list)], rng))
  end
  return s
end

t("arcade: every game comes to an end", function()
  for _, id in ipairs({ "connect4", "reversi", "dots", "checkers", "battleship", "mancala" }) do
    local rules = rulesOf(id)
    for seed = 1, 12 do randomGame(rules, seed * 7919) end
    testing.breathe()
  end
end)

t("arcade: dots fills 25 boxes, and mancala keeps its 48 seeds", function()
  local dots, mancala = rulesOf("dots"), rulesOf("mancala")
  for seed = 1, 30 do
    local s = randomGame(dots, seed * 104729)
    eq(s.score[1] + s.score[2], 25)
    local m = randomGame(mancala, seed * 15485863)
    eq(m.stores[1] + m.stores[2], 48)
  end
end)

t("arcade: mancala's third pit lands in the store", function()
  local rules = rulesOf("mancala")
  local s = rules.new({ first = 1 })
  rules.step(s, { kind = "sow", pit = 3 })
  eq(s.turn, 1)
end)

t("arcade: mastermind counts repeats properly", function()
  local rules = rulesOf("mastermind")
  local b, w = rules.feedback("1122", "2211")
  eq(b, 0); eq(w, 4)
  b, w = rules.feedback("1123", "1312")
  eq(b, 1); eq(w, 3)
  b, w = rules.feedback("1111", "1112")
  eq(b, 3); eq(w, 0)
end)

t("arcade: a hidden fleet and a hidden code stay out of what the other seat is shown", function()
  local battleship, mastermind = rulesOf("battleship"), rulesOf("mastermind")
  local s = battleship.new({ first = 1 })
  s.fleets[2][1] = { x = 1, y = 1, dir = "h", hits = 0 }
  local v = battleship.viewFor(s, 1)
  eq(v.fleets[2], nil)
  eq(v.grids[2], nil)
  eq(v.salts, nil)
  local m = mastermind.new({ first = 1 })
  mastermind.step(m, { kind = "set", code = "1234" })
  mastermind.step(m, { kind = "set", code = "5566" })
  eq(mastermind.viewFor(m, 1).secrets[2], nil)
end)

t("arcade: only a seated player acts, and nobody is seated for them", function()
  local match = { red = { name = "Ann" }, blue = { name = "CPU", cpu = "hard" } }
  truthy(seats.mayMove(match, match.red, "Ann"))
  truthy(not seats.mayMove(match, match.red, "Carol"))
  truthy(not seats.maySit("Ann", "Carol"))
  truthy(seats.mayWipe("Ann", "Ann"))
  truthy(not seats.mayWipe("Carol", "Ann"))
  eq(seats.resigner(match, nil, 2), 1, "a computer never resigns")
  eq(seats.wallSeat({ red = { name = "Ann", wall = "left" }, blue = { name = "CPU", cpu = "hard", wall = "right" } }, "right"), nil)
end)

t("arcade: a knockout of any size ends with one champion", function()
  for count = tournament.MIN, tournament.MAX do
    local names = {}
    for i = 1, count do names[i] = "P" .. i end
    local k = tournament.new("reversi", names)
    local champion, guard = nil, 0
    while not champion do
      guard = guard + 1
      assert(guard < 20, "a knockout never finished")
      champion = tournament.report(k, tournament.next(k).a)
    end
  end
end)
