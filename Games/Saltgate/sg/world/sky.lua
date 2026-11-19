-- world/sky.lua
-- The day and the weather, as palette. The terminal has 16 colours and the world uses them by name, so the whole look
-- of the hour is a table of 16 RGB values that is swapped as the day goes: dawn, day, dusk, night, and in between.
--
-- What each slot means in the world (see chunkmodel.lua):
--   purple, magenta, pink          the sky from the top down to the horizon (never on the ground)
--   lightBlue                      windows and lamps: blue glass by day, lit by dusk
--   everything else                the ground, walls, roofs, water, cars: tinted by the hour
-- Pure apart from the terminal given to apply().
--
--   sky.HOURS_PER_SECOND            the game clock's speed (a day is DAY_SECONDS)
--   sky.phaseOf(hour) -> "night" | "dawn" | "day" | "dusk"
--   sky.paletteAt(hour, weather) -> { name = 0xRRGGBB }   weather: { kind, mix } (see below)
--   sky.apply(term, palette, last) -> number of colours changed        last: the previous palette (skips unchanged)
--   sky.sunAt(hour) -> elevation (-1 .. 1), azimuth (radians)
--   sky.weather.new(rng) -> state;  sky.weather.update(state, dt) -> kind, previous (when it changes)
--   sky.WEATHER                     kind -> { dim, grey, fog, rain }

local M = {}

local floor = math.floor

M.DAY_SECONDS = 1200
M.HOURS_PER_SECOND = 24 / M.DAY_SECONDS

local NAMES = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray", "lightGray", "cyan", "purple",
  "blue", "brown", "green", "red", "black" }
M.NAMES = NAMES

-- keyframes: hour, then the colour of each slot at that hour
local KEY = {
  night = {
    white = 0x8E99B8, orange = 0x6A3A40, magenta = 0x161A44, lightBlue = 0xFFD470, yellow = 0x8A7A3C, lime = 0x2E5048, pink = 0x232766,
    gray = 0x2E3347, lightGray = 0x5A6280, cyan = 0x2C6A8C, purple = 0x0A0C24, blue = 0x141F4C, brown = 0x3C3040, green = 0x15332F,
    red = 0x7A2C3C, black = 0x07070C,
  },
  dawn = {
    white = 0xF2DDCC, orange = 0xE8944F, magenta = 0xC77096, lightBlue = 0xA6CBE0, yellow = 0xEBC66A, lime = 0x7BB065, pink = 0xF2A98E,
    gray = 0x585460, lightGray = 0xAD9F98, cyan = 0x40B4AC, purple = 0x5E5C96, blue = 0x305E9E, brown = 0x80503C, green = 0x30684C,
    red = 0xDC4C42, black = 0x17181E,
  },
  day = {
    white = 0xFAF6EC, orange = 0xE07A3F, magenta = 0x6AAAE8, lightBlue = 0x7DB4DC, yellow = 0xE8D68C, lime = 0x78C860, pink = 0xA8D6F4,
    gray = 0x62666F, lightGray = 0xB8B8B2, cyan = 0x3FC2BA, purple = 0x3F86D8, blue = 0x2D7AC4, brown = 0x8F5C42, green = 0x2F7C50,
    red = 0xD8413A, black = 0x1A1B22,
  },
  dusk = {
    white = 0xF2D6B6, orange = 0xE8803C, magenta = 0xD9467F, lightBlue = 0xF4C650, yellow = 0xF2BC4A, lime = 0x6FA454, pink = 0xF2A497,
    gray = 0x55505A, lightGray = 0xA8988A, cyan = 0x3A9C9C, purple = 0x5A4785, blue = 0x2C5088, brown = 0x7A4A38, green = 0x2A5A44,
    red = 0xD8413A, black = 0x17181E,
  },
}
M.KEYS = KEY

local TIMELINE = {
  { 0, "night" }, { 4.8, "night" }, { 6.3, "dawn" }, { 8.3, "day" }, { 16.0, "day" }, { 18.0, "dusk" }, { 19.8, "night" }, { 24, "night" },
}

function M.phaseOf(hour)
  hour = hour % 24
  if hour < 5 or hour >= 20.5 then return "night" end
  if hour < 7.3 then return "dawn" end
  if hour < 16.8 then return "day" end
  return "dusk"
end

local function rgb(v) return floor(v / 65536) % 256, floor(v / 256) % 256, v % 256 end
local function mix(a, b, t)
  local ar, ag, ab = rgb(a)
  local br, bg, bb = rgb(b)
  return floor(ar + (br - ar) * t + 0.5) * 65536 + floor(ag + (bg - ag) * t + 0.5) * 256 + floor(ab + (bb - ab) * t + 0.5)
end
local function scale(v, k)
  local r, g, b = rgb(v)
  return floor(math.min(255, r * k) + 0.5) * 65536 + floor(math.min(255, g * k) + 0.5) * 256 + floor(math.min(255, b * k) + 0.5)
