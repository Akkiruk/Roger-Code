-- games/baccarat/seatView.lua
-- A player's own screen. There is nothing to decide once the bets are in, so it shows the two hands and what this player has on each
-- side. Small cards, so both hands fit above the result banner. A seat with no bet on this coup is sent the public view and has no own.

local base = require("games.baccarat.coup")
local played = require("games.baccarat.played")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local ZONES = {
  player = { x = 2, label = "PLAYER" },
  banker = { x = 41, label = "BANKER" },
}
local ZONE_W, ZONE_H = 37, 21    -- the last row sits under the result banner
local CARD_INSET = 8             -- rows from the top of a zone to its cards, below the name and the big total
local SIDES = { { id = "player", label = "PLAYER" }, { id = "banker", label = "BANKER" }, { id = "tie", label = "TIE" } }
local BET_W, BET_H, BET_GAP = 24, 6, 2

local function won(winner, name)
  return winner == name or winner == "tie"
end

local function drawZone(c, y, shown, name)
  local zone, cards = ZONES[name], shown[name]
  local lit = won(shown.winner, name)
  c:rect(zone.x + 1, y + 1, ZONE_W - 2, ZONE_H - 2, lit and C.feltDark or C.felt)
  c:frame(zone.x, y, ZONE_W, ZONE_H, lit and C.gold or C.feltLight)
  c:text(zone.x + 3, y + 3, zone.label, lit and C.gold or C.text)
  if #cards > 0 then
    local total = tostring(base.total(cards))
    c:big(zone.x + ZONE_W - 3 - c:bigWidth(total, 1), y + 1, total, lit and C.gold or C.text, 1)
  end
  -- Three small cards overlap across a zone, so an empty place is left bare: its outline would cut into the card beside it
  local xs = ui.fan(zone.x + math.floor(ZONE_W / 2), 3, ui.SMALL_W, ZONE_W - 2, 1)
  for slot = 1, 3 do
    if cards[slot] then
      ui.card(c, xs[slot], y + CARD_INSET, cards[slot], true)
      -- White on white runs together, so each card gets an edge
      if cards[slot - 1] then c:rect(xs[slot], y + CARD_INSET + 1, 1, ui.SMALL_H - 2, C.mute) end
    end
  end
end

--- This player's three bets, lit when their side comes up.
local function drawBets(c, y, own, shown)
  for index, side in ipairs(SIDES) do
    local x = 2 + (index - 1) * (BET_W + BET_GAP)
    local amount = own[side.id]
    local lit = shown.winner == side.id and amount ~= nil
    c:rect(x, y, BET_W, BET_H, lit and C.gold or C.feltDark)
    local cx = x + math.floor(BET_W / 2)
    local ink = lit and C.ink or C.text
    c:textCenter(cx, y + 1, side.label, ink, lit and C.gold or C.feltDark)
    c:textCenter(cx, y + 3, amount and ui.group(amount) or "-", amount and (lit and C.ink or C.gold) or C.mute, lit and C.gold or C.feltDark)
  end
end

function M.draw(c, view, anim)
  local x, y, w = seatui.area(c)
  local shown = played.of(view, anim)
  drawZone(c, y, shown, "player")
  drawZone(c, y, shown, "banker")
  local cx = x + math.floor(w / 2)
  local below = y + ZONE_H + 1
  local line = below + BET_H
  if view.own then
    drawBets(c, below, view.own, shown)
  else
    c:textCenter(cx, below + 2, "You have no bet on this coup", C.text)
  end
  if view.own and view.own.void and view.own.void > 0 then
    c:textCenter(cx, line, ("Banker needs %d: your %d stands down"):format(base.MIN_BANKER, view.own.void), C.orange)
  elseif not view.over then
    c:textCenter(cx, line, "NO MORE BETS", C.gold)
  end
end

return M
