-- games/uttt/board.lua
-- The Ultimate Tic-Tac-Toe board on the Arcade's surface: layout, touch mapping, pieces. At text scale 0.5 a 6x6
-- monitor is 120x81 cells.

local rules = require("games.uttt.rules")
local ui = require("arcade_ui")

local M = {}
local C = ui.C
local max, min = math.max, math.min

M.C = C

-- ---------------------------------------------------------------- layout

--- Work out the game screen layout for a W x H surface.
function M.layout(W, H)
  local hdr = ui.fontHeight() + 4
  local statusH = ui.fontHeight() + 1
  local gx, gy = 3, 2
  local function candidate(side)
    local avail = H - hdr - statusH - 3 - (side and 0 or 8)
    local ch = math.floor((avail - 2 * gy) / 9)
    local cw = math.floor(ch * 1.5)
    local maxCw
    if side then maxCw = math.floor((W - 34 - 2 * gx) / 9) else maxCw = math.floor((W - 4 - 2 * gx) / 9) end
    if cw > maxCw then cw = maxCw end
    if cw < 4 then cw = 4 end
    if ch < 3 then ch = 3 end
    return { cw = cw, ch = ch, side = side, score = cw * ch }
  end
  local a, b = candidate(true), candidate(false)
  local pick = (a.score >= b.score) and a or b
  local cw, ch = pick.cw, pick.ch
  local bw, bh = 9 * cw + 2 * gx, 9 * ch + 2 * gy
  local L = {
    W = W, H = H, hdr = hdr, statusH = statusH, cw = cw, ch = ch, gx = gx, gy = gy, bw = bw, bh = bh, side = pick.side,
  }
  L.x0 = math.floor((W - bw) / 2)
  L.y0 = hdr + 2
  L.colX, L.rowY = {}, {}
  for i = 1, 9 do
    local bi = math.floor((i - 1) / 3)
    L.colX[i] = L.x0 + (i - 1) * cw + bi * gx
    L.rowY[i] = L.y0 + (i - 1) * ch + bi * gy
  end
  L.statusY = L.y0 + bh + 1
  L.sideW = L.x0 - 2
  L.footY = L.statusY + statusH + 1
  return L
end

--- Layout for a board placed anywhere (the idle demo, a small final board): cell size and top-left corner.
function M.layoutAt(x0, y0, cw, ch, gx, gy)
  gx, gy = gx or 2, gy or 1
  local L = { cw = cw, ch = ch, gx = gx, gy = gy, x0 = x0, y0 = y0, bw = 9 * cw + 2 * gx, bh = 9 * ch + 2 * gy, colX = {}, rowY = {} }
  for i = 1, 9 do
    local bi = math.floor((i - 1) / 3)
    L.colX[i] = x0 + (i - 1) * cw + bi * gx
    L.rowY[i] = y0 + (i - 1) * ch + bi * gy
  end
  return L
end

--- Map a surface cell to the board and cell it covers. Returns b, c or nil.
function M.cellAt(L, px, py)
  local gxI, gyI
  for i = 1, 9 do
    if px >= L.colX[i] and px < L.colX[i] + L.cw then gxI = i end
    if py >= L.rowY[i] and py < L.rowY[i] + L.ch then gyI = i end
  end
  if gxI and gyI then return rules.fromXY(gxI, gyI) end
  -- a touch in the gap between cells still counts for the nearest cell
  local bestX, bestY, dx, dy = nil, nil, 1e9, 1e9
  for i = 1, 9 do
    local cx, cy = L.colX[i] + L.cw / 2, L.rowY[i] + L.ch / 2
    if math.abs(px - cx) < dx then dx = math.abs(px - cx); bestX = i end
    if math.abs(py - cy) < dy then dy = math.abs(py - cy); bestY = i end
  end
  if bestX and bestY and dx <= L.cw and dy <= L.ch then return rules.fromXY(bestX, bestY) end
  return nil
end

-- ---------------------------------------------------------------- pieces

local function playerColor(p) return p == 1 and C.red or C.blue end
M.playerColor = playerColor

--- Draw an X (player 1) or O (player 2) inside the rectangle (x, y, w, h).
function M.piece(p, x, y, w, h, color, thick, bg)
  color = color or playerColor(p)
  thick = thick or 1
  bg = bg or C.panel
  if p == 1 then
    for t = 0, thick - 1 do
      ui.line(x + t, y, x + w - 1 - (thick - 1 - t), y + h - 1, color)
      ui.line(x + w - 1 - t, y, x + (thick - 1 - t), y + h - 1, color)
    end
  elseif w >= 14 and h >= 10 then
    -- large (a won board): a proper ring
    ui.ellipse(x, y, w, h, color)
    local iw, ih = w - thick * 2, h - thick
    if iw >= 2 and ih >= 2 then
      ui.ellipse(x + thick, y + math.floor((h - ih) / 2), iw, ih, bg)
    end
  else
    -- small cell: a rounded ring built from rectangles reads better than a tiny ellipse
    ui.fill(x, y, w, h, color)
    ui.fill(x, y, 1, 1, bg); ui.fill(x + w - 1, y, 1, 1, bg)
    ui.fill(x, y + h - 1, 1, 1, bg); ui.fill(x + w - 1, y + h - 1, 1, 1, bg)
    if w >= 4 and h >= 3 then ui.fill(x + 1, y + 1, w - 2, h - 2, bg) end
  end
