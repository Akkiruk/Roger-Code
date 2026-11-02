-- games/blightmare/regions/underdark.lua
-- The Underdark, draft for the author to edit. Plain data and local helpers. There is no overworld down here: everything hangs
-- off one chain of maps from the Abyss site. Four floors of the Violet Abyss to the foot, the Light of Touarch, the Pillar Road,
-- then the Underweb up into Strathe, the Quiet House, the Web Road and the Salt Stair, and Crysathula at the end of its bridge.
-- Blackhold and the Comet Seam hang off the Pillar Road, and they're the side quest (side_lovers): nothing else needs them.
-- The heart of it is the Quiet House: the "cure" that keeps the driders sane is a tadpole that never hatches. Nobody says what
-- that means for the hero, and nobody may yet. Colette's letter is hers to rewrite.

local say = require("games.blightmare.say")
local C = require("lib.arcade.ui").C

local t, ask, topic, person, line = say.t, say.ask, say.topic, say.person, say.line

local R = {
  id = "underdark", prefix = "ud_",
  entry = { flags = { "em_done" }, join = { "deserter", "cleric", "owlin" }, lvl = 25, site = "abyss", map = "ud_abyss_1", x = 3, y = 2 },
  exit = "ud_done",
  sites = { abyss = { mx = 3, my = 2, dir = 2 } },
  maps = {}, scripts = {}, shops = {}, goals = {},
  items = {
    ud_letter = { name = "SEVRIA'S LETTER", key = true },
    ud_page = { name = "BARRIS'S COPPER", key = true },
  },
  foes = {}, abilities = {}, encounters = {}, field = {},
  looks = {}, names = {}, art = {},
}

local S = R.scripts

local deserter = line("deserter")
local cleric = line("cleric")
local owlin = line("owlin")
local jezzara = line("jezzara")
local vierrela = line("vierrela")
local halryna = line("halryna")
local murgrum = line("murgrum")
local sevria = line("sevria")

local dangle = person("ud_dangle", "MABBET DANGLE")
local sentry = person("ud_sentry", "CORPORAL WEND")
local fettle = person("ud_fettle", "FETTLE")
local matron = person("ud_matron_npc", "MATRON SABRAL")
local ilzra = person("ud_ilzra", "ILZRA")
local olive = person("ud_olive", "QUEEN OLIVE")
local kindle = person("ud_kindle", "TOLLO KINDLE")
local mag = person("ud_mag", "MAG EMBER")
local hask = person("ud_hask", "HASK COBBLE")
local pell = person("ud_pell", "SIR ALDOUS PELL")
local tam = person("ud_tam", "KIT")
local winder = person("ud_winder", "BASKET-WINDER")
local moss = person("ud_moss", "ROAD-MOSS")
local tally = person("ud_tally", "KEEPER TALLY")
local forge = person("ud_forge", "FORGE-MOTHER HILDE")
local bruna = person("ud_bruna", "OLD BRUNA")
local drycup = person("ud_drycup", "DRY CUP KEEPER")
local dimsael = person("ud_dimsael", "QUEEN DIMSAEL")
local mmrk = person("ud_mmrk", "MMRK")
local ruaryn = person("ud_ruaryn", "RUARYN")
local borrowed = person("ud_ruaryn_w", "THE VOICE IN RUARYN")
local nulliira = person("ud_nulliira", "MOTHER NULLIIRA")
local commons = person("ud_commons", "COMMONS CLERK")
local houndrin = person("ud_houndrin", "HOUNDRIN DILAGON")
local sael = person("ud_sael", "SAEL")
local iliss = person("ud_iliss", "OLD ILISS")
local attendant = person("ud_attendant", "ATTENDANT")
local ibbit = person("ud_ibbit", "FACTOR IBBIT")
local zhar = person("ud_zhar", "CLERK ZHAR")
local sult = person("ud_sult", "BROTHER SULT")
local sweeper = person("ud_sweeper", "SWEEPER")
local uln = person("ud_uln", "ULN")
local vel = person("ud_vel", "ARCHIVIST VEL")
local pod = person("ud_pod", "CELL-KEEPER")

-- ---------------------------------------------------------------- how they look

local DROW_SKIN, DUERGAR_INK = C.blueTint, C.tie
local L = R.looks

L.ud_dangle = { kind = "old", tall = 0.8, build = "thin", lean = 0.1, cut = "coat", coat = C.redTint, trim = C.warn, hat = "wide", hatInk = C.tie, hatTrim = C.warn, beard = "long", beardInk = C.text, carry = "pole", oneShoe = true, eyes = "narrow", mouth = "smile", back = C.accent }
L.ud_sentry = { kind = "human", tall = 0.92, build = "thin", cut = "tunic", coat = C.line, trim = C.text, legs = C.line, skin = C.text, hat = "sallet", hatInk = C.text, hatTrim = C.line, carry = "spear", eyes = "tired", mouth = "line", back = C.bg }
L.ud_fettle = { kind = "deepgnome", tall = 0.5, build = "thin", cut = "tunic", coat = C.warn, trim = C.redTint, hat = "goggles", hatInk = C.hi, hatTrim = C.bg, hair = "wild", hairInk = C.text, carry = "lantern", mouth = "teeth", back = C.hiTint }
L.ud_matron_npc = { kind = "drow", tall = 0.98, build = "gaunt", cut = "robe", coat = C.bg, trim = C.accent, hat = "crown", hatInk = C.line, hatTrim = C.accent, hairInk = C.text, wear = { "necklace" }, carry = "staff", eyes = "red", mouth = "line", mark = "scar" }
L.ud_ilzra = { kind = "drow", tall = 0.82, build = "thin", cut = "tunic", coat = C.panel, trim = C.accent, hair = "plaits", hairInk = C.text, carry = "scroll", eyes = "wide", mouth = "open" }
L.ud_olive = { kind = "deepgnome", tall = 0.42, build = "stout", cut = "dress", coat = C.accent, trim = C.hi, hair = "bun", hairInk = C.text, wear = { "shawl" }, shawlInk = C.hiTint, carry = "bowl", eyes = "narrow", mouth = "smile", back = C.redTint }
L.ud_kindle = { kind = "deepgnome", tall = 0.54, build = "broad", cut = "tunic", coat = C.redTint, trim = C.warn, hat = "goggles", hatInk = C.warn, hatTrim = C.bg, hair = "tufts", hairInk = C.line, beard = "bolster", beardInk = C.line, wear = { "apron" }, apronInk = C.tie, carry = "shovel", eyes = "tired", mouth = "line" }
L.ud_mag = { kind = "deepgnome", tall = 0.5, build = "stout", cut = "dress", coat = C.redTint, trim = C.warn, hat = "scarf", hatInk = C.red, hatTrim = C.hi, wear = { "apron" }, carry = "mug", mouth = "smile" }
L.ud_hask = { kind = "deepgnome", tall = 0.52, cut = "coat", coat = C.tie, trim = C.hi, hat = "bowler", hatInk = C.bg, hatTrim = C.warn, beard = "goatee", beardInk = C.text, carry = "boots", eyes = "shifty", mouth = "smile" }
L.ud_pell = { kind = "human", tall = 0.94, build = "thin", cut = "coat", coat = C.red, trim = C.hi, legs = C.tie, hat = "feather", hatInk = C.red, hatTrim = C.text, hair = "short", hairInk = C.text, beard = "moustache", beardInk = C.text, wear = { "patches", "epaulettes" }, carry = "scroll", eyes = "wide", mouth = "smile", back = C.blueTint }
L.ud_tam = { kind = "deepgnome", tall = 0.36, build = "thin", cut = "tunic", coat = C.blueTint, trim = C.warn, hat = "earflap", hatInk = C.warn, hatTrim = C.bg, carry = "stone", eyes = "wide", mouth = "open" }
L.ud_winder = { kind = "deepgnome", tall = 0.52, build = "broad", cut = "tunic", coat = C.hiTint, trim = C.warn, hat = "cap", hatInk = C.red, hatTrim = C.bg, beard = "chops", beardInk = C.bg, carry = "wheel", eyes = "tired", mouth = "line" }
L.ud_moss = { kind = "human", tall = 0.92, build = "stout", cut = "robe", coat = C.hiTint, trim = C.soft, skin = C.soft, hat = "mushroom", hatInk = C.accent, hatTrim = C.soft, eyes = "closed", mouth = "none", nose = "none", back = C.bg }
L.ud_tally = { kind = "duergar", tall = 0.64, cut = "coat", coat = C.bg, trim = C.line, hat = "visor", hatInk = C.ok, hatTrim = C.bg, beard = "plaited", beardInk = C.line, beardTrim = C.red, eyes = "specs", carry = "ledger", mouth = "frown" }
L.ud_forge = { kind = "duergar", tall = 0.66, build = "broad", cut = "tunic", coat = C.redTint, trim = C.warn, beard = "none", hair = "bun", hairInk = C.tie, hat = "goggles", hatInk = C.info, hatTrim = C.bg, wear = { "apron" }, apronInk = C.tie, carry = "hammer", mouth = "line" }
L.ud_bruna = { kind = "duergar", tall = 0.6, build = "hunched", lean = 0.14, cut = "tunic", coat = C.tie, trim = C.red, beard = "belted", beardInk = C.text, hat = "helmet", hatInk = C.line, hatTrim = C.red, carry = "crutch", eyes = "narrow", mouth = "teeth", wear = { "armour" }, plateInk = C.line }
L.ud_drycup = { kind = "duergar", tall = 0.62, build = "stout", cut = "tunic", coat = C.panel, trim = C.warn, beard = "forked", beardInk = DUERGAR_INK, carry = "mug", eyes = "tired", mouth = "frown" }
L.ud_dimsael = { kind = "duergar", tall = 0.72, build = "broad", cut = "robe", coat = C.bg, trim = C.red, hat = "crown", hatInk = C.line, hatTrim = C.bg, beard = "none", hair = "long", hairInk = C.bg, eyes = "red", mouth = "line", wear = { "armour", "chain" }, plateInk = C.tie, back = C.redTint }
L.ud_barris = { kind = "duergar", pose = "lying", coat = C.panel, trim = C.hi, beard = "long", beardInk = C.text, wear = { "armour" }, plateInk = C.line, size = 1.25, mouth = "smile" }
L.ud_mmrk = { kind = "human", tall = 0.82, build = "hunched", lean = 0.16, cut = "rags", coat = C.hiTint, trim = C.bg, skin = C.ok, eyes = "wide", mouth = "fangs", nose = "none", tendrils = true, tendrilInk = C.tie, carry = "wheel", back = C.bg }
L.ud_mmrk_2 = { like = "ud_mmrk", carry = "basket" }
L.ud_ruaryn = { kind = "drider", tall = 1, build = "broad", coat = C.tie, trim = C.hi, hat = "helmet", hatInk = C.line, hatTrim = C.hi, wear = { "armour", "chain" }, plateInk = C.line, carry = "sword", eyes = "tired", mouth = "frown" }
L.ud_ruaryn_w = { like = "ud_ruaryn", eyes = "blank", mouth = "smile", skin = C.line, lean = 0.08, back = C.accent }
L.ud_halryna = { like = "halryna", carry = "scroll" }
L.ud_halryna_2 = { like = "ud_halryna" }
L.ud_halryna_c = { like = "halryna", eyes = "closed", carry = "none", pose = "lying", size = 1.25 }
L.ud_nulliira = { kind = "drider", build = "thin", coat = C.text, trim = C.line, hair = "bun", hairInk = C.text, eyes = "specs", mouth = "line", carry = "clipboard", wear = { "apron" }, apronInk = C.line }
L.ud_commons = { kind = "drider", tall = 0.94, build = "stout", coat = C.hiTint, trim = C.hi, hair = "short", hairInk = C.text, eyes = "narrow", carry = "list", mouth = "smile" }
L.ud_houndrin = { kind = "drider", tall = 1, build = "broad", coat = C.redTint, trim = C.warn, hair = "wild", hairInk = C.text, wear = { "fur", "belt" }, carry = "spear", eyes = "red", mouth = "fangs" }
L.ud_sael = { kind = "drider", tall = 0.6, build = "thin", coat = C.blueTint, trim = C.text, hair = "pigtails", hairInk = C.text, carry = "doll", eyes = "wide", mouth = "smile" }
L.ud_iliss = { kind = "drider", tall = 0.86, build = "hunched", coat = C.tie, trim = C.panel, hair = "long", hairInk = C.line, wear = { "shawl" }, shawlInk = C.accent, carry = "pillow", eyes = "tired", mouth = "smile" }
L.ud_jez_inn = { like = "jezzara", carry = "mug" }
L.ud_jez_c = { like = "jezzara", mouth = "line" }
L.ud_sleeper1 = { kind = "drider", pose = "lying", coat = C.tie, trim = C.panel, hairInk = C.text, eyes = "closed" }
L.ud_sleeper2 = { kind = "drider", pose = "lying", coat = C.hiTint, trim = C.panel, hairInk = C.line, eyes = "closed", flip = true }
L.ud_sleeper3 = { kind = "drider", pose = "lying", coat = C.blueTint, trim = C.panel, hairInk = C.text, eyes = "closed", size = 0.75 }
L.ud_attendant = { kind = "human", tall = 0.8, build = "hunched", lean = 0.12, cut = "rags", coat = C.text, trim = C.line, skin = C.ok, eyes = "wide", mouth = "fangs", nose = "none", tendrils = true, tendrilInk = C.tie, carry = "bowl", back = C.tie }
L.ud_ibbit = { kind = "gnome", tall = 0.48, build = "stout", cut = "tunic", coat = C.blueTint, trim = C.hi, hat = "pot", hatInk = C.warn, hatTrim = C.hi, eyes = "lens", mouth = "none", nose = "none", carry = "pole", back = C.bg }
L.ud_zhar = { kind = "gith", tall = 0.97, build = "thin", cut = "coat", coat = C.hiTint, trim = C.warn, wear = { "sash" }, sashInk = C.red, carry = "clipboard", mouth = "line" }
L.ud_sult = { kind = "illithid", coat = C.redTint, trim = C.accent, tentacles = true, carry = "bowl", mouth = "none" }
L.ud_sweeper = { kind = "human", tall = 0.86, build = "gaunt", cut = "rags", coat = C.line, trim = C.tie, skin = C.line, eyes = "blank", mouth = "smile", carry = "broom", back = C.blueTint }
L.ud_uln = { kind = "nothic", coat = C.panel, trim = C.bg, carry = "book", back = C.bg }
L.ud_vel = { kind = "gith", tall = 0.84, build = "stout", cut = "coat", coat = C.text, trim = C.soft, hair = "bun", hairInk = C.red, eyes = "specs", carry = "tube", mouth = "line", wear = { "surgeon" } }
L.ud_pod = { kind = "illithid", tall = 0.9, build = "stout", coat = C.tie, trim = C.text, tentacles = true, carry = "pillow" }
L.ud_vierrela = { like = "vierrela", carry = "goblet" }
L.ud_murgrum = { like = "murgrum", carry = "pen", eyes = "tired" }
L.ud_murgrum_t = { like = "murgrum", carry = "shovel", mouth = "smile" }
L.ud_sevria = { like = "sevria", carry = "ledger" }

