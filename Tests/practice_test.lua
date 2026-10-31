-- practice_test.lua
-- The seam between a table and money. Pretend seats are proved played on a real table by tools/casinotest/practice.mjs in
-- craftos-agent; this proves the wiring cannot come undone, including by a call added to table.lua later.

local door = require("lib.casino.door")
local pretend = require("lib.casino.pretend")
local t = require("testing")

--- A file on package.path, as text. The same whether this runs in plain Lua or on an emulated computer.
local function source(module)
  local relative = module:gsub("%.", "/")
  for template in package.path:gmatch("[^;]+") do
    local handle = io.open((template:gsub("%?", relative)), "r")
    if handle then
      local text = handle:read("*a")
      handle:close()
      return text
    end
  end
  error("cannot find " .. module)
end

local DOORS = { "books", "journal", "lamps", "net", "session", "stats", "wallet" }

--- What table.lua may require itself. None of these hold money or a player's record, and each is listed by hand, so a module
-- that does (badges.lua, say) fails here until it comes through door.to and has its stand-ins in pretend.lua.
local PLAIN = {
  audio = true, board = true, canvas = true, chat = true, demo = true, door = true, limits = true, playercard = true,
  presence = true, pretend = true, rng = true, theme = true, tournament = true, ui = true,
}

--- Calls a real table never makes in a pretend seat, because they only run as the table boots.
local BOOT_ONLY = { ["journal.loadKeep"] = true, ["net.worker"] = true, ["lamps.worker"] = true, ["badges.BIG_WIN_TIMES"] = true }
local THROUGH = { ["net.open"] = true, ["lamps.rescan"] = true }

local function seat(options)
  options = options or {}
  options.at = options.at or 1000
  return pretend.new(options)
end

t.test("table.lua reaches money only through a door", function()
  local text = source("lib.casino.table")
  for _, name in ipairs(DOORS) do
    t.eq(text:find('require%("lib%.casino%.' .. name .. '"%)'), nil, "a direct require of " .. name)
    t.truthy(text:find('local ' .. name .. ' = door%.to%("' .. name .. '"%)'), name .. " behind a door")
  end
end)

t.test("table.lua requires nothing that holds money or a record, unless it comes through a door", function()
  for name in source("lib.casino.table"):gmatch('require%("lib%.casino%.([%w_]+)"%)') do
    t.truthy(PLAIN[name], name .. " must go behind a door, in door.lua and pretend.lua, or be listed as harmless")
  end
end)

