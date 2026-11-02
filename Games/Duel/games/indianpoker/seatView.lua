-- games/indianpoker/seatView.lua
-- A player's wall: the other player's card big on the left, their own face down on the right, and the pot between them.
-- A view with no seat is a wall with no viewer: it has no card to show until the hand is over, so it draws two backs.

local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local SCALE = 2                                       -- twice ui.card's own size: one card each is all there is to look at
local CARD_W, CARD_H = ui.CARD_W * SCALE, ui.CARD_H * SCALE
local MARGIN = 3                                      -- each card's distance from its edge of the wall
local NAME_Y, NOTE_Y, CARD_Y = 11, 17, 18
local STACK_Y, LAST_Y = 52, 53                        -- under the cards, above where a result banner lands
local POT_Y, SUM_Y = 20, 41
local TURN_Y, SAID_Y, HINT_Y = 56, 63, 65             -- the strip a result banner covers
local NAME_ROOM = 9                                   -- letters of a name that fit in big type beside the pot
local TURN_AT = 0.35                                  -- how far through the reveal the cards turn

local SAID = { CHECK = "checked", BET = "bet", RAISE = "raised", CALL = "called", ["ALL-IN"] = "went all-in", FOLD = "folded" }

--- ui.card draws at one size, so it draws here through a canvas that scales what it is asked for.
local function zoomed(c, ox, oy)
  local function at(x, y) return ox + (x - 1) * SCALE, oy + (y - 1) * SCALE end
  return {
    rect = function(_, x, y, w, h, bg)
      local px, py = at(x, y)
      c:rect(px, py, w * SCALE, h * SCALE, bg)
    end,
    big = function(_, x, y, text, color, scale)
      local px, py = at(x, y)
      c:big(px, py, text, color, (scale or 1) * SCALE)
    end,
  }
end

local function bigCard(c, x, y, card)
  ui.card(zoomed(c, x, y), 1, 1, card)
  if card == nil then
    local cx, cy = x + math.floor(CARD_W / 2), y + math.floor(CARD_H / 2)
    c:rect(cx - 6, cy - 7, 13, 14, C.card)
    c:bigCenter(cx + 1, cy - 5, "?", C.ink, 2)
  end
end

--- Which player goes where: this wall's own on the right, the other on the left. A wall nobody owns keeps them in seat order.
local function sides(view, info)
  local players = view.players
  local me = view.seat or (info and info.seat)
  if players[1].seat == me then return players[2], players[1] end
  return players[1], players[2]
end

--- Whether the cards have turned: a hand can end on a press whose chips still have to land first.
local function turned(view, anim)
  if not view.over then return false end
  if not anim or not anim.ev then return true end
  return anim.ev.type == "reveal" and (anim.t or 1) >= TURN_AT
end

local function nameOf(player, room)
  return seatui.short(player and player.name or "?", room or 12)
end

local function acting(view, player)
  return not view.over and view.turn == player.seat
end

--- A band round the winning card. It starts level with the card, because the row above holds a note.
local function winnerMark(c, x)
  c:rect(x - 1, CARD_Y, CARD_W + 2, CARD_H + 1, C.win)
end

--- A player's stack and their last move, under their card.
local function under(c, x, player)
  local cx = x + math.floor(CARD_W / 2)
  c:textCenter(cx, STACK_Y, "STACK " .. ui.group(player.stack), C.text)
  if player.folded then
    c:textCenter(cx, LAST_Y, "FOLDED", C.mute)
  elseif player.allin then
    c:textCenter(cx, LAST_Y, "ALL-IN", C.gold)
  elseif player.last then
    c:textCenter(cx, LAST_Y, player.last, C.gold)
  end
end

--- The card on the left: what the wall's player can see. It is the other player's, and on a wall with no viewer it is a back.
local function leftSide(c, x, view, player, showing)
  c:big(x, NAME_Y, nameOf(player, NAME_ROOM), acting(view, player) and C.gold or C.text, 1)
  local note = "Face down until the hand ends"
  if view.over then
    note = player.folded and "Folded this" or "Held this"
  elseif view.seat then
    note = "Their card. You can see it, they cannot"
  end
  c:text(x, NOTE_Y, note, C.text)
  if showing and (player.net or 0) > 0 then winnerMark(c, x) end
  bigCard(c, x, CARD_Y, showing and player.card or view.theirs)
  under(c, x, player)
