-- games/blackjack/tableView.lua
-- The dealer's wall: the dealer's hand along the top and every seat's hand below it, in a grid of up to four across and two down. All
-- of it sits above the result banner, so the final hands stay in view over it.

local look = require("games.blackjack.look")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local DEALER_Y = seatui.TOP
local DEALER_FAN = 74
local SIDE_LEFT, SIDE_RIGHT = 12, 109   -- the columns beside the dealer's cards
local GRID_Y = 28
local PANEL_W, PANEL_H = 29, 15         -- 2 rows of 15 end above the banner, at row 58
local PANEL_GAP = 1
local COLUMNS = 4
local LEGEND_Y = 60

local function drawDealer(c, view, anim)
  local cards, total = look.dealerNow(view, anim)
  look.row(c, 61, DEALER_Y, DEALER_FAN, cards, true)
  c:textCenter(SIDE_LEFT, DEALER_Y + 1, "DEALER", C.text)
  if total then
    c:bigCenter(SIDE_LEFT, DEALER_Y + 5, tostring(total), look.totalColor(total), 2)
    if view.phase == "over" and not anim then
      if total > 21 then
        c:textCenter(SIDE_LEFT, DEALER_Y + 3, "BUST", C.red)
      elseif #cards == 2 and total == 21 then
        c:textCenter(SIDE_LEFT, DEALER_Y + 3, "BLACKJACK", C.gold)
      end
    end
  end
  for offset = 3, 0, -1 do ui.card(c, SIDE_RIGHT - 9 + offset * 2, DEALER_Y, nil, true) end
  c:textCenter(SIDE_RIGHT, DEALER_Y + ui.SMALL_H + 2, ui.group(view.left or 0) .. " cards", C.text)
  if anim and anim.ev.type == "start" and anim.ev.fresh then
    c:textCenter(SIDE_RIGHT, DEALER_Y + ui.SMALL_H + 3, "New shoe", C.gold)
  end
end

--- One line under a hand: its total on the left, and what became of it or its word on the right.
local function drawStatus(c, x, y, w, hand, judged)
  local total = tostring(hand.total)
  c:text(x, y, total, look.totalColor(hand.total), C.feltDark)
  local word, color
  if judged then word, color = look.outcome(hand) else word, color = look.tag(hand) end
  if word then c:text(x + w - #word, y, word, color, C.feltDark) end
end

--- A split seat has two hands in the room of one, so each is a row of the smallest cards with its line above.
local function drawSplit(c, x, y, seat, judged, acting)
  local cx = x + math.floor(PANEL_W / 2)
  for number, hand in ipairs(seat.hands) do
    local top = y + 1 + (number - 1) * 6
    local playing = acting and seat.active == number
    if playing then c:rect(x, top, PANEL_W, 1, C.ink) end
    drawStatus(c, x + 1, top, PANEL_W - 2, hand, judged)
    look.miniRow(c, cx, top + 1, PANEL_W - 2, hand.cards)
  end
end

local function drawSeat(c, x, y, seat, view, anim, position)
  local acting = view.turn == seat.seat
  local judged = look.judged(view, anim)
  local head = acting and C.gold or C.panel
  local ink = acting and C.ink or C.text
  c:rect(x, y, PANEL_W, PANEL_H - 1, C.feltDark)
  c:rect(x, y, PANEL_W, 1, head)
  c:text(x + 1, y, seatui.short(seat.name, 16), ink, head)
  local total = 0
  for _, hand in ipairs(seat.hands) do total = total + hand.bet end
  local bet = ui.group(total)
  c:text(x + PANEL_W - #bet - 1, y, bet, acting and C.ink or C.gold, head)

  if #seat.hands > 1 then
    drawSplit(c, x, y, seat, judged, acting)
    return
  end
  local hand = seat.hands[1]
  local cards = look.handNow(view, position, hand.cards, anim)
  look.row(c, x + math.floor(PANEL_W / 2), y + 1, PANEL_W - 2, cards, false)
  if #cards == #hand.cards then drawStatus(c, x + 1, y + PANEL_H - 2, PANEL_W - 2, hand, judged) end
end

function M.draw(c, view, anim)
  if type(view) ~= "table" or type(view.seats) ~= "table" then return end
  drawDealer(c, view, anim)
  local count = #view.seats
  local rows = math.ceil(count / COLUMNS)
  local top = rows == 1 and GRID_Y + 6 or GRID_Y
  -- Printed on the felt, as on a real table. The result banner goes over it
  local cx = math.floor(c.w / 2)
  c:bigCenter(cx, LEGEND_Y, "BLACKJACK PAYS 3 TO 2", C.feltLight, 1)
  c:textCenter(cx, LEGEND_Y + 7, "Dealer hits soft 17. Double on hard 11.", C.text)
  for position, seat in ipairs(view.seats) do
    local row = math.floor((position - 1) / COLUMNS)
    local inRow = math.min(COLUMNS, count - row * COLUMNS)
    local width = inRow * PANEL_W + (inRow - 1) * PANEL_GAP
    local left = math.floor((c.w - width) / 2) + 1
    local column = (position - 1) % COLUMNS
    drawSeat(c, left + column * (PANEL_W + PANEL_GAP), top + row * PANEL_H, seat, view, anim, position)
  end
end

return M
