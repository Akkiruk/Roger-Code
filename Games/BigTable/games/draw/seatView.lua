-- games/draw/seatView.lua
-- A player's own screen: their five cards, what the hand is, and on their turn in the draw the cards to tap.
-- The rows belong to the game from 10 to 39 of 52, and at the end the bottom ten of those go under the result, so the cards stop
-- above that. A screen with no hand on it is someone watching, who gets the public view: backs and the betting.

local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local cards = require("games.draw.cards")

local C = theme.C
local M = {}

local CENTRE = 40          -- the middle of a 78 wide seat. A view has no canvas in regions, so this is fixed
local INFO_Y, HAND_Y = 11, 13
local CARD_Y, LIFT = 16, 2
local LABEL_Y = 27         -- under a lifted card
local TURN_Y = 30
local OTHERS_Y = 33
local COLUMN_W, COLUMN_GAP = 34, 4   -- two columns of the other players
local LEFT = 4

local function xs()
  return ui.fan(CENTRE, 5, ui.SMALL_W, 76, 2)
end

--- The line about the turn, under the cards.
local function turnLine(view)
  if view.drawing then
    return "Tap the cards to throw: up to 3" .. (view.mayThrow > 3 and ", or 4 keeping an ace" or ""), C.gold,
      view.thrown > 0 and ("Throwing " .. view.thrown) or "With none marked you stand pat"
  end
  if view.folded then return "You folded this hand", C.mute end
  if view.seat and view.turn == view.seat then
    if (view.toCall or 0) > 0 then return "Your turn: " .. view.toCall .. " to call", C.gold end
    return "Your turn", C.gold
  end
  return cards.turnLine(view, 16), C.text
end

--- The rest of the table, a line each.
local function others(c, view)
  local row = 0
  for _, player in ipairs(view.players or {}) do
    if player.seat ~= view.seat then
      local x = LEFT + (row % 2) * (COLUMN_W + COLUMN_GAP)
      local y = OTHERS_Y + math.floor(row / 2) * 2
      local acting = player.seat == view.turn
      local color = player.folded and C.mute or (acting and C.gold or C.text)
      c:text(x, y, cards.short(player.name, 12), color)
      local status = cards.status(player) or ui.group(player.stack)
      status = status:sub(1, COLUMN_W - 13)
      c:text(x + COLUMN_W - #status, y, status, player.folded and C.mute or C.win)
      row = row + 1
    end
  end
end

function M.draw(c, view, anim)
  c:text(LEFT, INFO_Y, cards.PHASES[view.phase] or "", C.gold)
  local pot = "Pot " .. ui.group(view.pot or 0)
  c:text(c.w - 2 - #pot, INFO_Y, pot, C.text)

  if view.handName then c:text(LEFT, HAND_Y, view.handName, view.folded and C.mute or C.text) end
  if view.total then
    local line = "You are in for " .. ui.group(view.total)
    c:text(c.w - 2 - #line, HAND_Y, line, C.mute)
  end

  -- One card at a time while they are dealt
  local dealing = anim and anim.ev.type == "deal"
  local dealt = dealing and math.floor(anim.t * 5) + 1 or 5
  for i, x in ipairs(xs()) do
    local thrown = view.marks and view.marks[i]
    local y = thrown and CARD_Y - LIFT or CARD_Y
    local face = view.hand and not view.folded and i <= dealt and view.hand[i] or nil
    ui.card(c, x, y, face, true)
    if thrown then c:textCenter(x + 6, LABEL_Y, "THROW", C.orange) end
  end

  if not view.over then
    local text, color, more = turnLine(view)
    if text then c:textCenter(CENTRE - 1, TURN_Y, text, color) end
    if more then c:textCenter(CENTRE - 1, TURN_Y + 1, more, C.text) end
    others(c, view)
  end
end

--- The cards are tappable on this seat's turn in the draw.
function M.regions(view)
  local list = {}
  if not view.drawing then return list end
  for i, x in ipairs(xs()) do
    list[i] = { id = "mark", value = i, x = x, y = CARD_Y - LIFT, w = ui.SMALL_W + 1, h = ui.SMALL_H + LIFT + 2 }
  end
  return list
end

return M
