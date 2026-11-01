-- games/dungeon/scene.lua
-- The first-person view. The camera stands at the back of its square, so the wall in front is about two thirds of the
-- wall of the monitor. A square at distance z is TILE_W / z cells wide and TILE_H / z tall: a cell is 2 wide to 3 tall,
-- which is why these differ. Every face that can show is baked once into a flat list of fills, for each place in the view
-- it can stand. Painting is far to near, so a turn is only a short walk down those lists.

local art = require("games.dungeon.art")
local rules = require("games.dungeon.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor, max, min = math.floor, math.max, math.min

local M = {}

local VIEW_W, VIEW_H = 121, 66
local CX, CY = VIEW_W / 2, VIEW_H / 2
local TILE_W, TILE_H = 80, 160 / 3
local FARTHEST = 5                  -- the last row of squares drawn
local COURSES, BLOCKS = 5, 3        -- stone blocks in a wall, up it and along it
M.VIEW_W, M.VIEW_H = VIEW_W, VIEW_H

--- Colours of stone by how far away it is: main, the odd darker block, mortar, and the lit top edge of a block.
local STONE = {
  { C.line, C.tie, C.panel, C.text },
  { C.tie, C.tie, C.panel, C.line },
  { C.tie, C.panel, C.bg, C.line },
  { C.panel, C.panel, C.bg, C.tie },
  { C.panel, C.bg, C.bg, C.panel },
  { C.bg, C.bg, C.bg, C.panel },
}
-- Floor and ceiling by distance: two colours each, in a checker that moves as you walk.
local FLOOR = { { C.tie, C.hiTint }, { C.hiTint, C.panel }, { C.panel, C.hiTint }, { C.panel, C.bg }, { C.bg, C.bg } }
local CEILING = { { C.panel, C.tie }, { C.panel, C.bg }, { C.panel, C.bg }, { C.bg, C.panel }, { C.bg, C.bg } }
-- Colours fade with distance, each one a step darker.
local FADE = {
  [C.text] = C.line, [C.line] = C.tie, [C.tie] = C.panel, [C.panel] = C.bg, [C.red] = C.redTint, [C.warn] = C.redTint,
  [C.hi] = C.warn, [C.ok] = C.hiTint, [C.soft] = C.ok, [C.accent] = C.blueTint, [C.info] = C.blueTint, [C.blue] = C.blueTint,
  [C.redTint] = C.panel, [C.hiTint] = C.panel, [C.blueTint] = C.panel,
}
local FLASH = {}
for from in pairs(FADE) do FLASH[from] = C.text end
FLASH[C.text] = C.red

local function round(v) return floor(v + 0.5) end

--- A rectangle into a list, trimmed to the view.
local function add(list, x, y, w, h, color)
  local x2, y2 = min(x + w, VIEW_W), min(y + h, VIEW_H)
  x, y = max(x, 0), max(y, 0)
  if x2 <= x or y2 <= y then return end
  local n = #list
  list[n + 1], list[n + 2], list[n + 3], list[n + 4], list[n + 5] = x, y, x2 - x, y2 - y, color
end

--- A number from 0 to 99 that's always the same for the same block.
local function hash(a, b, c) return (a * 37 + b * 101 + c * 59 + a * b * 13) % 100 end

--- Stone blocks on a face square-on to the camera.
local function stoneFront(list, x1, y1, x2, y2, shade, variant)
  local ramp = STONE[shade]
  add(list, x1, y1, x2 - x1, y2 - y1, ramp[1])
  local tall = (y2 - y1) / COURSES
  if tall < 2 then return end
  for course = 0, COURSES - 1 do
    local top, bottom = y1 + round(tall * course), y1 + round(tall * (course + 1))
    local shift = (course + variant) % 2 == 0 and 0 or 0.5
    for block = -1, BLOCKS do
      local from = max(x1, x1 + round((block + shift) / BLOCKS * (x2 - x1)))
      local to = min(x2, x1 + round((block + 1 + shift) / BLOCKS * (x2 - x1)))
      if to > from then
        local look = hash(course, block, variant)
        if look < 30 then add(list, from, top, to - from, bottom - top, ramp[2]) end
        if tall >= 4 then add(list, from, top + 1, to - from - 1, 1, ramp[4]) end
        add(list, to - 1, top, 1, bottom - top, ramp[3])
        -- a crack across a few of the near blocks
        if tall >= 8 and look % 7 == 0 then
          add(list, from + 3, top + 3, 4, 1, ramp[3])
          add(list, from + 6, top + 4, 3, 1, ramp[3])
          add(list, from + 8, top + 5, 2, 1, ramp[3])
        end
      end
    end
    add(list, x1, top, x2 - x1, 1, ramp[3])
  end
end

local PLANK_WOOD = { C.redTint, C.redTint, C.redTint, C.redTint, C.panel, C.bg }
local PLANK_DARK = { C.warn, C.bg, C.bg, C.panel, C.bg, C.bg }
local IRON = { C.line, C.line, C.tie, C.tie, C.panel, C.bg }

--- A heavy door in a stone frame. A locked one has red bands and a padlock you can see from down the hall.
local function doorFront(list, x1, y1, x2, y2, shade, locked, variant)
  stoneFront(list, x1, y1, x2, y2, shade, variant)
  local w, h = x2 - x1, y2 - y1
  local inX, top = round(w * 0.14), round(h * 0.1)
  local dx1, dx2, dy1 = x1 + inX, x2 - inX, y1 + top
  local wood, dark, iron = PLANK_WOOD[shade], PLANK_DARK[shade], IRON[shade]
  add(list, dx1 - 1, dy1 - 1, dx2 - dx1 + 2, y2 - dy1 + 1, STONE[shade][3])
  add(list, dx1, dy1, dx2 - dx1, y2 - dy1, wood)
  for plank = 1, 3 do
    add(list, dx1 + round((dx2 - dx1) * plank / 4), dy1, 1, y2 - dy1, dark)
  end
  local band = locked and (shade <= 3 and C.red or C.redTint) or iron
  local bandH = max(1, round(h * 0.05))
  add(list, dx1, dy1 + round(h * 0.16), dx2 - dx1, bandH, band)
  add(list, dx1, dy1 + round(h * 0.62), dx2 - dx1, bandH, band)
  if h >= 12 then
    local cx = round((dx1 + dx2) / 2)
    local cy = dy1 + round(h * 0.42)
    if locked then
      local size = max(2, round(h * 0.08))
      add(list, cx - size, cy - size, size * 2, size * 2, C.hi)
      add(list, cx - round(size / 2), cy - size * 2, size, size, C.line)
      add(list, cx, cy - round(size / 2), 1, size, C.bg)
    else
      add(list, dx2 - round(w * 0.1), cy, max(1, round(w * 0.04)), max(1, round(h * 0.05)), C.hi)
    end
  end
end

--- An arch with steps going down into the dark, and a warm light at its rim so it reads from far off.
local function stairsFront(list, x1, y1, x2, y2, shade, variant)
  stoneFront(list, x1, y1, x2, y2, shade, variant)
  local w, h = x2 - x1, y2 - y1
  local inX, top = round(w * 0.1), round(h * 0.08)
  local ax1, ax2, ay1 = x1 + inX, x2 - inX, y1 + top
  add(list, ax1 - 1, ay1 - 1, ax2 - ax1 + 2, y2 - ay1 + 1, shade <= 4 and C.hi or C.warn)
  add(list, ax1, ay1, ax2 - ax1, y2 - ay1, C.bg)
  local ramp = { C.text, C.line, C.tie, C.panel, C.bg }
  if shade > 2 then ramp = { C.line, C.tie, C.panel, C.bg, C.bg } end
  if shade > 3 then ramp = { C.tie, C.panel, C.bg, C.bg, C.bg } end
  local steps = #ramp
  for step = 1, steps do
    local share = (steps - step) / steps
    local inset = round((ax2 - ax1) * 0.32 * (1 - share))
    local y = ay1 + round((y2 - ay1) * (0.38 + 0.62 * share))
    local bottom = ay1 + round((y2 - ay1) * (0.38 + 0.62 * (share + 1 / steps)))
    add(list, ax1 + inset, y, ax2 - ax1 - inset * 2, max(1, bottom - y), ramp[steps - step + 1])
    add(list, ax1 + inset, y, ax2 - ax1 - inset * 2, 1, C.bg)
  end
end

--- Stone on a face running away from the camera, a column at a time. edge is its offset from the camera's line.
local function stoneSide(list, edge, nearZ, farZ, row, variant)
  local xNear, xFar = CX + edge * TILE_W / nearZ, CX + edge * TILE_W / farZ
  local from, to = round(min(xNear, xFar)), round(max(xNear, xFar)) - 1
  for col = max(from, 0), min(to, VIEW_W - 1) do
    local z = edge * TILE_W / (col + 0.5 - CX)
    local half = TILE_H / 2 / z
    local top, bottom = round(CY - half), round(CY + half)
    -- a touch darker than a face at the same distance, with the odd column dithered to the next shade
    local depth = z + 0.55
    local shade = min(#STONE, floor(depth + ((col % 2 == 0) and 0.3 or 0)))
    local ramp = STONE[shade]
    add(list, col, top, 1, bottom - top, ramp[1])
    local tall = (bottom - top) / COURSES
    if tall >= 2 then
      local u = (z - nearZ) / (farZ - nearZ)
      for course = 0, COURSES - 1 do
        local y = top + round(tall * course)
        local spot = u * BLOCKS + ((course + variant) % 2 == 0 and 0 or 0.5)
        local block = floor(spot)
        local next_ = top + round(tall * (course + 1))
        if hash(course, block + row * 3, variant) < 30 then add(list, col, y, 1, next_ - y, ramp[2]) end
        add(list, col, y, 1, 1, ramp[3])
        local nextCol = u + 1 / ((farZ - nearZ) * TILE_W * math.abs(edge) / (z * z))
        if floor(nextCol * BLOCKS + (spot - u * BLOCKS)) ~= block then add(list, col, y, 1, next_ - y, ramp[3]) end
      end
    end
  end
end

-- ---------------------------------------------------------------- the baked faces

--- Floor and ceiling together, in runs along each row. parity flips as you step, which is what shows you moving.
local function bakeGround(parity)
  local list = {}
  for row = 0, VIEW_H - 1 do
    local below = row + 0.5 > CY
    local z = (TILE_H / 2) / math.abs(row + 0.5 - CY)
    local band = min(FARTHEST, max(1, floor(z)))
    local paint = below and FLOOR[band] or CEILING[band]
    if z >= FARTHEST then
      add(list, 0, row, VIEW_W, 1, C.bg)
    else
      local from = 0
      local inkOf = function(col)
        local lateral = (col + 0.5 - CX) * z / TILE_W
        return paint[(floor(lateral + 0.5) + floor(z) + parity) % 2 + 1]
      end
      local ink = inkOf(0)
      for col = 1, VIEW_W do
        local here = col < VIEW_W and inkOf(col) or nil
        if here ~= ink then
          add(list, from, row, col - from, 1, ink)
          from, ink = col, here
        end
      end
    end
  end
  return list
end

--- How many squares either side of the middle a row can show.
local function lateralsOf(row) return floor(0.75 * row + 1) end

local FRONT_KINDS = { "wall0", "wall1", "torch", "door", "locked", "stairs" }

--- A burning torch in an iron bracket, for a little warmth in the stone.
local function torchOn(list, x1, y1, x2, y2)
  local h = y2 - y1
  local cx, top = round((x1 + x2) / 2), y1 + round(h * 0.26)
  local size = max(1, round(h / 30))
  add(list, cx - size * 3, top - size * 3, size * 6, size * 7, C.redTint)
  add(list, cx - size, top + size * 3, size * 2, size * 6, C.panel)
  add(list, cx - size * 2, top + size * 4, size * 4, size, C.line)
  add(list, cx - size * 2, top - size, size * 4, size * 4, C.warn)
  add(list, cx - size, top - size * 3, size * 2, size * 3, C.warn)
  add(list, cx - size, top, size * 2, size * 2, C.hi)
end

local function bakeFront(kind, row, l, shadeVariant)
  local list = {}
  local z = row
  local shade = min(#STONE, row)
  local x1 = round(CX + (l - 0.5) * TILE_W / z)
  local x2 = round(CX + (l + 0.5) * TILE_W / z)
  local y1, y2 = round(CY - TILE_H / 2 / z), round(CY + TILE_H / 2 / z)
  if kind == "wall0" or kind == "wall1" then
    stoneFront(list, x1, y1, x2, y2, shade, shadeVariant)
  elseif kind == "torch" then
    stoneFront(list, x1, y1, x2, y2, shade, 0)
    torchOn(list, x1, y1, x2, y2)
  elseif kind == "stairs" then
    stairsFront(list, x1, y1, x2, y2, shade, 0)
  else
    doorFront(list, x1, y1, x2, y2, shade, kind == "locked", 0)
  end
  return list
end

local fronts, sides, ground

--- Build every face for every place in the view, the first time anything is drawn.
local function bakeAll()
  if fronts then return end
  fronts, sides = {}, {}
  ground = { bakeGround(0), bakeGround(1) }
  for row = 0, FARTHEST do
    fronts[row], sides[row] = {}, {}
    for l = -lateralsOf(row), lateralsOf(row) do
      fronts[row][l] = {}
      if row > 0 then
        for i, kind in ipairs(FRONT_KINDS) do fronts[row][l][kind] = bakeFront(kind, row, l, i - 1) end
      end
      if l ~= 0 then
        local edge = l < 0 and l + 0.5 or l - 0.5
        sides[row][l] = { {}, {} }
        for v = 1, 2 do stoneSide(sides[row][l][v], edge, max(row, 0.3), row + 1, row, v - 1) end
      end
    end
  end
end
M.bakeAll = bakeAll

local function blit(ox, oy, list)
  local fill = ui.fill
  for i = 1, #list, 5 do fill(ox + list[i], oy + list[i + 1], list[i + 2], list[i + 3], list[i + 4]) end
end

local function drawRuns(ox, oy, runs)
  local fill = ui.fill
  for i = 1, #runs, 4 do fill(ox + runs[i], oy + runs[i + 1], runs[i + 2], 1, runs[i + 3]) end
end

--- A sprite standing on the floor at a place in the view. Its colours fade with distance.
local function drawSprite(ox, oy, name, row, l, flash)
  local sprite = art.SPRITES[name]
  local z = row + sprite.near
  local tileW, tileH = TILE_W / z, TILE_H / z
  local w, h = round(tileW * sprite.size), round(tileH * sprite.size)
  if w < 2 or h < 2 then return end
  local x = round(CX + l * tileW - w / 2)
  local y = round(CY + tileH / 2 - h)
  local remap, look
  if flash then
    remap, look = FLASH, "flash"
  elseif row >= 4 then
    remap, look = FADE, "fade"
  end
  drawRuns(ox + x, oy + y, art.bake(name, w, h, remap, look))
end

local function objectSprite(o)
  if o.kind == "chest" then return o.opened and "openChest" or "chest" end
  if o.kind == "trap" then return nil end
  return o.kind
end

--- The map square at a place in the view: row squares ahead, and l to the right. Row 0 is the player's own.
local function squareAt(s, row, l)
  local d = rules.DIRS[s.dir]
  return s.x + d[1] * row - d[2] * l, s.y + d[2] * row + d[1] * l
end

local function solid(c) return c == rules.WALL or c == rules.DOOR or c == rules.LOCKED or c == rules.STAIRS end

local FACE_OF = { [rules.DOOR] = "door", [rules.LOCKED] = "locked", [rules.STAIRS] = "stairs" }

local function paintSquare(ox, oy, s, row, l, things)
  local x, y = squareAt(s, row, l)
  local c = rules.tileAt(s, x, y)
  if solid(c) then
    local v = (x + y) % 2 + 1
    if l ~= 0 and sides[row][l] then blit(ox, oy, sides[row][l][v]) end
    if row > 0 and fronts[row][l] then
      local plain = (x * 7 + y * 13) % 5 == 0 and "torch" or ("wall" .. (v - 1))
      blit(ox, oy, fronts[row][l][FACE_OF[c] or plain])
    end
  end
  if row > 0 and row < FARTHEST then
    local key = y * rules.WIDTH + x
    local o = things.objs[key]
    if o then
      for _, one in ipairs(o) do
        local name = objectSprite(one)
        if name then drawSprite(ox, oy, name, row, l) end
      end
    end
    local m = things.mons[key]
    if m then drawSprite(ox, oy, m.kind, row, l, s.fx.flash > 0 and row == 1 and l == 0) end
  end
end

--- Index what's on the level by square, so a frame doesn't search the list for each place in the view.
local function indexThings(s)
  local things = { objs = {}, mons = {} }
  for _, o in ipairs(s.objs) do
    local key = o.y * rules.WIDTH + o.x
    local list = things.objs[key]
    if not list then
      list = {}
      things.objs[key] = list
    end
    list[#list + 1] = o
  end
  for _, m in ipairs(s.mons) do things.mons[m.y * rules.WIDTH + m.x] = m end
  return things
end

--- How far the corridor runs ahead before a solid square stops the eye: nothing behind that can show.
local function reach(s)
  for row = 1, FARTHEST do
    local x, y = squareAt(s, row, 0)
    if solid(rules.tileAt(s, x, y)) then return row end
  end
  return FARTHEST
end

--- Paint the corridor into the view rectangle at ox, oy.
function M.draw(ox, oy, s)
  bakeAll()
  blit(ox, oy, ground[(s.x + s.y) % 2 + 1])
  local things = indexThings(s)
  for row = reach(s), 0, -1 do
    local span = lateralsOf(row)
    for l = span, 1, -1 do
      paintSquare(ox, oy, s, row, -l, things)
      paintSquare(ox, oy, s, row, l, things)
    end
    paintSquare(ox, oy, s, row, 0, things)
  end
end

return M
