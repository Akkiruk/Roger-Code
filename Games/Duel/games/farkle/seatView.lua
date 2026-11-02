-- games/farkle/seatView.lua
-- Both walls show the same game, because every die is public: the race to 5,000 along the top, whose throw it is and the running
-- total, the dice big across the middle, and what is set aside below them. The thrower's wall has the buttons and takes taps on the
-- dice. A view with no me is a wall with no viewer, and it draws just the same.

local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local RACE_Y, RACE_H, RACE_ROW = 10, 15, 7
local STATUS_Y, STATUS_H = 25, 8
local DICE_Y, DIE_W, DIE_H, DIE_GAP = 34, 18, 12, 2
local ASIDE_Y, SMALL_W, SMALL_H, SMALL_GAP = 47, 10, 7, 2
local TABLE_Y = 56           -- the scoring reminder, under where a result banner starts
local BAR_X, BAR_W = 24, 66  -- where the race bars run, past the names
local WALL_W = 121           -- regions get no canvas, and a Duel wall is always this wide

-- Where the pips of a face sit on a 3x3 grid, numbered from the top left
local PIPS = { { 5 }, { 1, 9 }, { 1, 5, 9 }, { 1, 3, 7, 9 }, { 1, 3, 5, 7, 9 }, { 1, 3, 4, 6, 7, 9 } }

local function die(c, x, y, face, bg, pip)
  c:rect(x, y, DIE_W, DIE_H, bg)
  for _, spot in ipairs(PIPS[face]) do
    local column, row = (spot - 1) % 3, math.floor((spot - 1) / 3)
    c:rect(x + 2 + column * 5, y + 1 + row * 4, 4, 2, pip)
  end
end

local function smallDie(c, x, y, face, bg, pip)
  c:rect(x, y, SMALL_W, SMALL_H, bg)
  for _, spot in ipairs(PIPS[face]) do
    local column, row = (spot - 1) % 3, math.floor((spot - 1) / 3)
    c:rect(x + 1 + column * 3, y + 1 + row * 2, 2, 1, pip)
  end
end

local function findPlayer(view, seat)
  for _, player in ipairs(view.players or {}) do
    if player.seat == seat then return player end
  end
  return nil
end

local function nameOf(view, seat, room)
  local player = findPlayer(view, seat)
  return seatui.short(player and player.name or "?", room or 12)
end

--- The left edge of a die in a row of count, centred on the wall. Both the picture and the touches use this.
local function dieX(x, w, count, index)
  local width = count * DIE_W + (count - 1) * DIE_GAP
  return x + math.floor((w - width) / 2) + (index - 1) * (DIE_W + DIE_GAP)
end

--- One player's row of the race: name, a bar to the target, the score. The thrower's bar shows what the turn would add.
local function racer(c, view, player, thrower, running, x, y, w)
  local acting = (view.phase ~= "over" or view.rolling) and thrower == player.seat
  local target = view.target or 5000
  c:text(x + 3, y + 1, seatui.short(player.name, BAR_X - 5), acting and C.gold or C.text, C.feltDark)
  local status = player.opened and "on the board" or ("needs " .. tostring(view.opening or 500))
  if view.closing and view.closing.leader == player.seat then status = "reached it first" end
  c:text(x + 3, y + 3, seatui.short(status, BAR_X - 5), C.mute, C.feltDark)
  local barX = x + BAR_X - 1
  c:rect(barX, y + 1, BAR_W, 4, C.ink)
  local fill = math.floor(BAR_W * math.min(1, player.score / target))
  local ahead = acting and math.floor(BAR_W * math.min(1, (player.score + running) / target)) or 0
  if ahead > fill then c:rect(barX, y + 1, ahead, 4, C.gold) end
  if fill > 0 then c:rect(barX, y + 1, fill, 4, C.win) end
  c:rect(barX + BAR_W, y, 1, 6, C.text)
  local text = ui.group(player.score)
  c:big(x + w - 3 - c:bigWidth(text, 1), y, text, acting and C.gold or C.text, 1)
