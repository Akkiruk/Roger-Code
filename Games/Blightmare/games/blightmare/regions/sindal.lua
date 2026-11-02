-- games/blightmare/regions/sindal.lua
-- The Veins of Sindal, in either order with Plexios. Draft for the author to edit, in the voice of story.lua.
-- The horror is niceness. Everyone is fed, everyone asks "Have you eaten?", which is what Nan asked, and everyone smiles the
-- same smile, because it's a scar: a monthly lancet under the ear nicks the nerve that lifts the mouth.
--
-- The way through: the Crevice and its post, then Syndalia, where the Usher gives a dinner card to be signed by the three lords
-- in any order: Asphodel at Antarith, who asks for the Vales to be got out through the Bats Nest; Ceiridwen at Eighstead, with a
-- Clinic man in her cask ship; Barnabas at Upriftin, with his coup under the ice. Then dinner, the tassel, and the cellars.
--
-- Maps are drawn with their people on them, as in heart.lua: a lower-case letter or digit is floor, a capital is stairs, h, L
-- and W keep their meaning, and place() finds each thing's at in the rows.

local say = require("games.blightmare.say")
local C = require("lib.arcade.ui").C

local t, ask, topic, person, line = say.t, say.ask, say.topic, say.person, say.line

local R = {
  id = "sindal", prefix = "sn_",
  entry = {
    flags = {
      "hr_done", "finished", "left_town", "arrived", "breach", "bread_done", "cleric_in", "escaped", "first_night", "foreman_down", "freed_dunnock",
      "frog_bucket", "frog_met", "frog_wet", "gas_met", "gas_mid", "gas_off", "gate_won", "handlers_gone", "have_lamp", "horn", "lamp_ask", "lift_free",
      "lockdown", "mallet_tried", "met_foreman", "mine_pass", "night_seen", "pip_done", "said_goodbye", "saw_shift", "signed", "tested", "thanked_props",
      "warden_ok", "wick_down", "admired_art",
    },
    join = { "deserter", "cleric", "owlin" }, lvl = 12, site = "crevice",
  },
  exit = "sn_done",
  -- How it went, for ruin_north and whoever else cares. side_barnabas is only set by stopping him.
  exports = { "sn_coup_backed", "sn_vales_out", "sn_barnabas_dead", "sn_told_hesper", "sn_lied_hesper", "sn_let_her_choose" },
  sites = {}, maps = {}, scripts = {}, shops = {}, goals = {},
  foes = {}, abilities = {}, encounters = {}, field = {},
  looks = {}, names = {}, art = {},
  items = {
    sn_tassel = { name = "THRONE TASSEL", key = true },
    sn_card = { name = "DINNER CARD", key = true },
  },
}

-- ---------------------------------------------------------------- the helpers maps are drawn with

local SPOTS = {}
local THINGS = { "npcs", "steps", "chests", "foes", "exits" }

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
  for _, kind in ipairs(THINGS) do
    for _, thing in ipairs(def[kind] or {}) do
      local spot = spots[thing.at]
      if not spot then error(id .. " has no mark " .. tostring(thing.at)) end
      thing.x, thing.y, thing.at = spot[1], spot[2], nil
    end
  end
  SPOTS[id] = spots
  R.maps[id] = def
end

--- A person standing on a mark. Their look has the same id, so the sprite is only there until the look is drawn.
local function who(id, at, script, extra)
  local npc = extra or {}
  npc.id, npc.at, npc.script = id, at, script
  npc.sprite = npc.sprite or "villager"
  return npc
end

--- A warp to a mark on a map that's already been placed.
local function warp(id, mark, dir) return { warp = { id, SPOTS[id][mark][1], SPOTS[id][mark][2], dir } } end

--- An exit by stairs to a mark on a map, read once all the maps are placed.
local function stairs(at, id, mark, dir) return { at = at, to = id, land = mark, dir = dir } end

--- A goal at a mark on a map.
local function goal(done, text, id, mark, when)
  local spot = SPOTS[id][mark]
  return { done = done, text = text, map = id, x = spot[1], y = spot[2], when = when }
end

-- ---------------------------------------------------------------- the Cavity Crevice

-- A ledge in from the east. The bridge is the middle row, and it's wound back until the two drums on the east side are turned.
place("sn_crevice_1", {
  name = "THE CAVITY CREVICE", theme = "cave",
  rows = {
    "##########################",
    "#.....#~~~~~~~~~#.1.n...##",
    "#.###.#~~~~~~~~~#.#####.##",
    "#.#...#~~~~~~~~~#.#...#..#",
    "#.#.###~~~~~~~~~#.#.#.##.#",
    "#.#.###~~~~~~~~~#.p.#..se#",
    "#..3###~~~~~~~~~#####.#.##",
    "###.###~~~~~~~~~####..#.##",
    "#.t........g....bk......##",
    "#.###.#~~~~~~~~~#.####.###",
    "#.#.u.#~~~~~~~~~#.#....###",
    "#.#.###~~~~~~~~~#.#.##2###",
    "###.###~~~~~~~~~#.q.#...##",
    "#A#...#~~~~~~~~~#.###.#.##",
    "#w....#~~~~~~~~~#...r.#m##",
    "##########################",
  },
  npcs = {
    who("sn_drum_n", "n", "sn_talk_drum_n"),
    who("sn_drum_s", "m", "sn_talk_drum_s"),
    who("sn_bridgeman", "b", "sn_talk_bridgeman", { unless = "sn_bridge" }),
  },
  steps = {
    { at = "s", script = "sn_crevice_in", once = true },
    { at = "k", script = "sn_sign_board", once = true },
    { at = "p", script = "sn_sign_doing_well", once = true },
    { at = "t", script = "sn_sign_written_to", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "hipotion", n = 1 },
    { id = "c2", at = "2", give = "iron_charm" },
    { id = "c3", at = "3", gold = 180 },
  },
  foes = {
    { id = "f1", at = "p", enc = "sn_pass_bats", sprite = "sn_cliff_bat" },
    { id = "f2", at = "q", enc = "sn_pass_lurker", sprite = "sn_lurker" },
    { id = "f3", at = "r", enc = "sn_pass_bats", sprite = "sn_cliff_bat" },
    { id = "f4", at = "g", enc = "sn_pass_lurker", sprite = "sn_lurker" },
    { id = "f5", at = "u", enc = "sn_pass_mixed", sprite = "sn_bloodshot" },
  },
  exits = {
    { at = "e", world = { 52, 33 } },
    stairs("A", "sn_crevice_2", "a", 4),
  },
})

-- Barnabas's post on the west side: whitewash and window boxes. Ansel is in the lower passage, between the yard and the road.
place("sn_crevice_2", {
  name = "THE CREVICE POST", theme = "city", savepoint = true,
  rows = {
    "########################",
    "#1...hh..............A##",
    "#.....h.......x.y....a##",
    "#.....+........i......##",
    "#.....h...............##",
    "#hhhhhhhhhhhh.hhhhhhhhh#",
    "#....h.............h...#",
    "#....+......p......+.2.#",
    "#....h.............h...#",
    "#hhhhhhhhhhhh.hhhhhhhhh#",
    "############..##########",
    "#vu...........q....#####",
    "#########.##############",
    "#######.....############",
    "#######.3.r.############",
    "#######.....############",
    "########################",
  },
  npcs = {
    who("sn_ivrael", "i", "sn_talk_ivrael"),
    who("sn_recruit_a", "x", "sn_talk_recruit"),
    who("sn_recruit_b", "y", "sn_talk_recruit"),
    who("sn_ansel", "u", "sn_scene_ansel", { unless = "sn_ansel_down" }),
  },
  steps = {
    { at = "a", script = "sn_outpost_in", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "tonic", n = 2 },
    { id = "c2", at = "2", give = "bone_saw" },
    { id = "c3", at = "3", give = "hide_coat" },
  },
  foes = {
    { id = "f1", at = "p", enc = "sn_post_shots", sprite = "sn_bloodshot" },
    { id = "f2", at = "q", enc = "sn_post_shots", sprite = "sn_bloodshot" },
    { id = "f3", at = "r", enc = "sn_pass_mixed", sprite = "sn_bloodshot" },
  },
  exits = {
    stairs("A", "sn_crevice_1", "w", 3),
    { at = "v", world = { 51, 33 } },
  },
})

-- ---------------------------------------------------------------- Syndalia

-- A triangle, with its point at the Citadel gate and the gardens at the foot. The shrine and the Chapel of the Open Hand face
-- each other across the top, the market is the two stalls in the middle, the Full Table is bottom left and the Institute right.
place("sn_syndalia", {
  name = "SYNDALIA", theme = "marble", savepoint = true,
  rows = {
    "##############################",
    "############......############",
    "###########...u....###########",
    "##########..........##########",
    "#########hhhhh..hhhhh#########",
    "########hh.a.h..h.b.hh########",
    "#######hhh.i.h..h...hhh#######",
    "######hhhhh+hh..hh+hhhhh######",
    "#####....................#####",
    "####......hhhh..hhhh......####",
    "###...g...h..h..h..h...k...###",
    "##........h.m+..+l.h........##",
    "##.f......hhhh..hhhh....e...##",
    "#hhhhh+hhh............hhh+hhh#",
    "#h...n...h............h.....h#",
    "#h...t...h............h..c..h#",
    "#h.....1.h............h.....h#",
    "#hhhhhhhhh............hhhhhhh#",
    "##########............########",
    "##########....s.......########",
    "#############.xy.#############",
    "##############################",
  },
  npcs = {
    who("sn_usher", "u", "sn_talk_usher"),
    who("sn_amareth", "a", "sn_talk_amareth"),
    who("sn_severin", "b", "sn_talk_severin"),
    who("sn_perrin", "g", "sn_talk_perrin"),
    who("sn_oswin", "k", "sn_talk_oswin", { sprite = "guard" }),
    who("sn_melon", "m", "sn_talk_melon"),
    who("sn_fenwick", "f", "sn_talk_fenwick"),
    who("sn_anwen", "n", "sn_talk_anwen"),
    who("sn_tam", "t", "sn_talk_tam", { sprite = "child", unless = "sn_tam_gone" }),
    who("sn_lira", "c", "sn_talk_lira", { unless = "sn_dined" }),
    who("sn_lira_after", "c", "sn_talk_lira_after", { when = "sn_dined" }),
  },
  steps = {
    { at = "s", script = "sn_syndalia_in", unless = "sn_arrived" },
  },
  chests = {
    { id = "c1", at = "1", give = "ether", n = 2 },
  },
  exits = {
    { at = "x", world = { 36, 28 } },
    { at = "y", world = { 36, 28 } },
  },
})

-- The way in is the bottom. The gallery is open to the air on both sides, and the dining room is at the head of it. The
-- steward's passage to the cellar stair goes off to the east.
place("sn_citadel", {
  name = "THE SPEAR CITADEL", theme = "marble", savepoint = true,
  rows = {
    "#####################",
    "##h.....y.s.......h##",
    "##h...............h##",
    "##h.......d.......h##",
    "##hhhhhhhh+hhhhhhhh##",
    "######h.......h######",
    "###~~~h.......h~~~###",
    "###~~~h.......h~~~###",
    "###~~~h...g...h~~~###",
    "###~~~h3......h~~~###",
    "######h.......h######",
    "######h.......hhhhhh#",
    "######h.......+n...A#",
    "######h.......hhhhhh#",
    "######h.......h######",
    "###~~~h.......h~~~###",
    "###~~~h...b...h~~~###",
    "######h.......h######",
    "#########xvx#########",
    "#####################",
  },
  npcs = {
    who("sn_sindal", "s", "sn_talk_sindal", { sprite = "captain" }),
    who("sn_undella", "y", "sn_talk_undella"),
    who("sn_steward", "n", "sn_talk_steward", { unless = "sn_dined" }),
  },
  steps = {
    { at = "d", script = "sn_scene_dinner", unless = "sn_dined" },
    { at = "g", script = "sn_gallery_note", once = true },
  },
  chests = {
    { id = "c1", at = "3", give = "hipotion", n = 2 },
  },
  exits = {
    { at = "v", script = "sn_leave_citadel" },
    stairs("A", "sn_veins_1", "a", 2),
  },
})

-- The blood supply, seen from below: the ribbons come down into one tiled cistern with a walk round it. Three thralls have the
-- three sluices, the cold line before the warm, and the gate at the bottom only lifts when the flow's been turned.
place("sn_veins_1", {
  name = "THE VEINS: THE CISTERN", theme = "chain",
  rows = {
    "##########################",
    "#Aa.....................1#",
    "###.###.##########.###.###",
    "#.....#.#~~~~~~~~#.#.....#",
    "#..n..#.#~~~~~~~~#.#..s..#",
    "#.....+.p~~~~~~~~q.+.....#",
    "#.....#.#~~~~~~~~#.#.....#",
    "#.....#.#~~~~~~~~#.#.....#",
    "###.###.##########.###.###",
    "#...........k............#",
    "####.##########.###.######",
    "#...r...#.....#.....#....#",
    "#.w.....#..t..#..2..#..u.#",
    "#.......+.....+.....+....#",
    "#########.....############",
    "#########.....############",
    "###########g##############",
    "###########B##############",
    "##########################",
  },
  npcs = {
    who("sn_sluice_n", "n", "sn_talk_sluice_n"),
    who("sn_sluice_s", "s", "sn_talk_sluice_s"),
    who("sn_sluice_w", "w", "sn_talk_sluice_w"),
    who("sn_gateman", "g", "sn_talk_gateman", { unless = "sn_sluiced" }),
  },
  steps = {
    { at = "a", script = "sn_veins_in", once = true },
    { at = "k", script = "sn_veins_plaque", once = true },
    { at = "p", script = "sn_veins_threads", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "ether", n = 2 },
    { id = "c2", at = "2", give = "wakeroot", n = 2 },
  },
  foes = {
    { id = "f1", at = "p", enc = "sn_works_men", sprite = "sn_sluiceman" },
    { id = "f2", at = "q", enc = "sn_works_men", sprite = "sn_sluiceman" },
    { id = "f3", at = "r", enc = "sn_works_tend", sprite = "sn_contented" },
    { id = "f4", at = "t", enc = "sn_works_tend", sprite = "sn_contented" },
    { id = "f5", at = "u", enc = "sn_works_men", sprite = "sn_sluiceman" },
  },
  exits = {
    stairs("A", "sn_citadel", "n", 4),
    stairs("B", "sn_veins_2", "a", 3),
  },
})

-- The Cellar: racks, tasting notes, the Export Room off to the east, and the Cellarmaster at the far end with this year's best.
place("sn_veins_2", {
  name = "THE VEINS: THE CELLAR", theme = "library",
  rows = {
    "########################",
    "#A.....................#",
    "#a.hhhh.hhhh.hhhh.hhhh.#",
    "#......................#",
    "#.hhhh.hhhh.hhhh.hhhh..#",
    "#......p.....1.......q.#",
    "#.hhhh.hhhh.hhhh.hhhhhh#",
    "#......................#",
    "#.hhhh.hhhh.hhhh+hhhhhh#",
    "#..............h.......#",
    "#.hhhh.hhhh.hhhh..m....#",
    "#......r.......h....2..#",
    "#hhhhhhhh.hhhhhhhhhhhhh#",
    "#hhhhh.......hhhhhhhhhh#",
    "#hhhhh...d...hhhhhhhhhh#",
    "#hhhhh..c.t..hhhhhhhhhh#",
    "#hhhhh.......hhhhhhhhhh#",
    "########################",
  },
  npcs = {
    who("sn_cellarmaster", "c", "sn_scene_cellar", { unless = "sn_cellar_down" }),
    who("sn_tam_rack", "t", "sn_talk_tam_rack", { sprite = "child", unless = "sn_tam_found" }),
  },
  steps = {
    { at = "a", script = "sn_cellar_in", once = true },
    { at = "m", script = "sn_export_room", once = true },
    { at = "d", script = "sn_scene_cellar", unless = "sn_cellar_down" },
  },
  chests = {
    { id = "c1", at = "1", give = "hipotion", n = 2 },
    { id = "c2", at = "2", give = "wool_habit" },
  },
  foes = {
    { id = "f1", at = "p", enc = "sn_cellar_stitchers", sprite = "sn_stitcher" },
    { id = "f2", at = "q", enc = "sn_works_tend", sprite = "sn_contented" },
    { id = "f3", at = "r", enc = "sn_cellar_stitchers", sprite = "sn_stitcher" },
  },
  exits = {
    stairs("A", "sn_veins_1", "g", 1),
  },
})

-- ---------------------------------------------------------------- Antarith and the Bats Nest

