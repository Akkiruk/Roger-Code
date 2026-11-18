-- roam_score.lua
-- Walking-around music: one tune in five arrangements, one for each district, so walking from one into the next
-- changes the colour on the next bar line and keeps the phrase going (sync group "roam").
-- 100 BPM, swung 16ths, C dorian; sixteen bars, 38 seconds. The theme's blue-note turn (Eb-E-Eb-C) comes back in
-- bars 4 and 11.
--   1 Cm9  2 F9  3 Cm9  4 F9 | 5 Abmaj7  6 G7sus  7 Abmaj7  8 G7 | 9 Ebmaj7  10 Dm7b5  11 Cm9  12 Cm9 |
--   13 Fm9  14 Bb13  15 Abmaj7  16 G7alt

local S = require("music.score")

local M = {}

M.lead = S.join(
  ". . . . | . . . . | . . G4 . | Bb4 . C5 .",
  "Eb5 . . . | . . . . | D5 . C5 . | A4 . . .",
  ". . . . | . . . . | G4 . Bb4 . | C5 . Eb5 .",
  "E5 . Eb5 . | . . C5 . | . . . . | . . . .",
  ". . . . | G4 . . . | C5 . . . | Eb5 . D5 .",
  "C5 . . . | . . . . | . . . . | . . F4 .",
  "G4 . Ab4 . | C5 . . . | Eb5 . . . | . . C5 .",
  "D5 . . . | B4 . . . | G4 . . . | . . . .",
  ". . . . | Bb4 . D5 . | . . Eb5 . | . . D5 .",
  "C5 . . . | Ab4 . . . | F4 . . . | . . . .",
  ". . . . | . . . . | C5 . Eb5 . | E5 . . .",
  "Eb5 . . C5 | . . . . | Bb4 . G4 . | . . . .",
  "Ab4 . . . | . . G4 . | . . F4 . | Eb4 . . .",
  ". . . . | D4 . F4 . | G4 . . . | Ab4 . . .",
  "G4 . . . | . . . . | Eb5 . . . | C5 . . .",
  "B4 . . . | . . Ab4 . | . . . . | . . . ."
)

M.bass = S.join(
  "C4 . . . | . . . . | G3 . . . | . . Bb3 .",
  "F4 . . . | . . . . | C4 . . . | . . Eb4 .",
  "C4 . . . | . . . . | G3 . . . | . . Bb3 .",
  "F4 . . . | . . . . | A3 . . . | C4 . . .",
  "Ab3 . . . | . . . . | Eb4 . . . | . . G3 .",
  "G3 . . . | . . . . | D4 . . . | C4 . . .",
  "Ab3 . . . | . . . . | Eb4 . . . | C4 . . .",
  "G3 . . . | . . . . | B3 . . . | D4 . F4 .",
  "Eb4 . . . | . . . . | Bb3 . . . | . . G3 .",
  "D4 . . . | . . . . | Ab3 . . . | . . G3 .",
  "C4 . . . | . . . . | G3 . . . | . . Bb3 .",
  "C4 . . . | . . Eb4 . | . . G4 . | . . E4 .",
  "F4 . . . | . . . . | C4 . . . | . . Eb4 .",
  "Bb3 . . . | . . . . | F4 . . . | . . D4 .",
  "Ab3 . . . | . . . . | Eb4 . . . | . . C4 .",
  "G3 . . . | . . . . | D4 . . . | B3 . . ."
)

M.chords = {
  "Eb4+Bb4", "A3+Eb4", "Eb4+Bb4", "A3+Eb4", "C4+G4", "C4+F4", "C4+G4", "B3+F4",
  "G3+D4", "Ab3+C4", "Eb4+Bb4", "Eb4+Bb4", "Ab3+Eb4", "Ab3+D4", "C4+G4", "B3+F4",
}

-- the chords on beat 2 and the "and" of 4, with every fourth bar pushed earlier
function M.keys(mod)
  local lines = {}
  for i = 0, 3 do
    lines[#lines + 1] = S.comp({ M.chords[i * 4 + 1], M.chords[i * 4 + 2], M.chords[i * 4 + 3] }, { { 4, mod }, { 14, mod } })
    lines[#lines + 1] = S.comp({ M.chords[i * 4 + 4] }, { { 2, mod }, { 10, mod } })
  end
  return table.concat(lines, " | ")
end

--- One district's arrangement as a track file table.
--   lead, keys, bass: instruments; drums: a one-bar kit line (the fourth bar of each four gets fill);
--   kit: the hits; extra: more voices with lines of their own; vols: { lead, keys, bass }
function M.arrange(o)
  local voices = {
    { name = "lead", inst = o.lead, vol = o.vols[1], shift = o.leadShift },
    { name = "bass", inst = o.bass or "bass", vol = o.vols[3] },
    { name = "keys", inst = o.keys, vol = o.vols[2], shift = o.keysShift },
    { name = "drums", vol = o.drumVol or 0.5, kit = o.kit },
  }
  local pat = {
    lead = M.lead,
    bass = M.bass,
    keys = M.keys(o.keysMod),
    drums = S.rep(S.join(S.rep(o.drums, 3), o.fill or o.drums), 4),
  }
  for _, x in ipairs(o.extra or {}) do
    voices[#voices + 1] = x.voice
    pat[x.voice.name] = x.line
  end
  return {
    mood = o.mood,
    ticks = { 4, 2 },
    loop = true,
    sync = "roam",
    voices = voices,
    patterns = { main = pat },
    order = { "main" },
  }
end

return M
