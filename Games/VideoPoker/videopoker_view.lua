-- videopoker_view.lua
-- The machine: the paytable across the top, the five cards under it, the hand's name below them.
-- The name sits where the result banner goes, because the banner says the same thing once the hand is over.
-- A card shown is its number, BACK while it is face down, nil before it is dealt.

local poker = require("lib.casino.poker")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("videopoker_rules")

local C = theme.C
local M = {}

local BACK = -1
local PAY_Y = ui.TOP
local PAY_H = 7
local PAY_ROW_H = PAY_H + 1   -- three rows of three pay lines
local PAY_COLUMNS = 3
local PAY_GAP = 3
local PAY_X = 4
local CARDS_Y = 36            -- with the frame round a held card, the last row above the banner is 52
local HELD_Y = 54             -- this, the hint and the name are in the banner's place
local HINT_Y = 60
local NAME_Y = 62
local CARD_GAP = 6

local function lerp(from, to, t)
  return math.floor(from + (to - from) * t + 0.5)
end

function M.new(ctx)
  return { ctx = ctx, shown = {}, final = false, slots = {} }
end

function M.sync(model, state)
  model.shown = {}
  for i, card in ipairs(state.hand) do model.shown[i] = card end
  model.final = state.over
end

function M.event(model, ev)
  if ev.type == "deal" then
    if ev.i == 1 then
      model.shown = {}
      model.final = false
    end
    return 0.25, "deal"
  elseif ev.type == "discard" then
    return 0.25, "flip"
  elseif ev.type == "flip" then
    return 0.3, "flip"
  end
  return 0.35, nil
end

function M.commit(model, ev)
  if ev.type == "deal" or ev.type == "flip" then
    model.shown[ev.i] = ev.card
  elseif ev.type == "final" then
    model.final = true
  end
end

--- Every card face up, so the hand can be named.
local function wholeHand(model)
  local hand = {}
  for i = 1, rules.HAND_SIZE do
    local card = model.shown[i]
    if card == nil or card == BACK then return nil end
    hand[i] = card
  end
  return hand
end

--- One pay line: its name and what the bet returns, beside the multiple in the big font.
local function drawPayCell(c, x, y, w, line, bet, bg, fg, value)
  c:rect(x, y, w, PAY_H, bg)
  c:text(x + 2, y + 2, line.name, fg, bg)
  c:text(x + 2, y + 4, ui.group(bet * line.multiple), value, bg)
  local multiple = tostring(line.multiple)
  c:big(x + w - 2 - c:bigWidth(multiple, 1), y + 1, multiple, value, 1)
end

local function drawPaytable(c, model, tier, bet)
  local w = math.floor((c.w - (PAY_X - 1) * 2 - PAY_GAP * (PAY_COLUMNS - 1)) / PAY_COLUMNS)
  for i, line in ipairs(rules.PAYS) do
    local column = (i - 1) % PAY_COLUMNS
    local row = math.floor((i - 1) / PAY_COLUMNS)
    local x, y = PAY_X + column * (w + PAY_GAP), PAY_Y + row * PAY_ROW_H
    if line.id == tier then
      drawPayCell(c, x, y, w, line, bet, model.final and C.win or C.gold, C.ink, C.ink)
    else
      drawPayCell(c, x, y, w, line, bet, C.feltDark, C.text, C.gold)
    end
  end
end

local function drawName(c, cx, hand)
  local tier = poker.jacksOrBetter(hand)
  local line = tier and rules.line(tier)
  local text = line and line.name:upper() or poker.describe((poker.evaluate(hand))):upper()
  c:bigCenter(cx, NAME_Y, text, line and C.gold or C.text, 1)
end

function M.draw(c, model, state, anim)
  c:clear(C.felt)
  local cx = math.floor(c.w / 2) + 1
  local xs = ui.fan(cx, rules.HAND_SIZE, ui.CARD_W, c.w - 6, CARD_GAP)
  model.slots = xs

  local hand = wholeHand(model)
  local tier = hand and poker.jacksOrBetter(hand) or nil
  local marks = (model.final and tier) and poker.scoring(hand) or nil
  local discarding = anim and anim.ev.type == "discard"
  local flipping = anim and anim.ev.type == "flip" and anim.ev.i or nil
  local dealing = anim and anim.ev.type == "deal" and anim.ev.i or nil
  drawPaytable(c, model, tier, state.bet)

  for i = 1, rules.HAND_SIZE do
    local x = xs[i]
    local card = model.shown[i]
    local held = state.held[i] and not model.final
    if held then
      c:frame(x - 1, CARDS_Y - 1, ui.CARD_W + 2, ui.CARD_H + 2, C.gold)
    elseif marks and marks[i] then
      c:frame(x - 1, CARDS_Y - 1, ui.CARD_W + 2, ui.CARD_H + 2, C.win)
    end
    if flipping == i then
      -- It lifts as it turns over
      local y = CARDS_Y - math.floor(math.sin(anim.t * math.pi) * 3)
      ui.card(c, x, y, anim.t > 0.5 and anim.ev.card or nil, false)
    elseif discarding and not state.held[i] then
      ui.card(c, x, CARDS_Y - math.floor(math.sin(anim.t * math.pi) * 2), anim.t < 0.5 and card or nil, false)
    elseif card == nil or dealing == i then
      ui.cardSlot(c, x, CARDS_Y, false)
    elseif card == BACK then
      ui.card(c, x, CARDS_Y, nil, false)
    else
      ui.card(c, x, CARDS_Y, card, false)
    end
    if held then c:bigCenter(x + math.floor(ui.CARD_W / 2), HELD_Y, "HELD", C.gold, 1) end
  end
  if dealing then
    -- Off the deck at the side of the machine and into its place
    local x, y = lerp(c.w - ui.CARD_W, xs[dealing], anim.t), lerp(PAY_Y, CARDS_Y, anim.t)
    ui.card(c, x, y, anim.t > 0.6 and anim.ev.card or nil, false)
  end

  if hand and not model.final then
    c:textCenter(cx, HINT_Y, "Tap the cards you want to keep, then DRAW", C.text)
    drawName(c, cx, hand)
  end
end

--- The cards themselves are the hold buttons.
function M.regions(model, state)
  local list = {}
  if state.over then return list end
  for i, x in ipairs(model.slots) do
    list[i] = { id = "hold" .. i, x = x, y = CARDS_Y, w = ui.CARD_W, h = ui.CARD_H }
  end
  return list
end

return M
