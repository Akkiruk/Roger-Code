-- games/blightmare/overworld.lua
-- SITE COORDINATES, for content and engine. Overworld x 1..120, y 1..80. An exit's world = { x, y } lands on the site's tile.
--   scythebreak      62, 60   (on the wall, western Heart)     map "scythebreak"
--   orrenshire       67, 44   (against the mountains)          map "orrenshire"
--   mine entrance    74, 41   (on the road past Orrenshire)    map "mine_1"
-- The one closed gate is at 80, 52, the Greywater bridge on the road east: its script is "gate_greywater".
--
-- The whole continent, one tile a character:
--   ~ sea   . grass   " tall grass   T forest   ^ mountain   = road   s swamp   W the pandemic wall   B bridge   O site
-- Ebrein is north-west, Shaid north-east, the walled Empire south-west and the Heart south-east, with the Empyreal Mountains
-- down the middle and Thuluan's freezing swamp across the top. The range stops short of the south coast, and the wall carries
-- on from its foot to the sea: Scythebreak sits in that gap. Only the country between the wall, the range and the Greywater
-- can be reached in this release. The other towns are drawn as places, but they aren't SITES yet.

local M = {}

M.W, M.H = 120, 80

M.ROWS = {
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~TTT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.TTTTTTTT~~~~~TTT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ss..TTTTTTTTTTTT..T..TTTTTT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~TT~sssssssTTTTTTTTTs.....T.sTTTTTs~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~sssssssssTTTTTTTT.......T.TTTTTTs~ss.~~~~TsT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~sssssss.TTTTTTs.........TTTTTTTT.TTTTTTTTTTTT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~sssss..TTTTssss.........TTTTTTTT..ssTTTTTTT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sss...TTssssTss........TTTT^^^^T.sssTTTTT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~......~Tsssssss..sss...T^^^^^^^^^TTTTT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~..~~~~~~sssssss.sss..T^^^^^^^^^^^^T^~~T~T~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sssssssssssss..s^^^^^^^^^^^^~~~TT....s~~~~~~~~~~~~~~~~~~~~~~ssssss~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sssssss~sssssss.s^^^^^^^^^^^~~^^^Ts..sssss~~~~~~~~~~~~~~~~ssssssssTTTT~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~T~~~~~~~~~ssssssss~sss.ss.s^^^^^^^^^^^^^^TTT...ssssss~~~~~~~~~~~~~ssssssssTTTTTTT~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~.TTTTTsss~~~~~sssssssss~ss~.sss^^^^^^^^^^^^^^^TTT...Tsssssss....~~~sssssssTsTTTTTTTTTT~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~"TTTTTTT...........TT.....~~~....T^^^^^^^^^^^^^^.T.""".........""""...........TTTTTTTTT.~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~."TTTTTTTT...........TTTT..........T^^^^^^^^^^^^^..TT."".T.......""""..........TTTTTTTTT...~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~."TTTTTTTTT............T...........T^T^^^^^^^^^^T...T."".T......."""".......""""TTTTTTTTTT..~~~~~~~~~~~',
  '~~~~~~~~~~~~~~"""."TTTTTTTTT...T....................^^^^^^^^^^^^^^^TTTT==============="....".""TT".TTTTTTTT...~~~~~~~~~~',
  '~~~~~~~~~~~~~~""""TTTTTTTTTTT.TTT.................."^^^^^^^^^^^^^^^.TTTTTT...........===....."TT""..TTTTTTTT....~~~~~~~~',
  '~~~~~~~~~~~...T""TTTTTTTTTTTTTTTTTT............"""".^^^^^^^^^^^^^^...TTTT........"""...====.TTTT"....TTTTTT.....~~~~~~~~',
  '~~~~~~~~~~....TTTTTTTTT.TTTTTTTTTTTT..........""""^^^^^^^^^^^^^^^^.TTTTTTT......."".......==TTT"T....TTTTTT......~~~~~~~',
  '~~~~~~~~~....TTTTTTTTT..TTTTTTTTTTTT.........."~~~~^^^^^^^^^^^^^^^.TTTTTT..................==.."......TTTTT......~~~~~~~',
  '~~~~~~~~.....TTTTTTTTTT.TTTTTTTTTTTT.........~~~""^^^^^^^^^^^^^^^.TTTTTTTT..................==.......TTTTTT..TT.T~~~~~~~',
  '~~~~~~~~.....TTTTTTTTTT..TTT=OBB~~~~~~~......~"""^^^^^^^^^^^^^^^.TTTTTTTTT..~~~~~~~~~~~~~..."===.....TTTTTTTTTTT~~~~~~~~',
  '~~~~~~~......TTTTTTTTTT..TT==~T===TT..~~....~~"""^^^^^^^^^^^^^^^^.TTTTTTTTT~~...........~......==B~~~~~~~TTTTTTT~~~~~~~~',
  '~~~~~~~......TTTTTTTT..TTT==~~TTT===...~~~~~~""""^^^^^^^^^^^^^^^^^..~~~~~~~~".".........~~~~~~~~~B==.TTT~~~~~.~~~~~~~~~~',
  '~~~~~~~....."TT.TTTT..T.T==T~TTTTT.===........""""^^^^^^^^^~~^^^^^^^..TTTT..""""...................===T~~~~~~~~~~~~~~~~~',
  '~~~~~~~TT."".......T...T==TT~TTTT....===.TTT....""^^^^^^^^^~~^^^^^...T....T."".......................==O~~~~~~~~~~~~~~~~',
  '~~~~~~~TTT"~~~~~~~~~~T.==.T.~.........T==TTT...."".^^^^^^^^~^^^^^^^........."".......................==T~~~~~~~~~....~~~',
  '~~~~~~~~~~~~TT......~BBB~~~~~.........TT====T...."""^^^^^^^^^^^^^^..........""....^......^..........==...~~~~~~~~...T.~~',
  '~~~~~~~~~TO===========TT..............TTTTT===.......T^^^^^^^^^^^..........^."...^^................==....~~~~~~~~....~~~',
  '~~~~~~~~~TTTTT.......TTTT............TTTTTT..===....TTT^^^^^^^^^^^.......^^^^....^^..........^.....=.....~~~~~~~~....~~~',
  '~~~~~~~~~~TTTT.......TTTT............TTTTT.....====OTT^^^^^^^^^^^^.^.....^^^^^^.^^^..^.....^^^.....=....~~~~~~~~~....~~~',
  '~~~~~~~~~~TTTT.......T..T............TTTTT....T.~~~~~~^^^^^^^^^^^^^^^..^^^^^^^^^^^^.^^^...........==..".~~~~~~~~~~..T~~~',
  '~~~~~~~~~~TTT....TTT......~~~~~~~~~~TTTTTTT..TT~~T..TT^^^^^^^^^^^^^^^^.^^^^^^^^^^^^""^^..........==......~~~~~~~~~..T.~~',
  '~~~~~~~~~TTTTTT.TTTT...~~~~........~~.TTTT....~~TTTT.^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"^^^.........==....."....~..~~~.~~~~~',
  '~~~~~~~~..TTTTTTTTTTT..~............~~~~~~~~~~~TTTTT.T^^^^^^^^^^^^^^^^^^^^^^^^^^~~^""^^^........=.....""........~~~~~~~~',
  '~~~~~~~.....~~~~~~~~~~~~.............."".."...TTTTTTTT^^^^^^^^^^^^^^^^^^^^^^^^^^~~^""...........=...."""".......~~~~~~~~',
  '~~~~~~.....~~TTTTTTTT.................""".""..TTTTTTTT^^^^^^^^^^^^^^^^^^^^^^^^^^~~^""......^^^..O==...""".....TT~~~~~~~~',
  '~~~~~~~...~~TTTTTTTTT.................""""""..TTTTTTTT^^^^^^^^^^^^^^^^^^^^^^^^^^~~TT.......^......==="....~~~~~~~~~~~~~~',
  '~~~~~~~.~~~.TTTTTTTT.................."""""".TTTTTTTTT^^^^^^^^^^^^^^^^^^^O...".^~~T........"........===..~~""".T.~~~~~~~',
  '~~~~~~..~...TTTTTTTT.................."""""".TTTTTTTTT^^^^^^^^^^^^^^^^^.==......~~.............T...~~~BBB=="""...~~~~~~~',
  '~~~~~~~WWWWWWWWWWWWW""......""...""""WWWWWWWWWWWWWWWWWW^^^^^^^^^^^^^sss==sss....~~..s...s......""..~......==.....~~~~~~~',
  '~~~~~~~.......T.T".WWWWWWWWWWWWWWWWWWW."""s"T.TTTTTTTT^^^^^^^^^^^^O...==.."""..~~~..s.ssssss~~~~~~~~.......=......~~~~~~',
  '~~~~~~~....".."""""""""T"."..=.ss"""s""..TTTTTTTTTTTT^^^^^^^^^^^^.==.==""""""""~~...ssssssss"""""""""""....=........~~~~',
  '~~~~~~~......"""".""""TTTTTTT=TTTTTTTT.TTTTTTTTTTTTTT^^^^^^^^^^^^..===""TTTT"""~~....ssss""""""""""""""""..=.......~~~~~',
  '~...~~~......"""""""TTTTTTTTT=TTTTTTTTTTTTTTTTTTTTTTTT^^^^^^^^^~T...=."""""""""~~T..sssss""""""""""""""""==O......~~~~~~',
  '~...~~~......"""""""TTTTTTTTT=TTTTTTTTTTTTTTTTTTTTTT^T^^^^^^^^^~....=."""""""""~~T...sss"""""""""""""""===.......~~~~~~~',
  '...~~~~......""""""TTTTTTTTTT=TTTTTTTTTTTTTTTTTTTTTT^^T^^^^^^^^~^...=..""""""""~~T...ss"""""""""""""""=="".......~~~~~~~',
  '...~~~~~...""""""""TTTTTTTTTT=TTTTTTTTTTTTTTTTT~~~~~~T^^^^^^^^^~~^..=======....~~....""""""""""""""""=="""".....~~~~~~~~',
  '~~.~~~~."".."""""""TTTTTTTTTT=TTTTTTTTTTTTTTT~~~TTTTTT^^^^WWW^^^~~..=.....==...~~~..""""""""""""""""=="""""""""~~~~~~~~~',
  '~~~.~~~~.""""".TT..TT"TTT...T=TTTTTTTTTTTTTTT~TTTTTTT^^^^^^^W^^^^~~~B~~~~~~=====BB==================="""""""""~~~~~~~~~~',
  '~~~~~~~~."""""TTT..."""""..TT=TTTTTTTTTTTTTT~~TTTTTTTT^^^^^^W^^^^^.==......~....~~~""""""""""==""""""""""""""~~~~~~~~~~~',
  '~~~~~~~~."""""TTTT.T"""sss..T=TTTTTTTTTTTTT~~TTTTTTTTTTTT^^^W^^^^^^=^......~....~~.""""""""""=""""""""""""""""~~~~~~~~~~',
  '~~~~~~~~.""""".TTTTT"""ss..TT=TTTTTTTTTTT~~~T.......TTTTTTTTW...TTT=...."..~~~~~~~"""""""""""=""""""""""""""""~~~~~~~~~~',
  '~~~~~~~..."T""..TTTT...ss..TT=TTTTTTTTTTT~TTT......"".TTTTTTW..TTTT=.."""""""".~~~"""""""""""="""""""""""""""""T~~~~~~~~',
  '~~~~~~~.......sTTTTT..ss...TTO==TTTTTTTT~~TTT........TTTTTTTW...TTT=."""""""""".~~"""""""""""="""""""""""""""""T~~~~~~~~',
  '~~~~~~~ss..sssTTTsTssss."..TT~~BBB~~~~~~~TTTT.......TTTTTTTTW......=."""""""""".~~"""""""""""=""""""""""""""""""~~~~~~~~',
  '~~~~~~~~ssssssTTsTsTsss""".TT~"""===TTT"TTTTT..."...TTTTTTTTW.....==."""""""""""~~~""""""""""="""""""""""""""""""~~~~~~~',
  '~~~~~~~~~ssssssssTTTTss"""TT"~"""""======="T...""....TTTTTT.WO=====."""""""""""".~~~"""""""""=""""""""""""""""""""~~~~~~',
  '~~~~~~~~~~ssssssssTTTTTTT.TT"~"""""""""""===.."......TTTTT..W........"""""""""....~~"""""""""="""""""""ssssss"""""~~~~~~',
  '~~~~~~~~~~~ssssssssTTTTTTTTT"~"""""""""""""===O""""...T...".W...TT....""""""".....~~~"""""""=="""""""sssssssssss"~~~~~~~',
  '~~~~~~~~~~~sssssssssTTTTTTT.~~""""""""""""""""""""""......".W.TTTTTT...............~~."""""=="""""""ssssssssssss~~~~~~~~',
  '~~~~~~~~~~~~ssssss.sTTTTTTT~~"..""""""""""""""""""""......".WTTTTTTTT.....TTTTT....~~..""""=""""""""ssssssssssss~~~~~~~~',
  '~~~~~~~~~~~~~ssss....TTTT~~~....""""""""""""""""""""."....s.WTTTTTTTTT..TTTTTTTT...~~s...."=""""""""sssssOsssss~~~~~~~~~',
  '~~~~~~~~~~~~~........TTTT~TT....."""""""".""""""""""""....sWWTTTTTTTTT..TTTTTTTT...~~s.....=""""""""sssssssssss~~~~~~~~~',
  '~~~~~~~~~~~~~~........TT~~TT.....""""""""""T""""""""......sWTTTTTTTTTT...TTTTTTT..~~~sTT...=."""""ssssssssssss~~~~~~~~~~',
  '~~~~~~~~~~~~~~........~~~....".""""""""""TTT"""""T"......."W.TTTTTTTTsssssTTTTT...~~.TTTT..=..".TT.sssssssssss~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~......~....ss.TTT""""""""""TsT"..T...sss.""W...TTTTTsssssssT....T.~~~TTTTT.=.....TTTsssssssss~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~......~"..sssTTTTT"""""""""s"s......ssss.""W.........sssss.......T.~~TTTTTT=T.....TTTTT.TT~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~.""~"s.sssT..."""""""""""........ssss.""W........~~.s...........~~TTTTTTOTT..T~~~TT~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~s~ssss..s...."""""""~~~".......s......W.....~~.~~~~...~....T..~~~TT~TTTT..T~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~ss......""""""""~~~~..............W..~~~~~~~~~~~~~~~~~~T..~~~~~~~TTsT~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~s....TTTT"".~~~~~~~~~~~~~....~~~~W~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sT~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~""TTTTTTT~~~~~~~~~~~~~~~~.~~~~~~W~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~TT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~...TT~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~T.T~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ss.............~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ssss..........s......~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ssss..........s..~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
}

