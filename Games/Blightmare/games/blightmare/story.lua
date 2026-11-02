-- games/blightmare/story.lua
-- Every word of the slice, draft for the author to edit. A script is a list of steps run by the engine in rules.lua.
-- A choice is the hero's own voice, and ask() puts a question over it. An option made with topic() comes back to the list when
-- it's been heard, so a list like that needs a question and at least one plain option as the way out. The test bot takes the
-- first plain option, so among those the first must be the one that moves the story on. No choice may block the story.
-- The deserter, cleric and owlin have no names yet, so people call them what they are: "doctor" and "sister". The names over
-- their portraits come from party.CHARS.
-- People who aren't in the portrait list borrow a portrait and give their own name, as nan() and wick() do.

local M = {}

M.START = "start"
M.SHOPS = {}
M.SCRIPTS = {}

-- The story guide, in order. The current goal is the first whose done flag isn't set, skipping any whose when flag isn't.
-- map, x, y is the square to reach or the person to talk to, and site is an id from overworld.SITES.
M.GOALS = {
  { done = "signed", text = "Sign the Dream Book", map = "scythebreak", x = 12, y = 10 },
  { done = "breach", text = "Take the loaf to the wall", map = "scythebreak", x = 4, y = 11 },
  { done = "wick_down", text = "Get away from the wall", map = "scythebreak", x = 7, y = 11 },
  { done = "tested", text = "Go to the Clinic house", map = "scythebreak", x = 16, y = 7 },
  { done = "gate_won", text = "Escape by the east gate", map = "scythebreak", x = 21, y = 11 },
  { done = "arrived", text = "Reach Orrenshire", site = "orrenshire" },
  { done = "mine_pass", text = "Talk to the Mayor", map = "orrenshire", x = 18, y = 12 },
  { done = "warden_ok", text = "Show the warden your chit", map = "mine_1", x = 5, y = 3 },
  { done = "cleric_in", text = "Search the first level", map = "mine_1", x = 10, y = 3 },
  { done = "gas_off", text = "Get through the long drift", map = "mine_2", x = 11, y = 12 },
  { done = "saw_shift", text = "Find the deep shift", map = "mine_3", x = 10, y = 7 },
  { done = "foreman_down", text = "Find the Foreman", map = "mine_3", x = 13, y = 13 },
  { done = "finished", text = "Show the Mayor the paper", map = "orrenshire", x = 18, y = 12 },
}

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

--- Someone with a borrowed portrait and a name of their own.
local function person(say, name)
  return function(text) return { say = say, name = name, text = text } end
end

local lioth = person("villager", "MISTRESS LIOTH")
local satchel = person("captain", "CLINIC CLERK")
local chalker = person("doctor", "CHALKER")
local tibble = person("gnome", "TIBBLE THE HATTER")
local silt = person("villager", "MOTHER SILT")
local bascombe = person("captain", "CLERK BASCOMBE")
local propsetter = person("gnome", "PROP-SETTER")
local dunnock = person("gnome", "DUNNOCK")
local handler = person("villager", "CASK HANDLER")

--- A line that asks a question, with the list of answers under it. One short page: it shows again each time the list comes back.
local function ask(line, options)
  line.choice = options
  return line
end

--- An option that goes back to the list once it's been heard.
local function topic(label, steps)
  return { label, steps, again = true }
end

-- ---------------------------------------------------------------- morning in Scythebreak

S.start = {
  { warp = { "scythebreak", 3, 3, 2 } },
  t("Everyone in Scythebreak goes somewhere at night. They tell you about it over breakfast: colours, falling, all their teeth, a dead uncle asking after the horse."),
  t("You have never been. You shut your eyes, you open them, and it is morning. There is nothing in between. There never has been."),
  nan("Up, {hero}! The bell's gone and the porridge has started to set, and I'm not chiselling it off the pot a second time. Come on, out of there."),
  ask(nan("Well, then? What did you dream?"), {
    topic("Why do you ask me every morning?", {
      nan("Because the Book's going to ask you, and I'd rather you practised on someone who loves you. And because a body ought to have one person who wants to know how their night went."),
    }),
    { "Nothing, Nan. Same as always.", {
      nan("Nothing. All these years under my roof and not one decent nightmare to share over breakfast. The Hanley boy was chased by a goose the size of a barn last week, and I'd have paid to hear that."),
    } },
    { "A dead uncle asked after the horse.", {
      nan("You've no uncle and we've no horse. You had that off the Hanley boy, and you can't even lie about it properly. Eat your porridge."),
      { set = "joked_nan" },
    } },
  }),
  nan("Two jobs, and then you're your own. Sign the Dream Book in the square before the clerk turns sour, and then take this loaf down to the lad on the wall-watch."),
  nan("He's too thin, and I've decided that's my problem."),
}

S.talk_nan = {
  { when = "bread_done", steps = {
    nan("That's my good one. Go on and play, or whatever it is you do now you're too big for it."),
  }, other = {
    { when = "signed", steps = {
      nan("The loaf, {hero}. Down through the square and west along the high street, right to the end. You can't miss the wall-watch, because it's the wall."),
    }, other = {
      nan("The Book first, love. A dream undeclared is a fine and a second one is a visit, and I'll not have a visit in this house."),
    } },
    ask(nan("What is it? You've got your standing-about face on."), {
      topic("Tell me about the cart from Evrastin.", {
        nan("Again? You came over on the last cart out, a babe in a crate, with half the Empire screaming behind the wall. Everyone on that cart had seen things they'd never stop seeing."),
        nan("And there was you, fast asleep. You slept through the end of the world, {hero}. I took one look and thought, well, that one's going to be no trouble."),
      }),
      topic("What's it actually like, dreaming?", {
        nan("Oh, love. It's like being told a story by someone who's forgotten how it goes. Mostly it's nonsense, and you lose it by breakfast. I don't know that you've missed much."),
        nan("These days, with the Book and the wall, I think you may be the lucky one. Don't tell anyone I said so."),
      }),
      { "I'm going, I'm going.", {
        nan("That's what I like to hear. Mind you come straight back, there's a fence wants mending."),
      } },
      { "Stop fussing, Nan.", {
        nan("I'll stop fussing when I'm dead, and then I'll fuss at you from the other side. Go on with you, cheek."),
        { set = "snapped_nan" },
      } },
    }),
  } },
}

S.talk_wick = {
  t("Wick the lamplighter is holding his pole in both hands, as if it might get away. It's broad daylight."),
  { when = "wick_spoke", steps = {
    wick("Still fine, {hero}. Still grand. You needn't keep checking. I'm just going to stand here a while and not sit down."),
  }, other = {
    wick("Morning, {hero}! Grand day. I slept like a stone last night, like a big, sleeping stone. Why, what have you heard? Has somebody said something?"),
    { choice = {
      { "You look dreadful. Are you all right?", {
        wick("Am I... that's kind of you. Nobody asks that any more, do they? They just look to see if they should write it down. I'm tired, that's all. Tired, and a bit too awake."),
        { set = "kind_wick" },
      } },
      { "Whatever it is, I won't tell the Book.", {
        wick("There's nothing to tell. But thank you. Thank you, {hero}. You always were a decent sort, for someone with nothing to hide."),
        { set = "promised_wick" },
      } },
      { "Maybe the clerk should hear about this.", {
        wick("Don't. Please. Don't joke about that, not even you. I've got eleven years of clean pages in that Book. I'd like to keep them."),
        { set = "threat_wick" },
      } },
    } },
    { set = "wick_spoke" },
  } },
}

S.talk_kid = {
  child("I'm the doctor and you're sick. Say ah. Now you're dead, and I'm very sorry, but it's for the good of the town. That's what you say. I've heard them."),
  ask(child("{hero}? What's nothing like? Nan says you don't get dreams, you just get nothing. Is it black? Is it like when you shut your eyes?"), {
    topic("Who told you to ask me that?", {
      child("Nobody. I asked a soldier what nothing was like, and he wrote my name down. Then he asked how to spell it. I don't think I was meant to be pleased."),
    }),
    { "It's quiet. It doesn't hurt at all.", {
      child("Oh. That sounds nice. I'd like some of that. I'm going to tell the man in my room it's nice, and maybe he'll go away."),
      { set = "kid_kind" },
    } },
    { "It's like nothing. Go and play.", {
      child("You're no fun. I'm going to give you the bad medicine now. You'll have to lie very still while I write it down."),
      { set = "kid_snub" },
    } },
  }),
}

S.talk_clerk = {
  { when = "signed", steps = {
    ask(clerk("You've signed, so don't loiter by the Book. People will think you've remembered something."), {
      topic("What happens if someone lies in it?", {
        clerk("Then it's a lie in very good handwriting. I don't catch liars, {hero}. I just keep the pages, and now and then someone comes and takes a page away. I've learned not to wonder."),
      }),
      { "I'll be off, then.", {} },
    }),
  }, other = {
    clerk("Next. Name, and anything to declare from the night. Oh, it's you, {hero}. I don't know why I ask."),
    ask(clerk("'Nothing', I suppose? I can write it for you, if you like. I've a very good hand for it by now."), {
      topic("Does anyone actually read all this?", {
        clerk("Somebody must. Every quarter a man comes with a satchel and counts the pages. That's him across the square, and he has never once smiled. I've kept this Book twenty-two years, and I'd rather not know who it's for."),
      }),
      { "Nothing, thank you.", {
        clerk("Nothing it is. There. You're a pleasure to file."),
      } },
      { "Put me down for a dragon. A big one.", {
        clerk("Very droll. I shall write 'nothing', and add a small note about your attitude. You'd be amazed how long a small note can follow a person."),
        { set = "sass_clerk" },
      } },
    }),
    t("You sign. The page above is yours, and the page above that. Nothing, nothing, nothing, in your own writing, back and back."),
    clerk("You know, in all my years with this Book, you're the one person who has never lied to me. Either that, or you're the only one who always has. Off you go."),
    { set = "signed" },
  } },
}

S.talk_widow = {
  { when = "horn", steps = {
    villager("I heard the horn, love. They'll want us all in a line, and I'll go when I've found my good shawl. Let them wait for me for once. I've had nine years of waiting for them."),
  } },
  { when = "heard_tobin", steps = {}, other = {
    villager("My Tobin put down a dream in that Book once. Only a small one. He said he'd been a fish, and that it was the happiest he'd ever been."),
    villager("They sent someone round, ever so polite, and took him for one night of observation. That's nine years ago now. They write every spring to say he's doing well."),
    { set = "heard_tobin" },
  } },
  ask(villager("I keep his boots by the door. You'll think that's foolish."), {
    topic("Have they ever let you see him?", {
      villager("You'd have to go to Adaphis, and you'd need a pass for that, and a reason for the pass. I've filled in the form four times. It's a very kind form. It thanks me for my patience."),
    }),
    { "It isn't foolish. I'm sorry.", {
      villager("You're a good child. Most people look at the floor. Tell Nan I've still got her pie dish."),
    } },
    { "He might still come back.", {
      villager("He might, at that. It costs nothing to think so. And I'll tell you, there's not much left round here that costs nothing."),
    } },
  }),
}

S.talk_doorman = {
  ask(soldier("Clinic house is for Clinic business. You'll know when it's your business, because they'll come and fetch you."), {
    topic("What goes on in there?", {
      soldier("Paperwork, mainly. Some nights you can smell lavender from the square. I've no idea why that should bother a person, but there you are."),
    }),
    { "Just passing.", {} },
  }),
}

