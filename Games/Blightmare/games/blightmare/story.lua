-- games/blightmare/story.lua
-- Every word of the slice, draft for the author to edit. A script is a list of steps run by the engine in rules.lua. The
-- first option of a choice should be the one that moves the story on: the test bot always takes it.
-- The hero speaks only in the handful of lines marked hero(). The deserter, cleric and owlin have no names yet, so people
-- call them what they are: "doctor" and "sister". The names over their portraits come from party.CHARS.
-- People who aren't in the portrait list borrow a portrait and give their own name, as nan() and wick() do.

local M = {}

M.START = "start"
M.SHOPS = {}
M.SCRIPTS = {}

local S = M.SCRIPTS

-- ---------------------------------------------------------------- who says what

local function t(text) return { text = text } end
local function hero(text) return { say = "hero", text = text } end
local function deserter(text) return { say = "deserter", text = text } end
local function cleric(text) return { say = "cleric", text = text } end
local function doctor(text) return { say = "doctor", text = text } end
local function captain(text) return { say = "captain", text = text } end
local function mayor(text) return { say = "mayor", text = text } end
local function smith(text) return { say = "smith", text = text } end
local function innkeeper(text) return { say = "innkeeper", text = text } end
local function foreman(text) return { say = "foreman", text = text } end
local function gnome(text) return { say = "gnome", text = text } end
local function child(text) return { say = "child", text = text } end
local function pip(text) return { say = "child", name = "PIP", text = text } end
local function nan(text) return { say = "villager", name = "NAN", text = text } end
local function wick(text) return { say = "villager", name = "WICK", text = text } end
local function clerk(text) return { say = "villager", name = "CLERK", text = text } end
local function soldier(text) return { say = "captain", name = "SOLDIER", text = text } end
local function orderly(text) return { say = "doctor", name = "ORDERLY", text = text } end
local function villager(text) return { say = "villager", text = text } end
local function bogg(text) return { say = "villager", name = "GENTLEMAN BOGG", text = text } end
local function nib(text) return { say = "gnome", name = "NIB", text = text } end
local function nob(text) return { say = "gnome", name = "NOB", text = text } end

-- ---------------------------------------------------------------- morning in Scythebreak

S.start = {
  { warp = { "scythebreak", 3, 3, 2 } },
  t("There is a place people go, just before they wake."),
  t("You have heard all about it. Colours. Falling. All your teeth. A dead uncle asking after the horse."),
  t("You open your eyes. It is morning. There was nothing before it. There never is."),
  nan("Up, {hero}! Bell's gone and the porridge has started to set."),
  nan("Well? What did you dream?"),
  { choice = {
    { "Nothing.", {
      nan("Nothing. All these years under my roof and not one decent nightmare to share at breakfast."),
    } },
    { "A dead uncle asked after the horse.", {
      nan("You've no uncle and we've no horse. You got that from the Hanley boy. You can't even lie about it properly."),
    } },
  } },
  nan("Two jobs, and then you're your own. Sign the Dream Book in the square before the clerk turns sour."),
  nan("Then take this loaf down to the lad on the wall-watch. He's too thin, and I've decided that's my problem."),
}

S.talk_nan = {
  { when = "bread_done", steps = {
    nan("That's my good one. Go on and play, or whatever it is you do now you're too big for it."),
  }, other = {
    { when = "signed", steps = {
      nan("The loaf, {hero}. The wall-watch. West end of the high street, you can't miss it. It's the wall."),
    }, other = {
      nan("The Book first. A dream undeclared is a fine, and a second is a visit, and I'll not have a visit."),
      nan("You came over on the last cart out of Evrastin, you know. Babe in a crate. Slept through the end of the world."),
      nan("I'd like you to keep sleeping well. So go and sign."),
    } },
  } },
}

S.talk_wick = {
  wick("Morning, {hero}. Grand day. Slept like a stone. Like a big, sleeping stone."),
  wick("Why, what've you heard? Nobody's said anything? Good. Nothing to say."),
  t("Wick the lamplighter is holding his pole in both hands. It's broad daylight."),
}

S.talk_kid = {
  child("I'm the doctor and you're sick. Say ah."),
  child("Now you're dead. I'm sorry. It's for the good of the town."),
  child("{hero}? What's nothing like? Nan says that's what you dream."),
  child("Is it black? Is it like when you shut your eyes? I asked a soldier and he wrote my name down."),
}

S.talk_clerk = {
  { when = "signed", steps = {
    clerk("You've signed. Don't loiter by the Book. People will think you remembered something."),
  }, other = {
    clerk("Next. Name, and anything to declare from the night. {hero}. Why do I ask."),
    clerk("'Nothing.' I'll write it for you, shall I? I've a very good hand for it by now."),
    t("You sign. The page above is yours, and the page above that. Nothing, nothing, nothing, in your own writing, back and back."),
    clerk("You know, in all my years with this Book you're the one person who has never lied to me."),
    clerk("Either that, or you're the only one who always has. Off you go."),
    { set = "signed" },
  } },
}

S.talk_gossip = {
  villager("They built that wall to keep something in. That's what they tell you."),
  villager("Sixty feet of stone, and they still come round and look under my bed."),
  villager("Wick's been up all hours, I've seen his lamp. I didn't say that. You didn't hear it."),
}

