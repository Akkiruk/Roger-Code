-- tracker/rules.lua
-- The tracker's books, as plain data: who has played what, for how long, and how it went. Messages come from Arcade
-- cabinets (arcade.v1 "play", sent by lib/arcade/track.lua) and casino tables (casino.v2 "round", which they already send
-- to the hub). Nothing here touches the screen, the disk or the network, so it tests on its own.
--
-- Every play message carries the time played so far, so only the growth since the last one is counted: a missed message
-- costs nothing, and a tracker started halfway through a game still counts the whole of it. A casino round carries no time,
-- so a player's rounds at one game less than CASINO_GAP_MS apart are one sitting, timed from round to round.

local M = {}

M.LIVE_STALE_MS = 3 * 60000   -- a game not heard from for this long has stopped, whatever it said
M.CASINO_GAP_MS = 5 * 60000   -- rounds closer than this are one sitting
M.CASINO_ROUND_MS = 60000     -- a sitting's first round counts as this long
M.RECENT = 80                 -- finished games kept for the RECENT page
M.MAX_MS = 6 * 3600000        -- no one message can honestly add more than this

local MAX_NAME, MAX_ID, MAX_TEXT = 32, 64, 60
local NOT_PEOPLE = { Computer = true, ["?"] = true, [""] = true }

local function text(v, n) return type(v) == "string" and v ~= "" and v:gsub("%c", ""):sub(1, n) or nil end
local function number(v, hi) return type(v) == "number" and v == v and v >= -1e12 and v <= (hi or 1e12) and v or nil end

function M.new()
  return { v = 1, players = {}, games = {}, live = {}, recent = {}, sittings = {} }
end

