-- games/blightmare/maps.lua
-- The first-person places of the slice. Rows are plain strings: # rock or town wall, . floor, + door, L locked door,
-- > stairs, h timber wall, W the great wall. Everything that moves the story lives in story.lua; a map only says where.
-- All a place knows about time is its when and unless flags, so one town can be morning, lockdown and night.
-- The rows themselves are safe for the author to edit: blightmare_content.test.lua walks every map and says what broke.

local M = {}

-- Where the exits land on the overworld. These match SITES in overworld.lua, and its mx, my of 3, 3 are each map's way in.
local SCYTHEBREAK_SITE = { 62, 60 }
local ORRENSHIRE_SITE = { 67, 44 }
local MINE_SITE = { 74, 41 }

M.DATA = {}

-- The wall fills the west end of every east-west street. Nan's house is top left, the Clinic house top right, the square in
-- the middle, and Gate Street runs east to the only way out.
M.DATA.scythebreak = {
  name = "SCYTHEBREAK", theme = "town", savepoint = true,
  rows = {
    "WW########L##############",
    "WW.....h.....h.....h...h#",
    "WW.....h.....h.....h...h#",
    "WW.....h.....hhh+hhhh+hh#",
    "WWhh+hhh.....h.........h#",
    "WW...........h.........h#",
    "WW...........h.........h#",
    "WWhhhhhh.....hh+hhhhhhhh#",
    "WW....hh........hhhhhhhh#",
    "WW....hh........hhhhhhhh#",
    "WW......................#",
    "WW....hh........hhhhhhhh#",
    "WW....hh........hhhhhhhh#",
    "WWhhhhhhh...hhhhhhhhhhhh#",
    "WW.....................h#",
    "WWhh+hhhhh+hhhhh+hhhhhhh#",
    "WW.....h.....h.....hhhhh#",
    "WW.....h.....h.....hhhhh#",
    "#########################",
  },
  npcs = {
    -- morning
    { id = "nan", x = 5, y = 3, sprite = "villager", script = "talk_nan", unless = "horn" },
    { id = "wick", x = 7, y = 7, sprite = "villager", script = "talk_wick", unless = "horn" },
    { id = "kid", x = 11, y = 3, sprite = "child", script = "talk_kid", unless = "horn" },
    { id = "clerk", x = 12, y = 10, sprite = "villager", script = "talk_clerk", unless = "horn" },
    { id = "widow", x = 4, y = 17, sprite = "villager", script = "talk_widow", unless = "tested" },
    { id = "watch", x = 4, y = 11, sprite = "soldier", script = "talk_watch", unless = "lockdown" },
    { id = "doorman", x = 16, y = 9, sprite = "guard", script = "talk_doorman", unless = "horn" },
    { id = "gateman", x = 22, y = 11, sprite = "orderly", script = "talk_gateman", unless = "gate_won" },
    { id = "lioth", x = 10, y = 17, sprite = "villager", script = "talk_lioth", unless = "horn" },
    { id = "satchel", x = 15, y = 12, sprite = "guard", script = "talk_satchel", unless = "horn" },
    -- what's left of Wick
    { id = "wick_changed", x = 9, y = 11, sprite = "blighted", script = "scene_wick", when = "breach", unless = "wick_down" },
    -- the queue for the draught
    { id = "q_kid", x = 13, y = 9, sprite = "child", script = "talk_q_kid", when = "lockdown", unless = "tested" },
    { id = "q_clerk", x = 14, y = 9, sprite = "villager", script = "talk_q_clerk", when = "lockdown", unless = "tested" },
    { id = "q_nan", x = 15, y = 9, sprite = "villager", script = "talk_q_nan", when = "lockdown", unless = "tested" },
    { id = "q_lioth", x = 12, y = 9, sprite = "villager", script = "talk_lioth", when = "lockdown", unless = "tested" },
    { id = "q_satchel", x = 15, y = 13, sprite = "guard", script = "talk_satchel", when = "lockdown", unless = "tested" },
    { id = "chalker", x = 8, y = 15, sprite = "orderly", script = "talk_chalker", when = "lockdown", unless = "tested" },
    -- the ward, that night
    { id = "w_nan", x = 19, y = 7, sprite = "shroud", script = "ward_nan", when = "tested" },
    { id = "w_kid", x = 17, y = 5, sprite = "shroud", script = "ward_kid", when = "tested" },
    { id = "w_clerk", x = 20, y = 5, sprite = "shroud", script = "ward_clerk", when = "tested" },
    { id = "w_watch", x = 15, y = 7, sprite = "shroud", script = "ward_watch", when = "tested" },
    { id = "w_bed", x = 22, y = 7, sprite = "shroud", script = "ward_bed", when = "tested" },
    { id = "w_lioth", x = 23, y = 5, sprite = "shroud", script = "talk_lioth", when = "tested" },
    -- the counting goes on, at midnight, in an empty square
    { id = "n_satchel", x = 13, y = 12, sprite = "guard", script = "talk_satchel", when = "tested", unless = "left_town" },
  },
  steps = {
    { x = 3, y = 3, script = "turned_back", when = "left_town" }, -- walking back in from the overworld lands here
    { x = 5, y = 4, script = "turned_back", when = "left_town" },
    { x = 22, y = 11, script = "turned_back", when = "left_town" }, -- a wipe on the road comes to just outside the gate
    { x = 7, y = 11, script = "scene_wick", when = "breach", unless = "wick_down" },
    { x = 16, y = 7, script = "scene_test", when = "lockdown", unless = "tested" },
    { x = 16, y = 9, script = "scene_night_street", when = "escaped", unless = "night_seen" },
    { x = 21, y = 11, script = "scene_gate", when = "escaped", unless = "gate_won" },
  },
  chests = {
    { id = "c1", x = 9, y = 2, give = "potion", n = 1 },
    { id = "c2", x = 13, y = 18, give = "antidote", n = 2 },
    { id = "c3", x = 19, y = 18, gold = 30 },
  },
  exits = {
    { x = 24, y = 11, world = SCYTHEBREAK_SITE },
  },
}

