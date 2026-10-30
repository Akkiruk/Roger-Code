-- uttt_ui.lua
-- Drawing for Ultimate Tic-Tac-Toe on a surface: layout, text, buttons, pieces and the board.
-- Coordinates are surface cells (0-based). At text scale 0.5 a 6x6 monitor is 120x81 cells.

local rules = require("uttt_rules")

local M = {}

-- Palette slots (values are set from uttt_config.PALETTE by the app)
M.C = {
  bg = colors.black, panel = colors.gray, line = colors.lightGray, text = colors.white,
  red = colors.red, blue = colors.blue, redTint = colors.brown, blueTint = colors.lightBlue,
  hi = colors.yellow, hiTint = colors.magenta, tie = colors.pink, ok = colors.green, warn = colors.orange,
  accent = colors.purple, info = colors.cyan, soft = colors.lime,
}
local C = M.C
local max, min = math.max, math.min

local surfaceApi, font, screen

function M.init(surfaceLib, fontObj, scr)
  surfaceApi, font, screen = surfaceLib, fontObj, scr
end

function M.setScreen(scr) screen = scr end

function M.fontHeight() return font.height end

function M.textWidth(str) return (surfaceApi.getTextSize(tostring(str), font)) end

--- Fit a string into maxWidth cells with the pixel font, shortening with ".." when needed.
local function fit(str, maxWidth)
  str = tostring(str)
  if M.textWidth(str) <= maxWidth then return str end
  while #str > 1 do
    str = str:sub(1, #str - 1)
    if M.textWidth(str .. "..") <= maxWidth then return str .. ".." end
  end
  return str
end
M.fit = fit

--- Pixel-font text. align: "left" (x is the left edge), "center" (x is the centre), "right" (x is the right edge).
function M.text(str, x, y, color, align, maxWidth)
  str = maxWidth and fit(str, maxWidth) or tostring(str)
  local w = M.textWidth(str)
  local dx = x
  if align == "center" then dx = x - math.floor(w / 2) elseif align == "right" then dx = x - w end
  if dx < 0 then dx = 0 end
  screen:drawText(str, font, dx, y, color)
  return w
end

--- Native small text (one cell per character).
function M.small(str, x, y, fg, bg, align, maxWidth)
  str = tostring(str)
  if maxWidth and #str > maxWidth then str = str:sub(1, math.max(0, maxWidth - 2)) .. ".." end
  local dx = x
  if align == "center" then dx = x - math.floor(#str / 2) elseif align == "right" then dx = x - #str end
  if dx < 0 then dx = 0 end
  screen:drawString(str, dx, y, bg or C.bg, fg or C.text)
  return #str
end

function M.fill(x, y, w, h, color)
  if w > 0 and h > 0 then screen:fillRect(x, y, w, h, color, nil, " ") end
end

function M.frame(x, y, w, h, color, thick)
  thick = thick or 1
  M.fill(x, y, w, thick, color)
  M.fill(x, y + h - thick, w, thick, color)
  M.fill(x, y, thick, h, color)
  M.fill(x + w - thick, y, thick, h, color)
end

--- Draw a solid line in a colour.
function M.line(x1, y1, x2, y2, color)
  screen:drawLine(x1, y1, x2, y2, color, nil, " ")
end

-- ---------------------------------------------------------------- buttons

local buttons = {}

function M.clearButtons() buttons = {} end
function M.buttons() return buttons end

--- Draw and register a button. opts: label, color, fg, enabled (default true), small (native text)
function M.button(id, x, y, w, h, label, color, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  local bg = enabled and (color or C.panel) or C.panel
  local fg = opts.fg or (enabled and ((bg == C.hi or bg == C.ok or bg == C.soft or bg == C.warn or bg == C.info or bg == C.text) and C.bg or C.text) or C.line)
  M.fill(x, y, w, h, bg)
  if opts.frame then M.frame(x, y, w, h, opts.frame) end
  if label and label ~= "" then
    local ty = y + math.floor((h - (opts.small and 1 or font.height)) / 2)
    if opts.small or M.textWidth(label) > w - 2 then
      M.small(label, x + math.floor(w / 2), y + math.floor((h - 1) / 2), fg, bg, "center", w - 1)
    else
      M.text(label, x + math.floor(w / 2), ty, fg, "center")
    end
  end
  buttons[#buttons + 1] = { id = id, x = x, y = y, w = w, h = h, label = label, enabled = enabled, data = opts.data }
end

--- Register a touch area without drawing anything.
function M.region(id, x, y, w, h, data)
  buttons[#buttons + 1] = { id = id, x = x, y = y, w = w, h = h, enabled = true, data = data }
end

--- Which enabled button covers surface cell (px, py)? Later buttons win.
function M.hit(px, py)
  for i = #buttons, 1, -1 do
    local b = buttons[i]
    if b.enabled and px >= b.x and px < b.x + b.w and py >= b.y and py < b.y + b.h then return b end
  end
  return nil
end

-- ---------------------------------------------------------------- layout

--- Work out the game screen layout for a W x H surface.
function M.layout(W, H)
  local hdr = font.height + 4
  local statusH = font.height + 1
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
      M.line(x + t, y, x + w - 1 - (thick - 1 - t), y + h - 1, color)
      M.line(x + w - 1 - t, y, x + (thick - 1 - t), y + h - 1, color)
    end
  elseif w >= 14 and h >= 10 then
    -- large (a won board): a proper ring
    screen:fillEllipse(x, y, w, h, color, nil, " ")
    local iw, ih = w - thick * 2, h - thick
    if iw >= 2 and ih >= 2 then
      screen:fillEllipse(x + thick, y + math.floor((h - ih) / 2), iw, ih, bg, nil, " ")
    end
  else
    -- small cell: a rounded ring built from rectangles reads better than a tiny ellipse
    M.fill(x, y, w, h, color)
    M.fill(x, y, 1, 1, bg); M.fill(x + w - 1, y, 1, 1, bg)
    M.fill(x, y + h - 1, 1, 1, bg); M.fill(x + w - 1, y + h - 1, 1, 1, bg)
    if w >= 4 and h >= 3 then M.fill(x + 1, y + 1, w - 2, h - 2, bg) end
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
      M.fill(x1 - 1, y1 - 1, bwid + 1, bhei + 1, C.bg)
      for c = 1, 9 do
        local cx, cy = rules.toXY(b, c)
        local tx, ty = L.colX[cx], L.rowY[cy]
        local tile = bgTile
        M.fill(tx, ty, L.cw - 1, L.ch - 1, tile)
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
        M.small("TIE", x1 + math.floor(bwid / 2), y1 + math.floor(bhei / 2), C.text, C.tie, "center")
      end
    else
      -- decided: one large mark on a tinted background, with the winning line struck through underneath
      M.fill(x1 - 1, y1 - 1, bwid + 1, bhei + 1, C.bg)
      M.fill(x1, y1, bwid - 1, bhei - 1, bgTile)
      M.piece(owner, x1 + 2, y1 + 1, bwid - 5, bhei - 3, nil, math.max(2, math.floor(L.cw / 3)), bgTile)
    end

    if active then
      M.frame(x1 - 1, y1 - 1, bwid + 1, bhei + 1, C.hi, 1)
    end
  end

  -- last move marker
  if last then
    local cx, cy = rules.toXY(last[1], last[2])
    if s.sub[last[1]] == 0 or s.sub[last[1]] == 3 then
      M.frame(L.colX[cx], L.rowY[cy], L.cw - 1, L.ch - 1, C.text, 1)
    end
  end
  -- hint marker
  if view.hint then
    local cx, cy = rules.toXY(view.hint[1], view.hint[2])
    M.frame(L.colX[cx], L.rowY[cy], L.cw - 1, L.ch - 1, C.ok, 1)
    M.fill(L.colX[cx] + 1, L.rowY[cy] + 1, L.cw - 3, L.ch - 3, C.ok)
  end
  -- flash on a freshly placed piece
  if view.flash and view.flash.on then
    local cx, cy = rules.toXY(view.flash.b, view.flash.c)
    M.frame(L.colX[cx] - 1, L.rowY[cy] - 1, L.cw + 1, L.ch + 1, C.hi, 1)
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
    local color = s.winner == 1 and C.red or C.blue
    for d = -1, 1 do
      if math.abs(bx - ax) >= math.abs(by - ay) then M.line(ax, ay + d, bx, by + d, C.hi) else M.line(ax + d, ay, bx + d, by, C.hi) end
    end
    local _ = color
  end
end

return M
