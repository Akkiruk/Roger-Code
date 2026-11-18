-- crashreport.lua
-- Sends a program's crash to the crash relay, which makes it a GitHub issue on Akkiruk/Roger-Code (one issue per kind of
-- crash; repeats add to its count). The computer holds no key: the relay takes reports from anyone and limits how many.
--
--   local crashreport = require("lib.crashreport")
--   local ok, err, status = crashreport.run("Saltgate", nil, main, { log = "saltgate.log" })
--     runs main under xpcall; on a crash it reports it and returns false, the error, a line for the crash screen
--     ("Crash report sent (#12)", "Crash report couldn't send (...)", or nil when reporting is off) and the traceback.
--     Ctrl+T (Terminated) is not a crash and is never reported.
--   crashreport.guard("Hi-Lo", main, { log = "casino.log" })
--     the same for a program with no crash screen of its own: on a crash it raises the error again, with the status
--     line added, so the Roger supervisor shows it and restarts the program as before.
--   crashreport.send(info)   one report: { program, version, error, traceback, log }. Never throws; returns ok, id or reason.
--
-- Off on one computer: set crashreport.enabled false. On again: set crashreport.enabled true (or unset it).
-- In an emulator (craftos-agent's, or CraftOS-PC) it is off unless crashreport.enabled is set to true, so test suites that
-- crash programs on purpose never file issues. With the http API off it does nothing and says nothing.

local M = {}

M.URL = "https://cc-crash-relay.rboone98s5.workers.dev/crash"
M.TIMEOUT = 5 -- seconds to wait for the relay
M.LOG_LINES = 30
M.LOG_BYTES = 8192 -- how far back from the end of a log to look for those lines
M.SETTING = "crashreport.enabled"
M.INSTALL_STATE = ".installed_program"

if settings and settings.define then
  pcall(settings.define, M.SETTING, {
    description = "Send this computer's program crashes to the owner as GitHub issues (unset means on, except in the emulator)",
    type = "boolean",
  })
end

--- The craftos-agent emulator (its runner always writes /results/world.json) or plain CraftOS-PC (periphemu).
function M.inEmulator()
  if rawget(_G, "periphemu") ~= nil then return true end
  local ok, found = pcall(function() return fs.exists("/results/world.json") end)
  return ok and found == true
end

--- Whether a report would be sent from this computer.
function M.enabled()
  local value = nil
  if settings and settings.get then
    local ok, got = pcall(settings.get, M.SETTING)
    if ok then value = got end
  end
  if value == false then return false end
  if value == true then return true end
  return not M.inEmulator()
end

--- Ctrl+T: the player leaving, not a crash.
function M.isTerminate(err)
  if type(err) ~= "string" then return false end
  return err == "Terminated" or err:match("[%s:]Terminated$") ~= nil
end

--- What the Roger installer wrote about this computer's program: version and source commit.
function M.installed()
  if not (fs and fs.exists and fs.exists(M.INSTALL_STATE)) then return nil end
  local h = fs.open(M.INSTALL_STATE, "r")
  if not h then return nil end
  local raw = h.readAll()
  h.close()
  local ok, state = pcall(textutils.unserialise, raw or "")
  if ok and type(state) == "table" then return state end
  return nil
end

--- The last n lines of a file, reading only its end. nil when there is no such file.
function M.tail(path, n)
  n = n or M.LOG_LINES
  if type(path) ~= "string" or not fs.exists(path) or fs.isDir(path) then return nil end
  local text = nil
  local h = fs.open(path, "rb")
  if h then
    local size = fs.getSize(path)
    if h.seek and size > M.LOG_BYTES then pcall(h.seek, "set", size - M.LOG_BYTES) end
    text = h.readAll()
    h.close()
  end
  if not text then return nil end
  local lines = {}
  for line in text:gmatch("[^\n]+") do lines[#lines + 1] = (line:gsub("\r$", "")) end
  if #text >= M.LOG_BYTES and #lines > 1 then table.remove(lines, 1) end -- the first may be cut in half
  local from = math.max(1, #lines - n + 1)
  local out = {}
  for i = from, #lines do out[#out + 1] = lines[i] end
  if #out == 0 then return nil end
  return table.concat(out, "\n")
end

local function textOrNil(value)
  if value == nil then return nil end
  return tostring(value)
end

--- The report the relay is sent. Plain strings and numbers only.
function M.build(info)
  local state = M.installed() or {}
  local label = os.getComputerLabel and os.getComputerLabel() or nil
  return {
    program = tostring(info.program or state.program or state.name or "unknown"),
    version = textOrNil(info.version or state.version),
    commit = textOrNil(info.commit or state.source_commit),
    error = tostring(info.error),
    traceback = textOrNil(info.traceback),
    computerId = os.getComputerID and os.getComputerID() or nil,
    label = textOrNil(label),
    host = textOrNil(rawget(_G, "_HOST")),
    uptime = os.clock and os.clock() or nil,
    log = info.logText or (info.log and M.tail(info.log)) or nil,
    logName = info.log and textOrNil(info.log) or nil,
  }
end

--- The relay's answer to one request: ok, data or false, reason. Waits at most M.TIMEOUT seconds.
local function post(body)
  local okReq, started, why = pcall(http.request, {
    url = M.URL,
    body = body,
    method = "POST",
    headers = { ["Content-Type"] = "application/json" },
  })
  if not okReq then return false, tostring(started) end
  if started == false then return false, tostring(why or "request refused") end

  local timer = os.startTimer(M.TIMEOUT)
  while true do
    local event = { os.pullEventRaw() }
    local name = event[1]
    if name == "http_success" and event[2] == M.URL then
      local handle = event[3]
      local raw = handle.readAll()
      handle.close()
      pcall(os.cancelTimer, timer)
      local okJson, data = pcall(textutils.unserialiseJSON, raw or "")
      if okJson and type(data) == "table" then return true, data end
      return false, "odd answer from the relay"
    elseif name == "http_failure" and event[2] == M.URL then
      pcall(os.cancelTimer, timer)
      local reason = tostring(event[3] or "request failed")
      local handle = event[4]
      if handle then
        local okRead, raw = pcall(handle.readAll)
        pcall(handle.close)
        local okJson, data = pcall(textutils.unserialiseJSON, okRead and raw or "")
        if okJson and type(data) == "table" and data.error then reason = tostring(data.error) end
      end
      return false, reason
    elseif name == "timer" and event[2] == timer then
      return false, "no answer from the relay"
    elseif name == "terminate" then
      pcall(os.cancelTimer, timer)
      return false, "cancelled"
    end
  end
end

--- Sends one report. Never throws. Returns true, the report's number, the relay's answer; or false and why not.
--- "off" and "no http" mean nothing was tried.
function M.send(info)
  local ok, sent, idOrErr, data = pcall(function()
    if not M.enabled() then return false, "off" end
    if not (http and http.request) then return false, "no http" end
    local okJson, body = pcall(textutils.serialiseJSON, M.build(info or {}))
    if not okJson then return false, "could not encode the report" end
    local done, answer = post(body)
    if not done then return false, answer end
    if answer.ok then return true, answer.id, answer end
    return false, tostring(answer.error or "refused")
  end)
  if not ok then return false, tostring(sent) end
  return sent, idOrErr, data
end

--- The line for a crash screen, or nil when nothing was tried.
function M.statusLine(sent, idOrErr)
  if sent then return "Crash report sent (#" .. tostring(idOrErr) .. ")" end
  if idOrErr == "off" or idOrErr == "no http" then return nil end
  return "Crash report couldn't send (" .. tostring(idOrErr) .. ")"
end

--- Runs fn under xpcall. true when it returns; else false, the error, the status line (nil if not reported) and the traceback.
--- opts.log: the program's own log, whose last lines go with the report. opts.onCrash(err, trace): called before sending.
function M.run(program, version, fn, opts)
  if type(fn) ~= "function" then error("crashreport.run needs a function", 2) end
  opts = opts or {}
  local trace = nil
  local ok, err = xpcall(fn, function(e)
    local okText, text = pcall(tostring, e)
    text = okText and text or "?"
    -- called straight from the handler: level 2 is where the error was raised (through pcall it would be this handler)
    trace = (debug and debug.traceback) and debug.traceback(text, 2) or text
    return e
  end)
  if ok then return true end
  if M.isTerminate(err) then return false, err, nil, trace end
  if type(opts.onCrash) == "function" then pcall(opts.onCrash, err, trace) end
  local sent, idOrErr = M.send({ program = program, version = version, error = err, traceback = trace, log = opts.log })
  return false, err, M.statusLine(sent, idOrErr), trace
end

--- run, then raise the error again (with the status line added) for whoever runs this program: the Roger supervisor.
function M.guard(program, fn, opts)
  local ok, err, status = M.run(program, opts and opts.version, fn, opts)
  if ok then return end
  if status and type(err) == "string" then err = err .. "\n" .. status end
  error(err, 0)
end

return M
