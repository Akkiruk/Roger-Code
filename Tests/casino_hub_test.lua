-- casino_hub_test.lua
-- The hub's books: leaderboards, measured returns, and a shared pot only one table can pay.

local rules = require("casino_hub_rules")
local t = require("testing")

local function round(game, player, wagered, result)
  return { kind = "round", game = game, player = player, wagered = wagered, net = result }
end

local function feed(data, messages)
  for i, message in ipairs(messages) do rules.apply(data, 7, message, 1000 + i) end
end

t.test("a new hub holds the seed and nothing else", function()
  local data = rules.new()
  t.eq(data.jackpot, 1000)
  t.eq(#rules.leaders(data), 0)
  t.eq(#rules.games(data), 0)
end)

t.test("leaders rank by net and by biggest win", function()
  local data = rules.new()
  feed(data, {
    round("slots", "Ann", 100, 500), round("slots", "Ann", 100, -100), round("hilo", "Bob", 50, 900),
    round("hilo", "Cat", 80, -80),
  })
  local byNet = rules.leaders(data, 2)
  t.eq(#byNet, 2, "cut to the limit")
  t.eq(byNet[1].name, "Bob")
  t.eq(byNet[2].name, "Ann")
  t.eq(byNet[2].net, 400)
  t.eq(byNet[2].best, 500, "the biggest single win")
  t.eq(byNet[2].rounds, 2)
  t.eq(rules.leaders(data, 8, "best")[1].name, "Bob")
end)

t.test("the measured return is real tokens back per token bet", function()
  local data = rules.new()
  feed(data, { round("hilo", "Ann", 100, -100), round("hilo", "Ann", 100, 96), round("hilo", "Bob", 200, -60) })
  local game = rules.games(data)[1]
  t.eq(game.name, "Hi-Lo")
  t.eq(game.rounds, 3)
  t.eq(game.wagered, 400)
  t.near(game.measured, 336 / 400, 1e-9)
  t.near(game.target, 0.96, 1e-9)
end)

t.test("games sort by how much they have seen, and an unknown game still counts", function()
  local data = rules.new()
  feed(data, { round("hilo", "Ann", 10, 0), round("newgame", "Ann", 500, 0) })
  local games = rules.games(data)
  t.eq(games[1].id, "newgame")
  t.eq(games[1].name, "newgame")
  t.eq(games[1].target, nil)
end)

t.test("a table of players trading chips measures exactly even", function()
  local data = rules.new()
  feed(data, { round("pokertable", "Ann", 40, 35), round("pokertable", "Bob", 40, -35) })
  t.eq(rules.games(data)[1].net, 0)
  t.near(rules.games(data)[1].measured, 1, 1e-12)
end)

t.test("wins are kept biggest first and latest first, and capped", function()
  local data = rules.new()
  local messages = {}
  for i = 1, rules.KEPT_WINS + 4 do messages[i] = round("slots", "Ann", 10, i * 10) end
  messages[#messages + 1] = round("slots", "Bob", 10, 5)
  feed(data, messages)
  t.eq(#data.biggest, rules.KEPT_WINS)
  t.eq(#data.latest, rules.KEPT_WINS)
  t.eq(data.biggest[1].amount, (rules.KEPT_WINS + 4) * 10)
  t.eq(data.latest[1].player, "Bob")
end)

t.test("nothing in the books appears twice, because the save would refuse it", function()
  local data = rules.new()
  feed(data, {
    round("slots", "Ann", 10, 40), round("hilo", "Bob", 10, 90),
    { kind = "jackpot", game = "slots", player = "Ann", amount = 500 },
  })
  local seen = {}
  local function walk(value)
    if type(value) ~= "table" then return end
    t.truthy(not seen[value], "a table reached twice")
    seen[value] = true
    for _, inner in pairs(value) do walk(inner) end
  end
  walk(data)
end)

t.test("losses are not wins", function()
  local data = rules.new()
  feed(data, { round("slots", "Ann", 10, -10), round("slots", "Ann", 10, 0) })
  t.eq(#data.latest, 0)
end)

t.test("the pot grows by what tables send", function()
  local data = rules.new()
  feed(data, { { kind = "pot", amount = 25 }, { kind = "pot", amount = 5.9 } })
  t.eq(data.jackpot, 1030)
end)

local function claim(data, sender, id, amount)
  local changed, grant = rules.apply(data, sender, { kind = "claim", id = id, game = "slots", player = "Ann", amount = amount }, 5000)
  return grant and grant.amount, changed, grant
end

t.test("two tables claiming the same pot cannot both be paid it", function()
  local data = rules.new()
  feed(data, { { kind = "pot", amount = 4000 } })
  t.eq(data.jackpot, 5000)
  t.eq(claim(data, 11, "a", 5000), 5000, "the first table gets the pot")
  t.eq(data.jackpot, rules.SEED, "the pool resets at once")
  t.eq(claim(data, 12, "b", 5000), rules.SEED, "the second gets only the fresh pool")
end)

t.test("a claim above the pool is cut to the pool, and a small one still resets it", function()
  local data = rules.new()
  t.eq(claim(data, 11, "a", 2500), 1000)
  feed(data, { { kind = "pot", amount = 500 } })
  t.eq(claim(data, 11, "b", 200), 200, "a small bet takes a small share")
  t.eq(data.jackpot, rules.SEED, "as the slots rules say, the pot still resets")
end)

t.test("a claim retried after a reboot gets the same answer and takes nothing more", function()
  local data = rules.new()
  feed(data, { { kind = "pot", amount = 500 } })
  t.eq(claim(data, 11, "a", 1500), 1500)
  feed(data, { { kind = "pot", amount = 300 } })
  t.eq(claim(data, 11, "a", 1500), 1500, "the same answer")
  t.eq(data.jackpot, 1300, "the pool is left alone")
  t.eq(claim(data, 12, "a", 100), 100, "the same id from another table is its own claim")
end)

t.test("the grant goes back to the table that asked", function()
  local data = rules.new()
  local _, changed, grant = claim(data, 11, "a", 100)
  t.truthy(changed)
  t.eq(grant.to, 11)
  t.eq(grant.id, "a")
end)

t.test("a paid jackpot is recorded, and resets the pool only if it was never claimed", function()
  local data = rules.new()
  feed(data, { { kind = "pot", amount = 900 } })
  claim(data, 7, "a", 1900)
  feed(data, { { kind = "pot", amount = 50 } })
  feed(data, { { kind = "jackpot", game = "slots", player = "Ann", amount = 1900, claim = "a" } })
  t.eq(data.jackpot, 1050, "the claim already took it")
  t.eq(data.jackpotsPaid, 1900)
  t.truthy(data.latest[1].jackpot, "marked as a jackpot")
  feed(data, { { kind = "jackpot", game = "slots", player = "Bob", amount = 300 } })
  t.eq(data.jackpot, rules.SEED, "a table that never asked still empties it")
end)

t.test("old claims are forgotten, so a long-running hub stays small", function()
  local data = rules.new()
  for i = 1, rules.CLAIMS_KEPT + 10 do claim(data, 1, "c" .. i, 5) end
  t.eq(#data.claimOrder, rules.CLAIMS_KEPT)
  local count = 0
  for _ in pairs(data.claims) do count = count + 1 end
  t.eq(count, rules.CLAIMS_KEPT)
end)

t.test("tables are listed latest first, and go quiet", function()
  local data = rules.new()
  rules.apply(data, 3, round("slots", "Ann", 10, 1), 1000)
  rules.apply(data, 4, { kind = "exposure", amount = 50 }, 1000 + rules.QUIET_MS)
  local list = rules.tables(data, 1000 + rules.QUIET_MS + 10)
  t.eq(list[1].id, 4)
  t.eq(list[1].name, "Table", "known only by its exposure so far")
  t.truthy(list[1].live)
  t.eq(list[2].id, 3)
  t.eq(list[2].name, "Slots")
  t.eq(list[2].rounds, 1)
  t.truthy(not list[2].live, "not heard from for a minute")
end)

t.test("nonsense from the network changes nothing", function()
  local data = rules.new()
  local bad = {
    "text", {}, { kind = "nope" }, { kind = "round" }, { kind = "round", game = "x", player = "y", wagered = -1, net = 0 },
    { kind = "round", game = "x", player = "", wagered = 1, net = 0 },
    { kind = "round", game = "x", player = "y", wagered = 1, net = 0 / 0 },
    { kind = "round", game = "x", player = "y", wagered = 1 / 0, net = 0 },
    { kind = "pot", amount = -5 }, { kind = "pot", amount = "9" }, { kind = "pot", amount = 1 / 0 },
    { kind = "claim", amount = 5 }, { kind = "claim", id = "a", amount = -5 }, { kind = "claim", id = "a" },
    { kind = "jackpot", amount = 5 }, { kind = "exposure" },
  }
  for _, message in ipairs(bad) do
    local changed = rules.apply(data, 7, message, 1000)
    t.truthy(not changed, "ignored")
  end
  t.eq(data.jackpot, rules.SEED)
  t.eq(next(data.players), nil)
  t.eq(next(data.tables), nil)
end)

t.test("an old save loads, and anything missing or wrong starts fresh", function()
  local data = rules.restore({ jackpot = 1234, players = "broken" })
  t.eq(data.jackpot, 1234)
  t.eq(type(data.players), "table")
  t.eq(type(data.claims), "table")
  t.eq(rules.restore(nil).jackpot, rules.SEED)
end)

t.test("the state tables read has the jackpot and leaders", function()
  local data = rules.new()
  feed(data, { round("slots", "Ann", 10, 40) })
  local state = rules.state(data)
  t.eq(state.jackpot, rules.SEED)
  t.eq(state.leaders[1].name, "Ann")
  t.eq(state.leaders[1].net, 40)
end)

t.test("every game in the casino that states a target has one here", function()
  for _, id in ipairs({ "baccarat", "hilo", "horse-racing", "pokertable", "roulette", "slots", "three-card-poker",
    "ultimate-holdem", "videopoker" }) do
    t.truthy(rules.GAMES[id] and rules.GAMES[id].target, id)
    t.truthy(rules.GAMES[id].target > 0.9 and rules.GAMES[id].target <= 1, id)
  end
end)
