-- gearshop_test.lua
-- The gear shop's rules (prices, what it buys, the tab, store credit) and its vault index against pretend chests.
-- The whole shop on emulated computers is tested from craftos-agent (tools/geartest).

local testing = require("testing")
local rules = require("lib.gearshop.rules")
local stockLib = require("lib.gearshop.stock")

local test, eq, truthy = testing.test, testing.eq, testing.truthy
local cfg = rules.DEFAULTS

-- ---------------------------------------------------------------- prices

test("gearshop: a piece costs 1 token per level, and never less than 1", function()
  eq(rules.price(1), 1, "level 1")
  eq(rules.price(9), 9, "level 9")
  eq(rules.price(40), 40, "level 40")
  eq(rules.price(49), 49, "level 49")
  eq(rules.price(50), 50, "level 50")
  eq(rules.price(100), 100, "level 100")
  eq(rules.price(0), 1, "level 0 costs the minimum")
  eq(rules.price(nil), 1, "no level costs the minimum")
  eq(rules.price(-5), 1, "a bad level costs the minimum")
  for level = 1, 120 do
    eq(rules.price(level), level, "level " .. level)
  end
  eq(rules.DEFAULTS.pricePerLevel, 1)
  eq(rules.DEFAULTS.minPrice, 1)
end)

test("gearshop: the price per level and the minimum are the owner's to change", function()
  eq(rules.price(45, { pricePerLevel = 2, minPrice = 1 }), 90, "2 a level at 45")
  eq(rules.price(3, { pricePerLevel = 1, minPrice = 5 }), 5, "a minimum of 5")
  eq(rules.price(45, { pricePerLevel = 0.5, minPrice = 1 }), 23, "half a token a level rounds to whole tokens")
  eq(rules.price(0, { pricePerLevel = 1, minPrice = 0 }), 0, "no minimum")
end)

test("gearshop: the price range of a level bracket", function()
  local low, high = rules.bracketPrices(0)
  eq(low, 1) eq(high, 9)
  low, high = rules.bracketPrices(4)
  eq(low, 40) eq(high, 49)
  low, high = rules.bracketPrices(10)
  eq(low, 100) eq(high, 100)
  eq(rules.priceRange(40, 49), "40-49")
  eq(rules.priceRange(100, 100), "100")
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
  eq(select(2, rules.accepts(rules.piece(detail(80, "EPIC")), cfg)), "Omega+ above 70")
  eq(select(2, rules.accepts(rules.piece(detail(100, "OMEGA")), cfg)), "Legendary only at 100")
end)

test("gearshop: a piece sold for tokens is worth 1 token, so there is nothing to carry", function()
  eq(rules.DEFAULTS.tokensPerPiece, 1)
  eq(rules.pieceMilli(cfg), 1000)
  local tokens, carry = rules.settleSale(0, 7, cfg)
  eq(tokens, 7)
  eq(carry, 0)
  tokens, carry = rules.settleSale(nil, 0, cfg)
  eq(tokens, 0)
  eq(carry, 0)
  -- a fraction carried from the old rate stays the seller's, and is paid once it makes a token
  tokens, carry = rules.settleSale(700, 3, cfg)
  eq(tokens, 3)
  eq(carry, 700)
  -- an owner's fractional rate still carries, and nothing is lost however a seller splits their pieces up
  local half = { tokensPerPiece = 0.5 }
  local total, left = 0, 0
  for n = 1, 37 do
    local t
    t, left = rules.settleSale(left, n % 4, half)
    total = total + t
  end
  local pieces = 0
  for n = 1, 37 do pieces = pieces + n % 4 end
  eq(total * 1000 + left, pieces * 500, "tokens paid plus the carry is every piece's worth")
end)

test("gearshop: each sold piece is 1 store credit", function()
  eq(rules.DEFAULTS.creditPerPiece, 1)
  eq(rules.creditMilli(10, cfg), 10000)
  eq(rules.creditMilli(1, cfg), 1000)
  eq(rules.creditMilli(0, cfg), 0)
  eq(rules.creditMilli(10, { creditPerPiece = 2 }), 20000, "the owner's own rate")
  eq(rules.creditMilli(3, { creditPerPiece = 0.5 }), 1500)
  eq(rules.pieceMilli({ tokensPerPiece = 2 }), 2000)
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
  truthy(empty:find("store credit: 1 a piece", 1, true), "an empty chest says what a piece gives")
  local three = drawSell(cfg, sellView(3))
  truthy(three:find("Buying: 3", 1, true), "how many are bought")
  truthy(three:find("You get 3 store credit", 1, true), "what the seller gets")
end)

