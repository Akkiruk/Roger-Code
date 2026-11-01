-- games/craps/plugin.lua
-- Shared Craps on Big Table: one shooter, one pair of dice, up to 8 seats betting on them against the house. rules.lua has the game.

local rules = require("games.craps.rules")
local seatView = require("games.craps.seat_view")
local tableView = require("games.craps.table_view")

local function help()
  return {
    { "THE ROUND", "gold" },
    "Bet Pass, Don't Pass or Field before the deal. The shooter taps ROLL. Nothing is taken until the round ends.",
    "On 7 or 11 Pass wins. On 2, 3 or 12 Pass loses. Any other number is the point, and the shooter rolls until that number or a 7.",
    "",
    { "THE BETS", "gold" },
    "Don't Pass is the other side of Pass, and 12 is a push.",
    "Come and Don't Come are the same bets made while a point is on. If the point is made, the shooter keeps rolling until they resolve.",
    "Field is one roll. 3, 4, 9, 10 and 11 pay even money. 2 pays 2 to 1 and 12 pays 3 to 1.",
    "",
    { "ODDS", "gold" },
    "Up to 3 times a bet behind it, paid at true odds with no house edge. Each press adds one more times the bet.",
    "ODDS DP is behind Don't Pass. C6 is a Come on six and D6 a Don't Come on six.",
    "",
    { "THE LIMIT", "gold" },
    "A seat can win at most 10 times its opening bet in a round. A bet that could pass that is not offered.",
    "",
    { "THE DICE", "gold" },
    "A shooter keeps the dice until a seven out. If the clock runs out the dice are thrown for them and pass on.",
  }
end

local EVENTS = {
  comeout = { 0.3, "start" },
  throw = { 0.1, "tap" },
  roll = { 1.6, "dice" },
  bet = { 0.05, "chip" },
  pass = { 0.05 },
  shooter = { 0.3 },
}

local function event(ev)
  local timing = EVENTS[ev.type] or { 0.1 }
  return timing[1], timing[2]
end

return {
  id = "craps", title = "CRAPS", kind = "house", minSeats = 1, maxSeats = 8, felt = "ember", tagline = "One shooter, shared dice",
  minBet = 10, maxBet = 1000, turnMs = 30000,
  spots = {
    { id = "pass", label = "PASS", sub = "1:1", color = "win" },
    { id = "dont", label = "DON'T PASS", sub = "1:1, bar 12", color = "blue" },
    { id = "field", label = "FIELD", sub = "One roll, 12 pays 3:1", color = "gold" },
  },
  help = help, event = event,
  rules = rules, tableView = tableView, seatView = seatView,
}
