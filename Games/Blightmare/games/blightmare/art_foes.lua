-- games/blightmare/art_foes.lua
-- What the regions asked the artist for: R.art.<sprite> in each regions/*.lua. Every entry here is a function that gives shapes in a unit
-- square, with the floor along the bottom, facing right, the way art_battle.lua draws: art_battle takes them all, and art.lua stands them
-- on the maps as well, so anything here works as a foe, an npc and a prop without saying so twice.
--
-- To add one: F.xx_thing = function() return ... end, built from a family below if one fits, since most things are like something
-- else. A prop goes in PROPS too, with how much of a square it takes and how far back in it it stands. Nothing is built until it's
-- seen, so this file costs little to load however long it gets.

local ui = require("lib.arcade.ui")

local C = ui.C
local abs, sin, sqrt = math.abs, math.sin, math.sqrt

local M = {}
local F = {}
M.SPRITES = F

local function E(cx, cy, rx, ry, color) return { kind = "e", cx = cx, cy = cy, rx = rx, ry = ry, color = color } end
local function R(x, y, w, h, color) return { kind = "r", x = x, y = y, w = w, h = h, color = color } end
local function P(color, ...) return { kind = "p", points = { ... }, color = color } end

--- One flat list from shapes and lists of shapes, in order. nil and false are skipped, so a family can say "and a hat, if any".
local function join(...)
  local out = {}
  for i = 1, select("#", ...) do
    local item = select(i, ...)
    if item then
      if item.kind then
        out[#out + 1] = item
      else
        for _, shape in ipairs(item) do out[#out + 1] = shape end
      end
    end
  end
  return out
end

--- The middle of a limb that bends, t of the way along.
local function along(x1, y1, x2, y2, bend, waves, phase, t)
  local dx, dy = x2 - x1, y2 - y1
  local long = sqrt(dx * dx + dy * dy)
  local nx, ny = -dy / long, dx / long
  local off = sin(t * 3.14159 * (waves or 1) + (phase or 0)) * (bend or 0) * (1 - t * 0.4)
  return x1 + dx * t + nx * off, y1 + dy * t + ny * off, nx, ny
end

--- A limb that wanders: x1, y1 to x2, y2, wide1 thick at the start, wide2 at the end, swinging bend either side. See art_battle.
local function snake(ink, x1, y1, x2, y2, wide1, wide2, bend, waves, phase)
  local out, back = {}, {}
  for i = 0, 14 do
    local t = i / 14
    local cx, cy, nx, ny = along(x1, y1, x2, y2, bend, waves, phase, t)
    local half = (wide1 + (wide2 - wide1) * t) / 2
    out[#out + 1] = cx + nx * half
    out[#out + 1] = cy + ny * half
    back[#back + 1] = cy - ny * half
    back[#back + 1] = cx - nx * half
  end
  for i = #back, 1, -1 do out[#out + 1] = back[i] end
  return { kind = "p", points = out, color = ink }
end

--- Moves and shrinks a whole drawing: scale toward the floor at the middle, then shift it.
local function fit(list, sx, sy, dx, dy)
  local out = {}
  local function fx(x) return 0.5 + (x - 0.5) * sx + (dx or 0) end
  local function fy(y) return 1 + (y - 1) * sy + (dy or 0) end
  for _, s in ipairs(list) do
    if s.kind == "e" then
      out[#out + 1] = E(fx(s.cx), fy(s.cy), s.rx * sx, s.ry * sy, s.color)
    elseif s.kind == "r" then
      out[#out + 1] = R(fx(s.x), fy(s.y), s.w * sx, s.h * sy, s.color)
    else
      local pts = {}
      for i = 1, #s.points, 2 do pts[i], pts[i + 1] = fx(s.points[i]), fy(s.points[i + 1]) end
      out[#out + 1] = P(s.color, unpack(pts))
    end
  end
  return out
end

--- The same drawing the colours changed, as a statue or a ghost of something.
local function inked(list, map)
  local out = {}
  for _, s in ipairs(list) do
    local copy = {}
    for k, v in pairs(s) do copy[k] = v end
    copy.color = map[s.color] or map.all or s.color
    out[#out + 1] = copy
  end
  return out
end

-- ---------------------------------------------------------------- people

local HAND_X, HAND_Y = 0.84, 0.48

--- Anyone on two legs, facing right, with an arm out to hold something at HAND_X, HAND_Y. wide: half the shoulders. hem: where the coat
-- stops, 0.98 for a robe with no legs showing. flare: how much it spreads. back goes behind them, body on their chest, head instead
-- of the plain head, over on top of everything. smile and fangs and eye for the plain head, hair its colour.
local function man(o)
  local w, hem, skin, coat = o.wide or 0.2, o.hem or 0.76, o.skin or C.warn, o.coat or C.tie
  local flare = o.flare or 1
  local legs, boots = o.legs or C.panel, o.boots or C.redTint
  local list = join(o.back)
  if hem < 0.95 then
    list = join(list, R(0.36, 0.7, 0.12, 0.28, legs), R(0.54, 0.7, 0.12, 0.28, legs), R(0.33, 0.93, 0.16, 0.07, boots), R(0.53, 0.93, 0.17, 0.07, boots))
  end
  list = join(list,
    R(0.5 - w - 0.07, 0.36, 0.1, 0.28, coat), E(0.5 - w - 0.02, 0.66, 0.05, 0.05, skin),
    P(coat, 0.5 - w, 0.34, 0.5 + w, 0.34, 0.5 + w * flare, hem, 0.5 - w * flare, hem),
    o.trim and R(0.46, 0.34, 0.09, hem - 0.34, o.trim), o.body)
  if not o.noArm then list = join(list, R(0.5 + w - 0.05, 0.44, HAND_X - 0.45 - w, 0.08, coat), E(HAND_X, HAND_Y, 0.05, 0.05, skin)) end
  local head = o.head
  if not head then
    head = { R(0.47, 0.3, 0.1, 0.06, skin), E(0.54, 0.2, 0.15, 0.16, skin) }
    if o.hair then head[#head + 1] = P(o.hair, 0.37, 0.2, 0.39, 0.05, 0.54, 0.01, 0.7, 0.06, 0.72, 0.14, 0.56, 0.11, 0.44, 0.13, 0.43, 0.26) end
    head = join(head, R(0.6, 0.17, 0.06, 0.05, o.eye or C.bg))
    if o.smile then head = join(head, P(C.bg, 0.52, 0.26, 0.6, 0.29, 0.68, 0.25, 0.68, 0.27, 0.6, 0.32, 0.52, 0.28)) end
    if o.fangs then head = join(head, R(0.55, 0.28, 0.02, 0.05, C.text), R(0.63, 0.27, 0.02, 0.05, C.text)) end
  end
  return join(list, head, o.over)
end

-- ---- what's on their heads
local function hatWide(ink, band)
  return { R(0.26, 0.09, 0.6, 0.04, ink), P(ink, 0.38, 0.1, 0.41, -0.01, 0.67, -0.01, 0.7, 0.1), R(0.39, 0.06, 0.3, 0.02, band or ink) }
end
local function bowler(ink, band) return { R(0.34, 0.11, 0.42, 0.03, ink), E(0.54, 0.09, 0.15, 0.1, ink), R(0.4, 0.09, 0.28, 0.02, band or ink) } end
local function nurseCap(ink) return { P(ink, 0.38, 0.13, 0.4, 0.01, 0.68, 0.01, 0.72, 0.13), R(0.36, 0.1, 0.38, 0.03, ink), R(0.5, 0.02, 0.09, 0.03, C.red), R(0.53, 0.0, 0.03, 0.08, C.red) } end
local function strawHat() return { P(C.hi, 0.24, 0.12, 0.84, 0.12, 0.6, 0.0, 0.48, 0.0), R(0.24, 0.11, 0.6, 0.02, C.warn) } end
local function mortar(ink, tassel) return { P(ink, 0.26, 0.06, 0.54, -0.02, 0.84, 0.06, 0.54, 0.13), R(0.4, 0.08, 0.28, 0.05, ink), R(0.28, 0.06, 0.02, 0.1, tassel or C.hi) } end
local function capHelm(ink, trim) return { E(0.54, 0.13, 0.16, 0.12, ink), R(0.37, 0.13, 0.36, 0.03, trim or ink) } end
local function ledgerShield(x, ink) return { R(x, 0.32, 0.2, 0.32, ink), R(x + 0.015, 0.34, 0.08, 0.28, C.text), R(x + 0.105, 0.34, 0.08, 0.28, C.text), R(x + 0.092, 0.32, 0.016, 0.32, C.bg), R(x + 0.03, 0.4, 0.05, 0.012, C.tie), R(x + 0.03, 0.46, 0.05, 0.012, C.tie), R(x + 0.12, 0.42, 0.05, 0.012, C.red) } end
local function needleLance(ink) return { E(HAND_X, HAND_Y, 0.04, 0.06, C.hi), R(HAND_X - 0.2, HAND_Y - 0.012, 0.36, 0.024, ink or C.text) } end
local function longPole(ink, tip) return { R(0.87, 0.0, 0.028, 1, ink), P(tip or C.text, 0.84, 0.1, 0.885, -0.08, 0.93, 0.1) } end

-- ---- the Clinic's and Sindal's people

--- A vampire soldier: long pale face, red eye, the two small teeth, and a very straight back. A Stitcher.
local function stitcher(o)
  return man({ wide = 0.17, hem = o.hem or 0.78, skin = C.text, coat = o.coat, trim = o.trim, legs = o.legs or C.bg, boots = C.bg, eye = C.red, hair = o.hair or C.bg, fangs = true, flare = o.flare, back = o.back, body = o.body,
    over = join(o.hat, o.over) })
end

F.sn_stitcher = function() return stitcher({ coat = C.red, trim = C.redTint, hat = capHelm(C.red, C.hi), body = { R(0.3, 0.6, 0.4, 0.04, C.hi) }, over = needleLance() }) end
F.wm_stitcher = function()
  return stitcher({ coat = C.line, trim = C.text, hem = 0.92, flare = 1.25, hair = C.text, hat = { E(0.54, 0.09, 0.16, 0.07, C.text) }, body = { R(0.3, 0.48, 0.4, 0.015, C.tie), R(0.3, 0.58, 0.42, 0.015, C.tie), R(0.3, 0.68, 0.44, 0.015, C.tie) }, over = longPole(C.redTint, C.info) })
end
F.vt_stitcher = function()
  -- he isn't standing up again: a heap of books, and the handsome dead man lying over it
  return { R(0.04, 0.74, 0.32, 0.12, C.blueTint), R(0.1, 0.86, 0.38, 0.14, C.redTint), R(0.42, 0.78, 0.34, 0.12, C.tie), R(0.5, 0.9, 0.44, 0.1, C.blue), R(0.26, 0.66, 0.3, 0.1, C.accent), R(0.12, 0.84, 0.3, 0.012, C.text), R(0.54, 0.88, 0.2, 0.012, C.text),
    P(C.red, 0.16, 0.66, 0.5, 0.52, 0.76, 0.6, 0.72, 0.74, 0.3, 0.76), P(C.bg, 0.3, 0.72, 0.5, 0.56, 0.56, 0.58, 0.4, 0.74), R(0.6, 0.66, 0.34, 0.06, C.bg),
    E(0.14, 0.6, 0.11, 0.1, C.text), P(C.bg, 0.05, 0.58, 0.14, 0.48, 0.25, 0.54, 0.2, 0.58), R(0.16, 0.62, 0.05, 0.015, C.bg), R(0.04, 0.72, 0.5, 0.012, C.text) }
end
F.sn_bloodshot = function()
  return man({ wide = 0.17, skin = C.text, coat = C.red, trim = C.text, legs = C.text, boots = C.bg, eye = C.red, hair = C.redTint, fangs = true, noArm = true, body = { R(0.3, 0.56, 0.4, 0.04, C.bg) },
    back = { R(0.68, 0.36, 0.09, 0.3, C.red), E(0.72, 0.66, 0.05, 0.05, C.text) } })
end
F.sn_sabeth = function()
  return stitcher({ coat = C.bg, trim = C.panel, hem = 0.92, hat = bowler(C.red, C.bg), body = { R(0.3, 0.42, 0.22, 0.26, C.redTint), R(0.32, 0.44, 0.18, 0.22, C.text), R(0.35, 0.5, 0.12, 0.012, C.tie), R(0.35, 0.56, 0.12, 0.012, C.tie) }, over = needleLance() })
end
F.sn_keeper = function()
  return fit(man({ wide = 0.27, hem = 0.86, flare = 1.05, skin = C.text, coat = C.hiTint, trim = C.tie, eye = C.red, fangs = true, hair = C.bg,
    body = { R(0.24, 0.5, 0.52, 0.03, C.redTint), R(0.24, 0.66, 0.52, 0.03, C.redTint) },
    over = { P(C.line, 0.8, 0.46, 0.92, 0.28, 0.99, 0.4, 0.93, 0.34, 0.86, 0.5), P(C.line, 0.8, 0.5, 0.92, 0.68, 0.99, 0.56, 0.93, 0.62, 0.86, 0.46) } }), 1, 0.82)
end
F.wm_steward = function()
  return join(stitcher({ coat = C.bg, trim = C.tie, hem = 0.9, hair = C.tie, body = { P(C.text, 0.34, 0.34, 0.66, 0.34, 0.64, 0.38, 0.36, 0.38) } }), ledgerShield(0.64, C.redTint),
    P(C.red, 0.74, 0.3, 0.76, 0.3, 0.9, 0.16, 0.92, 0.2), { R(0.34, 0.33, 0.1, 0.02, C.text), R(0.56, 0.33, 0.1, 0.02, C.text) })
end
F.wm_tally = function() return join(stitcher({ coat = C.panel, trim = C.bg, hem = 0.9, hair = C.tie }), ledgerShield(0.68, C.tie), { P(C.text, 0.62, 0.74, 0.65, 0.76, 0.98, 0.1, 0.96, 0.08), R(0.76, 0.5, 0.03, 0.04, C.red) }) end
F.sn_cellarmaster = function()
  return stitcher({ coat = C.bg, trim = C.redTint, hem = 0.9, hair = C.text, body = { P(C.redTint, 0.34, 0.42, 0.66, 0.42, 0.7, 0.9, 0.3, 0.9), P(C.line, 0.4, 0.34, 0.62, 0.34, 0.51, 0.46), E(0.51, 0.47, 0.03, 0.03, C.line) },
    over = { P(C.text, 0.78, 0.26, 0.92, 0.26, 0.87, 0.36, 0.83, 0.36), P(C.red, 0.795, 0.29, 0.905, 0.29, 0.87, 0.35, 0.83, 0.35), R(0.84, 0.36, 0.02, 0.1, C.text), R(0.8, 0.46, 0.1, 0.012, C.text),
      R(0.1, 0.64, 0.02, 0.32, C.line), P(C.line, 0.05, 0.96, 0.17, 0.9, 0.05, 0.84, 0.17, 0.78, 0.07, 0.74) } })
end
F.sn_barnabas = function()
  local list = fit(man({ wide = 0.3, hem = 0.8, flare = 1.05, skin = C.text, coat = C.redTint, trim = C.bg, eye = C.red, hair = C.red, legs = C.bg, boots = C.bg,
    body = { P(C.hi, 0.32, 0.36, 0.72, 0.36, 0.52, 0.56), P(C.redTint, 0.4, 0.36, 0.64, 0.36, 0.52, 0.48), E(0.52, 0.56, 0.04, 0.04, C.hi) },
    head = { R(0.45, 0.3, 0.16, 0.06, C.text), E(0.56, 0.2, 0.2, 0.18, C.text), P(C.red, 0.36, 0.2, 0.38, 0.03, 0.56, -0.02, 0.76, 0.06, 0.74, 0.12, 0.54, 0.1, 0.44, 0.14), R(0.62, 0.15, 0.07, 0.05, C.red),
      P(C.bg, 0.48, 0.26, 0.74, 0.24, 0.72, 0.34, 0.52, 0.36), P(C.text, 0.66, 0.25, 0.7, 0.25, 0.68, 0.42), R(0.54, 0.26, 0.08, 0.02, C.text) },
    over = { R(0.8, 0.33, 0.14, 0.15, C.hi), R(0.8, 0.3, 0.14, 0.04, C.text), R(0.94, 0.36, 0.03, 0.09, C.hi), R(0.86, 0.33, 0.012, 0.15, C.warn) } }), 1, 1)
  for i = 0, 6 do list[#list + 1] = E(0.2 + i * 0.1, 0.33 + (i % 2) * 0.02, 0.07, 0.05, i % 2 == 0 and C.text or C.line) end  -- the furs
  return list
end

-- ---- thralls and the kept, happy to a man

local function thrallOf(o)
  return man({ wide = o.wide or 0.16, hem = o.hem, skin = C.line, coat = o.coat or C.line, trim = o.trim, legs = o.legs or C.tie, boots = C.panel, eye = C.tie, hair = o.hair or C.tie, smile = true, body = o.body, over = o.over, noArm = o.noArm })
end
F.sn_contented = function()
  return thrallOf({ coat = C.tie, trim = C.line, hem = 0.86, over = { P(C.text, 0.74, 0.4, 0.84, 0.44, 0.84, 0.7, 0.76, 0.62), P(C.text, 0.8, 0.28, 0.9, 0.28, 0.88, 0.42, 0.82, 0.42), R(0.8, 0.28, 0.1, 0.02, C.red) } })
end
F.sn_harvester = function()
  return thrallOf({ coat = C.text, trim = C.line, hem = 0.8, over = join(strawHat(), { R(0.82, 0.08, 0.03, 0.9, C.redTint), P(C.text, 0.85, 0.08, 1, 0.14, 0.92, 0.0, 0.84, 0.03) }) })
end
F.sn_sluiceman = function()
  return fit(thrallOf({ wide = 0.27, coat = C.bg, trim = C.tie, hem = 0.86, over = { R(0.16, 0.34, 0.13, 0.34, C.bg), R(0.72, 0.44, 0.14, 0.08, C.bg), R(0.82, 0.04, 0.06, 0.76, C.line), R(0.76, 0.02, 0.18, 0.06, C.line), P(C.tie, 0.76, 0.76, 0.94, 0.76, 0.96, 1, 0.74, 1) } }), 1, 1)
end
F.wm_thrall = function()
  return thrallOf({ coat = C.tie, trim = C.panel, hem = 0.84, over = { P(C.text, 0.2, 0.76, 0.26, 0.8, 0.98, 0.1, 0.92, 0.06), P(C.redTint, 0.86, 0.02, 1, 0.08, 0.92, 0.2), E(0.56, 0.44, 0.05, 0.05, C.line), E(0.84, 0.48, 0.07, 0.04, C.text) } })
end

-- ---- pirates, dockers and grey men

F.hr_bruiser = function()
  return fit(man({ wide = 0.31, hem = 0.74, flare = 1.05, coat = C.redTint, trim = C.tie, hair = C.panel, eye = C.bg,
    head = { E(0.54, 0.24, 0.17, 0.13, C.warn), R(0.62, 0.21, 0.05, 0.04, C.bg), R(0.56, 0.3, 0.1, 0.015, C.bg), P(C.panel, 0.38, 0.2, 0.42, 0.1, 0.68, 0.1, 0.7, 0.16, 0.5, 0.17) },
    over = { R(0.82, 0.16, 0.05, 0.36, C.warn), R(0.8, 0.12, 0.09, 0.06, C.warn), R(0.8, 0.24, 0.09, 0.02, C.redTint) } }), 1, 1)
end
F.hr_cutthroat = function()
  return man({ wide = 0.16, coat = C.tie, trim = C.panel, hair = C.bg, legs = C.bg,
    head = { E(0.54, 0.2, 0.14, 0.15, C.warn), P(C.bg, 0.38, 0.2, 0.42, 0.05, 0.68, 0.06, 0.7, 0.13, 0.46, 0.15), R(0.6, 0.17, 0.06, 0.05, C.bg), P(C.red, 0.4, 0.23, 0.7, 0.23, 0.68, 0.34, 0.44, 0.36), P(C.red, 0.42, 0.28, 0.3, 0.42, 0.42, 0.34) },
    body = { R(0.3, 0.54, 0.4, 0.07, C.red), P(C.red, 0.34, 0.6, 0.42, 0.6, 0.4, 0.78, 0.32, 0.74) },
    over = { R(0.7, 0.45, 0.08, 0.05, C.blue), R(0.8, 0.44, 0.1, 0.02, C.hi), P(C.text, 0.84, 0.44, 0.88, 0.44, 0.99, 0.2, 0.92, 0.1, 0.97, 0.22) } })
end
F.hr_inspector = function()
  return man({ wide = 0.15, hem = 0.86, coat = C.line, trim = C.text, legs = C.tie, boots = C.bg, skin = C.warn,
    head = { R(0.47, 0.3, 0.1, 0.06, C.warn), E(0.54, 0.2, 0.14, 0.15, C.warn), P(C.bg, 0.4, 0.16, 0.42, 0.05, 0.66, 0.05, 0.69, 0.11, 0.46, 0.12), P(C.text, 0.5, 0.12, 0.7, 0.12, 0.7, 0.26, 0.5, 0.24), R(0.6, 0.16, 0.05, 0.03, C.bg) },
    body = { R(0.28, 0.58, 0.2, 0.14, C.redTint), P(C.redTint, 0.36, 0.36, 0.4, 0.36, 0.36, 0.6, 0.32, 0.6) },
    over = { R(0.83, 0.28, 0.02, 0.2, C.text), P(C.hi, 0.83, 0.28, 0.85, 0.28, 0.84, 0.22) } })
end
F.hr_keel = function()
  return man({ wide = 0.16, hem = 0.92, flare = 1.25, coat = C.tie, trim = C.line, legs = C.panel, skin = C.warn, eye = C.bg, hair = C.line,
    over = join(hatWide(C.tie, C.line), { E(HAND_X, HAND_Y, 0.05, 0.05, C.line), R(0.84, 0.43, 0.16, 0.05, C.redTint), P(C.line, 0.94, 0.34, 0.97, 0.34, 0.97, 0.56, 0.94, 0.56), R(0.8, 0.44, 0.04, 0.02, C.text) }) })
end
F.px_matron = function()
  return man({ wide = 0.13, hem = 0.97, flare = 1.5, coat = C.text, trim = C.line, skin = C.text,
    head = { R(0.47, 0.28, 0.1, 0.08, C.tie), E(0.54, 0.2, 0.13, 0.13, C.tie), P(C.tie, 0.43, 0.1, 0.38, -0.08, 0.5, 0.05), P(C.tie, 0.65, 0.1, 0.7, -0.08, 0.58, 0.05), P(C.redTint, 0.45, 0.09, 0.42, -0.02, 0.5, 0.06), P(C.redTint, 0.63, 0.09, 0.66, -0.02, 0.58, 0.06),
      R(0.59, 0.16, 0.05, 0.04, C.red), E(0.66, 0.25, 0.04, 0.03, C.redTint), P(C.text, 0.58, 0.28, 0.61, 0.28, 0.595, 0.34), P(C.text, 0.42, 0.04, 0.68, 0.04, 0.7, 0.1, 0.4, 0.1) },
    body = { R(0.42, 0.3, 0.2, 0.05, C.line), R(0.47, 0.4, 0.1, 0.02, C.red), R(0.51, 0.36, 0.02, 0.1, C.red) },
    over = { R(0.83, 0.5, 0.014, 0.05, C.line), R(0.79, 0.54, 0.1, 0.02, C.bg), R(0.8, 0.56, 0.08, 0.1, C.hi), R(0.825, 0.58, 0.03, 0.06, C.text), R(0.79, 0.66, 0.1, 0.02, C.bg) } })
end
F.vt_matron = function()
  return man({ wide = 0.13, hem = 0.97, flare = 1.5, coat = C.tie, trim = C.line, skin = C.line, eye = C.bg, hair = C.tie,
    body = { P(C.line, 0.4, 0.42, 0.62, 0.42, 0.7, 0.96, 0.32, 0.96), R(0.4, 0.46, 0.22, 0.015, C.tie) },
    over = join(nurseCap(C.text), { R(0.83, 0.34, 0.024, 0.12, C.redTint), P(C.hi, 0.8, 0.3, 0.87, 0.3, 0.93, 0.2, 0.74, 0.2), R(0.74, 0.3, 0.2, 0.012, C.warn) }) })
end
F.vt_reader = function()
  return man({ wide = 0.15, skin = C.text, coat = C.line, trim = C.text, legs = C.line, boots = C.tie, hair = C.tie,
    head = { R(0.47, 0.3, 0.1, 0.06, C.text), E(0.54, 0.2, 0.14, 0.15, C.text), P(C.tie, 0.4, 0.14, 0.42, 0.05, 0.66, 0.05, 0.69, 0.1, 0.46, 0.1), R(0.39, 0.13, 0.31, 0.08, C.text), R(0.39, 0.2, 0.31, 0.012, C.line), R(0.37, 0.14, 0.04, 0.1, C.text), R(0.56, 0.26, 0.09, 0.02, C.tie) },
    body = { R(0.46, 0.42, 0.09, 0.03, C.red), R(0.49, 0.38, 0.03, 0.12, C.red) }, over = { R(0.9, 0.44, 0.08, 0.018, C.text) } })
end
F.ud_exile = function()
  return man({ wide = 0.15, coat = C.bg, trim = C.panel, legs = C.bg, boots = C.panel, skin = C.blueTint, eye = C.red,
    head = { E(0.54, 0.2, 0.13, 0.15, C.blueTint), P(C.blueTint, 0.46, 0.14, 0.32, 0.08, 0.44, 0.24), P(C.text, 0.42, 0.3, 0.4, 0.06, 0.54, 0.02, 0.68, 0.07, 0.69, 0.12, 0.54, 0.11, 0.5, 0.34), R(0.6, 0.17, 0.05, 0.03, C.red) },
    body = { R(0.36, 0.42, 0.08, 0.08, C.tie), R(0.56, 0.6, 0.08, 0.07, C.tie) }, over = { R(0.82, 0.44, 0.14, 0.04, C.tie), P(C.line, 0.9, 0.36, 0.93, 0.36, 0.93, 0.56, 0.9, 0.56), R(0.9, 0.455, 0.1, 0.012, C.text) } })
end
F.ud_lolthsworn = function()
  local list = man({ wide = 0.15, hem = 0.97, flare = 1.5, coat = C.bg, trim = C.accent, skin = C.blueTint, eye = C.red,
    back = { P(C.text, 0.44, 0.0, 0.7, 0.04, 0.78, 0.5, 0.3, 0.52) },
    over = { R(0.86, 0.1, 0.03, 0.88, C.redTint), E(0.875, 0.08, 0.07, 0.06, C.bg), E(0.875, 0.08, 0.04, 0.035, C.red) } })
  for i = -3, 3 do list[#list + 1] = R(0.42 + (i + 3) * 0.05, 0.05 + abs(i) * 0.012, 0.01, 0.3, C.line) end
  for i = 0, 3 do
    list[#list + 1] = P(C.bg, 0.875, 0.08, 0.77 - i * 0.015, 0.0 + i * 0.05, 0.75, 0.04 + i * 0.05)
    list[#list + 1] = P(C.bg, 0.875, 0.08, 0.98 + i * 0.01, 0.0 + i * 0.05, 1, 0.04 + i * 0.05)
  end
  return list
end
F.ud_sapper = function()
  return fit(man({ wide = 0.23, skin = C.line, coat = C.tie, trim = C.redTint, legs = C.bg, eye = C.red, flare = 1.05,
    back = { E(0.2, 0.46, 0.17, 0.2, C.redTint), R(0.04, 0.4, 0.32, 0.03, C.line), R(0.04, 0.5, 0.32, 0.03, C.line), R(0.17, 0.2, 0.02, 0.1, C.warn), E(0.18, 0.2, 0.025, 0.03, C.hi) },
    head = { R(0.47, 0.3, 0.1, 0.06, C.line), E(0.54, 0.2, 0.15, 0.15, C.line), R(0.6, 0.17, 0.06, 0.04, C.red), P(C.tie, 0.42, 0.26, 0.68, 0.26, 0.6, 0.52, 0.5, 0.46) },
    over = { R(0.84, 0.1, 0.03, 0.46, C.redTint), P(C.line, 0.66, 0.2, 0.86, 0.06, 1, 0.18, 0.86, 0.13) } }), 0.92, 0.72)
end
F.ud_drowned = function()
  local list = man({ wide = 0.18, coat = C.line, trim = C.blueTint, legs = C.tie, boots = C.line, skin = C.text, eye = C.bg, hair = C.line, noArm = true,
    back = { R(0.68, 0.36, 0.1, 0.34, C.line), E(0.73, 0.72, 0.05, 0.05, C.text) } })
  for i = 0, 8 do list[#list + 1] = E(0.32 + i * 0.05, 0.42 + (i * 7 % 5) * 0.08, 0.03, 0.02, C.text) end
  return join(list, E(0.42, 0.24, 0.035, 0.05, C.soft), E(0.4, 0.26, 0.02, 0.03, C.ok), R(0.54, 0.27, 0.08, 0.02, C.bg))
end
F.em_shard = function()
  local list = man({ wide = 0.16, hem = 0.86, coat = C.text, trim = C.line, legs = C.line, boots = C.warn, skin = C.warn, eye = C.redTint, noArm = true, hair = C.redTint,
    back = { R(0.68, 0.38, 0.09, 0.14, C.text), R(0.74, 0.46, 0.18, 0.06, C.text), E(0.92, 0.49, 0.04, 0.04, C.warn) } })
  return join(list, P(C.info, 0.34, 0.86, 0.3, 0.5, 0.38, 0.3, 0.44, 0.6, 0.5, 0.42, 0.52, 0.86), P(C.text, 0.36, 0.84, 0.34, 0.54, 0.38, 0.4, 0.4, 0.84), P(C.info, 0.56, 0.16, 0.64, -0.04, 0.72, 0.12, 0.78, 0.04, 0.74, 0.3, 0.6, 0.3), P(C.text, 0.62, 0.14, 0.64, 0.02, 0.68, 0.16))
end
F.wm_stopped = function()
  local list = fit(man({ wide = 0.2, hem = 0.97, flare = 1.3, coat = C.bg, skin = C.ok, eye = C.red, hair = C.tie, head = { E(0.54, 0.2, 0.15, 0.15, C.ok), P(C.ok, 0.66, 0.2, 0.78, 0.26, 0.66, 0.28), R(0.59, 0.16, 0.06, 0.05, C.red), R(0.54, 0.27, 0.1, 0.05, C.bg), P(C.tie, 0.38, 0.22, 0.4, 0.03, 0.56, -0.02, 0.7, 0.06, 0.7, 0.13, 0.54, 0.09, 0.46, 0.2) } }), 1, 1)
  return join(list, P(C.info, 0.14, 1, 0.2, 0.42, 0.38, 0.32, 0.64, 0.32, 0.82, 0.42, 0.88, 1), P(C.blueTint, 0.5, 0.36, 0.76, 0.46, 0.82, 1, 0.56, 1), P(C.text, 0.24, 0.96, 0.28, 0.46, 0.36, 0.4, 0.32, 0.96), R(0.76, 0.5, 0.2, 0.02, C.text))
end
F.em_invigilator = function()
  local list = man({ wide = 0.17, hem = 0.97, flare = 1.5, coat = C.text, trim = C.line, skin = C.text, eye = C.tie, over = join(mortar(C.text, C.line), { R(0.84, 0.0, 0.03, 0.86, C.line), R(0.84, 0.1, 0.05, 0.012, C.tie), R(0.84, 0.2, 0.05, 0.012, C.tie), R(0.84, 0.3, 0.05, 0.012, C.tie), R(0.84, 0.4, 0.05, 0.012, C.tie) }) })
  list = inked(list, { [C.warn] = C.text })
  return join(list, R(0.3, 0.6, 0.015, 0.36, C.line), R(0.42, 0.64, 0.015, 0.32, C.line), R(0.62, 0.62, 0.015, 0.34, C.line), R(0.56, 0.27, 0.08, 0.012, C.tie), R(0.16, 0.93, 0.7, 0.07, C.line))
end
F.wm_reedman = function()
  local list = { R(0.36, 0.5, 0.06, 0.5, C.hi), R(0.56, 0.5, 0.06, 0.5, C.hi), R(0.47, 0.2, 0.06, 0.6, C.warn), R(0.12, 0.38, 0.76, 0.05, C.hi) }
  for i = 0, 6 do list[#list + 1] = P(i % 2 == 0 and C.hi or C.warn, 0.34 + i * 0.03, 0.3, 0.38 + i * 0.03, 0.3, 0.28 + i * 0.075, 0.74, 0.25 + i * 0.075, 0.74) end
  for i = 0, 3 do
    list[#list + 1] = R(0.08 + i * 0.02, 0.36 + i * 0.03, 0.02, 0.16, C.hi)
    list[#list + 1] = R(0.86 + i * 0.02, 0.36 + i * 0.03, 0.02, 0.16, C.hi)
  end
  return join(list, R(0.38, 0.32, 0.26, 0.03, C.redTint), R(0.38, 0.62, 0.26, 0.03, C.redTint), P(C.info, 0.38, 0.06, 0.64, 0.04, 0.68, 0.3, 0.5, 0.36, 0.36, 0.28), P(C.text, 0.42, 0.08, 0.56, 0.06, 0.5, 0.3, 0.4, 0.26),
    R(0.42, 0.14, 0.07, 0.04, C.bg), R(0.54, 0.14, 0.07, 0.04, C.bg), P(C.bg, 0.52, 0.04, 0.54, 0.18, 0.5, 0.3, 0.53, 0.18))
end

-- ---------------------------------------------------------------- worms, leeches and things with a mouth

--- A body that bends, ringed all down it. mouth: the round sucker of small teeth. eye: a single wet one.
local function worm(o)
  local x1, y1, x2, y2 = o.x1 or 0.04, o.y1 or 0.86, o.x2 or 0.74, o.y2 or 0.34
  local bend, waves, phase = o.bend or 0.15, o.waves or 1, o.phase or 0
  local wide1, wide2 = o.wide1 or 0.22, o.wide2 or 0.3
  local list = join(o.back, snake(o.ink, x1, y1, x2, y2, wide1, wide2, bend, waves, phase))
  local rings = o.rings or 7
  for i = 1, rings do
    local t = i / (rings + 1)
    local cx, cy, nx, ny = along(x1, y1, x2, y2, bend, waves, phase, t)
    local half = (wide1 + (wide2 - wide1) * t) / 2
    local dx, dy = -ny * 0.014, nx * 0.014
    list[#list + 1] = P(o.ring, cx + nx * half + dx, cy + ny * half + dy, cx + nx * half - dx, cy + ny * half - dy, cx - nx * half - dx, cy - ny * half - dy, cx - nx * half + dx, cy - ny * half + dy)
  end
  if o.belly then list[#list + 1] = snake(o.belly, x1, y1 + 0.03, x2, y2 + 0.03, wide1 * 0.3, wide2 * 0.25, bend, waves, phase) end
  local rx, ry = o.mouthW or wide2 * 0.55, o.mouthH or wide2 * 0.68
  if o.mouth then
    list = join(list, E(x2 + 0.02, y2, rx, ry, o.lip or o.ink), E(x2 + 0.03, y2, rx * 0.74, ry * 0.76, o.gum or C.red), E(x2 + 0.03, y2, rx * 0.4, ry * 0.42, C.bg))
    for i = 0, (o.teeth or 7) - 1 do
      local a = i / (o.teeth or 7) * 6.283
      local cs, sn = math.cos(a), sin(a)
      list[#list + 1] = P(C.text, x2 + 0.03 + cs * rx * 0.8, y2 + sn * ry * 0.8 - 0.012, x2 + 0.03 + cs * rx * 0.8, y2 + sn * ry * 0.8 + 0.012, x2 + 0.03 + cs * rx * 0.42, y2 + sn * ry * 0.42)
    end
  end
  if o.eye then list = join(list, E(x2 + 0.02, y2, rx, ry, C.text), E(x2 + 0.05, y2, rx * 0.6, ry * 0.7, o.eye), E(x2 + 0.06, y2, rx * 0.2, ry * 0.6, C.bg)) end
  return join(list, o.over)
end

F.px_leech = function() return worm({ ink = C.line, ring = C.tie, belly = C.text, mouth = true }) end
F.hr_leech = function() return worm({ ink = C.tie, ring = C.bg, belly = C.line, mouth = true, gum = C.redTint, wide1 = 0.18, wide2 = 0.24, x2 = 0.78, y2 = 0.26, over = { E(0.16, 0.92, 0.3, 0.05, C.blueTint) } }) end
F.px_fatleech = function() return worm({ ink = C.accent, ring = C.tie, belly = C.line, mouth = true, x1 = 0.04, y1 = 0.74, x2 = 0.8, y2 = 0.56, wide1 = 0.5, wide2 = 0.46, bend = 0.05, rings = 9, over = { E(0.3, 0.6, 0.09, 0.04, C.text), E(0.5, 0.56, 0.06, 0.03, C.text) } }) end
F.px_alderman = function()
  local list = worm({ ink = C.panel, ring = C.tie, belly = C.tie, mouth = true, x1 = 0.06, y1 = 0.92, x2 = 0.68, y2 = 0.26, wide1 = 0.42, wide2 = 0.5, bend = 0.1, rings = 8, mouthW = 0.25, mouthH = 0.3, teeth = 11, back = { R(0, 0.86, 1, 0.14, C.blueTint), R(0.1, 0.9, 0.5, 0.02, C.line) } })
  for i = 0, 8 do list[#list + 1] = E(0.2 + i * 0.045, 0.64 + i * 0.03 - (i > 4 and (i - 4) * 0.06 or 0), 0.03, 0.022, i % 2 == 0 and C.hi or C.warn) end  -- the chain of office
  return join(list, E(0.42, 0.72, 0.06, 0.06, C.hi), E(0.42, 0.72, 0.03, 0.03, C.warn))
end
F.ud_pitworm = function() return worm({ ink = C.text, ring = C.line, belly = C.line, mouth = true, gum = C.redTint, x1 = 0.02, y1 = 0.8, x2 = 0.72, y2 = 0.42, wide1 = 0.34, wide2 = 0.4, bend = 0.12, waves = 1.4, rings = 9 }) end
F.ud_lamprey = function() return worm({ ink = C.line, ring = C.tie, belly = C.text, mouth = true, x1 = 0.34, y1 = 0.98, x2 = 0.6, y2 = 0.22, wide1 = 0.12, wide2 = 0.24, bend = 0.1, waves = 1.5, rings = 0, teeth = 9, over = { P(C.line, 0.08, 1, 0.34, 0.86, 0.4, 0.98) } }) end
F.wm_eel = function()
  return worm({ ink = C.bg, ring = C.text, mouth = true, lip = C.tie, x1 = 0.4, y1 = 0.94, x2 = 0.62, y2 = 0.2, wide1 = 0.2, wide2 = 0.24, bend = 0.13, waves = 1.6, rings = 6, teeth = 9,
    back = { E(0.42, 0.94, 0.36, 0.06, C.bg), E(0.42, 0.93, 0.4, 0.07, C.text), E(0.42, 0.93, 0.28, 0.045, C.bg) } })
end
F.vt_grub = function() return worm({ ink = C.warn, ring = C.redTint, belly = C.hi, eye = C.soft, x1 = 0.06, y1 = 0.72, x2 = 0.78, y2 = 0.6, wide1 = 0.34, wide2 = 0.34, bend = 0.08, rings = 6, mouthW = 0.07, mouthH = 0.08,
  back = { R(0.0, 0.83, 1, 0.045, C.line), R(0.1, 0.8, 0.12, 0.1, C.tie), R(0.42, 0.8, 0.12, 0.1, C.tie), R(0.74, 0.8, 0.12, 0.1, C.tie) } })
end
F.em_bookworm = function()
  local list = worm({ ink = C.text, ring = C.line, mouth = true, gum = C.line, x1 = 0.02, y1 = 0.84, x2 = 0.76, y2 = 0.56, wide1 = 0.2, wide2 = 0.3, bend = 0.1, waves = 1.5, rings = 5 })
  for i = 0, 6 do list[#list + 1] = R(0.16 + i * 0.08, 0.68 - i * 0.022 + (i % 2) * 0.05, 0.05, 0.012, C.bg) end
  return list
end
F.ud_mother = function()
  local list = worm({ ink = C.text, ring = C.line, mouth = true, gum = C.red, lip = C.line, x1 = 0.0, y1 = 0.98, x2 = 0.5, y2 = 0.4, wide1 = 0.6, wide2 = 0.76, bend = 0.05, rings = 5, mouthW = 0.44, mouthH = 0.4, teeth = 15,
    back = { R(0, 0.9, 1, 0.1, C.blueTint), P(C.tie, 0.5, 0.82, 1, 0.74, 1, 0.84, 0.5, 0.9) } })
  list = join(list, E(0.53, 0.4, 0.31, 0.28, C.redTint), E(0.53, 0.4, 0.22, 0.2, C.bg), E(0.53, 0.4, 0.12, 0.11, C.red), E(0.53, 0.4, 0.06, 0.06, C.bg))
  for ring = 1, 2 do
    local rx, ry = 0.14 + ring * 0.08, 0.13 + ring * 0.072
    for i = 0, 15 do
      local a = i / 16 * 6.283 + ring
      list[#list + 1] = P(C.text, 0.53 + math.cos(a - 0.15) * rx, 0.4 + sin(a - 0.15) * ry, 0.53 + math.cos(a + 0.15) * rx, 0.4 + sin(a + 0.15) * ry, 0.53 + math.cos(a) * rx * 0.72, 0.4 + sin(a) * ry * 0.72)
    end
  end
  return list
end

local function chainDown(x, top, n, ink, dark)
  local list = {}
  for i = 0, n do
    list[#list + 1] = i % 2 == 0 and R(x - 0.05, top + i * 0.1, 0.1, 0.1, ink) or R(x - 0.018, top + i * 0.1 - 0.01, 0.036, 0.12, dark or C.line)
    if i % 2 == 0 then list[#list + 1] = R(x - 0.024, top + i * 0.1 + 0.025, 0.048, 0.05, C.bg) end
  end
  return list
end

F.vt_bookworm = function()
  local list = join(chainDown(0.1, -0.1, 11, C.tie), chainDown(0.5, -0.1, 11, C.tie), chainDown(0.92, -0.1, 11, C.tie),
    worm({ ink = C.line, ring = C.tie, x1 = 0.0, y1 = 0.9, x2 = 0.72, y2 = 0.3, wide1 = 0.34, wide2 = 0.38, bend = 0.3, waves = 2.3, phase = 0.4, rings = 12 }))
  for i = 1, 5 do
    local cx, cy = along(0.0, 0.9, 0.72, 0.3, 0.3, 2.3, 0.4, i / 6)
    list = join(list, E(cx, cy, 0.05, 0.09, C.tie), E(cx, cy, 0.024, 0.05, C.bg))
  end
  return join(list, E(0.76, 0.3, 0.23, 0.25, C.tie), E(0.76, 0.3, 0.19, 0.2, C.text), P(C.red, 0.6, 0.28, 0.7, 0.3, 0.66, 0.36), P(C.red, 0.76, 0.46, 0.8, 0.38, 0.84, 0.46), P(C.red, 0.72, 0.13, 0.78, 0.2, 0.68, 0.18),
    E(0.8, 0.3, 0.12, 0.14, C.soft), E(0.81, 0.3, 0.04, 0.13, C.bg), P(C.text, 0.58, 0.46, 0.64, 0.5, 0.6, 0.6), P(C.text, 0.72, 0.52, 0.78, 0.52, 0.75, 0.66), P(C.text, 0.86, 0.5, 0.92, 0.46, 0.91, 0.62))
end

F.vt_qarhuul = function()
  local list = { snake(C.line, 0.42, 1.1, 0.62, -0.1, 0.72, 0.28, 0.2, 1.5, 0), snake(C.tie, 0.32, 1.1, 0.58, -0.1, 0.3, 0.09, 0.2, 1.5, 0) }
  for i = 0, 7 do
    local cx, cy, nx = along(0.42, 1.1, 0.62, -0.1, 0.2, 1.5, 0, 0.1 + i * 0.105)
    local x, rx = cx + nx * (i % 2 == 0 and 0.07 or -0.06), 0.075 - i * 0.006
    list = join(list, E(x, cy, rx + 0.016, rx * 0.8 + 0.016, C.soft), E(x, cy, rx, rx * 0.8, C.text), E(x + (i % 3) * 0.01, cy, rx * 0.34, rx * 0.68, C.bg))
  end
  for i = 0, 3 do list[#list + 1] = E(0.06 + i * 0.3, 0.9 + (i % 2) * 0.06, 0.26, 0.1, i % 2 == 0 and C.line or C.tie) end
  return join(list, E(0.5, 0.97, 0.56, 0.06, C.text))
end

-- ---------------------------------------------------------------- bats and birds

--- Wings out, a small hungry body in the middle. hang: upside down, by a foot.
local function batOf(o)
  local wing, web, fur = o.wing or C.tie, o.web or C.panel, o.fur or C.redTint
  local list = {
    P(wing, 0.5, 0.36, 0.3, 0.1, 0.0, 0.2, 0.04, 0.5, 0.12, 0.44, 0.16, 0.66, 0.26, 0.54, 0.36, 0.72, 0.48, 0.6),
    P(wing, 0.62, 0.36, 0.76, 0.1, 1, 0.2, 0.98, 0.48, 0.9, 0.44, 0.86, 0.64, 0.8, 0.54, 0.74, 0.7, 0.66, 0.6),
    P(web, 0.48, 0.42, 0.3, 0.2, 0.12, 0.26, 0.2, 0.46, 0.4, 0.56), P(web, 0.66, 0.42, 0.76, 0.2, 0.92, 0.26, 0.86, 0.46, 0.68, 0.56),
    E(0.57, 0.56, o.thin and 0.08 or 0.12, 0.2, fur), E(0.57, 0.36, 0.12, 0.12, fur),
    P(fur, 0.47, 0.3, 0.46, 0.1, 0.55, 0.26), P(fur, 0.67, 0.3, 0.68, 0.1, 0.59, 0.26),
    E(0.61, 0.34, 0.03, 0.03, o.eye or C.red), E(0.53, 0.34, 0.03, 0.03, o.eye or C.red), R(0.52, 0.42, 0.1, 0.03, C.bg),
    P(C.text, 0.53, 0.44, 0.56, 0.44, 0.545, 0.5), P(C.text, 0.59, 0.44, 0.62, 0.44, 0.605, 0.5),
  }
  return join(list, o.over)
end

F.px_bat = function()
  local list = batOf({ wing = C.redTint, web = C.bg, fur = C.tie, thin = true })
  return join(list, R(0.5, 0.52, 0.14, 0.012, C.bg), R(0.5, 0.57, 0.14, 0.012, C.bg), R(0.5, 0.62, 0.14, 0.012, C.bg))
end
F.ud_bat = function()
  local list = batOf({ wing = C.panel, web = C.bg, fur = C.tie, eye = C.accent })
  for i = 0, 6 do
    list[#list + 1] = E(0.08 + i * 0.05, 0.24 + (i % 2) * 0.1, 0.03, 0.02, C.accent)
    list[#list + 1] = E(0.72 + i * 0.04, 0.2 + (i % 2) * 0.12, 0.03, 0.02, C.accent)
  end
  return list
end
F.sn_cliff_bat = function() return batOf({ wing = C.line, web = C.tie, fur = C.line, eye = C.bg, thin = true }) end
F.sn_nestling = function()
  local list = batOf({ wing = C.redTint, web = C.bg, fur = C.tie, thin = true })
  local flipped = {}
  for i, s in ipairs(fit(list, 0.8, 0.8)) do
    if s.kind == "e" then
      flipped[i] = E(s.cx, 1 - s.cy, s.rx, s.ry, s.color)
    elseif s.kind == "r" then
      flipped[i] = R(s.x, 1 - s.y - s.h, s.w, s.h, s.color)
    else
      local pts = {}
      for k = 1, #s.points, 2 do pts[k], pts[k + 1] = s.points[k], 1 - s.points[k + 1] end
      flipped[i] = P(s.color, unpack(pts))
    end
  end
  return join({ R(0.08, 0, 0.84, 0.05, C.tie) }, { R(0.55, 0.04, 0.02, 0.12, C.tie) }, flipped)
end

--- A bat on its hind legs that remembers having been someone. coat: what's left of their clothes.
local function batMan(o)
  return man({ wide = 0.18, hem = o.hem or 0.74, coat = o.coat, trim = o.trim, legs = C.tie, boots = C.line, skin = C.tie,
    back = { P(C.redTint, 0.34, 0.34, 0.1, 0.16, 0.0, 0.3, 0.02, 0.66, 0.12, 0.56, 0.16, 0.76, 0.3, 0.6), P(C.bg, 0.3, 0.38, 0.12, 0.26, 0.08, 0.5, 0.26, 0.56) },
    head = { E(0.56, 0.22, 0.14, 0.13, C.tie), P(C.tie, 0.45, 0.14, 0.4, -0.08, 0.54, 0.08), P(C.tie, 0.65, 0.12, 0.74, -0.08, 0.59, 0.08), P(C.redTint, 0.47, 0.13, 0.43, -0.02, 0.52, 0.08), P(C.redTint, 0.65, 0.11, 0.7, -0.02, 0.6, 0.08),
      E(0.66, 0.26, 0.05, 0.04, C.redTint), R(0.59, 0.18, 0.05, 0.04, C.red), R(0.54, 0.3, 0.15, 0.02, C.bg), P(C.text, 0.58, 0.31, 0.61, 0.31, 0.595, 0.37), P(C.text, 0.64, 0.31, 0.67, 0.31, 0.655, 0.37) },
    body = o.body, over = o.over })
end
F.px_werebat = function() return batMan({ coat = C.text, trim = C.line, body = { P(C.bg, 0.34, 0.76, 0.42, 0.66, 0.5, 0.76), P(C.bg, 0.54, 0.76, 0.62, 0.68, 0.68, 0.76), R(0.36, 0.46, 0.08, 0.05, C.red) }, over = { P(C.text, 0.87, 0.44, 0.98, 0.42, 0.9, 0.48), P(C.text, 0.87, 0.5, 0.98, 0.54, 0.88, 0.53) } }) end
F.sn_werebat = function() return batMan({ coat = C.tie, trim = C.panel, body = { R(0.42, 0.34, 0.2, 0.05, C.text), P(C.text, 0.42, 0.36, 0.48, 0.38, 0.44, 0.46) }, over = { P(C.warn, 0.82, 0.44, 0.88, 0.4, 0.92, 0.5, 0.86, 0.54) } }) end

--- A carrion bird. head: a bald red one by default.
local function vulture(o)
  return { P(o.wing, 0.46, 0.46, 0.22, 0.12, 0.0, 0.2, 0.06, 0.46, 0.0, 0.62, 0.16, 0.58, 0.14, 0.78, 0.36, 0.7), P(o.wing2 or C.tie, 0.46, 0.44, 0.26, 0.2, 0.12, 0.26, 0.16, 0.46, 0.44, 0.6),
    P(o.wing, 0.54, 0.44, 0.74, 0.1, 1, 0.14, 0.92, 0.42, 1, 0.58, 0.84, 0.56, 0.84, 0.74, 0.62, 0.66),
    E(0.5, 0.56, 0.14, 0.2, o.wing), R(0.45, 0.72, 0.03, 0.2, C.hi), R(0.54, 0.72, 0.03, 0.2, C.hi), P(C.hi, 0.4, 0.92, 0.52, 0.92, 0.52, 1, 0.46, 0.95, 0.4, 1), P(C.hi, 0.5, 0.92, 0.62, 0.92, 0.62, 1, 0.56, 0.95, 0.5, 1),
    P(o.neck or C.red, 0.46, 0.46, 0.54, 0.46, 0.6, 0.26, 0.54, 0.24), E(0.6, 0.22, 0.09, 0.08, o.neck or C.red), E(0.63, 0.2, 0.02, 0.02, C.hi), P(C.hi, 0.67, 0.18, 0.8, 0.28, 0.66, 0.27) }
end
F.hr_kite = function() return vulture({ wing = C.panel, wing2 = C.tie }) end

--- A harpy: a woman's hunched body, wings, and a beak of a face. over on top.
local function harpyOf(o)
  local wing, under, skin = o.wing, o.under or C.tie, o.skin or C.line
  return join({
    P(wing, 0.46, 0.4, 0.3, 0.04, 0.0, 0.08, 0.04, 0.44, 0.0, 0.56, 0.12, 0.56, 0.1, 0.76, 0.28, 0.66, 0.3, 0.8, 0.46, 0.66),
    P(under, 0.44, 0.38, 0.28, 0.12, 0.12, 0.16, 0.16, 0.4, 0.32, 0.58),
    P(skin, 0.42, 0.38, 0.7, 0.38, 0.66, 0.76, 0.46, 0.8),
    E(0.7, 0.22, 0.14, 0.15, skin), P(o.hair or C.bg, 0.54, 0.38, 0.5, 0.1, 0.68, 0.06, 0.84, 0.1, 0.66, 0.16, 0.6, 0.34),
    E(0.76, 0.2, 0.035, 0.035, C.red), P(C.hi, 0.82, 0.22, 0.98, 0.28, 0.82, 0.31),
    R(0.48, 0.76, 0.05, 0.14, C.hi), R(0.62, 0.76, 0.05, 0.14, C.hi),
    P(C.hi, 0.4, 0.88, 0.56, 0.88, 0.6, 1, 0.52, 0.94, 0.48, 1, 0.45, 0.94, 0.4, 1), P(C.hi, 0.56, 0.88, 0.7, 0.88, 0.76, 1, 0.66, 0.94, 0.62, 1, 0.6, 0.94, 0.56, 1),
  }, o.over)
end
F.wm_harrier = function() return harpyOf({ wing = C.bg, under = C.panel, skin = C.tie, hair = C.bg, over = { P(C.red, 0.58, 0.92, 0.72, 0.92, 0.7, 1, 0.56, 1) } }) end
F.hr_carrion = function()
  local list = harpyOf({ wing = C.panel, under = C.tie, skin = C.line, hair = C.tie })
  list = join({ P(C.tie, 0.6, 0.4, 0.8, 0.5, 0.74, 0.76, 0.96, 0.92, 0.7, 0.86, 0.6, 0.66) }, list)  -- the broken one, trailing
  for i = 0, 5 do
    list[#list + 1] = R(0.5 + i * 0.03, 0.38 + (i < 3 and i or 5 - i) * 0.026, 0.024, 0.05, C.text)
  end
  return join(list, P(C.text, 0.74, 0.3, 0.77, 0.3, 0.76, 0.36), P(C.text, 0.8, 0.31, 0.83, 0.31, 0.82, 0.37))
end
F.wm_lucilda = function()
  local list = {
    R(0, 0.84, 1, 0.08, C.redTint), R(0, 0.84, 1, 0.015, C.warn),
    P(C.panel, 0.42, 0.24, 0.18, 0.04, 0.0, 0.16, 0.04, 0.42, 0.0, 0.54, 0.1, 0.56, 0.04, 0.76, 0.2, 0.68, 0.22, 0.82, 0.42, 0.72),
    P(C.bg, 0.4, 0.3, 0.2, 0.14, 0.1, 0.2, 0.14, 0.42, 0.34, 0.56),
    P(C.tie, 0.34, 0.3, 0.64, 0.26, 0.66, 0.78, 0.42, 0.82), R(0.46, 0.8, 0.04, 0.06, C.hi), R(0.58, 0.78, 0.04, 0.08, C.hi),
    P(C.hi, 0.42, 0.84, 0.54, 0.84, 0.52, 0.92, 0.46, 0.88, 0.42, 0.92), P(C.hi, 0.54, 0.84, 0.66, 0.84, 0.66, 0.92, 0.6, 0.88, 0.56, 0.92),
    E(0.66, 0.2, 0.15, 0.15, C.line), P(C.text, 0.46, 0.34, 0.46, 0.08, 0.56, 0.1, 0.56, -0.02, 0.66, 0.06, 0.74, -0.02, 0.8, 0.1, 0.66, 0.12, 0.56, 0.22, 0.56, 0.36),
    R(0.68, 0.16, 0.06, 0.04, C.hi), R(0.7, 0.17, 0.025, 0.025, C.bg), P(C.hi, 0.76, 0.2, 0.96, 0.26, 0.78, 0.34, 0.74, 0.3),
    R(0.62, 0.46, 0.2, 0.06, C.line), P(C.hi, 0.8, 0.44, 0.98, 0.38, 0.86, 0.48), P(C.hi, 0.8, 0.48, 1, 0.5, 0.86, 0.52), P(C.hi, 0.8, 0.5, 0.96, 0.62, 0.84, 0.55),
  }
  for i = 0, 5 do list[#list + 1] = E(0.42 + i * 0.05, 0.3 + (i % 2) * 0.03, 0.05, 0.04, C.text) end
  return list
end

--- An owl on a bear's frame. o.scale, and over.
local function owlOf(o)
  local fur, chest, flecks = o.fur or C.redTint, o.chest or C.tie, o.flecks or C.line
  return join({
    R(0.24, 0.8, 0.18, 0.2, fur), R(0.56, 0.8, 0.18, 0.2, fur),
    E(0.46, 0.62, 0.38, 0.32, fur), E(0.46, 0.66, 0.26, 0.24, chest), E(0.5, 0.72, 0.16, 0.16, flecks),
    R(0.42, 0.56, 0.06, 0.02, flecks), R(0.54, 0.62, 0.06, 0.02, flecks), R(0.44, 0.72, 0.06, 0.02, chest), R(0.56, 0.76, 0.06, 0.02, chest),
    E(0.6, 0.28, 0.25, 0.23, fur), P(fur, 0.38, 0.2, 0.36, 0.0, 0.5, 0.1), P(fur, 0.82, 0.2, 0.86, 0.0, 0.7, 0.1),
    E(0.5, 0.28, 0.12, 0.13, C.line), E(0.72, 0.28, 0.12, 0.13, C.line), E(0.5, 0.28, 0.09, 0.1, C.hi), E(0.72, 0.28, 0.09, 0.1, C.hi), E(0.52, 0.29, 0.04, 0.05, C.bg), E(0.74, 0.29, 0.04, 0.05, C.bg),
    P(C.hi, 0.56, 0.32, 0.66, 0.32, 0.61, 0.46),
    R(0.76, 0.5, 0.2, 0.09, fur), P(C.text, 0.92, 0.5, 1, 0.48, 0.95, 0.54), P(C.text, 0.93, 0.54, 1, 0.56, 0.93, 0.59),
    E(0.16, 0.56, 0.08, 0.1, fur),
  }, o.over)
end
F.em_owlbeast = function()
  local list = owlOf({ fur = C.tie, chest = C.panel, flecks = C.line })
  for i = 0, 7 do list[#list + 1] = P(C.tie, 0.14 + i * 0.08, 0.84 + (i % 2) * 0.05, 0.2 + i * 0.08, 0.84 + (i % 2) * 0.05, 0.17 + i * 0.08, 0.94) end
  return list
end
F.em_owlet = function()
  return fit({ E(0.5, 0.62, 0.34, 0.36, C.line), E(0.5, 0.68, 0.22, 0.24, C.text), E(0.5, 0.32, 0.3, 0.26, C.line), P(C.line, 0.26, 0.2, 0.22, 0.04, 0.38, 0.14), P(C.line, 0.74, 0.2, 0.78, 0.04, 0.62, 0.14),
    E(0.38, 0.3, 0.1, 0.11, C.text), E(0.64, 0.3, 0.1, 0.11, C.text), E(0.4, 0.3, 0.06, 0.07, C.bg), E(0.66, 0.3, 0.06, 0.07, C.bg), P(C.hi, 0.42, 0.36, 0.62, 0.36, 0.52, 0.62), R(0.46, 0.42, 0.12, 0.012, C.warn),
    R(0.36, 0.94, 0.1, 0.06, C.hi), R(0.56, 0.94, 0.1, 0.06, C.hi) }, 0.8, 0.8)
end
F.em_provost = function()
  local list = { P(C.tie, 0.34, 0.3, 0.0, 0.0, 0.0, 0.7, 0.16, 0.62, 0.14, 0.92, 0.34, 0.76), P(C.panel, 0.32, 0.34, 0.06, 0.12, 0.06, 0.58, 0.3, 0.66), P(C.tie, 0.78, 0.3, 1, 0.04, 1, 0.68, 0.9, 0.62, 0.88, 0.86, 0.76, 0.74) }
  list = join(list, owlOf({ fur = C.redTint, chest = C.tie, flecks = C.line }), P(C.accent, 0.2, 0.46, 0.72, 0.46, 0.84, 1, 0.1, 1), P(C.blueTint, 0.4, 0.46, 0.56, 0.46, 0.58, 1, 0.38, 1), P(C.accent, 0.1, 1, 0.2, 0.86, 0.26, 1), P(C.accent, 0.6, 1, 0.72, 0.84, 0.78, 1))
  for i = 0, 8 do list[#list + 1] = E(0.36 + i * 0.05, 0.47 + (i < 5 and i or 8 - i) * 0.018, 0.028, 0.02, i % 2 == 0 and C.hi or C.warn) end
  return join(list, E(0.56, 0.58, 0.05, 0.05, C.hi))
end

-- ---------------------------------------------------------------- spiders, ticks and things with hard shells

--- Eight legs and a body side-on, lit by whatever's on its back.
local function spiderOf(o)
  local ink, leg = o.ink, o.leg or o.ink
  local list = {}
  for i = 0, 3 do
    local x = 0.12 + i * 0.1
    list[#list + 1] = P(leg, 0.4, 0.56, x, 0.26 - i * 0.02, x - 0.1, 1, x - 0.06, 1, x + 0.04, 0.36 - i * 0.02, 0.42, 0.64)
    list[#list + 1] = P(leg, 0.56, 0.56, 0.62 + i * 0.09, 0.26 + (3 - i) * 0.01, 0.7 + i * 0.1, 1, 0.74 + i * 0.1, 1, 0.68 + i * 0.09, 0.36, 0.56, 0.64)
  end
  return join(list, E(0.34, 0.58, 0.28, 0.24, ink), E(0.7, 0.62, 0.16, 0.16, ink), E(0.8, 0.6, 0.025, 0.025, o.eye or C.red), E(0.84, 0.64, 0.025, 0.025, o.eye or C.red), E(0.76, 0.56, 0.018, 0.018, o.eye or C.red),
    P(C.text, 0.82, 0.74, 0.86, 0.74, 0.84, 0.84), o.over)
end
F.ud_spider = function()
  local list = spiderOf({ ink = C.panel, leg = C.tie })
  for _, s in ipairs({ { 0.34, 0.42 }, { 0.3, 0.42 }, { 0.38, 0.42 }, { 0.32, 0.47 }, { 0.36, 0.47 }, { 0.34, 0.52 }, { 0.32, 0.57 }, { 0.36, 0.57 }, { 0.3, 0.62 }, { 0.34, 0.62 }, { 0.38, 0.62 } }) do list[#list + 1] = E(s[1], s[2], 0.018, 0.018, C.red) end
  return list
end
F.ud_phase = function()
  -- two halves of one spider, a step apart, and nothing at all between them
  local list = {}
  for i = 0, 3 do
    local x = 0.06 + i * 0.09
    list[#list + 1] = P(C.info, 0.34, 0.6, x, 0.3 - i * 0.02, x - 0.06, 1, x - 0.02, 1, x + 0.05, 0.4, 0.34, 0.68)
    list[#list + 1] = P(C.blue, 0.66, 0.48, 0.66 + i * 0.09, 0.16 + i * 0.02, 0.72 + i * 0.09, 0.88, 0.76 + i * 0.09, 0.88, 0.7 + i * 0.09, 0.28, 0.66, 0.56)
  end
  return join(list, P(C.text, 0.42, 0.34, 0.3, 0.36, 0.16, 0.48, 0.12, 0.6, 0.18, 0.74, 0.3, 0.82, 0.42, 0.84), P(C.info, 0.42, 0.42, 0.3, 0.44, 0.22, 0.56, 0.3, 0.7, 0.42, 0.74),
    P(C.text, 0.58, 0.22, 0.7, 0.24, 0.84, 0.36, 0.88, 0.48, 0.82, 0.62, 0.7, 0.7, 0.58, 0.72), P(C.info, 0.58, 0.3, 0.68, 0.34, 0.76, 0.46, 0.68, 0.58, 0.58, 0.62),
    E(0.72, 0.4, 0.02, 0.02, C.bg), E(0.78, 0.46, 0.02, 0.02, C.bg))
end
F.sn_cask_louse = function()
  local list = {}
  for i = 0, 3 do
    list[#list + 1] = P(C.tie, 0.6 + i * 0.03, 0.74, 0.74 + i * 0.08, 0.7, 0.84 + i * 0.05, 1, 0.8 + i * 0.05, 1, 0.72 + i * 0.07, 0.78, 0.6, 0.82)
    list[#list + 1] = P(C.tie, 0.4 - i * 0.03, 0.8, 0.26 - i * 0.06, 0.76, 0.16 - i * 0.04, 1, 0.2 - i * 0.04, 1, 0.3 - i * 0.05, 0.84, 0.4, 0.86)
  end
  return join(list, E(0.46, 0.62, 0.38, 0.32, C.text), E(0.42, 0.68, 0.24, 0.17, C.redTint), E(0.36, 0.7, 0.12, 0.08, C.red), E(0.86, 0.72, 0.1, 0.09, C.line), E(0.9, 0.7, 0.02, 0.02, C.bg), P(C.tie, 0.94, 0.76, 1, 0.8, 0.94, 0.82), E(0.3, 0.46, 0.08, 0.03, C.text))
end

local function driderOf(o)
  local list = {}
  for i = 0, 3 do
    local knee, y = 0.08 + i * 0.1, 0.44 + i * 0.03
    list[#list + 1] = P(i % 2 == 0 and o.dark or o.ink, 0.34 + i * 0.03, 0.66, knee, y, knee - 0.08, 1, knee - 0.03, 1, knee + 0.04, y + 0.08, 0.36 + i * 0.03, 0.74)
    list[#list + 1] = P(i % 2 == 1 and o.dark or o.ink, 0.56 + i * 0.03, 0.66, 0.56 + i * 0.13, y - 0.04, 0.68 + i * 0.1, 1, 0.64 + i * 0.1, 1, 0.53 + i * 0.13, y + 0.04, 0.54 + i * 0.03, 0.74)
  end
  return join(list, E(0.28, 0.68, 0.26, 0.2, o.ink), E(0.26, 0.64, 0.17, 0.1, o.dark), E(0.54, 0.66, 0.15, 0.13, o.ink), o.legs,
    P(o.coat, 0.46, 0.3, 0.68, 0.3, 0.64, 0.58, 0.46, 0.6), o.chest,
    E(0.58, 0.17, 0.12, 0.14, C.blueTint), P(C.blueTint, 0.68, 0.16, 0.78, 0.1, 0.69, 0.22), o.hair or P(C.text, 0.42, 0.34, 0.44, 0.1, 0.56, 0.0, 0.7, 0.05, 0.7, 0.14, 0.56, 0.1, 0.52, 0.36), o.face or R(0.6, 0.15, 0.05, 0.03, C.red),
    R(0.66, 0.36, 0.2, 0.05, o.coat), o.over)
end
F.ud_ruaryn = function()
  return driderOf({ ink = C.line, dark = C.tie, coat = C.tie,
    chest = { P(C.line, 0.46, 0.32, 0.68, 0.32, 0.66, 0.5, 0.48, 0.54), R(0.56, 0.3, 0.012, 0.3, C.bg) },
    face = { R(0.6, 0.15, 0.05, 0.03, C.red), P(C.bg, 0.56, 0.22, 0.62, 0.25, 0.68, 0.21, 0.68, 0.23, 0.62, 0.27, 0.56, 0.24) },
    over = { R(0.56, 0.3, 0.012, 0.16, C.warn), E(0.562, 0.49, 0.022, 0.03, C.hi), R(0.556, 0.44, 0.012, 0.03, C.hi), R(0.85, 0.3, 0.04, 0.2, C.line) } })
end
F.ud_unsettled = function()
  local list = driderOf({ ink = C.tie, dark = C.panel, coat = C.panel,
    hair = P(C.text, 0.4, 0.4, 0.38, 0.1, 0.46, 0.14, 0.44, -0.0, 0.56, 0.06, 0.6, -0.02, 0.72, 0.06, 0.66, 0.12, 0.56, 0.1, 0.52, 0.4),
    face = { E(0.6, 0.16, 0.035, 0.035, C.text), E(0.61, 0.16, 0.014, 0.014, C.bg), R(0.56, 0.23, 0.08, 0.016, C.bg) } })
  for i = 0, 3 do
    list[#list + 1] = R(0.03 + i * 0.1, 0.62 + i * 0.03, 0.08, 0.04, C.text)
    list[#list + 1] = R(0.7 + i * 0.09, 0.56 + i * 0.03, 0.08, 0.04, C.text)
  end
  return list
end
F.ud_matron = function()
  local rider = man({ wide = 0.13, hem = 0.7, skin = C.blueTint, coat = C.accent, trim = C.bg, eye = C.red, hair = C.text,
    over = { R(0.84, 0.46, 0.02, 0.04, C.redTint), snake(C.ok, 0.85, 0.48, 1, 0.62, 0.02, 0.01, 0.03, 2), snake(C.red, 0.85, 0.48, 0.96, 0.72, 0.02, 0.01, 0.03, 2), snake(C.text, 0.85, 0.48, 0.9, 0.8, 0.02, 0.01, 0.03, 2) } })
  for i = 0, 4 do rider[#rider + 1] = P(C.bg, 0.4 + i * 0.07, 0.07, 0.42 + i * 0.07, 0.07, 0.36 + i * 0.09, -0.08 - (i % 2) * 0.03, 0.34 + i * 0.09, -0.06) end
  return join(fit(spiderOf({ ink = C.tie, leg = C.line }), 1, 0.62), fit(rider, 0.74, 0.74, -0.14, -0.28))
end
F.ud_ettercap = function()
  return { E(0.26, 0.56, 0.24, 0.26, C.tie), E(0.22, 0.5, 0.13, 0.13, C.line), E(0.2, 0.46, 0.04, 0.04, C.red), E(0.28, 0.54, 0.03, 0.03, C.red),
    R(0.34, 0.74, 0.1, 0.24, C.ok), R(0.54, 0.74, 0.1, 0.24, C.ok), P(C.line, 0.3, 0.96, 0.46, 0.96, 0.5, 1, 0.28, 1), P(C.line, 0.52, 0.96, 0.66, 0.96, 0.72, 1, 0.5, 1),
    E(0.54, 0.56, 0.22, 0.26, C.ok), E(0.6, 0.6, 0.12, 0.17, C.soft), E(0.7, 0.28, 0.17, 0.15, C.ok), E(0.74, 0.22, 0.04, 0.04, C.red), E(0.84, 0.24, 0.03, 0.03, C.red), E(0.66, 0.2, 0.02, 0.02, C.red),
    P(C.text, 0.74, 0.36, 0.8, 0.36, 0.72, 0.52), P(C.text, 0.82, 0.36, 0.88, 0.36, 0.88, 0.52), R(0.68, 0.46, 0.24, 0.07, C.ok), P(C.line, 0.9, 0.44, 0.93, 0.44, 0.96, 0.8, 0.94, 0.8), P(C.text, 0.84, 0.56, 0.99, 0.56, 1, 0.98, 0.88, 0.98) }
end
F.ud_hookhorror = function()
  return { R(0.34, 0.74, 0.1, 0.24, C.panel), R(0.54, 0.74, 0.1, 0.24, C.panel), P(C.tie, 0.3, 0.96, 0.46, 0.96, 0.46, 1, 0.3, 1), P(C.tie, 0.5, 0.96, 0.68, 0.96, 0.68, 1, 0.5, 1),
    E(0.46, 0.54, 0.26, 0.28, C.tie), E(0.4, 0.5, 0.16, 0.2, C.panel), R(0.22, 0.52, 0.5, 0.02, C.bg), R(0.24, 0.62, 0.46, 0.02, C.bg),
    snake(C.tie, 0.52, 0.32, 0.66, 0.22, 0.14, 0.12, 0.02, 1), E(0.68, 0.2, 0.13, 0.12, C.tie), P(C.tie, 0.5, 0.1, 0.44, 0.0, 0.62, 0.1), P(C.hi, 0.76, 0.14, 0.98, 0.3, 0.82, 0.3), R(0.68, 0.16, 0.05, 0.04, C.red),
    R(0.1, 0.36, 0.24, 0.07, C.tie), P(C.line, 0.1, 0.38, 0.02, 0.5, 0.08, 0.66, 0.2, 0.7, 0.08, 0.6, 0.06, 0.5, 0.14, 0.42),
    R(0.66, 0.42, 0.2, 0.07, C.tie), P(C.line, 0.86, 0.42, 0.98, 0.5, 0.96, 0.7, 0.84, 0.8, 0.9, 0.66, 0.9, 0.54, 0.82, 0.48) }
end
F.ud_umber = function()
  return { R(0.14, 0.74, 0.2, 0.26, C.redTint), R(0.54, 0.74, 0.2, 0.26, C.redTint), P(C.tie, 0.12, 0.96, 0.36, 0.96, 0.36, 1, 0.12, 1), P(C.tie, 0.52, 0.96, 0.76, 0.96, 0.76, 1, 0.52, 1),
    E(0.42, 0.52, 0.38, 0.34, C.redTint), E(0.36, 0.48, 0.24, 0.24, C.tie), R(0.1, 0.46, 0.64, 0.015, C.bg), R(0.12, 0.58, 0.6, 0.015, C.bg), R(0.42, 0.2, 0.012, 0.6, C.bg), E(0.26, 0.34, 0.12, 0.08, C.line),
    E(0.72, 0.3, 0.2, 0.2, C.tie), E(0.62, 0.22, 0.03, 0.03, C.hi), E(0.7, 0.19, 0.035, 0.035, C.hi), E(0.79, 0.2, 0.035, 0.035, C.hi), E(0.86, 0.24, 0.03, 0.03, C.hi),
    P(C.line, 0.68, 0.36, 0.98, 0.34, 0.86, 0.46, 0.92, 0.48, 0.7, 0.48), P(C.text, 0.68, 0.46, 0.98, 0.56, 0.96, 0.62, 0.68, 0.54), R(0.7, 0.46, 0.2, 0.012, C.bg),
    R(0.7, 0.54, 0.2, 0.09, C.redTint), P(C.line, 0.88, 0.54, 1, 0.62, 0.9, 0.64) }
end
F.hr_crab = function()
  local list = {}
  for i = 0, 3 do
    list[#list + 1] = P(C.redTint, 0.26 + i * 0.03, 0.66, 0.14 - i * 0.03 + 0.06, 0.62 + i * 0.02, 0.06 + i * 0.04, 1, 0.1 + i * 0.04, 1, 0.22, 0.72)
    list[#list + 1] = P(C.redTint, 0.62 - i * 0.03, 0.68, 0.76 + i * 0.02, 0.66 + i * 0.02, 0.72 + i * 0.05, 1, 0.76 + i * 0.05, 1, 0.68, 0.76)
  end
  return join(list, E(0.46, 0.64, 0.32, 0.2, C.red), E(0.42, 0.58, 0.22, 0.09, C.warn), E(0.3, 0.56, 0.03, 0.02, C.text), E(0.5, 0.52, 0.03, 0.02, C.text), E(0.6, 0.62, 0.02, 0.02, C.text),
    R(0.52, 0.36, 0.02, 0.14, C.redTint), R(0.62, 0.38, 0.02, 0.14, C.redTint), E(0.53, 0.35, 0.03, 0.03, C.bg), E(0.63, 0.37, 0.03, 0.03, C.bg),
    R(0.7, 0.56, 0.14, 0.07, C.red), E(0.88, 0.42, 0.13, 0.2, C.red), P(C.bg, 0.86, 0.34, 1, 0.3, 1, 0.42, 0.88, 0.44), R(0.08, 0.5, 0.12, 0.05, C.red), E(0.08, 0.46, 0.06, 0.07, C.red))
end

--- A snapping turtle, side on. shell and coin are the two colours of the back.
local function turtle(o)
  local list = { R(0.14, 0.76, 0.16, 0.24, o.skin), R(0.56, 0.76, 0.16, 0.24, o.skin), P(o.skin, 0.1, 0.72, 0.0, 0.84, 0.14, 0.82), E(0.42, 0.56, 0.42, o.tall or 0.3, o.shell), E(0.42, 0.78, 0.4, 0.07, o.skin) }
  for i = 0, 11 do list[#list + 1] = E(0.12 + (i * 37 % 60) / 100, 0.36 + (i * 23 % 34) / 100, 0.05, 0.035, i % 3 == 0 and C.hi or o.coin) end
  return join(list, snake(o.skin, 0.76, 0.66, 0.92, 0.56, 0.2, 0.17, 0.02, 1), E(0.9, 0.54, 0.1, 0.1, o.skin), P(C.line, 0.92, 0.56, 1, 0.6, 0.92, 0.64), R(0.84, 0.59, 0.14, 0.012, C.bg), o.over)
end
F.hr_snapper = function() return fit(turtle({ skin = C.tie, shell = C.hiTint, coin = C.ok }), 1, 0.7) end
F.hr_dividend = function()
  return turtle({ skin = C.line, shell = C.hiTint, coin = C.ok, tall = 0.46,
    over = { R(0.82, 0.5, 0.11, 0.015, C.bg), E(0.9, 0.5, 0.025, 0.012, C.soft), R(0.8, 0.66, 0.16, 0.22, C.tie), R(0.8, 0.72, 0.16, 0.015, C.bg), R(0.8, 0.82, 0.16, 0.015, C.bg), E(0.1, 0.2, 0.0, 0.0, C.bg) } })
end
F.hr_grassback = function()
  local list = { R(0.14, 0.8, 0.14, 0.2, C.hiTint), R(0.6, 0.8, 0.14, 0.2, C.hiTint), E(0.46, 0.76, 0.46, 0.18, C.hiTint), E(0.88, 0.8, 0.12, 0.1, C.tie), R(0.82, 0.84, 0.18, 0.015, C.bg), E(0.9, 0.76, 0.015, 0.015, C.hi), P(C.text, 0.92, 0.85, 0.95, 0.85, 0.935, 0.9) }
  for i = 0, 14 do
    local x, high = 0.06 + i * 0.058, 0.6 - abs(i - 7) * 0.035 - (i * 7 % 5) * 0.03
    list[#list + 1] = P(i % 3 == 0 and C.soft or C.ok, x, 0.74, x + 0.05, 0.74, x + 0.04 + (i % 2) * 0.03, 0.72 - high)
  end
  return list
end
F.px_tusker = function()
  return { R(0.14, 0.72, 0.13, 0.28, C.panel), R(0.56, 0.72, 0.13, 0.28, C.panel), R(0.28, 0.74, 0.1, 0.26, C.tie), R(0.66, 0.74, 0.1, 0.26, C.tie), P(C.tie, 0.0, 0.3, 0.1, 0.36, 0.06, 0.5),
    E(0.4, 0.54, 0.36, 0.26, C.tie), E(0.36, 0.48, 0.26, 0.14, C.panel), P(C.line, 0.14, 0.32, 0.2, 0.2, 0.26, 0.3, 0.32, 0.18, 0.38, 0.28, 0.44, 0.18, 0.5, 0.28, 0.56, 0.2, 0.6, 0.34),
    E(0.72, 0.56, 0.2, 0.19, C.tie), P(C.tie, 0.8, 0.44, 1, 0.56, 1, 0.72, 0.8, 0.74), P(C.line, 0.62, 0.42, 0.66, 0.28, 0.72, 0.4), E(0.78, 0.5, 0.025, 0.025, C.red),
    P(C.text, 0.9, 0.68, 0.94, 0.68, 0.84, 0.36, 0.8, 0.4), P(C.text, 0.8, 0.7, 0.84, 0.7, 0.72, 0.5, 0.7, 0.54), P(C.line, 0.98, 0.7, 1, 0.68, 0.96, 0.44, 0.92, 0.46), P(C.text, 0.72, 0.72, 0.76, 0.72, 0.66, 0.62, 0.64, 0.66) }
end
F.wm_exhibit = function()
  return { R(0.14, 0.68, 0.1, 0.32, C.warn), R(0.3, 0.72, 0.08, 0.28, C.tie), R(0.58, 0.68, 0.12, 0.32, C.redTint), R(0.72, 0.74, 0.07, 0.26, C.warn),
    P(C.warn, 0.0, 0.2, 0.12, 0.3, 0.08, 0.5), P(C.tie, 0.08, 0.34, 0.5, 0.26, 0.54, 0.76, 0.1, 0.76), P(C.redTint, 0.46, 0.28, 0.84, 0.34, 0.8, 0.76, 0.48, 0.76),
    R(0.5, 0.28, 0.012, 0.5, C.text), R(0.47, 0.34, 0.07, 0.01, C.text), R(0.47, 0.44, 0.07, 0.01, C.text), R(0.47, 0.54, 0.07, 0.01, C.text), R(0.47, 0.64, 0.07, 0.01, C.text),
    E(0.84, 0.28, 0.14, 0.14, C.hi), P(C.hi, 0.74, 0.2, 0.7, 0.04, 0.82, 0.16), P(C.warn, 0.92, 0.26, 1, 0.34, 0.9, 0.36), E(0.8, 0.26, 0.04, 0.04, C.text), E(0.8, 0.26, 0.018, 0.018, C.bg), E(0.9, 0.22, 0.03, 0.03, C.info), E(0.9, 0.22, 0.014, 0.014, C.bg),
    R(0.68, 0.1, 0.1, 0.05, C.hi), R(0.72, 0.1, 0.012, 0.08, C.line) }
end

-- ---------------------------------------------------------------- what's made of something else

F.hr_mite = function()
  local list = {}
  for i = 0, 7 do
    local x = 0.1 + i * 0.1
    list[#list + 1] = E(x, 0.76 - i * 0.004, 0.08, 0.13 - abs(i - 3) * 0.013, i % 2 == 0 and C.line or C.text)
    list[#list + 1] = P(C.tie, x - 0.01, 0.84, x + 0.01, 0.84, x - 0.03, 1, x - 0.05, 1)
  end
  return join(list, P(C.line, 0.0, 0.76, 0.06, 0.72, 0.06, 0.8), P(C.tie, 0.86, 0.72, 0.9, 0.7, 1, 0.34, 0.98, 0.32), P(C.tie, 0.88, 0.74, 0.92, 0.72, 0.92, 0.3, 0.88, 0.3), E(0.84, 0.72, 0.02, 0.02, C.bg),
    R(0.2, 0.92, 0.06, 0.05, C.text), R(0.48, 0.94, 0.05, 0.04, C.text), R(0.68, 0.9, 0.05, 0.05, C.text))
end
F.hr_ink = function()
  local list = { P(C.blueTint, 0.27, 0.98, 0.22, 0.5, 0.29, 0.28, 0.38, 0.05, 0.62, 0.03, 0.71, 0.26, 0.8, 0.44, 0.9, 0.54, 0.8, 0.62, 0.76, 0.98, 0.9, 1, 0.08, 1), P(C.bg, 0.3, 0.98, 0.26, 0.5, 0.32, 0.3, 0.4, 0.08, 0.6, 0.06, 0.68, 0.28, 0.76, 0.46, 0.84, 0.54, 0.76, 0.6, 0.72, 0.98, 0.84, 1, 0.14, 1), E(0.5, 0.97, 0.42, 0.04, C.bg), E(0.14, 0.92, 0.04, 0.03, C.bg), E(0.9, 0.95, 0.03, 0.02, C.bg) }
  for i = 0, 11 do list[#list + 1] = R(0.34 + (i * 29 % 30) / 100, 0.3 + i * 0.05, 0.04 + (i % 3) * 0.03, 0.012, i % 4 == 0 and C.blue or C.text) end
  return join(list, E(0.56, 0.2, 0.015, 0.02, C.text), R(0.42, 0.15, 0.1, 0.012, C.text), R(0.46, 0.22, 0.06, 0.012, C.blue))
end
F.em_wool = function()
  local list = { R(0.26, 0.76, 0.07, 0.24, C.tie), R(0.44, 0.78, 0.07, 0.22, C.line), R(0.66, 0.76, 0.07, 0.24, C.tie) }
  for _, c in ipairs({ { 0.5, 0.58, 0.42, 0.26 }, { 0.2, 0.5, 0.15, 0.13 }, { 0.42, 0.38, 0.18, 0.15 }, { 0.66, 0.4, 0.17, 0.15 }, { 0.82, 0.52, 0.14, 0.13 }, { 0.3, 0.72, 0.14, 0.1 }, { 0.72, 0.72, 0.14, 0.1 } }) do list[#list + 1] = E(c[1], c[2], c[3] + 0.02, c[4] + 0.02, C.soft) end
  for _, c in ipairs({ { 0.5, 0.58, 0.42, 0.26 }, { 0.2, 0.5, 0.15, 0.13 }, { 0.42, 0.38, 0.18, 0.15 }, { 0.66, 0.4, 0.17, 0.15 }, { 0.82, 0.52, 0.14, 0.13 }, { 0.3, 0.72, 0.14, 0.1 }, { 0.72, 0.72, 0.14, 0.1 } }) do list[#list + 1] = E(c[1], c[2], c[3], c[4], C.line) end
  return join(list, E(0.46, 0.5, 0.18, 0.1, C.tie), E(0.68, 0.6, 0.13, 0.07, C.tie))
end
F.px_hulk = function()
  local list = { R(0.26, 0.7, 0.18, 0.3, C.panel), R(0.54, 0.7, 0.18, 0.3, C.panel), P(C.panel, 0.16, 0.34, 0.8, 0.34, 0.84, 0.8, 0.14, 0.82), E(0.48, 0.3, 0.36, 0.2, C.panel), E(0.32, 0.5, 0.1, 0.08, C.tie), E(0.6, 0.6, 0.12, 0.09, C.tie),
    E(0.52, 0.14, 0.13, 0.11, C.line), P(C.tie, 0.38, 0.14, 0.66, 0.14, 0.72, 0.2, 0.32, 0.2), R(0.5, 0.15, 0.1, 0.03, C.bg), E(0.26, 0.28, 0.08, 0.06, C.tie), R(0.2, 0.3, 0.16, 0.015, C.bg), E(0.7, 0.34, 0.09, 0.06, C.line), R(0.62, 0.36, 0.18, 0.015, C.bg), E(0.44, 0.7, 0.07, 0.05, C.tie),
    E(0.04, 0.66, 0.0, 0.0, C.bg) }
  return join(list, R(0.04, 0.4, 0.16, 0.34, C.panel), worm({ ink = C.line, ring = C.tie, mouth = true, x1 = 0.76, y1 = 0.48, x2 = 0.9, y2 = 0.3, wide1 = 0.14, wide2 = 0.18, bend = 0.03, rings = 3, mouthW = 0.09, mouthH = 0.11, teeth = 5 }))
end
F.ud_husk = function()
  return { R(0.32, 0.7, 0.13, 0.3, C.redTint), R(0.54, 0.7, 0.13, 0.3, C.redTint), P(C.tie, 0.28, 0.94, 0.46, 0.94, 0.48, 1, 0.26, 1), P(C.tie, 0.52, 0.94, 0.7, 0.94, 0.74, 1, 0.5, 1),
    P(C.redTint, 0.22, 0.32, 0.78, 0.32, 0.7, 0.76, 0.3, 0.76), P(C.tie, 0.28, 0.34, 0.72, 0.34, 0.66, 0.56, 0.5, 0.62, 0.34, 0.56), R(0.3, 0.42, 0.4, 0.02, C.redTint), R(0.32, 0.5, 0.36, 0.02, C.redTint), R(0.34, 0.66, 0.34, 0.03, C.line),
    E(0.22, 0.34, 0.1, 0.08, C.tie), E(0.78, 0.34, 0.1, 0.08, C.tie), P(C.line, 0.14, 0.32, 0.18, 0.16, 0.24, 0.28), R(0.14, 0.38, 0.09, 0.3, C.redTint), P(C.line, 0.14, 0.68, 0.2, 0.68, 0.17, 0.78),
    E(0.54, 0.2, 0.14, 0.15, C.redTint), P(C.line, 0.44, 0.1, 0.3, 0.0, 0.32, -0.08, 0.5, 0.05), P(C.line, 0.62, 0.1, 0.72, 0.04, 0.66, 0.14), R(0.58, 0.16, 0.06, 0.05, C.bg), E(0.61, 0.185, 0.012, 0.012, C.red), R(0.5, 0.26, 0.14, 0.03, C.bg), R(0.52, 0.26, 0.012, 0.03, C.line), R(0.57, 0.26, 0.012, 0.03, C.line), R(0.62, 0.26, 0.012, 0.03, C.line),
    R(0.76, 0.44, 0.12, 0.07, C.redTint), P(C.line, 0.86, 0.5, 0.92, 0.46, 0.99, 0.08, 0.95, 0.04) }
end
F.ud_cinder = function()
  return fit({ P(C.tie, 0.3, 0.1, 0.36, -0.1, 0.3, -0.2, 0.42, -0.1, 0.4, 0.1), R(0.3, 0.7, 0.14, 0.3, C.red), R(0.54, 0.7, 0.14, 0.3, C.red), E(0.5, 0.56, 0.26, 0.24, C.redTint), E(0.44, 0.52, 0.1, 0.1, C.red), E(0.6, 0.62, 0.08, 0.07, C.warn), R(0.3, 0.5, 0.4, 0.02, C.warn), P(C.hi, 0.36, 0.44, 0.5, 0.56, 0.42, 0.6, 0.54, 0.72, 0.58, 0.72, 0.5, 0.56, 0.6, 0.5),
    E(0.54, 0.24, 0.16, 0.14, C.redTint), R(0.56, 0.2, 0.06, 0.04, C.hi), P(C.warn, 0.44, 0.26, 0.66, 0.24, 0.62, 0.3), P(C.tie, 0.36, 0.14, 0.72, 0.14, 0.64, 0.02, 0.44, 0.02), E(0.54, 0.05, 0.03, 0.03, C.hi),
    R(0.2, 0.42, 0.1, 0.28, C.redTint), R(0.7, 0.42, 0.14, 0.1, C.redTint), E(0.84, 0.45, 0.05, 0.05, C.warn), R(0.1, 0.0, 0.05, 0.05, C.tie), R(0.2, -0.08, 0.04, 0.05, C.tie) }, 0.82, 0.82)
end
F.ud_myconid = function()
  local list = { R(0.32, 0.76, 0.14, 0.24, C.line), R(0.54, 0.76, 0.14, 0.24, C.line), P(C.text, 0.34, 0.4, 0.66, 0.4, 0.72, 0.8, 0.28, 0.8), R(0.2, 0.46, 0.14, 0.32, C.line), R(0.66, 0.46, 0.14, 0.32, C.line), P(C.accent, 0.5, 0.06, 0.92, 0.3, 0.96, 0.5, 0.04, 0.5, 0.08, 0.3), P(C.blueTint, 0.04, 0.5, 0.96, 0.5, 0.86, 0.44, 0.14, 0.44), P(C.tie, 0.14, 0.5, 0.86, 0.5, 0.82, 0.56, 0.18, 0.56),
    E(0.32, 0.3, 0.05, 0.04, C.text), E(0.54, 0.2, 0.06, 0.05, C.text), E(0.72, 0.34, 0.04, 0.03, C.text), R(0.42, 0.62, 0.05, 0.015, C.bg), R(0.54, 0.62, 0.05, 0.015, C.bg), P(C.bg, 0.45, 0.7, 0.56, 0.7, 0.5, 0.73) }
  for i = 0, 9 do list[#list + 1] = E(0.06 + i * 0.1, 0.02 + (i * 7 % 4) * 0.03, 0.012, 0.012, C.soft) end
  return list
end
F.ud_mantle = function()
  local list = { R(0, 0, 1, 0.08, C.tie), R(0, 0.08, 1, 0.012, C.line) }
  for i = 0, 5 do list[#list + 1] = snake(i % 2 == 0 and C.line or C.tie, 0.3 + i * 0.08, 0.34, 0.08 + i * 0.17, 0.72 + (i % 2) * 0.16, 0.08, 0.015, 0.05, 2, i) end
  return join(list, P(C.panel, 0.5, 0.04, 0.96, 0.36, 0.86, 0.52, 0.72, 0.4, 0.6, 0.56, 0.5, 0.42, 0.38, 0.56, 0.26, 0.4, 0.12, 0.52, 0.04, 0.36), P(C.tie, 0.5, 0.1, 0.8, 0.32, 0.5, 0.34, 0.2, 0.32), E(0.4, 0.26, 0.03, 0.02, C.red), E(0.6, 0.26, 0.03, 0.02, C.red))
end
F.ud_manta = function()
  return { P(C.line, 0.0, 0.2, 0.22, 0.32, 0.5, 0.26, 0.72, 0.42, 0.96, 0.46, 0.8, 0.5, 0.56, 0.7, 0.4, 0.74, 0.2, 0.56), P(C.text, 0.24, 0.4, 0.5, 0.36, 0.7, 0.46, 0.5, 0.62, 0.34, 0.6), P(C.tie, 0.42, 0.72, 0.22, 0.92, 0.06, 0.98, 0.0, 0.94, 0.2, 0.88, 0.34, 0.72), P(C.red, 0.0, 0.94, 0.1, 0.96, 0.02, 1),
    E(0.82, 0.44, 0.02, 0.03, C.bg), P(C.line, 0.84, 0.46, 1, 0.42, 0.9, 0.5), P(C.line, 0.8, 0.5, 0.98, 0.6, 0.84, 0.56), R(0.42, 0.46, 0.08, 0.012, C.tie), R(0.44, 0.5, 0.06, 0.012, C.tie) }
end
F.ud_grudge = function()
  local list = { R(0.14, 0.82, 0.72, 0.18, C.bg), E(0.26, 0.92, 0.1, 0.08, C.panel), E(0.5, 0.92, 0.1, 0.08, C.panel), E(0.74, 0.92, 0.1, 0.08, C.panel),
    P(C.panel, 0.16, 0.02, 0.84, 0.02, 0.9, 0.84, 0.1, 0.84), P(C.tie, 0.16, 0.02, 0.5, 0.02, 0.46, 0.84, 0.1, 0.84), R(0.1, 0.1, 0.8, 0.02, C.bg), R(0.09, 0.74, 0.82, 0.02, C.bg) }
  for row = 0, 11 do
    for col = 0, 6 do
      if (row * 3 + col * 5) % 4 ~= 0 and not (row > 3 and row < 7 and col > 0 and col < 6) then list[#list + 1] = R(0.16 + col * 0.1, 0.14 + row * 0.05, 0.07, 0.012, C.line) end
    end
  end
  return join(list, R(0.24, 0.32, 0.52, 0.14, C.bg), R(0.26, 0.36, 0.48, 0.05, C.red), R(0.26, 0.34, 0.48, 0.012, C.warn), E(0.3, 0.2, 0.05, 0.05, C.red), E(0.7, 0.2, 0.05, 0.05, C.red), R(0.88, 0.2, 0.1, 0.04, C.tie), E(0.98, 0.22, 0.03, 0.05, C.line))
end
F.em_kess = function()
  local list = { E(0.2, 0.34, 0.2, 0.32, C.hi), E(0.2, 0.34, 0.16, 0.28, C.info), E(0.15, 0.26, 0.05, 0.08, C.text), P(C.text, 0.34, 0.26, 0.98, 0.1, 0.98, 0.16, 0.34, 0.4),
    R(0.58, 0.14, 0.04, 0.03, C.text), R(0.74, 0.08, 0.04, 0.03, C.text), R(0.88, 0.18, 0.04, 0.03, C.text),
    R(0.42, 0.0, 0.34, 0.1, C.redTint), R(0.42, 0.0, 0.08, 0.98, C.redTint), R(0.68, 0.0, 0.08, 0.98, C.redTint), R(0.42, 0.56, 0.5, 0.1, C.redTint), R(0.42, 0.54, 0.5, 0.03, C.warn), R(0.84, 0.64, 0.08, 0.36, C.redTint),
    P(C.accent, 0.5, 0.3, 0.72, 0.3, 0.76, 0.56, 0.46, 0.56), R(0.56, 0.3, 0.08, 0.26, C.hi), R(0.6, 0.54, 0.26, 0.09, C.accent), R(0.72, 0.6, 0.1, 0.34, C.accent), R(0.7, 0.92, 0.16, 0.06, C.bg),
    E(0.6, 0.18, 0.11, 0.12, C.warn), R(0.56, 0.1, 0.1, 0.02, C.bg), E(0.64, 0.17, 0.03, 0.03, C.text), E(0.645, 0.17, 0.012, 0.012, C.bg), E(0.55, 0.17, 0.025, 0.03, C.text), R(0.58, 0.24, 0.06, 0.02, C.bg),
    P(C.info, 0.54, 0.34, 0.66, 0.34, 0.68, 0.24, 0.62, 0.26, 0.58, 0.22), P(C.text, 0.58, 0.32, 0.6, 0.26, 0.62, 0.32) }
  return list
end
F.em_breath = function()
  local list = {}
  for i = 0, 7 do list[#list + 1] = R(i * 0.14, 0, 0.14, 1, i % 2 == 0 and C.tie or C.panel) end
  for i = 0, 5 do
    list[#list + 1] = R(0, i * 0.17 + 0.04, 1, 0.012, C.bg)
  end
  list = join(list, E(0.5, 0.56, 0.5, 0.46, C.text), E(0.5, 0.58, 0.44, 0.4, C.line))
  for i = 0, 4 do
    local y = 0.26 + i * 0.13
    list[#list + 1] = P(C.text, 0.06 + i * 0.03, y, 0.46, y - 0.08, 0.46, y - 0.02, 0.12 + i * 0.03, y + 0.05)
    list[#list + 1] = P(C.text, 0.94 - i * 0.03, y, 0.54, y - 0.08, 0.54, y - 0.02, 0.88 - i * 0.03, y + 0.05)
    list[#list + 1] = R(0.1 + i * 0.04, y + 0.05, 0.8 - i * 0.08, 0.02, C.tie)
  end
  return join(list, E(0.26, 0.74, 0.1, 0.08, C.tie), R(0.17, 0.74, 0.18, 0.02, C.panel), E(0.26, 0.72, 0.07, 0.04, C.bg), E(0.72, 0.46, 0.08, 0.06, C.tie), E(0.74, 0.46, 0.05, 0.03, C.bg), P(C.tie, 0.6, 0.72, 0.8, 0.8, 0.7, 0.86), E(0.66, 0.78, 0.02, 0.02, C.red), R(0.46, 0.2, 0.08, 0.76, C.tie))
end
F.sn_lurker = function()
  -- flat on its ledge, knees above its back: you'd take it for a piece of the rock until it isn't
  local list = { R(0, 0.84, 1, 0.16, C.tie), R(0, 0.84, 1, 0.02, C.line) }
  for i = 0, 2 do
    local x = 0.18 + i * 0.22
    list[#list + 1] = P(C.line, x, 0.76, x + 0.04, 0.44, x + 0.1, 0.46, x + 0.09, 0.84, x + 0.04, 0.84)
    list[#list + 1] = P(C.line, x + 0.04, 0.44, x + 0.1, 0.46, x + 0.2, 0.74, x + 0.16, 0.76)
  end
  return join(list, E(0.46, 0.76, 0.42, 0.09, C.tie), E(0.4, 0.74, 0.16, 0.04, C.line), E(0.66, 0.77, 0.1, 0.03, C.panel), E(0.88, 0.74, 0.1, 0.07, C.tie), E(0.92, 0.72, 0.015, 0.015, C.red), E(0.87, 0.71, 0.015, 0.015, C.red), R(0.86, 0.78, 0.13, 0.012, C.bg))
end
F.vt_nothic = function()
  return fit({ R(0.34, 0.74, 0.08, 0.22, C.line), R(0.54, 0.74, 0.08, 0.22, C.line), P(C.line, 0.3, 0.94, 0.44, 0.94, 0.46, 1, 0.28, 1), P(C.line, 0.5, 0.94, 0.64, 0.94, 0.68, 1, 0.48, 1),
    P(C.tie, 0.22, 0.76, 0.28, 0.36, 0.56, 0.34, 0.7, 0.76), R(0.18, 0.42, 0.07, 0.42, C.tie), P(C.text, 0.12, 0.84, 0.28, 0.84, 0.32, 0.98, 0.26, 0.9, 0.22, 0.98, 0.18, 0.9, 0.12, 0.98),
    E(0.58, 0.28, 0.27, 0.25, C.line), E(0.6, 0.27, 0.21, 0.19, C.bg), E(0.6, 0.27, 0.19, 0.17, C.text), P(C.red, 0.42, 0.26, 0.5, 0.28, 0.46, 0.32), P(C.red, 0.74, 0.18, 0.7, 0.24, 0.66, 0.2), E(0.63, 0.27, 0.11, 0.13, C.soft), E(0.64, 0.27, 0.035, 0.12, C.bg), E(0.55, 0.21, 0.03, 0.025, C.text),
    R(0.5, 0.47, 0.2, 0.03, C.bg), R(0.66, 0.54, 0.16, 0.06, C.tie), P(C.text, 0.8, 0.5, 1, 0.42, 0.84, 0.54), P(C.text, 0.8, 0.54, 1, 0.56, 0.84, 0.58), P(C.text, 0.8, 0.56, 0.98, 0.7, 0.82, 0.6) }, 0.9, 0.84)
end
F.em_moth = function()
  return fit({ P(C.text, 0.48, 0.5, 0.2, 0.14, 0.02, 0.2, 0.04, 0.5, 0.14, 0.64, 0.02, 0.76, 0.16, 0.92, 0.44, 0.62), P(C.text, 0.52, 0.5, 0.8, 0.14, 0.98, 0.2, 0.96, 0.5, 0.86, 0.64, 0.98, 0.76, 0.84, 0.92, 0.56, 0.62), E(0.5, 0.56, 0.05, 0.18, C.line), E(0.5, 0.36, 0.05, 0.05, C.line),
    R(0.44, 0.22, 0.01, 0.12, C.tie), R(0.55, 0.22, 0.01, 0.12, C.tie), E(0.2, 0.34, 0.05, 0.05, C.info), E(0.8, 0.34, 0.05, 0.05, C.info), E(0.14, 0.42, 0.02, 0.02, C.info), E(0.86, 0.42, 0.02, 0.02, C.info), E(0.28, 0.72, 0.03, 0.03, C.info), E(0.72, 0.72, 0.03, 0.03, C.info) }, 0.74, 0.74, 0, -0.14)
end
F.vt_moth = function()
  return { P(C.line, 0.48, 0.5, 0.2, 0.08, 0.0, 0.14, 0.02, 0.5, 0.12, 0.64, 0.02, 0.8, 0.16, 0.96, 0.44, 0.64), P(C.line, 0.52, 0.5, 0.8, 0.08, 1, 0.14, 0.98, 0.5, 0.88, 0.64, 0.98, 0.8, 0.84, 0.96, 0.56, 0.64), P(C.tie, 0.46, 0.52, 0.24, 0.2, 0.1, 0.24, 0.12, 0.5, 0.44, 0.58), P(C.tie, 0.54, 0.52, 0.76, 0.2, 0.9, 0.24, 0.88, 0.5, 0.56, 0.58),
    E(0.5, 0.56, 0.06, 0.2, C.text), E(0.5, 0.34, 0.06, 0.06, C.text), R(0.44, 0.18, 0.012, 0.14, C.line), R(0.545, 0.18, 0.012, 0.14, C.line),
    E(0.22, 0.34, 0.08, 0.08, C.warn), E(0.22, 0.34, 0.05, 0.05, C.hi), E(0.78, 0.34, 0.08, 0.08, C.warn), E(0.78, 0.34, 0.05, 0.05, C.hi), E(0.46, 0.33, 0.02, 0.02, C.bg), E(0.54, 0.33, 0.02, 0.02, C.bg) }
end

--- Pages in the air, in the shape of whatever they're pretending to be. spots: { x, y, tilt }.
local function pageSwarm(spots, ink, line)
  local list = {}
  for i, p in ipairs(spots) do
    local x, y, t = p[1], p[2], (i % 3 - 1) * 0.03
    list[#list + 1] = P(ink, x, y + t, x + 0.1, y - t, x + 0.1, y + 0.12 - t, x, y + 0.12 + t)
    list[#list + 1] = R(x + 0.02, y + 0.04, 0.06, 0.01, line)
    list[#list + 1] = R(x + 0.02, y + 0.07, 0.05, 0.01, line)
  end
  return list
end
F.em_folio = function()
  local spots = {}
  for i = 0, 7 do spots[#spots + 1] = { 0.44 + (i % 2) * 0.1, 0.03 + i * 0.038 } end
  for i = 0, 8 do
    spots[#spots + 1] = { 0.3 + (i % 3) * 0.13 + (i > 5 and 0.03 or 0), 0.34 + (i - i % 3) / 3 * 0.14 }
  end
  for i = 0, 5 do spots[#spots + 1] = { 0.14 + i * 0.13, 0.82 + (i % 2) * 0.04 } end
  return join({ P(C.panel, 0.34, 0.3, 0.64, 0.3, 0.8, 1, 0.2, 1), E(0.5, 0.2, 0.13, 0.15, C.bg) }, pageSwarm(spots, C.text, C.tie))
end
F.vt_pages = function()
  local spots = {}
  for i = 0, 15 do spots[#spots + 1] = { 0.04 + (i * 37 % 86) / 100, 0.18 + 0.5 * (i / 15) + sin(i * 1.4) * 0.16 } end
  local list = pageSwarm(spots, C.text, C.tie)
  for _, p in ipairs(spots) do list[#list + 1] = R(p[1], p[2], 0.1, 0.012, C.hi) end
  return list
end

-- ---------------------------------------------------------------- props. On a map these stand for a thing, not for somebody.
-- PROPS gives each one how much of a square it takes and how far back in it it stands, from 0 at the front to 1 at the back.

local PROPS = {}
M.PROPS = PROPS

local function prop(name, size, near, build)
  F[name] = build
  PROPS[name] = { size = size, near = near }
end

--- A post with something on it, standing on the floor.
local function postOf(ink, x)
  return { R(x or 0.46, 0.3, 0.08, 0.7, ink or C.redTint), R((x or 0.46) - 0.06, 0.96, 0.2, 0.04, C.bg) }
end
--- A notice on its post.
local function boardOf(wood, face, lines, line)
  local list = join(postOf(wood), { R(0.18, 0.1, 0.64, 0.44, wood), R(0.22, 0.14, 0.56, 0.36, face) })
  for i = 1, lines do list[#list + 1] = R(0.27, 0.15 + i * 0.075, 0.46 - (i * 7 % 3) * 0.08, 0.02, line or C.tie) end
  return list
end
--- A spoked wheel on a post or a pipe.
local function wheelOf(ink, edge, hub)
  local list = join(postOf(C.tie), { E(0.5, 0.36, 0.33, 0.33, ink), E(0.5, 0.36, 0.26, 0.26, C.bg), R(0.47, 0.03, 0.06, 0.66, ink), R(0.17, 0.33, 0.66, 0.06, ink), P(ink, 0.27, 0.15, 0.31, 0.12, 0.73, 0.57, 0.69, 0.6), P(ink, 0.73, 0.15, 0.69, 0.12, 0.27, 0.57, 0.31, 0.6), E(0.5, 0.36, 0.07, 0.07, hub or C.line) })
  if edge then
    for i = 0, 7 do
      local a = i / 8 * 6.283 + 0.3
      list[#list + 1] = E(0.5 + math.cos(a) * 0.3, 0.36 + sin(a) * 0.3, 0.035, 0.025, edge)
    end
  end
  return list
end
--- Bars across a passage: a whole gate, from wall to wall. rail: how many cross pieces. Nothing between the bars, so you see through.
local function barsOf(ink, frame, count, rail, over)
  local list = { R(0, 0, 1, 0.06, frame), R(0, 0, 0.06, 1, frame), R(0.94, 0, 0.06, 1, frame), R(0, 0.95, 1, 0.05, frame) }
  for i = 1, count do list[#list + 1] = R(i / (count + 1) - 0.016, 0.04, 0.032, 0.92, ink) end
  for i = 1, rail do list[#list + 1] = R(0.03, i / (rail + 1) - 0.016, 0.94, 0.032, ink) end
  return join(list, over)
end
--- A cage on a cable, for going up or down.
local function cageOf(ink, floorInk, inside, top)
  local list = { R(0.48, 0, 0.04, 0.16, C.line), R(0.2, 0.14, 0.6, 0.05, ink), R(0.2, 0.86, 0.6, 0.08, floorInk) }
  for i = 0, 5 do list[#list + 1] = R(0.2 + i * 0.112, 0.16, 0.024, 0.72, ink) end
  return join(inside, list, R(0.2, 0.46, 0.6, 0.02, ink), top)
end

prop("px_board", 0.7, 0.5, function() return boardOf(C.redTint, C.text, 3, C.tie) end)
prop("vt_sign", 0.7, 0.5, function() return join(boardOf(C.tie, C.text, 3, C.bg), { R(0.46, 0.2, 0.09, 0.025, C.red), R(0.485, 0.17, 0.03, 0.09, C.red), R(0.49, 0.0, 0.02, 0.1, C.line), E(0.5, 0.08, 0.05, 0.04, C.hi), E(0.5, 0.08, 0.025, 0.02, C.text) }) end)
prop("px_wheel", 0.6, 0.45, function() return wheelOf(C.redTint, nil, C.warn) end)
prop("wm_wheel", 0.7, 0.45, function() return wheelOf(C.tie, C.text, C.text) end)
prop("vt_wheel", 0.7, 0.45, function()
  local list = wheelOf(C.red, nil, C.warn)
  return join({ R(0, 0.52, 1, 0.16, C.tie), R(0, 0.52, 1, 0.03, C.line), R(0.84, 0.46, 0.12, 0.28, C.line), R(0.86, 0.5, 0.08, 0.2, C.bg) }, list)
end)
prop("vt_brake", 0.7, 0.45, function()
  local list = {}
  for i = 0, 11 do
    local a = i / 12 * 6.283
    list[#list + 1] = E(0.5 + math.cos(a) * 0.33, 0.62 + sin(a) * 0.33, 0.05, 0.05, C.tie)
  end
  return join(list, E(0.5, 0.62, 0.32, 0.32, C.tie), E(0.5, 0.62, 0.22, 0.22, C.panel), P(C.warn, 0.08, 0.04, 0.16, 0.0, 0.62, 0.62, 0.54, 0.68), E(0.5, 0.62, 0.06, 0.06, C.hi), R(0.42, 0.56, 0.2, 0.02, C.line))
end)
prop("px_lamp", 0.5, 0.85, function() return { R(0.1, 0.84, 0.8, 0.16, C.tie), R(0.1, 0.84, 0.8, 0.03, C.line), R(0.34, 0.76, 0.32, 0.08, C.tie), R(0.38, 0.3, 0.24, 0.46, C.line), R(0.42, 0.34, 0.16, 0.38, C.bg), P(C.line, 0.3, 0.3, 0.7, 0.3, 0.5, 0.1), R(0.46, 0.02, 0.08, 0.1, C.line) } end)
prop("px_lamp_lit", 0.5, 0.85, function() return { E(0.5, 0.5, 0.48, 0.48, C.redTint), R(0.1, 0.84, 0.8, 0.16, C.tie), R(0.1, 0.84, 0.8, 0.03, C.line), R(0.34, 0.76, 0.32, 0.08, C.panel), R(0.38, 0.3, 0.24, 0.46, C.bg), R(0.42, 0.34, 0.16, 0.38, C.hi), E(0.5, 0.54, 0.05, 0.12, C.text), P(C.tie, 0.3, 0.3, 0.7, 0.3, 0.5, 0.1), R(0.46, 0.02, 0.08, 0.1, C.tie) } end)
prop("em_lamp", 0.9, 0.45, function() return join(postOf(C.tie), { R(0.3, 0.14, 0.4, 0.3, C.bg), R(0.34, 0.18, 0.1, 0.22, C.info), R(0.46, 0.18, 0.1, 0.22, C.accent), R(0.58, 0.18, 0.08, 0.22, C.red), P(C.tie, 0.22, 0.14, 0.78, 0.14, 0.5, 0.0), R(0.3, 0.44, 0.4, 0.03, C.tie) }) end)
prop("px_bell", 0.55, 0.85, function() return { R(0.14, 0.02, 0.72, 0.96, C.tie), E(0.5, 0.42, 0.26, 0.34, C.bg), R(0.24, 0.42, 0.52, 0.5, C.bg), R(0.48, 0.1, 0.04, 0.14, C.line), P(C.hi, 0.42, 0.22, 0.58, 0.22, 0.68, 0.56, 0.32, 0.56), R(0.32, 0.56, 0.36, 0.03, C.warn), E(0.5, 0.63, 0.05, 0.05, C.red), R(0.14, 0.9, 0.72, 0.08, C.line) } end)

-- ---- books on stands
local function standOf(ink, top) return join({ R(0.44, 0.44, 0.12, 0.5, ink), R(0.26, 0.92, 0.48, 0.08, ink), P(ink, 0.14, 0.3, 0.86, 0.3, 0.8, 0.46, 0.2, 0.46) }, top) end
local function openBook(under)
  return { P(under or C.redTint, 0.14, 0.24, 0.86, 0.24, 0.88, 0.32, 0.12, 0.32), P(C.text, 0.17, 0.12, 0.49, 0.18, 0.49, 0.3, 0.15, 0.28), P(C.text, 0.83, 0.12, 0.51, 0.18, 0.51, 0.3, 0.85, 0.28), P(C.line, 0.2, 0.17, 0.44, 0.21, 0.44, 0.23, 0.2, 0.19), P(C.line, 0.8, 0.17, 0.56, 0.21, 0.56, 0.23, 0.8, 0.19) }
end
local function chainLink() return { R(0.82, 0.3, 0.03, 0.05, C.line), R(0.8, 0.34, 0.03, 0.05, C.line), R(0.78, 0.38, 0.03, 0.05, C.line), R(0.74, 0.42, 0.05, 0.03, C.line), R(0.7, 0.46, 0.05, 0.03, C.line), R(0.62, 0.5, 0.04, 0.2, C.line) } end
prop("px_ledger", 0.72, 0.5, function() return standOf(C.redTint, openBook(C.red)) end)
prop("wm_board", 0.72, 0.5, function() return standOf(C.tie, join(openBook(C.bg), chainLink())) end)
prop("vt_lectern", 0.72, 0.5, function() return standOf(C.panel, join(openBook(C.blueTint), chainLink(), { R(0.46, 0.16, 0.08, 0.08, C.warn) })) end)

-- ---- casks, carts and machinery
prop("px_cask", 0.78, 0.45, function()
  return { R(0.1, 0.9, 0.8, 0.05, C.redTint), P(C.line, 0.04, 1, 0.1, 0.9, 0.16, 0.9, 0.12, 1), P(C.line, 0.84, 0.9, 0.9, 0.9, 0.96, 1, 0.88, 1), E(0.5, 0.48, 0.3, 0.42, C.tie), R(0.2, 0.2, 0.6, 0.6, C.tie), R(0.2, 0.28, 0.6, 0.04, C.line), R(0.2, 0.68, 0.6, 0.04, C.line), R(0.3, 0.14, 0.03, 0.74, C.redTint), R(0.66, 0.14, 0.03, 0.74, C.redTint),
    R(0.38, 0.4, 0.24, 0.2, C.text), R(0.47, 0.42, 0.06, 0.16, C.red), R(0.42, 0.47, 0.16, 0.06, C.red), E(0.74, 0.86, 0.02, 0.03, C.soft), E(0.5, 0.97, 0.05, 0.015, C.soft) }
end)
prop("px_cart", 1, 0.2, function()
  return { P(C.bg, 0.1, 0.1, 0.9, 0.1, 0.94, 0.74, 0.06, 0.74), P(C.panel, 0.14, 0.04, 0.86, 0.04, 0.9, 0.12, 0.1, 0.12), R(0.14, 0.2, 0.72, 0.02, C.tie), R(0.14, 0.62, 0.72, 0.02, C.tie), R(0.46, 0.34, 0.08, 0.05, C.red), R(0.48, 0.3, 0.04, 0.14, C.red),
    E(0.24, 0.84, 0.15, 0.16, C.line), E(0.24, 0.84, 0.1, 0.11, C.bg), E(0.24, 0.84, 0.04, 0.04, C.line), E(0.76, 0.84, 0.15, 0.16, C.line), E(0.76, 0.84, 0.1, 0.11, C.bg), E(0.76, 0.84, 0.04, 0.04, C.line) }
end)
prop("px_lift", 0.95, 0.5, function() return cageOf(C.hi, C.warn, { R(0.38, 0.62, 0.24, 0.24, C.red), R(0.38, 0.5, 0.24, 0.14, C.red), R(0.38, 0.6, 0.24, 0.03, C.redTint) }) end)
prop("vt_hoist", 1, 0.5, function() return cageOf(C.tie, C.panel, { R(0.3, 0.62, 0.3, 0.24, C.redTint) }, { R(0.42, 0.04, 0.16, 0.1, C.hi), R(0.42, 0.02, 0.16, 0.02, C.bg), R(0.42, 0.14, 0.16, 0.02, C.bg), R(0.47, 0.06, 0.06, 0.06, C.text) }) end)
prop("vt_cradle", 1, 0.5, function()
  return { R(0, 0.1, 1, 0.05, C.tie), R(0, 0.18, 1, 0.02, C.line), R(0.2, 0.15, 0.04, 0.5, C.tie), R(0.76, 0.15, 0.04, 0.5, C.tie), E(0.22, 0.13, 0.06, 0.05, C.line), E(0.78, 0.13, 0.06, 0.05, C.line), P(C.tie, 0.14, 0.6, 0.86, 0.6, 0.78, 0.86, 0.22, 0.86), P(C.panel, 0.2, 0.64, 0.8, 0.64, 0.74, 0.82, 0.26, 0.82), R(0.34, 0.6, 0.03, 0.26, C.tie), R(0.62, 0.6, 0.03, 0.26, C.tie) }
end)
prop("ud_basket", 0.85, 0.5, function()
  local list = { R(0.48, 0, 0.04, 0.3, C.line), P(C.line, 0.5, 0.26, 0.54, 0.26, 0.86, 0.46, 0.82, 0.48), P(C.line, 0.46, 0.26, 0.5, 0.26, 0.18, 0.48, 0.14, 0.46), P(C.warn, 0.14, 0.46, 0.86, 0.46, 0.76, 0.96, 0.24, 0.96) }
  for i = 0, 4 do list[#list + 1] = R(0.16 + i * 0.02, 0.5 + i * 0.09, 0.68 - i * 0.04, 0.02, C.redTint) end
  for i = 0, 5 do list[#list + 1] = R(0.22 + i * 0.11, 0.46, 0.02, 0.5, C.redTint) end
  return list
end)
prop("ud_winch", 0.85, 0.45, function()
  local list = { R(0.14, 0.3, 0.08, 0.7, C.redTint), R(0.78, 0.3, 0.08, 0.7, C.redTint), R(0.06, 0.94, 0.88, 0.06, C.bg), R(0.2, 0.34, 0.6, 0.32, C.warn) }
  for i = 0, 7 do list[#list + 1] = R(0.22, 0.36 + i * 0.04, 0.56, 0.02, C.text) end
  return join(list, R(0.8, 0.46, 0.14, 0.05, C.line), R(0.92, 0.46, 0.05, 0.34, C.line), R(0.92, 0.76, 0.08, 0.06, C.redTint))
end)
prop("wm_drum", 0.95, 0.4, function()
  local list = { R(0.04, 0.42, 0.92, 0.06, C.tie), R(0.08, 0.3, 0.07, 0.7, C.panel), R(0.85, 0.3, 0.07, 0.7, C.panel), E(0.5, 0.45, 0.32, 0.36, C.panel), R(0.2, 0.18, 0.6, 0.54, C.tie) }
  for i = 0, 7 do list[#list + 1] = R(0.2, 0.2 + i * 0.07, 0.6, 0.05, i % 2 == 0 and C.text or C.line) end
  for i = 0, 3 do list[#list + 1] = E(0.26 + i * 0.16, 0.08 + (i % 2) * 0.06, 0.07, 0.04, C.line) end
  return list
end)
prop("wm_jar", 0.75, 0.5, function()
  return { P(C.hi, 0.3, 0.84, 0.36, 0.84, 0.28, 1, 0.22, 1), P(C.hi, 0.64, 0.84, 0.7, 0.84, 0.78, 1, 0.72, 1), R(0.47, 0.84, 0.06, 0.16, C.hi), R(0.24, 0.8, 0.52, 0.05, C.warn), E(0.5, 0.38, 0.27, 0.34, C.blueTint), R(0.23, 0.38, 0.54, 0.43, C.blueTint), E(0.5, 0.52, 0.14, 0.17, C.text), E(0.5, 0.42, 0.11, 0.11, C.text), E(0.46, 0.4, 0.02, 0.02, C.bg), E(0.55, 0.4, 0.02, 0.02, C.bg), E(0.51, 0.47, 0.03, 0.03, C.bg),
    P(C.text, 0.3, 0.18, 0.34, 0.14, 0.3, 0.5, 0.27, 0.46), R(0.46, 0.0, 0.08, 0.05, C.hi) }
end)
prop("wm_case", 0.85, 0.5, function()
  return { R(0.1, 0.56, 0.8, 0.4, C.redTint), R(0.1, 0.56, 0.8, 0.03, C.warn), R(0.16, 0.94, 0.12, 0.06, C.bg), R(0.72, 0.94, 0.12, 0.06, C.bg), R(0.14, 0.14, 0.72, 0.42, C.blueTint), R(0.14, 0.14, 0.72, 0.03, C.text), R(0.14, 0.14, 0.03, 0.42, C.text), R(0.83, 0.14, 0.03, 0.42, C.text), P(C.line, 0.3, 0.2, 0.34, 0.2, 0.26, 0.5, 0.22, 0.5), E(0.5, 0.42, 0.1, 0.09, C.soft), E(0.5, 0.42, 0.04, 0.06, C.bg), R(0.38, 0.68, 0.24, 0.1, C.text), R(0.41, 0.72, 0.18, 0.012, C.tie) }
end)
prop("vt_kettle", 0.65, 0.5, function()
  return { R(0.18, 0.84, 0.46, 0.16, C.warn), R(0.3, 0.8, 0.22, 0.05, C.bg), E(0.41, 0.74, 0.04, 0.07, C.info), E(0.41, 0.46, 0.34, 0.3, C.tie), R(0.08, 0.28, 0.66, 0.04, C.line), R(0.36, 0.2, 0.1, 0.05, C.line), E(0.28, 0.16, 0.05, 0.04, C.line), E(0.42, 0.06, 0.06, 0.04, C.line),
    P(C.line, 0.76, 0.84, 0.98, 0.84, 0.92, 0.98, 0.82, 0.98), E(0.87, 0.84, 0.11, 0.025, C.text) }
end)
prop("vt_desk", 0.95, 0.45, function()
  local list = { R(0.0, 0.84, 1, 0.16, C.redTint), R(0.0, 0.84, 1, 0.02, C.warn), R(0.16, 0.5, 0.68, 0.06, C.warn), R(0.2, 0.56, 0.06, 0.3, C.redTint), R(0.74, 0.56, 0.06, 0.3, C.redTint), R(0.74, 0.3, 0.03, 0.2, C.line), R(0.68, 0.2, 0.15, 0.13, C.hi), R(0.72, 0.23, 0.07, 0.07, C.text), R(0.68, 0.18, 0.15, 0.02, C.bg) }
  return join(list, fit(openBook(C.accent), 0.5, 0.8, -0.18, -0.26))
end)
prop("vt_drawer", 0.95, 0.75, function()
  local list = { R(0.16, 0.0, 0.68, 1, C.redTint), R(0.16, 0, 0.68, 0.03, C.warn) }
  for row = 0, 7 do
    for col = 0, 3 do
      list[#list + 1] = R(0.2 + col * 0.155, 0.05 + row * 0.115, 0.13, 0.09, C.warn)
      list[#list + 1] = R(0.24 + col * 0.155, 0.08 + row * 0.115, 0.05, 0.02, C.text)
    end
  end
  return join(list, R(0.5, 0.42, 0.34, 0.11, C.hi), R(0.52, 0.4, 0.3, 0.04, C.text), R(0.64, 0.46, 0.05, 0.02, C.redTint))
end)
prop("vt_ashes", 0.7, 0.5, function()
  return { R(0.0, 0.92, 0.3, 0.02, C.line), R(0.0, 0.92, 0.02, 0.08, C.line), R(0.28, 0.92, 0.02, 0.08, C.line), R(0.7, 0.92, 0.3, 0.02, C.line), R(0.7, 0.92, 0.02, 0.08, C.line), R(0.98, 0.92, 0.02, 0.08, C.line),
    P(C.line, 0.3, 0.46, 0.7, 0.46, 0.66, 1, 0.34, 1), R(0.3, 0.46, 0.4, 0.05, C.tie), E(0.5, 0.48, 0.17, 0.04, C.bg), R(0.34, 0.7, 0.32, 0.015, C.panel), R(0.34, 0.84, 0.32, 0.015, C.panel), E(0.46, 0.47, 0.05, 0.015, C.warn), E(0.56, 0.48, 0.03, 0.012, C.red) }
end)
prop("vt_robe", 0.95, 0.7, function()
  local list = {}
  for row = 0, 11 do
    for col = 0, 4 do
      local x = 0.0 + col * 0.2 + (row % 2) * 0.1
      if row > 1 or col ~= 2 then list[#list + 1] = R(x, row * 0.085, 0.185, 0.07, C.redTint) end
    end
  end
  return join({ R(0, 0, 1, 1, C.bg) }, list, R(0.22, 0.16, 0.56, 0.84, C.bg), R(0.34, 0.66, 0.32, 0.04, C.warn), R(0.36, 0.7, 0.04, 0.3, C.warn), R(0.6, 0.7, 0.04, 0.3, C.warn), R(0.34, 0.3, 0.32, 0.04, C.warn), R(0.34, 0.3, 0.04, 0.4, C.warn), R(0.62, 0.3, 0.04, 0.4, C.warn),
    P(C.accent, 0.4, 0.36, 0.6, 0.36, 0.66, 0.84, 0.34, 0.84), P(C.hi, 0.36, 0.42, 0.64, 0.42, 0.68, 0.28, 0.6, 0.38, 0.4, 0.38, 0.32, 0.28), E(0.5, 0.36, 0.06, 0.03, C.bg))
end)
prop("vt_gap", 1, 0.2, function()
  return { R(0.0, 0.9, 0.2, 0.1, C.tie), R(0.2, 0.92, 0.1, 0.08, C.tie), R(0.3, 0.95, 0.08, 0.05, C.tie), R(0.7, 0.92, 0.3, 0.08, C.tie), R(0.62, 0.95, 0.08, 0.05, C.tie), R(0.14, 0.0, 0.03, 0.9, C.line), R(0.84, 0.0, 0.03, 0.92, C.line), R(0.38, 0.0, 0.02, 0.6, C.line), R(0.36, 0.58, 0.06, 0.04, C.tie), R(0.6, 0.0, 0.02, 0.44, C.line), R(0.58, 0.42, 0.06, 0.04, C.tie) }
end)
prop("vt_window", 1, 0.85, function()
  return join({ R(0, 0, 1, 1, C.panel), R(0.14, 0.1, 0.72, 0.8, C.bg), R(0.14, 0.1, 0.72, 0.03, C.warn), R(0.14, 0.87, 0.72, 0.03, C.warn), R(0.14, 0.1, 0.03, 0.8, C.warn), R(0.83, 0.1, 0.03, 0.8, C.warn), R(0.2, 0.6, 0.6, 0.3, C.tie) }, chainDown(0.5, 0.0, 9, C.line, C.tie))
end)

-- ---- gates
prop("px_grate", 1, 0.05, function() return barsOf(C.tie, C.panel, 7, 2) end)
prop("em_grille", 1, 0.05, function() return barsOf(C.panel, C.bg, 11, 1) end)
prop("wm_grille", 1, 0.05, function()
  return barsOf(C.warn, C.redTint, 9, 2, { E(0.5, 0.56, 0.32, 0.2, C.warn), E(0.5, 0.52, 0.27, 0.13, C.bg), P(C.warn, 0.2, 0.44, 0.8, 0.44, 0.6, 0.5, 0.4, 0.5), R(0.26, 0.54, 0.48, 0.02, C.warn), E(0.32, 0.28, 0.05, 0.05, C.warn), E(0.68, 0.28, 0.05, 0.05, C.warn) })
end)
prop("ud_saltgate", 1, 0.05, function()
  local list = barsOf(C.tie, C.line, 7, 2)
  for i = 0, 18 do list[#list + 1] = E((i * 37 % 94 + 3) / 100, (i * 61 % 90 + 5) / 100, 0.05, 0.03, C.text) end
  return join(list, R(0, 0, 1, 0.05, C.text), R(0, 0.93, 1, 0.07, C.text))
end)
prop("wm_lockgate", 1, 0.05, function()
  local list = { R(0, 0, 0.5, 1, C.tie), R(0.5, 0, 0.5, 1, C.panel), R(0.49, 0, 0.02, 1, C.bg) }
  for i = 1, 4 do list[#list + 1] = R(0, i * 0.19, 1, 0.03, C.bg) end
  return join(list, R(0, 0.68, 1, 0.07, C.text), R(0, 0.75, 1, 0.25, C.blueTint), E(0.3, 0.76, 0.02, 0.04, C.info), E(0.7, 0.74, 0.02, 0.04, C.info), E(0.5, 0.5, 0.05, 0.05, C.tie))
end)
prop("vt_gate", 1, 0.05, function()
  local list = {}
  for i = 0, 6 do list = join(list, chainDown(0.07 + i * 0.143, -0.02 + (i % 2) * 0.1, 9, C.line, C.tie)) end
  return join(list, R(0, 0, 1, 0.06, C.panel), R(0, 0.95, 1, 0.05, C.red))
end)
prop("ud_curtain", 1, 0.05, function()
  local list = { R(0, 0, 1, 1, C.tie) }
  for i = 0, 9 do list[#list + 1] = snake(i % 2 == 0 and C.line or C.panel, 0.05 + i * 0.1, 0, 0.05 + i * 0.1, 1, 0.05, 0.08, 0.03, 3, i) end
  for i = 0, 7 do list[#list + 1] = E((i * 37 % 90 + 5) / 100, (i * 53 % 80 + 10) / 100, 0.09, 0.012, C.text) end
  return list
end)
prop("ud_cocoon", 0.95, 0.8, function()
  return { R(0.48, 0, 0.03, 0.14, C.text), E(0.5, 0.52, 0.22, 0.42, C.text), E(0.56, 0.52, 0.14, 0.38, C.line), R(0.3, 0.3, 0.42, 0.015, C.tie), R(0.28, 0.42, 0.44, 0.015, C.tie), R(0.28, 0.54, 0.44, 0.015, C.tie), R(0.3, 0.66, 0.42, 0.015, C.tie), R(0.33, 0.78, 0.34, 0.015, C.tie), E(0.46, 0.3, 0.08, 0.06, C.tie) }
end)
prop("ud_anchor", 0.75, 0.5, function()
  return { P(C.text, 0.0, 0.0, 0.12, 0.0, 0.6, 0.66, 0.52, 0.74), P(C.line, 0.06, 0.0, 0.12, 0.0, 0.6, 0.66, 0.56, 0.7), R(0.44, 0.62, 0.3, 0.1, C.tie), R(0.5, 0.56, 0.1, 0.44, C.tie), P(C.tie, 0.5, 0.96, 0.6, 0.96, 0.55, 1.02), R(0.2, 0.92, 0.7, 0.08, C.panel), E(0.55, 0.66, 0.03, 0.03, C.line) }
end)
prop("ud_bones", 0.8, 0.5, function()
  return { R(0.6, 0.48, 0.34, 0.06, C.tie), R(0.66, 0.54, 0.06, 0.46, C.panel), R(0.84, 0.54, 0.06, 0.46, C.panel), R(0.66, 0.4, 0.2, 0.08, C.bg), R(0.68, 0.42, 0.14, 0.04, C.tie), R(0.08, 0.62, 0.3, 0.06, C.redTint), R(0.08, 0.68, 0.05, 0.32, C.redTint), R(0.32, 0.68, 0.05, 0.32, C.redTint), R(0.2, 0.3, 0.04, 0.34, C.text),
    R(0.13, 0.34, 0.18, 0.02, C.text), R(0.14, 0.4, 0.16, 0.02, C.text), R(0.15, 0.46, 0.14, 0.02, C.text), P(C.redTint, 0.12, 0.3, 0.32, 0.3, 0.3, 0.36, 0.14, 0.36), R(0.1, 0.62, 0.26, 0.04, C.text), R(0.34, 0.66, 0.03, 0.3, C.text), E(0.26, 0.2, 0.1, 0.1, C.text), E(0.3, 0.2, 0.025, 0.03, C.bg), P(C.text, 0.26, 0.34, 0.3, 0.36, 0.6, 0.46, 0.58, 0.5) }
end)

-- ---------------------------------------------------------------- the ruined world, and the end of it

local WHITE_COAT = { skin = C.text, coat = C.text, trim = C.line, legs = C.line, boots = C.tie }

--- Someone from the Clinic who has stopped sleeping. They keep their uniform very clean.
local function wakeful(o)
  return man({ wide = o.wide or 0.15, hem = o.hem or 0.76, flare = o.flare, skin = C.text, coat = o.coat, trim = o.trim, legs = o.legs or C.line, boots = C.tie, noArm = o.noArm, body = o.body, over = o.over, hair = o.hair or C.tie,
    head = o.head or { R(0.47, 0.3, 0.1, 0.06, C.text), E(0.54, 0.2, 0.14, 0.15, C.text), P(o.hair or C.tie, 0.4, 0.14, 0.42, 0.05, 0.66, 0.05, 0.69, 0.1, 0.46, 0.1), E(0.6, 0.18, 0.04, 0.04, C.text), E(0.61, 0.18, 0.02, 0.02, C.red), E(0.5, 0.18, 0.03, 0.04, C.text), E(0.51, 0.18, 0.015, 0.02, C.red),
      P(C.bg, 0.52, 0.26, 0.6, 0.28, 0.66, 0.25, 0.66, 0.27, 0.6, 0.3, 0.52, 0.28) } })
end

--- A plain nightshirt, up and walking, not awake.
local function sleeper(pale)
  return man({ wide = 0.15, hem = 0.84, skin = C.warn, coat = C.text, trim = C.line, legs = C.warn, boots = C.warn, hair = C.redTint, noArm = true,
    back = { R(0.65, 0.38, 0.09, 0.2, C.text), R(0.7, 0.5, 0.16, 0.06, C.text), E(0.87, 0.53, 0.04, 0.04, C.warn) },
    head = { R(0.47, 0.3, 0.1, 0.06, C.warn), E(0.54, 0.2, 0.14, 0.15, C.warn), P(C.redTint, 0.4, 0.14, 0.42, 0.05, 0.66, 0.05, 0.69, 0.1, 0.46, 0.1), E(0.6, 0.18, 0.035, 0.035, pale), E(0.5, 0.18, 0.03, 0.035, pale), R(0.54, 0.27, 0.08, 0.012, C.redTint) } })
end

--- A person gone to crystal. side says how far up it has reached.
local function crystal(ink, core, x, y, wide, tall, tilt)
  return { P(ink, x - wide, y, x + wide, y, x + wide * 0.6 + tilt, y - tall * 0.8, x + tilt, y - tall, x - wide * 0.6 + tilt, y - tall * 0.8), P(core, x - wide * 0.3, y, x + wide * 0.3, y, x + tilt, y - tall * 0.9) }
end

F.rs_nightman = function() return wakeful({ coat = C.line, trim = C.text, body = { R(0.46, 0.42, 0.09, 0.03, C.red), R(0.49, 0.38, 0.03, 0.12, C.red) } }) end
F.rn_sleepless = function()
  return wakeful({ coat = C.tie, trim = C.line, legs = C.tie, noArm = true, body = { R(0.42, 0.4, 0.26, 0.28, C.redTint), R(0.44, 0.42, 0.22, 0.25, C.text), R(0.47, 0.48, 0.16, 0.012, C.tie), R(0.47, 0.54, 0.16, 0.012, C.tie), R(0.47, 0.6, 0.12, 0.012, C.tie), R(0.62, 0.52, 0.1, 0.08, C.tie), E(0.68, 0.56, 0.05, 0.05, C.text) } })
end
F.rn_prynne = function()
  return wakeful({ wide = 0.12, hem = 0.86, coat = C.tie, trim = C.panel, hair = C.redTint, over = { P(C.text, 0.8, 0.42, 0.98, 0.42, 0.98, 0.54, 0.8, 0.54), P(C.line, 0.8, 0.42, 0.98, 0.42, 0.92, 0.47, 0.8, 0.47) } })
end
F.rd_consultant = function()
  local o = {}
  for k, v in pairs(WHITE_COAT) do o[k] = v end
  o.wide, o.hem, o.flare = 0.13, 0.94, 1.3
  o.head = { R(0.47, 0.3, 0.1, 0.06, C.text), E(0.54, 0.2, 0.14, 0.15, C.text), P(C.tie, 0.4, 0.14, 0.42, 0.05, 0.66, 0.05, 0.69, 0.1, 0.46, 0.1), R(0.39, 0.13, 0.31, 0.08, C.line), R(0.39, 0.2, 0.31, 0.012, C.tie), P(C.bg, 0.52, 0.26, 0.6, 0.29, 0.68, 0.25, 0.68, 0.27, 0.6, 0.32, 0.52, 0.28) }
  o.body = { R(0.46, 0.42, 0.09, 0.03, C.red), R(0.49, 0.38, 0.03, 0.12, C.red) }
  o.over = { R(0.76, 0.3, 0.17, 0.24, C.redTint), R(0.78, 0.32, 0.13, 0.21, C.text), R(0.81, 0.28, 0.07, 0.03, C.line), R(0.8, 0.38, 0.09, 0.012, C.tie), R(0.8, 0.43, 0.09, 0.012, C.tie) }
  return man(o)
end
F.rs_riser = function() return sleeper(C.text) end
F.fn_sleepers = function()
  local one = sleeper(C.warn)
  return join(fit(one, 0.5, 0.7, -0.33, -0.1), fit(one, 0.5, 0.7, -0.11, -0.08), fit(one, 0.5, 0.7, 0.11, -0.1), fit(one, 0.5, 0.7, 0.33, -0.08), fit(one, 0.6, 0.86, -0.22, 0), fit(one, 0.6, 0.86, 0.02, 0), fit(one, 0.6, 0.86, 0.26, 0))
end
F.rs_hand = function()
  return man({ wide = 0.18, coat = C.tie, legs = C.panel, boots = C.bg, skin = C.line, noArm = true,
    head = { R(0.47, 0.3, 0.1, 0.06, C.line), E(0.54, 0.2, 0.14, 0.15, C.line), R(0.6, 0.16, 0.06, 0.05, C.bg), E(0.6, 0.28, 0.05, 0.06, C.bg), P(C.tie, 0.4, 0.2, 0.42, 0.06, 0.66, 0.06, 0.68, 0.1, 0.46, 0.14) },
    body = { P(C.panel, 0.32, 0.76, 0.42, 0.62, 0.5, 0.76), P(C.panel, 0.56, 0.76, 0.62, 0.66, 0.7, 0.76), R(0.3, 0.42, 0.1, 0.02, C.hi), R(0.3, 0.46, 0.1, 0.02, C.hi) },
    over = { E(0.72, 0.56, 0.13, 0.13, C.warn), E(0.72, 0.56, 0.08, 0.08, C.bg), E(0.72, 0.56, 0.1, 0.1, C.redTint), E(0.72, 0.56, 0.05, 0.05, C.bg) } })
end
F.rs_bosun = function()
  local list = fit(man({ wide = 0.3, hem = 0.8, flare = 1.05, coat = C.panel, trim = C.bg, skin = C.line, legs = C.bg, boots = C.panel,
    head = { R(0.45, 0.3, 0.16, 0.06, C.line), E(0.56, 0.2, 0.18, 0.17, C.line), R(0.6, 0.15, 0.08, 0.05, C.warn), P(C.tie, 0.4, 0.22, 0.76, 0.22, 0.68, 0.46, 0.5, 0.48), P(C.tie, 0.38, 0.16, 0.42, 0.04, 0.72, 0.03, 0.74, 0.1, 0.5, 0.12) },
    over = { R(0.84, 0.3, 0.05, 0.24, C.line) } }), 1, 1)
  return join(list, P(C.red, 0.34, 0.76, 0.34, 0.5, 0.42, 0.56, 0.5, 0.42, 0.56, 0.58, 0.66, 0.5, 0.66, 0.76), P(C.warn, 0.38, 0.76, 0.42, 0.62, 0.5, 0.54, 0.58, 0.64, 0.62, 0.76), P(C.hi, 0.44, 0.76, 0.5, 0.64, 0.56, 0.76), P(C.hi, 0.44, 0.34, 0.66, 0.34, 0.54, 0.48), E(0.54, 0.5, 0.03, 0.03, C.text), R(0.53, 0.5, 0.06, 0.02, C.text))
end
F.rs_dole = function()
  local list = man({ wide = 0.13, hem = 0.92, flare = 1.25, coat = C.redTint, trim = C.tie, skin = C.warn, hair = C.tie, eye = C.bg, over = { R(0.83, 0.3, 0.015, 0.18, C.text) } })
  return join(list, E(0.46, 0.5, 0.12, 0.13, C.hi), E(0.46, 0.5, 0.09, 0.1, C.info), E(0.43, 0.46, 0.025, 0.03, C.text), crystal(C.info, C.text, 0.26, 0.74, 0.08, 0.5, -0.03), crystal(C.info, C.text, 0.38, 0.4, 0.06, 0.26, -0.05), crystal(C.text, C.info, 0.2, 0.52, 0.05, 0.3, -0.08))
end
F.rs_pane = function()
  return { P(C.info, 0.44, 0.98, 0.5, 1, 0.56, 0.98, 0.68, 0.3, 0.5, 0.0, 0.32, 0.3), P(C.text, 0.46, 0.92, 0.5, 0.98, 0.5, 0.04, 0.4, 0.28), P(C.blueTint, 0.5, 0.2, 0.6, 0.32, 0.54, 0.86, 0.5, 0.9),
    E(0.5, 0.36, 0.08, 0.1, C.line), R(0.46, 0.33, 0.03, 0.02, C.bg), R(0.52, 0.33, 0.03, 0.02, C.bg), E(0.5, 0.41, 0.018, 0.022, C.bg), R(0.14, 0.2, 0.08, 0.012, C.info), R(0.8, 0.3, 0.08, 0.012, C.info), R(0.1, 0.5, 0.1, 0.012, C.info), R(0.82, 0.56, 0.08, 0.012, C.info) }
end
F.rd_shard = function()
  return join(crystal(C.text, C.line, 0.26, 1, 0.13, 0.76, -0.1), crystal(C.line, C.text, 0.72, 1, 0.14, 0.84, 0.1), crystal(C.info, C.text, 0.42, 1, 0.14, 0.98, -0.04), crystal(C.text, C.info, 0.6, 1, 0.15, 0.66, 0.04),
    E(0.52, 0.5, 0.13, 0.1, C.tie), R(0.38, 0.5, 0.28, 0.03, C.panel), R(0.44, 0.52, 0.16, 0.05, C.bg), R(0.5, 0.42, 0.04, 0.1, C.line), E(0.56, 0.55, 0.012, 0.012, C.info))
end
F.rs_kite = function()
  local list = vulture({ wing = C.panel, wing2 = C.tie, neck = C.line })
  for i = 0, 8 do
    list[#list + 1] = R(0.02 + i * 0.05, 0.56 + (i * 3 % 4) * 0.05, 0.03, 0.025, i % 2 == 0 and C.warn or C.red)
    list[#list + 1] = R(0.66 + i * 0.04, 0.54 + (i * 5 % 4) * 0.05, 0.03, 0.025, i % 2 == 0 and C.red or C.hi)
  end
  return list
end
F.rs_cart = function() return join(F.px_cart(), { R(0.32, 0.26, 0.36, 0.42, C.bg), P(C.line, 0.32, 0.68, 0.68, 0.68, 0.76, 0.84, 0.24, 0.84), R(0.04, 0.3, 0.12, 0.02, C.line), R(0.84, 0.3, 0.12, 0.02, C.line) }) end
F.rn_crab = function()
  local list = inked(F.hr_crab(), { [C.red] = C.tie, [C.warn] = C.line, [C.redTint] = C.panel })
  return join(list, E(0.42, 0.56, 0.2, 0.18, C.redTint), R(0.24, 0.46, 0.36, 0.22, C.redTint), R(0.24, 0.5, 0.36, 0.02, C.warn), R(0.24, 0.62, 0.36, 0.02, C.warn), R(0.34, 0.53, 0.16, 0.07, C.text), R(0.37, 0.55, 0.1, 0.02, C.red), E(0.5, 0.74, 0.02, 0.03, C.red))
end
F.rn_clot = function()
  return fit({ E(0.5, 0.64, 0.42, 0.34, C.redTint), E(0.32, 0.5, 0.2, 0.2, C.redTint), E(0.68, 0.46, 0.22, 0.24, C.redTint), E(0.5, 0.66, 0.3, 0.22, C.red), E(0.6, 0.44, 0.1, 0.09, C.red), E(0.36, 0.5, 0.06, 0.05, C.warn), E(0.44, 0.74, 0.1, 0.05, C.bg), E(0.68, 0.4, 0.05, 0.03, C.text),
    R(0.42, 0.2, 0.2, 0.04, C.red), P(C.text, 0.48, 0.2, 0.42, 0.34, 0.5, 0.3), P(C.text, 0.56, 0.2, 0.62, 0.34, 0.54, 0.3), P(C.text, 0.44, 0.12, 0.6, 0.12, 0.52, 0.22), E(0.52, 0.2, 0.03, 0.03, C.text) }, 0.8, 0.8)
end
F.rn_giving = function()
  local list = { P(C.redTint, 0.0, 1, 0.0, 0.6, 0.14, 0.3, 0.4, 0.08, 0.72, 0.06, 0.96, 0.22, 1, 0.42, 0.86, 0.32, 0.74, 0.36, 0.72, 0.5, 1, 0.8, 1, 1),
    P(C.red, 0.06, 0.92, 0.1, 0.56, 0.24, 0.32, 0.44, 0.16, 0.7, 0.14, 0.9, 0.24, 0.72, 0.28, 0.64, 0.42, 0.68, 0.7, 0.9, 0.96), P(C.warn, 0.2, 0.3, 0.44, 0.1, 0.72, 0.08, 0.94, 0.22, 0.7, 0.14, 0.44, 0.16) }
  for i = 0, 13 do
    local x, y = 0.12 + (i * 37 % 54) / 100, 0.46 + (i * 23 % 46) / 100
    if i % 2 == 0 then
      list = join(list, P(C.line, x, y, x + 0.06, y, x + 0.04, y + 0.05, x + 0.02, y + 0.05), R(x + 0.025, y + 0.05, 0.01, 0.03, C.line))
    else
      list[#list + 1] = P(C.text, x, y, x + 0.018, y + 0.012, x + 0.09, y + 0.08, x + 0.08, y + 0.09)
    end
  end
  -- the smile: one, across the crest, up on both sides, exactly the same
  return join(list, P(C.bg, 0.18, 0.24, 0.26, 0.34, 0.42, 0.4, 0.58, 0.4, 0.72, 0.34, 0.82, 0.22, 0.76, 0.22, 0.6, 0.28, 0.42, 0.28, 0.26, 0.24), P(C.text, 0.24, 0.27, 0.42, 0.31, 0.6, 0.31, 0.77, 0.25, 0.72, 0.31, 0.58, 0.36, 0.42, 0.36, 0.28, 0.32))
end
F.rn_hollowling = function()
  local list = { snake(C.tie, 0.26, 0.74, 0.0, 0.94, 0.14, 0.02, 0.07, 2, 1), P(C.panel, 0.42, 0.5, 0.3, 0.06, 0.06, 0.1, 0.02, 0.4, 0.14, 0.34, 0.16, 0.56, 0.28, 0.42, 0.32, 0.62), R(0.3, 0.8, 0.09, 0.2, C.tie), R(0.56, 0.8, 0.09, 0.2, C.tie), P(C.line, 0.26, 0.96, 0.4, 0.96, 0.42, 1, 0.24, 1), P(C.line, 0.52, 0.96, 0.66, 0.96, 0.7, 1, 0.5, 1),
    E(0.46, 0.66, 0.26, 0.2, C.tie), E(0.46, 0.67, 0.2, 0.15, C.bg) }
  for i = 0, 5 do list[#list + 1] = P(C.line, 0.28 + i * 0.07, 0.5, 0.31 + i * 0.07, 0.5, 0.33 + i * 0.065, 0.84, 0.3 + i * 0.065, 0.84) end
  return join(list, snake(C.tie, 0.66, 0.6, 0.76, 0.24, 0.13, 0.08, 0.06, 1, 3.14), P(C.tie, 0.68, 0.24, 0.86, 0.08, 1, 0.16, 0.86, 0.22, 1, 0.36, 0.84, 0.36, 0.74, 0.36), P(C.bg, 0.74, 0.22, 0.86, 0.22, 0.98, 0.34, 0.8, 0.33), P(C.line, 0.68, 0.22, 0.6, 0.06, 0.74, 0.14), E(0.8, 0.16, 0.03, 0.03, C.bg),
    P(C.text, 0.88, 0.2, 0.9, 0.2, 0.89, 0.25), P(C.text, 0.94, 0.22, 0.96, 0.22, 0.95, 0.26), P(C.text, 0.84, 0.35, 0.86, 0.35, 0.85, 0.3))
end
F.rd_rover = function()
  local list = {}
  for i = 0, 3 do
    local x = 0.18 + i * 0.2
    list[#list + 1] = P(C.tie, x + 0.04, 0.6, x + 0.1, 0.6, x - 0.02 + i * 0.06, 0.92, x - 0.06 + i * 0.06, 0.92)
    list[#list + 1] = P(C.text, x - 0.1 + i * 0.06, 1, x - 0.06 + i * 0.06, 0.9, x + i * 0.06, 0.92, x - 0.04 + i * 0.06, 1)
  end
  return join(list, E(0.5, 0.46, 0.38, 0.26, C.line), snake(C.tie, 0.14, 0.42, 0.86, 0.46, 0.022, 0.022, 0.07, 5), snake(C.tie, 0.2, 0.56, 0.82, 0.58, 0.02, 0.02, 0.05, 5, 1), snake(C.tie, 0.26, 0.3, 0.78, 0.32, 0.02, 0.02, 0.05, 4, 2), R(0.49, 0.22, 0.02, 0.48, C.panel), E(0.56, 0.3, 0.1, 0.05, C.text))
end
F.rd_shed = function()
  local list = {}
  for i = 0, 7 do list[#list + 1] = snake(i % 2 == 0 and C.line or C.tie, 0.2 + i * 0.086, 0.72, 0.06 + i * 0.125, 0.98, 0.06, 0.015, 0.03, 2, i) end
  return join(list, E(0.5, 0.56, 0.46, 0.3, C.tie), E(0.5, 0.56, 0.4, 0.25, C.line), E(0.5, 0.56, 0.32, 0.19, C.tie), E(0.5, 0.56, 0.13, 0.12, C.text), E(0.52, 0.56, 0.08, 0.09, C.soft), E(0.53, 0.56, 0.025, 0.08, C.bg))
end
F.rd_zal = function()
  local list = man({ wide = 0.13, hem = 0.74, skin = C.hi, coat = C.hi, trim = C.warn, legs = C.hi, boots = C.warn, noArm = true,
    back = { R(0.66, 0.38, 0.05, 0.3, C.warn) },
    body = { R(0.38, 0.4, 0.24, 0.012, C.warn), R(0.38, 0.46, 0.24, 0.012, C.warn), R(0.38, 0.52, 0.24, 0.012, C.warn), R(0.38, 0.58, 0.24, 0.012, C.warn) },
    head = { E(0.54, 0.17, 0.17, 0.16, C.hi), E(0.5, 0.1, 0.1, 0.05, C.warn), E(0.6, 0.18, 0.04, 0.04, C.text), E(0.61, 0.185, 0.015, 0.02, C.bg), R(0.44, 0.06, 0.16, 0.012, C.warn) } })
  return join(list, snake(C.hi, 0.5, 0.28, 0.58, 0.6, 0.07, 0.04, 0.05, 2.4), snake(C.warn, 0.6, 0.28, 0.5, 0.58, 0.07, 0.04, 0.05, 2.4, 1), snake(C.hi, 0.44, 0.28, 0.62, 0.5, 0.06, 0.04, 0.04, 2, 2), snake(C.warn, 0.66, 0.26, 0.46, 0.48, 0.06, 0.04, 0.04, 2, 3), E(0.55, 0.62, 0.05, 0.04, C.hi))
end
F.rd_nulliira = function()
  return driderOf({ ink = C.line, dark = C.tie, coat = C.text,
    chest = { R(0.5, 0.3, 0.1, 0.26, C.line) },
    hair = P(C.line, 0.44, 0.24, 0.44, 0.08, 0.56, 0.02, 0.7, 0.06, 0.7, 0.13, 0.56, 0.1, 0.5, 0.24),
    face = { R(0.6, 0.16, 0.06, 0.012, C.panel), R(0.56, 0.23, 0.08, 0.012, C.bg) },
    over = { P(C.blueTint, 0.66, 0.34, 0.74, 0.34, 0.74, 0.2, 0.7, 0.2), R(0.72, 0.14, 0.02, 0.1, C.blueTint), R(0.84, 0.28, 0.1, 0.2, C.redTint), R(0.85, 0.3, 0.08, 0.17, C.text) } })
end
F.rd_wyrm = function()
  -- flat on the wall, going up it sideways, as a gecko would
  return { R(0, 0, 0.14, 1, C.tie), R(0, 0.3, 0.14, 0.012, C.panel), R(0, 0.68, 0.14, 0.012, C.panel), snake(C.line, 0.3, 0.72, 0.5, 1, 0.12, 0.012, 0.07, 2), P(C.tie, 0.34, 0.5, 0.56, 0.18, 0.8, 0.26, 0.74, 0.48, 0.64, 0.42, 0.58, 0.58, 0.48, 0.5, 0.42, 0.64),
    snake(C.text, 0.3, 0.76, 0.42, 0.26, 0.2, 0.14, 0.05, 1), R(0.26, 0.42, 0.14, 0.012, C.tie), R(0.28, 0.5, 0.14, 0.012, C.tie), R(0.3, 0.58, 0.12, 0.012, C.tie),
    P(C.text, 0.34, 0.34, 0.1, 0.24, 0.1, 0.3, 0.32, 0.42), P(C.text, 0.26, 0.66, 0.1, 0.72, 0.1, 0.78, 0.28, 0.74), P(C.line, 0.13, 0.2, 0.02, 0.2, 0.13, 0.26), P(C.line, 0.13, 0.26, 0.04, 0.32, 0.13, 0.3), P(C.line, 0.13, 0.72, 0.04, 0.68, 0.13, 0.76),
    E(0.48, 0.18, 0.16, 0.12, C.text), P(C.text, 0.5, 0.12, 0.8, 0.2, 0.74, 0.28, 0.46, 0.28), R(0.5, 0.25, 0.26, 0.012, C.bg), E(0.44, 0.09, 0.07, 0.07, C.line), E(0.44, 0.09, 0.055, 0.055, C.info), E(0.45, 0.09, 0.018, 0.05, C.bg), E(0.58, 0.11, 0.05, 0.05, C.line), E(0.58, 0.11, 0.04, 0.04, C.info), E(0.585, 0.11, 0.012, 0.035, C.bg) }
end

local function armOf(ink, under, eye)
  local list = { snake(ink, 0.42, 1.1, 0.62, -0.1, 0.72, 0.28, 0.2, 1.5, 0), snake(under, 0.32, 1.1, 0.58, -0.1, 0.3, 0.09, 0.2, 1.5, 0) }
  for i = 0, 7 do
    local cx, cy, nx = along(0.42, 1.1, 0.62, -0.1, 0.2, 1.5, 0, 0.1 + i * 0.105)
    list = join(list, eye(cx + nx * (i % 2 == 0 and 0.07 or -0.06), cy, 0.075 - i * 0.006, i))
  end
  return list
end
F.fn_arm = function()
  return armOf(C.tie, C.panel, function(x, y, rx) return { E(x, y, rx + 0.016, rx * 0.8 + 0.016, C.line), E(x, y, rx, rx * 0.8, C.panel), P(C.soft, x - rx, y, x, y + rx * 0.3, x + rx, y, x, y + rx * 0.6) } end)
end

local function crateOf(ink, edge, over)
  return join({ R(0.1, 0.34, 0.8, 0.66, ink), R(0.1, 0.34, 0.8, 0.04, edge), R(0.1, 0.96, 0.8, 0.04, edge), R(0.1, 0.34, 0.05, 0.66, edge), R(0.85, 0.34, 0.05, 0.66, edge), P(edge, 0.14, 0.38, 0.2, 0.38, 0.86, 0.96, 0.8, 0.96) }, over)
end
--- A ship's lamp on its stand.
local function shipLamp(glass)
  return { R(0.47, 0.5, 0.06, 0.46, C.hi), R(0.3, 0.94, 0.4, 0.06, C.warn), R(0.3, 0.14, 0.4, 0.04, C.hi), R(0.34, 0.18, 0.32, 0.3, glass), R(0.42, 0.22, 0.08, 0.2, C.text), R(0.3, 0.46, 0.4, 0.05, C.hi), R(0.34, 0.18, 0.03, 0.3, C.warn), R(0.63, 0.18, 0.03, 0.3, C.warn), P(C.hi, 0.36, 0.14, 0.64, 0.14, 0.5, 0.02) }
end
prop("fn_lamp_r", 0.8, 0.5, function() return shipLamp(C.red) end)
prop("fn_lamp_g", 0.8, 0.5, function() return shipLamp(C.ok) end)
prop("fn_lamp_w", 0.8, 0.5, function() return shipLamp(C.line) end)
prop("fn_lamp", 0.9, 0.5, function()
  return join(chainDown(0.5, -0.04, 3, C.line, C.tie), { E(0.5, 0.62, 0.4, 0.36, C.blueTint), R(0.3, 0.38, 0.4, 0.05, C.tie), R(0.32, 0.43, 0.36, 0.42, C.soft), R(0.3, 0.85, 0.4, 0.05, C.tie), E(0.5, 0.62, 0.11, 0.13, C.text), R(0.44, 0.58, 0.04, 0.02, C.bg), R(0.53, 0.59, 0.04, 0.02, C.bg), E(0.5, 0.68, 0.03, 0.02, C.bg), R(0.32, 0.56, 0.36, 0.012, C.ok), R(0.32, 0.74, 0.36, 0.012, C.ok) })
end)
prop("fn_chair", 0.75, 0.5, function() return { R(0.3, 0.02, 0.06, 0.98, C.redTint), R(0.64, 0.02, 0.06, 0.98, C.redTint), R(0.3, 0.1, 0.4, 0.06, C.warn), R(0.3, 0.26, 0.4, 0.05, C.warn), R(0.3, 0.42, 0.4, 0.05, C.warn), R(0.26, 0.56, 0.48, 0.07, C.warn), R(0.26, 0.63, 0.06, 0.37, C.redTint), R(0.68, 0.63, 0.06, 0.37, C.redTint) } end)
prop("fn_cot", 0.85, 0.5, function()
  return { P(C.tie, 0.04, 0.72, 0.28, 0.72, 0.26, 1, 0.06, 1), R(0.04, 0.8, 0.24, 0.02, C.line), P(C.tie, 0.72, 0.72, 0.96, 0.72, 0.94, 1, 0.74, 1), R(0.72, 0.8, 0.24, 0.02, C.line), R(0.0, 0.62, 1, 0.1, C.panel), R(0.0, 0.62, 1, 0.02, C.warn), R(0.1, 0.5, 0.86, 0.13, C.line), R(0.1, 0.5, 0.86, 0.02, C.text), P(C.text, 0.1, 0.5, 0.22, 0.5, 0.1, 0.62), P(C.text, 0.84, 0.5, 0.96, 0.5, 0.96, 0.62) }
end)
prop("fn_crate", 0.5, 0.5, function()
  return crateOf(C.warn, C.redTint, { R(0.2, 0.56, 0.6, 0.14, C.warn), R(0.22, 0.59, 0.56, 0.02, C.bg), R(0.22, 0.65, 0.4, 0.02, C.bg), P(C.redTint, 0.06, 0.34, 0.92, 0.2, 0.94, 0.28, 0.08, 0.4) })
end)
prop("rd_crate", 0.9, 0.4, function()
  local words = {}
  for i = 0, 4 do words[#words + 1] = R(0.2 + (i % 2) * 0.2, 0.44 + i * 0.1, 0.34, 0.03, i % 2 == 0 and C.red or C.bg) end
  return crateOf(C.tie, C.redTint, words)
end)
prop("fn_ladder", 0.95, 0.5, function()
  return { R(0.48, 0, 0.04, 0.5, C.line), R(0.53, 0.02, 0.02, 0.44, C.warn), E(0.56, 0.42, 0.04, 0.04, C.hi), R(0.44, 0.48, 0.12, 0.08, C.hi), P(C.hi, 0.46, 0.56, 0.54, 0.56, 0.54, 0.76, 0.4, 0.92, 0.26, 0.84, 0.28, 0.72, 0.34, 0.78, 0.44, 0.72) }
end)
prop("fn_tin", 0.9, 0.5, function()
  return { R(0.5, 0.34, 0.44, 0.3, C.tie), R(0.5, 0.48, 0.44, 0.02, C.panel), R(0.58, 0.02, 0.32, 0.32, C.tie), R(0.58, 0.16, 0.32, 0.02, C.panel), R(0.68, 0.14, 0.1, 0.05, C.red), R(0.04, 0.54, 0.62, 0.05, C.warn), P(C.line, 0.1, 0.59, 0.14, 0.59, 0.6, 1, 0.56, 1), P(C.line, 0.56, 0.59, 0.6, 0.59, 0.14, 1, 0.1, 1),
    R(0.16, 0.42, 0.2, 0.12, C.line), R(0.16, 0.42, 0.2, 0.02, C.text), R(0.42, 0.5, 0.18, 0.04, C.text), R(0.47, 0.44, 0.08, 0.08, C.tie) }
end)
prop("rd_fall", 1, 0.05, function()
  local list = { R(0, 0, 1, 1, C.line) }
  for i = 0, 22 do list[#list + 1] = E((i * 37 % 100) / 100, (i * 53 % 100) / 100, 0.11 + (i % 3) * 0.03, 0.06 + (i % 2) * 0.03, i % 3 == 0 and C.tie or C.text) end
  return join(list, P(C.text, 0, 1, 0.5, 0.74, 1, 1))
end)
prop("rd_gemwall", 1, 0.05, function()
  local list = { R(0, 0, 1, 1, C.blueTint), E(0.5, 0.56, 0.13, 0.3, C.line), E(0.5, 0.26, 0.09, 0.09, C.text) }
  for i = 0, 7 do
    list = join(list, crystal(i % 2 == 0 and C.text or C.info, C.text, 0.08 + i * 0.12 + (i > 3 and 0.03 or 0), 1.02, 0.07, 0.42 + (i * 5 % 4) * 0.13, 0))
    list[#list + 1] = P(i % 2 == 0 and C.info or C.line, 0.0 + i * 0.13, 0, 0.13 + i * 0.13, 0, 0.07 + i * 0.13, 0.26 + (i * 3 % 4) * 0.08)
  end
  return list
end)
prop("rd_lens", 1, 0.45, function()
  return { R(0.42, 0.78, 0.16, 0.22, C.redTint), R(0.24, 0.94, 0.52, 0.06, C.bg), R(0.72, 0.3, 0.2, 0.2, C.panel), R(0.92, 0.34, 0.06, 0.12, C.tie), E(0.46, 0.42, 0.38, 0.4, C.redTint), E(0.46, 0.42, 0.33, 0.35, C.text), E(0.46, 0.42, 0.28, 0.3, C.info), P(C.text, 0.3, 0.2, 0.38, 0.18, 0.24, 0.5, 0.2, 0.42), E(0.1, 0.42, 0.03, 0.05, C.warn), E(0.82, 0.42, 0.03, 0.05, C.warn) }
end)
prop("rd_log", 0.8, 0.7, function()
  return { P(C.tie, 0.3, 0.36, 0.62, 0.36, 0.66, 0.8, 0.26, 0.8), R(0.3, 0.42, 0.32, 0.02, C.text), R(0.28, 0.56, 0.36, 0.02, C.text), R(0.3, 0.78, 0.5, 0.1, C.panel), R(0.74, 0.8, 0.1, 0.2, C.panel), P(C.line, 0.3, 0.86, 0.46, 0.86, 0.46, 1, 0.2, 1), R(0.72, 0.94, 0.18, 0.06, C.text),
    E(0.46, 0.22, 0.13, 0.14, C.line), P(C.tie, 0.32, 0.22, 0.34, 0.06, 0.58, 0.06, 0.6, 0.22), R(0.34, 0.16, 0.24, 0.02, C.text), R(0.42, 0.22, 0.06, 0.04, C.bg), R(0.5, 0.22, 0.06, 0.04, C.bg), R(0.64, 0.66, 0.16, 0.12, C.red), R(0.66, 0.68, 0.12, 0.08, C.text), R(0.56, 0.5, 0.08, 0.2, C.tie) }
end)
prop("rd_page", 0.8, 0.5, function()
  return { R(0.58, 0.3, 0.05, 0.7, C.redTint), R(0.88, 0.3, 0.05, 0.7, C.redTint), R(0.58, 0.3, 0.35, 0.04, C.warn), R(0.56, 0.62, 0.4, 0.05, C.warn), R(0.6, 0.67, 0.04, 0.33, C.redTint), R(0.86, 0.67, 0.04, 0.33, C.redTint), P(C.text, 0.08, 0.9, 0.46, 0.86, 0.5, 0.96, 0.42, 1, 0.12, 1), R(0.16, 0.92, 0.22, 0.012, C.tie), R(0.16, 0.95, 0.16, 0.012, C.tie) }
end)
prop("rd_thread", 0.6, 0.5, function()
  return { P(C.redTint, 0.14, 1, 0.24, 1, 0.56, 0.1, 0.46, 0.08), P(C.warn, 0.16, 1, 0.18, 1, 0.5, 0.1, 0.46, 0.08), P(C.warn, 0.42, 0.04, 0.56, 0.02, 0.5, 0.2, 0.56, 0.1, 0.46, 0.2), R(0.28, 0.5, 0.2, 0.05, C.bg), E(0.38, 0.52, 0.05, 0.05, C.bg), R(0.4, 0.54, 0.02, 0.2, C.bg), R(0.34, 0.54, 0.02, 0.14, C.bg) }
end)
prop("rd_weight", 0.85, 0.5, function()
  local list = F.ud_basket()
  for i = 0, 8 do list[#list + 1] = E(0.26 + i * 0.06, 0.44 - (i % 3) * 0.03, 0.05, 0.04, i % 2 == 0 and C.tie or C.line) end
  return list
end)

-- ---------------------------------------------------------------- how they stand on a map, where it isn't a full square
M.MAP_SIZE = { rn_giving = 1.5, rn_clot = 0.6, rn_crab = 0.9, fn_arm = 1.7, rd_rover = 0.55, rd_shed = 0.8, rd_wyrm = 1.1, rn_hollowling = 1.2, rs_cart = 1.1, rs_bosun = 1.1, rs_kite = 0.7, rd_nulliira = 1.1,
   hr_crab = 0.55, hr_mite = 0.6, px_bat = 0.5, sn_cliff_bat = 0.7, ud_bat = 0.7, sn_nestling = 0.55, hr_kite = 0.7, hr_leech = 0.5, px_leech = 0.7, em_moth = 0.4, em_owlet = 0.4, sn_cask_louse = 0.6, ud_cinder = 0.7, hr_snapper = 0.7, vt_grub = 0.6, ud_pitworm = 0.8, ud_lamprey = 0.9,
  hr_dividend = 1.5, px_alderman = 1.4, ud_mother = 1.6, vt_bookworm = 1.6, vt_qarhuul = 1.7, em_breath = 1.3, em_provost = 1.3, ud_grudge = 1.1, ud_matron = 1.2, ud_ruaryn = 1.2, ud_unsettled = 1.1, px_tusker = 1.1, ud_umber = 1.2, hr_grassback = 1.1, sn_barnabas = 1.1 }

return M
