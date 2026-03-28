local M = {}

local function cloneValue(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, nested in pairs(value) do
    copy[key] = cloneValue(nested)
  end
  return copy
end

function M.new(initial)
  return cloneValue(initial or {})
end

function M.increment(stats, field, amount)
  amount = amount or 1
  stats[field] = (stats[field] or 0) + amount
  return stats[field]
end

function M.add(stats, field, amount)
  return M.increment(stats, field, amount)
end

function M.setMax(stats, field, candidate)
  if candidate and candidate > (stats[field] or 0) then
    stats[field] = candidate
  end
  return stats[field]
end

function M.bumpMap(stats, field, key, amount)
  local bucket = stats[field]
  if type(bucket) ~= "table" then
    bucket = {}
    stats[field] = bucket
  end

  bucket[key] = (bucket[key] or 0) + (amount or 1)
  return bucket[key]
end

function M.recordNet(stats, betAmount, netChange)
  M.increment(stats, "totalBet", betAmount or 0)
  M.increment(stats, "netProfit", netChange or 0)

  if (netChange or 0) > 0 then
    M.increment(stats, "totalWon", netChange)
    M.setMax(stats, "biggestWin", netChange)
  end
end

return M
