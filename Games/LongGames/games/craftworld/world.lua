-- games/craftworld/world.lua
-- The ground of CRAFT WORLD: blocks, the world made from a seed, the changes a player has made to it, and light.
-- Everything here is pure. A tile is a function of the seed and where it is, unless the player has changed it: the changes
-- are kept in the state as one short string for each chunk of 16 columns, three characters to a change, so the save holds
-- the seed and what was dug and built, never the world. What's worked out from those (columns, decoded changes) is kept in
-- caches outside the state, and rebuilt from it whenever it's a different state or a different seed.

local M = {}

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local CHUNK = 16
local HEIGHT = 176          -- rows from the sky's top (y = 0) to the bottom of the bedrock
local SEA = 46              -- ground lower than this fills with water; depth counts from here
local DIAMOND_DEPTH = 80
M.CHUNK, M.HEIGHT, M.SEA, M.DIAMOND_DEPTH = CHUNK, HEIGHT, SEA, DIAMOND_DEPTH

-- ---------------------------------------------------------------- blocks
-- hard: how much digging it takes (hits = hard / the tool's speed, at least 1). tier: the pickaxe it needs.
-- solid: stops walking and falling. opaque: stops the sky's light. drop: the item it gives.
local AIR, WATER = " ", "w"
M.AIR, M.WATER = AIR, WATER

local BLOCKS = {
  [" "] = { name = "Air" },
  w = { name = "Water", liquid = true },
  g = { name = "Grass", hard = 2, solid = true, opaque = true, drop = "dirt" },
  d = { name = "Dirt", hard = 2, solid = true, opaque = true, drop = "dirt" },
  a = { name = "Sand", hard = 2, solid = true, opaque = true, drop = "sand", falls = true },
  s = { name = "Stone", hard = 6, tier = 1, solid = true, opaque = true, drop = "cobble" },
  c = { name = "Cobblestone", hard = 6, tier = 1, solid = true, opaque = true, drop = "cobble" },
  l = { name = "Log", hard = 3, solid = true, opaque = true, drop = "log" },
  f = { name = "Leaves", hard = 1, solid = true, drop = "apple", chance = 4 },
  p = { name = "Planks", hard = 3, solid = true, opaque = true, drop = "planks" },
  k = { name = "Coal Ore", hard = 6, tier = 1, solid = true, opaque = true, drop = "coal", ore = 4 },
  i = { name = "Iron Ore", hard = 8, tier = 2, solid = true, opaque = true, drop = "iron_ore", ore = 9 },
  o = { name = "Gold Ore", hard = 8, tier = 3, solid = true, opaque = true, drop = "gold_ore", ore = 14 },
  x = { name = "Diamond Ore", hard = 10, tier = 3, solid = true, opaque = true, drop = "diamond", ore = 49 },
  B = { name = "Bedrock", solid = true, opaque = true },
  t = { name = "Torch", hard = 0, drop = "torch", light = true },
  T = { name = "Crafting Table", hard = 3, solid = true, opaque = true, drop = "table" },
  F = { name = "Furnace", hard = 6, tier = 1, solid = true, opaque = true, drop = "furnace" },
  D = { name = "Door", hard = 3, drop = "door", door = true },
  b = { name = "Bed", hard = 1, solid = true, drop = "bed", bed = true },
  y = { name = "Glass", hard = 1, solid = true, drop = "glass" },
}
M.BLOCKS = BLOCKS

function M.def(c) return BLOCKS[c] or BLOCKS[AIR] end
--- Stops a body: walking, falling, a mob. A door stops mobs, never the player.
function M.solid(c) return BLOCKS[c].solid == true end
function M.opaque(c) return BLOCKS[c].opaque == true end
--- Something there to dig, as opposed to air or water.
function M.diggable(c) return c ~= AIR and c ~= WATER end

-- ---------------------------------------------------------------- noise
-- Exact in doubles: every product stays well under 2^53.

local MOD = 2147483647

local function hash(a, b, salt)
  local h = (a * 73856093 + salt * 83492791 + 1013904223) % MOD
  h = h * 48271 % MOD
  h = (h + b * 19349663) % MOD
  h = h * 48271 % MOD
  h = (h + (h % 65536) * 31337 + salt) % MOD
  h = h * 48271 % MOD
  return h / MOD
end
M.hash = hash

local function smooth(t) return t * t * (3 - 2 * t) end

--- Smooth noise along x, 0 to 1, changing over about `scale` columns.
local function noise1(seed, x, scale, salt)
  local g = floor(x / scale)
  local t = smooth((x - g * scale) / scale)
  local a, b = hash(g, seed, salt), hash(g + 1, seed, salt)
  return a + (b - a) * t
end

-- ---------------------------------------------------------------- the land

--- Ground level at column x (the y of its top block), and whether it's desert.
local function ground(seed, x)
  local h = 42 + (noise1(seed, x, 26, 1) - 0.5) * 16 + (noise1(seed, x, 7, 2) - 0.5) * 5
  local hills = noise1(seed, x, 70, 3)
  if hills > 0.62 then h = h - (hills - 0.62) * 70 end
  local desert = noise1(seed, x, 53, 4) > 0.7
  return floor(h + 0.5), desert
end

--- A tree's trunk height at x, or nil. Trees stand two clear columns apart, on grass above the water.
local function treeAt(seed, x)
  local h, desert = ground(seed, x)
  if desert or h >= SEA then return nil end
  if hash(x, seed, 7) >= 0.16 or hash(x - 1, seed, 7) < 0.16 or hash(x - 2, seed, 7) < 0.16 then return nil end
  return 3 + floor(hash(x, seed, 8) * 3), h
end

--- Leaves round a trunk top at (tx, top): which cells of column x, row y, they fill.
local function leafAt(seed, tx, top, x, y)
  local dx, dy = x - tx, y - top
  if dy < -2 or dy > 1 then return false end
  if dy == -2 then return abs(dx) <= 1 end
  if abs(dx) > 2 then return false end
  if abs(dx) == 2 and dy ~= 0 then return hash(tx * 7 + dx, seed + dy, 9) < 0.5 end
  return true
end

local CAVE_W, CAVE_H = 13, 7
local BLOB_W, BLOB_H = 9, 6

--- Column x of the world, as it was made: a string of HEIGHT tiles, the first being y = 0.
local function makeColumn(seed, x)
  local h, desert = ground(seed, x)
  local cells = {}
  local soil = 3 + floor(hash(x, seed, 10) * 2)
  -- the corners of the cave noise on either side of this column, one for each grid row
  local gx, bx = floor(x / CAVE_W), floor(x / BLOB_W)
  local tx, tbx = smooth((x - gx * CAVE_W) / CAVE_W), smooth((x - bx * BLOB_W) / BLOB_W)
  local caveRow, blobRow = {}, {}
  for gy = 0, floor(HEIGHT / CAVE_H) + 1 do
    local a, b = hash(gx * 977 + gy, seed, 5), hash((gx + 1) * 977 + gy, seed, 5)
    caveRow[gy] = a + (b - a) * tx
  end
  for gy = 0, floor(HEIGHT / BLOB_H) + 1 do
    local a, b = hash(bx * 991 + gy, seed, 6), hash((bx + 1) * 991 + gy, seed, 6)
    blobRow[gy] = a + (b - a) * tbx
  end
  local function cave(y)
    local gy = floor(y / CAVE_H)
    local c0, c1 = caveRow[gy], caveRow[gy + 1]
    local n = c0 + (c1 - c0) * smooth((y - gy * CAVE_H) / CAVE_H)
    if abs(n - 0.5) < 0.05 then return true end
    local by = floor(y / BLOB_H)
    local b0, b1 = blobRow[by], blobRow[by + 1]
    return b0 + (b1 - b0) * smooth((y - by * BLOB_H) / BLOB_H) > 0.79
  end
  for y = 0, HEIGHT - 1 do
    local c
    if y >= HEIGHT - 3 then
      c = "B"
    elseif y >= HEIGHT - 5 and hash(x * 3 + y, seed, 11) < 0.5 then
      c = "B"
    elseif y < h then
      c = y >= SEA and WATER or AIR
    elseif y == h then
      c = (desert or h >= SEA) and "a" or "g"
    elseif y <= h + soil then
      c = (desert or h >= SEA) and "a" or "d"
    else
      c = "s"
      local depth = y - SEA
      if (y > h + 5 or (y > h + 2 and hash(x, seed, 12) < 0.08)) and cave(y) then
        c = AIR
      else
        -- ores come in clumps: a clump on a 2x2 grid, and some of its cells
        local clump = hash(floor(x / 2) * 613 + floor(y / 2), seed, 13)
        local cell = hash(x * 389 + y, seed, 14)
        if cell < 0.65 then
          if depth >= DIAMOND_DEPTH and clump < 0.010 then
            c = "x"
          elseif depth >= 40 and clump > 0.993 then
            c = "o"
          elseif depth >= 6 and clump > 0.025 and clump < 0.052 then
            c = "i"
          elseif clump > 0.94 and clump < 0.975 then
            c = "k"
          end
        end
      end
    end
    cells[y + 1] = c
  end
  -- trees, from this column and the two on either side
  for ox = x - 2, x + 2 do
    local height, th = treeAt(seed, ox)
    if height then
      local top = th - height
      for y = top - 2, th - 1 do
        if ox == x and y >= top then
          cells[y + 1] = "l"
        elseif cells[y + 1] == AIR and leafAt(seed, ox, top, x, y) then
          cells[y + 1] = "f"
        end
      end
    end
  end
  return table.concat(cells)
end

local columns = { seed = nil, n = 0, list = {} }
local COLUMNS_KEPT = 600

local function column(seed, x)
  if columns.seed ~= seed or columns.n > COLUMNS_KEPT then
    columns.seed, columns.n, columns.list = seed, 0, {}
  end
  local col = columns.list[x]
  if not col then
    col = makeColumn(seed, x)
    columns.list[x] = col
    columns.n = columns.n + 1
  end
  return col
end
M.column = column
M.ground = ground

-- ---------------------------------------------------------------- the player's changes

local DIGITS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-"
local VALUE = {}
for i = 1, 64 do VALUE[DIGITS:sub(i, i)] = i - 1 end

-- for each state, for each chunk: the string it was decoded from, and where each change sits in it
local decoded = setmetatable({}, { __mode = "k" })

local function chunkOf(x) return floor(x / CHUNK) end

local function changes(s, ci)
  local str = s.edits[ci]
  if not str then return nil end
  local per = decoded[s]
  if not per then
    per = {}
    decoded[s] = per
  end
  local entry = per[ci]
  if entry and entry.str == str then return entry end
  entry = { str = str, at = {} }
  for pos = 1, #str - 2, 3 do
    local idx = VALUE[str:sub(pos, pos)] * 64 + VALUE[str:sub(pos + 1, pos + 1)]
    entry.at[idx] = pos + 2
  end
  per[ci] = entry
  return entry
end

--- The tile at x, y as it is now. Above the sky is air, below the world is bedrock.
local function tileAt(s, x, y)
  if y < 0 then return AIR end
  if y >= HEIGHT then return "B" end
  local ci = chunkOf(x)
  local entry = changes(s, ci)
  if entry then
    local pos = entry.at[(x - ci * CHUNK) * HEIGHT + y]
    if pos then return entry.str:sub(pos, pos) end
  end
  local col = column(s.seed, x)
  return col:sub(y + 1, y + 1)
end
M.tileAt = tileAt

--- Change a tile. A change already made is changed in place, a new one goes on the end of its chunk's string.
function M.setTile(s, x, y, c)
  if y < 0 or y >= HEIGHT then return end
  local ci = chunkOf(x)
  local idx = (x - ci * CHUNK) * HEIGHT + y
  local entry = changes(s, ci)
  local str = s.edits[ci] or ""
  local pos = entry and entry.at[idx]
  if pos then
    str = str:sub(1, pos - 1) .. c .. str:sub(pos + 1)
  else
    local hi, lo = floor(idx / 64), idx % 64
    str = str .. DIGITS:sub(hi + 1, hi + 1) .. DIGITS:sub(lo + 1, lo + 1) .. c
    pos = #str
  end
  s.edits[ci] = str
  local per = decoded[s]
  if not per then
    per = {}
    decoded[s] = per
  end
  if not entry then entry = { at = {} } end
  entry.str, entry.at[idx] = str, pos
  per[ci] = entry
end

--- How many changes the state holds.
function M.changeCount(s)
  local n = 0
  for _, str in pairs(s.edits) do n = n + #str / 3 end
  return n
end

-- ---------------------------------------------------------------- light

local TORCH_R2 = 30          -- a torch lights about five blocks round
local GLOW_R2 = 8            -- the player sees a couple of blocks round them in the dark
local SKY_REACH = 3          -- daylight reaches this far into the ground and round cave mouths
local TORCH_SCAN = 6
M.TORCH_SCAN = TORCH_SCAN

--- The first row in column x that stops the sky's light.
local function skyTop(s, x)
  for y = 0, HEIGHT - 1 do
    if BLOCKS[tileAt(s, x, y)].opaque then return y end
  end
  return HEIGHT
end
M.skyTop = skyTop

--- Light over a window of the world: lit[row][col] for x0 .. x0+w-1 and y0 .. y0+h-1, each true or false, and sky[row][col]
--- for the cells open to the sky. px, py is the player, who glows a little.
function M.lightWindow(s, x0, y0, w, h, px, py)
  local tops = {}
  for x = x0 - SKY_REACH, x0 + w - 1 + SKY_REACH do tops[x] = skyTop(s, x) end
  local torches = {}
  for y = y0 - TORCH_SCAN, y0 + h - 1 + TORCH_SCAN do
    if y >= 0 and y < HEIGHT then
      for x = x0 - TORCH_SCAN, x0 + w - 1 + TORCH_SCAN do
        if tileAt(s, x, y) == "t" then torches[#torches + 1] = { x, y } end
      end
    end
  end
  local lit, sky = {}, {}
  for row = 1, h do
    local y = y0 + row - 1
    local litRow, skyRow = {}, {}
    for col = 1, w do
      local x = x0 + col - 1
      local on = false
      if y < tops[x] then
        skyRow[col] = true
        on = true
      else
        local best = 99
        for dx = -SKY_REACH, SKY_REACH do
          local d = abs(dx) + max(0, y - tops[x + dx] + 1)
          if d < best then best = d end
        end
        on = best <= SKY_REACH
        if not on and px then
          local gx, gy = x - px, y - py
          on = gx * gx + gy * gy <= GLOW_R2
        end
        if not on then
          for i = 1, #torches do
            local t = torches[i]
            local tx, ty = x - t[1], y - t[2]
            if tx * tx + ty * ty <= TORCH_R2 then
              on = true
              break
            end
          end
        end
      end
      litRow[col] = on
    end
    lit[row], sky[row] = litRow, skyRow
  end
  return lit, sky
end

--- Is one cell lit, by the sky or a torch (the player's own glow doesn't count: a mob can stand in it)?
function M.isLit(s, x, y)
  local lit = M.lightWindow(s, x, y, 1, 1)
  return lit[1][1]
end

--- How far down a row is, counted from the water level.
function M.depth(y) return max(0, y - SEA) end

return M
