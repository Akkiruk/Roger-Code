-- games/cribbage/seatView.lua
-- A player's wall, 121x81. Across the top the peg board, two streets of 60 holes with a lane for each player, so the race reads from
-- across the room. Under it the starter, the crib, and the count with its cards. At the bottom this player's hand. In the show the
-- count gives way to the hand being counted, with its breakdown and what the hand has made so far.
-- A wall with no viewer has no view.mine and shows only backs. Everything above row 54 stays in view under the result banner.

local deck = require("lib.casino.deck")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local MID = 61
local BOARD_Y, BOARD_H = 10, 14     -- the panel the board sits in
local LANE_H = 2                    -- a lane, with a row of board between the two of a street
local HOLES_X = 38                  -- the first hole of a street
local STREET = 60                   -- holes in a street
local FINISH_X = 111                -- the last hole, past the end of the second street
local TABLE_Y = 25                  -- the starter and the crib
local STARTER_X, CRIB_X = 4, 23
local COUNT_X = 44                  -- the count and the cards in it
local COUNT_Y = 24
local CALLED_X = 86                 -- the calls, right of the count
local RUN_Y = 30
local RUN_H, RUN_W = 13, 9          -- one card of the count, a thin card as in Gin
local PROMPT_Y = 44
local HAND_Y = 52                   -- the row of cards, with room above for a picked card to rise
local RISE = 2
local BACKS_Y = 53
local SHOW_CARD_Y = 31              -- the show
local SHOW_STARTER_X = 78
local SHOW_NOTES_X = 97
local TALLY_Y = 48

--- Each player's colour on the board, by position: the lane, and the same mark on their cards in the count.
local function colorOf(view, seat)
  return (view.players[1].seat == seat) and C.gold or C.blue
end

local function nameOf(view, seat)
  for _, player in ipairs(view.players) do
    if player.seat == seat then return player.name end
  end
  return "?"
end

--- Me and them, for a wall. A wall with nobody at it takes the first player as its own.
local function sides(view, info)
  local list = view.players
  local mine = (info and info.seat == list[2].seat) and list[2] or list[1]
  return mine, mine == list[1] and list[2] or list[1]
end

local function upper(name, room)
  return seatui.short(tostring(name), room or 10):upper()
end

--- "ALICE'S" on a wall nobody is at, "YOUR" to the player whose it is.
local function whose(view, seat, info)
  if view.mine and info and info.seat == seat then return "YOUR" end
  return upper(nameOf(view, seat)) .. "'S"
end

--- A line of big text if it fits the wall, or plain text.
local function say(c, y, words, color)
  if c:bigWidth(words, 1) <= 117 then
    c:bigCenter(MID, y, words, color, 1)
  else
    c:textCenter(MID, y + 2, words, color)
  end
end

-- ------------------------------------------------------------------ the board

local function holeX(hole)
  local along = (hole - 1) % STREET
  return HOLES_X + along + math.floor(along / 5)
end

--- One lane of one street. Lit up to the score in the player's colour, and what the last move added is white, so it can be seen moving.
local function lane(c, y, first, player, color)
  for hole = first, first + STREET - 1 do
    local fill = hole % 2 == 0 and C.panel or C.panel2
    if hole <= player.score then fill = hole > player.back and C.text or color end
    c:rect(holeX(hole), y, 1, LANE_H, fill)
  end
end

local function scoreBlock(c, y, view, player, color)
  c:rect(4, y, 2, 5, color)
  c:text(7, y, seatui.short(player.name, 10), C.text)
  if view.dealer == player.seat then c:text(7, y + 1, "CRIB", C.gold) end
  if view.turn == player.seat then c:text(7, y + 2, "TO PLAY", C.win) end
  if player.left > 0 then c:text(7, y + 3, player.left .. (player.left == 1 and " card" or " cards"), C.mute) end
  local text = tostring(player.score)
  c:big(36 - c:bigWidth(text, 1), y, text, player.score >= view.target and C.win or color, 1)