S.talk_widow = {
  villager("My Tobin put down a dream in that Book, once. Only a small one. He said he was a fish."),
  villager("They sent someone round. Very polite. They took him for one night of observation."),
  villager("That's nine years, now. They wrote to say he was doing well."),
}

S.talk_corner = {
  { when = "lockdown", steps = {
    soldier("Clinic house. Join the queue. Nobody is in trouble. Keep walking."),
  }, other = {
    soldier("Move along. Nothing to see. That's rather the point of the wall."),
  } },
}

S.talk_doorman = {
  soldier("Clinic house is for Clinic business. You'll know when it's your business. They'll fetch you."),
}

S.talk_gateman = {
  orderly("Good morning. The gate is for people with a pass. Passes are for people with a reason."),
  orderly("Is it a good reason? They're never good reasons. Have a pleasant day."),
}

S.talk_watch = {
  { when = "breach", steps = {
    soldier("Go on! Don't stop for anything! Don't let anything touch you!"),
  }, other = {
    { when = "signed", steps = {
      soldier("Is that bread? Is that Nan's bread? Don't tell the sergeant, he'll want to inspect it. With his mouth."),
      t("Behind him the wall goes up and up. It takes a while to find the top. You've stopped noticing that, mostly."),
      soldier("Do you hear something? Like a... like somebody breathing in, and not stopping."),
      { set = "bread_done" },
      { set = "horn" },
      { sfx = "horn" },
      t("The loaf is still warm when the horn starts."),
      soldier("That's not the drill horn."),
      t("At the foot of the wall there's a crack you've walked past every day of your life. It is getting wider. Something is coming out of it, in instalments."),
      { big = "THE WALL IS OPEN" },
      soldier("Get behind me! Get BEHIND me! Oh, gods, it's... I've dropped my... you'll have to..."),
      { battle = "tut_crawler" },
      t("It stops moving. It takes some time to stop all of it."),
      soldier("You killed it. With a kitchen knife."),
      soldier("Don't touch it. Don't breathe near it. Go home, {hero}, go on, go!"),
      { set = "breach" },
    }, other = {
      soldier("Morning, {hero}. Book first. Sergeant won't have me taking so much as a crust from anyone who hasn't signed."),
    } },
  } },
}

-- ---------------------------------------------------------------- the breach

S.scene_wick = {
  t("Wick is standing in the middle of the street with his lamp-pole, quite still."),
  wick("{hero}. Don't tell the Book."),
  wick("I had one. Night before last. First in years. Only a small one."),
  wick("It's still going."),
  t("His shadow has stopped doing what he does."),
  wick("It's looking at you. It looked right at you and it... no. Why doesn't it want you?"),
  wick("It wants everyone. Why doesn't it want you?"),
  { battle = "wall_breach" },
  { set = "wick_down" },
  t("The lamp-pole rolls a little way along the street and stops."),
  t("What's left doesn't stay to be looked at for long. Soldiers are already there with a sheet. They seem to have had it ready."),
  captain("You. Stand still. Did it touch you? Did you touch it? Think before you answer. I'll know."),
  captain("Hm. Let them through."),
  { sfx = "horn" },
  captain("By order of the Clinic, Scythebreak is closed. Every resident to the Clinic house for testing, now."),
  captain("There is no need to be afraid. There is also no need to run. We've thought of that."),
  { set = "lockdown" },
}

S.talk_q_nan = {
  nan("There you are. Stand with me. Oh, you've blood on you. Whose is that? Don't tell me."),
  nan("It's only a test. We've had them before. You drink it, you sleep it off, you complain."),
  nan("You'll be fine, {hero}. You always are."),
}

S.talk_q_clerk = {
  clerk("Twenty-two years I've kept that Book. Do you know, they didn't let me bring it?"),
}

S.talk_q_kid = {
  child("Is Wick sick? I said hello to him and he said hello back, but not from where he was."),
}

S.talk_q_gossip = {
  villager("I always said. Didn't I always say? I don't know what I said. I want to go home."),
}

