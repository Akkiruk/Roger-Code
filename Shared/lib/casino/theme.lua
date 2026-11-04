-- theme.lua
-- One look for the whole casino. The 16 monitor colours are named here; a game only changes its felt and accent.
-- Values are blit characters, ready for the canvas.

local M = {}

local SLOTS = {
  ink = "f",      -- near black: text on light, deep backgrounds
  panel = "7",    -- bars and panels
  panel2 = "8",   -- raised panels, disabled buttons
  line = "c",     -- outlines
  mute = "9",     -- quiet text
  text = "0",     -- main text
  card = "6",     -- card faces
  red = "e",      -- red suits, losses
  gold = "4",     -- gold accents, the bet
  win = "5",      -- wins
  orange = "1",   -- warnings
  blue = "b",     -- secondary actions
  felt = "d",     -- table surface
  feltDark = "a", -- table edge and shadows
  feltLight = "3", -- table markings
  accent = "2",   -- each game's colour
}

local RGB = {
  ink = 0x0E1014, panel = 0x1B1F2A, panel2 = 0x2E3546, line = 0x4B5468, mute = 0x8D97AB, text = 0xEEF0F5,
  card = 0xFBF8EF, red = 0xD8343F, gold = 0xF2C14E, win = 0x35D07F, orange = 0xF08A3C, blue = 0x4C8DF0,
}

M.C = SLOTS

local FELTS = {
  green = { felt = 0x0F5A3C, feltDark = 0x0A3F2A, feltLight = 0x1C7A54, accent = 0xF2C14E },
  blue = { felt = 0x123C6B, feltDark = 0x0C2A4C, feltLight = 0x24598F, accent = 0x6FB7FF },
  burgundy = { felt = 0x5B1426, feltDark = 0x3F0D1A, feltLight = 0x7D2239, accent = 0xFF7A8A },
  purple = { felt = 0x3A1C66, feltDark = 0x281248, feltLight = 0x54308C, accent = 0xC79BFF },
  teal = { felt = 0x0E5560, feltDark = 0x093B43, feltLight = 0x1B7884, accent = 0x5FE3D2 },
  ember = { felt = 0x5A3210, feltDark = 0x3F230B, feltLight = 0x7D4A1C, accent = 0xFFAE5C },
  -- An island in the sea, for board games with land on them (Game Night's Catan): the felt is the sea, feltLight a forest, accent
  -- sand, and card turns brick red. A felt may set any slot, so a game that needs other colours names them here
  island = { felt = 0x2B6EA6, feltDark = 0x173F66, feltLight = 0x2F6B2F, accent = 0xE2CC8E, card = 0xA4472A },
}

--- Set a monitor's 16 colours for a felt. Colours belong to the monitor, so this comes before the first draw.
function M.apply(monitor, feltName)
  local felt = FELTS[feltName] or FELTS.green
  local function setSlot(name, rgb)
    monitor.setPaletteColour(2 ^ tonumber(SLOTS[name], 16), rgb)
  end
  for name, rgb in pairs(RGB) do setSlot(name, rgb) end
  for name, rgb in pairs(felt) do setSlot(name, rgb) end
end

return M
