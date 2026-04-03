-- manifest-key: vhcctweaks_smoke_test
-- manifest-name: VH CC Tweaks Smoke Test
-- manifest-description: Guided proof-check for ccvault, vhcc, auth, and vault item detail enrichment.

if type(shell) == "table" and type(shell.run) == "function" then
  shell.run("vhcctweaks_smoke_test")
else
  print("Run vhcctweaks_smoke_test")
end