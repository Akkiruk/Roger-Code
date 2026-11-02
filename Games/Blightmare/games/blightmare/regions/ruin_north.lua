-- regions/ruin_north.lua: the fallen north. Adaphis under the Ribs, Sindal eaten, the thralls awake, and the Hollow One.
-- Plain data and local helpers only. Draft for the author to edit: story.lua's header says how a script is put together.
--
-- The way through: Adaphis first, for the news; Antarith, where Asphodel holds what's left; the cold line at Upriftin and the sea
-- line at Eighstead, in either order, which starve Tyamet; back to Antarith, where Asphodel shuts her own line and joins; then
-- Syndalia, Undella on the step, the Spear, the Veins and the Hollow. The Cranial is the side quest, by the Gutter, from Harrow.
--
-- Who's here. The hero, the doctor and the scholar always. The sister and Jezzara only when rd_done: every line of theirs is
-- behind that flag. The ruined world shows who made it: what's read from the earlier regions is in R.exports.
--
-- Maps are drawn with their people on them, as in sindal.lua: a lower-case letter or a digit is floor, a capital is stairs, h, L
-- and W keep their meaning, and place() finds each thing's at in the rows. Every id on a map is also that person's look.

local say = require("games.blightmare.say")
local t, ask, topic, person, line = say.t, say.ask, say.topic, say.person, say.line

local R = {
  id = "ruin_north", prefix = "rn_",
  entry = { flags = { "ruined", "rs_done" }, join = { "deserter", "owlin" }, lvl = 34, site = "adaphis_r" },
  exit = "rn_done",
  -- flags read here from the earlier regions, so the north answers for what was done there
  exports = {
    "px_gave_blood", "sn_coup_backed", "sn_barnabas_dead", "sn_barnabas_given", "sn_vales_out", "sn_told_hesper", "sn_lied_hesper",
    "sn_lira_chapter", "sn_let_her_choose", "sn_prayed", "wm_lucilda_dead", "wm_took",
  },
  sites = {},
  maps = {}, scripts = {}, shops = {}, goals = {},
  foes = {}, abilities = {}, encounters = {}, field = {},
  looks = {}, names = {}, art = {}, items = {},
}

local S = R.scripts

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
    for _, one in ipairs(def[kind] or {}) do
      local spot = spots[one.at]
      if not spot then error(id .. " has no mark " .. tostring(one.at)) end
      one.x, one.y, one.at = spot[1], spot[2], nil
    end
  end
  SPOTS[id] = spots
  R.maps[id] = def
end

--- A person standing on a mark. Their look has the same id.
local function who(id, at, script, extra)
  local npc = extra or {}
  npc.id, npc.at, npc.script = id, at, script
  npc.sprite = npc.sprite or "villager"
  return npc
end

--- A foe on a mark, with an encounter and a sprite. unless: a flag that means it was never here.
local function foe(id, at, enc, sprite, unless)
  return { id = id, at = at, enc = enc, sprite = sprite, unless = unless }
end

--- A trigger on a mark that stops once its own flag is set.
local function trigger(at, script, when, unless) return { at = at, script = script, when = when, unless = unless } end

--- Stairs to a mark on a map, read once all the maps are placed.
local function stairs(at, id, mark, dir) return { at = at, to = id, land = mark, dir = dir } end

--- A warp to a mark on a map that's already been placed.
local function warp(id, mark, dir) return { warp = { id, SPOTS[id][mark][1], SPOTS[id][mark][2], dir } } end

--- A goal at a mark on a map.
local function goal(done, text, id, mark, when)
  local spot = SPOTS[id][mark]
  return { done = done, text = text, map = id, x = spot[1], y = spot[2], when = when }
end

--- A site on its old tile, arriving on a mark.
local function site(id, x, y, map, mark, name, dir)
  local spot = SPOTS[map][mark]
  R.sites[id] = { x = x, y = y, map = map, mx = spot[1], my = spot[2], dir = dir or 1, name = name, when = "rs_done" }
end

--- A thing on a draped table, drawn with what a person would carry.
local function thing(carry)
  return { kind = "human", pose = "lying", bed = true, empty = true, carry = carry, carryX = 0.5 }
end

-- ---------------------------------------------------------------- Adaphis, the Ribs

place("rn_ribs", {
  name = "ADAPHIS: THE RIBS", theme = "city", savepoint = true,
  rows = {
    "#############################",
    "#hhhhhhhhhhhhhhhhhhhhhhhhhhh#",
    "#.r.........................#",
    "#hhhhh+hhhhhhh.hhhhhhh+hhhhh#",
    "#h..t.......1h.h.......m...h#",
    "#h...........h.h...........h#",
    "#hhhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#..c........................#",
    "#hhhhh+hhhhhhh.hhhhhhh+hhhhh#",
    "#h..b........h.h...........h#",
    "#h.......2...h.h..o....l...h#",
    "#hhhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#.............k.............#",
    "#hhhhhhhhhhhh...hhhhhhhhhhhh#",
    "#hhhhhhhhhhhGgs.hhhhhhhhhhhh#",
    "##############E##############",
  },
  npcs = {
    who("rn_harrow", "b", "rn_talk_harrow", { when = "rs_done" }),
    who("rn_tom", "t", "rn_talk_tom"),
    who("rn_maud", "m", "rn_talk_maud"),
    who("rn_osric", "o", "rn_talk_osric", { when = "rs_done" }),
    who("rn_loveday", "l", "rn_talk_loveday", { when = "rs_done" }),
    who("rn_cray", "c", "rn_talk_cray", { when = "rs_done" }),
    who("rn_refugee", "r", "rn_talk_refugee"),
    who("rn_fenn", "g", "rn_talk_fenn", { unless = "rn_job" }),
  },
  steps = {
    trigger("s", "rn_shut_ribs", nil, "rs_done"),
    trigger("s", "rn_ribs_in", "rs_done", "rn_ribs_in"),
  },
  chests = {
    { id = "c1", at = "1", give = "xpotion", n = 2 },
    { id = "c2", at = "2", gold = 1500 },
  },
  exits = {
    { at = "E", world = { 104, 28 } },
    stairs("G", "rn_gutter", "u", 2),
  },
})

-- ---------------------------------------------------------------- the Gutter, and Bram's shaft

place("rn_gutter", {
  name = "THE SPINE DRAIN", theme = "swamp",
  rows = {
    "############################",
    "#U.u......#.......#........#",
    "####.#####.........#.1.....#",
    "####.....p.........+.....w.#",
    "########.#...~~~...#.......#",
    "#......#.#...~~~...#########",
    "#..2...+.#...~~~..a#########",
    "#......#.#.........#########",
    "########.#########.#########",
    "########.....q..........gkT#",
    "###########.################",
    "#..............#############",
    "#..3.....n.....#############",
    "#.......b....r.#############",
    "############################",
  },
  npcs = {
    who("rn_gut_wheel", "w", "rn_t_gut_wheel"),
    who("rn_gut_grate", "g", "rn_t_gut_grate", { unless = "rn_sluice" }),
    who("rn_harbottle", "n", "rn_t_harbottle"),
  },
  steps = {
    { at = "u", script = "rn_gut_in", when = "rn_job", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "ash_vestment" },
    { id = "c2", at = "2", give = "panacea", n = 2 },
    { id = "c3", at = "3", give = "wraith_edge" },
  },
  foes = {
    foe("f1", "p", "rn_e_gut1", "leech"),
    foe("f2", "a", "rn_e_gut2", "leech"),
    foe("f3", "q", "rn_e_gut1", "leech"),
    foe("f4", "r", "rn_e_gut2", "rn_sleepless"),
  },
  exits = {
    stairs("U", "rn_ribs", "s", 3),
    stairs("T", "rn_cranial", "u", 1),
  },
})

-- ---------------------------------------------------------------- the Cranial

place("rn_cranial", {
  name = "ADAPHIS: THE CRANIAL", theme = "marble",
  rows = {
    "###########################",
    "#hhhhhhhhhhhhhhhhhhhhhhhhh#",
    "#h..a..h...k.....h.......h#",
    "#h.....h...l.m...h...b.y.h#",
    "#h.....h.........h.....v.h#",
    "#h.....h.........h...z...h#",
    "#hhh+hhhhhhhh+hhhhhhh+hhhh#",
    "#....................o....#",
    "#.......t............e....#",
    "#...hhhh...........hhhh...#",
    "#...h1.h...........h2.h...#",
    "#...h+hh...........hh+h...#",
    "#.....f.........j.........#",
    "#.x.u.....................#",
    "#hhUhhhhhhhhhhhhhhhhhhhhhh#",
    "#hhhhhhhhhhhhhhhhhhhhhhhhh#",
    "###########################",
  },
  npcs = {
    who("rn_hale", "a", "rn_talk_hale"),
    who("rn_henman", "l", "rn_talk_henman"),
    who("rn_bram", "x", "rn_talk_bram"),
    who("rn_porter", "o", "rn_talk_porter", { unless = "rn_porter_ok" }),
    who("rn_bed", "b", "rn_t_bed"),
    who("rn_prynne", "y", "rn_scene_prynne", { unless = "rn_prynne_down" }),
    who("rn_valve", "v", "rn_scene_valve", { unless = "side_revolution" }),
  },
  steps = {
    trigger("u", "rn_cr_in", nil, "rn_cr_in"),
    trigger("z", "rn_scene_prynne", nil, "rn_prynne_down"),
  },
  chests = {
    { id = "c1", at = "1", give = "mind_ward" },
    { id = "c2", at = "2", give = "grave_rod" },
  },
  foes = {
    foe("f1", "f", "rn_e_rounds", "rn_sleepless"),
    foe("f2", "j", "rn_e_rounds2", "orderly"),
    foe("f3", "e", "rn_e_rounds", "rn_sleepless"),
  },
  exits = {
    stairs("U", "rn_gutter", "k", 4),
  },
})

-- ---------------------------------------------------------------- the small towns of Shaid

place("rn_blackpool", {
  name = "BLACKPOOL", theme = "town",
  rows = {
    "#####################",
    "#...................#",
    "#..hhhh.......hhhh..#",
    "#..h1.h...n...h2.h..#",
    "#..h..h.......h..h..#",
    "#..hh+h.......h+hh..#",
    "#...................#",
    "#.......~~~~~.......#",
    "#.......~~~~~.......#",
    "#...o...~~~~~...p...#",
    "#...................#",
    "#hhhhhhhh...hhhhhhhh#",
    "#hhhhhhhh.s.hhhhhhhh#",
    "#hhhhhhhhh.hhhhhhhhh#",
    "##########E##########",
  },
  npcs = {
    who("rn_nell", "n", "rn_talk_nell"),
    who("rn_holt", "o", "rn_talk_holt"),
  },
  chests = {
    { id = "c1", at = "1", give = "hiether", n = 2 },
    { id = "c2", at = "2", gold = 900 },
  },
  foes = { foe("f1", "p", "rn_e_field2", "blighted") },
  exits = { { at = "E", world = { 97, 39 } } },
})

place("rn_killerth", {
  name = "KILLERTH", theme = "town",
  rows = {
    "#####################",
    "#h.................h#",
    "#h..hhhh.....hhhh..h#",
    "#h..h.1h..k..h2.h..h#",
    "#h..h..h.....h..h..h#",
    "#h..hh+h.....h+hh..h#",
    "#h.................h#",
    "#h.......b.........h#",
    "#h.................h#",
    "#hhhh.........hhhhhh#",
    "#hhhh.........hhhhhh#",
    "#hhhhhhhh...hhhhhhhh#",
    "#hhhhhhhh.s.hhhhhhhh#",
    "#hhhhhhhhh.hhhhhhhhh#",
    "##########E##########",
  },
  npcs = {
    who("rn_kest", "k", "rn_talk_kest"),
  },
  chests = {
    { id = "c1", at = "1", give = "feather", n = 2 },
    { id = "c2", at = "2", give = "life_ring" },
  },
  exits = { { at = "E", world = { 86, 26 } } },
})

place("rn_murkwell", {
  name = "MURKWELL", theme = "ruin",
  rows = {
    "#####################",
    "#~~~~~~~~~~~~~~~~~~~#",
    "#~~.....~~~~~.....~~#",
    "#~~..1...p.......~~~#",
    "#~~.......n.......~~#",
    "#~~~.............~~~#",
    "#~~~~...c.....2.~~~~#",
    "#~~~~...........~~~~#",
    "#~~~~~~.......~~~~~~#",
    "#~~~~~~.......~~~~~~#",
    "#~~~~~~.......~~~~~~#",
    "#hhhhhhhh...hhhhhhhh#",
    "#hhhhhhhh.s.hhhhhhhh#",
    "#hhhhhhhhh.hhhhhhhhh#",
    "##########E##########",
  },
  npcs = {
    who("rn_pell", "n", "rn_talk_pell"),
  },
  chests = {
    { id = "c1", at = "1", give = "xpotion", n = 2 },
    { id = "c2", at = "2", give = "shade_coat" },
  },
  foes = { foe("f1", "p", "rn_e_field3", "thrall") },
  exits = { { at = "E", world = { 72, 30 } } },
})

-- ---------------------------------------------------------------- over the mountains

