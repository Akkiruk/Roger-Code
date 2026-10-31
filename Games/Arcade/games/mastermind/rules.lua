-- games/mastermind/rules.lua
-- Mastermind for two, one code each. Pure: no screen, sound or files. Each seat hides four pegs of six colours, repeats
-- allowed, then both try to crack the other's code in turns. The seat that went first has had one more guess, so if it
-- cracks the code the other seat still gets its guess: both cracking in one round is a draw. secrets[seat] is that seat's
-- secret, and rules.viewFor is all anyone else is given.

local M = { PEGS = 4, COLOURS = 6, ROUNDS = 10 }

local PEGS, COLOURS = M.PEGS, M.COLOURS

function M.new(opts)
  local first = opts.first or 1
  return {
    turn = first, first = first, winner = 0, moves = 0, phase = "setup",
    secrets = {}, log = { {}, {} },
  }
end

local function isCode(code)
  return type(code) == "string" and #code == PEGS and not code:find("[^1-" .. COLOURS .. "]")
end

--- How close a guess is: right colour in the right place, and right colour in the wrong place.
function M.feedback(code, guess)
  local black, codeLeft, guessLeft = 0, {}, {}
  for i = 1, PEGS do
    local c, g = code:sub(i, i), guess:sub(i, i)
    if c == g then
      black = black + 1
    else
      codeLeft[c] = (codeLeft[c] or 0) + 1
      guessLeft[g] = (guessLeft[g] or 0) + 1
    end
  end
  local white = 0
  for colour, n in pairs(guessLeft) do white = white + math.min(n, codeLeft[colour] or 0) end
  return black, white
end

function M.checkAction(s, a)
  if s.winner ~= 0 then return false, "game over" end
  if a.kind == "forfeit" then return true end
  if a.kind ~= (s.phase == "setup" and "set" or "guess") then return false, "not now" end
  if not isCode(a.code) then return false, "Pick all four pegs first" end
  return true
end

local function cracked(s, seat)
  local log = s.log[seat]
  local last = log[#log]
  return last ~= nil and last.black == PEGS
end

function M.step(s, a)
  local ok, why = M.checkAction(s, a)
  if not ok then return nil, why end
  if a.kind == "forfeit" then
    s.winner, s.forfeit = 3 - a.seat, a.seat
    return s, {}
  end
  local p = s.turn
  if a.kind == "set" then
    s.secrets[p] = a.code
    if s.secrets[3 - p] then
      s.phase, s.turn = "play", s.first
    else
      s.turn = 3 - p
    end
    return s, { { type = "set", seat = p } }
  end
  local black, white = M.feedback(s.secrets[3 - p], a.code)
  local log = s.log[p]
  log[#log + 1] = { code = a.code, black = black, white = white }
  s.moves = s.moves + 1
  local ev = { type = "guess", seat = p, black = black, white = white }
  if p == s.first then
    s.turn = 3 - p -- the other seat always answers, whatever this guess did
    return s, { ev }
  end
  local a1, a2 = cracked(s, s.first), cracked(s, p)
  if a1 and a2 then
    s.winner = 3
  elseif a1 then
    s.winner = s.first
  elseif a2 then
    s.winner = p
  elseif #log >= M.ROUNDS then
    s.winner = 3
  else
    s.turn = s.first
  end
  return s, { ev }
end

--- Every code, for a missed timer or a computer that failed.
function M.legalActions(s)
  local out = {}
  if s.winner ~= 0 then return out end
  local kind = s.phase == "setup" and "set" or "guess"
  local function add(prefix)
    if #prefix == PEGS then
      out[#out + 1] = { kind = kind, code = prefix }
      return
    end
    for c = 1, COLOURS do add(prefix .. c) end
  end
  add("")
  return out
end

function M.key(a) return a.kind .. " " .. a.code end

local function copyLog(log)
  local out = {}
  for i, g in ipairs(log) do out[i] = { code = g.code, black = g.black, white = g.white } end
  return out
end

--- What seat may know: their own code and every guess with its answer.
function M.viewFor(s, seat)
  return {
    turn = s.turn, first = s.first, winner = s.winner, moves = s.moves, phase = s.phase, seat = seat,
    secrets = { [seat] = s.secrets[seat] }, log = { copyLog(s.log[1]), copyLog(s.log[2]) },
  }
end

function M.snapshot(s)
  local function rows(log)
    local out = {}
    for i, g in ipairs(log) do out[i] = g.code .. ":" .. g.black .. "," .. g.white end
    return out
  end
  return { phase = s.phase, log = { rows(s.log[1]), rows(s.log[2]) } }
end

return M
