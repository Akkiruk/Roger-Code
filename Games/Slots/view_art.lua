-- view_art.lua
-- Displays all slot machine NFP sprites on the terminal.
-- Uses paintutils (built-in CC API) to render pixel art.

local symbols = {
  { name = "SEVEN",   file = "seven.nfp"   },
  { name = "DIAMOND", file = "diamond.nfp" },
  { name = "BELL",    file = "bell.nfp"    },
  { name = "BAR",     file = "bar.nfp"     },
  { name = "CHERRY",  file = "cherry.nfp"  },
  { name = "LEMON",   file = "lemon.nfp"   },
  { name = "MELON",   file = "melon.nfp"   },
}

local W, H = term.getSize()

local function showSymbol(idx)
  local sym = symbols[idx]
  if not sym then return end

  term.setBackgroundColor(colors.black)
  term.clear()

  -- Title
  term.setCursorPos(1, 1)
  term.setTextColor(colors.yellow)
  term.write("=== " .. sym.name .. " (" .. idx .. "/" .. #symbols .. ") ===")

  -- Load and draw
  if fs.exists(sym.file) then
    local img = paintutils.loadImage(sym.file)
    if img then
      paintutils.drawImage(img, 3, 3)
    else
      term.setCursorPos(3, 3)
      term.setTextColor(colors.red)
      term.write("Failed to parse: " .. sym.file)
    end
  else
    term.setCursorPos(3, 3)
    term.setTextColor(colors.red)
    term.write("File not found: " .. sym.file)
  end

  -- Nav instructions
  term.setBackgroundColor(colors.black)
  term.setCursorPos(1, H - 1)
  term.setTextColor(colors.lightGray)
  term.write("[Left/Right] Navigate  [A] Show All  [Q] Quit")
end

local function showAll()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.yellow)
  term.write("=== ALL SLOT SYMBOLS ===")

  local col = 1
  local row = 3
  local maxArtH = 0

  for i, sym in ipairs(symbols) do
    -- Label above art
    term.setBackgroundColor(colors.black)
    term.setCursorPos(col, row)
    term.setTextColor(colors.white)
    term.write(sym.name)

    -- Draw art
    if fs.exists(sym.file) then
      local img = paintutils.loadImage(sym.file)
      if img then
        paintutils.drawImage(img, col, row + 1)
        local artH = #img
        if artH > maxArtH then maxArtH = artH end
      end
    end

    -- Move to next column (each symbol gets 15 cols)
    col = col + 15
    if col + 14 > W then
      -- Wrap to next row
      col = 1
      row = row + maxArtH + 3
      maxArtH = 0
    end
  end

  term.setBackgroundColor(colors.black)
  term.setCursorPos(1, H)
  term.setTextColor(colors.lightGray)
  term.write("[Any key] Back to single view  [Q] Quit")
end

-- Main
local current = 1
showSymbol(current)

while true do
  local ev, key = os.pullEvent("key")

  if key == keys.q then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("Done!")
    break
  elseif key == keys.right or key == keys.d then
    current = current + 1
    if current > #symbols then current = 1 end
    showSymbol(current)
  elseif key == keys.left or key == keys.a then
    current = current - 1
    if current < 1 then current = #symbols end
    showSymbol(current)
  elseif key == keys.space then
    showAll()
    os.pullEvent("key")
    showSymbol(current)
  end
end
