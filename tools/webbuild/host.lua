-- host.lua
-- Built and published by .github/workflows/publish-web.yml on every push that touches the game.
-- A stand-in for CC:Tweaked, written for plain Lua 5.1. It runs before the game, inside the browser's Lua, and gives the
-- real program the globals a computer would: term, peripheral, colors, os, fs, textutils, settings, shell, parallel, require.
-- The page never calls into the game. It calls __web.step with the time and any taps, the game's coroutine runs until
-- it waits for its next event, and step returns a string of everything the game did (see the record list at `flush`).
-- That one way in and out is why this needs nothing from the Lua C API beyond load and call.

local native = {
  pcall = pcall, type = type, tostring = tostring, tonumber = tonumber, select = select, error = error,
  create = coroutine.create, resume = coroutine.resume, yield = coroutine.yield, status = coroutine.status,
  loadstring = loadstring, setfenv = setfenv, date = os.date, clock = os.clock, time = os.time,
  traceback = debug.traceback, sethook = debug.sethook,
}
local type, tostring, tonumber, select, floor = type, tostring, tonumber, select, math.floor
local concat, unpack = table.concat, unpack
local sbyte, schar, ssub, srep, sformat = string.byte, string.char, string.sub, string.rep, string.format

__web = {}
local out, outN = {}, 0
local function emit(s) outN = outN + 1; out[outN] = s end

local nowMs, tzMs = 0, 0
local booted = false -- the first thing drawn ends boot

-- ------------------------------------------------------------------ Lua differences

-- CC:Tweaked's Cobalt can yield across pcall. Real 5.1 can't, and the shell waits for events inside pcall(main). So pcall
-- here runs its function in a coroutine of its own and passes any yield on up. Results and errors look the same.
local lastError, lastTrace

local function guarded(co, ...)
  if native.status(co) == "dead" then
    if (...) == false then
      local message = select(2, ...)
      if message ~= lastError then lastError, lastTrace = message, native.traceback(co) end
    end
    return ...
  end
  return guarded(co, native.resume(co, native.yield(select(2, ...))))
end

-- CraftOS kills a program that goes this long without yielding, so a loop here can't freeze the tab.
local STALL_SECONDS = 8
local stepStart = 0

local function stallCheck()
  if native.clock() - stepStart > STALL_SECONDS then
    stepStart = native.clock() -- the shell's last save on the way out gets a turn of its own
    error("Too long without yielding", 2)
  end
end

-- debug.sethook keeps its function per coroutine, so each new one needs its own.
local function newCoroutine(f)
  local co = native.create(f)
  native.sethook(co, stallCheck, "", 5000000)
  return co
end

function coroutine.create(f) return newCoroutine(f) end
function coroutine.wrap(f)
  local co = newCoroutine(f)
  return function(...)
    local function pass(ok, ...)
      if not ok then error((...), 0) end
      return ...
    end
    return pass(native.resume(co, ...))
  end
end

function pcall(f, ...)
  if type(f) ~= "function" then return native.pcall(f, ...) end
  local co = newCoroutine(f)
  return guarded(co, native.resume(co, ...))
end

local function xguarded(handler, co, ...)
  if native.status(co) == "dead" then
    if (...) == false then return false, handler((select(2, ...))) end
    return ...
  end
  return xguarded(handler, co, native.resume(co, native.yield(select(2, ...))))
end

function xpcall(f, handler, ...)
  local co = newCoroutine(f)
  return xguarded(handler, co, native.resume(co, ...))
end

-- The 5.2 parts of Cobalt that CraftOS leans on.
function table.pack(...) return { n = select("#", ...), ... } end
table.unpack = unpack

