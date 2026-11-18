-- combat/overlay.lua
-- Pixel effects drawn into the 3D frame's own buffer just before it is blitted to the screen (so a tracer, a puff or a
-- reticle is a true 2x3 sub-pixel mark, not a text character). It wraps frame:drawBuffer once; any plugin adds a
-- painter with overlay.add(name, fn(frame, rows, W, H)). Nothing runs when no painter is added, and painters only run
-- while the "play" screen is showing. Pure apart from the frame it is given.
--
--   overlay.install(frame, isPlaying)      wrap frame:drawBuffer (safe to call every frame: it wraps once)
--   overlay.add(name, fn) / overlay.remove(name)
--   overlay.project(frame, x, y, z) -> sx, sy (buffer pixels) or nil when behind the camera
--   overlay.line(plot, x0, y0, x1, y1, colour)       overlay.rect(plot, x, y, s, colour)

local M = {}

M.painters = {}
M.order = {}

local floor = math.floor

function M.add(name, fn)
  if not M.painters[name] then M.order[#M.order + 1] = name end
  M.painters[name] = fn
end

function M.remove(name)
  M.painters[name] = nil
  for i, n in ipairs(M.order) do
    if n == name then table.remove(M.order, i) break end
  end
end

function M.install(frame, isPlaying)
  if frame.overlayInstalled then
    frame.overlayPlaying = isPlaying
    return false
  end
  local original = frame.drawBuffer
  frame.overlayInstalled = true
  frame.overlayPlaying = isPlaying
  frame.drawBuffer = function(self, ...)
    if self.overlayPlaying and self.overlayPlaying() and #M.order > 0 then
      local rows = self.buffer.colorValues
      local H = #rows
      local W = rows[1] and #rows[1] or 0
      for _, name in ipairs(M.order) do
        local fn = M.painters[name]
        if fn then
          local ok = pcall(fn, self, rows, W, H)
          if not ok then M.painters[name] = nil end -- a broken painter is dropped, never the frame
        end
      end
    end
    return original(self, ...)
  end
  return true
end

function M.project(frame, x, y, z)
  local sx, sy, ahead = frame:map3dTo2d(x, y, z)
  if not ahead then return nil end
  return sx, sy
end

--- A plot function over rows (clipped to the buffer).
function M.plotter(rows, W, H)
  return function(x, y, c)
    x, y = floor(x + 0.5), floor(y + 0.5)
    if x >= 1 and x <= W and y >= 1 and y <= H then rows[y][x] = c end
  end
end

function M.rect(plot, x, y, s, c)
  for dy = 0, s - 1 do
    for dx = 0, s - 1 do plot(x + dx, y + dy, c) end
  end
end

function M.line(plot, x0, y0, x1, y1, c)
  local dx, dy = x1 - x0, y1 - y0
  local n = math.max(math.abs(dx), math.abs(dy))
  if n > 400 then return end
  if n < 1 then plot(x0, y0, c) return end
  for i = 0, floor(n) do
    plot(x0 + dx * i / n, y0 + dy * i / n, c)
  end
end

return M
