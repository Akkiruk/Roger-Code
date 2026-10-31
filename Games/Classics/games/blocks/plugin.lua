-- games/blocks/plugin.lua
-- Blocks as an Arcade classic. On a wide wall the well is narrow, so the sides do the work: tap a column in the well and
-- the piece goes there in one tap, tap either side of the well to turn it, and the long bar under the well drops it.

local base = require("lib.arcade.base")
local rules = require("games.blocks.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local COLS, ROWS = rules.COLS, rules.ROWS
local CELL_W, CELL_H = 5, 3    -- about square on a monitor
local NEXT_W, NEXT_H = 4, 2    -- the smaller cells of the preview
local INFO_H = 18              -- the panels above the turn zones
local DROP_MARGIN = 17         -- clear of the shell's QUIT, and the same on the other side
local COLORS = { I = C.info, J = C.blue, L = C.warn, O = C.hi, S = C.ok, T = C.accent, Z = C.red }

local view = {}

function view.layout(W, H)
  local L = base.actionLayout(W, H, COLS * CELL_W, ROWS * CELL_H)
  L.sideW = L.x0 - 3
  L.leftX, L.rightX = 1, L.x0 + L.bw + 2
  L.zoneY = L.y0 + INFO_H + 1
  L.zoneH = L.bh - INFO_H - 1
  return L
end

--- One square of a piece. Thin dark lines along its right and bottom, drawn with the monitor's block characters, keep
-- pieces of one colour apart without breaking a piece into bits.
local function block(L, x, y, color)
  if y < 1 then return end
  local px, py = L.x0 + (x - 1) * CELL_W, L.y0 + (y - 1) * CELL_H
  local right, low = px + CELL_W - 1, py + CELL_H - 1
  local screen = ui.screen()
  ui.fill(px, py, CELL_W - 1, CELL_H - 1, color)
  screen:fillRect(right, py, 1, CELL_H - 1, C.bg, color, "\149")
  screen:fillRect(px, low, CELL_W - 1, 1, C.bg, color, "\143")
  screen:fillRect(right, low, 1, 1, C.bg, color, "\133")
end

--- Faint stripes, one column in two, so a player can see which column they're aiming at.
local function drawWell(L)
  for x = 1, COLS do
    ui.fill(L.x0 + (x - 1) * CELL_W, L.y0, CELL_W, L.bh, x % 2 == 0 and C.panel or C.bg)
  end
  ui.fill(L.x0 - 1, L.y0, 1, L.bh + 1, C.line)
  ui.fill(L.x0 + L.bw, L.y0, 1, L.bh + 1, C.line)
  ui.fill(L.x0 - 1, L.y0 + L.bh, L.bw + 2, 1, C.line)
end

local function drawStack(L, s)
  for y = 1, ROWS do
    for x = 1, COLS do
      local letter = s.board[y][x]
      if letter then block(L, x, y, s.ending and C.line or COLORS[letter]) end
    end
  end
end

local function drawPiece(L, s)
  local p = s.piece
  if not p then return end
  if not s.ending then
    for _, c in ipairs(rules.cells(p.letter, p.rot, p.x, rules.landing(s))) do block(L, c[1], c[2], C.tie) end
  end
  for _, c in ipairs(rules.cells(p.letter, p.rot, p.x, p.y)) do block(L, c[1], c[2], COLORS[p.letter]) end
end

--- The next piece, centred in the panel on the right.
local function drawNext(L, s)
  local cx = L.rightX + math.floor(L.sideW / 2)
  ui.fill(L.rightX, L.y0, L.sideW, INFO_H, C.bg)
  ui.frame(L.rightX, L.y0, L.sideW, INFO_H, C.panel)
  ui.small("NEXT", cx, L.y0 + 2, C.line, C.bg, "center")
  local cells = rules.cells(s.next, 0, 0, 0)
  local lo, hi, top, low = 9, -9, 9, -9
  for _, c in ipairs(cells) do
    lo, hi, top, low = math.min(lo, c[1]), math.max(hi, c[1]), math.min(top, c[2]), math.max(low, c[2])
  end
  local x0 = cx - math.floor((hi - lo + 1) * NEXT_W / 2) - lo * NEXT_W
  local y0 = L.y0 + 5 + math.floor((10 - (low - top + 1) * NEXT_H) / 2) - top * NEXT_H
  for _, c in ipairs(cells) do
    ui.fill(x0 + c[1] * NEXT_W, y0 + c[2] * NEXT_H, NEXT_W, NEXT_H, COLORS[s.next])
  end
end

--- Lines so far, and how far off the next level is, in the panel on the left.
local function drawLines(L, s)
  local cx = L.leftX + math.floor(L.sideW / 2)
  ui.frame(L.leftX, L.y0, L.sideW, INFO_H, C.panel)
  ui.small("LINES", cx, L.y0 + 2, C.line, C.bg, "center")
  ui.text(s.lines, cx, L.y0 + 5, C.text, "center")
  ui.small((10 - s.lines % 10) .. " to level " .. (s.level + 1), cx, L.y0 + 14, C.line, C.bg, "center", L.sideW - 2)
end

local function drawZone(x, L, line2)
  local cx = x + math.floor(L.sideW / 2)
  ui.fill(x, L.zoneY, L.sideW, L.zoneH, C.panel)
  ui.text("TURN", cx, L.zoneY + 12, C.text, "center")
  ui.text(line2, cx, L.zoneY + 21, C.text, "center")
end

--- The well and the panels, which is all the idle screen wants.
local function drawGame(L, s)
  drawWell(L)
  drawStack(L, s)
  drawPiece(L, s)
  drawNext(L, s)
  drawLines(L, s)
end

function view.drawBoard(L, match)
  local s = match.state
  drawGame(L, s)
  ui.small("SCORE", L.leftX + math.floor(L.sideW / 2), L.zoneY + 2, C.line, C.bg, "center")
  ui.text(s.score, L.leftX + math.floor(L.sideW / 2), L.zoneY + 5, C.hi, "center")
end

function view.draw(L, s)
  drawGame(L, s)
  drawZone(L.leftX, L, "LEFT")
  drawZone(L.rightX, L, "RIGHT")
end

--- The one button: a long bar under the well, stopping well short of the shell's QUIT.
function view.controls(L)
  local w = L.W - 2 * DROP_MARGIN
  return { { label = "DROP", x = DROP_MARGIN, y = L.controlY, w = w, h = L.controlH, action = { kind = "drop" } } }
end

--- A tap in the well aims at that column. A tap anywhere beside the well turns the piece that way.
function view.actionAt(L, _, px, py)
  if py < L.y0 or py >= L.y0 + L.bh then return nil end
  if px < L.x0 then return { kind = "turn", dir = -1 } end
  if px >= L.x0 + L.bw then return { kind = "turn", dir = 1 } end
  return { kind = "aim", col = math.floor((px - L.x0) / CELL_W) + 1 }
end

function view.onEvents(app, _, events)
  for _, ev in ipairs(events) do
    if ev.type == "turn" then app.audio.play("select", 0.5) end
    if ev.type == "lock" and ev.lines == 0 then app.audio.play("placeBlue") end
    if ev.type == "lock" and ev.lines > 0 then app.audio.play("capture") end
    if ev.type == "lock" and ev.lines == 4 then app.audio.later("captureRed", 120) end
    if ev.type == "level" then app.audio.later("select", 120) end
    if ev.type == "topout" then app.audio.play("error") end
  end
end

return base.fill({
  id = "blocks", title = "Blocks", blurb = "Stack them, clear lines", color = "info", accent = 0xFFD257,
  action = true, tickMs = 100, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Fit the falling pieces together. A row with no gaps clears, and the rows above drop down.",
    "",
    "Tap a column in the well and the piece goes straight there. The grey shape shows where it will land.",
    "",
    "Tap left or right of the well to turn the piece that way. It doesn't matter which you do first.",
    "",
    "Tap DROP to send it down. Left alone it falls by itself and locks when it lands.",
    "",
    "1, 2, 3 or 4 rows at once score 100, 300, 500 or 800, times the level. Every 10 rows the level goes up and the fall speeds up.",
    "",
    "The game ends when a new piece has no room to enter.",
  },
})
