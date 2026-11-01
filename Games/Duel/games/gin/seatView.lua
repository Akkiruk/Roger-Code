-- games/gin/seatView.lua
-- A player's wall, 121x81. On top the other player's card count, the stock and the discard. Below it this player's hand, sorted into
-- melds with the deadwood last, one row of thin cards so that 11 fit with room between melds. A wall with no viewer has no view.hand
-- and shows backs. Once a knock is down both hands are shown, with what was laid off.

local deck = require("lib.casino.deck")
local melds = require("games.gin.melds")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local W = 121
local THIN_W, THIN_H = 9, 14        -- one card of a hand. Cells are tall, so a thin card still has room for a rank over a suit
local STEP, GROUP_GAP = 10, 3       -- card to card, and a little more between melds
local PILES_Y = 13                  -- the stock and the discard
local STOCK_X, PILE_X = 46, 68
local PROMPT_Y = 35                 -- what to do now, between the piles and the hand
local HAND_Y = 43                   -- the row of cards on a player's turn, with room above for a picked card to rise
local METER_Y = 61                  -- ends one row above the engine's note
local END_TOP, END_BOTTOM = 13, 33  -- the two rows of a finished hand. Both end above the result banner

local function thin(c, x, y, card)
  c:rect(x + 1, y, THIN_W - 2, THIN_H, C.card)
  c:rect(x, y + 1, THIN_W, THIN_H - 2, C.card)
  local color = deck.isRed(card) and C.red or C.ink
  local name = deck.rankName(card)
  c:bigCenter(x + 5, y + 1, name, color, 1)
  ui.suit(c, x + 1, y + 7, deck.suit(card), color, 1)
end

local function thinBack(c, x, y)
  c:rect(x + 1, y, THIN_W - 2, THIN_H, C.card)
  c:rect(x, y + 1, THIN_W, THIN_H - 2, C.card)
  c:rect(x + 1, y + 1, THIN_W - 2, THIN_H - 2, C.accent)
end

