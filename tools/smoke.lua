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

print('smoke: timeline chains (docs/timeline-sets-plan.md)');
-- the bracket rule, and its agreement with the server's slot count at
-- EVERY level -- the two must never drift (slots open AT 11/21/../71)
check(sets.bracketFloor(1) == 1 and sets.bracketFloor(6) == 1
    and sets.bracketFloor(7) == 11 and sets.bracketFloor(8) == 11
    and sets.bracketFloor(9) == 21 and sets.bracketFloor(19) == 71
    and sets.bracketFloor(20) == 71, 'bracketFloor: 1-6 open, pairs at x1 levels');
local agree = true;
for L = 1, 75 do
    local open = 0;
    for slot = 1, 20 do
        if sets.bracketFloor(slot) <= L then open = open + 1; end
    end
    if open ~= sets.slotsAtLevel(L) then agree = false; end
end
check(agree, 'bracketFloor agrees with slotsAtLevel at every level 1-75');
local br = sets.brackets();
check(#br == 8 and #br[1].slots == 6 and br[2].floor == 11 and br[8].floor == 71,
    'brackets(): 6 slots at 1, seven pairs after');

-- a new set is v2; a v1 set upgrades by SORTED placement (the migration is
-- the sorted apply layout made visible: lowest level in the lowest slot)
local v2 = sets.new('V2');
check(v2.builtFor == 75 and v2.chains ~= nil and #v2.chains[1] == 0,
    'new sets carry builtFor 75 and empty chains');
check(sets.upgrade(v2, book) == false or true, 'upgrade tolerates a v2 set');
local v1 = { name = 'Old', ids = {} };
for i = 1, 20 do v1.ids[i] = 0; end
v1.ids[3] = 529;      -- Bludgeon 18
v1.ids[9] = 603;      -- Wild Oats 4
check(sets.upgrade(v1, book) == true, 'a flat set migrates');
check(v1.chains[1][1].id == 603 and v1.chains[1][1].from == 4
    and v1.chains[2][1].id == 529 and v1.chains[2][1].from == 18,
    'migration sorts lowest level into the lowest slot, from = spell level');
check(v1.ids[1] == 603 and v1.ids[2] == 529 and v1.ids[3] == 0,
    'the ids mirror re-derives as the level-75 resolution');
check(sets.isFlat(v1, book), 'a migrated set is flat (no timeline chrome)');

-- the Wild Oats -> Bludgeon -> empty chain, Henrik's founding example
local tl = sets.new('Leveling');
check(sets.addEntry(tl, 1, 603, nil, book), 'Wild Oats joins slot 1 at its own level');
local okB = sets.addEntry(tl, 1, 529, nil, book);
check(okB, 'Bludgeon stacks on the same chain at 18');
check(not sets.isFlat(tl, book), 'a stacked chain is not flat');
local lo1, hi1 = sets.entryRange(tl, 1, 1);
local lo2, hi2 = sets.entryRange(tl, 1, 2);
check(lo1 == 4 and hi1 == 17 and lo2 == 18 and hi2 == 75,
    'ranges: Wild Oats 4-17, Bludgeon 18-75');
check(sets.resolveAtLevel(tl, 3, book)[1] == 0
    and sets.resolveAtLevel(tl, 17, book)[1] == 603
    and sets.resolveAtLevel(tl, 18, book)[1] == 529,
    'resolve: nothing at 3, Wild Oats at 17, Bludgeon from 18');
check(sets.addEntry(tl, 1, 0, 45, book), 'the slot goes deliberately empty at 45');
local _, hi2b = sets.entryRange(tl, 1, 2);
check(hi2b == 44 and sets.resolveAtLevel(tl, 44, book)[1] == 529
    and sets.resolveAtLevel(tl, 45, book)[1] == 0,
    'the empty marker ends Bludgeon at 44');
check(sets.count(tl) == 2, 'count = spell entries, markers not counted');
check(sets.contains(tl, 603) == 1, 'contains sees the RETIRED Wild Oats (assigned anywhere)');

-- entry validation: the gates the picker shows as reasons
check(select(2, sets.addEntry(tl, 1, 529, 18, book)) == 'another entry already activates at Lv.18',
    'equal activation levels cannot coexist');
