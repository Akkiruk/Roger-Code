-- games/gin/plugin.lua
-- Gin Rummy for two walls, for a stake per point. See rules.lua for the game.

local melds = require("games.gin.melds")
local rules = require("games.gin.rules")
local seatView = require("games.gin.seatView")
local tableView = require("games.gin.tableView")

local SECONDS = { deal = 0.8, draw = 0.2, take = 0.2, throw = 0.2, pick = 0.05, knock = 0.8, gin = 1, wash = 0.5 }
local SOUNDS = { deal = "deal", draw = "deal", take = "deal", throw = "deal" }

return {
  id = "gin", title = "GIN RUMMY", kind = "players", minSeats = 2, maxSeats = 2, felt = "teal", tagline = "A stake per point",
  -- A player must hold a full table maximum to sit, so what a hand can cost is known and agreed before a card is dealt
  stakes = { 1, 2, 5, 10, 25 },
  stakeCover = rules.POINT_CAP,
  stakeNote = function(stake)
    return "A point. Most a hand: " .. stake * rules.POINT_CAP
  end,
  turnMs = 60000,
  help = function()
    return {
      { "THE HAND", "gold" },
      "10 cards each. On your turn draw from the stock or take the top discard, then throw one card.",
      "The first turn is like any other: there is no passing on the first up card.",
      "Melds are 3 or 4 of a rank, or 3 or more in a row in one suit. Ace is low: A-2-3 counts, Q-K-A does not.",
      "Cards outside a meld are deadwood: ace 1, faces 10, the rest their number. The wall sorts your hand and finds your best melds.",
      "",
      { "ENDING IT", "gold" },
      "With 10 or less deadwood after your throw you can knock. The other player lays off what they can on your melds.",
      "You score the difference. If they are level or lower it is an undercut: they score the difference plus 25.",
      "With no deadwood you go gin: 25 plus their deadwood, and nothing can be laid off.",
      "If the stock is down to 2 cards the hand is off and nothing moves.",
      "",
      { "THE MONEY", "gold" },
      "Each point is worth the stake, up to the table maximum of 100 stakes a hand. Both players agree to the stake before they sit.",
      "One hand, one settle. Nothing moves until a hand ends.",
    }
  end,
  event = function(ev)
    return SECONDS[ev.type] or 0.1, SOUNDS[ev.type]
  end,
  rules = rules, tableView = tableView, seatView = seatView, melds = melds,
}
