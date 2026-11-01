-- threecard_game.lua
-- 3 Card Poker as the casino table sees it: its own bet scene for the Ante and the Pair Plus side bet.
-- The help is built from the rules, so the two cannot disagree.

local audio = require("lib.casino.audio")
local limits = require("lib.casino.limits")
local poker = require("lib.casino.poker")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")
local rules = require("threecard_rules")
local view = require("threecard_view")

local C = theme.C
local IDLE_BET_MS = 45000
local WARN_MS = 10000

local function now()
  return os.epoch("utc")
end

local function stakeOf(wager)
  return wager.ante + wager.side
end

--- Choose an Ante, and whether a Pair Plus bet of the same size goes with it. Nothing moves here.
local function chooseBet(ctx, tableObject, lastWager)
  local c = ctx.c
  local cx = math.floor(c.w / 2)
  local scene = { name = "bet", ante = 0, side = false, deadline = now() + IDLE_BET_MS }
  local maxAnte = tableObject:maxBet()
  local chips = limits.chips(maxAnte)

  local function wager(s)
    return { ante = s.ante, side = s.side and s.ante or 0 }
  end

  local function clamp(s)
    local balance = ctx.balance or 0
    s.ante = math.min(s.ante, maxAnte, s.side and math.floor(balance / 2) or balance)
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
    c:bigCenter(cx, ui.TOP, "PLACE YOUR ANTE", C.text, 1)
    c:bigCenter(cx, 16, ui.group(s.ante), C.gold, 2)
    c:textCenter(cx, 29, "Table limit " .. ui.group(maxAnte) .. "   You will need the same again to play", C.text)
    s.buttons = ui.newButtons()
    if maxAnte < 1 then
      c:textCenter(cx, 46, "The house cannot cover a bet right now.", C.orange)
    else
      ui.button(c, s.buttons, {
        id = "side", x = cx - 36, y = 31, w = 72, h = 7,
        label = s.side and "PAIR PLUS ON" or "PAIR PLUS OFF",
        color = s.side and C.gold or C.panel2, textColor = s.side and C.ink or C.text,
      })
      local specs = {}
      for _, value in ipairs(chips) do
        local label = value >= 1000 and (value / 1000 .. "K") or tostring(value)
        specs[#specs + 1] = { id = "chip", value = value, label = label, color = C.accent, textColor = C.ink }
      end
      ui.actionRow(c, s.buttons, specs, 43, 11)
      ui.actionRow(c, s.buttons, {
        { id = "clear", label = "CLEAR", color = C.panel2 },
        { id = "double", label = "X2", color = C.panel2, disabled = s.ante == 0 },
        { id = "max", label = "MAX", color = C.panel2 },
        { id = "repeat", label = "SAME", color = C.panel2, disabled = not lastWager },
      }, 57, 9)
    end
    if ctx.owedNotice then c:textCenter(cx, 41, ctx.owedNotice, C.orange) end
    local left = s.deadline - now()
    if left < WARN_MS then
      c:textCenter(cx, 40, "Leaving in " .. math.ceil(left / 1000) .. "s", C.orange)
    end
    ui.actionBar(c, s.buttons, {
      { id = "leave", label = "LEAVE", color = C.red, small = true },
      { id = "rules", label = "RULES", color = C.blue, small = true },
      { id = "stats", label = "STATS", color = C.blue, small = true },
      { id = "card", label = "CARD", color = C.blue, small = true },
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
    elseif hit.id == "card" then
      audio.play("tap")
      tableObject:playerCard()
      s.deadline = now() + IDLE_BET_MS
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

local function pair(line)
  return ("%-18s %d to 1"):format(line.name, line.pays)
end

--- The hand they kept, whatever the dealer held. A folded hand is not a hand played.
local function played(round, category)
  return not round.state.folded and poker.threeCategory(round.state.playerScore) == category
end

return {
  id = "three-card-poker",
  title = "3 CARD POKER",
  tagline = "Three cards each. Beat the dealer's hand or fold.",
  felt = "burgundy",
  demo = { wager = function() return { ante = 100, side = 50 } end },
  badges = {
    straight_flush = { name = "Straight Flush", text = "Play a straight flush",
      test = function(_, _, round) return played(round, poker.T_STRAIGHT_FLUSH) end },
    trips = { name = "Three Alike", text = "Play three of a kind",
      test = function(_, _, round) return played(round, poker.T_TRIPS) end },
  },
  rules = rules,
  view = view,
  stakeOf = stakeOf,
  bet = chooseBet,
  help = function()
    local lines = {
      "One deck, freshly shuffled for every hand. You and the dealer get three cards each.",
      "Put up an Ante, then look at your cards: FOLD loses the Ante, PLAY bets the same again.",
      "Three cards rank: straight flush, three of a kind, straight, flush, pair, high card.",
      "",
      { "THE DEALER", C.gold },
      ("The dealer needs Queen high or better. If not, the Ante pays 1 to 1 and Play comes back."):format(),
      "If the dealer qualifies, a better hand wins both 1 to 1 and a worse one loses both. A tie gives them back.",
      "",
      { "ANTE BONUS: PAID WHEN YOU PLAY, WHATEVER THE DEALER HOLDS", C.gold },
    }
    for _, line in ipairs(rules.ANTE_BONUS) do lines[#lines + 1] = pair(line) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = { "PAIR PLUS: AN OPTIONAL SIDE BET ON YOUR HAND ALONE, EVEN IF YOU FOLD", C.gold }
    for _, line in ipairs(rules.PAIR_PLUS) do lines[#lines + 1] = pair(line) end
    lines[#lines + 1] = "Turn it on before the deal. It matches your Ante."
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("Playing Queen, 6, 4 or better returns %.2f%% of the Ante. Pair Plus returns %.2f%%."):format(
      rules.ANTE_RETURN * 100, rules.SIDE_RETURN * 100)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Walk away and the table plays Queen, 6, 4 or better for you and folds the rest."
    return lines
  end,
}
