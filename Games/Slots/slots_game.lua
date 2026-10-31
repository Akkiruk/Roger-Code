-- slots_game.lua
-- Slots as the casino table sees it. The help is built from the rules, so the two cannot disagree.

local rules = require("slots_rules")
local view = require("slots_view")

return {
  id = "slots",
  title = "SLOTS",
  tagline = "Three reels, one shared jackpot.",
  felt = "purple",
  dealLabel = "SPIN",
  rules = rules,
  view = view,
  help = function()
    local lines = {
      ("Three reels of %d stops each, spun independently."):format(rules.STOPS),
      "Pays are the total you get back for each token bet. x1 returns your bet. A pair counts in any position.",
      "",
      { "THE REELS", "4" },
    }
    for _, symbol in ipairs(rules.SYMBOLS) do
      lines[#lines + 1] = ("%s: %d stop%s on each reel. Three pay x%d, any two pay x%d."):format(symbol.name,
        symbol.weight, symbol.weight == 1 and "" or "s", symbol.triple, symbol.pair)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("The pay table returns %.2f%% of what is bet, before the jackpot."):format(rules.exactReturn() * 100)
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("Every bet adds %d%% to the shared jackpot, which starts at %d. Three 7s pay x%d and the jackpot, up to %d times your bet. The jackpot then starts again."):format(
      rules.JACKPOT.share * 100, rules.JACKPOT.seed, rules.SYMBOLS[rules.SEVEN].triple, rules.POT_TIMES)
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("After a win you may collect, or gamble everything on a fair 50/50 flip to double it. Up to %d flips, while the total stays within x%d. Losing a flip loses your bet too."):format(
      rules.GAMBLES, rules.MAX_RETURN)
    lines[#lines + 1] = "The flip changes nothing about the return: it is exactly even."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Walk away and the table collects for you."
    return lines
  end,
}
