local M = {}

local function copyRect(rect)
  return {
    x = rect.x,
    y = rect.y,
    w = rect.w,
    h = rect.h,
  }
end

function M.rect(x, y, w, h)
  return {
    x = x,
    y = y,
    w = math.max(0, w),
    h = math.max(0, h),
  }
end

function M.copy(rect)
  return copyRect(rect)
end

function M.inset(rect, dx, dy)
  local insetX = dx or 0
  local insetY = dy or insetX
  return M.rect(
    rect.x + insetX,
    rect.y + insetY,
    rect.w - (insetX * 2),
    rect.h - (insetY * 2)
  )
end

function M.sliceTop(rect, height, gap)
  local slice = M.rect(rect.x, rect.y, rect.w, math.min(rect.h, height))
  local nextGap = gap or 0
  local remainder = M.rect(rect.x, rect.y + slice.h + nextGap, rect.w, rect.h - slice.h - nextGap)
  return slice, remainder
end

function M.sliceBottom(rect, height, gap)
  local sliceHeight = math.min(rect.h, height)
  local slice = M.rect(rect.x, rect.y + rect.h - sliceHeight, rect.w, sliceHeight)
  local nextGap = gap or 0
  local remainder = M.rect(rect.x, rect.y, rect.w, rect.h - sliceHeight - nextGap)
  return slice, remainder
end

function M.sliceLeft(rect, width, gap)
  local slice = M.rect(rect.x, rect.y, math.min(rect.w, width), rect.h)
  local nextGap = gap or 0
  local remainder = M.rect(rect.x + slice.w + nextGap, rect.y, rect.w - slice.w - nextGap, rect.h)
  return slice, remainder
end

function M.sliceRight(rect, width, gap)
  local sliceWidth = math.min(rect.w, width)
  local slice = M.rect(rect.x + rect.w - sliceWidth, rect.y, sliceWidth, rect.h)
  local nextGap = gap or 0
  local remainder = M.rect(rect.x, rect.y, rect.w - sliceWidth - nextGap, rect.h)
  return slice, remainder
end

function M.columns(rect, fractions, gap)
  local parts = {}
  local cursorX = rect.x
  local remaining = rect.w
  local spacing = gap or 0
  local totalGap = math.max(0, (#fractions - 1) * spacing)
  local usableWidth = math.max(0, rect.w - totalGap)

  for index, fraction in ipairs(fractions) do
    local width = usableWidth
    if index < #fractions then
      width = math.max(0, math.floor(usableWidth * fraction + 0.5))
      remaining = remaining - width - spacing
    else
      width = math.max(0, remaining)
    end

    parts[index] = M.rect(cursorX, rect.y, width, rect.h)
    cursorX = cursorX + width + spacing
  end

  return parts
end

function M.rows(rect, fractions, gap)
  local parts = {}
  local cursorY = rect.y
  local remaining = rect.h
  local spacing = gap or 0
  local totalGap = math.max(0, (#fractions - 1) * spacing)
  local usableHeight = math.max(0, rect.h - totalGap)

  for index, fraction in ipairs(fractions) do
    local height = usableHeight
    if index < #fractions then
      height = math.max(0, math.floor(usableHeight * fraction + 0.5))
      remaining = remaining - height - spacing
    else
      height = math.max(0, remaining)
    end

    parts[index] = M.rect(rect.x, cursorY, rect.w, height)
    cursorY = cursorY + height + spacing
  end

  return parts
end

function M.contains(rect, x, y)
  return x >= rect.x
    and x <= rect.x + rect.w - 1
    and y >= rect.y
    and y <= rect.y + rect.h - 1
end

function M.intersect(a, b)
  local left = math.max(a.x, b.x)
  local top = math.max(a.y, b.y)
  local right = math.min(a.x + a.w - 1, b.x + b.w - 1)
  local bottom = math.min(a.y + a.h - 1, b.y + b.h - 1)

  if right < left or bottom < top then
    return nil
  end

  return M.rect(left, top, right - left + 1, bottom - top + 1)
end

return M
