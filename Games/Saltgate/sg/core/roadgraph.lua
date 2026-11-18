-- core/roadgraph.lua
-- The road network as a graph: nodes (junctions, ends) and edges (curved 3D polylines between them), merged from the
-- chunks the streamer has loaded. AI drives along edges and routes with path(); nothing assumes a grid. Pure.
--
--   local g = roadgraph.new()
--   g:addChunk(chunk) / g:removeChunk(chunk)        (the streamer does this)
--   g:node(id) -> { id, x, y, z, edges = { edge, ... } }
--   g:edge(id) -> { id, a, b, width, lanes, speed, kind, pts, length }
--   g:nearest(x, z, maxDist [, kinds]) -> edge, s (distance along it), d (distance away), qx, qz, y, dirX, dirZ
--   g:pointAt(edge, s, side) -> x, y, z, dirX, dirZ   (side: lane offset to the right of a->b, negative for left)
--   g:path(fromNodeId, toNodeId [, kinds]) -> { nodeId, ... }, { edge, ... }  or nil when there is no way (yet)
--   g:exits(nodeId, fromEdge) -> edges leaving a node, the way back last

local geom = require("sg.core.geom")

local M = {}
local G = {}
G.__index = G

function M.new()
  return setmetatable({ nodes = {}, edges = {}, owners = {} }, G)
end

local function ensureNode(g, id)
  local n = g.nodes[id]
  if not n then
    n = { id = id, edges = {}, refs = 0 }
    g.nodes[id] = n
  end
  return n
end

