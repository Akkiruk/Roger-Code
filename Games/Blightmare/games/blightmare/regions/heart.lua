-- games/blightmare/regions/heart.lua
-- Act one of the rest of the game: over the Greywater, Hayford and its frogs, Oplinas and the library, Glamouth, and into the
-- Verdant Sea to Lucilda's windmill. Draft for the author to edit, in the voice of story.lua.
--
-- Maps here are drawn with their people on them. In a row any letter or digit is a mark: lower case and digits are floor, upper
-- case are stairs, and h, L and W keep their usual meaning. place() turns the marks into plain tiles and looks each thing's at
-- up in them, so moving someone is a matter of moving a letter.

local say = require("games.blightmare.say")
local C = require("lib.arcade.ui").C

local t, ask, topic, person, line = say.t, say.ask, say.topic, say.person, say.line

local R = {
  id = "heart", prefix = "hr_",
  entry = { flags = { "finished" }, join = { "deserter", "cleric" }, lvl = 6, site = "orrenshire" },
  exit = "hr_done",
  -- Flags from the slice that are read here, and flags from here that later regions may like to read.
  exports = {
    "frog_wet", "rude_frog", "wore_hat", "drew_fire",
    "hr_on_credit", "hr_tied_aude", "hr_keel_spared", "hr_fed_tully",
  },
  sites = {}, maps = {}, scripts = {}, shops = {}, goals = {},
  foes = {}, abilities = {}, encounters = {}, field = {},
  looks = {}, names = {}, art = {},
  items = {
    hr_passes = { name = "BRASSCAP'S PASSES", key = true },
    hr_receipt = { name = "TITHE RECEIPT", key = true },
    hr_ticket = { name = "READER'S TICKET", key = true },
    hr_hat = { name = "THE MAYOR'S HAT", key = true },
    hr_log = { name = "LOG OF THE LONG HAUL", key = true },
  },
}

local WORLD = { hayford = { 106, 65 }, oplinas = { 108, 47 }, glamouth = { 92, 71 }, windmill = { 96, 60 } }

-- ---------------------------------------------------------------- the helpers maps are drawn with

local SPOTS = {}

--- A map from its drawing: marks become tiles, and every at becomes an x and y.
local function place(id, def)
  local spots, rows = {}, {}
  for y, row in ipairs(def.rows) do
    local cells = {}
    for x = 1, #row do
      local c = row:sub(x, x)
      if c:find("%w") and c ~= "h" and c ~= "L" and c ~= "W" then
        spots[c] = { x, y }
        c = c:find("%u") and ">" or "."
      end
      cells[x] = c
    end
    rows[y] = table.concat(cells)
  end
  def.rows = rows
  SPOTS[id] = spots
  for _, kind in ipairs({ "npcs", "steps", "chests", "foes", "exits" }) do
    for _, thing in ipairs(def[kind] or {}) do
      local spot = spots[thing.at]
      if not spot then error(id .. " has no mark " .. tostring(thing.at)) end
      thing.x, thing.y, thing.at = spot[1], spot[2], nil
    end
  end
  R.maps[id] = def
end

--- x and y of a mark.
local function spot(id, mark)
  local at = SPOTS[id] and SPOTS[id][mark]
  if not at then error("no mark " .. tostring(mark) .. " on " .. tostring(id)) end
  return at[1], at[2]
end

--- A step that puts the party on a mark.
local function warpTo(id, mark, dir)
  local x, y = spot(id, mark)
  return { warp = { id, x, y, dir } }
end

--- Everyone with a name of their own has a look, and the name finds the look.
local function who(id, name)
  R.names[name] = id
  return person(id, name)
end

-- ---------------------------------------------------------------- how people look

local L = R.looks

-- Hayford: everyone well fed and slightly over-dressed, with something to sell in their hand
L.hr_tolliver = { kind = "old", tall = 0.76, build = "broad", cut = "coat", coat = C.accent, trim = C.hi, hair = "tufts", hairInk = C.line, beard = "chops", beardInk = C.line, wear = { "chain", "waistcoat" }, vestInk = C.hi, carry = "ledger", eyes = "shifty", mouth = "frown", back = C.hiTint }
L.hr_ambry = { kind = "human", tall = 0.93, build = "thin", cut = "robe", coat = C.hi, trim = C.accent, hat = "pointy", hatInk = C.hi, hatTrim = C.accent, hair = "bun", hairInk = C.text, wear = { "chain" }, carry = "tray", eyes = "narrow", mouth = "smile", back = C.hiTint }
L.hr_farthing = { kind = "child", tall = 0.46, build = "thin", cut = "coat", coat = C.tie, trim = C.hi, hat = "bowler", hatInk = C.bg, hatTrim = C.hi, hatSmall = 1.2, hair = "pigtails", hairInk = C.redTint, carry = "ledger", eyes = "narrow", mouth = "line", back = C.tie }
L.hr_sheaf = { kind = "human", tall = 0.88, build = "stout", cut = "dress", coat = C.hiTint, trim = C.warn, hat = "scarf", hatInk = C.hi, hatTrim = C.warn, hair = "curls", hairInk = C.redTint, wear = { "apron" }, carry = "keys", mouth = "smile", back = C.redTint }
L.hr_bushel = { kind = "human", tall = 0.84, build = "broad", cut = "dress", coat = C.redTint, trim = C.hi, hat = "straw", hatInk = C.hi, hatTrim = C.warn, hair = "plaits", hairInk = C.hi, wear = { "apron" }, carry = "basket", mouth = "open", back = C.hiTint }
L.hr_loam = { kind = "human", tall = 0.94, build = "thin", cut = "coat", coat = C.bg, trim = C.line, hat = "tophat", hatInk = C.bg, hatTrim = C.line, hair = "short", hairInk = C.line, beard = "goatee", beardInk = C.line, skin = C.text, carry = "clipboard", eyes = "specs", mouth = "smile", back = C.panel }
L.hr_punt = { kind = "old", tall = 0.78, build = "hunched", cut = "tunic", coat = C.hiTint, trim = C.panel, hat = "wide", hatInk = C.tie, hatTrim = C.panel, beard = "long", beardInk = C.line, carry = "pole", eyes = "closed", mouth = "line", back = C.panel }
L.hr_claim1 = { kind = "human", pose = "lying", bed = true, coat = C.hiTint, trim = C.tie, hair = "short", hairInk = C.redTint, thread = false }
L.hr_claim2 = { kind = "human", pose = "lying", bed = true, coat = C.hi, trim = C.warn, hair = "plaits", hairInk = C.hi, thread = false, flip = true, size = 0.85 }
L.hr_claim3 = { kind = "child", pose = "lying", bed = true, coat = C.tie, trim = C.line, hair = "wild", hairInk = C.bg, thread = false, size = 0.7 }

-- the swamp
L.hr_bogg = { kind = "frog", tall = 0.97, build = "broad", coat = C.bg, trim = C.ok, hat = "tophat", hatSmall = 0.6, hatShift = 0.05, hatInk = C.accent, hatTrim = C.hi, wear = { "waistcoat" }, vestInk = C.accent, stand = "stocks", carry = "mug", back = C.panel } -- he left with the plank, and has laid a table on it
L.hr_duck = { kind = "frog", tall = 0.66, build = "thin", cut = "robe", coat = C.bg, trim = C.line, carry = "goose", back = C.bg } -- a very small frog, holding the Duck
L.hr_skim = { kind = "frog", tall = 0.8, build = "thin", cut = "tunic", coat = C.tie, trim = C.ok, hat = "feather", hatInk = C.red, hatTrim = C.hi, carry = "spear", back = C.panel }
L.hr_rush = { kind = "frog", tall = 0.74, build = "normal", cut = "coat", coat = C.bg, trim = C.text, hat = "bowler", hatSmall = 0.5, hatInk = C.bg, hatTrim = C.text, wear = { "strap" }, carry = "scroll", back = C.blueTint }

-- Oplinas: refugees in old good cloth, Heartlanders in new plain cloth, and the Clinic in grey
L.hr_crue = { kind = "clinic", tall = 0.95, build = "broad", coat = C.tie, trim = C.panel, hat = "sallet", hatInk = C.line, hatTrim = C.blue, beak = 0.09, wear = { "badge", "belt" }, carry = "clipboard", back = C.redTint }
L.hr_ione = { kind = "half-elf", tall = 0.9, build = "thin", cut = "robe", coat = C.blue, trim = C.hi, hair = "long", hairInk = C.text, hat = "feather", hatInk = C.blue, hatTrim = C.hi, hatSmall = 0.7, wear = { "shawl" }, shawlInk = C.accent, carry = "scroll", eyes = "tired", mouth = "line", back = C.blueTint }
L.hr_tessaly = { kind = "old", tall = 0.8, build = "thin", cut = "robe", coat = C.accent, trim = C.text, hair = "bun", hairInk = C.text, eyes = "specs", carry = "book", mouth = "line", back = C.blueTint }
L.hr_wenna = { kind = "human", tall = 0.9, build = "broad", cut = "dress", coat = C.warn, trim = C.redTint, hat = "scarf", hatInk = C.red, hatTrim = C.warn, hair = "short", hairInk = C.bg, wear = { "apron" }, apronInk = C.redTint, carry = "mug", eyes = "narrow", mouth = "frown", back = C.hiTint }
L.hr_aude = { kind = "old", tall = 0.8, pose = "lying", bed = true, coat = C.line, trim = C.accent, hair = "long", hairInk = C.text, thread = false, back = C.tie }
L.hr_sorrel = { kind = "clinic", tall = 0.9, build = "thin", cut = "coat", coat = C.line, trim = C.red, hat = "hood", hatInk = C.line, hatTrim = C.red, beak = 0.05, maskInk = C.text, wear = { "strap" }, carry = "lantern", beakStyle = "hook", back = C.redTint }
L.hr_dossett = { kind = "human", tall = 0.86, build = "stout", cut = "tunic", coat = C.tie, trim = C.hi, hat = "cap", hatInk = C.redTint, hatTrim = C.hi, beard = "whiskers", beardInk = C.line, wear = { "apron", "tags" }, carry = "hammer", mouth = "smile", back = C.tie }
L.hr_hale = { kind = "half-elf", tall = 0.92, build = "normal", cut = "dress", coat = C.blueTint, trim = C.text, hat = "scarf", hatInk = C.blueTint, hatTrim = C.text, hair = "short", hairInk = C.line, wear = { "apron" }, carry = "keys", eyes = "tired", mouth = "smile", back = C.blueTint }
L.hr_inspector = { kind = "clinic", tall = 0.8, build = "gaunt", cut = "coat", coat = C.text, trim = C.line, hat = "bowler", hatInk = C.line, hatTrim = C.text, beak = 0.03, maskInk = C.text, beakInk = C.text, wear = { "strap" }, carry = "pen", back = C.panel }

-- the library
L.hr_vance = { kind = "old", tall = 0.84, build = "hunched", cut = "robe", coat = C.blueTint, trim = C.line, hair = "tufts", hairInk = C.text, beard = "long", beardInk = C.text, eyes = "specs", carry = "book", mouth = "open", back = C.blueTint }
L.hr_bust_owl = { kind = "owlin", tall = 0.62, build = "thin", cut = "robe", coat = C.line, trim = C.tie, skin = C.line, back = C.panel }
L.hr_bust_raven = { kind = "owlin", tall = 0.74, build = "gaunt", cut = "robe", coat = C.bg, trim = C.accent, skin = C.bg, back = C.panel }
L.hr_bust_key = { kind = "old", tall = 0.62, build = "thin", cut = "robe", coat = C.tie, trim = C.hi, skin = C.line, hat = "hood", hatInk = C.tie, hatTrim = C.line, carry = "keys", eyes = "closed", mouth = "none", back = C.panel }

L.hr_sluice_a = { kind = "old", tall = 0.6, lean = 0.26, build = "hunched", cut = "coat", coat = C.tie, trim = C.ok, skin = C.line, hair = "tufts", hairInk = C.ok, carry = "wheel", eyes = "closed", mouth = "none", back = C.panel }
L.hr_sluice_b = { kind = "old", tall = 0.56, lean = 0.3, build = "gaunt", cut = "coat", coat = C.panel, trim = C.soft, skin = C.line, carry = "pen", eyes = "closed", mouth = "line", back = C.panel }
L.hr_lucilda = { like = "lucilda", tall = 0.95, lean = 0.26, carry = "bowl" }

-- Glamouth: salt, colour and a great many knives
L.hr_drum = { kind = "half-elf", tall = 0.96, build = "broad", coat = C.red, trim = C.hi, hat = "tricorn", hatInk = C.bg, hatTrim = C.hi, hair = "long", hairInk = C.bg, wear = { "cape", "belt", "chain" }, capeInk = C.bg, carry = "rapier", eyes = "narrow", mouth = "smile", mark = "ink", back = C.redTint }
L.hr_keel = { kind = "human", tall = 0.93, build = "thin", cut = "coat", coat = C.tie, trim = C.bg, hat = "wide", hatInk = C.bg, hatTrim = C.line, hair = "short", hairInk = C.line, wear = { "belt", "strap" }, carry = "dagger", eyes = "narrow", mouth = "line", mark = "scar", back = C.panel }
L.hr_fathom = { kind = "miner", tall = 0.7, build = "broad", cut = "tunic", coat = C.blueTint, trim = C.text, hat = "earflap", hatInk = C.bg, hatTrim = C.line, beard = "plaited", beardInk = C.hi, wear = { "apron" }, carry = "mug", eyes = "tired", mouth = "line", back = C.blueTint }
L.hr_wren = { kind = "child", tall = 0.44, build = "thin", cut = "tunic", coat = C.panel, trim = C.tie, hat = "cap", hatInk = C.panel, hatTrim = C.red, hair = "wild", hairInk = C.redTint, oneShoe = true, carry = "keys", eyes = "shifty", mouth = "smile", back = C.tie }
L.hr_annis = { kind = "old", tall = 0.76, build = "hunched", lean = 0.12, cut = "coat", coat = C.blue, trim = C.hi, hat = "wide", hatInk = C.blue, hatTrim = C.hi, hair = "plaits", hairInk = C.text, carry = "cane", eyes = "closed", mouth = "smile", back = C.panel }
L.hr_gilt = { kind = "human", tall = 0.91, build = "normal", cut = "tunic", coat = C.hi, trim = C.bg, hat = "helmet", hatInk = C.hi, hatTrim = C.text, beard = "stubble", wear = { "belt" }, carry = "spear", eyes = "shifty", mouth = "frown", back = C.hiTint }
L.hr_scrimp = { kind = "gnome", tall = 0.48, build = "stout", cut = "tunic", coat = C.bg, trim = C.red, hat = "floppy", hatInk = C.red, hatTrim = C.bg, beard = "forked", beardInk = C.hi, wear = { "apron" }, carry = "hammer", eyes = "narrow", mouth = "smile", back = C.panel }

-- the grass
L.hr_tully = { kind = "old", tall = 0.82, build = "stout", cut = "tunic", coat = C.text, trim = C.blueTint, hat = "cap", hatInk = C.text, hatTrim = C.blue, beard = "whiskers", beardInk = C.text, wear = { "apron" }, carry = "ladle", eyes = "wide", mouth = "open", back = C.hiTint }
L.hr_thatch = { kind = "human", tall = 0.96, build = "thin", cut = "tunic", coat = C.tie, trim = C.hi, skin = C.hiTint, hat = "straw", hatInk = C.hi, hatTrim = C.warn, hair = "wild", hairInk = C.hi, wear = { "patches" }, carry = "pole", eyes = "wide", mouth = "stitched", nose = "none", back = C.hiTint }
L.hr_carrion = { kind = "harpyfolk", tall = 1, build = "hunched", cut = "rags", coat = C.bg, trim = C.red, wings = C.bg, hair = "wild", hairInk = C.tie, wear = { "fur", "necklace" }, eyes = "red", mouth = "teeth", back = C.redTint }

