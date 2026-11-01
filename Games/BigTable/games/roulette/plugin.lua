-- games/roulette/plugin.lua
-- Shared-wheel roulette on Big Table: every seat bets at once on its own screen, and one spin settles them all. See rules.lua.

local theme = require("lib.casino.theme")
local rules = require("games.roulette.rules")
local seatView = require("games.roulette.seatView")
local tableView = require("games.roulette.tableView")
local wheel = require("games.roulette.wheel")

local C = theme.C

local function help()
  local lines = {
    "European roulette: one zero, 37 numbers, and one wheel for the whole table. Nothing is charged until it lands.",
    "",
    { "HOW TO BET", C.gold },
    "Choose how much you want to play with and press READY. When betting opens, spread it over the layout on your own screen.",
    "Pick a chip along the bottom, pick the kind of bet along the top, then tap the layout. Red, black, odd, even, 1-18, 19-36, the dozens and the 2:1 columns can be tapped in any mode.",
    "UNDO takes back the last move, X2 doubles every stake, and REPEAT lays your last bet again.",
    "Press DONE when you are happy, or let the clock run out: your chips stay where they are. Whatever you did not lay down was never bet.",
    "The wheel spins as soon as everyone is done, or when the clock closes betting.",
    "",
    { "WHAT EACH BET PAYS", C.gold },
  }
  for _, kind in ipairs(wheel.KINDS) do
    lines[#lines + 1] = ("%s pays %d to 1: %s."):format(kind.label, kind.pay, kind.how)
  end
  local kind = wheel.KINDS[1]
  lines[#lines + 1] = ""
  lines[#lines + 1] = "When 0 lands, red, black, odd, even, low, high, the dozens and the columns all lose."
  lines[#lines + 1] = ("Every bet returns %.2f%%: %d numbers would need to pay %d to 1 to be even."):format(
    kind.covers * (kind.pay + 1) / wheel.POCKETS * 100, wheel.POCKETS, wheel.POCKETS - 1)
  lines[#lines + 1] = "The house must be able to cover your whole amount on one number. If it cannot, your amount is cut to fit."
  return lines
end

local TIMES = { spin = { 3.8, "spin" }, landed = { 1.3, "stop" }, payout = { 1.0, "chip" }, open = { 0.3, "tap" } }

--- A bet or a chip change is only a nudge for the screens. It must not hold up the next press.
local function event(ev)
  local entry = TIMES[ev.type]
  if entry then return entry[1], entry[2] end
  return 0.01, nil
end

return {
  id = "roulette",
  title = "ROULETTE",
  tagline = "One wheel, every seat",
  kind = "house",
  minSeats = 1,
  maxSeats = 8,
  felt = "green",
  minBet = 10,
  maxBet = 1000,
  turnMs = 25000, -- under the bank's 30 second touch window, so a player who bet and waited for the clock still settles at once
  help = help,
  event = event,
  rules = rules,
  tableView = tableView,
  seatView = seatView,
}
