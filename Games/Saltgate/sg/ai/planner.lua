-- ai/planner.lua
-- A* over the road graph with a binary heap, and with edges to avoid (a roadblock, a closed bridge) that are crossed only
-- at a price when there is no other way. The core's roads:path does the same job without a heap or avoid list; the
-- Patrol replans often enough to want this one. Pure.
--
--   planner.path(roads, fromNode, toNode [, opts]) -> { edge, ... } | nil
--     opts.avoid  { [edgeId] = true }    opts.kinds { road = true, ... } (allowed kinds)    opts.penalty (default 400)
--   planner.nearestNode(roads, x, z, maxDist [, kinds]) -> nodeId, edge, s

local M = {}

local sqrt = math.sqrt

local function push(h, id, pri)
  local n = #h + 1
  h[n] = { id, pri }
  while n > 1 do
    local p = math.floor(n / 2)
    if h[p][2] <= h[n][2] then break end
    h[p], h[n] = h[n], h[p]
    n = p
  end
end

local function pop(h)
  local top = h[1]
  local last = table.remove(h)
  local n = #h
  if n > 0 then
    h[1] = last
    local i = 1
    while true do
      local l, r, m = i * 2, i * 2 + 1, i
      if l <= n and h[l][2] < h[m][2] then m = l end
      if r <= n and h[r][2] < h[m][2] then m = r end
      if m == i then break end
      h[i], h[m] = h[m], h[i]
      i = m
    end
  end
  return top[1]
end

function M.path(roads, fromId, toId, opts)
  opts = opts or {}
  local goal, start = roads.nodes[toId], roads.nodes[fromId]
  if not goal or not start then return nil end
  if fromId == toId then return {} end
  local avoid, kinds, penalty = opts.avoid, opts.kinds, opts.penalty or 400
  local gx, gz = goal.x, goal.z
  local cost, came, via, closed = { [fromId] = 0 }, {}, {}, {}
  local open = {}
  push(open, fromId, 0)
  local guard = 0
  while #open > 0 and guard < 6000 do
    guard = guard + 1
    local cur = pop(open)
    if cur == toId then
      local edges = {}
      while came[cur] do
        table.insert(edges, 1, via[cur])
        cur = came[cur]
      end
      return edges
    end
    if not closed[cur] then
      closed[cur] = true
      for _, e in ipairs(roads:exits(cur)) do
        if not kinds or kinds[e.kind] then
          local nxt = e.a == cur and e.b or e.a
          local c = cost[cur] + e.length + ((avoid and avoid[e.id]) and penalty or 0)
          if cost[nxt] == nil or c < cost[nxt] then
            cost[nxt], came[nxt], via[nxt] = c, cur, e
            local n = roads.nodes[nxt]
            local h = n and n.x and sqrt((n.x - gx) ^ 2 + (n.z - gz) ^ 2) or 0
            push(open, nxt, c + h)
          end
        end
      end
    end
  end
  return nil
end

--- The node at the near end of the road nearest (x, z).
function M.nearestNode(roads, x, z, maxDist, kinds)
  local e, s = roads:nearest(x, z, maxDist, kinds)
  if not e then return nil end
  return (s < e.length / 2) and e.a or e.b, e, s
end

return M
