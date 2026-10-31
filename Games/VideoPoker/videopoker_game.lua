-- videopoker_game.lua
-- Video poker as the casino table sees it. The help is built from the rules, so the two cannot disagree.

local theme = require("lib.casino.theme")
local rules = require("videopoker_rules")
local view = require("videopoker_view")

return {
  id = "videopoker",
  title = "VIDEO POKER",
  tagline = "Jacks or Better. Hold what you like and draw once.",
  felt = "blue",
  dealLabel = "DEAL",
  rules = rules,
  view = view,
  help = function()
    local lines = {
      "Jacks or Better from one deck, freshly shuffled for every hand.",
      "You are dealt five cards. Tap the ones to keep, then DRAW replaces the rest once.",
      "",
      { "WHAT YOUR FINAL HAND RETURNS, FOR EACH TOKEN BET", theme.C.gold },
    }
    for _, line in ipairs(rules.PAYS) do
      lines[#lines + 1] = ("%-18s %d"):format(line.name, line.multiple)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "That is the total back, your bet included: a pair of Jacks returns your bet, so it wins nothing and loses nothing."
    lines[#lines + 1] = "Anything less than a pair of Jacks loses the bet."
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("With perfect holds this table returns %.2f%% of what is bet."):format(rules.RETURN * 100)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Walk away and the table draws for you, keeping your holds and any hand that already pays."
    return lines
  end,
}
