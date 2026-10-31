-- pokertable_view.lua
-- The poker wall: six places round an oval table, the pot in the middle. Seats run clockwise, 1-3 along the top from
-- the left and 4-6 along the bottom from the right, so "left of the button" reads the way it does at a real table.
-- Everyone's cards are backs here. A player's own hand only shows through the peek.

local poker = require("lib.casino.poker")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("pokertable_rules")

local C = theme.C
local M = {}

local TOP_Y, BOTTOM_Y = 9, 47
local BOX_H = 21
local NAME_MAX = 14
local SEAT_NAME_MAX = 11   -- beside the big stack number

M.PHASES = {
  bet1 = "FIRST BETTING ROUND",
  draw = "THE DRAW",
  bet2 = "FINAL BETTING ROUND",
  over = "SHOWDOWN",
}

--- Where a seat sits on the wall.
function M.seatBox(c, seat)
  local w = math.floor((c.w - 10) / 3)
  local column = seat <= 3 and seat or 7 - seat
  return 3 + (column - 1) * (w + 2), seat <= 3 and TOP_Y or BOTTOM_Y, w, BOX_H
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
  local cx, cy = (c.w + 1) / 2, 38
  local rx, ry = c.w / 2 - 3, 29
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
  c:rect(x, y, w, h - 1, C.feltDark)
  c:frame(x, y, w, h - 1, C.feltLight)
  if canSit then
    ui.button(c, list, { id = "sit", value = seat, x = x + 8, y = y + 5, w = w - 16, h = 9, label = "SIT",
      color = C.accent, textColor = C.ink })
  else
    c:textCenter(x + math.floor(w / 2), y + 9, "open seat", C.feltLight)
  end
end

--- A taken seat. info: name, stack, status, statusColor, cards (how many backs), active, button, dim.
function M.seat(c, seat, info)
  local x, y, w, h = M.seatBox(c, seat)
  local edge = info.active and C.gold or C.ink
  c:rect(x, y, w, h - 1, C.panel)
  c:frame(x, y, w, h - 1, edge)
  if info.active then c:frame(x + 1, y + 1, w - 2, h - 3, C.gold) end

  c:text(x + 3, y + 3, short(info.name, SEAT_NAME_MAX), info.dim and C.mute or C.text)
  if info.status then c:text(x + 3, y + 4, info.status, info.statusColor or C.mute) end
  local stack = ui.group(info.stack or 0)
  c:big(x + w - 3 - c:bigWidth(stack, 1), y + 2, stack, info.dim and C.mute or C.gold, 1)

  local shown = info.cards or 0
  if shown > 0 then
    local xs = ui.fan(x + math.floor(w / 2) - 3, rules.HAND_SIZE, ui.SMALL_W, w - 10, 1)
    for i = 1, math.min(shown, rules.HAND_SIZE) do
      ui.card(c, xs[i], y + 7, nil, true)
    end
  end

  if info.button then
    -- The dealer button, a small white disc on the seat's corner
    c:rect(x + w - 6, y + h - 7, 3, 3, C.card)
    c:text(x + w - 5, y + h - 6, "D", C.ink, C.card)
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
  c:textCenter(cx, 29, M.PHASES[state.phase] or "", C.gold)
  c:bigCenter(cx, 31, ui.group(rules.potTotal(state)), C.text, 2)

  local line = nil
  local pots = rules.pots(state.players)
  local contested, side = 0, 0
  for _, pot in ipairs(pots) do
    if #pot.eligible > 1 then
      contested = contested + 1
      if contested == 1 then line = "Pot " .. ui.group(pot.amount) else side = side + pot.amount end
    end
  end
  if side > 0 then c:textCenter(cx, 43, line .. "   Side pots " .. ui.group(side), C.text) end

  local actor = rules.actor(state)
  if actor and not anim then
    local text
    if state.phase == "draw" then
      text = short(actor) .. " to draw"
    else
      local toCall = rules.toCall(state)
      text = short(actor) .. (toCall > 0 and (" to call " .. toCall) or " to act")
    end
    c:textCenter(cx, 44, text, C.text)
    if turnShare then
      local width = math.floor(40 * turnShare)
      c:rect(cx - 20, 45, 40, 1, C.feltDark)
      c:rect(cx - 20, 45, width, 1, warn and C.orange or C.gold)
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
  c:rect(1, y, c.w, 15, C.ink)
  c:rect(1, y, c.w, 1, C.gold)
  c:rect(1, y + 14, c.w, 1, C.gold)
  c:bigCenter(cx, y + 2, title, C.gold, c:bigWidth(title, 2) <= c.w - 6 and 2 or 1)
  c:textCenter(cx, y + 12, detail, C.text)
