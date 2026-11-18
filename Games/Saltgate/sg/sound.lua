-- sound.lua
-- Saltgate's music cues and sound effects on a speaker, if there is one. Every cue is an original little phrase of note
-- block notes (instrument, pitch 0-24, beat), played on a clock so the game never waits on it. No speaker, no sound.

local M = {}

-- { instrument, pitch, at (seconds from the start of the cue), volume }
local CUES = {
  -- the theme: a slow minor figure over a walking bass, like lights coming on over the water
  title = {
    { "bass", 6, 0.0 }, { "flute", 18, 0.0 }, { "flute", 21, 0.3 }, { "bass", 9, 0.6 }, { "flute", 22, 0.6 },
    { "flute", 21, 1.0 }, { "bass", 11, 1.2 }, { "flute", 18, 1.4 }, { "bass", 13, 1.8 }, { "flute", 16, 1.8 },
    { "flute", 13, 2.4 }, { "bass", 6, 2.4 }, { "chime", 18, 3.0, 0.6 },
  },
  start = { { "pling", 13, 0 }, { "pling", 17, 0.12 }, { "pling", 20, 0.24 }, { "bass", 8, 0.24 } },
  pass = {
    { "bell", 13, 0 }, { "bell", 17, 0.15 }, { "bell", 20, 0.3 }, { "bell", 25 - 1, 0.45 },
    { "bass", 8, 0.45 }, { "chime", 20, 0.75 }, { "bass", 13, 0.75 },
  },
  fail = { { "bass", 10, 0 }, { "bass", 9, 0.25 }, { "bass", 8, 0.5 }, { "didgeridoo", 3, 0.8 } },
  cash = { { "bell", 18, 0, 0.6 }, { "bell", 23, 0.08, 0.6 } },
  heat = { { "bit", 18, 0, 0.7 }, { "bit", 13, 0.15, 0.7 }, { "bit", 18, 0.3, 0.7 } },
  cool = { { "chime", 13, 0, 0.5 } },
  lost = { { "chime", 13, 0, 0.6 }, { "chime", 17, 0.15, 0.6 }, { "chime", 20, 0.3, 0.6 } },
  nabbed = { { "bit", 18, 0 }, { "bit", 13, 0.3 }, { "bit", 18, 0.6 }, { "bit", 13, 0.9 }, { "bass", 1, 1.2 } },
  ko = { { "bass", 6, 0 }, { "bass", 3, 0.3 }, { "bass", 1, 0.6 } },
  talk = { { "hat", 14, 0, 0.4 } },
  door = { { "snare", 5, 0, 0.5 } },
  horn = { { "didgeridoo", 10, 0 }, { "didgeridoo", 10, 0.12 } },
  crash = { { "basedrum", 2, 0 }, { "snare", 1, 0.02 } },
  thud = { { "basedrum", 6, 0, 0.7 } },
  spray = { { "hat", 20, 0 }, { "hat", 22, 0.1 }, { "hat", 24, 0.2 }, { "pling", 18, 0.4 } },
  alarm = { { "bit", 20, 0 }, { "bit", 15, 0.2 }, { "bit", 20, 0.4 }, { "bit", 15, 0.6 } },
}
M.CUES = CUES

--- maxPerUpdate: notes it may send at once (the speaker takes 8 a tick; the music keeps 6 of them when it plays).
function M.new(speaker, maxPerUpdate)
  return { speaker = speaker, queue = {}, clock = 0, sirenT = 0, sirenHigh = false, cap = maxPerUpdate or 7 }

end

function M.play(s, name)
  if not s.speaker then return end
  local cue = CUES[name]
  if not cue then return end
  for _, n in ipairs(cue) do
    s.queue[#s.queue + 1] = { at = s.clock + n[3], inst = n[1], pitch = n[2], vol = n[4] or 1 }
  end
end

--- Play what is due. siren: the Patrol is close behind (a two-note wail now and then).
function M.update(s, dt, siren)
  s.clock = s.clock + dt
  if not s.speaker then return end
  if siren then
    s.sirenT = s.sirenT - dt
    if s.sirenT <= 0 then
      s.sirenT = 0.45
      s.sirenHigh = not s.sirenHigh
      s.queue[#s.queue + 1] = { at = s.clock, inst = "bit", pitch = s.sirenHigh and 19 or 14, vol = 0.35 }
    end
  end
  -- the due notes, oldest first, at most cap of them; the rest wait for the next update (a second late at most)
  local played, i = 0, 1
  local playNote = s.speaker.playNote
  while i <= #s.queue and played < s.cap do
    local n = s.queue[i]
    if n.at <= s.clock then
      table.remove(s.queue, i)
      if s.clock - n.at < 1 and playNote then
        pcall(playNote, n.inst, n.vol, n.pitch)
        played = played + 1
      end
    else
      i = i + 1
    end
  end
  s.lastPlayed = played
end

return M
