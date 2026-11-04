-- games/uno/draw.lua
-- How an UNO card looks, at any size, for both screens. A card has a cream edge and its colour inside. A card with room has a cream
-- oval in the middle with a tall numeral or symbol on it in the card's colour, shadowed in black so even yellow reads on cream; a
-- wild is black with the four colours filling its oval, and a Wild Draw Four has +4 over them. A small card has no oval: its number
-- or symbol is drawn straight on the colour. The edge says what the card is in small letters, top left and bottom right, so a card
-- can be read even when the middle is hard to see from across a room.
--   card(c, x, y, w, h, card, opts)   any size from 8x7 up. opts.dim greys it, opts.lit frames it gold, opts.color shows the
--                                     colour a played wild was given
--   mini(c, x, y, card, color)        6x4, the size of a word
--   back(c, x, y, w, h)               the back: black, a red oval, UNO in gold
--   pile(c, x, y, w, h, depth)        backs stacked, for the draw pile
--   fan(c, x, y, count, room)         a hand of small backs fanned out, for counting a hand on the wall
--   pip(c, x, y)                      2x2, a single small back
--   logo(c, cx, y, scale)             UNO in the deck's colours

local cards = require("games.uno.cards")
local font = require("lib.casino.font")
local theme = require("lib.casino.theme")

local C = theme.C
local M = {}

-- The four colours of the deck in the casino's palette
M.INK = { r = C.red, y = C.gold, g = C.win, b = C.blue, w = C.ink }
-- What reads on top of each colour
M.ON = { r = C.text, y = C.ink, g = C.ink, b = C.text, w = C.text }

-- Symbols drawn in cells, one character a cell: # is the symbol's colour. Each comes in shapes for different rooms, and the one
-- that fills the room best is used: square ones for a wide oval or a small card, tall ones for a seat's narrow oval.
local SYMBOLS = {
  S = {
    { ".###.", "#..##", "#.#.#", "##..#", ".###." },
    { ".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###." },
  },
  R = {
    { ".#...", "#####", ".#.#.", "#####", "...#." },
    { ".#...", "##...", "#####", "##...", ".#...", "...#.", "...##", "#####", "...##", "...#." },
    { "..#......", ".##......", "#########", ".##......", "..#......", "......#..", "......##.", "#########", "......##.", "......#.." },
  },
  D = {
    { ".....##.", ".#..#..#", "###...#.", ".#..#...", "....####" },
    { "..#..", ".###.", "..#..", ".....", ".##..", "#..#.", "..#..", ".#...", "####." },
    { ".#.###", "###..#", ".#.###", "...#..", "...###" },
  },
  F = {
    { "....#..#", ".#..#..#", "###.####", ".#.....#", ".......#" },
    { "..#..", ".###.", "..#..", ".....", "..#..", ".##..", "#.#..", "####.", "..#.." },
    { "...#.#", "...#.#", ".#.###", "###..#", ".#...#" },
  },
}

--- Paint rows of # in one colour, each # kx cells wide and ky tall.
local function paint(c, x, y, rows, color, kx, ky)
  for r, bits in ipairs(rows) do
    for col = 1, #bits do
      if bits:sub(col, col) == "#" then c:rect(x + (col - 1) * kx, y + (r - 1) * ky, kx, ky, color) end
    end
  end
end

--- Rows centred in a box, as big as fits, never more than twice as tall per cell as wide, so a numeral grows tall and narrow the
-- way the real cards print them. bold draws each stroke two cells wide when there is a cell to spare either side, so thin strokes
-- still read across a room.
local function stamp(c, x, y, w, h, rows, color, bold)
  local rw, rh = #rows[1], #rows
  local kx = math.min(3, math.floor(w / rw))
  local ky = math.min(3, math.floor(h / rh))
  if kx < 1 or ky < 1 then return false end
  kx = math.min(kx, ky)
  ky = math.min(ky, 2 * kx)
  local pad = (bold and kx == 1 and rw + 1 <= w) and 1 or 0
  local sw, sh = rw * kx + pad, rh * ky
  local sx, sy = x + math.floor((w - sw) / 2), y + math.floor((h - sh) / 2)
  if pad == 1 then paint(c, sx + 1, sy, rows, color, kx, ky) end
  paint(c, sx, sy, rows, color, kx, ky)
  return true
end

--- The shape of a symbol that fills a box best. A shape stretched taller than it was drawn counts for less, and one blown up a
-- little less: a symbol drawn tall, or drawn big, looks better than a small one pulled out of shape.
local function bestShape(shapes, w, h)
  local best, bestArea = nil, -1
  for _, rows in ipairs(shapes) do
    local rw, rh = #rows[1], #rows
    local kx, ky = math.min(3, math.floor(w / rw)), math.min(3, math.floor(h / rh))
    if kx >= 1 and ky >= 1 then
      kx = math.min(kx, ky)
      ky = math.min(ky, 2 * kx)
      local area = rw * kx * rh * ky * (ky > kx and 0.6 or 1) * (kx > 1 and 0.85 or 1)
      if area > bestArea then best, bestArea = rows, area end
    end
  end
  return best
