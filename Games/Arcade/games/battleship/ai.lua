-- games/battleship/ai.lua
-- The computer player for Battleship. It is only ever given rules.viewFor's view, so it cannot see the enemy fleet.
-- Easy shoots at random. Medium does that until it hits, then works around the hit. Hard counts every way the ships still
-- afloat could lie, given what the shots have shown, and fires where the most of them overlap.

local rules = require("games.battleship.rules")

local M = {}

local SIZE, MISS, HIT, SUNK = rules.SIZE, rules.MISS, rules.HIT, rules.SUNK
local AROUND = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function pick(list) return list[math.random(#list)] end
local function target(x, y) return { kind = "fire", x = x, y = y } end

local function unfired(row)
  local out = {}
  for y = 1, SIZE do
    for x = 1, SIZE do
      if row[y][x] == 0 then out[#out + 1] = target(x, y) end
    end
  end
  return out
end

local function besideHits(row)
  local out = {}
  for y = 1, SIZE do
    for x = 1, SIZE do
      if row[y][x] == HIT then
        for _, d in ipairs(AROUND) do
          local nx, ny = x + d[1], y + d[2]
          if row[ny] and row[ny][nx] == 0 then out[#out + 1] = target(nx, ny) end
        end
      end
    end
  end
  return out
end

--- Add one possible position of a ship to the counts, if the shots so far allow it.
local function countShip(row, counts, len, x, y, dx, dy)
  local hits = 0
  for i = 0, len - 1 do
    local v = row[y + i * dy][x + i * dx]
    if v == MISS or v == SUNK then return end
    if v == HIT then hits = hits + 1 end
  end
  -- a position through a known hit is worth far more than one through open water
  local weight = 1 + hits * 30
  for i = 0, len - 1 do
    local cy, cx = y + i * dy, x + i * dx
    counts[cy][cx] = counts[cy][cx] + weight
  end
end

local function densest(state, row)
  local counts = {}
  for y = 1, SIZE do
    counts[y] = {}
    for x = 1, SIZE do counts[y][x] = 0 end
  end
  for _, n in ipairs(state.afloat) do
    local len = rules.SHIPS[n].len
    for y = 1, SIZE do
      for x = 1, SIZE - len + 1 do countShip(row, counts, len, x, y, 1, 0) end
    end
    for y = 1, SIZE - len + 1 do
      for x = 1, SIZE do countShip(row, counts, len, x, y, 0, 1) end
    end
  end
  local best, bestCount = {}, -1
  for y = 1, SIZE do
    for x = 1, SIZE do
      if row[y][x] == 0 then
        if counts[y][x] > bestCount then
          best, bestCount = { target(x, y) }, counts[y][x]
        elseif counts[y][x] == bestCount then
          best[#best + 1] = target(x, y)
        end
      end
    end
  end
  return best
end

function M.choose(state, level)
  if state.phase == "setup" then return { kind = "auto" } end
  local row = state.shots[state.turn]
  if level == "hard" then return pick(densest(state, row)) end
  if level == "medium" then
    local near = besideHits(row)
    if #near > 0 then return pick(near) end
  end
  return pick(unfired(row))
end

return M
