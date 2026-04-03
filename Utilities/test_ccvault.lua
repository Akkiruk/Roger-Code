-- test_ccvault.lua -- compatibility launcher for the guided vhcctweaks smoke test

if type(shell) == "table" and type(shell.run) == "function" then
  print("Launching the guided vhcctweaks smoke test...")
  shell.run("test_ccvault_full")
else
  print("Run test_ccvault_full")
end