-- ---------------------------------------------------------------- the maps

-- Hayford is an island of barley. The causeway comes in on the west, the church, the inn and the shop are along the north, the
-- Mayor's counting house stands in the square, and Old Punt's jetty runs off east into the swamp. The barn is Adjuster Loam's.
place("hr_hayford", {
  name = "HAYFORD", theme = "town", savepoint = true,
  rows = {
    "##########################",
    "#hhhhhhhhhhhhhhhhhhhhhhhh#",
    "#h.....h.........h......h#",
    "#h..b..h....d....h..e...h#",
    "#h....1h.........h.....2h#",
    "#hh+hhhhhhhh+hhhhhhh+hhhh#",
    "#...................~~~~~#",
    "#za......hhhhhhhh...~~~~~#",
    "#........h......h...~~~~~#",
    "#...g....h..m...+......jn#",
    "#........h......h...~~~~~#",
    "#.....p..hhhhhhhh.k.~~~~~#",
    "#...................~~~~~#",
    "#hh+hhhhhhh+hhhhhhh+hhhhh#",
    "#h.....h.......h........h#",
    "#h..u..h..r....h..x..y..h#",
    "#h....3h.......h...w....h#",
    "##########################",
  },
  npcs = {
    { id = "hr_sheaf", at = "b", sprite = "innkeeper", script = "hr_talk_sheaf" },
    { id = "hr_ambry", at = "d", sprite = "villager", script = "hr_talk_ambry" },
    { id = "hr_bushel", at = "e", sprite = "villager", script = "hr_talk_bushel" },
    { id = "hr_farthing", at = "g", sprite = "child", script = "hr_talk_farthing" },
    { id = "hr_tolliver", at = "m", sprite = "villager", script = "hr_talk_tolliver" },
    { id = "hr_punt", at = "n", sprite = "villager", script = "hr_talk_punt" },
    { id = "hr_loam", at = "k", sprite = "villager", script = "hr_talk_loam" },
    { id = "hr_claim1", at = "x", sprite = "shroud", script = "hr_talk_claim" },
    { id = "hr_claim2", at = "y", sprite = "shroud", script = "hr_talk_claim" },
    { id = "hr_claim3", at = "w", sprite = "shroud", script = "hr_talk_claim" },
  },
  steps = {
    { at = "a", script = "hr_scene_hayford", unless = "hr_at_hayford" },
  },
  chests = {
    { id = "c1", at = "1", give = "potion", n = 2 },
    { id = "c2", at = "2", give = "eyewash", n = 2 },
    { id = "c3", at = "3", gold = 90 },
  },
  exits = {
    { at = "z", world = WORLD.hayford },
  },
})

-- The frogs' side of things. South from the jetty is the frogs' road, past a sentry with a very high opinion of his password.
-- North is the long way, which is why nobody uses it and everything lives there. Either way ends at the court and the stairs.
place("hr_swamp_1", {
  name = "THE SLOUGH", theme = "swamp",
  rows = {
    "########################",
    "#.a...#~~~~~~~~#..q....#",
    "#.#z#.#~~~~~~~~#.#####.#",
    "#.#1#.#~~~~~~~~#.#...#.#",
    "#.#.#...f......#.#.2.#.#",
    "#.#.#####.####.#.#...#.#",
    "#...#...#.#..#...##+##.#",
    "###.#.j.+.#..#####...#.#",
    "#...#...#.#......#.b.#.#",
    "#.#######.#.####.#...#.#",
    "#...r.....#.#~~#.#.d.#.#",
    "#####s#####.#~~#.#...#.#",
    "#~~~#.#...g.#~~#.#.o.#.#",
    "#~~~#.#.#####~~#.##+##.#",
    "#~~~#...#~~~~~~#..t....#",
    "#~~~###.#~~~~~~#####.###",
    "#~~~~~#3#~~~~~~~~~~#D###",
    "########################",
  },
  npcs = {
    { id = "hr_skim", at = "s", sprite = "frogman", script = "hr_talk_skim", unless = "hr_skim_ok" },
    { id = "hr_bogg", at = "b", sprite = "frogman", script = "hr_talk_bogg" },
    { id = "hr_duck", at = "d", sprite = "frogman", script = "hr_talk_duck" },
  },
  chests = {
    { id = "c1", at = "1", give = "antidote", n = 3 },
    { id = "c2", at = "2", give = "bone_saw" },
    { id = "c3", at = "3", give = "ether", n = 1 },
  },
  foes = {
    { id = "f1", at = "f", enc = "hr_slough_1", sprite = "frogman" },
    { id = "f2", at = "r", enc = "hr_slough_2", sprite = "hr_leech" },
    { id = "f3", at = "g", enc = "hr_slough_1", sprite = "frogman" },
    { id = "f4", at = "q", enc = "hr_slough_3", sprite = "hr_snapper" },
    { id = "f5", at = "t", enc = "hr_slough_2", sprite = "hr_leech" },
  },
  exits = {
    { at = "z", to = { "hr_hayford", "j", 4 } },
    { at = "D", to = { "hr_swamp_2", "a", 2 }, when = "hr_bogg_asked" },
    { at = "D", script = "hr_stair_shut", unless = "hr_bogg_asked" },
  },
})

-- A pool the size of a parish, with a causeway through it and an island in the middle. You can see Old Dividend from a long way
-- off, and he can see you.
place("hr_swamp_2", {
  name = "THE OFFERTORY", theme = "swamp",
  rows = {
    "######################",
    "#Aa..................#",
    "#.##################.#",
    "#.#~~~~~~~~~~~~~~~~#.#",
    "#.#~~~~~~~~~~~~~~~~#.#",
    "#.#~~~~#.....#~~~~~#.#",
    "#.#~~~~#.....#~~~~~#.#",
    "#...c...l.p.r...e....#",
    "#.#~~~~#..s..#~~~~~#.#",
    "#.#~~~~###.###~~~~~#.#",
    "#.#~~~~~~#.#~~~~~~~#.#",
    "#.########.#########.#",
    "#...g.....u...k......#",
    "#.#######.#.########.#",
    "#3......#.1.#4.....2.#",
    "######################",
  },
  steps = {
    { at = "a", script = "hr_scene_offertory", once = true },
    { at = "u", script = "hr_read_bailiff", once = true },
    { at = "l", script = "hr_scene_dividend", unless = "hr_dividend_down" },
    { at = "r", script = "hr_scene_dividend", unless = "hr_dividend_down" },
    { at = "s", script = "hr_scene_dividend", unless = "hr_dividend_down" },
  },
  chests = {
    { id = "c1", at = "1", gold = 250 },
    { id = "c2", at = "2", give = "tonic", n = 2 },
    { id = "c3", at = "3", give = "linen_alb" },
    { id = "c4", at = "4", give = "iron_charm" },
  },
  foes = {
    { id = "f1", at = "c", enc = "hr_slough_3", sprite = "hr_snapper" },
    { id = "f2", at = "e", enc = "hr_slough_2", sprite = "hr_leech" },
    { id = "f3", at = "g", enc = "hr_slough_3", sprite = "hr_snapper" },
    { id = "f4", at = "k", enc = "hr_slough_1", sprite = "frogman" },
  },
  exits = {
    { at = "A", to = { "hr_swamp_1", "t", 2 } },
  },
})

-- A city of refugees with a foreign army on its gate. The library's steps are north of the market, with the inn and the Circle
-- House either side, and the south street runs along the back of the almshouse and the undertaker's to the gate.
place("hr_oplinas", {
  name = "OPLINAS", theme = "city", savepoint = true,
  rows = {
    "##############################",
    "#hhhhhhhhhhhhhhhhhhhhhhhhhhhh#",
    "#h......h...........h.......h#",
    "#h..i...h...........h...v...h#",
    "#h.....1h...........h......2h#",
    "#hhh+hhhhhhhhhKhhhhhhhh+hhhhh#",
    "#.............k..............#",
    "#.hhhhhhh..............hhhhh.#",
    "#.h.....h..............h...h.#",
    "#.h..c..+...e....s.....+.y.h.#",
    "#.h.....h..............h...h.#",
    "#.hhhhhhh...w..........hhhhh.#",
    "#............................#",
    "#hhh+hhhhhh+hhhhhhhhh+hhh+hhh#",
    "#h.....h.......h.......h....h#",
    "#h..a..h...u...h...m...h.3..h#",
    "#h.....h.......h.......h....h#",
    "#hhhhhhhhhhhhhhhhhhhhhhhh+hhh#",
    "#............................#",
    "#hhhhhhhhhhhhh.o.hhhhhhhhhhhh#",
    "#hhhhhhhhhhhhh.g.hhhhhhhhhhhh#",
    "#hhhhhhhhhhhhh.z.hhhhhhhhhhhh#",
    "##############################",
  },
  npcs = {
    { id = "hr_hale", at = "i", sprite = "innkeeper", script = "hr_talk_hale" },
    { id = "hr_ione", at = "v", sprite = "villager", script = "hr_talk_ione" },
    { id = "hr_dossett", at = "c", sprite = "smith", script = "hr_talk_dossett" },
    { id = "hr_sorrel", at = "e", sprite = "doctor", script = "hr_talk_sorrel", unless = "hr_inspector_down" },
    { id = "hr_wenna", at = "s", sprite = "villager", script = "hr_talk_wenna" },
    { id = "hr_aude", at = "a", sprite = "shroud", script = "hr_talk_aude" },
    { id = "hr_crue", at = "o", sprite = "captain", script = "hr_talk_crue" },
  },
  steps = {
    { at = "g", script = "hr_scene_oplinas", unless = "hr_through_gate" },
    { at = "y", script = "hr_read_posters", once = true },
    { at = "m", script = "hr_read_left", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "ether", n = 1 },
    { id = "c2", at = "2", give = "ash_rod" },
    { id = "c3", at = "3", give = "tonic", n = 2 },
  },
  exits = {
    { at = "z", world = WORLD.oplinas },
    { at = "K", to = { "hr_library_1", "a", 1 } },
  },
})

-- The reading hall. Shelves in long bays either side, the Keeper's desk at the south, and the old vault stair in the middle, with
-- the Ultimatum's rule of shelving cut into the floor in front of it.
place("hr_library_1", {
  name = "THE GREAT LIBRARY", theme = "library", savepoint = true,
  rows = {
    "##########################",
    "#1.......h.......h......2#",
    "#.hhhhhh.h.hh.hh.h.hhhhh.#",
    "#........h.h...h.h.......#",
    "#.hhhhhh.h.h.D.h.h.hhhhh.#",
    "#........h.hhphh.h.......#",
    "#.hhhhhh.h.......h.hhhhh.#",
    "#...u....hhh...hhh...r...#",
    "#.hhhhhh.....k.....hhhhh.#",
    "#.................s......#",
    "#.hhhhhh.hhh.hhh.h.hhhhh.#",
    "#........h.....h.........#",
    "#.hhhhhh.h..v..h.hhhhhhh.#",
    "#........h.....h.........#",
    "#hhhhhhhhhhh.hhhhhhhhhhhh#",
    "#hhhhhhhhhhhahhhhhhhhhhhh#",
    "#hhhhhhhhhhhZhhhhhhhhhhhh#",
    "##########################",
  },
  npcs = {
    { id = "hr_tessaly", at = "v", sprite = "villager", script = "hr_talk_tessaly" },
    { id = "hr_vance", at = "u", sprite = "villager", script = "hr_talk_vance" },
  },
  steps = {
    { at = "p", script = "hr_read_rule", once = true },
    { at = "a", script = "hr_scene_library", unless = "hr_in_library" },
  },
  chests = {
    { id = "c1", at = "1", give = "echoherb", n = 2 },
    { id = "c2", at = "2", gold = 160 },
  },
  exits = {
    { at = "Z", to = { "hr_oplinas", "k", 3 } },
    { at = "D", to = { "hr_library_2", "a", 2 }, when = "hr_ticket_shown" },
    { at = "D", script = "hr_stair_keeper", unless = "hr_ticket_shown" },
  },
})

-- Everything the Empire's refugees carried out, in the order they put it down. Crates, then bays, then the scholar's nest in the
-- middle room, and at the south the long gallery with the three busts and the stair to the Closed Stack.
place("hr_library_2", {
  name = "THE LOST STACKS", theme = "library",
  rows = {
    "############################",
    "#Aa...f.....h..........q...#",
    "#####.#####.h.hhhhhhhhh.hh.#",
    "#1..#.#...#.h.h.......h.hh.#",
    "#.h.#e#.2.#.h.h.......hw...#",
    "#.h...#...#...h.......h.hhh#",
    "#.hhh.##+####.hhhh+hhhh.h3.#",
    "#............g.............#",
    "#.hhhhhh.hhhhhhhh.hhhhhhhh.#",
    "#.h....h.h......h.h......h.#",
    "#.h.4..+.h..b...+.+..r...h.#",
    "#.h....h.h......h.h......h.#",
    "#.hhhhhh.hhh.hhhh.hhhhhhhh.#",
    "#..........k...............#",
    "#hhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#h...........x............h#",
    "#h..p.....m.......n.....5.h#",
    "#h........................h#",
    "#hhhhhhhhhhhhDhhhhhhhhhhhhh#",
    "############################",
  },
  npcs = {
    { id = "owlin", at = "b", sprite = "villager", script = "hr_scene_scholar", unless = "hr_scholar" },
    { id = "hr_bust_key", at = "p", sprite = "villager", script = "hr_bust_key" },
    { id = "hr_bust_owl", at = "m", sprite = "villager", script = "hr_bust_owl" },
    { id = "hr_bust_raven", at = "n", sprite = "villager", script = "hr_bust_raven" },
  },
  steps = {
    { at = "e", script = "hr_read_note_1", once = true },
    { at = "w", script = "hr_read_note_2", once = true },
    { at = "x", script = "hr_read_gallery", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "potion", n = 3 },
    { id = "c2", at = "2", give = "ether", n = 2 },
    { id = "c3", at = "3", give = "hide_coat" },
    { id = "c4", at = "4", gold = 200 },
    { id = "c5", at = "5", give = "falchion" },
  },
  foes = {
    { id = "f1", at = "f", enc = "hr_stacks_1", sprite = "hr_mite" },
    { id = "f2", at = "q", enc = "hr_stacks_2", sprite = "hr_ink" },
    { id = "f3", at = "g", enc = "hr_stacks_3", sprite = "orderly" },
    { id = "f4", at = "k", enc = "hr_stacks_2", sprite = "hr_ink" },
    { id = "f5", at = "r", enc = "hr_stacks_1", sprite = "hr_mite" },
  },
  exits = {
    { at = "A", to = { "hr_library_1", "p", 3 } },
    { at = "D", to = { "hr_library_3", "a", 2 }, when = "hr_lec_open" },
    { at = "D", script = "hr_stair_shut_2", unless = "hr_lec_open" },
  },
})

