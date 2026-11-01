-- holdem_view.lua
-- The table: five shared cards across the top, the dealer's two on the left, yours on the right, your bets between.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("holdem_rules")

local C = theme.C
local M = {}

local BOARD_Y = ui.TOP + 1    -- a row over it for the frame round a winning card
local BOARD_GAP = 5
local NAME_Y = 30
local LABEL_Y = 36
local HOLE_Y = 39             -- small cards, so the hands, the bets and all they say stay above the banner
local DEALER_X = 4
local CARD_GAP = 3            -- so the frames round two winning cards do not meet
local SPOT_W, SPOT_H = 21, 7
local SPOT_Y = 37
local SPOT_STEP = 8           -- from one row of bets to the next, ending clear of the line a badge takes over the banner
local STAGE_Y = 56            -- this and the pay lines are in the banner's place, so the result covers them
local HINT_Y = 63

local STAGES = { preflop = "PRE-FLOP", flop = "THE FLOP", river = "THE RIVER" }
local RANK_LETTERS = {
  [11] = "J", [12] = "Q", [13] = "K", [14] = "A",
}

local function lerp(from, to, t)
  return math.floor(from + (to - from) * t + 0.5)
end

function M.new(ctx)
  return { ctx = ctx, player = {}, dealer = {}, board = {}, faces = {}, final = false, folded = false, play = 0 }
end

function M.sync(model, state)
  model.player, model.dealer, model.board, model.faces = {}, {}, {}, {}
  for i, card in ipairs(state.player) do model.player[i] = card end
  for i = 1, rules.HOLE_SIZE do model.dealer[i] = true end
  for i = 1, state.shown do model.board[i] = state.board[i] end
  if state.over then
    for i, card in ipairs(state.dealer) do model.faces[i] = card end
  end
  model.final = state.over
  model.folded = state.folded
  model.play = state.play
end

function M.event(model, ev)
  if ev.type == "deal" then
    if ev.who == "player" and ev.i == 1 then
      model.player, model.dealer, model.board, model.faces = {}, {}, {}, {}
      model.final, model.folded, model.play = false, false, 0
    end
    return 0.25, "deal"
  elseif ev.type == "bet" then
    return 0.3, "chipBig"
  elseif ev.type == "fold" then
    return 0.3, "tap"
  elseif ev.type == "board" then
    return 0.3, "flip"
  elseif ev.type == "reveal" then
    return 0.35, "flip"
  end
  return 0.35, nil
end

function M.commit(model, ev)
  if ev.type == "deal" then
    if ev.who == "player" then model.player[ev.i] = ev.card else model.dealer[ev.i] = true end
  elseif ev.type == "bet" then
    model.play = ev.amount
  elseif ev.type == "fold" then
    model.folded = true
  elseif ev.type == "board" then
    model.board[ev.i] = ev.card
  elseif ev.type == "reveal" then
    model.faces[ev.i] = ev.card
  elseif ev.type == "final" then
    model.final = true
  end
end

