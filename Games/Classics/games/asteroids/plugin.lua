-- games/asteroids/plugin.lua
-- Asteroids as an Arcade classic. A tap on the board turns the ship to face it and fires, because a monitor can only
-- give separate taps. THRUST and HYPERSPACE sit under the board. The rules work in world units; this file turns them
-- into monitor cells, each 2 units wide and 3 tall, so round things stay round.

local base = require("lib.arcade.base")
local rules = require("games.asteroids.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local WIDTH, HEIGHT = rules.WIDTH, rules.HEIGHT
local CELL_W, CELL_H = rules.CELL_W, rules.CELL_H
local BOARD_W, BOARD_H = WIDTH / CELL_W, HEIGHT / CELL_H
local TAU = math.pi * 2
local cos, floor, max, min, sin = math.cos, math.floor, math.max, math.min, math.sin

-- Rock outlines: how far out each spoke reaches, as a share of the radius. All close to 1, so a rock reads as round.
local LOOKS = {
  { 1, 0.9, 1, 0.95, 0.85, 1, 0.92, 1, 0.88, 1 },
  { 0.92, 1, 0.86, 1, 1, 0.9, 1, 0.84, 1, 0.95 },
  { 1, 0.95, 0.88, 1, 0.92, 1, 0.84, 1, 1, 0.9 },
  { 0.88, 1, 1, 0.9, 1, 0.85, 1, 1, 0.92, 0.96 },
}
local RIM = 3             -- world units of rim round a rock
local RIMMED = 12         -- rocks at least this big get a rim
local SHIP = { { 0, 15 }, { 2.4, 12 }, { math.pi, 5 }, { -2.4, 12 } } -- a dart: each point's angle from the nose, and distance
local STAR_COUNT = 36

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, BOARD_W, BOARD_H)
end

--- One row of cells, cut off at the edge of the board so nothing lands on the header or the buttons.
local function span(L, row, from, to, color)
  if row < 0 or row >= L.bh then return end
  from, to = max(0, from), min(L.bw - 1, to)
  ui.fill(L.x0 + from, L.y0 + row, to - from + 1, 1, color)
end

--- A filled shape from a list of world points { x, y }.
local function polygon(L, points, color)
  local top, bottom = math.huge, -math.huge
  for _, p in ipairs(points) do
    top, bottom = min(top, p[2]), max(bottom, p[2])
  end
  for row = floor(top / CELL_H), floor(bottom / CELL_H) do
    local y = (row + 0.5) * CELL_H
    local from, to = math.huge, -math.huge
    for i, a in ipairs(points) do
      local b = points[i % #points + 1]
      if (a[2] <= y) ~= (b[2] <= y) then
        local x = a[1] + (y - a[2]) / (b[2] - a[2]) * (b[1] - a[1])
        from, to = min(from, x), max(to, x)
      end
    end
    -- a sliver under a cell wide would only show as a stray spike
    if to - from >= CELL_W then span(L, row, floor(from / CELL_W), floor(to / CELL_W), color) end
  end
end

--- The copies a wrapped thing shows on one axis: itself, and the other side if it hangs over an edge.
local function copies(at, reach, size)
  if at < reach then return { 0, size } end
  if at > size - reach then return { 0, -size } end
  return { 0 }
end

--- Draw something once for each place it shows on the wrapped board. draw gets the offset to add.
local function wrapped(x, y, reach, draw)
  for _, dx in ipairs(copies(x, reach, WIDTH)) do
    for _, dy in ipairs(copies(y, reach, HEIGHT)) do
      draw(dx, dy)
    end
  end
end

local function rockShape(rock, dx, dy, radius)
  local look = LOOKS[rock.look]
  local points = {}
  for i, share in ipairs(look) do
    local heading = rock.angle + i / #look * TAU
    points[i] = { rock.x + dx + cos(heading) * radius * share, rock.y + dy + sin(heading) * radius * share }
  end
  return points
end

local function drawRock(L, rock)
  wrapped(rock.x, rock.y, rock.radius, function(dx, dy)
    polygon(L, rockShape(rock, dx, dy, rock.radius), C.line)
    -- only a large rock has room for a rim: on a smaller one it breaks up into odd shapes
    if rock.radius >= RIMMED then polygon(L, rockShape(rock, dx, dy, rock.radius - RIM), C.panel) end
  end)
end

--- A point a heading and distance from something, in world units.
local function offset(o, heading, distance, dx, dy)
  return { o.x + dx + cos(heading) * distance, o.y + dy + sin(heading) * distance }
end

--- A bright spot two cells wide, which is about square on the wall.
local function drawSpot(L, o, color)
  local col, row = floor(o.x / CELL_W), floor(o.y / CELL_H)
  span(L, row, col, col + 1, color)
end

local function drawFlame(L, ship, dx, dy)
  local back = ship.angle + math.pi
  polygon(L, {
    offset(ship, back + 0.5, 8, dx, dy), offset(ship, back, 20, dx, dy), offset(ship, back - 0.5, 8, dx, dy),
  }, C.warn)
end

--- A craft centred on its cell, so its outline stays even as it drifts across the rows.
local function snapped(craft)
  return {
    x = (floor(craft.x / CELL_W) + 0.5) * CELL_W, y = (floor(craft.y / CELL_H) + 0.5) * CELL_H, angle = craft.angle,
  }
end

local function drawShip(L, s)
  local ship = snapped(s.ship)
  wrapped(ship.x, ship.y, 20, function(dx, dy)
    if s.burn > 0 then drawFlame(L, ship, dx, dy) end
    local points = {}
    for i, part in ipairs(SHIP) do
      points[i] = offset(ship, ship.angle + part[1], part[2], dx, dy)
    end
    local blink = s.safe > 0 and floor(s.safe / 2) % 2 == 0
    polygon(L, points, blink and C.info or C.text)
    -- the nose marks the way a shot or a burn will go
    local nose = points[1]
    drawSpot(L, { x = nose[1], y = nose[2] }, C.warn)
  end)
end

local function drawSaucer(L, saucer)
  local r = saucer.radius * 1.4 -- a touch larger than it hits, or the small one is only a blob
  local color = saucer.kind == "small" and C.red or C.soft
  local at = snapped(saucer)
  wrapped(at.x, at.y, r, function(dx, dy)
    local x, y = at.x + dx, at.y + dy
    polygon(L, { { x - r * 1.3, y }, { x - r * 0.5, y + r * 0.6 }, { x + r * 0.5, y + r * 0.6 }, { x + r * 1.3, y } }, color)
    polygon(L, { { x - r * 1.3, y + 1 }, { x - r * 0.5, y - r * 0.4 }, { x + r * 0.5, y - r * 0.4 }, { x + r * 1.3, y + 1 } }, color)
    polygon(L, { { x - r * 0.5, y - r * 0.3 }, { x, y - r }, { x + r * 0.5, y - r * 0.3 } }, C.info)
  end)
end

local function drawBlast(L, b)
  local reach = (b.age + 1) * (1 + b.size)
  local color = b.age < 3 and C.hi or C.warn
  for i = 1, 8 do
    local heading = i / 8 * TAU + b.size
    drawSpot(L, { x = b.x + cos(heading) * reach, y = b.y + sin(heading) * reach }, color)
  end
end

--- A fixed scatter of stars: no chance needed, and the board never twinkles.
local function drawStars(L)
  for i = 1, STAR_COUNT do
    ui.fill(L.x0 + (i * 47) % L.bw, L.y0 + (i * 29) % L.bh, 1, 1, C.panel)
  end
end

--- A word over the middle of the board when the game is between things.
local function drawNotice(L, s)
  local word = s.hold > 0 and "TAP TO BEGIN" or (s.breather > 0 and ("WAVE " .. (s.level + 1)))
  if word and not s.over then ui.small(word, L.x0 + floor(L.bw / 2), L.y0 + 12, C.hi, C.bg, "center") end
end

function view.draw(L, s)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.bg)
  drawStars(L)
  for _, rock in ipairs(s.rocks) do drawRock(L, rock) end
  if s.saucer then drawSaucer(L, s.saucer) end
  for _, bomb in ipairs(s.bombs) do drawSpot(L, bomb, C.red) end
  for _, shot in ipairs(s.shots) do drawSpot(L, shot, C.hi) end
  for _, b in ipairs(s.blasts) do drawBlast(L, b) end
  if s.dead == 0 and s.gone == 0 then drawShip(L, s) end
  drawNotice(L, s)
