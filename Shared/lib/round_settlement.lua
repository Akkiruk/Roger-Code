local currency = require("lib.currency")
local alert = require("lib.alert")

local M = {}

local function notifyFailure(opts, message)
  alert.send(message)
  if opts and type(opts.logFailure) == "function" then
    opts.logFailure(message)
  else
    alert.log(message)
  end
end

function M.applyNetChange(netChange, opts)
  local options = opts or {}

  if netChange > 0 then
    local reason = options.winReason or options.reason or "round payout"
    local ok = currency.payout(netChange, reason)
    if not ok then
      notifyFailure(options, (options.failurePrefix or "CRITICAL") .. ": Failed to pay " .. tostring(netChange) .. " tokens")
      return false
    end
    return true
  end

  if netChange < 0 then
    local chargeAmount = -netChange
    local reason = options.lossReason or options.reason or "round loss"
    local ok = currency.charge(chargeAmount, reason)
    if not ok then
      notifyFailure(options, (options.failurePrefix or "CRITICAL") .. ": Failed to charge " .. tostring(chargeAmount) .. " tokens")
      return false
    end
    return true
  end

  return true
end

return M
