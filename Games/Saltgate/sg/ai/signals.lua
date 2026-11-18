-- ai/signals.lua
-- Traffic lights and who goes first. A crossing of four or more roads has a light that cycles by the clock (every
-- node starts at its own point in the cycle, so a street of lights is not one wave); everywhere else cars give way by
-- the priority of the road they came from (one-way edges, which includes roundabout rings, beat two-way ones; avenues
-- beat roads beat alleys). Pure.
--
--   signals.isSignal(node) -> bool
--   signals.state(node, edge, t) -> "green" | "amber" | "red"     for traffic arriving by edge
--   signals.priority(edge) -> number                               higher goes first

local M = {}

M.CYCLE = 24
M.GREEN, M.AMBER = 10, 2

local MAJOR = { road = true, avenue = true, highway = true }
local RANK = { highway = 3, avenue = 2, road = 1, alley = 0, path = -1 }

function M.priority(e)
  return (e.lanes == 1 and 4 or 0) + (RANK[e.kind] or 0)
end

--- Does this node have a traffic light? (cached on the node, redone when its edges change)
function M.isSignal(node)
  local n = #node.edges
  if node._sigN == n then return node._sig end
  local major = 0
  for _, e in ipairs(node.edges) do
    if MAJOR[e.kind] and e.lanes ~= 1 then major = major + 1 end
  end
  node._sigN = n
  node._sig = n >= 4 and major >= 3
  return node._sig
end

local function offset(node)
  if node._off then return node._off end
  local h = 0
  for i = 1, #node.id do h = (h * 31 + node.id:byte(i)) % 9973 end
  node._off = h % M.CYCLE
  return node._off
end

--- Which axis (0 or 1) the edge arrives along at the node: the direction of travel, folded to 0..pi, in two bands.
local function axis(node, edge)
  local p = edge.pts
  local n = #p
  local dx, dz
  if edge.b == node.id then
    dx, dz = p[n - 2] - p[n - 5], p[n] - p[n - 3]
  else
    dx, dz = p[4] - p[1], p[6] - p[3]
  end
  local a = (math.atan2 or math.atan)(dz, dx) % math.pi
  return math.floor(a / (math.pi / 2) + 0.5) % 2
end

function M.state(node, edge, t)
  local p = (t + offset(node)) % M.CYCLE
  if axis(node, edge) == 1 then p = (p + M.CYCLE / 2) % M.CYCLE end
  if p < M.GREEN then return "green" end
  if p < M.GREEN + M.AMBER then return "amber" end
  return "red"
end

return M
