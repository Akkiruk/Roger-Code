-- games/blightmare/view_world.lua
-- The two views of the ground. drawWorld is the continent, a tile at a time, with the party in the middle of the wall. drawWalk
-- is the first-person view with its status strip and automap. Both paint once for each rev into a surface of their own, and
-- keep it to copy across, as Dungeon does: the shell redraws all the time, and most of those redraws change nothing.

local art = require("games.blightmare.art")
local overworld = require("games.blightmare.overworld")
local rules = require("games.blightmare.rules")
local scene = require("games.blightmare.scene")
local ui = require("lib.arcade.ui")
local world = require("games.blightmare.world")

local C = ui.C
local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min

local M = {}

local TILE_W, TILE_H = 6, 4          -- close to square, since a cell is 2 wide by 3 tall
local GRASS_SIGHT = 2.5              -- how many tiles anyone can see from inside tall grass
local NAME_NEAR = 8                  -- a site's name shows from this many tiles off
local HUD_Y = scene.VIEW_H           -- the status strip, under the view
local HUD_RIGHT = 105                -- the shell's SAVE & QUIT starts just past this
local MAP_COLS, MAP_ROWS = 15, 11
local MAP_CELL_W = 2                 -- a map square is 2 cells wide and 1 tall, as near to square as a small map can be
local MAP_MARGIN = 1

local FACING_MARK = { "^", ">", "v", "<" }
local ACT_WORD = { foe = "FIGHT", npc = "TALK", chest = "OPEN", door = "OPEN", locked = "UNLOCK" }

-- ---------------------------------------------------------------- pictures

-- One for each ground, per wall of a cabinet with two. A state's picture stands until its rev moves on.
local pictures = {}