-- Fiendfolk in white streets. Arrivals and the portal are the open top of the town, Reformation is to its west and Asphodel's
-- hall to its east. The south gate at the bottom is the way to the pines.
place("sn_antarith", {
  name = "ANTARITH", theme = "city", savepoint = true,
  rows = {
    "##########################",
    "#.....h............h.....#",
    "#..g..h.....y......h..a..#",
    "#.....h............h.....#",
    "#hh+hhh.....hh.....hhh+hh#",
    "#.....................se.#",
    "#.hhhhh+hh......hh+hhhhh.#",
    "#.h...n..h..b...h....c.h.#",
    "#.h......h......h...m..h.#",
    "#.hhhhhhhh......hhhhhhhh.#",
    "#........t....j.....x....#",
    "############z.############",
    "############Z.############",
    "##########################",
    "##########################",
  },
  npcs = {
    who("sn_asphodel", "a", "sn_talk_asphodel"),
    who("sn_grub", "g", "sn_talk_grub", { sprite = "gnome" }),
    who("sn_newcomer", "y", "sn_talk_newcomer"),
    who("sn_hostess", "n", "sn_talk_hostess"),
    who("sn_thrax", "t", "sn_talk_thrax"),
    who("sn_corin", "c", "sn_talk_corin", { unless = "sn_bats_go" }),
    who("sn_maren", "m", "sn_talk_maren", { unless = "sn_bats_go" }),
    who("sn_sabeth", "b", "sn_talk_sabeth", { unless = "sn_bats_go" }),
    who("sn_tam_safe", "j", "sn_talk_tam_safe", { sprite = "child", when = "sn_done" }),
  },
  steps = {
    { at = "s", script = "sn_antarith_in", once = true },
    { at = "z", script = "sn_pines_shut", unless = "sn_bats_go" },
  },
  exits = {
    { at = "e", world = { 20, 38 } },
    { at = "Z", to = "sn_bats_1", land = "s", dir = 3, when = "sn_bats_go" },
  },
})

-- The pines turn you round: past the crossing anyone without the old runaways' rule is walked back to the start.
place("sn_bats_1", {
  name = "THE BATS NEST: THE PINES", theme = "swamp",
  rows = {
    "############################",
    "#s...#.......#.......#.....#",
    "####.#.#####.#.#####.#.###.#",
    "#....#.#...#...#...#...#...#",
    "#.####.#.#.#####.#.#####.###",
    "#......#.#.....#.#.......1.#",
    "#.######.#####.#.#########.#",
    "#.#..p...#...#.#.....#.....#",
    "#.#.######.#.#.#####.#.#####",
    "#...#......#...#...#.#.....#",
    "###.#.######.###.#.#.#####.#",
    "#2..#.#....#.....#...#...#.#",
    "#####.#.##.#######.###.#.#.#",
    "#.....#.#b.#.....#.....#...#",
    "#.#####.#.##.###.###########",
    "#.......#....#..t........Zu#",
    "############################",
  },
  steps = {
    { at = "s", script = "sn_bats_in", once = true },
    { at = "b", script = "sn_bats_blaze", unless = "sn_blaze" },
    { at = "t", script = "sn_bats_turned", unless = "sn_blaze" },
  },
  chests = {
    { id = "c1", at = "1", give = "hipotion", n = 1 },
    { id = "c2", at = "2", give = "echoherb", n = 3 },
  },
  foes = {
    { id = "f1", at = "p", enc = "sn_nest_young", sprite = "sn_nestling" },
  },
  exits = {
    stairs("Z", "sn_bats_2", "a", 3),
  },
})

-- A hollow under the pine roots, with the bats hung in a black mass over the pit. The way round is quiet, and at the far end
-- the Inquisitor has got there first.
place("sn_bats_2", {
  name = "THE BATS NEST: THE HOLLOW", theme = "cave",
  rows = {
    "##########################",
    "#Aa.......#######......1##",
    "#..###.##.#####...###...##",
    "#.##...##...p...#####.####",
    "#.##.####~~~~~~~#####.####",
    "#.##.###~~~~~~~~~####.####",
    "#....###~~~~~~~~~###...###",
    "####.###~~~~~~~~~.q..#.###",
    "####....~~~~~~~~~###.#.###",
    "#####.#.~~~~~~~~~###...###",
    "#2....#~~~~~~~~~####.#####",
    "#####.#####...######.#####",
    "#####...r.....#......#####",
    "#########.###.#.##########",
    "#########.###...###...####",
    "#########..........i.z.v##",
    "##########################",
  },
  npcs = {
    who("sn_sabeth_end", "i", "sn_scene_sabeth", { sprite = "guard", unless = "sn_sabeth_down" }),
  },
  steps = {
    { at = "a", script = "sn_hollow_in", once = true },
    { at = "z", script = "sn_pines_end", unless = "sn_vales_out" },
  },
  chests = {
    { id = "c1", at = "1", give = "oak_staff" },
    { id = "c2", at = "2", give = "antidote", n = 3 },
  },
  foes = {
    { id = "f1", at = "p", enc = "sn_nest_grown", sprite = "sn_werebat" },
    { id = "f2", at = "q", enc = "sn_nest_young", sprite = "sn_nestling" },
    { id = "f3", at = "r", enc = "sn_nest_grown", sprite = "sn_werebat" },
  },
  exits = {
    stairs("A", "sn_bats_1", "u", 4),
    { at = "v", script = "sn_pines_leave" },
  },
})

-- ---------------------------------------------------------------- Eighstead and the Good Neighbour

-- Warm, loud and sunny, with the water to the west. The counting house, the Sound Barrel and the tavern are along the top, and
-- the dry-dock shed with the Good Neighbour in it is along the bottom with the chandler.
place("sn_eighstead", {
  name = "EIGHSTEAD", theme = "town", savepoint = true,
  rows = {
    "############################",
    "#~~~~~~~h...n.h...c.h......#",
    "#~~~~~~~h.....h.....h...d..#",
    "#~~~~~~~hh+hhhhh+hhhhh+hhhh#",
    "#~~~~~~~...g...............#",
    "#~~~~~~..................se#",
    "#.f.....hhhhh+hhhhhhh+hhhhh#",
    "#~~~~~~~h.a...k...Hh.....p.#",
    "#~~~~~~~h.........xh.m.....#",
    "#~~~~~~~hhhhhhhhhhhhhhhhhhh#",
    "#~~~~~~~####################",
    "#~~~~~~~####################",
    "#~~~~~~~####################",
    "#~~~~~~~####################",
    "############################",
  },
  npcs = {
    who("sn_ceiridwen", "c", "sn_talk_ceiridwen"),
    who("sn_bram", "a", "sn_talk_bram"),
    who("sn_tallow", "n", "sn_talk_tallow"),
    who("sn_sailor", "d", "sn_talk_sailor"),
    who("sn_chandler", "m", "sn_talk_chandler"),
    who("sn_scraper", "g", "sn_talk_scraper"),
  },
  steps = {
    { at = "s", script = "sn_eighstead_in", once = true },
    { at = "x", script = "sn_hold_shut", unless = "sn_hold_open" },
  },
  chests = {
    { id = "c1", at = "p", give = "frost_ward" },
  },
  exits = {
    { at = "e", world = { 11, 31 } },
    { at = "H", to = "sn_hold", land = "a", dir = 2, when = "sn_hold_open" },
  },
})

-- A cask ship, stem to stern. The three chalked casks are spread along the hold, and the sheeted stack hides the bulkhead.
place("sn_hold", {
  name = "THE GOOD NEIGHBOUR", theme = "mine",
  rows = {
    "########################",
    "#Aa.hh.....hh.....hh..1#",
    "#...++..p..++..x..++...#",
    "#...hh.....hh.....hh...#",
    "#hhhhhhh+hhhhhhh+hhhhhh#",
    "#...y..h.......h.......#",
    "#......h...q...h...r...#",
    "#......+.......+.......#",
    "#hhhhhhhhhhh+hhhhhhhhhh#",
    "#......h.......h.......#",
    "#.2....h...z...+..t....#",
    "#......+.......h.......#",
    "#hhhhhhhhhhhshhhhhhhhhh#",
    "#hhhhhhhh.......hhhhhhh#",
    "#hhhhhhhh...u...hhhhhhh#",
    "#hhhhhhhh.......hhhhhhh#",
    "########################",
  },
  npcs = {
    who("sn_sheeted", "s", "sn_talk_sheeted", { sprite = "shroud", unless = "sn_bulkhead" }),
    who("sn_thrush", "u", "sn_scene_thrush", { sprite = "doctor", unless = "sn_thrush_gone" }),
  },
  steps = {
    { at = "a", script = "sn_hold_in", once = true },
    { at = "x", script = "sn_cask_1", unless = "sn_chalk_1" },
    { at = "y", script = "sn_cask_2", unless = "sn_chalk_2" },
    { at = "t", script = "sn_cask_3", unless = "sn_chalk_3" },
  },
  chests = {
    { id = "c1", at = "1", give = "antidote", n = 4 },
    { id = "c2", at = "2", give = "ash_rod" },
  },
  foes = {
    { id = "f1", at = "p", enc = "sn_hold_rats", sprite = "rat" },
    { id = "f2", at = "q", enc = "sn_hold_lice", sprite = "sn_cask_louse" },
    { id = "f3", at = "r", enc = "sn_hold_rats", sprite = "rat" },
    { id = "f4", at = "z", enc = "sn_hold_lice", sprite = "sn_cask_louse" },
  },
  exits = {
    stairs("A", "sn_eighstead", "x", 1),
  },
})

-- ---------------------------------------------------------------- Upriftin and the Reserve

-- The only town in the country where anyone frowns. Barnabas's keep is along the top, the soup hall and the Honest Frown
-- across the middle, and the old icehouse is down the lane at the bottom, past the berry women.
place("sn_upriftin", {
  name = "UPRIFTIN", theme = "town", savepoint = true,
  rows = {
    "##########################",
    "#hhhhhhhhhhhhhhhhhhhhhhhh#",
    "#h.........b............h#",
    "#h...q.............y....h#",
    "#hhhhhhhhhhh+hhhhhhhhhhhh#",
    "#........................#",
    "#.hhh+hhhhh....hhhhh+hhh.#",
    "#.h.......h....h.......h.#",
    "#.h....n..h....h...w...h.#",
    "#.h.....1.h....h.......h.#",
    "#.hhhhhhhhh....hhhhhhhhh.#",
    "#........p...........g.se#",
    "#hhhhhhhh........hhhhhhhh#",
    "#.....k.+........+...r...#",
    "#hhhhhhhh........hhhhhhhh#",
    "#########..f.m...#########",
    "#########........#########",
    "###########I..############",
"##########################",
  },
  npcs = {
    who("sn_barnabas", "b", "sn_talk_barnabas", { unless = "sn_coup_broken" }),
    who("sn_barnabas_smiling", "b", "sn_talk_barnabas_smiling", { when = "sn_barnabas_swept" }),
    who("sn_quill", "q", "sn_talk_quill"),
    who("sn_hesper", "w", "sn_talk_hesper"),
    who("sn_host_frown", "n", "sn_talk_host_frown"),
    who("sn_beggar", "p", "sn_talk_beggar"),
    who("sn_furrier", "k", "sn_talk_furrier"),
    who("sn_soup", "r", "sn_talk_soup"),
    who("sn_berry", "m", "sn_talk_berry", { sprite = "child" }),
    who("sn_iceman", "f", "sn_talk_iceman", { unless = "sn_ice_tip" }),
  },
  steps = {
    { at = "s", script = "sn_upriftin_in", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "frost_ward" },
  },
  exits = {
    { at = "e", world = { 30, 24 } },
    { at = "I", to = "sn_ice_1", land = "a", dir = 3, when = "sn_ice_tip" },
  },
})

-- The cold store: racks of ice blocks, the ledger room, and two levers that must both be drawn to free the lower stair.
place("sn_ice_1", {
  name = "THE ICEHOUSE", theme = "cave",
  rows = {
    "########################",
    "#Aa...#.........#.....1#",
    "#.....#.###.###.#.######",
    "##.####.#.....#.#.....##",
    "##.#......###.#.#####.##",
    "##.#.####.#...#.......##",
    "##...#..p.#.#####.######",
    "##l###.####.....#.#...##",
    "#......#..q####.#.#.#.##",
    "#.###.##.#.....r..#.#.##",
    "#...#.##.#.#######..#.##",
    "###.#....#.......####.##",
    "#m..#.####.#####....#.##",
    "#####......#2..#.##.#.##",
    "#######g####.###.##...##",
    "#######Z.....#.........#",
    "########################",
  },
  npcs = {
    who("sn_lever_a", "l", "sn_talk_lever_a"),
    who("sn_lever_b", "m", "sn_talk_lever_b"),
    who("sn_ice_gate", "g", "sn_talk_ice_gate", { unless = "sn_ice_lifted" }),
  },
  steps = {
    { at = "a", script = "sn_ice_in", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "hipotion", n = 2 },
    { id = "c2", at = "2", give = "brigandine" },
  },
  foes = {
    { id = "f1", at = "p", enc = "sn_ice_shots", sprite = "sn_bloodshot" },
    { id = "f2", at = "q", enc = "sn_ice_keepers", sprite = "sn_keeper" },
    { id = "f3", at = "r", enc = "sn_ice_shots", sprite = "sn_bloodshot" },
  },
  exits = {
    stairs("A", "sn_upriftin", "f", 1),
    stairs("Z", "sn_ice_2", "a", 2),
  },
})

-- The Reserve: long cold rows of cells, with Barnabas at the far end, in the warm.
place("sn_ice_2", {
  name = "THE RESERVE", theme = "cave",
  rows = {
    "########################",
    "#Aa....h.....h.........#",
    "#......h..o..h...p.....#",
    "#hhhh.hhhhh.hhhhhh.hhhh#",
    "#..h...h.1.......h...h.#",
    "#..+...+.........+...+.#",
    "#..h...h.........h...h.#",
    "#hhhh.hhhhhhhhhhhhh.hhh#",
    "#.....h...........h....#",
    "#..c..+.....q.....+....#",
    "#.....h...........h..2.#",
    "#hhhhhhhhhh.hhhhhhhhhhh#",
    "#hhhhhhh.......hhhhhhhh#",
    "#hhhhhhh...e...hhhhhhhh#",
    "#hhhhhhh..b.t..hhhhhhhh#",
    "#hhhhhhh.......hhhhhhhh#",
    "########################",
  },
  npcs = {
    who("sn_barnabas_ice", "b", "sn_scene_reserve", { sprite = "captain", unless = "sn_reserve_done" }),
    who("sn_cell_boy", "c", "sn_talk_cell_boy", { unless = "sn_cells_empty" }),
    who("sn_hesper_ice", "t", "sn_talk_hesper_ice", { when = "sn_coup_broken" }),
  },
  steps = {
    { at = "a", script = "sn_reserve_in", once = true },
    { at = "e", script = "sn_scene_reserve", unless = "sn_reserve_done" },
  },
  chests = {
    { id = "c1", at = "1", give = "tonic", n = 3 },
    { id = "c2", at = "2", give = "stiletto" },
  },
  foes = {
    { id = "f1", at = "o", enc = "sn_ice_shots", sprite = "sn_bloodshot" },
    { id = "f2", at = "p", enc = "sn_ice_keepers", sprite = "sn_keeper" },
    { id = "f3", at = "q", enc = "sn_ice_shots", sprite = "sn_bloodshot" },
  },
  exits = {
    stairs("A", "sn_ice_1", "g", 1),
  },
})

-- Exits by stairs were written as a mark, now that every map is there.
for _, map in pairs(R.maps) do
  for _, exit in ipairs(map.exits or {}) do
    if exit.to then
      local spot = SPOTS[exit.to][exit.land]
      exit.map, exit.mx, exit.my, exit.to, exit.land = exit.to, spot[1], spot[2], nil, nil
    end
  end
end

--- A site's arrival square, by its mark.
local function arrive(id, mark, dir)
  local spot = SPOTS[id][mark]
  return { mx = spot[1], my = spot[2], dir = dir }
end

R.sites.crevice = arrive("sn_crevice_1", "s", 4)
R.sites.syndalia = arrive("sn_syndalia", "s", 1)
R.sites.upriftin = arrive("sn_upriftin", "s", 4)
R.sites.eighstead = arrive("sn_eighstead", "s", 4)
R.sites.antarith = arrive("sn_antarith", "s", 4)

R.entry.map, R.entry.x, R.entry.y = "sn_crevice_1", SPOTS.sn_crevice_1.s[1], SPOTS.sn_crevice_1.s[2]

-- ---------------------------------------------------------------- looks
-- Citizens all have the same mouth. Thralls are pale with it, the vampires are pale without needing it, and the only people in
-- the country whose faces move are at Upriftin, on the very old, and on Tam.

local function citizen(fields)
  fields.kind, fields.mouth = fields.kind or "half-elf", fields.mouth or "smile"
  return fields
