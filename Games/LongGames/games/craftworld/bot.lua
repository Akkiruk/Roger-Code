-- games/craftworld/bot.lua
-- A player for the idle screen and the tests. It chops a tree, makes a table and a pickaxe, then digs a staircase down,
-- taking any ore it passes, lighting the way, making better tools as it goes, and fighting what comes at it. It plays
-- through the same actions a tap gives. What it remembers between moves is kept beside the state, not in it, one memory
-- for each player in the world.

local M = {}

local abs, max = math.abs, math.max

local memory = setmetatable({}, { __mode = "k" })

-- by player, so two bots in one world each keep their own
local function mem(s)
  local m = memory[s.p]
  if not m then
    m = { dir = 1, lastX = s.p.x, lastY = s.p.y, still = 0, torchAt = s.p.y, wander = 0 }
    memory[s.p] = m
  end
  return m
end

-- what to make, in order, each when it's wanted
local function wanted(R, s)
  local p, n = s.p, function(id) return R.count(s, id) end
  local list = {}
  local function want(id, cond)
    if cond then list[#list + 1] = id end
  end
  want("table", n("table") == 0 and not R.stationNear(s, "T") and n("planks") >= 4)
  want("stick", n("stick") < 3 and n("planks") >= 2)
  want("wood_pick", p.pick < 1)
  want("wood_sword", p.sword < 1 and p.pick >= 1)
  want("stone_pick", p.pick < 2)
  want("stone_sword", p.sword < 2 and p.pick >= 2)
  want("torch", n("torch") < 10)
  want("furnace", n("furnace") == 0 and not R.stationNear(s, "F") and n("iron_ore") + n("raw_meat") > 0)
  want("iron", true)
  want("cook", true)
  want("iron_pick", p.pick < 3)
  want("iron_sword", p.sword < 3 and p.pick >= 3)
  want("iron_armour", p.armour < 1 and p.pick >= 3)
  want("diamond_pick", p.pick < 4)
  want("diamond_sword", p.sword < 4 and p.pick >= 4)
  want("planks", n("log") > 0 and n("planks") < 12)
  return list
end

--- Everything a recipe needs, save the station it must be made at.
local function onlyStationMissing(R, s, r)
  if not r.at or R.stationNear(s, r.at) then return false end
  for _, need in ipairs(r.need) do
    if R.count(s, need[1]) < need[2] then return false end
  end
  return true
end

--- Put an item down in an empty cell beside the player.
local function putDown(R, s, item)
  local p = s.p
  local W = R.world
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 1, -1 }, { -1, -1 }, { 0, -1 } }) do
    local x, y = p.x + d[1], p.y + d[2]
    if W.tileAt(s, x, y) == W.AIR and not R.mobAt(s, x, y) then
      if R.held(s) ~= item then return { kind = "pick", item = item } end
      return { kind = "use", dx = d[1], dy = d[2] }
    end
  end
  return nil
end

local function craftStep(R, s)
  for _, id in ipairs(wanted(R, s)) do
    local r = R.RECIPE[id]
    if R.canMake(s, r) then return { kind = "craft", id = id } end
    if onlyStationMissing(R, s, r) then
      local item = r.at == "T" and "table" or "furnace"
      if R.count(s, item) > 0 then
        local a = putDown(R, s, item)
        if a then return a end
      elseif item == "table" and R.count(s, "planks") >= 4 then
        return { kind = "craft", id = "table" }
      end
    end
  end
  return nil
end

local function canDig(R, s, c)
  local def = R.world.BLOCKS[c]
  return def.hard ~= nil and (def.tier or 0) <= s.p.pick
end

--- A neighbour worth taking for itself: ore the pickaxe can break, a log, or leaves when there's nothing to eat.
local function treasure(R, s, hungry)
  local p, W = s.p, R.world
  for dy = -1, 1 do
    for dx = -1, 1 do
      local c = W.tileAt(s, p.x + dx, p.y + dy)
      if (W.BLOCKS[c].ore or c == "l" or (hungry and c == "f")) and canDig(R, s, c) then return dx, dy end
    end
  end
  return nil
end

--- The nearest log a player could stand beside, as a column; or a log just out of reach overhead, for a jump.
local function nearestLog(R, s)
  local p, W = s.p, R.world
  for dx = -1, 1 do
    if W.tileAt(s, p.x + dx, p.y - 2) == "l" then return nil, true end
  end
  for r = 2, 16 do
    for _, x in ipairs({ p.x - r, p.x + r }) do
      for y = p.y - 3, p.y + 2 do
        if W.tileAt(s, x, y) == "l" then return x end
      end
    end
  end
  return nil
end

--- Has anything changed for the better lately? Walking to and fro for ever is as stuck as standing still.
local function signature(R, s)
  local n = 0
  for _, v in pairs(s.p.inv) do n = n + v end
  return n * 1000 + s.p.y * 10 + s.p.pick
end

