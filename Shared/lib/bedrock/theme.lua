local M = {}

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, child in pairs(value) do
    copy[key] = deepCopy(child)
  end
  return copy
end

function M.merge(base, overrides)
  local merged = deepCopy(base or {})
  for key, value in pairs(overrides or {}) do
    if type(value) == "table" and type(merged[key]) == "table" then
      merged[key] = M.merge(merged[key], value)
    else
      merged[key] = deepCopy(value)
    end
  end
  return merged
end

function M.resolve(theme, value, fallback)
  if type(value) == "number" then
    return value
  end

  if type(value) == "string" and theme and theme[value] ~= nil then
    return theme[value]
  end

  if type(fallback) == "number" then
    return fallback
  end

  if type(fallback) == "string" and theme and theme[fallback] ~= nil then
    return theme[fallback]
  end

  return colors.white
end

function M.toBlit(color)
  if colors.toBlit then
    return colors.toBlit(color)
  end

  local lookup = {
    [colors.white] = "0",
    [colors.orange] = "1",
    [colors.magenta] = "2",
    [colors.lightBlue] = "3",
    [colors.yellow] = "4",
    [colors.lime] = "5",
    [colors.pink] = "6",
    [colors.gray] = "7",
    [colors.lightGray] = "8",
    [colors.cyan] = "9",
    [colors.purple] = "a",
    [colors.blue] = "b",
    [colors.brown] = "c",
    [colors.green] = "d",
    [colors.red] = "e",
    [colors.black] = "f",
  }

  return lookup[color] or "0"
end

return M
