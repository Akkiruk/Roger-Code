-- Auto-updater module for ComputerCraft programs.
-- Checks the generated deploy index on startup and silently updates
-- code, assets, and vendored lib files when a new package is available.
-- Config files are preserved unless missing.
--
-- Usage (in startup.lua):
--   local updater = require("lib.updater")
--   updater.checkForUpdates()  -- silent, non-blocking on failure

local REPO_OWNER = "Akkiruk"
local REPO_NAME = "Roger-Code"
local DEPLOY_BRANCH = "deploy-index"
local RAW_ROOT = "https://raw.githubusercontent.com/" .. REPO_OWNER .. "/" .. REPO_NAME .. "/"
local DEPLOY_URL = RAW_ROOT .. DEPLOY_BRANCH .. "/"
local LATEST_URL = DEPLOY_URL .. "latest.json"
local VERSION_FILE = ".installed_program"
local MANAGED_FILES = ".roger_managed_files"
local LOG_FILE = "updater.log"
local UPDATE_LOCK = ".update_lock"
local LOCKDOWN_FILE = "vhcc_lockdown.txt"
local UNLOCK_FILE = ".vhcc_unlock"
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

local function parseJson(data, label)
  if type(data) ~= "string" then
    return nil, "Unexpected " .. tostring(label or "JSON") .. " data type"
  end

  local decoded = textutils.unserialiseJSON(data)
  if type(decoded) ~= "table" then
    return nil, "Failed to parse " .. tostring(label or "JSON")
  end

  return decoded
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

local function readFile(path, binary)
  if not fs.exists(path) then
    return nil
  end
  local mode = binary and "rb" or "r"
  local f = fs.open(path, mode)
  if not f then
    return nil
  end
  local data = f.readAll()
  f.close()
  return data
end

local function computeSha256(data)
  if textutils and type(textutils.sha256) == "function" then
    return textutils.sha256(data)
  end
  return nil
end

local function verifyHash(data, expected)
  if type(expected) ~= "string" or expected == "" then
    return true
  end

  local actual = computeSha256(data)
  if not actual then
    return true
  end

  return string.lower(actual) == string.lower(expected)
end

local function buildCommitUrl(commit, repoPath)
  return RAW_ROOT .. commit .. "/" .. repoPath
end

local function loadInstalled()
  if not fs.exists(VERSION_FILE) then
    return nil
  end
  local raw = readFile(VERSION_FILE, false)
  if not raw then
    return nil
  end
  local ok, info = pcall(function()
    return textutils.unserialise(raw)
  end)
  if ok and type(info) == "table" then
    return info
  end
  return nil
end

local function saveInstalled(info)
  local f = fs.open(VERSION_FILE, "w")
  if f then
    f.write(textutils.serialise(info))
    f.close()
  end
end