--- Go one way, digging what's in the way and climbing what can be climbed.
local function headTo(R, s, dir, m)
  local p, W = s.p, R.world
  local side, above = W.tileAt(s, p.x + dir, p.y), W.tileAt(s, p.x + dir, p.y - 1)
  if R.mobAt(s, p.x + dir, p.y) then return { kind = "use", dx = dir, dy = 0 } end
  if not W.BLOCKS[side].solid then return { kind = "walk", dir = dir } end
  if not W.BLOCKS[above].solid and not W.BLOCKS[W.tileAt(s, p.x, p.y - 1)].solid then return { kind = "walk", dir = dir } end
  if canDig(R, s, side) then return { kind = "use", dx = dir, dy = 0 } end
  if W.BLOCKS[above].solid and canDig(R, s, above) then return { kind = "use", dx = dir, dy = -1 } end
  m.dir = -dir
  return { kind = "jump" }
end

--- The staircase: down a step and along a step, until near the bottom, then along.
local function staircase(R, s, m)
  local p, W = s.p, R.world
  local dir = m.dir
  local ahead, under = W.tileAt(s, p.x + dir, p.y), W.tileAt(s, p.x + dir, p.y + 1)
  local deepEnough = p.y >= W.HEIGHT - 8
  if R.mobAt(s, p.x + dir, p.y) then return { kind = "use", dx = dir, dy = 0 } end
  if W.diggable(ahead) and ahead ~= "w" then
    if canDig(R, s, ahead) then return { kind = "use", dx = dir, dy = 0 } end
    m.dir = -dir
    return { kind = "walk", dir = -dir }
  end
  if not deepEnough and W.diggable(under) and under ~= "w" and canDig(R, s, under) and under ~= "B" then
    return { kind = "use", dx = dir, dy = 1 }
  end
  return headTo(R, s, dir, m)
end

function M.choose(R, s, rng)
  if s.over then return nil end
  if s.mode ~= "play" then return { kind = "close" } end
  local p, W = s.p, R.world
  if not R.supported(s) then return nil end
  local m = mem(s)
  -- stuck: the same place for a long time, digging or not
  if p.x == m.lastX and p.y == m.lastY then m.still = m.still + 1 else m.still = 0 end
  m.lastX, m.lastY = p.x, p.y
  local sig = signature(R, s)
  if sig ~= m.sig then m.sig, m.idle = sig, 0 else m.idle = (m.idle or 0) + 1 end
  if m.still > 30 or m.idle > 80 then
    m.still, m.idle, m.dir, m.wander = 0, 0, -m.dir, 10
  end
  -- eat when hungry or hurt
  local hasFood = R.count(s, "cooked_meat") + R.count(s, "apple") + R.count(s, "raw_meat") + R.count(s, "golden_apple") > 0
  if hasFood and (p.food <= 12 or (p.hp <= 8 and p.food < R.MAX_FOOD)) then return { kind = "eat" } end
  -- fight what's next to it, and take meat from animals that wander close
  for dy = -1, 1 do
    for dx = -1, 1 do
      local mob = R.mobAt(s, p.x + dx, p.y + dy)
      if mob and (R.MOBS[mob.k].hostile or p.food < 18) then return { kind = "use", dx = dx, dy = dy } end
    end
  end
  local a = craftStep(R, s)
  if a then return a end
  if R.held(s) and R.held(s) ~= "torch" then return { kind = "select", slot = 0 } end
  -- light the way down
  local under = p.y > W.skyTop(s, p.x) + 2
  if under and R.count(s, "torch") > 0 and abs(p.y - m.torchAt) + abs(p.x - (m.torchX or p.x)) >= 7 then
    for _, d in ipairs({ { -m.dir, 0 }, { 0, -1 }, { -m.dir, -1 }, { m.dir, -1 } }) do
      local x, y = p.x + d[1], p.y + d[2]
      if W.tileAt(s, x, y) == W.AIR and not R.mobAt(s, x, y) then
        if R.held(s) ~= "torch" then return { kind = "pick", item = "torch" } end
        m.torchAt, m.torchX = p.y, p.x
        return { kind = "use", dx = d[1], dy = d[2] }
      end
    end
    m.torchAt, m.torchX = p.y, p.x
  end
  if R.held(s) then return { kind = "select", slot = 0 } end
  local tx, ty = treasure(R, s, not hasFood and p.food < 16)
  if tx then return { kind = "use", dx = tx, dy = ty } end
  if W.tileAt(s, p.x, p.y) == W.WATER then return { kind = "jump" } end
  if m.wander > 0 then
    m.wander = m.wander - 1
    return headTo(R, s, m.dir, m)
  end
  -- wood first
  if p.pick < 1 or (R.count(s, "planks") + R.count(s, "log") * 4 < 3 and p.sword < 1 and p.y < W.skyTop(s, p.x) + 2) then
    local logX, overhead = nearestLog(R, s)
    if overhead and not p.hang then return { kind = "jump" } end
    if logX then return headTo(R, s, logX > p.x and 1 or -1, m) end
    if p.pick < 1 then return headTo(R, s, m.dir, m) end
  end
  return staircase(R, s, m)
end

return M
