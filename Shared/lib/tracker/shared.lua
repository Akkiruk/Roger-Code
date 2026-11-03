-- tracker/shared.lua
-- The floor's master copy of every cabinet's saved data: saved games, high score tables, Versus wins and board game records
-- (lib/arcade/share.lua sends them, lib/arcade/merge.lua says how two copies become one). Each change the tracker takes gets
-- the next number, and a cabinet asks for everything after the last number it has, for the games it runs. Plain data, so it
-- tests on its own; the tracker's app keeps it on disk.

local merge = require("lib.arcade.merge")

local M = {}

M.PAGE = 12          -- entries in one answer; the cabinet asks again for the rest
local MAX_ID, MAX_NAME = 64, 32
local KINDS = { save = true, scores = true, versus = true, records = true }

local function text(v, n) return type(v) == "string" and v ~= "" and #v <= n and v or nil end

function M.new()
  return { v = 1, seq = 0, entries = {} }
end

local function keyOf(what, game, player)
  return what .. "|" .. game .. "|" .. (player or "")
end

--- A cabinet's change: merged into the master copy. Returns true if the master copy changed.
function M.put(sh, msg, at)
  local what, game = msg.what, text(msg.game, MAX_ID)
  if not (KINDS[what] and game) then return false end
  local player = nil
  if what == "save" then
    player = text(msg.player, MAX_NAME)
    if not player then return false end
  end
  local incoming
  if what == "save" then
    if msg.deleted then
      incoming = { at = tonumber(msg.at) or at, deleted = true }
    elseif type(msg.data) == "table" and type(msg.data.at) == "number" then
      incoming = msg.data
    else
      return false
    end
  elseif type(msg.data) == "table" then
    incoming = msg.data
  else
    return false
  end
  local key = keyOf(what, game, player)
  local e = sh.entries[key]
  local merged = merge.by(what, e and e.data, incoming)
  if e and merge.same(merged, e.data) then return false end
  sh.seq = sh.seq + 1
  sh.entries[key] = { seq = sh.seq, what = what, game = game, player = player, data = merged, at = at }
  return true
end

--- What a cabinet asked for: the entries after `after`, for its games, oldest change first, a page at a time.
function M.since(sh, after, games)
  local wanted
  if type(games) == "table" and #games > 0 then
    wanted = {}
    for _, g in ipairs(games) do wanted[g] = true end
  end
  local list = {}
  for _, e in pairs(sh.entries) do
    if e.seq > (tonumber(after) or 0) and (not wanted or wanted[e.game]) then list[#list + 1] = e end
  end
  table.sort(list, function(a, b) return a.seq < b.seq end)
  local out = {}
  for i = 1, math.min(#list, M.PAGE) do
    local e = list[i]
    local data = e.data
    if e.what == "save" and data and data.deleted then
      out[i] = { seq = e.seq, what = e.what, game = e.game, player = e.player, deleted = true, at = data.at }
    else
      out[i] = { seq = e.seq, what = e.what, game = e.game, player = e.player, data = data, at = data and data.at or e.at }
    end
  end
  -- a page that stops early is still a page: the cabinet takes the place of its last entry and asks again
  return { kind = "shared", entries = out, more = #list > M.PAGE, top = sh.seq }
end

--- How much is held, for the tracker's screen.
function M.counts(sh)
  local out = { save = 0, scores = 0, versus = 0, records = 0 }
  for _, e in pairs(sh.entries) do
    if not (e.what == "save" and e.data and e.data.deleted) then out[e.what] = (out[e.what] or 0) + 1 end
  end
  return out
end

return M
