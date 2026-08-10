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

print('smoke: level builds');
-- THE RUNGS: the two server rules (slots, base points) both step every ten
-- levels from 1, so eight bands cover the whole job and one build serves a
-- whole band. 71 is the last -- it runs to the 75 cap.
check(#sets.LEVELS == 8 and sets.LEVELS[1] == 1 and sets.LEVELS[8] == 71
    and sets.TOP == 71, 'eight rungs, 1 through 71');
local rungOk = true;
for _, lvl in ipairs(sets.LEVELS) do
    if sets.rungFor(lvl) ~= lvl then rungOk = false; end
    -- every level in a band answers the same rung, the same slots, the same base
    for l = lvl, sets.bandTop(lvl) do
        if sets.rungFor(l) ~= lvl then rungOk = false; end
        if sets.slotsAtLevel(l) ~= sets.slotsAtLevel(lvl) then rungOk = false; end
        if sets.baseCapAtLevel(l) ~= sets.baseCapAtLevel(lvl) then rungOk = false; end
    end
end
check(rungOk, 'every level in a band shares its rung, its slots and its base');
check(sets.rungFor(40) == 31 and sets.rungFor(75) == 71 and sets.rungFor(1) == 1,
    'rungFor: 40 -> 31, 75 -> 71, 1 -> 1');
check(sets.rungFor(nil) == nil and sets.rungFor(0) == nil, 'no level, no rung');
check(sets.bandTop(41) == 50 and sets.bandTop(71) == 75, 'bands: 41-50, 71-75');
check(sets.levelForSlot(6) == 1 and sets.levelForSlot(7) == 11
    and sets.levelForSlot(14) == 41 and sets.levelForSlot(20) == 71,
    'levelForSlot inverts slotsAtLevel');
local invOk = true;
for i = 1, 20 do
    local l = sets.levelForSlot(i);
    if sets.slotsAtLevel(l) < i then invOk = false; end
    if l > 1 and sets.slotsAtLevel(l - 1) >= i then invOk = false; end
end
check(invOk, 'levelForSlot is the LOWEST level holding that slot');

-- a tier knows its own ceiling: a Lv.41 draft stops at fourteen slots
local t1 = sets.new('Mid', 41);
check(sets.slotMax(t1) == 14 and sets.slotMax(sets.new('High')) == 20,
    'slotMax follows the build level (a level-less build keeps all 20)');
for _, id in ipairs(book.filter({})) do sets.add(t1, id, book, 999); end
check(sets.count(t1) == 14, 'a Lv.41 build fills fourteen slots and no more');
check((select(2, sets.add(t1, 623, book, 999))):find('Lv.41 has 14') ~= nil,
    'and says which level ran out of slots');
-- the band ceiling: a Lv.41 build reaches level 50, so nothing above it fits
local highId, highLvl = nil, nil;
for _, id in ipairs(book.filter({})) do
    local s = book.spells[id];
    if highId == nil and s.level ~= nil and s.level > 50 then highId, highLvl = id, s.level; end
end
check(highId ~= nil, 'the data has a spell above level 50 to test the band with');
check((select(2, sets.add(sets.new('Mid', 41), highId, book, 999))):find('stops at 50') ~= nil,
    'a Lv.41 build refuses a spell its band cannot cast');
check(sets.add(sets.new('Top', 71), highId, book, 999),
    ('and the top band takes it (Lv.%d, it reaches 75)'):format(highLvl));

-- A SAVED SET: its flat build, plus a build per level band under it. `level
-- nil` addresses the flat one everywhere -- it is a real answer, not a
-- missing one, and it is what a set stays until someone builds a level.
local g = sets.newGroup('Solo');
check(#g.builds == 0 and sets.groupTop(g) == nil and sets.countIds(g.ids) == 0,
    'a new set has an empty flat build and no level builds');
sets.groupPut(g, nil, { 623, 513, 549 });
check(sets.countIds(sets.groupIds(g, nil)) == 3 and #g.builds == 0,
    'writing the flat build adds no level builds');
sets.groupPut(g, 71, { 623, 513 });
sets.groupPut(g, 41, { 623 });
check(#g.builds == 2 and g.builds[1].level == 41 and g.builds[2].level == 71,
    'level builds sort ascending');
check(sets.countIds(sets.groupIds(g, 71)) == 2
    and sets.countIds(sets.groupIds(g, 51)) == 0,
    'an unbuilt band reads as twenty zeros, not nil');
