-- slots_view.lua
-- The cabinet: a marquee with the pot, three reel windows on a pay line, the pay table beside them, and a strip
-- below for what is happening, which the result banner covers at the end.
-- The reels scroll the real 52-stop strip from the rules, so the symbols flashing past keep the real weights.

local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("slots_rules")

local C = theme.C
local M = {}

local SPRITE_H = 13
local STEP = SPRITE_H + 1            -- rows from one symbol to the next on the reel
local REEL_W, REEL_GAP = 22, 3
local CAB_X, CAB_Y, CAB_W, CAB_H = 5, ui.TOP, 78, ui.BANNER_Y - ui.TOP - 1
local WIN_Y, WIN_H = CAB_Y + 9, 32   -- the reel window
local LINE_Y = WIN_Y + 9             -- the top of the symbol on the pay line
local PAY_X, PAY_W = 86, 32
local PAY_ROWS = { 0, 6, 12, 17, 22, 28, 34 }  -- a row each in pay order: the bar's own blank rows do for its gaps
local STRIP_Y = ui.BANNER_Y          -- what is happening; the result banner lands here
local LAST_STOP = { 0.9, 1.5, 2.2 }  -- seconds into the spin at which each reel lands
local SPIN_SPEED = 18                -- stops a second at full speed
local BRAKE = 0.35                   -- seconds a reel takes to slow down

-- Bold pictures for cells 2 wide by 3 tall, so each reads as a square about 40x39 in real proportions
local SPRITES = {
  seven = {
    "..kkkkkkkkkkkkkkkk..",
    ".krrrrrrrrrrrrrrrrk.",
    ".krggggggggggggggrk.",
    ".krrrrrrrrrrrrgrrrk.",
    ".kkkkkkkkkkkrrgrrk..",
    "..........krrrgrk...",
    ".........krrrgrk....",
    "........krrrgrk.....",
    ".......krrrgrrk.....",
    "......krrrgrrk......",
    "......krrgrrrk......",
    "......krrrrrrk......",
    "......kkkkkkkk......",
  },
  diamond = {
    "....kkkkkkkkkkkk....",
    "...kttbbttbbbbbbk...",
    "..kttbbttbbbbbbbbk..",
    ".kttbbttbbbbbbbbbbk.",
    "kkkkkkkkkkkkkkkkkkkk",
    ".kbbtbbbbbbbbbbmbbk.",
    "..kbbtbbbbbbbbmbbk..",
    "...kbbtbbbbbbmbbk...",
    "....kbbtbbbbmbbk....",
    ".....kbbtbbmbbk.....",
    "......kbbtmbbk......",
    ".......kbbbbk.......",
    ".........kk.........",
  },
  bell = {
    ".........kk.........",
    "........kggk........",
    ".......kggggk.......",
    "......kgtgggok......",
    ".....kgtggggook.....",
    ".....kgtggggook.....",
    "....kgtggggggook....",
    "....kgtggggggook....",
    "...kgggggggggoook...",
    "..kggggggggggooook..",
    "..kkkkkkkkkkkkkkkk..",
    ".......kooook.......",
    "........kkkk........",
  },
  bar = {
    "....................",
    "kkkkkkkkkkkkkkkkkkkk",
    "kggggggggggggggggggk",
    "kgkkkkkkkkkkkkkkkkgk",
    "kgktttkkkttkkttttkgk",
    "kgktkktkkttkkktkktgk",
    "kgktttkkttttkktttkgk",
    "kgktkktkkkkkkktktkgk",
    "kgktttkktkktkktkktgk",
    "kgkkkkkkkkkkkkkkkkgk",
    "kggggggggggggggggggk",
    "kkkkkkkkkkkkkkkkkkkk",
    "....................",
  },
  cherry = {
    "............kkk.....",
    "...........kGGGkkk..",
    "..........kkGGGGGGk.",
    ".........k.k..kkkk..",
    "........k...k.......",
    "...kkkkk.....kkkkk..",
    "..krrrrrk...krrrrrk.",
    ".krtrrrrrk.krtrrrrrk",
    ".krtrrrrrk.krtrrrrrk",
    ".krrrrrrrk.krrrrrrrk",
    ".krrrrrrrk..krrrrrk.",
    "..krrrrrk....kkkkk..",
    "...kkkkk............",
  },
  lemon = {
    "....................",
    ".......kkkkkk.......",
    "....kkkggggggkkk....",
    "..kkgggttggggggokk..",
    ".kgggttggggggggoook.",
    "kkgggtgggggggggoookk",
    "kggggggggggggggooook",
    "kkgggggggggggggoookk",
    ".kggggggggggggoooook",
    "..kkggggggggooookk..",
    "....kkkggggookkk....",
    ".......kkkkkk.......",
    "....................",
  },
  melon = {
    "....................",
    "....................",
    "kkkkkkkkkkkkkkkkkkkk",
    "krrrkrrrrkrrrrkrrrrk",
    "krrrrrrrrrrrrrrrrrrk",
    ".krrrrkrrrrrrkrrrrk.",
    ".ktrrrrrrrrrrrrrrtk.",
    "..ktrrrrkrrkrrrrtk..",
    "..kGttrrrrrrrrttGk..",
    "...kGGttttttttGGk...",
    "....kkGGGGGGGGkk....",
    "......kkkkkkkk......",
    "....................",
  },
}
M.SPRITES = SPRITES

