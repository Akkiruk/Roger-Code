-- progress/wallet.lua
-- Money in the player's pocket (save.player.money). Every change goes through here and is announced on the bus with the
-- "money" event (amount signed, reason, total), so stats and the HUD hear all of it. Pure.

local M = {}

function M.balance(ctx)
  return ctx.save.player.money or 0
end

--- Pay the player (n > 0). Returns the new balance.
function M.add(ctx, n, reason)
  n = math.floor(n or 0)
  if n == 0 then return M.balance(ctx) end
  local p = ctx.save.player
  p.money = (p.money or 0) + n
  ctx.bus:emit("money", { amount = n, reason = reason or "", total = p.money })
  return p.money
end

--- Take n from the player if there is enough. Returns true and the new balance, or false.
function M.spend(ctx, n, reason)
  n = math.floor(n or 0)
  local have = M.balance(ctx)
  if n < 0 or have < n then return false, have end
  if n == 0 then return true, have end
  local p = ctx.save.player
  p.money = have - n
  ctx.bus:emit("money", { amount = -n, reason = reason or "", total = p.money })
  return true, p.money
end

function M.canAfford(ctx, n)
  return M.balance(ctx) >= n
end

return M
