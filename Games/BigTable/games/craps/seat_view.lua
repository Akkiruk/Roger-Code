-- games/craps/seat_view.lua
-- A seat: what this player has riding on the dice, the dice themselves, and what the last rolls did. The wall has the rest.

local dice = require("games.craps.dice")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local COLUMN = 24      -- one column of bets
local LIST_ROWS = 16   -- bets to a column

--- A bet and its odds as one line.
local function amount(record)
  local text = ui.group(record.bet)
  if record.odds > 0 then text = text .. " +" .. ui.group(record.odds) end
  return text
end

local function padded(label, value)
  return label .. string.rep(" ", math.max(1, COLUMN - 2 - #label - #value)) .. value
end

--- Everything this seat has up, as lines.
local function lines(mine)
  local list = {}
  local function add(label, value) list[#list + 1] = padded(label, value) end
  if mine.pass.bet > 0 then add("PASS", amount(mine.pass)) end
  if mine.dont.bet > 0 then add("DON'T PASS", amount(mine.dont)) end
  if mine.field > 0 then add("FIELD", ui.group(mine.field)) end
  if mine.comeBox > 0 then add("COME", ui.group(mine.comeBox)) end
  if mine.dontBox > 0 then add("DON'T COME", ui.group(mine.dontBox)) end
  for _, bet in ipairs(mine.come) do add("COME " .. bet.n, amount(bet)) end
  for _, bet in ipairs(mine.lay) do add("DON'T " .. bet.n, amount(bet)) end
  return list
end

local function status(view, mine)
  if view.over then return view.call or "ROUND OVER" end
  if view.rolling then return "NO MORE BETS" end
  if view.stage == "comeout" then return mine and mine.shooting and "COME OUT ROLL. YOUR DICE" or "COME OUT ROLL" end
  if view.stage == "runout" then return mine and mine.shooting and "ROLL OUT THE COME BETS" or "ROLLING OUT THE COME BETS" end
  return "POINT IS " .. tostring(view.point) .. (mine and mine.shooting and ". YOUR DICE" or "")
end

--- The six numbers along the bottom, with the puck.
local function strip(c, view, x, y, puck)
  for index, spot in ipairs(view.numbers or {}) do
    local bx = x + (index - 1) * 12
    local lit = puck == spot.n
    c:panel(bx, y, 11, 3, lit and C.gold or C.feltLight, C.felt)
    c:textCenter(bx + 5, y + 1, tostring(spot.n), lit and C.ink or C.text, lit and C.gold or C.feltLight)
  end
end

function M.draw(c, view, anim)
  if not view or not view.stage then return end
  local x, y, w = seatui.area(c)
  local cx = math.floor(c.w / 2) + 1
  local mine = view.mine
  local flying = dice.flying(anim)
  local puck = view.point
  if flying then puck = anim.ev.point end

  c:textCenter(cx, y + 1, flying and "THE DICE ARE OUT" or status(view, mine), C.gold)

  local diceX = x + w - 2 * dice.SMALL_W - 5
  if anim and anim.ev.type == "roll" then
    local dx, dy = dice.flight(anim, 8, 2)
    dice.draw(c, diceX - dx, y + 3 - dy, dice.tumble(anim, 1), false)
    dice.draw(c, diceX + dice.SMALL_W + 2 - dx, y + 3, dice.tumble(anim, 2), false)
  else
    local shown = view.dice or {}
    dice.draw(c, diceX, y + 3, shown[1], false)
    dice.draw(c, diceX + dice.SMALL_W + 2, y + 3, shown[2], false)
  end

  local logX = diceX
  if not flying then
    if view.total then c:text(logX, y + 12, "Rolled " .. view.total, C.text) end
    for index, line in ipairs(mine and mine.log or {}) do
      local value = ui.signed(line.amount)
      local row = y + 12 + index
      c:text(logX, row, line.label, C.mute)
      c:text(c.w - 2 - #value, row, value, line.amount > 0 and C.win or (line.amount < 0 and C.red or C.text))
    end
  end

  if mine and not flying then
    c:text(x + 2, y + 3, "YOUR BETS", C.gold)
    local list = lines(mine)
    if #list == 0 then c:text(x + 2, y + 4, "Nothing up", C.mute) end
    for index, line in ipairs(list) do
      local column = math.floor((index - 1) / LIST_ROWS)
      c:text(x + 2 + column * COLUMN, y + 4 + (index - 1) % LIST_ROWS, line, C.text)
    end
    if mine.limit then c:text(x + 2, y + 20, "Table limit reached", C.orange) end
    c:text(x + 2, y + 21, "This round " .. ui.signed(mine.net), mine.net > 0 and C.win or (mine.net < 0 and C.red or C.text))
  end

  strip(c, view, x + 3, y + 25, puck)
end

return M
