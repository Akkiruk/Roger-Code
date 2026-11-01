-- games/druaga/plugin.lua
-- The Tower of Druaga as an Arcade classic. The whole wall steers, and the middle of the wall draws or sheathes the sword.
-- Cells are 8 wide and 6 tall with one line of wall between them, which leaves a 7 x 5 sprite. The strip under the board has
-- the riddle, the timer, his strength and what he carries.

local base = require("lib.arcade.base")
local rules = require("games.druaga.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local COLS, ROWS = rules.COLS, rules.ROWS
local CELL_W, CELL_H = 8, 6
local STRIP_W = 105            -- the strip stops short of QUIT

-- The tower changes colour as it goes up.
local BRICKS = { C.warn, C.info, C.soft, C.accent, C.red, C.blue, C.line }

local INK = {
  ["h"] = C.hi, ["w"] = C.text, ["b"] = C.blue, ["o"] = C.warn, ["r"] = C.red, ["g"] = C.ok, ["k"] = C.bg,
  ["s"] = C.soft, ["l"] = C.line, ["p"] = C.tie, ["a"] = C.accent, ["c"] = C.info, ["d"] = C.redTint,
}

-- Sprites, one string for each row, 7 wide and 5 tall, drawn facing right. A letter is a colour from INK; "." is left as it is.
local GIL = { "..hhh..", "..hkw..", ".oooo..", ".oooo..", "..l.l.." }
local GIL_STEP = { "..hhh..", "..hkw..", ".oooo..", ".oooo..", ".l...l." }
local GIL_UP = { "..hhh..", "..hhh..", ".oooo..", ".oooo..", "..l.l.." }
local GIL_DOWN = { "..hhh..", "..wkw..", ".oooo..", ".oooo..", "..l.l.." }
local SLIME = { ".......", "..xxx..", ".xwxwx.", "xxxxxxx", "x.xxx.x" }
local SLIME_B = { ".......", ".......", ".xxxxx.", "xwxxxwx", "xxxxxxx" }
local KNIGHT = { "..xxx..", "..xkw..", ".xxxxl.", ".xxxxl.", "..x.x.." }
local KNIGHT_B = { "..xxx..", "..xkw..", ".xxxxl.", ".xxxxl.", ".x...x." }
local MAGE = { "...x...", "..xxx..", "..wkw..", ".xxxxx.", ".xxxxx." }
local MAGE_GLOW = { "..hxh..", ".hxxxh.", "..wkw..", "hxxxxxh", ".xxxxx." }
local WISP = { "...x...", "..xhx..", ".xhwhx.", "..xhx..", "...x..." }
local WISP_B = { "..x.x..", ".xhxhx.", "..hwh..", ".xhxhx.", "..x.x.." }
local ROPER = { "x.x.x.x", ".xxxxx.", ".xwxwx.", ".xxxxx.", "x.x.x.x" }
local ROPER_B = { ".x.x.x.", "x.xxx.x", ".xwxwx.", "x.xxx.x", ".x.x.x." }
local DRAGON = { "..xx...", ".xxkxx.", "xxxxxxx", "xx.xxx.", "x..x.x." }
local DRAGON_GLOW = { "..xx...", ".xxkxxh", "xxxxxoo", "xx.xxx.", "x..x.x." }
local KEY = { ".......", ".hh....", "h..hhhh", ".hh..h.", "......." }
local DOOR = { ".ddddd.", ".dddhd.", ".dddhd.", ".ddddd.", ".ddddd." }
local DOOR_OPEN = { ".ddddd.", ".dkkkd.", ".dkkkd.", ".dkkkd.", ".dkkkd." }
local CHEST = { ".......", ".ddddd.", "dhhhhhd", "ddhdhdd", "ddddddd" }
local KI = { "..aaa..", ".aawaa.", "..www..", ".ccccc.", ".ccccc." }
local DRUAGA = {
  "...r.......r...", "..rr.......rr..", "..rrrrrrrrrrr..", ".rrhhrrrrrhhrr.", ".rrkhrrrrrhkrr.", "rrrrrrkkkrrrrrr",
  "rr.rrrrrrrrr.rr", "rr.aaaaaaaaa.rr", "...aaaaaaaaa...", "...aa.aaa.aa...", "..aa...a...aa..",
}

-- Each enemy's sprites and main colour.
local LOOKS = {
  green = { SLIME, SLIME_B, C.ok }, black = { SLIME, SLIME_B, C.tie }, red = { SLIME, SLIME_B, C.red },
  blueKnight = { KNIGHT, KNIGHT_B, C.blue }, greenKnight = { KNIGHT, KNIGHT_B, C.ok },
  redKnight = { KNIGHT, KNIGHT_B, C.red }, blackKnight = { KNIGHT, KNIGHT_B, C.tie },
  mage = { MAGE, MAGE, C.accent }, ghost = { MAGE, MAGE, C.info },
  wisp = { WISP, WISP_B, C.blue }, hunter = { WISP, WISP_B, C.red },
  roper = { ROPER, ROPER_B, C.soft }, dragon = { DRAGON, DRAGON, C.ok }, silverDragon = { DRAGON, DRAGON, C.line },
}

local function mirrored(sprite)
  local out = {}
  for i, line in ipairs(sprite) do out[i] = line:reverse() end
  return out
end

local function cellX(L, x) return L.x0 + 1 + (x - 1) * CELL_W end
local function cellY(L, y) return L.y0 + 1 + (y - 1) * CELL_H end

--- x is the colour of the sprite's owner.
local function drawSprite(sprite, x, y, color, flip)
  for row, line in ipairs(flip and mirrored(sprite) or sprite) do
    local from = 1
    while from <= #line do
      local ink = line:sub(from, from)
      local to = from
      while line:sub(to + 1, to + 1) == ink do to = to + 1 end
      if ink ~= "." then ui.fill(x + from - 1, y + row - 1, to - from + 1, 1, ink == "x" and color or INK[ink]) end
      from = to + 1
    end
  end
end

--- Where an actor shows: on its way from the last cell, by how much of the next one it has banked.
local function actorAt(L, a)
  local t = math.min(1, math.max(0, a.budget) / 100)
  if a.px == a.x and a.py == a.y then t = 1 end
  return floor(cellX(L, a.px + (a.x - a.px) * t) + 0.5), floor(cellY(L, a.py + (a.y - a.py) * t) + 0.5)
end

--- Walls, joined along each line so a wall costs one fill and not one for every cell.
local function drawWalls(L, s)
  local brick = BRICKS[(s.level - 1) % #BRICKS + 1]
  ui.frame(L.x0, L.y0, COLS * CELL_W + 1, ROWS * CELL_H + 1, brick)
  for y = 1, ROWS - 1 do
    local x = 1
    while x <= COLS do
      if s.below[y][x] then
        local from = x
        while x < COLS and s.below[y][x + 1] do x = x + 1 end
        ui.fill(L.x0 + (from - 1) * CELL_W, L.y0 + y * CELL_H, (x - from + 1) * CELL_W + 1, 1, brick)
      end
      x = x + 1
    end
  end
  for x = 1, COLS - 1 do
    local y = 1
    while y <= ROWS do
      if s.right[y][x] then
        local from = y
        while y < ROWS and s.right[y + 1][x] do y = y + 1 end
        ui.fill(L.x0 + x * CELL_W, L.y0 + (from - 1) * CELL_H, 1, (y - from + 1) * CELL_H + 1, brick)
      end
      y = y + 1
    end
  end
end

local function drawFixtures(L, s)
  local door = s.door
  if s.level >= rules.TOP then
    drawSprite(KI, cellX(L, door.x), cellY(L, door.y))
    if not s.hasKey then ui.fill(cellX(L, door.x), cellY(L, door.y) + 3, 7, 1, C.line) end
  else
    drawSprite(s.hasKey and DOOR_OPEN or DOOR, cellX(L, door.x), cellY(L, door.y))
  end
  if rules.keyShown(s) then drawSprite(KEY, cellX(L, s.key.x), cellY(L, s.key.y)) end
  local chest = s.chest
  if chest and chest.shown then drawSprite(CHEST, cellX(L, chest.x), cellY(L, chest.y)) end
end

--- Druaga fills two cells each way, and flashes when he's hit.
local function drawDruaga(L, s, e)
  local x, y = cellX(L, e.x), cellY(L, e.y)
  if e.hit > 0 and s.frame % 2 == 0 then
    ui.fill(x, y, 15, 11, C.text)
    return
  end
  drawSprite(DRUAGA, x, y)
  if e.mode == "cast" then ui.frame(x, y, 15, 11, s.frame % 2 == 0 and C.hi or C.red) end
end

local function drawEnemy(L, s, e)
  if e.kind == "druaga" then
    drawDruaga(L, s, e)
    return
  end
  local look = LOOKS[e.kind]
  local x, y = actorAt(L, e)
  if e.hidden then
    -- a faded ghost mage is only a flicker, for anyone watching closely
    if s.frame % 4 == 0 then ui.fill(x + 3, y + 2, 1, 1, C.info) end
    return
  end
  local color = look[3]
  if e.hit > 0 then color = C.text end
  local sprite = look[1 + floor(s.frame / 2) % 2]
  if e.mode == "cast" then sprite = MAGE_GLOW end
  if e.mode == "windup" then sprite = DRAGON_GLOW end
  drawSprite(sprite, x, y, color, e.dir == "left")
  if e.guard then ui.fill(x + 2, y, 3, 1, C.text) end
end

--- A spell is a spark. Fire is a tail of three, coming back from its head.
local function drawSpells(L, s)
  for _, spell in ipairs(s.spells) do
    local x, y = cellX(L, spell.x), cellY(L, spell.y)
    if spell.kind == "fire" then
      local d = rules.DIRECTIONS[spell.dir]
      ui.fill(x, y + 1, 7, 3, C.warn)
      ui.fill(x + 2, y + 2, 3, 1, C.hi)
      if rules.FIRE_REACH - spell.left >= 1 then ui.fill(x - d[1] * CELL_W, y + 1 - d[2] * CELL_H, 7, 3, C.red) end
    else
      local on = s.frame % 2 == 0
      ui.fill(x + 2, y + 1, 3, 3, on and C.text or C.info)
      ui.fill(x + 3, y + 2, 1, 1, on and C.info or C.text)
    end
  end
end

--- Sword out in front of him, or the shield on the side he faces.
local function drawArms(s, x, y, dir)
  local p = s.player
  local d = rules.DIRECTIONS[p.dir]
  if s.drawn then
    local swung = p.swing > 0
    local tipX, tipY = x + 3 + d[1] * (swung and 6 or 5), y + 2 + d[2] * (swung and 4 or 3)
    ui.line(x + 3 + d[1] * 2, y + 2 + d[2], tipX, tipY, s.items.sword >= 3 and C.hi or C.text)
    return
  end
  local color = s.items.shield >= 2 and C.hi or C.info
  if dir == "right" then ui.fill(x + 5, y + 1, 2, 3, color) end
  if dir == "left" then ui.fill(x, y + 1, 2, 3, color) end
  if dir == "up" then ui.fill(x + 1, y, 5, 2, color) end
  if dir == "down" then ui.fill(x + 1, y + 3, 5, 2, color) end
end

local function drawGil(L, s)
  local p = s.player
  local x, y = actorAt(L, p)
  if s.after == "life" then
    local squash = math.min(4, floor((rules.DEATH_TICKS - s.pause) / 2))
    ui.fill(x + 1, y + squash, 5, CELL_H - 1 - squash, s.frame % 2 == 0 and C.text or C.hi)
    return
  end
  if s.safe > 0 and s.frame % 2 == 0 then return end
  local dir = p.dir
  local stepping = p.walk and s.frame % 4 < 2
  if dir == "up" then
    drawSprite(GIL_UP, x, y, nil)
  elseif dir == "down" then
    drawSprite(GIL_DOWN, x, y, nil)
  else
    drawSprite(stepping and GIL_STEP or GIL, x, y, nil, dir == "left")
  end
  drawArms(s, x, y, dir)
end

local function drawBursts(L, s)
  for _, b in ipairs(s.bursts) do
    local x, y = cellX(L, b.x), cellY(L, b.y)
    local spread = 3 - b.left
    ui.fill(x + 3 - spread, y + 2, 1, 1, C.text)
    ui.fill(x + 3 + spread, y + 2, 1, 1, C.text)
    ui.fill(x + 3, y + math.max(0, 2 - spread), 1, 1, C.hi)
    ui.fill(x + 3, y + math.min(CELL_H - 2, 2 + spread), 1, 1, C.hi)
  end
end

local function banner(L, y, text, color)
  ui.small("  " .. text .. "  ", L.x0 + floor(L.bw / 2), y, color, C.bg, "center")
end

local function drawNotes(L, s)
  for _, n in ipairs(s.popups) do
    local x = math.max(L.x0 + floor(#n.text / 2), math.min(cellX(L, n.x) + 3, L.x0 + L.bw - math.ceil(#n.text / 2)))
    ui.small(n.text, x, cellY(L, n.y) + 2, C.text, C.bg, "center")
  end
  local y = L.y0 + 8
  if s.ready then
    banner(L, y, "FLOOR " .. s.level, C.hi)
    banner(L, y + 2, rules.riddle(s), C.text)
  elseif s.note then
    banner(L, y, s.note.text, C.hi)
  elseif s.after == "floor" then
    banner(L, y, "FLOOR CLEAR!", C.hi)
  elseif s.after == "won" then
    banner(L, y, "KI IS FREE!", C.hi)
  end
end

--- A bar that shows what's left, by colour as it runs out.
local function drawBar(x, y, w, part, whole, color)
  ui.fill(x, y, w, 1, C.panel)
  ui.fill(x, y, math.max(0, floor(w * part / whole + 0.5)), 1, color)
end

--- What he carries, as short words: the original showed it the same way along the bottom.
local function carried(s)
  local got = s.items
  local list = { ({ "COPPER", "SILVER", "EXCALIBUR" })[got.sword] }
  if got.shield >= 2 then list[#list + 1] = "HYPER" end
  if got.pick then list[#list + 1] = "PICK " .. s.picks end
  if got.boots then list[#list + 1] = "JET" end
  if got.balance then list[#list + 1] = "BALANCE" end
  if got.potions > 0 then list[#list + 1] = "POTION " .. got.potions end
  return table.concat(list, " ")
end

--- The strip under the board: the riddle, then time and strength, then what he has.
local function drawStrip(L, s)
  local y = L.y0 + L.bh + 2
  ui.small(rules.riddle(s), 1, y, C.text, C.bg, "left", STRIP_W)
  local timeLeft = s.timer / rules.floorTicks(s.level)
  local seconds = math.ceil(s.timer / rules.SECOND)
  ui.small("TIME", 1, y + 2, C.line, C.bg, "left")
  drawBar(6, y + 2, 30, s.timer, rules.floorTicks(s.level), timeLeft < 0.2 and C.red or C.info)
  ui.small(s.timer > 0 and tostring(seconds) or "HURRY", 37, y + 2, s.timer > 0 and C.text or C.red, C.bg, "left")
  ui.small("HP", 44, y + 2, C.line, C.bg, "left")
  drawBar(47, y + 2, 20, s.hp, rules.MAX_HP, s.hp <= 12 and C.red or C.ok)
  ui.small(s.drawn and "SWORD" or "SHIELD", 69, y + 2, s.drawn and C.text or C.info, C.bg, "left")
  if s.hasKey then ui.small("KEY", 76, y + 2, C.hi, C.bg, "left") end
  ui.small(carried(s), 1, y + 4, C.line, C.bg, "left", STRIP_W)
end

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, COLS * CELL_W, ROWS * CELL_H)
end

local function drawTower(L, s)
  ui.fill(L.x0, L.y0, L.bw + 1, L.bh + 1, C.bg)
  drawWalls(L, s)
  drawFixtures(L, s)
  for _, e in ipairs(s.enemies) do drawEnemy(L, s, e) end
  drawSpells(L, s)
  drawGil(L, s)
  drawBursts(L, s)
  drawNotes(L, s)
end

function view.draw(L, s)
  drawTower(L, s)
  drawStrip(L, s)
  base.drawMiddle(L, C.text)
end

--- The idle screen: its prompt goes where the strip would be.
function view.drawBoard(L, match)
  drawTower(L, match.state)
end

--- The whole wall steers: tap the side you want. The middle of the wall is the sword.
function view.actionAt(L, _, px, py)
  if base.inMiddle(L, px, py) then return { kind = "sword" } end
  return base.splitAction(L, px, py)
end

--- A short line for the saved game list.
function view.saveSummary(s)
  return string.format("Floor %d, %d %s", s.level, s.lives, s.lives == 1 and "life" or "lives")
end

--- A busy step can hold many of one thing: one sound of each is plenty.
-- Which sounds each enemy makes.
local FAMILY = {
  green = "slime", black = "slime", red = "slime", blueKnight = "knight", greenKnight = "knight",
  redKnight = "knight", blackKnight = "knight", mage = "mage", ghost = "ghost", wisp = "ghost",
  hunter = "ghost", roper = "roper", dragon = "dragon", silverDragon = "dragon", druaga = "boss",
}

-- What each event sounds like. Names are in lib/sound_picks.lua.
local SFX = {
  sword = "sword", clink = "clang", block = "block", charge = "telegraph", spell = "spell", fire = "flame",
  windup = "telegraph", jump = "jump", dig = "dig", key = "pickup", knock = "knock", chest = "chest",
  item = "pickup", potion = "potion", timeUp = "ui_warning", zap = "teleport", death = "death",
  clear = "level_clear", win = "level_clear",
  hit = function(ev, app)
    app.audio.later(base.monster(FAMILY[ev.kind], "hurt"), 90)
    return "sword_hit"
  end,
  clash = function(ev, app)
    app.audio.later("player_hurt", 90)
    return base.monster(FAMILY[ev.kind], "attack")
  end,
  kill = function(ev) return base.monster(FAMILY[ev.kind], "die") end,
}

function view.onEvents(app, _, events)
  base.sfx(app, events, SFX)
end

return base.fill({
  id = "druaga", title = "Tower of Druaga", blurb = "Twenty floors, one sword, one shield", color = "hi",
  action = true, split = true, splitMiddle = "SWORD", tickMs = 140, saves = true, minSize = { w = 120, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "The knight Gilgamesh climbs twenty floors to free Ki from the demon Druaga. On each floor, find the key, then reach the door before the timer runs out. You have three lives.",
    "",
    "Tap the side of the wall you want to go: the top goes up, the bottom down, the left side left and the right side right. He keeps walking until a wall stops him, and a turn waits for the next opening.",
    "",
    "The middle of the wall, between the four marks, draws or sheathes the sword. You get one or the other.",
    "",
    "Sword out: walk into an enemy to fight it, and nothing can walk into you. But any spell kills you.",
    "",
    "Sword away: your shield stops spells from the way you face. But anything that touches you kills you.",
    "",
    "Knights trade blows and wear down your HP, which fills again on each floor. Mages glow before they cast, and walls stop spells. A ghost mage is faded until it glows. Ropers reach two cells. Dragons breathe in, then fire along a line. Wisps follow the walls, and nothing stops them, so get out of the way.",
    "",
    "Every floor hides a chest. The line under the board is a riddle saying what brings it out. Keep what you find: some doors zap you back down the tower if you left a chest behind.",
    "",
    "With the pick-axe, stop at a wall and tap it twice to break it. It works twice on each floor. A potion saves your life once. On dark floors the key can't be seen until you're close, unless you have the Balance.",
    "",
    "When time runs out, red wisps come for you. Time left on the clock is a bonus.",
  },
})
