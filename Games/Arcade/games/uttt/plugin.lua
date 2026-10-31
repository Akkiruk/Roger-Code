-- games/uttt/plugin.lua
-- Ultimate Tic-Tac-Toe as an Arcade game.

local ai = require("games.uttt.ai")
local base = require("games.base")
local config = require("games.uttt.uttt_config")
local rules = require("games.uttt.rules")
local Store = require("games.uttt.store")
local view = require("games.uttt.view")

local M = {
  id = "uttt",
  title = "Ultimate Tic-Tac-Toe",
  short = "Tic-Tac-Toe",
  chatTag = "UTTT",
  blurb = "Ultimate: nine boards in one",
  color = "hi",
  minSize = { w = 80, h = 54 },
  accent = 0xFFD257,
  cpuLevels = { "easy", "medium", "hard" },
  sounds = config.SOUNDS,
  rules = rules,
  view = view,
}

--- The rules' options for a new match, from this game's settings.
function M.matchOptions(store)
  return { tiebreak = store:setting("tiebreak") }
end

function M.newStore(opts)
  return Store.new(opts)
end

--- A computer's action for the player to move, or nil. Runs in small slices when opts.yield is set.
function M.chooseAction(state, level, opts)
  local b, c, info = ai.choose(state, level, opts)
  if not b then return nil, info end
  return { kind = "move", b = b, c = c }, info
end

--- A fresh per-match table for what this game tracks beyond its rules.
function M.newExtras()
  return { trailed = { 0, 0 } }
end

--- What the records need from a finished match, beyond who played and who won.
function M.summarize(match)
  local s = match.state
  local trailed = match.extras.trailed
  return {
    moves = s.moves, boardsRed = s.boards[1], boardsBlue = s.boards[2],
    trailed = s.winner == 1 and trailed[1] or trailed[2],
  }
end

--- Rows on the settings screen: { id, label }, and what tapping one does.
function M.settingsRows(store)
  return {
    { "timer", "MOVE TIMER: " .. (store:setting("timer") > 0 and (store:setting("timer") .. "s") or "OFF") },
    { "tiebreak", "NO MOVES LEFT: " .. (store:setting("tiebreak") and "MOST BOARDS WINS (HOUSE)" or "DRAW") },
    { "ai", "DEFAULT CPU: " .. string.upper(store:setting("ai")) },
  }
end

function M.changeSetting(store, id, cycle)
  if id == "timer" then
    store:setting("timer", cycle({ 0, 15, 30, 60 }, store:setting("timer")))
  elseif id == "tiebreak" then
    store:setting("tiebreak", not store:setting("tiebreak"))
  elseif id == "ai" then
    store:setting("ai", cycle({ "easy", "medium", "hard" }, store:setting("ai")))
  end
end

--- The settings shown in the lobby's options button.
function M.optionsLine(store)
  local timer = store:setting("timer")
  return (timer > 0 and ("TIMER " .. timer .. "s") or "TIMER OFF") .. "  /  "
    .. (store:setting("tiebreak") and "MOST-BOARDS RULE" or "STANDARD DRAW")
end

--- How long each move may take, in seconds. 0 is no limit.
function M.moveTimer(store)
  return store:setting("timer") or 0
end

return base.fill(M)