S.talk_gateman = {
  { when = "horn", steps = {
    orderly("I'm so sorry, the gate is shut for the present, pass or no pass. I'm afraid reasons have stopped working this morning. Everyone's being seen at the Clinic house, and I hear they're being very good about it."),
  }, other = {
    { when = "asked_pass", steps = {
      orderly("Back already? I'm still thinking about what counts as a good reason, and it's turned out to be a very large question. Bring me yours when you've got one, and we'll see how it does."),
    }, other = {
      orderly("Good morning. The gate is for people with a pass, and passes are for people with a reason. We're very happy to hear your reason. Do you have one?"),
      { choice = {
        { "Not really. Just looking.", {
          orderly("Looking is free. It's a lovely gate. Have a pleasant day."),
        } },
        { "What counts as a good reason?", {
          orderly("Do you know, in six years nobody has asked me that. I'll have to think about it. Come back when you've got one, and we'll see how it does."),
          { set = "asked_pass" },
        } },
      } },
    } },
  } },
}

S.talk_watch = {
  { when = "breach", steps = {
    soldier("Go on, get away from here! Don't stop for anything, and don't let anything touch you! I'm going to stay and, and hold this!"),
  }, other = {
    { when = "signed", steps = {
      ask(soldier("Is that bread? Is that Nan's bread? Don't tell the sergeant, whatever you do. He'll want to inspect it, and he inspects with his mouth."), {
        topic("What's it like, standing here all day?", {
          soldier("Honestly? You stop seeing it. It goes up and up and after a week it's just the sky with a bad attitude. My mother thinks I'm guarding something. I think I'm guarding a wall."),
        }),
        { "Nan says you're too thin. Eat.", {
          soldier("Tell her she's the only person in Scythebreak who's noticed. No, I mean it. I'll bring the cloth back washed."),
          { set = "fed_watch" },
        } },
        { "Here. Mind you don't choke.", {
          soldier("Charming. Thanks anyway."),
        } },
      }),
      t("Behind him the wall goes up and up. It takes a while to find the top. You've stopped noticing that, mostly."),
      soldier("Do you hear something? It's like somebody breathing in, and breathing in, and not stopping."),
      { set = "bread_done" },
      { set = "horn" },
      { sfx = "horn" },
      t("The loaf is still warm when the horn starts."),
      soldier("That's not the drill horn. There's no drill today. Why is that...?"),
      t("At the foot of the wall there's a crack you've walked past every day of your life. It is getting wider. Something is coming out of it, in instalments."),
      { big = "THE WALL IS OPEN" },
      soldier("Get behind me! Get BEHIND me! Oh, gods, it's... I've dropped my... you'll have to..."),
      { battle = "tut_crawler" },
      t("It stops moving. It takes some time to stop all of it."),
      soldier("You killed it. With a kitchen knife. I've had eight weeks of training and I dropped my spear."),
      { choice = {
        { "Are you hurt?", {
          soldier("I don't think so. I don't know. Nobody's ever asked me what to do about this, so I don't suppose anybody knows. Thanks for... yes."),
        } },
        { "Pick up your spear.", {
          soldier("Yes. Right. Yes, I'll do that. You're not supposed to be the calm one."),
        } },
      } },
      soldier("Don't touch it, and don't breathe near it. Go home, {hero}. Go on, go, before they get here and start asking who was standing where!"),
      { set = "breach" },
    }, other = {
      soldier("Morning, {hero}. Book first, I'm afraid. The sergeant won't have me taking so much as a crust from anyone who hasn't signed, and he counts the crumbs."),
    } },
  } },
}

-- ---------------------------------------------------------------- the breach

S.scene_wick = {
  t("Wick is standing in the middle of the street with his lamp-pole, quite still."),
  { when = "promised_wick", steps = {
    wick("{hero}. You said you wouldn't tell the Book, and I believed you. I want you to know that's the last nice thing that's going to happen to me."),
  }, other = {
    { when = "kind_wick", steps = {
      wick("{hero}. You asked if I was all right. I should have said. I should have said it to someone, and it might as well have been you."),
    }, other = {
      { when = "threat_wick", steps = {
        wick("{hero}. Did you tell them? No. No, it doesn't matter now. Don't tell the Book. There isn't going to be a Book."),
      }, other = {
        wick("{hero}. Don't tell the Book. I've kept clean pages for eleven years, and I'd hate to spoil them now."),
      } },
    } },
  } },
  wick("I had one. The night before last, the first in years, and only a small one. I thought if I stayed awake it would get bored and go away. It's still going."),
  t("His shadow has stopped doing what he does."),
  { choice = {
    { "Wick, put the pole down.", {
      wick("I'd like to. I've been asking my hands. They say it isn't up to them."),
    } },
    { "What's still going?", {
      wick("I don't know its name. It's so very big, {hero}, and I'm only the door it came in by."),
    } },
    { "Stay back. I mean it.", {
      wick("That's right. That's good. You stay back, and I'll stay here, and we'll see which of us it listens to."),
    } },
  } },
  wick("It's looking at you. It looked right at you, and it... no. It wants everyone. It wants everyone in the world. Why doesn't it want you?"),
  { battle = "wall_breach" },
  { set = "wick_down" },
  t("The lamp-pole rolls a little way along the street and stops."),
  t("What's left doesn't stay to be looked at for long. Soldiers are already there with a sheet. They seem to have had it ready."),
  captain("You. Stand still. Did it touch you? Did you touch it? Think carefully before you answer, because I'll know, and it'll be worse for having been lied about."),
  { choice = {
    { "It never touched me.", {
      captain("Hm. No, I don't believe it did. That's interesting. Let them through."),
    } },
    { "That was Wick. He lit your lamps.", {
      captain("I'm aware of who it was. He'll be in the report, under his own name. That's more than most get. Let them through."),
    } },
  } },
  { sfx = "horn" },
  captain("By order of the Clinic, Scythebreak is closed. Every resident will go at once to the Clinic house for testing, and you'll be seen in good order."),
  captain("There is no need to be afraid. There is also no need to run. We've thought of that."),
  { set = "lockdown" },
}

S.talk_q_nan = {
  { when = "nan_queued", steps = {}, other = {
    nan("There you are. Come and stand by me. Oh, you've blood on you. Whose is that? No, don't tell me, not here."),
    { when = "snapped_nan", steps = {
      nan("And before you say it, yes, I'm fussing. You can tell me to stop later. I'd like that. I'd like there to be a later for you to be rude in."),
    } },
    { when = "joked_nan", steps = {
      nan("I've been thinking about that dead uncle you made up, and his horse, and I'll say this: it's the best laugh I've had all week. It's a poor week."),
    } },
    { set = "nan_queued" },
  } },
  ask(nan("It's only a test, they say. You drink it, you sleep it off, and you complain."), {
    topic("Are you frightened?", {
      nan("I've been frightened since before you were born, love, and I've still got the washing done. You don't stop for it. That's the whole of what I know."),
    }),
    { "We'll be fine, Nan.", {
      nan("Course we will. You always are, {hero}. I've never known it to fail."),
    } },
  }),
}

S.talk_q_clerk = {
  { when = "sass_clerk", steps = {
    clerk("Twenty-two years I've kept that Book, and they didn't let me bring it. I've been thinking about your dragon. I don't know why I wrote that note. It's not as though it matters now."),
  }, other = {
    clerk("Twenty-two years I've kept that Book, and do you know, they wouldn't let me bring it? They've got their own. I saw it. It's much thinner than mine."),
  } },
  { choice = {
    { "Who's it for, that thin book?", {
      clerk("For the names, I should think. Only the ones they're interested in. I always assumed I'd feel safer not being in it."),
    } },
    { "Save me a place in the queue.", {
      clerk("I've kept a place for everyone for twenty-two years. I don't see why I'd stop today."),
    } },
  } },
}

S.talk_q_kid = {
  { when = "kid_snub", steps = {
    child("I'm still not talking to you. But is Wick sick? I said hello to him, and he said hello back, only not from where he was."),
  }, other = {
    child("Is Wick sick? I said hello to him and he said hello back, only not from where he was. The man in my room doesn't look worried."),
  } },
  { choice = {
    { "Stay close to Nan, all right?", {
      child("All right. She's got a pocket with a biscuit in it. I checked."),
    } },
    { "What man in your room?", {
      child("He's only there when it's dark. I say hello, because it's polite. He doesn't say anything yet."),
    } },
  } },
}

S.scene_test = {
  t("The hall smells of lavender and boiled linen. Someone has set out chairs. Someone has given thought to the chairs."),
  doctor("Come in and sit down. Whoever was nearest the wall is seen first, so you've gone to the head of the queue. You've had a frightening morning, and I'm sorry for that. Would you like some water?"),
  doctor("I'm the doctor, and that's all you need to call me. This is a draught, and it will give you one night of very bad dreams. If there is anything in you, we'll see it by morning."),
  doctor("If there is nothing in you, you'll have lost a night's rest, and I shall apologise to you in person. Everyone takes it. Your neighbours have all been very good."),
  ask(doctor("Is there anything you'd like to ask first? I always encourage questions."), {
    topic("What's in it?", {
      doctor("A little of what you're afraid of, in a very safe amount. That's how most medicine works. I could give you the proper name, but people tend to find it doesn't help."),
    }),
    topic("Will Nan have to take it too?", {
      doctor("She's next, just outside that door. She's being very good, and she's told my orderly he's too thin. She'll be looked after by people who are trained to do it."),
    }),
    topic("What happens if it finds something?", {
      doctor("Then you'll be cared for. Nobody here is being punished, {hero}. I want you to hold on to that, whatever else you hear tonight. The Clinic has never once been angry with a patient."),
    }),
    { "All right. I'll drink it.", {
      t("It tastes of pennies."),
    } },
    { "No. I won't.", {
      doctor("Of course. You may refuse. It's on the form. The form says you will then be held down and given it, but you may refuse, and I want you to feel that you've been heard."),
      t("It tastes of pennies."),
      { set = "refused_draught" },
    } },
  }),
  { fade = true },
  t("You shut your eyes, you open them, and it is morning. There is nothing in between. There never has been."),
  t("The rest of Scythebreak does not wake so well."),
  t("It comes through the walls of the ward, from every bed at once. Nobody is screaming. It's much quieter than that."),
  { warp = { "scythebreak", 17, 3, 3 } },
  doctor("Good morning, {hero}. How did you sleep? There's fresh water by your hand. Now, I'd like you to tell me what you saw."),
  hero("Nothing."),
  t("The pen stops."),
  doctor("Take your time. There's no wrong answer, and nobody is going to be cross. Would you like some water?"),
  { choice = {
    { "Nothing. I never do.", {} },
    { "What's wrong with everyone?", {
      doctor("In a moment. First I'd like you to answer the question, and then I shall be delighted to answer yours. What did you see?"),
      hero("Nothing."),
      { set = "challenged_doctor" },
    } },
  } },
  captain("Every bed in that ward, doctor. My own men, and children. And this one's sitting here as if it were any other breakfast."),
  doctor("Yes. Isn't it wonderful?"),
  doctor("Captain, this is a clean result. Do you understand me? In all the years of the wall, there has never been a clean result."),
  captain("What do you want done?"),
  doctor("A closed cart for Adaphis, at first light. Doctor Colette will want to see this one herself."),
  ask(doctor("You've done nothing wrong, {hero}. Do remember that. It won't help, but it's true. Is there anything else?"), {
    topic("Can I see Nan?", {
      doctor("Not at present. She's in the ward, and she's comfortable, and she's asking for you, which is a very good sign. I wouldn't want you to upset the readings."),
    }),
    { "I'm not getting in any cart.", {
      doctor("No one will mind that at all. We have people to lift you. Captain, thank you."),
      { set = "defied_cart" },
    } },
    { "Say nothing.", {
      doctor("Good. Rest. You've been a great help to a great many people, and you'll never know their names."),
    } },
  }),
  { warp = { "scythebreak", 22, 3, 3 } },
  { fade = true },
  { set = "tested" },
  t("Night. A bed, a bucket and a very clean floor."),
  t("Through the wall a whole town is breathing, all together, in time."),
  t("Someone is working at the lock. Badly."),
  deserter("Hold still. I mean, I'm the one who... give me a moment, this is a delicate instrument."),
  { sfx = "door" },
  deserter("It's a spoon."),
  t("The door opens on a Clinic coat with the badge cut off. Above it is a long scar, and a face that has been awake for about a year."),
  deserter("Quietly, friend. I'm from the Clinic, and I'm also leaving it, as of roughly now. At first light they put you in a closed cart. I've walked beside those carts eleven times."),
  deserter("The orderlies on this ward have had the soup. I made the soup. They'll wake at noon feeling dreadful, and I'm at peace with that."),
  { when = "refused_draught", steps = {
    deserter("I read your sheet, by the way. 'Refused, then drank.' You'd be surprised how few have that first word on them. I liked seeing it."),
  } },
  { when = "defied_cart", steps = {
    deserter("And I gather you told the doctor you wouldn't get in the cart. Very good. Now let's arrange for that to be true."),
  } },
  { when = "challenged_doctor", steps = {
    deserter("I also hear you asked what was wrong with them. Nobody's ever going to answer that, friend. I've been asking for years."),
  } },
  ask(deserter("We haven't long, but I'd sooner you came with your eyes open. Ask what you need to."), {
    topic("Why are you doing this?", {
      deserter("Because I've written the word 'clean' on a great many forms, and you're the first time it was true. And because I'd like to have done one thing in that coat I could tell someone about."),
    }),
    topic("What about the others? What about Nan?", {
      deserter("They told us at the college that the draught only shows what's already there. They told us a lot of things at the college."),
      deserter("There's nothing I can do in that ward tonight, and I'm sorry. There is something I can do about you."),
    }),
    topic("What happens in Adaphis?", {
      deserter("I've only ever seen the outside of it. Do you know what comes back from Adaphis? The cart. It comes back very clean."),
    }),
    { "Get me out of here.", {
      deserter("Good. I was hoping you'd be the practical sort."),
    } },
    { "How do I know this isn't another test?", {
      deserter("You don't. If I were you I'd keep thinking that for a while. It's what I'd want in a patient. Now come on anyway, because the alternative is the cart."),
      { set = "doubted_deserter" },
    } },
  }),
  { when = "heard_tobin", steps = {
    hero("A man called Tobin went in one of those carts, nine years ago. His wife still gets letters."),
    deserter("Every spring. Yes. There's a whole office for that. I've never met anyone who worked in it, and I've never met anyone who'd admit to it."),
  } },
  deserter("The ward's on our way to the front door, so don't stop long. After that it's the square, then Gate Street, and try to look like someone who's being discharged."),
  { join = "deserter", lvl = 2 },
  { set = "escaped" },
  { warp = { "scythebreak", 22, 5, 3 } },
  { save = true },
}