check(sets.countIds(sets.groupIds(g, nil)) == 3, 'and the flat build is untouched');
check(sets.groupTop(g) == 71 and #sets.groupLevels(g) == 2, 'levels and top');
sets.groupPut(g, 41, {});
check(#g.builds == 2 and sets.groupBuild(g, 41) ~= nil,
    'emptying a level build is not the same as not having one -- it stays');
check(sets.groupRemove(g, 41) and #g.builds == 1 and sets.groupBuild(g, 41) == nil,
    'only Remove takes a band away');
check(not sets.groupRemove(g, 41), 'and removing one twice is not an error');
sets.groupPut(g, nil, {});
check(g.ids ~= nil and sets.countIds(g.ids) == 0,
    'the flat build always exists, empty or not -- it is the set itself');

-- BANDS ARE ADDED ON PURPOSE: a set has the levels you gave it, none to start
check(sets.groupAdd(g, 41) and sets.groupBuild(g, 41) ~= nil
    and sets.countIds(sets.groupIds(g, 41)) == 0,
    'groupAdd gives the set an empty band to build in');
check(not sets.groupAdd(g, 41), 'adding a band it already has does nothing');
check(not sets.groupAdd(g, 45) and not sets.groupAdd(g, nil),
    'and only real bands can be added');
local free = sets.groupFree(g);
check(#free == #sets.LEVELS - 2 and free[1] == 1,
    'groupFree offers exactly the bands not added yet');
sets.groupPut(g, nil, { 623 });                -- something to fall back to
check(sets.groupPick(g, 45) == nil,
    'an EMPTY band is not a build to pick -- it means "not yet", not "wear nothing"');
sets.groupRemove(g, 41);
-- THE SELECTION RULE (Henrik 2026-08-06, after walking out of a sync still
-- wearing the Lv.31 build): the band's OWN build, otherwise THE FLAT BUILD.
-- A level build serves its band and NOWHERE else -- it must not fill forward.
sets.groupPut(g, nil, { 623, 513 });           -- a flat build to fall back on
sets.groupPut(g, 21, { 623 });
check(sets.groupPick(g, 25) == 21, 'the band you stand in wins');
check(sets.groupPick(g, 75) == 71, 'and so does the top band, with a build');
sets.groupPut(g, 71, {});                      -- drop the 71 build again
check(sets.groupPick(g, 75) == nil and sets.groupPick(g, 45) == nil,
    'no build for this band -> the FLAT build, not the nearest below');
check(sets.groupPick(g, 21) == 21, 'the built band still answers for itself');
-- the one exception: a set with an empty flat build has no backup to give
sets.groupPut(g, nil, {});
check(sets.groupPick(g, 45) == 21 and sets.groupPick(g, 5) == 21,
    'with nothing flat to fall back on, the nearest build beats nothing at all');
sets.groupPut(g, nil, { 623 });
check(sets.groupPick(g, 45) == nil, 'and the flat build takes over the moment it exists');
check(sets.groupPick(sets.newGroup('x'), 75) == nil,
    'a set with no level builds always answers flat');

-- COPY: how a flat set becomes a level one, and how a build carries upward.
-- Keeps what the band can hold -- lowest spell levels first, nothing above
-- what it can cast, no more than its slots -- and lets the POINTS overflow,
-- because trimming is the player's call.
local wide = {};
for i, id in ipairs(book.filter({})) do if i <= 20 then wide[i] = id; end end
local into41, rep41 = sets.copyInto(wide, 41, book);
check(sets.countIds(into41) == 14 and rep41.taken == 14,
    'a copy into Lv.41 fills its fourteen slots');
local levelsOk, prev = true, 0;
for i = 1, sets.countIds(into41) do
    local s = book.spells[into41[i]];
    if s.level < prev then levelsOk = false; end
    if s.level > 50 then levelsOk = false; end
    prev = s.level;
end
check(levelsOk, 'lowest levels first, and nothing its band cannot cast');
check(rep41.tooHigh > 0 and rep41.tooHigh + rep41.noSlot + rep41.taken == 20,
    'and every spell is accounted for: taken + too high + no slot');
local into1 = sets.copyInto(wide, 1, book);
check(sets.countIds(into1) <= 6, 'a copy into Lv.1 cannot exceed six slots');
check(sets.countIds(sets.copyInto(wide, nil, book)) == 20,
    'copying into the flat build keeps all twenty');
check(sets.copyInto({}, 41, book) ~= nil and sets.countIds(sets.copyInto({}, 41, book)) == 0,
    'copying nothing is not an error');

-- THE LEVEL-CHANGE RULE BELONGS TO THE SET (Henrik 2026-08-07), and unset it
-- is DERIVED from the set's shape -- so the default follows what you build
-- rather than being flipped behind your back. A stored choice stands.
local r = sets.newGroup('Rules');
check(sets.ruleOf(r) == 'restore', 'a flat set restores');
sets.groupAdd(r, 41);
check(sets.ruleOf(r) == 'switch', 'give it a level and it switches between them');
check(sets.setRule(r, 'manual') and sets.ruleOf(r) == 'manual', 'a stored choice wins');
sets.groupAdd(r, 71);
check(sets.ruleOf(r) == 'manual', 'and keeps winning as the set grows');
check(not sets.setRule(r, 'nonsense') and sets.ruleOf(r) == 'manual',
    'an unknown rule is refused, not stored');
r.rule = 'nonsense';                           -- as if hand-edited into the file
sets.normalizeGroup(r);
check(r.rule == nil and sets.ruleOf(r) == 'switch',
    'and one that got in anyway is dropped back to derived');
check(sets.ruleOf(nil) == 'restore', 'no set, no rule to run');

-- NOTHING IS MIGRATED (Henrik 2026-08-06): a set saved before level builds
-- existed is a flat set and stays one.
local legacy = sets.normalizeGroup({ name = 'Old', ids = { 623, 0, 513 } });
check(#legacy.builds == 0 and legacy.ids[1] == 623 and legacy.ids[3] == 513,
    'a flat { name, ids } set keeps its spells flat, with no level builds');
check(sets.groupIds(legacy, nil)[1] == 623 and sets.groupIds(legacy, 71)[1] == 0,
    'and reads back as the flat build, not as a Lv.71 one');
local blank = sets.normalizeGroup({ name = 'Blank' });
check(#blank.builds == 0 and #blank.ids == 20 and sets.countIds(blank.ids) == 0,
    'an entry with no ids at all still normalizes to twenty zeros');
local twice = sets.normalizeGroup(sets.normalizeGroup({ name = 'Old', ids = { 623 } }));
check(#twice.builds == 0 and twice.ids[1] == 623,
    'normalizeGroup is idempotent (the UI runs it over every row it draws)');
local messy = sets.normalizeGroup({ name = 'Hand', ids = {}, builds = {
    { level = 45, ids = { 623 } },            -- not a band start: snapped to 41
    { level = 41, ids = { 513 } },            -- so this one is the duplicate
    { level = 71, ids = {} },                 -- empty, but added on purpose: KEPT
    { level = 0,  ids = { 549 } },            -- no such band: dropped
} });
check(#messy.builds == 2 and messy.builds[1].level == 41
    and messy.builds[1].ids[1] == 623 and messy.builds[2].level == 71,
    'a hand-edited file is snapped to bands and deduped, empties kept');
check(sets.usableFrom(sets.groupIds(legacy, nil), book)
    == math.max(book.spells[623].level, book.spells[513].level),
    'usableFrom reports the highest spell level in a build');
check(sets.usableFrom(sets.groupIds(sets.newGroup('x'), nil), book) == nil,
    'and nothing for an empty one');

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
-- the two equations the budget rests on (Henrik's field readings 2026-08-06:
-- 49 at Lv40, 79 at Lv75). Below 75 merits do not count, so the remainder is
-- the learned bonus; at 75 the merits are whatever is left after it.
check(49 - sets.baseCapAtLevel(40) == 24, 'Lv40: 49 - 25 base = 24 learned bonus');
check(79 - sets.baseCapAtLevel(75) - 24 == 5 * book.traits.rules.assimilationPerMerit,
    'Lv75: 79 - 45 base - 24 learned = 10 = five merits at +2');

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

-- the 0x08C merit read: the packet that actually reports Assimilation, and
-- the one CatsEyeXI pushes in full at every zone-in.
-- layout: u16 count, u16 pad, { u16 id, u8 next, u8 count } x count
local function meritPacket(entries)
    local b = { 0x8C, 0x50, 0, 0, #entries % 256, math.floor(#entries / 256), 0, 0 };
    for _, e in ipairs(entries) do
        b[#b + 1] = e[1] % 256; b[#b + 1] = math.floor(e[1] / 256);
        b[#b + 1] = 0;          b[#b + 1] = e[2];
    end
    local s = '';
    for _, v in ipairs(b) do s = s .. string.char(v); end
    return s;
end
local ASSIM = blu.MERIT_ASSIMILATION;
check(ASSIM == 3014, 'Assimilation is merits.sql 3014 (MCATEGORY_BLU_2 + 0x06)');
check(blu.parseMeritCount(meritPacket({ { 66, 10 }, { ASSIM, 5 } })) == 5,
    '0x08C: finds Assimilation among other merits');
check(blu.parseMeritCount(meritPacket({ { 66, 10 } })) == nil,
    '0x08C: nil when the packet has no Assimilation entry');
check(blu.parseMeritCount(meritPacket({ { ASSIM + 1, 3 } })) == 0,
    '0x08C: an ODD id is the removal flag -- back to zero');
check(blu.parseMeritCount(meritPacket({ { ASSIM, 5 } }):sub(1, 10)) == nil,
    '0x08C: a truncated entry cannot over-read');
-- merit COUNT x2 = points, and one 0x063 then completes the pair
blu.learnedBonus, blu.meritPts, blu.wireTotal = nil, nil, 34;
check(blu.setMeritCount(5) and blu.meritPts == 10, 'five merits = 10 points');
check(blu.learnedBonus == 24, '0x063 total 34 minus 10 merits leaves the 24 learned');
-- A BORUKO VISIT COSTS A ZONE, NOT A MENU: with the merits known, a new
-- wire total re-derives the learned bonus even though both were already set.
blu.wireTotal = nil;                           -- (setWireTotal ignores repeats)
check(blu.setMeritCount(5) == false, 'the same merit count is not a change');
blu.wireTotal = 39;                            -- +5 collected from Boruko
check(blu.setMeritCount(4) and blu.meritPts == 8, 'merits changed to 4 = 8 points');
check(blu.learnedBonus == 31, 'a moved total re-derives the bonus (39 - 8), not a one-shot');
blu.learnedBonus, blu.meritPts, blu.wireTotal = nil, nil, nil;
-- THE PER-MERIT RATE IS MEASURED, NOT ASSUMED, once all three are in hand:
-- 0x08C gives the allocations, a sub-75 reading gives the learned bonus by
-- itself, and the remainder of the wire total is what the merits are worth.
blu.learnedBonus, blu.meritPts, blu.wireTotal = nil, nil, nil;
blu.meritCount, blu.meritValue, blu.meritValueProven = nil, 2, false;
blu.learnedBonus = 24;                         -- measured at a Lv40 sync
blu.wireTotal = 34;                            -- 0x063 at Lv75
blu.setMeritCount(5);
check(blu.meritPts == 10 and blu.meritValue == 2 and blu.meritValueProven,
    'five merits worth 34-24=10 proves the +2 rate rather than assuming it');
-- a server paying a different rate is caught rather than mis-modelled
blu.learnedBonus, blu.meritPts, blu.wireTotal = 24, nil, 39;
blu.meritCount, blu.meritValue, blu.meritValueProven = nil, 2, false;
blu.setMeritCount(5);
check(blu.meritPts == 15 and blu.meritValue == 3,
    'a 39 total against 24 learned and 5 merits measures the rate as 3, not 2');
blu.learnedBonus, blu.meritPts, blu.wireTotal = nil, nil, nil;
blu.meritCount, blu.meritValue, blu.meritValueProven = nil, 2, false;

-- A FRESH CHARACTER: 0x063 sends 33 and 0x08C says 4 merits. The COUNT is
-- reported, never inferred -- so the only assumption is the per-merit rate,
-- and at Lv75 even a wrong rate cannot change the total (45 + 33 = 78 either
-- way). The first sync settles it: below 75 the cap gives the learned bonus
-- with no merits in it, and the rate follows.
blu.resetCapWatch();
blu.learnedBonus, blu.meritPts, blu.wireTotal = nil, nil, nil;
blu.meritCount, blu.meritValue, blu.meritValueProven = nil, 2, false;
blu.wireTotal = 33;
blu.setMeritCount(4);
check(blu.meritPts == 8 and blu.learnedBonus == 25, 'fresh char: 4 merits -> 8 + 25 bonus');
check(not blu.meritValueProven, 'the rate is still only believed');
check(blu.expectedCap(75) == 78, 'Lv75 total is 78 whatever the split');
-- now a sync to 40 with a TRUE bonus of 21 (so the rate was really 3)
blu.watchCap(78, 75);                     -- baseline first: a lone reading never learns
blu.watchCap(46, 40);                     -- 46 - 25 base = 21 learned, no merits
check(blu.learnedBonus == 21, 'a sub-75 reading gives the bonus with no assumption');
check(blu.meritValue == 3 and blu.meritValueProven, 'and measures the real rate: (33-21)/4');
check(blu.meritPts == 12, 'the merits are corrected to 12');
check(blu.expectedCap(75) == 78, 'Lv75 still totals 78 -- the split moved, not the sum');
check(blu.expectedCap(40) == 46, 'and Lv40 is now right, which is what the split is for');
blu.resetCapWatch();
blu.learnedBonus, blu.meritPts, blu.wireTotal = nil, nil, nil;
blu.meritCount, blu.meritValue, blu.meritValueProven = nil, 2, false;

-- the undocumented /bludex forget: everything learned goes, and the believed
-- rate comes back so a relearn starts from the same footing as a fresh char
blu.learnedBonus, blu.meritPts, blu.wireTotal = 24, 10, 34;
blu.meritCount, blu.meritValue, blu.meritValueProven = 5, 3, true;
blu.watchCap(79, 75);
local had = blu.forgetBudget();
check(had.bonus == 24 and had.merits == 10 and had.count == 5 and had.rate == 3,
    'forgetBudget reports what it discarded');
check(blu.learnedBonus == nil and blu.meritPts == nil and blu.meritCount == nil
    and blu.wireTotal == nil, 'forgetBudget clears every learned figure');
check(blu.meritValue == 2 and not blu.meritValueProven, 'and the rate returns to believed');
check(blu.capValue() == nil and blu.expectedCap(75) == nil,
    'the cap watch forgets too -- nothing is guessed from the old state');

-- NO PACKETS AT ALL (the dlac flavor): the client's own cap carries the same
-- information the packets do. A verified Lv75 recompute gives bonus+merits
-- (79 - 45 = 34, exactly 0x063's number); a sub-75 one gives the bonus alone.
-- Two menu visits and the split is complete without reading a single packet.
blu.resetCapWatch();
blu.learnedBonus, blu.meritPts, blu.wireTotal = nil, nil, nil;
blu.meritCount, blu.meritValue, blu.meritValueProven = nil, 2, false;
blu.watchCap(49, 40);                     -- baseline
blu.watchCap(79, 75);                     -- recompute at 75
check(blu.wireTotal == 34, 'a Lv75 recompute yields bonus+merits from the cap alone');
blu.watchCap(49, 40);                     -- recompute under a sync
check(blu.learnedBonus == 24, 'a sub-75 recompute yields the learned bonus');
check(blu.meritPts == 10, 'and the merits follow: 34 - 24');
check(blu.expectedCap(75) == 79 and blu.expectedCap(40) == 49,
    'both levels answer correctly with no packet ever read');
blu.resetCapWatch();
blu.learnedBonus, blu.meritPts, blu.wireTotal = nil, nil, nil;
blu.meritCount, blu.meritValue, blu.meritValueProven = nil, 2, false;

-- THE CAP WATCH, driven directly (three field bugs have lived in here).
-- The rule: the client's cap is trustworthy only while our level still
-- matches the level it was computed at.
blu.resetCapWatch(); blu.learnedBonus, blu.meritPts = 24, 10;
blu.watchCap(79, 75);
check(not blu.capStale(), 'first reading is a baseline, not stale');
blu.watchCap(79, 40);                         -- sync down, client has not recomputed
check(blu.capStale(), 'level moved away from the cap it was computed at -> stale');
blu.watchCap(49, 40);                         -- the set menu opened while synced
check(not blu.capStale(), 'a real value change is a recompute -> fresh again');
-- THE ZONE BOUNCE (field 2026-08-06): the struct reads empty through a zone
-- handoff. nil is NOT a reading, and the value coming back is NOT a
-- recompute -- treating it as one adopted a Lv40 cap of 49 as correct at 75.
blu.watchCap(nil, 40);
blu.watchCap(nil, 75);
blu.watchCap(49, 75);
check(blu.capStale(), 'a zone bounce through nil does not clear the suspicion');
check(blu.budget(75) == 79, 'so the budget answers 79 at Lv75, not the stale 49');
-- and once the client really does recompute at 75, it agrees
blu.watchCap(79, 75);
check(not blu.capStale() and blu.budget(75) == 79, 'client recomputes to 79 and agrees');
-- OURS WINS while the client's number is stale...
blu.watchCap(79, 40);
check(blu.capStale() and blu.budget(40) == 49, 'stale client -> our Lv40 answer, 49');
check(not blu.capDisagrees(40), 'a stale client is not a disagreement');
-- AFTER A RELOAD the client's value is merely FOUND, never witnessed: it may
-- be the sync's leftover, so ours outranks it (field 2026-08-06: 49 sitting
-- at Lv75 after reloading out of a sync, while ours correctly said 79).
blu.resetCapWatch();
blu.watchCap(49, 75);                          -- first look: found, not watched
local differs, watched = blu.capDisagrees(75);
check(differs and not watched, 'found-not-watched disagreement is flagged as unverified');
check(blu.budget(75) == 79, 'an unwitnessed client value does not outrank ours');
-- A WITNESSED recompute is not a disagreement -- it is a lesson. At 75 it
-- gives bonus+merits outright, so the model adopts it and the two agree by
-- construction.
blu.watchCap(60, 75);
differs, watched = blu.capDisagrees(75);
check(not differs and blu.budget(75) == 60, 'a witnessed recompute is absorbed, not argued with');
check(blu.wireTotal == 15, 'and it teaches: 60 - 45 base = 15 above base');
-- which leaves ONE way to reach a verified disagreement: a hand-typed
-- Settings figure that contradicts what the game just recalculated.
blu.learnedBonus = 30;                         -- as if typed in by hand
differs, watched = blu.capDisagrees(75);
check(differs and watched, 'a hand-set figure against a witnessed recompute IS a disagreement');
check(blu.budget(75) == 60, 'and the game wins: the witnessed number is shown');
blu.resetCapWatch(); blu.learnedBonus, blu.meritPts = nil, nil;

-- THE BUDGET MODEL: cap = base + learnedBonus + merits, merits only at 75.
-- Henrik's field numbers 2026-08-06: Lv40 read 49 (base 25 -> bonus 24) and
-- Lv75 read 79 (base 45 -> merits = 79 - 45 - 24 = 10, his five merits).
blu.learnedBonus, blu.meritPts = 24, 10;
check(blu.expectedCap(40) == 49, 'Lv40 = 25 base + 24 learned (no merits under sync)');
check(blu.expectedCap(60) == 59, 'Lv60 = 35 base + 24 learned');
check(blu.expectedCap(75) == 79, 'Lv75 = 45 base + 24 learned + 10 merits');
-- 74 and 75 share a base bracket (45), so the whole step from one to the
-- other IS the merits switching on
check(sets.baseCapAtLevel(74) == sets.baseCapAtLevel(75), '74 and 75 share a base');
check(blu.expectedCap(75) - blu.expectedCap(74) == 10,
    'merits switch on at 75 and account for the entire step');
-- THE RUNG BUDGET: what one level tier is planned against. Every rung uses
-- its own level -- except the top one, which runs 71-75 and is planned at 75,
-- where the merits switch on. Henrik's numbers: 24 bonus, five merits.
check(blu.rungCap(1) == 34, 'Lv.1 rung: 10 base + 24 learned = 34 (his example)');
check(blu.rungCap(41) == 54 and blu.rungCap(61) == 64, 'Lv.41 -> 54, Lv.61 -> 64');
check(blu.rungCap(71) == 79, 'the top rung is planned at 75: 45 + 24 + 10 = 79');
check(select(2, blu.rungCap(41)) == 'model', 'and says the model answered');
local rungLadderOk = true;
for i = 2, #sets.LEVELS do
    if blu.rungCap(sets.LEVELS[i]) <= blu.rungCap(sets.LEVELS[i - 1]) then
        rungLadderOk = false;
    end
end
check(rungLadderOk, 'the ladder climbs at every rung');
-- with nothing measured the rung still answers -- with the server's base rule,
-- flagged as the FLOOR it is rather than passed off as the total
blu.learnedBonus, blu.meritPts = nil, nil;
local baseCap, baseSrc = blu.rungCap(41);
check(baseCap == 30 and baseSrc == 'base', 'unmeasured: the base rule, flagged base');
check(blu.rungCap(nil) == nil, 'and no rung at all answers nothing');
blu.learnedBonus, blu.meritPts = 24, 10;

-- unknowns must answer nil, never a confident wrong number
blu.learnedBonus, blu.meritPts = 24, nil;
check(blu.expectedCap(40) == 49, 'bonus alone still answers below 75');
check(blu.expectedCap(75) == nil, 'no merits known -> no guess at Lv75');
blu.learnedBonus, blu.meritPts = nil, 10;
check(blu.expectedCap(40) == nil and blu.expectedCap(75) == nil,
    'no learned bonus -> no guess at any level');
-- 0x063 carries the two summed, so it can complete a known half
blu.learnedBonus, blu.meritPts, blu.wireTotal = 24, nil, nil;
check(34 > 5 * book.traits.rules.assimilationPerMerit,
    '0x063 bluBonus (34) exceeds any possible merit total -- it holds both');
blu.learnedBonus, blu.meritPts = nil, nil;

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

print('smoke: the Sets tab actions');
-- setsui owns the verbs (the tab buttons and the window header share them),
-- and none of Save / Revert / load touches imgui -- so the whole state
-- machine runs here. This is the net under the one promise that matters:
-- editing a LEVEL build must never disturb the flat set it sits under.
local setsui = require('bludex\\ui\\setsui');
local saves = 0;
local sctx = {
    sets = sets, book = book,
    cfg = { sets = {}, activeSetName = '', activeSetLevel = 0 },
    state = { editingSet = sets.new('Solo'), activeSet = nil, activeLevel = nil },
    save = function() saves = saves + 1; end,
};
sets.add(sctx.state.editingSet, 623, book, 999);
sets.add(sctx.state.editingSet, 513, book, 999);
check(setsui.unsaved(sctx), 'a new set with spells in it is unsaved');
setsui.saveEditing(sctx);
check(#sctx.cfg.sets == 1 and sets.countIds(sctx.cfg.sets[1].ids) == 2
    and #sctx.cfg.sets[1].builds == 0,
    'saving a flat build makes a flat set -- no level builds invented');
check(not setsui.unsaved(sctx) and sctx.cfg.activeSetLevel == 0,
    'saved and clean, and the flat build is what is remembered');

setsui.loadBuild(sctx, 1, 41);
check(sctx.state.editingSet.level == 41 and sets.count(sctx.state.editingSet) == 0
    and sets.slotMax(sctx.state.editingSet) == 14,
    'clicking a level opens an empty build with that level\'s slots');
check(not setsui.unsaved(sctx), 'an unbuilt level is not "unsaved changes"');
sets.add(sctx.state.editingSet, 623, book, 999);
check(setsui.unsaved(sctx), 'and adding to it is');
setsui.saveEditing(sctx);
check(#sctx.cfg.sets == 1 and #sctx.cfg.sets[1].builds == 1
    and sctx.cfg.sets[1].builds[1].level == 41,
    'saving it adds the level build to the same set');
check(sets.countIds(sctx.cfg.sets[1].ids) == 2,
    'AND LEAVES THE FLAT BUILD ALONE -- nothing was migrated into a level');
check(sctx.cfg.activeSetLevel == 41, 'the level being edited is remembered');

sets.add(sctx.state.editingSet, 513, book, 999);
setsui.revertEditing(sctx);
check(sets.count(sctx.state.editingSet) == 1 and sctx.state.editingSet.level == 41,
    'Revert restores THIS level build, and stays on it');
setsui.loadBuild(sctx, 1, nil);
check(sctx.state.editingSet.level == nil and sets.count(sctx.state.editingSet) == 2
    and sets.slotMax(sctx.state.editingSet) == 20,
    'the set name row opens the flat build again, all 20 slots');

sctx.state.editingSet.name = 'Solo DD';
setsui.saveEditing(sctx);
check(sctx.cfg.sets[1].name == 'Solo DD' and #sctx.cfg.sets[1].builds == 1,
    'the name box renames the whole set, level builds and all');
setsui.loadBuild(sctx, 1, 41);
sets.clear(sctx.state.editingSet);
setsui.saveEditing(sctx);
check(#sctx.cfg.sets[1].builds == 1 and sets.countIds(sctx.cfg.sets[1].ids) == 2,
    'clearing a level build empties it but keeps it -- Remove is what drops it');
check(sets.groupPick(sctx.cfg.sets[1], 45) == nil,
    'and an emptied band falls back to the flat build like an unbuilt one');
sets.groupRemove(sctx.cfg.sets[1], 41);
check(#sctx.cfg.sets[1].builds == 0 and sets.countIds(sctx.cfg.sets[1].ids) == 2,
    'Remove drops the band, flat build untouched');
check(saves > 0, 'every one of those persisted');

print('smoke: the level-change rule');
-- The one rule that sends packets on its own, so it is driven end to end here
-- with a stub client. What it must get right: fire only when the level crosses
-- into a band THAT HAS ITS OWN BUILD, equip that, and stay silent otherwise --
-- a band change that costs a 60s cast lock for no reason is the failure that
-- matters. Everywhere else Lvl Set Switch behaves as Restore does, adds-only,
-- which is the restoreMissing path and not this one.
local host = require('bludex\\ui\\host');
local fake;                      -- declared first: the stubs close over it
fake = {
    level = 75, live = {}, applied = nil, says = {}, applying = false,
    watchCap = function() end,
    watchJobState = function() return nil; end,
    effectiveLevel = function() return fake.level; end,
    canApply = function() return true; end,
    currentSet = function() return fake.live; end,
    say = function(s) fake.says[#fake.says + 1] = s; end,
    applyDiff = function(ids) fake.applied = ids; return true; end,
    -- the adds-only path Restore (and Lvl Set Switch, off a band build) uses
    restoreMissing = function(ids) fake.restored = ids; return true; end,
    reportLevelDown = function() end,
};
for i = 1, 20 do fake.live[i] = 0; end
local fcfg = {
    sets = {},
    lastApplied = {}, lastAppliedSet = 'Solo',
    capModelVer = 3, capLearnedBonus = 24, capMeritPoints = 10,
    activeSetName = '', activeSetLevel = 0,
};
local flat = {}; for i = 1, 20 do flat[i] = 0; end
flat[1] = 623; flat[2] = 513;                      -- the flat build: 2 spells
local low  = {}; for i = 1, 20 do low[i] = 0; end
low[1] = 549;                                      -- the Lv.31 build: 1 spell
fcfg.sets[1] = { name = 'Solo', ids = flat, builds = { { level = 31, ids = low } } };
host.init({ book = book, blu = fake, sets = sets, cfg = fcfg, save = function() end });

local function tickNow()                           -- fire any pending check now
    host.tick();
    if host.switchCheck ~= nil then host.switchCheck = 0; host.tick(); end
end
tickNow();
check(fake.applied == nil, 'the first tick only baselines the band -- nothing is sent');
fake.level = 40;                                   -- sync down: 71 -> 31 band
tickNow();
check(fake.applied ~= nil and fake.applied[1] == 549,
    'crossing into Lv.31-40 applies that band\'s build');
check(#fake.says == 1 and fake.says[1]:find('Lv.31 set of "Solo"', 1, true) ~= nil,
    'and says which build it equipped, by name');
fake.live[1] = 549;                                -- the game now holds it
fake.applied = nil;
fake.level = 45;                                   -- up into the Lv.41 band
tickNow();
check(fake.applied == nil,
    'a band with no build of its own equips nothing outright...');
check(sets.groupPick(fcfg.sets[1], 45) == nil,
    '...it is the flat set that serves there, restore-style');
fake.applied = nil;
fake.level = 48;                                   -- same band
tickNow();
check(fake.applied == nil and host.switchCheck == nil,
    'moving inside a band is not a band change -- nothing is scheduled');
-- back into the band that HAS a build, while already wearing it: no packets
fake.live = sets.sortedLayout(low, book);
fake.level = 40;
tickNow();
check(fake.applied == nil, 'and a band change that would move nothing sends nothing');
-- the rule lives on the SET, and Manual means Manual
fcfg.sets[1].rule = 'manual';
fake.live = sets.sortedLayout(flat, book);
fake.level = 75; tickNow();
fake.level = 40; tickNow();
check(fake.applied == nil, 'Manual on the set never triggers it');
fcfg.sets[1].rule = 'restore';
fake.level = 75; tickNow();
fake.level = 40; tickNow();
check(fake.applied == nil, 'nor does Restore -- it never swaps builds');
fcfg.sets[1].rule = nil;                           -- back to derived: has levels
check(sets.ruleOf(fcfg.sets[1]) == 'switch',
    'a set with levels derives Lvl Set Switch');
-- and it follows nothing it was not told about
fcfg.lastAppliedSet = '';
fake.level = 75; tickNow();
fake.level = 40; tickNow();
check(fake.applied == nil, 'with no last-applied set there is nothing to follow');

print('smoke: the codex show-filter');
-- the resolver reads these BY INDEX, so the order is load-bearing: renaming
-- or reordering them silently turns a filter into a no-op
local spellsui = require('bludex\\ui\\spellsui');
check(#spellsui.SHOW_CHOICES == 4
    and spellsui.SHOW_CHOICES[1] == 'Learned'
    and spellsui.SHOW_CHOICES[2] == 'Missing'
    and spellsui.SHOW_CHOICES[3] == 'In the set'
    and spellsui.SHOW_CHOICES[4] == 'Not in the set',
    'the codex show-filter choices, in the order the resolver indexes them');

print('smoke: dlac module adapter');
local dm = require('bludex\\dlacmodule\\init');
check(dm.api == 2 and type(dm.panel) == 'function' and type(dm.init) == 'function'
    and type(dm.window) == 'function' and type(dm.open) == 'function',
    'contract shape (api 2, panel, init, window, open)');
check(dm.config and dm.config.keys and dm.config.keys.sets == 'string'
    and dm.config.defaults.lastAppliedSet == '', 'config declaration');
-- the two flavors keep ONE settings shape: a key the library defaults but
-- this adapter never declared is a setting that silently forgets itself in
-- dlac. (`sets` and `lastApplied` are declared as the codec's strings.)
local libdef = require('bludex\\lib\\config').defaults();
local undeclared = nil;
for k in pairs(libdef) do
    if dm.config.keys[k] == nil then undeclared = k; break; end
end
check(undeclared == nil, 'every library setting is declared here too'
    .. (undeclared and (' -- missing ' .. undeclared) or ''));
check(dm.config.defaults.tooltipDelay == libdef.tooltipDelay,
    'and the hover delay defaults the same in both flavors');
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
-- LEVEL BUILDS ride along as extra lines under the same name; the flat line
-- keeps the exact shape it had before they existed, which is why a set nobody
-- has levelled needs no migration in either direction.
local low = {}; for i = 1, 20 do low[i] = 0; end
low[1] = 623;
local wire = dm._codec.encodeSets({
    { name = 'Solo', ids = ids, builds = { { level = 41, ids = low } } },
    { name = 'Flat', ids = ids, builds = {} },
});
check(select(2, wire:gsub('\n', '\n')) == 2, 'three lines for two sets, one levelled');
check(wire:find('Flat\t' .. dm._codec.encodeIds(ids), 1, true) ~= nil,
    'the flat line is byte-identical to the pre-level shape');
local tl = dm._codec.decodeSets(wire);
check(#tl == 2 and tl[1].name == 'Solo' and #tl[1].builds == 1
    and tl[1].builds[1].level == 41 and tl[1].builds[1].ids[1] == 623,
    'level builds group under their set by name');
check(tl[1].ids[7] == 700 and #tl[2].builds == 0,
    'the flat build survives beside them, and a flat set stays flat');
-- a settings string written by the PREVIOUS version reads back unchanged
local old = dm._codec.decodeSets('Solo\t' .. dm._codec.encodeIds(ids));
check(#old == 1 and #old[1].builds == 0 and old[1].ids[7] == 700,
    'a pre-level settings string reads back as one flat set');
-- the set's level-change rule rides as its own line, and only when stored
local rw = dm._codec.decodeSets(dm._codec.encodeSets({
    { name = 'A', ids = ids, builds = {}, rule = 'manual' },
    { name = 'B', ids = ids, builds = {} },
}));
check(rw[1].rule == 'manual' and rw[2].rule == nil,
    'a picked rule round-trips; a derived one writes nothing');
check(dm._codec.encodeSets({ { name = 'B', ids = ids, builds = {} } }):find('rule') == nil,
    'so a set nobody configured stays exactly one line');

print('smoke: the hover gate');
-- The tooltip dwell (Settings: hover tooltip delay). Pure timing, so it runs
-- here; the busy-waits are the only honest way to watch a clock tick.
local kit = require('bludex\\ui\\kit');
kit.hoverDelay = 0;
check(kit.hoverReady('a') == true, 'zero delay shows a tooltip at once');
kit.hoverDelay = 5;
check(kit.hoverReady('b') == false, 'a delay holds it back');
check(kit.hoverReady('b') == false, 'and keeps holding while the cursor rests');
kit.hoverDelay = 0.02;
kit.hoverReady('c');                                   -- the dwell starts here
local ready, t0 = false, os.clock();
while os.clock() - t0 < 0.06 do ready = kit.hoverReady('c'); end
check(ready == true, 'and shows once the dwell is served');
check(kit.hoverReady('d') == false, 'moving to another item restarts it');
kit.hoverReady('c');
t0 = os.clock();
while os.clock() - t0 < 0.30 do end                    -- longer than HOVER_GAP
check(kit.hoverReady('c') == false, 'and so does coming back after leaving');

print('smoke: the spell tooltip');
-- No textures headless, so tooltip takes its plain-text path -- which is
-- exactly the text, in order, that the rich flavor draws line by line.
local spellsui = require('bludex\\ui\\spellsui');
local tipText = nil;
local tctx = {
    im = {
        IsItemHovered = function() return true; end,
        SetTooltip = function(s) tipText = s; end,
    },
    book = book, sets = sets,
    blu = { onBlu = function() return false; end },
    state = { editingSet = sets.new('T') },
};
kit.hoverDelay = 0;
spellsui.tooltip(tctx, 719, true);                     -- Searing Tempest
check(tipText ~= nil and tipText:find('116 MP', 1, true) ~= nil,
    'it carries the MP cost');
check(tipText:find('Set: 8 pts', 1, true) ~= nil, 'beside the set cost');
kit.hoverDelay = 5;
tipText = nil;
spellsui.tooltip(tctx, 719, true);
check(tipText == nil, 'and waits out the hover delay like every other tooltip');
kit.hoverDelay = 0.5;

print('smoke: job traits (the collision table)');
-- The rule under test (src/map/utils/blueutils.cpp, CalculateTraits): a job
-- trait makes the blue one INELIGIBLE -- not weaker, not overridden when the
-- blue tier is higher. Gone. Everything below is that rule, per ladder.
local tsrc = require('bludex\\lib\\traitsource');
check(tsrc.jobCode(14) == 'DRG' and tsrc.jobName(14) == 'Dragoon', 'job names');
check(tsrc.abilityId(18) == 1554, 'Dual Wield reads at ability id 1554 (1536 + 18)');
local drg30 = tsrc.jobTraits(14, 30);
check(drg30[1] ~= nil and drg30[1].rank == 1, 'DRG has Accuracy Bonus at 30');
check(tsrc.jobTraits(14, 29)[1] == nil, 'and not at 29');
check(tsrc.jobTraits(14, 60)[1].rank == 2 and tsrc.jobTraits(14, 75)[1].rank == 2,
    'rank 2 lands at 60 and holds to 75 (rank 3 is level 76)');
check(tsrc.jobTraits(14, 75)[1].mods[1].value == 22, 'at its own value, +22 not +10');
check(tsrc.jobTraits(16, 75)[1] == nil, 'BLU itself brings no colliding job trait');

-- BLU75/DRG37: the sub job is where a 75 BLU meets its collisions
local blu_drg = tsrc.jobs(16, 75, 14, 37);
check(blu_drg[1] ~= nil and blu_drg[1].slot == 'sub' and blu_drg[1].code == 'DRG',
    'BLU/DRG: Accuracy Bonus comes from the SUB job');
check(blu_drg[1].rank == 1, 'at rank 1 -- a sub job is half your level');
-- DRG75/BLU37: the same trait, the other way round, two ranks higher
local drg_blu = tsrc.jobs(14, 75, 16, 37);
check(drg_blu[1].slot == 'main' and drg_blu[1].rank == 2, 'DRG/BLU: main job, rank 2');

print('smoke: trait attribution');
local ACC = 16;                                  -- the Accuracy Bonus ladder
local v = tsrc.verdict(ACC, 2, book, blu_drg);
check(#v.suppressed == 1 and v.suppressed[1].job.code == 'DRG',
    'BLU/DRG: the 2-weight Accuracy rung is suppressed by DRG');
check(#v.active == 1 and v.active[1].source == 'job',
    'what is live is the JOB trait, and it is reported as such');
check(v.active[1].mods[1].value == 10, 'at the job\'s own tier (+10 at rank 1)');
check(v.deadWeight == true, 'and the weight the set fed it bought nothing');
check(v.contested == true, 'the ladder is flagged contested');

-- no jobs in the way: the same ladder is the set's own
local free = tsrc.verdict(ACC, 2, book, {});
check(#free.suppressed == 0 and #free.active == 1 and free.active[1].source == 'set',
    'with no colliding job the set owns the ladder');
check(free.deadWeight == false and free.contested == false, 'nothing wasted, nothing contested');
-- a job trait with an EMPTY set still shows: you have it, from them
local idle = tsrc.verdict(ACC, 0, book, blu_drg);
check(#idle.active == 1 and idle.active[1].source == 'job' and idle.deadWeight == false,
    'a job trait is reported with an empty set, and nothing is called wasted');

print('smoke: tiers correlate, stat values do not');
-- Henrik, 2026-08-07, from the field: the tab read "Clear Mind  MpHeal +3
-- [SCH (sub job)]". The two sides of this collision DO NOT SHARE A MODIFIER --
-- job Clear Mind grants MPHEAL (mod 71), the blue ladder grants CLEAR_MIND
-- (mod 295) -- so a stat value from one side means nothing against the other.
-- The RANK is the game's own counter for the trait, and it is what compares.
local CM = 4;                                        -- the Clear Mind ladder
check(book.traits.traitNames[24] == 'Clear Mind'
    and book.traits.traitNames[16] == 'Triple Attack',
    'each rung id carries its own trait name');
local sch30 = tsrc.jobs(16, 60, 20, 30);             -- SCH sub, rank 1 (level 20)
check(sch30[24].rank == 1 and sch30[24].mods[1].stat == 'MPHEAL',
    'SCH sub at 30 holds Clear Mind rank 1, and it grants MPHEAL');
check(book.traits.categories[CM].tiers[1].mods[1].stat == 'CLEAR_MIND',
    'while the blue rung grants CLEAR_MIND -- a different modifier entirely');
local cm = tsrc.verdict(CM, 0, book, sch30);
check(cm.active[1].source == 'job' and cm.active[1].tier == 1,
    'so the verdict speaks in TIERS: tier 1, from the job');
check(cm.active[1].traitName == 'Clear Mind', 'named by its own trait');
check(cm.held[1] ~= nil and cm.held[1].code == 'SCH',
    'rung 1 is HELD -- the job\'s rank reaches it (this is the green one)');
check(cm.blocked[2] ~= nil and cm.blocked[3] ~= nil and cm.blocked[4] ~= nil,
    'and rungs 2-4 are out of reach: blue cannot lift a job trait');
check(cm.held[2] == nil, 'rung 2 is NOT held -- rank 1 does not reach it');
-- climb the sub job and the held/out-of-reach line moves up with it
local cm2 = tsrc.verdict(CM, 0, book, tsrc.jobs(16, 75, 20, 37));   -- rank 2 at 35
check(cm2.held[1] ~= nil and cm2.held[2] ~= nil and cm2.blocked[3] ~= nil,
    'at rank 2 the job holds two rungs');
check(cm2.active[1].tier == 2, 'and the headline follows the rank');

print('smoke: the per-tier trait id');
-- Category 24 is TWO different traits: Double Attack (15) at 2 weight and
-- Triple Attack (16) at 4. A per-category id would answer for the wrong one.
local DA = 24;
local tiers = book.traits.categories[DA].tiers;
check(tiers[1].traitId == 15 and tiers[2].traitId == 16,
    'the ladder carries a trait id per tier, not per category');
local solo = tsrc.verdict(DA, 4, book, {});
check(#solo.active == 1 and solo.active[1].traitId == 16,
    'at 4 weight only Triple Attack applies -- it overwrites Double Attack');
-- WAR grants Double Attack (25) but NOT Triple Attack: a PARTIAL block
local blu_war = tsrc.jobs(16, 75, 1, 37);
local part = tsrc.verdict(DA, 4, book, blu_war);
check(#part.suppressed == 1 and part.suppressed[1].traitId == 15,
    'BLU/WAR: WAR kills the Double Attack rung');
check(part.deadWeight == false, 'but the ladder is NOT dead');
local sawTA = false;
for _, a in ipairs(part.active) do
    if a.traitId == 16 and a.source == 'set' then
        sawTA = a.traitName == 'Triple Attack' and a.tier == 2;
    end
end
check(sawTA, 'Triple Attack still comes through from the set, named as itself');
check(part.held[1] ~= nil and part.held[2] == nil and part.blocked[2] == nil,
    'WAR holds rung 1 and does not touch rung 2 -- that rung is another trait');
check(tsrc.verdict(DA, 2, book, blu_war).deadWeight == true,
    'at 2 weight, though, WAR blocks the only rung reached');

-- THF holds BOTH rungs of the Gilfinder ladder (Gilfinder 5, Treasure Hunter 15)
local blu_thf = tsrc.jobs(16, 75, 6, 37);
check(tsrc.verdict(28, 3, book, blu_thf).deadWeight == true,
    'BLU/THF: THF holds both Gilfinder rungs, so all of it is dead weight');
check(tsrc.ladderBlocks(28, book, blu_thf).all == true, 'ladderBlocks says the same');
-- and THF's own Dual Wield starts at 83, far above any sub job
check(#tsrc.ladderBlocks(25, book, blu_thf).blocks == 0,
    'THF at sub level does NOT block Dual Wield (its trait starts at 83)');

print('smoke: the live bit is the referee');
-- The 0x0AC trait bit says whether a trait is UP; it can never say where it
-- came from (blue traits set the same bits). A disagreement is reported, not
-- smoothed over -- the job-trait table is base-LSB and CEXI may differ.
local denied = tsrc.verdict(ACC, 2, book, blu_drg, function() return false; end);
check(denied.disagrees == true, 'model says active, game says no -> disagrees');
local agreed = tsrc.verdict(ACC, 2, book, blu_drg, function() return true; end);
check(agreed.disagrees == nil and agreed.active[1].live == true, 'agreement is quiet');
check(tsrc.verdict(ACC, 2, book, blu_drg).disagrees == nil,
    'and with no live reader at all, nothing is claimed either way');

print('smoke: the Traits tab renders');
-- THE LAW THIS ENFORCES: an unknown Lua name is a silent nil GLOBAL, not an
-- error, until the line runs. The tab draws inside pcall in game, so a typo
-- shows up as "tab error:" on a panel nobody screenshots. Drive the real
-- render against a stub binding instead, and let it throw here.
local traitsui = require('bludex\\ui\\traitsui');
local drew = {};                          -- every string the tab put on screen
local function draw(s) drew[#drew + 1] = tostring(s); end
local stubIm = {
    Text = draw,
    TextColored = function(_, s) draw(s); end,
    TextWrapped = draw,
    SameLine = function() end,
    NewLine = function() end,
    Separator = function() end,
    Indent = function() end,
    Unindent = function() end,
    Selectable = function(label) draw(label); return false; end,
    BeginChild = function() return true; end,
    EndChild = function() end,
    BeginCombo = function() return false; end,
    EndCombo = function() end,
    SetNextItemWidth = function() end,
    CalcTextSize = function(s) return #tostring(s) * 7; end,
    GetContentRegionAvail = function() return 780; end,
    GetTextLineHeight = function() return 17; end,
    GetCursorPosX = function() return 0; end,
    GetCursorPosY = function() return 0; end,
    SetCursorPosX = function() end,
    SetCursorPosY = function() end,
    PushID = function() end,
    PopID = function() end,
    PushStyleColor = function() end,
    PopStyleColor = function() end,
    IsItemHovered = function() return false; end,
    IsItemClicked = function() return false; end,
    SetTooltip = draw,
    GetItemRectMin = function() return 0, 0; end,
    GetItemRectMax = function() return 10, 10; end,
    GetColorU32 = function() return 0xFFFFFFFF; end,
    GetWindowDrawList = function() return { AddLine = function() end }; end,
};
local tset = sets.new('Traits smoke');
for _, id in ipairs(book.filter({ traitCat = ACC })) do sets.add(tset, id, book, 999); end
local tctx2 = {
    im = stubIm, book = book, sets = sets,
    blu = { onBlu = function() return true; end },
    cfg = { traitsDensity = 'normal' },
    state = { editingSet = tset, openCat = { [ACC] = true, [CM] = true }, detailOpen = { false } },
    tsrc = tsrc, jobTraits = sch30,
    jobPair = { mainJob = 16, mainLevel = 60, subJob = 20, subLevel = 30 },
    verdict = function(c, w) return tsrc.verdict(c, w, book, sch30, nil); end,
    budgetMax = function() return 79; end,
};
traitsui.render(tctx2);                    -- unguarded ON PURPOSE
local screen = table.concat(drew, '\n');
check(#drew > 20, ('the tab drew (%d strings)'):format(#drew));
check(screen:find('BLU60 / SCH30', 1, true) ~= nil, 'the job pair is named on the tab');
check(screen:find('Clear Mind', 1, true) ~= nil, 'the contested ladder is listed');
-- THE FIELD REPORT, as a check: tier language in the headline, never a raw
-- stat value the blue side does not even use
check(screen:find('Tier 1 [SCH (sub job)]', 1, true) ~= nil,
    'the headline reads "Tier 1 [SCH (sub job)]"');
check(screen:find('MpHeal +3 [SCH', 1, true) == nil,
    'and NOT the job trait\'s own stat value, which compares to nothing');
check(screen:find('<- SCH (sub job), rank 1', 1, true) ~= nil,
    'rung 1 is annotated with the job that has you standing on it');
check(screen:find('out of reach', 1, true) ~= nil,
    'and the rungs above it say why they cannot be climbed');
-- and with no job data at all the same tab still renders, claiming nothing
drew = {};
tctx2.verdict, tctx2.jobPair, tctx2.jobTraits = nil, nil, {};
traitsui.render(tctx2);
check(#drew > 20, 'it renders without the job side too');
check(table.concat(drew, '\n'):find('blocked', 1, true) == nil,
    'and blocks nothing it cannot know about');

print('smoke: all green');
