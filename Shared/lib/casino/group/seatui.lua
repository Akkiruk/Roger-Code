-- seatui.lua
-- How a seat's screen is laid out, whatever the wall. A dealer never draws on a seat: it sends a screen, a plain table, and this
-- file turns that into a picture and a list of touch regions. The same code draws a seat on its own computer and a wall of a Duel.
--
-- A screen:
--   n         changes whenever anything but left or countdown changes. A seat only redraws and plays events for a new n
--   kind      "panel", the engine's own (sit, buy-in, bet, a page), or "game", drawn by the game's seatView
--   game, felt, title, number, name, money, owed
--             which game, whose seat, and what the top bar says. name is false on an empty seat. money is the figure in the bar
--   note      a short line above the buttons, in orange if warn is set
--   lines     for a panel: { { text, color, big } }, centred. big is a font scale
--   tiles     for a panel: a grid of big buttons above the action bar
--   buttons   the action bar: { id, value, label, sub, color, textColor, disabled, small }. color names come from theme.C
--   only      only this name's touches count here. The seat says so to anyone else, and the dealer checks again
--   view, events, tap, left, total, hash, result
--             for a game: the seat's view, events to play, whether regions are live, the turn's clock in ms, the fair hash, and
--             the result banner
--   countdown ms until something happens, shown in the note
--   approve   this name still has to click [APPROVE] in chat
--
-- The layout of a 4x4 wall, 78x52 at text scale 0.5. A bigger wall centres the same 78x52. A Duel wall is all 121x81.
--   rows 1-9    the top bar (ui.bar)
--   rows 10-39  the game's: seatView.draw has M.area(c) to itself. On a 6x6 Duel wall that runs to row 68
--   row 40      the turn clock
--   rows 41-51  the buttons
--   row 52      the hash

local canvas = require("lib.casino.canvas")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

M.W, M.H = 78, 52           -- a seat's screen
M.TOP = ui.TOP              -- the first row a game draws on
M.ACTIONS_H = 13            -- the clock, the buttons and the hash along the bottom
M.DEALER_W, M.DEALER_H = 120, 80   -- the least that is a dealer's wall. A 6x6 wall at text scale 0.5 is 121x81
M.STRIP_H = 7               -- the row of seats along the bottom of the dealer's wall
M.RESULT_H = 10             -- a seat's result banner, at the bottom of the game's area

local MAX_BUTTONS = 10
local TILE_GAP = 2
local RESULT_COLOR = { win = "win", lose = "red", loss = "red", push = "gold", tie = "gold" }

--- The part of the screen a game has to itself: x, y, w, h.
function M.area(c)
  return 1, M.TOP, c.w, c.h - M.TOP - M.ACTIONS_H + 1
end

--- The same on the dealer's wall, above the row of seats.
function M.tableArea(c)
  return 1, M.TOP, c.w, c.h - M.TOP - M.STRIP_H - 1
end

--- A name that fits in a small space.
function M.short(name, room)
  name = tostring(name)
  room = room or 12
  if #name <= room then return name end
  return name:sub(1, room - 1) .. "."
end

--- Where a seat's 78x52 goes on a wall: a target for a canvas, and how far in it starts. A wall too small gives nil.
function M.fit(monitor)
  local w, h = monitor.getSize()
  if w < M.W or h < M.H then return nil end
  local ox, oy = math.floor((w - M.W) / 2), math.floor((h - M.H) / 2)
  if ox == 0 and oy == 0 and w == M.W and h == M.H then return monitor, 0, 0 end
  return window.create(monitor, ox + 1, oy + 1, M.W, M.H, true), ox, oy
end

--- A canvas for a seat on this monitor, or nil and the size it should have been. full gives a Duel the whole wall.
function M.canvas(monitor, full)
  if full then return canvas.new(monitor), 0, 0 end
  local target, ox, oy = M.fit(monitor)
  if not target then return nil end
  return canvas.new(target), ox, oy
end

local function colorOf(name, fallback)
  return C[name] or fallback
end

--- A button as a screen describes it, with its colours resolved. The spec on the screen stays as it was sent.
local function spec(button)
  local out = {}
  for key, value in pairs(button) do out[key] = value end
  out.color = colorOf(button.color, C.blue)
  out.textColor = colorOf(button.textColor, C.text)
  out.label = tostring(button.label or button.id or "?")
  return out
