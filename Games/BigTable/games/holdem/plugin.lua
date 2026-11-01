-- games/holdem/plugin.lua
-- Texas Hold'em on Big Table, fixed limit. The rules and pictures are lib/casino/group/community.lua, which Omaha and Duel share.

local community = require("lib.casino.group.community")

return community.plugin({
  id = "holdem", variant = "holdem", title = "HOLD'EM", tagline = "Texas Hold'em, fixed limit", felt = "green",
  minSeats = 2, maxSeats = 8,
})
