-- ui.lua
-- Shared drawing: the bar across the top, buttons, cards, messages. Sizes assume a 6x6 wall (about 121x81).

local deck = require("lib.casino.deck")
local theme = require("lib.casino.theme")

local C = theme.C
local M = {}

M.BAR_H = 8           -- the top bar
M.ACTIONS_H = 12      -- the button rows along the bottom
-- Monitor cells are 2 wide by 3 tall, so a card with real proportions has about as many rows as columns
M.CARD_W, M.CARD_H = 17, 16
M.SMALL_W, M.SMALL_H = 13, 12

local function group(n)
  local text = tostring(math.floor(math.abs(n)))
  local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (n < 0 and "-" or "") .. out
end
M.group = group

--- "1,250" with a sign, for results.
function M.signed(n)
  return (n > 0 and "+" or "") .. group(n)
end

-- ------------------------------------------------------------------ buttons

--- A list of touch regions, rebuilt with every draw so the screen and the touch map cannot disagree.
function M.newButtons()
  return {}
end

--- Draw a button and add its region. spec: x, y, w, h, label, color, textColor, sub, disabled, id.
function M.button(c, list, spec)
  local x, y, w, h = spec.x, spec.y, spec.w, spec.h
  local bg = spec.disabled and C.panel2 or (spec.color or C.blue)
  local fg = spec.disabled and C.mute or (spec.textColor or C.text)
  c:rect(x + 1, y + h, w, 1, C.ink) -- a thin shadow lifts it off the table
  c:rect(x + w, y + 1, 1, h, C.ink)
  c:panel(x, y, w, h, bg, nil)
  local label = tostring(spec.label)
  local cx = x + math.floor(w / 2)
  local scale = (h >= 16 and c:bigWidth(label, 2) <= w - 4) and 2 or 1
  if c:bigWidth(label, scale) <= w then
    local textTop = y + math.floor((h - 6 * scale - (spec.sub and 2 or 0)) / 2) + (scale == 1 and 1 or 0)
    c:bigCenter(cx, textTop, label, fg, scale)
    if spec.sub then c:textCenter(cx, y + h - 2, spec.sub, fg) end
  else
    c:textCenter(cx, y + math.floor(h / 2) - (spec.sub and 1 or 0), label, fg)
    if spec.sub then c:textCenter(cx, y + math.floor(h / 2) + 1, spec.sub, fg) end
  end
  if not spec.disabled then list[#list + 1] = spec end
end

--- The button under a touch, if any.
function M.hit(list, x, y)
  for i = #list, 1, -1 do
    local b = list[i]
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b end
  end
  return nil
end

--- Lay a row of buttons evenly across the screen. specs carry label, color, id, sub, disabled.
function M.actionRow(c, list, specs, y, h)
  local gap = 2
  local margin = 3
  local n = #specs
  local w = math.floor((c.w - margin * 2 - gap * (n - 1)) / n)
  for i, spec in ipairs(specs) do
    spec.x, spec.y, spec.w, spec.h = margin + 1 + (i - 1) * (w + gap), y, w, h
    M.button(c, list, spec)
  end
end

--- The bottom bar, one row of up to five actions.
function M.actionBar(c, list, specs)
  local y = c.h - M.ACTIONS_H + 2
  c:rect(1, y - 2, c.w, M.ACTIONS_H, C.feltDark)
  M.actionRow(c, list, specs, y, 9)
end

-- ------------------------------------------------------------------ the top bar

--- ctx carries title, seat, balance. info is optional text for the middle, such as the bet.
function M.bar(c, ctx, info)
  c:rect(1, 1, c.w, M.BAR_H - 1, C.panel)
  c:rect(1, M.BAR_H - 1, c.w, 1, C.accent)
  c:big(3, 1, ctx.title, C.gold, 1)
  if ctx.seat then
    -- A long reveal sets heldBalance, so the wall does not give away a result the money already reflects
    local shown = ctx.heldBalance or ctx.balance
    local balance = shown and group(shown) or "?"
    local x = c.w - c:bigWidth(balance, 1) - 1
    c:big(x, 1, balance, C.gold, 1)
    c:text(x - #ctx.seat - 2, 2, ctx.seat, C.text)
    if ctx.jackpot then
      local line = "Jackpot " .. group(ctx.jackpot)
      c:text(x - #line - 2, 4, line, C.win)
    end
  end
  if info then c:big(c:bigWidth(ctx.title, 1) + 8, 1, info, C.text, 1) end
end

-- ------------------------------------------------------------------ cards

-- Drawn for cells 2 wide by 3 tall, so they look square on the wall
local SUITS = {
  [0] = { "...#...", "..###..", ".#####.", "### ###", "...#..." },
  [1] = { "...#...", "..###..", ".#####.", "..###..", "...#..." },
  [2] = { ".##.##.", "#######", ".#####.", "..###..", "...#..." },
  [3] = { "...#...", "..###..", ".#####.", "#######", "...#..." },
}
M.SUIT_W, M.SUIT_H = 7, 5

--- Draw a suit symbol, 7x5 cells at scale 1.
function M.suit(c, x, y, suit, color, scale)
  scale = scale or 1
  local rows = SUITS[suit]
  for j = 1, #rows do
    for i = 1, #rows[j] do
      if rows[j]:sub(i, i) == "#" then
        c:rect(x + (i - 1) * scale, y + (j - 1) * scale, scale, scale, color)
      end
    end
  end
end

local function cardFace(c, x, y, w, h, card)
  c:rect(x + 1, y, w - 2, h, C.card)
  c:rect(x, y + 1, w, h - 2, C.card)
  local color = deck.isRed(card) and C.red or C.ink
  c:big(x + 1, y + 1, deck.rankName(card), color, 1)
  M.suit(c, x + w - M.SUIT_W - 1, y + h - M.SUIT_H - 1, deck.suit(card), color, 1)
end

local function cardBack(c, x, y, w, h)
  c:rect(x + 1, y, w - 2, h, C.card)
  c:rect(x, y + 1, w, h - 2, C.card)
  c:rect(x + 1, y + 1, w - 2, h - 2, C.accent)
  for j = 2, h - 3, 2 do
    for i = 2 + (j % 4) / 2, w - 3, 2 do
      c:rect(x + i, y + j, 1, 1, C.feltDark)
    end
  end
end

--- Draw a card, or its back when card is nil. small picks the smaller size.
function M.card(c, x, y, card, small)
  local w, h = small and M.SMALL_W or M.CARD_W, small and M.SMALL_H or M.CARD_H
  c:rect(x + 1, y + h, w - 1, 1, C.feltDark)
  if card == nil then
    cardBack(c, x, y, w, h)
  else
    cardFace(c, x, y, w, h, card)
  end
end

--- An empty place on the felt for a card.
function M.cardSlot(c, x, y, small)
  local w, h = small and M.SMALL_W or M.CARD_W, small and M.SMALL_H or M.CARD_H
  c:frame(x, y, w, h, C.feltLight)
end

--- x positions for n cards centred on cx, overlapping as needed to fit in maxW.
function M.fan(cx, n, cardW, maxW, gap)
  gap = gap or 2
  local step = cardW + gap
  if n > 1 and step * (n - 1) + cardW > maxW then
    step = math.floor((maxW - cardW) / (n - 1))
  end
  local total = step * (n - 1) + cardW
  local left = cx - math.floor(total / 2)
  local xs = {}
  for i = 1, n do xs[i] = left + (i - 1) * step end
  return xs
end

-- ------------------------------------------------------------------ messages

--- A banner over the table. It never clears what is under it, so the final hand stays in view.
function M.banner(c, y, title, detail, color)
  local h = detail and 13 or 11
  c:rect(1, y, c.w, h, C.ink)
  c:rect(1, y, c.w, 1, color)
  c:rect(1, y + h - 1, c.w, 1, color)
  local scale = c:bigWidth(title, 2) <= c.w - 6 and 2 or 1
  c:bigCenter(math.floor(c.w / 2), y + 3 - scale, title, color, scale) -- big titles sit one row higher, clear of the detail
  if detail then c:textCenter(math.floor(c.w / 2), y + h - 2, detail, C.text) end
end

--- Short lines, wrapped to width.
function M.wrap(text, width)
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if #line + #word + 1 > width and line ~= "" then
      lines[#lines + 1] = line
      line = word
    else
      line = line == "" and word or (line .. " " .. word)
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

return M
