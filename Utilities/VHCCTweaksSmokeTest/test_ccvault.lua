if type(shell) == "table" and type(shell.run) == "function" then
  shell.run("vhcctweaks_smoke_test")
else
  print("Run vhcctweaks_smoke_test")
end