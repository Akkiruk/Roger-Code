-- games/uno/plugin.lua
-- UNO on Game Night: one to eight people, the computer filling the table to four, so one person can play. Free, like everything on
-- Game Night. rules.lua has the game, bot.lua the computer players, draw.lua the cards, and the two views what each screen shows.

local rules = require("games.uno.rules")
local seatView = require("games.uno.seatView")
local tableView = require("games.uno.tableView")

-- Seconds each event holds the screens, and its sound by its name in lib/sound_picks.lua
local LENGTHS = {
  start = { 0.6, "ui_start" },
  goal = { 0.4, "ui_select" },
  deal = { 1.4, "card_deal" },
  play = { 0.5, "card_flip" },
  skip = { 0.9, "block" },
  reverse = { 0.9, "swish" },
  draw2 = { 1.0, "sting" },
  draw4 = { 1.4, "zap" },
  wild = { 0.9, "spell" },
  color = { 0.7, "spell" },
  draw = { 0.4, "card_deal" },
  uno = { 1.1, "bell" },
  catch = { 1.4, "capture" },
  shuffle = { 0.8, "card_deal" },
  pass = { 0.2, nil },
  handwin = { 3.0, "win_small" },
  win = { 2.0, "win_big" },
  ready = { 0.1, "ui_tap" },
  pick = { 0.05, nil },
  page = { 0.05, nil },
  late = { 0.05, nil },
  clock = { 0.05, nil },
}

local function event(ev)
  local entry = LENGTHS[ev.type]
  if entry then return entry[1], entry[2] end
  return 0.1
end

return {
  id = "uno", title = "UNO", kind = "players", minSeats = 1, maxSeats = 8, felt = "purple",
  tagline = "Match colour or number: 1 to 8 players, the computer fills in",
  turnMs = rules.TURN_MS,
  lobbyMs = 30000,     -- time for friends to sit before the computer fills the table. START begins at once
  wallClock = true,    -- the wall shows each player's clock
  help = function()
    return {
      { "THE GOAL", "gold" },
      "Be first to play every card in your hand. Going out scores the cards left in everyone else's hands: a number its face, Skip, Reverse and Draw Two 20, a wild 50. First to 500 wins, or 200, or one hand, as the first seat picks.",
      "",
      { "A TURN", "gold" },
      "Play one card that matches the colour in play, or the number or symbol on top, or any wild. The cards you may play are lit on your screen: tap one.",
      "Nothing to play, or would rather not? DRAW one. If it can be played you may play it straight away (PLAY IT) or KEEP it, and the turn passes.",
      "",
      { "THE CARDS", "gold" },
      "Skip: the next player misses a turn. Reverse: play turns round (with two players it is a Skip). Draw Two: the next player draws two and misses a turn.",
      "Wild: name any colour. Wild Draw Four: name a colour, and the next player draws four and misses a turn. It can be played at any time, and there is no challenge. Draws do not stack.",
      "",
      { "UNO!", "gold" },
      "When you hold two cards on your turn the UNO! button lights up: tap it, then play. Forget, and anyone can tap CATCH! before the next player moves: you draw two.",
      "",
      { "THE CLOCK", "gold" },
      "A turn has a minute. When it runs out you draw a card and the turn passes, and your clock is short until you tap again.",
      "Free to play. Nothing here ever touches tokens.",
    }
  end,
  event = event,
  rules = rules, tableView = tableView, seatView = seatView,
}