end

local function race(c, view, thrower, running, x, w)
  c:rect(x + 1, RACE_Y, w - 2, RACE_H, C.feltDark)
  for index, player in ipairs(view.players or {}) do
    racer(c, view, player, thrower, running, x, RACE_Y + 1 + (index - 1) * RACE_ROW, w)
  end
end

--- Big text if it fits this wide, or the plain font, on a band across the wall.
local function headline(c, text, color, x, w, fg)
  c:rect(x + 1, STATUS_Y, w - 2, STATUS_H, color)
  local cx = x + math.floor(w / 2)
  if c:bigWidth(text, 1) <= w - 6 then
    c:bigCenter(cx, STATUS_Y + 1, text, fg, 1)
  else
    c:textCenter(cx, STATUS_Y + 3, text, fg, color)
  end
end

--- The turn in words, and the running total on the right.
local function status(c, view, thrower, running, x, w)
  local name = nameOf(view, thrower, 12):upper()
  local live = view.phase == "pick" or view.rolling
  local last = view.last
  local text, color = thrower == view.me and "YOUR THROW" or (name .. "'S THROW"), C.text
  if live and view.closing then
    text, color = thrower == view.me and "YOUR LAST TURN" or (name .. "'S LAST TURN"), C.orange
  elseif not live and last then
    local who = nameOf(view, last.seat, 12):upper()
    text = who .. " BANKED " .. ui.group(last.points)
    if last.kind == "farkle" then
      text, color = who .. " FARKLED", C.orange
      if last.points > 0 then text = text .. " -" .. ui.group(last.points) end
    end
  end
  if c:bigWidth(text, 1) <= w - (live and 40 or 6) then
    c:big(x + 3, STATUS_Y + 1, text, color, 1)
  else
    c:text(x + 3, STATUS_Y + 3, text, color)
  end
  if live then
    local total = ui.group(running)
    local right = x + w - 3 - c:bigWidth(total, 1)
    c:big(right, STATUS_Y + 1, total, C.gold, 1)
    c:text(right - 6, STATUS_Y + 3, "TURN", C.mute)
  end
end

--- What the last turn has to beat, on one row under the status, for as long as it lasts.
local function closing(c, view, x, w)
  local turn = view.closing
  if not turn or view.over then return end
  local leader, chaser = findPlayer(view, turn.leader), findPlayer(view, turn.chaser)
  if not leader or not chaser then return end
  c:rect(x + 1, STATUS_Y + 7, w - 2, 1, C.orange)
  local need = leader.score - chaser.score + 1
  c:textCenter(x + math.floor(w / 2), STATUS_Y + 7, seatui.short(chaser.name, 14) .. " must beat " .. ui.group(leader.score) .. ": needs " .. ui.group(need), C.ink, C.orange)
end

--- A face for a die still tumbling. It comes from the clock of the animation and nothing else, so it cannot say what is coming.
local function tumble(t, index)
  return (math.floor(t * 16) * 5 + index * 3) % 6 + 1
end