end

local function thrall(fields)
  fields.kind, fields.mouth, fields.skin, fields.eyes = fields.kind or "human", "smile", C.text, fields.eyes or "tired"
  fields.cut, fields.coat, fields.trim = fields.cut or "tunic", fields.coat or C.line, fields.trim or C.text
  return fields
end

local function fiend(fields)
  fields.kind, fields.skin, fields.horns, fields.tail = "tiefling", fields.skin or C.red, "ram", "devil"
  return fields
end

local L = R.looks

L.sn_drum_n = thrall({ build = "thin", carry = "wheel", legs = C.tie, back = C.panel })
L.sn_drum_s = thrall({ build = "stout", carry = "wheel", hair = "short", hairInk = C.tie, legs = C.tie, back = C.panel })
L.sn_bridgeman = thrall({ tall = 0.94, build = "broad", beard = "stubble", beardInk = C.line, hair = "short", hairInk = C.line, legs = C.tie, back = C.panel })
L.sn_ivrael = { kind = "vampire", tall = 0.97, build = "thin", skin = C.text, coat = C.red, trim = C.text, legs = C.bg, hat = "peaked", hatInk = C.red, hatTrim = C.text, eyes = "narrow", mouth = "line", wear = { "epaulettes", "belt" }, carry = "cane", back = C.redTint }
L.sn_recruit_a = { kind = "half-elf", tall = 0.92, build = "thin", cut = "tunic", skin = C.text, coat = C.red, trim = C.text, legs = C.bg, hat = "cap", hatInk = C.red, hatTrim = C.text, eyes = "red", mouth = "line", carry = "spear", back = C.redTint }
L.sn_recruit_b = { kind = "human", tall = 0.88, build = "normal", cut = "tunic", skin = C.text, coat = C.red, trim = C.text, legs = C.bg, hat = "cap", hatInk = C.red, hatTrim = C.text, eyes = "red", mouth = "teeth", carry = "spear", back = C.redTint }
L.sn_ansel = { kind = "human", tall = 0.9, build = "hunched", lean = 0.1, cut = "tunic", skin = C.text, coat = C.red, trim = C.text, legs = C.bg, hair = "short", hairInk = C.warn, eyes = "red", mouth = "teeth", back = C.redTint }

L.sn_usher = { kind = "vampire", tall = 0.99, build = "thin", cut = "coat", skin = C.text, coat = C.bg, trim = C.red, legs = C.bg, hair = "short", hairInk = C.text, mouth = "smile", eyes = "narrow", wear = { "chain" }, carry = "list", back = C.hiTint }
L.sn_amareth = citizen({ kind = "old", tall = 0.8, build = "stout", cut = "robe", coat = C.bg, trim = C.accent, hat = "hood", hatInk = C.bg, hatTrim = C.accent, carry = "knitting", back = C.tie })
L.sn_severin = citizen({ tall = 0.96, build = "stout", cut = "robe", coat = C.hi, trim = C.red, hair = "short", hairInk = C.warn, wear = { "chain" }, carry = "bowl", back = C.hiTint })
L.sn_perrin = thrall({ build = "thin", hair = "wild", hairInk = C.tie, carry = "broom", legs = C.tie, back = C.hiTint })
L.sn_oswin = { kind = "vampire", tall = 0.96, build = "normal", cut = "coat", skin = C.text, coat = C.tie, trim = C.red, legs = C.bg, hat = "bowler", hatInk = C.bg, hatTrim = C.red, mouth = "smile", eyes = "shifty", wear = { "badge" }, carry = "pen", back = C.tie }
L.sn_melon = citizen({ kind = "human", build = "broad", cut = "dress", coat = C.ok, trim = C.hiTint, hat = "straw", hatInk = C.hi, hatTrim = C.ok, wear = { "apron" }, carry = "tray", back = C.hiTint })
L.sn_fenwick = { kind = "old", tall = 0.72, build = "hunched", lean = 0.16, cut = "robe", coat = C.redTint, trim = C.tie, hat = "nightcap", hatInk = C.blueTint, hatTrim = C.text, beard = "long", beardInk = C.text, carry = "cane", eyes = "narrow", mouth = "frown", back = C.tie }
L.sn_anwen = citizen({ tall = 0.9, build = "stout", cut = "dress", coat = C.hiTint, trim = C.text, hair = "bun", hairInk = C.hi, wear = { "apron" }, carry = "bowl", back = C.hiTint })
L.sn_tam = { kind = "child", tall = 0.55, build = "thin", cut = "tunic", coat = C.warn, trim = C.hiTint, hair = "pigtails", hairInk = C.redTint, wear = { "apron" }, carry = "tray", eyes = "wide", mouth = "teeth", back = C.hiTint }
L.sn_tam_rack = { kind = "child", tall = 0.48, build = "hunched", lean = 0.08, cut = "dress", coat = C.text, trim = C.line, hair = "short", hairInk = C.redTint, eyes = "wide", mouth = "line", wear = { "tags" }, back = C.tie }
L.sn_tam_safe = { kind = "child", tall = 0.6, build = "normal", cut = "coat", coat = C.tie, trim = C.hiTint, hat = "straw", hatInk = C.hi, hatTrim = C.tie, hair = "pigtails", hairInk = C.redTint, carry = "basket", eyes = "tired", mouth = "teeth", back = C.redTint }
L.sn_lira = citizen({ tall = 0.9, build = "thin", cut = "robe", coat = C.blue, trim = C.text, hair = "plaits", hairInk = C.bg, eyes = "specs", mouth = "line", carry = "book", back = C.blueTint })
L.sn_lira_after = thrall({ kind = "half-elf", build = "thin", cut = "robe", coat = C.line, hair = "plaits", hairInk = C.tie, carry = "broom", back = C.blueTint })

L.sn_sindal = { like = "sindal", build = "normal", cut = "robe", hair = "long", hairInk = C.bg, skin = C.warn, mouth = "smile", eyes = "narrow", carry = "goblet" }
L.sn_undella = { kind = "vampire", tall = 0.96, build = "thin", cut = "dress", skin = C.text, coat = C.bg, trim = C.line, hat = "veil", hatInk = C.bg, hatTrim = C.red, hair = "long", hairInk = C.bg, mouth = "line", eyes = "tired", back = C.bg }
L.sn_steward = { kind = "vampire", tall = 0.93, build = "stout", cut = "coat", skin = C.text, coat = C.tie, trim = C.hi, legs = C.bg, hair = "short", hairInk = C.line, mouth = "smile", carry = "keys", back = C.tie }
L.sn_sluice_n = thrall({ carry = "wheel", hat = "cap", hatInk = C.tie, hatTrim = C.line, back = C.redTint })
L.sn_sluice_s = thrall({ kind = "human", skin = C.text, carry = "wheel", build = "stout", hat = "horned", hatInk = C.line, hatTrim = C.text, back = C.redTint })
L.sn_sluice_w = thrall({ build = "broad", carry = "wheel", beard = "stubble", beardInk = C.line, hat = "floppy", hatInk = C.tie, hatTrim = C.line, back = C.redTint })
L.sn_gateman = thrall({ tall = 0.98, build = "broad", wear = { "belt" }, carry = "keys", back = C.redTint })
L.sn_cellarmaster = { kind = "vampire", tall = 0.98, build = "thin", cut = "coat", skin = C.text, coat = C.bg, trim = C.red, legs = C.bg, hair = "short", hairInk = C.text, beard = "goatee", beardInk = C.text, wear = { "apron", "chain" }, apronInk = C.redTint, carry = "mug", eyes = "narrow", mouth = "smile", back = C.redTint }

L.sn_asphodel = { kind = "tiefling", tall = 0.96, build = "thin", cut = "robe", skin = C.red, coat = C.bg, trim = C.hi, horns = "ram", tail = "devil", hair = "long", hairInk = C.bg, eyes = "tired", mouth = "fangs", wear = { "necklace" }, back = C.redTint }
L.sn_grub = { kind = "gnome", tall = 0.4, build = "thin", cut = "tunic", skin = C.redTint, coat = C.hi, trim = C.bg, horns = "spike", tail = "devil", carry = "clipboard", eyes = "shifty", mouth = "teeth", back = C.hiTint }
L.sn_newcomer = fiend({ build = "broad", cut = "tunic", coat = C.tie, trim = C.bg, skin = C.redTint, eyes = "wide", mouth = "open", carry = "bowl", back = C.panel })
L.sn_hostess = fiend({ tall = 0.9, build = "stout", cut = "dress", coat = C.hiTint, trim = C.hi, skin = C.blueTint, mouth = "smile", wear = { "apron" }, carry = "mug", back = C.hiTint })
L.sn_thrax = fiend({ tall = 1, build = "broad", cut = "coat", coat = C.ok, trim = C.text, skin = C.red, hatInk = C.tie, mouth = "smile", wear = { "apron" }, apronInk = C.hiTint, carry = "basket", back = C.hiTint })
L.sn_corin = citizen({ kind = "human", tall = 0.9, build = "thin", cut = "tunic", coat = C.tie, trim = C.panel, hair = "short", hairInk = C.redTint, eyes = "tired", mouth = "line", back = C.panel })
L.sn_maren = citizen({ kind = "human", tall = 0.86, build = "normal", cut = "dress", coat = C.blueTint, trim = C.text, hair = "bun", hairInk = C.redTint, eyes = "tired", carry = "pillow", back = C.panel })
L.sn_sabeth = { kind = "vampire", tall = 0.97, build = "thin", cut = "coat", skin = C.text, coat = C.bg, trim = C.red, legs = C.bg, hat = "bowler", hatInk = C.red, hatTrim = C.bg, eyes = "narrow", mouth = "smile", wear = { "badge", "cape" }, capeInk = C.red, carry = "clipboard", back = C.redTint }
L.sn_sabeth_end = { kind = "vampire", tall = 0.97, build = "thin", cut = "coat", skin = C.text, coat = C.bg, trim = C.red, legs = C.bg, hat = "bowler", hatInk = C.red, hatTrim = C.bg, lean = 0.1, eyes = "red", mouth = "smile", wear = { "badge", "cape" }, capeInk = C.red, carry = "spear", back = C.redTint }

L.sn_ceiridwen = { like = "ceiridwen", kind = "vampire", tall = 1, build = "broad", hat = "wide", hatInk = C.hi, hatTrim = C.blue, hair = "long", hairInk = C.red, eyes = "wide", mouth = "teeth", carry = "goblet" }
L.sn_bram = citizen({ kind = "human", build = "broad", cut = "tunic", coat = C.redTint, trim = C.tie, beard = "chops", beardInk = C.tie, wear = { "apron" }, carry = "hammer", back = C.panel })
L.sn_tallow = citizen({ kind = "old", build = "stout", cut = "dress", coat = C.blueTint, trim = C.text, hat = "scarf", hatInk = C.info, hatTrim = C.text, carry = "kettle", back = C.hiTint })
L.sn_sailor = citizen({ kind = "human", build = "normal", cut = "tunic", coat = C.info, trim = C.text, hat = "cap", hatInk = C.blue, hatTrim = C.text, beard = "plaited", beardInk = C.hi, carry = "mug", back = C.blueTint })
L.sn_chandler = citizen({ tall = 0.92, build = "thin", cut = "coat", coat = C.redTint, trim = C.hi, hat = "feather", hatInk = C.blue, hatTrim = C.hi, carry = "lantern", back = C.panel })
L.sn_scraper = thrall({ build = "hunched", lean = 0.12, hat = "wide", hatInk = C.tie, hatTrim = C.line, carry = "shovel", back = C.blueTint })
L.sn_thrush = { kind = "clinic", tall = 0.9, build = "thin", cut = "coat", coat = C.line, trim = C.tie, legs = C.tie, hat = "cap", hatInk = C.tie, hatTrim = C.line, beak = 0.1, carry = "ledger", back = C.redTint }

L.sn_barnabas = { like = "barnabas", tall = 1, build = "broad", mouth = "fangs", eyes = "wide", carry = "goblet", hair = "wild", hairInk = C.hi, beard = "forked", beardInk = C.hi }
L.sn_barnabas_ice = { like = "sn_barnabas", eyes = "red", carry = "dagger", lean = 0.12, back = C.panel }
L.sn_barnabas_smiling = thrall({ kind = "vampire", tall = 1, build = "hunched", cut = "coat", coat = C.line, hair = "wild", hairInk = C.line, carry = "broom", back = C.hiTint })
L.sn_quill = { kind = "vampire", tall = 0.94, build = "thin", cut = "robe", skin = C.text, coat = C.blueTint, trim = C.text, hat = "goggles", hatInk = C.info, hatTrim = C.bg, hair = "wild", hairInk = C.line, eyes = "specs", mouth = "open", carry = "scroll", back = C.blueTint }
L.sn_hesper = { kind = "human", tall = 0.92, build = "normal", cut = "coat", skin = C.warn, coat = C.tie, trim = C.panel, hat = "earflap", hatInk = C.redTint, hatTrim = C.text, hair = "short", hairInk = C.line, eyes = "narrow", mouth = "frown", wear = { "belt" }, carry = "spear", back = C.tie }
L.sn_hesper_ice = { kind = "human", tall = 0.92, build = "normal", cut = "coat", skin = C.warn, coat = C.tie, trim = C.panel, hair = "short", hairInk = C.line, eyes = "tired", mouth = "line", wear = { "belt" }, carry = "lantern", back = C.tie }
L.sn_host_frown = { kind = "human", tall = 0.9, build = "stout", cut = "tunic", skin = C.warn, coat = C.redTint, trim = C.tie, beard = "long", beardInk = C.tie, mouth = "frown", eyes = "narrow", wear = { "apron" }, carry = "mug", back = C.redTint }
L.sn_beggar = { kind = "old", tall = 0.74, build = "hunched", lean = 0.1, cut = "tunic", coat = C.panel, trim = C.tie, hat = "floppy", hatInk = C.tie, hatTrim = C.panel, beard = "stubble", beardInk = C.line, carry = "bowl", mouth = "frown", wear = { "patches" }, back = C.panel }
L.sn_furrier = { kind = "human", tall = 0.88, build = "stout", cut = "coat", skin = C.warn, coat = C.tie, trim = C.text, hat = "earflap", hatInk = C.text, hatTrim = C.line, eyes = "shifty", mouth = "frown", wear = { "shawl" }, shawlInk = C.text, back = C.tie }
L.sn_soup = { kind = "old", tall = 0.78, build = "stout", cut = "dress", coat = C.panel, trim = C.tie, hat = "scarf", hatInk = C.redTint, hatTrim = C.tie, carry = "ladle", mouth = "frown", wear = { "apron" }, back = C.redTint }
L.sn_berry = { kind = "child", tall = 0.48, build = "thin", cut = "tunic", coat = C.panel, trim = C.red, hat = "earflap", hatInk = C.tie, hatTrim = C.red, carry = "basket", eyes = "narrow", mouth = "frown", back = C.tie }
L.sn_iceman = { kind = "old", tall = 0.84, build = "stout", cut = "coat", coat = C.tie, trim = C.line, hat = "earflap", hatInk = C.line, hatTrim = C.tie, beard = "bolster", beardInk = C.text, carry = "keys", eyes = "shifty", mouth = "line", back = C.tie }
L.sn_lever_a = thrall({ carry = "wheel", hair = "short", hairInk = C.text, wear = { "fur" }, back = C.tie })
L.sn_lever_b = thrall({ build = "stout", carry = "wheel", hat = "earflap", hatInk = C.line, hatTrim = C.text, back = C.tie })
L.sn_ice_gate = thrall({ build = "broad", tall = 0.97, carry = "keys", hat = "pot", hatInk = C.line, hatTrim = C.tie, back = C.tie })
L.sn_sheeted = { kind = "human", pose = "lying", coat = C.text, trim = C.line, thread = false, carry = "none" }
L.sn_labelled = thrall({ cut = "robe", coat = C.text, trim = C.line, wear = { "tags" }, back = C.tie })
L.sn_cell_boy = { kind = "human", tall = 0.86, build = "hunched", lean = 0.08, cut = "tunic", skin = C.text, coat = C.red, trim = C.line, legs = C.bg, hair = "short", hairInk = C.tie, eyes = "red", mouth = "line", back = C.blueTint }

