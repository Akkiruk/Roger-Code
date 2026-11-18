-- limits.lua
-- Table limits. Pure: give it the host's balance and it says what the table can cover.
--
-- The two house limits are owner settings. The defaults below are the only place their numbers live. The owner changes them
-- on the casino hub's wall (touch it, then HOUSE LIMITS): the hub puts them in every state it sends, net.lua hands them to
-- choose(), and every table and group table of that host uses them from then on. A table that has heard no hub since it
-- booted uses the defaults.

local M = {}

M.RESERVE = 500           -- default: the host's balance below this is never put at risk
M.LIABILITY_SHARE = 0.25  -- default: one round's biggest win may take this share of what is above the reserve

-- What the hub's owner menu offers, and the only values a table believes from the network
M.RESERVES = { 0, 500, 1000, 2000, 5000, 10000 }
M.SHARES = { 0.1, 0.25, 0.5, 0.75 }

local chosen = {}   -- host name -> { reserve, share }: what that host set on their hub

local function listed(list, value)
  for _, entry in ipairs(list) do
    if entry == value then return true end
  end
  return false
end

--- Whether a reserve and share are ones the hub offers.
function M.valid(reserve, share)
  return listed(M.RESERVES, reserve) and listed(M.SHARES, share)
end

--- A host's own limits, from their hub. Anything not on the lists is ignored.
function M.choose(host, reserve, share)
  if type(host) ~= "string" or host == "" or not M.valid(reserve, share) then return false end
  chosen[host] = { reserve = reserve, share = share }
  return true
end

--- Forget every host's choice (tests).
function M.reset()
  chosen = {}
end

--- The reserve and share a host's tables use now.
function M.current(host)
  local mine = host and chosen[host]
  if mine then return mine.reserve, mine.share end
  return M.RESERVE, M.LIABILITY_SHARE
end

function M.reserve(host)
  return (M.current(host))
end

function M.share(host)
  local _, share = M.current(host)
  return share
end

--- A share as the owner reads it: 0.25 is "25%".
function M.percent(share)
  return math.floor(share * 100 + 0.5) .. "%"
end

--- What the host can put at risk after the reserve and what other tables have open.
function M.protected(hostBalance, otherExposure, host)
  return math.max(0, math.floor((hostBalance or 0) - M.reserve(host) - (otherExposure or 0)))
end

--- The biggest net win one round may promise: the share of what is protected.
function M.room(hostBalance, otherExposure, host)
  return math.floor(M.protected(hostBalance, otherExposure, host) * M.share(host))
end

--- The biggest bet a table can take.
-- @param maxWin number   biggest net win as a multiple of the bet
-- @param capTokens number|nil  a table's own limit in tokens
-- @param host string|nil  whose limits: the defaults when nil or never chosen
function M.maxBet(hostBalance, otherExposure, maxWin, capTokens, host)
  local bet = math.floor(M.protected(hostBalance, otherExposure, host) * M.share(host) / math.max(1, maxWin))
  if capTokens then bet = math.min(bet, capTokens) end
  return math.max(0, bet)
end

--- What a player may bet now: the smaller of their balance and the table's own limit (the house's cover and any cap of the game's),
-- and which of the two it is, as a bet screen says it. A balance not read yet gives nil, so a screen says so instead of guessing.
-- @return max (nil while the balance is unknown), reason: "your balance" or "table limit"
function M.allowed(balance, tableMax)
  tableMax = math.max(0, math.floor(tableMax or 0))
  if balance == nil then return nil, "checking" end
  balance = math.max(0, math.floor(balance))
  if balance <= tableMax then return balance, "your balance" end
  return tableMax, "table limit"
end

--- Whether the host can cover a net win right now.
function M.covers(hostBalance, otherExposure, amount, host)
  return amount <= M.protected(hostBalance, otherExposure, host)
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