S.ward_nan = {
  { when = "said_goodbye", steps = {
    t("She doesn't wake again. Her hands go on kneading."),
    deserter("She's still in there. I know that isn't a comfort, and I'd offer you a better one if I had any. We should go."),
  }, other = {
    t("Nan is lying very straight, which she has never done. Her hands are moving a little on the blanket, as if there were dough."),
    nan("{hero}? Is that you? Have you eaten? You've got thin. They'll have you thin as that poor lad on the wall."),
    nan("I had a dream, love. Imagine, at my age. It was so big, and it's still... tell me. Tell me what you dreamed."),
    { choice = {
      { "Nothing, Nan.", {
        nan("Good. That's my good one. You keep it that way, whatever anybody tells you. Promise me that."),
      } },
      { "A small one, Nan. A nice one.", {
        nan("Did you, now? Well. You never could lie, but that's the best you've ever done it. Oh, I'm proud of you."),
        { set = "lied_to_nan" },
      } },
    } },
    nan("Go on, now. Off you go, before the porridge sets."),
    { set = "said_goodbye" },
  } },
}

S.ward_kid = {
  { when = "kid_kind", steps = {
    t("The child is humming, with both eyes shut. As you lean in the humming stops, and the small lips move. 'It's quiet,' says the child. 'You said.'"),
    t("Someone else in the room goes on humming. You're the only two awake in this row."),
  }, other = {
    t("The child is humming, with both eyes shut. Someone is humming along. You're the only two awake in this row."),
  } },
  { choice = {
    { "Tuck the blanket in.", {
      t("It's a very thin blanket. You do it properly anyway, the way Nan does."),
    } },
    { "Walk on.", {} },
  } },
}

S.ward_clerk = {
  t("The clerk's right hand writes on the sheet, over and over, with no pen. It's the same short word each time."),
  { choice = {
    { "Read the word.", {
      t("It isn't 'nothing'. It's a very neat hand. You wish you hadn't looked, and a moment later you can't remember why."),
    } },
    { "Leave him to it.", {} },
  } },
}

S.ward_watch = {
  { when = "fed_watch", steps = {
    t("The lad from the wall-watch. There's still a heel of Nan's loaf in his fist, and a cloth folded in his belt, washed. Nobody has been able to get either away from him."),
  }, other = {
    t("The lad from the wall-watch. There's still a heel of Nan's loaf in his fist. Nobody has been able to get it out."),
  } },
}

S.ward_bed = {
  ask(deserter("That was to be yours in the morning, for the form. Every patient gets a bed. After that you'd have been a transfer, and nobody counts a transfer."),  {
    topic("How many have you transferred?", {
      deserter("I told you, eleven carts. Don't ask me how many to a cart. I've tried not knowing, and it didn't take."),
    }),
    { "Let's go.", {} },
  }),
}

S.scene_night_street = {
  t("The town is dark for the first time in your life. Nobody has lit the lamps. Nobody is left who does."),
  t("Each door has been marked in chalk with a neat tally. Nan's will have one too."),
  { set = "night_seen" },
}

S.scene_gate = {
  t("Two orderlies stand at the gate, with a lantern. Neither of them has had the soup."),
  orderly("Good evening, doctor. You're not on the sheet tonight, and I don't believe the patient is either. Might I ask your reason?"),
  deserter("No. I've taken myself off it."),
  { when = "asked_pass", steps = {
    orderly("Ah, and it's you. Did you come up with a good reason? I've been looking forward to it. I did say to come back."),
  } },
  orderly("Please step away from the patient. There's no need for this to be unpleasant."),
  { choice = {
    { "Open the gate.", {
      orderly("I'd be delighted, with the proper form. I'm afraid you'd have to fill it in from inside the cart."),
    } },
    { "This is my reason.", {
      t("You show him the knife. He nods politely, and makes a small note."),
    } },
    { "Please. Let us go.", {
      orderly("That's nicely asked. It really is. I'm so sorry."),
    } },
  } },
  deserter("There's never any need for it to be unpleasant. That's what's wrong with it."),
  { battle = "gate_orderlies" },
  { set = "gate_won" },
  { warp = { "scythebreak", 23, 11, 2 } },
  { save = true },
  t("The gate stands open. Behind you no horn sounds. Nobody is running. Somewhere, you suspect, a pen is writing this down."),
  { when = "lied_to_nan", steps = {
    deserter("I heard what you told the old woman. You could have let her have the truth, and you gave her something better. I don't know that I'd have thought of it."),
  } },
  deserter("North-east, up the road, is Orrenshire, against the mountains. Gnomes, mostly. The Clinic keeps one bored clerk there and a drawer of unanswered letters, so it's the last place anyone will look."),
  ask(deserter("If we walk all night we'll be off their map by morning. Unless there's something you'd like to say first."), {
    topic("Will Nan get better?", {
      deserter("I've never seen it. I've seen them stop getting worse, and I've been told that's the same thing. I won't tell you that, because you've been lied to enough for one day."),
    }),
    { "Lead on.", {
      deserter("That's the spirit. Well, it's a spirit."),
    } },
    { "I should go back for them.", {
      deserter("I know. And in a day you'd be in a cart, and they'd be exactly where they are. If there's an answer, it isn't in that town. Help me look for it. You can hate me for it as we go."),
      { set = "wanted_back" },
    } },
  }),
  deserter("And friend, when we get there, I'm a herbalist. Don't call me doctor unless you have to. I'm trying to give it up."),
  { set = "left_town" },
  { world = { 62, 60 } },
}

S.turned_back = {
  { when = "wm_done", steps = { { warp = { "em_scythebreak", 23, 11, 4 } } }, other = { -- by then there is nobody left to turn anyone back
    t("Clinic lamps at every corner, and chalk on every door. There's no one left here you can reach. Not yet."),
    { when = "wanted_back", steps = {
      deserter("I know, friend. Not like this. We'll come back when we've got something to come back with."),
    } },
    { world = { 62, 60 } },
  } },
}

S.gate_greywater = {
  t("The Greywater bridge is barred, with a Clinic lamp at each end."),
  { when = "escaped", steps = {
    deserter("Not that way. That road goes to Oplinas, and Oplinas is theirs. Back up the road to Orrenshire, friend."),
  } },
}

-- ---------------------------------------------------------------- Orrenshire

S.scene_orrenshire = {
  t("Orrenshire is built into the foot of the mountain, and all of it is slightly too small. The doors come up to your chest. Every lamp in town is lit. It's the middle of the day."),
  gnome("Halt! State your name, your business, your height, and whether you have at any time today been asleep! Take your time, I've got a form, and I've lost it!"),
  { choice = {
    { "Just passing through. Is something wrong?", {
      gnome("Wrong? Nothing's wrong! Morale has never been higher! I've been looking at that post for six hours and I think we've become friends!"),
    } },
    { "Asleep? Who's asking?", {
      gnome("The Town of Orrenshire's asking, that's who, and I'll thank you not to say that word so loud! There's people here hanging on by their eyebrows!"),
    } },
    { "I slept wonderfully, thank you.", {
      gnome("Oh, you monster. Oh, you lucky, lucky monster. Was it soft? No! Don't tell me! I'm a public official!"),
    } },
  } },
  deserter("Is this a trick question, or is it a local custom?"),
  gnome("It's Ordinance Forty! Anyone found asleep in Orrenshire shall be shouted at, kindly, until they stop! Nine days, we've gone! It's a new town record, and the Mayor's making a speech about it. She started on Tuesday!"),
  deserter("Nobody stays awake nine days for fun. Friend, I think we'd better hear that speech. It's the east side of the square, by the sound of it."),
  { set = "arrived" },
}

