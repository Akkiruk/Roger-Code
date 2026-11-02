-- games/blightmare/regions/vault.lua
-- The Nightmare Vault, the turn of the game. The party follows Colette's column along the chains, gaining on it floor by floor
-- (19 hours, 11, 4, 2, 20 minutes, then a gap of three squares), and every thing they do to stop her has already stopped
-- mattering. Plain data and local helpers. Draft for the author: Colette's scene is hers to rewrite.

local say = require("games.blightmare.say")

local t, ask, topic, line, person = say.t, say.ask, say.topic, say.line, say.person

local R = {
  id = "vault", prefix = "vt_",
  entry = {
    flags = { "ud_done" }, join = { "deserter", "cleric", "owlin", "jezzara" }, lvl = 30,
    map = "vt_vault_1", x = 3, y = 3, script = "vt_arrive",
  },
  exit = "ruined",
  sites = {},
  maps = {}, scripts = {}, shops = {}, goals = {},
  foes = {}, abilities = {}, encounters = {}, field = {},
  looks = {}, names = {}, art = {},
}

local S = R.scripts

local deserter = line("deserter")
local cleric = line("cleric")
local owlin = line("owlin")
local jezzara = line("jezzara")
local colette = line("colette")
local changed = line("colette_changed")
local father = line("father")
local clerk = person("captain", "CLINIC CLERK")
local orderly = person("doctor", "ORDERLY")
local margin = person("vt_margin", "MARGIN")
local matron = person("vt_matron", "MATRON")

-- ---------------------------------------------------------------- looks and pictures

R.looks.vt_margin = {
  kind = "nothic", tall = 0.62, build = "hunched", lean = 0.18, cut = "robe", coat = "tie", trim = "line", skin = "line",
  mouth = "teeth", nose = "none", bigeye = true, carry = "ledger", back = "bg",
}
R.looks.vt_margin_2 = { like = "vt_margin" }
R.looks.vt_matron = {
  kind = "human", tall = 0.97, build = "thin", cut = "dress", coat = "line", trim = "text", skin = "text", hat = "veil", hatInk = "text",
  hatTrim = "line", wear = { "apron", "badge" }, apronInk = "text", carry = "bell", eyes = "narrow", mouth = "line", back = "redTint",
}
R.names = { MARGIN = "vt_margin", MATRON = "vt_matron" }

R.art = {
  vt_moth = "A pale moth as wide as a door, its wings dusted grey, with a lit lantern-coloured spot on each.",
  vt_grub = "A fat segmented grub the colour of rust, gripping a length of chain, one small wet eye at the front.",
  vt_nothic = "A hunched grey hairless thing the size of a child, long clever hands, one huge wet eye filling most of its face.",
  vt_reader = "A Clinic orderly walking very straight, a clean bandage over his eyes, lips moving, one hand held out as if following a line.",
  vt_pages = "A swarm of torn book pages flying like a shoal, their edges bright, with no one inside them.",
  vt_bookworm = "A vast worm made half of flesh and half of chain, coiled link over link, its front one bloodshot nothic eye. Huge.",
  vt_matron = "A tall thin woman in a starched cap and grey apron, holding a small brass handbell, entirely unhurried.",
  vt_qarhuul = "One arm of a beast too big to see, rising out of grey mist, thick as a street, ringed with eyes that are not looking at you. Huge.",
  vt_sign = "A Clinic notice on a post, very neat, wired up with a little lamp.",
  vt_ashes = "A drum fire, raked out, among tidy squares in the dust where bedrolls were.",
  vt_window = "A gap in a lantern wall with a great chain going past it, up and down.",
  vt_gap = "Broken boards ending in the air, chain ends hanging.",
  vt_brake = "A brake bar as long as a person, pinned through a toothed wheel.",
  vt_hoist = "A heavy cargo cage on a chain, with a Clinic lamp on top.",
  vt_stitcher = "A handsome dead vampire soldier in red and black, lying across a heap of fallen books.",
  vt_kettle = "A big soup kettle on a spirit lamp, one clean bowl set out beside it.",
  vt_wheel = "A red iron stopcock wheel on a pipe as thick as an arm, clamped to a chain link.",
  vt_gate = "A portcullis of hanging chain across a doorway, with the red line running under it.",
  vt_lectern = "A reading stand with a chained book or letter on it.",
  vt_drawer = "A tall card catalogue with one small drawer pulled open.",
  vt_robe = "A brick carrel, one course knocked out, an empty mind flayer's robe sitting in a chair inside.",
  vt_cradle = "A cargo cradle hanging in its rails.",
  vt_desk = "A small desk on an island of boards, one lamp on it, and an old book lying open, whole.",
}

-- ---------------------------------------------------------------- foes

R.abilities = {
  vt_lampdust = { name = "LAMP DUST", power = 60, status = "blind", chance = 50 },
  vt_rust = { name = "RUST SPIT", power = 70, status = "poison", chance = 60 },
  vt_gaze = { name = "ROTTING GAZE", mp = 4, power = 80, magic = true, element = "mind" },
  vt_aloud = { name = "READ ALOUD", mp = 5, power = 30, magic = true, element = "mind", status = "nightmare", chance = 50 },
  vt_sentence = { name = "THE SENTENCE", mp = 6, magic = true, status = "doom", chance = 40 },
  vt_papercut = { name = "PAPER CUT", power = 60 },
  vt_thrash = { name = "THRASH", power = 115 },
  vt_eye = { name = "BLOODSHOT EYE", mp = 5, power = 60, magic = true, element = "mind", status = "blind", chance = 50 },
  vt_brood = { name = "SHAKES THE CHAIN", target = "summon" },
  vt_cinch = { name = "CHAIN CINCH", power = 190, magic = true, target = "all", windup = 34, warn = "THE CHAINS DRAW TIGHT" },
  vt_cuffs = { name = "A FIRM HAND", power = 110 },
  vt_sedate = { name = "SEDATIVE", mp = 5, power = 40, status = "sleep", chance = 55 },
  vt_ring = { name = "VISITING HOURS", power = 170, magic = true, target = "all", windup = 34, warn = "SHE LIFTS THE LITTLE BELL" },
  vt_colours = { name = "COLOURS", power = 180, magic = true, target = "all", element = "mind", status = "nightmare", chance = 80 },
  vt_teeth = { name = "ALL YOUR TEETH", power = 260 },
  vt_falling = { name = "FALLING", power = 420, magic = true, target = "all", windup = 20, warn = "THE ROAD IS NOT THERE" },
}

