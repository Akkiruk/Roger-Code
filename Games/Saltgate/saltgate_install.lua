-- saltgate_install.lua
-- Installs SALTGATE: Low Tide on this computer straight from GitHub (Akkiruk/Roger-Code, main). It is the installer
-- players get from Pastebin; the game itself (about 400 KB) comes from GitHub, as Pastebin keeps pastes small.
--   pastebin run <code>          or     pastebin get <code> install, then: install
-- Run it again to update: your save (saltgate_save2.dat) and settings (saltgate_settings.lua) are kept.

local OWNER, REPO, BRANCH = "Akkiruk", "Roger-Code", "main"
local RAW = "https://raw.githubusercontent.com/" .. OWNER .. "/" .. REPO .. "/"
local GAME = "Games/Saltgate/"

-- { path in the repo, where it goes, binary, keep an existing copy }
local FILES = {
  { GAME .. "saltgate.pak", "saltgate.pak", true },
  { GAME .. "sgpak.lua", "sgpak.lua" },
  { GAME .. "saltgate.lua", "saltgate.lua" },
  { GAME .. "startup.lua", "saltgate_startup.lua" },
  { GAME .. "saltgate_settings.lua", "saltgate_settings.lua", false, true },
  { GAME .. "CREDITS.txt", "CREDITS.txt" },
  { GAME .. "pine3d/LICENSE.txt", "pine3d/LICENSE.txt" },
  -- sends a crash to the game's author as a bug report (turn it off with: set crashreport.enabled false)
  { "Shared/lib/crashreport.lua", "lib/crashreport.lua" },
}
local TRIES = 4
local STARTUP = "startup/saltgate.lua"

local w, h = term.getSize()

local function colour(c)
  if term.isColour() then term.setTextColour(c) end
end

local function say(text, c)
  colour(c or colours.white)
  print(text)
  colour(colours.white)
end

local function ask(question)
  while true do
    colour(colours.yellow)
    write(question .. " (y/n) ")
    colour(colours.white)
    local answer = (read() or ""):lower()
    if answer == "y" or answer == "yes" then return true end
    if answer == "n" or answer == "no" then return false end
  end
end

--- A progress bar on line y, and what it is doing on the line under it.
local function bar(y, done, total, label)
  local width = math.max(10, w - 2)
  local fill = math.floor(width * math.min(1, done / math.max(1, total)) + 0.5)
  term.setCursorPos(1, y)
  term.clearLine()
  term.setBackgroundColour(colours.orange)
  write(string.rep(" ", fill))
  term.setBackgroundColour(colours.grey)
  write(string.rep(" ", width - fill))
  term.setBackgroundColour(colours.black)
  term.setCursorPos(1, y + 1)
  term.clearLine()
  colour(colours.lightGrey)
  write(label:sub(1, w))
  colour(colours.white)
end

local function get(url, binary)
  local ok, response, err = pcall(http.get, url, nil, binary)
  if not ok then return nil, tostring(response) end
  if not response then return nil, tostring(err or "no answer") end
  local code = response.getResponseCode and response.getResponseCode() or 200
  local data = response.readAll()
  response.close()
  if code ~= 200 then return nil, "HTTP " .. tostring(code) end
  if not data or #data == 0 then return nil, "empty answer" end
  return data
end

--- get, tried TRIES times with a growing wait between.
local function fetch(url, binary, onRetry)
  local data, err
  for try = 1, TRIES do
    data, err = get(url, binary)
    if data then return data end
    if try < TRIES then
      if onRetry then onRetry(try, err) end
      sleep(try * 2)
    end
  end
  return nil, err
end

--- The commit main is at now, so every file comes from the same one (GitHub's raw files are cached for minutes, a
-- file of an older commit beside a newer one could otherwise be fetched). main itself if GitHub will not say.
local function commitOfMain()
  local ok, response = pcall(http.get, "https://api.github.com/repos/" .. OWNER .. "/" .. REPO .. "/commits/" .. BRANCH,
    { ["Accept"] = "application/vnd.github.sha", ["User-Agent"] = "saltgate-installer" })
  if ok and response then
    local sha = response.readAll()
    response.close()
    if sha and sha:match("^%x+$") and #sha == 40 then return sha end
  end
  return BRANCH
end

local function writeFile(path, data, binary)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f, err = fs.open(path, binary and "wb" or "w")
  if not f then return false, err end
  f.write(data)
  f.close()
  return true