-- A town at the foot of the mountain, all of it slightly too small. The road comes in along the top row. The inn and the
-- smith are off it, the lane down the middle leads to the square, and the mayor's hall is on the square's east side.
M.DATA.orrenshire = {
  name = "ORRENSHIRE", theme = "town", savepoint = true,
  rows = {
    "#######################",
    "#hhhhhhhhhhhhhhhhhhhhh#",
    "#.....................#",
    "#hhhh+hhhh...hhhh+hhhh#",
    "#h.......h...h.......h#",
    "#h.......h...h.......h#",
    "#h.......h...h.......h#",
    "#hhhhhhhhh...hhhhhhhhh#",
    "#.....................#",
    "#.hhhh+hh.....hh+hhhh.#",
    "#.h.....h.....h.....h.#",
    "#.h.....h.....h.....h.#",
    "#.hhhhhhh.....hhhhhhh.#",
    "#.....................#",
    "#hhh+hhhhhh+hhhhhh+hhh#",
    "#h.....h......h......h#",
    "#h.....h......h......h#",
    "#######################",
  },
  npcs = {
    { id = "innkeeper", x = 6, y = 6, sprite = "innkeeper", script = "talk_innkeeper" },
    { id = "smith", x = 18, y = 6, sprite = "smith", script = "talk_smith" },
    { id = "mayor", x = 18, y = 12, sprite = "mayor", script = "talk_mayor" },
    { id = "chair", x = 6, y = 12, sprite = "gnome", script = "talk_chair" },
    { id = "ledger", x = 10, y = 10, sprite = "gnome", script = "talk_ledger" },
    { id = "well", x = 13, y = 12, sprite = "gnome", script = "talk_well" },
    { id = "frog", x = 11, y = 11, sprite = "frogman", script = "talk_frog", unless = "foreman_down" },
    { id = "stocks", x = 11, y = 11, sprite = "gnome", script = "talk_stocks", when = "foreman_down" },
    { id = "pip", x = 4, y = 17, sprite = "child", script = "talk_pip" },
    { id = "hatter", x = 14, y = 10, sprite = "gnome", script = "talk_hatter" },
    { id = "silt", x = 12, y = 13, sprite = "frogman", script = "talk_silt" },
    { id = "bascombe", x = 12, y = 17, sprite = "guard", script = "talk_bascombe" }, -- his own office: never in the Mayor's hall, where she says what she says
    { id = "dunnock_up", x = 12, y = 11, sprite = "miner", script = "talk_dunnock_up", when = "freed_dunnock" },
  },
  steps = {
    { x = 3, y = 3, script = "scene_orrenshire", unless = "arrived" },
  },
  chests = {
    { id = "c1", x = 16, y = 17, give = "tonic", n = 1 },
    { id = "c2", x = 3, y = 5, give = "ether", n = 1 },
  },
  exits = {
    { x = 2, y = 3, world = ORRENSHIRE_SITE },
    { x = 22, y = 3, world = ORRENSHIRE_SITE },
  },
}

