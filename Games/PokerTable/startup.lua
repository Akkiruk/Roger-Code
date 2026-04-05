local ok, updater = pcall(require, "lib.updater")
if ok and updater and type(updater.checkForUpdates) == "function" then
  pcall(function()
    updater.checkForUpdates()
  end)
end

shell.run("pokertable.lua")