-- roam_gilt.lua: Gilt Heights. The roam tune on harp with high bell chords and a hush of hats: money, glass, quiet.
local S = require("music.score")
local R = require("music.roam_score")

local function bars(list)
  local t = {}
  for i = 1, 16 do t[i] = list[i] and (list[i] .. " . . . | . . . . | . . . . | . . . .") or S.rest(1) end
  return table.concat(t, " | ")
end

return R.arrange({
  mood = "Gilt Heights: glass towers, doormen, the money is quiet",
  lead = "harp", keys = "bell", vols = { 0.65, 0.6, 0.8 },
  kit = { k = { "basedrum", 7, 0.6 }, h = { "hat", 18, 0.6 } },
  drumVol = 0.45,
  drums = "k+h' . h' . | h . h' . | . . h' k' | h . h' h'",
  extra = {
    { voice = { name = "chime", inst = "chime", vol = 0.9 }, line = bars({ "Bb4", nil, "G4", nil, "G4", nil, "C5", nil, "D5", nil, "Bb4", nil, "Eb4", nil, "G4" }) },
  },
})
