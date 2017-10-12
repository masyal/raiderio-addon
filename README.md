# Raider.IO

Provides you with an easy way to view Raider.IO Mythic+ Scores in-game.

Simply hover over a player with your mouse, your guild roster, or even the Group Finder list where you see queued people; if they have a score you'll see it on their tooltip.

# Getting started

The easiest way is to use the Twitch client over at Curse to get your addon up-to-date. Install it, then start your game. The next step is to then open the addons dialog at the character selection screen and making sure you only enable your own region, and the factions you wish to be able to lookup in-game. If you attempt to load the wrong region, it will be automatically disabled and the memory freed, so don't worry if you keep everything enabled and load in, but you might experience a slower loading screen the first time on that character.

# Options

Type ``/raiderio`` to open the Raider.IO options frame. You can also find a shortcut in the Interface/AddOn settings frame, just scroll down on the addon list, click Raider.IO then click the button to open the config frame.

Here you can easily enable or disable various features and behavior, including the region and faction addons that are loaded for your character. Remember to click Save to save the changes, or Cancel to abort and close the dialog.

# Updates

We'll upload nightly builds with updated databases over players and their scores. Simply use the Twitch client to update the addon, and you'll update the scores as well.

# API

Addon developers can utilize the ``RaiderIO`` table to access certain API provided by this addon.

Use this function to retrieve a profile for a specific unit, or by using a name and realm, and optionally provide a faction (1 for Alliance, 2 for Horde) for a quicker lookup.

  ``RaiderIO.GetScore(unit)``

  ``RaiderIO.GetScore("Name-Realm"[, nil, 1|2])``

  ``RaiderIO.GetScore("Name", "Realm"[, 1|2])``

The following table is returned if there are results, otherwise nil:

  ``{ region = "eu|us...|", faction = 1|2, date = "2001-12-31T12:00:00Z", season = "Season 7.2.5", prevSeason = "Season 7.2.0", name = "Name", realm = "Realm", allScore = number, prevAllScore = number, tankScore = number, healScore = number, dpsScore = number, isTank = boolean, isHealer = boolean, isDPS = boolean, numRoles = number }``

Use this function to retrieve the color scheme for a given score.

  ``RaiderIO.GetScoreColor(number)``

The following arguments are returned in the 0-1 range:

  ``r, g, b``
