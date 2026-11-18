-- roam.lua: walking Old Saltgate (and anywhere else when no district is set). Flute over harp and brushes.
local S = require("music.score")
local R = require("music.roam_score")

local function bars(list)
  local t = {}
  for i = 1, 16 do t[i] = list[i] and (list[i] .. " . . . | . . . . | . . . . | . . . .") or S.rest(1) end
  return table.concat(t, " | ")
end

return R.arrange({
  mood = "dusk in the old town: cobbles, gulls, a radio through an open window",
  lead = "flute", keys = "harp", vols = { 0.7, 0.38, 0.85 },
  kit = { k = { "basedrum", 6, 0.8 }, s = { "snare", 14, 0.45 }, h = { "hat", 16, 0.7 } },
  drums = "k+h . h . | s . h . | . . h k' | s . h h'",
  fill = "k+h . h . | s . h . | s' . s' . | s . s' s'",
  extra = {
    { voice = { name = "chime", inst = "chime", vol = 0.9 }, line = bars({ "G4", nil, nil, nil, "Eb4", nil, nil, nil, "D4", nil, "G4" }) },
  },
})