-- The Clinic's end of the library: crates, carts, and at the middle the furnace room, with a door either side.
place("hr_library_3", {
  name = "THE CLOSED STACK", theme = "library",
  rows = {
    "######################",
    "#Aa....f..h.........2#",
    "####.####.h.hhhhhhhh.#",
    "#1...#....h.h......h.#",
    "####.#.hhhh.h..o...h.#",
    "#..g.#......+..p...+.#",
    "#.####.hhhh.h......h.#",
    "#......h..h.h......h.#",
    "#.####.h3.h.hhhhhhhh.#",
    "#.#....hh+h..........#",
    "#.#.k...............##",
    "#.#.####.##########.##",
    "#...#..............r.#",
    "#.#...##.#############",
    "#4.....#...........7.#",
    "######################",
  },
  npcs = {
    { id = "hr_inspector", at = "o", sprite = "hr_inspector", script = "hr_scene_inspector", unless = "hr_inspector_down" },
  },
  steps = {
    { at = "p", script = "hr_scene_furnace", once = true },
    { at = "7", script = "hr_read_carts", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "hipotion", n = 2 },
    { id = "c2", at = "2", give = "chainmail" },
    { id = "c3", at = "3", give = "ether", n = 2 },
    { id = "c4", at = "4", gold = 280 },
  },
  foes = {
    { id = "f1", at = "f", enc = "hr_stacks_3", sprite = "orderly" },
    { id = "f2", at = "g", enc = "hr_stacks_4", sprite = "doctor" },
    { id = "f3", at = "k", enc = "hr_stacks_2", sprite = "hr_ink" },
    { id = "f4", at = "r", enc = "hr_stacks_4", sprite = "doctor" },
  },
  exits = {
    { at = "A", to = { "hr_library_2", "x", 3 } },
  },
})

-- A pirate's capital. Tavern and Drum's house to the north, the relic dealer and the chandler to the south, and two piers: the
-- west one has an old woman on the end of it, and the east one ends at the Tide Door.
place("hr_glamouth", {
  name = "GLAMOUTH", theme = "town", savepoint = true,
  rows = {
    "##############################",
    "#hhhhhhhhhhhhh.z.hhhhhhhhhhhh#",
    "#hhhhhhhhhhhhh.a.hhhhhhhhhhhh#",
    "#..............g.............#",
    "#.hhhhh+hhhh......hhhh+hhhhh.#",
    "#.h........h......h........h.#",
    "#.h..f..1..h..w...h...o..2.h.#",
    "#.h........h......h........h.#",
    "#.hhhhhhhhhh......hhhhhhhhhh.#",
    "#.............d..............#",
    "#.hhh+hhhh..........hhhh+hhh.#",
    "#.h......h..........h......h.#",
    "#.h..r.3.h...e......h.t..4.h.#",
    "#.h......h..........h......h.#",
    "#.hhhhhhhh..........hhhhhhhh.#",
    "#............................#",
    "#~~~~~~~.~~~~~~~~~~~~.~~~~~~~#",
    "#~~~~~~~.~~~~~~~~~~~~q~~~~~~~#",
    "#~~~~~~~n~~~~~~~~~~~~T~~~~~~~#",
    "##############################",
  },
  npcs = {
    { id = "hr_gilt", at = "g", sprite = "guard", script = "hr_talk_gilt" },
    { id = "hr_fathom", at = "f", sprite = "innkeeper", script = "hr_talk_fathom" },
    { id = "hr_drum", at = "o", sprite = "captain", script = "hr_talk_drum" },
    { id = "hr_wren", at = "w", sprite = "child", script = "hr_talk_wren" },
    { id = "hr_scrimp", at = "t", sprite = "gnome", script = "hr_talk_scrimp" },
    { id = "hr_annis", at = "n", sprite = "villager", script = "hr_talk_annis" },
  },
  steps = {
    { at = "a", script = "hr_scene_glamouth", unless = "hr_at_glamouth" },
  },
  chests = {
    { id = "c1", at = "1", give = "potion", n = 3 },
    { id = "c2", at = "2", gold = 220 },
    { id = "c3", at = "3", give = "wakeroot", n = 1 },
    { id = "c4", at = "4", give = "tonic", n = 2 },
  },
  exits = {
    { at = "z", world = WORLD.glamouth },
    { at = "T", script = "hr_tide_door" },
  },
})

-- The old smugglers' exchange under the harbour. The upper level holds the two sluices, one down each side, and only when both
-- are turned does the water leave the stair. The strongroom level is on its own, reached by that stair.
place("hr_cellars", {
  name = "THE DROWNED EXCHANGE", theme = "coral",
  rows = {
    "##########################",
    "#Aa....g....h.......q...1#",
    "####.#####.hh.#####.######",
    "#2...#...#....#...#......#",
    "####.#.u.#.##.#.v.#.####.#",
    "#..f.#...#.##.#...#.#3...#",
    "#.####+###.##.##+##.######",
    "#..........##..........j.#",
    "######.########.##########",
    "#~~~~#.#~~~~~~#n#~~~~~~~~#",
    "#~~~~#4#~~~~~~#D#~~~~~~~~#",
    "##########################",
    "#b.......h........h.....5#",
    "#.hhhhh..h.hhhhh..h.hhhh.#",
    "#...k....+.h.e.h..+....w.#",
    "#.hhhhh..h.h.o.h..h.hhhh.#",
    "#U......6h.......xh......#",
    "##########################",
  },
  npcs = {
    { id = "hr_sluice_a", at = "u", sprite = "shroud", script = "hr_sluice_a" },
    { id = "hr_sluice_b", at = "v", sprite = "shroud", script = "hr_sluice_b" },
  },
  steps = {
  },
  chests = {
    { id = "c1", at = "1", gold = 260 },
    { id = "c2", at = "2", give = "hipotion", n = 2 },
    { id = "c3", at = "3", give = "ether", n = 2 },
    { id = "c4", at = "4", give = "tonic", n = 2 },
    { id = "c5", at = "5", give = "broadsword" },
    { id = "c6", at = "6", give = "stiletto" },
    { id = "c7", at = "e", gold = 120 },
  },
  steps = {
    { at = "o", script = "hr_scene_keel", when = "hr_stair_down", unless = "hr_keel_down" },
  },
  foes = {
    { id = "f1", at = "g", enc = "hr_tide_1", sprite = "hr_cutthroat" },
    { id = "f2", at = "q", enc = "hr_tide_2", sprite = "hr_crab" },
    { id = "f3", at = "f", enc = "hr_tide_3", sprite = "hr_bruiser" },
    { id = "f4", at = "j", enc = "hr_tide_1", sprite = "hr_cutthroat" },
    { id = "f5", at = "k", enc = "hr_tide_3", sprite = "hr_bruiser" },
    { id = "f6", at = "w", enc = "hr_tide_2", sprite = "hr_crab" },
  },
  exits = {
    { at = "A", script = "hr_tide_out" },
    { at = "D", script = "hr_sluice_stair" },
    { at = "U", to = { "hr_cellars", "n", 1 } },
  },
})

-- The tall grass. The walls here are grass, and it moves. In the middle of it all is a ship. Everyone who comes this way walks in
-- circles until they've climbed its mast and seen the way the grass leans.
place("hr_verdant_1", {
  name = "THE VERDANT SEA", theme = "grass",
  rows = {
    "############################",
    "#1za.....f.........#....3..#",
    "#.######.#########.#.####.##",
    "#.#....#.#.......#...#..#..#",
    "#.#.4..#.#.hhhhh.#####.##.##",
    "#.#....#.#.h...h.......#...#",
    "#.##.###.#.h.m.h.#####.#.#.#",
    "#........#.h...h.#...#.#.#.#",
    "#.######.#.hh+hh.#.2.#.#.#.#",
    "#.#....#.#.g.....#...#...#.#",
    "#.#.w..#.###.#####.###.###.#",
    "#.#....#.....#.....#...#...#",
    "#.##.#########.#####.###.###",
    "#..............t........x.y#",
    "#.....6#############.....7.#",
    "############################",
  },
  npcs = {
    { id = "hr_tully", at = "g", sprite = "villager", script = "hr_talk_tully" },
  },
  steps = {
    { at = "a", script = "hr_scene_grass", unless = "hr_in_grass" },
    { at = "m", script = "hr_scene_mast", unless = "hr_saw_line" },
    { at = "x", script = "hr_grass_turns", unless = "hr_saw_line" },
  },
  chests = {
    { id = "c1", at = "1", give = "tonic", n = 2 },
    { id = "c2", at = "2", give = "brigandine" },
    { id = "c3", at = "3", gold = 300 },
    { id = "c4", at = "4", give = "padded_coat" },
    { id = "c6", at = "6", give = "wool_habit" },
    { id = "c7", at = "7", give = "hipotion", n = 2 },
  },
  foes = {
    { id = "f1", at = "f", enc = "hr_grass_1", sprite = "hr_kite" },
    { id = "f2", at = "t", enc = "hr_grass_2", sprite = "stalker" },
    { id = "f3", at = "w", enc = "hr_grass_3", sprite = "harpy" },
  },
  exits = {
    { at = "z", script = "hr_leave_grass" },
    { at = "y", to = { "hr_verdant_2", "a", 2 } },
  },
})

-- Past the ship the grass goes over your head and stays there. A ring of old stones, a nest, a burnt place. The way on is the
-- whole south edge, and it's the last thing you find.
place("hr_verdant_2", {
  name = "THE DEEP GRASS", theme = "grass",
  rows = {
    "##########################",
    "#za....f...#......#....1.#",
    "###.#####.##.####.#.####.#",
    "#2..#...#....#..#...#....#",
    "#.###.k.#.##.#..###.#.##.#",
    "#.....s.#.##.#......#.#..#",
    "###.#...#.##.########.#.##",
    "#...#####....#.......g#..#",
    "#.#......###.#.#####.##.##",
    "#.#.####.#...#.#...#.....#",
    "#.#...3#.#.#.#.#.w.#.###.#",
    "#.######.#...#.##.##.....#",
    "#........#.#.#......t...x#",
    "#.######.#7#.#########.#.#",
    "#4......................y#",
    "##########################",
  },
  steps = {
    { at = "k", script = "hr_read_stones", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "hiether", n = 1 },
    { id = "c2", at = "2", give = "hipotion", n = 2 },
    { id = "c3", at = "3", give = "oak_staff" },
    { id = "c4", at = "4", gold = 340 },
    { id = "c7", at = "7", give = "feather", n = 1 },
  },
  foes = {
    { id = "f1", at = "f", enc = "hr_grass_2", sprite = "stalker" },
    { id = "f2", at = "s", enc = "hr_grass_4", sprite = "hr_grassback" },
    { id = "f3", at = "g", enc = "hr_grass_1", sprite = "hr_kite" },
    { id = "f4", at = "t", enc = "hr_grass_3", sprite = "harpy" },
  },
  exits = {
    { at = "z", to = { "hr_verdant_1", "y", 4 } },
    { at = "y", to = { "hr_ruin", "a", 2 } },
  },
})

-- The ruined town, grass in its streets and a bird on everything. The mill stands at the north end, and its door is taken.
place("hr_ruin", {
  name = "THE RUINED TOWN", theme = "ruin", savepoint = true,
  rows = {
    "##########################",
    "#1......#..hhMhh..#.....2#",
    "#.hh.hh.#..h.b.h..#.hh.h.#",
    "#.h..........c...........#",
    "#.h.hhhh.hhh.t.hhh.hhhh..#",
    "#...h..h.h.....h...h.w.h.#",
    "#.#.h3.h.h..p..h.4.h...h.#",
    "#.#.hh+h.hh.hhhh...hh+hh.#",
    "#.#......................#",
    "#.hhh.hhhhhh.hhhhhhh.hhh.#",
    "#.....h....f.h...g.....h.#",
    "#.###.h.hh...h.hhhhh.h.h.#",
    "#.#...h.h..6.h.h.....h...#",
    "#.#.###.hhhhhh.h.hhhhhhh.#",
    "#za......................#",
    "##########################",
  },
  npcs = {
    { id = "hr_thatch", at = "t", sprite = "villager", script = "hr_talk_thatch" },
    { id = "hr_carrion", at = "b", sprite = "harpy", script = "hr_scene_carrion", unless = "hr_carrion_down" },
  },
  steps = {
    { at = "a", script = "hr_scene_ruin", unless = "hr_at_ruin" },
    { at = "w", script = "hr_read_kitchen", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "hipotion", n = 2 },
    { id = "c2", at = "2", give = "ether", n = 3 },
    { id = "c3", at = "3", gold = 360 },
    { id = "c4", at = "4", give = "scale_vest" },
    { id = "c6", at = "6", give = "tonic", n = 3 },
  },
  foes = {
    { id = "f1", at = "f", enc = "hr_grass_3", sprite = "harpy" },
    { id = "f2", at = "g", enc = "hr_grass_1", sprite = "hr_kite" },
  },
  exits = {
    { at = "z", to = { "hr_verdant_2", "y", 4 } },
    { at = "M", to = { "hr_mill", "a", 1 }, when = "hr_carrion_down" },
    { at = "M", script = "hr_mill_shut", unless = "hr_carrion_down" },
  },
})

-- The mill is a spiral. Round the outside, in by the top, round the inside, and through the one door to the middle, past a
-- collection that has been a very long time in the making.
place("hr_mill", {
  name = "THE WINDMILL", theme = "ruin",
  rows = {
    "##################",
    "#...s.......3....#",
    "#.hhhhhhhhhhhh.h.#",
    "#.h.....1...c..h.#",
    "#.h.hhhhhhhhhh.h.#",
    "#.h.h..e.f.g.h.h.#",
    "#.h.h........h.h.#",
    "#.h.h........h.h.#",
    "#.h.h...l....h.h.#",
    "#.h.h........h.h.#",
    "#.h.hhhh+hhhhh.h.#",
    "#.h....k.......h.#",
    "#.hhhhhhhhhhhhhh.#",
    "#..q....a.....p..#",
    "########Z#########",
  },
  npcs = {
    { id = "hr_lucilda", at = "l", sprite = "villager", script = "hr_scene_lucilda" },
  },
  steps = {
    { at = "c", script = "hr_read_shelves", once = true },
    { at = "e", script = "hr_read_jar", once = true },
    { at = "f", script = "hr_read_sock", once = true },
    { at = "g", script = "hr_read_crown", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "hiether", n = 1 },
    { id = "c3", at = "3", give = "hipotion", n = 3 },
  },
  foes = {
    { id = "f1", at = "s", enc = "hr_grass_3", sprite = "harpy" },
    { id = "f2", at = "q", enc = "hr_grass_1", sprite = "hr_kite" },
    { id = "f3", at = "p", enc = "hr_grass_3", sprite = "harpy" },
    { id = "f4", at = "k", enc = "hr_grass_4", sprite = "hr_grassback" },
  },
  exits = {
    { at = "Z", to = { "hr_ruin", "c", 3 } },
  },
})

-- With every map drawn, the exits can say where they land.
for _, def in pairs(R.maps) do
  for _, exit in ipairs(def.exits or {}) do
    if exit.to then
      exit.map, exit.dir = exit.to[1], exit.to[3]
      exit.mx, exit.my = spot(exit.to[1], exit.to[2])
      exit.to = nil
    end
  end
end

-- Where each town is walked into from the overworld.
local function arrival(id, mapId, mark, dir)
  local mx, my = spot(mapId, mark)
  R.sites[id] = { mx = mx, my = my, dir = dir }
end
arrival("hayford", "hr_hayford", "a", 2)
arrival("oplinas", "hr_oplinas", "g", 1)
arrival("glamouth", "hr_glamouth", "a", 3)
arrival("windmill", "hr_verdant_1", "a", 2)

-- ---------------------------------------------------------------- who says what

local S = R.scripts

local hero, doctor, sister, scholar = line("hero"), line("deserter"), line("cleric"), line("owlin")
local lucilda = person("lucilda", "LUCILDA")

local tolliver = who("hr_tolliver", "MAYOR TOLLIVER")
local ambry = who("hr_ambry", "DEACONESS AMBRY")
local farthing = who("hr_farthing", "FARTHING")
local sheaf = who("hr_sheaf", "GOODWIFE SHEAF")
local bushel = who("hr_bushel", "MISTRESS BUSHEL")
local loam = who("hr_loam", "ADJUSTER LOAM")
local punt = who("hr_punt", "OLD PUNT")
local bogg = person("hr_bogg", "GENTLEMAN BOGG")
local skim = who("hr_skim", "SKIM")
local rush = who("hr_rush", "NOTARY RUSH")

