-- games/stud/tableView.lua
-- The dealer's wall: every board, the pot, the street and whose turn it is. Only ever drawn from the public view.
--
-- Rows 10-17 are the pot and the street, 18-57 the boards, 58-72 the turn. The result banner covers those last 15 rows.
-- Up to four players get a wide box with a row of seven cards. More get a narrow box with the down-cards over the up-cards.

local cards = require("games.stud.cards")
local rules = require("games.stud.rules")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local HEAD_H = 8
local BOX_H, BOX_GAP = 19, 1
local WIDE_BOX, TINY_BOX = 59, 29
local STREET_X = 50    -- past the widest pot

--- The seat this view says is acting, or nil.
local function acting(view)
  for _, player in ipairs(view.players) do
    if player.seat == view.turn then return player end
  end
  return nil
end

local function header(c, view, x, y, w)
  c:big(x + 3, y + 1, "POT " .. ui.group(view.pot or 0), C.gold, 1)
  c:big(x + STREET_X, y + 1, view.name or "", C.text, 1)
  if view.community then
    local cardX = x + w - cards.TINY_W - 3
    c:text(cardX - 7, y + 3, "SHARED", C.gold)
    cards.draw(c, cardX, y, view.community, cards.TINY_W, cards.TINY_H)
  else
    local limit = "Limit " .. tostring(view.size or rules.SMALL)
    c:text(x + w - #limit - 3, y + 2, limit, C.mute)
  end
end

--- The down-cards known for a player: faces at a showdown, otherwise backs.
local function downs(player)
  local list = {}
  for index = 1, player.downs or 0 do
    list[index] = player.down and player.down[index] or false
  end
  return list
end

local function face(c, x, y, card, w, h)
  cards.draw(c, x, y, card or nil, w, h)
end

--- Two cards down, four up and one down, in a row, as the hand was dealt.
local function wideCards(c, player, x, y)
  local list = downs(player)
  local w, h = cards.WIDE_W, cards.WIDE_H
  local step = w + 1
  for index = 1, 7 do
    local cardX = x + (index - 1) * step
    local card
    if index <= 2 then card = list[index]
    elseif index <= 6 then card = player.up[index - 2]
    else card = list[3] end
    if card == nil then cards.slot(c, cardX, y, w, h) else face(c, cardX, y, card, w, h) end
  end
end

local function tinyCards(c, player, x, y)
  local list = downs(player)
  local w, h = cards.TINY_W, cards.TINY_H
  local step = w + 1
  for index = 1, 3 do
    if list[index] ~= nil then face(c, x + (index - 1) * step, y, list[index], w, h) end
  end
  for index = 1, 4 do
    local card = player.up[index]
    if card then cards.draw(c, x + (index - 1) * step, y + h + 1, card, w, h) end
  end
end

local function statusOf(player, over)
  if player.folded then return "FOLDED", C.mute end
  if over and player.net then
    if player.net > 0 then return "+" .. ui.group(player.net), C.win end
    if player.net < 0 then return ui.group(player.net), C.red end
    return "EVEN", C.text
  end
  if player.allin then return "ALL-IN", C.orange end
  return player.last or "", C.text
end

local function box(c, view, player, x, y, w, wide)
  local up = view.turn == player.seat
  c:rect(x, y, w, BOX_H, C.feltDark)
  c:frame(x, y, w, BOX_H, up and C.gold or C.feltLight)
  local status, color = statusOf(player, view.over)
  local room = w - #status - 4
  c:text(x + 2, y + 1, seatui.short(player.name, room), up and C.gold or C.text, C.feltDark)
  c:text(x + w - #status - 2, y + 1, status, color, C.feltDark)
  local line = player.handName or player.board or ""
  if not player.folded then
    local total = tostring(player.total or 0)
    c:text(x + 2, y + 2, line:sub(1, w - #total - 6), C.gold, C.feltDark)
    c:text(x + w - #total - 2, y + 2, total, C.mute, C.feltDark)
  end
  if player.folded then return end
  if wide then wideCards(c, player, x + 2, y + 4) else tinyCards(c, player, x + 1, y + 3) end
end

local function boards(c, view, x, y, w)
  local list = view.players
  local wide = #list <= 4
  local columns = wide and 2 or 4
  local boxW = wide and WIDE_BOX or TINY_BOX
  local rows = math.ceil(#list / columns)
  local room = 2 * BOX_H + BOX_GAP
  local top = y + math.floor((room - (rows * BOX_H + (rows - 1) * BOX_GAP)) / 2)
  for row = 1, rows do
    local first = (row - 1) * columns + 1
    local last = math.min(#list, row * columns)
    local used = (last - first + 1) * boxW + (last - first) * BOX_GAP
    local left = x + math.floor((w - used) / 2)
    for index = first, last do
      box(c, view, list[index], left + (index - first) * (boxW + BOX_GAP), top + (row - 1) * (BOX_H + BOX_GAP), boxW, wide)
    end
  end
end

--- Below the boards while a hand runs. The result banner takes this space at the end.
local function turnLine(c, view, anim, y, cx)
  if view.over then return end
  if anim and anim.ev and anim.ev.type == "street" then
    c:bigCenter(cx, y, tostring(rules.STREETS[anim.ev.street] or ""), C.gold, 2)
    return
  end
  local player = acting(view)
  if not player then return end
  c:bigCenter(cx, y, seatui.short(player.name, 13) .. " TO ACT", C.gold, 1)
  local note
  if view.bringin then
    note = "Lowest card brings it in for " .. rules.BRING_IN .. " or completes to " .. rules.SMALL
  elseif (view.current or 0) > 0 then
    note = "Bet " .. view.current .. " this street, " .. view.bets .. " of " .. view.maxBets .. " bets made"
  else
    note = "No bet yet this street"
  end
  c:textCenter(cx, y + 8, note, C.text)
end

function M.draw(c, view, anim)
  if type(view) ~= "table" or type(view.players) ~= "table" then return end
  local x, y, w = seatui.tableArea(c)
  header(c, view, x, y, w)
  boards(c, view, x, y + HEAD_H, w)
  turnLine(c, view, anim, y + HEAD_H + 2 * BOX_H + BOX_GAP + 2, x + math.floor(w / 2))
end

return M
