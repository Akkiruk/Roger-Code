-- Act 2, job 6: a freight train, a level crossing, and a lot of crates in a hurry. Rusty needs the valves off the freight
-- before the Authority impounds the whole train. Race it to the crossing, hold while the crates go over, run.
return function(api)
  api.step("yard", function()
    api.say("Rusty", "Freight. Cinder yard. Forty wagons of pressure valves and one of pumps. The Authority will seize the lot at the junction.")
    api.say("Wren", "What do you want with forty wagons of valves?")
    api.say("Rusty", "Not forty. Two crates. Sluice valves. The gate has them. If you want to stop the gate, you want the valves.")
    api.say("Wren", "That is the longest thing I have ever heard you say.")
    api.say("Rusty", "Admiral is on my shoulder. He makes me eloquent.")
    local pick = api.choose("The Admiral eyes you. He has one eye. It is judgemental.", {
      "Where does the train cross?",
      "I did not know you had a plan.",
      "Admiral, you ought to be on the payroll.",
    })
    if pick == 1 then
      api.say("Rusty", "Cinder crossing, west of the yard. Forty seconds ahead of the train if you take the service road. Thirty if you do not stop.")
    elseif pick == 2 then
      api.say("Rusty", "I did not. Then I looked at the schedule and thought: I could be useful. Terrible feeling.")
      api.tally("rusty", 1)
    else
      api.say("Rusty", "He is. I pay him in chips. It is a fair wage.")
      api.tally("heart", 1)
    end
  end)

  api.step("wheels", function()
    api.anyCar("Get a car. The train will not wait.")
  end, { at = "rusty_door" })

  api.step("race", function()
    api.say("Tam", "Pit Wall! Train is rolling. It has left the yard. You have a service road and a dream. Go!")
    api.hint("The service road runs beside the rails. Stay on it and do not brake for the bumps.")
    api.drive("crossing", { text = "Beat the freight to the level crossing!", timer = 45, timerText = "TRAIN",
      timerReason = "the train got there first" })
  end, { at = "rusty_door", give = { name = "car", kind = "marlin" } })

  api.step("load", function()
    api.say("Rusty", "Here it comes. Hold the crossing! I will wave the wagons. When I say, the crates go over.")
    api.hold("crossing", 8, { text = "Hold the crossing while the crates go over.", away = "Get back on the crossing!", radius = 3 })
    api.toast("The Authority is on the track!", "alarm")
    api.heat(2)
    api.say("Rusty", "That is two crates. Valves. Go! They are on the train and they are very angry!")
  end, { at = "crossing", give = { name = "car", kind = "marlin" } })

  api.step("escape", function()
    api.hint("Cut across the yard. Cruisers corner like barges. Use the narrow gaps between the stacks.")
    api.loseHeat("Lose the Authority's cars.")
    api.drive("rusty", { text = "Bring the valves to Rusty's yard.", noHeat = true, hotText = "Lose them first. Rusty will not open for a tail." })
  end, { at = "crossing", give = { name = "car", kind = "marlin" } })

  api.step("done", function()
    api.say("Rusty", "Valves. Two crates. I could kiss you. I will not. Admiral, say thank you.")
    api.say("Wren", "He is not saying anything.")
    api.say("Rusty", "That is how he says thank you.")
    api.remember("have_valves", true)
    api.text("rusty", "Yard. Valves safe. Come back if you want to see what we do with them.")
  end, { at = "rusty_door" })
end
