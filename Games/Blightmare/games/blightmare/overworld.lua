-- games/blightmare/overworld.lua
-- The whole continent, one tile a character, and what the story has opened of it. Overworld x 1..120, y 1..80. An exit's
-- world = { x, y } lands on a site's tile.
--
--   ~ sea   . grass   " tall grass   T forest   ^ mountain   = road   s swamp   W the pandemic wall   B bridge   O site
--   and after the world breaks:  x blighted ground   X blight spire (solid)   t dead forest   a ash flats
--
-- Ebrein is north-west, Shaid north-east, the walled Empire south-west and the Heart south-east, with the Empyreal Mountains
-- down the middle and Thuluan's freezing swamp across the top. The range stops short of the south coast, and the wall carries
-- on from its foot to the sea: Scythebreak sits in that gap.
--
-- The order the land opens in: the slice's stretch west of the Greywater; over the Greywater bridge to Hayford, Oplinas and
-- Glamouth; the one road through the ridge into the heart of the Verdant Sea, and the windmill; over the Nevermore Portal to
-- Blackpool and Shaid; out of Murkwell by the Cavity Crevice route into Ebrein; over the strait to Thuluan; through the wall by
-- the crack, a dungeon, which is the only way to the Empire's side; and up the valley to the Violet Abyss.
--
-- Everything that hangs on the story takes s as its last argument. No s means the slice: no flags, not ruined.

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
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sss...TTssssTssO.......TTTT^^^^T.sssTTTTT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~......~Tsss=====.sss...T^^^^^^^^^TTTTT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~..~~~~~~ss=ssss.sss..T^^^^^^^^^^^^T^~~T~T~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ssss=ssssssss..s^^^^^^^^^^^^~~~TT....s~~~~~~~~~~~~~~~~~~~~~~ssssss~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sssss=s~sssssss.s^^^^^^^^^^^~~^^^Ts..sssss~~~~~~~~~~~~~~~~ssssssssTTTT~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~T~~~~~~~~~~~~~~B~~~~~~~~~~~^^^^^^^^^^^^^^TTT...ssssss~~~~~~~~~~~~~ssssssssTTTTTTT~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~.TTTTTsss~~~~~~~~~~B~~~~~~~~~~~^^^^^^^^^^^^^^^TTT...Tsssssss....~~~sssssssTsTTTTTTTTTT~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~"TTTTTTT...........TT=....~~~....T^^^^^^^^^^^^^^.T.""".........""""...........TTTTTTTTT.~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~."TTTTTTTT.=============T..........T^^^^^^^^^^^^^..TT."".T.......""""..........TTTTTTTTT...~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~."TTTTTTTTT=...........T...........T^T^^^^^^^^^^T...T."".T......."""".......""""TTTTTTTTTT..~~~~~~~~~~~',
  '~~~~~~~~~~~~~~"""."TTTTTTTTT=..T....................^^^^^^^^^^^^^^^TTTT==============="....".""TT".TTTTTTTT...~~~~~~~~~~',
  '~~~~~~~~~~~~~~""""TTTTTTTTTT=.TTT.................."^^^^^^^^^^^^^^^.TTTTTT...........===....."TT""..TTTTTTTT....~~~~~~~~',
  '~~~~~~~~~~~...T""TTTTTTTTTTT=TTTTTT............"""".^^^^^^^^^^^^^^...TTTT........"""...====.TTTT"....TTTTTT.....~~~~~~~~',
  '~~~~~~~~~~....TTTTTTTTT.TTTT=TTTTTTT..........""""^^^^^^^^^^^^^^^^.TTTTTTT......."".......==TTT"T....TTTTTT......~~~~~~~',
  '~~~~~~~~~....TTTTTTTTT..TTTT=TTTTTTT.........."~~~~^^^^^^^^^^^^^^^.TTTTTT..................==.."......TTTTT......~~~~~~~',
  '~~~~~~~~.....TTTTTTTTTT.TTTT=TTTTTTT.........~~~""^^^^^^^^^^^^^^^.TTTTTTTT..................==.......TTTTTT..TT.T~~~~~~~',
  '~~~~~~~~.....TTTTTTTTTT..TTT=OBB~~~~~~~......~"""^^^^^^^^^^^^^^^.TTTTTTTTT..~~~~~~~~~~~~~..."===.....TTTTTTTTTTT~~~~~~~~',
  '~~~~~~~......TTTTTTTTTT..TT==~T===TT..~~....~~"""^^^^^^^^^^^^^^^^.TTTTTTTTT~~...........~......==B~~~~~~~TTTTTTT~~~~~~~~',
  '~~~~~~~......TTTTTTTT..TTT==~~TTT===...~~~~~~""""^^^^^^^^^....^^^^..~~~~~~~~"."......O..~~~~~~~~~B==.TTT~~~~~.~~~~~~~~~~',
  '~~~~~~~....."TT.TTTT..T.T==T~TTTTT.===........""""^^^^^^^..O========..TTTT.."""".....=.............===T~~~~~~~~~~~~~~~~~',
  '~~~~~~~TT."".......T...T==TT~TTTT..O.===.TTT....""^^^^^^^^.~~.^^^^.=.T....T."".......=...............==O~~~~~~~~~~~~~~~~',
  '~~~~~~~TTT"~~~~~~~~~~T.==.T.~.........T==TTT...."".^^^^^^^^~^^^^^^^=........"".......=...............==T~~~~~~~~~....~~~',
  '~~~~~~~~~~~~TT......~BBB~~~~~.........TT====T...."""^^^^^^^^^^^^^^=====O==============================...~~~~~~~~...T.~~',
  '~~~~~~~~~TO===========TT..............TTTTT===.......T^^^^^^^^^^^.=........^."...^^................==....~~~~~~~~....~~~',
  '~~~~~~~~~TTTTT.....=.TTTT............TTTTTT..===...^^^^^^^^^^^^^^^=......^^^^....^^..........^.....=.....~~~~~~~~....~~~',
  '~~~~~~~~~~TTTT.....=.TTTT............TTTTT.....====O===============^.....^^^^^^.^^^..^.....^^^.....=....~~~~~~~~~....~~~',
  '~~~~~~~~~~TTTT.....=.T..T............TTTTT....T.~~~~~~^^^^^^^^^^^^^^^..^^^^^^^^^^^^.^^^...........==..".~~~~~~~~~~..T~~~',
  '~~~~~~~~~~TTT....TT=......~~~~~~~~~~TTTTTTT..TT~~T..TT^^^^^^^^^^^^^^^^.^^^^^^^^^^^^""^^..........==......~~~~~~~~~..T.~~',
  '~~~~~~~~~TTTTTT.TTT=...~~~~........~~.TTTT....~~TTTT.^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"^^^.........==....."....~..~~~.~~~~~',
  '~~~~~~~~..TTTTTTTTT=T..~............~~~~~~~~~~~TTTTT.T^^^^^^^^^^^^^^^^^^^^^^^^^^~~^""^^^........=.....""........~~~~~~~~',
  '~~~~~~~.....~~~~~~~O~~~~.............."".."...TTTTTTTT^^^^^^^^^^^^^^^^^^^^^^^^^^~~^""...........=...."""".......~~~~~~~~',
  '~~~~~~.....~~TTTTTTTT.................""".""..TTTTTTTT^^^^^^^^^^^^^^^^^^^^^^^^^^~~^""......^^^..O==...""".....TT~~~~~~~~',
  '~~~~~~~...~~TTTTTTTTT.................""""""..TTTTTTTT^^^^^^^^^^^^^^^^^^^^^^^^^^~~TT.......^......==="....~~~~~~~~~~~~~~',
  '~~~~~~~.~~~.TTTTTTTT.................."""""".TTTTTTTTT^^^^^^^^^^^^^^^^^^^O...".^~~T........"........=====~~""".T.~~~~~~~',
  '~~~~~~..~...TTTTTTTT.................."""""".TTTTTTTTT^^^^^^^^^^^^^^^^^.==......~~.............T...~~~~~B~~"""...~~~~~~~',
  '~~~~~~~WWWWWWWWWWWWW""......""...""""WWWWWWWWWWWWWWWWWW^^^^^^^^^^^^^sss==sss....~~..s...s......""..~....====.....~~~~~~~',
  '~~~~~~~.......T.T".WWWWWWWWWWWWWWWWWWW."""s"T.TTTTTTTT^^^^^^^^^^^^O...==.."""..~~~~~~~~~~~~~~~~~~~~~.......=......~~~~~~',
  '~~~~~~~....".."""""""""T"."..=.ss"""s""..TTTTTTTTTTTT^^^^^^^^^^^^.==.==""""""""~~...ssssssss"""""""""""....=........~~~~',
  '~~~~~~~......"""".""""TTTTTTT=TTTTTTTT.TTTTTTTTTTTTTT^^^^^^^^^^^^..===""TTTT"""~~....ssss""""""""""""""""..=.......~~~~~',
  '~...~~~......"""""""TTTTTTTTT=TTTTTTTTTTTTTTTTTTTTTTTT^^^^^^^^^~T...=."""""""""~~T..sssss""""""""""""""""==O......~~~~~~',
  '~...~~~......"""""""TTTTTTTTT=TTTTTTTTTTTTTTTTTTTTTT^T^^^^^^^^^~....=."""""""""~~T...sss"""""""""""""""===.......~~~~~~~',
  '...~~~~......""""""TTTTTTTTTT=TTTTTTTTTTTTTTTTTTTTTT^^T^^^^^^^^~^...=..""""""""~~T...ss"""""""""""""""=="".......~~~~~~~',
  '...~~~~~...""""""""TTTTTTTTTT=TTTTTTTTTTTTTTTTT~~~~~~T^^^^^^^^^~~^..=======....~~....""""""""""""""""=="""".....~~~~~~~~',
  '~~.~~~~."".."""""""TTTTTTTTTT=TTTTTTTTTTTTTTT~~~TTTTTT^^^^WWW^^^~~..=.....==...~~~..""""""""""""""""=="""""""""~~~~~~~~~',
  '~~~.~~~~.""""".TT..TT"TTT...T=TTTTTTTTTTTTTTT~TTTTTTT^^^^^^^W^^^^~~~B~~~~~~=====BB==================="""""""""~~~~~~~~~~',
  '~~~~~~~~."""""TTT..."""""..TT=TTTTTTTTTTTTTT~~TTTTTTTT^^^^^^W^^^^^.==......~....~~~""""""""""==""""="""""""""~~~~~~~~~~~',
  '~~~~~~~~."""""TTTT.T"""sss..T=TTTTTTTTTTTTT~~TTTTTTTTTTTT^^^W^^^^^^=^......~....~~.""""""""""="""^^=^^^^"""^^^^^~~~~~~~~',
  '~~~~~~~~.""""".TTTTT"""ss..TT=TTTTTTTTTTT~~~T.......TTTTTTTTW...TTT=...."..~~~~~~~"""""""""""="^^^"="""^^^^^""~~~~~~~~~~',
  '~~~~~~~..."T""..TTTT...ss..TT=TTTTTTTTTTT~TTT......"".TTTTTTW..TTTT=.."""""""".~~~"""""""""""=^^"""="""""""""""T~~~~~~~~',
  '~~~~~~~.......sTTTTT..ss...TTO==TTTTTTTT~~TTT........TTTTTTTW...TTT=."""""""""".~~"""""""""""=^""""="""""""""""T~~~~~~~~',
  '~~~~~~~ss..sssTTTsTssss."..TT~~BBB~~~~~~~TTTT.......TTTTTTTTW......=."""""""""".~~"""""""""""=^""""=""""""""""""~~~~~~~~',
  '~~~~~~~~ssssssTTsTsTsss""".TT~"""===TTT"TTTTT..."...TTTTTTTTW.....==."""""""""""~~~""""""""""=^""""="""""""""""""~~~~~~~',
  '~~~~~~~~~ssssssssTTTTss"""TT"~"""""======="T...""....TTTTTT.WO=====."""""""""""".~~~"""""""""=^O====""""""""""""""~~~~~~',
  '~~~~~~~~~~ssssssssTTTTTTT.TT"~"""""""""""===.."......TTTTT..W.=......"""""""""....~~"""""""""=^""""""""ssssss"""""~~~~~~',
  '~~~~~~~~~~~ssssssssTTTTTTTTT"~"""""""""""""===O=========..".W.=.TT....""""""".....~~~"""""""==^""^^^^^^sssssssss"~~~~~~~',
  '~~~~~~~~~~~sssssssssTTTTTTT.~~""""""""""""""""""""""...=..".W.=TTTTT...............~~."""""=="^^^^""ss^^^^^^^^^^^~~~~~~~',
  '~~~~~~~~~~~~ssssss.sTTTTTTT~~"..""""""""""""""""""""...=..".WT=TTTTTT.....TTTTT....~~..""""=""""""""ssssssssssss~~~~~~~~',
  '~~~~~~~~~~~~~ssss....TTTT~~~...."""""""""""""""""""".".=..s.WT=TTTTTTT..TTTTTTTT...~~s....===============Osssss~~~~~~~~~',
  '~~~~~~~~~~~~~........TTTT~TT.....""""""""."""""""""""".=..sWWT=TTTTTTT..TTTTTTTT...~~s.....=""""""""sssssssssss~~~~~~~~~',
  '~~~~~~~~~~~~~~........TT~~TT.....""""""""""T""""""""...=O.sWTO=TTTTTTT...TTTTTTT..~~~sTT...=."""""ssssssssssss~~~~~~~~~~',
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