end

local function board(c, view)
  c:rect(2, BOARD_Y, 119, BOARD_H, C.feltDark)
  local first, second = view.players[1], view.players[2]
  scoreBlock(c, BOARD_Y + 1, view, first, C.gold)
  scoreBlock(c, BOARD_Y + 7, view, second, C.blue)
  for tens = 1, 6 do
    c:textCenter(holeX(tens * 10), BOARD_Y + 1, tens * 10, C.mute)
    if tens ~= 3 then c:textCenter(holeX(tens * 10), BOARD_Y + 7, 60 + tens * 10, C.mute) end
  end
  lane(c, BOARD_Y + 2, 1, first, C.gold)
  lane(c, BOARD_Y + 5, 1, second, C.blue)
  lane(c, BOARD_Y + 8, STREET + 1, first, C.gold)
  lane(c, BOARD_Y + 11, STREET + 1, second, C.blue)
  -- Hole 91: a loser short of it is skunked
  local mark = holeX(view.skunk)
  c:rect(mark, BOARD_Y + 8, 1, LANE_H * 2 + 1, C.red)
  c:text(mark - 2, BOARD_Y + 7, "SKUNK", C.red)
  c:text(FINISH_X, BOARD_Y + 7, tostring(view.target), C.gold)
  for index, player in ipairs(view.players) do
    local home = player.score >= view.target
    c:rect(FINISH_X, BOARD_Y + 5 + index * 3, 3, LANE_H, home and C.win or C.panel)
  end
end

-- ------------------------------------------------------------------ cards

local function thin(c, x, y, card)
  c:rect(x + 1, y, RUN_W - 2, RUN_H, C.card)
  c:rect(x, y + 1, RUN_W, RUN_H - 2, C.card)
  local color = deck.isRed(card) and C.red or C.ink
  c:bigCenter(x + 5, y + 1, deck.rankName(card), color, 1)
  ui.suit(c, x + 1, y + 7, deck.suit(card), color, 1)
end

local function starterAndCrib(c, view, info)
  c:textCenter(STARTER_X + 8, TABLE_Y - 1, "STARTER", C.text)
  if view.starter then
    ui.card(c, STARTER_X, TABLE_Y, view.starter)
  else
    ui.card(c, STARTER_X, TABLE_Y, nil)
  end
  if view.dealer then c:textCenter(CRIB_X + 8, TABLE_Y - 1, whose(view, view.dealer, info) .. " CRIB", C.text) end
  if view.cribCards > 0 then
    ui.card(c, CRIB_X, TABLE_Y, nil)
    c:textCenter(CRIB_X + 8, TABLE_Y + ui.CARD_H + 1, view.cribCards .. " cards", C.mute)
  else
    ui.cardSlot(c, CRIB_X, TABLE_Y)
  end
end

