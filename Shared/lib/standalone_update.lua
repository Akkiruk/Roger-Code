-- standalone_update.lua
-- Install and keep up to date a program installed on its own (from a Pastebin installer), not through the Roger
-- installer and its deploy index (lib/updater.lua). One GitHub API call says which commit main is at; when that is newer
-- than the installed one, the files are downloaded into a staging folder while the program runs, every one checked, and
-- only then marked ready. The swap happens at the next start, before the program loads anything: never mid-game. A
-- failed or partial download changes nothing. A fresh install is an update from nothing, done at once.
--
-- Which files: the program's standalone manifest in the repo, read at the commit being installed, so files can be
-- added, renamed or removed in the repo and old installs follow. A manifest (e.g. Games/Saltgate/standalone.txt):
--   program saltgate                                    names its settings (saltgate.autoupdate) and state file
--   file Games/Saltgate/saltgate.pak saltgate.pak       repo path, install path
--   keep Games/Saltgate/saltgate_settings.lua saltgate_settings.lua    written only when missing; never deleted
-- Files that were installed and left the list are deleted; anything never in a list (saves, logs) is never touched.
--
--   local up = require("lib.standalone_update")
--   local o = up.options("Games/Saltgate/standalone.txt", "saltgate")
--   local commit = up.applyStaged(o)        at the start: a ready update swapped in (returns its commit), or nil
--   up.check(o)                             in the background: at most once a boot, never more often than INTERVAL
--   up.install(o, progress)                 a fresh install (the installer): fetched, checked, written
-- Off on one computer: set <program>.autoupdate false. No http, GitHub down or the API's rate limit (60 an hour per
-- IP, which a server's computers share): it carries on with the installed files and waits longer before asking again.

local M = {}

M.OWNER, M.REPO, M.BRANCH = "Akkiruk", "Roger-Code", "main"
M.INTERVAL = 30 * 60      -- seconds between two checks of main
M.BACKOFF_MAX = 6 * 3600  -- the longest wait after failures
M.STAGE = ".update"       -- the staging folder
M.TRIES = 3               -- for a download that gets no answer at all
M.MARGIN = 4000           -- bytes kept free beyond what an update needs (saves and logs still have to fit)

local function now(o) return o.now and o.now() or math.floor((os.epoch and os.epoch("utc") or os.time() * 1000) / 1000) end
local function log(o, msg) if o.log then pcall(o.log, msg) end end

--- The options for one program. manifest: its standalone manifest's repo path; program: its name (settings, state).
function M.options(manifest, program, extra)
  local o = {
    manifest = manifest, program = program, state = program .. "_install.dat",
    fs = rawget(_G, "fs"), http = rawget(_G, "http"), settings = rawget(_G, "settings"),
  }
  for k, v in pairs(extra or {}) do o[k] = v end
  -- (tests point these at a local server: <program>.update_api and <program>.update_raw)
  local st = o.settings
  if st and st.get then
    o.apiBase = o.apiBase or st.get(program .. ".update_api")
    o.rawBase = o.rawBase or st.get(program .. ".update_raw")
    o.interval = o.interval or tonumber(st.get(program .. ".update_interval"))
  end
  return o
end

local function apiUrl(o)
  return (o.apiBase or ("https://api.github.com/repos/" .. M.OWNER .. "/" .. M.REPO .. "/")) .. "commits/" .. M.BRANCH
end
local function rawUrl(o, commit, path)
  return (o.rawBase or ("https://raw.githubusercontent.com/" .. M.OWNER .. "/" .. M.REPO .. "/")) .. commit .. "/" .. path
end

-- ---------------------------------------------------------------- the manifest