end

--- The rows of a digit in the pixel font, without the blank row under it.
local function digit(ch)
  local rows = font.glyph(ch).rows
  local out = {}
  for i = 1, 5 do out[i] = rows[i] end
  return out
end

--- Knock the corners off a block so it reads as round: one cell, or a little more on a big block.
local function round(c, x, y, w, h, around)
  local cut = { { 0, 0 }, { w - 1, 0 }, { 0, h - 1 }, { w - 1, h - 1 } }
  if w >= 12 and h >= 10 then
    for _, d in ipairs({ { 1, 0 }, { w - 2, 0 }, { 1, h - 1 }, { w - 2, h - 1 }, { 0, 1 }, { w - 1, 1 }, { 0, h - 2 }, { w - 1, h - 2 } }) do
      cut[#cut + 1] = d
    end
  end
  for _, d in ipairs(cut) do c:rect(x + d[1], y + d[2], 1, 1, around) end
end

--- The four colours in a block, for a wild.
local function quarters(c, x, y, w, h)
  local hw, hh = math.floor(w / 2), math.floor(h / 2)
  c:rect(x, y, hw, hh, M.INK.r)
  c:rect(x + hw, y, w - hw, hh, M.INK.b)
  c:rect(x, y + hh, hw, h - hh, M.INK.y)
  c:rect(x + hw, y + hh, w - hw, h - hh, M.INK.g)
end

--- What goes in a card's middle: on an oval when there is room, straight on the colour when not.
local function middle(c, ix, iy, iw, ih, card, color, kind, opts)
  local fill = opts.dim and C.panel or M.INK[color]
  local on = opts.dim and C.mute or M.ON[color]
  -- Only a big card, the wall's discard, has room for the oval: on a seat's narrow card it would squeeze the numeral thin
  local roomy = iw >= 12 and ih >= 10 and not opts.dim
  if roomy then
    local mx, my = math.max(1, math.floor(iw / 8)), math.max(1, math.floor(ih / 8))
    local ox, oy, ow, oh = ix + mx, iy + my, iw - 2 * mx, ih - 2 * my
    if kind == "W" or kind == "F" then
      quarters(c, ox, oy, ow, oh)
    else
      c:rect(ox, oy, ow, oh, C.card)
    end
    round(c, ox, oy, ow, oh, fill)
    -- Yellow on cream is too faint, so a yellow card's numeral is black
    local ink = color == "y" and C.ink or M.INK[color]
    if cards.isNumber(card) then
      stamp(c, ox + 2, oy + 1, ow - 4, oh - 2, digit(kind), ink)
    elseif kind == "F" then
      stamp(c, ox + 1, oy + 1, ow - 2, oh - 2, bestShape(SYMBOLS.F, ow - 2, oh - 2), C.ink)
    elseif SYMBOLS[kind] then
      stamp(c, ox + 2, oy + 1, ow - 4, oh - 2, bestShape(SYMBOLS[kind], ow - 4, oh - 2), ink)
    end
    return
  end
  if cards.isNumber(card) then
    -- A cell of colour either side, so a white numeral never runs into the cream edge
    stamp(c, ix + 1, iy, iw - 2, ih, digit(kind), on, true)
  elseif kind == "W" then
    local qw, qh = math.max(4, math.floor(iw * 0.6)), math.max(2, math.floor(ih * 0.6))
    local qx, qy = ix + math.floor((iw - qw) / 2), iy + math.floor((ih - qh) / 2)
    if opts.dim then c:rect(qx, qy, qw, qh, C.panel2) else quarters(c, qx, qy, qw, qh) end
  elseif kind == "F" then
    if not opts.dim then
      -- A little of each colour in the corners
      c:rect(ix, iy, 2, 1, M.INK.r)
      c:rect(ix + iw - 2, iy, 2, 1, M.INK.b)
      c:rect(ix, iy + ih - 1, 2, 1, M.INK.y)
      c:rect(ix + iw - 2, iy + ih - 1, 2, 1, M.INK.g)
    end
    local rows = bestShape(SYMBOLS.F, iw, ih)
    if rows then stamp(c, ix, iy, iw, ih, rows, opts.dim and C.mute or C.text, true) end
  elseif SYMBOLS[kind] then
    local rows = bestShape(SYMBOLS[kind], iw, ih)
    if rows then stamp(c, ix, iy, iw, ih, rows, on, kind == "D") end
  end
end

function M.card(c, x, y, w, h, card, opts)
  opts = opts or {}
  local color = cards.color(card)
  local kind = cards.kind(card)
  local edge = opts.dim and C.panel2 or C.card
  local fill = opts.dim and C.panel or M.INK[color]
  c:rect(x, y, w, h, edge)
  c:rect(x + 1, y + 1, w - 2, h - 2, fill)
  -- The edge says what it is, in the card's colour: top left, and bottom right on a tall card
  local label = cards.label(card)
  local labelInk = opts.dim and C.mute or ((color == "w" or color == "y") and C.ink or M.INK[color])
  if #label <= w - 2 then
    c:text(x + 1, y, label, labelInk, edge)
    if h >= 9 then c:text(x + w - 1 - #label, y + h - 1, label, labelInk, edge) end
  end
  middle(c, x + 1, y + 1, w - 2, h - 2, card, color, kind, opts)
  -- A played wild shows the colour it was given along its bottom edge
  if opts.color and color == "w" and M.INK[opts.color] then c:rect(x, y + h - 1, w, 1, M.INK[opts.color]) end
  if opts.lit then c:frame(x - 1, y - 1, w + 2, h + 2, C.gold) end
end

--- A card the size of a word: a cream top with what it is, and its colour below.
function M.mini(c, x, y, card, color)
  local kind = cards.color(card)
  local label = cards.label(card)
  if #label > 4 then label = label:sub(1, 4) end
  c:rect(x, y, 6, 1, C.card)
  c:text(x + 3 - math.floor(#label / 2), y, label, C.ink, C.card)
  if kind == "w" then
    quarters(c, x, y + 1, 6, 2)
    c:rect(x, y + 3, 6, 1, M.INK[color] or C.ink)
    return
  end
  c:rect(x, y + 1, 6, 3, M.INK[kind])
end

--- The back of a card: black inside a cream edge, a red oval, UNO across it in gold.
function M.back(c, x, y, w, h)
  c:rect(x, y, w, h, C.card)
  c:rect(x + 1, y + 1, w - 2, h - 2, C.ink)
  if w < 8 or h < 5 then return end
  local ox, oy, ow, oh = x + 2, y + 2, w - 4, h - 4
  c:rect(ox, oy, ow, oh, C.red)
  round(c, ox, oy, ow, oh, C.ink)
  local cx, cy = x + math.floor(w / 2), y + math.floor(h / 2)
  if c:bigWidth("UNO", 1) <= ow - 2 and oh >= 8 then
    -- A gold shadow under black letters, the way the deck prints its name
    c:big(cx - math.floor(c:bigWidth("UNO", 1) / 2) + 1, cy - 2, "UNO", C.ink, 1)
    c:big(cx - math.floor(c:bigWidth("UNO", 1) / 2), cy - 3, "UNO", C.gold, 1)
  else
    c:rect(ox, cy - 1, ow, 3, C.gold)
    round(c, ox, cy - 1, ow, 3, C.red)
    c:textCenter(cx + 1, cy, "UNO", C.ink, C.gold)
  end
end

--- The draw pile: backs stacked, the stack a little deeper the more cards are left.
function M.pile(c, x, y, w, h, depth)
  depth = math.max(0, math.min(3, depth or 0))
  for i = depth, 1, -1 do
    c:rect(x + i, y + i, w, h, C.card)
    c:rect(x + i + 1, y + i, w - 1, h - 1, C.panel2)
  end
  M.back(c, x, y, w, h)
end

--- A single small back, 2x2.
function M.pip(c, x, y)
  c:rect(x, y, 2, 2, C.card)
  c:rect(x, y + 1, 2, 1, C.red)
end

--- A hand of small backs fanned out from x, overlapping more the more there are: each back is 3 wide and 4 tall, cream round a red
-- middle. Two rows when one would crowd. Says how many it could not show.
function M.fan(c, x, y, count, room)
  -- Two cells apart at least, or the edges run together into one cream bar
  local perRow = math.floor((room - 3) / 2) + 1
  local rows = count > perRow and 2 or 1
  local shown = 0
  for row = 1, rows do
    local n = rows == 1 and count or (row == 1 and math.ceil(count / 2) or math.floor(count / 2))
    n = math.min(n, perRow)
    for i = 1, n do
      local cx = x + (i - 1) * 2
      local cy = y + (row - 1) * 4
      c:rect(cx, cy, 3, 4, C.card)
      c:rect(cx + 1, cy + 1, 1, 2, C.red)
    end
    shown = shown + n
  end
  return count - shown
end

--- UNO in the deck's colours, centred on cx.
function M.logo(c, cx, y, scale)
  local word, inks = "UNO", { M.INK.r, M.INK.y, M.INK.g }
  local x = cx - math.floor(c:bigWidth(word, scale) / 2)
  for i = 1, #word do
    local ch = word:sub(i, i)
    c:big(x, y, ch, inks[i], scale)
    x = x + c:bigWidth(ch, scale) + scale
  end
end

return M