place("rn_crevice", {
  name = "THE CAVITY CREVICE", theme = "cave",
  rows = {
    "#######################",
    "#.....#~~~~~~~~~#.....#",
    "#..1..#~~~~~~~~~#..b..#",
    "#.....#~~~~~~~~~#.....#",
    "###.###~~~~~~~~~###.###",
    "###.###~~~~~~~~~###.###",
    "#G....p...........q.sE#",
    "###.###~~~~~~~~~###.###",
    "###.###~~~~~~~~~###.###",
    "#.....#~~~~~~~~~#.....#",
    "#..2..#~~~~~~~~~#..d..#",
    "#.....#~~~~~~~~~#.....#",
    "#######################",
    "#######################",
    "#######################",
  },
  npcs = {
    who("rn_drum", "b", "rn_talk_drum"),
    who("rn_post_grave", "d", "rn_t_post_grave"),
  },
  chests = {
    { id = "c1", at = "1", give = "hipotion", n = 3 },
    { id = "c2", at = "2", give = "night_kris" },
  },
  foes = {
    foe("f1", "p", "rn_e_field1", "bat"),
    foe("f2", "q", "rn_e_field2", "blighted"),
  },
  exits = {
    { at = "E", world = { 52, 33 } },
    { at = "G", world = { 52, 33 } },
  },
})

place("rn_thuluan", {
  name = "THULUAN", theme = "swamp",
  rows = {
    "#######################",
    "#~~~~~~~~~~~~~~~~~~~~~#",
    "#~~~.....~~~~~.....~~~#",
    "#~~...r.........t...~~#",
    "#~~.................~~#",
    "#~~~...b.......1...~~~#",
    "#~~~~...........~~~~~~#",
    "#~~~~~~...s...~~~~~~~~#",
    "#~~~~~~~~~E~~~~~~~~~~~#",
    "#######################",
    "#######################",
    "#######################",
    "#######################",
    "#######################",
    "#######################",
  },
  npcs = {
    who("rn_rime", "r", "rn_talk_rime"),
    who("rn_sedge", "t", "rn_talk_sedge"),
  },
  chests = {
    { id = "c1", at = "1", give = "raven_charm" },
  },
  exits = { { at = "E", world = { 45, 8 } } },
})

-- ---------------------------------------------------------------- Antarith

place("rn_antarith", {
  name = "ANTARITH", theme = "town", savepoint = true,
  rows = {
    "#############################",
    "#hhhhhhhhhhhhhhhhhhhhhhhhhhh#",
    "#h.................h.......h#",
    "#h..l...d.....w....h...a...h#",
    "#h.........t.......+.......h#",
    "#h.......r...g.....h...v...h#",
    "#hhhhhhhh+hhhhhhhhhhhhhhhhhh#",
    "#........k..................#",
    "#..........................c#",
    "#hhhhh+hhhhhhh.hhhhhhh+hhhhh#",
    "#h...i.......h.h.....n.....h#",
    "#h..........1h.h..2........h#",
    "#hhhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#.......p.............b.....#",
    "#hhhhhhhhhhhh...hhhhhhhhhhhh#",
    "#hhhhhhhhhhhhhshhhhhhhhhhhhh#",
    "##############E##############",
  },
  npcs = {
    who("rn_asphodel", "a", "rn_talk_asphodel", { when = "rs_done", unless = "rn_asphodel_in" }),
    who("rn_tam", "t", "rn_talk_tam", { when = "rs_done" }),
    who("rn_thrax", "w", "rn_talk_thrax", { when = "rs_done" }),
    who("rn_lira", "l", "rn_talk_lira", { when = "rs_done" }),
    who("rn_davin", "d", "rn_talk_davin", { when = "rs_done" }),
    who("rn_grub", "g", "rn_talk_grub", { when = "rs_done" }),
    who("rn_vesh", "i", "rn_talk_vesh"),
    who("rn_corin", "c", "rn_talk_corin", { when = "rs_done" }),
    who("rn_maren", "b", "rn_talk_maren", { when = "rs_done" }),
    who("rn_wall_boy", "p", "rn_talk_wall_boy", { when = "side_barnabas" }),
    who("rn_devils_wheel", "v", "rn_t_devils_wheel"),
  },
  steps = {
    trigger("s", "rn_shut_antarith", nil, "rs_done"),
    trigger("s", "rn_ant_in", "rs_done", "rn_ant_in"),
    { at = "r", script = "rn_scene_house", when = "rs_done", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "ruin_plate" },
    { id = "c2", at = "2", give = "tent", n = 2 },
  },
  exits = { { at = "E", world = { 20, 38 } } },
})

-- ---------------------------------------------------------------- Upriftin, and the icehouse

place("rn_upriftin", {
  name = "UPRIFTIN", theme = "town", savepoint = true,
  rows = {
    "#########################",
    "#hhhhhhhhhhhhhhhhhhhhhhh#",
    "#h.....h.......h.......h#",
    "#h..b..h...t...h...k...h#",
    "#h.....h.......h.......h#",
    "#hh+hhhhhhh+hhhhhhh+hhhh#",
    "#.......................#",
    "#....n.............r....#",
    "#hhhhhhh.hhhh.hhhhhhhhhh#",
    "#hhhhhhh.hhhh.hhhhhhhhhh#",
    "#hhhhhhh.hhhh.hhhhhhhhhh#",
    "#hhhhhhhIhhhhshhhhhhhhhh#",
    "#############E###########",
    "#########################",
    "#########################",
  },
  npcs = {
    who("rn_barnabas_broom", "b", "rn_talk_broom", { when = "sn_barnabas_given" }),
    who("rn_barnabas_lord", "b", "rn_talk_lord", { unless = "side_barnabas" }),
    who("rn_tooth", "b", "rn_t_tooth", { when = "sn_barnabas_dead" }),
    who("rn_bress", "t", "rn_talk_bress"),
    who("rn_hesper", "k", "rn_talk_hesper", { when = "rs_done" }),
    who("rn_nettle", "n", "rn_talk_nettle"),
  },
  steps = {
    trigger("s", "rn_shut_upriftin", nil, "rs_done"),
    trigger("s", "rn_up_in", "rs_done", "rn_up_in"),
  },
  foes = { foe("f1", "r", "rn_e_reserve", "sn_bloodshot", "side_barnabas") },
  exits = {
    { at = "E", world = { 30, 24 } },
    stairs("I", "rn_icehouse", "u", 2),
  },
})

place("rn_icehouse", {
  name = "THE OLD ICEHOUSE", theme = "cave",
  rows = {
    "###########################",
    "#U.u....#.....#.....#.....#",
    "####.####.....#.....#..w..#",
    "####.####..1..#..2..#.....#",
    "####.####.....#.....#.....#",
    "####.#####.#####.#####.####",
    "#.......................###",
    "#...p.......q.......r...###",
    "###########.###############",
    "#########.....#############",
    "#########..n..#############",
    "#########..3..#############",
    "#########.....#############",
    "###########################",
    "###########################",
  },
  npcs = {
    who("rn_cold_man", "w", "rn_scene_cold"),
    who("rn_cell_note", "n", "rn_t_cell_note"),
  },
  chests = {
    { id = "c1", at = "1", give = "xpotion", n = 2 },
    { id = "c2", at = "2", give = "hiether", n = 2 },
    { id = "c3", at = "3", give = "might_ring" },
  },
  foes = {
    foe("f1", "p", "rn_e_cold1", "sn_keeper"),
    foe("f2", "q", "rn_e_cold2", "sn_bloodshot", "side_barnabas"),
    foe("f3", "r", "rn_e_cold1", "sn_keeper"),
  },
  exits = {
    stairs("U", "rn_upriftin", "s", 3),
  },
})

-- ---------------------------------------------------------------- Eighstead, and the sea line

place("rn_eighstead", {
  name = "EIGHSTEAD", theme = "town", savepoint = true,
  rows = {
    "#########################",
    "#hhhhhhhhhhhhhhhhhhhhhhh#",
    "#h.....h.......h.......h#",
    "#h..c..h...o...h...b...h#",
    "#h.....h.......h.......h#",
    "#hh+hhhhhhh+hhhhhhh+hhhh#",
    "#.......................#",
    "#....t.............r....#",
    "#hhhhhhhh.hhhh.hhhhhhhhh#",
    "#hhhhhhhh.hhhh.hhhhhhhhh#",
    "#hhhhhhhh.hhhh.hhhhhhhhh#",
    "#hhhhhhhhDhhhhshhhhhhhhh#",
    "##############E##########",
    "#########################",
    "#########################",
  },
  npcs = {
    who("rn_ceiridwen", "c", "rn_talk_ceiridwen", { when = "rs_done" }),
    who("rn_tallow", "t", "rn_talk_tallow"),
  },
  steps = {
    trigger("s", "rn_shut_eighstead", nil, "rs_done"),
    trigger("s", "rn_ei_in", "rs_done", "rn_ei_in"),
  },
  exits = {
    { at = "E", world = { 11, 31 } },
    stairs("D", "rn_seaworks", "u", 1),
  },
})

place("rn_seaworks", {
  name = "THE SEA LINE", theme = "coral",
  rows = {
    "###########################",
    "#~~~~~~~~~#.....#~~~~~~~~~#",
    "#~~.....~~#..2..#~~.....~~#",
    "#~~..1..~~#.....#~~..w..~~#",
    "#~~.....~~###.###~~.....~~#",
    "#~~~~.~~~~###.###~~~~.~~~~#",
    "#####....p.......q....#####",
    "#############.#############",
    "#############.#############",
    "#############u#############",
    "#############U#############",
    "###########################",
    "###########################",
    "###########################",
    "###########################",
  },
  npcs = {
    who("rn_sea_woman", "w", "rn_scene_sea"),
  },
  chests = {
    { id = "c1", at = "1", give = "raven_vest" },
    { id = "c2", at = "2", give = "xpotion", n = 2 },
  },
  foes = {
    foe("f1", "p", "rn_e_sea1", "rn_crab"),
    foe("f2", "q", "rn_e_sea2", "rn_crab"),
  },
  exits = {
    stairs("U", "rn_eighstead", "s", 3),
  },
})

-- ---------------------------------------------------------------- Syndalia, and the Spear

place("rn_syndalia", {
  name = "SYNDALIA", theme = "city", savepoint = true,
  rows = {
    "##############Z##############",
    "#hhhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#hhhhhhhhhhhhhuhhhhhhhhhhhhh#",
    "#....f.................o....#",
    "#hhhhh+hhhhhhh.hhhhhhh+hhhhh#",
    "#h...a.......h.h.....m.....h#",
    "#h..........1h.h...........h#",
    "#hhhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#......p....................#",
    "#hhhhh+hhhhhhh.hhhhhhh+hhhhh#",
    "#h...c.......h.h.....l.....h#",
    "#h...........h.h..2........h#",
    "#hhhhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#...........................#",
    "#hhhhhhhhhhhh...hhhhhhhhhhhh#",
    "#hhhhhhhhhhhhhshhhhhhhhhhhhh#",
    "##############E##############",
  },
  npcs = {
    who("rn_undella", "u", "rn_talk_undella", { when = "rs_done", unless = "rn_spear_open" }),
    who("rn_fenwick", "f", "rn_talk_fenwick"),
    who("rn_perrin", "o", "rn_talk_perrin", { when = "rs_done" }),
    who("rn_anwen", "a", "rn_talk_anwen", { when = "rs_done" }),
    who("rn_dulcie", "m", "rn_talk_dulcie"),
    who("rn_amareth", "c", "rn_talk_amareth"),
    who("rn_oswin", "l", "rn_talk_oswin"),
  },
  steps = {
    trigger("s", "rn_shut_syndalia", nil, "rs_done"),
    trigger("s", "rn_syn_in", "rs_done", "rn_syn_in"),
  },
  chests = {
    { id = "c1", at = "1", give = "grief_knife" },
    { id = "c2", at = "2", give = "panacea", n = 2 },
  },
  foes = { foe("f1", "p", "rn_e_field1", "vampire_knight") },
  exits = {
    { at = "E", world = { 36, 28 } },
    stairs("Z", "rn_spear", "u", 4),
  },
})

place("rn_spear", {
  name = "THE SPEAR CITADEL", theme = "marble",
  rows = {
    "###########################",
    "#h.....h.........h.......h#",
    "#h..1..h..d......h...2...h#",
    "#h.....h.........h.......h#",
    "#hhh+hhhhhhh+hhhhhhh+hhhhh#",
    "#.........................#",
    "#....p...........q.......uU",
    "#hhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#hhhhhhhhhhh.hhhhhhhhhhhhh#",
    "#...........r.............#",
    "#hh+hhhhhhhhhhhhhhhhhhh+hh#",
    "#h.......hhhhhhhhhhhhh...h#",
    "#h...m...hhhhhhhhhhhhheD.h#",
    "#h.......hhhhhhhhhhhhhhhhh#",
    "#hhhhhhhhhhhhhhhhhhhhhhhhh#",
    "###########################",
  },
  npcs = {
    who("rn_table", "d", "rn_t_table"),
    who("rn_manifest", "m", "rn_t_manifest"),
  },
  chests = {
    { id = "c1", at = "1", give = "archon_crown" },
    { id = "c2", at = "2", give = "elixir" },
  },
  foes = {
    foe("f1", "p", "rn_e_spear1", "vampire_knight"),
    foe("f2", "q", "rn_e_spear2", "thrall"),
    foe("f3", "r", "rn_e_spear1", "vampire_knight"),
  },
  exits = {
    stairs("U", "rn_syndalia", "u", 3),
    stairs("D", "rn_veins", "u", 3),
  },
})

