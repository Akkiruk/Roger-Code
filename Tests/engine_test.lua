-- engine_test.lua
-- The pure parts of the casino engine.

local deck = require("lib.casino.deck")
local limits = require("lib.casino.limits")
local net = require("lib.casino.net")
local rng = require("lib.casino.rng")
local t = require("testing")

t.test("sha256 matches the published vectors", function()
  t.eq(rng.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  t.eq(rng.sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  t.eq(rng.sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
end)

t.test("the bit32 stand-in agrees with bit32", function()
  local shim = require("lib.casino.bit32_shim")
  local real = rawget(_G, "bit32")
  if not real then return end
  local values = { 0, 1, 255, 0x80000000, 0xFFFFFFFF, 0xDEADBEEF, 0x12345678 }
  for _, a in ipairs(values) do
    t.eq(shim.bnot(a), real.bnot(a), "bnot")
    for _, b in ipairs(values) do
      t.eq(shim.band(a, b), real.band(a, b), "band")
      t.eq(shim.bor(a, b), real.bor(a, b), "bor")
      t.eq(shim.bxor(a, b), real.bxor(a, b), "bxor")
    end
    for _, n in ipairs({ 1, 7, 16, 25, 31 }) do
      t.eq(shim.rshift(a, n), real.rshift(a, n), "rshift")
      t.eq(shim.lshift(a, n), real.lshift(a, n), "lshift")
      t.eq(shim.rrotate(a, n), real.rrotate(a, n), "rrotate")
    end
  end
end)

t.test("chacha20 keystream matches RFC 7539 block with a zero key", function()
  local stream = rng.new(string.rep("0", 64))
  -- RFC 7539 appendix A.1 test vector 1, little-endian words
  t.eq(stream:u32(), 0xade0b876)
  t.eq(stream:u32(), 0x903df1a0)
  t.eq(stream:u32(), 0xe56a5d40)
end)

t.test("a generator restored mid-stream carries on identically", function()
  local a = rng.new(string.rep("ab", 32))
  for _ = 1, 37 do a:u32() end
  local b = rng.restore(a:serial())
  for _ = 1, 40 do t.eq(a:u32(), b:u32(), "next word") end
end)

t.test("below stays in range and is even", function()
  local stream = rng.new(string.rep("cd", 32))
  local counts = {}
  for _ = 1, 6000 do
    local v = stream:below(6)
    counts[v] = (counts[v] or 0) + 1
  end
  for v = 0, 5 do t.near(counts[v], 1000, 120, "count of " .. v) end
end)

t.test("a shuffle keeps every card", function()
  local cards = deck.shuffle(deck.fresh(2), rng.new(string.rep("11", 32)))
  local seen = {}
  for _, card in ipairs(cards) do seen[card] = (seen[card] or 0) + 1 end
  for card = 0, 51 do t.eq(seen[card], 2, "copies of " .. card) end
end)

t.test("cards name and parse", function()
  t.eq(deck.name(deck.card(14, deck.SPADES)), "AS")
  t.eq(deck.parse("10D"), deck.card(10, deck.DIAMONDS))
  t.eq(deck.rank(deck.parse("QH")), 12)
  t.truthy(deck.isRed(deck.parse("2H")))
end)

t.test("exposure must be a believable amount for a named host", function()
  t.truthy(net.validExposure({ host = "Host", amount = 500 }))
  t.truthy(net.validExposure({ host = "Host", amount = 0 }))
  for _, amount in ipairs({ -1, -1e12, 1e12, 0 / 0, math.huge, -math.huge, "500" }) do
    t.truthy(not net.validExposure({ host = "Host", amount = amount }), tostring(amount))
  end
  t.truthy(not net.validExposure({ amount = 500 }), "no host")
end)

t.test("a hub's state is believed whole or not at all", function()
  local leader = { name = "Ann", net = -40 }
  t.truthy(net.validState({ jackpot = 1000, leaders = {} }))
  t.truthy(net.validState({ jackpot = 1000, leaders = { leader, { name = "Bob", net = 12, best = 5, rounds = 2 } } }))
  for _, message in ipairs({
    { leaders = {} },
    { jackpot = 1000 },
    { jackpot = 1000, leaders = 5 },
    { jackpot = 1000, leaders = "Ann" },
    { jackpot = 1e12, leaders = {} },
    { jackpot = -1, leaders = {} },
    { jackpot = 0 / 0, leaders = {} },
    { jackpot = 1000, leaders = { leader, 5 } },
    { jackpot = 1000, leaders = { { net = 1 } } },
    { jackpot = 1000, leaders = { { name = 7, net = 1 } } },
    { jackpot = 1000, leaders = { { name = "Ann" } } },
    { jackpot = 1000, leaders = { { name = "Ann", net = 0 / 0 } } },
    { jackpot = 1000, leaders = { one = leader } },
    { jackpot = 1000, leaders = { { name = ("x"):rep(100), net = 1 } } },
  }) do
    t.truthy(not net.validState(message))
  end
end)

t.test("a grant needs an id and a believable amount", function()
  t.truthy(net.validGrant({ id = "a", amount = 1000 }))
  t.truthy(net.validGrant({ id = 7, amount = 0 }))
  t.truthy(not net.validGrant({ amount = 1000 }), "no id")
  t.truthy(not net.validGrant({ id = {}, amount = 1000 }), "a table for an id")
  t.truthy(not net.validGrant({ id = "a", amount = -1 }), "negative")
  t.truthy(not net.validGrant({ id = "a", amount = 1e12 }), "absurd")
end)

t.test("limits keep the reserve and split the risk", function()
  t.eq(limits.protected(2500, 0), 500)
  t.eq(limits.protected(1000, 0), 0)
  t.eq(limits.protected(10000, 3000), 5000)
  t.eq(limits.maxBet(102000, 0, 49), 1020)
  t.eq(limits.maxBet(102000, 0, 49, 100), 100)
  t.eq(limits.maxBet(1000, 0, 1), 0)
end)