R.foes = {
  vt_moth = { name = "VAULT MOTH", tier = 30, shape = "quick", sprite = "vt_moth", family = "bug",
    abilities = { { "bite", 3 }, { "vt_lampdust", 2 } }, weak = { "fire" } },
  vt_grub = { name = "CHAIN GRUB", tier = 30, shape = "small", sprite = "vt_grub", family = "bug",
    abilities = { { "gnaw", 3 }, { "vt_rust", 1 } }, weak = { "ice" } },
  vt_nothic = { name = "NOTHIC", tier = 31, shape = "caster", sprite = "vt_nothic", family = "stalker",
    abilities = { { "vt_gaze", 3 }, { "claw", 2 }, { "vt_aloud", 2 } }, weak = { "holy" }, resist = { "mind" } },
  vt_rearguard = { name = "REARGUARD", tier = 31, shape = "brute", sprite = "orderly", family = "staff",
    abilities = { { "baton", 4 }, { "needle", 2 } } },
  vt_surgeon = { name = "FIELD SURGEON", short = "SURGEON", tier = 31, shape = "healer", sprite = "doctor", family = "staff",
    abilities = { { "baton", 2 }, { "field_surgery", 2 }, { "draught", 1 } } },
  vt_reader = { name = "BLIND READER", short = "READER", tier = 32, shape = "tank", sprite = "vt_reader", family = "blighted",
    abilities = { { "claw", 3 }, { "vt_sentence", 1 } }, immune = { "blind" }, weak = { "holy" } },
  vt_pages = { name = "LOOSE PAGES", short = "PAGES", tier = 32, shape = "small", sprite = "vt_pages", family = "bug",
    abilities = { { "vt_papercut", 3 }, { "hush_word", 1 } }, weak = { "fire" } },

  vt_bookworm = {
    name = "THE BOOKWORM", short = "BOOKWORM", tier = 31, shape = "brute", sprite = "vt_bookworm", family = "boss", size = 3, weak = { "fire" },
    boss = { hpx = 1.1, phases = {
      { at = 100, moves = { { "vt_thrash", 5 }, { "vt_eye", 2 } }, every = 5, big = "vt_cinch" },
      { at = 66, moves = { { "vt_thrash", 5 }, { "vt_eye", 3 } }, every = 4, big = "vt_cinch", say = "IT TAKES UP THE SLACK", speedUp = 1, summon = "vt_grub", call = "vt_brood" },
      { at = 33, moves = { { "vt_thrash", 6 }, { "vt_eye", 2 } }, every = 3, big = "vt_cinch", say = "THE WHOLE ROAD SWINGS", speedUp = 1 },
    } },
  },
  vt_matron = {
    name = "THE MATRON", short = "MATRON", tier = 32, shape = "caster", sprite = "vt_matron", family = "staff",
    boss = { hpx = 1, phases = {
      { at = 100, moves = { { "vt_cuffs", 5 }, { "vt_sedate", 2 }, { "draught", 2 } }, every = 5, big = "vt_ring" },
      { at = 66, moves = { { "vt_cuffs", 5 }, { "vt_sedate", 3 }, { "bind_word", 2 } }, every = 4, big = "vt_ring", say = "LIGHTS OUT ON THE WARD", summon = "vt_surgeon" },
      { at = 33, moves = { { "vt_cuffs", 6 }, { "bind_word", 2 } }, every = 3, big = "vt_ring", say = "SHE ROLLS UP HER SLEEVES", speedUp = 1 },
    } },
  },
  -- The fight that can't be won: it has the HP of a small moon, and three of its turns end it.
  vt_qarhuul = {
    name = "QARHUUL", tier = 45, shape = "brute", sprite = "vt_qarhuul", family = "boss", size = 3, xpx = 0, goldx = 0, steal = false,
    immune = { "poison" },
    boss = { hpx = 9, phases = {
      { at = 100, moves = { { "vt_teeth", 3 }, { "vt_colours", 2 } }, every = 3, big = "vt_falling" },
    } },
  },
}

R.encounters = {
  vt_e_moths = { foes = { "vt_moth", "vt_moth" }, flee = true, bg = "chain" },
  vt_e_grubs = { foes = { "vt_grub", "vt_grub", "vt_grub" }, flee = true, bg = "chain" },
  vt_e_rear = { foes = { "vt_rearguard", "vt_rearguard" }, flee = true, bg = "chain" },
  vt_e_aid = { foes = { "vt_rearguard", "vt_surgeon" }, flee = true, bg = "chain" },
  vt_e_nothic = { foes = { "vt_nothic", "vt_moth" }, flee = true, bg = "chain" },
  vt_e_nothics = { foes = { "vt_nothic", "vt_nothic" }, flee = true, bg = "ruin" },
  vt_e_reader = { foes = { "vt_reader", "vt_nothic" }, flee = true, bg = "ruin" },
  vt_e_pages = { foes = { "vt_pages", "vt_pages", "vt_pages" }, flee = true, bg = "ruin" },
  vt_e_stacks = { foes = { "vt_pages", "vt_pages", "vt_reader" }, flee = true, bg = "ruin" },
  vt_e_worm = { foes = { "vt_bookworm" }, flee = false, bg = "chain", boss = true },
  vt_e_matron = { foes = { "vt_matron" }, flee = false, bg = "ruin", boss = true },
  vt_e_qarhuul = { foes = { "vt_qarhuul" }, flee = false, bg = "chain", boss = true, mustLose = true },
}

R.shops.vt_stores = { tier = 5 }

-- ---------------------------------------------------------------- goals

R.goals = {
  { done = "vt_met_clerk", text = "Ask at the Clinic desk", map = "vt_vault_1", x = 6, y = 6, when = "ud_done" },
  { done = "vt_toll_paid", text = "Pay the nothic's toll", map = "vt_vault_2", x = 14, y = 11, when = "ud_done" },
  { done = "vt_fell", text = "Cross the long span", map = "vt_vault_2", x = 20, y = 11, when = "ud_done" },
  { done = "vt_hoisted", text = "Free the cargo hoist", map = "vt_vault_3", x = 22, y = 11, when = "ud_done" },
  { done = "vt_worm_down", text = "Shut the three stopcocks", map = "vt_vault_4", x = 13, y = 3, when = "ud_done" },
  { done = "vt_matron_down", text = "Reach the far door", map = "vt_vault_5", x = 14, y = 5, when = "ud_done" },
  { done = "vt_too_late", text = "Find Colette", map = "vt_vault_6", x = 11, y = 2, when = "ud_done" },
  { done = "ruined", text = "Run", map = "vt_vault_7", x = 29, y = 8, when = "ud_done" },
}

-- ---------------------------------------------------------------- maps

-- A shelf of cavern rock with the Clinic's tent on it, and the first of the chain roads. The way on is the little lantern at the
-- east end of the bridge. The stair the party came down is gone.
R.maps.vt_vault_1 = {
  name = "THE LAST LANDING", theme = "chain", savepoint = true,
  rows = {
    "########################",
    "#.........#~~~~~~~~~~~~#",
    "#.........#~~~~~~~~~~~~#",
    "#.hhh+hhh.#~~~~~~~~~~~~#",
    "#.h.....h.#~~~~~~hhhhh~#",
    "#.h.....h.~~~~~~~h.>.h~#",
    "#.h.....h.~~~~~~~h...h~#",
    "#.hhhhhhh.~~~~~~~hh+hh~#",
    "#...................~~~#",
    "#.........~~~~.~~~~~~~~#",
    "#.........~~~~.~~~~~~~~#",
    "#.#####...~~hh+hh~~~~~~#",
    "#.........~~h...h~~~~~~#",
    "#.........~~h...h~~~~~~#",
    "#.........~~hhhhh~~~~~~#",
    "########################",
  },
  npcs = {
    { id = "satchel", x = 6, y = 6, sprite = "guard", script = "vt_talk_clerk" },
    { id = "vt_board", x = 9, y = 9, sprite = "vt_sign", script = "vt_read_board" },
    { id = "vt_cradle_top", x = 8, y = 10, sprite = "vt_cradle", script = "vt_cradle_down", when = "vt_worm_down" },
  },
  steps = {
    { x = 3, y = 3, script = "vt_arrive", unless = "vt_arrived" },
  },
  chests = {
    { id = "c1", x = 9, y = 14, give = "hipotion", n = 3 },
    { id = "c2", x = 15, y = 14, give = "spider_silk" },
    { id = "c3", x = 2, y = 14, gold = 900 },
  },
  foes = {
    { id = "f1", x = 13, y = 9, enc = "vt_e_moths", sprite = "vt_moth" },
    { id = "f2", x = 15, y = 11, enc = "vt_e_grubs", sprite = "vt_grub" },
  },
  exits = {
    { x = 20, y = 6, map = "vt_vault_2", mx = 3, my = 11, dir = 2 },
  },
}

