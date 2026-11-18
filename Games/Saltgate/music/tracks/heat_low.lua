-- heat_low.lua: the Patrol has seen you (heat 1-2). 150 BPM rock beat, eighth-note bass, guitar off-beats, the theme's
-- turn on flute at full tilt. Same bars as heat_high: heat going up or down changes mid-phrase.
local S = require("music.score")
local C = require("music.chase_score")

local BEAT = "k+h . h . | s+h . h . | k+h . k+h . | s+h . h ."
local FILL = "k+h . h . | s+h . h . | s . s . | s s' s s"

return {
  mood = "lights in the mirror: run, but you can still lose them",
  ticks = { 2 },
  loop = true,
  sync = "chase",
  voices = {
    { name = "lead", inst = "flute", vol = 0.7 },
    { name = "bass", inst = "bass", vol = 0.9 },
    { name = "keys", inst = "guitar", vol = 0.4 },
    { name = "drums", vol = 0.55, kit = { k = { "basedrum", 6, 1 }, s = { "snare", 13, 0.75 }, h = { "hat", 18, 0.7 } } },
  },
  patterns = {
    main = {
      lead = C.lead,
      bass = C.follow("C4 . C4 . C5 . C4 . C4 . C4 . Bb4 . C5 ."),
      keys = C.chords({ 2, 6, 10, 14 }),
      drums = S.rep(S.join(BEAT, BEAT, BEAT, FILL), 4),
    },
  },
  order = { "main" },
}
