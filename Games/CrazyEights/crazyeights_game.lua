-- crazyeights_game.lua
-- Crazy Eights as the casino table sees it. The help is built from the rules, so the two cannot disagree.

local rules = require("crazyeights_rules")
local view = require("crazyeights_view")

return {
  id = "crazyeights",
  title = "CRAZY EIGHTS",
  tagline = "Wild 8s, stacking 2s, one hand against the dealer.",
  felt = "purple",
  dealLabel = "DEAL",
  capTokens = 5000,
  rules = rules,
  view = view,
  help = function()
    return {
      ("One deck, %d cards each, and you play first. Empty your hand before the dealer does."):format(rules.HAND),
      "",
      "On your turn play one card that matches the suit or the rank on the pile, or play an 8.",
      "8s are wild: they go on anything except a draw stack, and you name the suit that follows. An 8 that is your last card needs no suit.",
      "",
      ("A 2 makes the next player draw %d, unless they answer with a 2 of their own. Stacks grow by %d up to +%d. At +%d no more 2s can be played and the stack must be taken."):format(
        rules.PENALTY, rules.PENALTY, rules.CAP, rules.CAP),
      "An 8 does NOT stop a draw stack. Only a 2 does.",
      "",
      "Or tap DRAW: you take one card and your turn ends, even if that card could be played. You may draw whenever you like. Taking a stack also ends your turn.",
      "When the stock runs out the pile is shuffled back in, leaving its top card. If nobody can move at all the hand ends and the fewer cards wins.",
      ("A hand still going after %d turns is called the same way. Equal hands push and your bet comes back."):format(rules.MAX_TURNS),
      "A first card that is an 8 or a 2 goes back under the stock.",
      "",
      ("A win pays %.2f times your bet, so %d tokens win %d. Winnings round down. A loss costs your bet."):format(
        rules.PAY, 100, rules.maxWin(100)),
      "The dealer plays from what it can see, never from your cards or the stock.",
      "",
      "Walk away and the table plays your hand for you. The result waits here until you touch it again.",
    }
  end,
}