S.talk_mayor = {
  { when = "finished", steps = {
    t("The Mayor is asleep at her desk, on a motion of her own. Someone has put a coat over her. It's a very small coat."),
  }, other = {
    { when = "foreman_down", steps = {
      mayor("They're up! Twenty-nine of them, on their own feet, and most of them know their own names! Oh, I shall want that in the minutes!"),
      t("The doctor lays the paper on her desk. She reads it twice, standing on a box."),
      mayor("It's a form. I knew it. I wrote eleven letters to those people, and all along the answer was a form. Do you know, I think I'd have minded less if they'd been rude."),
      ask(mayor("They'll come for us when they hear of this, won't they? You look like you know how that goes."), {
        topic("What will you do with the casks?", {
          mayor("Burn them, and then bury the ashes, and then hold a meeting about the burying. The second-level gnomes want to drop them down the shaft. I've told them it's been a hard month for the shaft."),
        }),
        topic("What about the ones who didn't wake?", {
          mayor("Eleven tags on the wrong side of the board. The sister's thread is on every one, and we'll keep them warm for as long as it takes. A town can do that much. It's what a town is for."),
        }),
        { "They'll come. Be ready.", {
          deserter("They'll come with a kind voice and a clean cot, so burn the casks and keep your letters short. Don't let anyone take a count of you."),
        } },
        { "We'll keep them looking at us.", {
          deserter("Which I hadn't planned on, but very well. Burn the casks anyway. If anyone comes with a form, tell them the tall ones went east."),
          { set = "drew_fire" },
        } },
      }),
      mayor("And you? There'll be a bounty on a tall one and a herbalist by Friday. Don't look like that, we can read. We just don't like to bother people with it."),
      cleric("We need to learn whose hand was on that seal, and that means going somewhere other than here. I'll want a day with my sleepers first."),
      { when = "drew_fire", steps = {
        mayor("That's a brave thing, to stand where they'll look. Orrenshire remembers its debts, in triplicate."),
      } },
      { when = "held_handlers", steps = {
        mayor("And those two great lumps you sent up with the casks are in my cellar, with a chair each, as requested. They've offered to play me at cards. I've taken eleven gold off them."),
      } },
      { when = "spared_handlers", steps = {
        deserter("Those two handlers will be halfway to Blackpool by now, telling anyone who'll listen that they never asked. I hope that was mercy, friend. It's hard to tell, from the inside."),
      } },
      { when = "pledged_free", steps = {
        mayor("You said you'd go down for nothing, and I've thought of that every hour since. So the town of Orrenshire offers you its thanks, carried unanimously, and this. It's more than you asked for."),
        { gold = 300 },
      }, other = {
        { when = "haggled_mayor", steps = {
          mayor("You asked what it was worth, and quite right. I said we'd see you paid. The town's thanks are carried unanimously, and here's the coin, counted twice."),
          { gold = 200 },
        }, other = {
          mayor("The town of Orrenshire offers you its thanks, carried unanimously, and this. It's most of the coin there is."),
          { gold = 200 },
        } },
      } },
      mayor("There's one further item. It's a motion to go to bed. All those in favour?"),
      t("It carries in about four seconds."),
      { fade = true },
      t("All over Orrenshire the lamps go out, one street at a time, for the first time in eleven days."),
      t("Somebody is snoring. Somebody shouts at them, kindly, and then forgets to go on."),
      deserter("Listen to that. It's the worst sound in the world, and I could listen to it all night."),
      { when = "hid_dream", steps = {
        deserter("You never did give us an answer, down there at the wheel. That's all right. You needn't tell me anything until you're ready. I've just been noticing, that's all."),
      } },
      ask(cleric("Go to sleep, both of you. I'll sit up with them. I generally do."),  {
        topic("What's it like when she takes someone?", {
          cleric("Quiet, mostly. People expect her to be cruel, and she isn't. She just doesn't look away. I've tried to learn that, and it's harder than the praying."),
        }),
        topic("Doctor, what will you do about the seal?", {
          deserter("Read it again, in the morning, and hope it says something else. Then I'm going to find the person who pressed it, friend, and I'd like to be wrong when I do."),
        }),
        { "Goodnight.", {
          cleric("Goodnight. I'll be here. For what it's worth, you've done some good today, and I don't say that to many people."),
        } },
        { "Wake me if anyone needs me.", {
          cleric("I will. It's a kind thought. Oddly, I think you'd be the easiest person in the world to wake."),
        } },
      }),
      t("You lie down. You know what happens next. Nothing does."),
      { fade = true },
      t("Far to the north-east, in Adaphis, a high room in the Cranial District. One lamp."),
      t("On the desk, a clerk's report. SCYTHEBREAK. CLEAN RESULT: ONE. SUBJECT ABSENT."),
      t("Beside it, an old book lies open at a place where pages have been torn out. A woman in a physician's grey reads the report through to the end, and then reads one word of it for a long time."),
      t('"Everyone dreams," says Doctor Colette, to no one. "They simply haven\'t been asked properly."'),
      t("Her hand moves to the book, the way a hand moves to an old wound."),
      { fade = true },
      { set = "finished" },
      { big = "THE ROAD EAST IS OPEN" },
    }, other = {
      { when = "mine_pass", steps = {
        { when = "cleric_in", steps = {
          mayor("Back already, tall ones? And I see you've brought nobody with you. Nobody at all, and she's looking tired. The bottom of the mine, if you please. I'd come myself, but I've a speech to finish."),
        }, other = {
          mayor("The bottom of the mine, tall ones. Take the road east out of town to the first big hole, and show the warden your chit. I'd come myself, but I've a speech to finish."),
        } },
      }, other = {
        mayor("...and in CONCLUSION, which I have now reached twice... oh! Visitors! Tall ones! Ottilie Brasscap, Mayor, sixty years unopposed. You'll forgive the lamps. We've a small difficulty."),
        mayor("We have a mine, and we had a deep shift in it, forty gnomes. Twelve days ago they stopped sending up coal, and then the second-level men started coming up with a look on them."),
        mayor("They'd drop off, you see, and they'd wake up wrong. Or they wouldn't. And then whoever was sat next to them would have a bad night too. So we stopped. Sleeping, I mean, as a town. It went to a vote."),
        ask(mayor("Carried, with one abstention, and he never woke. Now, you've the look of people with questions. Everyone's got questions. I've got a speech."), {
          topic("Did you send to the Clinic?", {
            deserter("That was going to be mine. Speaking purely as a herbalist, did you?"),
            mayor("Eleven letters, doctor... herbalist, was it? They sent back a form asking how many of us there are. They're very interested in the number. They've sent no doctor."),
          }),
          topic("What was the deep shift doing?", {
            mayor("Opening the new seam, under the Foreman, a very sound gnome who has never been late in his life. He stopped reporting the same day the coal did. I'd sooner not think about that."),
          }),
          topic("Who's looking after the sick?", {
            mayor("Nobody. Absolutely nobody. There is no cleric down there, I want that clearly understood. The Clinic burns people for that, and nobody is treating anybody on the first level."),
            t("The Mayor winks. It takes her a moment to get the eye open again."),
          }),
          { "We'll go down and see.", {
            mayor("I've no right to ask it, but you've the look of people with nowhere better to be. Bless you. I'll see you're paid."),
          } },
          { "We'd do it for nothing.", {
            mayor("Would you, now? Do you know, nobody has said a thing like that in this office in sixty years. I'm going to have to sit down. No! No, I'm not!"),
            { set = "pledged_free" },
          } },
        }),
        { when = "pledged_free", steps = {}, other = {
          { choice = {
            { "Good. Glad that's agreed.", {} },
            { "What's it worth to you?", {
              mayor("Everything, and also about two hundred gold, which is everything. We'll see you right. I shall minute that you asked."),
              { set = "haggled_mayor" },
            } },
          } },
        } },
        mayor("Here's a chit for the warden at the pit. It says that you're authorised, and it also says that you're responsible. I'd read the second part carefully."),
        mayor("And if you should happen not to meet anyone on the first level, because there's nobody there, you might tell her we're out of bandages."),
        { set = "mine_pass" },
      } },
    } },
  } },
}

S.talk_innkeeper = {
  { when = "finished", steps = {
    t("The innkeeper is asleep on the stairs, smiling, with a key in each hand."),
  }, other = {
    { when = "first_night", steps = {
      innkeeper("Back again! Forty beds, and yours is the only one that's been slept in for nine days. I've left it just as it was. I go up and look at it sometimes."),
      ask(innkeeper("It's twenty gold a bed, and I look the other way, and you never saw me. What'll it be?"), {
        topic("Who hasn't been down to breakfast?", {
          innkeeper("I keep count. It's a habit, thirty years in this trade. There were nineteen regulars at my table a fortnight ago, and now there's seven. I still lay the nineteen places."),
        }),
        { "A bed, please. (20 gold)", {
          { inn = 20 },
          { save = true },
        } },
        { "Something from the kitchen stores.", {
          { shop = "orrenshire_goods" },
        } },
        { "Not now.", {} },
      }),
    }, other = {
      innkeeper("Welcome to the Feather and Pick! Forty beds, the best in the Heart, and I've not had a soul in one of them for nine days. I still turn them all down at night. You've got to have something to do."),
      innkeeper("Ordinance Forty's for residents, mind, and you're visitors. So the first night's on the house, and I'll tell you honestly, it's just so that I can watch someone do it."),
      { choice = {
        { "That's very kind. Thank you.", {
          innkeeper("Kind nothing. I'll be on the landing, listening to you breathe. It's the nearest thing I've had to a holiday."),
        } },
        { "Is it safe to sleep here?", {
          innkeeper("I couldn't tell you, my love. Safe's not what it was. But it's clean, and it's yours, and your friend there can shake you if you start to mutter."),
        } },
      } },
      { fade = true },
      { heal = true },
      { save = true },
      t("You sleep. There is nothing. Then there is morning."),
      deserter("You didn't move all night. I checked. It's an old habit. I've sat up with thousands of sleepers, and they twitch, they mutter, their eyes go back and forth. You just stop, friend. Like a clock."),
      { choice = {
        { "Is that bad?", {
          deserter("I don't know. It's probably nothing. I've spent a long time learning what a sleeper looks like, and I'd just never seen that. Forget I said anything."),
        } },
        { "Maybe I'm just good at it.", {
          deserter("Maybe you are. It'd be a fine thing to be good at, in this town. Forget I said anything."),
        } },
        { "Were you watching me sleep?", {
          deserter("Professionally. Yes, I heard how that sounded. I'll work on my manner, it's one of the reasons I left."),
        } },
      } },
      { set = "first_night" },
    } },
  } },
}

S.talk_smith = {
  { when = "finished", steps = {
    t("The forge has gone out for the first time in living memory. The smith is asleep against the anvil, in a beard like a bolster."),
    { when = "admired_art", steps = {
      { shop = "orrenshire_friend" },
    }, other = {
      { shop = "orrenshire" },
    } },
  }, other = {
    smith("Forged in the mountain and tested on my brother-in-law. Nine days without sleep and I'm doing the best work of my life, so what do you need?"),
    ask(smith("Mind that one on the bench. It's a sword with two handles and no blade. It's art."), {
      topic("What was the Foreman like?", {
        smith("Last I saw of him he came in for hinges, a fortnight back. Very polite, very neat, and he paid in new coin. I remember thinking it was the first time I'd ever seen him without coal on him."),
      }),
      topic("It's magnificent. What's it for?", {
        smith("For? Hah! Nobody's ever... you've got an eye, you have. It's for looking at, and then for feeling slightly worse. Tell you what, anything off this wall is cheaper for you. Don't tell my brother-in-law."),
        { set = "admired_art" },
      }),
      { "Show me what you've got.", {
        { when = "admired_art", steps = {
          { shop = "orrenshire_friend" },
        }, other = {
          { shop = "orrenshire" },
        } },
      } },
      { "That's all.", {} },
    }),
  } },
}

