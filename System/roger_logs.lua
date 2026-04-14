-- Universal Roger-Code log bundle command.
-- Collects local logs into one or more text bundles and uploads them with pastebin.

local logging = require("lib.roger_logging")

local function printUsage()
  print("Usage:")
  print("  rogerlogs          Build bundles and upload them to pastebin")
  print("  rogerlogs local    Build bundles only and print the local files")
  print("  rogerlogs help     Show this help")
end

local function printBundleList(parts)
  print("")
  print("Generated bundle files:")
  for _, part in ipairs(parts) do
    print("- " .. tostring(part.path) .. " (" .. tostring(part.size) .. " bytes)")
  end
end

local mode = ({ ... })[1] or "upload"

if mode == "help" or mode == "--help" or mode == "-h" then
  printUsage()
  return
end

local parts, metaOrErr = logging.collectBundle({})
if not parts then
  printError("Failed to collect logs: " .. tostring(metaOrErr))
  return
end

print("Roger-Code log bundle complete.")
print("Included files: " .. tostring(#(metaOrErr.files or {})))
printBundleList(parts)

if mode == "local" or mode == "bundle" then
  print("")
  print("Local-only mode: no uploads attempted.")
  return
end

local results, uploadErr = logging.uploadBundle(parts)
if not results then
  print("")
  printError("Pastebin upload failed: " .. tostring(uploadErr))
  print("The bundle files are still available locally.")
  return
end

print("")
print("Pastebin upload complete.")
print("Copy the URLs or codes printed above into chat for debugging.")