place("rn_veins", {
  name = "THE VEINS", theme = "chain",
  rows = {
    "#############################",
    "#U.u.....#....x....#....y...#",
    "####.....#..1...a..#..2.....#",
    "####.....+.........+........#",
    "####.....#.........#.....b..#",
    "####.#####.........#####.####",
    "####.#####~~~~~~~~~#####.####",
    "####.#####~~~~~~~~~#####.####",
    "####.#####~~~~~~~~~#####.####",
    "####.....p...........q...####",
    "############.################",
    "############g################",
    "############.################",
    "#########.......#############",
    "#########t..k...#############",
    "############D################",
    "#############################",
  },
  npcs = {
    who("rn_wheel_a", "x", "rn_t_wheel_a"),
    who("rn_wheel_b", "y", "rn_t_wheel_b"),
    who("rn_plaque", "b", "rn_t_plaque"),
    who("rn_sump", "g", "rn_scene_giving", { unless = "rn_giving_down" }),
    who("rn_stools", "t", "rn_t_stools"),
  },
  steps = {
    { at = "u", script = "rn_veins_in", once = true },
  },
  chests = {
    { id = "c1", at = "1", give = "xpotion", n = 3 },
    { id = "c2", at = "2", give = "hiether", n = 3 },
  },
  foes = {
    foe("f1", "a", "rn_e_veins1", "rn_clot"),
    foe("f2", "p", "rn_e_veins2", "thrall"),
    foe("f3", "q", "rn_e_veins1", "rn_clot"),
  },
  exits = {
    stairs("U", "rn_spear", "e", 2),
    stairs("D", "rn_hollow", "u", 3),
  },
})

place("rn_hollow", {
  name = "THE HOLLOW", theme = "ash",
  rows = {
    "#########################",
    "###########U#############",
    "###########u#############",
    "###########.#############",
    "########.......##########",
    "#####.1...p.....#########",
    "#####.......2...#########",
    "#######.......###########",
    "#########.q.#############",
    "##########.##############",
    "##########z##############",
    "#####.............#######",
    "#####.............#######",
    "#####....~~~~~....#######",
    "#####~~~~~~~~~~~~~#######",
    "#########################",
  },
  steps = {
    trigger("z", "rn_scene_tyamet", nil, "rn_done"),
  },
  chests = {
    { id = "c1", at = "1", give = "elixir" },
    { id = "c2", at = "2", give = "dragon_heart" },
  },
  foes = {
    foe("f1", "p", "rn_e_hollow1", "rn_hollowling"),
    foe("f2", "q", "rn_e_hollow2", "rn_hollowling"),
  },
  exits = {
    stairs("U", "rn_veins", "k", 1),
  },
})

for _, def in pairs(R.maps) do
  for _, exit in ipairs(def.exits or {}) do
    if exit.to then
      local spot = SPOTS[exit.to][exit.land]
      exit.map, exit.mx, exit.my = exit.to, spot[1], spot[2]
      exit.to, exit.land = nil, nil
    end
  end
end

site("blackpool_r", 97, 39, "rn_blackpool", "s", "BLACKPOOL")
site("killerth_r", 86, 26, "rn_killerth", "s", "KILLERTH")
site("murkwell_r", 72, 30, "rn_murkwell", "s", "MURKWELL")
site("adaphis_r", 104, 28, "rn_ribs", "s", "ADAPHIS")
site("crevice_r", 52, 33, "rn_crevice", "s", "CAVITY CREVICE", 4)
site("syndalia_r", 36, 28, "rn_syndalia", "s", "SYNDALIA")
site("upriftin_r", 30, 24, "rn_upriftin", "s", "UPRIFTIN")
site("eighstead_r", 11, 31, "rn_eighstead", "s", "EIGHSTEAD")
site("antarith_r", 20, 38, "rn_antarith", "s", "ANTARITH")
site("thuluan_r", 45, 8, "rn_thuluan", "s", "THULUAN")

-- ---------------------------------------------------------------- looks

local L = R.looks

L.rn_harrow = { like = "px_harrow", tall = 0.93, eyes = "tired", wear = { "apron", "badge" } }
L.rn_tom = { like = "px_tom" }
L.rn_maud = { like = "px_canteen" }
L.rn_osric = { like = "px_osric", carry = "book" }
L.rn_loveday = { like = "px_loveday", eyes = "tired", mouth = "line" }
L.rn_cray = { like = "px_cray" }
L.rn_fenn = { like = "px_fenn" }
L.rn_refugee = { kind = "half-elf", tall = 0.88, build = "thin", cut = "rags", coat = "line", trim = "tie", skin = "text", hair = "long", hairInk = "tie", eyes = "tired", mouth = "smile", wear = { "shawl" }, shawlInk = "tie", oneShoe = true, back = "panel" }
L.rn_hale = { like = "px_hale" }
L.rn_henman = { like = "px_henman" }
L.rn_bram = { like = "px_bram" }
L.rn_porter = { like = "px_porter", eyes = "red" }
L.rn_prynne = { kind = "clinic", tall = 0.96, build = "gaunt", cut = "coat", coat = "line", trim = "text", legs = "tie", skin = "text", hair = "short", hairInk = "tie", eyes = "red", mouth = "line", carry = "clipboard", beak = 0.03, back = "redTint" }
L.rn_nell = { like = "px_nell", eyes = "tired" }
L.rn_holt = { like = "px_holt" }
L.rn_kest = { like = "px_kest", eyes = "narrow" }
L.rn_pell = { like = "px_pell", carry = "scalpel" }
L.rn_drum = { like = "sn_drum_n", eyes = "wide", mouth = "smile" }
L.rn_rime = { like = "wm_rime" }
L.rn_sedge = { like = "wm_sedge" }
L.rn_asphodel = { like = "asphodel", build = "gaunt", eyes = "tired", mouth = "line", carry = "list" }
L.rn_tam = { like = "sn_tam_safe", tall = 0.66, carry = "bowl" }
L.rn_thrax = { like = "sn_thrax", eyes = "tired", mouth = "line" }
L.rn_lira = { like = "sn_lira_after", eyes = "specs", carry = "book" }
L.rn_davin = { kind = "human", tall = 0.92, build = "thin", cut = "tunic", coat = "line", trim = "text", legs = "tie", skin = "text", hair = "short", hairInk = "tie", eyes = "wide", mouth = "smile", back = "panel" }
L.rn_grub = { like = "sn_grub" }
L.rn_vesh = { like = "sn_hostess" }
L.rn_corin = { like = "sn_corin", eyes = "tired" }
L.rn_maren = { like = "sn_maren" }
L.rn_wall_boy = { like = "sn_cell_boy", carry = "spear" }
L.rn_barnabas_broom = { like = "sn_barnabas_smiling", eyes = "tired" }
L.rn_barnabas_lord = { like = "sn_barnabas", eyes = "red" }
L.rn_bress = { like = "sn_soup" }
L.rn_hesper = { like = "sn_hesper_ice" }
L.rn_nettle = { like = "sn_berry", tall = 0.56 }
L.rn_cold_man = { like = "sn_sluice_n", eyes = "closed" }
L.rn_ceiridwen = { like = "sn_ceiridwen", build = "normal", eyes = "tired", mouth = "line" }
L.rn_tallow = { like = "sn_tallow" }
L.rn_sea_woman = { kind = "human", tall = 0.88, build = "thin", cut = "dress", coat = "line", trim = "tie", skin = "text", hat = "scarf", hatInk = "tie", hatTrim = "line", wear = { "apron" }, apronInk = "blueTint", carry = "wheel", eyes = "tired", mouth = "smile", back = "blueTint" }
L.rn_undella = { like = "sn_undella", eyes = "narrow", mouth = "open" }
L.rn_fenwick = { like = "sn_fenwick", mouth = "smile" }
L.rn_perrin = { like = "sn_perrin", eyes = "narrow" }
L.rn_anwen = { like = "sn_anwen", eyes = "tired" }
L.rn_dulcie = { like = "sn_melon", eyes = "tired" }
L.rn_amareth = { like = "sn_amareth", eyes = "tired" }
L.rn_oswin = { like = "sn_oswin", eyes = "wide" }
for _, pair in ipairs({
  { "rn_gut_wheel", "wheel" }, { "rn_gut_grate", "keys" }, { "rn_harbottle", "letter" }, { "rn_bed", "pillow" }, { "rn_valve", "wheel" }, { "rn_post_grave", "stone" },
  { "rn_devils_wheel", "wheel" }, { "rn_tooth", "dagger" }, { "rn_cell_note", "letter" }, { "rn_table", "tray" },
  { "rn_manifest", "list" }, { "rn_wheel_a", "wheel" }, { "rn_wheel_b", "wheel" }, { "rn_plaque", "board" }, { "rn_sump", "wheel" }, { "rn_stools", "list" },
}) do
  L[pair[1]] = thing(pair[2])
end

R.names = {
  ["HOUSE OFFICER PRYNNE"] = "rn_prynne", DAVIN = "rn_davin", ["A WOMAN FROM THE WEST"] = "rn_refugee",
}

-- ---------------------------------------------------------------- what you fight

local A = R.abilities

A.rn_thirst = { name = "THIRST", power = 118 }
A.rn_lance = { name = "STARVED LANCE", power = 145 }
A.rn_still_asking = { name = "STILL ASKING", mp = 5, power = 72, magic = true, element = "mind" }
A.rn_round = { name = "THE ROUND", power = 122 }
A.rn_declare = { name = "NOTHING TO DECLARE", mp = 6, power = 60, magic = true, status = "nightmare", chance = 55 }
A.rn_kept_under = { name = "KEPT UNDER", mp = 6, power = 32, magic = true, target = "all", status = "sleep", chance = 50 }
A.rn_seven = { name = "SEVEN O'CLOCK", power = 195, magic = true, target = "all", windup = 34, warn = "HE TURNS DOWN THE BED" }
A.rn_ring_staff = { name = "RINGS FOR STAFF", target = "summon" }
A.rn_smother = { name = "SMOTHER", power = 128 }
A.rn_sour = { name = "GONE SOUR", power = 52, target = "all", status = "poison", chance = 60 }
A.rn_cup = { name = "A CUP A MONTH", mp = 5, power = 88, magic = true, element = "blood" }
A.rn_eaten = { name = "HAVE YOU EATEN?", power = 200, magic = true, target = "all", element = "blood", windup = 34, warn = "THE LAKE DRAWS BREATH" }
A.rn_wells_up = { name = "IT WELLS UP", target = "summon" }
A.rn_maw = { name = "BLACK MAW", power = 155 }
A.rn_black_spit = { name = "BLACK SPIT", mp = 6, power = 72, magic = true, target = "all", status = "poison", chance = 60 }
A.rn_empty = { name = "THE EMPTY", mp = 7, power = 100, magic = true, element = "blood" }
A.rn_breathes_in = { name = "SHE BREATHES IN", power = 215, magic = true, target = "all", windup = 34, warn = "THE DARK BREATHES IN" }
A.rn_crawls_out = { name = "SOMETHING CRAWLS OUT", target = "summon" }

local F = R.foes

F.rn_ruin_bat = { name = "RUIN BAT", tier = 34, shape = "small", sprite = "bat", family = "harpy", abilities = { { "bite", 3 }, { "shriek", 1 } }, weak = { "fire" } }
F.rn_starved = { name = "STARVED STITCHER", short = "STITCHER", tier = 35, shape = "quick", sprite = "vampire_knight", family = "staff", abilities = { { "rn_thirst", 3 }, { "rn_lance", 1 } }, weak = { "holy", "fire" } }
F.rn_unwoken = { name = "THE UNWOKEN", short = "UNWOKEN", tier = 35, shape = "healer", sprite = "thrall", family = "blighted", abilities = { { "rn_still_asking", 2 }, { "field_surgery", 1 }, { "sn_eaten", 1 } } }
F.rn_ruin_blighted = { name = "RUIN BLIGHTED", short = "BLIGHTED", tier = 34, shape = "brute", sprite = "blighted", family = "blighted", abilities = { { "claw", 3 }, { "touch", 1 } }, weak = { "holy" } }
F.rn_gut_leech = { name = "SPINE LEECH", tier = 35, shape = "small", sprite = "leech", family = "bug", abilities = { { "bite", 3 }, { "retch", 1 } }, weak = { "fire" } }
F.rn_fat_leech = { name = "SPINE GORGER", tier = 36, shape = "tank", sprite = "leech", family = "bug", abilities = { { "rn_smother", 2 }, { "rn_sour", 1 } }, weak = { "fire" } }
F.rn_sleepless = { name = "THE SLEEPLESS", short = "SLEEPLESS", tier = 36, shape = "quick", sprite = "rn_sleepless", family = "staff", abilities = { { "rn_round", 3 }, { "rn_declare", 1 } }, immune = { "sleep", "nightmare" } }
F.rn_last_orderly = { name = "LAST ORDERLY", tier = 36, shape = "brute", sprite = "orderly", family = "staff", abilities = { { "baton", 3 }, { "rn_round", 2 }, { "needle", 1 } } }
F.rn_ward_sister = { name = "WARD SISTER", tier = 36, shape = "healer", sprite = "doctor", family = "staff", abilities = { { "baton", 2 }, { "draught", 1 }, { "suture", 2 } } }
F.rn_reserve = { name = "THE RESERVE", short = "RESERVE", tier = 36, shape = "quick", sprite = "sn_bloodshot", family = "blighted", abilities = { { "sn_sorry", 3 }, { "rn_thirst", 2 } }, weak = { "fire", "holy" } }
F.rn_cold_keeper = { name = "COLD KEEPER", tier = 36, shape = "tank", sprite = "sn_keeper", family = "staff", abilities = { { "rime", 2 }, { "baton", 3 } }, weak = { "fire" }, resist = { "ice" } }
F.rn_cask_crab = { name = "CASK CRAB", tier = 36, shape = "tank", sprite = "rn_crab", family = "bug", abilities = { { "claw", 3 }, { "rn_smother", 1 } }, weak = { "bolt" }, resist = { "ice" } }
F.rn_brine_louse = { name = "BRINE LOUSE", tier = 36, shape = "small", sprite = "sn_cask_louse", family = "bug", abilities = { { "bite", 3 }, { "leech_vein", 1 } }, weak = { "bolt" } }
F.rn_clot = { name = "RED CLOT", tier = 38, shape = "small", sprite = "rn_clot", family = "blighted", abilities = { { "rn_smother", 3 }, { "rn_cup", 1 } }, weak = { "fire" }, resist = { "blood" } }
F.rn_contented = { name = "STILL CONTENTED", short = "CONTENTED", tier = 38, shape = "healer", sprite = "thrall", family = "blighted", abilities = { { "rn_still_asking", 2 }, { "field_surgery", 2 } } }
F.rn_famished = { name = "FAMISHED GUARD", short = "FAMISHED", tier = 38, shape = "brute", sprite = "vampire_knight", family = "staff", abilities = { { "rn_lance", 2 }, { "rn_thirst", 3 } }, weak = { "holy", "fire" } }
F.rn_hollowling = { name = "HOLLOWLING", tier = 40, shape = "quick", sprite = "rn_hollowling", family = "boss", abilities = { { "rn_maw", 2 }, { "rn_empty", 1 } }, weak = { "holy" }, resist = { "blood" } }
F.rn_gullet = { name = "GULLET THING", tier = 40, shape = "tank", sprite = "rn_hollowling", family = "boss", abilities = { { "rn_smother", 3 }, { "rn_black_spit", 1 } }, weak = { "holy" }, resist = { "blood" } }

