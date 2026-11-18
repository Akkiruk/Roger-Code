-- roulette_game.lua
-- Roulette as the casino table sees it: its own bet scene, and help built from the rules so the two cannot disagree.
-- Nothing is charged while chips are on the layout. If the player walks off, the chips wait for them.

local audio = require("lib.casino.audio")
local limits = require("lib.casino.limits")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("roulette_rules")
local view = require("roulette_view")

local C = theme.C

local IDLE_MS = 45000
local WARN_MS = 10000
local UNDO_DEPTH = 60
local LIMIT_EVERY_MS = 5000     -- how often the scene reads the house's limit again
local BOARD_TOP = ui.TOP + 7
local STEPS_Y = 58              -- the three steps, between the layout and the chips
local INFO_X = 74               -- the column right of the mode buttons
local PAD_Y, PAD_H = 60, 7      -- the row of chips and edit buttons, ending clear of the strip above the button band
local PAD_LEFT, PAD_RIGHT = 4, 118
local CHIPS_W = 67              -- chips share this much of the row out between them, and the edit buttons sit at its far end
local PAD_GAP = 3
local CHIP_COLORS = { "blue", "red", "win", "orange", "panel2", "line" }
local MAX_CHIP = "max"          -- the chip that lays as much as may go on the spot tapped

local parked = {} -- chips left on the layout when a player walked off, by name

local function now()
  return os.epoch("utc")
end

--- What may be bet in all: the balance, and the house's room, which an even-money bet uses one for one.
-- A spot that pays more is checked against the room as it goes down.
local function allowance(ctx, room)
  return limits.allowed(ctx.balance, room)
end

--- Chip values worth offering: a straight bet the house can cover, and that the player can afford, then MAX for anything bigger.
local function chipsFor(ctx, room)
  local cap = math.min(ctx.balance or 0, math.floor(room / 35))
  if cap < 1 and room >= 1 and (ctx.balance or 0) >= 1 then cap = 1 end
  local chips = limits.chips(cap)
  if #chips > 0 then chips[#chips + 1] = MAX_CHIP end
  return chips
end

local function chipLabel(value)
  if value == MAX_CHIP then return "MAX" end
  return value >= 1000 and (value / 1000 .. "K") or tostring(value)
end

