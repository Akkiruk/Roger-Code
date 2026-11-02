-- games/blightmare/regions/finale.lua
-- The end of the game. The Vault again, with the lid off. The eye reads the father to the last page, Colette asks what he was
-- going to say, and the player answers. Qarhuul can't die. The hero's parasite is the door it wants, so the hero goes in by the
-- first dream and shuts it from inside, and stays. Draft for the author: Colette's lines are hers to rewrite, and they stand on
-- three things planted earlier: her promise to close the book, "Thank you for saying so. Nobody does", and "asked properly".
--
-- What the choice does:
--   fn_lie    she closes the Tome as she promised, the blood stops feeding it, and Qarhuul is the lesser fight.
--   fn_truth  the Tome stays open and Qarhuul is the harder fight, but she pays truth with truth: a sleeper can be called back.
-- With fn_truth and all six side flags that is what happens, and the hero wakes. fn_truth alone: they ask, and it isn't enough.
--
-- The ending warps to fn_vault_1 before the last pages, so the return after THE END lands at the tent, and a sleeping ending can
-- still be turned into the waking one there, if the ledger is cleared later. Thrupp is dead (ruin_south), so the stores are his
-- honesty tin.

local say = require("games.blightmare.say")

local t, ask, topic, line, person = say.t, say.ask, say.topic, say.line, say.person