--- The same continent after the Vault: the wall down in stretches, the coast moved, the Verdant Sea burned to ash, and blight
--- round the Abyss and along the wall. Every site is on its old tile, and all of it can be walked.
M.ROWS_RUINED = {
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.ttt~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ss..ttttt~~~~~~~~~~~.tttttt~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sssssstttttTTTxxxx~~~T.sttttts~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sssssstttttTXxxxxxx.xt.tttttt~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~ssssss.tttttxxxxxxxxxx.tttttt~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ssss..ttttxxxxxxxxxx..xtttttt~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sssa..ttsxxxxxxOxxxxXaatttt^^^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~aaa...atxxx=xxxxxxxxxxat^^^^^^^^^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~aaaaa~xx=xxxxxxxxxat^^^^^^^^^^^^~^~~t~t~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~aaaa~~~x=xxxxxxxxxxs^^^^^^^^^^^^~~~tt..xx~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~aaa~~~~~xxx~xxxxxxxas^^^^^^^^^^^~~^^^Txxxx~~~~~~aaaaaaa~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~t~~~~~~aaaaaa~aaa~~~~~aaa~~^^^^^^^^^^^^^^xxxxxxxx~~~~~~aaaaaa~~~~~~~~~~~~~~~~~~~Ta~a~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~ttttssx~~aaaaaaaaaa~~~~~aaa~~^^^^^^^^^^X^^^^xxxxxxXx~~~~~~~xxx~~~xxxxsssTsTTTTTTTTTTaaa~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~tttt.x.xxxxxxxx~~=~~~~~~~xxx.t^^^^^^X^^^^X^^xXxxxxxxxxxxxxxx~xxxxxxxxx.aaaTTTTTTTTTaaaa~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~tttt.=======x=====~~~~xxxxxxxt^^^^^^^^^^^^^xxxxxxxxxxxxxxXXx~xxxxxxxxx.aaTTTTTTTTT..aa~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~Ttttttt=xxxxxxXxxx~x~~~~~xxxxxxt^~^^^^^^XX^^xxxxxxxxxxxxxxxxxxxxxxxxxxx.....TTTTTTTTTT..~~~~~~~~~~~',
  '~~~~~~~~~aaaaa""~~~TTTTttttt=xxxxxxxxxXXxxxxx~xxxxxx^^^^^^^X^^^X^^^xxxxxxx============xxxxxx...TT".TTTTTTTT..~~~~~~~~~~~',
  '~~~~~~~~~aaaaa""~~tttTTTTTTT=.TTxxxxxxxxxxxxxxxXxxxx^^^^^^^^X^^X^^Xxxxxxxtxx.xxXxxxxx=xxxxXxx.TT""..TTTTTTTT..~~~~~~~~~~',
  '~~~~~~~~~~a.x.t"~ttttTTTTTTT=TTTTTxxxxxxxxxxxxxxxxxx^^^^^^^^^^^^X^xxxxtttaaxx.x.xxxxxxxxxxxaTTTT"....TTTTTT.....~~~~~~~~',
  '~~~~~~~~~~xxx.tttttttTT.TTTT=TTTTTtxxx~xxxxXxxxxxx^^^^^^^^^^^^^^^^xtttttttaa....x"".xxxxxxxxTTT"T....TTTTTT......~~~~~~~',
  '~~~~~~~~~..xxttttttttT..TTTT=TTTTttt~~~~xXx~xxx~~~~^^^^^^^^^^^^^^^.ttttttaaaaa...x...xxxxaxxxxx"x.~~~~~~~TT......~~~~~~~',
  '~~~~~aa~xxxx.tttttttttT.TTTT=aaaa~~~~~~~~~~xx~~~xx^^^^^^^^^^^^^^^xttttttttaa~aaaaaxx.xxxxxaax=x.~~~~~~~~~~TaaTTaT~~~~~~~',
  '~~~~~aa~xxxx.tttttttttT..TTT=Oaaa~aaaa~~~~~xx~xxxXX^^^^^^^^^^^^^.TT~TTTTT~~~~~~~~~~~~aaaaxaa.===aaa~~~~~~~TTTTTT~~~~~~~~',
  '~~~~~aaxxxxx.tttttttttt..TT==aaaaxttxx~~~~~x~~xxx^^X^^^^^^^^^^^^^x~TTTTTTT~~~aaaaaxx.xx.a.xxx.x=aaa~~~~~~TTTTTTT~~~~~~~~',
  '~~~~~aax..x.xtttttt~~..tT~==~aaaaaxxxxx~~~~~~xxxxX^^^^^^^^xxxx^^^~~xaaaaaa~~.a.aaaxaaOxxaaaaaaaaaaa=.ttt~~~aa.~~~~~~~~~~',
  '~~~~~aa.x..x"ttatttta.t.~==T~tttttaaxxxxxxxxxxxxxx^^^^^^^xxOx=======.xTTTTaa....aaaaxxxxxxxxxXxxaaa===t~~~~aaa~~~~~~~~~~',
  '~~~~~aaTT......aaaata..t==~~~~~tt.aOxxxxxxxxxXxxxx^^^^^^^^xaax^~^^x=xTx..aTa..aaaaaaaxxxxxxxxxxx~~~~x==O~aaaaa~~~~~~~~~~',
  '~~~~~aaTTT"~~~~~~~~~aaaaa.~~~~....aaaxt==xxxxxxxxxx^^^^^^^^a^^^^^^^=xx....aa..aaaaxaXxxxxxxxxxxx~xxxx==t~aa~~~~~~~~~~~~~',
  '~~~~~~~a~~~~Ttaaaaaaaaaaa~~~~~........tt====xxxxxxxx^^^^^^^^^^^^^^=====O======aaaaxxx=====xxxxxxx=====xx.aa~~~~~~~~~~~~~',
  '~~~~~~~~~TO===aaaa==aaaaa~~~~~........tttxxxx=xxxxxxxt^^^^^~~^^^^x=x.x.....^.".aa^^xxxxxxxxxxxxxxxx==xxx.aa~~~~~~~~~~~~~',
  '~~~~~~~~~TTTTTaaaa.=.TTTT~~~~~.......ttttXxxx===xxx^^^^^^^^~^^^^^^=x..xx.^^^^..aa^^xxxxXxxxxx^xxxXx=xxx..aa~~~~~~~~~~~~~',
  '~~~~~~~~~~TTTTaaa..=.TTTT~~~~~.......ttttxxxxxx====O===============^xx.x.^^^^^^a^^^ax^xxxxx^^^xxxxx=xxxx~~a~~~~~~~~~~~~~',
  '~~~~~~~~~~TTTT.....=.T..~~~~~~.......tttxxxxxxxx~~~~~~^~~^^^^^^^^^^^^xx^^^^^^^^^^^^x^^^XxxxxxxxxXx==x~x.~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~TTT....TT=....~~~aaaa~~~~~ttttxxXxxxX~~xxxtt^~^^^^X^XX^^^^^^x^^^^^^^^^^^^..^^x.xxxxxxxx==xxxx..~~~~~~~~~~~~~~~',
  '~~~~~~~~~TTTTTT.TTT=...~~~~~~~aa...~~xtxxxxxxx~~xxxxx^^^^^XXX^X^^X^^^^^^^^^^^^~^^^^.^^^.axaaxxxx==Xxxxx"....~.a~~~~~~~~~',
  '~~~~~~~~a.TTTTTTTTT=T..~~~~~~~aa....~~~~~~~~~~~xXxxx~~X^^^X^^^^X^^X^^^X^^^^^^~~^~~^..^^^aaaxaxxx=xxXx.""........~~~~~~~~',
  '~~~~~~~.xxxX~~~~~~aOa~~~~~~~~~aaxx..xxxxxxxxxxxxxxxxxX^^^^^^^^^^^^^^^XX^^^^^^~~^~~^..aaaaaaax.xx=xxxx"""".......~~~~~~~~',
  '~~~~~~..xxx~~TTTTTTxT...~~~..x.xxxxxxxxxxxxxxxxxxXxxxx^^^^^^X^^X^^^^^^^^^^^^^^^^~~^..aaaaaa^^^xxO==x~x........tt~~~~~~~~',
  '~~~~~~~xxx~~xTTtttttt...~..xx....xaxxxxxxxxxxxxxxxxxxx^^^^^^^^^^XX^^^^X^^^^^^^^^~attaaaaaaa^x..xxx===.xaa.aaa~~~~~~~~~~~',
  '~~~~~~~x~~~xxTtttttt........x.x.x.xaxxxxxxxxxxxxxXxxxx^^X^XX^^^X^^^^^^^^^Oxxx".^~a~~~~~~~~~~~x.xxxxx==aaaaa""".t.~~~~~~~',
  '~~~~~~..~xxxTTtttttt.....xxxxxxa.xxx.xxxxxxxXxxxxxxxxXX^X^^^XX^^^^^^X^Xx==xx.xxx~a~~~~~~~~~~~x.tx.x~~~aaaaa"""...~~~~~~~',
  '~~~~~~~WWWWWWWaaaaax..aaaxxxxxxaa""""xxxaWWWWWxxxxxxaax^^^^^^^^^^^^^xxx==xxxxxx.~a~~~~~~~~~~~aaaaa.~..aaaaaa.....~~~~~~~',
  '~~~~~~~xx..xx.txt..xaaWWWxxxxxxxxxxxaa.xxxxxxxXxxxxxxT^^^^^^X^^^X^Oxxx==xxxxxxX~~aaaaaaaaaaaaaaaaaa~..aaaaaaaaaa..~~~~~~',
  'aa~~~~~a..x"x..........t.xxxxxxss"""s"".xxxxxxxxxxTTT^^^^^^^^^^^Xxxxx==xxxxxxxx~~x~~~~~~~~~~~aaaaa~~aaa..aaaaaaa....~~~~',
  'aaaaa~~......"...x""""ttttttt=ttttttttxttxxxxxxxxtTTT^^^^^^^^^^^^xxxx=xxxxxxxxx~~x~~~~~~~~~~~aaaaa~~aaaaa.aaaaaa...~~~~~',
  'a...aaa......"..."""ttttttttt=tTTTTTTTttttxxxtxxttTT~~^^^^^^^^^~txxxxxxxxxxxxxx~~x~~~~~~~~~~~~~~~~~~aaaaa=aOaaa...~~~~~~',
  'a...aaa......"..."""ttttttttt=tTTTTTTTTttttxxtxxttTT~~^^^^^^^^^~xxaxxxxxxxxxxxxaax~~asssaaaaaaaaaaaaaaa===aaaaa..~~~~~~~',
  '...aaaa......"...""tttttttttt=tTTTTTTTTtttttttxxttTT~~~^^^^^^^^~^axxxxXxxxxxxxxaaTx~xssaaaaatattaaaaaa==aa.aaaaa.~~~~~~~',
  '...aaaaa..."""...""tttttttttt=tTTTTTTTTtttttttx~~~~~~~~~^^^^^^^~~^aax======xxxxaa.xx.aaaaaaaaaaaaaaaa==ataa...aa~~~~~~~~',
  '~~.aaaa.""..""...""tttttttttt=tTTTTTTTTTtt~~~~~~~~~~TT^^^^axx^^^~~aaaxxxx.==x.aaaaaaaaaaaaaaaaaaaaaa==aaataaaaa~~~~~~~~~',
  '~~~aaaaa~~~"""atT..Tt"ttt...t=tTTTTTTTTTt~~~~~~~~~~~t^^^^^^^a^~~~~aaa~~~aaa===aaaaaa==aaaaaaaaaaaaa==aaaaaaaaa~~~~~~~~~~',
  '~~~~aaa~~~~"""tTT..."".....tt=tTTTTTTTTT~~~~~~~~~~~~tt^^^^^^a^^~~~aaa~~a...a..aaaaaaaaaaaaaaaaaaaaa=aaaaaaaaa~~~~~~~~~~~',
  '~~~~aaa~~~~"""TTTT.T"""sss..t=tTTTTTTTT~~~~~~~~~ttttttttt^^^x^^^~~~a~~~~~..a....aa.aaaaaaaaaa=aaa^^=^^^^aaa^^^^^~~~~~~~~',
  '~~~~~aa~~~~""".TTTTT"""ss..tt=txxxTTT~~~~~~~~~~...xxtttttttta...t~~aa~~~"..~aaaaaa"aataaaaaaa=a^^^t=aaa^^^^^aa~~~~~~~~~~',
  '~~~~~~~..."t""..TTTT...ss..tt=xxxxxTTT~~~~~~~~....."".tttttta..ttttaa."""""~~".aaa"aaaaaaaaaa=^^aaa=ataaaaaataaa~~~~~~~~',
  '~~~~~~~.......sTTTTT..ss...taOaaaaaTTTT~~~~~~.......xttttttta...ttta."""""~~~~~.~~"aaaaaaaata=^aaaa=aaaaaaaaaaaa~~~~~~~~',
  '~~~~~~~ss..sssTTTsTssss...ataaaaaaa~~~~~~~~~t.......ttttttttaa.....=.""""""~~~~~~~"taaaaaaaaa=^aaaaaaaaaaaaaaaaa~~~~~~~~',
  '~~~~~~~~ssssssTTsTsTsss...ataaaaaaa=TTT~~~~tt..."...ttttttttxaaa..==.""."""""~~~~~~aaaaaaaaaa=^aaaaaaaaataaaaaaaa~~~~~~~',
  '~~~~~~~~~ssssssssTTTTss...ttaaa"xx"======a.taa.""....TTTTttaxOaa===.""..."""""~~.~~~aaaaaxaaaa^O=aaaaaaaaaaaaaaaa"~~~~~~',
  '~~~~~~~~~~ssssssssTTTTtttatt.~"""""""""~~aaaa."......TTTTTaaaaaxx...."...""""".~..~~xxxxxxxxx=^xxxxxxxassssssaaaa"~~~~~~',
  '~~~~~~~~~~~ssssssssTTTtttttt.~"""""""""""..aa=O=========..".ax=xTT...xx"""""".....~~~xxxxxxxa=^xx^^^^^^ssssxxxxxa~~~~~~~',
  '~~~~~~~~~~~sssssssssTTttttta~~""""".""""""..."""""""...a..".xx=TTTTTxxxxx..........~~axxxxxa=x^^^^xxss^^^^^^^^^^^~~~~~~~',
  '~~~~~~~~~~~assssss.sTTt~~tt~~..."...."""""..."""""""..aaaxxxxxxxTXxxxxxxxxTTTTTxxxx~~x.xxxx=xxxxxxxxsssssxxxxxxx~~~~~~~~',
  '~~~~~~~~~~~aass~s....t~~~~~~~~~."...."""""...""""""".".a.xxxxxxxTTTTTTxxTTTTTTTTx.a~~x.xxx=a======aaaaaaaOxxxxx~~~~~~~~~',
  '~~~~~~~~~~~aa~~~.....~~~~a~~~~.......""""."""""""""""".=.xxxxxxxTTTTTT..TTTTTTTT...~~s...xxa."""""..ssssssxxxxx~~~~~~~~~',
  '~~~~~~~~~~~aaa~~~..a~~~~aa~~~xxx.....""""""t""....""...=O.sxTO=TTTTTTT...TTTTTTT..~~~sTT..aaa"""""ssssssssssss~~~~~~~~~~',
  '~~~~~~~~~~~aaa~~~~~~~~aaa....".""....""""ttt""...t.......xxxxxTTTTTTTsssssTTTTT...~~.Tttt.aaa.".t~~~ssssssssss~~~~~~~~~~',
  '~~~~~~~~~~~~aaaa~~..xxaxx.xss.ttT....""""""tst.aat...sss.xxxxxxTTTTTsssssssT....T.aaatttttaaa...~~~~~ssssssss~~~~~~~~~~~',
  '~~~~~~~~~~~~~~aa~xxxxxaxxxxxxtttTT.."""""".s.saaa.x.sxxxxxxxxx.......sssss.......T.aatttttt=t.....ttttt.tt~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~aaaaaxxx~xxxxxxtxxxx."""".....aa~~~~~xxxxx.""Wx......a~a.s...........aattttttOtt..t~aattaaa~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~aaaaaax~xxxxxxxxxxx"""....~~~.a~~~~~.xxxxx..x.....~~a~aaa...~....T..aa~tt~tttt..t~~aa~aaa~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~aaaa~~~~xxxxxxxxx.......~~~~a~~~~~x.xxxxx.ax.~~~~~~~aaaaa~~~~~~t..aa~~~~~ttst~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~x..x.tTTT..a~~~~~~~~~~~~~..xx~~~~a~~~~~~~~~~aaa~~~~~~~~~~aa~~~~~~st~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~""tttTTTT~~~~~~~~~~~~~~~~.~~~~~axaa~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~TT~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
  '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
}

