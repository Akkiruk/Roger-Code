-- games/cookie/data.lua
-- What there is to buy and to earn in Cookie Clicker: the buildings, the upgrades and the achievements, as plain tables.
-- Nothing here changes during a game. The rules look things up by id, and a save holds only ids and counts.

local M = {}

-- ---------------------------------------------------------------- buildings
-- cost is the price of the first one, cps what each makes per second. Every one owned raises the price by 15%.
M.BUILDINGS = {
  { id = "cursor", name = "Cursor", cost = 15, cps = 0.1, says = "Autoclicks once every 10 seconds" },
  { id = "grandma", name = "Grandma", cost = 100, cps = 1, says = "A nice grandma to bake more cookies" },
  { id = "farm", name = "Farm", cost = 1100, cps = 8, says = "Grows cookie plants from cookie seeds" },
  { id = "mine", name = "Mine", cost = 12000, cps = 47, says = "Mines out cookie dough and chocolate chips" },
  { id = "factory", name = "Factory", cost = 130000, cps = 260, says = "Produces large quantities of cookies" },
  { id = "bank", name = "Bank", cost = 1.4e6, cps = 1400, says = "Generates cookies from interest" },
  { id = "temple", name = "Temple", cost = 2e7, cps = 7800, says = "Full of precious, ancient chocolate" },
  { id = "wizard", name = "Wizard Tower", cost = 3.3e8, cps = 44000, says = "Summons cookies with magic spells" },
  { id = "shipment", name = "Shipment", cost = 5.1e9, cps = 260000, says = "Brings in fresh cookies from the cookie planet" },
  { id = "alchemy", name = "Alchemy Lab", cost = 7.5e10, cps = 1.6e6, says = "Turns gold into cookies" },
  { id = "portal", name = "Portal", cost = 1e12, cps = 1e7, says = "Opens a door to the Cookieverse" },
  { id = "timemachine", name = "Time Machine", cost = 1.4e13, cps = 6.5e7, says = "Brings cookies from the past, before they were eaten" },
  { id = "antimatter", name = "Antimatter Condenser", cost = 1.7e14, cps = 4.3e8, says = "Condenses the antimatter in the universe into cookies" },
  { id = "prism", name = "Prism", cost = 2.1e15, cps = 2.9e9, says = "Converts light itself into cookies" },
  { id = "chancemaker", name = "Chancemaker", cost = 2.6e16, cps = 2.1e10, says = "Generates cookies out of thin air through sheer luck" },
}