F.rn_prynne = {
  name = "HOUSE OFFICER PRYNNE", short = "PRYNNE", tier = 37, shape = "caster", sprite = "rn_prynne", family = "boss", weak = { "holy" },
  boss = { hpx = 0.76, phases = {
    { at = 100, moves = { { "rn_round", 5 }, { "rn_declare", 3 } }, every = 5, big = "rn_seven" },
    { at = 66, moves = { { "rn_round", 4 }, { "rn_declare", 3 }, { "rn_kept_under", 2 } }, every = 4, big = "rn_seven", say = "HE RINGS FOR THE NIGHT STAFF", call = "rn_ring_staff", summon = "rn_ward_sister" },
    { at = 33, moves = { { "rn_round", 5 }, { "rn_kept_under", 2 }, { "rn_declare", 2 } }, every = 3, big = "rn_seven", say = "HE IS VERY NEARLY ASLEEP", speedUp = 1, call = "rn_ring_staff", summon = "rn_sleepless" },
  } },
}
F.rn_giving = {
  name = "THE GIVING", tier = 39, shape = "tank", sprite = "rn_giving", family = "boss", weak = { "fire" }, resist = { "blood", "ice" }, size = 2,
  boss = { hpx = 1.1, phases = {
    { at = 100, moves = { { "rn_smother", 5 }, { "rn_cup", 3 } }, every = 5, big = "rn_eaten" },
    { at = 66, moves = { { "rn_smother", 4 }, { "rn_cup", 3 }, { "rn_sour", 2 } }, every = 4, big = "rn_eaten", say = "EVERYONE GIVES A LITTLE", call = "rn_wells_up", summon = "rn_contented" },
    { at = 33, moves = { { "rn_cup", 4 }, { "rn_sour", 3 }, { "rn_smother", 3 } }, every = 3, big = "rn_eaten", say = "IT WILL TAKE THE WHOLE", speedUp = 1, call = "rn_wells_up", summon = "rn_clot" },
  } },
}
F.rn_tyamet = {
  name = "TYAMET THE HOLLOW ONE", short = "TYAMET", tier = 41, shape = "brute", sprite = "tyamet", family = "boss", resist = { "blood", "mind" }, weak = { "holy" }, size = 3,
  boss = { hpx = 0.78, phases = {
    { at = 100, moves = { { "rn_maw", 5 }, { "rn_empty", 3 } }, every = 5, big = "rn_breathes_in" },
    { at = 75, moves = { { "rn_maw", 4 }, { "rn_empty", 3 }, { "rn_black_spit", 2 } }, every = 5, big = "rn_breathes_in", say = "SHE IS NOT FULL", call = "rn_crawls_out", summon = "rn_hollowling" },
    { at = 50, moves = { { "rn_maw", 4 }, { "rn_black_spit", 3 }, { "death_mark", 1 } }, every = 4, big = "rn_breathes_in", say = "SHE HAS NEVER BEEN FULL", speedUp = 1, call = "rn_crawls_out", summon = "rn_gullet" },
    { at = 25, moves = { { "rn_maw", 5 }, { "rn_empty", 4 }, { "death_mark", 1 } }, every = 3, big = "rn_breathes_in", say = "THE HOLLOW OPENS", speedUp = 1, call = "rn_crawls_out", summon = "rn_hollowling" },
  } },
}

local E = R.encounters

E.rn_field_1 = { foes = { "rn_ruin_bat", "rn_ruin_bat", "rn_ruin_bat" }, flee = true, bg = "ash" }
E.rn_field_2 = { foes = { "rn_ruin_blighted", "rn_ruin_blighted" }, flee = true, bg = "ruin" }
E.rn_field_3 = { foes = { "rn_unwoken", "rn_starved" }, flee = true, bg = "grass" }
E.rn_field_4 = { foes = { "rn_starved", "rn_starved" }, flee = true, bg = "ruin" }
E.rn_e_field1 = { foes = { "rn_starved", "rn_ruin_bat" }, flee = true, bg = "city" }
E.rn_e_field2 = { foes = { "rn_ruin_blighted", "rn_ruin_bat" }, flee = true, bg = "cave" }
E.rn_e_field3 = { foes = { "rn_unwoken", "rn_ruin_blighted" }, flee = true, bg = "swamp" }
E.rn_e_gut1 = { foes = { "rn_gut_leech", "rn_gut_leech", "rn_gut_leech" }, flee = true, bg = "swamp" }
E.rn_e_gut2 = { foes = { "rn_fat_leech", "rn_gut_leech" }, flee = true, bg = "swamp" }
E.rn_e_rounds = { foes = { "rn_sleepless", "rn_sleepless" }, flee = true, bg = "marble" }
E.rn_e_rounds2 = { foes = { "rn_last_orderly", "rn_ward_sister" }, flee = true, bg = "marble" }
E.rn_e_reserve = { foes = { "rn_reserve", "rn_reserve" }, flee = true, bg = "snow" }
E.rn_e_cold1 = { foes = { "rn_cold_keeper", "rn_ruin_bat" }, flee = true, bg = "snow" }
E.rn_e_cold2 = { foes = { "rn_reserve", "rn_cold_keeper" }, flee = true, bg = "snow" }
E.rn_e_sea1 = { foes = { "rn_cask_crab", "rn_brine_louse" }, flee = true, bg = "brine" }
E.rn_e_sea2 = { foes = { "rn_brine_louse", "rn_brine_louse", "rn_brine_louse" }, flee = true, bg = "brine" }
E.rn_e_spear1 = { foes = { "rn_famished", "rn_starved" }, flee = true, bg = "marble" }
E.rn_e_spear2 = { foes = { "rn_contented", "rn_famished" }, flee = true, bg = "marble" }
E.rn_e_veins1 = { foes = { "rn_clot", "rn_clot", "rn_clot" }, flee = true, bg = "chain" }
E.rn_e_veins2 = { foes = { "rn_contented", "rn_clot" }, flee = true, bg = "chain" }
E.rn_e_hollow1 = { foes = { "rn_hollowling", "rn_hollowling" }, flee = true, bg = "ash" }
E.rn_e_hollow2 = { foes = { "rn_gullet", "rn_hollowling" }, flee = true, bg = "ash" }
E.rn_boss_prynne = { foes = { "rn_prynne" }, flee = false, bg = "marble", boss = true }
E.rn_boss_giving = { foes = { "rn_giving" }, flee = false, bg = "chain", boss = true }
E.rn_boss_tyamet = { foes = { "rn_tyamet" }, flee = false, bg = "ash", boss = true }

R.field.ruin_north = { "rn_field_1", "rn_field_2", "rn_field_3", "rn_field_4" }

R.art = {
  rn_sleepless = "A hospital orderly in a spotless grey tunic with no mask and very red eyes, standing perfectly straight, a clipboard held to the chest.",
  rn_prynne = "A very thin young doctor in physician's grey, reddest eyes in the world, holding out a neatly folded corner of a bed sheet.",
  rn_crab = "A crab as wide as a table that has grown its shell around a blood cask, with the Synder Fleet's stencil still legible on its back.",
  rn_clot = "A wobbling knot of black-red jelly, the size of a dog, with a clean little ribbon stuck in it.",
  rn_giving = "A rearing wave of old dark blood with a skin on it, thousands of small cups and silver lancets turning inside it, and across the crest of the wave one enormous smile, up on both sides, exactly the same.",
  rn_hollowling = "A dragon-shaped thing of black scales with nothing inside, the ribs showing darkness, its mouth open and no throat behind it.",
}

-- ---------------------------------------------------------------- shops

R.shops.rn_maud = { tier = 6 }
R.shops.rn_dulcie = { tier = 6 }
R.shops.rn_vesh = { tier = 6 }
R.shops.rn_tallow = { tier = 6 }
R.shops.rn_nell = { tier = 6 }
R.shops.rn_sedge = { tier = 7 }

-- ---------------------------------------------------------------- the story guide

R.goals = {
  { done = "rn_heard", text = "Go north to Adaphis", site = "adaphis_r", when = "rs_done" },
  { done = "rn_ant_in", text = "Go west to Antarith", site = "antarith_r", when = "rn_heard" },
  goal("rn_met_asphodel", "Find Asphodel Syren", "rn_antarith", "a", "rn_ant_in"),
  goal("rn_cold_cut", "Shut the cold line", "rn_icehouse", "w", "rn_met_asphodel"),
  goal("rn_sea_cut", "Shut the sea line", "rn_seaworks", "w", "rn_met_asphodel"),
  goal("rn_asphodel_in", "Go back to Asphodel", "rn_antarith", "a", "rn_met_asphodel"),
  goal("rn_spear_open", "Go to the Spear at Syndalia", "rn_syndalia", "u", "rn_asphodel_in"),
  goal("rn_giving_down", "Drain the Veins", "rn_veins", "g", "rn_spear_open"),
  goal("rn_done", "End the Hollow One", "rn_hollow", "z", "rn_giving_down"),
}

-- ---------------------------------------------------------------- who says what

local hero, doc, owl, sis, jez, asp = line("hero"), line("deserter"), line("owlin"), line("cleric"), line("jezzara"), line("asphodel")

local harrow = person("rn_harrow", "FOREWOMAN HARROW")
local tom = person("rn_tom", "OLD TOM")
local maud = person("rn_maud", "CANTEEN MAUD")
local osric = person("rn_osric", "OSRIC")
local loveday = person("rn_loveday", "MR LOVEDAY")
local cray = person("rn_cray", "MOTHER CRAY")
local fenn = person("rn_fenn", "GOODMAN FENN")
local refugee = person("rn_refugee", "A WOMAN FROM THE WEST")
local hale = person("rn_hale", "PROFESSOR HALE")
local henman = person("rn_henman", "THE HEN-BEARER")
local bram = person("rn_bram", "BRAM THE SWEEPER")
local porter = person("rn_porter", "HOSPITAL PORTER")
local prynne = person("rn_prynne", "HOUSE OFFICER PRYNNE")
local nell = person("rn_nell", "CRAB NELL")
local holt = person("rn_holt", "HOLT")
local kest = person("rn_kest", "WARDEN KEST")
local pell = person("rn_pell", "DOCTOR NYE")
local drum = person("rn_drum", "BRIDGEMAN")
local rime = person("rn_rime", "GRANNY RIME")
local sedge = person("rn_sedge", "AUNT SEDGE")
local asphodel = person("rn_asphodel", "ASPHODEL SYREN")
local tam = person("rn_tam", "TAM")
local thrax = person("rn_thrax", "MR THRAX")
local lira = person("rn_lira", "LIRA")
local davin = person("rn_davin", "DAVIN")
local grub = person("rn_grub", "GRUB")
local vesh = person("rn_vesh", "VESH")
local corin = person("rn_corin", "CORIN VALE")
local maren = person("rn_maren", "MAREN VALE")
local wallboy = person("rn_wall_boy", "TOBIT WANE")
local broom = person("rn_barnabas_broom", "BARNABAS")
local lord = person("rn_barnabas_lord", "BARNABAS KNIFE TOOTH")
local bress = person("rn_bress", "MOTHER BRESS")
local hesper = person("rn_hesper", "HESPER WANE")
local nettle = person("rn_nettle", "NETTLE")
local coldman = person("rn_cold_man", "THE COLD LINE")
local ceiridwen = person("rn_ceiridwen", "CEIRIDWEN HEARTFORD")
local tallow = person("rn_tallow", "OLD BARLOW")
local seawoman = person("rn_sea_woman", "THE SEA LINE")
local undella = person("rn_undella", "UNDELLA")
local fenwick = person("rn_fenwick", "OLD FENWICK")
local perrin = person("rn_perrin", "PERRIN")
local anwen = person("rn_anwen", "ANWEN")
local dulcie = person("rn_dulcie", "DULCIE MELON")
local amareth = person("rn_amareth", "MOTHER AMARETH")
local oswin = person("rn_oswin", "CONSTABLE OSWIN")