R.names = {
  ["SERGEANT IVRAEL"] = "sn_ivrael", ANSEL = "sn_ansel", ["THE USHER"] = "sn_usher", ["MOTHER AMARETH"] = "sn_amareth", ["ALMONER SEVERIN"] = "sn_severin",
  PERRIN = "sn_perrin", ["CONSTABLE OSWIN"] = "sn_oswin", ["DULCIE MELON"] = "sn_melon", ["OLD FENWICK"] = "sn_fenwick",
  ANWEN = "sn_anwen", TAM = "sn_tam", LIRA = "sn_lira", ["SINDAL DEVEROUS"] = "sn_sindal", UNDELLA = "sn_undella",
  ["THE BUTLER"] = "sn_steward", ["THE CELLARMASTER"] = "sn_cellarmaster", ["ASPHODEL SYREN"] = "sn_asphodel", GRUB = "sn_grub", ["THE NEWCOMER"] = "sn_newcomer",
  VESH = "sn_hostess", ["MR THRAX"] = "sn_thrax", ["CORIN VALE"] = "sn_corin", ["MAREN VALE"] = "sn_maren",
  ["INQUISITOR SABETH"] = "sn_sabeth", ["CEIRIDWEN HEARTFORD"] = "sn_ceiridwen", ["JOSS THE COOPER"] = "sn_bram", ["OLD BARLOW"] = "sn_tallow", ["JEB THE SAILOR"] = "sn_sailor",
  ["THE CHANDLER"] = "sn_chandler", ["THE SCRAPER"] = "sn_scraper", THRUSH = "sn_thrush",
  ["BARNABAS KNIFE TOOTH"] = "sn_barnabas", BARNABAS = "sn_barnabas_smiling", BRIDGEMAN = "sn_bridgeman", ["THE NORTH DRUM"] = "sn_drum_n", ["THE SOUTH DRUM"] = "sn_drum_s",
  RECRUITS = "sn_recruit_a", ["THE SWEEPER"] = "sn_lira_after", ["A THRALL"] = "sn_gateman", ["THE COLD LINE"] = "sn_sluice_n", ["THE DEVILS' LINE"] = "sn_sluice_s", ["THE SEA LINE"] = "sn_sluice_w",
  ["THE LABELLED"] = "sn_labelled", ["A BOY IN RED"] = "sn_cell_boy", ["DOCTOR MOTT"] = "sn_quill", ["HESPER WANE"] = "sn_hesper", ["GRIM THE HOST"] = "sn_host_frown",
  ["THE BEGGAR"] = "sn_beggar", ["THE FURRIER"] = "sn_furrier", ["MOTHER BRESS"] = "sn_soup", NETTLE = "sn_berry", ["THE ICEMAN"] = "sn_iceman",
}

-- ---------------------------------------------------------------- what you fight

local A = R.abilities

A.sn_sorry = { name = "SO SORRY", power = 110 }
A.sn_famished = { name = "NINETEEN DAYS", power = 200, windup = 34, warn = "HE STOPS APOLOGISING" }
A.sn_stitch = { name = "STITCH", power = 120 }
A.sn_run_through = { name = "RUN THROUGH", power = 150 }
A.sn_eaten = { name = "HAVE YOU EATEN?", mp = 3, status = "sleep", chance = 45 }
A.sn_lovely = { name = "A LOVELY DAY", mp = 5, magic = true, status = "thrall", chance = 35 }
A.sn_scythe = { name = "HARVEST", power = 115 }
A.sn_flush = { name = "FLUSH", power = 60, target = "all" }
A.sn_asked = { name = "ASKED KINDLY", mp = 4, power = 60, magic = true, element = "mind" }
A.sn_asked_twice = { name = "ASKED TWICE", power = 220, magic = true, windup = 34, warn = "SHE ASKS A SECOND TIME" }
A.sn_nest_stirs = { name = "THE NEST STIRS", target = "summon" }
A.sn_corkscrew = { name = "CORKSCREW", power = 125 }
A.sn_decant = { name = "DECANT", mp = 4, power = 80, magic = true, element = "blood" }
A.sn_last_pour = { name = "THE LAST POUR", power = 130, magic = true, target = "all", element = "blood", windup = 34, warn = "HE RAISES THE GLASS" }
A.sn_ring_bell = { name = "RINGS FOR SERVICE", target = "summon" }
A.sn_knife_tooth = { name = "KNIFE TOOTH", power = 130 }
A.sn_toast = { name = "A TOAST", mp = 6, power = 55, magic = true, target = "all", status = "poison", chance = 50 }
A.sn_hard_winter = { name = "A HARD WINTER", power = 125, magic = true, target = "all", element = "ice", windup = 34, warn = "THE COLD COMES UP THE STAIRS" }
A.sn_whistle_up = { name = "WHISTLES UP A BOY", target = "summon" }

local F = R.foes

F.sn_cliff_bat = { name = "CLIFF BAT", tier = 12, shape = "small", sprite = "sn_cliff_bat", family = "harpy", abilities = { { "bite", 3 }, { "blind_dust", 1 } }, weak = { "ice" } }
F.sn_lurker = { name = "PASS LURKER", tier = 12, shape = "tank", sprite = "sn_lurker", family = "stalker", abilities = { { "claw", 3 }, { "lunge", 1 } }, weak = { "bolt" } }
F.sn_bloodshot = { name = "BLOODSHOT", tier = 13, shape = "quick", sprite = "sn_bloodshot", family = "blighted", abilities = { { "sn_sorry", 3 }, { "leech_vein", 1 } }, weak = { "fire", "holy" } }
F.sn_harvester = { name = "HARVESTER", tier = 13, shape = "brute", sprite = "sn_harvester", family = "blighted", abilities = { { "sn_scythe", 3 }, { "sn_eaten", 1 } }, weak = { "fire" } }
F.sn_verger = { name = "ROAD WARDEN", tier = 14, shape = "caster", sprite = "sn_stitcher", family = "staff", abilities = { { "sn_stitch", 2 }, { "sn_asked", 2 }, { "sn_eaten", 1 } }, weak = { "holy" } }
F.sn_cask_rat = { name = "CASK RAT", tier = 13, shape = "small", sprite = "rat", family = "rat", abilities = { { "gnaw", 3 }, { "retch", 1 } }, goldx = 1.4 }
F.sn_cask_louse = { name = "CASK LOUSE", tier = 14, shape = "healer", sprite = "sn_cask_louse", family = "bug", abilities = { { "leech_vein", 3 }, { "suture", 1 } }, weak = { "fire" } }
F.sn_clinic_man = { name = "CLINIC ORDERLY", short = "ORDERLY", tier = 14, shape = "brute", sprite = "orderly", family = "staff", abilities = { { "baton", 3 }, { "needle", 1 } } }
F.sn_nestling = { name = "NESTLING", tier = 14, shape = "small", sprite = "sn_nestling", family = "harpy", abilities = { { "bite", 3 }, { "shriek", 1 } }, weak = { "ice" } }
F.sn_werebat = { name = "WEREBAT", tier = 15, shape = "quick", sprite = "sn_werebat", family = "stalker", abilities = { { "claw", 3 }, { "leech_vein", 1 }, { "blind_dust", 1 } }, weak = { "holy" } }
F.sn_sluiceman = { name = "SLUICEMAN", tier = 16, shape = "brute", sprite = "sn_sluiceman", family = "blighted", abilities = { { "swing", 3 }, { "sn_flush", 1 } }, weak = { "bolt" } }
F.sn_contented = { name = "THE CONTENTED", short = "CONTENTED", tier = 16, shape = "healer", sprite = "sn_contented", family = "blighted", abilities = { { "sn_eaten", 2 }, { "field_surgery", 2 }, { "sn_lovely", 1 } } }
F.sn_stitcher = { name = "STITCHER", tier = 16, shape = "quick", sprite = "sn_stitcher", family = "staff", abilities = { { "sn_stitch", 3 }, { "sn_run_through", 1 } }, weak = { "holy", "fire" } }
F.sn_frozen_shot = { name = "THE RESERVE", short = "RESERVE", tier = 16, shape = "quick", sprite = "sn_bloodshot", family = "blighted", abilities = { { "sn_sorry", 3 }, { "leech_vein", 1 } }, weak = { "fire" }, resist = { "ice" } }
F.sn_keeper = { name = "ICE KEEPER", tier = 16, shape = "tank", sprite = "sn_keeper", family = "staff", abilities = { { "rime", 2 }, { "baton", 3 } }, weak = { "fire" }, resist = { "ice" } }

F.sn_ansel = {
  name = "RECRUIT ANSEL", short = "ANSEL", tier = 13, shape = "quick", sprite = "sn_bloodshot", family = "blighted", weak = { "fire", "holy" },
  boss = { hpx = 0.8, phases = {
    { at = 100, moves = { { "sn_sorry", 5 }, { "leech_vein", 2 } }, every = 5, big = "sn_famished" },
    { at = 50, moves = { { "sn_sorry", 4 }, { "leech_vein", 3 } }, every = 4, big = "sn_famished", say = "HE ASKS YOU TO BE QUICK", speedUp = 1 },
  } },
}
F.sn_sabeth = {
  name = "INQUISITOR SABETH", short = "SABETH", tier = 15, shape = "caster", sprite = "sn_sabeth", family = "staff", weak = { "holy" },
  boss = { hpx = 1.0, phases = {
    { at = 100, moves = { { "sn_stitch", 4 }, { "sn_asked", 3 }, { "hush_word", 1 } }, every = 5, big = "sn_asked_twice" },
    { at = 66, moves = { { "sn_stitch", 3 }, { "sn_asked", 3 }, { "sn_lovely", 2 } }, every = 4, big = "sn_asked_twice", say = "SHE MAKES A SMALL NOTE", call = "sn_nest_stirs", summon = "sn_nestling" },
    { at = 33, moves = { { "sn_run_through", 3 }, { "sn_asked", 3 }, { "sn_lovely", 2 } }, every = 3, big = "sn_asked_twice", say = "SHE STOPS BEING POLITE", speedUp = 1, call = "sn_nest_stirs", summon = "sn_werebat" },
  } },
}
F.sn_cellarmaster = {
  name = "THE CELLARMASTER", short = "CELLARMASTER", tier = 18, shape = "brute", sprite = "sn_cellarmaster", family = "boss", weak = { "holy" }, resist = { "blood" },
  boss = { hpx = 1.1, phases = {
    { at = 100, moves = { { "sn_corkscrew", 5 }, { "sn_decant", 3 } }, every = 5, big = "sn_last_pour" },
    { at = 66, moves = { { "sn_corkscrew", 4 }, { "sn_decant", 3 }, { "sn_eaten", 2 } }, every = 4, big = "sn_last_pour", say = "HE RINGS FOR SERVICE", call = "sn_ring_bell", summon = "sn_contented" },
    { at = 33, moves = { { "sn_corkscrew", 4 }, { "sn_decant", 4 }, { "sn_lovely", 2 } }, every = 3, big = "sn_last_pour", say = "HE TAKES OFF THE APRON", speedUp = 1, call = "sn_ring_bell", summon = "sn_contented" },
  } },
}
F.sn_barnabas = {
  name = "BARNABAS KNIFE TOOTH", short = "BARNABAS", tier = 18, shape = "brute", sprite = "sn_barnabas", family = "boss", weak = { "fire", "holy" }, resist = { "ice" },
  boss = { hpx = 1.15, phases = {
    { at = 100, moves = { { "sn_knife_tooth", 5 }, { "sn_toast", 2 } }, every = 5, big = "sn_hard_winter" },
    { at = 66, moves = { { "sn_knife_tooth", 5 }, { "sn_toast", 3 } }, every = 4, big = "sn_hard_winter", say = "HE OPENS A CELL", call = "sn_whistle_up", summon = "sn_frozen_shot" },
    { at = 33, moves = { { "sn_knife_tooth", 6 }, { "leech_vein", 3 } }, every = 3, big = "sn_hard_winter", say = "HE STOPS JOKING", speedUp = 1, call = "sn_whistle_up", summon = "sn_frozen_shot" },
  } },
}

local E = R.encounters

E.sn_pass_bats = { foes = { "sn_cliff_bat", "sn_cliff_bat", "sn_cliff_bat" }, flee = true, bg = "cave" }
E.sn_pass_lurker = { foes = { "sn_lurker", "sn_cliff_bat" }, flee = true, bg = "cave" }
E.sn_pass_mixed = { foes = { "sn_bloodshot", "sn_cliff_bat", "sn_cliff_bat" }, flee = true, bg = "cave" }
E.sn_post_shots = { foes = { "sn_bloodshot", "sn_bloodshot" }, flee = true, bg = "city" }
E.sn_boss_ansel = { foes = { "sn_ansel" }, flee = false, bg = "cave", boss = true }
E.sn_field_1 = { foes = { "sn_harvester" }, flee = true, bg = "grass" }
E.sn_field_2 = { foes = { "sn_verger", "sn_harvester" }, flee = true, bg = "grass" }
E.sn_field_3 = { foes = { "sn_cliff_bat", "sn_cliff_bat", "sn_cliff_bat" }, flee = true, bg = "grass" }
E.sn_hold_rats = { foes = { "sn_cask_rat", "sn_cask_rat", "sn_cask_rat" }, flee = true, bg = "mine" }
E.sn_hold_lice = { foes = { "sn_cask_louse", "sn_cask_rat", "sn_cask_rat" }, flee = true, bg = "mine" }
E.sn_clinic_men = { foes = { "sn_clinic_man", "sn_clinic_man" }, flee = false, bg = "mine" }
E.sn_nest_young = { foes = { "sn_nestling", "sn_nestling", "sn_nestling" }, flee = true, bg = "swamp" }
E.sn_nest_grown = { foes = { "sn_werebat", "sn_nestling" }, flee = true, bg = "cave" }
E.sn_boss_sabeth = { foes = { "sn_sabeth" }, flee = false, bg = "cave", boss = true }
E.sn_works_men = { foes = { "sn_sluiceman", "sn_contented" }, flee = true, bg = "chain" }
E.sn_works_tend = { foes = { "sn_contented", "sn_contented" }, flee = true, bg = "chain" }
E.sn_cellar_stitchers = { foes = { "sn_stitcher", "sn_stitcher" }, flee = true, bg = "chain" }
E.sn_boss_cellarmaster = { foes = { "sn_cellarmaster" }, flee = false, bg = "chain", boss = true }
E.sn_ice_shots = { foes = { "sn_frozen_shot", "sn_frozen_shot" }, flee = true, bg = "snow" }
E.sn_ice_keepers = { foes = { "sn_keeper", "sn_frozen_shot" }, flee = true, bg = "snow" }
E.sn_boss_barnabas = { foes = { "sn_barnabas" }, flee = false, bg = "snow", boss = true }

R.field.ebrein = { "sn_field_1", "sn_field_2", "sn_field_3" }

R.art = {
  sn_cliff_bat = "A lean grey bat with a wingspan like an open coat, and a very clean face.",
  sn_lurker = "Something flat and rock-coloured that has learned to wait on a ledge, all elbows and patience.",
  sn_bloodshot = "A young soldier in a spotless red tunic, standing to attention, red-eyed, teeth just showing, ashamed of it.",
  sn_harvester = "A thrall in a straw hat and a clean smock with a long scythe, smiling at nothing in the middle of a melon field.",
  sn_stitcher = "A pale vampire soldier in red lacquer with a needle-thin lance, tall and very upright.",
  sn_cask_louse = "A fat pale tick the size of a dog, its belly full and showing dark through the skin.",
  sn_nestling = "A half-grown werebat, all ears and hunger, hanging by one foot.",
  sn_werebat = "A man-sized bat on its hind legs, with a person's hands and a torn collar.",
  sn_sluiceman = "A huge thrall in a rubber apron and long gloves, with a sluice key the size of a spade, smiling.",
  sn_contented = "A thin pale thrall in a grey smock, holding a towel over one arm and a small glass in the other hand.",
  sn_keeper = "A squat vampire wrapped in sacking and ice-tongs, breath not showing at all.",
  sn_sabeth = "A narrow vampire inquisitor in a black coat and a red bowler, with a clipboard in one hand and a needle-lance in the other.",
  sn_cellarmaster = "A thin old vampire sommelier in a leather apron and a silver tasting chain, one glass held up to the light, the other hand on a corkscrew as long as a forearm.",
  sn_barnabas = "A huge laughing vampire lord in furs and gold chain, with one long steel-bright tooth, and a mug.",
}

-- ---------------------------------------------------------------- shops

R.shops.sn_shop_market = { tier = 3 }
R.shops.sn_shop_antarith = { tier = 3 }
R.shops.sn_shop_eighstead = { tier = 3, extra = { { item = "swift_band", price = 900 }, { item = "tent", price = 300 } } }
R.shops.sn_shop_furrier = { tier = 3, extra = { { item = "oath_ring", price = 1500 } } }

-- ---------------------------------------------------------------- goals

