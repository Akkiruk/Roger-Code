-- horseracing_view.lua
-- The race card you bet on, and the race. The race only tells the order the rules already drew: every horse's run
-- comes from rules.position, so the last frame is that order exactly.

local audio = require("lib.casino.audio")
local rng = require("lib.casino.rng")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("horseracing_rules")

local C = theme.C
local M = {}

local RACE_SECONDS = 14
local LINE_SECONDS = 0.9
local IDLE_BET_MS = 45000
local WARN_MS = 10000

-- Track geometry: six lanes between two rails, then the strip the result banner lands on. The far rail takes the last
-- lane's spare row, so the track ends a clear row above the banner
local LANE_H = 7
local RAIL_Y = ui.TOP
local LANES_Y = RAIL_Y + 1
local FAR_RAIL_Y = LANES_Y + 6 * LANE_H - 1
local STRIP_Y = ui.BANNER_Y
local NOSE_X = 100              -- where the leader's nose runs on the wall
local GATE_X = 22               -- where the noses start
local CELLS_PER_UNIT = 0.45
local POST_EVERY = 50

local HORSE_COLOR = { C.red, C.blue, C.gold, C.win, C.card, C.ink }
local HORSE_TEXT = { C.text, C.text, C.ink, C.ink, C.ink, C.text }
local CHIPS = { 5, 10, 25, 100, 500, 1000 }

-- The bet scene, top to bottom: the tabs, a line of captions, the card, the chips, and a line of what is on the card
local LEFT, RIGHT = 5, 117       -- the same margins as the button rows
local TABS_Y, TABS_H = ui.TOP, 5
local CAPTION_Y = TABS_Y + TABS_H + 4
local CARD_Y = CAPTION_Y + 2
local BADGE_W = 8
local CHIPS_Y, CHIPS_H = 58, 7
local NOTE_Y = 67                -- the last row before the strip the table keeps for itself
local BADGE_STEP = 11            -- a row of badges, as in the last winners and the running order

M.COLORS = HORSE_COLOR

-- A horse in a gallop, nose to the right, for cells 2 wide by 3 tall. b body, d dark, s silks, j jockey's cap
local GALLOP_W = 17
local GALLOP = {
  {
    "........jj.......",
    ".......sss....bb.",
    "d.....sssss..bbbd",
    ".dbbbbbsssbbbbb..",
    "..bbbbbbbbbbb....",
    "..b.bb....bb.b...",
  },
  {
    "........jj.......",
    ".......sss....bb.",
    "dd....sssss..bbbd",
    "..bbbbbsssbbbbb..",
    "..bbbbbbbbbbb....",
    ".b...bb..bb...b..",
  },
  {
    "........jj.......",
    ".......sss....bb.",
    ".d....sssss..bbbd",
    "ddbbbbbsssbbbbb..",
    "..bbbbbbbbbbb....",
    "...bb.b..b.bb....",
  },
  {
    "........jj.......",
    ".......sss....bb.",
    "d.....sssss..bbbd",
    ".dbbbbbsssbbbbb..",
    "..bbbbbbbbbbb....",
    "..bb...bb...bb...",
  },
}
M.GALLOP = GALLOP

local function ordinal(n)
  return n .. (n == 1 and "st" or n == 2 and "nd" or n == 3 and "rd" or "th")
end

--- A multiple for small spaces: x4.20, x42.5, x425.
local function multipleText(hundredths)
  if hundredths < 1000 then return ("x%d.%02d"):format(math.floor(hundredths / 100), hundredths % 100) end
  if hundredths < 10000 then return ("x%d.%d"):format(math.floor(hundredths / 100), math.floor(hundredths / 10) % 10) end
  return "x" .. math.floor(hundredths / 100)
end
M.multipleText = multipleText

--- The number on a horse's colours.
local function badge(c, x, y, horse, h)
  c:rect(x, y, BADGE_W, h, HORSE_COLOR[horse])
  c:textCenter(x + math.floor(BADGE_W / 2), y + math.floor((h - 1) / 2), tostring(horse), HORSE_TEXT[horse])
