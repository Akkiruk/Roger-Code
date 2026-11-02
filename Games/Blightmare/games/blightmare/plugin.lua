-- games/blightmare/plugin.lua
-- A dark RPG for one wall, the first playable slice of it: Scythebreak, a stretch of the Heart, Orrenshire and its mine.
-- This file only sends things where they belong by mode. Most of what's on the wall stands still, so the picture is painted
-- once for each change into a surface of its own, and the shell's steady redraw copies it across, as Dungeon does.

local base = require("lib.arcade.base")
local rules = require("games.blightmare.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor

-- The pictures load when first drawn, so the rules can be tested with none of them there.
local function part(name) return require("games.blightmare." .. name) end

local view = {}

function view.layout(W, H)
  return { W = W, H = H, x0 = 0, y0 = 0, bw = W, bh = H, statusY = 60 }
end

--- The ground the player is standing on: behind speech, it's whatever the script will come back to.
local function drawGround(L, s, ground)
  if ground == "world" then
    part("view_world").drawWorld(L, s)
  else
    part("view_world").drawWalk(L, s)
  end
  if s.mode == ground then
    if s.msg ~= "" then ui.small(" " .. s.msg .. " ", floor(L.W / 2), L.statusY, C.text, C.bg, "center", L.W - 4) end
    if ground == "walk" then base.drawMiddle(L, C.text) end
    local left = s.hints[ground]
    if type(left) == "number" and left > 0 then
      if ground == "walk" then
        base.drawSplit(L.W, L.H, "ACT")
      else
        ui.small(" Tap where you want to go ", floor(L.W / 2), 2, C.text, C.bg, "center", L.W - 4)
      end
    end
  end
end

local function paint(L, s)
  local mode = s.mode
  if mode == "name" then
    part("view_talk").drawName(L, s)
  elseif mode == "battle" then
    part("view_battle").draw(L, s)
  elseif mode == "menu" or mode == "shop" then
    part("view_menu").draw(L, s)
  else
    local run = s.run
    drawGround(L, s, mode == "talk" and run and run.back or mode)
    if s.fx.fade > 0 or s.dark then ui.fill(0, 0, L.W, L.H, C.bg) end
    if mode == "talk" then part("view_talk").draw(L, s) end
  end
end

-- A state's picture stands until its rev moves on. Two, in case a save is being shown while another run's on the wall.
local pictures = {}

local function pictureFor(L, s)
  for _, picture in ipairs(pictures) do
    if picture.state == s and picture.rev == s.rev and picture.L == L then return picture end
  end
  local picture = pictures[2] or {}
  pictures[2], pictures[1] = pictures[1], picture
  local screen = ui.screen()
  if not picture.surf or picture.surf.width ~= screen.width or picture.surf.height ~= screen.height then
    picture.surf = screen:copy()
  end
  ui.setScreen(picture.surf)
  local ok, err = pcall(paint, L, s)
  ui.setScreen(screen)
  if not ok then error(err, 0) end -- the screen goes back first, or the shell's own drawing lands on a hidden surface
  picture.state, picture.rev, picture.L = s, s.rev, L
  return picture
end

function view.draw(L, s)
  local picture = pictureFor(L, s)
  ui.screen():drawSurface(picture.surf, 0, 0, L.W, L.H, 0, 0, L.W, L.H)
end

--- By mode. There may be no state at all: a tap can come in while the shell is between screens.
function view.actionAt(L, s, px, py)
  if not s then return nil end
  local mode = s.mode
  if mode == "name" then return part("view_talk").nameAt(L, px, py) end
  if mode == "battle" then return part("view_battle").actionAt(L, s, px, py) end
  if mode == "menu" or mode == "shop" then return part("view_menu").actionAt(L, s, px, py) end
  if mode == "talk" then return part("view_talk").actionAt(L, s, px, py) end
  if py >= part("view_world").HUD_Y then return { kind = "menu" } end -- the info bar along the bottom
  if mode == "world" then
    local x, y = part("view_world").worldTile(L, s, px, py)
    return { kind = "goto", x = x, y = y }
  end
  if base.inMiddle(L, px, py) then return { kind = "act" } end
  return base.splitAction(L, px, py)
end

--- For the saved game list.
function view.saveSummary(s)
  local map = part("maps").DATA[s.map]
  local place = s.mode == "world" and "the road" or (map and map.name or s.map)
  return "Level " .. s.level .. ", " .. place .. ", " .. s.gold .. " gold"
end

-- Which sounds each foe makes.
local FAMILY = {
  rat = "rat", crawler = "bug", harpy = "harpy", frogman = "frog", stalker = "stalker", orderly = "staff",
  doctor = "staff", blighted = "blighted", miner = "blighted", foreman = "boss",
}

--- A region's foe names its own family.
local function familyOf(id)
  if FAMILY[id] then return FAMILY[id] end
  local def = id and part("enemies").FOES[id]
  return def and def.family
end

-- What a script's { sfx = name } plays. A name not here plays the plain tap sound rather than nothing.
local SCRIPTED = { hit = "sword_hit", door = "door_open", horn = "horn", thud = "crush", coin = "coin" }

-- What each event sounds like. Names are in lib/sound_picks.lua.
local SFX = {
  step = "step", turn = "ui_page", page = "ui_page", pick = "ui_tap", bump = "wall", door = "door_open",
  unlock = "unlock", chest = "chest", gold = "coin", buy = "coin", item = "pickup", heal = "heal",
  join = "save", save = "save", fin = "level_clear", battle = "battle", wipe = "death", sting = "sting",
  hurt = "player_hurt", fall = "death", miss = "miss", defend = "block", menu = "ui_tap", spell = "spell",
  focus = "powerup", cure = "heal", status = "curse", telegraph = "telegraph", phase = "telegraph",
  cavein = "cave_in", fled = "flee", levelup = "level_up", win = "win_big", lose = "lose",
  hit = function(ev, app)
    app.audio.later(base.monster(familyOf(ev.id), "hurt"), 90)
    return "sword_hit"
  end,
  foeStrike = function(ev) return base.monster(familyOf(ev.id), "attack") end,
  kill = function(ev) return base.monster(familyOf(ev.id), "die") end,
  sfx = function(ev) return SCRIPTED[ev.name] or "ui_tap" end, -- a script's { sfx = name }
}

function view.onEvents(app, _, events)
  base.sfx(app, events, SFX)
end

--- No demo: the story isn't to be seen before it's played, so the idle screen never moves.
function view.demoStep() return false end

--- The title, over the one thing every player will see first: the great wall at night, with a crack in it.
function view.drawAttract(W, H)
  ui.fill(0, 0, W, H, C.bg)
  local wallY = floor(H * 0.52)
  ui.fill(0, wallY, W, H - wallY - 12, C.panel)
  for x = 0, W - 1, 8 do ui.fill(x, wallY - 2, 5, 2, C.panel) end
  for row = 0, 4 do ui.fill(0, wallY + 3 + row * 5, W, 1, C.bg) end
  local crack = floor(W * 0.62)
  for y = wallY - 2, H - 13 do
    ui.fill(crack + (y % 7 < 3 and 1 or -1), y, 2, 1, C.red)
  end
  ui.text("BLIGHTMARE", floor(W / 2), 8, C.red, "center", W - 2)
  ui.small("A wall, a plague, and a hero who has never dreamed", floor(W / 2), 17, C.line, C.bg, "center", W - 2)
  return H - 8
end

return base.fill({
  id = "blightmare", title = "BLIGHTMARE", blurb = "A wall, a plague, and a hero who has never dreamed", color = "red", accent = 0xE5484D,
  action = true, story = true, saves = true, tickMs = 120, minSize = { w = 120, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "A long story, saved as you go. SAVE & QUIT keeps your place, and so does walking away.",
    "",
    "On foot, tap the top of the wall to step forward and the bottom to step back. Tap a side to turn.",
    "",
    "The middle of the wall, between the four marks, is ACT. It talks, opens doors and chests, and starts a fight with what's ahead. With nothing ahead it walks forward. Tap the bar along the bottom for the menu: items, gear and how everyone is doing.",
    "",
    "On the map, tap anywhere and the party finds its own way there, round mountains and water. Tap the party to stop. Tap a town or dungeon to walk to it and go in. The bar along the bottom opens the menu here too.",
    "",
    "When someone is talking, tap anywhere to go on. A question waits for a tap on the answer.",
    "",
    "In a fight, gauges fill and a full one gives that character a turn. Time stands still while you choose. Top is ATTACK, left the character's special, right ITEM, bottom DEFEND. Then tap the target, or tap away to go back.",
    "",
    "If the whole party falls you wake at the last safe place, with half your gold gone.",
    "",
    "Lost? The purple mark on the map is where the story goes next, and an arrow points to it when it's further off. The bar along the bottom says what to do there.",
  },
})
