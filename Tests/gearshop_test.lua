-- gearshop_test.lua
-- The gear shop's rules (prices, what it buys, the tab, store credit) and its vault index against pretend chests.
-- The whole shop on emulated computers is tested from craftos-agent (tools/geartest).

local testing = require("testing")
local rules = require("lib.gearshop.rules")
local stockLib = require("lib.gearshop.stock")

local test, eq, truthy = testing.test, testing.eq, testing.truthy
local cfg = rules.DEFAULTS

-- ---------------------------------------------------------------- prices

test("gearshop: the price goes up 2 for every 10 levels", function()
  eq(rules.price(1), 2, "level 1")
  eq(rules.price(9), 2, "level 9")
  eq(rules.price(10), 4, "level 10")
  eq(rules.price(19), 4, "level 19")
  eq(rules.price(40), 10, "level 40")
  eq(rules.price(49), 10, "level 49")
  eq(rules.price(50), 12, "level 50")
  eq(rules.price(99), 20, "level 99")
  eq(rules.price(100), 22, "level 100")
  eq(rules.price(0), 2, "level 0")
  eq(rules.price(nil), 2, "no level")
  eq(rules.price(140), 22, "past 100 is the top bracket")
  for level = 0, 100 do
    eq(rules.price(level), 2 * (math.min(10, math.floor(level / 10)) + 1), "level " .. level)
  end
end)

test("gearshop: the price per bracket is the owner's to change", function()
  eq(rules.price(45, { pricePerBracket = 3 }), 15, "3 a bracket at 45")
  eq(rules.bracketPrice(10, { pricePerBracket = 5 }), 55, "5 a bracket at 100")
end)

test("gearshop: brackets and their labels", function()
  eq(rules.bracket(0), 0)
  eq(rules.bracket(9), 0)
  eq(rules.bracket(10), 1)
  eq(rules.bracket(99), 9)
  eq(rules.bracket(100), 10)
  eq(rules.bracket(-3), 0)
  eq(rules.bracketLabel(0), "1-9")
  eq(rules.bracketLabel(4), "40-49")
  eq(rules.bracketLabel(10), "100")
end)

-- ---------------------------------------------------------------- pieces

local function detail(level, rarity, extra)
  local d = { name = "the_vault:sword", count = 1, nbt = "n" .. level .. rarity .. tostring(extra and extra.tag or ""),
    displayName = "Sword", vaultData = { itemType = "Gear", level = level, rarity = rarity, name = "Sword" } }
  for k, v in pairs(extra or {}) do
    if k ~= "tag" then d.vaultData[k] = v end
  end
  return d
end

test("gearshop: a piece is read from its item details", function()
  local piece = rules.piece(detail(45, "EPIC", { prefixes = { { name = "+5 Attack Damage" } }, suffixes = { { name = "Soul Chance" } } }))
  eq(piece.key, "the_vault:sword#n45EPIC")
  eq(piece.type, "the_vault:sword")
  eq(piece.kind, "Gear")
  eq(piece.level, 45)
  eq(piece.rarity, "EPIC")
  eq(piece.legendary, nil)
  truthy(piece.search:find("soul chance", 1, true), "modifier names can be searched")
  eq(rules.grade(piece), "EPIC")
  eq(rules.typeLabel(piece.type), "Sword")
  eq(rules.typeLabel("the_vault:magnet_helmet"), "Magnet Helmet")
end)

test("gearshop: legendary is the piece's flag or a legendary modifier", function()
  eq(rules.piece(detail(45, "RARE", { isLegendary = true })).legendary, true)
  eq(rules.piece(detail(45, "RARE", { prefixes = { { name = "x", legendary = true } } })).legendary, true)
  eq(rules.grade(rules.piece(detail(45, "RARE", { isLegendary = true }))), "LEGENDARY")
  eq(rules.piece(detail(45, "RARE")).legendary, nil)
end)

test("gearshop: an item with no vault data is stored but never on display", function()
  local piece = rules.piece({ name = "minecraft:cobblestone", count = 3 })
  eq(piece.kind, nil)
  eq(rules.forSale(piece, cfg), false)
  eq(rules.piece(nil), nil)
  eq(rules.forSale(rules.piece({ name = "the_vault:jewel", vaultData = { itemType = "Jewel", level = 5 } }), cfg), false)
end)

-- ---------------------------------------------------------------- buying