--- What the last card scored, and anything else to know about the count, to the right of it.
local function calledOut(c, view)
  local y = COUNT_Y + 1
  for index = math.max(1, #view.called - 1), #view.called do
    local item = view.called[index]
    c:text(CALLED_X, y, seatui.short(nameOf(view, item.seat), 10) .. ": " .. item.words .. " " .. item.points, colorOf(view, item.seat))
    y = y + 2
  end
  if view.closed then
    c:text(CALLED_X, y, "A new count starts", C.mute)
  elseif view.saidGo then
    c:text(CALLED_X, y, seatui.short(nameOf(view, view.saidGo), 10) .. " says go", C.mute)
  end
end

local function theCount(c, view)
  if view.count == 0 and #view.run == 0 then
    c:big(COUNT_X, COUNT_Y, "COUNT 0", C.mute, 1)
    return
  end
  c:big(COUNT_X, COUNT_Y, "COUNT " .. view.count, view.closed and C.mute or C.gold, 1)
  local step = #view.run < 8 and RUN_W + 1 or RUN_W
  for index, item in ipairs(view.run) do
    local x = COUNT_X + (index - 1) * step
    thin(c, x, RUN_Y, item.card)
    c:rect(x, RUN_Y + RUN_H, RUN_W, 1, colorOf(view, item.seat))
  end
  calledOut(c, view)
end

--- Who has thrown, without a word of what.
local function discards(c, view)
  local y = COUNT_Y + 1
  for _, player in ipairs(view.players) do
    c:text(COUNT_X, y, seatui.short(player.name, 16), C.text)
    c:big(COUNT_X, y + 1, player.thrown and "THROWN" or "CHOOSING", player.thrown and C.win or C.mute, 1)
    y = y + 8
  end
  if view.mine and #view.mine.threw > 0 then
    c:text(COUNT_X, y + 1, "You threw " .. deck.name(view.mine.threw[1]) .. " and " .. deck.name(view.mine.threw[2]), C.text)
  end
end

--- Where a hand's cards go across the wall.
local function handXs(count)
  return ui.fan(MID, math.max(1, count), ui.CARD_W, 116)
end

local function has(list, card)
  for _, item in ipairs(list or {}) do
    if item == card then return true end
  end
  return false
end

local function ownHand(c, view)
  local mine = view.mine
  local xs = handXs(#mine.cards)
  for index, card in ipairs(mine.cards) do
    local rise = has(mine.picks, card) and RISE or 0
    ui.card(c, xs[index], HAND_Y - rise, card)
    if rise > 0 then c:frame(xs[index], HAND_Y - rise, ui.CARD_W, ui.CARD_H, C.gold) end
    if mine.live then
      if has(mine.live, card) then
        c:rect(xs[index], HAND_Y + ui.CARD_H, ui.CARD_W, 1, C.gold)
      else
        c:textCenter(xs[index] + 9, HAND_Y + 8, "NO FIT", C.red, C.card)
      end
    end
  end
end

--- Backs for both, on a wall nobody is at.
local function backs(c, view)
  for index, player in ipairs(view.players) do
    local cx = index == 1 and 32 or 90
    c:textCenter(cx, BACKS_Y - 1, seatui.short(player.name, 14), C.text)
    if player.left > 0 then
      local xs = ui.fan(cx, player.left, ui.SMALL_W, 44, 0)
      for at = 1, player.left do ui.card(c, xs[at], BACKS_Y, nil, true) end
    end
  end
end

-- ------------------------------------------------------------------ the phases

local function prompt(view, mine, info)
  if view.phase == "cut" then
    if not view.dealer then return "A TIE. CUT AGAIN" end
    return upper(nameOf(view, view.dealer)) .. " CUTS LOW AND DEALS"
  end
  if view.phase == "discard" then
    if not view.mine then return "THROWING TO " .. whose(view, view.dealer, info) .. " CRIB" end
    if view.mine.thrown then return "WAITING FOR " .. upper(nameOf(view, view.players[1].thrown and view.players[2].seat or view.players[1].seat)) end
    return "THROW 2 TO " .. whose(view, view.dealer, info) .. " CRIB"
  end
  if view.phase == "starter" then return "CUTTING THE STARTER" end
  if view.phase == "peg" then
    if not view.mine then return upper(nameOf(view, view.turn)) .. " TO PLAY" end
    if view.turn == mine.seat then return "YOUR TURN: TAP A CARD" end
    return "WAITING FOR " .. upper(nameOf(view, view.turn))
  end
  return ""
end

local function cutScene(c, view)
  local xs = { 28, 76 }
  for index, player in ipairs(view.players) do
    c:textCenter(xs[index] + 8, TABLE_Y - 1, seatui.short(player.name, 14), C.text)
    ui.card(c, xs[index], TABLE_Y, player.cut)
  end
  say(c, PROMPT_Y, prompt(view), C.gold)
end

--- The hand on show, its breakdown, and the tally of the three counts.
local function showScene(c, view, info)
  local shown = view.shown
  if not shown then
    say(c, TABLE_Y + 8, "THE SHOW", C.gold)
  else
    local title = whose(view, shown.seat, info) .. " " .. (shown.what == "crib" and "CRIB" or "HAND")
    c:big(4, TABLE_Y - 1, title, colorOf(view, shown.seat), 1)
    local points = shown.points == 0 and "NOTHING" or ("+" .. shown.points)
    c:big(118 - c:bigWidth(points, 1), TABLE_Y - 1, points, shown.points == 0 and C.mute or C.win, 1)
    local xs = ui.fan(40, #shown.cards, ui.CARD_W, 72)
    for index, card in ipairs(shown.cards) do ui.card(c, xs[index], SHOW_CARD_Y, card) end
    c:textCenter(SHOW_STARTER_X + 8, SHOW_CARD_Y - 1, "STARTER", C.text)
    ui.card(c, SHOW_STARTER_X, SHOW_CARD_Y, view.starter)
    local y = SHOW_CARD_Y
    for _, item in ipairs(shown.items) do
      c:text(SHOW_NOTES_X, y, item.label, C.text)
      c:text(118 - #tostring(item.points) + 1, y, item.points, C.gold)
      y = y + 2
    end
    if #shown.items == 0 then c:text(SHOW_NOTES_X, y, "No points", C.mute) end
  end
  local width = 37
  local pone = view.players[1].seat == view.dealer and view.players[2].seat or view.players[1].seat
  for step = 1, 3 do
    local x = 3 + (step - 1) * (width + 2)
    c:rect(x, TALLY_Y, width, 5, C.feltDark)
    local item = view.tally[step]
    local label = seatui.short(nameOf(view, step == 1 and pone or view.dealer), 10) .. (step == 3 and "'s crib" or "'s hand")
    c:text(x + 2, TALLY_Y + 1, label, item and C.text or C.mute)
    if item then c:text(x + 2, TALLY_Y + 3, tostring(item.points) .. (item.points == 1 and " point" or " points"), C.gold) end
  end
end

local function playing(c, view, info)
  starterAndCrib(c, view, info)
  if view.phase == "discard" then
    discards(c, view)
  else
    theCount(c, view)
  end
end

local function finished(c, view, info)
  if view.shown then
    showScene(c, view, info)
    return
  end
  starterAndCrib(c, view, info)
  theCount(c, view)
  say(c, PROMPT_Y, upper(nameOf(view, view.outcome.winner)) .. " REACHES " .. view.target, C.gold)
end

function M.draw(c, view, anim, info)
  if type(view) ~= "table" or not view.players or not view.players[2] then return end
  board(c, view)
  local mine = sides(view, info)
  if view.over then
    finished(c, view, info)
  elseif view.phase == "cut" then
    cutScene(c, view)
  elseif view.phase == "show" then
    showScene(c, view, info)
  else
    playing(c, view, info)
    local mineToAct = view.mine and ((view.phase == "discard" and not view.mine.thrown) or view.turn == mine.seat)
    say(c, PROMPT_Y, prompt(view, mine, info), mineToAct and C.gold or C.mute)
    if view.mine then
      ownHand(c, view)
    else
      backs(c, view)
    end
  end
end

--- Cards are tapped to pick them for the crib or to lay them on the count. Only what can really be tapped now.
function M.regions(view)
  local list = {}
  if type(view) ~= "table" or not view.mine or view.over then return list end
  local mine = view.mine
  local xs = handXs(#mine.cards)
  for index, card in ipairs(mine.cards) do
    if view.phase == "discard" and not mine.thrown then
      list[#list + 1] = { id = "pick", value = card, x = xs[index], y = HAND_Y - RISE, w = ui.CARD_W, h = ui.CARD_H + RISE }
    elseif has(mine.live, card) then
      list[#list + 1] = { id = "play", value = card, x = xs[index], y = HAND_Y - RISE, w = ui.CARD_W, h = ui.CARD_H + RISE }
    end
  end
  return list
end

return M
