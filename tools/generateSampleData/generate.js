const moment = require('moment');
const fs = require('fs');
const Faker = require('faker');
const _ = require('lodash');

function fixupRealmName(name) {
  return name.replace(/[\- ]/g, '');
}

if (process.argv.length !== 3) {
  console.log(`Usage: ${process.argv[0]} <CHARACTERS PER REALM>`);
  process.exit(1);
}

const TOTAL_ENTRIES_TO_MAKE = parseInt(process.argv[2], 10);
if (TOTAL_ENTRIES_TO_MAKE <= 0 || isNaN(TOTAL_ENTRIES_TO_MAKE)) {
  console.log('Entries must be a positive integer');
  process.exit(1);
}

const TOTAL_ENTRIES_PER_FACTION = TOTAL_ENTRIES_TO_MAKE / 2;

console.log(`Generating ${TOTAL_ENTRIES_TO_MAKE} total characters per region ${TOTAL_ENTRIES_PER_FACTION} per faction`);

const REALMS_PER_REGION = {
  us: 246,
  eu: 267,
  kr: 18,
  tw: 25,
};

try {
  fs.mkdirSync('./sample-data');
} catch (e) {
  /* do nothing */
}

const REALMS = {};
const NUM_LOOKUP_FIELDS = 2;

for (const [region, numRealms] of _.toPairs(REALMS_PER_REGION)) {
  REALMS[region] = _.range(numRealms).reduce((acc, itme) => {
    acc[Faker.address.country()] = {
      horde: [],
      alliance: []
    };
    return acc;
  }, {});

  // distribute the entries across the realms
  const numEntriesPerRealm = Math.ceil(TOTAL_ENTRIES_PER_FACTION / numRealms);
  for (const realm of Object.keys(REALMS[region])) {
    for (const faction of ['alliance', 'horde']) {
      REALMS[region][realm][faction] = _.times(numEntriesPerRealm, () => {
        return _.capitalize((Faker.name.firstName() + Faker.name.lastName()).toLowerCase())
      }).sort();
    }
  }

  for (const factionId of [1, 2]) {
    const lookup = [];
    const factionSlug = factionId === 1 ? 'alliance' : 'horde';
    const sharedFields = `name=...,`
        + `region="${region}",`
        + `faction=${factionId},`
        + `date="${moment.utc().format()}",`
        + `season="season-7.3.0",`
        + `prevSeason="season-7.2.5",`;

    //
    // Characters
    //
    const characterFileName = `./sample-data/db_${region}_${factionSlug}_characters.lua`;
    console.log('Writing', characterFileName, '...');
    const fChar = fs.openSync(characterFileName, 'w');
    fs.writeSync(fChar, `RaiderIO.AddProvider({`
      + sharedFields
      + `db${factionId}={`);

    let lookupIndex = 0;

    _.toPairs(REALMS[region]).forEach(([realm, factionData], rcIndex) => {
      const characters = factionData[factionSlug];
      fs.writeSync(fChar, (rcIndex > 0 ? ',' : '') + `["${fixupRealmName(realm)}"]={${NUM_LOOKUP_FIELDS * lookupIndex},`);

      characters.forEach((info, chIndex) => {
        lookup.push(Faker.random.number());
        lookup.push(Faker.random.number());
      });

      fs.writeSync(fChar, characters.map((a) => `"${a}"`).join(','));

      fs.writeSync(fChar, `}`);

      lookupIndex += characters.length;
    });

    fs.writeSync(fChar, '}})\n');
    fs.closeSync(fChar);

    //
    // Lookup Table
    //
    const lookupFileName = `./sample-data/db_${region}_${factionSlug}_lookup.lua`;
    console.log('Writing', lookupFileName, '...');
    const fLookup = fs.openSync(lookupFileName, 'w');
    fs.writeSync(fLookup, `RaiderIO.AddProvider({`
                  + sharedFields
                  + `lookup${factionId}={`);
    fs.writeSync(fLookup, lookup.join(','));
    fs.writeSync(fLookup, '}})\n');
    fs.closeSync(fLookup);
  }
}
