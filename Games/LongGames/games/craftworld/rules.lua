-- games/craftworld/rules.lua
-- CRAFT WORLD: a side-on world of blocks, endless left and right and deep, for one player and a long time, and a friend
-- from the other wall now and then.
-- It works in steps, as Dungeon does: nothing in the world moves until a player does, and then everything takes one step
-- (mobs, hunger, the clock of the day). The one thing the clock does by itself is let a falling player fall, a block a tick.
-- The state is plain data, so it can be saved: the world is the seed and the players' changes to it (world.lua).

local world = require("games.craftworld.world")

local M = {}

local floor, max, min, abs, ceil = math.floor, math.max, math.min, math.abs, math.ceil
local tileAt, setTile, BLOCKS = world.tileAt, world.setTile, world.BLOCKS
local AIR, WATER = world.AIR, world.WATER

M.world = world

local MAX_HP, MAX_FOOD = 20, 20
local DAY = 480                       -- steps in a whole day
local DUSK, NIGHT, DAWN = 280, 320, 450 -- where each part of the day starts
local MONSTERS_FROM, MONSTERS_TO = 300, 450
local START_TIME = 30
local HUNGER_EVERY = 40               -- steps for each point of food used up
local REGEN_EVERY, REGEN_FOOD = 8, 16 -- a well-fed player heals a point this often
local STARVE_EVERY = 25               -- an empty belly hurts this often, but never past one heart
local SAFE_FALL = 3
local QUEUE_LONGEST = 2
local MSG_STEPS = 16
local HINT_STEPS = 14
local MAX_HOSTILE_NIGHT, MAX_HOSTILE_CAVE, MAX_ANIMALS = 6, 5, 4
local FAR_AWAY = 48                   -- mobs this far off are forgotten
local BED_SAFE = 8                    -- no sleeping with a monster this close

M.MAX_HP, M.MAX_FOOD, M.DAY = MAX_HP, MAX_FOOD, DAY

-- ---------------------------------------------------------------- items

-- place: the block it puts down. food: how much it fills. Order is the order the inventory shows them in.
local ITEMS = {
  { id = "dirt", name = "Dirt", place = "d" },
  { id = "cobble", name = "Cobblestone", place = "c" },
  { id = "sand", name = "Sand", place = "a" },
  { id = "log", name = "Log", place = "l" },
  { id = "planks", name = "Planks", place = "p" },
  { id = "glass", name = "Glass", place = "y" },
  { id = "torch", name = "Torch", place = "t" },
  { id = "table", name = "Crafting Table", place = "T" },
  { id = "furnace", name = "Furnace", place = "F" },
  { id = "door", name = "Door", place = "D" },
  { id = "bed", name = "Bed", place = "b" },
  { id = "apple", name = "Apple", food = 4 },
  { id = "raw_meat", name = "Raw Meat", food = 3 },
  { id = "cooked_meat", name = "Cooked Meat", food = 8 },
  { id = "golden_apple", name = "Golden Apple", food = 20 },
  { id = "stick", name = "Stick" },
  { id = "coal", name = "Coal" },
  { id = "iron_ore", name = "Iron Ore" },
  { id = "gold_ore", name = "Gold Ore" },
  { id = "iron", name = "Iron Ingot" },
  { id = "gold", name = "Gold Ingot" },
  { id = "diamond", name = "Diamond" },
  { id = "wool", name = "Wool" },
}
local ITEM = {}
for i, item in ipairs(ITEMS) do
  item.order = i
  ITEM[item.id] = item
end
M.ITEMS, M.ITEM = ITEMS, ITEM

local TIER_NAME = { [0] = "HAND", "WOODEN", "STONE", "IRON", "DIAMOND" }
local PICK_SPEED = { [0] = 1, 2, 3, 4, 6 }
local SWORD_HIT = { [0] = 2, 4, 5, 7, 9 }
M.TIER_NAME, M.PICK_SPEED, M.SWORD_HIT = TIER_NAME, PICK_SPEED, SWORD_HIT

-- at: "T" wants a crafting table near, "F" a furnace. tool/tier: what it makes of the player's pickaxe, sword or armour.
-- smelt: the furnace does as many as there's ore and fuel for, in one tap.
local RECIPES = {
  { id = "planks", out = "planks", n = 4, need = { { "log", 1 } } },
  { id = "stick", out = "stick", n = 4, need = { { "planks", 2 } } },
  { id = "table", out = "table", n = 1, need = { { "planks", 4 } } },
  { id = "torch", out = "torch", n = 4, need = { { "coal", 1 }, { "stick", 1 } } },
  { id = "wood_pick", name = "Wooden Pickaxe", tool = "pick", tier = 1, need = { { "planks", 3 }, { "stick", 2 } }, at = "T" },
  { id = "wood_sword", name = "Wooden Sword", tool = "sword", tier = 1, need = { { "planks", 2 }, { "stick", 1 } }, at = "T" },
  { id = "stone_pick", name = "Stone Pickaxe", tool = "pick", tier = 2, need = { { "cobble", 3 }, { "stick", 2 } }, at = "T" },
  { id = "stone_sword", name = "Stone Sword", tool = "sword", tier = 2, need = { { "cobble", 2 }, { "stick", 1 } }, at = "T" },
  { id = "furnace", out = "furnace", n = 1, need = { { "cobble", 8 } }, at = "T" },
  { id = "door", out = "door", n = 1, need = { { "planks", 6 } }, at = "T" },
  { id = "bed", out = "bed", n = 1, need = { { "wool", 3 }, { "planks", 3 } }, at = "T" },
  { id = "iron", out = "iron", n = 1, need = { { "iron_ore", 1 } }, at = "F", smelt = true },
  { id = "gold", out = "gold", n = 1, need = { { "gold_ore", 1 } }, at = "F", smelt = true },
  { id = "cook", out = "cooked_meat", n = 1, need = { { "raw_meat", 1 } }, at = "F", smelt = true },
  { id = "glass", out = "glass", n = 1, need = { { "sand", 1 } }, at = "F", smelt = true },
  { id = "iron_pick", name = "Iron Pickaxe", tool = "pick", tier = 3, need = { { "iron", 3 }, { "stick", 2 } }, at = "T" },
  { id = "iron_sword", name = "Iron Sword", tool = "sword", tier = 3, need = { { "iron", 2 }, { "stick", 1 } }, at = "T" },
  { id = "iron_armour", name = "Iron Armour", tool = "armour", tier = 1, need = { { "iron", 8 } }, at = "T" },
  { id = "golden_apple", out = "golden_apple", n = 1, need = { { "gold", 4 }, { "apple", 1 } }, at = "T" },
  { id = "diamond_pick", name = "Diamond Pickaxe", tool = "pick", tier = 4, need = { { "diamond", 3 }, { "stick", 2 } }, at = "T" },
  { id = "diamond_sword", name = "Diamond Sword", tool = "sword", tier = 4, need = { { "diamond", 2 }, { "stick", 1 } }, at = "T" },
  { id = "diamond_armour", name = "Diamond Armour", tool = "armour", tier = 2, need = { { "diamond", 8 } }, at = "T" },
}
local RECIPE = {}
for _, r in ipairs(RECIPES) do
  RECIPE[r.id] = r
  r.name = r.name or ITEM[r.out].name
