-- story/text.lua
-- Fitting words to the 51-column screen: word wrap and the limits every line of the story is tested against. Pure.

local M = {}

M.SCREEN = 51
M.TEXT = 47 -- a dialogue box's inner width (screen minus a margin and a frame each side)
M.ROWS = 4 -- rows of talk in the box
M.OPTION = 42 -- a choice's longest text (after "1. ")
M.OBJECTIVE = 49 -- the HUD's objective line
M.TITLE = 36 -- a mission title

--- Wrap text to width columns on spaces. A word longer than the width is cut. Returns a list of lines.
function M.wrap(text, width)
  width = width or M.TEXT
  local lines = {}
  local line = ""
  for word in tostring(text):gmatch("%S+") do
    while #word > width do
      if line ~= "" then lines[#lines + 1] = line line = "" end
      lines[#lines + 1] = word:sub(1, width)
      word = word:sub(width + 1)
    end
    if line == "" then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" or #lines == 0 then lines[#lines + 1] = line end
  return lines
end

--- Does text fit in rows lines of width columns, with no word cut?
function M.fits(text, width, rows)
  width = width or M.TEXT
  rows = rows or M.ROWS
  for word in tostring(text):gmatch("%S+") do
    if #word > width then return false end
  end
  return #M.wrap(text, width) <= rows
end

--- Cut text to n columns, ending in ".." when it was longer.
function M.clip(text, n)
  text = tostring(text)
  if #text <= n then return text end
  return text:sub(1, math.max(0, n - 2)) .. ".."
end

--- Pad or cut to exactly n columns.
function M.pad(text, n)
  text = tostring(text)
  if #text >= n then return text:sub(1, n) end
  return text .. string.rep(" ", n - #text)
end

--- Centre text in n columns.
function M.centre(text, n)
  text = M.clip(text, n)
  local left = math.floor((n - #text) / 2)
  return string.rep(" ", left) .. text .. string.rep(" ", n - #text - left)
end

return M
