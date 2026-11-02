-- games/backgammon/seatView.lua
-- A player's wall. The walls are back to back, so each shows the board from its own player's side, in their numbering: their checkers
-- are white and run from top right, along the top, down and along the bottom to home at the bottom right, then off into the tray. The
-- other player's checkers are red and their home is top right. A wall with no viewer shows the same picture for the seat it belongs
-- to, with nothing to tap.
--
-- Rows 10 to 53 are the board, so a result banner leaves all of it in view. The rows below it hold the players, the dice and the cube.
-- A point is my own point number; the other player's p is drawn at 25 - p.

local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")

local C = theme.C
local M = {}

local POINT_W, HALF_H, CHECKER_W, CHECKER_H, SHOWN = 8, 20, 6, 4, 5
local LEFT_X, BAR_X, BAR_W = 3, 51, 7
local RIGHT_X = BAR_X + BAR_W
local TRAY_X, TRAY_W = RIGHT_X + 6 * POINT_W + 1, 13
local NUMBER_TOP, TOP_Y, BOTTOM_Y, NUMBER_BOTTOM = 10, 11, 33, 53
local STRIP_Y = 54
local DIE_W, DIE_H, SMALL_W, SMALL_H = 15, 10, 10, 7
local NAME_X, DICE_CX, CUBE_X, CUBE_W, CUBE_H = 3, 61, 88, 13, 9
local BAR, OFF = 25, 0

local CHECKER = { " #### ", "######", "######", " ==== " }  -- the dark edge keeps a pile countable
local PIPS = { { 5 }, { 1, 9 }, { 1, 5, 9 }, { 1, 3, 7, 9 }, { 1, 3, 5, 7, 9 }, { 1, 3, 4, 6, 7, 9 } }

local function isIn(list, value)
  for _, item in ipairs(list or {}) do
    if item == value then return true end
  end
  return false
end

local function findPlayer(view, seat)
  for _, player in ipairs(view.players or {}) do
    if player.seat == seat then return player end
  end
  return nil
end

--- Which player goes where: this wall's player below and in white, the other above and in red.
local function sides(view, info)
  local players = view.players or {}
  local me = view.me or (info and info.seat)
  if players[2] and players[2].seat == me then return players[1], players[2] end
  return players[2], players[1]
end

--- Where a point sits: its left column and whether it is on the top half.
local function place(point)
  if point <= 6 then return RIGHT_X + (6 - point) * POINT_W, false end
  if point <= 12 then return LEFT_X + (12 - point) * POINT_W, false end
  if point <= 18 then return LEFT_X + (point - 13) * POINT_W, true end
  return RIGHT_X + (point - 19) * POINT_W, true
end

local function triangle(c, x, top, color)
  for row = 0, HALF_H - 1 do
    local width = math.max(2, math.floor((HALF_H - row) * POINT_W / HALF_H / 2 + 0.5) * 2)
    local y = top and TOP_Y + row or BOTTOM_Y + HALF_H - 1 - row
    c:rect(x + math.floor((POINT_W - width) / 2), y, width, 1, color)
  end
end

local function checkerAt(c, x, y, color)
  c:sprite(x, y, CHECKER, { ["#"] = color, ["="] = C.feltDark })
end

--- A pile on a point or the bar. The last checker shown says how many there are when not all of them fit.
local function pile(c, x, top, count, color, ink, lift)
  local shown = math.min(count, SHOWN)
  for index = 1, shown do
    local y = top and TOP_Y + (index - 1) * CHECKER_H or BOTTOM_Y + HALF_H - index * CHECKER_H
    checkerAt(c, x, y, (lift and index == shown) and C.gold or color)
    if index == shown and count > SHOWN then
      c:textCenter(x + 3, y + 1, tostring(count), (lift and C.ink) or ink, (lift and C.gold) or color)
    end
  end
end

