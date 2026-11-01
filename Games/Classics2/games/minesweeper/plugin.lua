-- games/minesweeper/plugin.lua
-- Minesweeper as an Arcade classic. The board fills the left of the wall and the column beside it holds the counters
-- and the DIG/FLAG button. The shell draws every control grey, and this one has to show its mode in colour, so the game
-- draws the button itself and takes its taps in actionAt.

local base = require("lib.arcade.base")
local rules = require("games.minesweeper.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor, ceil, min = math.floor, math.ceil, math.min

local PANEL_W = 21
local BLURB = "Clear the board, spare the mines"

-- the classic colours. Navy, maroon and black vanish on a dark board, so 4, 5 and 7 take the nearest colour that shows
local NUMBER_COLORS = { C.blue, C.ok, C.red, C.accent, C.warn, C.info, C.text, C.line }

-- 3 wide by 5 tall, for tiles too short for the font
local DIGITS = {
  "010110010010111", "111001111100111", "111001011001111", "101101111001001",
  "111100111001111", "111100111101111", "111001010010010", "111101111101111",
}

local view = {}

function view.layout(W, H)
  local L = base.actionLayout(W, H, W - PANEL_W - 3, H - 8)
  L.x0 = 1
  L.panelX = W - PANEL_W - 1
  L.modeY = 28
  L.modeH = H - L.modeY - 9
  return L
end

--- Where a board sits: its left and top, and the size of a tile. Tiles are as big as the space allows, and square to the eye.
function view.tiles(L, s)
  local ch = floor(L.bh / s.rows)
  local cw = min(floor(L.bw / s.cols), ceil(ch * 1.5))
  return L.x0 + floor((L.bw - cw * s.cols) / 2), L.y0 + floor((L.bh - ch * s.rows) / 2), cw, ch
end

--- A round mine, or on the smallest tile a spiked cross, which still reads as one where a disc would be a bar.
local function drawMine(x, y, w, h, color)
  if h < 5 then
    ui.fill(x + 1, y + floor(h / 2), w - 2, 1, color)
    ui.fill(x + floor(w / 2), y, 1, h, color)
    return
  end
  local dx, dy = floor(w / 5), floor(h / 5)
  base.disc(x + dx, y + dy, w - 2 * dx, h - 2 * dy, color)
end

--- A red pennant on a dark pole, with a foot.
local function drawFlag(x, y, w, h)
  local dx, dy = floor(w / 5), floor(h / 5)
  local poleX = x + floor(w * 0.6)
  local tall = h - 2 * dy
  ui.fill(x + dx, y + dy, poleX - x - dx, ceil(tall * 0.6), C.red)
  ui.fill(poleX, y + dy, 1, tall, C.bg)
  ui.fill(poleX - dx, y + dy + tall - 1, 2 * dx + 1, 1, C.bg)
end

--- A digit in teletext characters, whose two columns and three rows of blocks fit 3x5 into a square of 2x2 characters.
--- Each entry says what to draw for one character; the last block has no bit of its own, so it means swapping the colours.
local function teletext(glyph)
  local chars = {}
  for row = 0, 1 do
    for col = 0, 1 do
      local code = 0
      for dy = 0, 2 do
        for dx = 0, 1 do
          local gx, gy = col * 2 + dx, row * 3 + dy
          if gx < 3 and gy < 5 and glyph:sub(gy * 3 + gx + 1, gy * 3 + gx + 1) == "1" then code = code + 2 ^ (dy * 2 + dx) end
        end
      end
      local swap = code >= 32
      chars[#chars + 1] = { char = string.char(128 + (swap and 63 - code or code)), swap = swap, col = col, row = row }
    end
  end
  return chars
end

local TELETEXT = {}
for n, glyph in ipairs(DIGITS) do TELETEXT[n] = teletext(glyph) end

--- A number on a tile. The font if the tile takes it, then the same digits in cells, then in teletext on the smallest tile.
local function drawNumber(n, x, y, w, h, bg)
  local color = NUMBER_COLORS[n]
  local height = ui.fontHeight()
  if h >= height then
    ui.text(n, x + floor(w / 2), y + floor((h - height) / 2), color, "center")
  elseif h >= 5 then
    local left, top = x + floor((w - 3) / 2), y + floor((h - 5) / 2)
    for i = 1, 15 do
      if DIGITS[n]:sub(i, i) == "1" then ui.fill(left + (i - 1) % 3, top + floor((i - 1) / 3), 1, 1, color) end
    end
  else
    for _, c in ipairs(TELETEXT[n]) do
      ui.small(c.char, x + floor((w - 2) / 2) + c.col, y + c.row, c.swap and bg or color, c.swap and color or bg)
    end
  end
end

--- A tile's face, w x h, which stops a cell short of the next tile so the grid shows.
local function drawSquare(s, cell, hit, x, y, w, h)
  if hit then
    ui.fill(x, y, w, h, C.red)
    drawMine(x, y, w, h, C.bg)
  elseif s.hit and cell.mine and not cell.flag then
    ui.fill(x, y, w, h, C.panel)
    drawMine(x, y, w, h, C.text)
  elseif s.hit and cell.flag and not cell.mine then
    ui.fill(x, y, w, h, C.warn)
    ui.small("X", x + floor(w / 2), y + floor((h - 1) / 2), C.bg, C.warn)
  elseif cell.flag then
    ui.fill(x, y, w, h, C.line)
    drawFlag(x, y, w, h)
  elseif cell.open then
    ui.fill(x, y, w, h, C.panel)
    if cell.count > 0 then drawNumber(cell.count, x, y, w, h, C.panel) end
  else
    ui.fill(x, y, w, h, C.line)
  end
end

local function drawStat(L, label, value, y, color)
  local x = L.panelX + floor(PANEL_W / 2)
  ui.small(label, x, y, C.line, C.bg, "center")
  if ui.textWidth(value) <= PANEL_W then
    ui.text(value, x, y + 2, color, "center")
  else
    ui.small(value, x, y + 3, color, C.bg, "center")
  end
end

local function drawPanel(L, s)
  local left, seconds = rules.minesLeft(s), rules.seconds(s)
  drawStat(L, "MINES LEFT", left, L.y0 + 1, left < 0 and C.warn or C.text)
  drawStat(L, "TIME", string.format("%d:%02d", floor(seconds / 60), seconds % 60), L.y0 + 10, C.text)
  local digging = s.mode == "dig"
  local color, fg = digging and C.ok or C.red, digging and C.bg or C.text
  local cx = L.panelX + floor(PANEL_W / 2)
  local mid = L.modeY + floor(L.modeH / 2)
  ui.fill(L.panelX, L.modeY, PANEL_W, L.modeH, color)
  ui.small("MODE", cx, L.modeY + 2, fg, color, "center")
  ui.text(digging and "DIG" or "FLAG", cx, mid - 3, fg, "center")
  ui.small("TAP TO", cx, L.modeY + L.modeH - 5, fg, color, "center")
  ui.small("SWITCH", cx, L.modeY + L.modeH - 3, fg, color, "center")
end

local function drawBanner(L, s)
  local b = s.banner
  if not b then return end
  local w, h = min(L.bw, 62), 16
  local x, y = L.x0 + floor((L.bw - w) / 2), L.y0 + floor((L.bh - h) / 2)
  local cx = x + floor(w / 2)
  ui.fill(x, y, w, h, C.panel)
  ui.frame(x, y, w, h, C.ok, 1)
  ui.text("BOARD CLEAR", cx, y + 2, C.ok, "center", w - 2)
  ui.small("CLEAR +" .. b.clear .. "   TIME +" .. b.time, cx, y + 10, C.text, C.panel, "center", w - 2)
  ui.small("NEXT BOARD COMING UP", cx, y + 12, C.line, C.panel, "center", w - 2)
end

function view.draw(L, s)
  local x0, y0, cw, ch = view.tiles(L, s)
  local hit = s.hit
  for y = 1, s.rows do
    for x = 1, s.cols do
      local isHit = hit and hit[1] == x and hit[2] == y
      drawSquare(s, s.grid[y][x], isHit, x0 + (x - 1) * cw, y0 + (y - 1) * ch, cw - 1, ch - 1)
    end
  end
  drawPanel(L, s)
  drawBanner(L, s)
end

--- The mode button, or the square under a tap. Each tile takes every cell it covers, grid lines included, so nothing is a dead spot.
function view.actionAt(L, s, px, py)
  if px >= L.panelX and px < L.panelX + PANEL_W and py >= L.modeY and py < L.modeY + L.modeH then return { kind = "mode" } end
  local x0, y0, cw, ch = view.tiles(L, s)
  local x, y = floor((px - x0) / cw) + 1, floor((py - y0) / ch) + 1
  if x < 1 or x > s.cols or y < 1 or y > s.rows then return nil end
  return { kind = "tap", x = x, y = y }
end

--- The idle screen needs a line for TOUCH TO PLAY, so its board stops short of the foot of the wall.
function view.drawAttract(W, H, demo)
  local L = view.layout(W, H)
  L.y0, L.bh = 9, H - 17
  ui.text("Minesweeper", floor(W / 2), 1, C.info, "center", W - 2)
  if demo.match then view.draw(L, demo.match.state) end
  return L.y0 + L.bh + 1
end

-- What each event sounds like. Names are in lib/sound_picks.lua.
local SFX = {
  flag = "piece_a", unflag = "ui_back", mode = "ui_select", boom = "boom_big", clear = "win_small",
  board = "ui_select",
  open = function(ev) return ev.count > 1 and "capture" or "ui_tap" end, -- a big opening is worth more
}

function view.onEvents(app, _, events)
  base.sfx(app, events, SFX)
end

return base.fill({
  id = "minesweeper", title = "Minesweeper", blurb = BLURB, color = "info", accent = 0x3CD3E6,
  action = true, tickMs = rules.TICK_MS, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Open every square that isn't a mine. A number tells you how many mines touch that square, counting corners.",
    "",
    "Your first tap on a board is always safe. The big button switches between DIG and FLAG: in FLAG mode a tap sets or clears a flag on a square you think is a mine. A flagged square can't be dug.",
    "",
    "Tap an open number whose flags match it, in either mode, and everything else around it opens at once. If a flag is wrong, that can open a mine.",
    "",
    "One mine ends the run. Every square scores a point, and a cleared board pays a bonus, more the quicker you are. Boards grow, and each has more mines.",
  },
})