end

--- The peek: one player's hand, big, over the middle of the table. discards marks the cards they will throw.
-- Returns the regions of the cards when they can be tapped.
function M.peek(c, name, hand, discards, share, drawing)
  local cx = math.floor(c.w / 2)
  local w, h = 103, 31
  local x, y = cx - math.floor(w / 2), 22
  c:rect(x, y, w, h, C.ink)
  c:frame(x, y, w, h, C.gold)
  c:text(x + 3, y + 1, short(name) .. "'s hand", C.gold)
  local value = poker.evaluate(hand)
  local label = poker.describe(value)
  c:text(x + w - 3 - #label, y + 1, label, C.text)

  local regions = {}
  local xs = ui.fan(cx, #hand, ui.CARD_W, w - 6, 2)
  for i, card in ipairs(hand) do
    local lifted = discards and discards[i]
    local top = y + 4 + (lifted and 0 or 3)
    ui.card(c, xs[i], top, card, false)
    if lifted then c:textCenter(xs[i] + 8, top + 17, "THROW", C.orange) end
    regions[i] = { id = "card" .. i, x = xs[i], y = y + 3, w = ui.CARD_W, h = ui.CARD_H + 5 }
  end

  c:rect(x + 2, y + h - 2, math.floor((w - 4) * share), 1, C.gold)
  if drawing then
    c:textCenter(cx, y + h - 3, "Tap cards to throw. Keep an ace and you may throw " .. rules.MAX_DISCARD_ACE .. ".", C.mute)
  end
  return drawing and regions or {}
end

-- ------------------------------------------------------------------ the end of a hand

local function revealBox(c, position, total)
  local w = math.floor((c.w - 8) / 2)
  local rows = math.ceil(total / 2)
  local h = 14
  local top = 25 + math.floor((42 - rows * h) / 2)
  local row = math.ceil(position / 2)
  local odd = position % 2 == 1
  local x = (odd and 3 or 3 + w + 2)
  if position == total and odd then x = math.floor((c.w - w) / 2) + 1 end
  return x, top + (row - 1) * h, w, h
end

--- Every hand still in, face up, under the result.
function M.reveal(c, state, owedNote)
  local shown = {}
  for _, player in ipairs(state.players) do
    if not player.folded then shown[#shown + 1] = player end
  end
  for position, player in ipairs(shown) do
    local x, y, w = revealBox(c, position, #shown)
    local won = player.net > 0
    c:rect(x, y, w, 13, won and C.feltLight or C.panel)
    c:text(x + 2, y, short(player.name), C.text)
    if player.handName then c:textCenter(x + math.floor(w / 2), y, player.handName, won and C.gold or C.text) end
    local net = ui.signed(player.net)
    c:text(x + w - 2 - #net, y, net, won and C.win or (player.net < 0 and C.red or C.text))
    local xs = ui.fan(x + math.floor(w / 2), #player.hand, ui.SMALL_W, w - 2, 1)
    for i, card in ipairs(player.hand) do
      ui.card(c, xs[i], y + 1, card, true)
    end
  end
  local out = {}
  for _, player in ipairs(state.players) do
    if player.folded then out[#out + 1] = short(player.name) .. " " .. ui.signed(player.net) end
  end
  if #out > 0 then c:textCenter(math.floor(c.w / 2), 68, "Folded: " .. table.concat(out, "   "), C.text) end
  if owedNote then c:textCenter(math.floor(c.w / 2), 24, owedNote, C.orange) end
end

return M
