-- story/index.lua
-- The story's table of contents, read from content/story/list.lua: missions in order, by id, and where each act ends.
-- Also the cast, the places and the phone book (content files too), and the check the tests run on all of them.
--
--   local idx, err = index.load(content)        content: core/content.lua's reader
--   idx.missions  idx.byId  idx.acts  idx.actEnd[act] -> the id of the act's last mission  idx.cast  idx.places  idx.phone
--   idx.script(id) -> the mission's function(api), or nil, err

local M = {}

function M.load(content)
  local list, err = content:data("story/list.lua")
  if not list then return nil, err end
  local idx = { missions = list.missions, acts = list.acts, byId = {}, actEnd = {}, content = content }
  for i, def in ipairs(list.missions) do
    def.index = i
    idx.byId[def.id] = def
    idx.actEnd[def.act] = def.id
  end
  idx.cast = content:data("story/cast.lua") or {}
  idx.places = content:data("story/places.lua") or {}
  idx.phone = content:data("story/phone.lua") or { order = {}, contacts = {} }
  function idx.script(id)
    return content:script("story/m_" .. id .. ".lua")
  end
  return idx
end

return M
