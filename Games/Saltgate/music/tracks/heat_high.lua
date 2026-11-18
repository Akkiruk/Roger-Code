-- heat_high.lua: the whole Harbor Patrol (heat 3+). The chase doubled: sixteenth-note bass, kick and snare
-- trading, flute and bit in unison on the turn, iron xylophone hammering the roots.
local S = require("music.score")
local C = require("music.chase_score")

local BEAT = "k+h . h' k | s+h . k h | k+h . h' k | s+h . h s'"
local FILL = "k+h . s s | s+h . s s | s s s s | s! s s s!"

return {
  mood = "every siren in Saltgate: no thinking, only driving",
  ticks = { 2 },
  loop = true,
  sync = "chase",
  voices = {
    { name = "lead", inst = "flute", vol = 0.75 },
    { name = "bass", inst = "bass", vol = 0.9 },
    { name = "double", inst = "bit", vol = 0.8 },
    { name = "stab", inst = "iron_xylophone", vol = 0.45 },
    { name = "drums", vol = 0.6, kit = { k = { "basedrum", 6, 1 }, s = { "snare", 14, 0.75 }, h = { "hat", 20, 0.7 } } },
  },
  patterns = {
    main = {
      lead = C.lead,
      double = C.lead,
      bass = C.follow("C4 C4' C5 C4' C4 C4' C5 C4' C4 C4' C5 C4' Bb4 C4' C5 C4'"),
      stab = C.tops({ 0, { 3, "'" }, 6, { 10, "'" } }),
      drums = S.rep(S.join(BEAT, BEAT, BEAT, FILL), 4),
    },
  },
  order = { "main" },
}