--- Lay groups of cards along a row, centred. Returns the groups with each card's x: { label, color, x, w, cards = { { card, x } } }.
local function layout(groups)
  local count, shown = 0, 0
  for _, group in ipairs(groups) do
    if #group.cards > 0 then
      count = count + #group.cards
      shown = shown + 1
    end
  end
  local width = count * STEP - 1 + math.max(0, shown - 1) * GROUP_GAP
  local x = math.floor((W - width) / 2) + 1
  local placed = {}
  for _, group in ipairs(groups) do
    if #group.cards > 0 then
      local item = { label = group.label, color = group.color, x = x, cards = {} }
      for index, card in ipairs(group.cards) do
        item.cards[index] = { card = card, x = x }
        x = x + STEP
      end
      item.w = x - item.x - 1
      x = x + GROUP_GAP
      placed[#placed + 1] = item
    end
  end
  return placed
end

local function kindOf(meld)
  return melds.low(meld[1]) == melds.low(meld[#meld]) and "SET" or "RUN"
end

--- The groups of a hand: its melds, then anything laid off, then the deadwood.
local function groupsOf(hand)
  local groups = {}
  for _, meld in ipairs(hand.melds) do
    groups[#groups + 1] = { label = kindOf(meld), color = C.gold, cards = meld }
  end
  if hand.laid and #hand.laid > 0 then groups[#groups + 1] = { label = "LAID OFF", color = C.win, cards = hand.laid } end
  if #hand.loose > 0 then groups[#groups + 1] = { label = "LOOSE", color = C.orange, cards = hand.loose } end
  return groups
end

local function drawRow(c, placed, y, picked, fresh)
  for _, group in ipairs(placed) do
    for _, item in ipairs(group.cards) do
      local rise = item.card == picked and 2 or 0
      thin(c, item.x, y - rise, item.card)
      if rise > 0 then c:frame(item.x, y - rise, THIN_W, THIN_H + rise, C.gold) end
      if item.card == fresh then c:textCenter(item.x + 5, y - rise - 1, "NEW", C.gold) end
    end
    c:rect(group.x, y + THIN_H + 1, group.w, 1, group.color)
    if group.label and #group.label <= group.w then c:textCenter(group.x + math.floor(group.w / 2), y + THIN_H + 2, group.label, group.color) end
  end
end

local function nameOf(view, seat)
  for _, player in ipairs(view.players) do
    if player.seat == seat then return player.name end
  end
  return "?"
end

--- Me and them, for a wall. A wall with nobody at it takes the first player as its own bottom row.
local function sides(view, info)
  local list = view.players
  local mine = (info and info.seat == list[2].seat) and list[2] or list[1]
  return mine, mine == list[1] and list[2] or list[1]
end

local function lastMove(view)
  local last = view.last
  if not last then return nil end
  local name = nameOf(view, last.seat)
  if last.what == "stock" then return name .. " drew from the stock" end
  if last.what == "take" then return name .. " took the " .. deck.name(last.card) end
  return name .. " threw the " .. deck.name(last.card)
end

local function topRow(c, view, them)
  c:text(4, PILES_Y - 1, tostring(them.name):sub(1, 18), C.text)
  c:big(4, PILES_Y + 1, them.count .. " CARDS", C.gold, 1)
  local xs = ui.fan(24, math.max(1, them.count), ui.SMALL_W, 40, 0)
  for index = 1, them.count do ui.card(c, xs[index], PILES_Y + 8, nil, true) end

  c:textCenter(STOCK_X + 8, PILES_Y - 1, "STOCK", C.text)
  ui.card(c, STOCK_X, PILES_Y, nil)
  c:textCenter(STOCK_X + 8, PILES_Y + ui.CARD_H + 1, view.stock .. " left", C.mute)
  c:textCenter(PILE_X + 8, PILES_Y - 1, "DISCARD", C.text)
  ui.card(c, PILE_X, PILES_Y, view.top)

  c:text(90, PILES_Y - 1, ui.group(view.stake) .. " a point", C.gold)
  c:text(90, PILES_Y + 1, "Most a hand", C.mute)
  c:text(90, PILES_Y + 2, "can move: " .. ui.group(view.cap), C.mute)
  c:text(90, PILES_Y + 4, "Knock at " .. view.knockAt, C.mute)
  c:text(90, PILES_Y + 5, "Gin pays 25", C.mute)
  local move = lastMove(view)
  if move then
    for index, line in ipairs(ui.wrap(move, 29)) do c:text(90, PILES_Y + 7 + index, line, C.text) end
  end
end

local function prompt(view, mine, them)
  -- A wall with no viewer has no "you": it may be anyone standing there
  if not view.hand then return tostring(nameOf(view, view.turn)):upper():sub(1, 12) .. " TO PLAY" end
  if view.turn ~= mine.seat then return "WAITING FOR " .. tostring(them.name):upper():sub(1, 12) end
  if view.phase == "draw" then return "YOUR TURN: DRAW" end
  return "PICK A CARD TO THROW"
end

--- How far the hand is from a knock.
local function meter(c, deadwood)
  local good = deadwood <= 10
  c:big(4, METER_Y, "DEADWOOD " .. deadwood, good and C.win or C.text, 1)
  local x, w = 66, 52
  local fill = math.min(w, math.floor(w * deadwood / 40 + 0.5))
  local mark = x + math.floor(w * 10 / 40)
  c:rect(x, METER_Y + 1, w, 3, C.feltDark)
  if fill > 0 then c:rect(x, METER_Y + 1, fill, 3, good and C.win or C.orange) end
  c:rect(mark, METER_Y, 1, 5, C.gold)
  c:text(mark + 2, METER_Y + 5, "Knock at 10", C.gold)
end

local function playing(c, view, info)
  local mine, them = sides(view, info)
  topRow(c, view, them)
  c:bigCenter(61, PROMPT_Y, prompt(view, mine, them), (view.hand and view.turn == mine.seat) and C.gold or C.mute, 1)
  local hand = view.hand
  if not hand then
    local groups = {}
    for index = 1, mine.count do groups[index] = true end
    local xs = layout({ { cards = groups } })[1]
    for _, item in ipairs(xs and xs.cards or {}) do thinBack(c, item.x, HAND_Y) end
    c:textCenter(61, HAND_Y + THIN_H + 2, tostring(mine.name):sub(1, 18), C.text)
    return
  end
  drawRow(c, layout(groupsOf(hand)), HAND_Y, hand.pick, hand.fresh)
  meter(c, hand.left or hand.deadwood)
end

local function showRow(c, player, y, view)
  local final = player.final
  local words = tostring(player.name):sub(1, 18)
  if view.outcome.knocker == player.seat then words = words .. (view.outcome.gin and " went gin" or " knocked") end
  c:text(4, y - 1, words, C.text)
  local score = "Deadwood " .. final.deadwood
  c:text(118 - #score, y - 1, score, final.deadwood == 0 and C.win or C.gold)
  drawRow(c, layout(groupsOf(final)), y)
end

local function finished(c, view, info)
  local mine, them = sides(view, info)
  if view.outcome.wash then
    topRow(c, view, them)
    c:bigCenter(61, PROMPT_Y, "NO HAND", C.gold, 1)
    if view.hand then drawRow(c, layout(groupsOf(view.hand)), HAND_Y) end
    return
  end
  showRow(c, them, END_TOP, view)
  showRow(c, mine, END_BOTTOM, view)
end

function M.draw(c, view, anim, info)
  if type(view) ~= "table" or not view.players or not view.players[2] then return end
  if view.over then
    finished(c, view, info)
  else
    playing(c, view, info)
  end
end

--- A card is tapped to choose it, and the piles can be tapped as well as their buttons.
function M.regions(view)
  local list = {}
  if type(view) ~= "table" or not view.hand or view.over then return list end
  if view.phase == "draw" then
    list[1] = { id = "stock", x = STOCK_X, y = PILES_Y, w = ui.CARD_W, h = ui.CARD_H }
    list[2] = { id = "take", x = PILE_X, y = PILES_Y, w = ui.CARD_W, h = ui.CARD_H }
    return list
  end
  for _, group in ipairs(layout(groupsOf(view.hand))) do
    for _, item in ipairs(group.cards) do
      if item.card ~= view.hand.took then
        list[#list + 1] = { id = "pick", value = item.card, x = item.x, y = HAND_Y - 2, w = THIN_W, h = THIN_H + 2 }
      end
    end
  end
  return list
end

return M
