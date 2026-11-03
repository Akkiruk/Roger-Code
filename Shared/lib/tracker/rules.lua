-- tracker/rules.lua
-- The tracker's books, as plain data. The tracker counts nothing itself: every Arcade cabinet keeps its own record of the
-- games played on it (lib/arcade/track.lua) and every casino table keeps its own record of its players (lib/casino/stats.lua).
-- The tracker collects those records and adds them up across the floor.
--
--   arcade.v1 "log"    a cabinet's finished sessions after the number the tracker asked from. Each has a number, so one is
--                      never counted twice, and the tracker remembers the last number it has from each cabinet.
--   casino.v2 "stats"  a table's whole record of its players, kept as the latest copy from each table.
--   arcade.v1 "play", casino.v2 "round"   what's going on right now, for the NOW page only: a game finishing, or a round,
--                      is also the tracker's cue to ask that computer for its record again.
-- Nothing here touches the screen, the disk or the network, so it tests on its own.

local M = {}

M.LIVE_STALE_MS = 3 * 60000   -- a game not heard from for this long has stopped
M.CASINO_LIVE_MS = 5 * 60000  -- someone at a table is still there this long after a round
M.RECENT = 80                 -- finished games kept for the RECENT page

local MAX_NAME, MAX_ID, MAX_TEXT = 32, 64, 60
local MAX_MS = 24 * 3600000 -- no one session is honestly longer than a day
local NOT_PEOPLE = { Computer = true, ["?"] = true, [""] = true }

local function text(v, n) return type(v) == "string" and v ~= "" and (v:gsub("%c", "")):sub(1, n) or nil end
local function number(v, lo, hi) return type(v) == "number" and v == v and v >= (lo or 0) and v <= (hi or 1e12) and v or nil end

function M.new()
  return { v = 2, cabinets = {}, tables = {}, players = {}, games = {}, live = {}, recent = {}, want = {} }
end

