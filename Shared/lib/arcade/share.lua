-- arcade_share.lua
-- One floor, one set of saves. Every saved game, high score table, Versus wins table and board game record a cabinet writes
-- is also sent to the play tracker (Games/Tracker), which keeps the floor's master copy. Each cabinet asks the tracker for
-- anything new for the games it runs (when it starts, every few minutes, and when someone opens a ready screen) and merges
-- it into its own (merge.lua says how). So a player can save on one cabinet and carry on at another, and a new cabinet gets
-- the floor's scores and records the first time it asks.
--
-- A cabinet's own files are still its own: with no tracker, or no modem, nothing changes and nothing waits. What comes from
-- the tracker is written without being sent back, so nothing echoes.

local net = require("lib.arcade.net")

local M = {}

M.ASK_MS = 5 * 60000
M.WHATS = { save = true, scores = true, versus = true, records = true }

local STATE_FILE = "arcade_share.dat"

local appliers = {}   -- what -> function(game, player, data, at, deleted)
local games = {}      -- the game ids this cabinet runs
local state = nil     -- { seq = the tracker's last update number taken }
local applying = false
local askedAt = -1e15

local function now() return os.epoch("utc") end

local function loadState()
  if state then return state end
  state = { seq = 0 }
  if fs.exists(STATE_FILE) then
    local h = fs.open(STATE_FILE, "r")
    if h then
      local ok, value = pcall(textutils.unserialise, h.readAll() or "")
      h.close()
      if ok and type(value) == "table" and type(value.seq) == "number" then state = value end
    end
  end
  return state
end

local function saveState()
  local h = fs.open(STATE_FILE, "w")
  if h then
    h.write(textutils.serialise(state))
    h.close()
  end
end

--- The games this cabinet runs, by id: only those are asked for and taken.
function M.setGames(ids)
  games = {}
  for _, id in ipairs(ids or {}) do games[#games + 1] = id end
end

--- What to do with an update from the tracker, for one kind: fn(game, player, data, at, deleted).
function M.on(what, fn) appliers[what] = fn end

--- This cabinet changed something: tell the tracker. data nil with deleted = true for a saved game that ended.
function M.push(what, game, player, data, deleted)
  if applying or not M.WHATS[what] then return end
  net.share({ kind = "share", what = what, game = game, player = player, data = data, deleted = deleted or nil, at = now() })
end

--- Ask the tracker for anything new for this cabinet's games. Not more than once in 10 seconds unless forced.
function M.ask(force)
  local t = now()
  if not force and t - askedAt < 10000 then return end
  askedAt = t
  net.share({ kind = "shareask", after = loadState().seq, games = games })
end

--- Ask again every few minutes.
function M.tick()
  if now() - askedAt >= M.ASK_MS then M.ask(true) end
end

local function mine(game)
  for _, id in ipairs(games) do
    if id == game then return true end
  end
  return false
end

--- The tracker's answer: each update is merged in through its applier, and the place is kept.
function M.hear(_, msg, protocol)
  if protocol ~= net.PROTOCOL or type(msg) ~= "table" or msg.kind ~= "shared" or type(msg.entries) ~= "table" then return false end
  local st = loadState()
  -- a tracker that has started again from nothing counts from 1 again: take everything it has, merging changes nothing old
  if type(msg.top) == "number" and msg.top < st.seq then
    st.seq = 0
    saveState()
    M.ask(true)
    return true
  end
  applying = true
  for _, e in ipairs(msg.entries) do
    if type(e) == "table" and type(e.seq) == "number" then
      local fn = appliers[e.what]
      if fn and type(e.game) == "string" and mine(e.game) then pcall(fn, e.game, e.player, e.data, e.at, e.deleted) end
      if e.seq > st.seq then st.seq = e.seq end
    end
  end
  applying = false
  saveState()
  if msg.more then M.ask(true) end
  return true
end

-- for tests
function M.reset() state, applying, askedAt, appliers, games = nil, false, -1e15, {}, {} end
function M.isApplying() return applying end

return M