S.talk_chair = {
  { when = "foreman_down", steps = {
    { when = "finished", steps = {
      t("The Chair is asleep at the Wakefulness Engine. Every ninety seconds the small mallet comes down on his head, and every time he smiles a little."),
    }, other = {
      gnome("The Committee for Staying Awake is pleased to announce that it has met its goals and is dissolving itself. I may have a small lie down. On the mallet. It's how I've come to think of myself."),
    } },
  }, other = {
    gnome("Welcome to the Committee for Staying Awake! I am the Chair. I'd offer you a chair, but that's how it starts."),
    gnome("Behold the Wakefulness Engine! Every ninety seconds a small mallet strikes the operator upon the head. It has struck me eleven thousand times, and I've never felt more... there's a word. There's a word for how I am."),
    { when = "mallet_tried", steps = {
      gnome("Back for another go? No? Very wise. Very... was it Tuesday?"),
    }, other = {
      ask(gnome("Would you care to try it? Visitors are entitled to one free blow."), {
        topic("Does it actually work?", {
          gnome("Nobody who's used it has fallen asleep. Three have fallen over. The Committee has ruled that this counts as a different thing, and we've minuted it very carefully."),
        }),
        { "Go on, then.", {
          { sfx = "hit" },
          t("It's a very small mallet. It is not a very small pain."),
          gnome("Excellent! You look terrible! That's a Committee record for a visitor! Have a tonic, you've earned it. It's mostly chicory and fear."),
          { give = "tonic", n = 1 },
          { set = "mallet_tried" },
        } },
        { "No, thank you.", {
          gnome("Coward! Oh, I am sorry, that's the mallet talking. Do come back."),
        } },
      }),
    } },
  } },
}

S.talk_ledger = {
  { when = "finished", steps = {
    t("The ledger gnome is asleep on the ledger, and the ink has made a small map on one cheek. You leave a note of your own."),
    { save = true },
  }, other = {
    ask(gnome("Would you care to sign the visitors' ledger? It's a comfort to know somebody wrote you down. It's how we found out we'd lost the deep shift."),  {
      topic("Who else has signed it lately?", {
        gnome("Nobody much. There was a very polite gentleman a month back, who wanted to see the lower workings. His handwriting was lovely. He signed as 'Inspector', and I remember thinking that isn't a name."),
      }),
      { "I'll sign.", {
        { save = true },
        gnome("Noted. Should you die, we'll know where to send the bill."),
      } },
      { "Not now.", {} },
    }),
  } },
}

S.talk_frog = {
  { when = "frog_wet", steps = {
    bogg("Ahhh. A new frog. A happier frog. I shan't forget you, tall one. I forget most things, I'll admit, but I keep a list, and you're on the good side of it."),
  }, other = {
    { when = "frog_bucket", steps = {
      t("You upend the bucket over the head in the stocks. It closes its enormous eyes."),
      bogg("Oh, that's the stuff. That's the good mud-water. There's a bit of a newt in that, and I don't mind who knows it."),
      bogg("Honour among redistributors, then. Left boot. No, MY left boot. There."),
      t("From somewhere in his left boot he produces a small glass ether, slightly warm."),
      { give = "ether", n = 1 },
      { when = "rude_frog", steps = {
        bogg("And that's in spite of what you said earlier, which I've written down. I took that off a wizard in Hayford. It makes you a receiver of stolen goods. Welcome to the profession."),
      }, other = {
        bogg("I took that off a wizard in Hayford, and now it's yours, which makes you a receiver of stolen goods. Welcome to the profession. There's a lovely pension, if you don't get caught."),
      } },
      { set = "frog_wet" },
    }, other = {
      { when = "frog_met", steps = {
        bogg("Still crisp, tall one. The bucket's at the well. I can hear myself curling up at the edges."),
      }, other = {
        t("A frog folk, a large one, stands in the town stocks with his chin on the plank. He wears a very good hat that doesn't fit."),
        bogg("Psst. Tall one. Gentleman Bogg, of the Hayford Swamp, at your service. Don't let the stocks deceive you, I'm only here for the company."),
        bogg("They found me on the road with eleven sacks of barley, a duck, and the hat of the Mayor of Hayford. I want you to know that I can explain two of those."),
        ask(bogg("Now, a frog must stay damp, and nobody in this town can lift a bucket any more. I'm going crisp. Fetch me one from the well, there's a good tall one."), {
          topic("What exactly are you?", {
            bogg("I am what you'd call a redistributor. There's a great deal of barley in Hayford and very little in the swamp, and I've made it my life's work to redistribute it to me."),
          }),
          topic("Which two can you explain?", {
            bogg("The barley was a gift from the people of Hayford, in the sense that they failed to stop me. And the duck is a friend. I've no idea about the hat. I woke up in it, in a manner of speaking."),
          }),
          { "All right. One bucket.", {
            bogg("A marvel! A marvel among the tall! I'll be right here. I want that clearly understood. I shall not move."),
          } },
          { "Dry up, you thief.", {
            bogg("Dry up! Oh, that's very good. That's cruel, and it's also funny, which is the worst kind. The well's still there if you've a change of heart."),
            { set = "rude_frog" },
          } },
        }),
        { set = "frog_met" },
      } },
    } },
  } },
}

S.talk_stocks = {
  { when = "finished", steps = {
    t("The gnome who minds the stocks is asleep across them, with his chin where the plank used to be."),
    { when = "frog_wet", steps = {
      t("A note is pinned to his coat, addressed to 'the tall one with the bucket'. It says 'Owed: one favour. Do not tell the duck.'"),
    } },
  }, other = {
    gnome("He was right here. The stocks are still locked, I've checked them, I've checked them several times. And my hat's gone too, and so has the plank."),
    { when = "frog_wet", steps = {
      gnome("There was a note, addressed to 'the tall one with the bucket'. It says 'Owed: one favour. Do not tell the duck.' I've no idea what that means, and I've filed it."),
    } },
    { choice = {
      { "How do you lose a plank?", {
        gnome("Slowly! And with a great many witnesses, all of whom had been awake for eleven days! I've had statements! One of them's about a horse!"),
      } },
      { "I'm sure he'll turn up.", {
        gnome("That's what I'm afraid of."),
      } },
    } },
  } },
}

S.talk_well = {
  { when = "finished", steps = {
    t("Asleep, sitting up, with one arm around the well like an old friend."),
  }, other = {
    { when = "foreman_down", steps = {
      gnome("They've come up, did you hear? I'm still shouting at myself, out of habit. If you're after a bucket, you've missed that frog. He's gone from the stocks, plank and all, and he still owes me a duck."),
    }, other = {
      { when = "frog_met", steps = {
        { when = "frog_bucket", steps = {
          gnome("I'd go easy with that water. It's got a newt in it. It had a newt in it. Has he got the newt? He owes me for a duck as it is."),
        }, other = {
          gnome("For the frog, is it? He owes me a duck. Go on, then, I can't lift it. I tried on Monday, and I was very brave, and it was not enough."),
          t("You haul up a full bucket. It weighs about as much as the gnome."),
          { set = "frog_bucket" },
        } },
      }, other = {
        gnome("I dropped off on the windlass yesterday, just for one second, and shouted at myself. I was very firm about it. I felt quite let down."),
        { choice = {
          { "Sounds like you did the right thing.", {
            gnome("That's what I told myself, but I wasn't really listening."),
          } },
          { "How long can you keep this up?", {
            gnome("As long as it takes! Which I'm told is not very long. There's a fellow in Pick Lane started talking to his boots on the eighth day. They've been very supportive."),
          } },
        } },
      } },
    } },
  } },
}

S.talk_pip = {
  { when = "pip_done", steps = {
    pip("Mum's asleep, and she's snoring. It's the best thing I ever heard. I'm going to go and watch her do it some more."),
  }, other = {
    { when = "foreman_down", steps = {
      { when = "have_lamp", steps = {
        pip("That's her lamp! That's the green stripe! She came up, she came up on the lift, and she's asking who has her lamp!"),
        pip("She said she dreamed she was walking down and down, and then somebody came through and stopped it. It was you, wasn't it? I said it was you."),
        pip("Here, these are for you, and so is this. It's my best thing. It's a very good stone."),
        { give = "potion", n = 2 },
        t("It's two potions, and a very good stone."),
        { choice = {
          { "Keep the stone. Look after her.", {
            pip("All right. But it's still yours. I'll just mind it for you."),
          } },
          { "It's a very good stone. Thank you.", {
            pip("I know. I told you."),
          } },
        } },
        { set = "pip_done" },
      }, other = {
        pip("My mum came up! She was on the deep shift, and she came up on the lift! She left her lamp down there, the one with the green stripe, and she says it can stay there. That's all right. She's got me."),
      } },
    }, other = {
      { when = "lamp_ask", steps = {
        { when = "have_lamp", steps = {
          t("The lamp is in your pack. You find you can't take it out, not until there's someone to give it back to."),
          pip("You've been down. You've got the look. Don't tell me. Just keep looking."),
        }, other = {
          pip("It's got a green stripe. She painted it herself, so that nobody would take it by accident. It's a bit crooked, but you're not allowed to say so."),
        } },
      }, other = {
        pip("My mum's on the deep shift. The Mayor says they've just gone on a long one. I'm six, I'm not stupid."),
        ask(pip("If you go down, her lamp has a green stripe. You don't have to bring her. Only if you see it."), {
          topic("Who's looking after you?", {
            pip("Me. And the Mayor comes by and tells me I'm very brave, and she gives me a biscuit. I think she's only got the one sentence left. It's a good biscuit."),
          }),
          { "I'll find it. I promise.", {
            pip("Don't promise. Everybody promises. Just look."),
          } },
          { "I can't promise anything.", {
            pip("Good. Thank you. You're the first one who's said that."),
          } },
        }),
        { set = "lamp_ask" },
      } },
    } },
  } },
}

-- ---------------------------------------------------------------- the first level

S.talk_warden = {
  { when = "mine_pass", steps = {
    gnome("Chit. Stamped, and countersigned by the Mayor, by the Mayor, and by me, apparently. I don't remember that, but it's a good signature, so that's all in order."),
    { choice = {
      { "What should we expect down there?", {
        gnome("Rats you could saddle, and worse below. Anything that used to be a friend of yours, don't stop to catch up. Mind the floor. It's down."),
      } },
      { "Thank you, warden.", {
        gnome("You're the first who ever has. Mind the floor. It's down."),
      } },
    } },
    { set = "warden_ok" },
  }, other = {
    gnome("Nobody goes below without a chit from the Mayor. I don't care how tall you are. I've been awake for nine days, and I'll bite your knee."),
    { choice = {
      { "Where do I find the Mayor?", {
        gnome("In the town, in her hall on the square, making a speech. Follow the sound of someone concluding."),
      } },
      { "All right, all right.", {} },
    } },
  } },
}

S.scene_cleric = {
  t("The side gallery has been swept. Gnomes lie on clean sacking in careful rows, and each has a black thread tied at the wrist."),
  cleric("Stop there, and mind your boots. That one has only just stopped shaking, and I'd like to keep it that way."),
  t("The woman kneeling among them doesn't turn round. Her eyes are shut. You get the feeling this makes no difference."),
  cleric("Lavender and boiled linen. I know that smell. The last time it came through a door of mine, it took the door with it, and everyone behind it."),
  deserter("Formerly of the Clinic. I cut the badge off."),
  cleric("I've buried a lot of people who were formerly something."),
  deserter("A Thread Weaver, here, under their noses. They'd burn you for that, sister."),
  cleric("Eventually. There's a form first."),
  { choice = {
    { "We're not here for you. We're here for the mine.", {
      cleric("Then you're the first who's come down here for anyone but themselves. Let me look at you."),
    } },
    { "The Mayor says she's out of bandages.", {
      cleric("Is there one gnome in that town who can keep a secret? No, don't answer. Tell her I've been boiling my own. Let me look at you."),
    } },
    { "The doctor's with me. Leave them be.", {
      cleric("Are they, now? You've an odd way of choosing friends. I do too, as it happens. Let me look at you."),
      { set = "vouched_doctor" },
    } },
  } },
  t("She rises and takes your wrist, without asking, the way you'd check a loaf. For a moment she says nothing at all."),
  ask(cleric("The Raven Queen's work is mostly noticing. Every life is a thread, and a sleeper's goes slack and wanders off. Yours doesn't look as if it has ever wandered anywhere."), {
    topic("What does that mean?", {
      cleric("I don't know. I'm saying that honestly, and I don't often have to. How strange. Have you been sleeping?"),
      t("She lets go, and doesn't explain."),
    }),
    topic("Who are these people?", {
      cleric("Second-level men, mostly, and their wives. The ones who stayed awake too long and fell, or fell asleep and came back wrong. I tie a thread on so they'll have something to hold, and so she'll know where to find them."),
    }),
    { "Whatever's doing this, we'll find it.", {
      cleric("Three more came up yesterday, and it's getting worse. Whatever is doing this is at the bottom."),
    } },
  }),
  { when = "vouched_doctor", steps = {
    deserter("You needn't have done that, you know. Spoken up for me. It's been a while. I'd forgotten what to do with my face."),
  } },
  cleric("I'm coming with you. Those who can't wake will keep, they've got better at waiting than I have. Don't thank me. She has a list, and I'd like to see who's next on it."),
  { join = "cleric", lvl = 3 },
  { set = "cleric_in" },
}

