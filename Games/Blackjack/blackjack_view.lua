-- blackjack_view.lua
-- Blackjack's table: the dealer above, the player below, the shoe in the corner. The hands and totals sit above
-- ui.BANNER_Y, where the engine's result banner goes, so the final hands stay in view over it. Only the printed legend
-- is under the banner.
-- Only the model is drawn: the hole card is in the state from the start, and the model never holds it until the reveal.

local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("blackjack_rules")

local C = theme.C
local M = {}

local CX = 64                 -- the middle of the cards, between the side columns
local FAN_W = 66              -- how wide a hand may fan out
local LEFT_CX = 16            -- the column for totals
local RIGHT_CX = 109          -- the column for the shoe and the bet
local DEALER_Y = ui.TOP + 1
local PLAYER_Y = 33
local SHOE_X, SHOE_Y = 100, DEALER_Y
local LEGEND_Y = 56
-- A split has the rows between the dealer and the banner to share, so its two hands go down to small cards
local SPLIT_TOP, SPLIT_H = 30, 23  -- the two hand panels
local SPLIT_TOTAL_Y = 32
local SPLIT_CARD_Y = 38
local PANELS = { { x = 4, w = 56 }, { x = 63, w = 56 } }

local function copy(list)
  local out = {}
  for i, value in ipairs(list) do out[i] = value end
  return out
end

function M.new(ctx)
  return { ctx = ctx, dealer = {}, hands = { { cards = {}, bet = 0 } }, active = 1, down = false }
end

--- A round picked up after a reboot: show it as the player left it, hole card still down.
function M.sync(model, state)
  model.hands = {}
  for i, hand in ipairs(state.hands) do
    model.hands[i] = { cards = copy(hand.cards), bet = hand.bet, doubled = hand.doubled, split = hand.split }
  end
  model.active = state.active
  model.dealer = { state.dealer[1], false }
  model.down = true
end

local DURATIONS = {
  start = { 0.01 }, deal = { 0.3, "deal" }, peek = { 0.4 }, reveal = { 0.4, "flip" },
  split = { 0.3, "chip" }, double = { 0.3, "chipBig" }, turn = { 0.2, "tap" }, outcome = { 0.3, "chip" },
}

function M.event(model, ev)
  if ev.type == "start" then
    model.dealer, model.down, model.active = {}, true, 1
    model.hands = { { cards = {}, bet = model.hands[1].bet } }
    model.outcomes = nil
    if ev.fresh then return 0.6, "flip" end
  end
  local timing = DURATIONS[ev.type] or { 0.2 }
  return timing[1], timing[2]
end

