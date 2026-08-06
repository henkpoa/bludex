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
check(#g.builds == 1 and sets.groupBuild(g, 41) == nil,
    'clearing a level build REMOVES it -- the band goes back to unbuilt');
sets.groupPut(g, nil, {});
check(g.ids ~= nil and sets.countIds(g.ids) == 0,
    'but the flat build always exists, empty or not -- it is the set itself');
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
    { level = 71, ids = {} },                 -- empty: dropped
    { level = 0,  ids = { 549 } },            -- no such band: dropped
} });
check(#messy.builds == 1 and messy.builds[1].level == 41
    and messy.builds[1].ids[1] == 623,
    'a hand-edited file is snapped to bands, deduped and pruned');
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
check(#sctx.cfg.sets[1].builds == 0 and sets.countIds(sctx.cfg.sets[1].ids) == 2,
    'clearing a level build and saving drops it, flat build untouched');
check(saves > 0, 'every one of those persisted');

print('smoke: the level-change Switch rule');
-- The one rule that sends packets on its own, so it is driven end to end here
-- with a stub client. What it must get right: fire only when the level crosses
-- into a different BAND, apply that band's build (or the flat one), and stay
-- silent when nothing would move -- a band change that costs a 60s cast lock
-- for no reason is the failure that matters.
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
};
for i = 1, 20 do fake.live[i] = 0; end
local fcfg = {
    sets = {}, autoSwitch = true, autoRestore = false,
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
check(#fake.says == 1 and fake.says[1]:find('Lv.31 build') ~= nil,
    'and says which build, by name');
fake.live[1] = 549;                                -- the game now holds it
fake.applied = nil;
fake.level = 45;                                   -- still the Lv.41 band? no: 41
tickNow();
check(fake.applied ~= nil, 'moving up into Lv.41-50 switches again -- to the flat build');
check(fake.applied[1] == 623 and fake.applied[2] == 513,
    'because no Lv.41 build exists, and the flat set is the backup');
fake.applied = nil;
fake.level = 48;                                   -- same band
tickNow();
check(fake.applied == nil and host.switchCheck == nil,
    'moving inside a band is not a band change -- nothing is scheduled');
-- already wearing the right build: no packets, no cast lock
fake.live = sets.sortedLayout(flat, book);
fake.level = 75;
tickNow();
check(fake.applied == nil, 'and a band change that would move nothing sends nothing');
-- disarmed, it never fires
fcfg.autoSwitch = false;
fake.level = 40;
tickNow();
check(fake.applied == nil, 'Manual/Restore never triggers it');
-- and it follows nothing it was not told about
fcfg.autoSwitch, fcfg.lastAppliedSet = true, '';
fake.level = 75;
tickNow();
check(fake.applied == nil, 'with no last-applied set there is nothing to follow');

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

print('smoke: all green');