R.goals = {
  { done = "sn_crossed", text = "Cross the Cavity Crevice", site = "crevice", when = "hr_done" },
  { done = "sn_arrived", text = "Reach Syndalia", site = "syndalia", when = "hr_done" },
  goal("sn_has_card", "Ask at the Citadel gate", "sn_syndalia", "u", "sn_arrived"),
  { done = "sn_sign_a", text = "Find Asphodel in Antarith", site = "antarith", when = "sn_has_card" },
  goal("sn_vales_out", "Get the Vales to the pines", "sn_antarith", "z", "sn_bats_go"),
  { done = "sn_hold_open", text = "Find Ceiridwen in Eighstead", site = "eighstead", when = "sn_has_card" },
  goal("sn_thrush_gone", "Search the Good Neighbour", "sn_eighstead", "x", "sn_hold_open"),
  goal("sn_sign_c", "Report to Ceiridwen", "sn_eighstead", "c", "sn_thrush_gone"),
  { done = "sn_sign_b", text = "Find Barnabas in Upriftin", site = "upriftin", when = "sn_has_card" },
  goal("sn_dined", "Dine at the Spear Citadel", "sn_syndalia", "u", "sn_has_card"),
  goal("sn_tam_found", "Find Tam in the cellars", "sn_citadel", "n", "sn_dined"),
  goal("sn_done", "Take your leave of Sindal", "sn_citadel", "v", "sn_tam_found"),
}

-- ---------------------------------------------------------------- who says what

local S = R.scripts

local hero, deserter, cleric, owlin = line("hero"), line("deserter"), line("cleric"), line("owlin")

local bridgeman = person("sn_bridgeman", "BRIDGEMAN")
local drum_n = person("sn_drum_n", "THE NORTH DRUM")
local drum_s = person("sn_drum_s", "THE SOUTH DRUM")
local ivrael = person("sn_ivrael", "SERGEANT IVRAEL")
local recruits = person("sn_recruit_a", "RECRUITS")
local ansel = person("sn_ansel", "ANSEL")
local usher = person("sn_usher", "THE USHER")
local amareth = person("sn_amareth", "MOTHER AMARETH")
local severin = person("sn_severin", "ALMONER SEVERIN")
local perrin = person("sn_perrin", "PERRIN")
local oswin = person("sn_oswin", "CONSTABLE OSWIN")
local dulcie = person("sn_melon", "DULCIE MELON")
local fenwick = person("sn_fenwick", "OLD FENWICK")
local anwen = person("sn_anwen", "ANWEN")
local tam = person("sn_tam", "TAM")
local lira = person("sn_lira", "LIRA")

-- ---------------------------------------------------------------- the Crevice

S.sn_crevice_in = {
  t("The Cavity Crevice is what's left of a mountain after something took a bite out of it. The road goes in along a ledge, and the wind comes up from below with nothing on it at all."),
  t("There's a sign at the mouth of the pass, freshly painted, with a neat border of melons. WELCOME TO THE VEINS OF SINDAL. HAVE YOU EATEN? PLEASE MIND THE DROP."),
  { when = "px_done", steps = {
    deserter("After Adaphis I would dearly like to be welcomed by something. I'm aware that's how it's done."),
  }, other = {
    deserter("Somebody climbed up here with a very small brush to do those melons. I find that more alarming than the drop."),
  } },
}

S.sn_sign_doing_well = { t("Another sign, on a bend with no rail. YOU ARE DOING VERY WELL.") }
S.sn_sign_written_to = { t("A sign, at the narrowest place on the whole ledge. THE LAST PERSON TO FALL FROM HERE HAS BEEN WRITTEN TO.") }
S.sn_sign_board = { t("A painted board. TO CROSS, WIND THE NORTH DRUM AND THE SOUTH DRUM. THE BRIDGEMEN WILL DO AS THEY ARE TOLD. PLEASE ASK NICELY.") }

local BRIDGE_COMES = {
  all = { "sn_drum_n", "sn_drum_s" },
  steps = {
    t("Out over the drop, chain takes up. A long grey bridge slides across the Crevice, and locks with a noise like a very large door being closed politely."),
    { set = "sn_bridge" },
  },
}

local function drum(flag, speaker, says, after)
  return {
    { when = flag, steps = after, other = {
      ask(speaker(says), {
        { "Wind the drum, please.", {
          speaker("Yes. It is a lovely day."),
          { set = flag },
          BRIDGE_COMES,
        } },
        { "Not yet.", {} },
      }),
    } },
  }
end

S.sn_talk_drum_n = drum("sn_drum_n", drum_n, "I am the north drum. I wind it when I am asked. It is a lovely day. Have you eaten?", {
  { when = "sn_drum_stopped", steps = {
    t("He stands with his hands held out, still curled round nothing, smiling."),
  }, other = {
    t("He's still winding. The drum stopped some time ago. The handle has worn two clean grooves in his palms, and it hasn't occurred to anyone to tell him he can stop."),
    { choice = {
      { "Tell him he can stop.", {
        t("He stops. He stands with his hands held out, still curled round nothing, smiling. After a while you begin to feel it was better before."),
        { set = "sn_drum_stopped" },
      } },
      { "Leave him.", {} },
    } },
  } },
})
S.sn_talk_drum_s = drum("sn_drum_s", drum_s, "I am the south drum. It is a lovely day. Have you eaten?", {
  drum_s("It is a lovely day."),
})

S.sn_talk_bridgeman = {
  t("A big man stands at the end of the ledge, where a bridge ought to be. He has no coat on. There's frost in his eyelashes, and he hasn't noticed. He is smiling at you."),
  ask(bridgeman("The bridge is wound back. It is a lovely day. Have you eaten?"), {
    topic("Aren't you cold?", { bridgeman("Yes. It is a lovely day.") }),
    topic("Doctor, what's the matter with him?", {
      deserter("Pulse slow and even, no fever, nothing broken. He's in perfect health, friend, and there's nobody home. I've watched a great many people go out behind the eyes. I've never seen one look this pleased about it."),
      cleric("He isn't dead. His thread is whole. It just doesn't go anywhere."),
    }),
    { "Leave him be.", {} },
  }),
}

S.sn_outpost_in = {
  t("The pass comes out at a stone fort, whitewashed, with window boxes. A squad of young soldiers in spotless red stands at attention in the yard. Every one has red eyes. Every one is looking at your throats, and trying hard not to."),
  ivrael("Recruits! What do we do when we see a guest?"),
  recruits("ASK IF THEY HAVE EATEN, SERGEANT!"),
  ivrael("And what do we not do?"),
  recruits("EAT THEM, SERGEANT!"),
  ivrael("Very nice. Two of you were looking at the sister's neck, and I'll see you after. Sergeant Ivrael, friends, Crevice Post, Lord Barnabas's garrison. Have you eaten?"),
}

S.sn_talk_ivrael = {
  { when = "sn_ansel_down", steps = {
    ask(ivrael("West road's clear, and I'm obliged. There's a cot if you want one. No charge. Nothing in this country has a charge, you'll find."), {
      { "A cot, please.", { { inn = 0 }, { save = true } } },
      { "We'll get on.", {} },
    }),
  }, other = {
    ask(ivrael("You'll be for Syndalia. Everybody's welcome. Only you'd have to get past Ansel, and I'd take it as a kindness."), {
      topic("What's the matter with those boys?", {
        ivrael("Bloodshots, we call them. You turn a lad in the spring and spend a year teaching him not to. It takes, nineteen days in twenty. The twentieth is what the drop's for. I'm joking. Mostly I'm joking."),
      }),
      topic("Who's Ansel?", {
        ivrael("Farm boy from Upriftin way. Never a day's trouble. He's sat down in the lower passage with the hunger in him, right across the west road. I can't send the squad. It would be a bad lesson whichever way it went."),
      }),
      topic("What's Lord Barnabas like?", {
        ivrael("You'll like him. Everyone does, for about an hour."),
      }),
      { "We'll see to it.", {
        ivrael("Down past the yard and west. Be kind if you can. He was always very polite."),
      } },
    }),
  } },
}

S.sn_talk_recruit = {
  recruits("Have you eaten? Please say you have. It helps if I know you've eaten."),
}

S.sn_scene_ansel = {
  t("He's sitting on the floor of the passage in his clean uniform, with his boots together, the way he was taught. He has been chewing his own sleeve."),
  ansel("Oh, please stay back. Have you eaten? That's what I'm meant to say. I'm so sorry. I can hear you. I can hear all of you going round."),
  ask(ansel("Would you tell the sergeant I tried? I did nineteen days. I did it nearly right."), {
    { "We'll tell him.", {
      ansel("Thank you. That's all right, then."),
    } },
    topic("Sister, is there anything you can do?", {
      cleric("I can stay with him. That's what there is."),
    }),
    { "Stay where you are. We can help.", {} },
  }),
  ansel("I'm getting up now. I'm not doing it. Please be quick."),
  { battle = "sn_boss_ansel" },
  t("He stops being hungry. It happens all at once, and his face goes back to being about seventeen."),
  ansel("Mother's at Upriftin. She thinks it's the cavalry. Don't..."),
  { set = "sn_ansel_down" },
  { set = "sn_crossed" },
  ivrael("Thank you. Leave him, I'll see to him. They all get a letter. 'Gave his service gladly.' I write them myself. I've a nice hand."),
  deserter("I know that letter. Where I come from there's a whole office for it, every spring."),
}

-- ---------------------------------------------------------------- Syndalia

S.sn_syndalia_in = {
  t("You've been walking through gardens for a day before you understand that they're the fields. Melons to the horizon, and not a weed, not one thin dog."),
  t("Syndalia is a triangle of white streets around a spear of stone so tall it has weather. Three red ribbons, each wider than a road, go out from its head across the sky, and lift a little in the wind."),
  t("Everyone you pass is clean and well fed. Everyone smiles at you, and it takes a minute to work out what's wrong with that. It's the same smile."),
  deserter("Friend, I've been looking for a sick person for an hour. A cough. A limp. A bad tooth. I'd pay money for a boil."),
  cleric("There's a shrine of the Thread Weavers on that corner. With its door open."),
  t("A girl of about twelve steps in front of you with a tray. Her smile has a gap in it, and it goes up on the wrong side. After an hour of the other one, it's like a drink of water."),
  tam("Melon? It's free, it's all free, you just have to take some or they keep asking. Have you eaten? Say yes. You have to say it quite firmly."),
  { choice = {
    { "Yes. Quite firmly.", {
      tam("That's how! I'm Tam. Mum has the Full Table, the door on the west side. She'll want to feed you. You can't stop her. I've tried."),
    } },
    { "Why is your smile different?", {
      tam("It isn't anything. It's only that I've not had my Giving yet. It goes straight after. I've got till Friday."),
      t("She looks down at the tray. The smile stays where it is, but she has stopped being behind it."),
    } },
  } },
  owlin("The Citadel gate is at the north point. One simply asks, I gather."),
  { set = "sn_crossed" },
  { set = "sn_arrived" },
}

S.sn_talk_usher = {
  { when = "sn_dined", steps = {
    usher("His Excellency hopes you'll treat the house as your own."),
    warp("sn_citadel", "b", 1),
  }, other = {
    { when = "sn_has_card", steps = {
      { all = { "sn_sign_a", "sn_sign_b", "sn_sign_c" }, steps = {
        usher("All three hands. How nice. Do go up. Dinner's at dusk, and he never minds if you're late. He has never had to."),
        warp("sn_citadel", "b", 1),
      }, other = {
        usher("Your card wants its other hands: Antarith to the south, Eighstead on the coast, Upriftin in the north. There's no hurry at all. Nobody has been in a hurry here for some time."),
      } },
    }, other = {
      usher("Guests of His Excellency are always welcome, and I want that clearly understood. All that's wanted is the Courtesy."),
      t("He gives you a card, very thick, the colour of cream, with three lines ruled at the foot. It's probably the nicest thing you've ever been handed."),
      ask(usher("One hand from each of the three lords. It isn't a rule. We've no rules. It's only that it would be rude to arrive unannounced."), {
        topic("We've come for something from the throne.", {
          usher("Then you'll have it. People generally do."),
        }),
        { "We'll get your three hands.", {} },
      }),
      { give = "sn_card" },
      { set = "sn_has_card" },
    } },
  } },
}

S.sn_talk_anwen = {
  { when = "sn_tam_gone", steps = {
    { when = "sn_tam_found", steps = {
      anwen("You brought her up! And now she's off to Antarith for a rest. She'll come home for her Giving when she's better, won't she?"),
    }, other = {
      anwen("Tam's gone below for a rest. Two lovely young men came with a chair. Wasn't that thoughtful?"),
    } },
  }, other = {
    { when = "sn_fed", other = {
      anwen("Look at you! Have you eaten? You've got thin."),
      t("Nobody has said those words to you in that order since Scythebreak. She can't know why you've stopped in the doorway. She goes on smiling until you start again."),
      { set = "sn_fed" },
    } },
  } },
  ask(anwen("There's rice and peppers and the good melon, and a bed if you want one."), {
    topic("What do you charge?", {
      anwen("Charge? Oh, love. Nobody pays for a bed in Sindal. It's paid for."),
    }),
    topic("Tam seems frightened.", {
      { when = "sn_tam_gone", steps = {
        anwen("Frightened? Tam? It's only nerves, they all have them, the young ones. I said no myself, once. I can't think why."),
      }, other = {
        anwen("It's only nerves. She said no the first time. They do, the young ones. They ask so nicely. I said no myself. I can't think why."),
      } },
    }),
    { "A bed, please.", { { inn = 0 }, { save = true } } },
    { "Not now.", {} },
  }),
}

S.sn_talk_tam = {
  { when = "sn_knows_scar", steps = {
    tam("You keep looking at my neck. Everyone is, this week."),
  } },
  ask(tam("Have you eaten? Sorry. It just comes out."), {
    topic("What happens on Friday?", {
      tam("I'm twelve, so I get my first Giving. There's a party, and you sit in the nice chair. Everyone says it doesn't hurt, and they all say it the same way."),
    }),
    topic("What if you don't want to?", {
      tam("I said that. The Almoner said of course, nobody has to, and gave me a melon. Then Mum cried, and she smiled while she did it. They ask again, after. I don't know anyone who's said it twice."),
    }),
    { "You're doing fine.", {
      tam("You're the first person who hasn't said lovely. That's nice. That's different."),
    } },
  }),
}

S.sn_talk_amareth = {
  { when = "sn_prayed", steps = {
    ask(amareth("The door's never shut. Have you eaten?"), {
      topic("And the threads that go through the floor?", {
        amareth("Oh, those ones aren't dead. The threads aren't cut. They're only... stretched. I don't look at those much. It's a very big wheel."),
      }),
      { "We'd like to pray.", {
        t("The sister prays in her full voice. You all go out feeling better than you have any right to."),
        { heal = true },
        { save = true },
      } },
      { "Thank you, Mother.", {} },
    }),
  }, other = {
    t("The shrine smells of beeswax. There's a spool on the altar the size of a cartwheel, and black threads run off it through the wall, and through the floor. The door is open on the street."),
    amareth("Sister. I'd know that walk anywhere, that's someone who's been praying into her sleeve. You poor thing. You may do it out loud here."),
    cleric("Out loud."),
    amareth("Have you eaten?"),
    t("The sister kneels. For a long moment nothing happens. Then she begins the office for the dying in a voice you've never heard from her, a whole voice, that goes out of the door and down the street."),
    cleric("I've said that in cellars, and through my teeth with a Clinic lamp going by. I didn't know I still had that much of a voice."),
    ask(cleric("Give me a little while, {hero}. I'd just like to do it again."), {
      { "Take as long as you want.", {
        cleric("Thank you."),
      } },
      { "Doesn't this worry you?", {
        cleric("Of course it worries me. Ask me tomorrow. Today I'm going to be let."),
      } },
    }),
    { set = "sn_prayed" },
    { heal = true },
    { save = true },
  } },
}

S.sn_talk_severin = {
  ask(severin("The Chapel of the Open Hand. A cup a month from everyone of twelve and up, by the little lancet under the ear. Then melon and a ribbon. Over the door it says GIVE THE HAND A LITTLE, AND IT WILL NOT TAKE THE WHOLE."), {
    topic("Why does everyone smile the same way?", {
      severin("Do they? What a lovely thing to say."),
      deserter("Look at the woman in the chair, friend. Under the ear, that silver line. There's a nerve just there that lifts the corner of the mouth."),
      deserter("Nick it once a month and it scars, and the scar pulls. That isn't a smile. It's the same scar on all of them. They can't put it down."),
      { set = "sn_knows_scar" },
    }),
    { "I'll give a cup.", {
      { when = "sn_gave", steps = {
        severin("You've been more than generous. Please. Have some melon."),
      }, other = {
        t("A sting under the ear, and a glass the size of a thimble. The Almoner holds it to the light, then to his nose."),
        t("His smile doesn't move. It can't. But his hand sets the glass down very carefully at the far end of the table, and goes away from it."),
        severin("Thank you. We shan't be needing that. Please take your melon. Please take two."),
        { give = "potion", n = 2 },
        { set = "sn_gave" },
      } },
    } },
    { "Not today.", {
      severin("Of course. Nobody has to."),
    } },
  }),
}