end

--- The card on the right: the wall's own player's, which this wall only turns over at the end.
local function rightSide(c, x, view, player, showing)
  local title = view.seat and "YOUR CARD" or nameOf(player, NAME_ROOM)
  c:big(x + CARD_W - c:bigWidth(title, 1), NAME_Y, title, acting(view, player) and C.gold or C.text, 1)
  local note = "Face down until the hand ends"
  if view.over then
    note = player.folded and "Folded this" or "Held this"
  elseif view.seat then
    note = "This one is yours. You cannot see it"
  end
  c:text(x + CARD_W - #note, NOTE_Y, note, C.text)
  if showing and (player.net or 0) > 0 then winnerMark(c, x) end
  bigCard(c, x, CARD_Y, showing and player.card or nil)
  under(c, x, player)
end

--- Between the cards: the pot, and who has put in what.
local function middle(c, view, cx, left, right)
  c:bigCenter(cx, POT_Y, "POT", C.gold, 1)
  c:bigCenter(cx, POT_Y + 7, ui.group(view.pot), C.gold, 2)
  if view.over then return end
  c:textCenter(cx, SUM_Y, nameOf(left, 12) .. " has " .. left.total .. " in", C.text)
  local own = view.seat and "You have " or (nameOf(right, 12) .. " has ")
  c:textCenter(cx, SUM_Y + 2, own .. right.total .. " in", C.text)
  c:textCenter(cx, SUM_Y + 5, "Bets are " .. view.size, C.mute)
end

--- What the last move was, in words.
local function lastMove(view, left, right)
  local who = view.lastSeat == right.seat and right or left
  if not view.lastSeat or not who.last then return nil end
  local name = (view.seat and who == right) and "You" or nameOf(who, 14)
  return name .. " " .. (SAID[who.last] or "moved")
end

--- The strip under the cards, which says what is on the player: their turn and its price, or whose turn it is.
local function strip(c, view, cx, left, right)
  if view.over then
    c:bigCenter(cx, TURN_Y, "THE CARDS TURN OVER", C.gold, 1)
    return
  end
  local turn = view.turn == left.seat and left or right
  local line, color = nameOf(turn, 14) .. " TO ACT", C.text
  if view.seat == view.turn then
    line, color = "YOUR TURN", C.gold
    if (view.toCall or 0) > 0 then line = line .. ": " .. view.toCall .. " TO CALL" end
  elseif view.seat then
    line, color = "WAITING FOR " .. nameOf(turn, 12), C.text
  end
  if c:bigWidth(line, 1) <= c.w - 4 then
    c:bigCenter(cx, TURN_Y, line, color, 1)
  else
    c:textCenter(cx, TURN_Y + 2, line, color)
  end
  local said = lastMove(view, left, right)
  if said then c:textCenter(cx, SAID_Y, said, C.text) end
  local hint
  if not view.seat then
    hint = "Each player sees only the other's card, so no card shows here"
  elseif view.bets >= view.maxBets then
    hint = "That was the last raise: call or fold"
  else
    hint = view.bets .. " of " .. view.maxBets .. " bets made. A bet and two raises at most"
  end
  c:textCenter(cx, HINT_Y, hint, C.mute)
end

function M.draw(c, view, anim, info)
  if not view.players or not view.players[2] then return end
  local x, _, w = seatui.area(c)
  local cx = math.floor(c.w / 2) + 1
  local left, right = sides(view, info)
  local showing = turned(view, anim)
  leftSide(c, x + MARGIN, view, left, showing)
  rightSide(c, x + w - MARGIN - CARD_W, view, right, showing)
  middle(c, view, cx, left, right)
  strip(c, view, cx, left, right)
end

return M
