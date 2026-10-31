-- floor_test.lua
-- The extras around a table that can be proved without one: demos of every game, the scoreboard's layout on any monitor,
-- what a session says, and the shape of a whisper. tools/casinotest/floor.mjs runs them on a real table in the emulator.

local canvas = require("lib.casino.canvas")
local board = require("lib.casino.board")
local chat = require("lib.casino.chat")
local deck = require("lib.casino.deck")
local demo = require("lib.casino.demo")
local session = require("lib.casino.session")
local ui = require("lib.casino.ui")
local poker = require("pokertable_rules")
local t = require("testing")

local GAMES = { "baccarat_game", "blackjack_game", "crazyeights_game", "hilo_game", "horseracing_game", "roulette_game",
  "slots_game", "threecard_game", "holdem_game", "videopoker_game" }

--- Everything the demo was handed that is not its own, watched for a write.
local function untouchable(what)
  return setmetatable({}, { __newindex = function(_, key) error(what .. " was written: " .. tostring(key), 2) end })
end

for _, file in ipairs(GAMES) do
  t.test(file .. ": demo rounds finish, draw and show a result", function()
    local game = require(file)
    local c = canvas.new(nil, 121, 81)
    local ctx = { title = game.title, c = c, demo = true }
    local show = demo.new(demo.forGame(game, ctx))
    local finished = 0
    for _ = 1, 4000 do
      show:tick(0.5)
      if show.state then
        game.view.draw(c, show.model, show.state, show.playing)
        ui.bar(c, ctx, "DEMO")
        if show:finished() then
          local result = game.rules.result(show.state)
          t.truthy(result.title, "a result")
          finished = finished + 1
          show.state = nil
          if finished == 3 then break end
        end
      end
      t.breathe()
    end
    t.eq(finished, 3, "rounds played to the end")
  end)
end

t.test("a demo gets a keep of its own each round, and rules.finish is never called", function()
  local kept, finishes = {}, 0
  local rules = {
    new = function(_, _, keep) kept[#kept + 1] = keep; keep.shoe = "mine"; return { over = true }, {} end,
    done = function() return true end,
    finish = function() finishes = finishes + 1 end,
  }
  local view = { new = function() return {} end, sync = function() end }
  local show = demo.new(demo.forGame({ rules = rules, view = view }, untouchable("ctx")))
  for _ = 1, 20 do show:tick(1) end
  t.truthy(#kept >= 2, "two rounds")
  t.truthy(kept[1] ~= kept[2], "a new keep each time")
  t.eq(finishes, 0, "finish")
end)

t.test("a demo that goes round for ever is dropped", function()
  local rules = {
    new = function() return { over = false }, {} end,
    done = function() return false end,
    auto = function() return "x" end,
    act = function() return {} end,
  }
  local view = { new = function() return {} end, sync = function() end }
  local show = demo.new(demo.forGame({ rules = rules, view = view }, {}))
  for _ = 1, 200 do show:tick(2) end
  t.truthy(show.rounds >= 2, "it starts again")
end)

t.test("the board fits every monitor smaller than a wall, and keeps NOW PLAYING and the jackpot", function()
  local leaders = {}
  for i = 1, 8 do leaders[i] = { name = "CaptainLongname" .. i, net = 1234567 * (i % 2 == 0 and -1 or 1) } end
  for _, size in ipairs({ { 15, 10 }, { 18, 12 }, { 29, 19 }, { 39, 26 }, { 57, 38 }, { 77, 52 }, { 100, 67 } }) do
    local c = canvas.new(nil, size[1], size[2])
    board.draw(c, { title = "CRAZY EIGHTS", leaders = leaders, jackpot = 1234567, playing = { "CaptainLongname1" } })
    local rows = {}
    for y = 1, c.h do rows[y] = table.concat(c.ch[y]) end
    local text = table.concat(rows, "\n")
    t.truthy(text:find("NOW PLAYING", 1, true), size[1] .. "x" .. size[2] .. " now playing")
    t.truthy(text:find("Jackpot", 1, true), size[1] .. "x" .. size[2] .. " jackpot")
    t.truthy(text:find("1 Captain", 1, true), size[1] .. "x" .. size[2] .. " the leader")
  end
end)

t.test("the board says so when nobody has played or sat down", function()
  local c = canvas.new(nil, 29, 19)
  board.draw(c, { title = "HI-LO", leaders = {}, playing = {} })
  local rows = {}
  for y = 1, c.h do rows[y] = table.concat(c.ch[y]) end
  local text = table.concat(rows, "\n")
  t.truthy(text:find("No rounds yet", 1, true), "no rounds")
  t.truthy(text:find("Table free", 1, true), "free")
end)

t.test("a session reads the way the wall says it", function()
  t.eq(session.text({ rounds = 12, net = 340, best = 900 }), "12 rounds, +340, best win 900")
  t.eq(session.text({ rounds = 1, net = -100, best = 0 }), "1 round, -100")
  t.eq(session.text({ rounds = 2, net = 0, best = 50 }), "2 rounds, 0, best win 50")
  t.eq(session.text({ rounds = 1200, net = -1500, best = 2500 }), "1,200 rounds, -1,500, best win 2,500")
end)

t.test("the longest hand there can be fits one line of chat, dealt or drawn", function()
  local hand = { deck.parse("10C"), deck.parse("10D"), deck.parse("10H"), deck.parse("10S"), deck.parse("9C") }
  t.eq(poker.whisper(hand), "Your hand: 10C 10D 10H 10S 9C")
  t.eq(poker.whisper(hand, true), "After the draw: 10C 10D 10H 10S 9C")
  t.truthy(#poker.whisper(hand, true) <= chat.LINE, "fits")
end)
