-- arcade_seats.lua
-- Who may do what at the wall. Pure: every answer comes from the seats and the name vhcc_touch gave for the touch.
-- A seat is { name }, { name, guest = true } or { name, cpu = level }. Identity is the mod's vhcc_touch event, so a
-- named seat answers only to that player. A guest has no identity of their own, so anyone at the wall plays for them:
-- that is how one person plays hot seat against a guest. On a computer with no vhcc_touch at all (who is nil for every
-- touch) nothing can be checked, so the wall is open to whoever is there.

local M = {}

function M.isHuman(seat) return seat ~= nil and not seat.cpu and not seat.guest end

local function isIn(seat, who)
  return M.isHuman(seat) and seat.name == who
end

--- Is this player sitting at the match?
function M.isSeated(match, who)
  return isIn(match.red, who) or isIn(match.blue, who)
end

--- May this touch move for the seat that is to move?
-- @return boolean, message for the wall when refused
function M.mayMove(match, mover, who)
  if who == nil or not M.isHuman(mover) then return true end
  if who == mover.name then return true end
  return false, string.format("%s - it is %s's turn", who, mover.name)
end

--- May this touch use a match control (pause, resign, hint)? Only the people playing, or anyone when no seat is named.
function M.mayControl(match, who)
  if who == nil then return true end
  if not M.isHuman(match.red) and not M.isHuman(match.blue) then return true end
  if M.isSeated(match, who) then return true end
  return false, who .. " is not in this game"
end

--- May this touch take a seat for name? A player only ever seats themselves, so nobody can be put in a game unasked.
function M.maySit(name, who)
  if who == nil or who == name then return true end
  return false, name .. " has to tap their own name"
end

--- The seat number a resignation counts against: the toucher's own seat, otherwise the side to move. A computer never
-- resigns, so with one to move it counts against the other side.
function M.resigner(match, who, turn)
  if isIn(match.red, who) then return 1 end
  if isIn(match.blue, who) then return 2 end
  local slot = turn == 1 and match.red or match.blue
  if slot.cpu then return 3 - turn end
  return turn
end

--- The seat a wall belongs to, in a match played on two walls. A wall is a monitor's name, which stays true if the other
-- wall is lost. A computer has no eyes, so its wall belongs to nobody and shows nothing secret.
function M.wallSeat(match, wall)
  if match.red.wall == wall and not match.red.cpu then return 1 end
  if match.blue.wall == wall and not match.blue.cpu then return 2 end
  return nil
end

local function distance(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Has a player crossed to the far side of the divider? A wall's spot is where its owner stood when they last touched
-- it, so this needs no compass and works however the cabinet was built. With any position unknown the answer is no.
function M.peeking(position, spotHere, spotThere)
  if not (position and spotHere and spotThere) then return false end
  return distance(position, spotHere) < distance(position, spotThere)
end

--- Does a match have two named players, so that either one quitting costs a rating?
function M.isRated(match)
  return M.isHuman(match.red) and M.isHuman(match.blue) and match.red.name ~= match.blue.name
end

return M
