-- games/craps/table_view.lua
-- The dealer's wall: the six numbers and the puck, the line and the Field, the dice, and who has what on the felt.

local dice = require("games.craps.dice")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local BOX_W, BOX_H, BOX_GAP = 18, 16, 2
local SIDE_W = 28

local function shooterName(view)
  for _, seat in ipairs(view.seats or {}) do
    if seat.seat == view.shooter then return seatui.short(seat.name, 16) end
  end
  return nil
end

local function status(view)
  local name = shooterName(view)
  if view.over then return view.sevenOut and "THE DICE PASS" or "ROUND OVER" end
  if view.rolling then return "NO MORE BETS" end
  if view.stage == "comeout" then return "COME OUT ROLL" .. (name and (". SHOOTER " .. name) or "") end
  if view.stage == "runout" then return "POINT MADE. ROLLING OUT THE COME BETS" end
  return "THE POINT IS " .. tostring(view.point) .. (name and (". SHOOTER " .. name) or "")
end

--- The puck sits on the point.
local function numbers(c, view, x, y, flying, puck)
  for index, spot in ipairs(view.numbers or {}) do
    local bx = x + (index - 1) * (BOX_W + BOX_GAP)
    local lit = puck == spot.n
    local bg = lit and C.gold or C.feltLight
    local fg = lit and C.ink or C.text
    c:panel(bx, y, BOX_W, BOX_H, bg, C.felt)
    c:bigCenter(bx + math.floor(BOX_W / 2), y + 1, tostring(spot.n), fg, 2)
    if lit then c:text(bx + BOX_W - 4, y + 1, "ON", C.ink, C.text) end
    if not flying then
      if spot.come > 0 then c:text(bx + 1, y + BOX_H - 3, "Come " .. ui.group(spot.come), fg, bg) end
      if spot.lay > 0 then c:text(bx + 1, y + BOX_H - 2, "Don't " .. ui.group(spot.lay), fg, bg) end
    end
  end
end

--- A place on the felt with the chips on it.
local function spot(c, x, y, w, h, label, line, amount, flying)
  c:panel(x, y, w, h, C.feltDark, C.felt)
  c:text(x + 2, y + 1, label, C.gold, C.feltDark)
  if line then c:text(x + 2, y + 2, line, C.mute, C.feltDark) end
  if not flying and amount > 0 then c:text(x + 2, y + h - 2, ui.group(amount), C.text, C.feltDark) end
end

--- The last rolls, newest at the right.
local function history(c, view, x, y, w, flying)
  c:text(x, y, "LAST ROLLS", C.gold)
  local list = view.history or {}
  local px = x
  local newest = #list - (flying and 1 or 0)
  for index = math.max(1, newest - 7), newest do
    local total = list[index]
    c:text(px, y + 1, tostring(total), total == 7 and C.red or C.text)
    px = px + 3
    if px > x + w - 3 then break end
  end
end

--- Two dice at rest in the middle, or on their way there.
local function drawDice(c, view, anim, cx, y)
  local gap = 4
  local x = cx - dice.BIG_W - math.floor(gap / 2)
  local second = x + dice.BIG_W + gap
  if anim and anim.ev.type == "roll" then
    local dx, dy = dice.flight(anim, 22, 5)
    dice.draw(c, x - dx, y - dy, dice.tumble(anim, 1), true)
    dice.draw(c, second - dx, y - math.floor(dy / 2), dice.tumble(anim, 2), true)
    return
  end
  local shown = view.dice or {}
  dice.draw(c, x, y, shown[1], true)
  dice.draw(c, second, y, shown[2], true)
end

--- What was called, as big as the room allows.
local function callout(c, text, color, cx, y, room)
  local scale = c:bigWidth(text, 2) <= room and 2 or 1
  if c:bigWidth(text, scale) <= room then
    c:bigCenter(cx, y, text, color, scale)
  else
    c:textCenter(cx, y, text, color)
  end
end

local function seatLine(c, seat, view, x, y, w, flying)
  local shooter = seat.seat == view.shooter
  local bg = shooter and C.gold or C.panel
  local fg = shooter and C.ink or C.text
  c:panel(x, y, w, 5, bg, C.felt)
  c:text(x + 2, y + 1, seatui.short(seat.name, w - 4), fg, bg)
  if not flying then
    c:text(x + 2, y + 2, seat.on > 0 and (ui.group(seat.on) .. " on the felt") or "No bets up", shooter and C.ink or C.mute, bg)
  end
  if shooter then c:text(x + 2, y + 3, "SHOOTER", C.ink, bg) end
end

function M.draw(c, view, anim)
  if not view.stage then return end
  local x, y, w = seatui.tableArea(c)
  local cx = math.floor(c.w / 2) + 1
  local flying = dice.flying(anim)
  -- The roll is decided before it lands, so the old point stays up until it does
  local puck = view.point
  if flying then puck = anim.ev.point end

  c:textCenter(cx, y + 1, flying and "THE DICE ARE OUT" or status(view), C.gold)

  local rowW = 6 * BOX_W + 5 * BOX_GAP
  local boxX = x + math.floor((w - rowW) / 2)
  numbers(c, view, boxX, y + 3, flying, puck)

  local top = y + 3 + BOX_H + 2
  spot(c, 3, top, SIDE_W, 7, "PASS LINE", "7 and 11 win", view.pass, flying)
  spot(c, 3, top + 8, SIDE_W, 7, "DON'T PASS", "Bar 12", view.dont, flying)
  spot(c, 3, top + 16, SIDE_W, 7, "FIELD", "2 pays 2:1, 12 pays 3:1", view.field, flying)
  local right = c.w - SIDE_W - 2
  spot(c, right, top, SIDE_W, 7, "COME", "Moves to its number", view.comeBox, flying)
  spot(c, right, top + 8, SIDE_W, 7, "DON'T COME", "Bar 12", view.dontBox, flying)
  history(c, view, right, top + 16, SIDE_W, flying)

  drawDice(c, view, anim, cx, top + 1)
  local total = not flying and view.total
  if total then
    c:textCenter(cx, top + 14, "Rolled " .. total, C.text)
    if view.call then callout(c, view.call, view.sevenOut and C.red or C.gold, cx, top + 16, 2 * (right - cx) - 4) end
  end

  local seats = view.seats or {}
  local rowY = y + 49
  local tileW = math.floor((c.w - 6) / 4) - 1
  for index, seat in ipairs(seats) do
    local column = (index - 1) % 4
    local row = math.floor((index - 1) / 4)
    seatLine(c, seat, view, 4 + column * (tileW + 1), rowY + row * 6, tileW, flying)
  end
end

return M
