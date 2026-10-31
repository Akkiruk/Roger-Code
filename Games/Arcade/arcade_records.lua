-- arcade_records.lua
-- Persistent player records for one game: ratings, leaderboards, head-to-head, achievements, match history and that
-- game's settings. Stored as one serialised table (atomic temp-file write). A game gives this its settings and
-- achievements; everything else is the same for every game. The two seats are always called red and blue.
-- boardsWon and boardsLost count whatever a game scores in a match; the names come from the first game and stay so
-- old records still load. The file layer is injectable so the logic can be tested without a filesystem.

local M = {}

M.VERSION = 2
M.START_ELO = 1000
M.HISTORY_LIMIT = 60
M.RECORDED_LIMIT = 40     -- match ids remembered, so a result can never count twice

local function defaultIO()
  return {
    exists = fs.exists,
    read = function(path)
      local h = fs.open(path, "r")
      if not h then return nil end
      local text = h.readAll()
      h.close()
      return text
    end,
    write = function(path, text)
      local h = fs.open(path, "w")
      if not h then return false end
      h.write(text)
      h.close()
      return true
    end,
    move = function(a, b)
      if fs.exists(b) then fs.delete(b) end
      fs.move(a, b)
    end,
    delete = fs.delete,
  }
end

local function nowMs()
  return os.epoch and os.epoch("utc") or 0
end

local function key(name)
  return string.lower(tostring(name or ""))
end

local function newPlayer(name, at)
  return {
    name = name, games = 0, wins = 0, losses = 0, draws = 0, elo = M.START_ELO, peak = M.START_ELO,
    streak = 0, bestStreak = 0, boardsWon = 0, boardsLost = 0, moves = 0, fastestWin = nil, longest = 0,
    seconds = 0, first = at, last = at, vsCpu = {}, h2h = {}, achievements = {},
    asRed = { games = 0, wins = 0 }, asBlue = { games = 0, wins = 0 },
  }
end

--- opts: path, settings (defaults), achievements (id -> { name, text }), award (see M:record), io, clock, log
function M.new(opts)
  opts = opts or {}
  local self = {
    path = opts.path,
    io = opts.io or defaultIO(),
    clock = opts.clock or nowMs,
    log = opts.log,
    defaults = opts.settings or {},
    achievementDefs = opts.achievements or {},
    award = opts.award,
    data = nil,
    dirty = false,
  }
  setmetatable(self, { __index = M })
  self.data = self:blank()
  return self
end

function M:blank()
  local settings = {}
  for k, v in pairs(self.defaults) do settings[k] = v end
  return {
    version = M.VERSION, players = {}, history = {}, settings = settings, recorded = {},
    totals = { games = 0, moves = 0, draws = 0 },
  }
end

function M:_log(msg)
  if self.log then self.log(msg) end
end

--- Load from disk; a missing file starts fresh, a damaged file is kept as .bak and replaced.
function M:load()
  local text = self.io.exists(self.path) and self.io.read(self.path) or nil
  if not text or text == "" then
    self.data = self:blank()
    return true, "fresh"
  end
  local ok, parsed = pcall(textutils.unserialise, text)
  if ok and type(parsed) == "table" and type(parsed.players) == "table" then
    local blank = self:blank()
    for k, v in pairs(blank) do
      if parsed[k] == nil then parsed[k] = v end
    end
    for k, v in pairs(blank.settings) do
      if parsed.settings[k] == nil then parsed.settings[k] = v end
    end
    -- version 2: the standard rule (a full board with no line is a draw) became the default
    if (parsed.version or 1) < 2 then
      parsed.settings.tiebreak = false
      parsed.version = M.VERSION
    end
    self.data = parsed
    return true, "loaded"
  end
  pcall(self.io.write, self.path .. ".bak", text)
  self:_log("data file unreadable, kept a .bak and started fresh")
  self.data = self:blank()
  return false, "corrupt"
end

--- Save atomically: write a temp file, then replace the real one.
function M:save()
  local tmp = self.path .. ".tmp"
  local ok = self.io.write(tmp, textutils.serialise(self.data))
  if not ok then
    self:_log("could not write " .. tmp)
    return false
  end
  self.io.move(tmp, self.path)
  self.dirty = false
  return true
end

function M:get(name)
  return self.data.players[key(name)]
end

function M:ensure(name)
  local k = key(name)
  local p = self.data.players[k]
  if not p then
    p = newPlayer(name, self.clock())
    self.data.players[k] = p
  end
  return p
end

function M:setting(name, value)
  if value ~= nil then
    self.data.settings[name] = value
    self.dirty = true
  end
  return self.data.settings[name]