--- { program, files = { { from, to, keep } } } from a manifest's text, or nil, err.
function M.parse(text)
  if type(text) ~= "string" then return nil, "no manifest" end
  local out = { files = {} }
  local seen = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    local word, a, b = line:match("^%s*(%S+)%s+(%S+)%s*(%S*)%s*$")
    if word == "program" then
      out.program = a
    elseif word == "file" or word == "keep" then
      local to = b ~= "" and b or a
      if to:find("%.%.") or to:sub(1, 1) == "/" then return nil, "bad install path " .. to end
      if seen[to] then return nil, "two files install to " .. to end
      seen[to] = true
      out.files[#out.files + 1] = { from = a, to = to, keep = word == "keep" }
    end
  end
  if #out.files == 0 then return nil, "the manifest lists no files" end
  return out
end

-- ---------------------------------------------------------------- state

local function serialise(t)
  local tu = rawget(_G, "textutils")
  if tu and tu.serialise then return tu.serialise(t) end
  -- (plain Lua: enough for the state's strings, numbers and lists)
  local function ser(v)
    if type(v) == "table" then
      local parts = {}
      for k, x in pairs(v) do
        local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
        parts[#parts + 1] = key .. "=" .. ser(x)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    elseif type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
  end
  return ser(t)
end

local function unserialise(text)
  if not text then return nil end
  local tu = rawget(_G, "textutils")
  if tu and tu.unserialise then return tu.unserialise(text) end
  local fn = (rawget(_G, "loadstring") or load)("return " .. text)
  if not fn then return nil end
  local ok, v = pcall(fn)
  return ok and v or nil
end

local function readFile(fs_, path, binary)
  if not fs_.exists(path) or fs_.isDir(path) then return nil end
  local h = fs_.open(path, binary and "rb" or "r")
  if not h then return nil end
  local data = h.readAll()
  h.close()
  return data
end

local function writeFile(fs_, path, data, binary)
  local dir = fs_.getDir and fs_.getDir(path) or (path:match("^(.*)/[^/]*$") or "")
  if dir ~= "" and not fs_.exists(dir) then fs_.makeDir(dir) end
  local h, err = fs_.open(path, binary and "wb" or "w")
  if not h then return false, err or ("cannot write " .. path) end
  h.write(data)
  h.close()
  return true
end

function M.readState(o)
  local st = unserialise(readFile(o.fs, o.state))
  if type(st) ~= "table" then st = {} end
  st.files = type(st.files) == "table" and st.files or {}
  return st
end

function M.writeState(o, st)
  return writeFile(o.fs, o.state, serialise(st))
end

-- ---------------------------------------------------------------- http

--- data, or nil, err, code (code: the HTTP status when there was an answer).
local function get(o, url, headers)
  local http_ = o.http
  if not http_ or not http_.get then return nil, "no http" end
  local ok, h, err, failed = pcall(http_.get, url, headers, true)
  if not ok then return nil, tostring(h) end
  if not h then
    local code
    if failed then
      local okc, c = pcall(failed.getResponseCode)
      code = okc and c or nil
      pcall(failed.close)
    end
    return nil, tostring(err or "no answer"), code
  end
  local code = h.getResponseCode and h.getResponseCode() or 200
  local headers = h.getResponseHeaders and h.getResponseHeaders() or {}
  local data = h.readAll()
  h.close()
  if code ~= 200 then return nil, "HTTP " .. tostring(code), code end
  if not data or #data == 0 then return nil, "empty answer", code end
  -- a connection that dropped part way: fewer bytes than the server said
  for k, v in pairs(headers) do
    if type(k) == "string" and k:lower() == "content-length" and tonumber(v) and tonumber(v) ~= #data then
      return nil, "cut short (" .. #data .. " of " .. v .. " bytes)"
    end
  end
  return data
end

--- get, tried again (a few times, a little later) when nothing answered at all; never again on an HTTP error.
local function fetch(o, url, headers)
  local data, err, code
  for try = 1, M.TRIES do
    data, err, code = get(o, url, headers)
    if data or code then return data, err, code end
    if err == "no http" then return nil, err end
    if try < M.TRIES and o.sleep then o.sleep(try) end
  end
  return nil, err, code
end

--- The commit main is at: a 40-character sha, or nil, err, code.
function M.latest(o)
  local data, err, code = fetch(o, apiUrl(o), { ["Accept"] = "application/vnd.github.sha", ["User-Agent"] = "cc-standalone-update" })
  if not data then return nil, err, code end
  local sha = data:match("^%s*(%x+)%s*$")
  if not sha or #sha ~= 40 then return nil, "odd answer from GitHub" end
  return sha:lower()
end

-- ---------------------------------------------------------------- download, check, stage

--- What a file must look like to be used: Lua that compiles, a pak with its header, anything else not empty.
local function valid(to, data)
  if not data or #data == 0 then return false, "empty" end
  if to:match("%.pak$") then
    if not data:match("^SGPAK1 %d+\n") then return false, "not a pack" end
    -- a SALTGATE pack ends with its own length ("\nSGEND <bytes before it>\n"): one cut short is refused
    local before = data:match("\nSGEND (%d+)\n$")
    if not before or tonumber(before) ~= #data - #("\nSGEND " .. before .. "\n") then return false, "cut short" end
  end
  if to:match("%.lua$") then
    local ls = rawget(_G, "loadstring") or load
    local fn, err = ls(data, "=" .. to)
    if not fn then return false, "does not compile: " .. tostring(err) end
  end
  return true
end

--- The manifest and every file it lists at commit, checked: { man, text, blobs = { [to] = data } }, or nil, err.
-- progress(done, total, path) as files come in. A keep file that is already installed is not fetched.
function M.download(o, commit, progress)
  local text, err = fetch(o, rawUrl(o, commit, o.manifest))
  if not text then return nil, "manifest: " .. tostring(err) end
  local man, perr = M.parse(text)
  if not man then return nil, perr end
  local blobs = {}
  for i, f in ipairs(man.files) do
    if progress then progress(i - 1, #man.files, f.to) end
    if not (f.keep and o.fs.exists(f.to)) then
      local data, ferr = fetch(o, rawUrl(o, commit, f.from))
      if not data then return nil, f.to .. ": " .. tostring(ferr) end
      local ok, why = valid(f.to, data)
      if not ok then return nil, f.to .. ": " .. why end
      blobs[f.to] = data
    end
  end
  if progress then progress(#man.files, #man.files, nil) end
  return { man = man, text = text, blobs = blobs, commit = commit }
end

--- What a file costs on a CC disk.
local function cost(n) return math.max(500, n) end

--- Write a download into the staging folder, then (last) its ready mark. true, or nil, err (nothing is left half done).
function M.stage(o, got)
  local fs_ = o.fs
  local need = M.MARGIN + 1000
  for _, data in pairs(got.blobs) do need = need + cost(#data) end
  if fs_.getFreeSpace and fs_.getFreeSpace("/") < need then
    return nil, "not enough disk space for the update (" .. math.ceil(need / 1024) .. " KB)"
  end
  if fs_.exists(M.STAGE) then fs_.delete(M.STAGE) end
  for to, data in pairs(got.blobs) do
    local ok, err = writeFile(fs_, M.STAGE .. "/files/" .. to, data, true)
    if not ok then pcall(fs_.delete, M.STAGE) return nil, err end
  end
  local ok, err = writeFile(fs_, M.STAGE .. "/ready.dat", serialise({ commit = got.commit, manifest = got.text }))
  if not ok then pcall(fs_.delete, M.STAGE) return nil, err end
  return true
end

--- A staged update, if one is complete: { commit, manifest = text }, or nil. A partial one is cleared away.
function M.staged(o)
  local fs_ = o.fs
  if not fs_.exists(M.STAGE) then return nil end
  local ready = unserialise(readFile(fs_, M.STAGE .. "/ready.dat"))
  if type(ready) ~= "table" or type(ready.commit) ~= "string" or type(ready.manifest) ~= "string" then
    pcall(fs_.delete, M.STAGE) -- a download that never finished
    return nil
  end
  return ready
end

--- Swap a staged update in: each staged file over its install path, files that left the list deleted, the state
-- updated, the staging folder cleared. Safe to run again if the computer stops halfway (the ready mark stays until the
-- end, and a file already moved is simply not staged any more). Returns the new commit, or nil.
function M.applyStaged(o)
  local fs_ = o.fs
  local ready = M.staged(o)
  if not ready then return nil end
  local man = M.parse(ready.manifest)
  if not man then pcall(fs_.delete, M.STAGE) return nil end
  local st = M.readState(o)
  local listed, keep = {}, {}
  for _, f in ipairs(man.files) do
    listed[f.to] = true
    if f.keep then keep[f.to] = true end
    local from = M.STAGE .. "/files/" .. f.to
    if fs_.exists(from) then
      if not (f.keep and fs_.exists(f.to)) then
        if fs_.exists(f.to) then fs_.delete(f.to) end
        local dir = fs_.getDir and fs_.getDir(f.to) or ""
        if dir ~= "" and not fs_.exists(dir) then fs_.makeDir(dir) end
        fs_.move(from, f.to)
      end
    end
  end
  -- what an older list installed and this one does not: gone (keep files and anything never listed stay)
  for _, old in ipairs(st.files) do
    if not listed[old] and not (st.keep and st.keep[old]) and fs_.exists(old) and not fs_.isDir(old) then fs_.delete(old) end
  end
  local files = {}
  for _, f in ipairs(man.files) do files[#files + 1] = f.to end
  st.files, st.keep = files, keep
  st.previous = st.commit
  st.commit = ready.commit
  st.updatedAt = now(o)
  M.writeState(o, st)
  fs_.delete(M.STAGE)
  log(o, "updated to " .. ready.commit:sub(1, 7))
  return ready.commit
end

-- ---------------------------------------------------------------- the check

--- Whether a check may run now (the off switch, http, the wait since the last one and after failures).
function M.due(o, st)
  local s = o.settings
  if s and s.get and s.get(o.program .. ".autoupdate") == false then return false, "off" end
  if not (o.http and o.http.get) then return false, "no http" end
  st = st or M.readState(o)
  local t = now(o)
  if st.backoffUntil and t < st.backoffUntil then return false, "waiting after a failure" end
  if st.checkedAt and t - st.checkedAt < (o.interval or M.INTERVAL) then return false, "checked recently" end
  return true
end

--- One check: if main is past the installed commit, download and stage it (swapped in at the next start). Never
-- throws. Returns what happened: "off", "no http", "current", "staged", "already staged", or "failed: ...".
function M.check(o)
  local ok, result = pcall(function()
    local st = M.readState(o)
    local go, why = M.due(o, st)
    if not go then return why end
    st.checkedAt = now(o)
    M.writeState(o, st)
    local function failed(err, code)
      st.fails = (st.fails or 0) + 1
      -- a refusal (the rate limit, GitHub down): wait longer each time, up to BACKOFF_MAX
      local wait = math.min(M.BACKOFF_MAX, (o.interval or M.INTERVAL) * 2 ^ math.min(st.fails, 8))
      st.backoffUntil = now(o) + wait
      st.lastError = tostring(err) .. (code and (" (" .. code .. ")") or "")
      M.writeState(o, st)
      log(o, "update check failed: " .. st.lastError)
      return "failed: " .. st.lastError
    end
    local commit, err, code = M.latest(o)
    if not commit then return failed(err, code) end
    if commit == st.commit then
      st.fails, st.backoffUntil = 0, nil
      M.writeState(o, st)
      return "current"
    end
    local ready = M.staged(o)
    if ready and ready.commit == commit then return "already staged" end
    local got, derr = M.download(o, commit)
    if not got then return failed(derr) end
    local sok, serr = M.stage(o, got)
    if not sok then return failed(serr) end
    st = M.readState(o)
    st.fails, st.backoffUntil, st.lastError = 0, nil, nil
    M.writeState(o, st)
    log(o, "update " .. commit:sub(1, 7) .. " downloaded; it goes in at the next start")
    return "staged"
  end)
  if not ok then log(o, "update check crashed: " .. tostring(result)) return "failed: " .. tostring(result) end
  return result
end

--- A fresh install (or a repair): main's commit, every file fetched and checked, then written. progress(done, total,
-- path). Returns the commit, or nil, err (and then nothing was changed).
function M.install(o, progress)
  local commit, err, code = M.latest(o)
  if not commit then
    -- GitHub would not say (the rate limit): the branch itself still names the newest files
    if code == 403 or code == 429 then return nil, "GitHub is busy (rate limit): try again in a few minutes" end
    return nil, err
  end
  local got, derr = M.download(o, commit, progress)
  if not got then return nil, derr end
  local ok, serr = M.stage(o, got)
  if not ok then return nil, serr end
  local done = M.applyStaged(o)
  if not done then return nil, "the files could not be put in place" end
  local st = M.readState(o)
  st.checkedAt = now(o)
  st.installedBy = "installer"
  M.writeState(o, st)
  return commit
end

return M