--- The three steps along the strip over the chips. The one to do next is lit gold, and the ones done are green.
-- Returns the column after the last one.
local function drawSteps(c, y, chip, total)
  local steps = {
    { "1 PICK A CHIP" .. (chip and (": " .. chipLabel(chip)) or ""), chip ~= nil },
    { "2 TAP WHERE TO BET", total > 0 },
    { "3 PRESS SPIN", false },
  }
  local current = 3
  for i, step in ipairs(steps) do
    if not step[2] then
      current = i
      break
    end
  end
  local x = PAD_LEFT
  for i, step in ipairs(steps) do
    local text = "  " .. step[1] .. "  "
    local bg = i == current and C.gold or (step[2] and C.win or C.panel)
    c:rect(x, y - 1, #text, 3, bg)
    c:text(x, y, text, (i == current or step[2]) and C.ink or C.text, bg)
    x = x + #text
    if i < #steps then
      c:text(x, y, " > ", C.text)
      x = x + 3
    end
  end
  return x
end

local function bet(ctx, table_, lastWager)
  local c = table_.c
  local seat = ctx.seat
  table_:refreshBalance()
  local room = table_:liabilityRoom()
  local chips = chipsFor(ctx, room)
  local scene = {
    name = "bet",
    deadline = now() + IDLE_MS,
    limitAt = now(),
    spots = {},
    undo = {},
    mode = ctx.rouletteMode or "straight",
    chip = ctx.rouletteChip,
  }
  scene.debugState = function()
    local most, reason = allowance(ctx, room)
    return { spots = scene.spots, mode = scene.mode, chip = scene.chip, total = rules.stakeOf(scene.spots), lit = scene.litSpot or false,
      max = most or false, reason = reason, room = room }
  end

  local function known(value)
    for _, chip in ipairs(chips) do
      if chip == value then return true end
    end
    return false
  end
  if not known(scene.chip) then scene.chip = chips[math.min(2, #chips)] end

  --- May this wager stand? Says why not on the wall.
  local function allowed(trial)
    local balance = ctx.balance
    if not balance then
      table_:toast("Checking your balance...")
      return false
    end
    if rules.stakeOf(trial) > balance then
      table_:toast("Your balance: " .. ui.group(balance) .. " is the most you can bet")
      return false
    end
    if rules.maxWin(trial) > room then
      table_:toast("Table limit: the house cannot cover that bet")
      return false
    end
    return true
  end

  local function remember(s)
    s.undo[#s.undo + 1] = rules.copyWager(s.spots)
    if #s.undo > UNDO_DEPTH then table.remove(s.undo, 1) end
  end

  local function replace(s, trial, sound)
    if not allowed(trial) then return end
    remember(s)
    s.spots = trial
    audio.play(sound)
  end

  --- The most that can go on one spot now, and what stops it there.
  local function mostOn(s, id)
    local left = math.max(0, (ctx.balance or 0) - rules.stakeOf(s.spots))
    local function fits(amount)
      local trial = rules.copyWager(s.spots)
      trial[id] = (trial[id] or 0) + amount
      return rules.maxWin(trial) <= room
    end
    if fits(left) then return left, "your balance" end
    local low, high = 0, left
    while low < high do
      local mid = math.floor((low + high + 1) / 2)
      if fits(mid) then low = mid else high = mid - 1 end
    end
    return low, "table limit"
  end

  local function place(s, id)
    if not s.chip then
      table_:toast("Table limit: the house cannot cover a bet right now")
      return
    end
    local amount = s.chip
    if amount == MAX_CHIP then
      local reason
      amount, reason = mostOn(s, id)
      if amount < 1 then
        table_:toast(reason == "table limit" and ("Table limit: no more on " .. rules.describe(id))
          or "Your balance: nothing left to bet")
        return
      end
    end
    local trial = rules.copyWager(s.spots)
    trial[id] = (trial[id] or 0) + amount
    if ctx.balance and rules.stakeOf(trial) <= ctx.balance and rules.maxWin(trial) > room then
      local most = mostOn(s, id)
      table_:toast("Table limit: " .. (most > 0 and ("up to " .. ui.group(most) .. " more") or "no more") .. " on " .. rules.describe(id))
      return
    end
    if not allowed(trial) then return end
    remember(s)
    s.spots = trial
    s.litSpot = id
    audio.play(amount >= 100 and "chipBig" or "chip")
  end

  -- A player who walked off and came back finds their chips where they left them
  local waiting = seat and parked[seat]
  if waiting then
    parked[seat] = nil
    if rules.stakeOf(waiting) <= (ctx.balance or 0) and rules.maxWin(waiting) <= room then
      scene.spots = waiting
    end
  end

  function scene.tick(s)
    local time = now()
    local left = s.deadline - time
    if left <= 0 then
      if next(s.spots) then parked[seat] = s.spots end
      s.finished = true
    end
    if left < WARN_MS then s.dirty = true end
    -- The host's balance and the other tables move the room, and the heartbeat reads the player's balance: both shown as they are
    if time - s.limitAt >= LIMIT_EVERY_MS then
      s.limitAt = time
      room = table_:liabilityRoom()
      s.dirty = true
    end
  end

  function scene.draw(s)
    local total = rules.stakeOf(s.spots)
    local most, reason = allowance(ctx, room)
    local buttons = ui.newButtons()
    c:clear(C.felt)
    ui.bar(c, ctx, ui.group(total))
    -- Stacked in the space the bar leaves between its title and the total, however long the total gets
    local captionX = c:bigWidth(ctx.title, 1) + 7
    c:textCenter(captionX, 3, "TOTAL", C.gold, C.panel)
    c:textCenter(captionX, 5, "BET", C.gold, C.panel)

    view.modeRow(c, buttons, ui.TOP, s.mode, 4, 11, 5)
    local litNums = {}
    local info = view.hint(s.mode) .. ", or any outside bet"
    if s.litSpot and s.spots[s.litSpot] then
      local spot = rules.spot(s.litSpot)
      for _, n in ipairs(spot.nums) do litNums[n] = true end
      info = rules.describe(s.litSpot) .. "  pays " .. spot.pay .. ":1  on it " .. ui.group(s.spots[s.litSpot])
    end
    local width = c.w - INFO_X - 1
    c:text(INFO_X, ui.TOP, info:sub(1, width), s.litSpot and C.gold or C.text)
    -- What may be bet, always in view: the whole bet, and what one number can take when the house allows less there
    local lines = ui.allowance(most, reason, total)
    local first = lines[1][1]
    local straight = math.floor(room / 35)
    if most and most >= 1 and straight < most then first = first .. "  1 number: " .. ui.group(straight) end
    c:text(INFO_X, ui.TOP + 2, first:sub(1, width), C[lines[1][2]])
    local left = s.deadline - now()
    if left < WARN_MS then
      c:text(INFO_X, ui.TOP + 4, ("Leaving in " .. math.ceil(left / 1000) .. "s. Your chips wait."):sub(1, width), C.orange)
    elseif lines[2] then
      c:text(INFO_X, ui.TOP + 4, lines[2][1]:sub(1, width), C[lines[2][2]])
    elseif ctx.owedNotice then
      c:text(INFO_X, ui.TOP + 4, ctx.owedNotice:sub(1, width), C.orange)
    end

    view.drawBoard(c, BOARD_TOP, { spots = s.spots, mode = s.mode, lit = litNums, litSpot = s.litSpot })
    for _, target in ipairs(view.targets(BOARD_TOP, s.mode)) do buttons[#buttons + 1] = target end

    local stepsEnd = drawSteps(c, STEPS_Y, s.chip, total)
    local recent = table_.keep.recent or {}
    local count = math.min(#recent, math.floor((c.w - 3 - stepsEnd - 8) / 4))
    if count > 0 then
      local x = c.w - 2 - count * 4
      c:text(x - 5, STEPS_Y, "LAST", C.mute)
      view.recentRow(c, x, STEPS_Y, recent, count)
    end

    -- Chips, each in its own colour, with the one in hand filled gold. A chip bigger than what is left to bet is greyed
    if #chips == 0 then
      c:textCenter(PAD_LEFT + math.floor(CHIPS_W / 2), PAD_Y + 3, (ui.allowance(most, reason, 0))[1][1], C.orange)
    end
    local rest = most and math.max(0, most - total)
    local over = most and ("Only " .. ui.group(rest) .. " left to bet: " .. reason) or "Checking your balance..."
    local chipW = #chips > 0 and math.floor((CHIPS_W - PAD_GAP * (#chips - 1)) / #chips)
    for i, value in ipairs(chips) do
      local on = value == s.chip
      local off = not rest or (value == MAX_CHIP and rest < 1) or (value ~= MAX_CHIP and value > rest)
      ui.button(c, buttons, { id = "chip", value = value, label = on and ("[" .. chipLabel(value) .. "]") or chipLabel(value),
        small = true, x = PAD_LEFT + (i - 1) * (chipW + PAD_GAP), y = PAD_Y, w = chipW, h = PAD_H,
        color = on and C.gold or C[CHIP_COLORS[i]], textColor = on and C.ink or C.text, disabled = off, why = over })
    end
    local x = PAD_RIGHT + 1 - (37 + PAD_GAP * 3) -- the four widths below, and the gaps between them
    for _, spec in ipairs({
      { id = "clear", label = "CLEAR", w = 10, color = C.panel2, disabled = next(s.spots) == nil },
      { id = "undo", label = "UNDO", w = 9, color = C.panel2, disabled = #s.undo == 0 },
      { id = "repeat", label = "REPEAT", w = 11, color = C.panel2, disabled = not lastWager },
      { id = "double", label = "X2", w = 7, color = C.panel2, disabled = next(s.spots) == nil },
    }) do
      spec.x, spec.y, spec.h, spec.small = x, PAD_Y, PAD_H, true
      ui.button(c, buttons, spec)
      x = x + spec.w + PAD_GAP
    end
    ui.actionBar(c, buttons, {
      { id = "leave", label = "LEAVE", color = C.red, small = true },
      { id = "rules", label = "RULES", color = C.blue, small = true },
      { id = "stats", label = "STATS", color = C.blue, small = true },
      { id = "card", label = "CARD", color = C.blue, small = true },
      { id = "spin", label = "SPIN", color = C.win, textColor = C.ink, disabled = total < 1,
        why = "Place a bet first: pick a chip, then tap the layout" },
    })
    s.buttons = buttons
  end

  function scene.touch(s, x, y)
    s.deadline = now() + IDLE_MS
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end
    if hit.id == "refused" then
      table_:toast(hit.why)
    elseif hit.id == "spot" then
      place(s, hit.value)
    elseif hit.id == "chip" then
      s.chip = hit.value
      audio.play("tap")
    elseif hit.id == "mode" then
      s.mode = hit.value
      s.litSpot = nil
      audio.play("tap")
    elseif hit.id == "clear" then
      remember(s)
      s.spots, s.litSpot = {}, nil
      audio.play("tap")
    elseif hit.id == "undo" then
      s.spots = table.remove(s.undo)
      s.litSpot = nil
      audio.play("tap")
    elseif hit.id == "repeat" then
      s.litSpot = nil
      replace(s, rules.copyWager(lastWager), "chip")
    elseif hit.id == "double" then
      local trial = rules.copyWager(s.spots)
      for id, amount in pairs(trial) do trial[id] = amount * 2 end
      s.litSpot = nil
      replace(s, trial, "chipBig")
    elseif hit.id == "rules" then
      audio.play("tap")
      table_:page("RULES", table_.game.help())
      s.deadline = now() + IDLE_MS
    elseif hit.id == "stats" then
      audio.play("tap")
      table_:statsPage()
      s.deadline = now() + IDLE_MS
    elseif hit.id == "card" then
      audio.play("tap")
      table_:playerCard()
      s.deadline = now() + IDLE_MS
    elseif hit.id == "leave" then
      audio.play("tap")
      s.finished = true
    elseif hit.id == "spin" then
      table_:refreshBalance()
      room = table_:liabilityRoom()
      if allowed(s.spots) then
        audio.play("start")
        s.chosen, s.finished = true, true
      end
    end
  end

  table_:run(scene)
  ctx.rouletteMode, ctx.rouletteChip = scene.mode, scene.chip
  table_:refreshBalance()
  if scene.chosen then return scene.spots end
  return nil
end

--- A straight bet on the number that landed: the 35 to 1 the wheel is known for.
local function hitStraight(round)
  return round.state.spots["straight:" .. round.state.number] ~= nil
end

local function help()
  local lines = {
    "European roulette: one zero, 37 numbers, and one number picked as the wheel starts. Nothing is charged until it lands.",
    "",
    { "HOW TO BET", C.gold },
    "1. Pick a chip along the bottom. 2. Tap where to bet. 3. Press SPIN.",
    "The buttons along the top choose what a tap on the numbers means: one number, a split, a street, a corner or a line. White dots mark each target in that mode, and the numbers a bet covers light up when you place it.",
    "Red/black, odd/even, 1-18/19-36, the dozens and the 2:1 columns can be tapped in any mode. Each box says what it pays.",
    "MAX lays as much as you may on the spot you tap. UNDO takes back the last move, CLEAR takes everything off, X2 doubles every stake, and REPEAT lays your last bet again.",
    "The top right says how much you can bet: your balance, or the table limit if that is lower. A spot that pays more, like one number, can take less, because the house must cover your biggest win.",
    "",
    { "WHAT EACH BET PAYS", C.gold },
  }
  for _, kind in ipairs(rules.KINDS) do
    lines[#lines + 1] = ("%s pays %d to 1: %s."):format(kind.label, kind.pay, kind.how)
  end
  local kind = rules.KINDS[1]
  lines[#lines + 1] = ""
  lines[#lines + 1] = "When 0 lands, red, black, odd, even, low, high, the dozens and the columns all lose."
  lines[#lines + 1] = ("Every bet returns %.2f%%: %d numbers would need to pay %d to 1 to be even."):format(
    kind.covers * (kind.pay + 1) / rules.POCKETS * 100, rules.POCKETS, rules.POCKETS - 1)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "The house must be able to cover your biggest possible win. A chip it cannot cover is refused."
  lines[#lines + 1] = "Walk away and nothing is charged. Your chips stay on the layout until you come back."
  return lines
end

return {
  id = "roulette",
  title = "ROULETTE",
  tagline = "One zero, every bet on the layout, and the ball decides.",
  felt = "green",
  demo = {
    wager = function(stream)
      local even = ({ "red", "black", "odd", "even", "low", "high" })[stream:below(6) + 1]
      return { [even] = 50, ["dozen:" .. (stream:below(3) + 1)] = 25, ["straight:" .. stream:below(rules.POCKETS)] = 10 }
    end,
  },
  badges = {
    straight_up = { name = "Straight Up", text = "Hit a number straight up",
      test = function(_, _, round) return hitStraight(round) end },
    zero = { name = "Zero Hero", text = "Hit the zero straight up",
      test = function(_, _, round) return round.state.number == 0 and hitStraight(round) end },
    struck_twice = { name = "Struck Twice", text = "Hit the number that just landed",
      test = function(_, _, round) return round.state.recent[1] == round.state.number and hitStraight(round) end },
  },
  rules = rules,
  view = view,
  stakeOf = rules.stakeOf,
  bet = bet,
  help = help,
}