S.scene_test = {
  t("The hall smells of lavender and boiled linen. Someone has set out chairs. Someone has given thought to the chairs."),
  doctor("Come in. Sit down. You've had a frightening morning. Would you like some water?"),
  doctor("I'm the doctor. That's all you need to call me. This is a draught, and it will give you one night of very bad dreams."),
  doctor("If there is anything in you, we will see it by morning. If there is nothing in you, you've lost a night's rest, and I shall apologise in person."),
  doctor("Everyone takes it. Your neighbours have all been very good."),
  { choice = {
    { "Drink it.", {
      t("It tastes of pennies."),
    } },
    { "Refuse.", {
      doctor("Of course. You may refuse. It's on the form."),
      doctor("The form says you will then be held down and given it. But you may refuse. I want you to feel that you've been heard."),
      t("It tastes of pennies."),
    } },
  } },
  { fade = true },
  t("You sleep. You wake. There was nothing before it. There never is."),
  t("The rest of Scythebreak does not wake so well."),
  t("It comes through the walls of the ward, from every bed at once. Nobody is screaming. It's much quieter than that."),
  { warp = { "scythebreak", 17, 3, 3 } },
  doctor("Good morning, {hero}. How did you sleep?"),
  doctor("And what did you see?"),
  hero("Nothing."),
  t("The pen stops."),
  doctor("Take your time. There's no wrong answer. Would you like some water?"),
  hero("Nothing. I never do."),
  captain("Every bed in that ward, doctor. My own men. Children. And this one is asking what's for breakfast."),
  doctor("Yes. Isn't it wonderful?"),
  doctor("Captain, this is a clean result. Do you understand? There has never been a clean result."),
  captain("What do you want done?"),
  doctor("A closed cart for Adaphis, at first light. Doctor Colette will want to see this one herself."),
  doctor("You've done nothing wrong, {hero}. Do remember that. It won't help, but it's true."),
  { warp = { "scythebreak", 22, 3, 3 } },
  { fade = true },
  { set = "tested" },
  t("Night. A bed, a bucket and a very clean floor."),
  t("Through the wall a whole town is breathing, all together, in time."),
  t("Someone is working at the lock. Badly."),
  deserter("Hold still. I mean, I'm the one who... this is a delicate instrument."),
  { sfx = "door" },
  deserter("It's a spoon."),
  t("The door opens on a Clinic coat with the badge cut off. Above it is a long scar, and a face that has been awake for about a year."),
  deserter("Quietly, friend. I'm from the Clinic. I'm also leaving it. As of roughly now."),
  deserter("At first light they put you in a closed cart. I've walked beside those carts. Eleven times."),
  deserter("Do you know what comes back from Adaphis? The cart. It comes back very clean."),
  deserter("The orderlies on this ward have had the soup. I made the soup. They'll wake up at noon feeling dreadful, and I'm at peace with that."),
  { choice = {
    { "Why are you doing this?", {
      deserter("Because I've written the word 'clean' on a great many forms, and you're the first time it was true."),
    } },
    { "What about the others? What about Nan?", {
      deserter("They told us at the college that the draught only shows what's already there."),
      deserter("They told us a lot of things at the college. Nothing I can do in that ward tonight. Something I can do about you."),
    } },
  } },
  deserter("The ward's on the way to the front door. Don't stop long. Then the square, then Gate Street, and try to look like someone who's being discharged."),
  { join = "deserter", lvl = 2 },
  { set = "escaped" },
  { warp = { "scythebreak", 22, 5, 3 } },
  { save = true },
}

S.ward_nan = {
  { when = "said_goodbye", steps = {
    t("She doesn't wake again. Her hands go on kneading."),
    deserter("She's still in there. I know that isn't a comfort. We should go."),
  }, other = {
    t("Nan is lying very straight, which she has never done. Her hands are moving a little on the blanket, as if there were dough."),
    nan("{hero}? Is that you? Have you eaten?"),
    nan("I had a dream, love. Imagine. At my age."),
    nan("It was so big. It's still... what did you dream?"),
    hero("Nothing, Nan."),
    nan("Good. That's my good one. You keep it that way."),
    nan("Go on, now. Before the porridge sets."),
    { set = "said_goodbye" },
  } },
}

S.ward_kid = {
  t("The child is humming, with both eyes shut. Someone is humming along. You're the only two awake in this row."),
}

S.ward_clerk = {
  t("The clerk's right hand writes on the sheet, over and over, with no pen. The same short word. It isn't 'nothing'."),
}

S.ward_watch = {
  t("The lad from the wall-watch. There's still a heel of Nan's loaf in his fist. Nobody has been able to get it out."),
}

S.ward_bed = {
  deserter("That was to be yours, in the morning, for the form. Every patient gets a bed. Then you'd have been a transfer."),
}

S.scene_night_street = {
  t("The town is dark for the first time in your life. Nobody has lit the lamps. Nobody is left who does."),
  t("Each door has been marked in chalk with a neat tally. Nan's will have one too."),
  { set = "night_seen" },
}

S.scene_gate = {
  t("Two orderlies stand at the gate, with a lantern. Neither of them has had the soup."),
  orderly("Evening, doctor. You're not on the sheet."),
  deserter("No. I've taken myself off it."),
  orderly("Is that the patient? Step away from the patient, please. There's no need for this to be unpleasant."),
  deserter("There never is. That's what's wrong with it."),
  { battle = "gate_orderlies" },
  { set = "gate_won" },
  { warp = { "scythebreak", 23, 11, 2 } },
  { save = true },
  t("The gate stands open. Behind you no horn sounds. Nobody is running. Somewhere, you suspect, a pen is writing this down."),
  deserter("North-east, up the road. Orrenshire, against the mountains. Gnomes, mostly. The Clinic keeps one bored clerk there and a drawer of unanswered letters."),
  deserter("It's the last place anyone will look, because looking would mean reading the letters."),
  deserter("And friend. When we get there, I'm a herbalist. Don't call me doctor unless you have to. I'm trying to give it up."),
  { set = "left_town" },
  { world = { 62, 60 } },
}

S.turned_back = {
  t("Clinic lamps at every corner, and chalk on every door. There's no one left here to come back for. Not yet."),
  { world = { 62, 60 } },
}