-- The same seven, small, for the pay table
local MINI = {
  seven = { ".rrrrrrr.", "....rrr..", "...rrr...", "..rrr....", "..rrr...." },
  diamond = { "..bbbbb..", ".btbbbbb.", "..bbbbb..", "...bbb...", "....b...." },
  bell = { "....g....", "...ggg...", "..ggggo..", ".gggggoo.", "....k...." },
  bar = { ".........", "kkkkkkkkk", "kgggggggk", "kkkkkkkkk", "........." },
  cherry = { ".....GG..", "....k....", "...k.k...", ".rr...rr.", ".rr...rr." },
  lemon = { "...ggg...", ".ggggggo.", "ggggggggo", ".ggggggo.", "...ggg..." },
  melon = { "rrkrrrkrr", "rrrrrrrrr", ".rrkrrkr.", "..GGGGG..", "........." },
}
M.MINI = MINI

local PAINT = {
  k = C.ink, r = C.red, g = C.gold, o = C.orange, t = C.text, b = C.blue, m = C.mute, G = C.win,
}

-- ------------------------------------------------------------------ small helpers

local function clock()
  return os.epoch and os.epoch("utc") or os.time() * 1000
end

--- Blinks between two states, a few times a second, from the wall clock: it needs no event, so it blocks nothing.
local function blink(rate)
  return math.floor(clock() / (rate or 220)) % 2 == 0
end

--- A sprite cut off at the window's top and bottom.
local function drawClipped(c, x, y, rows, top, bottom)
  for j = 1, #rows do
    local row = y + j - 1
    if row >= top and row <= bottom then
      local line = rows[j]
      for i = 1, #line do
        local color = PAINT[line:sub(i, i)]
        if color then c:rect(x + i - 1, row, 1, 1, color) end
      end
    end
  end
end

--- How far a reel still has to travel, in stops, with `left` seconds to go: full speed, then a smooth brake.
local function travel(left)
  if left <= 0 then return 0 end
  if left >= BRAKE then return SPIN_SPEED * (left - BRAKE / 2) end
  return SPIN_SPEED * left * left / (2 * BRAKE)
end

local function reelX(reel)
  return CAB_X + 3 + (reel - 1) * (REEL_W + REEL_GAP)
end

-- ------------------------------------------------------------------ the model

function M.new(ctx)
  return { ctx = ctx, stops = { 1, 1, 1 }, payout = 0, landed = 3 }
end

function M.sync(model, state)
  model.stops = { state.stops[1], state.stops[2], state.stops[3] }
  model.payout = state.lost and 0 or state.payout
  model.landed = 3
  model.flash = state.times > 1 and not state.lost
end

function M.event(model, ev)
  if ev.type == "reel" then
    if ev.reel == 1 then
      model.landed, model.flash = 0, false
      return LAST_STOP[1], "spin"
    end
    return LAST_STOP[ev.reel] - LAST_STOP[ev.reel - 1], "stop"
  elseif ev.type == "win" then
    model.flash = true
    if ev.jackpot then return 2.5, "bigWin" end
    return ev.hold and 1.2 or 0.35, ev.times >= 16 and "bigWin" or "win"
  elseif ev.type == "flip" then
    return 1.1, "flip"
  end
  return 0.3, "chipBig"
end

function M.commit(model, ev)
  if ev.type == "reel" then
    model.landed = ev.reel
  elseif ev.type == "flip" then
    model.payout = ev.amount
    model.flash = ev.won
  end
end

-- ------------------------------------------------------------------ drawing

