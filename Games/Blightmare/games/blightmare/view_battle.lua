-- games/blightmare/view_battle.lua
-- Battle screen A, the Final Fantasy layout: a message across the top, the side view under it with foes left and the party
-- staggered down the right, and under the line big commands on the left beside a status strip. SAVE & QUIT is the shell's, in
-- the bottom right corner, so the strip stops short of it.
-- The field and sprites change rarely and gauges change every tick, so the still part is kept in a surface of its own and the
-- gauges go over it. The shell's steady redraw only copies the finished picture across, until s.rev moves on.

local art = require("games.blightmare.art_battle")
local battle = require("games.blightmare.battle")
local enemies = require("games.blightmare.enemies")
local party = require("games.blightmare.party")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor, max, min = math.floor, math.max, math.min

local M = {}

local FX, FY, FW, FH = 0, 7, 121, 49 -- the field
local LINE_Y = 56
local TOP_Y = FY + 1                 -- nothing on the field stands above this
local ALLY_ROOM = 48                 -- rows the party shares
local ALLY_STEP = 8                  -- each one stands this much further right than the last
local ALLY_MAX_H = 22

-- the command block, and the four commands in it
local BLOCK_W, BLOCK_Y = 71, 57
local BTN_W, BTN_H = 35, 11
local BTN_Y1, BTN_Y2 = 58, 69
local BTN_X2 = 36

-- the status strip: x + w stops before SAVE & QUIT at x 107, whichever row it is
M.STRIP = { x = 72, y = 58, w = 35, rowH = 6 }
local NAME_W, HP_RIGHT, MP_X, TAG_X = 8, 88, 89, 92
local HP_BAR_W, ATB_X, ATB_W = 20, 93, 14

-- a list opens over the foes, and leaves the party in view. Six rows fit: a longer list pages, with MORE as its last row.
local ROW_X, ROW_Y, ROW_W, ROW_H = 2, 8, 73, 8

-- where foes stand, by how many there are: { x, y }, and the size each takes. No two boxes meet, bars included.
local SLOTS = {
  { w = 50, h = 34, { 12, 11 } },
  { w = 34, h = 23, { 2, 9 }, { 37, 28 } },
  { w = 30, h = 20, { 2, 8 }, { 36, 19 }, { 2, 31 } },
  { w = 30, h = 20, { 2, 8 }, { 36, 8 }, { 2, 31 }, { 36, 31 } },
  { w = 22, h = 18, { 2, 8 }, { 26, 8 }, { 50, 8 }, { 14, 31 }, { 38, 31 } },
}
-- a big foe fills the left of the field, and whoever it calls stands in front of it. Boxes by the size of the biggest: def.size 2
-- or 3. The party never comes further left than x 78, so all of this is clear of them.
local BIG = {
  [2] = { rect = { x = 1, y = 8, w = 50, h = 45 }, adds = { { 53, 9 }, { 53, 30 } }, addW = 21, addH = 14 },
  [3] = { rect = { x = 1, y = 8, w = 58, h = 45 }, adds = { { 60, 9 }, { 60, 30 } }, addW = 17, addH = 14 },
}
-- two big foes side by side, and helpers in the narrow column left over
local PAIR = { { x = 1, y = 8, w = 29, h = 45 }, { x = 31, y = 8, w = 29, h = 45 } }
local PAIR_ADDS = { adds = { { 61, 9 }, { 61, 30 } }, addW = 16, addH = 14 }

--- How much of the field a foe takes. A lone boss's lead is big unless its def says, and a test's bare table has no id.
local function sizeOf(b, i)
  local f = b.foes[i]
  local def = f and f.id and enemies.FOES[f.id]
  if def and def.size then return def.size end
  if not b.boss then return 1 end
  local leads = 0
  for _, other in ipairs(b.foes) do
    if not other.added then leads = leads + 1 end
  end
  return i == 1 and leads <= 1 and 2 or 1
end

