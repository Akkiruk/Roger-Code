-- update_screen.lua
-- What a computer shows while it updates: the same animated screen on its own terminal and every monitor it can see.
-- Games are stopped by then, so this owns the screens. They get their own colours and text size back when they restart.

local M = {}

local SPIN = { "|", "/", "-", "\\" }
local FRAME = 0.15
local BAR_MAX = 40
local SWEEP = 6                 -- length of the moving block before there's a progress figure to show
local TARGET_WIDTH = 28         -- monitors use the largest text that still leaves this many columns

local INK, PANEL, TEXT, MUTED, GOOD, BAD = colors.black, colors.gray, colors.white, colors.lightGray, colors.lime, colors.red

local PALETTE = {
  [INK] = 0x14161C, [PANEL] = 0x2E3546, [TEXT] = 0xF2F4F8, [MUTED] = 0x8D97AB, [GOOD] = 0x35D07F, [BAD] = 0xE5484D,
}

local function prepare(target)
  for colour, rgb in pairs(PALETTE) do
    if target.setPaletteColour then pcall(target.setPaletteColour, colour, rgb) end
  end
  target.setBackgroundColor(INK)
  target.setCursorBlink(false)
  target.clear()
end

--- Every screen this computer has. A monitor gets large text, so it reads from across the room.
local function allScreens()
  local screens = { term.current() }
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "monitor") then
      local monitor = peripheral.wrap(name)
      for _, scale in ipairs({ 3, 2, 1.5, 1, 0.5 }) do
        monitor.setTextScale(scale)
        if monitor.getSize() >= TARGET_WIDTH then break end
      end
      screens[#screens + 1] = monitor
    end
  end
  for _, screen in ipairs(screens) do pcall(prepare, screen) end
  return screens
end

local function centre(target, y, text, colour)
  local w = target.getSize()
  target.setCursorPos(math.max(1, math.floor((w - #text) / 2) + 1), y)
  target.setBackgroundColor(INK)
  target.setTextColor(colour)
  target.write(text)
end

--- The bar: a share of it filled, or a block sweeping along while the share isn't known yet.
local function drawBar(target, y, share, tick)
  local w = target.getSize()
  local width = math.min(w - 4, BAR_MAX)
  local x = math.floor((w - width) / 2) + 1
  local from, to = 1, math.floor(width * (share or 0) + 0.5)
  if not share then
    local travel = width - SWEEP
    local at = tick % math.max(1, 2 * travel)
    if at > travel then at = 2 * travel - at end
    from, to = at + 1, at + SWEEP
  end
  target.setCursorPos(x, y)
  target.setBackgroundColor(PANEL)
  target.write(string.rep(" ", width))
  if to >= from then
    target.setCursorPos(x + from - 1, y)
    target.setBackgroundColor(GOOD)
    target.write(string.rep(" ", to - from + 1))
  end
end

local function draw(target, state, tick)
  local _, h = target.getSize()
  local top = math.max(1, math.floor(h / 2) - 2)
  centre(target, top, SPIN[tick % #SPIN + 1] .. " UPDATING " .. SPIN[tick % #SPIN + 1], TEXT)
  centre(target, top + 1, state.name, MUTED)
  drawBar(target, top + 3, state.share, tick)
  centre(target, top + 5, "                            ", MUTED)
  centre(target, top + 5, state.text, MUTED)
end

local function finish(target, title, line, colour)
  target.setBackgroundColor(INK)
  target.clear()
  local _, h = target.getSize()
  local top = math.max(1, math.floor(h / 2) - 1)
  centre(target, top, title, colour)
  centre(target, top + 2, line, MUTED)
end

-- A sound of its own as an update starts and ends, so anyone near a cabinet knows what's going on. The picks live in
-- lib/sound_picks.lua where a program has it; these stand in where it doesn't.
local SOUNDS = {
  update_start = { "minecraft:block.conduit.activate", 1.0, 1 },
  update_done = { "minecraft:ui.toast.challenge_complete", 0.8, 1 },
  update_fail = { "minecraft:block.beacon.deactivate", 0.8, 1 },
}

local function sound(name)
  local ok, picks = pcall(require, "lib.sound_picks")
  local def = (ok and type(picks) == "table" and picks[name]) or SOUNDS[name]
  if not def then return end
  pcall(function()
    for _, speaker in ipairs({ peripheral.find("speaker") }) do speaker.playSound(def[1], def[2], def[3]) end
  end)
end

--- Run an update on screen. work(progress) does it, calling progress(done, total) as files arrive, and returns a status.
-- @return whatever work returned
function M.run(name, work)
  local screens = allScreens()
  sound("update_start")
  local state = { name = tostring(name or "Program"), text = "Back in a moment" }

  local function animate()
    local tick = 0
    while true do
      for _, screen in ipairs(screens) do pcall(draw, screen, state, tick) end
      tick = tick + 1
      sleep(FRAME)
    end
  end

  local result
  parallel.waitForAny(function()
    result = work(function(done, total)
      state.share = total > 0 and done / total or nil
      state.text = done .. " of " .. total .. " files"
    end)
  end, animate)

  local good = result == "updated"
  sound(good and "update_done" or "update_fail")
  for _, screen in ipairs(screens) do
    pcall(finish, screen, good and "UPDATED" or "UPDATE DIDN'T FINISH", good and "Restarting..." or "Trying again later", good and GOOD or BAD)
  end
  sleep(1.5)
  return result
end

return M