--- Lists of steps, one after another.
local function joined(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, step in ipairs(list) do out[#out + 1] = step end
  end
  return out
end

--- A place the hero can't yet get into alone, in the months before the party is back together.
local function shutOut(id, text, x, y)
  S[id] = { t(text), { world = { x, y } } }
end

shutOut("rn_shut_ribs", "A wall of carts, and a woman on top of it with a hammer. 'Nobody comes in alone. Find your people and come back.'", 104, 28)
shutOut("rn_shut_antarith", "A line of lamps across the road, and pale soldiers who look at your neck and then, with an effort, away. 'Not alone. Please.'", 20, 38)
shutOut("rn_shut_upriftin", "Boards across the street, and a very large crossbow. 'Town's shut. Come back with friends, or come back as meat.'", 30, 24)
shutOut("rn_shut_eighstead", "The harbour chain is up, and a boat comes out to say so. 'Full, love. Come back when you've someone to help you row.'", 11, 31)
shutOut("rn_shut_syndalia", "You can smell it from here. Something enormous lies across the white streets, twitching. You aren't going into that alone.", 36, 28)

-- ---------------------------------------------------------------- Adaphis

S.rn_ribs_in = {
  t("The Corpse of Adaphis has lost its head. The steeples of the Cranial stand behind a wall of carts, and someone has chalked a hammer on everything else."),
  t("The Ribs are still working. The sheds are turning out stoves and very large saucepans, from the moulds they used for guns, and it shows."),
  doc("Not one cart, friend. I've been standing here a full minute, and I haven't seen one cart. Give me a moment."),
  owl("There are refugees all along the rib. Look at the mouths. Those people have walked over the mountains, and they're delighted."),
  { when = "rd_done", steps = {
    sis("They aren't. I've got my hand on their threads, and I'd like somebody to take it off."),
  } },
  { set = "rn_ribs_in" },
}

local JOB_ASK = {
  ask(harrow("We've got the Ribs, the Works and the Gutter. We haven't got the head. I could use people who've been up there and come back."), {
    topic("Who's holding the Cranial?", {
      harrow("A boy called Prynne. House Officer. Colette left him in charge for a fortnight, the week she killed the King. That was thirteen months ago. He's still doing the rounds."),
    }),
    topic("Why not storm it?", {
      harrow("The sopor main for the Long Ward runs off a wheel in the Open Door. Thirty thousand asleep down the spine from it. We come up the front, he shuts the wheel, and they stop."),
    }),
    { "We'll go up.", {
      harrow("Thought you might. Cray's got a way that isn't the front. She's on the next rib, and Fenn'll let you down the manhole."),
      { set = "rn_job" },
    } },
    { "We've got to go west first.", {
      harrow("Then go. It'll keep. That's the horror of it."),
    } },
  }),
}

S.rn_talk_harrow = {
  { when = "side_revolution", steps = {
    harrow("Either pick up a shovel or go and save the world. I've got a harvest to invent."),
  }, other = {
    { when = "rn_job", steps = {
      { when = "rn_prynne_down", steps = {
        harrow("He's down? Then what are you doing here? There's still a wheel up there. Go and see to it."),
      }, other = {
        harrow("Cray's on the next rib up. Mind Prynne. He's very polite. They're the ones you want to watch."),
      } },
    }, other = {
      { when = "rn_harrow_told", steps = JOB_ASK, other = {
        t("The press is still in the back room behind the washing, though nobody's hiding anything now. Forewoman Harrow looks up from a heap of ration slips. She's picked up a city and lost two fingers."),
        { when = "px_revolt_started", steps = {
          harrow("You. The ones with the book. When the sky went wrong the Clinic's pay stopped, and the Ribs walked up to the Works with those sheets in their hands. We read the names out at the gate, and they opened it. Half of them looked relieved. I'd have liked them to look less relieved."),
        }, other = {
          harrow("You. The ones with the book. We rose without it. The sky went wrong, the pay stopped, and we walked up with hammers."),
          ask(harrow("It found its way to me in the end, and I never printed it. People are starting to ask what it was all for, and I've nothing to show them but a big saucepan."), {
            topic("Why didn't you print it?", {
              harrow("I needed the drains. Then I needed a week. Then I'd read page ninety again. It's a hard thing, setting your own brother in type."),
            }),
            { "Print it. Every name. Today.", {
              t("The doctor takes the ledger from under the mangle and lays it on the press-bed, open at a page with a very nice signature on it."),
              doc("Mine as well, please. Set it nice and large."),
              t("The press starts to thump, slowly, like something waking up. By morning there isn't a wall in the Ribs without a name on it, and people are going along them with their fingers, very quietly, reading."),
            } },
          }),
        } },
        { set = "rn_harrow_told" },
        { set = "rn_heard" },
        harrow("Now, half of Ebrein's on my doorstep, smiling. Something's happened to Sindal. Ask them, and they offer you melon and burst into tears."),
        { when = "rn_ant_in", other = {
          harrow("There's a name they all say. A lady at Antarith who takes anyone. If you want to know what's gone on in the west, ask her."),
        } },
        JOB_ASK[1],
      } },
    } },
  } },
}

S.rn_talk_tom = {
  ask(tom("The Ninth Rib, under new management. It's still me. There's a bed for twenty-five. The revolution fixed prices and then cried."), {
    { "A bed, please.", { { inn = 25 } } },
    { "No, thanks.", {} },
  }),
}

S.rn_talk_maud = {
  ask(maud("Found the peaches. Nine hundred tins, in a crate marked MEDICAL. Any child who can tell me what a peach is gets one. What d'you want?"), {
    { "Show me the supplies.", { { shop = "rn_maud" } } },
    { "Never mind.", {} },
  }),
}

S.rn_talk_osric = {
  { when = "side_revolution", steps = {
    osric("They've brought her down a tenth. Yesterday she said my name. It took her most of the afternoon. It's the best thing I've ever had to wait for."),
  }, other = {
    osric("Ten letters now. I found her, you know. Rack forty, third cot. I go down and read to her. Nobody told me she'd have got old. This last letter's the first that has ever said anything."),
  } },
}

S.rn_talk_loveday = {
  t("A small, unhappy old man sits with a very good pen, between two pipefitters who aren't sure what they're guarding."),
  ask(loveday("Thirty thousand families, the Forewoman says, each by hand, all over again. The truth, this time. It's terribly hard to get the tone."), {
    topic("What do you write now?", {
      loveday("'Your wife is alive. She is not well. I am the one who wrote that she spoke of you warmly.' There's no variety in it at all."),
    }),
    { "Keep writing.", {
      loveday("Oh, yes. There's still no form for stopping."),
    } },
  }),
}

S.rn_talk_refugee = {
  refugee("It is a lovely... no. Excuse me. I walked from Syndalia. My feet are bleeding, and I can't stop looking pleased about it. Have you eaten? I'm sorry. I don't know how to turn it off."),
}

S.rn_talk_fenn = {
  fenn("Funerals, removals, condolences. People want to do their own crying now. The drain's shut, unless the Forewoman says otherwise. I'm sorry for your loss. It saves time."),
}

S.rn_talk_cray = {
  { when = "rn_job", steps = {
    { when = "side_revolution", steps = {
      cray("Now I've got a hospital with a roof. It leaks. Get out of the way, you're standing in the good bit."),
    }, other = {
      { when = "rn_prynne_down", steps = {
        cray("You've put that boy to bed, then. Good. There's a wheel up there wants a hand on it, and it won't be his."),
      }, other = {
        ask(cray("The front's Harrow's, and the back's mine. Old Bram's poured lavender down the Spine Shaft for fifty years, so my patients needn't smell the Cranial. A shaft that lets a smell down will let a person up."), {
          topic("Where does it come out?", {
            cray("A linen cupboard, past the Spine Drain, east end. There'll be a grate. The old sluice wheel lifts it."),
          }),
          { "We'll find it.", {
            cray("Tell that boy the bed by the window wants turning. He'll know. They always know."),
            { set = "rn_cray_word" },
          } },
        }),
      } },
    } },
  }, other = {
    cray("You again. I don't do politics. I do turning people over. If Harrow wants something, she knows where I am."),
  } },
}

S.rn_gut_in = {
  t("The Gutter has gone quiet since the carts stopped. What's left down here has got thin, and bad-tempered, and very large."),
}

S.rn_t_harbottle = {
  t("A proper grave, with a board. 'MR HARBOTTLE. THIRTY YEARS A CLERK. HE IS NOW RESTING COMFORTABLY. THIS TIME HE MEANS IT.'"),
}

S.rn_t_gut_wheel = {
  { when = "rn_sluice", steps = {
    t("The old sluice wheel. It's done what it can."),
  }, other = {
    ask(t("An old sluice wheel, with a neat painted line: SPINE GRATE. LIFT FOR THE SWEEPING ONLY."), {
      { "Turn it.", {
        t("It takes two of you. Off to the south and east, something heavy lifts out of the mud with a sound like a boot coming off."),
        { set = "rn_sluice" },
      } },
      { "Leave it.", {} },
    }),
  } },
}

S.rn_t_gut_grate = {
  t("An iron grate as thick as your wrist. Past it a narrow stair goes up, and all of it smells of somebody's grandmother."),
}

S.rn_cr_in = {
  t("You come out behind a stack of linen, into a white street under a wrong sky. A bell strikes the hour, though it isn't one. A line of orderlies goes by with their masks off, at a steady pace. There's nothing in those eyes but red."),
  doc("They've stopped sleeping. All of them. Oh, Prynne. What have you done?"),
  owl("It's the only district on the continent still working perfectly, and I'd like very much to set fire to it."),
  { set = "rn_cr_in" },
}

S.rn_talk_bram = {
  t("An old man is pouring a jug down a hole at the foot of the wall. He looks up, and swallows, and looks at something interesting."),
  bram("Fifty-one years. Mother Cray's lot still have noses. You came up the shaft? I never saw you. I've had the practice."),
}

S.rn_talk_hale = {
  { when = "side_revolution", steps = {
    hale("Is it the two o'clock? I've forty first years, and a fishwife with a sore foot. Read the set texts."),
  }, other = {
    { when = "rn_chit", steps = {
      hale("That's your chit. There is always a test."),
    }, other = {
      ask(hale("Is it the two o'clock? Sit. I've a full hall at last. The orderlies come in at night and sit very straight. Nobody's slept through a lecture in a year. It's the most frightening thing that's ever happened to me."), {
        topic("Who's in charge up here now?", {
          hale("Prynne, the House Officer. Colette left him to mind things. Fainted at his first dissection. Best bedside manner I ever saw. He asked her what he should do while she was gone, and she told him. She's the only one who ever did."),
        }),
        { "We need to get into the hospital.", {
          hale("Do you? I'm still the Regius Professor, though nobody's told the Regius. Here. Visiting hours, by a physician's hand."),
          { set = "rn_chit" },
        } },
      }),
    } },
  } },
}

S.rn_talk_henman = {
  ask(henman("I carry Lady Margaret, thirteenth of that name, Taster to the Crown. It's been a hard year for tasters. Since last spring she's also the senior surviving officer of the realm. I've had it looked up."), {
    topic("You mean Plexios is ruled by a hen?", {
      henman("In strict order of precedence, yes. There've been no new taxes."),
    }),
    { "Good day, Your Majesty.", {
      t("The hen looks at you with one round orange eye. You have the distinct feeling you've been noted."),
    } },
  }),
}

S.rn_talk_porter = {
  { when = "rn_chit", steps = {
    t("The Porter holds the chit close to his red eyes, and his lips move."),
    porter("Visiting hours. In order. It's been so long. Wipe your feet."),
    { set = "rn_porter_ok" },
  }, other = {
    porter("The Open Door Hospital. Closed, by order. Visitors by a physician's hand only. One patient, expected. The bed's been aired."),
  } },
}

S.rn_t_bed = {
  t("A bed made up in hospital corners, with a chair beside it. The card says {hero}, in a very neat hand. Below that: 'I would so hate to treat you in the field. C.'"),
}

--- What Prynne can be told. The window bed is only there once Mother Cray has given you the word.
local function prynneAsks(extra)
  local options = {
    topic("She isn't coming back.", {
      prynne("That isn't on the chart."),
      doc("The sky's broken, Prynne. Look out of the window."),
      prynne("We keep the blinds down on this ward. It's better for the patients."),
    }),
    topic("Let go of the wheel.", {
      prynne("If I stopped, somebody would have to tell me what to do. There isn't anybody. Do you see? There isn't anybody."),
    }),
    { "I'm not getting in your bed.", {
      prynne("You may refuse. It's on the form. I do hate this part."),
    } },
  }
  options[#options + 1] = extra
  return ask(prynne("The bed's been aired every morning. Won't you lie down? I've got you for seven o'clock."), options)
end

S.rn_scene_prynne = {
  { save = true },
  t("The Open Door is very clean, and nearly silent. One lamp, one chair. A thin young man in physician's grey stands at the foot of a bed with a clipboard. He looks about twenty-six and about ninety, and his eyes are the reddest you've seen in a living head."),
  prynne("Ah, {hero}. You're expected. House Officer Prynne. Doctor Colette has stepped out, and she's asked me to keep everything exactly as she left it. She did say a fortnight."),
  doc("Prynne. You were on my ward. You used to faint."),
  prynne("Doctor! I've had time to get over that. It's been thirteen months. Or one day, if you do it without a break, and I've found that's simpler."),
  { when = "px_gave_blood", steps = {
    prynne("She left a small glass in the cold room, with your name on it. I've had a drop on my tongue every night. One needn't sleep at all, did you know? There's nothing there. Nothing, nothing, nothing, all the way down."),
    t("He says it the way you said it every morning of your life, to a clerk with a Dream Book."),
  }, other = {
    prynne("She left your chair out, and a needle on a cloth. She said you'd come and give it yourself, in the end. I've not slept since, in case I missed you. It's quite easy, once one stops."),
  } },
  { when = "rn_cray_word", steps = {
    prynneAsks({ "Mother Cray says the window bed wants turning.", {
      t("His hand goes out, all by itself, to the bed. For a moment he's twenty-six."),
      prynne("Yes. It does. I've been... No. I've got it down for seven o'clock."),
    } }),
  }, other = {
    prynneAsks(),
  } },
  { battle = "rn_boss_prynne" },
  t("He sits down on the edge of the bed, very carefully, so as not to crease it, and looks at the pillow for some time."),
  prynne("I wonder, would it be all right if I..."),
  t("The doctor takes off Prynne's shoes, lifts his feet up, and pulls the sheet straight. He's asleep before it's done. He doesn't wake."),
  { set = "rn_prynne_down" },
}

S.rn_scene_valve = {
  { when = "rn_prynne_down", steps = {
    t("A brass wheel on the wall, warm to the touch, and a chart with thirty thousand ticks on it."),
    ask(doc("Shut it and they stop. Leave it and they dream for ever. Or a tenth a month, and someone turning each of them by hand. Most won't come back as anyone. Some will. Whose hand goes on the wheel?"), {
      { "Mother Cray's. It's her hospital.", {
        doc("Yes. It always was."),
      } },
      { "Yours, doctor. Write it out, and show her.", {
        doc("A feeding chart. It's the one thing I've ever been truly qualified for."),
      } },
    }),
    t("You raise the blinds. The light that comes in is the wrong colour, and all down the white street the bell stops, in the middle of an hour."),
    { fade = true },
    warp("rn_ribs", "k", 1),
    t("Three days on. The carts come down from the Cranial, full of the Cranial, and nobody's hurt. The orderlies walk as far as the first bed anyone offers, and fall on it. Nobody has the heart to count."),
    harrow("Thirty thousand people with a chance, and the gate open with no blood on it. I don't know what that's worth, so I asked the foundry."),
    { give = "last_light" },
    { gold = 4000 },
    t("There's a treaty. It's signed by a forewoman and, in the absence of anyone senior, by a hen. Lady Margaret walks across the seal with great dignity."),
    t("At the top of the spine an old man with a chisel is cutting letters back into the College door, very badly. ALL WHO ARE SICK MAY COME. Mother Cray stands below and tells him where he's gone wrong."),
    harrow("A rib's so what's inside doesn't get crushed. I said that was all the plan we had. Now get out of here. You're not on the rota."),
    { big = "THE OPEN DOOR IS OPEN" },
    { set = "side_revolution" },
  }, other = {
    t("A brass wheel on the wall, warm to the touch. Someone in a grey coat is standing between you and it."),
  } },
}

-- ---------------------------------------------------------------- the small towns

S.rn_talk_nell = {
  ask(nell("The bridge is down and the crab's gone funny. I've got a claw here with an opinion. I'm still selling, though."), {
    { "Show me what you've got.", { { shop = "rn_nell" } } },
    { "Not today, Nell.", {} },
  }),
}

S.rn_talk_holt = {
  holt("Forty years I took people over the Nevermore Portal. Now there's a very fine view of where it was. People still buy a ticket. I think they like being told it's on time."),
}

S.rn_talk_kest = {
  kest("We hunted the smilers, the first month. We thought they were bait. Then one sat down in front of my bow and asked if I'd eaten, crying the whole time. I've told my people to shoot what bites."),
}

S.rn_talk_pell = {
  ask(pell("Four hundred from Ebrein in the yard. The Clinic trained me to say 'fit' or 'unfit'. It's amazing how little of that one uses."), {
    topic("Can anything be done about the smiling?", {
      pell("Cut the scar band, and the mouth falls. I've done eleven. Half of them weep with relief. One old fellow looked in my shaving glass and asked me to put it back."),
    }),
    { "Keep at it, Doctor.", {} },
  }),
}

S.rn_talk_drum = {
  t("A big man in a grey smock stands at the north drum with both hands on the bar. The bridge went into the gorge a year ago, and there's only the old footing across now. He's still turning it, and there's nothing on the chain."),
  ask(drum("I know it's gone. I woke up in the spring, holding this. Every time I think what to do next, I get as far as letting go."), {
    topic("What do you remember?", {
      drum("Everyone who went over. Those lads, in rows, for the Crevice. I wound them across. I said it was a lovely day."),
    }),
    { "There's a town at Antarith. They'll take you.", {
      drum("Will they? Yes. I'll just do this turn."),
    } },
  }),
}

S.rn_t_post_grave = {
  t("A stone by the old post. Someone came all the way up here to cut it. 'ANSEL WANE. HE WAS FOR THE CAVALRY.'"),
}

S.rn_talk_rime = {
  ask(rime("Two crowns bowed, and one's been eaten and the other's in a hole. Best year I've had in three centuries."), {
    topic("Sindal's crate came from below.", {
      sedge("Oars, under the ice, a year before the sky went. They rowed it so carefully, and they were so frightened of it."),
      rime("Something that gave a god a cough isn't a thing you open. They'd have told him it was a key. It's a very good lie. It's almost true."),
    }),
    { "Good day, Granny.", {} },
  }),
  { when = "wm_lucilda_dead", steps = {
    t("Old Mother Tallow sits by the far reeds with a place laid beside her, and nobody in it."),
  }, other = {
    { when = "wm_took", steps = {
      rime("She came home, you know, the old buzzard. Very pleased with herself. She still hasn't paid."),
    } },
  } },
}

S.rn_talk_sedge = {
  ask(sedge("I've a few things put by, dear. A hag doesn't tell you what they cost until much later."), {
    { "Show me.", { { shop = "rn_sedge" } } },
    { "No, thank you.", {} },
  }),
}

-- ---------------------------------------------------------------- Antarith

S.rn_ant_in = {
  t("Antarith still has its window boxes. There's a line of lamps across the north road now, and a wall of carts and pews, and thin pale soldiers on it. A very large devil goes along the road with a watering can, giving people a drink."),
  { when = "side_barnabas", steps = {
    t("There are boys on the wall, hundreds of them, in old red tunics, standing very straight. A bucket on a pole goes along behind them."),
    doc("That's my feeding chart, friend. They've kept to the quantities."),
  }, other = {
    { when = "sn_coup_backed", steps = {
      doc("There ought to be three hundred more on that wall. I can count, friend. I've never been able to stop."),
    } },
  } },
  { set = "rn_heard" },
  { set = "rn_ant_in" },
}

S.rn_scene_house = {
  t("The Reformation Centre was built for devils who'd had enough. Now it's cots, wall to wall, with a smiling person on each. Most of them are crying. It's very quiet. The smile sits on top of it like a lid."),
  thrax("Mr Thrax, formerly of Soul Processing. They wake in the small hours, mostly. First the hands stop. Then they look at the hands. Then they remember it, from the beginning, in order, and nobody can do that for them."),
  thrax("Nine hundred years in the Seventh Circle, and I can tell you to the ounce how much a soul can stand. I used to think of that as a professional skill. It turns out that it is."),
  t("On the end cot a young man sits bolt upright in a grey smock, with very clean hands. He's saying something, over and over, quite pleasantly."),
  davin("It is a lovely day. It is a lovely day. It is a lovely. It is."),
  t("He stops. His hands turn over on his knees. He looks at them as if someone had just handed them to him."),
  t("A girl with pigtails is coming down the row with a tray. She's taller. Her smile still goes up on the wrong side. She reaches the end cot, and looks at him, and the bowl rattles, just a little."),
  davin("There was a chair. We brought a chair. I had the left side. You said no. You said it twice, and you said it to me. You said please. And I said..."),
  tam("You said it was a lovely day."),
  davin("You'd got no shoes on. I thought, she'll be cold. I thought it so pleasantly. Oh. Oh, no."),
  t("Nobody in the room is breathing. The smile hasn't moved. Everything else in his face has gone somewhere you can't follow."),
  { choice = {
    { "Stay where you are. Let her do this.", {
      t("It's the hardest thing you've done since you woke, and it hasn't been an easy waking."),
    } },
    { "Go to her.", {
      t("The doctor's hand closes on your sleeve, and stays there."),
    } },
  } },
  tam("You had cold hands. I remember that too."),
  t("She looks at him for rather a long time. Then she sits down on the end of the cot and holds out the spoon. Her hand isn't steady, and she doesn't put it down."),
  tam("Have you eaten?"),
  t("It's the first time you've ever heard anyone in this country ask that, and want to know."),
  doc("I was the left side of the chair for eleven years, friend. Nobody had to take anything out of me to do it. I thought I'd tell you."),
  { when = "rd_done", steps = {
    sis("His thread's come back, in a dreadful state. I've tied it to the next one along. It's not nothing."),
  } },
}

local FIRST_MEETING = {
  t("The uncomfortable chair is still here. The woman behind the desk is standing to read, at the last of the window. Her armour was made for someone with more of herself to fill it."),
  asphodel("You're still frowning. Good."),
  t("She lays a sheet on a very tall pile. It's a list, in a small upright hand. They all are."),
  asphodel("I signed them, so it seems only fair. When someone wakes and asks what they did, someone ought to be able to tell them. I've a hundred and ninety years of it, and I've reached the spring of the fourth."),
  ask(asphodel("Ask what you came to ask. Go straight to the worst of it."), {
    topic("What happened to Sindal?", {
      asphodel("He got his hobby. The black head of Tiamat, under the Spear. He had a crate brought up, the one he paid sixty people for, sixty I signed for, and he went down in his good coat and woke her. She ate him. I'd like that on a stone."),
      asphodel("Every thrall in Ebrein was held in that one hand. When it went, they all fell out of it."),
    }),
    topic("What do they remember?", {
      asphodel("Everything. I told you they weren't in pain. That's true. It was all being kept for them."),
    }),
    topic("Why are you so thin?", {
      asphodel("Nobody gives a cup any more, and I won't take one. The hundred and forty on my wall make do with what the line sends up. Eleven have stopped being able to."),
    }),
    { "What's under the Spear now?", {} },
  }),
}

local PLAN = {
  asphodel("The ribbons run both ways. Everything he banked is running back down them, into her. They call her the Hollow One because she has never once been full. She's getting closer."),
  owl("And the crate stands at her lip. If it's what I've feared since that manifest, that's what gave Qarhuul the plague. It needs something in her to catch hold of, and she's nothing in her. Yet."),
  doc("So we starve the patient. I've a certain amount of practice."),
  ask(asphodel("Three heads feed her. The cold line, under the icehouse at Upriftin. The sea line, below the dock at Eighstead. The Devils' line is in this room. Shut the first two, and come back. I'll shut mine last."), {
    topic("Why not shut yours today?", {
      asphodel("It's a cup a day to the hundred and forty on that wall, who could be eating the cots, and aren't. The day it stops, they've got nothing. So it had better be the last day."),
    }),
    { "We'll shut them.", {
      asphodel("Thank you. Go back through the House. Don't be kind about it. They can tell."),
    } },
  }),
  { set = "rn_met_asphodel" },
}

local CUT_THE_LINE = {
  asphodel("Cold and sea? Then it's today."),
  t("The Devils' line comes up through the floor behind her desk, as thick as a tree, with a small red wheel on it. She takes hold with both hands. It's the only time you ever see her look old."),
  asphodel("Stitchers of Antarith. There won't be another cup. I've nothing to offer you but my example, and I'm told it's irritating."),
  t("The wheel goes round. The note in the pipe drops, and stops. Up on the wall a hundred and forty pale heads turn at once, and turn back."),
  { when = "side_barnabas", steps = {
    t("Nobody leaves the wall. The boys in red are standing between the Stitchers and the road, because a woman with a bucket told them to, and they've had a great deal of practice at standing."),
  }, other = {
    t("Some of them walk down off the wall and away into the dark, quite slowly, apologising."),
  } },
  t("She lets go of the wheel, and doesn't quite get as far as the chair. There's a clatter of a tray in the doorway."),
  tam("Lady Asphodel. Have you eaten?"),
  asphodel("That's very funny, child."),
  tam("It isn't. It's been eleven weeks. I've been watching. Have you eaten?"),
  t("Nobody has asked her that in a hundred and ninety years. You watch it go in."),
  asphodel("No."),
  tam("You can have some of mine. I'm saying it. Nobody's asking me to."),
  asphodel("No! You've said no twice in your life, and it nearly finished you. Don't you dare say yes to me. Not you."),
  ask(t("She's on her knees, looking at the floor with enormous care. The veins are standing out in her hands."), {
    { "The doctor can spare a cup.", {
      doc("Juniper and lamp oil, I'm told, with a long finish of regret. A Cellarmaster said so, and he'd know. One moment, Lady Asphodel."),
    } },
    { "Take mine.", {
      t("She lifts your wrist, breathes in, and goes very still. Then she lays it down, as you'd put back something that was ticking."),
      asphodel("No. Thank you. There's something in that I shouldn't care to wake."),
      { when = "px_gave_blood", steps = {
        doc("The last lady who took a glass of that had a poor year. Give me the cup, friend."),
      }, other = {
        doc("I'd keep that to yourself, friend. Give me the cup."),
      } },
    } },
  }),
  t("The doctor fills it from a neat small cut, and looks at the wall. She takes it in both hands. It takes a long time, and nobody mentions it."),
  asphodel("I've never once been asked if I wanted it. Isn't that absurd?"),
  t("She gets up, and takes the sword from behind the door."),
  asphodel("Tam, the lists are in order. If anyone asks for me, tell them I've gone to see someone about it."),
  tam("You'll want a coat. It's cold in Syndalia."),
  { join = "asphodel", lvl = 36 },
  { big = "ASPHODEL SYREN JOINS" },
  asp("Syndalia, then. Undella will be on the step. She has rather a lot to say."),
  { set = "rn_asphodel_in" },
  { save = true },
}

S.rn_talk_asphodel = {
  { when = "rn_met_asphodel", steps = {
    { all = { "rn_cold_cut", "rn_sea_cut" }, steps = CUT_THE_LINE, other = {
      asphodel("Upriftin and Eighstead, under the icehouse and the dock. I'll feel each one go."),
    } },
  }, other = joined(FIRST_MEETING, PLAN) },
}

S.rn_t_devils_wheel = {
  t("A small red wheel on a pipe as thick as a tree."),
}

S.rn_talk_tam = {
  { when = "rn_done", steps = {
    tam("You came back! Davin's doing the washing up. He's terrible at it. Have you eaten?"),
  }, other = {
    { when = "rn_anwen_told", steps = {
      ask(tam("You saw Mum? Has she got any food? She never eats. She gives it all to people."), {
        topic("Will you go and see her?", {
          tam("She said wasn't that thoughtful. She couldn't help it. I know she couldn't. I'm going to go. I'm just not going yet. Is that all right?"),
        }),
        { "It's all right.", {
          tam("I've got frowning at four. Nobody's passed yet."),
        } },
      }),
    }, other = {
      tam("I do the tray, and the frowning class at four. Nobody's passed yet. You've got to start with the eyebrows."),
    } },
  } },
}

S.rn_talk_thrax = {
  thrax("People ask if it gets better. In the Circles we had a phrase. 'It gets quieter.' I always thought that was the cruellest thing we did. Now I say it forty times a night. It's true, that's the trouble."),
}

S.rn_talk_davin = {
  t("A slate on the cot says DAVIN, in a child's writing. Under that, HE HAD THE LEFT SIDE. Under that, ASK HIM ABOUT BOATS."),
  davin("She comes every morning. I can't look at her, and she makes me. I was a boatwright, you know. I'd forgotten I was anybody."),
}

S.rn_talk_lira = {
  t("A young woman with two plaits is writing at a table. A line of people wait to speak to her, and each of them smiles, and sits down."),
  ask(lira("Fewest deaths per thousand of any state in history. It's correct. I checked it again when I woke. Now I'm writing the chapter on who wasn't in the figures. They tell me what they did, and I put it down."),
    { topic("Scholar, have you anything to say?", {
      { when = "sn_lira_chapter", steps = {
        owl("Candidate. I had a reply prepared. I've carried it for some time."),
        lira("Yes? I'd honestly love one."),
        owl("Your figures are correct. It's the most important paper I've ever read. May I hold the lamp?"),
      }, other = {
        owl("I can check your arithmetic, Candidate. It's very nearly the only thing I'm good for."),
      } },
    }), { "We'll leave you to it.", {
      lira("Thank you. There's a queue."),
    } } }),
}

S.rn_talk_grub = {
  grub("Twelfth time I've been reformed, and the first anyone's needed me for it. It's the same intake form. 'How did it make you feel?' The big ones cry. They're all the big ones now. Here's your purse back."),
}

S.rn_talk_vesh = {
  ask(vesh("The Second Chance. No charge for the bed. Have you eaten? I mean it as a question. I've got a list."), {
    { "A bed, please.", { { inn = 0 }, { save = true } } },
    { "Show me the shelf.", { { shop = "rn_vesh" } } },
    { "Not now.", {} },
  }),
}

S.rn_talk_corin = {
  { when = "sn_vales_out", steps = {
    corin("I came back. I said no, and I've still got my own face. I'm the only one here who knows what they could have done instead, and I sit with them and don't say so. It's the hardest work I've done."),
  }, other = {
    t("A man with a very flat calm sits on a bench with his hands on his knees. Once, he said no twice. It's been ten days, and he's started to look at his hands."),
    corin("It is a lovely day. Have you... Who's that boy?"),
  } },
}

S.rn_talk_maren = {
  { when = "sn_vales_out", steps = {
    maren("Jory told me I was the worst mother on Embia yesterday, with his whole face. I had to go and sit down. I was so happy."),
  }, other = {
    maren("That's our Jory, by the well. His father's coming back, a bit at a time. I don't know which of them I should warn."),
  } },
}

S.rn_talk_wall_boy = {
  { when = "sn_told_hesper", steps = {
    wallboy("I'm Tobit Wane. I'm for the cavalry. Mother told me about Ansel. She said some people came and told her true."),
  }, other = {
    wallboy("I'm Tobit Wane. I'm for the cavalry. Have you seen my brother? He went to the Crevice. They say he's well."),
  } },
}

-- ---------------------------------------------------------------- Upriftin

S.rn_up_in = {
  t("Upriftin was always a little hungry, and it's taken the news better than anywhere. People are arguing in the street, loudly, with both sides of their faces."),
  owl("That man is cheating that woman over a sack of turnips. I could stand here all day."),
  { set = "rn_up_in" },
}

S.rn_talk_hesper = {
  { when = "side_barnabas", steps = {
    hesper("Tobit's on the wall at Antarith, with the rest. Three hundred boys who think it's the cavalry. I take the bucket down each month. He knows me about one time in three. That's one more than most get."),
  }, other = {
    { when = "sn_coup_backed", steps = {
      hesper("I counted three hundred up that culvert, and I counted who took the money. Do what you came for, and go."),
    }, other = {
      hesper("Nobody opened those cells. When the ice went, they walked. They're out there yet, in their good red tunics. I do the ones I know last."),
    } },
  } },
  { when = "sn_told_hesper", steps = {
    hesper("You told me about Ansel, straight. I've kept that."),
  }, other = {
    { when = "sn_lied_hesper", steps = {
      hesper("You told me Ansel was well. I went up to the post, after the sky went. I cut the stone myself. I know why people do it. I had a very nice letter once."),
    } },
  } },
  { when = "rn_met_asphodel", steps = {
    { when = "rn_cold_cut", other = {
      hesper("The cold line's under the old icehouse, by the west wall. It's been humming since the thaw."),
    } },
  } },
}

S.rn_talk_broom = {
  t("A huge man in a grey smock is sweeping the great hall, very well. He sees you, and a slow, dreadful, entirely real grin spreads across the gap in his teeth."),
  ask(broom("Here's the conscience! A year I swept for him. Four hundred years without an honest day's work, and I did three hundred and sixty-five. It's the worst thing anybody's ever done to me. I do wish I'd thought of it."),
    { topic("You remember all of it?", {
      broom("Every corner. I woke up, and this floor was the first thing I've ever finished. I've tried to steal something. I just keep noticing the skirting."),
    }), { "Keep sweeping, Barnabas.", {
      broom("Ha! I shall. Isn't that horrible?"),
    } } }),
}

S.rn_talk_lord = {
  { when = "sn_coup_backed", steps = {
    ask(lord("Partners! A cup's two silver now, and it's the only cup in Ebrein. A country needs one place where a person can go wrong. I hadn't thought how well it'd scale."), {
      topic("Three hundred boys died for you.", {
        lord("For us! You took the money. Do sit down, you're making the place look honest."),
      }),
      { "We're leaving.", {} },
    }),
  }, other = {
    lord("A frown, and a tired one! Lord of Upriftin, and shortly of everywhere else. A cup's two silver. As for my boys, they got out on their own, poor lambs. You'll have met them."),
  } },
}

S.rn_t_tooth = {
  t("The great hall is a soup kitchen now. A hand's length of bright steel has been nailed over the hatch, for opening jars. It's very good at it."),
}

S.rn_talk_bress = {
  ask(bress("Soup's a copper, and I've thirty customers from Syndalia who all say thank you. Eleven times. I've had to sit down."), {
    { "A bowl, and a bed for the night.", { { inn = 40 } } },
    { "Nothing, Mother.", {} },
  }),
}

S.rn_talk_nettle = {
  nettle("I'm twelve. Nobody came. I did my face in the window to see, and it was still mine. Berries are a gold now. They're no less sour. That's the market."),
}

S.rn_t_cell_note = {
  t("The cells stand open, and the ice has gone. There's a word scratched low on each wall, in a careful schoolboy hand. They all say CAVALRY."),
}

S.rn_scene_cold = {
  { when = "rn_cold_cut", steps = {
    t("A great wheel, stopped. The groove in the stone goes round it, with nobody in it."),
  }, other = {
    { when = "rn_met_asphodel", steps = {
      t("The pipe comes up through the floor, wide as a house, with a wheel on it taller than you. A thin grey man is walking it round with his eyes shut. His feet have worn a groove in the stone."),
      coldman("I am the cold line. It is a lovely day. Have you eaten?"),
      doc("He's been down here since before the sky broke. No light, and no one to stop for. He didn't wake, friend. Nobody told him anything had happened."),
      ask(t("The wheel comes round to you."), {
        { "Stop the wheel.", {
          t("You put your shoulder to it, and the doctor beside you. It groans, and stops. The hum that's been in your teeth for a day goes out of the world."),
          t("The man stands with his hands on the rim. Then his fingers open, one at a time. He looks at them."),
          coldman("Oh. Oh, look at my hands. What's the time? How long have I... Is my mother up?"),
          doc("Come and sit down, sir. I'm a doctor. Come and sit down, and I'll tell you what I can."),
          { set = "rn_cold_cut" },
        } },
        { "Not yet.", {} },
      }),
    }, other = {
      t("A great wheel, turning. A thin grey man walks it round with his eyes shut."),
    } },
  } },
}

-- ---------------------------------------------------------------- Eighstead

S.rn_ei_in = {
  t("Every ship of the Synder Fleet is moored in Eighstead harbour, hull to hull, with washing on the yards. It's the biggest town you've seen since the sky broke, and it's floating."),
  { set = "rn_ei_in" },
}

S.rn_talk_ceiridwen = {
  { when = "rn_sea_cut", steps = {
    ceiridwen("That's the sea line dry, and I've still got my teeth. Go on, love. Go and kill it."),
  }, other = {
    ask(ceiridwen("Ha! Sit down, shove the charts off. Have you eaten? I've got crab. I'm nine hundred and five, love, and I'm that hungry I can see your pulse. Don't mind me."),
      { topic("You shipped the casks.", {
        ceiridwen("I did. I told you I slept fine. Now I go down the rows at night and count children. I carried my sisters up that beach, and then I built this."),
      }), { "What's that humming under your dock?", {
        ceiridwen("That's the sea line, and I built the housing! The stair's in the south lane. The Good Neighbour's casks went in the water, and they've hatched."),
      } } }),
  } },
}

S.rn_talk_tallow = {
  ask(tallow("I've a boat full of useful things, and I'd sooner they went to someone who means to be alive on Thursday."), {
    { "Show me what you've got.", { { shop = "rn_tallow" } } },
    { "Not today.", {} },
  }),
}

S.rn_scene_sea = {
  { when = "rn_sea_cut", steps = {
    t("The wheel's stopped. There's a coat on the floor, neatly folded. Up the stair you can hear the gulls."),
  }, other = {
    { when = "rn_met_asphodel", steps = {
      t("The sea line comes through the wall in a great rusted elbow, and a thin woman, wet to the waist, is turning the wheel on it. She looks up. There's somebody in there. That's the first thing you notice, and you wish you hadn't."),
      seawoman("You needn't whisper. I woke up the same night as everyone."),
      owl("Madam, then why on earth are you still turning it?"),
      seawoman("Because I know what's up those stairs. I've a husband up there, and a boy. When the list came I sent the boy down myself, and I smiled at him. As long as I've got this in my hands, I'm working. I'm not anyone."),
      ask(t("She doesn't stop. The wheel comes round, and her hands go with it."), {
        { "You have to let go.", {
          seawoman("Do I? Yes. I know."),
        } },
        { "We can't go up there for you.", {
          seawoman("No. Isn't that a terrible thing?"),
        } },
      }),
      t("She takes her hands off the wheel and wipes them on her apron. Then she leans on the rim with her whole thin weight, and you lean with her, and it stops."),
      seawoman("There. Now I'm somebody. Excuse me. I've got to find my shoes."),
      { set = "rn_sea_cut" },
    }, other = {
      t("A woman wet to the waist is turning a wheel on a great rusted pipe. She looks up, and looks down. She doesn't stop."),
    } },
  } },
}

-- ---------------------------------------------------------------- Syndalia

S.rn_syn_in = {
  t("You smell Syndalia a day before you see it. The melons were in fruit when the thralls stopped, and nobody told the melons. They lay in their rows to the horizon and got sweeter, and then they went on."),
  t("Two of the ribbons lie across the white streets like something dead on a beach. The third hangs from the Spear, and twitches, once a minute. There's a crack up the Spear you could drive a cart through."),
  doc("That's the smell of a perfectly kept ward, friend, when the staff have gone home."),
  { set = "rn_syn_in" },
}

S.rn_talk_undella = {
  t("A woman in black sits on the bottom step of the Spear, with her shoes beside her. It's the first time you've seen her look at anything."),
  ask(undella("Sit first. I've a great deal saved up. I held the same fork for nineteen hundred years, and last spring I put it down."), {
    topic("What happened that night?", {
      undella("He opened the crate at table, and put on his good coat, and went down, humming. I followed. I wasn't told not to. She opened her eye. It was the first thing he'd wanted in two thousand years that hadn't come on a tray."),
      undella("He bowed. He looked up at her, and he said, 'Have you eaten?' It was the last joke he made. He would have been delighted with the answer."),
    }),
    topic("You were a thrall.", {
      undella("I was his wife. He'd have told you there's a difference, and laughed. Nobody ever went round for me. He only asked once."),
    }),
    topic("Will the country live?", {
      undella("It's sitting in the road, saying thank you. I'd like to see what it does when nobody's holding it."),
    }),
    { "Let us in.", {} },
  }),
  { when = "rn_asphodel_in", steps = {
    asp("Undella. You're speaking."),
    undella("Yes. Nobody's stopped me yet. Go in. The door was never locked. Down through the gallery, by the east stair, to the Veins."),
    { set = "rn_spear_open" },
  }, other = {
    undella("Not yet. You'd only be something else for her to swallow. Come back when Asphodel has shut her line, and is with you."),
  } },
}

S.rn_talk_fenwick = {
  ask(fenwick("You're frowning! Everyone is! It's terrible. It's lovely. A woman called me a filthy old goat this morning, and I had to go and lie down."), {
    topic("You don't mind what's happened?", {
      fenwick("I said no twice, and I've waited all this time to be proved right, and I've a street full of the dead. That's why it's such a rotten thing, being right."),
    }),
    { "Mind how you go, old man.", {
      fenwick("Why? What's going to happen to me? No, go on, I really want to know now."),
    } },
  }),
}

S.rn_talk_perrin = {
  t("A thin man in a grey smock stands in the middle of a filthy street, holding a broom, not sweeping."),
  ask(perrin("It is a filthy day. There. I've been practising. I'm Perrin. I wrote comic verses about His Excellency."), {
    topic("Do you remember one?", {
      perrin("One came back on Tuesday. 'His Excellency's looking well, / And so he might, and so he should. / He's had a little of you all, / And says you're very, very good.'"),
      t("He waits. Somewhere a melon gives up."),
      perrin("That's it. Nine years, for that. It doesn't even scan. I'd so hoped it would be better."),
    }),
    { "It's not a bad line.", {
      perrin("It's a very bad line. It's mine. Oh, that's wonderful."),
    } },
  }),
}

local ANWEN_ASKS = "I waved her off with you, from that door, and I smiled. Tam. She's twelve. She'd be thirteen. Is she...?"

S.rn_talk_anwen = {
  { when = "rn_anwen_told", steps = {
    anwen("I've saved a little rice, in case she comes. I'll not ask her anything. I'll put it on the table, and go and stand somewhere else."),
  }, other = {
    t("The Full Table still has its door on the west side. There's one pot on the fire, with very little in it, and she's set out twelve bowls."),
    anwen("Look at you, you've got thin! Have you... No. Sorry. Sit down, love."),
    anwen("Two lovely young men came with a chair. Wasn't that thoughtful? I said that. I've got the same mouth I had. It's still pleased about it."),
    { when = "rn_ant_in", steps = {
      ask(anwen(ANWEN_ASKS), {
        { "She's alive. She's at Antarith.", {
          t("Anwen stands quite still, with the spoon held out. Then she sits down on the floor."),
          anwen("Alive. Has she eaten?"),
          hero("She feeds everyone. She's got a tray."),
          anwen("Yes. She would. Don't tell her that I asked. No, do. Tell her there's a little rice."),
        } },
        { "She got out. I'll say no more than that.", {
          anwen("Out. Good girl. She always said it quite firmly."),
        } },
      }),
      { set = "rn_anwen_told" },
    }, other = {
      anwen(ANWEN_ASKS),
      hero("We left her at Antarith, with Lady Asphodel. We haven't been back."),
      anwen("Antarith. Then go and look, love, and come and tell me. I'll be here. I'm always here."),
    } },
  } },
}

S.rn_talk_dulcie = {
  ask(dulcie("I've no food, love. I've got blades, though. There's been a run on blades. Isn't that a thing?"), {
    { "Show me what you've got.", { { shop = "rn_dulcie" } } },
    { "Not just now.", {} },
  }),
}

S.rn_talk_amareth = {
  t("The spool on the altar has stopped, and the threads that ran through the floor have gone slack. She's taken them across her knees, and she's going through them, one at a time."),
  amareth("I said I don't look at those ones much. It's a very big wheel. I'm looking now. There are eleven thousand so far."),
  { when = "rd_done", steps = {
    { when = "sn_prayed", steps = {
      sis("You let me say it out loud here, Mother. I've not forgiven you for it."),
    }, other = {
      sis("I walked past this door once, Mother. I've thought about that."),
    } },
    { when = "sn_let_her_choose", steps = {
      sis("{hero} told me I could stay, you know. I'd like the other end of that, if you'll have me for an hour."),
    }, other = {
      sis("I'd like the other end of that, if you'll have me for an hour."),
    } },
  } },
}

S.rn_talk_oswin = {
  oswin("Constable Oswin. Would you believe I've got crimes? A hundred thousand of them, all confessing. They queue. I ask who I should arrest, and they all name the same man, and he's been eaten. I've reopened the badly parked cart."),
}

-- ---------------------------------------------------------------- the Spear

S.rn_t_table = {
  t("What's left of the dining room at the top of the world. The small table is still laid. On a cushion nearby is one tassel-shaped patch of clean dust."),
}

S.rn_t_manifest = {
  t("A manifest on a nail. CONSIGNED BELOW: SIXTY, SOUND, UNTRUSTED. RECEIVED IN TRADE: ONE CRATE, NOT TO BE OPENED. Below that, in a fresh and cheerful ink: 'OPENED. H.E. DELIGHTED.'"),
  asp("There's my signature, third line down. I thought if I read it slowly enough it might turn into something else."),
}

S.rn_veins_in = {
  t("The tile's still clean, and the long brass handrail's still there. But whatever's in the lake has stopped being a liquid, and hasn't decided on the next thing. The little sign is still on the rail. PLEASE DO NOT LEAN."),
}

S.rn_t_plaque = {
  t("A brass plaque, gone green. IN THE EVENT OF A SPILL, OPEN BOTH SUMP COCKS, NORTH AND EAST, AND DRAW OFF AT THE LOWER GATE. PLEASE REMAIN CALM."),
}

S.rn_t_wheel_a = {
  { when = "rn_cock_a", steps = {
    t("The north sump cock stands open."),
  }, other = {
    ask(t("A sump cock with a red iron wheel, marked NORTH."), {
      { "Open it.", {
        t("It comes round with a long wet sigh. The lake sags a little, and then rises again, as if it had noticed."),
        { set = "rn_cock_a" },
      } },
      { "Leave it.", {} },
    }),
  } },
}

S.rn_t_wheel_b = {
  { when = "rn_cock_b", steps = {
    t("The east sump cock stands open."),
  }, other = {
    ask(t("A sump cock with a red iron wheel, marked EAST."), {
      { "Open it.", {
        t("It turns easily. Someone kept it oiled for two thousand years. Down the walkway a heavy gate starts to tick."),
        { set = "rn_cock_b" },
      } },
      { "Leave it.", {} },
    }),
  } },
}

S.rn_t_stools = {
  t("Forty or fifty stools stand down the old aisle, all empty. On the last is a neat heap of wrist labels with their knots undone, and a note in careful, shaky letters. 'WE HAVE GONE UP. THANK YOU FOR ASKING.'"),
}

S.rn_scene_giving = {
  { all = { "rn_cock_a", "rn_cock_b" }, steps = {
    { save = true },
    t("The lower gate stands open a hand's width. But the lake isn't going down the drains. It's drawing itself together behind you."),
    t("Every cup, every month, from everyone twelve and up, since the Horned War. It lifts out of the basin with a skin on it, and thousands of little silver lancets turn over inside it. Across the crest something opens, and goes up at both corners."),
    asp("I signed for this. All of it. I've always thought it would come and find me."),
    { big = "HAVE YOU EATEN?" },
    { battle = "rn_boss_giving" },
    t("It comes apart all at once, as a wave does. Then it's only wet tile, and dripping, and thousands of small silver blades lying on the floor."),
    asp("That was them, as much as anything's left. I'd like to say something, and I've nothing that's the right size."),
    { when = "rd_done", steps = {
      sis("I have. It's short. It's the only one I've got that's for everyone."),
    } },
    { set = "rn_giving_down" },
  }, other = {
    t("A heavy iron gate over a long stair down. A notice says it can only be drawn when the sump's been drained. The lake is lying on the far side of the walkway, watching."),
  } },
}

-- ---------------------------------------------------------------- the Hollow

local AFTER_TYAMET = {
  t("It takes a very long time, for something that big to stop. The great eye doesn't close. It only goes on being open, until there's nobody in it."),
  t("Then there's the crate. There's something small in it, and it's been looking at the Hollow One with such patience. Slowly, without moving at all, it turns its attention to you."),
  t("You've been looked at by Colette, and by a pleasant man at a dining table. This isn't the same. This is how you'd look at a house you grew up in."),
  owl("{hero}. Don't go any nearer. Doctor, the lid."),
  doc("One moment, friend. I've closed a great many things."),
  t("The doctor nails it shut with the heel of a boot and eleven old nails. It doesn't take long. It's only that nobody breathes."),
  { when = "rd_done", steps = {
    jez("Never leave me alone with that. Let's drop it down a very deep hole."),
  } },
  asp("Give it to me. I've signed for worse."),
  t("She carries it to the lip of the Hollow. On the lid, in a small upright hand, she writes one more line: NOT TO BE OPENED. She lets go. You listen for a while. You don't hear it land."),
  { fade = true },
  t("The top of the Spear comes down in the night, a little at a time. In the morning the whole of Ebrein is silent, and it's raining, and for once it's only rain."),
  warp("rn_antarith", "k", 1),
  asp("I haven't got a country. I've got a list, and I'm on the spring of the fourth. I'll stay with you, if you'll still have me."),
  { when = "rd_done", steps = {
    doc("That's the north and the deep, friend. There's only one way left to go, and we all know where. Mind you keep hold of that spoon."),
    owl("Something that patient won't have only one way in. We know what it's been growing, and where. I'd like to get there before it wakes."),
  }, other = {
    doc("That's the north, friend. There's still the deep, and I've people down there I'd like to see before the end. The Abyss, when you're ready."),
    owl("Something that patient won't have only one way in. I'd very much like to know what it thinks it knows about you."),
  } },
  t("Someone tugs your sleeve. She's holding out a chipped bowl. She's frowning, with her whole face, and she's nearly got it."),
  tam("Have you eaten?"),
  { choice = {
    { "Not yet.", {
      tam("Then sit down. You have to say it quite firmly. Sit down."),
    } },
    { "Yes, thank you.", {
      tam("You're a liar. Sit down."),
    } },
  } },
  t("You sit down. It's rice, and it's not very good. It's the best thing you've ever eaten."),
  { set = "rn_done" },
  { save = true },
  { big = "THE HOLLOW ONE IS EMPTY" },
}

S.rn_scene_tyamet = joined({
  { save = true },
  t("Below the Veins the stonework stops being built and starts being bone. You've been walking down the inside of a neck for some time. Nobody wants to be the one to say so."),
  t("Then the walls go away, and the dark in front of you has an eye in it, the size of a chapel."),
  t("One vast black head, and no neck behind it. No anything. Her jaw hangs open on a dark that goes down, and all the country you've seen is on its way into it, and there's nothing there to put it in."),
  t("At her lip stands a plain crate with the lid off, and near it one very good gold button. Everyone is looking at the head. You find you're looking at the crate. You have the strong, polite impression that it's looking back."),
  owl("She's starving. If she falls now, it has nothing to catch hold of. If she feeds once more, I shouldn't like to say what we'd be standing in front of."),
  { when = "rd_done", steps = {
    sis("There's no thread on her at all. She's the only thing I've ever seen that nothing's holding."),
  } },
  ask(doc("Well, friend, there's the patient. I've given some very bad news in my time. Do you want to tell her, or shall I?"), {
    { "I'll tell her.", {
      t("You walk out onto the lip of the rock. The eye comes round, and finds you, and you've never been looked at by anything so empty."),
      hero("We've eaten."),
    } },
    { "Don't tell her anything. Just hit her.", {
      doc("That's the bedside manner I've come to admire."),
    } },
  }),
  { big = "TYAMET THE HOLLOW ONE" },
  { battle = "rn_boss_tyamet" },
}, AFTER_TYAMET)

return R
