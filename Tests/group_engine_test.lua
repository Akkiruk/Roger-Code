-- group_engine_test.lua
-- The parts of the group engine that need no computer: the order money moves in, and what the link believes. Everything with real
-- rednet and real seats is in tools/casinotest/group.mjs in craftos-agent.

local kit = require("group_kit")
local testing = require("testing")
local dealer = require("lib.casino.group.dealer")
local link = require("lib.casino.group.link")
local eq, test, truthy = testing.eq, testing.test, testing.truthy

local plan = dealer.plan

local function everyone(...)
  local wanted = {}
  for _, name in ipairs({ ... }) do wanted[name] = true end
  return wanted
end

local function orderFor(orders, name)
  for _, order in ipairs(orders) do
    if order.name == name then return order end
  end
  return nil
end

test("losers are collected before any winner is paid", function()
  local orders = plan({ Ann = 60, Bea = -30, Cy = -30 }, {}, everyone("Ann", "Bea", "Cy"))
  eq(#orders, 2, "orders")
  eq(orderFor(orders, "Bea").amount, -30, "Bea")
  eq(orderFor(orders, "Cy").amount, -30, "Cy")
  eq(orderFor(orders, "Ann"), nil, "Ann waits")
end)

test("a winner is paid only what has come in", function()
  local orders = plan({ Ann = 60, Bea = -30 }, {}, everyone("Ann"))
  eq(#orders, 1, "orders")
  eq(orders[1].amount, 30, "what came in")
end)

test("nothing collected means nothing paid", function()
  eq(#plan({ Ann = 60, Bea = -30, Cy = -30 }, {}, everyone("Ann")), 0, "orders")
end)

test("an order not yet answered counts as paid, and a collection as not in yet", function()
  local moves = { t1 = { name = "Ann", amount = 40 } }
  local orders = plan({ Ann = 40, Bea = 40 }, moves, everyone("Ann", "Bea"))
  eq(orderFor(orders, "Ann"), nil, "one order at a time for a player")
  eq(orderFor(orders, "Bea").amount, 40, "the rest of what the host holds")
  eq(#plan({ Ann = 40, Bea = 40 }, { t1 = { name = "Ann", amount = 60 } }, everyone("Bea"))[1] and 1 or 0, 1, "twenty left")
  eq(plan({ Ann = 40, Bea = 40 }, { t1 = { name = "Ann", amount = 60 } }, everyone("Bea"))[1].amount, 20, "twenty left")
  eq(#plan({ Ann = 30, Bea = -30 }, { t1 = { name = "Bea", amount = -30 } }, everyone("Ann", "Bea")), 0, "an unanswered collection pays nobody")
end)

test("winners go biggest first, and share what there is", function()
  -- The book adds up to 70, which is what the host holds for players
  local orders = plan({ Ann = 30, Bea = 50, Cy = -10 }, {}, everyone("Ann", "Bea"))
  eq(orders[1].name, "Bea", "the biggest first")
  eq(orders[1].amount, 50, "all of Bea's")
  eq(orders[2].name, "Ann", "then Ann")
  eq(orders[2].amount, 20, "and what is left")
end)

test("pays hold back while a loser's seat may still answer", function()
  eq(#plan({ Ann = 30 }, {}, everyone("Ann"), true), 0, "held")
  eq(plan({ Ann = 30 }, {}, everyone("Ann"), false)[1].amount, 30, "released")
end)

test("nobody is asked for who is not wanted", function()
  eq(#plan({ Ann = 30, Bea = -30 }, {}, everyone("Cy")), 0, "orders")
end)

test("a house amount stands on its own, and never funds a players debt", function()
  local orders = plan({ ["Ann@house"] = 100, Bea = 50, Cy = -50 }, {}, everyone("Ann", "Bea"))
  eq(orderFor(orders, "Ann").amount, 100, "the house pays what it lost")
  eq(orderFor(orders, "Ann").key, "Ann@house", "and against the house's side of the book")
  eq(orderFor(orders, "Bea"), nil, "Cy has not paid, so Bea waits")
end)

test("a player's two sides of the book go one at a time, debt first", function()
  local orders = plan({ Ann = -20, ["Ann@house"] = 100 }, {}, everyone("Ann"))
  eq(#orders, 1, "orders")
  eq(orders[1].key, "Ann", "the debt")
end)

test("what the house owes waits for nobody else's money", function()
  local book = { ["Ann@house"] = 100, ["Bea@house"] = -100 }
  eq(orderFor(plan(book, {}, everyone("Ann", "Bea")), "Ann").amount, 100, "beside a collection going out")
  eq(orderFor(plan(book, { t1 = { name = "Bea@house", amount = -100 } }, everyone("Ann")), "Ann").amount, 100, "with one still out")
  eq(orderFor(plan(book, {}, everyone("Ann"), true), "Ann").amount, 100, "while a loser's seat may still answer")
  eq(orderFor(plan({ Bea = 50, Cy = -50, ["Dee@house"] = -5 }, {}, everyone("Bea", "Dee"), false), "Bea"), nil, "a pot is still short of Cy")
  eq(orderFor(plan({ Bea = 50, ["Dee@house"] = -5 }, {}, everyone("Bea", "Dee"), false), "Bea").amount, 50, "and a house debt does not hold a pot back")
end)

test("a loser nobody can reach holds up no winner", function()
  -- Carol has paid her 30 and Bea has not
  local book = { Ann = 60, Bea = -30 }
  eq(orderFor(plan(book, {}, everyone("Ann", "Bea")), "Ann"), nil, "while Bea is being asked, a winner waits so one payment is not two")
  eq(plan(book, {}, everyone("Ann"))[1].amount, 30, "and once she is not asked for, what came in goes out")
end)

test("whatever fails, a players table never takes the host below even", function()
  local rng = testing.fastRng(99)
  for _ = 1, 400 do
    local names = { "Ann", "Bea", "Cy", "Dee", "Eve" }
    local owed, net = {}, 0
    for i = 1, #names - 1 do
      local amount = rng:below(201) - 100
      if amount ~= 0 then owed[names[i]] = amount end
      net = net + amount
    end
    if net ~= 0 then owed[names[#names]] = -net end
    local held, moves, seq = 0, {}, 0
    local wanted = everyone(unpack(names))
    for _ = 1, 30 do
      for _, order in ipairs(plan(owed, moves, wanted, false)) do
        seq = seq + 1
        moves[seq] = { name = order.key, amount = order.amount }
      end
      -- Any order may be answered with all, part or nothing, or not at all yet
      for tag, move in pairs(moves) do
        local roll = rng:below(4)
        if roll > 0 then
          local moved = roll == 1 and 0 or (roll == 2 and move.amount or (move.amount > 0 and 1 or -1) * math.floor(math.abs(move.amount) / 2))
          moves[tag] = nil
          owed[move.name] = (owed[move.name] or 0) - moved
          if owed[move.name] == 0 then owed[move.name] = nil end
          held = held - moved
          truthy(held >= 0, "the host holds " .. held)
        end
      end
      local pending = 0
      for _, move in pairs(moves) do
        if move.amount > 0 then pending = pending + move.amount end
      end
      truthy(held - pending >= 0, "the host promised more than it holds")
    end
    testing.breathe()
  end
end)

-- ------------------------------------------------------------------ a seat's book, on a real disk

local MONEY_FILES = { "casino_owed.dat", "group_orders.dat", "casino_transactions.log" }

--- A clean disk and a stand-in for ccvault, for the seat's real order code. Only on a computer: plain Lua has no fs or textutils.
local function withVault(fn)
  if not rawget(_G, "fs") or not rawget(_G, "textutils") then return end
  local function wipe()
    for _, file in ipairs(MONEY_FILES) do
      for _, path in ipairs({ file, file .. ".bak", file .. ".tmp" }) do
        if fs.exists(path) then fs.delete(path) end
      end
    end
  end
  wipe()
  local saved = rawget(_G, "ccvault")
  local world = { ledger = {}, live = "Bob" }
  _G.ccvault = {
    isAvailable = function() return true end,
    getPlayerName = function() return world.live end,
    getHostName = function() return "Hosty" end,
    getPlayerBalance = function() return 100000 end,
    isAuthenticated = function() return true end,
    transfer = function(from, to, amount, reason)
      world.ledger[#world.ledger + 1] = { from = from, to = to, amount = amount, reason = reason }
      return { txId = "tx" .. #world.ledger }
    end,
    getTransactionHistory = function() return world.ledger end,
  }
  local ok, err = pcall(fn, world)
  _G.ccvault = saved
  wipe()
  if not ok then error(err, 0) end
end

--- What a crash at the transfer leaves: the order open, booked and noted, the move written, the ledger has it, and no audit line.
-- Then a long wait, with other players' orders going through this computer and the dealer asking again all the while.
local function doubt(amount, rounds)
  local journal = require("lib.casino.journal")
  local seat = require("lib.casino.group.seat")
  local answered, tag = nil, "Group 1.2 #aaaa.1"
  return function(world)
    world.ledger[1] = { from = amount < 0 and "player:Ann" or "host", to = amount < 0 and "host" or "player:Ann", amount = math.abs(amount), reason = tag }
    journal.save(seat.ORDER_FILE, { open = { [tag] = { name = "Ann", amount = amount, booked = true } }, done = {} })
    journal.book("Ann", amount, "order " .. tag)
    journal.beginMove("Ann", amount, tag)
    local orders = seat.orders(function(which, moved)
      if which == tag then answered = moved end
    end)
    orders:recover()
    for i = 1, rounds do
      orders:run("Group 1.2 #bbbb." .. i, "Bob", i % 2 == 0 and 10 or -10)
      orders:run(tag, "Ann", amount)
      testing.breathe()
    end
    eq(journal.owedTo("Ann"), amount, "her amount is in the book once, " .. rounds .. " orders on")
    world.live = "Ann"
    orders:recover("Ann")
    eq(answered, amount, "the answer says it moved")
    eq(journal.owedTo("Ann"), 0, "and the book is clear")
    eq(#world.ledger, 1 + rounds, "nothing moved twice")
  end
end

test("an order in doubt is booked once, however many other orders go by", function()
  for _, rounds in ipairs({ 0, 19, 20, 45 }) do
    withVault(doubt(-100, rounds))
    withVault(doubt(100, rounds))
  end
end)

test("a crash right after booking is answered at boot, and books nothing twice", function()
  local journal = require("lib.casino.journal")
  local seat = require("lib.casino.group.seat")
  withVault(function(world)
    local tag = "Group 1.2 #cccc.1"
    journal.save(seat.ORDER_FILE, { open = { [tag] = { name = "Bob", amount = -40 } }, done = {} })
    journal.book("Bob", -40, "order " .. tag)
    local answered
    seat.orders(function(_, moved) answered = moved end):recover()
    eq(answered, 0, "no transfer was written, so nothing moved")
    eq(journal.owedTo("Bob"), 0, "and the seat's book is clear")
    eq(#world.ledger, 0, "no transfer")
  end)
end)

test("the ledger answers a trace with what really moved, parts and all, and moves nothing", function()
  local seat = require("lib.casino.group.seat")
  withVault(function(world)
    local tag = "Group 1.2 #dddd.1"
    local answers = {}
    local orders = seat.orders(function(which, moved) answers[which] = moved end)
    orders:trace(tag, "Ann", -100, os.epoch("utc"))
    eq(answers[tag], nil, "the wrong player's touch cannot read her ledger, so it stays open")
    world.live = "Ann"
    orders:trace(tag, "Ann", -100, os.epoch("utc"))
    eq(answers[tag], 0, "nothing under the tag")
    world.ledger[1] = { amount = 60, reason = tag }
    world.ledger[2] = { amount = 15, reason = tag .. "/2" }
    world.ledger[3] = { amount = 5, reason = tag .. "/3", rejectionReason = "no" }
    world.ledger[4] = { amount = 7, reason = tag .. "x" }
    orders:trace(tag, "Ann", -100, os.epoch("utc"))
    eq(answers[tag], -75, "what went, not what was asked for")
    orders:trace(tag, "Ann", 70, os.epoch("utc"))
    eq(answers[tag], 70, "never more than the order")
    eq(#world.ledger, 4, "no transfer")
    world.ledger = {}
    _G.ccvault.getTransactionHistory = nil
    orders:trace(tag, "Ann", -100, os.epoch("utc"))
    eq(answers[tag], -100, "with no ledger a charge counts as taken")
    orders:trace(tag, "Ann", 100, os.epoch("utc"))
    eq(answers[tag], 0, "and a payment as not made")
  end)
end)

test("a credit and a debt cancel in one write of the book", function()
  local journal = require("lib.casino.journal")
  withVault(function()
    journal.addOwed("Ann", -100)
    journal.addOwed("Ann@house", 60)
    eq(journal.offset("Ann", "Ann@house"), 60, "as far as they can")
    eq(journal.owedTo("Ann"), -40, "what is left of the debt")
    eq(journal.owedTo("Ann@house"), 0, "the credit is gone")
    eq(journal.offset("Ann", "Ann@house"), 0, "one side alone does nothing")
    journal.addOwed("Bea", 10)
    journal.addOwed("Bea@house", 5)
    eq(journal.offset("Bea", "Bea@house"), 0, "nor do two the same way")
  end)
end)

test("the link believes only what has the right shape", function()
  truthy(link.valid({ kind = "input", seq = 1, who = "Ann", id = "fold" }), "a press")
  truthy(link.valid({ kind = "input", seq = 1, who = "Ann" }), "a touch with no button")
  truthy(link.valid({ kind = "order", seq = 1, tag = "t", name = "Ann", amount = -30 }), "an order")
  truthy(link.valid({ kind = "answer", seq = 1, tag = "t", moved = 0 }), "an answer of nothing")
  truthy(link.valid({ kind = "view", seq = 1, screen = { n = 1, kind = "panel", buttons = {} } }), "a screen")
  truthy(link.valid({ kind = "trace", seq = 1, tag = "t", name = "Ann", amount = -30, at = 5 }), "a trace")
  truthy(link.valid({ kind = "here", seq = 1, host = "Hosty", cabinet = "bigtable" }), "an answer with its cabinet")
  truthy(link.valid({ kind = "join", seq = 1, host = "Hosty", cabinet = "bigtable" }), "a join with its cabinet")
  eq(link.valid({ kind = "trace", seq = 1, tag = "t", name = "Ann", amount = 0, at = 5 }), false, "a trace of nothing")
  eq(link.valid({ kind = "trace", seq = 1, tag = "t", name = "Ann", amount = 5 }), false, "a trace with no time")
  eq(link.valid({ kind = "join", seq = 1, host = "Hosty", cabinet = {} }), false, "a join with a junk cabinet")
  for _, junk in ipairs({
    "text", 42, true, {}, { kind = "input" }, { kind = "nothing", seq = 1 }, { kind = "input", seq = 0 / 0, who = "Ann" },
    { kind = "input", seq = 1, who = ("x"):rep(99) }, { kind = "input", seq = 1, who = "Ann@house" }, { kind = "input", seq = 1, who = "Ann", id = {} },
    { kind = "input", seq = 1, who = "Ann", value = {} }, { kind = "order", seq = 1, tag = "t", name = "Ann", amount = 1 / 0 },
    { kind = "order", seq = 1, tag = "t", name = "Ann", amount = 1.5 }, { kind = "order", seq = 1, tag = "t", name = "Ann", amount = 0 },
    { kind = "order", seq = 1, tag = "t", name = "Ann", amount = 1e12 }, { kind = "order", seq = 1, tag = ("t"):rep(99), name = "Ann", amount = 5 },
    { kind = "answer", seq = 1, tag = "t", moved = "lots" }, { kind = "view", seq = 1, screen = "no" }, { kind = "view", seq = 1, screen = { n = 1, kind = "panel" } },
    { kind = "welcome", seq = 1, number = -1 }, { kind = "welcome", seq = 1, number = 1.5 }, { kind = "toast", seq = 1, text = ("x"):rep(999) },
  }) do
    eq(link.valid(junk), false, "junk")
  end
end)

test("a link hears a message once, and only one that is newer", function()
  local wire = link.new()
  truthy(wire:hear(5, { kind = "beat", seq = 10 }, link.PROTOCOL), "first")
  eq(wire:hear(5, { kind = "beat", seq = 10 }, link.PROTOCOL), false, "the same again")
  eq(wire:hear(5, { kind = "beat", seq = 9 }, link.PROTOCOL), false, "an older one")
  truthy(wire:hear(6, { kind = "beat", seq = 1 }, link.PROTOCOL), "another computer has its own count")
  eq(wire:hear(5, { kind = "beat", seq = 20 }, "other"), false, "another protocol")
  eq(#wire:drain(), 2, "heard")
  eq(#wire:drain(), 0, "drained")
end)

test("a flood cannot grow the inbox without limit", function()
  local wire = link.new()
  for i = 1, 1000 do wire:hear(7, { kind = "beat", seq = i }, link.PROTOCOL) end
  truthy(#wire:drain() <= 256, "the inbox has a limit")
end)

test("the test plugins keep the contract", function()
  kit.fuzz(require("group_plugins.highcard"), { rounds = 150, seats = { 2, 3, 8 }, stack = 100, absent = 20 })
  kit.fuzz(require("group_plugins.onebet"), { rounds = 150, seats = { 1, 4, 8 }, bet = 25, absent = 20 })
end)

test("the kit can fail: nets that do not add up are caught", function()
  local base = require("group_plugins.highcard")
  local rules = {}
  for key, value in pairs(base.rules) do rules[key] = value end
  function rules.nets(state)
    local nets = base.rules.nets(state)
    nets[state.players[1].seat] = nets[state.players[1].seat] + 1
    return nets
  end
  local broken = {}
  for key, value in pairs(base) do broken[key] = value end
  broken.rules = rules
  eq(pcall(kit.fuzz, broken, { rounds = 3, seats = { 2 }, stack = 100 }), false, "fuzz")
end)
