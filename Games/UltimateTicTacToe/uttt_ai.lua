-- uttt_ai.lua
-- Computer opponent for Ultimate Tic-Tac-Toe: negamax with alpha-beta pruning, move ordering and iterative
-- deepening under a time or node budget, on top of a positional evaluation.
--
-- Levels: easy (mostly greedy with mistakes), medium (shallow search), hard (iterative deepening, ~1.5 s).
--   local ai = require("uttt_ai")
--   local b, c, info = ai.choose(state, "hard")

local rules = require("uttt_rules")

local M = {}

local LINES = rules.LINES
local WIN = 100000

-- A board in the middle, then corners, matters more than an edge board; same for cells inside a board.
local BOARD_WEIGHT = { 1.15, 1.0, 1.15, 1.0, 1.35, 1.0, 1.15, 1.0, 1.15 }
local CELL_WEIGHT = { 3, 2, 3, 2, 5, 2, 3, 2, 3 }

M.LEVELS = {
  easy = { depth = 1, mistakes = 0.35, ms = 0 },
  medium = { depth = 3, mistakes = 0.08, ms = 400 },
  hard = { depth = 12, mistakes = 0, ms = 1500 },
}

local function now()
  return os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
end

--- Value of a small board for p: line potentials plus a little positional credit.
local function boardScore(cells, base, p)
  local q = 3 - p
  local score = 0
  for li = 1, #LINES do
    local l = LINES[li]
    local mine, theirs = 0, 0
    for k = 1, 3 do
      local v = cells[base + l[k]]
      if v == p then mine = mine + 1 elseif v == q then theirs = theirs + 1 end
    end
    if theirs == 0 then
      if mine == 2 then score = score + 9 elseif mine == 1 then score = score + 1 end
    elseif mine == 0 then
      if theirs == 2 then score = score - 9 elseif theirs == 1 then score = score - 1 end
    end
  end
  for c = 1, 9 do
    local v = cells[base + c]
    if v == p then score = score + CELL_WEIGHT[c] * 0.3 elseif v == q then score = score - CELL_WEIGHT[c] * 0.3 end
  end
  return score
end

--- Static evaluation from the point of view of player p (positive is good for p).
function M.evaluate(s, p)
  local q = 3 - p
  local score = 0
  for b = 1, 9 do
    local owner = s.sub[b]
    local w = BOARD_WEIGHT[b]
    if owner == p then
      score = score + 100 * w
    elseif owner == q then
      score = score - 100 * w
    elseif owner == 0 then
      score = score + boardScore(s.cells, (b - 1) * 9, p) * w
    end
  end
  for li = 1, #LINES do
    local l = LINES[li]
    local mine, theirs, open = 0, 0, 0
    for k = 1, 3 do
      local v = s.sub[l[k]]
      if v == p then mine = mine + 1 elseif v == q then theirs = theirs + 1 elseif v == 0 then open = open + 1 end
    end
    if theirs == 0 and open + mine == 3 then
      if mine == 2 then score = score + 70 elseif mine == 1 then score = score + 12 end
    end
    if mine == 0 and open + theirs == 3 then
      if theirs == 2 then score = score - 70 elseif theirs == 1 then score = score - 12 end
    end
  end
  -- Free choice is worth a lot; whoever has it next gets it.
  if s.forced == nil and s.winner == 0 then
    if s.turn == p then score = score + 18 else score = score - 18 end
  end
  return score
end

--- Heuristic order key for a move (higher is searched first).
local function orderKey(s, idx, p)
  local b, c = rules.boardOf(idx), rules.cellOf(idx)
  local key = CELL_WEIGHT[c]
  if rules.wouldWinBoard(s, b, c, p) then key = key + 60 end
  if rules.wouldWinBoard(s, b, c, 3 - p) then key = key + 25 end -- block
  if s.sub[c] ~= 0 then
    key = key - 30 -- hands the opponent a free move
  elseif rules.canWinBoard(s, c, 3 - p) then
    key = key - 45 -- sends them to a board they can win now
  end
  return key
end

local function orderedMoves(s)
  local moves = rules.legalMoves(s)
  local p = s.turn
  local keys = {}
  for i = 1, #moves do keys[moves[i]] = orderKey(s, moves[i], p) end
  table.sort(moves, function(a, b)
    if keys[a] ~= keys[b] then return keys[a] > keys[b] end
    return a < b
  end)
  return moves
end

local search -- forward declaration (negamax)

local function checkBudget(ctx)
  ctx.nodes = ctx.nodes + 1
  if ctx.maxNodes and ctx.nodes >= ctx.maxNodes then ctx.aborted = true end
  if ctx.nodes % 64 == 0 then
    -- let the computer breathe: a long search without yielding can be descheduled or killed on a real server
    if ctx.yield then ctx.yield() end
    if ctx.deadline and now() >= ctx.deadline then ctx.aborted = true end
  end
