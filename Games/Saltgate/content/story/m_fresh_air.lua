-- Act 1, job 1: Wren is out of the lockup. Juno wants wheels.
return function(api)
  api.step("meet", function()
    api.say("Mama Juno", "Wren Calloway. Three years in the Harbor lockup and you still walk like you own the street.")
    api.say("Wren", "Missed you too, Juno. You said there'd be work.")
    api.say("Mama Juno", "There is. The Gilts have been busy while you were away. They own the docks now, and the Patrol drinks their wine.")
    local pick = api.choose("What do you say?", {
      "Their wine must be terrible.",
      "Who do I have to drive?",
      "Noodles first. Work second.",
    })
    if pick == 1 then
      api.say("Mama Juno", "Awful. They pour it into a decanter so nobody can read the label.")
      api.tally("juno", 1)
    elseif pick == 2 then
      api.say("Mama Juno", "Nobody, yet. Tonight I only need to see that you can still do it.")
    else
      api.say("Mama Juno", "Ha! There she is. Sit, eat, and I will pretend I did not see you wolf it.")
      api.tally("juno", 1)
      api.tally("heart", 1)
    end
    api.say("Mama Juno", "First you need wheels. Borrow some. Bring them round to my back lot.")
    api.say("Wren", "Borrow. As in, give back?")
    api.say("Mama Juno", "As in, nobody is going to ask for it back. Probably.")
  end)

  api.step("wheels", function()
    api.hint("Walk up to any car and press E. It is not stealing if it is quick.")
    api.anyCar("Get into any car (walk up to one, press E).")
  end, { at = "juno" })

  api.step("lot", function()
    api.hint("Back lot is behind the stall. Nothing fancy. Just do not hit the lamp post.")
    api.drive("juno_lot", { text = "Drive to Juno's back lot." })
  end, { at = "juno", give = { name = "car", kind = "marlin" } })

  api.step("thanks", function()
    api.say("Mama Juno", "Not bad. Keep the car. Nobody's going to ask for it back. Probably.")
    api.say("Wren", "You keep saying probably.")
    api.say("Mama Juno", "I keep meaning it. Come by the stall tomorrow. I have a pot of broth and a pier that needs it.")
    api.text("juno", "Welcome home, Wren. Stall's open all night. Bring the car, not the attitude.")
  end, { at = "juno_lot" })
end