S.gate_greywater = {
  t("The Greywater bridge is barred, with a Clinic lamp at each end."),
  { when = "escaped", steps = {
    deserter("Not that way. That road goes to Oplinas, and Oplinas is theirs. North to Orrenshire, friend."),
  } },
}

-- ---------------------------------------------------------------- Orrenshire

S.scene_orrenshire = {
  t("Orrenshire is built into the foot of the mountain, and all of it is slightly too small. The doors come up to your chest. Every lamp in town is lit. It's the middle of the day."),
  gnome("Halt! State your name, your business, your height, and whether you've been asleep!"),
  deserter("Is that a trick question?"),
  gnome("It's Ordinance Forty! Anyone found asleep in Orrenshire shall be shouted at, kindly, until they stop!"),
  deserter("How long since anyone here went to bed?"),
  gnome("Nine days! New town record! The Mayor is making a speech about it! She started on Tuesday!"),
  deserter("Nobody stays awake nine days for fun. Friend, I think we'd better hear that speech. East side of the square."),
  { set = "arrived" },
}

S.talk_mayor = {
  { when = "finished", steps = {
    t("The Mayor is asleep at her desk, on a motion of her own. Someone has put a coat over her. It's a very small coat."),
  }, other = {
    { when = "foreman_down", steps = {
      mayor("They're coming up! Twenty-nine of them, on their own feet, and most of them know their names! Oh, I'll want that in the minutes."),
      t("The doctor puts the paper on her desk. She reads it twice, standing on a box."),
      mayor("It's a form. I knew it. I wrote eleven letters, and all along it was a form."),
      mayor("They'll come for us when they hear, won't they?"),
      deserter("They'll come with a kind voice and a clean cot. So burn the casks, and keep your letters short."),
      mayor("And you? There's a bounty on a tall one and a herbalist, or there will be by Friday. Don't think we can't read."),
      cleric("We need to learn whose hand was on that seal. That takes us somewhere other than here."),
      mayor("Then the town of Orrenshire offers you its thanks, carried unanimously, and this. It's all the coin there is."),
      { gold = 200 },
      mayor("There's one more item. Motion to go to bed. All in favour?"),
      t("It carries in about four seconds."),
      { fade = true },
      t("All over Orrenshire the lamps go out, one street at a time, for the first time in twenty-one days."),
      t("Somebody is snoring. Somebody shouts at them, kindly, and then forgets to go on."),
      deserter("Listen to that. Worst sound in the world, and I could listen to it all night."),
      cleric("Go to sleep, both of you. I'll sit up with them."),
      t("You lie down. You know what happens next. Nothing does."),
      { fade = true },
      t("Far to the north-east, in Adaphis, a high room in the Cranial District. One lamp."),
      t("On the desk, a clerk's report. SCYTHEBREAK. CLEAN RESULT: ONE. SUBJECT ABSENT."),
      t("Beside it, an old book lies open at a place where pages have been torn out. A woman in a physician's grey reads the report through to the end, and then reads one word of it for a long time."),
      t('"Everyone dreams," says Doctor Colette, to no one. "They simply haven\'t been asked properly."'),
      t("Her hand moves to the book, the way a hand moves to an old wound."),
      { fade = true },
      { set = "finished" },
      { fin = true },
    }, other = {
      { when = "mine_pass", steps = {
        mayor("Bottom of the mine, tall ones. The road east out of town and the first big hole. Chit's in your hand."),
        mayor("And if you don't meet anyone on the first level, because there's nobody there, tell her we're out of bandages."),
      }, other = {
        mayor("...and in CONCLUSION, which I have now reached twice... oh! Visitors! Tall ones! Ottilie Brasscap, Mayor. Sixty years unopposed."),
        mayor("You'll forgive the lamps. We have a small difficulty. We have a mine. We had a deep shift in it, forty gnomes."),
        mayor("Twelve days ago they stopped sending up coal. Then the second-level men started coming up with a look on them."),
        mayor("They'd drop off, you see, and they'd wake up wrong. Or they wouldn't. And then whoever was sat next to them would have a bad night too."),
        mayor("So we stopped. Sleeping. As a town. It went to a vote. Carried, with one abstention, and he's in the ward."),
        deserter("Did you send to the Clinic?"),
        mayor("Eleven letters. They sent back a form asking how many of us there are. Very interested in the number. No doctor."),
        mayor("I've no right to ask, but you've the look of people with nowhere better to be. Somebody has to go down there and see."),
        mayor("Here's a chit for the warden at the pit. It says you're authorised. It also says you're responsible."),
        mayor("Now, there's no cleric down there. I want that clearly understood. The Clinic hangs people for it. Nobody is treating anybody on the first level."),
        t("The Mayor winks. It takes her a moment to get the eye open again."),
        { set = "mine_pass" },
      } },
    } },
  } },
}