S.talk_nurse = {
  gnome("Sister left me in charge. Sit down. Sit, I said, not lie! There, now drink this, and don't dream, and don't tell me anything you've seen, I've got enough of my own."),
  { heal = true },
  t("The party is rested."),
  { choice = {
    { "Thanks. Hold on up here.", {
      gnome("Holding on's what we do. It's mostly what mining is, when you come down to it."),
    } },
    { "How are they doing?", {
      { when = "foreman_down", steps = {
        gnome("Most of them got up and walked out, complaining. Loveliest thing I ever heard. The ones who are left are the same, and that's good news, these days."),
      }, other = {
        gnome("They're the same. That's good news, these days. Nobody tell them it's not."),
      } },
    } },
  } },
}

S.talk_sick = {
  { when = "foreman_down", steps = {
    t("Most of the sacking is empty now, with a black thread folded on each. This one holds someone from the deep shift who didn't wake. The eyes have stopped moving."),
  }, other = {
    t("Asleep, or something like it. The eyes move back and forth under the lids, all in the same direction, all together."),
  } },
}

S.talk_nib = {
  { when = "lift_free", steps = {
    { when = "blamed_nib", steps = {
      nib("Oh, it's you, the one who said it was my turn. Fine. Brake's off, and I'm a professional. Going down?"),
    }, other = {
      nib("Brake's off! You're a marvel. Going down? Tell him it was still his turn, and that I've got it in writing."),
    } },
    { choice = {
      { "Down to the deep seam.", {
        { warp = { "mine_3", 2, 13, 2 } },
      } },
      { "Not yet.", {} },
    } },
  }, other = {
    nib("The lift's stuck. Nob's got the brake on at the bottom, and he won't take it off till I say it was my turn. Twelve days we've been at it, down this speaking tube. Nob! NOB! Tell them whose turn it was!"),
    t("From a brass tube in the rock, very faint, a small voice says something rude."),
    ask(nib("You see what I have to work with? If you're going down there, tell him to take the brake off. Otherwise it's the stairs for you. So whose turn was it?"), {
      topic("Turn at what?", {
        nib("To go up and get the sandwiches, on the day it all went bad. If he'd gone, he'd have been up here with me, and I could keep an eye on him. Not that I'm worried. I'm furious."),
      }),
      { "I'll talk to him.", {
        nib("You do that. Be firm. He's a very small gnome, but he's got a great big sulk on him."),
      } },
      { "Sounds like it was your turn, Nib.", {
        nib("MY TURN! Whose side are you... who even are you? Go on, get out of my lift. Not in it. Near it."),
        { set = "blamed_nib" },
      } },
    }),
  } },
}

-- ---------------------------------------------------------------- the second level

S.talk_logkeeper = {
  ask(gnome("Sign the shift log? Whoever signs in gets counted out. That's the rule, and it's a very comforting rule."),  {
    topic("Is it safe ahead?", {
      { when = "gas_off", steps = {
        gnome("Safer. The long drift's stopped smelling of pears, and I've you to thank for that, I'm told. I've written it down as a fan fault. You don't want to be in the book for a thing like that."),
      }, other = {
        gnome("Not the long drift, east of here. Stay out of it if you can. It's full of sweetdamp, and a fortnight ago it wasn't. It smells of pears."),
        gnome("We sent a canary down. The canary had a lovely nap, and when it woke up it was not what you would call a canary."),
      } },
    }),
    { "I'll sign.", {
      { save = true },
      gnome("Noted. That's you in the book, and you're counted. Don't make a liar of me."),
    } },
    { "Not now.", {} },
  }),
}

S.scene_gas = {
  { when = "gas_met", steps = {
    t("They lie where they fell, breathing slowly. The doctor is frowning in their sleep. The sister isn't. You can't carry them both past the sweetness, and it's only getting thicker."),
    t("Something creaks, far down the drift."),
  }, other = {
    t("The air in the long drift turns sweet. Pears, and something under the pears."),
    deserter("That's no damp. I know that smell. Friend, hold your breath, that's Clinic sopor, and it isn't meant to be anywhere near..."),
    t("The doctor sits down quite carefully, and does not get up."),
    cleric("Oh. Oh, the threads. They're all going slack..."),
    t("You catch the sister's lamp before it hits the floor. You wait for your own eyes to close."),
    t("They don't."),
    ask({ text = "They're both breathing. Far down the drift, something is creaking in a draught." }, {
      topic("Shake the doctor.", {
        t("The doctor's head rolls on your arm. There's a small frown, and that's all. Nobody is home, and whoever's out is not coming back for you."),
      }),
      topic("Call to the sister.", {
        t("Your voice goes a little way along the drift and lies down. Her hand is closed around the black thread, and it stays closed."),
      }),
      { "Go on alone.", {} },
    }),
    { set = "gas_met" },
  } },
}

S.scene_gas_mid = {
  t("The sweetness lies on your tongue and does nothing at all. In the lamplight the air has a colour now. It seems to lean away from you as you walk."),
  { set = "gas_mid" },
}

S.scene_valve = {
  t("A gnome sits slumped at a great iron wheel, smiling in his sleep. Above him a pipe runs into the rock, and a grey cask is strapped to it, with Clinic stencils."),
  ask({ text = "His hands are on the wheel. He must have nearly made it." }, {
    topic("Try to wake him.", {
      t("He smiles a little wider, and says something polite to someone you can't see."),
    }),
    { "Turn the wheel.", {
      t("You lift his hands away, and set yours on the iron."),
    } },
  }),
  { sfx = "door" },
  { big = "THE VENTS OPEN" },
  t("Somewhere above, fans start to turn. The air comes down the drift cold and clean and smelling of nothing."),
  { fade = true },
  { set = "gas_off" },
  deserter("How long was I... who turned that? Who's been... oh."),
  cleric("You walked through that. All that way, on your own, with your eyes open."),
  deserter("Nobody walks through that. I've handled sopor in gloves. It doesn't put a person to sleep so much as drag them down into whatever they dream."),
  cleric("So what happened to you?"),
  { choice = {
    { "I don't dream.", {
      cleric("No. No, I don't suppose you do."),
    } },
    { "I don't know.", {
      cleric("No. I don't suppose you do."),
      { set = "hid_dream" },
    } },
    { "Does it matter? It's off now.", {
      cleric("It might. But you're right, it can wait. Most things can, in my line of work."),
      { set = "hid_dream" },
    } },
  } },
  t("Water drips somewhere for a while."),
  { when = "doubted_deserter", steps = {
    deserter("You asked me at the cell door how you'd know this wasn't a test. I've been wondering the same about you, friend, and I still think we should go on together."),
  } },
  deserter("Let's talk about it when we're not standing in it. That cask has our old stencil on it, sister. I mean mine. I mean theirs."),
  t("The gnome at the wheel is still smiling. The sister ties a black thread at his wrist, and you all go on."),
}

-- ---------------------------------------------------------------- the deep seam

S.talk_nob = {
  { when = "lift_free", steps = {
    { when = "blamed_nib", steps = {
      nob("You told him it was his turn? You really told him? You're my favourite tall person. Going up?"),
    }, other = {
      nob("Going up? I'm not saying whose turn it was. I'm just saying that I'm going up, and that I'll be taking the sandwiches."),
    } },
    { choice = {
      { "Stay down here.", {} },
      { "Up to the first level.", {
        { warp = { "mine_1", 16, 14, 4 } },
      } },
    } },
  }, other = {
    t("A very small gnome is wedged in the back of the lift cage with a shovel across his knees."),
    nob("Are you real? Say something only a real person would say. No, don't, it would know that too."),
    ask(nob("I saw the Foreman go by. He went by the way a coat goes by on a hook. Did Nib send you? It was HIS turn. You can tell him that."), {
      topic("What did the Foreman do?", {
        nob("He walked the whole shift down the drift, in a line, and he was reading out their names. They all answered. They were asleep. I've been sat in here ever since with this shovel."),
      }),
      topic("Are you all right in there?", {
        nob("I've got a shovel and half a sandwich, and I've stopped shaking twice. So I'd say I'm doing better than anyone else on this level. Thanks for asking. Nib wouldn't."),
      }),
      { "Take the brake off, Nob.", {
        nob("Fine. FINE. But that's only because you're tall and I'm frightened, and not because it was my turn."),
        { sfx = "door" },
        t("Chains shudder away up the shaft. The lift is free: Nob and Nib can carry you between here and the first level."),
        { set = "lift_free" },
      } },
      { "Leave him be.", {} },
    }),
  } },
}

S.scene_deep_shift = {
  t("The great hall of the deep seam. Lamps still burn along the walls. Below them, the deep shift lies in rows, tools beside them, as neatly as if someone had counted them down."),
  cleric("They're alive. All of them, every one. Oh, you poor loves."),
  deserter("That isn't sleep, sister. It's a dosage. Somebody worked out how much it would take, and then wrote it down."),
  t("Forty gnomes breathe in and out together. You have heard that sound before, through a wall."),
  { set = "saw_shift" },
  { choice = {
    { "Can you help them?", {
      cleric("Not while whatever's doing this is still going. I could sit with them. I've sat with a lot of people. Let's go and stop it instead, for a change."),
    } },
    { "I've heard this before. In Scythebreak.", {
      deserter("So have I. I'd hoped you hadn't noticed. It's the same breath, friend. I don't know what that means, and I don't care to guess in here."),
    } },
    { "Keep moving.", {
      cleric("Yes. They'd say the same, if they could. Gnomes have no patience with people who stop to look at the work."),
    } },
  } },
}

S.talk_sleeper = {
  t("Fast asleep, with lips moving. They're all saying the same thing, but it isn't a word yet."),
}

S.talk_lampwoman = {
  { when = "have_lamp", steps = {
    t("She sleeps on, one hand open where the lamp was."),
  }, other = {
    { when = "lamp_ask", steps = {
      t("A lamp stands by this one's hand, burning low. It has a green stripe, carefully painted, and only slightly crooked."),
      { choice = {
        { "Take the lamp for Pip.", {
          t("You take it, and turn the wick down. The sister looks at you for a moment, and then away."),
          { set = "have_lamp" },
        } },
        { "Leave it with her for now.", {
          t("It's the one thing down here that's hers. You leave it burning. You can always come back."),
        } },
      } },
    }, other = {
      t("A gnome in a patched coat. A lamp burns by her hand, with a green stripe painted on it."),
    } },
  } },
}

