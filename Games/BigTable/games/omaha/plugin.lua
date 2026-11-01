-- games/omaha/plugin.lua
-- Omaha on Big Table, fixed limit. The rules and pictures are lib/casino/group/community.lua, which Hold'em and Duel share.

local community = require("lib.casino.group.community")

return community.plugin({
  id = "omaha", variant = "omaha", title = "OMAHA", tagline = "Two of your four, three of the board", felt = "blue",
  minSeats = 2, maxSeats = 8,
})
