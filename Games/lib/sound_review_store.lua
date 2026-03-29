local M = {}

local function sortedKeys(set)
  local items = {}

  for key, enabled in pairs(set or {}) do
    if enabled then
      items[#items + 1] = key
    end
  end

  table.sort(items)
  return items
end

local function normalizeSet(value)
  local set = {}

  if type(value) == "table" then
    for key, enabled in pairs(value) do
      if type(key) == "number" then
        if type(enabled) == "string" and enabled ~= "" then
          set[enabled] = true
        end
      elseif enabled then
        set[key] = true
      end
    end
  end

  return set
end

local function normalizeData(data)
  local value = type(data) == "table" and data or {}

  value.version = 1
  value.updated_at = tonumber(value.updated_at) or 0
  value.favorites = normalizeSet(value.favorites)
  value.rejects = normalizeSet(value.rejects)
  value.maybe = normalizeSet(value.maybe)
  value.sound_notes = type(value.sound_notes) == "table" and value.sound_notes or {}
  value.role_reviews = type(value.role_reviews) == "table" and value.role_reviews or {}

  return value
end

function M.load(path)
  if not fs.exists(path) then
    return normalizeData({})
  end

  local ok, loaded = pcall(function()
    return dofile(path)
  end)

  if not ok or type(loaded) ~= "table" then
    return normalizeData({})
  end

  return normalizeData(loaded)
end

function M.save(path, data)
  local normalized = normalizeData(data)
  local handle = fs.open(path, "w")
  local persisted = nil

  if not handle then
    return false, "Could not open review file"
  end

  persisted = {
    version = 1,
    updated_at = os.epoch("local"),
    favorites = sortedKeys(normalized.favorites),
    rejects = sortedKeys(normalized.rejects),
    maybe = sortedKeys(normalized.maybe),
    sound_notes = normalized.sound_notes,
    role_reviews = normalized.role_reviews,
  }

  handle.write("return " .. textutils.serialize(persisted))
  handle.close()
  return true, nil
end

function M.getBucket(data, soundId)
  if data.favorites[soundId] then
    return "favorite"
  end
  if data.rejects[soundId] then
    return "reject"
  end
  if data.maybe[soundId] then
    return "maybe"
  end
  return nil
end

function M.setBucket(data, soundId, bucket)
  data.favorites[soundId] = nil
  data.rejects[soundId] = nil
  data.maybe[soundId] = nil

  if bucket == "favorite" then
    data.favorites[soundId] = true
  elseif bucket == "reject" then
    data.rejects[soundId] = true
  elseif bucket == "maybe" then
    data.maybe[soundId] = true
  end
end

function M.toggleBucket(data, soundId, bucket)
  if M.getBucket(data, soundId) == bucket then
    M.setBucket(data, soundId, nil)
    return nil
  end

  M.setBucket(data, soundId, bucket)
  return bucket
end

function M.ensureSoundNote(data, soundId)
  local note = data.sound_notes[soundId]

  if type(note) ~= "table" then
    note = {
      manual_tags = {},
      note = "",
    }
    data.sound_notes[soundId] = note
  end

  if type(note.manual_tags) ~= "table" then
    note.manual_tags = {}
  end

  if type(note.note) ~= "string" then
    note.note = ""
  end

  return note
end

function M.setManualTags(data, soundId, tags)
  local note = M.ensureSoundNote(data, soundId)
  note.manual_tags = tags or {}
end

function M.getManualTags(data, soundId)
  local note = data.sound_notes[soundId]
  return note and note.manual_tags or {}
end

function M.setSoundNote(data, soundId, noteText)
  local note = M.ensureSoundNote(data, soundId)
  note.note = tostring(noteText or "")
end

function M.getSoundNote(data, soundId)
  local note = data.sound_notes[soundId]
  return note and note.note or ""
end

function M.ensureRoleReview(data, roleId, soundId)
  local roleReviews = data.role_reviews[roleId]
  local review = nil

  if type(roleReviews) ~= "table" then
    roleReviews = {}
    data.role_reviews[roleId] = roleReviews
  end

  review = roleReviews[soundId]
  if type(review) ~= "table" then
    review = {
      verdict = "",
      note = "",
      updated_at = 0,
    }
    roleReviews[soundId] = review
  end

  return review
end

function M.setRoleVerdict(data, roleId, soundId, verdict)
  local review = M.ensureRoleReview(data, roleId, soundId)
  review.verdict = tostring(verdict or "")
  review.updated_at = os.epoch("local")
end

function M.getRoleVerdict(data, roleId, soundId)
  local roleReviews = data.role_reviews[roleId]
  local review = roleReviews and roleReviews[soundId] or nil
  return review and review.verdict or ""
end

function M.setRoleNote(data, roleId, soundId, noteText)
  local review = M.ensureRoleReview(data, roleId, soundId)
  review.note = tostring(noteText or "")
  review.updated_at = os.epoch("local")
end

function M.getRoleNote(data, roleId, soundId)
  local roleReviews = data.role_reviews[roleId]
  local review = roleReviews and roleReviews[soundId] or nil
  return review and review.note or ""
end

return M
