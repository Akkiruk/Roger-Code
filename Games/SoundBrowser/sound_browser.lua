local sound = require("lib.sound")
local catalog = require("lib.sound_catalog")

local PROGRAM_NAME = "Sound Browser"
local VERSION = "1.0.0"
local LOG_FILE = "sound_browser.log"

local ROOT = fs.getDir(shell.getRunningProgram())
local FAVORITES_FILE = nil
local state = nil

local appendLog = nil
local trimText = nil
local formatNumber = nil
local countFavorites = nil
local sortedFavorites = nil
local clampSelection = nil
local visibleRows = nil
local ensureScroll = nil
local setStatus = nil
local recalcMatches = nil
local selectedSound = nil
local toggleFavorite = nil
local saveFavorites = nil
local loadFavorites = nil
local refreshSpeaker = nil
local playSelected = nil
local promptFilter = nil
local clearFilter = nil
local adjustVolume = nil
local adjustPitch = nil
local moveSelection = nil
local pageSelection = nil
local drawScreen = nil
local runBrowser = nil

if ROOT == "" and shell.dir then
  ROOT = shell.dir()
end

FAVORITES_FILE = ROOT ~= "" and fs.combine(ROOT, "sound_browser_favorites.lua") or "sound_browser_favorites.lua"

state = {
  filter = "",
  favorites = {},
  matches = {},
  selected = 0,
  scroll = 0,
  volume = 1.0,
  pitch = 1.0,
  status = "Loading sound catalog...",
  speakerSide = nil,
}

appendLog = function(message)
  local handle = fs.open(LOG_FILE, "a")
  if not handle then
    return
  end

  handle.writeLine("[" .. tostring(os.epoch("local")) .. "] " .. tostring(message))
  handle.close()
end

trimText = function(value, maxLen)
  local text = tostring(value or "")
  if maxLen <= 0 then
    return ""
  end
  if #text <= maxLen then
    return text
  end
  if maxLen <= 2 then
    return text:sub(1, maxLen)
  end
  return text:sub(1, maxLen - 2) .. ".."
end

formatNumber = function(value)
  return string.format("%.1f", value or 0)
end

countFavorites = function()
  local total = 0

  for _, enabled in pairs(state.favorites) do
    if enabled then
      total = total + 1
    end
  end

  return total
end

