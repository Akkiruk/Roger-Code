-- crazyeights_view.lua
-- The table: the counts and the dealer on the left of the top band and the stock, pile and suit on the right of it, your hand
-- below, and the strip under that for what happens next. Three full rows of cards would not leave the strip any room. The whole
-- hand stays above the result banner, and every card keeps a strip at least MIN_STRIP wide.

local deck = require("lib.casino.deck")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("crazyeights_rules")

local C = theme.C
local M = {}

M.MIN_STRIP = 7

local PILE_Y = ui.TOP + 2
local DEALER_Y = PILE_Y + 2   -- its cards are shorter, so they sit level with the middle of the pile
local HAND_Y = 34
local LIFT = 2
local STRIP_Y = 55
local STRIP_H = 10
local ARROW_W = 15
local EDGE = 4                -- the first column on the wall, the last being its mirror
local COUNT_LINES = 9         -- from the DEALER count down to the YOU count
local DEALER_LEFT, DEALER_W = 16, 41   -- the dealer's fan, between the counts and the stock
local RANK_STEP = 7           -- a narrower strip of a dealer's card cannot show a big rank
local PLAY_SECONDS, DRAW_SECONDS = 0.5, 0.24
local SUIT_CHARS = { [0] = 5, [1] = 4, [2] = 3, [3] = 6 } -- clubs, diamonds, hearts, spades

local function copyList(list)
  local out = {}
  for i, value in ipairs(list) do out[i] = value end
  return out
end

function M.new(ctx)
  return { ctx = ctx, player = {}, dealer = 0, stock = 0, say = "" }
end

