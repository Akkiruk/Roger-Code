-- games/baccarat/plugin.lua
-- Baccarat at Big Table. Up to eight seats bet Player, Banker or Tie, on any of them at once, and the computer deals one coup for the
-- table from a shoe that lasts across rounds. The help is built from the rules, so the two cannot disagree.

local base = require("games.baccarat.coup")
local rules = require("games.baccarat.rules")
local seatView = require("games.baccarat.seatView")
local tableView = require("games.baccarat.tableView")

-- A screen plays these a frame at a time and the result comes up when their sum has passed, so a card can land late. The outcome's long
-- beat leaves room for that, so the banner never covers a card still on its way.
local TIMING = { start = { 0.01 }, deal = { 0.3, "deal" }, outcome = { 1, "flip" } }

return {
  id = "baccarat",
  title = "BACCARAT",
  kind = "house",
  minSeats = 1, maxSeats = 8,
  felt = "burgundy",
  tagline = ("Player, Banker or Tie. Tie pays %d to 1."):format(base.PAYS.tie),
  minBet = base.MIN_BANKER, maxBet = 2000,
  shoe = true,
  spots = {
    { id = "player", label = "PLAYER", sub = ("%d:1"):format(base.PAYS.player), color = "blue" },
    { id = "banker", label = "BANKER", sub = ("%d:1 less %d%%"):format(base.PAYS.banker, base.COMMISSION), color = "red" },
    { id = "tie", label = "TIE", sub = ("%d:1"):format(base.PAYS.tie), color = "win" },
  },
  event = function(ev)
    local timing = TIMING[ev.type] or { 0.2 }
    return timing[1], timing[2]
  end,
  rules = rules,
  tableView = tableView,
  seatView = seatView,
  help = function()
    return {
      ("%d decks, burn %d, reshuffled between rounds when fewer than %d cards are left."):format(base.DECKS, base.BURN, base.RESHUFFLE_BELOW),
      "",
      "Pick a chip, then tap a side to put it there. You can bet more than one side. When betting closes the computer deals one coup for the whole table.",
      ("Player pays %d to 1."):format(base.PAYS.player),
      ("Banker pays %d to 1 less %d%% commission, rounded up to a whole token, so a bet of 100 wins %d."):format(base.PAYS.banker, base.COMMISSION, base.winOn("banker", 100)),
      ("Multiples of %d pay the plain %d%%. A Banker bet under %d does not stand."):format(base.MIN_BANKER, base.COMMISSION, base.MIN_BANKER),
      ("Tie is a side bet that pays %d to 1. On a tie, Player and Banker bets push."):format(base.PAYS.tie),
      "",
      "Aces count 1, tens and faces 0, and only the last digit of a total counts.",
      ("Either side on %d or %d from two cards is a natural and ends the coup."):format(base.NATURAL, base.NATURAL + 1),
      "Otherwise the Player draws on 0 to 5.",
      "If the Player stood, the Banker draws on 0 to 5.",
      "If the Player drew, the Banker draws on:",
      "  0-2 always; 3 unless the third card was 8; 4 on 2-7; 5 on 4-7; 6 on 6-7; 7 never.",
    }
  end,
}
