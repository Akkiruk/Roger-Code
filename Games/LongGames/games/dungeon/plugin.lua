-- games/dungeon/plugin.lua
-- A dungeon crawl as a classic, in the first person. The whole wall is the control: top a step forward, bottom a step back,
-- the sides turn, the middle is ACT. Nothing moves until the player does, so the picture is painted once for each change
-- into a surface of its own, and the shell's steady redraw only copies it across.

local base = require("lib.arcade.base")
local rules = require("games.dungeon.rules")
local scene = require("games.dungeon.scene")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor, min = math.floor, math.min

local DEMO_STEP_MS = 420       -- the idle screen walks, so it can be watched
local DEMO_LONGEST_STEPS = 400 -- and it gives way to the other games in the end
local HUD_H = 8                -- the status strip along the bottom
local MAP_COLS, MAP_ROWS = 15, 11
local MAP_CELL_W = 2           -- a map square is 2 cells wide and 1 tall, as near to square as a small map can be
local MAP_MARGIN = 1

local FACING_MARK = { "^", ">", "v", "<" }
local ACT_WORD = { attack = "FIGHT", door = "OPEN", locked = "UNLOCK", chest = "OPEN", stairs = "GO DOWN" }

local view = {}

function view.layout(W, H)
  local L = base.actionLayout(W, H, W, H - 7)
  L.viewX = floor((W - scene.VIEW_W) / 2)
  L.viewY = L.y0
  L.hudY = H - HUD_H
  L.statusY = L.y0 + 4 -- where the idle screen says to touch
  return L
end

--- A bar of filled cells, with the rest dark.
local function drawBar(x, y, w, share, color)
  ui.fill(x, y, w, 1, C.bg)
  local filled = math.max(share > 0 and 1 or 0, floor(w * min(1, share)))
  ui.fill(x, y, filled, 1, color)
end

local function hpColor(share)
  if share > 0.5 then return C.ok end
  return share > 0.25 and C.warn or C.red
end

--- The strip along the bottom. QUIT is the shell's, in the right-hand corner, so everything stays left of it.
local function drawHud(L, s)
  local p = s.p
  local y = L.hudY
  ui.fill(0, y, L.W, HUD_H, C.panel)
  ui.fill(0, y, L.W, 1, C.tie)
  local share = p.hp / p.maxHp
  ui.small("HP", 2, y + 2, C.text, C.panel)
  drawBar(5, y + 2, 30, share, hpColor(share))
  ui.small(p.hp .. "/" .. p.maxHp, 37, y + 2, hpColor(share), C.panel)
  ui.small("LV " .. p.lvl, 46, y + 2, C.hi, C.panel)
  drawBar(52, y + 2, 16, p.xp / rules.xpFor(p.lvl), C.accent)
  ui.small("POTIONS " .. p.potions, 71, y + 2, p.potions > 0 and C.text or C.line, C.panel)
  ui.small("KEYS " .. p.keys, 82, y + 2, p.keys > 0 and C.hi or C.line, C.panel)
  ui.small("GOLD " .. p.gold, 90, y + 2, C.hi, C.panel, "left", 15)
  ui.small(rules.SWORDS[p.sword].name .. " +" .. rules.attackPower(p), 2, y + 4, C.text, C.panel)
  ui.small(rules.ARMOURS[p.armour].name .. " +" .. rules.armourOf(p), 26, y + 4, C.text, C.panel)
  ui.small("DEPTH " .. s.level .. " OF " .. rules.DEPTHS, 46, y + 4, C.line, C.panel)
  ui.small("BEATEN " .. p.kills, 62, y + 4, C.line, C.panel)
  ui.small(s.msg, 2, y + 6, C.hi, C.panel, "left", L.W - 18)
end

local function mapInk(s, x, y)
  if x < 1 or y < 1 or x > rules.WIDTH or y > rules.HEIGHT then return C.bg end
  if s.seen[y]:sub(x, x) == "0" then return C.bg end
  local c = rules.tileAt(s, x, y)
  if c == rules.WALL then return C.panel end
  if c == rules.DOOR then return C.warn end
  if c == rules.LOCKED then return C.red end
  if c == rules.STAIRS then return C.hi end
  if rules.chestAt(s, x, y) then return C.warn end
  return C.line