S.scene_last_lamp = {
  { when = "boss_warned", steps = {}, other = {
    t("One lamp still burns here, in a niche in the rock, and someone has left a flask beside it. You can hear scratching further on. It sounds a lot like a pen."),
    { choice = {
      { "Everyone ready?", {
        deserter("No. But I've got all my fingers and most of a plan, and that's the best I've managed in some years. Whatever's ahead, let's meet it in good order."),
      } },
      { "Sister, say something.", {
        cleric("She knows where we are. That's all I've got, and it's less of a comfort than it sounds. It's still more than most people have. Go on."),
      } },
    } },
    { set = "boss_warned" },
  } },
  { save = true },
}

S.scene_foreman = {
  { when = "met_foreman", steps = {
    foreman("Back on shift, are we? I've docked you for the time. It's all here on the list, {hero}. Clock in."),
  }, other = {
    t("The gallery opens out. Grey casks stand stacked in neat shift order, each one with a chalk tally."),
    t("At the far end a very small figure in a very good waistcoat is checking a very long list."),
    foreman("Late. You're late. The shift started twelve days ago, and I shall have to dock you. There's not been a word of complaint from my deep shift, you know. Everybody sleeping so well. Best figures in the history of the seam."),
    cleric("Foreman, they've been lying there for twelve days."),
    ask(foreman("Rest, you see. That's all they ever wanted. Have you come about the casks?"), {
      topic("Who gave you these casks?", {
        foreman("A very polite gentleman, with a very clean form. I signed for them. It was all in order. Vent at the end of the shift, he said, and everyone rests easy."),
        foreman("I wasn't to breathe it myself. But you do. You do get curious. Oh, you get a lot of things."),
      }),
      topic("Do you know what you've done?", {
        foreman("Everything on the list. I've never missed an item in thirty-one years. There's a great many items now. They come in the night, and they're in my own hand."),
      }),
      { "It's over, Foreman. Let them go.", {
        foreman("Let them go? But they've only just started. Nobody clocks off till the whistle."),
      } },
      { "Put down the list. Now.", {
        foreman("I can't do that. I've tried. It's what I'm holding on with."),
      } },
    }),
    t("He looks up from the list, and his head goes on tilting a little after it should have stopped."),
    foreman("Oh."),
    foreman("Oh, there you are. It said you'd be along. I've got you on the books, {hero}, right at the top. The longest shift of anyone, and you've never once clocked in."),
    deserter("Friend, who is he talking to?"),
    foreman("Clock in, {hero}. Everybody clocks in. CLOCK IN!"),
    { set = "met_foreman" },
  } },
  { battle = "boss_foreman" },
  { set = "foreman_down" },
  t("The Foreman sits down among his casks. Whatever was wearing him goes out of him all at once, and what's left is a small old gnome, very tired."),
  foreman("Did they make quota?"),
  { choice = {
    { "They did. Every one.", {
      cleric("You heard. Every one, Foreman. You can clock off now."),
    } },
    { "Forty gnomes, and you ask that?", {
      cleric("Leave him be. It isn't him that's asking any more. Yes, Foreman, they did. You can clock off now."),
    } },
  } },
  t("She ties the black thread at his wrist. Then she stays a moment longer than she needs to."),
  t("Folded inside his waistcoat is a sheet of good paper, with a seal in black wax."),
  deserter("'Orrenshire, deep seam. Casks to be vented at end of shift. Subjects must sleep for the strain to take. Record onset. Record spread to surface.'"),
  deserter("'Do not treat.' That's underlined. Such a neat hand."),
  cleric("So they sent this here. It didn't come up out of the mountain. Somebody sent it, in casks, and asked to be told how it went."),
  t("The doctor has gone very still, thumb on the seal. A raven, with a lancet in its beak."),
  deserter("That's on my commission. It's on everyone's. It's Doctor Colette's own seal, and she doesn't lend it."),
  ask(deserter("She taught my year. I once saw her sit up three nights with a dying charwoman, and nobody made her do it."), {
    topic("What was the test at Scythebreak, then?", {
      deserter("I've been trying very hard not to ask that. They told us it only showed what was there. If this paper's true, I don't know what I've been carrying round in that bag."),
    }),
    { "Then someone has stolen it.", {
      deserter("Then someone has stolen it. Yes. Let's say that."),
    } },
    { "You know what this looks like.", {
      cleric("Leave it for now. Someone has stolen it, doctor. That's what we'll say until we know better."),
      deserter("Yes. Let's say that."),
    } },
  }),
  t("Behind you, down the long hall, somebody coughs. Then somebody else. Someone starts, very quietly, to cry. It's the most wonderful sound you've heard in days."),
  { fade = true },
  { warp = { "orrenshire", 12, 9, 2 } },
  { set = "lift_free" }, -- whoever took the stairs: the brake is off now, or nobody could have come up in it
  t("It takes all that day to bring them up, in the lift, a few at a time. Nib and Nob work the cage without a word. Then they have a word."),
  t("The Mayor will want to see that paper."),
}

-- ---------------------------------------------------------------- more of Scythebreak

S.talk_lioth = {
  { when = "tested", steps = {
    t("Mistress Lioth lies with her thin hands moving, as if turning pages. Whatever the book is, she doesn't seem to like how it ends. She has read it before."),
  }, other = {
    { when = "lockdown", steps = {
      { when = "heard_evrastin", steps = {
        lioth("I came through one gate on a list, {hero}, and I've been waiting ever since to find out about the second. Watch this doctor's hands. In Agoshull the ones who were lying always kept them so very still."),
      }, other = {
        lioth("I've stood in this queue before, at a different gate, with a different nice young man. You drink what you're given, and you remember your name for as long as they let you."),
      } },
      { choice = {
        { "What happened at the other gate?", {
          lioth("I lived, and that's the whole of the story. I've been apologising for it ever since."),
        } },
        { "We'll be all right, Mistress.", {
          lioth("That's very kind. I taught for thirty years, and I always gave a little credit for kindness. Not full marks."),
        } },
      } },
    }, other = {
      lioth("Those boots will want soles by winter, and no, I don't do it for love. I was once a lecturer at the Ultimatum in Agoshull, with four hundred students and a chair of my own. Now I've got a last and a hammer."),
      ask(lioth("You'll have heard of it, I suppose? Nobody here has. Sit down if you want, and mind the tacks. I don't mind being asked. Nobody does."), {
        topic("What was Agoshull like?", {
          lioth("Towers, child, a whole city of them, and everyone in them arguing. You could get a good word for a wizard on any street, and a bad one for the next. It was the happiest noise I ever heard."),
        }),
        topic("I came from Evrastin, they say.", {
          lioth("Did you? City of crystals, and the great lighthouse. They were very interested in the mind there. They brought something home that they couldn't get out of it, and put it to bed to see if it would go away."),
          lioth("You've a look of... no. It's nothing. I've read too many books and buried too many friends. Mind the tacks."),
          { set = "heard_evrastin" },
        }),
        topic("How did you get out?", {
          lioth("On a list. Somebody thought I might be useful, and somebody else was not on that list. I've never learned who. I think of that person whenever I sit down to eat."),
        }),
        { "Thanks, Mistress. I'll bring the boots.", {
          lioth("Do. It's the only thing anyone's asked me to fix in years that can be fixed."),
        } },
      }),
    } },
  } },
}

S.talk_satchel = {
  { when = "tested", steps = {
    t("A small man with a satchel stands in the empty square at midnight, counting the doors. He looks at you, looks at the doctor, and looks at his list."),
    satchel("I've got nobody down for this. There's no form for a patient and an officer leaving at night, so as far as I can tell it isn't happening. I wonder if you'd mind not happening a little faster."),
    { choice = {
      { "You never saw us.", {
        satchel("I never see anybody. It's the whole of my training. Good evening."),
      } },
      { "How can you stand it here?", {
        satchel("I count. It's quite restful, if you keep it to the numbers. The numbers have all been very good."),
      } },
    } },
    deserter("I've met a hundred of him. I used to be afraid of the soldiers. It's the ones with satchels who scare me now."),
  }, other = {
    { when = "lockdown", steps = {
      satchel("Four hundred and eleven, four hundred and twelve. You're four hundred and twelve. Please don't move, I've only just got you written down."),
      { choice = {
        { "Who wants the number?", {
          satchel("Adaphis. Everyone asks that. They want it very promptly, which I'll admit I find a little odd. It's usually such a slow office."),
        } },
        { "My name's {hero}, not a number.", {
          satchel("Of course it is. That goes in the other column. It's a much narrower column."),
        } },
      } },
    }, other = {
      satchel("Good morning. Don't mind me. I'm only here from the Records Office, for the quarterly count. I make sure that the pages in the Book add up to the people in the town."),
      ask(satchel("Have you been counted yet? You'll want to say yes. It's less trouble."), {
        topic("What's the count for?", {
          satchel("I couldn't say. I'm only told how many, never why. But I've done this for sixteen years, and I'll tell you what I've noticed. It's lately become the only thing they ever write back about."),
        }),
        { "Yes. I've been counted.", {
          satchel("Lovely. So you have. You're a great help."),
        } },
        { "Count me twice. I'm worth it.", {
          satchel("I'm afraid that's fraud. It's a pleasant change to be asked, though."),
        } },
      }),
    } },
  } },
}

S.talk_chalker = {
  chalker("Good day. Do excuse me, I'm just doing your neighbour's door. It's only so that we know who's been seen. There's no need to read anything into a tally."),
  { choice = {
    { "What do the marks mean?", {
      chalker("One stroke for each person in the house. Then, when they're home again, we rub one out. It's very simple. So far I've not been asked to bring a cloth."),
    } },
    { "Leave Nan's door alone.", {
      chalker("I'm afraid it's done already. It's a lovely door. It wants oiling."),
    } },
  } },
}

-- ---------------------------------------------------------------- more of Orrenshire

S.talk_hatter = {
  { when = "finished", steps = {
    t("Tibble is asleep sitting up, in nine hats. There's a tenth on the way down."),
  }, other = {
    tibble("Hats! Fine hats! Hats for all occasions, though there's only been the one occasion for a fortnight. That frog they put in the stocks is wearing the finest thing I ever made, and I want you to know I sold it to the Mayor of Hayford in good faith."),
    { when = "wore_hat", steps = {
      tibble("And look at you in that hat! It's terrible on you! It's the best thing I've seen all week. Wear it in good health."),
    }, other = {
      ask(tibble("A person's head is their own affair, but yours, if I may say so, is a public concern. It's very tall. It's out where people can see it."), {
        topic("Who buys hats in a mine town?", {
          tibble("Everyone, once! A gnome's got one hat for the pit and one for his funeral, and I've been told that's a bad joke this month. I sold six funeral hats last week, and I've stopped keeping them in the window."),
        }),
        { "Go on, then. Find me a hat.", {
          tibble("At last! This is a Hat of Some Standing, made for a very large gnome who didn't live to collect it. Take it, take it. I can't sell it. I want to see one tall person walking about in a thing I made."),
          t("It sits on the top of your head like a bird that hasn't decided. The doctor looks at it for some time, and says nothing, kindly."),
          { set = "wore_hat" },
        } },
        { "I'll keep my head as it is.", {
          tibble("That's what they said in Evrastin! I don't know what that means. I've been awake for nine days."),
        } },
      }),
    } },
  } },
}

-- Her prices depend on what you did to her nephew.
local SILT_TRAY = {
  { when = "frog_wet", steps = {
    { shop = "frog_family" },
  }, other = {
    { when = "rude_frog", steps = {
      { shop = "frog_markup" },
    }, other = {
      { shop = "frog_goods" },
    } },
  } },
}