S.sn_talk_perrin = {
  t("A thin man is sweeping the street. It's a clean street. He's sweeping a place he swept a moment ago."),
  perrin("It is a lovely day. Have you eaten?"),
}

S.sn_talk_oswin = {
  oswin("Constable Oswin, Splinter Cell of Fangs. If anybody troubles you, please, I want to hear about it. I had a case in the spring, a badly parked cart, and I've been living on it since."),
}

S.sn_talk_melon = {
  ask(dulcie("Dulcie Melon, and yes, I've heard it. Food's free, love. Blades are a trade. I sold a paper knife in the spring. Have you eaten?"), {
    { "Show me what you've got.", { { shop = "sn_shop_market" } } },
    { "Not just now.", {} },
  }),
}

S.sn_talk_fenwick = {
  ask(fenwick("You're frowning. Do that again. Oh, that's lovely. I've only my own left to look at, and I have to use a spoon."), {
    topic("You don't smile like the others.", {
      fenwick("I said no. Twice. I was ninety-one, and they sent a lovely young vampire who laughed and went home. It's the only freedom in the country, and it takes ninety years to earn."),
    }),
    topic("What was it like before?", {
      fenwick("Before I came down from Upriftin? People died of teeth. My sister hated me for sixty years, and I do miss it."),
    }),
    topic("Who's that man sweeping?", {
      fenwick("That's Perrin. He wrote comic verses about His Excellency. Very funny, they say. I'd tell you one, but nobody can remember any."),
    }),
    { "Mind how you go, old man.", {
      fenwick("Why? What's going to happen to me?"),
    } },
  }),
}

S.sn_talk_lira = {
  ask(lira("Candidate Lira, Arch Faith Institute. My thesis: fewest deaths per thousand of any state in history. Is there a figure you'd dispute? I'd honestly love one."), {
    topic("Scholar, can you answer her?", {
      owlin("Her figures are correct. I've checked two. It's the most distressing paper I've read in years."),
      lira("Thank you! I've put in a chapter on the people who aren't in the figures. My teachers have asked me to reconsider it. Very kindly. They've asked once."),
      { set = "sn_lira_chapter" },
    }),
    { "Good luck with it.", {} },
  }),
}

S.sn_talk_lira_after = {
  t("The Institute's front room is very clean. A young woman in a grey smock is sweeping it, with her hair in two plaits."),
  { when = "sn_lira_chapter", steps = {
    owlin("Candidate. The chapter. I had a reply prepared."),
  } },
  person("sn_lira_after", "THE SWEEPER")("It is a lovely day. I have withdrawn my thesis. Have you eaten?"),
}

-- ---------------------------------------------------------------- Antarith

local asphodel = person("sn_asphodel", "ASPHODEL SYREN")
local grub = person("sn_grub", "GRUB")
local newcomer = person("sn_newcomer", "THE NEWCOMER")
local vesh = person("sn_hostess", "VESH")
local thrax = person("sn_thrax", "MR THRAX")
local corin = person("sn_corin", "CORIN VALE")
local maren = person("sn_maren", "MAREN VALE")
local sabeth = person("sn_sabeth", "INQUISITOR SABETH")
local tam_safe = person("sn_tam_safe", "TAM")

S.sn_antarith_in = {
  t("Antarith is the same white stone and the same smile, on faces with horns. Something the size of a wardrobe is watering a window box. At the top of the town the air shimmers in one place: the portal to the Nine Hells."),
  deserter("The Clinic would have this whole town in a pit, friend. I don't know what I'm supposed to do with a devil holding a watering can."),
}

S.sn_pines_shut = {
  t("The south gate stands open on a road into black pines. A sentry looks at you, and then with great care looks somewhere else. There's nothing down there for you yet."),
}

local TAKE_THE_VALES = {
  asphodel("Thank you. The south gate, the moss at your back. The guards are very bad at it. I pay them to be."),
  { set = "sn_bats_go" },
}

S.sn_talk_asphodel = {
  { when = "sn_vales_out", steps = {
    asphodel("You're still frowning. Good. Keep doing that as long as you can."),
  }, other = {
    { when = "sn_sign_a", steps = {
      { when = "sn_bats_go", steps = {
        asphodel("Go, please. And I never said so."),
      }, other = {
        { when = "sn_dined", steps = {
          asphodel("You'll have seen the Vale house. He's very well. I signed for it. I want you to know that I read it first."),
        }, other = {
          ask(asphodel("The Vales are still in Church Row, and Sabeth is still in my square. It isn't too late."), {
            { "We'll take them.", TAKE_THE_VALES },
            { "Not now.", {} },
          }),
        } },
      } },
    }, other = { { when = "sn_has_card", other = {
      asphodel("Look at you, frowning. You can't know how restful that is. But there's no card in your hand, and nothing happens here without one. Go and ask at the Citadel gate."),
    }, steps = {
      asphodel("You'll be the ones with the card. Sit. Not that chair, it was made uncomfortable on purpose. Look at you, still frowning. You can't know how restful that is."),
      ask(asphodel("Ask what you came to ask. I find it's quicker if people go straight to the worst of it."), {
        topic("What does the peace cost?", {
          asphodel("Nobody's hungry and nobody's sick. I've read the figures, and I'd put them against any country on Embia. The price is a cup a month. Anyone who says no is asked again, very kindly."),
          asphodel("Anyone who says no twice is untrusted. Someone goes round, and after that they don't say no to anything."),
        }),
        topic("What's a thrall, exactly?", {
          asphodel("A person with the part removed that minds. They aren't in pain. I went on checking for years."),
        }),
        topic("And what are you?", {
          asphodel("A vampire who asked for this chair. There were three men in line for it, and I knew what each of them would do with it. I've touched no one unwilling in a hundred and ninety years. Don't admire that. I've signed every list that ever crossed this desk."),
        }),
        topic("Some people go further than thrall.", {
          asphodel("Yes. A list comes round every season. They go below Syndalia, and they don't come back as anything. It's the one thing here nobody will tell you, however nicely you ask."),
        }),
        { "Will you sign our card?", {} },
      }),
      t("She reads the card as if it might be a trap, and signs it in a small upright hand."),
      { set = "sn_sign_a" },
      asphodel("That wasn't a favour. This is. A cooper called Corin Vale said no on the first of the month, and again on the eighth. Inquisitor Sabeth is here with the paper, and she'll sit with him when she's finished her tea."),
      ask(asphodel("The Bats Nest is south of my gate. A family can get through if someone walks in front who can fight. Everyone I could ask has a smile to keep. Will you take them?"), {
        { "We'll take them.", TAKE_THE_VALES },
        { "We have our own road to walk.", {
          asphodel("Yes. You have. I'd have said the same, once. That's how I got this chair."),
        } },
      }),
    } } } },
  } },
}

S.sn_talk_grub = {
  ask(grub("Reformation Centre, new lives, claws trimmed free! I'm Grub, I was an imp of the Grinning Grabbers, and I've been reformed eleven times. Here's your purse back. Force of habit."), {
    topic("Does reformation work?", {
      grub("They ask how the torment made you feel. The big ones cry."),
    }),
    { "Keep your hands to yourself.", {
      grub("Thank you. Nobody's shouted at me all week."),
    } },
  }),
}

S.sn_talk_newcomer = {
  newcomer("Is this the Eighth Circle? They keep giving me soup. A woman just told me I've got kind eyes. I've been waiting for the trap for two days."),
}

S.sn_talk_hostess = {
  ask(vesh("Welcome to the Second Chance. Beds for all sizes, the chimney's been widened, and there's a shelf of useful things. No charge for the bed. Have you eaten?"), {
    { "A bed, please.", { { inn = 0 }, { save = true } } },
    { "Show me the shelf.", { { shop = "sn_shop_antarith" } } },
    { "Not now.", {} },
  }),
}

S.sn_talk_thrax = {
  ask(thrax("Peonies? Thrax, formerly of Soul Processing, the Seventh Circle. Peonies don't scream when you get it wrong. I've no idea how anyone learns."), {
    { "They're very nice peonies.", {
      thrax("Are they really? Everybody here just says it."),
    } },
    { "Good day.", {} },
  }),
}

S.sn_talk_corin = {
  { when = "sn_dined", steps = {
    t("Corin Vale is sitting at the table with his hands flat upon it. He looks very well."),
    corin("It is a lovely day. Have you eaten?"),
  }, other = {
    corin("I only said no thank you, and then I said it again. I made a cask once with a flaw in it, and I thought, that's the only thing I've ever made that looks like me. Then I went in for my Giving, and I just didn't sit down."),
  } },
}

S.sn_talk_maren = {
  { when = "sn_dined", steps = {
    maren("Corin's so much better. I don't know why I keep sitting down on the stairs."),
  }, other = {
    maren("Our Jory's six. He's got no scar yet. I look at him and think, you'll be able to frown at me one day, when you're cross. I'd like that very much."),
  } },
}

S.sn_talk_sabeth = {
  sabeth("Inquisitor Sabeth. Don't get up. I always take my tea in the square before a visit. Unhappiness is a very sad thing, and it spreads. I do so like to get to it early."),
}

S.sn_talk_tam_safe = {
  tam_safe("Lady Asphodel says I can stay. Mr Thrax is teaching me bulbs. I keep saying 'have you eaten' to the devils, and they get frightened. It's nice."),
}

-- ---------------------------------------------------------------- the Bats Nest

S.sn_bats_in = {
  t("The Vales walk behind you: Corin, Maren with a bundle, and a boy of six who's been told it's a game. The road closes behind them. The pines stand so thick that it's dusk by noon."),
}

S.sn_bats_blaze = {
  t("A dead pine, with something cut into it low down, where a child could read it. KEEP THE MOSS AT YOUR BACK. Below it, in dozens of hands, a long column of tally marks. At the bottom, very small: HAVE YOU EATEN? NO. GOOD."),
  { set = "sn_blaze" },
}

S.sn_bats_turned = {
  t("The trees thin, and you're sure of the way. You walk for some time. Then there's a familiar stump, and the small boy pointing at it and laughing."),
  corin("It does that. The last ones through always leave a mark. It'll be off the path somewhere."),
  warp("sn_bats_1", "s", 2),
}

S.sn_hollow_in = {
  t("Under the roots the wood is hollow. Over a pit hangs something like a black ceiling, breathing. Thousands of them. Maren puts her hand gently over the boy's mouth."),
}

S.sn_scene_sabeth = {
  t("She's waiting where the roots open to the south, on a folding stool, with a flask of tea. She looks pleased to see you. You suspect it's sincere."),
  sabeth("Good evening. Corin, Maren, you look tired. There's no need for any of this. Nobody is cross."),
  deserter("'Nobody is cross.' I've used that one. I used it on a cart. I had no idea how it sounded from over here."),
  ask(sabeth("I'll ask you once. Step away from the family, and go and have your dinner. Then I'll ask again."), {
    { "No.", { sabeth("That's once.") } },
    { "Corin Vale says no thank you.", { sabeth("Yes, that's rather how it began. That's once.") } },
  }),
  sabeth("No?"),
  t("It's asked very gently. She puts down the tea, and takes something long and thin from inside her coat."),
  { battle = "sn_boss_sabeth" },
  t("Her bowler rolls a little way and settles on its brim. The flask is still warm."),
  { set = "sn_sabeth_down" },
}

S.sn_pines_end = {
  t("A line of white stones crosses the path. Two sentries are fast asleep, with great concentration."),
  corin("Thank you. I don't... Have you eaten?"),
  t("He hears himself. He stands there in the road with his mouth open. Then he begins to laugh, or something like it, and Maren takes his arm and walks him over the line."),
  t("The boy looks back and waves. He's frowning, because the game's over. It's the best thing you've seen all month."),
  { set = "sn_vales_out" },
}

S.sn_pines_leave = {
  { when = "sn_vales_out", steps = {
    warp("sn_antarith", "s", 4),
    { when = "sn_ringed", other = {
      asphodel("Over the line? All three? Good. Sabeth had an accident in the pines. They happen. Take this. It was given to me by a better woman than I am, and I've already said yes to everything."),
      { give = "oath_ring" },
      { set = "sn_ringed" },
    } },
  }, other = {
    t("The Vales are waiting for you to see them over the line."),
  } },
}

-- ---------------------------------------------------------------- Eighstead

local ceiridwen = person("sn_ceiridwen", "CEIRIDWEN HEARTFORD")
local bram = person("sn_bram", "JOSS THE COOPER")
local tallow = person("sn_tallow", "OLD BARLOW")
local hob = person("sn_sailor", "JEB THE SAILOR")
local chandler = person("sn_chandler", "THE CHANDLER")
local scraper = person("sn_scraper", "THE SCRAPER")
local thrush = person("sn_thrush", "THRUSH")

S.sn_eighstead_in = {
  t("Eighstead is warm and loud and smells of tar and frying. They smile the same smile here, but they do it with their sleeves rolled up."),
  deserter("I could almost like it. I'm going to try not to."),
}

S.sn_hold_shut = {
  t("A painted board says THE GOOD NEIGHBOUR, and under that, NOT WITHOUT THE LADY'S SAY-SO."),
}

S.sn_talk_ceiridwen = {
  { when = "sn_sign_c", steps = {
    ask(ceiridwen("Back for more crab? Sit! You're all skin and worry."), {
      topic("Doesn't any of it trouble you?", {
        ceiridwen("I was born on that beach in the last famine, love. I carried my sisters up it. I'm nine hundred and four, and I haven't seen a hungry child in eight hundred of those. I ship the casks. I'd like you to know that I sleep fine."),
      }),
      { "We'll be going.", {} },
    }),
  }, other = {
    { when = "sn_thrush_gone", steps = {
      t("You tell her about the space behind the bulkhead, the ledgers and the lavender."),
      ceiridwen("Three years? On MY ship? I've been carrying the Clinic's clerk up and down the coast for nothing? Ha! I should have charged him berth!"),
      t("The laugh goes on for a while, and then it doesn't. She takes off the great hat and looks into it."),
      ceiridwen("They buy on Black Peaks paper and pay on the day. I always knew it went to Adaphis. But that's a few hundred casks. What would anyone want with the total?"),
      owlin("I'd suggest you tell His Excellency."),
      ceiridwen("'How interesting.' That's what he'll say. Give me the card. You've earned it."),
      t("She signs with a hand like a bosun's, leaves a thumbprint in tar, and counts coin out onto the chart."),
      { gold = 600 },
      { set = "sn_sign_c" },
    }, other = {
      { when = "sn_hold_open", steps = {
        ceiridwen("Dry dock's through the cooper's, south side. I want one number, the same number twice!"),
      }, other = { { when = "sn_has_card", other = {
        ceiridwen("Ha! Have you eaten? No, really, have you? I've got crab, and no time. Everybody gets to dinner in the end, but it starts at the Citadel gate. Get yourselves a card, and then we'll talk."),
      }, steps = {
        ceiridwen("Ha! Strangers! Shove the charts off and sit. Ceiridwen Heartford, Crafters' Guild, Synder Fleet, and the biggest hat in the Empire. Have you eaten? No, really, have you? I've got crab."),
        ask(ceiridwen("A card, is it? Everybody gets to dinner in the end. But I never put my hand to anything for someone I haven't seen work."), {
          topic("What's in the casks?", {
            ceiridwen("You've been to the Chapel, haven't you? Then you know what's in the casks. Don't look like that, sit down. It's only trade."),
          }),
          { "What's the job?", {} },
        }),
        ceiridwen("I've a cask ship in the dry dock, the Good Neighbour. Every man I send down to count her comes back with a different number. Nobody's hurt. They're just wrong, and I can't sail with wrong sums."),
        { choice = {
          { "We'll go down and count.", {} },
          { "All this for a signature?", {
            ceiridwen("A signature and a plate of crab! Mind yourselves. It smells funny down there, and I can't place it."),
          } },
        } },
        { set = "sn_hold_open" },
      } } } },
    } },
  } },
}

S.sn_talk_bram = {
  ask(bram("Joss, master cooper. Best casks on the coast. They'd have to be, it wouldn't do to spill. Have you eaten?"), {
    topic("Seen anything odd on the Good Neighbour?", {
      bram("Violet chalk on some of the casks, small and neat. Isn't ours. We use white."),
    }),
    { "Good day.", {} },
  }),
}

S.sn_talk_tallow = {
  ask(tallow("The Sound Barrel, dears. Nine hundred years Lady Ceiridwen's been drinking here, and I've never seen her swallow. Have you eaten?"), {
    { "A bed, please.", { { inn = 0 }, { save = true } } },
    { "Not now.", {} },
  }),
}