end

-- ---------------------------------------------------------------- board

--- Draw the board. view = {
---   state, hint = {b, c}, last = {b, c}, flash = {b, c, on}, subBlink = b, hover }
function M.board(L, view)
  local s = view.state
  local last = view.last
  for b = 1, 9 do
    local owner = s.sub[b]
    local bx, by = rules.toXY(b, 1)
    local x1, y1 = L.colX[bx], L.rowY[by]
    local bwid, bhei = 3 * L.cw, 3 * L.ch
    local active = s.winner == 0 and owner == 0 and (s.forced == nil or s.forced == b)
    local bgTile = C.panel
    if active then bgTile = C.hiTint end
    if owner == 1 then bgTile = C.redTint elseif owner == 2 then bgTile = C.blueTint elseif owner == 3 then bgTile = C.tie end

    if owner == 0 or owner == 3 then
      -- backing so the gaps between tiles show the board colour
      ui.fill(x1 - 1, y1 - 1, bwid + 1, bhei + 1, C.bg)
      for c = 1, 9 do
        local cx, cy = rules.toXY(b, c)
        local tx, ty = L.colX[cx], L.rowY[cy]
        local tile = bgTile
        ui.fill(tx, ty, L.cw - 1, L.ch - 1, tile)
        local v = s.cells[(b - 1) * 9 + c]
        if v ~= 0 then
          -- a cell is taller than wide (about 2:3), so a square-looking piece is wide and short
          local tw, th = L.cw - 1, L.ch - 1
          local pw = max(3, tw - 1)
          local ph = max(3, min(th, math.floor(pw * 2 / 3 + 0.5)))
          M.piece(v, tx + math.floor((tw - pw) / 2), ty + math.floor((th - ph) / 2), pw, ph, owner == 3 and C.line or nil, 1, tile)
        end
      end
      if owner == 3 then
        ui.small("TIE", x1 + math.floor(bwid / 2), y1 + math.floor(bhei / 2), C.text, C.tie, "center")
      end
    else
      -- decided: one large mark on a tinted background, with the winning line struck through underneath
      ui.fill(x1 - 1, y1 - 1, bwid + 1, bhei + 1, C.bg)
      ui.fill(x1, y1, bwid - 1, bhei - 1, bgTile)
      M.piece(owner, x1 + 2, y1 + 1, bwid - 5, bhei - 3, nil, math.max(2, math.floor(L.cw / 3)), bgTile)
    end

    if active then
      ui.frame(x1 - 1, y1 - 1, bwid + 1, bhei + 1, C.hi, 1)
    end
  end

  -- last move marker
  if last then
    local cx, cy = rules.toXY(last[1], last[2])
    if s.sub[last[1]] == 0 or s.sub[last[1]] == 3 then
      ui.frame(L.colX[cx], L.rowY[cy], L.cw - 1, L.ch - 1, C.text, 1)
    end
  end
  -- hint marker
  if view.hint then
    local cx, cy = rules.toXY(view.hint[1], view.hint[2])
    ui.frame(L.colX[cx], L.rowY[cy], L.cw - 1, L.ch - 1, C.ok, 1)
    ui.fill(L.colX[cx] + 1, L.rowY[cy] + 1, L.cw - 3, L.ch - 3, C.ok)
  end
  -- flash on a freshly placed piece
  if view.flash and view.flash.on then
    local cx, cy = rules.toXY(view.flash.b, view.flash.c)
    ui.frame(L.colX[cx] - 1, L.rowY[cy] - 1, L.cw + 1, L.ch + 1, C.hi, 1)
  end
  -- winning meta line
  if s.winner ~= 0 and s.metaLine then
    local l = rules.LINES[s.metaLine]
    local function centre(b)
      local bx, by = rules.toXY(b, 5)
      return L.colX[bx] + math.floor(L.cw / 2), L.rowY[by] + math.floor(L.ch / 2)
    end
    local ax, ay = centre(l[1])
    local bx, by = centre(l[3])
    for d = -1, 1 do
      if math.abs(bx - ax) >= math.abs(by - ay) then ui.line(ax, ay + d, bx, by + d, C.hi) else ui.line(ax + d, ay, bx + d, by, C.hi) end
    end
  end
end

return M