S.talk_innkeeper = {
  { when = "finished", steps = {
    t("The innkeeper is asleep on the stairs, smiling, with a key in each hand."),
  }, other = {
    innkeeper("Welcome to the Feather and Pick! Forty beds, best in the Heart, and I've not had a soul in one for nine days."),
    { when = "first_night", steps = {
      innkeeper("Twenty gold a bed. I look the other way, and you never saw me."),
      { choice = {
        { "Stay the night (20 gold).", {
          { inn = 20 },
          { save = true },
        } },
        { "Buy from the kitchen stores.", {
          { shop = "orrenshire_goods" },
        } },
        { "Not now.", {} },
      } },
    }, other = {
      innkeeper("Ordinance Forty's for residents. You're visitors. First night's on the house, just so I can watch someone do it."),
      { fade = true },
      { heal = true },
      { save = true },
      t("You sleep. There is nothing. Then there is morning."),
      deserter("You didn't move all night. I checked. Old habit."),
      deserter("I've sat up with thousands of sleepers. They twitch. They mutter. Their eyes go back and forth. You just stop, friend. Like a clock."),
      deserter("Probably nothing."),
      { set = "first_night" },
    } },
  } },
}

S.talk_dozer = {
  { when = "finished", steps = {
    t("Sound asleep, with one shoe on. Nobody shouts."),
  }, other = {
    gnome("I'm not asleep. I'm resting my face. This is the bed inspection. Somebody has to inspect them."),
    gnome("Very soft. Very... MY NAME IS ALWIN AND IT IS THURSDAY!"),
    gnome("Sorry. That's a technique."),
  } },
}

S.talk_smith = {
  { when = "finished", steps = {
    t("The forge has gone out for the first time in living memory. The smith is asleep against the anvil, in a beard like a bolster."),
  }, other = {
    smith("Forged in the mountain and tested on my brother-in-law. What do you need?"),
    smith("Nine days without sleep, I'm doing the best work of my life. Don't touch that one. It's a sword with two handles and no blade. It's art."),
    { shop = "orrenshire" },
  } },
}

S.talk_apprentice = {
  gnome("She's made eleven left boots since Sunday. I've stopped mentioning it."),
}

S.talk_chair = {
  { when = "foreman_down", steps = {
    gnome("The Committee for Staying Awake is pleased to announce that it has met its goals and is dissolving itself. I may have a small lie down. On the mallet."),
  }, other = {
    gnome("Welcome to the Committee for Staying Awake! I am the Chair. I'd offer you a chair, but that's how it starts."),
    gnome("Behold the Wakefulness Engine! Every ninety seconds a small mallet strikes the operator on the head."),
    gnome("It has struck me eleven thousand times. I've never felt more... there's a word. There's a word for how I am."),
    { when = "mallet_tried", steps = {
      gnome("Back for another go? No? Very wise. Very... was it Tuesday?"),
    }, other = {
      { choice = {
        { "Try the Wakefulness Engine.", {
          { sfx = "hit" },
          t("It's a very small mallet. It is not a very small pain."),
          gnome("Excellent! You look terrible! That's a Committee record for a visitor!"),
          { give = "tonic", n = 1 },
          gnome("Have a tonic. It's mostly chicory and fear."),
          { set = "mallet_tried" },
        } },
        { "No, thank you.", {
          gnome("Coward. Oh, I'm sorry. That's the mallet talking."),
        } },
      } },
    } },
  } },
}

S.talk_ledger = {
  { when = "finished", steps = {
    t("The ledger gnome is asleep on the ledger. The ink has made a small map on one cheek. You leave a note of your own."),
    { save = true },
  }, other = {
    gnome("Sign the visitors' ledger? It's a comfort to know somebody wrote you down. It's how we found out we'd lost the deep shift."),
    { choice = {
      { "Sign the ledger.", {
        { save = true },
        gnome("Noted. If you should die, we'll know where to send the bill."),
      } },
      { "Not now.", {} },
    } },
  } },
}

S.talk_frog = {
  { when = "frog_wet", steps = {
    bogg("Ahhh. A new frog. A happier frog. I shan't forget you, tall one. I forget most things, but I keep a list."),
  }, other = {
    { when = "frog_bucket", steps = {
      t("You upend the bucket over the head in the stocks. It closes its enormous eyes."),
      bogg("Oh, that's the stuff. That's the good mud-water. There's a bit of a newt in that."),
      bogg("Honour among redistributors. Left boot. No, MY left boot. There."),
      t("From somewhere in his left boot he produces a small glass ether, slightly warm."),
      { give = "ether", n = 1 },
      bogg("I took that off a wizard in Hayford. It's yours. Which makes you a receiver of stolen goods. Welcome to the profession."),
      { set = "frog_wet" },
    }, other = {
      t("A frog folk, a large one, stands in the town stocks with his chin on the plank. He wears a very good hat that doesn't fit."),
      bogg("Psst. Tall one. Gentleman Bogg, of the Hayford Swamp. Don't let the stocks deceive you, I'm here for the company."),
      bogg("They found me on the road with eleven sacks of barley, a duck, and the hat of the Mayor of Hayford. I want you to know that I can explain two of those."),
      bogg("I am what you'd call a redistributor. I redistribute things to me."),
      bogg("Here's my trouble. A frog must stay damp, and nobody in this town can lift a bucket any more. I'm going crisp. Fetch me one from the well, there's a tall fellow."),
      { set = "frog_met" },
    } },
  } },
}

S.talk_stocks = {
  gnome("He was right here. The stocks are still locked. I've checked them. I've checked them several times."),
  gnome("My hat's gone too. And the plank."),
}