end

search = function(s, depth, alpha, beta, ctx, ply)
  if s.winner ~= 0 then
    local me = s.turn -- the player to move would be the loser of the previous move
    if s.winner == 3 then return 0 end
    if s.winner == me then return WIN - ply end
    return -(WIN - ply)
  end
  checkBudget(ctx)
  if ctx.aborted then return 0 end
  if depth == 0 then return M.evaluate(s, s.turn) end

  local moves = orderedMoves(s)
  local best = -math.huge
  for i = 1, #moves do
    local idx = moves[i]
    rules.play(s, rules.boardOf(idx), rules.cellOf(idx))
    local v = -search(s, depth - 1, -beta, -alpha, ctx, ply + 1)
    rules.undo(s)
    if ctx.aborted then return 0 end
    if v > best then best = v end
    if v > alpha then alpha = v end
    if alpha >= beta then break end
  end
  return best
end

--- Score every legal move with a search of the given depth. Returns a list of { idx, score } or nil when
--- the budget ran out before the depth finished.
local function scoreMoves(s, depth, ctx, exact)
  local moves = orderedMoves(s)
  local out = {}
  local alpha = -math.huge
  for i = 1, #moves do
    local idx = moves[i]
    rules.play(s, rules.boardOf(idx), rules.cellOf(idx))
    -- exact scores for every root move when variety is wanted; otherwise prune against the best so far
    local v = -search(s, depth - 1, -math.huge, exact and math.huge or -alpha, ctx, 1)
    rules.undo(s)
    if ctx.aborted then return nil end
    out[#out + 1] = { idx = idx, score = v }
    if not exact and v > alpha then alpha = v end
  end
  return out
end

--- Pick a move for the player to move.
-- opts: seed (number), ms (override time budget), maxNodes (deterministic budget), depth (cap)
-- @return number b, number c, table info {level, depth, nodes, score}
function M.choose(state, level, opts)
  opts = opts or {}
  local cfg = M.LEVELS[level] or M.LEVELS.medium
  local s = rules.copy(state)
  local moves = rules.legalMoves(s)
  if #moves == 0 then return nil, nil, { level = level, depth = 0, nodes = 0 } end
  if #moves == 1 then
    return rules.boardOf(moves[1]), rules.cellOf(moves[1]), { level = level, depth = 0, nodes = 0, forced = true }
  end

  local p = s.turn
  -- Always take a win on the game, and never miss it at any level.
  for i = 1, #moves do
    local b, c = rules.boardOf(moves[i]), rules.cellOf(moves[i])
    rules.play(s, b, c)
    local won = s.winner == p
    rules.undo(s)
    if won then return b, c, { level = level, depth = 1, nodes = i, score = WIN } end
  end

  local rnd = opts.random or math.random
  if cfg.mistakes > 0 and rnd() < cfg.mistakes then
    local idx = moves[rnd(#moves)]
    return rules.boardOf(idx), rules.cellOf(idx), { level = level, depth = 0, nodes = 0, mistake = true }
  end

  local ctx = { nodes = 0, maxNodes = opts.maxNodes, yield = opts.yield }
  local ms = opts.ms or cfg.ms
  if ms and ms > 0 then ctx.deadline = now() + ms end
  local maxDepth = math.min(cfg.depth, opts.depth or cfg.depth)

  local best, bestDepth
  for depth = 1, maxDepth do
    local scored = scoreMoves(s, depth, ctx, level ~= "hard")
    if not scored then break end
    best, bestDepth = scored, depth
    table.sort(scored, function(a, b) return a.score > b.score end)
    if scored[1].score >= WIN - 50 or scored[1].score <= -(WIN - 50) then break end -- decided
  end

  if not best then
    -- budget was too small even for depth 1: fall back on move ordering
    local idx = moves[1]
    return rules.boardOf(idx), rules.cellOf(idx), { level = level, depth = 0, nodes = ctx.nodes, score = 0 }
  end

  -- Choose among moves within a small margin of the best so games vary, but never a losing one.
  local top = best[1].score
  local margin = level == "hard" and 0 or (level == "medium" and 6 or 25)
  local pool = {}
  for i = 1, #best do
    if best[i].score >= top - margin and (best[i].score > -(WIN - 50) or top <= -(WIN - 50)) then
      pool[#pool + 1] = best[i]
    end
  end
  local pick = pool[(opts.seed and (opts.seed % #pool) + 1) or rnd(#pool)]
  return rules.boardOf(pick.idx), rules.cellOf(pick.idx), {
    level = level, depth = bestDepth, nodes = ctx.nodes, score = pick.score,
  }
end

return M
