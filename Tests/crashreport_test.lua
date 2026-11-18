-- crashreport_test.lua
-- lib/crashreport.lua against a pretend http: what it sends, what it says on the crash screen, and that it never throws.
-- Needs CC (settings, textutils JSON, events): under plain Lua it skips itself. In craftos-agent: node tools/casinotest/unit.mjs crashreport

local testing = require("testing")

if not (rawget(_G, "os") and os.pullEventRaw and rawget(_G, "textutils") and textutils.serialiseJSON and rawget(_G, "settings")) then
  print("skip crashreport_test (needs CC)")
  return
end

local crashreport = require("lib.crashreport")
local eq, truthy = testing.eq, testing.truthy

local DIR = "/.crashreport_test"
fs.makeDir(DIR)
crashreport.INSTALL_STATE = DIR .. "/installed"

-- ------------------------------------------------------------------ pretend http
-- answer(url) gives the event the request gets back: { "http_success", url, handle } or { "http_failure", url, why, handle }
-- or nil for none (a timeout). It is handed to os.pullEventRaw directly: queued events lose their functions.
local realHttp = rawget(_G, "http")
local realPull = os.pullEventRaw
local sent, queued = {}, {}

local function handle(text)
  return { readAll = function() return text end, close = function() end }
end

local function fakeHttp(answer)
  _G.http = {
    request = function(opts)
      sent[#sent + 1] = opts
      local event = answer(opts.url, opts)
      if event then queued[#queued + 1] = event end
      return true
    end,
  }
  os.pullEventRaw = function(filter)
    if #queued > 0 then return table.unpack(table.remove(queued, 1)) end
    return realPull(filter)
  end
end

local function restore()
  _G.http = realHttp
  os.pullEventRaw = realPull
  sent, queued = {}, {}
  settings.unset(crashreport.SETTING)
  crashreport.TIMEOUT = 5
end

local function okAnswer(id)
  return function(url) return { "http_success", url, handle('{"ok":true,"id":' .. id .. ',"sig":"abc","count":1}') } end
end

local function body(n)
  return textutils.unserialiseJSON(sent[n or #sent].body)
end

local function case(name, fn)
  testing.test("crashreport: " .. name, function()
    local ok, err = pcall(fn)
    restore()
    if not ok then error(err, 0) end
  end)
end

-- ------------------------------------------------------------------ the toggle

case("on unless set false; in the emulator only when set true", function()
  settings.set(crashreport.SETTING, false)
  eq(crashreport.enabled(), false)
  settings.set(crashreport.SETTING, true)
  eq(crashreport.enabled(), true)
  settings.unset(crashreport.SETTING)
  eq(crashreport.enabled(), not crashreport.inEmulator())
end)

-- Every test suite runs in the emulator, and many crash programs on purpose: none of that may reach GitHub
if fs.exists("/results") then
  case("the emulator is seen as one, so an unset toggle is off", function()
    eq(crashreport.inEmulator(), true)
    settings.unset(crashreport.SETTING)
    eq(crashreport.enabled(), false)
  end)
end

case("set false: nothing is sent and the crash screen says nothing", function()
  fakeHttp(okAnswer(1))
  settings.set(crashreport.SETTING, false)
  local ok, err, status = crashreport.run("Test", nil, function() error("boom") end)
  eq(ok, false)
  truthy(tostring(err):find("boom", 1, true))
  eq(status, nil)
  eq(#sent, 0)
end)

case("http off: silent, no error", function()
  settings.set(crashreport.SETTING, true)
  _G.http = nil
  local sentOk, why = crashreport.send({ program = "Test", error = "x" })
  eq(sentOk, false)
  eq(why, "no http")
  eq(crashreport.statusLine(sentOk, why), nil)
  local ok, _, status = crashreport.run("Test", nil, function() error("boom") end)
  eq(ok, false)
  eq(status, nil)
end)

-- ------------------------------------------------------------------ what is sent

case("a crash is sent with its traceback, the computer, the install and the end of the log", function()
  fakeHttp(okAnswer(42))
  settings.set(crashreport.SETTING, true)
  local f = fs.open(crashreport.INSTALL_STATE, "w")
  f.write(textutils.serialise({ program = "saltgate", version = "7", source_commit = "4d6cf1b0aa11" }))
  f.close()
  local logPath = DIR .. "/game.log"
  f = fs.open(logPath, "w")
  for i = 1, 50 do f.writeLine("line " .. i) end
  f.close()

  local order = {}
  local function inner() local t = nil; return t.field end
  local function outer() inner() end
  local ok, err, status, trace = crashreport.run("Saltgate", nil, outer, {
    log = logPath,
    onCrash = function(e) order[#order + 1] = "screen " .. tostring(#sent) end,
  })
  eq(ok, false)
  truthy(tostring(err):find("attempt to index", 1, true), tostring(err))
  eq(status, "Crash report sent (#42)")
  eq(order[1], "screen 0") -- the crash screen is up before the report goes
  truthy(trace:find("stack traceback", 1, true), trace)
  local top = trace:match("stack traceback:\n%s*([^\n]+)")
  truthy(top and top:find("crashreport_test", 1, true), "the first frame is where it broke, not the handler: " .. trace)

  eq(#sent, 1)
  eq(sent[1].url, crashreport.URL)
  eq(sent[1].method, "POST")
  eq(sent[1].headers["Content-Type"], "application/json")
  local b = body()
  eq(b.program, "Saltgate")
  eq(b.version, "7")
  eq(b.commit, "4d6cf1b0aa11")
  eq(b.error, tostring(err))
  eq(b.traceback, trace)
  eq(b.computerId, os.getComputerID())
  eq(b.host, _HOST)
  truthy(type(b.uptime) == "number")
  eq(b.logName, logPath)
  local lines = {}
  for line in b.log:gmatch("[^\n]+") do lines[#lines + 1] = line end
  eq(#lines, 30)
  eq(lines[1], "line 21")
  eq(lines[30], "line 50")
  fs.delete(crashreport.INSTALL_STATE)
end)

case("a version given beats the install record; no log, no install record is fine", function()
  fakeHttp(okAnswer(3))
  settings.set(crashreport.SETTING, true)
  crashreport.run("Test", "1.2", function() error("x", 0) end, { log = DIR .. "/missing.log" })
  local b = body()
  eq(b.version, "1.2")
  eq(b.commit, nil)
  eq(b.log, nil)
  eq(b.error, "x")
end)

case("tail reads only the end of a big log", function()
  local path = DIR .. "/big.log"
  local f = fs.open(path, "w")
  for i = 1, 3000 do f.writeLine("entry number " .. i .. " with some words to make it longer") end
  f.close()
  local text = crashreport.tail(path, 30)
  local lines = {}
  for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
  eq(#lines, 30)
  eq(lines[30], "entry number 3000 with some words to make it longer")
  eq(lines[1], "entry number 2971 with some words to make it longer")
  eq(crashreport.tail(DIR .. "/nope.log"), nil)
end)

-- ------------------------------------------------------------------ what is not a crash, and failures

case("Ctrl+T is not a crash", function()
  fakeHttp(okAnswer(1))
  settings.set(crashreport.SETTING, true)
  local ok, err, status = crashreport.run("Test", nil, function() error("Terminated", 0) end)
  eq(ok, false)
  eq(err, "Terminated")
  eq(status, nil)
  eq(#sent, 0)
  truthy(crashreport.isTerminate("Terminated"))
  truthy(crashreport.isTerminate("x.lua:3: Terminated"))
  eq(crashreport.isTerminate("Terminated early: bad"), false)
end)

case("a program that returns is not reported", function()
  fakeHttp(okAnswer(1))
  settings.set(crashreport.SETTING, true)
  eq(crashreport.run("Test", nil, function() return 5 end), true)
  eq(#sent, 0)
end)

case("the relay says no (429): couldn't send, with its reason", function()
  fakeHttp(function(url)
    return { "http_failure", url, "Too Many Requests", handle('{"ok":false,"limited":true,"error":"too many reports from this computer this hour"}') }
  end)
  settings.set(crashreport.SETTING, true)
  local _, _, status = crashreport.run("Test", nil, function() error("boom") end)
  eq(status, "Crash report couldn't send (too many reports from this computer this hour)")
end)

case("no answer in time: couldn't send", function()
  fakeHttp(function() return nil end)
  settings.set(crashreport.SETTING, true)
  crashreport.TIMEOUT = 0.1
  local sentOk, why = crashreport.send({ program = "Test", error = "x" })
  eq(sentOk, false)
  eq(why, "no answer from the relay")
end)

case("a refused or throwing request never throws", function()
  settings.set(crashreport.SETTING, true)
  _G.http = { request = function() return false, "Domain not permitted" end }
  local sentOk, why = crashreport.send({ program = "Test", error = "x" })
  eq(sentOk, false)
  eq(why, "Domain not permitted")
  eq(crashreport.statusLine(sentOk, why), "Crash report couldn't send (Domain not permitted)")
  _G.http = { request = function() error("kaboom") end }
  sentOk, why = crashreport.send({ program = "Test", error = "x" })
  eq(sentOk, false)
  truthy(tostring(why):find("kaboom", 1, true))
  fakeHttp(function(url) return { "http_success", url, handle("<html>not json</html>") } end)
  sentOk, why = crashreport.send({ program = "Test", error = "x" })
  eq(sentOk, false)
  eq(why, "odd answer from the relay")
  sentOk = crashreport.send(nil)
  eq(sentOk, false)
end)

case("an error that is not a string is sent as text", function()
  fakeHttp(okAnswer(9))
  settings.set(crashreport.SETTING, true)
  local ok, err, status = crashreport.run("Test", nil, function() error({ code = 1 }) end)
  eq(ok, false)
  eq(type(err), "table")
  eq(status, "Crash report sent (#9)")
  truthy(body().error:find("^table"))
end)

-- ------------------------------------------------------------------ guard, for programs with no crash screen of their own

case("guard raises the error again with the status line, for the supervisor", function()
  fakeHttp(okAnswer(77))
  settings.set(crashreport.SETTING, true)
  local ok, err = pcall(crashreport.guard, "Test", function() error("x.lua:1: broke", 0) end)
  eq(ok, false)
  eq(err, "x.lua:1: broke\nCrash report sent (#77)")
  ok, err = pcall(crashreport.guard, "Test", function() error("Terminated", 0) end)
  eq(ok, false)
  eq(err, "Terminated")
  eq(#sent, 1)
  eq(pcall(crashreport.guard, "Test", function() end), true)
  settings.set(crashreport.SETTING, false)
  ok, err = pcall(crashreport.guard, "Test", function() error("plain", 0) end)
  eq(err, "plain")
end)

fs.delete(DIR)
