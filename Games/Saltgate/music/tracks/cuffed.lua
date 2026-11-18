-- cuffed.lua: the Patrol has you. A siren figure on bit, the flute sliding down a half step at a time, and a cell
-- door: a cow bell and a kick on a tritone.
local S = require("music.score")

return {
  mood = "busted: the door shuts",
  ticks = { 3 },
  trim = true,
  voices = {
    { name = "lead", inst = "flute", vol = 0.7 },
    { name = "bass", inst = "bass", vol = 0.9 },
    { name = "siren", inst = "bit", vol = 0.9 },
    { name = "keys", inst = "harp", vol = 0.45 },
    { name = "drums", vol = 0.7, kit = { k = { "basedrum", 3, 1 }, c = { "cow_bell", 2, 0.6 }, s = { "snare", 8, 0.6 } } },
  },
  patterns = {
    main = {
      siren = S.join("G4 . . . | D5 . . . | G4 . . . | D5 . . .", S.rest(1)),
      lead = S.join(". . . . | . . . . | Eb5 . D5 . | Db5 . . .", "C5 . . . | . . . . | . . . . | . . . ."),
      bass = S.join("Eb4 . . . | . . . . | D4 . . . | Db4 . . .", "C4 . . . | . . . . | . . . . | . . . ."),
      keys = S.join(S.rest(1), "F#3+C4 . . . | . . . . | . . . . | . . . ."),
      drums = S.join(". . . . | . . . . | . . . . | . . s' s", "k+c . . . | s' . . . | . . . . | . . . ."),
    },
  },
  order = { "main" },
}
