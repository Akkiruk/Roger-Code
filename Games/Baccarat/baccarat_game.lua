-- baccarat_game.lua
-- Baccarat as the casino table sees it. The help is built from the rules, so the two cannot disagree.
-- The standard bet screen sets the amount, and the round's first action picks the side, which is what deals.

local rules = require("baccarat_rules")
local view = require("baccarat_view")

return {
  id = "baccarat",
  title = "BACCARAT",
  tagline = ("Player, Banker or Tie. Tie pays %d to 1."):format(rules.PAYS.tie),
  felt = "burgundy",
  dealLabel = "BET",
  capTokens = 100,
  shoe = true,
  rules = rules,
  view = view,
  help = function()
    return {
      ("%d decks, burn %d, reshuffled between rounds when fewer than %d cards are left."):format(rules.DECKS, rules.BURN, rules.RESHUFFLE_BELOW),
      "",
      "Set your amount, then pick a side: the side you pick deals the coup.",
      ("Player pays %d to 1."):format(rules.PAYS.player),
      ("Banker pays %d to 1 less %d%% commission, rounded up to a whole token, so a bet of 100 wins %d."):format(rules.PAYS.banker, rules.COMMISSION, rules.winOn("banker", 100)),
      ("Multiples of %d pay the plain %d%%. The smallest Banker bet is %d."):format(rules.MIN_BANKER, rules.COMMISSION, rules.MIN_BANKER),
      ("Tie is a side bet that pays %d to 1. On a tie, Player and Banker bets push."):format(rules.PAYS.tie),
      "",
      "Aces count 1, tens and faces 0, and only the last digit of a total counts.",
      ("Either side on %d or %d from two cards is a natural and ends the coup."):format(rules.NATURAL, rules.NATURAL + 1),
      "Otherwise the Player draws on 0 to 5.",
      "If the Player stood, the Banker draws on 0 to 5.",
      "If the Player drew, the Banker draws on:",
      "  0-2 always; 3 unless the third card was 8; 4 on 2-7; 5 on 4-7; 6 on 6-7; 7 never.",
      "",
      "Walk away without picking a side and the round is cancelled at no cost.",
    }
  end,
}
