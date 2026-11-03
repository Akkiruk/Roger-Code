-- economy.lua
-- How to make a ccvault call without losing events. On vhcctweaks 2.2.36, ccvault.transfer, getPlayerBalance, and getBalance of
-- anyone not online here run on the mod's economy thread: the call yields until vhcc_economy_done, every other event that arrives
-- meanwhile is lost to the caller, and a terminate in that wait errors the call after the money has already moved.
-- M.call runs the call in a coroutine of its own and feeds it only what it waits for. Everything else that arrives in the wait is
-- held for the caller, which gets it, in order, from its next os.pullEvent: a tap, its frame timer, a rednet reply. A terminate is
-- held as well, so it lands after the call has answered and the caller has written the answer down.
-- Other coroutines under parallel see every event as they always did, and nothing is queued twice.

local M = {}

local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end

-- One hold for the whole computer, kept on os so a program run again after this one does not wrap os.pullEventRaw twice
local shared = rawget(os, "rcEconomyHold")
if not shared then
  -- Plain Lua, for Tests/run.lua, has no pullEventRaw: the fallback is what CC's own bios defines
  local pullRaw = os.pullEventRaw or function(filter) return coroutine.yield(filter) end
  shared = { held = setmetatable({}, { __mode = "k" }), pull = pullRaw }
  os.rcEconomyHold = shared
  local held, pull = shared.held, shared.pull
  --- Events held for this coroutine come first. One its filter would not have taken is dropped, as it would have been.
  function os.pullEventRaw(filter)
    local co = coroutine.running() or shared
    local list = held[co]
    while list do
      local event = table.remove(list, 1)
      if #list == 0 then
        held[co] = nil
        list = nil
      end
      if event and (filter == nil or event[1] == filter or event[1] == "terminate") then
        return unpack(event, 1, event.n)
      end
    end
    return pull(filter)
  end
end

--- Call fn(...) as pcall does, but keep every event that arrives while it waits.
-- @return true and fn's results, or false and the error
function M.call(fn, ...)
  if type(fn) ~= "function" then return false, "ccvault function missing" end
  -- coroutine.resume catches an error as pcall would, so the call needs no pcall of its own to yield across
  local worker = coroutine.create(function(...)
    return fn(...)
  end)
  local step = pack(coroutine.resume(worker, ...))
  if coroutine.status(worker) ~= "dead" then
    local caller = coroutine.running() or shared
    local keep = shared.held[caller] or {}
    shared.held[caller] = nil
    repeat
      local filter = step[2]
      local event = pack(shared.pull())
      if event[1] ~= "terminate" and (filter == nil or event[1] == filter) then
        step = pack(coroutine.resume(worker, unpack(event, 1, event.n)))
      end
      if event[1] ~= "vhcc_economy_done" then keep[#keep + 1] = event end
    until coroutine.status(worker) == "dead"
    if #keep > 0 then shared.held[caller] = keep end
  end
  if not step[1] then return false, tostring(step[2]) end
  return unpack(step, 1, step.n)
end

return M