function load(chunk, name, _, env)
  if type(chunk) == "function" then
    local parts = {}
    while true do
      local piece = chunk()
      if not piece or piece == "" then break end
      parts[#parts + 1] = piece
    end
    chunk = concat(parts)
  end
  local fn, err = native.loadstring(chunk, name or "=load")
  if not fn then return nil, err end
  if env then native.setfenv(fn, env) end
  return fn
end

-- ------------------------------------------------------------------ colors

colors = {
  white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32, pink = 64, gray = 128,
  lightGray = 256, cyan = 512, purple = 1024, blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768,
}
colors.grey, colors.lightGrey = colors.gray, colors.lightGray

local HEX = "0123456789abcdef"
local function slot(color)
  local i = 0
  while color > 1 do color = floor(color / 2); i = i + 1 end
  return i
end

function colors.toBlit(color) local i = slot(color) + 1; return ssub(HEX, i, i) end
function colors.fromBlit(c) local i = tonumber(c, 16); return i and 2 ^ i or nil end
function colors.packRGB(r, g, b)
  return floor(r * 255 + 0.5) * 65536 + floor(g * 255 + 0.5) * 256 + floor(b * 255 + 0.5)
end
function colors.unpackRGB(rgb)
  return floor(rgb / 65536) % 256 / 255, floor(rgb / 256) % 256 / 255, rgb % 256 / 255
end
function colors.rgb8(r, g, b)
  if g == nil then return colors.unpackRGB(r) end
  return colors.packRGB(r, g, b)
end
colours = colors

local DEFAULT_PALETTE = {
  0xF0F0F0, 0xF2B233, 0xE57FD8, 0x99B2F2, 0xDEDE6C, 0x7FCC19, 0xF2B2CC, 0x4C4C4C,
  0x999999, 0x4C99B2, 0xB266E5, 0x3366CC, 0x7F664C, 0x57A64E, 0xCC4C4C, 0x111111,
}

-- ------------------------------------------------------------------ the monitor

local W, H = 121, 81

local function newScreen(name, width, height, drawn)
  local self = {}
  local cx, cy, fg, bg, scale, blink = 1, 1, colors.white, colors.black, 1, false
  local palette = {}
  for i, rgb in ipairs(DEFAULT_PALETTE) do palette[i - 1] = rgb end

  local function put(text, fgs, bgs)
    if drawn then
      booted = true
      emit("B" .. cx .. "," .. cy .. "," .. #text .. "\n" .. text .. fgs .. bgs)
    end
    cx = cx + #text
  end

  function self.getSize() return width, height end
  function self.setTextScale(s) scale = s end
  function self.getTextScale() return scale end
  function self.setCursorPos(x, y) cx, cy = floor(x), floor(y) end
  function self.getCursorPos() return cx, cy end
  function self.setCursorBlink(on) blink = on end
  function self.getCursorBlink() return blink end
  function self.isColor() return true end
  function self.setTextColor(c) fg = c end
  function self.getTextColor() return fg end
  function self.setBackgroundColor(c) bg = c end
  function self.getBackgroundColor() return bg end

  function self.blit(text, fgs, bgs)
    if type(text) ~= "string" or type(fgs) ~= "string" or type(bgs) ~= "string" then
      error("bad argument (expected string)", 2)
    end
    if #text ~= #fgs or #text ~= #bgs then error("Arguments must be the same length", 2) end
    put(text, fgs, bgs)
  end

  function self.write(text)
    text = tostring(text)
    put(text, srep(colors.toBlit(fg), #text), srep(colors.toBlit(bg), #text))
  end

  function self.clear()
    if drawn then
      booted = true
      emit("C" .. slot(bg) .. "\n")
    end
  end

  function self.clearLine()
    local x = cx
    cx = 1
    put(srep(" ", width), srep(colors.toBlit(fg), width), srep(colors.toBlit(bg), width))
    cx = x
  end

  function self.scroll(n)
    if drawn then emit("R" .. floor(n) .. "," .. slot(bg) .. "\n") end
  end

  function self.setPaletteColor(color, r, g, b)
    local i, rgb = slot(color), r
    if g then rgb = colors.packRGB(r, g, b) end
    palette[i] = rgb
    if drawn then emit("P" .. i .. "," .. floor(rgb) .. "\n") end
  end

  function self.getPaletteColor(color) return colors.unpackRGB(palette[slot(color)]) end
  function self.nativePaletteColor(color) return colors.unpackRGB(DEFAULT_PALETTE[slot(color) + 1]) end

  self.setTextColour, self.getTextColour = self.setTextColor, self.getTextColor
  self.setBackgroundColour, self.getBackgroundColour = self.setBackgroundColor, self.getBackgroundColor
  self.isColour, self.setPaletteColour, self.getPaletteColour = self.isColor, self.setPaletteColor, self.getPaletteColor
  self.nativePaletteColour = self.nativePaletteColor
  return self
end

local MONITOR, SPEAKER = "monitor_0", "speaker_0"
local monitor = newScreen(MONITOR, W, H, true)

-- ------------------------------------------------------------------ the speaker

-- A sound's resource id says little, but sound_picks names each one: step, coin, heal, mon_rat_hurt. The page's
-- synth goes by that name, so the id is turned back into it here.
local pickOf

local function pickName(id)
  if not pickOf then
    pickOf = {}
    local ok, picks = native.pcall(require, "lib.sound_picks")
    if ok and type(picks) == "table" then
      local names = {}
      for name in pairs(picks) do names[#names + 1] = name end
      table.sort(names)
      -- the opening's names first: its music has to be known by name, and where it shares a sound the synth's kind for
      -- the opening suits the other use as well
      for _, intro in ipairs({ true, false }) do
        for _, name in ipairs(names) do
          local id2 = picks[name][1]
          if id2 and not pickOf[id2] and (name:sub(1, 6) == "intro_") == intro then pickOf[id2] = name end
        end
      end
    end
  end
  return pickOf[id] or id
end

local speaker = {}
function speaker.playSound(id, volume, pitch)
  emit("S" .. sformat("%.2f,%.2f,", volume or 1, pitch or 1) .. pickName(id) .. "\n")
  return true
end
function speaker.playNote(_, volume, pitch)
  emit("S" .. sformat("%.2f,%.2f,note\n", volume or 1, 2 ^ (((pitch or 12) - 12) / 12)))
  return true
end
function speaker.playAudio() return true end
function speaker.stop() emit("S1.00,1.00,__stop\n") end -- the page's synth ends its music

-- ------------------------------------------------------------------ peripheral

local attached = { [MONITOR] = { "monitor", monitor }, [SPEAKER] = { "speaker", speaker } }

peripheral = {}
function peripheral.getNames() return { MONITOR, SPEAKER } end
function peripheral.isPresent(name) return attached[name] ~= nil end
function peripheral.getType(name)
  if type(name) == "table" then return nil end
  local p = attached[name]
  return p and p[1] or nil
end
function peripheral.hasType(name, kind)
  local p = attached[name]
  if not p then return nil end
  return p[1] == kind
end
function peripheral.getMethods(name)
  local p, list = attached[name], {}
  if not p then return nil end
  for k in pairs(p[2]) do list[#list + 1] = k end
  return list
end
function peripheral.wrap(name)
  local p = attached[name]
  return p and p[2] or nil
end
function peripheral.call(name, method, ...)
  local p = attached[name]
  if not p then error("No peripheral attached", 2) end
  return p[2][method](...)
end
function peripheral.find(kind, filter)
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    local p = attached[name]
    if p[1] == kind and (not filter or filter(name, p[2])) then found[#found + 1] = p[2] end
  end
  return unpack(found)
end
function peripheral.getName(wrapped)
  for name, p in pairs(attached) do
    if p[2] == wrapped then return name end
  end
  error("Not a peripheral", 2)
end

-- ------------------------------------------------------------------ term and printing

local terminal = newScreen("terminal", 51, 19, false)
local current = terminal

term = {}
for name, fn in pairs(terminal) do term[name] = fn end
function term.current() return current end
function term.native() return terminal end
function term.redirect(target)
  local old = current
  current = target
  return old
end

local function logLine(text)
  emit("L" .. #text .. "\n" .. text)
end

function write(text)
  logLine(tostring(text))
  return 0
end

function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  logLine(concat(parts, " "))
  return 1
end

function printError(...) print(...) end
function read() return "" end

-- ------------------------------------------------------------------ fs

local bundled, written, dirty, dirs = {}, {}, {}, { [""] = true }
local DELETED = {} -- bundled files can't really go, so a delete only hides them

local function clean(path)
  path = tostring(path):gsub("\\", "/")
  local parts = {}
  for piece in path:gmatch("[^/]+") do
    if piece == ".." then parts[#parts] = nil elseif piece ~= "." then parts[#parts + 1] = piece end
  end
  return concat(parts, "/")
end

local function contents(path)
  local text = written[path]
  if text == DELETED then return nil end
  return text or bundled[path]
end

local function noteDirs(path)
  while true do
    path = path:match("^(.*)/[^/]*$")
    if not path or dirs[path] then return end
    dirs[path] = true
  end
end

local function store(path, text)
  written[path] = text
  dirty[path] = true
  noteDirs(path)
end

fs = {}
function fs.combine(a, ...)
  local all = { a, ... }
  return clean(concat(all, "/"))
end
function fs.getName(path) path = clean(path); return path:match("([^/]*)$") end
function fs.getDir(path)
  path = clean(path)
  return path:match("^(.*)/[^/]*$") or ""
end
function fs.exists(path) path = clean(path); return contents(path) ~= nil or dirs[path] == true end
function fs.isDir(path) return dirs[clean(path)] == true end
function fs.isReadOnly() return false end
function fs.getDrive() return "hdd" end
function fs.getFreeSpace() return 1000000 end
function fs.getCapacity() return 1000000 end
function fs.getSize(path)
  local text = contents(clean(path))
  if not text then error("/" .. clean(path) .. ": No such file", 2) end
  return #text
end
function fs.makeDir(path) path = clean(path); dirs[path] = true; noteDirs(path) end

function fs.list(path)
  path = clean(path)
  if not dirs[path] then error("/" .. path .. ": Not a directory", 2) end
  local prefix, found, names = path == "" and "" or (path .. "/"), {}, {}
  local function consider(full)
    if ssub(full, 1, #prefix) == prefix then
      local name = ssub(full, #prefix + 1):match("^[^/]+")
      if name then found[name] = true end
    end
  end
  for full in pairs(bundled) do if contents(full) then consider(full) end end
  for full, text in pairs(written) do if text ~= DELETED then consider(full) end end
  for full in pairs(dirs) do consider(full) end
  for name in pairs(found) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function fs.delete(path)
  path = clean(path)
  if bundled[path] then
    store(path, DELETED)
  elseif written[path] then
    written[path] = nil
    dirty[path] = true
  end
end

function fs.copy(from, to)
  from, to = clean(from), clean(to)
  local text = contents(from)
  if not text then error("/" .. from .. ": No such file", 2) end
  if contents(to) then error("/" .. to .. ": File exists", 2) end
  store(to, text)
end

function fs.move(from, to)
  fs.copy(from, to)
  fs.delete(from)
end

function fs.open(path, mode)
  path = clean(path)
  mode = mode or "r"
  local kind = ssub(mode, 1, 1)
  local binary = ssub(mode, 2, 2) == "b"
  local closed = false
  local handle = {}
  local function check()
    if closed then error("attempt to use a closed file", 2) end
  end
  function handle.close() check(); closed = true end

  if kind == "r" then
    local text = contents(path)
    if not text then return nil, "/" .. path .. ": No such file" end
    local at = 1
    function handle.readAll()
      check()
      if at > #text then return at == 1 and "" or nil end
      local rest = ssub(text, at)
      at = #text + 1
      return rest
    end
    function handle.readLine(keep)
      check()
      if at > #text then return nil end
      local stop = text:find("\n", at, true)
      local line = ssub(text, at, stop and (keep and stop or stop - 1) or #text)
      at = (stop or #text) + 1
      return line
    end
    function handle.read(n)
      check()
      if at > #text then return nil end
      if not n then
        local b = sbyte(text, at)
        at = at + 1
        return binary and b or schar(b)
      end
      local piece = ssub(text, at, at + n - 1)
      at = at + n
      return piece
    end
    return handle
  end

  if kind ~= "w" and kind ~= "a" then error("Unsupported mode", 2) end
  if dirs[path] then return nil, "/" .. path .. ": Is a directory" end
  local parts = {}
  if kind == "a" then parts[1] = contents(path) or "" end
  store(path, kind == "w" and "" or parts[1])
  local function save() store(path, concat(parts)) end
  function handle.write(value)
    check()
    parts[#parts + 1] = type(value) == "number" and binary and schar(value) or tostring(value)
  end
  function handle.writeLine(value)
    check()
    parts[#parts + 1] = tostring(value) .. "\n"
  end
  function handle.flush() check(); save() end
  function handle.close() check(); closed = true; save() end
  return handle
end

-- Lua's own io works on the wasm's memory disk. surface reads its font through this one, as it would in CraftOS.
io = {}
function io.open(path, mode)
  local handle, err = fs.open(path, mode or "r")
  if not handle then return nil, err end
  local file = {}
  function file:read(what)
    if type(what) == "number" then return handle.read(what) end
    if what == "*a" or what == "a" then return handle.readAll() or "" end
    return handle.readLine()
  end
  function file:write(...)
    for i = 1, select("#", ...) do handle.write((select(i, ...))) end
    return self
  end
  function file:close() handle.close() end
  return file
end

-- ------------------------------------------------------------------ loading code

local function loadFile(path)
  local text = contents(clean(path))
  if not text then return nil, "File not found" end
  return native.loadstring(text, "@" .. clean(path))
end

function loadfile(path)
  return loadFile(path)
end

function dofile(path)
  local fn, err = loadFile(path)
  if not fn then error(err .. ": " .. tostring(path), 2) end
  return fn()
end

local LOADING = {}

function require(name)
  local loaded = package.loaded
  local value = loaded[name]
  if value == LOADING then error("loop or previous error loading module '" .. name .. "'", 2) end
  if value ~= nil then return value end
  local base = name:gsub("%.", "/")
  for _, path in ipairs({ base, base .. ".lua", base .. "/init.lua" }) do
    if contents(path) then
      local fn, err = loadFile(path)
      if not fn then error(err, 0) end
      loaded[name] = LOADING
      local ok, result = pcall(fn, name, path)
      if not ok then
        loaded[name] = nil
        error(result, 0)
      end
      if result == nil then result = true end
      loaded[name] = result
      return result
    end
  end
  error("module '" .. name .. "' not found", 2)
end

-- ------------------------------------------------------------------ os

local timers, nextTimer = {}, 1
local events, first, last = {}, 1, 0
local ccOs = {}

local function enqueue(...)
  last = last + 1
  events[last] = { n = select("#", ...), ... }
end

function ccOs.epoch(kind)
  if kind == "local" then return nowMs + tzMs end
  if kind == "utc" or kind == nil then return nowMs end
  return (nowMs + tzMs) % 86400000
end
function ccOs.clock() return native.clock() end
function ccOs.time(arg)
  if type(arg) == "table" then return native.time(arg) end
  return ((nowMs + tzMs) % 86400000) / 3600000
end
function ccOs.day() return floor((nowMs + tzMs) / 86400000) end
function ccOs.date(format, at) return native.date(format or "%c", at or floor(nowMs / 1000)) end
function ccOs.getComputerID() return 1 end
function ccOs.computerID() return 1 end
function ccOs.getComputerLabel() return "BLIGHTMARE" end
function ccOs.computerLabel() return "BLIGHTMARE" end
function ccOs.setComputerLabel() end
function ccOs.version() return "CraftOS 1.8" end
function ccOs.startTimer(seconds)
  local id = nextTimer
  nextTimer = id + 1
  timers[id] = nowMs + (seconds or 0) * 1000
  return id
end
function ccOs.cancelTimer(id) timers[id] = nil end
function ccOs.setAlarm() return 0 end
function ccOs.cancelAlarm() end
function ccOs.queueEvent(...) enqueue(...) end
function ccOs.pullEventRaw(filter) return native.yield(filter) end
function ccOs.pullEvent(filter)
  local results = { n = 0 }
  local function hold(...)
    results = { n = select("#", ...), ... }
    return ...
  end
  hold(native.yield(filter))
  if results[1] == "terminate" then error("Terminated", 0) end
  return unpack(results, 1, results.n)
end
function ccOs.sleep(seconds)
  if not booted then return end -- nobody is watching yet: the shell's wait for slow peripherals needn't hold up the title
  local id = ccOs.startTimer(seconds or 0)
  repeat
    local _, done = ccOs.pullEvent("timer")
  until done == id
end
function ccOs.reboot() emit("Q\n"); while true do native.yield() end end
function ccOs.shutdown() emit("Q\n"); while true do native.yield() end end
os = ccOs
sleep = ccOs.sleep

-- ------------------------------------------------------------------ parallel, as CraftOS has it

local function runUntil(routines, limit)
  local count, living = #routines, #routines
  if count < 1 then return 0 end
  local filters = {}
  local data = { n = 0 }
  while true do
    for n = 1, count do
      local r = routines[n]
      if r and (filters[r] == nil or filters[r] == data[1] or data[1] == "terminate") then
        local ok, param = native.resume(r, unpack(data, 1, data.n))
        if not ok then
          if param ~= lastError then lastError, lastTrace = param, native.traceback(r) end
          error(param, 0)
        end
        filters[r] = param
        if native.status(r) == "dead" then
          routines[n] = nil
          living = living - 1
          if living <= limit then return n end
        end
      end
    end
    data = table.pack(ccOs.pullEventRaw())
  end
end

local function spawn(list)
  local routines = {}
  for i, fn in ipairs(list) do routines[i] = newCoroutine(fn) end
  return routines
end

parallel = {}
function parallel.waitForAny(...) return runUntil(spawn({ ... }), select("#", ...) - 1) end
function parallel.waitForAll(...) return runUntil(spawn({ ... }), 0) end

-- ------------------------------------------------------------------ textutils

textutils = {}

local RESERVED = {}
for word in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%a+") do
  RESERVED[word] = true
end

local function number(n)
  if n ~= n then return "0/0" end
  if n == math.huge then return "1/0" end
  if n == -math.huge then return "-1/0" end
  -- %d goes through a C long, which is 32 bits in wasm: an epoch time would wrap
  if n == floor(n) and n > -1e15 and n < 1e15 then return sformat("%.0f", n) end
  return sformat("%.17g", n)
end

local function serialiseValue(value, seen, opts, pad)
  local kind = type(value)
  if kind == "string" then return sformat("%q", value) end
  if kind == "number" then return number(value) end
  if kind == "boolean" or kind == "nil" then return tostring(value) end
  if kind ~= "table" then error("Cannot serialize type " .. kind, 0) end
  if seen[value] ~= nil then
    if seen[value] == false then error("Cannot serialize table with repeated entries", 0) end
    error("Cannot serialize table with recursive entries", 0)
  end
  seen[value] = true
  local parts, n = {}, 0
  local inner = opts.compact and "" or (pad .. "  ")
  local eq = opts.compact and "=" or " = "
  local length = #value
  for i = 1, length do
    n = n + 1
    parts[n] = inner .. serialiseValue(value[i], seen, opts, inner)
  end
  for k, v in pairs(value) do
    if not (type(k) == "number" and k >= 1 and k <= length and k == floor(k)) then
      local key
      if type(k) == "string" and not RESERVED[k] and k:match("^[%a_][%w_]*$") then
        key = k
      else
        key = "[" .. serialiseValue(k, seen, opts, inner) .. "]"
      end
      n = n + 1
      parts[n] = inner .. key .. eq .. serialiseValue(v, seen, opts, inner)
    end
  end
  seen[value] = opts.allow_repetitions and nil or false
  if n == 0 then return "{}" end
  if opts.compact then return "{" .. concat(parts, ",") .. "}" end
  return "{\n" .. concat(parts, ",\n") .. ",\n" .. pad .. "}"
end

function textutils.serialise(value, opts)
  return serialiseValue(value, {}, opts or {}, "")
end

function textutils.unserialise(text)
  local fn = native.loadstring("return " .. tostring(text), "unserialise")
  if not fn then return nil end
  native.setfenv(fn, {})
  local ok, result = pcall(fn)
  if ok then return result end
  return nil
end

local function jsonString(s)
  return '"' .. s:gsub('[%c"\\]', function(c) return sformat("\\u%04x", sbyte(c)) end) .. '"'
end

local function toJson(value)
  local kind = type(value)
  if kind == "string" then return jsonString(value) end
  if kind == "number" then return number(value) end
  if kind == "boolean" then return tostring(value) end
  if kind ~= "table" then return "null" end
  local parts = {}
  if #value > 0 or next(value) == nil then
    for i = 1, #value do parts[i] = toJson(value[i]) end
    return "[" .. concat(parts, ",") .. "]"
  end
  for k, v in pairs(value) do parts[#parts + 1] = jsonString(tostring(k)) .. ":" .. toJson(v) end
  return "{" .. concat(parts, ",") .. "}"
end

function textutils.serialiseJSON(value) return toJson(value) end
textutils.serialize, textutils.unserialize, textutils.serializeJSON = textutils.serialise, textutils.unserialise, textutils.serialiseJSON

-- ------------------------------------------------------------------ settings, shell and the odd stub

local stored = {}
settings = {}
function settings.get(name, default)
  local value = stored[name]
  if value == nil then return default end
  return value
end
function settings.set(name, value) stored[name] = value end
function settings.unset(name) stored[name] = nil end
function settings.clear() stored = {} end
function settings.define() end
function settings.undefine() end
function settings.load() return true end
function settings.save() return true end
function settings.getNames()
  local names = {}
  for name in pairs(stored) do names[#names + 1] = name end
  table.sort(names)
  return names
end

shell = { }
local running = ""
function shell.run(path, ...)
  local fn, err = loadFile(path)
  if not fn then
    printError(err)
    return false
  end
  local before = running
  running = clean(path)
  local ok, problem = pcall(fn, ...)
  running = before
  if not ok then
    if problem ~= nil and problem ~= "" then printError(problem) end
    return false
  end
  return true
end
function shell.dir() return "" end
function shell.setDir() end
function shell.path() return "." end
function shell.resolve(path) return clean(path) end
function shell.resolveProgram(path) return clean(path) end
function shell.getRunningProgram() return running end
function shell.exit() end

rednet = {}
function rednet.open() end
function rednet.close() end
function rednet.isOpen() return false end
function rednet.broadcast() end
function rednet.send() return false end

redstone = {}
function redstone.setOutput() end
function redstone.getOutput() return false end
function redstone.getInput() return false end
function redstone.getAnalogInput() return 0 end
function redstone.setAnalogOutput() end
rs = redstone

keys = setmetatable({}, { __index = function() return 0 end })
_HOST = "ComputerCraft 1.101.3 (Minecraft 1.18.2)"

-- ccvault and vhcc are left out on purpose: hw.lua asks `if not ccvault`, and with no vhcc_touch a tap has no name, so the
-- game's own keyboard asks for one. That's a computer with none of that fitted.

-- ------------------------------------------------------------------ the keyboard

-- A website has keys, a cabinet doesn't, so all of this lives here and the game never hears of it. A key becomes a tap: either a
-- real monitor_touch where a button is, or a touch on a blank cell that actionAt answers with the key's action. Either way it comes
-- in by the same road as a finger, through the shell's touch code, so the idle clock, the save, the redraw and the end of the
-- game all work as they do for a tap. Nothing runs here for someone who never presses a key.

local kb = {
  active = false, held = {}, pending = {}, targets = {}, cursor = nil, shownBox = "", hard = nil, soft = nil,
}

local DIR = { up = "up", w = "up", down = "down", s = "down", left = "left", a = "left", right = "right", d = "right" }
local CONFIRM = { enter = true, space = true, e = true }
local BACK = { escape = true, backspace = true, q = true }
local MENU = { m = true, tab = true }
local BLANK_X, BLANK_Y = 0, 0 -- no shell button sits here while a run is on the wall
local LARGE = 0.6 -- a target taking this share of the wall is a "tap anywhere", which isn't a choice
local SHELL_FIRST = { "actContinue", "actStart", "rulesDone", "actDone" }
local SHELL_BACK = { "back", "rulesDone", "actDone" }

--- The shell's own tables, once it has started.
local function shell_()
  if kb.app then return kb.app end
  local actions = package.loaded["lib.arcade.action"]
  if not actions then return nil end
  for i = 1, 16 do
    local name, value = debug.getupvalue(actions.bind, i)
    if not name then return nil end
    if name == "app" then
      if type(value) == "table" and value.plugin and value.env and value.env.L then kb.app = value end
      break
    end
  end
  return kb.app
end

local function wrapView(app)
  if kb.realAt then return end
  local view = app.plugin.view
  kb.realAt = view.actionAt
  function view.actionAt(L, s, px, py)
    if px == BLANK_X and py == BLANK_Y and kb.pending[1] then return table.remove(kb.pending, 1) end
    return kb.realAt(L, s, px, py)
  end
end

local function touch(px, py) enqueue("monitor_touch", MONITOR, px + 1, py + 1) end

local function send(action)
  kb.pending[#kb.pending + 1] = action
  touch(BLANK_X, BLANK_Y)
end

--- What kind of screen is up, and the run's state if there is one.
local function screenOf(app)
  local S = app.S
  local a = S.action
  local s = S.view == "action" and a and a.phase == "play" and a.state or nil
  if not s then return "shell" end
  local mode = s.mode
  if mode == "name" or mode == "walk" or mode == "world" then return mode, s end
  if mode == "menu" or mode == "shop" then return "choose", s end
  if mode == "talk" then
    local talk = app.plugin.rules.talk(s)
    if not talk then return "none", s end
    if talk.choices then return "choose", s end
    return talk.wait == "fade" and "none" or "tap", s
  end
  local b = s.battle
  if mode == "battle" and b and not b.result then
    if b.phase == "spoils" then return "tap", s end
    if b.phase == "cmd" or b.phase == "list" or b.phase == "target" then return "choose", s end
  end
  return "none", s
end

-- A hard change is a new screen, and the cursor starts again. A soft one is the same screen with something gone from it.
local function signatures(app, s)
  local rules = app.plugin.rules
  local mode = s.mode
  if mode == "battle" then
    local b = s.battle
    local _, list = package.loaded["games.blightmare.battle"].targets(s)
    return concat({ "b", b.phase, tostring(b.active), tostring(b.pick), tostring(b.pickId), tostring(b.list), tostring(b.top) }, ","),
      concat(list or {}, ",")
  elseif mode == "menu" then
    local m = s.menu
    return concat({ "m", tostring(m.page), tostring(m.top), tostring(m.who) }, ","), tostring(#rules.menuRows(s))
  elseif mode == "shop" then
    return "s," .. tostring(s.shop.top), tostring(#rules.shopRows(s))
  end
  local talk = rules.talk(s)
  return "t," .. tostring(talk and talk.say) .. "," .. concat(talk and talk.choices or {}, "|"), ""
end

local function actionKey(a)
  return concat({ a.kind, tostring(a.cmd), tostring(a.i), tostring(a.side), tostring(a.dir) }, ",")
end

local function byReading(p, q)
  if p.y ~= q.y then return p.y < q.y end
  return p.x < q.x
end

--- Tap every other cell of the wall and see what answers: whatever the game's screens are, that's what can be chosen.
local function scan(app, s)
  local L = app.env.L
  local at = kb.realAt
  local W, H = L.W, L.H
  local groups, list = {}, {}
  for y = 0, H - 1, 2 do
    for x = 0, W - 1, 2 do
      local a = at(L, s, x, y)
      if a and a.kind ~= "back" then
        local key = actionKey(a)
        local g = groups[key]
        if not g then
          g = { key = key, x0 = x, x1 = x, y0 = y, y1 = y, px = x, py = y }
          groups[key] = g
          list[#list + 1] = g
        end
        if x < g.x0 then g.x0 = x end
        if x > g.x1 then g.x1 = x end
        if y < g.y0 then g.y0 = y end
        if y > g.y1 then g.y1 = y end
      end
    end
  end
  local out = {}
  for _, g in ipairs(list) do
    -- the scan misses every other cell, so each edge may be one further out
    local function same(x, y)
      local a = x >= 0 and y >= 0 and x < W and y < H and at(L, s, x, y)
      return a and actionKey(a) == g.key
    end
    local midX, midY = floor((g.x0 + g.x1) / 2), floor((g.y0 + g.y1) / 2)
    if same(g.x0 - 1, midY) then g.x0 = g.x0 - 1 end
    if same(g.x1 + 1, midY) then g.x1 = g.x1 + 1 end
    if same(midX, g.y0 - 1) then g.y0 = g.y0 - 1 end
    if same(midX, g.y1 + 1) then g.y1 = g.y1 + 1 end
    local w, h = g.x1 - g.x0 + 1, g.y1 - g.y0 + 1
    if w * h <= W * H * LARGE then
      out[#out + 1] = { key = g.key, x = g.x0, y = g.y0, w = w, h = h, px = g.px, py = g.py }
    end
  end
  table.sort(out, byReading)
  if s.mode == "menu" or s.mode == "shop" then
    -- SAVE & QUIT is the shell's, not the game's, so it needs adding, or the keyboard can never leave
    for _, b in ipairs(app.env.walls[1].buttons) do
      if b.id == "actQuit" then
        out[#out + 1] = { key = "actQuit", x = b.x, y = b.y, w = b.w, h = b.h, px = b.x + 1, py = b.y + 1, shell = true }
      end
    end
  end
  return out
end

local function shellTargets(app)
  local out = {}
  local whole
  local W, H = app.env.W, app.env.H
  for _, b in ipairs(app.env.walls[1].buttons) do
    if b.enabled then
      local t = {
        key = b.id .. "," .. tostring(b.data), id = b.id, x = b.x, y = b.y, w = b.w, h = b.h,
        px = b.x + floor(b.w / 2), py = b.y + floor(b.h / 2),
      }
      if b.w * b.h > W * H * LARGE then whole = t else out[#out + 1] = t end
    end
  end
  table.sort(out, byReading)
  return out, whole
end

local function findKey(list, key)
  for _, t in ipairs(list) do
    if t.key == key then return t end
  end
  return nil
end

local function firstOf(list, shell)
  if shell then
    for _, id in ipairs(SHELL_FIRST) do
      for _, t in ipairs(list) do
        if t.id == id then return t end
      end
    end
  end
  return list[1]
end

--- Bring the cursor up to date with the wall. Only ever runs once a key has been used.
local function refresh(app)
  local screen, s = screenOf(app)
  local hard, soft
  if screen == "choose" then
    hard, soft = signatures(app, s)
  elseif screen == "shell" then
    local S = app.S
    local a = S.action
    hard = concat({ "shell", S.view, tostring(a and a.phase), tostring(a and a.reviewed) }, ",")
    local ids = {}
    for i, b in ipairs(app.env.walls[1].buttons) do ids[i] = b.id end
    soft = concat(ids, ",")
  else
    hard, soft = screen, ""
  end
  if hard == kb.hard and soft == kb.soft then return end
  local newScreen = hard ~= kb.hard
  kb.hard, kb.soft = hard, soft
  local keep = kb.cursor and kb.cursor.key
  kb.whole = nil
  if screen == "choose" then
    kb.targets = scan(app, s)
  elseif screen == "shell" then
    kb.targets, kb.whole = shellTargets(app)
  else
    kb.targets = {}
  end
  local kept = not newScreen and keep and findKey(kb.targets, keep)
  kb.cursor = kept or firstOf(kb.targets, screen == "shell")
end

--- The nearest target that way: distance along it, and twice as much for any distance across it. Up and down go round at the ends.
local function moveCursor(way)
  local from = kb.cursor
  if not from then return end
  local fx, fy = from.x + from.w / 2, from.y + from.h / 2
  local dx = way == "left" and -1 or way == "right" and 1 or 0
  local dy = way == "up" and -1 or way == "down" and 1 or 0
  local best, bestScore
  for _, t in ipairs(kb.targets) do
    if t ~= from then
      local cx, cy = t.x + t.w / 2 - fx, t.y + t.h / 2 - fy
      local along = cx * dx + cy * dy
      local across = math.abs(cx * dy) + math.abs(cy * dx)
      if along > 0 then
        local score = along + 2 * across
        if not bestScore or score < bestScore then best, bestScore = t, score end
      end
    end
  end
  if not best and dy ~= 0 then
    -- the far end, as straight across as there is
    for _, t in ipairs(kb.targets) do
      if t ~= from then
        local cx, cy = t.x + t.w / 2 - fx, t.y + t.h / 2 - fy
        local score = cy * dy * 1 + 2 * math.abs(cx)
        if not bestScore or score < bestScore then best, bestScore = t, score end
      end
    end
  end
  if best then kb.cursor = best end
end

local function press(t)
  touch(t.px, t.py)
end

local function chooseKey(s, name, kind, way, wasActive)
  if way then
    -- the first key only shows where the cursor is
    if wasActive then moveCursor(way) end
    return
  end
  if kind == "repeat" then return end
  if CONFIRM[name] then
    if kb.cursor then press(kb.cursor) end
    return
  end
  local n = tonumber(name)
  if n and n >= 1 then
    local t = kb.targets[n]
    if t and not t.shell then
      kb.cursor = t
      press(t)
    end
    return
  end
  local b = s.battle
  local canBack = s.mode == "menu" or s.mode == "shop" or (s.mode == "battle" and (b.phase == "list" or b.phase == "target"))
  if canBack and (BACK[name] or (MENU[name] and s.mode ~= "battle")) then send({ kind = "back" }) end
end

local function shellKey(name, kind, way, wasActive)
  if way then
    if wasActive then moveCursor(way) end
    return
  end
  if kind == "repeat" then return end
  if CONFIRM[name] then
    local t = kb.cursor or kb.whole
    if t then press(t) end
  elseif BACK[name] then
    for _, id in ipairs(SHELL_BACK) do
      for _, t in ipairs(kb.targets) do
        if t.id == id then
          press(t)
          return
        end
      end
    end
  end
end

local function worldSteer(s, dir)
  kb.sentFrom = s.wx .. "," .. s.wy
  send({ kind = "turn", dir = dir })
end

local function keyUp(app, way)
  local held = kb.held
  for i = #held, 1, -1 do
    if held[i] == way then table.remove(held, i) end
  end
  local screen, s = screenOf(app)
  if screen ~= "world" then return end
  if held[#held] then
    worldSteer(s, held[#held])
  else
    kb.stopWalk = true -- the turn may still be in the queue: a quick tap has to walk its tile first
  end
end

local function keyEvent(kind, name)
  local app = shell_()
  if not app then return end
  wrapView(app)
  local way = DIR[name]
  if kind == "up" then
    if way then keyUp(app, way) end
    return
  end
  local wasActive = kb.active
  kb.active = true
  if kind == "down" and way then
    local listed = false
    for _, h in ipairs(kb.held) do listed = listed or h == way end
    if not listed then kb.held[#kb.held + 1] = way end
  end
  refresh(app)
  local screen, s = screenOf(app)
  local rules = app.plugin.rules
  if screen == "name" then
    if kind == "repeat" then return end
    if #name == 1 and name:match("%l") then
      send({ kind = "pick", i = sbyte(name) - 96 })
    elseif name == "backspace" then
      send({ kind = "pick", i = rules.NAME_DELETE })
    elseif name == "enter" then
      send({ kind = "pick", i = rules.NAME_DONE })
    end
  elseif screen == "walk" then
    if way then
      send({ kind = "turn", dir = way })
    elseif kind == "down" and CONFIRM[name] then
      send({ kind = "act" })
    elseif kind == "down" and MENU[name] then
      send({ kind = "menu" })
    end
  elseif screen == "world" then
    if way then
      -- a repeat only picks the walk up again where it stopped, as a turn restarts the tile's clock. Pressing on against a
      -- wall would only bump, so that waits for a fresh press.
      kb.stopWalk = false
      local stopped = not s.heading and not s.route and #s.queue == 0 and kb.sentFrom ~= s.wx .. "," .. s.wy
      if kind == "down" or stopped then worldSteer(s, way) end
    elseif kind == "down" and MENU[name] then
      send({ kind = "menu" })
    end
  elseif screen == "tap" then
    if kind == "down" and (way or CONFIRM[name]) then send({ kind = "tap" }) end
  elseif screen == "choose" then
    chooseKey(s, name, kind, way, wasActive)
  elseif screen == "shell" then
    shellKey(name, kind, way, wasActive)
  end
end

local function pointerUsed()
  kb.active = false
  kb.cursor, kb.hard, kb.soft = nil, nil, nil
end

--- After the game has had its turn: stop a walk whose key is up, and tell the page where the cursor is.
local function keyboardStep()
  kb.pending = {}
  local app = kb.app
  if not app then return end
  if kb.stopWalk then
    local a = app.S.action
    local s = a and a.state
    if not s or s.mode ~= "world" then
      kb.stopWalk = false
    elseif #s.queue == 0 then
      kb.stopWalk = false
      if not s.route then s.heading = nil end
    end
  end
  local box = ""
  if kb.active then
    refresh(app)
    local c = kb.cursor
    if c then box = c.x .. "," .. c.y .. "," .. c.w .. "," .. c.h end
  end
  if box ~= kb.shownBox then
    kb.shownBox = box
    emit("K" .. (box == "" and "0,0,0,0" or box) .. "\n")
  end
end

-- ------------------------------------------------------------------ the phone panel

-- At 121 cells across a phone the game's small text can't be read, so the page shows the same words large beside the wall. This
-- only reads the state and says what's on the wall. A panel button names the action, and pressing it looks for the cell of the wall
-- that gives that action and taps there, so the two can't disagree, and a button left over from a moment ago does nothing.

local panel = { on = false, sig = nil, json = nil }

local function module(name) return package.loaded[name] or require(name) end

local function partyLines(s)
  local party = module("games.blightmare.party")
  local out = {}
  for i, m in ipairs(s.party) do
    local stats = party.stats(m)
    local char = party.CHARS[m.id]
    out[i] = {
      name = m.id == "hero" and s.heroName or (char and char.name or m.id), lvl = m.lvl,
      hp = m.hp, maxHp = stats.maxHp, mp = stats.maxMp > 0 and m.mp or nil, maxMp = stats.maxMp > 0 and stats.maxMp or nil,
    }
  end
  return out
end

local function pickId(i) return actionKey({ kind = "pick", i = i }) end

local function talkPanel(app, s)
  local talk = app.plugin.rules.talk(s)
  if not talk then return { kind = "none" } end
  local out = {
    kind = "talk", name = talk.name, text = talk.lines and concat(talk.lines, " ") or nil, big = talk.big and concat(talk.big, " ") or nil,
    more = talk.more or false, tap = not talk.choices and talk.wait ~= "fade",
  }
  if talk.choices then
    out.choices = {}
    for i, label in ipairs(talk.choices) do out.choices[i] = { id = pickId(i), label = label } end
  end
  if app.plugin.rules.canSkip and app.plugin.rules.canSkip(s) then out.skip = actionKey({ kind = "skip" }) end
  return out
end

local function statusLines(s, member)
  local party = module("games.blightmare.party")
  local stats, char = party.stats(member), party.CHARS[member.id]
  local gear = function(id)
    local def = id and party.GEAR[id]
    return def and def.name or "-"
  end
  return {
    { "ROLE", (char.role or ""):upper() }, { "SPECIAL", char.special or "-" }, { "ATTACK", stats.atk }, { "DEFENCE", stats.def },
    { "MAGIC", stats.mag }, { "SPEED", stats.spd }, { "WEAPON", gear(member.weapon) }, { "ARMOUR", gear(member.armour) },
    { "ACCESSORY", gear(member.accessory) }, { "XP TO NEXT", math.max(0, party.xpFor(member.lvl + 1) - member.xp) },
  }
end

local function quitLabel(app)
  local a = app.S.action
  return a.quitUntil and nowMs + tzMs < a.quitUntil and "SURE?" or "SAVE & QUIT"
end

local function menuPanel(app, s)
  local rules = app.plugin.rules
  local menu = s.menu
  local titles = { useon = "USE ON", main = "MENU" }
  local out = { kind = "menu", title = titles[menu.page] or menu.page:upper(), rows = {}, gold = s.gold, line = menu.line, quit = quitLabel(app) }
  for i, row in ipairs(rules.menuRows(s)) do
    out.rows[i] = { id = pickId(i), label = row.label, dim = (row.item and not row.field) or (row.swap and row.picked) or false }
  end
  local member = menu.who and s.party[menu.who]
  if menu.page == "status" then
    out.facts = statusLines(s, member or s.party[1])
  elseif menu.page == "items" and #out.rows == 0 then
    out.note = "Nothing in the bag."
  elseif menu.page == "equip" and #out.rows == 0 then
    out.note = "No spare gear to wear."
  end
  out.party = partyLines(s)
  return out
end

local function shopPanel(app, s)
  local rules = app.plugin.rules
  local party = module("games.blightmare.party")
  local out = { kind = "menu", title = "SHOP", rows = {}, gold = s.gold, line = s.shop.line, bag = {}, quit = quitLabel(app) }
  for i, row in ipairs(rules.shopRows(s)) do
    out.rows[i] = { id = pickId(i), label = row.label, right = row.price and tostring(row.price) or nil, dim = row.afford == false }
  end
  for _, id in ipairs(party.ITEM_ORDER) do
    if s.bag[id] then out.bag[#out.bag + 1] = rules.itemName(id) .. " x" .. s.bag[id] end
  end
  return out
end

local function battlePanel(app, s)
  local battle, party, enemies = module("games.blightmare.battle"), module("games.blightmare.party"), module("games.blightmare.enemies")
  local b = s.battle
  local lines = partyLines(s)
  local out = { kind = "battle", phase = b.phase, msg = b.msg, allies = {}, tap = b.phase == "spoils" }
  for i, u in ipairs(b.allies) do
    local line = lines[u.m]
    if line then
      line.active = b.active == i
      out.allies[#out.allies + 1] = line
    end
  end
  if b.phase == "cmd" then
    local u = b.allies[b.active]
    local cmd = function(name, label) return { id = actionKey({ kind = "cmd", cmd = name }), label = label } end
    out.cmds = { cmd("attack", "ATTACK"), cmd("special", party.CHARS[s.party[u.m].id].special), cmd("defend", "DEFEND"), cmd("item", "ITEM") }
    out.cmds[3].warn = battle.blowIn(b) ~= nil and not u.braced
    if u.braced then out.cmds[3].label, out.cmds[3].dim = "GUARDING", true end
    if out.cmds[2].label == "FOCUS" and u.focus then out.cmds[2].label, out.cmds[2].dim = "FOCUSED", true end
  elseif b.phase == "list" then
    out.rows, out.back = {}, true
    for i, row in ipairs(battle.rows(s)) do
      out.rows[i] = { id = pickId(i), label = row.name, right = row.note ~= "" and row.note or nil, dim = not row.ok }
    end
  elseif b.phase == "target" then
    out.rows, out.back = {}, true
    local side, list = battle.targets(s)
    local seen = {}
    for n, i in ipairs(list) do
      local label
      if side == "foe" then
        local def = enemies.FOES[b.foes[i].id]
        label = def.short or def.name
        seen[label] = (seen[label] or 0) + 1
        if seen[label] > 1 then label = label .. " " .. seen[label] end
      else
        local u = b.allies[i]
        label = lines[u.m] and lines[u.m].name or "?"
      end
      out.rows[n] = { id = actionKey({ kind = "target", side = side, i = i }), label = label }
    end
  elseif b.phase == "spoils" then
    out.spoils = { xp = b.spoils and b.spoils.xp, gold = b.spoils and b.spoils.gold, ups = {} }
    for i, up in ipairs(b.spoils and b.spoils.ups or {}) do
      out.spoils.ups[i] = (up.id == "hero" and s.heroName or party.CHARS[up.id].name) .. " reached level " .. up.lvl
    end
  end
  return out
end

local function groundPanel(app, s)
  local rules = app.plugin.rules
  local goal = rules.goal(s)
  local place
  if s.mode == "world" then
    local overworld = module("games.blightmare.overworld")
    place = overworld.REGION_NAME[overworld.region(s.wx, s.wy, s) or ""] or "The road"
  else
    local map = module("games.blightmare.world").map(s.map)
    place = map and map.name or nil
  end
  return { kind = "ground", mode = s.mode, place = place, goal = goal and goal.text or nil, msg = s.msg ~= "" and s.msg or nil, gold = s.gold, party = partyLines(s) }
end

local function shellPanel(app)
  local S = app.S
  if S.view == "rules" then return { kind = "help", lines = app.plugin.help, done = S.rulesThen and "GOT IT - START" or "GOT IT" } end
  local a = S.action
  if S.view == "action" and a and a.phase == "ready" then return { kind = "ready", line = a.saved and a.saved.line or nil } end
  return { kind = "none" }
end

local function panelData(app)
  local screen, s = screenOf(app)
  if screen == "shell" then return shellPanel(app) end
  local mode = s.mode
  if mode == "talk" then return talkPanel(app, s) end
  if mode == "menu" then return menuPanel(app, s) end
  if mode == "shop" then return shopPanel(app, s) end
  if mode == "battle" and s.battle then return battlePanel(app, s) end
  if mode == "walk" or mode == "world" then return groundPanel(app, s) end
  return { kind = "none" }
end

local function panelSignature(app)
  local S = app.S
  local a = S.action
  local s = S.view == "action" and a and a.state
  local quit = a and a.quitUntil and nowMs + tzMs < a.quitUntil
  return concat({ S.view, tostring(a and a.phase), tostring(s and s.rev), tostring(quit), tostring(a and a.saved and a.saved.line) }, ",")
end

local function panelStep()
  if not panel.on then return end
  local app = shell_()
  if not app then return end
  local sig = panelSignature(app)
  if sig == panel.sig then return end
  panel.sig = sig
  local json = textutils.serialiseJSON(panelData(app))
  if json ~= panel.json then
    panel.json = json
    emit("J" .. #json .. "\n" .. json)
  end
end

--- A panel button. Every press is checked against the wall as it is now.
local function panelPress(id)
  local app = shell_()
  if not app then return end
  wrapView(app)
  pointerUsed()
  local screen, s = screenOf(app)
  local button = id:match("^button:(.+)$")
  if button then
    for _, b in ipairs(app.env.walls[1].buttons) do
      if b.id == button and b.enabled then
        touch(b.x + floor(b.w / 2), b.y + floor(b.h / 2))
        return
      end
    end
  elseif id == "tap" then
    if screen == "tap" then send({ kind = "tap" }) end
  elseif id == "menu" then
    if screen == "walk" or screen == "world" then send({ kind = "menu" }) end
  elseif id == "back" then
    local b = s and s.battle
    if s and (s.mode == "menu" or s.mode == "shop" or (s.mode == "battle" and b and (b.phase == "list" or b.phase == "target"))) then
      send({ kind = "back" })
    end
  elseif screen == "choose" then
    local t = findKey(scan(app, s), id)
    if t then touch(t.px, t.py) end
  end
end

-- ------------------------------------------------------------------ what the page calls

local PROGRAM = "blightmare.lua"
local game
local crashed = false

function __web.addFile(path, text)
  bundled[path] = text
  noteDirs(path)
end

--- A file the player's browser kept from an earlier visit.
function __web.restoreFile(path, text)
  written[path] = text
  noteDirs(path)
end

function __web.start(tz)
  tzMs = (tonumber(tz) or 0) * 60000
  game = newCoroutine(function() return shell.run(PROGRAM) end)
  enqueue("__start")
end

local function reportCrash(message)
  crashed = true
  local trace = lastTrace or ""
  local text = tostring(message or lastError or "the program stopped") .. "\n" .. tostring(trace)
  emit("E" .. #text .. "\n" .. text)
end

local filter

local function deliver(ev)
  if filter == nil or filter == ev[1] or ev[1] == "terminate" then
    stepStart = native.clock()
    local ok, param = native.resume(game, unpack(ev, 1, ev.n))
    if not ok then
      reportCrash(param)
      return
    end
    filter = param
    if native.status(game) == "dead" then
      if param == true then emit("Q\n") else reportCrash(lastError) end
    end
  end
end

local function flushFiles()
  for path in pairs(dirty) do
    local text = written[path]
    if text == DELETED or text == nil then
      emit("D" .. #path .. "\n" .. path)
    else
      emit("W" .. #path .. "," .. #text .. "\n" .. path .. text)
    end
  end
  dirty = {}
end

--- One go round. input is the page's events, one to a line: "touch x y", "char i", "terminate".
-- Records returned, each a letter and a header line, the bytes after it counted by the header:
--   B x,y,n  text fg bg    a run of cells
--   C bg                   clear
--   R n,bg                 scroll
--   P slot,rgb             a palette colour
--   S vol,pitch,name       a sound
--   L n  text              printed text
--   W pn,n  path text      a file saved
--   D pn  path             a file deleted
--   E n  text              the program has crashed
--   Q                      the program asked to shut down
--   K x,y,w,h              the keyboard cursor, in cells from 0; all zero hides it
--   J n  text              what the phone panel shows, as JSON
--   N ms                   when the next timer is due
function __web.step(time, input)
  nowMs = tonumber(time) or nowMs
  stepStart = native.clock()
  if input ~= "" then
    for line in input:gmatch("[^\n]+") do
      local kind, a, b = line:match("^(%S+)%s*(%S*)%s*(%S*)")
      if kind == "touch" then
        pointerUsed()
        enqueue("monitor_touch", MONITOR, tonumber(a), tonumber(b))
      elseif kind == "press" then
        local ok, err = native.pcall(panelPress, a)
        if not ok then logLine("panel: " .. tostring(err)) end
      elseif kind == "panel" then
        panel.on, panel.sig, panel.json = a == "1", nil, nil
      elseif kind == "key" then
        -- a slip in here is the keyboard's, and needn't take the game down with it
        local ok, err = native.pcall(keyEvent, a, b)
        if not ok then logLine("keyboard: " .. tostring(err)) end
      elseif kind == "char" then
        enqueue("char", a)
      elseif kind == "terminate" then
        enqueue("terminate")
      end
    end
  end
  if game and not crashed and native.status(game) ~= "dead" then
    local due = {}
    for id, at in pairs(timers) do
      if at <= nowMs then due[#due + 1] = id end
    end
    table.sort(due, function(p, q) return timers[p] < timers[q] or (timers[p] == timers[q] and p < q) end)
    for _, id in ipairs(due) do
      timers[id] = nil
      enqueue("timer", id)
    end
    while first <= last and not crashed and native.status(game) ~= "dead" do
      local ev = events[first]
      events[first] = nil
      first = first + 1
      deliver(ev)
    end
  end
  local kept, why = native.pcall(keyboardStep)
  if not kept then logLine("keyboard: " .. tostring(why)) end
  if panel.on then
    local shown, problem = native.pcall(panelStep)
    if not shown then logLine("panel: " .. tostring(problem)) end
  end
  flushFiles()
  local nextAt
  for _, at in pairs(timers) do
    if not nextAt or at < nextAt then nextAt = at end
  end
  emit("N" .. number(nextAt or (nowMs + 1000)) .. "\n")
  local result = concat(out, "", 1, outN)
  out, outN = {}, 0
  return #result .. "\n" .. result
end

--- Run a piece of Lua and return what it says, for the test scripts.
function __web.eval(code)
  local fn, err = native.loadstring(code, "=eval")
  if not fn then return "error: " .. tostring(err) end
  local ok, result = native.pcall(fn)
  if not ok then return "error: " .. tostring(result) end
  local shown, text = native.pcall(textutils.serialise, result, { compact = true, allow_repetitions = true })
  return shown and text or tostring(result)
end
