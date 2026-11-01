-- games/draw/tableView.lua
-- The dealer's wall: everyone's place round the pot, cards face down, whose turn it is. The wall only ever gets the public view, so
-- the only faces here are the hands a showdown turned over. Places run clockwise, the top row from the left and the bottom row from
-- the right, so "left of the button" reads the way it does at a real table.

local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local cards = require("games.draw.cards")

local C = theme.C
local M = {}

local BOX_W, BOX_H, BOX_GAP = 37, 17, 3
local TOP_Y, BOTTOM_Y = ui.TOP + 2, 55
local PHASE_Y, POT_Y, ACTOR_Y, SIDE_Y, LIMIT_Y = 30, 32, 46, 48, 50
local CARD_ROW = 4         -- down from the top of a box
local WALL_W = 115         -- between the margins
local REVEAL_Y, REVEAL_ROOM = 12, 41  -- the rows for shown hands, over the result banner and the folded line
local REVEAL_H, REVEAL_GAP = 18, 3
local FOLDED_Y = 55

--- Where a place sits, with the rows centred. The top row has the odd one.
local function box(c, index, total)
  local top = math.ceil(total / 2)
  local inRow, column = top, index
  local y = TOP_Y
  if index > top then
    inRow = total - top
    column = total - index + 1
    y = BOTTOM_Y
  end
  local width = inRow * BOX_W + (inRow - 1) * BOX_GAP
  return math.floor((c.w - width) / 2) + 1 + (column - 1) * (BOX_W + BOX_GAP), y
end

--- A place at the table. cards is how many backs are dealt to it so far.
local function place(c, view, player, index, active, dealt)
  local x, y = box(c, index, #view.players)
  c:rect(x, y, BOX_W, BOX_H, C.panel)
  c:frame(x, y, BOX_W, BOX_H, active and C.gold or C.ink)
  if active then c:frame(x - 1, y - 1, BOX_W + 2, BOX_H + 2, C.gold) end

  local dim = player.folded
  c:text(x + 2, y + 1, cards.short(player.name, 16), dim and C.mute or C.text)
  if view.button == player.seat then
    c:text(x + BOX_W - 4, y + 1, " D ", C.ink, C.card)
  end
  local status = cards.status(player)
  c:text(x + 2, y + 2, ui.group(player.stack), dim and C.mute or C.gold)
  if status then c:text(x + BOX_W - 2 - #status, y + 2, status, dim and C.mute or C.win) end

  if player.folded then
    c:textCenter(x + math.floor(BOX_W / 2), y + 9, "FOLDED", C.mute)
    return
  end
  local xs = ui.fan(x + math.floor(BOX_W / 2), 5, ui.SMALL_W, BOX_W - 4, 1)
  for i = 1, math.min(dealt, 5) do ui.card(c, xs[i], y + CARD_ROW, nil, true) end
end

local function middle(c, view, dealing)
  local cx = math.floor(c.w / 2)
  c:textCenter(cx, PHASE_Y, cards.PHASES[view.phase] or "", C.gold)
  c:bigCenter(cx, POT_Y, ui.group(view.pot or 0), C.text, 2)
  local line = cards.turnLine(view)
  if line and not dealing then c:textCenter(cx, ACTOR_Y, line, C.text) end
  if (view.side or 0) > 0 then
    c:textCenter(cx, SIDE_Y, "Pot " .. ui.group(view.mainPot or 0) .. "   Side pots " .. ui.group(view.side), C.text)
  end
  if view.betsLeft and view.size then
    c:textCenter(cx, LIMIT_Y, "Bet size " .. view.size .. ". Bets left this round: " .. math.max(0, view.betsLeft), C.mute)
  end
end

--- Where a shown hand sits: two across, or three for five or six hands. Each row is centred.
local function revealBox(c, position, total)
  local across = total > 4 and 3 or 2
  local gap = 3
  local w = math.floor((WALL_W - gap * (across - 1)) / across)
  local rows = math.ceil(total / across)
  local row = math.ceil(position / across)
  local inRow = row < rows and across or total - (rows - 1) * across
  local left = 1 + math.floor((c.w - inRow * w - (inRow - 1) * gap) / 2)
  local top = REVEAL_Y + math.floor((REVEAL_ROOM - rows * REVEAL_H - (rows - 1) * REVEAL_GAP) / 2)
  return left + (position - (row - 1) * across - 1) * (w + gap), top + (row - 1) * (REVEAL_H + REVEAL_GAP), w
end

local function reveal(c, view)
  local shown, out = {}, {}
  for _, player in ipairs(view.players) do
    if player.hand then shown[#shown + 1] = player end
    if player.folded then out[#out + 1] = cards.short(player.name, 14) .. " " .. ui.signed(player.net or 0) end
  end
  for position, player in ipairs(shown) do
    local x, y, w = revealBox(c, position, #shown)
    local won = (player.net or 0) > 0
    c:rect(x, y, w, REVEAL_H, won and C.feltLight or C.panel)
    c:text(x + 2, y + 1, cards.short(player.name, 16), C.text)
    local net = ui.signed(player.net or 0)
    c:text(x + w - 2 - #net, y + 1, net, won and C.win or (player.net < 0 and C.red or C.text))
    if player.handName then c:text(x + 2, y + 2, player.handName, won and C.gold or C.text) end
    cards.fan(c, x + math.floor(w / 2), y + 4, player.hand, w - 4)
  end
  if #out > 0 then
    c:textCenter(math.floor(c.w / 2), FOLDED_Y, ("Folded: " .. table.concat(out, "   ")):sub(1, WALL_W), C.text)
  end
end

--- Nobody had to show: nothing is turned over, so just the pot.
local function walkover(c, view)
  local cx = math.floor(c.w / 2)
  c:textCenter(cx, 26, "POT", C.gold)
  c:bigCenter(cx, 28, ui.group(view.pot or 0), C.text, 2)
end

function M.draw(c, view, anim)
  if not view.players then return end
  if view.over then
    if view.uncontested then walkover(c, view) else reveal(c, view) end
    return
  end

  local dealing = anim and anim.ev.type == "deal"
  local count = #view.players
  for index, player in ipairs(view.players) do
    local dealt = 5
    if dealing then
      -- One card at a time round the table
      local progress = anim.t * 5
      dealt = math.floor(progress) + ((index - 1) / count < progress % 1 and 1 or 0)
    end
    place(c, view, player, index, view.turn == player.seat and not dealing, dealt)
  end
  middle(c, view, dealing)
end

return M
