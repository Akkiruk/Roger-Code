-- finale.lua: "Low Tide", the last job. Four bars of storm (pumping bass, iron xylophone, the drums building), then
-- the whole theme at full strength: flute doubled by bit, the walking bass in eighths, sixteenth hats. After the
-- bridge the tide goes out (four bars of harp, chimes and bass alone) and the theme comes back in. Loops from the
-- theme; the storm plays once.
local S = require("music.score")
local T = require("music.theme")

--- The theme's walking bass with each quarter struck again on the off-beat.
local function walking8(from, to)
  local toks = S.tokens(T.bars(T.bass, from, to))
  for i = 1, #toks - 2 do
    if S.pitch(toks[i]) and toks[i + 1] == "." and toks[i + 2] == "." then toks[i + 2] = toks[i] .. "'" end
  end
  return table.concat(toks, " ")
end

--- The upper note of each bar's chord, hammered on syncopated steps.
local function stabs(from, to)
  local list = {}
  for i = from, to do list[#list + 1] = string.match(T.chords[i][1], "%+(.+)$") end
  return S.comp(list, { { 0, "!" }, 3, { 6, "'" }, 11 })
end

local HEAVY = "k+h h' h k | s+h h' h k | k+h h' k+h h' | s+h h' h s'"
local FILL = "k+h . s s | s+h . s s | s s s s | s! s s s!"
local HALF = "k+h . h . | s+h . h . | k+h . h k | s+h . h h'"
local DRIP = "h' . . . | . . h' . | h' . . . | . . h' ."

return {
  mood = "the last job: everything Wren has, one run, the tide going out",
  ticks = { 3 },
  loop = true,
  loopFrom = 2,
  voices = {
    { name = "lead", inst = "flute", vol = 0.8 },
    { name = "bass", inst = "bass", vol = 0.9 },
    { name = "double", inst = "bit", vol = 0.8 },
    { name = "stab", inst = "iron_xylophone", vol = 0.4 },
    { name = "keys", inst = "harp", vol = 0.42 },
    { name = "chime", inst = "chime", vol = 0.9 },
    { name = "drums", vol = 0.6, kit = { k = { "basedrum", 5, 1 }, s = { "snare", 13, 0.75 }, h = { "hat", 19, 0.7 } } },
  },
  patterns = {
    storm = {
      bass = S.join(S.rep("C4 C4' C5 C4' C4 C4' C5 C4' C4 C4' C5 C4' Db4 C4' Db5 C4'", 3),
        "G3 G3' G4 G3' G3 G3' G4 G3' B3 B3' B4 B3' D4 D4' F4 D4'"),
      stab = S.join(S.rep("C5 . . C5 | . . C5 . | . . . . | Db5 . . .", 3), "B4 . . B4 | . . D5 . | F5 . D5 . | B4 . G4 ."),
      drums = S.join(S.rep("k+h . h k | h . k h | k+h . h k | s+h . h h", 3), "s . s s | s . s s | s s s s | s! s! s! s!"),
    },
    a = {
      lead = T.bars(T.lead, 1, 4),
      double = T.bars(T.lead, 1, 4),
      bass = walking8(1, 4),
      stab = stabs(1, 4),
      drums = S.join(HEAVY, HEAVY, HEAVY, FILL),
    },
    a2 = {
      lead = T.bars(T.lead, 5, 8),
      double = T.bars(T.lead, 5, 8),
      bass = walking8(5, 8),
      stab = stabs(5, 8),
      drums = S.join(HEAVY, HEAVY, HEAVY, FILL),
    },
    b = {
      lead = T.bars(T.lead, 9, 12),
      bass = T.bars(T.bass, 9, 12),
      keys = T.stabs(9, 12, 6, 14),
      drums = S.join(HALF, HALF, HALF, "k+h . h . | s+h . h . | s . s . | s s' s s"),
    },
    tide = {
      keys = S.join("C4 . Eb4 . | E4 . . Eb4 | . C4 . . | Bb3 . . .", "G3 . . . | . . . . | . . . . | . . . .",
        "C4 . Eb4 . | F4 . . Eb4 | . C4 . . | Ab3 . . .", "G3 . . B3 | . . D4 . | . F4 . . | Eb4 . D4 ."),
      bass = S.join("C4 . . . | . . . . | . . . . | . . . .", "C4 . . . | . . . . | G3 . . . | . . . .",
        "Ab3 . . . | . . . . | . . . . | . . . .", "G3 . . . | . . . . | . . . . | . . . ."),
      chime = S.join(". . . . | . . . . | G4 . . . | . . . .", ". . . . | Eb4 . . . | . . . . | C5 . . .",
        ". . . . | . . . . | Ab4 . . . | . . . .", "D5 . . . | . . . . | . . . . | . . . ."),
      drums = S.join(DRIP, DRIP, DRIP, "h . h . | s' . s' . | s . s . | s s s s"),
    },
    c = {
      lead = T.bars(T.lead, 13, 16),
      double = T.bars(T.lead, 13, 16),
      bass = walking8(13, 16),
      stab = stabs(13, 16),
      drums = S.join(HEAVY, HEAVY, HEAVY, FILL),
    },
  },
  order = { "storm", "a", "a2", "b", "tide", "c" },
}