local function readManagedFiles()
  if not fs.exists(MANAGED_FILES) then
    return {}
  end

  local raw = readFile(MANAGED_FILES, false) or ""
  local items = {}
  local seen = {}
  for line in raw:gmatch("[^\r\n]+") do
    local path = line:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    if path ~= "" and not seen[path] then
      seen[path] = true
      items[#items + 1] = path
    end
  end
  table.sort(items)
  return items
end

local function saveManagedFiles(paths)
  table.sort(paths)
  local f = fs.open(MANAGED_FILES, "w")
  if not f then
    return
  end

  local seen = {}
  for _, path in ipairs(paths) do
    if path ~= "" and not seen[path] then
      seen[path] = true
      f.writeLine(path)
    end
  end
  f.close()
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

local function fetchLatestIndex()
  local data, err = download(LATEST_URL)
  if not data then
    return nil, err or "Could not fetch deploy index"
  end
  return parseJson(data, "deploy index")
end

local function fetchProgramSpec(specPath)
  local data, err = download(DEPLOY_URL .. specPath)
  if not data then
    return nil, err or "Could not fetch program spec"
  end
  return parseJson(data, "program spec")
end

--- Simple lock to prevent concurrent update runs.
local function acquireLock()
  if fs.exists(UPDATE_LOCK) then
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

local function removePath(path)
  if fs.exists(path) then
    fs.delete(path)
  end
end

local function removeStaleFiles(previouslyManaged, desiredPaths)
  local wanted = {}
  for _, path in ipairs(desiredPaths) do
    wanted[path] = true
  end

  for _, path in ipairs(previouslyManaged) do
    if not wanted[path] and path ~= VERSION_FILE and path ~= MANAGED_FILES then
      removePath(path)
    end
  end
end

-----------------------------------------------------
-- Update logic
-----------------------------------------------------

local function performUpdate(spec, installed)
  local unlockOk, unlockResult = beginWriteWindow("auto-update")
  if not unlockOk then
    logMsg("Update unlock failed: " .. tostring(unlockResult))
    return false, 0, 0
  end
  local createdUnlock = unlockResult == true

  local build = spec.build or {}
  local program = spec.program or {}
  local managedPaths = {}
  local success = 0
  local failed = 0
  local previouslyManaged = readManagedFiles()

  for _, entry in ipairs(spec.install.files or {}) do
    managedPaths[#managedPaths + 1] = entry.install_path
  end

  removeStaleFiles(previouslyManaged, managedPaths)

  for _, entry in ipairs(spec.install.files or {}) do
    if entry.preserve_existing and fs.exists(entry.install_path) then
      success = success + 1
    else
      local data, err = download(buildCommitUrl(build.commit, entry.repo_path))
      if data and verifyHash(data, entry.sha256) then
        if fs.exists(entry.install_path) then
          fs.delete(entry.install_path)
        end
        local saveOk, saveErr = saveFile(entry.install_path, data)
        if saveOk then
          success = success + 1
        else
          failed = failed + 1
          logMsg("Save failed: " .. tostring(entry.install_path) .. " - " .. tostring(saveErr))
        end
      else
        failed = failed + 1
        logMsg("Download failed: " .. tostring(entry.install_path) .. " - " .. tostring(err or "hash mismatch"))
      end
    end
    os.sleep(0)
  end

  if failed == 0 then
    saveManagedFiles(managedPaths)
    saveInstalled({
      schema_version = 1,
      program = program.key,
      name = program.name,
      version = program.version,
      source_commit = build.commit,
      package_hash = build.package_hash,
      content_hash = build.package_hash,
      spec_path = spec._spec_path or installed.spec_path or "",
      installed_at = installed.installed_at or os.epoch("local"),
      updated_at = os.epoch("local"),
    })
  end

  endWriteWindow(createdUnlock)
  return failed == 0, success, failed
end

-----------------------------------------------------
-- Public API
-----------------------------------------------------

local function checkForUpdates(opts)
  opts = opts or {}
  local callback = opts.callback or function() end
  local status = "skipped"

  local ok, err = pcall(function()
    if not acquireLock() then
      status = "skipped"
      callback("skipped", "Another update in progress")
      return
    end

    local installed = loadInstalled()
    if not installed then
      logMsg("No install record found - skipping update check")
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

    callback("checking", "Fetching deploy index...")
    local index, fetchErr = fetchLatestIndex()
    if not index then
      logMsg("Deploy index fetch failed: " .. tostring(fetchErr))
      releaseLock()
      status = "error"
      callback("error", "Deploy index fetch failed: " .. tostring(fetchErr))
      return
    end

    local programEntry = index.programs and index.programs[progKey] or nil
    if not programEntry then
      logMsg("Program '" .. progKey .. "' not found in deploy index")
      releaseLock()
      status = "error"
      callback("error", "Program not in deploy index")
      return
    end

    local localCommit = installed.source_commit or ""
    local remoteCommit = programEntry.commit or ""
    local localHash = installed.package_hash or installed.content_hash or ""
    local remoteHash = programEntry.package_hash or ""

    if localCommit == remoteCommit and localHash == remoteHash then
      logMsg("Up to date: " .. progKey .. " v" .. tostring(installed.version or "?"))
      releaseLock()
      status = "up-to-date"
      callback("up-to-date", progKey .. " local=" .. tostring(installed.version or "?")
        .. " commit=" .. tostring(localCommit):sub(1, 8))
      return
    end

    local reason = ""
    if localCommit ~= remoteCommit then
      reason = "commit changed"
    end
    if localHash ~= remoteHash then
      reason = reason ~= "" and (reason .. ", package changed") or "package changed"
    end

    callback("updating", "Fetching package spec...")
    local spec, specErr = fetchProgramSpec(programEntry.spec_path)
    if not spec then
      logMsg("Spec fetch failed for " .. progKey .. ": " .. tostring(specErr))
      releaseLock()
      status = "error"
      callback("error", "Spec fetch failed: " .. tostring(specErr))
      return
    end
    spec._spec_path = programEntry.spec_path

    logMsg("Updating " .. progKey .. ": " .. reason)
    callback("updating", "Updating " .. progKey .. ": " .. reason)

    local updated, filesOk, filesFailed = performUpdate(spec, installed)
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

local function getInstallInfo()
  return loadInstalled()
end

local function forceUpdate()
  return checkForUpdates()
end

local function watchForUpdates(opts)
  opts = opts or {}
  local interval = opts.interval or 300
  local callback = opts.callback or function() end

  while true do
    os.sleep(interval)
    local status = checkForUpdates({ callback = callback })
    if status == "updated" then
      callback("rebooting", "Update applied, rebooting...")
      os.sleep(1)
      os.reboot()
    end
  end
end

return {
  checkForUpdates = checkForUpdates,
  forceUpdate = forceUpdate,
  watchForUpdates = watchForUpdates,
  getInstallInfo = getInstallInfo,
}