function G:addChunk(c)
  local key = c.cx .. "," .. c.cz
  if self.owners[key] then return end
  local owned = { nodes = {}, edges = {} }
  self.owners[key] = owned
  for _, rec in ipairs(c.nodes or {}) do
    local n = ensureNode(self, rec[1])
    n.x, n.y, n.z, n.defined = rec[2], rec[3], rec[4], true
    owned.nodes[#owned.nodes + 1] = rec[1]
  end
  for _, rec in ipairs(c.roads or {}) do
    local pts = rec[8]
    local e = {
      id = rec[1], a = rec[2], b = rec[3], width = rec[4], lanes = rec[5], speed = rec[6], kind = rec[7], pts = pts,
      length = geom.polylineLength(pts),
    }
    self.edges[e.id] = e
    owned.edges[#owned.edges + 1] = e.id
    local na, nb = ensureNode(self, e.a), ensureNode(self, e.b)
    na.edges[#na.edges + 1] = e
    if nb ~= na then nb.edges[#nb.edges + 1] = e end
    -- a node another chunk has not given yet still has a place: the polyline's end
    if not na.defined then na.x, na.y, na.z = pts[1], pts[2], pts[3] end
    if not nb.defined then nb.x, nb.y, nb.z = pts[#pts - 2], pts[#pts - 1], pts[#pts] end
  end
end

function G:removeChunk(c)
  local key = c.cx .. "," .. c.cz
  local owned = self.owners[key]
  if not owned then return end
  self.owners[key] = nil
  for _, id in ipairs(owned.edges) do
    local e = self.edges[id]
    if e then
      self.edges[id] = nil
      for _, nid in ipairs({ e.a, e.b }) do
        local n = self.nodes[nid]
        if n then
          for i = #n.edges, 1, -1 do
            if n.edges[i] == e then table.remove(n.edges, i) end
          end
        end
      end
    end
  end
  for _, id in ipairs(owned.nodes) do
    local n = self.nodes[id]
    if n then n.defined = nil end
  end
  for id, n in pairs(self.nodes) do
    if not n.defined and #n.edges == 0 then self.nodes[id] = nil end
  end
end

function G:node(id) return self.nodes[id] end
function G:edge(id) return self.edges[id] end

function G:count()
  local n, e = 0, 0
  for _ in pairs(self.nodes) do n = n + 1 end
  for _ in pairs(self.edges) do e = e + 1 end
  return n, e
end

local function kindOk(kinds, e)
  return not kinds or kinds[e.kind]
end

--- The nearest road to (x, z) within maxDist.
function G:nearest(x, z, maxDist, kinds)
  local best, bs, bd, bqx, bqz, by, bdx, bdz = nil, 0, maxDist or math.huge, 0, 0, 0, 1, 0
  for _, e in pairs(self.edges) do
    if kindOk(kinds, e) then
      local x0, z0, x1, z1 = geom.bounds(e.pts, 3)
      if x >= x0 - bd and x <= x1 + bd and z >= z0 - bd and z <= z1 + bd then
        local d, y, seg, t, qx, qz, dx, dz = geom.polylineNearest(e.pts, x, z)
        if d < bd then
          -- s: flat distance along the edge to the nearest point
          local s = 0
          for i = 1, seg - 1 do
            local k = (i - 1) * 3 + 1
            s = s + math.sqrt((e.pts[k + 3] - e.pts[k]) ^ 2 + (e.pts[k + 5] - e.pts[k + 2]) ^ 2)
          end
          local k = (seg - 1) * 3 + 1
          s = s + t * math.sqrt((e.pts[k + 3] - e.pts[k]) ^ 2 + (e.pts[k + 5] - e.pts[k + 2]) ^ 2)
          best, bs, bd, bqx, bqz, by, bdx, bdz = e, s, d, qx, qz, y, dx, dz
        end
      end
    end
  end
  return best, bs, bd, bqx, bqz, by, bdx, bdz
end

--- A point s units along an edge, side units to the right of the a->b direction (a lane).
function G:pointAt(e, s, side)
  local x, y, z, dx, dz = geom.polylineAt(e.pts, s)
  side = side or 0
  return x - dz * side, y, z + dx * side, dx, dz
end

--- The edges you can leave a node by, coming from fromEdge: one-way edges only from their a end; the way back last.
function G:exits(nodeId, fromEdge)
  local n = self.nodes[nodeId]
  local out, back = {}, nil
  if not n then return out end
  for _, e in ipairs(n.edges) do
    local allowed = e.lanes ~= 1 or e.a == nodeId
    if allowed then
      if e == fromEdge then back = e else out[#out + 1] = e end
    end
  end
  if back then out[#out + 1] = back end
  return out
end

--- The other end of an edge.
function M.other(e, nodeId)
  return e.a == nodeId and e.b or e.a
end

--- Shortest way between two nodes over the loaded roads (A*). Returns the node ids and the edges, or nil.
function G:path(fromId, toId, kinds)
  local goal = self.nodes[toId]
  if not self.nodes[fromId] or not goal then return nil end
  local function h(id)
    local n = self.nodes[id]
    if not n or not n.x then return 0 end
    return math.sqrt((n.x - goal.x) ^ 2 + (n.z - goal.z) ^ 2)
  end
  local open, openSet = { fromId }, { [fromId] = true }
  local cost, came, via = { [fromId] = 0 }, {}, {}
  local guard = 0
  while #open > 0 and guard < 20000 do
    guard = guard + 1
    local bi, best = 1, math.huge
    for i, id in ipairs(open) do
      local f = cost[id] + h(id)
      if f < best then bi, best = i, f end
    end
    local cur = table.remove(open, bi)
    openSet[cur] = nil
    if cur == toId then
      local nodes, edges = { cur }, {}
      while came[cur] do
        table.insert(edges, 1, via[cur])
        cur = came[cur]
        table.insert(nodes, 1, cur)
      end
      return nodes, edges
    end
    for _, e in ipairs(self:exits(cur)) do
      if kindOk(kinds, e) then
        local nxt = M.other(e, cur)
        local c = cost[cur] + e.length
        if cost[nxt] == nil or c < cost[nxt] then
          cost[nxt], came[nxt], via[nxt] = c, cur, e
          if not openSet[nxt] then
            open[#open + 1] = nxt
            openSet[nxt] = true
          end
        end
      end
    end
  end
  return nil
end

return M
