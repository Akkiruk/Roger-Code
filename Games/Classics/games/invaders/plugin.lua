-- games/invaders/plugin.lua
-- Space Invaders as an Arcade classic. A tap anywhere in a column sends the cannon there, and it fires by itself.

local base = require("lib.arcade.base")
local rules = require("games.invaders.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local COLS, ROWS = rules.COLS, rules.ROWS

-- Two frames of each sprite, one letter to a monitor cell. A cell is taller than it's wide, so these look squarer than this.
local INVADERS = {
  [30] = {
    {
      "...###...",
      "..#####..",
      ".##.#.##.",
      "..#####..",
      ".#.#.#.#.",
    },
    {
      "...###...",
      "..#####..",
      ".##.#.##.",
      "..#####..",
      "..#...#..",
    },
  },
  [20] = {
    {
      "..#...#..",
      ".#######.",
      "##.###.##",
      "#########",
      "#.#...#.#",
    },
    {
      "#.#...#.#",
      "#.#####.#",
      "##.###.##",
      ".#######.",
      ".#.....#.",
    },
  },
  [10] = {
    {
      "..#####..",
      ".#######.",
      "##.###.##",
      "#########",
      ".#.#.#.#.",
    },
    {
      "..#####..",
      ".#######.",
      "##.###.##",
      "#########",
      "#..#.#..#",
    },
  },
}

local UFO = {
  "...#####...",
  ".#########.",
  "##.##.##.##",
}

local CANNON = {
  "....#....",
  ".#######.",
  "#########",
}

local BLAST = {
  "#..#.#..#",
  ".#.....#.",
  "#.......#",
  ".#.....#.",
  "#..#.#..#",
}

local INVADER_COLOR = { [30] = "info", [20] = "accent", [10] = "soft" }

--- A sprite as runs of cells, so a row with one solid stretch is one fill.
local function runs(lines)
  local out = {}
  for y, line in ipairs(lines) do
    local from = 1
    while true do
      local a, b = line:find("#+", from)
      if not a then break end
      out[#out + 1] = { x = a - 1, y = y - 1, w = b - a + 1 }
      from = b + 1
    end
  end
  return out
end

for _, frames in pairs(INVADERS) do
  frames[1], frames[2] = runs(frames[1]), runs(frames[2])
end
UFO, CANNON, BLAST = runs(UFO), runs(CANNON), runs(BLAST)

--- Draw a sprite at a board position, cut off at the sides of the board.
local function sprite(L, shape, x, y, color)
  for _, run in ipairs(shape) do
    local from = math.max(1, x + run.x)
    local to = math.min(COLS, x + run.x + run.w - 1)
    if to >= from then ui.fill(L.x0 + from - 1, L.y0 + y + run.y - 1, to - from + 1, 1, color) end
  end
end

local function drawBases(L, s)
  for y = rules.BASE_Y, rules.BASE_Y + rules.BASE_H - 1 do
    local row = s.bases[y]
    local start
    for x = 1, COLS + 1 do
      if row[x] and not start then start = x end
      if start and not row[x] then
        ui.fill(L.x0 + start - 1, L.y0 + y - 1, x - start, 1, C.ok)
        start = nil
      end
    end
  end
end

local function drawCannon(L, s)
  local left = s.x - math.floor(rules.CANNON_W / 2)
  if s.wreck then
    -- it burns for the whole pause, so the cannon never seems to have just vanished
    sprite(L, BLAST, left, rules.CANNON_Y - 2, s.clock % 4 < 2 and C.warn or C.red)
  else
    sprite(L, CANNON, left, rules.CANNON_Y, C.ok)
  end
  -- a mark on the ground where the last tap asked it to go, until it gets there
  if s.target ~= s.x then ui.fill(L.x0 + s.target - 2, L.y0 + ROWS - 1, 3, 1, C.hi) end
end

local function drawBlasts(L, s)
  for _, b in ipairs(s.blasts) do
    if b.points then
      ui.small(b.points, L.x0 + b.x, L.y0 + b.y, C.red, C.panel, "left")
    else
      sprite(L, BLAST, b.x, b.y, C.hi)
    end
  end
end

--- The field alone. The idle screen uses just this, because it puts its own words under the board.
local function drawField(L, s)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.panel)
  drawBases(L, s)
  for _, inv in ipairs(s.invaders) do
    sprite(L, INVADERS[inv.points][s.frame], inv.x, inv.y, C[INVADER_COLOR[inv.points]])
  end
  if s.ufo then sprite(L, UFO, s.ufo.x, rules.UFO_Y, C.red) end
  for _, shot in ipairs(s.shots) do ui.fill(L.x0 + shot.x - 1, L.y0 + shot.y - 1, 1, 2, C.hi) end
  for _, bomb in ipairs(s.bombs) do ui.fill(L.x0 + bomb.x - 1, L.y0 + bomb.y - 2, 1, 2, C.warn) end
  drawCannon(L, s)
  drawBlasts(L, s)
  if s.pause > 0 and not s.wreck then
    ui.text("WAVE " .. s.level, L.x0 + math.floor(L.bw / 2), L.y0 + math.floor(L.bh / 2), C.hi, "center")
  end
end

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, COLS, ROWS)
end

function view.draw(L, s)
  drawField(L, s)
  ui.small("TAP A COLUMN TO AIM. THE CANNON FIRES BY ITSELF.", math.floor(L.W / 2), L.controlY + 2, C.line, C.bg, "center")
end

function view.drawBoard(L, match)
  drawField(L, match.state)
end

--- No buttons: every tap is an aim, so there's nothing else to reach for.
function view.controls()
  return {}
end

--- A tap anywhere in a column aims there, even above the board, so a player needn't reach down past their own view.
function view.actionAt(L, _, px)
  if px < L.x0 or px >= L.x0 + L.bw then return nil end
  return { kind = "aim", x = px - L.x0 + 1 }
end

-- What each event sounds like. Names are in lib/sound_picks.lua.
local SFX = {
  shot = "laser", hit = "boom_small", mystery = "boom_small", ufo = "ufo", wave = "level_clear",
  lost = "death", landed = "death",
  march = function(ev) return "march", 1, ev.frame == 1 and 1 or 0.85 end,
}

function view.onEvents(app, _, events)
  base.sfx(app, events, SFX)
end

return base.fill({
  id = "invaders", title = "Space Invaders", short = "Invaders", blurb = "Aim, and hold the line",
  color = "info", accent = 0xFFD257,
  action = true, tickMs = 100, minSize = { w = 118, h = 79 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Tap anywhere in a column and the cannon slides there. It fires by itself, so all you do is aim.",
    "",
    "Shoot the invaders: the bottom two rows are worth 10, the middle two 20 and the top row 30. The ship across the top is worth up to 300.",
    "",
    "Dodge the orange bombs, or shelter under a green base. Your own shots pass over the bases, but bombs wear them away.",
    "",
    "A bomb costs a life, and you have three. If the invaders reach you the game is over. Each wave starts lower.",
  },
})