local crue = who("hr_crue", "GATE-SERGEANT CRUE")
local ione = who("hr_ione", "SPEAKER IONE")
local tessaly = who("hr_tessaly", "KEEPER TESSALY")
local wenna = who("hr_wenna", "WENNA OAKES")
local aude = who("hr_aude", "OLD AUDE")
local sorrel = who("hr_sorrel", "EXAMINER SORREL")
local dossett = who("hr_dossett", "DOSSETT")
local hale = who("hr_hale", "MISTRESS HYTHE")
local inspector = who("hr_inspector", "THE INSPECTOR")
local vance = who("hr_vance", "READER VANCE")

local drum = who("hr_drum", "CAPTAIN DRUM")
local keel = who("hr_keel", "VESPER KEEL")
local fathom = who("hr_fathom", "FATHOM")
local wren = who("hr_wren", "WREN")
local annis = who("hr_annis", "SALT ANNIS")
local gilt = who("hr_gilt", "WATCHMAN GILT")
local scrimp = who("hr_scrimp", "SCRIMP")

local tully = who("hr_tully", "COOK TULLY")
local thatch = who("hr_thatch", "MISTER THATCH")
local carrion = who("hr_carrion", "AUNT CARRION")

-- ---------------------------------------------------------------- Hayford

S.hr_scene_hayford = {
  t("The causeway climbs out of the swamp onto an island of barley. Every fence post has a small brass slot in it. A board says WELCOME TO HAYFORD, and under it: THIS WELCOME 1 GOLD. PAY AT ANY POST."),
  { when = "hr_passes_read", steps = {
    doctor("One tithe receipt, friend, and back to that gate. Try not to pay for the welcome."),
  }, other = {
    doctor("Don't pay that. I've been reading the passes Mayor Brasscap had waiting for us at the bridge. Forged in triplicate, and beautifully: 'Two barley factors of Hayford, and a patient in their care.'"),
    sister("I'm the patient, I take it."),
    doctor("You've the face for it, sister. In Oplinas that thread would hang you, so you're a mute with a cough until we're out again."),
    { give = "hr_passes" },
    { set = "hr_passes_read" },
    ask(sister("And why a swamp? I thought the library at Oplinas was the whole point."), {
      topic("Why the library at all?", {
        doctor("Every book the Empire's people carried over the wall is in it. If anyone wrote down what this sickness is, and why it walks round you, friend, it's there."),
      }),
      { "The passes say barley. We need a receipt.", {
        doctor("Just so. The Clinic at Oplinas wants a Hayford tithe receipt with any Hayford barley. We find out who sells those."),
      } },
      { "I vote we pay for the welcome.", {
        sister("You would. Come along."),
      } },
    }),
  } },
  { set = "hr_at_hayford" },
}

S.hr_talk_ambry = {
  { when = "hr_receipt", steps = {
    { when = "hr_treaty", steps = {
      ask(ambry("The coin has come back, as I always said it would! You look as if you've something to say, factor."), {
        { "Nothing. Mammon be praised.", {
          ambry("You see? It costs nothing to believe. Well, a tenth."),
        } },
        { "It's frogs. It was always frogs.", {
          ambry("I have seen webbed prints on that spillway every morning for thirty-one years. Who do you imagine leaves the sacks unguarded? Faith is a well-run business, factor."),
        } },
      }),
    }, other = {
      ambry("Mammon keep your purse heavy, factor. That blessing was complimentary. The next is two gold."),
    } },
  }, other = {
    ambry("Welcome to the Cornucopia. I am Deaconess Ambry. All gifts return, that's the whole of the faith, and there's a leaflet, if you'd care to purchase it."),
    ask(ambry("A tithe receipt? Fifty gold into the Offertory and it's yours. Or I can write it on credit, at Mammon's usual rate."), {
      topic("What's the Offertory?", {
        ambry("The holy pool, out in the deep swamp. Four thousand gold a year goes down the spillway, and by harvest it has come back into the tills, a little damp. Nobody knows how. We call it the Miracle of Return. It stopped in the spring."),
      }),
      topic("Mammon's usual rate?", {
        ambry("Payable in this life or the next. I've known a man to die in arrears and be seen at the counter the following morning."),
      }),
      { "Here's the fifty.", {
        { paid = 50, steps = {
          ambry("Bless you. I do mean that, it's included."),
        }, other = {
          ambry("That's not fifty. Don't look stricken, I'll write it as credit. He's been very understanding this year. He's had to be."),
          { set = "hr_on_credit" },
        } },
      } },
      { "Put it on credit.", {
        ambry("How brave. Press your thumb there. No, the other thumb, he has that one on file."),
        { set = "hr_on_credit" },
      } },
    }),
    { give = "hr_receipt" },
    { set = "hr_receipt" },
    { when = "hr_on_credit", steps = {
      sister("We've just borrowed money from a god."),
      doctor("An arch devil, strictly speaking. I'm sure it will be fine."),
    } },
    doctor("That's our barley in order. North to Oplinas, friend, when you're ready."),
  } },
}

S.hr_talk_farthing = {
  { when = "hr_dividend_down", steps = {
    { when = "hr_paid_farthing", steps = {
      farthing("Mum's cross about the premiums. It's the best sound there is. You've got credit with me."),
    }, other = {
      t("The girl with the ledger isn't looking at the ledger."),
      farthing("My mum woke up. She asked who'd been at her good pans. That puts me in your debt, and I don't leave a debt on the books, so take this, or it won't balance."),
      { give = "hipotion", n = 2 },
      { set = "hr_paid_farthing" },
    } },
  }, other = {
    farthing("Conversation's a copper a sentence. That one was a free sample. That one wasn't."),
    ask(farthing("I've got gossip, directions and one password."), {
      topic("Why charge for talk?", {
        farthing("My mum's on the Adjuster's books. If the premium's paid, she stays in the good barn, with a blanket and a bowl. I do the premium. I'm nine. I'm very good."),
      }),
      topic("Password?", {
        farthing("The frogs have one, on the south road. I'll tell you for nothing that it's a warning, and it's got poultry in it."),
      }),
      { "Keep the change.", {
        farthing("There isn't any. I'd have told you."),
      } },
    }),
  } },
}

S.hr_talk_loam = {
  { when = "hr_dividend_down", steps = {
    t("The Adjuster is packing a small bag, quickly, without seeming to."),
    loam("Nine claimants on their feet and asking about their premiums. Most irregular. I sold the gentleman a count, that's all. Everyone's always so upset, and it's only ever a number."),
    sister("Let him run. Let him find out what a claim feels like, from the other side of the desk."),
  }, other = {
    loam("Adjuster Loam, of the Hayford Mutual Assurance Against Bad Dreams. For a modest premium, the Mutual guarantees bed and board should you become unable to wake."),
    ask(loam("Every claim is honoured in full, in that barn. Claimants need only present themselves, awake, and sign. So far they've been unable to attend."), {
      topic("Who's in the barn?", {
        loam("Eleven policyholders, resting. It came on this spring, a village thing. A polite gentleman with a satchel bought our list of them at a very good price. Only the number, and where they drink."),
      }),
      { "No, thank you.", {
        loam("Of course. Sleep on it. Forgive me, that's our little joke."),
      } },
    }),
  } },
}

S.hr_talk_claim = {
  { when = "hr_dividend_down", steps = {
    t("The cot has been stripped, and the sleeper's gone home. There's a black thread folded on the pillow. The sister tied it on at some point, and never said."),
  }, other = {
    t("Clean straw, a good blanket, and a bowl of well water. The eyes move back and forth under the lids, all together."),
    { when = "hr_barn_seen", steps = {}, other = {
      sister("Scythebreak. Orrenshire. Now a barn on a barley farm, with a price list on the door. And nobody here has been near a cask. Find out what these people drink."),
      { set = "hr_barn_seen" },
    } },
  } },
}

S.hr_talk_tolliver = {
  { when = "side_frogs", steps = {
    tolliver("I've had that frog to dinner. I've had to buy a second set of spoons, and I don't know whose the first set are now. Hayford thanks you. That was free. Don't tell anyone."),
  }, other = {
    { has = "hr_hat", steps = {
      t("You set the hat on the counter, with Notary Rush's treaty tucked in the band. The Mayor looks at it the way one looks at a son come home from the sea."),
      tolliver("It's damp. There's a smell of duck. Oh, you beauty."),
      t("He puts it on. Thirty years go back into his face."),
      tolliver("Licensed Collectors of the Offertory, one gold in ten to the swamp. That's a thief with a licence. Do you know what we call that in Hayford? A partner. Give me the pen."),
      { take = "hr_hat", n = 1 },
      { gold = 400 },
      t("He counts out four hundred gold, with tears in his eyes, and lets go of it one finger at a time."),
      { give = "iron_charm" },
      { set = "side_frogs" },
      { big = "THE RETURN IS RESTORED" },
      { when = "frog_wet", steps = {
        doctor("You carried a bucket for a frog in the stocks, and it's come to this. I've stopped trying to predict you."),
      } },
    }, other = {
      { when = "hr_hat_quest", steps = {
        tolliver("Have you got it? No. You're not carrying yourself like someone holding a hat. Old Punt on the east jetty will take you out."),
      }, other = {
        tolliver("Mayor Tolliver. That's a free introduction, I've a budget of one a week. You'll be looking at my head. Everyone does."),
        t("There's a band of pale skin round his scalp, where a hat has lived for thirty years."),
        ask(tolliver("A frog took it on the Orrenshire road, with eleven sacks of my barley. I've coin for whoever brings it back. Not much. Since the Return failed there's not much of anything."), {
          { "We'll look out for it.", {
            tolliver("Bless you. Old Punt takes boats out from the east jetty. There's a fee. I'd waive it, but I can't afford to."),
          } },
          { "Not our business.", {
            tolliver("No, it's nobody's business, that's what's wrong with it."),
          } },
        }),
        { set = "hr_hat_quest" },
      } },
    } },
  } },
}

S.hr_talk_punt = {
  punt("Three coppers out, and you pay coming back. Nobody's ever been in a hurry about that. I've not seen a thing since the wet year, and I've not hit a thing since the year after."),
  { when = "hr_dividend_down", steps = {
    ask(punt("Out to the Slough, is it? The frogs won't trouble a boat, and nothing else has come up under one since you went out there."), {
      { "Take us across.", {
        t("He poles out without looking, which is to say without being able to. The reeds close over."),
        warpTo("hr_swamp_1", "a", 2),
      } },
      { "Not today.", {} },
    }),
  }, other = {
    ask(punt("Out to the Slough, is it? The frogs won't trouble a boat. There's something else that's been troubling the boats."), {
      { "Take us across.", {
        t("He poles out without looking, which is to say without being able to. The reeds close over."),
        warpTo("hr_swamp_1", "a", 2),
      } },
      topic("What's troubling the boats?", {
        punt("It comes up under them, slow. It don't break them. It lifts them and sets them down, as if it was wondering."),
      }),
      { "Not today.", {} },
    }),
  } },
}

S.hr_talk_sheaf = {
  { when = "hr_dividend_down", steps = {
    sheaf("Welcome to the Paid Bed! Twenty-five gold, breathing included. We're charging by the snore again. It's the loveliest money I've ever taken."),
  }, other = {
    sheaf("Welcome to the Paid Bed! Twenty-five gold, breathing included. We used to charge by the snore, but nobody cares to be heard snoring just now."),
    sheaf("It's this or the barn, and the barn's got a waiting list."),
  } },
  ask(sheaf("You'll stay, then?"), {
    topic("Is the water safe?", {
      sheaf("It's Hayford water, love, straight from the well. It's been tasting a touch of pears this year. I've had compliments."),
      t("The doctor sets the cup down very carefully, and does not pick it up again."),
    }),
    { "A bed, please. (25 gold)", {
      { inn = 25 },
      { save = true },
    } },
    { "Not tonight.", {} },
  }),
}

S.hr_talk_bushel = {
  ask(bushel("Bushel's Sundries! I'd say make me an offer, but I've seen your shoes."), {
    { "Show me what you have.", {
      { shop = "hr_hayford" },
    } },
    { "Just looking.", {
      bushel("That's a copper. I'm mostly joking."),
    } },
  }),
}

-- ---------------------------------------------------------------- the Slough

S.hr_talk_skim = {
  skim("Halt! This is the Queen's highway. There's no queen, it just sounds better. Password."),
  ask(skim("I've got all day. I've had all day for eleven years."), {
    { "Do not tell the duck.", {
      skim("Keep your voice DOWN! Yes. Correct. Go through, and walk softly near the court."),
      { set = "hr_skim_ok" },
    } },
    topic("Is there a hint?", {
      skim("It's a warning that everyone in this swamp lives by, and it's got poultry in it. I've said too much. I've got a family."),
    }),
    { "Stand aside, frog.", {
      skim("Oh, good. I've been practising."),
      { battle = "hr_slough_1" },
      t("Skim sits down in the road and waves you through with his hat. He'd like it known that he let you win."),
      { set = "hr_skim_ok" },
    } },
    { "We'll try the north road.", {
      skim("Nobody uses the north road. That's why the things on it are so hungry."),
    } },
  }),
}

S.hr_talk_duck = {
  t("A very small frog in black holds up the Duck, as you might hold up a lamp."),
  t("The Duck looks at you. It goes on for some time. You find yourself thinking about a loaf you took from a sill, when you were six."),
  { choice = {
    { "Nod respectfully.", {
      t("The Duck turns one eye on you, and then the other. Somewhere in the swamp, a figure has been adjusted."),
    } },
    { "Say something to the Duck.", {
      t("You open your mouth. The small frog very slightly shakes its head. You close your mouth."),
    } },
  } },
}

S.hr_talk_bogg = {
  { when = "hr_treaty", steps = {
    bogg("A licensed Collector of the Offertory, tall one! I'm a respectable frog now, tall one, so I'll have to rob you more carefully."),
  }, other = {
    { when = "hr_dividend_down", steps = {
      bogg("It's dead! There was a splash this morning, out on the Offertory, and it was only a coin. It's the most beautiful thing I've ever heard."),
      rush("The Treaty of the Plank. The frogs of the Slough to be licensed as Collectors of the Offertory, for one part in ten. In return, one hat."),
      t("Gentleman Bogg takes off the hat, and gives it a small, sad brush with his sleeve."),
      bogg("Tell him it was only ever on deposit."),
      { give = "hr_hat" },
      { set = "hr_treaty" },
      t("The Duck looks at you. Then, for the first time in anyone's memory, it looks away. A frog faints."),
      { choice = {
        { "What about the plank?", {
          bogg("Ah. The Treaty's silent on the plank. It's not coming off, tall one. I've taken it up as a career."),
        } },
        { "Stay out of trouble, Bogg.", {
          bogg("I'll stay out of the stocks. It's not at all the same."),
        } },
      } },
    }, other = {
      { when = "hr_bogg_asked", steps = {
        bogg("The stair's at the south end. Mind the pool. It's got a sense of humour, and it's very slow to get to the end of it."),
      }, other = {
        t("Gentleman Bogg sits at the head of the court in a very good hat, with the plank of the Orrenshire stocks still around his neck. He has laid a napkin on the plank, and is using it as a table."),
        { when = "frog_wet", steps = {
          bogg("The tall one with the bucket! Don't get up. I can't. Owed, one favour, and Gentleman Bogg pays when he's cornered. Left boot. It's slightly warm."),
          { give = "hipotion", n = 1 },
        }, other = {
          { when = "rude_frog", steps = {
            bogg("'Dry up, you thief!' I'd know that face anywhere. Oh, don't look like that, I've told that one all over the swamp."),
          }, other = {
            bogg("Tall ones! Gentleman Bogg, redistributor. You'll forgive my not rising. I've come by a piece of civic furniture, and I can't put it down."),
          } },
        } },
        bogg("You'll be here about the hat. Let me tell you how the world works. Hayford throws its money in a pond. We go and get it. We spend it in Hayford, on barley. Two hundred years, round and round. That's their Miracle of Return. That's me, in a hat."),
        sister("Does anyone in that village know?"),
        bogg("Everyone, sister. It's only that nobody's ever been willing to pay to have it said."),
        ask(bogg("Only there's a tenant in the Offertory, Old Dividend. A snapper, big as a chapel, harmless as a hill. Then in the spring he woke up wrong."), {
          topic("Woke up wrong how?", {
            bogg("He comes up under the boats with his eyes shut, and his eyes moving, and he doesn't stop. I've lost six good collectors. Not a coin's come out of that pool since."),
            doctor("His eyes moving. Friend, I don't care for that at all."),
          }),
          { "We'll deal with Old Dividend.", {
            bogg("A prince! Clear that pool and I'll put the hat in your hand myself."),
          } },
          { "A big turtle. How hard can it be?", {
            bogg("That was the last thing Cousin Mudge said. We had it put on the bit of him we found."),
          } },
        }),
        { set = "hr_bogg_asked" },
      } },
    } },
  } },
}