end

--- Two wide buttons, stopping short of the shell's QUIT in the corner.
function view.controls(L, s)
  local x, gap = L.x0, 2
  local w = floor((L.W - 16 - x - gap) / 2)
  return {
    { label = "THRUST", x = x, y = L.controlY, w = w, h = L.controlH, action = { kind = "thrust" } },
    {
      label = s.cool > 0 and "HYPERSPACE CHARGING" or "HYPERSPACE", x = x + w + gap, y = L.controlY, w = w,
      h = L.controlH, action = { kind = "hyper" },
    },
  }
end

--- A tap on the board turns the ship to face it and fires.
function view.actionAt(L, _, px, py)
  if px < L.x0 or px >= L.x0 + L.bw or py < L.y0 or py >= L.y0 + L.bh then return nil end
  return { kind = "aim", x = (px - L.x0 + 0.5) * CELL_W, y = (py - L.y0 + 0.5) * CELL_H }
end

local ROCK_SOUNDS = { "captureRed", "capture", "captureBlue" }

function view.onEvents(app, _, events)
  for _, ev in ipairs(events) do
    if ev.type == "shot" then app.audio.play("placeRed") end
    if ev.type == "hyper" then app.audio.play("placeBlue") end
    if ev.type == "rock" then app.audio.play(ROCK_SOUNDS[ev.size]) end
    if ev.type == "saucer" then app.audio.play("select") end
    if ev.type == "saucerHit" then app.audio.play("capture") end
    if ev.type == "level" or ev.type == "life" then app.audio.later("select", 120) end
    if ev.type == "crash" then app.audio.play("error") end
  end
end

return base.fill({
  id = "asteroids", title = "Asteroids", blurb = "Tap to aim and fire, mind the rocks", color = "info", accent = 0x4CC9F0,
  action = true, tickMs = 100, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Shoot the rocks. Large ones split into medium, medium into small, and smaller is worth more: 20, 50 and 100.",
    "",
    "Tap the board: the ship turns to face your tap and fires. Tap right on a rock or saucer and the shot aims ahead of it for you. You can have five shots flying.",
    "",
    "THRUST pushes the ship the way it's facing. One tap is one short burn, and the ship coasts on, slows down and wraps round the edges.",
    "",
    "HYPERSPACE jumps to a random spot, which may not be a safe one, then takes four seconds to charge.",
    "",
    "Three lives, and a short safe moment each time you come back. An extra life comes every 10,000. Saucers pay 200, or 1,000 for the small one that aims at you.",
  },
})
