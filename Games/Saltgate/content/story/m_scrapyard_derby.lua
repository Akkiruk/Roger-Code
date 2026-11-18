-- Act 3, job 4: three armoured Authority trucks have rolled into Rusty's chop yard to seize his cranes. A demolition derby
-- among the stacks: ram each one to a stop. (Trucks only scrape; nobody is hurt, and the drivers hop out and run.)
return function(api)
  api.step("gate", function()
    api.say("Rusty", "Three trucks. Armoured. They rolled in at dawn. I am standing in my own yard in my own dressing gown, and I have never been so angry.")
    api.say("Wren", "Where are the trucks now?")
    api.say("Rusty", "Doing circuits. They think they are going to wear me down. They are in a yard. It is a loop. I know every inch of the loop.")
    api.say("Rusty", "Admiral is perched on the crane. He has opinions. He wants the trucks gone. I want the trucks gone.")
    local pick = api.choose("Rusty hands you the keys to a dented estate car.", {
      "A derby. In your yard. I like it.",
      "Do you have a better car than this?",
      "What happens to the trucks afterwards?",
    })
    if pick == 1 then
      api.say("Rusty", "That is exactly the kind of person who ends up in my yard. Welcome. Mind the cable drum.")
      api.tally("rusty", 1)
    elseif pick == 2 then
      api.say("Rusty", "Better? No. That is the best car I have. Do not hurt it. It is Admiral's favourite.")
    else
      api.say("Rusty", "Afterwards? Parts. Obviously. A truck is just a very large collection of other people's problems.")
      api.tally("greed", 1)
    end
  end)

  api.step("car", function()
    api.car("tidewater", "rusty_door", { name = "car", label = "estate car" })
    api.getIn("car", "Take Rusty's dented estate car.")
  end, { at = "rusty_door" })

  api.step("first", function()
    api.say("Tam", "Pit Wall to Wren! Truck one is at the north stack. It is heavy. It does not turn well. It turns even less well if you push it from the side.")
    api.ensureCar("car", "tidewater", "rusty_door", { label = "estate car" })
    api.actor("runner", "rusty", { name = "truck1", vehicle = "tidewater", route = { "scrapyard_gate", "rusty" }, flees = true, label = "truck" })
    api.hint("Hit it from the side. Aim for its rear wheel. Do not ram it head-on.")
    api.chase("truck1", { text = "Ram the first Authority truck to a stop." })
    api.say("Warden", "(jumping out) That is it! I quit! I have a pension! Not for this!")
  end, { at = "rusty_door", give = { name = "car", kind = "tidewater" } })

  api.step("second", function()
    api.say("Rusty", "One down. Two to go. Admiral is cheering. That is a screech. It means he is cheering.")
    api.ensureCar("car", "tidewater", "rusty_door", { label = "estate car" })
    api.actor("runner", "rusty", { name = "truck2", vehicle = "tidewater", route = { "scrapyard_gate", "rusty" }, flees = true, label = "truck" })
    api.hint("The second truck is faster. It will try to get out of the gate. Cut it off.")
    api.chase("truck2", { text = "Ram the second Authority truck to a stop." })
  end, { at = "rusty_door", give = { name = "car", kind = "tidewater" } })

  api.step("third", function()
    api.say("Tam", "Truck three has seen what you did to the others. It is trying to flee. It is a very large truck trying to flee. I am enjoying this.")
    api.ensureCar("car", "tidewater", "rusty_door", { label = "estate car" })
    api.actor("runner", "rusty", { name = "truck3", vehicle = "tidewater", route = { "scrapyard_gate" }, flees = true, label = "truck" })
    api.hint("Last one. It is heading for the gate. Cut across the stacks and meet it.")
    api.chase("truck3", { text = "Stop the last truck before it leaves the yard." })
  end, { at = "rusty_door", give = { name = "car", kind = "tidewater" } })

  api.step("done", function()
    api.say("Rusty", "Three trucks, no wardens, one very satisfied gull. I will remember this when I am old and dull.")
    local pick = api.choose("Rusty looks at the three dented trucks and sighs happily.", {
      "Keep the trucks. Good ballast.",
      "Give them back with a note saying thanks.",
      "Park them across the old town gate.",
    })
    if pick == 1 then
      api.say("Rusty", "Ballast! Yes! That is what I will tell the Authority when they ask for them back.")
      api.tally("greed", 1)
    elseif pick == 2 then
      api.say("Rusty", "A note. A little note. 'Thanks, we kept the fuel.' Perfect.")
      api.tally("heart", 1)
    else
      api.say("Rusty", "A barricade! A real one! Pip will be thrilled. He will paint a face on one.")
      api.remember("gate_barricaded", true)
      api.tally("juno", 1)
    end
    api.say("Rusty", "I am coming with you on Saturday. Do not argue. Someone has to hold the crane.")
    api.text("rusty", "Yard clear. Valves safe. Admiral wishes you luck. I do too, quietly.")
  end, { at = "rusty_door" })
end