-- Three lanterns and the roads between them. Margin sits at the east door of the middle one. The long span goes east from there,
-- and doesn't arrive.
R.maps.vt_vault_2 = {
  name = "THE CHAIN ROADS", theme = "chain",
  rows = {
    "############################",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~hhhhh~~~~~~~~~hhhhh~~~~~#",
    "#~~h...h~~~~~~~~~h...h~~~~~#",
    "#~~h...+.........+...h~~~~~#",
    "#~~h...h~~~~.~~~~h...h~~~~~#",
    "#~~hh+hh~~~~.~~~~hhhhh~~~~~#",
    "#~~~~.~~~~~~.~~~~~~~~~~~~~~#",
    "#hhhh+hh~~~~.~~~~~~~~~~~~~~#",
    "#h.....h~~hh+hh~~~~~~~~~~~~#",
    "#h.....+..+...+...........h#",
    "#h>....h~~h...h~~~~~~~~~~~h#",
    "#hhhhhhh~~hhhhh~~~~~~~~~~~h#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "############################",
  },
  npcs = {
    { id = "vt_margin", x = 14, y = 11, sprite = "vt_nothic", script = "vt_toll", unless = "vt_toll_paid" },
    { id = "vt_ashes", x = 6, y = 5, sprite = "vt_ashes", script = "vt_read_ashes" },
    { id = "vt_window", x = 20, y = 5, sprite = "vt_window", script = "vt_read_window" },
    { id = "vt_gap", x = 19, y = 11, sprite = "vt_gap", script = "vt_read_gap", when = "vt_fell" },
  },
  steps = {
    { x = 20, y = 11, script = "vt_fall", unless = "vt_fell" },
  },
  chests = {
    { id = "c1", x = 5, y = 4, give = "hiether", n = 2 },
    { id = "c2", x = 21, y = 6, give = "web_staff" },
    { id = "c3", x = 12, y = 12, give = "feather", n = 1 },
  },
  foes = {
    { id = "f1", x = 9, y = 11, enc = "vt_e_rear", sprite = "orderly" },
    { id = "f2", x = 13, y = 8, enc = "vt_e_nothic", sprite = "vt_nothic" },
    { id = "f3", x = 15, y = 5, enc = "vt_e_moths", sprite = "vt_moth" },
    { id = "f4", x = 19, y = 4, enc = "vt_e_aid", sprite = "doctor" },
    { id = "f5", x = 17, y = 11, enc = "vt_e_grubs", sprite = "vt_grub" },
  },
  exits = {
    { x = 3, y = 12, map = "vt_vault_1", mx = 20, my = 7, dir = 3 },
  },
}

-- What the party falls into: half-buildings, tilted, hung off each other by whatever held. West room is where you land, the
-- brakes are north-west and south, the hoist is at the east end of the east room.
R.maps.vt_vault_3 = {
  name = "THE BROKEN LANTERNS", theme = "chain", savepoint = true,
  rows = {
    "##########################",
    "#~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~hhhhhhh~~~~~hhhhhhh~~~~#",
    "#~h.....h~~~~~h.....h~~~~#",
    "#~h.....+.....+.....h~~~~#",
    "#~h.....h~~.~~h.....h~~~~#",
    "#~hhh+hhh~~.~~hhhh+hh~~~~#",
    "#~~~~.~~~~~.~~~~~~.~~~~~~#",
    "#hhhh+hhhh~.~~~hhh+hhhh~~#",
    "#h.......h~.~~~h......h~~#",
    "#h.......+.....+......h~~#",
    "#h.......h~.~~~h......h~~#",
    "#hhhhhhhhh~.~~~hhhh+hhh~~#",
    "#~~~~~~~~~~.~~~~~~~.~~~~~#",
    "#~~~~~~~hhh.hhh~~~~.~~~~~#",
    "#~~~~~~~h.....h~~hh+hh~~~#",
    "#~~~~~~~h.....h~~h...h~~~#",
    "#~~~~~~~hhhhhhh~~hhhhh~~~#",
    "##########################",
  },
  npcs = {
    { id = "vt_wounded", x = 7, y = 10, sprite = "orderly", script = "vt_talk_wounded" },
    { id = "vt_brake_n", x = 6, y = 4, sprite = "vt_brake", script = "vt_pin_north" },
    { id = "vt_brake_s", x = 12, y = 17, sprite = "vt_brake", script = "vt_pin_south" },
    { id = "vt_stitcher", x = 18, y = 5, sprite = "vt_stitcher", script = "vt_read_receipt" },
    { id = "vt_hoist", x = 22, y = 11, sprite = "vt_hoist", script = "vt_ride_hoist" },
  },
  chests = {
    { id = "c1", x = 8, y = 6, give = "xpotion", n = 1 },
    { id = "c2", x = 20, y = 17, give = "drow_plate" },
    { id = "c3", x = 10, y = 17, give = "hiether", n = 2 },
    { id = "c4", x = 16, y = 6, gold = 1400 },
  },
  foes = {
    { id = "f1", x = 12, y = 8, enc = "vt_e_grubs", sprite = "vt_grub" },
    { id = "f2", x = 18, y = 11, enc = "vt_e_reader", sprite = "vt_reader" },
    { id = "f3", x = 12, y = 13, enc = "vt_e_moths", sprite = "vt_moth" },
    { id = "f4", x = 13, y = 5, enc = "vt_e_nothic", sprite = "vt_nothic" },
    { id = "f5", x = 19, y = 8, enc = "vt_e_rear", sprite = "orderly" },
  },
}

-- The great chain itself goes up through the middle, where nobody walks. A ring of road goes round it, with a stopcock at the
-- north, east and south and the Clinic's camp at the west. The chain gate to the stacks is at the north-east corner.
R.maps.vt_vault_4 = {
  name = "THE GREAT CHAIN", theme = "chain", savepoint = true,
  rows = {
    "##########################",
    "#~~~~~~~~~~hhhhh~~~~~~~~~#",
    "#~~~~~~~~~~h...h~~>~~~~~~#",
    "#~~~~~~~~~~hh.hh~~.~~~~~~#",
    "#~~~~~~~...........~~~~~~#",
    "#~~~~~~~.~~~~~~~~~.~~~~~~#",
    "#~~~~~~~.~hhhhhhh~.~~~~~~#",
    "#~~~~~~~.~hhhhhhh~.~~~~~~#",
    "#hhhhhh~.~hhhhhhh~.~~hhhh#",
    "#h....+..~hhhhhhh~...+..h#",
    "#h....h~.~hhhhhhh~.~~h..h#",
    "#hhhhhh~.~hhhhhhh~.~~hhhh#",
    "#~~~~~~~.~hhhhhhh~.~~~~~~#",
    "#~~~~~~~.~~~~~~~~~.~~~~~~#",
    "#~~~~~~~...........~~~~~~#",
    "#~~~~~~~~~~hh.hh~~~~~~~~~#",
    "#~~~~~~~~~~h...h~~~~~~~~~#",
    "#~~~~~~~~~~hhhhh~~~~~~~~~#",
    "##########################",
  },
  npcs = {
    { id = "vt_kettle", x = 4, y = 10, sprite = "vt_kettle", script = "vt_read_kettle" },
    { id = "vt_hoist_top", x = 3, y = 10, sprite = "vt_hoist", script = "vt_ride_down" },
    { id = "vt_wheel_n", x = 13, y = 3, sprite = "vt_wheel", script = "vt_stop_north" },
    { id = "vt_wheel_e", x = 24, y = 10, sprite = "vt_wheel", script = "vt_stop_east" },
    { id = "vt_wheel_s", x = 15, y = 17, sprite = "vt_wheel", script = "vt_stop_south" },
    { id = "vt_gate", x = 19, y = 4, sprite = "vt_gate", script = "vt_read_gate", unless = "vt_worm_down" },
  },
  chests = {
    { id = "c1", x = 6, y = 11, give = "tent", n = 1 },
    { id = "c2", x = 23, y = 11, give = "panacea", n = 2 },
    { id = "c3", x = 13, y = 17, give = "xpotion", n = 2 },
    { id = "c4", x = 15, y = 3, give = "spider_fang" },
  },
  foes = {
    { id = "f1", x = 9, y = 7, enc = "vt_e_aid", sprite = "doctor" },
    { id = "f2", x = 19, y = 13, enc = "vt_e_nothic", sprite = "vt_nothic" },
    { id = "f3", x = 14, y = 15, enc = "vt_e_grubs", sprite = "vt_grub" },
    { id = "f4", x = 14, y = 5, enc = "vt_e_rear", sprite = "orderly" },
    { id = "f5", x = 20, y = 10, enc = "vt_e_moths", sprite = "vt_moth" },
  },
  exits = {
    { x = 19, y = 3, map = "vt_vault_5", mx = 14, my = 17, dir = 1, when = "vt_worm_down" },
  },
}

