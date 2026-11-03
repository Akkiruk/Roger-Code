-- arcade_track.lua
-- Who is playing what, for a tracker computer (Games/Tracker) on the same network. A game says when it starts, every
-- minute while it goes on, and when it stops; each message carries the time played so far, so a tracker that misses one
-- loses nothing. Optional, like everything on net.lua: with no modem nothing is sent and nothing waits.

local net = require("lib.arcade.net")

local M = {}

M.BEAT_MS = 60000

local live = {}
local count = 0

local function now() return os.epoch("utc") end

local function send(phase, s, info)
  local msg = { phase = phase, id = s.id, game = s.game, title = s.title, players = s.players, ms = now() - s.from }
  for k, v in pairs(info or {}) do
    if msg[k] == nil then msg[k] = v end
  end
  net.play(msg)
end

--- A game has started. players: the names in it. info: anything worth showing (score, level, percent, goal).
function M.start(game, title, players, info)
  count = count + 1
  local s = { id = os.getComputerID() .. ":" .. now() .. ":" .. count, game = game, title = title, players = players, from = now(), sent = now() }
  live[s.id] = s
  send("start", s, info)
  return s
end

--- Still going: sent at most once a minute however often it's called.
function M.beat(s, info)
  if not (s and live[s.id]) or now() - s.sent < M.BEAT_MS then return end
  s.sent = now()
  send("beat", s, info)
end

--- It's over. Safe to call twice.
function M.stop(s, info)
  if not (s and live[s.id]) then return end
  live[s.id] = nil
  send("end", s, info)
end

return M