--- The nth box of a helper column.
local function addRect(set, n)
  local at = set.adds[(n - 1) % #set.adds + 1]
  return { x = at[1], y = at[2], w = set.addW, h = set.addH }
end

--- The box a foe stands in. The bars go just under it.
function M.foeRect(b, i)
  local bigs = {}
  for k = 1, #b.foes do
    if sizeOf(b, k) >= 2 then bigs[#bigs + 1] = k end
  end
  if #bigs == 1 or #bigs == 2 then
    local set = #bigs == 1 and BIG[math.min(3, sizeOf(b, bigs[1]))] or PAIR_ADDS
    local n = 0
    for k = 1, i do
      local big = k == bigs[1] or k == bigs[2]
      if big and k == i then
        if #bigs == 1 then return set.rect end
        return PAIR[k == bigs[1] and 1 or 2]
      end
      if not big then n = n + 1 end
    end
    return addRect(set, n)
  end
  local slot = SLOTS[#b.foes] or SLOTS[#SLOTS]
  local at = slot[i] or slot[1]
  return { x = at[1], y = at[2], w = slot.w, h = slot.h }
end

--- The box a party member stands in, staggered down the right. Fewer people stand bigger.
function M.allyRect(b, i)
  local n = max(1, #b.allies)
  local h = min(ALLY_MAX_H, floor(ALLY_ROOM / n))
  local w = floor(h * 1.5)
  return {
    x = FW - 1 - w - (n - i) * ALLY_STEP,
    y = TOP_Y + floor((ALLY_ROOM - h * n) / 2) + (i - 1) * h,
    w = w, h = h,
  }
end

local function rowRect(i) return { x = ROW_X, y = ROW_Y + (i - 1) * ROW_H, w = ROW_W, h = ROW_H } end

local function inside(r, px, py) return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h end

-- ---------------------------------------------------------------- tapping

--- The command under a tap. The block has no dead gaps, so a tap that lands between two buttons still counts.
local function commandAt(px, py)
  if px < 0 or px >= BLOCK_W or py < BLOCK_Y then return nil end
  if py < BTN_Y2 then return px < BTN_X2 and "attack" or "special" end
  return px < BTN_X2 and "defend" or "item"
end

--- What a tap means now. Time stops for a menu, so a tap outside a list or a target is always a step back.
function M.actionAt(L, s, px, py)
  local b = s and s.battle
  if not b or b.result then return nil end
  if b.phase == "spoils" then return { kind = "tap" } end
  if b.phase == "cmd" then
    local cmd = commandAt(px, py)
    return cmd and { kind = "cmd", cmd = cmd } or nil
  end
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
  if (u.thrall or 0) > 0 then out = out .. " THR" end
  if (u.tadpole or 0) > 0 then out = out .. " TAD" end
  if (u.blind or 0) > 0 then out = out .. " BLD" end
  if (u.silence or 0) > 0 then out = out .. " SIL" end
  if (u.doom or 0) > 0 then out = out .. " DOM" end
  if u.hidden then out = out .. " HID" end
  if u.guard then out = out .. " GRD" end
  if u.focus then out = out .. " FOC" end
  return out
end

-- ---------------------------------------------------------------- the still part

--- A sprite the artist hasn't drawn yet must never stop a fight: a foe stands in for it.
local function spriteFor(name)
  if name and art.SPRITES[name] then return name end
  return art.SPRITES.blighted and "blighted" or "downed"
end

--- A ground the artist hasn't drawn yet does the same.
local function drawGround(bg)
  if not pcall(art.ground, bg, FX, FY, FW, FH) then art.ground("mine", FX, FY, FW, FH) end
end

local function drawUnits(s, b)
  for i, f in ipairs(b.foes) do
    if f.hp > 0 then
      local r = M.foeRect(b, i)
      art.draw(spriteFor(enemies.FOES[f.id].sprite), r.x, r.y, r.w, r.h, f.flash > 0 and "flash" or f.sleep > 0 and "dim" or nil)
    end
  end
  for i, u in ipairs(b.allies) do
    local m = s.party[u.m]
    local r = M.allyRect(b, i)
    if m.hp <= 0 then
      art.draw("downed", r.x, r.y, r.w, r.h)
    else
      art.draw(m.id, r.x, r.y, r.w, r.h, u.flash > 0 and "flash" or u.sleep > 0 and "dim" or nil)
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
    drawGround(b.bg)
    ui.fill(0, LINE_Y, L.W, 1, C.line)
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
      local y = r.y + r.h
      bar(r.x + 3, y, r.w - 6, f.hp / f.mhp, C.red)
      if f.charge > 0 then
        local ab = enemies.ABILITIES[f.charging]
        bar(r.x + 3, y + 1, r.w - 6, 1 - f.charge / ab.windup, C.warn, C.bg)
        foeRing(r, blink(b) and C.warn or C.red)
        ui.text("!", r.x + r.w + 3, y - 6, blink(b) and C.warn or C.red, "center")
      end
      local tags = statusText(f)
      if tags ~= "" then ui.small(tags, r.x + floor(r.w / 2), y - 1, C.accent, C.bg, "center") end
    end
  end
end

--- A member's name, the player's own for the hero, cut to fit.
local function shortName(s, m)
  local name = m.id == "hero" and s.heroName and s.heroName:upper() or party.CHARS[m.id].short or party.CHARS[m.id].name
  return name:sub(1, NAME_W)
end

--- Name, HP, MP and status on one line, with the HP bar and ATB gauge on the line under it.
local function drawStrip(s, b)
  local strip = M.STRIP
  for i, u in ipairs(b.allies) do
    local m = s.party[u.m]
    local st = party.stats(m)
    local y = strip.y + (i - 1) * strip.rowH
    local share = m.hp / st.hp
    local low = share < 0.25
    ui.small(shortName(s, m), strip.x, y, b.active == i and C.hi or m.hp > 0 and C.text or C.tie, C.bg)
    ui.small(m.hp .. "/" .. st.hp, HP_RIGHT, y, low and C.warn or C.text, C.bg, "right")
    if st.mp > 0 then ui.small(m.mp, MP_X, y, C.info, C.bg) end
    local tags = statusText(u)
    if tags ~= "" then ui.small(tags, TAG_X, y, C.accent, C.bg, "left", strip.x + strip.w - TAG_X) end
    bar(strip.x, y + 1, HP_BAR_W, share, low and C.warn or C.ok)
    bar(ATB_X, y + 1, ATB_W, u.atb / battle.GAUGE, u.atb >= battle.GAUGE and C.hi or C.info)
  end
end

local function drawFloats(b)
  for _, f in ipairs(b.floats) do
    local r = f.side == "foe" and M.foeRect(b, f.i) or M.allyRect(b, f.i)
    local y = max(TOP_Y, r.y + floor(r.h / 2) - 7 + floor(f.t / 2))
    if f.small then
      ui.small(f.text, r.x + floor(r.w / 2), y + ui.fontHeight() + 1, C[f.color] or C.text, C.bg, "center")
    else
      ui.text(f.text, r.x + floor(r.w / 2), y, C[f.color] or C.text, "center")
    end
  end
end

local function button(x, y, label, frame, ink)
  ui.fill(x, y, BTN_W, BTN_H, C.panel)
  ui.frame(x, y, BTN_W, BTN_H, frame)
  ui.text(label, x + floor(BTN_W / 2), y + floor((BTN_H - ui.fontHeight()) / 2), ink, "center")
end

local function drawCommands(s, b)
  local u = b.allies[b.active]
  local warned = battle.blowIn(b) ~= nil
  local defend = warned and (blink(b) and C.warn or C.hi) or C.line
  button(0, BTN_Y1, "ATTACK", C.line, C.text)
  button(BTN_X2, BTN_Y1, party.CHARS[s.party[u.m].id].special, C.hi, C.hi)
  button(0, BTN_Y2, "DEFEND", defend, warned and defend or C.text)
  button(BTN_X2, BTN_Y2, "ITEM", C.line, C.text)
  ring(M.allyRect(b, b.active), C.hi)
end

--- Split a message into lines of the big font that fit the block, at spaces.
local function bigLines(text)
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    local longer = line == "" and word or (line .. " " .. word)
    if line ~= "" and ui.textWidth(longer) > BLOCK_W - 2 then
      lines[#lines + 1] = line
      line = word
    else
      line = longer
    end
  end
  lines[#lines + 1] = line
  return lines
end

--- A line or two of big text in the command block.
local function blockLines(first, second, color, under)
  local cx = floor(BLOCK_W / 2)
  if second then
    ui.text(first, cx, 61, color, "center", BLOCK_W - 2)
    ui.text(second, cx, 71, under or color, "center", BLOCK_W - 2)
  else
    ui.text(first, cx, 66, color, "center", BLOCK_W - 2)
  end
end

local function drawList(s, b)
  local rows = battle.rows(s)
  local x, y, w = ROW_X - 1, ROW_Y - 1, ROW_W + 2
  ui.fill(x, y, w, #rows * ROW_H + 2, C.panel)
  ui.frame(x, y, w, #rows * ROW_H + 2, C.hi)
  for i, row in ipairs(rows) do
    local r = rowRect(i)
    local ink = row.ok and C.text or C.line
    ui.text(row.name, r.x + 2, r.y + 1, ink)
    if row.note ~= "" then ui.text(row.note, r.x + r.w - 2, r.y + 1, row.ok and C.info or C.line, "right") end
  end
  ring(M.allyRect(b, b.active), C.hi)
  blockLines("TAP A ROW", "AWAY: BACK", C.hi, C.line)
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
  blockLines("TAP WHO", "AWAY: BACK", C.hi, C.line)
end

local function drawSpoils(s, b)
  local x, y, w, h = 28, 12, 65, 34
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
  blockLines("TAP", nil, C.line)
end

local function paint(L, s)
  local b = s.battle
  drawStill(L, s, b)
  drawFoeBars(b)
  drawStrip(s, b)
  if b.phase ~= "spoils" then ui.text(b.msg, 60, 0, C.text, "center", 119) end
  if b.phase == "cmd" then drawCommands(s, b) end
  if b.phase == "target" then drawTarget(s, b) end
  drawFloats(b)
  if b.phase == "list" then drawList(s, b) end
  if b.phase == "spoils" then drawSpoils(s, b) end
  if b.phase == "run" then
    local lines = bigLines(b.msg)
    blockLines(lines[1], lines[2], C.text)
  end
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
