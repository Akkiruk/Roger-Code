-- games/battleship/plugin.lua
-- Battleship for a stake, on Duel's two walls back to back, so each player's fleet stays on their own side.

local rules = require("games.battleship.rules")
local seatview = require("games.battleship.seatview")
local tableview = require("games.battleship.tableview")

local TIMINGS = {
  deal = { 0.3, "start" }, placed = { 0.1, "deal" }, undo = { 0.05, nil }, rotate = { 0.05, nil }, ready = { 0.2, "flip" },
  battle = { 0.3, "start" }, late = { 0.1, "warn" }, forfeit = { 0.4, nil }, void = { 0.3, "push" },
}

local function event(ev)
  if ev.type == "shot" then
    if ev.sunk then return 0.9, "chipBig" end
    return 0.6, ev.hit and "stop" or "chip"
  end
  local timing = TIMINGS[ev.type]
  if timing then return timing[1], timing[2] end
  return 0.05, nil
end

local function help()
  return {
    "Each player hides five ships on their own wall: Carrier 5, Battleship 4, Cruiser 3, Submarine 3, Destroyer 2. Keep to your side.",
    "",
    { "PLACING", "gold" },
    "You both place at once. Tap the square a ship starts on. Turn it with ACROSS or DOWN, take the last one back with UNDO, or tap RANDOM to place the rest for you. Ships can touch but not overlap.",
    "",
    { "SHOOTING", "gold" },
    "Take turns firing at the enemy's water on your wall. A hit does not earn another shot. When every square of a ship is hit it sinks, and both players are told. Sink all five to win.",
    "",
    { "THE MONEY", "gold" },
    "The first to sit names the stake and the second takes it or leaves it. Nothing moves until the match ends, then the loser pays the winner. Run out of time, while placing or on a shot, or give up, and you lose the stake. If neither of you places a fleet in time, nothing moves.",
  }
end

return {
  id = "battleship", title = "BATTLESHIP", kind = "players", minSeats = 2, maxSeats = 2, felt = "blue",
  tagline = "Sink all five for the stake",
  stakes = { 25, 50, 100, 250, 500 },
  turnMs = 90000,        -- longer than a table's, because running out loses the match. Placing a whole fleet shares one clock
  help = help, event = event,
  rules = rules, tableView = tableview, seatView = seatview,
}
