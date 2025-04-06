-- ChunkLoaderTurtle.lua
-- Simple script to keep a turtle's chunk loaded
-- Place this file as startup.lua on a turtle to make it a permanent chunk loader

-- Function to ensure we're still running and chunk is loaded
local function keepAlive()
    while true do
        -- Move slightly up and down to ensure chunk stays loaded
        -- This minimal movement keeps the chunk loaded without consuming fuel
        turtle.up()
        os.sleep(30) -- Wait 30 seconds
        turtle.down()
        os.sleep(30) -- Wait another 30 seconds
        
        -- Print status message every minute
        term.clear()
        term.setCursorPos(1,1)
        print("Chunk Loader Active")
        print("Current position is loaded")
        print("Press Ctrl+T to stop")
    end
end

-- Main program
print("Starting Chunk Loader")
print("This turtle will keep its current chunk loaded")
print("Press Ctrl+T to stop")

-- Start the keep-alive loop
parallel.waitForAll(keepAlive)