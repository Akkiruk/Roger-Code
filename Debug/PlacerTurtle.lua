-- PlacerTurtle.lua
-- Interactive turtle script that places items in user-specified directions

local function printDirections()
    term.clear()
    term.setCursorPos(1,1)
    print("=== Turtle Item Placer ===")
    print("Commands:")
    print("- up")
    print("- down")
    print("- left")
    print("- right")
    print("- front")
    print("- back")
    print("- exit (to quit)")
    print("=====================")
    print("Enter direction: ")
end

local function placeInDirection(direction)
    -- Save current orientation
    local success = false
    
    if direction == "up" then
        success = turtle.placeUp()
    elseif direction == "down" then
        success = turtle.placeDown()
    elseif direction == "front" then
        success = turtle.place()
    elseif direction == "back" then
        turtle.turnRight()
        turtle.turnRight()
        success = turtle.place()
        turtle.turnRight()
        turtle.turnRight()
    elseif direction == "left" then
        turtle.turnLeft()
        success = turtle.place()
        turtle.turnRight()
    elseif direction == "right" then
        turtle.turnRight()
        success = turtle.place()
        turtle.turnLeft()
    end
    
    if success then
        print("Successfully placed item!")
    else
        print("Failed to place item. Make sure:")
        print("1. There's an item in the selected slot")
        print("2. There's space to place the item")
    end
    os.sleep(2)
end

-- Main program loop
while true do
    printDirections()
    local input = read():lower()
    
    if input == "exit" then
        print("Goodbye!")
        break
    elseif input == "up" or input == "down" or 
           input == "left" or input == "right" or 
           input == "front" or input == "back" then
        placeInDirection(input)
    else
        print("Invalid direction!")
        os.sleep(1)
    end
end