-- The way in is the top left. Everything runs through the side gallery where the sister has laid out the sick, and past it
-- a long gallery splits to the lift, the stairs and two pockets of old workings.
M.DATA.mine_1 = {
  name = "ORRENSHIRE MINE: FIRST LEVEL", theme = "mine",
  rows = {
    "#####################",
    "########h.....h######",
    "#.......+.....+.....#",
    "########h.....h####.#",
    "########h.....h####.#",
    "########hhh+hhh####.#",
    "#...................#",
    "#.###.#####.#####.#.#",
    "#.###.#####.#####.###",
    "#.....#####.##.....##",
    "###.#######.###.#####",
    "###.#######.###.#####",
    "#.....#####.#...#####",
    "#.....#####.#...#####",
    "###########>#########",
    "#####################",
  },
  npcs = {
    { id = "warden", x = 5, y = 3, sprite = "miner", script = "talk_warden", unless = "warden_ok" },
    { id = "nurse", x = 13, y = 5, sprite = "gnome", script = "talk_nurse", when = "cleric_in" },
    { id = "sick1", x = 11, y = 2, sprite = "shroud", script = "talk_sick" },
    { id = "sick2", x = 13, y = 2, sprite = "shroud", script = "talk_sick" },
    { id = "sick3", x = 14, y = 4, sprite = "shroud", script = "talk_sick" },
    { id = "nib", x = 15, y = 14, sprite = "gnome", script = "talk_nib" },
    { id = "propsetter", x = 4, y = 14, sprite = "miner", script = "talk_propsetter" },
  },
  steps = {
    { x = 10, y = 3, script = "scene_cleric", unless = "cleric_in" },
  },
  chests = {
    { id = "c1", x = 2, y = 14, give = "potion", n = 2 },
    { id = "c2", x = 20, y = 8, gold = 60 },
    { id = "c3", x = 6, y = 14, give = "antidote", n = 2 },
    { id = "c4", x = 14, y = 14, give = "shortsword" },
  },
  foes = {
    { id = "f1", x = 4, y = 10, enc = "mine_1", sprite = "crawler" },
    { id = "f2", x = 12, y = 9, enc = "mine_1", sprite = "rat" },
    { id = "f3", x = 17, y = 10, enc = "mine_1", sprite = "crawler" },
    { id = "f4", x = 18, y = 3, enc = "mine_1", sprite = "rat" },
  },
  exits = {
    { x = 2, y = 3, world = MINE_SITE },
    { x = 12, y = 15, map = "mine_2", mx = 3, my = 2, dir = 2 },
  },
}

-- The long drift is column 11, straight down from the top gallery. The sweetdamp fills it, the valve wheel is at its far end,
-- and the way round to the stairs is only open past the wheel.
M.DATA.mine_2 = {
  name = "ORRENSHIRE MINE: SECOND LEVEL", theme = "mine",
  rows = {
    "#####################",
    "#>.........##......>#",
    "##.###.###.##.####.##",
    "##.###.###.##.####.##",
    "##.......#.##.####.##",
    "##.###.###.##.####.##",
    "##.###.###.##.####.##",
    "##.....###.##.####.##",
    "####.#####.##.####.##",
    "##.....###.##.####.##",
    "##.....###.##......##",
    "##########.##.#######",
    "##########.##.#######",
    "##########....#######",
    "#####################",
  },
  npcs = {
    { id = "logkeeper", x = 3, y = 3, sprite = "gnome", script = "talk_logkeeper" },
    { id = "valve", x = 11, y = 12, sprite = "shroud", script = "scene_valve", unless = "gas_off" },
    { id = "dunnock", x = 3, y = 8, sprite = "miner", script = "talk_dunnock", unless = "freed_dunnock" },
    { id = "handler_big", x = 17, y = 11, sprite = "orderly", script = "talk_handlers", unless = "handlers_gone" },
    { id = "handler_small", x = 15, y = 11, sprite = "orderly", script = "talk_handlers", unless = "handlers_gone" },
  },
  steps = {
    { x = 11, y = 3, script = "scene_gas", unless = "gas_off" },
    { x = 11, y = 8, script = "scene_gas_mid", when = "gas_met", unless = "gas_mid" },
  },
  chests = {
    { id = "c1", x = 3, y = 10, give = "potion", n = 2 },
    { id = "c2", x = 7, y = 10, give = "leathers" },
    { id = "c3", x = 9, y = 5, gold = 80 },
    { id = "c4", x = 16, y = 11, give = "ether", n = 1 },
  },
  foes = {
    { id = "f1", x = 5, y = 5, enc = "mine_2", sprite = "blighted" },
    { id = "f2", x = 5, y = 10, enc = "mine_1", sprite = "crawler" },
    { id = "f3", x = 16, y = 2, enc = "mine_2", sprite = "blighted" },
    { id = "f4", x = 19, y = 7, enc = "mine_2", sprite = "blighted" },
    { id = "f5", x = 14, y = 6, enc = "mine_3", sprite = "miner" },
  },
  exits = {
    { x = 2, y = 2, map = "mine_1", mx = 12, my = 14, dir = 1 },
    { x = 20, y = 2, map = "mine_3", mx = 3, my = 2, dir = 2 },
  },
}

