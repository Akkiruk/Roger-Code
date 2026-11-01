-- games/oregon/text.lua
-- Everything the trail says: names, epitaphs, what the landmarks look like and what people will tell you. Plain lists,
-- kept apart from the rules so neither has to scroll past the other. Rules pick from these with their own rng.

local M = {}

-- period names for the four who aren't the player
M.NAMES = {
  "Ezra", "Mary", "Josiah", "Hannah", "Silas", "Abigail", "Amos", "Sarah", "Caleb", "Martha", "Elias", "Rebecca",
  "Jedediah", "Prudence", "Obadiah", "Temperance", "Thaddeus", "Lavinia", "Hiram", "Mercy", "Zebulon", "Charity",
}

-- under the name on the stone
M.CAUSES = {
  dysentery = "Dysentery", typhoid = "Typhoid", cholera = "Cholera", measles = "Measles", snakebite = "A snake",
  ["broken arm"] = "A broken arm", starvation = "Want of food", exhaustion = "Exhaustion", cold = "The cold", drowned = "The river",
}

M.EPITAPHS = {
  "Asked how much farther once too often.",
  "Should have taken the ferry.",
  "Left the wagon. Took the blame.",
  "Paid in full, Matt's store excepted.",
  "Gone ahead to look for grass.",
  "Died as lived: behind schedule.",
  "Never did see Oregon. Heard it's damp.",
  "Rest here. The oxen won't.",
  "A good walker, for a while.",
  "Traveled light. Now lighter.",
  "Here, at least, the road is level.",
  "Would have preferred Missouri.",
  "Ate last, complained first.",
  "Blessed are the meek. The trail is not.",
  "Not lost. Merely stopped.",
  "Two thousand miles was a bit much.",
}

M.ARRIVE = {
  kearney = "Soldiers, sod walls and prices that climb with the miles. The Platte runs wide and shallow from here.",
  chimney = "A spire of clay you have been able to see for two days. It looks no closer than it did. It is, slightly.",
  laramie = "The last real walls for a long while. Mend what you can. Buy what you can bear to pay for.",
  rock = "Half the country has carved a name on it. You are meant to reach it by the Fourth of July.",
  southpass = "So gentle a climb that you might miss the top of the Rockies. The waters run west from here. The trail divides.",
  bridger = "A blacksmith, a trading post and Jim Bridger's opinions, all of which come at a price.",
  soda = "The springs fizz like beer and taste like nails. Some drink it anyway.",
  hall = "A Hudson's Bay post. The Snake lies ahead, and a good many people's patience ends here.",
  boise = "A small mud fort on the Snake, and glad of the company.",
  blue = "Pines at last, steep ones, and the wagon must go over them. The trail divides again.",
  wallawalla = "A post on the Columbia. Your family's boots are now mostly a matter of opinion.",
  dalles = "The road ends at the rock and the river. Ahead lie the Cascades: float them, or pay to go around.",
}

M.FORK_TITLE = {
  southpass = "The trail divides",
  blue = "The trail divides",
  dalles = "The last choice",
}

M.FORK_SAY = {
  southpass = {
    "Fort Bridger: 125 miles to the fort, with a store, then 100 on to the Green.",
    "The Sublette Cutoff: 160 miles straight for the Green, and 50 of them with no water at all.",
  },
  blue = {
    "Fort Walla Walla: 55 miles to the fort and 111 on to The Dalles.",
    "The Dalles: 120 miles straight there, with no store on the way.",
  },
  dalles = {
    "The Columbia: a raft, a hundred miles, four days if the rapids allow it. Goods and people go overboard.",
    "The Barlow Road: a toll of $15 and a hundred miles of mud around Mount Hood. Slow, and snow comes early.",
  },
}

-- what people will tell you, by the last place you passed. All of it is true of the game
M.TALK = {
  independence = {
    "A drover, spitting: \"Three yoke at the least. A wagon doesn't pull itself, whatever the fellow at the store says.\"",
    "A widow: \"Leave in April. Sooner there's no grass. Later there's snow on the Blues.\"",
  },
  kansas = { "A ferryman: \"Over two and a half feet she wets the goods. Over three she takes them.\"" },
  bigblue = {
    "An old hand: \"No ferry on the Blue. A shallow river will ground a caulked wagon, mind. Float the deep ones.\"",
  },
  kearney = {
    "A corporal: \"Boil your water or don't. Cholera has no opinion.\"",
    "A sutler: \"Everything's dearer west of here. Everything. I'd know.\"",
  },
  chimney = {
    "A woman mending a shirt: \"Bison on these plains, and more meat than any one soul can carry. A hundred pounds and you're done.\"",
  },
  laramie = {
    "A trapper: \"Buy spare parts here. Nobody ever whittled an axle and felt good about it.\"",
    "A Lakota trader, in fair English: \"You people walk a long way to be unhappy.\"",
  },
  rock = { "A guide: \"Late July here and you're fine. Late August and you'd better own warm clothes.\"" },
  southpass = {
    "A surveyor: \"The cutoff saves you sixty-five miles and costs you an ox or two.\"",
    "A mule packer: \"Snow by October up here. It doesn't ask.\"",
  },
  bridger = {
    "Jim Bridger, or so he says: \"I've seen a petrified bird singing a petrified song. The Green's still deeper.\"",
  },
  green = {
    "A Mormon ferryman: \"Pay me or pay the river. I'm cheaper.\"",
  },
  soda = {
    "A man by the spring: \"Rest a few days when the sickness comes. Walking it off is how you get a stone.\"",
  },
  hall = { "A trader: \"Shoshone will ferry you over the Snake for a price. It's not a river to argue with.\"" },
  snake = { "A traveler with one wagon wheel: \"Don't ask.\"" },
  boise = {
    "A clerk: \"Short rations will carry you farther. Bare bones will carry you to the graveyard.\"",
  },
  blue = {
    "A wagoner: \"Lock your wheels going down and don't take the pace too hard. It only feels like the end.\"",
  },
  wallawalla = {
    "A missionary: \"The Barlow Road is slower and the river is quicker. Choose which you fear the less.\"",
  },
  dalles = {
    "A raftsman: \"Mostly they make it.\" He did not say how much of them.",
  },
}

-- for anywhere
M.TALK_ANY = {
  "A woman walking beside her wagon: \"Grueling pace gets you there sooner. The ones it gets there.\"",
  "A farmer: \"Meager rations and a steady pace. That's how my father did it, and he only lost the one mule.\"",
  "A preacher: \"The Lord provides.\" He then asked if you could spare some bacon.",
  "A child: \"Are we there yet?\" You are not.",
  "A trader: \"Two sets of clothes each, or the cold finds you. It finds you anyway. But later.\"",
}

return M
