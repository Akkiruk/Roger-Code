-- roam_brine.lua: the Brine Docks. The roam tune on banjo over guitar, sparse drums, a buoy bell and a foghorn now
-- and then.
local S = require("music.score")
local R = require("music.roam_score")

local function bars(list)
  local t = {}
  for i = 1, 16 do t[i] = list[i] and (list[i] .. " . . . | . . . . | . . . . | . . . .") or S.rest(1) end
  return table.concat(t, " | ")
end

return R.arrange({
  mood = "the Brine Docks: cranes, fog, rope creaking on the bollards",
  lead = "banjo", keys = "guitar", vols = { 0.6, 0.4, 0.8 },
  kit = { k = { "basedrum", 5, 0.9 }, s = { "snare", 12, 0.4 }, h = { "hat", 14, 0.6 } },
  drums = "k . h . | . . h . | k . h . | s' . h .",
  fill = "k . h . | . . h . | k . h s' | s . s' s'",
  extra = {
    { voice = { name = "buoy", inst = "bell", vol = 0.8 }, line = bars({ "C4", nil, nil, nil, "G3", nil, nil, nil, "C4", nil, nil, nil, "G3" }) },
    { voice = { name = "horn", inst = "didgeridoo", vol = 0.3 }, line = bars({ "C4", nil, nil, nil, nil, nil, nil, nil, "Eb4" }) },
  },
})
