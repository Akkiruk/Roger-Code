-- games/cookie/art.lua
-- The pictures: the big cookie, the golden cookie, and a little icon for every building. A wall cell is about twice as
-- tall as it is wide, so a round cookie is drawn half again as wide as it is tall.

local ui = require("lib.arcade.ui")

local M = {}
local C = ui.C
local floor, max = math.floor, math.max

-- Chocolate chips on the cookie, as shares of its half-width and half-height from the centre.
local CHIPS = {
  { -0.55, -0.45 }, { 0.05, -0.62 }, { 0.5, -0.35 }, { -0.2, -0.1 }, { 0.3, 0.12 }, { -0.62, 0.2 },
  { 0.68, 0.3 }, { -0.25, 0.55 }, { 0.2, 0.6 }, { 0.0, 0.25 },
}

--- The big cookie, w by h cells at x, y. pressed draws it squashed in a little, as if pushed. glow rings it in gold.
function M.cookie(x, y, w, h, pressed, glow)
  if pressed then x, y, w, h = x + 2, y + 1, w - 4, h - 2 end
  if glow then ui.ellipse(x - 2, y - 1, w + 4, h + 2, C.hi) end
  ui.ellipse(x, y + 1, w, h, C.redTint)               -- the shadow under it
  ui.ellipse(x, y, w, h, C.hiTint)                    -- the baked rim
  ui.ellipse(x + 1, y, w - 2, h - 1, C.warn)          -- the dough
  if not pressed then
    ui.ellipse(x + floor(w * 0.18), y + floor(h * 0.1), floor(w * 0.34), max(2, floor(h * 0.18)), C.hi) -- a shine
    ui.ellipse(x + floor(w * 0.22), y + floor(h * 0.12), floor(w * 0.22), max(1, floor(h * 0.1)), C.warn)
  end
  local cx, cy = x + w / 2, y + h / 2
  local chipW, chipH = max(2, floor(w / 14)), max(1, floor(h / 12))
  for _, c in ipairs(CHIPS) do
    local px = floor(cx + c[1] * w / 2 - chipW / 2)
    local py = floor(cy + c[2] * h / 2 - chipH / 2)
    ui.fill(px, py, chipW, chipH, C.redTint)
    ui.fill(px + 1, py, max(1, chipW - 2), 1, C.hiTint)
  end
end

--- A golden cookie, w by h, with a sparkle that moves with phase.
function M.golden(x, y, w, h, phase, fading)
  if not fading or phase % 2 == 0 then ui.ellipse(x - 1, y - 1, w + 2, h + 2, C.text) end
  ui.ellipse(x, y, w, h, C.hi)
  ui.ellipse(x + 2, y + 1, w - 5, h - 3, C.warn)
  ui.ellipse(x + 3, y + 1, w - 7, h - 4, C.hi)
  local sx = x + 1 + (phase % 4)
  ui.fill(sx, y + 1, 1, 1, C.text)
  ui.fill(x + w - 3, y + h - 2, 1, 1, C.text)
end

-- Digits 4 wide and 5 tall, for counts in a store row too short for the big font.
local DIGITS = {
  ["0"] = { ".##.", "#..#", "#..#", "#..#", ".##." }, ["1"] = { "..#.", ".##.", "..#.", "..#.", ".###" },
  ["2"] = { ".##.", "#..#", "..#.", ".#..", "####" }, ["3"] = { "###.", "...#", ".##.", "...#", "###." },
  ["4"] = { "#..#", "#..#", "####", "...#", "...#" }, ["5"] = { "####", "#...", "###.", "...#", "###." },
  ["6"] = { ".##.", "#...", "###.", "#..#", ".##." }, ["7"] = { "####", "...#", "..#.", ".#..", ".#.." },
  ["8"] = { ".##.", "#..#", ".##.", "#..#", ".##." }, ["9"] = { ".##.", "#..#", ".###", "...#", ".##." },
}
M.DIGIT_W = 5 -- with the gap

function M.digitsWidth(text) return #text * M.DIGIT_W - 1 end

--- A number in the small digits, its right edge at right.
function M.digits(text, right, y, color)
  local x = right - M.digitsWidth(text) + 1
  for i = 1, #text do
    local glyph = DIGITS[text:sub(i, i)]
    if glyph then
      for r, row in ipairs(glyph) do
        local c = 1
        while c <= 4 do
          if row:sub(c, c) == "#" then
            local e = c
            while row:sub(e + 1, e + 1) == "#" do e = e + 1 end
            ui.fill(x + c - 1, y + r - 1, e - c + 1, 1, color)
            c = e + 1
          else
            c = c + 1
          end
        end
      end
    end
    x = x + M.DIGIT_W
  end
end

-- Icons, 7 wide and 5 tall. A letter is a colour slot, a dot is the row's background.
local INK = {
  w = "text", g = "line", d = "panel", r = "red", b = "blue", o = "warn", y = "hi", k = "ok", l = "soft",
  c = "info", p = "accent", m = "redTint", n = "hiTint", s = "tie", u = "blueTint",
}

local ICONS = {
  cursor = { "w......", "ww.....", "www....", "wwww...", "w.ww..." },
  grandma = { ".ggggg.", "gwwwwwg", ".bwwbw.", ".wwmww.", "..ppp.." },
  farm = { "...r...", "..rrr..", "..rwr..", "kkkkkkk", "lklklkl" },
  mine = { "...g...", "..ggg..", ".gyggy.", "ggggggg", "mmmmmmm" },
  factory = { "g..g...", "g..g...", "ggggggg", "gygygyg", "ggggggg" },
  bank = { "..yyy..", ".yyyyy.", ".w.w.w.", ".w.w.w.", "yyyyyyy" },
  temple = { "...y...", "..ooo..", ".ooooo.", ".o.o.o.", "ooooooo" },
  wizard = { "...p...", "..ppp..", "..pyp..", ".ppppp.", "..ggg.." },
  shipment = { "...w...", "..wbw..", "..www..", ".wwwww.", "..o.o.." },
  alchemy = { "..ggg..", "...g...", "..kkk..", ".kklkk.", ".kkkkk." },
  portal = { ".ppppp.", "pp...pp", "p..c..p", "pp...pp", ".ppppp." },
  timemachine = { ".yyyyy.", "ywwgwwy", "ywwgggy", "ywwwwwy", ".yyyyy." },
  antimatter = { "c.....c", ".c.p.c.", "..ppp..", ".c.p.c.", "c.....c" },
  prism = { "...w...", "..www.r", ".wwwwoo", "wwwwwyy", "wwwwwkb" },
  chancemaker = { ".kk.kk.", "kkkkkkk", ".kkkkk.", "..kkk..", "...k..." },
}
M.ICON_W, M.ICON_H = 7, 5

--- A building's icon at x, y. dark draws it as a silhouette, for one not yet discovered.
function M.icon(id, x, y, dark)
  local rows = ICONS[id]
  if not rows then return end
  for r, row in ipairs(rows) do
    -- runs of one colour go in one fill
    local from, ink = 1, row:sub(1, 1)
    for i = 2, #row + 1 do
      local here = row:sub(i, i)
      if here ~= ink then
        if ink ~= "." then ui.fill(x + from - 1, y + r - 1, i - from, 1, dark and C.bg or C[INK[ink]]) end
        from, ink = i, here
      end
    end
  end
end

return M