R.names = {
  ["MABBET DANGLE"] = "ud_dangle", ["CORPORAL WEND"] = "ud_sentry", FETTLE = "ud_fettle", ["MATRON SABRAL"] = "ud_matron_npc", ILZRA = "ud_ilzra",
  ["QUEEN OLIVE"] = "ud_olive", ["TOLLO KINDLE"] = "ud_kindle", ["MAG EMBER"] = "ud_mag", ["HASK COBBLE"] = "ud_hask", ["SIR ALDOUS PELL"] = "ud_pell",
  KIT = "ud_tam", ["BASKET-WINDER"] = "ud_winder", ["ROAD-MOSS"] = "ud_moss", ["KEEPER TALLY"] = "ud_tally", ["FORGE-MOTHER HILDE"] = "ud_forge",
  ["OLD BRUNA"] = "ud_bruna", ["DRY CUP KEEPER"] = "ud_drycup", ["QUEEN DIMSAEL"] = "ud_dimsael", MMRK = "ud_mmrk", RUARYN = "ud_ruaryn",
  ["THE VOICE IN RUARYN"] = "ud_ruaryn_w", ["MOTHER NULLIIRA"] = "ud_nulliira", ["COMMONS CLERK"] = "ud_commons", ["HOUNDRIN DILAGON"] = "ud_houndrin",
  SAEL = "ud_sael", ["OLD ILISS"] = "ud_iliss", ATTENDANT = "ud_attendant", ["FACTOR IBBIT"] = "ud_ibbit", ["CLERK ZHAR"] = "ud_zhar",
  ["BROTHER SULT"] = "ud_sult", SWEEPER = "ud_sweeper", ULN = "ud_uln", ["ARCHIVIST VEL"] = "ud_vel", ["CELL-KEEPER"] = "ud_pod",
}

-- ---------------------------------------------------------------- what's down here to fight

local A = R.abilities

A.ud_fang = { name = "VENOM FANG", power = 95, status = "poison", chance = 60 }
A.ud_silk = { name = "SILK", power = 45, status = "sleep", chance = 45 }
A.ud_xbow = { name = "SLEEP BOLT", power = 80, status = "sleep", chance = 35 }
A.ud_hook = { name = "HOOK", power = 125 }
A.ud_clack = { name = "ECHO CLACK", power = 50, target = "all" }
A.ud_dark = { name = "DARKNESS", mp = 5, status = "blind", chance = 70 }
A.ud_spite = { name = "LOLTH'S SPITE", mp = 6, power = 80, magic = true, element = "blood" }
A.ud_gaze = { name = "UMBER GAZE", mp = 4, status = "thrall", chance = 35 }
A.ud_spore = { name = "MENDING SPORE", mp = 5, target = "friend", power = 0, share = 20 }
A.ud_cloak = { name = "SMOTHER", power = 70, status = "blind", chance = 50 }
A.ud_sap = { name = "BLACK POWDER", power = 60, target = "all", element = "fire" }
A.ud_ember = { name = "SLOW EMBER", power = 90, element = "fire" }
A.ud_ramble = { name = "REASONABLE VOICE", mp = 4, power = 40, magic = true, status = "nightmare", chance = 50 }
A.ud_blink = { name = "BLINK BITE", power = 115, status = "poison", chance = 30 }
A.ud_sting = { name = "TAIL STING", power = 100, status = "poison", chance = 40 }
A.ud_brine = { name = "BRINE SPIT", mp = 3, power = 70, magic = true, element = "ice" }
A.ud_latch = { name = "LATCH ON", power = 105 }

A.ud_scourge = { name = "SNAKE SCOURGE", power = 115, status = "poison", chance = 40 }
A.ud_brood = { name = "CALLS THE BROOD", target = "summon" }
A.ud_verdict = { name = "LOLTH'S VERDICT", power = 200, magic = true, target = "all", element = "blood", windup = 34, warn = "THE WEBS PULL TIGHT" }
A.ud_legs = { name = "EIGHT LEGS", power = 110 }
A.ud_spoon = { name = "HER WORD", mp = 6, magic = true, status = "tadpole", chance = 50 }
A.ud_voice = { name = "THE QUIET", power = 210, magic = true, target = "all", element = "mind", windup = 34, warn = "HE SPEAKS IN HER VOICE" }
A.ud_stamp = { name = "IRON STAMP", power = 125 }
A.ud_list = { name = "READS THE LIST", mp = 5, power = 60, magic = true, target = "all", status = "doom", chance = 25 }
A.ud_forty = { name = "FORTY THOUSAND NAMES", power = 215, magic = true, target = "all", windup = 34, warn = "IT DRAWS A BREATH OF NAMES" }
A.ud_rings = { name = "RINGS OF TEETH", power = 125 }
A.ud_salt = { name = "SALT SQUALL", mp = 6, power = 60, magic = true, target = "all", element = "ice", status = "blind", chance = 30 }
A.ud_mouths = { name = "TIDE OF MOUTHS", power = 220, target = "all", windup = 34, warn = "THE SEA STANDS UP" }

local F = R.foes

F.ud_bat = { name = "VIOLET BAT", tier = 25, shape = "small", sprite = "ud_bat", family = "bat", abilities = { { "bite", 3 }, { "shriek", 1 } }, weak = { "bolt" } }
F.ud_hookhorror = { name = "HOOK HORROR", tier = 26, shape = "brute", sprite = "ud_hookhorror", family = "stalker", abilities = { { "ud_hook", 3 }, { "ud_clack", 1 } }, weak = { "ice" } }
F.ud_husk = { name = "HORNED HUSK", tier = 26, shape = "tank", sprite = "ud_husk", family = "skeleton", abilities = { { "claw", 3 }, { "ud_dark", 1 } }, weak = { "holy" } }
F.ud_lemure = { name = "PIT-WORM", tier = 25, shape = "small", sprite = "ud_pitworm", family = "slime", abilities = { { "gnaw", 3 }, { "spit", 1 } }, weak = { "fire" } }
F.ud_spider = { name = "WEB SPIDER", tier = 26, shape = "small", sprite = "ud_spider", family = "bug", abilities = { { "ud_fang", 3 }, { "ud_silk", 1 } }, weak = { "fire" } }
F.ud_exile = { name = "DROW EXILE", tier = 26, shape = "quick", sprite = "ud_exile", family = "staff", abilities = { { "stab", 3 }, { "ud_xbow", 1 } }, weak = { "holy" } }
F.ud_lolthsworn = { name = "LOLTH-SWORN", tier = 27, shape = "caster", sprite = "ud_lolthsworn", family = "mage", abilities = { { "ud_spite", 3 }, { "ud_dark", 1 }, { "field_surgery", 1 } }, weak = { "holy" } }
F.ud_umber = { name = "UMBER HULK", tier = 27, shape = "tank", sprite = "ud_umber", family = "orc", abilities = { { "claw", 3 }, { "ud_gaze", 1 } }, weak = { "ice" } }
F.ud_mantle = { name = "DARKMANTLE", tier = 27, shape = "small", sprite = "ud_mantle", family = "roper", abilities = { { "ud_cloak", 1 } }, weak = { "bolt" } }
F.ud_myconid = { name = "SPORE WALKER", tier = 27, shape = "healer", sprite = "ud_myconid", family = "slime", abilities = { { "retch", 3 }, { "ud_spore", 1 } }, weak = { "fire" } }
F.ud_sapper = { name = "DUERGAR SAPPER", tier = 28, shape = "brute", sprite = "ud_sapper", family = "orc", short = "SAPPER", abilities = { { "swing", 3 }, { "ud_sap", 1 } }, weak = { "ice" } }
F.ud_cinder = { name = "SEAM CINDER", tier = 28, shape = "caster", sprite = "ud_cinder", family = "ghost", abilities = { { "ud_ember", 3 }, { "scorch", 1 } }, weak = { "ice" }, resist = { "fire" } }
F.ud_unsettled = { name = "THE UNSETTLED", tier = 28, shape = "brute", sprite = "ud_unsettled", family = "stalker", abilities = { { "lunge", 2 }, { "ud_ramble", 1 } }, resist = { "mind" }, weak = { "fire" } }
F.ud_phase = { name = "PHASE SPIDER", tier = 28, shape = "quick", sprite = "ud_phase", family = "bug", abilities = { { "ud_blink", 1 } }, weak = { "bolt" } }
F.ud_ettercap = { name = "FERAL ETTERCAP", tier = 28, shape = "brute", sprite = "ud_ettercap", family = "bug", short = "ETTERCAP", abilities = { { "claw", 3 }, { "ud_silk", 1 } }, weak = { "fire" } }
F.ud_manta = { name = "PALE MANTA", tier = 29, shape = "quick", sprite = "ud_manta", family = "harpy", abilities = { { "ud_sting", 3 }, { "ud_cloak", 1 } }, weak = { "bolt" } }
F.ud_lamprey = { name = "SALT LAMPREY", tier = 29, shape = "small", sprite = "ud_lamprey", family = "slime", abilities = { { "ud_latch", 3 }, { "ud_brine", 1 } }, weak = { "bolt" } }
F.ud_drowned = { name = "BRINE THRALL", tier = 29, shape = "tank", sprite = "ud_drowned", family = "blighted", abilities = { { "claw", 3 }, { "tadpole_drop", 1 } }, resist = { "ice" }, weak = { "fire" } }

F.ud_matron = {
  name = "MATRON SABRAL", tier = 27, shape = "caster", sprite = "ud_matron", family = "boss", short = "SABRAL", weak = { "holy" },
  boss = { hpx = 0.9, phases = {
    { at = 100, moves = { { "ud_scourge", 5 }, { "ud_spite", 3 }, { "ud_dark", 1 } }, every = 5, big = "ud_verdict" },
    { at = 60, moves = { { "ud_scourge", 4 }, { "ud_spite", 4 } }, every = 4, big = "ud_verdict", say = "SHE CALLS HER CHILDREN", call = "ud_brood", summon = "ud_spider" },
    { at = 25, moves = { { "ud_spite", 5 }, { "ud_scourge", 3 } }, every = 3, big = "ud_verdict", say = "LOLTH DOES NOT ANSWER", speedUp = 1 },
  } },
}
F.ud_grudge = {
  name = "THE GRUDGEBEARER", tier = 29, shape = "tank", sprite = "ud_grudge", family = "knight", short = "GRUDGEBEARER", weak = { "ice" }, resist = { "fire" },
  boss = { hpx = 0.95, phases = {
    { at = 100, moves = { { "ud_stamp", 5 }, { "ud_sap", 2 } }, every = 5, big = "ud_forty" },
    { at = 66, moves = { { "ud_stamp", 4 }, { "ud_list", 3 } }, every = 4, big = "ud_forty", say = "IT TURNS THE PAGE" },
    { at = 33, moves = { { "ud_stamp", 4 }, { "ud_list", 2 }, { "ud_sap", 2 } }, every = 3, big = "ud_forty", say = "IT HAS NOT FORGOTTEN YOU", speedUp = 1 },
  } },
}
F.ud_ruaryn = {
  name = "RUARYN", tier = 29, shape = "brute", sprite = "ud_ruaryn", family = "boss", resist = { "mind" }, weak = { "fire" },
  boss = { hpx = 1.05, phases = {
    { at = 100, moves = { { "ud_legs", 5 }, { "ud_silk", 2 } }, every = 5, big = "ud_voice" },
    { at = 66, moves = { { "ud_legs", 4 }, { "ud_spoon", 3 } }, every = 4, big = "ud_voice", say = "HE KNOWS WHERE YOU STAND" },
    { at = 33, moves = { { "ud_legs", 3 }, { "ud_spoon", 2 }, { "mind_wave", 2 } }, every = 3, big = "ud_voice", say = "HE STOPS PROTECTING HIMSELF", speedUp = 2 },
  } },
}
F.ud_mother = {
  name = "LAMPREY MOTHER", tier = 28, shape = "brute", sprite = "ud_mother", family = "roper", short = "MOTHER", weak = { "bolt" }, resist = { "ice" }, size = 3,
  boss = { hpx = 0.86, phases = {
    { at = 100, moves = { { "ud_rings", 5 }, { "ud_brine", 2 } }, every = 5, big = "ud_mouths" },
    { at = 66, moves = { { "ud_rings", 4 }, { "ud_salt", 3 } }, every = 4, big = "ud_mouths", say = "THE WATER RISES", summon = "ud_lamprey" },
    { at = 33, moves = { { "ud_rings", 4 }, { "ud_salt", 3 } }, every = 3, big = "ud_mouths", say = "THE BRIDGE IS GOING", speedUp = 1, summon = "ud_lamprey" },
  } },
}

local E = R.encounters

E.ud_lip_1 = { foes = { "ud_bat", "ud_bat", "ud_bat" }, flee = true, bg = "cave" }
E.ud_lip_2 = { foes = { "ud_hookhorror" }, flee = true, bg = "cave" }
E.ud_lip_3 = { foes = { "ud_lemure", "ud_lemure", "ud_lemure" }, flee = true, bg = "cave" }
E.ud_stair_1 = { foes = { "ud_husk", "ud_bat" }, flee = true, bg = "ruin" }
E.ud_stair_2 = { foes = { "ud_husk", "ud_husk" }, flee = true, bg = "ruin" }
E.ud_stair_3 = { foes = { "ud_hookhorror", "ud_lemure", "ud_lemure" }, flee = true, bg = "ruin" }
E.ud_web_1 = { foes = { "ud_spider", "ud_spider", "ud_spider" }, flee = true, bg = "web" }
E.ud_web_2 = { foes = { "ud_exile", "ud_exile" }, flee = true, bg = "web" }
E.ud_web_3 = { foes = { "ud_exile", "ud_lolthsworn" }, flee = true, bg = "web" }
E.ud_foot_1 = { foes = { "ud_exile", "ud_spider", "ud_spider" }, flee = true, bg = "cave" }
E.ud_foot_2 = { foes = { "ud_lolthsworn", "ud_hookhorror" }, flee = true, bg = "cave" }
E.ud_road_1 = { foes = { "ud_umber" }, flee = true, bg = "cave" }
E.ud_road_2 = { foes = { "ud_mantle", "ud_mantle", "ud_mantle" }, flee = true, bg = "cave" }
E.ud_road_3 = { foes = { "ud_myconid", "ud_umber" }, flee = true, bg = "cave" }
E.ud_seam_1 = { foes = { "ud_sapper", "ud_sapper" }, flee = true, bg = "mine" }
E.ud_seam_2 = { foes = { "ud_cinder", "ud_cinder" }, flee = true, bg = "mine" }
E.ud_seam_3 = { foes = { "ud_sapper", "ud_cinder" }, flee = true, bg = "mine" }
E.ud_under_1 = { foes = { "ud_phase", "ud_phase" }, flee = true, bg = "web" }
E.ud_under_2 = { foes = { "ud_ettercap", "ud_spider", "ud_spider" }, flee = true, bg = "web" }
E.ud_under_3 = { foes = { "ud_unsettled" }, flee = true, bg = "web" }
E.ud_salt_1 = { foes = { "ud_manta", "ud_manta" }, flee = true, bg = "brine" }
E.ud_salt_2 = { foes = { "ud_lamprey", "ud_lamprey", "ud_lamprey" }, flee = true, bg = "brine" }
E.ud_salt_3 = { foes = { "ud_drowned", "ud_manta" }, flee = true, bg = "brine" }
E.ud_boss_matron = { foes = { "ud_matron" }, flee = false, bg = "web", boss = true }
E.ud_boss_grudge = { foes = { "ud_grudge" }, flee = false, bg = "mine", boss = true }
E.ud_boss_ruaryn = { foes = { "ud_ruaryn" }, flee = false, bg = "marble", boss = true }
E.ud_boss_mother = { foes = { "ud_mother" }, flee = false, bg = "brine", boss = true }

