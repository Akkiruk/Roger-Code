-- saltgate_d_term.lua
-- A made-up 51x19 terminal and keyboard for the story's screen tests (not a test itself). The term keeps a grid of
-- characters, text colours and background colours; the input answers pressedAction for the actions the test queues.

local T = {}

local COLOURS = { white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32, pink = 64, gray = 128,
  lightGray = 256, cyan = 512, purple = 1024, blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768 }
local NAMES = {}
for n, v in pairs(COLOURS) do NAMES[v] = n end
T.COLOURS = COLOURS

function T.term(w, h)
  w, h = w or 51, h or 19
  local t = { w = w, h = h, cx = 1, cy = 1, fg = 1, bg = 32768, writes = 0, overflow = 0 }
  t.ch, t.fgs, t.bgs = {}, {}, {}
  for y = 1, h do
    t.ch[y], t.fgs[y], t.bgs[y] = {}, {}, {}
    for x = 1, w do t.ch[y][x], t.fgs[y][x], t.bgs[y][x] = " ", 1, 32768 end
  end
  function t.getSize() return w, h end
  function t.setCursorPos(x, y) t.cx, t.cy = x, y end
  function t.setTextColour(c) t.fg = c end
  function t.setBackgroundColour(c) t.bg = c end
  t.setTextColor, t.setBackgroundColor = t.setTextColour, t.setBackgroundColour
  function t.clear()
    for y = 1, h do
      for x = 1, w do t.ch[y][x], t.fgs[y][x], t.bgs[y][x] = " ", t.fg, t.bg end
    end
  end
  function t.write(s)
    s = tostring(s)
    t.writes = t.writes + 1
    for i = 1, #s do
      local x = t.cx + i - 1
      if t.cy >= 1 and t.cy <= h then
        if x >= 1 and x <= w then
          t.ch[t.cy][x], t.fgs[t.cy][x], t.bgs[t.cy][x] = s:sub(i, i), t.fg, t.bg
        elseif x > w then
          t.overflow = t.overflow + 1
        end
      end
    end
    t.cx = t.cx + #s
  end
  function t.row(y) return table.concat(t.ch[y]) end
  function t.text()
    local rows = {}
    for y = 1, h do rows[y] = t.row(y) end
    return table.concat(rows, "\n")
  end
  function t.has(s)
    for y = 1, h do
      if t.row(y):find(s, 1, true) then return y end
    end
    return nil
  end
  function t.fgAt(x, y) return NAMES[t.fgs[y][x]] end
  function t.bgAt(x, y) return NAMES[t.bgs[y][x]] end
  return t
end

--- A keyboard: press("advance") makes the next frame's pressedAction("advance") true, once.
function T.input()
  local inp = { queued = {}, map = {}, keys = {} }
  function inp:pressedAction(name)
    if self.queued[name] then
      self.queued[name] = nil
      return true
    end
    return false
  end
  function inp:press(name) self.queued[name] = true end
  return inp
end

return T
