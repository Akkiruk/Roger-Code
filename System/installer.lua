-- installer.lua
-- Program Installer & Updater for ComputerCraft
--
-- Bootstrap (paste into CC shell):
--   wget https://raw.githubusercontent.com/Akkiruk/Roger-Code/main/System/installer.lua
--
-- Usage:
--   installer              -- Interactive menu
--   installer <name>       -- Install/update a specific program
--   installer update       -- Update currently installed program
--   installer self-update  -- Update just the installer
--   installer wipe         -- Delete everything except the installer script

local INSTALLER_VERSION = "1.1.7"
local REPO_OWNER = "Akkiruk"
local REPO_NAME = "Roger-Code"
local SOURCE_BRANCH = "main"
local DEPLOY_BRANCH = "deploy-index"
local RAW_ROOT = "https://raw.githubusercontent.com/" .. REPO_OWNER .. "/" .. REPO_NAME .. "/"
local DEPLOY_URL = RAW_ROOT .. DEPLOY_BRANCH .. "/"
local LATEST_URL = DEPLOY_URL .. "latest.json"
local VERSION_FILE = ".installed_program"
local MANAGED_FILES = ".roger_managed_files"
local PHONE_HOST_MARKER_FILE = ".phone_os_host_claimed"
local LOG_FILE = "installer_error.log"
local LOCKDOWN_FILE = "vhcc_lockdown.txt"
local UNLOCK_FILE = ".vhcc_unlock"
local API_URL = "https://api.github.com/repos/" .. REPO_OWNER .. "/" .. REPO_NAME
local API_HEADERS = {
  ["User-Agent"] = "Roger-Code-Installer",
  ["Accept"] = "application/vnd.github+json",
}
local CONTENTS_API_ROOT = API_URL .. "/contents/"
local CONTENTS_API_HEADERS = {
  ["User-Agent"] = "Roger-Code-Installer",
  ["Accept"] = "application/vnd.github.raw+json",
}
local HIDDEN_STANDALONE_PROGRAMS = {
  peripheral_info_collector = true,
  test_ccvault = true,
  test_ccvault_full = true,
}
local STANDALONE_SKIP_SUFFIXES = {
  ".bak",
  ".old",
  ".log",
  ".md",
}
local INSTALL_STATE_SCHEMA = 2
local DEFAULT_UPDATE_INTERVAL = 300
local UPDATED_ARG = "--installer-updated"
local RESERVED_LOCAL_PATHS = {
  [VERSION_FILE] = true,
  [MANAGED_FILES] = true,
  [PHONE_HOST_MARKER_FILE] = true,
  [LOG_FILE] = true,
  ["updater.log"] = true,
  ["crash_recovery.log"] = true,
  ["phone_os_startup.log"] = true,
  ["vaultgear_error.log"] = true,
  ["vhcc_lockdown.txt"] = true,
  ["installer.lua"] = true,
  [UNLOCK_FILE] = true,
}

local tArgs = { ... }
-- Forward declarations keep Lua 5.1 local scope intact for helpers used
-- by earlier-defined functions in this file.
local readManagedFiles = nil
local fetchLatestMainCommit = nil

---------------------------------------------------------------------------
-- Error logging
---------------------------------------------------------------------------
local function logError(msg)
  local f = fs.open(LOG_FILE, "a")
  if f then
    f.writeLine("[" .. os.epoch("local") .. "] " .. tostring(msg))
    f.close()
  end
end

---------------------------------------------------------------------------
-- UI helpers
---------------------------------------------------------------------------
local W, H = term.getSize()

local function cls()
  term.clear()
  term.setCursorPos(1, 1)
end

local function cprint(color, text)
  term.setTextColor(color)
  print(text)
  term.setTextColor(colors.white)
end

local function cwrite(color, text)
  term.setTextColor(color)
  write(text)
  term.setTextColor(colors.white)
end

local function header(title)
  cls()
  local line = string.rep("-", W)
  cprint(colors.cyan, line)
  cprint(colors.cyan, " " .. title)
  cprint(colors.cyan, line)
  print("")
end

local function progressBar(current, total, width)
  width = width or 20
  local safeTotal = total > 0 and total or 1
  local filled = math.floor((current / safeTotal) * width)
  return "[" .. string.rep("=", filled)
    .. string.rep(" ", width - filled) .. "] "
    .. current .. "/" .. total
end

local function unpackArgs(args, startIndex)
  if table.unpack then
    return table.unpack(args, startIndex or 1)
  end
  return unpack(args, startIndex or 1)
end

