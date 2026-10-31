-- horseracing_game.lua
-- Horse Racing as the casino table sees it. The help is built from the rules, so the two cannot disagree.

local rules = require("horseracing_rules")
local view = require("horseracing_view")

return {
  id = "horse-racing",
  title = "HORSE RACING",
  tagline = "Six horses, fresh odds every race. Back as many as you like.",
  felt = "ember",
  rules = rules,
  view = view,
  stakeOf = rules.stake,
  bet = view.bet,
  help = function()
    local percent = rules.RETURN * 100
    return {
      ("%d horses run each race. Each has a strength, and the odds on the card come from those strengths."):format(rules.HORSES),
      "",
      { "THE BETS", "4" },
      ("Win: your horse comes %s."):format(rules.KIND_HELP.win),
      ("Place: your horse comes %s."):format(rules.KIND_HELP.place),
      ("Show: your horse comes %s."):format(rules.KIND_HELP.show),
      "Exacta: you name the first and the second, in that order.",
      "",
      "Pick a chip, then tap any bets on the card. Put down as many as you like. The multiple is what comes back per token, your stake included, rounded down to whole tokens.",
      ("The smallest chip is %d. Small bets on short odds lose the most to rounding."):format(rules.MIN_BET),
      "",
      { "THE ODDS", "4" },
      "The finishing order is drawn once, as the race starts. Each place goes to a horse with a chance in proportion to its strength, among the horses left.",
      ("Every bet on every horse is priced from its exact chance to return %d%%, so no bet on the card is better or worse than another."):format(percent),
      "The race on the wall shows that order: nothing you see can change it.",
      "",
      "Tables have a limit: the house must be able to cover the best case of your whole card.",
      "AGAIN runs the same card and the same bets once more, a new race with the same odds.",
    }
  end,
}
