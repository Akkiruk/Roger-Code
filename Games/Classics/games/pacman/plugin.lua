-- games/pacman/plugin.lua
-- Pac-Man as an Arcade classic. A tap sets a direction, by the arrows or on the board, and Pac-Man takes it at the
-- next junction that allows it. Tiles are 4 wide and 3 tall, which looks nearly square on a monitor.

local base = require("lib.arcade.base")
local rules = require("games.pacman.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local COLS, ROWS = rules.COLS, rules.ROWS
local CELL_W, CELL_H = 4, 3
local FLASH_TICKS = 13 -- ghosts flash for this long before they stop being frightened

local GHOST_COLORS = { blinky = C.red, pinky = C.accent, inky = C.info, clyde = C.warn }
local FRUIT_COLORS = { C.red, C.warn, C.ok, C.accent, C.info, C.hi, C.text, C.soft }

-- Sprites, one string for each row. A marked cell takes the sprite's colour; "." is left as it is.
-- They are bigger than a tile, as in the arcade game: they lap over the wall edges but never reach the next dot.
local SPRITE_W, SPRITE_H = 6, 5
local PAC_SHUT = { ".####.", "######", "######", "######", ".####." }
local PAC_OPEN = {
  right = { ".####.", "####..", "###...", "####..", ".####." },
  left = { ".####.", "..####", "...###", "..####", ".####." },
  up = { ".#..#.", "##..##", "###.##", "######", ".####." },
  down = { ".####.", "######", "###.##", "##..##", ".#..#." },
}
local PAC_GONE = {
  PAC_SHUT,
  { "......", ".####.", ".####.", ".####.", "......" },
  { "......", "......", "..##..", "......", "......" },
}
local GHOST_BODY = {
  { ".####.", "######", "######", "######", "#.##.#" },
  { ".####.", "######", "######", "######", ".#..#." },
}
-- A ghost's eyes in each direction: how far right they sit, then the pupil's column and row in each eye.
local EYES = {
  left = { 0, 0, 1 }, right = { 1, 1, 1 }, up = { 0, 1, 0 }, down = { 1, 0, 1 },
}

local function tileX(L, x) return L.x0 + (x - 1) * CELL_W end
local function tileY(L, y) return L.y0 + (y - 1) * CELL_H end

local function spriteX(L, x) return tileX(L, x) - (SPRITE_W - CELL_W) / 2 end
local function spriteY(L, y) return tileY(L, y) - (SPRITE_H - CELL_H) / 2 end

local function isWall(x, y)
  local row = rules.GRID[y]
  return not row or row[x] == nil or row[x] == "#"
end

--- The maze never changes, so its rectangles are worked out once: dark blocks, with bright edges on corridor sides.
local function buildWalls()
  local fills, edges = {}, {}
  for y = 1, ROWS do
    local x = 1
    while x <= COLS do
      if rules.GRID[y][x] == "#" then
        local from = x
        while x < COLS and rules.GRID[y][x + 1] == "#" do x = x + 1 end
        fills[#fills + 1] = { from, y, x - from + 1 }
      end
      x = x + 1
    end
  end
  local runs = {}
  -- an edge that carries straight on from the last one along its line just makes that one longer
  local function edge(x, y, ox, oy, w, h)
    local left, top = (x - 1) * CELL_W + ox, (y - 1) * CELL_H + oy
    local line = (w > h and "row" or "col") .. (w > h and top or left)
    local last = runs[line]
    if last and w > h and last[1] + last[3] == left then
      last[3] = last[3] + w
    elseif last and h > w and last[2] + last[4] == top then
      last[4] = last[4] + h
    else
      last = { left, top, w, h }
      runs[line] = last
      edges[#edges + 1] = last
    end
  end
  for y = 1, ROWS do
    for x = 1, COLS do
      if rules.GRID[y][x] == "#" then
        if y > 1 and not isWall(x, y - 1) then edge(x, y, 0, 0, CELL_W, 1) end
        if y < ROWS and not isWall(x, y + 1) then edge(x, y, 0, CELL_H - 1, CELL_W, 1) end
        if x > 1 and not isWall(x - 1, y) then edge(x, y, 0, 0, 1, CELL_H) end
        if x < COLS and not isWall(x + 1, y) then edge(x, y, CELL_W - 1, 0, 1, CELL_H) end
      end
    end
  end
  return fills, edges
end

local WALL_FILLS, WALL_EDGES = buildWalls()

local function drawSprite(sprite, x, y, color)
  for row, line in ipairs(sprite) do
    for col = 1, #line do
      if line:sub(col, col) == "#" then ui.fill(x + col - 1, y + row - 1, 1, 1, color) end
    end
  end
end

local function drawMaze(L, s)
  for _, r in ipairs(WALL_FILLS) do
    ui.fill(tileX(L, r[1]), tileY(L, r[2]), r[3] * CELL_W, CELL_H, C.blueTint)
  end
  local cleared = s.after == "level" and s.frame % 2 == 0
  for _, r in ipairs(WALL_EDGES) do
    ui.fill(L.x0 + r[1], L.y0 + r[2], r[3], r[4], cleared and C.text or C.blue)
  end
  for y = 1, ROWS do
    for x = 1, COLS do
      if rules.GRID[y][x] == "-" then ui.fill(tileX(L, x), tileY(L, y) + 1, CELL_W, 1, C.line) end
    end
  end
end

local function drawDots(L, s)
  local pellet = s.frame % 6 < 3 and C.text or C.line
  for y = 1, ROWS do
    for x, c in pairs(s.dots[y]) do
      if c == "." then
        ui.fill(tileX(L, x) + 1, tileY(L, y) + 1, 2, 1, C.text)
      else
        base.disc(tileX(L, x), tileY(L, y), CELL_W, CELL_H, pellet)
      end
    end
  end
end

local function drawFruit(L, s)
  if not s.fruit then return end
  local x, y = spriteX(L, rules.FRUIT_AT[1]), spriteY(L, rules.FRUIT_AT[2])
  base.disc(x, y, SPRITE_W, SPRITE_H, FRUIT_COLORS[math.min(s.level, #FRUIT_COLORS)])
  ui.fill(x + 3, y, 1, 1, C.ok)
end

--- A small mark beside Pac-Man while a turn is waiting, so a tap always shows it landed.
local function drawWaiting(L, s)
  local p = s.pac
  if s.want == p.dir then return end
  local d = rules.DIRECTIONS[s.want]
  ui.fill(tileX(L, p.x) + 1 + d[1] * 5, tileY(L, p.y) + 1 + d[2] * 4, 2, 1, C.hi)
end

local function drawPac(L, s)
  local p = s.pac
  local x, y = spriteX(L, p.x), spriteY(L, p.y)
  if s.after == "life" then
    drawSprite(PAC_GONE[math.max(1, 3 - math.floor(s.pause / 3))], x, y, C.hi)
    return
  end
  local moving = p.x ~= p.px or p.y ~= p.py
  drawSprite((moving and s.frame % 2 == 0) and PAC_SHUT or PAC_OPEN[p.dir], x, y, C.hi)
end

local function ghostColor(s, g)
  if not g.scared then return GHOST_COLORS[g.name] end
  local flashing = s.frightLeft <= FLASH_TICKS and s.frame % 2 == 0
  return flashing and C.text or C.blue
end

local function drawEyes(x, y, dir)
  local e = EYES[dir]
  for _, eye in ipairs({ x + e[1], x + 3 + e[1] }) do
    ui.fill(eye, y + 1, 2, 2, C.text)
    ui.fill(eye + e[2], y + 1 + e[3], 1, 1, C.blueTint)
  end
end

--- A frightened ghost's face: two dots for eyes, and a wobbly mouth.
local function drawFace(x, y, color)
  ui.fill(x + 1, y + 1, 1, 1, color)
  ui.fill(x + 4, y + 1, 1, 1, color)
  for col = 1, 4, 2 do ui.fill(x + col, y + 3, 1, 1, color) end
end

local function drawGhost(L, s, g)
  local x, y = spriteX(L, g.x), spriteY(L, g.y)
  if g.mode == "eyes" then
    drawEyes(x, y, g.dir)
  elseif g.scared then
    drawSprite(GHOST_BODY[s.frame % 2 + 1], x, y, ghostColor(s, g))
    drawFace(x, y, ghostColor(s, g) == C.text and C.red or C.text)
  else
    drawSprite(GHOST_BODY[s.frame % 2 + 1], x, y, GHOST_COLORS[g.name])
    drawEyes(x, y, g.dir)
  end
end

local function drawNotes(L, s)
  if s.popup then
    ui.small(s.popup.text, tileX(L, s.popup.x) + 2, tileY(L, s.popup.y) + 1, C.hi, C.bg, "center")
  end
  if s.ready then
    ui.small("READY!", tileX(L, rules.FRUIT_AT[1]) + 2, tileY(L, rules.FRUIT_AT[2]) + 1, C.hi, C.bg, "center")
  end
end

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, COLS * CELL_W, ROWS * CELL_H)
end

function view.draw(L, s)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.bg)
  drawMaze(L, s)
  drawDots(L, s)
  drawFruit(L, s)
  if s.after ~= "level" then
    drawPac(L, s)
    if not s.after then
      drawWaiting(L, s)
      for _, g in ipairs(s.ghosts) do drawGhost(L, s, g) end
    end
  end
  drawNotes(L, s)
end

--- The whole wall steers: tap the side you want.
function view.actionAt(L, _, px, py)
  return base.splitAction(L, px, py)
end

function view.onEvents(app, s, events)
  for _, ev in ipairs(events) do
    if ev.type == "dot" then
      app.audio.play(s.dotsLeft % 2 == 0 and "placeRed" or "placeBlue", 0.4)
    elseif ev.type == "pellet" then
      app.audio.play("captureRed")
    elseif ev.type == "ghost" then
      app.audio.play("capture", 1, 0.8 + 0.2 * ev.combo)
    elseif ev.type == "fruit" then
      app.audio.play("captureBlue")
    elseif ev.type == "clear" or ev.type == "level" then
      app.audio.later("select", 120)
    elseif ev.type == "death" then
      app.audio.play("error")
    end
  end
end

return base.fill({
  id = "pacman", title = "Pac-Man", blurb = "Eat every dot, dodge the ghosts", color = "hi", accent = 0xFFD257,
  action = true, split = true, tickMs = 150, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Eat every dot on the board to reach the next level. Four ghosts are after you, and you have three lives.",
    "",
    "Tap the side of the wall you want to go: the top goes up, the bottom down, the left side left and the right side right. The wall is split corner to corner, so you never have to look away.",
    "",
    "You don't need perfect timing. Your last tap stays set, and Pac-Man turns at the first junction that lets him, so tap before you get there. A small yellow mark shows a turn is waiting.",
    "",
    "Power pellets make the ghosts blue, and you can eat them for 200, 400, 800 and 1600. White flashing means they're nearly back to normal.",
    "",
    "The tunnel at the sides comes out on the other side, and ghosts are slow in it. Fruit by the pen is worth more on later levels, and each level is faster, with less time to eat the ghosts.",
  },
})