end

--- The automap in the top right corner, following the player, in runs of colour along each row.
local function drawMap(L, s)
  local boxW, boxH = MAP_COLS * MAP_CELL_W + 2, MAP_ROWS + 2
  local x0, y0 = L.W - boxW - MAP_MARGIN, L.viewY + MAP_MARGIN
  ui.fill(x0, y0, boxW, boxH, C.bg)
  ui.frame(x0, y0, boxW, boxH, C.tie)
  local left, top = s.x - floor(MAP_COLS / 2) - 1, s.y - floor(MAP_ROWS / 2) - 1
  for row = 1, MAP_ROWS do
    local from, ink = 1, mapInk(s, left + 1, top + row)
    for col = 2, MAP_COLS + 1 do
      local here = col <= MAP_COLS and mapInk(s, left + col, top + row) or nil
      if here ~= ink then
        if ink ~= C.bg then ui.fill(x0 + 1 + (from - 1) * MAP_CELL_W, y0 + row, (col - from) * MAP_CELL_W, 1, ink) end
        from, ink = col, here
      end
    end
  end
  local px, py = x0 + 1 + floor(MAP_COLS / 2) * MAP_CELL_W, y0 + 1 + floor(MAP_ROWS / 2)
  ui.small(FACING_MARK[s.dir] .. " ", px, py, C.bg, C.hi)
end

--- The name and health of whatever you're facing.
local function drawFoe(L, s)
  local x, y = rules.ahead(s)
  local m = rules.monsterAt(s, x, y)
  if not m then return end
  local name = rules.MONSTERS[m.kind].name
  local cx = floor(L.W / 2)
  ui.small(" " .. name .. " ", cx, L.viewY + 1, C.text, C.bg, "center")
  ui.fill(cx - 13, L.viewY + 2, 26, 1, C.bg)
  drawBar(cx - 12, L.viewY + 2, 24, m.hp / m.maxHp, C.red)
end

--- What ACT would do, under the middle of the wall, and the potion choice when one is open.
local function drawPrompt(L, s)
  local cx, cy = floor(L.W / 2), floor(L.H / 2)
  if s.menu then
    ui.fill(cx - 21, cy - 5, 42, 11, C.panel)
    ui.frame(cx - 21, cy - 5, 42, 11, C.hi)
    ui.small("DRINK A POTION?", cx, cy - 3, C.hi, C.panel, "center")
    ui.small("You have " .. s.p.potions .. ", and " .. s.p.hp .. " of " .. s.p.maxHp .. " HP", cx, cy - 1, C.text, C.panel, "center")
    ui.small("MIDDLE: DRINK", cx, cy + 1, C.ok, C.panel, "center")
    ui.small("ANYWHERE ELSE: NOT NOW", cx, cy + 3, C.line, C.panel, "center")
    return
  end
  local word = ACT_WORD[rules.target(s) or ""]
  if word and not s.over then ui.small(" " .. word .. " ", cx, cy + 11, C.hi, C.bg, "center") end
end

--- The depth, for a moment after arriving.
local function drawBanner(L, s)
  if s.fx.banner <= 0 then return end
  local cx = floor(L.W / 2)
  local word = "DEPTH " .. s.level
  local w = ui.textWidth(word) + 6
  local y = L.viewY + 5
  ui.fill(cx - floor(w / 2), y, w, ui.fontHeight() + 2, C.bg)
  ui.text(word, cx, y + 1, s.level == rules.DEPTHS and C.red or C.hi, "center")
end

local function paint(L, s)
  scene.draw(L.viewX, L.viewY, s)
  if s.fx.fire > 0 then ui.frame(0, L.viewY, L.W, L.hudY - L.viewY, C.warn, 3) end
  if s.fx.hurt > 0 then ui.frame(0, L.viewY, L.W, L.hudY - L.viewY, C.red, 2) end
  drawMap(L, s)
  drawFoe(L, s)
  drawBanner(L, s)
  drawHud(L, s)
  base.drawMiddle(L, C.text)
  drawPrompt(L, s)