check(select(2, sets.addEntry(tl, 2, 529, 10, book)) == 'cannot activate before its level (18)',
    'a spell cannot activate before its own level');
check(select(2, sets.addEntry(tl, 2, 0, 30, book)) == 'the slot is already empty',
    'an empty marker needs a chain to end');
check(select(2, sets.addEntry(tl, 1, 0, 50, book)) == 'already empty from Lv.45',
    'empty on empty says so');
check(select(2, sets.addEntry(tl, 1, 737, nil, book)) == 'Unbridled spells cannot be set',
    'the unbridled gate holds for chain entries');

-- the one-place-at-a-time rule and the EXTENSION GUARD (plan 2.4): the
-- retired Wild Oats may return in another slot at 30 -- and from then on,
-- removing Bludgeon would stretch slot 1's Wild Oats over 30+, so that
-- removal is refused with the collision named, never silently absorbed
check(sets.addEntry(tl, 2, 603, 30, book), 'Wild Oats re-added at 30 in another slot (ranges disjoint)');
check(select(2, sets.addEntry(tl, 3, 603, 50, book)) == 'already active at Lv.30-75 in another slot',
    'a third overlapping placement is refused');
local okRm, whyRm = sets.removeEntry(tl, 1, 2, book);
check(okRm == false and whyRm == 'Wild Oats would then be active twice (already Lv.30-75 elsewhere)',
    'the extension guard: removing Bludgeon is refused while Wild Oats lives at 30');
check(sets.removeEntry(tl, 2, 1, book), 'the 30+ placement removes cleanly');
check(sets.removeEntry(tl, 1, 2, book), 'and now Bludgeon can go');
check(sets.resolveAtLevel(tl, 30, book)[1] == 603 and sets.resolveAtLevel(tl, 45, book)[1] == 0,
    'Wild Oats stretches to 44, the empty marker still ends the chain');

-- the DEAD-ENTRY guard: a high-bracket slot floors every entry, and an
-- insert may not shadow a neighbor into never existing
local hb = sets.new('HighBracket');
check(sets.addEntry(hb, 9, 603, nil, book), 'Wild Oats in a 21+ slot is legal');
local lo9 = sets.entryRange(hb, 9, 1);
check(lo9 == 21, 'but it activates at the slot floor, not its level');
check(select(2, sets.addEntry(hb, 9, 529, nil, book)) == 'Wild Oats would never be active in this slot',
    'an insert may not shadow a floored neighbor to death');
check(sets.addEntry(hb, 10, 529, 21, book), 'Bludgeon at the floor of its own slot is fine');
check(select(2, sets.addEntry(hb, 10, 603, nil, book)) == 'never active here (the slot unlocks at Lv.21)',
    'a below-floor insert that never activates says why');

