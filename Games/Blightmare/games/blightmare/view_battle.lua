-- games/blightmare/view_battle.lua
-- Battle screen B: the side view in a middle box, and when someone's ready the whole wall is the menu, split corner to corner.
-- The field and sprites change rarely and gauges change every tick, so the still part is kept in a surface of its own and the
-- gauges go over it. The shell's steady redraw only copies the finished picture across, until s.rev moves on.

local art = require("games.blightmare.art_battle")
local base = require("lib.arcade.base")
local battle = require("games.blightmare.battle")
local enemies = require("games.blightmare.enemies")
local party = require("games.blightmare.party")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor, max, min = math.floor, math.max, math.min

local M = {}

local FX, FY, FW, FH = 16, 8, 89, 64 -- the field
local LETTER_H = 8                   -- the side words are stacked a letter at a time
local ROW_X, ROW_Y, ROW_W, ROW_H = 24, 13, 73, 9

-- where foes stand, by how many there are
local SLOTS = {
  { { 28, 26 } },
  { { 22, 12 }, { 36, 42 } },
  { { 18, 10 }, { 40, 28 }, { 18, 48 } },
  { { 18, 10 }, { 44, 12 }, { 18, 46 }, { 44, 48 } },
  { { 18, 9 }, { 44, 12 }, { 30, 30 }, { 18, 50 }, { 44, 50 } },
}
local FOE_W, FOE_H = 26, 18
local BOSS = { x = 34, y = 12, w = 37, h = 50 }
local ADDS = { { 17, 14 }, { 17, 46 } }
local ADD_W, ADD_H = 20, 14