S.hr_stair_shut = {
  t("A stair goes down into dark water, with a rope across it. OFFERTORY. BY ORDER OF THE COURT, ASK BOGG FIRST."),
}

S.hr_scene_offertory = {
  t("The reeds stop, and the sky comes down to the water. The Offertory is the size of a parish, black and quite still. Coins lie along the causeway in drifts, like leaves."),
  t("There's an island in the middle. Your eye passes over it, and comes back. You don't remember islands breathing."),
  doctor("Pears. Do you smell that? Breathe through your mouth, sister. Friend, you may please yourself."),
}

S.hr_read_bailiff = {
  t("A bailiff's chain on a heap of bones, with a slate tied to it. 'Came to serve notice of arrears on the tenant of this pool. Tenant declined. Tenant has accepted me.'"),
}

S.hr_scene_dividend = {
  { when = "hr_met_dividend", steps = {
    t("The great head comes round again, with its eyes shut, and the eyes moving."),
  }, other = {
    t("You're a few steps onto the island when it moves. It's a snapping turtle the size of a chapel, its shell crusted with two hundred years of green coppers. It clinks as it breathes."),
    t("Its eyes are shut. Behind the lids they go back and forth, back and forth. It's asleep. It has been asleep since the spring, and it has been walking about."),
    { set = "hr_met_dividend" },
  } },
  { battle = "hr_boss_dividend" },
  { set = "hr_dividend_down" },
  t("The shell splits along an old seam, and a fortune slides into the shallows with a long, musical sigh. Wedged in the folds of the neck is a grey cask with a Clinic stencil. Its bung has been drawn."),
  doctor("Someone sent that down the spillway with the tithe, and it's been leaking into every well in the swamp. A slow dose, in a village that counts everything. I'd lay money someone has been buying the count. I think I might be sick."),
  ask(sister("Burn it, doctor. And then we'll see who wakes."), {
    { "Do it. Then back to Bogg.", {
      t("It burns blue for a long time, and the smell of pears goes off across the water."),
    } },
    { "It wasn't the turtle's fault.", {
      sister("No. It rarely is. The Raven Queen will have made a note of that."),
    } },
  }),
}

-- ---------------------------------------------------------------- Oplinas

S.hr_scene_oplinas = {
  t("Oplinas climbs its hill in white stone and grey scaffold, a city of people who used to live somewhere better and are too polite to say so. Two flags hang over the gate, and only the Clinic's has been washed."),
  { when = "hr_receipt", steps = {
    crue("Papers. Two barley factors and a patient. Tithe paid and stamped. That's the first honest barley I've seen this month. What's wrong with the patient?"),
    t("The sister coughs, once, like a door closing in another part of the house."),
    { choice = {
      { "A wasting cough. I'd stand back.", {
        crue("I've stood closer to worse. But I'll take the advice."),
      } },
      { "She's mute. It's very restful.", {
        crue("Is it? Mine isn't."),
        t("Something happens behind the sister's eyes that you will be hearing about later."),
      } },
    } },
    crue("Prayer of any kind is an offence in Oplinas, as is any token of the old gods. There's a reward for reporting it. Go on through."),
    t("Under the arch, well past his ears, the mute with the cough finds her voice."),
    sister("Well, then. There's an almshouse in this city, and someone in it will be dying, and I'll have to walk past. Let's get on."),
    { set = "hr_through_gate" },
  }, other = {
    { when = "hr_passes_read", steps = {
      crue("Papers. Barley factors, and no tithe receipt. Get one from the Deaconess in Hayford, and then come back and let me be bored by it."),
    }, other = {
      crue("Two barley factors of Hayford, are you? Then where's your tithe receipt? No receipt, no barley."),
      t("The doctor walks you a little way back along the road."),
      doctor("Mayor Brasscap had these passes waiting for us at the bridge, friend, and they're the best forgery I've seen. I'd thought they'd be enough. We need a receipt from Hayford, in the swamps to the south. And in that city, sister, you're mute. That thread would hang you."),
      { give = "hr_passes" },
      { set = "hr_passes_read" },
    } },
    { world = WORLD.oplinas },
  } },
}

S.hr_talk_crue = {
  { when = "hr_inspector_down", steps = {
    crue("There's been some accident at the library, and every officer in the city is writing it up. I never saw anyone. It's the secret of a long career."),
  }, other = {
    crue("Move along. Eleven years, and it's a city of ten thousand wizards who've lost everything and still correct my grammar."),
  } },
}

S.hr_read_posters = {
  t("A Clinic notice room, all very clean paper. PRAYER IS A SYMPTOM. DREAMS MUST BE DECLARED. The newest has no picture. WANTED, ALIVE: A TALL PERSON OF NO DREAMS. DO NOT INJURE."),
  { when = "drew_fire", steps = {
    doctor("You did tell the Mayor you'd keep them looking at us. I'd like it noted that it's working."),
  } },
}

S.hr_read_left = {
  t("A long hall of glass cases, holding whatever people had in their hands when they crossed the wall. A soup ladle. A child's shoe. A door key, a door key, a door key. Each has a small card: This was mine. I would like to have it back, if that is possible."),
}

S.hr_talk_sorrel = {
  sorrel("Examiner Sorrel, Office of Faith. It's only a candle. When someone's been touched by a god, the flame leans, toward them or away. The literature is divided."),
  ask(sorrel("I test everyone in the end. Might I?"), {
    topic("Does it work?", {
      sorrel("Nine thousand people through this square, and it has never once leaned. We've made forty-one arrests. One mustn't let a candle have the last word."),
    }),
    topic("Go on, then. Test me.", {
      t("She holds it up to you. The flame stops flickering, and stands perfectly straight and perfectly still, like a line drawn with a rule. There's a breeze in the square. It's moving her hood."),
      sorrel("How curious. I haven't a box for that."),
      { set = "hr_candle" },
    }),
    { "Good day, Examiner.", {
      sorrel("Do take care of your patient. That's a very upright cough she has."),
    } },
  }),
}

S.hr_talk_wenna = {
  wenna("Oakes wine, from before there was a wall. Nine generations on this hill, and I'd like that written down, since nobody on the Circle will write it."),
  ask(wenna("You're welcome to a cup. Everyone's welcome. That's what's wrong with us."), {
    topic("What have you got against the refugees?", {
      wenna("Nothing. That's the worst of it. They came over that wall screaming, and we fed them. Then they got two votes for each of ours, because they're clever. You try being grateful every day for twenty-two years."),
    }),
    { "I'll take that cup.", {
      t("It's rough and strong, and it tastes of somewhere that has always been there."),
    } },
    { "We'll move on.", {} },
  }),
}

S.hr_talk_aude = {
  { when = "hr_aude_done", steps = {
    { when = "hr_tied_aude", steps = {
      t("The bed has been made. Under the pillow, where no one will look, there's a little end of black thread."),
    }, other = {
      t("The bed has been made. There's a new name on the card."),
    } },
  }, other = {
    t("A very old woman with her hair in a good plait. She is looking at the sister's left wrist, where the sleeve has ridden up by a finger's width."),
    aude("I was a Weaver's girl, in Agoshull. You needn't say anything. There's nobody left to tie mine. They'll burn me with a number on my foot, and she won't know where to find me. Isn't that silly, at my age?"),
    t("The orderly at the far end of the ward turns a page. The doctor's hand goes to the bag, and stops."),
    { choice = {
      { "Stand between her and the orderly.", {
        t("You ask the orderly something stupid about barley. It's the longest conversation of your life. When you look back, the sister's hands are folded."),
        aude("There. Oh, there you are."),
        t("Going out, the sister takes your sleeve for a moment, and lets go. She can't say anything. You find you know what it was."),
        { set = "hr_tied_aude" },
      } },
      { "Shake your head. It's too dangerous.", {
        t("The sister draws her sleeve down, and walks on along the ward. She doesn't look back. You can see what it costs, and you wish you couldn't."),
        aude("No. Of course. Go on, dear."),
      } },
    } },
    { set = "hr_aude_done" },
  } },
}

S.hr_talk_hale = {
  hale("Welcome to the Lost Property. I had four hundred rooms in Agoshull, and I'll thank you not to ask."),
  ask(hale("Thirty gold. If anyone cries out in the night, we don't write it down."), {
    { "A bed, please. (30 gold)", {
      { inn = 30 },
      { save = true },
    } },
    { "Not tonight.", {} },
  }),
}

S.hr_talk_dossett = {
  ask(dossett("Dossett, sutler to the garrison. Clinic pays late, wizards pay in lectures. You look like coin."), {
    { "Show me your stock.", {
      { shop = "hr_oplinas" },
    } },
    topic("Anything strange lately?", {
      { when = "hr_scholar", steps = {
        dossett("Someone was buying lamp wicks and paying by leaving books on my step. That's stopped. I've a shelf of good books I can't read, and I find I miss it."),
      }, other = {
        dossett("Someone buys lamp wicks and pays by leaving books on my step. Good books. I can't read them."),
      } },
    }),
    { "Nothing today.", {} },
  }),
}

S.hr_talk_ione = {
  { when = "hr_gone_south", steps = {
    ione("Go, before I'm obliged to notice you. My report says the Inspector slipped. It's the best thing I've written in years."),
  }, other = {
    { when = "hr_inspector_down", steps = {
      ione("A Clinic Inspector, dead in my library. I'll write that he slipped. They'll send another, and I'll sign what he brings me, because ten thousand people eat when I do. Don't look at me like that. I've been doing it for eleven years."),
      scholar("You signed the order, Speaker. Page four. Your hand shook."),
      ione("Yes. I'm glad somebody read it."),
      ask(ione("Nobody goes into the Verdant Sea. The grass moves. But what Lucilda sells turns up in Glamouth, through the Cutlass Crest. They say one of their ships once called at the windmill."), {
        { "We'll leave tonight.", {
          ione("South by the coast road. Don't turn your back on anyone you've paid."),
        } },
        { "Come with us, Speaker.", {
          ione("No. Someone has to stay and be hated."),
        } },
      }),
      { set = "hr_gone_south" },
      { save = true },
    }, other = {
      { when = "hr_ticket", steps = {
        ione("The Keeper has your ticket, or she ought to. And if something that isn't a mouse has been at the Inspector's carts, do not tell me."),
      }, other = {
        t("The Circle House has a hundred carved seats. At the far end, in one of them, a woman sits writing."),
        ione("The barley factors. Those are the finest forgeries I've seen in eleven years, and I've been forging my own consent on Clinic orders since the day they took the gate."),
        ask(ione("I am Speaker of the Circle. The Constellation of Lords had a thousand seats. We have forty, and we borrowed the chairs. You want the stacks."), {
          topic("What's the Clinic doing in the library?", {
            ione("Every morning a very polite man goes down to the Closed Stack with an empty cart. Every evening that chimney smokes. I signed the order. We eat because I signed."),
          }),
          topic("Who runs the Clinic here?", {
            ione("A very polite man who signs himself Inspector. That's not a name, and I've asked. He came a month ago from a mine in the west. He told me it had gone very well."),
            doctor("Orrenshire. He gave the Foreman his casks."),
          }),
          { "We need the first case files.", {
            ione("If there are any left. That's the one thing he came here to burn. The rest is kindling."),
          } },
          { "We're only here to read.", {
            ione("Nobody's only here to read. I had that carved over the door, once."),
          } },
        }),
        ione("Here's a reader's ticket. I'll say you stole it. Give it to Keeper Tessaly. She'll be unpleasant to you. It's how you'll know she's on your side."),
        { give = "hr_ticket" },
        { set = "hr_ticket" },
      } },
    } },
  } },
}

-- ---------------------------------------------------------------- the library

S.hr_scene_library = {
  t("You hadn't known there was so much to write down. The shelves go up into the dark, and old men and women in old good robes are reading as if someone might take it away."),
  { set = "hr_in_library" },
}

S.hr_talk_tessaly = {
  { set = "hr_keeper_asked" },
  { when = "hr_ticket_shown", steps = {
    ask(tessaly("Silence in the hall. Do not lick your fingers."), {
      topic("What's the rule of shelving?", {
        tessaly("It's cut into the floor at the head of the vault stair. Every first-year at the Ultimatum had it by heart."),
      }),
      { "Thank you, Keeper.", {} },
    }),
  }, other = {
    { has = "hr_ticket", steps = {
      t("She reads both sides of the ticket, and holds it up to the lamp."),
      tessaly("Good. The vault stair is in the middle of the hall. Below is the Lost Stacks, uncatalogued since they came over the wall, and under that the Closed Stack, which is the Clinic's. I suggest you read the floor."),
      { take = "hr_ticket", n = 1 },
      { set = "hr_ticket_shown" },
    }, other = {
      tessaly("Reading hall, free to all. The stacks, by ticket. Tickets are issued by the Speaker of the Circle, at the Circle House. Do lower your voice."),
      { choice = {
        { "We'll find the Speaker.", {} },
        { "We haven't said anything.", {
          tessaly("You were going to."),
        } },
      } },
    } },
  } },
}

S.hr_talk_vance = {
  { when = "hr_inspector_down", steps = {
    vance("They've stopped taking the books! So there'll be another after this one, and I've turned the page. I don't suppose you know how it ends? No, don't say."),
  }, other = {
    vance("Shh. I'd just begun this on the morning of the fall, and I picked it up on the way out of the door. I've been on page ten for twenty-two years. Once I turn it, I'll be that much nearer the end."),
    t("The page under his finger has worn pale."),
  } },
}

S.hr_read_rule = {
  t("Letters cut into the stone by a great many feet: WHAT IS KNOWN, AND THEN WHAT IS BELIEVED, AND THEN WHAT IS LOCKED AWAY. SO SHELVE, AND SO LIVE."),
}

S.hr_stair_keeper = {
  t("The vault stair goes down into the dark, past a small sign: BY TICKET ONLY. HAVE IT STAMPED AT THE DESK."),
}

S.hr_read_note_1 = {
  t("A slip of paper pinned to a shelf, in a tiny, furious hand. 'TO WHOEVER IS READING THIS. This section is being shelved. You have left the door open. Kindly leave as you found it, or preferably better.'"),
}

S.hr_read_note_2 = {
  t("Another slip. 'The insects are not mine. They eat only Ethics. You will have noticed the ink. Do not reason with the ink. It has read everything, and it has understood none of it.'"),
}