local function parseInstallerArgs(rawArgs)
  local args = {}
  local updatedTo = nil
  local updatedFrom = nil
  local index = 1

  while index <= #rawArgs do
    local value = rawArgs[index]
    if value == UPDATED_ARG then
      updatedTo = rawArgs[index + 1]
      updatedFrom = rawArgs[index + 2]
      index = index + 3
    else
      args[#args + 1] = value
      index = index + 1
    end
  end

  return args, updatedTo, updatedFrom
end

---------------------------------------------------------------------------
-- HTTP / file helpers
---------------------------------------------------------------------------
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

local function withCacheBust(url)
  local separator = url:find("?", 1, true) and "&" or "?"
  return url .. separator .. "t=" .. tostring(os.epoch("local"))
end

local function removePath(path)
  if fs.exists(path) then
    fs.delete(path)
  end
end

local function normalizePath(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function basename(path)
  local normalized = normalizePath(path)
  local name = normalized:match("([^/]+)$")
  return name or normalized
end

local function fileNameNoExt(path)
  local name = basename(path)
  return (name:gsub("%.lua$", ""))
end

local function shouldSkipStandaloneUtility(path)
  local name = string.lower(basename(path))
  if name == "manifest.json" then
    return true
  end

  for _, suffix in ipairs(STANDALONE_SKIP_SUFFIXES) do
    if name:sub(-#suffix) == suffix then
      return true
    end
  end

  return false
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

local function downloadAndSaveVerified(url, finalPath, expectedSha)
  local data, err = download(url)
  if not data then
    return false, err
  end

  if not verifyHash(data, expectedSha) then
    return false, "Hash mismatch for " .. tostring(url)
  end

  if fs.exists(finalPath) then
    fs.delete(finalPath)
  end

  return saveFile(finalPath, data)
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
    return nil, err
  end
  return parseJson(data, label)
end

local repoTextCache = {}

local function fetchRepoText(path, ref)
  local repoPath = normalizePath(path)
  local targetRef = tostring(ref or SOURCE_BRANCH)
  local cacheKey = targetRef .. ":" .. repoPath
  if repoTextCache[cacheKey] then
    return repoTextCache[cacheKey]
  end

  local rawUrl = withCacheBust(RAW_ROOT .. targetRef .. "/" .. repoPath)
  local data, err = download(rawUrl)
  if not data then
    local apiUrl = withCacheBust(CONTENTS_API_ROOT .. repoPath .. "?ref=" .. targetRef)
    data, err = download(apiUrl, CONTENTS_API_HEADERS)
    if not data then
      return nil, err
    end
  end

  repoTextCache[cacheKey] = data
  return data
end

local function fetchRepoTree(ref)
  local url = withCacheBust(API_URL .. "/git/trees/" .. tostring(ref or SOURCE_BRANCH) .. "?recursive=1")
  local data, err = download(url, API_HEADERS)
  if not data then
    return nil, err
  end
  return parseJson(data, "repo tree")
end

local function splitPreviewLines(text, limit)
  local lines = {}
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
    if limit and #lines >= limit then
      break
    end
  end
  return lines
end

local function parseStandaloneMetadata(fileName, text)
  local key = string.lower(fileNameNoExt(fileName))
  local name = fileNameNoExt(fileName)
  local description = ""

  for _, line in ipairs(splitPreviewLines(text, 12)) do
    local value = line:match('^%s*%-%-%s*manifest%-key:%s*(.+)%s*$')
    if value and value ~= "" then
      key = value
    else
      value = line:match('^%s*%-%-%s*manifest%-name:%s*(.+)%s*$')
      if value and value ~= "" then
        name = value
      else
        value = line:match('^%s*%-%-%s*manifest%-description:%s*(.+)%s*$')
        if value and value ~= "" and description == "" then
          description = value
        else
          value = line:match('^%s*%-%-%s*(.+)%s*$')
          if value
            and #value > 10
            and not value:match('^manifest%-(key|name|description|category):')
            and not value:match('^%S+%.lua$')
            and not value:match('^[-=]+$')
            and description == "" then
            description = value
          end
        end
      end
    end
  end

  return {
    key = key,
    name = name,
    description = description,
    category = "Utilities",
    entrypoint = fileName,
    source_root = "Utilities",
  }
end

local function findRequiredLibModules(text)
  local modules = {}
  local seen = {}

  local function addModule(module)
    if module and module ~= "" and module:sub(1, 4) == "lib." and not seen[module] then
      seen[module] = true
      modules[#modules + 1] = module
    end
  end

  for module in tostring(text or ""):gmatch('require%s*%(%s*"(lib%.[^"]+)"%s*%)') do
    addModule(module)
  end
  for module in tostring(text or ""):gmatch("require%s*%(%s*'(lib%.[^']+)'%s*%)") do
    addModule(module)
  end
  for module in tostring(text or ""):gmatch('require%s+"(lib%.[^"]+)"') do
    addModule(module)
  end
  for module in tostring(text or ""):gmatch("require%s+'(lib%.[^']+)'") do
    addModule(module)
  end

  table.sort(modules)
  return modules
end

local function buildStandaloneLibClosure(fileName, commit)
  local queue = { "Utilities/" .. fileName }
  local seenRepoPaths = { ["Utilities/" .. fileName] = true }
  local closure = {}
  local seenLibs = {}
  local index = 1

  while index <= #queue do
    local repoPath = queue[index]
    index = index + 1

    local text = fetchRepoText(repoPath, commit)
    if text then
      for _, module in ipairs(findRequiredLibModules(text)) do
        local libRelative = module:sub(5):gsub('%.', '/') .. ".lua"
        local libRepoPath = "Shared/lib/" .. libRelative
        if not seenLibs[libRelative] then
          seenLibs[libRelative] = true
          closure[#closure + 1] = libRelative
        end
        if not seenRepoPaths[libRepoPath] then
          seenRepoPaths[libRepoPath] = true
          queue[#queue + 1] = libRepoPath
        end
      end
    end
  end

  table.sort(closure)
  return closure
end

local function buildInstallFileEntry(commit, repoPath, installPath, preserveExisting)
  local data, err = fetchRepoText(repoPath, commit)
  if not data then
    return nil, err
  end

  local entry = {
    repo_path = repoPath,
    install_path = installPath,
    sha256 = computeSha256(data) or "",
  }
  if preserveExisting then
    entry.preserve_existing = true
  end
  return entry
end

local function buildStandaloneUtilitySpec(repoPath, commit)
  local fileName = basename(repoPath)
  local fileData, fileErr = fetchRepoText(repoPath, commit)
  if not fileData then
    return nil, fileErr
  end

  local meta = parseStandaloneMetadata(fileName, fileData)
  local installFiles = {}
  local runtimeFiles = {
    { repo_path = "System/runtime_startup.lua", install_path = "startup.lua" },
    { repo_path = "Shared/lib/roger_supervisor.lua", install_path = "lib/roger_supervisor.lua" },
    { repo_path = "Shared/lib/updater.lua", install_path = "lib/updater.lua" },
    { repo_path = repoPath, install_path = fileName },
  }

  for _, item in ipairs(runtimeFiles) do
    local entry, entryErr = buildInstallFileEntry(commit, item.repo_path, item.install_path, item.preserve_existing)
    if not entry then
      return nil, entryErr
    end
    installFiles[#installFiles + 1] = entry
  end

  local libModules = {}
  for _, libRelative in ipairs(buildStandaloneLibClosure(fileName, commit)) do
    local repoLibPath = "Shared/lib/" .. libRelative
    local entry, entryErr = buildInstallFileEntry(commit, repoLibPath, "lib/" .. libRelative, false)
    if not entry then
      return nil, entryErr
    end
    installFiles[#installFiles + 1] = entry
    libModules[#libModules + 1] = "lib." .. libRelative:gsub('%.lua$', ''):gsub('/', '.')
  end

  table.sort(installFiles, function(a, b)
    if a.install_path == b.install_path then
      return a.repo_path < b.repo_path
    end
    return a.install_path < b.install_path
  end)

  local hashLines = {}
  for _, entry in ipairs(installFiles) do
    hashLines[#hashLines + 1] = tostring(entry.install_path) .. "|" .. tostring(entry.repo_path) .. "|"
      .. tostring(entry.preserve_existing == true) .. "|" .. tostring(entry.sha256 or "")
  end
  local packageHash = computeSha256(table.concat(hashLines, "\n")) or tostring(commit) .. ":" .. meta.key
  local version = "tree-" .. tostring(commit):sub(1, 7)

  return {
    schema_version = 1,
    program = {
      key = meta.key,
      name = meta.name,
      category = meta.category,
      description = meta.description,
      source_root = meta.source_root,
      entrypoint = meta.entrypoint,
      version = version,
    },
    build = {
      commit = commit,
      generated_at = tostring(os.epoch("utc") or os.epoch("local")),
      package_hash = packageHash,
    },
    install = {
      preserve = {},
      files = installFiles,
    },
    runtime = {
      boot_mode = "supervisor",
      system_entrypoint = "startup.lua",
      app_entrypoint = fileName,
      auto_restart = false,
      update_interval = DEFAULT_UPDATE_INTERVAL,
      requires_updater = true,
      lib_modules = libModules,
    },
  }
end

local function buildRepoTreeStandaloneIndex()
  local commit, commitErr = fetchLatestMainCommit()
  if not commit then
    return nil, commitErr
  end

  local tree, treeErr = fetchRepoTree(SOURCE_BRANCH)
  if not tree or type(tree.tree) ~= "table" then
    return nil, treeErr or "Repo tree missing entries"
  end

  local installerData, installerErr = fetchRepoText("System/installer.lua", commit)
  if not installerData then
    return nil, installerErr
  end

  local installerVersion = installerData:match('local%s+INSTALLER_VERSION%s*=%s*"([^"]+)"') or INSTALLER_VERSION
  local index = {
    schema_version = 1,
    generated_at = tostring(os.epoch("utc") or os.epoch("local")),
    repo = {
      owner = REPO_OWNER,
      name = REPO_NAME,
      branch = SOURCE_BRANCH,
    },
    installer = {
      version = installerVersion,
      commit = commit,
      path = "System/installer.lua",
      sha256 = computeSha256(installerData) or "",
    },
    programs = {},
    _inline_specs = {},
    _catalog_source = "repo tree",
  }

  local repoPaths = {}
  for _, entry in ipairs(tree.tree) do
    if entry.type == "blob" and type(entry.path) == "string" then
      local utilityFile = entry.path:match('^Utilities/([^/]+%.lua)$')
      if utilityFile and not shouldSkipStandaloneUtility(utilityFile) then
        local hiddenKey = string.lower(fileNameNoExt(utilityFile))
        if not HIDDEN_STANDALONE_PROGRAMS[hiddenKey] then
          repoPaths[#repoPaths + 1] = normalizePath(entry.path)
        end
      end
    end
  end
  table.sort(repoPaths)

  for _, repoPath in ipairs(repoPaths) do
    local spec, specErr = buildStandaloneUtilitySpec(repoPath, commit)
    if spec then
      local program = spec.program or {}
      index.programs[program.key] = {
        name = program.name,
        category = program.category,
        description = program.description,
        version = program.version,
        commit = commit,
        package_hash = spec.build and spec.build.package_hash or "",
      }
      index._inline_specs[program.key] = spec
    else
      logError("Repo tree utility discovery failed for " .. tostring(repoPath) .. ": " .. tostring(specErr))
    end
  end

  return index
end

local function mergeRepoTreeStandalonePrograms(index, directIndex)
  if type(index) ~= "table" then
    return directIndex
  end
  if type(directIndex) ~= "table" then
    return index
  end

  index.programs = index.programs or {}
  index._inline_specs = index._inline_specs or {}

  for key, spec in pairs(directIndex._inline_specs or {}) do
    index._inline_specs[key] = spec
  end

  for key, program in pairs(directIndex.programs or {}) do
    local existing = index.programs[key]
    if not existing then
      index.programs[key] = program
    else
      if existing.name == key then
        existing.name = program.name
      end
      if (not existing.description or existing.description == "") and program.description and program.description ~= "" then
        existing.description = program.description
      end
      if not existing.category or existing.category == "" then
        existing.category = program.category
      end
    end
  end

  if not index.installer and directIndex.installer then
    index.installer = directIndex.installer
  end

  index._catalog_source = "deploy index + repo tree"
  return index
end

local function fetchLatestIndex()
  local deployIndex, deployErr = fetchDeployJson("latest.json", "deploy index")
  local directIndex, directErr = buildRepoTreeStandaloneIndex()

  if deployIndex and directIndex then
    return mergeRepoTreeStandalonePrograms(deployIndex, directIndex)
  end

  if deployIndex then
    deployIndex._catalog_source = "deploy index"
    return deployIndex
  end

  if directIndex then
    return directIndex
  end

  return nil, "Deploy index failed: " .. tostring(deployErr) .. "; repo tree failed: " .. tostring(directErr)
end

local function fetchProgramSpec(specPath)
  return fetchDeployJson(specPath, "program spec")
end

fetchLatestMainCommit = function()
  local data, err = download(API_URL .. "/commits/" .. SOURCE_BRANCH, API_HEADERS)
  if not data then
    return nil, err
  end

  local info, parseErr = parseJson(data, "commit metadata")
  if not info then
    return nil, parseErr
  end

  if type(info.sha) ~= "string" or info.sha == "" then
    return nil, "Commit metadata did not include a SHA"
  end

  return info.sha
end

local function buildCommitUrl(commit, repoPath)
  return RAW_ROOT .. commit .. "/" .. repoPath
end

---------------------------------------------------------------------------
-- Installed state
---------------------------------------------------------------------------
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
    boot_mode = runtime.boot_mode or "supervisor",
    system_entrypoint = runtime.system_entrypoint or "startup.lua",
    app_entrypoint = runtime.app_entrypoint or program.entrypoint or "",
    auto_restart = runtime.auto_restart ~= false,
    update_interval = tonumber(runtime.update_interval) or DEFAULT_UPDATE_INTERVAL,
  }
end

readManagedFiles = function()
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
  local seen = {}
  table.sort(paths)
  local f = fs.open(MANAGED_FILES, "w")
  if not f then
    return
  end
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
    source = tag or "installer",
    openedAt = os.epoch("local"),
    persistent = true,
  }))
  f.close()
  return true, false
end

local function endWriteWindow(createdUnlock)
  if createdUnlock and fs.exists(UNLOCK_FILE) then
    fs.delete(UNLOCK_FILE)
  end
end

local function writePhoneHostMarker(info)
  local f = fs.open(PHONE_HOST_MARKER_FILE, "w")
  if not f then
    return false, "Cannot write phone host marker"
  end

  f.write(textutils.serialise(info))
  f.close()
  return true
end

local function claimPhoneHostIfNeeded(shouldClaim)
  if not shouldClaim then
    return true
  end

  if not ccvault or type(ccvault.claimHost) ~= "function" then
    return false, "ccvault.claimHost is unavailable"
  end

  local ok, result, err = pcall(ccvault.claimHost)
  if not ok then
    return false, tostring(result)
  end
  if type(result) ~= "table" then
    return false, tostring(err or "host claim failed")
  end

  local markerOk, markerErr = writePhoneHostMarker({
    claimed_at = os.epoch("local"),
    computer_id = (ccvault.getComputerId and ccvault.getComputerId()) or os.getComputerID(),
    host_name = result.hostName,
    changed = result.changed == true,
  })
  if not markerOk then
    return false, markerErr
  end

  return true, result
end

---------------------------------------------------------------------------
-- Package install helpers
---------------------------------------------------------------------------
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

local function wipeManagedFiles(paths)
  local wiped = {}
  for _, path in ipairs(paths or {}) do
    local normalized = normalizePath(path)
    if normalized ~= ""
      and not wiped[normalized]
      and normalized ~= VERSION_FILE
      and normalized ~= MANAGED_FILES
      and not RESERVED_LOCAL_PATHS[normalized] then
      removePath(normalized)
      wiped[normalized] = true
    end
  end
end

local function addPreservedPath(set, path)
  local normalized = normalizePath(path)
  if normalized == "" or normalized == "." then
    return
  end

  set[normalized] = true

  local current = normalized
  while true do
    local parent = fs.getDir(current)
    if parent == nil or parent == "" or parent == "." or parent == current then
      break
    end
    set[normalizePath(parent)] = true
    current = parent
  end
end

local function wipePathRecursive(path, preserved, stats)
  local normalized = normalizePath(path)
  if normalized == "" or normalized == "." or preserved[normalized] then
    return
  end

  if not fs.exists(path) then
    return
  end

  if fs.isReadOnly(path) then
    return
  end

  if fs.isDir(path) then
    for _, name in ipairs(fs.list(path)) do
      wipePathRecursive(fs.combine(path, name), preserved, stats)
    end

    if fs.exists(path) and #fs.list(path) == 0 and not preserved[normalized] then
      fs.delete(path)
      stats.removed_dirs = stats.removed_dirs + 1
    end
    return
  end

  fs.delete(path)
  stats.removed_files = stats.removed_files + 1
end

local function wipeComputerKeepInstaller()
  local runningProgram = normalizePath(shell.getRunningProgram() or "installer.lua")
  if runningProgram == "" then
    runningProgram = "installer.lua"
  end

  local preserved = {}
  addPreservedPath(preserved, runningProgram)
  addPreservedPath(preserved, "installer.lua")
  addPreservedPath(preserved, UNLOCK_FILE)

  local stats = {
    removed_files = 0,
    removed_dirs = 0,
  }

  for _, name in ipairs(fs.list(".")) do
    wipePathRecursive(name, preserved, stats)
  end

  return stats, runningProgram
end

local function confirmFullWipe()
  cprint(colors.red, "WARNING: this will delete everything on this computer except the installer script and protected system files.")
  cprint(colors.red, "Programs, configs, logs, managed files, and local data will be removed.")
  print("")
  cwrite(colors.white, "Type WIPE to continue: ")
  local input = read()
  return type(input) == "string" and input:upper() == "WIPE"
end

local function runFullWipe(interactive)
  header("Wipe Computer")

  if interactive ~= false and not confirmFullWipe() then
    cprint(colors.yellow, "Wipe cancelled.")
    return false
  end

  local unlockOk, unlockResult = beginWriteWindow("installer-wipe")
  if not unlockOk then
    cprint(colors.red, "Could not open update window: " .. tostring(unlockResult))
    logError("Wipe unlock failed: " .. tostring(unlockResult))
    return false
  end

  local createdUnlock = unlockResult == true
  local ok, statsOrErr, installerPath = pcall(wipeComputerKeepInstaller)
  endWriteWindow(createdUnlock)

  if not ok then
    cprint(colors.red, "Wipe failed: " .. tostring(statsOrErr))
    logError("Wipe failed: " .. tostring(statsOrErr))
    return false
  end

  cprint(colors.lime, "Computer wiped.")
  cprint(colors.white, "Kept: " .. tostring(installerPath))
  cprint(colors.gray, "Read-only system paths like rom are preserved.")
  cprint(colors.gray, "Removed files: " .. tostring(statsOrErr.removed_files))
  cprint(colors.gray, "Removed directories: " .. tostring(statsOrErr.removed_dirs))
  print("")
  cprint(colors.white, "The installer remains so you can reinstall anything later.")
  return true
end

local function installFromSpec(spec, forceConfig, installedBefore)
  local unlockOk, unlockResult = beginWriteWindow("install")
  if not unlockOk then
    cprint(colors.red, "Could not open update window: " .. tostring(unlockResult))
    logError("Install unlock failed: " .. tostring(unlockResult))
    return false
  end
  local createdUnlock = unlockResult == true

  local program = spec.program or {}
  local build = spec.build or {}
  header("Installing " .. tostring(program.name or program.key or "program")
    .. " v" .. tostring(program.version or "?"))

  local shouldClaimPhoneHost = program.key == "phone_os" and not fs.exists(PHONE_HOST_MARKER_FILE)
  local managedPaths = {}
  local failed = {}
  local total = #(spec.install and spec.install.files or {})
  local success = 0
  local previouslyManaged = readManagedFiles()
  cleanupStaleRuntimeArtifacts()

  for _, entry in ipairs(spec.install.files or {}) do
    managedPaths[#managedPaths + 1] = entry.install_path
  end

  removeStaleFiles(previouslyManaged, managedPaths)
  pruneLegacyPayload(managedPaths)

  if forceConfig then
    local resetPaths = {}
    for _, path in ipairs(previouslyManaged) do
      resetPaths[#resetPaths + 1] = path
    end
    for _, path in ipairs(managedPaths) do
      resetPaths[#resetPaths + 1] = path
    end
    wipeManagedFiles(resetPaths)
  end

  print("")
  for index, entry in ipairs(spec.install.files or {}) do
    local _, row = term.getCursorPos()
    term.setCursorPos(1, row)
    term.clearLine()

    local label = entry.install_path or "?"
    if entry.preserve_existing then
      label = label .. " (config)"
    end
    cwrite(colors.white, "  " .. progressBar(index, total) .. "  " .. label .. " ")

    if entry.preserve_existing and not forceConfig and fs.exists(entry.install_path) then
      success = success + 1
      cprint(colors.gray, "")
    else
      local ok, err = downloadAndSaveVerified(
        buildCommitUrl(build.commit, entry.repo_path),
        entry.install_path,
        entry.sha256
      )
      if ok then
        success = success + 1
      else
        failed[#failed + 1] = entry.install_path
        logError(tostring(err))
      end
    end
    os.sleep(0)
  end

  print("")

  local installedOk = false
  if #failed == 0 then
    saveManagedFiles(managedPaths)
    saveInstalled(buildInstalledRecord(spec, installedBefore))
    installedOk = true
  end

  local phoneHostResult = nil
  local phoneHostErr = nil
  if installedOk then
    local claimOk, claimInfo = claimPhoneHostIfNeeded(shouldClaimPhoneHost)
    if claimOk then
      phoneHostResult = claimInfo
    else
      phoneHostErr = claimInfo
      logError("Phone host claim failed: " .. tostring(claimInfo))
    end
  end

  if installedOk then
    cprint(colors.lime, "  Installed " .. success .. "/" .. total .. " files. All good!")
  else
    cprint(colors.yellow, "  Installed " .. success .. "/" .. total .. " files.")
    cprint(colors.red, "  Failed: " .. table.concat(failed, ", "))
    cprint(colors.gray, "  See " .. LOG_FILE .. " for details.")
  end

  if phoneHostResult then
    local hostName = phoneHostResult.hostName or "Unknown"
    local claimVerb = phoneHostResult.changed and "assigned" or "confirmed"
    cprint(colors.lime, "  Phone host " .. claimVerb .. ": " .. tostring(hostName))
  elseif phoneHostErr then
    cprint(colors.yellow, "  Phone host was not assigned.")
    cprint(colors.yellow, "  " .. tostring(phoneHostErr))
  end

  print("")
  if installedOk then
    cprint(colors.white, "Run 'startup' to launch " .. tostring(program.name or program.key) .. ".")
  end

  endWriteWindow(createdUnlock)
  return installedOk
end

---------------------------------------------------------------------------
-- Version comparison
---------------------------------------------------------------------------
local function isNewer(remoteVer, localVer)
  if not remoteVer or not localVer then
    return remoteVer ~= localVer
  end
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
    if r > l then
      return true
    end
    if r < l then
      return false
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Self-update
---------------------------------------------------------------------------
local function selfUpdate(index, silent, commandArgs)
  local installer = index and index.installer or nil
  if type(installer) ~= "table" then
    if not silent then
      cprint(colors.red, "No installer metadata in deploy index.")
    end
    return "error", "No installer metadata in deploy index"
  end

  local needsUpdate = isNewer(installer.version, INSTALLER_VERSION)
  if not needsUpdate then
    local myPath = shell.getRunningProgram()
    local currentData = readFile(myPath, true)
    local currentHash = currentData and computeSha256(currentData) or nil
    if currentHash and installer.sha256 then
      needsUpdate = string.lower(currentHash) ~= string.lower(installer.sha256)
    end
  end

  if not needsUpdate then
    if not silent then
      cprint(colors.lime, "Installer is up to date (v" .. INSTALLER_VERSION .. ")")
    end
    return "current"
  end

  if not silent then
    cwrite(colors.yellow, "Updating installer v"
      .. INSTALLER_VERSION .. " -> v" .. tostring(installer.version or "?") .. "... ")
  end

  local unlockOk, unlockResult = beginWriteWindow("installer-self-update")
  if not unlockOk then
    if not silent then
      cprint(colors.red, "Failed!")
    end
    logError("Self-update unlock failed: " .. tostring(unlockResult))
    return "error", tostring(unlockResult)
  end
  local createdUnlock = unlockResult == true

  local commit = installer.commit
  if not commit or commit == "" then
    commit = fetchLatestMainCommit()
  end
  if not commit then
    if not silent then
      cprint(colors.red, "Failed!")
    end
    endWriteWindow(createdUnlock)
    logError("Self-update could not resolve source commit")
    return "error", "Could not resolve installer source commit"
  end

  local myPath = shell.getRunningProgram()
  local data, err = download(buildCommitUrl(commit, installer.path))
  if data and verifyHash(data, installer.sha256) then
    local ok, saveErr = saveFile(myPath, data)
    if ok then
      if not silent then
        cprint(colors.lime, "Done! Restarting...")
      end
      endWriteWindow(createdUnlock)
      local args = commandArgs or tArgs
      shell.run(myPath, UPDATED_ARG, tostring(installer.version or "?"), tostring(INSTALLER_VERSION), unpackArgs(args))
      return "updated"
    end
    err = saveErr
  elseif data then
    err = "Installer hash mismatch"
  end

  if not silent then
    cprint(colors.red, "Failed!")
  end
  endWriteWindow(createdUnlock)
  logError("Self-update failed: " .. tostring(err))
  return "error", tostring(err)
end

---------------------------------------------------------------------------
-- Program selection menu
---------------------------------------------------------------------------
local function getProgramCategory(prog)
  if type(prog) ~= "table" then
    return "Other"
  end

  if type(prog.category) == "string" and prog.category ~= "" then
    return prog.category
  end

  return "Other"
end

local function buildProgramGroups(index)
  local grouped = {}

  for key, prog in pairs(index.programs or {}) do
    local category = getProgramCategory(prog)
    if not grouped[category] then
      grouped[category] = {}
    end

    grouped[category][#grouped[category] + 1] = {
      key = key,
      name = prog.name,
      ver = prog.version,
      desc = prog.description or "",
    }
  end

  for _, entries in pairs(grouped) do
    table.sort(entries, function(a, b)
      return a.name < b.name
    end)
  end

  local folders = {}
  for category, entries in pairs(grouped) do
    folders[#folders + 1] = {
      key = category,
      name = category,
      count = #entries,
      entries = entries,
    }
  end

  table.sort(folders, function(a, b)
    local order = {
      Games = 1,
      Apps = 2,
      Utilities = 3,
      Other = 4,
    }
    local aOrder = order[a.name] or 99
    local bOrder = order[b.name] or 99
    if aOrder ~= bOrder then
      return aOrder < bOrder
    end
    return a.name < b.name
  end)

  return folders
end

local function selectFromList(title, items, renderEntry)
  local perPage = H - 7
  if perPage < 3 then
    perPage = 3
  end

  local totalPages = math.max(1, math.ceil(#items / perPage))
  local page = 1

  while true do
    header(title)

    local startIdx = (page - 1) * perPage + 1
    local endIdx = math.min(page * perPage, #items)

    for i = startIdx, endIdx do
      renderEntry(i, items[i])
    end

    print("")

    if totalPages > 1 then
      local nav = "Page " .. page .. "/" .. totalPages
      if page < totalPages then
        nav = nav .. "  [n]ext"
      end
      if page > 1 then
        nav = nav .. "  [p]rev"
      end
      cprint(colors.lightGray, "  " .. nav)
    end
    cprint(colors.gray, "  0. Back")
    cwrite(colors.white, "Select: ")

    local input = read()
    if not input then
      return nil
    end
    input = input:lower():gsub("^%s+", ""):gsub("%s+$", "")

    if input == "n" and page < totalPages then
      page = page + 1
    elseif input == "p" and page > 1 then
      page = page - 1
    else
      local choice = tonumber(input)
      if not choice or choice == 0 then
        return nil
      end
      if choice >= 1 and choice <= #items then
        return items[choice]
      end
    end
  end
end

local function selectProgramFromFolder(folder)
  return selectFromList(folder.name, folder.entries, function(i, p)
    local prefix = string.format("  %d. ", i)
    local nameVer = p.name .. " v" .. tostring(p.ver or "?")
    local remaining = W - #prefix - #nameVer - 2
    local suffix = ""
    if remaining > 5 and p.desc ~= "" then
      if #p.desc > remaining then
        suffix = " " .. p.desc:sub(1, remaining - 2) .. ".."
      else
        suffix = " " .. p.desc
      end
    end
    cwrite(colors.yellow, prefix)
    cwrite(colors.white, nameVer)
    cprint(colors.gray, suffix)
  end)
end

local function selectProgram(index)
  while true do
    local folders = buildProgramGroups(index)
    local folder = selectFromList("Select Folder", folders, function(i, entry)
      cwrite(colors.yellow, string.format("  %d. ", i))
      cwrite(colors.white, entry.name)
      cprint(colors.gray, " (" .. tostring(entry.count) .. ")")
    end)

    if not folder then
      return nil
    end

    local program = selectProgramFromFolder(folder)
    if program then
      return program.key
    end
  end
end

local function installByKey(index, programKey, forceConfig)
  local programEntry = index.programs and index.programs[programKey] or nil
  if not programEntry then
    cprint(colors.red, "Unknown program: " .. tostring(programKey))
    return false
  end

  local spec = index._inline_specs and index._inline_specs[programKey] or nil
  if not spec then
    local specErr
    spec, specErr = fetchProgramSpec(programEntry.spec_path)
    if not spec then
      cprint(colors.red, "Could not fetch package spec: " .. tostring(specErr))
      logError("Spec fetch failed for " .. tostring(programKey) .. ": " .. tostring(specErr))
      return false
    end
    spec._spec_path = programEntry.spec_path
  else
    spec._spec_path = programEntry.spec_path or ("repo-tree:" .. tostring(programKey))
  end

  return installFromSpec(spec, forceConfig, loadInstalled())
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------
local function main()
  local commandArgs, updatedTo, updatedFrom = parseInstallerArgs(tArgs)
  local index, indexErr = fetchLatestIndex()
  if not index then
    cprint(colors.red, "Installer self-check failed: " .. tostring(indexErr))
    cprint(colors.red, "Refusing to continue because installer freshness could not be verified.")
    print("")
    cprint(colors.gray, "Check that HTTP is enabled in the server config")
    cprint(colors.gray, "and that github.com is allowed.")
    logError("Installer self-check failed: " .. tostring(indexErr))
    return
  end

  local selfUpdateStatus, selfUpdateErr = selfUpdate(index, true, commandArgs)
  if selfUpdateStatus == "updated" then
    return
  end
  if selfUpdateStatus == "error" then
    cprint(colors.red, "Installer self-update failed: " .. tostring(selfUpdateErr or "Unknown error"))
    cprint(colors.red, "Refusing to continue until the installer is verified current.")
    logError("Installer self-update failed: " .. tostring(selfUpdateErr))
    return
  end

  if updatedTo then
    cprint(colors.lime, "Installer updated to v" .. tostring(updatedTo)
      .. (updatedFrom and updatedFrom ~= "" and (" from v" .. tostring(updatedFrom)) or "") .. ".")
    print("")
  end

  if commandArgs[1] == "self-update" then
    cprint(colors.lime, "Installer is up to date (v" .. INSTALLER_VERSION .. ")")
    return
  end

  if commandArgs[1] == "update" then
    local installed = loadInstalled()
    if not installed then
      cprint(colors.red, "No program installed. Run 'installer' to install.")
      return
    end
    local key = installed.program or installed.game
    installByKey(index, key, false)
    return
  end

  if commandArgs[1] == "wipe" then
    runFullWipe(true)
    return
  end

  if commandArgs[1] and commandArgs[1] ~= "" then
    installByKey(index, string.lower(commandArgs[1]), false)
    return
  end

  header("Program Installer v" .. INSTALLER_VERSION)
  cprint(colors.lime, "Catalog loaded from " .. tostring(index._catalog_source or "deploy index") .. ". " .. INSTALLER_VERSION)

  local installed = loadInstalled()
  if not installed and fs.exists(".casino_installed") then
    local raw = readFile(".casino_installed", false)
    if raw then
      local parseOk, info = pcall(function()
        return textutils.unserialise(raw)
      end)
      if parseOk and type(info) == "table" then
        installed = info
      end
    end
  end

  if installed then
    local key = installed.program or installed.game
    local prog = index.programs and index.programs[key] or nil
    local progName = prog and prog.name or key
    local instVer = installed.version or "?"
    print("")

    if prog and ((installed.source_commit or "") ~= (prog.commit or "")
        or (installed.package_hash or installed.content_hash or "") ~= (prog.package_hash or "")) then
      cprint(colors.yellow, progName .. " v" .. instVer .. " installed")
      cprint(colors.lime, "  Update available: v" .. tostring(prog.version or "?"))
    elseif prog then
      cprint(colors.lime, progName .. " v" .. instVer .. " - up to date")
    else
      cprint(colors.gray, "Installed: " .. tostring(key) .. " v" .. tostring(instVer))
    end

    print("")
    print("  1. Update " .. progName)
    print("  2. Reinstall " .. progName .. " (keep config)")
    print("  3. Reinstall " .. progName .. " (reset config)")
    print("  4. Install different program")
    print("  5. Wipe computer (keep installer only)")
    print("  6. Exit")
    print("")
    cwrite(colors.white, "Select: ")
    local choice = tonumber(read())

    if choice == 1 or choice == 2 then
      installByKey(index, key, false)
      return
    elseif choice == 3 then
      installByKey(index, key, true)
      return
    elseif choice == 4 then
      -- fall through
    elseif choice == 5 then
      runFullWipe(true)
      return
    else
      return
    end
  end

  print("")
  print("  1. Install a program")
  print("  2. Wipe computer (keep installer only)")
  print("  3. Exit")
  print("")
  cwrite(colors.white, "Select: ")
  local choice = tonumber(read())

  if choice == 2 then
    runFullWipe(true)
    return
  end

  if choice ~= 1 then
    return
  end

  local programKey = selectProgram(index)
  if programKey then
    installByKey(index, programKey, true)
  end
end

local ok, err = pcall(main)
if not ok then
  logError("CRASH: " .. tostring(err))
  term.setTextColor(colors.red)
  print("\nInstaller crashed: " .. tostring(err))
  print("See " .. LOG_FILE)
  term.setTextColor(colors.white)
end
