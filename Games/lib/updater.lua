-- Auto-updater module for ComputerCraft programs.
-- Checks the manifest on startup and silently updates
-- code, assets, and shared libs when a new version is available.
-- Config files are always preserved.
--
-- Usage (in startup.lua):
--   local updater = require("lib.updater")
--   updater.checkForUpdates()  -- silent, non-blocking on failure

local REPO_OWNER = "Akkiruk"
local REPO_NAME  = "Roger-Code"
local BRANCH     = "main"
local REPO_URL   = "https://raw.githubusercontent.com/"
                    .. REPO_OWNER .. "/" .. REPO_NAME
                    .. "/" .. BRANCH .. "/"
local MANIFEST_URL  = REPO_URL .. "Games/manifest.json"
local VERSION_FILE  = ".installed_program"
local LOG_FILE      = "updater.log"
local UPDATE_LOCK   = ".update_lock"
local LOCKDOWN_FILE = "vhcc_lockdown.txt"
local UNLOCK_FILE   = ".vhcc_unlock"

-----------------------------------------------------
-- Helpers
-----------------------------------------------------

local function logMsg(msg)
  local f = fs.open(LOG_FILE, "a")
  if f then
    f.writeLine("[" .. os.epoch("local") .. "] " .. tostring(msg))
    f.close()
  end
end

local function download(url)
  local ok, response = pcall(function()
    return http.get(url, nil, true)
  end)
  if not ok or not response then
    return nil, "HTTP request failed: " .. tostring(url)
  end
  local data = response.readAll()
  local code = response.getResponseCode()
  response.close()
  if code ~= 200 then
    return nil, "HTTP " .. tostring(code) .. ": " .. tostring(url)
  end
  if not data or #data == 0 then
    return nil, "Empty response: " .. tostring(url)
  end
  return data
end

local function saveFile(path, data)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
  local f = fs.open(path, "wb")
  if not f then
    return false, "Cannot write: " .. path
  end
  f.write(data)
  f.close()
  return true
end

local function loadInstalled()
  if not fs.exists(VERSION_FILE) then return nil end
  local f = fs.open(VERSION_FILE, "r")
  if not f then return nil end
  local raw = f.readAll()
  f.close()
  local ok, info = pcall(function() return textutils.unserialise(raw) end)
  if ok and type(info) == "table" then return info end
  return nil
end

local function saveInstalled(info)
  local f = fs.open(VERSION_FILE, "w")
  if f then
    f.write(textutils.serialise(info))
    f.close()
  end
end

local function beginWriteWindow(tag)
  if not fs.exists(LOCKDOWN_FILE) then
    return true, false
  end

  if fs.exists(UNLOCK_FILE) then
    return true, false
  end

  local f = fs.open(UNLOCK_FILE, "w")
  if not f then
    return false, "Cannot create lockdown unlock file"
  end

  f.write(textutils.serialise({
    source = tag or "updater",
    openedAt = os.epoch("local"),
  }))
  f.close()
  return true, true
end

local function endWriteWindow(createdUnlock)
  if createdUnlock and fs.exists(UNLOCK_FILE) then
    fs.delete(UNLOCK_FILE)
  end
end

local function fetchManifest()
  local data, err = download(MANIFEST_URL)
  if not data then
    return nil, err or "Could not fetch manifest"
  end
  local manifest = textutils.unserialiseJSON(data)
  if not manifest then
    return nil, "Failed to parse manifest JSON"
  end
  if not manifest.programs and manifest.games then
    manifest.programs = manifest.games
  end
  return manifest
end

--- Simple lock to prevent concurrent update runs.
local function acquireLock()
  if fs.exists(UPDATE_LOCK) then
    -- Check if lock is stale (>5 min old)
    local f = fs.open(UPDATE_LOCK, "r")
    if f then
      local raw = f.readAll()
      f.close()
      local lockTime = tonumber(raw)
      if lockTime and (os.epoch("local") - lockTime) / 1000 > 300 then
        fs.delete(UPDATE_LOCK)
      else
        return false
      end
    end
  end
  local f = fs.open(UPDATE_LOCK, "w")
  if f then
    f.write(tostring(os.epoch("local")))
    f.close()
    return true
  end
  return false
end

local function releaseLock()
  if fs.exists(UPDATE_LOCK) then
    fs.delete(UPDATE_LOCK)
  end
end

