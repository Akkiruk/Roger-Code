-- games/blackjack/plugin.lua
-- Blackjack on Big Table: every seat against one dealer hand from one shoe, each playing in seat order. The help comes from the rules.

local rules = require("games.blackjack.rules")
local tableView = require("games.blackjack.tableView")
local seatView = require("games.blackjack.seatView")

local TIMES = {
  start = { 0.1 }, deal = { 0.15, "deal" }, peek = { 0.4 }, hit = { 0.25, "deal" }, stand = { 0.1, "tap" },
  double = { 0.3, "chipBig" }, split = { 0.3, "chip" }, turn = { 0.2, "tap" }, reveal = { 0.5, "flip" },
  draw = { 0.4, "deal" }, outcome = { 0.1 },
}

return {
  id = "blackjack",
  title = "BLACKJACK",
  tagline = ("Blackjack pays %d to %d"):format(rules.NATURAL_PAYS[1], rules.NATURAL_PAYS[2]),
  kind = "house",
  minSeats = 1, maxSeats = 8,
  felt = "green",
  minBet = 10, maxBet = 100,   -- 100 is Games/Blackjack's own table limit
  shoe = true,
  rules = rules,
  tableView = tableView,
  seatView = seatView,
  event = function(ev)
    if ev.type == "start" and ev.fresh then return 0.6, "flip" end
    local timing = TIMES[ev.type] or { 0.1 }
    return timing[1], timing[2]
  end,
  help = function()
    return {
      { "THE TABLE", "gold" },
      "Everyone bets at once, then plays against the same dealer hand, in seat order. Other players' cards do not change your odds.",
      ("%d decks. The shoe carries over from round to round, and is reshuffled between rounds once fewer than %d cards are left."):format(rules.DECKS, rules.RESHUFFLE_BELOW),
      "",
      { "PAYS", "gold" },
      ("A natural pays %d to %d, rounded down to whole tokens. Every other win pays 1 to 1. Ties push."):format(rules.NATURAL_PAYS[1], rules.NATURAL_PAYS[2]),
      ("The dealer hits soft %d, and peeks at the hole card under an ace or a ten, so a dealer blackjack ends the round before anyone acts."):format(rules.DEALER_HITS_SOFT),
      "",
      { "PLAYS", "gold" },
      ("Double on a hard %d only: one more card, for one more bet."):format(rules.DOUBLE_ON),
      "Split two cards of the same rank once, for one more bet. No double after a split.",
      "Split aces get one card each. 21 on a split hand is not a blackjack and pays 1 to 1.",
      "Any hand that reaches 21 stands by itself. There is no insurance or surrender.",
      "",
      "Doubling and splitting need the extra tokens in your balance. Nothing moves until the round ends.",
      "Leave your turn and the table stands for you.",
    }
  end,
}
