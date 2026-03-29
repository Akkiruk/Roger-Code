local soundRoles = require("lib.sound_roles")
local reviewStore = require("lib.sound_review_store")
local recommendations = require("lib.sound_recommendations")

local ROOT = fs.getDir(shell.getRunningProgram())
local REVIEW_FILE = nil
local OUTPUT_FILE = nil
local handle = nil
local reviewData = nil
local role = nil
local items = nil
local item = nil
local index = nil

if ROOT == "" and shell.dir then
  ROOT = shell.dir()
end

REVIEW_FILE = ROOT ~= "" and fs.combine(ROOT, "sound_browser_reviews.lua") or "sound_browser_reviews.lua"
OUTPUT_FILE = ROOT ~= "" and fs.combine(ROOT, "sound_review_report.txt") or "sound_review_report.txt"

reviewData = reviewStore.load(REVIEW_FILE)
handle = fs.open(OUTPUT_FILE, "w")

if not handle then
  error("Could not open report file: " .. OUTPUT_FILE)
end

handle.writeLine("Sound Review Report")
handle.writeLine("Generated at: " .. tostring(os.epoch("local")))
handle.writeLine("Review file: " .. REVIEW_FILE)
handle.writeLine("")

for _, role in ipairs(soundRoles.LIST) do
  items = recommendations.getTopCandidates(reviewData, role.id, 5)
  handle.writeLine(role.label .. " [" .. role.id .. "]")
  handle.writeLine(role.description)

  if #items == 0 then
    handle.writeLine("  No strong candidates yet.")
  else
    index = 1
    while index <= #items do
      item = items[index]
      handle.writeLine("  " .. tostring(index) .. ". " .. item.sound_id .. " (score " .. tostring(item.score) .. ")")
      handle.writeLine("     " .. item.reason)
      index = index + 1
    end
  end

  handle.writeLine("")
end

handle.close()

print("Wrote sound review report to " .. OUTPUT_FILE)