local function site(id, x, y, map, name, kind, mx, my, dir, when)
  return { id = id, x = x, y = y, map = map, name = name, kind = kind, mx = mx, my = my, dir = dir, when = when, unless = "ruined" }
end

--- Where the party comes out, and the square they arrive on when they go in. Every site in the game, open or not: M.sites(s)
--- is what's open now. map and mx, my, dir match maps.DATA, and a region's R.sites gives its own through addSite.
M.SITES = {
  site("scythebreak", 62, 60, "scythebreak", "SCYTHEBREAK", "town", 3, 3, 1),
  site("orrenshire", 67, 44, "orrenshire", "ORRENSHIRE", "town", 3, 3, 2),
  site("mine", 74, 41, "mine_1", "ORRENSHIRE MINE", "dungeon", 3, 3, 2),
  site("hayford", 106, 65, "hr_hayford", "HAYFORD", "town", nil, nil, nil, "finished"),
  site("oplinas", 108, 47, "hr_oplinas", "OPLINAS", "city", nil, nil, nil, "finished"),
  site("glamouth", 92, 71, "hr_glamouth", "GLAMOUTH", "city", nil, nil, nil, "finished"),
  site("windmill", 96, 60, "hr_verdant_1", "THE WINDMILL", "town", nil, nil, nil, "hr_verdant_open"),
  site("blackpool", 97, 39, "px_blackpool", "BLACKPOOL", "town", nil, nil, nil, "hr_done"),
  site("killerth", 86, 26, "px_killerth", "KILLERTH", "town", nil, nil, nil, "hr_done"),
  site("murkwell", 72, 30, "px_murkwell", "MURKWELL", "town", nil, nil, nil, "hr_done"),
  site("adaphis", 104, 28, "px_pelvic", "ADAPHIS", "city", nil, nil, nil, "hr_done"),
  site("crevice", 52, 33, "sn_crevice_1", "CAVITY CREVICE", "dungeon", nil, nil, nil, "hr_done"),
  site("syndalia", 36, 28, "sn_syndalia", "SYNDALIA", "city", nil, nil, nil, "hr_done"),
  site("upriftin", 30, 24, "sn_upriftin", "UPRIFTIN", "town", nil, nil, nil, "hr_done"),
  site("eighstead", 11, 31, "sn_eighstead", "EIGHSTEAD", "town", nil, nil, nil, "hr_done"),
  site("antarith", 20, 38, "sn_antarith", "ANTARITH", "town", nil, nil, nil, "hr_done"),
  site("thuluan", 45, 8, "wm_thuluan", "THULUAN", "dungeon", nil, nil, nil, "wm_bargain"),
  site("crack_east", 62, 67, "em_crack_1", "THE CRACK", "dungeon", nil, nil, nil, "wm_done"),
  site("crack_west", 57, 67, "em_crack_1", "THE CRACK", "dungeon", nil, nil, nil, "wm_done"),
  site("agoshull", 30, 57, "em_agoshull", "AGOSHULL", "city", nil, nil, nil, "wm_done"),
  site("evrastin", 47, 62, "em_evrastin", "EVRASTIN", "town", nil, nil, nil, "wm_done"),
  site("abyss", 60, 27, "ud_abyss_1", "THE VIOLET ABYSS", "dungeon", nil, nil, nil, "em_done"),
}

