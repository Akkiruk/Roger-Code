-- games/blightmare/regions/ruin_deep.lua
-- Back below, a year on: draft for the author to edit. Plain data and local helpers. Everything hangs off one chain of maps from the
-- abyss_r site: the Armway (the bore Qarhuul's arm left), Touarch, the Broken Road, the Last Lantern, the Underweb, Strathe and the
-- Quiet House, the Salt Stair, Crysathula, and the Cortex Nest at the end of it.
-- The Old Hive under Crysathula (side_zalabarula) and the Diamond Cave off the Broken Road (side_chylbad) are off the route.
-- The heart of it is the page in the Nest: Ansa Thole's own hand tells the hero what they are, and then the party answers. Keep it
-- quiet. The way to the finale is the stair at the east end of the Nest, which opens on rn_done and rd_done together.
-- ruin_north may have come first or not: anything that cares reads rn_done.

local say = require("games.blightmare.say")

local t, ask, topic, person, line = say.t, say.ask, say.topic, say.person, say.line

local R = {
  id = "ruin_deep", prefix = "rd_",
  entry = { flags = { "ruined", "rs_done" }, join = { "deserter", "owlin" }, lvl = 38, site = "abyss_r", map = "rd_abyss", x = 3, y = 2 },
  exit = "rd_done",
  sites = {
    abyss_r = { x = 60, y = 27, map = "rd_abyss", mx = 3, my = 2, dir = 2, name = "THE VIOLET ABYSS", when = "rs_done" },
  },
  -- read from other regions, and set here for the finale
  exports = { "ud_boot", "ud_fettle_free", "ud_grudge_filed", "rd_asked_jez", "rd_zal_kept" },
  maps = {}, scripts = {}, shops = {}, goals = {},
  foes = {}, abilities = {}, encounters = {}, field = {},
  looks = {}, names = {}, art = {},
}

local S = R.scripts

local deserter = line("deserter")
local cleric = line("cleric")
local owlin = line("owlin")
local jezzara = line("jezzara")
local asphodel = line("asphodel")
local vierrela = person("rd_vierrela", "VIERRELA")
local halryna = person("rd_halryna_c", "HALRYNA")

local dangle = person("rd_dangle", "MABBET DANGLE")
local kindle = person("rd_kindle", "TOLLO KINDLE")
local tally = person("rd_tally", "KEEPER TALLY")
local olive = person("rd_olive", "QUEEN OLIVE")
local mag = person("rd_mag", "MAG EMBER")
local hask = person("rd_hask", "HASK COBBLE")
local pell = person("rd_pell", "SIR ALDOUS PELL")
local tam = person("rd_tam", "KIT")
local winder = person("rd_winder", "BASKET-WINDER")
local fettle = person("rd_fettle", "FETTLE")
local sevria = person("rd_sevria", "SEVRIA")
local murgrum = person("rd_murgrum", "MURGRUM")
local moss = person("rd_moss", "ROAD-MOSS")
local ilzra = person("rd_ilzra", "ILZRA")
local bruna = person("rd_w_bruna", "OLD BRUNA")
local orderly = person("rd_w_orderly", "ORDERLY")
local consultant = person("rd_consultant_f", "THE CONSULTANT")
local mmrk = person("rd_mmrk", "MMRK")
local commons = person("rd_commons", "COMMONS CLERK")
local houndrin = person("rd_houndrin", "HOUNDRIN DILAGON")
local sael = person("rd_sael", "SAEL")
local iliss = person("rd_iliss", "OLD ILISS")
local nulliira = person("rd_nulliira_f", "MOTHER NULLIIRA")
local borrowed = person("rd_nulliira_w", "THE VOICE IN NULLIIRA")
local ibbit = person("rd_ibbit", "FACTOR IBBIT")
local zhar = person("rd_zhar", "CLERK ZHAR")
local sult = person("rd_sult", "BROTHER SULT")
local sweeper = person("rd_sweeper", "SWEEPER")
local uln = person("rd_uln", "ULN")
local vel = person("rd_vel", "ARCHIVIST VEL")
local pod = person("rd_pod", "CELL-KEEPER")
local husk = person("rd_husk_f", "WHAT'S LEFT")
local zal = person("rd_zal", "ZALABARULA")

-- ---------------------------------------------------------------- how they look

local L = R.looks

L.rd_dangle = { like = "ud_dangle", coat = "tie", trim = "line", mouth = "line" }
L.rd_olive = { like = "ud_olive", coat = "tie", carry = "ladle", hat = "crown", hatInk = "warn", hatTrim = "hi" }
L.rd_kindle = { like = "ud_kindle", coat = "panel", eyes = "tired", mouth = "line" }
L.rd_tally = { like = "ud_tally", carry = "tome", coat = "panel" }
L.rd_mag = { like = "ud_mag", coat = "tie", eyes = "tired" }
L.rd_hask = { like = "ud_hask", coat = "panel", carry = "boots" }
L.rd_pell = { like = "ud_pell", carry = "scroll", eyes = "wide", oneShoe = true, coat = "redTint" }
L.rd_tam = { like = "ud_tam", tall = 0.42, carry = "lantern" }
L.rd_winder = { like = "ud_winder", carry = "wheel", eyes = "narrow" }
L.rd_fettle = { like = "ud_fettle", wear = { "badge" }, mouth = "smile" }
L.rd_sevria = { like = "sevria", carry = "ledger", eyes = "tired", mouth = "line" }
L.rd_murgrum = { like = "murgrum", carry = "shovel", mouth = "smile", eyes = "normal" }
L.rd_moss = { like = "ud_moss", eyes = "wide", mouth = "open", back = "redTint" }
L.rd_ilzra = { like = "ud_ilzra", coat = "text", trim = "line", carry = "bowl", mouth = "line" }
L.rd_ilzra_w = { like = "rd_ilzra", carry = "none", eyes = "tired" }
L.rd_sister = { like = "cleric" }
L.rd_w_bruna = { kind = "duergar", pose = "lying", coat = "tie", trim = "red", beard = "belted", beardInk = "text", mouth = "teeth", eyes = "narrow" }
L.rd_w_orderly = { kind = "human", pose = "lying", coat = "text", trim = "line", eyes = "tired", mouth = "line", flip = true }
L.rd_w_eyes = { kind = "deepgnome", pose = "lying", coat = "blueTint", trim = "panel", eyes = "wide", size = 0.75 }
L.rd_consultant_f = { kind = "human", tall = 0.98, build = "thin", cut = "coat", coat = "text", trim = "line", skin = "line", hat = "bandage", hatInk = "text", wear = { "surgeon", "badge" }, carry = "clipboard", eyes = "none", mouth = "smile", back = "bg" }
L.rd_mmrk = { like = "ud_mmrk", carry = "basket", eyes = "tired" }
L.rd_mmrk_2 = { like = "rd_mmrk" }
L.rd_commons = { like = "ud_commons", coat = "panel", mouth = "line", eyes = "tired" }
L.rd_houndrin = { like = "ud_houndrin", coat = "tie", mouth = "line" }
L.rd_sael = { like = "ud_sael", tall = 0.7, carry = "doll", mouth = "line" }
L.rd_sael_c = { like = "rd_sael", carry = "ladle", wear = { "strap" } }
L.rd_iliss = { like = "ud_iliss", eyes = "tired" }
L.rd_rail_1 = { kind = "drider", coat = "tie", trim = "panel", hairInk = "text", eyes = "blank", mouth = "line" }
L.rd_rail_2 = { kind = "drider", tall = 0.92, coat = "hiTint", trim = "panel", hairInk = "line", eyes = "blank", mouth = "line" }
L.rd_rail_3 = { kind = "drider", tall = 0.86, coat = "blueTint", trim = "panel", hairInk = "text", eyes = "blank", mouth = "line" }
L.rd_nulliira_f = { like = "ud_nulliira", eyes = "tired", mouth = "line" }
L.rd_nulliira_w = { like = "ud_nulliira", eyes = "closed", mouth = "smile", skin = "line", lean = 0.08, back = "accent" }
L.rd_jez_c = { like = "jezzara", carry = "dagger", mouth = "line", eyes = "tired" }
L.rd_halryna_c = { like = "halryna", eyes = "closed", carry = "none", pose = "lying" }
L.rd_ibbit = { like = "ud_ibbit", carry = "pole" }
L.rd_zhar = { like = "ud_zhar", mouth = "open", eyes = "tired" }
L.rd_sult = { like = "ud_sult", coat = "tie", carry = "bowl" }
L.rd_sweeper = { like = "ud_sweeper", eyes = "wide", mouth = "frown", back = "panel" }
L.rd_uln = { like = "ud_uln", carry = "tome" }
L.rd_vel = { like = "ud_vel", carry = "tube", eyes = "tired" }
L.rd_pod = { like = "ud_pod", carry = "pillow" }
L.rd_vierrela = { like = "vierrela", wear = { "shawl" }, shawlInk = "tie", carry = "none", eyes = "tired", mouth = "smile" }
L.rd_husk_f = { like = "vierrela", eyes = "blank", mouth = "smile", skin = "line", back = "bg", carry = "none", mark = "scar" }
L.rd_zal = { kind = "illithid", tall = 0.85, build = "gaunt", cut = "rags", coat = "hiTint", trim = "bg", skin = "hi", tentacles = true, eyes = "blank", back = "bg" }

R.names = {
  ["MABBET DANGLE"] = "rd_dangle", ["TOLLO KINDLE"] = "rd_kindle", ["KEEPER TALLY"] = "rd_tally", ["QUEEN OLIVE"] = "rd_olive", ["MAG EMBER"] = "rd_mag",
  ["HASK COBBLE"] = "rd_hask", ["SIR ALDOUS PELL"] = "rd_pell", KIT = "rd_tam", ["BASKET-WINDER"] = "rd_winder", FETTLE = "rd_fettle", SEVRIA = "rd_sevria",
  MURGRUM = "rd_murgrum", ["ROAD-MOSS"] = "rd_moss", ILZRA = "rd_ilzra", ["OLD BRUNA"] = "rd_w_bruna", ORDERLY = "rd_w_orderly",
  ["THE CONSULTANT"] = "rd_consultant_f", MMRK = "rd_mmrk", ["COMMONS CLERK"] = "rd_commons", ["HOUNDRIN DILAGON"] = "rd_houndrin", SAEL = "rd_sael",
  ["OLD ILISS"] = "rd_iliss", ["MOTHER NULLIIRA"] = "rd_nulliira_f", ["THE VOICE IN NULLIIRA"] = "rd_nulliira_w", ["FACTOR IBBIT"] = "rd_ibbit",
  ["CLERK ZHAR"] = "rd_zhar", ["BROTHER SULT"] = "rd_sult", SWEEPER = "rd_sweeper", ULN = "rd_uln", ["ARCHIVIST VEL"] = "rd_vel", ["CELL-KEEPER"] = "rd_pod",
  ["WHAT'S LEFT"] = "rd_husk_f", ZALABARULA = "rd_zal", VIERRELA = "rd_vierrela", HALRYNA = "rd_halryna_c",
}

-- ---------------------------------------------------------------- what's down here to fight

local A = R.abilities

A.rd_lid = { name = "THE LID OPENS", power = 90, status = "blind", chance = 30 }
A.rd_hook = { name = "OLD HOOK", power = 130 }
A.rd_clack = { name = "ECHO CLACK", power = 55, target = "all" }
A.rd_smother = { name = "GREY SMOTHER", power = 80, status = "blind", chance = 50 }
A.rd_dust = { name = "FALLING DUST", power = 65, status = "sleep", chance = 40 }
A.rd_line = { name = "THE LINE", mp = 5, power = 50, magic = true, element = "mind", status = "nightmare", chance = 60 }
A.rd_stare = { name = "FOUR EYES", mp = 4, status = "thrall", chance = 35 }
A.rd_legs = { name = "EIGHT LEGS", power = 115 }
A.rd_calm = { name = "ONE BREATH", mp = 4, power = 45, magic = true, target = "all", element = "mind" }
A.rd_blink = { name = "BLINK BITE", power = 120, status = "poison", chance = 30 }
A.rd_silk = { name = "WET SILK", power = 50, status = "sleep", chance = 40 }
A.rd_sting = { name = "SALT STING", power = 110, status = "poison", chance = 40 }
A.rd_squall = { name = "OCEAN ROPE", mp = 6, power = 60, magic = true, target = "all", element = "ice" }
A.rd_sip = { name = "SIP", mp = 5, power = 100, magic = true, element = "mind", status = "tadpole", chance = 30 }
A.rd_leap = { name = "EAR LEAP", power = 80, status = "tadpole", chance = 25 }
A.rd_chill = { name = "COLD SPIT", mp = 3, power = 75, magic = true, element = "ice" }
A.rd_facet = { name = "EDGE", power = 120 }
A.rd_glint = { name = "GLINT", mp = 3, power = 40, status = "blind", chance = 60 }

A.rd_round = { name = "WARD ROUND", power = 115 }
A.rd_notes = { name = "CASE NOTES", mp = 5, magic = true, status = "doom", chance = 35 }
A.rd_students = { name = "CALLS HIS STUDENTS", target = "summon" }
A.rd_prognosis = { name = "PROGNOSIS", power = 205, magic = true, target = "all", element = "mind", windup = 34, warn = "HE TURNS TO THE NEXT BED" }
A.rd_drop = { name = "ONE DROP", mp = 6, magic = true, status = "tadpole", chance = 50 }
A.rd_hush = { name = "HUSH NOW", mp = 5, power = 55, magic = true, target = "all", status = "sleep", chance = 35 }
A.rd_children = { name = "CALLS THE CHILDREN", target = "summon" }
A.rd_slept = { name = "SLEPT WELL", power = 215, magic = true, target = "all", element = "mind", windup = 34, warn = "SHE LAYS A FINGER TO HER LIPS" }
A.rd_sit = { name = "SIT DOWN, DEAR", mp = 6, power = 60, magic = true, status = "thrall", chance = 45 }
A.rd_restful = { name = "SO RESTFUL", mp = 6, power = 70, magic = true, target = "all", element = "mind", status = "nightmare", chance = 50 }
A.rd_incision = { name = "CLEAN INCISION", power = 150, status = "silence", chance = 40 }
A.rd_hive = { name = "IT CALLS THE HIVE", target = "summon" }
A.rd_goodnight = { name = "GOODBYE, DEAR", power = 230, magic = true, target = "all", element = "mind", windup = 34, warn = "IT HOLDS OUT ONE HAND" }
A.rd_dictate = { name = "DICTATION", mp = 5, power = 85, magic = true, element = "mind", status = "doom", chance = 30 }
A.rd_tendril = { name = "DRY TENDRILS", power = 120, status = "silence", chance = 30 }
A.rd_held = { name = "HELD", power = 210, magic = true, target = "all", element = "mind", windup = 34, warn = "ITS TENDRILS CLOSE ON NOTHING" }
A.rd_fang = { name = "DIAMOND FANG", power = 150 }
A.rd_stalk = { name = "FROM BEHIND", power = 190, status = "blind", chance = 30 }
A.rd_rime = { name = "RIME BREATH", mp = 6, power = 95, magic = true, target = "all", element = "ice" }
A.rd_white = { name = "WHITE BREATH", power = 270, magic = true, target = "all", element = "ice", windup = 34, warn = "THE AIR GOES THIN AND STILL" }
A.rd_shards = { name = "THE WALLS SHED", target = "summon" }

local F = R.foes

F.rd_shed = { name = "SHED EYE", tier = 38, shape = "small", sprite = "rd_shed", family = "slime", abilities = { { "rd_lid", 3 }, { "stare", 1 } }, weak = { "holy" } }
F.rd_hook = { name = "OLD HOOK", tier = 38, shape = "brute", sprite = "ud_hookhorror", family = "stalker", abilities = { { "rd_hook", 3 }, { "rd_clack", 1 } }, weak = { "ice" } }
F.rd_walker = { name = "SLEEPWALKER", tier = 39, shape = "tank", sprite = "blighted", family = "blighted", abilities = { { "claw", 3 }, { "touch", 1 } }, weak = { "holy" } }
F.rd_mantle = { name = "GREY MANTLE", tier = 39, shape = "small", sprite = "ud_mantle", family = "roper", abilities = { { "rd_smother", 1 } }, weak = { "bolt" } }
F.rd_moth = { name = "FALLEN MOTH", tier = 39, shape = "quick", sprite = "vt_moth", family = "bug", abilities = { { "bite", 3 }, { "rd_dust", 2 } }, weak = { "fire" } }
F.rd_reader = { name = "LINE READER", tier = 40, shape = "caster", sprite = "vt_reader", family = "blighted", abilities = { { "claw", 3 }, { "rd_line", 2 } }, immune = { "blind" }, weak = { "holy" } }
F.rd_hulk = { name = "BLIND HULK", tier = 40, shape = "tank", sprite = "ud_umber", family = "orc", abilities = { { "claw", 3 }, { "rd_stare", 1 } }, weak = { "ice" } }
F.rd_risen = { name = "THE RISEN", tier = 40, shape = "brute", sprite = "drider", family = "stalker", abilities = { { "rd_legs", 3 }, { "rd_calm", 1 } }, weak = { "fire" }, resist = { "mind" } }
F.rd_ettercap = { name = "LOOSE ETTERCAP", short = "ETTERCAP", tier = 40, shape = "healer", sprite = "ettercap", family = "bug", abilities = { { "claw", 3 }, { "rd_silk", 2 }, { "field_surgery", 1 } }, weak = { "fire" } }
F.rd_phase = { name = "SPLIT SPIDER", tier = 40, shape = "quick", sprite = "ud_phase", family = "bug", abilities = { { "rd_blink", 1 } }, weak = { "bolt" } }
F.rd_manta = { name = "STORM MANTA", tier = 41, shape = "quick", sprite = "ud_manta", family = "harpy", abilities = { { "rd_sting", 3 }, { "rd_smother", 1 } }, weak = { "bolt" } }
F.rd_drowned = { name = "SALT WALKER", tier = 41, shape = "tank", sprite = "ud_drowned", family = "blighted", abilities = { { "claw", 3 }, { "rd_squall", 1 } }, resist = { "ice" }, weak = { "fire" } }
F.rd_flayer = { name = "HUNGRY FLAYER", short = "FLAYER", tier = 42, shape = "caster", sprite = "mindflayer", family = "mage", abilities = { { "mind_lash", 3 }, { "rd_sip", 2 } }, resist = { "mind" } }
F.rd_rover = { name = "BRAIN ROVER", tier = 42, shape = "small", sprite = "rd_rover", family = "slime", abilities = { { "bite", 3 }, { "rd_leap", 1 } }, weak = { "fire" } }
F.rd_wyrm = { name = "CAVE WYRMLING", short = "WYRMLING", tier = 42, shape = "quick", sprite = "rd_wyrm", family = "dragon", xpx = 1.5, abilities = { { "bite", 3 }, { "rd_chill", 1 } }, weak = { "fire" }, resist = { "ice" } }
F.rd_shard = { name = "SHARD WALKER", short = "SHARD", tier = 42, shape = "tank", sprite = "rd_shard", family = "skeleton", xpx = 1.5, abilities = { { "rd_facet", 3 }, { "rd_glint", 1 } }, weak = { "bolt" }, resist = { "ice" } }

F.rd_consultant = {
  name = "THE CONSULTANT", short = "CONSULTANT", tier = 38, shape = "caster", sprite = "rd_consultant", family = "staff", weak = { "holy" },
  boss = { hpx = 0.9, phases = {
    { at = 100, moves = { { "rd_round", 5 }, { "rd_line", 3 } }, every = 5, big = "rd_prognosis" },
    { at = 66, moves = { { "rd_round", 4 }, { "rd_notes", 3 } }, every = 4, big = "rd_prognosis", say = "HE ASKS FOR A SECOND OPINION", call = "rd_students", summon = "rd_reader" },
    { at = 33, moves = { { "rd_line", 4 }, { "rd_round", 4 } }, every = 3, big = "rd_prognosis", say = "VISITING HOURS ARE OVER", speedUp = 1 },
  } },
}
F.rd_nulliira = {
  name = "MOTHER NULLIIRA", short = "NULLIIRA", tier = 40, shape = "caster", sprite = "rd_nulliira", family = "boss", resist = { "mind" }, weak = { "fire" },
  boss = { hpx = 0.78, phases = {
    { at = 100, moves = { { "rd_legs", 5 }, { "rd_hush", 2 } }, every = 5, big = "rd_slept" },
    { at = 66, moves = { { "rd_legs", 4 }, { "rd_drop", 3 } }, every = 4, big = "rd_slept", say = "THE VOICE LOSES ITS PLACE", call = "rd_children", summon = "rd_risen" },
    { at = 33, moves = { { "rd_drop", 3 }, { "rd_legs", 3 }, { "rd_hush", 2 } }, every = 3, big = "rd_slept", say = "SHE IS TRYING TO LET GO", speedUp = 1 },
  } },
}
-- All her power and nobody home. Her words come back as moves, and she spends the last third of it with no one to tell her to stop.
F.rd_husk = {
  name = "WHAT'S LEFT", tier = 42, shape = "caster", sprite = "vierrela_husk", family = "boss", resist = { "mind" },
  boss = { hpx = 0.66, phases = {
    { at = 100, moves = { { "rd_incision", 4 }, { "rd_sit", 3 } }, every = 5, big = "rd_goodnight" },
    { at = 70, moves = { { "rd_incision", 4 }, { "rd_restful", 3 }, { "rd_sit", 2 } }, every = 4, big = "rd_goodnight", say = "IT FINDS ANOTHER WORD", call = "rd_hive", summon = "rd_flayer" },
    { at = 35, moves = { { "rd_restful", 4 }, { "rd_incision", 4 } }, every = 3, big = "rd_goodnight", say = "THERE IS NOBODY IN THERE", speedUp = 1 },
  } },
}
F.rd_zal = {
  name = "ZALABARULA", tier = 42, shape = "caster", sprite = "rd_zal", family = "boss", resist = { "mind" }, weak = { "holy", "fire" },
  boss = { hpx = 0.95, phases = {
    { at = 100, moves = { { "rd_tendril", 5 }, { "rd_dictate", 3 } }, every = 5, big = "rd_held" },
    { at = 66, moves = { { "rd_tendril", 4 }, { "rd_sip", 3 } }, every = 4, big = "rd_held", say = "THE HUNGER DOES NOT ASK HIM", summon = "rd_rover" },
    { at = 33, moves = { { "rd_dictate", 4 }, { "rd_sip", 3 } }, every = 3, big = "rd_held", say = "HE IS HOLDING HIMSELF BACK", speedUp = 1 },
  } },
}
-- Tier 50, and the only reason to grind in the whole game. He hunts: fast, and worse from behind.
F.rd_chylbad = {
  name = "CHYLBAD", tier = 50, shape = "quick", sprite = "chylbad", family = "dragon", size = 3, weak = { "fire" }, resist = { "ice" }, goldx = 2,
  boss = { hpx = 1.05, phases = {
    { at = 100, moves = { { "rd_fang", 5 }, { "rd_rime", 2 } }, every = 5, big = "rd_white" },
    { at = 70, moves = { { "rd_fang", 4 }, { "rd_stalk", 3 } }, every = 4, big = "rd_white", say = "HE GOES VERY QUIET", speedUp = 1 },
    { at = 40, moves = { { "rd_stalk", 4 }, { "rd_rime", 3 } }, every = 4, big = "rd_white", say = "HE HAS STOPPED PLAYING", call = "rd_shards", summon = "rd_shard" },
    { at = 15, moves = { { "rd_stalk", 5 }, { "rd_fang", 3 } }, every = 3, big = "rd_white", say = "NOTHING LIVES THIS LONG BY DYING", speedUp = 1 },
  } },
}

local E = R.encounters

E.rd_e_arm_1 = { foes = { "rd_shed", "rd_shed", "rd_shed" }, flee = true, bg = "cave" }
E.rd_e_arm_2 = { foes = { "rd_hook", "rd_shed" }, flee = true, bg = "cave" }
E.rd_e_arm_3 = { foes = { "rd_walker", "rd_walker" }, flee = true, bg = "cave" }
E.rd_e_road_1 = { foes = { "rd_mantle", "rd_mantle", "rd_mantle" }, flee = true, bg = "cave" }
E.rd_e_road_2 = { foes = { "rd_moth", "rd_moth" }, flee = true, bg = "cave" }
E.rd_e_road_3 = { foes = { "rd_hulk" }, flee = true, bg = "cave" }
E.rd_e_road_4 = { foes = { "rd_reader", "rd_walker" }, flee = true, bg = "chain" }
E.rd_e_web_1 = { foes = { "rd_risen" }, flee = true, bg = "web" }
E.rd_e_web_2 = { foes = { "rd_phase", "rd_phase" }, flee = true, bg = "web" }
E.rd_e_web_3 = { foes = { "rd_ettercap", "rd_risen" }, flee = true, bg = "web" }
E.rd_e_house_1 = { foes = { "rd_risen", "rd_risen" }, flee = true, bg = "marble" }
E.rd_e_house_2 = { foes = { "rd_ettercap", "rd_phase" }, flee = true, bg = "marble" }
E.rd_e_salt_1 = { foes = { "rd_manta", "rd_manta" }, flee = true, bg = "brine" }
E.rd_e_salt_2 = { foes = { "rd_drowned", "rd_manta" }, flee = true, bg = "brine" }
E.rd_e_salt_3 = { foes = { "rd_drowned", "rd_drowned" }, flee = true, bg = "brine" }
E.rd_e_hive_1 = { foes = { "rd_rover", "rd_rover", "rd_rover" }, flee = true, bg = "ruin" }
E.rd_e_hive_2 = { foes = { "rd_flayer", "rd_rover" }, flee = true, bg = "ruin" }
E.rd_e_hive_3 = { foes = { "rd_flayer", "rd_flayer" }, flee = true, bg = "ruin" }
E.rd_e_gem_1 = { foes = { "rd_wyrm", "rd_wyrm" }, flee = true, bg = "snow" }
E.rd_e_gem_2 = { foes = { "rd_shard", "rd_wyrm" }, flee = true, bg = "snow" }
E.rd_e_gem_3 = { foes = { "rd_shard", "rd_shard" }, flee = true, bg = "snow" }
E.rd_e_consultant = { foes = { "rd_consultant" }, flee = false, bg = "chain", boss = true }
E.rd_e_nulliira = { foes = { "rd_nulliira" }, flee = false, bg = "marble", boss = true }
E.rd_e_husk = { foes = { "rd_husk" }, flee = false, bg = "marble", boss = true }
E.rd_e_zal = { foes = { "rd_zal" }, flee = false, bg = "ruin", boss = true }
E.rd_e_chylbad = { foes = { "rd_chylbad" }, flee = false, bg = "snow", boss = true }

R.art.rd_shed = "A round lid of grey skin the size of a cart wheel, shed from something much larger, dragging itself along on short ringed tendrils, one eye in the middle."
R.art.rd_rover = "A bare grey brain scuttling on four clawed legs, with no head to go with it."
R.art.rd_wyrm = "A thin white dragon the size of a horse, bulbous-eyed, with a gecko's flat face, clinging sideways to the wall."
R.art.rd_shard = "A man-high stack of white crystal blades, walking, with an old hunter's helmet stuck somewhere in the middle."
R.art.rd_consultant = "A tall thin Clinic consultant in a long white coat, a clean bandage over his eyes, walking very upright with a clipboard, smiling at the air."
R.art.rd_nulliira = "A thin old drider in a spotless white apron, eyes shut, standing bolt upright with a finger to her lips, a small clipboard in the other hand."
R.art.rd_zal = "A mind flayer dried yellow as an old tooth, naked and very thin, its four long tendrils knotted round each other."
R.art.rd_thread = "A short length of black thread tied in a hard knot round a broken spar."
R.art.rd_weight = "A big wicker basket on a line, half full of rubble."
R.art.rd_crate = "A heavy shipping crate stencilled FRAGILE many times over, in many alphabets, and shifting very slightly."
R.art.rd_fall = "A wall of fallen white salt filling the stair from side to side."
R.art.rd_page = "A single torn leaf of paper lying on a wet stone floor, beside an empty chair."
R.art.rd_lens = "A great round lens of white crystal in a rusted hunter's frame, on a pivot, with a dead lamp behind it."
R.art.rd_gemwall = "A curtain of white crystal from floor to roof, with something pale and thin moving behind it."
R.art.rd_log = "A dead dragon hunter in frosted armour, sitting against the wall with a small book on one knee."

-- ---------------------------------------------------------------- the maps

local M = R.maps

-- Dangle's camp at the top, and the great bore round the outside, down to the Light. The arm went up through the middle.
M.rd_abyss = {
  name = "THE VIOLET ABYSS: THE ARMWAY", theme = "cave", savepoint = true,
  rows = {
    "############################",
    "#>.......###################",
    "###......###################",
    "###.......~~~~~~~~~~~~~~~###",
    "###.......~~~~~~~~~~~~~~~..#",
    "#####.####~~~~~~~~~~~~~~~#.#",
    "#####.####~~~~~~~~~~~~~~~#.#",
    "#.........~~~~~~~~~~~~~~~#.#",
    "#.###.####~~~~~~~~~~~~~~~#.#",
    "#.###.####~~~~~~~~~~~~~~~#.#",
    "#.....####~~~~~~~~~~~~~~~#.#",
    "#.##.#####################.#",
    "#.##.......................#",
    "#.##.####.#########.#####.##",
    "#....####.###.......#####.##",
    "#########.###.#####.#####.##",
    "#.............#####.......##",
    "#.#################.#####.##",
    "#.........#########....>####",
    "############################",
  },
  npcs = {
    { id = "rd_dangle", x = 6, y = 3, sprite = "villager", script = "rd_talk_dangle" },
    { id = "rd_basket", x = 5, y = 5, sprite = "ud_basket", script = "rd_talk_basket", when = "rd_touarch_in" },
  },
  steps = {
    { x = 3, y = 2, script = "rd_too_soon", unless = "rs_done" },
    { x = 4, y = 2, script = "rd_scene_lip", once = true },
    { x = 6, y = 7, script = "rd_read_boots", once = true },
    { x = 16, y = 15, script = "rd_read_ring", once = true },
  },
  chests = {
    { id = "c1", x = 26, y = 5, give = "xpotion", n = 2 },
    { id = "c2", x = 10, y = 19, gold = 3000 },
    { id = "c3", x = 9, y = 4, give = "hiether", n = 2 },
    { id = "c4", x = 26, y = 18, give = "feather", n = 2 },
  },
  foes = {
    { id = "f1", x = 2, y = 10, enc = "rd_e_arm_1", sprite = "rd_shed" },
    { id = "f2", x = 13, y = 13, enc = "rd_e_arm_2", sprite = "ud_hookhorror" },
    { id = "f3", x = 25, y = 13, enc = "rd_e_arm_3", sprite = "blighted" },
    { id = "f4", x = 17, y = 15, enc = "rd_e_arm_1", sprite = "rd_shed" },
    { id = "f5", x = 6, y = 17, enc = "rd_e_arm_3", sprite = "blighted" },
    { id = "f6", x = 20, y = 17, enc = "rd_e_arm_2", sprite = "ud_hookhorror" },
  },
  exits = {
    { x = 2, y = 2, world = { 60, 27 } },
    { x = 24, y = 19, map = "rd_touarch", mx = 3, my = 2, dir = 2 },
  },
}

-- Touarch with its east side gone down the crack. The inn is north-west, Hask north-east, the Light in the rock in the middle, and
-- the Queen's house south-west. The Pillar Road leaves by the south gate.
M.rd_touarch = {
  name = "TOUARCH", theme = "city", savepoint = true,
  rows = {
    "############################",
    "#>.........................#",
    "#.hh+hhh.##########.hhh+hhh#",
    "#.h....h.##########.h.....h#",
    "#.h....h.##########.h.....h#",
    "#.hhhhhh.##########.hhhhhhh#",
    "#........##########........#",
    "#........##########........#",
    "#........##########........#",
    "#.hhhhhh.##########.hhhhhhh#",
    "#.h....h.##.....###.h.....h#",
    "#.h....h.##.....###.h.....h#",
    "#.hh+hhh.####+#####.hhh+hhh#",
    "#..........................#",
    "#.hhhh+hhhhh.....~~~~~~~~~~#",
    "#.h........h.....~~~~~~~~~~#",
    "#.h........h.....~~~~~~~~~~#",
    "#.hhhhhhhhhh.....~~~~~~~~~~#",
    "#................~~~~~~~~~~#",
    "##############>#############",
  },
  npcs = {
    { id = "rd_mag", x = 7, y = 4, sprite = "villager", script = "rd_talk_mag" },
    { id = "rd_hask", x = 25, y = 5, sprite = "villager", script = "rd_talk_hask" },
    { id = "rd_olive", x = 8, y = 16, sprite = "villager", script = "rd_talk_olive" },
    { id = "rd_kindle", x = 13, y = 11, sprite = "villager", script = "rd_talk_kindle" },
    { id = "rd_tally", x = 16, y = 11, sprite = "villager", script = "rd_talk_tally" },
    { id = "rd_sevria", x = 12, y = 12, sprite = "villager", script = "rd_talk_sevria" },
    { id = "rd_murgrum", x = 16, y = 12, sprite = "villager", script = "rd_talk_murgrum", when = "side_lovers" },
    { id = "rd_pell", x = 15, y = 16, sprite = "villager", script = "rd_talk_pell" },
    { id = "rd_tam", x = 22, y = 8, sprite = "villager", script = "rd_talk_tam" },
    { id = "rd_winder", x = 3, y = 7, sprite = "villager", script = "rd_talk_winder" },
    { id = "rd_fettle", x = 25, y = 8, sprite = "villager", script = "rd_talk_fettle", when = "ud_fettle_free" },
  },
  steps = {
    { x = 3, y = 2, script = "rd_scene_touarch", unless = "rd_touarch_in" },
  },
  chests = {
    { id = "c1", x = 25, y = 12, give = "elixir", n = 1 },
    { id = "c2", x = 4, y = 11, gold = 2500 },
  },
  exits = {
    { x = 2, y = 2, map = "rd_abyss", mx = 23, my = 19, dir = 4 },
    { x = 15, y = 20, script = "rd_gate_shut", unless = "rd_heard_ward" },
    { x = 15, y = 20, map = "rd_pillars", mx = 2, my = 9, dir = 2, when = "rd_heard_ward" },
  },
}

-- The road under the world, after a fire: the Great Pillar is a hole. Touarch is west, Strathe's chasm east, the lantern overhead by
-- the ladder at the north, and the crack to the Diamond Cave at the south.
M.rd_pillars = {
  name = "THE BROKEN ROAD", theme = "cave",
  rows = {
    "##############>###############",
    "#............................#",
    "#.##..##..##..##..##..##..##.#",
    "#..........~~~~~~~~..........#",
    "#.##..##...~~~~~~~~.##..##...#",
    "#..........~~~~~~~~..........#",
    "#.##..##...~~~~~~~~.##..##...#",
    "#............................#",
    ">............................>",
    "#............................#",
    "#.##..##..##..##..##..##..##.#",
    "#....................~~~~~~~.#",
    "#.##..##..##..##..##.~~~~~~~.#",
    "#....................~~~~~~~.#",
    "#.##..##..##..##..##.~~~~~~~.#",
    "#............................#",
    "########>#####################",
  },
  npcs = {
    { id = "rd_moss", x = 8, y = 10, sprite = "villager", script = "rd_talk_moss" },
    { id = "rd_thread_a", x = 10, y = 12, sprite = "rd_thread", script = "rd_thread_a", unless = "rd_thread_a" },
    { id = "rd_thread_b", x = 20, y = 8, sprite = "rd_thread", script = "rd_thread_b", unless = "rd_thread_b" },
    { id = "rd_thread_c", x = 22, y = 2, sprite = "rd_thread", script = "rd_thread_c", unless = "rd_thread_c" },
  },
  steps = {
    { x = 2, y = 9, script = "rd_scene_road", once = true },
    { x = 15, y = 8, script = "rd_read_signs", once = true },
  },
  chests = {
    { id = "c1", x = 29, y = 16, gold = 3000 },
    { id = "c2", x = 2, y = 16, give = "xpotion", n = 2 },
    { id = "c3", x = 29, y = 2, give = "hiether", n = 2 },
  },
  foes = {
    { id = "f1", x = 6, y = 4, enc = "rd_e_road_3", sprite = "ud_umber" },
    { id = "f2", x = 23, y = 4, enc = "rd_e_road_1", sprite = "ud_mantle" },
    { id = "f3", x = 12, y = 8, enc = "rd_e_road_2", sprite = "vt_moth" },
    { id = "f4", x = 12, y = 12, enc = "rd_e_road_1", sprite = "ud_mantle" },
    { id = "f5", x = 24, y = 9, enc = "rd_e_road_4", sprite = "vt_reader" },
    { id = "f6", x = 18, y = 16, enc = "rd_e_road_3", sprite = "ud_umber" },
    { id = "f7", x = 5, y = 14, enc = "rd_e_road_2", sprite = "vt_moth" },
  },
  exits = {
    { x = 1, y = 9, map = "rd_touarch", mx = 15, my = 19, dir = 1 },
    { x = 15, y = 1, script = "rd_ladder_shut", unless = "rd_threads" },
    { x = 15, y = 1, map = "rd_ward", mx = 10, my = 14, dir = 1, when = "rd_threads" },
    { x = 30, y = 9, script = "rd_east_shut", unless = "rd_cleric_in" },
    { x = 30, y = 9, map = "rd_underweb", mx = 2, my = 10, dir = 2, when = "rd_cleric_in" },
    { x = 9, y = 17, script = "rd_crack_shut", unless = "rd_pell_map" },
    { x = 9, y = 17, map = "rd_crystal", mx = 3, my = 2, dir = 2, when = "rd_pell_map" },
  },
}

-- A Vault lantern, snagged in the broken pillars. The ladder comes up into the hall, the ward is north, and the stores are either side.
M.rd_ward = {
  name = "THE LAST LANTERN", theme = "chain", savepoint = true,
  rows = {
    "####################",
    "#..................#",
    "#..................#",
    "#..................#",
    "#hhhhhhhhh+hhhhhhhh#",
    "#.......h....h.....#",
    "#.......h....h.....#",
    "#.......+....+.....#",
    "#.......h....h.....#",
    "#.......h....h.....#",
    "#hhhhhhhh.hhhhhhhhh#",
    "#########.##########",
    "#########.##########",
    "#########.##########",
    "#########>##########",
  },
  npcs = {
    { id = "rd_w_bruna", x = 4, y = 2, sprite = "villager", script = "rd_talk_bruna" },
    { id = "rd_w_orderly", x = 8, y = 2, sprite = "villager", script = "rd_talk_orderly" },
    { id = "rd_w_eyes", x = 13, y = 2, sprite = "villager", script = "rd_talk_eyes" },
    { id = "rd_sister", x = 17, y = 3, sprite = "villager", script = "rd_scene_ward", unless = "rd_cleric_in" },
    { id = "rd_ilzra", x = 12, y = 8, sprite = "villager", script = "rd_talk_ilzra", unless = "rd_cleric_in" },
    { id = "rd_ilzra_w", x = 17, y = 3, sprite = "villager", script = "rd_talk_ilzra", when = "rd_cleric_in" },
  },
  steps = {
    { x = 11, y = 4, script = "rd_scene_ward", unless = "rd_cleric_in" },
  },
  chests = {
    { id = "c1", x = 2, y = 6, give = "panacea", n = 3 },
    { id = "c2", x = 19, y = 10, give = "xpotion", n = 2 },
    { id = "c3", x = 2, y = 10, gold = 3000 },
  },
  exits = {
    { x = 10, y = 15, map = "rd_pillars", mx = 15, my = 2, dir = 3 },
  },
}

-- What's left of the web. Mmrk at the head of the last strand, with a counterweight basket out at each far end.
M.rd_underweb = {
  name = "THE UNDERWEB", theme = "web",
  rows = {
    "############>#############",
    "#~~~~~~~~~~~...~~~~~~~~~~#",
    "#~~~~~~~~~~~~.~~~~~~~~~~~#",
    "#~~~..................~~~#",
    "#~~~.~~~~~~~~.~~~~~~~.~~~#",
    "#~~~.~~~~~~~~.~~~~~~~.~~~#",
    "#~~~.~~~~~~.....~~~~~.~~~#",
    "#~~~.~~~~~~.....~~~~~.~~~#",
    "#~~~.~~~~~~.....~~~~~.~~~#",
    ">.....~~~~~~~.~~~~~~~.~~~#",
    "#~~~~~~~~~~~~.~~~~~~~.~~~#",
    "#~~~~~~.................~#",
    "#~~~~~~.~~~~~~~~~~~~~~~.~#",
    "#~~~~~~.~~~~~~~~~~~~~~~.~#",
    "#~~~~~...~~~~~~~~~~~~...~#",
    "#~~~~~...~~~~~~~~~~~~...~#",
    "##########################",
  },
  npcs = {
    { id = "rd_mmrk", x = 14, y = 3, sprite = "villager", script = "rd_talk_mmrk", unless = "rd_lift_up" },
    { id = "rd_mmrk_2", x = 15, y = 2, sprite = "villager", script = "rd_talk_mmrk", when = "rd_lift_up" },
    { id = "rd_weight_a", x = 7, y = 16, sprite = "rd_weight", script = "rd_weight_a" },
    { id = "rd_weight_b", x = 23, y = 16, sprite = "rd_weight", script = "rd_weight_b" },
  },
  steps = {
    { x = 2, y = 10, script = "rd_scene_web", once = true },
  },
  chests = {
    { id = "c1", x = 16, y = 9, give = "xpotion", n = 2 },
    { id = "c2", x = 9, y = 16, give = "hiether", n = 3 },
    { id = "c3", x = 22, y = 16, give = "elixir", n = 1 },
    { id = "c4", x = 12, y = 7, gold = 3500 },
  },
  foes = {
    { id = "f1", x = 5, y = 7, enc = "rd_e_web_2", sprite = "ud_phase" },
    { id = "f2", x = 10, y = 4, enc = "rd_e_web_1", sprite = "drider" },
    { id = "f3", x = 14, y = 11, enc = "rd_e_web_3", sprite = "ettercap" },
    { id = "f4", x = 8, y = 13, enc = "rd_e_web_2", sprite = "ud_phase" },
    { id = "f5", x = 18, y = 12, enc = "rd_e_web_1", sprite = "drider" },
    { id = "f6", x = 24, y = 14, enc = "rd_e_web_3", sprite = "ettercap" },
  },
  exits = {
    { x = 1, y = 10, map = "rd_pillars", mx = 29, my = 9, dir = 4 },
    { x = 13, y = 1, map = "rd_strathe", mx = 14, my = 17, dir = 1 },
  },
}

-- The north side of the city is gone, the Queen's hall with it. The Commons and the Hunt still stand, the Quiet House is east of
-- the avenue, and the Web Road leaves by the west end of the low street.
M.rd_strathe = {
  name = "STRATHE THE WEBBED RECLUSE", theme = "web", savepoint = true,
  rows = {
    "############################",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#..........................>",
    "#..hhh+hhh.........hhh+hhh.#",
    "#..h.....h.........h.....h.#",
    "#..h.....h.........h.....h.#",
    "#..hhhhhhh.........hhhhhhh.#",
    ">..........................#",
    "#~~~~~~~~...........~~~~~~~#",
    "#~~~~~~~~...........~~~~~~~#",
    "#~~~~~~~~~~~.....~~~~~~~~~~#",
    "#~~~~~~~~~~~.....~~~~~~~~~~#",
    "#~~~~~~~~~~~~.~~~~~~~~~~~~~#",
    "#############>##############",
  },
  npcs = {
    { id = "rd_commons", x = 8, y = 10, sprite = "villager", script = "rd_talk_commons" },
    { id = "rd_houndrin", x = 24, y = 10, sprite = "villager", script = "rd_talk_houndrin" },
    { id = "rd_sael", x = 12, y = 10, sprite = "villager", script = "rd_talk_sael", unless = "rd_jezzara_in" },
    { id = "rd_iliss", x = 17, y = 11, sprite = "villager", script = "rd_talk_iliss" },
    { id = "rd_rail_1", x = 10, y = 7, sprite = "villager", script = "rd_talk_rail" },
    { id = "rd_rail_2", x = 16, y = 7, sprite = "villager", script = "rd_talk_rail" },
    { id = "rd_rail_3", x = 19, y = 14, sprite = "villager", script = "rd_talk_rail" },
  },
  steps = {
    { x = 14, y = 17, script = "rd_scene_strathe", unless = "rd_strathe_in" },
  },
  chests = {
    { id = "c1", x = 5, y = 10, give = "xpotion", n = 2 },
    { id = "c2", x = 21, y = 9, gold = 3500 },
  },
  exits = {
    { x = 14, y = 18, map = "rd_underweb", mx = 13, my = 2, dir = 3 },
    { x = 28, y = 7, map = "rd_quiet", mx = 2, my = 6, dir = 2 },
    { x = 1, y = 12, script = "rd_road_shut", unless = "rd_jezzara_in" },
    { x = 1, y = 12, map = "rd_stair", mx = 3, my = 2, dir = 2, when = "rd_jezzara_in" },
  },
}

-- As it was, and white, and the wards are empty. The Cradle is down at the far end behind the antechamber.
M.rd_quiet = {
  name = "THE QUIET HOUSE", theme = "marble",
  rows = {
    "########################",
    "#.......h.......h......#",
    "#.......h.......h......#",
    "#.......h.......h......#",
    "#hhh+hhhhhhh+hhhhhh+hhh#",
    ">......................#",
    "#hhh+hhhhhhh+hhhhhh+hhh#",
    "#.......h.......h......#",
    "#.......h.......h......#",
    "#.......h.......h......#",
    "#hhhhhhhhhhhhhhhhhh+hhh#",
    "###############h.......#",
    "###############h.......#",
    "###############h.......#",
    "########################",
  },
  npcs = {
    { id = "rd_halryna_c", x = 20, y = 14, sprite = "villager", script = "rd_talk_cradle" },
    { id = "rd_jez_c", x = 19, y = 14, sprite = "villager", script = "rd_scene_cradle", unless = "rd_jezzara_in" },
    { id = "rd_sael_c", x = 18, y = 14, sprite = "villager", script = "rd_talk_sael", when = "rd_jezzara_in" },
  },
  steps = {
    { x = 13, y = 3, script = "rd_read_records", once = true },
    { x = 13, y = 8, script = "rd_read_drawers", once = true },
    { x = 20, y = 12, script = "rd_scene_cradle", unless = "rd_jezzara_in" },
  },
  chests = {
    { id = "c1", x = 22, y = 2, give = "panacea", n = 2 },
    { id = "c2", x = 7, y = 8, give = "xpotion", n = 2 },
    { id = "c3", x = 15, y = 10, give = "elixir", n = 1 },
  },
  foes = {
    { id = "f1", x = 4, y = 3, enc = "rd_e_house_1", sprite = "drider" },
    { id = "f2", x = 10, y = 2, enc = "rd_e_house_2", sprite = "ettercap" },
    { id = "f3", x = 4, y = 9, enc = "rd_e_house_1", sprite = "drider" },
    { id = "f4", x = 21, y = 8, enc = "rd_e_house_2", sprite = "ud_phase" },
    { id = "f5", x = 15, y = 6, enc = "rd_e_house_1", sprite = "drider" },
  },
  exits = {
    { x = 1, y = 6, map = "rd_strathe", mx = 27, my = 7, dir = 4 },
  },
}

-- The stair down the cavern wall, blocked by a salt fall, with the crate on the ledge west of the top. The bridge is one square
-- wide all the way across, and it stops being a bridge halfway.
M.rd_stair = {
  name = "THE SALT STAIR", theme = "coral",
  rows = {
    "##############################",
    "#>.........................###",
    "#####.###~~~~~~~~~~~~~~~~..###",
    "#####.###~~~~~~~~~~~~~~~~~.###",
    "#...........#~~~~~~~~~~~~~.###",
    "#.##.######.#~~~~~~~~~~~~~..##",
    "#.##.######.#~~~~~~~~~~~~~~.##",
    "#....#......#~~~~~~~~~~~~~~.##",
    "#############~~~~~~~~~~~~~~.##",
    "#############~~~~~~~~~~.....##",
    "#############~~~~~~~~~~.....##",
    "#############~~~~~~~~~~.....##",
    "#############~~~~~~~~~~~~~~.##",
    "#############~~~~~~~~~~~~~~.##",
    "#############~~~~~~~~~~~~~~.##",
    "###~~~~~~~~~~~~~~~~~~~~~~~~.##",
    ">...........................##",
    "###~~~~~~~~~~~~~~~~~~~~~~~~###",
    "##############################",
  },
  npcs = {
    { id = "rd_fall", x = 28, y = 7, sprite = "rd_fall", script = "rd_talk_fall", unless = "rd_gate_open" },
    { id = "rd_crate", x = 12, y = 8, sprite = "rd_crate", script = "rd_talk_crate", unless = "rd_crate_got" },
    { id = "rd_ibbit", x = 26, y = 11, sprite = "villager", script = "rd_talk_ibbit" },
  },
  steps = {
    { x = 3, y = 2, script = "rd_scene_rain", once = true },
    { x = 14, y = 17, script = "rd_read_mother", once = true },
  },
  chests = {
    { id = "c1", x = 2, y = 8, give = "hiether", n = 3 },
    { id = "c2", x = 24, y = 10, gold = 4000 },
    { id = "c3", x = 24, y = 12, give = "feather", n = 3 },
  },
  foes = {
    { id = "f1", x = 20, y = 2, enc = "rd_e_salt_1", sprite = "ud_manta" },
    { id = "f2", x = 8, y = 5, enc = "rd_e_salt_3", sprite = "ud_drowned" },
    { id = "f3", x = 28, y = 15, enc = "rd_e_salt_1", sprite = "ud_manta" },
    { id = "f4", x = 28, y = 11, enc = "rd_e_salt_2", sprite = "ud_drowned" },
    { id = "f5", x = 22, y = 17, enc = "rd_e_salt_3", sprite = "ud_drowned" },
    { id = "f6", x = 7, y = 17, enc = "rd_e_salt_2", sprite = "ud_manta" },
  },
  exits = {
    { x = 2, y = 2, map = "rd_strathe", mx = 2, my = 12, dir = 2 },
    { x = 1, y = 17, map = "rd_crysathula", mx = 25, my = 8, dir = 4 },
  },
}

-- The same thin street, with the rain coming in. The hatch to the Old Hive is in the street by the research wing, broken open from below.
M.rd_crysathula = {
  name = "CRYSATHULA", theme = "city", savepoint = true,
  rows = {
    "##########################",
    "#~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~hhhhhhh~~~hhhhhhhh~~~~#",
    "#~~h.....h~~~h......h~~~~#",
    "#~~h.....h~~~h......h~~~~#",
    "#~~hhh+hhh~~~hhh+hhhh~~~~#",
    "#~~......................#",
    ">........................>",
    "#~~.......>..............#",
    "#~~hhhh+hhh~~hhhh+hhhh~~~#",
    "#~~h......h~~h.......h~~~#",
    "#~~h......h~~h.......h~~~#",
    "#~~hhhhhhhh~~hhhhhhhhh~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~#",
    "##########################",
  },
  npcs = {
    { id = "rd_zhar", x = 23, y = 7, sprite = "villager", script = "rd_talk_zhar" },
    { id = "rd_sult", x = 13, y = 7, sprite = "villager", script = "rd_talk_sult" },
    { id = "rd_sweeper", x = 18, y = 9, sprite = "villager", script = "rd_talk_sweeper" },
    { id = "rd_uln", x = 7, y = 4, sprite = "villager", script = "rd_talk_uln" },
    { id = "rd_pod", x = 17, y = 4, sprite = "villager", script = "rd_talk_pod" },
    { id = "rd_vel", x = 8, y = 12, sprite = "villager", script = "rd_talk_vel" },
  },
  steps = {
    { x = 25, y = 8, script = "rd_scene_crysathula", unless = "rd_crys_in" },
  },
  chests = {
    { id = "c1", x = 20, y = 5, give = "elixir", n = 1 },
    { id = "c2", x = 19, y = 11, give = "feather", n = 2 },
  },
  exits = {
    { x = 26, y = 8, map = "rd_stair", mx = 2, my = 17, dir = 2 },
    { x = 1, y = 8, map = "rd_nest", mx = 11, my = 13, dir = 1 },
    { x = 11, y = 9, map = "rd_hive", mx = 3, my = 2, dir = 2 },
  },
}

-- One long hall, the mother brain behind cracked glass. The stair at the end of the east bay is the way to the end of the game.
M.rd_nest = {
  name = "THE CORTEX NEST", theme = "marble",
  rows = {
    "####################",
    "#~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~#",
    "#~~~~~h......h~~~~~#",
    "######h......h######",
    "######h......h######",
    "######h......h######",
    "######h......hhhhhh#",
    "######h...........>#",
    "######h......hhhhhh#",
    "######h......h######",
    "##########>#########",
    "####################",
  },
  npcs = {
    { id = "rd_vierrela", x = 11, y = 6, sprite = "villager", script = "rd_scene_nest", unless = "rd_husk_down" },
    { id = "rd_husk_f", x = 11, y = 6, sprite = "villager", script = "rd_talk_husk", when = "rd_husk_down" },
    { id = "rd_page", x = 9, y = 9, sprite = "rd_page", script = "rd_scene_page", when = "rd_husk_down", unless = "rd_done" },
  },
  steps = {
    { x = 11, y = 8, script = "rd_scene_nest", unless = "rd_husk_down" },
  },
  exits = {
    { x = 11, y = 14, map = "rd_crysathula", mx = 2, my = 8, dir = 2 },
    { x = 19, y = 11, script = "rd_way_down" },
  },
}

-- The Brain Sipper's first hive, grown and not built. Three chambers along the top, and his own room at the bottom of everything.
M.rd_hive = {
  name = "THE OLD HIVE", theme = "ruin",
  rows = {
    "########################",
    "#>......h.......h......#",
    "#######.h.......h......#",
    "#.......+.......+......#",
    "#.#####.h.......h......#",
    "#.#...#.h.......h......#",
    "#.#...#.hhhh.hhhhhhhh.##",
    "#.#...#.####.#######..##",
    "#.##.##.####.#######.###",
    "#............#######.###",
    "#.#########.########.###",
    "#...........########.###",
    "#.#########.hhhhhhhh+hh#",
    "#.#########.h.........h#",
    "#.....#####.h.........h#",
    "#.....#####.h.........h#",
    "#.....######h.........h#",
    "########################",
  },
  npcs = {
    { id = "rd_zal", x = 18, y = 16, sprite = "villager", script = "rd_scene_zal", unless = "side_zalabarula" },
  },
  steps = {
    { x = 3, y = 2, script = "rd_hive_in", once = true },
    { x = 13, y = 4, script = "rd_read_pool", once = true },
    { x = 20, y = 4, script = "rd_read_tablets", once = true },
    { x = 21, y = 14, script = "rd_scene_zal", unless = "side_zalabarula" },
  },
  chests = {
    { id = "c1", x = 5, y = 6, give = "xpotion", n = 2 },
    { id = "c2", x = 3, y = 16, give = "hiether", n = 3 },
    { id = "c3", x = 23, y = 2, give = "last_light" },
    { id = "c4", x = 12, y = 16, gold = 5000 },
  },
  foes = {
    { id = "f1", x = 8, y = 6, enc = "rd_e_hive_1", sprite = "rd_rover" },
    { id = "f2", x = 12, y = 2, enc = "rd_e_hive_2", sprite = "mindflayer" },
    { id = "f3", x = 19, y = 5, enc = "rd_e_hive_3", sprite = "mindflayer" },
    { id = "f4", x = 7, y = 10, enc = "rd_e_hive_1", sprite = "rd_rover" },
    { id = "f5", x = 21, y = 10, enc = "rd_e_hive_2", sprite = "mindflayer" },
  },
  exits = {
    { x = 2, y = 2, map = "rd_crysathula", mx = 11, my = 8, dir = 1 },
  },
}

-- Chylbad's natural hoard, grown in the rock. Three lens rooms in the middle band: light them all and the crystal curtain at the
-- bottom cracks. Off the route, and meant for a party of about fifty.
M.rd_crystal = {
  name = "THE DIAMOND CAVE", theme = "cave",
  rows = {
    "############################",
    "#>.....#.........#.........#",
    "######.#.........#.........#",
    "#......+.........+.........#",
    "#.####.#.........#.........#",
    "#.####.#.........#.........#",
    "#.####.####.#########.######",
    "#......####.#########.######",
    "#####.#####.#########.######",
    "#.........................##",
    "#.#######.#######.#######.##",
    "#.#.....#.#.....#.#.....#.##",
    "#.#.....#.#.....#.#.....#.##",
    "#.#.....+.#.....+.#.....+.##",
    "#.#.....#.#.....#.#.....#.##",
    "#.#######.#######.#######.##",
    "#.........................##",
    "#############.##############",
    "#~~~~~~~...........~~~~~~~~#",
    "#~~~~~~.............~~~~~~~#",
    "#~~~~~...............~~~~~~#",
    "#~~~~~~.............~~~~~~~#",
    "#~~~~~~~...........~~~~~~~~#",
    "############################",
  },
  npcs = {
    { id = "rd_log_a", x = 13, y = 2, sprite = "rd_log", script = "rd_read_log_a" },
    { id = "rd_log_b", x = 24, y = 5, sprite = "rd_log", script = "rd_read_log_b" },
    { id = "rd_lens_a", x = 5, y = 13, sprite = "rd_lens", script = "rd_lens_a" },
    { id = "rd_lens_b", x = 13, y = 13, sprite = "rd_lens", script = "rd_lens_b" },
    { id = "rd_lens_c", x = 21, y = 13, sprite = "rd_lens", script = "rd_lens_c" },
    { id = "rd_gemwall", x = 14, y = 18, sprite = "rd_gemwall", script = "rd_talk_gemwall", unless = "rd_wall_down" },
    { id = "rd_chylbad", x = 14, y = 22, sprite = "chylbad", script = "rd_scene_chylbad", unless = "side_chylbad" },
  },
  steps = {
    { x = 3, y = 2, script = "rd_crystal_in", once = true },
    { x = 14, y = 20, script = "rd_scene_chylbad", unless = "side_chylbad" },
  },
  chests = {
    { id = "c1", x = 26, y = 2, give = "elixir", n = 1 },
    { id = "c2", x = 4, y = 12, gold = 6000 },
    { id = "c3", x = 16, y = 15, give = "archon_crown" },
    { id = "c4", x = 23, y = 15, give = "xpotion", n = 3 },
  },
  foes = {
    { id = "f1", x = 12, y = 5, enc = "rd_e_gem_1", sprite = "rd_wyrm" },
    { id = "f2", x = 22, y = 3, enc = "rd_e_gem_2", sprite = "rd_shard" },
    { id = "f3", x = 7, y = 10, enc = "rd_e_gem_1", sprite = "rd_wyrm" },
    { id = "f4", x = 20, y = 10, enc = "rd_e_gem_3", sprite = "rd_shard" },
    { id = "f5", x = 12, y = 17, enc = "rd_e_gem_2", sprite = "rd_wyrm" },
    { id = "f6", x = 24, y = 17, enc = "rd_e_gem_3", sprite = "rd_shard" },
  },
  exits = {
    { x = 2, y = 2, map = "rd_pillars", mx = 9, my = 16, dir = 1 },
  },
}

-- ---------------------------------------------------------------- the Armway

S.rd_too_soon = {
  t("The ledge at the Lip has fallen in, and grey light comes up out of the ground. It isn't a place to go down alone. You stand at the edge until the wind changes. Then you go back up to find the others."),
  { world = { 60, 27 } },
}

S.rd_scene_lip = {
  t("The Lip is still here, mostly. The violet has gone out of the Abyss. What comes up now is grey, and it smells of wet rope."),
  t("Something came up through here a year ago, and it didn't use the stair. A bore as wide as a town goes down through the rock, scored all the way round with rings, each the size of a cart wheel."),
  owlin("Those are sucker marks. I'd like it in the notes that the arm which made them is still attached to something."),
  deserter("If anyone's left alive down there, friend, they'll want a doctor. And I know one sister who won't have walked out on them."),
}

S.rd_talk_dangle = {
  { when = "ud_boot", steps = {
    dangle("Your boot's still on the pile. I've had it dusted. That's not sentiment. It's stock."),
  } },
  dangle("Still here. Forty-two years on this pitch, and I've never had a single complaint. A lot of people have come up lately who don't say anything at all, but I don't count that."),
  ask(dangle("The stair's gone. There's the bore, if you don't mind what made it. What'll it be?"), {
    topic("Have you heard from below?", {
      dangle("Last thing up the basket line before it went: a note from a hard-faced woman in a black habit. It said SEND THREAD. No please. No thank you. I sent forty coils, at cost."),
      { when = "rd_cleric_in", steps = {
        cleric("I'm standing right here, you know. And that was not at cost."),
      }, other = {
        deserter("That's her. Oh, friend, that's her. She's alive, and she's rude."),
      } },
    }),
    { "We're going down.", {
      dangle("Left hand on the wall, then. If the wall looks back, apologise."),
    } },
    { "Show me what you've got.", {
      { shop = "rd_dangle" },
    } },
  }),
}

S.rd_talk_basket = {
  ask({ text = "The basket line has been mended, with a great many different kinds of knot." }, {
    { "Stay up here.", {} },
    { "Ride down to Touarch.", {
      t("It swings more than it did."),
      { warp = { "rd_touarch", 3, 2, 2 } },
    } },
  }),
}

S.rd_read_boots = {
  t("The cairn of boots has outlived the road it stood on. Every left boot is still tied to the next. It doesn't look as if anyone is coming back for them."),
  { when = "ud_boot", steps = {
    t("Yours is near the top. It's got further than you expected."),
  } },
}

S.rd_read_ring = {
  t("One of the rings in the wall has a lid of grey skin over it, and the lid is moving. It turns as you go by, very slowly, the way a flower turns."),
  deserter("Keep walking, friend. It's only a scar. I've seen scars do worse."),
  t("Nobody mentions which of you it's turning to follow."),
}

-- ---------------------------------------------------------------- Touarch

S.rd_scene_touarch = {
  t("You come out of the bore into a line of warm yellow. It moves slowly as the hand of a clock, passes over you, and goes on. The Light of Touarch is still burning."),
  t("Half the city has gone down a crack you could lose a town in, and gnomes and duergar are asleep on the plaza in rows, side by side, which you'd been told would never happen."),
  deserter("The keeper of the Light sees further than anyone down here. If our sister's anywhere below, friend, that's who'll know. The door's in the rock, in the middle of town."),
  { set = "rd_touarch_in" },
}

S.rd_gate_shut = {
  t("A small gnome with a large ledger is sitting across the south gate. She'd want to write down where you're going, she says, and you don't seem to know. Have you tried the keeper of the Light?"),
}

S.rd_talk_kindle = {
  { when = "rd_heard_ward", steps = {
    { when = "rd_cleric_in", steps = {
      kindle("You found her, then. Good. She's had the last of my coal, and she told me off about the size of the lumps."),
    }, other = {
      kindle("The threads start east of the south gate. Black ones, knee high. She's very particular about the knots."),
    } },
  }, other = {
    kindle("Tollo Kindle. Forty tons a night, that hopper took, and we ran out of coal in the spring. Don't ask what's going in it now. Ask Keeper Tally. He's reading it out."),
    ask(kindle("Who have you lost? Everyone who comes in has lost somebody. I keep a list."), {
      topic("What do you see from up there now?", {
        kindle("Those folk at the edge of the beam, with no lamps? They've come in closer. They stand with their backs to us. I think they're waiting for somebody to go by."),
      }),
      { "A woman in a black habit. A sister of the Raven Queen.", {
        kindle("Her. She comes in for coal, and she tells me off. There's a lantern hung up in the broken pillars, east of here, a great glass thing from the Lower Dark. It came up with the arm and got left."),
        kindle("She's made a ward in it, for the ones too far gone for us. She's tied black threads along the Road, so her stretcher parties can find the ladder. Follow those."),
        { set = "rd_heard_ward" },
      } },
    }),
  } },
}

S.rd_talk_tally = {
  t("A duergar in a visor stands at the hopper with a huge book open on his arm. He reads out one line in a level voice, rules it through, tears out the page and feeds it to the fire. Overhead the Light goes round."),
  tally("Number twenty-two thousand and six. 'A gnome sat in the wrong chair.' Struck."),
  { when = "ud_grudge_filed", steps = {
    tally("You. I've kept back one page: 'Clinic, Plexian, surface. For everything.' It isn't going in the fire. A Keeper has to have something."),
  } },
  ask(tally("We carried the Book here on our backs when Blackhold came down. It has found eleven hundred people so far. Have you anything to declare?"), {
    { "Nothing to declare.", {
      tally("None at all? After the year we've had? I'm putting you down as suspicious."),
    } },
    topic("Sixty years of grudges, for this?", {
      tally("It has never done anyone so much good. I'm thinking of entering that as a grudge."),
    }),
  }),
}

S.rd_talk_olive = {
  t("A tiny, ancient gnome sits with her feet on an empty coal scuttle. A very old, very heavy crown hangs over the fire on a chain, and it's steaming."),
  { when = "side_lovers", steps = {
    olive("Dimsael's in the back room, with a stone table she brought down the road on a cart. We've stopped being polite. It's a great relief to us both."),
  } },
  ask(olive("You've got thin, the lot of you. And you, {hero}, you've still got that restful face. Did you have it looked at?"), {
    topic("Is that the Crown of Comets?", {
      olive("It's a soup pot. Holds four portions. I've had the right to rule every duergar living for sixty-four years, and this winter I finally did it. I ladled."),
    }),
    { "We'll be going on.", {
      olive("Mind how you go. There's soup on the way back, if there's a way back."),
    } },
  }),
}

S.rd_talk_mag = {
  ask(mag("Welcome to the Lost and Found. It's mostly Lost now, the beds are a hundred, and you can have the one without a duergar in it."), {
    { "A bed, please.", {
      { inn = 100 },
    } },
    { "Not tonight.", {} },
  }),
}

S.rd_talk_hask = {
  hask("Hask Cobble, general goods. Business has never been better. The previous owners have raised no objection. I've checked."),
  { choice = {
    { "Show me.", { { shop = "rd_hask" } } },
    { "Not just now.", {} },
  } },
}

S.rd_talk_pell = {
  { when = "side_chylbad", steps = {
    pell("You found him! Exactly where it says! Ten years in the Underdark, and I've finally been right. Would you sign the map? No? Quite understand. Your hands are shaking."),
  }, other = {
    { when = "rd_pell_map", steps = {
      pell("The crack on the south side of the Road, under the ninth pillar. Do come back and tell me if it's there."),
    }, other = {
      pell("Ah, fellow travellers! Sir Aldous Pell, of the Pell Expedition. Ten years now, and you'll never guess. I've had it the wrong way up!"),
      t("He spreads a map the size of a bedsheet across a barrel. It's all sea, as it always was. He turns it round, and it isn't."),
      ask(pell("That's the Road, those are the pillars, and that, marked HERE BE A WHITE LIZARD, is a cave. I've never once found anything where the map said it was. Would you care to be the first?"), {
        { "Show me where.", {
          pell("Splendid! South side of the Road, a crack full of white light. Chylbad the Diamond Fang. He has killed every hunter who ever found him, and eaten three dragons for variety."),
          owlin("I'd want us a good deal larger than we are, {hero}. Nothing else down here needs us to go and see him."),
          { set = "rd_pell_map" },
        } },
        { "Keep your map, Sir Aldous.", {
          pell("Quite right. I'll be off directly. First thing tomorrow."),
        } },
      }),
    } },
  } },
}

S.rd_talk_tam = {
  ask(tam("You're from Up. Did the sky stop? Mam says it's come down in places."), {
    { "It's still up there.", {
      tam("Oh, good. Who's holding it? We could send some pillars, but we've got fewer than we did."),
    } },
    { "Not yet.", {
      tam("That's what Mam says about the roof."),
    } },
  }),
}

S.rd_talk_winder = {
  ask(winder("Line's mended. It took a year, and every knot anyone knew. Basket to the Lip, about an hour, if you don't mind swinging."), {
    { "Stay here.", {} },
    { "Take us up.", {
      t("You'd still rather not talk about the ride."),
      { warp = { "rd_abyss", 4, 2, 2 } },
    } },
  }),
}

S.rd_talk_fettle = {
  fettle("It's the boots! Second class now, if you can believe it. They promoted me when everyone above me stopped turning up. I trim the marker lamps on the Road. It's lovely out there, if you like screaming. Mind the moths."),
}

S.rd_talk_sevria = {
  { when = "side_lovers", steps = {
    sevria("Coal book's nearly closed. There isn't any coal. I've got him doing the Book's accounts now, and he's stopped carrying the grudge. He gives it to me to hold."),
  }, other = {
    sevria("Blackhold's people came down the Road with the Book on their backs. I checked every face. There's a niche up there somewhere with a lot of ink in it."),
    sevria("I keep doing the coal sums. I've stopped getting them wrong. That's the worst of it."),
  } },
}

S.rd_talk_murgrum = {
  murgrum("We were married on the plaza. Keeper Tally entered it as a grudge, number forty thousand, one hundred and nineteen, and then he struck it. He says it's the proudest he's ever been of a ruler."),
}

-- ---------------------------------------------------------------- the Broken Road

S.rd_scene_road = {
  t("The Pillar Road used to be a forest. Now it's a forest after a fire. Where the Great Pillar stood there's a hole, with grey light coming up out of it."),
  t("High overhead, among the broken tops, something is caught: a lantern the size of a town hall, tilted on a yard of chain, and one window of it is lit."),
  owlin("That came from miles below us, and it's gone upward. One does wish somebody had consulted the physics."),
  deserter("Look for the threads, friend. She'd tie them at knee height, where a tired stretcher-bearer would see."),
}

--- A black thread. Any two of the three show the way to the ladder.
local function thread(flag, ...)
  local list = { ... }
  list[#list + 1] = { set = flag }
  list[#list + 1] = { count = { "rd_thread_a", "rd_thread_b", "rd_thread_c" }, at = 2, steps = {
    { when = "rd_threads", other = {
      t("That's enough to go on. All the knots pull the same way, north, past the old fork. If you stand at the far wall and look up, someone has let down a ladder."),
      { set = "rd_threads" },
    } },
  } }
  return list
end

S.rd_thread_a = thread("rd_thread_a",
  t("A black thread is tied at knee height round a fallen spar, pulled tight in a knot you've seen on a great many wrists."),
  deserter("That's hers. Nobody else alive can make a knot look disappointed in you."))

S.rd_thread_b = thread("rd_thread_b",
  t("A second thread, and with it a strip of bandage, lettered in a firm hand. STRETCHERS LEFT OF THE PIT. NOT RIGHT. I HAVE TOLD YOU."),
  owlin("She's told them. One can hear it from here."))

S.rd_thread_c = thread("rd_thread_c",
  t("A third thread, on the stump of a pillar. A sack of coal is hanging from it, off the ground, on a very small and very clean knife, driven in up to the handle."),
  deserter("Somebody's looking after her, friend, and doesn't want it known."))

S.rd_read_signs = {
  t("Two signposts still stand at the fork. BLACKHOLD, NORTH has been ruled through, very straight. On the other, the hard duergar capitals say TOUARCH, WEST. THIEVES (ROYAL)."),
  t("Below that someone has added, in the same capitals, with a great deal of pressure on the pen: HOME."),
}

S.rd_ladder_shut = {
  t("You can see the lantern from here, a long way up. You can't see any way of reaching it. Somebody must have one. There's that look about the place of somebody who has told people already."),
}

S.rd_east_shut = {
  deserter("East is Strathe, friend, and we'll get to it. I'm not walking past that lantern. Not with her in it."),
}

S.rd_crack_shut = {
  t("A crack in the rock on the south side of the Road, full of cold white light. It forks at once, and forks again. You'd want a map."),
}

S.rd_talk_moss = {
  t("A mushroom the height of a man turns toward you, faster than you'd have thought it could."),
  ask(moss("WE ARE THE ROAD-MOSS. WE WERE WRONG. SOMETHING IS URGENT."), {
    { "Sit down for a while.", {
      { heal = true },
      { save = true },
      t("You sit, and everyone feels much better. The moss keeps nudging you to get up."),
    } },
    topic("What's urgent?", {
      moss("THE THING THAT GROWS IN THE DARK AND WAITS. WE SAID IT WAS VERY LIKE US. WE HAVE MET IT NOW. WE WOULD LIKE TO WITHDRAW THE REMARK."),
      moss("YOU SMELL OF IT A LITTLE. NO OFFENCE. WE SMELL OF EVERYTHING."),
    }),
    { "Thanks. We'll keep moving.", {
      moss("YES. GOOD. GO. WHY ARE YOU STILL HERE."),
    } },
  }),
}

-- ---------------------------------------------------------------- the Last Lantern

S.rd_talk_ilzra = {
  { when = "rd_cleric_in", steps = {
    ilzra("All quiet. I've told them they're my subjects. I did the speech last night, the whole thing. Bed four cried. It's much better without a balcony."),
    { heal = true },
    t("She gets you all something hot, and you sit on the floor by the wall for a while. It's a clean floor."),
  }, other = {
    ilzra("Wipe your feet. Sorry, I've started saying it too. She's in the ward, north. Touarch takes in anyone, they said, and it did. I was a princess of Strathe, in a cave, and now I do bedpans."),
  } },
}

S.rd_talk_bruna = {
  bruna("Who's that? If you're the Clinic, I've still got my teeth. If you're the priest, I've still got my hate. If you've got a drink, I'm a very reasonable woman."),
  { when = "side_lovers", steps = {
    bruna("They read us the copper. He'd had it stolen, the great liar. I lay here laughing till that hard-faced girl came to see if I was dying. I was. It was worth it."),
  } },
}

S.rd_talk_orderly = {
  orderly("Rearguard, Vault column. I'm told we lost. Is there a form?"),
}

S.rd_talk_eyes = {
  t("An old gnome lies with her hands open. Her eyes go from side to side under the lids, slowly, like someone reading. So do the eyes in the next bed, at just the same speed."),
}

-- A wipe comes back to this: the talk is only heard once, and the fight is at the end of it.
S.rd_scene_ward = {
  { when = "rd_ward_told", other = {
    t("A long room lies on a slant, and somebody has wedged the beds level with books. Eleven beds, one lamp, and the smell of boiled linen. Everything in here that can be clean is clean."),
    t("At the far end a woman in a black habit sits on a stool with her back to you, holding someone's hand. She doesn't look round."),
    cleric("Wipe your feet. If that's the coal, it's late."),
    deserter("It isn't the coal."),
    t("Her shoulders stop. For a moment that's all. Then she lays the hand on the blanket, and ties something round the wrist. She takes her time over it. She would."),
    cleric("I'm sorry. He was going anyway, and I'd told him I'd stay."),
    t("She turns round. There's less of her under the hood than there was. She looks at the doctor, and the scholar, and at you for a long while, and then just behind your ear, the way you'd check a dressing."),
    { when = "rn_done", steps = {
      t("Her eye stops on Asphodel Syren for a moment, the way you'd look at a bill a hundred and ninety years overdue. It can wait."),
    } },
    cleric("You've let yourselves go. {hero}, you've a knot in your thread the size of a walnut. That's where you fell. I felt it catch."),
    ask(cleric("I kept hold. I said I would. Have you eaten?"), {
      topic("How did you get here?", {
        cleric("The lantern fell, and then it was going the wrong way. I sat with them all the way up. Somebody carried me down to the Road and back after, somebody who leaves no footprints. There was a very clean knife in the door."),
      }),
      topic("You sent for thread.", {
        cleric("Forty coils, and he sent a bill. I've twelve lengths left. Don't look like that. It's been a busy year."),
      }),
      { "We came to get you.", {
        cleric("Yes. I told the coal you'd be late."),
      } },
    }),
    cleric("I can't come. There's something that comes here every night, and I've nobody else who can stand in front of it."),
    t("Down in the hall a small bell rings twice, as if someone wished to be announced."),
    cleric("He's never late. A Clinic consultant, off the Vault column, and he read the line. He does his rounds now, one bed a night, and he reads it to them. What's asleep in them gets up. I'd be glad of the company."),
    { set = "rd_ward_told" },
  } },
  t("He comes in very upright, in a long white coat, with a clean bandage where his eyes should be. He doesn't look at any of you. He looks at the clipboard."),
  consultant("Good evening. Bed six, I think. And who are all these? Students? Do keep up. There's no need for anyone to be afraid."),
  { battle = "rd_e_consultant" },
  t("He folds up neatly, section by section, like a screen. His lips go on for a little while under the bandage, and then they stop in the middle of a word."),
  t("The sister goes down on one knee and ties a thread on him. She doesn't seem to think about it."),
  cleric("He was somebody's. Eleven lengths left."),
  t("She looks along the row, bed by bed, the way you'd check a sum. Ilzra has come in behind you with a bowl. She looks at the stool, and sets the bowl down, and sits on it."),
  ilzra("Go on. I know how to sit up straight. It's the only thing I was ever taught. Give me some thread."),
  cleric("You'll stay till it's over, and you won't ask for anything, and you won't look away."),
  ilzra("That's more or less what my mother told me about court."),
  { join = "cleric", lvl = 38 },
  { big = "THE SISTER RETURNS" },
  cleric("I said I'd been wrong once, {hero}. I've had a year to check my sums. There's a thing I want to tell you, and I'm not doing it here, and I'd thank you not to ask."),
  cleric("Whoever carried me went east, to Strathe. I know who it was. She'd rather I didn't. Let's go and embarrass her."),
  { set = "rd_cleric_in" },
}

-- ---------------------------------------------------------------- the Underweb

S.rd_scene_web = {
  t("The web that caught a falling city has been torn nearly in half. What's left hangs in long wet rags over nothing. Below you, somebody is talking in a low and reasonable voice. Then a great many people are."),
}

--- Stone in a basket. Two of them bring the lift.
local function weight(flag, text)
  return {
    { when = flag, steps = {
      t("The basket's full. The line has gone taut."),
    }, other = {
      t(text),
      { set = flag },
      { all = { "rd_weight_a", "rd_weight_b" }, steps = {
        { sfx = "door" },
        t("Far above, something heavy shifts. A long shiver goes through every strand that's left, and a net basket the size of a barn starts down to the head of the strand."),
        { set = "rd_lift_up" },
      } },
    } },
  }
end

S.rd_weight_a = weight("rd_weight_a", "A big wicker basket, tied off at the far end of the web. You fill it from the rubble, and it takes all of you. The line above it creaks, and comes tight.")
S.rd_weight_b = weight("rd_weight_b", "The second basket. Someone has tucked a folded blanket in the bottom of it. You leave the blanket, and pile the stones round it.")

S.rd_talk_mmrk = {
  t("An ettercap crouches on the strand with its long hands full of silk, mending what can't be mended."),
  { when = "rd_lift_up", steps = {
    mmrk("Lift is up. Go. Mmrk stays. Someone has to do the baskets."),
  }, other = {
    mmrk("Click. Net-tender Mmrk, tenth shift. Nobody has relieved me. Lift is dead. Counterweights went down with the north side. Fill the two baskets at the far ends with stone, and it comes. There is no form for this. I have made one."),
  } },
  ask(mmrk("You have question? Be quick. It is nearly bell."), {
    topic("Who do you feed now?", {
      mmrk("Everyone. They all come down now. Moss is short. I say their names when I lower the basket. Some look up."),
    }),
    { "Thanks. Keep mending.", {
      mmrk("Yes. I am the union now. I have voted."),
    } },
  }),
}

-- ---------------------------------------------------------------- Strathe

S.rd_scene_strathe = {
  t("The lift brings you up through what used to be a floor. Half of Strathe went into the chasm the night the world broke, the Queen's hall and the whole north side. What's left hangs from a rag of web, tilted like a plate on a tired hand."),
  t("People stand along every rail, driders by the hundred, facing east with their hands open. None of them turns. They're all breathing together, and you find that you've begun to."),
  commons("Keep your voices down, please, and don't sneeze. I'm not joking. The Queen's had a cold since Tuesday. Last time she sneezed, a whole street walked off the edge."),
  cleric("She's alive, then."),
  commons("It's all anyone's doing. She hasn't left the cradle at the Quiet House for a year. While she breathes they stand. Nulliira's gone, and there's a cat on the rim who won't be moved, and she's bitten Houndrin. East end of the avenue."),
  { set = "rd_strathe_in" },
}

S.rd_talk_rail = {
  t("She doesn't turn. Her lips are moving very slightly. You wait through three of her breaths, and all up and down the rail a hundred others take them with her."),
}

S.rd_talk_commons = {
  { when = "rn_done", steps = {
    commons("They say the black head's dead, up north. We felt it go, in the pillars. Nobody on the rail so much as blinked. I've written it down."),
  } },
  ask(commons("This is the Commons. Take what you need, and write down what you took. There's more than there used to be. There are fewer of us."), {
    { "Show me.", { { shop = "rd_commons" } } },
    { "Not just now.", {} },
  }),
}

S.rd_talk_houndrin = {
  ask(houndrin("Houndrin Dilagon. Hunt's over. I've got six hundred years of good steel and a hand the cat bit. Do you want it, or do you want to watch me cry?"), {
    { "Show me your gear.", { { shop = "rd_houndrin" } } },
    topic("Do you still eat people?", {
      houndrin("I've been introduced to everyone. It's a very small city now."),
    }),
    { "Not just now.", {} },
  }),
}

S.rd_talk_sael = {
  { when = "rd_jezzara_in", steps = {
    sael("I've got the rim. I taste her dinner first, and then I look pleased. Lunch has the door. He's very good. He's had two."),
  }, other = {
    sael("This is Lunch. He's bigger than me now. I take the Queen her dinner, and he goes first, in case it's poison. I told him it might be. He looked pleased. It's the same face."),
    { choice = {
      { "He's very handsome.", {} },
      { "Mind how you go, Sael.", {} },
    } },
  } },
}

S.rd_talk_iliss = {
  ask(iliss("A bed? Sit, sit. There's a thousand hammocks in this city and nobody in them. They're all on the rails, and I still go round and turn them down."), {
    { "We'd like to rest.", {
      { heal = true },
      t("The hammock takes you up like a hand. Nothing happens for several hours, which for you is usual."),
    } },
    { "Not now, thanks.", {} },
  }),
}

S.rd_road_shut = {
  cleric("That's the Web Road, and it can wait. I'm not going anywhere until I've seen who's on that rim."),
}

-- ---------------------------------------------------------------- the Quiet House

S.rd_read_records = {
  t("The settling-books are still on their shelves. The last of them stops a year ago, in the same small clear hand. Name, moult, one drop, left ear, slept well. Then there's one more line, by itself."),
  t("NULLIIRA T'SARREN, ADULT. ONE DROP, BY MY OWN HAND. I HAVE BEEN VERY TIRED."),
  cleric("Forty thousand children, and she couldn't sleep. I'd have sat with her. Nobody ever thinks to ask, for that sort."),
}

S.rd_read_drawers = {
  t("The cold room. Every drawer stands open and every phial is empty. They've been washed, and dried, and put back with the labels facing out."),
  deserter("Thousands of them, friend, and she tidied up afterwards. I don't want to think about where they've gone. I want it noted that I'm thinking about it."),
}

S.rd_scene_cradle = {
  { when = "rd_cradle_talked", other = {
    t("The Queen lies in the great silk cradle, a good deal smaller than she was. On the rim of it sits Jezzara Deth, or a yard to the left of that, with a year of no sleep under her eyes and a very small clean knife. She's peeling something."),
    jezzara("You're late. I had you down for spring. No, don't hug me. It isn't that I'd object. You'd miss."),
    cleric("You left a knife in my door."),
    jezzara("I don't know what you're talking about. And you're heavier than you look. I want that noted."),
    ask(jezzara("So. I've spent a year keeping alive the only woman I was ever paid to kill, and the money's terrible. What do you want?"), {
      topic("Why are you here?", {
        jezzara("She's the keystone. If she goes, a hundred thousand of them walk into the sea for Vierrela. Every few nights something comes to see to it, and I send it back. I told her I'd be insulted if anyone else did it. I don't say things I don't mean. It's a nuisance."),
      }),
      topic("Is she awake?", {
        halryna("Forty-two years, dear. She hums, you know, when she thinks I'm under. It's very flat."),
        jezzara("That's a lie, and I'll kill you."),
      }),
      { "We're going to Crysathula. Come with us.", {} },
    }),
    t("The door opens behind you. Nobody opened it. Mother Nulliira stands there in a spotless apron, very straight, and her eyes are shut."),
    borrowed("Jezzara. That was twelve good years, and you've spo... you've spoiled them by. By reading. I did wonder who it would be."),
    jezzara("That's the third time I've had that speech. It's getting shorter."),
    borrowed("{hero}. How nice. Do come and see me, all of you. I've kept a. I've kept a. There's a chair."),
    t("The smile stays exactly where it is. Something behind it is feeling for the next word, the way you'd feel for a stair in the dark."),
    cleric("Something's wrong with her. Vierrela, I mean. That isn't anyone being clever. I've sat beside that sound for a year."),
    jezzara("Stand in front of the Queen. Everyone."),
    { big = "MOTHER IS NOT ASLEEP" },
    { set = "rd_cradle_talked" },
  } },
  { battle = "rd_e_nulliira" },
  t("She comes down carefully, folding each leg, as if someone might be sleeping. The smile goes out. Her eyes open, and they're her own, and they go along the room, counting."),
  nulliira("Did anyone wake? Nobody woke?"),
  { choice = {
    { "Nobody woke, Mother.", {
      nulliira("Good. That's good. I can put that down. Slept well."),
    } },
    { "They're all at the rails.", {
      nulliira("Yes. I know. Somebody should write it down."),
    } },
  } },
  t("The sister ties the thread. She looks at what's left of it, and puts it away."),
  cleric("Ten left. I don't suppose there's a prayer for it."),
  halryna("That was the last of my old household. Jezzara, dear, I release you. Go and do what you came down here to do. Not to me. To her."),
  jezzara("And who sits up here? You'll have a street over the edge by Thursday."),
  t("Something small comes round the door on eight careful legs, leading something much larger on a string. She has a spoon on a cord round her neck, and it's far too big for her."),
  sael("I can do the rim. Lunch can do the door. Uncle showed me. You taste it first, and then you look pleased."),
  jezzara("That's a child and a spider."),
  halryna("It was a spoon that kept me alive for thirty years. I've had worse guards. I've had you."),
  jezzara("Keep breathing, your majesty. I'd still be insulted."),
  halryna("And you, {hero}. Keep breathing. I mean that as one professional to another."),
  t("You've no idea what she means. The sister does. You watch her not say so."),
  { join = "jezzara", lvl = 38 },
  { big = "JEZZARA DETH RETURNS" },
  jezzara("The first time I turned on Vierrela, it was free. This time I'd pay for it. West end of the low street, the Web Road. Let's go and see what's left of her."),
  { set = "rd_jezzara_in" },
}

S.rd_talk_cradle = {
  { when = "rd_jezzara_in", steps = {
    t("The Queen's chest rises and falls. Out along the rails, all at once, so do a hundred others."),
    { when = "rd_done", steps = {
      halryna("I felt the line go dead. They're all still standing. I find I can't let go. I'll keep on. You'd know about that."),
    } },
  }, other = {
    t("The Queen lies quite still. Somebody on the rim shifts a yard to the left, and looks at you until you go away."),
  } },
}

-- ---------------------------------------------------------------- the Salt Stair

S.rd_scene_rain = {
  t("The Web Road lets you out on the wet rock, and the rain is worse than you remember. Something has cracked the roof of the world, and the Guldan Ocean is coming through in ropes."),
  jezzara("See that green bubble, a long way out? No, neither do I. It went out in the spring. Whatever's keeping that city dry has stopped bothering."),
}

S.rd_talk_fall = {
  { when = "rd_crate_got", steps = {
    t("You set the crate against the salt and take off the lid. Then there's a small, contented sound, like someone starting on a very large biscuit."),
    jezzara("All right. Now I do want to know what it says in the ninth language."),
    t("The salt goes down in about the time it takes to be sorry you stayed. The crate is a good deal heavier, and it moves off along the stair by itself."),
    { set = "rd_gate_open" },
  }, other = {
    t("The stair is blocked by a fall of white salt, packed as hard as brick."),
    deserter("Unless anyone's got something that eats salt, friend, we're stuck. There's wreckage along the ledge, west of the top. It might be worth a look."),
  } },
}

S.rd_talk_crate = {
  t("A shipping crate has wedged itself in the corner of the ledge. It says FRAGILE in nine languages, and PROPERTY OF ASTRAL HAULAGE. Something inside it shifts, and licks the wall."),
  t("It comes along with hardly any help, leaving a clean wet line on the rock."),
  { set = "rd_crate_got" },
}

S.rd_talk_ibbit = {
  t("A small round person in a brass helmet sits on the last rib of a sky ship, fishing, with no line."),
  { when = "rd_gate_open", steps = {
    ibbit("Did you see a crate? It's on the manifest as 'lunch'. I never asked whose."),
  }, other = {
    ibbit("Factor Ibbit, Astral Haulage. Thirteen years without a scratch, not counting everything. I've finally had a bite. It asked to see my licence."),
  } },
}

S.rd_read_mother = {
  t("Halfway along, the bridge stops. Lying across the gap, ring over ring, is something pale and long, with the salt set round it as hard as stone."),
  deserter("I don't want to seem ungrateful, friend, but this is the nicest she's ever been to us."),
  t("You walk across her. It's a long way, and you don't look at what you're stepping on."),
}

-- ---------------------------------------------------------------- Crysathula

S.rd_scene_crysathula = {
  t("There's no green skin to pass through now. It's raining in Crysathula, on the clean curved streets, for the first time in the city's life. Tall figures stand here and there in the wet, like things left out to be collected."),
  zhar("Arrival registered. You were expected. It says here you were expected. State your plane of origin. I'm so sorry. I've forgotten why that matters."),
  zhar("The Hive Queen will see you. She's said so every day for a month, at the same hour, in the same words. The Cortex Nest is at the west end. No door here is locked. You'll find you can try them now."),
  { set = "rd_crys_in" },
}

S.rd_talk_zhar = {
  ask(zhar("Clerk Zhar, departures. There's one skiff left, and I can't remember who it belongs to, so it's yours. It's two hundred, to Touarch. I do remember that it's two hundred."), {
    { "Nothing, thank you.", {} },
    { "Book the skiff to Touarch.", {
      { paid = 200, steps = {
        t("The skiff goes up through the rain and down the dark like a thrown knife."),
        { warp = { "rd_touarch", 4, 2, 2 } },
      }, other = {
        zhar("Two hundred gold. It's a form. I think it's a form."),
      } },
    } },
  }),
}

S.rd_talk_sult = {
  t("A tall figure in a wet robe stands in the street, holding out a bowl. It's filling up with rain."),
  { when = "rd_zal_kept", steps = {
    sult("There's a voice now, you know. Very old, and very tired. It tells one it's all right. One doesn't believe it, and neither does it, and one finds that's rather a comfort."),
  } },
  ask(sult("I do apologise, my eyes are wandering rather more than they did. She used to say nothing, and one knew what she wanted. Now she says nothing, and it's simply nothing."), {
    topic("Are you going to eat us?", {
      sult("I shouldn't think so. Look, it holds water. Twenty-three years of bowls, and I've finally made one that holds water. I find I'd like to go on having done that."),
    }),
    { "Enjoy the pottery.", {} },
  }),
}

S.rd_talk_sweeper = {
  { when = "rd_sweeper_stopped", steps = {
    t("The thin man sits on a step with the broom across his knees and the rain running off him. He's saying a name over, quietly, so as not to lose it."),
  }, other = {
    t("A thin man in a grey shift is sweeping the rain along the street in long even strokes. It keeps coming back. He stops, and looks at the broom."),
    sweeper("Good evening. I came from Eighstead, in a crate. I think I had a wife."),
    t("He stands there for a moment."),
    sweeper("I had a wife. Her name was Merrin. Why have I got a broom?"),
    t("He isn't smiling any more. He's the first person you've seen stop, in this whole city. It's terrible to watch, and it's the best thing that's happened all year."),
    cleric("Sit down, love. I'll stay a bit. Tell me about Merrin."),
    { set = "rd_sweeper_stopped" },
  } },
}

S.rd_talk_uln = {
  t("The shelves still go up further than the ceiling does, and there's a bucket on the counter. The grey thing with the one wet eye looks at you, and away, and at you."),
  { when = "side_zalabarula", steps = {
    uln("It's stopped, under the floor. Uln slept last night, for the first time in nine hundred years. It was horrible. Uln doesn't know how you people stand it."),
  } },
  { when = "rd_done", steps = {
    uln("Ah. The pages have come unstuck. Uln can see that from here. Thirty percent off, and it's not enough."),
  } },
  ask(uln("Uln has a bad conscience, a stock of very good things, and nobody left to sell them to. What will it be?"), {
    { "Show me your wares.", { { shop = "rd_uln" } } },
    topic("What do you see in me?", {
      uln("No. Uln still won't. Stand over there. No, further."),
    }),
    topic("What's on your conscience?", {
      uln("There's a carrel in the Vault, bricked up from inside. Uln knocked out one course, to look. There was a robe in a chair, writing, and nothing in the robe. It turned its hood. Uln ran, and didn't stop until there was a city on top of him."),
      { when = "side_zalabarula", steps = {
        uln("It was his city, as it turned out. Zalabarula the Brain Sipper. He came home, and you went down the hatch after him. Uln hasn't asked. Uln can see what you did from here."),
      }, other = {
        uln("It was his city, as it turned out. Zalabarula the Brain Sipper. The hatch by the research wing has been broken open from below. It sips, down there. Uln can hear it. He's come home."),
      } },
    }),
    { "Not today.", {} },
  }),
}

S.rd_talk_pod = {
  ask(pod("Rest cells, a hundred a night. You will have no dreams at all. I do mean you in particular. I've been told to say that, and I can't think who by."), {
    { "A cell, please.", { { inn = 100 } } },
    { "Not tonight.", {} },
  }),
}

S.rd_talk_vel = {
  ask(vel("Research wing, what's left of it. She came in the spring and corrected my notes again. Doctor, I think she's trying to write something down before it goes."), {
    topic("What does it say?", {
      vel("The same line, four hundred times. HE IS OWED. It changes to SHE, and THEY, here and there, as if she's not sure. I've never seen her unsure."),
    }),
    { "We'll be going.", {} },
  }),
}

-- ---------------------------------------------------------------- the Cortex Nest

S.rd_scene_nest = {
  { when = "rd_nest_talked", other = {
    t("The green glass has cracked from floor to roof, and the rain has found the hall. Behind it the great grey thing lies as it always lay, with its one clean scar."),
    t("A drow woman sits in a plain chair with a shawl round her shoulders, facing it, like someone's aunt at a window. Behind her is a row of empty chairs."),
    { when = "rn_done", steps = { t("There are exactly six.") }, other = { t("There are exactly five.") } },
    vierrela("There you are. Sit down, {hero}. You've come such a long way, and you've done it so... you've done it so well. I've been saying that every day for a month, in case I lost it."),
    jezzara("I've come to finish it. This one's on me."),
    vierrela("Jezzara. You kept your knife. It's good of you to come, dear, but I'm afraid somebody has got there first."),
    t("She turns her head. It takes longer than it should. There's a fine grey line along her brow, and you take it at first for a strand of hair."),
    ask(vierrela("Ask quickly, please. I've been dismissed, you see. I'm only working out my notice."), {
      topic("What's happening to you?", {
        vierrela("It's up, dear, and it has a world to see to, and I was only ever the jar. It's taking me back a word at a time, very neatly, the way I did that."),
        t("She doesn't look round at the glass."),
        vierrela("I chose it because it didn't care what I was worth. I did say so. I want it noted that I was right."),
      }),
      topic("Where's Colette?", {
        vierrela("At the Vault, what's walking in her. She went down to be told she mattered. It's the most ordinary thing anyone has ever done."),
      }),
      topic("Let Strathe go.", {
        vierrela("I can't find it. I reach for Halryna, and there's only a room. It was so restful, having something I hadn't done yet. I've lost the word for what it was."),
      }),
      { "What am I? You said you knew.", {} },
    }),
    t("For the first time she looks pleased. She draws a folded leaf of paper out of the shawl and holds it on her knee, with one finger on it."),
    vierrela("This came off the last cart out of Evrastin, with you. Your mother cut it from the ward book and gave it to the carter, to keep till you could read. He sold it. People do."),
    vierrela("I've had it for twenty-three years. I've rehearsed. I know what your face does. {hero}, you have never..."),
    t("She stops."),
    t("It isn't the way a person stops. The grey line has closed, all the way round, very thin and very straight. It's the cleanest scar you've ever seen. You've seen one other."),
    vierrela("Oh."),
    t("It's the first thing she has ever said that she didn't already know. The page slides off her knee, and away across the wet floor."),
    jezzara("I find people who resign are so much more useful."),
    t("The chair scrapes. What was Vierrela gets up, and it gets up very well. Everything she ever learned is still there, the power that stilled a mother brain, with nobody in the room to say what it's for."),
    t("It smiles her smile. It holds out one hand towards the row of chairs."),
    husk("Sit down, dear. Sit down, dear. Sit down. Sit."),
    { big = "WHAT'S LEFT OF HER" },
    { set = "rd_nest_talked" },
  } },
  { battle = "rd_e_husk" },
  t("It stops halfway through a word, with its hand still out. Then it walks back to the plain chair, because that's where it goes, and it sits, and folds its hands, and faces the glass."),
  t("It's still breathing."),
  cleric("There's nobody in there to sit up with. I've never had that before. I don't know that I know how."),
  t("She takes out her black thread anyway. She looks at it for some time, and then she ties it round that thin wrist."),
  jezzara("She'd have hated that."),
  cleric("Yes. Nine left."),
  t("Nobody says anything. The rain comes in. Out on the wet floor, by the last of the chairs, lies the page."),
  { set = "rd_husk_down" },
}

S.rd_talk_husk = {
  t("She sits with her hands folded, facing the glass. Rain runs down her face, and she doesn't mind it. There's a black thread round her wrist."),
}

-- The great reveal. The player walks to the page by themselves, the mother says it, and the scholar finishes the sum. Then they answer.
S.rd_scene_page = {
  t("A leaf from a ward book, cut close along one edge. The writing is strong and black, gone rather large, running downhill. You've read that hand before."),
  t("The others have stopped a little way off. Nobody told them to."),
  t("'{hero}. I've cut this out so they can't make a study of you. Tyto thinks you got better. You didn't. I've kept a light for twenty years, and I know when a ship has gone down, and when it has only put out its lamps.'"),
  t("'It's still in you, behind the left ear. I've felt it with my thumb. The others hatch, and eat the sleeper. Yours lay down. On the eleventh night your eyes stopped halfway across, and it stopped with them.'"),
  t("'It takes your dreams, before you can have them. That's all it takes. So you'll never dream, and you'll never catch this, and you'll eat your dinner and grow. They'll call you lucky. Let them.'"),
  t("'It's the only bargain anyone ever had out of that thing, and you made it at six weeks old. Don't let them wake it. Red for the reef, green for the harbour. Always finish on home.'"),
  { fade = true },
  t("You put your hand up behind your left ear. There's a small hard place there, no bigger than a lentil. You've always had it. Nan's thumb used to rest there at bedtime. You'd thought that was just where her thumb went."),
  t("Nothing, you told her, every morning of your life. Nothing, Nan. Same as always. You signed for it, in a book."),
  t("There was something. There was something on its way, every night, and it was taken before it ever reached you."),
  owlin("I said I'd show my working. I've spent a year wanting very much to be wrong. May I?"),
  { choice = {
    { "Say it.", {
      owlin("Thank you."),
    } },
    { "It looked at me, at the Vault. It lifted the cloth.", {
      owlin("Yes. I saw. I think that's just what it was doing."),
    } },
    { "You knew. All of you.", {
      cleric("I knew there were two ends to your thread. Since Orrenshire. I told myself I was tired. I've never wanted so much to be tired."),
    } },
  } },
  owlin("Every tadpole in every ear is one creature, in one hand, as that nothic said. A piece of Qarhuul, awake and screaming. That's the sickness."),
  owlin("The Quiet House made it lie down, with one sleeper to hold down the rest. Proctor Dole's working is that, for the whole world. With the right key it would work. That's why it asked for you the way a lock asks for a key. We saw what it did with the wrong one."),
  owlin("Everyone we've met has wanted the cure, {hero}. It's behind your ear. It's a piece of Qarhuul that hasn't woken up."),
  t("The rain comes in through the glass. Nobody seems to know where to look. Then, one at a time, they come and stand where you can see them."),
  ask({ text = "Nobody is going anywhere. You can ask them anything." }, {
    topic("Doctor. Can you take it out?", {
      deserter("It's had twenty-three years, friend. It has grown through everything you've got. I could have it out, and you'd come out with it."),
      deserter("I told you I'd stay right here beside you, and I called that a clinical opinion. I've reviewed the case. The opinion stands."),
    }),
    topic("Sister. If I die, does it end?", {
      cleric("I asked her, every night for a year, and my lady doesn't lie. No. You'd go, and it would stay, and hatch in the dark with nobody home."),
      cleric("So you're not to go dying. I've nine lengths left, and one of them I've put by. No, you may not ask."),
    }),
    topic("Scholar. What does it want with me?", {
      owlin("A way in. What came up through the Abyss was arms. The rest of it is very far off and very large, and a thing that size doesn't climb. It comes through a door. It's been growing one, and waiting for it to rise."),
      owlin("Your mother says your eyes stopped halfway. Something was on its way to you, that night, and it never got there. I intend to think about that."),
    }),
    topic("Jezzara. If it wakes, will you do it?", {
      jezzara("You're asking me that in front of everyone. Yes. You wouldn't see it coming, and I wouldn't charge."),
      t("She looks at the wall, a yard to the left of it."),
      jezzara("Nobody's ever asked me as a favour. Don't do it again."),
      { set = "rd_asked_jez" },
    }),
    { "That's enough.", {} },
  }),
  { when = "rn_done", steps = {
    asphodel("I've kept a country on its feet with worse than that in my blood. You get up in the morning, and you see who's left. That's the whole trick of it."),
  } },
  { choice = {
    { "I'm still me. Same as always.", {
      deserter("You are, friend. That was never in question. You're also late for dinner."),
    } },
    { "Was any of it mine? Any of me?", {
      cleric("You got up every morning. That thing has never got up in its life. I've sat with a great many people, {hero}. I know who's in there."),
    } },
    { "We carried that cure across the world.", {
      owlin("We did. I gave my life to it, and I signed the first line. I'm told one can be wrong and carry on. I've had a good deal of practice."),
    } },
  } },
  t("The doctor looks round at the rain and the cracked glass and the woman in the chair. Then a spirit lamp comes out of the bag, and a pot, and they go down on the floor of the Cortex Nest."),
  deserter("I've given a lot of bad news, and I've only ever found the one treatment. Sit down, all of you. She went to the trouble of getting the chairs."),
  t("You sit. They're very comfortable chairs. Nobody says so. For some time nobody says anything at all, and the rain comes in, and it's very good soup."),
  t("You find that you can eat. You've always been able to eat. Your mother said you would."),
  { set = "rd_done" },
  { save = true },
  { when = "rn_done", steps = {
    deserter("That stair at the end of the east bay goes down to all the rest of it, friend. When you've finished your soup, and not before."),
  }, other = {
    deserter("That stair at the end of the east bay goes down to all the rest of it. It'll wait. There's still Sindal's country to see to, up north, and I want everyone we've got. Finish your soup."),
  } },
}

-- The way to the end of the game. It needs both halves of the ruined world done, in either order.
S.rd_way_down = {
  { all = { "rn_done", "rd_done" }, steps = {
    t("The Brain Sipper's stair goes down from the end of the bay, old and dry, to where the Clinic sawed through the last flight. Past that a fallen chain as thick as a street hangs down into the dark. The air coming up it tastes of pennies. Nobody will be coming back up this one."),
    { choice = {
      { "Go down.", {
        { warp = { "fn_vault_1", 3, 3, 2 } },
      } },
      { "Not yet.", {} },
    } },
  }, other = {
    t("A low arch at the end of the bay opens on old, dry steps going down. There's no one in it now. It isn't time. You couldn't say how you know."),
  } },
}

-- ---------------------------------------------------------------- the Old Hive

S.rd_hive_in = {
  t("The hatch lets you down into something older than the city. These walls were grown, and they've dried, like the inside of a gourd. Somewhere ahead there's a small, patient sound, like someone finishing a drink."),
  jezzara("I've been in a lot of places I shouldn't. This is the first one that's wanted to get into me."),
}

S.rd_read_pool = {
  t("A brine pool, dried to a crust. Hundreds of small grey shapes lie curled in the salt. All their heads have turned the same way, to the south."),
}

S.rd_read_tablets = {
  t("Tablets line the wall, all in one small neat hand. The last of them says: I AM TOLD THERE IS A LIBRARY. I SHALL BE GONE AN AFTERNOON."),
}

S.rd_scene_zal = {
  { when = "rd_zal_talked", other = {
    t("The last room was his throne room, or his stomach. In the middle of the dry floor sits something with no robe at all, yellow as an old tooth. There's very little of it, and its four long tendrils are holding one another."),
    zal("Forgive my not rising. You passed my chair, I believe. I wasn't in it. I'd been gone for some time, and nobody had told my hands."),
    ask(zal("I am Zalabarula. I was, I believe, the Brain Sipper. Nobody comes down here for the conversation. What do you want?"), {
      topic("What happened to you?", {
        zal("I went to the Vault to learn to hold a mind without a mother. It was an easy lesson. Then I found I had the end of something that was already holding me. I took dictation for three hundred years."),
        zal("When the lid came off it let me go, the way you'd put down a pen. I walked home. I'm so very hungry, and nothing tells me not to be."),
      }),
      topic("How do you fight something that holds?", {
        zal("You don't hold it. Everyone who tries is held. You close your hand, and there it is in your palm. The only thing I ever saw it fail to take was a thing that wouldn't close. Do write that down."),
      }),
      { "We've come to let you go.", {
        { set = "rd_zal_end" },
      } },
      { "Your people are starving for a voice. Go up to them.", {} },
    }),
    { set = "rd_zal_talked" },
  } },
  { when = "rd_zal_end", steps = {
    zal("Have you? How kind. I should warn you that the hunger doesn't ask me. Do be quick."),
    { battle = "rd_e_zal" },
    t("The tendrils come apart, one at a time, as if each had to be persuaded."),
    zal("There. I've let go. It's so much easier than one was told."),
    cleric("I'll take your name, if you'd like. Someone ought to have it in writing."),
    t("He tells her. It's a long one, and it isn't the one anybody knows. She writes it on the wall with a burnt stick, under all the ledgers."),
    { give = "mind_ward" },
  }, other = {
    zal("Up? To sit in the rain, and tell them that it's all right? They'd have a voice again, from someone who knows that it isn't. I believe that's more or less the definition of kindness."),
    zal("I'd hold them gently. I do know what it's like. If I close my hand, you will come back and see to it, won't you?"),
    t("He gets up. It takes a long while. You hear him start up the old passage, one step at a time, going somewhere on his own for the first time in three hundred years."),
    { give = "raven_charm" },
    { set = "rd_zal_kept" },
  } },
  { set = "side_zalabarula" },
}

-- ---------------------------------------------------------------- the Diamond Cave

S.rd_crystal_in = {
  t("White. After a year of the dark it hurts. The walls are diamond, grown in the rock, and every wall has you in it twenty times over."),
  owlin("Nobody hoarded this. It simply grew, and something came and lay down on it. Nobody who's walked along these walls has written home."),
}

S.rd_read_log_a = {
  t("A dragon hunter in frosted armour sits against the wall, with a little book on one knee. DAY 2. Trail fresh. Thirty-three in the party, in good heart. A fine beast, by the tracks, and thin. It will be hungry. We shall be rich."),
}

S.rd_read_log_b = {
  t("Another hunter, and the same small book, in the same hand, much shakier. DAY 40. He has been behind us since day 2. There were never any tracks ahead. He laid them. I am the last. I can see him in the wall. He's waiting till I finish wri"),
}

--- A lens. All three together crack the curtain.
local function lens(flag, text)
  return {
    { when = flag, steps = {
      t("The lens is lit. Its beam goes off through the wall, down and to the south."),
    }, other = {
      t(text),
      { set = flag },
      { all = { "rd_lens_a", "rd_lens_b", "rd_lens_c" }, steps = {
        { sfx = "thud" },
        t("Somewhere to the south, the third beam meets the other two. There's a note, very high and very clean, and then the long sound of a great deal of crystal letting go."),
        { set = "rd_wall_down" },
      } },
    } },
  }
end

S.rd_lens_a = lens("rd_lens_a", "A great lens of white crystal stands in a hunter's iron frame, with a dead lamp behind it. The doctor trims the wick, and it catches. A hard white beam goes off through the rock.")
S.rd_lens_b = lens("rd_lens_b", "A second lens, aimed at the south wall by someone who knew just what they were doing. It takes a while to light. The beam makes your teeth ache.")
S.rd_lens_c = lens("rd_lens_c", "The third lens. Someone has scratched on the frame: ALL THREE AND THE WALL COMES DOWN. THEN RUN. Below that, in the same hand: THERE IS NOWHERE TO RUN TO.")

S.rd_talk_gemwall = {
  t("A curtain of white crystal closes the way south. Three old burn marks lie across it. Behind it something pale and thin goes by, without any hurry."),
}

S.rd_scene_chylbad = {
  { when = "rd_chyl_seen", other = {
    t("The floor of the last cave is gems, knee deep, with a path worn through them by something long. Nothing moves. Then a small piece of the far wall turns its head."),
    t("He's thinner than a dragon has any right to be, and white as a tooth, with a gecko's wide flat face and two huge bulging eyes. He doesn't roar. Nothing that has lived this long makes a noise it doesn't need to."),
    owlin("Chylbad, the Diamond Fang. It took the whole Empire to tie him down. I have a sum here about our chances, {hero}, and I'd rather not finish it."),
    { set = "rd_chyl_seen" },
  } },
  t("The great eyes come round to you, and slide to the side of your head, and stay there. It's the first thing you've ever met that looks at that place behind your ear and isn't afraid. It only looks hungry."),
  ask({ text = "He hasn't moved. You'd swear he's closer." }, {
    { "Back out, slowly. Not today.", {
      t("You go back the way you came, facing him, one step at a time. He lets you. He has all the time there is."),
      { warp = { "rd_crystal", 14, 17, 1 } },
    } },
    { "Draw.", {
      { battle = "rd_e_chylbad" },
      t("He doesn't fall. He goes still, the way a lizard goes still, and you stand for a long time with your blades up. Then the light goes out of those great eyes, very slowly, from the outside in."),
      owlin("Nobody will ever believe this. I've written it down, and I don't believe it."),
      { when = "rd_jezzara_in", steps = {
        jezzara("I want it noted that I've just stolen from a dragon, and that nobody saw."),
      } },
      { give = "dragon_heart" },
      { give = "elixir", n = 5 },
      { gold = 30000 },
      { set = "side_chylbad" },
    } },
  }),
}

-- ---------------------------------------------------------------- shops

R.shops.rd_dangle = { tier = 7 }
R.shops.rd_hask = { tier = 7 }
R.shops.rd_commons = { tier = 7 }
R.shops.rd_houndrin = { tier = 7 }
R.shops.rd_uln = { tier = 7, extra = { { item = "life_ring", price = 2200 }, { item = "mind_ward", price = 2600 }, { item = "raven_charm", price = 2000 } } }

-- ---------------------------------------------------------------- where the story goes

local OPEN = "rs_done"

R.goals = {
  { done = "rd_touarch_in", text = "Go down to Touarch", map = "rd_abyss", x = 23, y = 19, when = OPEN },
  { done = "rd_heard_ward", text = "See the keeper of the Light", map = "rd_touarch", x = 14, y = 11, when = OPEN },
  { done = "rd_threads", text = "Follow the black threads", map = "rd_pillars", x = 15, y = 2, when = OPEN },
  { done = "rd_cleric_in", text = "Find the sister", map = "rd_ward", x = 11, y = 4, when = OPEN },
  { done = "rd_lift_up", text = "Raise the Underweb lift", map = "rd_underweb", x = 14, y = 4, when = OPEN },
  { done = "rd_strathe_in", text = "Go up into Strathe", map = "rd_strathe", x = 14, y = 17, when = OPEN },
  { done = "rd_jezzara_in", text = "Reach the Queen's cradle", map = "rd_quiet", x = 20, y = 12, when = OPEN },
  { done = "rd_gate_open", text = "Clear the Salt Stair", map = "rd_stair", x = 27, y = 6, when = OPEN },
  { done = "rd_crys_in", text = "Cross to Crysathula", map = "rd_crysathula", x = 25, y = 8, when = OPEN },
  { done = "rd_husk_down", text = "Go to the Cortex Nest", map = "rd_nest", x = 11, y = 8, when = OPEN },
  { done = "rd_done", text = "Pick up the page", map = "rd_nest", x = 9, y = 9, when = OPEN },
}

return R
