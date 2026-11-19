-- saltgate.lua
-- SALTGATE: LOW TIDE. An open-city crime and driving game in 3D (Pine3D), played on an advanced computer's own screen
-- with its keyboard. (A pocket computer works too.) The game is sg/core/app.lua and its plugins in sg/plugins/.
--   saltgate             play
--   saltgate bench [n]   the autopilot drives n frames; the frame times and memory go to saltgate_bench.log
-- Saves go to saltgate_save2.dat; the first time, a save from the first SALTGATE (saltgate_save.dat) is read and moved
-- over (money, the jobs done, stats). Music: music/ (see sg/core/app.lua). A crash is logged, shown, and reported.

local render = require("sg.render")

local args = { ... }
local LOG = "saltgate.log"

local function log(msg)
  local h = fs.open(LOG, "a")
  if h then
    h.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg))
    h.close()
  end
end

local function run()
  if not term.isColour() then
    print("SALTGATE needs an advanced computer (gold) or an advanced pocket computer.")
    return
  end
  require("sg.core.app").main(args)
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
    render.resetPalette(native)
    error(err, 0)
  end
  if not logged then writeCrashLog(err, crashTrace) end
  local shown = pcall(showCrash, err, crashTrace, status)
  if shown then pcall(os.pullEvent, "key") end
  error(err, 0)
end