R.art.ud_bat = "A bat the size of a dog with glowing violet moss growing along its wings."
R.art.ud_hookhorror = "A tall beaked thing like a vulture crossed with a beetle, with long curved hooks for hands, clacking."
R.art.ud_husk = "The dried husk of a horned demon from an ancient war, armour grown into its bones, one horn snapped."
R.art.ud_pitworm = "A fat pale worm, ringed like a finger, with a round mouth and no eyes at all."
R.art.ud_spider = "A black spider as big as a pony with a red hourglass of little lamps on its back."
R.art.ud_exile = "A lean drow raider in patched black silk with a hand crossbow and tired eyes."
R.art.ud_lolthsworn = "A drow priestess in a spider-web veil, holding up a staff topped with a dead spider."
R.art.ud_umber = "A huge armoured beetle-ape with four shining eyes set in a line and jaws like a pair of shovels."
R.art.ud_mantle = "A black squid-like thing that hangs from the roof like a wet cloak and drops on heads."
R.art.ud_myconid = "A man-high walking mushroom with a slow, kindly droop and a cloud of spores."
R.art.ud_sapper = "A grey duergar in a sooty leather apron with a pick and a keg of black powder on his back, still following orders."
R.art.ud_cinder = "A small glowing shape of burning coal in the rough outline of a miner, trailing smoke."
R.art.ud_unsettled = "A ragged drider with too-wide eyes, its legs bound in old bandages, talking quietly to nobody."
R.art.ud_phase = "A blue-white spider half there, drawn with a gap down the middle of it where it has stepped sideways."
R.art.ud_ettercap = "A hunched, bloated thing with a spider's fangs and long working hands trailing silk."
R.art.ud_manta = "A pale grey manta ray with a stinging tail, flying as if the air were water."
R.art.ud_lamprey = "An eel as long as a man, all round sucker of teeth, flopping upright on the wet stone."
R.art.ud_drowned = "A drowned sailor crusted white with salt, with something small and grey moving behind the ear."
R.art.ud_matron = "A gaunt drow matron in a crown of spider legs with a five-headed snake whip, riding a huge black spider."
R.art.ud_grudge = "A black iron war-engine twice a duergar's height, every inch stamped with tiny names, its mouth a slot like a ledger's spine."
R.art.ud_ruaryn = "A big armoured drider with a spoon on a cord round his neck, standing bolt upright, smiling with someone else's smile."
R.art.ud_mother = "Ring after ring of teeth as wide as a mill wheel, on a pale body rising out of grey water and lying across a stone bridge."
R.art.ud_basket = "A big wicker basket on a line going straight up out of sight."
R.art.ud_bones = "A skeleton in old harness, seated at a stone desk, with a slate in front of it."
R.art.ud_cocoon = "A human-sized bundle of grey silk hanging from the wall, wriggling a bit."
R.art.ud_anchor = "A cable of silk as thick as an arm, pegged to the rock with a drow iron spike."
R.art.ud_curtain = "A wall of heavy grey web filling a passage from floor to roof, very slightly breathing."
R.art.ud_winch = "A wooden winch drum wound with silk rope, a long crank on the side."
R.art.ud_saltgate = "A barred iron gate crusted thick and white with salt."

-- ---------------------------------------------------------------- the maps

local M = R.maps

-- A ledge round the first great drop, with Dangle's camp at the top and a pocket or two for the curious.
M.ud_abyss_1 = {
  name = "THE VIOLET ABYSS: THE LIP", theme = "cave", savepoint = true,
  rows = {
    "##########################",
    "#>......##~~~~~~~~~~~~~###",
    "###.....##~~~~~~~~~~~~~###",
    "###.....~~~~~~~~~~~~~~~###",
    "###.....~~~~~~~~~~~~~~~..#",
    "######.#~~~~~~~~~~~~~~~#.#",
    "######.#~~~~~~~~~~~~~~~#.#",
    "#......#~~~~~~~~~~~~~~~#.#",
    "#.####.#~~~~~~~~~~~~~~~#.#",
    "#.####.~~~~~~~~~~~~~~~~#.#",
    "#.####.#################.#",
    "#...##...................#",
    "###.##.##########.########",
    "#......##########......>##",
    "##########################",
  },
  npcs = {
    { id = "ud_dangle", x = 6, y = 3, sprite = "villager", script = "ud_talk_dangle" },
    { id = "ud_basket", x = 5, y = 5, sprite = "ud_basket", script = "ud_talk_basket", when = "ud_touarch_in" },
  },
  steps = {
    { x = 3, y = 2, script = "ud_scene_lip", once = true },
    { x = 7, y = 7, script = "ud_read_boots", once = true },
  },
  chests = {
    { id = "c1", x = 24, y = 5, give = "hipotion", n = 3 },
    { id = "c2", x = 2, y = 14, give = "hiether", n = 1 },
    { id = "c3", x = 3, y = 12, gold = 900 },
  },
  foes = {
    { id = "f1", x = 7, y = 10, enc = "ud_lip_1", sprite = "ud_bat" },
    { id = "f2", x = 2, y = 10, enc = "ud_lip_3", sprite = "ud_pitworm" },
    { id = "f3", x = 15, y = 12, enc = "ud_lip_2", sprite = "ud_hookhorror" },
    { id = "f4", x = 25, y = 9, enc = "ud_lip_1", sprite = "ud_bat" },
    { id = "f5", x = 18, y = 14, enc = "ud_lip_2", sprite = "ud_hookhorror" },
  },
  exits = {
    { x = 2, y = 2, world = { 60, 27 }, when = "finished" }, -- always so by now; the region test stays below ground, as its bot would wander the whole game
    { x = 24, y = 14, map = "ud_abyss_2", mx = 3, my = 2, dir = 2 },
  },
}

-- The stair the demons came up. The memorial hall is the middle room, the guardroom is the south-west one, and Corporal Wend
-- stands on the only way down to the rib causeway.
M.ud_abyss_2 = {
  name = "THE VIOLET ABYSS: THE HORNED STAIR", theme = "ruin",
  rows = {
    "########################",
    "#>.......h.......h.....#",
    "###.####.h.......h.....#",
    "###.####.+.......+.....#",
    "###.####.h.......h.....#",
    "###.####.h.......h.....#",
    "###......hhhh.hhhh###.##",
    "#..#.###.####.#######.##",
    "#.....##.####.#####~~.##",
    "#.....##.####.####~~~.##",
    "#.....##......###~~~~.##",
    "########.####.##~~~~~.##",
    "#........####.#~~~~~~.##",
    "#.######.####.#~~~~~~~##",
    "#.######.####..........#",
    "#.....##.####~~~~~~~~.##",
    "########.####~~~~~~~~>##",
    "########################",
  },
  npcs = {
    { id = "ud_bones", x = 2, y = 10, sprite = "ud_bones", script = "ud_read_bones" },
    { id = "ud_sentry", x = 14, y = 12, sprite = "villager", script = "ud_talk_sentry", unless = "ud_relieved" },
  },
  steps = {
    { x = 14, y = 3, script = "ud_read_wall", once = true },
  },
  chests = {
    { id = "c1", x = 20, y = 3, give = "hipotion", n = 3 },
    { id = "c2", x = 22, y = 13, gold = 1100 },
    { id = "c3", x = 9, y = 17, give = "hiether", n = 2 },
    { id = "c4", x = 2, y = 16, give = "oath_ring" },
  },
  foes = {
    { id = "f1", x = 9, y = 5, enc = "ud_stair_1", sprite = "ud_husk" },
    { id = "f2", x = 12, y = 5, enc = "ud_stair_2", sprite = "ud_husk" },
    { id = "f3", x = 21, y = 5, enc = "ud_stair_3", sprite = "ud_hookhorror" },
    { id = "f4", x = 4, y = 10, enc = "ud_stair_1", sprite = "ud_husk" },
    { id = "f5", x = 22, y = 10, enc = "ud_stair_2", sprite = "ud_husk" },
    { id = "f6", x = 9, y = 14, enc = "ud_stair_3", sprite = "ud_pitworm" },
    { id = "f7", x = 20, y = 15, enc = "ud_stair_2", sprite = "ud_husk" },
  },
  exits = {
    { x = 2, y = 2, map = "ud_abyss_1", mx = 23, my = 14, dir = 4 },
    { x = 22, y = 17, map = "ud_abyss_3", mx = 3, my = 2, dir = 2 },
  },
}

-- The camp of the banished, hung over two pits. The web curtain closes the south. Its two anchors are out at the ends of the
-- pits, west and east, and Fettle hangs in the larder off the camp.
M.ud_abyss_3 = {
  name = "THE VIOLET ABYSS: THE EXILE WEBS", theme = "web",
  rows = {
    "########################",
    "#>...........#.........#",
    "###.#######.##.#######.#",
    "###.#~~~~~#.##.#~~~~~#.#",
    "###.#~~~~~#....#~~~~~#.#",
    "#...#~~~~~##.###~~~~~#.#",
    "#...~~~~~~##.###~~~~~..#",
    "#...########.###########",
    "#...########.###########",
    "########.........#######",
    "#......+.........+.....#",
    "#......#.........#.....#",
    "########.........#######",
    "############.###########",
    "#......................#",
    "#.####################>#",
    "#......#################",
    "########################",
  },
  npcs = {
    { id = "ud_anchor_w", x = 4, y = 7, sprite = "ud_anchor", script = "ud_cut_west", unless = "ud_anchor_w" },
    { id = "ud_anchor_e", x = 22, y = 7, sprite = "ud_anchor", script = "ud_cut_east", unless = "ud_anchor_e" },
    { id = "ud_fettle_web", x = 3, y = 12, sprite = "ud_cocoon", script = "ud_talk_cocoon", unless = "ud_fettle_free" },
    { id = "ud_curtain", x = 13, y = 14, sprite = "ud_curtain", script = "ud_read_curtain", unless = "ud_web_down" },
  },
  steps = {
    { x = 13, y = 10, script = "ud_read_camp", once = true },
  },
  chests = {
    { id = "c1", x = 22, y = 12, give = "spider_fang" },
    { id = "c2", x = 2, y = 9, give = "hipotion", n = 3 },
    { id = "c3", x = 2, y = 17, give = "gloam_robe" },
    { id = "c4", x = 6, y = 11, gold = 1200 },
  },
  foes = {
    { id = "f1", x = 4, y = 4, enc = "ud_web_1", sprite = "ud_spider" },
    { id = "f2", x = 9, y = 2, enc = "ud_web_2", sprite = "ud_exile" },
    { id = "f3", x = 13, y = 7, enc = "ud_web_1", sprite = "ud_spider" },
    { id = "f4", x = 23, y = 4, enc = "ud_web_2", sprite = "ud_exile" },
    { id = "f5", x = 11, y = 11, enc = "ud_web_3", sprite = "ud_lolthsworn" },
    { id = "f6", x = 15, y = 12, enc = "ud_web_3", sprite = "ud_lolthsworn" },
    { id = "f7", x = 20, y = 11, enc = "ud_web_2", sprite = "ud_exile" },
    { id = "f8", x = 10, y = 15, enc = "ud_web_1", sprite = "ud_spider" },
  },
  exits = {
    { x = 2, y = 2, map = "ud_abyss_2", mx = 21, my = 15, dir = 1 },
    { x = 23, y = 16, map = "ud_abyss_4", mx = 3, my = 2, dir = 2 },
  },
}

-- The last of the Abyss. The Matron holds the room at the far side, and past her there's only the dark and the Light.
M.ud_abyss_4 = {
  name = "THE VIOLET ABYSS: THE FOOT", theme = "cave",
  rows = {
    "######################",
    "#>......##############",
    "#######.##.......#####",
    "#######.##.#####.#####",
    "#.......##.#####.#####",
    "#.#####.##.#####.#####",
    "#.#####......###.#####",
    "#.#####.####.###.#####",
    "#...###.####.#.......#",
    "#.#.###.####.#.......#",
    "#.#.########.#......>#",
    "#.#....#####.#.......#",
    "#......#####.#.......#",
    "#.....##.....#########",
    "######################",
  },
  npcs = {
    { id = "ud_matron_npc", x = 18, y = 11, sprite = "villager", script = "ud_scene_matron", unless = "ud_matron_down" },
    { id = "ud_ilzra", x = 16, y = 12, sprite = "villager", script = "ud_talk_ilzra", when = "ud_matron_down" },
  },
  steps = {
    { x = 17, y = 9, script = "ud_scene_matron", unless = "ud_matron_down" },
  },
  chests = {
    { id = "c1", x = 19, y = 9, give = "drow_sabre" },
    { id = "c2", x = 2, y = 14, give = "drow_plate" },
    { id = "c3", x = 9, y = 14, give = "tent", n = 1 },
    { id = "c4", x = 6, y = 12, give = "feather", n = 2 },
  },
  foes = {
    { id = "f1", x = 8, y = 4, enc = "ud_foot_1", sprite = "ud_exile" },
    { id = "f2", x = 13, y = 3, enc = "ud_foot_2", sprite = "ud_hookhorror" },
    { id = "f3", x = 17, y = 6, enc = "ud_foot_1", sprite = "ud_spider" },
    { id = "f4", x = 2, y = 8, enc = "ud_foot_2", sprite = "ud_lolthsworn" },
    { id = "f5", x = 13, y = 11, enc = "ud_foot_1", sprite = "ud_exile" },
  },
  exits = {
    { x = 2, y = 2, map = "ud_abyss_3", mx = 22, my = 15, dir = 1 },
    { x = 21, y = 11, script = "ud_scene_light", unless = "ud_lit" },
    { x = 21, y = 11, map = "ud_touarch", mx = 3, my = 2, dir = 2, when = "ud_lit" },
  },
}

-- Touarch wraps the foot of its pillar. The Light's own room is inside the rock, by the door on the south face.
M.ud_touarch = {
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
    "#.hhhh+hhhhh.....hhhh+hhhhh#",
    "#.h........h.....h........h#",
    "#.h........h.....h........h#",
    "#.hhhhhhhhhh.....hhhhhhhhhh#",
    "#..........................#",
    "##############>#############",
  },
  npcs = {
    { id = "ud_mag", x = 7, y = 4, sprite = "villager", script = "ud_talk_mag" },
    { id = "ud_jez_inn", x = 4, y = 5, sprite = "villager", script = "ud_talk_jez_inn", unless = "ud_jez_met" },
    { id = "ud_hask", x = 25, y = 5, sprite = "villager", script = "ud_talk_hask" },
    { id = "ud_olive", x = 8, y = 16, sprite = "villager", script = "ud_talk_olive" },
    { id = "ud_kindle", x = 14, y = 11, sprite = "villager", script = "ud_talk_kindle" },
    { id = "ud_sevria", x = 12, y = 12, sprite = "villager", script = "ud_talk_sevria" },
    { id = "ud_murgrum_t", x = 13, y = 12, sprite = "villager", script = "ud_talk_murgrum_t", when = "side_lovers" },
    { id = "ud_pell", x = 13, y = 14, sprite = "villager", script = "ud_talk_pell" },
    { id = "ud_tam", x = 20, y = 8, sprite = "villager", script = "ud_talk_tam" },
    { id = "ud_winder", x = 2, y = 5, sprite = "villager", script = "ud_talk_winder" },
    { id = "ud_fettle", x = 22, y = 8, sprite = "villager", script = "ud_talk_fettle", when = "ud_fettle_free" },
  },
  steps = {
    { x = 3, y = 2, script = "ud_scene_touarch", unless = "ud_touarch_in" },
  },
  chests = {
    { id = "c1", x = 25, y = 12, give = "tonic", n = 3 },
    { id = "c2", x = 4, y = 11, gold = 700 },
    { id = "c3", x = 25, y = 17, give = "hiether", n = 1 },
  },
  exits = {
    { x = 2, y = 2, map = "ud_abyss_4", mx = 20, my = 11, dir = 4 },
    { x = 15, y = 20, script = "ud_gate_shut", unless = "ud_met_olive" },
    { x = 15, y = 20, map = "ud_pillars", mx = 2, my = 9, dir = 2, when = "ud_met_olive" },
  },
}