local function drawReel(c, reel, stop, left)
  local x = reelX(reel)
  local away = travel(left)
  local whole = math.floor(away)
  local slide = math.floor((away - whole) * STEP)
  c:rect(x, WIN_Y, REEL_W, WIN_H, C.card)
  local top, bottom = WIN_Y, WIN_Y + WIN_H - 1
  for offset = -2, 2 do
    local at = (stop - whole + offset - 1) % rules.STOPS + 1
    local symbol = rules.SYMBOLS[rules.STRIP[at]]
    drawClipped(c, x + 1, LINE_Y + offset * STEP + slide, SPRITES[symbol.id], top, bottom)
  end
  -- The curve of the drum
  c:rect(x, WIN_Y, REEL_W, 1, C.mute)
  c:rect(x, bottom, REEL_W, 1, C.mute)
end

local function drawCabinet(c, model, lit)
  c:rect(CAB_X, CAB_Y, CAB_W, CAB_H, C.panel)
  c:frame(CAB_X, CAB_Y, CAB_W, CAB_H, C.accent)
  -- Lights that chase round the marquee all the time, and race on a win
  local beat = math.floor(clock() / (lit and 90 or 260))
  for i = 0, 18 do
    local on = (i + beat) % 3 == 0
    local x = CAB_X + 2 + i * 4
    c:rect(x, CAB_Y + 1, 2, 1, on and (lit and C.win or C.gold) or C.panel2)
  end
  local pot = model.ctx.jackpot or rules.JACKPOT.seed
  local line = "JACKPOT " .. ui.group(pot)
  c:bigCenter(CAB_X + math.floor(CAB_W / 2), CAB_Y + 3, line, C.gold, 1)
end

--- The pay line: markers at both ends, and a rule above and below the symbols that count.
local function drawPayLine(c, state, lit)
  local color = C.gold
  if lit and blink() then color = C.text end
  local left, right = reelX(1), reelX(3) + REEL_W
  for _, y in ipairs({ LINE_Y - 1, LINE_Y + SPRITE_H }) do
    c:rect(left, y, right - left, 1, color)
  end
  c:rect(left - 2, LINE_Y + 4, 2, 5, color)
  c:rect(right, LINE_Y + 4, 2, 5, color)

  if lit and state.symbol then
    -- A frame round each symbol that paid
    for reel = 1, 3 do
      if state.symbols[reel] == state.symbol then
        c:frame(reelX(reel), LINE_Y - 1, REEL_W, SPRITE_H + 2, blink() and C.win or C.gold)
      end
    end
  end
end