S.hr_scene_scholar = {
  t("The room has been built out of books, stacked into walls and a low careful roof, each with its shelf-mark outward. An owlin sits on a crate, very upright, reading in no light at all. A thin silver band sits between the tufts of the brow."),
  scholar("You are eleven minutes late, and you are in the wrong section. Put that down. No. Not there."),
  ask(scholar("Everything here was stolen from a man who wished to burn it. I am the thief. I am also the last reader on the rolls of the Ultimatum, which comes to the same thing nowadays. State your business."), {
    topic("What's that on your head?", {
      scholar("A circlet. We made them when we understood what was coming in, and by what door. I have slept in this one for twenty-two years, and it has a dent in it the shape of me. There isn't a spare this side of the wall."),
    }),
    topic("How did you get out of the Empire?", {
      scholar("I keep a list of what I would rather not discuss. That is item one. Item two is the spell. Please do not ask me about the spell."),
    }),
    { "We're looking for the first known case.", {
      scholar("So is the man downstairs with the furnace. You are both late."),
    } },
  }),
  t("The head turns to look at you. It goes on turning, a good way after you think it ought to stop."),
  scholar("No circlet, a yard from the worst case notes in the world, and you've not so much as twitched. What do you dream?"),
  { choice = {
    { "Nothing. I never have.", {
      scholar("Incorrect. Everyone in the literature dreams. There are eleven thousand cases on these shelves, and not one exception."),
    } },
    { "Why does everyone ask me that?", {
      scholar("Because it's the only interesting thing about you. I withdraw that. It's the only frightening thing about you."),
    } },
  } },
  { when = "hr_candle", steps = {
    sister("An Examiner held her candle up to {hero}, and the flame stood still in a breeze. Nobody's said a word about that."),
    doctor("I noticed. I've been noticing for some time."),
  } },
  scholar("You are an erratum, then. A thing in the printed record that somebody ought to have caught. I shall want to look at you properly. Not now."),
  ask(scholar("The first case: a general who came up out of the Nightmare Vault, years before Evrastin. The Inspector has been burning that file one leaf a day. The rest is in the Closed Stack, and the door wants three things pressed in order, and someone to stand guard. I had not, until today, known anyone."), {
    { "Come with us, then.", {
      scholar("Yes. That's what I was leading up to. I rehearsed it, and it went better without you."),
    } },
    topic("It's only paper.", {
      scholar("Everything I've ever loved is only paper, now. Every person I knew is a name on a card. Somebody has to bring them back to the shelf."),
    }),
  }),
  t("The scholar picks up one small bag, takes a long look at every spine, and then, for the sake of doing it, blows out a lamp that was not lit."),
  { join = "owlin", lvl = 9 },
  { set = "hr_scholar" },
}

S.hr_read_gallery = {
  t("A long swept gallery. At the south end is an iron stair-gate with a Clinic padlock the size of a loaf, and no keyhole. Three busts stand on brass collars, well apart: a hooded figure with keys, an owl, a raven."),
}

--- A bust that sinks if it's pressed in its turn, and sends the others back up if it isn't.
local function bust(intro, mine, needs, wrong)
  local right = { { set = mine }, { sfx = "door" }, t("It sinks a finger's width into its collar, and stays there.") }
  local press = right
  if needs then
    press = { { when = needs, steps = right, other = wrong } }
  end
  return {
    { when = "hr_lec_open", steps = {
      t("It has sunk into its collar, and it's done with all that now."),
    }, other = {
      t(intro),
      { choice = {
        { "Press it.", press },
        { "Leave it.", {} },
      } },
    } },
  }
end

local ALL_RISE = {
  { unset = "hr_lec_owl" }, { unset = "hr_lec_raven" },
  t("There's a soft clunk in the plinth. Along the gallery, whatever had sunk rises slowly back."),
}

S.hr_bust_owl = bust("A stone owl, its eyes worn smooth by the thumbs of first-year students.", "hr_lec_owl", nil, nil)
S.hr_bust_raven = bust("A raven in black stone, its head on one side. Some Clinic hand has chipped at the beak.", "hr_lec_raven", "hr_lec_owl", ALL_RISE)

S.hr_bust_key = {
  { when = "hr_lec_open", steps = {
    t("It has sunk into its collar, and it's done with all that now."),
  }, other = {
    t("A hooded figure in old bronze with a ring of keys, and the look of something that has always said no."),
    { choice = {
      { "Press it.", {
        { when = "hr_lec_raven", steps = {
          { sfx = "door" },
          t("It sinks. Under the floor, something heavy shifts its weight, and the padlock on the stair-gate drops open."),
          { big = "THE CLOSED STACK IS OPEN" },
          { set = "hr_lec_open" },
        }, other = ALL_RISE },
      } },
      { "Leave it.", {} },
    } },
  } },
}

S.hr_stair_shut_2 = {
  t("An iron gate across the stair. There isn't a keyhole. The chains run away under the floor, toward the three busts."),
}

S.hr_read_carts = {
  t("Six handcarts lined up square to the wall, each with a docket in a very neat hand. 'Faculty of the Mind, vols. 1 to 300. Disposed. Plague Register, A to M. Disposed.' The last says: 'Case the First. In hand.'"),
}

S.hr_scene_furnace = {
  t("Heat comes through the door before the light does. There's a brick furnace against the far wall, with the look of something that gets fed on time."),
}

S.hr_scene_inspector = {
  { when = "hr_met_inspector", steps = {
    inspector("Back again. I've made a note of the interruption. Shall we proceed?"),
  }, other = {
    t("A slight man in a spotless grey coat is feeding the furnace one leaf at a time, reading each before it goes in. He looks up, and seems pleased."),
    inspector("Ah. Orrenshire. I did wonder. Do come in. Doctor, you've cut your badge off, and you signed for those scalpels. I've been meaning to speak to you."),
    scholar("That is the last of the first-case file, and it is the property of the Ultimatum. Return it."),
    ask(inspector("I always encourage questions. It's so much easier to write them down."), {
      topic("You gave the Foreman those casks.", {
        inspector("I gave him a form, and he signed it. Forty gnomes, twelve days, a very clean curve. His filing was exemplary."),
      }),
      topic("Why burn it?", {
        inspector("Because I was asked to, by the only person I've met who is never wrong about what others can bear to know. There's a name in this file. One name, in a great many places. It has been a lot of work."),
      }),
      topic("What does Doctor Colette want with me?", {
        inspector("Clean result, one. She has asked that you arrive with all your blood. I shall do my best. It's the arms and legs I can't vouch for."),
      }),
      { "Step away from the furnace.", {
        inspector("I'm afraid that's not on the form."),
      } },
      { "You're going to answer for Orrenshire.", {
        inspector("Everyone does. That is what the forms are for."),
      } },
    }),
    t("He feeds the last leaf into the fire, closes the iron door, and takes the pen from behind his ear."),
    inspector("Now. Name? I have that. Cause of death? Let's see what we can fill in."),
    { set = "hr_met_inspector" },
  } },
  { battle = "hr_boss_inspector" },
  { set = "hr_inspector_down" },
  t("The Inspector sits down against the furnace, quite neatly, takes out a form, and begins to fill it in. The pen goes on a little way by itself, and stops."),
  doctor("It's his own. 'Cause.' He's left it blank. In eleven years I never once saw that man leave a blank."),
  scholar("It's gone. All of it. A man's whole life, reduced to a smell. However."),
  t("The scholar makes a small, private motion of the throat, and brings up a neat grey pellet onto the lid of a crate."),
  scholar("The index card. I swallowed it on the sixteenth, when he came for the catalogue. An owl keeps what it can't digest. It's the last reliable filing system in the Heart."),
  t("Unpicked and smoothed flat, it's a small card. Where a name should be there's a neat little window, cut clean through."),
  doctor("That's a surgeon's cut, and an old one. Somebody did this years ago. Long before he came."),
  scholar("'Case the First. A general, of the war for the fey gate. Went down to the Nightmare Vault. Returned with an unknown item and an unknown sickness. Did harm in his own house. Walked away.'"),
  scholar("'See also: nothic eye, a compass to the subject, living or dead. Last held, by bill of sale, by Lucilda, called the Vulture, at the windmill in the Verdant Sea.'"),
  ask(sister("A compass. So it can find where this began."), {
    topic("Why would Colette burn a sick man's file?", {
      doctor("That window was cut to fit one name. I sat in that woman's lectures for three years, and I've only ever seen her frightened of one thing, and that's being looked at."),
    }),
    { "Then we find the Vulture.", {
      scholar("We shall need to tell the Speaker. I've always wanted to be part of a procedure."),
    } },
    { "We should get out of here.", {
      scholar("Agreed. One moment. I have left a note."),
      t("It says OVERDUE. It's pinned to his coat."),
    } },
  }),
  { fade = true },
  warpTo("hr_oplinas", "k", 3),
  t("On the library steps it's evening, and the chimney isn't smoking."),
}

-- ---------------------------------------------------------------- Glamouth

S.hr_scene_glamouth = {
  t("Glamouth smells of tar, fish and other people's money. The harbour is packed with ships flying flags that belonged to someone else last week."),
  gilt("Welcome to the free Heart. No drawn steel in the street unless you've paid for it. I'm the Watch. I'm Golden Gliders by trade, but the Crest pays Thursdays."),
  t("On the post behind him: WANTED, ALIVE. A TALL PERSON OF NO DREAMS, AND ONE HERBALIST. ONE THOUSAND GOLD. THE SAME AGAIN IF DELIVERED UNBLED."),
  { when = "wore_hat", steps = {
    t("Someone has added, in pencil: IN A VERY BAD HAT."),
  } },
  doctor("Unbled. That's not a word you put on a poster by accident, friend."),
  sister("It's lovely to be somewhere nobody cares what I believe. They also don't care if you're stabbed."),
  { set = "hr_at_glamouth" },
}

S.hr_talk_gilt = {
  gilt("The Assembly meets second Tuesdays, in a tavern. Captain Drum and the Crest run the town. Big house on the north quay, with someone else's flag on it."),
}

S.hr_talk_wren = {
  { when = "hr_wren_done", steps = {
    wren("Still got all your buttons? Just checking."),
  }, other = {
    t("A small person bumps into you, says sorry, walks on, stops, comes back, and holds out your own purse."),
    wren("Keep this inside your coat. Are you the ones off the poster? Don't say. I'll give you one for free: a lady in grey gloves went up to the Captain's house the night before you got here, and came down looking paid."),
    { set = "hr_wren_done" },
  } },
}

S.hr_talk_scrimp = {
  ask(scrimp("Scrimp's Chandlery! If it's on the shelf it's for sale. If it's on your back, we'll talk."), {
    { "Show me what you've got.", {
      { shop = "hr_glamouth" },
    } },
    { "Nothing today.", {} },
  }),
}

S.hr_talk_fathom = {
  { when = "hr_gone_south", steps = {
    { when = "hr_heard_mast", steps = {
      ask(fathom("Thirty gold a bed, and nobody goes through your bags who isn't family."), {
        { "A bed, please. (30 gold)", {
          { inn = 30 },
          { save = true },
        } },
        { "Not tonight.", {} },
      }),
    }, other = {
      fathom("Windmill, is it? Quiet, now. Just one ship ever called there. The Long Haul, forty guns, up the beach on rollers with six hundred oxen and into the Verdant Sea, because old Captain Drum had a bet on with a hag."),
      scholar("The windmill is thirty miles from salt water."),
      fathom("It is. They say the grass moves, but a ship's mast doesn't. It's all in her Log, and the Log's with the Crest. Her pilot came back, too. Salt Annis, on the end of the west pier. She's not been right since."),
      { set = "hr_heard_mast" },
    } },
  }, other = {
    ask(fathom("The Drowned Parrot. Thirty gold a bed, and nobody goes through your bags who isn't family."), {
      { "A bed, please. (30 gold)", {
        { inn = 30 },
        { save = true },
      } },
      { "Not tonight.", {} },
    }),
  } },
}

S.hr_talk_annis = {
  t("An ancient woman on a bollard, facing inland, with her eyes shut. She's rocking in time with something that isn't the sea."),
  { when = "hr_keel_down", steps = {
    annis("You've got the Log. I can hear it. You can't read the grass from inside it, nobody ever could. Find my ship, and go up the mast. You'll see which way it all leans."),
  }, other = {
    annis("Hard a-port, you fools, there's a hill! Who's that? You smell of paper."),
    ask(annis("A year and a day we were out there. I'd take a bearing on the windmill, and the windmill would be somewhere else."), {
      topic("What happened to the crew?", {
        annis("Went over the side, one at a time, for a walk. You can't stop a man going for a walk. The cook wouldn't go. He said there was a dinner to get."),
      }),
      { "Rest easy, pilot.", {
        annis("I shan't. It's coming on to blow."),
      } },
    }),
  } },
}

S.hr_talk_drum = {
  { when = "hr_verdant_open", steps = {
    drum("Still alive? Good. I'd hate to have to sell you twice."),
  }, other = {
    { when = "hr_keel_down", steps = {
      t("Captain Drum looks up from her dinner, and sees the Log. Then she sees who isn't behind you. She finishes her mouthful."),
      drum("Well, now. That's a thousand gold I'll not be seeing."),
      { choice = {
        { "You sold us.", {
          drum("I took her money for the door and gave you my word on the Log, and I kept both. It's nothing personal, love. It's a port."),
        } },
        { "Give me one reason not to draw on you.", {
          drum("I can give you forty, stood behind that door with crossbows. Don't sulk. You're worth more to me now than you were this morning."),
        } },
      } },
      drum("Keep the Log. My mother went to the windmill for a bet, and came back with a look on her that never left. Tell that bird the Drums are still counting."),
      { when = "side_frogs", steps = {
        drum("I've also had a note from the Hayford swamp, advising me not to sink you. It's got a small duck drawn on it. I can't think why that bothers me."),
      } },
      { big = "THE VERDANT SEA IS OPEN" },
      { set = "hr_verdant_open" },
      { gold = 300 },
      t("She slides a small bag across the table with one finger, and doesn't look at it. It's the most frightening thing she's done yet."),
    }, other = {
      { when = "hr_drum_deal", steps = {
        drum("The Tide Door's at the end of the east pier, and you've got my word on the Log."),
      }, other = {
        { when = "hr_heard_mast", steps = {
          t("A broad woman in a good coat is eating a very small fish, slowly, with a very large knife."),
          drum("Captain Drum, of the Cutlass Crest. You've come about my mother's Log, and you're the two off the poster, and I find that delightful."),
          doctor("Herbalist."),
          ask(drum("Of course you are, love. The Log's in the strongroom of the old Exchange, and the harbour got in years back. Fetch it up, and it's yours. You've my word, and you may ask anyone what that's worth."), {
            { "We'll fetch it.", {
              drum("I knew I liked you. East pier, the Tide Door. Here's the key."),
            } },
            { "Whatever you're planning, it won't work.", {
              drum("Oh, love. It always works. That's what's so tiring. East pier. Here's the key."),
            } },
          }),
          { set = "hr_drum_deal" },
        }, other = {
          drum("That's my chair you're looking at. If you've business, take it to the Parrot first. They'll tell you whether I want to hear it."),
        } },
      } },
    } },
  } },
}

S.hr_tide_door = {
  { when = "hr_keel_down", steps = {
    t("The Tide Door is shut, and the sea has gone back in."),
  }, other = {
    { when = "hr_drum_deal", steps = {
      warpTo("hr_cellars", "a", 2),
    }, other = {
      t("A round iron door in the end of the pier, green to the top of its hinges. The lock is the only clean thing on it."),
    } },
  } },
}

S.hr_tide_out = {
  { text = "Stairs back up to the Tide Door. Go up to the harbour?", choice = {
    { "Not yet.", {} },
    { "Go up.", { warpTo("hr_glamouth", "q", 1) } },
  } },
}

-- ---------------------------------------------------------------- the Drowned Exchange

