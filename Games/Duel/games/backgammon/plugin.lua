-- games/backgammon/plugin.lua
-- Backgammon on Duel. See rules.lua for how it plays. No stake moves until the game ends.

local rules = require("games.backgammon.rules")
local seatView = require("games.backgammon.seatView")
local tableView = require("games.backgammon.tableView")

local LENGTHS = {
  opening = { 1.6, "dice" },
  roll = { 0.7, "dice" },
  blocked = { 1.8, "ui_error" },
  double = { 1.0, "warn" },
  take = { 0.5, "chip" },
  drop = { 0.8, "ui_back" },
  undo = { 0.1, "ui_back" },
  pick = { 0.05, nil },
  turn = { 0.1, nil },
  win = { 1.2, "chipBig" },
}

local function event(ev)
  if ev.type == "move" then
    if ev.hit then return 0.6, "capture" end
    if ev.to == rules.OFF then return 0.35, "chip" end
    return 0.3, "piece_a"
  end
  local entry = LENGTHS[ev.type]
  if entry then return entry[1], entry[2] end
  return 0.1
end

return {
  id = "backgammon", title = "BACKGAMMON", kind = "players", minSeats = 2, maxSeats = 2, felt = "ember",
  tagline = "One game, a stake and a cube",
  stakes = { 25, 50, 100, 250, 500 }, stakeCover = 1,
  turnMs = 75000,        -- one clock for the whole turn: the roll and up to four checkers at two taps each
  help = function()
    return {
      { "THE GAME", "gold" },
      "Each wall shows the board from its own player's side. Your checkers are white, your home is bottom right, and you run them round to it and bear them off. First to bear off all fifteen wins.",
      "",
      { "A TURN", "gold" },
      "One die each to open: the higher starts and plays both. After that, roll and play both dice, or four of a double. Tap a checker's point, then a green point. UNDO takes a move back until your last die is played, which ends your turn.",
      "A point with two or more of the other player's checkers is closed. A single checker there is hit and goes to the bar, and a checker on the bar must come in first.",
      "You must play both dice if any way of doing it exists. If only one can be played, it must be the higher.",
      "With all your checkers home you may bear off. A die higher than your furthest checker bears that checker off.",
      "",
      { "THE CUBE", "gold" },
      "Before you roll you may double, while the cube is in the middle or yours. The other player takes, and holds the cube, or drops and pays the stake times the cube as it stood.",
      "",
      { "THE MONEY", "gold" },
      "The loser pays the stake times the cube. A gammon, when the loser has borne off nothing, pays double. A backgammon, when they also have a checker on the bar or in the winner's home, pays triple.",
      "No game pays more than the shorter stack, and the cube is not offered past what that can pay. A gammon can hit that cap and pay less than double.",
      "If your time runs out you roll without doubling and the first legal moves are played, and you drop any double.",
    }
  end,
  event = event,
  rules = rules, tableView = tableView, seatView = seatView,
}