-- The road under the world: a forest of pillars with the Great Pillar in the middle and a pit in the south-east. Touarch is the
-- west end, Strathe's chasm the east, Blackhold north and the Comet Seam south.
M.ud_pillars = {
  name = "THE PILLAR ROAD", theme = "cave",
  rows = {
    "##############>###############",
    "#............................#",
    "#.##..##..##..##..##..##..##.#",
    "#..........########..........#",
    "#.##..##...########.##..##...#",
    "#..........########..........#",
    "#.##..##...########.##..##...#",
    "#............................#",
    ">............................>",
    "#............................#",
    "#.##..##..##..##..##..##..##.#",
    "#....................~~~~~~~.#",
    "#.##..##..##..##..##.~~~~~~~.#",
    "#....................~~~~~~~.#",
    "#.##..##..##..##..##.~~~~~~~.#",
    "#............................#",
    "#####################>########",
  },
  npcs = {
    { id = "ud_moss", x = 8, y = 10, sprite = "villager", script = "ud_talk_moss" },
  },
  steps = {
    { x = 15, y = 2, script = "ud_read_signs", once = true },
  },
  chests = {
    { id = "c1", x = 29, y = 13, give = "web_staff" },
    { id = "c2", x = 2, y = 16, give = "hipotion", n = 3 },
    { id = "c3", x = 29, y = 2, give = "spider_silk" },
  },
  foes = {
    { id = "f1", x = 6, y = 4, enc = "ud_road_1", sprite = "ud_umber" },
    { id = "f2", x = 22, y = 4, enc = "ud_road_2", sprite = "ud_mantle" },
    { id = "f3", x = 15, y = 8, enc = "ud_road_3", sprite = "ud_myconid" },
    { id = "f4", x = 12, y = 12, enc = "ud_road_2", sprite = "ud_mantle" },
    { id = "f5", x = 24, y = 9, enc = "ud_road_1", sprite = "ud_umber" },
    { id = "f6", x = 18, y = 16, enc = "ud_road_3", sprite = "ud_umber" },
  },
  exits = {
    { x = 1, y = 9, map = "ud_touarch", mx = 15, my = 19, dir = 1 },
    { x = 15, y = 1, map = "ud_blackhold", mx = 3, my = 2, dir = 2 },
    { x = 30, y = 9, map = "ud_underweb", mx = 2, my = 10, dir = 2 },
    { x = 22, y = 17, script = "ud_seam_shut", unless = "ud_seam_open" },
    { x = 22, y = 17, map = "ud_seam", mx = 3, my = 2, dir = 2, when = "ud_seam_open" },
  },
}

-- One black road spiralling in, with niches off it. The door at the top left is the short way in. The outer ring is for those
-- with shopping to do, and the Queen's hall is at the middle of everything.
M.ud_blackhold = {
  name = "BLACKHOLD", theme = "mine", savepoint = true,
  rows = {
    "##########################",
    "#>......................##",
    "##+####.######.########.##",
    "##.########.#####.#####.##",
    "##...................##.##",
    "##.#################.##.##",
    "##.######.##########.##.##",
    "##.##.............##.##.##",
    "##.##.##..........##.##.##",
    "##.##.##..........##.##.##",
    "##.##.##..........##.##.##",
    "##.##.##############.##.##",
    "##.##.######.#######.##.##",
    "##.##................##.##",
    "##.######.######.######.##",
    "##.##.#############.###.##",
    "##......................##",
    "##########################",
  },
  npcs = {
    { id = "ud_tally", x = 8, y = 3, sprite = "villager", script = "ud_talk_tally" },
    { id = "ud_forge", x = 12, y = 4, sprite = "villager", script = "ud_talk_forge" },
    { id = "ud_bruna", x = 18, y = 4, sprite = "villager", script = "ud_talk_bruna" },
    { id = "ud_drycup", x = 13, y = 13, sprite = "villager", script = "ud_talk_drycup" },
    { id = "ud_murgrum", x = 10, y = 7, sprite = "villager", script = "ud_talk_murgrum", unless = "side_lovers" },
    { id = "ud_dimsael", x = 13, y = 10, sprite = "villager", script = "ud_talk_dimsael" },
  },
  steps = {
    { x = 3, y = 2, script = "ud_scene_blackhold", once = true },
  },
  chests = {
    { id = "c1", x = 15, y = 3, give = "storm_ward" },
    { id = "c2", x = 10, y = 15, give = "hiether", n = 2 },
    { id = "c3", x = 17, y = 15, gold = 1400 },
    { id = "c4", x = 6, y = 16, give = "panacea", n = 2 },
    { id = "c5", x = 20, y = 16, give = "sage_ring" },
  },
  exits = {
    { x = 2, y = 2, map = "ud_pillars", mx = 15, my = 2, dir = 3 },
  },
}

-- The worked-out coal between the two pillars. The lovers' tin is in the south-west, and the east end runs to the wall with
-- Barris's mark on it.
M.ud_seam = {
  name = "THE COMET SEAM", theme = "mine",
  rows = {
    "########################",
    "#>....#####.....########",
    "#####.#####.###.########",
    "#####.......###.....####",
    "#.....#####.###.###.####",
    "#.###.#####.###.###.####",
    "#.###...........###.####",
    "#.###.#############.####",
    "#.....#############.####",
    "###.###############....#",
    "###.##################.#",
    "#.....################.#",
    "#.....#h.............+.#",
    "#######h.............h##",
    "########################",
  },
  npcs = {
    { id = "ud_barris", x = 10, y = 13, sprite = "villager", script = "ud_talk_barris" },
  },
  steps = {
    { x = 4, y = 12, script = "ud_read_tin", once = true },
    { x = 21, y = 13, script = "ud_scene_grudge", unless = "ud_grudge_down" },
  },
  chests = {
    { id = "c1", x = 2, y = 12, give = "hipotion", n = 3 },
    { id = "c2", x = 16, y = 2, gold = 1600 },
    { id = "c3", x = 12, y = 14, give = "life_ring" },
    { id = "c4", x = 2, y = 7, give = "hiether", n = 2 },
  },
  foes = {
    { id = "f1", x = 6, y = 4, enc = "ud_seam_1", sprite = "ud_sapper" },
    { id = "f2", x = 12, y = 7, enc = "ud_seam_2", sprite = "ud_cinder" },
    { id = "f3", x = 4, y = 9, enc = "ud_seam_3", sprite = "ud_sapper" },
    { id = "f4", x = 20, y = 5, enc = "ud_seam_2", sprite = "ud_cinder" },
    { id = "f5", x = 22, y = 10, enc = "ud_seam_1", sprite = "ud_sapper" },
  },
  exits = {
    { x = 2, y = 2, map = "ud_pillars", mx = 22, my = 16, dir = 1 },
  },
}

-- The web that caught a falling city, and the only way up to it from the Pillar Road. Strands and platforms over nothing. Mmrk
-- stands at the head of the last strand, and two of the three winches bring the lift.
M.ud_underweb = {
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
    { id = "ud_mmrk", x = 14, y = 3, sprite = "villager", script = "ud_talk_mmrk", unless = "ud_lift_up" },
    { id = "ud_mmrk_2", x = 15, y = 2, sprite = "villager", script = "ud_talk_mmrk", when = "ud_lift_up" },
    { id = "ud_winch_a", x = 7, y = 16, sprite = "ud_winch", script = "ud_wind_a" },
    { id = "ud_winch_b", x = 23, y = 16, sprite = "ud_winch", script = "ud_wind_b" },
    { id = "ud_winch_c", x = 22, y = 4, sprite = "ud_winch", script = "ud_wind_c" },
  },
  steps = {
    { x = 14, y = 8, script = "ud_read_baskets", once = true },
  },
  chests = {
    { id = "c1", x = 16, y = 9, give = "hipotion", n = 3 },
    { id = "c2", x = 9, y = 16, give = "hiether", n = 2 },
    { id = "c3", x = 22, y = 16, give = "panacea", n = 2 },
    { id = "c4", x = 12, y = 7, gold = 1500 },
  },
  foes = {
    { id = "f1", x = 5, y = 7, enc = "ud_under_1", sprite = "ud_phase" },
    { id = "f2", x = 10, y = 4, enc = "ud_under_2", sprite = "ud_ettercap" },
    { id = "f3", x = 14, y = 11, enc = "ud_under_3", sprite = "ud_unsettled" },
    { id = "f4", x = 8, y = 13, enc = "ud_under_1", sprite = "ud_phase" },
    { id = "f5", x = 18, y = 12, enc = "ud_under_3", sprite = "ud_unsettled" },
    { id = "f6", x = 24, y = 14, enc = "ud_under_2", sprite = "ud_ettercap" },
    { id = "f7", x = 22, y = 8, enc = "ud_under_3", sprite = "ud_unsettled" },
  },
  exits = {
    { x = 1, y = 10, map = "ud_pillars", mx = 29, my = 9, dir = 4 },
    { x = 13, y = 1, map = "ud_strathe", mx = 14, my = 17, dir = 1 },
  },
}

-- The city on its web. The Queen's hall is north, the Commons and the Hunt either side of the market, the Quiet House off the
-- east end of the avenue, and the Web Road leaves by the west end of the lower street.
M.ud_strathe = {
  name = "STRATHE THE WEBBED RECLUSE", theme = "web", savepoint = true,
  rows = {
    "############################",
    "#~~~~~~hhhhhhhhhhhhhh~~~~~~#",
    "#~~~~~~h............h~~~~~~#",
    "#~~~~~~h............h~~~~~~#",
    "#~~~~~~h............h~~~~~~#",
    "#~~~~~~hhhhhh+hhhhhhh~~~~~~#",
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
    { id = "ud_halryna", x = 14, y = 3, sprite = "villager", script = "ud_talk_halryna", unless = "ud_quiet_seen" },
    { id = "ud_halryna_2", x = 14, y = 3, sprite = "villager", script = "ud_talk_halryna", when = "ud_jezzara_in" },
    { id = "ud_ruaryn", x = 16, y = 4, sprite = "villager", script = "ud_talk_ruaryn", unless = "ud_quiet_seen" },
    { id = "ud_commons", x = 8, y = 10, sprite = "villager", script = "ud_talk_commons" },
    { id = "ud_houndrin", x = 24, y = 10, sprite = "villager", script = "ud_talk_houndrin" },
    { id = "ud_nulliira", x = 27, y = 8, sprite = "villager", script = "ud_talk_nulliira" },
    { id = "ud_sael", x = 12, y = 10, sprite = "villager", script = "ud_talk_sael" },
    { id = "ud_iliss", x = 17, y = 11, sprite = "villager", script = "ud_talk_iliss" },
  },
  steps = {
    { x = 14, y = 17, script = "ud_scene_strathe", unless = "ud_strathe_in" },
  },
  chests = {
    { id = "c1", x = 5, y = 10, give = "hipotion", n = 2 },
    { id = "c2", x = 25, y = 10, give = "tonic", n = 3 },
    { id = "c3", x = 9, y = 3, gold = 1000 },
  },
  exits = {
    { x = 14, y = 18, map = "ud_underweb", mx = 13, my = 2, dir = 3 },
    { x = 28, y = 7, script = "ud_quiet_shut", unless = "ud_audience" },
    { x = 28, y = 7, map = "ud_quiet", mx = 2, my = 6, dir = 2, when = "ud_audience" },
    { x = 1, y = 12, script = "ud_road_shut", unless = "ud_jezzara_in" },
    { x = 1, y = 12, map = "ud_stair", mx = 3, my = 2, dir = 2, when = "ud_jezzara_in" },
  },
}

-- White and silent. Wards, records and the Mother's office on the north side, the cold room on the south, and the Cradle down
-- at the end behind the antechamber.
M.ud_quiet = {
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
    { id = "ud_sleeper1", x = 3, y = 3, sprite = "villager", script = "ud_talk_sleeper" },
    { id = "ud_sleeper2", x = 6, y = 3, sprite = "villager", script = "ud_talk_sleeper" },
    { id = "ud_sleeper3", x = 4, y = 9, sprite = "villager", script = "ud_talk_sleeper" },
    { id = "ud_attendant", x = 20, y = 8, sprite = "villager", script = "ud_talk_attendant", unless = "ud_quiet_seen" },
    { id = "ud_halryna_c", x = 20, y = 14, sprite = "villager", script = "ud_talk_cradle", unless = "ud_jezzara_in" },
    { id = "ud_jez_c", x = 19, y = 14, sprite = "villager", script = "ud_talk_cradle", unless = "ud_jezzara_in" },
  },
  steps = {
    { x = 13, y = 3, script = "ud_read_records", once = true, unless = "ud_jezzara_in" },
    { x = 13, y = 8, script = "ud_scene_jars", unless = "ud_quiet_seen" },
    { x = 20, y = 12, script = "ud_scene_cradle", unless = "ud_jezzara_in" },
  },
  chests = {
    { id = "c1", x = 22, y = 2, give = "panacea", n = 2 },
    { id = "c2", x = 7, y = 8, give = "hipotion", n = 2 },
    { id = "c3", x = 15, y = 10, give = "wakeroot", n = 3 },
  },
  exits = {
    { x = 1, y = 6, map = "ud_strathe", mx = 27, my = 7, dir = 4 },
  },
}

-- The stair down the cavern wall, along the top and down the east side, with the salt gate on it and Ibbit's wreck below that,
-- and then the bridge, one square wide and all the way across.
M.ud_stair = {
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
    { id = "ud_saltgate", x = 28, y = 8, sprite = "ud_saltgate", script = "ud_talk_saltgate", unless = "ud_gate_open" },
    { id = "ud_ibbit", x = 26, y = 11, sprite = "villager", script = "ud_talk_ibbit" },
  },
  steps = {
    { x = 3, y = 2, script = "ud_scene_rain", once = true },
    { x = 6, y = 3, script = "ud_read_marker", once = true },
    { x = 14, y = 17, script = "ud_scene_mother", unless = "ud_bridge_won" },
  },
  chests = {
    { id = "c1", x = 2, y = 8, give = "hiether", n = 2 },
    { id = "c2", x = 12, y = 8, gold = 2000 },
    { id = "c3", x = 24, y = 10, give = "feather", n = 2 },
    { id = "c4", x = 24, y = 12, give = "wakeroot", n = 3 },
  },
  foes = {
    { id = "f1", x = 20, y = 2, enc = "ud_salt_1", sprite = "ud_manta" },
    { id = "f2", x = 8, y = 5, enc = "ud_salt_2", sprite = "ud_lamprey" },
    { id = "f3", x = 27, y = 5, enc = "ud_salt_1", sprite = "ud_manta" },
    { id = "f4", x = 28, y = 14, enc = "ud_salt_3", sprite = "ud_drowned" },
    { id = "f5", x = 22, y = 17, enc = "ud_salt_2", sprite = "ud_lamprey" },
    { id = "f6", x = 7, y = 17, enc = "ud_salt_3", sprite = "ud_drowned" },
  },
  exits = {
    { x = 2, y = 2, map = "ud_strathe", mx = 2, my = 12, dir = 2 },
    { x = 1, y = 17, map = "ud_crysathula", mx = 25, my = 8, dir = 4 },
  },
}

