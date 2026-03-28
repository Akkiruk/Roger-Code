local M = {}

function M.trimText(text, maxLen)
  local value = tostring(text or "")
  if maxLen <= 0 then
    return ""
  end
  if #value <= maxLen then
    return value
  end
  if maxLen <= 2 then
    return value:sub(1, maxLen)
  end
  return value:sub(1, maxLen - 2) .. ".."
end

function M.truncateText(text, maxWidth, suffix)
  local value = tostring(text or "")
  local limit = maxWidth or 0
  if limit < 1 then
    return ""
  end
  if #value <= limit then
    return value
  end

  local tail = suffix or ".."
  if limit <= #tail then
    return value:sub(1, limit)
  end

  return value:sub(1, limit - #tail) .. tail
end

function M.wrapText(text, maxWidth, maxLines)
  local source = tostring(text or "")
  local width = math.max(1, maxWidth or 1)
  local limit = maxLines or math.huge
  local lines = {}
  local current = ""

  for word in source:gmatch("%S+") do
    local candidate = current == "" and word or (current .. " " .. word)
    if #candidate <= width then
      current = candidate
    else
      if current ~= "" then
        lines[#lines + 1] = current
        if #lines >= limit then
          return lines
        end
      end

      current = #word <= width and word or M.trimText(word, width)
    end
  end

  if current ~= "" and #lines < limit then
    lines[#lines + 1] = current
  end

  if #lines == 0 then
    lines[1] = ""
  end

  return lines
end

return M
