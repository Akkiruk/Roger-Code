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
local DEFAULT_WATCH_INTERVAL = 300
local DEFAULT_STARTUP_INTERVALS = { 5, 5, 10, 10, 15, 15, 30, 30, 60, 60, 120 }
local API_URL = "https://api.github.com/repos/" .. REPO_OWNER .. "/" .. REPO_NAME
local CONTENTS_API_ROOT = API_URL .. "/contents/"
local CONTENTS_API_HEADERS = {
  ["User-Agent"] = "Roger-Code-Updater",
  ["Accept"] = "application/vnd.github.raw+json",
}
local INSTALLER_PATH = "installer.lua"
local INSTALL_STATE_SCHEMA = 2
local RESERVED_LOCAL_PATHS = {
  [VERSION_FILE] = true,
  [MANAGED_FILES] = true,
  [LOG_FILE] = true,
  ["installer_error.log"] = true,
  ["crash_recovery.log"] = true,
  ["phone_os_startup.log"] = true,
  ["vaultgear_error.log"] = true,
  ["vhcc_lockdown.txt"] = true,
  ["installer.lua"] = true,
  [UNLOCK_FILE] = true,
}
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

local function download(url, headers)
  local ok, response = pcall(function()
    return http.get(url, headers, true)
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
    local makeOk, makeErr = pcall(fs.makeDir, dir)
    if not makeOk then
      return false, tostring(makeErr)
    end
  end
  local openOk, f = pcall(fs.open, path, "wb")
  if not openOk then
    return false, tostring(f)
  end
  if not f then
    return false, "Cannot write: " .. path
  end

  local writeOk, writeErr = pcall(function()
    f.write(data)
    f.close()
  end)
  if not writeOk then
    pcall(function()
      if f.close then
        f.close()
      end
    end)
    return false, tostring(writeErr)
  end

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

local function withCacheBust(url)
  local separator = url:find("?", 1, true) and "&" or "?"
  return url .. separator .. "t=" .. tostring(os.epoch("local"))
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

local function buildInstalledRecord(spec, previous)
  local program = spec.program or {}
  local build = spec.build or {}
  local runtime = spec.runtime or {}
  local existing = previous or {}

  return {
    schema_version = INSTALL_STATE_SCHEMA,
    program = program.key,
    name = program.name,
    version = program.version,
    source_commit = build.commit,
    package_hash = build.package_hash,
    content_hash = build.package_hash,
    spec_path = spec._spec_path or existing.spec_path or "",
    installed_at = existing.installed_at or os.epoch("local"),
    updated_at = os.epoch("local"),
    boot_mode = runtime.boot_mode or existing.boot_mode or "supervisor",
    system_entrypoint = runtime.system_entrypoint or existing.system_entrypoint or "startup.lua",
    app_entrypoint = runtime.app_entrypoint or existing.app_entrypoint or program.entrypoint or "",
    auto_restart = runtime.auto_restart ~= false,
    update_interval = tonumber(runtime.update_interval) or tonumber(existing.update_interval) or DEFAULT_WATCH_INTERVAL,
  }
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

local function fetchDeployJson(path, label)
  local rawUrl = withCacheBust(DEPLOY_URL .. path)
  local data, err = download(rawUrl)
  if data then
    local parsed, parseErr = parseJson(data, label)
    if parsed then
      return parsed
    end
    err = parseErr
  end

  local apiUrl = withCacheBust(CONTENTS_API_ROOT .. path .. "?ref=" .. DEPLOY_BRANCH)
  data, err = download(apiUrl, CONTENTS_API_HEADERS)
  if not data then
    return nil, err or ("Could not fetch " .. tostring(label or "deploy metadata"))
  end
  return parseJson(data, label)
end

local function fetchLatestIndex()
  return fetchDeployJson("latest.json", "deploy index")
end

local function fetchProgramSpec(specPath)
  return fetchDeployJson(specPath, "program spec")
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

local function deletePath(path)
  if not fs.exists(path) then
    return true
  end

  local ok, err = pcall(fs.delete, path)
  if not ok then
    return false, tostring(err)
  end

  return true
end

local function removePath(path)
  if fs.exists(path) then
    fs.delete(path)
  end
end

local function normalizePath(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function refreshInstaller(index)
  local installer = index and index.installer or nil
  if type(installer) ~= "table" then
    return true, false, "No installer metadata"
  end

  local installerPath = normalizePath(installer.install_path or installer.path or INSTALLER_PATH)
  if installerPath == "" then
    installerPath = INSTALLER_PATH
  end

  local currentData = readFile(installerPath, true)
  if currentData and verifyHash(currentData, installer.sha256) then
    return true, false, "Installer up to date"
  end

  local commit = installer.commit
  local repoPath = installer.path
  if type(commit) ~= "string" or commit == "" or type(repoPath) ~= "string" or repoPath == "" then
    return false, false, "Installer metadata incomplete"
  end

  local unlockOk, unlockResult = beginWriteWindow("installer-refresh")
  if not unlockOk then
    return false, false, "Installer write locked: " .. tostring(unlockResult)
  end
  local createdUnlock = unlockResult == true

  local data, err = download(buildCommitUrl(commit, repoPath))
  if not data then
    endWriteWindow(createdUnlock)
    return false, false, err or "Installer download failed"
  end
  if not verifyHash(data, installer.sha256) then
    endWriteWindow(createdUnlock)
    return false, false, "Installer hash mismatch"
  end

  if fs.exists(installerPath) then
    local deleteOk, deleteErr = deletePath(installerPath)
    if not deleteOk then
      endWriteWindow(createdUnlock)
      return false, false, deleteErr or "Installer delete failed"
    end
  end

  local saved, saveErr = saveFile(installerPath, data)
  if not saved then
    endWriteWindow(createdUnlock)
    return false, false, saveErr or "Installer save failed"
  end

  endWriteWindow(createdUnlock)

  return true, true, installerPath
end

local function pathSetFromList(paths)
  local set = {}
  for _, path in ipairs(paths or {}) do
    set[normalizePath(path)] = true
  end
  return set
end

local function listFilesRecursive(root, prefix, out)
  out = out or {}
  prefix = prefix or ""
  if not fs.exists(root) then
    return out
  end

  for _, name in ipairs(fs.list(root)) do
    local child = fs.combine(root, name)
    local rel = prefix ~= "" and (prefix .. "/" .. name) or name
    if fs.isDir(child) then
      listFilesRecursive(child, rel, out)
    else
      out[#out + 1] = normalizePath(rel)
    end
  end

  return out
end

local function cleanupStaleRuntimeArtifacts()
  removePath(".install_staging")
  removePath(".update_staging")
end

local function buildWatchSchedule(opts)
  local options = opts or {}
  local steadyInterval = tonumber(options.interval) or DEFAULT_WATCH_INTERVAL
  if steadyInterval < 5 then
    steadyInterval = 5
  end

  local startupIntervals = options.startupIntervals
  if startupIntervals == false then
    return {}, steadyInterval
  end
  if type(startupIntervals) ~= "table" then
    startupIntervals = DEFAULT_STARTUP_INTERVALS
  end

  local schedule = {}
  for _, entry in ipairs(startupIntervals) do
    local delay = tonumber(entry)
    if delay and delay > 0 then
      schedule[#schedule + 1] = delay
    end
  end

  return schedule, steadyInterval
end

local function isLegacyPayloadPath(path)
  if path:sub(1, 4) == "lib/" then
    return true
  end

  if path:find("/", 1, true) then
    return false
  end

  if path:match("%.lua$") or path:match("%.nfp$") then
    return true
  end

  return path == "font"
    or path == "surface"
    or path == "gothic"
    or path == "logo.nfp"
end

local function pruneLegacyPayload(desiredPaths)
  local existingManaged = readManagedFiles()
  if #existingManaged > 0 then
    return
  end

  local desired = pathSetFromList(desiredPaths)
  local files = listFilesRecursive(".", "", {})
  for _, rel in ipairs(files) do
    local normalized = normalizePath(rel)
    if isLegacyPayloadPath(normalized)
      and not desired[normalized]
      and not RESERVED_LOCAL_PATHS[normalized] then
      removePath(normalized)
    end
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
  cleanupStaleRuntimeArtifacts()

  for _, entry in ipairs(spec.install.files or {}) do
    managedPaths[#managedPaths + 1] = entry.install_path
  end

  removeStaleFiles(previouslyManaged, managedPaths)
  pruneLegacyPayload(managedPaths)

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
    saveInstalled(buildInstalledRecord(spec, installed))
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
  local rebootOnUpdate = opts.rebootOnUpdate == true
  local rebootDelay = tonumber(opts.rebootDelay) or 1
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

    local installerOk, installerUpdated, installerMessage = refreshInstaller(index)
    if installerUpdated then
      logMsg("Installer refreshed: " .. tostring(installerMessage or INSTALLER_PATH))
      callback("updating", "Refreshed installer.lua")
    elseif not installerOk then
      logMsg("Installer refresh failed: " .. tostring(installerMessage))
      callback("warning", "Installer refresh failed: " .. tostring(installerMessage))
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

    if status == "updated" and rebootOnUpdate then
      logMsg("Rebooting after update")
      callback("rebooting", "Update applied, rebooting...")
      releaseLock()
      os.sleep(rebootDelay)
      os.reboot()
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
  local callback = opts.callback or function() end
  local verbose = opts.verbose == true
  local startupSchedule, steadyInterval = buildWatchSchedule(opts)
  local startupIndex = 1
  local lastStatus = nil
  local lastMessage = nil

  local function notify(status, message)
    local normalizedMessage = tostring(message or "")

    if not verbose and (status == "checking" or status == "up-to-date" or status == "skipped") then
      return
    end

    if not verbose and status == lastStatus and normalizedMessage == lastMessage then
      return
    end

    lastStatus = status
    lastMessage = normalizedMessage
    callback(status, message)
  end

  while true do
    local interval = startupSchedule[startupIndex] or steadyInterval
    os.sleep(interval)

    local status = checkForUpdates({ callback = notify })
    if status == "updated" then
      notify("rebooting", "Update applied, rebooting...")
      os.sleep(1)
      os.reboot()
    end

    if startupSchedule[startupIndex] then
      startupIndex = startupIndex + 1
    end
  end
end

return {
  checkForUpdates = checkForUpdates,
  forceUpdate = forceUpdate,
  watchForUpdates = watchForUpdates,
  getInstallInfo = getInstallInfo,
}
