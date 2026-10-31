-- threecard_view.lua
-- The table: the dealer's three cards above yours, what the bets pay down the left, your bets down the right.

local poker = require("lib.casino.poker")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("threecard_rules")

local C = theme.C
local M = {}

local SIDE_W = 24             -- the panels either side of the cards
local DEALER_NAME_Y = 9
local DEALER_Y = 16
local PLAYER_NAME_Y = 33
local PLAYER_Y = 39
local CARD_GAP = 2
local SPOT_H = 10

local function lerp(from, to, t)
  return math.floor(from + (to - from) * t + 0.5)
end

function M.new(ctx)
  return { ctx = ctx, player = {}, dealer = {}, faces = {}, final = false, folded = false, playing = false }
end

function M.sync(model, state)
  model.player, model.dealer, model.faces = {}, {}, {}
  for i, card in ipairs(state.player) do model.player[i] = card end
  for i = 1, rules.HAND_SIZE do model.dealer[i] = true end
  if state.over then
    for i, card in ipairs(state.dealer) do model.faces[i] = card end
  end
  model.final = state.over
  model.folded = state.folded
  model.playing = state.played == true
end

function M.event(model, ev)
  if ev.type == "deal" then
    if ev.who == "player" and ev.i == 1 then
      model.player, model.dealer, model.faces = {}, {}, {}
      model.final, model.folded, model.playing = false, false, false
    end
    return 0.25, "deal"
  elseif ev.type == "bet" then
    return 0.3, "chipBig"
  elseif ev.type == "fold" then
    return 0.3, "tap"
  elseif ev.type == "reveal" then
    return 0.35, "flip"
  end
  return 0.35, nil
end

function M.commit(model, ev)
  if ev.type == "deal" then
    if ev.who == "player" then model.player[ev.i] = ev.card else model.dealer[ev.i] = true end
  elseif ev.type == "bet" then
    model.playing = true
  elseif ev.type == "fold" then
    model.folded = true
  elseif ev.type == "reveal" then
    model.faces[ev.i] = ev.card
  elseif ev.type == "final" then
    model.final = true
  end
end

local function complete(hand)
  return hand[1] ~= nil and hand[2] ~= nil and hand[3] ~= nil
end

local function bigName(c, cx, y, text, color)
  c:bigCenter(cx, y, text, color, 1)
end

--- One paytable. lit is the category of the hand in front of you.
local function drawPays(c, x, y, title, paytable, category, on)
  c:text(x + 2, y, title, on and C.gold or C.mute)
  y = y + 1
  for _, line in ipairs(paytable) do
    y = y + 1
    local pays = tostring(line.pays)
    local lit = on and category and rules.pays(paytable, category) == line.pays
    local bg = lit and C.gold or C.feltDark
    local fg = lit and C.ink or (on and C.text or C.mute)
    c:rect(x + 1, y, SIDE_W - 2, 1, bg)
    c:text(x + 2, y, line.name, fg, bg)
    c:text(x + SIDE_W - 2 - #pays, y, pays, fg, bg)
    y = y + 1
  end
  return y
end

--- A betting spot: its name, the stake on it, and how it came out.
local function drawSpot(c, x, y, label, amount, result)
  local active = amount > 0 or (result and result ~= 0)
  c:rect(x, y, SIDE_W, SPOT_H, active and C.feltDark or C.felt)
  c:frame(x, y, SIDE_W, SPOT_H, active and C.feltLight or C.feltDark)
  c:text(x + 2, y + 1, label, active and C.gold or C.mute)
  if amount > 0 then c:big(x + 2, y + 3, ui.group(amount), C.text, 1) end
  if result and result ~= 0 then
    local text = ui.signed(result)
    c:text(x + SIDE_W - 2 - #text, y + 1, text, result > 0 and C.win or C.orange)
  end
end

function M.draw(c, model, state, anim)
  c:clear(C.felt)
  local cx = math.floor(c.w / 2) + 1
  local xs = ui.fan(cx, rules.HAND_SIZE, ui.CARD_W, c.w, CARD_GAP)
  local dealing = anim and anim.ev.type == "deal" and anim.ev or nil
  local turning = anim and anim.ev.type == "reveal" and anim.ev.i or nil

  -- Dealer
  local dealerHand = complete(model.faces) and poker.three(model.faces) or nil
  if dealerHand then
    bigName(c, cx, DEALER_NAME_Y, poker.describeThree(dealerHand):upper(), C.text)
    local passes = not rules.qualifies(dealerHand)
    c:textCenter(cx, DEALER_Y - 1, passes and "The dealer does not qualify" or "The dealer qualifies",
      passes and C.gold or C.text)
  else
    bigName(c, cx, DEALER_NAME_Y, "DEALER", C.mute)
    c:textCenter(cx, DEALER_Y - 1, "Needs Queen high or better", C.mute)
  end
  for i = 1, rules.HAND_SIZE do
    local x = xs[i]
    if turning == i then
      local y = DEALER_Y - math.floor(math.sin(anim.t * math.pi) * 3)
      ui.card(c, x, y, anim.t > 0.5 and anim.ev.card or nil, false)
    elseif model.faces[i] then
      ui.card(c, x, DEALER_Y, model.faces[i], false)
    elseif model.dealer[i] and not (dealing and dealing.who == "dealer" and dealing.i == i) then
      ui.card(c, x, DEALER_Y, nil, false)
    else
      ui.cardSlot(c, x, DEALER_Y, false)
    end
  end

  -- Player
  local playerHand, category = nil, nil
  if complete(model.player) then playerHand, category = poker.three(model.player) end
  if playerHand then
    bigName(c, cx, PLAYER_NAME_Y, poker.describeThree(playerHand):upper(), model.folded and C.mute or C.gold)
    c:textCenter(cx, PLAYER_Y - 1, model.folded and "Folded" or "Your hand", C.text)
  else
    bigName(c, cx, PLAYER_NAME_Y, "YOU", C.mute)
  end
  for i = 1, rules.HAND_SIZE do
    local x = xs[i]
    if model.player[i] and not (dealing and dealing.who == "player" and dealing.i == i) then
      ui.card(c, x, PLAYER_Y, model.player[i], false)
    else
      ui.cardSlot(c, x, PLAYER_Y, false)
    end
  end

  if dealing then
    -- From the deck at the top of the table to its place
    local who = dealing.who == "player"
    local x, y = lerp(c.w - SIDE_W - ui.CARD_W, xs[dealing.i], anim.t), lerp(0, who and PLAYER_Y or DEALER_Y, anim.t)
    ui.card(c, x, y, (who and anim.t > 0.6) and dealing.card or nil, false)
  end

  -- What pays, left
  c:rect(2, DEALER_NAME_Y, SIDE_W, 46, C.feltDark)
  local y = drawPays(c, 2, DEALER_NAME_Y + 1, "PAIR PLUS", rules.PAIR_PLUS, category, state.side > 0)
  drawPays(c, 2, y + 2, "ANTE BONUS", rules.ANTE_BONUS, category, not model.folded)

  -- The bets, right
  local x = c.w - SIDE_W - 1
  local outcome = model.final and state.outcome or {}
  drawSpot(c, x, DEALER_NAME_Y, "ANTE", state.ante, outcome.ante)
  drawSpot(c, x, DEALER_NAME_Y + 12, "PLAY", model.playing and state.ante or 0, outcome.play)
  drawSpot(c, x, DEALER_NAME_Y + 24, "BONUS", 0, outcome.bonus)
  drawSpot(c, x, DEALER_NAME_Y + 36, "PAIR PLUS", state.side, outcome.side)
end

return M
