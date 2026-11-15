-- browser.lua
-- The Game Browser: every free cabinet on one computer. The wall lists the cabinets; picking one saves the choice and reboots
-- into it, so a cabinet always starts clean, exactly as it does on its own computer. MORE GAMES on its menu (or on a one-game
-- cabinet's ready screen) clears the choice and reboots back to this list. A reboot or a crash goes back to the cabinet that
-- was picked.
-- Each cabinet's files are installed under its own folder (see manifest-bundle in startup.lua), because every one of them has
-- its own games/registry.lua; the shell (lib/arcade) and the pixel font are shared. Game ids are unique across the cabinets,
-- so their saves, scores and records sit side by side at the root as they would on their own computers. The one file they
-- would share, the play tracker's last update number, is kept per cabinet.
-- Free to play: nothing here or in any cabinet it runs reaches ccvault or moves a token. Game Night is not here: it needs a
-- computer at every seat.

local config = require("lib.arcade.constants")
local hw = require("lib.arcade.hw")
local audio = require("lib.arcade.audio")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor, max, min = math.floor, math.max, math.min

local CHOICE_FILE = "browser_cabinet.dat"
local LOG_FILE = "browser.log"

local CABINETS = {
  { id = "arcade", name = "ARCADE", title = "ARCADE", color = "hi",
    blurb = "Board games: Connect Four, Checkers, Reversi, Battleship and more" },
  { id = "versus", name = "VERSUS", title = "VERSUS", color = "red",
    blurb = "Two players in real time: Pong, Bomberman, Light Cycles, MOAG" },
  { id = "classics", name = "CLASSICS", title = "CLASSICS", color = "info",
    blurb = "Pac-Man, Asteroids, Invaders and more, for the high score" },
  { id = "classics2", name = "CLASSICS 2", title = "CLASSICS 2", color = "soft",
    blurb = "Dig Dug, Flappy Bird, Tapper, Minesweeper and more" },
  { id = "longgames", name = "LONG GAMES", title = "LONG GAMES", color = "ok",
    blurb = "Oregon Trail, Craft World, Cookie Clicker: saved between visits" },
  { id = "blightmare", name = "BLIGHTMARE", title = "BLIGHTMARE", color = "accent",
    blurb = "A dark first-person RPG, saved between visits" },
}

local M = { CABINETS = CABINETS, CHOICE_FILE = CHOICE_FILE }

local function log(msg)
  local h = fs.open(LOG_FILE, "a")
  if h then
    h.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg))
    h.close()
  end
end

function M.find(id)
  for _, cab in ipairs(CABINETS) do
    if cab.id == id then return cab end
  end
  return nil
end

function M.readChoice()
  if not fs.exists(CHOICE_FILE) then return nil end
  local h = fs.open(CHOICE_FILE, "r")
  if not h then return nil end
  local id = h.readAll()
  h.close()
  return M.find(id and id:match("^%s*(.-)%s*$"))
end

local function writeChoice(id)
  local h = fs.open(CHOICE_FILE, "w")
  if not h then return false end
  h.write(id)
  h.close()
  return true
end

--- Back to the list of cabinets. Never returns.
function M.backToList()
  log("back to the list")
  fs.delete(CHOICE_FILE)
  os.reboot()
end

--- Make this cabinet's files the ones require finds: its games/registry.lua and games/<id>/, ahead of the root.
function M.usePaths(cab)
  local dir = "/" .. cab.id
  package.path = dir .. "/?;" .. dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. package.path
  require("lib.arcade.share").useStateFile("browser_share_" .. cab.id .. ".dat")
end

--- Run a cabinet for ever, as its own package would.
function M.play(cab)
  log("starting " .. cab.id)
  M.usePaths(cab)
  require("lib.arcade.main").run({ name = cab.name, cabinets = M.backToList })
end

-- ------------------------------------------------------------------ the list

local surfaceApi, font, screen
local walls = {}
local W, H = 0, 0
local picked = nil -- the cabinet being started, shown while the computer reboots

local function prepare(mon)
  if mon.setTextScale then mon.setTextScale(config.TEXT_SCALE) end
  for name, hex in pairs(config.PALETTE) do
    if colors[name] then mon.setPaletteColor(colors[name], hex) end
  end
  mon.setBackgroundColor(colors.black)
  mon.clear()
