-- games/mancala/rules.lua
-- Mancala, the Kalah rules with six pits a side and four seeds in each. Pure: no screen, sound or files.
-- Each seat numbers its own pits 1 to 6 from its own left, sows toward 6, then its store, then the other side's pits.
-- Pit i on one side faces pit 7 - i on the other.

local M = { PITS = 6, SEEDS = 4 }

local PITS = M.PITS

function M.new(opts)
  local s = { turn = opts.first or 1, winner = 0, moves = 0, pits = { {}, {} }, stores = { 0, 0 } }
  for i = 1, PITS do
    s.pits[1][i], s.pits[2][i] = M.SEEDS, M.SEEDS
  end
  return s
end

local function sideEmpty(s, seat)
  for i = 1, PITS do
    if s.pits[seat][i] > 0 then return false end
  end
  return true
end

function M.checkAction(s, a)
  if s.winner ~= 0 then return false, "game over" end
  if a.kind == "forfeit" then return true end
  if a.kind ~= "sow" or not s.pits[s.turn][a.pit] then return false, "no such pit" end
  if s.pits[s.turn][a.pit] == 0 then return false, "That pit is empty" end
  return true
end

function M.step(s, a)
  local ok, why = M.checkAction(s, a)
  if not ok then return nil, why end
  if a.kind == "forfeit" then
    s.winner, s.forfeit = 3 - a.seat, a.seat
    return s, {}
  end
  local p, other = s.turn, 3 - s.turn
  local seeds = s.pits[p][a.pit]
  s.pits[p][a.pit] = 0
  local side, pit = p, a.pit -- where the last seed went; pit 7 is the mover's store
  local landedOn = 0
  while seeds > 0 do
    pit = pit + 1
    if side == p and pit == PITS + 1 then
      s.stores[p] = s.stores[p] + 1
      landedOn = -1
    elseif pit > PITS then
      side, pit = 3 - side, 1
      landedOn = s.pits[side][pit]
      s.pits[side][pit] = landedOn + 1
    else
      landedOn = s.pits[side][pit]
      s.pits[side][pit] = landedOn + 1
    end
    seeds = seeds - 1
  end
  s.moves = s.moves + 1
  local inStore = landedOn == -1
  local ev = { type = "sow", seat = p, pit = a.pit, side = side, last = inStore and 0 or pit, again = inStore }
  if not inStore and side == p and landedOn == 0 then
    local across = PITS + 1 - pit
    local taken = s.pits[other][across]
    if taken > 0 then
      s.stores[p] = s.stores[p] + taken + 1
      s.pits[other][across], s.pits[p][pit] = 0, 0
      ev.captured = taken + 1
    end
  end
  if sideEmpty(s, 1) or sideEmpty(s, 2) then
    for seat = 1, 2 do
      for i = 1, PITS do
        s.stores[seat] = s.stores[seat] + s.pits[seat][i]
        s.pits[seat][i] = 0
      end
    end
    local a1, a2 = s.stores[1], s.stores[2]
    s.winner = a1 > a2 and 1 or (a2 > a1 and 2 or 3)
    return s, { ev }
  end
  if not inStore then s.turn = other end
  return s, { ev }
end

function M.legalActions(s)
  local out = {}
  if s.winner ~= 0 then return out end
  for i = 1, PITS do
    if s.pits[s.turn][i] > 0 then out[#out + 1] = { kind = "sow", pit = i } end
  end
  return out
end

function M.key(a) return tostring(a.pit) end

function M.snapshot(s)
  local function copy(t)
    local out = {}
    for i, v in ipairs(t) do out[i] = v end
    return out
  end
  return { pits = { copy(s.pits[1]), copy(s.pits[2]) }, stores = { s.stores[1], s.stores[2] } }
end

return M
