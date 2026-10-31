-- games/uttt/store.lua
-- Ultimate Tic-Tac-Toe's records: the Arcade's records with this game's achievements and settings.

local Records = require("arcade_records")
local config = require("games.uttt.uttt_constants")

local M = setmetatable({}, { __index = Records })

M.ACHIEVEMENTS = {
  first_win = { name = "First Blood", text = "Win your first game" },
  sweep = { name = "Clean Sweep", text = "Win without losing a small board" },
  comeback = { name = "Comeback", text = "Win after trailing by 2 small boards" },
  quick = { name = "Blitz", text = "Win in 25 moves or fewer" },
  marathon = { name = "Marathon", text = "Finish a game of 60+ moves" },
  hot = { name = "On Fire", text = "Win 3 games in a row" },
  giant = { name = "Giant Killer", text = "Beat a player rated 100+ above you" },
  machine = { name = "Machine Breaker", text = "Beat the computer on hard" },
  regular = { name = "Regular", text = "Play 25 games" },
  veteran = { name = "Veteran", text = "Play 100 games" },
  rival = { name = "Rivalry", text = "Play the same opponent 5 times" },
}

local function key(name)
  return string.lower(tostring(name or ""))
end

local function award(ctx)
  local m, sides, players, grant = ctx.m, ctx.sides, ctx.players, ctx.grant
  for i, sd in ipairs(sides) do
    local p = players[i]
    if p then
      local won = m.winner == sd.num
      if won then
        grant(p, "first_win")
        if sd.other == 0 and not m.forfeit then grant(p, "sweep") end
        if (m.trailed or 0) >= 2 and sd.num == m.winner then grant(p, "comeback") end
        if (m.moves or 0) <= 25 and not m.forfeit then grant(p, "quick") end
        if p.streak >= 3 then grant(p, "hot") end
        if sd.oppCpu == "hard" then grant(p, "machine") end
      end
      if (m.moves or 0) >= 60 then grant(p, "marathon") end
      if p.games >= 25 then grant(p, "regular") end
      if p.games >= 100 then grant(p, "veteran") end
      if ctx.ranked then
        local r = p.h2h[key(sd.oppName)]
        if r and r.w + r.l + r.d >= 5 then grant(p, "rival") end
      end
    end
  end
  if ctx.ranked and (m.winner == 1 or m.winner == 2) then
    local wi = m.winner
    local li = 3 - wi
    local summary = ctx.summary
    local wSum, lSum = summary[wi == 1 and "red" or "blue"], summary[li == 1 and "red" or "blue"]
    if wSum.before and lSum.before and lSum.before - wSum.before >= 100 then grant(players[wi], "giant") end
  end
end

function M.new(opts)
  opts = opts or {}
  return Records.new({
    path = opts.path or config.DATA_FILE, io = opts.io, clock = opts.clock, log = opts.log,
    settings = config.SETTINGS, achievements = M.ACHIEVEMENTS, award = award,
  })
end

return M
