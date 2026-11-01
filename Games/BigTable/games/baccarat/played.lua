-- games/baccarat/played.lua
-- What has been played so far. A view of a finished coup holds every card, so while the deal events run both screens show only the
-- cards that have landed. The winner, the nets and the road's new result wait for the outcome, as in Games/Baccarat.

local base = require("games.baccarat.coup")

local M = {}

local function first(list, count)
  local out = {}
  for index = 1, math.min(count, #list) do out[index] = list[index] end
  return out
end

--- { player, banker, incoming, winner, road }: the hands on the felt, the deal event on its way to one, and the outcome once it is out.
function M.of(view, anim)
  local player, banker = view.player or {}, view.banker or {}
  local ev = anim and anim.ev
  local incoming = ev and ev.type == "deal" and ev or nil
  local out = { road = view.road or "", incoming = incoming }
  if incoming then
    -- The deal goes Player, Banker, Player, Banker, then each side's third
    local slot, toPlayer = incoming.slot, incoming.who == "player"
    out.player = first(player, toPlayer and slot - 1 or (slot <= 2 and slot or #player))
    out.banker = first(banker, slot - 1)
    return out
  end
  out.player, out.banker = player, banker
  if view.winner then
    out.winner = view.winner
    out.road = base.addToRoad(out.road, view.winner)
  end
  return out
end

return M