local R = {
  id = "finale", prefix = "fn_",
  entry = { flags = { "ruined", "rn_done", "rd_done" }, map = "fn_vault_1", x = 3, y = 3 },
  exit = "fn_ended",
  exports = {
    "ruined", "rn_done", "rd_done", "heard_tobin", "lied_to_nan", "px_gave_blood", "px_refused_blood",
    "wm_peewit_lives", "wm_took", "rd_asked_jez", "rd_zal_kept",
  },
  -- The gnomes' hook lands on the Abyss tile, where abyss_r comes first in the list, so the way back in is ruin_deep's stair.
  -- This site is what the region check needs to see a way back, and it does no harm.
  sites = { fn_vault = { x = 60, y = 27, map = "fn_vault_1", mx = 3, my = 3, dir = 2, name = "THE NIGHTMARE VAULT", kind = "dungeon", when = "fn_arrived" } },
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
local hero = line("hero")
local changed = line("colette_changed")
local margin = person("vt_margin", "MARGIN")
local nan = person("villager", "NAN")
local itsNan = person("qarhuul", "NAN")
local uncle = person("fn_uncle", "A DEAD UNCLE")
local keeper = person("fn_ansa", "THE KEEPER")

local SIX = { "side_frogs", "side_revolution", "side_barnabas", "side_lovers", "side_zalabarula", "side_chylbad" }
local SECRET = { "side_frogs", "side_revolution", "side_barnabas", "side_lovers", "side_zalabarula", "side_chylbad", "fn_truth" }
local STILL_OPEN = { "side_frogs", "side_barnabas", "side_lovers", "fn_truth" }

--- One list from several, in order.
local function chain(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, step in ipairs(list) do out[#out + 1] = step end
  end
  return out
end

-- ---------------------------------------------------------------- looks and pictures

R.looks.fn_uncle = {
  kind = "human", tall = 0.92, build = "thin", cut = "coat", coat = "tie", trim = "line", skin = "line", hat = "bowler", hatInk = "panel",
  eyes = "tired", mouth = "line", beard = "whiskers", beardInk = "line", back = "accent",
}
R.looks.fn_ansa = {
  kind = "human", tall = 0.96, build = "broad", cut = "coat", coat = "blueTint", trim = "tie", skin = "warn", hair = "wild", hairInk = "text",
  eyes = "narrow", mouth = "open", carry = "lantern", back = "bg",
}
R.names = { ["A DEAD UNCLE"] = "fn_uncle", ["THE KEEPER"] = "fn_ansa" }

R.art = {
  fn_arm = "One grey arm thick as a tree, rearing out of the dark on its own, ringed with shut eyes.",
  fn_ladder = "A big brass hook on a cable going up into the dark, with a speaking tube tied to it.",
  fn_tin = "A folding desk with a tin on it, and a note weighted with a dead lamp, Clinic crates stacked behind.",
  fn_lamp = "A lamp on a chain, its light with something moving in it, like a face under water.",
  fn_sleepers = "A rank of people in nightshirts, shoulder to shoulder, standing asleep, all facing one way.",
  fn_chair = "A plain high-backed chair, set very square to the edge of the boards.",
  fn_cot = "A lantern door laid on two casks, a thin Clinic blanket on it, tucked in with hospital corners.",
  fn_lamp_r = "A ship's lamp on a brass stand with a red glass.",
  fn_lamp_g = "A ship's lamp on a brass stand with a green glass.",
  fn_lamp_w = "A ship's lamp on a brass stand with a clear glass.",
  fn_crate = "A wooden crate about the size for a baby, NO TROUBLE lettered on its lid, the lid not quite shut.",
}

-- ---------------------------------------------------------------- foes

R.abilities = {
  fn_reach = { name = "REACH", power = 120 },
  fn_latch = { name = "FEELS FOR THE LATCH", mp = 5, power = 70, magic = true, element = "mind", status = "tadpole", chance = 40 },
  fn_talk = { name = "TALKS IN ITS SLEEP", mp = 6, power = 60, magic = true, target = "all", element = "mind", status = "sleep", chance = 35 },
  fn_gaze = { name = "READS YOU", mp = 5, power = 90, magic = true, element = "mind" },
  fn_cut = { name = "PAPER CUT", power = 70 },
  fn_dust = { name = "LAMP DUST", power = 70, status = "blind", chance = 50 },
  fn_hand = { name = "A FIRM HAND", power = 115 },

  fn_bedside = { name = "BEDSIDE MANNER", power = 125 },
  fn_notreat = { name = "DO NOT TREAT", mp = 5, status = "silence", chance = 65 },
  fn_sleeping = { name = "ARE YOU SLEEPING", mp = 6, power = 95, magic = true, target = "all", element = "mind", status = "nightmare", chance = 45 },
  fn_dose = { name = "THE DOSE", mp = 6, power = 130, magic = true, element = "blood", status = "doom", chance = 30 },
  fn_casks = { name = "FORTY CASKS", power = 200, magic = true, target = "all", element = "blood", windup = 34, warn = "THE RED LINE FILLS" },
  fn_column = { name = "SENDS FOR THE COLUMN", target = "summon" },

  fn_teeth = { name = "ALL YOUR TEETH", power = 160 },
  fn_colours = { name = "COLOURS", mp = 6, power = 100, magic = true, target = "all", element = "mind", status = "nightmare", chance = 50 },
  fn_asks = { name = "WHAT DID YOU DREAM", mp = 6, power = 110, magic = true, element = "mind", status = "thrall", chance = 40 },
  fn_falling = { name = "FALLING", power = 210, magic = true, target = "all", windup = 34, warn = "THE FLOOR IS NOT THERE" },
  fn_course = { name = "THE FULL COURSE", power = 235, magic = true, target = "all", element = "blood", windup = 34, warn = "THE BOOK TURNS A PAGE" },
  fn_arrives = { name = "ANOTHER ARM ARRIVES", target = "summon" },
}

R.foes = {
  fn_moth = { name = "LANTERN MOTH", tier = 42, shape = "quick", sprite = "vt_moth", family = "bug",
    abilities = { { "bite", 3 }, { "fn_dust", 2 } }, weak = { "fire" } },
  fn_pages = { name = "THE LAST PAGES", short = "PAGES", tier = 42, shape = "small", sprite = "vt_pages", family = "bug",
    abilities = { { "fn_cut", 3 }, { "hush_word", 1 } }, weak = { "fire" } },
  fn_nothic = { name = "HUNGRY NOTHIC", short = "NOTHIC", tier = 43, shape = "caster", sprite = "nothic", family = "stalker",
    abilities = { { "fn_gaze", 3 }, { "claw", 2 } }, weak = { "holy" }, resist = { "mind" } },
  fn_orderly = { name = "TRANSFERRED", tier = 43, shape = "brute", sprite = "vt_reader", family = "staff",
    abilities = { { "fn_hand", 4 }, { "needle", 2 } }, immune = { "blind" }, weak = { "holy" } },
  fn_walker = { name = "SLEEPWALKER", tier = 44, shape = "tank", sprite = "blighted", family = "blighted",
    abilities = { { "claw", 3 }, { "fn_talk", 1 } }, weak = { "holy" } },
  fn_arm = { name = "SMALL ARM", tier = 44, shape = "brute", sprite = "fn_arm", family = "boss",
    abilities = { { "fn_reach", 3 }, { "fn_latch", 2 } }, resist = { "mind" } },

  fn_colette = {
    name = "COLETTE", tier = 44, shape = "caster", sprite = "colette_changed", family = "boss", size = 2, steal = false,
    weak = { "holy" }, resist = { "mind", "blood" },
    boss = { hpx = 0.88, phases = {
      { at = 100, moves = { { "fn_bedside", 5 }, { "fn_notreat", 2 }, { "fn_dose", 2 } }, every = 5, big = "fn_casks" },
      { at = 66, moves = { { "fn_bedside", 4 }, { "fn_sleeping", 3 }, { "fn_dose", 2 } }, every = 4, big = "fn_casks", say = "SHE ROLLS UP HER SLEEVES", summon = "fn_orderly", call = "fn_column" },
      { at = 33, moves = { { "fn_bedside", 4 }, { "fn_sleeping", 3 } }, every = 3, big = "fn_casks", say = "SHE IS VERY KIND ABOUT IT", speedUp = 1 },
    } },
  },
  -- The book is shut. What it was being fed has stopped arriving.
  fn_qarhuul_eased = {
    name = "QARHUUL", tier = 45, shape = "brute", sprite = "qarhuul", family = "boss", size = 3, steal = false, atkx = 0.75, immune = { "poison" },
    boss = { hpx = 0.6, phases = {
      { at = 100, moves = { { "fn_teeth", 4 }, { "fn_colours", 2 } }, every = 5, big = "fn_falling" },
      { at = 60, moves = { { "fn_teeth", 4 }, { "fn_colours", 2 }, { "fn_asks", 2 } }, every = 4, big = "fn_falling", say = "IT HAS NOTHING TO EAT", summon = "fn_arm", call = "fn_arrives" },
      { at = 25, moves = { { "fn_teeth", 3 }, { "fn_asks", 3 } }, every = 4, big = "fn_falling", say = "IT REMEMBERS WHERE IT WAS GOING", speedUp = 1 },
    } },
  },
  -- The book is open. It has everything she ever read, and her hands.
  fn_qarhuul = {
    name = "QARHUUL", tier = 45, shape = "brute", sprite = "qarhuul", family = "boss", size = 3, steal = false, atkx = 0.85, immune = { "poison" },
    boss = { hpx = 0.66, phases = {
      { at = 100, moves = { { "fn_teeth", 4 }, { "fn_colours", 2 } }, every = 5, big = "fn_falling" },
      { at = 70, moves = { { "fn_teeth", 3 }, { "fn_colours", 2 }, { "fn_asks", 2 } }, every = 4, big = "fn_course", say = "THE BOOK IS STILL OPEN", summon = "fn_arm", call = "fn_arrives" },
      { at = 40, moves = { { "fn_teeth", 4 }, { "fn_dose", 2 }, { "fn_asks", 2 } }, every = 3, big = "fn_falling", say = "IT HAS HER HANDS", speedUp = 1 },
      { at = 15, moves = { { "fn_teeth", 3 }, { "fn_colours", 3 } }, every = 3, big = "fn_course", say = "THERE IS NO NEED TO BE AFRAID" },
    } },
  },
}

R.encounters = {
  fn_e_moths = { foes = { "fn_moth", "fn_moth" }, flee = true, bg = "chain" },
  fn_e_nothic = { foes = { "fn_nothic", "fn_moth" }, flee = true, bg = "chain" },
  fn_e_column = { foes = { "fn_orderly", "fn_orderly" }, flee = true, bg = "chain" },
  fn_e_pages = { foes = { "fn_pages", "fn_pages", "fn_pages" }, flee = true, bg = "ruin" },
  fn_e_stacks = { foes = { "fn_nothic", "fn_orderly" }, flee = true, bg = "ruin" },
  fn_e_walkers = { foes = { "fn_walker", "fn_walker" }, flee = true, bg = "dream" },
  fn_e_arm = { foes = { "fn_arm", "fn_walker" }, flee = true, bg = "dream" },
  fn_e_colette = { foes = { "fn_colette" }, flee = false, bg = "ruin", boss = true },
  fn_e_qarhuul_truth = { foes = { "fn_qarhuul" }, flee = false, bg = "dream", boss = true },
  fn_e_qarhuul_lie = { foes = { "fn_qarhuul_eased" }, flee = false, bg = "dream", boss = true },
}

R.shops.fn_stores = { tier = 7 }

-- ---------------------------------------------------------------- goals

R.goals = {
  { done = "fn_arrived", text = "Take the stair to the Vault", map = "rd_nest", x = 18, y = 11, when = "rd_done" },
  { done = "fn_stacks", text = "Cross the slack roads", map = "fn_vault_3", x = 14, y = 16, when = "fn_arrived" },
  { done = "fn_read_him", text = "Hold the eye to the lamps", map = "fn_vault_3", x = 2, y = 8, when = "fn_arrived" },
  { done = "fn_colette_down", text = "Cross the bridge to her", map = "fn_vault_4", x = 11, y = 10, when = "fn_arrived" },
  { done = "fn_q_down", text = "Go down to the open lid", map = "fn_vault_5", x = 19, y = 8, when = "fn_arrived" },
  { done = "fn_asleep", text = "Say goodbye, then lie down", map = "fn_vault_5", x = 24, y = 8, when = "fn_arrived" },
  { done = "fn_ended", text = "Shut the door", map = "fn_dream_1", x = 6, y = 11, when = "fn_arrived" },
}

-- ---------------------------------------------------------------- maps

-- The shelf of black rock, with the south half of it gone. The dead clerk's tent and his honesty tin, the gnomes' hook, and the road on.
R.maps.fn_vault_1 = {
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
    "#.........~~~~~~~~~~~~~#",
    "#.........~~~~~~~~~~~~~#",
    "#.#####...~~~~~~~~~~~~~#",
    "#.........~~~~~~~~~~~~~#",
    "#.........~~~~~~~~~~~~~#",
    "#.........~~~~~~~~~~~~~#",
    "########################",
  },
  npcs = {
    { id = "fn_tin", x = 6, y = 6, sprite = "fn_tin", script = "fn_talk_stores" },
    { id = "fn_board", x = 9, y = 9, sprite = "vt_sign", script = "fn_read_board" },
    { id = "fn_ladder", x = 2, y = 2, sprite = "fn_ladder", script = "fn_way_up", when = "fn_arrived" },
  },
  steps = {
    { x = 3, y = 3, script = "fn_arrive", unless = "fn_arrived" },
  },
  chests = {
    { id = "c1", x = 9, y = 14, give = "xpotion", n = 3 },
    { id = "c2", x = 2, y = 14, give = "elixir", n = 1 },
  },
  foes = {
    { id = "f1", x = 15, y = 9, enc = "fn_e_moths", sprite = "vt_moth" },
  },
  exits = {
    { x = 20, y = 6, map = "fn_vault_2", mx = 3, my = 11, dir = 2 },
  },
}

-- The same lanterns, on chains that have gone slack. They swing. Margin keeps the only quiet floor left.
R.maps.fn_vault_2 = {
  name = "THE SLACK ROADS", theme = "chain",
  rows = {
    "##########################",
    "#~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~hhhhh~~~~~~~~~hhhhh~~~#",
    "#~~h...h~~~~~~~~~h...h~~~#",
    "#~~h...+.........+...h~~~#",
    "#~~h...h~~~~.~~~~h...h~~~#",
    "#~~hh+hh~~~~.~~~~hh+hh~~~#",
    "#~~~~.~~~~~~.~~~~~~.~~~~~#",
    "#hhhh+hh~~~~.~~~~~~.~~~~~#",
    "#h.....h~~hh+hh~~hh+hhh~~#",
    "#h.....+..+...+..+....h~~#",
    "#h>....h~~h...h~~h..>.h~~#",
    "#hhhhhhh~~hhhhh~~hhhhhh~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~#",
    "##########################",
  },
  npcs = {
    { id = "vt_margin", x = 12, y = 12, sprite = "nothic", script = "fn_talk_margin" },
  },
  chests = {
    { id = "c1", x = 5, y = 4, give = "hiether", n = 3 },
    { id = "c2", x = 21, y = 6, give = "grief_coat" },
    { id = "c3", x = 14, y = 12, give = "panacea", n = 2 },
  },
  foes = {
    { id = "f1", x = 9, y = 11, enc = "fn_e_column", sprite = "vt_reader" },
    { id = "f2", x = 13, y = 8, enc = "fn_e_nothic", sprite = "nothic" },
    { id = "f3", x = 15, y = 5, enc = "fn_e_moths", sprite = "vt_moth" },
    { id = "f4", x = 17, y = 11, enc = "fn_e_column", sprite = "vt_reader" },
    { id = "f5", x = 20, y = 8, enc = "fn_e_moths", sprite = "vt_moth" },
  },
  exits = {
    { x = 3, y = 12, map = "fn_vault_1", mx = 20, my = 7, dir = 3 },
    { x = 21, y = 12, map = "fn_vault_3", mx = 14, my = 17, dir = 1 },
  },
}

-- The great lantern on its side. Three lamps still burn, and each is a page of him. When all three have been read the way north opens.
R.maps.fn_vault_3 = {
  name = "THE LONG STACKS", theme = "library", savepoint = true,
  rows = {
    "#############>##############",
    "#hhhhhhhhhhhh.hhhhhhhhhhhhh#",
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
    { id = "fn_lamp_a", x = 2, y = 7, sprite = "fn_lamp", script = "fn_lamp_stable" },
    { id = "fn_lamp_b", x = 27, y = 10, sprite = "fn_lamp", script = "fn_lamp_table" },
    { id = "fn_lamp_c", x = 17, y = 13, sprite = "fn_lamp", script = "fn_lamp_vault" },
    { id = "fn_shut_way", x = 14, y = 3, sprite = "vt_gate", script = "fn_read_shut", unless = "fn_read_him" },
  },
  steps = {
    { x = 14, y = 16, script = "fn_stacks_in", unless = "fn_stacks" },
  },
  chests = {
    { id = "c1", x = 2, y = 13, give = "raven_vest" },
    { id = "c2", x = 27, y = 5, give = "xpotion", n = 2 },
    { id = "c3", x = 22, y = 13, give = "might_ring" },
  },
  foes = {
    { id = "f1", x = 7, y = 11, enc = "fn_e_pages", sprite = "vt_pages" },
    { id = "f2", x = 12, y = 8, enc = "fn_e_stacks", sprite = "nothic" },
    { id = "f3", x = 22, y = 8, enc = "fn_e_pages", sprite = "vt_pages" },
    { id = "f4", x = 17, y = 5, enc = "fn_e_column", sprite = "vt_reader" },
    { id = "f5", x = 27, y = 13, enc = "fn_e_stacks", sprite = "nothic" },
  },
  exits = {
    { x = 14, y = 18, map = "fn_vault_2", mx = 21, my = 11, dir = 3 },
    { x = 14, y = 1, map = "fn_vault_4", mx = 11, my = 15, dir = 1, when = "fn_read_him" },
  },
}

-- The ring and the island, and this time she has put the bridge back. A stair of chain opens in the island when she's done.
R.maps.fn_vault_4 = {
  name = "THE READING ROOM", theme = "library",
  rows = {
    "#####################",
    "#...................#",
    "#.~~~~~~~~~~~~~~~~~.#",
    "#.~~~~~~~~~~~~~~~~~.#",
    "#.~~~~~.......~~~~~.#",
    "#.~~~~~.......~~~~~.#",
    "#.~~~~~.......~~~~~.#",
    "#.~~~~~.>.....~~~~~.#",
    "#.~~~~~.......~~~~~.#",
    "#.~~~~~~~~.~~~~~~~~.#",
    "#.~~~~~~~~.~~~~~~~~.#",
    "#...................#",
    "##########+##########",
    "#hhhhhhhh...hhhhhhhh#",
    "#hhhhhhhh...hhhhhhhh#",
    "##########>##########",
  },
  npcs = {
    { id = "colette_changed", x = 11, y = 7, sprite = "blighted", script = "fn_scene_colette", unless = "fn_colette_down" },
    { id = "father", x = 11, y = 5, sprite = "blighted", script = "fn_read_father" },
    { id = "fn_chair", x = 13, y = 8, sprite = "fn_chair", script = "fn_read_chair" },
  },
  steps = {
    { x = 11, y = 14, script = "fn_room_in", once = true },
    { x = 11, y = 10, script = "fn_scene_colette", unless = "fn_colette_down" },
  },
  chests = {
    { id = "c1", x = 10, y = 15, give = "elixir", n = 1 },
    { id = "c2", x = 12, y = 15, give = "hiether", n = 2 },
  },
  exits = {
    { x = 11, y = 16, map = "fn_vault_3", mx = 14, my = 3, dir = 3 },
    { x = 9, y = 8, map = "fn_vault_5", mx = 5, my = 8, dir = 2, when = "fn_colette_down" },
  },
}

-- What used to be the bottom. A road of fallen chain out across the dark, split round the ones standing in it, to the last dry
-- ground. That is where Qarhuul turns its attention, and where the five of them make up a bed.
R.maps.fn_vault_5 = {
  name = "THE OPEN LID", theme = "chain",
  rows = {
    "############################",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~.......~~~~~~~~~#",
    "#~hhhhh~~~~.~~~~~.~~~~~~~~~#",
    "#~h...h~~~~.~~~~~.~.......~#",
    "#~h...h~~~~.~~~~~.~.......~#",
    "#~h...h~~~~.~~~~~.~.......~#",
    "#~h...+...................~#",
    "#~h.>.h~~~~.~~~~~.~.......~#",
    "#~hhhhh~~~~.~~~~~.~.......~#",
    "#~~~~~~~~~~.~~~~~.~.......~#",
    "#~~~~~~~~~~.......~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~~~~~~~#",
    "############################",
  },
  npcs = {
    { id = "fn_sleepers", x = 15, y = 8, sprite = "fn_sleepers", script = "fn_read_sleepers" },
    { id = "qarhuul", x = 24, y = 8, sprite = "qarhuul", script = "fn_scene_qarhuul", unless = "fn_q_down" },
    { id = "deserter", x = 22, y = 6, sprite = "doctor", script = "fn_bye_doctor", when = "fn_q_down", unless = "fn_asleep" },
    { id = "cleric", x = 22, y = 10, sprite = "villager", script = "fn_bye_sister", when = "fn_q_down", unless = "fn_asleep" },
    { id = "owlin", x = 25, y = 6, sprite = "villager", script = "fn_bye_scholar", when = "fn_q_down", unless = "fn_asleep" },
    { id = "jezzara", x = 25, y = 10, sprite = "villager", script = "fn_bye_jezzara", when = "fn_q_down", unless = "fn_asleep" },
    { id = "asphodel", x = 21, y = 8, sprite = "villager", script = "fn_bye_asphodel", when = "fn_q_down", unless = "fn_asleep" },
    { id = "fn_cot", x = 25, y = 8, sprite = "fn_cot", script = "fn_lie_down", when = "fn_q_down", unless = "fn_asleep" },
  },
  steps = {
    { x = 5, y = 8, script = "fn_lid_in", once = true },
    { x = 19, y = 8, script = "fn_scene_qarhuul", unless = "fn_q_down" },
  },
  chests = {
    { id = "c1", x = 4, y = 5, give = "tent", n = 1 },
    { id = "c2", x = 15, y = 3, give = "xpotion", n = 2 },
    { id = "c3", x = 15, y = 12, give = "feather", n = 2 },
  },
  foes = {
    { id = "f1", x = 9, y = 8, enc = "fn_e_walkers", sprite = "blighted" },
    { id = "f2", x = 12, y = 5, enc = "fn_e_arm", sprite = "fn_arm" },
    { id = "f3", x = 12, y = 11, enc = "fn_e_walkers", sprite = "blighted" },
    { id = "f4", x = 18, y = 5, enc = "fn_e_arm", sprite = "fn_arm" },
    { id = "f5", x = 18, y = 11, enc = "fn_e_walkers", sprite = "blighted" },
  },
  exits = {
    { x = 5, y = 9, map = "fn_vault_4", mx = 8, my = 8, dir = 4 },
  },
}

-- The first dream. Three rooms of other people's nightmares, told over breakfast, and a dead uncle. Then the one room nobody ever
-- described. No fights: the hero is alone, and nothing here wants to fight.
R.maps.fn_dream_1 = {
  name = "THE FIRST DREAM", theme = "dream",
  rows = {
    "##########################",
    "#h.....h.....h.....h....h#",
    "#h.....h.....h.....h....h#",
    "#h.....h.....h.....h....h#",
    "#h.....+.....+.....+....h#",
    "#h.....h.....h.....h....h#",
    "#h.....h.....h.....h....h#",
    "#hhhhhhhhhhhhhhhhhhhh+hhh#",
    "#h......................h#",
    "#h......................h#",
    "#h......................h#",
    "#h......................h#",
    "#h......................h#",
    "#hhhhhhhhhhhhhhhhhhhhhhhh#",
    "##########################",
  },
  npcs = {
    { id = "fn_uncle", x = 22, y = 7, sprite = "villager", script = "fn_d_uncle", unless = "fn_uncle_gone" },
    { id = "fn_ansa", x = 13, y = 10, sprite = "villager", script = "fn_d_keeper" },
    { id = "fn_red", x = 19, y = 12, sprite = "fn_lamp_r", script = "fn_d_red" },
    { id = "fn_green", x = 15, y = 12, sprite = "fn_lamp_g", script = "fn_d_green" },
    { id = "fn_white", x = 11, y = 12, sprite = "fn_lamp_w", script = "fn_d_white" },
    { id = "fn_crate", x = 5, y = 11, sprite = "fn_crate", script = "fn_d_crate" },
  },
  steps = {
    { x = 9, y = 5, script = "fn_d_falling", once = true },
    { x = 15, y = 5, script = "fn_d_teeth", once = true },
    { x = 22, y = 9, script = "fn_d_ward", once = true },
  },
}

-- ---------------------------------------------------------------- the last landing

S.fn_arrive = {
  t("The black shelf again. The rock is the same, and nothing else is. The few lanterns left hang on chains gone slack, and swing."),
  t("Where the mist lay there's a hole. It isn't dark. You keep wanting to call it a colour, and each time you start to, you find that you've looked away."),
  owlin("A year ago I said I'd give everything in there to be looking at it from further off. I'd like it noted that the offer was made in good faith."),
  t("The Clinic's tent is still up. There's no light in it now."),
  { set = "fn_arrived" },
}

-- What's still owing, from the back of the ledger the hero has carried since Scythebreak. It's how the player learns what the
-- secret ending wants.
local LEDGER = {
  { all = SIX, steps = {
    t("You turn to the back of the narrow column, to what's still owing. There's nothing. Not a line. He'd have liked to see that."),
  }, other = {
    t("You turn to the back of the narrow column, to what's still owing."),
    { when = "side_frogs", other = { t("'Hayford. A frog, a hat, and a Return not paid.'") } },
    { when = "side_revolution", other = { t("'Adaphis. The Ribbed District: one revolution, not brought to a close.'") } },
    { when = "side_barnabas", other = { t("'Sindal. The Barnabas matter. Nobody has told that man no.'") } },
    { when = "side_lovers", other = { t("'Touarch and Blackhold. Two young persons, one crown, no marriage on file.'") } },
    { when = "side_zalabarula", other = { t("'The Brain Sipper. Missing a very long time, and nobody has found him.'") } },
    { when = "side_chylbad", other = { t("'The Diamond Fang. One very large dragon, unsettled.'") } },
    { when = "fn_colette_down", steps = {
      t("The gnomes' hook is by the rock wall, if you want to settle up."),
    }, other = {
      t("Whatever's past that bridge, you'd want your accounts in order first. The gnomes' hook is by the rock wall, if you want to settle up."),
    } },
  } },
}

local COUNTER = {
  ask(t("The stores, the one cot, and the tin. Nobody's watching. That seems to have been the idea."), {
    { "See what's in the stores.", {
      { shop = "fn_stores" },
    } },
    { "Use the cot. (200 gold, in the tin)", {
      { inn = 200 },
      { save = true },
    } },
    topic("Read what's still owing.", LEDGER),
    { "Leave it.", {} },
  }),
}

S.fn_wake_late = chain({
  t("The narrow column. Every line is closed, but the one at the foot of the page, that you left open. It was irregular. He'd have known that."),
  { fade = true },
  { dark = true },
})

S.fn_talk_stores = chain({
  { when = "fn_ended", steps = {
    { when = "fn_woken", steps = {
      t("The narrow column. Every line closed. Seen to."),
    }, other = {
      { all = SECRET, steps = S.fn_wake_late, other = {
        -- Hayford, Sindal and the lovers can't be settled once the world is ruined, and the lie can't be taken back: don't promise.
        { all = STILL_OPEN, steps = {
          t("The narrow column. One line is open at the foot of the page, and it's yours. If the rest ever closes, come back here."),
        }, other = {
          t("The narrow column. One line is open at the foot of the page, and it's yours."),
        } },
      } },
    } },
  } },
  { when = "fn_stores_read", other = {
    t("The stores are stacked along the canvas in good order, each with its chit. There's a tin for the money, and a note in a small upright hand, weighted with a lamp that has burned out."),
    t("'GONE TO SCYTHEBREAK WITH NO. 412. STORES AS LISTED. PLEASE PAY FOR WHAT YOU TAKE. THERE IS ONE COT. A.T.'"),
    deserter("Two hundred and eleven days with you on his back, friend, and he stopped to do the inventory."),
    { set = "fn_stores_read" },
  } },
}, COUNTER)

S.fn_read_board = {
  t("VAULT COLUMN: STANDING ORDERS. 5. THERE IS NO NEED TO BE AFRAID."),
  t("Someone has added a line below that, in a very small neat hand. 6. THERE IS SOME NEED. MINUTED."),
}

S.fn_way_up = {
  t("A brass hook on a long cable, with a speaking tube tied to it. Nob's far shaft, down from the Abyss workings. It's the only way up from here. Whatever you owe up there that can still be paid, you could go and pay."),
  { choice = {
    { "Stay. We're finishing this.", {} },
    { "Ride the hook up.", {
      { world = { 60, 27 } },
    } },
  } },
}

-- ---------------------------------------------------------------- the slack roads

S.fn_talk_margin = {
  { when = "fn_margin_met", other = {
    t("Something small and grey sits with its knees up. Her left hand has gone since you saw her. She has tied a bookmark round the stump."),
    jezzara("Told you. They eat them to see what happens."),
    margin("Shh. It's the only quiet floor left. You're overdue, all of you, and I've stopped sending the letters."),
    { set = "fn_margin_met" },
  } },
  ask(margin("You've brought that eye home. Ask quickly, dear. I've a great deal left to not read."), {
    topic("Is there anything left of Colette?", {
      { when = "fn_colette_down", steps = {
        margin("Not now, dear. It has stopped listening. I've marked the entry closed."),
      }, other = {
        margin("A very little, that stopped where it stopped, behind a door. It has been listening for a year. It's holding the whole poor thing up."),
      } },
    }),
    topic("My stuck pages. What did you see?", {
      margin("Reference only. Not to be taken out. You know what you're carrying now, or you think so. You've been told it's a thing, dear. It isn't. It's a place. Mind how you go in."),
    }),
    { "We're going on.", {} },
  }),
}

-- ---------------------------------------------------------------- the long stacks

S.fn_stacks_in = {
  t("The great lantern has come to rest on its side. Most of the lamps are out. Three aren't, and each has something in its light, like the one in the passage."),
  t("In your bag, in its cloth, the eye has begun to turn. It doesn't point down now. It points at the lamps, one after another."),
  owlin("Hold it to the light, and we'll see what he saw. I want to read this. I know what that makes me."),
  { set = "fn_stacks" },
}

S.fn_read_shut = {
  t("The door isn't locked. The eye drags at your hand, back towards the lamps. It hasn't finished."),
}

local NOT_YET = t("It won't catch. There's an order to these, and you've read it, in a strong black hand.")

local LAMPS = { "fn_mem_a", "fn_mem_b", "fn_mem_c" }

-- The last of him. The fade comes before the killing, as it did for her (Q40): all the eye shows is the hall afterwards.
local HINGE = {
  t("The eye stops turning. All three lamps come up together, and you know this house. You've stood behind that door."),
  { dark = true },
  t("Rain. The good cups. He comes in with his coat on, and sets the old book among them, and looks at the wall. From in here, the wall is covered in colours."),
  t("'You're home,' someone says."),
  { fade = true },
  t("After. He's in the hall, drawing on his gloves, a finger at a time. He isn't out of breath."),
  t("He goes by a door. There's a gap at the hinge, and an eye in the gap, wet and nine years old. He sees it. It's all here: he knows whose it is. He stops."),
  t("You wait. All of you wait. You go through everything he has, looking for what comes next. What comes next is the rain, and how long the mare's been standing out in it."),
  t("'Has someone seen to the horse?' he says, to the house. And he goes out to her."),
  { dark = false },
  owlin("That's the whole of him. I've read every page there is. I kept waiting for the place where he refuses to be sorry. There isn't one. It never came up."),
  jezzara("I've killed for money since I could reach a knife. You always know what you've done. That's the whole trade. That's not a monster. That's a man thinking about something else."),
  deserter("Thirty years, friend. A kingdom, the Book, every door in Embia, to hear one word. And he'd told her all he had to say when she was nine."),
  t("The eye has one page left. The reading room, from his side. A woman in a plain dress is saying 'Yes. Go on.' He turns. He's found the word for her, and behind the word there's a stable yard, and a bucket."),
  t("His mouth opens. The eye goes dark. It can't go further than he did."),
  { big = "HE WAS NEVER SORRY" },
  { set = "fn_read_him" },
  jezzara("Everyone's got a dead uncle who asks about the horse. I always thought that was just a thing people said."),
}

--- A lamp, and the page of him that's in it. Any order. The third brings on the last page.
local function lampOf(flag, pages)
  local steps = chain({
    t("You hold the eye up to the lamp. It looks, and the light goes in."),
    { dark = true },
  }, pages, {
    { set = flag },
    { all = LAMPS, steps = HINGE },
  })
  return {
    { when = flag, steps = {
      t("The lamp has gone out. It only had the one thing to say."),
    }, other = steps },
  }
end

S.fn_lamp_stable = lampOf("fn_mem_a", {
  t("A stable yard in Adaphis, and a grey mare. A tall man in a general's coat has his hand flat on her neck. You've seen that coat on a corpse. You've never seen that face on anyone. He's smiling."),
  t("He knows every leg she has: the feed, the farrier, what she cost. It's the eye, so you know it too. He has never wanted anything so simply."),
  t("A small girl is holding a bucket in both arms. She has been there for some time. He doesn't look round."),
  t("'Colette,' he says. 'See to the horse.'"),
  t("She runs. He doesn't see it. You do. It's the best part of her year."),
  { dark = false },
  deserter("She told me once she could shoe a horse. I took it for a joke. It's the only one I ever thought she'd made."),
})

S.fn_lamp_table = lampOf("fn_mem_b", {
  t("A long table, and a marriage settlement. He reads it through twice, with the lawyer waiting. Lands. A name. A seat at the King's table. One grey mare, from her father's stud."),
  t("A young woman across the table is trying to catch his eye. He turns the page."),
  t("You go looking for what he thinks of her. You go through all of it. There's the sum, and the line he signs on."),
  { dark = false },
  asphodel("I've sat at that table. In Sindal, at least, they thank you for the meal."),
})

S.fn_lamp_vault = lampOf("fn_mem_c", {
  t("This place, when the chains were tight. He stands in a lantern with forty men behind him, and then with nine. He writes the rest in a book. Rank, number, replace."),
  t("Something no bigger than an eyelash goes in at his ear. He brushes at it, as you would at a fly. He takes an old book off its stand, reads one line, and shuts it."),
  t("He dreams, after that. You can see them. Colours. Falling. All your teeth. He looks at them as he'd look at bad weather, and sends for the farrier."),
  { dark = false },
  owlin("Every sleeper in Embia has had those. They're his. The whole world has been having a dead man's bad nights, and he never even minded them."),
})

-- ---------------------------------------------------------------- the reading room

S.fn_room_in = {
  t("The ring of boards, the well, and the one lamp, in the colour you have no word for. And the bridge is back. It has been laid again, plank by plank, and swept."),
  jezzara("She's put the bridge back. I liked it better when she didn't want us."),
}

S.fn_read_chair = {
  t("A plain chair, squared to the edge of the boards, and kept dusted."),
}

S.fn_read_father = {
  { when = "fn_truth", steps = {
    t("He lies where he fell, in good order. His mouth is open. Nobody has closed it."),
  }, other = {
    { when = "fn_lie", steps = {
      t("He lies where he fell, in good order, with his mouth shut. You could almost believe he'd said something."),
    }, other = {
      t("He stands very straight, with his mouth open. It hasn't finished."),
    } },
  } },
}

local TRUTH = {
  hero("Nothing you wanted. He'd found your name, and behind it there was a stable yard and a bucket. He was going to tell you to see to the horse."),
  t("Nothing moves on the island. Then there's a small dry sound, and it takes you a moment to place it. She's laughing."),
  changed("Yes."),
  changed("Yes, that's him. That's the whole chart. I did so want to be wrong."),
  t("She looks at you, then. It's the tired face. Nothing has ever looked at you so kindly."),
  changed("Thank you for saying so. Nobody does."),
  changed("I said I'd close the book for one word of it, and he hasn't said one. So it stays open. I'm afraid that will cost you. I do keep my word."),
  changed("You told a patient the truth, so here's yours. It's in the pages I came for. A door like yours shuts from inside. And anyone shut in can be called back, if they're asked properly. By a great many, for a very long time."),
  changed("I never had the numbers."),
  t("She turns her head towards the man in the coat. It takes her a while. She looks at him the way a doctor looks at a chart she has finished with."),
  changed("I'm sorry. There. That's one of us."),
  changed("Mind the step."),
  t("She stops, and whatever held the general up stops with her. He goes down in good order, with his mouth open. The doctor stands over him for a while, and doesn't close it."),
  t("On the desk the old book turns another page, all by itself."),
  { set = "fn_truth" },
}

local LIE = {
  hero("He was sorry. It's all through him, Colette. It was the last thing he had."),
  t("It's a very small lie. It only has to cross a very small room."),
  t("Her head comes up, a little at a time, and it's nine years old."),
  changed("He... was he?"),
  t("You nod. Behind you somebody breathes in, and doesn't let it out."),
  changed("Oh."),
  changed("There. That wasn't so hard, was it? I knew you could."),
  { when = "lied_to_nan", steps = {
    t("You never could lie. Nan told you so. She said that was the best you'd ever done it."),
  } },
  t("Her hand goes up to the desk and finds the old book by feel. She said she'd close it for one word of it, and she does keep her word. It shuts with a very small sound."),
  t("All the way down the well, something the size of the sky flinches."),
  changed("I'll go home now."),
  t("She lies down by his boots, with her head on her arm, like a child who's been told she needn't wait up any more. She's still smiling when the doctor gets there."),
  t("Whatever held the general up stops with her. He goes down in good order, and the doctor looks for a while, then reaches over and closes his mouth."),
  deserter("Never lie to a patient. First thing she taught us. They can always tell, she said."),
  deserter("I'll never know if she could. Thank you, friend. Don't ever ask me if it was right."),
  { set = "fn_lie" },
}

S.fn_scene_colette = {
  { when = "fn_met_changed", other = {
    t("The man stands where he stood, turned towards the desk, with his mouth open. It has been open for a year."),
    t("In front of him is what got up off the floor. It's tall now, and thin, and a good deal of it goes on down through the boards. It has its back to you and its head on one side. It's listening."),
    changed("{hero}. You've had a dreadful walk. Sit. I kept the chair."),
    { when = "px_refused_blood", steps = {
      changed("You said no. I did so like that."),
    } },
    { when = "px_gave_blood", steps = {
      changed("I still have your blood. I hold it up to the lamp. I've had nothing else to read."),
    } },
    ask(changed("Everyone dreams. I've asked them all. There's only you now. Are you sleeping?"), {
      { "He's never going to say it. We've read him.", {
        changed("Hush. He's just getting to it."),
      } },
      { "Colette. Stop this.", {
        changed("I've stopped, dear. It's only that nobody has told the rest of me."),
      } },
      { "Say nothing.", {
        changed("Yes. You were always such a good witness."),
      } },
    }),
    changed("There's no need to be afraid."),
    { set = "fn_met_changed" },
  } },
  { battle = "fn_e_colette" },
  t("It comes down all at once, the way a tent does when someone takes out the pole. What ran down through the boards lets go, and falls a long way."),
  t("What's left is on the floor, in a plain dress, with its head on one side. It isn't much. It's about the size of a girl behind a door."),
  t("She isn't looking at you. She's looking at his mouth."),
  changed("He's stopped. I've lost my place."),
  changed("You've his eye. I can smell it on you. You've read him to the end."),
  ask(changed("'Colette,' he said. And then? I was listening. What was he going to say?"), {
    topic("Doctor. What do I tell her?", {
      deserter("I've sat with two hundred and seven, and lied to every one. She never lied to a patient in her life. I couldn't say which of us did less harm. I can say which of us slept."),
    }),
    topic("Sister?", {
      cleric("She's asked. That's a patient's right. Some want it straight, and most want a hand. My lady doesn't mind which. They weigh the same on her side. It's this side they weigh on."),
    }),
    topic("Scholar?", {
      owlin("There's no such page. If you tell her he was sorry, yours will be the only copy in the world. I signed something once that wasn't so. I'd tell her the truth, and I can't swear that isn't vanity."),
    }),
    { "He was going to tell you to see to the horse.", TRUTH },
    { "He was going to say he was sorry.", LIE },
  }),
  t("The island has opened. A stair of chain goes down through it, into the place it all came from."),
  jezzara("That was the one who thought she was in charge. Let's go and see the other."),
  { set = "fn_colette_down" },
  { save = true },
}

-- ---------------------------------------------------------------- the open lid

S.fn_lid_in = {
  t("The stair comes out on what used to be the bottom of the world. A road of fallen chain runs out across the dark. There are people on it, a great many, all in their nightclothes."),
}

S.fn_read_sleepers = {
  t("Early risers, shoulder to shoulder, facing the hole. They've walked here from everywhere. They've got their eyes open. Nobody has told them they can sit."),
  deserter("Don't look for anyone you know, friend. I've tried it."),
}

S.fn_scene_qarhuul = {
  { when = "fn_met_q", other = {
    t("On the road it was climbing. Now it's already here, on every side and a long way up, and it only has to turn its attention."),
    t("It turns its attention."),
    t("It looks at you the way it did on the road. It lifts the cloth. It's very pleased with what it finds."),
    itsNan("Up, {hero}. The bell's gone."),
    deserter("Don't listen to it. Friend, that isn't..."),
    ask(itsNan("Well, then? What did you dream?"), {
      { "Nothing.", {
        t("It's pleased. You can feel that, the way you can feel a hill."),
        itsNan("That's my good one."),
      } },
      { "That's not your voice.", {
        itsNan("She has such a lot of it to spare."),
      } },
    }),
    jezzara("I know what the bird said last time. I'm asking again. Can it be killed?"),
    owlin("No."),
    jezzara("Right, then."),
    { big = "QARHUUL" },
    { set = "fn_met_q" },
  } },
  { when = "fn_truth", steps = {
    { battle = "fn_e_qarhuul_truth" },
  }, other = {
    { battle = "fn_e_qarhuul_lie" },
  } },
  t("The arms come down, one street at a time, and lie where they fall. In the oldest margin of the oldest book it only says: do not. You did."),
  t("Then a long way off one of them twitches, and lifts. Then the next."),
  jezzara("I want it known that I asked."),
  owlin("It can't die here, because it isn't here. All of this is an arm through a window, and the rest is on the far side, looking for a bigger way in."),
  t("One arm has come all the way across the dark. It stops a hand's width from your chest. It isn't attacking you. It's feeling, quite gently, for the latch."),
  t("Behind your left ear, the small hard place turns over. You've never felt that before. You've had it all your life."),
  owlin("I've been thinking about your mother's page. A piece of a thing is joined to the thing. Yours is a door, the only one never opened, and that arm has come to see if it has risen."),
  owlin("If it wakes, all of that comes through. If it's shut, from inside, all of it goes back: one sleeper to hold down the rest. Your eyes stopped halfway across, on the eleventh night. Something was on its way, that night, and it never got to you. It's been waiting ever since. It's the way in."),
  deserter("From inside. Then how do they get out?"),
  t("Nobody says anything. The sister's hand is on her black thread."),
  { when = "fn_truth", steps = {
    deserter("She said called back, if they're asked properly. Sitting up with people, friend. We've done nothing else for a year. And she'd never lie to a patient."),
  } },
  hero("It's all right. I've never had a dream. I'd like to see what all the fuss is about."),
  t("Nobody laughs. The doctor makes a sound that might have been going to be one."),
  asphodel("We can keep those off you for a while. Say what you have to say."),
  { set = "fn_q_down" },
  { save = true },
}

local BYES = { "fn_bye_a", "fn_bye_b", "fn_bye_c", "fn_bye_d", "fn_bye_e" }

S.fn_bye_doctor = {
  { when = "fn_bye_a", steps = {
    deserter("I'm counting drops, friend. Go on. I'll be right here."),
  }, other = {
    deserter("It'll have to be a draught, or that thing will eat the dream as it always has. I've done the sum four times. It's a good sum. I hate it."),
    deserter("Two hundred and seven, and I never said goodbye to one of them. It was against procedure. I find I don't know how it's done."),
    { choice = {
      { "You make very good soup.", {
        deserter("I do. I do make very good soup."),
      } },
      { "You came after me. In Scythebreak. You needn't have.", {
        deserter("I had a spoon and no plan. Best thing I ever did."),
      } },
    } },
    t("The doctor takes your hand, and turns it over, and looks for a while at the bent spoon in it, and folds your fingers shut."),
    deserter("Signed out for as long as there's anyone to feed. I wrote that. It's a delicate instrument. I'll want it back. Do you hear me? I'll want it BACK."),
    hero("I know. It's a very good spoon."),
    { set = "fn_bye_a" },
  } },
}

S.fn_bye_sister = {
  { when = "fn_bye_b", steps = {
    t("Her lips are moving. It's the first time you've ever seen her ask for anything."),
  }, other = {
    cleric("A thousand beds, and I've never once asked for one of them to live. I'm asking today. She won't like it. I've never sent in a bill before."),
    cleric("I've had one length put by. You may ask now. It's yours."),
    t("She ties the black thread round your wrist, in a plain knot, and tests it twice."),
    cleric("You've done some good, {hero}. That's twice I've said it. Don't let it go to your head."),
    { set = "fn_bye_b" },
  } },
}

S.fn_bye_scholar = {
  { when = "fn_bye_c", steps = {
    owlin("Notes. I mean it."),
  }, other = {
    owlin("The circlet has to come off. It has been keeping things out, and for once we want them in. Hold still."),
    t("The band comes away. It's cold, and then it isn't."),
    owlin("I'll write it all down, with my name on the first line this time. A million books, and none of them has this right. If you can, find out what it's like."),
    hero("I'll take notes."),
    owlin("Do. Do that."),
    { set = "fn_bye_c" },
  } },
}

S.fn_bye_jezzara = {
  { when = "fn_bye_d", steps = {
    jezzara("Go away. I'm watching the arms."),
  }, other = {
    jezzara("Don't. I've walked out of a lot of rooms, and I've never said anything on the way."),
    { choice = {
      { "You're the best, Jezzara.", {
        jezzara("I know. Everyone knows that."),
        t("She looks away. Her tail does the thing you've seen it do once before."),
        jezzara("Nobody's ever said it when it wasn't about killing someone."),
      } },
      { "Tell no one about this.", {
        t("She laughs before she can stop herself. It goes wrong about halfway."),
      } },
    } },
    { when = "rd_asked_jez", steps = {
      jezzara("You asked me something, in the Nest. If that lid comes up, I'll be right here. I won't charge."),
    } },
    jezzara("Land on your feet. It's a rule."),
    { set = "fn_bye_d" },
  } },
}

S.fn_bye_asphodel = {
  { when = "fn_bye_e", steps = {
    asphodel("I can hear it from here. It's a good one. Go on."),
  }, other = {
    asphodel("I've known you the shortest of any of them, so I'll be plain. Once you're under, your heart will want to stop. In Sindal we learn to hold a pulse, to keep the supply alive. It's the worst thing I know how to do. I'll hold it until it steadies, and I'll come back and check. I don't sleep."),
    hero("Thank you."),
    asphodel("Don't. In my country that's what they say instead of screaming. All right. Just the once."),
    { set = "fn_bye_e" },
  } },
}

local GO_UNDER = {
  t("You lie down. It's a very thin blanket, and somebody has done it properly."),
  t("Someone is holding your wrist. Someone is holding the thread. Behind them the arms are getting up."),
  deserter("Say ah."),
  t("It tastes of lavender."),
  deserter("There now. There's no need to... No. There's every need. I'll be right here, friend. I'm not going anywhere."),
  t("Everyone in Scythebreak goes somewhere at night. You have never been."),
  t("You go."),
  { fade = true },
  { dark = true },
  { solo = "hero" },
  { set = "fn_asleep" },
  { warp = { "fn_dream_1", 3, 3, 3 } },
  t("There is a place people go, just before they wake."),
  t("You have heard all about it."),
  { dark = false },
  t("You're standing in a room, and the room is wrong, and then you see that it's the colours. There are a great many, and nobody has told them where to go."),
  t("Something the size of a barn goes honking past behind the wall. That's the Hanley boy's goose. You'd know it anywhere, though you've only ever heard about it."),
  hero("None of this is mine."),
  t("It isn't. It's only what you were told. You've nothing of your own to dream with."),
}

S.fn_lie_down = {
  { all = BYES, steps = {
    { when = "fn_waited", steps = GO_UNDER, other = {
      ask(deserter("I've made up the bed. Are you ready, friend? Say no. Please."), {
        { "Yes.", GO_UNDER },
        { "A moment longer.", {
          deserter("Yes. Yes, take a moment. Take two."),
          { set = "fn_waited" },
        } },
      }),
    } },
  }, other = {
    t("A lantern door laid on two casks, with a Clinic blanket on it, and hospital corners. Not yet. There's someone you haven't said goodbye to."),
  } },
}

-- ---------------------------------------------------------------- the first dream

S.fn_d_falling = {
  t("The floor isn't there. You fall. You've been told about this. You fall, and your stomach goes, and you wake."),
  t("You go on falling. You don't wake. After a while you look about you. It's rather peaceful, when you've nowhere to be."),
  t("You land on your feet, in the room you were in. It's a rule."),
}

S.fn_d_teeth = {
  t("Something shifts in your mouth. You put your hand up, and all your teeth come away, one after another, and lie in your palm like small change."),
  t("There are thirty-two. You count them. Then you've nowhere to put them, so you put them back. People wake up screaming about that. You feel you were told it better than it was."),
}

S.fn_d_uncle = {
  t("A man is sitting on a kitchen chair, with his hat on his knee. He's dead, and he's your uncle, the way people are in dreams. You've no uncle, but you know him at once. Everybody does."),
  ask(uncle("Ah, there you are. Has someone seen to the horse?"), {
    { "I've no uncle, and we've no horse.", {
      uncle("Have you not? I do beg your pardon. I'm so sorry. I took you for someone else."),
      t("It's the only time anyone ever heard him say it. It wasn't to anyone, and it wasn't about anything."),
    } },
    { "Yes. It's been seen to.", {
      uncle("Ah. Good. Good. Then I can get on."),
      t("Nobody had told him. All those years, and all those beds, and nobody had thought to tell him."),
    } },
    { "The horse is dead.", {
      uncle("Dead? Is it?"),
      t("He thinks about that. It's the first new thought he has had in a long while, and you can see it doesn't suit him."),
      uncle("Then someone had better see to it."),
    } },
  }),
  t("He puts on his hat and goes out through the wall. In every bed in Embia, somebody turns over."),
  { set = "fn_uncle_gone" },
}

S.fn_d_ward = {
  t("The colours stop at the door. It's a ward, very small and very quiet. There's a window, and a small bed with a brass 9 on the rail. Somewhere someone is singing, and it's terrible."),
  t("Nobody ever told you about this room. This part isn't second hand."),
}

S.fn_d_keeper = {
  { when = "fn_keeper_met", other = {
    t("A big woman with a lamp-black thumb sits on the bed, singing a shanty, flat, with great conviction. She looks up the way you look up at a boat that's late."),
    keeper("There you are. Twenty-three years, and that's the lazy tack you took? Come here. Let me look. You've got my chin, you poor thing, and somebody's been feeding you."),
    hero("Are you...?"),
    keeper("I'm what you had. Six weeks of me. It ate everything else you ever got, but it never could get this down. I've been stuck in its throat all your life. That's my side of the family."),
    { set = "fn_keeper_met" },
  } },
  ask(keeper("Well? Speak up. I've a lamp to see to."), {
    topic("Why did you cut the page?", {
      keeper("I wasn't having them make a study of you. You got porridge instead, and I call that a good night's work."),
    }),
    topic("I had a good nan.", {
      keeper("I know. I can taste the bread. She asked you every morning, and got nothing, and went on asking. I'd like to shake that woman's hand."),
    }),
    { "How do I shut it?", {
      keeper("The way I shut up the Light every night of my life. Red for the reef. Green for the harbour. White for home. In that order. The boy forgets, and you're not to. Then the lid goes down, and you pin it."),
    } },
    { "I'm not ready.", {
      keeper("Nobody is. I've done the night shift with people who weren't. I'll be here."),
    } },
  }),
}

S.fn_d_red = {
  { when = "fn_lit_red", steps = {
    t("The red lamp is burning, for the reef."),
  }, other = {
    t("The wick takes at a touch. Red, out over the water. You were six weeks old, and you know how to do this."),
    { set = "fn_lit_red" },
  } },
}

S.fn_d_green = {
  { when = "fn_lit_green", steps = {
    t("The green lamp is burning, for the harbour."),
  }, other = {
    { when = "fn_lit_red", steps = {
      t("Green, low down, for the boats that are coming in anyway."),
      { set = "fn_lit_green" },
    }, other = {
      NOT_YET,
    } },
  } },
}

S.fn_d_white = {
  { when = "fn_lit_white", steps = {
    t("The white lamp is burning. Always finish on home."),
  }, other = {
    { when = "fn_lit_green", steps = {
      t("White. It's very plain, after all that. It goes a long way."),
      { set = "fn_lit_white" },
    }, other = {
      NOT_YET,
    } },
  } },
}

-- ---------------------------------------------------------------- how it ends

local function theEnd(kind)
  return { { set = "fn_ended" }, { ending = kind } }
end

local CREDITS = {
  { big = "BLIGHTMARE" },
  t("Embia isn't ours. Every god, plague, city and name in this story came first from one person, who built a whole world to share with her friends across a table, and wrote it all down, and waited for them to play."),
  t("That campaign never started. This is the first time anyone has walked there. It's her world, and you've been a guest in it."),
  t("Mind the step."),
}

local CARRIED = {
  t("They carry you up out of the Vault on a door. None of them will let anyone else have a corner. You're breathing as sweet as you please. The doctor checks every hour, like a clock."),
  t("There's only one place to take you. The east ward at Orrenshire, twelve beds, twelve chairs. Bed Five has been kept made. In Bed Four the blanket is thrown back, and there's flour in the air."),
  t("An old woman comes out of the kitchen, telling someone they're too thin. She sees the door, and what's on it. For the first time anyone can remember, she has nothing to say."),
  t("She goes and fetches a chair."),
}

local WAKE = chain(CARRIED, {
  t("The doctor tells them what Colette said. Called back, if you're asked properly. So word goes out, by every bird and lift and ship that's left, to everyone who ever owed you anything."),
  t("Gentleman Bogg comes up from Hayford, at very reasonable rates, and waives them. He clears his throat, and asks what you dreamed."),
  t("The Ribbed District sends a delegation, having voted on the wording. Touarch and Blackhold come up from under the world with their lamps, each pretending it hasn't seen the other. Somebody thin from Crysathula asks politely, inside everyone's head."),
  t("What's left of Sindal comes, with its own faces. Nobody sees who leaves a diamond the size of a loaf on the step. Nan props the door with it."),
  t("They fill Orrenshire, and the mine road, and the hills. Every morning for a year, all together, they ask."),
  t("A long way in, on a very small bed, you open one eye. Someone is knocking. Not that door. That one's staying shut. A little door you never saw, with a draught under it, and a smell of burnt porridge."),
  keeper("That'll be for you. Go on, you lazy article. I've a lamp to see to. Go on. Always finish on home."),
  t("You get up. It's the hardest thing you've ever done, and you've done some things."),
  t("You open your eyes. It is morning. There was something before it."),
  nan("Up, {hero}! The bell's gone and the porridge has started to set, and I'm not chiselling it off the pot a second time. Come on, out of there."),
  t("There are a great many people at the window, all of them holding their breath. She doesn't look at them. She has put her hands in her apron, so nobody can see them shake."),
  ask(nan("Well, then? What did you dream?"), {
    { "A dead uncle asked after the horse.", {
      nan("You've no uncle and we've no horse. You had that off the Hanley boy, and you can't even lie about it properly. Eat your porridge."),
    } },
    { "A woman sang to me, very badly.", {
      nan("Did she, now? Well. That's the first decent thing you've brought me to breakfast in twenty-three years. Eat your porridge."),
    } },
    { "Nothing, Nan. Same as always.", {
      nan("Nothing. A year in that bed, and the whole world on the step, and it's nothing. Eat your porridge."),
    } },
  }),
  t("She gets as far as the door. Then she sits down on the floor, all at once, and puts her apron over her face."),
  deserter("Friend. {hero}. I hate to raise this. My spoon?"),
  hero("I had to leave it. It's holding the door shut."),
  t("The doctor thinks about that for some time, and sits down on the floor as well."),
  deserter("You signed for that. Yes. Yes, it would. It's a very good spoon."),
  t("The scholar has the narrow column open on one knee. There's a last line at the foot of the page, in an inch of pencil. A very small claw rules it through, and writes two words. Seen to."),
  { set = "fn_woken" },
}, CREDITS, theEnd("wake"))

local SLEEP = chain(CARRIED, {
  { when = "fn_truth", steps = {
    t("The doctor tells them what Colette said. So word goes out, and some of those who owed you come. They stand in the road, and they ask."),
    { count = SIX, at = 4, steps = {
      t("It's nearly enough. There are chairs still empty. The doctor sets them out every morning anyway."),
    }, other = {
      t("It isn't enough. A great many is a great many. The doctor sets out the chairs every morning anyway, in rows."),
    } },
  } },
  t("The sister takes a ward in Oplinas, and prays out loud, and asks for them to live. She's wrong about one in five, she says. She has had worse years."),
  t("The scholar keeps the narrow column now. There's one line left at the foot of the page, in an inch of pencil. Outstanding: one."),
  t("Nobody hears from Jezzara Deth. Now and then a very good lock in Orrenshire turns out to have been opened in the night, and your blanket straightened."),
  t("Asphodel Syren goes down her list, town by town. Twice a year, at dusk, she comes and sits for an hour with two fingers on your wrist. Then she nods to the old woman, and goes."),
  t("The doctor has rooms over the bakery, and no forms. The doctor makes the soup, and eats it with a fork, and won't discuss it."),
  t("Every morning the bell goes, and Nan comes in with the porridge, and sits, and gets an arm behind your head. Your mouth opens for the spoon by itself. Somebody taught you that."),
  nan("Up, {hero}. Well, then? What did you dream?"),
  t("Nobody answers. She nods. A body ought to have one person who wants to know how their night went."),
  t("Under the blanket, your eyes have begun to move. Back and forth, slowly, the way they haven't since you were six weeks old."),
  t("A long way in, a lamp goes red, then green, then white. Someone is singing, very badly."),
}, CREDITS, theEnd("sleep"))

for _, step in ipairs(WAKE) do S.fn_wake_late[#S.fn_wake_late + 1] = step end

local WORLD = {
  { dark = true },
  { unsolo = true },
  { warp = { "fn_vault_1", 3, 3, 2 } },
  t("It is morning, all over Embia. On every road the early risers stop where they are, and sit down. A great many people ask for a glass of water, and what year it is."),
  t("In Bed Four of the east ward at Orrenshire, an old woman sits up and wants to know who has been making this porridge."),
  t("Far below, it tries the lid now and then, the way you'd try a door in a house you used to live in. The lid holds."),
  { when = "side_frogs", steps = {
    t("In Hayford the Return is paid, one gold in ten, to the swamp. Gentleman Bogg collects it himself, at very reasonable rates."),
  }, other = {
    t("In Hayford the water has come up, and the frog folk have gone wherever they go. Nobody collects the Return. Nobody left can say what it was for."),
  } },
  { when = "side_revolution", steps = {
    t("The Ribbed District still holds Adaphis. It has a council, the council has a quarrel, and the quarrel has minutes. Medicine is free on every floor."),
  }, other = {
    t("The Ribbed District held until the spring, and nobody came. The skeleton city has gone back to being a skeleton."),
  } },
  { when = "side_barnabas", steps = {
    t("What's left of Sindal wakes, and finds its own face. It's fed a little at a time, from the doctor's notes."),
  }, other = {
    t("What's left of Sindal wakes hungry, and there's nobody to tell it no."),
  } },
  { when = "side_lovers", steps = {
    t("There's a feast on the Pillar Road, for a wedding both sides claim to have won. The Crown of Comets is passed round, with the nuts in it."),
  }, other = {
    t("Touarch and Blackhold have stopped speaking again, in the dark. In a back room a young man is writing out the Book of Grudges from memory. He's nearly at the end."),
  } },
  { when = "side_zalabarula", steps = {
    t("Crysathula has no mother now. Its people have the Brain Sipper's notes, and they're learning to hold themselves together. They've given up brains. They describe this as a phase."),
    { when = "rd_zal_kept", steps = {
      t("A very old voice holds them while they learn. It holds them gently. It knows who'll come if it closes its hand."),
    } },
  }, other = {
    t("Crysathula has no mother now, and nobody left instructions. It's very quiet down there, and getting quieter."),
  } },
  { when = "side_chylbad", steps = {
    t("Nobody has been eaten in the southern caves this year. Dragons have begun, carefully, to come up and look at the sky."),
  }, other = {
    t("Something thin and white still hunts in the southern caves. It's getting bigger."),
  } },
  { when = "wm_peewit_lives", steps = {
    t("At the windmill a small harpy leads the birds, and sings one note, clean and true."),
  } },
  { when = "wm_took", steps = {
    t("At the windmill the shutters stay closed. The birds still keep the beams, and they still don't sing."),
  } },
  { when = "heard_tobin", steps = {
    t("A very thin man comes walking up the high street of Scythebreak, and stops at a door. His boots are beside it. He sits down on the step for a long time. He was a fish once."),
  } },
  { all = SECRET, steps = WAKE, other = SLEEP },
}

local CLOSING = chain({
  t("Three lights stand over the water, red and green and white. You go to the crate."),
  t("It's what you came in. NO TROUBLE, it says, on the lid. Inside is something small and pale, the size of a lentil and the size of the sky. It's asleep. Behind it, a long way down, all of that is coming up the stairs."),
  hero("You've been no trouble either."),
  t("You lower the lid. It comes down on an arm, and the arm draws back. Then it comes down all the way. The hasp wants a pin. There's nothing in this room the right shape."),
  t("You've got a spoon."),
  t("It goes through the hasp as if it had been made for it. Something on the far side tries the lid, once, quite politely. Then it tries with the whole weight of the Far Realm."),
  t("It holds."),
  hero("It's a very good spoon."),
  { big = "THE DOOR IS SHUT" },
  keeper("That's the way. Now lie down, before you fall down. I'll sit up. I've done the night shift before."),
  t("It's a very small bed, and you fit. You have never been so tired, and you've no idea what you were afraid of. It's quiet. It doesn't hurt at all."),
  { fade = true },
}, WORLD)

S.fn_d_crate = {
  { when = "fn_lit_white", steps = CLOSING, other = {
    t("A crate about the size for a baby, with NO TROUBLE on its lid. The lid is rattling. A long way under, something is feeling for the latch. It won't stay down, not with the lamps out."),
  } },
}

return R
