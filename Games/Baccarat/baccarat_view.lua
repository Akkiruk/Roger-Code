-- baccarat_view.lua
-- Baccarat's table: Player on the left, Banker on the right, the shoe by the legend. Everything that matters
-- sits above ui.BANNER_Y, where the engine's result banner goes, so the final coup stays in view over it.

local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("baccarat_rules")

local C = theme.C
local M = {}

local ZONES = {
  player = { x = 4, w = 56, label = "PLAYER" },
  banker = { x = 63, w = 56, label = "BANKER" },
}
local ZONE_Y, ZONE_H = ui.TOP, 40
local LABEL_Y = ZONE_Y + 2
local TOTAL_Y = LABEL_Y + 7
local BET_Y = TOTAL_Y + 3      -- the bet on one side of the total
local NATURAL_Y = TOTAL_Y + 4  -- the word on the other
local CARD_Y = TOTAL_Y + 12
local LEGEND_Y = 56
local SHOE_X, SHOE_Y = 4, 55
local CANCEL = { x = 103, y = 56, w = 15, h = 10 }
local ROAD_X, ROAD_Y = 4, ui.BANNER_Y - 2   -- between the zones and the shoe, and above the result banner
local ROAD_COLORS = { P = "blue", B = "red", T = "gold" }

local function copy(list)
  local out = {}
  for i, value in ipairs(list) do out[i] = value end
  return out
end

function M.new(ctx)
  return { ctx = ctx, player = {}, banker = {} }
end

function M.sync(model, state)
  model.player, model.banker = copy(state.player), copy(state.banker)
  model.side, model.winner = state.side, nil
end

local DURATIONS = { start = { 0.01 }, side = { 0.25, "chip" }, deal = { 0.32, "deal" }, outcome = { 0.35, "flip" } }

function M.event(model, ev)
  if ev.type == "start" then
    model.player, model.banker, model.side, model.winner = {}, {}, nil, nil
  end
  local timing = DURATIONS[ev.type] or { 0.2 }
  return timing[1], timing[2]
end

function M.commit(model, ev)
  if ev.type == "side" then
    model.side = ev.side
  elseif ev.type == "deal" then
    local hand = model[ev.who]
    hand[#hand + 1] = ev.card
  elseif ev.type == "outcome" then
    model.winner = ev.winner
  end
end

local function won(model, name)
  return model.winner == name or model.winner == "tie"
end

--- The three card places in a zone, which share a column to keep two clear inside its frame.
local function slots(zone)
  return ui.fan(zone.x + math.floor(zone.w / 2), 3, ui.CARD_W, zone.w - 6, 1)
end

local function drawZone(c, model, state, name, anim)
  local zone, cards = ZONES[name], model[name]
  local cx = zone.x + math.floor(zone.w / 2)
  local lit = won(model, name)
  c:rect(zone.x + 1, ZONE_Y + 1, zone.w - 2, ZONE_H - 2, lit and C.feltDark or C.felt)
  c:frame(zone.x, ZONE_Y, zone.w, ZONE_H, lit and C.gold or C.feltLight)
  c:bigCenter(cx, LABEL_Y, zone.label, model.side == name and C.gold or C.text, 1)

  -- The bet lies on its side of the table; a Tie bet shows on both, between which it is decided
  if model.side == name or model.side == "tie" then
    c:text(zone.x + 3, BET_Y, model.side == "tie" and "Tie bet" or "Your bet", C.gold)
    c:text(zone.x + 3, BET_Y + 2, ui.group(state.bet), C.gold)
  end

  if #cards > 0 then
    local total = rules.total(cards)
    local natural = #cards == 2 and total >= rules.NATURAL
    c:bigCenter(cx, TOTAL_Y, tostring(total), (natural or lit) and C.gold or C.text, 2)
    if natural then c:text(zone.x + zone.w - 10, NATURAL_Y, "NATURAL", C.gold) end
  end

  local incoming = anim and anim.ev.type == "deal" and anim.ev.who == name and anim.ev or nil
  local xs = slots(zone)
  for slot = 1, 3 do
    if cards[slot] then
      ui.card(c, xs[slot], CARD_Y, cards[slot], false)
      -- White on white runs together, so each card gets an edge
      if cards[slot - 1] then c:rect(xs[slot], CARD_Y + 1, 1, ui.CARD_H - 2, C.mute) end
    elseif not incoming or incoming.slot ~= slot then
      ui.cardSlot(c, xs[slot], CARD_Y, false)
    end
  end
end

--- The card on its way from the shoe goes over everything else.
local function drawIncoming(c, anim)
  if not anim or anim.ev.type ~= "deal" then return end
  local xs = slots(ZONES[anim.ev.who])
  local t = anim.t
  ui.card(c, SHOE_X + math.floor((xs[anim.ev.slot] - SHOE_X) * t), SHOE_Y + math.floor((CARD_Y - SHOE_Y) * t), anim.ev.card, false)
end

local function drawLegend(c, model, state)
  local cx = math.floor(c.w / 2)
  if model.side then
    c:bigCenter(cx, LEGEND_Y, ("%s %s"):format(model.side:upper(), ui.group(state.bet)), C.gold, 1)
  elseif not state.over then
    c:bigCenter(cx, LEGEND_Y, "PICK A SIDE: " .. ui.group(state.bet), C.gold, 1)
  end
  local line = ("Player %d:1   Banker %d:1 less %d%%   Tie %d:1, others push"):format(
    rules.PAYS.player, rules.PAYS.banker, rules.COMMISSION, rules.PAYS.tie)
  c:textCenter(cx, LEGEND_Y + 7, line, C.text)
  if not state.over and state.bet < rules.MIN_BANKER then
    c:textCenter(cx, LEGEND_Y + 9, "Banker needs a bet of " .. rules.MIN_BANKER .. " or more", C.orange)
  end
end

--- Recent coups as a row of pills, newest first. Only what has played: the state holds the road from before this round, and
-- this round joins it when its outcome has shown on the table, however early the books closed.
local function drawRoad(c, model, state)
  if model.ctx.demo then return end
  local road = state.road or ""
  if model.winner then road = rules.addToRoad(road, model.winner) end
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

function M.draw(c, model, state, anim)
  c:clear(C.felt)
  for i = 2, 0, -1 do ui.card(c, SHOE_X + i, SHOE_Y, nil, true) end
  drawLegend(c, model, state)
  drawZone(c, model, state, "player", anim)
  drawZone(c, model, state, "banker", anim)
  drawRoad(c, model, state)
  drawIncoming(c, anim)
  if not state.over then
    ui.button(c, ui.newButtons(), { x = CANCEL.x, y = CANCEL.y, w = CANCEL.w, h = CANCEL.h, label = "NO BET", color = C.panel2 })
  end
end

--- Backing out is a button on the felt, so the three sides keep the bar and their big labels.
function M.regions(_, state)
  if state.over then return {} end
  return { { id = "cancel", x = CANCEL.x, y = CANCEL.y, w = CANCEL.w, h = CANCEL.h } }
end

return M