end

--- The bottom of the screen: one row of up to five big buttons, or two rows of up to five small ones.
function M.actions(c, list, buttons)
  local specs = {}
  for i = 1, math.min(#buttons, MAX_BUTTONS) do specs[i] = spec(buttons[i]) end
  if #specs == 0 then
    c:rect(1, c.h - ui.ACTIONS_H, c.w, ui.ACTIONS_H + 1, C.feltDark)
  elseif #specs <= 5 then
    ui.actionBar(c, list, specs)
  else
    local top = c.h - 11
    c:rect(1, c.h - ui.ACTIONS_H, c.w, ui.ACTIONS_H + 1, C.feltDark)
    local first, second = {}, {}
    local half = math.ceil(#specs / 2)
    for i, item in ipairs(specs) do
      item.small = true
      if i <= half then first[#first + 1] = item else second[#second + 1] = item end
    end
    ui.actionRow(c, list, first, top, 5)
    ui.actionRow(c, list, second, top + 6, 5)
  end
end

--- The turn's clock, a bar that runs down.
function M.clock(c, left, total)
  if not left or not total or total <= 0 then return end
  local y = c.h - ui.ACTIONS_H
  local share = math.max(0, math.min(1, left / total))
  local w = math.floor((c.w - 2) * share)
  c:rect(2, y, c.w - 2, 1, C.ink)
  if w > 0 then c:rect(2, y, w, 1, share < 0.25 and C.red or C.gold) end
end

--- The top bar, the same on every seat.
local function bar(c, screen)
  local title = tostring(screen.title or "")
  local money = type(screen.money) == "number" and screen.money or nil
  -- A long title on a 78 wide seat would run under the money, so it gives way to plain text
  local room = c.w - (screen.name and c:bigWidth(ui.group(money or 0), 1) + 8 or 6)
  local fits = c:bigWidth(title, 1) <= room
  ui.bar(c, {
    title = fits and title or "",
    seat = screen.name and M.short(screen.name, 16) or nil,
    balance = money,
  })
  if not fits then c:text(4, 4, title, C.gold, C.panel) end
end

--- A grid of tiles from row y down to row bottom.
function M.tiles(c, list, tiles, y, bottom)
  local count = #tiles
  if count == 0 then return end
  local columns = count <= 2 and count or (count <= 6 and 3 or 4)
  if count <= 4 and c.w >= 100 then columns = count end
  local rows = math.ceil(count / columns)
  local x0 = 3
  local w = math.floor((c.w - 2 * (x0 - 1) - TILE_GAP * (columns - 1)) / columns)
  local h = math.floor((bottom - y + 1 - TILE_GAP * (rows - 1)) / rows)
  if h > 14 then h = 14 end
  for i, tile in ipairs(tiles) do
    local item = spec(tile)
    local column = (i - 1) % columns
    local row = math.floor((i - 1) / columns)
    item.x, item.y, item.w, item.h = x0 + column * (w + TILE_GAP), y + row * (h + TILE_GAP), w, h
    ui.button(c, list, item)
  end
end

--- The engine's own screens: centred lines, then tiles.
local function panel(c, screen, list)
  local cx = math.floor(c.w / 2) + 1
  local y = M.TOP + 1
  for _, line in ipairs(screen.lines or {}) do
    local text = tostring(line[1] or "")
    local color = colorOf(line[2], C.text)
    if line[3] then
      local scale = line[3]
      while scale > 1 and c:bigWidth(text, scale) > c.w - 4 do scale = scale - 1 end
      if c:bigWidth(text, scale) <= c.w - 4 then
        c:bigCenter(cx, y, text, color, scale)
        y = y + 6 * scale + 1
      else
        c:textCenter(cx, y, text, color)
        y = y + 2
      end
    elseif text == "" then
      y = y + 1
    else
      for _, part in ipairs(ui.wrap(text, c.w - 6)) do
        c:textCenter(cx, y, part, color)
        y = y + 1
      end
    end
  end
  local _, top, _, h = M.area(c)
  M.tiles(c, list, screen.tiles or {}, y + 1, top + h - 2)
end

--- The result along the bottom of the game's area. A seat's screen is small, so its banner leaves the cards in view.
local function banner(c, result)
  local color = C[RESULT_COLOR[result.kind] or "gold"]
  local title = tostring(result.title or "")
  local _, top, _, h = M.area(c)
  if c.h >= ui.BANNER_Y then
    ui.banner(c, top + h - ui.BANNER_H, title, result.detail, color)
    return
  end
  local y = top + h - M.RESULT_H
  c:rect(1, y, c.w, M.RESULT_H, C.ink)
  c:rect(1, y, c.w, 1, color)
  c:bigCenter(math.floor(c.w / 2) + 1, y + 2, title, color, 1)
  if result.detail then c:textCenter(math.floor(c.w / 2) + 1, y + 8, tostring(result.detail):sub(1, c.w - 2), C.text) end
end

--- Draw a screen. The game's code runs under pcall: a mistake in a view must not take a seat down.
-- @return the touch regions, topmost last
function M.draw(c, screen, plugin, anim, countdown)
  local list = ui.newButtons()
  c:clear(C.felt)
  c:frame(1, 1, c.w, c.h, C.feltDark)
  if screen.kind == "game" and plugin and plugin.seatView then
    local ok, err = pcall(plugin.seatView.draw, c, screen.view, anim, { seat = screen.number, name = screen.name })
    if not ok then
      c:textCenter(math.floor(c.w / 2), M.TOP + 4, "This screen could not be drawn", C.orange)
      c:textCenter(math.floor(c.w / 2), M.TOP + 5, tostring(err):sub(1, c.w - 6), C.mute)
    end
  elseif screen.kind == "game" then
    c:textCenter(math.floor(c.w / 2), M.TOP + 4, "This seat does not have this game yet", C.orange)
  else
    panel(c, screen, list)
  end
  bar(c, screen)

  if screen.result then banner(c, screen.result) end

  M.actions(c, list, screen.buttons or {})
  M.clock(c, screen.left, screen.total)

  local note = screen.note
  if countdown and countdown > 0 and screen.countdownText then
    note = screen.countdownText:format(math.ceil(countdown / 1000))
  end
  if note then
    local _, top, _, h = M.area(c)
    c:textCenter(math.floor(c.w / 2) + 1, top + h - 1, tostring(note):sub(1, c.w - 2), screen.warn and C.orange or C.text, C.ink)
  end
  if screen.hash then ui.hash(c, screen.hash) end

  if screen.tap and plugin and plugin.seatView and plugin.seatView.regions then
    local ok, regions = pcall(plugin.seatView.regions, screen.view)
    if ok and type(regions) == "table" then
      for _, region in ipairs(regions) do list[#list + 1] = region end
    end
  end
  return list
end

--- The small toast in the middle of a seat.
function M.toast(c, text)
  local w = math.min(#text + 4, c.w - 2)
  local x = math.floor((c.w - w) / 2) + 1
  local y = math.floor(c.h / 2)
  c:rect(x, y, w, 3, C.orange)
  c:text(x + 2, y + 1, text:sub(1, w - 4), C.ink, C.orange)
end

--- The row of seats along the bottom of the dealer's wall. seats is a list of { number, name, line, color, acting }.
function M.strip(c, seats)
  local y = c.h - M.STRIP_H
  c:rect(1, y, c.w, M.STRIP_H + 1, C.feltDark)
  local count = math.max(1, #seats)
  local w = math.floor((c.w - 2) / count) - 1
  for i, seat in ipairs(seats) do
    local x = 2 + (i - 1) * (w + 1)
    c:rect(x, y + 1, w, M.STRIP_H - 2, seat.acting and C.gold or C.panel)
    local ink = seat.acting and C.ink or C.text
    local bg = seat.acting and C.gold or C.panel
    c:text(x + 1, y + 2, M.short(seat.name or ("Seat " .. tostring(seat.number)), w - 2), ink, bg)
    c:text(x + 1, y + 3, tostring(seat.line or ""):sub(1, w - 2), seat.acting and C.ink or colorOf(seat.color, C.mute), bg)
  end
end

return M