end

--- What a file takes on the disk, as CC counts it.
local function cost(size) return math.max(500, size) end

local function main()
  term.clear()
  term.setCursorPos(1, 1)
  say("SALTGATE: Low Tide - installer", colours.orange)
  say("An open-city crime and driving game in 3D.", colours.lightGrey)
  print()
  if not term.isColour() then
    say("SALTGATE needs an advanced computer (gold) or an advanced pocket computer.", colours.red)
    return false
  end
  if not http then
    say("This computer cannot reach the internet: the http API is off.", colours.red)
    return false
  end
  if fs.exists(".installed_program") then
    say("This computer runs a Roger-Code program, which keeps itself up to date. This installer sets SALTGATE up on its own.",
      colours.yellow)
    if not ask("Install anyway?") then return false end
  end

  say("Finding the newest version...", colours.lightGrey)
  local commit = commitOfMain()
  say("Version: " .. (commit == BRANCH and BRANCH or commit:sub(1, 7)), colours.lightGrey)
  print()

  -- everything is fetched into memory first, so a failed download changes nothing on the disk
  local got = {}
  local fetched = 0
  print()
  print()
  local _, below = term.getCursorPos()
  local barY = below - 2
  local function step(i, label) bar(barY, i, #FILES, label) end
  for i, f in ipairs(FILES) do
    local repoPath, path, binary, keep = f[1], f[2], f[3], f[4]
    if keep and fs.exists(path) then
      step(i, "keeping your " .. path)
    else
      step(i - 1, "downloading " .. path)
      local data, err = fetch(RAW .. commit .. "/" .. repoPath, binary, function(try, why)
        step(i - 1, "retrying " .. path .. " (" .. tostring(why) .. ")")
      end)
      if not data then
        term.setCursorPos(1, barY + 2)
        say("Could not download " .. path .. ": " .. tostring(err), colours.red)
        say("Nothing was changed. Try again in a minute.", colours.red)
        return false
      end
      if path == "saltgate.pak" and not data:match("^SGPAK1 %d+\n") then
        term.setCursorPos(1, barY + 2)
        say("saltgate.pak came down damaged. Nothing was changed. Try again.", colours.red)
        return false
      end
      got[#got + 1] = { path = path, data = data, binary = binary }
      fetched = fetched + #data
      step(i, path .. " (" .. math.floor(#data / 1024 + 0.5) .. " KB)")
    end
  end
  term.setCursorPos(1, barY + 2)

  -- enough room? (what the old copies take is given back)
  local need = 0
  for _, f in ipairs(got) do
    need = need + cost(#f.data)
    if fs.exists(f.path) and not fs.isDir(f.path) then need = need - cost(fs.getSize(f.path)) end
  end
  need = need + 2000 -- new folders, and room for the first save
  local free = fs.getFreeSpace("/")
  if free < need then
    say(string.format("Not enough disk space: SALTGATE needs %d KB more, %d KB is free.", math.ceil(need / 1024),
      math.floor(free / 1024)), colours.red)
    say("Delete some files (or use a computer with a bigger disk) and run the installer again.", colours.red)
    return false
  end

  for _, f in ipairs(got) do
    local ok, err = writeFile(f.path, f.data, f.binary)
    if not ok then
      say("Could not write " .. f.path .. ": " .. tostring(err), colours.red)
      return false
    end
  end
  say(string.format("Installed: %d KB downloaded, %d KB free.", math.floor(fetched / 1024 + 0.5),
    math.floor(fs.getFreeSpace("/") / 1024)), colours.lime)
  print()

  if ask("Start SALTGATE when this computer turns on?") then
    local ok = writeFile(STARTUP, '-- SALTGATE on boot (saltgate_install.lua). Delete this file to stop it.\nshell.run("/saltgate_startup.lua")\n')
    if ok then say("It will. (Delete " .. STARTUP .. " to stop it.)", colours.lightGrey) end
  elseif fs.exists(STARTUP) then
    fs.delete(STARTUP)
  end
  print()
  say("Type saltgate to play.", colours.orange)
  if ask("Play now?") then
    shell.run("/saltgate_startup.lua")
  end
  return true
end

local ok, err = pcall(main)
colour(colours.white)
if not ok then
  if tostring(err):find("Terminated", 1, true) then print("Cancelled.") return end
  printError("The installer crashed: " .. tostring(err))
end