end
M.RECIPES, M.RECIPE = RECIPES, RECIPE

local FUEL = { { "coal", 4 }, { "log", 2 }, { "planks", 1 } } -- smelts each gives, in the order they're used

-- The goals, in the order the bar suggests them.
local GOALS = {
  { id = "wood", text = "Chop a log from a tree" },
  { id = "table", text = "Make a crafting table" },
  { id = "wood_pick", text = "Make a wooden pickaxe" },
  { id = "stone_pick", text = "Make a stone pickaxe" },
  { id = "torch", text = "Make torches from coal" },
  { id = "fighter", text = "Defeat a monster" },
  { id = "furnace", text = "Build a furnace" },
  { id = "iron", text = "Smelt some iron" },
  { id = "iron_pick", text = "Make an iron pickaxe" },
  { id = "cook", text = "Cook some meat" },
  { id = "night", text = "Live through a night" },
  { id = "house", text = "Build a house: bed, door, torch, roof" },
  { id = "deep", text = "Dig down to diamond depth (" .. world.DIAMOND_DEPTH .. ")" },
  { id = "diamond", text = "Find a diamond" },
  { id = "diamond_pick", text = "Make a diamond pickaxe" },
  { id = "bedrock", text = "Reach the bedrock at the bottom" },
}
local GOAL = {}
for _, g in ipairs(GOALS) do GOAL[g.id] = g end
M.GOALS = GOALS

-- mobs: hp, and what they leave
local MOBS = {
  zombie = { hp = 12, hostile = true, name = "ZOMBIE", hit = 3 },
  skeleton = { hp = 10, hostile = true, name = "SKELETON", hit = 2 },
  pig = { hp = 6, name = "PIG", drops = { { "raw_meat", 1, 2 } } },
  cow = { hp = 8, name = "COW", drops = { { "raw_meat", 2, 3 } } },
  sheep = { hp = 6, name = "SHEEP", drops = { { "wool", 2, 3 }, { "raw_meat", 1, 1 } } },
}
M.MOBS = MOBS

-- ---------------------------------------------------------------- small things

local function changed(s) s.rev = s.rev + 1 end

local function say(s, text)
  s.msg, s.msgAge = text, 0
end

-- ---------------------------------------------------------------- two players in one world
-- The world's owner is the player at the top of the state (s.p, s.bed and the rest), as it always was. A friend who joins
-- from the other wall is a seat in s.guests, under their name, and stays there when they go, so their things are waiting
-- next time. Everything the rules do, they do for "the player", s.p: for a friend, the friend's fields are swapped into
-- the top of the state for the while, and swapped back after. The world, the mobs, the clock and the goals are shared.

local PERSONAL = { "p", "bed", "mode", "tab", "page", "msg", "msgAge", "dig", "queue", "hint", "fx" }
local swapped = setmetatable({}, { __mode = "k" }) -- the friend whose fields are at the top of a state just now

local function swap(s, seat)
  for _, k in ipairs(PERSONAL) do s[k], seat[k] = seat[k], s[k] end
end

