-- arcade_net.lua
-- Tells the floor how matches end, over rednet, for a hub wall to show. Optional: with no modem nothing happens.
-- It only ever sends, and it carries no tokens and no secrets. Nothing the Arcade does depends on an answer.

local M = {}

M.PROTOCOL = "arcade.v1"

local opened = false

--- Open every modem attached. Safe to call again when peripherals change.
function M.open()
  opened = false
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "modem") then
      pcall(rednet.open, name)
      opened = true
    end
  end
  return opened
end

--- Someone playing, for the tracker (track.lua says what's in it). The cabinet's label says which cabinet it was.
function M.play(msg)
  if not opened then return end
  msg.kind = "play"
  msg.cabinet = os.getComputerLabel and os.getComputerLabel() or nil
  pcall(rednet.broadcast, msg, M.PROTOCOL)
end

--- An answer to one computer that asked, such as a tracker asking for this cabinet's book.
function M.reply(to, msg)
  if not opened then return end
  msg.cabinet = os.getComputerLabel and os.getComputerLabel() or nil
  pcall(rednet.send, to, msg, M.PROTOCOL)
end

--- A finished match, for leaderboards on another screen.
function M.result(game, title, red, blue, winner, moves, ranked)
  if not opened then return end
  pcall(rednet.broadcast, {
    kind = "result", game = game, title = title, red = red, blue = blue, winner = winner, moves = moves, ranked = ranked,
  }, M.PROTOCOL)
end

return M
