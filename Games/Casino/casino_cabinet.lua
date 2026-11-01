-- casino_cabinet.lua
-- Every casino game on one computer. The menu picks a game, and a reboot starts it, so a game always runs from a clean start
-- exactly as it would on its own table. ALL GAMES on its idle screen, or 90 idle seconds, reboots back here.
-- Each game keeps its own books: its casino_* files are renamed for it below, so no game can read or overwrite another's
-- round, shoe, stats or debts. A round left open goes back to its game on boot, whatever was picked.

local audio = require("lib.casino.audio")
local board = require("lib.casino.board")
local canvas = require("lib.casino.canvas")
local theme = require("lib.casino.theme")
local ui = require("lib.casino.ui")

local C = theme.C
local M = {}

local CHOICE_FILE = "cabinet_game.dat"
local MIN_W, MIN_H = 121, 81
local TILE_H = 8

local GAMES = {
  { id = "blackjack", title = "BLACKJACK", module = "blackjack_game" },
  { id = "baccarat", title = "BACCARAT", module = "baccarat_game" },
  { id = "roulette", title = "ROULETTE", module = "roulette_game" },
  { id = "slots", title = "SLOTS", module = "slots_game" },
  { id = "videopoker", title = "VIDEO POKER", module = "videopoker_game" },
  { id = "threecard", title = "3 CARD", module = "threecard_game" },
  { id = "holdem", title = "HOLD'EM", module = "holdem_game" },
  { id = "hilo", title = "HI-LO", module = "hilo_game" },
  { id = "horseracing", title = "HORSES", module = "horseracing_game" },
  { id = "crazyeights", title = "CRAZY 8S", module = "crazyeights_game" },
  { id = "pokertable", title = "POKER", app = "pokertable_app" },
}

local function find(id)
  for _, game in ipairs(GAMES) do
    if game.id == id then return game end
  end
  return nil
end

local function stored(id, name)
  return "cabinet_" .. id .. "_" .. name
end

local function hasFile(id, name)
  for _, suffix in ipairs({ "", ".tmp", ".bak" }) do
    local path = stored(id, name .. suffix)
    if fs.exists(path) and fs.getSize(path) > 0 then return true end
  end
  return false
end

--- Give this game's files their own names, for everything it does until the next reboot.
local function keepFilesApart(id)
  local LEFT_ALONE = { ["casino_debug.flag"] = true, ["casino_rig.dat"] = true, ["casino_ui.dat"] = true }
  local function rename(path)
    if type(path) == "string" and path:find("^casino[_%.]") and not LEFT_ALONE[path] then return stored(id, path) end
    return path
  end
  for _, name in ipairs({ "open", "exists", "delete", "getSize", "isDir", "attributes" }) do
    local real = fs[name]
    fs[name] = function(path, ...) return real(rename(path), ...) end
  end
  for _, name in ipairs({ "move", "copy" }) do
    local real = fs[name]
    fs[name] = function(from, to) return real(rename(from), rename(to)) end
  end
end

local function readChoice()
  local handle = fs.open(CHOICE_FILE, "r")
  if not handle then return nil end
  local id = handle.readAll()
  handle.close()
  return id
end

local function writeChoice(id)
  local handle = assert(fs.open(CHOICE_FILE, "w"))
  handle.write(id)
  handle.close()
end

--- A game with a round still open comes first: only it can finish that round.
local function openRound()
  for _, game in ipairs(GAMES) do
    if hasFile(game.id, "casino_round.dat") then return game end
  end
  return nil
end

local function backToMenu()
  fs.delete(CHOICE_FILE)
  os.reboot()
end

local function play(game)
  keepFilesApart(game.id)
  local opts = { back = backToMenu }
  if game.app then
    require(game.app).run(opts)
  else
    require("lib.casino.table").run(require(game.module), opts)
  end
end

local function drawMenu(c)
  c:clear(C.felt)
  ui.bar(c, { title = "CASINO" })
  local buttons = ui.newButtons()
  local y = ui.TOP + 1
  for i = 1, #GAMES, 2 do
    local specs = {}
    for j = i, math.min(i + 1, #GAMES) do
      local game = GAMES[j]
      local owed = hasFile(game.id, "casino_owed.dat")
      specs[#specs + 1] = { id = game.id, label = game.title, color = owed and C.orange or C.panel2,
        textColor = owed and C.ink or C.gold }
    end
    ui.actionRow(c, buttons, specs, y, TILE_H)
    y = y + TILE_H + 2
  end
  c:bigCenter(math.floor(c.w / 2), c.h - 9, "PICK A GAME", C.text, 1)
  c:textCenter(math.floor(c.w / 2), c.h - 2, "Orange: money waiting at that game", C.mute)
  c:flush()
  return buttons
end

local function menu()
  audio.init()
  local name = assert(board.largest(), "this cabinet needs a monitor")
  local monitor = peripheral.wrap(name)
  monitor.setTextScale(0.5)
  theme.apply(monitor, "green")
  local c = canvas.new(monitor)
  while c.w < MIN_W or c.h < MIN_H do
    c:clear(C.ink)
    c:textCenter(math.floor(c.w / 2), 3, "Needs a 6x6 monitor wall", C.text)
    c:flush()
    os.pullEvent("monitor_resize")
    monitor.setTextScale(0.5)
    c:attach(monitor)
  end
  local buttons = drawMenu(c)
  while true do
    local event, side, x, y = os.pullEvent()
    if event == "monitor_touch" and side == name then
      local hit = ui.hit(buttons, x, y)
      if hit then
        audio.play("tap")
        writeChoice(hit.id)
        os.reboot()
      end
    elseif event == "monitor_resize" and side == name then
      monitor.setTextScale(0.5)
      c:attach(monitor)
      buttons = drawMenu(c)
    end
  end
end

function M.run()
  local game = openRound() or find(readChoice())
  if game then play(game) else menu() end
end

return M