--- A sluice wheel: a dead clerk at it, and a flag for each.
local function sluice(mine, intro)
  return {
    { when = mine, steps = {
      t("The wheel's turned, and the clerk has finished his entry."),
    }, other = {
      t(intro),
      { choice = {
        { "Turn the wheel.", {
          { sfx = "door" },
          t("It fights every inch. Then something gives, a long way off, with a noise like a large animal letting out its breath."),
          { set = mine },
          { all = { "hr_sluice_1", "hr_sluice_2" }, steps = {
            { big = "THE WATER GOES DOWN" },
          } },
        } },
        { "Leave it.", {} },
      } },
    } },
  }
end

S.hr_sluice_a = sluice("hr_sluice_1", "A clerk of the old Exchange sits at an iron wheel, in what's left of a good coat. There's a very small crab living in his ledger.")
S.hr_sluice_b = sluice("hr_sluice_2", "Another wheel, and another clerk. His pen has gone on standing upright in the coral, long after the rest of him stopped.")

S.hr_sluice_stair = {
  { all = { "hr_sluice_1", "hr_sluice_2" }, steps = {
    { set = "hr_stair_down" },
    warpTo("hr_cellars", "b", 2),
  }, other = {
    t("The stair goes down into green water, and doesn't come up. Two iron pipes run off along the wall, one east and one west."),
    { when = "hr_scholar", steps = {
      scholar("Sluices, two. I don't swim, and I don't intend to find out."),
    } },
  } },
}

S.hr_scene_keel = {
  { when = "hr_met_keel", steps = {
    keel("Again, then. I bill by the hour."),
  }, other = {
    t("A strongbox stands on a coral plinth, its lid up, and it has been dusted. There's no book in it."),
    keel("It isn't in there. It's in my coat. Don't turn round too quickly, it upsets the crossbow."),
    t("A woman in grey has come out of the dark behind you, walking the way the tide comes in. She has very clean gloves."),
    keel("Vesper Keel. The Captain promised the Log to whoever could fetch it, and she promised you to me. I'd read that again, if I were you. It's very nicely drafted."),
    ask(keel("A thousand for the tall one, and a thousand more if there isn't a mark on them. Shall we say the easy way? Blood's so difficult to get out of grey."), {
      topic("Who's paying?", {
        keel("A lady doctor in Adaphis. She asked for {hero} to be delivered with a full set of blood, and she underlined that herself. I've taken strange commissions, and that's the one I've thought about."),
      }),
      { "Take your best shot.", {
        keel("I never take my best. It's so hard on the goods."),
      } },
    }),
    { set = "hr_met_keel" },
  } },
  { battle = "hr_boss_keel" },
  { set = "hr_keel_down" },
  t("Keel goes down on one knee, breathing through her teeth. She looks at the state of her gloves, and it seems to hurt her more than the rest. She drops an oilskin packet on the coral."),
  { give = "hr_log" },
  { choice = {
    { "Get out. Tell them you never found us.", {
      keel("I don't lie to clients. I'll tell them you're worth more than they're paying, and I'll send them the bill."),
      { set = "hr_keel_spared" },
    } },
    { "Stay where you are.", {
      t("She doesn't. There's a hatch behind the plinth, and a great deal of harbour under it. One splash, and then only the grey hat, turning on the water."),
    } },
  } },
  doctor("'A full set of blood.' Friend, I've been thinking about that, and I don't like any of the places it goes."),
  warpTo("hr_glamouth", "q", 1),
}

-- ---------------------------------------------------------------- the Verdant Sea

S.hr_scene_grass = {
  t("The road stops at a low stone wall, with nothing behind it but grass, to the end of the sky. It's taller than you are, and it moves in long slow swells, the other way from the wind."),
  scholar("I've read eleven accounts of the Verdant Sea, and they all end in the middle of a sentence."),
  doctor("The Log says keep the mast ahead of you. I can't see any mast, friend. Only something over there that stopped moving a moment after the rest did."),
  { set = "hr_in_grass" },
}

S.hr_leave_grass = {
  { text = "The low stone wall, and the road beyond it. Leave the grass?", choice = {
    { "Not yet.", {} },
    { "Back to the road.", { { world = WORLD.windmill } } },
  } },
}

S.hr_grass_turns = {
  t("The path runs straight and wide, and you walk for a long time. It begins to seem you've seen that broken cartwheel before. Then there's the low stone wall. You've come out exactly where you went in."),
  scholar("'You can't read the grass from inside it.' That's the pilot's hand, in the Log. How humiliating, to have to quote a mad old woman."),
  warpTo("hr_verdant_1", "a", 2),
}

S.hr_scene_mast = {
  t("The Long Haul lies on her keel in the sea of grass, forty guns and all, at a slight, jaunty angle, like someone refusing to admit they've fallen over. There are rungs up the mainmast."),
  t("You climb, and for the first time you can see. It's all leaning. Every blade, for miles, like the hair on an animal, toward one dark speck on the northern sky. You've been walking across the grain."),
  scholar("That is a windmill. I would draw attention to the fact that there isn't any wind."),
  t("Far off, on the dark speck, one sail goes slowly round."),
  { set = "hr_saw_line" },
}

S.hr_talk_tully = {
  { when = "hr_fed_tully", steps = {
    tully("Forty-one years, and never late with a dinner. Mind you tell the Captain."),
  }, other = {
    t("Beside the hull a galley stove stands on bare ground, with a fire in it. An old man in an apron is stirring a very large pot. He looks up, overjoyed."),
    tully("Is that the shore party? You're late! The lads have all gone for a walk, and the Captain said to keep it hot. Twenty-seven years, and I've not let that fire go out once."),
    ask(tully("It's a sort of a stew. There's things in that grass, and you can stew most of them. Will you try it?"), {
      { "I'd be glad to.", {
        t("It's the worst thing you have ever eaten. It's hot, and made with care, and he watches you swallow it as if he'd been waiting twenty-seven years to see that."),
        tully("That's put the colour back in you! Take some for the Captain."),
        { give = "hipotion", n = 2 },
        { heal = true },
        { set = "hr_fed_tully" },
      } },
      topic("Tully, this ship isn't going anywhere.", {
        tully("Not in this calm, she's not. It'll pick up. It always does."),
        t("He looks out across the grass for a little while, and stirs a bit faster."),
      }),
      { "We have to get on.", {
        tully("They all say that. There'll be a plate kept. There's a plate kept for all of them."),
      } },
    }),
  } },
}

S.hr_read_stones = {
  t("The grass stops at a ring of old black stones, and it doesn't lean here. Each stone is worn away at the height of a hand, as if someone came back to touch it, for a very long time."),
  sister("The first hags sat here. I can feel the threads. It's like reaching into a drain."),
}

S.hr_scene_ruin = {
  t("There was a town here. You can tell from the way the grass goes: it runs in streets. Every wall has a row of birds on it, all facing you. Over everything stands the windmill, as black as a tooth."),
  scholar("It isn't on any map. There was a name here, and someone has it now, on a shelf."),
  { set = "hr_at_ruin" },
  { save = true },
}

S.hr_talk_thatch = {
  { when = "hr_carrion_down", steps = {
    thatch("You got past Aunt Carrion! I saw it all, between the crows. I mean, I've got no eyes. They had them the first week."),
  }, other = {
    t("A scarecrow on a long pole, with a very small bird on its head. It speaks out of the side of its stitching."),
    thatch("Psst. Are they watching? Mister Thatch, the only scarecrow in Embia ever hired by the crows. The lady at the mill made me out of a dead man's coat, for a joke. The joke's that I can feel it when they land."),
    ask(thatch("A hundred and forty years up here."), {
      topic("How do we get into the mill?", {
        thatch("Past Aunt Carrion, who sits on the door. She's got one good wing, a terrible memory for faces, and a very good memory for how they taste."),
      }),
      topic("What was this town?", {
        thatch("There was a fair. Then a woman came to the mill, and asked what everyone was willing to sell. They all thought that was very funny. I expect I was one of them."),
      }),
      { "Hold on, Mister Thatch.", {
        thatch("Oh, I shall. I'm tied on."),
      } },
    }),
  } },
}

S.hr_read_kitchen = {
  t("A kitchen with most of its roof gone. The table is laid for six, with a square of old paper on each plate. Bills of sale, each signed. 'Sells to L. all his Tuesdays.' 'Sells to L. the name of her firstborn.'"),
}

S.hr_mill_shut = {
  t("The door of the mill is twenty feet high, and something is sitting in front of it."),
}

S.hr_scene_carrion = {
  { when = "hr_met_carrion", steps = {
    carrion("The meat came back. It's so obliging of it."),
  }, other = {
    t("The heap of old feathers on the mill steps unfolds, and goes on unfolding. Every bird on every wall in the town falls silent."),
    carrion("Walking meat, and it's come such a long way. Wipe your feet, says herself, and I'm to ask your business, and then I'm to eat you."),
    ask(carrion("Well, little dinners?"), {
      topic("Who's in the mill?", {
        carrion("Herself. She took me from an egg, and I've never been given a name that was mine. It's Aunt. It's what she calls all of us she's finished with."),
      }),
      { "We've come to see Lucilda.", {
        carrion("I've got the bones of everyone who has. Come and be seen."),
      } },
      { "Get off the steps, bird.", {
        carrion("It's got a mouth on it! That's the bit I'll start on."),
      } },
    }),
    { set = "hr_met_carrion" },
  } },
  { battle = "hr_boss_carrion" },
  { set = "hr_carrion_down" },
  t("She comes down the steps all at once, in a slow burst of feathers. The door of the mill swings open a little way, as if someone inside has lost interest in waiting."),
  t("The sister stoops, ties a black thread round one long grey feather, and sets it on the step. It's not in her vows, as far as you know."),
  { save = true },
}

-- ---------------------------------------------------------------- the mill

S.hr_read_shelves = {
  t("The whole inside of the mill is shelves, dusted, and everything labelled in a very fine hand. A jar of sand: the last of a beach. A child's milk teeth, in order. A letter: 'Do not open until she apologises'."),
  scholar("I would very much like to say that it disgusts me. Look at the cross-referencing."),
}

S.hr_read_jar = {
  t("A sealed jar with something moving softly inside, like breath on glass. LAUGH, ONE, GOOD. BOUGHT FROM A WIDOW IN ANTARITH."),
}

S.hr_read_sock = {
  t("On a velvet cushion, a very old sock. LEFT SOCK OF A GOD (WHICH?). GENUINE. It has been darned."),
}

S.hr_read_crown = {
  t("Two bare stands of black oak, polished, with a blank label on each. They're the only empty places in the room."),
}

S.hr_scene_lucilda = {
  { when = "hr_done", steps = {
    lucilda("Two stands, my ducks, and both still bare. Off you go. You've let the warm out."),
  }, other = {
    t("The great wheel has stopped. Something is sitting up among the gears, eating from a bowl, and watching you with its head on one side."),
    lucilda("Wipe your feet. I've had this floor since before your kingdoms."),
    lucilda("A runaway doctor, a Raven's girl, and a bookworm with its head in a tin. And what's this one? No. Don't tell me. It spoils it."),
    { when = "hr_on_credit", steps = {
      lucilda("You owe Mammon fifty gold, my duck. I can smell it. He's added to it."),
    } },
    scholar("You hold a nothic's eye. We have read the bill of sale."),
    lucilda("Then you'll know what I paid. I sold every sister I ever had for it, the whole of Thuluan, to a pretty man with a castle. Would you like to see?"),
    t("She tips the bowl. In a little cold milk lies something the size of a plum. It's wet, and it's not dead. It rolls, and steadies, and looks down and away to the north-west, through the floor."),
    lucilda("It looks at one corpse, and sees everything he ever laid eyes on. A general, dead as mutton, and still walking. Three hundred years I've had it, and for the last thirty it hasn't looked at anything else."),
    t("The eye moves. It turns in the milk, slowly, against the pull of the whole world, and it stops. It's looking at you."),
    t("Up in the rafters, nine thousand birds have stopped shifting from foot to foot. For the first time, Lucilda isn't smiling."),
    lucilda("Well, now."),
    t("She puts one long hand over the bowl. When she takes it away, the eye is staring through the floor again, and she has started smiling. You'd prefer it if she hadn't."),
    ask(lucilda("You want it, of course. And I don't give, my ducks. I collect."), {
      topic("What just happened?", {
        lucilda("Did something happen? I'm a very old woman, and my eyes aren't what they were. That one certainly isn't."),
      }),
      { "Name your price.", {
        lucilda("That's the only sensible thing anyone has said in this room in forty years."),
      } },
      { "We could just take it.", {
        lucilda("There are nine thousand birds in this roof, and they haven't eaten since Tuesday. I bought Tuesday, you know."),
      } },
    }),
    lucilda("See those two stands? I've something from every power in Embia, except two. I want a thing from the throne of Plexios, and a thing from the throne of Sindal. Not stolen. Stolen things sulk. Handed over, by the hand that sits there."),
    ask(lucilda("I've all the time I've bought, and I've bought a great deal."), {
      topic("Why thrones?", {
        lucilda("Because I sold my sisters to a throne once, and it kept its word. It was the most horrible thing I've ever seen. I'd like to own a little piece of that."),
      }),
      { "We'll bring them.", {
        lucilda("I know you will. They do come back."),
      } },
      { "And if they refuse?", {
        lucilda("Then you'll have learned what's in them."),
      } },
    }),
    doctor("Plexios is an old king who's dying, and Sindal is a vampire who won't. And beside Fabian's throne, friend, stands the person who pressed that seal."),
    { fade = true },
    { dark = true },
    t("Far to the north-east, in Adaphis, a high room. One lamp. A clerk's report: OPLINAS. INSPECTOR: NOT RETURNED. CASE THE FIRST: DESTROYED AS ORDERED."),
    t("The woman in physician's grey reads it to the end. She takes up a very small knife from beside the old book, looks at it, and sets it down."),
    t('"Good," says Doctor Colette, to no one. "Let them look. I should so like someone else to have seen it."'),
    { dark = false },
    { fade = true },
    { big = "THE ROADS NORTH ARE OPEN" },
    { set = "hr_done" },
    { world = WORLD.windmill },
  } },
}

-- ---------------------------------------------------------------- shops, foes and fights

R.shops.hr_hayford = { tier = 2 }
R.shops.hr_oplinas = { tier = 2, extra = { { item = "wakeroot", price = 50 } } }
R.shops.hr_glamouth = { tier = 2, extra = { { item = "hipotion", price = 60 }, { item = "stiletto", price = 550 }, { item = "broadsword", price = 600 } } }

R.abilities.hr_snap = { name = "SNAP", power = 125 }
R.abilities.hr_coin_spit = { name = "COIN SPRAY", power = 55, target = "all" }
R.abilities.hr_sleepwalk = { name = "SLEEP SURGE", power = 60, magic = true, target = "all", status = "sleep", chance = 35, mp = 6 }
R.abilities.hr_dividend = {
  name = "THE DIVIDEND", power = 200, target = "all", windup = 34, warn = "THE WHOLE POOL DRAWS BACK",
}
R.abilities.hr_redact = { name = "REDACT", power = 70, magic = true, status = "silence", chance = 50, mp = 4, element = "mind" }
R.abilities.hr_form = { name = "FORM 11-C", power = 60, magic = true, status = "blind", chance = 50, mp = 3 }
R.abilities.hr_ink_spit = { name = "BLOT", power = 65, magic = true, status = "blind", chance = 40, mp = 3 }
R.abilities.hr_paper_cut = { name = "PAPER CUT", power = 90 }
R.abilities.hr_furnace = {
  name = "OPEN THE FURNACE", power = 190, magic = true, target = "all", element = "fire", windup = 34, warn = "HE REACHES FOR THE IRON DOOR",
}
R.abilities.hr_page_call = { name = "RINGS FOR AN ORDERLY", target = "summon" }
R.abilities.hr_grey_shot = { name = "CROSSBOW", power = 100 }
R.abilities.hr_tide = {
  name = "SHE PULLS THE PIN", power = 140, target = "all", windup = 34, warn = "THE TIDE COMES BACK IN",
}
R.abilities.hr_pinion = { name = "PIN", power = 70, status = "blind", chance = 50 }
R.abilities.hr_scream = { name = "CARRION SCREAM", power = 45, magic = true, target = "all", status = "sleep", chance = 40, mp = 5 }
R.abilities.hr_rend = { name = "REND", power = 135 }
R.abilities.hr_flock = {
  name = "THE WHOLE FLOCK", power = 195, target = "all", windup = 34, warn = "THE SKY GOES DARK",
}
R.abilities.hr_flock_call = { name = "CALLS THE FLOCK", target = "summon" }

