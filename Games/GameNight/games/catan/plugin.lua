-- games/catan/plugin.lua
-- Catan on Game Night: three or four players, the computer filling the empty places, so one person can play. Free, like everything
-- on Game Night. rules.lua has the game, bot.lua the computer players, draw.lua the island, and the two views what each screen shows.

local rules = require("games.catan.rules")
local seatView = require("games.catan.seatView")
local tableView = require("games.catan.tableView")

-- Seconds each event holds the screens, and its sound by its name in lib/sound_picks.lua
local LENGTHS = {
  start = { 0.8, "ui_start" },
  turn = { 0.4, "ui_hint" },
  roll = { 1.2, "dice" },
  seven = { 0.9, "telegraph" },
  produce = { 0.5, "payout" },
  robber = { 0.9, "curse" },
  steal = { 0.6, "pickup" },
  road = { 0.5, "piece_a" },
  town = { 0.6, "piece_b" },
  city = { 0.7, "lock_in" },
  buy = { 0.5, "card_flip" },
  bank = { 0.5, "coin" },
  offer = { 0.5, "ui_presence" },
  answer = { 0.2, "ui_select" },
  trade = { 0.6, "chip_one" },
  offerClosed = { 0.1, nil },
  discard = { 0.4, "ui_page" },
  longest = { 0.9, "ui_achievement" },
  army = { 0.9, "ui_achievement" },
  win = { 1.5, "win_big" },
  ["end"] = { 0.1, nil },
  pass = { 0.2, nil },
  pick = { 0.05, nil },
  menu = { 0.05, nil },
}

local PLAYS = { knight = "sword", roads = "dig", plenty = "potion", monopoly = "chest" }

local function event(ev)
  if ev.type == "play" then return 0.8, PLAYS[ev.k] end
  local entry = LENGTHS[ev.type]
  if entry then return entry[1], entry[2] end
  return 0.1
end

return {
  id = "catan", title = "CATAN", kind = "players", minSeats = 1, maxSeats = 4, felt = "island",
  tagline = "Settle the island: 1 to 4 players, the computer fills in",
  turnMs = rules.TURN_MS,
  lobbyMs = 30000,     -- time for friends to sit before the computer fills the table. START begins at once
  wallClock = true,    -- the wall shows the turn's clock
  help = function()
    return {
      { "THE GOAL", "gold" },
      "First to 10 points on their own turn wins. A settlement is 1 point, a city 2, the longest road 2, the largest army 2, and a victory point card 1.",
      "",
      { "SETTING UP", "gold" },
      "Each player places a settlement and a road, then again in reverse order. Your second settlement gives you one of each resource around it.",
      "On your screen, tap the island near where you want to build, or step through the places with < and >. The numbers match the wall. Then PLACE.",
      "",
      { "A TURN", "gold" },
      "ROLL. Every hex with that number pays its resource to each settlement beside it, two to a city. The robber's hex pays nothing.",
      "Then BUILD, TRADE or play CARDS as often as you can pay, and END. Road: brick and wood. Settlement: brick, wood, wool and grain. City: 2 grain and 3 ore. Card: wool, grain and ore.",
      "A settlement needs your road to reach it and no building on a corner next to it.",
      "",
      { "A SEVEN", "gold" },
      "Anyone holding more than 7 cards gives up half. Then the roller moves the robber and takes a card from someone beside it.",
      "",
      { "TRADING", "gold" },
      "Tap what you give and what you want, then BANK or OFFER. The bank takes 4 of one kind, 3 at a 3:1 harbour, 2 at a harbour of that kind. An offer goes to every player, and you pick who to trade with from those who accept.",
      "",
      { "CARDS", "gold" },
      "Knight: move the robber. Three or more and the most knights is the largest army. Road Building: two free roads. Year of Plenty: two resources. Monopoly: everyone gives you all of one resource. One card a turn, never the one you just bought.",
      "",
      { "THE CLOCK", "gold" },
      "A turn has three minutes. When the clock runs out the turn is played out for you, and your clock is short until you tap again.",
      "Free to play. Nothing here ever touches tokens.",
    }
  end,
  event = event,
  rules = rules, tableView = tableView, seatView = seatView,
}
