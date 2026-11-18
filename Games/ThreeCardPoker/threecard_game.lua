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
  local function readLimit()
    return tableObject:maxBet()
  end
  local maxAnte = readLimit()
  local chips = limits.chips(maxAnte)

  local function wager(s)
    return { ante = s.ante, side = s.side and s.ante or 0 }
  end

  --- The most the Ante may be now: the table limit, and the balance shared by everything this hand can ask for.
  local function allowed(s)
    return tableObject:allowance(maxAnte, s.side and 2 or 1)
  end

  local function clamp(s)
    s.ante = math.max(0, math.min(s.ante, allowed(s) or 0))
  end

  scene.debugState = function()
    local most, reason = allowed(scene)
    return { ante = scene.ante, side = scene.side, max = most or false, reason = reason, tableMax = maxAnte }
  end

  function scene.tick(s)
    local left = s.deadline - now()
    if left <= 0 then s.finished = true end
    if left < WARN_MS then s.dirty = true end
    -- The limit and the balance follow the host and the other tables while the player chooses
    if now() - (s.limitAt or 0) >= 5000 then
      s.limitAt = now()
      maxAnte = readLimit()
      clamp(s)
      s.dirty = true
    end
  end

  function scene.draw(s)
    c:clear(C.felt)
    c:frame(1, 1, c.w, c.h, C.feltDark)
    ui.bar(c, ctx)
    c:bigCenter(cx, ui.TOP, "PLACE YOUR ANTE", C.text, 1)
    c:bigCenter(cx, 16, ui.group(s.ante), C.gold, 2)
    local most, reason = allowed(s)
    local lines = ui.allowance(most, reason, s.ante, "ante")
    c:textCenter(cx, 29, lines[1][1] .. (most and most >= 1 and "   You will need the same again to play" or ""), C[lines[1][2]])
    if lines[2] then c:textCenter(cx, 39, lines[2][1], C[lines[2][2]]) end
    s.buttons = ui.newButtons()
    if maxAnte >= 1 then
      local over = ui.overNote(most, reason)
      ui.button(c, s.buttons, {
        id = "side", x = cx - 36, y = 31, w = 72, h = 7,
        label = s.side and "PAIR PLUS ON" or "PAIR PLUS OFF",
        color = s.side and C.gold or C.panel2, textColor = s.side and C.ink or C.text,
      })
      local specs = {}
      for _, value in ipairs(chips) do
        local label = value >= 1000 and (value / 1000 .. "K") or tostring(value)
        specs[#specs + 1] = { id = "chip", value = value, label = label, color = C.accent, textColor = C.ink,
          disabled = not most or s.ante + value > most, why = over }
      end
      ui.actionRow(c, s.buttons, specs, 43, 11)
      ui.actionRow(c, s.buttons, {
        { id = "clear", label = "CLEAR", color = C.panel2, disabled = s.ante == 0 },
        { id = "double", label = "X2", color = C.panel2, disabled = s.ante == 0 or not most or s.ante >= most,
          why = s.ante > 0 and over or nil },
        { id = "max", label = "MAX", color = C.panel2, disabled = not most or most < 1 or s.ante == most,
          why = most and most >= 1 and "That is already the most" or over },
        { id = "repeat", label = "SAME", color = C.panel2, disabled = not lastWager or not most or most < 1 },
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
      { id = "deal", label = "DEAL", color = C.win, textColor = C.ink, disabled = s.ante < 1,
        why = "Pick a chip first" },
    })
  end

  function scene.touch(s, x, y)
    s.deadline = now() + IDLE_BET_MS
    local hit = ui.hit(s.buttons or {}, x, y)
    if not hit then return end
    if hit.id == "refused" then
      tableObject:toast(hit.why)
    elseif hit.id == "chip" then
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
      s.ante = allowed(s) or 0
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
