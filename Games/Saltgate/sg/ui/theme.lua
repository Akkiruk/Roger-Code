-- ui/theme.lua
-- How SALTGATE's screens look on a 51x19 terminal: the colours, and the few drawing helpers every screen and HUD widget
-- shares (text at a place, a panel with a title, a bar, a wrapped paragraph, a line of key hints). Pure: it draws on any
-- term-shaped table, so the tests draw on a fake one. The colour numbers are CC's own, so no globals are needed.
--
-- One rule for every hint line: keys are written in capitals and shown yellow, what they do is lower case and grey.

local M = {}

M.C = {
  white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32, pink = 64, gray = 128,
  lightGray = 256, cyan = 512, purple = 1024, blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768,
}
local C = M.C

-- the screen's own palette (see sg/render.lua PALETTE): the panel is dark slate, the highlight the dusk orange
M.PANEL = C.gray
M.INK = C.black

local floor, max, min = math.floor, math.max, math.min

--- Write text at (x, y).
function M.put(t, x, y, text, fg, bg)
  t.setCursorPos(x, y)
  t.setTextColour(fg or C.white)
  t.setBackgroundColour(bg or C.black)
  t.write(text)
end

--- Fill a rectangle with a background colour.
function M.fill(t, x, y, w, h, bg)
  if w <= 0 then return end
  local row = string.rep(" ", w)
  t.setBackgroundColour(bg or C.black)
  for i = 0, h - 1 do
    t.setCursorPos(x, y + i)
    t.write(row)
  end
end

--- Text centred in a width (from column x0, default 1).
function M.centre(t, y, text, fg, bg, w, x0)
  w = w or 51
  local x = (x0 or 1) + max(0, floor((w - #text) / 2))
  M.put(t, x, y, text, fg, bg)
end

--- Cut text to n characters, ending in ".." when it was longer.
function M.fit(text, n)
  text = tostring(text)
  if #text <= n then return text end
  if n <= 2 then return text:sub(1, max(0, n)) end
  return text:sub(1, n - 2) .. ".."
end

--- Word-wrap text to lines of at most width characters.
function M.wrap(text, width)
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if line == "" then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
    while #line > width do
      lines[#lines + 1] = line:sub(1, width)
      line = line:sub(width + 1)
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  if #lines == 0 then lines[1] = "" end
  return lines
end

--- Is this word of a hint a key? (all capitals and digits, or a pair like A/D, or + joins like SHIFT+W)
function M.isKey(word)
  if word == "A/D" or word == "W/S" or word == "</>" then return true end
  return word:match("^[A-Z0-9%+/]+$") ~= nil and word:match("%u") ~= nil
end

--- A line of key hints at row y: "WASD move  ENTER start". Words in capitals are keys (yellow); the rest grey.
-- Stops at the width. Returns the column after the last character.
function M.keyline(t, x, y, w, text, keyFg, wordFg, bg)
  local cx = x
  for word, gap in tostring(text):gmatch("(%S+)(%s*)") do
    if cx + #word - 1 > x + w - 1 then break end
    M.put(t, cx, y, word, M.isKey(word) and (keyFg or C.yellow) or (wordFg or C.lightGray), bg)
    cx = cx + #word + #gap
  end
  return cx
end

--- A bar of width w, filled frac (0..1), as coloured blanks.
function M.bar(t, x, y, w, frac, fg, bg)
  frac = max(0, min(1, frac or 0))
  local on = floor(frac * w + 0.5)
  if frac > 0 and on == 0 then on = 1 end
  if on > 0 then
    t.setBackgroundColour(fg)
    t.setCursorPos(x, y)
    t.write(string.rep(" ", on))
  end
  if w - on > 0 then
    t.setBackgroundColour(bg or C.gray)
    t.setCursorPos(x + on, y)
    t.write(string.rep(" ", w - on))
  end
end

--- A thin line bar (a line through the middle of each cell, so rows of bars do not run together into a block).
function M.thinBar(t, x, y, w, frac, on, off, bg)
  frac = max(0, min(1, frac or 0))
  local n = floor(frac * w + 0.5)
  if frac > 0 and n == 0 then n = 1 end
  t.setBackgroundColour(bg or M.PANEL)
  if n > 0 then
    t.setTextColour(on)
    t.setCursorPos(x, y)
    t.write(string.rep("\140", n))
  end
  if w - n > 0 then
    t.setTextColour(off or C.black)
    t.setCursorPos(x + n, y)
    t.write(string.rep("\140", w - n))
  end
end

--- A panel: a title strip in the highlight colour over a dark body. Returns the inner x, y, w, h.
function M.panel(t, x, y, w, h, title, body, strip)
  body = body or M.PANEL
  M.fill(t, x, y, w, h, body)
  if title then
    M.fill(t, x, y, w, 1, strip or C.orange)
    M.put(t, x + 1, y, M.fit(title, w - 2), C.black, strip or C.orange)
  end
  return x + 1, y + (title and 1 or 0), w - 2, h - (title and 1 or 0)
end

--- "1:05.3" for seconds.
function M.clock(seconds)
  if seconds == nil then return "-:--.-" end
  local tenths = floor(seconds * 10 + 0.5)
  local m = floor(tenths / 600)
  local s = (tenths - m * 600) / 10
  return string.format("%d:%04.1f", m, s)
end

--- "12:30" for a count of seconds in whole minutes.
function M.playtime(seconds)
  local m = floor((seconds or 0) / 60)
  return string.format("%dh %02dm", floor(m / 60), m % 60)
end

return M