--- The box a foe stands in. The bars go just under it.
function M.foeRect(b, i)
  if b.boss then
    if i == 1 then return BOSS end
    local at = ADDS[(i - 2) % #ADDS + 1]
    return { x = at[1], y = at[2], w = ADD_W, h = ADD_H }
  end
  local at = (SLOTS[#b.foes] or SLOTS[#SLOTS])[i] or { 18, 10 }
  return { x = at[1], y = at[2], w = FOE_W, h = FOE_H }
end

--- The box a party member stands in, numbers and bars included. Fewer people stand bigger.
function M.allyRect(b, i)
  local n = max(1, #b.allies)
  local h = min(20, floor(FH / n))
  local top = FY + floor((FH - h * n) / 2)
  return { x = 74 + ((i + 1) % 2) * 6, y = top + (i - 1) * h, w = 24, h = h }
end

local function rowRect(i) return { x = ROW_X, y = ROW_Y + (i - 1) * ROW_H, w = ROW_W, h = ROW_H } end

local function inside(r, px, py) return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h end

-- ---------------------------------------------------------------- tapping

local SPLIT = { up = "attack", left = "special", right = "item", down = "defend" }

--- What a tap means now. Time stops for a menu, so a tap outside a list or a target is always a step back.
function M.actionAt(L, s, px, py)
  local b = s and s.battle
  if not b or b.result then return nil end
  if b.phase == "spoils" then return { kind = "tap" } end
  if b.phase == "cmd" then return { kind = "cmd", cmd = SPLIT[base.splitAction(L, px, py).dir] } end
  if b.phase == "list" then
    for i = 1, #battle.rows(s) do
      if inside(rowRect(i), px, py) then return { kind = "pick", i = i } end
    end
    return { kind = "back" }
  end
  if b.phase == "target" then
    local side, list = battle.targets(s)
    for _, i in ipairs(list) do
      local r = side == "foe" and M.foeRect(b, i) or M.allyRect(b, i)
      if inside(r, px, py) then return { kind = "target", side = side, i = i } end
    end
    return { kind = "back" }
  end
  return nil
end

-- ---------------------------------------------------------------- bars and marks

local function bar(x, y, w, share, color, back)
  ui.fill(x, y, w, 1, back or C.panel)
  ui.fill(x, y, share > 0 and max(1, min(w, floor(w * share + 0.5))) or 0, 1, color)
end

local function ring(r, color) ui.frame(r.x - 1, r.y - 1, r.w + 2, r.h + 2, color) end

--- A ring round a foe takes in the bars under it.
local function foeRing(r, color) ring({ x = r.x, y = r.y, w = r.w, h = r.h + 2 }, color) end

local function blink(b) return floor(b.t / 3) % 2 == 0 end

local function statusText(u)
  local out = ""
  if u.poison > 0 then out = out .. " PSN" end
  if u.sleep > 0 then out = out .. " ZZZ" end
  if u.nightmare > 0 then out = out .. " NMR" end
  if u.guard then out = out .. " GRD" end
  if u.focus then out = out .. " FOC" end
  return out
end

-- ---------------------------------------------------------------- the still part

local function allySpriteBox(r)
  local h = r.h - 4
  local w = min(r.w, floor(h * 1.5))
  return r.x + floor((r.w - w) / 2), r.y, w, h
end

local function drawUnits(s, b)
  for i, f in ipairs(b.foes) do
    if f.hp > 0 then
      local r = M.foeRect(b, i)
      art.draw(enemies.FOES[f.id].sprite, r.x, r.y, r.w, r.h, f.flash > 0 and "flash" or f.sleep > 0 and "dim" or nil)
    end
  end
  for i, u in ipairs(b.allies) do
    local m = s.party[u.m]
    local x, y, w, h = allySpriteBox(M.allyRect(b, i))
    if m.hp <= 0 then
      art.draw("downed", x, y, w, h)
    else
      art.draw(m.id, x, y, w, h, u.flash > 0 and "flash" or u.sleep > 0 and "dim" or nil)
    end
  end
end

--- All that decides the still picture, as a string.
local function stillKey(s, b)
  local parts = { b.bg, b.boss and "b" or "" }
  for _, list in ipairs({ b.foes, b.allies }) do
    for _, u in ipairs(list) do
      local hp = u.m and s.party[u.m].hp or u.hp
      parts[#parts + 1] = (u.id or s.party[u.m].id) .. (hp > 0 and 1 or 0) .. (u.flash > 0 and "f" or "") .. (u.sleep > 0 and "z" or "")
    end
  end
  return table.concat(parts, ",")
end

local still = {}

local function drawStill(L, s, b)
  local screen = ui.screen()
  if not still.surf or still.surf.width ~= screen.width or still.surf.height ~= screen.height then
    still.surf, still.key = screen:copy(), nil
  end
  local key = stillKey(s, b)
  if still.key ~= key then
    ui.setScreen(still.surf)
    ui.fill(0, 0, L.W, L.H, C.bg)
    art.ground(b.bg, FX, FY, FW, FH)
    drawUnits(s, b)
    ui.setScreen(screen)
    still.key = key
  end
  screen:drawSurface(still.surf, 0, 0, L.W, L.H, 0, 0, L.W, L.H)
end

-- ---------------------------------------------------------------- the moving part

local function drawFoeBars(b)
  for i, f in ipairs(b.foes) do
    if f.hp > 0 then
      local r = M.foeRect(b, i)
      local y = min(FY + FH - 1, r.y + r.h)
      bar(r.x + 3, y, r.w - 6, f.hp / f.mhp, C.red)
      if f.charge > 0 then
        local ab = enemies.ABILITIES[f.charging]
        bar(r.x + 3, y + 1, r.w - 6, 1 - f.charge / ab.windup, C.warn, C.bg)
        foeRing(r, blink(b) and C.warn or C.red)
        ui.text("!", r.x - 5, r.y + floor(r.h / 2) - 3, blink(b) and C.warn or C.red, "center")
      end
      local tags = statusText(f)
      if tags ~= "" then ui.small(tags, r.x + floor(r.w / 2), y - 1, C.accent, C.bg, "center") end
    end
  end
end

local function drawAllyBars(s, b)
  for i, u in ipairs(b.allies) do
    local m = s.party[u.m]
    local st = party.stats(m)
    local r = M.allyRect(b, i)
    local y = r.y + r.h - 4
    local share = m.hp / st.hp
    local low = share < 0.25
    local line = m.hp .. "/" .. st.hp
    ui.small(line, r.x, y, low and C.warn or C.text, C.bg, "left")
    local x = r.x + #line
    if st.mp > 0 then
      local mana = " " .. m.mp
      ui.small(mana, x, y, C.info, C.bg, "left")
      x = x + #mana
    end
    local tags = statusText(u)
    if tags ~= "" then ui.small(tags, x, y, C.accent, C.bg, "left", r.x + r.w - x) end
    bar(r.x, y + 1, r.w, share, low and C.warn or C.ok)
    bar(r.x, y + 2, r.w, u.atb / battle.GAUGE, u.atb >= battle.GAUGE and C.hi or C.info)
  end
end

local function drawFloats(b)
  for _, f in ipairs(b.floats) do
    local r = f.side == "foe" and M.foeRect(b, f.i) or M.allyRect(b, f.i)
    local y = max(FY, r.y + floor(r.h / 2) - 7 + floor(f.t / 2))
    ui.text(f.text, r.x + floor(r.w / 2), y, C[f.color] or C.text, "center")
  end
end

local function topLine(b)
  ui.text(b.msg, 60, 1, C.text, "center", 119)
end

--- A word down the side of the wall, a letter at a time.
local function downWord(word, x, color)
  local top = 40 - #word * floor(LETTER_H / 2)
  for i = 1, #word do ui.text(word:sub(i, i), x, top + (i - 1) * LETTER_H, color, "center") end
end

--- Dots from each corner of the wall to the field, showing the split.
local function drawSplit(L)
  for i = 2, 15, 3 do
    local x, y = floor(i * 1.5), i - 1
    ui.fill(x, y, 1, 1, C.line)
    ui.fill(L.W - 1 - x, y, 1, 1, C.line)
    ui.fill(x, L.H - 1 - y, 1, 1, C.line)
    ui.fill(L.W - 1 - x, L.H - 1 - y, 1, 1, C.line)
  end
end

local function drawCommands(L, s, b)
  local u = b.allies[b.active]
  local warned = battle.blowIn(b) ~= nil
  ui.text("ATTACK", 60, 1, C.text, "center")
  ui.text("DEFEND", 60, 74, warned and (blink(b) and C.warn or C.hi) or C.text, "center")
  downWord(party.CHARS[s.party[u.m].id].special, 8, C.hi)
  downWord("ITEM", 112, C.text)
  drawSplit(L)
  ring(M.allyRect(b, b.active), C.hi)
  ui.small(b.msg, 60, 7, C.hi, C.bg, "center", FW)
end

local function drawList(s)
  local rows = battle.rows(s)
  local x, y, w = ROW_X - 2, ROW_Y - 2, ROW_W + 4
  local h = #rows * ROW_H + 4
  ui.fill(x, y, w, h, C.panel)
  ui.frame(x, y, w, h, C.hi)
  for i, row in ipairs(rows) do
    local r = rowRect(i)
    local ink = row.ok and C.text or C.line
    ui.text(row.name, r.x + 2, r.y + 1, ink)
    if row.note ~= "" then ui.text(row.note, r.x + r.w - 2, r.y + 1, row.ok and C.info or C.line, "right") end
  end
  ui.text("TAP AWAY: BACK", 60, 74, C.line, "center", 100)
end

local function drawTarget(s, b)
  local side, list = battle.targets(s)
  local on = blink(b)
  for _, i in ipairs(list) do
    local r = side == "foe" and M.foeRect(b, i) or M.allyRect(b, i)
    if side == "foe" then
      local def = enemies.FOES[b.foes[i].id]
      foeRing(r, on and C.hi or C.warn)
      ui.small(def.short or def.name, r.x + floor(r.w / 2), r.y, C.text, C.bg, "center")
    else
      ring(r, on and C.hi or C.warn)
    end
  end
  ui.text("TAP WHO", 60, 73, C.hi, "center")
  ui.small("tap away to go back", 60, 80, C.line, C.bg, "center")
end

local function drawSpoils(s, b)
  local x, y, w, h = 28, 22, 65, 34
  local won = b.outcome == "won"
  ui.fill(x, y, w, h, C.bg)
  ui.frame(x, y, w, h, won and C.ok or (b.outcome == "lost" and C.red or C.line))
  ui.text(b.msg, 60, y + 3, won and C.ok or (b.outcome == "lost" and C.red or C.text), "center", w - 4)
  if b.spoils then
    ui.text(b.spoils.xp .. " XP", 60, y + 11, C.text, "center")
    ui.text(b.spoils.gold .. " GOLD", 60, y + 18, C.hi, "center")
    for i, up in ipairs(b.spoils.ups) do
      if i <= 4 then ui.small((up.id == "hero" and s.heroName and s.heroName:upper() or party.CHARS[up.id].name) .. " REACHED LEVEL " .. up.lvl, 60, y + 25 + i, C.soft, C.bg, "center") end
    end
  end
end

local function paint(L, s)
  local b = s.battle
  drawStill(L, s, b)
  drawFoeBars(b)
  drawAllyBars(s, b)
  if b.phase == "cmd" then
    drawCommands(L, s, b)
  elseif b.phase ~= "spoils" then
    topLine(b)
  end
  if b.phase == "list" then drawList(s) end
  if b.phase == "target" then drawTarget(s, b) end
  drawFloats(b)
  if b.phase == "spoils" then drawSpoils(s, b) end
end
M.paint = paint

-- A cabinet may show a battle on two walls, so one picture for each state, as Dungeon keeps them.
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

function M.draw(L, s)
  local picture = pictureFor(L, s)
  ui.screen():drawSurface(picture.surf, 0, 0, L.W, L.H, 0, 0, L.W, L.H)
end

return M
