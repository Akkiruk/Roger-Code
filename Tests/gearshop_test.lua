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