S.sn_talk_sailor = {
  ask(hob("Back from the north run. We go as far as the ice, then we turn. Everyone turns at the ice. Have you eaten?"), {
    topic("What's past the ice?", {
      hob("Thuluan. Black reeds. You hear singing on a still night, old women's voices, very sweet. There's a law against it. Not against going. Against answering."),
    }),
    { "Fair winds.", {} },
  }),
}

S.sn_talk_chandler = {
  ask(chandler("Rope, lamps, swords, sundries. And things that fell off ships. Nothing falls off her ships. It's just a thing we say, for the fun of it."), {
    { "Show me your stock.", { { shop = "sn_shop_eighstead" } } },
    { "Not today.", {} },
  }),
}

S.sn_talk_scraper = {
  t("A thrall in a wide hat is scraping a hull that isn't there, working along the empty air above the quay, one careful stroke at a time. The ship left in the spring."),
  scraper("It is a lovely day."),
}

-- ---------------------------------------------------------------- the Good Neighbour

S.sn_hold_in = {
  t("The hold is warm and very clean. Casks go away into the dark in tiers, and the air is sweet with oak and a thin note of iron. The doctor stops on the ladder and doesn't come down."),
  deserter("Friend. Under the oak. Do you smell that? I know of one institution on Embia that boils its linen in lavender."),
}

local CHALK_ADDS_UP = {
  count = { "sn_chalk_1", "sn_chalk_2", "sn_chalk_3" }, at = 3,
  steps = {
    owlin("Three violet marks, three bearings. Laid over the ship's plan, they agree on one place: the sheeted stack at the bottom of the mid hold. Someone has been navigating by casks."),
    { set = "sn_bulkhead" },
  },
}

S.sn_cask_1 = { t("A cask marked in violet chalk, in a beautiful hand: a figure, an arrow, and a tick."), { set = "sn_chalk_1" }, CHALK_ADDS_UP }
S.sn_cask_2 = { t("Another violet mark. The tick is fresh. An arrow points the other way from the last."), { set = "sn_chalk_2" }, CHALK_ADDS_UP }
S.sn_cask_3 = { t("Violet chalk again. Someone has knelt here often enough to wear the boards pale."), { set = "sn_chalk_3" }, CHALK_ADDS_UP }

S.sn_talk_sheeted = {
  t("A stack of casks under a sheet, too heavy to shift without a reason. It smells of lavender. There are marks elsewhere in the hold that might give you one."),
}

S.sn_scene_thrush = {
  t("Behind the stack is a space the size of a pantry: a cot, a set of scales, a shelf of ledgers, and sachets of lavender on a string. A thin man in a Clinic coat looks up from his sums."),
  thrush("Doctor! They told me you'd run. You still owe me eleven silver."),
  deserter("Thrush. You were the worst anatomist of our year."),
  thrush("I was the best at sums. Three years on this ship, and nobody's asked me if I've eaten. It's been a holiday."),
  ask(thrush("It's all done now, so you may as well ask."), {
    topic("What are you counting?", {
      thrush("Not casks. Every cistern and every neck. I've got the whole country to within a pint."),
    }),
    topic("Who wants that?", {
      thrush("Doctor Colette wants a number. She was very particular. Not a sample and not a supplier. A total."),
    }),
    { "What is it for?", {} },
  }),
  thrush("I keep the pages. I've learned not to wonder."),
  { when = "px_done", steps = {
    deserter("She asked for one person's blood, friend, when we stood in front of her. What does she want with all the rest?"),
  }, other = {
    deserter("Colette has never wasted a clerk in her life. Three years of one, to weigh a country's blood. What on Embia for?"),
  } },
  owlin("Nobody weighs a river to drink it. There are very old workings priced by the measure. I've only met them in footnotes. Someone in Adaphis has been reading the footnotes."),
  thrush("The last figure went ashore last month, so this is only tidying. These two gentlemen will see to it."),
  { battle = "sn_clinic_men" },
  t("When the noise stops he's sitting just where he was, with a small empty bottle beside him and the pen still in his hand. He has finished the column."),
  deserter("Eleven silver. I'd have paid him, you know."),
  { set = "sn_thrush_gone" },
}

-- ---------------------------------------------------------------- Upriftin

local barnabas = person("sn_barnabas", "BARNABAS KNIFE TOOTH")
local quill = person("sn_quill", "DOCTOR MOTT")
local hesper = person("sn_hesper", "HESPER WANE")
local hesper_ice = person("sn_hesper_ice", "HESPER WANE")
local grim = person("sn_host_frown", "GRIM THE HOST")
local beggar = person("sn_beggar", "THE BEGGAR")
local furrier = person("sn_furrier", "THE FURRIER")
local bress = person("sn_soup", "MOTHER BRESS")
local nettle = person("sn_berry", "NETTLE")
local iceman = person("sn_iceman", "THE ICEMAN")
local cellboy = person("sn_cell_boy", "A BOY IN RED")

S.sn_upriftin_in = {
  t("Upriftin is flat and white and bitterly cold, and the hedges are heavy with red berries. A man on the corner in a coat with holes in it looks you up and down, and scowls."),
  deserter("Oh, thank goodness."),
  { when = "sn_knows_scar", steps = {
    cleric("He has the scar, but it's old. I'd say they sell their cups here, when they're short."),
  }, other = {
    cleric("There's a silver line under his ear, but it's old. Whatever they do to faces in this country, it's stopped working on his."),
  } },
}

local BARNABAS_SIGNS = {
  barnabas("A signature! For you, fifty gold. Don't look at me like that. I have a reputation."),
  { paid = 50, steps = {
    barnabas("A pleasure! Here's your receipt. It's also a threat, but it's mostly a receipt."),
  }, other = {
    barnabas("Skint? Ha! I like you more and more. It'll go on your bill. You'll find it's a very long bill."),
  } },
  t("He signs across all three lines, and then, seeing what he's done, looks delighted."),
  { set = "sn_sign_b" },
  barnabas("Now then. You're going to dinner, and I can't get a glass within a mile of that table. All it wants is a drop of this in his wine. It would only make him a bit unwell."),
  t("He holds up a small phial. It smells of cloves."),
  ask(barnabas("Well? There'd be a great deal of money in it. There's always a great deal of money in it."), {
    { "We'll think about it.", {
      barnabas("Do! Thinking's free. It's the only thing here that is, and I'm looking into that."),
    } },
    { "Give it here.", {
      barnabas("Ha! Honest faces! Honest faces will do anything."),
      { set = "sn_phial" },
    } },
    topic("What would happen to the country?", {
      barnabas("Prices, feuds, bad teeth! They'd get their own faces back. You have no idea what they'd pay."),
    }),
  }),
}

S.sn_talk_barnabas = {
  { when = "sn_sign_b", steps = {
    { when = "sn_cells_empty", steps = {
      barnabas("Partners! Three hundred boys, and he had them met with brooms. I've had a very nice note about it. Have you eaten? Ha! It isn't any funnier."),
    }, other = {
      { when = "sn_coup_backed", steps = {
        barnabas("Partners! Have you eaten? Ha! I can't say it with a straight face. Nobody can, that's the secret."),
      }, other = {
        barnabas("Mind the icehouse lane, it's private. I wouldn't go there if I were you. I said that very clearly, and I hope it's written down."),
      } },
    } },
  }, other = {
    { when = "sn_has_card", steps = {
      { when = "sn_reserve_done", steps = BARNABAS_SIGNS, other = {
        barnabas("A frown! Look at that, a real one, that's Clinic work! Come in, shut the door, you're letting the money out. Barnabas Knife Tooth, Lord of Upriftin. Yes, the tooth is real. I had it made."),
        t("He taps it with a fingernail, and it rings. One of his teeth is a hand's length of bright steel."),
        ask(barnabas("I'm the only crook in the Veins of Sindal, my friends, and you'll find me very refreshing. What do you need?"), {
          topic("Why are there poor people here?", {
            barnabas("I brought them in specially! In Upriftin a cup's two silver, if you're short. So people get short. A country needs one place where a person can still go wrong."),
          }),
          { "We need your hand on this card.", BARNABAS_SIGNS },
        }),
      } },
    }, other = {
      barnabas("A frown! I do like a frown. Come back with the Usher's card, my friends. I only rob people who've been properly introduced."),
    } },
  } },
}

S.sn_talk_barnabas_smiling = {
  t("A huge man in a grey smock is sweeping the great hall of the keep. There's a gap in his teeth where something used to be. He looks very well."),
  person("sn_barnabas_smiling", "BARNABAS")("It is a lovely day. Have you eaten?"),
}

S.sn_talk_quill = {
  ask(quill("Don't touch that, it's four thousand years old! Doctor Mott, Antiquarian to His Excellency. We look for old things with teeth. Look at this one!"), {
    topic("What's that?", {
      t("A single black scale as big as a door, propped in a corner. It isn't reflecting anything."),
      quill("From the Hollow One, we think, Tiamat's own black head. His Excellency wants her woken. There's a library very far down, with a thing in it that knows how."),
    }),
    { "Mind you don't cut yourself.", {
      quill("Oh, I don't bleed. I gave that up."),
    } },
  }),
}

S.sn_talk_hesper = {
  { when = "sn_hesper_met", steps = {
    { when = "sn_coup_broken", steps = {
      hesper("It's a bad end to a bad business, and it's the best I've seen. I'll take that."),
    }, other = {
      { when = "sn_cells_empty", steps = {
        hesper("The sleds came back up empty. I counted those too."),
      }, other = {
        hesper("You know where the icehouse is. I'm only telling you what I counted."),
      } },
    } },
  }, other = {
    hesper("You came in by the Crevice. There's a boy of mine went that way, Ansel Wane. He's for the cavalry, he says. I've not had a letter since spring."),
    { when = "sn_ansel_down", steps = {
      t("The doctor looks at you, and then at the floor. Nobody else is going to do this."),
      { choice = {
        { "He died at the post. I'm sorry.", {
          hesper("Did he. Yes. Was it clean?"),
          hero("It was quick. He asked us to be."),
          hesper("Thank you. Nobody says. There'll be a very nice letter, won't there? I've two of those already, from his brothers."),
          { set = "sn_told_hesper" },
        } },
        { "He's well. He asked after you.", {
          hesper("Did he, now. That's good."),
          t("She looks at you for some time. She's been a hunter for thirty years, and she knows what a track looks like when something has been dragged over it."),
          { set = "sn_lied_hesper" },
        } },
      } },
    } },
    { when = "sn_coup_broken", steps = {
      hesper("It's a bad end to a bad business, and it's the best I've seen. I'll take that."),
    }, other = {
      hesper("Count the sleds, if you want to know what's wrong in this town. Meat goes in at the old icehouse every week, and more lads go through that door than ever reached the Crevice. Tell old Dowd on the icehouse door I said to let you by. He owes me for a winter."),
      { set = "sn_ice_tip" },
    } },
    { set = "sn_hesper_met" },
  } },
}

S.sn_talk_iceman = {
  ask(iceman("Icehouse is shut. Lord's orders. There's nothing in it but ice, and it isn't any of your business."), {
    { "A hundred gold says it isn't shut.", {
      { paid = 100, steps = {
        iceman("Well now. It's a funny old lock. Sometimes it just falls open."),
        { set = "sn_ice_tip" },
      }, other = {
        iceman("Say that again when you've got it."),
      } },
    } },
    { "Never mind.", {} },
  }),
}

S.sn_talk_host_frown = {
  ask(grim("The Honest Frown. Twenty gold a bed, cash. It's a terrible bed, but it's mine to charge for. What do you want?"), {
    { "A bed, please. (20 gold)", { { inn = 20 }, { save = true } } },
    { "Not now.", {} },
  }),
}

S.sn_talk_beggar = {
  beggar("Spare a coin for the only beggar in the Empire? I've a licence, and three houses. A lady from Syndalia paid extra just to touch my coat. No? Sod off, then."),
}

S.sn_talk_furrier = {
  ask(furrier("Furs, hides, and anything else a person has stopped needing. It's the last place in the country you can be cheated."), {
    { "Show me what you've got.", { { shop = "sn_shop_furrier" } } },
    { "I'll keep my money.", {} },
  }),
}

S.sn_talk_soup = {
  bress("Soup's a copper. Forty years I've fed this street, and nobody's thanked me once. Lovely people. I've been to Syndalia. You've no idea."),
}

S.sn_talk_berry = {
  nettle("Berries. One silver the bag. They're sour. When I'm twelve Mum'll sell my cup for coal, and I'll get the face. I do it in the window to see. I look like everybody."),
}

-- ---------------------------------------------------------------- the Reserve

S.sn_ice_in = {
  t("The icehouse goes down a good deal farther than an icehouse needs to. Lake ice stands in blocks to the roof. From a long way below, very faint, someone is saying 'sorry'."),
}

local LOWER_GATE = {
  all = { "sn_lever_a", "sn_lever_b" },
  steps = {
    t("Far off, a counterweight drops. The gate at the head of the lower stair rises into the roof with a groan."),
    { set = "sn_ice_lifted" },
  },
}

S.sn_talk_lever_a = {
  { when = "sn_lever_a", steps = { t("The windlass is drawn and pinned.") }, other = {
    t("A thrall stands frozen to a windlass marked UPPER STOP. He's still smiling."),
    { choice = {
      { "Draw it.", { { set = "sn_lever_a" }, LOWER_GATE } },
      { "Leave it.", {} },
    } },
  } },
}

S.sn_talk_lever_b = {
  { when = "sn_lever_b", steps = { t("The windlass is drawn and pinned.") }, other = {
    t("A thrall stands frozen to a windlass marked LOWER STOP. Somebody has scratched on the casing: DON'T."),
    { choice = {
      { "Draw it.", { { set = "sn_lever_b" }, LOWER_GATE } },
      { "Leave it.", {} },
    } },
  } },
}

S.sn_talk_ice_gate = {
  t("A thrall holds the lower stair gate. It's on two stops, one north, one south. He's frozen to it."),
}

S.sn_reserve_in = {
  t("Long cold rows of cells. In each a boy in clean red stands at attention, with frost on his shoulders and his eyes wide open. They follow you. There are a great many cells."),
  deserter("Starved and kept cold, so it doesn't kill them and it doesn't stop. I couldn't have done it better. I want that noted."),
}

S.sn_talk_cell_boy = {
  cellboy("Is it time? Have you eaten? I'm Tobit Wane. I'm for the cavalry. Tell Mother I'm in the cavalry."),
}

S.sn_scene_reserve = {
  { when = "sn_sign_b", steps = {
    barnabas("There you are! I did say the icehouse was private. I didn't say it very loud. Three hundred boys, and not a mouthful in a hundred days."),
  }, other = {
    barnabas("A frown, down here! Look at that, a real one. Barnabas Knife Tooth, Lord of Upriftin, and you've found my icehouse. Three hundred boys, and not a mouthful in a hundred days."),
  } },
  barnabas("At the Thanksgiving Feast I open the culvert and pour them up the ribbon line into the Chapels of Syndalia. The Stitchers run to the screaming. And I walk up the quiet stairs with a knife."),
  ask(barnabas("You're the only people I've met in four hundred years with a working conscience. Well?"), {
    topic("What happens to the boys?", {
      barnabas("They die, of course. They'd have died poor anyway. This way it's for something."),
    }),
    topic("And the people in the chapels?", {
      barnabas("A few thousand. He's had millions, and they thanked him. I'm offering them someone to hate."),
    }),
    { "It ends here. Open the cells.", {
      barnabas("Ha! You'd save a country that thanks its butcher? Oh, I do like you. It's such a pity about the teeth."),
      { battle = "sn_boss_barnabas" },
      t("He goes down on one knee, laughing, with the steel tooth snapped off in his hand."),
      barnabas("So that's being told no by someone who means it. It's horrible! Well, go on. Finish it. Or give me to him, and see which you like better."),
      { choice = {
        { "Let Sindal have you.", {
          t("Hunters from the town come down the stair with rope. He's still laughing when they take him up. You don't suppose he will be for much longer."),
          { set = "sn_barnabas_given" },
          { when = "sn_done", steps = { { set = "sn_barnabas_swept" } } },
        } },
        { "Finish it.", {
          t("For a moment you think he's going to say something clever. Then there's only a lot of very old dust, and a tooth."),
          { set = "sn_barnabas_dead" },
        } },
      } },
      { when = "sn_sign_b", other = {
        { when = "sn_has_card", steps = {
          t("The doctor takes the seal from the chain on the floor, and presses it onto his line of the card. It's a very good seal. Nobody in the Empire is going to argue with it."),
        }, other = {
          t("The doctor takes the seal from the chain on the floor, and keeps it for whatever card comes along. It's a very good seal. Nobody in the Empire is going to argue with it."),
        } },
        { set = "sn_sign_b" },
      } },
      { set = "sn_coup_broken" },
      { set = "sn_cells_empty" },
      { set = "side_barnabas" },
      { set = "sn_reserve_done" },
      deserter("They'll have to be fed a little at a time. I can write that out. It's the one thing I'm truly qualified for."),
    } },
    { "All right. We're in.", {
      barnabas("Ha! Honest faces! Here's for your trouble. Now go away and look innocent. You've the faces for it."),
      { gold = 800 },
      { set = "sn_coup_backed" },
      { set = "sn_reserve_done" },
    } },
  }),
}