local function drawCached(L, s, ground, paint)
  local picture
  for _, one in ipairs(pictures) do
    if one.ground == ground and one.state == s and one.L == L then picture = one end
  end
  local screen = ui.screen()
  if picture and picture.rev == s.rev and picture.surf.width == screen.width and picture.surf.height == screen.height then
    screen:drawSurface(picture.surf, 0, 0, L.W, L.H, 0, 0, L.W, L.H)
    return
  end
  if not picture then
    picture = table.remove(pictures, 1) or {}
    if #pictures < 3 then picture = {} end
    pictures[#pictures + 1] = picture
  end
  if not picture.surf or picture.surf.width ~= screen.width or picture.surf.height ~= screen.height then
    picture.surf = screen:copy()
  end
  ui.setScreen(picture.surf)
  paint(L, s)
  ui.setScreen(screen)
  picture.state, picture.rev, picture.L, picture.ground = s, s.rev, L, ground
  screen:drawSurface(picture.surf, 0, 0, L.W, L.H, 0, 0, L.W, L.H)
end

-- ---------------------------------------------------------------- the first-person view

--- A bar of filled cells, with the rest dark.
local function drawBar(x, y, w, share, color)
  ui.fill(x, y, w, 1, C.bg)
  ui.fill(x, y, max(share > 0 and 1 or 0, floor(w * min(1, share))), 1, color)
end

local function hpColor(share)
  if share > 0.5 then return C.ok end
  return share > 0.25 and C.warn or C.red
end

--- What ACT will do. The rules decide, so this can never disagree with what happens.
local function actWord(s)
  local target = rules.target(s)
  if target == "exit" then
    local x, y = world.ahead(s)
    return world.tileAt(s.map, x, y) == ">" and "GO DOWN" or "LEAVE"
  end
  return ACT_WORD[target or ""] or "MENU"
end

--- The strip along the bottom: the party on the left, where you are and what ACT does on the right, clear of SAVE & QUIT.
local function drawHud(L, s)
  local party = require("games.blightmare.party")
  local y = HUD_Y
  ui.fill(0, y, L.W, L.H - y, C.panel)
  ui.fill(0, y, L.W, 1, C.tie)
  for i, member in ipairs(s.party) do
    if i > 4 then break end
    local row = y + i * 2 - 1
    local st = party.stats(member)
    local share = member.hp / st.maxHp
    local ch = party.CHARS[member.id]
    ui.small(member.id == "hero" and s.heroName or (ch and ch.name or member.id), 2, row, C.text, C.panel, "left", 10)
    drawBar(13, row, 18, share, hpColor(share))
    ui.small(member.hp .. "/" .. st.maxHp, 32, row, hpColor(share), C.panel)
    if st.maxMp > 0 then
      drawBar(41, row, 8, member.mp / st.maxMp, C.accent)
      ui.small(member.mp .. "/" .. st.maxMp, 50, row, C.line, C.panel)
    end
  end
  local map = world.map(s.map)
  ui.small(map and map.name or "", 60, y + 1, C.line, C.panel, "left", HUD_RIGHT - 60)
  ui.small("GOLD " .. s.gold, 60, y + 3, C.hi, C.panel, "left", 20)
  ui.small("MIDDLE:", 60, y + 5, C.line, C.panel)
  ui.small(actWord(s), 68, y + 5, C.hi, C.panel)
end

local function mapInk(s, foes, x, y)
  local c = world.tileAt(s.map, x, y)
  if c == "#" or c == "h" or c == "W" then return C.panel end
  if foes[y * 1000 + x] then return C.red end
  if rules.chestAt(s, x, y) then return C.warn end
  if rules.npcAt(s, x, y) then return C.info end
  if not world.solid(s.map, x, y, s) then return c == ">" and C.hi or C.line end
  return c == "L" and C.red or C.warn
end

--- The automap in the top right corner, following the player, in runs of colour along each row.
local function drawMap(L, s)
  local boxW, boxH = MAP_COLS * MAP_CELL_W + 2, MAP_ROWS + 2
  local x0, y0 = L.W - boxW - MAP_MARGIN, MAP_MARGIN
  ui.fill(x0, y0, boxW, boxH, C.bg)
  ui.frame(x0, y0, boxW, boxH, C.tie)
  local foes = {}
  for _, f in ipairs(s.foes or {}) do foes[f.y * 1000 + f.x] = true end
  local left, top = s.x - floor(MAP_COLS / 2) - 1, s.y - floor(MAP_ROWS / 2) - 1
  for row = 1, MAP_ROWS do
    local from, ink = 1, mapInk(s, foes, left + 1, top + row)
    for col = 2, MAP_COLS + 1 do
      local here = col <= MAP_COLS and mapInk(s, foes, left + col, top + row) or nil
      if here ~= ink then
        if ink ~= C.bg then ui.fill(x0 + 1 + (from - 1) * MAP_CELL_W, y0 + row, (col - from) * MAP_CELL_W, 1, ink) end
        from, ink = col, here
      end
    end
  end
  local px, py = x0 + 1 + floor(MAP_COLS / 2) * MAP_CELL_W, y0 + 1 + floor(MAP_ROWS / 2)
  ui.small(FACING_MARK[s.dir] .. " ", px, py, C.bg, C.hi)
end

local function paintWalk(L, s)
  scene.draw(floor((L.W - scene.VIEW_W) / 2), 0, s)
  local fx = s.fx or {}
  if (fx.hurt or 0) > 0 then ui.frame(0, 0, L.W, HUD_Y, C.red, 2) end
  drawMap(L, s)
  drawHud(L, s)
end

function M.drawWalk(L, s) drawCached(L, s, "walk", paintWalk) end

-- ---------------------------------------------------------------- the tiles

--- Road-like, for the shape of a road that bends: sites and bridges join it.
local function joins(x, y)
  local c = overworld.tileAt(x, y)
  return c == "=" or c == "B" or c == "O"
end

--- A number from 0 to 99 that's always the same for the same tile.
local function speck(x, y) return (x * 37 + y * 101 + x * y * 13) % 100 end

local function paintGrass(px, py, v)
  ui.fill(px, py, TILE_W, TILE_H, C.hiTint)
  if v < 22 then
    ui.fill(px + v % 5, py + v % 3, 1, 1, C.ok)
  elseif v > 86 then
    ui.fill(px + v % 4, py + 1 + v % 3, 2, 1, C.panel)
  end
end

local function paintTallGrass(px, py, v)
  -- blades standing close, dark at the foot: it should look like it could hide something, not like a lawn
  ui.fill(px, py, TILE_W, TILE_H, C.hiTint)
  ui.fill(px, py + 3, TILE_W, 1, C.panel)
  local a, b, c = v % 2, 2 + floor(v / 7) % 2, 4 + floor(v / 13) % 2
  ui.fill(px + a, py + v % 3, 1, 4 - v % 3, C.ok)
  ui.fill(px + b, py + floor(v / 3) % 2, 1, 3, C.ok)
  ui.fill(px + c, py + 1 + floor(v / 5) % 2, 1, 2, C.ok)
  ui.fill(px + b, py + floor(v / 3) % 2, 1, 1, C.soft)
end

--- One pine, lit down its left side, with anything outside the tile at px cut off.
local function paintPine(px, py, at, tip)
  local function cut(x, y, w, color)
    local from, to = max(x, px), min(x + w, px + TILE_W)
    if to > from then ui.fill(from, y, to - from, 1, color) end
  end
  cut(at + 2, py, 2, tip)
  cut(at + 1, py + 1, 4, C.panel)
  cut(at + 1, py + 1, 1, tip)
  cut(at, py + 2, 6, C.panel)
  cut(at, py + 2, 1, tip)
  cut(at + 2, py + 3, 2, C.redTint)
end

local function paintForest(px, py, y, v)
  ui.fill(px, py, TILE_W, TILE_H, C.bg)
  -- staggered like bricks, every other row half a tile along, or a wood comes out as stripes
  local tip = v < 18 and C.soft or C.ok
  if y % 2 == 0 then
    paintPine(px, py, px, tip)
  else
    paintPine(px, py, px - 3, tip)
    paintPine(px, py, px + 3, tip)
  end
end

local function paintMountain(px, py, v)
  ui.fill(px, py, TILE_W, TILE_H, C.panel)
  local lean = v % 2
  if v % 7 == 0 then
    -- a bare shoulder between the peaks
    ui.fill(px, py + 2, TILE_W, 1, C.tie)
    ui.fill(px + 1, py + 1, 3, 1, C.tie)
    ui.fill(px, py + 3, TILE_W, 1, C.tie)
    return
  end
  ui.fill(px + 2 + lean, py, 1, 1, C.text)
  ui.fill(px + 1 + lean, py + 1, 3, 1, C.line)
  ui.fill(px + 2 + lean, py + 1, 1, 1, C.text)
  ui.fill(px + lean, py + 2, 5, 1, C.tie)
  ui.fill(px + 1 + lean, py + 2, 2, 1, C.line)
  ui.fill(px, py + 3, TILE_W, 1, C.tie)
  ui.fill(px + 3 + lean, py + 3, 3 - lean, 1, C.panel)
end

local function paintRoad(px, py, x, y)
  ui.fill(px, py, TILE_W, TILE_H, C.hiTint)
  local n, e, s, w = joins(x, y - 1), joins(x + 1, y), joins(x, y + 1), joins(x - 1, y)
  ui.fill(px + 2, py + 1, 2, 2, C.warn)
  if w then ui.fill(px, py + 1, 2, 2, C.warn) end
  if e then ui.fill(px + 4, py + 1, 2, 2, C.warn) end
  if n then ui.fill(px + 2, py, 2, 1, C.warn) end
  if s then ui.fill(px + 2, py + 3, 2, 1, C.warn) end
end

local function paintSwamp(px, py, v)
  ui.fill(px, py, TILE_W, TILE_H, C.panel)
  ui.fill(px + v % 3, py + 1 + v % 2, 3, 1, C.blueTint)
  ui.fill(px + (v + 2) % 5, py + 3, 2, 1, C.blueTint)
  ui.fill(px + (v + 4) % 6, py, 1, 2, C.hiTint)
  if v > 60 then ui.fill(px + (v + 1) % 6, py + 1, 1, 2, C.ok) end
end

local function paintSea(px, py, x, y, v)
  ui.fill(px, py, TILE_W, TILE_H, C.blueTint)
  -- foam on the shore, and the odd long swell out in the deep
  if overworld.tileAt(x, y - 1) ~= "~" and y > 1 then
    ui.fill(px, py, TILE_W, 1, C.tie)
  elseif v < 16 then
    ui.fill(px + v % 3, py + 1 + v % 2, 3, 1, C.blue)
  end
end

local function paintWall(px, py, x, y)
  ui.fill(px, py, TILE_W, TILE_H, C.line)
  if overworld.tileAt(x, y - 1) == "W" or overworld.tileAt(x, y + 1) == "W" then
    -- running north to south it shows its top: lit on the Empire's side, its shadow thrown on the Heart
    ui.fill(px, py, 2, TILE_H, C.text)
    ui.fill(px + 4, py, 2, TILE_H, C.tie)
    if y % 2 == 0 then ui.fill(px + 2, py + 1, 2, 2, C.tie) end
  else
    -- running east to west it shows its face, in courses of block
    ui.fill(px, py, TILE_W, 1, C.text)
    ui.fill(px, py + 3, TILE_W, 1, C.tie)
    ui.fill(px + (x % 2) * 3, py + 1, 1, 2, C.tie)
  end
end

local function paintBridge(px, py, x, y)
  paintSea(px, py, x, y, 99)
  if joins(x - 1, y) or joins(x + 1, y) then
    ui.fill(px, py, TILE_W, TILE_H - 1, C.redTint)
    ui.fill(px, py, TILE_W, 1, C.warn)
    ui.fill(px + 2, py + 1, 1, 2, C.bg)
    ui.fill(px + 5, py + 1, 1, 2, C.bg)
  else
    ui.fill(px + 1, py, 4, TILE_H, C.redTint)
    ui.fill(px + 1, py, 1, TILE_H, C.warn)
    ui.fill(px + 2, py + 1, 3, 1, C.bg)
    ui.fill(px + 2, py + 3, 3, 1, C.bg)
  end
end

local function paintGate(px, py)
  ui.fill(px, py, TILE_W, 1, C.red)
  ui.fill(px + 1, py, 1, TILE_H, C.text)
  ui.fill(px + 4, py, 1, TILE_H, C.text)
  ui.fill(px, py + 2, TILE_W, 1, C.red)
end

-- A place on the map, 6 wide and 4 tall, on top of its ground.
local function paintTown(px, py, roof)
  ui.fill(px, py + 2, 2, 2, C.line)
  ui.fill(px + 3, py + 2, 3, 2, C.line)
  ui.fill(px, py + 1, 2, 1, roof)
  ui.fill(px + 3, py + 1, 3, 1, roof)
  ui.fill(px + 4, py, 1, 1, roof)
  ui.fill(px + 4, py + 2, 1, 2, C.redTint)
end

local function paintMine(px, py)
  ui.fill(px, py, TILE_W, TILE_H, C.tie)
  ui.fill(px + 1, py, 4, 1, C.warn)
  ui.fill(px + 1, py, 1, TILE_H, C.warn)
  ui.fill(px + 4, py, 1, TILE_H, C.warn)
  ui.fill(px + 2, py + 1, 2, 3, C.bg)
end

local function paintSite(px, py, x, y)
  paintGrass(px, py, 50)
  local site = overworld.siteAt(x, y)
  if not site then
    paintTown(px, py, C.tie)
  elseif site.id == "mine" then
    paintMine(px, py)
  else
    paintTown(px, py, C.red)
  end
end

local function paintTile(px, py, x, y)
  local c = overworld.tileAt(x, y)
  local v = speck(x, y)
  if c == "~" then
    paintSea(px, py, x, y, v)
  elseif c == "." then
    paintGrass(px, py, v)
  elseif c == '"' then
    paintTallGrass(px, py, v)
  elseif c == "T" then
    paintForest(px, py, y, v)
  elseif c == "^" then
    paintMountain(px, py, v)
  elseif c == "=" then
    paintRoad(px, py, x, y)
  elseif c == "s" then
    paintSwamp(px, py, v)
  elseif c == "W" then
    paintWall(px, py, x, y)
  elseif c == "B" then
    paintBridge(px, py, x, y)
  else
    paintSite(px, py, x, y)
  end
  if overworld.gateAt(x, y) then paintGate(px, py) end
end

--- The party: a figure in the hero's rags, with a tick on the side they're walking toward.
local function paintParty(px, py, heading)
  ui.fill(px + 1, py - 1, 4, TILE_H + 1, C.bg)
  ui.fill(px + 2, py - 1, 2, 1, C.warn)
  ui.fill(px + 2, py, 2, 2, C.text)
  ui.fill(px + 2, py + 2, 1, 1, C.tie)
  ui.fill(px + 3, py + 2, 1, 1, C.tie)
  if heading then
    local d = world.DIRS[heading]
    ui.fill(px + 2 + d[1] * 4, py + 1 + d[2] * 3, 2, 1, C.hi)
  end
end

local function drawSiteNames(L, s, ox, oy, sight)
  for _, site in ipairs(overworld.SITES) do
    local dx, dy = site.x - s.wx, site.y - s.wy
    local shown = not site.when or (s.flags and s.flags[site.when])
    if shown and max(math.abs(dx), math.abs(dy)) <= sight then
      local px = ox + dx * TILE_W + floor(TILE_W / 2)
      local py = oy + dy * TILE_H - 2
      if py >= 1 and py < L.H - 1 then ui.small(" " .. site.name .. " ", px, py, C.text, C.bg, "center") end
    end
  end
end

local function paintWorld(L, s)
  local ox, oy = floor((L.W - TILE_W) / 2), floor((L.H - TILE_H) / 2)
  local deep = overworld.tileAt(s.wx, s.wy) == '"'
  local cols, rows = ceil(ox / TILE_W), ceil(oy / TILE_H)
  for dy = -rows, rows do
    for dx = -cols, cols do
      local px, py = ox + dx * TILE_W, oy + dy * TILE_H
      local x, y = s.wx + dx, s.wy + dy
      if deep and dx * dx + dy * dy > GRASS_SIGHT * GRASS_SIGHT then
        paintTallGrass(px, py, speck(x, y))
      else
        paintTile(px, py, x, y)
      end
    end
  end
  paintParty(ox, oy, s.heading)
  drawSiteNames(L, s, ox, oy, deep and GRASS_SIGHT or NAME_NEAR)
  local region = overworld.region(s.wx, s.wy)
  local name = overworld.REGION_NAME[region or ""]
  if name then ui.small(" " .. name .. " ", 1, 1, C.text, C.bg) end
end

function M.drawWorld(L, s) drawCached(L, s, "world", paintWorld) end

M.portrait = art.portrait -- the talk and menu views can reach a face from here too

return M
