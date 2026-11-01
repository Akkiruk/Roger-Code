-- games/pipedream/plugin.lua
-- Pipe Dream as an Arcade classic. No buttons: a tap on the board lays the next piece, and a tap on the start piece rushes
-- the flooz. The board takes the wall, the queue runs down the column beside it, and a strip below says what the flooz is doing.

local base = require("lib.arcade.base")
local rules = require("games.pipedream.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor, ceil, min = math.floor, math.ceil, math.min
local UP, RIGHT, DOWN, LEFT = rules.UP, rules.RIGHT, rules.DOWN, rules.LEFT

local MAX_CW, MAX_CH = 11, 9     -- a tile 11x9 looks near enough square, and centres the pipe both ways
local QUEUE_CW, QUEUE_CH = 9, 7  -- a queue tile
local QUEUE_GAP = 1
local PANEL_W = QUEUE_CW + 2
local TOP = 8                    -- the header ends here
local STRIP_H = 9
local STRIP_END = 105            -- QUIT starts just past here
local BLURB = "Keep the flooz flowing"

-- half widths of a pipe's wall and of its bore. A cell is taller than wide, so these look the same thickness both ways
local WALL_X, WALL_Y = 2, 1
local BORE_X, BORE_Y = 1, 0

local view = {}

function view.layout(W, H)
  local cw = min(MAX_CW, floor((W - PANEL_W) / rules.COLS))
  local ch = min(MAX_CH, floor((H - TOP - STRIP_H) / rules.ROWS))
  local L = base.actionLayout(W, H, cw * rules.COLS, ch * rules.ROWS)
  L.x0, L.y0, L.cw, L.ch = 0, TOP, cw, ch
  L.statusY = L.y0 + L.bh + 1
  L.controlY = L.statusY
  L.queueX = W - QUEUE_CW
  L.queueY = L.y0 + 2
  L.panelY = L.queueY + rules.QUEUE * (QUEUE_CH + QUEUE_GAP) + 1
  return L
end

--- One arm of a pipe, from the middle of a tile to the side given, half-widths hx and hy. part is how much of it to draw,
--- from the edge of the tile if inward, or from the middle if not.
local function arm(x, y, w, h, side, hx, hy, color, part, inward)
  local cx, cy = x + floor(w / 2), y + floor(h / 2)
  part = part or 1
  if side == UP or side == DOWN then
    local len = side == UP and cy + hy - y + 1 or y + h - cy + hy
    local n = ceil(len * part)
    local top
    if side == UP then
      top = inward and y or cy + hy - n + 1
    else
      top = inward and y + h - n or cy - hy
    end
    ui.fill(cx - hx, top, 2 * hx + 1, n, color)
  else
    local len = side == LEFT and cx + hx - x + 1 or x + w - cx + hx
    local n = ceil(len * part)
    local left
    if side == LEFT then
      left = inward and x or cx + hx - n + 1
    else
      left = inward and x + w - n or cx - hx
    end
    ui.fill(left, cy - hy, n, 2 * hy + 1, color)
  end
end

--- A piece: its walls, then its bore on top, so that arms overlap into one pipe.
local function drawPipe(x, y, w, h, sides, wall)
  for side in pairs(sides) do arm(x, y, w, h, side, WALL_X, WALL_Y, wall) end
  for side in pairs(sides) do arm(x, y, w, h, side, BORE_X, BORE_Y, C.bg) end
end

--- The bore of a tile, wet as far as the flooz has got. head is the flooz, if it's in this tile.
local function drawWater(x, y, w, h, cell, head, s)
  for side in pairs(cell.wet) do
    if not head or (side ~= head.from and side ~= head.to) then arm(x, y, w, h, side, BORE_X, BORE_Y, C.ok) end
  end
  if not head then return end
  local done = min(1, head.t / rules.flowSteps(s.level))
  if s.leak then done = 1 end
  if not head.from then
    arm(x, y, w, h, head.to, BORE_X, BORE_Y, C.ok, done)
  elseif done < 0.5 then
    arm(x, y, w, h, head.from, BORE_X, BORE_Y, C.ok, done * 2, true)
  else
    arm(x, y, w, h, head.from, BORE_X, BORE_Y, C.ok)
    arm(x, y, w, h, head.to, BORE_X, BORE_Y, C.ok, done * 2 - 1)
  end
end

--- The start piece: a tank with one way out, flashing while a tap on it would rush the flooz.
local function drawStart(x, y, w, h, cell, s, head)
  local ready = s.flow and not s.rushing and not s.leak
  local flash = ready and floor(s.steps / 4) % 2 == 0
  ui.fill(x, y, w, h, C.hiTint)
  ui.frame(x, y, w, h, s.rushing and C.warn or (flash and C.text or C.hi), 1)
  drawPipe(x, y, w, h, { [cell.dir] = true }, s.rushing and C.warn or C.hi)
  ui.fill(x + floor(w / 2) - 1, y + floor(h / 2), 3, 1, s.flow and C.ok or C.bg)
  drawWater(x, y, w, h, cell, head, s)
end

local function drawBlock(x, y, w, h)
  ui.fill(x, y, w, h, C.tie)
  ui.frame(x, y, w, h, C.line, 1)
  ui.fill(x + 2, y + 2, w - 4, h - 4, C.redTint)
end

--- Smoke where a piece was, shrinking away.
local function drawBlast(x, y, w, h, blast)
  local cut = blast.left % 3
  ui.fill(x + cut, y + cut, w - 2 * cut, h - 2 * cut, blast.left % 2 == 0 and C.warn or C.hi)
end

--- Flooz spilling out of the end of the pipe, over the edge of the next square.
local function drawLeak(L, s)
  local leak = s.leak
  if not leak then return end
  local cx = L.x0 + (leak.x - 1) * L.cw + floor(L.cw / 2)
  local cy = L.y0 + (leak.y - 1) * L.ch + floor(L.ch / 2)
  local dx, dy = 0, 0
  if leak.dir == LEFT or leak.dir == RIGHT then dx = (leak.dir == RIGHT and 1 or -1) * floor(L.cw / 2) end
  if leak.dir == UP or leak.dir == DOWN then dy = (leak.dir == DOWN and 1 or -1) * floor(L.ch / 2) end
  local color = floor(s.steps / 3) % 2 == 0 and C.red or C.warn
  local left = cx + dx - 3
  local top = cy + dy - 2
  local right = min(left + 7, L.x0 + L.bw)
  local bottom = min(top + 5, L.y0 + L.bh)
  left, top = math.max(left, L.x0), math.max(top, L.y0)
  ui.fill(left, top, right - left, bottom - top, color)
end

local function drawBoard(L, s)
  for y = 1, s.rows do
    for x = 1, s.cols do
      local px, py = L.x0 + (x - 1) * L.cw, L.y0 + (y - 1) * L.ch
      local cell = s.grid[y][x]
      local shade = (x + y) % 2 == 0 and C.panel or C.bg
      local head = s.flow and s.flow.x == x and s.flow.y == y and s.flow or nil
      ui.fill(px, py, L.cw, L.ch, shade)
      if s.blast and s.blast.x == x and s.blast.y == y then
        drawBlast(px, py, L.cw, L.ch, s.blast)
      elseif cell and cell.block then
        drawBlock(px, py, L.cw, L.ch)
      elseif cell and cell.start then
        drawStart(px, py, L.cw, L.ch, cell, s, head)
      elseif cell then
        drawPipe(px, py, L.cw, L.ch, rules.OPEN[cell.piece], C.text)
        drawWater(px, py, L.cw, L.ch, cell, head, s)
      end
    end
  end
  drawLeak(L, s)
end

--- The next five pieces, the one to lay first on top and lit up.
local function drawQueue(L, s)
  ui.small("NEXT", L.queueX + floor(QUEUE_CW / 2), L.y0, C.line, C.bg, "center")
  for i, piece in ipairs(s.queue) do
    local x, y = L.queueX, L.queueY + (i - 1) * (QUEUE_CH + QUEUE_GAP)
    ui.fill(x, y, QUEUE_CW, QUEUE_CH, i == 1 and C.hiTint or C.panel)
    if i == 1 then ui.frame(x, y, QUEUE_CW, QUEUE_CH, C.hi, 1) end
    drawPipe(x, y, QUEUE_CW, QUEUE_CH, rules.OPEN[piece], i == 1 and C.hi or C.text)
  end
end

--- How much pipe is still wanted: a number, then a tick of a word once there's enough.
local function drawLeft(L, s)
  local cx = L.queueX + floor(QUEUE_CW / 2)
  local left = rules.left(s)
  ui.small("PIPES", cx, L.panelY, C.line, C.bg, "center")
  ui.small("LEFT", cx, L.panelY + 1, C.line, C.bg, "center")
  if left > 0 then
    ui.text(left, cx, L.panelY + 3, C.text, "center", QUEUE_CW)
  else
    ui.text("OK", cx, L.panelY + 3, C.ok, "center", QUEUE_CW)
  end
  ui.small("OF " .. s.need, cx, L.panelY + 4 + ui.fontHeight(), C.line, C.bg, "center")
end

local function drawBanner(L, s)
  local b = s.banner
  if not b then return end
  local w, h = min(L.bw, 70), 20
  local x, y = L.x0 + floor((L.bw - w) / 2), L.y0 + floor((L.bh - h) / 2)
  local cx = x + floor(w / 2)
  ui.fill(x, y, w, h, C.panel)
  ui.frame(x, y, w, h, C.ok, 1)
  ui.text("LEVEL CLEAR", cx, y + 2, C.ok, "center", w - 2)
  ui.small(s.pipes .. " PIPES   LENGTH +" .. b.length, cx, y + 10, C.text, C.panel, "center", w - 2)
  ui.small(b.unused .. " UNUSED, " .. b.replaced .. " REPLACED", cx, y + 12, C.line, C.panel, "center", w - 2)
  ui.small("LEVEL BONUS +" .. b.bonus, cx, y + 14, C.hi, C.panel, "center", w - 2)
  ui.small("NEXT LEVEL COMING UP", cx, y + 16, C.line, C.panel, "center", w - 2)
end

--- A bar across the strip, filled as far as `part` from its left.
local function drawBar(x, y, part, color)
  local w = STRIP_END - x
  ui.fill(x, y, w, 3, C.panel)
  ui.fill(x, y, ceil(w * part), 3, color)
end

--- What the flooz is up to, in the strip under the board.
local function drawStrip(L, s)
  local y = L.statusY
  local mid = y + floor(ui.fontHeight() / 2) - 1
  if s.leak and not s.banner then
    ui.text("TOO SHORT: " .. s.pipes .. " OF " .. s.need, 2, y, C.warn, "left", STRIP_END - 2)
  elseif s.banner then
    ui.text("PIPE COMPLETE", 2, y, C.ok, "left", STRIP_END - 2)
  elseif not s.flow then
    local seconds = ceil(s.clock * rules.TICK_MS / 1000)
    ui.text("FLOOZ IN " .. seconds, 2, y, seconds <= 3 and C.warn or C.text, "left")
    drawBar(ui.textWidth("FLOOZ IN 00") + 5, mid, s.clock / s.clockFull, seconds <= 3 and C.warn or C.ok)
  elseif s.rushing then
    ui.text("RUSHING", 2, y, C.warn, "left")
    ui.small("DOUBLE POINTS FOR EACH PIPE", STRIP_END, mid + 1, C.hi, C.bg, "right")
  else
    ui.text("FLOWING", 2, y, C.ok, "left")
    ui.small("TAP THE START TO RUSH", STRIP_END, mid + 1, C.hi, C.bg, "right")
  end
end

--- Everything but the strip, which the idle screen needs for TOUCH TO PLAY.
function view.drawBoard(L, match)
  local s = match.state
  drawBoard(L, s)
  drawQueue(L, s)
  drawLeft(L, s)
  drawBanner(L, s)
end

function view.draw(L, s)
  view.drawBoard(L, { state = s })
  drawStrip(L, s)
end

--- The square under a tap. Each tile takes every cell it covers, so nothing on the board is a dead spot.
function view.actionAt(L, _, px, py)
  if px < L.x0 or px >= L.x0 + L.bw or py < L.y0 or py >= L.y0 + L.bh then return nil end
  return { kind = "tap", x = floor((px - L.x0) / L.cw) + 1, y = floor((py - L.y0) / L.ch) + 1 }
end

-- What each event sounds like. Names are in lib/sound_picks.lua.
local SFX = {
  place = "lock_in", replace = "brick", refused = "ui_error", go = "ui_start", rush = "ui_warning",
  enough = "coin", leak = "splash", clear = "level_clear", level = "ui_select",
  flow = function(ev) return "pour", 1, ev.rush and 1.3 or 1 end,
}

function view.onEvents(app, _, events)
  base.sfx(app, events, SFX)
end

return base.fill({
  id = "pipedream", title = "Pipe Dream", blurb = BLURB, color = "ok", accent = 0x35D07F,
  action = true, tickMs = rules.TICK_MS, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Build a pipe for the flooz to run through. Tap any square to lay the next piece, shown at the top of the column on the right. Five are shown, so plan ahead.",
    "",
    "Tap a pipe the flooz hasn't reached to blow it up and lay the next piece there. That takes a moment, and costs you off the level bonus.",
    "",
    "When the countdown ends the flooz leaves the start piece and follows your pipes. When it reaches an open end or a wall the level is over. Fill the length the level asks for and you go on, with a bonus for length. Fall short and the run is over.",
    "",
    "A cross counts twice if the flooz goes through it both ways. Pipes left dry on the board come off the level bonus, never your score.",
    "",
    "Pipe laid and ready? Tap the start piece to rush the flooz: every pipe filled from then on pays double. Later levels are faster, want more pipe, and have obstacles in the way.",
  },
})