function M.commit(model, ev)
  if ev.type == "deal" then
    if ev.who == "dealer" then
      if ev.hole then
        model.dealer[#model.dealer + 1] = false
      else
        model.dealer[#model.dealer + 1] = ev.card
      end
    else
      local hand = model.hands[ev.hand]
      hand.cards[#hand.cards + 1] = ev.card
    end
  elseif ev.type == "reveal" then
    model.dealer[2] = ev.card
    model.down = false
  elseif ev.type == "split" then
    local first = model.hands[1]
    first.split = true
    model.hands[2] = { cards = { table.remove(first.cards) }, bet = first.bet, split = true }
  elseif ev.type == "double" then
    local hand = model.hands[ev.hand]
    hand.bet, hand.doubled = ev.bet, true
  elseif ev.type == "turn" then
    model.active = ev.hand
  elseif ev.type == "outcome" then
    model.outcomes = ev.hands
  end
end

local function faceUp(cards)
  local out = {}
  for _, card in ipairs(cards) do
    if card then out[#out + 1] = card end
  end
  return out
end

local function totalColor(total)
  if total > 21 then return C.red end
  if total == 21 then return C.gold end
  return C.text
end

--- The word beside a total: only what the number alone does not say.
local function totalTag(hand)
  local total, soft = rules.total(hand.cards)
  if total > 21 then return "BUST", C.red end
  if rules.isNaturalHand(hand) then return "BLACKJACK", C.gold end
  if soft and total < 21 then return "soft", C.text end
  return nil
end

--- A total, big, under its label and its word.
local function drawTotal(c, cx, y, label, cards, tag, tagColor)
  c:textCenter(cx, y, label, C.text)
  if #cards == 0 then return end
  local total = rules.total(cards)
  if tag then c:textCenter(cx, y + 2, tag, tagColor) end
  c:bigCenter(cx, y + 4, tostring(total), totalColor(total), 2)
end

local function dealerSpot(n)
  return ui.fan(CX, n, ui.CARD_W, FAN_W, 2), DEALER_Y
end

--- Where a hand's cards go, and whether they are the small ones.
local function playerSpot(model, index, n)
  if #model.hands > 1 then
    local panel = PANELS[index]
    return ui.fan(panel.x + math.floor(panel.w / 2), n, ui.SMALL_W, panel.w - 6, 1), SPLIT_CARD_Y, true
  end
  return ui.fan(CX, n, ui.CARD_W, FAN_W, 2), PLAYER_Y, false
end

local function flying(anim, who, index)
  if not anim or anim.ev.type ~= "deal" or anim.ev.who ~= who then return nil end
  if who == "player" and anim.ev.hand ~= index then return nil end
  return anim.ev
end

--- A row of cards, with room kept for the one on its way in, which lands from the shoe.
local function drawCards(c, cards, spot, incoming, anim)
  local xs, y, small = spot(#cards + (incoming and 1 or 0))
  local w, h = small and ui.SMALL_W or ui.CARD_W, small and ui.SMALL_H or ui.CARD_H
  for i, card in ipairs(cards) do
    ui.card(c, xs[i], y, card or nil, small)
    -- White on white runs together when a fan overlaps, so each card gets an edge
    if i > 1 and xs[i] - xs[i - 1] < w then c:rect(xs[i], y + 1, 1, h - 2, C.mute) end
  end
  if incoming then
    local x, t = xs[#xs], anim.t
    ui.card(c, SHOE_X + math.floor((x - SHOE_X) * t), SHOE_Y + math.floor((y - SHOE_Y) * t), incoming.card, small)
  end
end

local function drawDealer(c, model, anim)
  local shown = faceUp(model.dealer)
  local tag, color = nil, C.text
  if not model.down then
    local total = rules.total(shown)
    if total > 21 then
      tag, color = "BUST", C.red
    elseif #shown == 2 and total == 21 then
      tag, color = "BLACKJACK", C.gold
    end
  end
  drawTotal(c, LEFT_CX, DEALER_Y, "DEALER", shown, tag, color)

  local cards = copy(model.dealer)
  local lifted = nil
  if anim and anim.ev.type == "reveal" then
    if anim.t > 0.5 then cards[2] = anim.ev.card end
    lifted = math.floor(math.sin(anim.t * math.pi) * 3)
  elseif anim and anim.ev.type == "peek" then
    lifted = math.floor(math.sin(anim.t * math.pi) * 2)
  end
  drawCards(c, cards, dealerSpot, flying(anim, "dealer"), anim)
  if lifted and lifted > 0 then
    local xs, y = dealerSpot(#cards)
    c:rect(xs[2], y + ui.CARD_H - lifted, ui.CARD_W, lifted + 1, C.felt)
    ui.card(c, xs[2], y - lifted, cards[2] or nil, false)
  end
end

local OUTCOME = {
  blackjack = { "BLACKJACK", "win" }, win = { "WIN", "win" }, push = { "PUSH", "gold" },
  lose = { "LOSE", "red" }, bust = { "BUST", "red" },
}

local function drawSplitHand(c, model, index, anim)
  local hand, panel = model.hands[index], PANELS[index]
  local playing = index == model.active and not model.outcomes
  c:rect(panel.x + 1, SPLIT_TOP + 1, panel.w - 2, SPLIT_H - 2, playing and C.feltDark or C.felt)
  c:frame(panel.x, SPLIT_TOP, panel.w, SPLIT_H, playing and C.gold or C.feltLight)

  local total = rules.total(hand.cards)
  c:big(panel.x + 3, SPLIT_TOTAL_Y, total, totalColor(total), 1)
  local right = panel.x + panel.w - 4
  local title = "HAND " .. index
  c:text(right - #title + 1, SPLIT_TOTAL_Y, title, playing and C.gold or C.text)
  local bet = "Bet " .. ui.group(hand.bet)
  c:text(right - #bet + 1, SPLIT_TOTAL_Y + 2, bet, C.gold)

  local outcome = model.outcomes and model.outcomes[index]
  if outcome then
    local look = OUTCOME[outcome.result]
    local word = look[1]
    if outcome.net ~= 0 then word = word .. " " .. ui.signed(outcome.net) end
    c:text(right - #word + 1, SPLIT_TOTAL_Y + 4, word, C[look[2]])
  else
    local tag, color = totalTag(hand)
    if tag then c:text(right - #tag + 1, SPLIT_TOTAL_Y + 4, tag, color) end
  end

  drawCards(c, hand.cards, function(n) return playerSpot(model, index, n) end, flying(anim, "player", index), anim)
end

local function drawSingleHand(c, model, anim)
  local hand = model.hands[1]
  local label = model.ctx.seat or "YOU"
  if #label > 22 then label = label:sub(1, 22) end
  local tag, color = totalTag(hand)
  drawTotal(c, LEFT_CX, PLAYER_Y, label, hand.cards, tag, color)
  drawCards(c, hand.cards, function(n) return playerSpot(model, 1, n) end, flying(anim, "player", 1), anim)

  c:textCenter(RIGHT_CX, PLAYER_Y + 4, hand.doubled and "DOUBLED" or "BET", C.text)
  c:bigCenter(RIGHT_CX, PLAYER_Y + 6, ui.group(hand.bet), C.gold, 1)
end

local function drawShoe(c, left)
  for i = 3, 0, -1 do ui.card(c, SHOE_X + i * 2, SHOE_Y, nil, true) end
  c:textCenter(RIGHT_CX, SHOE_Y + ui.SMALL_H + 2, left .. " cards", C.text)
end

--- The rules are printed on the felt, as on a real table, and come from the rules module.
local function drawLegend(c, model, state)
  local cx = math.floor(c.w / 2)
  c:bigCenter(cx, LEGEND_Y, ("BLACKJACK PAYS %d TO %d"):format(rules.NATURAL_PAYS[1], rules.NATURAL_PAYS[2]), C.feltLight, 1)
  c:textCenter(cx, LEGEND_Y + 7, ("Dealer hits soft %d. Double on hard %d."):format(rules.DEALER_HITS_SOFT, rules.DOUBLE_ON), C.text)
  if state.hold and not state.over then
    local mine = rules.isNaturalHand(model.hands[1])
    c:textCenter(CX, PLAYER_Y + ui.CARD_H + 3, mine and "Blackjack! Turn over the hole card." or "The dealer has looked at the hole card.", C.gold)
  end
end

function M.draw(c, model, state, anim)
  c:clear(C.felt)
  drawShoe(c, state.left or #state.cards)
  drawLegend(c, model, state)
  drawDealer(c, model, anim)
  if #model.hands > 1 then
    drawSplitHand(c, model, 1, anim)
    drawSplitHand(c, model, 2, anim)
  else
    drawSingleHand(c, model, anim)
  end
  if anim and anim.ev.type == "start" and anim.ev.fresh then
    c:textCenter(RIGHT_CX, SHOE_Y + ui.SMALL_H + 4, "New shoe", C.gold)
  end
end

return M
