-- horseracing_game.lua
-- Horse Racing as the casino table sees it. The help is built from the rules, so the two cannot disagree.

local rules = require("horseracing_rules")
local view = require("horseracing_view")

local LONG_SHOT = 6   -- what a winner paid back for each token: 5 to 1

--- Whether any bet on the card that won is of this kind and paid at least this many times its amount.
local function paidOn(state, kind, times)
  for _, bet in ipairs(state.bets) do
    if bet.kind == kind and bet.paid > 0 and bet.paid >= bet.amount * times then return true end
  end
  return false
end

return {
  id = "horse-racing",
  title = "HORSE RACING",
  tagline = "Six horses, fresh odds every race. Back as many as you like.",
  felt = "ember",
  demo = {
    wager = function(stream)
      return { race = rules.newRace(stream), bets = { { kind = "win", a = stream:below(rules.HORSES) + 1, amount = 100 } } }
    end,
  },
  badges = {
    long_shot = { name = "Long Shot", text = "Back a winner at 5 to 1 or longer",
      test = function(_, _, round) return paidOn(round.state, "win", LONG_SHOT) end },
    exacta = { name = "Exacta", text = "Call the first two home",
      test = function(_, _, round) return paidOn(round.state, "exacta", 1) end },
    photo = { name = "Photo Finish", text = "Win a race decided by a photo",
      test = function(_, _, round) return round.state.photo == true and round.net > 0 end },
  },
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
