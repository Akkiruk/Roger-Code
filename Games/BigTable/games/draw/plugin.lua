-- games/draw/plugin.lua
-- Five-Card Draw: the rules of Poker Table, each hand private on its own seat, the pot and the turn on the dealer's wall.

local five = require("pokertable_rules")
local rules = require("games.draw.rules")
local seatView = require("games.draw.seatView")
local tableView = require("games.draw.tableView")

local EVENTS = {
  deal = { 1.2, "deal" },
  street = { 0.5, "flip" },
  draw = { 0.5, "deal" },
  chips = { 0.2, "chip" },
  action = { 0.15 },
  showdown = { 1, "flip" },
}

return {
  id = "draw", title = "FIVE-CARD DRAW", kind = "players", minSeats = five.MIN_PLAYERS, maxSeats = five.MAX_SEATS, felt = "green",
  tagline = "Fixed limit " .. five.SMALL .. "/" .. five.BIG .. ", ante " .. five.ANTE,
  ante = five.ANTE, minBuy = five.MIN_BUY, maxStack = five.MAX_STACK,
  help = function()
    return {
      { "THE HAND", "gold" },
      "Everyone antes " .. five.ANTE .. " and gets five cards. A betting round at " .. five.SMALL .. ", one draw, a betting round at "
        .. five.BIG .. ", then the best hand still in takes the pot.",
      "",
      { "THE DRAW", "gold" },
      "On your turn tap the cards to throw, then press DRAW. Throw up to " .. five.MAX_DISCARD .. ", or " .. five.MAX_DISCARD_ACE
        .. " if the card you keep is an ace.",
      "",
      { "BETTING", "gold" },
      "A bet and three raises each round. Short of chips, you go all-in and side pots sort it out. A player who runs out of time checks if it is free and folds if not.",
      "",
      { "THE MONEY", "gold" },
      "Nothing moves until a hand ends. Then losers pay and winners are paid from that. An odd chip in a split pot goes to the house.",
    }
  end,
  event = function(ev)
    local entry = EVENTS[ev.type]
    if entry then return entry[1], entry[2] end
    return 0, nil
  end,
  rules = rules, tableView = tableView, seatView = seatView,
}
