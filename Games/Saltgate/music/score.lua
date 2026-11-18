-- score.lua
-- Turns SALTGATE's tracker-style track files into rows of speaker notes, and checks them on the way.
--
-- A track file returns:
--   ticks        ticks per step, cycled: { 3 } is straight 16ths at 100 BPM, { 4, 2 } swung 16ths at 100 BPM,
--                { 3, 2 } a light shuffle at 120 BPM, { 2 } straight 16ths at 150 BPM (20 ticks a second)
--   stepsPerBar  default 16; stepsPerBeat default 4
--   loop         true for music that repeats; loopFrom: the order index it repeats from (an intro plays once)
--   trim         a sting: it ends one beat after its last note, not at the end of its last bar
--   resume       a sting: when it ends, the loop it interrupted comes back
--   sync         tracks with the same sync group and bar length switch into the same bar of the phrase
--   voices       in priority order (the first ones win if notes have to be dropped):
--                { name = "lead", inst = "flute", vol = 0.7, shift = 0 }
--                a kit voice maps lowercase letters to hits: kit = { k = { "basedrum", 4, 1 }, h = { "hat", 18, 0.5 } }
--   patterns     name -> { voice = "C5 . Eb5 . | ..." }: one token a step, "|" is only for the eye
--   order        pattern names in play order
--
-- Tokens: "." rest; a note "C5", "Eb4", "F#3" (pitch space: F#3 is speaker pitch 0, F#5 is 24, whatever the
-- instrument's own octave); kit letters "k"; "+" joins notes on one step ("Eb4+G4", "k+h"); a trailing "!" is an
-- accent (x1.3), "'" a ghost (x0.5).

local M = {}

M.TICKS_PER_SECOND = 20
-- A CC:Tweaked speaker takes 8 notes a tick (max_notes_per_tick); music keeps 2 of them free for the game's effects.
M.MAX_NOTES = 6

M.INSTRUMENTS = {
  harp = true, bass = true, basedrum = true, snare = true, hat = true, bell = true, flute = true, chime = true,
  guitar = true, xylophone = true, iron_xylophone = true, cow_bell = true, didgeridoo = true, bit = true,
  banjo = true, pling = true,
}

-- How loud each note block sample is, evened out: a voice volume of 1 is about as loud on any instrument (the quiet
-- ones, bell, bit, chime and xylophone, cannot go louder than 1, so they stay a little under). Measured on the
-- vanilla samples, RMS over the first 0.3 s.
M.LEVEL = {
  bass = 0.48, basedrum = 0.34, cow_bell = 0.48, pling = 0.63, flute = 0.72, iron_xylophone = 0.74, didgeridoo = 0.73,
  snare = 0.8, harp = 1, banjo = 1, guitar = 1, hat = 1, bell = 1, bit = 1, chime = 1, xylophone = 1,
}

local LETTER ={ C = 6, D = 8, E = 10, F = 11, G = 13, A = 15, B = 17 }
local NAMES = { [0] = "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }

--- "C5" -> 18. nil if it is not a note name.
function M.pitch(name)
  local l, acc, oct = string.match(name, "^([A-G])([b#]?)(%d)$")
  if not l then return nil end
  local p = LETTER[l] + (tonumber(oct) - 4) * 12
  if acc == "#" then p = p + 1 elseif acc == "b" then p = p - 1 end
  return p
end

--- 18 -> "C5" (any whole number, so transposing can leave the range and be caught later).
function M.name(p)
  return NAMES[(p + 6) % 12] .. (3 + math.floor((p + 6) / 12))
end

--- The tokens of a line, without the bar marks.
function M.tokens(line)
  local out = {}
  for tok in string.gmatch(line or "", "%S+") do
    if tok ~= "|" then out[#out + 1] = tok end
  end
  return out
end

--- A line with every note moved by semis (kit letters and rests stay).
function M.transpose(line, semis)
  return (string.gsub(line, "%S+", function(tok)
    if tok == "|" or tok == "." then return tok end
    local parts = {}
    for part in string.gmatch(tok, "[^+]+") do
      local note, mods = string.match(part, "^([A-G][b#]?%d)(.*)$")
      if note then part = M.name(M.pitch(note) + semis) .. mods end
      parts[#parts + 1] = part
    end
    return table.concat(parts, "+")
  end))
end

--- Lines joined end to end (bars in a row).
function M.join(...)
  return table.concat({ ... }, " | ")
end

--- A line n times over.
function M.rep(line, n)
  local t = {}
  for i = 1, n do t[i] = line end
  return table.concat(t, " | ")
end

--- A line moved later by n steps; what falls off the end comes round to the start (an echo of a whole loop).
function M.delay(line, n)
  local toks = M.tokens(line)
  local out = {}
  local len = #toks
  for i = 1, len do out[((i - 1 + n) % len) + 1] = toks[i] end
  return table.concat(out, " ")
end

--- Silence for n bars of 16 steps.
function M.rest(bars, steps)
  local t = {}
  for i = 1, bars * (steps or 16) do t[i] = "." end
  return table.concat(t, " ")
end

--- One bar per chord: each chord token put at the given steps of a 16-step bar (the rest are rests).
--   steps entries may be a number, or { step, mod } where mod is "!" or "'".
function M.comp(chords, steps, barSteps)
  local bars = {}
  for b, chord in ipairs(chords) do
    local bar = {}
    for i = 1, barSteps or 16 do bar[i] = "." end
    if chord ~= "." then
      for _, s in ipairs(steps) do
        local at, mod = s, ""
        if type(s) == "table" then at, mod = s[1], s[2] or "" end
        local tok = {}
        for part in string.gmatch(chord, "[^+]+") do tok[#tok + 1] = part .. mod end
        bar[at + 1] = table.concat(tok, "+")
      end
    end
    bars[b] = table.concat(bar, " ")
  end
  return table.concat(bars, " | ")
end

local function fail(name, where, msg)
  error("music track " .. tostring(name) .. ": " .. where .. ": " .. msg, 0)
end

--- One token -> list of { inst, pitch, vol }, or an error message.
local function parseToken(tok, voice)
  local notes = {}
  for part in string.gmatch(tok, "[^+]+") do
    local body, mods = string.match(part, "^([^!']+)([!']*)$")
    if not body then return nil, "bad token " .. tok end
    local mult = 1
    for c in string.gmatch(mods, ".") do
      if c == "!" then mult = mult * 1.3 else mult = mult * 0.5 end
    end
    local inst, pitch, vol
    if voice.kit then
      local hit = voice.kit[body]
      if not hit then return nil, "no kit hit '" .. body .. "'" end
      inst, pitch, vol = hit[1], hit[2], (voice.vol or 1) * (hit[3] or 1) * mult
    else
      local p = M.pitch(body)
      if not p then return nil, "not a note: " .. tok end
      inst, pitch, vol = voice.inst, p + (voice.shift or 0), (voice.vol or 1) * mult
    end
    if not M.INSTRUMENTS[inst] then return nil, "unknown instrument " .. tostring(inst) end
    if pitch < 0 or pitch > 24 or pitch ~= math.floor(pitch) then
      return nil, "pitch " .. tostring(pitch) .. " out of 0-24 (" .. tok .. ")"
    end
    vol = vol * (M.LEVEL[inst] or 1)
    if vol > 1 then vol = 1 end
    notes[#notes + 1] = { inst, pitch, vol }
  end
  return notes
end

--- A track file's table -> a compiled track, or an error naming the place.
-- Compiled: { name, loop, trim, resume, sync, enter, barTicks, beatTicks, bars, length, loopTick,
--             rows = { { tick = n, notes = { { inst, pitch, vol, prio } } } } }
function M.compile(def, name)
  name = name or def.name or "?"
  local ticks = def.ticks or { 3 }
  local spb = def.stepsPerBar or 16
  local spbeat = def.stepsPerBeat or 4
  if type(ticks) ~= "table" or #ticks == 0 then fail(name, "ticks", "need a list of ticks per step") end
  for _, t in ipairs(ticks) do
    if type(t) ~= "number" or t < 1 or t ~= math.floor(t) then fail(name, "ticks", "each step needs a whole number of ticks >= 1") end
  end
  if spb % #ticks ~= 0 or spbeat % #ticks ~= 0 then fail(name, "ticks", "the step cycle must fit a beat and a bar exactly") end
  local cycle = 0
  for _, t in ipairs(ticks) do cycle = cycle + t end
  local barTicks = cycle * spb / #ticks
  local beatTicks = cycle * spbeat / #ticks

  local voices = def.voices or {}
  if #voices == 0 then fail(name, "voices", "none") end
  local seen = {}
  for i, v in ipairs(voices) do
    if not v.name then fail(name, "voice " .. i, "no name") end
    if seen[v.name] then fail(name, "voice " .. v.name, "named twice") end
    seen[v.name] = true
    if not v.kit and not M.INSTRUMENTS[v.inst] then fail(name, "voice " .. v.name, "unknown instrument " .. tostring(v.inst)) end
    if v.vol and (v.vol < 0 or v.vol > 1) then fail(name, "voice " .. v.name, "volume must be 0-1 (more only widens the range)") end
  end

  local order = def.order or {}
  if #order == 0 then fail(name, "order", "empty") end
  local patterns = def.patterns or {}
  local rows = {}
  local step, tick = 0, 0
  local barStartOf = {}
  local totalBars = 0
  for oi, pname in ipairs(order) do
    local pat = patterns[pname]
    if not pat then fail(name, "order " .. oi, "no pattern " .. tostring(pname)) end
    for vname in pairs(pat) do
      if not seen[vname] then fail(name, "pattern " .. pname, "line for unknown voice " .. tostring(vname)) end
    end
    local len
    local toks = {}
    for _, v in ipairs(voices) do
      if pat[v.name] then
        toks[v.name] = M.tokens(pat[v.name])
        local n = #toks[v.name]
        if len and n ~= len then
          fail(name, "pattern " .. pname, "voice " .. v.name .. " has " .. n .. " steps, others " .. len)
        end
        len = n
      end
    end
    if not len or len == 0 then fail(name, "pattern " .. pname, "no steps") end
    if len % spb ~= 0 then fail(name, "pattern " .. pname, len .. " steps is not whole bars of " .. spb) end
    barStartOf[oi] = tick
    totalBars = totalBars + len / spb
    for s = 1, len do
      local notes = {}
      for prio, v in ipairs(voices) do
        local tok = toks[v.name] and toks[v.name][s]
        if tok and tok ~= "." and tok ~= "-" then
          local got, err = parseToken(tok, v)
          if not got then
            fail(name, "pattern " .. pname .. ", voice " .. v.name .. ", bar " .. (math.floor((s - 1) / spb) + 1)
              .. ", step " .. ((s - 1) % spb + 1), err)
          end
          for _, n in ipairs(got) do
            n[4] = prio
            notes[#notes + 1] = n
          end
        end
      end
      if #notes > M.MAX_NOTES then
        fail(name, "pattern " .. pname .. ", bar " .. (math.floor((s - 1) / spb) + 1) .. ", step " .. ((s - 1) % spb + 1),
          #notes .. " notes at once (at most " .. M.MAX_NOTES .. ")")
      end
      if #notes > 0 then rows[#rows + 1] = { tick = tick, notes = notes } end
      tick = tick + ticks[(step % #ticks) + 1]
      step = step + 1
    end
  end

  local length = tick
  if def.trim and #rows > 0 then
    length = math.min(tick, rows[#rows].tick + beatTicks)
  end
  local loopTick = 0
  if def.loopFrom then
    loopTick = barStartOf[def.loopFrom]
    if not loopTick then fail(name, "loopFrom", "no order entry " .. tostring(def.loopFrom)) end
  end
  if #rows == 0 then fail(name, "rows", "no notes at all") end

  return {
    name = name,
    loop = def.loop and true or false,
    trim = def.trim and true or false,
    resume = def.resume and true or false,
    sync = def.sync,
    enter = def.enter or (def.loop and "bar" or "beat"),
    mood = def.mood,
    barTicks = barTicks,
    beatTicks = beatTicks,
    bars = totalBars,
    length = length,
    loopTick = loopTick,
    rows = rows,
  }
end

return M
