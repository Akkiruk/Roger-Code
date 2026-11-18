-- chase_score.lua
-- The Harbor Patrol chase, shared by heat_low and heat_high so a rise in heat changes the music in the same bar of
-- the phrase (sync group "chase"). 150 BPM, straight 16ths, C minor, sixteen bars of 1.6 seconds.
-- The theme's turn played fast: C-Eb-E-Eb-C-Bb-G.
--   1 Cm  2 Cm  3 Ab  4 Bb | 5 Cm  6 Cm  7 Ab  8 G7 | 9 Fm  10 Fm  11 Ab  12 Bb | 13 Cm  14 Ab  15 G7  16 G7

local S = require("music.score")

local M = {}

M.roots = { 0, 0, -4, -2, 0, 0, -4, -5, 5, 5, -4, -2, 0, -4, -5, -5 }
M.chordOf = { [0] = "Eb4+G4", [-4] = "C4+Eb4", [-2] = "D4+F4", [-5] = "B3+F4", [5] = "Ab3+C4" }
M.topOf = { [0] = "C5", [-4] = "Ab4", [-2] = "Bb4", [-5] = "G4", [5] = "F4" }

M.lead = S.join(
  "C5 . Eb5 E5 | . Eb5 C5 . | Bb4 . G4 . | . . . .",
  ". . . . | . . . . | G4 . Bb4 . | C5 . Eb5 .",
  "C5 . Eb5 F5 | . Eb5 C5 . | Ab4 . . . | . . . .",
  ". . . . | D5 . F5 . | . . D5 . | Bb4 . . .",
  "C5 . Eb5 E5 | . Eb5 C5 . | Bb4 . G4 . | . . . .",
  ". . G4 . | Bb4 . C5 . | Eb5 . . . | F5 . Eb5 .",
  "C5 . . . | Eb5 . . . | Ab4 . . . | C5 . . .",
  "B4 . . . | D5 . . . | F5 . . . | D5 . B4 .",
  "C5 . . . | Ab4 . . . | F4 . Ab4 . | C5 . . .",
  "Eb5 . . . | . . C5 . | . . Ab4 . | . . F4 .",
  "Eb5 . . . | C5 . Eb5 . | F5 . . . | Eb5 . C5 .",
  "D5 . . . | . . . . | F5 . . . | . . D5 .",
  "C5 . Eb5 E5 | . Eb5 C5 . | Bb4 . G4 . | . . . .",
  "Ab4 . C5 Eb5 | . C5 Ab4 . | F#4 . . . | . . . .",
  "G4 . B4 . | D5 . F5 . | . . D5 . | B4 . . .",
  "G4 . . . | . . . . | B4 . D5 . | F5 . D5 ."
)

--- A one-bar line written on C, moved to each bar's root.
function M.follow(line)
  local t = {}
  for i, r in ipairs(M.roots) do t[i] = S.transpose(line, r) end
  return table.concat(t, " | ")
end

function M.chords(steps)
  local list = {}
  for i, r in ipairs(M.roots) do list[i] = M.chordOf[r] end
  return S.comp(list, steps)
end

function M.tops(steps)
  local list = {}
  for i, r in ipairs(M.roots) do list[i] = M.topOf[r] end
  return S.comp(list, steps)
end

return M
