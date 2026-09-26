// Generates sql/penal-codes.sql from the book below.
//
// Codes read  PC <title>.<section> <subsection>  — PC 1.34 A is title 1,
// section 34, subsection A. Sections are padded to two digits so a plain
// string sort still puts 1.09 before 1.10.
//
// Titles:
//   1  Offences Against Persons
//   2  Offences Against Property
//   3  Offences Against Public Order
//   4  Controlled Substances
//   5  Vehicle and Traffic
//   6  Weapons and Explosives
//   7  Offences Against the Government
//
// A row is [section, subsection, name, class, fine, jail]. Subsection is null
// when the section has only one offence in it. Jail time is in minutes, which
// is what the arrest panel adds up.
//
// Run after editing:   node tools/build-penal.mjs
import { writeFileSync } from 'node:fs';

const F = 'felony', M = 'misdemeanor', I = 'infraction';

const BOOK = [
  ['Offences Against Persons', [
    [ 1, 'A', 'Murder in the First Degree',                    F, 0,     150],
    [ 1, 'B', 'Murder in the Second Degree',                   F, 0,     110],
    [ 2, null, 'Attempted Murder',                             F, 0,      75],
    [ 3, 'A', 'Voluntary Manslaughter',                        F, 0,      60],
    [ 3, 'B', 'Involuntary Manslaughter',                      F, 5000,   40],
    [ 4, null, 'Vehicular Manslaughter',                       F, 7500,   45],
    [ 5, 'A', 'Assault',                                       M, 1000,    8],
    [ 5, 'B', 'Assault on a Peace Officer',                    F, 4000,   30],
    [ 5, 'C', 'Assault with a Deadly Weapon',                  F, 5000,   40],
    [ 6, 'A', 'Battery',                                       M, 1500,   10],
    [ 6, 'B', 'Battery on a Peace Officer',                    F, 4500,   30],
    [ 6, 'C', 'Battery Causing Serious Bodily Injury',         F, 6000,   45],
    [ 7, 'A', 'Kidnapping',                                    F, 0,      60],
    [ 7, 'B', 'Kidnapping for Ransom',                         F, 0,      90],
    [ 8, null, 'False Imprisonment',                           M, 2500,   15],
    [ 9, null, 'Criminal Threats',                             M, 2000,   12],
    [10, null, 'Stalking',                                     M, 2500,   15],
    [11, null, 'Harassment',                                   M, 1000,    5],
    [12, null, 'Hostage Taking',                               F, 0,      75],
    [13, null, 'Torture',                                      F, 0,      90],
    [14, null, 'Domestic Violence',                            M, 3000,   20],
    [15, null, 'Child Endangerment',                           F, 5000,   35],
    [16, null, 'Elder Abuse',                                  F, 5000,   35],
    [17, null, 'Reckless Endangerment',                        M, 2000,   12],
    [18, null, 'Assault with Intent to Commit a Felony',       F, 5000,   40],
    [19, null, 'Mayhem',                                       F, 6000,   50],
    [20, null, 'Poisoning',                                    F, 6000,   50],
    [21, null, 'Human Trafficking',                            F, 0,     120],
    [22, null, 'Unlawful Restraint of a Peace Officer',        F, 5000,   40],
  ]],

  ['Offences Against Property', [
    [ 1, 'A', 'Robbery',                                       F, 0,      40],
    [ 1, 'B', 'Armed Robbery',                                 F, 0,      55],
    [ 1, 'C', 'Robbery of a Financial Institution',            F, 0,      80],
    [ 2, 'A', 'Residential Burglary',                          F, 4000,   30],
    [ 2, 'B', 'Commercial Burglary',                           F, 3000,   25],
    [ 3, null, 'Grand Theft',                                  F, 2500,   20],
    [ 4, null, 'Petty Theft',                                  M, 750,     0],
    [ 5, null, 'Grand Theft Auto',                             F, 4000,   30],
    [ 6, null, 'Joyriding',                                    M, 1500,    8],
    [ 7, null, 'Receiving Stolen Property',                    M, 2000,   12],
    [ 8, 'A', 'Vandalism Under $1,000',                        M, 1000,    5],
    [ 8, 'B', 'Vandalism Over $1,000',                         F, 3000,   20],
    [ 9, 'A', 'Arson of Property',                             F, 5000,   40],
    [ 9, 'B', 'Arson of an Occupied Structure',                F, 0,      70],
    [10, null, 'Trespassing',                                  M, 500,     0],
    [11, null, 'Extortion',                                    F, 4000,   30],
    [12, null, 'Blackmail',                                    F, 4000,   30],
    [13, null, 'Embezzlement',                                 F, 5000,   30],
    [14, 'A', 'Credit Card Fraud',                             F, 3500,   25],
    [14, 'B', 'Insurance Fraud',                               F, 5000,   30],
    [14, 'C', 'Identity Theft',                                F, 4000,   30],
    [15, null, 'Forgery',                                      F, 3000,   20],
    [16, null, 'Counterfeiting',                               F, 5000,   35],
    [17, null, 'Money Laundering',                             F, 7500,   45],
    [18, null, 'Possession of Burglary Tools',                 M, 1500,   10],
    [19, null, 'Looting',                                      F, 3500,   25],
    [20, null, 'Destruction of Government Property',           F, 4000,   30],
    [21, null, 'Tampering with a Vehicle',                     M, 1000,    5],
    [22, null, 'Theft of Services',                            M, 1000,    5],
    [23, null, 'Shoplifting',                                  M, 750,     0],
    [24, null, 'Criminal Mischief',                            M, 1000,    5],
  ]],

  ['Offences Against Public Order', [
    [ 1, null, 'Disturbing the Peace',                         I, 500,     0],
    [ 2, null, 'Disorderly Conduct',                           M, 750,     0],
    [ 3, null, 'Public Intoxication',                          M, 500,     5],
    [ 4, null, 'Unlawful Assembly',                            M, 1000,    5],
    [ 5, null, 'Rioting',                                      F, 3000,   25],
    [ 6, null, 'Inciting a Riot',                              F, 4000,   30],
    [ 7, null, 'Loitering',                                    I, 250,     0],
    [ 8, null, 'Prowling',                                     M, 750,     5],
    [ 9, null, 'Indecent Exposure',                            M, 1500,    8],
    [10, null, 'Solicitation',                                 M, 1500,    8],
    [11, null, 'Pandering',                                    F, 4000,   30],
    [12, null, 'Illegal Gambling',                             M, 2500,   12],
    [13, null, 'Animal Cruelty',                               M, 2500,   15],
    [14, null, 'Noise Ordinance Violation',                    I, 350,     0],
    [15, null, 'Littering',                                    I, 250,     0],
    [16, null, 'Public Urination',                             I, 350,     0],
    [17, null, 'Panhandling',                                  I, 250,     0],
    [18, null, 'Failure to Disperse',                          M, 1000,    5],
    [19, null, 'Obstructing a Public Way',                     M, 750,     0],
    [20, null, 'Illegal Dumping',                              M, 2000,   10],
  ]],

  ['Controlled Substances', [
    [ 1, 'A', 'Possession of a Schedule I or II Substance',    M, 1500,   10],
    [ 1, 'B', 'Possession of a Schedule III to V Substance',   M, 1000,    5],
    [ 1, 'C', 'Possession of Marijuana Over the Legal Limit',  I, 500,     0],
    [ 2, null, 'Possession with Intent to Distribute',         F, 5000,   30],
    [ 3, null, 'Sale of a Controlled Substance',               F, 6000,   35],
    [ 4, null, 'Transportation of a Controlled Substance',     F, 7500,   45],
    [ 5, null, 'Manufacture of a Controlled Substance',        F, 9000,   55],
    [ 6, null, 'Cultivation of a Controlled Substance',        F, 5000,   30],
    [ 7, null, 'Possession of Drug Paraphernalia',             I, 500,     0],
    [ 8, null, 'Maintaining a Drug House',                     F, 6000,   35],
    [ 9, null, 'Under the Influence of a Controlled Substance', M, 1000,   8],
    [10, null, 'Sale of a Controlled Substance Near a School', F, 9000,   60],
    [11, null, 'Possession of Precursor Chemicals',            F, 5000,   30],
    [12, null, 'Prescription Fraud',                           F, 3500,   25],
  ]],

  ['Vehicle and Traffic', [
    [ 1, 'A', 'Speeding 1 to 15 Over the Limit',               I, 350,     0],
    [ 1, 'B', 'Speeding 16 to 25 Over the Limit',              I, 650,     0],
    [ 1, 'C', 'Speeding 26 or More Over the Limit',            M, 1200,    5],
    [ 2, null, 'Reckless Driving',                             M, 2000,   10],
    [ 3, null, 'Street Racing',                                M, 2500,   15],
    [ 4, 'A', 'Driving Under the Influence',                   M, 2500,   15],
    [ 4, 'B', 'Driving Under the Influence, Second Offence',   F, 5000,   30],
    [ 4, 'C', 'Driving Under the Influence Causing Injury',    F, 7500,   45],
    [ 5, null, 'Driving Without a Licence',                    I, 1000,    0],
    [ 6, null, 'Driving on a Suspended Licence',               M, 1500,    8],
    [ 7, null, 'Unregistered Vehicle',                         I, 500,     0],
    [ 8, null, 'Driving Without Insurance',                    I, 750,     0],
    [ 9, 'A', 'Failure to Yield to a Vehicle',                 I, 350,     0],
    [ 9, 'B', 'Failure to Yield to an Emergency Vehicle',      M, 1000,    5],
    [ 9, 'C', 'Failure to Yield to a Pedestrian',              I, 500,     0],
    [10, null, 'Running a Red Light',                          I, 500,     0],
    [11, null, 'Running a Stop Sign',                          I, 400,     0],
    [12, null, 'Illegal U-Turn',                               I, 250,     0],
    [13, null, 'Unsafe Lane Change',                           I, 350,     0],
    [14, null, 'Failure to Signal',                            I, 250,     0],
    [15, null, 'Illegal Parking',                              I, 200,     0],
    [16, null, 'Parking in a Disabled Space',                  I, 750,     0],
    [17, 'A', 'Hit and Run, Property Damage',                  M, 1500,   10],
    [17, 'B', 'Hit and Run, Injury',                           F, 4000,   30],
    [18, 'A', 'Evading a Peace Officer',                       F, 3500,   25],
    [18, 'B', 'Evading a Peace Officer Causing Injury',        F, 6000,   45],
    [19, null, 'Driving the Wrong Way',                        M, 1000,    5],
    [20, null, 'Illegal Window Tint',                          I, 300,     0],
    [21, null, 'Defective Equipment',                          I, 250,     0],
    [22, null, 'Excessive Exhaust Noise',                      I, 350,     0],
    [23, null, 'Driving Without Headlights',                   I, 250,     0],
    [24, null, 'Unsafe Speed for Conditions',                  I, 400,     0],
    [25, null, 'Following Too Closely',                        I, 350,     0],
    [26, null, 'Obstructing Traffic',                          I, 400,     0],
    [27, null, 'Operating an Unsafe Vehicle',                  M, 750,     0],
    [28, null, 'Open Container in a Vehicle',                  M, 750,     0],
    [29, null, 'Off-Road Operation',                           I, 400,     0],
    [30, null, 'Failure to Maintain Lane',                     I, 350,     0],
    [31, null, 'Unsafe Passing',                               I, 400,     0],
    [32, null, 'Distracted Driving',                           I, 500,     0],
    [33, null, 'Seatbelt Violation',                           I, 200,     0],
    [34, null, 'Illegal Vehicle Modification',                 I, 600,     0],
  ]],

  ['Weapons and Explosives', [
    [ 1, null, 'Carrying a Concealed Weapon',                  M, 2000,   10],
    [ 2, null, 'Carrying a Loaded Firearm in Public',          M, 2500,   15],
    [ 3, null, 'Brandishing a Weapon',                         M, 1500,   10],
    [ 4, null, 'Possession of an Unregistered Firearm',        M, 2500,   15],
    [ 5, 'A', 'Possession of a Prohibited Weapon',             F, 5000,   35],
    [ 5, 'B', 'Possession of a Military Grade Weapon',         F, 9000,   60],
    [ 6, null, 'Possession of a Firearm by a Felon',           F, 5000,   40],
    [ 7, null, 'Use of a Firearm in the Commission of a Felony', F, 0,    45],
    [ 8, 'A', 'Discharge of a Firearm in Public',              F, 4000,   30],
    [ 8, 'B', 'Discharge of a Firearm from a Vehicle',         F, 6000,   45],
    [ 9, null, 'Possession of an Explosive Device',            F, 8000,   55],
    [10, null, 'Manufacture of a Weapon',                      F, 7000,   45],
    [11, null, 'Sale of an Illegal Firearm',                   F, 8000,   50],
    [12, null, 'Possession of Body Armour During a Felony',    F, 3000,   20],
    [13, null, 'Defacing a Firearm Serial Number',             F, 3500,   25],
    [14, null, 'Possession of a Suppressor',                   F, 4000,   30],
  ]],

  ['Offences Against the Government', [
    [ 1, null, 'Resisting Arrest',                             M, 1500,   10],
    [ 2, null, 'Obstruction of Justice',                       M, 2000,   12],
    [ 3, null, 'Failure to Identify',                          M, 750,     5],
    [ 4, null, 'Providing False Information to a Peace Officer', M, 1500,  8],
    [ 5, null, 'Impersonating a Peace Officer',                F, 4000,   30],
    [ 6, null, 'Impersonating a Government Official',          F, 3500,   25],
    [ 7, null, 'Bribery of a Public Official',                 F, 6000,   40],
    [ 8, null, 'Perjury',                                      F, 4000,   30],
    [ 9, null, 'Tampering with Evidence',                      F, 4500,   30],
    [10, null, 'Witness Intimidation',                         F, 5000,   35],
    [11, null, 'Accessory After the Fact',                     M, 2500,   15],
    [12, null, 'Escape from Custody',                          F, 4000,   30],
    [13, null, 'Aiding an Escape',                             F, 4500,   35],
    [14, null, 'Contempt of Court',                            M, 2000,   12],
    [15, null, 'Failure to Appear',                            M, 2500,   15],
    [16, null, 'Violation of Probation',                       M, 2000,   15],
    [17, null, 'Violation of a Restraining Order',             M, 2500,   15],
    [18, null, 'Misuse of Emergency Services',                 M, 1500,    8],
    [19, null, 'Filing a False Police Report',                 M, 2000,   12],
    [20, null, 'Conspiracy',                                   F, 3500,   25],
    [21, null, 'Criminal Trespass on Government Property',     M, 2000,   12],
    [22, null, 'Terrorism',                                    F, 0,     150],
    [23, null, 'Treason',                                      F, 0,     150],
    [24, null, 'Unlawful Flight to Avoid Prosecution',         F, 4000,   30],
    [25, null, 'Harbouring a Fugitive',                        F, 3500,   25],
    [26, null, 'Failure to Comply with a Lawful Order',        M, 1000,    5],
  ]],
];

const esc = (s) => String(s).replace(/'/g, "''");
const rows = [];
let n = 0;

BOOK.forEach(([category, sections], i) => {
  const title = i + 1;
  for (const [section, sub, name, cls, fine, jail] of sections) {
    const code = `PC ${title}.${String(section).padStart(2, '0')}${sub ? ' ' + sub : ''}`;
    rows.push(`('${esc(category)}', '${code}', '${esc(name)}', '${cls}', ${fine}, ${jail}, ${title}, ${section}, ${sub ? `'${sub}'` : 'NULL'})`);
    n++;
  }
});

const sql = `-- XS-MDT — charge book. Run after sql/mdt.sql.
-- Generated by tools/build-penal.mjs. Edit charges in the MDT, not here.

INSERT IGNORE INTO \`mdt_penal_codes\`
    (\`category\`, \`code\`, \`name\`, \`type\`, \`fine_amount\`, \`jail_time\`, \`title_no\`, \`section_no\`, \`subsection\`)
VALUES
${rows.join(',\n')};
`;

writeFileSync('sql/penal-codes.sql', sql);
console.log(`${n} charges across ${BOOK.length} titles written to sql/penal-codes.sql`);