-- A thin dry street in a green bubble, with salt rain on the outside of everything. Shops and rooms north and south, the Stair
-- at the east end and the Cortex Nest at the west.
M.ud_crysathula = {
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
    "#~~......................#",
    "#~~hhhh+hhh~~hhhh+hhhh~~~#",
    "#~~h......h~~h.......h~~~#",
    "#~~h......h~~h.......h~~~#",
    "#~~hhhhhhhh~~hhhhhhhhh~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~#",
    "##########################",
  },
  npcs = {
    { id = "ud_zhar", x = 23, y = 7, sprite = "villager", script = "ud_talk_zhar" },
    { id = "ud_sult", x = 13, y = 7, sprite = "villager", script = "ud_talk_sult" },
    { id = "ud_sweeper", x = 18, y = 9, sprite = "villager", script = "ud_talk_sweeper" },
    { id = "ud_uln", x = 7, y = 4, sprite = "villager", script = "ud_talk_uln" },
    { id = "ud_pod", x = 17, y = 4, sprite = "villager", script = "ud_talk_pod" },
    { id = "ud_vel", x = 8, y = 12, sprite = "villager", script = "ud_talk_vel" },
  },
  steps = {
    { x = 25, y = 8, script = "ud_scene_crysathula", unless = "ud_crys_in" },
  },
  chests = {
    { id = "c1", x = 20, y = 5, give = "hiether", n = 2 },
    { id = "c2", x = 5, y = 12, give = "mind_ward" },
    { id = "c3", x = 19, y = 11, give = "feather", n = 2 },
  },
  exits = {
    { x = 26, y = 8, map = "ud_stair", mx = 2, my = 17, dir = 2 },
    { x = 1, y = 8, map = "ud_nest", mx = 11, my = 13, dir = 1 },
  },
}

-- One long hall, with the mother brain behind green glass along the north wall. The old stair down to the Lower Dark is Zalabarula's,
-- at the back of the east bay, and it isn't there to be found until she says so.
M.ud_nest = {
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
    { id = "ud_vierrela", x = 11, y = 6, sprite = "villager", script = "ud_scene_nest", unless = "ud_done" },
  },
  steps = {
    { x = 11, y = 8, script = "ud_scene_nest", unless = "ud_done" },
  },
  exits = {
    { x = 11, y = 14, map = "ud_crysathula", mx = 2, my = 8, dir = 2 },
    { x = 19, y = 11, script = "ud_stair_shut", unless = "ud_done" },
    { x = 19, y = 11, map = "vt_vault_1", mx = 3, my = 3, dir = 2, when = "ud_done" },
  },
}

-- ---------------------------------------------------------------- the Lip

S.ud_scene_lip = {
  t("The road stops. There's no warning and no railing. The Empyreal Mountains simply open, and violet light comes up out of the ground, as if something down there had left a lamp on."),
  t("The wind comes up too, warm and wet, and it smells of old coins."),
  owlin("The eye has turned in its cloth again, {hero}. It's given up on north and west, and started looking straight down. I don't envy you carrying it. It's like having a very patient opinion in one's bag."),
  deserter("Down it is, then. There's a camp on the ledge, friend, and the last shop before a hole is always worth a look."),
  cleric("There are no shrines to my lady below this ledge. It isn't that she's unwelcome. She's never needed one down there. The business comes to her."),
}

S.ud_talk_dangle = {
  { when = "ud_boot", steps = {
    dangle("Your boot's still on the pile. That's either good luck or a boot. I've never been able to tell."),
  } },
  ask(dangle("Mabbet Dangle: rope, pitons, lamp oil and sound advice. Mind the edge, it's the only one we've got. You'll be going down. Nobody comes up here for the view."), {
    topic("How many people come back up?", {
      dangle("Forty-one years I've had this pitch, and I've never had a single complaint. You think about that for as long as you like. I charge by the coil."),
    }),
    { "We're going down.", {
      dangle("Left hand on the wall, then, and if the wall moves, apologise. Mind how you go."),
    } },
    { "Show me what you've got.", {
      { shop = "ud_dangle" },
    } },
  }),
}

S.ud_read_boots = {
  t("A cairn stands at the head of the path, and it's made of boots. Left boots, hundreds of them, tied by the laces, with a name chalked on every heel."),
  cleric("It's an old custom. You leave one behind, so that you'll have to come back for it."),
  { choice = {
    { "Walk on.", {} },
    { "Leave a boot.", {
      t("You tie yours to the pile, and you're now rather lopsided. The doctor hands you a spare, without comment."),
      { set = "ud_boot" },
    } },
  } },
}

S.ud_talk_basket = {
  ask({ text = "A basket on a very long line, and a speaking tube tied to the rim." }, {
    { "Stay up here.", {} },
    { "Ride down to Touarch.", {
      t("You shut your eyes. It's a good deal quicker than the way you came, and it swings more."),
      { warp = { "ud_touarch", 4, 2, 2 } },
    } },
  }),
}

-- ---------------------------------------------------------------- the Horned Stair

S.ud_read_wall = {
  t("A long hall, cut by people who expected to be remembered. Names run along both walls from floor to roof, thousands of them."),
  owlin("The Horned War. These are the ones who held the stair against the demons. The carving stops halfway along the second wall. I imagine the carvers were needed elsewhere."),
}

S.ud_read_bones = {
  t("A skeleton sits at a stone desk in a soldier's harness, with a stylus still in its finger bones. In front of it is the watch roster, scratched on slate so that it would last."),
  t("RELIEF AT THE BELL. GIVE THE WORD OR BE REFUSED. Below that is a column of words, one to a day. HOLD FAST. IRON. HOLD FAST AGAIN. The last line of all says: LAMPLIGHT."),
  { set = "ud_read_roster" },
}

S.ud_talk_sentry = {
  t("A soldier stands in the middle of the stair. You can see the far wall through his chest. He has a spear, and it's pointed at you, with very little hope."),
  sentry("Halt. Stand and give the word. I've been told there's a relief coming. I've been told that for some time."),
  { when = "ud_read_roster", steps = {
    t("You think of a slate in the guardroom, and of the last line on it."),
  } },
  ask(sentry("The word, if you please. I'm sorry. I can't let anyone by without it. It's the only thing I've got left."), {
    topic("How long have you been here?", {
      sentry("Since the bell. They said to hold till the bell, and the bell's not gone. I think it may be getting late. I can't feel my feet, but I've put that down to the cold."),
    }),
    topic('"Hold fast."', {
      sentry("That was the word for yesterday. Or the day before. It's a very good word, but I can't accept it."),
    }),
    { '"Lamplight."', {
      sentry("Lamplight. That's... yes. That's today's. You're the relief? I'd started to think I'd misheard."),
      { choice = {
        { "We're your relief. Stand down, Corporal.", {
          sentry("Oh, that's good. That's very good. The next lot will want telling about the draught on this step."),
        } },
        { "The war's over. You can rest.", {
          sentry("Over. Did we win? No, don't tell me. I'd only want to know who got the credit."),
        } },
      } },
      cleric("You've held long enough, soldier. I'll take your name, if you'd like. Someone ought to have it in writing."),
      sentry("Wend. Corporal Wend, Third Stair. Nobody's ever asked."),
      t("The sister ties a black thread to the butt of his spear. He looks down at his feet. Then very slowly, and with enormous relief, he sits."),
      t("There's a spear on the stair. After a moment there isn't."),
      deserter("I've watched a lot of people die, friend. I've never seen anyone so glad to be given permission."),
      { set = "ud_relieved" },
    } },
    { "We'll come back.", {
      sentry("I'll be here. I hope that doesn't sound like a threat."),
    } },
  }),
}

-- ---------------------------------------------------------------- the Exile Webs

S.ud_read_camp = {
  t("The camp of the Lolth-sworn. Silk tents, black and very clean. A shrine in the shape of a spider, made of old swords. Someone has scratched days on a plank in neat tens, year after year of them."),
  t('Nailed over the tally is a note in a beautiful hand: "You will have your throne when my work is done. Be patient. You are so good at it. V."'),
}

S.ud_talk_cocoon = {
  t("A bundle of silk hangs against the wall, about four feet long, and it's swearing."),
  fettle("Is that boots? That's boots. If you're a spider, I've got a family who'd miss me. If you're not, there's a knife in my left sock, and I can't reach my left sock."),
  ask(fettle("Well? Are you a spider? I'd want to know before I say anything else about your mother."), {
    { "Cut the gnome down.", {
      t("A small, furious deep gnome falls out of the silk, with a lamp still clipped to her belt and a very large number of opinions."),
      fettle("Fettle, lamp-runner of Touarch, third class. I came up to trim the marker lamps and got trimmed."),
      fettle("You want the south way? That curtain's held by two great cables, out at the end of each pit, west and east. Cut both and the lot comes down. After that, follow the Light."),
      fettle("There's a drink in it if you make the city. I'm leaving now, very fast. No offence."),
      { set = "ud_fettle_free" },
    } },
    { "Leave it hanging for now.", {
      fettle("Oh, very nice. Very surface."),
    } },
    topic("Why does it smell of soup?", {
      fettle("That's me. They baste. Don't look at me like that."),
    }),
  }),
}

S.ud_read_curtain = {
  t("A wall of grey web fills the passage, as thick as a mattress. A blade only makes it angry. Two great cables run off overhead, one west and one east."),
}

local CURTAIN_FALLS = {
  { all = { "ud_anchor_w", "ud_anchor_e" }, steps = {
    { sfx = "thud" },
    t("The second cable goes with a sound like a very long sigh. Somewhere behind you, eleven years of somebody's patient work slides down off the roof and lies in a heap."),
    { set = "ud_web_down" },
  }, other = {
    t("The cable goes slack and whips away. The whole web shudders, and leans. It's still holding by the other one."),
  } },
}

S.ud_cut_west = {
  ask({ text = "A cable of silk as thick as your arm, spiked to the rock with drow iron. It's humming." }, {
    { "Cut it.", { { set = "ud_anchor_w" }, CURTAIN_FALLS[1] } },
    { "Leave it.", {} },
  }),
}

S.ud_cut_east = {
  ask({ text = "A cable of silk as thick as your arm, spiked to the rock with drow iron. It's humming." }, {
    { "Cut it.", { { set = "ud_anchor_e" }, CURTAIN_FALLS[1] } },
    { "Leave it.", {} },
  }),
}

-- ---------------------------------------------------------------- the Foot

S.ud_scene_matron = {
  t("The floor of the Abyss at last. The violet stops here. In a chair made of spiders' legs a drow woman sits waiting, with a very large spider beside her like a dog."),
  matron("You cut my curtain. That was eleven years' work. Stand where I can see you, surfacers. I'd like to look at what she's sent."),
  ask(matron("Vierrela promised me the throne of Strathe, and all I've had for it is a note. She'd send something to try the door. Well? Are you what she sent?"), {
    topic("Who is Vierrela to you?", {
      matron("We were lords in Strathe, before she made the spiders sane. I went to her on my knees, and I sold her the way to a nothic ruin with an old scroll in it. She went somewhere, and came back with something in a jar. I've wondered since what I sold."),
    }),
    { "Nobody sent us. Stand aside.", {
      matron("Nobody ever thinks they were sent. Lolth doesn't hear much down here. I've checked. So I shall have to do this myself."),
    } },
    { "We're going through you, then.", {
      matron("Yes. That's how it was put to me as well."),
    } },
  }),
  { battle = "ud_boss_matron" },
  t("The chair goes over. The great spider folds its legs, one at a time, like someone putting away a tent. Sabral looks at the dark for a while, as though waiting to be told something."),
  deserter("V. That's this Vierrela, friend, and I'd like to know who she is. She's had these people waiting in a hole for eleven years, for something she never meant to give them."),
  { set = "ud_matron_down" },
}

S.ud_talk_ilzra = {
  t("A young drow woman stands by the fallen chair with a roll of paper."),
  ilzra("Mother told me I'd be a princess of Strathe. I was born in a cave. I've only ever seen caves. I've got a whole speech for when we march in. It's very good. Nobody's ever heard it."),
  ask(ilzra("What am I supposed to do now?"), {
    topic("Do the speech.", {
      ilzra("People of Strathe. We have returned. Long have we... um. Long have we been in a cave. It was better with a balcony."),
    }),
    { "Go to Touarch. They take in anyone.", {
      ilzra("Gnomes. My mother would die. Oh. Well, yes. I'll think about it."),
    } },
  }),
}

S.ud_scene_light = {
  t("Past the last ledge the dark is complete. It isn't the dark of a room with the lamps out. This dark has never had anything else in it."),
  t("You stand in it for some time, with your hand on the doctor's shoulder and the sister's hand on yours."),
  t("Then, a very long way off, a line of warm yellow comes round, slow as the hand of a clock. It passes over you, and goes on."),
  owlin("A lighthouse. Under the world. Whoever built that has either gone quite mad, or had the kindest idea I've ever heard."),
  deserter("It's coming round again. Walk toward it, friend, before someone sends us a bill."),
  { big = "THE LIGHT OF TOUARCH" },
  { set = "ud_lit" },
  { warp = { "ud_touarch", 3, 2, 2 } },
}

-- ---------------------------------------------------------------- Touarch

S.ud_scene_touarch = {
  t("A city of deep gnomes is wrapped round the foot of a pillar, a column of black rock as wide as Scythebreak, going up until the dark wins. There's coal smoke, and lamps, and somebody is baking. High in the rock, the great Light goes round."),
  t("Nobody stares. A small grey person takes your names, writes down the hour, and tells you, as if you might have forgotten, that you're not lost any more."),
  deserter("Everyone off the Light goes to see the old queen, they say. South-west, the house with the fire in it."),
  { set = "ud_touarch_in" },
}

local OLIVE_ROAD = {
  olive("The Vault? You've a fine sense of occasion. Show me that eye. No, put it away. It's got a nasty way of looking."),
  olive("There's one way down that I ever heard of, under Crysathula, in the mind flayers' own city, so you'll be asking Vierrela's leave. To reach the salt you need the Web Road, and that belongs to Strathe."),
  olive("So take the south gate and the Pillar Road, east till it smells of crab, and ask for Queen Halryna. She's a decent soul, for someone with that many knees."),
  olive("And you, {hero}, is it? You've a very restful sort of face. I'd have that looked at."),
  { set = "ud_met_olive" },
}

S.ud_talk_olive = {
  t("A tiny, ancient gnome sits by the fire with her feet on a coal scuttle, cracking nuts. The nuts are in a crown. It's very old and very heavy, and there are shells in it."),
  { when = "ud_met_olive", other = {
    olive("Another lot off the Light. Sit down, you've got the look. Olive Synny, queen here, on account of I stole the right hat. Have a walnut."),
  } },
  { when = "ud_page_shown", other = {
    { has = "ud_page", steps = {
      t("You lay the sheet of copper on the coal scuttle. She reads it through once, holding it a long way off. She doesn't crack a nut for some time."),
      olive("Sixty-three years I've been a thief. I'd got rather good at it."),
      olive("He could have told them. No, he couldn't, could he? That was the whole trick. Take it to Dimsael. Tell her it's the only thing I ever stole that I was asked to."),
      { set = "ud_page_shown" },
    } },
  } },
  { when = "side_lovers", steps = {
    olive("I've had a very stiff letter from Dimsael. It says 'yours' at the bottom. I've had it framed."),
  } },
  ask(olive("So what's brought you down, past all the reasons not to come?"), {
    topic("Is that the Crown of Comets?", {
      olive("It is. It gives you the right to rule every duergar living, and a very bad neck. I stole it off Barris Underbelly sixty-three years ago. It holds about two pounds of walnuts."),
    }),
    topic("Why keep a light burning down here?", {
      olive("I was lost once, as a girl. Eleven days. I swore that if I ever got hold of a city, nobody would have to do that again. Then I got hold of a city."),
    }),
    { "We're following this eye to the Nightmare Vault.", {
      { when = "ud_met_olive", steps = {
        olive("So you've said. South gate, Pillar Road, east till it smells of crab. Go on with you."),
      }, other = OLIVE_ROAD },
    } },
  }),
}

