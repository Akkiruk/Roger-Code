-- roam_cinder.lua: Cinder Flats. The roam tune on iron xylophone over guitar, a didgeridoo under the bass and a
-- cow bell clanking on the backbeat like a hammer on pipe.
local R = require("music.roam_score")

return R.arrange({
  mood = "Cinder Flats: furnaces, rail yards, rust and steam",
  lead = "iron_xylophone", keys = "guitar", vols = { 0.6, 0.45, 0.85 },
  kit = { k = { "basedrum", 4, 1 }, s = { "snare", 10, 0.7 }, c = { "cow_bell", 6, 0.35 }, h = { "hat", 12, 0.6 } },
  drums = "k+h . h . | s+c . h . | k . h k | s+c . h .",
  fill = "k+h . h . | s+c . h . | k . s . | s s' s s'",
  extra = {
    { voice = { name = "drone", inst = "didgeridoo", vol = 0.25 }, line = R.bass },
  },
})