end

--- Elo with a larger K for new players. score is 1, 0.5 or 0 for a.
function M.eloDelta(ra, rb, score, games)
  local k = (games or 0) < 10 and 40 or 24
  local expected = 1 / (1 + 10 ^ ((rb - ra) / 400))
  local change = k * (score - expected)
  -- round the same way on both sides, so what the winner gains is what the loser drops
  if change >= 0 then return math.floor(change + 0.5) end
  return -math.floor(-change + 0.5)
end

local function bumpRecord(t, k, result)
  local r = t[k]
  if not r then r = { w = 0, l = 0, d = 0 }; t[k] = r end
  if result == "w" then r.w = r.w + 1 elseif result == "l" then r.l = r.l + 1 else r.d = r.d + 1 end
end

--- Record a finished game.
-- m = { red, blue, redCpu, blueCpu (level strings or nil), winner (1|2|3), moves, seconds, boardsRed,
--       boardsBlue, trailed (max small-board deficit of the winner), forfeit (1|2|nil), tiebreak }
-- matchId, when given, makes this safe to call twice: a match already recorded changes nothing and returns nil.
-- Returns a summary { red = {name, delta, elo, ...}, blue = {...}, ranked = bool, achievements = {...} }.
-- The award hook gets { m, sides, players, ranked, summary, now, grant = function(player, id) } after the records move.
function M:record(m)
  local recorded = self.data.recorded
  if m.matchId then
    for _, id in ipairs(recorded) do
      if id == m.matchId then return nil, "already recorded" end
    end
  end
  local now = self.clock()
  local summary = { ranked = false, achievements = {}, red = {}, blue = {} }
  local redCpu, blueCpu = m.redCpu, m.blueCpu
  summary.red.name, summary.blue.name = m.red, m.blue
  summary.red.cpu, summary.blue.cpu = redCpu, blueCpu
  if redCpu and blueCpu then return summary end -- demo game, nothing to record
  if m.matchId then
    recorded[#recorded + 1] = m.matchId
    while #recorded > M.RECORDED_LIMIT do table.remove(recorded, 1) end
  end

  local ranked = (not redCpu) and (not blueCpu) and key(m.red) ~= key(m.blue)
  summary.ranked = ranked

  local t = self.data.totals
  t.games = t.games + 1
  t.moves = t.moves + (m.moves or 0)
  if m.winner == 3 then t.draws = t.draws + 1 end

  local sides = {
    { name = m.red, cpu = redCpu, side = "red", num = 1, boards = m.boardsRed or 0, other = m.boardsBlue or 0, oppName = m.blue, oppCpu = blueCpu },
    { name = m.blue, cpu = blueCpu, side = "blue", num = 2, boards = m.boardsBlue or 0, other = m.boardsRed or 0, oppName = m.red, oppCpu = redCpu },
  }
  local players = {}
  for i, sd in ipairs(sides) do
    if not sd.cpu then players[i] = self:ensure(sd.name) end
  end

  -- ratings first, from the pre-game values
  local deltas = { 0, 0 }
  if ranked then
    local a, b = players[1], players[2]
    local scoreA = m.winner == 1 and 1 or (m.winner == 2 and 0 or 0.5)
    deltas[1] = M.eloDelta(a.elo, b.elo, scoreA, a.games)
    deltas[2] = M.eloDelta(b.elo, a.elo, 1 - scoreA, b.games)
  end

  for i, sd in ipairs(sides) do
    local p = players[i]
    local res = summary[sd.side]
    if p then
      local result = m.winner == 3 and "d" or (m.winner == sd.num and "w" or "l")
      local before = p.elo
      p.games = p.games + 1
      p.moves = p.moves + math.ceil((m.moves or 0) / 2)
      p.seconds = p.seconds + (m.seconds or 0)
      p.last = now
      p.boardsWon = p.boardsWon + sd.boards
      p.boardsLost = p.boardsLost + sd.other
      if (m.moves or 0) > p.longest then p.longest = m.moves end
      local sideRec = sd.side == "red" and p.asRed or p.asBlue
      sideRec.games = sideRec.games + 1
      if result == "w" then
        p.wins = p.wins + 1
        sideRec.wins = sideRec.wins + 1
        p.streak = p.streak > 0 and p.streak + 1 or 1
        if not m.forfeit and (not p.fastestWin or m.moves < p.fastestWin) then p.fastestWin = m.moves end
      elseif result == "l" then
        p.losses = p.losses + 1
        p.streak = p.streak < 0 and p.streak - 1 or -1
      else
        p.draws = p.draws + 1
        p.streak = 0
      end
      if p.streak > p.bestStreak then p.bestStreak = p.streak end
      if sd.oppCpu then
        bumpRecord(p.vsCpu, sd.oppCpu, result)
      else
        bumpRecord(p.h2h, key(sd.oppName), result)
      end
      if ranked then
        p.elo = p.elo + deltas[i]
        if p.elo > p.peak then p.peak = p.elo end
      end
      res.delta, res.elo, res.before = ranked and deltas[i] or 0, p.elo, before
      res.result, res.streak, res.games = result, p.streak, p.games
    end
  end

  -- achievements belong to the game
  if self.award then
    self.award({
      m = m, sides = sides, players = players, ranked = ranked, summary = summary, now = now,
      grant = function(p, id)
        if p and not p.achievements[id] then
          p.achievements[id] = now
          local def = self.achievementDefs[id]
          summary.achievements[#summary.achievements + 1] = { player = p.name, id = id, name = def and def.name or id }
        end
      end,
    })
  end

  -- history
  local h = self.data.history
  h[#h + 1] = {
    at = now, red = m.red, blue = m.blue, redCpu = redCpu, blueCpu = blueCpu, winner = m.winner,
    moves = m.moves, seconds = m.seconds, boardsRed = m.boardsRed, boardsBlue = m.boardsBlue, forfeit = m.forfeit,
    redDelta = summary.red.delta, blueDelta = summary.blue.delta,
  }
  while #h > M.HISTORY_LIMIT do table.remove(h, 1) end
  self.dirty = true
  return summary
end

--- All real players (no computers) as a list.
function M:players()
  local list = {}
  for _, p in pairs(self.data.players) do list[#list + 1] = p end
  return list
end

local function winRate(p)
  if p.games == 0 then return 0 end
  return (p.wins + p.draws * 0.5) / p.games
end
M.winRate = winRate

M.BOARDS = {
  elo = { title = "RATING", value = function(p) return p.elo end, min = 1 },
  wins = { title = "WINS", value = function(p) return p.wins end, min = 1, minValue = 1 },
  rate = { title = "WIN %", value = function(p) return math.floor(winRate(p) * 100 + 0.5) end, min = 5, suffix = "%" },
  streak = { title = "BEST STREAK", value = function(p) return p.bestStreak end, min = 1, minValue = 1 },
  boards = { title = "BOARDS", value = function(p) return p.boardsWon end, min = 1, minValue = 1 },
}
M.BOARD_ORDER = { "elo", "wins", "rate", "streak", "boards" }

--- Leaderboard: list of { rank, name, value, player }. Ties share a rank.
function M:leaderboard(kind, limit)
  local def = M.BOARDS[kind] or M.BOARDS.elo
  local rows = {}
  for _, p in pairs(self.data.players) do
    local v = def.value(p)
    if p.games >= def.min and (not def.minValue or v >= def.minValue) then rows[#rows + 1] = { name = p.name, value = v, player = p } end
  end
  table.sort(rows, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    if a.player.wins ~= b.player.wins then return a.player.wins > b.player.wins end
    return string.lower(a.name) < string.lower(b.name)
  end)
  local out, last, lastRank = {}, nil, 0
  for i, r in ipairs(rows) do
    if r.value ~= last then lastRank = i; last = r.value end
    r.rank = lastRank
    if not limit or i <= limit then out[#out + 1] = r end
  end
  return out, #rows
end

--- Rank of a player on a board, or nil if not listed.
function M:rank(name, kind)
  local rows = self:leaderboard(kind or "elo")
  for _, r in ipairs(rows) do
    if key(r.name) == key(name) then return r.rank, #rows end
  end
  return nil, #rows
end

function M:recent(limit)
  local out, h = {}, self.data.history
  for i = #h, math.max(1, #h - (limit or 10) + 1), -1 do out[#out + 1] = h[i] end
  return out
end

--- Head-to-head of a against b: w, l, d from a's side.
function M:headToHead(a, b)
  local p = self:get(a)
  local r = p and p.h2h[key(b)]
  if not r then return { w = 0, l = 0, d = 0 } end
  return { w = r.w, l = r.l, d = r.d }
end

function M:achievements(name)
  local p = self:get(name)
  local out = {}
  if p then
    for id, at in pairs(p.achievements) do out[#out + 1] = { id = id, at = at, name = self.achievementDefs[id] and self.achievementDefs[id].name or id } end
  end
  table.sort(out, function(x, y) return x.at < y.at end)
  return out
end

--- Wipe all records (settings stay).
function M:reset()
  local settings = self.data.settings
  self.data = self:blank()
  self.data.settings = settings
  self.dirty = true
end

return M
