-- games/roulette/seatView.lua
-- A player's own 78x52: tabs for the inside bets, the layout, and a few lines on their money. The chips and the edit buttons are the
-- engine's button rows. The wheel itself is on the dealer's wall. Here the numbers run past, and the result lands on the layout.

local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local board = require("games.roulette.board")
local wheel = require("games.roulette.wheel")

local C = theme.C
local M = {}

local BOARD_OFFSET = 4               -- rows under the top of the area, for the tabs and a gap
local STATUS_OFFSET = BOARD_OFFSET + board.HEIGHT
local BAND_OFFSET = 19               -- the running numbers lie over the outside bets, below what a result banner must leave clear
local BAND_H = 10
local RUN_PAST = 74                  -- pockets that go by in a spin. Two times round and then some

local function easeOut(t)
  local u = 1 - t
  return 1 - u * u * u
end

local function pocketAt(number, t)
  local home
  for i, n in ipairs(wheel.WHEEL) do
    if n == number then home = i end
  end
  local steps = math.floor(easeOut(t) * RUN_PAST + 0.5)
  return wheel.WHEEL[(home - 1 + steps - RUN_PAST) % wheel.POCKETS + 1]
end

--- The numbers go by and slow down on the winner. Nothing on the board has changed yet.
local function runningNumbers(c, y, number, t)
  local shown = pocketAt(number, t)
  local bg = board.numberBg(shown)
  local cx = math.floor(c.w / 2) + 1
  c:rect(2, y, c.w - 2, BAND_H - 1, C.ink)
  c:rect(cx - 10, y + 1, 20, BAND_H - 3, bg)
  c:bigCenter(cx, y + 1, tostring(shown), shown == 0 and C.ink or C.text, 1)
end

local function litNumbers(me)
  local lit = {}
  if me and me.lit then
    for _, n in ipairs(wheel.spot(me.lit).nums) do lit[n] = true end
  end
  return lit
end

--- The three steps, the one to do next lit gold and the ones done green, so a first-timer always knows what comes next.
local function steps(c, y, me)
  local list = {
    { "1 PICK A CHIP", me.chip ~= nil },
    { "2 TAP WHERE TO BET", me.placed > 0 },
    { "3 PRESS DONE", false },
  }
  local current = 3
  for i, step in ipairs(list) do
    if not step[2] then
      current = i
      break
    end
  end
  local x = 3
  for i, step in ipairs(list) do
    local text = " " .. step[1] .. " "
    local bg = i == current and C.gold or (step[2] and C.win or C.panel)
    c:text(x, y, text, (i == current or step[2]) and C.ink or C.text, bg)
    x = x + #text
    if i < #list then
      c:text(x, y, ">", C.text)
      x = x + 2
    end
  end
end

--- The lines under the layout while bets can still go down: the total and what may still go down, the last tap, and the steps.
local function betting(c, y, me)
  local chip = me.chip == "max" and "MAX" or ui.group(me.chip or 0)
  local line = ("TOTAL BET %s   You can bet up to %s"):format(ui.group(me.placed), ui.group(me.budget))
  c:text(3, y, line, C.gold)
  if me.left < 1 then
    c:text(3, y + 1, "That is all of it: the amount you chose for this spin", C.orange)
  elseif me.lit then
    local spot = wheel.spot(me.lit)
    c:text(3, y + 1, ("%s  pays %d:1  on it %s"):format(wheel.describe(me.lit), spot.pay, ui.group(me.spots[me.lit] or 0)), C.text)
  else
    c:text(3, y + 1, ("Chip %s. %s, or any outside bet"):format(chip, board.hint(me.mode)), C.text)
  end
  steps(c, y + 2, me)
end

local function lastRow(c, y, recent)
  if #recent == 0 then return end
  c:text(3, y, "LAST", C.mute)
  board.recentRow(c, 8, y, recent, 10)
end

function M.draw(c, view, anim)
  local _, top = seatui.area(c)
  local me = view.me
  local spinning = view.over and anim ~= nil and anim.ev.type == "spin"
  local number = (view.over and not spinning) and view.number or nil
  local open = me ~= nil and not me.done and not view.over
  local statusY = top + STATUS_OFFSET

  if open then
    board.drawTabs(c, top, me.mode)
  else
    local line = view.over and "NO MORE BETS" or "WAITING FOR THE OTHERS"
    if number then line = wheel.numberName(number) end
    if not me and not view.over then line = "BETS ARE OPEN" end
    c:textCenter(math.floor(c.w / 2) + 1, top + 1, line, C.gold)
  end

  board.draw(c, top + BOARD_OFFSET, {
    spots = me and me.spots or view.board, mode = open and me.mode or nil, lit = open and litNumbers(me) or nil,
    litSpot = open and me.lit or nil, number = number,
  })

  if spinning then
    runningNumbers(c, top + BAND_OFFSET, view.number, anim.t)
  elseif open then
    betting(c, statusY, me)
    lastRow(c, statusY + 3, view.recent or {})
  elseif me and not view.over then
    c:text(3, statusY, ("YOUR BET IS IN: %s"):format(ui.group(me.placed)), C.gold)
    c:text(3, statusY + 1, "The wheel spins when betting closes", C.text)
    lastRow(c, statusY + 2, view.recent or {})
  elseif me and number then
    c:text(3, statusY, ("BET %s   NET %s"):format(ui.group(me.placed), ui.group(me.net or 0)), C.gold)
  end
end

--- The tabs and the layout, while this seat can still bet.
function M.regions(view)
  local me = view.me
  if not me or me.done or view.over then return {} end
  local list = board.tabs(seatui.TOP)
  for _, target in ipairs(board.targets(seatui.TOP + BOARD_OFFSET, me.mode)) do list[#list + 1] = target end
  return list
end

return M