test("gearshop: the shop buys epic, omega and legendary; above 70 omega and legendary; at 100 legendary only", function()
  local function buys(level, rarity, extra)
    return (rules.accepts(rules.piece(detail(level, rarity, extra)), cfg))
  end
  for _, level in ipairs({ 0, 1, 35, 69, 70 }) do
    eq(buys(level, "SCRAPPY"), false, "scrappy " .. level)
    eq(buys(level, "COMMON"), false, "common " .. level)
    eq(buys(level, "RARE"), false, "rare " .. level)
    eq(buys(level, "EPIC"), true, "epic " .. level)
    eq(buys(level, "OMEGA"), true, "omega " .. level)
    eq(buys(level, "RARE", { isLegendary = true }), true, "legendary " .. level)
  end
  for _, level in ipairs({ 71, 85, 99 }) do
    eq(buys(level, "RARE"), false, "rare " .. level)
    eq(buys(level, "EPIC"), false, "epic " .. level)
    eq(buys(level, "OMEGA"), true, "omega " .. level)
    eq(buys(level, "EPIC", { isLegendary = true }), true, "legendary " .. level)
  end
  for _, level in ipairs({ 100, 101 }) do
    eq(buys(level, "EPIC"), false, "epic " .. level)
    eq(buys(level, "OMEGA"), false, "omega " .. level)
    eq(buys(level, "OMEGA", { isLegendary = true }), true, "legendary " .. level)
    eq(buys(level, "COMMON", { prefixes = { { name = "x", legendary = true } } }), true, "legendary modifier " .. level)
  end
  eq(buys(50, "UNIQUE"), false, "unique")
  local ok, why = rules.accepts(rules.piece({ name = "minecraft:dirt", count = 1 }), cfg)
  eq(ok, false)
  eq(why, "not gear")
  eq(select(2, rules.accepts(rules.piece(detail(80, "EPIC")), cfg)), "omega or better above 70")
  eq(select(2, rules.accepts(rules.piece(detail(100, "OMEGA")), cfg)), "legendary only at 100")
end)

test("gearshop: ten pieces make a token, and the fraction carries to the next sale", function()
  eq(rules.pieceMilli(cfg), 100)
  local tokens, carry = rules.settleSale(0, 7, cfg)
  eq(tokens, 0)
  eq(carry, 700)
  tokens, carry = rules.settleSale(carry, 5, cfg)
  eq(tokens, 1)
  eq(carry, 200)
  tokens, carry = rules.settleSale(carry, 28, cfg)
  eq(tokens, 3)
  eq(carry, 0)
  tokens, carry = rules.settleSale(nil, 0, cfg)
  eq(tokens, 0)
  eq(carry, 0)
  -- nothing is lost however a seller splits their pieces up
  local total, left = 0, 0
  for n = 1, 37 do
    local t
    t, left = rules.settleSale(left, n % 4, cfg)
    total = total + t
  end
  local pieces = 0
  for n = 1, 37 do pieces = pieces + n % 4 end
  eq(total * 1000 + left, pieces * 100, "tokens paid plus the carry is every piece's worth")
end)

test("gearshop: store credit is four times the tokens", function()
  eq(rules.creditMilli(10, cfg), 4000)
  eq(rules.creditMilli(1, cfg), 400)
  eq(rules.creditMilli(0, cfg), 0)
  eq(rules.creditMilli(10, { piecesPerToken = 5, creditMultiplier = 2 }), 4000)
  eq(rules.pieceMilli({ piecesPerToken = 3 }), 333)
  eq(rules.showMilli(3600), "3.6")
  eq(rules.showMilli(4000), "4")
  eq(rules.showMilli(0), "0")
  eq(rules.showMilli(50), "0.05")
end)

-- ---------------------------------------------------------------- store credit only, unless the owner turns tokens on

local tokensOn = {}
for k, v in pairs(cfg) do tokensOn[k] = v end
tokensOn.sellForTokens = true

test("gearshop: by default a sale pays store credit only", function()
  eq(rules.DEFAULTS.sellForTokens, false, "the default is credit only")
  eq(rules.sellsForTokens(cfg), false)
  eq(rules.sellsForTokens(nil), false, "no limits at all is the default")
  eq(rules.sellsForTokens({}), false, "a limit left out is the default")
  eq(rules.saleMode("credit", cfg), "credit")
  eq(rules.saleMode("tokens", cfg), "credit", "a tokens tap from an old screen still pays credit")
  eq(rules.saleMode(nil, cfg), "credit")
  eq(rules.saleMode("tokens", nil), "credit")
end)

test("gearshop: with sellForTokens on the seller picks tokens or credit", function()
  eq(rules.sellsForTokens(tokensOn), true)
  eq(rules.saleMode("tokens", tokensOn), "tokens")
  eq(rules.saleMode("credit", tokensOn), "credit")
  eq(rules.saleMode("anything", tokensOn), "credit", "only TOKENS is ever a token sale")
  eq(rules.sellsForTokens({ sellForTokens = "true" }), false, "only a real true turns tokens on")
end)

