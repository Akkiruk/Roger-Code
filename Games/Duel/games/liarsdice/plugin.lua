-- games/liarsdice/plugin.lua
-- Liar's Dice on Duel. See rules.lua for how it plays. No stake moves until one player is out of dice.

local rules = require("games.liarsdice.rules")
local seatView = require("games.liarsdice.seatView")
local tableView = require("games.liarsdice.tableView")

local LENGTHS = {
  roll = { 0.6, "dice" },
  bid = { 0.5, "chip" },
  pick = { 0.05, "tap" },
  liar = { 1.0, "warn" },
  reveal = { 3.5, "flip" },
}

return {
  id = "liarsdice", title = "LIAR'S DICE", kind = "players", minSeats = 2, maxSeats = 2, felt = "burgundy",
  tagline = "Five dice each, one stake",
  stakes = { 25, 50, 100, 250, 500 }, stakeCover = 1,
  help = function()
    return {
      { "THE GAME", "gold" },
      "You each roll five dice in secret, then take turns to bid how many of a face are on the table between you, counting both players' dice.",
      "",
      { "BIDDING", "gold" },
      "Tap a count and a face, then BID. Each bid must beat the last: a higher count, or the same count on a higher face. Ones rank above sixes.",
      "Ones are wild: they count as the bid face, unless the bid is for ones.",
      "",
      { "LIAR", "gold" },
      "Think the last bid is too high? Call LIAR. Every die shows. If the bid fell short the bidder loses a die, otherwise you do. The loser opens the next round.",
      "",
      { "THE MONEY", "gold" },
      "The last player with dice wins the stake. Nothing moves until then. If your time runs out you open with the lowest bid, or call LIAR on what stands.",
    }
  end,
  event = function(ev)
    local entry = LENGTHS[ev.type]
    if entry then return entry[1], entry[2] end
    return 0.1
  end,
  rules = rules, tableView = tableView, seatView = seatView,
}