S.talk_well = {
  { when = "finished", steps = {
    t("Asleep, sitting up, with one arm around the well like an old friend."),
  }, other = {
    { when = "frog_met", steps = {
      { when = "frog_bucket", steps = {
        gnome("I'd go easy. Water's got a newt in it. Had a newt. Has he got the newt?"),
      }, other = {
        gnome("For the frog? He owes me a duck. Go on, then, I can't lift it. I tried on Monday. I was very brave."),
        t("You haul up a full bucket. It weighs about as much as the gnome."),
        { set = "frog_bucket" },
      } },
    }, other = {
      gnome("I dropped off on the windlass yesterday, one second, and shouted at myself. Very firm. I felt quite let down."),
    } },
  } },
}

S.talk_shopkeep = {
  { when = "finished", steps = {
    t("The shop's door is propped open. A note on the counter reads BACK WHEN I FEEL LIKE IT. There's a jar for coins."),
    { shop = "orrenshire_goods" },
  }, other = {
    gnome("Potions, ethers, tonics. All very reasonable. Tonic's gone up, everyone's been drinking it to stay awake. The side effect is that you stay awake."),
    { shop = "orrenshire_goods" },
  } },
}

S.talk_pip = {
  { when = "pip_done", steps = {
    pip("Mum's asleep. She's snoring. It's the best thing I ever heard. I'm going to go and watch her do it."),
  }, other = {
    { when = "foreman_down", steps = {
      { when = "have_lamp", steps = {
        pip("That's her lamp! That's the green stripe! She came up, she came up on the lift, she's asking who has her lamp!"),
        pip("She said she dreamed she was walking down and down. And somebody came through and stopped it."),
        pip("Here. It's my best thing. It's a very good stone."),
        { give = "potion", n = 2 },
        t("It's two potions, and a very good stone."),
        { set = "pip_done" },
      }, other = {
        pip("She came up! She came up on the lift! She keeps asking who has her lamp. It's got a green stripe."),
      } },
    }, other = {
      { when = "lamp_ask", steps = {
        pip("It's got a green stripe. She painted it herself, so that nobody would take it by accident."),
      }, other = {
        pip("My mum's on the deep shift. The Mayor says they've just gone on a long one."),
        pip("I'm six. I'm not stupid."),
        pip("If you go down, her lamp has a green stripe. If you see it. You don't have to bring her. Only if you see it."),
        { set = "lamp_ask" },
      } },
    } },
  } },
}

S.talk_linen = {
  { when = "foreman_down", steps = {
    gnome("Tell her it was all clean. Every last strip. Tell her that from nobody."),
  }, other = {
    gnome("These aren't bandages. This is just a lot of clean cloth I happen to boil every night. For no one. On my own."),
    gnome("And that's not a black thread. I found it. There's a great deal of it to find."),
  } },
}

S.talk_sweeper = {
  { when = "finished", steps = {
    t("Asleep on the broom, standing up. It's a real skill."),
  }, other = {
    gnome("I've swept this street four hundred times. It was clean by the second. But if I stop, I sit. And if I sit..."),
  } },
}

S.talk_tally = {
  { when = "foreman_down", steps = {
    gnome("Twenty-nine tags back on the board. Eleven still on the wrong side. We'll leave them there a while."),
  }, other = {
    gnome("That's the tally board. Tag goes on the left going down. Comes back to the right when you're up. Forty tags on the left."),
    gnome("I come out and look, every hour. It's not that I think they've moved."),
  } },
}

S.talk_lane = {
  { when = "foreman_down", steps = {
    gnome("Is it true? Can we go to bed? I want it in writing. No, I want it now."),
  }, other = {
    { when = "arrived", steps = {
      gnome("There's no cleric in this town. Nobody's seen a cleric. She definitely doesn't go down the mine at night with a basket."),
      gnome("Why, did somebody tell you she did? Who was it? I'll tell them to stop."),
    } },
  } },
}

-- ---------------------------------------------------------------- the first level

S.talk_warden = {
  { when = "mine_pass", steps = {
    gnome("Chit. Stamped. Countersigned by the Mayor, by the Mayor, and by me, apparently. That's in order."),
    gnome("Mind the floor. It's down."),
    { set = "warden_ok" },
  }, other = {
    gnome("Nobody goes below without a chit from the Mayor. I don't care how tall you are. I've been awake nine days and I'll bite your knee."),
  } },
}

S.scene_cleric = {
  t("The side gallery has been swept. Gnomes lie on clean sacking in careful rows, and each has a black thread tied at the wrist."),
  cleric("Stop there. Mind your boots. That one has only just stopped shaking."),
  t("The woman kneeling among them doesn't turn round. Her eyes are shut. You get the feeling this makes no difference."),
  cleric("Lavender and boiled linen. I know that smell. The last time it came through a door of mine, it took the door with it."),
  deserter("Formerly of the Clinic. I cut the badge off."),
  cleric("I've buried a lot of people who were formerly something."),
  deserter("A Thread Weaver. Here. They'd burn you for that, sister."),
  cleric("Eventually. There's a form first."),
  deserter("The Mayor says, if we don't meet you, she's out of bandages."),
  cleric("Is there one gnome in that town who can keep a secret?"),
  t("She rises and takes your wrist, without asking, the way you'd check a loaf. For a moment she says nothing at all."),
  cleric("The Raven Queen's work is mostly noticing. Every life is a thread, and a sleeper's goes slack and wanders off."),
  cleric("Yours doesn't look as if it has ever wandered anywhere. How strange. Have you been sleeping?"),
  t("She lets go, and doesn't explain."),
  cleric("Three more came up yesterday, and it's getting worse. Whatever is doing this is at the bottom. Those who can't wake will keep. They've got better at waiting than I have."),
  cleric("I'm coming with you. Don't thank me. She has a list, and I'd like to see who's next."),
  { join = "cleric", lvl = 3 },
  { set = "cleric_in" },
}