S.ud_gate_shut = {
  t("A small gnome with a large ledger is sitting across the south gate. Everyone off the Light sees the old queen first, she says. It isn't a rule. It's just that nobody has ever got past her."),
}

S.ud_talk_kindle = {
  ask(kindle("Tollo Kindle, keeper of the Light. Forty tons a night go down that hopper. Every year the council asks if that's sensible. Every year I turn the Light off for one minute, and they stop asking."), {
    topic("Who have you found?", {
      kindle("Four thousand, one hundred and six: miners, thieves, two bishops, and a horse, walking up the beam on its own. We gave it a pension."),
    }),
    topic("What do you see from up there?", {
      kindle("Lately there's been folk at the far edge of the beam, out east. They don't come in. They stand still with no lamps, facing away from us, and by morning they've gone."),
      kindle("I've seen a lot of lost people. They wave. These ones aren't lost. That's what I don't like."),
    }),
    { "Keep it burning.", {
      kindle("I intend to. That's the job, friend. It's the whole of the job."),
    } },
  }),
}

S.ud_talk_mag = {
  ask(mag("Welcome to the Lost and Found. Beds are sixty, and if you came in off the Light your first drink's on the house, because you'll want it."), {
    { "A bed, please.", {
      { inn = 60 },
    } },
    { "Not tonight.", {} },
  }),
}

S.ud_talk_jez_inn = {
  t("Someone at the end of the bench is sitting about a yard to the left of where she's sitting. Your eyes keep sliding off her: a long, grey, cat-shaped woman, with something extra moving at her shoulders."),
  jezzara("I've paid for your beds. Don't thank me, it isn't kindness. I like to see what's been ordered before it arrives."),
  { heal = true },
  { set = "ud_jez_met" },
  ask(jezzara("No, I'm over here. Everyone does that. You'd be the surface party. You're slower than I was told."), {
    topic("Who told you about us?", {
      jezzara("The person who tells me everything. She's left me instructions about you. They say: 'Not that one. That one's spoken for.' I've never had that before. I'd love to know what it means."),
    }),
    topic("What are you, exactly?", {
      jezzara("Tabaxi on my mother's side. The rest is displacer beast, and I don't recommend asking about the wedding. I'm always a yard from where you think I am. It's a good way to earn a living, and a terrible way to pour a drink."),
    }),
    { "What's your business here?", {
      jezzara("Travel. I'm going to the city of spiders to see a queen. Everybody should have a hobby. Enjoy the bed."),
    } },
  }),
  t("You look down at your drink, and when you look up the bench is empty."),
}

S.ud_talk_hask = {
  hask("Hask Cobble, general goods. It's all good stock, and all second hand, from people who've stopped needing it. The previous owners have raised no objection."),
  { choice = {
    { "Show me.", { { shop = "ud_hask" } } },
    { "Not just now.", {} },
  } },
}

S.ud_talk_pell = {
  ask(pell("Ah, fellow travellers! Sir Aldous Pell, of the Pell Expedition. I'm stopping here briefly for directions. Nine years. I don't suppose you know the way out?"), {
    topic("The way out is up.", {
      pell("Is it? How extraordinary. I've got it down here as 'left'. Do you know, it may be that this is a map of somewhere else. I did wonder about all the sea."),
    }),
    { "Good luck, Sir Aldous.", {
      pell("Thank you! I'll be off directly. First thing tomorrow."),
    } },
  }),
}

S.ud_talk_tam = {
  ask(tam("Are you from Up? Is it true about the sky? How far does it go?"), {
    { "It doesn't stop. It just keeps going.", {
      tam("That's horrible. How do you sleep? I'd want someone to put a lid on it."),
    } },
    { "It's like the biggest cavern there is.", {
      tam("Oh, that's all right, then. Who's holding it up? We've got pillars. I could send some."),
    } },
  }),
}

S.ud_talk_winder = {
  ask(winder("Basket line, to the Lip, in about an hour, if you don't mind swinging. There's a basket at the top that'll bring you back."), {
    { "Stay here.", {} },
    { "Take us up.", {
      t("You'd rather not talk about the next hour."),
      { warp = { "ud_abyss_1", 4, 2, 2 } },
    } },
  }),
}

S.ud_talk_fettle = {
  { when = "ud_fettle_paid", steps = {
    fettle("Third class still, if you can believe it. I've put in for a transfer to anywhere with less silk."),
  }, other = {
    fettle("It's the boots! You lived. Well, a promise is a promise. I said a drink, but I've thought about it, and this was in a dead bishop's bag. It's worth more than I am, and I'd rather not owe you."),
    { give = "tent", n = 2 },
    { set = "ud_fettle_paid" },
  } },
}

S.ud_talk_sevria = {
  { when = "side_lovers", steps = {
    sevria("The coal books have never been so wrong, and I don't care. He's doing the sums. He keeps carrying the grudge."),
  }, other = {
    { has = "ud_page", steps = {
      sevria("You've got something. I can tell, you're walking as if it weighs more than it does. Take it where it has to go. Please."),
    }, other = {
      { when = "ud_seam_open", steps = {
        sevria("He's answered? Eleven thousand. Oh, that idiot. The Seam's off the south side of the Pillar Road. You'll want a lamp."),
      }, other = {
        { has = "ud_letter", steps = {
          sevria("Blackhold's north along the Pillar Road. Just give it to him. Thirty-one days. I keep doing the coal sums wrong."),
        }, other = {
          sevria("Coal book. If you've come about the smoke, it's Princess Sevria, and I don't care. If you're going anywhere near Blackhold, it's just Sevria, and please sit down."),
          ask(sevria("Are you? Going near Blackhold? It's north, up the Pillar Road."), {
            topic("Why Blackhold?", {
              sevria("There's a prince there. I've been writing to him for four years. We met in an old seam between the pillars. He'd come to sabotage it. I'd come to sabotage it first."),
            }),
            { "We can take him a letter.", {
              sevria("He's stopped answering. Thirty-one days. Murgrum Coalcinder would write to me from his own funeral, so something's wrong. Don't let him read it out loud, he does voices."),
              { give = "ud_letter" },
            } },
            { "Not this time.", {} },
          }),
        } },
      } },
    } },
  } },
}

S.ud_talk_murgrum_t = {
  murgrum("I've been given a shovel. Everyone keeps telling me jokes, and I write them all down, and I'm told that isn't how it works."),
}

-- ---------------------------------------------------------------- the Pillar Road

S.ud_read_signs = {
  t("Two signposts stand side by side at the fork. One, in neat gnomish, says: BLACKHOLD, NORTH. MIND THE SMELL. The other, in hard duergar capitals, says: TOUARCH, WEST. THIEVES."),
  t("Someone has corrected the second one, in a small careful hand, to THIEVES (ROYAL). Both are full of crossbow bolts."),
}

S.ud_talk_moss = {
  t("A mushroom the height of a man turns toward you. A slow puff of spores drifts out, and you find that you know what it's saying, and that you've always agreed."),
  ask(moss("WE ARE THE ROAD-MOSS. YOU ARE TIRED. SIT. NOTHING IS URGENT. NOTHING HAS EVER BEEN URGENT."), {
    { "Sit down for a while.", {
      { heal = true },
      { save = true },
      t("You seem to have sat for some time. Everyone feels very much better, and slightly mouldy."),
    } },
    topic("What do you know about the Blightmare?", {
      moss("WE KNOW OF A THING THAT GROWS IN THE DARK AND WAITS. WE THINK IT IS VERY LIKE US. WE THINK YOU SHOULD BE MORE WORRIED."),
    }),
    { "Thanks. We'll keep moving.", {
      moss("WHY."),
    } },
  }),
}

S.ud_seam_shut = {
  t("A steel shutter closes an old mine road, with the Coalcinder mark on one side and a very small drawing of a walnut on the other. It's locked."),
}

-- ---------------------------------------------------------------- Blackhold

S.ud_scene_blackhold = {
  t("Blackhold climbs its pillar in one long black road, round and round, cut through obsidian so dark that the lamps seem to fall into it. It's very clean, and very quiet, and everyone who looks at you writes something down."),
  deserter("I've been in a lot of places that didn't want me, friend. This is the first that's kept a record of it."),
}

S.ud_talk_tally = {
  { when = "side_lovers", steps = {
    { when = "ud_grudge_filed", steps = {
      tally("Struck, all of them, and thirty-eight thousand still to go. Yours is the only live entry in the Book: the Clinic, for everything. I've kept it. A Keeper has to have something."),
    }, other = {
      tally("Struck, all of them, and thirty-eight thousand still to go. I hear gnomes have hobbies."),
    } },
  }, other = {
    ask(tally("Halt and declare. Name, people of origin, and any grudges you're bringing into the city. A party, is it? I can do you a group grudge. It saves on ink."), {
      topic("What is all this?", {
        tally("The Book of Grudges. Forty thousand, one hundred and eighteen entries, every wrong ever done to the duergar. Number one is the Crown of Comets. Number forty thousand and eighteen is a gnome who looked at my cousin's hat."),
      }),
      { "No grudges, thanks.", {
        tally("None at all? At your age? I'm putting you down as suspicious."),
      } },
      { "Put me down for the Clinic.", {
        tally("Clinic, Plexian, surface. 'For everything.' It's vague, but I like your heart. Entered."),
        { set = "ud_grudge_filed" },
      } },
    }),
  } },
}

S.ud_talk_forge = {
  forge("Hilde. I make things that hurt gnomes. Pay first. We've had people change their minds."),
  { choice = {
    { "Show me.", { { shop = "ud_forge" } } },
    { "Not just now.", {} },
  } },
}

S.ud_talk_bruna = {
  ask(bruna("Bruna Ironlip, last of Barris Underbelly's shield-line. Ninety-four years old, and I've kept all my teeth and all my hate. What do you want?"), {
    topic("Tell me about Barris.", {
      bruna("Biggest liar I ever loved. The day the Crown was stolen, the whole hold was howling. I went in to tell him, and he was sitting on his bed with his boots off, laughing till he wept. He never spoke of it. Within the year he'd walked down into the old seam and sealed it behind him."),
      bruna("I've not told that to the Keeper. It doesn't fit the Book."),
    }),
    { "Nothing. Good day.", {
      bruna("It's not. But you can go."),
    } },
  }),
}

S.ud_talk_drycup = {
  ask(drycup("The Dry Cup. Eighty for a bed, and we don't do conversation. There's a sign. Someone stole the sign. I've entered it."), {
    { "A bed.", { { inn = 80 } } },
    { "Not tonight.", {} },
  }),
}

S.ud_talk_murgrum = {
  t("In a niche off the inner road a young duergar sits with ink to his elbows, copying. He's grey and broad, and he looks like a doorstep that has been crying."),
  { when = "ud_seam_open", steps = {
    murgrum("You'll want the far end of the Seam, the wall with Barris's mark. Number eleven thousand, three hundred and two: 'A gnome laughed.' I'd like to have met that gnome."),
  }, other = {
    murgrum("Number eleven thousand, two hundred and six. 'A gnome sold my grandfather a cracked bucket.' Sorry, who are you? I'm not supposed to have visitors. I'm not supposed to have anything."),
    { has = "ud_letter", steps = {
      ask(murgrum("Is that gnomish coal I can smell?"), {
        { "Sevria sent this.", {
          { take = "ud_letter" },
          t("He reads it twice, and then he holds it against his chest with both inky hands, and doesn't say anything for a while."),
          murgrum("Mother found the letters, all four years of them, in a boot. I've to copy out the whole Book of Grudges by hand, until I know what I am."),
          murgrum("Where we met, there's a wall with Barris Underbelly's mark on it. If there's anything on this world my mother would listen to, it's him."),
          murgrum("The shutter's on the south side of the Pillar Road. The watchword is 'Mine first'. Tell her I'm on eleven thousand. Tell her I've got a plan. I haven't, but tell her."),
          { set = "ud_seam_open" },
        } },
        { "Nothing. Sorry to disturb you.", {} },
      }),
    } },
  } },
}

S.ud_talk_dimsael = {
  t("Queen Dimsael Coalcinder sits in a hall of black glass with a stone table in front of her and nothing on it. She looks at you the way an anvil would."),
  { when = "side_lovers", steps = {
    dimsael("I've read all forty thousand now. Half of them are about hats. Get out, please. I'm trying to work out what to be angry about."),
  }, other = {
    { has = "ud_page", steps = {
      t("You put the sheet of copper on the empty table. The Queen doesn't touch it. She reads it from where she sits, and then she reads it again. Somewhere up the road a pen is scratching."),
      dimsael("That's his hand. I learned my letters from his war orders."),
      dimsael("Sixty-three years. Forty thousand entries. A people raised on it. He looked at us, and he decided we would rather be angry together than be anything else apart."),
      { choice = {
        { "He was right. It kept you together.", {
          dimsael("It did. That's the worst of it. I'd like to dig him up and have him tell me so."),
        } },
        { "You can stop now.", {
          dimsael("Can I? You've a very high opinion of queens."),
        } },
      } },
      dimsael("Keeper. Bring a rule and a pen."),
      tally("Which entry, ma'am?"),
      dimsael("All of them."),
      tally("Ma'am, there are forty thousand, one hundred and eighteen."),
      dimsael("Then you had better sit down."),
      { take = "ud_page" },
      dimsael("And let my son out of that niche. Surface person, I don't thank people. Take this, and go away."),
      { give = "might_ring" },
      { fade = true },
      { dark = true },
      t("Two lamps come along the Pillar Road from opposite ends, very slowly, each pretending that it hasn't seen the other."),
      murgrum("Your seam is inferior."),
      sevria("Your mother's a thief. No, wait, that's mine."),
      t("Nobody on the Pillar Road has ever heard a duergar laugh before. Several people write it down."),
      { dark = false },
      { set = "side_lovers" },
    }, other = {
      dimsael("You've come from Touarch. I can smell the coal, and the jokes. Be brief. I have a war to plan."),
      ask(dimsael("Well?"), {
        topic("War with who?", {
          dimsael("Touarch. We swore a truce at Barris Underbelly's sealed door, to last as long as the Crown stayed whole. I'm told they keep nuts in it. I consider that a breach."),
        }),
        topic("Where's your son?", {
          dimsael("Copying the Book of Grudges by hand, by my order. I found some letters. When he's finished he will know what his people are."),
        }),
        { "We want nothing from you.", {
          dimsael("That's the first sensible thing anyone's said in this hall all year."),
        } },
      }),
    } },
  } },
}

-- ---------------------------------------------------------------- the Comet Seam

S.ud_read_tin = {
  t("A hollow in the coal holds a biscuit tin, and the tin holds about two hundred letters. The top one reads:"),
  t('"My dear hateful gnome, your seam is inferior, and your mother is a thief. Same time Thursday? Yours in contempt, M."'),
  t('And under it: "Dearest stunted menace, I have counted your faults, and you are nine short of a full set. I will bring the pie. S."'),
}

S.ud_scene_grudge = {
  t("A long dry vault, with a stone bed at the far end. Between you and it stands a thing of black iron, twice the height of a duergar. Every inch of it is stamped with small, neat names."),
  owlin("Those are gnomish names. All of them. It appears to be reading them to itself."),
  deserter("A grudge you can hit. Do you know, friend, I could get to like this country."),
  { battle = "ud_boss_grudge" },
  t("It comes down in sections. The names go on for a little while after that, more and more slowly, and the last one is never finished."),
  { set = "ud_grudge_down" },
}

