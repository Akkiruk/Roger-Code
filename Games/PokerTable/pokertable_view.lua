-- pokertable_view.lua
-- The poker wall: six places round an oval table, the pot in the middle. Seats run clockwise, 1-3 along the top from
-- the left and 4-6 along the bottom from the right, so "left of the button" reads the way it does at a real table.
-- Everyone's cards are backs here. A player's own hand only shows through the peek.

local deck = require("lib.casino.deck")
local poker = require("lib.casino.poker")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("pokertable_rules")

local C = theme.C
local M = {}

local TOP_Y, BOTTOM_Y = ui.TOP + 1, 50   -- a row free round each, for the gold of the seat to act
local BOX_W, BOX_H, BOX_GAP = 35, 17, 4
local BOX_LEFT = 5
local NAME_MAX = 14
local SEAT_NAME_MAX = 13   -- beside the seat's status
local HEAD_H = 9           -- a seat's name and stack. Its cards tuck in under this, or two rows of seats leave no room for the pot
local CARD_TOP = 3         -- a seat's cards, down from the top of the box, most of them under the head
local PHASE_Y, POT_Y = 31, 33
local ACTOR_Y, TURN_Y, SIDE_Y = 44, 46, 47
local PEEK_W, PEEK_H, PEEK_Y = 103, 31, 23
local REVEAL_NOTE_Y = ui.TOP + ui.BANNER_H + 1
local REVEAL_Y, REVEAL_ROOM = 28, 37   -- the rows for the hands, under the note and over the folded line
local REVEAL_H, REVEAL_GAP = 17, 3
local FOLDED_Y = 67
local WALL_W = 115         -- between the margins
local RANK_STEP = 7        -- a narrower strip of a card cannot show a big rank
local SUIT_CHARS = { [0] = 5, [1] = 4, [2] = 3, [3] = 6 } -- clubs, diamonds, hearts, spades

M.BANNER_Y = 31            -- the result of a hand nobody had to show, between the rows of seats

M.PHASES = {
  bet1 = "FIRST BETTING ROUND",
  draw = "THE DRAW",
  bet2 = "FINAL BETTING ROUND",
  over = "SHOWDOWN",
}

--- Where a seat sits on the wall.
function M.seatBox(_, seat)
  local column = seat <= 3 and seat or 7 - seat
  return BOX_LEFT + (column - 1) * (BOX_W + BOX_GAP), seat <= 3 and TOP_Y or BOTTOM_Y, BOX_W, BOX_H
end

--- Where a seat's SIT sits, whether it is a button or lies under a demo's player.
function M.sitSpot(c, seat)
  local x, y, w, h = M.seatBox(c, seat)
  return x + 8, y + math.floor((h - 9) / 2), w - 16, 9
end

local function short(name, limit)
  name = tostring(name)
  limit = limit or NAME_MAX
  if #name <= limit then return name end
  return name:sub(1, limit - 1) .. "."
end
M.short = short

--- The table itself: a dark rail and an oval of felt with one fine line round it.
function M.felt(c)
  c:clear(C.feltDark)
  local cx, cy = (c.w + 1) / 2, 39
  local rx, ry = c.w / 2 - 3, 27
  for y = cy - ry, cy + ry do
    local dy = (y - cy) / ry
    local half = math.floor(rx * math.sqrt(math.max(0, 1 - dy * dy)))
    local line = half + 1
    c:rect(math.floor(cx - line), y, line * 2 + 1, 1, C.feltLight)
    c:rect(math.floor(cx - half + 1), y, math.max(0, (half - 1) * 2 + 1), 1, C.felt)
  end
end

--- A seat nobody has taken.
function M.emptySeat(c, list, seat, canSit)
  local x, y, w, h = M.seatBox(c, seat)
  c:rect(x, y, w, h, C.feltDark)
  c:frame(x, y, w, h, C.feltLight)
  if canSit then
    local sx, sy, sw, sh = M.sitSpot(c, seat)
    ui.button(c, list, { id = "sit", value = seat, x = sx, y = sy, w = sw, h = sh, label = "SIT",
      color = C.accent, textColor = C.ink })
  else
    c:textCenter(x + math.floor(w / 2), y + math.floor(h / 2), "open seat", C.feltLight)
  end
end

