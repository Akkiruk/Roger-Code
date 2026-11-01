-- games/stud/seatView.lua
-- A seat's screen, 78 wide: the street and pot, this player's seven places, and a line for each other player. Down-cards are marked,
-- because only this screen shows them. With no private fields in the view, as for someone watching, it shows the boards alone.
--
-- Rows 10-11 the street and what the hand is, 12-24 the cards, 25 the marks, 26-29 the others. A result banner covers rows 30-39.

local cards = require("games.stud.cards")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local SLOTS = 7
local LINE_W = 38    -- two columns of other players
local NAME_W = 9

local function headline(c, view, x, y, w)
  c:text(x + 2, y, view.name or "", C.text)
  local pot = "Pot " .. ui.group(view.pot or 0)
  c:text(x + w - #pot - 3, y, pot, C.gold)
  local me = view.me
  if not me then return end
  c:text(x + 2, y + 1, me.folded and "You folded" or (me.handName or ""), me.folded and C.mute or C.gold)
  if not view.over and not me.folded and (me.toCall or 0) > 0 then
    local owes = "To call " .. ui.group(me.toCall)
    c:text(x + w - #owes - 3, y + 1, owes, C.text)
  end
end

--- Two down, four up, then the last down or the shared card. The marks say which only this player can see.
local function hand(c, view, x, y, w)
  local me = view.me
  local cw, ch = cards.SEAT_W, cards.SEAT_H
  local xs = ui.fan(x + math.floor(w / 2), SLOTS, cw, w - 2, 1)
  for index = 1, SLOTS do
    local card
    if index <= 2 then card = me.down[index]
    elseif index <= 6 then card = me.up[index - 2]
    else card = me.down[3] or view.community end
    if card == nil then
      cards.slot(c, xs[index], y, cw, ch)
    else
      cards.draw(c, xs[index], y, card, cw, ch)
    end
    local hidden = index <= 2 or (index == 7 and me.down[3] ~= nil)
    if hidden then
      c:textCenter(xs[index] + math.floor(cw / 2), y + ch, "HIDDEN", C.gold)
    elseif index == 7 and card ~= nil then
      c:textCenter(xs[index] + math.floor(cw / 2), y + ch, "SHARED", C.text)
    end
  end
end

--- One other player on a line: name, what they show, what they did.
local function other(c, view, player, x, y)
  local up = view.turn == player.seat
  c:text(x, y, seatui.short(player.name, NAME_W), up and C.gold or (player.folded and C.mute or C.text))
  local cardX = x + NAME_W + 1
  if player.folded then
    c:text(cardX, y, "folded", C.mute)
    return
  end
  for _, card in ipairs(player.down or {}) do
    cardX = cardX + cards.chip(c, cardX, y, card) + 1
  end
  for _, card in ipairs(player.up or {}) do
    cardX = cardX + cards.chip(c, cardX, y, card) + 1
  end
  local status = player.allin and "ALL-IN" or player.last
  if status and x + LINE_W - #status - 1 > cardX then
    c:text(x + LINE_W - #status - 1, y, status, player.allin and C.orange or C.mute)
  end
end

local function others(c, view, x, y, rows, columns)
  local me = view.me and view.me.seat
  local row, column = 0, 0
  for _, player in ipairs(view.players) do
    if player.seat ~= me then
      if row < rows and column < columns then other(c, view, player, x + column * LINE_W, y + row) end
      row = row + 1
      if row == rows then row, column = 0, column + 1 end
    end
  end
end

function M.draw(c, view)
  if type(view) ~= "table" or type(view.players) ~= "table" then return end
  local x, y, w = seatui.area(c)
  headline(c, view, x, y, w)
  if view.me then
    hand(c, view, x, y + 2, w)
    others(c, view, x + 2, y + 2 + cards.SEAT_H + 1, 4, 2)
  else
    if view.community then
      c:text(x + 2, y + 1, "Shared card", C.text)
      cards.chip(c, x + 14, y + 1, view.community)
    end
    others(c, view, x + 2, y + 3, 4, 2)
  end
end

return M
