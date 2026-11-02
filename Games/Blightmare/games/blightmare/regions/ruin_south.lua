-- games/blightmare/regions/ruin_south.lua
-- The second half opens, the World of Ruin moment. The hero wakes a year on because for the first time nobody has come with the
-- spoon. Alone through Scythebreak, Orrenshire, Hayford and Oplinas, following the doctor's notices. The Annexe, and the same lock
-- from the other side. Then two, by the lift line, to Glamouth, the burned Verdant Sea, the mill, Agoshull and Evrastin, where the
-- scholar is keeping the Light. Then three, back to Nan. Draft for the author to edit.
--
-- The rule of the ruined world, which this region invents and later regions may use: the night the wall fell, every sleeper in
-- Embia opened their eyes and got up (the EARLY RISERS, Orrenshire's name for them), except the ones somebody was sitting up with.
-- The clerk with the satchel carried the hero home from the Vault, and has a name now. His ledger's narrow column, the names,
-- is what the hero carries on, and that's Q39: the ruined world shows who made it.
--
-- Later regions can read rs_tully_came and rs_hob_came, and the key item rs_ledger. Nan is at Orrenshire from rs_sitters on.

local say = require("games.blightmare.say")

local t, ask, topic, person, line = say.t, say.ask, say.topic, say.person, say.line

local WORLD = {
  scythebreak = { 62, 60 }, orrenshire = { 67, 44 }, hayford = { 106, 65 }, oplinas = { 108, 47 },
  glamouth = { 92, 71 }, windmill = { 96, 60 }, agoshull = { 30, 57 }, evrastin = { 47, 62 },
}

local R = {
  id = "ruin_south", prefix = "rs_",
  entry = { flags = { "ruined" }, join = {}, lvl = 32, site = "scythebreak_r" },
  exit = "rs_done",
  -- read from earlier regions, so that the ruined world answers for what was done there; the last two are for later regions
  exports = {
    "lied_to_nan", "said_goodbye", "kid_kind", "kid_snub", "spared_handlers", "held_handlers", "drew_fire", "wore_hat",
    "hr_fed_tully", "hr_keel_spared", "hr_tied_aude", "wm_got_dish", "wm_took", "wm_peewit_lives", "wm_lucilda_dead",
    "em_counted", "vt_met_clerk",
    "rs_tully_came", "rs_hob_came",
  },
  sites = {}, maps = {}, scripts = {}, shops = {}, goals = {},
  foes = {}, abilities = {}, encounters = {}, field = {},
  looks = {}, names = {}, art = {},
  items = {
    rs_spoon = { name = "A SPOON", key = true },
    rs_ledger = { name = "THE NARROW COLUMN", key = true },
    rs_winding_key = { name = "THE WINDING KEY", key = true },
  },
}

local S, M, L = R.scripts, R.maps, R.looks

-- ---------------------------------------------------------------- the helpers maps are drawn with

local SPOTS = {}

--- A map from its drawing: marks become tiles, and every at becomes an x and y. Lower case and digits are floor, upper case stairs.
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
    for _, item in ipairs(def[kind] or {}) do
      local where = spots[item.at]
      if not where then error(id .. " has no mark " .. tostring(item.at)) end
      item.x, item.y, item.at = where[1], where[2], nil
    end
  end
  M[id] = def
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
local function who(id, name, look)
  L[id] = look
  R.names[name] = id
  return person(id, name)
end

--- A thing set on a draped table, drawn with what a person would carry.
local function thing(id, carry)
  L[id] = { kind = "human", pose = "lying", bed = true, empty = true, carry = carry, carryX = 0.5 }
end

--- A site in the ruined world, on the tile of the one it replaces.
local function ruined(id, map, mark, dir, name)
  local at = WORLD[id]
  local mx, my = spot(map, mark)
  R.sites[id .. "_r"] = { x = at[1], y = at[2], map = map, mx = mx, my = my, dir = dir, name = name, when = "ruined" }
end

-- ---------------------------------------------------------------- who says what

local doc, owl = line("deserter"), line("owlin")
local mayor, gnome, smith, innkeeper = line("mayor"), line("gnome"), line("smith"), line("innkeeper")

local nib = who("rs_nib", "NIB", { kind = "gnome", tall = 0.5, build = "stout", coat = "tie", trim = "hi", hat = "cap", hatInk = "tie", wear = { "apron", "belt" }, carry = "keys", eyes = "tired", mouth = "line", back = "panel" })
local nob = who("rs_nob", "NOB", { kind = "gnome", tall = 0.5, build = "thin", coat = "tie", trim = "warn", hat = "earflap", hatInk = "warn", wear = { "strap" }, carry = "tube", eyes = "shifty", mouth = "frown", back = "panel" })
local pip = who("rs_pip", "PIP", { kind = "gnome", tall = 0.46, build = "thin", coat = "blueTint", trim = "ok", hair = "tufts", hairInk = "warn", carry = "greenlamp", eyes = "tired", mouth = "smile", back = "hiTint" })
local lump = who("rs_lump", "CASK HANDLER", { kind = "human", tall = 0.97, build = "broad", cut = "tunic", coat = "tie", trim = "line", hair = "short", hairInk = "line", beard = "stubble", beardInk = "line", wear = { "apron" }, apronInk = "panel", carry = "cards", eyes = "tired", mouth = "line", back = "tie" })
local bogg = who("rs_bogg", "GENTLEMAN BOGG", { like = "hr_bogg", carry = "cane", eyes = "narrow" })
local farthing = who("rs_farthing", "FARTHING", { like = "hr_farthing", tall = 0.54, carry = "ledger" })
local ambry = who("rs_ambry", "DEACONESS AMBRY", { like = "hr_ambry", eyes = "tired", mouth = "line" })
local ione = who("rs_ione", "SPEAKER IONE", { like = "hr_ione", eyes = "tired", wear = { "shawl" }, shawlInk = "tie" })
local wenna = who("rs_wenna", "WENNA OAKES", { like = "hr_wenna", carry = "ladle", wear = { "apron", "shawl" }, apronInk = "line", shawlInk = "tie" })
local vance = who("rs_vance", "READER VANCE", { like = "hr_vance", carry = "book" })
local drum = who("rs_drum", "CAPTAIN DRUM", { like = "hr_drum", eyes = "tired" })
local keel = who("rs_keel", "VESPER KEEL", { like = "hr_keel", eyes = "tired", carry = "none" })
local wren = who("rs_wren", "WREN", { like = "hr_wren", tall = 0.56, carry = "keys", hat = "tricorn", hatInk = "tie" })
local scrimp = who("rs_scrimp", "SCRIMP", { like = "hr_scrimp", eyes = "shifty" })
local tully = who("rs_tully", "COOK TULLY", { like = "hr_tully", skin = "line", coat = "tie", carry = "ladle", eyes = "tired" })
local peewit = who("rs_peewit", "PEEWIT", { like = "wm_peewit_free", tall = 0.8, eyes = "normal", mouth = "smile" })
local harrier = who("rs_harrier", "HARRIER", { like = "wm_harrier", eyes = "tired" })
local moll = who("rs_moll", "MAGPIE MOLL", { like = "wm_moll", carry = "bowl", eyes = "tired" })
local hob = who("rs_hob", "HOB", { like = "em_hob", eyes = "tired" })
local gannet = who("rs_gannet", "PILOT GANNET", { like = "em_gannet", mouth = "smile" })
local tawn = who("rs_tawn", "WARDEN TAWN", { like = "em_tawn", eyes = "tired" })
local tyto = who("rs_tyto", "MATRON TYTO", { like = "em_tyto" })
local sorrel = who("rs_sorrel", "BURDOCK", { like = "em_sorrel" })
local dole = who("rs_dole", "PROCTOR DOLE", { like = "em_dole", skin = "text", coat = "text", trim = "info", eyes = "blank", mouth = "line", carry = "none", back = "blueTint" })
local crue = who("rs_crue", "GATE-SERGEANT CRUE", { like = "hr_crue", skin = "line", eyes = "wide", mouth = "line", blight = true })
local lucky = who("rs_lucky", "A YOUNG FROG", { kind = "frog", tall = 0.74, build = "stout", cut = "coat", coat = "ok", trim = "hi", carry = "pole", eyes = "wide", mouth = "smile", back = "hiTint" })
local ward = who("rs_orderly", "ORDERLY", { kind = "clinic", tall = 0.9, build = "thin", coat = "text", trim = "line", skin = "line", hat = "bandage", hatInk = "text", eyes = "wide", mouth = "smile", carry = "clipboard", back = "tie" })

-- those who don't say anything
L.rs_nan = { kind = "old", tall = 0.8, pose = "lying", bed = true, coat = "line", trim = "text", hair = "bun", hairInk = "text", thread = false, back = "tie" }
L.rs_nan_o = { like = "rs_nan", thread = true }
L.rs_thrupp = { like = "em_satchel", tall = 0.62, lean = 0.2, eyes = "closed", mouth = "line", carry = "ledger", stand = "box" }
L.rs_scholar = { kind = "owlin", tall = 0.8, build = "stout", cut = "robe", coat = "tie", trim = "line", carry = "chalk", wings = "tie", hat = "circlet", hatInk = "line", eyes = "tired", back = "bg" }
L.rs_hob_e = { like = "em_hob", eyes = "tired", carry = "bowl" }
L.rs_lump_2 = { like = "rs_lump", carry = "doll", wear = { "strap" } }
thing("rs_t_chart", "board")
thing("rs_t_book", "book")
thing("rs_t_chalk", "chalk")
thing("rs_t_cart", "wheel")
thing("rs_t_house", "bowl")
thing("rs_t_pole", "pole")
thing("rs_t_notice_o", "letter")
thing("rs_t_notice_h", "letter")
thing("rs_t_notice_p", "letter")
thing("rs_t_poster", "letter")
thing("rs_t_bell", "bell")
thing("rs_t_sheet", "clipboard")
thing("rs_t_tray", "tray")
thing("rs_t_wall", "chalk")
thing("rs_t_bed", "pillow")
thing("rs_t_cap", "eye")
thing("rs_t_shutter_a", "wheel")
thing("rs_t_shutter_b", "wheel")
thing("rs_t_basket", "basket")
thing("rs_t_work", "chalk")
thing("rs_t_lamp", "lantern")
thing("rs_t_hat", "feather")
thing("rs_t_log", "letter")
thing("rs_t_scratch", "bowl")
thing("rs_t_cell", "tray")

-- ---------------------------------------------------------------- what's in the way

R.abilities = {
  rs_reach = { name = "REACH", power = 100 },
  rs_tuck = { name = "TUCKS YOU IN", power = 70, status = "sleep", chance = 45 },
  rs_asked = { name = "ARE YOU AWAKE?", mp = 4, power = 55, magic = true, element = "mind", status = "nightmare", chance = 45 },
  rs_ember = { name = "EMBER WING", power = 95, element = "fire" },
  rs_soot = { name = "SOOT", power = 45, status = "blind", chance = 60 },
  rs_rounds = { name = "ROUNDS", power = 105 },
  rs_sedate = { name = "SOMETHING TO HELP", mp = 4, power = 40, status = "sleep", chance = 50 },
  rs_shard = { name = "CUTTING EDGE", power = 110 },
  rs_ring = { name = "THE RINGING", mp = 5, power = 50, magic = true, target = "all", element = "mind" },
  rs_dust = { name = "LAMP DUST", power = 45, status = "blind", chance = 55 },
  -- the Last Cart
  rs_rumble = { name = "THE SHAFTS", power = 105 },
  rs_load = { name = "ROOM FOR ONE MORE", power = 65, status = "sleep", chance = 55 },
  rs_clean = { name = "A VERY CLEAN FLOOR", power = 150, magic = true, target = "all", windup = 34, warn = "THE TAILGATE DROPS" },
  rs_callhand = { name = "THE BELL FOR ROUNDS", target = "summon" },
  -- the bosun
  rs_haul = { name = "HEAVE", power = 110 },
  rs_cinders = { name = "COLD CINDERS", mp = 5, power = 60, magic = true, target = "all", element = "fire" },
  rs_late = { name = "SORRY WE'RE LATE", power = 160, magic = true, target = "all", element = "fire", windup = 34, warn = "THE WHOLE CREW BREATHES IN" },
  rs_muster = { name = "ALL HANDS", target = "summon" },
  -- Dole
  rs_proof = { name = "LINE NINE", mp = 5, power = 90, magic = true, element = "mind" },
  rs_lattice = { name = "LATTICE", power = 115 },
  rs_fracture = { name = "FRACTURE", mp = 6, power = 50, magic = true, target = "all", status = "blind", chance = 40 },
  rs_verge = { name = "THE BREAKTHROUGH", power = 190, magic = true, target = "all", windup = 34, warn = "EVERY PANE SINGS ONE NOTE" },
  rs_growth = { name = "IT GROWS", target = "summon" },
}

R.foes = {
  rs_riser = { name = "EARLY RISER", tier = 32, shape = "brute", sprite = "rs_riser", family = "blighted",
    abilities = { { "rs_reach", 3 }, { "rs_tuck", 1 } }, weak = { "holy" } },
  rs_crawler = { name = "WALL CRAWLER", tier = 32, shape = "small", sprite = "crawler", family = "bug",
    abilities = { { "bite", 3 }, { "spit", 1 } }, weak = { "fire" } },
  rs_kite = { name = "ASH KITE", tier = 33, shape = "quick", sprite = "rs_kite", family = "harpy",
    abilities = { { "rs_ember", 3 }, { "rs_soot", 2 } }, weak = { "ice" } },
  rs_rat = { name = "CINDER RAT", tier = 33, shape = "small", sprite = "rat", family = "rat",
    abilities = { { "gnaw", 3 }, { "retch", 1 } }, resist = { "fire" }, weak = { "ice" } },
  rs_orderly = { name = "NIGHT ORDERLY", short = "ORDERLY", tier = 33, shape = "brute", sprite = "rs_nightman", family = "staff",
    abilities = { { "rs_rounds", 4 }, { "rs_sedate", 2 } }, weak = { "holy" } },
  rs_surgeon = { name = "DUTY DOCTOR", tier = 33, shape = "healer", sprite = "doctor", family = "staff",
    abilities = { { "baton", 2 }, { "field_surgery", 2 }, { "rs_asked", 1 } } },
  rs_hand = { name = "SHORE HAND", tier = 34, shape = "small", sprite = "rs_hand", family = "blighted",
    abilities = { { "rs_reach", 3 }, { "rs_soot", 1 } }, weak = { "ice" } },
  rs_owlbeast = { name = "STARVED OWLBEAST", short = "OWLBEAST", tier = 35, shape = "brute", sprite = "em_owlbeast", family = "stalker",
    abilities = { { "claw", 4 }, { "em_hoot", 1 } } },
  rs_walker = { name = "SHARD WALKER", tier = 35, shape = "tank", sprite = "em_shard", family = "blighted",
    abilities = { { "rs_shard", 3 }, { "rs_asked", 1 } }, immune = { "blind" }, weak = { "bolt" } },
  rs_moth = { name = "LAMP MOTH", tier = 35, shape = "small", sprite = "em_moth", family = "bug",
    abilities = { { "bite", 3 }, { "rs_dust", 2 } }, weak = { "fire" } },
  rs_pane = { name = "SINGING PANE", tier = 36, shape = "caster", sprite = "rs_pane", family = "ghost",
    abilities = { { "rs_ring", 2 }, { "mind_lash", 3 } }, resist = { "mind" }, weak = { "bolt" } },

  rs_cart = {
    name = "THE LAST CART", short = "LAST CART", tier = 33, shape = "tank", sprite = "rs_cart", family = "boss", size = 2, atkx = 0.75, weak = { "fire" },
    boss = { hpx = 0.5, phases = {
      { at = 100, moves = { { "rs_rumble", 5 }, { "rs_load", 2 } }, every = 5, big = "rs_clean" },
      { at = 60, moves = { { "rs_rumble", 5 }, { "rs_load", 3 } }, every = 4, big = "rs_clean", say = "IT HAS A SHEET WITH YOUR NAME ON", summon = "rs_orderly", call = "rs_callhand" },
      { at = 30, moves = { { "rs_rumble", 6 }, { "rs_load", 2 } }, every = 3, big = "rs_clean", say = "IT WANTS TO GO HOME", speedUp = 1 },
    } },
  },
  rs_bosun = {
    name = "THE BOSUN", tier = 34, shape = "brute", sprite = "rs_bosun", family = "boss", size = 2, atkx = 0.8, weak = { "ice" },
    boss = { hpx = 0.55, phases = {
      { at = 100, moves = { { "rs_haul", 5 }, { "rs_cinders", 2 } }, every = 5, big = "rs_late" },
      { at = 66, moves = { { "rs_haul", 5 }, { "rs_cinders", 3 } }, every = 4, big = "rs_late", say = "THE SHORE PARTY COMES ABOARD", summon = "rs_hand", call = "rs_muster" },
      { at = 33, moves = { { "rs_haul", 6 }, { "rs_cinders", 3 } }, every = 3, big = "rs_late", say = "TWENTY-EIGHT YEARS OF HUNGRY", speedUp = 1 },
    } },
  },
  rs_dole = {
    name = "PROCTOR DOLE", short = "DOLE", tier = 36, shape = "caster", sprite = "rs_dole", family = "boss", size = 2, atkx = 0.85, weak = { "bolt" }, resist = { "mind" },
    boss = { hpx = 0.8, phases = {
      { at = 100, moves = { { "rs_lattice", 5 }, { "rs_proof", 3 } }, every = 5, big = "rs_verge" },
      { at = 66, moves = { { "rs_proof", 4 }, { "rs_fracture", 3 } }, every = 4, big = "rs_verge", say = "SHE CORRECTS A LINE", summon = "rs_pane", call = "rs_growth" },
      { at = 33, moves = { { "rs_lattice", 4 }, { "rs_proof", 4 } }, every = 3, big = "rs_verge", say = "ON THE VERGE", speedUp = 1 },
    } },
  },
}

R.encounters = {
  -- the first of these is met alone, so nothing on the road comes in a crowd
  rs_f_1 = { foes = { "rs_riser" }, flee = true, bg = "ruin" },
  rs_f_2 = { foes = { "rs_crawler", "rs_crawler", "rs_crawler" }, flee = true, bg = "ruin" },
  rs_f_3 = { foes = { "rs_kite", "rs_kite" }, flee = true, bg = "ash" },
  rs_f_4 = { foes = { "rs_rat", "rs_rat", "rs_rat" }, flee = true, bg = "ash" },
  rs_f_5 = { foes = { "rs_riser", "rs_kite" }, flee = true, bg = "ruin" },
  rs_w_1 = { foes = { "rs_owlbeast" }, flee = true, bg = "snow" },
  rs_w_2 = { foes = { "rs_walker", "rs_riser" }, flee = true, bg = "ruin" },
  rs_w_3 = { foes = { "rs_moth", "rs_moth", "rs_moth" }, flee = true, bg = "ruin" },
  rs_w_4 = { foes = { "rs_owlbeast", "rs_walker" }, flee = true, bg = "snow" },

  rs_e_home = { foes = { "rs_riser" }, flee = true, bg = "town" },
  rs_e_ward = { foes = { "rs_orderly" }, flee = true, bg = "marble" },
  rs_e_rounds = { foes = { "rs_orderly", "rs_surgeon" }, flee = true, bg = "marble" },
  rs_e_kites = { foes = { "rs_kite", "rs_kite" }, flee = true, bg = "ash" },
  rs_e_rats = { foes = { "rs_rat", "rs_rat", "rs_rat" }, flee = true, bg = "ash" },
  rs_e_hands = { foes = { "rs_hand", "rs_hand", "rs_hand" }, flee = true, bg = "ash" },
  rs_e_moths = { foes = { "rs_moth", "rs_moth", "rs_moth" }, flee = true, bg = "ruin" },
  rs_e_walkers = { foes = { "rs_walker", "rs_moth" }, flee = true, bg = "ruin" },
  rs_e_pane = { foes = { "rs_pane", "rs_walker" }, flee = true, bg = "ruin" },
  rs_e_owlbeast = { foes = { "rs_owlbeast" }, flee = true, bg = "city" },

  rs_b_cart = { foes = { "rs_cart" }, flee = false, bg = "city", boss = true },
  rs_b_bosun = { foes = { "rs_bosun" }, flee = false, bg = "ash", boss = true },
  rs_b_dole = { foes = { "rs_dole" }, flee = false, bg = "ruin", boss = true },
}

R.field.ruin_south = { "rs_f_1", "rs_f_2", "rs_f_3", "rs_f_4", "rs_f_5" }
R.field.ruin_west = { "rs_w_1", "rs_w_2", "rs_w_3", "rs_w_4" }

R.art = {
  rs_riser = "A sleeper in a nightshirt, up and walking, arms a little out, eyes wide open and pale, looking pleasantly at nothing.",
  rs_kite = "A lean black bird the size of a child, wings edged with live embers, shedding soot as it turns.",
  rs_nightman = "A Clinic orderly on night rounds, spotless, with both eyes wide and a small fixed smile, one hand held out for your wrist.",
  rs_hand = "A sailor burned grey as ash, in the rags of a very old uniform, still carrying a coil of rope, mouth hanging open.",
  rs_pane = "A tall thin blade of pale crystal standing on its point, ringing, with something like a face moving about inside it.",
  rs_cart = "A closed Clinic cart with no horse in the shafts, scrubbed spotless, rolling by itself, tailgate hanging open on a clean dark inside. Big.",
  rs_bosun = "A huge burned man in a bosun's coat with the sleeves gone, whistle on a chain, ash for a beard, grass fire still crawling in his chest.",
  rs_dole = "A long thin woman in a stained coat, grown through with pale crystal from the left hand up, pen still in the right, a lens where her ribs were.",
}

-- ---------------------------------------------------------------- the maps

place("rs_scythebreak", {
  name = "SCYTHEBREAK", theme = "ruin", savepoint = true,
  rows = {
    "########################",
    "#WWWW###hhhhhhhhhhhhhh##",
    "#WWW..##h.n.a......p.h##",
    "#WW...##h............h##",
    "#WW.1.##hhhhhh+hhhhhhh##",
    "#WW....#......d.......##",
    "#W.....#......c.b.....##",
    "#W..2.....hhhh.......y##",
    "#WW.......h.kh........##",
    "#WW.......h..+........##",
    "#W........hhhh........##",
    "#W....................gE",
    "#WW......v.....w.....###",
    "#WWW.....hhhhhhh.....###",
    "########################",
  },
  npcs = {
    { id = "rs_nan", at = "n", script = "rs_t_nan", unless = "rs_sitters" },
    { id = "rs_t_chart", at = "p", script = "rs_t_chart" },
    { id = "rs_thrupp", at = "c", sprite = "guard", script = "rs_t_chair", unless = "rs_carried" },
    { id = "rs_t_book", at = "b", script = "rs_t_book" },
    { id = "rs_t_cart", at = "y", script = "rs_t_cart" },
    { id = "rs_t_house", at = "k", script = "rs_t_house" },
    { id = "rs_t_chalk", at = "v", script = "rs_t_chalk" },
    { id = "rs_t_pole", at = "w", script = "rs_t_pole" },
  },
  steps = {
    { at = "g", script = "rs_wake", unless = "rs_woke", once = true },
    { at = "d", script = "rs_s_clerk", once = true },
  },
  foes = {
    { id = "f1", at = "1", enc = "rs_e_home", sprite = "rs_riser" },
    { id = "f2", at = "2", enc = "rs_e_home", sprite = "rs_riser" },
  },
  exits = { { at = "E", world = WORLD.scythebreak } },
})

place("rs_orrenshire", {
  name = "ORRENSHIRE", theme = "town", savepoint = true,
  rows = {
    "######################",
    "#hhhhhhhh####hhhhhhhh#",
    "#h..i...h####h.m....h#",
    "#h......h####h......h#",
    "#hhh+hhhh####hhh+hhhh#",
    "#....................#",
    "#..x.........t..p....#",
    "E.g..................#",
    "#....................#",
    "#hhh+hhhh#..#hhh+hhhh#",
    "#h.s....h#..#h.n.q..h#",
    "#h......h#..#h.y....h#",
    "#hhhhhhhh#..#hhhhhhhh#",
    "#.........j..........#",
    "######################",
  },
  npcs = {
    { id = "rs_inn", at = "i", sprite = "innkeeper", script = "rs_t_inn" },
    { id = "rs_mayor", at = "m", sprite = "mayor", script = "rs_t_mayor" },
    { id = "rs_gate", at = "x", sprite = "gnome", script = "rs_t_gate" },
    { id = "rs_t_notice_o", at = "t", script = "rs_t_notice_o" },
    { id = "rs_smith", at = "s", sprite = "smith", script = "rs_t_smith" },
    { id = "rs_nib", at = "j", script = "rs_t_nib" },
    { id = "rs_nan_o", at = "n", script = "rs_t_nan_o", when = "rs_sitters" },
    { id = "rs_pip", at = "y", script = "rs_t_pip", when = "rs_sitters" },
    { id = "rs_lump", at = "q", script = "rs_t_lump_held", when = "held_handlers" },
    { id = "rs_lump_2", at = "q", script = "rs_t_lump_home", when = "spared_handlers" },
  },
  steps = {
    { at = "g", script = "rs_back_home", unless = "rs_woke" },
    { at = "g", script = "rs_s_orrenshire", once = true },
  },
  exits = { { at = "E", world = WORLD.orrenshire } },
})

place("rs_hayford", {
  name = "WHAT'S LEFT OF HAYFORD", theme = "swamp", savepoint = true,
  rows = {
    "####################",
    "#~~~~~~~~~~~~~~~~~~#",
    "#~~~hhhh~~~~~hhhh~~#",
    "#~~~h.bh~~~~~h.fh~~#",
    "#~~~h..+.....+e.h~~#",
    "#~~~hhhh~~.~~hhhh~~#",
    "#~~~~~~~~~.~~~~~~~~#",
    "#~~~~~~~...n.~~~~~~#",
    "E.g..............~~#",
    "#~~~~~.....a.....~~#",
    "#~~~~~.~~~~~~~~~.~~#",
    "#~~~~~.~~~~~~~~~.~~#",
    "#~~~~~p~~~~~~~~~s~~#",
    "#~~~~~~~~~~~~~~~~~~#",
    "####################",
  },
  npcs = {
    { id = "rs_bogg", at = "a", script = "rs_t_bogg" },
    { id = "rs_farthing", at = "f", script = "rs_t_farthing" },
    { id = "rs_ambry", at = "b", script = "rs_t_ambry" },
    { id = "rs_t_notice_h", at = "n", script = "rs_t_notice_h" },
    { id = "rs_t_hat", at = "p", script = "rs_t_hat" },
    { id = "rs_lucky", at = "s", script = "rs_t_lucky" },
  },
  steps = {
    { at = "g", script = "rs_too_far_h", unless = "rs_sitters" },
    { at = "g", script = "rs_s_hayford", once = true },
  },
  chests = { { id = "c1", at = "e", give = "hipotion", n = 3 } },
  exits = { { at = "E", world = WORLD.hayford } },
})

place("rs_oplinas", {
  name = "OPLINAS", theme = "ruin", savepoint = true,
  rows = {
    "##########A###########",
    "#hhhhhhhhh.hhhhhhhhhh#",
    "#.........d..........#",
    "#....................#",
    "#hhh+hhhh....hhh+hhh.#",
    "#h..i...h....h..w..h.#",
    "#h..a...h....h.....h.#",
    "#hhhhhhhh....hhhhhhh.#",
    "#....................#",
    "#......c.......n.....#",
    "E.g..................#",
    "#...........m........#",
    "#...t.........o......#",
    "#....................#",
    "######################",
  },
  npcs = {
    { id = "rs_ione", at = "i", script = "rs_t_ione" },
    { id = "rs_aude", at = "a", sprite = "shroud", script = "rs_t_aude" },
    { id = "rs_wenna", at = "w", script = "rs_t_wenna" },
    { id = "rs_crue", at = "c", script = "rs_t_crue" },
    { id = "rs_t_notice_p", at = "n", script = "rs_t_notice_p" },
    { id = "rs_vance", at = "t", script = "rs_t_vance" },
    { id = "rs_nob", at = "o", script = "rs_t_nob" },
  },
  steps = {
    { at = "g", script = "rs_too_far_p", unless = "rs_sitters" },
    { at = "g", script = "rs_s_oplinas", once = true },
    { at = "d", script = "rs_t_stair", unless = "rs_cart_down", once = true },
  },
  exits = {
    { at = "E", world = WORLD.oplinas },
    { at = "A", map = "rs_annexe_1", mx = 9, my = 14, dir = 1 },
  },
})

place("rs_annexe_1", {
  name = "THE ANNEXE", theme = "marble",
  rows = {
    "####################",
    "#hhhhhhhhhhhhhhhhhh#",
    "#h.a.b.c..h..1...Uh#",
    "#h........h.......h#",
    "#h.......xh.2.....h#",
    "#hhh+hhhhhh+hhhhhhh#",
    "#..........v.......#",
    "#....3.............#",
    "#hhhhhh...hhhhhhhhh#",
    "#h4...h...h.......h#",
    "#h....+...+..y..s.h#",
    "#h...zh...h.......h#",
    "#hhhhhh...hhhhhhhhh#",
    "#.......g..........#",
    "########S###########",
  },
  npcs = {
    { id = "rs_orderly", at = "v", script = "rs_t_door_orderly", unless = "rs_a_signed" },
    { id = "rs_t_sheet", at = "s", script = "rs_t_sheet" },
    { id = "rs_t_bell", at = "y", script = "rs_t_bell" },
    { id = "rs_t_bed", at = "a", script = "rs_t_bed_a" },
    { id = "rs_t_tray", at = "b", script = "rs_t_tray" },
  },
  chests = {
    { id = "c1", at = "x", give = "xpotion" },
    { id = "c2", at = "z", give = "shade_coat" },
    { id = "c3", at = "c", give = "hiether", n = 2 },
  },
  foes = {
    { id = "f1", at = "1", enc = "rs_e_ward", sprite = "rs_nightman" },
    { id = "f2", at = "2", enc = "rs_e_rounds", sprite = "rs_nightman" },
    { id = "f3", at = "3", enc = "rs_e_ward", sprite = "rs_nightman" },
    { id = "f4", at = "4", enc = "rs_e_rounds", sprite = "doctor" },
  },
  exits = {
    { at = "S", map = "rs_oplinas", mx = 11, my = 2, dir = 3 },
    { at = "U", map = "rs_annexe_2", mx = 4, my = 6, dir = 2 },
  },
})

place("rs_annexe_2", {
  name = "THE ANNEXE, SECURE WARD", theme = "marble",
  rows = {
    "####################",
    "#hhhhhhhhhhhhhhhhhh#",
    "#h...h...h...h....h#",
    "#h.a.h.b.h.x.h..e.h#",
    "#hh+hhh+hhh+hh....h#",
    "#D.g...............#",
    "#..........k.......#",
    "#hh+hhh+hhh+hhhh+hh#",
    "#h.2.h...h.q.h..y.h#",
    "#h...h.z.h...h....h#",
    "#h...h...h...h....h#",
    "#hhhhhhhhhhhhhhhhhh#",
    "####################",
    "####################",
    "####################",
  },
  npcs = {
    { id = "rs_t_wall", at = "a", script = "rs_t_wall" },
    { id = "rs_t_scratch", at = "b", script = "rs_t_scratch" },
    { id = "rs_t_cell", at = "q", script = "rs_t_cell", when = "rs_doc_back" },
    { id = "rs_the_cart", at = "y", sprite = "rs_cart", script = "rs_s_cart", unless = "rs_cart_down" },
  },
  steps = { { at = "k", script = "rs_s_lock", once = true } },
  chests = {
    { id = "c1", at = "x", give = "ruin_plate" },
    { id = "c2", at = "z", give = "panacea", n = 2 },
  },
  foes = {
    { id = "f1", at = "2", enc = "rs_e_ward", sprite = "rs_nightman" },
    { id = "f2", at = "e", enc = "rs_e_rounds", sprite = "rs_nightman" },
  },
  exits = { { at = "D", map = "rs_annexe_1", mx = 17, my = 3, dir = 3 } },
})

place("rs_glamouth", {
  name = "GLAMOUTH", theme = "ruin", savepoint = true,
  rows = {
    "######################",
    "#hhhhhhh....hhhhhhhh~#",
    "#h.s...h....h..d...h~#",
    "#h.....+....+......h~#",
    "#hhhhhhh....hhhhhhhh~#",
    "#.............p....~~#",
    "E.g..............k.~~#",
    "#...w...........~~~~~#",
    "#..............~~~~~~#",
    "#...x.......~~~~~~~~~#",
    "#..........~~~~~~~~~~#",
    "#........~~~~~~~~~~~~#",
    "#......~~~~~~~~~~~~~~#",
    "#.....~~~~~~~~~~~~~~~#",
    "######################",
  },
  npcs = {
    { id = "rs_scrimp", at = "s", script = "rs_t_scrimp" },
    { id = "rs_drum", at = "d", script = "rs_t_drum" },
    { id = "rs_t_poster", at = "p", script = "rs_t_poster" },
    { id = "rs_keel", at = "k", script = "rs_t_keel", when = "hr_keel_spared" },
    { id = "rs_wren", at = "w", script = "rs_t_wren" },
  },
  steps = {
    { at = "g", script = "rs_too_soon_g", unless = "can_travel" },
    { at = "g", script = "rs_s_glamouth", once = true },
  },
  chests = { { id = "c1", at = "x", give = "hiether", n = 2 } },
  exits = { { at = "E", world = WORLD.glamouth } },
})

place("rs_ash_1", {
  name = "THE BURNED SEA", theme = "ash",
  rows = {
    "########################",
    "#########..My.##########",
    "###....#####n#####..1.##",
    "###.x...####r####......#",
    "#......................#",
    "#.....hhhhhhhhh........#",
    "#.....h...o...+......2.#",
    "#.....hhhhhhhhh........#",
    "#..3...................#",
    "#..........#####.......#",
    "#...####......z.....4..#",
    "#...####...............#",
    "E.g....................#",
    "#......................#",
    "########################",
  },
  npcs = { { id = "rs_tully", at = "o", script = "rs_t_tully" } },
  steps = {
    { at = "g", script = "rs_too_soon_a", unless = "can_travel" },
    { at = "g", script = "rs_s_ash", once = true },
    { at = "n", script = "rs_s_shore", unless = "rs_shore_down" },
  },
  chests = {
    { id = "c1", at = "x", give = "wraith_edge" },
    { id = "c2", at = "z", give = "xpotion", n = 2 },
  },
  foes = {
    { id = "f1", at = "1", enc = "rs_e_kites", sprite = "rs_kite" },
    { id = "f2", at = "2", enc = "rs_e_rats", sprite = "rat" },
    { id = "f3", at = "3", enc = "rs_e_hands", sprite = "rs_hand" },
    { id = "f4", at = "4", enc = "rs_e_kites", sprite = "rs_kite" },
  },
  exits = {
    { at = "E", world = WORLD.windmill },
    { at = "M", map = "rs_windmill", mx = 9, my = 13, dir = 1 },
  },
})

place("rs_windmill", {
  name = "THE WINDMILL", theme = "ruin", savepoint = true,
  rows = {
    "##################",
    "#hhhhhhhhhhhhhhhh#",
    "#h......c.......h#",
    "#h..............h#",
    "#h...p.....m....h#",
    "#h..............h#",
    "#hhhhhhh+hhhhhhhh#",
    "#................#",
    "#...1............#",
    "#................#",
    "#...x............#",
    "#................#",
    "#.......g........#",
    "#................#",
    "########S#########",
  },
  npcs = {
    { id = "rs_t_cap", at = "c", script = "rs_s_cap" },
    { id = "rs_peewit", at = "p", script = "rs_t_peewit", when = "wm_peewit_lives" },
    { id = "rs_harrier", at = "x", script = "rs_t_harrier", when = "wm_peewit_lives" },
    { id = "rs_moll", at = "m", script = "rs_t_moll" },
  },
  foes = { { id = "f1", at = "1", enc = "rs_e_kites", sprite = "rs_kite" } },
  exits = { { at = "S", map = "rs_ash_1", mx = 13, my = 2, dir = 3 } },
})

place("rs_agoshull", {
  name = "AGOSHULL", theme = "city", savepoint = true,
  rows = {
    "####################",
    "#hhhhhhh....hhhhhhh#",
    "#h..o..h....h.....h#",
    "#h.....+....+..x..h#",
    "#hhhhhhh....hhhhhhh#",
    "#..................#",
    "#....1.............#",
    "#hhhhhhh.b..hhhhhhh#",
    "#..................#",
    "E.g................#",
    "#..................#",
    "#.....2............#",
    "#..................#",
    "#..................#",
    "####################",
  },
  npcs = {
    { id = "rs_hob", at = "b", script = "rs_t_hob", unless = "rs_hob_came" },
    { id = "rs_t_lamp", at = "o", script = "rs_t_agoshull_lamp" },
  },
  steps = {
    { at = "g", script = "rs_too_soon_ag", unless = "rs_mill_seen" },
    { at = "g", script = "rs_s_agoshull", once = true },
  },
  chests = { { id = "c1", at = "x", give = "grave_rod" } },
  foes = {
    { id = "f1", at = "1", enc = "rs_e_owlbeast", sprite = "em_owlbeast" },
    { id = "f2", at = "2", enc = "rs_e_walkers", sprite = "em_shard" },
  },
  exits = { { at = "E", world = WORLD.agoshull } },
})

place("rs_evrastin", {
  name = "EVRASTIN", theme = "coral", savepoint = true,
  rows = {
    "###########T##########",
    "#hhhhhhhhhh.hhhhhhhhh#",
    "#....................#",
    "#..t..........s......#",
    "#....................#",
    "#hhh+hhhh#..#hhh+hhhh#",
    "#h......h#..#h......h#",
    "#h..m...h#..#h..a...h#",
    "#hhhhhhhh#..#hhhhhhhh#",
    "#...........z........#",
    "E.g..................#",
    "#.............p......#",
    "#.....~~~~~~~~~~~~~~~#",
    "#~~~~~~~~~~~~~~~~~~~~#",
    "######################",
  },
  npcs = {
    { id = "rs_sorrel", at = "t", script = "rs_t_sorrel" },
    { id = "rs_hob_e", at = "s", script = "rs_t_hob_e", when = "rs_hob_came" },
    { id = "rs_tyto", at = "m", script = "rs_t_tyto" },
    { id = "rs_tawn", at = "a", script = "rs_t_tawn" },
    { id = "rs_gannet", at = "p", script = "rs_t_gannet" },
  },
  steps = {
    { at = "g", script = "rs_too_soon_e", unless = "rs_mill_seen" },
    { at = "g", script = "rs_s_evrastin", once = true },
  },
  exits = {
    { at = "E", world = WORLD.evrastin },
    { at = "T", map = "rs_light_1", mx = 8, my = 11, dir = 1 },
  },
})

place("rs_light_1", {
  name = "THE TOWER", theme = "marble",
  rows = {
    "#################",
    "#hhhhhhhhhhhhhhh#",
    "#h.a.........b.h#",
    "#h....hh.hh....h#",
    "#h.1..hhmhh..2.h#",
    "#h....hhUhh....h#",
    "#h.............h#",
    "#h.x.........y.h#",
    "#hhhhhh+hhhhhhhh#",
    "#...............#",
    "#......g.j......#",
    "#...............#",
    "#...............#",
    "#...............#",
    "#######S#########",
  },
  npcs = {
    { id = "rs_t_shutter_a", at = "a", script = "rs_t_shutter_a" },
    { id = "rs_t_shutter_b", at = "b", script = "rs_t_shutter_b" },
    { id = "rs_moths", at = "m", sprite = "em_moth", script = "rs_t_moths", unless = "rs_shutters" },
    { id = "rs_t_basket", at = "j", script = "rs_t_basket" },
    { id = "rs_t_log", at = "y", script = "rs_t_log" },
  },
  steps = { { at = "g", script = "rs_s_tower", once = true } },
  chests = { { id = "c1", at = "x", give = "ash_vestment" } },
  foes = {
    { id = "f1", at = "1", enc = "rs_e_moths", sprite = "em_moth" },
    { id = "f2", at = "2", enc = "rs_e_walkers", sprite = "em_shard" },
  },
  exits = {
    { at = "S", map = "rs_evrastin", mx = 12, my = 2, dir = 3 },
    { at = "U", map = "rs_light_2", mx = 8, my = 13, dir = 1 },
  },
})

place("rs_light_2", {
  name = "THE LAMP ROOM", theme = "marble",
  rows = {
    "#################",
    "#hhhhhhhhhhhhhhh#",
    "#h.....o.......h#",
    "#h..c.......l..h#",
    "#h.............h#",
    "#hhhhhhh+hhhhhhh#",
    "#~~~~~~...~~~~~~#",
    "#~~~~~~...~~~~~~#",
    "#~~~~~~.e.~~~~~~#",
    "#~~~~~~...~~~~~~#",
    "#...1.......2...#",
    "#.x...........z.#",
    "#......g.D......#",
    "#...............#",
    "#################",
  },
  npcs = {
    { id = "rs_scholar", at = "o", script = "rs_s_scholar", unless = "rs_dole_down" },
    { id = "rs_t_work", at = "c", script = "rs_t_work" },
    { id = "rs_t_lamp_2", at = "l", sprite = "em_lamp", script = "rs_t_lamp" },
    { id = "rs_dole", at = "e", script = "rs_t_dole_still", unless = "rs_dole_down" },
  },
  chests = {
    { id = "c1", at = "x", give = "elixir" },
    { id = "c2", at = "z", give = "life_ring" },
  },
  foes = {
    { id = "f1", at = "1", enc = "rs_e_pane", sprite = "rs_pane" },
    { id = "f2", at = "2", enc = "rs_e_moths", sprite = "em_moth" },
  },
  exits = { { at = "D", map = "rs_light_1", mx = 9, my = 7, dir = 3 } },
})

-- ---------------------------------------------------------------- sites

ruined("scythebreak", "rs_scythebreak", "g", 4, "WHAT'S LEFT OF SCYTHEBREAK")
ruined("orrenshire", "rs_orrenshire", "g", 2, "ORRENSHIRE")
ruined("hayford", "rs_hayford", "g", 2, "WHAT'S LEFT OF HAYFORD")
ruined("oplinas", "rs_oplinas", "g", 2, "OPLINAS")
ruined("glamouth", "rs_glamouth", "g", 2, "GLAMOUTH")
ruined("windmill", "rs_ash_1", "g", 2, "THE BURNED SEA")
ruined("agoshull", "rs_agoshull", "g", 2, "AGOSHULL")
ruined("evrastin", "rs_evrastin", "g", 2, "EVRASTIN")

-- ---------------------------------------------------------------- going the wrong way

local function turned(text, at, withDoctor)
  if not withDoctor then return { t(text), { world = at } } end
  return { { when = "rs_doc_back", steps = { doc(withDoctor) }, other = { t(text) } }, { world = at } }
end

--- The same list of answers, less one, once flag is set: nobody asks after someone who's standing there.
local function askUntil(flag, line, options, drop)
  local fewer = {}
  for i, option in ipairs(options) do
    if i ~= drop then fewer[#fewer + 1] = option end
  end
  local function shown(list)
    return ask({ say = line.say, name = line.name, text = line.text }, list)
  end
  local later = { shown(fewer) }
  if #fewer == 1 then -- nothing left to choose between: it's just said
    later = { { say = line.say, name = line.name, text = line.text } }
    for _, step in ipairs(fewer[1][2]) do later[#later + 1] = step end
  end
  return { when = flag, steps = later, other = { shown(options) } }
end

S.rs_back_home = turned("You get as far as the first broken wall, and your legs stop. There's one place on all this torn country that you know the way to. You seem to have been falling towards it for some time.", WORLD.orrenshire)
S.rs_too_far_h = turned("You stop at the edge of the water. It's the best part of three days back to the ward from here, and there's a lamp burning by a bed with nobody to trim it. Not yet. Someone has to sit with Nan first.", WORLD.hayford)
S.rs_too_far_p = turned("The white hill stands up in front of you, and you stop. It's too far. Nobody is sitting with Nan. That comes first, and Orrenshire's the nearest place that might still have people in it.", WORLD.oplinas)
S.rs_too_soon_g = turned("Glamouth stinks of low tide from a mile off. There's a post at the road's end with no notice on it, and you've got a trail of notices to follow. They all point to Oplinas.", WORLD.glamouth, "Not yet, friend. There's a key to see to first, and a gnome who's been waiting a year for it.")
S.rs_too_soon_a = turned("Black country, right to the sky, and the wind is carrying it away a little at a time. There's no notice on anything here. Whoever you're following didn't come this way, or there's nothing left to nail one to.", WORLD.windmill, "Not yet, friend. There's a key to see to first, and a gnome who's been waiting a year for it.")
S.rs_too_soon_ag = turned("The towers stand a long way off through the rain. You've no notice to follow out here, and you're tired of being the only one on the road. There are people still to find, and nothing out here says where. Not yet.", WORLD.agoshull, "Not this way, friend. Not yet. Nobody's told us an owl came this far, and I've walked in enough wrong directions for one year.")
S.rs_too_soon_e = turned("The coast road, and the wind off the sea. You don't feel ready for what's here. You'd want a reason to come, and someone to come with, and you've not got the whole of either yet.", WORLD.evrastin)

-- ---------------------------------------------------------------- waking

S.rs_wake = {
  { dark = true },
  t("There is a place people go, just before they wake."),
  t("You've heard all about it. You still haven't been."),
  t("What wakes you, in the end, is a feeling you haven't had in so long that it takes you a while to find the word. Nothing hurts. Nobody's calling you. You're hungry."),
  warpTo("rs_scythebreak", "a", 2),
  { dark = false },
  t("A ceiling. A long room, grey light, and no sound at all. You're lying in a bed with hospital corners, drawn tight enough to bounce a coin. Your arms take some time to agree that they're yours."),
  t("Your hair has grown. Your nails have been cut, very straight, by someone who has read how. By your hand there's a clean bowl with nothing in it, and a spoon in the bowl."),
  t("You know that spoon. It has a dent in it where it opened a door once. You can't think what it's doing here. You can't think what you are."),
  { choice = {
    { "Call out.", {
      t("Your voice comes out like a hinge. It goes down the ward to the far wall, and nobody sends it back."),
    } },
    { "Get up.", {
      t("It goes badly. The floor is very cold and a long way off. You get to it, and then you get up off it, and that takes longer."),
    } },
  } },
  t("In the next bed someone is lying very straight, which she has never done. Her hands are on the blanket. They're not moving. You'd know those hands anywhere, in the dark, by the smell of flour."),
  { choice = {
    { "Nan?", {
      t("She breathes in. She breathes out. That's all she's doing, and she's doing it the way she does everything, as though someone had said she couldn't."),
    } },
    { "What did you dream?", {
      t("In all those mornings you never once asked her. You wait. You had no idea how long it was, on this side of the question."),
    } },
  } },
  { when = "lied_to_nan", steps = {
    t("The last thing you told her was a lie. A small one, and a nice one. You look at her hands, and you'd tell it again."),
  }, other = {
    { when = "said_goodbye", steps = {
      t("You said goodbye to her once, in this room. You told yourself that was the worst of it."),
    }, other = {
      t("You never came by to say goodbye. You told yourself you'd come back with an answer. Well, you've come back."),
    } },
  } },
  t("Her lips have cracked. Your own have too. The stove at the end of the ward has gone cold, not long since, and there's a sack of oats beside it, and a pot, and nobody."),
  t("You've watched this done every morning of your life, and it turns out you weren't paying attention. It comes out grey. It has lumps in it that you'd want to look at twice."),
  { choice = {
    { "Feed Nan first.", {
      t("You get an arm behind her head, and her mouth opens for the spoon by itself. Somebody has taught her that, a spoonful at a time. You drop a good deal of it. Nobody says a word about the blanket."),
    } },
    { "Eat something, then feed Nan.", {
      t("You eat standing up, and it's the worst porridge anyone has ever made. Then you get an arm behind her head, and her mouth opens for the spoon by itself. Somebody has taught her that."),
    } },
  } },
  { give = "rs_spoon" },
  { set = "rs_woke" },
  { save = true },
  t("Someone did this. Someone cut your nails. There are two cards on a board by the far bed, and one door."),
}

S.rs_t_chart = {
  ask(t("Two bed cards on a board, in a small upright hand. BED FOUR: NAN, OF SCYTHEBREAK. BED FIVE: NUMBER 412, OF SCYTHEBREAK. OUTSTANDING has been ruled through, and over it is written RECEIVED."), {
    topic("Read Bed Four, the old driver's note.", {
      t("It's pinned to the card, on a Clinic waybill. 'Cart 19. Orders stopped coming at the Greywater so I turned round. She wouldn't leave off about my driving, and she never once opened her eyes. She says I'm too thin. Nobody has said so since my mother.'"),
      t("'The night the wall went, every bed on the Adaphis road got up and walked. She didn't. I was sitting with her. I don't say that's why. I say don't leave her alone at night.'"),
    }),
    topic("Read the winter.", {
      t("'Day 240. No coal. Have burned the Clinic's returns for the year in the stove. They gave a very good heat. I find this gave me more satisfaction than it ought. Nobody has asked. I am noting it.'"),
      t("'Day 263. Found a recipe on a slate in Bed Four's house. Salt, it seems. All this time. Both patients took more.'"),
    }),
    topic("Read the last lines.", {
      t("'Day 361. A little short of breath on the stair. Day 363. Oats, third bin, nine days at the present rate. Day 364. Quarter day tomorrow, and the count falls due. There's only the three of us, but the instruction says quarterly.'"),
      t("'Bed Four first, or she gets cross. I know she can't. She does.'"),
    }),
    { "Put it back.", {} },
  }),
}

S.rs_t_nan = {
  { when = "rs_lamp_lit", steps = {
    ask(t("Nan breathes in. She breathes out. You've lit the lamp by her bed. It's about the only thing you've done right."), {
      topic("Tell her what you dreamed.", {
        t("Nothing, Nan. Same as always. You find you've said it aloud, and you find you were waiting for the bit where she's rude about it."),
      }),
      { "Trim the lamp, and go.", {
        t("Up, and a quarter turn. You'll be back."),
      } },
    }),
  }, other = {
    t("Nan breathes in. She breathes out. Whoever's been doing this will be back in a minute, you tell yourself. There's only the one door."),
  } },
}

S.rs_s_clerk = {
  t("The door opens on what's left of the square, and the cold comes in. The great wall isn't where it was. It's lying down, all along the west of the town, and you can see over it. There's a great deal of sky you've never met."),
  t("The Dream Book is still on its stand, under its oilcloth. Beside it a folding chair has been set up, exactly square to the street. A small man is sitting in it, with a satchel on his knees."),
  t("He has a pencil in his hand. He doesn't look up. There's frost on his shoulders, and nothing has disturbed it."),
  { when = "vt_met_clerk", steps = {
    t("You know him. The last time you saw that satchel it was on a shelf of black rock at the edge of the Vault, and he had you down as outstanding. You can't imagine how he got here. Then you see his boots."),
  }, other = {
    t("You know him. He counted the doors of this town at midnight, the night it closed. You can't imagine how he comes to be here. Then you see his boots."),
  } },
  t("There's almost nothing left of them. They've been soled with cut harness, and then with the boards of a book, and then with rag, and the rag has worn through. Someone has walked a very long way in those."),
  t("A ledger lies open on his knee. The last line is dated yesterday, and the hand has got rather small."),
  t("'Quarter day. Doors, 412. Residents, two, and the undersigned. All correct. A little tired. I shall sit for a moment, and then see about the oats.'"),
  { choice = {
    { "Take the ledger from his knee.", {
      t("His fingers let it go quite easily. He has always been very good about handing things over."),
    } },
    { "Close his eyes.", {
      t("They're closed already. He'll have seen to that himself. He never could leave a thing undone. You take the ledger from his knee."),
    } },
  } },
  { give = "rs_ledger" },
  t("Each page has a wide column for the figures, and down the right-hand side a narrow one, for the total. He's been using the narrow one for something else."),
  t("'Day 1. The shelf, Nightmare Vault. Lanterns remaining, none. Column remaining, none. One item fell on the stores at about the fourth hour and is breathing. It is Number 412, of Scythebreak. I have had it down as outstanding for some time.'"),
  t("'I was told to count the column back in. I have been told nothing since. There is a Clinic handcart among the stores. Whatever else may be said of us, a cart has always come back.'"),
  t("'Day 9. Patient's right hand has released the spoon. It objected, in its sleep. That is the only objection I have on file from anyone in sixteen years. I have washed the spoon. I have never fed a person before. It is slower on paper.'"),
  t("You stop reading for a bit. The next part is two hundred days of road, a line for each, with the distance and the weather. Nowhere does he say what it was like. In the narrow column, every so often, there's a word. Rain. Stair. Rain. Sorry."),
  t("'Day 211. Scythebreak. Delivered. Four hundred and twelve out, and one back. Have found Bed Four, and her driver in the chair, a day dead, who has kept her very well and is now under the pear tree. I find I have been crying. There's no column for that. I have put it here.'"),
  { when = "em_counted", steps = {
    t("'I told Number 412 once, in the empty square, that I made it four hundred and twelve out, and one over. It has occurred to me on the road that it was the best sum I ever did.'"),
  } },
  t("'I counted. I should like that noted. I weighed the world for her, and never asked what for, and I have tried every way I know and it will not balance. I have also carried. I should like that noted too.'"),
  t("There's one more page, headed TO THE NEXT CLERK. It's very short."),
  t("'If you are reading this, you'll be 412. Ambrose Thrupp, Counting Clerk, Third Grade. Nobody ever asked, and I find I'd like it written down. Please continue the count. Not the doors. The narrow column. Who's left. Somebody ought to know.'"),
  t("'It is quite restful, if you keep it to the names.'"),
  { choice = {
    { "Write his name in the narrow column.", {
      t("The pencil is about an inch long. You've only ever written one word in anyone's book. You write: AMBROSE THRUPP. And then, because he'd want it noted: CARRIED."),
    } },
    { "Say thank you.", {
      t("It's been a year, and it comes out in pieces. Then you take the pencil, and write in the narrow column: AMBROSE THRUPP. CARRIED."),
    } },
  } },
  { fade = true },
  { set = "rs_carried" },
  warpTo("rs_scythebreak", "a", 2),
  t("You bring him in out of the frost, and it takes you most of the morning. He weighs almost nothing. You can't think how he did it."),
  t("You put him in Bed Six, and you do the corners as well as you can. They aren't very good. He'd have made a small note."),
  t("That leaves the driver's waybill on Bed Four, and it's easy to remember. Don't leave her alone at night. There are nine days of oats, and you can't lift her. And there's nobody in this town who isn't you."),
  t("Orrenshire's half a day up the road, if there's still an Orrenshire. You light the lamp by her bed, the way someone must have. Up, and a quarter turn. Wick would have been ashamed of you."),
  { set = "rs_lamp_lit" },
  { save = true },
}

S.rs_t_chair = {
  t("A folding chair, exactly square to the street."),
}

S.rs_t_book = {
  t("The Dream Book, under its oilcloth, tied with a good knot. The last pages are in a new hand, small and upright. He's been keeping it up. Every quarter day, for all the doors: 'Nothing to declare.'"),
  { when = "rs_declared", steps = {
    t("Under the last of his, in a much worse hand: 'Woke up. Very hungry. {hero}.' You stand by it."),
  }, other = {
    { when = "rs_carried", steps = {
      { choice = {
        { "Declare something.", {
          t("There's a pen on a string. 'Woke up. Very hungry. {hero}.' It's only the second thing you've ever declared."),
          { set = "rs_declared" },
        } },
        { "Leave it.", {} },
      } },
    } },
  } },
}

S.rs_t_cart = {
  t("A Clinic handcart stands in the yard, with its shafts on the ground. It's been scrubbed. Of course it has. Someone has cut down the harness to fit a very small man, and it's worn through at both shoulders and been stitched, and worn through again."),
  t("The bed of it has been padded with folded forms. There's a hollow in them, about your length."),
}

S.rs_t_house = {
  { when = "wm_got_dish", steps = {
    t("Nan's door still sticks. The fence still wants mending. The slate is on its nail."),
    { when = "rs_dish_home", steps = {
      t("The pie dish is back on its shelf, with the chip to the wall. It's the only thing in the town that's where it belongs."),
    }, other = {
      { choice = {
        { "Put Nan's pie dish back on the shelf.", {
          { take = "wm_pie_dish", n = 1 },
          t("It goes back with the chip to the wall, the way she keeps it, so that nobody will ask. You stand there with your hand on it for a bit."),
          { set = "rs_dish_home" },
        } },
        { "Keep it with you.", {
          t("It goes back in your coat. You'll bring it to her yourself."),
        } },
      } },
    } },
  }, other = {
    t("Nan's door still sticks. The fence still wants mending. The slate is on its nail, and under the shopping someone has added, in a small upright hand: 'Salt. Noted with thanks.'"),
  } },
}

S.rs_t_chalk = {
  { when = "kid_kind", steps = {
    t("The chalk has mostly gone from the yard wall. The rain's had it. Low down, the one line that was out of the weather: 'ITS QUIET. {hero} SAYD.'"),
    t("You'd give a good deal to have said something else."),
  }, other = {
    { when = "kid_snub", steps = {
      t("The chalk has mostly gone from the yard wall. There's the tall person with the scribbled face, still lying very still. You're fairly sure you've earned that."),
    }, other = {
      t("The chalk has mostly gone from the yard wall. The tall thin man is still there in his corner, in his hat. Somebody's rubbed out the corner."),
    } },
  } },
}

S.rs_t_pole = {
  t("A lamp at the end of the street, and a pole leaning by it. It's been lit every night for months by someone who didn't know how, with the wick cut far too long."),
  t("Tonight nobody has lit it."),
  { choice = {
    { "Light it.", {
      t("It takes two tries. It's getting easier, and you wish it weren't."),
    } },
    { "Leave it.", {} },
  } },
}

-- ---------------------------------------------------------------- Orrenshire

S.rs_s_orrenshire = {
  t("Orrenshire is still there. It's the first thing you've seen with its roofs on. Every lamp in the town is lit, in the middle of the day, and it's the most beautiful thing you've ever seen."),
  gnome("Halt! State your name, your business, your height, and whether you have at any time today been asleep! Take your time! I've found the form!"),
  { choice = {
    { "I've been asleep for a year.", {
      gnome("For a... all in one go? A YEAR? Oh, you monster. Was it soft? No! Don't tell me! I've got a wife!"),
    } },
    { "You're still doing this?", {
      gnome("Still? Still, the tall one says! Day three hundred and sixty-seven! It's the only reason any of us are here!"),
    } },
    { "Please. I need help.", {
      gnome("Well, why didn't you say? There's a form, but I can just shout. MAYOR! IT'S A TALL ONE! AND IT'S SAD!"),
    } },
  } },
  gnome("Wait a moment. I know you. You're dead! I've got you in the minutes! Go up to the Mayor, you'll want to get that corrected before Friday."),
}

S.rs_t_gate = {
  gnome("Ordinance Forty, as amended: nobody sleeps unless someone's sitting up with them, and whoever sits up is shouted at, kindly, on the hour. It's a very tiring town. I've never been so happy."),
}

S.rs_t_notice_o = {
  t("A notice nailed to the post, in a doctor's terrible hand. It's been up for months. The rain has been at it, and someone has inked the letters back in."),
  t("'LOST. ONE FRIEND. TALL. DOES NOT DREAM. ANSWERS TO {hero}. MAY BE CARRYING A SPOON. IF FOUND, TELL THEM THE DOCTOR WANTS IT BACK.'"),
  t("You read it three times. You find you have to sit down on the edge of the horse trough, which is rather low."),
}

S.rs_t_mayor = {
  { when = "rs_sitters", steps = {
    { when = "rs_done", steps = {
      mayor("She's sat with, and she'll stay sat with. That motion doesn't lapse. Go on, you great long thing. Mind the lamp."),
    }, other = { { when = "rs_dole_down", steps = {
      mayor("You've brought them back alive, I see, and the owl's already corrected the Committee's arithmetic. Go through. She's been waiting. I know she can't. She has."),
    }, other = {
      ask(mayor("Your Nan's in the east ward, and well sat with. Now then, I'm in the middle of a speech. It's Tuesday's."), {
        topic("How are the sleepers?", {
          mayor("Eleven tags on the wrong side of the board, and not one has stirred in a year. That's what a town is for. I said that once as a figure of speech. I've had it carved over the door."),
        }),
        { "Carry on, Mayor.", {} },
      }),
    } } } },
  }, other = {
    t("The Mayor is standing on a box. She's thinner, and very much smaller, and she stops halfway through a sentence, which you hadn't known she could."),
    mayor("Point of order. You're dead. I moved it myself, with a very moving speech. Oh, come here, you great long thing. Mind the lamp."),
    t("She can reach about as high as your elbow. She takes hold of it, and holds it for a while, in front of the whole Committee."),
    ask(mayor("Strike that from the minutes. Now. You've got the look of someone with something to say. Everyone has. I've got a speech."), {
      topic("What happened here, when the wall fell?", {
        mayor("Every sleeper in Embia sat up at once, and got out of bed, and went for a walk. We call them the Early Risers. They've got their eyes open. They're ever so polite. You'll want to stay out of reach."),
        mayor("But I had eleven tags in my ward, with that sister's thread on them, and a gnome on a chair by every bed, because I'd said we'd keep them warm. Not one of those eleven got up. Do you see?"),
        mayor("It's only the ones who were left alone. So: Ordinance Forty, as amended. It carried in four seconds."),
      }),
      topic("Have you seen any of the others?", {
        mayor("That notice on the post? Scar, no sleep, terrible handwriting. Came through in the autumn, wouldn't eat, wouldn't sit, and asked after you nine times. Then it was east, to nail up some more of those."),
        mayor("Hayford and then Oplinas. The doctor's not the sort to stop, you know. I've been told that I'm not either. It takes a town to tell."),
      }),
      topic("Why was I in the minutes as dead?", {
        mayor("You stopped turning up, and then the world ended, and I put two and two together. I thought we owed you a good speech. It ran to eleven days. You'd have hated it."),
      }),
      { "My Nan's alone at Scythebreak. Please.", {
        t("You tell her about the ward, and the driver's note, and the man in Bed Six. It doesn't take long. She gets down off the box, which you've never seen her do without a motion."),
        mayor("How long has she been alone? Since this morning? Then I've no time for a quorum."),
        mayor("I move that the town of Orrenshire go and fetch an old woman! All those in favour!"),
        t("It carries before she's finished saying it. Nib has the whole shift turned out by the time you reach the door. Six gnomes go down the road at a dead run with a stretcher built for someone a good deal shorter."),
        { fade = true },
        t("They have her back by dark. They carry her into the east ward and the whole shift stands up. Pip has already got the chair. Pip got the chair before anyone asked."),
        mayor("There. She'll not be left. It's the first thing anyone's asked this town for all year that we actually had."),
        { when = "drew_fire", steps = {
          mayor("And Orrenshire remembers its debts, in triplicate. You kept their eyes on you and off us. Take these. The motion's already carried."),
          { give = "xpotion", n = 2 },
        }, other = {
          mayor("And take these, for the road. Don't argue. I've got a motion that says you won't."),
          { give = "hipotion", n = 3 },
        } },
        { set = "rs_sitters" },
        { save = true },
      } },
    }),
    mayor("Now go and find that doctor, before the doctor runs out of posts. East, over the Greywater. We'll be here. We're always here. We can't seem to stop."),
  } },
}

S.rs_t_nib = {
  { when = "can_travel", steps = {
    nib("The line's running! Station to station, anywhere you've been! Nob's got the far end, and he says it was his turn to get it working. It was not. I have that in writing."),
  }, other = {
    ask(nib("Mind the rails. That's the lift line. We've run it out under the Greywater this past year, cart road and old shafts, every town from here to the sea. It's the safest road in the Heart, and it doesn't go."),  {
      topic("Why doesn't it go?", {
        nib("No key. There's one winding key for the whole line, and in the last audit the Clinic came and impounded it, with a form, and put it in their Annexe at Oplinas. Nob's at that end, sulking over a very long hole."),
      }),
      topic("Who's the Annexe, these days?", {
        nib("Nobody. That's what's wrong with it. It's still doing the rounds."),
      }),
      { "I'll keep an eye out for it.", {
        nib("You do that. Tell Nob it's his turn."),
      } },
    }),
  } },
}

S.rs_t_pip = {
  { when = "rs_dole_down", steps = {
    pip("She's had her oats. Salt in them, the way it says on the slate. I've told her about my day. I think she liked the bit about the goat."),
  }, other = {
    ask(pip("I've got the night shift and the day shift. I told them I don't mind. I know how it goes. My mum came back, you know, when everyone said she wouldn't."),  {
      topic("Does she ever stir?", {
        pip("No. But I told her I hadn't had breakfast, and I'd swear she breathed in crossly."),
      }),
      { "Thank you, Pip.", {
        pip("Is it true she asks everyone what they dreamed? I've been telling her anyway, in case. Somebody ought to ask."),
      } },
    }),
  } },
}

S.rs_t_lump_held = {
  { when = "rs_lump_met", steps = {
    lump("Quiet shift. You can't ask more than that."),
  }, other = {
    t("A very large man is sitting on a very small chair by a sleeper's bed, playing patience on the blanket."),
    lump("You. From the second level. You said I'd stand in front of the Mayor. I did. She gave me a chair. It's been a while now, and the door was never locked. I just never left."),
    lump("I hooked those casks up. I never asked what was in them. So I sit with what came of it. My eleventh's a gnome called Old Bruddle. He cheats. He's been asleep for a year and I don't know how."),
    { set = "rs_lump_met" },
  } },
}

S.rs_t_lump_home = {
  { when = "rs_lump_met", steps = {
    lump("Girls are at the school. There's a school. There's always tea."),
  }, other = {
    t("A big man in a clean shirt sits by a sleeper's bed, with a very small girl asleep on his arm and another sitting up to keep an eye on her."),
    lump("You told me to go home, and I went. I want you to know that. I had a year of the school run. Then the wall came down, and Bess went to sleep that night by herself, because I'd gone down to see to the horse."),
    lump("So I walked the girls to the one town that sits up. I thought they might owe me a chair. They said they didn't, and gave me one anyway."),
    { set = "rs_lump_met" },
  } },
}

S.rs_t_smith = {
  ask(smith("Well, it's not what I'd call the good stuff. It's what I can make out of a wall. Turns out they built that thing out of the best iron in the world, and left it lying about."), {
    { "Show me what you've got.", {
      { shop = "rs_smith" },
    } },
    { "Not today.", {} },
  }),
}

S.rs_t_inn = {
  ask(innkeeper("Bed and a sitter, a hundred and fifty. You'll have Mistress Oddie. She knits, she doesn't talk, and she'll shout at you, kindly, if you start smiling in your sleep."), {
    { "A bed. (150 gold)", {
      { inn = 150 },
      { save = true },
    } },
    { "Not tonight.", {} },
  }),
}

-- ---------------------------------------------------------------- Hayford

S.rs_s_hayford = {
  t("The island has gone down at last. Hayford stands to its eaves in brown water, with planks laid from roof to roof, and fat grey reeds growing up through the Cornucopia's collection plates."),
  { when = "side_frogs", steps = {
    t("There are lights in the windows. There are ducks. A frog in a good hat is rowing a boat full of humans across the high street, and charging them for it. You could weep."),
  }, other = {
    t("Most of the windows are dark. Green shapes move on the planks with long poles, and they don't look round at you. Nobody here is rowing anyone anywhere."),
  } },
  { set = "rs_hay_seen" },
}

S.rs_t_bogg = {
  { when = "side_frogs", steps = {
    askUntil("rs_doc_back", bogg("A tall party! Sir or madam, you find Hayford in rude health. The Return is restored, and the swamp has simply returned rather more of the town than we'd budgeted for."), {
      topic("How did Hayford come through?", {
        bogg("The partnership, sir. A frog sleeps with its eyes open, it's the merest habit, and we've no end of cousins. Every human in this town has a frog on the end of the bed, at very reasonable rates."),
        bogg("It seems nobody gets up, so long as somebody's looking. Friend Tolliver has it in the contract. He calls that the finest clause he ever wrote, and he didn't write it. He only noticed he could charge."),
      }),
      topic("Did a doctor come through?", {
        bogg("With a hammer! Nailed one up on my own front plank without a by-your-leave. I'd have sent a bill, but I saw the face. I've left it up. I had it varnished."),
      }),
      { "Thank you. Stay damp.", {
        bogg("Always. A pool was cleared for me once, you know, and I've not forgotten it. Mind the duck."),
      } },
    }, 2),
  }, other = {
    askUntil("rs_doc_back", bogg("Tall party. You'll forgive me if I don't get up. There was a town here, and I'd a mind to have it to dinner. Well. The swamp's had it instead."), {
      topic("What happened here?", {
        bogg("Offertory Night, the night it broke. They'd all gone to bed full and locked their doors. Humans do love a lock. We came up in the morning and every door stood open, and they were walking away north, in their nightshirts."),
        bogg("A frog sleeps with its eyes open, so I saw it. I called after them. I don't know why I should have minded so. We'd been robbing them for thirty years."),
      }),
      topic("Did a doctor come through?", {
        bogg("With a hammer. It's on the plank. I'd have sent a bill, but there's nobody left to take it to. I've left it up. It's something to read."),
      }),
      { "I'm sorry.", {
        bogg("So am I, and at no charge. I find that's the most disturbing part."),
      } },
    }, 2),
  } },
}

S.rs_t_notice_h = {
  t("Nailed to a plank, a little newer than the last. 'LOST. ONE FRIEND, TALL, AS BEFORE. WILL ALSO ANSWER TO FRIEND. SPOON IS SIGNED OUT, AND THERE WILL BE A FORM.'"),
  t("Under it, smaller: 'If you've found this yourself, you great lump, I've gone on to Oplinas. They'll have bandages. Stay where you are. Eat something.'"),
}

local FARTHING_NOTICE = {
  { "Yes. Please read it.", {
    t("She gets it out of the ledger, and reads it aloud in a flat clear voice, with her finger under the words. It's a letter to you. It's mostly about eating."),
    farthing("That's the whole contract, discharged. I don't do on the house. But it's a funny thing. Nobody's ever paid me in advance before. They all thought I'd be here."),
  } },
  { "No. I've read it.", {
    farthing("I'll keep the four coppers, then. I don't do refunds. I've thought about it, and I don't."),
  } },
}

S.rs_t_farthing = {
  { when = "rs_paid_farthing", steps = {
    ask(farthing("You've got credit. I've looked. It doesn't stop being strange."), {
      { "Show me what you've got.", { { shop = "rs_farthing" } } },
      { "Nothing, thank you.", {} },
    }),
  }, other = {
    t("A person of about ten, with a ledger bigger than her head, is sitting at the window of the Tolliver Exchange, above the water line."),
    farthing("Conversation's two coppers a sentence now. It's the shortage. That one was free, because you look like you've stopped eating. So was that."),
    { when = "rs_doc_back", steps = {
      ask(farthing("That scarred person paid me four coppers to read a notice out to anyone tall. Prepaid, one year. Standing there doesn't void it. Do you want it read?"), FARTHING_NOTICE),
    }, other = {
      ask(farthing("A scarred person paid me four coppers to read a notice out to anyone tall. Prepaid, one year. You're the only one who ever came. Do you want it read?"), FARTHING_NOTICE),
    } },
    { set = "rs_paid_farthing" },
    ask(farthing("I've got a shop, if it's any use to you. Mostly what people left."), {
      { "Show me what you've got.", { { shop = "rs_farthing" } } },
      { "Not now.", {} },
    }),
  } },
}

S.rs_t_ambry = {
  { when = "side_frogs", steps = {
    ambry("All gifts return. I've preached that for thirty years. I should like it noted that I'm as surprised as anyone."),
  }, other = {
    ambry("All gifts return. They do, you know. It's the people I've had trouble with. Blessings are complimentary now. There's nobody to invoice."),
  } },
}

S.rs_t_hat = {
  { when = "side_frogs", steps = {
    t("A jetty post has been carved into a very good likeness of Mayor Tolliver, with a real hat on it. There's a slot for coins in the waistcoat. It's doing quite well."),
  }, other = {
    { has = "hr_hat", steps = {
      t("A bare jetty post, with a ring in the moss at about the height of a hat. You've still got Tolliver's. There's nobody left to hand it to."),
    }, other = {
      t("A hat hangs on a jetty post, very damp, with a smell of duck. Tolliver's. It's the only thing in Hayford he didn't take a percentage of. Someone has been keeping the moss off it."),
    } },
  } },
}

S.rs_t_lucky = {
  { when = "side_frogs", steps = {
    lucky("Row you anywhere in the town for a copper, sir? Only the town stops here."),
  }, other = {
    t("A young frog sits on the end of the pier with a pole across its knees, and its eyes open. It's looking north, where they went. It doesn't blink. They don't."),
  } },
}

-- ---------------------------------------------------------------- Oplinas

S.rs_s_oplinas = {
  t("Oplinas still climbs its hill, but the scaffolding's gone for firewood. The Clinic's flag hangs from the gate, washed and very clean, and over the top of the hill one tall grey building has all its lamps lit."),
  t("Everyone else in the city is living in the bottom four streets, with a great many fires, and a very small number of people sitting up beside each one."),
  { set = "rs_op_seen" },
}

S.rs_t_crue = {
  t("Gate-Sergeant Crue is at his post, with his hand out. His eyes are open and his buttons are done up. Someone has wound a scarf round his neck against the cold."),
  crue("Papers."),
  { choice = {
    { "Show him the ledger.", {
      crue("Papers."),
      t("He doesn't look down. He's got nothing behind his eyes but the one word. It's probably the most at peace you've ever seen him."),
    } },
    { "Walk round him.", {
      t("Everyone does. There's a path worn in the stones."),
    } },
  } },
}

local IONE_FEUD = topic("How are the refugees and the Heartlanders?", {
  ione("Oh, we still hate each other. It's the only thing we've kept up. But you need somebody to sit up with you, and you find you'd rather it was someone you can argue with."),
})

S.rs_t_ione = {
  { when = "rs_cart_down", steps = {
    ask(ione("Fires, please, not lamps. I know the hill's gone dark. The first quiet night in a year, and I've four streets of people who won't believe it. Neither do I."), {
      IONE_FEUD,
      { "Keep warm, Speaker.", {
        ione("That's the whole of my programme."),
      } },
    }),
  }, other = {
  askUntil("rs_doc_back", ione("Fires, please, not lamps. We can't spare the oil. I'm Speaker of four streets now, and I've never had so few complaints or so many people sharing a bed."), {
    topic("Who's up in that grey building?", {
      ione("The Annexe. Everyone who was in it the night the wall came down, and every one was alone at their desk. So they got up, and they went on with it. The bell goes for rounds. A cart comes out at first light."),
      ione("We've lost eleven people to that cart. It isn't cruel about it. It waits at the bottom of the hill for anyone on the sheet. They've got everyone on the sheet."),
    }),
    topic("Have you seen a scarred doctor?", {
      ione("We've all seen the doctor. Set Wenna's arm, and told my sister to eat something, and looked at our last roll of bandage as if it had made a personal remark. Then the doctor walked up that hill with a form. That was three days ago."),
      ione("The form said 'stores requisition'. I'd have stopped it, but there's no stopping that one. I think you may know that."),
    }),
    IONE_FEUD,
    { "I'm going up there.", {
      ione("Yes. You've got the same look. There's nothing I can give you but a warning: don't let them put you on the sheet as anything that gets looked after."),
    } },
  }, 2),
  } },
}

S.rs_t_wenna = {
  { when = "hr_tied_aude", steps = {
    wenna("Soup. It's mostly water, but it's hot water, and I've called it soup, so don't start. Old Aude's still with us, across the way. Your sister's thread's on her yet. She's not stirred, and she's not got up."),
  }, other = {
    wenna("Soup. It's mostly water, but it's hot water, and I've called it soup, so don't start. I've got a mage on my left who says it wants thyme. I may hit her. It's been a long winter, and it's nice to have a hobby."),
  } },
}

S.rs_t_aude = {
  { when = "hr_tied_aude", steps = {
    t("Old Aude lies in the warm by the fire, very small. There's a black thread on her wrist, knotted in a way you know. Someone's been re-tying it, badly, with great care."),
  }, other = {
    t("A very old woman lies in the warm by the fire. A refugee mage on one side and a Heartlander farmwife on the other are having a low, bitter argument about whose turn it is."),
  } },
}

S.rs_t_vance = {
  ask(vance("You'll excuse me. I'm reading. It's a shelf a day. I burn it after, for the fires. I've agreed to that, but I'm going to read them first. Nobody's going to say they went unread."), {
    topic("What became of the library?", {
      vance("It's keeping four streets warm. The Treatises on Faith went in the first week. They burned very poorly. The poets were excellent."),
    }),
    { "Keep reading.", {
      vance("Thank you. Nobody ever says that. I shall put it down as the high point of my career."),
    } },
  }),
}

S.rs_t_notice_p = {
  t("The last notice. The nails are new. 'LOST. ONE FRIEND. YOU WILL KNOW WHO YOU ARE. I'VE GONE UP TO THE ANNEXE FOR BANDAGES, AND I'LL BE ONE HOUR.'"),
  t("Under that, later, the ink not quite the same. 'If you're reading this it's been more than an hour.'"),
}

S.rs_t_nob = {
  { when = "can_travel", steps = {
    nob("Going anywhere? Tell Nib it's his turn. I'm only saying."),
  }, other = {
    { has = "rs_winding_key", steps = {
      t("Nob takes the key in both hands. It's as long as he is. He looks at it for a while, and then he looks at the very long hole."),
      nob("Well. It's about time somebody did something around here. It wasn't Nib, I'll tell you that."),
      t("He sets it in the winding head and leans on it, and his feet come off the floor. Somewhere under the hill a great many teeth find each other. Then a sound comes up the shaft that nobody here has heard for a year: something going where it's meant to."),
      { sfx = "door" },
      { take = "rs_winding_key", n = 1 },
      { big = "THE LINE IS RUNNING" },
      nob("Every town we've got a shaft under! Anywhere you've already been, you can be there by dinner! Just ask at the map! I mean the TRAVEL page. It's on your... it's what we're calling it!"),
      doc("A railway that the Clinic didn't build. I'd like to sit in it and do nothing for an hour. Friend, before we go anywhere, there's something I've got to tell you about the scholar."),
      ask(doc("We came up out of that hole together, and it took a month. I had the scholar on my back for the last of it. Do you want it now, or after you've eaten?"), {
        topic("What happened to the scholar?", {
          doc("'I can carry one,' the scholar said, and then did, for eleven hours, straight up, with me hanging off one claw. Owls aren't built for that. I set the left wing on a kitchen table. I set it badly. It doesn't open."),
        }),
        { "Where's the scholar now?", {
          doc("I don't know. We came to Glamouth in the summer. The scholar had a thought to disprove, the one from Evrastin, wouldn't say what, and took passage west. I'd got a great many posts to get to. So we parted, and we were very rude about it. I'd like to fix that."),
        } },
        { "Now. Tell me all of it.", {
          doc("We came to Glamouth in the summer. The wing's broken for good, friend. I set it. The scholar had a thought to disprove, and took passage west. We were very rude to each other about it. I'd like to fix that."),
        } },
      }),
      doc("Glamouth first, then. Someone there will know what ship. Let's go and find out how much trouble an owl can get into on foot."),
      { set = "can_travel" },
    }, other = {
      nob("It's a very long hole. That's all I'll say. If you'd come with a key I'd have more to say. I've a whole speech. Are you going to the Annexe? Everyone goes to the Annexe. Nobody brings anything back."),
    } },
  } },
}

S.rs_t_stair = {
  t("The stair goes up to the Annexe doors between two rows of white lamps, each one full of good clean oil. They're the best-kept lamps you've seen in a year. The steps have been scrubbed."),
  t("A long way up, quite distinctly, someone rings a small handbell. It's time for rounds."),
}

-- ---------------------------------------------------------------- the Annexe

S.rs_t_door_orderly = {
  { when = "rs_a_written", steps = {
    ward("Good evening. Are you on the sheet? Ah. A transfer. Nobody counts a transfer. Do go through."),
    t("He steps aside, and goes on standing there, facing the wall."),
    { set = "rs_a_signed" },
  }, other = {
    { when = "rs_a_entered", steps = {
      ward("Are you on the sheet? I'm so sorry. I can't let you up unless you're on the sheet. There is one by the bell, in the treatment room, if you'd care to enter yourself."),
    }, other = {
      t("A young orderly stands square in front of the east door, with a clean bandage where he must once have had some other reason to be here. His eyes are wide open and very pleasant. He isn't looking at you."),
      ward("Good evening. Are you on the sheet? I'm so sorry. I can't let you up unless you're on the sheet. There is one by the bell, in the treatment room, if you'd care to enter yourself."),
      { set = "rs_a_entered" },
    } },
  } },
}

S.rs_t_sheet = {
  { when = "rs_a_written", steps = {
    t("The sheet, in the same round hand all the way down. Your own entry looks like something a child would do."),
  }, other = {
    t("The ward sheet, on its board, with a pencil on a string. Rounds at the hour. Every line has a name, a tick, and a word in the last column. Patient. Visitor. Staff. Transfer. Most of the words are 'Transfer'."),
    t("You remember someone telling you about that word. 'Every patient gets a bed. After that you'd have been a transfer, and nobody counts a transfer.'"),
    ask(t("There's a blank line at the foot of the page. What do you put?"), {
      topic("Patient.", {
        t("You write it, and the sheet takes it, and from somewhere overhead come soft quick steps, hurrying to see to you. You rub it out, very fast. The steps stop and wait."),
      }),
      topic("Visitor.", {
        t("You write it. 'Visiting hours are over,' says a pleasant voice from nowhere in particular. You rub it out."),
      }),
      { "Transfer.", {
        t("You write it. It's a horrible word. It sits on the page as if it had always been there. Nothing comes."),
        { set = "rs_a_written" },
      } },
      { "Leave it blank.", {} },
    }),
  } },
}

S.rs_t_bell = {
  t("A small brass handbell on a clean cloth, with a chit under it. PLEASE RING FOR ATTENTION. There's a dent in the cloth where it's been lifted and set back, at the hour, every hour, for a year."),
}

S.rs_t_bed_a = {
  t("Every bed in this ward has been made up tight. There's a tag on this one in the round hand. Cart 7. Bandages: nil. Stores: nil. Stores requisition received from a former officer, and filed."),
}

S.rs_t_tray = {
  t("A tray of instruments, laid out square. Every one's been boiled. There's soup on a spirit lamp nearby, gone to black glue in the pot, and a clean bowl, and a chit in it. FOR THE PATIENT IN SEVEN."),
}

S.rs_t_wall = {
  t("Someone in this cell has been scratching a tally on the wall. It goes on for four walls and starts again. They've ruled a line under it, and written: CARRIED FORWARD. You've seen that done."),
}

S.rs_t_scratch = {
  t("An empty cell with a tin plate on the floor. Someone has written on the plate, with a nail: 'EAT SOMETHING'. You can't think who'd do that in a place like this. Then you can."),
}

S.rs_t_cell = {
  t("Cell seven. The door's open. There's a bent fork on the floor, in about the state you'd expect."),
}

S.rs_s_lock = {
  t("The corridor is very clean and very quiet. The lamps burn. Then, somewhere just ahead of you, you hear a small scratching sound."),
  t("You stop. You know that sound. You heard it once, in the dark, through the door of a room with a bed, a bucket and a very clean floor."),
  t("Someone is working at a lock. Badly."),
  doc("Hold still, you miserable little... no. No. It's got far too many points. You can't be expected to work under these conditions. Who makes a fork out of this?"),
  t("It's coming from behind the door of Cell Seven, from the inside. It stops for a moment. There's a sigh, and a small clang, and it starts again."),
  { choice = {
    { "It's a delicate instrument.", {
      t("It doesn't come out very loud. Your voice still isn't what it was, and your throat's doing something. The scratching doesn't stop. It just slows down, as if someone had started listening to something else."),
    } },
    { "Say nothing. Get out the spoon.", {
      t("It's in your coat, where it's been since the ward. You find you can't quite see what you're doing."),
    } },
  } },
  t("You put the handle to the lock. Up, and a quarter turn. You only saw this done once, by someone who was terrible at it. You're worse. It takes a very long time, and all that time, from the other side, there isn't a sound."),
  { sfx = "door" },
  t("The door opens on a patient's gown tied at the back with a proper knot. Above it is a long scar, and a face that has been awake for about two years."),
  doc("Orderly, I've told you. I'm not on your..."),
  t("The doctor stops. The doctor looks at your face. Then, for a good while, at the spoon. Nobody says anything. You had a great many things to say, and you've mislaid them."),
  doc("You've bent it."),
  t("A hand comes out and takes hold of the spoon. It takes hold of your hand as well, and it doesn't let go. You've heard about this in stories. This time it isn't a spoon's length. This time it's no distance at all."),
  doc("I said I'd want that back. I said so. You heard me. Do you know how many posts there are in the Heart?"),
  { take = "rs_spoon", n = 1 },
  { join = "deserter", lvl = 32 },
  { set = "rs_doc_back" },
  ask(doc("Look at you. You're thin. Oh, friend. You're as thin as a... who's been feeding you?"), {
    topic("A small man with a satchel. He carried me home.", {
      t("You hold out the ledger. The doctor reads for some time, standing up, in a hospital gown, with one finger under the lines. At 'Sorry' the finger stops."),
      doc("I've met a hundred of him. I used to be afraid of the soldiers, and after that it was the ones with satchels who scared me."),
      doc("I'd like that struck out, please. Ambrose Thrupp. Third Grade. Two hundred and eleven days. He'd have needed a form for the shoes."),
    }),
    topic("Nan's alive. She didn't get up.", {
      doc("She's... the old woman? Your Nan? Alive, and fed? Friend, they had her down for Adaphis, I saw the card. Who..."),
      doc("Never mind. Never mind who. Don't tell me yet. Give me a moment. I've spent a year telling myself that's one I didn't get to."),
      doc("I can't mend her. I'll tell you that now, so nobody else has to. But I'd like to take her pulse, and be rude to her, if I may."),
    }),
    topic("Why would you come up here alone?", {
      doc("For bandages. I'd a whole hill full of people on a last roll of bandage, and I told myself I knew the regulations. I walked in with a form. They took it. They were delighted. They gave me a bed."),
      doc("I've been on the wrong side of that door for three days, and they've been so very kind. It's a dreadful thing to find out from the inside, what you did to people for eleven years with a clipboard."),
    }),
    { "Let's get out of here.", {
      doc("Yes. Yes, quite right. In a moment. There's a cart at first light, and I'm on the sheet. I know the way to the yard, friend. I've walked it eleven times."),
    } },
  }),
  doc("And before you ask, no, I don't have a scalpel. I've got you. Come on."),
  { save = true },
}

S.rs_s_cart = {
  { when = "rs_doc_back", steps = {
    t("The yard door stands open on a grey sky. It's nearly first light. In the middle of the yard stands a closed Clinic cart, scrubbed white. There's nothing between the shafts. There's a bell on the tailgate."),
    doc("Oh, there you are. I wondered who was driving."),
    t("Nobody is. All round the yard, the windows are full of people with their eyes open, in very clean uniforms. Nobody's looking at you. The tailgate lowers itself, gently, on a smell of lavender and boiled linen."),
    doc("Do you know what comes back from Adaphis? The cart. I never told you what was inside. Friend, there's no need for this to be pleasant."),
    { battle = "rs_b_cart" },
    t("It goes over slowly, with its wheels still turning. The tailgate hangs open. There's nothing in there at all, not a mark, not a smell. It really is very clean."),
    t("All round the yard the faces go out of the windows, one at a time, like lamps. The bell rolls a little way across the stones. Nobody picks it up."),
    t("Hanging from a hook in the roof of the cart, tagged and signed for, is a long iron key."),
    doc("'Impounded, one key, winding, gnomes for the use of.' I signed for a lot of these. Help me with the stores, friend. I came up here for bandages and I'm not going home without them."),
    { give = "rs_winding_key", n = 1 },
    { give = "hiether", n = 2 },
    { set = "rs_cart_down" },
    { fade = true },
    warpTo("rs_oplinas", "m", 2),
    t("You come down the hill with your arms full of clean linen. By the time you reach the fires everyone on the bottom four streets is standing up, not saying anything, looking at the top of the hill. For the first time in a year, the Annexe has gone dark."),
    doc("Well. That's one, then. Let's get that key to the gnome. And friend, the first thing you eat, I want to watch."),
    { save = true },
  }, other = {
    t("Beyond the door there's a yard, and something big and white standing in it. You don't care to go any nearer on your own. Somebody's in this building. Somebody with a form."),
  } },
}

-- ---------------------------------------------------------------- Glamouth

S.rs_s_glamouth = {
  t("The sea has gone out at Glamouth, and it hasn't come all the way back. The harbour's a long grey slope of mud with the ships lying on their sides, each with a flag that belonged to someone else, and a family living in it."),
  doc("We parted on that quay, the scholar and I. I said something about the arithmetic of a one-winged owl. Then I went and hit a post with a hammer for a while."),
  { set = "rs_gl_seen" },
}

S.rs_t_poster = {
  t("The old poster's still on its post. WANTED, ALIVE. A TALL PERSON OF NO DREAMS, AND ONE HERBALIST. ONE THOUSAND GOLD. THE SAME AGAIN IF DELIVERED UNBLED."),
  { when = "wore_hat", steps = {
    t("IN A VERY BAD HAT, it still says, in pencil. Someone has added, in a different pencil: WHATEVER HAPPENED TO THAT HAT."),
  } },
  doc("Payable by a queen who's no longer in a position to pay. I'd like it for my wall. It's the only reference I've ever had."),
}

S.rs_t_wren = {
  { when = "rs_wren_asked", steps = {
    wren("I said the mill. Do you want it in writing? That's extra. You've still got your buttons. I've checked."),
  }, other = {
    { when = "rs_doc_back", steps = {
      t("A small person bumps into you, says sorry, walks on, and stops. She's grown a hand or so, and she's wearing a great many keys and somebody else's hat."),
      wren("Harbourmaster. There wasn't anyone else. There's no harbour either, so it works out. You two aren't dead, then. There goes a good story. What d'you want?"),
      ask(wren("I'll tell you one for free. I've gone off selling them. Nobody's got anything I want."), {
        topic("How did Glamouth come through?", {
          wren("Every ship's got an anchor watch. Always has done, or someone steals your ship. So there was always one awake. Turns out that's all it took. Crew stayed in their hammocks. It's the first time anyone's said we were lucky to be thieves."),
        }),
        { "An owl took a ship west, in the summer.", {
          wren("The owl! Walked like a sack of very angry books. Yes. It paid a berth on the Second Mortgage for the Evrastin road, with a thing out of its own head, a silver band or something, and the Captain's still got it. They sailed on the last water we had."),
          wren("And nothing's come back. Nothing goes that far now, not with the sea like this. Ask the Captain if you like. But if you want to know where a thing put in, it's only the birds go over there. Ask at the mill. They've picked at everything."),
          { set = "rs_wren_asked" },
        } },
      }),
    }, other = {
      wren("Harbourmaster. There wasn't anyone else. Mind your buttons."),
    } },
  } },
}

S.rs_t_drum = {
  { when = "rs_wren_asked", steps = {
    t("Captain Drum has moved her desk into the keel of someone else's ship. She has a silver band on the blotter, and she's looking at it as if it had said something rude."),
    drum("The owl's. A spare, it says, for its head, and worth a berth to anyone with sense. I've not had the heart to sell it. There's nothing else in this town I've not sold."),
    drum("Forty-two years at sea and I've never yet seen water leave. If you find that ship, tell the mate it's his turn to pay me. And tell that owl it talked my crew's ears off for a week, and that they've been asking after it."),
  }, other = {
    drum("You'll be wanting something. Everyone does. Ask the child with the keys. It's her harbour. I only own it."),
  } },
}

S.rs_t_keel = {
  { when = "rs_keel_met", steps = {
    keel("I'm still here. So is the invoice. Do mind the mud. It's so difficult to get out of grey."),
  }, other = {
    t("At the end of the quay a tall woman in a grey coat is sitting on a bollard. She has one clean glove. Beside her is a sheet of very good paper, weighted with a small crossbow."),
    keel("You got away from me, and you told me to go. I said I'd send them the bill. I did. Here's the reply."),
    t("She holds up the paper. The Clinic's seal, and one line. 'Account closed. Thank you for your patience.'"),
    ask(keel("A thousand for the tall one. I've never failed to collect. Now the only client I ever had is a thing in a hole. So I've taken to walking the quay at night, and sitting up with the children on the wrecks. Don't look at me."), {
      topic("Why would you do that?", {
        keel("Because somebody's got to, and they can't pay, and I find I'm very good at watching a door. I've stopped asking why it should matter. I shall deny all this."),
      }),
      { "We'll say we never saw you.", {
        keel("You'll say whatever you like. I don't lie to clients. I've no clients. It's been very restful."),
      } },
    }),
    { set = "rs_keel_met" },
  } },
}

S.rs_t_scrimp = {
  ask(scrimp("Scrimp's Chandlery! If it's on the shelf, it's for sale! If it was on a ship, it's on the shelf! I've got the whole Long Reach fleet in here, all except the bits still attached."), {
    { "Show me what you've got.", { { shop = "rs_scrimp" } } },
    { "Not today.", {} },
  }),
}

-- ---------------------------------------------------------------- the burned sea

S.rs_s_ash = {
  t("Nothing prepares you for it. There was a sea of grass here, as high as a man, from the ridge to the sky. It's all gone. It's gone to a soft black ash that lifts when you walk, and the wind has made waves in that too."),
  doc("A year ago you could have lost a horse in this. Who could have done such a thing? It'd take an army, or an act of the gods."),
  t("A long way off in the black, on a flat place, a thin thread of smoke goes straight up. Somebody has a fire going."),
  { set = "rs_ash_seen" },
}

S.rs_t_tully = {
  { when = "rs_shore_down", steps = {
    { when = "rs_tully_came", steps = {
      t("The galley fire's been raked out, and the plates are stacked and tied. There's a note. 'Gone to Orrenshire. Dinner at the usual hour.'"),
    }, other = {
      tully("I'll see that fire stays in. It's all there is to be said for me. You'll tell the Captain, won't you?"),
    } },
  }, other = {
    t("The hulk of the Long Haul sits in the ash, on her keel, with her rails burned off. In the galley an old man is stirring a pot. There are plates set out along the board, a great many of them."),
    { when = "hr_fed_tully", steps = {
      tully("It's you! You had the stew, and you lived, and you asked for nothing. Come in, come in. Forty-two years, and never late with a dinner. Sit down. Is that a doctor? Doctor can sit too."),
    }, other = {
      tully("Is that the shore party? You're late! No. No, you're not them. You've not eaten, I can see that. Forty-two years, and never late with a dinner. Stand there if you want. It's a free ship."),
    } },
    doc("Cook, I don't suppose you know what happened to all that grass?"),
    t("The spoon stops going round. It's the only time you've ever seen it stop."),
    ask(tully("Twenty-eight years I've kept that fire in, and I never once left it. Then a noise came from the north, and the whole sky went wrong. And I went up on deck to look."), {
      topic("You burned the Verdant Sea?", {
        tully("It was only a minute. It was only the one spark, in dry grass, in the wind. I've thought about that minute a good deal. I've had the leisure. It went on for eleven days. There's a whole coast you can read by it."),
        doc("Friend, I'd sit down. That's the funniest and the worst thing I've heard in a year, and I need a moment to work out which."),
      }),
      topic("Who are all these plates for?", {
        tully("The lads! The shore party. All the fires brought them out, see. I can see them from the rail. They're coming back up the mill road, all of them, in good order. I said they'd come. Twenty-eight years, I said. Keep it hot."),
      }),
      { "We need to get through to the mill.", {
        tully("You'll meet them, then, on the road. Tell them it's getting cold. Tell the bosun I've kept his plate."),
      } },
    }),
    { set = "rs_tully_met" },
  } },
}

S.rs_s_shore = {
  { when = "rs_tully_met", steps = {
    t("Where the road narrows between two black stumps, something is standing, and there are others behind it. They're in rows. They've lined up by height. They've been walking for twenty-eight years, and they burned on the way, and they've kept station."),
    t("At the front is a very large man in the remains of a bosun's coat. There's fire in him, a little of it, moving about. His eyes are open. He raises a whistle to what's left of his mouth."),
    doc("Those are the Long Haul's people. They went for a walk. Friend, these are the first of them. The very first. Before there was anyone to call it anything."),
    { battle = "rs_b_bosun" },
    t("He comes down all at once, and he goes on coming down, into a heap, and the wind takes the top off it. The whistle falls on the road. Behind him, the rows are just ash standing up. They last a moment, and then the wind's had them."),
    { set = "rs_shore_down" },
    { when = "hr_fed_tully", steps = {
      t("When you go back, the old man's already at the rail. He has the bosun's plate in his hands. He looks down the road for a good while, and he doesn't ask."),
      tully("You ate it. Do you know that? Twenty-eight years, and you're the only one who ever ate it."),
      doc("The gnomes at Orrenshire are feeding two hundred people in shifts, and they've been boiling things. They need a cook, Tully. Someone who won't leave the fire."),
      t("He sets the plate down carefully, in its place on the board. It takes him some time to take his hand away."),
      tully("Is it a big stove?"),
      { set = "rs_tully_came" },
    }, other = {
      t("When you go back, the old man's at the rail with a plate in his hands. He looks down the road for a good while."),
      tully("They'll want it hot, when they come. It'll pick up. It always does."),
    } },
    { save = true },
  }, other = {
    t("The road to the mill runs between two black stumps, and there's something moving on it, in rows. There's a fire back on the flat, on a hulk. Whoever keeps it may know what those are, and you'd like to know that first."),
    warpTo("rs_ash_1", "r", 3),
  } },
}

S.rs_s_cap = {
  { when = "rs_mill_seen", steps = {
    t("The cap of the mill. Far to the west, past the place the wall used to be, the small white light goes round."),
  }, other = {
    t("The stair's gone, but the sails came down in a heap that makes a kind of ladder. At the top, what's left of the cap looks west over the whole black country, over the long grey line where the wall lies down, and on."),
    t("It's getting dark. The doctor gets up beside you with a good deal of language, and stands looking for a while, and goes quiet."),
    t("A long, long way off, right at the edge of the world, there's a very small white light. It goes round. You count, without meaning to. It goes round again."),
    doc("That's Evrastin. We put that out, friend. You and I were there. It took everything we had. Who in the world would go to the trouble of..."),
    doc("Oh, you stubborn, pedantic, one-winged, impossible bird."),
    t("The doctor doesn't say anything else for some time, and you find there's something in your eye. It's the ash."),
    { set = "rs_mill_seen" },
    doc("West, then. We'll go by Agoshull. The road's open now. There's nothing left to stop anyone walking into the Empire. I suppose that's the good news."),
  } },
}

S.rs_t_peewit = {
  { when = "rs_peewit_met", steps = {
    peewit("New verse! It's about Doctor Grumpy! It's got a high bit. Don't worry, it's only a little bit fatal."),
  }, other = {
    t("A harpy is sitting on a heap of burned sailcloth. She's got one eye bandaged, and she's grown. Every stump and rafter for a mile is black with birds, all facing her, and none of them making a sound."),
    peewit("It's YOU! I knew it! I've done a verse! I told Harrier, I said you weren't dead, because you hadn't heard the end of it. It's a long story. I didn't go flat, you know. Listen."),
    t("She takes a breath and sings. It's only three notes, and they're perfectly in tune. Out in the ash, a long way off, a line of little figures in nightshirts stops, and turns, and starts to walk the other way."),
    peewit("I can't stop them! But I can send them round. They'll follow it right off the edge of the Sea if I want, only I don't want, some of them are somebody's. So I walk them round and round. It's a big job. I'm very important."),
    { set = "rs_peewit_met" },
  } },
}

S.rs_t_harrier = {
  harrier("Keys to everything, and nothing to keep it from. I'm still doing the books. Two hundred thousand birds, four hundred nightshirts, one idiot. She's the best thing that ever happened to this mill. If you tell her that, I'll have your eyes."),
}

S.rs_t_moll = {
  { when = "wm_took", steps = {
    ask(moll("Magpie Moll's. Not much of a stall, I grant you. The old bird went north and never came back. The little one's under the east wall. I put a stone on her. I don't know why, there's no margin in it."), {
      topic("What do the birds do now?", {
        moll("Whatever they like. There's nobody to tell them, and nobody to sing to them. They eat what's lying about. Don't stand still too long. I've had to stop sleeping out of doors."),
      }),
      topic("Have you still got the spoons?", {
        moll("A whole street's worth. Nobody wants them. I've been giving them out to anyone with someone to feed. It's the worst business I've ever been in."),
      }),
      { "Thanks, Moll.", {
        moll("Don't thank me. Thanks are how they get you."),
      } },
    }),
  }, other = {
    ask(moll("Magpie Moll's. Not much of a stall, I grant you. That one-eyed child has got the birds bringing me things again. Nothing's worth anything. I've never had such stock."), {
      topic("Have you still got the spoons?", {
        moll("A whole street's worth. I've been giving them out to anyone with someone to feed. It's the worst business I've ever been in."),
      }),
      { "Thanks, Moll.", {
        moll("Don't thank me. Thanks are how they get you."),
      } },
    }),
  } },
}

-- ---------------------------------------------------------------- Agoshull

S.rs_s_agoshull = {
  t("You've come round the end of the wall. There's no end, really. It's just that a little way back it stopped being a wall and turned into a very long hill of grey stone, and you walked over it. Nobody asked you for anything."),
  t("Agoshull stands in the rain with hardly a light in it. The great towers have been burned, or left. The barricade of books at the foot of the road has swollen with the wet, and something behind it raises a spear."),
  { set = "rs_ag_seen" },
}

S.rs_t_hob = {
  { when = "rs_hob_asked", steps = {
    hob("Nothing's got through the Proceedings of the Constellation yet. I don't believe anything's tried. I've still got you down as friend."),
    { when = "rs_ev_seen", steps = {
      { choice = {
        { "Come with us, Hob. You're relieved.", {
          hob("Relieved? I am? Is that allowed? Who's relieving... oh. Oh, I see. I've never been relieved. What do I do? Do I give you the spear?"),
          doc("Keep the spear. Evrastin's got a warm room and a Warden who'll shout at you. Off you go."),
          t("He looks at the barricade for some time. Then he picks up the one book that was on top, and tucks it under his wing, and walks away down the road in the rain, very upright, not looking back."),
          { set = "rs_hob_came" },
        } },
        { "Hold the line, Hob.", {
          hob("Yes. I will. It's what I'm for. Thank you."),
        } },
      } },
    } },
  }, other = {
    hob("Halt! Friend or foe? And mind, I've got to write down which, so... oh. It's you. Oh, that's three! Oh, this is a very good year."),
    ask(hob("Twelve years I've been doing this. I'm to hold the line until relieved. Warden Tawn took everyone to Evrastin when the rain got into the Orrery. She said she'd send somebody."), {
      topic("Has anyone come this way?", {
        hob("One! An owl, up from the coast on foot, wing in a sling. I put 'friend'. I wasn't sure about that, because of the first thing, you know, the thing with the arithmetic. But it stopped, and it looked at the Proceedings, and it said 'That's a very good barricade.' Nobody's ever said that."),
      }),
      topic("Who's left in the towers?", {
        hob("Only the ones that come down for the rain. Mind them. Corvin's one. I say good morning to him. It seems only right."),
      }),
      { "We're going on to Evrastin.", {
        hob("Then you'll tell the Warden the line's holding? And that it's been some time?"),
      } },
    }),
    { set = "rs_hob_asked" },
  } },
}

S.rs_t_agoshull_lamp = {
  t("Someone has left a lamp burning in the Quiet Rooms, with a full tin of oil beside it. There's a card on the tin in a sharp small hand. 'For Hob. Back soon. This is a lie, and I know you know that. T.'"),
}

-- ---------------------------------------------------------------- Evrastin

S.rs_s_evrastin = {
  t("You come down to Evrastin along the coast with the sea on your right. There's no fog. The crystal has stopped ringing, and in the last of the light the whole city shines very faintly, like the inside of a shell."),
  t("Overhead, the Light goes round, not the great white blade it used to be but one small plain lamp, in a very big lens. The ground doesn't hum. It's only a light. Somebody's minding it."),
  t("You came from here. You've been told that all your life. And somewhere up there is a gallery where a woman stood and bawled out the lazy tacks, and sat up with whoever's boat was late."),
  doc("Ansa Thole's lamp. Friend, are you all right? No. Neither am I. Shall we go up? I've got a speech. It's mainly an apology, with some rude bits."),
  { set = "rs_ev_seen" },
}

S.rs_t_gannet = {
  askUntil("rs_dole_down", gannet("Second Mortgage, you're fouling my berth! Call that a mooring? Oh, hello, love! Look at that, will you? I told them! Fifty-two years! I said they were only a bit late!"), {
    topic("Is that the ship from Glamouth?", {
      gannet("It's a ship! In my harbour, in the berth I kept! Wrong flag, wrong crew, a load of thieves and an owl. I don't care. Tied up alongside at the top of the tide. I've been bawling them out for six months. I've never been so happy."),
    }),
    topic("Who's up the tower?", {
      gannet("The Keeper's bird! Lit her lamp, the first night it got to the top. Climbed all the way with that wing, and it took three days. I can see the fairway again. She'd have said the wick's too long. I've been telling it so myself."),
      gannet("Proctor Dole went up a while before, though, and she never came down, and now the stair's got a lot of moths in it. I send up oil and biscuits in the basket. The rope's on the quay side."),
    }),
    { "Keep bawling, Pilot.", {
      gannet("Aye. It's what she'd want."),
    } },
  }, 2),
}

local TAWN_TOPICS = {
  topic("You're feeding the scholar?", {
    tawn("Oil and biscuits. I said I'd moved that one off the list. I didn't say what list it had moved to. It's turned out to be useful. I remain unforgiving. It's in very good health, I'm sorry to say."),
  }),
  { "We'll see you, Warden.", {
    tawn("Very likely. Try to come back owing me nothing."),
  } },
}

S.rs_t_tawn = {
  { when = "rs_hob_came", steps = {
    askUntil("rs_dole_down", tawn("I've got a hundred and two souls and a ward, and enough fish, for once. That lad from the barricade's on my step, asking me friend or foe. It was my job to send for him. Don't look at me."), TAWN_TOPICS, 1),
  }, other = {
    askUntil("rs_dole_down", tawn("I've got a hundred and two souls and a ward, and enough fish, for once. I left a lad at the barricade. I told him I'd send someone. I've been meaning to do it for eight months. Don't look at me."), TAWN_TOPICS, 1),
  } },
}

S.rs_t_tyto = {
  ask(tyto("You've got her chin. Someone ought to have told you that. Sit down before you fall down. Bed nine's still made up. I don't know why I do it."), {
    topic("What was she like, the Keeper?", {
      tyto("Loud. She'd bawl you out of bed for a lazy knot. And the night you came into my ward she sat in that chair till morning, with her boots on, and she never said a word. I think she knew she only had the one night."),
    }),
    topic("Did the sleepers get up here?", {
      tyto("Every bed in my ward had somebody in the chair. It's what a ward is, or was, before people started counting them. Not one of mine walked. I've had a year to be proud of that, and I'm getting quite good."),
    }),
    { "Thank you, Matron.", {
      tyto("Eat something."),
    } },
  }),
}

S.rs_t_sorrel = {
  ask(sorrel("Crystals, last of the season! They've stopped singing, so I've had to drop the price. I've also got armour and tonics, because it still turns out that nobody can eat a crystal."), {
    { "Show me what you've got.", { { shop = "rs_sorrel" } } },
    { "Not today.", {} },
  }),
}

S.rs_t_hob_e = {
  t("Hob is standing at the top of the road with his spear, in the sun, looking at a plate of fish as if it might be a trick."),
  hob("Friend or foe? It's all right, I'm only practising."),
}

S.rs_s_tower = {
  t("The sea-sluice stands open. The stair of the great white tower goes up from here, the way you came before, but you don't remember the stones having grown. Pale crystal has come through the walls in long thin blades, and it's all faintly warm."),
  doc("Crystal doesn't do that by itself, friend. That wasn't here when we put the Light out. Something has been feeding it."),
}

S.rs_t_basket = {
  t("A rope comes down the well of the tower, and on the end of it there's a basket, and in the basket there's a note, in a neat, cross hand you'd know anywhere."),
  t("'MORE OIL. MORE BISCUIT. THE LAST BISCUIT WAS AN INSULT TO THE TRADITION. DO NOT ON ANY ACCOUNT COME UP. THE STAIR IS NOT SAFE, AND I HAVE PROVED IT.'"),
  { when = "rs_dole_down", steps = {
    owl("I stand by that. It was an insult."),
  }, other = {
    doc("Eight months of silence, and it's still telling me what to do. Oh, I've missed that bird. Let's go up."),
  } },
}

local SHUTTERS = { "rs_shut_a", "rs_shut_b" }

local function shutter(flag, seen)
  return {
    { when = flag, steps = {
      t("The storm shutter is down. A few pale moths are walking up and down it, looking for the way in."),
    }, other = {
      t(seen),
      { set = flag },
      { all = SHUTTERS, steps = {
        t("The second shutter comes down, and the light on the stair goes dim. The moths on the middle landing lift off all at once, and pour away up the well, towards the lamp, leaving the way clear."),
        { set = "rs_shutters" },
      }, other = {
        doc("That's half of it. The moths are coming in by the storm ports, for the crystal's glow. Shut the other one, and they'll have nothing on the stair to stay for."),
      } },
    } },
  }
end

S.rs_t_shutter_a = shutter("rs_shut_a", "A storm port, as wide as a door, with the shutter jammed open and crystal growing on the chain. The moths are coming in through it in a steady soft stream. You put your back into the wheel.")
S.rs_t_shutter_b = shutter("rs_shut_b", "The other storm port. Someone tried to shut this one, with a great many scratches and one small rude word in chalk. You and the doctor take a side of the wheel each, and it comes.")

S.rs_t_moths = {
  t("The middle landing is solid with moths, wall to wall. They've got their faces to the crystal, and they're taking no notice of you. They're a good deal thicker than air. You'd have to shut off whatever's drawing them, at the storm ports east and west."),
}

S.rs_t_log = {
  t("A page of Proctor Dole's, left on the step. The writing starts firm. 'The working wants its key. I can't ask the key, and the key isn't here. I may therefore take the working into a substitute, for the purposes of the trial. I've had the crystal in one hand for twenty-three years.'"),
  t("'I want it noted that I'm not doing this in despair. I'm on the verge. It's a wonderful place. The views are excellent.'"),
  doc("Oh, you foolish, foolish woman."),
}

S.rs_t_dole_still = {
  { when = "rs_owl_back", steps = {
    t("She's looking at you. You're quite sure of it. She hasn't moved."),
  }, other = {
    t("On the gallery round the great lens stands a long thin figure in a stained coat. Crystal has gone up her arm, and across her, and it's come out through the spectacles. She isn't moving. She's holding a pen."),
    doc("Proctor? Proctor Dole. No. Don't touch her, friend. Go past. On tiptoe. Go past, and don't let her hear you think."),
  } },
}

S.rs_t_work = {
  t("Chalk. Every wall, from the floor to as high as a short owl can reach, is covered in a neat cross hand. It's been rubbed out and written again, and rubbed out, until the stone has a shine to it. There's your name, at the top, and a line under it."),
  t("You can't follow it. You know how it ends, though. It's the only thing that's never been rubbed out, in the corner, very small. 'Still.'"),
}

S.rs_t_lamp = {
  t("One plain oil lamp in a lens the size of a house. The wick is cut too long. Someone has stood a biscuit next to it, as an offering, or in protest."),
}

S.rs_s_scholar = {
  { when = "rs_owl_back", other = {
    t("The lamp room's warm, and it smells of oil and chalk. A small round figure is sitting with its back to you, on an upturned bucket, trimming a wick. One wing's folded neatly. The other hangs a little way down, as though it belonged to someone else."),
    owl("If that's the oil, put it by the door. If it's the biscuit, I love you. I've told you not to come up. The stair isn't safe, and I've proved it."),
    doc("It's a year late, and it's come up anyway. And I've got something to say to you about the arithmetic of a one-winged owl."),
    t("The hands stop. The head turns. Owls can do that, you'd forgotten. It comes round a long way, very slowly, past the doctor, and on, and stops at you, and it stays stopped."),
    owl("Well, I'll be plucked."),
    t("The scholar gets down off the bucket with some care, and walks across the room, and looks up at you for a long time. Then a small hard fist hits you in the chest."),
    owl("You're dead. I proved it. I had it to eleven places. I've got the rate of fall, and the height of the road, and page four is one of the best things I've ever done."),
    owl("I've never been so pleased to be wrong in all my life, and I'd like that written down, because you won't hear it twice."),
    { join = "owlin", lvl = 32 },
    { set = "rs_owl_back" },
    ask(owl("You look dreadful. So does the doctor. I gather I'm to be apologised to. Go on, then. I've got time, if you've got biscuit."), {
      topic("What happened to your wing?", {
        owl("It carried one. It's what it was for. I'd do it again, and I'd complain again, and I've been told that I'm very bad at sitting still for a splint."),
        doc("I set that on a kitchen table, with a fork handle, because I hadn't got a spoon. I'm sorry. I'm sorry I said what I said."),
        owl("I know. You've been saying it in your own terrible hand on every post in the Heart. I had a lot of time on the ship. They told me."),
      }),
      topic("What's all that chalk?", {
        owl("My working. I said I'd show you when it was finished, {hero}. I keep my promises now. It isn't finished. I came here to prove something wrong, and I've rubbed it out three hundred times."),
        owl("Please don't ask me again yet. I do mean yet."),
      }),
      topic("Why did you light the lamp?", {
        owl("It's the only high place on the coast, and I can't fly. And the fog came back to the walls after dark. I remembered what those old lamps did in the crack. It doesn't take much. It takes someone staying up."),
        owl("She lit this for twenty years, you know, your mother. Up all those stairs. I found her oil tin. It's got a dent in it from where she threw it at someone. I've taken to thinking of her as a colleague."),
      }),
      { "Nan's alive. Come home.", {
        t("The scholar looks at you, and blinks, once, one eye and then the other. You've never seen that happen before. Nobody says anything about it."),
        owl("Is she? Well. Well, then, I'd better come and check the figures."),
      } },
    }),
  } },
  t("Under your feet, the floor gives one long low hum. Down on the gallery, every blade of crystal in the tower has begun to sing the same note."),
  owl("Ah. That's why the note says not to come up. I've been keeping very quiet up here. The Proctor doesn't hear small sounds. But you've brought the one thing in the world that she's been working on."),
  dole("Is that the key? I've been on the verge of you for some time."),
  t("She comes up through the floor of the lamp room, without using the door, in a long slow shining line. It's her voice, very clear and interested. Nothing else about her has stayed the same."),
  dole("It's such a lovely working. You should see it from in here. There's only the blank in the middle, like a tooth. It asks for you the way a lock asks for a key. Do hold still."),
  doc("I've had just about enough of being held still. Scholar, how does your magic like glass?"),
  owl("It's never been asked so nicely."),
  { battle = "rs_b_dole" },
  t("A line runs through her from side to side, as fine as a hair. She looks down at it. For a moment, behind all that glass, there's a long thin tired woman with her head on one side."),
  dole("Oh. Line nine. Oh, that's very good. You sent me a stiff note about that. Twenty-three years. It's a wonderful place to live."),
  t("She doesn't fall. She just stops being held together. The whole length of her comes down on the boards in a long soft rush, like a wave going out over shingle. Then it's very quiet, and all through the tower the crystal has gone dark."),
  { set = "rs_dole_down" },
  owl("The stair's safe now. I'd stake page four on it. It's only that it's three hundred and twelve steps, and I needed three days to get up them, and I've seen how the doctor's knees are looking. You two go on, and send the basket."),
  { choice = {
    { "I can carry one.", {
      owl("Don't be ridiculous. I'm a very senior... put me down. Put me... {hero}, I've got a great many books about my person."),
      t("You pick the scholar up. There's almost nothing to an owl. It's all feathers and opinions. A year ago someone small walked you home, and you find that your arms know what to do."),
      owl("If you tell anyone about this I'll deny it, and I'll have the proof."),
      t("About a third of the way down, a small warm weight leans its head against your shoulder, and it stays there."),
    } },
    { "Say nothing. Just pick the scholar up.", {
      t("There's almost nothing to an owl. It's all feathers and opinions. A year ago someone small walked you home, and you find that your arms know what to do."),
      owl("I said I can... oh, very well. If you tell anyone about this I'll deny it, and I'll have the proof."),
      t("About a third of the way down, a small warm weight leans its head against your shoulder, and it stays there."),
    } },
  } },
  doc("Leave the lamp. It'll want someone. Gannet's been shouting at that wick for six months. I think we can trust the Pilot to climb a stair for the Keeper. Friend, shall we go and see your Nan?"),
  { fade = true },
  warpTo("rs_evrastin", "z", 3),
  { save = true },
}

-- ---------------------------------------------------------------- the end of it

local function roll(flag, yes, no)
  return { when = flag, steps = { t(yes) }, other = no and { t(no) } or nil }
end

local THE_END = {
    t("It's evening in the east ward at Orrenshire. Twelve beds, twelve chairs, and all the lamps lit. Pip gets up to give you the chair, and looks at the doctor, and sits down again, and is lifted out of it by the scholar's good wing, and falls asleep in about a minute."),
    t("The doctor sits on the edge of Nan's bed, and takes her wrist, and looks at nothing for a long time, with lips moving."),
    doc("Like a clock. Do you know, I said that about you, the first night. Stubborn, regular, and no use to anyone trying to tell it what time it is."),
    ask(doc("I've lied at a great many bedsides, friend. I won't lie at this one. So ask."), {
      topic("Will she wake?", {
        doc("I don't know. I've never seen it. There's something in her that said no to the whole of the night the world ended, and I don't know what that is. It isn't medicine. I think it's mostly spite. It's the best prognosis I've given all year."),
      }),
      topic("Why didn't she get up?", {
        owl("Someone was sitting with her. That's all anyone's got, and I've checked it against a hundred and two owls, eleven gnomes and every anchor watch in Glamouth. It doesn't appear in any of the literature. Nobody thought to look."),
      }),
      { "Thank you for coming.", {
        doc("Don't. I've only come for my spoon."),
      } },
    }),
    doc("Which reminds me. I've been carrying this about, and it isn't right, and I've done the paperwork."),
    t("It's a sheet of very poor paper, ruled by hand. ITEM: ONE SPOON, DELICATE INSTRUMENT, BENT. SIGNED OUT TO: {hero}. PERIOD OF LOAN: AS LONG AS THERE'S ANYONE TO FEED. RECEIVED BY: and then a blank line, with a cross by it, for you."),
    doc("There wasn't a form. So I made one. Don't look like that, it's only a spoon."),
    { give = "rs_spoon" },
    t("You sign. It's the first form you've ever put your name to and meant it."),
    t("Then you get an arm behind Nan's head, and the spoon goes in, and her mouth opens for it. There's salt in it. Nobody in the room has anything to say, and nobody leaves."),
    { fade = true },
    t("When she's done, you open the ledger at the narrow column. There's a good many names in it now. You read them out to her, in the order you came to them. Somebody ought to know."),
    t("'Ambrose Thrupp. Carried. A driver, Cart 19, name not known, under the pear tree. Ottilie Brasscap, Mayor, unopposed. Nib. Nob. Pip, who had the chair before anyone asked.'"),
    roll("held_handlers", "'One large man, on a small chair.'"),
    roll("spared_handlers", "'One large man, two small girls. Bess slept alone. I told him to go home.'"),
    roll("side_frogs", "'Gentleman Bogg, and all of Hayford, on the end of the bed, at very reasonable rates.'", "'Gentleman Bogg. Farthing, who keeps the books. Hayford, no.'"),
    t("'Ione, and Wenna Oakes, who still hate each other. Reader Vance, a shelf a day. Wren, Harbourmaster. Captain Drum.'"),
    roll("hr_keel_spared", "'Vesper Keel. She'll deny it.'"),
    roll("rs_tully_came", "'Cook Tully, of the Long Haul, now of Orrenshire. Dinner at the usual hour.'", "'Cook Tully, keeping it hot.'"),
    roll("wm_peewit_lives", "'Peewit, and two hundred thousand birds, and Harrier, doing the books.'", "'Magpie Moll. One stone, by the east wall.'"),
    roll("rs_hob_came", "'Hob. Relieved.'", "'Hob, holding the line.'"),
    t("'Warden Tawn. Matron Tyto. Pilot Gannet, with a ship in the berth, and the Keeper's lamp. They were only a bit late.'"),
    t("The scholar has been reading over your arm. There's a soft cross noise, and a very small claw comes down on the bottom of the page, where there's nothing written yet."),
    owl("You've left two off. I don't know what they teach in Scythebreak. A proper ledger shows what's owing."),
    { sfx = "horn" },
    nib("Mayor! Tall ones! It's Nob on the tube, he's got the far shaft down to the Abyss workings, and he won't say whose turn it was, but there's something on the cable, coming up out of the deep! It's a bit of black thread! It's tied on!"),
    t("They bring it in on a brass hook. It's as long as your hand, and it's been knotted, firmly, by someone who didn't look away, and it's still a little warm. Nobody says her name. The doctor takes it, and stands holding it, then ties it to Nan's wrist. It's the wrong knot. Nobody says that either."),
    nib("And there's a paper come down the line from the north! It's got 'RIBBED DISTRICT' at the top, and a lot of shouting. They say Adaphis is still standing. They say Sindal's country's falling down. They want anyone who can hold a door."),
    doc("North, then. Or down. Either way, friend, I'd want to do it on a full stomach."),
    t("You take the inch of pencil, and find the place at the foot of the page where the scholar's claw has been. You think about it for a while. He was always very particular about the word."),
    { big = "OUTSTANDING: TWO" },
    t("'One sister. One cat, who says that she lands on her feet.'"),
    { set = "rs_done" },
    t("Then it's night, and it's your turn in the chair. The doctor's asleep on the floor, with one hand on your boot. The scholar's feet are on Pip. Somebody, somewhere in the town, is being shouted at, kindly."),
    t("In the morning, you lean over the bed. Someone ought to tell her how the night went."),
    t("'Nothing, Nan,' you say. 'Same as always.'"),
    { save = true },
}

S.rs_t_nan_o = {
  { when = "rs_done", steps = {
    t("Nan breathes in. She breathes out. There's a black thread round her wrist, tied with the wrong knot. Nobody's said so."),
  }, other = {
    { when = "rs_dole_down", steps = THE_END, other = {
      t("Nan breathes in. She breathes out. Someone has combed her hair, and has done it as well as a small person can."),
    } },
  } },
}

-- ---------------------------------------------------------------- shops

R.shops.rs_smith = { tier = 6 }
R.shops.rs_farthing = { tier = 6 }
R.shops.rs_scrimp = { tier = 6 }
R.shops.rs_sorrel = { tier = 6 }

-- ---------------------------------------------------------------- the story guide

local function goalOn(done, text, map, mark, when)
  local x, y = spot(map, mark)
  return { done = done, text = text, map = map, x = x, y = y, when = when or "ruined" }
end

R.goals = {
  { done = "rs_woke", text = "Go home", site = "scythebreak_r", when = "ruined" },
  goalOn("rs_carried", "See who fed you", "rs_scythebreak", "d"),
  { done = "rs_sitters", text = "Find someone to sit with Nan", site = "orrenshire_r", when = "ruined" },
  { done = "rs_hay_seen", text = "Follow the notices east", site = "hayford_r", when = "ruined" },
  { done = "rs_op_seen", text = "Follow them to Oplinas", site = "oplinas_r", when = "ruined" },
  goalOn("rs_a_signed", "Get past the night orderly", "rs_annexe_1", "s"),
  goalOn("rs_doc_back", "Find the doctor", "rs_annexe_2", "k"),
  goalOn("rs_cart_down", "Get out by the yard", "rs_annexe_2", "y"),
  goalOn("can_travel", "Take the key to Nob", "rs_oplinas", "o"),
  { done = "rs_gl_seen", text = "Ask at Glamouth", site = "glamouth_r", when = "ruined" },
  goalOn("rs_wren_asked", "Find who saw the scholar", "rs_glamouth", "w"),
  { done = "rs_ash_seen", text = "Go to the mill", site = "windmill_r", when = "ruined" },
  goalOn("rs_tully_met", "See who keeps the fire", "rs_ash_1", "o"),
  goalOn("rs_shore_down", "Clear the mill road", "rs_ash_1", "n"),
  goalOn("rs_mill_seen", "Climb the mill's cap", "rs_windmill", "c"),
  { done = "rs_ag_seen", text = "Go west, to Agoshull", site = "agoshull_r", when = "ruined" },
  { done = "rs_ev_seen", text = "Follow the light to Evrastin", site = "evrastin_r", when = "ruined" },
  goalOn("rs_shutters", "Shut the tower's storm ports", "rs_light_1", "a"),
  goalOn("rs_dole_down", "Climb to the lamp room", "rs_light_2", "o"),
  goalOn("rs_done", "Take everyone home to Nan", "rs_orrenshire", "n"),
}

return R