end

-- Two pictures, because a cabinet with two walls can show a different demo on each. A state's picture stands until its rev moves on.
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
  paint(L, s)
  ui.setScreen(screen)
  picture.state, picture.rev, picture.L = s, s.rev, L
  return picture
end

function view.draw(L, s)
  local picture = pictureFor(L, s)
  ui.screen():drawSurface(picture.surf, 0, L.y0, L.W, L.bh, 0, L.y0, L.W, L.bh)
end

--- The whole wall steers. The middle is ACT, and when the potion choice is open a side says no.
function view.actionAt(L, _, px, py)
  if base.inMiddle(L, px, py) then return { kind = "act" } end
  return base.splitAction(L, px, py)
end

--- For the saved game list.
function view.saveSummary(s)
  return "Depth " .. s.level .. ", " .. s.p.hp .. " HP"
end

--- One sound of each kind a step: a fight can bring several of the same.
-- What each event sounds like. Names are in lib/sound_picks.lua.
local SFX = {
  step = "step", turn = "swish", bump = "wall", miss = "miss", dodge = "miss", trap = "player_hurt",
  fire = "flame", door = "door_open", unlock = "unlock", chest = "chest", gold = "coin", potion = "potion",
  key = "pickup", gear = "pickup", drink = "drink", levelup = "level_up", descend = "step", win = "win_big",
  death = "death",
  hit = function(ev, app)
    app.audio.later(base.monster(ev.kind, "hurt"), 90)
    return "sword_hit"
  end,
  hurt = function(ev, app)
    app.audio.later("player_hurt", 90)
    return base.monster(ev.kind, "attack")
  end,
  kill = function(ev) return base.monster(ev.kind, "die") end,
}

function view.onEvents(app, _, events)
  base.sfx(app, events, SFX)
end

local function demoRng(n)
  if n then return math.random(n) end
  return math.random()
end

--- The idle screen: the bot at walking pace. A stair-diving run could last an hour, so a demo stops after a while.
function view.demoStep(demo, t)
  if not demo.state or (demo.finishedAt and t - demo.finishedAt > 5000) then
    demo.state, demo.nextAt, demo.finishedAt, demo.steps = rules.new({ rng = demoRng }), t + 800, nil, 0
    demo.match = { state = demo.state }
    return true
  end
  if demo.finishedAt or t < demo.nextAt then return false end
  demo.nextAt = t + DEMO_STEP_MS
  demo.steps = demo.steps + 1
  local action = rules.bot(demo.state, demoRng)
  if action then rules.input(demo.state, action) end
  rules.tick(demo.state, demoRng)
  if demo.state.over or demo.steps >= DEMO_LONGEST_STEPS then demo.finishedAt = t end
  return true
end

return base.fill({
  id = "dungeon", title = "Dungeon", blurb = "Ten depths, one sword, a dragon", color = "warn", accent = 0xFFD257,
  action = true, split = true, splitMiddle = "ACT", tickMs = 120, saves = true, minSize = { w = 120, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Go down through ten depths and kill the dragon at the bottom. You get one life, and nothing moves until you do.",
    "",
    "Tap the top of the wall to step forward and the bottom to step back. Tap a side to turn: turning takes no time.",
    "",
    "The middle of the wall, between the four marks, is ACT. It attacks what's ahead, opens a door or a chest, or takes the stairs. Each of those gives the monsters a turn, and so does a step.",
    "",
    "With nothing ahead, ACT offers a potion. Tap the middle again to drink it, anywhere else to put it back. In a fight, turn to a wall first.",
    "",
    "Walk over gold, potions, keys and gear to take them. A red door needs a key. Chests can bite, and the floor can hide spikes. Walking slowly heals you.",
    "",
    "The map in the corner fills in as you go. Yellow on it is the stairs. Bats flit about, slimes are slow, and ghosts come through doors.",
    "",
    "You score for gold, monsters beaten and each new depth, and a great deal for the dragon.",
  },
})
