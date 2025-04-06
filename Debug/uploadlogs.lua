-- upload_logs.lua
-- This script finds all .log files in the entire filesystem and uploads them to Pastebin.
-- Ensure HTTP is enabled on your ComputerCraft computer.

-- Function to recursively list all files starting from a given directory.
local function listFilesRecursively(directory)
    local files = {}
    local function scan(dir)
      for _, file in ipairs(fs.list(dir)) do
        local fullPath = fs.combine(dir, file)
        if fs.isDir(fullPath) then
          scan(fullPath)
        else
          table.insert(files, fullPath)
        end
      end
    end
    scan(directory)
    return files
  end
  
  -- Retrieve all files starting at the root directory.
  local allFiles = listFilesRecursively("/")
  
  -- Iterate through each file and upload if it ends with ".log"
  for _, file in ipairs(allFiles) do
    if file:match("%.log$") then
      print("Uploading: " .. file)
      -- The pastebin command uploads the file and prints the resulting paste URL.
      shell.run("pastebin", "put", file)
      print("Finished uploading " .. file)
    end
  end
  
  print("All .log files processed.")
  