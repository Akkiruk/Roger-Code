-- games/blightmare/intro_player.lua
-- The opening as the cabinet's idle screen. It plays by itself on a loop, silent, as the attract. A touch carries on from
-- the same moment with its music and sounds and a SKIP, and its end, or SKIP, opens the ready screen (lib/arcade/action.lua).
-- The pages come from story.INTRO, the pictures from intro.lua, and each page stays up long enough to read.

local ui = require("lib.arcade.ui")

local C = ui.C
local floor, max, min = math.floor, math.max, math.min

local M = {}

local TICK_MS = 120        -- the game's own tick, which the pictures' clocks count in
local BIG_TICKS = 30       -- big letters stay about three and a half seconds
local TEXT_MIN = 48        -- narration about six seconds at the least
local TEXT_PER_CHAR = 0.55 -- and longer for longer lines: about fifteen letters a second
local LOOP_HOLD = 34       -- idle, the last page holds a while before it starts again
local BOX_H = 17
local NARRATE_WIDE = 100

local function story() return require("games.blightmare.story") end
local function intro() return require("games.blightmare.intro") end
local function rules() return require("games.blightmare.rules") end

local pages -- built once from story.INTRO

--- Each page: the picture under it and how long that picture has been up when the page starts, its words, how long it
-- stays, the music playing under it, and any sounds the script plays as it starts.
local function build()
  pages = {}
  local pic, picSince, music, sfx = nil, 0, false, {}
  for _, step in ipairs(story().INTRO or {}) do
    if step.mark then break end
    if step.pic ~= nil then
      pic, picSince = step.pic or nil, 0
    elseif step.music ~= nil then
      music = step.music or false
    elseif step.sfx then
      sfx[#sfx + 1] = step.sfx
    elseif step.text or step.big then
      local ticks = step.big and BIG_TICKS or max(TEXT_MIN, floor(#step.text * TEXT_PER_CHAR))
      pages[#pages + 1] = { pic = pic, picFrom = picSince, text = step.text, big = step.big, ticks = ticks, music = music, sfx = sfx }
      picSince = picSince + ticks
      sfx = {}
    end
  end
  return pages
end

function M.pages() return pages or build() end

--- A fresh run of it: page 1, tick 0. ms is where its clock started.
function M.new(ms)
  return { page = 1, t = 0, from = ms, last = 0, ticks = 0 }
end

--- Move the clock on to ms. Returns whether the picture changed, and whether it has finished. Played sounds go to
-- play(name) and music to music(name or nil), when given: the idle loop gives neither.
function M.step(run, ms, play, music)
  local list = M.pages()
  local ticks = floor((ms - run.from) / TICK_MS)
  if ticks <= run.ticks then return false, false end
  local changed = false
  while run.ticks < ticks do
    run.ticks = run.ticks + 1
    run.t = run.t + 1
    local page = list[run.page]
    if run.t >= page.ticks + (run.page == #list and run.hold or 0) then
      if run.page >= #list then return true, true end
      M.turn(run, play, music)
      changed = true
    else
      local picT = page.picFrom + run.t
      if play and page.pic then
        for _, cue in ipairs(intro().cues(page.pic)) do
          if cue[1] == picT then play(cue[2]) end
        end
      end
      local length = page.pic and intro().length(page.pic)
      if length == true or (length and picT <= length) then changed = true end
    end
  end
  return changed, false
end

--- On to the next page: its sounds, and its music if that changes.
function M.turn(run, play, music)
  local list = M.pages()
  local before = list[run.page]
  run.page, run.t = min(#list, run.page + 1), 0
  local page = list[run.page]
  if play then
    for _, name in ipairs(page.sfx) do play(name) end
  end
  if music and page.music ~= before.music then music(page.music or nil) end
end

--- The idle loop: a run that starts again at its end, after a pause on the last page.
function M.loopStep(run, ms)
  run.hold = LOOP_HOLD
  local changed, done = M.step(run, ms)
  if done then
    local fresh = M.new(ms)
    for k, v in pairs(fresh) do run[k] = v end
    return true
  end
  return changed
end

--- A touch: from here on the run is heard. The music for this page starts at once.
function M.engage(run, music)
  run.hold = 0
  local page = M.pages()[run.page]
  if music and page.music then music(page.music) end
end

local function drawBox(W, H, text, tapHint)
  local y = H - BOX_H
  ui.fill(0, y, W, BOX_H, C.panel)
  ui.fill(0, y, W, 1, C.line)
  for i, line in ipairs(rules().wrap(text, NARRATE_WIDE)) do
    if i > 5 then break end
    ui.small(line, 3, y + 2 + (i - 1) * 2, C.text, C.panel)
  end
  if tapHint then ui.small("TAP", W - 18, y + 15, C.line, C.panel, "right") end
end

local function drawBig(W, H, big)
  local lines = rules().wrap(big, rules().BIG_WIDE)
  local step = ui.fontHeight() + 2
  local h = #lines * step + 3
  local y = floor((H - h) / 2) - 8
  ui.fill(2, y, W - 4, h, C.bg)
  ui.frame(2, y, W - 4, h, C.red)
  for i, line in ipairs(lines) do
    ui.text(line, floor(W / 2), y + 2 + (i - 1) * step, C.hi, "center", W - 6)
  end
end

--- The picture with its page's words over it, on the whole wall.
function M.draw(W, H, run, tapHint)
  local page = M.pages()[run.page]
  ui.fill(0, 0, W, H, C.bg)
  if page.pic then intro().draw({ W = W, H = H }, page.pic, page.picFrom + run.t) end
  if page.big then drawBig(W, H, page.big) end
  if page.text then drawBox(W, H, page.text, tapHint) end
end

--- What the phone panel says: this page's words.
function M.words(run)
  local page = M.pages()[run.page]
  return page.text, page.big
end

return M