--- A hand's cards in view: hole cards and whatever of the board is up.
local function inView(hole, board)
  local cards = {}
  for i = 1, rules.HOLE_SIZE do
    if hole[i] == nil then return nil end
    cards[i] = hole[i]
  end
  for i = 1, rules.BOARD_SIZE do
    if board[i] ~= nil then cards[#cards + 1] = board[i] end
  end
  return cards
end

--- The short form a player would say aloud, for when two long names would meet on their row.
local function shortName(value)
  local category = poker.category(value)
  local rank = poker.topRank(value)
  if category == poker.PAIR then
    return "PAIR OF " .. (RANK_LETTERS[rank] or tostring(rank)) .. "S"
  elseif category == poker.TRIPS then
    return "TRIPS"
  elseif category == poker.QUADS then
    return "QUADS"
  elseif category == poker.STRAIGHT_FLUSH then
    return "STR FLUSH"
  end
  return poker.describe(value):upper()
end

--- What two hole cards are before the flop: the name in full, then short.
local function holeName(cards)
  local a, b = deck.rank(cards[1]), deck.rank(cards[2])
  if a == b then
    return "PAIR OF " .. poker.rankPlural(a):upper(), "PAIR OF " .. (RANK_LETTERS[a] or tostring(a)) .. "S"
  end
  local high = poker.rankWord(math.max(a, b)):upper() .. " HIGH"
  return high, high
end

--- A hand's name in full and short, or nil before its cards are known.
local function handName(cards)
  if not cards then return nil, nil end
  if #cards < 5 then return holeName(cards) end
  local value = poker.evaluate(cards)
  return poker.describe(value):upper(), shortName(value)
end

--- Whether each of these cards is in the best five of a whole hand.
local function usedBy(cards)
  local used = {}
  if not cards or #cards < 5 then return used end
  for _, card in ipairs(poker.bestFive(cards)) do used[card] = true end
  return used
end

local function drawBoard(c, model, anim, used, xs)
  local turning = anim and anim.ev.type == "board" and anim.ev.i or nil
  for i = 1, rules.BOARD_SIZE do
    local x = xs[i]
    local card = model.board[i]
    if turning == i then
      local y = BOARD_Y + 2 - math.floor(math.sin(anim.t * math.pi) * 2)
      ui.card(c, x, y, anim.t > 0.5 and anim.ev.card or nil, false)
    elseif card then
      if used[card] then c:frame(x - 1, BOARD_Y - 1, ui.CARD_W + 2, ui.CARD_H + 2, C.win) end
      ui.card(c, x, BOARD_Y, card, false)
    else
      ui.card(c, x, BOARD_Y, nil, false)
    end
  end
end

local function holeXs(left)
  return { left, left + ui.SMALL_W + CARD_GAP }
end

--- A betting spot: its name, the stake on it, and how it came out.
local function drawSpot(c, x, y, label, amount, result)
  local active = amount > 0
  c:rect(x, y, SPOT_W, SPOT_H, active and C.feltDark or C.felt)
  c:frame(x, y, SPOT_W, SPOT_H, active and C.feltLight or C.feltDark)
  c:text(x + 3, y + 2, label, active and C.gold or C.mute)
  if amount > 0 then
    local stake = ui.group(amount)
    c:text(x + SPOT_W - 3 - #stake, y + 2, stake, C.text)
  end
  if result and result ~= 0 then
    local text = ui.signed(result)
    c:text(x + SPOT_W - 3 - #text, y + 4, text, result > 0 and C.win or C.orange)
  elseif result == 0 and amount > 0 then
    c:text(x + SPOT_W - 7, y + 4, "push", C.mute)
  end
end

local function payLine(title, paytable, short)
  local parts = {}
  for _, line in ipairs(paytable) do
    parts[#parts + 1] = (short[line.id] or line.name) .. " " .. (line.text or line.pays)
  end
  return title .. "  " .. table.concat(parts, "  ")
end

local SHORT = {
  royal = "Royal", straightFlush = "Str Flush", quads = "Quads", fullHouse = "Full House",
  straight = "Straight", trips = "Trips", flush = "Flush",
}

function M.draw(c, model, state, anim)
  c:clear(C.felt)
  local cx = math.floor(c.w / 2) + 1
  local boardXs = ui.fan(cx, rules.BOARD_SIZE, ui.CARD_W, c.w - 10, BOARD_GAP)
  local dealing = anim and anim.ev.type == "deal" and anim.ev or nil
  local turning = anim and anim.ev.type == "reveal" and anim.ev.i or nil

  local mine = inView(model.player, model.board)
  local theirs = #model.faces == rules.HOLE_SIZE and inView(model.faces, model.board) or nil
  local used = model.final and not model.folded and usedBy(mine) or {}
  drawBoard(c, model, anim, used, boardXs)

  -- Dealer, left
  local dealerXs = holeXs(DEALER_X)
  local dealerLong, dealerShort = handName(theirs)
  local myLong, myShort = handName(mine)
  local dealerName, myName = dealerLong or "DEALER", myLong or "YOU"
  if c:bigWidth(dealerName, 1) + c:bigWidth(myName, 1) > c.w - 10 then
    dealerName, myName = dealerShort or dealerName, myShort or myName
  end
  c:big(DEALER_X, NAME_Y, dealerName, dealerLong and C.text or C.mute, 1)
  c:text(DEALER_X, LABEL_Y, theirs and "Dealer" or "Needs a pair or better", C.mute)
  for i = 1, rules.HOLE_SIZE do
    local x = dealerXs[i]
    if turning == i then
      local y = HOLE_Y - math.floor(math.sin(anim.t * math.pi) * 3)
      ui.card(c, x, y, anim.t > 0.5 and anim.ev.card or nil, true)
    elseif model.faces[i] then
      ui.card(c, x, HOLE_Y, model.faces[i], true)
    elseif model.dealer[i] and not (dealing and dealing.who == "dealer" and dealing.i == i) then
      ui.card(c, x, HOLE_Y, nil, true)
    else
      ui.cardSlot(c, x, HOLE_Y, true)
    end
  end

  -- You, right
  local playerLeft = c.w - 2 - (ui.SMALL_W * 2 + CARD_GAP)
  local playerXs = holeXs(playerLeft)
  local right = playerLeft + ui.SMALL_W * 2 + CARD_GAP
  c:big(right - c:bigWidth(myName, 1), NAME_Y, myName, model.folded and C.mute or (mine and C.gold or C.mute), 1)
  local label = model.folded and "Folded" or "Your hand"
  c:text(right - #label, LABEL_Y, label, C.mute)
  for i = 1, rules.HOLE_SIZE do
    local x = playerXs[i]
    if model.player[i] and not (dealing and dealing.who == "player" and dealing.i == i) then
      if used[model.player[i]] then c:frame(x - 1, HOLE_Y - 1, ui.SMALL_W + 2, ui.SMALL_H + 2, C.win) end
      ui.card(c, x, HOLE_Y, model.player[i], true)
    else
      ui.cardSlot(c, x, HOLE_Y, true)
    end
  end

  if dealing then
    local who = dealing.who == "player"
    local tx = who and playerXs[dealing.i] or dealerXs[dealing.i]
    ui.card(c, lerp(cx - 6, tx, anim.t), lerp(BOARD_Y, HOLE_Y, anim.t), (who and anim.t > 0.6) and dealing.card or nil, true)
  end

  -- The bets, between the hands
  local spotLeft = cx - SPOT_W - 2
  local spotRight = cx + 3
  local outcome = model.final and state.outcome or {}
  drawSpot(c, spotLeft, SPOT_Y, "ANTE", state.ante, outcome.ante)
  drawSpot(c, spotRight, SPOT_Y, "BLIND", state.blind, outcome.blind)
  drawSpot(c, spotLeft, SPOT_Y + SPOT_STEP, "PLAY", model.play, model.play > 0 and outcome.play or nil)
  drawSpot(c, spotRight, SPOT_Y + SPOT_STEP, "TRIPS", state.side, outcome.side)

  if not model.final and not anim then
    c:bigCenter(cx, STAGE_Y, STAGES[state.stage] or "", C.text, 1)
  end
  if not model.final then
    c:textCenter(cx, HINT_Y, payLine("BLIND", rules.BLIND, SHORT), C.text)
    if state.side > 0 then c:textCenter(cx, HINT_Y + 2, payLine("TRIPS", rules.TRIPS, SHORT), C.text) end
  end
end

return M
