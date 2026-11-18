-- Act 1, job 2: a timed delivery. The ferry crew want Juno's broth hot, and the cook, Dill, has opinions about it.
return function(api)
  api.step("pot", function()
    api.say("Mama Juno", "The night ferry crew want my broth hot. Hot, Wren. Not warm.")
    api.say("Wren", "Where's the pot?")
    api.say("Mama Juno", "Already in your boot. Ferry pier, south shore. The lid is loose, so I would not take the roundabouts like it owes you money.")
    local pick = api.choose("How do you take the job?", {
      "Hot. Understood.",
      "How hot are we talking?",
      "I will be there in a blink.",
    })
    if pick == 2 then
      api.say("Mama Juno", "Hot enough that Dill will cry and then thank you. Eighty-five seconds, from the moment you pull away.")
    elseif pick == 3 then
      api.say("Mama Juno", "Eighty-five seconds is a blink to you? Show me.")
      api.tally("juno", 1)
    else
      api.say("Mama Juno", "That is all I ask. Eighty-five seconds, and not one more.")
    end
    api.say("Mama Juno", "Go, go, go!")
  end)

  api.step("car", function()
    api.hint("Any car will do, but a quick one will do better.")
    api.anyCar("Get a car for the delivery.")
  end, { at = "juno" })

  api.step("run", function()
    api.hint("The pier is at the bottom of the map. Take the straight roads and brake before the corners, not in them.")
    api.drive("ferry", {
      text = "Get the broth to the ferry pier before it cools.",
      timer = 85, timerText = "BROTH", timerReason = "the broth went cold",
    })
  end, { at = "juno", give = { name = "car", kind = "kestrel" } })

  api.step("served", function()
    api.say("Ferry Cook", "Still steaming! Tell Juno the crew says thanks.")
    api.say("Wren", "She will be pleased. She was worried about the lid.")
    api.say("Ferry Cook", "Name's Dill. If you need a ferry, ask for the Tern. If you need a second bowl, ask for me.")
    api.say("Captain Rook", "Don't pay him any mind, lass. He sniffs everyone's delivery. It is a sickness.")
    api.say("Ferry Cook", "It is professional curiosity, Captain.")
  end, { at = "ferry" })
end
