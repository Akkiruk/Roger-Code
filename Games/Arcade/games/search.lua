-- games/search.lua
-- A computer player for any game with no hidden pieces: alpha-beta search over the game's own rules, deepening until it
-- runs out of depth or time. The side to move can stay the same across a move (an extra turn, a pass, a jump that carries
-- on), so each node asks whose turn it is. A game supplies how a position looks to it and how much each level plays.

local M = {}

local WIN = 1000000
local LEVEL_MS = 1500
local YIELD_EVERY = 150
local inf = math.huge

--- A deep copy of plain data.
local function clone(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = clone(x) end
  return out
end
M.clone = clone

local function shuffled(list)
  for i = #list, 2, -1 do
    local j = math.random(i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

--- Best action for the side to move.
-- rules: the game's rules. eval(state, seat): how good a position is for seat, higher is better.
-- level: { depth, blunder = chance of a random move, ms }. opts: ms, maxNodes, yield.
-- Returns action, { depth, nodes, score }.
function M.best(rules, state, eval, level, opts)
  opts = opts or {}
  local moves = shuffled(rules.legalActions(state))
  if #moves == 0 then return nil end
  if #moves == 1 then return moves[1], { depth = 0, nodes = 0, score = 0 } end
  if level.blunder and math.random() < level.blunder then return moves[1], { depth = 0, nodes = 0, score = 0 } end

  local me = state.turn
  local stopAt = os.epoch("utc") + (opts.ms or level.ms or LEVEL_MS)
  local maxNodes = opts.maxNodes or inf
  local nodes, stopped = 0, false

  local function search(s, depth, alpha, beta, ply)
    nodes = nodes + 1
    if nodes % YIELD_EVERY == 0 then
      if opts.yield then opts.yield() end
      if os.epoch("utc") >= stopAt or nodes >= maxNodes then stopped = true end
    end
    if s.winner ~= 0 then
      if s.winner == 3 then return 0 end
      return s.winner == me and WIN - ply or ply - WIN
    end
    if depth <= 0 or stopped then return eval(s, me) end
    local maximizing = s.turn == me
    local best = maximizing and -inf or inf
    for _, a in ipairs(rules.legalActions(s)) do
      local v = search(rules.step(clone(s), a), depth - 1, alpha, beta, ply + 1)
      if maximizing then
        if v > best then best = v end
        if v > alpha then alpha = v end
      else
        if v < best then best = v end
        if v < beta then beta = v end
      end
      if alpha >= beta or stopped then break end
    end
    return best
  end

  local chosen, score, reached = moves[1], 0, 0
  for depth = 1, level.depth do
    local bestHere, valueHere = nil, -inf
    for _, a in ipairs(moves) do
      local v = search(rules.step(clone(state), a), depth - 1, valueHere, inf, 1)
      if stopped then break end
      if v > valueHere then bestHere, valueHere = a, v end
    end
    if stopped then break end -- an unfinished depth proves nothing, so it is thrown away
    chosen, score, reached = bestHere, valueHere, depth
    for i, a in ipairs(moves) do
      if a == bestHere then
        table.remove(moves, i)
        table.insert(moves, 1, a)
        break
      end
    end
    if valueHere >= WIN - 1000 then break end -- a forced win needs no deeper look
  end
  return chosen, { depth = reached, nodes = nodes, score = score }
end

return M