--- The row of dice. While a throw plays, each die stops in turn from the left.
local function dice(c, view, anim, x, w)
  local rolling = anim and anim.ev and anim.ev.type == "roll"
  local list = view.dice or {}
  local count = rolling and (anim.ev.count or #list) or #list
  local t = rolling and (anim.t or 1) or 1
  for index = 1, count do
    local at = dieX(x, w, count, index)
    local stopped = not rolling or t >= 0.4 + 0.09 * index
    if not stopped then
      local bounce = math.floor(t * 16 + index) % 2
      die(c, at, DICE_Y - 1 + bounce * 2, tumble(t, index), C.card, C.ink)
    elseif list[index] then
      local chosen = view.marks and view.marks[index]
      if chosen then
        c:rect(at - 1, DICE_Y - 1, DIE_W + 2, DIE_H + 2, view.dead and C.red or C.text)
        die(c, at, DICE_Y, list[index], C.gold, C.ink)
      elseif view.phase == "pick" and view.scoring and not view.scoring[index] then
        die(c, at, DICE_Y, list[index], C.line, C.ink)
      elseif view.last and view.last.kind == "farkle" and view.phase ~= "pick" then
        die(c, at, DICE_Y, list[index], C.red, C.ink)
      else
        die(c, at, DICE_Y, list[index], C.card, C.ink)
      end
    end
  end
end

--- What is set aside this turn, and what the marks are worth.
local function aside(c, view, x, w)
  local list = view.aside or {}
  if #list > 0 then
    c:text(x + 3, ASIDE_Y + 1, "SET", C.mute)
    c:text(x + 3, ASIDE_Y + 2, "ASIDE", C.mute)
    for index, face in ipairs(list) do
      smallDie(c, x + 9 + (index - 1) * (SMALL_W + SMALL_GAP), ASIDE_Y, face, C.panel2, C.text)
    end
  end
  if view.phase ~= "pick" then return end
  local right = x + w - 3
  if view.dead then
    local text = "A DIE THERE DOES NOT SCORE"
    c:text(right - #text, ASIDE_Y + 3, text, C.orange)
  elseif (view.picked or 0) > 0 then
    local text = "+" .. ui.group(view.picked)
    local at = right - c:bigWidth(text, 1)
    c:big(at, ASIDE_Y, text, C.gold, 1)
    if view.hot then c:big(at - 6 - c:bigWidth("HOT!", 1), ASIDE_Y, "HOT!", C.orange, 1) end
  end
end

--- The scoring table, in the room a result covers.
local function reminder(c, x, w)
  local cx = x + math.floor(w / 2)
  c:textCenter(cx, TABLE_Y, "A one 100    A five 50    Three of a kind: face x 100    Three ones 1000", C.mute)
  c:textCenter(cx, TABLE_Y + 2, "Four 1000    Five 2000    Six 3000", C.mute)
  c:textCenter(cx, TABLE_Y + 4, "Straight 1500    Three pairs 1500    Two triples 2500", C.mute)
end

--- Everything but the reminder. Fits a 121 wide wall from row 10 to row 54, above where a result banner lands.
function M.board(c, view, anim, info, x, w)
  local ev = anim and anim.ev
  local kind = ev and ev.type
  -- The view is already past the event, so while a throw plays the wall holds back whose turn it became
  local rolling = kind == "roll"
  local thrower = rolling and ev.seat or view.turn
  local running = rolling and (ev.running or 0) or (view.running or 0)
  local shown = {}
  for key, value in pairs(view) do shown[key] = value end
  shown.rolling = rolling
  race(c, shown, thrower, running, x, w)
  if kind == "farkle" then
    headline(c, "FARKLE!", C.red, x, w, C.text)
  elseif kind == "hot" then
    headline(c, "HOT DICE!", C.gold, x, w, C.ink)
  elseif kind == "lastturn" then
    headline(c, "LAST TURN", C.orange, x, w, C.ink)
  elseif kind == "bank" then
    headline(c, "BANK " .. ui.group(ev.points or 0), C.win, x, w, C.ink)
  else
    status(c, shown, thrower, running, x, w)
  end
  closing(c, view, x, w)
  dice(c, shown, anim, x, w)
  aside(c, shown, x, w)
end

function M.draw(c, view, anim, info)
  local x, _, w = seatui.area(c)
  M.board(c, view, anim, info, x, w)
  reminder(c, x, w)
end

--- Each die is a tap, but only on the thrower's own wall.
function M.regions(view)
  local list = {}
  if view.phase ~= "pick" or not view.me or view.me ~= view.turn then return list end
  for index = 1, #(view.dice or {}) do
    list[index] = { id = "die", value = index, x = dieX(1, WALL_W, #view.dice, index), y = DICE_Y, w = DIE_W, h = DIE_H }
  end
  return list
end

return M