S.talk_silt = {
  { when = "finished", steps = {
    t("Mother Silt sits with her eyes open and her mouth a little ajar. She may be asleep. Frog folk are hard to tell. There's a sign on her tray: HONEST PRICES, ASK ME HOW."),
    { when = "frog_met", steps = SILT_TRAY, other = {
      { shop = "frog_goods" },
    } },
  }, other = {
    { when = "frog_wet", steps = {
      silt("So you're the tall one who wet our Bogg. He's a fool, and he's my sister's boy, and he's been dry a long time. Anyone who'd carry a bucket for that frog can have the family rate."),
    }, other = {
      { when = "rude_frog", steps = {
        silt("You're the tall one who told our Bogg to dry up. He laughed about it for an hour. I've marked you up. Business is business."),
      }, other = {
        silt("Mother Silt, of the Hayford Swamp, licensed peddler, and you'll note I said licensed. It's a very good licence. The person it belonged to has no more use for it."),
      } },
    } },
    ask(silt("Everything on this tray fell off something. Potions and such, slightly damp. What'll it be, dear?"), {
      topic("Are you with that frog?", {
        { when = "foreman_down", steps = {
          silt("I've never seen him before in my life, and he's my nephew. If he's slipped out of those stocks, dear, I was here at this tray the whole time, and I can show you a licence that says so."),
        }, other = {
          silt("I've never seen him before in my life, and he's my nephew. I've come to collect him when the town has stopped looking. These people haven't closed their eyes in nine days, so it's turning into a very long wait."),
        } },
      }),
      topic("What's it like in the swamp?", {
        silt("Wet, dear, and honest about it. Hayford calls us thieves, and they worship Mammon. We've just cut out the middle man. The whole of Hayford's got its hand in someone's pocket, and we're the ones who get called slippery."),
      }),
      { "Show me the tray.", SILT_TRAY },
      { "No, thank you.", {
        silt("Your loss, dear. It generally is."),
      } },
    }),
  } },
}

S.talk_bascombe = {
  { when = "finished", steps = {
    { when = "nudged_clerk", steps = {
      t("Clerk Bascombe has gone home to bed for the first time in eleven years. His drawer is empty and very tidy. On the desk is a report to Adaphis, marked ORRENSHIRE: NOTHING TO REPORT."),
    }, other = {
      t("Clerk Bascombe is asleep on the drawer, one arm round it, keeping it shut."),
    } },
  }, other = {
    bascombe("Clerk Bascombe, Clinic Liaison, Orrenshire. Population one, if you count only those who've ever read a thing I've sent. I expect you're here about the drawer. Nobody's ever here about the drawer."),
    deserter("Say nothing about me, friend. I know that kind of coat. He won't know mine. Not with the badge off."),
    { when = "foreman_down", steps = {
      { when = "nudged_clerk", steps = {
        bascombe("I read the Mayor's letters. All eleven. I've had to go and stand in the yard for a while. A form came in this morning asking for numbers from Orrenshire. I find I've mislaid it."),
      }, other = {
        bascombe("There's a very polite request from Adaphis for a count of the town. It's the fourth this month. I shall answer it. I always do. It's only a number."),
      } },
    }, other = {
      ask(bascombe("I've eleven letters from the Mayor in here. I don't read them. I stamp them and put them in the drawer, and I've got eleven years' worth of drawer."), {
        topic("Doesn't anyone come to check on you?", {
          bascombe("An inspector came last month, very polite, and he asked after the mine. It was the first time in eleven years that anybody's asked me anything. I gave him tea. I thought it was going rather well."),
        }),
        { "You could read them, you know.", {
          bascombe("I could. I've been told that's not the procedure. I've been told a good many things. Leave it with me. I expect it's nothing."),
          { set = "nudged_clerk" },
        } },
        { "Keep up the good work.", {
          bascombe("I shall. That's the terrible thing."),
        } },
      }),
    } },
  } },
}

-- ---------------------------------------------------------------- more of the mine

S.talk_propsetter = {
  propsetter("Mind your head. No, the other head. I'm the prop-setter, and I've been holding up the first level on my own since the crew stopped coming. You'd be amazed how much of a mine is just someone refusing to let it fall."),
  { choice = {
    { "Why are you still down here?", {
      propsetter("Because a roof doesn't care if you've got a sickness in the town. A roof wants a prop every six feet. I find that very restful, in a way. It's the only thing in Orrenshire that's still got its priorities straight."),
    } },
    { "Is it safe further down?", {
      propsetter("The timber is. I set it myself. Whatever's walking about on it, I wouldn't like to say. Some of them were my crew. They still nod, going by."),
    } },
    { "Thank you for holding it up.", {
      { when = "thanked_props", steps = {
        propsetter("That's twice. Don't go soft on me, I've a roof to mind."),
      }, other = {
        propsetter("Hah! That's a first. Take this, then, I've been carrying it about for a month, and it does my back no good."),
        { give = "potion", n = 1 },
        { set = "thanked_props" },
      } },
    } },
  } },
}

S.talk_dunnock = {
  t("A prop has come down across a passage. There's a miner under it, wedged by one leg, in the dark, whistling very quietly through his teeth."),
  dunnock("Don't mind me. I'm only whistling so I'll know I'm awake. Dunnock's the name, second level, and I've been lying here since the day before yesterday, or thereabouts. There's nobody to shout at me but me."),
  ask(dunnock("If you've a moment and a strong back, that beam would be a kindness. If you haven't, I'd take a bit of company. I'm not fussy any more."), {
    topic("What brought the prop down?", {
      dunnock("Somebody walked into it. One of the lads, one who used to be a lad. He didn't stop, you know. He went into it and through it, and on down the drift, with his eyes shut."),
    }),
    { "Lift the beam.", {
      t("It takes everything you've got, and it comes up slowly. He pulls himself out on his elbows, grey in the face, and gets his breath."),
      dunnock("That's the finest thing that's ever been done to me. Here, take this, I was saving it for the walk home. I'll see you up top, if there's a top."),
      { give = "ether", n = 1 },
      { set = "freed_dunnock" },
    } },
    { "Not yet. Hold on.", {
      dunnock("Right you are. I'll be here. I've got a very full diary."),
    } },
  }),
}

S.talk_dunnock_up = {
  { when = "finished", steps = {
    t("Dunnock is asleep on the bench with his bad leg up on a crate and a pipe gone out in his hand. He's whistling, very quietly, in his sleep."),
  }, other = {
    dunnock("There's the tall one. Look at me, sat in the sun like a lord! They say the leg will mend. You tell anyone who asks that Dunnock of the second level owes you a drink, and that he's good for it."),
    { choice = {
      { "How's the leg?", {
        dunnock("Attached, which is the main thing. I'm told I'll always know when it's going to rain, and it's a mining town, so that's a skill I'll get no use from at all."),
      } },
      { "Stay out of the deep seam.", {
        dunnock("You needn't tell me twice. I'm taking up hens."),
      } },
    } },
  } },
}

S.talk_handlers = {
  t("Two big men in grey leather sit on upturned casks, playing cards by a shaded lamp. They wear masks with glass eyes. One of them slowly takes his off."),
  handler("Oh, thank goodness, are you the relief? We've been down here three weeks. We just bring the casks and hook them up and sign. They said not to take the masks off till the wheel was turned, and I see it's been turned, so that's us done."),
  handler("I've got a family in Blackpool, and I never asked what was in it. I'll say that to anyone. Never once."),
  deserter("Handlers. They hire them off the Blackpool docks, by the day. I've signed their chits. They'd have the same look on them if it was cheese."),
  ask(handler("We don't want any trouble. We've a card game going."), {
    topic("Who do you work for?", {
      handler("A polite gentleman, with a satchel. He had a form for everything. He never said Clinic, and we never asked why all the casks had a stencil. It's very good money, that's all I know."),
    }),
    topic("Do you know what's in those casks?", {
      handler("Something for the damp, they said. Then the gnomes all lay down, so I've started to think it might not be for the damp. You can stop looking at me like that. I've worked it out for myself. It took me a while."),
    }),
    { "Get out of here. Go home.", {
      handler("Yes. Yes, I think so. Right, come on, leave the cards."),
      { set = "spared_handlers" },
    } },
    { "You'll stand in front of the Mayor for this.", {
      handler("Fair enough. Fair enough, I suppose. Would there be a chair?"),
      { set = "held_handlers" },
    } },
  }),
  { set = "handlers_gone" },
}

-- ---------------------------------------------------------------- shops

-- Prices are party.lua's, so a shop and a treasure agree on what a thing is worth. The friend's prices are for those who
-- admire the art.
M.SHOPS.orrenshire = {
  { item = "shortsword", price = 60 },
  { item = "miners_pick", price = 130 },
  { item = "leathers", price = 50 },
  { item = "ringmail", price = 120 },
  { item = "robe", price = 15 },
}

M.SHOPS.orrenshire_friend = {
  { item = "shortsword", price = 50 },
  { item = "miners_pick", price = 110 },
  { item = "leathers", price = 42 },
  { item = "ringmail", price = 100 },
  { item = "robe", price = 12 },
}

M.SHOPS.orrenshire_goods = {
  { item = "potion", price = 12 },
  { item = "antidote", price = 8 },
  { item = "tonic", price = 30 },
  { item = "ether", price = 40 },
}

-- Mother Silt's tray: the family rate if you watered her nephew, a little over if you told him to dry up.
M.SHOPS.frog_goods = {
  { item = "potion", price = 12 },
  { item = "antidote", price = 8 },
  { item = "ether", price = 40 },
}

M.SHOPS.frog_family = {
  { item = "potion", price = 10 },
  { item = "antidote", price = 6 },
  { item = "ether", price = 32 },
}

M.SHOPS.frog_markup = {
  { item = "potion", price = 14 },
  { item = "antidote", price = 10 },
  { item = "ether", price = 46 },
}

-- ---------------------------------------------------------------- the road

-- The closed places on the overworld. Each opens with a flag, in overworld.GATES, so these only ever say why not yet.
S.gate_portal = { t("The Nevermore Portal stands shut, a gate the size of a hillside. The sentries won't look at you. There's more to do in the Heart first.") }
S.gate_verdant = { t("The grass here is taller than the party, and it moves against the wind. Nobody goes in without a reason. You'll want to know what you're looking for.") }
S.gate_crevice = { t("The pass is cracked from side to side, and the outpost above it has its lamps lit. Without a reason to be here, you'd be climbing it for nothing.") }
S.gate_thuluan = { t("The road ends in black ice and reeds. Nobody sane goes further without being sent.") }
S.gate_crack = { t("The wall has a crack in it here, and something breathes in it. Without something to guard your mind, you won't come out the same.") }
S.gate_abyss = { t("The Violet Abyss. The light goes down a long way and doesn't come back. Not yet.") }

-- ---------------------------------------------------------------- the rest of the game

--- A shop written as a tier is that tier's standard stock, with any extras after it.
local function shopFrom(def)
  if not def.tier then return def end
  local list = {}
  for _, ware in ipairs(require("games.blightmare.party").SHOP_TIERS[def.tier] or {}) do list[#list + 1] = ware end
  for _, ware in ipairs(def.extra or {}) do list[#list + 1] = ware end
  return list
end

for _, region in ipairs(require("games.blightmare.content").regions()) do
  for id, script in pairs(region.scripts or {}) do S[id] = script end
  for id, shop in pairs(region.shops or {}) do M.SHOPS[id] = shopFrom(shop) end
  for _, goal in ipairs(region.goals or {}) do M.GOALS[#M.GOALS + 1] = goal end
end

return M
