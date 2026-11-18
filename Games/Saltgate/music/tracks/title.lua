-- title.lua: the main theme, as the title screen plays it. 100 BPM, C minor. Two bars of harbour lights, then the
-- tune: bare the first time round, the drums come in at bar 5, the bridge lifts to Eb, and back home.
local S = require("music.score")
local T = require("music.theme")

local GROOVE = "k+h . h . | s+h . h k | h . k+h . | s+h . h h'"
local LIGHT = "k+h . h . | s+h . h . | k+h . h . | s+h . h h'"

return {
  mood = "the theme: neon on dark water, a getaway car idling",
  ticks = { 3 },
  loop = true,
  loopFrom = 2,
  voices = {
    { name = "lead", inst = "flute", vol = 0.75 },
    { name = "bass", inst = "bass", vol = 0.9 },
    { name = "keys", inst = "harp", vol = 0.4 },
    { name = "chime", inst = "chime", vol = 0.9 },
    { name = "drums", vol = 0.55, kit = { k = { "basedrum", 6, 1 }, s = { "snare", 12, 0.7 }, h = { "hat", 16, 0.7 } } },
  },
  patterns = {
    intro = {
      lead = S.join(S.rest(1), ". . . . | . . . . | G4 . . . | Bb4 . B4 ."),
      bass = "C4 . . . | . . . . | . . . . | . . . . | G3 . . . | . . . . | . . . . | . . . .",
      keys = "C4 . Eb4 . | G4 . C5 . | . . G4 . | Eb4 . . . | B3 . D4 . | F4 . G4 . | . . . . | . . . .",
      chime = S.join("C5 . . . | . . . . | . . . . | . . . .", S.rest(1)),
    },
    a = {
      lead = T.bars(T.lead, 1, 4),
      bass = T.bars(T.bass, 1, 4),
      keys = T.stabs(1, 4, 6, 14),
      chime = S.join(S.rest(1), ". . . . | C5 . . . | . . . . | . . . .", S.rest(2)),
    },
    a2 = {
      lead = T.bars(T.lead, 5, 8),
      bass = T.bars(T.bass, 5, 8),
      keys = T.stabs(5, 8, 6, 14),
      chime = S.join(S.rest(1), ". . . . | C5 . . . | . . . . | . . . .", S.rest(2)),
      drums = S.join(S.rep(GROOVE, 3), "k+h . h . | s+h . h k | h . k+h . | s s' s s'"),
    },
    b = {
      lead = T.bars(T.lead, 9, 12),
      bass = T.bars(T.bass, 9, 12),
      keys = T.stabs(9, 12, 6, 14),
      chime = S.join("Ab4 . . . | . . . . | . . . . | . . . .", S.rest(1), "G4 . . . | . . . . | . . . . | . . . .", S.rest(1)),
      drums = S.join(S.rep(LIGHT, 3), "k+h . h . | s+h . h . | k+h . s' . | s . s s'"),
    },
    c = {
      lead = T.bars(T.lead, 13, 16),
      bass = T.bars(T.bass, 13, 16),
      keys = T.stabs(13, 16, 6, 14),
      chime = S.join(S.rest(3), "C5 . . . | . . . . | . . . . | . . . ."),
      drums = S.join(S.rep(GROOVE, 3), "k+h . h . | s+h . h k | . . s' s | s s' s s"),
    },
  },
  order = { "intro", "a", "a2", "b", "c" },
}