S.talk_nurse = {
  gnome("Sister left me in charge. Sit down. Sit, I said, not lie. There. Drink this. Don't dream."),
  { heal = true },
  t("The party is rested."),
}

S.talk_sick = {
  { when = "foreman_down", steps = {
    t("The sacking is empty. A black thread lies folded on it."),
  }, other = {
    t("Asleep, or something like it. The eyes move back and forth under the lids, all in the same direction, all together."),
  } },
}

S.talk_nib = {
  { when = "lift_free", steps = {
    nib("Brake's off! Going down? Tell him it was still his turn."),
    { choice = {
      { "Down to the deep seam.", {
        { warp = { "mine_3", 2, 13, 2 } },
      } },
      { "Not yet.", {} },
    } },
  }, other = {
    nib("Lift's stuck. Nob's got the brake on at the bottom, and he won't take it off till I say it was my turn."),
    nib("Eleven days we've been at it, down this speaking tube. Nob! NOB! Tell them whose turn it was!"),
    t("From a brass tube in the rock, very faint, a small voice says something rude."),
    nib("You see what I have to work with? If you're going down, tell him to take the brake off. There's no other way but the stairs."),
  } },
}

-- ---------------------------------------------------------------- the second level

S.talk_logkeeper = {
  gnome("Sign the shift log? Whoever signs in gets counted out. That's the rule. It's a very comforting rule."),
  { choice = {
    { "Sign the log.", {
      { save = true },
      gnome("Noted. Now, the long drift, east of here. Stay out if you can. It's full of sweetdamp, and it wasn't a fortnight ago."),
      gnome("Smells of pears. We sent a canary down. The canary had a lovely nap, and when it woke up it was not what you would call a canary."),
    } },
    { "Not now.", {} },
  } },
}

S.scene_gas = {
  { when = "gas_met", steps = {
    t("They lie where they fell, breathing slowly. The doctor is frowning in their sleep. The sister isn't. You can't carry them both past the sweetness, and it's only getting thicker."),
    t("Something creaks, far down the drift."),
  }, other = {
    t("The air in the long drift turns sweet. Pears, and something under the pears."),
    deserter("That's no damp. I know that smell. Friend, hold your breath, that's Clinic sopor, it isn't..."),
    t("The doctor sits down quite carefully, and does not get up."),
    cleric("Threads... all going slack..."),
    t("You catch the sister's lamp before it hits the floor. You wait for your own eyes to close."),
    t("They don't."),
    t("Far down the drift, something is creaking in a draught. You go on alone."),
    { set = "gas_met" },
  } },
}

S.scene_gas_mid = {
  t("The sweetness lies on your tongue and does nothing at all. In the lamplight the air has a colour now. It seems to lean away from you as you walk."),
  { set = "gas_mid" },
}

S.scene_valve = {
  t("A gnome sits slumped at a great iron wheel, smiling in his sleep. Above him a pipe runs into the rock, and a grey cask is strapped to it, with Clinic stencils."),
  t("You lift his hands away, and set yours on the wheel."),
  { sfx = "door" },
  { big = "THE VENTS OPEN" },
  t("Somewhere above, fans start to turn. The air comes down the drift cold and clean and smelling of nothing."),
  { fade = true },
  { set = "gas_off" },
  deserter("How long was I... who turned that? Who's been... oh."),
  cleric("You walked through that."),
  deserter("Nobody walks through that. I've handled sopor in gloves. It doesn't put you to sleep so much as drag you down into whatever you dream."),
  cleric("And you?"),
  hero("I don't dream."),
  t("Water drips somewhere for a while."),
  cleric("No. No, I don't suppose you do."),
  deserter("Let's talk about it when we're not standing in it. That cask has our old stencil on it, sister. I mean mine. I mean theirs."),
  t("The gnome at the wheel is still smiling. The sister ties a black thread at his wrist, and you all go on."),
}

-- ---------------------------------------------------------------- the deep seam

S.talk_nob = {
  { when = "lift_free", steps = {
    nob("Going up? I'm not saying whose turn it was. I'm just going up."),
    { choice = {
      { "Stay down here.", {} },
      { "Up to the first level.", {
        { warp = { "mine_1", 16, 14, 4 } },
      } },
    } },
  }, other = {
    t("A very small gnome is wedged in the back of the lift cage with a shovel across his knees."),
    nob("Are you real? Say something only a real person would say. No, don't. It would know that too."),
    nob("I saw the Foreman go by. He went by the way a coat goes by on a hook. Nib send you? It was HIS turn. You tell him."),
    { choice = {
      { "Take the brake off, Nob.", {
        nob("Fine. FINE. But only because you're tall and I'm frightened. Not because it was my turn."),
        { sfx = "door" },
        t("Chains shudder away up the shaft. The lift is free: Nob and Nib can carry you between here and the first level."),
        { set = "lift_free" },
      } },
      { "Leave him be.", {} },
    } },
  } },
}