-- Down the stairs, along to the hall where the deep shift lies, through it, and round to the Foreman's gallery. The lift
-- cage is off on its own at the bottom left: it's the shortcut back up once its brake is off.
M.DATA.mine_3 = {
  name = "ORRENSHIRE MINE: THE DEEP SEAM", theme = "mine",
  rows = {
    "#####################",
    "#>......#############",
    "###.###.#############",
    "###.###.#############",
    "#.........###########",
    "#.#######+###########",
    "#.###h........h######",
    "#.###h........h######",
    "#.###h........+.....#",
    "#.###h........h####.#",
    "#.###h........h####.#",
    "#.###hhhhhhhhhh###..#",
    "#...####............#",
    "#...####...##########",
    "#####################",
  },
  npcs = {
    { id = "nob", x = 3, y = 13, sprite = "gnome", script = "talk_nob" },
    { id = "foreman", x = 11, y = 13, sprite = "foreman", script = "scene_foreman", unless = "foreman_down" },
    { id = "sleeper1", x = 8, y = 8, sprite = "shroud", script = "talk_sleeper", unless = "foreman_down" },
    { id = "sleeper2", x = 12, y = 8, sprite = "shroud", script = "talk_sleeper", unless = "foreman_down" },
    { id = "sleeper3", x = 8, y = 10, sprite = "shroud", script = "talk_sleeper", unless = "foreman_down" },
    { id = "sleeper4", x = 10, y = 11, sprite = "shroud", script = "talk_sleeper", unless = "foreman_down" },
    { id = "lampwoman", x = 12, y = 10, sprite = "shroud", script = "talk_lampwoman", unless = "foreman_down" },
  },
  steps = {
    { x = 10, y = 7, script = "scene_deep_shift", once = true },
    { x = 20, y = 11, script = "scene_last_lamp", unless = "foreman_down" },
    { x = 13, y = 13, script = "scene_foreman", unless = "foreman_down" },
  },
  chests = {
    { id = "c1", x = 4, y = 13, give = "tonic", n = 2 },
    { id = "c2", x = 14, y = 11, give = "miners_pick" },
    { id = "c3", x = 19, y = 12, give = "potion", n = 3 },
  },
  foes = {
    { id = "f1", x = 4, y = 3, enc = "mine_2", sprite = "blighted" },
    { id = "f2", x = 6, y = 5, enc = "mine_3", sprite = "miner" },
    { id = "f3", x = 2, y = 9, enc = "mine_3", sprite = "miner" },
    { id = "f4", x = 13, y = 9, enc = "mine_4", sprite = "miner" },
    { id = "f5", x = 18, y = 9, enc = "mine_4", sprite = "blighted" },
    { id = "f6", x = 17, y = 13, enc = "mine_4", sprite = "miner" },
  },
  exits = {
    { x = 2, y = 2, map = "mine_2", mx = 19, my = 2, dir = 4 },
  },
}

for _, region in ipairs(require("games.blightmare.content").regions()) do
  for id, map in pairs(region.maps or {}) do M.DATA[id] = map end
end

return M
