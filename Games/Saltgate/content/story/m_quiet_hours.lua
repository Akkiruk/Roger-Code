-- Act 2, job 5: the Authority motor pool is a multi-storey car park. Slip in at quiet hours, climb the levels to the roof deck,
-- knock down the guards, take the gate schedule and the fleet keys, and get out. A heist with set pieces on every deck.
return function(api)
  api.step("plan", function()
    api.say("Sable", "Welcome to my lock-up. Do not touch the gnome. Do not look at the gnome. The gnome is not part of this.")
    api.say("Sable", "The Authority motor pool: seven decks of car park behind a barrier. The fleet keys are on the roof deck, in a lockbox, in a wardens' break room.")
    api.say("Wren", "That's a lot of car park for a lockbox.")
    api.say("Sable", "It is a lot of car park for everything. Hence the heist. Roll in quiet, ramp up, knock down the guards, take the keys, ramp down loud.")
    api.say("Tam", "Pit Wall is up! I have the car park plans on my wall. It is a spiral. It is a really beautiful spiral. It will take you right to the top.")
    local pick = api.choose("Sable slides a laminated map across the bonnet.", {
      "Quiet in, loud out. I like it.",
      "What if they spot us at the barrier?",
      "Why do you want the keys?",
    })
    if pick == 1 then
      api.say("Sable", "Quiet in, loud out. Put it on a mug.")
      api.tally("sable", 1)
    elseif pick == 2 then
      api.say("Sable", "Then it gets loud sooner. We have a loud plan too. It is called the other plan.")
    else
      api.say("Sable", "The keys open the fleet gates and the schedule shows when the sea gate closes. I told you I saw the plans. I want the full picture.")
      api.tally("law", 1)
    end
  end)

  api.step("car", function()
    api.anyCar("Get a quiet car. Nothing gold. Nothing loud.")
  end, { at = "sable_garage" })

  api.step("barrier", function()
    api.hint("Do not speed. Do not hit anything. Heat at the barrier will bring the wardens out early.")
    api.drive("motor_pool", { text = "Roll up to the motor pool barrier. Quietly.", noHeat = true,
      hotText = "Too loud. Lose the heat before the barrier." })
  end, { at = "sable_garage", give = { name = "car", kind = "pipit" } })

  api.step("climb", function()
    api.say("Sable", "Barrier is up. Tam, you are a genius. Wren, spiral. Up, up, up. Do not scrape the walls, they echo.")
    api.hint("The ramp spirals up through the decks. Keep it smooth. The top deck is the roof.")
    api.ensureCar("car", "pipit", "motor_pool", { label = "car" })
    api.drive("motor_pool_top", { name = "car", text = "Spiral up to the roof deck.", radius = 3 })
  end, { at = "motor_pool", give = { name = "car", kind = "pipit" } })

  api.step("guards", function()
    api.say("Warden", "Hey! Roof deck is closed! No visitors! Authority business!")
    api.say("Wren", "I am just parking.")
    api.say("Warden", "Nobody parks up here! Get her!")
    api.say("Tam", "Pit Wall to Wren! Four wardens! They have rubber truncheons and bad attitudes! Knock them down! Nicely!")
    api.actor("crew", "motor_pool_top", { group = "wardens", count = 4, look = "warden" })
    api.hint("Walk up and punch them (G), or drive through them at speed. They get back up in a minute. Be quick.")
    api.defeat("wardens", { text = "Knock the wardens down." })
    api.say("Sable", "Four little wardens, all in a row. See stars. Oh, there they are.")
  end, { at = "motor_pool_top", give = { name = "car", kind = "pipit" } })

  api.step("keys", function()
    api.say("Tam", "Lockbox is behind the break room door. I will pop it. Hold position for six seconds. Please do not fidget.")
    api.hold("motor_pool_top", 6, { text = "Hold at the lockbox while Tam opens it.", away = "Get back to the lockbox!", radius = 3 })
    api.toast("Sirens! The wardens called it in!", "alarm")
    api.heat(3)
    api.say("Tam", "Got it! Keys, schedule and a flask of tea. I am keeping the flask. Go go go!")
  end, { at = "motor_pool_top", give = { name = "car", kind = "pipit" } })

  api.step("out", function()
    api.hint("Down the spiral, fast. They will try to block the ramp below. Find the gap.")
    api.loseHeat("Get out of the motor pool and lose the wardens.")
  end, { at = "motor_pool_top", give = { name = "car", kind = "pipit" } })

  api.step("read", function()
    api.say("Tam", "Right. The schedule. I have scanned it. Every year the sea gate closes for the 'King Tide' test. This year, the test is real.")
    api.say("Sable", "Real how?")
    api.say("Tam", "Gates shut at high water. Everything inside the wall is safe. Everything outside is... managed. Look at the map. Old Saltgate is outside.")
    api.say("Wren", "That's Juno's street. Pip's street. Rusty's yard.")
    api.say("Sable", "And your three years in the lockup were to keep you out of the way of this. I wish I could say I was surprised.")
    local pick = api.choose("The keys are on the table. Three faces look at you.", {
      "We tell Juno. Now.",
      "Not yet. We need more than a map.",
      "We tell everyone. Ferris, put it on air.",
    })
    if pick == 1 then
      api.say("Sable", "Right. And if she already knows?")
      api.say("Wren", "Then I want to see her face when I ask.")
      api.remember("told_juno_first", true)
      api.tally("juno", 1)
    elseif pick == 2 then
      api.say("Sable", "Good. A map is a rumour. A key is a fact. Keep the keys.")
      api.tally("law", 1)
    else
      api.say("Tam", "Ferris is going to faint. Do not tell him in the car.")
      api.remember("told_ferris", true)
      api.tally("heart", 1)
    end
    api.text("sable", "Keys in my pocket, guards asleep. You are welcome.")
  end, { at = "sable_garage" })
end
