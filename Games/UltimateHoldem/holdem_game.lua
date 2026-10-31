-- holdem_game.lua
-- Ultimate Texas Hold'em as the casino table sees it: its own bet scene for the Ante, Blind and Trips.
-- The help is built from the rules, so the two cannot disagree.

local audio = require("lib.casino.audio")
local limits = require("lib.casino.limits")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("holdem_rules")
local view = require("holdem_view")

local C = theme.C
local IDLE_BET_MS = 45000
local WARN_MS = 10000

local function now()
  return os.epoch("utc")
end

local function stakeOf(wager)
  return wager.ante * 2 + wager.side
end

--- Choose an Ante, which the Blind matches, and whether a Trips bet of the same size goes with it. Nothing moves here.
local function chooseBet(ctx, tableObject, lastWager)
  local c = ctx.c
  local cx = math.floor(c.w / 2)
  local scene = { name = "bet", ante = 0, side = false, deadline = now() + IDLE_BET_MS }
  local maxAnte = math.min(tableObject:maxBet(), rules.MAX_ANTE)
  local chips = limits.chips(maxAnte)

  local function wager(s)
    return { ante = s.ante, side = s.side and s.ante or 0 }
  end

  local function clamp(s)
    local balance = ctx.balance or 0
    s.ante = math.min(s.ante, maxAnte, math.floor(balance / (s.side and 3 or 2)))
  end

  function scene.tick(s)
    local left = s.deadline - now()
    if left <= 0 then s.finished = true end
    if left < WARN_MS then s.dirty = true end
  end

  function scene.draw(s)
    c:clear(C.felt)
    c:frame(1, 1, c.w, c.h, C.feltDark)
    ui.bar(c, ctx)
    c:bigCenter(cx, 11, "ANTE AND BLIND", C.text, 1)
    c:bigCenter(cx, 18, ui.group(s.ante) .. " + " .. ui.group(s.ante), C.gold, 2)
    c:textCenter(cx, 30, "Table limit " .. ui.group(maxAnte) .. " each   Raises cost up to 4 Antes more", C.text)
    s.buttons = ui.newButtons()
    if maxAnte < 1 then
      c:textCenter(cx, 44, "The house cannot cover a bet right now.", C.orange)
    else
      ui.button(c, s.buttons, {
        id = "side", x = cx - 30, y = 32, w = 60, h = 8,
        label = s.side and "TRIPS ON" or "TRIPS OFF",
        color = s.side and C.gold or C.panel2, textColor = s.side and C.ink or C.text,
      })
      local specs = {}
      for _, value in ipairs(chips) do
        specs[#specs + 1] = { id = "chip", value = value, label = tostring(value), color = C.accent, textColor = C.ink }
      end
      ui.actionRow(c, s.buttons, specs, 42, 11)
      ui.actionRow(c, s.buttons, {
        { id = "clear", label = "CLEAR", color = C.panel2 },
        { id = "double", label = "X2", color = C.panel2, disabled = s.ante == 0 },
        { id = "max", label = "MAX", color = C.panel2 },
        { id = "repeat", label = "SAME", color = C.panel2, disabled = not lastWager },
      }, 55, 9)
    end
    if ctx.owedNotice then c:textCenter(cx, 66, ctx.owedNotice, C.orange) end
    local left = s.deadline - now()
    if left < WARN_MS then
      c:textCenter(cx, 40, "Leaving in " .. math.ceil(left / 1000) .. "s", C.orange)
    end
    ui.actionBar(c, s.buttons, {
      { id = "leave", label = "LEAVE", color = C.red },
      { id = "rules", label = "RULES", color = C.blue },
      { id = "stats", label = "STATS", color = C.blue },
      { id = "deal", label = "DEAL", color = C.win, textColor = C.ink, disabled = s.ante < 1 },
    })
  end

  function scene.touch(s, x, y)
    s.deadline = now() + IDLE_BET_MS
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end
    if hit.id == "chip" then
      s.ante = s.ante + hit.value
      audio.play(hit.value >= 100 and "chipBig" or "chip")
    elseif hit.id == "side" then
      s.side = not s.side
      audio.play("chip")
    elseif hit.id == "clear" then
      s.ante = 0
      audio.play("tap")
    elseif hit.id == "double" then
      s.ante = s.ante * 2
      audio.play("chip")
    elseif hit.id == "max" then
      s.ante = maxAnte
      audio.play("chipBig")
    elseif hit.id == "repeat" then
      s.ante = lastWager.ante
      s.side = lastWager.side > 0
      audio.play("chip")
    elseif hit.id == "leave" then
      audio.play("tap")
      s.finished = true
    elseif hit.id == "rules" then
      audio.play("tap")
      tableObject:page("RULES", tableObject.game.help())
    elseif hit.id == "stats" then
      audio.play("tap")
      tableObject:statsPage()
    elseif hit.id == "deal" then
      audio.play("start")
      s.chosen, s.finished = true, true
    end
    clamp(s)
  end

  tableObject:run(scene)
  tableObject:refreshBalance()
  if not scene.chosen or scene.ante < 1 then return nil end
  local chosen = wager(scene)
  if stakeOf(chosen) > (ctx.balance or 0) or rules.maxWin(chosen) > tableObject:liabilityRoom() then
    tableObject:toast("Bet too big for the table right now")
    return nil
  end
  return chosen
end

return {
  id = "ultimate-holdem",
  title = "HOLD'EM",
  tagline = "Ultimate Texas Hold'em. The fewer cards you see, the more you can raise.",
  felt = "green",
  -- A round's whole stake at the most: Ante, Blind and Trips. rules.MAX_ANTE keeps each of them survivable.
  capTokens = rules.MAX_ANTE * 3,
  rules = rules,
  view = view,
  stakeOf = stakeOf,
  bet = chooseBet,
  help = function()
    local lines = {
      "One deck, freshly shuffled for every hand. You and the dealer get two cards and share five on the table.",
      "Put up an Ante and an equal Blind. Each hand plays the best five of its seven cards.",
      "",
      { "YOU RAISE ONCE", C.gold },
      "Before the flop: raise 3x or 4x the Ante, or check.",
      "After the flop: raise 2x, or check.",
      "After the river: raise 1x, or fold and lose the Ante and Blind.",
      "The sooner you raise the more you can bet, and the rest of the cards then play out.",
      "",
      { "THE SHOWDOWN", C.gold },
      "The Play bet pays 1 to 1. The dealer needs a pair or better: if not, the Ante comes back.",
      "A tie gives back every bet. Lose, and the Blind and Play go too.",
      "",
      { "THE BLIND: PAID ONLY WHEN YOU WIN. LESSER HANDS GIVE IT BACK", C.gold },
    }
    for _, line in ipairs(rules.BLIND) do
      lines[#lines + 1] = ("%-18s %s"):format(line.name, line.text)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = { "TRIPS: AN OPTIONAL SIDE BET ON YOUR FINAL HAND, EVEN IF YOU FOLD", C.gold }
    for _, line in ipairs(rules.TRIPS) do
      lines[#lines + 1] = ("%-18s %d to 1"):format(line.name, line.pays)
    end
    lines[#lines + 1] = "Turn it on before the deal. It matches your Ante. Anything less loses it."
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("Sound play returns about %.1f%% of the Ante. Trips returns %.1f%%."):format(
      rules.ANTE_RETURN * 100, rules.SIDE_RETURN * 100)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Walk away and the table checks to the river, then folds. It never raises for you."
    return lines
  end,
}