sortedFavorites = function()
  local items = {}

  for soundId, enabled in pairs(state.favorites) do
    if enabled then
      items[#items + 1] = soundId
    end
  end

  table.sort(items)
  return items
end

visibleRows = function()
  local _, height = term.getSize()
  return math.max(5, height - 9)
end

clampSelection = function()
  if #state.matches == 0 then
    state.selected = 0
    state.scroll = 0
    return
  end

  if state.selected < 1 then
    state.selected = 1
  elseif state.selected > #state.matches then
    state.selected = #state.matches
  end
end

ensureScroll = function()
  local rows = visibleRows()

  clampSelection()

  if state.selected <= 0 then
    state.scroll = 0
    return
  end

  if state.selected <= state.scroll then
    state.scroll = state.selected - 1
  end

  if state.selected > state.scroll + rows then
    state.scroll = state.selected - rows
  end

  if state.scroll < 0 then
    state.scroll = 0
  end
end

setStatus = function(message)
  state.status = tostring(message or "")
  appendLog(state.status)
end

recalcMatches = function()
  local lowered = string.lower(state.filter or "")
  local matches = {}

  for _, soundId in ipairs(catalog.SOUNDS or {}) do
    if lowered == "" or string.find(string.lower(soundId), lowered, 1, true) then
      matches[#matches + 1] = soundId
    end
  end

  state.matches = matches
  clampSelection()

  if state.selected == 0 and #state.matches > 0 then
    state.selected = 1
  end

  ensureScroll()
end

selectedSound = function()
  if state.selected <= 0 then
    return nil
  end

  return state.matches[state.selected]
end

toggleFavorite = function()
  local soundId = selectedSound()
  if not soundId then
    setStatus("No sound selected.")
    return
  end

  if state.favorites[soundId] then
    state.favorites[soundId] = nil
    setStatus("Removed favorite: " .. soundId)
    return
  end

  state.favorites[soundId] = true
  setStatus("Saved favorite in memory: " .. soundId)
end

saveFavorites = function()
  local data = {
    version = 1,
    saved_at = os.epoch("local"),
    volume = state.volume,
    pitch = state.pitch,
    favorites = sortedFavorites(),
  }
  local serialized = "return " .. textutils.serialize(data)
  local handle = fs.open(FAVORITES_FILE, "w")

  if not handle then
    setStatus("Could not open favorites file for writing.")
    return
  end

  handle.write(serialized)
  handle.close()
  setStatus("Saved " .. tostring(#data.favorites) .. " favorites to " .. FAVORITES_FILE)
end

loadFavorites = function()
  local ok = nil
  local loaded = nil

  if not fs.exists(FAVORITES_FILE) then
    return
  end

  ok, loaded = pcall(function()
    return dofile(FAVORITES_FILE)
  end)

  if not ok or type(loaded) ~= "table" then
    setStatus("Could not load existing favorites file.")
    return
  end

  if type(loaded.volume) == "number" then
    state.volume = math.max(0, math.min(3, loaded.volume))
  end

  if type(loaded.pitch) == "number" then
    state.pitch = math.max(0.5, math.min(2, loaded.pitch))
  end

  if type(loaded.favorites) == "table" then
    for _, soundId in ipairs(loaded.favorites) do
      if type(soundId) == "string" and soundId ~= "" then
        state.favorites[soundId] = true
      end
    end
  end
end

refreshSpeaker = function(side)
  state.speakerSide = side

  if sound.init(side) then
    return true
  end

  return false
end

playSelected = function()
  local soundId = selectedSound()
  local attempts = 0
  local ok = false
  local err = nil

  if not soundId then
    setStatus("No sound selected.")
    return
  end

  if not sound.isAvailable() then
    setStatus("No speaker found. Pass a side or attach a speaker.")
    return
  end

  while attempts < 5 do
    attempts = attempts + 1
    ok, err = sound.play(soundId, state.volume, state.pitch)
    if ok then
      setStatus("Played " .. soundId .. " at vol " .. formatNumber(state.volume) .. ", pitch " .. formatNumber(state.pitch))
      return
    end
    os.sleep(0.05)
  end

  setStatus("Could not play " .. soundId .. ": " .. tostring(err or "unknown error"))
end

promptFilter = function()
  local width, height = term.getSize()

  term.setCursorBlink(false)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.setCursorPos(1, height)
  term.clearLine()
  write("Filter: ")
  term.setCursorBlink(true)
  state.filter = read() or ""
  term.setCursorBlink(false)
  recalcMatches()

  if state.filter == "" then
    setStatus("Filter cleared.")
  else
    setStatus("Filter set to \"" .. trimText(state.filter, math.max(1, width - 20)) .. "\"")
  end
end

clearFilter = function()
  state.filter = ""
  recalcMatches()
  setStatus("Filter cleared.")
end

adjustVolume = function(delta)
  state.volume = math.max(0, math.min(3, math.floor((state.volume + delta) * 10 + 0.5) / 10))
  setStatus("Volume set to " .. formatNumber(state.volume))
end

adjustPitch = function(delta)
  state.pitch = math.max(0.5, math.min(2, math.floor((state.pitch + delta) * 10 + 0.5) / 10))
  setStatus("Pitch set to " .. formatNumber(state.pitch))
end

moveSelection = function(delta)
  if #state.matches == 0 then
    return
  end

  state.selected = state.selected + delta
  clampSelection()
  ensureScroll()
end

pageSelection = function(delta)
  moveSelection(delta * visibleRows())
end

drawScreen = function()
  local width, height = term.getSize()
  local rows = visibleRows()
  local footerY = height - 2
  local selectedId = selectedSound()
  local speakerLabel = sound.isAvailable() and "ready" or "missing"

  term.setCursorBlink(false)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  term.write(trimText(PROGRAM_NAME .. " v" .. VERSION, width))

  term.setCursorPos(1, 2)
  term.setTextColor(colors.lightGray)
  term.write(trimText(
    "Speaker: " .. speakerLabel ..
    "  Showing: " .. tostring(#state.matches) .. "/" .. tostring(catalog.SOUND_COUNT or #(catalog.SOUNDS or {})) ..
    "  Favorites: " .. tostring(countFavorites()),
    width
  ))

  term.setCursorPos(1, 3)
  term.setTextColor(colors.yellow)
  term.write(trimText("Filter: " .. (state.filter ~= "" and state.filter or "(none)"), width))

  term.setCursorPos(1, 4)
  term.setTextColor(colors.cyan)
  term.write(trimText("Volume [-/=]: " .. formatNumber(state.volume) .. "  Pitch [[/]]: " .. formatNumber(state.pitch), width))

  term.setCursorPos(1, 5)
  term.setTextColor(colors.gray)
  term.write(string.rep("-", width))

  if #state.matches == 0 then
    term.setCursorPos(1, 7)
    term.setTextColor(colors.red)
    term.write(trimText("No sounds match the current filter.", width))
  else
    local row = 1
    while row <= rows do
      local index = state.scroll + row
      local soundId = state.matches[index]

      if not soundId then
        break
      end

      term.setCursorPos(1, 5 + row)
      if index == state.selected then
        term.setBackgroundColor(colors.lightBlue)
        term.setTextColor(colors.black)
      else
        term.setBackgroundColor(colors.black)
        term.setTextColor(state.favorites[soundId] and colors.lime or colors.white)
      end

      term.clearLine()
      term.write(trimText((index == state.selected and ">" or " ") .. (state.favorites[soundId] and "*" or " ") .. " " .. soundId, width))
      row = row + 1
    end
  end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.lightGray)
  term.setCursorPos(1, footerY)
  term.clearLine()
  term.write(trimText("Arrows move  Enter tests  / search  F favorite  S save  R reset  Q quit", width))

  term.setCursorPos(1, height)
  term.setTextColor(selectedId and colors.white or colors.orange)
  term.clearLine()
  term.write(trimText(state.status or "", width))
end

runBrowser = function(...)
  local args = { ... }
  local event = nil
  local p1 = nil
  local p2 = nil
  local p3 = nil
  local running = true

  loadFavorites()
  refreshSpeaker(args[1])
  recalcMatches()
  setStatus("Loaded " .. tostring(catalog.SOUND_COUNT or #(catalog.SOUNDS or {})) .. " sound IDs. Favorites file: " .. FAVORITES_FILE)

  while running do
    drawScreen()
    event, p1, p2, p3 = os.pullEvent()

    if event == "char" then
      if p1 == "/" then
        promptFilter()
      elseif p1 == "f" or p1 == "F" then
        toggleFavorite()
      elseif p1 == "s" or p1 == "S" then
        saveFavorites()
      elseif p1 == "r" or p1 == "R" then
        clearFilter()
      elseif p1 == "q" or p1 == "Q" then
        running = false
      elseif p1 == "-" then
        adjustVolume(-0.1)
      elseif p1 == "=" or p1 == "+" then
        adjustVolume(0.1)
      elseif p1 == "[" or p1 == "{" then
        adjustPitch(-0.1)
      elseif p1 == "]" or p1 == "}" then
        adjustPitch(0.1)
      end
    elseif event == "key" then
      if p1 == keys.up then
        moveSelection(-1)
      elseif p1 == keys.down then
        moveSelection(1)
      elseif p1 == keys.pageUp then
        pageSelection(-1)
      elseif p1 == keys.pageDown then
        pageSelection(1)
      elseif p1 == keys.home then
        state.selected = 1
        ensureScroll()
      elseif p1 == keys["end"] then
        state.selected = #state.matches
        ensureScroll()
      elseif p1 == keys.enter or p1 == keys.numPadEnter or p1 == keys.space then
        playSelected()
      end
    elseif event == "peripheral" or event == "peripheral_detach" then
      if refreshSpeaker(state.speakerSide) then
        setStatus("Speaker detected.")
      else
        setStatus("Speaker not available.")
      end
    elseif event == "term_resize" then
      ensureScroll()
    elseif event == "terminate" then
      running = false
    end
  end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("Exited " .. PROGRAM_NAME .. ".")
  print("Favorites file: " .. FAVORITES_FILE)
end

local ok, err = pcall(function(...)
  runBrowser(...)
end, ...)

if not ok then
  appendLog("Fatal error: " .. tostring(err))
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  term.clear()
  term.setCursorPos(1, 1)
  print(PROGRAM_NAME .. " crashed.")
  print("")
  term.setTextColor(colors.white)
  print(tostring(err))
  print("")
  print("See " .. LOG_FILE .. " for details.")
end
