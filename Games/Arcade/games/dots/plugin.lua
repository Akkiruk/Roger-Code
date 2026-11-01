-- games/dots/plugin.lua
-- Dots and Boxes as an Arcade game.

local ai = require("games.dots.ai")
local base = require("lib.arcade.base")
local rules = require("games.dots.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local SIZE = rules.SIZE
local NEAR_LINE = 0.40 -- how far from a line a touch still counts, as a share of a box: the very middle of a box means nothing

local view = { scoreName = "BOXES" }

function view.layout(W, H)
  local L = base.grid(W, H, SIZE, SIZE)
  -- the last row and column of dots must fit inside the board
  L.sx, L.sy = floor((L.bw - 3) / SIZE), floor((L.bh - 2) / SIZE)
  L.debug = { sx = L.sx, sy = L.sy, size = SIZE }
  return L
end

local function seatColor(p) return p == 1 and C.red or C.blue end
local function isHere(mark, dir, x, y) return mark and mark.dir == dir and mark.x == x and mark.y == y end

function view.score(state) return state.score[1], state.score[2] end

function view.drawBoard(L, match)
  local s = match.state
  local sx, sy = L.sx, L.sy
  local function dotX(x) return L.x0 + (x - 1) * sx end
  local function dotY(y) return L.y0 + (y - 1) * sy end
  local hint = match.hint and os.epoch("local") < match.hintUntil and match.hint
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.bg)
  for y = 1, SIZE do
    for x = 1, SIZE do
      local owner = s.boxes[y][x]
      if owner ~= 0 then
        ui.fill(dotX(x) + 2, dotY(y) + 1, sx - 1, sy - 1, owner == 1 and C.redTint or C.blueTint)
      end
    end
  end
  -- a box just closed flashes in its owner's colour
  local t = base.animT(match)
  if t and match.anim.closed and floor(t * 4) % 2 == 0 then
    for _, box in ipairs(match.anim.closed) do
      ui.fill(dotX(box[1]) + 2, dotY(box[2]) + 1, sx - 1, sy - 1, seatColor(match.anim.seat))
    end
  end
  for y = 1, SIZE + 1 do
    for x = 1, SIZE do
      local who = s.h[y][x]
      local color = who ~= 0 and seatColor(who) or C.panel
      if isHere(s.last, "h", x, y) then color = C.hi end
      if isHere(hint, "h", x, y) then color = C.ok end
      ui.fill(dotX(x) + 2, dotY(y), sx - 1, 1, color)
    end
  end
  for y = 1, SIZE do
    for x = 1, SIZE + 1 do
      local who = s.v[y][x]
      local color = who ~= 0 and seatColor(who) or C.panel
      if isHere(s.last, "v", x, y) then color = C.hi end
      if isHere(hint, "v", x, y) then color = C.ok end
      ui.fill(dotX(x), dotY(y) + 1, 2, sy - 1, color)
    end
  end
  for y = 1, SIZE + 1 do
    for x = 1, SIZE + 1 do ui.fill(dotX(x), dotY(y), 2, 1, C.text) end
  end
end

--- The line nearest a touch. A touch in the very middle of a box could mean any side, so it means nothing.
function view.actionAt(L, _, px, py)
  local rx, ry = (px - L.x0) / L.sx, (py - L.y0) / L.sy
  if rx < -0.3 or ry < -0.3 or rx > SIZE + 0.3 or ry > SIZE + 0.3 then return nil end
  local col, row = math.max(0, math.min(SIZE - 1, floor(rx))), math.max(0, math.min(SIZE - 1, floor(ry)))
  local fx, fy = rx - col, ry - row
  local best = math.min(fx, 1 - fx, fy, 1 - fy)
  if best > NEAR_LINE then return nil end
  if best == fy then return { kind = "line", dir = "h", x = col + 1, y = row + 1 } end
  if best == 1 - fy then return { kind = "line", dir = "h", x = col + 1, y = row + 2 } end
  if best == fx then return { kind = "line", dir = "v", x = col + 1, y = row + 1 } end
  return { kind = "line", dir = "v", x = col + 2, y = row + 1 }
end

function view.hintText() return "Hint: the green line" end

function view.prompt(state, name)
  return name .. " to draw a line", state.turn == 1 and C.red or C.blue
end

function view.finalLine(match)
  local s = match.state
  if s.forfeit then
    return (s.winner == 1 and match.red or match.blue).name .. " WINS by forfeit", seatColor(s.winner)
  end
  if s.winner == 3 then return "DRAW", C.hi end
  local w = s.winner == 1 and match.red or match.blue
  return string.format("%s WINS %d-%d", w.name, s.score[s.winner], s.score[3 - s.winner]), seatColor(s.winner)
end

function view.howLine(r, duration)
  return string.format("%s  -  %d lines  -  %s  -  boxes %d-%d", r.forfeit and "BY FORFEIT" or "ALL BOXES CLAIMED", r.state.moves, duration,
    r.state.score[1], r.state.score[2])
end

function view.scoreLine(match)
  local s = match.state
  return string.format("%d lines - boxes %d-%d", s.moves, s.score[1], s.score[2])
end

function view.historyLine(h) return string.format("%d-%d boxes", h.boardsRed or 0, h.boardsBlue or 0) end

function view.onEvents(app, match, events)
  for _, ev in ipairs(events) do
    if ev.type == "line" then
      if ev.scored > 0 then
        base.animate(match, 500, { closed = ev.closed, seat = ev.seat })
        app.audio.play("capture")
        if match.state.winner == 0 then
          app.setToast((ev.seat == 1 and match.red or match.blue).name .. " scores and goes again", seatColor(ev.seat), 1500)
        end
      else
        app.audio.play("pen_line")
      end
    end
  end
end

local M = {
  id = "dots", title = "Dots and Boxes", short = "Dots+Boxes", chatTag = "DOTS", blurb = "Close the box, go again", color = "accent", accent = 0x9B7BFF,
  minSize = { w = 60, h = 40 }, cpuLevels = { "easy", "medium", "hard" },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Take turns drawing one line between two dots. Tap near the line you want.",
    "",
    "Draw the fourth side of a box and it is yours, and you go again. One line can close two boxes.",
    "",
    "When every line is drawn, the most boxes wins.",
    "",
    "Avoid drawing a box's third side, because that hands it to your opponent. Late in the game the boxes join into long chains: leaving your opponent the last two of a chain can win you the next one.",
  },
  badges = {
    shutout = { name = "Shutout", text = "Win with 20 boxes or more", test = function(m, sd, _, won)
      return won and not m.forfeit and sd.boards >= 20
    end },
    close = { name = "Photo Finish", text = "Win by a single box", test = function(m, sd, _, won)
      return won and not m.forfeit and sd.boards == 13
    end },
  },
}

function M.chooseAction(state, level, opts)
  return ai.choose(state, level, opts)
end

function M.summarize(match)
  local s = match.state
  return { moves = s.moves, boardsRed = s.score[1], boardsBlue = s.score[2] }
end

return base.fill(M)
