-- games/bomberman/plugin.lua
-- Bomberman on two walls. Both players see the same arena from the same side, and each wall marks its own player's bomber.
-- The whole wall steers, split corner to corner, and the middle is BOMB. Tiles are 9 wide and 6 tall, which looks square.
-- The shell clears each wall every step, so the arena is kept on a surface of its own: only tiles that changed are painted
-- there, it's copied to each wall in one go, and only what moves is drawn over it.

local base = require("lib.arcade.base")
local rules = require("games.bomberman.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local COLS, ROWS = rules.COLS, rules.ROWS
local TILES = COLS * ROWS
local CELL_W, CELL_H = 9, 6
local WARN_TILES = 3          -- tiles of sudden death shown before they fall
local PLAYER_COLOR = { C.red, C.blue }
local PLAYER_NAME = { "RED", "BLUE" }

local ITEMS = {
  bomb = { code = 1, letter = "B", color = C.accent },
  flame = { code = 2, letter = "F", color = C.warn },
  boots = { code = 3, letter = "S", color = C.ok },
  kick = { code = 4, letter = "K", color = C.info },
}

-- Sprites, one string for each row. A letter is a colour; "c" is the bomber's own, and "." is left as it is.
local INK = { w = C.text, k = C.bg, l = C.line }
local BOMBER = {
  down = { { "..wwwww..", "..wkwkw..", "..wwwww..", ".ccccccc.", "..ccccc..", "..l...l.." },
           { "..wwwww..", "..wkwkw..", "..wwwww..", ".ccccccc.", "..ccccc..", "...l.l..." } },
  up = { { "..wwwww..", "..wwwww..", "..wwwww..", ".ccccccc.", "..ccccc..", "..l...l.." },
         { "..wwwww..", "..wwwww..", "..wwwww..", ".ccccccc.", "..ccccc..", "...l.l..." } },
  right = { { "..wwwww..", "..wwkwk..", "..wwwww..", "..cccccc.", "..ccccc..", "..l...l.." },
            { "..wwwww..", "..wwkwk..", "..wwwww..", "..cccccc.", "..ccccc..", "...l.l..." } },
}
BOMBER.left = {}
for i, frame in ipairs(BOMBER.right) do
  BOMBER.left[i] = {}
  for row, line in ipairs(frame) do BOMBER.left[i][row] = line:reverse() end
end

local function tileX(L, x) return L.x0 + (x - 1) * CELL_W end
local function tileY(L, y) return L.y0 + (y - 1) * CELL_H end

local function drawSprite(sprite, x, y, own)
  for row, line in ipairs(sprite) do
    local from = 1
    while from <= #line do
      local ink = line:sub(from, from)
      local to = from
      while line:sub(to + 1, to + 1) == ink do to = to + 1 end
      if ink ~= "." then ui.fill(x + from - 1, y + row - 1, to - from + 1, 1, ink == "c" and own or INK[ink]) end
      from = to + 1
    end
  end
end

local function drawPillar(x, y)
  ui.fill(x, y, CELL_W, CELL_H, C.line)
  ui.fill(x, y, CELL_W, 1, C.text)
  ui.fill(x, y + CELL_H - 1, CELL_W, 1, C.tie)
  ui.fill(x + CELL_W - 1, y + 1, 1, CELL_H - 1, C.tie)
end

--- Two rows of bricks, offset, with their mortar.
local function drawBrick(x, y)
  ui.fill(x, y, CELL_W, CELL_H, C.redTint)
  ui.fill(x, y + 2, CELL_W, 1, C.tie)
  ui.fill(x, y + 5, CELL_W, 1, C.tie)
  ui.fill(x + 4, y, 1, 2, C.tie)
  ui.fill(x + 1, y + 3, 1, 2, C.tie)
  ui.fill(x + 6, y + 3, 1, 2, C.tie)
end

local function drawClosed(x, y)
  ui.fill(x, y, CELL_W, CELL_H, C.tie)
  ui.fill(x + 1, y + 1, CELL_W - 2, CELL_H - 2, C.line)
end

local function drawItem(x, y, item)
  ui.fill(x + 1, y + 1, CELL_W - 2, CELL_H - 2, item.color)
  ui.small(item.letter, x + 4, y + 2, C.bg, item.color)
end

local function drawTile(L, s, i)
  local tx, ty = rules.tileOf(i)
  local x, y = tileX(L, tx), tileY(L, ty)
  local tile = s.map[i]
  ui.fill(x, y, CELL_W, CELL_H, C.panel)
  if tile == rules.PILLAR then drawPillar(x, y)
  elseif tile == rules.BRICK then drawBrick(x, y)
  elseif tile == rules.WALL then drawClosed(x, y)
  elseif s.items[i] then drawItem(x, y, ITEMS[s.items[i]]) end
end

local arena = {}

--- Bring the kept arena up to date, then copy it to this wall.
local function drawArena(L, s)
  local live = ui.screen()
  if not arena.surf or arena.W ~= L.W then arena.surf, arena.W, arena.codes = live:copy(), L.W, {} end
  ui.setScreen(arena.surf)
  for i = 1, TILES do
    local item = s.items[i]
    local code = s.map[i] * 10 + (item and ITEMS[item].code or 0)
    if arena.codes[i] ~= code then
      arena.codes[i] = code
      drawTile(L, s, i)
    end
  end
  ui.setScreen(live)
  live:drawSurface(arena.surf, L.x0, L.y0, L.bw, L.bh, L.x0, L.y0, L.bw, L.bh)
end

--- The next tiles to fall in sudden death, flashing, so nobody is caught by surprise.
local function drawWarnings(L, s)
  if s.clock < rules.SUDDEN_TICKS - 8 or s.frame % 2 == 1 then return end
  for k = s.closed + 1, s.closed + WARN_TILES do
    local i = rules.CLOSE_ORDER[k]
    if i then
      for _, at in ipairs({ i, rules.mirror(i) }) do
        local x, y = rules.tileOf(at)
        ui.frame(tileX(L, x), tileY(L, y), CELL_W, CELL_H, C.warn, 1)
      end
    end
  end
end

local function drawBombs(L, s)
  for _, b in ipairs(s.bombs) do
    local x, y = tileX(L, b.x), tileY(L, b.y)
    local close = b.fuse <= 6
    local body = C.line
    if close then body = s.frame % 2 == 0 and C.text or C.red end
    base.disc(x + 1, y + 1, 7, 5, body)
    ui.fill(x + 2, y + 2, 2, 1, C.text)
    ui.fill(x + 5, y, 2, 1, s.frame % 2 == 0 and C.hi or C.warn)
  end
end

--- The fire, along its arm, burning down to red.
local function drawFire(L, s)
  for i = 1, TILES do
    local left = s.fire[i]
    if left then
      local tx, ty = rules.tileOf(i)
      local x, y = tileX(L, tx), tileY(L, ty)
      local kind = s.fireKind[i]
      local outer = left <= 1 and C.red or C.warn
      if kind == "h" then
        ui.fill(x, y + 1, CELL_W, 4, outer)
        ui.fill(x, y + 2, CELL_W, 2, C.hi)
      elseif kind == "v" then
        ui.fill(x + 1, y, 7, CELL_H, outer)
        ui.fill(x + 3, y, 3, CELL_H, C.hi)
      else
        ui.fill(x, y, CELL_W, CELL_H, outer)
        ui.fill(x + 2, y + 1, 5, 4, C.hi)
        if left > 2 then ui.fill(x + 3, y + 2, 3, 2, C.text) end
      end
    end
  end
end

--- Where a bomber shows: on its way from the last tile.
local function bomberAt(L, p)
  local t = math.min(1, (p.budget + rules.speedOf(p)) / 100)
  if p.px == p.x and p.py == p.y then t = 1 end
  return floor(tileX(L, p.px + (p.x - p.px) * t) + 0.5), floor(tileY(L, p.py + (p.y - p.py) * t) + 0.5)
end

--- A yellow box and an arrow over the bomber this wall belongs to.
local function drawOwnMark(x, y, s)
  ui.frame(x, y, CELL_W, CELL_H, C.hi, 1)
  local bob = s.frame % 6 < 3 and 0 or 1
  ui.fill(x + 3, y - 3 + bob, 3, 1, C.hi)
  ui.fill(x + 4, y - 2 + bob, 1, 1, C.hi)
end

local function drawBomber(L, s, p, own)
  local x, y = bomberAt(L, p)
  if not p.alive then
    -- a scorched heap where they fell
    ui.fill(x + 1, y + 3, 7, 3, C.line)
    ui.fill(x + 3, y + 2, 3, 1, PLAYER_COLOR[p.n])
    return
  end
  if own then drawOwnMark(x, y, s) end
  local step = (p.dir and s.frame % 4 < 2) and 2 or 1
  drawSprite(BOMBER[p.face][step], x, y, PLAYER_COLOR[p.n])
end

--- A player's powerups in a row, the colours matching the tiles they came from.
local function drawKit(x, y, name, color, p)
  ui.small(name, x, y, color, C.bg)
  ui.small("BOMBS " .. p.bombs, x + 6, y, ITEMS.bomb.color, C.bg)
  ui.small("FLAME " .. p.flame, x + 15, y, ITEMS.flame.color, C.bg)
  ui.small("SPEED " .. p.boots, x + 24, y, ITEMS.boots.color, C.bg)
  if p.kick then ui.small("KICK", x + 33, y, ITEMS.kick.color, C.bg) end
end

local function clockLine(s)
  local left = rules.SUDDEN_TICKS - s.clock
  if left <= 0 then return "SUDDEN DEATH", s.frame % 4 < 2 and C.warn or C.red end
  local seconds = math.ceil(left * rules.TICK_MS / 1000)
  return string.format("WALLS IN %d:%02d", floor(seconds / 60), seconds % 60), seconds <= 15 and C.warn or C.line
end

--- Under the arena: both kits, yours first, and time until the walls come in. QUIT has the corner to the right.
local function drawStrip(L, s, player)
  local mine = player or 1
  local y = L.y0 + L.bh + 1
  drawKit(2, y, player and "YOU" or PLAYER_NAME[1], PLAYER_COLOR[mine], s.p[mine])
  drawKit(2, y + 2, player and "THEM" or PLAYER_NAME[2], PLAYER_COLOR[3 - mine], s.p[3 - mine])
  local text, color = clockLine(s)
  ui.small(text, 104, y, color, C.bg, "right")
  ui.small("ROUND " .. s.round .. "  FIRST TO " .. rules.WINS, 104, y + 2, C.line, C.bg, "right")
end

local function bannerText(s, player)
  if s.after == "start" then return "ROUND " .. s.round, C.hi end
  if s.after ~= "round" then return nil end
  local won = s.roundWinner
  if won == 0 then return "DRAW - PLAY IT AGAIN", C.hi end
  if won == player then return "YOU WIN THE ROUND", C.ok end
  if player then return "YOU LOSE THE ROUND", C.red end
  return PLAYER_NAME[won] .. " WINS THE ROUND", PLAYER_COLOR[won]
end

local function drawBanner(L, s, player)
  local text, color = bannerText(s, player)
  if not text or s.over then return end
  local cx = L.x0 + floor(L.bw / 2)
  local w, y = #text + 6, L.y0 + floor(L.bh / 2) - 1
  ui.fill(cx - floor(w / 2), y - 1, w, 3, C.bg)
  ui.frame(cx - floor(w / 2) - 1, y - 2, w + 2, 5, color, 1)
  ui.small(text, cx, y, color, C.bg, "center")
end

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, COLS * CELL_W, ROWS * CELL_H)
end