local function drawPayTable(c, state, lit)
  c:panel(PAY_X, CAB_Y, PAY_W, CAB_H, C.panel, C.felt)
  local tripleEnd, pairEnd = PAY_X + 22, PAY_X + 30  -- the columns of numbers, by the column after each
  local top = CAB_Y + 3
  c:text(PAY_X + 2, CAB_Y + 1, "PAYS x", C.gold)
  c:text(tripleEnd - 7, CAB_Y + 1, "3 alike", C.mute)
  c:text(pairEnd - 5, CAB_Y + 1, "any 2", C.mute)
  c:rect(PAY_X + 2, top, 13, CAB_H - 4, C.card)
  for i, symbol in ipairs(rules.SYMBOLS) do
    local y = top + PAY_ROWS[i]
    local hot = lit and state.symbol == i
    if hot then c:rect(PAY_X + 15, y, PAY_W - 16, 5, blink() and C.panel2 or C.panel) end
    c:sprite(PAY_X + 4, y, MINI[symbol.id], PAINT)
    local tripleLit = hot and state.kind == "triple"
    local pairLit = hot and state.kind == "pair"
    local triple, pair = tostring(symbol.triple), tostring(symbol.pair)
    c:text(tripleEnd - #triple, y + 2, triple, tripleLit and C.win or C.gold)
    c:text(pairEnd - #pair, y + 2, pair, pairLit and C.win or C.text)
  end
end

local function drawCoin(c, cx, y, t, won)
  -- The coin narrows and widens as it turns, and lands in the colour of the result
  local turns = 5
  local width = math.max(2, math.floor(math.abs(math.cos(t * turns * math.pi)) * 20))
  local landed = t > 0.82
  if landed then width = 20 end
  local face = landed and (won and C.win or C.red) or C.gold
  local lift = landed and 0 or math.floor(math.sin(t / 0.82 * math.pi) * 3)
  local x = cx - math.floor(width / 2)
  c:rect(x + 2, y - lift, width - 4, 1, C.ink)
  c:rect(x, y + 1 - lift, width, 9, C.ink)
  c:rect(x + 2, y + 10 - lift, width - 4, 1, C.ink)
  if width > 4 then
    c:rect(x + 1, y + 1 - lift, width - 2, 9, face)
    if landed then c:bigCenter(cx, y + 3, won and "x2" or "X", C.ink, 1) end
  end
end

--- A word that should fill the strip, at full size if the wall is wide enough for it.
local function headline(c, cx, text, color)
  if c:bigWidth(text, 2) <= c.w - 8 then
    c:bigCenter(cx, STRIP_Y + 1, text, color, 2)
  else
    c:bigCenter(cx, STRIP_Y + 3, text, color, 1)
  end
end

local function drawStrip(c, model, state, anim)
  local cx = math.floor(c.w / 2)
  local kind = anim and anim.ev.type
  if kind == "reel" then
    local a, b = state.symbols[1], state.symbols[2]
    if model.landed == 2 and a == b then
      -- Text only: the reel keeps its time and its odds
      local symbol = rules.SYMBOLS[a]
      c:bigCenter(cx, STRIP_Y + 3, "TWO " .. symbol.plural .. "...", C.gold, 1)
      c:textCenter(cx, STRIP_Y + 10, "Third reel to come", C.text)
    else
      c:bigCenter(cx, STRIP_Y + 4, "GOOD LUCK", C.feltLight, 1)
    end
  elseif kind == "flip" then
    drawCoin(c, cx, STRIP_Y + 3, anim.t, anim.ev.won)
    c:big(5, STRIP_Y + 1, "DOUBLE", C.gold, 1)
    c:big(5, STRIP_Y + 8, ui.group(model.payout * 2), C.text, 1)
    local right = c.w - 3
    if anim.t > 0.82 then
      local word = anim.ev.won and "DOUBLED" or "LOST"
      c:big(right - c:bigWidth(word, 1), STRIP_Y + 1, word, anim.ev.won and C.win or C.red, 1)
    else
      c:big(right - c:bigWidth("OR", 1), STRIP_Y + 1, "OR", C.gold, 1)
      c:big(right - c:bigWidth("NOTHING", 1), STRIP_Y + 8, "NOTHING", C.gold, 1)
    end
  elseif model.landed == 3 and not state.over and not kind then
    -- The choice: the buttons are live under this, and the flash needs no event
    local text = ui.group(model.payout)
    headline(c, cx, "WIN " .. text, blink(300) and C.win or C.gold)
    local left = rules.gamblesLeft(state)
    c:textCenter(cx, STRIP_Y + 12, ("Collect it, or gamble it on a fair flip. %d flip%s left."):format(left,
      left == 1 and "" or "s"), C.text)
  elseif kind == "win" then
    local color = blink(150) and C.win or C.gold
    if anim.ev.jackpot then
      headline(c, cx, "JACKPOT", color)
      c:textCenter(cx, STRIP_Y + 12, "+" .. ui.group(anim.ev.amount), C.gold)
    else
      headline(c, cx, "WIN " .. ui.group(anim.ev.amount), color)
    end
  end
end

--- The idle screen: three reels that show a different line every few seconds.
function M.attract(c, t)
  local cx = math.floor(c.w / 2)
  local top = 53
  for reel = 1, 3 do
    local x = cx - 37 + (reel - 1) * 25
    c:rect(x - 1, top - 1, REEL_W + 2, SPRITE_H + 3, C.gold)
    c:rect(x, top, REEL_W, SPRITE_H + 1, C.card)
    local at = (math.floor(t / 2) * (reel + 3) + reel * 11) % rules.STOPS + 1
    c:sprite(x + 1, top + 1, SPRITES[rules.SYMBOLS[rules.STRIP[at]].id], PAINT)
  end
end

function M.draw(c, model, state, anim)
  c:clear(C.felt)
  c:frame(1, 1, c.w, c.h, C.feltDark)

  local spinning = anim and anim.ev.type == "reel"
  local seconds = 0
  if spinning then
    local reel = anim.ev.reel
    local start = reel == 1 and 0 or LAST_STOP[reel - 1]
    seconds = start + (LAST_STOP[reel] - start) * anim.t
  end
  local lit = model.flash and not spinning and model.landed == 3

  drawCabinet(c, model, lit)
  for reel = 1, 3 do
    local left = spinning and (LAST_STOP[reel] - seconds) or 0
    if reel <= model.landed then left = 0 end
    drawReel(c, reel, model.stops[reel], left)
  end
  drawPayLine(c, state, lit)
  drawPayTable(c, state, lit)
  drawStrip(c, model, state, anim)
end

return M
