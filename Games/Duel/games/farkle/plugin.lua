-- games/farkle/plugin.lua
-- Farkle on Duel. See rules.lua for how it plays. No stake moves until the match is over.

local rules = require("games.farkle.rules")
local seatView = require("games.farkle.seatView")
local tableView = require("games.farkle.tableView")

local LENGTHS = {
  roll = { 0.9, "dice" },
  pick = { 0.05, "tap" },
  bank = { 0.8, "chipBig" },
  farkle = { 1.8, "resign" },
  hot = { 1.2, "level_clear" },
  lastturn = { 1.6, "warn" },
}

return {
  id = "farkle", title = "FARKLE", kind = "players", minSeats = 2, maxSeats = 2, felt = "ember",
  tagline = "Six dice, first to 5,000",
  stakes = { 25, 50, 100, 250, 500 }, stakeCover = 1,
  turnMs = 60000,        -- one clock for a whole turn, every roll of it, because a seat that stays up keeps its clock
  help = function()
    return {
      { "THE GAME", "gold" },
      "First to 5,000 takes the stake. Your turn starts with six dice thrown for you.",
      "Tap the dice you want to keep. They must all score, and you must keep at least one.",
      "Then ROLL the rest to chase more, or BANK the turn's points.",
      "",
      { "SCORING", "gold" },
      "A one: 100",
      "A five: 50",
      "Three of a kind: the face x 100",
      "Three ones: 1000",
      "Four of a kind: 1000",
      "Five of a kind: 2000",
      "Six of a kind: 3000",
      "A straight, 1 to 6: 1500",
      "Three pairs: 1500",
      "Two triples: 2500",
      "Only dice from the same roll combine. Four ones are three ones and a one, 1100.",
      "",
      { "FARKLE", "gold" },
      "A roll with nothing scoring is a farkle: the turn's points are gone and the dice pass.",
      "",
      { "HOT DICE", "gold" },
      "When all six dice have scored they are hot. Roll all six again and keep your points, or bank.",
      "",
      { "BANKING", "gold" },
      "Your first bank needs 500 or more in one turn. After that any amount will do.",
      "",
      { "THE LAST TURN", "gold" },
      "Bank past 5,000 and the other player gets one last turn to beat you. The higher score wins.",
      "If that turn only ties you, you win, for getting there first.",
      "",
      { "THE MONEY", "gold" },
      "The winner takes the stake and nothing moves before then. A turn has one clock. If it runs out",
      "you keep the best the dice offer, and bank if you may, or roll on if you may not.",
    }
  end,
  event = function(ev)
    local entry = LENGTHS[ev.type]
    if entry then return entry[1], entry[2] end
    return 0.1
  end,
  rules = rules, tableView = tableView, seatView = seatView,
}