--- A game's own title from its id, for casino games that send none: "three_card_poker" becomes "Three Card Poker".
local function titled(id)
  return (id:gsub("[_%-]", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

local function gameRow(d, id, title)
  local g = d.games[id]
  if not g then
    g = { title = title or titled(id), ms = 0, sessions = 0, rounds = 0, players = {}, last = 0 }
    d.games[id] = g
  end
  if title then g.title = title end
  return g
end

local function playerRow(d, name, id, title)
  local p = d.players[name]
  if not p then
    p = { ms = 0, sessions = 0, games = {}, last = 0 }
    d.players[name] = p
  end
  local e = p.games[id]
  if not e then
    e = { title = title or titled(id), ms = 0, sessions = 0, rounds = 0, wagered = 0, net = 0, wins = 0, losses = 0 }
    p.games[id] = e
  end
  if title then e.title = title end
  return p, e
end

local function remember(d, item)
  table.insert(d.recent, 1, item)
  while #d.recent > M.RECENT do table.remove(d.recent) end
end

local function people(list)
  local out = {}
  for _, name in ipairs(list or {}) do
    if not NOT_PEOPLE[name] then out[#out + 1] = name end
  end
  return out
end

--- An Arcade cabinet's play message. Returns true if the books changed.
local function onPlay(d, m, at)
  local phase, id, game = m.phase, text(m.id, MAX_ID), text(m.game, MAX_ID)
  if not (id and game and (phase == "start" or phase == "beat" or phase == "end")) then return false end
  if type(m.players) ~= "table" or #m.players < 1 or #m.players > 8 then return false end
  local players = {}
  for i, name in ipairs(m.players) do players[i] = text(name, MAX_NAME) or "?" end
  local title = text(m.title, MAX_TEXT)
  local ms = number(m.ms, 1e10) or 0
  local live = d.live[id]
  local fresh = not live
  if fresh then
    live = { game = game, title = title, players = players, cabinet = text(m.cabinet, MAX_TEXT), from = at - ms, counted = 0 }
    d.live[id] = live
  end
  local grew = math.max(0, math.min(M.MAX_MS, ms - live.counted))
  live.counted, live.at = math.max(live.counted, ms), at
  local g = gameRow(d, game, title)
  g.ms, g.last = g.ms + grew, at
  if fresh then g.sessions = g.sessions + 1 end
  for _, name in ipairs(people(players)) do
    local p, e = playerRow(d, name, game, title)
    g.players[name] = true
    p.ms, e.ms, p.last, e.last = p.ms + grew, e.ms + grew, at, at
    if fresh then p.sessions, e.sessions = p.sessions + 1, e.sessions + 1 end
    local score, level, percent = number(m.score), number(m.level, 1e6), number(m.percent, 100)
    if score and (not e.best or score > e.best) then e.best = score end
    if level and (not e.level or level > e.level) then e.level = level end
    if percent then e.percent = math.max(e.percent or 0, percent) end
    if text(m.goal, MAX_TEXT) then e.goal = text(m.goal, MAX_TEXT) end
  end
  live.score, live.level, live.percent, live.goal = number(m.score), number(m.level, 1e6), number(m.percent, 100), text(m.goal, MAX_TEXT)
  if phase == "end" then
    d.live[id] = nil
    local winner = text(m.winner, MAX_NAME)
    if winner and winner ~= "draw" and #players > 1 then
      for _, name in ipairs(people(players)) do
        local _, e = playerRow(d, name, game, title)
        if name == winner then e.wins = e.wins + 1 else e.losses = e.losses + 1 end
      end
    end
    local note = winner and (winner == "draw" and "a draw" or (winner .. " won")) or (m.abandoned and "stopped" or nil)
    if not note and live.percent then note = live.percent .. "% of the story" end
    if not note and live.score then note = "score " .. live.score end
    remember(d, { at = at, title = title or g.title, players = players, ms = live.counted, note = note, cabinet = live.cabinet })
  end
  return true
end

--- A casino table's round. Returns true if the books changed.
local function onRound(d, m, at)
  local game, name = text(m.game, MAX_ID), text(m.player, MAX_NAME)
  local wagered, net = number(m.wagered, 1e9), number(m.net)
  if not (game and name and wagered and net) or net > 1e9 or net < -1e9 then return false end
  local key = name .. "@" .. game
  local last = d.sittings[key]
  local fresh = not last or at - last > M.CASINO_GAP_MS
  local grew = fresh and M.CASINO_ROUND_MS or math.max(0, at - last)
  d.sittings[key] = at
  local g = gameRow(d, game)
  local p, e = playerRow(d, name, game)
  g.ms, g.rounds, g.last, g.players[name] = g.ms + grew, g.rounds + 1, at, true
  p.ms, e.ms, p.last, e.last = p.ms + grew, e.ms + grew, at, at
  e.rounds, e.wagered, e.net = e.rounds + 1, e.wagered + wagered, e.net + net
  if fresh then
    g.sessions, p.sessions, e.sessions = g.sessions + 1, p.sessions + 1, e.sessions + 1
  end
  local liveId = "casino:" .. key
  local live = d.live[liveId] or { game = game, title = g.title, players = { name }, from = at, counted = 0, casino = true }
  live.at, live.rounds, live.net = at, (live.rounds or 0) + 1, (live.net or 0) + net
  live.counted = at - live.from + M.CASINO_ROUND_MS
  d.live[liveId] = live
  return true
end

--- Any message heard. protocol says who sent it.
function M.hear(d, protocol, m, at)
  if type(m) ~= "table" then return false end
  if protocol == "arcade.v1" and m.kind == "play" then return onPlay(d, m, at) end
  if protocol == "casino.v2" and m.kind == "round" then return onRound(d, m, at) end
  return false
end

--- Games gone quiet are over: they go to RECENT. Returns true if any did.
function M.expire(d, at)
  local changed = false
  for id, live in pairs(d.live) do
    if at - (live.at or 0) > M.LIVE_STALE_MS then
      d.live[id] = nil
      local note = live.casino and (live.rounds .. " rounds, " .. (live.net >= 0 and "+" or "") .. live.net .. " tokens") or "went quiet"
      remember(d, { at = live.at, title = live.title or gameRow(d, live.game).title, players = live.players, ms = live.counted, note = note, cabinet = live.cabinet })
      changed = true
    end
  end
  for key, last in pairs(d.sittings) do
    if at - last > M.CASINO_GAP_MS then d.sittings[key] = nil end
  end
  return changed
end

-- ---------------------------------------------------------------- what the pages show

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
  for name, p in pairs(d.players) do
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
  local out = {}
  for id, g in pairs(d.games) do
    local count = 0
    for _ in pairs(g.players) do count = count + 1 end
    out[#out + 1] = { id = id, title = g.title, ms = g.ms, sessions = g.sessions, rounds = g.rounds, players = count, last = g.last }
  end
  table.sort(out, function(a, b) return a.ms > b.ms or (a.ms == b.ms and a.title < b.title) end)
  return out
end

--- One player's games, most time first.
function M.player(d, name)
  local p = d.players[name]
  if not p then return nil end
  local out = {}
  for id, e in pairs(p.games) do
    local row = { id = id }
    for k, v in pairs(e) do row[k] = v end
    out[#out + 1] = row
  end
  table.sort(out, function(a, b) return a.ms > b.ms end)
  return { name = name, ms = p.ms, sessions = p.sessions, last = p.last, games = out }
end

--- "3h 20m", "45m", "under a minute".
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