S.ud_talk_barris = {
  { when = "ud_barris_read", steps = {
    t("Barris Underbelly lies on the stone with his boots off, looking extremely pleased with himself."),
  }, other = {
    t("Barris Underbelly lies on the stone in his war-harness, boots off, hands folded on a single sheet of copper. He's been dead for sixty-three years, and he looks extremely pleased with himself."),
    t('"To whoever has the stomach. This is the first grudge and the last, and it\'s against me. The lads were going to melt the Crown down for war-iron, and I could not stop them. So I asked the cleverest thief I ever met to steal it."'),
    t('"She did it in one night. A people will melt a crown, but they will keep a grudge for ever, and it has held you together better than any hat. Forgive me. Do not tell Olive about the laughing. B."'),
    deserter("He had it stolen. The whole Book, forty thousand entries. He did it on purpose, and then he went off and lay down."),
    cleric("There's a second line, very small, at the bottom. 'She said she would wait.' I don't think that one was meant for anybody."),
    { give = "ud_page" },
    { set = "ud_barris_read" },
  } },
}

-- ---------------------------------------------------------------- the Underweb

S.ud_read_baskets = {
  t("Baskets hang along this strand, dozens of them, each on its own line from the city overhead. In each is a week's moss, neatly packed, and a folded blanket."),
  t("Below you, something big moves slowly from strand to strand. It's talking, in a low and very reasonable voice, to nobody."),
}

S.ud_talk_mmrk = {
  t("An ettercap crouches on the strand with its long hands full of silk, mending. It looks like somebody's bad dream about a dentist."),
  { when = "ud_lift_up", steps = {
    mmrk("Lift is up. Go. Mmrk stays. Someone has to do the baskets."),
  }, other = {
    mmrk("Click. Net-tender Mmrk, ninth shift. Lift is stuck. Mad ones chew the cables. I tell Commons, send more hands. Commons says, fill in a form. I am the form."),
    mmrk("Three winches on the web, one at each far end. Turn two, and I bring the lift. Three is better, but two is the rule."),
  } },
  ask(mmrk("You have question? Be quick. They get hungry at the bell."), {
    topic("Who are the mad ones?", {
      mmrk("The Unsettled. Quiet House tries. Sometimes it does not take. City cannot keep them, so they come down here, and I feed them. Nobody asks Mmrk to. They were citizens."),
    }),
    { "Thanks. Keep mending.", {
      mmrk("Yes. I am in the union."),
    } },
  }),
}

local LIFT_RISES = {
  { when = "ud_lift_up", other = {
    { count = { "ud_wound_a", "ud_wound_b", "ud_wound_c" }, at = 2, steps = {
      { sfx = "door" },
      t("Far above, something heavy shifts. A long shiver runs through every strand of the web at once, and a net basket the size of a barn begins to come down to the head of the strand."),
      { set = "ud_lift_up" },
    } },
  } },
}

S.ud_wind_a = {
  { when = "ud_wound_a", steps = { t("The winch is turned as far as it goes.") }, other = {
    t("You put your shoulder to the crank, and a long line of silk comes up taut out of the dark."),
    { set = "ud_wound_a" },
    LIFT_RISES[1],
  } },
}

S.ud_wind_b = {
  { when = "ud_wound_b", steps = { t("The winch is turned as far as it goes.") }, other = {
    t("You put your shoulder to the crank. Something has been chewing the rope. It holds."),
    { set = "ud_wound_b" },
    LIFT_RISES[1],
  } },
}

S.ud_wind_c = {
  { when = "ud_wound_c", steps = { t("The winch is turned as far as it goes.") }, other = {
    t("The crank turns easily, as if someone has been greasing it. A small basket of moss swings past on the line."),
    { set = "ud_wound_c" },
    LIFT_RISES[1],
  } },
}

-- ---------------------------------------------------------------- Strathe

S.ud_scene_strathe = {
  t("You come up through the floor of the city in a net, like a catch. Strathe hangs over a drop with no bottom, roped to its pillar by one web as wide as the sky. Whole streets tilt a little. Nobody seems to mind."),
  t("A drider comes down the road on eight plated legs, very fast. He has a drawn blade, a ledger, a small spoon on a cord around his neck, and the look of a man who hasn't slept since he was born."),
  ruaryn("Stop there. Arms out. Ruaryn Lhalith, brother to the Queen. Nobody goes near her with anything sharper than a compliment. What's in the bag? Why does that one have a beak?"),
  owlin("I assure you that I..."),
  ruaryn("It talks. Noted. It's a fine beak, and it will have to be declared."),
  { set = "ud_strathe_in" },
  ask(ruaryn("I've stopped eleven assassins in thirty years. The twelfth is in the city now. I can feel it in my knees, and I've got eight of them. What's your business?"), {
    topic("What's the spoon for?", {
      ruaryn("I taste everything she eats. Every meal, for thirty years. She says it's unnecessary. She's also alive. You'll notice that those two facts don't argue."),
    }),
    { "We need the Web Road to the salt.", {
      ruaryn("Only the Queen can give you that. She's in the hall, to the north. I'll be behind you. You won't hear me. That's rather the point."),
    } },
    { "Just passing through.", {
      ruaryn("Nobody passes through a city on a web. They're held up, or they fall. The hall's to the north."),
    } },
  }),
}

local HALRYNA_ASKS = {
  halryna("Seven of my people got out of their beds last week, walked to the east rail, and stood there. They didn't answer to their names. By morning they'd gone back to bed, and they remembered nothing."),
  halryna("Mother Nulliira runs the Quiet House, where we are settled. She says it's nothing. You have a doctor and a sister with you, and strangers see things. Go and look, and tell me what I already know. I'll be there myself. I always go on the last night of the month."),
  { set = "ud_audience" },
}

S.ud_talk_halryna = {
  { when = "ud_jezzara_in", steps = {
    halryna("I'm still breathing. It's what I'm for. The Web Road is open, at the west end of the low street."),
  }, other = {
    { when = "ud_audience", steps = {
      halryna("The Quiet House is at the east end of the avenue. Mother Nulliira will let you in. I'll be going there myself soon. I always do, on the last night of the month."),
    }, other = {
      t("The Queen of Strathe is larger than you expected, and sadder: a drow woman in plain grey from the waist up, and from the waist down a spider the size of a coach, folded carefully so as not to damage the furniture."),
      halryna("You'll forgive my brother. He has frisked the ambassador of Touarch twice this year, and she's three feet tall. I'm Halryna. We don't use titles much."),
      ask(halryna("You've come for the Web Road, and you'll have it. But first I'd like to ask a favour. Not a price, you understand. We don't do prices."), {
        topic("What's Vierrela to Strathe?", {
          halryna("Everything. We were mad, you know, all of us, for longer than your kingdoms have stood. Then a girl our emperor had sold came back and made us well. She asked for nothing. We live in her grace."),
          halryna("I've thought about that phrase more than you would believe."),
        }),
        { "What do you need?", HALRYNA_ASKS },
      }),
    } },
  } },
}

S.ud_talk_ruaryn = {
  ruaryn("The cat-woman's been seen on the south rail. If you see her, don't look directly at her. Look a yard to the right."),
}

S.ud_talk_nulliira = {
  { when = "ud_jezzara_in", steps = {
    nulliira("I've settled forty thousand children. You didn't see what we were before. I'd do it again. Go away, please. They're all still sleeping."),
  }, other = {
    { when = "ud_audience", steps = {
      ask(nulliira("The Queen has asked, so the door's open. Walk softly. Don't wake anyone. I can't stress that enough. Don't wake anyone."), {
        topic("What is settling?", {
          nulliira("Every child of Strathe comes to us at the first moult. A drop in the ear, a night's sleep, and they never know the madness. It's very safe. Forty-one years without a failure, if you don't count the Underweb."),
        }),
        { "We'll be careful.", {} },
      }),
    }, other = {
      nulliira("The Quiet House is closed to visitors. Nothing is wrong. It's a very quiet house."),
    } },
  } },
}

S.ud_quiet_shut = {
  nulliira("No. Not without the Queen's word. I don't care who you are, or how far you've walked. People are resting."),
}

S.ud_road_shut = {
  t("The Web Road runs out from the end of the street, one grey strand as wide as a cart. Two armed citizens sit across it, playing a game with small bones. Nobody walks the Road without the Queen's word. They're sorry. It was voted on."),
}

S.ud_talk_commons = {
  ask(commons("This is the Commons. Take what you need, write down what you took, and put in what you can. Coins? We've had coins before. They're very good for weighing down nets."), {
    { "Show me.", { { shop = "ud_commons" } } },
    { "Not just now.", {} },
  }),
}

S.ud_talk_houndrin = {
  ask(houndrin("Houndrin Dilagon, master of the Hunt. There's a lovely smell coming off you. Sun. I've been up top twice. I took a stag, a Clinic surveyor, and something called a goose. The goose fought hardest."),{
    { "Show me your gear.", { { shop = "ud_houndrin" } } },
    topic("Do you eat people?", {
      houndrin("Not anyone who's introduced themselves. It keeps me honest. What did you say your name was?"),
    }),
    { "Not just now.", {} },
  }),
}

S.ud_talk_sael = {
  { when = "ud_jezzara_in", steps = {
    sael("Nobody will tell me why Uncle's spoon is on the table. Lunch keeps going to look for him. I told Lunch he's busy."),
  }, other = {
    sael("This is Lunch. He's a hatchling. I got to keep him from the harvest because I cried. You can stroke him, but don't get attached. I mean he gets attached. With his mouth."),
    ask(sael("Do you want to hold him?"), {
      topic("Why is he called Lunch?", {
        sael("That's what the harvest-warden wrote on his tag. I said he could keep it, if he promised not to be."),
      }),
      { "He's very handsome.", {
        sael("I know. He's looking at you with all eight eyes. That means he likes you, or he's hungry. It's the same face."),
      } },
    }),
  } },
}

S.ud_talk_iliss = {
  ask(iliss("A bed? Sit, sit. Why would you pay for a bed? In forty years I've never known a soul in Strathe to wake up shouting."),{
    { "We'd like to rest.", {
      { heal = true },
      t("The hammock takes you up like a hand. Nothing happens for several hours, which for you is usual."),
    } },
    { "Not now, thanks.", {} },
  }),
}

-- ---------------------------------------------------------------- the Quiet House

S.ud_talk_sleeper = {
  t("A drider sleeps in a silk cradle, legs folded and hands open. Her breathing is slow and even. So is the next one's. So is everyone's."),
  t("After a while you realise that it's one breath, and that the whole room is taking it together."),
}

S.ud_talk_attendant = {
  attendant("No. Cradle is for Queen. Mother says nobody. Nobody argues with Mother."),
}

S.ud_read_records = {
  t("Shelves of settling-books, forty-one years of them, in one small, clear hand. Every child has a line: name, moult, one drop, left ear, slept well."),
  t("The first entry in the first book is different. HALRYNA LHALITH, ADULT. ONE DROP, BY THE HAND OF V. Beside it there's a note: Keystone. All others to be tuned to this one. She is not to be lost."),
  owlin("Tuned? One doesn't tune a medicine."),
  { set = "ud_read_keystone" },
}

S.ud_scene_jars = {
  t("A cold room, lined with drawers of glass phials packed in salt. Each holds a single clear drop. The doctor holds one to the lamp. The drop turns over, and looks back."),
  deserter("No. Friend, step away from the shelf. That's the thing in Scythebreak, the thing in the mine. It's a tadpole, no longer than an eyelash, and they've been putting it in their children's ears."),
  cleric("But they aren't sick. Forty-one years, and not one of them has turned."),
  owlin("Because it's asleep. It stays asleep, and it holds the mind still, the way a stone holds down a paper. That isn't a cure. It's a tenant."),
  deserter("Then what does it live on, if it never wakes?"),
  t("Nobody answers. The sister looks at you for a moment, and then at the floor, and you can't think why."),
  ask(deserter("I want a word with this Mother Nulliira, and I want it now."), {
    topic("Can you take them out?", {
      deserter("From a hundred thousand people? If I knew how, friend, I'd have stopped Scythebreak with a pair of tweezers. No."),
    }),
    topic("What would wake it?", {
      { when = "ud_read_keystone", steps = {
        owlin("A voice, I should think. The first book says they're all tuned to one keystone. While she lives, they sleep. If she died, they'd have nobody left to listen to but the one who put them there."),
      }, other = {
        owlin("A voice, I should think. I'd very much like to read the first page of those settling-books across the corridor."),
      } },
    }),
    { "Where's the Queen?", {
      t("Down the corridor a small bell starts to ring, and stops, as if someone has put a hand on it."),
      deserter("The last night of the month, she said. She comes here alone, so as not to wake the ward. Friend, if I were the twelfth assassin, that's where I'd be standing."),
    } },
  }),
  { set = "ud_quiet_seen" },
  deserter("The antechamber's at the far end. Go. Go!"),
}

S.ud_talk_cradle = {
  t("The Queen lies quite still in the great silk cradle. Whatever is standing on the rim of it isn't quite where you're looking."),
}

S.ud_scene_cradle = {
  { when = "ud_cradle_talked", other = {
    t("The Queen lies in a great silk cradle with her eyes shut. Standing on the rim of it, as easily as on a pavement, is Jezzara Deth. Or a yard to the left of that. Her knife is very small and very clean, and it's resting under the Queen's ear."),
    jezzara("You're early. I had this timed to the breath. Her brother's asleep on the front steps. I left him a note."),
    ask(jezzara("Go on, then. Tell me why I shouldn't. People usually have something, and I do like to hear it."), {
      topic("Who's paying you?", {
        jezzara("Vierrela. The drow begged her for their throne back, and paid up front. She always delivers. One queen for one chair. I've done worse before breakfast."),
      }),
      { "Kill her, and the whole city wakes.", {} },
      { "Look at what they've got in the drawers.", {} },
    }),
    t("The doctor sets a glass phial on the rim of the cradle. The scholar, who can't pass a shelf, lays the first settling-book beside it, open at the first page. Jezzara doesn't move. Her eyes do."),
    owlin("Every drider in Strathe carries one, all tuned to this woman. While she lives they sleep. Kill her, and a hundred thousand of them wake on one breath, with nobody left to hear but the one who put them there."),
    deserter("It was never about a throne. You were sent to open a door on an army."),
    halryna("Forty-one years. I wondered who would say it first."),
    t("The Queen hasn't opened her eyes."),
    jezzara("You knew."),
    halryna("Every queen knows what she's for. I've been trying not to sneeze for four decades. You've lovely balance, by the way. I could hear you not falling."),
    cleric("You never told them. All those children. Why would you never tell them?"),
    halryna("Would you want to be told? They sleep so well. And a thing like that lies quieter when nobody goes looking for it."),
    jezzara("I've killed kings. I killed a bishop on his birthday. I don't do cities."),
    t("The knife isn't there any more. You didn't see it go."),
    jezzara("Vierrela told me it was a chair."),
    t("The door opens. Ruaryn Lhalith comes in with the spoon swinging at his neck, and stops. He's looking at all of you and at none of you. He's standing very straight, like somebody else's idea of him."),
    borrowed("Jezzara. That was twelve good years, and you've spoiled them by reading. I did wonder who it would be."),
    halryna("Ruaryn? Ruaryn, look at me."),
    borrowed("He can't, dear. I've only borrowed him. One is enough to make the point."),
    borrowed("{hero}. How nice. Do come and see me, all of you. I've kept a chair. But I would like to know what the new knife is worth."),
    jezzara("The attendants have turned. I'll take the door. You hold him. Try not to kill him. I'll understand if you do."),
    { big = "RUARYN WAKES" },
    { set = "ud_cradle_talked" },
  } },
  { battle = "ud_boss_ruaryn" },
  t("He comes down all at once, with his legs folding the wrong way. For a moment his eyes are his own, and they go straight to his sister's hands, to see whether she's eaten."),
  ruaryn("Did you... have you had anything... let me just..."),
  t("The sister gets there first. She ties the thread herself. The spoon slides off its cord, rolls a little way across the white floor, and stops."),
  halryna("He tasted everything I ate for thirty years. I can smell poison, you know. I always could. I never told him. He was so pleased to have something to do."),
  t("Jezzara comes back from the door, wiping nothing off a very clean knife."),
  ask(jezzara("That's the attendants seen to. So I've a knife and no employer. You'll be going to see her. Of course you will. You've been told to."), {
    { "Come with us.", {
      jezzara("I wasn't asking, but it's nice that you said so. The first one's free. After that, we'll discuss the second."),
    } },
    { "Why should we trust you?", {
      jezzara("You shouldn't. I'm never where you think I am. But she told me you were spoken for, and I've decided I'd like to find out by whom."),
    } },
  }),
  { join = "jezzara", lvl = 26 },
  { big = "JEZZARA DETH JOINS" },
  halryna("Take the Web Road. It's yours. I'll stay and keep breathing. It seems that's the job."),
  jezzara("Keep at it, your majesty. I'd be insulted if anyone else did it."),
  { set = "ud_jezzara_in" },
}

