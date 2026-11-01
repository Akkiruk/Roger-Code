-- games/holdem/plugin.lua
-- Heads-Up Hold'em on Duel, fixed limit. The rules and pictures are lib/casino/group/community.lua, which Big Table shares.

local community = require("lib.casino.group.community")

return community.plugin({
  id = "holdem", variant = "holdem", title = "HEADS-UP HOLD'EM", tagline = "Fixed limit, one against one", felt = "green",
  minSeats = 2, maxSeats = 2, duel = true,
})