end

local function setup()
  hw.init()
  walls = {}
  local mon, name = hw.monitor()
  if not mon then return false end
  prepare(mon)
  W, H = mon.getSize()
  surfaceApi = surfaceApi or dofile("surface")
  font = font or surfaceApi.loadFont(surfaceApi.load("font"))
  screen = surfaceApi.create(W, H)
  ui.init(surfaceApi, font, screen)
  walls[1] = { mon = mon, name = name, out = ui.changedRows(mon) }
  local second, secondName = hw.wall2()
  if second then
    prepare(second)
    walls[2] = { mon = second, name = secondName, out = ui.changedRows(second) }
  end
  audio.init(hw.speakerName())
  return true
end

--- The list, the same on every wall.
function M.draw()
  screen:clear(C.bg, nil, " ")
  ui.clearButtons()
  local cx = floor(W / 2)
  ui.text("GAME BROWSER", cx, 2, C.hi, "center", W - 2)
  ui.small("Free to play - pick a cabinet", cx, 10, C.line, C.bg, "center", W - 2)
  local cols = W >= 80 and 2 or 1
  local rows = math.ceil(#CABINETS / cols)
  local top, bottom = 13, H - 4
  local rowH = max(5, min(20, floor((bottom - top) / rows) - 2))
  local tileW = floor((W - 4 - (cols - 1) * 2) / cols)
  for i, cab in ipairs(CABINETS) do
    local x = 2 + ((i - 1) % cols) * (tileW + 2)
    local y = top + floor((i - 1) / cols) * (rowH + 2)
    local color = C[cab.color] or C.hi
    local starting = picked == cab
    ui.button("cabinet", x, y, tileW, rowH, "", C.panel, { data = cab.id, frame = color, enabled = not picked })
    if starting then ui.fill(x, y, tileW, rowH, color) end
    local bg = starting and color or C.panel
    local fg = starting and C.bg or C.text
    local titleFits = ui.textWidth(cab.title) <= tileW - 4 and rowH >= font.height + 6
    local lines = ui.wrap(starting and "Starting..." or cab.blurb, tileW - 4)
    local textH = (titleFits and font.height or 1) + 1 + min(#lines, 2)
    local ty = y + max(1, floor((rowH - textH) / 2))
    if titleFits then
      ui.text(cab.title, x + floor(tileW / 2), ty, fg, "center")
      ty = ty + font.height + 1
    else
      ui.small(cab.title, x + floor(tileW / 2), ty, fg, bg, "center", tileW - 2)
      ty = ty + 2
    end
    for j = 1, min(#lines, 2) do
      if ty < y + rowH - 1 then ui.small(lines[j], x + floor(tileW / 2), ty, starting and C.bg or C.line, bg, "center", tileW - 2) end
      ty = ty + 1
    end
  end
  ui.small("MORE GAMES on any cabinet's menu comes back here", cx, H - 2, C.line, C.bg, "center", W - 2)
  for _, wall in ipairs(walls) do screen:output(wall.out, 0, 0) end
end

local function onWall(side)
  for _, wall in ipairs(walls) do
    if wall.name == side then return true end
  end
  return false
end

--- The list, until someone picks a cabinet. Picking reboots into it.
function M.list()
  while not setup() do
    log("no monitor attached")
    os.pullEvent("peripheral")
  end
  M.draw()
  while true do
    local event, side, x, y = os.pullEvent()
    if event == "monitor_touch" and onWall(side) and not picked then
      local b = ui.hit(x - 1, y - 1)
      local cab = b and b.id == "cabinet" and M.find(b.data)
      if cab and writeChoice(cab.id) then
        audio.play("select")
        picked = cab
        M.draw()
        log("picked " .. cab.id)
        os.sleep(0.4)
        os.reboot()
      end
    elseif event == "monitor_resize" or event == "peripheral" or event == "peripheral_detach" then
      if setup() then M.draw() end
    end
  end
end

function M.run()
  local cab = M.readChoice()
  if cab then M.play(cab) else M.list() end
end

-- run as a program; required (by a test), it only hands over its functions
if not ... or ... ~= "browser" then
  M.run()
end
return M