--- The whole board. marks says which of my points to light up: { [point] = colour }.
local function board(c, below, above, marks, selected, sources)
  c:rect(1, NUMBER_TOP, TRAY_X + TRAY_W, NUMBER_BOTTOM - NUMBER_TOP + 1, C.feltDark)
  c:rect(LEFT_X, TOP_Y, 6 * POINT_W, BOTTOM_Y + HALF_H - TOP_Y, C.felt)
  c:rect(RIGHT_X, TOP_Y, 6 * POINT_W, BOTTOM_Y + HALF_H - TOP_Y, C.felt)
  for point = 1, 24 do
    local x, top = place(point)
    triangle(c, x, top, marks[point] or (point % 2 == 1 and C.feltLight or C.line))
    local live = isIn(sources, point)
    c:textCenter(x + 4, top and NUMBER_TOP or NUMBER_BOTTOM, tostring(point), live and C.gold or C.mute, C.feltDark)
  end
  if not below or not above then return end
  for point = 1, 24 do
    local x, top = place(point)
    local mine, theirs = below.points[point], above.points[25 - point]
    if mine > 0 then
      pile(c, x + 1, top, mine, C.card, C.ink, selected == point)
    elseif theirs > 0 then
      pile(c, x + 1, top, theirs, C.red, C.text, false)
    end
  end
end

local function barColumn(c, below, above, selected, sources)
  c:rect(BAR_X, NUMBER_TOP, BAR_W, NUMBER_BOTTOM - NUMBER_TOP + 1, C.panel)
  c:textCenter(BAR_X + 3, TOP_Y + HALF_H, "BAR", C.mute, C.panel)
  if above and above.bar > 0 then pile(c, BAR_X, true, above.bar, C.red, C.text, false) end
  if below and below.bar > 0 then pile(c, BAR_X, false, below.bar, C.card, C.ink, selected == BAR) end
  if isIn(sources, BAR) then c:textCenter(BAR_X + 3, NUMBER_BOTTOM, "TAP", C.gold, C.panel) end
end

--- The tray at the right, a thin bar for each checker borne off. Mine is the bottom half, and it lights up when I can bear off.
local function trays(c, below, above, canBearOff)
  local x, w = TRAY_X, TRAY_W
  c:rect(x, TOP_Y, w, HALF_H, C.panel)
  c:rect(x, BOTTOM_Y, w, HALF_H, canBearOff and C.win or C.panel)
  if above then
    for index = 1, above.off do c:rect(x + 2, TOP_Y + index - 1, w - 4, 1, C.red) end
    c:textCenter(x + 6, TOP_Y + HALF_H - 2, "OFF " .. above.off, C.mute, C.panel)
  end
  if below then
    for index = 1, below.off do c:rect(x + 2, BOTTOM_Y + HALF_H - index, w - 4, 1, C.card) end
    if canBearOff then
      c:textCenter(x + 7, BOTTOM_Y + 1, "BEAR OFF", C.ink, C.win)
      c:textCenter(x + 7, BOTTOM_Y + 2, "TAP HERE", C.ink, C.win)
    else
      c:textCenter(x + 6, BOTTOM_Y + 1, "OFF " .. below.off, C.mute, C.panel)
    end
  end
end

local function die(c, x, y, big, face, bg, pip)
  local w, h = big and DIE_W or SMALL_W, big and DIE_H or SMALL_H
  c:rect(x, y, w, h, bg)
  for _, spot in ipairs(PIPS[face] or {}) do
    local column, row = (spot - 1) % 3, math.floor((spot - 1) / 3)
    if big then
      c:rect(x + 2 + column * 4, y + 1 + row * 3, 3, 2, pip)
    else
      c:rect(x + 1 + column * 3, y + 1 + row * 2, 2, 1, pip)
    end
  end
end

--- A face that changes as the dice tumble, then lands. Worked out from the time alone, so a view stays pure.
local function tumbling(face, anim, index)
  if not anim or (anim.t or 1) >= 0.75 then return face end
  return (math.floor((anim.t or 0) * 20) * (index + 4) + index) % 6 + 1
