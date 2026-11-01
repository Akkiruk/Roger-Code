-- games/baccarat/tableView.lua
-- The dealer's wall: Player on the left and Banker on the right as on a Baccarat table, then the road and everyone's bets. All of that
-- sits above the engine's result banner, which covers the shoe and the legend, so the final coup stays in view over it.

local base = require("games.baccarat.coup")
local played = require("games.baccarat.played")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local ZONES = {
  player = { x = 4, w = 56, label = "PLAYER" },
  banker = { x = 63, w = 56, label = "BANKER" },
}
local ZONE_Y, ZONE_H = ui.TOP, 40
local LABEL_Y = ZONE_Y + 2
local TOTAL_Y = LABEL_Y + 7
local STAKE_Y = TOTAL_Y + 3    -- what's on this side, to one side of the total
local NATURAL_Y = TOTAL_Y + 4  -- the word on the other
local CARD_Y = TOTAL_Y + 12
local ROAD_X, ROAD_Y = 4, ZONE_Y + ZONE_H + 1
local BOARD_Y = ROAD_Y + 2     -- four rows of bets, two columns, and the banner starts below them
local BOARD_ROWS, BOARD_W = 4, 58
local LEGEND_Y = BOARD_Y + 7
local SHOE_X, SHOE_Y = 4, LEGEND_Y
local ROAD_COLORS = { P = "blue", B = "red", T = "gold" }

local function won(winner, name)
  return winner == name or winner == "tie"
end

--- The three card places in a zone, which share a column to keep two clear inside its frame.
local function slots(zone)
  return ui.fan(zone.x + math.floor(zone.w / 2), 3, ui.CARD_W, zone.w - 6, 1)
end

--- All the seats' bets on one side.
local function staked(view, side)
  local sum = 0
  for _, line in ipairs(view.bets or {}) do sum = sum + (line[side] or 0) end
  return sum
end

local function drawZone(c, view, shown, name)
  local zone, cards = ZONES[name], shown[name]
  local cx = zone.x + math.floor(zone.w / 2)
  local lit = won(shown.winner, name)
  c:rect(zone.x + 1, ZONE_Y + 1, zone.w - 2, ZONE_H - 2, lit and C.feltDark or C.felt)
  c:frame(zone.x, ZONE_Y, zone.w, ZONE_H, lit and C.gold or C.feltLight)
  c:bigCenter(cx, LABEL_Y, zone.label, lit and C.gold or C.text, 1)

  local on = staked(view, name)
  if on > 0 then
    c:text(zone.x + 3, STAKE_Y, "Bets", C.gold)
    c:text(zone.x + 3, STAKE_Y + 2, ui.group(on), C.gold)
  end

  if #cards > 0 then
    local total = base.total(cards)
    local natural = #cards == 2 and total >= base.NATURAL
    c:bigCenter(cx, TOTAL_Y, tostring(total), (natural or lit) and C.gold or C.text, 2)
    if natural then c:text(zone.x + zone.w - 10, NATURAL_Y, "NATURAL", C.gold) end
  end

  local incoming = shown.incoming
  local xs = slots(zone)
  for slot = 1, 3 do
    if cards[slot] then
      ui.card(c, xs[slot], CARD_Y, cards[slot], false)
      -- White on white runs together, so each card gets an edge
      if cards[slot - 1] then c:rect(xs[slot], CARD_Y + 1, 1, ui.CARD_H - 2, C.mute) end
    elseif not (incoming and incoming.who == name and incoming.slot == slot) then
      ui.cardSlot(c, xs[slot], CARD_Y, false)
    end
  end
end

--- The card on its way from the shoe goes over everything else.
local function drawIncoming(c, shown, anim)
  local ev = shown.incoming
  if not ev then return end
  local xs = slots(ZONES[ev.who])
  local t = anim.t
  ui.card(c, SHOE_X + math.floor((xs[ev.slot] - SHOE_X) * t), SHOE_Y + math.floor((CARD_Y - SHOE_Y) * t), ev.card, false)
end

--- Recent coups as a row of pills, newest first.
local function drawRoad(c, road)
  if road == "" then return end
  c:text(ROAD_X, ROAD_Y, "ROAD", C.text)
  for i = 1, #road do
    local letter = road:sub(i, i)
    local x = ROAD_X + 5 + (i - 1) * 4
    local bg = C[ROAD_COLORS[letter]]
    c:rect(x, ROAD_Y, 3, 1, bg)
    c:text(x + 1, ROAD_Y, letter, letter == "T" and C.ink or C.text, bg)
  end
end

--- One seat's bets on one row: name, a figure a side, and the net once the outcome is out.
local function drawLine(c, x, y, line, settled)
  c:text(x, y, seatui.short(line.name or ("Seat " .. tostring(line.seat)), 13), C.text)
  local column = x + 14
  for _, side in ipairs({ "player", "banker", "tie" }) do
    if line[side] then
      c:text(column, y, side:sub(1, 1):upper() .. " " .. ui.group(line[side]), side == "tie" and C.gold or C.text)
    end
    column = column + 11
  end
  if settled and line.net then
    local net = line.net
    local text = (net > 0 and "+" or "") .. ui.group(net)
    c:text(x + BOARD_W - 1 - #text, y, text, net > 0 and C.win or net < 0 and C.red or C.gold)
  end
end

local function drawBoard(c, view, shown)
  for index, line in ipairs(view.bets or {}) do
    local column = math.floor((index - 1) / BOARD_ROWS)
    drawLine(c, ROAD_X + column * (BOARD_W + 1), BOARD_Y + (index - 1) % BOARD_ROWS, line, shown.winner ~= nil)
  end
end

local function drawLegend(c, view)
  local cx = math.floor(c.w / 2) + 1
  if not view.over then
    c:bigCenter(cx, LEGEND_Y + 1, "NO MORE BETS", C.gold, 1)
  end
  local tie = staked(view, "tie")
  if tie > 0 then c:textCenter(cx, LEGEND_Y + 7, "Tie bets " .. ui.group(tie), C.gold) end
  c:textCenter(cx, LEGEND_Y + 9, ("Player %d:1   Banker %d:1 less %d%%   Tie %d:1, others push"):format(
    base.PAYS.player, base.PAYS.banker, base.COMMISSION, base.PAYS.tie), C.text)
  if view.fresh then c:textCenter(cx, LEGEND_Y + 11, "A new shoe", C.text) end
end

function M.draw(c, view, anim)
  local shown = played.of(view, anim)
  for i = 2, 0, -1 do ui.card(c, SHOE_X + i, SHOE_Y, nil, true) end
  drawLegend(c, view)
  drawZone(c, view, shown, "player")
  drawZone(c, view, shown, "banker")
  drawRoad(c, shown.road)
  drawBoard(c, view, shown)
  drawIncoming(c, shown, anim)
end

return M