--- A game's own title from its id, for when none is given: "three_card_poker" becomes "Three Card Poker".
local function titled(id)
  return (id:gsub("[_%-]", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

local function names(list)
  if type(list) ~= "table" or #list < 1 or #list > 8 then return nil end
  local out = {}
  for i, name in ipairs(list) do out[i] = text(name, MAX_NAME) or "?" end
  return out
end

local function people(list)
  local out = {}
  for _, name in ipairs(list or {}) do
    if not NOT_PEOPLE[name] then out[#out + 1] = name end
  end
  return out
end

local function remember(d, item)
  d.recent[#d.recent + 1] = item
  table.sort(d.recent, function(a, b) return (a.at or 0) > (b.at or 0) end)
  while #d.recent > M.RECENT do table.remove(d.recent) end
end

-- ---------------------------------------------------------------- an Arcade cabinet's own record

local function addSession(d, cab, s)
  local game, players = text(s.game, MAX_ID), names(s.players)
  local ms = number(s.ms, 0, MAX_MS)
  if not (game and players and ms) then return end
  local title = text(s.title, MAX_TEXT) or titled(game)
  local at = number(s.at, 0, 1e14) or 0
  local g = d.games[game] or { title = title, ms = 0, sessions = 0, players = {}, last = 0 }
  d.games[game] = g
  g.title, g.ms, g.sessions, g.last = title, g.ms + ms, g.sessions + 1, math.max(g.last, at)
  local winner = text(s.winner, MAX_NAME)
  local them = people(players)
  for _, name in ipairs(them) do
    g.players[name] = true
    local p = d.players[name] or { ms = 0, sessions = 0, games = {}, last = 0 }
    d.players[name] = p
    local e = p.games[game] or { title = title, ms = 0, sessions = 0, wins = 0, losses = 0 }
    p.games[game] = e
    e.title = title
    p.ms, p.sessions, p.last = p.ms + ms, p.sessions + 1, math.max(p.last, at)
    e.ms, e.sessions, e.last = e.ms + ms, e.sessions + 1, math.max(e.last or 0, at)
    local score, level, percent = number(s.score, -1e12), number(s.level, 0, 1e6), number(s.percent, 0, 100)
    if score and (not e.best or score > e.best) then e.best = score end
    if level and (not e.level or level > e.level) then e.level = level end
    if percent then e.percent = math.max(e.percent or 0, percent) end
    local goal = text(s.goal, MAX_TEXT)
    if goal and at >= (e.goalAt or 0) then e.goal, e.goalAt = goal, at end
    if winner and winner ~= "draw" and #players > 1 then
      if name == winner then e.wins = e.wins + 1 else e.losses = e.losses + 1 end
    end
  end
  local note = winner and (winner == "draw" and "a draw" or (winner .. " won")) or (s.abandoned and "stopped") or (s.cut and "cut off")
  if not note and number(s.percent, 0, 100) then note = s.percent .. "% of the story" end
  if not note and number(s.score, -1e12) then note = "score " .. s.score end
  remember(d, { at = at, title = title, players = players, ms = ms, note = note, cabinet = cab.label })
end

local function onLog(d, sender, m)
  local id = tostring(number(m.computer) or sender)
  if type(m.sessions) ~= "table" or #m.sessions > 200 then return false end
  local cab = d.cabinets[id] or { seq = 0 }
  d.cabinets[id] = cab
  cab.label = text(m.cabinet, MAX_TEXT) or cab.label
  -- a cabinet whose numbers went backwards has lost its record (wiped and reinstalled): start again from its first
  local theirs = number(m.seq)
  if theirs and theirs < cab.seq then cab.seq = 0 end
  local changed = false
  for _, s in ipairs(m.sessions) do
    local seq = type(s) == "table" and number(s.seq)
    if seq and seq > cab.seq then
      addSession(d, cab, s)
      cab.seq = seq
      changed = true
    end
  end
  if m.more == true then d.want[id] = true end
  return changed
end

-- ---------------------------------------------------------------- a casino table's own record

local function onStats(d, sender, m)
  local id = tostring(number(m.computer) or sender)
  local game = text(m.game, MAX_ID)
  if not game or type(m.players) ~= "table" then return false end
  local players, count = {}, 0
  for name, p in pairs(m.players) do
    local n = text(name, MAX_NAME)
    if n and type(p) == "table" and count < 300 then
      count = count + 1
      players[n] = {
        rounds = number(p.rounds) or 0, wagered = number(p.wagered) or 0, net = number(p.net, -1e12) or 0,
        best = number(p.best, -1e12) or 0, ms = number(p.ms) or 0, sessions = number(p.sessions) or 0, last = number(p.last) or 0,
      }
    end
  end
  d.tables[id] = { game = game, title = text(m.title, MAX_TEXT) or titled(game), players = players, cabinet = text(m.cabinet, MAX_TEXT) }
  return true
end

-- ---------------------------------------------------------------- what's on now

local function onPlay(d, sender, m, at)
  local id, game, players = text(m.id, MAX_ID), text(m.game, MAX_ID), names(m.players)
  if not (id and game and players and (m.phase == "start" or m.phase == "beat" or m.phase == "end")) then return false end
  if m.phase == "end" then
    d.live[id] = nil
    d.want[tostring(sender)] = true -- the finished game is in that cabinet's record now
    return true
  end
  d.live[id] = {
    game = game, title = text(m.title, MAX_TEXT) or titled(game), players = players, cabinet = text(m.cabinet, MAX_TEXT),
    ms = number(m.ms, 0, MAX_MS) or 0, score = number(m.score, -1e12), percent = number(m.percent, 0, 100),
    goal = text(m.goal, MAX_TEXT), at = at,
  }
  return true
end

local function onRound(d, sender, m, at)
  local game, name = text(m.game, MAX_ID), text(m.player, MAX_NAME)
  local net = number(m.net, -1e9, 1e9)
  if not (game and name and net) then return false end
  local key = "casino:" .. name .. "@" .. game
  local live = d.live[key]
  if not live or at - live.at > M.CASINO_LIVE_MS then
    live = { game = game, title = titled(game), players = { name }, from = at, rounds = 0, net = 0, casino = true }
  end
  live.rounds, live.net, live.at = live.rounds + 1, live.net + net, at
  live.ms = at - live.from + 60000
  d.live[key] = live
  d.want[tostring(sender)] = true
  return true
end

--- Any message heard, from computer `sender` on `protocol`. Returns true if the books changed.
function M.hear(d, sender, protocol, m, at)
  if type(m) ~= "table" then return false end
  if protocol == "arcade.v1" then
    if m.kind == "log" then return onLog(d, sender, m) end
    if m.kind == "play" then return onPlay(d, sender, m, at) end
  elseif protocol == "casino.v2" then
    if m.kind == "stats" then return onStats(d, sender, m) end
    if m.kind == "round" then return onRound(d, sender, m, at) end
  end
  return false
end

--- What to ask every computer for: the last session number the tracker has from each cabinet.
function M.ask(d)
  local after = {}
  for id, cab in pairs(d.cabinets) do after[id] = cab.seq end
  return { kind = "sync", after = after }
end

--- The computers with something new to say, and forget them: the tracker asks each of them.
function M.wanted(d)
  local out = {}
  for id in pairs(d.want) do out[#out + 1] = tonumber(id) end
  d.want = {}
  return out
end

--- Games gone quiet are over. Returns true if any were.
function M.expire(d, at)
  local changed = false
  for id, live in pairs(d.live) do
    if at - (live.at or 0) > (live.casino and M.CASINO_LIVE_MS or M.LIVE_STALE_MS) then
      d.live[id] = nil
      changed = true
    end
  end
  return changed
end

-- ---------------------------------------------------------------- the floor, added up

--- Every player's record, the cabinets' and the tables' together: { name = { ms, sessions, last, games = { id = row } } }.
local function everyone(d)
  local all = {}
  local function row(name)
    local p = all[name]
    if not p then
      p = { ms = 0, sessions = 0, last = 0, games = {} }
      all[name] = p
    end
    return p
  end
  for name, src in pairs(d.players) do
    local p = row(name)
    p.ms, p.sessions, p.last = p.ms + src.ms, p.sessions + src.sessions, math.max(p.last, src.last)
    for id, e in pairs(src.games) do
      local copy = {}
      for k, v in pairs(e) do copy[k] = v end
      copy.rounds, copy.wagered, copy.net = 0, 0, 0
      p.games[id] = copy
    end
  end
  for _, tbl in pairs(d.tables) do
    for name, src in pairs(tbl.players) do
      local p = row(name)
      p.ms, p.sessions, p.last = p.ms + src.ms, p.sessions + src.sessions, math.max(p.last, src.last)
      local e = p.games[tbl.game] or { title = tbl.title, ms = 0, sessions = 0, wins = 0, losses = 0, rounds = 0, wagered = 0, net = 0 }
      e.ms, e.sessions, e.rounds = e.ms + src.ms, e.sessions + src.sessions, (e.rounds or 0) + src.rounds
      e.wagered, e.net = (e.wagered or 0) + src.wagered, (e.net or 0) + src.net
      e.last = math.max(e.last or 0, src.last)
      if src.best > (e.bestWin or 0) then e.bestWin = src.best end
      p.games[tbl.game] = e
    end
  end
  return all
end
M.everyone = everyone

--- Everyone playing now, most recently heard first.
function M.now(d)
  local out = {}
  for _, live in pairs(d.live) do out[#out + 1] = live end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

--- Every player, most time played first, with the game they play most.
function M.players(d)
  local out = {}
  for name, p in pairs(everyone(d)) do
    local top, topMs, count = nil, -1, 0
    for _, e in pairs(p.games) do
      count = count + 1
      if e.ms > topMs then top, topMs = e.title, e.ms end
    end
    out[#out + 1] = { name = name, ms = p.ms, sessions = p.sessions, last = p.last, top = top, count = count }
  end
  table.sort(out, function(a, b) return a.ms > b.ms or (a.ms == b.ms and a.name < b.name) end)
  return out
end

--- Every game, most time played first.
function M.games(d)
  local rows = {}
  local function row(id, title)
    local g = rows[id]
    if not g then
      g = { id = id, title = title, ms = 0, sessions = 0, rounds = 0, players = {}, last = 0 }
      rows[id] = g
    end
    return g
  end
  for id, src in pairs(d.games) do
    local g = row(id, src.title)
    g.ms, g.sessions, g.last = g.ms + src.ms, g.sessions + src.sessions, math.max(g.last, src.last)
    for name in pairs(src.players) do g.players[name] = true end
  end
  for _, tbl in pairs(d.tables) do
    local g = row(tbl.game, tbl.title)
    for name, p in pairs(tbl.players) do
      g.ms, g.sessions, g.rounds, g.last = g.ms + p.ms, g.sessions + p.sessions, g.rounds + p.rounds, math.max(g.last, p.last)
      g.players[name] = true
    end
  end
  local out = {}
  for _, g in pairs(rows) do
    local count = 0
    for _ in pairs(g.players) do count = count + 1 end
    g.players = count
    out[#out + 1] = g
  end
  table.sort(out, function(a, b) return a.ms > b.ms or (a.ms == b.ms and a.title < b.title) end)
  return out
end

--- One player's games, most time first.
function M.player(d, name)
  local p = everyone(d)[name]
  if not p then return nil end
  local out = {}
  for id, e in pairs(p.games) do
    e.id = id
    out[#out + 1] = e
  end
  table.sort(out, function(a, b) return a.ms > b.ms end)
  return { name = name, ms = p.ms, sessions = p.sessions, last = p.last, games = out }
end

--- "3h 20m", "45m", "<1m".
function M.duration(ms)
  local mins = math.floor((ms or 0) / 60000)
  if mins < 1 then return "<1m" end
  if mins < 60 then return mins .. "m" end
  return math.floor(mins / 60) .. "h " .. (mins % 60) .. "m"
end

--- "just now", "5m ago", "3h ago", "2d ago".
function M.ago(at, now)
  if not at or at == 0 then return "" end
  local mins = math.floor((now - at) / 60000)
  if mins < 2 then return "just now" end
  if mins < 60 then return mins .. "m ago" end
  local hours = math.floor(mins / 60)
  if hours < 48 then return hours .. "h ago" end
  return math.floor(hours / 24) .. "d ago"
end

return M
