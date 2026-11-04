-- games/uno/seatView.lua
-- A player's own screen, 78 wide. Along the top the card to match on a block of the colour in play, that colour's name in big
-- letters, who is next, and everyone's card count. Below, their hand as big cards, fourteen at a time (< and > for more). On their
-- turn the cards they may play are framed in gold and the rest are dimmed: a tap on a lit card plays it. A wild asks for its colour
-- with four big colour tiles. The buttons along the bottom are DRAW, UNO! (lit gold while they hold two cards: tap it, then play),
-- CATCH! when someone else has gone down to one card without saying it, and KEEP or PLAY IT after drawing a card that can be played.

local cards = require("games.uno.cards")
local draw = require("games.uno.draw")
local seatui = require("lib.casino.group.seatui")
local theme = require("lib.casino.theme")

local C = theme.C
local M = {}

local TOP = seatui.TOP          -- 10
local W = seatui.W              -- 78
local CARD_W, CARD_H, GAP = 10, 7, 1
local PER_ROW = 7
local ROW_Y = { 22, 30 }
local TALL_H = 14         -- seven cards or fewer: one row, twice as tall
local PAGE = 14
local TILE_Y, TILE_H, TILE_W = 23, 14, 18

local function short(name, room)
  name = tostring(name or "")
  if #name <= room then return name end
  return name:sub(1, room - 1) .. "."
end

local function contains(list, value)
  for _, item in ipairs(list or {}) do
    if item == value then return true end
  end
  return false
end

local function myTurn(view)
  return view.me and view.turn == view.me and (view.phase == "play" or view.phase == "drawn" or view.phase == "color")
end