S.sn_talk_hesper_ice = {
  hesper_ice("We can't have them home. They can't be what they were. But the doctor's written out a feeding, and a lady in Antarith says she'll take anyone. I found Tobit. He told me he's in the cavalry. I said I know, love."),
}

-- ---------------------------------------------------------------- the Spear Citadel

local sindal = person("sn_sindal", "SINDAL DEVEROUS")
local undella = person("sn_undella", "UNDELLA")
local steward = person("sn_steward", "THE BUTLER")
local cellarmaster = person("sn_cellarmaster", "THE CELLARMASTER")
local gateman = person("sn_gateman", "A THRALL")
local sluice_n = person("sn_sluice_n", "THE COLD LINE")
local sluice_s = person("sn_sluice_s", "THE DEVILS' LINE")
local sluice_w = person("sn_sluice_w", "THE SEA LINE")

S.sn_gallery_note = {
  t("One of the ribbons passes close enough to touch. It isn't cloth. It's as thick as a street, ribbed and hollow, and it swells a little, very slowly, and subsides."),
  deserter("Count with me, friend. There. And there. Once a minute. I've been calling that a flag since we got here, and I went to medical school."),
}

S.sn_talk_steward = {
  steward("The cellars aren't on the evening's tour, but nothing's forbidden. It's only that dinner would get cold. Do go up."),
}

S.sn_scene_dinner = {
  t("The dining room is at the top of the world, with all of Ebrein below turning gold. A small table has been laid for four. Nobody sent word that there would be four of you."),
  sindal("Come in, come in! What a dreadful journey, I've had it all read to me. Sit. I'm Sindal. This is my wife Undella, who doesn't talk at table, and I find that very restful."),
  t("He looks about forty, brown from the sun, like someone who has slept well every night of his life, and he has the easiest laugh you've ever heard. You like him. You notice yourself doing it."),
  sindal("Sister, would you say the grace? No, I insist. It's such a long time since anyone here meant one."),
  t("She says the old words of the Thread Weavers aloud, in a room with the oldest thing on Embia in it. Her voice shakes, and then it doesn't."),
  sindal("Beautiful. Do eat. I don't, but I so like to watch."),
  ask(sindal("You've been told all sorts of things about me. Ask me anything you like. I've nothing to hide. I gave that up years ago, it's so much less work."), {
    topic("How do you keep them all so well?", {
      sindal("You know this, doctor, you kept a ward. Feed them, keep them warm, keep them calm. The only difference between us is that I never needed a cart."),
      deserter("No. You've got a stair."),
      sindal("Oh, very good. I do like you."),
    }),
    topic("Doctor Colette has been counting your blood.", {
      sindal("I know! Ceiridwen sends me the bills. I do so like to see a young person take an interest. What could she possibly do with it?"),
      { when = "px_done", steps = {
        sindal("You've met her. Did she ask for your blood? She asked me for mine. By letter, with diagrams. I was so touched."),
      }, other = {
        sindal("She asked me for my blood. By letter, with diagrams. I was so touched."),
      } },
    }),
    topic("What do you want, after all this time?", {
      sindal("A hobby! There's something very old asleep a long way under us that I'd love to wake. Forgive me, it's very dull for anyone else."),
    }),
    { "Lucilda the Vulture sent us.", {} },
  }),
  sindal("Lucilda! How is she? I gave that woman an old eye out of a cabinet for the freedom of every hag in Thuluan, and I've been laughing about it for three hundred years. What does she want?"),
  hero("Something from your throne."),
  sindal("She would. Excuse me one moment."),
  t("He goes through a small door, humming. He comes back with a silk tassel, rather faded, and puts it in your hand."),
  sindal("Off the cushion. It's been on that throne since the Horned War, and I shan't miss it. Was that all? Oh, my dears. Did you think I'd make you fight for it?"),
  { give = "sn_tassel" },
  { set = "sn_token" },
  owlin("Three cities, and a good deal of walking. I should like it noted that this is a tassel."),
  sindal("Everyone leaves my table with what they came for. That's the whole of my policy. You'd be amazed how far it goes."),
  { when = "sn_phial", steps = {
    { when = "sn_coup_broken", other = {
      t("His glass stands by your hand. Nobody's looking. The phial is in your sleeve."),
      { choice = {
        { "Leave it where it is.", {} },
        { "Tip the phial into his glass.", {
          t("He picks up the glass, breathes in, and takes a long, slow, contented sip."),
          sindal("Cloves. Barnabas does use too much clove. That's eleven now. It's how he says hello."),
          { set = "sn_poured" },
        } },
      } },
    } },
  } },
  t("He has been looking at you for some time, like a man trying to place a tune."),
  { when = "sn_gave", steps = {
    sindal("My Almoner sent up a very small glass of yours, with a very worried note."),
  } },
  ask(sindal("Forgive me, this isn't polite. I've had every sort of blood at this table for two thousand years, and there's always a note of something. Fear, mutton, somebody's grandfather. Yours has a door in it, and the door is shut."), {
    { "What does that mean?", {
      sindal("I've no idea. I shouldn't open it, if I were you. I wouldn't touch it if you paid me. There, what a dreadful thing to say to a guest. Have some melon."),
    } },
    { "Say nothing.", {
      sindal("Quite right. Have some melon."),
    } },
  }),
  t("At the door a cold hand closes on your sleeve. Undella hasn't looked up. Her lips barely move."),
  undella("The innkeeper's girl said no a second time, at noon. She is below. He wouldn't mind your knowing. He simply wouldn't think to say."),
  deserter("The stair, friend. East side of the gallery. Don't run. Nobody will stop us, and I find that's the worst of it."),
  { set = "sn_tam_gone" },
  { set = "sn_dined" },
}

S.sn_talk_sindal = {
  { when = "sn_done", steps = {
    sindal("Back again? How nice. The new man's very promising. You must let him try you."),
  }, other = {
    { when = "sn_tam_found", steps = {
      sindal("Not this way, my dears. The door's at the foot of the gallery. I'll bring a lamp."),
    }, other = {
      sindal("Still here? Have you seen the cellars? You must. Everyone should see how the thing is done, once."),
    } },
  } },
}

S.sn_talk_undella = {
  t("Undella sits with her hands in her lap. There's a small scar under her left ear, very old."),
}

-- ---------------------------------------------------------------- the Veins

S.sn_veins_in = {
  t("The stair goes down through the root of the Spear for a long time. At the bottom the tile begins, clean and wet, and the ribbons come in through the roof as pipes as wide as a house, and empty into a lake."),
  t("There is a long brass handrail, and a small polite sign on it. PLEASE DO NOT LEAN."),
  deserter("This is the best-kept ward I've ever seen. Look at the drains, friend. I've begged for drains like that."),
}

S.sn_veins_threads = {
  t("Black threads come down through the ceiling in their thousands, fine as hair, and run along the wall beside the pipes. The sister puts out one finger, not quite touching."),
  { when = "sn_prayed", steps = {
    cleric("Every one of them's a life. Most go on along the wall. A few go through the floor, like the ones off Mother Amareth's spool."),
  }, other = {
    cleric("Every one of them's a life. Most go on along the wall. A few go through the floor. I don't think anyone up there looks at those."),
  } },
}

S.sn_veins_plaque = {
  t("A polished brass plaque. TO TURN THE FLOW: FIRST THE COLD LINE, THEN THE DEVILS' LINE, AND LAST THE SEA. PLEASE DO NOT LEAN."),
}

local WRONG_LINE = {
  t("A long sigh in the pipes, and all three thralls turn their wheels back to the start. They look very happy to do it."),
  { unset = "sn_line_1" },
  { unset = "sn_line_2" },
}

S.sn_talk_sluice_n = {
  { when = "sn_line_1", steps = { sluice_n("The cold line is turned. It is a lovely day.") }, other = {
    { when = "sn_sluiced", other = {
      ask(sluice_n("I am the cold line. Have you eaten?"), {
        { "Turn the line.", { t("The great wheel goes round, and the note of the pipes goes down."), { set = "sn_line_1" } } },
        { "Not yet.", {} },
      }),
    } },
  } },
}

S.sn_talk_sluice_s = {
  { when = "sn_line_2", steps = { sluice_s("The devils' line is turned. It is a lovely day.") }, other = {
    { when = "sn_sluiced", other = {
      ask(sluice_s("I am the devils' line. Have you eaten?"), {
        { "Turn the line.", {
          { when = "sn_line_1", steps = { t("The great wheel goes round, and the note goes down again."), { set = "sn_line_2" } }, other = WRONG_LINE },
        } },
        { "Not yet.", {} },
      }),
    } },
  } },
}

S.sn_talk_sluice_w = {
  { when = "sn_sluiced", steps = { sluice_w("It is a lovely day.") }, other = {
    ask(sluice_w("I am the sea line. Have you eaten?"), {
      { "Turn the line.", {
        { when = "sn_line_2", steps = {
          t("The great wheel goes round. All through the works the noise of the water drops away, and in the quiet you hear a gate lifting, and someone a long way off, humming."),
          { set = "sn_sluiced" },
        }, other = WRONG_LINE },
      } },
      { "Not yet.", {} },
    }),
  } },
}

S.sn_talk_gateman = {
  gateman("The gate is shut while the lines run. It is a lovely day. Have you eaten?"),
}

S.sn_cellar_in = {
  t("Past the gate are old brick and racks, floor to ceiling. Every rack has a label in a beautiful hand. 'UPRIFTIN, HARD WINTER. SURPRISINGLY BRIGHT.'"),
  owlin("There's a section here marked EARLY SORROW. I'd advise everyone not to look at it."),
}

S.sn_export_room = {
  t("A cold room with iron rings in the wall at the height of a wrist. A manifest hangs on a nail. CONSIGNED BELOW: SIXTY, SOUND, UNTRUSTED. RECEIVED IN TRADE: ONE CRATE, NOT TO BE OPENED."),
  owlin("The countersign has been pressed into the paper from inside. Those who made it live under a salt sea, a very long way down, and I should like not to finish this sentence."),
  cleric("The threads go through this floor."),
  deserter("So that's what the second no is for. Nothing here is wasted. I keep saying that as though it's a comfort."),
}

S.sn_talk_tam_rack = {
  tam("Please. He's got a list. Don't go away."),
}

S.sn_scene_cellar = {
  t("At the end of the aisle a thin old man in a leather apron is holding a small glass up to a candle. Behind him, on a stool, in a clean white shift, with a label tied to her wrist, sits Tam."),
  cellarmaster("Good evening. You'll forgive the apron. One moment."),
  cellarmaster("Doctor: juniper, lamp oil, and a long finish of regret. Sister: cold water and iron, superb with game. Scholar: ink, feathers, and is that Agoshull, before the fall? I could weep."),
  t("He turns to you, and breathes in, and stops. It's the first time you've seen anyone in this country stop smiling."),
  cellarmaster("No. That isn't anything. That's a corked bottle with no wine in it. Who let that into my cellar?"),
  tam("You came! I said it twice! Tell him I said it twice!"),
  cellarmaster("A very young vintage, asked twice, that declined. She's laid down for consignment. One doesn't take a bottle from the cellar. One asks."),
  ask(cellarmaster("Is there something I can get you?"), {
    { "Give her to us.", {
      cellarmaster("Then I have the honour to decline, as the young lady did. Do you know, it's rather bracing."),
    } },
    { "Step away from her.", {
      cellarmaster("How direct. You're going to have a very short finish."),
    } },
  }),
  { battle = "sn_boss_cellarmaster" },
  t("The glass goes first. Then the apron is lying on the brick with a good deal of grey dust in it, and a small silver spoon on a chain."),
  { set = "sn_cellar_down" },
  t("Tam can't get the knot on her wrist undone. The sister cuts it for her, and neither of them says anything."),
  tam("Is it over? Have you eaten? Sorry. Sorry, it just comes out."),
  t("There are others on stools further down the aisle, forty or fifty, in white, with labels. They've already been seen to. You ask them to get up, and they get up. You ask them to come with you."),
  person("sn_labelled", "THE LABELLED")("It is a lovely day."),
  t("They sit back down."),
  cleric("Come away, {hero}. There's a live one with us. Come away."),
  { set = "sn_tam_found" },
  { fade = true },
  warp("sn_citadel", "g", 3),
}

-- ---------------------------------------------------------------- taking your leave

local TAKE_LEAVE = {
  t("He's waiting at the foot of the gallery with a lamp and a blanket over his arm. He's alone. There are no guards. There never were."),
  sindal("There she is. You'll be cold, child."),
  t("He tucks the blanket in at her neck, and his thumb rests for a moment under her ear."),
  sindal("You've killed my Cellarmaster. I'll have a new one by Thursday."),
  { when = "sn_barnabas_given", steps = {
    t("Behind him a huge man in a grey smock is sweeping the marble. There's a gap in his teeth. He looks up at you, and it's the same smile."),
    sindal("Four hundred years of plotting, and he's marvellous with a broom. I shall send him home to do his own hall. Thank you for him."),
    { set = "sn_barnabas_swept" },
  }, other = {
    { when = "sn_barnabas_dead", steps = {
      sindal("And poor Barnabas! I've been meaning to replace him for years. You wouldn't care for Upriftin, I suppose? It has wonderful berries."),
    }, other = {
      { when = "sn_coup_backed", steps = {
        sindal("There was a little unpleasantness in the north. Three hundred young men came up through the culverts. They were met. It's all been swept up."),
        t("The doctor, who counts everything, doesn't look at you for the rest of the night."),
        { set = "sn_cells_empty" },
      }, other = {
        { when = "sn_poured", steps = {
          sindal("Do tell Barnabas the cloves were better this time."),
        } },
      } },
    } },
  } },
  ask(sindal("Did you want the child? Keep her. A gift. There's no need to look at me like that."), {
    { "Why are you letting us go?", {
      sindal("My dears, what would I stop you with? Tomorrow there'll be a Giving in every chapel, and melon after it, and they'll all say thank you. You may tell anyone you like. They know."),
    } },
    { "We'll be back for the rest.", {
      sindal("I do hope so. I've so enjoyed it."),
    } },
  }),
  t("He lifts the lamp a little, to light you to the door. Then he says it, quite gently, for the first time. You'd thought he might not."),
  sindal("Have you eaten?"),
  { fade = true },
  warp("sn_syndalia", "i", 1),
  t("Morning in Syndalia. The sister stands in front of the great wheel for a long time, and you wait."),
  cleric("I could stay. Nobody would hang me. I could say the office out loud every day until I die, and they'd bring me melon."),
  cleric("Twenty years I wanted that. He knew, {hero}. They all know. That's how this country works. It finds the thing you'd pay anything for, and it hands it to you for nothing."),
  ask(cleric("I need to hear someone say it. Why can't I stay?"), {
    { "Because of the ones under the floor.", {
      cleric("Yes. Thank you. I knew. I just needed it said out loud. It's that sort of place."),
    } },
    { "You can. I won't stop you.", {
      cleric("No. You wouldn't, would you? That's the cruellest thing anyone has said to me in this whole country, and I've been so kindly treated."),
      { set = "sn_let_her_choose" },
    } },
  }),
  t("She says the office once more, very quietly, into her sleeve, the old way. Then she picks up her bag."),
  t("Tam's mother waves from the door of the Full Table, smiling. Tam waves back, with the wrong side of her mouth, and doesn't let go of the doctor's coat."),
  deserter("Antarith first. There's a lady there who takes anyone."),
  { when = "px_done", steps = {
    owlin("Two tokens. One given in fear, one given for nothing at all. I know which frightens me more. The windmill, I think."),
  }, other = {
    owlin("One token. Plexios has the other, and I shall be glad of a little open hostility."),
  } },
  { dark = true },
  t("Far to the east, in Adaphis, a high room. One lamp."),
  t("A woman in a physician's grey reads a single sheet with one figure on it. She lays it in an old book, at the place where the pages have been torn out."),
  t('"Enough," says Doctor Colette, to no one. She does not sound glad.'),
  { dark = false },
  { set = "sn_done" },
  { save = true },
}

S.sn_leave_citadel = {
  { when = "sn_tam_found", steps = {
    { when = "sn_done", steps = { { world = { 36, 28 } } }, other = TAKE_LEAVE },
  }, other = {
    { world = { 36, 28 } },
  } },
}

return R
