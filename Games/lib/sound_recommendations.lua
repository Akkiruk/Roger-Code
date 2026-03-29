local soundMetadata = require("lib.sound_metadata")
local soundRoles = require("lib.sound_roles")
local reviewStore = require("lib.sound_review_store")

local M = {}

local verdictBoost = {
  best = 10,
  good = 5,
  avoid = -12,
}

local bucketBoost = {
  favorite = 4,
  maybe = 1,
  reject = -8,
}

local function buildReason(meta, roleId, bucket, verdict)
  local reasons = {}
  local score = soundMetadata.scoreForRole(meta.sound_id, roleId)

  if score > 0 then
    reasons[#reasons + 1] = "role score " .. tostring(score)
  end

  if #meta.role_candidates > 0 then
    reasons[#reasons + 1] = "AI candidates: " .. table.concat(meta.role_candidates, ", ")
  end

  if bucket then
    reasons[#reasons + 1] = "bucket: " .. bucket
  end

  if verdict and verdict ~= "" then
    reasons[#reasons + 1] = "verdict: " .. verdict
  end

  if #meta.auto_tags > 0 then
    reasons[#reasons + 1] = "tags: " .. table.concat(meta.auto_tags, ", ")
  end

  return table.concat(reasons, " | ")
end

function M.scoreSound(reviewData, roleId, soundId)
  local meta = soundMetadata.get(soundId)
  local score = 0
  local bucket = nil
  local verdict = nil

  if not meta then
    return -999, nil, nil
  end

  score = soundMetadata.scoreForRole(soundId, roleId)
  bucket = reviewStore.getBucket(reviewData, soundId)
  verdict = reviewStore.getRoleVerdict(reviewData, roleId, soundId)

  if bucket and bucketBoost[bucket] then
    score = score + bucketBoost[bucket]
  end

  if verdict and verdictBoost[verdict] then
    score = score + verdictBoost[verdict]
  end

  score = score + math.floor((meta.ai_confidence or 0) * 10 + 0.5)

  return score, bucket, verdict
end

function M.getTopCandidates(reviewData, roleId, limit)
  local results = {}
  local allMetadata = soundMetadata.all()
  local role = soundRoles.BY_ID[roleId]
  local soundId = nil

  if not role then
    return results
  end

  for soundId, meta in pairs(allMetadata or {}) do
    local score, bucket, verdict = M.scoreSound(reviewData, roleId, soundId)
    if score > 0 then
      results[#results + 1] = {
        sound_id = soundId,
        score = score,
        bucket = bucket,
        verdict = verdict,
        reason = buildReason(meta, roleId, bucket, verdict),
      }
    end
  end

  table.sort(results, function(a, b)
    if a.score == b.score then
      return a.sound_id < b.sound_id
    end
    return a.score > b.score
  end)

  if limit and #results > limit then
    while #results > limit do
      table.remove(results)
    end
  end

  return results
end

return M
