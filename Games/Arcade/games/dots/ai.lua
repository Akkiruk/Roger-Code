-- games/dots/ai.lua
-- The computer player for Dots and Boxes. Easy misses boxes and gives them away. Medium takes every box and gives away as
-- few as it can. Hard also knows the game's real trick: at the end of a long chain it can leave the last two boxes
-- unclaimed, so its opponent has to take them and then open the next chain.

local rules = require("games.dots.rules")
local search = require("games.search")

local M = {}

local SIZE = rules.SIZE
local YIELD_EVERY = 12

local function completes(s, a)
  for _, box in ipairs(rules.neighbours(a)) do
    if rules.sides(s, box[1], box[2]) == 3 then return true end
  end
  return false
end

--- Would this line leave a third side on a box, handing it to the other player?
local function gives(s, a)
  for _, box in ipairs(rules.neighbours(a)) do
    if rules.sides(s, box[1], box[2]) == 2 then return true end
  end
  return false
end

local function pick(list) return list[math.random(#list)] end

local function capturing(s)
  local out = {}
  for _, a in ipairs(rules.legalActions(s)) do
    if completes(s, a) then out[#out + 1] = a end
  end
  return out
end

local function safe(s)
  local out = {}
  for _, a in ipairs(rules.legalActions(s)) do
    if not completes(s, a) and not gives(s, a) then out[#out + 1] = a end
  end
  return out
end

--- Take every box on offer. Returns the changed copy and how many were taken.
local function takeAll(s)
  local c, taken = search.clone(s), 0
  local list = capturing(c)
  while #list > 0 and c.winner == 0 do
    local before = c.score[c.turn]
    local seat = c.turn
    rules.step(c, list[1])
    taken = taken + c.score[seat] - before
    list = capturing(c)
  end
  return c, taken
end

--- How many boxes the opponent collects after this line is drawn.
local function cost(s, a)
  local c = search.clone(s)
  rules.step(c, a)
  local _, taken = takeAll(c)
  return taken
end

--- The line that gives the least away.
local function cheapest(s, opts)
  local best, bestCost = {}, math.huge
  for i, a in ipairs(rules.legalActions(s)) do
    if opts.yield and i % YIELD_EVERY == 0 then opts.yield() end
    local n = cost(s, a)
    if n < bestCost then best, bestCost = { a }, n elseif n == bestCost then best[#best + 1] = a end
  end
  return pick(best), bestCost
end

--- Sizes of what is left to open once no safe line remains, smallest first: each chain, as its opening costs.
local function chains(s, opts)
  local c, sizes = search.clone(s), {}
  while c.winner == 0 do
    local a, n = cheapest(c, opts)
    sizes[#sizes + 1] = n
    rules.step(c, a)
    local after = takeAll(c)
    if after.winner ~= 0 then break end
    c = after
  end
  return sizes
end

--- The line that leaves exactly two boxes for the opponent, both of them free and the turn theirs: a double-cross.
local function doubleCross(s)
  for _, a in ipairs(rules.legalActions(s)) do
    if not completes(s, a) then
      local c = search.clone(s)
      rules.step(c, a)
      local after, taken = takeAll(c)
      if taken == 2 and after.turn == c.turn and after.winner == 0 then return a end
    end
  end
  return nil
end

--- Is giving up two boxes now worth keeping control of what is left?
local function worthControl(after, opts)
  if #safe(after) > 0 or after.winner ~= 0 then return false end
  local total, long = 0, 0
  for _, n in ipairs(chains(after, opts)) do
    total = total + n
    if n >= 3 then long = long + 1 end
  end
  return long >= 1 and total - 4 * (long - 1) > 4
end

local function hard(s, opts)
  local take = capturing(s)
  if #take > 0 then
    local after, taken = takeAll(s)
    if taken == 2 and worthControl(after, opts) then
      local a = doubleCross(s)
      if a then return a end
    end
    return pick(take)
  end
  local free = safe(s)
  if #free > 0 then return pick(free) end
  return (cheapest(s, opts))
end

local function medium(s, opts)
  local take = capturing(s)
  if #take > 0 then return pick(take) end
  local free = safe(s)
  if #free > 0 then return pick(free) end
  return (cheapest(s, opts))
end

local function easy(s)
  local take = capturing(s)
  if #take > 0 and math.random() < 0.6 then return pick(take) end
  return pick(rules.legalActions(s))
end

function M.choose(s, level, opts)
  opts = opts or {}
  if level == "hard" then return hard(s, opts) end
  if level == "medium" then return medium(s, opts) end
  return easy(s)
end

return M
