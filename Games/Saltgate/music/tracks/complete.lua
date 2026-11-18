-- complete.lua: job done. The theme's turn climbs to G and lands on C major, with bells; then the music that was
-- playing comes back.
local S = require("music.score")

return {
  mood = "job done: cash in the glovebox",
  ticks = { 3 },
  trim = true,
  resume = true,
  voices = {
    { name = "lead", inst = "flute", vol = 0.75 },
    { name = "bass", inst = "bass", vol = 0.9 },
    { name = "keys", inst = "harp", vol = 0.45 },
    { name = "bell", inst = "bell", vol = 0.9 },
    { name = "drums", vol = 0.6, kit = { k = { "basedrum", 6, 1 }, s = { "snare", 13, 0.7 }, h = { "hat", 18, 0.7 } } },
  },
  patterns = {
    main = {
      lead = S.join("C5 . Eb5 . | E5 . . . | G4 . C5 . | E5 . . .", "D5 . E5! . | . . . . | . . . . | . . . ."),
      bass = S.join("C4 . . . | Eb4 . . . | E4 . . . | G4 . . .", "C4 . . . | . . . . | . . . . | . . . ."),
      keys = S.join(S.rest(1), "E4+G4 . . . | . . . . | . . . . | . . . ."),
      bell = S.join(S.rest(1), ". . C4 . | E4 . G4 . | C5 . . . | . . . ."),
      drums = S.join(". . . . | . . . . | . . . . | s . s s", "k+h . . . | . . . . | . . . . | . . . ."),
    },
  },
  order = { "main" },
}
