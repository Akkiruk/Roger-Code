-- theme.lua
-- SALTGATE's main theme, grown from the title phrase the game has played since the start: the flute's
-- C-Eb-E-Eb-C-Bb-G blue-note turn over the walking bass C-Eb-F-G. Sixteen bars of 16 steps in C minor.
-- The title plays it as it is; the finale and the credits arrange the same lines.
--   bars:  1 Cm   2 Cm   3 Ab7   4 G7  | 5 Cm  6 Cm  7 Ab7  8 G7 | 9 Fm7  10 Bb7  11 Ebmaj7  12 Ab G7 |
--          13 Cm  14 Ab7  15 G7  16 Cm G7

local M = {}

M.lead = {
  "C5 . Eb5 . | E5 . . Eb5 | . C5 . . | Bb4 . . .",
  "G4 . . . | . . . . | . . . . | G4 . Bb4 .",
  "C5 . Eb5 . | F5 . . Eb5 | . C5 . . | Ab4 . . .",
  "G4 . . B4 | . . D5 . | . F5 . . | Eb5 . D5 .",
  "C5 . Eb5 . | E5 . . Eb5 | . C5 . . | Bb4 . . .",
  "G4 . . . | . . . . | C5 . Bb4 . | G4 . Bb4 .",
  "C5 . Eb5 . | F5 . . Eb5 | . C5 . . | Ab4 . . .",
  "G4 . . B4 | . . D5 . | F5 . Eb5 . | D5 . C5 .",
  "Ab4 . . C5 | . . Eb5 . | . . F5 . | Eb5 . C5 .",
  "D5 . . . | . . Bb4 . | Ab4 . . . | F4 . . .",
  "G4 . . Bb4 | . . D5 . | . . Eb5 . | D5 . Bb4 .",
  "C5 . . . | Ab4 . . . | B4 . D5 . | F5 . D5 .",
  "C5 . Eb5 . | E5 . . Eb5 | . C5 . . | Bb4 . . .",
  "Ab4 . C5 . | Eb5 . . C5 | . Ab4 . . | F#4 . . .",
  "G4 . . . | . . B4 . | D5 . . . | F5 . Eb5 .",
  "D5 . C5 . | . . . . | G4 . . . | Bb4 . B4 .",
}

M.bass = {
  "C4 . . . | Eb4 . . . | F4 . . . | G4 . . .",
  "C4 . . . | . . G3 . | Bb3 . . . | A3 . . .",
  "Ab3 . . . | C4 . . . | Eb4 . . . | F#4 . . .",
  "G4 . . . | F4 . . . | D4 . . . | B3 . . .",
  "C4 . . . | Eb4 . . . | F4 . . . | G4 . . .",
  "C4 . . . | . . G3 . | Bb3 . . . | A3 . . .",
  "Ab3 . . . | C4 . . . | Eb4 . . . | F#4 . . .",
  "G4 . . . | F4 . . . | D4 . . . | C4 . . .",
  "F4 . . . | G4 . . . | Ab4 . . . | A4 . . .",
  "Bb4 . . . | Ab4 . . . | F4 . . . | D4 . . .",
  "Eb4 . . . | F4 . . . | G4 . . . | Bb4 . . .",
  "Ab4 . . . | Eb4 . . . | G4 . . . | B3 . . .",
  "C4 . . . | Eb4 . . . | F4 . . . | G4 . . .",
  "Ab3 . . . | C4 . . . | Eb4 . . . | F#4 . . .",
  "G4 . . . | F4 . . . | D4 . . . | B3 . . .",
  "C4 . . . | . . C4' . | G3 . . . | D4 . B3 .",
}

-- two chord tones under the tune for each half bar
M.chords = {
  { "Eb4+G4" }, { "Eb4+G4" }, { "C4+F#4" }, { "B3+F4" },
  { "Eb4+G4" }, { "Eb4+G4" }, { "C4+F#4" }, { "B3+F4" },
  { "Ab3+Eb4" }, { "Ab3+D4" }, { "G3+D4" }, { "C4+Eb4", "B3+F4" },
  { "Eb4+G4" }, { "C4+F#4" }, { "B3+F4" }, { "Eb4+G4", "B3+F4" },
}

-- roots, for bass lines of another shape: transpose a line written on C by these
M.roots = { 0, 0, -4, -5, 0, 0, -4, -5, 5, -2, 3, -4, 0, -4, -5, 0 }

--- Bars from..to of a list, joined.
function M.bars(list, from, to)
  local t = {}
  for i = from, to do t[#t + 1] = list[i] end
  return table.concat(t, " | ")
end

--- Chord stabs at two steps of each bar (the second half's chord at the second step, if the bar has one).
function M.stabs(from, to, a, b, modA, modB)
  local t = {}
  for i = from, to do
    local bar = {}
    for s = 1, 16 do bar[s] = "." end
    local c = M.chords[i]
    local function put(step, chord, mod)
      local parts = {}
      for part in string.gmatch(chord, "[^+]+") do parts[#parts + 1] = part .. (mod or "") end
      bar[step + 1] = table.concat(parts, "+")
    end
    put(a, c[1], modA)
    put(b, c[2] or c[1], modB)
    t[#t + 1] = table.concat(bar, " ")
  end
  return table.concat(t, " | ")
end

return M