-- The lantern of all lanterns, on a slant now. Aisles of shelves, the way in at the south and the Matron's desk in the one
-- corridor north. The cradle down to the landing is in the south-west corner.
R.maps.vt_vault_5 = {
  name = "THE STACKS", theme = "library", savepoint = true,
  rows = {
    "#############>##############",
    "#hhhhhhhhhhhh+hhhhhhhhhhhhh#",
    "#hhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#hhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#..........................#",
    "#.hhhh.hhhh.hhhh.hhhh.hhhh.#",
    "#.hhhh.hhhh.hhhh.hhhh.hhhh.#",
    "#..........................#",
    "#.hhhh.hhhh.hhhh.hhhh.hhhh.#",
    "#.hhhh.hhhh.hhhh.hhhh.hhhh.#",
    "#..........................#",
    "#.hhhh.hhhh.hhhh.hhhh.hhhh.#",
    "#.hhhh.hhhh.hhhh.hhhh.hhhh.#",
    "#..........................#",
    "#hhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#hhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#hhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#############>##############",
  },
  npcs = {
    { id = "vt_matron", x = 14, y = 4, sprite = "doctor", script = "vt_scene_matron", unless = "vt_matron_down" },
    { id = "vt_margin_2", x = 22, y = 5, sprite = "vt_nothic", script = "vt_talk_margin" },
    { id = "vt_cradle_low", x = 2, y = 14, sprite = "vt_cradle", script = "vt_cradle_up" },
    { id = "vt_robe", x = 2, y = 8, sprite = "vt_robe", script = "vt_read_robe" },
    { id = "vt_letter", x = 27, y = 11, sprite = "vt_lectern", script = "vt_read_letter" },
    { id = "vt_drawer", x = 7, y = 7, sprite = "vt_drawer", script = "vt_read_drawer" },
  },
  steps = {
    { x = 14, y = 16, script = "vt_stacks_in", once = true },
    { x = 14, y = 5, script = "vt_scene_matron", unless = "vt_matron_down" },
  },
  chests = {
    { id = "c1", x = 2, y = 6, give = "mind_ward" },
    { id = "c2", x = 27, y = 13, give = "feather", n = 2 },
    { id = "c3", x = 17, y = 13, give = "gloam_robe" },
    { id = "c4", x = 12, y = 6, give = "elixir", n = 1 },
  },
  foes = {
    { id = "f1", x = 7, y = 11, enc = "vt_e_pages", sprite = "vt_pages" },
    { id = "f2", x = 17, y = 8, enc = "vt_e_stacks", sprite = "vt_reader" },
    { id = "f3", x = 22, y = 11, enc = "vt_e_nothics", sprite = "vt_nothic" },
    { id = "f4", x = 12, y = 9, enc = "vt_e_pages", sprite = "vt_pages" },
    { id = "f5", x = 27, y = 8, enc = "vt_e_nothics", sprite = "vt_nothic" },
    { id = "f6", x = 6, y = 14, enc = "vt_e_reader", sprite = "vt_reader" },
  },
  exits = {
    { x = 14, y = 18, map = "vt_vault_4", mx = 19, my = 5, dir = 3 },
    { x = 14, y = 1, map = "vt_vault_6", mx = 11, my = 15, dir = 1, when = "vt_matron_down" },
  },
}

-- A ring of boards round a well, with Colette's island in the middle of it. The nearest the ring comes is the middle of the far
-- side, and that's three squares short. You can see everything from there. That's what it's for.
R.maps.vt_vault_6 = {
  name = "THE READING ROOM", theme = "library",
  rows = {
    "#####################",
    "#...................#",
    "#.~~~~~~~~~~~~~~~~~.#",
    "#.~~~~~~~~~~~~~~~~~.#",
    "#.~~~~~.......~~~~~.#",
    "#.~~~~~.......~~~~~.#",
    "#.~~~~~.......~~~~~.#",
    "#.~~~~~.......~~~~~.#",
    "#.~~~~~.......~~~~~.#",
    "#.~~~~~~~~~~~~~~~~~.#",
    "#.~~~~~~~~~~~~~~~~~.#",
    "#...................#",
    "##########+##########",
    "#hhhhhhhh...hhhhhhhh#",
    "#hhhhhhhh...hhhhhhhh#",
    "##########>##########",
  },
  npcs = {
    { id = "colette", x = 11, y = 5, sprite = "doctor", script = "vt_shout", unless = "vt_too_late" },
    { id = "father", x = 11, y = 7, sprite = "blighted", script = "vt_shout", unless = "vt_too_late" },
    { id = "vt_desk", x = 9, y = 6, sprite = "vt_desk", script = "vt_shout", unless = "vt_too_late" },
  },
  steps = {
    { x = 11, y = 14, script = "vt_memory", once = true },
    { x = 11, y = 12, script = "vt_ring", once = true },
    { x = 11, y = 2, script = "vt_scene_colette", unless = "vt_too_late" },
  },
  chests = {
    { id = "c1", x = 10, y = 15, give = "xpotion", n = 2 },
    { id = "c2", x = 12, y = 15, give = "hiether", n = 2 },
  },
  exits = {
    { x = 11, y = 16, map = "vt_vault_5", mx = 14, my = 3, dir = 3 },
  },
}

-- One road, one way. Every step along it costs someone.
R.maps.vt_vault_7 = {
  name = "THE FALLING ROAD", theme = "chain",
  rows = {
    "################################",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#hhh~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#............................~~#",
    "#hhh~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "################################",
  },
  steps = {
    { x = 8, y = 8, script = "vt_scene_qarhuul", unless = "vt_q_done" },
    { x = 13, y = 8, script = "vt_lose_sister", when = "vt_q_done", unless = "vt_lost_sister" },
    { x = 18, y = 8, script = "vt_lose_jezzara", when = "vt_lost_sister", unless = "vt_lost_jezzara" },
    { x = 23, y = 8, script = "vt_lose_doctor", when = "vt_lost_jezzara", unless = "vt_lost_doctor" },
    { x = 26, y = 8, script = "vt_alone", when = "vt_lost_doctor", once = true },
    { x = 29, y = 8, script = "vt_the_end", when = "vt_lost_doctor", unless = "ruined" },
  },
  exits = {
  },
}

-- ---------------------------------------------------------------- the last landing

