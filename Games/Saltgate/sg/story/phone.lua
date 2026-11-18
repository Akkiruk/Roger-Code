-- story/phone.lua
-- The phone, without the screen: which contacts you have, their texts, what a call says. Pure; the screen
-- (sg/story/screens.lua) draws it. The data is content/story/phone.lua (read through story/index.lua), the state is
-- the save's story.phone = { unlocked = { id = true }, texts = { { from, text, read } } }.

local M = {}

--- The contacts you have, in the book's order: { id, name, blurb, unread }.
function M.contacts(story, idx)
  local out = {}
  local phone = story.phone or { unlocked = {}, texts = {} }
  for _, id in ipairs(idx.phone.order) do
    local c = idx.phone.contacts[id]
    if c and phone.unlocked[id] then
      local unread = 0
      for _, tx in ipairs(phone.texts) do
        if tx.from == id and not tx.read then unread = unread + 1 end
      end
      out[#out + 1] = { id = id, name = c.name, blurb = c.blurb, unread = unread }
    end
  end
  return out
end

--- Everything unread, all contacts.
function M.unread(story)
  local n = 0
  for _, tx in ipairs((story.phone or {}).texts or {}) do
    if not tx.read then n = n + 1 end
  end
  return n
end

--- The texts from one contact, oldest first.
function M.thread(story, id)
  local out = {}
  for _, tx in ipairs((story.phone or {}).texts or {}) do
    if tx.from == id then out[#out + 1] = tx end
  end
  return out
end

function M.markRead(story, id)
  for _, tx in ipairs((story.phone or {}).texts or {}) do
    if tx.from == id then tx.read = true end
  end
end

--- What a call to a contact says: { { who, text }, ... }. Tam gives the job's hint when there is one.
function M.call(story, idx, id, hint)
  local c = idx.phone.contacts[id]
  if not c then return { { "", "No answer." } } end
  if id == "tam" and hint then
    return { { "Tam", hint } }
  end
  local best, fallback
  for _, entry in ipairs(c.calls) do
    if not entry.after then
      fallback = fallback or entry
    elseif story.done and story.done[entry.after] then
      best = entry
    end
  end
  local entry = best or fallback or c.calls[1]
  if not entry then return { { c.name, "..." } } end
  return entry.say
end

return M
