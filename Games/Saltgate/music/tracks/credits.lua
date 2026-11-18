-- credits.lua: the end. The theme at 75 BPM on flute and harp over slow harp arpeggios, and for once it ends in
-- C major: morning over the harbour, the tide coming back in.
local S = require("music.score")
local T = require("music.theme")

local TONES = {
  { "C4", "Eb4", "G4" }, { "C4", "Eb4", "G4" }, { "Ab3", "C4", "Eb4", "F#4" }, { "G3", "B3", "D4", "F4" },
  { "C4", "Eb4", "G4" }, { "C4", "Eb4", "G4" }, { "Ab3", "C4", "Eb4", "F#4" }, { "G3", "B3", "D4", "F4" },
  { "Ab3", "C4", "Eb4", "F4" }, { "Bb3", "D4", "F4", "Ab4" }, { "G3", "Bb3", "D4", "Eb4" }, { "Ab3", "C4", "Eb4", "G4" },
  { "C4", "Eb4", "G4" }, { "Ab3", "C4", "Eb4", "F#4" }, { "G3", "B3", "D4", "F4" }, { "C4", "E4", "G4" },
}
local UPDOWN3 = { 1, 2, 3, 2, 1, 2, 3, 2 }
local UPDOWN4 = { 1, 2, 3, 4, 3, 2, 1, 2 }

local arp = {}
for i, tones in ipairs(TONES) do
  local shape = #tones == 4 and UPDOWN4 or UPDOWN3
  local bar = {}
  for k = 1, 8 do
    bar[#bar + 1] = tones[shape[k]] .. (k % 2 == 0 and "'" or "")
    bar[#bar + 1] = "."
  end
  arp[i] = table.concat(bar, " ")
end

-- the walking bass at half speed: the first and third quarter of each bar
local bass = {}
for i = 1, 16 do
  local toks = S.tokens(T.bass[i])
  local bar = {}
  for s = 1, 16 do bar[s] = "." end
  bar[1] = toks[1]
  if toks[9] ~= "." then bar[9] = toks[9] end
  bass[i] = table.concat(bar, " ")
end

local DAWN = "C5 . . . | . . E5 . | . . . . | G4 . . ."
local SOFT = "k' . . . | h' . . . | . . k' . | h' . . ."

return {
  mood = "the end: dawn on the water, Wren driving out of town",
  ticks = { 4 },
  loop = true,
  voices = {
    { name = "lead", inst = "flute", vol = 0.6 },
    { name = "bass", inst = "bass", vol = 0.75 },
    { name = "harp", inst = "harp", vol = 0.55 },
    { name = "arp", inst = "harp", vol = 0.3 },
    { name = "chime", inst = "chime", vol = 0.9 },
    { name = "drums", vol = 0.45, kit = { k = { "basedrum", 6, 1 }, h = { "hat", 16, 0.8 } } },
  },
  patterns = {
    main = {
      lead = S.join(T.bars(T.lead, 1, 8), S.rest(4), T.bars(T.lead, 13, 15), DAWN),
      harp = S.join(S.rest(8), T.bars(T.lead, 9, 12), S.rest(4)),
      bass = table.concat(bass, " | "),
      arp = table.concat(arp, " | "),
      chime = S.join("G4 . . . | . . . . | . . . . | . . . .", S.rest(3), "Eb4 . . . | . . . . | . . . . | . . . .", S.rest(3),
        "Ab4 . . . | . . . . | . . . . | . . . .", S.rest(3), "G4 . . . | . . . . | . . . . | . . . .", S.rest(2),
        "E4 . . . | . . . . | . . . . | . . . ."),
      drums = S.join(S.rest(4), S.rep(SOFT, 11), "k' . . . | . . . . | . . . . | . . . ."),
    },
  },
  order = { "main" },
}