--- Where the party comes out, and the square they arrive on when they go in. map and mx, my, dir match maps.DATA.
M.SITES = {
  { id = "scythebreak", x = 62, y = 60, map = "scythebreak", mx = 3, my = 3, dir = 1, name = "SCYTHEBREAK" },
  { id = "orrenshire", x = 67, y = 44, map = "orrenshire", mx = 3, my = 3, dir = 2, name = "ORRENSHIRE" },
  { id = "mine", x = 74, y = 41, map = "mine_1", mx = 3, my = 3, dir = 2, name = "ORRENSHIRE MINE" },
}

--- Closed roads. The tile looks like any other but stops the party, and bumping it runs the script.
M.GATES = {
  { x = 80, y = 52, script = "gate_greywater" },
}

M.REGION_NAME = { heart = "THE QYRRISSIAN HEART", road = "THE ORRENSHIRE ROAD" }

local WALKS = { ["."] = true, ['"'] = true, T = true, ["="] = true, s = true, B = true, O = true }
local ON_THE_ROAD = { ["="] = true, B = true, O = true }

function M.tileAt(x, y)
  local row = M.ROWS[y]
  if not row or x < 1 or x > M.W then return "~" end
  return row:sub(x, x)
end

function M.gateAt(x, y)
  for _, g in ipairs(M.GATES) do
    if g.x == x and g.y == y then return g end
  end
  return nil
end

function M.siteAt(x, y)
  for _, site in ipairs(M.SITES) do
    if site.x == x and site.y == y then return site end
  end
  return nil
end

function M.walkable(x, y) return WALKS[M.tileAt(x, y)] == true and not M.gateAt(x, y) end

local stretch

--- Every square the party can get to, found once. Keys are y * 1000 + x.
function M.stretch()
  if stretch then return stretch end
  stretch = {}
  local first = M.SITES[1]
  local todo = { first.x, first.y }
  while #todo > 0 do
    local y, x = table.remove(todo), table.remove(todo)
    local key = y * 1000 + x
    if not stretch[key] and M.walkable(x, y) then
      stretch[key] = true
      local n = #todo
      todo[n + 1], todo[n + 2], todo[n + 3], todo[n + 4] = x + 1, y, x - 1, y
      todo[n + 5], todo[n + 6], todo[n + 7], todo[n + 8] = x, y + 1, x, y - 1
    end
  end
  return stretch
end

--- Which random fights live here: "road" on the road itself, "heart" in the country round it, nil past the slice's edge.
function M.region(x, y)
  if not M.stretch()[y * 1000 + x] then return nil end
  return ON_THE_ROAD[M.tileAt(x, y)] and "road" or "heart"
end

return M