-- ---------------------------------------------------------------- the Salt Stair

S.ud_scene_rain = {
  t("The Web Road lets you out onto a shelf of wet rock, and the world turns to rain. Billions of stalactites hang from a roof you can't see, each one dripping the Guldan Ocean on you, a drop at a time."),
  t("Far below lies the Pale Depths, a sea the colour of old milk. Long grey shapes are flying over it, very low."),
  jezzara("See that green bubble, a long way out? That's Crysathula. Everyone's dry in there. It's the first thing she takes from you. She makes you glad to be indoors."),
}

S.ud_read_marker = {
  t("A waymarker stands in a niche, gith-made, cut in three languages. Under them someone has added a line in fresh paint, and it hasn't had time to run."),
  t("YOU ARE EXPECTED."),
  jezzara("That wasn't there last month. I'd take it as a compliment. I wouldn't take it as anything else."),
}

S.ud_talk_saltgate = {
  t("An iron gate blocks the stair, crusted white with salt and barred on the far side. The bars are too close to get an arm through."),
  ask(jezzara("Well? I'd like it noted that I'm not being paid for this."), {
    { "Go on, then.", {
      t("Jezzara walks up to the bars and doesn't stop. The part of her you were looking at was never there. A moment later you hear the bar lift, on the far side."),
      jezzara("That's all it is. All I've ever needed is something that thinks it knows where I am."),
      { set = "ud_gate_open" },
    } },
    topic("How do you do that?", {
      jezzara("I don't. It's done to me. I've never once seen where I'm standing."),
    }),
    { "Let's look round first.", {} },
  }),
}

S.ud_talk_ibbit = {
  t("A sky ship lies on the ledge with her back broken. On the hull sits a small round person in a brass helmet, fishing, with no line."),
  { when = "ud_ibbit_gave", steps = {
    ibbit("Still no fish. Head office will be very cross."),
  }, other = {
    ibbit("Is this Ecklund's World? No? I've got you down here as a spice market. Factor Ibbit, Astral Haulage. Twelve years without a scratch, not counting this."),
    ask(ibbit("I'm going out of business, you see. Everything must go."),{
      { "What have you got?", {
        ibbit("Crate of something. It says FRAGILE in nine languages, and in one of them it may say HUNGRY. It's yours."),
        { give = "hiether", n = 3 },
        { give = "xpotion", n = 2 },
        { set = "ud_ibbit_gave" },
      } },
      { "Good luck with the fish.", {} },
    }),
  } },
}

S.ud_scene_mother = {
  t("Halfway along the bridge, for the first time since you came down, the rain stops making any sound."),
  t("The water on the left stands up. It's a ring of teeth as wide as a mill wheel, and inside it another ring, and another. Something long and pale lays its weight across the stone."),
  jezzara("That's new. I'd have remembered that."),
  { battle = "ud_boss_mother" },
  t("It slides away off the rock, ring after ring. The rain starts up again, as if nothing had happened, which down here is true of nearly everything."),
  { set = "ud_bridge_won" },
}

-- ---------------------------------------------------------------- Crysathula

S.ud_scene_crysathula = {
  t("You pass through the green skin of the bubble with a faint, reluctant kiss. The rain stops. Crysathula lies ahead, clean and dry and curved, as if grown by something that had once been told about cities."),
  t("Ships hang at the towers overhead, nautiloids and hulls from nowhere at all. Things with more elbows than they need are buying and selling, very quietly."),
  zhar("Arrival registered. You are expected. Hold still. State your plane of origin. Yes, I know. It's a form."),
  { set = "ud_crys_in" },
  zhar("The Hive Queen will see you when you're ready. She knows when that is. The Cortex Nest is at the west end. The door isn't locked. No door here is locked. You'll find you don't want to try them."),
}

S.ud_talk_zhar = {
  ask(zhar("Clerk Zhar, arrivals and departures. If you'd like to go back, there's the stair, or for two hundred there's the Touarch skiff."), {
    { "Nothing, thank you.", {} },
    { "Book the skiff to Touarch.", {
      { paid = 200, steps = {
        t("The skiff goes up through the bubble and down the dark like a thrown knife."),
        { warp = { "ud_touarch", 4, 2, 2 } },
      }, other = {
        zhar("Two hundred gold. It's a form."),
      } },
    } },
  }),
}

S.ud_talk_sult = {
  t("A tall figure in a plum-coloured robe is looking at the sister's head. It sees you notice, and looks away, embarrassed."),
  sult("I do apologise. One's eyes wander. I've not eaten anyone in twenty-two years. We have a committee."),
  ask(sult("Since the Queen took out the mother brain's, ah, opinions, we've all felt so much calmer. One used to know exactly what one wanted. Now I've taken up pottery."), {
    topic("Do you miss it?", {
      sult("I miss being sure. There used to be a voice that told you it was all right. Now there's only Her, and she says nothing. One simply does things, and later one finds they were what she wanted."),
    }),
    topic("Who built this place?", {
      sult("It was the hive of Zalabarula the Brain Sipper. He went down to the Vault to learn to rule without a mother brain, and he never came back. We came looking for him, and it seemed a shame to leave."),
    }),
    { "Enjoy the pottery.", {
      sult("Would you like a bowl? It doesn't hold anything. None of them do."),
    } },
  }),
}

S.ud_talk_sweeper = {
  t("A thin man in a grey shift is sweeping the dry street in very even strokes. There's nothing on it to sweep."),
  sweeper("Good evening. I came from Eighstead, in a crate. Lord Sindal's people are very careful with the paperwork. I think I had a wife. Would you like me to sweep something?"),
  ask({ text = "He's smiling. It doesn't appear to be doing anything else." }, {
    { "Leave him be.", {
      t("He goes on sweeping. The sister ties a black thread round the broom handle, and he doesn't notice."),
    } },
    topic("Do you want to leave here?", {
      sweeper("Leave? I'm sorry, I don't know that one. Is it a kind of floor?"),
    }),
  }),
}

S.ud_talk_uln = {
  t("The shop is all shelves, and they go up further than the ceiling does. Behind the counter crouches a grey, stooped thing with one huge wet eye. It's been reading you since before you came in."),
  uln("Come in, come in. Uln sees that the doctor has an old letter they've never burned, and the cat still owes a bishop's family an apology. No charge. It slips out."),
  ask(uln("Uln came up from the Vault with a sackful of goods and a bad conscience. What will it be?"), {
    { "Show me your wares.", { { shop = "ud_uln" } } },
    topic("What's the Vault like?", {
      uln("A library that's eaten its readers. It hangs, all of it, on chains over a fog, and a worm in the chains reads you on the way down. Uln left. Uln recommends it."),
    }),
    topic("What do you see in me?", {
      t("The great eye comes round to you, and stops. For the first time, the shop is quiet."),
      uln("Uln sees... no. No, Uln thinks he won't say. Ten percent off. No, twenty. Please take your time. And stand over there. And don't lean on anything."),
    }),
    { "Not today.", {} },
  }),
}

S.ud_talk_pod = {
  ask(pod("Rest cells, a hundred a night. They're very good cells. You will have no dreams at all. I don't mean you in particular. I mean everyone."), {
    { "A cell, please.", { { inn = 100 } } },
    { "Not tonight.", {} },
  }),
}

S.ud_talk_vel = {
  ask(vel("Research wing. You'd be the doctor, the Clinic one. We've read your papers. It's nice to meet someone who has been wrong so carefully."), {
    topic("Has anyone else been in here?", {
      vel("I'm not to say. She left the bench very clean, and she corrected my notes. She was right."),
    }),
    { "We'll be going.", {} },
  }),
}

S.ud_stair_shut = {
  t("A low arch at the end of the bay opens on old, dry steps going down. Two gith stand in it, doing nothing, with enormous skill."),
  t("One of them says, without looking round, that this is the Brain Sipper's stair, and that it's not without her leave. She's in the hall behind you. He wouldn't keep her waiting."),
}

-- ---------------------------------------------------------------- the Cortex Nest

S.ud_scene_nest = {
  t("The Cortex Nest is a long pale hall, full of a slow sound like sleep. Behind one wall of green glass lies a thing the size of Orrenshire, grey and folded, with a single clean scar. It isn't dead. It has simply stopped having views."),
  t("A drow woman in a plain dark robe sits in a plain chair in front of it. Facing her are some empty chairs. Then you notice that there are exactly five."),
  vierrela("Sit down, {hero}. You've come such a long way, and you've done it so well. Doctor. Sister. Scholar, I'm sorry about Evrastin. I mean that, though not in any way you'd like."),
  vierrela("Jezzara. You kept your knife. Do go on keeping it. I find people who resign are so much more useful than people who are dismissed."),
  jezzara("Say one more thing to me, and we'll see which of us is sitting where you think."),
  ask(vierrela("You have questions. Ask them out loud, please. You think so very loudly, and it's been a long day."), {
    topic("You brought the Blightmare into the world.", {
      vierrela("I fetched something from the Far Realm, in a jar, on a scroll I bought from some very disappointed people. It was no larger than your eyelash. It caught on rather."),
      vierrela("You think I did it for power. My father sold me to pay for a bad harvest, dear. I did it because I'd found something that didn't care what I was worth."),
    }),
    topic("What's at the Nightmare Vault?", {
      vierrela("A very old library with its best pages torn out. A general went there once, and came home with more than he'd borrowed. Everyone who matters ends up there sooner or later."),
    }),
    topic("Let Strathe go.", {
      vierrela("I could wake them tonight. I could have done it on any night in forty-one years. It's so restful, having something you haven't done yet."),
    }),
    topic("What am I?", {
      t("She looks at you for the first time. She looks at you the way the sister looks at a fever: with interest, and patience, and a certain tenderness."),
      vierrela("I've known what you are since you were a bundle in a crate, on the last cart out of Evrastin. I have had your porridge watched."),
      vierrela("You have never dreamed. You think of that as something you lack. I would think of it as something you're owed. No, that's enough. You'd only try to do something about it, and you aren't ready to fail yet."),
      t("The sister's hand has closed on her black thread. She doesn't seem to know."),
    }),
    { "Why are you letting us live?", {
      vierrela("Because I've nothing to do. You're walking exactly where I'd send you, at about the speed I'd like. It would be such bad manners to interrupt."),
    } },
  }),
  t("Bare feet slap in the corridor. Clerk Zhar comes in without bowing, the first person you've seen hurry in this city, holding a slip of wet paper."),
  zhar("From the Adaphis packet, Queen. King Fabian Blud is dead. The Clinic gives the cause as a long illness."),
  vierrela("How long?"),
  zhar("About four minutes. Doctor Colette Oshlyn has taken the throne of Plexios. She appears also to have left it. The Clinic doesn't know where she's gone."),
  vierrela("I do. She sat in that chair nine days ago. I gave her tea, and a ship, and the way down."),
  deserter("No. She'd never leave Adaphis, not with the throne still warm. She's got the Tome with her, hasn't she?"),
  vierrela("She has her Tome, and one very old question, and she's gone to put it to someone. She believes she's using me. It's done her so much good."),
  t("She holds out a folded paper, sealed in Clinic red. She didn't take it from anywhere."),
  vierrela("She left this for you. I haven't read it. I didn't need to."),
  t('"{hero}. Turn back. There is a bed made up for you in Adaphis, and nobody left to tell me not to. Don\'t come down after me. I would so hate to have to treat you in the field. C."'),
  { choice = {
    { "We're going after her.", {
      vierrela("Yes. I know."),
    } },
    { "Hand the letter to the doctor.", {
      deserter("That's her writing. Friend, she meant every word. She's never once told a patient a lie. That's what's so terrible about her."),
    } },
  } },
  vierrela("The way down is the Brain Sipper's old stair, off the east bay of this hall. No one will stop you. Nothing that goes down it has ever needed stopping."),
  { big = "COLETTE HAS GONE DOWN" },
  vierrela("Goodbye, {hero}. Sleep well."),
  t("She turns her chair back to the glass. Behind it, something enormous doesn't stir."),
  { set = "ud_done" },
}

-- ---------------------------------------------------------------- shops

R.shops.ud_dangle = { tier = 4 }
R.shops.ud_hask = { tier = 5 }
R.shops.ud_forge = { tier = 5, extra = { { item = "cantor_ring", price = 700 }, { item = "swift_band", price = 900 } } }
R.shops.ud_commons = { tier = 5, extra = { { item = "clear_eye", price = 700 } } }
R.shops.ud_houndrin = { tier = 5, extra = { { item = "drow_sabre", price = 1800 }, { item = "drow_plate", price = 1450 } } }
R.shops.ud_uln = { tier = 5, extra = { { item = "life_ring", price = 2200 }, { item = "mind_ward", price = 2600 }, { item = "raven_charm", price = 2000 } } }

-- ---------------------------------------------------------------- where the story goes

local OPEN = "em_done"

R.goals = {
  { done = "ud_relieved", text = "Get down the Horned Stair", map = "ud_abyss_2", x = 14, y = 11, when = OPEN },
  { done = "ud_web_down", text = "Bring down the web curtain", map = "ud_abyss_3", x = 13, y = 13, when = OPEN },
  { done = "ud_matron_down", text = "Reach the foot of the Abyss", map = "ud_abyss_4", x = 17, y = 9, when = OPEN },
  { done = "ud_lit", text = "Follow the Light", map = "ud_abyss_4", x = 20, y = 11, when = OPEN },
  { done = "ud_met_olive", text = "See the queen of Touarch", map = "ud_touarch", x = 7, y = 16, when = OPEN },
  { done = "ud_lift_up", text = "Raise the Underweb lift", map = "ud_underweb", x = 14, y = 4, when = OPEN },
  { done = "ud_strathe_in", text = "Go up into Strathe", map = "ud_strathe", x = 14, y = 17, when = OPEN },
  { done = "ud_audience", text = "See Queen Halryna", map = "ud_strathe", x = 14, y = 4, when = OPEN },
  { done = "ud_quiet_seen", text = "Search the Quiet House", map = "ud_quiet", x = 13, y = 8, when = OPEN },
  { done = "ud_jezzara_in", text = "Get to the Queen", map = "ud_quiet", x = 20, y = 12, when = OPEN },
  { done = "ud_gate_open", text = "Take the Web Road west", map = "ud_stair", x = 27, y = 6, when = OPEN },
  { done = "ud_bridge_won", text = "Cross the long bridge", map = "ud_stair", x = 14, y = 17, when = OPEN },
  { done = "ud_crys_in", text = "Enter Crysathula", map = "ud_crysathula", x = 25, y = 8, when = OPEN },
  { done = "ud_done", text = "Go to the Cortex Nest", map = "ud_nest", x = 11, y = 8, when = OPEN },
}

return R
