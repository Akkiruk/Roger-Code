-- games/cribbage/plugin.lua
-- Cribbage for two walls, one game to 121 for a stake. See rules.lua for the game and scoring.lua for what cards are worth.

local rules = require("games.cribbage.rules")
local scoring = require("games.cribbage.scoring")
local seatView = require("games.cribbage.seatView")

-- A step of the show has to stay up long enough to read a breakdown. The engine adds its own second before the next step
local SHOW_SECONDS = 5
local SECONDS = { cut = 2.5, deal = 0.8, pick = 0.05, discard = 0.2, starter = 1, heels = 1.2, go = 0.6, point = 0.5, pegged = 0.8, show = SHOW_SECONDS,
  win = 1 }

local function soundOf(ev)
  if ev.type == "peg" then
    if ev.count == scoring.THIRTY_ONE then return "bell" end
    return ev.points > 0 and "chip" or "deal"
  end
  if ev.type == "show" then
    if ev.points == 0 then return "ui_page" end
    return ev.points >= 12 and "chipBig" or "chip"
  end
  if ev.type == "win" then return ev.skunk and "horn" or "bigWin" end
  if ev.type == "cut" then return ev.tie and "push" or "flip" end
  return ({ deal = "deal", pick = "tap", discard = "flip", starter = "flip", heels = "coin", go = "knock", point = "coin" })[ev.type]
end

return {
  id = "cribbage", title = "CRIBBAGE", kind = "players", minSeats = 2, maxSeats = 2, felt = "ember", tagline = "First to 121 for a stake",
  stakes = { 25, 50, 100, 250, 500 },
  stakeCover = 1,
  stakeNote = function(stake)
    return "Skunk pays " .. stake * 2
  end,
  turnMs = 60000,
  help = function()
    return {
      { "THE GAME", "gold" },
      "First to 121 wins the stake. Reaching 121 ends the game on the spot, even in the middle of a count.",
      "Low card on the cut deals first, aces low, and a tie cuts again. The crib then goes back and forth.",
      "",
      { "THE HAND", "gold" },
      "Six cards each. You both throw two to the dealer's crib at the same time, then a starter is cut. A jack pays the dealer 2, his heels.",
      "",
      { "PEGGING", "gold" },
      "Take turns laying a card, the count never passing 31. Fifteen 2, thirty-one 2, pairs 2, 6, 12, runs in any order, go 1, last card 1.",
      "Ace is 1, faces 10. If no card of yours fits, the wall says go for you.",
      "",
      { "THE SHOW", "gold" },
      "The player who did not deal counts first, then the dealer, then the crib, with the starter in every hand.",
      "Fifteens 2, pairs, runs, flush of 4 or 5, and nobs 1, the jack of the starter's suit. A crib flush must be 5, starter included.",
      "The wall counts everything. There is no muggins.",
      "",
      { "THE MONEY", "gold" },
      "A loser under 91 is skunked and pays double. There is no double skunk.",
      "What a game moves is held to the shorter stack, skunk or not. Nothing moves until the game ends.",
    }
  end,
  event = function(ev)
    if ev.type == "peg" then return ev.points > 0 and 0.9 or 0.5, soundOf(ev) end
    return SECONDS[ev.type] or 0.1, soundOf(ev)
  end,
  rules = rules, seatView = seatView, scoring = scoring,
}
