-- job.lua: on a job. 100 BPM, C minor leaning on Db: a bass that will not stop ticking, a hat like a clock, the
-- theme's turn slowed down on flute, and pling trembling a half step apart while it goes wrong.
--   1-4 C   5-6 Cm  7 Db/C  8 Cm | 9-10 Cm  11 Ab  12 G | 13-14 Cm  15 Db  16 G
local S = require("music.score")

local PULSE = "C4 . C4' . C4 . C4' . C4 . C4' . Db4 . C4' ."
local ROOTS = { 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, -4, -5, 0, 0, 1, -5 }
local bass = {}
for i, r in ipairs(ROOTS) do bass[i] = S.transpose(PULSE, r) end

local CLOCK = "h . h' . h . h' . h . h' . h . h' h'"
local KICK = "k+h . h' . h . h' . k+h . h' . h . h' h'"

return {
  mood = "a job in progress: watching mirrors, counting seconds",
  ticks = { 3 },
  loop = true,
  voices = {
    { name = "lead", inst = "flute", vol = 0.65 },
    { name = "bass", inst = "bass", vol = 0.8 },
    { name = "nerve", inst = "pling", vol = 0.25 },
    { name = "chime", inst = "chime", vol = 0.9 },
    { name = "drums", vol = 0.5, kit = { k = { "basedrum", 4, 1 }, s = { "snare", 12, 0.6 }, h = { "hat", 20, 0.6 } } },
  },
  patterns = {
    main = {
      lead = S.join(
        S.rest(1),
        "G4 . . . | . . . . | Ab4 . . . | G4 . . .",
        S.rest(1),
        "G4 . . . | . . . . | Ab4 . . . | B4 . . .",
        "C5 . . Eb5 | . . E5 . | . . . . | Eb5 . . .",
        "C5 . . . | . . . . | . . . . | . . . .",
        "Db5 . . F5 | . . E5 . | . . . . | Db5 . . .",
        "C5 . . . | . . . . | Bb4 . . . | G4 . . .",
        S.rest(1),
        "Ab4 . . . | . . G4 . | . . . . | . . . .",
        "Ab4 . . C5 | . . Eb5 . | . . . . | . . . .",
        "D5 . . . | . . B4 . | . . . . | G4 . . .",
        "C5 . . Eb5 | . . E5 . | . . . . | Eb5 . . .",
        "C5 . . . | Bb4 . G4 . | . . . . | . . . .",
        "Db5 . . . | C5 . . . | Bb4 . . . | Ab4 . . .",
        "G4 . . . | . . . . | B4 . . . | D5 . . ."
      ),
      bass = table.concat(bass, " | "),
      nerve = S.join(S.rest(8),
        S.rep("C5 . Db5 . C5 . Db5 . C5 . Db5 . C5 . Db5 .", 2),
        "Eb5 . E5 . Eb5 . E5 . Eb5 . E5 . Eb5 . E5 .",
        "D5 . Eb5 . D5 . Eb5 . D5 . Eb5 . D5 . Eb5 .",
        S.rest(4)),
      chime = S.join("C5 . . . | . . . . | . . . . | . . . .", S.rest(7),
        "Ab4 . . . | . . . . | . . . . | . . . .", S.rest(7)),
      drums = S.join(S.rep(CLOCK, 4), S.rep(KICK, 8),
        KICK, KICK, KICK, "k+h . h' . h . h' . s' . s' . s . s s"),
    },
  },
  order = { "main" },
}