--- Run fn with seat (a friend's seat, or nil for the owner) as the player, and put everything back after.
local function as(s, seat, fn, ...)
  local cur = swapped[s]
  if cur == seat then return fn(...) end
  if cur then swap(s, cur) end
  if seat then swap(s, seat) end
  swapped[s] = seat
  local ok, a, b = pcall(fn, ...)
  if seat then swap(s, seat) end
  if cur then swap(s, cur) end
  swapped[s] = cur
  if not ok then error(a, 0) end
  return a, b
end

--- A friend's player, wherever their fields are just now.
local function pOf(s, seat)
  local cur = swapped[s]
  if seat == cur then return s.p end
  if seat == nil then return cur.p end
  return seat.p
end

--- Everyone in the world just now, the owner first, then the friends by name: { seat, p, name }.
local function players(s)
  local list = { { p = pOf(s, nil), name = s.host } }
  if s.guests then
    local names = {}
    for name, g in pairs(s.guests) do
      if g.here then names[#names + 1] = name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local g = s.guests[name]
      list[#list + 1] = { seat = g, p = pOf(s, g), name = name }
    end
  end
  return list
end
M.players = players

--- Is anybody standing in this cell?
local function playerAt(s, x, y)
  local p = s.p
  if p.x == x and p.y == y then return true end
  if not s.guests then return false end
  for _, e in ipairs(players(s)) do
    if e.p.x == x and e.p.y == y then return true end
  end
  return false
end

--- Do fn for each player in the world in turn, as them.
local function forEach(s, fn)
  for _, e in ipairs(players(s)) do as(s, e.seat, fn) end
end

--- The seat for a name: a friend who is here, or nil for the owner (and for anyone else).
local function seatOf(s, who)
  local g = who ~= nil and s.guests and s.guests[who]
  return (g and g.here) and g or nil
end

--- Run fn(...) as the named player: the owner for nil, or for a name that isn't here.
function M.as(s, who, fn, ...)
  return as(s, seatOf(s, who), fn, ...)
end

local function sign(n) return n > 0 and 1 or (n < 0 and -1 or 0) end

function M.timeOfDay(s) return s.time % DAY end
function M.dayNumber(s) return floor(s.time / DAY) + 1 end

--- "day", "dusk", "night" or "dawn".
function M.phase(s)
  local t = s.time % DAY
  if t < DUSK then return "day" end
  if t < NIGHT then return "dusk" end
  if t < DAWN then return "night" end
  return "dawn"
end
local phase = M.phase

local function count(s, item) return s.p.inv[item] or 0 end
M.count = count

function M.mobAt(s, x, y)
  for i, m in ipairs(s.mobs) do
    if m.x == x and m.y == y then return m, i end
  end
  return nil
end
local mobAt = M.mobAt

--- Can the player stand in this cell? Doors let the player through.
local function freeForPlayer(s, x, y)
  return not BLOCKS[tileAt(s, x, y)].solid and not mobAt(s, x, y)
end

--- Can a mob stand here? Not in a door, not on the player, not on another mob.
local function freeForMob(s, x, y)
  local c = tileAt(s, x, y)
  if BLOCKS[c].solid or c == "D" then return false end
  if playerAt(s, x, y) then return false end
  return not mobAt(s, x, y)
end

--- Something under the player to stand on, or water to float in, or the top of a jump.
local function supported(s)
  local p = s.p
  if p.hang then return true end
  if tileAt(s, p.x, p.y) == WATER then return true end
  return BLOCKS[tileAt(s, p.x, p.y + 1)].solid == true or mobAt(s, p.x, p.y + 1) ~= nil
end
M.supported = supported

local function grant(s, id, events)
  if s.ach[id] or not GOAL[id] then return end
  events = events or {}
  s.ach[id] = true
  s.achCount = s.achCount + 1
  s.level = 1 + s.achCount
  s.score = s.score + 100
  say(s, "GOAL DONE: " .. GOAL[id].text .. "!")
  events[#events + 1] = { type = "goal", id = id }
end
M.grant = grant

--- The first goal not yet done, or nil when they all are.
function M.nextGoal(s)
  for _, g in ipairs(GOALS) do
    if not s.ach[g.id] then return g end
  end
  return nil
end

-- ---------------------------------------------------------------- the inventory and the hotbar

local BAR_SLOTS = 8 -- after the hand
M.BAR_SLOTS = BAR_SLOTS

local function barred(s, item)
  for i, id in ipairs(s.p.bar) do
    if id == item then return i end
  end
  return nil
end

local function give(s, item, n)
  local p = s.p
  p.inv[item] = (p.inv[item] or 0) + n
  local def = ITEM[item]
  if (def.place or def.food) and not barred(s, item) and #p.bar < BAR_SLOTS then p.bar[#p.bar + 1] = item end
  if item == "log" then grant(s, "wood", s.pending) end
  if item == "diamond" then
    s.stats.diamonds = s.stats.diamonds + n
    grant(s, "diamond", s.pending)
  end
end
M.give = give

--- Take n of an item. A slot on the bar that runs out goes, and the hand is held again if it was the one in use.
local function take(s, item, n)
  local p = s.p
  p.inv[item] = (p.inv[item] or 0) - n
  if p.inv[item] > 0 then return end
  p.inv[item] = nil
  local at = barred(s, item)
  if at then
    table.remove(p.bar, at)
    if p.sel == at then p.sel = 0 elseif p.sel > at then p.sel = p.sel - 1 end
  end
end

--- The item in the selected slot, or nil for the hand.
function M.held(s)
  local p = s.p
  return p.sel > 0 and p.bar[p.sel] or nil
end

-- ---------------------------------------------------------------- crafting

local function stationNear(s, tile)
  local p = s.p
  for y = p.y - 3, p.y + 3 do
    for x = p.x - 4, p.x + 4 do
      if tileAt(s, x, y) == tile then return true end
    end
  end
  return false
end
M.stationNear = stationNear

local function hasFuel(s)
  if s.p.heat > 0 then return true end
  for _, f in ipairs(FUEL) do
    if count(s, f[1]) > 0 then return true end
  end
  return false
end

--- Can the recipe be made now? Returns true, or false and what's missing (a short line), and how many of the needs are met.
function M.canMake(s, r)
  local missing, have = {}, 0
  if r.tool and s.p[r.tool] >= r.tier then return false, "you have one as good", 0 end
  for _, need in ipairs(r.need) do
    local got = count(s, need[1])
    if got >= need[2] then
      have = have + 1
    else
      if got > 0 then have = have + 0.5 end
      missing[#missing + 1] = (need[2] - got) .. " " .. ITEM[need[1]].name
    end
  end
  if r.smelt and not hasFuel(s) then missing[#missing + 1] = "fuel (coal or wood)" end
  if r.at and not stationNear(s, r.at) then
    missing[#missing + 1] = r.at == "T" and "a crafting table near" or "a furnace near"
  end
  if #missing > 0 then return false, "needs " .. table.concat(missing, ", "), have end
  return true, nil, have
end
local canMake = M.canMake

--- What the crafting list shows: what can be made, and what's close (some of what it needs, and not a lesser tool than the
--- player's own). { r, ok, why } in recipe order, ready ones first.
function M.recipeList(s)
  local ready, close = {}, {}
  for _, r in ipairs(RECIPES) do
    local ok, why, have = canMake(s, r)
    if ok then
      ready[#ready + 1] = { r = r, ok = true }
    elseif not (r.tool and s.p[r.tool] >= r.tier) and count(s, r.need[1][1]) > 0 then
      close[#close + 1] = { r = r, ok = false, why = why }
    end
  end
  for _, e in ipairs(close) do ready[#ready + 1] = e end
  return ready
end

local function useFuel(s)
  local p = s.p
  if p.heat > 0 then
    p.heat = p.heat - 1
    return true
  end
  for _, f in ipairs(FUEL) do
    if count(s, f[1]) > 0 then
      take(s, f[1], 1)
      p.heat = f[2] - 1
      return true
    end
  end
  return false
end

local function craft(s, id, events)
  local r = RECIPE[id]
  if not r then return end
  local ok, why = canMake(s, r)
  if not ok then
    say(s, r.name .. ": " .. why)
    events[#events + 1] = { type = "refuse" }
    return
  end
  local made = 0
  repeat
    for _, need in ipairs(r.need) do take(s, need[1], need[2]) end
    if r.smelt then useFuel(s) end
    if r.tool then
      s.p[r.tool] = r.tier
      made = 1
    else
      give(s, r.out, r.n)
      made = made + r.n
    end
  until not r.smelt or not canMake(s, r) or made >= 64
  s.stats.crafted = s.stats.crafted + made
  local goal = ({ table = "table", torch = "torch", wood_pick = "wood_pick", stone_pick = "stone_pick", furnace = "furnace",
    iron = "iron", iron_pick = "iron_pick", cook = "cook", diamond_pick = "diamond_pick" })[id]
  if goal then grant(s, goal, events) end
  if s.msg == "" or not s.msg:find("^GOAL") then
    say(s, (r.smelt and "Smelted " or "Made ") .. (made > 1 and (made .. " x ") or "") .. r.name)
  end
  events[#events + 1] = { type = r.smelt and "smelt" or "craft" }
end

-- ---------------------------------------------------------------- the house

--- A bed with a door and a torch near it, and a roof over it.
local function checkHouse(s, events)
  if s.ach.house then return end
  local p = s.p
  for by = p.y - 5, p.y + 5 do
    for bx = p.x - 7, p.x + 7 do
      if tileAt(s, bx, by) == "b" then
        local door, torch, roof = false, false, false
        for y = by - 5, by + 2 do
          for x = bx - 7, bx + 7 do
            local c = tileAt(s, x, y)
            if c == "D" then door = true elseif c == "t" then torch = true end
          end
        end
        for y = by - 6, by - 1 do
          if BLOCKS[tileAt(s, bx, y)].solid then roof = true end
        end
        if door and torch and roof then
          grant(s, "house", events)
          return
        end
      end
    end
  end
end

-- ---------------------------------------------------------------- the world changing

--- Sand with nothing under it drops, all the way.
local function settle(s, x, y)
  while y >= 0 and tileAt(s, x, y) == "a" do
    local to = y
    while true do
      local below = tileAt(s, x, to + 1)
      if (below ~= AIR and below ~= WATER) or playerAt(s, x, to + 1) or mobAt(s, x, to + 1) then break end
      to = to + 1
    end
    if to == y then return end
    setTile(s, x, y, AIR)
    setTile(s, x, to, "a")
    y = y - 1
  end
end

local function hurt(s, dmg, events, from)
  local p = s.p
  dmg = max(1, dmg - (from and p.armour or 0))
  p.hp = p.hp - dmg
  s.fx.hurt = 3
  events[#events + 1] = { type = "hurt", from = from }
end

--- Where a player can stand at or above x, y: the first free cell with ground under it, looking up the column and then
--- along. Used for a respawn, when a bed may have been walled in.
local function standingPlace(s, x, y)
  for dx = 0, 12 do
    for _, side in ipairs({ 1, -1 }) do
      local cx = x + dx * side
      for cy = y, max(0, y - 40), -1 do
        if freeForPlayer(s, cx, cy) and BLOCKS[tileAt(s, cx, cy + 1)].solid then return cx, cy end
      end
    end
  end
  return x, world.skyTop(s, x) - 1
end

local function respawn(s, events)
  local p = s.p
  s.stats.deaths = s.stats.deaths + 1
  events[#events + 1] = { type = "death" }
  local bed = s.bed and tileAt(s, s.bed.x, s.bed.y) == "b" and s.bed or nil
  if not bed then s.bed = nil end
  local x, y
  if bed then
    x, y = standingPlace(s, bed.x, bed.y - 1)
  else
    x, y = standingPlace(s, s.home.x, s.home.y)
  end
  p.x, p.y, p.hp, p.food, p.fall, p.hang = x, y, MAX_HP, max(p.food, 14), 0, false
  s.dig = nil
  for i = #s.mobs, 1, -1 do
    local m = s.mobs[i]
    if MOBS[m.k].hostile and abs(m.x - x) <= 24 then table.remove(s.mobs, i) end
  end
  say(s, "You fainted, and woke " .. (bed and "in your bed" or "where you started") .. ". Your things are all here.")
end

local function checkDeath(s, events)
  if s.p.hp <= 0 then respawn(s, events) end
end

-- ---------------------------------------------------------------- mobs

local function sightClear(s, x1, y1, x2, y2)
  local n = max(abs(x2 - x1), abs(y2 - y1))
  for i = 1, n - 1 do
    local x = x1 + floor((x2 - x1) * i / n + 0.5)
    local y = y1 + floor((y2 - y1) * i / n + 0.5)
    if BLOCKS[tileAt(s, x, y)].opaque then return false end
  end
  return true
end
M.sightClear = sightClear

--- A step sideways, up a block if it must.
local function mobStep(s, m, dir)
  if dir == 0 then return false end
  local nx = m.x + dir
  if freeForMob(s, nx, m.y) then
    m.x, m.dir = nx, dir
    return true
  end
  if freeForMob(s, nx, m.y - 1) and freeForMob(s, m.x, m.y - 1) then
    m.x, m.y, m.dir = nx, m.y - 1, dir
    return true
  end
  return false
end

local function underSky(s, x, y) return y < world.skyTop(s, x) end

local function mobAct(s, m, rng, events)
  local p = s.p
  local def = MOBS[m.k]
  if m.cd > 0 then m.cd = m.cd - 1 end
  if m.scared and m.scared > 0 then m.scared = m.scared - 1 end
  -- falling comes first, and is the whole step
  if tileAt(s, m.x, m.y) ~= WATER and freeForMob(s, m.x, m.y + 1) then
    m.y = m.y + 1
    return
  end
  if def.hostile and phase(s) == "day" and underSky(s, m.x, m.y) then
    m.hp = m.hp - 4
    m.burn = true
    if m.hp <= 0 then return "gone" end
  end
  local dx, dy = p.x - m.x, p.y - m.y
  local dist = max(abs(dx), abs(dy))
  if def.hostile then
    if dist <= 1 then
      if m.cd == 0 then
        m.cd = 1
        hurt(s, def.hit, events, m.k)
        events[#events + 1] = { type = "strike", kind = m.k }
      end
      return
    end
    if abs(dx) > 18 or abs(dy) > 10 then
      if rng(4) == 1 then mobStep(s, m, rng(2) == 1 and -1 or 1) end
      return
    end
    if m.k == "skeleton" then
      if dist <= 7 and m.cd == 0 and sightClear(s, m.x, m.y, p.x, p.y) then
        m.cd = 4
        s.fx.arrow = { m.x, m.y, p.x, p.y, 3 }
        events[#events + 1] = { type = "shoot" }
        if rng(4) > 1 then hurt(s, def.hit, events, m.k) end
        return
      end
      if dist < 3 then
        mobStep(s, m, -sign(dx))
      elseif dist > 5 and s.time % 2 == 0 then
        mobStep(s, m, sign(dx))
      end
      return
    end
    if s.time % 3 ~= 0 then mobStep(s, m, sign(dx)) end
    return
  end
  -- animals wander, and run when hit
  if m.scared and m.scared > 0 then
    mobStep(s, m, -sign(dx) ~= 0 and -sign(dx) or 1)
  elseif rng(3) == 1 then
    mobStep(s, m, rng(2) == 1 and -1 or 1)
  end
end

local function torchNear(s, x, y, r)
  for cy = y - r, y + r do
    for cx = x - r, x + r do
      if tileAt(s, cx, cy) == "t" then return true end
    end
  end
  return false
end

local function newMob(k, x, y)
  return { k = k, x = x, y = y, hp = MOBS[k].hp, cd = 0, dir = -1 }
end
M.newMob = newMob

local function spawnMobs(s, rng)
  local p = s.p
  local hostile, animals = 0, 0
  for _, m in ipairs(s.mobs) do
    if MOBS[m.k].hostile then hostile = hostile + 1 else animals = animals + 1 end
  end
  local t = s.time % DAY
  local side = rng(2) == 1 and -1 or 1
  if t >= MONSTERS_FROM and t < MONSTERS_TO and hostile < MAX_HOSTILE_NIGHT and rng(10) == 1 then
    local x = p.x + side * (9 + rng(8))
    local y = world.skyTop(s, x) - 1
    if y > 0 and tileAt(s, x, y) == AIR and abs(y - p.y) < 14 and not torchNear(s, x, y, 5) then
      s.mobs[#s.mobs + 1] = newMob(rng(3) == 1 and "skeleton" or "zombie", x, y)
    end
    return
  end
  if p.y > world.skyTop(s, p.x) + 3 and hostile < MAX_HOSTILE_CAVE and rng(14) == 1 then
    local x, y = p.x + side * (6 + rng(8)), p.y + rng(13) - 7
    if tileAt(s, x, y) == AIR and BLOCKS[tileAt(s, x, y + 1)].solid and not mobAt(s, x, y) and not world.isLit(s, x, y) then
      s.mobs[#s.mobs + 1] = newMob(rng(3) == 1 and "skeleton" or "zombie", x, y)
    end
    return
  end
  if t < DUSK and animals < MAX_ANIMALS and rng(25) == 1 then
    local x = p.x + side * (10 + rng(12))
    local y = world.skyTop(s, x) - 1
    if tileAt(s, x, y) == AIR and tileAt(s, x, y + 1) == "g" and not mobAt(s, x, y) then
      s.mobs[#s.mobs + 1] = newMob(({ "pig", "sheep", "cow", "sheep", "pig" })[rng(5)], x, y)
    end
  end
end

--- The player a mob goes for: the nearest, the owner first on a tie. Returns their entry and how far.
local function nearest(list, m)
  local best, bestD
  for _, e in ipairs(list) do
    local d = max(abs(e.p.x - m.x), abs(e.p.y - m.y))
    if not bestD or d < bestD then best, bestD = e, d end
  end
  return best, bestD
end

local function mobsAct(s, rng, events)
  local list = players(s)
  local i = 1
  while i <= #s.mobs do
    local m = s.mobs[i]
    local e = nearest(list, m)
    local gone = abs(m.x - e.p.x) > FAR_AWAY or abs(m.y - e.p.y) > FAR_AWAY
    if gone and #list > 1 then
      gone = true
      for _, other in ipairs(list) do
        if abs(m.x - other.p.x) <= FAR_AWAY and abs(m.y - other.p.y) <= FAR_AWAY then gone = false end
      end
    end
    if not gone then gone = as(s, e.seat, mobAct, s, m, rng, events) == "gone" end
    if gone then table.remove(s.mobs, i) else i = i + 1 end
    for _, other in ipairs(list) do
      if other.p.hp <= 0 then return end
    end
  end
  spawnMobs(s, rng)
end

-- ---------------------------------------------------------------- one step of the world

--- One step of the world, for whichever player moved (s.p). The clock, the mobs and everybody's messages move on for all;
--- hunger and healing go with the player's own steps, so a friend busy at the other wall never starves anyone.
local function worldStep(s, rng, events)
  local p = s.p
  local before = phase(s)
  s.time = s.time + 1
  s.steps = s.steps + 1
  forEach(s, function()
    s.msgAge = s.msgAge + 1
    if s.msgAge > MSG_STEPS then s.msg = "" end
    if s.hint > 0 then s.hint = s.hint - 1 end
  end)
  p.hungerT = p.hungerT + 1
  if p.hungerT >= HUNGER_EVERY then
    p.hungerT = 0
    p.food = max(0, p.food - 1)
  end
  if p.food >= REGEN_FOOD and p.hp < MAX_HP then
    p.regenT = p.regenT + 1
    if p.regenT >= REGEN_EVERY then p.regenT, p.hp = 0, p.hp + 1 end
  elseif p.food == 0 then
    p.regenT = p.regenT + 1
    if p.regenT >= STARVE_EVERY then
      p.regenT = 0
      if p.hp > 1 then
        p.hp = p.hp - 1
        s.fx.hurt = 3
        events[#events + 1] = { type = "hurt" }
        say(s, "You're starving! Eat something: tap yourself.")
      end
    end
  end
  local now = phase(s)
  if now ~= before then
    if now == "dusk" then
      forEach(s, function() say(s, "The sun is going down. Find shelter, or light!") end)
      events[#events + 1] = { type = "dusk" }
    elseif now == "day" then
      forEach(s, function() say(s, "Morning of day " .. M.dayNumber(s) .. ". Monsters burn in the sun.") end)
      events[#events + 1] = { type = "dawn" }
      grant(s, "night", events)
    end
  end
  mobsAct(s, rng, events)
  -- how deep, and the bottom of the world
  local depth = world.depth(p.y)
  if depth > s.stats.deepest then
    s.score = s.score + (depth - s.stats.deepest) * 2
    s.stats.deepest = depth
    if depth >= world.DIAMOND_DEPTH then grant(s, "deep", events) end
  end
  if tileAt(s, p.x, p.y + 1) == "B" then grant(s, "bedrock", events) end
  s.stats.days = M.dayNumber(s)
  forEach(s, function() checkDeath(s, events) end)
end

-- ---------------------------------------------------------------- what the player does

local function land(s, events)
  local p = s.p
  if p.fall > SAFE_FALL and tileAt(s, p.x, p.y) ~= WATER then
    hurt(s, p.fall - SAFE_FALL, events)
    say(s, "Ouch! That was a long way down.")
  elseif p.fall > 0 then
    events[#events + 1] = { type = tileAt(s, p.x, p.y) == WATER and "splash" or "land" }
  end
  p.fall = 0
end

local function fallStep(s, rng, events)
  local p = s.p
  p.y = p.y + 1
  p.fall = p.fall + 1
  if tileAt(s, p.x, p.y) == WATER then p.fall = 0 end
  if supported(s) then land(s, events) end
  worldStep(s, rng, events)
end

local function attack(s, m, rng, events)
  local p = s.p
  local def = MOBS[m.k]
  m.hp = m.hp - SWORD_HIT[p.sword]
  p.facing = sign(m.x - p.x) ~= 0 and sign(m.x - p.x) or p.facing
  local away = sign(m.x - p.x)
  if away ~= 0 and freeForMob(s, m.x + away, m.y) then m.x = m.x + away end
  if not def.hostile then m.scared = 6 end
  events[#events + 1] = { type = "hit", kind = m.k }
  if m.hp <= 0 then
    for i, other in ipairs(s.mobs) do
      if other == m then table.remove(s.mobs, i) break end
    end
    events[#events + 1] = { type = "kill", kind = m.k }
    if def.hostile then
      s.stats.kills = s.stats.kills + 1
      s.score = s.score + 10
      grant(s, "fighter", events)
      say(s, "You beat the " .. def.name:lower() .. "!")
    else
      local got = {}
      for _, d in ipairs(def.drops) do
        local n = d[2] + rng(d[3] - d[2] + 1) - 1
        give(s, d[1], n)
        got[#got + 1] = n .. " " .. ITEM[d[1]].name
      end
      say(s, "Got " .. table.concat(got, " and "))
      events[#events + 1] = { type = "pickup" }
    end
  end
  return true
end

--- One blow at a block. Returns true if it took a step.
local function dig(s, x, y, rng, events)
  local p = s.p
  local c = tileAt(s, x, y)
  local def = BLOCKS[c]
  if not def.hard then
    say(s, def.name .. " can't be broken.")
    events[#events + 1] = { type = "bump" }
    return false
  end
  if (def.tier or 0) > p.pick then
    say(s, def.name .. " needs a " .. TIER_NAME[def.tier]:lower() .. " pickaxe or better.")
    events[#events + 1] = { type = "bump" }
    return false
  end
  if x ~= p.x then p.facing = sign(x - p.x) end
  local hits = max(1, ceil(def.hard / PICK_SPEED[p.pick]))
  local d = s.dig
  if d and d.x == x and d.y == y and d.c == c then
    d.n = d.n + 1
  else
    d = { x = x, y = y, c = c, n = 1, of = hits }
    s.dig = d
  end
  d.of = hits
  if d.n < hits then
    events[#events + 1] = { type = "dig", tile = c }
    return true
  end
  s.dig = nil
  local natural = world.column(s.seed, x):sub(y + 1, y + 1) == c
  setTile(s, x, y, AIR)
  s.stats.mined = s.stats.mined + 1
  if natural then s.score = s.score + 1 + (def.ore or 0) end
  if def.chance then
    if rng(def.chance) == 1 then
      give(s, def.drop, 1)
      say(s, "An apple fell out of the leaves!")
    end
  elseif def.drop then
    give(s, def.drop, 1)
    if def.ore and natural then say(s, "Got " .. ITEM[def.drop].name .. "!") end
  end
  if s.bed and s.bed.x == x and s.bed.y == y then s.bed = nil end
  events[#events + 1] = { type = "break", tile = c, ore = def.ore and natural }
  settle(s, x, y - 1)
  return true
end

local function place(s, x, y, item, events)
  local p = s.p
  local c = tileAt(s, x, y)
  if (c ~= AIR and c ~= WATER) or mobAt(s, x, y) or playerAt(s, x, y) then return false end
  local tile = ITEM[item].place
  setTile(s, x, y, tile)
  take(s, item, 1)
  s.stats.placed = s.stats.placed + 1
  if x ~= p.x then p.facing = sign(x - p.x) end
  events[#events + 1] = { type = "place", tile = tile }
  settle(s, x, y)
  if tile == "b" or tile == "D" or tile == "t" then checkHouse(s, events) end
  if tile == "b" and not s.bed then say(s, "Tap the bed to make it your spawn point, or to sleep at night.") end
  return true
end

local FOOD_ORDER = { "cooked_meat", "apple", "raw_meat", "golden_apple" }

local function eat(s, events)
  local p = s.p
  local item = M.held(s)
  if not (item and ITEM[item].food) then
    item = nil
    for _, id in ipairs(FOOD_ORDER) do
      if count(s, id) > 0 then
        item = id
        break
      end
    end
  end
  if not item then
    say(s, "Nothing to eat. Leaves drop apples; animals give meat.")
    events[#events + 1] = { type = "bump" }
    return false
  end
  local golden = item == "golden_apple"
  if p.food >= MAX_FOOD and not (golden and p.hp < MAX_HP) then
    say(s, "You're full.")
    events[#events + 1] = { type = "bump" }
    return false
  end
  take(s, item, 1)
  p.food = min(MAX_FOOD, p.food + ITEM[item].food)
  if golden then p.hp = MAX_HP end
  say(s, "Ate " .. ITEM[item].name:lower() .. ".")
  events[#events + 1] = { type = "eat" }
  return true
end

local function hostileNear(s, r)
  for _, m in ipairs(s.mobs) do
    if MOBS[m.k].hostile and abs(m.x - s.p.x) <= r and abs(m.y - s.p.y) <= r then return true end
  end
  return false
end

--- A bed: sleep at night, set the spawn point by day. Tapped again by day, it's dug up like anything else.
local function useBed(s, x, y, rng, events)
  local sameBed = s.bed and s.bed.x == x and s.bed.y == y
  local t = s.time % DAY
  if t >= DUSK then
    if hostileNear(s, BED_SAFE) then
      say(s, "You can't sleep with monsters nearby!")
      events[#events + 1] = { type = "bump" }
      return false
    end
    s.bed = { x = x, y = y }
    s.time = (floor(s.time / DAY) + 1) * DAY
    s.stats.days = M.dayNumber(s)
    for i = #s.mobs, 1, -1 do
      if MOBS[s.mobs[i].k].hostile then table.remove(s.mobs, i) end
    end
    events[#events + 1] = { type = "sleep" }
    grant(s, "night", events)
    checkHouse(s, events)
    if not s.msg:find("^GOAL") then say(s, "You slept through the night. Good morning! Day " .. M.dayNumber(s) .. ".") end
    s.dig = nil
    return false
  end
  if not sameBed then
    s.bed = { x = x, y = y }
    say(s, "Spawn point set. Sleep here when it gets dark.")
    events[#events + 1] = { type = "spawnset" }
    checkHouse(s, events)
    return false
  end
  return dig(s, x, y, rng, events)
end

--- A block part dug stays part dug while the player is next to it, so a jump and a blow, and another, can bring down a
--- log that's out of reach from the ground.
local function forgetDig(s)
  local d, p = s.dig, s.p
  if d and (abs(d.x - p.x) > 1 or abs(d.y - p.y) > 1) then s.dig = nil end
end

local function walk(s, dir, rng, events)
  local p = s.p
  p.facing = dir
  local nx = p.x + dir
  local m = mobAt(s, nx, p.y)
  if m then return attack(s, m, rng, events) end
  if freeForPlayer(s, nx, p.y) then
    p.x = nx
  elseif freeForPlayer(s, nx, p.y - 1) and freeForPlayer(s, p.x, p.y - 1) and (supported(s)) then
    p.x, p.y = nx, p.y - 1
  else
    local c = tileAt(s, nx, p.y)
    if BLOCKS[c].hard then say(s, "Tap the " .. BLOCKS[c].name:lower() .. " right beside you to dig it.") end
    events[#events + 1] = { type = "bump" }
    return false
  end
  forgetDig(s)
  events[#events + 1] = { type = tileAt(s, p.x, p.y) == WATER and "swim" or "step" }
  return true
end

local function jump(s, events)
  local p = s.p
  local inWater = tileAt(s, p.x, p.y) == WATER
  if not inWater and not BLOCKS[tileAt(s, p.x, p.y + 1)].solid then
    events[#events + 1] = { type = "bump" }
    return false
  end
  if not freeForPlayer(s, p.x, p.y - 1) then
    local c = tileAt(s, p.x, p.y - 1)
    if BLOCKS[c].hard then say(s, "Tap the " .. BLOCKS[c].name:lower() .. " above you to dig it.") end
    events[#events + 1] = { type = "bump" }
    return false
  end
  p.y = p.y - 1
  p.hang = true
  forgetDig(s)
  events[#events + 1] = { type = inWater and "swim" or "jump" }
  return true, true
end

local function swimDown(s, events)
  local p = s.p
  if tileAt(s, p.x, p.y) == WATER and freeForPlayer(s, p.x, p.y + 1) then
    p.y = p.y + 1
    events[#events + 1] = { type = "swim" }
    return true
  end
  events[#events + 1] = { type = "bump" }
  return false
end

--- A tap on the cell dx, dy from the player, worked out now, with the world as it is.
function M.resolveTap(s, dx, dy)
  local adx, ady = abs(dx), abs(dy)
  if dx == 0 and dy == 0 then return { kind = "eat" } end
  if adx <= 1 and ady <= 1 then
    local x, y = s.p.x + dx, s.p.y + dy
    if mobAt(s, x, y) then return { kind = "use", dx = dx, dy = dy } end
    local c = tileAt(s, x, y)
    if world.diggable(c) then return { kind = "use", dx = dx, dy = dy } end
    local item = M.held(s)
    if item and ITEM[item].place then return { kind = "use", dx = dx, dy = dy } end
    if dy == -1 and dx == 0 then return { kind = "jump" } end
    if dy == 1 and dx == 0 then return { kind = "down" } end
    return { kind = "walk", dir = dx }
  end
  if adx >= 2 then return { kind = "walk", dir = dx > 0 and 1 or -1 } end
  if dy <= -2 then return { kind = "jump" } end
  return { kind = "down" }
end

--- A tap on a neighbouring cell: hit what's there, dig it, or put the held block in it.
local function use(s, dx, dy, rng, events)
  local p = s.p
  if abs(dx) > 1 or abs(dy) > 1 or (dx == 0 and dy == 0) then return false end
  local x, y = p.x + dx, p.y + dy
  local m = mobAt(s, x, y)
  if m then return attack(s, m, rng, events) end
  local c = tileAt(s, x, y)
  if c == "b" then return useBed(s, x, y, rng, events) end
  if world.diggable(c) then return dig(s, x, y, rng, events) end
  local item = M.held(s)
  if item and ITEM[item].place then return place(s, x, y, item, events) end
  if dy == 0 then return walk(s, dx, rng, events) end
  return false
end

--- A world action, once the clock reaches it. Returns true if the world takes a step.
local function apply(s, action, rng, events)
  local kind = action.kind
  if kind == "tap" then
    action = M.resolveTap(s, action.dx or 0, action.dy or 0)
    kind = action.kind
  end
  local stepped, keepHang = false, false
  if kind == "walk" then
    stepped = walk(s, action.dir == -1 and -1 or 1, rng, events)
  elseif kind == "jump" then
    stepped, keepHang = jump(s, events)
  elseif kind == "down" then
    stepped = swimDown(s, events)
  elseif kind == "use" then
    stepped = use(s, action.dx or 0, action.dy or 0, rng, events)
  elseif kind == "eat" then
    stepped = eat(s, events)
  end
  if stepped then
    if not keepHang then s.p.hang = false end
    worldStep(s, rng, events)
  end
  return stepped
end

-- ---------------------------------------------------------------- the menu: no time passes in it

local MENU_KINDS = { menu = true, close = true, tab = true, craft = true, pick = true, page = true, select = true }
M.TABS = { "craft", "items", "goals" }

local function menuAction(s, action, events)
  local kind = action.kind
  if kind == "menu" then
    s.mode = s.mode == "menu" and "play" or "menu"
    s.page = 1
    events[#events + 1] = { type = "menu" }
  elseif kind == "close" then
    s.mode = "play"
    events[#events + 1] = { type = "menu" }
  elseif kind == "tab" then
    s.mode, s.tab, s.page = "menu", action.tab or "craft", 1
    events[#events + 1] = { type = "menu" }
  elseif kind == "page" then
    s.page = max(1, s.page + (action.d or 1))
    events[#events + 1] = { type = "menu" }
  elseif kind == "craft" then
    craft(s, action.id, events)
  elseif kind == "select" then
    local slot = action.slot or 0
    if slot >= 0 and slot <= #s.p.bar then
      s.p.sel = slot
      events[#events + 1] = { type = "select" }
    end
  elseif kind == "pick" then
    -- an item from the inventory to the bar, in the selected slot if the bar is full
    local item, p = action.item, s.p
    if not ITEM[item] or count(s, item) <= 0 or not (ITEM[item].place or ITEM[item].food) then return end
    local at = barred(s, item)
    if not at then
      if #p.bar < BAR_SLOTS then
        p.bar[#p.bar + 1] = item
        at = #p.bar
      else
        at = p.sel > 0 and p.sel or BAR_SLOTS
        p.bar[at] = item
      end
    end
    p.sel = at
    s.mode = "play"
    say(s, ITEM[item].name .. " in hand.")
    events[#events + 1] = { type = "select" }
  end
end

-- ---------------------------------------------------------------- the contract

--- Where a new world starts: beside the first tree on dry land from x = 0, or the first dry land.
local function findHome(s)
  for x = 0, 400 do
    local h = world.ground(s.seed, x)
    if h < world.SEA and tileAt(s, x, h) == "g" and tileAt(s, x + 1, h - 1) == "l" and tileAt(s, x, h - 1) == AIR then
      return x, h - 1
    end
  end
  for x = 0, 2000 do
    local h = world.ground(s.seed, x)
    if h < world.SEA and tileAt(s, x, h - 1) == AIR then return x, h - 1 end
  end
  return 0, world.skyTop(s, 0) - 1
end

function M.new(opts)
  local rng = opts.rng
  local s = {
    score = 0, level = 1, over = false, won = false, rev = 0, frame = 0, steps = 0, time = START_TIME,
    seed = opts.seed or rng(2147483646), edits = {}, mode = "play", tab = "craft", page = 1,
    mobs = {}, queue = {}, msg = "", msgAge = 0, hint = HINT_STEPS, ach = {}, achCount = 0,
    fx = { hurt = 0 },
    stats = { mined = 0, placed = 0, crafted = 0, deepest = 0, diamonds = 0, kills = 0, deaths = 0, days = 1 },
    p = {
      x = 0, y = 0, hp = MAX_HP, food = MAX_FOOD, sel = 0, bar = {}, inv = {}, pick = 0, sword = 0, armour = 0,
      heat = 0, hang = false, fall = 0, hungerT = 0, regenT = 0, facing = 1,
    },
  }
  local x, y = findHome(s)
  s.home = { x = x, y = y }
  s.p.x, s.p.y = x, y
  say(s, "A new world! Tap the tree trunk beside you to chop it.")
  return s
end

--- A tap. A menu tap happens at once (no time passes in the menu); a tap in the world waits for the clock, and a second
--- one waits behind it. More than that are dropped.
local input

--- who: the friend whose tap it is, by name; nil for the world's owner. A name that isn't in the world does nothing.
function M.input(s, action, who)
  if s.over or type(action) ~= "table" then return end
  if who == nil then return input(s, action) end
  local seat = seatOf(s, who)
  if seat then as(s, seat, input, s, action) end
end

function input(s, action)
  if MENU_KINDS[action.kind] then
    local events = {}
    s.pending = events
    menuAction(s, action, events)
    s.pending = nil
    s.heard = events
    changed(s)
    return
  end
  if s.mode ~= "play" then return end
  if #s.queue >= QUEUE_LONGEST then return end
  s.queue[#s.queue + 1] = { kind = action.kind, dir = action.dir, dx = action.dx, dy = action.dy }
end

function M.tick(s, rng)
  local events = {}
  if s.over then return events end
  if s.heard then
    for _, ev in ipairs(s.heard) do events[#events + 1] = ev end
    s.heard = nil
  end
  s.frame = s.frame + 1
  s.pending = events
  -- each player in turn: the owner, then the friends
  forEach(s, function()
    local fx = s.fx
    if fx.hurt > 0 then
      fx.hurt = fx.hurt - 1
      if fx.hurt == 0 then changed(s) end
    end
    if fx.arrow then
      fx.arrow[5] = fx.arrow[5] - 1
      if fx.arrow[5] <= 0 then fx.arrow = nil end
      changed(s)
    end
    if s.mode == "play" then
      if not supported(s) then
        fallStep(s, rng, events)
        changed(s)
      else
        local action = table.remove(s.queue, 1)
        if action then
          apply(s, action, rng, events)
          changed(s)
        end
      end
    end
  end)
  s.pending = nil
  return events
end

-- ---------------------------------------------------------------- friends joining and leaving

local function newPlayer(x, y)
  return {
    x = x, y = y, hp = MAX_HP, food = MAX_FOOD, sel = 0, bar = {}, inv = {}, pick = 0, sword = 0, armour = 0,
    heat = 0, hang = false, fall = 0, hungerT = 0, regenT = 0, facing = 1,
  }
end

--- A friend comes into the world: the one they had here before, with their things, where they left it; or a new player
--- beside the owner. host is the owner's name, for the tags over their heads. Returns true, or false and why.
function M.join(s, who, host)
  if type(who) ~= "string" or who == "" then return false, "who?" end
  if host and who == host then return false, "That's your own world" end
  s.host = host or s.host
  s.guests = s.guests or {}
  local g = s.guests[who]
  local owner = pOf(s, nil)
  if g and g.here then return true end
  if g then
    g.here, g.queue, g.mode, g.page, g.dig = true, {}, "play", 1, nil
    g.fx = { hurt = 0 }
    if not freeForPlayer(s, g.p.x, g.p.y) then g.p.x, g.p.y = standingPlace(s, g.p.x, g.p.y) end
    g.p.fall, g.p.hang = 0, false
    g.msg, g.msgAge = "Welcome back, " .. who .. "! Your things are just as you left them.", 0
  else
    local x, y = standingPlace(s, owner.x - 2, owner.y) -- two blocks off, so the two are told apart
    g = {
      name = who, here = true, p = newPlayer(x, y), mode = "play", tab = "craft", page = 1, queue = {}, hint = 0,
      fx = { hurt = 0 }, msg = "Welcome to " .. (s.host or "this") .. "'s world, " .. who .. "! Chop a tree to begin.", msgAge = 0,
    }
    g.p.facing = owner.x >= x and 1 or -1
    s.guests[who] = g
  end
  as(s, nil, say, s, who .. " has come to play in your world!")
  changed(s)
  return true
end

--- A friend goes, and their things stay in the world for next time. With no name, every friend goes (a saved world comes
--- back with nobody but its owner in it).
function M.part(s, who)
  if not s.guests then return end
  for name, g in pairs(s.guests) do
    if g.here and (who == nil or name == who) then
      g.here, g.queue, g.mode, g.dig = false, {}, "play", nil
      g.fx = { hurt = 0 }
      if who then as(s, nil, say, s, name .. " has gone. Their things are kept in this world.") end
    end
  end
  changed(s)
end

--- The friends in the world just now, by name.
function M.guests(s)
  local out = {}
  for i, e in ipairs(players(s)) do
    if i > 1 then out[#out + 1] = e.name end
  end
  return out
end

--- For the list of everyone's games: { level, percent, goal, minutes, place }.
function M.progress(s)
  local goal = M.nextGoal(s)
  return {
    level = s.level, percent = floor(s.achCount * 100 / #GOALS), goal = goal and goal.text or "Every goal done!",
    minutes = floor((s.frame or 0) * 0.12 / 60), ended = false,
    place = "deepest " .. s.stats.deepest .. ", " .. s.stats.diamonds .. " diamond" .. (s.stats.diamonds == 1 and "" or "s"),
  }
end

--- who: a friend, by name, for the bot to play as; nil for the owner.
function M.bot(s, rng, who)
  return M.as(s, who, require("games.craftworld.bot").choose, M, s, rng)
end

return M
