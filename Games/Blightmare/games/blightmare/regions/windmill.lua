-- games/blightmare/regions/windmill.lua
-- Act four: both tokens in hand, back to Lucilda's mill. She sends the party to the hags of Thuluan, who she sold, and they come
-- back to find out how she keeps her word. Draft for the author to edit, in the voice of story.lua.
--
-- The site windmill stays hr_verdant_1 until Plexios is done. From px_done the tile opens wm_windmill instead, through
-- wm_windmill in R.sites below; a party that hasn't finished Sindal is turned back at the door by Harrier.
--
-- What later regions can read, all in R.exports:
--   wm_took         the player let Lucilda take the eye out of Peewit, who died. Lucilda walked north to Thuluan.
--   wm_lucilda_dead the player fought her. Peewit lives, and every bargain Lucilda held fell with her.
--   wm_peewit_lives Peewit is alive, in tune, and leading the coven and the birds (a fit for Ruin south's travel).
--   wm_owe_favor    the hero inherited Lucilda's debt to the Hag's Favor.
--   wm_mercy        the sister gave the oarsman in the Barge Cut his death.
--   wm_got_dish     the hero has Nan's pie dish (item wm_pie_dish), from Moll, for when they go back to Scythebreak.

local say = require("games.blightmare.say")
local C = require("lib.arcade.ui").C

local t, ask, topic, person, line = say.t, say.ask, say.topic, say.person, say.line

local WINDMILL = { 96, 60 }
local THULUAN = { 45, 8 }

local R = {
  id = "windmill", prefix = "wm_",
  entry = {
    flags = { "finished", "hr_done", "px_done", "sn_done", "px_token", "sn_token" },
    join = { "deserter", "cleric", "owlin" }, lvl = 18, site = "windmill",
    map = "wm_windmill", x = 13, y = 17, script = "wm_arrive",
  },
  exit = "wm_done",
  exports = { "wm_took", "wm_lucilda_dead", "wm_peewit_lives", "wm_owe_favor", "wm_mercy", "wm_got_dish" },
  sites = {
    -- Sites at one tile go by list order, and regions add to the end, so the Heart's has to step aside for this one.
    windmill = { unless = "px_done" },
    wm_windmill = { x = 96, y = 60, map = "wm_windmill", mx = 13, my = 17, dir = 1, name = "THE WINDMILL", kind = "town", when = "px_done", unless = "ruined" },
    thuluan = { mx = 13, my = 16, dir = 1 },
  },
  maps = {}, scripts = {}, shops = {}, goals = {},
  foes = {}, abilities = {}, encounters = {}, field = {},
  looks = {}, names = {}, art = {},
  items = {
    wm_casket = { name = "THE CROWNS' CASKET", key = true },
    wm_eye = { name = "THE NOTHIC EYE", key = true },
    wm_strip = { name = "STRIP OF THE ROLL", key = true },
    wm_pie_dish = { name = "NAN'S PIE DISH", key = true },
  },
}

local S, L = R.scripts, R.looks

--- Everyone with a name of their own has a look, and the name finds the look.
local function who(id, name)
  R.names[name] = id
  return person(id, name)
end

local doctor, sister, scholar = line("deserter"), line("cleric"), line("owlin")
local lucilda = line("lucilda")

-- ---------------------------------------------------------------- how people look

-- The coven: thin, ragged, and always about to leave. The town's few people have the look of those who have been pecked.
L.wm_harrier = { kind = "harpyfolk", tall = 0.92, build = "thin", cut = "tunic", coat = C.bg, trim = C.line, skin = C.line, hair = "short", hairInk = C.bg, wings = C.bg, wear = { "belt", "tags" }, carry = "keys", eyes = "narrow", mouth = "line", back = C.panel }
L.wm_peewit = { kind = "harpyfolk", tall = 0.74, build = "thin", cut = "tunic", coat = C.tie, trim = C.hi, skin = C.warn, hair = "wild", hairInk = C.redTint, wings = C.tie, hat = "bandage", hatInk = C.bg, hatTrim = C.bg, eyes = "wide", mouth = "open", back = C.hiTint }
L.wm_peewit_free = { kind = "harpyfolk", tall = 0.74, build = "thin", cut = "tunic", coat = C.tie, trim = C.hi, skin = C.warn, hair = "wild", hairInk = C.redTint, wings = C.tie, hat = "bandage", hatInk = C.red, hatTrim = C.bg, eyes = "closed", mouth = "smile", back = C.hiTint }
L.wm_moll = { kind = "human", tall = 0.88, build = "stout", cut = "dress", coat = C.bg, trim = C.text, hat = "feather", hatInk = C.bg, hatTrim = C.blue, hair = "curls", hairInk = C.text, wear = { "apron", "necklace" }, apronInk = C.line, carry = "ledger", eyes = "shifty", mouth = "smile", back = C.redTint }
L.wm_levy = { kind = "human", tall = 0.9, build = "thin", cut = "coat", coat = C.panel, trim = C.tie, hat = "bowler", hatInk = C.bg, hatTrim = C.line, hair = "short", hairInk = C.text, beard = "moustache", beardInk = C.text, wear = { "waistcoat" }, vestInk = C.tie, carry = "ledger", eyes = "tired", mouth = "line", back = C.tie }
L.wm_arle = { kind = "human", tall = 0.86, build = "normal", cut = "dress", coat = C.blueTint, trim = C.text, hat = "scarf", hatInk = C.blue, hatTrim = C.text, hair = "bun", hairInk = C.line, carry = "letter", eyes = "tired", mouth = "line", back = C.blueTint }
L.wm_hobbin = { kind = "old", tall = 0.72, build = "hunched", lean = 0.26, cut = "tunic", coat = C.text, trim = C.line, legs = C.line, skin = C.line, hat = "floppy", hatInk = C.line, hatTrim = C.text, beard = "long", beardInk = C.text, wear = { "apron" }, apronInk = C.line, carry = "pole", eyes = "tired", mouth = "line", back = C.tie }

-- The hags: three hundred years of bad weather, and each of them someone you'd cross the road from.
L.wm_rime = { kind = "hag", tall = 0.8, build = "hunched", lean = 0.1, skin = C.blueTint, coat = C.text, trim = C.blueTint, hair = "long", hairInk = C.text, hat = "crown", hatInk = C.text, hatTrim = C.blueTint, wear = { "fur", "necklace" }, carry = "cane", eyes = "narrow", mouth = "line", back = C.blueTint }
L.wm_sedge = { kind = "hag", tall = 0.84, build = "stout", skin = C.soft, coat = C.ok, trim = C.redTint, hair = "wild", hairInk = C.ok, wear = { "rags", "shawl" }, shawlInk = C.redTint, carry = "pipe", eyes = "wide", mouth = "teeth", back = C.panel }
L.wm_tallow = { kind = "hag", tall = 0.82, build = "thin", cut = "dress", skin = C.text, coat = C.line, trim = C.text, hair = "bun", hairInk = C.line, wear = { "apron" }, apronInk = C.text, carry = "ladle", eyes = "tired", mouth = "smile", back = C.bg }
L.wm_sliver = { kind = "hag", tall = 0.6, build = "thin", skin = C.ok, coat = C.redTint, trim = C.warn, hat = "pointy", hatInk = C.redTint, hatTrim = C.hi, hair = "plaits", hairInk = C.bg, wear = { "tags" }, carry = "tray", eyes = "shifty", mouth = "smile", back = C.redTint }
L.wm_bitty = { kind = "hag", tall = 0.42, build = "thin", cut = "tunic", skin = C.soft, coat = C.tie, trim = C.panel, hair = "wild", hairInk = C.bg, carry = "doll", eyes = "wide", mouth = "teeth", back = C.tie }
L.wm_fenn = { kind = "vampire", tall = 0.62, build = "broad", coat = C.bg, trim = C.red, hair = "short", hairInk = C.bg, wear = { "collar", "epaulettes" }, carry = "spear", mouth = "smile", back = C.blueTint }
L.wm_fenn_free = { kind = "vampire", tall = 0.94, build = "thin", coat = C.bg, trim = C.red, hair = "short", hairInk = C.bg, wear = { "collar", "epaulettes" }, carry = "spear", eyes = "tired", mouth = "line", back = C.hiTint }

-- Below the ice
L.wm_oarsman = { kind = "human", tall = 0.8, build = "hunched", lean = 0.2, cut = "tunic", coat = C.text, trim = C.line, skin = C.line, hair = "short", hairInk = C.tie, carry = "pole", eyes = "tired", mouth = "frown", back = C.bg }
L.wm_steward = { kind = "vampire", tall = 0.98, build = "thin", cut = "coat", coat = C.bg, trim = C.text, hair = "short", hairInk = C.line, wear = { "collar", "ribbon" }, carry = "ledger", mouth = "smile", back = C.blueTint }

-- Things that don't speak but can be looked at
L.wm_stopped_1 = { kind = "hag", tall = 0.84, lean = 0.18, skin = C.blueTint, coat = C.text, trim = C.blueTint, hair = "wild", hairInk = C.text, carry = "basket", eyes = "wide", mouth = "open" }
L.wm_stopped_2 = { kind = "hag", tall = 0.76, lean = 0.3, skin = C.blueTint, coat = C.line, trim = C.text, hair = "long", hairInk = C.text, carry = "letter", eyes = "closed", mouth = "line" }
L.wm_stopped_3 = { kind = "hag", tall = 0.8, build = "stout", lean = 0.1, skin = C.blueTint, coat = C.text, trim = C.line, hat = "pointy", hatInk = C.text, hatTrim = C.blueTint, eyes = "narrow", mouth = "teeth" }

local harrier = who("wm_harrier", "HARRIER")
local peewit = who("wm_peewit", "PEEWIT")
local moll = who("wm_moll", "MAGPIE MOLL")
local levy = who("wm_levy", "MISTER LEVY")
local arle = who("wm_arle", "GOODY ARLE")
local hobbin = who("wm_hobbin", "OLD HOBBIN")
local rime = who("wm_rime", "GRANNY RIME")
local sedge = who("wm_sedge", "AUNT SEDGE")
local tallow = who("wm_tallow", "MOTHER TALLOW")
local sliver = who("wm_sliver", "NANNY SLIVER")
local bitty = who("wm_bitty", "BITTY")
local fenn = who("wm_fenn", "CORPORAL TEAL")
local fennFree = person("wm_fenn_free", "CORPORAL TEAL")
local oarsman = who("wm_oarsman", "THE COOPER")
local steward = who("wm_steward", "THE GOOD STEWARD")

-- ---------------------------------------------------------------- what you fight

R.abilities = {
  wm_peck = { name = "PECK OUT", power = 70, status = "blind", chance = 45 },
  wm_whisper = { name = "PAID IN FULL", mp = 4, power = 40, magic = true, status = "silence", chance = 50 },
  wm_cold_word = { name = "COLD WORD", mp = 4, power = 80, magic = true, element = "ice" },
  wm_lamp_eye = { name = "GLASS STARE", mp = 3, power = 45, magic = true, status = "nightmare", chance = 45 },
  wm_smile = { name = "BE HAPPY", mp = 5, power = 25, magic = true, status = "thrall", chance = 35 },
  wm_oar = { name = "OAR STROKE", power = 105 },
  -- the Steward
  wm_pen = { name = "RED PEN", power = 100 },
  wm_form = { name = "A SMALL NOTE", mp = 4, power = 50, magic = true, status = "silence", chance = 60 },
  wm_strike_out = { name = "STRUCK OFF", mp = 6, power = 60, magic = true, status = "doom", chance = 45 },
  wm_long_count = { name = "THE LONG COUNT", power = 190, magic = true, target = "all", element = "ice", windup = 34, warn = "HE TURNS TO YOUR PAGE" },
  -- Lucilda
  wm_talon = { name = "OLD TALON", power = 110 },
  wm_have_that = { name = "I'LL HAVE THAT", mp = 5, power = 70, magic = true, status = "blind", chance = 60 },
  wm_small_print = { name = "SMALL PRINT", mp = 6, power = 60, magic = true, target = "all", status = "silence", chance = 40 },
  wm_flock = { name = "EVERY BIRD SHE OWNS", power = 200, target = "all", windup = 34, warn = "THE ROOF GOES DARK" },
  wm_call_kites = { name = "SHE WHISTLES", target = "summon" },
  -- Harrier
  wm_rake = { name = "RAKE", power = 115 },
  wm_stoop = { name = "STOOP", power = 240, windup = 34, warn = "SHE CLIMBS OUT OF SIGHT" },
  wm_harrow = { name = "HARROW", power = 55, target = "all", status = "blind", chance = 35 },
}

R.foes = {
  -- the mill
  wm_kite = { name = "CARRION KITE", tier = 19, shape = "small", sprite = "hr_kite", family = "harpy", abilities = { { "bite", 3 }, { "wm_peck", 1 } }, weak = { "bolt" } },
  wm_coven = { name = "COVEN HARPY", tier = 20, shape = "quick", sprite = "harpy", family = "harpy", abilities = { { "claw", 3 }, { "shriek", 1 } } },
  wm_exhibit = { name = "LOOSE EXHIBIT", tier = 19, shape = "brute", sprite = "wm_exhibit", family = "stalker", abilities = { { "lunge", 1 }, { "claw", 3 } }, weak = { "fire" } },
  wm_jar = { name = "TALKING JAR", tier = 19, shape = "caster", sprite = "wm_jar", family = "bug", abilities = { { "wm_whisper", 3 }, { "wm_lamp_eye", 2 } }, weak = { "bolt" } },
  -- Thuluan
  wm_eel = { name = "BLACK ICE EEL", tier = 19, shape = "quick", sprite = "wm_eel", family = "stalker", abilities = { { "bite", 3 }, { "spit", 1 } }, weak = { "bolt" }, resist = { "ice" } },
  wm_reedman = { name = "REED MAN", tier = 19, shape = "brute", sprite = "wm_reedman", family = "staff", abilities = { { "claw", 3 }, { "needle", 1 } }, weak = { "fire" }, resist = { "ice" } },
  wm_stopped = { name = "STOPPED HAG", tier = 20, shape = "caster", sprite = "wm_stopped", family = "blighted", abilities = { { "wm_cold_word", 3 }, { "hush_word", 1 } }, weak = { "fire" }, resist = { "ice" } },
  -- the Sump
  wm_stitcher = { name = "OLD STITCHER", tier = 20, shape = "tank", sprite = "wm_stitcher", family = "staff", abilities = { { "stab", 3 }, { "lunge", 1 } }, weak = { "holy", "fire" } },
  wm_thrall = { name = "SMILING ROWER", tier = 19, shape = "small", sprite = "wm_thrall", family = "blighted", abilities = { { "wm_oar", 3 }, { "wm_smile", 1 } }, weak = { "holy" } },
  wm_salt = { name = "SALT CRAWLER", tier = 20, shape = "small", sprite = "crawler", family = "bug", abilities = { { "bite", 3 }, { "retch", 1 } }, resist = { "ice" } },
  wm_tally = { name = "TALLY CLERK", tier = 20, shape = "healer", sprite = "wm_tally", family = "staff", abilities = { { "baton", 2 }, { "field_surgery", 1 }, { "wm_smile", 1 } }, weak = { "holy", "fire" } },
  -- bosses
  wm_boss_steward = {
    name = "THE GOOD STEWARD", short = "STEWARD", tier = 20, sprite = "wm_steward", family = "boss", weak = { "fire", "holy" }, resist = { "ice" },
    boss = { hpx = 1.0, phases = {
      { at = 100, moves = { { "wm_pen", 5 }, { "wm_form", 2 } }, every = 5, big = "wm_long_count" },
      { at = 66, moves = { { "wm_pen", 4 }, { "wm_form", 2 }, { "wm_strike_out", 2 } }, every = 4, big = "wm_long_count", say = "HE CORRECTS AN ERROR", summon = "wm_tally" },
      { at = 33, moves = { { "wm_pen", 5 }, { "wm_strike_out", 3 } }, every = 3, big = "wm_long_count", say = "HE STOPS SMILING", speedUp = 1 },
    } },
  },
  wm_boss_lucilda = {
    name = "LUCILDA", tier = 22, sprite = "wm_lucilda", family = "boss", weak = { "fire" },
    boss = { hpx = 1.0, phases = {
      { at = 100, moves = { { "wm_talon", 5 }, { "wm_have_that", 2 } }, every = 5, big = "wm_flock" },
      { at = 66, moves = { { "wm_talon", 4 }, { "wm_have_that", 2 }, { "wm_small_print", 2 } }, every = 4, big = "wm_flock", say = "THE BIRDS COME IN", summon = "wm_kite", call = "wm_call_kites" },
      { at = 33, moves = { { "wm_talon", 5 }, { "wm_small_print", 3 } }, every = 3, big = "wm_flock", say = "SHE IS VERY OLD, AND VERY ANGRY", speedUp = 1, summon = "wm_kite", call = "wm_call_kites" },
    } },
  },
  -- her name said aloud: no birds, no magic to speak of, and a good deal less of her
  wm_boss_named = {
    name = "LUCILDA, NAMED", short = "LUCILDA", tier = 22, sprite = "wm_lucilda", family = "boss", weak = { "fire" },
    boss = { hpx = 0.6, phases = {
      { at = 100, moves = { { "wm_talon", 1 } }, every = 6, big = "wm_flock" },
      { at = 40, moves = { { "wm_talon", 4 }, { "wm_have_that", 1 } }, every = 5, big = "wm_flock", say = "SHE STILL HAS HER CLAWS" },
    } },
  },
  wm_boss_harrier = {
    name = "HARRIER", tier = 21, sprite = "wm_harrier", family = "harpy", weak = { "bolt" },
    boss = { hpx = 0.8, phases = {
      { at = 100, moves = { { "wm_rake", 5 }, { "wm_harrow", 2 } }, every = 5, big = "wm_stoop" },
      { at = 50, moves = { { "wm_rake", 5 }, { "wm_harrow", 3 } }, every = 3, big = "wm_stoop", say = "SHE ISN'T DONE", speedUp = 2 },
    } },
  },
}

R.encounters = {
  wm_mill_1 = { foes = { "wm_exhibit" }, flee = true, bg = "ruin" },
  wm_mill_2 = { foes = { "wm_jar", "wm_jar" }, flee = true, bg = "ruin" },
  wm_mill_3 = { foes = { "wm_exhibit", "wm_jar" }, flee = true, bg = "ruin" },
  wm_mill_4 = { foes = { "wm_coven", "wm_kite", "wm_kite" }, flee = true, bg = "ruin" },
  wm_ice_1 = { foes = { "wm_eel", "wm_eel" }, flee = true, bg = "snow" },
  wm_ice_2 = { foes = { "wm_reedman", "wm_eel" }, flee = true, bg = "snow" },
  wm_ice_3 = { foes = { "wm_stopped", "wm_reedman" }, flee = true, bg = "snow" },
  wm_sump_1 = { foes = { "wm_stitcher" }, flee = true, bg = "brine" },
  wm_sump_2 = { foes = { "wm_thrall", "wm_thrall", "wm_thrall" }, flee = true, bg = "brine" },
  wm_sump_3 = { foes = { "wm_stitcher", "wm_thrall" }, flee = true, bg = "brine" },
  wm_sump_4 = { foes = { "wm_salt", "wm_salt", "wm_tally" }, flee = true, bg = "brine" },
  wm_door_guard = { foes = { "wm_stitcher", "wm_stitcher" }, flee = false, bg = "brine" },
  wm_roll_1 = { foes = { "wm_stitcher", "wm_tally" }, flee = true, bg = "ruin" },
  wm_field_1 = { foes = { "wm_eel", "wm_eel" }, flee = true, bg = "snow" },
  wm_field_2 = { foes = { "wm_reedman" }, flee = true, bg = "snow" },
  wm_field_3 = { foes = { "wm_reedman", "wm_eel" }, flee = true, bg = "snow" },
  wm_fight_steward = { foes = { "wm_boss_steward" }, flee = false, bg = "ruin", boss = true },
  wm_fight_lucilda = { foes = { "wm_boss_lucilda" }, flee = false, bg = "ruin", boss = true },
  wm_fight_named = { foes = { "wm_boss_named" }, flee = false, bg = "ruin", boss = true },
  wm_fight_harrier = { foes = { "wm_boss_harrier" }, flee = false, bg = "ruin", boss = true },
}

R.field = { thuluan = { "wm_field_1", "wm_field_2", "wm_field_3" } }

R.art = {
  wm_exhibit = "A taxidermy beast stitched from several animals that never met, with glass eyes and a brass label wired to one ear, walking.",
  wm_jar = "A glass bell jar on three brass legs, with a pale something inside mouthing words against the glass.",
  wm_eel = "A long black eel rearing out of a hole in the ice, its body rimed white, mouth a round ring of teeth.",
  wm_reedman = "A tall scarecrow of frozen reeds bound with hag-knots, with a cracked mask of ice for a face.",
  wm_stopped = "A hag cased to the shoulders in blue ice, one arm out, walking very slowly with her mouth still moving.",
  wm_stitcher = "A frost-furred vampire soldier in a long quilted coat with a very long thrusting spear, and a perfect smile.",
  wm_thrall = "A thin rower in a grey smock with an oar frozen to both hands, eyes shut, smiling.",
  wm_tally = "A narrow vampire clerk with a ledger held open like a shield and a pen as long as a sword.",
  wm_steward = "A thin vampire in a beautifully kept black coat, frost on his shoulders, a huge open ledger and a red pen, smiling.",
  wm_lucilda = "A very old hag who is half a vulture, wings like torn sacking, hunched on a beam, a claw held out as if to take something from you.",
  wm_harrier = "A lean black harpy, wings tight, one foot clutching a small patch of cloth.",
  -- things on the maps that aren't people
  wm_case = "A glass display case on a dark wooden stand, with a small card on the front.",
  wm_wheel = "A chest-high iron sluice wheel, furred with white salt.",
  wm_grille = "A bronze grille filling a passage, with a wide bronze smiling mouth set into it.",
  wm_lockgate = "A black iron lock gate, dripping, with a band of salt where the water stands.",
  wm_board = "A clerk's board or lectern with a book chained to it.",
  wm_drum = "A great iron drum on an axle, wound thick with pale skin, smoking with cold.",
}

R.shops = {
  wm_moll = { tier = 4, extra = { { item = "feather", price = 200 } } },
  wm_sliver = { tier = 4, extra = { { item = "wakeroot", price = 40 }, { item = "tent", price = 300 } } },
}

-- ---------------------------------------------------------------- the town and the mill

R.maps.wm_windmill = {
  name = "THE RUINED TOWN", theme = "ruin", savepoint = true,
  rows = {
    "#########################",
    "##########hh>hh##########",
    "##########h...h##########",
    "#.....hhhhh...hhhhhhh...#",
    "#.....h.............h...#",
    "#.....+.............+...#",
    "#.....h.............h...#",
    "#hh+hhh...hh.hh.....hh+h#",
    "#.....h...h...h.....h...#",
    "#.....h...hh.hh.....h...#",
    "#.....h.............h...#",
    "#.....+.............+...#",
    "#.....h.............h...#",
    "#hhhhhh.............hhhh#",
    "######h...........h######",
    "######h...........h######",
    "#########.......#########",
    "#########hhh.hhh#########",
    "#########################",
  },
  npcs = {
    { id = "wm_harrier", x = 13, y = 5, script = "wm_talk_harrier", unless = "wm_took" },
    { id = "wm_peewit", x = 13, y = 9, script = "wm_talk_peewit", unless = "wm_answer" },
    { id = "wm_peewit_free", x = 13, y = 9, script = "wm_talk_peewit_free", when = "wm_peewit_lives" },
    { id = "wm_moll", x = 3, y = 5, script = "wm_talk_moll" },
    { id = "wm_levy", x = 17, y = 12, script = "wm_talk_levy" },
    { id = "wm_arle", x = 23, y = 10, script = "wm_talk_arle", unless = "wm_arle_left" },
  },
  steps = {
    { x = 13, y = 17, script = "wm_arrive", unless = "wm_arrived" },
    { x = 13, y = 14, script = "wm_coming_back", when = "wm_answer", unless = "wm_saw_birds" },
  },
  chests = {
    { id = "c1", x = 23, y = 5, give = "hipotion", n = 3 },
    { id = "c2", x = 3, y = 12, give = "ether", n = 3 },
    { id = "c3", x = 13, y = 16, gold = 400 },
  },
  exits = {
    { x = 13, y = 2, map = "wm_mill_1", mx = 8, my = 13, dir = 1 },
    { x = 13, y = 18, world = WINDMILL },
  },
}

-- A round floor round a round stone. Old Hobbin walks it.
R.maps.wm_mill_1 = {
  name = "THE MILL: GRINDING FLOOR", theme = "ruin",
  rows = {
    "###############",
    "#####h.>.h#####",
    "###hh.....hh###",
    "##h.........h##",
    "##h...hhh...h##",
    "#h...h###h...h#",
    "#h...h###h...h#",
    "#h...h###h...h#",
    "##h...hhh...h##",
    "##h.........h##",
    "###hh.....hh###",
    "#####h...h#####",
    "######h.h######",
    "#######.#######",
    "###############",
  },
  npcs = {
    { id = "wm_hobbin", x = 5, y = 7, script = "wm_talk_hobbin" },
  },
  chests = {
    { id = "c1", x = 12, y = 7, give = "tonic", n = 3 },
  },
  exits = {
    { x = 8, y = 2, map = "wm_mill_2", mx = 11, my = 13, dir = 1 },
    { x = 8, y = 14, map = "wm_windmill", mx = 13, my = 3, dir = 3 },
  },
}

-- The Collection. The straight way up is walled, so everyone sees it on the way round: two wings, a ring gallery and the landing.
R.maps.wm_mill_2 = {
  name = "THE MILL: THE COLLECTION", theme = "library",
  rows = {
    "#####################",
    "#hhhhhhhhh>hhhhhhhhh#",
    "#h.....h.....h.....h#",
    "#h.....+.....+.....h#",
    "#h.....h.....h.....h#",
    "#hh+hhhhhhhhhhhhh+hh#",
    "#h.................h#",
    "#h.hhhhhhh.hhhhhhh.h#",
    "#h.h.....h.h.....h.h#",
    "#h.h.....+.+.....h.h#",
    "#h.h.....h.h.....h.h#",
    "#h.hhhhhhh.hhhhhhh.h#",
    "#h.................h#",
    "#hhhhhhhhh>hhhhhhhhh#",
    "#####################",
  },
  npcs = {
    { id = "wm_case_jars", x = 7, y = 3, sprite = "wm_case", script = "wm_case_jars" },
    { id = "wm_case_masks", x = 3, y = 5, sprite = "wm_case", script = "wm_case_masks" },
    { id = "wm_case_stand", x = 17, y = 4, sprite = "wm_case", script = "wm_case_stand" },
    { id = "wm_case_letter", x = 19, y = 3, sprite = "wm_case", script = "wm_case_letter" },
  },
  steps = {
    { x = 11, y = 3, script = "wm_harrier_fight", when = "wm_took", unless = "wm_harrier_down" },
    { x = 11, y = 3, script = "wm_drawer", once = true, unless = "wm_took" },
  },
  chests = {
    { id = "c1", x = 5, y = 10, give = "hiether", n = 1 },
    { id = "c2", x = 17, y = 10, give = "swift_band" },
    { id = "c3", x = 19, y = 5, give = "hipotion", n = 2 },
  },
  foes = {
    { id = "f1", x = 3, y = 10, enc = "wm_mill_1", sprite = "wm_exhibit" },
    { id = "f2", x = 8, y = 7, enc = "wm_mill_2", sprite = "wm_jar" },
    { id = "f3", x = 16, y = 13, enc = "wm_mill_3", sprite = "wm_exhibit" },
    { id = "f4", x = 19, y = 9, enc = "wm_mill_2", sprite = "wm_jar" },
    { id = "f5", x = 5, y = 4, enc = "wm_mill_4", sprite = "harpy" },
    { id = "f6", x = 15, y = 3, enc = "wm_mill_3", sprite = "wm_exhibit" },
    { id = "f7", x = 7, y = 9, enc = "wm_mill_4", sprite = "harpy" },
  },
  exits = {
    { x = 11, y = 2, map = "wm_mill_3", mx = 8, my = 11, dir = 1 },
    { x = 11, y = 14, map = "wm_mill_1", mx = 8, my = 3, dir = 3 },
  },
}

-- The cap has lost its floor. A single beam runs out over the drop to the great shaft, and she sits at the end of it.
R.maps.wm_mill_3 = {
  name = "THE MILL: THE CAP", theme = "ruin",
  rows = {
    "###############",
    "#####hhhhh#####",
    "###hh.....hh###",
    "##h.........h##",
    "##h..~~~~~..h##",
    "#h..~~~.~~~..h#",
    "#h..~~~.~~~..h#",
    "#h..~~~.~~~..h#",
    "#h..~~~.~~~..h#",
    "##h.~~~.~~~.h##",
    "##h.........h##",
    "###hh..>..hh###",
    "#####hhhhh#####",
    "###############",
    "###############",
  },
  npcs = {
    { id = "lucilda", x = 8, y = 6, script = "wm_lucilda", unless = "wm_gone" },
  },
  chests = {
    { id = "c1", x = 8, y = 3, give = "hiether", n = 2 },
    { id = "c2", x = 3, y = 7, give = "cantor_ring" },
  },
  exits = {
    { x = 8, y = 12, map = "wm_mill_2", mx = 11, my = 3, dir = 3 },
  },
}

-- ---------------------------------------------------------------- Thuluan

-- Houses on stilts, sunk to the sills in black ice. The Moot's hall at the top, the road in at the bottom, and the way out onto
-- the ice through the last house, at the east.
R.maps.wm_thuluan = {
  name = "THULUAN", theme = "swamp", savepoint = true,
  rows = {
    "#########################",
    "#.....h...hhhhh...h.....#",
    "#.....h...h...h...h.....#",
    "#.....+...h...h...+.....#",
    "#.....h...h...h...h.....#",
    "#hhhhhh...hh+hh...hhhhhh#",
    "#.......................#",
    "#~~~....~~~...~~~....~~~#",
    "#~~~....~~~...~~~....~~~#",
    "#.......................#",
    "#hhhh+hh.........hh+hhhh#",
    "#......h.........h......#",
    "#......h.........h......#",
    "#hhhhhhh.........hhhhhhh#",
    "###########...###########",
    "###########...###########",
    "###########...###########",
    "#########################",
  },
  npcs = {
    { id = "wm_rime", x = 13, y = 3, script = "wm_moot" },
    { id = "wm_sedge", x = 13, y = 9, script = "wm_talk_sedge" },
    { id = "wm_tallow", x = 4, y = 12, script = "wm_talk_tallow" },
    { id = "wm_sliver", x = 3, y = 3, script = "wm_talk_sliver" },
    { id = "wm_bitty", x = 22, y = 13, script = "wm_talk_bitty" },
    { id = "wm_fenn", x = 12, y = 15, script = "wm_talk_fenn", unless = "wm_burned" },
    { id = "wm_fenn_free", x = 12, y = 15, script = "wm_talk_fenn_free", when = "wm_burned" },
  },
  steps = {
    { x = 13, y = 16, script = "wm_thuluan_first", unless = "wm_saw_ice" },
    { x = 24, y = 3, script = "wm_ice_shut", unless = "wm_moot" },
    { x = 24, y = 3, script = "wm_ice_gone", when = "wm_burned" },
  },
  chests = {
    { id = "c1", x = 23, y = 5, give = "wakeroot", n = 2 },
    { id = "c2", x = 2, y = 13, give = "frost_ward" },
  },
  exits = {
    { x = 24, y = 3, map = "wm_ice_1", mx = 2, my = 2, dir = 3, when = "wm_moot", unless = "wm_burned" },
    { x = 13, y = 17, world = THULUAN },
  },
}

-- Two ways round the holes, a pocket in the south-west, and the Line of the Stopped: those who tried to walk out.
R.maps.wm_ice_1 = {
  name = "THE BLACK ICE", theme = "swamp",
  rows = {
    "#>######################",
    "#......~~~~~~......~~~~#",
    "#.~~~~.~~~~~~.~~~~.~~~~#",
    "#.~~~~.~~~~~~.~~~~.....#",
    "#.~~~~........~~~~~~~~.#",
    "#.~~~~~~~~~~~~~~~~~~~~.#",
    "#...........~~~~.......#",
    "#.~~~~~~~~~.~~~~.~~~~~~#",
    "#.......~~~.......~~~~~#",
    "#.~~~~~.~~~~~~~~~.~~~~~#",
    "#.~~~~~.......~~~.....~#",
    "#.~~~~~~~~~~~.~~~~~~~.~#",
    "#.............~~~~~~~.~#",
    "#~~~~~~~~~~~~~~~~~~~~.~#",
    "#~~~~~~~~~~~~~~~~~~~..~#",
    "#~~~~~~~~~~~~~~~~~~~>.~#",
    "########################",
  },
  npcs = {
    { id = "wm_stopped_1", x = 16, y = 2, script = "wm_stopped_1" },
    { id = "wm_stopped_2", x = 8, y = 13, script = "wm_stopped_2" },
    { id = "wm_stopped_3", x = 20, y = 7, script = "wm_stopped_3" },
  },
  chests = {
    { id = "c1", x = 14, y = 12, give = "hipotion", n = 2 },
    { id = "c2", x = 2, y = 13, gold = 600 },
    { id = "c3", x = 23, y = 4, give = "ether", n = 2 },
  },
  foes = {
    { id = "f1", x = 10, y = 5, enc = "wm_ice_1", sprite = "wm_eel" },
    { id = "f2", x = 8, y = 7, enc = "wm_ice_2", sprite = "wm_reedman" },
    { id = "f3", x = 14, y = 9, enc = "wm_ice_3", sprite = "wm_stopped" },
    { id = "f4", x = 5, y = 9, enc = "wm_ice_1", sprite = "wm_eel" },
    { id = "f5", x = 20, y = 11, enc = "wm_ice_2", sprite = "wm_reedman" },
    { id = "f6", x = 11, y = 11, enc = "wm_ice_3", sprite = "wm_stopped" },
  },
  exits = {
    { x = 2, y = 1, map = "wm_thuluan", mx = 23, my = 3, dir = 4 },
    { x = 21, y = 16, map = "wm_sump_1", mx = 3, my = 2, dir = 2 },
  },
}

-- The stair Sindal's engineers cut down through the swamp's floor. Long galleries, doubling back, and a talking door at the end.
R.maps.wm_sump_1 = {
  name = "THE SUMP: THE COLD STAIR", theme = "cave",
  rows = {
    "#####################",
    "#>..................#",
    "###.##############.##",
    "#.....#............##",
    "#.....#.#############",
    "#######.............#",
    "###################.#",
    "#...................#",
    "#.###########.#####.#",
    "#.#.........#.#.....#",
    "#.#.#######.#.#.#####",
    "#...#>......#...#####",
    "#####################",
    "#####################",
    "#####################",
  },
  npcs = {
    { id = "wm_grille", x = 8, y = 12, sprite = "wm_grille", script = "wm_grille", unless = "wm_door_open" },
    { id = "wm_notice", x = 3, y = 4, sprite = "wm_board", script = "wm_notice" },
  },
  chests = {
    { id = "c1", x = 6, y = 5, give = "hipotion", n = 2 },
    { id = "c2", x = 16, y = 12, give = "fire_ward" },
    { id = "c3", x = 2, y = 5, gold = 500 },
  },
  foes = {
    { id = "f1", x = 12, y = 4, enc = "wm_sump_1", sprite = "wm_stitcher" },
    { id = "f2", x = 14, y = 6, enc = "wm_sump_2", sprite = "wm_thrall" },
    { id = "f3", x = 10, y = 8, enc = "wm_sump_4", sprite = "crawler" },
    { id = "f4", x = 2, y = 10, enc = "wm_sump_1", sprite = "wm_stitcher" },
    { id = "f5", x = 8, y = 10, enc = "wm_sump_3", sprite = "wm_thrall" },
    { id = "f6", x = 18, y = 10, enc = "wm_sump_4", sprite = "crawler" },
  },
  exits = {
    { x = 2, y = 2, map = "wm_ice_1", mx = 22, my = 16, dir = 1 },
    { x = 6, y = 12, map = "wm_sump_2", mx = 3, my = 2, dir = 2 },
  },
}

-- The north quay and its two wheel rooms, the canal you can see across but not cross, and the south quay, walked back west to
-- the lock. Both wheels have to be turned before the lock drains.
R.maps.wm_sump_2 = {
  name = "THE SUMP: THE BARGE CUT", theme = "cave",
  rows = {
    "##########################",
    "#>.......................#",
    "#........................#",
    "#hhhhh+hhhhhhhhhh+hhhhh..#",
    "#..........h..........h..#",
    "#..........h..........h..#",
    "#hhhhhhhhhhhhhhhhhhhhhh..#",
    "#~~~~~~~~~~~~~~~~~~~~~~..#",
    "#~~~~~~~~~~~~~~~~~~~~~~..#",
    "#~~~~~~~~~~~~~~~~~~~~~~..#",
    "#~~~~~~~~~~~~~~~~~~~~~~..#",
    "#....h...................#",
    "#........................#",
    "#>...h...................#",
    "##########################",
  },
  npcs = {
    { id = "wm_wheel_a", x = 5, y = 6, sprite = "wm_wheel", script = "wm_wheel_a", unless = "wm_wheel_a" },
    { id = "wm_wheel_b", x = 20, y = 5, sprite = "wm_wheel", script = "wm_wheel_b", unless = "wm_wheel_b" },
    { id = "wm_manifest", x = 20, y = 14, sprite = "wm_board", script = "wm_manifest" },
    { id = "wm_oarsman", x = 14, y = 12, script = "wm_talk_oarsman", unless = "wm_mercy" },
    { id = "wm_lock", x = 6, y = 13, sprite = "wm_lockgate", script = "wm_lock", unless = "wm_lock_open" },
  },
  steps = {
    { x = 24, y = 11, script = "wm_barges", unless = "wm_saw_barges" },
    { x = 25, y = 11, script = "wm_barges", unless = "wm_saw_barges" },
  },
  chests = {
    { id = "c1", x = 2, y = 5, give = "hiether", n = 1 },
    { id = "c2", x = 13, y = 6, give = "hipotion", n = 3 },
    { id = "c3", x = 3, y = 12, give = "oath_ring" },
  },
  foes = {
    { id = "f1", x = 9, y = 2, enc = "wm_sump_1", sprite = "wm_stitcher" },
    { id = "f2", x = 16, y = 3, enc = "wm_sump_2", sprite = "wm_thrall" },
    { id = "f3", x = 8, y = 6, enc = "wm_sump_3", sprite = "wm_thrall" },
    { id = "f4", x = 17, y = 5, enc = "wm_sump_1", sprite = "wm_stitcher" },
    { id = "f5", x = 21, y = 12, enc = "wm_sump_2", sprite = "wm_thrall" },
    { id = "f6", x = 11, y = 14, enc = "wm_sump_4", sprite = "crawler" },
    { id = "f7", x = 25, y = 3, enc = "wm_sump_3", sprite = "wm_thrall" },
  },
  exits = {
    { x = 2, y = 2, map = "wm_sump_1", mx = 7, my = 12, dir = 2 },
    { x = 2, y = 14, map = "wm_sump_3", mx = 10, my = 15, dir = 1 },
  },
}

-- Stacks up the south, a hall in the middle, and at the north end the balcony over the black shaft where the oars go down.
R.maps.wm_sump_3 = {
  name = "THE ROLL HOUSE", theme = "library",
  rows = {
    "###################",
    "#~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~#",
    "#hhhhh.......hhhhh#",
    "#h...h.......h...h#",
    "#h...h.......h...h#",
    "#h...+.......+...h#",
    "#hhhhhh.....hhhhhh#",
    "#.................#",
    "#.hhh.hhh.hhh.hhh.#",
    "#.................#",
    "#.hhh.hhh.hhh.hhh.#",
    "#.................#",
    "#.hhh.hhh.hhh.hhh.#",
    "#.................#",
    "#hhhhhhhh>hhhhhhhh#",
    "###################",
  },
  npcs = {
    { id = "wm_steward", x = 10, y = 7, script = "wm_steward", unless = "wm_steward_down" },
    { id = "wm_roll", x = 10, y = 5, sprite = "wm_drum", script = "wm_roll", when = "wm_steward_down", unless = "wm_burned" },
  },
  steps = {
    { x = 10, y = 4, script = "wm_balcony", once = true },
  },
  chests = {
    { id = "c1", x = 3, y = 5, give = "scholar_robe" },
    { id = "c2", x = 17, y = 7, give = "elixir", n = 1 },
    { id = "c3", x = 2, y = 15, give = "hipotion", n = 2 },
    { id = "c4", x = 18, y = 9, give = "hiether", n = 1 },
  },
  foes = {
    { id = "f1", x = 6, y = 13, enc = "wm_roll_1", sprite = "wm_stitcher" },
    { id = "f2", x = 14, y = 11, enc = "wm_sump_4", sprite = "wm_tally" },
    { id = "f3", x = 6, y = 9, enc = "wm_roll_1", sprite = "wm_stitcher" },
    { id = "f4", x = 14, y = 15, enc = "wm_sump_3", sprite = "wm_tally" },
  },
  exits = {
    { x = 10, y = 16, map = "wm_sump_2", mx = 3, my = 14, dir = 2 },
  },
}

-- ---------------------------------------------------------------- arriving

S.wm_arrive = {
  { when = "sn_done", steps = {
    t("The grass gives way all at once. The town is where you left it, which is to say falling down, though a few stalls have gone up in it since, for the sort of people who deal with her. The mill stands over it with three sails gone and the fourth hanging by a rope."),
    t("Every wall is a row of birds. They turn their heads at the same moment. There are a great many more of them than last time."),
    sister("They know what we're carrying. Look at them. They're counting."),
    doctor("Two thrones and half a continent, for a bird in a windmill. I've followed stupider orders, but I was paid for those."),
    { set = "wm_arrived" },
  }, other = {
    t("The birds watch you come. A harpy drops off a wall, looks at your hands, and laughs through her nose."),
    harrier("One token. She said one from each throne, and she can count, and so can I. You'll want the vampire's. Come back when you've got it, and mind the grass on your way out."),
    { world = WINDMILL },
  } },
}

S.wm_coming_back = {
  -- The square can be walked round on the way in, and she's gone by the time it's crossed on the way out.
  { when = "wm_gone", other = {
    t("The town has gone quiet. Every bird is on the mill now, on the cap, on the last sail, on each other. Not one of them is looking at you. They are all looking north."),
  } },
  { set = "wm_saw_birds" },
}

-- ---------------------------------------------------------------- people of the town

S.wm_talk_harrier = {
  { when = "wm_peewit_lives", steps = {
    harrier("I've got the keys to everything and nobody to keep it from. The little idiot's in charge, gods help us, and the birds do what she says. Don't tell me what you did up there. I might have to thank you."),
  }, other = {
    { when = "wm_answer", steps = {
      harrier("She's had the good chair brought up. I've done her books thirty years and I've never known her to want a chair. Go on up, she's expecting you."),
    }, other = {
      { when = "wm_bargain", steps = {
        harrier("Thuluan, is it? She says those hags have never forgiven anything in their lives. She says it the way you'd talk about a good cheese."),
      }, other = {
        ask(harrier("Harrier. I keep her door, since you saw to Aunt Carrion. You've got what she wanted, or you'd have no eyes. She's moved up to the cap, where she can see north. Don't touch the Collection. Some of it doesn't know it's been collected."), {
          topic("How many of you are there?", {
            harrier("Seven in the coven, and I do the books. Birds, I stopped counting. Peewit's the seventh, and don't let her sing at you."),
          }),
          topic("What is she, exactly?", {
            harrier("Half a hag, half a vulture, and I've never been sure which half was the bad idea. She's never cheated me, and I check."),
          }),
          { "Out of my way, then.", {} },
        }),
      } },
    } },
  } },
}

S.wm_talk_peewit = {
  { when = "wm_peewit_met", steps = {
    peewit("I've done a new verse! It's about your boots. It's mostly about your boots. I can't do the high bit yet, I go flat, it's the hum. But when I get it, you'll walk right off a cliff. You'll be so pleased."),
  }, other = {
    t("A small harpy with a patch over one eye is standing on the rim of the old well with her wings held out, breathing very deeply."),
    peewit("Oh! People! Stay there, don't move. You're meant to walk toward me and off a cliff. There isn't a cliff. We'll pretend. I'm Peewit, I'm the youngest, and this is my luring."),
    t("She shuts her one eye and sings. It is the sound of a gate being given bad news. Somewhere behind you, a bird falls off a wall."),
    ask(peewit("Well? Are you lured?"), {
      topic("What's under the patch?", {
        peewit("That's my bad eye. There's a lucky stone in it. Mother put it there when I was an egg, nearly. It hums. It's why I go flat on the high bit, because I'm always singing over the top of it. Nobody else can hear it, I've asked."),
      }),
      { "Completely. I can't help myself.", {
        peewit("You are? Really? Nobody's ever been lured before! Mother says it's a gift. She doesn't say what kind. Oh, wait till I tell Harrier. She said I could curdle a lake."),
        { set = "wm_kind_peewit" },
      } },
      { "No. That was horrible.", {
        peewit("I know! Isn't it? Harrier says I could curdle a lake. But I'm getting worse, and that's a change, and that's how you know you're learning. Same time tomorrow?"),
      } },
    }),
    { set = "wm_peewit_met" },
  } },
}

S.wm_talk_peewit_free = {
  t("Peewit is sitting on the rim of the well with a clean strip of cloth tied over the place where the patch was. Every bird in town is sitting round her, very politely. She's holding one note, quite softly, for the pleasure of it."),
  { when = "wm_kind_peewit", steps = {
    peewit("You said you were lured. You weren't, were you? It's all right. You will be. Come back when I've learned the second note."),
  }, other = {
    { when = "wm_peewit_met", steps = {
      peewit("You said it was horrible. It was, wasn't it? It was so horrible. I can hear it now. I can hear everything. Thank you for not lying. Nobody else ever bothered."),
    }, other = {
      peewit("You never heard me when I was horrible. Everyone else did. Oh, you missed it. Come back when I've learned the second note."),
    } },
  } },
}

S.wm_talk_moll = {
  { when = "wm_took", steps = {
    moll("I liked that daft bird. I'm not saying anything. I've a business to run, and I know what you came for and what it cost. My prices are my prices. Don't ask me how I am."),
  } },
  ask(moll("Magpie Moll, lost and found. Whatever the birds bring, I clean it and price it, and nobody in the Heart ever lost a thing that didn't end up here. What'll it be?"), {
    topic("Why trade with harpies?", {
      { when = "wm_gone", steps = {
        moll("They pay in what they've picked, and I don't ask what off. I asked once, and I couldn't eat for a week, and I've a good stomach. The old bird never cheated me, mind. That's what ought to have frightened me."),
      }, other = {
        moll("They pay in what they've picked, and I don't ask what off. I asked once, and I couldn't eat for a week, and I've a good stomach. The old bird's never cheated me, mind. That's what ought to frighten you. Read what she offers you twice, and then again in a mirror."),
      } },
    }),
    { "Show me what you've got.", { { shop = "wm_moll" } } },
    { "A cot for the night. 100 gold.", { { inn = 100 } } },
    { "Anything from Scythebreak?", {
      { when = "wm_got_dish", steps = {
        moll("Nothing new. Spoons, mostly. I've stopped putting those out."),
      }, other = {
        moll("Funny you should ask. There's been a lot from there lately, all at once. A whole street's worth of spoons. A coat that had been hung up by someone coming back, you can always tell. And this, with NAN scratched into the bottom."),
        t("It's a pie dish. It has a chip in the rim, where it hit the pump in the winter you were nine."),
        moll("You've gone a bad colour. No, take it. Take it, I don't sell people their own bad news. There's no margin in it."),
        { give = "wm_pie_dish" },
        { set = "wm_got_dish" },
      } },
    } },
    { "Nothing, thank you.", {} },
  }),
}

S.wm_talk_levy = {
  { when = "wm_lucilda_dead", steps = {
    { when = "wm_owe_favor", steps = {
      levy("I've the paper in order, sir or madam. One favour, of a size to be named, payable on demand. You'll hear from us. Probably not for ninety years. We are very patient people, and it turns out we like it here."),
    }, other = {
      t("Mister Levy has stood up from his chair. It seems to have taken some time. He is reading a very old paper."),
      levy("Dead. Ninety years of the firm's money, and she's dead. A syndicate named for one favour, and no one left to collect it from. You don't know what that does to a man."),
      levy("Hold on, though. Clause nine. Debts of the deceased pass to whoever did the deceasing. Oh, that's very nice. Oh, I do beg your pardon. Congratulations."),
      { set = "wm_owe_favor" },
    } },
  }, other = {
    { when = "wm_took", steps = {
      t("Mister Levy is sitting perfectly still, with his hat in his lap and a paper marked PAID."),
      levy("She stopped at the chair, on her way north. 'Levy,' she said, 'here's your favour. Go home.' And I've looked at it from every side, and it is one. It counts. Ninety years, and the firm's whole reason for being, and it's in the book as settled. I don't know what to do with my legs."),
    }, other = {
      ask(levy("Mister Levy, of the Hag's Favor. No, do go on past, you're not who I'm waiting for. I'm here to collect."), {
        topic("Collect what?", {
          levy("A favour. The old bird owes us one. That's the whole of the firm, you know, the north's largest criminal concern: it was founded on one favour, owed by one hag, and it's never yet been paid. Ninety years. I'm the eleventh man to sit in this chair."),
        }),
        { "Good luck with that.", {
          levy("If you do see her, you might mention it. Politely. The last man mentioned it impolitely, and I've got his hat."),
        } },
      }),
    } },
  } },
}

S.wm_talk_arle = {
  { when = "wm_lucilda_dead", steps = {
    t("Goody Arle is standing very straight in the doorway, with one boot half laced and her hand over her mouth."),
    arle("It came back. Just now, all at once, while I was doing my boot. He has a scar on his chin. He got it off the gate at home. He laughs with his mouth shut. Oh, my boy. I have to go. I have to go home. Excuse me. Excuse me."),
    { set = "wm_arle_left" },
  }, other = {
    { when = "wm_took", steps = {
      arle("She went by me on the road, and she wished me good morning. The jar's still up there. A thing paid is a thing paid. I expect I'll come again next year, and ask the birds."),
    }, other = {
      arle("I've come to ask for my son's face again. I come every year. He had the fever, and I went to her, and he lived, and that was the price. She keeps it in a jar. She's very fair about it."),
      ask(arle("He writes to me, you know. A nice young man, he sounds. I'm told I'm very proud of him."), {
        topic("Will she give it back?", {
          arle("She says a thing paid is a thing paid. I don't blame her. I'd pay it again. I'd only like to know who it was for."),
        }),
        { "I'm sorry, Goody.", {
          arle("Everyone is, dear. It's a very sorry town. Mind the birds."),
        } },
      }),
    } },
  } },
}

S.wm_talk_hobbin = {
  { when = "wm_lucilda_dead", steps = {
    { when = "wm_hobbin_called", steps = {
      t("Old Hobbin sits with his back against the stone and the pole across his knees. Someone has closed his eyes. Nothing in this room is turning, and it's very restful."),
    }, other = {
      t("The stone has stopped. Old Hobbin is sitting with his back against it and the pole across his knees, like a man who has at last put something down."),
      sister("Him I can do. He's been on the list for a very long time, and he's not sorry to be called. Give me a moment. It's nice to be wanted."),
      { set = "wm_hobbin_called" },
    } },
  }, other = {
    t("A very old man is walking round and round the great millstone, leaning on a pole. The stone turns. There's nothing under it, and there hasn't been for a long time."),
    { when = "wm_took", steps = {
      hobbin("She came down before she left. She checked it was turning, and she wrote it in her book. Fair to the last. How's the harvest?"),
    }, other = {
      ask(hobbin("Don't stop me, I can't stop. Hobbin's the name. I'm the miller. How's the harvest?"), {
        topic("Why are you turning an empty stone?", {
          hobbin("It was the year of the red grass, and everyone was dying. I went to the old bird and I said, let me not die so long as this mill turns. I thought that was a good one. I thought I'd got the better of her. Then the wind dropped."),
          hobbin("That was a hundred and forty years ago. The town went. My wife went. The grain ran out before your grandmother was born. She comes down every year and checks it's turning."),
        }),
        topic("Have you ever tried to stop?", {
          hobbin("Twice. You get three steps. Then you feel it coming up behind you, all those years at once, and you find you've gone on walking."),
          sister("He's on the list. A hundred and forty years overdue, and the Raven Queen can't touch him while the stone turns. I've never seen anyone cheat so hard and win so little."),
        }),
        { "The harvest was good, Hobbin.", {
          hobbin("Was it? That's good. That's very good. We'll want the stones dressed, then."),
        } },
      }),
    } },
  } },
}

-- ---------------------------------------------------------------- the Collection

S.wm_case_jars = {
  { when = "wm_lucilda_dead", steps = {
    t("A shelf of small jars with neat tags. PAID IN FULL: THE TASTE OF PEARS. PAID IN FULL: HIS MOTHER'S SINGING. PAID IN FULL: A BOY'S FACE. Every stopper is out. There's nothing in any of them now."),
  }, other = {
    t("A shelf of small stoppered jars with neat tags. PAID IN FULL: THE TASTE OF PEARS. PAID IN FULL: HIS MOTHER'S SINGING. PAID IN FULL: A BOY'S FACE. That last one is warm. When you tilt it, something inside it turns to look."),
  } },
}

S.wm_case_masks = {
  t("A row of Clinic masks on pegs, beaks all pointing the same way, each one labelled with a date. The dates are getting closer together."),
  doctor("One of those was a friend's. I'm not going to tell you which."),
}

S.wm_case_stand = {
  t("An empty stand of black wood, lit by a hole in the roof. The label says THE EYE. A second card says NOT FOR SALE. A third, in fresher ink, says MAKE AN OFFER."),
  t("The velvet on the stand hasn't a mark on it. Nothing has ever stood here."),
}

S.wm_case_letter = {
  t("A framed letter on very good paper. 'Dear Madam, thank you for the Roll. Your eye is enclosed, with our compliments. Do call on us if you are ever in the country. S.' Someone has stood a hot cup on the glass, many times, on purpose."),
}

S.wm_drawer = {
  t("A long flat drawer stands open on the landing, lined with green baize like a tray of spoons. In it lie dozens of thin silver bands, each with a small dark stone. Some of them still have hair in the clasp."),
  scholar("Those are ours. Circlets. Survivor work. We made forty in the first year, and we thought that was a great many."),
  sister("The birds go over the wall. Nothing stops a bird. And nobody up there is using them now."),
  scholar("Each one has a name inside the band. I could read them. I find I'm not going to."),
  scholar("Three of those would take the rest of you through the wall with your own heads. I want to ask her for them. I also want to set fire to this building. I'll try to do those in order."),
}

-- ---------------------------------------------------------------- Lucilda

local CIRCLETS = {
  t("The scholar goes to the drawer and stands over it for a long time, then takes out three bands, one after another, and doesn't read them."),
  { give = "circlet", n = 3 },
  scholar("These three were good people, and they won't mind. I've told myself that, and I'm going to go on telling myself. Put them on. They're cold for a while."),
}

local VISION = {
  { give = "wm_eye" },
  t("The eye lies in its cloth and looks at nothing. Then it turns, all by itself, and stops, the way a compass stops. North and west, and down. A long way down."),
  scholar("It isn't showing us where. Hold it up. It's showing us what's there."),
  { dark = true },
  t("Dark. Chain, each link the size of a house, going down for ever. Lanterns that nobody lit."),
  t("Something is walking on the chain. It wears a general's coat, and it wears it well, though the man inside has been dead a long time. It's in no hurry. It never has been."),
  t("Behind one of its eyes, something small and pale turns over in its sleep."),
  t("It doesn't look up. You get the feeling that it knows it could."),
  { dark = false },
  doctor("I know that coat. There's a portrait in the Clinic's founders' hall, with a black cloth over it, and we were told never to lift the cloth. Every one of us lifted the cloth."),
  doctor("That's her father. That's Colette's father. She told us he was dead."),
  sister("He is. That's what's wrong with him. I can't find him on the list, and I can't find him off it."),
  scholar("The first known case, still walking. We can't go to that with a strip of silver and a good attitude. Whatever anyone learned about it, they learned at Evrastin, behind the wall."),
  scholar("So it's the wall first, and the crack in it, and the books. I'd say I was looking forward to going home, if it were still there."),
}

local AFTER_FIGHT = {
  t("She comes down off the shaft in one long slow tumble of old feathers. The birds on the beams rise all together, and for once they don't make a sound."),
  lucilda("Oh, well done. Everything I was owed is loose now, and everything I owed. You'll find that's a great deal. Tell Tallow to keep it warm."),
  t("She stops. It takes a while to be sure."),
  { set = "wm_lucilda_dead" },
  peewit("Mother? It's gone loud. It's coming away. It doesn't want to stay now she isn't holding it on."),
  peewit("It's all right. I can do it. We take eyes. It's the one thing any of us is any good at. Look the other way, I go funny when people watch."),
  t("There is a small wet sound, and a small sharp breath. Then she's holding something out to you in both feet, wrapped in a scrap of cloth, shaking, with her head on one side."),
  peewit("Here. It's yours. Is it... it's so quiet. Oh. Oh, is that what it's like?"),
  t("She opens her beak and tries one note, the high one. It comes out clean and true and very small. All over the town the birds stop, and turn to listen."),
  { set = "wm_peewit_lives" },
  { set = "wm_gone" },
  { when = "wm_gone", steps = VISION },
  { when = "wm_gone", steps = CIRCLETS },
  { set = "wm_done" },
}

local function chooser(extra)
  local options = {
    topic("Can anyone here save her?", {
      doctor("Give me a clean table and a year. It's gone in behind everything. If I try it here she dies, only slower. I'm sorry. I've told a lot of people that, and meant it perhaps twice. I mean it."),
      sister("She'll die, and the Raven Queen will take her kindly, and I'll say the words. That's not an answer. Don't make me the one who gives you an answer."),
    }),
    topic("Scholar, do we need it?", {
      scholar("Without the eye we can't find him, and without him I don't know how this ends. I've seen what the end of this looks like. I'm doing the sum and I hate it. Don't ask me again."),
    }),
    { "A bargain's a bargain. Do it.", {
      { set = "wm_took" },
      sister("Then look at the floor. One of us should be looking at something when it's over."),
      { fade = true },
      { dark = true },
      t("You look at the floor, what there is of it. It's good old oak, worn pale, and you learn it very well. A small surprised noise. A lot of wings. Then a hum you never knew you could hear, stopping."),
      { dark = false },
      { when = "wm_kind_peewit", steps = {
        t("She asked you, the first day, if you were lured. You said you were."),
      } },
      t("Lucilda wipes something with care, folds it in a cloth, and puts it in your hand. It's warm. It weighs about what you'd think."),
      lucilda("Paid in full, and nobody can say otherwise. Here's your change: the drawer's yours, on the landing. You'll notice I'm the only one up here who doesn't look ill."),
      t("She climbs down from the shaft one joint at a time, and walks out along the beam and through the hole where the sail used to be. She doesn't fly. She goes north on foot, through the grass, toward the soup. She doesn't look back."),
      { set = "wm_gone" },
      sister("I'll say the words. You don't have to stay for it. I think I'd rather you did."),
    } },
    { "Let her go, Lucilda.", {
      { set = "wm_fight" },
      lucilda("No? Well, well. Do you know, nobody's surprised me since the Horned War. Get behind me, chick. Let me show them what a bargain looks like when it goes bad."),
      { battle = "wm_fight_lucilda" },
      { when = "wm_fight", steps = AFTER_FIGHT },
    } },
  }
  if extra then options[#options + 1] = extra end
  return ask(lucilda("Well? I've soup to get to. Say the word."), options)
end

local SAY_THE_NAME = { "Read out the name on the strip.", {
  { take = "wm_strip" },
  t("You unroll the strip. It's as cold as the day it was cut. There's one word on it. It hurts your teeth to say, and you say it."),
  lucilda("No. No, not out loud, not in front of the children."),
  t("Every feather on her stands up and goes flat. Her claw comes away from Peewit as if it's been slapped. For the first time she looks like what she is, a very old woman, caught."),
  lucilda("Three hundred years, I've been the only one who knew that. You said it wrong, by the way. It goes further back in the throat. Well, come on, then. Let's be having you."),
  { set = "wm_used_name" },
  { set = "wm_fight" },
  { battle = "wm_fight_named" },
  { when = "wm_fight", steps = AFTER_FIGHT },
} }

S.wm_lucilda = {
  { when = "wm_fight", steps = {
    lucilda("Back already? Good. I was afraid you'd lost your nerve, and then I'd have had to respect you."),
    { when = "wm_used_name", steps = {
      { battle = "wm_fight_named" },
    }, other = {
      { battle = "wm_fight_lucilda" },
    } },
    { when = "wm_fight", steps = AFTER_FIGHT },
  }, other = {
    { when = "wm_answer", steps = {
      lucilda("And the ice behind you has gone soft. I can smell it from here. You burnt the Roll, you dear fools. Every hag in Thuluan is walking south, and I don't suppose it's you they're walking to. Well? What did the Moot say?"),
      { choice = {
        { "They say you can come home.", {
          t("You tell her the rest of it. Tallow has kept her place."),
        } },
        { "Tallow says she kept your place.", {} },
      } },
      t("She's quiet for a while. It's the first time you've seen her keep still."),
      lucilda("Did she? Three hundred years, and the same spoon, I expect. She always could hold a grudge at a simmer. Yes. I believe I'll go. I'm tired, and it's very good soup."),
      lucilda("But first. I said you'd have the eye, and nobody living can say I broke my word. Oh, not this."),
      t("She reaches behind her for the bowl of milk, and tips it. The eye she showed you the day you met rolls along the beam, and bounces, and goes over the edge. A long way down, it breaks. It's glass."),
      lucilda("A copy, my ducks, tied to the real thing. It looks where that looks, and it's all anyone has ever been shown."),
      lucilda("Peewit! Up here, my chick. Mother wants you."),
      t("Peewit lands on the beam beside you, all elbows, delighted, with a new verse. She's told it can wait. Lucilda hooks one claw, very gently, under the patch on her bad eye, and lifts it."),
      t("There's no bird's eye under there. There is a lid, heavy and pale, and it rolls open. The thing that looks out of the side of Peewit's face is old and round, and has nothing to do with her."),
      lucilda("Best lock I ever owned. Who robs a fool? I set it in the egg, and it's grown in nicely. It comes out by the root, and the root goes all the way through. There it is. I never said what it was attached to."),
      peewit("Is that the hum, Mother? Is it the hum coming out? Will I get the high bit?"),
      { has = "wm_strip", steps = { chooser(SAY_THE_NAME) }, other = { chooser() } },
    }, other = {
      { when = "wm_bargain", steps = {
        { when = "wm_moot", steps = {
          lucilda("No answer? Then they've set you a job first. They always did like to see someone run."),
        }, other = {
          lucilda("Still here? The hags won't come to you. North past Sindal's last port, over the strait, and the reeds will let you by. They'll want to see what you do next."),
        } },
        ask(lucilda("Well? I'm not going anywhere, more's the pity."), {
          topic("And the eye?", {
            lucilda("Look how pretty it is, in its bowl. It's yours the moment you bring me their answer. I do like to hold a thing that's nearly someone else's."),
          }),
          { "We're going.", {} },
        }),
      }, other = {
        t("The cap of the mill has no floor to speak of. A single beam runs out over the drop to the great shaft, and on the end of it, as if she had grown there, sits what's left of a very old woman and the better part of a very old vulture."),
        lucilda("There you are. Hands full, and it only took you a kingdom each. Put them on the beam. Gently, now. One of those has been under a vampire since the Horned War, and they do so hate a smudge."),
        t("She doesn't touch them. She sniffs one and then the other and shuts her eyes, and a long slow shudder of pleasure goes down her from the neck to the claws."),
                ask(lucilda("You've got a look on your face, chick. Out with it."), {
          topic("What do you want them for?", {
            lucilda("When the Moot of Thuluan put me off the ice, they said I could come home the day two crowns bowed to me. It was a joke. It's the sort of joke you tell a sister you never mean to see again."),
            lucilda("Well, there are two crowns bowing. It only needs the Moot to look at them and say so, and I can't set foot on that ice to show them."),
          }),
          topic("What did you do to them?", {
            lucilda("Ask them. They tell it better. There's more crying."),
          }),
          topic("The circlets in the drawer.", {
            lucilda("Scraps. The birds bring them over the wall, and I can't get the hair out. Bring me the Moot's answer and you can have the drawer, for the asking. I've no use for a thing that only works on the living."),
                      }),
          { "The eye. That was the bargain.", {
            lucilda("And you shall have it. I have never once broken my word, and you can ask anyone who's still got a tongue. But I never said when. You should always ask when."),
            lucilda("Box them up, my ducks, and take that casket to Thuluan. Show the Moot what's in it, and bring me their answer, whichever it is. Then the eye, and I'll put it in your hand myself."),
            lucilda("And don't sulk, you need them too. That eye points a long way down, and the only creatures above ground who know the road sit round a fire on the ice, hating me. They know where the flayers are. Ask them."),
            sister("You're sending us to the people you sold."),
            lucilda("I am. Isn't it awful? Off you go, the road north is open to you now. Tell the reeds who sent you. Take a coat."),
            { take = "sn_tassel" },
            { give = "wm_casket" },
            { set = "wm_bargain" },
          } },
        }),
      } },
    } },
  } },
}

S.wm_harrier_fight = {
  t("Harrier is sitting on the open drawer. She has a small strip of cloth in one foot, and she doesn't look up at once."),
  harrier("She was an idiot. She never caught a thing in her life. It took me four years to teach her to fly, and she said thank you every single day."),
  harrier("You stood there."),
  { battle = "wm_fight_harrier" },
  t("Harrier drags herself up onto the sill. One wing hangs wrong. She looks at you with her whole head, and she doesn't ask for anything."),
  harrier("No. I'm not finished. I'm just finished for now. Take your drawer. Get out of my sky."),
  { set = "wm_harrier_down" },
  { when = "wm_harrier_down", steps = VISION },
  { when = "wm_harrier_down", steps = CIRCLETS },
  { set = "wm_done" },
}

-- ---------------------------------------------------------------- Thuluan and its people

S.wm_thuluan_first = {
  t("The road ends at a line of reeds, each cased in ice, and they lean aside for you with a sound like knitting needles. Beyond them black ice runs out flat to the end of the world, and on it, sunk to their sills, stand a great many crooked houses on stilts."),
  t("In every window, someone old is watching you, and not one of them blinks."),
  scholar("I've read about this. The books say Thuluan is a warm bog with a pleasant smell. I'd like a word with the books."),
  { set = "wm_saw_ice" },
}

S.wm_ice_shut = {
  t("Past the last house the ice goes on, and a hag's stick lies across the way. It's only a stick. You find you don't want to step over it until someone has said you can."),
}

S.wm_ice_gone = {
  t("Past the last house the ice has broken into black plates, heaving on the water. The way down has gone under, and nobody is going that way again."),
}

S.wm_talk_fenn = {
  t("A soldier in a long quilted coat stands at the gate of Thuluan, in the ice to his waist. He has a fine long spear, frost in his eyelashes, and a smile you've seen before."),
  fenn("Good evening! Corporal Teal, the Stitchers, Thuluan post. You'll be my relief. No? Not to worry, they did say it might be a while."),
  ask(fenn("Anything to declare? I'm obliged to ask. Nobody ever has."), {
    topic("How long have you been here?", {
      fenn("Since the freeze. The sergeant said 'stand there', and then it got rather cold, very fast. He's a little further along, if you look down. I'm told it's marvellous for the complexion."),
    }),
    topic("Don't you get hungry?", {
      fenn("How kind of you to ask. Yes. You're all looking very well. Would you step a little to the left? A little more. There, thank you. That does help."),
    }),
    topic("What's under the ice?", {
      fenn("The Sump, and I couldn't possibly say. The door at the bottom's a talker, mind. It asks after the country, and the answer is 'Perfect, thank you.' Smile when you say it, it can tell. I expect that's secret, but nobody's come to check."),
    }),
    { "Carry on, corporal.", {
      fenn("I will! It's the one thing I've got going for me."),
    } },
  }),
}

S.wm_talk_fenn_free = {
  t("The ice has let go. Corporal Teal is standing on the bank on two thin legs, looking down at them as if they'd been delivered to the wrong address."),
  fennFree("I seem to have been relieved. Nobody's said so, but I think that's what this is. I haven't seen a sunrise since before the freeze. I'm told they're not good for me. I thought I might walk east a little way and form my own opinion."),
  ask(fennFree("How's the country, by the way? I never did get to ask."), {
    { "Perfect, thank you.", {
      fennFree("Good. Very good. I knew it was."),
    } },
    { "It's rotten, corporal.", {
      fennFree("Yes. I did wonder. You hold a smile for three hundred years, you start to notice how it's fastened."),
    } },
  }),
}

S.wm_talk_sliver = {
  ask(sliver("Come in, come in, shut the door, you're letting the cold out, it's all we've got. Nanny Sliver. Goods and a warm room. Gold only. We've gone off firstborns, you've no idea what they cost to feed."), {
    topic("What keeps this fire going?", {
      sliver("Bad memories, mostly. They burn very clean. Somebody's first husband's been heating this room since the spring. Don't lean on him."),
    }),
    { "Show me your tray.", { { shop = "wm_sliver" } } },
    { "A warm room. 100 gold.", { { inn = 100 } } },
    { "Not today.", {} },
  }),
}

S.wm_talk_sedge = {
  { when = "wm_answer", steps = {
    sedge("I've packed! Three hundred years of nothing, and I've packed. Two shawls and a stolen cat. I'm off to see a tree. Do you know, I bit one once. Give my love to the buzzard, while there's some of her to give it to."),
  }, other = {
    { when = "wm_moot", steps = {
      ask(sedge("Back for a look at the fire? Go on, then, it's free. It's the only thing here that is."), {
        topic("You were in her coven?", {
          sedge("Three of us. Her, me and Tallow. She had the brains and I had the laugh, and Tallow had the patience, gods help us. Then she took the first offer. A hag! The first offer! She could have got him up to two eyes."),
        }),
        { "Enjoy the fire.", {} },
      }),
    }, other = {
      sedge("Visitors! Actual ones, with blood in! Go on through to the hall, dears, the Moot's sitting. The Moot's always sitting. Granny Rime's been sitting since before your people had shoes. Wipe your feet, she'll want them later."),
    } },
  } },
}

S.wm_talk_tallow = {
  t("A table is laid for two in a room with no fire. One bowl has been used, and used, and used. The other is clean, with a folded cloth and a spoon worn thin by polishing."),
  { when = "wm_answer", steps = {
    tallow("I've put the pot on. It wants a long time, this one. I've got the bones for it. You needn't stay."),
  }, other = {
    ask(tallow("Mother Tallow. I don't get up. You'd be the ones she sent. Does she still take her soup too hot? She was always in such a hurry. Sit anywhere but there."), {
      topic("You still lay her a place?", {
        tallow("Every night. There were three of us, child, and we swore never to sit down to supper without the other two. That was the night before she sold us. An oath is an oath. I'll have her at this table. I don't say on which side of the bowl."),
      }),
      topic("Did she ever send word?", {
        tallow("A feather, the first winter. Nothing with it. I keep thinking about that feather. I ate it, of course."),
      }),
      { "I'll leave you to it.", {} },
    }),
  } },
}

S.wm_talk_bitty = {
  { when = "wm_burned", steps = {
    t("The smallest hag in Thuluan is crouched at a crack in the ice with one bare foot in the water, shrieking with outrage and joy."),
    bitty("It's warm! It's warm and it's wet and it's horrible! Do it again! Is everywhere like this? Is it true there's a thing called a duck?"),
  }, other = {
    ask(bitty("Are you dinner? Aunt Sedge says you're not dinner. I'm Bitty. I'm only ninety. What's warm? They all keep saying warm. Is it like bleeding?"), {
      { "A bit. But it stays in you.", {
        bitty("Ooh. Keep your secrets, then. When I'm big I'm going to go and get some, and I'll keep it in a box."),
      } },
      { "Nothing like that, Bitty.", {
        bitty("That's what they all say. I bet it's made up. I bet it's like Tuesdays."),
      } },
    }),
  } },
}

S.wm_moot = {
  { when = "wm_answer", steps = {
    rime("You've had what you came for, and we've paid. Don't linger. I've three hundred years of grudges to get through, and you're standing on my list."),
  }, other = {
    { when = "wm_burned", steps = {
      t("The whole colony groans under you, and lets out a long breath. In the hall every hag is on her feet and no one is speaking. Some of them are crying. It isn't pleasant to watch."),
      rime("You'll forgive us if we don't curtsey. We pay what we owe, so listen, for I'll say it the once."),
      rime("The flayers are under the Guldan, at the bottom of everything. Go down the Violet Abyss, past the pillars of the world, to where the roof rains salt. That's the Pale Depths. Their city sits on a spit, with one thin bridge to it and a green skin over it to keep off the rain."),
      rime("A drow girl rules it, who was sold to them, and who ate their god's wits with a spoon. Keep your head wrapped and your thoughts dull. She'll know you're coming. I rather think she has for some time."),
      { has = "wm_strip", steps = {
        sedge("There's one name we didn't feel go. Someone's been at the Roll with a little knife. Clever. We shan't ask. We'd only want it."),
      } },
      rime("You, the quiet one. Come here. Hm. There's a great deal of nothing in that head, and it's very neatly kept."),
      sister("What does that mean?"),
      rime("It means somebody's been keeping it. I'd shut that door, if I were you. Well. On to business."),
      rime("The casket had a question in it, and here is the Moot's answer. Two crowns have bowed, and we keep our word, whatever you've heard. The banishment is lifted. Tell Lucilda she can come home."),
      t("Mother Tallow has got up, and come to the door of the hall. Nobody here looks as if they've seen that before."),
      tallow("Tell her I've kept her place."),
      t("All round the dark of the hall, very softly, a great many old women begin to smile."),
      { set = "wm_answer" },
    }, other = {
      { when = "wm_moot", steps = {
        ask(rime("Past the last house, east, and down. Burn it where it lies. We'll feel it. You're still here. Is there a question in you?"), {
          topic("What's under the swamp?", {
            sedge("Oars. Three hundred years of hard ice, and we lie awake and hear oars. Someone's using our swamp for a road, and it isn't anybody's friend. Go down far enough and you'll taste salt."),
          }),
          { "We're going.", {} },
        }),
      }, other = {
        t("The Moot of Thuluan is three old women round a fire that gives no heat. Behind them, in the dark of the hall, a great many more are breathing."),
        rime("Sit or don't, it's the same floor. Granny Rime, of the Moot. You've come a long way to be looked at. What's in the box?"),
        t("You open the casket. For a long moment there's no sound at all. Then somewhere in the dark somebody starts to laugh, and it goes round the hall like a lit fuse."),
        sedge("Two crowns! She did it! The wicked old buzzard actually did it! Oh, my ribs! Oh, I've still got some of those!"),
        rime("'When two crowns bow to you, you may come home.' We said that to her. It was a joke, child. We're known for them. She'll have sent you with a story. Ask what you came to ask."),
        { take = "wm_casket" },
        ask(rime("Well?"), {
          topic("What did Lucilda do to you?", {
            rime("Every hag has one true name, and ours were on the Roll: one skin, in one hand, in our keeping. She sold it to Sindal Deverous for a shiny thing out of his cabinet. He took it down under the swamp, and that night the water froze, from the bottom up."),
            sedge("She didn't even haggle, that's what stings. A hag! And she took the first offer!"),
          }),
          topic("Why haven't you gone after her?", {
            rime("A hag who goes past the last reed, or too near her own name, stops. They're out there still, the ones who tried. She can't come here, for the banishment. We can't go there, for the Roll. It's been a very long conversation."),
          }),
          { "Where is the mind flayers' city?", {
            rime("Ah. Yes. We know that. We used to listen at the bottom of the swamp, and things down there would listen back. You'll have it the day the Roll is ash, and not before. If I told you now, you'd only leave."),
          } },
          { "I'm nobody's errand-runner.", {
            sedge("Oh, I like this one. Everyone's somebody's errand, dear. You can have ours, or you can have a long walk home with nothing to show for it. Have a think on the way down."),
          } },
        }),
        rime("So. Go down the Sump, where no hag can go, and burn the Roll, every name on it. Do that and you have the road, and she has her answer. Past the last house, east."),
        { set = "wm_moot" },
      } },
    } },
  } },
}

-- ---------------------------------------------------------------- the ice and the Sump

S.wm_stopped_1 = {
  t("A hag, cased in blue ice, stopped in mid-stride with a basket on her arm. Someone has hung a little painted sign round her neck. It says BACK SOON. The paint is very old."),
}

S.wm_stopped_2 = {
  t("This one was running. She's a long way out for someone her age. There's a letter in her hand, sealed, and the ice has it too. You can read the address, and it just says WARM."),
}

S.wm_stopped_3 = {
  t("A big hag, facing back the way she came, with her mouth wide open and one finger raised. She had thought of what she should have said. You will never know what it was."),
}

S.wm_notice = {
  t("A board, screwed to the rock, in a beautiful hand: ALL STAFF. REMEMBER THAT A SMILE COSTS NOTHING. Under it, scratched with a spearpoint: IT COST ME MY FEET."),
}

S.wm_grille = {
  t("A bronze grille fills the passage, with a wide bronze mouth set into it, smiling. It has been polished, quite recently, and you'd rather not think who by."),
  ask(t("'Good evening,' says the grille, warmly. 'How is the country?'"), {
    { "Perfect, thank you.", {
      { set = "wm_door_open" },
      t("'I'm so glad,' says the grille, and it folds back into the rock with a long sigh of contentment."),
      doctor("I've been checked through a great many doors in my life, and that's the one I'm going to dream about."),
    } },
    { "It's full of vampires.", {
      t("'I see,' says the grille, no less warmly. 'Somebody will be along to help you with that.'"),
      { battle = "wm_door_guard" },
      t("The grille considers what's left, for a moment. 'Perfect,' it says, and folds back into the rock."),
      { set = "wm_door_open" },
    } },
    { "Say nothing, and smile.", {
      t("You smile. The grille smiles. It goes on for much longer than you'd like. 'Yes,' it says at last, 'that's it. That's how it's done,' and it folds back into the rock."),
      { set = "wm_door_open" },
    } },
  }),
}

S.wm_barges = {
  t("The barges are frozen into the cut, six in a line, black and low in the water. On every bench sits a rower with an oar in both hands. They're pulling slowly at nothing, all in time, and the salt has grown on them like fur."),
  t("Every one of them is smiling."),
  sister("Those are people. Those are his people. He had me say grace at his table, with this going on under it."),
  { set = "wm_saw_barges" },
}

S.wm_manifest = {
  t("A clerk's desk on the quay, with a book chained to it. 'Season the four hundredth. Sixty for the east, in good order, all content. Received in the same order, and thanked.' The thanks aren't signed. There is a small, tidy, greenish thumbprint where a name would go."),
  scholar("Four hundred seasons of sixty. Sindal's perfect country has been paying someone, by the head, for longer than I've been alive. I'd like to know what he's been buying."),
}

S.wm_talk_oarsman = {
  t("The man at the end of the bench has stopped pulling. His oar is frozen to his hands, and he's looking at them. He isn't smiling. It's the first honest face you've seen since Sindal."),
  { when = "wm_promised", steps = {
    oarsman("You came back. Or you never left, I can't tell. It's all right. I've been practising being unhappy. It's coming along."),
  }, other = {
    oarsman("Is it you? Is it my turn? I was a cooper in Upriftin. I said something about the berries, at a dinner, and a nice man came. Then I was so happy. I was happy for years. It's worn off, and I'm sorry, I can't make it come back."),
  } },
  ask(oarsman("They go on down, when the ice lets them. East, under the water. Something at the bottom wants us. Please. I don't want to be happy when I get there."), {
    topic("Who buys you?", {
      oarsman("There's a green light. Someone counts us, but not with their hands. It's inside your head, very gentle, like being looked over by a good aunt. I think it's the worst thing I've ever felt. I can't remember why."),
    }),
    { "We'll come back for you.", {
      oarsman("Will you? That's kind. People used to say that to me at the door. Go on, then. I'll keep your place."),
      { set = "wm_promised" },
    } },
    { "Sister. Can you do anything?", {
      sister("I can do one thing. The Raven Queen doesn't ask anyone to wait. Look at me, cooper. What was your wife's name?"),
      oarsman("Hetty. It was Hetty. Oh, there she is."),
      { fade = true },
      t("The sister takes her hand from his eyes. The oar has come free. She lays it across his knees, and is quiet for some time."),
      { set = "wm_mercy" },
    } },
  }),
}

S.wm_wheel_a = {
  t("A sluice wheel as high as your chest, furred with salt. It takes all of you. It goes round once, with a shriek, and somewhere under the quay something heavy begins to let go."),
  { set = "wm_wheel_a" },
}

S.wm_wheel_b = {
  t("Another wheel. A plate riveted to it says TURN BOTH, THEN ASK AT THE LOCK. SMILE. You turn it. Far off down the cut, water starts to move."),
  { set = "wm_wheel_b" },
}

S.wm_lock = {
  { all = { "wm_wheel_a", "wm_wheel_b" }, steps = {
    t("The lock gate shudders. Black water sinks down its face, a foot, a yard, and the gate swings out on its own weight, and the way to the west stands open, dripping."),
    { set = "wm_lock_open" },
  }, other = {
    t("A lock gate of black iron, with brine standing behind it to the height of your head. There's a sluice wheel in each of the rooms off the north quay, up there across the water."),
  } },
}

S.wm_balcony = {
  t("The hall ends in a balcony with no rail. Beyond it the ground just stops. A black shaft as wide as a town goes down and away to the east, and the wind that comes up it tastes of salt, and something else, like a coin held in the mouth."),
  t("You can hear it, very faintly, from a long way below. Oars."),
  scholar("That's how the sixty go. I don't advise it. Nothing in that water comes back."),
}

S.wm_steward = {
  t("A long desk has been set across the hall, in front of a great iron drum, and a thin man sits behind it in a beautifully kept coat. Frost has grown over his shoulders. He looks up and smiles, and you've met that smile."),
  steward("Good evening, and welcome to the Roll House. Have you an appointment? Let me look. Three hundred years I've had this book open, and you're my first visitors. I do hope you've enjoyed the country."),
  ask(steward("I'm afraid the Roll isn't open to the public. Everyone on it is very well looked after."), {
    topic("Who do you keep this for?", {
      steward("His Excellency, and the good of all. Thuluan is the best-run department in the Veins. Nothing has ever gone wrong here. I have the forms."),
    }),
    topic("Those people at the oars.", {
      steward("Citizens, in transit. The east pays in things you wouldn't understand, and we pay in smiles. Sixty a season, in good order, and nobody has ever complained. Do go and ask them."),
    }),
    { "Step away from the drum.", {
      steward("Ah. I shall have to make a note of that."),
      { battle = "wm_fight_steward" },
      t("The Steward sits back down, very carefully, and puts his pen straight. 'Perfect,' he says. Then there's only a coat in the chair, and a little fine cold dust."),
      { set = "wm_steward_down" },
    } },
  }),
}

local BURN = {
  t("The doctor's firepot goes in at the bottom of the drum. For a moment, nothing. Then the names start to run, all together, like ants from a kicked nest."),
  { big = "THE ROLL BURNS" },
  t("It's the first warm thing in this whole cold country. High above you the ice gives a long, low groan that goes on for some time. And then, faintly, through a mile of rock, you hear an enormous number of old women starting to laugh."),
  sister("That's the cut going. All that ice is going to come down this stair. I'd run."),
  { set = "wm_burned" },
  { fade = true },
  t("You run. The water comes up behind you on the stair, salt and black, and when you come out onto the ice of Thuluan it's cracking from one end of the world to the other."),
  { warp = { "wm_thuluan", 13, 7, 1 } },
}

S.wm_roll = {
  t("The Roll is a single skin as long as a street, wound on an iron drum, and the cold comes off it the way heat comes off an oven. Names run down it in small neat rows. They won't stay still to be read."),
  sister("You know what walks off that ice tonight. All of them. I'm not saying don't. I'm saying know it."),
  doctor("They're prisoners of the man who feeds that canal. I find I'd rather have them loose and angry at him. It's your hand on the match."),
  ask(scholar("There's one entry here scored through, near the top, with a note in the margin. 'Sold by this hand.' That will be hers."), {
    topic("What would a true name do?", {
      scholar("Whatever you liked, for as long as you could bear to say it. It wouldn't last. But a hag named aloud is a hag with her hands tied. I'd want that kept from the Moot. I'm not sure I'd want it kept by us."),
    }),
    { "Burn it. Every name.", BURN },
    { "Cut her name out first, then burn it.", {
      t("It takes the sister's knife, and it doesn't want to come. The strip is no longer than your hand, and so cold that it sticks. One word on it. You don't read it, and put it away quickly."),
      { give = "wm_strip" },
      { when = "wm_steward_down", steps = BURN },
    } },
  }),
}

-- ---------------------------------------------------------------- the guide

R.goals = {
  { done = "wm_bargain", text = "Bring Lucilda the tokens", map = "wm_mill_3", x = 8, y = 6, when = "sn_done" },
  { done = "wm_moot", text = "Go to the hags of Thuluan", site = "thuluan", when = "wm_bargain" },
  { done = "wm_door_open", text = "Get down the Cold Stair", map = "wm_sump_1", x = 9, y = 12, when = "wm_moot" },
  { done = "wm_lock_open", text = "Open the lock", map = "wm_sump_2", x = 7, y = 13, when = "wm_door_open" },
  { done = "wm_burned", text = "Burn the Roll", map = "wm_sump_3", x = 10, y = 6, when = "wm_lock_open" },
  { done = "wm_answer", text = "Hear the Moot's answer", map = "wm_thuluan", x = 13, y = 4, when = "wm_burned" },
  { done = "wm_done", text = "Leave the mill", map = "wm_mill_2", x = 11, y = 3, when = "wm_took" },
  { done = "wm_done", text = "Take the answer to Lucilda", map = "wm_mill_3", x = 8, y = 7, when = "wm_answer" },
}

return R