function M.sync(model, state)
  model.player = copyList(state.player)
  model.dealer = #state.dealer
  model.top = rules.top(state)
  model.under = state.pile[#state.pile - 1]
  model.suit = state.suit
  model.pending = state.pending
  model.stock = #state.stock
  model.say = ""
  model.shown = state.over and copyList(state.dealer) or nil
end

-- ------------------------------------------------------------------ geometry

local function centerX(model)
  return math.floor(model.ctx.c.w / 2)
end

local function pileX(model)
  return model.ctx.c.w - 40
end

local function stockX(model)
  return pileX(model) - 21
end

--- Where the dealer's cards are centred, and so where theirs fly from and to.
local function dealerX()
  return DEALER_LEFT + math.floor(DEALER_W / 2)
end

--- x positions for a fan of the player's cards, wall to wall at the most.
local function handFan(model, n)
  return ui.fan(centerX(model) + 1, n, ui.CARD_W, model.ctx.c.w - (EDGE - 1) * 2, 1)
end

--- The cards on show, with where each sits and how wide a strip of it can be touched.
-- live means it is the player's move, so cards that can go are lifted.
local function handLayout(model, state, live)
  local sorted = rules.sorted(model.player)
  local pages = math.max(1, math.ceil(#sorted / rules.PAGE))
  local page = math.min(state.page, pages - 1)
  local list = {}
  for i = page * rules.PAGE + 1, math.min(#sorted, (page + 1) * rules.PAGE) do list[#list + 1] = sorted[i] end
  local xs = handFan(model, math.max(1, #list))
  local cards = {}
  for i, card in ipairs(list) do
    local legal = live and rules.canPlay(state, card)
    if state.choosing == card then legal = true end
    local w = i < #list and math.min(xs[i + 1] - xs[i], ui.CARD_W) or ui.CARD_W
    cards[i] = { card = card, x = xs[i], y = legal and HAND_Y - LIFT or HAND_Y, w = w, legal = legal }
  end
  return cards, page, pages
end

--- Does the next or the last page hold a card that can be played?
local function legalBeyond(model, state, page)
  local sorted = rules.sorted(model.player)
  local before, after = false, false
  for i, card in ipairs(sorted) do
    local cardPage = math.floor((i - 1) / rules.PAGE)
    if rules.canPlay(state, card) then
      before = before or cardPage < page
      after = after or cardPage > page
    end
  end
  return before, after
end

local function isLive(state, anim)
  return anim == nil and not state.over and not state.choosing
end

local SUIT_W, SUIT_X = 26, { 5, 34, 63, 92 }

--- Touchable parts of the table. The scene asks only when it is the player's move.
function M.regions(model, state)
  local list = {}
  if state.choosing then
    for suit = 0, 3 do
      list[#list + 1] = { id = "suit" .. suit, x = SUIT_X[suit + 1], y = STRIP_Y - 1, w = SUIT_W, h = STRIP_H + 1 }
    end
    return list
  end
  local cards, page, pages = handLayout(model, state, true)
  for _, placed in ipairs(cards) do
    if placed.legal then
      list[#list + 1] = { id = "p" .. placed.card, x = placed.x, y = placed.y, w = placed.w, h = ui.CARD_H }
    end
  end
  if page > 0 then list[#list + 1] = { id = "pagePrev", x = EDGE, y = STRIP_Y - 1, w = ARROW_W, h = STRIP_H + 1 } end
  if page < pages - 1 then
    list[#list + 1] = { id = "pageNext", x = model.ctx.c.w - EDGE + 1 - ARROW_W, y = STRIP_Y - 1, w = ARROW_W, h = STRIP_H + 1 }
  end
  return list
end

-- ------------------------------------------------------------------ events

local function say(model, text)
  model.say = text
end

local function cardName(card)
  return deck.rankName(card) .. " of " .. rules.SUIT_NAMES[deck.suit(card)]:lower()
end

function M.event(model, ev)
  if ev.type == "deal" then
    model.player, model.dealer, model.top, model.under, model.shown = {}, 0, nil, nil, nil
    model.pending = 0
    model.say = ""
    return 1.5, "deal"
  elseif ev.type == "think" then
    say(model, "Dealer is thinking")
    return 0.5
  elseif ev.type == "play" then
    if ev.who == "player" then
      -- The card leaves from where it sat in the fan
      model.flyFrom = centerX(model)
      for _, placed in ipairs((handLayout(model, { page = model.page or 0 }, false))) do
        if placed.card == ev.card then model.flyFrom = placed.x end
      end
      for i, card in ipairs(model.player) do
        if card == ev.card then
          table.remove(model.player, i)
          break
        end
      end
    else
      model.flyFrom = dealerX() - math.floor(ui.CARD_W / 2)
      model.dealer = math.max(0, model.dealer - 1)
      say(model, "Dealer plays the " .. cardName(ev.card))
    end
    return PLAY_SECONDS, "deal"
  elseif ev.type == "draw" then
    if ev.who == "dealer" then say(model, "Dealer draws") end
    return DRAW_SECONDS, "chip"
  elseif ev.type == "reshuffle" then
    say(model, "The pile is shuffled back into the stock")
    return 0.7, "flip"
  elseif ev.type == "pass" then
    say(model, (ev.who == "player" and "You pass" or "Dealer passes"))
    return 0.6
  elseif ev.type == "reveal" then
    model.shown = copyList(ev.cards)
    return 1.1, "flip"
  end
  return 0.1
end

function M.commit(model, ev)
  if ev.type == "deal" then
    model.player = copyList(ev.player)
    model.dealer = ev.dealer
    model.top = ev.top
    model.suit = ev.suit
    model.stock = ev.stock
  elseif ev.type == "play" then
    model.under = model.top
    model.top = ev.card
    model.suit = ev.suit
    model.pending = ev.pending
    if deck.rank(ev.card) == 8 and ev.who == "dealer" then
      say(model, "Dealer plays a wild and names " .. rules.SUIT_NAMES[ev.suit])
    end
  elseif ev.type == "draw" then
    model.stock = math.max(0, model.stock - 1)
    if ev.who == "player" then
      model.player[#model.player + 1] = ev.card
    else
      model.dealer = model.dealer + 1
    end
    model.pending = 0
  elseif ev.type == "reshuffle" then
    model.stock = ev.left
    model.under = nil
  end
end

-- ------------------------------------------------------------------ drawing

local function lerp(a, b, t)
  return math.floor(a + (b - a) * t + 0.5)
end

local function ease(t)
  return 1 - (1 - t) * (1 - t)
end

--- Draw a card of the hand, with its suit under its rank so it reads with only the left strip showing.
local function handCard(c, placed)
  ui.card(c, placed.x, placed.y, placed.card, false)
  if placed.w and placed.w < ui.CARD_W then
    -- The next card hides this one's corner pip: clear what would peek out, and edge the strip so cards stay apart
    c:rect(placed.x + 8, placed.y + 10, placed.w - 8, 5, C.card)
    c:rect(placed.x + placed.w - 1, placed.y + 1, 1, ui.CARD_H - 2, C.mute)
  end
  ui.suit(c, placed.x + 1, placed.y + 7, deck.suit(placed.card), deck.isRed(placed.card) and C.red or C.ink, 1)
  if placed.legal then
    c:rect(placed.x, placed.y + ui.CARD_H, (placed.w or ui.CARD_W) - 1, 1, C.win)
  end
end

local function drawDealer(c, model, anim)
  local cx = dealerX()
  c:text(EDGE, PILE_Y, "DEALER", C.mute)
  c:big(EDGE, PILE_Y + 2, tostring(model.shown and #model.shown or model.dealer), C.text, 1)
  if model.shown then
    -- With the player's hand gone, the turned cards spread out where it was
    local away = #model.player == 0
    local y = away and HAND_Y or DEALER_Y
    local xs = ui.fan(away and centerX(model) + 1 or cx, math.max(1, #model.shown), ui.SMALL_W,
      away and c.w - (EDGE - 1) * 2 or DEALER_W, 1)
    local count = #model.shown
    if anim and anim.ev.type == "reveal" then count = math.ceil(anim.t * count) end
    for i, card in ipairs(model.shown) do
      ui.card(c, xs[i], y, i <= count and card or nil, true)
      local step = xs[i + 1] and xs[i + 1] - xs[i] or ui.SMALL_W
      if step < ui.SMALL_W and i <= count then
        -- Overlapped: the suit moves under the rank, in the monitor font's own suit characters. A strip too thin for the big rank
        -- has the rank in those characters too.
        local color = deck.isRed(card) and C.red or C.ink
        local tight = step < RANK_STEP
        c:rect(xs[i] + 1, y + (tight and 1 or 6), step - 1, tight and 10 or 5, C.card)
        c:rect(xs[i] + step - 1, y + 1, 1, ui.SMALL_H - 2, C.mute)
        if tight then c:text(xs[i] + 1, y + 2, deck.rankName(card):sub(1, math.max(0, step - 2)), color, C.card) end
        c:text(xs[i] + 1, y + (tight and 4 or 8), string.char(SUIT_CHARS[deck.suit(card)]), color, C.card)
      end
    end
  else
    local n = model.dealer
    if anim and anim.ev.type == "deal" then n = math.min(7, math.floor(anim.t * 14 / 2)) end
    local xs = ui.fan(cx, math.max(1, n), ui.SMALL_W, DEALER_W, 1)
    for i = 1, n do ui.card(c, xs[i], DEALER_Y, nil, true) end
    if model.dealer == 1 and not anim then
      c:text(xs[1] + ui.SMALL_W + 3, DEALER_Y + math.floor(ui.SMALL_H / 2), "LAST CARD", C.orange)
    end
  end
end

local function drawCenter(c, model)
  ui.cardSlot(c, stockX(model), PILE_Y, false)
  if model.stock > 0 then ui.card(c, stockX(model), PILE_Y, nil, false) end
  c:rect(stockX(model) + 5, PILE_Y + 7, 7, 3, C.ink)
  c:textCenter(stockX(model) + 8, PILE_Y + 8, tostring(model.stock), C.text, C.ink)
  ui.cardSlot(c, pileX(model), PILE_Y, false)
  if model.under then ui.card(c, pileX(model) - 1, PILE_Y, model.under, false) end
  if model.top then ui.card(c, pileX(model), PILE_Y, model.top, false) end

  -- The suit in force, large, because after a wild it is not the suit on the pile
  if model.suit then
    local x, y = pileX(model) + 22, PILE_Y + 1
    local wild = model.top and deck.rank(model.top) == 8
    c:panel(x, y, 18, 14, wild and C.card or C.feltDark, C.felt)
    ui.suit(c, x + 2, y + 3, model.suit, (model.suit == 1 or model.suit == 2) and C.red or (wild and C.ink or C.text), 2)
    c:textCenter(x + 9, y + 1, wild and "NAMED" or "SUIT", wild and C.ink or C.mute)
  end
end

local function drawFlying(c, model, anim)
  if not anim then return end
  local ev, t = anim.ev, ease(anim.t)
  if ev.type == "play" then
    local fromY = ev.who == "player" and HAND_Y or DEALER_Y
    ui.card(c, lerp(model.flyFrom or pileX(model), pileX(model), t), lerp(fromY, PILE_Y, t), ev.card, false)
  elseif ev.type == "draw" then
    local toY = ev.who == "player" and HAND_Y or DEALER_Y
    local toX = (ev.who == "player" and centerX(model) or dealerX()) - math.floor(ui.CARD_W / 2)
    ui.card(c, stockX(model) + math.floor((toX - stockX(model)) * t), lerp(PILE_Y, toY, t), nil, false)
  end
end

local function drawChooser(c, state)
  local counts = { 0, 0, 0, 0 }
  for _, card in ipairs(state.player) do
    if card ~= state.choosing and deck.rank(card) ~= 8 then
      counts[deck.suit(card) + 1] = counts[deck.suit(card) + 1] + 1
    end
  end
  for suit = 0, 3 do
    local x, y = SUIT_X[suit + 1], STRIP_Y - 1
    local red = suit == 1 or suit == 2
    c:rect(x + 1, y + STRIP_H + 1, SUIT_W, 1, C.ink)
    c:rect(x + SUIT_W, y + 1, 1, STRIP_H + 1, C.ink)
    c:panel(x, y, SUIT_W, STRIP_H + 1, C.card, nil)
    ui.suit(c, x + 2, y + 3, suit, red and C.red or C.ink, 1)
    c:text(x + 11, y + 4, rules.SUIT_NAMES[suit], red and C.red or C.ink, C.card)
    c:text(x + 11, y + 6, "you hold " .. counts[suit + 1], C.line, C.card)
  end
end

local function drawStrip(c, model, state, anim, page, pages)
  local cx = centerX(model)
  if state.choosing then
    drawChooser(c, state)
    return
  end
  local live = isLive(state, anim)
  if pages > 1 then
    local before, after = false, false
    if live then before, after = legalBeyond(model, state, page) end
    local function arrow(x, label, on, hot)
      if not on then return end
      c:rect(x, STRIP_Y - 1, ARROW_W, STRIP_H + 1, hot and C.win or C.panel2)
      c:bigCenter(x + math.floor(ARROW_W / 2), STRIP_Y, label, hot and C.ink or C.text, 2)
    end
    arrow(EDGE, "<", page > 0, before)
    arrow(c.w - EDGE + 1 - ARROW_W, ">", page < pages - 1, after)
    c:textCenter(cx, STRIP_Y + 8, "Page " .. (page + 1) .. " of " .. pages, C.text)
  end
  if live then
    if state.pending > 0 then
      local answers = #rules.legal(state, "player") > 0
      c:bigCenter(cx, STRIP_Y, "TAKE " .. state.pending, C.orange, 1)
      c:textCenter(cx, STRIP_Y + 6, answers and "or answer with a 2. An 8 cannot stop it." or
        (state.pending >= rules.CAP and "The stack is at its limit, so a 2 cannot answer." or "Only a 2 could answer it."), C.text)
    else
      local any = #rules.legal(state, "player") > 0
      c:bigCenter(cx, STRIP_Y, any and "YOUR TURN" or "NOTHING TO PLAY", any and C.gold or C.orange, 1)
      c:textCenter(cx, STRIP_Y + 6, any and "Tap a lit card, or draw." or "Draw a card.", C.text)
    end
  elseif model.pending and model.pending > 0 then
    c:bigCenter(cx, STRIP_Y, "+" .. model.pending, C.orange, 1)
    c:textCenter(cx, STRIP_Y + 6, model.say, C.text)
  elseif model.say ~= "" then
    c:textCenter(cx, STRIP_Y + 3, model.say, C.text)
  end
end

function M.draw(c, model, state, anim)
  c:clear(C.felt)
  local dealing = anim and anim.ev.type == "deal"
  drawDealer(c, model, anim)
  drawCenter(c, model)

  local cards, page, pages = handLayout(model, state, isLive(state, anim))
  model.page = page
  if dealing then
    -- Seven cards land one by one, then the first card turns
    local shown = {}
    local sorted = rules.sorted(anim.ev.player)
    local xs = handFan(model, #sorted)
    for i, card in ipairs(sorted) do
      if i <= math.floor(anim.t * 14 / 2 + 0.5) then shown[#shown + 1] = { card = card, x = xs[i], y = HAND_Y } end
    end
    cards, pages = shown, 1
  end
  for _, placed in ipairs(cards) do handCard(c, placed) end
  c:text(EDGE, PILE_Y + COUNT_LINES, "YOU", C.mute)
  c:big(EDGE, PILE_Y + COUNT_LINES + 2, tostring(#model.player), C.text, 1)

  drawStrip(c, model, state, anim, page, pages)
  drawFlying(c, model, anim)
end

return M
