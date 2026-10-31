-- limits.lua
-- Table limits. Pure: give it the host's balance and it says what the table can cover.

local M = {}

M.RESERVE = 2000          -- the host's balance below this is never put at risk
M.LIABILITY_SHARE = 0.5   -- one round's biggest win may take this share of what is left

--- What the host can put at risk after the reserve and what other tables have open.
function M.protected(hostBalance, otherExposure)
  return math.max(0, math.floor((hostBalance or 0) - M.RESERVE - (otherExposure or 0)))
end

--- The biggest bet a table can take.
-- @param maxWin number   biggest net win as a multiple of the bet
-- @param capTokens number|nil  a table's own limit in tokens
function M.maxBet(hostBalance, otherExposure, maxWin, capTokens)
  local protected = M.protected(hostBalance, otherExposure)
  local bet = math.floor(protected * M.LIABILITY_SHARE / math.max(1, maxWin))
  if capTokens then bet = math.min(bet, capTokens) end
  return math.max(0, bet)
end

--- Whether the host can cover a net win right now.
function M.covers(hostBalance, otherExposure, amount)
  return amount <= M.protected(hostBalance, otherExposure)
end

--- Chip values for a table limit: a tidy ladder that always ends at something useful.
function M.chips(maxBet)
  local ladder = { 1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000 }
  local chips = {}
  for _, value in ipairs(ladder) do
    if value <= maxBet then chips[#chips + 1] = value end
  end
  while #chips > 6 do table.remove(chips, 1) end
  return chips
end

return M
