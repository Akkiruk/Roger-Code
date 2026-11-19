-- saltgate.lua
-- SALTGATE: LOW TIDE. An open-city crime and driving game in 3D (Pine3D), played on an advanced computer's own screen
-- with its keyboard. (A pocket computer works too.) The game is sg/core/app.lua and its plugins in sg/plugins/.
--   saltgate             play
--   saltgate bench [n]   the autopilot drives n frames; the frame times and memory go to saltgate_bench.log
-- Saves go to saltgate_save2.dat; the first time, a save from the first SALTGATE (saltgate_save.dat) is read and moved
-- over (money, the jobs done, stats). Music: music/ (see sg/core/app.lua). A crash is logged, shown, and reported.
-- Installed, the game is saltgate.pak (everything under sg/, content/, music/ and pine3d/, compressed): sgpak.lua
-- inflates it into memory behind a loading card and runs the game from there. Beside its readable sources (the repo)
-- it runs them instead.

local args = { ... }
local LOG = "saltgate.log"
local here = fs.getDir(shell and shell.getRunningProgram() or "")
local function at(p) return here == "" and p or fs.combine(here, p) end
local gameRequire = require

local function log(msg)
  local h = fs.open(LOG, "a")
  if h then
    h.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg))
    h.close()
  end
end

--- The loading card while the pack inflates: done and total are bytes.
local function loadingCard(done, total)
  local t = term.current()
  local w, h = t.getSize()
  local y = math.floor(h / 2)
  if done == 0 then
    t.setBackgroundColour(colours.black)
    t.clear()
    local title = "SALTGATE"
    t.setCursorPos(math.floor((w - #title) / 2) + 1, y - 1)
    t.setTextColour(colours.orange)
    t.write(title)
    local sub = "Waking the harbor..."
    t.setCursorPos(math.floor((w - #sub) / 2) + 1, y + 3)
    t.setTextColour(colours.grey)
    t.write(sub)
  end
  local barW = math.max(10, math.floor(w * 0.6))
  local x0 = math.floor((w - barW) / 2) + 1
  local fill = math.floor(barW * math.min(1, done / math.max(1, total)) + 0.5)
  t.setCursorPos(x0, y + 1)
  t.setBackgroundColour(colours.orange)
  t.write(string.rep(" ", fill))
  t.setBackgroundColour(colours.grey)
  t.write(string.rep(" ", barW - fill))
  t.setBackgroundColour(colours.black)
end

--- Installed: the game from saltgate.pak, in memory. The time it took goes to the log.
local function mountPak()
  if fs.exists(at("sg/core/app.lua")) or not fs.exists(at("saltgate.pak")) then return end
  local started = os.epoch("utc")
  local pak = dofile(at("sgpak.lua"))
  loadingCard(0, 1)
  local last = started
  local files, order = pak.read(at("saltgate.pak"), {
    fs = fs,
    yield = function(done, total)
      local now = os.epoch("utc")
      if now - last < 50 then return end
      last = now
      loadingCard(done, total)
      os.queueEvent("saltgate_pak")
      os.pullEvent("saltgate_pak")
    end,
  })
  if not files then error("SALTGATE could not open its pack: " .. tostring(order), 0) end
  local env = pak.mount(files, {
    fs = fs,
    env = { shell = shell, multishell = multishell, require = require, package = package },
    require = require,
  })
  gameRequire = env.require
  log(string.format("pak: %d files in memory in %d ms", #order, os.epoch("utc") - started))
end

local function run()
  if not term.isColour() then
    print("SALTGATE needs an advanced computer (gold) or an advanced pocket computer.")
    return
  end
  mountPak()
  gameRequire("sg.core.app").main(args)
end

-- ---------------------------------------------------------------- when it goes wrong

local CRASH_LOG = "saltgate_crash.log"
local native = term.current()

-- lib/crashreport sends the crash to the owner as a GitHub issue. Without it (a desktop harness) the game still runs.
local hasReport, crashreport = pcall(function() return require("lib.crashreport") end)
if not hasReport or type(crashreport) ~= "table" then crashreport = nil end

local function writeCrashLog(err, trace)
  local h = fs.open(CRASH_LOG, "a")
  if h then
    h.writeLine("==== " .. os.date("%Y-%m-%d %H:%M:%S"))
    h.writeLine(tostring(err))
    h.writeLine(tostring(trace))
    h.close()
  end
  log("crash: " .. tostring(err))
end

--- The error and where it happened on the screen; status: how the crash report went (nil when none was sent).
local function showCrash(err, trace, status)
  term.redirect(native)
  local hasRender, render = pcall(gameRequire, "sg.render")
  if not hasRender then
    render = { resetPalette = function() end, wrap = function(text, width)
      local out = {}
      for i = 1, #text, width do out[#out + 1] = text:sub(i, i + width - 1) end
      return out
    end }
  end
  render.resetPalette(native)
  native.setBackgroundColour(colours.black)
  native.clear()
  local w, hgt = native.getSize()
  local y = 1
  local function line(text, colour)
    for _, part in ipairs(render.wrap(text, w - 1)) do
      if y > hgt - 3 then return end
      native.setCursorPos(1, y)
      native.setTextColour(colour)
      native.write(part)
      y = y + 1
    end
  end
  line("SALTGATE crashed. Sorry!", colours.red)
  line(tostring(err), colours.yellow)
  for frame in tostring(trace):gmatch("[^\n]+") do
    if not frame:find("^stack traceback") and not frame:find("%[C%]") then
      line(frame:gsub("^%s+", ""), colours.lightGrey)
    end
  end
  if status then
    native.setCursorPos(1, hgt - 2)
    native.setTextColour(status:find("sent", 1, true) and colours.lightBlue or colours.orange)
    native.write(status)
  end
  native.setCursorPos(1, hgt - 1)
  native.setTextColour(colours.white)
  native.write("Saved to " .. CRASH_LOG .. ".")
  native.setCursorPos(1, hgt)
  native.write("Press any key to restart.")
end

local function game() run() end
local logged = false
local ok, err, status, crashTrace
if crashreport then
  ok, err, status, crashTrace = crashreport.run("Saltgate", nil, game, {
    log = LOG,
    onCrash = function(e, trace)
      writeCrashLog(e, trace)
      logged = true
      if crashreport.enabled() and http then pcall(showCrash, e, trace, "Sending crash report...") end
    end,
  })
else
  ok, err = xpcall(game, function(e)
    crashTrace = debug and debug.traceback and debug.traceback(tostring(e), 2) or tostring(e)
    return e
  end)
end
if not ok then
  if type(err) == "string" and err:find("Terminated", 1, true) then
    local hasRender, render = pcall(gameRequire, "sg.render")
    if hasRender then render.resetPalette(native) end
    error(err, 0)
  end
  if not logged then writeCrashLog(err, crashTrace) end
  local shown = pcall(showCrash, err, crashTrace, status)
  if shown then pcall(os.pullEvent, "key") end
  error(err, 0)
end
