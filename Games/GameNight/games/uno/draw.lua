-- games/uno/draw.lua
-- How an UNO card looks, at any size, for both screens. A card has a cream edge, its colour inside, and its number or symbol in
-- the middle: the pixel font for numbers, small pictures for Skip, Reverse, +2 and +4, and the four colours for a wild. The edge's
-- top row says what the card is in small letters, so a card can be read even when the middle is hard to see from across a room.
-- Numbers and symbols are drawn twice the size whenever the card has room.
--   card(c, x, y, w, h, card, opts)   any size from 10x7 up. opts.dim greys it, opts.lit frames it gold, opts.color shows the
--                                     colour a played wild was given
--   mini(c, x, y, card, color)        6x4, for the row of recent plays
--   back(c, x, y, w, h)               the back, for the draw pile
--   pip(c, x, y)                      2x2, for counting a hand on the wall
--   logo(c, cx, y, scale)             UNO in the deck's colours

local cards = require("games.uno.cards")
local theme = require("lib.casino.theme")

local C = theme.C
local M = {}

-- The four colours of the deck in the casino's palette
M.INK = { r = C.red, y = C.gold, g = C.win, b = C.blue, w = C.ink }
-- What reads on top of each colour
M.ON = { r = C.text, y = C.ink, g = C.ink, b = C.text, w = C.text }

-- Symbols drawn in cells, one character a cell: # is the symbol's colour. All at most 8 wide and 5 tall, so they fit a 10x7 card
local SYMBOLS = {
  S = { ".###.", "#..##", "#.#.#", "##..#", ".###." },
  R = { ".#...", "#####", ".#.#.", "#####", "...#." },
  D = { ".....##.", ".#..#..#", "###...#.", ".#..#...", "....####" },
  F = { "....#..#", ".#..#..#", "###.####", ".#.....#", ".......#" },
}