R.foes.hr_footpad = { name = "FROG FOOTPAD", short = "FOOTPAD", tier = 7, shape = "quick", sprite = "frogman", family = "frog",
  abilities = { { "stab", 3 }, { "tongue", 1 } } }
R.foes.hr_leech = { name = "BOG LEECH", tier = 7, shape = "small", sprite = "hr_leech", family = "bug",
  abilities = { { "gnaw", 3 }, { "retch", 1 } }, weak = { "fire" } }
R.foes.hr_snapper = { name = "TITHE SNAPPER", short = "SNAPPER", tier = 8, shape = "tank", sprite = "hr_snapper", family = "frog",
  abilities = { { "hr_snap", 3 }, { "bite", 2 } }, weak = { "ice" }, goldx = 2 }
R.foes.hr_dividend = {
  name = "OLD DIVIDEND", short = "DIVIDEND", tier = 9, sprite = "hr_dividend", family = "boss", size = 3, weak = { "bolt" }, goldx = 3,
  boss = { hpx = 0.82, phases = {
    { at = 100, moves = { { "hr_snap", 5 }, { "hr_coin_spit", 2 } }, every = 5, big = "hr_dividend" },
    { at = 60, moves = { { "hr_snap", 4 }, { "hr_coin_spit", 2 }, { "hr_sleepwalk", 2 } }, every = 4, big = "hr_dividend",
      say = "IT DOES NOT WAKE. IT WALKS", speedUp = 1, summon = "hr_leech", call = "call_help" },
  } },
}

R.foes.hr_mite = { name = "BOOK MITE", tier = 8, shape = "small", sprite = "hr_mite", family = "bug",
  abilities = { { "hr_paper_cut", 3 }, { "gnaw", 2 } }, weak = { "fire" } }
R.foes.hr_ink = { name = "SPILT INK", tier = 9, shape = "caster", sprite = "hr_ink", family = "blighted",
  abilities = { { "hr_ink_spit", 3 }, { "mind_lash", 2 }, { "stare", 1 } }, weak = { "fire", "holy" } }
R.foes.hr_orderly = { name = "STACK ORDERLY", short = "ORDERLY", tier = 9, shape = "brute", sprite = "orderly", family = "staff",
  abilities = { { "baton", 4 }, { "needle", 1 } } }
R.foes.hr_censor = { name = "CLINIC CENSOR", short = "CENSOR", tier = 10, shape = "healer", sprite = "doctor", family = "staff",
  abilities = { { "baton", 3 }, { "hr_redact", 2 }, { "suture", 2 } } }
R.foes.hr_inspector = {
  name = "THE INSPECTOR", short = "INSPECTOR", tier = 10, sprite = "hr_inspector", family = "staff", shape = "caster", weak = { "holy" },
  boss = { hpx = 0.95, phases = {
    { at = 100, moves = { { "hr_form", 4 }, { "hr_redact", 3 }, { "baton", 2 } }, every = 5, big = "hr_furnace" },
    { at = 66, moves = { { "hr_form", 3 }, { "hr_redact", 3 }, { "draught", 3 } }, every = 4, big = "hr_furnace",
      say = "HE TURNS TO A FRESH PAGE", speedUp = 1, summon = "hr_orderly", call = "hr_page_call" },
    { at = 33, moves = { { "hr_redact", 4 }, { "draught", 3 }, { "needle", 2 } }, every = 3, big = "hr_furnace",
      say = "THE COAT IS NO LONGER CLEAN", speedUp = 1, summon = "hr_orderly", call = "hr_page_call" },
  } },
}

R.foes.hr_cutthroat = { name = "CREST CUTTHROAT", short = "CUTTHROAT", tier = 10, shape = "quick", sprite = "hr_cutthroat", family = "stalker",
  abilities = { { "stab", 4 }, { "blind_dust", 1 } }, goldx = 2 }
R.foes.hr_bruiser = { name = "HIRED BRUISER", short = "BRUISER", tier = 10, shape = "brute", sprite = "hr_bruiser", family = "stalker",
  abilities = { { "baton", 3 }, { "lunge", 1 } } }
R.foes.hr_crab = { name = "REEF CRAB", tier = 10, shape = "tank", sprite = "hr_crab", family = "bug",
  abilities = { { "hr_snap", 2 }, { "claw", 3 } }, weak = { "bolt" } }
R.foes.hr_keel = {
  name = "VESPER KEEL", short = "KEEL", tier = 11, sprite = "hr_keel", family = "boss", shape = "quick", size = 1, steal = "hunters_eye",
  boss = { hpx = 0.42, atkx = 0.6, phases = {
    { at = 100, moves = { { "hr_grey_shot", 4 }, { "stab", 3 }, { "blind_dust", 2 } }, every = 5, big = "hr_tide" },
    { at = 50, moves = { { "hr_grey_shot", 5 }, { "lunge", 3 }, { "blind_dust", 2 } }, every = 3, big = "hr_tide",
      say = "SHE TAKES OFF ONE GLOVE", speedUp = 1 },
  } },
}
R.foes.hr_keel_man = {
  name = "KEEL'S MAN", tier = 11, sprite = "hr_bruiser", family = "stalker", shape = "brute", size = 1,
  boss = { hpx = 0.18, atkx = 0.5, phases = {
    { at = 100, moves = { { "baton", 4 }, { "lunge", 2 } } },
  } },
}

R.foes.hr_kite = { name = "CARRION KITE", tier = 11, shape = "small", sprite = "hr_kite", family = "harpy",
  abilities = { { "claw", 3 }, { "hr_pinion", 1 } }, weak = { "bolt" } }
R.foes.hr_stalker = { name = "GRASS STALKER", short = "STALKER", tier = 11, shape = "quick", sprite = "stalker", family = "stalker",
  abilities = { { "claw", 4 }, { "lunge", 2 } }, weak = { "fire" } }
R.foes.hr_harpy = { name = "COVEN HARPY", short = "HARPY", tier = 12, shape = "caster", sprite = "harpy", family = "harpy",
  abilities = { { "claw", 3 }, { "shriek", 2 }, { "hr_pinion", 1 } } }
R.foes.hr_grassback = { name = "GRASSBACK", tier = 12, shape = "tank", sprite = "hr_grassback", family = "stalker",
  abilities = { { "hr_snap", 3 }, { "lunge", 1 } }, weak = { "fire" } }
R.foes.hr_carrion = {
  name = "AUNT CARRION", short = "CARRION", tier = 12, sprite = "hr_carrion", family = "harpy", shape = "brute", weak = { "bolt" },
  boss = { hpx = 1, phases = {
    { at = 100, moves = { { "hr_rend", 5 }, { "hr_scream", 2 }, { "hr_pinion", 2 } }, every = 5, big = "hr_flock" },
    { at = 66, moves = { { "hr_rend", 5 }, { "hr_scream", 3 }, { "hr_pinion", 2 } }, every = 4, big = "hr_flock",
      say = "THE WALLS EMPTY", speedUp = 1, summon = "hr_kite", call = "hr_flock_call" },
    { at = 33, moves = { { "hr_rend", 6 }, { "hr_scream", 3 } }, every = 3, big = "hr_flock",
      say = "SHE HAS STOPPED BEING HUNGRY", speedUp = 1, summon = "hr_kite", call = "hr_flock_call" },
  } },
}

-- A small foe comes in threes, so that's what these lists say.
R.encounters.hr_field_1 = { foes = { "hr_leech", "hr_leech", "hr_leech" }, flee = true, bg = "swamp" }
R.encounters.hr_field_2 = { foes = { "hr_footpad", "hr_footpad" }, flee = true, bg = "grass" }
R.encounters.hr_field_3 = { foes = { "hr_snapper" }, flee = true, bg = "swamp" }
R.encounters.hr_field_4 = { foes = { "hr_cutthroat", "hr_bruiser" }, flee = true, bg = "grass" }
R.encounters.hr_field_5 = { foes = { "hr_kite", "hr_kite", "hr_kite" }, flee = true, bg = "grass" }
R.encounters.hr_field_6 = { foes = { "hr_stalker", "hr_stalker" }, flee = true, bg = "grass" }
R.encounters.hr_field_7 = { foes = { "hr_harpy", "hr_kite" }, flee = true, bg = "grass" }
R.encounters.hr_slough_1 = { foes = { "hr_footpad", "hr_footpad" }, flee = true, bg = "swamp" }
R.encounters.hr_slough_2 = { foes = { "hr_leech", "hr_leech", "hr_leech" }, flee = true, bg = "swamp" }
R.encounters.hr_slough_3 = { foes = { "hr_snapper", "hr_leech" }, flee = true, bg = "swamp" }
R.encounters.hr_boss_dividend = { foes = { "hr_dividend" }, flee = false, bg = "swamp", boss = true }
R.encounters.hr_stacks_1 = { foes = { "hr_mite", "hr_mite", "hr_mite" }, flee = true, bg = "marble" }
R.encounters.hr_stacks_2 = { foes = { "hr_ink", "hr_mite" }, flee = true, bg = "marble" }
R.encounters.hr_stacks_3 = { foes = { "hr_orderly", "hr_orderly" }, flee = true, bg = "marble" }
R.encounters.hr_stacks_4 = { foes = { "hr_censor", "hr_orderly" }, flee = true, bg = "marble" }
R.encounters.hr_boss_inspector = { foes = { "hr_inspector" }, flee = false, bg = "marble", boss = true }
R.encounters.hr_tide_1 = { foes = { "hr_cutthroat", "hr_cutthroat" }, flee = true, bg = "brine" }
R.encounters.hr_tide_2 = { foes = { "hr_crab", "hr_crab" }, flee = true, bg = "brine" }
R.encounters.hr_tide_3 = { foes = { "hr_bruiser", "hr_cutthroat" }, flee = true, bg = "brine" }
R.encounters.hr_boss_keel = { foes = { "hr_keel", "hr_keel_man", "hr_keel_man" }, flee = false, bg = "brine", boss = true }
R.encounters.hr_grass_1 = { foes = { "hr_kite", "hr_kite", "hr_kite" }, flee = true, bg = "grass" }
R.encounters.hr_grass_2 = { foes = { "hr_stalker", "hr_stalker" }, flee = true, bg = "grass" }
R.encounters.hr_grass_3 = { foes = { "hr_harpy", "hr_kite" }, flee = true, bg = "grass" }
R.encounters.hr_grass_4 = { foes = { "hr_grassback", "hr_stalker" }, flee = true, bg = "grass" }
R.encounters.hr_boss_carrion = { foes = { "hr_carrion" }, flee = false, bg = "ruin", boss = true }

R.field.heart_east = { "hr_field_1", "hr_field_2", "hr_field_3", "hr_field_4" }
R.field.verdant = { "hr_field_5", "hr_field_6", "hr_field_7" }

R.art.hr_leech = "A fat black swamp leech reared up on its tail, as long as an arm, with a round mouth of small teeth."
R.art.hr_snapper = "A low snapping turtle the size of a table, its shell crusted with green copper coins."
R.art.hr_dividend = "A snapping turtle as big as a chapel, shell grown over with two centuries of green coins, eyes shut with lumps moving under the lids, a grey cask lodged under its jaw."
R.art.hr_mite = "A pale silverfish the size of a dog, all feelers, shedding scraps of chewed page."
R.art.hr_ink = "A standing blot of black ink, roughly the shape of a person, with half-written words swimming in it."
R.art.hr_inspector = "A slight, neat man in a spotless grey coat and white half-mask, with a satchel, holding a pen as if it were a scalpel."
R.art.hr_cutthroat = "A lean pirate in a red sash with a cutlass, a scarf round the jaw, and a crest tattooed on the forearm."
R.art.hr_bruiser = "A very wide docker in a leather apron with a belaying pin, no neck, and a mild expression."
R.art.hr_crab = "A crab as high as your knee with a shell of pink coral, one claw much bigger than the other."
R.art.hr_keel = "A tall woman in a grey coat, wide grey hat and very clean grey gloves, levelling a small crossbow."
R.art.hr_kite = "A ragged black carrion bird the size of a large dog, bald red head, wings too long for its body."
R.art.hr_grassback = "Something low, wide and armoured whose back is grown over with tall living grass, so it looks like a moving hummock with a mouth at the front."
R.art.hr_carrion = "An enormous old harpy with one good wing, one broken, a necklace of small bones, and a matted grey crest, all beak and teeth."

-- ---------------------------------------------------------------- the story guide

local function goalAt(done, text, id, mark, when)
  local x, y = spot(id, mark)
  R.goals[#R.goals + 1] = { done = done, text = text, map = id, x = x, y = y, when = when }
end

local function goalSite(done, text, site, when)
  R.goals[#R.goals + 1] = { done = done, text = text, site = site, when = when }
end

goalSite("hr_at_hayford", "Reach Hayford", "hayford", "finished")
goalAt("hr_receipt", "Get a tithe receipt", "hr_hayford", "d", "hr_at_hayford")
goalSite("hr_through_gate", "Enter Oplinas", "oplinas", "hr_receipt")
goalAt("hr_keeper_asked", "Ask at the library", "hr_library_1", "v", "hr_through_gate")
goalAt("hr_ticket", "See the Speaker", "hr_oplinas", "v", "hr_keeper_asked")
goalAt("hr_ticket_shown", "Show the Keeper your ticket", "hr_library_1", "v", "hr_ticket")
goalAt("hr_scholar", "Find the book thief", "hr_library_2", "b", "hr_ticket_shown")
goalAt("hr_lec_open", "Open the Closed Stack", "hr_library_2", "m", "hr_scholar")
goalAt("hr_inspector_down", "Stop the Inspector", "hr_library_3", "p", "hr_lec_open")
goalAt("hr_gone_south", "Speak to the Speaker", "hr_oplinas", "v", "hr_inspector_down")
goalSite("hr_at_glamouth", "Go south to Glamouth", "glamouth", "hr_gone_south")
goalAt("hr_heard_mast", "Ask at the Drowned Parrot", "hr_glamouth", "f", "hr_at_glamouth")
goalAt("hr_drum_deal", "See Captain Drum", "hr_glamouth", "o", "hr_heard_mast")
goalAt("hr_keel_down", "Find the Log", "hr_cellars", "o", "hr_drum_deal")
goalAt("hr_verdant_open", "Face Captain Drum", "hr_glamouth", "o", "hr_keel_down")
goalSite("hr_in_grass", "Enter the Verdant Sea", "windmill", "hr_verdant_open")
goalAt("hr_saw_line", "Climb the grounded ship", "hr_verdant_1", "m", "hr_in_grass")
goalAt("hr_at_ruin", "Reach the ruined town", "hr_verdant_2", "y", "hr_saw_line")
goalAt("hr_carrion_down", "Get into the mill", "hr_ruin", "c", "hr_at_ruin")
goalAt("hr_done", "Climb to Lucilda", "hr_mill", "l", "hr_carrion_down")

return R
