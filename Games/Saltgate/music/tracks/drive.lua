-- drive.lua: behind the wheel. 120 BPM on a light shuffle, C minor: an octave-jumping bass riff that follows the
-- chords, guitar on the off-beats, and the theme's turn on pling, chopped up and pushed ahead of the beat.
--   1 Cm  2 Cm  3 Ab  4 Bb | 5 Cm  6 Cm  7 Ab  8 G | 9 Fm  10 Fm  11 Cm  12 Cm | 13 Ab  14 Bb  15 Cm  16 G7
local S = require("music.score")

local RIFF = "C4 . C4' C5 | . . C4 . | Eb4 . . F4 | . G4 . Bb4'"
local TURN = "G3 . G3' G4 | . . G3 . | B3 . D4 . | F4 . D4 ."
local ROOTS = { 0, 0, -4, -2, 0, 0, -4, -5, 5, 5, 0, 0, -4, -2, 0, -5 }
local CHORD = { [0] = "Eb4+G4", [-4] = "C4+Eb4", [-2] = "D4+F4", [-5] = "B3+D4", [5] = "Ab3+C4" }

local bass, chords = {}, {}
for i, r in ipairs(ROOTS) do
  bass[i] = (i == 8 or i == 16) and TURN or S.transpose(RIFF, r)
  chords[i] = CHORD[r]
end
chords[16] = "B3+F4"

local BEAT = "k+h . h k | s+h . h . | k+h . h k' | s+h . h s'"
local FILL = "k+h . h k | s+h . s' . | s . s s' | s s s s"

return {
  mood = "foot down along the harbour road, streetlights strobing past",
  ticks = { 3, 2 },
  loop = true,
  voices = {
    { name = "lead", inst = "pling", vol = 0.6 },
    { name = "bass", inst = "bass", vol = 0.9 },
    { name = "keys", inst = "guitar", vol = 0.45 },
    { name = "drums", vol = 0.55, kit = { k = { "basedrum", 6, 1 }, s = { "snare", 13, 0.75 }, h = { "hat", 18, 0.7 } } },
  },
  patterns = {
    main = {
      lead = S.join(
        "C5 . Eb5 . | E5 . . . | . . Eb5 . | C5 . . .",
        ". . . . | . . . . | G4 . Bb4 . | C5 . . .",
        "C5 . Eb5 . | F5 . . . | . . Eb5 . | C5 . Ab4 .",
        ". . . . | Bb4 . D5 . | F5 . . . | D5 . . .",
        "C5 . Eb5 . | E5 . . . | . . Eb5 . | C5 . . .",
        ". . G4 . | Bb4 . C5 . | Eb5 . . . | C5 . . .",
        "Eb5 . C5 . | Ab4 . . . | C5 . Eb5 . | F5 . . .",
        "D5 . . . | B4 . . . | G4 . . . | . . . .",
        "Ab4 . . Ab4 | . C5 . . | F5 . . . | Eb5 . C5 .",
        ". . . . | Ab4 . C5 . | Eb5 . F5 . | . . Eb5 .",
        "C5 . . . | . . . . | Eb5 . E5 . | . . Eb5 .",
        "C5 . . . | Bb4 . . . | G4 . . . | . . . .",
        "Eb5 . . . | F5 . Eb5 . | C5 . . . | Ab4 . . .",
        "D5 . . . | F5 . . . | F#5 . . . | F5 . D5 .",
        "Eb5 . . . | E5 . Eb5 . | C5 . . . | . . . .",
        "B4 . . . | D5 . . . | F5 . . . | D5 . B4 ."
      ),
      bass = table.concat(bass, " | "),
      keys = S.comp(chords, { 2, { 6, "'" }, 10, { 13, "'" } }),
      drums = S.rep(S.join(S.rep(BEAT, 7), FILL), 2),
    },
  },
  order = { "main" },
}