test("gearshop: with sellForTokens on the sell screen is as before: TOKENS or STORE CREDIT", function()
  local text, buttons = drawSell(tokensOn, sellView(3))
  eq(buttons, "tokens:TOKENS,credit:STORE CREDIT")
  truthy(text:find("tokens 3", 1, true), "what three pieces make in tokens")
  truthy(text:find("or store credit 3", 1, true), "and in credit")
  local empty = drawSell(tokensOn, sellView(0))
  truthy(empty:find("Each piece pays 1 token, or 1 in store credit.", 1, true), "the rate line")
end)

--- A display chest's monitor at a size, open for Alice (tab 20, credit 1.5) with `n` pieces in it, or on its type picker.
local function drawStation(w, h, n, mode, note, wing, opts)
  opts = opts or {}
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
  local ds = { shopper = "Alice", type = "the_vault:sword", bracket = 4, phase = "open", page = opts.page or 1, pages = 3, total = n, shown = shown, prices = {} }
  if opts.free then ds = { shown = {}, prices = {} } end
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
  ui.station(s, shop, { id = "1", kind = "station", category = wing, gearType = opts.gearType }, { mode = mode })
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
        -- the whole screen behind the buttons, so a tap by someone else off them is answered
        if b.id ~= "claim" then
          eq(b.h, bh, where .. " is big enough to tap")
          truthy(b.label:match("%a%a"), where .. " has a whole label: " .. b.label)
          ids[#ids + 1] = b.id
        end
      end
      local text = table.concat(s.text, " "):gsub("%s+", " ")
      local where = w .. "x" .. h
      if mode then
        truthy(table.concat(ids, " "):find("settype settype", 1, true), where .. " types to pick")
        truthy(table.concat(ids, " "):find("back", 1, true), where .. " BACK")
      else
        eq(table.concat(ids, " "), w < 24 and "types pay level level next done" or "types level level next pay done", where .. " every button")
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

test("gearshop stations: a station of one type is titled with it when free, and has no TYPE picker in use", function()
  local flat = function(s) return (table.concat(s.text, " "):gsub("%s+", " ")) end
  for _, size in ipairs({ { 36, 10 }, { 15, 24 }, { 57, 24 } }) do
    local w, h = size[1], size[2]
    local where = w .. "x" .. h
    local s = drawStation(w, h, 0, nil, nil, "Weapons", { gearType = "the_vault:sword", free = true })
    local text = flat(s)
    truthy(text:find("SWORDS", 1, true), where .. " the type as the title: " .. text)
    if w >= 22 then truthy(s.text[1]:find("SWORDS - tap to browse", 1, true), where .. " the whole title") end
    truthy(text:find("TAP TO OPEN", 1, true), where .. " tap to open")
    truthy(text:find("15 in stock", 1, true), where .. " how many")
    eq(#s.buttons, 2, where .. " the whole screen, and PAY")
    eq(s.buttons[1].id, "claim")
    eq(s.buttons[2].id, "pay", where .. " PAY on a free station too")
    truthy(s.buttons[2].x >= 1 and s.buttons[2].y + s.buttons[2].h - 1 <= h, where .. " PAY fits")
    s = drawStation(w, h, 30, nil, nil, "Weapons", { gearType = "the_vault:sword", page = 2 })
    local ids = {}
    for _, b in ipairs(s.buttons) do
      truthy(b.x >= 1 and b.y >= 1 and b.x + b.w - 1 <= w and b.y + b.h - 1 <= h, where .. " " .. b.id .. " fits")
      ids[#ids + 1] = b.id
    end
    eq(table.concat(ids, " "), w < 24 and "claim level level next done pay" or "claim level level pay next done", where .. " no TYPE, and PAY")
    text = flat(s)
    truthy(text:find("In use by Alice", 1, true), where .. " whose station, for everyone who looks")
    truthy(text:find("Page 2 of 3", 1, true), where .. " the page")
    truthy(text:find("10 each", 1, true), where .. " the price")
  end
  local s = drawStation(36, 10, 12, nil, "In use by Alice. Free in ~4 min if unused.", nil, { gearType = "the_vault:sword" })
  truthy(flat(s):find("In use by Alice. Free in ~4 min if unused.", 1, true), "the note for someone else: " .. flat(s))
  s = drawStation(36, 10, 0, nil, nil, nil, { gearType = "the_vault:sword" })
  truthy(flat(s):find("Try LV - or LV +", 1, true), "nothing at this level")
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

test("gearshop stations: the owner's word for a gear type, its wing and its title", function()
  local known = { "the_vault:axe", "the_vault:idol_benevolent", "the_vault:sword" }
  eq(rules.gearTypeFor("sword", known, cfg), "the_vault:sword")
  eq(rules.gearTypeFor(" Swords ", known, cfg), "the_vault:sword", "any case, a plural")
  eq(rules.gearTypeFor("idol benevolent", known, cfg), "the_vault:idol_benevolent", "spaces for underscores")
  eq(rules.gearTypeFor("the_vault:magnet", known, cfg), "the_vault:magnet", "a full id as typed")
  eq(rules.gearTypeFor("helmet", known, cfg), "the_vault:helmet", "none in stock yet, but a wing names it")
  eq(rules.gearTypeFor("boots", known, cfg), "the_vault:boots", "a name that ends in s")
  eq(rules.gearTypeFor("Shoes", known, cfg), nil, "nobody has heard of it")
  eq(rules.gearTypeFor("idol", known, cfg), "the_vault:idol", "a family: every idol")
  eq(rules.gearTypeFor("Idols", { "the_vault:sword" }, cfg), "the_vault:idol", "a family a wing names, none in stock yet")
  eq(rules.ofType("the_vault:idol_benevolent", "the_vault:idol"), true, "an idol is of the idol family")
  eq(rules.ofType("the_vault:idolatry", "the_vault:idol"), false, "a start of a word is not enough")
  eq(rules.ofType("the_vault:sword", "the_vault:sword"), true)
  eq(rules.ofType("the_vault:axe", "the_vault:sword"), false)
  local counts = rules.typeCounts({ types = {
    ["the_vault:idol_benevolent"] = { total = 3, brackets = { [4] = 2, [5] = 1 } },
    ["the_vault:idol_timekeeper"] = { total = 2, brackets = { [4] = 2 } },
    ["the_vault:sword"] = { total = 9, brackets = { [4] = 9 } },
  } }, "the_vault:idol")
  eq(counts.total, 5, "every idol counted together")
  eq(counts.brackets[4], 4)
  eq(counts.brackets[5], 1)
  eq(rules.typeCounts({ types = {} }, "the_vault:idol"), nil, "none in stock")
  eq(rules.typePlural("the_vault:idol"), "Idols")
  eq(rules.wingOf("the_vault:idol", cfg), "Magic")
  eq(rules.gearTypeFor("", known, cfg), nil)
  eq(rules.wingOf("the_vault:sword", cfg), "Weapons")
  eq(rules.wingOf("the_vault:idol_malevolent", cfg), "Magic")
  eq(rules.wingOf("the_vault:magnet", cfg), "Oddities", "what no wing names: the rest")
  eq(rules.typePlural("the_vault:sword"), "Swords")
  eq(rules.typePlural("the_vault:leggings"), "Leggings")
  eq(rules.typePlural("the_vault:boots"), "Boots")
  eq(rules.typePlural("the_vault:idol_benevolent"), "Idol Benevolent")
  eq(rules.DEFAULTS.stationsPerShopper, 3)
  eq(rules.DEFAULTS.chestsPerShopper, nil, "check-in fills nothing any more")
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

-- ---------------------------------------------------------------- refused gear: the returns chest and DONATE

--- A sell point with pretend chests (sell, returns, junk), a detector by it, and a shop whose writes are counted instead of
-- written. crashAt names a write the computer goes down at, before it is made.
local function sellPoint(opts)
  opts = opts or {}
  if not os.epoch then os.epoch = function() return os.time() * 1000 end end
  local world = pretend({
    sell = { size = 27, items = {} }, returns = { size = 27, items = {} }, junk = { size = 27, items = {} },
  })
  local players = opts.players or { Bob = { x = 1, y = 64, z = 0 } }
  local call = world.io.call
  world.io.names = function() return { "det" } end
  world.io.hasType = function(name, kind) return name == "det" and kind == "playerDetector" end
  world.io.call = function(name, method, a)
    if name == "det" then
      if method == "getOnlinePlayers" then
        local out = {}
        for who in pairs(players) do out[#out + 1] = who end
        table.sort(out)
        return true, out
      elseif method == "getPlayerPos" then
        return true, players[a] or {}
      end
      return false, "no such method"
    end
    return call(name, method, a)
  end
  local setup = store.newSetup()
  setup.sell = { monitor = "msell", chest = "sell", pos = { x = 0, y = 64, z = 0 } }
  if opts.returns ~= false then setup.returns = { chest = "returns" } end
  if opts.junk ~= false then setup.junk = { chest = "junk" } end
  local state = opts.state or store.newState()
  local shop = shopLib.new(world.io, rules.DEFAULTS, setup, state)
  shop.ready = true
  shop.saves = {}
  shop.save = function(self, why)
    if opts.crashAt == why then error("crash at " .. why, 0) end
    self.saves[#self.saves + 1] = why
  end
  return shop, world, state
end

local function unidentified(kind)
  local g = gear(kind, 30, "RARE")
  g.vaultData.state = "UNIDENTIFIED"
  return g
end

test("gearshop sell: refused gear goes to the returns chest at once, with whose it is and why", function()
  local shop, world, state = sellPoint()
  local bought = gear("sword", 40, "EPIC")
  world.chests.sell.items = { bought, gear("sword", 71, "EPIC"), unidentified("axe"), gear("helmet", 20, "RARE") }
  shop:sellScan()
  eq(world.held("sell"), 1, "only what the shop buys is left in the sell chest")
  eq(world.chests.sell.items[1], bought)
  eq(world.held("returns"), 3, "the three refused pieces are in the returns chest")
  local whose = 0
  for _, by in pairs(state.returnsBy) do
    eq(by, "Bob", "Bob was standing at the sell point")
    whose = whose + 1
  end
  eq(whose, 3)
  eq(table.concat(shop.saves, " "), "refuse-begin refuse-done", "the move is written down before and after")
  eq(#shop.sellView.accepted, 1)
  eq(#shop.sellView.rejected, 0)
  local why = {}
  for _, entry in ipairs(shop.refused.entries) do
    local what = entry.grade and ("L" .. entry.level .. " " .. entry.grade) or entry.label
    why[#why + 1] = what .. ": " .. entry.why
  end
  table.sort(why)
  truthy(table.concat(why, " | "):match("^L20 RARE: Epic%+ only | L71 EPIC: Omega%+ above 70 | axe %d+: identify it first$"), table.concat(why, " | "))
  -- taken out of the returns chest by its owner: forgotten
  world.chests.returns.items = {}
  shop:pruneReturns()
  eq(next(state.returnsBy), nil)
end)

test("gearshop sell: with nobody near the sell point the record says someone, and with no returns chest nothing moves", function()
  local shop, world, state = sellPoint({ players = { Bob = { x = 40, y = 64, z = 0 } } })
  world.chests.sell.items = { gear("sword", 20, "RARE") }
  shop:sellScan()
  local _, by = next(state.returnsBy)
  eq(by, "?")
  shop, world = sellPoint({ returns = false })
  world.chests.sell.items = { gear("sword", 20, "RARE") }
  shop:sellScan()
  eq(world.held("sell"), 1, "it stays in the sell chest, as before")
  eq(#shop.sellView.rejected, 1)
  eq(#shop.saves, 0, "nothing was written")
end)

test("gearshop sell: DONATE gives the tapper's refused gear to the junk chest, never to stock", function()
  local shop, world, state = sellPoint({ players = { Bob = { x = 1, y = 64, z = 0 }, Alice = { x = 30, y = 64, z = 0 } } })
  world.chests.sell.items = { gear("sword", 20, "RARE"), gear("axe", 20, "RARE") }
  shop:sellScan()
  -- one more, left by someone else
  local alices = gear("helmet", 20, "RARE")
  world.chests.returns.items[5] = alices
  state.returnsBy[rules.key(alices)] = "Alice"
  shop:donate("Bob", "msell")
  eq(world.held("junk"), 2, "Bob's two")
  eq(world.held("returns"), 1, "Alice's stays")
  eq(state.stats.donated, 2)
  eq(state.returnsBy[rules.key(alices)], "Alice")
  local left = 0
  for _ in pairs(state.returnsBy) do left = left + 1 end
  eq(left, 1, "only Alice's is still recorded")
  eq(shop.stock:summary().total, 0, "nothing went into stock")
  -- with no returns chest, DONATE takes the refused gear straight from the sell chest, and leaves what is bought
  shop, world = sellPoint({ returns = false })
  local epic = gear("sword", 20, "EPIC")
  world.chests.sell.items = { epic, gear("axe", 20, "RARE") }
  shop:donate("Bob", "msell")
  eq(world.held("junk"), 1)
  eq(world.chests.sell.items[1], epic)
  -- and with no junk chest there is no DONATE
  shop, world = sellPoint({ junk = false })
  world.chests.sell.items = { gear("axe", 20, "RARE") }
  shop:sellScan()
  shop:donate("Bob", "msell")
  eq(world.held("returns"), 1)
end)

test("gearshop sell: a reboot at any step of moving refused gear finishes the move once", function()
  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
  end
  for _, point in ipairs({ "refuse-begin", "refuse-done", "donate-begin", "donate-done" }) do
    local donate = point:find("donate", 1, true) ~= nil
    local shop, world = sellPoint()
    -- what is on disk: each write as it was made; the computer goes down at `point`, before that write is made
    local disk = store.newState()
    shop.save = function(self, why)
      if why == point then error("crash at " .. why, 0) end
      disk = copy(self.state)
    end
    world.chests.sell.items = { gear("sword", 20, "RARE"), gear("axe", 71, "EPIC") }
    if donate then
      shop:sellScan()
      eq(world.held("returns"), 2, point .. ": refused first")
      eq(pcall(shop.donate, shop, "Bob", "msell"), false, point .. " went down")
    else
      eq(pcall(shop.sellScan, shop), false, point .. " went down")
    end
    -- back up, on the same chests and the state as it was last written
    local state = copy(disk)
    local again = shopLib.new(world.io, rules.DEFAULTS, shop.setup, state)
    again.ready = true
    again.save = function() end
    if point:find("begin", 1, true) then
      -- the write that would have begun the move was never made: nothing moved, and the next look starts it again
      eq(state.moving, nil, point)
      eq(world.held(donate and "junk" or "returns"), 0, point .. ": nothing moved")
      if donate then again:donate("Bob", "msell") else again:sellScan() end
    else
      truthy(state.moving, point .. ": the move is still written down")
      if again.state.moving then again:finishMove() end
    end
    eq(state.moving, nil, point .. ": finished")
    local where = donate and "junk" or "returns"
    eq(world.held(where), 2, point .. ": both pieces in " .. where .. ", once")
    eq(world.held("sell"), 0, point)
    eq(world.held(donate and "returns" or "junk"), 0, point)
    local recorded = 0
    for _ in pairs(state.returnsBy) do recorded = recorded + 1 end
    eq(recorded, donate and 0 or 2, point .. ": the record")
    if donate then eq(state.stats.donated, 2, point .. ": counted once") end
  end
end)

-- ---------------------------------------------------------------- one station per gear type

--- Three stations (two of swords, one of axes) over pretend vault chests, with Alice (level 45) and Bob (level 12) checked
-- in, and a shop whose writes are copied to a pretend disk.
local function stationShop(opts)
  opts = opts or {}
  if not os.epoch then os.epoch = function() return os.time() * 1000 end end
  local swords, axes = {}, {}
  for _ = 1, 6 do swords[#swords + 1] = gear("sword", 45) end
  for _ = 1, 4 do swords[#swords + 1] = gear("sword", 12) end
  for _ = 1, 2 do swords[#swords + 1] = gear("sword", 75) end
  for _ = 1, 3 do axes[#axes + 1] = gear("axe", 45) end
  local world = opts.world or pretend({
    v1 = { size = 54, items = swords }, v2 = { size = 54, items = axes }, v3 = { size = 54, items = {} },
    c1 = { size = 54, items = {} }, c2 = { size = 54, items = {} }, c3 = { size = 54, items = {} },
  })
  local cfgHere = {}
  for k, v in pairs(rules.DEFAULTS) do cfgHere[k] = v end
  for k, v in pairs(opts.limits or {}) do cfgHere[k] = v end
  local setup = store.newSetup()
  setup.stations = {
    { monitor = "m1", chest = "c1", pos = { x = 10, y = 64, z = 0 }, gearType = "the_vault:sword", category = "Weapons" },
    { monitor = "m2", chest = "c2", pos = { x = 20, y = 64, z = 0 }, gearType = "the_vault:sword", category = "Weapons" },
    { monitor = "m3", chest = "c3", pos = { x = 30, y = 64, z = 0 }, gearType = "the_vault:axe", category = "Weapons" },
  }
  local state = opts.state
  if not state then
    state = store.newState()
    state.shoppers.Alice = { at = 0, last = os.epoch("utc"), level = 45 }
    state.shoppers.Bob = { at = 0, last = os.epoch("utc"), level = 12 }
  end
  world.io.names = function() return {} end
  world.io.hasType = function() return false end
  local shop = shopLib.new(world.io, cfgHere, setup, state)
  for _, name in ipairs({ "v1", "v2", "v3" }) do shop.stock:add(name) end
  shop.stock:indexAll()
  shop.ready = true
  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
  end
  local disk = { state = copy(state), copy = copy }
  shop.save = function(self, why)
    if opts.crashAt == why then error("crash at " .. why, 0) end
    self:changed()
    disk.state = copy(self.state)
  end
  return shop, world, disk
end

--- The shop's books need a disk: a pretend one with nothing on it.
local function withDisk(fn)
  return function()
    local had = rawget(_G, "fs")
    if not had then rawset(_G, "fs", { exists = function() return false end }) end
    local ok, err = pcall(fn)
    if not had then rawset(_G, "fs", nil) end
    if not ok then error(err, 0) end
  end
end

local function all(world)
  local n = 0
  for name in pairs(world.chests) do n = n + world.held(name) end
  return n
end

local function levelsIn(world, chest)
  local out = {}
  for _, item in pairs(world.chests[chest].items) do out[#out + 1] = item.vaultData.level end
  table.sort(out)
  return table.concat(out, " ")
end

test("gearshop stations: check-in fills nothing; a tap fills the station's type at the shopper's level, and it is theirs", withDisk(function()
  local shop, world = stationShop()
  local s1, s2, s3 = shop.stations[1], shop.stations[2], shop.stations[3]
  eq(world.held("c1") + world.held("c2") + world.held("c3"), 0, "nothing on display before anyone taps")
  shop:stationAction(s1, "Alice", "claim")
  local ds = shop:ds(s1)
  eq(ds.shopper, "Alice")
  eq(ds.type, "the_vault:sword")
  eq(ds.bracket, 4, "her bracket")
  eq(ds.phase, "open")
  eq(levelsIn(world, "c1"), "45 45 45 45 45 45")
  -- Bob wants swords too: Alice's station tells him whose it is, and roughly when it frees
  shop:stationAction(s1, "Bob", "claim")
  eq(shop:noteFor("m1"), "In use by Alice. Free in ~5 min if unused.")
  eq(ds.shopper, "Alice", "still hers")
  shop:stationAction(s1, "Bob", "next")
  eq(ds.page, 1, "his tap on her buttons changes nothing")
  -- the other sword station is his, at his own bracket
  shop:stationAction(s2, "Bob", "claim")
  eq(shop:ds(s2).shopper, "Bob")
  eq(shop:ds(s2).bracket, 1)
  eq(levelsIn(world, "c2"), "12 12 12 12")
  -- someone not checked in yet is checked in by the tap, with no door, and has the station
  shop:stationAction(s3, "Carol", "claim")
  truthy(shop.state.shoppers.Carol, "Carol checked in")
  eq(shop:noteFor("m3"), "Welcome Carol (level 0).")
  eq(shop:ds(s3).shopper, "Carol")
  eq(shop:ds(s3).bracket, 4, "the only axes there are")
  -- PAY from anyone's station pays the tapper's own tab: Carol has none
  shop:stationAction(s1, "Carol", "pay")
  eq(shop:noteFor("m1"), "Carol: nothing to pay.")
  eq(ds.shopper, "Alice", "and Alice's station is still hers")
  shop:stationAction(s3, "Carol", "done")

  -- LV + and LV - step to the next level that has some; past the last there is nothing to step to
  shop:stationAction(s1, "Alice", "level", 1)
  eq(ds.bracket, 7, "40-49 to 70-79, passing the empty ones")
  eq(levelsIn(world, "c1"), "75 75")
  shop:stationAction(s1, "Alice", "level", 1)
  eq(shop:noteFor("m1"), "No higher level in stock.")
  eq(ds.bracket, 7)
  shop:stationAction(s1, "Alice", "level", -1)
  eq(ds.bracket, 4)
  shop:stationAction(s1, "Alice", "type", "the_vault:axe")
  eq(ds.type, "the_vault:sword", "a station of one type has no other")

  -- a piece taken there goes on the tab of the station's shopper
  local slot = next(world.chests.c1.items)
  world.chests.c1.items[slot] = nil
  shop:reconcile(s1)
  eq(#(shop.state.tabs.Alice or {}), 1, "on Alice's tab")
  eq(shop.state.tabs.Alice[1].price, 45, "a level 45 sword costs 45")

  -- DONE: only hers works; the station empties into the vault and is free, and Bob can have it
  shop:stationAction(s1, "Bob", "done")
  eq(ds.shopper, "Alice")
  shop:stationAction(s1, "Alice", "done")
  eq(ds.shopper, nil)
  eq(ds.phase, nil)
  eq(world.held("c1"), 0)
  shop:stationAction(s1, "Bob", "claim")
  eq(ds.shopper, "Bob")
  eq(ds.bracket, 4, "every 10-19 sword is in his other station: the nearest level that has some")
  eq(all(world), 14, "every piece but the one taken is somewhere, once")
end))

test("gearshop stations: each piece is charged its own level, and one put back takes its own price off the tab", withDisk(function()
  local swords = { gear("sword", 41), gear("sword", 44), gear("sword", 49), gear("sword", 0), gear("sword", 0) }
  local world = pretend({
    v1 = { size = 54, items = swords }, v2 = { size = 54, items = {} }, v3 = { size = 54, items = {} },
    c1 = { size = 54, items = {} }, c2 = { size = 54, items = {} }, c3 = { size = 54, items = {} },
  })
  local shop = stationShop({ world = world })
  local s1 = shop.stations[1]
  shop:stationAction(s1, "Alice", "claim")
  local ds = shop:ds(s1)
  eq(levelsIn(world, "c1"), "41 44 49")
  -- the price of each piece is fixed when it goes on display
  local priced = {}
  for key in pairs(ds.shown) do priced[#priced + 1] = shop:priceOf(s1, key) end
  table.sort(priced)
  eq(table.concat(priced, " "), "41 44 49", "every piece at its own level")
  local function slotOf(level)
    for slot, item in pairs(world.chests.c1.items) do
      if item.vaultData.level == level then return slot, item end
    end
  end
  -- she takes the 41 and the 49: a tab of two lines at their own prices
  local slot41, item41 = slotOf(41)
  world.chests.c1.items[slot41] = nil
  local slot49 = slotOf(49)
  world.chests.c1.items[slot49] = nil
  shop:reconcile(s1)
  eq(#shop.state.tabs.Alice, 2, "two lines")
  eq(rules.tabTotal(shop.state.tabs.Alice), 90, "41 + 49")
  eq(shop:owes("Alice"), 90)
  -- the 41 goes back: 41 comes off, the 49 stays
  world.chests.c1.items[slot41] = item41
  shop:reconcile(s1)
  eq(#shop.state.tabs.Alice, 1, "one line left")
  eq(shop.state.tabs.Alice[1].price, 49, "the piece she kept")
  eq(shop:owes("Alice"), 49)
  -- and taken again it costs what it did
  world.chests.c1.items[slot41] = nil
  shop:reconcile(s1)
  eq(shop:owes("Alice"), 90)

  -- a level 0 piece costs the minimum, 1
  shop:stationAction(s1, "Alice", "level", -1)
  eq(ds.bracket, 0)
  eq(levelsIn(world, "c1"), "0 0")
  local slot0 = slotOf(0)
  world.chests.c1.items[slot0] = nil
  shop:reconcile(s1)
  eq(shop:owes("Alice"), 91, "41 + 49 + 1")
end))

test("gearshop stations: the screen shows the price range of what is in the chest", withDisk(function()
  local swords = { gear("sword", 41), gear("sword", 44), gear("sword", 49) }
  local world = pretend({
    v1 = { size = 54, items = swords }, v2 = { size = 54, items = {} }, v3 = { size = 54, items = {} },
    c1 = { size = 54, items = {} }, c2 = { size = 54, items = {} }, c3 = { size = 54, items = {} },
  })
  local shop = stationShop({ world = world })
  local s1 = shop.stations[1]
  shop:stationAction(s1, "Alice", "claim")
  local hadColors = rawget(_G, "colors")
  if not hadColors then rawset(_G, "colors", { black = 32768 }) end
  local ui = require("lib.gearshop.ui")
  local function draw()
    local s = ui.screen({ call = function(_, method)
      if method == "getSize" then return true, 36, 10 end
      return true
    end }, "m1", 0.5)
    shop.noteFor = function() return nil end
    ui.station(s, shop, s1, {})
    return (table.concat(s.text, " "):gsub("%s+", " "))
  end
  local text = draw()
  if not hadColors then rawset(_G, "colors", nil) end
  truthy(text:find("41-49 each", 1, true), "the range of the three: " .. text)
  -- one piece left: its own price
  for slot, item in pairs(world.chests.c1.items) do
    if item.vaultData.level ~= 44 then world.chests.c1.items[slot] = nil end
  end
  shop:reconcile(s1)
  if not hadColors then rawset(_G, "colors", { black = 32768 }) end
  text = draw()
  if not hadColors then rawset(_G, "colors", nil) end
  truthy(text:find("44 each", 1, true), "one piece, one price: " .. text)
end))

test("gearshop stations: with nothing of its type at all, a tap says so and opens nothing", withDisk(function()
  local shop = stationShop()
  shop.stations[3].gearType = "the_vault:wand"
  shop:stationAction(shop.stations[3], "Alice", "claim")
  eq(shop:noteFor("m3"), "No Wands in stock right now.")
  eq(shop:ds(shop.stations[3]).shopper, nil)
end))

test("gearshop stations: a station for a family of types (idol) fills with every one of them and nothing else", withDisk(function()
  local idols = {}
  for _ = 1, 2 do idols[#idols + 1] = gear("idol_benevolent", 45) end
  for _ = 1, 3 do idols[#idols + 1] = gear("idol_timekeeper", 44) end
  idols[#idols + 1] = gear("idol_omniscient", 75)
  local world = pretend({
    v1 = { size = 54, items = { gear("sword", 45), gear("sword", 45) } }, v2 = { size = 54, items = idols }, v3 = { size = 54, items = {} },
    c1 = { size = 54, items = {} }, c2 = { size = 54, items = {} }, c3 = { size = 54, items = {} },
  })
  local shop = stationShop({ world = world })
  local s3 = shop.stations[3]
  s3.gearType = "the_vault:idol"
  shop:stationAction(s3, "Alice", "claim")
  local ds = shop:ds(s3)
  eq(ds.shopper, "Alice")
  eq(ds.bracket, 4)
  eq(world.held("c3"), 5, "both kinds of idol at 40-49")
  for _, item in pairs(world.chests.c3.items) do
    truthy(item.name:find("^the_vault:idol_"), "only idols: " .. item.name)
  end
  shop:stationAction(s3, "Alice", "level", 1)
  eq(ds.bracket, 7, "LV + steps to the next bracket any idol has")
  eq(world.held("c3"), 1)
  shop:stationAction(s3, "Alice", "done")
  eq(all(world), 8, "every piece back, once")
end))

test("gearshop stations: one more station than a shopper may hold frees the one used longest ago", withDisk(function()
  local shop, world = stationShop({ limits = { stationsPerShopper = 2 } })
  local s1, s2, s3 = shop.stations[1], shop.stations[2], shop.stations[3]
  shop:stationAction(s1, "Alice", "claim")
  shop:stationAction(s3, "Alice", "claim")
  shop:ds(s1).used, shop:ds(s3).used = 1, 2
  shop:stationAction(s2, "Alice", "claim")
  eq(shop:ds(s1).shopper, nil, "the oldest is given back")
  eq(world.held("c1"), 0, "and emptied")
  eq(shop:noteFor("m1"), "Free again: Alice opened station 2.")
  eq(shop:ds(s2).shopper, "Alice")
  eq(shop:ds(s3).shopper, "Alice")
  eq(all(world), 15)
  -- 0 is no limit
  shop.cfg.stationsPerShopper = 0
  shop:stationAction(s1, "Alice", "claim")
  eq(#shop:held("Alice"), 3)
end))

test("gearshop stations: walking away, leaving it untouched, or checking out frees a station", withDisk(function()
  local shop, world = stationShop()
  local s1, s3 = shop.stations[1], shop.stations[3]
  shop:stationAction(s1, "Alice", "claim")
  shop:freeStations({ Alice = { x = 12, y = 64, z = 0 } })
  eq(shop:ds(s1).shopper, "Alice", "she is at it")
  shop:freeStations({ Alice = { x = 40, y = 64, z = 0 } })
  eq(shop:ds(s1).shopper, "Alice", "one look away is not enough")
  shop:stationAction(s1, "Bob", "claim")
  eq(shop:noteFor("m1"), "In use by Alice. Free soon.")
  shop:freeStations({ Alice = { x = 40, y = 64, z = 0 } })
  eq(shop:ds(s1).shopper, nil, "two looks running: she walked away")
  eq(world.held("c1"), 0)
  eq(shop:noteFor("m1"), "Free again: Alice walked away.")
  -- with no word of where she is, a station stays hers
  shop:stationAction(s1, "Alice", "claim")
  shop:freeStations({})
  shop:freeStations({})
  eq(shop:ds(s1).shopper, "Alice")
  -- untouched too long
  shop:stationAction(s3, "Alice", "claim")
  shop:ds(s3).used = os.epoch("utc") - 6 * 60000
  shop:freeStations({ Alice = { x = 30, y = 64, z = 0 } })
  eq(shop:ds(s3).shopper, nil, "five minutes with no tap or take")
  eq(world.held("c3"), 0)
  -- checking out gives back every station she holds
  shop:stationAction(s3, "Alice", "claim")
  shop:checkOut("Alice", "checked out")
  eq(shop:ds(s1).shopper, nil)
  eq(shop:ds(s3).shopper, nil)
  eq(world.held("c1") + world.held("c3"), 0)
  eq(all(world), 15)
end))

test("gearshop stations: a reboot at any step of filling or emptying a station is finished once", withDisk(function()
  for _, point in ipairs({ "fill-begin", "fill-end", "sweep-begin", "sweep-end" }) do
    local emptying = point:find("sweep", 1, true) ~= nil
    local shop, world, disk = stationShop()
    local s1 = shop.stations[1]
    if emptying then
      shop:stationAction(s1, "Alice", "claim")
      eq(world.held("c1"), 6, point .. ": filled")
    end
    local real = shop.save
    shop.save = function(self, why)
      if why == point then error("crash at " .. why, 0) end
      return real(self, why)
    end
    eq(pcall(shop.stationAction, shop, s1, "Alice", emptying and "done" or "claim"), false, point .. " went down")
    -- back up on the same chests, with the state as it was last written
    local again = stationShop({ world = world, state = disk.copy(disk.state) })
    for _, d in ipairs(again.stations) do again:mend(d) end
    local ds = again:ds(again.stations[1])
    if point == "sweep-end" then
      eq(ds.shopper, nil, point .. ": the station is free")
      eq(ds.phase, nil, point)
      eq(world.held("c1"), 0, point .. ": and empty")
    elseif point == "sweep-begin" then
      -- DONE was never written: the station is still hers, as it was
      eq(ds.shopper, "Alice", point)
      eq(ds.phase, "open", point)
      eq(world.held("c1"), 6, point)
    else
      eq(ds.shopper, "Alice", point .. ": still hers")
      eq(ds.phase, "open", point .. ": open again")
      eq(levelsIn(world, "c1"), "45 45 45 45 45 45", point .. ": her six, once")
    end
    eq(all(world), 15, point .. ": nothing made or lost")
    eq(next(again.state.tabs), nil, point .. ": nobody charged")
  end
end))