local function scaled(rows, k)
  if k <= 1 then return rows end
  local out = {}
  for _, row in ipairs(rows) do
    local line = row:gsub(".", function(ch) return ch:rep(k) end)
    for _ = 1, k do out[#out + 1] = line end
  end
  return out
end

--- The biggest whole scale at which something w by h fits in room.
local function fit(w, h, roomW, roomH)
  local k = 1
  while (k + 1) * w <= roomW and (k + 1) * h <= roomH and k < 3 do k = k + 1 end
  return k
end

-- Bigger drawings for a tall card's 8x12 middle, where twice the small ones would not fit across
local TALL = {
  S = { "..####..", ".#....#.", "#....###", "#...##.#", "#..##..#", "#.##...#", "###....#", ".#....#.", "..####.." },
  R = { "..#.....", ".##.....", "########", ".##.....", "..#.....", "........", ".....#..", ".....##.", "########",
    ".....##.", ".....#.." },
  D = { "....####", ".......#", ".......#", ".#.....#", "###.####", ".#..#...", "....#...", "....#...", "....####" },
  F = { "....#..#", "....#..#", "....#..#", ".#..#..#", "###.####", ".#.....#", ".......#", ".......#", ".......#" },
}

--- Rows k times as tall, the same width: a tall card's +2 and +4.
local function taller(rows, k)
  local out = {}
  for _, row in ipairs(rows) do
    for _ = 1, k do out[#out + 1] = row end
  end
  return out
end

local function symbol(c, x, y, w, h, rows, color, kind)
  local k = fit(#rows[1], #rows, w, h)
  local tall = TALL[kind]
  if k == 1 and tall and #tall[1] <= w and #tall <= h then
    rows = tall
  elseif k == 1 and 2 * #rows <= h then
    rows = taller(rows, 2)
  else
    rows = scaled(rows, k)
  end
  local sw, sh = #rows[1], #rows
  c:sprite(x + math.floor((w - sw) / 2), y + math.floor((h - sh) / 2), rows, { ["#"] = color })
end

--- The four colours in a square, for a wild.
local function quarters(c, x, y, w, h)
  local hw, hh = math.floor(w / 2), math.floor(h / 2)
  c:rect(x, y, hw, hh, M.INK.r)
  c:rect(x + hw, y, w - hw, hh, M.INK.b)
  c:rect(x, y + hh, hw, h - hh, M.INK.y)
  c:rect(x + hw, y + hh, w - hw, h - hh, M.INK.g)
end

function M.card(c, x, y, w, h, card, opts)
  opts = opts or {}
  local color = cards.color(card)
  local kind = cards.kind(card)
  local edge = opts.dim and C.panel2 or C.card
  local fill = opts.dim and C.panel or M.INK[color]
  local on = opts.dim and C.mute or M.ON[color]
  c:rect(x, y, w, h, edge)
  c:rect(x + 1, y + 1, w - 2, h - 2, fill)
  -- The top edge says what it is, in the card's colour
  local label = cards.label(card)
  local labelInk = opts.dim and C.mute or (color == "w" and C.ink or M.INK[color])
  if color == "y" and not opts.dim then labelInk = C.ink end
  if #label <= w - 2 then c:text(x + 1, y, label, labelInk, edge) end
  -- The middle, inside the edge
  local ix, iy, iw, ih = x + 1, y + 1, w - 2, h - 2
  if cards.isNumber(card) then
    local k = fit(4, 5, iw, ih)
    -- A numeral as wide as the middle touches the cream edge: in white it would run into it, so it goes dark
    local ink = (4 * k >= iw and not opts.dim) and C.ink or on
    c:bigCenter(ix + math.floor(iw / 2), iy + math.floor((ih - 5 * k) / 2), kind, ink, k)
  elseif kind == "W" then
    local qw, qh = math.max(4, math.floor(iw * 0.6)), math.max(2, math.floor(ih * 0.6))
    local qx, qy = ix + math.floor((iw - qw) / 2), iy + math.floor((ih - qh) / 2)
    if opts.dim then c:rect(qx, qy, qw, qh, C.panel2) else quarters(c, qx, qy, qw, qh) end
  elseif kind == "F" then
    if not opts.dim and h >= 9 then
      -- A little of each colour in the corners
      c:rect(ix, iy, 2, 1, M.INK.r)
      c:rect(ix + iw - 2, iy, 2, 1, M.INK.b)
      c:rect(ix, iy + ih - 1, 2, 1, M.INK.y)
      c:rect(ix + iw - 2, iy + ih - 1, 2, 1, M.INK.g)
    end
    symbol(c, ix, iy, iw, ih, SYMBOLS.F, opts.dim and C.mute or C.text, "F")
  elseif SYMBOLS[kind] then
    symbol(c, ix, iy, iw, ih, SYMBOLS[kind], on, kind)
  end
  -- A played wild shows the colour it was given along its bottom edge
  if opts.color and color == "w" and M.INK[opts.color] then c:rect(x, y + h - 1, w, 1, M.INK[opts.color]) end
  if opts.lit then c:frame(x - 1, y - 1, w + 2, h + 2, C.gold) end
end

--- A card the size of a word, for the list of recent plays: a cream top with what it is, and its colour below.
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

--- The back of a card: dark, with a red middle and UNO across it in gold.
function M.back(c, x, y, w, h)
  c:rect(x, y, w, h, C.card)
  c:rect(x + 1, y + 1, w - 2, h - 2, C.ink)
  if w >= 8 and h >= 5 then
    c:rect(x + 2, y + 2, w - 4, h - 4, C.red)
    local cy = y + math.floor(h / 2)
    c:rect(x + 2, cy - 1, w - 4, 3, C.gold)
    c:textCenter(x + math.floor(w / 2) + 1, cy, "UNO", C.ink, C.gold)
  end
end

--- A tiny back, 2x2, for counting a hand on the wall.
function M.pip(c, x, y)
  c:rect(x, y, 2, 2, C.card)
  c:rect(x, y + 1, 2, 1, C.red)
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