end

M.WEATHER = {
  clear = { dim = 1, grey = 0, fog = 0, rain = 0 },
  cloudy = { dim = 0.88, grey = 0.55, fog = 0, rain = 0 },
  rain = { dim = 0.72, grey = 0.8, fog = 0.1, rain = 1 },
  storm = { dim = 0.55, grey = 0.9, fog = 0.2, rain = 2 },
  fog = { dim = 0.9, grey = 0.7, fog = 1, rain = 0 },
}
local SKY = { purple = true, magenta = true, pink = true }
local OVERCAST = { purple = 0x7C8694, magenta = 0x97A0AC, pink = 0xB2B8C0 }
local FOG = 0xBFC4CA

--- The 16 colours at an hour of the day under a kind of weather.
function M.paletteAt(hour, kind, flash)
  hour = hour % 24
  local a, b, t = TIMELINE[1], TIMELINE[2], 0
  for i = 1, #TIMELINE - 1 do
    if hour >= TIMELINE[i][1] and hour <= TIMELINE[i + 1][1] then
      a, b = TIMELINE[i], TIMELINE[i + 1]
      local span = b[1] - a[1]
      t = span > 0 and (hour - a[1]) / span or 0
      break
    end
  end
  local ka, kb = KEY[a[2]], KEY[b[2]]
  local w = M.WEATHER[kind or "clear"] or M.WEATHER.clear
  local night = M.nightness(hour)
  local out = {}
  for _, name in ipairs(NAMES) do
    local c = mix(ka[name], kb[name], t)
    if SKY[name] then
      local grey = w.grey
      if grey > 0 then
        local g = scale(OVERCAST[name], 1 - 0.7 * night)
        if w.fog > 0.5 then g = mix(g, scale(FOG, 1 - 0.75 * night), (name == "pink") and 1 or 0.7) end
        c = mix(c, g, grey)
      end
      if flash and flash > 0 then c = mix(c, 0xF2F4FF, flash) end
    else
      c = scale(c, w.dim)
      if w.fog > 0 then c = mix(c, scale(FOG, 1 - 0.8 * night), w.fog * 0.18) end
    end
    out[name] = c
  end
  return out
end

--- How dark it is: 0 in daylight, 1 at night (for stars, lamps, the moon).
function M.nightness(hour)
  hour = hour % 24
  if hour >= 20 or hour < 4.8 then return 1 end
  if hour >= 18 then return (hour - 18) / 2 end
  if hour < 6.5 then return 1 - (hour - 4.8) / 1.7 end
  return 0
end

--- The sun's height (-1 below the horizon .. 1 overhead) and where it is round the compass (radians).
function M.sunAt(hour)
  local a = ((hour - 6) / 12) * math.pi
  return math.sin(a), math.pi - a * 0.5
end

--- Set the terminal's palette. `last` is the palette applied before: only what changed is sent. Returns how many.
function M.apply(term, palette, last)
  if not term.setPaletteColour then return 0 end
  local n = 0
  for _, name in ipairs(NAMES) do
    local v = palette[name]
    if not last or last[name] ~= v then
      term.setPaletteColour(colors[name] or colours[name], v)
      n = n + 1
    end
  end
  return n
end

-- ---------------------------------------------------------------- weather
M.weather = {}

local CHANCES = {
  clear = { { "clear", 0.15 }, { "cloudy", 0.5 }, { "fog", 0.15 }, { "rain", 0.2 } },
  cloudy = { { "clear", 0.45 }, { "rain", 0.35 }, { "fog", 0.1 }, { "cloudy", 0.1 } },
  rain = { { "cloudy", 0.5 }, { "storm", 0.2 }, { "clear", 0.2 }, { "rain", 0.1 } },
  storm = { { "rain", 0.7 }, { "cloudy", 0.3 } },
  fog = { { "clear", 0.6 }, { "cloudy", 0.4 } },
}
local LENGTH = { clear = { 120, 260 }, cloudy = { 60, 140 }, rain = { 50, 130 }, storm = { 25, 60 }, fog = { 50, 110 } }

function M.weather.new(rng, kind)
  kind = kind or "clear"
  local l = LENGTH[kind]
  return { kind = kind, left = l[1] + rng() * (l[2] - l[1]), rng = rng, forced = false }
end

--- Count the weather down; when its time is up pick the next. Returns kind, previous when it changes.
function M.weather.update(state, dt)
  if state.forced then return nil end
  state.left = state.left - dt
  if state.left > 0 then return nil end
  local r = state.rng()
  local acc = 0
  local next_ = "clear"
  for _, c in ipairs(CHANCES[state.kind]) do
    acc = acc + c[2]
    if r <= acc then next_ = c[1] break end
  end
  local previous = state.kind
  local l = LENGTH[next_]
  state.kind = next_
  state.left = l[1] + state.rng() * (l[2] - l[1])
  if next_ ~= previous then return next_, previous end
  return nil
end

return M
