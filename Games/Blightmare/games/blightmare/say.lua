-- games/blightmare/say.lua
-- The small words a script is written in, for the regions. story.lua's header says how a script is put together.

local M = {}

--- Narration.
function M.t(text) return { text = text } end

--- A speaker: line("cleric") gives a function of the text. say is a portrait id or a look id.
function M.line(say) return function(text) return { say = say, text = text } end end

--- Someone with a portrait and a name of their own.
function M.person(say, name) return function(text) return { say = say, name = name, text = text } end end

--- A line that asks a question, with the list of answers under it. One short page: it shows again each time the list comes back.
function M.ask(line, options)
  line.choice = options
  return line
end

--- An option that goes back to the list once it's been heard.
function M.topic(label, steps) return { label, steps, again = true } end

return M
