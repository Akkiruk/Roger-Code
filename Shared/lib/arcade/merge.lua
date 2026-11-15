-- arcade_merge.lua
-- How two copies of the same saved data become one, for the play tracker's hub (lib/tracker/shared.lua) and the cabinets
-- that take copies from it (share.lua). Every merge is pure, keeps nothing that's in neither copy, and gives the same answer
-- whichever copy comes first, so a cabinet and the hub can merge back and forth and settle on the same thing.

local M = {}

M.SCORES_KEPT = 10
M.HISTORY_KEPT = 60
M.RECORDED_KEPT = 40
M.CHAMPIONS_KEPT = 12

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
M.copy = copy

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end
M.same = same

M.ENDED_KEPT = 30

--- Does x know that y's playthrough is over (ended, or replaced by NEW GAME)?
local function knowsEnded(x, y)
  if type(y.run) ~= "string" or type(x.ended) ~= "table" then return false end
  for _, run in ipairs(x.ended) do
    if run == y.run then return true end
  end
  return false
end

--- Every playthrough either copy knows is over, newest last, kept short.
local function endedOf(a, b)
  local seen, out = {}, {}
  for _, list in ipairs({ a.ended or {}, b.ended or {} }) do
    for _, run in ipairs(list) do
      if type(run) == "string" and not seen[run] then seen[run] = true; out[#out + 1] = run end
    end
  end
  while #out > M.ENDED_KEPT do table.remove(out, 1) end
  return out
end

--- Of two copies of one player's save, the one to keep, before the ended lists are pooled.
local function pick(a, b, rankOf)
  -- a playthrough one copy knows has ended never comes back, however far it got
  local aKnows, bKnows = knowsEnded(a, b), knowsEnded(b, a)
  if aKnows and not bKnows then return a end
  if bKnows and not aKnows then return b end
  local newer = (b.at or 0) > (a.at or 0) and b or a
  local sameRun = type(a.run) == "string" and a.run == b.run
  if sameRun and (a.deleted or b.deleted) then
    -- the run ended: the ending stands
    if a.deleted and b.deleted then return newer end
    return a.deleted and a or b
  end
  if a.deleted or b.deleted then
    -- the end of some other playthrough says nothing about this one; with no way to tell them apart, the newer stands
    if type(a.run) == "string" or type(b.run) == "string" then return a.deleted and b or a end
    return newer
  end
  -- two saves: the one furthest along, whichever is newer. A copy whose progress can't be told loses only to one whose can
  local ra, rb = rankOf(a), rankOf(b)
  if ra and rb and ra ~= rb then return ra > rb and a or b end
  return newer
end

--- A saved game: the copy with the most progress wins, not the newest (the owner's choice), except that a playthrough that
--- has ended, by finishing or by NEW GAME, stays ended. Each is a save { at, run, rank, ended, ... } or a marker
--- { at, deleted = true, run, ended } for a run that ended. rank is the game's own measure of progress, written with the save
--- (saves.rank); rankOf may work it out where the game is at hand. Saves from before ranks and runs go by time, as they did.
function M.save(a, b, rankOf)
  if not a then return copy(b) end
  if not b then return copy(a) end
  rankOf = rankOf or function(s) return type(s.rank) == "number" and s.rank or nil end
  local out = copy(pick(a, b, rankOf))
  local ended = endedOf(a, b)
  if #ended > 0 then out.ended = ended end
  return out
end

--- Of two copies, the one pick left out, if it is a live playthrough nobody has ended: the hub keeps it aside, so a save is never
--- lost to a choice made without the game at hand.
function M.saveLeftOut(a, b, kept)
  if not (a and b and kept) then return nil end
  local out = (kept.run == a.run and kept.at == a.at) and b or a
  if out.deleted or knowsEnded(kept, out) then return nil end
  if type(out.run) == "string" and out.run == kept.run then return nil end -- the same run, further along: nothing lost
  return out
end

--- A high score table: every run from both, once each, best first, the top ten.
function M.scores(a, b)
  local seen, rows = {}, {}
  for _, list in ipairs({ a or {}, b or {} }) do
    for _, row in ipairs(list) do
      if type(row) == "table" and type(row.score) == "number" then
        local k = tostring(row.name) .. "|" .. row.score .. "|" .. tostring(row.level) .. "|" .. tostring(row.at)
        if not seen[k] then
          seen[k] = true
          rows[#rows + 1] = copy(row)
        end
      end
    end
  end
  table.sort(rows, function(x, y)
    if x.score ~= y.score then return x.score > y.score end
    return (x.at or 0) < (y.at or 0)
  end)
  while #rows > M.SCORES_KEPT do table.remove(rows) end
  return rows
end

--- Versus wins: each player's row from whichever copy has seen more of their matches.
function M.versus(a, b)
  local by = {}
  for _, list in ipairs({ a or {}, b or {} }) do
    for _, row in ipairs(list) do
      if type(row) == "table" and row.name then
        local have = by[row.name]
        local n = (row.wins or 0) + (row.losses or 0)
        if not have or n > (have.wins or 0) + (have.losses or 0) then by[row.name] = copy(row) end
      end
    end
  end
  local rows = {}
  for _, row in pairs(by) do rows[#rows + 1] = row end
  table.sort(rows, function(x, y)
    if x.wins ~= y.wins then return x.wins > y.wins end
    if x.losses ~= y.losses then return x.losses < y.losses end
    return x.name < y.name
  end)
  return rows
end

local function union(a, b, keyOf, order, limit)
  local seen, out = {}, {}
  for _, list in ipairs({ a or {}, b or {} }) do
    for _, item in ipairs(list) do
      local k = keyOf(item)
      if not seen[k] then
        seen[k] = true
        out[#out + 1] = copy(item)
      end
    end
  end
  if order then table.sort(out, order) end
  while #out > limit do table.remove(out, order and #out or 1) end
  return out
end

local function historyKey(h)
  return type(h) == "table" and (tostring(h.at) .. "|" .. tostring(h.red) .. "|" .. tostring(h.blue) .. "|" .. tostring(h.winner)) or tostring(h)
end

--- A board game's records (records.lua). Each player's row comes from whichever copy has seen more of their games; the
--- histories, the matches already counted and the season champions are pooled. Settings are each cabinet's own, so `mine`
--- keeps its own and the hub never hands them out.
function M.records(mine, theirs)
  if type(mine) ~= "table" then return copy(theirs) end
  if type(theirs) ~= "table" then return copy(mine) end
  local out = copy(mine)
  out.players = copy(mine.players or {})
  for k, row in pairs(theirs.players or {}) do
    local have = out.players[k]
    if type(row) == "table" and (not have or (row.games or 0) > (have.games or 0)
      or ((row.games or 0) == (have.games or 0) and (row.last or 0) > (have.last or 0))) then
      out.players[k] = copy(row)
    end
  end
  -- history oldest first, the newest kept
  out.history = union(mine.history, theirs.history, historyKey, function(x, y) return (x.at or 0) < (y.at or 0) end, M.HISTORY_KEPT)
  while #out.history > M.HISTORY_KEPT do table.remove(out.history, 1) end
  out.recorded = union(mine.recorded, theirs.recorded, tostring, nil, M.RECORDED_KEPT * 2)
  while #out.recorded > M.RECORDED_KEPT do table.remove(out.recorded, 1) end
  out.champions = union(mine.champions, theirs.champions, function(c) return tostring(c.season) .. "|" .. tostring(c.name) end,
    function(x, y) return tostring(x.season) > tostring(y.season) end, M.CHAMPIONS_KEPT)
  out.totals = copy(mine.totals or {})
  for k, v in pairs(theirs.totals or {}) do
    if type(v) == "number" and v > (out.totals[k] or 0) then out.totals[k] = v end
  end
  if tostring(theirs.season or "") > tostring(out.season or "") then out.season = theirs.season end
  return out
end

--- One of the four kinds by name: "save", "scores", "versus" or "records".
function M.by(what, a, b)
  if what == "save" then return M.save(a, b) end
  if what == "scores" then return M.scores(a, b) end
  if what == "versus" then return M.versus(a, b) end
  if what == "records" then return M.records(a, b) end
  return nil
end

return M