S.vt_arrive = {
  t("The stair out of the Underdark ends on a shelf of black rock, and the world stops. Past the edge there is no floor, no wall and no far side. There are only the lanterns."),
  t("Hundreds of them, each as big as a town hall, hang out of the dark on chains as thick as a street. Some are still lit. A long way below them a grey mist lies quite still, the way water lies in a well."),
  owlin("The Nightmare Vault. Everything I ever wanted to read is in there, and I'd give the lot to be looking at it from further away."),
  t("Behind you the last flight of the stair slides off the rock with a long sigh, and goes down into the mist. The timbers have been sawn most of the way through. Somebody has chalked MIND THE STEP on the wall."),
  deserter("That's Clinic work. They'd want it noted that you were warned."),
  jezzara("So we're not going back. Good. There's a lamp in that tent."),
  { set = "vt_arrived" },
}

S.vt_talk_clerk = {
  { when = "vt_met_clerk", steps = {
    ask(clerk("Four hundred and twelve, outstanding. I'm to count the column back in, so I've brought a chair. The stores are behind me, and there's a cot, if you'll sign."), {
      { "Show me the stores.", {
        { shop = "vt_stores" },
      } },
      { "A cot for the night. (120 gold)", {
        { inn = 120 },
        { save = true },
      } },
      { "That's all.", {} },
    }),
  }, other = {
    t("At the back of the tent there's a folding desk, a folding chair, and a small man with a satchel, who looks up as if you were slightly late."),
    clerk("Good evening. Do mind the edge. You'll be four hundred and twelve, of Scythebreak. I've had you down as outstanding for some time."),
    deserter("I know that satchel. You counted that town at midnight, with the ward breathing behind you."),
    clerk("Records Office, attached to the column. Doctor Colette passed this desk nineteen hours ago, with sixty in good order and forty casks. She signed as Queen. Then she crossed it out and put 'doctor'. It'll have to be initialled."),
    ask(clerk("I'm afraid I've nothing for you to sign. Was there something else?"), {
      topic("Forty casks of what?", {
        clerk("Stencilled 'for the damp', though I've seen the manifest. It's Sindal's deep reserve, every drop, bought through the flayers. She's having it run along the chains as she goes. That's the red line by your foot."),
        deserter("She's put the Vault on a drip. Forty casks, at that bore. It'd take a day and a night to run through. Friend, that's how long we've got."),
      }),
      topic("What was the count for?", {
        clerk("Do you know, I finally asked. Sixteen years, and the question took about a minute. It's for the Tome. So much blood to so many people, that's how it works. You can't make up a dose without the patient's weight."),
        clerk("Every Dream Book, every door, every town. I was only ever told how many. I've been weighing the world for her, and I had thought it was filing."),
        { set = "vt_heard_dose" },
      }),
      { "Stand aside. We're going after her.", {
        clerk("By all means. The road starts at the end of this shelf, and the stores are here if you want them. I'm told it's the worm you should look out for. I've no figure for the worm."),
      } },
      { "You helped her do this.", {
        clerk("I counted. I'd like that noted. I've been sitting here trying to think of another word for it, and it has been a very long nineteen hours."),
      } },
    }),
    { when = "vt_heard_dose", steps = {
      deserter("All those forms. All those clean little columns. Friend, it was a prescription. It was always a prescription."),
    } },
    { set = "vt_met_clerk" },
  } },
}

S.vt_read_board = {
  t("VAULT COLUMN: STANDING ORDERS. 1. DO NOT READ. 2. IF YOU HAVE READ, REPORT TO MATRON. 3. IF SOMETHING HAS READ YOU, THERE IS NO NEED TO REPORT. 4. KEEP THE LINE CLEAR. 5. THERE IS NO NEED TO BE AFRAID."),
}

S.vt_cradle_down = {
  t("The Clinic's cargo cradle sways in its rails. It still runs to the stacks."),
  { choice = {
    { "Ride it back up to the stacks.", {
      { warp = { "vt_vault_5", 3, 14, 2 } },
    } },
    { "Stay here for now.", {} },
  } },
}

-- ---------------------------------------------------------------- the chain roads

S.vt_toll = {
  t("At the far door of this lantern something sits with its knees up, where a clerk would sit. It's grey and hairless and about the size of a child, with long clever hands and one wet eye that takes up most of its face."),
  margin("Shh. This is a quiet floor. Reader's ticket? No. You've no ticket, you came in by the Clinic's hole. That's all right. You'll pay at the door, like the others."),
  owlin("A nothic. They were wizards once, people who read one thing too far. Don't let it look at you for long."),
  margin("I'm called Margin, because that's where I live. The toll is one true thing, read out loud. I don't keep it. I only say it. You'd be surprised what people will pay to have it stop."),
  ask(margin("Sixty went over ahead of you, and they all paid. Whose page shall I turn?"), {
    topic("Read the doctor.", {
      margin("Eleven carts. And you tell yourself you never counted what was in them. You counted. You count them when you wash your hands. Two hundred and six."),
      deserter("Seven. Two hundred and seven. You've missed one."),
    }),
    topic("Read the sister.", {
      margin("A thousand nights at a thousand beds, and you've never once asked for one of them to live. You only ask that it's quick. You've started looking forward to it."),
      cleric("That's between her and me. Turn the page."),
    }),
    topic("Read the scholar.", {
      margin("The failed cure. You tell them your name was on the third line of the report. It was the first. You signed it before the trial was over, because you wanted to be right."),
      owlin("I know what I signed."),
    }),
    topic("Read Jezzara.", {
      margin("You don't kill for the money. You kill to be told you're the best. Nobody has ever told you anything else."),
      jezzara("Is that it? I've got worse than that in my other coat. Everyone knows I'm the best."),
    }),
    { "Read me, then.", {
      margin("You, then. Come into the light. Let's see. A town, a nan, a loaf of bread. And then nothing. Page after page of it. I've never seen such clean..."),
      t("The wet eye slides down you, and stops. It stays stopped for some time. The long hands have begun to shake."),
      margin("Two of your pages are stuck together. Right at the very front. Whoever shut them..."),
      t("She closes her eye. You hadn't known they could. The lantern is suddenly very quiet."),
      margin("No. That one's not for lending. The toll's paid, it's paid. Go across, all of you, quickly, before I can't help myself. And mind the Bookworm. It goes round the chains, and it's read everyone who ever fell."),
      { set = "vt_toll_paid" },
    } },
  }),
  jezzara("I once watched one of those eat its own hand, to see what would happen. Nothing scares them. What did it see?"),
  deserter("Nothing. That's what it's always going to be, isn't it, friend? Let's keep moving."),
}

S.vt_read_ashes = {
  t("A Clinic rest halt. Sixty tidy squares in the dust where the bedrolls were, and a drum fire raked out exactly as the regulations say."),
  deserter("Warm at the bottom. They rake it on the half hour, and they're never late. Call it eleven hours. We've made up eight, and they aren't even trying to hide it."),
  cleric("She wants us to know we're close. Doesn't she?"),
  deserter("She wants someone to know."),
}

S.vt_read_window = {
  t("Through a gap in the wall you can see the lantern's chain going up into the dark. There's another one, that you hadn't noticed, going down."),
  owlin("Look how that lower chain stands. It's as tight as a bowstring, all the way to the mist. They all are, every lantern. A chain with nothing on the end of it hangs slack."),
  jezzara("So there's something on the end of it."),
  owlin("Nobody hung this place up here. It's been pegged down. It's a lid. And she's going to stand on it and read out loud."),
}

S.vt_read_gap = {
  t("The boards end here. A few chains swing in the air, a long way from anything."),
}