--- A taken seat. info: name, stack, status, statusColor, cards (how many backs), active, button, dim.
function M.seat(c, seat, info)
  local x, y, w, h = M.seatBox(c, seat)
  c:rect(x, y, w, h, C.panel)
  c:frame(x, y, w, h, info.active and C.gold or C.ink)
  if info.active then c:frame(x - 1, y - 1, w + 2, h + 2, C.gold) end

  local shown = info.cards or 0
  if shown > 0 then
    local xs = ui.fan(x + math.floor(w / 2), rules.HAND_SIZE, ui.SMALL_W, w - 10, 1)
    for i = 1, math.min(shown, rules.HAND_SIZE) do
      ui.card(c, xs[i], y + CARD_TOP, nil, true)
    end
    c:rect(x + 1, y + 1, w - 2, HEAD_H, C.panel)
  end

  c:text(x + 3, y + 2, short(info.name, SEAT_NAME_MAX), info.dim and C.mute or C.text)
  if info.status then c:text(x + w - 3 - #info.status, y + 2, info.status, info.statusColor or C.mute) end
  c:big(x + 3, y + 4, ui.group(info.stack or 0), info.dim and C.mute or C.gold, 1)

  if info.button then
    -- The dealer button, a small white disc level with the stack
    c:rect(x + w - 6, y + 5, 3, 3, C.card)
    c:text(x + w - 5, y + 6, "D", C.ink, C.card)
  end
end

local function seatInfo(state, player, index, anim, dealt)
  local info = {
    name = player.name, stack = player.stack, cards = player.folded and 0 or dealt,
    active = state.turn == index and not anim, button = state.button == index, dim = player.folded,
  }
  if player.folded then
    info.status, info.statusColor = "folded", C.mute
  elseif player.allin then
    info.status, info.statusColor = "ALL-IN " .. player.total, C.orange
  elseif player.last then
    info.status = player.last .. (player.bet > 0 and (" " .. player.bet) or "")
    info.statusColor = C.win
  elseif player.bet > 0 then
    info.status, info.statusColor = "in for " .. player.bet, C.win
  end
  return info
end

--- The middle of the table during a hand.
function M.centre(c, state, anim, warn, turnShare)
  local cx = math.floor(c.w / 2)
  c:textCenter(cx, PHASE_Y, M.PHASES[state.phase] or "", C.gold)
  c:bigCenter(cx, POT_Y, ui.group(rules.potTotal(state)), C.text, 2)

  local line = nil
  local pots = rules.pots(state.players)
  local contested, side = 0, 0
  for _, pot in ipairs(pots) do
    if #pot.eligible > 1 then
      contested = contested + 1
      if contested == 1 then line = "Pot " .. ui.group(pot.amount) else side = side + pot.amount end
    end
  end
  if side > 0 then c:textCenter(cx, SIDE_Y, line .. "   Side pots " .. ui.group(side), C.text) end

  local actor = rules.actor(state)
  if actor and not anim then
    local text
    if state.phase == "draw" then
      text = short(actor) .. " to draw"
    else
      local toCall = rules.toCall(state)
      text = short(actor) .. (toCall > 0 and (" to call " .. toCall) or " to act")
    end
    c:textCenter(cx, ACTOR_Y, text, C.text)
    if turnShare then
      local width = math.floor(40 * turnShare)
      c:rect(cx - 20, TURN_Y, 40, 1, C.feltDark)
      c:rect(cx - 20, TURN_Y, width, 1, warn and C.orange or C.gold)
    end
  end
end

--- A whole hand in play.
function M.table(c, state, anim)
  M.felt(c)
  local inHand = {}
  local dealing = anim and anim.ev.type == "deal"
  local players = #state.players
  for index, player in ipairs(state.players) do
    inHand[player.seat] = true
    local dealt = rules.HAND_SIZE
    if dealing then
      -- One card at a time round the table
      local progress = anim.t * rules.HAND_SIZE
      dealt = math.floor(progress) + ((index - 1) / players < progress % 1 and 1 or 0)
    end
    M.seat(c, player.seat, seatInfo(state, player, index, anim, dealt))
  end
  for seat = 1, rules.MAX_SEATS do
    if not inHand[seat] then M.emptySeat(c, {}, seat, false) end
  end
end

--- The result across the wall, tall enough that its detail line clears a big title.
function M.banner(c, y, title, detail)
  local cx = math.floor(c.w / 2)
  c:rect(1, y, c.w, ui.BANNER_H, C.ink)
  c:rect(1, y, c.w, 1, C.gold)
  c:rect(1, y + ui.BANNER_H - 1, c.w, 1, C.gold)
  c:bigCenter(cx, y + 2, title, C.gold, c:bigWidth(title, 2) <= c.w - 6 and 2 or 1)
  c:textCenter(cx, y + ui.BANNER_H - 2, detail, C.text)
end

--- The peek: one player's hand, big, over the middle of the table. discards marks the cards they will throw.
-- Returns the regions of the cards when they can be tapped.
function M.peek(c, name, hand, discards, share, drawing)
  local cx = math.floor(c.w / 2)
  local w, h = PEEK_W, PEEK_H
  local x, y = cx - math.floor(w / 2) + 1, PEEK_Y
  c:rect(x, y, w, h, C.ink)
  c:frame(x, y, w, h, C.gold)
  c:text(x + 3, y + 2, short(name) .. "'s hand", C.gold)
  local value = poker.evaluate(hand)
  local label = poker.describe(value)
  c:text(x + w - 3 - #label, y + 2, label, C.text)

  local regions = {}
  local xs = ui.fan(cx + 1, #hand, ui.CARD_W, w - 6, 2)
  for i, card in ipairs(hand) do
    local lifted = discards and discards[i]
    local top = y + 4 + (lifted and 0 or 3)
    ui.card(c, xs[i], top, card, false)
    if lifted then c:textCenter(xs[i] + 8, top + 18, "THROW", C.orange) end
    regions[i] = { id = "card" .. i, x = xs[i], y = y + 4, w = ui.CARD_W, h = ui.CARD_H + 4 }
  end

  c:rect(x + 3, y + h - 3, math.floor((w - 6) * share), 1, C.gold)
  if drawing then
    c:textCenter(cx, y + h - 5, "Tap cards to throw. Keep an ace and you may throw " .. rules.MAX_DISCARD_ACE .. ".", C.mute)
  end
  return drawing and regions or {}
end

-- ------------------------------------------------------------------ the end of a hand

--- Where a shown hand sits: two across, or three across for five or six hands, which could not stand in three rows of two
-- under the banner. Each row is centred, so a short last row sits in the middle.
local function revealBox(c, position, total)
  local across = total > 4 and 3 or 2
  local gap = across == 3 and BOX_GAP or 3
  local w = math.floor((WALL_W - gap * (across - 1)) / across)
  local rows = math.ceil(total / across)
  local row = math.ceil(position / across)
  local inRow = row < rows and across or total - (rows - 1) * across
  local left = 1 + math.floor((c.w - inRow * w - (inRow - 1) * gap) / 2)
  -- Two hands alone have the room for full-size cards
  local h = rows == 1 and REVEAL_H + ui.CARD_H - ui.SMALL_H or REVEAL_H
  local top = REVEAL_Y + math.floor((REVEAL_ROOM - rows * h - (rows - 1) * REVEAL_GAP) / 2)
  return left + (position - (row - 1) * across - 1) * (w + gap), top + (row - 1) * (h + REVEAL_GAP), w, h
end

--- A shown hand, fanned. Strips of a fan lose the corner pip, so the suit moves under the rank, in the monitor font's own
-- suit characters on small cards, and a strip too thin for the big rank has the rank in those characters too.
local function shownHand(c, cx, y, hand, maxW, small)
  local cardW = small and ui.SMALL_W or ui.CARD_W
  local xs = ui.fan(cx, #hand, cardW, maxW, 1)
  for i, card in ipairs(hand) do
    ui.card(c, xs[i], y, card, small)
    local step = xs[i + 1] and xs[i + 1] - xs[i] or cardW
    if step < cardW then
      local color = deck.isRed(card) and C.red or C.ink
      local tight = step < RANK_STEP
      if small then
        c:rect(xs[i] + 1, y + (tight and 1 or 6), step - 1, tight and 10 or 5, C.card)
      else
        c:rect(xs[i] + 8, y + 10, step - 8, 5, C.card)
      end
      c:rect(xs[i] + step - 1, y + 1, 1, (small and ui.SMALL_H or ui.CARD_H) - 2, C.mute)
      if tight then c:text(xs[i] + 1, y + 3, deck.rankName(card):sub(1, step - 2), color, C.card) end
      if small then
        c:text(xs[i] + 1, y + (tight and 6 or 8), string.char(SUIT_CHARS[deck.suit(card)]), color, C.card)
      else
        ui.suit(c, xs[i] + 1, y + 7, deck.suit(card), color, 1)
      end
    end
  end
end

--- Every hand still in, face up, under the result.
function M.reveal(c, state, owedNote)
  local shown = {}
  for _, player in ipairs(state.players) do
    if not player.folded then shown[#shown + 1] = player end
  end
  for position, player in ipairs(shown) do
    local x, y, w, h = revealBox(c, position, #shown)
    local won = player.net > 0
    c:rect(x, y, w, h, won and C.feltLight or C.panel)
    c:text(x + 2, y + 1, short(player.name), C.text)
    local net = ui.signed(player.net)
    c:text(x + w - 2 - #net, y + 1, net, won and C.win or (player.net < 0 and C.red or C.text))
    if player.handName then c:text(x + 2, y + 2, player.handName, won and C.gold or C.text) end
    shownHand(c, x + math.floor(w / 2), y + 4, player.hand, w - 4, h == REVEAL_H)
  end
  local out = {}
  for _, player in ipairs(state.players) do
    if player.folded then out[#out + 1] = short(player.name) .. " " .. ui.signed(player.net) end
  end
  if #out > 0 then c:textCenter(math.floor(c.w / 2), FOLDED_Y, "Folded: " .. table.concat(out, "   "), C.text) end
  if owedNote then c:textCenter(math.floor(c.w / 2), REVEAL_NOTE_Y, owedNote, C.orange) end
end

return M
