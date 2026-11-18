-- Act 1, job 3: Juno's crate at the dock crane, a lot of Harbor Patrol, and Rusty's cellar.
return function(api)
  api.step("brief", function()
    api.say("Mama Juno", "A crate came in on the Brine docks with my name on it.")
    api.say("Mama Juno", "The Harbor Patrol has the same idea. Get there first, then lose them.")
    api.say("Wren", "And then?")
    api.say("Mama Juno", "Then Rusty. He has a cellar nobody has ever found, and a gull that thinks he owns it.")
    local pick = api.choose("What is in the crate?", {
      "Do I get to know what is in it?",
      "Better not be fish.",
      "Never mind. Where is the crane?",
    })
    if pick == 1 then
      api.say("Mama Juno", "No. If the Patrol asks you, you will be honest when you say you do not know.")
    elseif pick == 2 then
      api.say("Mama Juno", "It is not fish. It is... adjacent to fish.")
    else
      api.say("Mama Juno", "Past the container stacks. You cannot miss it. It is very tall and very rusty.")
    end
  end)

  api.step("crate", function()
    api.hint("The crane is down at the Brine docks. Tall, rusty, impossible to miss.")
    api.goTo("crane", { text = "Pick up Juno's crate at the dock crane." })
    api.toast("The crate's tagged! Patrol on the way.", "alarm")
    api.heat(2)
    api.say("Dispatch", "All units, a Gilt-flagged crate has been moved off the Brine docks. Find the driver. Be polite. Then be firm.")
  end, { at = "juno", give = { name = "car", kind = "marlin" } })

  api.step("shake", function()
    api.hint("Cruisers pull up fast, but they corner like barges. Use the alleys.")
    api.loseHeat("Lose the Harbor Patrol.")
  end, { at = "crane", give = { name = "car", kind = "marlin" } })

  api.step("cellar", function()
    api.hint("Rusty's yard is in Cinder Flats. If the Patrol is still on you he will not open the gate.")
    api.drive("rusty", {
      text = "Take the crate to Rusty's Chop Yard.",
      noHeat = true, hotText = "Lose the Patrol first. Nobody opens up with cops on your tail.",
    })
  end, { at = "crane", give = { name = "car", kind = "marlin" } })

  api.step("cellar_talk", function()
    api.say("Rusty", "Juno's crate, Juno's runner. Tell her the cellar's still dry.")
    api.say("Wren", "You are the man with the gull.")
    api.say("Rusty", "Admiral. He is on the roof. He disapproves of you.")
    local pick = api.choose("Rusty looks you up and down.", {
      "Tell the Admiral I am not a threat.",
      "I drive. I do not do birds.",
      "What do you do with a crate like that?",
    })
    if pick == 1 then
      api.say("Rusty", "He heard you. He does not believe you. That is a good sign. He distrusts everyone worth keeping.")
      api.tally("rusty", 1)
      api.tally("heart", 1)
    elseif pick == 2 then
      api.say("Rusty", "Fair. Birds do not do you either.")
    else
      api.say("Rusty", "I put it somewhere nobody looks. That is the whole trick. Nobody ever looks.")
    end
    api.say("Rusty", "Come back when you are ready for something with a few more tyres to it.")
    api.unlock("rusty")
    api.text("rusty", "Yard. Number's saved. Don't text, just come.")
  end, { at = "rusty" })
end
