-- board.lua
-- Which monitor is which, and the scoreboard: a monitor smaller than the wall that shows a table's leaders to anyone walking
-- past. It is display only. Touches on it never reach a table, because the event loops only take touches from the wall.
-- It is drawn through the canvas, so a board with nothing new sends nothing, and only every few seconds, so a table never
-- notices it. A board pulled out mid-draw just stops: show() says so, and the next peripheral event finds what is left.

local canvas = require("lib.casino.canvas")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

M.ROWS = 8            -- leaders worth keeping for a board
M.REFRESH_MS = 5000   -- how often a table redraws its board at the most
M.STREAK_SHOWN = 2    -- wins running before the board mentions them. A run of losses is nobody else's business

local SCALE = 0.5
local NAME_ROOM = 8   -- the least a leader's name gets

--- Every monitor, measured at the text scale they play at, largest first. A real monitor remembers an earlier program's scale.
function M.monitors()
  local list = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "monitor") then
      local monitor = peripheral.wrap(name)
      monitor.setTextScale(SCALE)
      local w, h = monitor.getSize()
      list[#list + 1] = { name = name, area = w * h }
    end
  end
  table.sort(list, function(a, b)
    if a.area ~= b.area then return a.area > b.area end
    return a.name < b.name
  end)
  return list
end

--- The wall: whatever is largest.
function M.largest()
  local first = M.monitors()[1]
  return first and first.name or nil
end

--- The biggest monitor smaller than the wall, or nil. Another monitor the size of the wall is not a board.
function M.find(wallName)
  local list = M.monitors()
  local wallArea = nil
  for _, entry in ipairs(list) do
    if entry.name == wallName then wallArea = entry.area end
  end
  for _, entry in ipairs(list) do
    if wallArea and entry.area < wallArea then return entry.name end
  end
  return nil
end

--- Get a board ready, or nil if there is none. felt is the table's own, so the board looks like part of it.
function M.attach(wallName, felt)
  local name = M.find(wallName)
  if not name then return nil end
  local monitor = peripheral.wrap(name)
  theme.apply(monitor, felt)
  return { name = name, c = canvas.new(monitor) }
end

local function short(text, limit)
  text = tostring(text)
  if #text <= limit then return text end
  return text:sub(1, math.max(1, limit - 1)) .. "."
end

--- The bottom block, written upwards so it survives on the smallest monitor. Returns the first row it used.
local function footer(c, info)
  local y = c.h
  local playing = info.playing
  if playing then
    for i = math.min(#playing, 2), 1, -1 do
      c:text(2, y, short(playing[i], c.w - 2), C.text)
      y = y - 1
    end
    if #playing == 0 then
      c:text(2, y, "Table free", C.mute)
      y = y - 1
    end
    c:text(2, y, "NOW PLAYING", C.gold)
    y = y - 1
  end
  if info.note then
    c:text(2, y, short(info.note, c.w - 2), C.text)
    y = y - 1
  end
  if info.jackpot then
    c:text(2, y, short("Jackpot " .. ui.group(info.jackpot), c.w - 2), C.win)
    y = y - 1
  end
  return y + 1
end

--- Draw into a canvas. info: title, leaders { {name, net} }, jackpot or nil, playing (a list of names, or nil to leave it off),
-- note or nil, streak (a line for the top) or nil. Nothing here is hidden from anyone at the table.
function M.draw(c, info)
  c:clear(C.felt)
  local cx = math.floor(c.w / 2)
  local top = 2
  if c.h >= 18 and c:bigWidth(info.title, 1) <= c.w - 2 then
    c:bigCenter(cx, 1, info.title, C.gold, 1)
    top = 7
  else
    c:textCenter(cx, 1, short(info.title, c.w), C.gold)
  end
  c:rect(1, top, c.w, 1, C.feltDark)
  if info.streak then c:text(2, top, short(info.streak, c.w - 2), C.gold) end

  local bottom = footer(c, info)
  local rows = bottom - top - 1
  if rows < 1 then return end
  if #info.leaders == 0 then
    c:text(2, top + 1, short("No rounds yet", c.w - 2), C.mute)
    return
  end
  for i, entry in ipairs(info.leaders) do
    if i > rows then break end
    local y = top + i
    local amount = ui.signed(entry.net)
    if c.w - #amount - 3 < NAME_ROOM then amount = "" end -- on a narrow board the name matters more
    if i % 2 == 1 then c:rect(1, y, c.w, 1, C.feltDark) end
    c:text(2, y, short(i .. " " .. entry.name, c.w - #amount - 3), i == 1 and C.gold or C.text)
    c:text(c.w - #amount, y, amount, entry.net >= 0 and C.win or C.red)
  end
end

--- Put it on the monitor. Returns false once the monitor has gone.
function M.show(board, info)
  return (pcall(function()
    M.draw(board.c, info)
    board.c:flush()
  end))
end

return M