t.test("every call table.lua makes through a door has a stand-in", function()
  local text = source("lib.casino.table"):gsub("%-%-[^\n]*", "")
  local stands = seat().stands
  local calls = 0
  local scanned = { "badges" }
  for _, name in ipairs(DOORS) do scanned[#scanned + 1] = name end
  for _, name in ipairs(scanned) do
    for key in text:gmatch("[^%w_%.]" .. name .. "%.([%a_]+)") do
      local whole = name .. "." .. key
      if not BOOT_ONLY[whole] and not THROUGH[whole] then
        calls = calls + 1
        t.truthy(stands[name] and stands[name][key], "a stand-in for " .. whole)
      end
    end
  end
  t.truthy(calls > 30, "the scan found the calls")
end)

t.test("pretend.lua cannot reach anything real, because it requires nothing at all", function()
  local text = source("lib.casino.pretend")
  t.eq(text:find("require%("), nil, "a require")
  t.eq(text:find("ccvault", 1, true), nil, "ccvault")
  t.eq(text:find("[^%w]fs%."), nil, "a file call")
  t.eq(text:find("rednet", 1, true), nil, "rednet")
end)

t.test("a tournament's table side has no way to tokens, a round or the keep", function()
  local text = source("lib.casino.tournament")
  t.eq(text:find('require%("lib%.casino%.wallet"%)'), nil, "the wallet")
  t.eq(text:find('require%("lib%.casino%.books"%)'), nil, "the books")
  t.eq(text:find("ccvault", 1, true), nil, "ccvault")
  t.eq(text:find("saveKeep", 1, true), nil, "the keep")
  t.eq(text:find("saveRound", 1, true), nil, "a round")
  t.eq(text:find('net.send("round"', 1, true), nil, "a hub round")
end)

t.test("a door is the real module for a live seat", function()
  local books = require("lib.casino.books")
  local wallet = require("lib.casino.wallet")
  t.eq(door.to("books").move, books.move)
  t.eq(door.to("wallet").balance, wallet.balance)
  t.eq(door.pretending(), false)
end)

t.test("with a pretend seat sitting no door reaches the real module", function()
  local real = {}
  for _, name in ipairs(DOORS) do real[name] = require("lib.casino." .. name) end
  local sitter = seat({ name = "Ann" })
  door.enter(sitter.stands)
  local ok, err = pcall(function()
    for name, module in pairs(real) do
      local way = door.to(name)
      for key, fn in pairs(module) do
        if type(fn) == "function" then
          local through = THROUGH[name .. "." .. key]
          local found, got = pcall(function() return way[key] end)
          -- A function with no stand-in is refused. One with a stand-in is never the real thing
          if found and not through then t.truthy(got ~= fn, name .. "." .. key .. " is the real thing") end
          if through then t.eq(got, fn, name .. "." .. key .. " goes through") end
        end
      end
    end
  end)
  door.leave()
  t.truthy(ok, err)
end)

t.test("a door fails closed: anything without a stand-in is an error, not the real call", function()
  local sitter = seat({ name = "Ann" })
  door.enter(sitter.stands)
  local ok = pcall(function() return door.to("wallet").send end)
  local ok2 = pcall(function() return door.to("books").anythingNew end)
  door.leave()
  t.eq(ok, false, "wallet.send")
  t.eq(ok2, false, "a function added later")
end)

t.test("leaving the seat gives the real module back", function()
  local sitter = seat()
  door.enter(sitter.stands)
  door.leave()
  t.eq(door.to("wallet").send, require("lib.casino.wallet").send)
end)

t.test("a pretend round settles in chips, and owes nothing", function()
  local sitter = seat({ name = "Ann" })
  local moved, left, err = sitter.stands.books.move("Ann", 150, "HI-LO #1")
  t.eq(moved, 150)
  t.eq(left, 0)
  t.eq(err, nil)
  t.eq(sitter.chips, pretend.CHIPS + 150)
  t.eq(sitter.stands.wallet.balance("Ann"), pretend.CHIPS + 150)
  t.eq(sitter.stands.journal.owedTo("Ann"), 0)
end)

t.test("chips cannot go below nothing", function()
  local sitter = seat({ chips = 40 })
  sitter.stands.books.move("Ann", -100, "x")
  t.eq(sitter.chips, 0)
end)

t.test("each seat has its own keep, and stats that stay with it", function()
  local a, b = seat(), seat()
  t.truthy(a.keep ~= b.keep, "two keeps")
  a.keep.shoe = { 1, 2, 3 }
  t.eq(b.keep.shoe, nil)
  a.stands.stats.record("Ann", 100, 50, "tag")
  t.eq(a.stands.stats.player("Ann").rounds, 1)
  t.eq(a.stands.stats.player("Ann").best, 50)
  t.eq(b.stands.stats.player("Ann").rounds, 0)
  t.eq(#a.stands.stats.leaders(8), 0, "nobody's leaderboard")
end)

t.test("a seat always has a limit it can use, and never a house to cover it", function()
  local sitter = seat()
  t.truthy(sitter.stands.wallet.hostBalance() > 1e8, "room for any bet")
  t.eq(sitter.stands.wallet.hostName(), nil, "no host")
  t.eq(sitter.stands.net.hub(), nil, "no hub, so no shared pot")
  t.eq(sitter.stands.net.otherExposure("x"), 0)
end)

t.test("only the player's touch is theirs, but a guest cannot be told from anyone", function()
  t.eq(seat({ name = "Ann" }):owns("Ann"), true)
  t.eq(seat({ name = "Ann" }):owns("Bob"), false)
  t.eq(seat({ name = "Ann" }):owns(nil), false, "a touch nobody can name")
  t.eq(seat({ guest = true }):owns(nil), true)
end)

t.test("an idle seat ends, and sooner with someone waiting or the player gone", function()
  local bet = { name = "bet" }
  local sitter = seat({ name = "Ann", at = 0 })
  t.eq(sitter:over(pretend.WAITED_MS, bet), nil, "alone it has longer")
  t.eq(sitter:over(pretend.IDLE_MS, bet), "idle")

  sitter = seat({ name = "Ann", at = 0 })
  sitter:wanted()
  t.eq(sitter:over(pretend.WAITED_MS - 1, bet), nil)
  t.eq(sitter:over(pretend.WAITED_MS, bet), "idle", "someone is waiting")

  sitter = seat({ name = "Ann", at = 0 })
  t.eq(sitter:over(pretend.WAITED_MS, bet, 0), nil, "the detector can see them")
  t.eq(sitter:over(pretend.WAITED_MS, bet, 2000), "idle", "the detector says they left")

  sitter = seat({ name = "Ann", at = 0 })
  sitter:wanted()
  sitter:touch(9000)
  t.eq(sitter:over(pretend.WAITED_MS, bet), nil, "while they keep playing the seat is theirs")
end)

t.test("a reveal is never cut off by the idle clock", function()
  local sitter = seat({ at = 0 })
  sitter:wanted()
  t.eq(sitter:over(60000, { name = "play", playing = {} }), nil)
  t.eq(sitter:over(60000, { name = "play", queue = { {} } }), nil)
end)

t.test("a seat out of chips ends on the bet screen, after its result has been seen", function()
  local sitter = seat({ chips = 10, at = 0 })
  sitter.stands.books.move("Ann", -10, "x")
  t.eq(sitter:over(1, { name = "result" }), nil)
  t.eq(sitter:over(1, { name = "bet" }), "bust")
end)

t.test("the label is on every seat and says no tokens", function()
  t.truthy(seat():label(0):find("NO TOKENS", 1, true), "practice")
  t.truthy(seat():label(0):find("PRACTICE", 1, true), "practice")
  local hooked = seat({ kind = "tournament", hooks = { ends = function() return 600000 end } })
  t.truthy(hooked:label(0):find("TOURNAMENT", 1, true), "tournament")
  t.truthy(hooked:label(0):find("10 MIN", 1, true), "time left")
  t.truthy(#seat():label(0) <= 119, "it fits the wall")
end)
