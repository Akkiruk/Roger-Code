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
local BOARD_TOP = 15
local CHIP_COLORS = { "blue", "red", "win", "orange", "panel2", "line" }

local parked = {} -- chips left on the layout when a player walked off, by name

local function now()
  return os.epoch("utc")
end

--- Chip values worth offering: a straight bet the house can cover, and that the player can afford.
local function chipsFor(ctx, table_)
  local room = table_:liabilityRoom()
  local cap = math.min(ctx.balance or 0, math.floor(room / 35))
  if cap < 1 and room >= 1 and (ctx.balance or 0) >= 1 then cap = 1 end
  return limits.chips(cap)
end

local function chipLabel(value)
  return value >= 1000 and (value / 1000 .. "K") or tostring(value)
end

local function bet(ctx, table_, lastWager)
  local c = table_.c
  local seat = ctx.seat
  table_:refreshBalance()
  local chips = chipsFor(ctx, table_)
  local scene = {
    name = "bet",
    deadline = now() + IDLE_MS,
    spots = {},
    undo = {},
    mode = ctx.rouletteMode or "straight",
    chip = ctx.rouletteChip,
  }
  scene.debugState = function()
    return { spots = scene.spots, mode = scene.mode, chip = scene.chip, total = rules.stakeOf(scene.spots), lit = scene.litSpot or false }
  end

  local known = false
  for _, value in ipairs(chips) do known = known or value == scene.chip end
  if not known then scene.chip = chips[math.min(2, #chips)] end

  --- May this wager stand? Says why not on the wall.
  local function allowed(trial)
    if rules.stakeOf(trial) > (ctx.balance or 0) then
      table_:toast("Not enough tokens")
      return false
    end
    if rules.maxWin(trial) > table_:liabilityRoom() then
      table_:toast("The table cannot cover that bet")
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

  local function place(s, id)
    if not s.chip then
      table_:toast("The house cannot cover a bet right now")
      return
    end
    local trial = rules.copyWager(s.spots)
    trial[id] = (trial[id] or 0) + s.chip
    if not allowed(trial) then return end
    remember(s)
    s.spots = trial
    s.litSpot = id
    audio.play(s.chip >= 100 and "chipBig" or "chip")
  end

  -- A player who walked off and came back finds their chips where they left them
  local waiting = seat and parked[seat]
  if waiting then
    parked[seat] = nil
    if rules.stakeOf(waiting) <= (ctx.balance or 0) and rules.maxWin(waiting) <= table_:liabilityRoom() then
      scene.spots = waiting
    end
  end

  function scene.tick(s)
    local left = s.deadline - now()
    if left <= 0 then
      if next(s.spots) then parked[seat] = s.spots end
      s.finished = true
    end
    if left < WARN_MS then s.dirty = true end
  end

  function scene.draw(s)
    local total = rules.stakeOf(s.spots)
    local buttons = ui.newButtons()
    c:clear(C.felt)
    ui.bar(c, ctx, ui.group(total))
    c:text(46, 6, "TOTAL BET", C.mute, C.panel)

    view.modeRow(c, buttons, 9, s.mode, 3, 13, 5)
    local litNums = {}
    local info = view.hint(s.mode)
    if s.litSpot and s.spots[s.litSpot] then
      local spot = rules.spot(s.litSpot)
      for _, n in ipairs(spot.nums) do litNums[n] = true end
      info = rules.describe(s.litSpot) .. "  " .. spot.pay .. " to 1  on it " .. ui.group(s.spots[s.litSpot])
    end
    c:text(74, 9, info, s.litSpot and C.gold or C.text)
    local left = s.deadline - now()
    if left < WARN_MS then
      c:text(74, 13, "Leaving in " .. math.ceil(left / 1000) .. "s. Your chips wait.", C.orange)
    elseif ctx.owedNotice then
      c:text(74, 13, ctx.owedNotice, C.orange)
    end
    c:text(74, 11, "LAST", C.mute)
    view.recentRow(c, 79, 11, table_.keep.recent or {}, 10)

    view.drawBoard(c, BOARD_TOP, { spots = s.spots, mode = s.mode, lit = litNums, litSpot = s.litSpot })
    for _, target in ipairs(view.targets(BOARD_TOP, s.mode)) do buttons[#buttons + 1] = target end

    -- Chips, each in its own colour, with the one in hand filled gold
    local chipSpecs = {}
    for i, value in ipairs(chips) do
      local on = value == s.chip
      chipSpecs[i] = { id = "chip", value = value, label = chipLabel(value), color = on and C.gold or C[CHIP_COLORS[i]],
        textColor = on and C.ink or C.text }
    end
    if #chips == 0 then
      c:textCenter(math.floor(c.w / 2), 58, "The house cannot cover a bet right now.", C.orange)
    else
      ui.actionRow(c, buttons, chipSpecs, 56, 6)
    end
    local x = 4
    for _, spec in ipairs({
      { id = "clear", label = "CLEAR", w = 28, color = C.panel2, disabled = next(s.spots) == nil },
      { id = "undo", label = "UNDO", w = 24, color = C.panel2, disabled = #s.undo == 0 },
      { id = "repeat", label = "REPEAT", w = 34, color = C.panel2, disabled = not lastWager },
      { id = "double", label = "X2", w = 23, color = C.panel2, disabled = next(s.spots) == nil },
    }) do
      spec.x, spec.y, spec.h = x, 63, 6
      ui.button(c, buttons, spec)
      x = x + spec.w + 2
    end
    ui.actionBar(c, buttons, {
      { id = "leave", label = "LEAVE", color = C.red },
      { id = "rules", label = "RULES", color = C.blue },
      { id = "stats", label = "STATS", color = C.blue },
      { id = "spin", label = "SPIN", color = C.win, textColor = C.ink, disabled = total < 1 },
    })
    s.buttons = buttons
  end

  function scene.touch(s, x, y)
    s.deadline = now() + IDLE_MS
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end
    if hit.id == "spot" then
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
    elseif hit.id == "leave" then
      audio.play("tap")
      s.finished = true
    elseif hit.id == "spin" then
      table_:refreshBalance()
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

local function help()
  local lines = {
    "European roulette: one zero, 37 numbers, and one number picked as the wheel starts. Nothing is charged until it lands.",
    "",
    { "HOW TO BET", C.gold },
    "Pick a chip, pick the kind of bet with the buttons along the top, then tap the layout. White dots mark each target in that mode, and the numbers a bet covers light up when you place it.",
    "Red/black, odd/even, 1-18/19-36, the dozens and the 2:1 columns can be tapped in any mode.",
    "UNDO takes back the last move, X2 doubles every stake, and REPEAT lays your last bet again.",
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
  rules = rules,
  view = view,
  stakeOf = rules.stakeOf,
  bet = bet,
  help = help,
}
