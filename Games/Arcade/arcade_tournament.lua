-- arcade_tournament.lua
-- A knockout on one game for three to eight players, played as ordinary matches. Pure apart from its save file.
-- rounds[n] is a list of pairings { a, b, winner }. A missing b is a bye: a, who goes straight through.

local M = { MIN = 3, MAX = 8 }

local FILE = "arcade_tournament.dat"

--- A bracket from players in the order they joined, shuffled by shuffle(list) if given.
function M.new(game, names, shuffle)
  local players = {}
  for i, name in ipairs(names) do players[i] = name end
  if shuffle then shuffle(players) end
  local t = { game = game, rounds = {} }
  M.fillRound(t, players)
  return t
end

--- Pair up who is left. An odd player out gets a bye.
function M.fillRound(t, players)
  local round = {}
  for i = 1, #players, 2 do
    local pairing = { a = players[i], b = players[i + 1] }
    if not pairing.b then pairing.winner = pairing.a end
    round[#round + 1] = pairing
  end
  t.rounds[#t.rounds + 1] = round
end

--- The next pairing still to play, or nil.
function M.next(t)
  local round = t.rounds[#t.rounds]
  for _, pairing in ipairs(round) do
    if not pairing.winner then return pairing end
  end
  return nil
end

--- The winner of the whole thing, or nil.
function M.champion(t)
  local round = t.rounds[#t.rounds]
  if #round == 1 and round[1].winner and round[1].b then return round[1].winner end
  return nil
end

--- Put a match's winner through. A draw changes nothing, so the same pair play again. Returns the champion if that was the final.
function M.report(t, winner)
  local pairing = M.next(t)
  if not pairing or not winner then return nil end
  pairing.winner = winner
  if M.next(t) then return nil end
  local through = {}
  for _, p in ipairs(t.rounds[#t.rounds]) do through[#through + 1] = p.winner end
  if #through == 1 then return through[1] end
  M.fillRound(t, through)
  if M.next(t) == nil then return M.report(t, nil) end -- only a lone bye left cannot happen with two or more through
  return nil
end

function M.save(t)
  if not t then
    if fs.exists(FILE) then fs.delete(FILE) end
    return
  end
  local h = fs.open(FILE .. ".tmp", "w")
  if not h then return end
  h.write(textutils.serialise(t))
  h.close()
  if fs.exists(FILE) then fs.delete(FILE) end
  fs.move(FILE .. ".tmp", FILE)
end

function M.load()
  if not fs.exists(FILE) then return nil end
  local h = fs.open(FILE, "r")
  if not h then return nil end
  local ok, value = pcall(textutils.unserialise, h.readAll() or "")
  h.close()
  if ok and type(value) == "table" and value.rounds then return value end
  return nil
end

return M