--- Closed roads. The tile looks like any other but stops the party, and bumping it runs the script. A gate stands until its
--- unless flag is set, and from then on it's plain ground. The crack's gate stands on the site itself.
M.GATES = {
  { x = 80, y = 52, script = "gate_greywater", unless = "finished" },      -- the Greywater bridge
  { x = 100, y = 54, script = "gate_verdant", unless = "hr_verdant_open" }, -- the road through the ridge to the windmill
  { x = 105, y = 42, script = "gate_portal", unless = "hr_done" },         -- the Nevermore Portal, a bridge over to Blackpool
  { x = 64, y = 33, script = "gate_crevice", unless = "hr_done" },         -- the Cavity Crevice route, in the pass from Murkwell
  { x = 41, y = 14, script = "gate_thuluan", unless = "wm_bargain" },      -- the bridge over the strait to Thuluan
  { x = 62, y = 67, script = "gate_crack", unless = "wm_done" },           -- the crack in the wall
  { x = 65, y = 27, script = "gate_abyss", unless = "em_done" },           -- the valley up to the Violet Abyss
}

M.REGION_NAME = {
  heart = "THE QYRRISSIAN HEART", road = "THE ORRENSHIRE ROAD", heart_east = "THE EASTERN HEART", verdant = "THE VERDANT SEA",
  shaid = "SHAID", ebrein = "EBREIN", thuluan = "THULUAN", owlundia = "OWLUNDIA",
  ruin_south = "THE BROKEN HEART", ruin_north = "THE FALLEN NORTH", ruin_west = "THE DEAD EMPIRE",
}

