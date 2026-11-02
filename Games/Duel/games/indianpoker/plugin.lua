-- games/indianpoker/plugin.lua
-- Indian Poker on Duel: a cash game with a buy-in, hand after hand. See rules.lua for how it plays.

local rules = require("games.indianpoker.rules")
local seatView = require("games.indianpoker.seatView")

local function help()
  return {
    { "THE GAME", "gold" },
    "You each get one card and hold it to your forehead, like Blind Man's Bluff. You can see your opponent's card but never your own.",
    "Your wall shows THEIR card, big. The face down card beside it is yours. High card wins, so you are betting on a card you cannot see.",
    "",
    { "PLAY FAIR", "gold" },
    "Your card is on your opponent's wall, so you could read it by walking round to the other side. That is on your honour: looking at the other wall is not part of the game.",
    "",
    { "THE BETTING", "gold" },
    "Both ante " .. rules.ANTE .. ". Then one round of betting, starting with the player who has the button, which moves each hand. Bets and raises are " .. rules.BET .. ", a bet and two raises at most.",
    "Run out of chips and you go all-in: you can win what you matched, and the rest comes back to your opponent.",
    "If your time runs out you check, or fold if there is a bet to call.",
    "",
    { "THE CARDS", "gold" },
    "Aces are high. Suits do not rank. Equal ranks split the pot. It is a fresh deck every hand.",
    "When the hand ends, by a fold or a showdown, both cards turn over, so a folder sees what they threw away.",
    "",
    { "THE MONEY", "gold" },
    "Nothing moves until a hand ends. Then the loser pays the winner.",
  }
end

local function event(ev)
  if ev.type == "deal" then return 0.6, "deal" end
  if ev.type == "reveal" then return 1.6, "flip" end
  if ev.type == "chips" then return 0.1, ev.raise and "chipBig" or "chip" end
  if ev.type == "action" and ev.id == "check" then return 0.1, "knock" end
  if ev.type == "action" and ev.id == "fold" then return 0.4, "ui_back" end
  return 0.05, nil
end

return {
  id = "indianpoker", title = "INDIAN POKER", kind = "players", minSeats = 2, maxSeats = 2, felt = "ember",
  tagline = "You see their card, never your own",
  ante = rules.ANTE, minBuy = 100, maxStack = 5000,
  help = help,
  event = event,
  rules = rules.rules, seatView = seatView,
}