-- ---------------------------------------------------------------- upgrades
-- Every upgrade: id, name, says (what it does), cost, kind, and what unlocks it. kind is one of
--   building (doubles one building: of = its index), tap (doubles taps too, for the cursor's first three),
--   fingers (cursors and taps gain per other building), mouse (a tap gains a share of the cookies per second),
--   flavour (pct more production), kitten (production grows with milk), golden (golden cookie luck).
M.UPGRADES = {}
local function add(u)
  M.UPGRADES[#M.UPGRADES + 1] = u
end

local TIER_OWNED = { 1, 5, 25, 50, 100, 150, 200, 250, 300, 350 }
local TIER_PRICE = { 10, 50, 500, 5e4, 5e6, 5e8, 5e10, 5e12, 5e14, 5e16 }
local TIER_WORDS = { "Improved", "Reinforced", "Polished", "Supercharged", "Quantum", "Cosmic", "Eldritch", "Infinite", "Transcendent", "Omnipotent" }

-- The first few tiers of each building have names of their own; later tiers are the building's name with a grander word.
local TIER_NAMES = {
  cursor = { "Reinforced index finger", "Carpal tunnel cream", "Ambidextrous", "Thousand-tap gloves", "Quintillion fingers" },
  grandma = { "Forwards from grandma", "Steel-plated rolling pins", "Lubricated dentures", "Prune juice", "Double-thick glasses" },
  farm = { "Cheap hoes", "Fertilizer", "Cookie trees", "Genetically-modified cookies", "Gingerbread scarecrows" },
  mine = { "Sugar gas", "Megadrill", "Ultradrill", "Ultimadrill", "H-bomb mining" },
  factory = { "Sturdier conveyor belts", "Child labor", "Sweatshop", "Radium reactors", "Recombobulators" },
  bank = { "Taller tellers", "Scissor-resistant credit cards", "Acid-proof vaults", "Chocolate coins", "Exponential interest" },
  temple = { "Golden idols", "Sacrifices", "Delicious blessing", "Sun festival", "Enlarged pantheon" },
  wizard = { "Pointier hats", "Beardlier beards", "Ancient grimoires", "Kitchen curses", "School of sorcery" },
  shipment = { "Vanilla nebulae", "Wormholes", "Frequent flyer", "Warp drive", "Chocolate monoliths" },
  alchemy = { "Antimony", "Essence of dough", "True chocolate", "Ambrosia", "Aqua crustulae" },
  portal = { "Ancient tablet", "Insane oatling workers", "Soul bond", "Sanity dance", "Brane transplant" },
  timemachine = { "Flux capacitors", "Time paradox resolver", "Quantum conundrum", "Causality enforcer", "Yestermorrow comparators" },
  antimatter = { "Sugar bosons", "String theory", "Large macaron collider", "Big bang bake", "Reverse cyclotrons" },
  prism = { "Gem polish", "9th color", "Chocolate light", "Grainbow", "Pure cosmic light" },
  chancemaker = { "Your lucky cookie", "All Bets Are Off", "Winning lottery ticket", "Four-leaf clover field", "A recipe book about books" },
}

for i, b in ipairs(M.BUILDINGS) do
  local names = TIER_NAMES[b.id] or {}
  for tier = 1, #TIER_OWNED do
    local name = names[tier] or (TIER_WORDS[tier] .. " " .. b.name:lower() .. "s")
    local tapToo = b.id == "cursor" and tier <= 3
    add({
      id = b.id .. tier, name = name, cost = b.cost * TIER_PRICE[tier], kind = tapToo and "tap" or "building", of = i,
      needOwned = TIER_OWNED[tier],
      says = tapToo and "Taps and cursors twice as good" or (b.name .. "s twice as good"),
    })
  end
end

-- Thousand fingers: cursors and taps gain a little for every building that isn't a cursor, and later tiers multiply it.
add({ id = "fingers1", name = "Thousand fingers", cost = 1e5, kind = "fingers", gain = 0.1, needOwned = 25, of = 1,
  says = "Taps and cursors +0.1 for each other building" })
add({ id = "fingers2", name = "Million fingers", cost = 1e7, kind = "fingers", times = 5, needOwned = 50, of = 1, says = "Thousand fingers x5" })
add({ id = "fingers3", name = "Billion fingers", cost = 1e8, kind = "fingers", times = 10, needOwned = 100, of = 1, says = "Thousand fingers x10" })
add({ id = "fingers4", name = "Trillion fingers", cost = 1e9, kind = "fingers", times = 20, needOwned = 150, of = 1, says = "Thousand fingers x20" })

-- Mice: each makes a tap worth 1% more of the cookies per second. Unlocked by cookies made by hand.
local MICE = { "Plastic mouse", "Iron mouse", "Titanium mouse", "Adamantium mouse", "Unobtainium mouse", "Eludium mouse", "Wishalloy mouse", "Fantasteel mouse" }
for i, name in ipairs(MICE) do
  add({ id = "mouse" .. i, name = name, cost = 5e4 * 100 ^ (i - 1), kind = "mouse", pct = 1, needHand = 1000 * 100 ^ (i - 1),
    says = "Taps gain 1% of your cookies per second" })
end

-- Flavours: a percentage more of everything. Each shows once this run has baked half its price.
local FLAVOURS = {
  { "Plain cookies", 1e6, 1 }, { "Sugar cookies", 5e6, 1 }, { "Oatmeal raisin cookies", 1e7, 1 },
  { "Peanut butter cookies", 5e7, 1 }, { "Coconut cookies", 1e8, 2 }, { "White chocolate cookies", 5e8, 2 },
  { "Macadamia nut cookies", 1e9, 2 }, { "Double-chip cookies", 5e9, 2 }, { "White choc macadamia cookies", 1e10, 2 },
  { "All-chocolate cookies", 5e10, 2 }, { "Dark choc-coated cookies", 1e11, 4 }, { "White choc-coated cookies", 5e11, 4 },
  { "Eclipse cookies", 1e12, 4 }, { "Zebra cookies", 5e12, 4 }, { "Snickerdoodles", 1e13, 4 }, { "Stroopwafels", 5e13, 4 },
  { "Macaroons", 1e14, 4 }, { "Empire biscuits", 5e14, 4 }, { "Madeleines", 1e15, 5 }, { "Palmiers", 5e15, 5 },
  { "Palets", 1e16, 5 }, { "Sables", 5e16, 5 }, { "Gingerbread men", 1e17, 5 }, { "Gingerbread trees", 5e17, 5 },
  { "Pure black chocolate cookies", 1e18, 5 }, { "Pure white chocolate cookies", 5e18, 5 }, { "Ladyfingers", 1e19, 5 },
  { "Tuiles", 5e19, 5 }, { "Chocolate-stuffed biscuits", 1e20, 5 }, { "Checker cookies", 5e20, 5 },
  { "Butter cookies", 1e21, 5 }, { "Cream cookies", 5e21, 5 }, { "Gingersnaps", 1e22, 5 }, { "Cinnamon cookies", 5e22, 5 },
  { "Vanity cookies", 1e23, 5 }, { "Cigars", 5e23, 5 }, { "Pinwheel cookies", 1e24, 5 }, { "Fudge squares", 5e24, 5 },
  { "Shortbread biscuits", 1e25, 5 }, { "Millionaires' shortbreads", 5e25, 5 }, { "Caramel cookies", 1e26, 5 },
  { "Pecan sandies", 5e26, 5 }, { "Moravian spice cookies", 1e27, 5 }, { "Anzac biscuits", 5e27, 5 },
  { "Buttercakes", 1e28, 5 }, { "Ice cream sandwiches", 5e28, 5 }, { "Dragon cookies", 1e30, 7 }, { "Cosmic cookies", 1e33, 10 },
  { "Infinity cookies", 1e36, 10 }, { "The final cookie", 1e40, 15 },
}
for i, f in ipairs(FLAVOURS) do
  add({ id = "flavour" .. i, name = f[1], cost = f[2], kind = "flavour", pct = f[3], needBaked = f[2] / 2,
    says = "Cookie production +" .. f[3] .. "%" })
end

-- Kittens: production grows with milk, and milk comes from achievements (4% each).
local KITTENS = {
  { "Kitten helpers", 9e6, 0.1, 13 }, { "Kitten workers", 9e9, 0.125, 25 }, { "Kitten engineers", 9e12, 0.15, 40 },
  { "Kitten overseers", 9e15, 0.175, 55 }, { "Kitten managers", 9e18, 0.2, 70 }, { "Kitten accountants", 9e21, 0.2, 85 },
  { "Kitten specialists", 9e24, 0.2, 100 }, { "Kitten experts", 9e27, 0.2, 115 },
}
for i, k in ipairs(KITTENS) do
  add({ id = "kitten" .. i, name = k[1], cost = k[2], kind = "kitten", per = k[3], needAch = k[4],
    says = "More production the more milk you have" })
end

-- Golden cookie luck, unlocked by golden cookies tapped (all time).
add({ id = "lucky1", name = "Lucky day", cost = 777777777, kind = "golden", needGolden = 7, says = "Golden cookies come twice as often" })
add({ id = "lucky2", name = "Serendipity", cost = 77777777777, kind = "golden", needGolden = 27, says = "Golden cookies come twice as often again" })
add({ id = "lucky3", name = "Get lucky", cost = 77777777777777, kind = "golden", needGolden = 77, says = "Golden cookie effects last twice as long" })

M.UPGRADE_BY_ID = {}
for i, u in ipairs(M.UPGRADES) do
  u.index = i
  M.UPGRADE_BY_ID[u.id] = u
end

-- ---------------------------------------------------------------- achievements
-- Every achievement: id, name, says, and a test of the rules' stats. The rules know how to read each kind:
--   baked (all time), rate (cookies per second), hand (cookies made by tapping), taps, golden, owned (one building),
--   total (all buildings), ups (upgrades bought), ascend (times ascended), away (longest bake while away, in seconds),
--   neverclick (baked this many with 15 taps or fewer).
M.ACHIEVEMENTS = {}
local function earn(id, name, kind, need, says, of)
  M.ACHIEVEMENTS[#M.ACHIEVEMENTS + 1] = { id = id, name = name, kind = kind, need = need, says = says, of = of }
end

local BAKED = {
  { "Wake and bake", 1 }, { "Making some dough", 1000 }, { "So baked right now", 1e5 }, { "Fledgling bakery", 1e6 },
  { "Affluent bakery", 1e8 }, { "World-famous bakery", 1e9 }, { "Cosmic bakery", 1e10 }, { "Galactic bakery", 1e11 },
  { "Universal bakery", 1e12 }, { "Timeless bakery", 1e13 }, { "Infinite bakery", 1e14 }, { "Immortal bakery", 1e15 },
  { "Don't stop me now", 1e16 }, { "You can stop now", 1e17 }, { "Cookies all the way down", 1e18 },
  { "Overdose", 1e19 }, { "How?", 1e20 }, { "The land of milk and cookies", 1e21 }, { "Dreams of cookies", 1e24 },
  { "Cookie singularity", 1e27 }, { "Beyond the end", 1e30 },
}
for i, a in ipairs(BAKED) do earn("baked" .. i, a[1], "baked", a[2], "Bake " .. "%s cookies in all") end

local RATE = {
  { "Casual baking", 1 }, { "Hardcore baking", 10 }, { "Steady tasty stream", 100 }, { "Cookie monster", 1000 },
  { "Mass producer", 1e4 }, { "Cookie vortex", 1e5 }, { "Cookie pulsar", 1e6 }, { "Cookie quasar", 1e7 },
  { "Oh hey, you're still here", 1e8 }, { "Let's never bake again", 1e9 }, { "A world filled with cookies", 1e10 },
  { "Fading luck", 1e12 }, { "Endless stream", 1e15 },
}
for i, a in ipairs(RATE) do earn("rate" .. i, a[1], "rate", a[2], "Bake %s cookies per second") end

local HAND = { { "Clicktastic", 1000 }, { "Clickathlon", 1e5 }, { "Clickolympics", 1e7 }, { "Clickorama", 1e9 }, { "Clickasmic", 1e11 }, { "Clickageddon", 1e13 } }
for i, a in ipairs(HAND) do earn("hand" .. i, a[1], "hand", a[2], "Make %s cookies by tapping") end

local TAPS = { { "First tap", 1 }, { "Finger exercise", 100 }, { "Sore finger", 1000 }, { "Ten thousand taps", 10000 }, { "Tap legend", 50000 } }
for i, a in ipairs(TAPS) do earn("taps" .. i, a[1], "taps", a[2], "Tap the cookie %s times") end

local GOLDEN = { { "Golden cookie", 1 }, { "Lucky cookie", 7 }, { "A stroke of luck", 27 }, { "Fortune", 77 }, { "Leprechaun", 777 } }
for i, a in ipairs(GOLDEN) do earn("golden" .. i, a[1], "golden", a[2], "Tap %s golden cookies") end

-- One building: own 1, 50 and 100 of it.
local OWN_NAMES = {
  cursor = { "Click", "Double-click", "Mouse wheel" }, grandma = { "Grandma's cookies", "Sloppy kisses", "Retirement home" },
  farm = { "Bought the farm", "Reap what you sow", "Farm ill" }, mine = { "Production chain", "Industrial revolution", "Global warming" },
  factory = { "You too can be a factory", "Mass production", "Cookie works" }, bank = { "Pretty penny", "Fit the bill", "A loan in the dark" },
  temple = { "Your time to shrine", "Shady sect", "New-age cult" }, wizard = { "Bewitched", "The sorcerer's apprentice", "Charms and enchantments" },
  shipment = { "Expedition", "Galactic highway", "Far far away" }, alchemy = { "Transmutation", "Transmogrification", "Gold member" },
  portal = { "A whole new world", "Now you're thinking", "Dimensional shift" }, timemachine = { "Time warp", "Alternate timeline", "Rewriting history" },
  antimatter = { "Antibatter", "Quirky quarks", "It does matter!" }, prism = { "Prism", "Clever optics", "Lucky rainbow" },
  chancemaker = { "Lucky charms", "Chance of a lifetime", "What are the odds" },
}
for i, b in ipairs(M.BUILDINGS) do
  local names = OWN_NAMES[b.id]
  for j, need in ipairs({ 1, 50, 100 }) do
    earn(b.id .. "_own" .. need, names[j], "owned", need, "Have %s " .. b.name:lower() .. (need == 1 and "" or "s"), i)
  end
end

local TOTAL = { { "Builder", 100 }, { "Architect", 500 }, { "Engineer", 1000 }, { "Lord of constructs", 2000 } }
for i, a in ipairs(TOTAL) do earn("total" .. i, a[1], "total", a[2], "Own %s buildings") end

local UPS = { { "Enhancer", 20 }, { "Augmenter", 50 }, { "Upgrader", 100 }, { "Lord of progress", 150 } }
for i, a in ipairs(UPS) do earn("ups" .. i, a[1], "ups", a[2], "Buy %s upgrades") end

local ASCEND = { { "Rebirth", 1 }, { "Resurrection", 5 }, { "Reincarnation", 10 }, { "Endless cycle", 25 } }
for i, a in ipairs(ASCEND) do earn("ascend" .. i, a[1], "ascend", a[2], "Ascend %s times") end

earn("away1", "Sleeping baker", "away", 3600, "Bake while away for an hour")
earn("away2", "Night shift", "away", 8 * 3600, "Bake while away for eight hours")
earn("away3", "The bakery never sleeps", "away", 24 * 3600, "Bake while away for a whole day")
earn("never1", "Neverclick", "neverclick", 1e6, "Bake a million cookies with 15 taps or fewer")
earn("never2", "True Neverclick", "neverclick", 1e9, "Bake a billion cookies with 15 taps or fewer")

M.ACH_BY_ID = {}
for i, a in ipairs(M.ACHIEVEMENTS) do
  a.index = i
  M.ACH_BY_ID[a.id] = a
end

return M
