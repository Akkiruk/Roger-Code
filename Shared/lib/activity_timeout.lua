local ceil = math.ceil
local max = math.max

local M = {}
local State = {}

local function nowMs()
  return os.epoch("local")
end

function M.resolveDuration(...)
  local values = { ... }
  for index = 1, #values do
    local value = tonumber(values[index])
    if value and value > 0 then
      return math.floor(value)
    end
  end
  return nil
end

function M.create(durationMs, opts)
  local options = opts or {}
  local resolvedDuration = M.resolveDuration(durationMs, options.fallbackDuration)
  if not resolvedDuration then
    return nil
  end

  local warningMs = M.resolveDuration(options.warningMs, math.min(10000, resolvedDuration))
  local state = {
    durationMs = resolvedDuration,
    warningMs = warningMs,
    lastActivityMs = tonumber(options.lastActivityTime) or nowMs(),
    pollSeconds = tonumber(options.pollSeconds) or 0.25,
  }

  return setmetatable(state, { __index = State })
end

function State:touch(timestamp)
  self.lastActivityMs = tonumber(timestamp) or nowMs()
  return self.lastActivityMs
end

function State:elapsed(timestamp)
  return max(0, (tonumber(timestamp) or nowMs()) - self.lastActivityMs)
end

function State:remaining(timestamp)
  return max(0, self.durationMs - self:elapsed(timestamp))
end

function State:isExpired(timestamp)
  return self:elapsed(timestamp) > self.durationMs
end

function State:isWarning(timestamp)
  return self.warningMs and self:remaining(timestamp) <= self.warningMs or false
end

function State:secondsLeft(timestamp)
  return max(1, ceil(self:remaining(timestamp) / 1000))
end

return M