end

local function diceRow(c, dice, left, anim, y)
  local count, big = #dice, #dice <= 2
  local step = (big and DIE_W or SMALL_W) + 2
  local x = DICE_CX - math.floor((count * step - 2) / 2)
  local unused = {}
  for _, face in ipairs(left) do unused[face] = (unused[face] or 0) + 1 end
  for index = count, 1, -1 do
    local face = dice[index]
    local live = (unused[face] or 0) > 0
    if live then unused[face] = unused[face] - 1 end
    local at = x + (index - 1) * step
    if live then
      die(c, at, y, big, tumbling(face, anim, index), C.card, C.ink)
    else
      die(c, at, y, big, face, C.panel2, C.mute)
    end
  end
end

--- A move as players write it, such as 13/7*, bar/20 or 3/off.
local function written(move)
  local from = move.from == BAR and "bar" or tostring(move.from)
  local to = move.to == OFF and "off" or tostring(move.to)
  return from .. "/" .. to .. (move.hit and "*" or "")
end

local function moveList(moves)
  local parts = {}
  for index, move in ipairs(moves or {}) do parts[index] = written(move) end
  return table.concat(parts, " ")
end

--- What just happened, for the row under the players.
local function lastLine(view)
  local last = view.last
  if last then
    local who = seatui.short((findPlayer(view, last.seat) or {}).name or "?", 10)
    local dice = (last.dice[1] or "?") .. "-" .. (last.dice[#last.dice] or "?")
    if #last.played == 0 then return who .. " " .. dice .. ": no move" end
    return who .. " " .. dice .. ": " .. moveList(last.played)
  end
  local first, second = view.opening and view.opening[1], view.opening and view.opening[2]
  if first and second then
    return "Opening " .. seatui.short((findPlayer(view, first.seat) or {}).name or "?", 8) .. " " .. first.die .. ", " ..
      seatui.short((findPlayer(view, second.seat) or {}).name or "?", 8) .. " " .. second.die
  end
  return ""
end

local function playerRow(c, view, player, y, color, you)
  if not player then return end
  local acting = view.phase ~= "over" and ((view.phase == "double" and view.offer and view.offer.seat ~= player.seat) or (view.phase ~= "double" and view.turn == player.seat))
  checkerAt(c, NAME_X, y, color)
  local name = you and "YOU" or seatui.short(player.name, 16)
  c:text(NAME_X + 8, y, name, acting and C.gold or C.text)
  c:text(NAME_X + 8, y + 2, "Pips " .. tostring(player.pips or 0) .. "  Off " .. tostring(player.off or 0), C.mute)
end

--- One line on what is going on, and what to tap.
local function status(view, above, below)
  local mine = view.me ~= nil
  local name = function(player) return seatui.short(player and player.name or "?", 14) end
  local mover = findPlayer(view, view.turn)
  if view.phase == "double" and view.offer then
    local doubler = findPlayer(view, view.offer.seat)
    if mine and view.offer.seat ~= view.me then return name(doubler) .. " doubles. TAKE or DROP?", C.gold end
    return "Waiting on " .. name(doubler == above and below or above) .. " to take or drop", C.text
  end
  if view.phase == "roll" then
    if mine and view.turn == view.me then return "Your roll", C.gold end
    return name(mover) .. " to roll", C.text
  end
  if view.phase == "move" then
    if not (mine and view.turn == view.me) then return name(mover) .. " to move", C.text end
    if view.draft then return "Tap a green point. Tap again to put it back", C.gold end
    return "Tap a checker to move", C.gold
  end
  return "", C.text
end

--- The cube and what the game is worth.
local function cube(c, view, anim)
  local x, y = CUBE_X, STRIP_Y + 1
  local flash = anim and anim.ev and (anim.ev.type == "double" or anim.ev.type == "take")
  local value = view.offer and view.offer.cube or view.cube or 1
  c:rect(x, y, CUBE_W, CUBE_H, flash and C.gold or C.card)
  c:bigCenter(x + 7, y + 2, tostring(value), C.ink, 1)
  local where = "In the middle"
  if view.offer then
    where = "Offered"
  elseif view.holder then
    local holder = findPlayer(view, view.holder)
    where = (view.me and view.holder == view.me) and "Yours" or (seatui.short(holder and holder.name or "?", 10) .. " holds it")
  end
  local tx = x + CUBE_W + 2
  c:text(tx, y, "CUBE", C.gold)
  c:text(tx, y + 2, where, C.text)
  c:text(tx, y + 4, "Stake " .. tostring(view.stake or 0), C.mute)
  c:text(tx, y + 6, "Worth " .. tostring((view.stake or 0) * value), C.text)
  c:text(tx, y + 8, "Cap " .. tostring(view.cap or 0), C.mute)
end

local function strip(c, view, anim, above, below)
  playerRow(c, view, above, STRIP_Y + 1, C.red, false)
  playerRow(c, view, below, STRIP_Y + 6, C.card, view.me ~= nil)
  c:text(NAME_X, STRIP_Y + 12, lastLine(view), C.mute)
  local rolling = anim and anim.ev and (anim.ev.type == "roll" or anim.ev.type == "opening") and anim or nil
  local shownDice = view.dice or (view.last and view.last.dice)
  if view.offer then
    c:bigCenter(DICE_CX, STRIP_Y, "DOUBLE", C.gold, 1)
    c:bigCenter(DICE_CX, STRIP_Y + 6, "TO " .. view.offer.cube, C.gold, 1)
  elseif shownDice then
    diceRow(c, shownDice, view.dice and view.left or {}, rolling, STRIP_Y + 1)
  end
  local text, color = status(view, above, below)
  c:textCenter(DICE_CX, STRIP_Y + 12, text, color)
  cube(c, view, anim)
end

--- Point lit by what just moved, on this wall's numbering.
local function moved(anim, below)
  if not anim or not anim.ev or anim.ev.type ~= "move" or not below then return nil end
  local ev = anim.ev
  if ev.to == OFF then return nil end
  return ev.seat == below.seat and ev.to or 25 - ev.to
end

function M.draw(c, view, anim, info)
  local above, below = sides(view, info)
  local marks, canBearOff = {}, false
  for _, point in ipairs(view.targets or {}) do
    if point == OFF then canBearOff = true else marks[point] = C.win end
  end
  local flash = moved(anim, below)
  if flash then marks[flash] = anim.ev.hit and C.orange or C.gold end
  local selected = view.draft and view.draft.from or nil
  local sources = view.sources
  board(c, below, above, marks, selected, sources)
  barColumn(c, below, above, selected, sources)
  trays(c, below, above, canBearOff)
  strip(c, view, anim, above, below)
end

--- The tappable parts: the checkers that can move, or with one selected its green points and itself to put it back. Only what is
-- lit up can be hit, so a stray tap beside a green point does nothing.
function M.regions(view)
  local list = {}
  if not view.me then return list end
  local function spot(point, id)
    if point == BAR then
      list[#list + 1] = { id = id, value = point, x = BAR_X, y = BOTTOM_Y, w = BAR_W, h = HALF_H + 1 }
    elseif point == OFF then
      list[#list + 1] = { id = id, value = point, x = TRAY_X, y = BOTTOM_Y, w = TRAY_W, h = HALF_H + 1 }
    else
      local x, top = place(point)
      list[#list + 1] = { id = id, value = point, x = x, y = top and NUMBER_TOP or BOTTOM_Y, w = POINT_W, h = HALF_H + 1 }
    end
  end
  if view.draft then
    for _, point in ipairs(view.targets or {}) do spot(point, "to") end
    spot(view.draft.from, "from")
    return list
  end
  for _, point in ipairs(view.sources or {}) do spot(point, "from") end
  return list
end

return M
