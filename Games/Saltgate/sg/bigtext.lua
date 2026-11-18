-- bigtext.lua
-- A 3x5 pixel font for big words (the title, NABBED, JOB DONE), drawn into the Pine3D pixel buffer, where each pixel is a
-- third of a character's height and half its width.

local M = {}

local GLYPHS = {
  A = "010101111101101", B = "110101110101110", C = "011100100100011", D = "110101101101110",
  E = "111100110100111", F = "111100110100100", G = "011100101101011", H = "101101111101101",
  I = "111010010010111", J = "001001001101010", K = "101101110101101", L = "100100100100111",
  M = "101111111101101", N = "101111111111101", O = "111101101101111", P = "110101110100100",
  Q = "010101101110011", R = "110101110101101", S = "011100010001110", T = "111010010010010",
  U = "101101101101111", V = "101101101101010", W = "101101111111101", X = "101101010101101",
  Y = "101101010010010", Z = "111001010100111",
  ["0"] = "111101101101111", ["1"] = "010110010010111", ["2"] = "110001010100111", ["3"] = "110001010001110",
  ["4"] = "101101111001001", ["5"] = "111100110001110", ["6"] = "011100111101111", ["7"] = "111001010010010",
  ["8"] = "111101111101111", ["9"] = "111101111001110", ["!"] = "010010010000010", ["$"] = "011110010011110",
  ["-"] = "000000111000000", [":"] = "000010000010000", ["."] = "000000000000010", ["'"] = "010010000000000",
  [" "] = "000000000000000",
}

--- Width in pixels of text at a scale.
function M.width(text, scale)
  return (#text * 4 - 1) * scale
end

--- Draw text into rows (rows[y][x] = colour) with its top-left at (x, y), each font pixel scale x scale.
-- shadow, if given, is drawn one pixel down-right first.
function M.draw(rows, text, x, y, scale, colour, shadow)
  local height = #rows
  local width = rows[1] and #rows[1] or 0
  local function plot(px, py, c)
    for dy = 0, scale - 1 do
      local row = rows[py + dy]
      if row then
        for dx = 0, scale - 1 do
          local xx = px + dx
          if xx >= 1 and xx <= width then row[xx] = c end
        end
      end
    end
  end
  local function pass(ox, oy, c)
    local cx = x + ox
    for i = 1, #text do
      local g = GLYPHS[text:sub(i, i):upper()] or GLYPHS[" "]
      for gy = 0, 4 do
        for gx = 0, 2 do
          if g:sub(gy * 3 + gx + 1, gy * 3 + gx + 1) == "1" then
            plot(cx + gx * scale, y + oy + gy * scale, c)
          end
        end
      end
      cx = cx + 4 * scale
    end
  end
  if shadow then
    -- a solid plate behind the word reads better than a drop shadow at these sizes
    local w = M.width(text, scale)
    for py = y - scale, y + 6 * scale - 1 do
      local row = rows[py]
      if row then
        for px = x - scale - 1, x + w + scale do
          if px >= 1 and px <= width then row[px] = shadow end
        end
      end
    end
  end
  pass(0, 0, colour)
  local _ = height
end

return M
