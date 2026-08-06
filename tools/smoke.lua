--[[
    tools/smoke.lua -- headless smoke test for the pure modules (spellbook +
    setmodel + generated data). Run from the ADDONS directory:

        cd Ashita/addons && lua bludex/tools/smoke.lua

    The UI and lib/blu need Ashita (ffi, AshitaCore) and are only
    syntax-checked separately; everything here must pass with plain Lua.
]]--

package.path = './?.lua;' .. package.path;

local function check(cond, label)
    if cond then
        print('  ok   ' .. label);
    else
        print('  FAIL ' .. label);
        os.exit(1);
    end
end

local book = require('bludex\\lib\\spellbook');
local sets = require('bludex\\lib\\setmodel');

print('smoke: data');
local n = 0; for _ in pairs(book.spells) do n = n + 1; end
check(n == 136, '136 spells loaded');
check(#book.filter({}) == 135, '135 castable through the default filter');
check(book.spells[623].name == 'Head Butt', 'Head Butt by id');
check(book.byName[book.norm('O. Counterstance')] == 696, 'normalized name lookup');
check(book.spells[736].unbridled == true, 'Thunderbolt is unbridled');
check(book.spells[719].setPoints == 8, 'Searing Tempest field set cost');
check(book.spells[719].mpCost == 116, 'Searing Tempest field MP');
check(book.spells[664].castable == false, 'Regeneration flagged uncastable');
check(book.description(623) == nil, 'description is headless-safe (nil without the client)');

print('smoke: filters');
check(#book.filter({ category = 'Healing' }) == 6, '6 castable healing spells');
check(#book.filter({ text = 'head' }) >= 1, 'text filter finds Head Butt');
check(#book.statChoices == 9 and book.statChoices[1] == 'HP',
    '9 stat choices, canonical order');
local function has(t, id)
    for _, v in ipairs(t) do if v == id then return true; end end
    return false;
end
check(has(book.filter({ stat = 'DEX' }), 623), 'stat filter: DEX finds Head Butt');
check(has(book.filter({ stat = 'INT' }), 720), 'stat filter: INT finds Spectral Floe');
check(not has(book.filter({ stat = 'STR' }), 720), 'stat filter excludes non-grantors');
check(book.spells[720].mods[1].stat == 'MP' and book.spells[720].mods[1].value == 30
    and book.spells[720].mods[2].stat == 'INT' and book.spells[720].mods[2].value == 8,
    'field: Spectral Floe MP+30 INT+8');
check(book.spells[719].mods[2].stat == 'STR' and book.spells[719].mods[2].value == 8,
    'field: Searing Tempest MP+30 STR+8');
check(#book.spells[728].mods == 4, 'field: Tenebral Crush grants four stats');
check(has(book.filter({ stat = 'AGI' }), 725) and has(book.filter({ stat = 'AGI' }), 727),
    'stat filter: AGI finds Blinding Fulgor and Silent Storm');
local dw = nil;
for _, t in ipairs(book.traitChoices) do
    if t.name == 'Dual Wield' then dw = t.cat; end
end
check(dw ~= nil, 'Dual Wield trait category exists');
local dwSpells = book.filter({ traitCat = dw });
check(#dwSpells >= 2, 'spells feed Dual Wield');

print('smoke: set model');
-- headless there is no AshitaCore, so every spell counts as learned here
-- (canAdd requires learned in-game -- the codex/traits add paths gate on it)
book.learned = function() return true; end
local s = sets.new('Smoke');
check(sets.count(s) == 0, 'new set empty');
local ok = sets.add(s, 623, book, 80);
check(ok and sets.count(s) == 1, 'added Head Butt');
check(sets.usedPoints(s, book) == 3, 'points used = 3');
local ok2, why = sets.add(s, 623, book, 80);
check(not ok2 and why == 'already in set', 'duplicate rejected');
check((select(2, sets.add(s, 737, book, 80))) == 'Unbridled spells cannot be set',
    'unbridled rejected');

-- fill with Dual Wield feeders and check the ladder activates
local s2 = sets.new('DW');
for _, id in ipairs(dwSpells) do sets.add(s2, id, book, 999); end
local evals = sets.traitEval(s2, book);
local found = nil;
for _, ev in ipairs(evals) do if ev.cat == dw then found = ev; end end
check(found ~= nil and found.tier ~= nil, 'Dual Wield tier active with all feeders set');
print(('       (Dual Wield at weight %d: %s)'):format(found.weight, found.tierText));

local stats = sets.stats(s2, book);
check(type(stats) == 'table', 'stats aggregate');
check(sets.prettyStat('DUAL_WIELD') == 'Dual Wield', 'prettyStat');
check(sets.slotsAtLevel(1) == 6 and sets.slotsAtLevel(10) == 6
    and sets.slotsAtLevel(11) == 8 and sets.slotsAtLevel(38) == 12
    and sets.slotsAtLevel(75) == 20 and sets.slotsAtLevel(99) == 20,
    'slotsAtLevel follows the server rule (6 at 1-10, +2 per 10, cap 20)');

-- the server's base point rule, bracket by bracket (Henrik's table,
-- 2026-08-06; blueutils.cpp clamp(((lvl-1)/10)*5+10, 0, 55))
local BASE_BRACKETS = {
    { 1, 10 }, { 10, 10 }, { 11, 15 }, { 20, 15 }, { 21, 20 }, { 30, 20 },
    { 31, 25 }, { 40, 25 }, { 41, 30 }, { 50, 30 }, { 51, 35 }, { 60, 35 },
    { 61, 40 }, { 70, 40 }, { 71, 45 }, { 75, 45 },
};
local baseOk = true;
for _, b in ipairs(BASE_BRACKETS) do
    if sets.baseCapAtLevel(b[1]) ~= b[2] then baseOk = false; end
end
check(baseOk, 'baseCapAtLevel matches the server bracket table (10..45, +5 per 10)');
-- the two field measurements this whole model rests on: at Lv75 the client
-- read 79 (base 45, gap 34); synced to Lv40 it read 49 (base 25, gap 24).
-- The 10-point difference IS the Assimilation merits, which apply only 75+.
check(79 - sets.baseCapAtLevel(75) == 34 and 49 - sets.baseCapAtLevel(40) == 24,
    'field 2026-08-06: measured gaps are 34 at Lv75 and 24 synced to Lv40');
check((79 - sets.baseCapAtLevel(75)) - (49 - sets.baseCapAtLevel(40))
    == 5 * book.traits.rules.assimilationPerMerit,
    'the gap difference equals 5 Assimilation merits at +2 each');

-- the 0x063 merit read (pure parser; 0x063_miscdata_merits.h layout:
-- 0x04 type, 0x0A uint16 bitfield meritPoints:7 then bluBonus:6)
local blu = require('bludex\\lib\\blu');
local function miscdata(typ, meritPoints, bluBonus)
    local w = (meritPoints % 128) + (bluBonus % 64) * 128;
    local b = { 0x63, 0x50, 0, 0, typ, 0, 0, 0, 0, 0, w % 256, math.floor(w / 256) };
    local s = '';
    for _, v in ipairs(b) do s = s .. string.char(v); end
    return s;
end
check(blu.parseMeritBonus(miscdata(0x02, 31, 10)) == 10, '0x063: reads bluBonus 10 past meritPoints');
check(blu.parseMeritBonus(miscdata(0x02, 127, 63)) == 63, '0x063: bluBonus max 63 with meritPoints max');
check(blu.parseMeritBonus(miscdata(0x02, 0, 0)) == 0, '0x063: zero is a real reading, not nil');
check(blu.parseMeritBonus(miscdata(0x05, 31, 10)) == nil, '0x063: other MISCDATA types ignored');
check(blu.parseMeritBonus('short') == nil, '0x063: short packet cannot over-read');

-- budget rules sanity
check(book.traits.rules.assimilationPerMerit == 2, 'field: +2 per Assimilation merit');
check(book.traits.rules.expectedTotalAt75 == 80, 'field: expected total 80');

print('smoke: sorted apply layout');
local slIds = { 623, 513, 0, 719 };   -- Head Butt, Sandspin, empty, Searing Tempest
local sl = sets.sortedLayout(slIds, book);
check(sl[1] ~= 0 and sl[2] ~= 0 and sl[3] ~= 0 and sl[4] == 0 and sl[20] == 0,
    'sortedLayout packs into slots 1..n with a zero tail');
check(book.spells[sl[1]].level <= book.spells[sl[2]].level
    and book.spells[sl[2]].level <= book.spells[sl[3]].level,
    'sortedLayout is level-ascending');
check(sets.sortedLayout({}, book)[1] == 0, 'sortedLayout of an empty set is all zeros');

print('smoke: blusets import');
local imp = require('bludex\\lib\\blusetsimport');
local ids2, unk = imp.parse({ 'Head Butt', '', ' Pollen ', 'Not A Spell' }, book);
check(ids2[1] == 623 and ids2[2] == 0 and ids2[3] == 549 and ids2[20] == 0,
    'names map to slot ids (blank line = empty slot, whitespace trimmed)');
check(#unk == 1 and unk[1] == 'Not A Spell', 'unknown names reported');
check(imp.parse({}, book)[20] == 0, 'empty file -> all-zero ids');
local icfg = { sets = { { name = 'DI', ids = {} } } };
check(imp.describe({ found = 0, imported = {}, skipped = {}, unknown = {} })
    :find('No blusets') ~= nil, 'describe: nothing found');
check(imp.describe({ found = 2, imported = { 'a' }, skipped = { 'b' }, unknown = {} })
    == 'Imported 1 set; 1 skipped (name exists).', 'describe: summary line');
check(#imp.scan() == 0, 'scan is headless-safe (no AshitaCore -> empty)');

print('smoke: skillchain rules + weaponskill data');
local sc = require('bludex\\lib\\skillchain');
check(#sc.weapons == 14 and sc.weapons[1] == 'Sword', '14 weapons, Sword first');
check(#sc.ws > 150, 'weaponskill data loaded');
local function findWs(name)
    for _, w in ipairs(sc.ws) do if w.name == name then return w; end end
    return nil;
end
check(findWs('Savage Blade').tag == 'quest', 'Savage Blade tagged WSNM quest');
check(findWs('Knights of Round').tag == 'relic', 'Knights of Round tagged relic');
check(findWs('Expiacion').tag == 'mythic', 'Expiacion tagged mythic');
check(findWs('Chant du Cygne').tag == 'empyrean', 'Chant du Cygne tagged empyrean');
check(findWs('Requiescat').tag == 'merit', 'Requiescat tagged merit (Aeonic)');
check(findWs('Uriel Blade') == nil and findWs('Spirits Within') == nil,
    'mob-only and property-less weaponskills excluded');
check(findWs('Fast Blade').sc[1] == 'Scission', 'Fast Blade carries Scission');
-- the resonance table, spot-checked against battleutils.cpp
check(sc.resolve({ 'Liquefaction' }, { 'Impaction' }) == 'Fusion', 'Liq -> Imp = Fusion');
check(sc.resolve({ 'Gravitation' }, { 'Distortion' }) == 'Darkness', 'Grav -> Dist = Darkness');
check(sc.resolve({ 'Light' }, { 'Light' }) == 'Light II', 'Light -> Light = Light II');
check(sc.resolve({ 'Impaction' }, { 'Scission' }) == nil, 'Imp -> Sci does not chain');
check(sc.resolve({ 'Light', 'Fusion' }, { 'Fragmentation' }) == 'Light',
    'opener property priority: primary first, then secondary');
-- partners: Head Butt (Impaction) against swords, both directions
local wsOpens, spellOpens = sc.partners({ 'Impaction' }, 'Sword');
check(#wsOpens > 0 and wsOpens[1].level >= spellOpens[1].level,
    'partner lists sorted big chains first');
local sawFusion = false;
for _, e in ipairs(wsOpens) do
    if e.ws.name == 'Burning Blade' and e.chain == 'Fusion' then sawFusion = true; end
end
check(sawFusion, 'Burning Blade -> Head Butt closes Fusion');
check(sc.LEVEL['Darkness II'] == 4 and sc.ELEMENTS.Fusion == 'Fire/Light',
    'level + burst-element tables');

print('smoke: dlac module adapter');
local dm = require('bludex\\dlacmodule\\init');
check(dm.api == 2 and type(dm.panel) == 'function' and type(dm.init) == 'function'
    and type(dm.window) == 'function' and type(dm.open) == 'function',
    'contract shape (api 2, panel, init, window, open)');
check(dm.config and dm.config.keys and dm.config.keys.sets == 'string'
    and dm.config.defaults.autoRestore == false, 'config declaration');
local ids = {}; for i = 1, 20 do ids[i] = 0; end
ids[1] = 623; ids[7] = 700;
local rt = dm._codec.decodeIds(dm._codec.encodeIds(ids));
check(rt[1] == 623 and rt[7] == 700 and rt[20] == 0 and #rt == 20, 'ids codec roundtrip');
local sl = dm._codec.decodeSets(dm._codec.encodeSets({
    { name = 'Solo DD', ids = ids }, { name = 'x', ids = {} },
}));
check(#sl == 2 and sl[1].name == 'Solo DD' and sl[1].ids[7] == 700
    and sl[2].ids[1] == 0, 'sets codec roundtrip');
check(dm._codec.decodeSets('')[1] == nil and dm._codec.decodeIds(nil)[20] == 0,
    'codec tolerates empty and nil');

print('smoke: all green');
