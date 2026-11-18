-- testing.lua
-- The small test kit for Tests/*_test.lua.

local M = { passed = 0, failed = 0 }

--- Yield now and then under CC, whose computers stop programs that never yield (after about 7 seconds). A yield costs a whole
-- round trip through the event queue, so it only happens once half a second has passed since the last one: tests call this every
-- few steps, and yielding each time made a long fuzz spend most of its time waiting on the queue.
local BREATHE_MS = 500
local lastBreath = nil

function M.breathe()
  if rawget(_G, "os") and os.queueEvent and os.pullEvent then
    local time = os.epoch and os.epoch("utc") or nil
    if time and lastBreath and time - lastBreath < BREATHE_MS then return end
    os.queueEvent("breathe")
    os.pullEvent("breathe")
    lastBreath = os.epoch("utc")
  end
end

function M.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    M.passed = M.passed + 1
    print("ok   " .. name)
  else
    M.failed = M.failed + 1
    print("FAIL " .. name .. "\n     " .. tostring(err))
  end
end

function M.eq(actual, expected, what)
  if actual ~= expected then
    error((what or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

function M.near(actual, expected, tolerance, what)
  if math.abs(actual - expected) > tolerance then
    error((what or "value") .. ": expected about " .. expected .. ", got " .. actual, 2)
  end
end

function M.truthy(value, what)
  if not value then error((what or "value") .. " should be true", 2) end
end

--- A fast generator for simulations, with the same below(n) the real one has.
function M.fastRng(seed)
  local state = (seed or 12345) % 2147483647
  if state <= 0 then state = 1 end
  local rng = {}
  function rng.below(_, n)
    -- Two steps of Park-Miller give enough bits for any n a game uses
    state = (state * 48271) % 2147483647
    local high = state
    state = (state * 48271) % 2147483647
    return ((high % 32768) * 32768 + (state % 32768)) % n
  end
  return rng
end

--- Play rounds with a strategy and report return per token staked.
-- play(state) names the action to take. Yields as it goes.
function M.simulate(rules, rounds, wager, play, seed, stakeOf)
  local rng = M.fastRng(seed)
  local keep, total, staked = {}, 0, 0
  for i = 1, rounds do
    local state = rules.new(wager, rng, keep, {})
    while not rules.done(state) do
      rules.act(state, play(state), rng)
    end
    total = total + rules.net(state)
    staked = staked + (stakeOf and stakeOf(wager) or wager)
    rules.finish(state, keep)
    M.breathe()
  end
  return (staked + total) / staked
end

function M.finish()
  print(("%d passed, %d failed"):format(M.passed, M.failed))
  return M.failed
end

return M