S.vt_fall = {
  t("Halfway across, the chain under your hand begins to hum. Then all of them do. It comes along the span towards you from somewhere out in the dark, the way a tune comes along a street."),
  owlin("That isn't wind. There's no wind down here."),
  t("Something passes beneath the boards, quite fast, and very long. There are a great many links of it. It looks up as it goes, with one wet eye the size of a cart wheel."),
  jezzara("Run. No, not back. RUN."),
  { sfx = "horn" },
  { big = "THE ROAD GOES" },
  { fade = true },
  { warp = { "vt_vault_3", 4, 11, 2 } },
  { set = "vt_fell" },
  t("You come down hard on a floor that isn't level, and slide, and stop. Books are still landing around you. You've fallen into what's left of a lantern, hung off its neighbours by a few bent chains."),
  deserter("Is anybody dead? No? Then let's not make a habit of it. There's a cargo hoist at the east end of this wreck. I can see the rails. That's our way up."),
}

-- ---------------------------------------------------------------- the broken lanterns

S.vt_talk_wounded = {
  { when = "vt_met_wounded", steps = {
    t("He lies very straight. Someone has folded his hands, with hospital corners."),
  }, other = {
    t("Someone has made up a bed on the tilted floor, and the blanket has hospital corners. A Clinic orderly lies on it, very straight, with a clean bandage tied round his own eyes."),
    orderly("Good evening. I'm so sorry, I can't see who's there. Are you on the sheet?"),
    deserter("I used to be."),
    orderly("Doctor? How nice. You'll forgive my not getting up. I was told not to read anything, and I want it known I never meant to. It was only one line. It was lying on the floor."),
    orderly("The column went up by the hoist four hours ago. Matron has left me to be looked after. I'm looking after myself, as per her note. I'm doing very well."),
    ask(orderly("I can still see the line, doctor, with the bandage on. Eleven of us can, and they've gone on walking. Would you like me to tell you what it says?"), {
      { "No. Don't say it. Rest.", {
        cleric("I'll sit with him for a moment. You needn't wait."),
        t("She does. It doesn't take long. She comes back with his bandage folded in her hand, and says nothing, and neither do you."),
      } },
      { "Tell me.", {
        deserter("Friend, what are you...? Everyone, cover your ears!"),
        t("He tells you. He says it clearly, in a pleasant voice. It's a short sentence, and you hear every word of it. You wait. Nothing happens. It's just some words."),
        orderly("Oh. Oh, how lovely. It's got nothing to hold on to. I do wish I'd been you."),
        t("He smiles, and lets out a breath. He doesn't take another."),
        { set = "vt_told_line" },
      } },
    }),
    { set = "vt_met_wounded" },
  } },
}

S.vt_read_receipt = {
  t("A Stitcher in Sindal's colours lies across a heap of fallen books, as neat and handsome as the day he died. There's a slip of vellum in his hand."),
  t("RECEIVED OF THE VEINS OF SINDAL, ONE HUNDRED, IN GOOD HEALTH. LENT IN RETURN, ONE VOLUME: ON THE OPENING OF THE HOLLOW ONE. DUE BACK: NEVER."),
  cleric("One hundred what?"),
  jezzara("You know what. So Sindal's been shopping here too. The Hollow One. Isn't that...?"),
  owlin("Tiamat's black head. No. Nobody could be that stupid."),
  deserter("I've met him. He could, and he'd be charming about it."),
}

S.vt_pin_north = {
  { when = "vt_pin_a", steps = {
    t("The brake bar lies where you dropped it. The wheel creaks round a tooth or two on its own."),
  }, other = {
    t("The hoist's north brake is a bar as long as you are, pinned through a toothed wheel. There's a chit wired to it. PINNED BY ORDER. PLEASE LEAVE THE HOIST AS YOU WOULD WISH TO FIND IT."),
    t("It takes three of you. It comes out with a shriek you'd rather have kept to yourselves, and somewhere out in the dark the chains begin, faintly, to hum."),
    { set = "vt_pin_a" },
  } },
}

S.vt_pin_south = {
  { when = "vt_pin_b", steps = {
    t("The south brake is off. There's nothing here now but the wheel, and the drop."),
  }, other = {
    t("The south brake, and another chit, in the same neat hand. THANK YOU FOR YOUR COOPERATION."),
    jezzara("I want to find whoever writes these. It's not a job. I'd do it for nothing."),
    t("The bar comes free, and goes over the edge. You never hear it land."),
    { set = "vt_pin_b" },
  } },
}

S.vt_ride_hoist = {
  { all = { "vt_pin_a", "vt_pin_b" }, steps = {
    t("Freed, the cage rocks on its chain. It's built for casks. Someone has to work the hand line, and it turns out to be everyone."),
    { when = "vt_told_line", steps = {
      jezzara("That orderly said something to you and died happy, and you're just standing there. Does it ever occur to you that you're strange?"),
    } },
    { set = "vt_hoisted" },
    { warp = { "vt_vault_4", 4, 11, 2 } },
    t("The hoist opens on the great chain, the one every other chain in the cavern comes back to. A road runs right round it, and the air tastes of pennies."),
    deserter("There's the red line. It splits three ways round the chain, north, east and south, and each branch has a stopcock. Shut all three and the casks stay where they are."),
  }, other = {
    t("The cage won't stir. Two great brakes hold its chain, one at the north end of the wreck and one down at the south. You can see both from here, and the bars they're pinned with."),
  } },
}

S.vt_ride_down = {
  t("The hoist hangs here, ready, on its hand line."),
  { choice = {
    { "Stay up here.", {} },
    { "Go down to the broken lanterns.", {
      { warp = { "vt_vault_3", 21, 11, 4 } },
    } },
  } },
}

-- ---------------------------------------------------------------- the great chain

S.vt_read_kettle = {
  t("A Clinic camp, packed and swept. A kettle of soup still hangs over a spirit lamp. It's warm. One clean bowl has been left out, with a chit in it. FOR THE DOCTOR WHO MAKES THE SOUP."),
  deserter("Two hours. Two hours ahead of us, and she stopped to leave me that. She has never once let a column march hungry. The terrible thing, friend, is that it's very good soup."),
  { choice = {
    { "Eat, and rest a while.", {
      { fade = true },
      { heal = true },
      { save = true },
    } },
    { "Leave it. We're close.", {
      jezzara("Good. I don't eat anything with a note on it."),
    } },
  } },
}

S.vt_read_gate = {
  t("A curtain of hanging chain closes this way off, drawn tight from overhead. The red line runs in under it. It won't lift while the great chain's under this much strain."),
}

local WHEELS = { "vt_wheel_a", "vt_wheel_b", "vt_wheel_c" }

local WORM = {
  t("The last wheel comes round. All along the red line the pulse stops, and for the first time since the stair it's quiet."),
  { big = "THE LINE IS SHUT" },
  deserter("That's it. That's forty casks that never reach her. Friend, I think we've actually..."),
  t("The chain under your feet has begun to hum."),
  jezzara("Oh, you would. You would say it out loud."),
  t("It comes up round the great chain in a long slow spiral, link over link. There's a great deal of it. It has been following the sound of you since the first bridge."),
  t("At the front of it is one eye, wet and bloodshot, and it looks at you the way the nothics do. It has read everyone who ever came here. Then it ate them, to be sure."),
  { battle = "vt_e_worm" },
  t("It stops. It hangs on the great chain for a moment, coil over coil, with its eye on you. Then it lets go, and slides away down into the mist. It takes a long while. It takes a lot of the chain with it."),
  t("The whole of the road drops a yard, and stops, with a sound you feel in your teeth. Far off a lantern goes out. Then the next one along."),
  t("Something small and grey comes down the chain hand over hand, and hangs there by one arm, looking at where it went."),
  margin("Shh. Oh, what have you done? Nine thousand years it's gone round these chains. Where a link rusted it ate the link and laid another. It wasn't guarding the books. It was the only thing mending the lid."),
  owlin("You told us it hunted people!"),
  margin("It hunted readers. What did you think it was for? Well, the chain gate's slack now, so the stacks are open. Go and see what she came for. You won't be in time. Nobody ever is. It's the first thing you learn down here."),
  { set = "vt_worm_down" },
}