--- No buttons: the whole wall is the control.
function view.controls()
  return {}
end

function view.draw(L, s, player)
  drawArena(L, s)
  drawWarnings(L, s)
  drawBombs(L, s)
  drawFire(L, s)
  -- this wall's bomber goes on top, so it's never the one hidden when both share a tile
  local first = player == 1 and 2 or 1
  drawBomber(L, s, s.p[first], first == player)
  drawBomber(L, s, s.p[3 - first], 3 - first == player)
  base.drawMiddle(L, C.text)
  drawStrip(L, s, player)
  drawBanner(L, s, player)
end

--- The whole wall steers: tap the side you want. The middle of the wall is BOMB.
function view.actionAt(L, _, px, py)
  if base.inMiddle(L, px, py) then return { kind = "bomb" } end
  return base.splitAction(L, px, py)
end

--- A big chain can hold many of one thing: one sound of each is plenty.
-- What each event sounds like. Names are in lib/sound_picks.lua.
local SFX = {
  death = "death", blast = "boom_small", wall = "brick", bomb = "bomb_set", kick = "bounce", powerup = "powerup",
  sudden = "ui_warning", go = "ui_start", round = "win_small",
}

function view.onEvents(app, _, events)
  base.sfx(app, events, SFX)
end

return base.fill({
  id = "bomberman", title = "Bomberman", blurb = "First to three rounds", color = "warn",
  versus = true, split = true, splitMiddle = "BOMB", tickMs = 140, minSize = { w = 120, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Blow up the other bomber before they blow up you. Win three rounds to win the match. A round where you both go up plays again.",
    "",
    "Tap the side of the wall you want to go: the top goes up, the bottom down, the left side left and the right side right. The wall is split corner to corner, so you never have to look away. You keep going until something blocks you.",
    "",
    "A turn that isn't open yet waits for one more tile, so tap early. If it still isn't open, you stop, so tapping a wall is how to stop.",
    "",
    "The middle of the wall, between the four marks, drops a bomb and stops you. It goes off after two and a half seconds, in a cross. Pillars stop the fire. It breaks bricks and sets off other bombs, and it kills you just the same as anyone else. Your bomber is the one in the yellow box.",
    "",
    "Bricks hide powerups. B is one more bomb at a time, F is longer fire, S is speed, and K lets you kick a bomb by walking into it. Fire burns them, and they don't last past the round.",
    "",
    "After two minutes the walls come in from the edges, and they crush anything they reach. Head for the middle.",
  },
})