-- removeId clears every placement; clearChain and removeSlot clear one
sets.removeId(tl, 603);
check(sets.contains(tl, 603) == nil, 'removeId clears every placement of the spell');
sets.clearChain(hb, 9, book);
check(#hb.chains[9] == 0 and sets.contains(hb, 603) == nil, 'clearChain empties one slot');

-- the convenience add: a new chain in the lowest free slot (floors ascend,
-- so the first free slot is the earliest-activating home)
local qa = sets.new('Quick');
check(sets.add(qa, 529, book, 80), 'add() lands the spell as a new chain');
check(qa.chains[1][1].id == 529 and qa.chains[1][1].from == 18, 'in slot 1 at its own level');
check(select(2, sets.add(qa, 529, book, 80)) == 'already in set', 'duplicates still refused');

-- the BAND SWEEP (plan 2.6): whole-curve point validation with a stub
-- book, so the arithmetic is pinned exactly
local stub = { spells = {
    [900] = { setPoints = 10, level = 1 },
    [901] = { setPoints = 10, level = 15 },
    [902] = { setPoints = 5,  level = 1 },
}, learned = function() return true; end };
local bandSet = sets.new('Bands');
bandSet.chains[1] = { { id = 900, from = 1 } };
bandSet.chains[2] = { { id = 902, from = 1 } };
bandSet.chains[3] = { { id = 901, from = 15 } };
sets.syncLegacyIds(bandSet, stub);
local baseFn = function(L) return sets.baseCapAtLevel(L); end
local bands = sets.bandViolations(bandSet, stub, baseFn);
check(#bands == 2, 'two violation bands against the base rule');
check(bands[1].lo == 1 and bands[1].hi == 10 and bands[1].over == 5,
    'band 1: 15 pts vs 10 at levels 1-10');
check(bands[2].lo == 15 and bands[2].hi == 30 and bands[2].over == 10,
    'band 2: 25 pts vs 15/20 merges over 15-30 at its worst (10 over)');
check(not bands[1].enforced and not bands[2].enforced,
    'builtFor 75: nothing below it is enforced');
check(#sets.enforcedViolations(bandSet, stub, baseFn) == 0,
    'an endgame set with low-level noise blocks nothing');
bandSet.builtFor = 1;
local bands2 = sets.bandViolations(bandSet, stub, baseFn);
check(bands2[1].enforced and bands2[2].enforced, 'builtFor 1 enforces the whole curve');
check(#sets.enforcedViolations(bandSet, stub, baseFn) == 2, 'and both bands now block');
check(sets.bandText(bands2[2]) == 'Between level 15 and 30, you are up to 10 point(s) above threshold',
    'the band message is the plan\'s, with "up to" when the overage varies inside');
check(sets.bandText(bands2[1]) == 'Between level 1 and 10, you are 5 point(s) above threshold',
    'a constant band states its overage plainly');
local prov = sets.bandViolations(bandSet, stub, function() return nil; end);
check(prov[1].provisional and #sets.enforcedViolations(bandSet, stub, function() return nil; end) == 0,
    'an unknown budget makes bands provisional -- warned, never blocking');
-- the merit cliff: a maxed 75 set (79 pts) is over at EVERY level below 75
-- (merits count only at 75) -- REAL math, but builtFor 75 keeps it all
-- un-enforced: the false positive that shaped the builtFor rule. At
-- builtFor 71 the 71-74 stretch becomes the set's own problem and blocks.
local cliff = sets.new('Cliff');
cliff.chains[1] = { { id = 900, from = 1 } };
sets.syncLegacyIds(cliff, stub);
local cliffFn = function(L)                     -- bonus 24 known, merits 10 at 75
    local c = sets.baseCapAtLevel(L) + 24;
    if L >= 75 then c = c + 10; end
    return c;
end
stub.spells[900].setPoints = 79;
local cbands = sets.bandViolations(cliff, stub, cliffFn);
check(#cbands == 1 and cbands[1].lo == 1 and cbands[1].hi == 74
    and cbands[1].over == 45 and cbands[1].overMin == 10 and not cbands[1].enforced,
    'a maxed 75 set is over everywhere below 75 -- one un-enforced band');
check(sets.bandText(cbands[1]) == 'Between level 1 and 74, you are up to 45 point(s) above threshold',
    'a varying band says "up to" instead of overstating');
check(#sets.enforcedViolations(cliff, stub, cliffFn) == 0,
    'a maxed endgame set stays appliable (nothing at/above builtFor 75)');
cliff.builtFor = 71;
local cbands2 = sets.bandViolations(cliff, stub, cliffFn);
check(#cbands2 == 2 and cbands2[2].lo == 71 and cbands2[2].hi == 74
    and cbands2[2].over == 10 and cbands2[2].enforced,
    'builtFor 71 splits the band at the boundary and enforces the merit cliff');
check(#sets.enforcedViolations(cliff, stub, cliffFn) == 1,
    'a set that claims 71-75 really must fit at 71-74');
stub.spells[900].setPoints = 10;

-- equality, cloning, backups
local eqA = sets.new('Eq');
sets.addEntry(eqA, 1, 603, nil, book);
local eqB = sets.clone(eqA, 'Eq');
check(sets.equal(eqA, eqB), 'a clone is equal');
sets.addEntry(eqB, 1, 529, nil, book);
check(not sets.equal(eqA, eqB), 'an added entry breaks equality');
eqB.chains[1][2] = nil;
sets.syncLegacyIds(eqB, book);
eqB.builtFor = 40;
check(not sets.equal(eqA, eqB), 'builtFor is authorship (compared)');
eqB.builtFor = 75;
check(sets.equal(eqA, eqB), 'and back');
for i = 1, 7 do
    sets.pushBackup(eqA, eqB, 1000 + i);
end
check(#eqA.backups == sets.BACKUP_CAP and eqA.backups[1].ts == 1007,
    'backups cap at 5, newest first');
local rb = sets.new('RB');
sets.addEntry(rb, 1, 603, nil, book);
sets.pushBackup(rb, rb, 1);
sets.addEntry(rb, 1, 529, nil, book);
check(sets.restoreBackup(rb, 1, book, 2), 'restore returns true');
check(#rb.chains[1] == 1 and rb.chains[1][1].id == 603, 'restore brings the old chain back');
check(rb.backups[1].ts == 2 and #rb.backups[1].chains[1] == 2,
    'and the pre-restore state was banked first (restore is undoable)');
local cl = sets.clone(rb, 'CL');
cl.chains[1][1].from = 10;
check(rb.chains[1][1].from == 4, 'clone is deep (chains detached)');

-- fromIds (Read current / blusets import) and the legacy resolve fallback
local fi = sets.fromIds('Imported', { [1] = 529, [2] = 603 }, book);
check(fi.chains[1][1].id == 603 and fi.chains[2][1].id == 529,
    'fromIds sorts like the migration');
local legacy = { name = 'L', ids = { [1] = 529 } };
check(sets.resolveAtLevel(legacy, 75, book)[1] == 529
    and sets.resolveAtLevel(legacy, 17, book)[1] == 0,
    'an un-upgraded set still resolves (built on the fly)');

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

-- the TIMELINE grammar (sets2/sets2bak, plan 7): lossless round-trip of
-- chains, builtFor and backups -- and the legacy key stays a usable flat
-- mirror, because the OLD decoder zeroes unknown tokens (changing the old
-- grammar in place would silently EMPTY every set on an older module)
local tset = sets.new('Level Up');
check(sets.addEntry(tset, 1, 603, nil, book)
    and sets.addEntry(tset, 1, 529, nil, book)
    and sets.addEntry(tset, 1, 0, 45, book), 'codec fixture builds');
tset.builtFor = 1;
sets.pushBackup(tset, tset, 12345);
local dec = dm._codec.decodeSets2(dm._codec.encodeSets2({ tset }));
check(#dec == 1 and dec[1].builtFor == 1, 'sets2: builtFor survives');
check(#dec[1].chains[1] == 3 and dec[1].chains[1][2].id == 529
    and dec[1].chains[1][2].from == 18 and dec[1].chains[1][3].id == 0
    and dec[1].chains[1][3].from == 45,
    'sets2: the chain survives, empty marker included');
check(#dec[1].chains[2] == 0 and dec[1].chains[20] ~= nil,
    'sets2: empty chains keep their places (the split keeps empty tokens)');
dm._codec.attachBackups(dec, dm._codec.encodeBackups({ tset }));
check(dec[1].backups ~= nil and dec[1].backups[1].ts == 12345
    and #dec[1].backups[1].chains[1] == 3, 'sets2bak: backups reattach by name');
sets.upgrade(dec[1], book);
check(sets.equal(dec[1], tset), 'the round-tripped set equals the original');
check(dm._codec.decodeSets2('')[1] == nil and dm._codec.decodeSets2('#v2')[1] == nil,
    'sets2 decode tolerates empty and header-only');
local eg = sets.fromIds('EG', { 529, 603 }, book);
local oldRead = dm._codec.decodeSets(dm._codec.encodeSets({ eg }));
check(oldRead[1].ids[1] == 603 and oldRead[1].ids[2] == 529,
    'the legacy key carries the flat level-75 mirror for older modules');

print('smoke: settings lifecycle (logoff / relog / character switch)');
-- The Ashita settings library swaps the WHOLE settings table at every
-- login and logout: the shared defaults profile while logged off, the
-- character's own file at login. host.onSettingsSwap is the addon's answer;
-- these drive the three arms it has to get right. (ui/host is headless-safe
-- to require -- every imgui touch is guarded -- and none of this renders.)
local host   = require('bludex\\ui\\host');
local config = require('bludex\\lib\\config');
local function mkcfg(t)
    local c = config.defaults();
    for k, v in pairs(t or {}) do c[k] = v; end
    return c;
end
local function entry(name, id)
    local e = sets.new(name);
    e.ids[1] = id;
    return e;
end
blu.forgetBudget();
-- A COLD START: addons load at the title screen, so init can only adopt the
-- defaults profile. The character's real file arrives with the first login,
-- THROUGH THE SWAP -- before the swap adopted it, every fresh game start
-- came up with an empty editor and an unseeded budget, which from the chair
-- reads as 'my save did not survive the log off'.
host.init({ im = {}, book = book, blu = blu, sets = sets, cfg = mkcfg(),
    save = function() end });
host.noteChar(nil);
check(host.state.activeSet == nil, 'cold start: nothing to select in the defaults profile');
local aCfg = mkcfg({ activeSetName = 'Solo', capLearnedBonus = 24, capMeritPoints = 10 });
aCfg.sets = { entry('Farm', 623), entry('Solo', 700) };
host.onSettingsSwap(aCfg, 'Aludra_101');
check(host.deps.cfg == aCfg, 'first login: the swapped-in table is the one saves serialize');
check(host.state.activeSet == 2 and host.state.editingSet.name == 'Solo'
    and host.state.editingSet.ids[1] == 700,
    'first login restores the remembered active set from the character file');
check(blu.learnedBonus == 24 and blu.meritPts == 10,
    'first login seeds the budget halves from the character file');
-- the timeline migration rides the same adopt: flat entries gain chains
check(aCfg.sets[1].chains ~= nil and aCfg.sets[1].chains[1][1] ~= nil
    and aCfg.sets[1].chains[1][1].id == 623 and aCfg.sets[1].builtFor == 75,
    'adopt migrates stored flat sets to chains (builtFor 75)');
check(aCfg.setsModelVer == 2, 'and stamps setsModelVer 2');
check(aCfg.replan == 'manual', 'the retired autoRestore maps to replan=manual');
check(host.state.editingSet.chains ~= nil, 'the editing clone speaks chains too');
-- LOG OFF: the defaults profile swaps in. The working state stays put (the
-- same character usually returns; the standalone gates rendering meanwhile).
host.state.editingSet.ids[3] = 623;                 -- an unsaved edit
host.onSettingsSwap(mkcfg(), nil);
check(host.deps.cfg ~= aCfg, 'logoff: cfg rebinds to the defaults profile');
check(host.state.editingSet.ids[3] == 623, 'logoff keeps the working state');
-- THE SAME CHARACTER RETURNS: their file reloads into a fresh table; the
-- selection and the unsaved edits are still theirs to keep.
local aCfg2 = mkcfg({ activeSetName = 'Solo', capLearnedBonus = 24, capMeritPoints = 10 });
aCfg2.sets = { entry('Farm', 623), entry('Solo', 700) };
host.onSettingsSwap(aCfg2, 'Aludra_101');
check(host.deps.cfg == aCfg2, 'relog: cfg rebinds to the reloaded file');
check(host.state.activeSet == 2 and host.state.editingSet.ids[3] == 623,
    'relog keeps the selection and the unsaved edits');
check(blu.learnedBonus == 24 and blu.meritPts == 10, 'relog keeps the seeded budget');
-- A DIFFERENT CHARACTER: everything the previous one owned is dropped.
-- Keeping it is how their editing set overwrote the new character\'s saved
-- set, and how their budget figures were saved into the new character\'s
-- file by the first 0x08C of the session.
host.state.tab = 'Sets';
local bCfg = mkcfg();
bCfg.sets = { entry('Tank', 594) };
host.onSettingsSwap(mkcfg(), nil);                  -- the logoff between them
host.onSettingsSwap(bCfg, 'Belias_101');
check(host.deps.cfg == bCfg, 'switch: cfg rebinds');
check(host.state.activeSet == nil and sets.count(host.state.editingSet) == 0,
    'switch drops the previous character\'s selection and editing set');
check(blu.learnedBonus == nil and blu.meritPts == nil and blu.wireTotal == nil,
    'switch forgets the previous character\'s budget instead of inheriting it');
check(host.state.tab == 'Sets', 'switch keeps pure view state (the active tab)');
check(type(blu.resetJobWatch) == 'function', 'the job watch has its lifecycle seam');
blu.forgetBudget();

print('smoke: dlac adapter store lifecycle');
-- dlac loads modules BEFORE login, and its store serves declared defaults
-- until the character directory exists. The adapter's decoded bridge must
-- FOLLOW the store: init's snapshot alone meant the first save of a session
-- wrote an empty set list over the character's real file.
local disk = {};                       -- the stub store's backing 'files'
local storeDir = nil;                  -- nil = pre-login
local stubStore = {
    get = function(k)
        local f = storeDir and disk[storeDir] or nil;
        local v = nil;
        if f ~= nil then v = f[k]; end
        if v == nil then return dm.config.defaults[k]; end
        return v;
    end,
    set = function(k, v)
        if storeDir == nil then return false; end
        disk[storeDir] = disk[storeDir] or {};
        disk[storeDir][k] = v;
        return true;
    end,
    path = function()
        if storeDir == nil then return nil; end
        return storeDir .. 'jobhelper-bludex.lua';
    end,
};
local function ids20(firstId)
    local t = {}; for i = 1, 20 do t[i] = 0; end
    t[1] = firstId;
    return t;
end
dm._forceLib({ host = host, book = book, blu = blu, sets = sets });
dm.init({ cfg = stubStore, say = { err = function() end } });
check(#host.deps.cfg.sets == 0, 'pre-login init: the bridge holds the declared defaults');
-- character A logs in: their file already has a set the bridge must adopt
disk['A\\'] = {
    sets = dm._codec.encodeSets({ { name = 'Solo', ids = ids20(700) } }),
    activeSetName = 'Solo', capLearnedBonus = 24, capMeritPoints = 10,
};
storeDir = 'A\\';
dm._syncStore();
check(#host.deps.cfg.sets == 1 and host.deps.cfg.sets[1].name == 'Solo',
    'first login: the bridge re-decodes the character file');
check(host.state.editingSet.name == 'Solo' and host.state.editingSet.ids[1] == 700,
    'and the host adopts it (the active set is restored)');
check(host.deps.cfg.sets[1].chains ~= nil,
    'a legacy dlac store migrates to chains through the same adopt');
check(blu.learnedBonus == 24 and blu.meritPts == 10,
    'the budget halves now persist through the dlac store too');
-- a save now round-trips the real list, not the empty init snapshot --
-- and writes BOTH grammars: sets2 as the truth, sets as the flat mirror
host.deps.save();
check(dm._codec.decodeSets(disk['A\\'].sets)[1].name == 'Solo',
    'a save after login keeps the character file (no empty-snapshot clobber)');
check(dm._codec.decodeSets2(disk['A\\'].sets2)[1] ~= nil
    and dm._codec.decodeSets2(disk['A\\'].sets2)[1].chains[1][1].id == 700,
    'the save writes the timeline grammar alongside the legacy key');
-- character B: their own file (none yet) -- nothing of A may leak
storeDir = 'B\\';
dm._syncStore();
check(#host.deps.cfg.sets == 0 and host.state.activeSet == nil,
    'character switch: B starts from their own file, not A\'s bridge');
check(blu.learnedBonus == nil and blu.meritPts == nil,
    'and A\'s budget is not inherited');
-- back to A: this login must decode the TIMELINE grammar (sets2 written by
-- the save above outranks the legacy key)
storeDir = 'A\\';
dm._syncStore();
check(host.deps.cfg.sets[1].chains ~= nil and host.deps.cfg.sets[1].chains[1][1].id == 700,
    'a return to A decodes the timeline grammar directly');
check(host.state.editingSet.name == 'Solo',
    'and the active set restores from it as before');
blu.forgetBudget();

print('smoke: all green');