--- A stopcock. Its flag stays set if the fight is lost, so any of the three can bring the worm back.
local function stopcock(flag, text)
  return {
    { when = "vt_worm_down", steps = {
      t("The wheel is shut. The pipe has gone cold under your hand. Whatever that bought, it's bought."),
    }, other = {
      { when = flag, other = {
        t(text),
        { set = flag },
      } },
      { all = WHEELS, steps = WORM, other = {
        { count = WHEELS, at = 2, steps = {
          deserter("That's two. The line's dropped by half, I can feel it in the pipe. One more."),
        }, other = {
          deserter("That's one, and the gauge has moved. It works, friend. Two more."),
        } },
      } },
    } },
  }
end

S.vt_stop_north = stopcock("vt_wheel_a", "A red iron wheel, clamped to a link of the great chain. It's stiff, and it's warm, and the pipe beside it beats like a wrist. You put your weight on it and it turns.")
S.vt_stop_east = stopcock("vt_wheel_b", "The east stopcock, with a Clinic tag on it: CHECKED. The doctor reads the tag, and turns it over, and puts both hands on the wheel next to yours.")
S.vt_stop_south = stopcock("vt_wheel_c", "The south stopcock. Something has been gnawing at the link it's clamped to, and has stopped. The wheel comes round with a long wet sigh.")

-- ---------------------------------------------------------------- the stacks

S.vt_stacks_in = {
  t("The great lantern hangs on a slant now, and all its lamps lean the same way. Somewhere among the shelves, loose pages are moving, the way pigeons move in a loft."),
  owlin("Don't touch anything. I'm saying that to myself."),
}

S.vt_talk_margin = {
  ask(margin("Shh. It's still a quiet floor, though less of one than it was. Ask quickly. We're all about to be overdue."), {
    topic("What's under the Vault?", {
      margin("Everything wrong with the world has the same handwriting. It came here first. People who aren't in any catalogue now put this place on top of it, and pegged it down. I shan't say its name. It's been listening for that."),
    }),
    topic("What are the missing pages?", {
      margin("The Tome was never a weapon, dear. It's a dosing chart. Enough blood and the right words, and a whole people lies down and doesn't get up. She had that half. The pages we kept are the other half. They say who the dose is for."),
    }),
    { "We're going on.", {} },
  }),
}

S.vt_cradle_up = {
  t("The Clinic's cargo cradle hangs in its rails. It runs back to the landing, and the small man's folding chair."),
  { choice = {
    { "Stay in the stacks.", {} },
    { "Ride down to the landing.", {
      { warp = { "vt_vault_1", 7, 10, 3 } },
    } },
  } },
}

S.vt_read_robe = {
  t("A carrel has been bricked up from the inside, and someone has knocked out one course to look. There's a smell of old brine. A mind flayer's robe sits in the chair, with nobody in it."),
  t("The desk is covered in a small neat hand, over and over. HOW TO HOLD THEM WITHOUT THE MOTHER. HOW TO HOLD THEM. HOW TO HOLD. The last page is very tidy. It says: IT WAS HOLDING ME."),
  jezzara("Zalabarula. The Brain Sipper. Half of Crysathula's been looking for him since before there was a Crysathula. I'd leave that chair alone."),
}

S.vt_read_letter = {
  t("A letter on good paper has been left on a reading stand, weighted with a Clinic lancet. The paper smells faintly of the sea."),
  t("'My dear doctor. You asked if he is still there. He is, and he has been asking for you. I should go quickly. You are owed, and I do so hate to see a debt outlive the debtor. Your friend in the deep, V.'"),
  jezzara("I've been paid in that handwriting. She doesn't write a thing down until it has already happened."),
  deserter("She's the cleverest person I ever met. She'll have read that, and known just what it was, and gone anyway."),
}

S.vt_read_drawer = {
  t("A tall card catalogue, with one small drawer pulled out. It's open at your name. Someone has been here before you, and left it so."),
  t("Every other card in the drawer is black with tiny writing. Yours has one line, in a hand so old that the ink has gone brown. REFERENCE ONLY. NOT TO BE TAKEN OUT."),
}

S.vt_scene_matron = {
  t("At the end of the last aisle a lamp burns on a small clean desk, with a door behind it and a brass handbell at its corner. A tall woman in a starched cap sits writing, as if the Vault were a ward and this the night shift."),
  matron("Visiting hours are over. Oh. It's you, doctor. You've let your cuffs go. I did tell you, in your first week, what a person's cuffs say about their patients."),
  deserter("Matron. Friend, stand behind me. This woman taught me to make a bed, lance a boil and sign for a cart, all in the one year."),
  matron("Doctor Colette passed this desk twenty minutes ago. If you'd hurried, you could have been too late in person."),
  ask(matron("You may have three questions. I find relatives are calmer after three questions."), {
    topic("Where are the sixty?", {
      matron("Transferred. We came up short at the last stopcock, eleven casks lost on the chains, and a column has its own supply, if it's asked nicely. They were all very good about it."),
      deserter("All sixty, Matron?"),
      matron("Nobody counts a transfer, doctor. I taught you that."),
    }),
    topic("We shut the line.", {
      matron("You did. I saw the needle drop, and it was thoughtful of you. That line had been dry for an hour, dear. We were only rinsing it. The patient has had the full course."),
    }),
    topic("Does she know what's under this place?", {
      matron("She knows what her friend from the deep has told her. In forty years I've never met anyone so well informed about everything except the one thing."),
    }),
    { "Open that door.", {
      matron("No."),
    } },
  }),
  matron("Forty years on the wards, and I have never yet let anyone in before the doctor was ready. There's no need for this to be unpleasant."),
  deserter("There never is. I'm so very tired of hearing it."),
  { battle = "vt_e_matron" },
  t("She gets back to the chair by herself, and sits, and straightens the pen on the blotter. The little bell rolls off the desk. Nobody picks it up."),
  matron("Nineteen minutes. You've made up one. That was very nice work. Do wash your hands."),
  t("The doctor stands over her for a moment, then closes her eyes and sets her cap straight. There's nobody else left who'd know how it goes."),
  { set = "vt_matron_down" },
  deserter("Through the door. Come on, friend, it's only nineteen minutes!"),
}

-- ---------------------------------------------------------------- the reading room

-- The fade comes before the killing, as Q40 says, and this is all of that night the game shows until the finale.
S.vt_memory = {
  t("In the passage a lamp hangs on a chain, and its light has something in it. The nothics read her as she went by, and they don't waste anything."),
  { dark = true },
  t("A tall house in Adaphis, and rain. A girl stands behind a door where she's been told not to be, looking through the gap at the hinge."),
  t("Her mother is laying the table for two, with the good cups, and humming, because he's home."),
  t("He comes in with his coat on. He hasn't slept. He sets an old book down among the cups with great care, and he doesn't look at his wife. He looks at the wall."),
  t("'You're home,' her mother says, and she goes to take his coat."),
  { fade = true },
  { dark = false },
  t("The lamp swings on its chain, and it's only a lamp."),
}

S.vt_ring = {
  t("The floor of this room went long ago. A ring of boards runs round the wall, and in the middle the well drops straight to the mist. Out on the last island of floor, one lamp is burning."),
  t("There was a bridge. It has been taken up, very neatly, and stacked on the far side."),
  jezzara("Too wide to jump. I don't say that often. The ring gets closest at the north side, and that's all it does."),
}