--- The page on show: the one with the drawn card when there is one, otherwise the player's own.
local function pageOf(view)
  local hand = view.hand or {}
  if view.drawn then
    for i, card in ipairs(hand) do
      if card == view.drawn then return math.floor((i - 1) / PAGE) + 1 end
    end
  end
  return math.max(1, math.min(view.page or 1, math.ceil(#hand / PAGE)))
end

--- Where each card of the page goes.
local function layout(view)
  local hand = view.hand or {}
  local page = pageOf(view)
  local first = (page - 1) * PAGE + 1
  local last = math.min(#hand, first + PAGE - 1)
  local count = last - first + 1
  local out = {}
  for i = first, last do
    local k = i - first
    local row = math.floor(k / PER_ROW)
    local col = k % PER_ROW
    local inRow = math.min(PER_ROW, count - row * PER_ROW)
    -- A short row sits in the middle
    local rowW = inRow * (CARD_W + GAP) - GAP
    local x0 = math.floor((W - rowW) / 2) + 1
    out[#out + 1] = { card = hand[i], x = x0 + col * (CARD_W + GAP), y = ROW_Y[row + 1], h = count <= PER_ROW and TALL_H or CARD_H }
  end
  return out, page
end

local function picking(view)
  return myTurn(view) and (view.pick or view.phase == "color")
end

local function tiles()
  local out = {}
  for i, c in ipairs(cards.COLORS) do
    out[i] = { color = c, x = 2 + (i - 1) * (TILE_W + 1), y = TILE_Y, w = TILE_W, h = TILE_H }
  end
  return out
end

-- ------------------------------------------------------------------ pieces of the screen

local function header(c, view, text, ink, bg)
  bg = bg or C.feltDark
  c:rect(1, TOP, W, 1, bg)
  c:text(2, TOP, short(text, 56), ink or C.gold, bg)
  local me = view.players[view.me or 0]
  if me then
    local score = tostring(me.score) .. (view.goal and view.goal > 0 and (" / " .. view.goal) or "") .. " PTS"
    c:text(W - #score, TOP, score, bg == C.feltDark and C.gold or C.ink, bg)
  end
end

--- The card to match, the colour in play, who is next and how many cards everyone holds.
local function tableStrip(c, view)
  local color = view.color
  local box = color and draw.INK[color] or C.panel2
  c:rect(2, TOP + 1, 14, 9, box)
  if view.top then draw.card(c, 4, TOP + 2, CARD_W, CARD_H, view.top, { color = color }) end
  if color then
    c:big(18, TOP + 2, cards.COLOR_WORD[color], box, 1)
  else
    c:text(18, TOP + 3, "No colour yet", C.text)
  end
  local n = #view.players
  local nextP = ((view.turn - 1 + (view.dir or 1)) % n) + 1
  local nextName = view.players[nextP] and view.players[nextP].name or "?"
  c:text(18, TOP + 8, ((view.dir or 1) == 1 and ">> " or "<< ") .. "next: " .. short(nextName, 12), C.text)
  -- Everyone's count, in turn order
  local x = 52
  c:rect(x - 1, TOP + 1, W - x + 1, 9, C.panel)
  local rows = math.min(n, 8)
  for p = 1, rows do
    local player = view.players[p]
    local y = TOP + 1 + (p - 1) + (n <= 4 and (p - 1) or 0)
    local turn = view.turn == p and view.phase ~= "scored" and view.phase ~= "over" and view.phase ~= "goal"
    local mark = turn and ">" or " "
    local name = short(view.me == p and "You" or player.name, 12)
    local ink = turn and C.gold or (view.me == p and C.text or C.mute)
    c:text(x, y, mark .. name, ink, C.panel)
    local count = tostring(player.count)
    local tag = ""
    if view.window and view.window.p == p then tag = "!" elseif player.said and player.count == 1 then tag = "U" end
    c:text(W - 5, y, count, player.count == 1 and C.gold or C.text, C.panel)
    if tag ~= "" then c:text(W - 2, y, tag, C.ink, tag == "!" and C.red or C.gold) end
  end
end

local function handCards(c, view, live)
  local places, page = layout(view)
  local playable = view.playable or {}
  for _, at in ipairs(places) do
    local can = live and contains(playable, at.card)
    local dim = live and not can
    draw.card(c, at.x, at.y, CARD_W, at.h, at.card, { dim = dim, lit = can })
  end
  local pages = math.max(1, math.ceil(#(view.hand or {}) / PAGE))
  if pages > 1 then
    local text = "page " .. page .. " of " .. pages .. "  (" .. #view.hand .. " cards)"
    c:textCenter(math.floor(W / 2) + 1, 38, text, C.mute)
  end
  if #(view.hand or {}) == 0 then c:textCenter(math.floor(W / 2) + 1, 27, "No cards", C.mute) end
end

local function hint(c, text, ink, bg)
  if bg then c:rect(2, TOP + 10, W - 2, 1, bg) end
  c:textCenter(math.floor(W / 2) + 1, TOP + 10, short(text, W - 4), ink or C.text, bg)
end

local function colorScreen(c, view)
  local wild = view.pick
  header(c, view, wild and "NAME A COLOUR FOR YOUR " .. string.upper(cards.name(wild)) or "NAME THE FIRST COLOUR")
  tableStrip(c, view)
  hint(c, "Tap a colour. The next player must match it.", C.text)
  for _, tile in ipairs(tiles()) do
    local ink = draw.INK[tile.color]
    c:rect(tile.x, tile.y, tile.w, tile.h, ink)
    c:frame(tile.x, tile.y, tile.w, tile.h, C.card)
    local word = cards.COLOR_WORD[tile.color]
    c:textCenter(tile.x + math.floor(tile.w / 2) + 1, tile.y + math.floor(tile.h / 2), word, draw.ON[tile.color], ink)
    local held = 0
    for _, card in ipairs(view.hand or {}) do
      if cards.color(card) == tile.color then held = held + 1 end
    end
    c:textCenter(tile.x + math.floor(tile.w / 2) + 1, tile.y + math.floor(tile.h / 2) + 2, "you hold " .. held, draw.ON[tile.color], ink)
  end
end

local function goalScreen(c, view)
  header(c, view, "A NEW GAME OF UNO")
  draw.logo(c, math.floor(W / 2) + 1, TOP + 2, 2)
  local y = TOP + 16
  if view.chooser == view.me then
    c:textCenter(math.floor(W / 2) + 1, y, "How long a game?", C.gold)
    c:textCenter(math.floor(W / 2) + 1, y + 2, "TO 500: the official game, several hands.", C.text)
    c:textCenter(math.floor(W / 2) + 1, y + 3, "TO 200: a shorter one.  ONE HAND: first out wins.", C.text)
    c:textCenter(math.floor(W / 2) + 1, y + 5, "Nobody picks in time and it is 500.", C.mute)
  else
    local chooser = view.players[view.chooser or 0]
    c:textCenter(math.floor(W / 2) + 1, y, (chooser and chooser.name or "The first seat") .. " is picking how long a game.", C.text)
    c:textCenter(math.floor(W / 2) + 1, y + 2, "Say UNO before you play your second-last card!", C.gold)
  end
end

local function scoreScreen(c, view)
  local last = view.lastHand
  local winner = last and view.players[last.winner]
  local title = winner and ((last.winner == view.me and "YOU" or string.upper(winner.name)) .. " WON HAND " .. last.hand
    .. ": +" .. last.points) or "SCORES"
  header(c, view, title)
  local y = TOP + 2
  c:text(4, y, "PLAYER", C.mute)
  c:text(26, y, "CARDS LEFT", C.mute)
  c:text(40, y, "POINTS", C.mute)
  c:text(50, y, "SCORE", C.mute)
  for p, player in ipairs(view.players) do
    local row = y + p * 2
    local isMe = view.me == p
    local ink = (last and last.winner == p) and C.gold or (isMe and C.text or C.mute)
    c:text(4, row, short(isMe and (player.name .. " (you)") or player.name, 20), ink)
    local r = last and last.rows and last.rows[p]
    if r then
      c:text(26, row, tostring(r.cards), C.text)
      c:text(40, row, last.winner == p and ("+" .. last.points) or tostring(r.points), last.winner == p and C.win or C.mute)
    end
    c:text(50, row, tostring(player.score), ink)
  end
  if view.phase == "scored" then
    local goal = view.goal == 0 and "one hand" or ("first to " .. view.goal)
    c:textCenter(math.floor(W / 2) + 1, 36, "Playing " .. goal .. ". NEXT HAND when you are ready.", C.gold)
  end
end

local function watchScreen(c, view)
  header(c, view, "UNO: WATCHING")
  if view.phase == "goal" then
    c:textCenter(math.floor(W / 2) + 1, TOP + 6, "A game is about to start.", C.text)
    return
  end
  if view.phase == "scored" or view.phase == "over" then
    scoreScreen(c, view)
    return
  end
  tableStrip(c, view)
  local who = view.players[view.turn]
  hint(c, (who and who.name or "?") .. "'s turn", C.gold)
  c:textCenter(math.floor(W / 2) + 1, 28, "Tap your seat to see your hand.", C.text)
end

local function handScreen(c, view)
  local p = view.me
  local live = myTurn(view)
  local who = view.players[view.turn]
  local window = view.window
  local offender = window and view.players[window.p]
  if view.canCatch and offender then
    header(c, view, string.upper(offender.name) .. " DID NOT SAY UNO!  CATCH!", C.text, C.red)
  elseif live and view.phase == "drawn" then
    header(c, view, "YOU DREW " .. string.upper(cards.name(view.drawn)) .. ": PLAY IT OR KEEP IT")
  elseif live then
    header(c, view, "YOUR TURN")
  elseif view.phase == "over" then
    header(c, view, "GAME OVER")
  else
    header(c, view, (who and who.name or "?") .. "'s turn", C.text)
  end
  tableStrip(c, view)
  local hand = view.hand or {}
  if live then
    local playable = view.playable or {}
    if view.phase == "drawn" then
      hint(c, "Tap the lit card or PLAY IT to play it, or KEEP it", C.text)
    elseif #hand == 2 and #playable > 0 and not view.armed then
      hint(c, "Two cards: tap UNO! first, then play!", C.ink, C.gold)
    elseif view.armed then
      hint(c, "UNO said. Now play your card", C.ink, C.gold)
    elseif #playable == 0 then
      hint(c, "Nothing matches: DRAW a card", C.orange)
    else
      hint(c, "Tap a lit card to play it, or DRAW", C.text)
    end
  elseif view.canCatch and offender then
    hint(c, "Tap CATCH! before the next player moves: " .. offender.name .. " draws 2", C.text, C.red)
  elseif p and view.players[p] and view.players[p].said and #hand == 1 then
    hint(c, "UNO! One card left", C.ink, C.gold)
  end
  handCards(c, view, live)
end

function M.draw(c, view, anim, info)
  if not view or not view.players then return end
  if not view.me then
    watchScreen(c, view)
  elseif view.phase == "goal" then
    goalScreen(c, view)
  elseif view.phase == "scored" then
    scoreScreen(c, view)
  elseif view.phase == "over" then
    scoreScreen(c, view)
  elseif picking(view) then
    colorScreen(c, view)
  else
    handScreen(c, view)
  end
  if anim and view.me then
    local ev = anim.ev
    -- A moment on this seat for what happened to it
    local text, ink
    if ev.type == "catch" and ev.q == view.me then text, ink = "CAUGHT! +2", C.red
    elseif ev.type == "catch" and ev.p == view.me then text, ink = "GOT THEM!", C.win
    elseif ev.victim == view.me and ev.p ~= view.me then
      text = ({ skip = "SKIPPED", draw2 = "+2 SKIP", draw4 = "+4 SKIP" })[ev.type]
      ink = C.red
    elseif ev.type == "uno" and ev.p == view.me then text, ink = "UNO!", C.gold
    end
    if text and anim.t < 0.9 then
      local w = c:bigWidth(text, 1) + 6
      local x = math.floor((W - w) / 2) + 1
      c:rect(x, 24, w, 9, C.ink)
      c:frame(x, 24, w, 9, ink)
      c:bigCenter(math.floor(W / 2) + 1, 26, text, ink, 1)
    end
  end
end

--- Taps on the screen itself: a lit card plays it, a colour tile names the colour.
function M.regions(view)
  if not view or not view.me or not myTurn(view) then return {} end
  local list = {}
  if picking(view) then
    for _, tile in ipairs(tiles()) do
      list[#list + 1] = { id = "color", value = tile.color, x = tile.x, y = tile.y, w = tile.w, h = tile.h }
    end
    return list
  end
  local places = layout(view)
  for _, at in ipairs(places) do
    if contains(view.playable, at.card) then
      list[#list + 1] = { id = "play", value = at.card, x = at.x, y = at.y, w = CARD_W, h = at.h }
    end
  end
  return list
end

M.layout = layout

return M