local WALKS = { ["."] = true, ['"'] = true, T = true, ["="] = true, s = true, B = true, O = true, x = true, t = true, a = true }
local ON_THE_ROAD = { ["="] = true, B = true, O = true }

local function ruinedIn(s) return s ~= nil and s.flags ~= nil and s.flags.ruined == true end

--- Is a thing with when and unless flags in force? With no s, the flags are the slice's: none.
local function inForce(thing, s)
  local flags = s and s.flags or {}
  if thing.when and not flags[thing.when] then return false end
  if thing.unless and flags[thing.unless] then return false end
  return true
end

--- The tile at x, y. Anything off the edge of the map is sea.
function M.tileAt(x, y, s)
  local row = (ruinedIn(s) and M.ROWS_RUINED or M.ROWS)[y]
  if not row or x < 1 or x > M.W then return "~" end
  return row:sub(x, x)
end

--- The gates standing now. In the ruined world nothing is gated.
function M.gates(s)
  local list = {}
  if ruinedIn(s) then return list end
  for _, g in ipairs(M.GATES) do
    if inForce(g, s) then list[#list + 1] = g end
  end
  return list
end

function M.gateAt(x, y, s)
  if ruinedIn(s) then return nil end
  for _, g in ipairs(M.GATES) do
    if g.x == x and g.y == y and inForce(g, s) then return g end
  end
  return nil
end

--- The sites open now.
function M.sites(s)
  local list = {}
  for _, one in ipairs(M.SITES) do
    if inForce(one, s) then list[#list + 1] = one end
  end
  return list
end

function M.siteAt(x, y, s)
  for _, one in ipairs(M.SITES) do
    if one.x == x and one.y == y and inForce(one, s) then return one end
  end
  return nil
end

--- The site drawn on this tile, open yet or not.
function M.siteOn(x, y)
  for _, one in ipairs(M.SITES) do
    if one.x == x and one.y == y then return one end
  end
  return nil
end

--- A region's own numbers for a site, merged over the entry here. A new id is a new site: <id>_r takes its tile, name and look
--- from <id>, and opens once the world is ruined.
function M.addSite(id, fields)
  local entry
  for _, one in ipairs(M.SITES) do
    if one.id == id then entry = one end
  end
  if not entry then
    entry = { id = id }
    local was = id:match("^(.+)_r$")
    for _, one in ipairs(M.SITES) do
      if one.id == was then
        entry.x, entry.y, entry.name, entry.kind, entry.when = one.x, one.y, one.name, one.kind, "ruined"
      end
    end
    M.SITES[#M.SITES + 1] = entry
  end
  for k, v in pairs(fields) do entry[k] = v end
  return entry
end

function M.walkable(x, y, s) return WALKS[M.tileAt(x, y, s)] == true and not M.gateAt(x, y, s) end

--- Every square that can be walked to from here, keys y * 1000 + x, added to into.
local function spread(into, x, y, s)
  local todo = { x, y }
  while #todo > 0 do
    local ty, tx = table.remove(todo), table.remove(todo)
    local key = ty * 1000 + tx
    if not into[key] and M.walkable(tx, ty, s) then
      into[key] = true
      local n = #todo
      todo[n + 1], todo[n + 2], todo[n + 3], todo[n + 4] = tx + 1, ty, tx - 1, ty
      todo[n + 5], todo[n + 6], todo[n + 7], todo[n + 8] = tx, ty + 1, tx, ty - 1
    end
  end
  return into
end

local sliceStretch

--- The slice's country, found once, and never moved by the story: it's what the road and heart field tables mean.
function M.stretch()
  if sliceStretch then return sliceStretch end
  local first = M.SITES[1]
  sliceStretch = spread({}, first.x, first.y, nil)
  return sliceStretch
end

local reaches = {}

--- Where the party can get to from Scythebreak with these flags. The crack counts as a way through once it's open. Found once
--- for each set of open gates.
function M.reach(s)
  local key = ruinedIn(s) and "ruined" or "open"
  for _, g in ipairs(M.gates(s)) do key = key .. "," .. g.script end
  if reaches[key] then return reaches[key] end
  local first, east, west = M.SITES[1], nil, nil
  for _, one in ipairs(M.SITES) do
    if one.id == "crack_east" then east = one end
    if one.id == "crack_west" then west = one end
  end
  local found = spread({}, first.x, first.y, s)
  if found[east.y * 1000 + east.x] then spread(found, west.x, west.y, s) end
  reaches[key] = found
  return found
end

function M.isReachable(x, y, s) return M.reach(s)[y * 1000 + x] == true end

--- Which land a tile lies in, by where it is on the map, before the world breaks.
local function landOf(x, y)
  if y <= 13 and x <= 62 then return "thuluan" end
  if x <= 60 and (y >= 45 or (y == 44 and x < 20)) then return "owlundia" end
  if x <= 54 then return "ebrein" end
  if y < 44 then return "shaid" end
  if x <= 82 then return "heart" end
  if x >= 84 and x <= 112 and y >= 46 and y <= 63 and not (x >= 105 and y <= 50) then return "verdant" end
  return "heart_east"
end

--- And after. The field tables go by act: the Heart is the south, everything over the mountains' line the north.
local function ruinOf(x, y)
  if y < 44 then return "ruin_north" end
  return x <= 60 and "ruin_west" or "ruin_south"
end

--- Which random fights live here: "road" on the slice's road, "heart" in the country round it, and the land's own table past
--- that. With no s, nil past the slice's edge. nil on anything that can't be walked.
function M.region(x, y, s)
  if ruinedIn(s) then return WALKS[M.tileAt(x, y, s)] and ruinOf(x, y) or nil end
  if M.stretch()[y * 1000 + x] then return ON_THE_ROAD[M.tileAt(x, y)] and "road" or "heart" end
  if not s then return nil end
  return WALKS[M.tileAt(x, y, s)] and landOf(x, y) or nil
end

-- Each region brings its own arrival squares, and its ruined sites.
do
  local ok, content = pcall(require, "games.blightmare.content")
  if ok then
    for _, region in ipairs(content.regions()) do
      for id, fields in pairs(region.sites or {}) do M.addSite(id, fields) end
    end
  end
end

return M