S.vt_shout = {
  t("She doesn't turn round. Your voice goes out across the well, and doesn't get there."),
}

S.vt_scene_colette = {
  t("There's a desk on the island, and on the desk an old book, and it's whole. Doctor Colette has taken off her greys and folded them over the chair. Without them she's smaller than you remember."),
  t("She's standing in front of a man who stands with his back to her, facing nothing. His back is very straight. There's a general's coat on it, and not much else."),
  colette("{hero}. Good, you're in time. I took up the bridge a minute ago, I'm afraid. I find I want a witness, and I can't bear a rescue. Please don't try the gap."),
  { choice = {
    { "Get away from him. It isn't him.", {
      colette("It's all the him there is. I've done the reading."),
    } },
    { "You've got the pages. What's this for?", {
      colette("The pages were on the way. I'm a doctor, and I've come to see a patient. I've been meaning to for thirty years."),
    } },
    { "Say nothing.", {
      colette("Yes. That's what I wanted you for."),
    } },
  } },
  deserter("Doctor, don't. You wrote the paper on what's left in them. Whatever you've come to hear, it isn't in there to say."),
  colette("I know what's in there. Hush, now. This is a private consultation."),
  t("She turns away from you, and she's nine years old. You couldn't say how you know."),
  colette("Father. It's Colette. I was behind the door."),
  t("Nothing. Then the straight back moves a little, as if someone a long way off had pulled a thread."),
  father("Has someone seen to the horse?"),
  colette("The horse is dead, Father. So is she. So are you, I think. I have a kingdom, and I took it to stand in this room. You needn't love me. I've read what you are."),
  colette("Say it. One word of it. Say you know what you did, and I'll close this book and go home. I mean that. I've thirty years of it, and I would put it down."),
  t("For the first time he turns round. It takes a long while. What's left of his eyes finds her, and stays."),
  father("Colette."),
  colette("Yes. Yes, I'm here. Go on."),
  t("His mouth opens. It goes on opening."),
  { fade = true },
  { dark = true },
  t("The lamp goes out. Nobody will ever know what he was going to tell her."),
  cleric("She's gone. I felt her go by me. {hero}, she was still listening."),
  t("In the dark, someone gets up. Someone in a plain dress, and it takes them a while to work out how."),
  { dark = false },
  t("The lamp comes on again by itself, and it's a colour you have no word for. The old book turns its own last page."),
  changed("Everyone dreams."),
  t("It's her voice. It's very kind. It comes from the island, and the well, and the back of your own teeth."),
  changed("They simply haven't been asked properly."),
  t("Down in the mist, every chain in the cavern goes slack at once."),
  { big = "THE LID COMES OFF" },
  { set = "vt_too_late" },
  { fade = true },
  { warp = { "vt_vault_7", 3, 8, 2 } },
  jezzara("Move! The road's still up, it goes east, back to the rock! MOVE!"),
}

-- ---------------------------------------------------------------- the falling road

S.vt_scene_qarhuul = {
  t("Ahead of you the mist has begun to climb. It comes up the chains in no hurry at all, and then it isn't mist."),
  t("It's an arm. You know it's an arm the way you know a hill is a hill, by how long it takes to get past. There are others behind it. Far down, something has opened."),
  cleric("She doesn't look away. Oh, I wish she'd look away."),
  owlin("Qarhuul. It's in the oldest margin of the oldest book in Owlundia. It only says: do not."),
  jezzara("Can it be killed?"),
  owlin("No."),
  jezzara("Right, then."),
  { big = "QARHUUL" },
  { battle = "vt_e_qarhuul" },
  t("Nothing you did touched it. You find that you're on your feet, all of you, and that you've been set down, the way you'd set down something you hadn't finished with."),
  t("It's looking at you. All of that, all the way up from the bottom of the world, and it looks at you and nobody else, for about as long as it takes to breathe in."),
  t("Nan used to look at a loaf like that. She'd lift the cloth to see if it had risen."),
  t("Then the cloth comes down. It goes on past you, up, towards the rest of the world."),
  { set = "vt_q_done" },
  deserter("Run! Friend, what are you standing there for? RUN!"),
}

S.vt_lose_sister = {
  t("A lantern has torn loose and swung in against the road, and it's holding there, on one chain. Someone inside it is calling out, in a polite voice. Then several people are."),
  cleric("Those are the blind ones. There are people alive in there, {hero}. No. I can hear them going."),
  cleric("Go on. I'll sit up with them. I generally do. You've done some good, {hero}, and I don't say that to many people."),
  t("She steps across. The chain lets go. The whole lit lantern swings away from the road with her in the doorway, walking in towards the voices, not hurrying. She doesn't look back. She doesn't look away."),
  { leave = "cleric" },
  { set = "vt_lost_sister" },
}

S.vt_lose_jezzara = {
  jezzara("Did she just... She owes me nothing. I owe her nothing. I have never once in my life gone back for anyone."),
  t("She looks down the long drop after the falling light. She looks at you. Her tail does something you've never seen it do."),
  jezzara("Tell no one about this. And don't look like that, I land on my feet. It's a rule."),
  t("She goes over the edge without a sound, from chain to chain to chain, down into the dark, getting smaller, until you can't tell her from the lanterns falling past."),
  { leave = "jezzara" },
  { set = "vt_lost_jezzara" },
}

S.vt_lose_doctor = {
  t("The road bucks. Ahead of you the boards start to go, one after another, coming towards you very fast."),
  owlin("I can carry one! Only one! Give me your hand!"),
  t("Wings open in the dark. The scholar has the doctor by the collar, and the road goes out from under all three of you. You've got one hand on a chain. They've got the air."),
  deserter("Friend! {hero}! Take my hand! Take my..."),
  t("You both reach. You've heard about this in stories. Your fingers are about a spoon's length apart."),
  t("Something small and hard hits you in the chest, thrown. You catch it without thinking. It's a spoon."),
  deserter("It's a delicate instrument! I'll want that back, do you hear me? I'll want it BACK!"),
  t("The wind takes the rest. The wings beat upward, hauling, and the dark closes behind them."),
  { leave = "owlin" },
  { leave = "deserter" },
  { set = "vt_lost_doctor" },
}

S.vt_alone = {
  t("You turn to say something. There's nobody behind you."),
}

S.vt_the_end = {
  t("The road ends. It doesn't break. It simply isn't there any more, and ahead of you there's only the dark, and the lanterns going by as they fall, each with its light still on."),
  { choice = {
    { "Hold on.", {
      t("You hold on. The chain lets go of you."),
    } },
    { "Let go.", {
      t("You let go. It's the first thing you've decided all day."),
    } },
  } },
  { leave = "deserter" }, { leave = "cleric" }, { leave = "owlin" }, { leave = "jezzara" },
  { dark = true },
  t("A long way above you, at Scythebreak, a crack you walked past every day of your life gets wider, and goes on getting wider. The Pandemic Wall, which has stood since before you can remember, lies down."),
  t("In every bed in every town in Embia, at the same moment, the sleepers open their eyes. Nobody is screaming. It's much quieter than that."),
  t("In a ward in Scythebreak, an old woman's hands stop kneading."),
  t("On a shelf of black rock, a small man on a folding chair counts the lanterns as they go out. He reaches the end. He rules a line under it. The numbers have all been very good."),
  { big = "THE WORLD BREAKS" },
  t("You fall. It goes on for a long time."),
  t("There is a place people go, just before they wake."),
  t("You have heard all about it."),
  { fade = true },
  { set = "ruined" },
  { site = "scythebreak_r" },
}

return R