S.scene_deep_shift = {
  t("The great hall of the deep seam. Lamps still burn along the walls. Below them, the deep shift lies in rows, tools beside them, as neatly as if someone had counted them down."),
  cleric("They're alive. All of them. Oh, you poor loves."),
  deserter("That's not sleep. That's a dosage."),
  t("Thirty-odd gnomes breathe in and out together. You have heard that sound before, through a wall."),
}

S.talk_sleeper = {
  t("Fast asleep. Lips moving. They're all saying the same thing, but it isn't a word yet."),
}

S.talk_lampwoman = {
  { when = "have_lamp", steps = {
    t("She sleeps on, one hand open where the lamp was."),
  }, other = {
    { when = "lamp_ask", steps = {
      t("A lamp stands by this one's hand, burning low. It has a green stripe, carefully painted, and only slightly crooked."),
      t("You take it, and turn the wick down. The sister looks at you for a moment, and then away."),
      { set = "have_lamp" },
    }, other = {
      t("A gnome in a patched coat. A lamp burns by her hand, with a green stripe painted on it."),
    } },
  } },
}

S.scene_last_lamp = {
  { when = "boss_warned", steps = {}, other = {
    t("One lamp still burns here, in a niche in the rock, and someone has left a flask beside it. You can hear scratching, further on. It sounds a lot like a pen."),
    deserter("That's the last of the good air. Whatever's ahead, let's meet it in good order."),
    { set = "boss_warned" },
  } },
  { save = true },
}

S.scene_foreman = {
  t("The gallery opens out. Grey casks stand stacked in neat shift order, each one with a chalk tally."),
  t("At the far end a very small figure in a very good waistcoat is checking a very long list."),
  foreman("Late. You're late. Shift started twelve days ago. I shall have to dock you."),
  foreman("Not a word of complaint from my deep shift. Not one. Everybody sleeping so well. Best figures in the history of the seam."),
  cleric("Foreman, they've been lying there for twelve days."),
  foreman("I signed for the casks. It was all in order. A very polite gentleman, and a very clean form. Vent at end of shift, and everyone rests easy."),
  foreman("I wasn't to breathe it myself. But you do. You do get curious. Oh, you get a lot of things."),
  t("He looks up from the list, and his head goes on tilting a little after it should have stopped."),
  foreman("Oh."),
  foreman("Oh, there you are. It said you'd be along."),
  foreman("I've got you on the books, {hero}. Right at the top. Longest shift of anyone, and you've never once clocked in."),
  deserter("Friend, who is he talking to?"),
  foreman("Clock in, {hero}. Everybody clocks in. CLOCK IN!"),
  { battle = "boss_foreman" },
  { set = "foreman_down" },
  t("The Foreman sits down among his casks. Whatever was wearing him goes out of him all at once, and what's left is a small old gnome, very tired."),
  foreman("Did they make quota?"),
  cleric("They did, Foreman. Every one. You can clock off."),
  t("She ties the black thread at his wrist. Then she stays a moment longer than she needs to."),
  t("Folded inside his waistcoat is a sheet of good paper, with a seal in black wax."),
  deserter("'Orrenshire, deep seam. Casks to be vented at end of shift. Subjects must sleep for the strain to take. Record onset. Record spread to surface.'"),
  deserter("'Do not treat.' It's underlined. Such a neat hand."),
  cleric("They sent this here. It didn't come out of the mountain. Somebody sent it, in casks, and asked to be told how it went."),
  t("The doctor has gone very still, thumb on the seal. A raven, with a lancet in its beak."),
  deserter("That's on my commission. It's on everyone's. It's Doctor Colette's own seal, and she doesn't lend it."),
  deserter("She taught my year. I saw her sit up three nights with a dying charwoman. Nobody made her."),
  cleric("Then someone has stolen it."),
  deserter("Then someone has stolen it. Yes. Let's say that."),
  t("Behind you, down the long hall, somebody coughs. Then somebody else. Someone starts, very quietly, to cry. It's the most wonderful sound you've heard in days."),
  { fade = true },
  { warp = { "orrenshire", 12, 9, 2 } },
  t("It takes all that day to bring them up, in the lift, a few at a time. Nib and Nob work the cage without a word. Then they have a word."),
  t("The Mayor will want to see that paper."),
}

-- ---------------------------------------------------------------- shops

-- Prices are party.lua's, so a shop and a treasure agree on what a thing is worth.
M.SHOPS.orrenshire = {
  { item = "shortsword", price = 60 },
  { item = "miners_pick", price = 130 },
  { item = "leathers", price = 50 },
  { item = "ringmail", price = 120 },
  { item = "robe", price = 15 },
}

M.SHOPS.orrenshire_goods = {
  { item = "potion", price = 12 },
  { item = "antidote", price = 8 },
  { item = "tonic", price = 30 },
  { item = "ether", price = 40 },
}

return M