end

local function clock()
  return os.epoch and os.epoch("utc") or os.time() * 1000
end

-- ------------------------------------------------------------------ the bet scene

local function betKey(kind, a, b)
  return kind .. ":" .. a .. (b and (":" .. b) or "")
end

--- The card as a wager: plain tables, in a fixed order, with no empty bets.
local function wagerOf(s)
  local bets = {}
  for _, kind in ipairs(rules.KINDS) do
    for horse = 1, rules.HORSES do
      local amount = s.chips[betKey(kind, horse)]
      if amount then bets[#bets + 1] = { kind = kind, a = horse, amount = amount } end
    end
  end
  for a = 1, rules.HORSES do
    for b = 1, rules.HORSES do
      local amount = s.chips[betKey("exacta", a, b)]
      if amount then bets[#bets + 1] = { kind = "exacta", a = a, b = b, amount = amount } end
    end
  end
  return { race = s.race, bets = bets }
end

--- One bet on the card: its odds, and once a chip lands, what is on it under them.
local function drawCell(c, s, x, y, w, h, key, hundredths)
  local amount = s.chips[key]
  local cx = x + math.floor(w / 2)
  c:rect(x, y, w, h, amount and C.gold or C.panel2)
  local text = multipleText(hundredths)
  if amount then
    c:textCenter(cx, y + 1, text, C.ink)
    c:textCenter(cx, y + h - 2, amount >= 1000 and (amount / 1000 .. "K") or tostring(amount), C.ink)
  else
    c:textCenter(cx, y + math.floor((h - 1) / 2), text, C.text)
  end
  s.buttons[#s.buttons + 1] = { id = "cell", value = key, x = x, y = y, w = w, h = h, label = text }
end

local function drawWinCard(c, s, prices)
  local headers = { "WIN  1st", "PLACE  1st or 2nd", "SHOW  top 3" }
  local columnW, gap = 24, 3
  local columnX = RIGHT + 1 - 3 * columnW - 2 * gap
  local rowH, rowStep = 5, 6
  local nameX = LEFT + BADGE_W + 2
  local chance = rules.chances(s.race.strengths)
  for i in ipairs(rules.KINDS) do
    c:textCenter(columnX + (i - 1) * (columnW + gap) + math.floor(columnW / 2), CAPTION_Y, headers[i], C.gold)
  end
  for horse = 1, rules.HORSES do
    local y = CARD_Y + (horse - 1) * rowStep
    badge(c, LEFT, y, horse, rowH)
    c:text(nameX, y + 1, s.race.names[horse], C.text)
    c:text(nameX, y + 3, ("Wins %d in 100"):format(math.floor(chance.win[horse] * 100 + 0.5)), C.mute)
    for i, kind in ipairs(rules.KINDS) do
      drawCell(c, s, columnX + (i - 1) * (columnW + gap), y, columnW, rowH, betKey(kind, horse), prices[kind][horse])
    end
  end
end

local function drawExactaCard(c, s, prices)
  c:text(LEFT, CAPTION_Y, "FIRST down, SECOND across: both, in that order", C.gold)
  local cellW, cellH, gap, rowStep = 12, 4, 3, 5
  local left = RIGHT + 1 - 6 * cellW - 5 * gap
  local rowsY = CARD_Y + cellH + 1
  local nameX = LEFT + BADGE_W + 2
  for second = 1, rules.HORSES do
    local x = left + (second - 1) * (cellW + gap)
    c:rect(x, CARD_Y, cellW, cellH, HORSE_COLOR[second])
    c:textCenter(x + math.floor(cellW / 2), CARD_Y + 1, tostring(second), HORSE_TEXT[second])
  end
  for first = 1, rules.HORSES do
    local y = rowsY + (first - 1) * rowStep
    badge(c, LEFT, y, first, cellH)
    c:text(nameX, y + 1, s.race.names[first]:match("%S+"):sub(1, 10), C.text)
    for second = 1, rules.HORSES do
      local x = left + (second - 1) * (cellW + gap)
      if first == second then
        c:rect(x, y, cellW, cellH, C.panel)
      else
        drawCell(c, s, x, y, cellW, cellH, betKey("exacta", first, second), prices.exacta[first][second])
      end
    end
  end
end

--- The bet scene: one race card, chips on any number of bets. Returns the wager, or nil when the player leaves.
function M.bet(ctx, tbl, lastWager)
  local _ = lastWager
  local c = tbl.c
  local race = rules.newRace(rng.new(rng.freshSeed(ctx.seat)))
  local prices = rules.prices(race.strengths)
  local scene = { name = "bet", race = race, chips = {}, chip = nil, tab = "card",
    deadline = clock() + IDLE_BET_MS }
  local cx = math.floor(c.w / 2)
  local room = tbl:liabilityRoom()    -- asks the vault, so only after a touch, not every frame

  scene.debugState = function() return { race = race, stake = rules.stake(wagerOf(scene)), bets = wagerOf(scene).bets } end

  local function chipChoices()
    local list = {}
    for _, value in ipairs(CHIPS) do
      if value <= math.max(ctx.balance or 0, 0) then list[#list + 1] = value end
    end
    return list
  end

  function scene.tick(s)
    local left = s.deadline - clock()
    if left <= 0 then s.finished = true end
    if left < WARN_MS then s.dirty = true end
  end

  function scene.draw(s)
    c:clear(C.felt)
    c:frame(1, 1, c.w, c.h, C.feltDark)
    ui.bar(c, ctx)
    s.buttons = ui.newButtons()

    -- The two sides of the card, and how the last races went
    ui.button(c, s.buttons, { id = "tab", value = "card", label = "WIN PLACE SHOW", x = LEFT, y = TABS_Y, w = 24, h = TABS_H,
      small = true, color = s.tab == "card" and C.accent or C.panel2, textColor = s.tab == "card" and C.ink or C.text })
    ui.button(c, s.buttons, { id = "tab", value = "exacta", label = "EXACTA", x = LEFT + 28, y = TABS_Y, w = 13, h = TABS_H,
      small = true, color = s.tab == "exacta" and C.accent or C.panel2, textColor = s.tab == "exacta" and C.ink or C.text })
    local recent = tbl.keep.recent or {}
    if #recent > 0 then
      local recentX = RIGHT + 1 - 5 * BADGE_STEP - BADGE_W
      c:text(recentX - 7, TABS_Y + 2, "Last", C.mute)
      for i, horse in ipairs(recent) do
        if i <= 6 then badge(c, recentX + (i - 1) * BADGE_STEP, TABS_Y, horse, TABS_H) end
      end
    end

    if s.tab == "card" then drawWinCard(c, s, prices) else drawExactaCard(c, s, prices) end

    -- What a tap puts down
    local specs = {}
    local choices = chipChoices()
    if not s.chip or s.chip > (ctx.balance or 0) then s.chip = choices[math.min(2, #choices)] end
    for _, value in ipairs(choices) do
      local label = value >= 1000 and (value / 1000 .. "K") or tostring(value)
      local chosen = value == s.chip
      specs[#specs + 1] = { id = "chip", value = value, label = label, color = chosen and C.gold or C.panel2,
        textColor = chosen and C.ink or C.text }
    end
    specs[#specs + 1] = { id = "clear", label = "CLEAR", color = C.panel2, small = true }
    if #choices > 0 then ui.actionRow(c, s.buttons, specs, CHIPS_Y, CHIPS_H) end

    local wager = wagerOf(s)
    local stake = rules.stake(wager)
    local maxWin = rules.maxWin(wager)
    local left = s.deadline - clock()
    if #choices == 0 then
      c:textCenter(cx, CHIPS_Y + math.floor(CHIPS_H / 2), ("It takes %d tokens to bet here."):format(rules.MIN_BET), C.orange)
    elseif maxWin > room then
      c:textCenter(cx, NOTE_Y, "The house cannot cover that card. Take something off.", C.orange)
    elseif left < WARN_MS then
      c:textCenter(cx, NOTE_Y, "Leaving in " .. math.ceil(left / 1000) .. "s", C.orange)
    else
      c:textCenter(cx, NOTE_Y, ("On the card %s   Best case +%s   Each tap adds %s"):format(ui.group(stake),
        ui.group(maxWin), ui.group(s.chip or 0)), C.text)
    end

    ui.actionBar(c, s.buttons, {
      { id = "leave", label = "LEAVE", color = C.red, small = true },
      { id = "rules", label = "RULES", color = C.blue, small = true },
      { id = "stats", label = "STATS", color = C.blue, small = true },
      { id = "card", label = "CARD", color = C.blue, small = true },
      { id = "deal", label = "RACE", color = C.win, textColor = C.ink,
        disabled = stake < 1 or stake > (ctx.balance or 0) or maxWin > room },
    })
  end

  function scene.touch(s, x, y)
    s.deadline = clock() + IDLE_BET_MS
    room = tbl:liabilityRoom()
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end
    if hit.id == "cell" then
      local amount = s.chip or 0
      if amount < 1 then return end
      if rules.stake(wagerOf(s)) + amount > (ctx.balance or 0) then
        tbl:toast("That is more than your balance")
        return
      end
      s.chips[hit.value] = (s.chips[hit.value] or 0) + amount
      audio.play(amount >= 100 and "chipBig" or "chip")
    elseif hit.id == "chip" then
      s.chip = hit.value
      audio.play("tap")
    elseif hit.id == "tab" then
      s.tab = hit.value
      audio.play("tap")
    elseif hit.id == "clear" then
      s.chips = {}
      audio.play("tap")
    elseif hit.id == "leave" then
      audio.play("tap")
      s.finished = true
    elseif hit.id == "rules" then
      audio.play("tap")
      tbl:page("RULES", tbl.game.help())
    elseif hit.id == "stats" then
      audio.play("tap")
      tbl:statsPage()
    elseif hit.id == "card" then
      audio.play("tap")
      tbl:playerCard()
      s.deadline = clock() + IDLE_BET_MS
    elseif hit.id == "deal" then
      audio.play("start")
      s.chosen, s.finished = true, true
    end
  end

  tbl:run(scene)
  tbl:refreshBalance()
  if not scene.chosen then return nil end
  local wager = wagerOf(scene)
  local stake = rules.stake(wager)
  if stake < 1 or stake > (ctx.balance or 0) or rules.maxWin(wager) > tbl:liabilityRoom() then return nil end
  return wager
end

-- ------------------------------------------------------------------ the race

--- Where the eye rests: the gate at first, then the leader held near the right of the wall.
local function camera(t)
  local run = math.min(1, t / 0.15)
  return GATE_X + math.floor((NOSE_X - GATE_X) * run)
end

--- Slower through the last stretch, so the finish takes its time.
local function warp(t)
  if t < 0.8 then return t * 1.1 end
  return 0.88 + (t - 0.8) * 0.6
end

--- What the caller says, worked out once from the positions, so it never disagrees with the picture.
local function commentary(state)
  local calls = { { t = 0, text = "And they're off!" } }
  local leader, lastCall = nil, 0
  for step = 1, 100 do
    local t = step / 100
    local best, bestAt = nil, -1
    for horse = 1, rules.HORSES do
      local at = rules.position(state, horse, t)
      if at > bestAt then best, bestAt = horse, at end
    end
    if best ~= leader and t - lastCall >= 0.12 and t < 0.86 then
      local form = leader and "%s takes the lead!" or "%s breaks in front"
      calls[#calls + 1] = { t = t, text = form:format(rules.label(state, best)) }
      leader, lastCall = best, t
    end
  end
  calls[#calls + 1] = { t = 0.87, text = "Into the final stretch!" }
  calls[#calls + 1] = { t = 0.97, text = state.photo and "Neck and neck to the line!" or
    (rules.label(state, state.order[1]) .. " has it!") }
  return calls
end

function M.new(ctx)
  return { ctx = ctx, finished = true, t = 1 }
end

function M.sync(model, state)
  model.finished, model.t = true, 1
  model.calls = commentary(state)
end

function M.event(model, ev)
  if ev.type == "race" then
    model.finished, model.t = false, 0
    return RACE_SECONDS, "start"
  end
  model.finished, model.t, model.flash = true, 1, true
  return LINE_SECONDS, "stop"
end

function M.commit(model, ev)
  if ev.type == "line" then model.flash = false end
  model.finished, model.t = true, 1
end

local function drawHorse(c, x, y, horse, frame)
  local rows = GALLOP[frame]
  -- Dark bays, and a grey under the black silks so number 6 stands out from its own colours
  local body = horse == 6 and C.mute or C.ink
  c:sprite(x, y, rows, { b = body, d = body, s = HORSE_COLOR[horse], j = horse == 5 and C.red or C.card })
  c:text(x + 8, y + 2, tostring(horse), HORSE_TEXT[horse], HORSE_COLOR[horse])
end

--- The idle screen: the field galloping past, again and again.
function M.attract(c, t)
  for horse = 1, 6 do
    local lane = (horse - 1) % 3
    local x = math.floor((t * (11 + horse) + horse * 37) % (c.w + 24)) - 22
    drawHorse(c, x, 54 + lane * 8, horse, math.floor(t * 6 + horse) % #GALLOP + 1)
  end
end

local function drawTrack(c, camX, leaderAt, t)
  c:rect(1, RAIL_Y, c.w, LANES_Y - RAIL_Y, C.card)
  for lane = 1, 6 do
    c:rect(1, LANES_Y + (lane - 1) * LANE_H, c.w, LANE_H, lane % 2 == 0 and C.felt or C.feltLight)
  end
  c:rect(1, FAR_RAIL_Y, c.w, 1, C.card)
  -- Posts race past on both rails, each a world distance from the start, so speed reads from them
  local firstPost = math.floor((leaderAt - camX / CELLS_PER_UNIT) / POST_EVERY) - 1
  local lastPost = math.ceil((leaderAt + (c.w - camX) / CELLS_PER_UNIT) / POST_EVERY) + 1
  for post = firstPost, lastPost do
    local at = post * POST_EVERY
    local x = camX + math.floor((at - leaderAt) * CELLS_PER_UNIT)
    if at >= 0 and at < rules.DISTANCE then
      c:rect(x, RAIL_Y, 1, 1, C.red)
      c:rect(x, FAR_RAIL_Y, 1, 1, C.red)
      if at % 200 == 0 then
        local to = tostring(rules.DISTANCE - at)
        c:text(x + 1, FAR_RAIL_Y, to, C.ink, C.card)
      end
    end
  end
  -- The start gate, left behind, and the line with its chequers
  local gateX = camX + math.floor((0 - leaderAt) * CELLS_PER_UNIT)
  if gateX >= 1 and t < 0.3 then c:rect(gateX, LANES_Y, 1, 6 * LANE_H, C.card) end
  local lineX = camX + math.floor((rules.DISTANCE - leaderAt) * CELLS_PER_UNIT)
  if lineX <= c.w then
    for y = RAIL_Y, FAR_RAIL_Y do
      local even = y % 2 == 0
      c:rect(lineX, y, 1, 1, even and C.card or C.ink)
      c:rect(lineX + 1, y, 1, 1, even and C.ink or C.card)
    end
  end
end

--- The last frame's words in each lane: place, and what that horse did for the player's bets.
local function drawLaneResults(c, state)
  local earned = {}
  for _, bet in ipairs(state.bets) do
    if bet.paid > 0 then
      local horse = bet.a
      earned[horse] = (earned[horse] or 0) + bet.paid
    end
  end
  for lane = 1, rules.HORSES do
    local y = LANES_Y + (lane - 1) * LANE_H + 3
    local rank = state.rankOf[lane]
    local line = ordinal(rank) .. "  #" .. lane .. " " .. state.race.names[lane]
    c:text(LEFT, y, line, rank == 1 and C.gold or C.text)
    if earned[lane] then c:text(LEFT + #line + 3, y, "pays " .. ui.group(earned[lane]), C.win) end
  end
end

--- The running order, a commentary line, and the player's bets, in small type under the track. width is how far across
-- the bets may run.
local function drawStrip(c, model, state, t, order, width)
  local badgeY = STRIP_Y + 1
  c:text(LEFT, badgeY + 2, "Running order", C.mute)
  for place, horse in ipairs(order) do
    badge(c, 21 + (place - 1) * BADGE_STEP, badgeY, horse, 5)
  end
  -- How much of the race is left, along the same row
  local barX, barW = 87, 31
  c:rect(barX, badgeY + 2, barW, 1, C.feltDark)
  c:rect(barX, badgeY + 2, math.floor(barW * math.min(1, t)), 1, C.gold)
  c:rect(barX + barW - 1, badgeY + 1, 1, 3, C.card)
  local text = ""
  for _, call in ipairs(model.calls or {}) do
    if call.t <= t then text = call.text end
  end
  c:text(LEFT, STRIP_Y + 8, text, C.gold)
  local parts = {}
  for _, bet in ipairs(state.bets) do
    local name = rules.KIND_NAMES[bet.kind]
    parts[#parts + 1] = name .. " #" .. bet.a .. (bet.b and ("-" .. bet.b) or "") .. " " .. ui.group(bet.amount)
  end
  local line = "Your bets: " .. table.concat(parts, ", ")
  for i, part in ipairs(ui.wrap(line, width)) do
    if i <= 3 then c:text(LEFT, STRIP_Y + 10 + i, part, C.text) end
  end
end

function M.draw(c, model, state, anim)
  c:clear(C.felt)
  c:frame(1, 1, c.w, c.h, C.feltDark)
  local raceT = 1
  if anim and anim.ev.type == "race" then raceT = warp(anim.t) end

  local places, leaderAt = {}, 0
  for horse = 1, rules.HORSES do
    places[horse] = rules.position(state, horse, raceT)
    if places[horse] > leaderAt then leaderAt = places[horse] end
  end
  local camX = camera(raceT)
  drawTrack(c, camX, leaderAt, raceT)

  local order = {}
  for horse = 1, rules.HORSES do
    order[horse] = horse
    local x = camX + math.floor((places[horse] - leaderAt) * CELLS_PER_UNIT) - GALLOP_W
    local y = LANES_Y + (horse - 1) * LANE_H
    local stride = raceT >= 1 and 1 or (math.floor(raceT * 160 + horse * 3) % 4) + 1
    drawHorse(c, math.max(4, x), y, horse, stride)
  end
  table.sort(order, function(a, b) return places[a] > places[b] end)

  if raceT >= 1 then drawLaneResults(c, state) end
  -- The result banner takes this space once the race is run. The photo sign takes the right of the bottom rows, so the
  -- bets wrap short of it while it is up
  local photo = anim and anim.ev.type == "race" and raceT > 0.93 and state.photo
  local photoX = RIGHT - 1 - c:bigWidth("PHOTO FINISH", 1)
  if anim then
    drawStrip(c, model, state, raceT, raceT >= 1 and state.order or order, photo and photoX - 2 - 3 - LEFT or RIGHT - LEFT + 1)
  end

  if photo then
    c:rect(photoX - 2, STRIP_Y + 7, c:bigWidth("PHOTO FINISH", 1) + 4, 7, C.ink)
    c:big(photoX, STRIP_Y + 8, "PHOTO FINISH", C.gold, 1)
  end
  if model.flash and anim and anim.t < 0.35 then
    -- The camera at the line goes off
    c:rect(1, LANES_Y, c.w, 6 * LANE_H, C.card)
  end
end

return M
