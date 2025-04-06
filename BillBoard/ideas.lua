local ideas = {}

local function loadIdeas()
    if not fs.exists("ideas.db") then
        return {}
    end
    local file = fs.open("ideas.db", "r")
    local data = textutils.unserialize(file.readAll())
    file.close()
    return data or {}
end

local function saveIdeas(data)
    local file = fs.open("ideas.db", "w")
    file.write(textutils.serialize(data))
    file.close()
end

local storedIdeas = loadIdeas()

function ideas.init()
    if not fs.exists("ideas.db") then
        saveIdeas({})
    end
    storedIdeas = loadIdeas()
end

function ideas.save(text)
    table.insert(storedIdeas, {
        text = text,
        timestamp = os.epoch("utc")
    })
    saveIdeas(storedIdeas)
end

function ideas.getRecent(count)
    count = count or 5
    local recent = {}
    for i = #storedIdeas, math.max(1, #storedIdeas - count + 1), -1 do
        table.insert(recent, storedIdeas[i])
    end
    return recent
end

return ideas