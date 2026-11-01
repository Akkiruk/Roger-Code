-- rounding.lua
-- The owner's only cut of a players game: a split pot that cannot divide evenly leaves odd chips, and they go to the owner.
-- Take a finished hand's odd chips off the winner pokertable_rules gave them to. The hand's nets then add up to -state.kept, and
-- the dealer's settling needs nothing new: it only ever pays out of what it holds above that, so the owner keeps them first and
-- never pays them out of pocket.

local M = {}

--- Once a hand is over and its nets are worked out. Safe to call again.
function M.take(state)
  if state.kept or not state.pots then return end
  state.kept = 0
  for _, pot in ipairs(state.pots) do
    if pot.odd > 0 then
      local first = state.players[pot.winners[1]]
      first.won = first.won - pot.odd
      first.net = first.net - pot.odd
      first.stack = first.stack - pot.odd
      state.kept = state.kept + pot.odd
    end
  end
end

return M
