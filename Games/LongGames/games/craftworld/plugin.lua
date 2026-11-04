-- games/craftworld/plugin.lua
-- CRAFT WORLD: a side-on world of blocks to dig, build and live in, for one player over many visits. The whole wall is the
-- world: a tap beside the player digs or builds, a tap further off walks or jumps, and the bar along the bottom holds the
-- hotbar and opens the menu. Nothing moves until the player does, so a slow tap never costs anything.

local base = require("lib.arcade.base")
local rules = require("games.craftworld.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor

local DEMO_STEP_MS = 260
local DEMO_LONGEST_STEPS = 700

-- The pictures load when first drawn, so the rules can be tested with none of them there.
local function paintView() return require("games.craftworld.view") end

local view = {}

function view.layout(W, H)
  return paintView().layout(W, H)
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
  local ok, err = pcall(paintView().paint, L, s)
  ui.setScreen(screen)
  if not ok then error(err, 0) end -- the screen goes back first, or the shell's own drawing lands on a hidden surface
  picture.state, picture.rev, picture.L = s, s.rev, L
  return picture
end

function view.draw(L, s)
  local picture = pictureFor(L, s)
  ui.screen():drawSurface(picture.surf, 0, 0, L.W, L.H, 0, 0, L.W, L.H)
end

function view.actionAt(L, s, px, py)
  return paintView().actionAt(L, s, px, py)
end

function view.controls() return {} end

--- For the saved game list.
function view.saveSummary(s)
  local st = s.stats
  return "Day " .. rules.dayNumber(s) .. ", deepest " .. st.deepest .. ", " .. st.diamonds .. " diamond" .. (st.diamonds == 1 and "" or "s")
end

--- For the list of everyone's games and the play tracker.
function view.progress(s)
  return rules.progress(s)
end

-- What each event sounds like. Names are in lib/sound_picks.lua.
local SFX = {
  step = "step", swim = "splash", splash = "splash", jump = "jump", land = "step", bump = "wall", place = "piece_a",
  pickup = "pickup", eat = "drink", craft = "clang", smelt = "flame", menu = "ui_tap", select = "ui_select", refuse = "ui_error",
  goal = "level_up", death = "death", sleep = "save", spawnset = "save", dusk = "bell", dawn = "level_clear", shoot = "missile",
  dig = function(ev)
    local c = ev.tile
    if c == "s" or c == "c" or c == "k" or c == "i" or c == "o" or c == "x" or c == "F" then return "brick" end
    return "dig"
  end,
  ["break"] = function(ev)
    if ev.ore then return "coin" end
    if ev.tile == "f" or ev.tile == "y" then return "smash" end
    return "pickup"
  end,
  hurt = function(ev) return ev.from and base.monster(ev.from == "zombie" and "blighted" or ev.from, "attack") or "player_hurt" end,
  hit = function(ev, app)
    local family = ev.kind == "skeleton" and "skeleton" or nil
    app.audio.later(base.monster(family, "hurt"), 90)
    return "sword_hit"
  end,
  kill = function(ev) return base.monster(ev.kind == "skeleton" and "skeleton" or nil, "die") end,
}

function view.onEvents(app, _, events)
  base.sfx(app, events, SFX)
end

local function demoRng(n)
  if n then return math.random(n) end
  return math.random()
end

--- The idle screen: the bot at a pace that can be watched. It starts again after a while, in a new world.
function view.demoStep(demo, t)
  if not demo.state or (demo.finishedAt and t - demo.finishedAt > 3000) then
    demo.state, demo.nextAt, demo.finishedAt, demo.steps = rules.new({ rng = demoRng }), t + 800, nil, 0
    demo.state.hint = 0
    demo.match = { state = demo.state }
    return true
  end
  if demo.finishedAt or t < demo.nextAt then return false end
  demo.nextAt = t + DEMO_STEP_MS
  demo.steps = demo.steps + 1
  local action = rules.bot(demo.state, demoRng)
  if action then rules.input(demo.state, action) end
  rules.tick(demo.state, demoRng)
  if demo.steps >= DEMO_LONGEST_STEPS then demo.finishedAt = t end
  return true
end

--- The bot digging away, with the title over the sky.
function view.drawAttract(W, H, demo)
  local L = view.layout(W, H)
  if demo and demo.state then
    view.draw(L, demo.state)
  else
    ui.fill(0, 0, W, H, C.blue)
  end
  ui.fill(0, 0, W, 10, C.bg)
  ui.text("CRAFT WORLD", floor(W / 2), 1, C.ok, "center", W - 2)
  return H - 30
end

return base.fill({
  id = "craftworld", title = "CRAFT WORLD", short = "CRAFT", blurb = "Dig, build and survive in a world of blocks",
  color = "ok", accent = 0xEED78F,
  action = true, story = true, saves = true, tickMs = 120, minSize = { w = 120, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "A world of blocks, side on, that goes on for ever left and right and a long way down. Your world is saved as you go: SAVE & QUIT keeps it, and so does walking away.",
    "",
    "Nothing moves until you do. Every step you take, every swing of the pickaxe, the monsters and the clock take one too.",
    "",
    "Tap a block right beside you (or above, below, or corner to corner) to dig it. Hard blocks take a few taps, and stone and ores need a pickaxe.",
    "",
    "Tap the wall further off to the left or right to walk that way: you climb one block by yourself. Tap high above you to jump. Tap a monster or an animal beside you to hit it.",
    "",
    "The bar along the bottom holds your blocks. Tap one to hold it, then tap an empty space beside you to put it there. The hand, on the left, puts nothing down. Tap yourself to eat.",
    "",
    "Tap the line above the bar for the menu: CRAFT makes things (some need a crafting table or a furnace close by), ITEMS puts anything in your hand, GOALS shows how far you've come.",
    "",
    "Start by chopping a tree. Logs make planks, planks make sticks and a crafting table, and those make a wooden pickaxe. Then dig down for stone, coal for torches, iron, and diamonds deep below.",
    "",
    "Monsters come out at night, and in dark caves: torches keep the dark away. Make a bed from wool and planks, and sleep through the night. Leaves drop apples; animals give meat to cook.",
    "",
    "If you faint you wake at your bed, or where you began, with all your things.",
  },
})
