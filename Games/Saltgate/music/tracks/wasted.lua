-- wasted.lua: lights out. The theme's turn once more, then it sinks: Fm, G, and a low C with the didgeridoo under it.
local S = require("music.score")

local LAST = "C4 . . . | . . . . | . . . . | . . . . | . . . . | . . . . | . . . . | . . . ."

return {
  mood = "lights out: the tune runs down",
  ticks = { 3 },
  trim = true,
  voices = {
    { name = "lead", inst = "flute", vol = 0.75 },
    { name = "bass", inst = "bass", vol = 0.9 },
    { name = "keys", inst = "harp", vol = 0.45 },
    { name = "drone", inst = "didgeridoo", vol = 0.4 },
    { name = "chime", inst = "chime", vol = 0.8 },
    { name = "drums", vol = 0.7, kit = { k = { "basedrum", 2, 1 } } },
  },
  patterns = {
    main = {
      lead = S.join("C5 . Eb5 . | E5 . . Eb5 | . C5 . . | Bb4 . . .", "Ab4 . . . | . . G4 . | . . F4 . | D4 . . .",
        ". . . . | Eb4 . . . | . . . . | C4 . . . | . . . . | . . . . | . . . . | . . . ."),
      bass = S.join("C4 . . . | . . . . | Ab3 . . . | . . . .", "F4 . . . | . . . . | G3 . . . | . . . .", LAST),
      keys = S.join("Eb4+G4 . . . | . . . . | C4+Eb4 . . . | . . . .", "Ab3+C4 . . . | . . . . | B3+D4 . . . | . . . .",
        "Eb4+G4 . . . | . . . . | . . . . | . . . . | . . . . | . . . . | . . . . | . . . ."),
      drone = S.join(S.rest(2), LAST),
      chime = S.join(S.rest(2), ". . . . | . . . . | F#4 . . . | . . . . | . . . . | . . . . | . . . . | . . . ."),
      drums = S.join(S.rest(2), "k . . . | . . . . | . . . . | . . . . | . . . . | . . . . | . . . . | . . . ."),
    },
  },
  order = { "main" },
}