-- the sell point's monitor, drawn into a pretend 39x19 monitor
local function drawSell(limits, view)
  local hadColors = rawget(_G, "colors")
  if not hadColors then rawset(_G, "colors", { black = 32768 }) end
  local ui = require("lib.gearshop.ui")
  local fakeIo = { call = function(_, method)
    if method == "getSize" then return true, 39, 19 end
    return true
  end }
  local s = ui.screen(fakeIo, "monitor_sell", 0.5)
  local shop = { ready = true, cfg = limits, sellView = view, noteFor = function() return nil end }
  ui.sell(s, shop)
  if not hadColors then rawset(_G, "colors", nil) end
  local labels = {}
  for _, b in ipairs(s.buttons) do labels[#labels + 1] = b.id .. ":" .. b.label end
  -- the rows read as one line of words, so text wrapped over two rows is still found
  return (table.concat(s.text, " "):gsub("%s+", " ")), table.concat(labels, ",")
end

local function sellView(n)
  local view = { accepted = {}, rejected = {}, returns = {} }
  for i = 1, n do view.accepted[i] = { slot = i, key = "k" .. i, label = "Sword" } end
  return view
end

test("gearshop: the credit-only sell screen offers store credit and never tokens or the floor", function()
  for _, n in ipairs({ 0, 3 }) do
    local text, buttons = drawSell(cfg, sellView(n))
    eq(buttons, "credit:SELL FOR STORE CREDIT", "one button, store credit, with " .. n .. " pieces in")
    eq(text:lower():find("token", 1, true), nil, "no word of tokens with " .. n .. " pieces in")
    eq(text:lower():find("floor", 1, true), nil, "no word of the floor with " .. n .. " pieces in")
  end
  local empty = drawSell(cfg, sellView(0))
  truthy(empty:find("store credit: 0.4 a piece", 1, true), "an empty chest says what a piece gives")
  local three = drawSell(cfg, sellView(3))
  truthy(three:find("Buying: 3", 1, true), "how many are bought")
  truthy(three:find("You get 1.2 store credit", 1, true), "what the seller gets")
end)

test("gearshop: with sellForTokens on the sell screen is as before: TOKENS or STORE CREDIT", function()
  local text, buttons = drawSell(tokensOn, sellView(3))
  eq(buttons, "tokens:TOKENS,credit:STORE CREDIT x4")
  truthy(text:find("tokens 0.3", 1, true), "what three pieces make in tokens")
  truthy(text:find("or store credit 1.2", 1, true), "and in credit")
  local empty = drawSell(tokensOn, sellView(0))
  truthy(empty:find("10 pieces make 1 token, or 4 in store credit.", 1, true), "the old rate line")
end)

--- A display chest's monitor at a size, open for Alice (tab 20, credit 1.5) with `n` pieces in it, or on its type picker.
local function drawStation(w, h, n, mode, note, wing)
  local hadColors = rawget(_G, "colors")
  if not hadColors then rawset(_G, "colors", { black = 32768 }) end
  local ui = require("lib.gearshop.ui")
  local s = ui.screen({ call = function(_, method)
    if method == "getSize" then return true, w, h end
    return true
  end }, "12:monitor_1", 0.5)
  local shown, known = {}, {}
  for i = 1, n do
    shown["the_vault:sword#k" .. i] = 1
    known["the_vault:sword#k" .. i] = { label = "Sword", level = 40 + i % 10, rarity = "RARE", vaultData = { rarity = "RARE" } }
  end
  local typeList = { "the_vault:sword", "the_vault:axe", "the_vault:helmet", "the_vault:chestplate", "the_vault:leggings",
    "the_vault:boots", "the_vault:shield", "the_vault:wand", "the_vault:focus", "the_vault:magnet" }
  local summary = { types = {} }
  for _, t in ipairs(typeList) do summary.types[t] = { total = 15 } end
  local ds = { shopper = "Alice", type = "the_vault:sword", bracket = 4, phase = "open", page = 1, pages = 3, total = n, shown = shown, prices = {} }
  local shop = {
    ready = true, cfg = cfg, state = { shoppers = { Alice = {} }, credit = { Alice = 1500 } },
    ds = function() return ds end,
    owes = function() return 20 end,
    noteFor = function() return note end,
    priceOf = function() return 10 end,
    stock = { known = known, summary = function() return summary end,
      typesNear = function()
        local out = {}
        for _, t in ipairs(typeList) do out[#out + 1] = { type = t, bracket = 4, count = 15 } end
        return out
      end },
    typesFor = function(self, d, bracket) return rules.inCategoryList(self.stock.typesNear(bracket), d.category, cfg) end,
  }
  ui.station(s, shop, { id = "1", kind = "station", category = wing }, { mode = mode })
  if not hadColors then rawset(_G, "colors", nil) end
  return s
end

test("gearshop: a display chest's screen lists no gear: the type, the price, her tab and credit, the page, on every size", function()
  -- 2x1 in the floor (the owner's layout), one block wide and two high, and the bigger walls the shop had before
  for _, size in ipairs({ { 36, 10 }, { 15, 24 }, { 39, 19 }, { 57, 24 } }) do
    local w, h = size[1], size[2]
    local bh = h >= 16 and 3 or 2
    for _, mode in ipairs({ false, "types" }) do
      local s = drawStation(w, h, 30, mode or nil)
      local ids = {}
      for _, b in ipairs(s.buttons) do
        local where = ("%dx%d %s %s"):format(w, h, mode or "chest", b.id)
        truthy(b.x >= 1 and b.y >= 1 and b.x + b.w - 1 <= w and b.y + b.h - 1 <= h, where .. " fits on the monitor")
        eq(b.h, bh, where .. " is big enough to tap")
        truthy(b.label:match("%a%a"), where .. " has a whole label: " .. b.label)
        ids[#ids + 1] = b.id
      end
      local text = table.concat(s.text, " "):gsub("%s+", " ")
      local where = w .. "x" .. h
      if mode then
        truthy(table.concat(ids, " "):find("settype settype", 1, true), where .. " types to pick")
        truthy(table.concat(ids, " "):find("back", 1, true), where .. " BACK")
      else
        eq(table.concat(ids, " "), "types level level next done", where .. " every button")
        truthy(text:find("Sword", 1, true) and text:find("40-49", 1, true), where .. " what the chest is showing")
        truthy(text:find("10 each", 1, true), where .. " the price")
        truthy(text:find("Alice's chest", 1, true), where .. " whose chest")
        truthy(text:find("Tab 20", 1, true), where .. " her tab")
        truthy(text:find("Credit 1.5", 1, true), where .. " her store credit")
        truthy(text:find("Page 1 of 3", 1, true), where .. " the page")
        eq(text:find("L4%d"), nil, where .. " no piece is listed")
        eq(text:find("Rare", 1, true), nil, where .. " no rarity is listed")
      end
    end
  end
  local s = drawStation(36, 10, 12, nil, "Locked to Bob.")
  truthy((table.concat(s.text, " "):gsub("%s+", " ")):find("Locked to Bob.", 1, true), "the note")
  s = drawStation(36, 10, 0)
  truthy((table.concat(s.text, " "):gsub("%s+", " ")):find("None in stock at this level", 1, true), "nothing at this level")
end)

test("gearshop: a payout never takes the owner below the floor", function()
  eq(rules.payable(5, 1005, 1000), 5)
  eq(rules.payable(5, 1004, 1000), 4)
  eq(rules.payable(5, 1000, 1000), 0)
  eq(rules.payable(5, 400, 1000), 0)
  eq(rules.payable(5, nil, 1000), 0, "a balance that cannot be read pays nothing")
  eq(rules.payable(0, 5000, 1000), 0)
  eq(rules.payable(-3, 5000, 1000), 0, "the floor is only about payouts")
  eq(rules.payable(7, 1000.9, 1000), 0)
end)

-- ---------------------------------------------------------------- the tab

test("gearshop: store credit pays first, in whole tokens, and tokens cover the rest", function()
  local credit, tokens = rules.splitPayment(10, 3600)
  eq(credit, 3)
  eq(tokens, 7)
  credit, tokens = rules.splitPayment(10, 0)
  eq(credit, 0)
  eq(tokens, 10)
  credit, tokens = rules.splitPayment(10, nil)
  eq(tokens, 10)
  credit, tokens = rules.splitPayment(10, 25000)
  eq(credit, 10)
  eq(tokens, 0)
  credit, tokens = rules.splitPayment(2, 900)
  eq(credit, 0)
  eq(tokens, 2)
  credit, tokens = rules.splitPayment(0, 5000)
  eq(credit, 0)
  eq(tokens, 0)
  eq(rules.tabTotal({ { price = 10 }, { price = 2 }, { price = 22 } }), 34)
  eq(rules.tabTotal(nil), 0)
end)

-- ---------------------------------------------------------------- what goes on display

test("gearshop: pieces nearest the shopper's level come first, in an order that never changes", function()
  local list = {}
  for i, level in ipairs({ 40, 49, 45, 44, 46, 45 }) do list[i] = { level = level, key = "k" .. i } end
  rules.order(list, 45)
  eq(list[1].key, "k3")
  eq(list[2].key, "k6")
  eq(list[3].level, 44)
  eq(list[4].level, 46)
  eq(list[5].level, 49)
  eq(list[6].level, 40)
end)

test("gearshop: pages of a chestful, wrapping after the last", function()
  local list = {}
  for i = 1, 120 do list[i] = i end
  local page, at, pages = rules.page(list, 1, 54)
  eq(#page, 54)
  eq(page[1], 1)
  eq(at, 1)
  eq(pages, 3)
  page, at = rules.page(list, 2, 54)
  eq(page[1], 55)
  eq(#page, 54)
  page, at = rules.page(list, 3, 54)
  eq(#page, 12)
  eq(page[12], 120)
  page, at = rules.page(list, 4, 54)
  eq(at, 1, "past the end is the first page again")
  eq(page[1], 1)
  page, at, pages = rules.page({}, 3, 54)
  eq(#page, 0)
  eq(at, 1)
  eq(pages, 1)
end)

test("gearshop: a search matches on type, level bracket, rarity and text", function()
  local piece = rules.piece(detail(45, "OMEGA", { prefixes = { { name = "Lucky Hit Chance" } } }))
  eq(rules.matches(piece, {}), true)
  eq(rules.matches(piece, { type = "the_vault:sword" }), true)
  eq(rules.matches(piece, { type = "the_vault:axe" }), false)
  eq(rules.matches(piece, { bracket = 4 }), true)
  eq(rules.matches(piece, { bracket = 5 }), false)
  eq(rules.matches(piece, { rarity = "OMEGA" }), true)
  eq(rules.matches(piece, { rarity = "LEGENDARY" }), false)
  eq(rules.matches(piece, { text = "LUCKY" }), true)
  eq(rules.matches(piece, { text = "mana" }), false)
  eq(rules.matches(piece, { text = "" }), true)
  eq(rules.matches(piece, { type = "the_vault:sword", bracket = 4, rarity = "OMEGA", text = "hit" }), true)
end)

test("gearshop: chests nearest the shopper fill first", function()
  local stations = {
    { id = "1", pos = { x = 30, y = 64, z = 0 } }, { id = "2", pos = { x = 10, y = 64, z = 0 } },
    { id = "3" }, { id = "4", pos = { x = 20, y = 64, z = 0 } },
  }
  local order = rules.nearest(stations, { x = 0, y = 64, z = 0 })
  eq(order[1].id, "2")
  eq(order[2].id, "4")
  eq(order[3].id, "1")
  eq(order[4].id, "3", "a chest with no known place comes last")
  order = rules.nearest(stations, nil)
  eq(order[1].id, "1", "with no idea where the shopper is, the owner's order")
  eq(order[4].id, "4")
end)

test("gearshop wings: each wing takes its own types, idols by their start, and Oddities the rest", function()
  eq(rules.inCategory("the_vault:sword", "Weapons", cfg), true)
  eq(rules.inCategory("the_vault:rang", "weapons", cfg), true, "any case")
  eq(rules.inCategory("the_vault:helmet", "Weapons", cfg), false)
  eq(rules.inCategory("the_vault:shield", "Armour", cfg), true)
  eq(rules.inCategory("the_vault:idol_benevolent", "Magic", cfg), true, "every idol")
  eq(rules.inCategory("the_vault:idolatry", "Magic", cfg), false, "a start of a word is not enough")
  eq(rules.inCategory("the_vault:magnet", "Oddities", cfg), true)
  eq(rules.inCategory("the_vault:sword", "Oddities", cfg), false, "Oddities is only what no other wing names")
  eq(rules.inCategory("the_vault:sword", nil, cfg), true, "no wing shows every type")
  eq(rules.inCategory("the_vault:sword", "Gone", cfg), true, "a wing that no longer exists is no wing")
  local list = { { type = "the_vault:axe" }, { type = "the_vault:boots" }, { type = "the_vault:magnet" }, { type = "the_vault:wand" } }
  eq(#rules.inCategoryList(list, "Armour", cfg), 1)
  eq(rules.inCategoryList(list, "Magic", cfg)[1].type, "the_vault:wand")
  eq(#rules.inCategoryList(list, nil, cfg), 4)
  -- the owner's own wings
  local own = { categories = { { name = "Blades", types = { "sword" } }, { name = "Else", rest = true } } }
  eq(rules.inCategory("the_vault:axe", "Else", own), true)
  eq(rules.inCategory("the_vault:sword", "Blades", own), true)
  eq(rules.category("Weapons", own), nil)
end)

test("gearshop wings: check-in fills the nearest chest of every wing first, then the nearest of the rest", function()
  local function ids(list)
    local out = {}
    for i, s in ipairs(list) do out[i] = s.id end
    return table.concat(out, " ")
  end
  local always = function() return true end
  -- nearest first: two Weapons chests by the shopper, then Armour, Magic, Oddities further off
  local stations = {
    { id = "w1", category = "Weapons" }, { id = "w2", category = "Weapons" }, { id = "a1", category = "Armour" },
    { id = "w3", category = "Weapons" }, { id = "m1", category = "Magic" }, { id = "o1", category = "Oddities" },
    { id = "a2", category = "Armour" },
  }
  eq(ids(rules.spread(stations, 6, always)), "w1 w2 a1 w3 m1 o1", "a chest in every wing, then the nearest left")
  eq(ids(rules.spread(stations, 3, always)), "w1 a1 m1", "fewer chests than wings: the nearest wings")
  eq(ids(rules.spread(stations, 6, function(c) return c ~= "Magic" end)), "w1 w2 a1 w3 o1 a2", "a wing with nothing to show is passed over")
  -- with no wings it is the nearest chests, as before
  local plain = { { id = "1" }, { id = "2" }, { id = "3" } }
  eq(ids(rules.spread(plain, 2, always)), "1 2")
  eq(ids(rules.spread(plain, 2, function() return false end)), "", "nothing in stock")
end)

test("gearshop wings: a chest's type picker only offers its wing's types", function()
  local s = drawStation(36, 10, 5, "types", nil, "Armour")
  local offered = {}
  for _, b in ipairs(s.buttons) do
    if b.id == "settype" then offered[#offered + 1] = b.value end
  end
  eq(table.concat(offered, " "), "the_vault:helmet the_vault:chestplate the_vault:leggings the_vault:boots the_vault:shield", "Armour")
  s = drawStation(15, 24, 5, "types", nil, "Oddities")
  offered = {}
  for _, b in ipairs(s.buttons) do
    if b.id == "settype" then offered[#offered + 1] = b.value end
  end
  eq(table.concat(offered, " "), "the_vault:magnet")
end)

test("gearshop: with nothing at the shopper's level, the nearest bracket that has stock", function()
  eq(rules.nearestBracket({ [4] = 3 }, 4), 4)
  eq(rules.nearestBracket({ [2] = 3, [7] = 1 }, 4), 2)
  eq(rules.nearestBracket({ [3] = 1, [5] = 1 }, 4), 3, "lower first on a tie")
  eq(rules.nearestBracket({ [10] = 1 }, 0), 10)
  eq(rules.nearestBracket({}, 4), nil)
end)

-- ---------------------------------------------------------------- the vault index, against pretend chests

--- Chests as the shop sees them: size, list, listDetailed and moveMany, with a count of every call and a move budget.
local function pretend(chests)
  local world = { chests = chests, calls = {}, budget = math.huge, down = {} }
  local function count(method) world.calls[method] = (world.calls[method] or 0) + 1 end
  world.io = {
    call = function(name, method, arg)
      local chest = chests[name]
      if not chest or world.down[name] then return false, "not attached" end
      count(method)
      if method == "size" then return true, chest.size end
      if method == "list" then
        local out = {}
        for slot, item in pairs(chest.items) do out[slot] = { name = item.name, count = item.count, nbt = item.nbt } end
        return true, out
      end
      if method == "listDetailed" then
        local out = {}
        for slot, item in pairs(chest.items) do out[slot] = item end
        return true, out
      end
      if method == "moveMany" then
        local moved, done = {}, 0
        for i, move in ipairs(arg) do
          if i > world.budget then break end
          local target = chests[move.to]
          if not target or world.down[move.to] then return false, "Target '" .. tostring(move.to) .. "' does not exist" end
          local item = chest.items[move.fromSlot]
          moved[i] = 0
          if item then
            for slot = 1, target.size do
              if not target.items[slot] then
                target.items[slot] = item
                chest.items[move.fromSlot] = nil
                moved[i] = 1
                break
              end
            end
          end
          done = i
        end
        return true, { moved = moved, done = done }
      end
      return false, "no such method"
    end,
  }
  function world.held(name)
    local n = 0
    for _ in pairs(chests[name].items) do n = n + 1 end
    return n
  end
  return world
end

local serial = 0
local function gear(kind, level, rarity)
  serial = serial + 1
  return { name = "the_vault:" .. kind, count = 1, nbt = "hash" .. serial,
    vaultData = { itemType = "Gear", level = level, rarity = rarity or "RARE", name = kind .. " " .. serial } }
end

local function vault()
  local swords, axes = {}, {}
  for i = 1, 20 do swords[i] = gear("sword", 40 + i % 10) end
  for i = 1, 6 do axes[i] = gear("axe", 12) end
  local world = pretend({
    v1 = { size = 27, items = swords }, v2 = { size = 27, items = axes }, v3 = { size = 27, items = {} },
    display = { size = 54, items = {} },
  })
  local stock = stockLib.new(world.io, { maxBatchMoves = 256, sellTypes = { "Gear" } })
  for _, name in ipairs({ "v1", "v2", "v3" }) do stock:add(name) end
  stock:indexAll()
  return world, stock
end

test("gearshop stock: the index counts every piece by type and bracket", function()
  local world, stock = vault()
  local s = stock:summary()
  eq(s.total, 26)
  eq(s.forSale, 26)
  eq(s.chests, 3)
  eq(s.slots, 81)
  eq(s.used, 26)
  eq(s.types["the_vault:sword"].total, 20)
  eq(s.types["the_vault:sword"].brackets[4], 20)
  eq(s.types["the_vault:axe"].brackets[1], 6)
  eq(#s.typeList, 2)
  eq(stock.chests.v1.cat, "the_vault:sword")
  eq(stock.chests.v3.cat, nil)
  eq(world.calls.listDetailed, 3, "one detailed read a chest")
  local near = stock:typesNear(4)
  eq(near[1].type, "the_vault:axe")
  eq(near[1].bracket, 1, "axes only exist at 10-19")
  eq(near[2].bracket, 4)
end)

test("gearshop stock: a second look at a chest is a plain list, with details only for something new", function()
  local world, stock = vault()
  stock:index("v1")
  eq(world.calls.listDetailed, 3, "nothing new: no detailed read")
  world.chests.v1.items[25] = gear("helmet", 77)
  stock:index("v1")
  eq(world.calls.listDetailed, 4, "a new piece is read in detail")
  eq(stock:summary().types["the_vault:helmet"].brackets[7], 1)
  world.chests.v1.items[25] = nil
  stock:index("v1")
  eq(stock:summary().total, 26, "a piece the owner took out is gone from the index")
end)

test("gearshop stock: taking pieces moves them and takes them off the index", function()
  local world, stock = vault()
  local list = stock:select("the_vault:sword", 4, 45)
  eq(#list, 20)
  eq(list[1].level, 45, "nearest the shopper's level first")
  local page = rules.page(list, 1, 8)
  eq(stock:take(page, "display"), 8)
  eq(world.held("display"), 8)
  eq(world.held("v1"), 12)
  eq(stock:summary().total, 18)
  eq(#stock:select("the_vault:sword", 4, 45), 12)
end)

test("gearshop stock: a batch the server cuts short is sent again from where it stopped", function()
  local world, stock = vault()
  world.budget = 3
  local list = stock:select("the_vault:sword", 4, 45)
  eq(stock:take(list, "display"), 20)
  eq(world.held("display"), 20)
  eq(world.calls.moveMany, 7, "20 moves at 3 a call")
  local slots = {}
  for slot, item in pairs(world.chests.display.items) do slots[slot] = rules.key(item) end
  local moved, _, stuck = stock:put("display", slots)
  eq(moved, 20)
  eq(stuck, 0)
  eq(world.held("display"), 0)
  eq(world.held("v1"), 20, "each piece went back to the chest it came from")
end)

test("gearshop stock: batches are never longer than the server allows", function()
  local world, stock = vault()
  stock.cfg.maxBatchMoves = 6
  local longest = 0
  local real = world.io.call
  world.io.call = function(name, method, arg)
    if method == "moveMany" then longest = math.max(longest, #arg) end
    return real(name, method, arg)
  end
  eq(stock:take(stock:select("the_vault:sword", 4, 45), "display"), 20)
  eq(longest, 6)
end)

test("gearshop stock: a piece goes to a chest of its type, then an empty chest, then anywhere", function()
  local world, stock = vault()
  world.chests.intake = { size = 27, items = { gear("axe", 30), gear("helmet", 50), gear("helmet", 51) } }
  local ok, list = stock:listKnown("intake")
  truthy(ok)
  local slots = {}
  for slot, item in pairs(list) do slots[slot] = rules.key(item) end
  local moved, _, stuck = stock:put("intake", slots)
  eq(moved, 3)
  eq(stuck, 0)
  eq(world.held("v2"), 7, "the axe joined the axes")
  eq(world.held("v3"), 2, "the helmets took the empty chest, together")
  eq(stock.chests.v3.cat, "the_vault:helmet")
  eq(stock:summary().total, 29)
end)

test("gearshop stock: a chest that turns out to be full is passed over, and what fits nowhere is reported", function()
  local world, stock = vault()
  -- the owner filled the axe chest behind the shop's back
  for slot = 7, 27 do world.chests.v2.items[slot] = gear("axe", 12) end
  world.chests.intake = { size = 27, items = { gear("axe", 30) } }
  local _, list = stock:listKnown("intake")
  local moved, _, stuck = stock:put("intake", { [1] = rules.key(list[1]) })
  eq(moved, 1)
  eq(stuck, 0)
  eq(world.held("v2"), 27)
  eq(world.held("intake"), 0)
  -- and with every chest full nothing is lost: it stays where it was
  for _, name in ipairs({ "v1", "v2", "v3" }) do
    for slot = 1, 27 do world.chests[name].items[slot] = world.chests[name].items[slot] or gear("sword", 1) end
    stock:index(name)
  end
  world.chests.intake.items[1] = gear("axe", 31)
  _, list = stock:listKnown("intake")
  moved, _, stuck = stock:put("intake", { [1] = rules.key(list[1]) })
  eq(moved, 0)
  eq(stuck, 1)
  eq(world.held("intake"), 1)
end)

test("gearshop stock: a chest whose computer has unloaded fails cleanly and is offered again when it is back", function()
  local world, stock = vault()
  world.down.v1 = true
  eq(stock:index("v1"), false)
  eq(stock:summary().total, 6, "its pieces are not offered while it is away")
  eq(#stock:select("the_vault:sword", 4, 45), 0)
  eq(stock:take({ { chest = "v1", slot = 1, key = "x" } }, "display"), 0)
  world.down.v1 = nil
  eq(stock:index("v1"), true)
  eq(stock:summary().total, 26)
end)

test("gearshop stock: the slow look goes round the chests that are not watched", function()
  local _, stock = vault()
  local seen = {}
  for _ = 1, 4 do seen[#seen + 1] = stock:nextTurn({ v2 = true }) end
  eq(table.concat(seen, " "), "v1 v3 v1 v3")
  eq(stock:nextTurn({ v1 = true, v2 = true, v3 = true }), nil)
end)

-- ---------------------------------------------------------------- detectors: a display chest needs none of its own

local shopLib = require("lib.gearshop.shop")
local store = require("lib.gearshop.store")

--- Player detectors as the shop sees them, each at a place, and players at theirs. getPlayerPos works server-wide, as
-- Advanced Peripherals does with its position function on; the range calls only see players near that detector.
local function detectorWorld(detectors, players)
  local world = { calls = {} }
  local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
  end
  world.io = {
    names = function()
      local list = { "top" }
      for name in pairs(detectors) do list[#list + 1] = name end
      table.sort(list)
      return list
    end,
    hasType = function(name, kind)
      if name == "top" then return kind == "modem" end
      return detectors[name] ~= nil and kind == "playerDetector"
    end,
    call = function(name, method, a, b)
      local at = detectors[name]
      if not at then return false, "not attached" end
      world.calls[#world.calls + 1] = name .. "." .. method
      if method == "getPlayerPos" then
        local p = players[a]
        if not p then return true, {} end -- offline, another server or dimension: an empty table, as Advanced Peripherals answers
        return true, { x = p.x, y = p.y, z = p.z, dimension = "minecraft:overworld" }
      elseif method == "isPlayerInRange" then
        local p = players[b]
        return true, p ~= nil and distance(p, at) <= a
      elseif method == "getPlayersInRange" then
        local out = {}
        for who, p in pairs(players) do
          if distance(p, at) <= a then out[#out + 1] = who end
        end
        table.sort(out)
        return true, out
      end
      return false, "no such method"
    end,
  }
  return world
end

local function none() return false end

test("gearshop setup: a display chest with no detector of its own records where the owner stands through the door's", function()
  local players = { Akkiruk = { x = 110, y = 64, z = 0 } }
  local world = detectorWorld({ ["12:door"] = { x = 90, y = 64, z = 0 } }, players)
  local assigned = function(name) return name == "12:door" end
  local found, why = shopLib.standAt(world.io, "Akkiruk", true, assigned)
  truthy(found, why)
  eq(found.detector, nil, "the door's detector is not taken as the chest's own")
  eq(found.pos.x, 110)
  eq(found.pos.z, 0)

  -- the same with the door's detector still free but out of reach of the chest: the old setup said "no free detector"
  found, why = shopLib.standAt(world.io, "Akkiruk", true, none)
  truthy(found, why)
  eq(found.detector, nil, "a detector 20 blocks away is not the chest's")
  eq(found.pos.x, 110)

  -- and for the kiosk, the same step
  players.Akkiruk = { x = 100, y = 64, z = 20 }
  found = shopLib.standAt(world.io, "Akkiruk", true, assigned)
  eq(found.detector, nil)
  eq(found.pos.z, 20)
end)

test("gearshop setup: a display chest's own detector is still found and used when it has one", function()
  local players = { Akkiruk = { x = 110, y = 64, z = 0 } }
  local world = detectorWorld({
    ["12:door"] = { x = 90, y = 64, z = 0 }, ["12:d1"] = { x = 111, y = 64, z = 0 }, ["12:d2"] = { x = 130, y = 64, z = 0 },
  }, players)
  local found = shopLib.standAt(world.io, "Akkiruk", true, function(name) return name == "12:door" end)
  eq(found.detector, "12:d1")
  eq(found.pos.x, 110)
  eq(world.calls[#world.calls], "12:d1.getPlayerPos", "its position comes from its own detector first")

  -- two free detectors as near as each other still stop the step: either could be the chest's
  world = detectorWorld({ ["12:a"] = { x = 108, y = 64, z = 0 }, ["12:b"] = { x = 112, y = 64, z = 0 } }, players)
  local again, why = shopLib.standAt(world.io, "Akkiruk", true, none)
  eq(again, nil)
  truthy(why:find("as near as each other", 1, true), why)
end)

test("gearshop setup: a step with no detector to offer, or no way to see the owner, says so", function()
  local players = { Akkiruk = { x = 110, y = 64, z = 0 } }
  local found, why = shopLib.standAt(detectorWorld({}, players).io, "Akkiruk", true, none)
  eq(found, nil)
  truthy(why:find("No player detector", 1, true), why)
  found, why = shopLib.standAt(detectorWorld({ ["12:door"] = { x = 90, y = 64, z = 0 } }, {}).io, "Akkiruk", true, none)
  eq(found, nil, "the owner is on another server")
  truthy(why:find("Press Enter to try again", 1, true), why)
  -- a step that offers no detector of its own gets the position the same way
  found = shopLib.standAt(detectorWorld({ ["12:door"] = { x = 200, y = 64, z = 0 } }, players).io, "Akkiruk", false, none)
  eq(found.detector, nil)
  eq(found.pos.x, 110)
end)

--- A shop set up with no detector at any display chest or the kiosk, only one at the door.
local function shopWithoutStationDetectors(players)
  local world = detectorWorld({ ["12:door"] = { x = 90, y = 64, z = 0 } }, players)
  local setup = store.newSetup()
  setup.door = { monitor = "12:m0", detector = "12:door", pos = { x = 90, y = 64, z = 0 } }
  -- in the owner's order, which is not nearest-first: chest 1 is the far one
  for i, x in ipairs({ 140, 100, 120 }) do
    setup.stations[i] = { monitor = "12:m" .. i, chest = "12:c" .. i, pos = { x = x, y = 64, z = 0 } }
  end
  setup.kiosk = { monitor = "12:m20", chest = "12:c20", pos = { x = 100, y = 64, z = 20 } }
  return shopLib.new(world.io, rules.DEFAULTS, setup, store.newState()), world
end

test("gearshop: with no detectors at the display chests, they still fill nearest the shopper first", function()
  local players = { Alice = { x = 95, y = 64, z = 0 } }
  local shop = shopWithoutStationDetectors(players)
  local pos, answered = shop:playerPos("Alice")
  truthy(answered, "the door's detector answers")
  eq(pos.x, 95)
  local order = rules.nearest(shop.stations, pos)
  eq(order[1].id, "2", "x=100 first")
  eq(order[2].id, "3", "then x=120")
  eq(order[3].id, "1", "the far one last")
  players.Alice = { x = 145, y = 64, z = 0 }
  order = rules.nearest(shop.stations, (shop:playerPos("Alice")))
  eq(order[1].id, "1", "a shopper at the far end gets the far chest first")

  -- a shopper on another server: the detector answers that they are not here
  pos, answered = shop:playerPos("Bob")
  eq(pos, nil)
  eq(answered, true)
end)

test("gearshop: any attached detector answers where a player is, after the ones with a job", function()
  local players = { Alice = { x = 95, y = 64, z = 0 } }
  local world = detectorWorld({ ["12:spare"] = { x = 0, y = 64, z = 0 } }, players)
  local setup = store.newSetup()
  setup.stations[1] = { monitor = "12:m1", chest = "12:c1", pos = { x = 100, y = 64, z = 0 } }
  local shop = shopLib.new(world.io, rules.DEFAULTS, setup, store.newState())
  eq(table.concat(shop:detectors(), " "), "12:spare")
  eq(shop:playerPos("Alice").x, 95)
  shop = shopWithoutStationDetectors(players)
  eq(table.concat(shop:detectors(), " "), "12:door", "the door's is listed once")
end)

test("gearshop: a piece taken from a chest with no detector is charged to the shopper the chest is locked to", function()
  local players = { Alice = { x = 100, y = 64, z = 0 }, Bob = { x = 100, y = 64, z = 1 } }
  local shop = shopWithoutStationDetectors(players)
  shop.state.shoppers.Alice = { at = 0, last = 0, level = 45 }
  shop.state.shoppers.Bob = { at = 0, last = 0, level = 12 }
  shop:ds(shop.stations[2]).shopper = "Bob"
  shop:ds(shop.stations[3]).shopper = "Alice"
  eq(shop:taker(shop.stations[2]), "Bob", "Bob's chest, though Alice stands as near")
  eq(shop:taker(shop.stations[3]), "Alice")
  shop:ds(shop.kiosk).shopper = "Alice"
  eq(shop:taker(shop.kiosk), "Alice", "the kiosk's pickup chest the same")
end)
