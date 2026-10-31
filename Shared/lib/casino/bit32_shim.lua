-- bit32_shim.lua
-- The bit32 functions rng.lua needs, for plain Lua 5.1 in CI. CC:Tweaked has bit32 and never loads this.

local M = {}

local MOD = 4294967296

local function bitwise(a, b, rule)
  local result, place = 0, 1
  a, b = a % MOD, b % MOD
  for _ = 1, 32 do
    local x, y = a % 2, b % 2
    if rule(x, y) then result = result + place end
    a, b, place = (a - x) / 2, (b - y) / 2, place * 2
  end
  return result
end

local function fold(rule, first, ...)
  local result = first
  for _, value in ipairs({ ... }) do
    result = bitwise(result, value, rule)
  end
  return result
end

function M.band(...) return fold(function(x, y) return x == 1 and y == 1 end, ...) end
function M.bor(...) return fold(function(x, y) return x == 1 or y == 1 end, ...) end
function M.bxor(...) return fold(function(x, y) return x ~= y end, ...) end
function M.bnot(a) return MOD - 1 - (a % MOD) end
function M.lshift(a, n) return (a * 2 ^ n) % MOD end
function M.rshift(a, n) return math.floor((a % MOD) / 2 ^ n) end

function M.rrotate(a, n)
  a = a % MOD
  return (M.rshift(a, n) + M.lshift(a, 32 - n)) % MOD
end

return M
