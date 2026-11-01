-- games/stud/plugin.lua
-- Seven Card Stud on Big Table. See rules.lua for the game and games/README.md for what a plugin provides.

local rules = require("games.stud.rules")
local seatView = require("games.stud.seatView")
local tableView = require("games.stud.tableView")

local SOUNDS = { deal = "deal", street = "deal", showdown = "flip" }
local LENGTHS = { deal = 1.0, street = 0.7, showdown = 1.0, action = 0.15 }

return {
  -- Short, so a seat's top bar keeps the player's name beside their balance
  id = "stud", title = "STUD", kind = "players", minSeats = 2, maxSeats = 8, felt = "burgundy",
  tagline = "Seven card, fixed limit",
  ante = rules.ANTE, minBuy = 100, maxStack = 5000,

  help = function()
    return {
      { "THE HAND", "gold" },
      "Everyone antes " .. rules.ANTE .. " and gets two cards down and one up. Then a card up on each of the next three streets and a last card down.",
      "Your best five of seven wins. Your down-cards are on your own screen, and everyone's up-cards are on the big wall.",
      "",
      { "THE BETTING", "gold" },
      "The lowest up-card opens: bring it in for " .. rules.BRING_IN .. " or complete to " .. rules.SMALL .. ".",
      "After that the best board acts first. Pairs and better count on a board, straights and flushes do not.",
      "Bets are " .. rules.SMALL .. " on third and fourth street and " .. rules.BIG .. " after that, with a bet and three raises a street.",
      "",
      { "THE LAST CARD", "gold" },
      "If the deck cannot give everyone left a seventh card, one card goes face up in the middle and everyone plays it.",
      "",
      { "THE MONEY", "gold" },
      "Nothing moves until a hand ends. Losers pay, then winners are paid. An odd chip in a split pot goes to the house.",
    }
  end,

  event = function(ev)
    return LENGTHS[ev.type] or 0.1, SOUNDS[ev.type]
  end,

  rules = rules, tableView = tableView, seatView = seatView,
}
