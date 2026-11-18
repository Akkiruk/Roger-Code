-- roam_lantern.lua: Lantern Row. The roam tune on pling, xylophone chords, snappier drums, and the lead echoed on
-- bit three steps behind, like neon doubled in a puddle.
local S = require("music.score")
local R = require("music.roam_score")

return R.arrange({
  mood = "Lantern Row: neon, noodle steam, a crowd that never goes home",
  lead = "pling", keys = "xylophone", vols = { 0.6, 0.8, 0.85 },
  kit = { k = { "basedrum", 8, 1 }, s = { "snare", 16, 0.7 }, h = { "hat", 20, 0.6 } },
  drums = "k+h . h . | s+h . h k | . k h . | s+h . h h",
  fill = "k+h . h . | s+h . h k | s . k s' | s s' s s",
  extra = {
    { voice = { name = "echo", inst = "bit", vol = 0.6 }, line = S.delay(R.lead, 3) },
  },
})
