local M = {}

function M.isArray(value)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" then
      return false
    end
    count = count + 1
  end

  return count == #value
end

function M.deepCopy(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, item in pairs(value) do
    copy[key] = M.deepCopy(item)
  end

  return copy
end

function M.mergeDefaults(defaults, loaded)
  if type(defaults) ~= "table" then
    if loaded == nil then
      return defaults
    end
    return loaded
  end

  if type(loaded) ~= "table" then
    return M.deepCopy(defaults)
  end

  if M.isArray(defaults) then
    local result = {}
    for index, item in ipairs(loaded) do
      result[index] = M.deepCopy(item)
    end
    return result
  end

  local result = M.deepCopy(defaults)
  for key, value in pairs(loaded) do
    if defaults[key] ~= nil then
      result[key] = M.mergeDefaults(defaults[key], value)
    else
      result[key] = M.deepCopy(value)
    end
  end

  return result
end

function M.sortedKeys(map)
  local keys = {}
  for key in pairs(map or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

function M.clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

function M.normalizeKey(text)
  local value = tostring(text or ""):lower()
  value = value:gsub("^%s+", "")
  value = value:gsub("%s+$", "")
  value = value:gsub("[^%w:]+", "_")
  value = value:gsub("_+", "_")
  return value
end

function M.cycleValue(list, current, delta)
  local index = 1
  for i, value in ipairs(list) do
    if value == current then
      index = i
      break
    end
  end

  index = index + delta
  if index < 1 then
    index = #list
  elseif index > #list then
    index = 1
  end

  return list[index]
end

function M.pushRecent(list, entry, limit)
  list[#list + 1] = entry
  while #list > limit do
    table.remove(list, 1)
  end
end

function M.findByKey(list, key)
  if type(list) ~= "table" then
    return nil
  end

  for index, entry in ipairs(list) do
    if entry.key == key then
      return entry, index
    end
  end

  return nil
end

function M.formatPercent(value)
  if type(value) ~= "number" then
    return "?"
  end
  return tostring(math.floor(value + 0.5)) .. "%"
end

function M.trimText(text, maxLen)
  local value = tostring(text or "")
  if #value <= maxLen then
    return value
  end
  if maxLen <= 2 then
    return value:sub(1, maxLen)
  end
  return value:sub(1, maxLen - 2) .. ".."
end

function M.wrapText(text, width, maxLines)
  local source = tostring(text or "")
  width = math.max(1, tonumber(width) or 1)
  maxLines = maxLines or 999

  local words = {}
  for word in source:gmatch("%S+") do
    words[#words + 1] = word
  end

  if #words == 0 then
    return { "" }
  end

  local lines = {}
  local current = ""

  for _, word in ipairs(words) do
    local candidate = current == "" and word or (current .. " " .. word)
    if #candidate <= width then
      current = candidate
    else
      if current ~= "" then
        lines[#lines + 1] = current
        if #lines >= maxLines then
          lines[#lines] = M.trimText(lines[#lines], width)
          return lines
        end
        current = word
      else
        lines[#lines + 1] = M.trimText(word, width)
        if #lines >= maxLines then
          return lines
        end
      end
    end
  end

  if current ~= "" and #lines < maxLines then
    lines[#lines + 1] = current
  end

  if #lines == 0 then
    lines[1] = ""
  end

  return lines
end

function M.formatTime(epochMs)
  if type(epochMs) ~= "number" then
    return "--:--:--"
  end
  local seconds = math.floor(epochMs / 1000)
  local hours = math.floor(seconds / 3600) % 24
  local minutes = math.floor(seconds / 60) % 60
  local secs = seconds % 60
  return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

return M
