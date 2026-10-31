-- blackjack_game.lua
-- Blackjack as the casino table sees it. The help is built from the rules, so the two cannot disagree.

local rules = require("blackjack_rules")
local view = require("blackjack_view")

return {
  id = "blackjack",
  title = "BLACKJACK",
  tagline = ("Blackjack pays %d to %d. Dealer hits soft %d."):format(rules.NATURAL_PAYS[1], rules.NATURAL_PAYS[2], rules.DEALER_HITS_SOFT),
  felt = "green",
  dealLabel = "DEAL",
  capTokens = 100,
  shoe = true,
  rules = rules,
  view = view,
  help = function()
    return {
      ("%d decks. The shoe carries over from round to round, and is reshuffled between rounds once fewer than %d cards are left."):format(rules.DECKS, rules.RESHUFFLE_BELOW),
      "",
      ("A natural pays %d to %d, rounded down to whole tokens. Every other win pays 1 to 1. Ties push."):format(rules.NATURAL_PAYS[1], rules.NATURAL_PAYS[2]),
      ("The dealer hits soft %d, and peeks at the hole card under an ace or a ten, so a dealer blackjack ends the round before you act."):format(rules.DEALER_HITS_SOFT),
      "",
      ("Double on a hard %d only: one more card, for one more bet."):format(rules.DOUBLE_ON),
      "Split two cards of the same rank once, for one more bet. No double after a split.",
      "Split aces get one card each. 21 on a split hand is not a blackjack and pays 1 to 1.",
      "Any hand that reaches 21 stands by itself. There is no insurance or surrender.",
      "",
      "Doubling and splitting need the extra tokens in your balance. Nothing moves until the round ends.",
      "Walk away and the table stands for you. Your result waits here until you touch it again.",
    }
  end,
}
