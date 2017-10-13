# Raider.IO Mythic Plus

This is a companion addon to go along with the Raid and Mythic+ Rankings site, Raider.IO: https://raider.io. With this addon installed, you'll gain access to an easy way to view the Mythic Keystone scores for players-- all without leaving the game!

Simply hover over a player with your mouse, your guild roster, or even the Group Finder list where you see queued people; if they have a score you'll see it on their tooltip.

Additionally, you can right-click players from the standard target unit frame to `Copy Raider.IO URL` and then easily look up their full profile on the site.

If you have run into any problems, check out our FAQ at https://raider.io/faq, or join us on Discord at: https://discord.gg/jxpbvDy -- we always have people around willing to help.

# Getting Started

The easiest way to get started is to download the Twitch Desktop App at: https://app.twitch.tv/download, and then search for the "Raider.IO Mythic Plus" addon and install it.

Once installed you can just load into the game and you will start seeing scores on players around you. Do note that there are some limitations on the scores you see:

The addon stores a snapshot of player data that is updated nightly. Each night the database will include all players that meet this criteria:

- Have earned at least 500 points in the current or previous Mythic+ season
- Have logged in to the game within the past 30 days

We'll upload nightly builds with updated databases over players and their scores. Simply use the Twitch client to download the latest version of the addon, which will always contain the latest scores.

# Configuring the AddOn

Our recommended settings are enabled by default, but we've provided several options to customize how and where the tooltips might show while in-game. Type ``/raiderio`` to open the Raider.IO options frame. Alternatively, you can also find a shortcut in the ``Interface > AddOn`` settings frame.

Here you can easily enable or disable various features, including whether to show scores from each faction, and various tooltip customization options.

_Remember to click Save to save the changes, or Cancel to abort and close the dialog._

# Developer API

We love our fellow developers! We wanted to provide anyone in the community a simple way to tap into the scores that are a part of this addon. Addon developers can do this by utilizing the ``RaiderIO`` table to access certain APIs we provide.

Use this function to retrieve a profile for a specific unit, or by using a name and realm, and optionally provide a faction (1 for Alliance, 2 for Horde) for a quicker lookup.

### RaiderIO.GetScore

Retrieve Mythic+ Scores for a given unit/player:

  ``RaiderIO.GetScore(unit)``

  ``RaiderIO.GetScore("Name-Realm"[, nil, 1|2])``

  ``RaiderIO.GetScore("Name", "Realm"[, 1|2])``

The following table is returned if there are results, otherwise nil:

```
{
  region = "us" | "eu" | "kr" | "tw",
  faction = 1|2,
  date = "2001-12-31T12:00:00Z",
  season = "Season 7.2.5",
  prevSeason = "Season 7.2.0",
  name = "Name",
  realm = "Realm",
  allScore = number,
  prevAllScore = number,
  tankScore = number,
  healScore = number,
  dpsScore = number,
  isTank = boolean,
  isHealer = boolean,
  isDPS = boolean,
  numRoles = number
}
```

### RaiderIO.GetScoreColor

Retrieve the color to use when rendering the given score value.

``RaiderIO.GetScoreColor(number)``

This will return a tuple of r/g/b values in the 0-1 range:

```
r, g, b
```