-----------------------------------------------------
-- Update logic
-----------------------------------------------------

--- Compare two version strings (e.g. "1.0.0" vs "1.1.0").
-- @return boolean  true if remote is newer than local
local function isNewer(remoteVer, localVer)
  if not remoteVer or not localVer then return remoteVer ~= localVer end
  -- Parse major.minor.patch
  local rParts = {}
  for p in tostring(remoteVer):gmatch("(%d+)") do
    rParts[#rParts + 1] = tonumber(p) or 0
  end
  local lParts = {}
  for p in tostring(localVer):gmatch("(%d+)") do
    lParts[#lParts + 1] = tonumber(p) or 0
  end
  for i = 1, math.max(#rParts, #lParts) do
    local r = rParts[i] or 0
    local l = lParts[i] or 0
    if r > l then return true end
    if r < l then return false end
  end
  return false
end

--- Perform the actual file update for a program.
-- Downloads code files, assets, and shared libs. Preserves config files.
-- @param manifest table
-- @param progKey  string
-- @param installed table  Current install info
-- @return boolean updated, number filesUpdated, number filesFailed
local function performUpdate(manifest, progKey, installed)
  local prog = manifest.programs[progKey]
  if not prog then
    return false, 0, 0
  end

  local unlockOk, unlockResult = beginWriteWindow("auto-update")
  if not unlockOk then
    logMsg("Update unlock failed: " .. tostring(unlockResult))
    return false, 0, 0
  end
  local createdUnlock = unlockResult == true

  local srcDir = prog.source_dir
  local downloads = {}

  -- Code files (always overwrite)
  for _, file in ipairs(prog.files or {}) do
    downloads[#downloads + 1] = {
      url  = REPO_URL .. srcDir .. "/" .. file,
      path = file,
    }
  end

  -- Config files — NEVER overwrite existing configs during auto-update
  for _, file in ipairs(prog.config_files or {}) do
    if not fs.exists(file) then
      downloads[#downloads + 1] = {
        url  = REPO_URL .. srcDir .. "/" .. file,
        path = file,
        tag  = "config",
      }
    end
  end

  -- Asset files
  for _, file in ipairs(prog.assets or {}) do
    downloads[#downloads + 1] = {
      url  = REPO_URL .. srcDir .. "/" .. file,
      path = file,
    }
  end

  -- Shared libraries
  if prog.uses_lib and manifest.lib and manifest.lib.files then
    for _, file in ipairs(manifest.lib.files) do
      downloads[#downloads + 1] = {
        url  = REPO_URL .. "Games/lib/" .. file,
        path = "lib/" .. file,
      }
    end
  end

  local success = 0
  local failed = 0

  for _, entry in ipairs(downloads) do
    local data, err = download(entry.url)
    if data then
      local ok, saveErr = saveFile(entry.path, data)
      if ok then
        success = success + 1
      else
        failed = failed + 1
        logMsg("Save failed: " .. entry.path .. " - " .. tostring(saveErr))
      end
    else
      failed = failed + 1
      logMsg("Download failed: " .. entry.path .. " - " .. tostring(err))
    end
    os.sleep(0)
  end

  -- Update install record
  saveInstalled({
    program      = progKey,
    version      = prog.version,
    content_hash = prog.content_hash,
    lib_version  = prog.uses_lib and manifest.lib and manifest.lib.version or nil,
    installed_at = installed.installed_at or os.epoch("local"),
    updated_at   = os.epoch("local"),
  })

  endWriteWindow(createdUnlock)
  return true, success, failed
end

-----------------------------------------------------
-- Public API
-----------------------------------------------------

--- Check for updates and apply them silently.
-- Safe to call on every startup.
-- Never throws errors; all failures are logged silently.
-- @param opts table|nil  Optional: { callback=function(status,msg) }
-- @return string status  "updated", "up-to-date", "skipped", or "error"
local function checkForUpdates(opts)
  opts = opts or {}
  local callback = opts.callback or function() end

  local status = "skipped"

  local ok, err = pcall(function()
    -- Lock to prevent concurrent runs
    if not acquireLock() then
      status = "skipped"
      callback("skipped", "Another update in progress")
      return
    end

    -- Load install info
    local installed = loadInstalled()
    if not installed then
      logMsg("No install record found — skipping update check")
      releaseLock()
      status = "skipped"
      callback("skipped", "No install record")
      return
    end

    local progKey = installed.program or installed.game
    if not progKey then
      logMsg("No program key in install record")
      releaseLock()
      status = "skipped"
      callback("skipped", "No program key")
      return
    end

    -- Fetch manifest
    callback("checking", "Fetching manifest...")
    local manifest, fetchErr = fetchManifest()
    if not manifest then
      logMsg("Manifest fetch failed: " .. tostring(fetchErr))
      releaseLock()
      status = "error"
      callback("error", "Manifest fetch failed: " .. tostring(fetchErr))
      return
    end

    local prog = manifest.programs[progKey]
    if not prog then
      logMsg("Program '" .. progKey .. "' not found in manifest")
      releaseLock()
      status = "error"
      callback("error", "Program not in manifest")
      return
    end

    -- Compare versions
    local localVer = installed.version or "0.0.0"
    local remoteVer = prog.version or "0.0.0"
    local localLibVer = installed.lib_version
    local remoteLibVer = (prog.uses_lib and manifest.lib) and manifest.lib.version or nil

    local needsUpdate = isNewer(remoteVer, localVer)
    local needsLibUpdate = remoteLibVer and localLibVer and isNewer(remoteLibVer, localLibVer)

    -- Also check content hash for changes without version bumps
    local localHash = installed.content_hash
    local remoteHash = prog.content_hash
    local hashChanged = remoteHash and localHash and remoteHash ~= localHash

    if not needsUpdate and not needsLibUpdate and not hashChanged then
      logMsg("Up to date: " .. progKey .. " v" .. localVer)
      releaseLock()
      status = "up-to-date"
      callback("up-to-date", progKey .. " local=v" .. localVer .. " remote=v" .. remoteVer
        .. " hash=" .. tostring(localHash):sub(1, 8) .. "/" .. tostring(remoteHash):sub(1, 8))
      return
    end

    -- Perform update
    local reason = ""
    if needsUpdate then
      reason = "v" .. localVer .. " -> v" .. remoteVer
    end
    if hashChanged and not needsUpdate then
      reason = reason ~= "" and (reason .. ", hash changed") or "hash changed"
    end
    if needsLibUpdate then
      local libReason = "lib v" .. tostring(localLibVer) .. " -> v" .. tostring(remoteLibVer)
      reason = reason ~= "" and (reason .. ", " .. libReason) or libReason
    end

    logMsg("Updating " .. progKey .. ": " .. reason)
    callback("updating", "Updating " .. progKey .. ": " .. reason)

    local updated, filesOk, filesFailed = performUpdate(manifest, progKey, installed)

    if updated and filesFailed == 0 then
      logMsg("Update complete: " .. filesOk .. " files updated")
      status = "updated"
      callback("updated", filesOk .. " files updated (" .. reason .. ")")
    elseif updated then
      logMsg("Update partial: " .. filesOk .. " ok, " .. filesFailed .. " failed")
      status = "updated"
      callback("updated", filesOk .. " files updated, " .. filesFailed .. " failed")
    else
      status = "error"
      callback("error", "Update failed")
    end

    releaseLock()
  end)

  if not ok then
    logMsg("Update check crashed: " .. tostring(err))
    pcall(releaseLock)
    status = "error"
    callback("error", "Crashed: " .. tostring(err))
  end

  return status
end

--- Get current install info for display.
-- @return table|nil  {program, version, lib_version, installed_at, updated_at}
local function getInstallInfo()
  return loadInstalled()
end

--- Force an update check.
-- @return string status
local function forceUpdate()
  return checkForUpdates()
end

--- Background polling loop that checks for updates at a fixed interval.
-- When an update is applied, automatically reboots the computer.
-- Designed to run inside parallel.waitForAny alongside the game loop.
-- @param opts table|nil  Optional: { interval=number (seconds, default 300), callback=function(status,msg) }
local function watchForUpdates(opts)
  opts = opts or {}
  local interval = opts.interval or 300
  local callback = opts.callback or function() end

  while true do
    os.sleep(interval)
    local status = checkForUpdates({ force = true, callback = callback })
    if status == "updated" then
      callback("rebooting", "Update applied, rebooting...")
      os.sleep(1)
      os.reboot()
    end
  end
end

return {
  checkForUpdates = checkForUpdates,
  forceUpdate     = forceUpdate,
  watchForUpdates = watchForUpdates,
  getInstallInfo  = getInstallInfo,
  isNewer         = isNewer,
}
