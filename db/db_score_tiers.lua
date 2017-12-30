local _, ns = ...
ns.scoreTiers = {
  [1] = {
    ["score"] = 6000,
    ["color"] = { 1.00, 0.53, 0.00 } -- 6000+ #ff8800 |cffff88006000+|r
  },
  [2] = {
    ["score"] = 5600,
    ["color"] = { 0.93, 0.44, 0.18 } -- 5600+ #ec712f |cffec712f5600+|r
  },
  [3] = {
    ["score"] = 5200,
    ["color"] = { 0.85, 0.38, 0.37 } -- 5200+ #da625f |cffda625f5200+|r
  },
  [4] = {
    ["score"] = 4800,
    ["color"] = { 0.78, 0.33, 0.56 } -- 4800+ #c7538e |cffc7538e4800+|r
  },
  [5] = {
    ["score"] = 4400,
    ["color"] = { 0.71, 0.27, 0.75 } -- 4400+ #b544be |cffb544be4400+|r
  },
  [6] = {
    ["score"] = 4000,
    ["color"] = { 0.64, 0.21, 0.93 } -- 4000+ #a335ee |cffa335ee4000+|r
  },
  [7] = {
    ["score"] = 3600,
    ["color"] = { 0.51, 0.25, 0.92 } -- 3600+ #8240ea |cff8240ea3600+|r
  },
  [8] = {
    ["score"] = 3200,
    ["color"] = { 0.38, 0.30, 0.91 } -- 3200+ #614ce7 |cff614ce73200+|r
  },
  [9] = {
    ["score"] = 2900,
    ["color"] = { 0.25, 0.35, 0.89 } -- 2900+ #4158e3 |cff4158e32900+|r
  },
  [10] = {
    ["score"] = 2600,
    ["color"] = { 0.13, 0.39, 0.88 } -- 2600+ #2064e0 |cff2064e02600+|r
  },
  [11] = {
    ["score"] = 2300,
    ["color"] = { 0.00, 0.44, 0.87 } -- 2300+ #0070dd |cff0070dd2300+|r
  },
  [12] = {
    ["score"] = 2000,
    ["color"] = { 0.02, 0.55, 0.69 } -- 2000+ #068cb0 |cff068cb02000+|r
  },
  [13] = {
    ["score"] = 1750,
    ["color"] = { 0.05, 0.66, 0.52 } -- 1750+ #0ca984 |cff0ca9841750+|r
  },
  [14] = {
    ["score"] = 1500,
    ["color"] = { 0.07, 0.77, 0.35 } -- 1500+ #12c558 |cff12c5581500+|r
  },
  [15] = {
    ["score"] = 1250,
    ["color"] = { 0.09, 0.89, 0.17 } -- 1250+ #18e22c |cff18e22c1250+|r
  },
  [16] = {
    ["score"] = 1000,
    ["color"] = { 0.12, 1.00, 0.00 } -- 1000+ #1eff00 |cff1eff001000+|r
  },
  [17] = {
    ["score"] = 900,
    ["color"] = { 0.29, 1.00, 0.20 } -- 900+ #4bff33 |cff4bff33900+|r
  },
  [18] = {
    ["score"] = 800,
    ["color"] = { 0.47, 1.00, 0.40 } -- 800+ #78ff66 |cff78ff66800+|r
  },
  [19] = {
    ["score"] = 700,
    ["color"] = { 0.65, 1.00, 0.60 } -- 700+ #a5ff99 |cffa5ff99700+|r
  },
  [20] = {
    ["score"] = 600,
    ["color"] = { 0.82, 1.00, 0.80 } -- 600+ #d2ffcc |cffd2ffcc600+|r
  },
  [21] = {
    ["score"] = 500,
    ["color"] = { 1.00, 1.00, 1.00 } -- 500+ #ffffff |cffffffff500+|r
  },
}

-- Simple "Color Blind" (standard quality) mode
ns.scoreTiersSimple = {
  [1] = {
    ["score"] = 4000,
    ["quality"] = 5
  },
  [2] = {
    ["score"] = 3000,
    ["quality"] = 4
  },
  [3] = {
    ["score"] = 2000,
    ["quality"] = 3
  },
  [4] = {
    ["score"] = 1000,
    ["quality"] = 2
  },
  [5] = {
    ["score"] = 500,
    ["quality"] = 1
  }
}

-- Dungeon listing sorted by id
ns.dungeons = {
  [1] = {
    ["id"] = 7546,
    ["name"] = "Neltharion's Lair",
    ["shortName"] = "NL"
  },
  [2] = {
    ["id"] = 7672,
    ["name"] = "Halls of Valor",
    ["shortName"] = "HOV"
  },
  [3] = {
    ["id"] = 7673,
    ["name"] = "Darkheart Thicket",
    ["shortName"] = "DHT"
  },
  [4] = {
    ["id"] = 7787,
    ["name"] = "Vault of the Wardens",
    ["shortName"] = "VOTW"
  },
  [5] = {
    ["id"] = 7805,
    ["name"] = "Black Rook Hold",
    ["shortName"] = "BRH"
  },
  [6] = {
    ["id"] = 7812,
    ["name"] = "Maw of Souls",
    ["shortName"] = "MOS"
  },
  [7] = {
    ["id"] = 7855,
    ["name"] = "The Arcway",
    ["shortName"] = "ARC"
  },
  [8] = {
    ["id"] = 8040,
    ["name"] = "Eye of Azshara",
    ["shortName"] = "EOA"
  },
  [9] = {
    ["id"] = 8079,
    ["name"] = "Court of Stars",
    ["shortName"] = "COS"
  },
  [10] = {
    ["id"] = 8527,
    ["name"] = "Cathedral of Eternal Night",
    ["shortName"] = "COEN"
  },
  [11] = {
    ["id"] = 8910,
    ["name"] = "Seat of the Triumvirate",
    ["shortName"] = "SEAT"
  },
  [12] = {
    ["id"] = 999998,
    ["name"] = "Return to Karazhan: Lower",
    ["shortName"] = "LOWR"
  },
  [13] = {
    ["id"] = 999999,
    ["name"] = "Return to Karazhan: Upper",
    ["shortName"] = "UPPR"
  }
}