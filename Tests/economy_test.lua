-- economy_test.lua
-- economy.call on a call that waits as vhcctweaks 2.2.36's economy thread does: nothing that arrives in the wait is lost to the
-- caller, a terminate cannot cut the call short, and the call's own answer comes back as pcall's would.

local t = require("testing")
local economy = require("lib.casino.economy")

local unpack = table.unpack or unpack

--- Run body as a computer would, handing it the scripted events one by one whenever it yields.
local function drive(body, script)
  local co = coroutine.create(body)
  local ok, err = coroutine.resume(co)
  local i = 0
  while coroutine.status(co) ~= "dead" do
    assert(ok, err)
    i = i + 1
    local event = script[i]
    if not event then error("the script ran out after " .. (i - 1) .. " events", 2) end
    ok, err = coroutine.resume(co, unpack(event))
  end
  assert(ok, err)
  return i
end

--- A money call that does its work at once, then waits for its ticket, as the mod's does.
local function slowTransfer(log, ticket)
  return function(amount, reason)
    log[#log + 1] = reason .. " " .. amount
    while true do
      local event, id = coroutine.yield("vhcc_economy_done")
      if event == "terminate" then error("Terminated", 0) end
      if event == "vhcc_economy_done" and id == ticket then break end
    end
    return { txId = reason }
  end
end

t.test("economy: events in the wait reach the caller afterwards, in order", function()
  local seen, result = {}, nil
  local log = {}
  drive(function()
    local ok, value = economy.call(slowTransfer(log, 7), 100, "pay")
    result = ok and value.txId
    for _ = 1, 3 do
      local event, a = os.pullEventRaw()
      seen[#seen + 1] = event .. ":" .. tostring(a)
    end
  end, {
    { "char", "a" },
    { "vhcc_economy_done", 6 },     -- someone else's ticket
    { "timer", 990012 },
    { "vhcc_economy_done", 7 },
    { "rednet_message", 4 },
  })
  t.eq(result, "pay", "the call's answer")
  t.eq(table.concat(log, ","), "pay 100", "the work happened once")
  t.eq(table.concat(seen, ","), "char:a,timer:990012,rednet_message:4", "nothing lost, nothing doubled")
end)

t.test("economy: a terminate in the wait lands after the call has answered", function()
  local result, after = nil, nil
  drive(function()
    local ok, value = economy.call(slowTransfer({}, 1), 5, "charge")
    result = ok and value.txId
    after = os.pullEventRaw()
  end, {
    { "terminate" },
    { "vhcc_economy_done", 1 },
  })
  t.eq(result, "charge", "the call finished")
  t.eq(after, "terminate", "the terminate came next")
end)

t.test("economy: an error comes back as pcall's would, at once or after a wait", function()
  local ok, err = economy.call(function() error("Amount exceeds maximum (500)", 0) end)
  t.eq(ok, false, "refused at once")
  t.eq(err, "Amount exceeds maximum (500)", "its reason")
  local ok2, value = economy.call(function(a, b) return a + b, "two" end, 2, 3)
  t.eq(ok2, true, "a quick call")
  t.eq(value, 5, "its answer")
  local late
  drive(function()
    late = { economy.call(function()
      coroutine.yield("vhcc_economy_done")
      return nil, "internal error"
    end) }
  end, { { "vhcc_economy_done", 1 } })
  t.eq(late[1], true, "a waited call that answers nil")
  t.eq(late[3], "internal error", "keeps its message")
  local missing = { economy.call(nil) }
  t.eq(missing[2], "ccvault function missing", "a missing function")
end)

t.test("economy: a filter that would have dropped a held event still drops it", function()
  local got
  drive(function()
    economy.call(slowTransfer({}, 2), 1, "x")
    got = { os.pullEventRaw("timer") }
  end, {
    { "char", "a" },
    { "timer", 990003 },
    { "vhcc_economy_done", 2 },
  })
  t.eq(got[1], "timer", "the timer")
  t.eq(got[2], 990003, "its id")
end)
