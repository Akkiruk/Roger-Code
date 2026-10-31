-- hilo_game.lua
-- Hi-Lo as the casino table sees it. The help is built from the rules, so the two cannot disagree.

local rules = require("hilo_rules")
local view = require("hilo_view")

return {
  id = "hilo",
  title = "HI-LO",
  tagline = "Higher or lower? Every guess is priced from the cards left.",
  felt = "teal",
  dealLabel = "DEAL",
  rules = rules,
  view = view,
  help = function()
    return {
      "One deck, freshly shuffled every round. Aces are high.",
      "Guess whether the next card is higher or lower. An equal rank loses.",
      "",
      "Each guess shows what it pays and how likely it is, worked out from the cards still in the deck.",
      "Cash out after any right guess. A wrong guess loses your bet.",
      ("A streak ends by itself after %d guesses or at x%d."):format(rules.MAX_GUESSES, rules.MAX_MULTIPLE),
      "",
      ("The game returns %d%% of what is bet at every point you can stop, whatever you do."):format(rules.RETURN * 100),
      "",
      "Walk away and the table cashes out for you. Your winnings wait here until you touch it again.",
    }
  end,
}
