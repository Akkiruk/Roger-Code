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

--- A saved game: the newer copy wins. Each is { at, ... } or { at, deleted = true } for one that ended.
function M.save(a, b)
  if not a then return copy(b) end
  if not b then return copy(a) end
  return copy((b.at or 0) > (a.at or 0) and b or a)
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
