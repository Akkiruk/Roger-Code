-- arcade_track.lua
-- Every game played on this cabinet, kept on its own disk: who, what, for how long, and how it went. This record is the
-- cabinet's own, whether or not anything is listening. A tracker computer (Games/Tracker) collects it: it asks for every
-- session after the last one it has, and the cabinet answers from the file, so a tracker that was off, or put in months
-- later, still gets everything. Each finished session has a number, counting up, so nothing is counted twice.
--
-- While a game runs the cabinet also says so (start, a beat each minute, end) for the tracker's NOW page, and the session
-- in progress is written down each minute, so a reboot loses at most a minute of it. With no modem nothing is sent, and the
-- record is kept all the same.

local net = require("lib.arcade.net")

local M = {}

M.BEAT_MS = 60000
M.KEPT = 1000          -- sessions kept on disk; a tracker that's been away longer than this many games misses the oldest
M.SEND_AT_ONCE = 40    -- sessions in one answer; the tracker asks again for the rest

local LOG_FILE = "arcade_play.dat"
local LIVE_FILE = "arcade_play_live.dat"

local live = {}
local count = 0
local book = nil

local function now() return os.epoch("utc") end

local function readFile(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local text = h.readAll()
  h.close()
  local ok, value = pcall(textutils.unserialise, text or "")
  return ok and value or nil
end

--- Write beside and swap, so a reboot mid-write leaves the last good copy.
local function writeFile(path, value)
  local ok, text = pcall(textutils.serialise, value, { compact = true })
  if not ok then return false end
  local tmp = path .. ".tmp"
  local h = fs.open(tmp, "w")
  if not h then return false end
  h.write(text)
  h.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
  return true
end

local function copyOf(s, info)
  local out = { id = s.id, game = s.game, title = s.title, players = s.players, from = s.from, ms = now() - s.from }
  for k, v in pairs(info or s.info or {}) do
    if out[k] == nil then out[k] = v end
  end
  return out
end

local function saveLive()
  local list = {}
  for _, s in pairs(live) do list[#list + 1] = copyOf(s) end
  if #list == 0 then
    if fs.exists(LIVE_FILE) then fs.delete(LIVE_FILE) end
  else
    writeFile(LIVE_FILE, list)
  end
end

--- The cabinet's book: { seq, sessions }. A session cut off by a reboot is closed here, as long as it was last written.
local function load()
  if book then return book end
  local value = readFile(LOG_FILE)
  if type(value) == "table" and type(value.sessions) == "table" and type(value.seq) == "number" then
    book = value
  else
    book = { seq = 0, sessions = {} }
  end
  local cut = readFile(LIVE_FILE)
  if type(cut) == "table" and #cut > 0 then
    for _, s in ipairs(cut) do
      book.seq = book.seq + 1
      s.seq, s.at, s.cut = book.seq, (s.from or now()) + (s.ms or 0), true
      book.sessions[#book.sessions + 1] = s
    end
    while #book.sessions > M.KEPT do table.remove(book.sessions, 1) end
    writeFile(LOG_FILE, book)
    fs.delete(LIVE_FILE)
  end
  return book
end
M.load = load

local function send(phase, s, info)
  local msg = copyOf(s, info)
  msg.phase = phase
  net.play(msg)
end

--- A game has started. players: the names in it. info: anything worth showing (score, level, percent, goal).
function M.start(game, title, players, info)
  load()
  count = count + 1
  local s = { id = os.getComputerID() .. ":" .. now() .. ":" .. count, game = game, title = title, players = players, from = now(), sent = now(), info = info }
  live[s.id] = s
  send("start", s, info)
  saveLive()
  return s
end

--- Still going: at most once a minute however often it's called, it's said and written down.
function M.beat(s, info)
  if not (s and live[s.id]) or now() - s.sent < M.BEAT_MS then return end
  s.sent = now()
  if info then s.info = info end
  send("beat", s, info)
  saveLive()
end

--- It's over: into the cabinet's book. Safe to call twice.
function M.stop(s, info)
  if not (s and live[s.id]) then return end
  live[s.id] = nil
  local b = load()
  b.seq = b.seq + 1
  local done = copyOf(s, info)
  done.seq, done.at = b.seq, now()
  b.sessions[#b.sessions + 1] = done
  while #b.sessions > M.KEPT do table.remove(b.sessions, 1) end
  writeFile(LOG_FILE, b)
  saveLive()
  send("end", s, info)
end

--- The sessions after number `after`, oldest first, at most SEND_AT_ONCE of them, and whether there are more.
function M.since(after)
  local b = load()
  local out = {}
  for _, s in ipairs(b.sessions) do
    if s.seq > (after or 0) then
      if #out >= M.SEND_AT_ONCE then return out, true end
      out[#out + 1] = s
    end
  end
  return out, false
end

--- A message heard by the cabinet: a tracker asking for what it hasn't got gets an answer from the book.
function M.hear(sender, msg, protocol)
  if protocol ~= net.PROTOCOL or type(msg) ~= "table" or msg.kind ~= "sync" then return false end
  local after = type(msg.after) == "table" and tonumber(msg.after[tostring(os.getComputerID())]) or 0
  local sessions, more = M.since(after)
  net.reply(sender, {
    kind = "log", computer = os.getComputerID(), seq = load().seq, sessions = sessions, more = more,
  })
  return true
end

-- for tests: forget what's in memory, so the files are read again
function M.reset() book, live, count = nil, {}, 0 end

return M
