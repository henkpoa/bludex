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

print('smoke: SoA burst spell traits (bg-wiki 2026-08-08)');
-- Henrik's call: the wiki is authoritative for everything but the level;
-- traits, MP etc. are the same on CatsEyeXI. Each spell feeds weight 8.
check(book.spells[719].trait.category == 8 and book.spells[719].trait.weight == 8,
    'Searing Tempest feeds Attack Bonus at weight 8');
check(book.spells[720].trait.category == 6, 'Spectral Floe feeds Magic Atk. Bonus');
check(book.spells[721].trait.category == 16, 'Anvil Lightning feeds Accuracy Bonus');
check(book.spells[722].trait.category == 11, 'Entomb feeds Defense Bonus');
check(book.spells[725].trait.category == 29, 'Blinding Fulgor feeds Magic Eva. Bonus');
check(book.spells[726].trait.category == 13, 'Scouring Spate feeds Magic Def. Bonus');
check(book.spells[727].trait.category == 18, 'Silent Storm feeds Evasion Bonus');
check(book.spells[728].trait.category == 30, 'Tenebral Crush feeds Magic Acc. Bonus');
check(book.traits.categories[29] ~= nil and book.traits.categories[29].name == 'Magic Eva. Bonus'
    and book.traits.categories[29].tiers[1].points == 8
    and book.traits.categories[29].traitId == 126,
    'the Magic Eva. Bonus addendum ladder exists (trait.h 126, tier at 8)');
check(book.traits.categories[30] ~= nil and book.traits.categories[30].traitId == 125,
    'the Magic Acc. Bonus addendum ladder exists (trait.h 125)');
local soa = sets.new('SoA');
check(sets.add(soa, 720, book, 99), 'Spectral Floe joins a set');
local mab = nil;
for _, ev in ipairs(sets.traitEval(soa, book)) do
    if ev.cat == 6 then mab = ev; end
end
check(mab ~= nil and mab.tier ~= nil,
    'one SoA spell activates its trait outright (weight 8 clears the tier)');
local hasFloe = false;
for _, id in ipairs(book.filter({ traitCat = 6 })) do
    if id == 720 then hasFloe = true; end
end
check(hasFloe, 'the trait filter finds Spectral Floe under Magic Atk. Bonus');

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

-- a new (kindless) set is a timeline; a v1 set STAYS FLAT under the v3
-- adopt (docs/set-types-plan.md 1: the kinds stamp, nothing converts --
-- the v2 chains-for-everyone migration is repealed)
local v2 = sets.new('V2');
check(v2.builtFor == 75 and v2.chains ~= nil and #v2.chains[1] == 0,
    'new sets carry builtFor 75 and empty chains');
check(sets.kindOf(v2) == 'timeline', 'and they are timeline kind');
check(sets.upgrade(v2, book) == false, 'upgrade is a no-op on a fresh v2 set');
local v1 = { name = 'Old', ids = {} };
for i = 1, 20 do v1.ids[i] = 0; end
v1.ids[3] = 529;      -- Bludgeon 18
v1.ids[9] = 603;      -- Wild Oats 4
check(sets.upgrade(v1, book) == true, 'a v1 set is stamped by the v3 adopt');
check(v1.kind == 'flat' and v1.chains == nil,
    'and it STAYS FLAT -- no chains are built for it');
check(v1.ids[3] == 529 and v1.ids[9] == 603,
    'its ids are untouched, slots and all');
check(sets.upgrade(v1, book) == false, 'the stamp is idempotent');
local rv = sets.resolveAtLevel(v1, 10, book);
check(rv[3] == 529 and rv[9] == 603,
    'a flat set resolves VERBATIM at every level (the client handles sync)');

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
local rmm = sets.new('RM');
check(sets.addEntry(rmm, 1, 529, nil, book) and sets.addEntry(rmm, 1, 603, 30, book),
    'mirror fixture builds (Bludgeon 18-29, Wild Oats 30-75)');
sets.removeId(rmm, 603);
check(rmm.ids[1] == 529,
    'removeId re-derives the mirror: the exposed predecessor returns at 75 (review)');
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
check(sets.kindOf(legacy) == 'flat', 'a bare-ids table reads as a flat set');
check(sets.resolveAtLevel(legacy, 75, book)[1] == 529
    and sets.resolveAtLevel(legacy, 17, book)[1] == 529,
    'and it resolves VERBATIM at every level (kinds era: no on-the-fly chains)');

print('smoke: the three set kinds (docs/set-types-plan.md)');
-- kindOf: an explicit kind wins; otherwise the shape speaks
check(sets.kindOf({ name = 'x', ids = {} }) == 'flat'
    and sets.kindOf({ name = 'x', ids = {}, builds = {} }) == 'levels'
    and sets.kindOf({ name = 'x', chains = {} }) == 'timeline',
    'kindOf infers by shape: bare ids flat, builds levels, chains timeline');
local fl = sets.new('Flatty', 'flat');
check(fl.kind == 'flat' and fl.chains == nil and fl.builds == nil,
    'new flat: ids only, no chains, no builds');
local lv = sets.new('Bandy', 'levels');
check(lv.kind == 'levels' and lv.chains == nil and #lv.builds == 0,
    'new levels: ids (the base build) plus an empty build list');
check(sets.new('T').kind == 'timeline', 'new without a kind stays timeline');

-- the rungs (the 2026-08-06 law, back with the levels kind)
check(sets.rungFor(40) == 31 and sets.rungFor(75) == 71 and sets.rungFor(1) == 1,
    'rungFor: 40 -> 31, 75 -> 71, 1 -> 1');
check(sets.rungFor(nil) == nil and sets.rungFor(0) == nil, 'no level, no rung');
check(sets.bandTop(41) == 50 and sets.bandTop(71) == 75 and sets.bandTop(nil) == 75,
    'bands: 41-50, 71-75, and level-less reaches the cap');

-- flat editing runs the id-array path end to end
check(sets.add(fl, 623, book, 80) and fl.ids[1] == 623,
    'flat add lands in the first free slot');
check(sets.resolveAtLevel(fl, 5, book)[1] == 623,
    'and resolves verbatim below the spell\'s level');
local flc = sets.clone(fl, fl.name);
check(flc.kind == 'flat' and sets.equal(fl, flc), 'flat clone equals its source');
flc.ids[2] = 603;
check(not sets.equal(fl, flc), 'one id apart is not equal');
check(not sets.equal(fl, lv), 'kinds never compare equal across each other');

-- the group API: band-else-base, exactly the old semantics
check(sets.add(lv, 603, book, 999), 'the base build takes adds (level nil)');
check(sets.groupAdd(lv, 41) and sets.groupBuild(lv, 41) ~= nil,
    'a band is added on purpose');
check(not sets.groupAdd(lv, 45), 'a level that is not a rung is not a band');
check(sets.groupPick(lv, 45) == nil,
    'an added-but-EMPTY band is not picked - the base answers');
sets.groupPut(lv, 41, { [1] = 529 });
check(sets.groupPick(lv, 45) == 41, 'the band with its own build answers for 41-50');
check(sets.groupPick(lv, 25) == nil, 'an unbuilt band falls back to the base');
check(sets.resolveAtLevel(lv, 45, book)[1] == 529
    and sets.resolveAtLevel(lv, 25, book)[1] == 603,
    'resolveAtLevel speaks groupPick: the band build at 45, the base at 25');
local lvEmpty = sets.new('NoBase', 'levels');
sets.groupAdd(lvEmpty, 21);
sets.groupPut(lvEmpty, 21, { [1] = 603 });
check(sets.groupPick(lvEmpty, 45) == 21 and sets.groupPick(lvEmpty, 5) == 21,
    'an EMPTY base falls back to the nearest built band, either side');
local lvc = sets.clone(lv, lv.name);
check(sets.equal(lv, lvc), 'levels clone equals its source, builds included');
sets.groupPut(lvc, 71, { [1] = 623 });
check(not sets.equal(lv, lvc), 'a new band build is authorship');

-- the draft: one build as the editing surface, its band's ceilings live
local d = sets.draft(lv, 41);
check(d.kind == 'levels' and d.draft == true and d.ids[1] == 529,
    'draft carries the band\'s ids and names itself a draft');
check(sets.slotMax(d) == 14, 'a Lv.41 draft owns its band\'s 14 slots');
check(sets.slotMax(sets.draft(lv, nil)) == 20, 'the base draft keeps all 20');
local d1 = sets.draft(lv, 1);
check(select(2, sets.canAdd(d1, 529, book, 999))
    == 'needs Lv.18 - this set stops at 10',
    'the band-top ceiling: Bludgeon has no business in a Lv.1 build');
for i = 1, 6 do d1.ids[i] = 100 + i; end
check(select(2, sets.canAdd(d1, 603, book, 999)) == 'no free slot (Lv.1 has 6)',
    'the slot ceiling: Lv.1 has six, and the seventh is refused by name');

-- upgrade stamps kinds and is idempotent, per shape
local raw = { name = 'L', ids = {}, builds = { { level = 41, ids = {} } } };
check(sets.upgrade(raw, book) == true and raw.kind == 'levels',
    'a builds-shaped store entry is stamped levels');
check(sets.upgrade(raw, book) == false, 'and the stamp is idempotent');

print('smoke: kind conversion (the flat projection is the bridge)');
do
-- flat -> anywhere: lossless, and the source is never touched
local cf = sets.new('Conv', 'flat');
sets.add(cf, 529, book, 80); sets.add(cf, 603, book, 80);
check(#sets.convertLoss(cf, 'levels', book) == 0
    and #sets.convertLoss(cf, 'timeline', book) == 0,
    'a flat set converts anywhere losslessly');
local cl = sets.convertTo(cf, 'levels', book);
check(cl.kind == 'levels' and cl.name == 'Conv' and cl.ids[1] == 529
    and #cl.builds == 0, 'flat -> levels: the ids become the base build');
local ct = sets.convertTo(cf, 'timeline', book);
check(ct.kind == 'timeline' and ct.chains[1][1].id == 603,
    'flat -> timeline: sorted placement, lowest level in the lowest slot');
check(cf.kind == 'flat' and cf.ids[1] == 529, 'the source is never mutated');

-- levels -> flat: the base crosses; builds and a stored rule are NAMED
sets.groupAdd(cl, 41);
sets.groupPut(cl, 41, { [1] = 549 });
cl.rule = 'switch';
local closs = sets.convertLoss(cl, 'flat', book);
check(#closs == 2 and closs[1]:find('1 level build', 1, true) ~= nil
    and closs[2]:find('switch', 1, true) ~= nil,
    'levels -> flat names the build and the stored rule it drops');
local cback = sets.convertTo(cl, 'flat', book);
check(cback.kind == 'flat' and cback.ids[1] == 529 and cback.builds == nil,
    'and the base build is what crosses');

-- timeline -> flat: flat-shaped crosses clean; a real timeline is named
check(#sets.convertLoss(ct, 'flat', book) == 0,
    'a flat-shaped timeline converts back losslessly');
local deep = sets.new('Deep');
check(sets.addEntry(deep, 1, 603, nil, book)
    and sets.addEntry(deep, 1, 529, nil, book), 'conversion fixture stacks a chain');
local dloss = sets.convertLoss(deep, 'flat', book);
check(#dloss == 1 and dloss[1]:find('1 entry beyond', 1, true) ~= nil,
    'timeline -> flat counts the entries the Lv.75 plan leaves behind');
sets.pushBackup(deep, deep, 1000);
check(#sets.convertLoss(deep, 'levels', book) == 1,
    'backups are NOT a named loss -- the ring crosses with the set');
local dflat = sets.convertTo(deep, 'flat', book);
check(dflat.kind == 'flat' and dflat.ids[1] == 529,
    'what crosses is the Lv.75 plan (Bludgeon, not the retired Wild Oats)');

-- same kind = a plain clone: timeline detail and backups survive intact
local dsame = sets.convertTo(deep, 'timeline', book);
check(dsame.chains[1][2] ~= nil and #(dsame.backups or {}) == 1,
    'convert to the same kind is a full clone, nothing projected away');
end

print('smoke: backups for every kind (and the conversion undo)');
do
-- a flat ring: bank, mutate, restore, and the replaced state banks in turn
local bf1 = sets.new('B', 'flat'); bf1.ids[1] = 529;
sets.pushBackup(bf1, bf1, 100);
check(bf1.backups[1].kind == 'flat' and bf1.backups[1].ids[1] == 529
    and bf1.backups[1].chains == nil, 'a flat backup banks ids, not chains');
bf1.ids[1] = 603;
check(sets.restoreBackup(bf1, 1, book, 200) and bf1.ids[1] == 529,
    'restoring puts the flat ids back');
check(bf1.backups[1].ids[1] == 603, 'and banks the replaced state as backup 1');

-- a levels ring carries base, builds and the stored rule
local bl = sets.new('BL', 'levels'); bl.ids[1] = 529;
sets.groupAdd(bl, 41); sets.groupPut(bl, 41, { [1] = 549 }); bl.rule = 'switch';
sets.pushBackup(bl, bl, 100);
check(bl.backups[1].kind == 'levels' and bl.backups[1].builds[1].level == 41
    and bl.backups[1].rule == 'switch',
    'a levels backup banks base, builds and rule');
sets.groupRemove(bl, 41); bl.rule = nil;
check(sets.restoreBackup(bl, 1, book, 200)
    and sets.groupBuild(bl, 41) ~= nil and bl.rule == 'switch',
    'restoring brings the builds and the rule back');

-- THE CONVERSION UNDO (the flow setsui's Convert runs: the ring crosses
-- and the state being left banks on it): convert away, restore backup 1,
-- and the set is its OLD KIND again
local csrc = sets.new('CU', 'levels'); csrc.ids[1] = 529;
sets.groupAdd(csrc, 41); sets.groupPut(csrc, 41, { [1] = 549 });
local cnv = sets.convertTo(csrc, 'flat', book);
cnv.backups = csrc.backups;
sets.pushBackup(cnv, csrc, 300);
check(sets.kindOf(cnv) == 'flat' and cnv.builds == nil,
    'converted: a flat set, the builds gone');
check(sets.restoreBackup(cnv, 1, book, 400), 'the ring takes the restore');
check(sets.kindOf(cnv) == 'levels' and sets.groupBuild(cnv, 41) ~= nil
    and sets.groupBuild(cnv, 41).ids[1] == 549,
    'and the set is its old kind again, band build and all');
check(cnv.chains == nil and cnv.builtFor == nil,
    'with no other kind\'s fields left to shadow');
check(cnv.backups[1].kind == 'flat',
    'the flat state it replaced banked in turn -- the undo is undoable');
end

print('smoke: share text (one set, one pasteable line)');
do
-- every kind round-trips whole through its share line
local sf = sets.new('My|Set ~ 100%', 'flat'); sf.ids[1] = 529; sf.ids[7] = 603;
local line = sets.shareText(sf);
check(line:find('^BDXSET1|') ~= nil and line:find('\t') == nil,
    'the line is one BDXSET1 token, no tabs anywhere');
local rf, why = sets.parseShare(line);
check(rf ~= nil and rf.name == 'My|Set ~ 100%' and sets.equal(sf, rf),
    'a flat set round-trips, awkward name and all');

local sl = sets.new('Climb', 'levels'); sl.ids[1] = 529;
sets.groupAdd(sl, 41); sets.groupPut(sl, 41, { [1] = 549 });
sl.rule = 'switch';
local rl = sets.parseShare(sets.shareText(sl));
check(rl ~= nil and sets.equal(sl, rl)
    and rl.rule == 'switch' and rl.builds[1].level == 41,
    'a levels set round-trips: base, rule and builds');

local stl = sets.new('Plan');
check(sets.addEntry(stl, 1, 603, nil, book)
    and sets.addEntry(stl, 1, 529, nil, book), 'share fixture stacks a chain');
stl.builtFor = 30;
sets.pushBackup(stl, stl, 100);
local rt = sets.parseShare(sets.shareText(stl));
check(rt ~= nil and sets.equal(stl, rt) and rt.builtFor == 30,
    'a timeline round-trips: chains and builtFor');
check(rt.backups == nil, 'and backups never travel');

-- the paste side is forgiving where it can be, strict where it must be
local framed = 'Mindie: ' .. sets.shareText(sf) .. '  ';
check(sets.parseShare(framed) ~= nil, 'chat framing around the line is fine');
local damaged = sets.shareText(sf):gsub('BDXSET1|flat', 'BDXSET1|falt');
local _, dwhy = sets.parseShare(damaged);
check(dwhy ~= nil and dwhy:find('damaged', 1, true) ~= nil,
    'a mangled body fails the checksum with a reason');
local _, twhy = sets.parseShare('hello there');
check(twhy ~= nil and twhy:find('BDXSET1', 1, true) ~= nil,
    'plain text is refused by name');
local trunc = sets.shareText(sl):sub(1, 40);
check(sets.parseShare(trunc) == nil,
    'a truncated paste imports nothing (never half a set)');
end

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
-- the legacy decoder and the kinds: bare lines stay flat, build lines mean
-- levels (a pre-timeline store with level lines must adopt as that kind)
check(dm._codec.decodeSets('Solo\t' .. dm._codec.encodeIds(ids))[1].builds == nil,
    'a bare legacy line decodes with NO builds table (reads as flat)');
local lvLegacy = dm._codec.decodeSets(
    'Climb\t' .. dm._codec.encodeIds(ids) .. '\n'
    .. 'Climb\t41\t' .. dm._codec.encodeIds(ids) .. '\n'
    .. 'Climb\trule\tswitch');
check(lvLegacy[1].builds ~= nil and lvLegacy[1].builds[1].level == 41
    and lvLegacy[1].rule == 'switch',
    'legacy level and rule lines decode into a levels-shaped entry');

-- the KINDS grammar (sets3): one line per set, kind first, lossless for
-- all three -- and tolerant of lines it does not know
local trio = {
    { kind = 'flat', name = 'F', ids = ids },
    { kind = 'levels', name = 'L', ids = ids, rule = 'switch',
      builds = { { level = 41, ids = ids } } },
    { kind = 'timeline', name = 'T', builtFor = 30,
      chains = { { { id = 623, from = 5 } } } },
};
local rt3 = dm._codec.decodeSets3(dm._codec.encodeSets3(trio));
check(#rt3 == 3, 'sets3 round-trips all three kinds');
check(rt3[1].kind == 'flat' and rt3[1].ids[7] == 700, 'the flat line survives');
check(rt3[2].kind == 'levels' and rt3[2].rule == 'switch'
    and rt3[2].builds[1].level == 41 and rt3[2].builds[1].ids[1] == 623,
    'the levels line carries base, rule and builds');
check(rt3[3].kind == 'timeline' and rt3[3].builtFor == 30
    and rt3[3].chains[1][1].id == 623 and rt3[3].chains[1][1].from == 5,
    'the timeline line is the sets2 line, tagged');
check(#dm._codec.decodeSets3('#v3\nwibble\tX\t1,2,3') == 0,
    'an unknown kind drops the line, never the file');

-- kind-shaped backups on the wire: one ring, all three kinds, round-tripped
do
local bakSrc = { { name = 'F', ids = ids, backups = {
    { ts = 1, kind = 'flat', name = 'F', ids = ids },
    { ts = 2, kind = 'levels', name = 'F', ids = ids, rule = 'switch',
      builds = { { level = 41, ids = ids } } },
    { ts = 3, kind = 'timeline', name = 'F', builtFor = 30,
      chains = { { { id = 623, from = 5 } } } },
} } };
local bakDst = { { name = 'F', ids = ids } };
dm._codec.attachBackups(bakDst, dm._codec.encodeBackups(bakSrc));
local ring = bakDst[1].backups;
check(#ring == 3, 'a mixed-kind ring round-trips whole');
check(ring[1].kind == 'flat' and ring[1].ids[7] == 700,
    'the flat backup line survives');
check(ring[2].kind == 'levels' and ring[2].rule == 'switch'
    and ring[2].builds[1].level == 41 and ring[2].builds[1].ids[1] == 623,
    'the levels backup line carries base, rule and builds');
check(ring[3].kind == 'timeline' and ring[3].builtFor == 30
    and ring[3].chains[1][1].id == 623,
    'the timeline backup line is unchanged from the v2 days');
end

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
-- decode tolerance sharpened by review 2026-08-08: a corrupt builtFor
-- clamps (0 would enforce everything, 200 nothing), an out-of-order chain
-- re-sorts (resolveAtLevel breaks at the first later entry), and duplicate
-- names hand the ring to the FIRST set (the activeSetName rule)
local oo = dm._codec.decodeSets2('#v2\nOO\t0\t529@18,603@4');
check(oo[1].builtFor == 75, 'a corrupt builtFor clamps to 75');
check(oo[1].chains[1][1].from == 4 and oo[1].chains[1][2].from == 18,
    'an out-of-order stored chain re-sorts on decode');
local dupA, dupB = sets.new('D'), sets.new('D');
local dup = { dupA, dupB };
dm._codec.attachBackups(dup,
    'D\t5\t75\t' .. dm._codec.encodeChains(sets.new('D').chains));
check(dupA.backups ~= nil and dupB.backups == nil,
    'duplicate names: the first set gets the ring');

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
check(aCfg.setsModelVer == 3, 'and stamps setsModelVer 3 (the kinds era)');
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

print('smoke: timeline apply verbs (applyState / applyEditing / checkReplan)');
-- setsui owns the verbs; a stubbed game layer drives them headless.
local setsuiM = require('bludex\\ui\\setsui');
local stubLive = { lvl = 20, live = nil, applied = nil };
local _cur, _eff, _can, _onb, _diff, _ann =
    blu.currentSet, blu.effectiveLevel, blu.canApply, blu.onBlu, blu.applyDiff, blu.announce;
blu.currentSet = function() return stubLive.live or {}; end
blu.effectiveLevel = function() return stubLive.lvl; end
blu.canApply = function() return true; end
blu.onBlu = function() return true; end
blu.applyDiff = function(ids) stubLive.applied = ids; return true; end
local said = nil;
blu.announce = function(s) said = s; end
local function live20(t)
    local out = {};
    for i = 1, 20 do out[i] = t[i] or 0; end
    return out;
end

local plan = sets.new('Plan');
check(sets.addEntry(plan, 1, 603, nil, book)
    and sets.addEntry(plan, 1, 529, nil, book), 'verb fixture builds');
local vcfg = mkcfg();
local vst = { editingSet = plan, activeSet = nil, applyNote = nil };
local vctx = { im = {}, book = book, blu = blu, sets = sets, cfg = vcfg,
    save = function() end, state = vst,
    budgetMax = function() return 80; end };

-- the consolidated three-state compare
stubLive.live = live20({ [1] = 529 });
check(setsuiM.applyState(vctx) == 'clean', 'applyState: live == the plan for the live level');
stubLive.live = live20({});
check(setsuiM.applyState(vctx) == 'dirty', 'applyState: an empty live set is dirty');
stubLive.live = nil;
check(setsuiM.applyState(vctx) == nil, 'applyState: an unreadable live set answers nil');

-- the preemptive apply (plan 2.9): send the Lv.4 plan while standing at 20,
-- and be recognized afterwards instead of glowing dirty
setsuiM.applyEditing(vctx, 4);
check(stubLive.applied ~= nil and stubLive.applied[1] == 603
    and stubLive.applied[2] == 0, 'Apply for Lv.4 sends the Wild Oats plan');
check(vcfg.lastApplied.level == 4, 'lastApplied remembers the level the plan was FOR');
stubLive.live = live20({ [1] = 603 });
local vs, vl = setsuiM.applyState(vctx);
check(vs == 'planned' and vl == 4, 'applyState: live matches the Lv.4 plan -> planned, not dirty');
stubLive.applied = nil;
setsuiM.applyEditing(vctx);
check(stubLive.applied ~= nil and stubLive.applied[1] == 529 and vcfg.lastApplied.level == 20,
    'a plain Apply resolves at the live level');

-- the band block (plan 2.6): a known budget, a leveling builtFor, and a
-- low bracket stuffed past it -- Apply refuses with the band message;
-- builtFor 75 un-enforces the same bands and Apply works again
blu.learnedBonus, blu.meritPts = 0, 0;
plan.builtFor = 1;
local lowIds = {};
for _, id in ipairs(book.filter({})) do
    local sp = book.spells[id];
    if sp.level ~= nil and sp.level <= 10 and sp.setPoints ~= nil and id ~= 603 then
        lowIds[#lowIds + 1] = id;
    end
end
-- dearest first, and only into the six level-1 slots -- the 11+ slots'
-- floors would keep anything there out of the level-10 resolution
table.sort(lowIds, function(a, b)
    return (book.spells[a].setPoints or 0) > (book.spells[b].setPoints or 0);
end);
local slotN = 2;
while slotN <= 6
    and sets.usedPoints(sets.resolveAtLevel(plan, 10, book), book) <= 10 and #lowIds > 0 do
    check(sets.addEntry(plan, slotN, table.remove(lowIds, 1), nil, book),
        'fixture: low spell joins its own chain');
    slotN = slotN + 1;
end
check(sets.usedPoints(sets.resolveAtLevel(plan, 10, book), book) > 10,
    'fixture: the low bracket overflows a 10-point budget');
stubLive.live = live20({});
stubLive.applied = nil;
vst.applyNote = nil;
setsuiM.applyEditing(vctx);
check(stubLive.applied == nil and type(vst.applyNote) == 'string'
    and vst.applyNote:find('Cannot apply: ', 1, true) == 1
    and vst.applyNote:find('above threshold', 1, true) ~= nil,
    'an enforced band blocks Apply with the band message');
plan.builtFor = 75;
setsuiM.applyEditing(vctx);
check(stubLive.applied ~= nil, 'builtFor 75 un-enforces the low bands; Apply works again');
blu.learnedBonus, blu.meritPts = nil, nil;

-- the level-change watcher: nudge on new spells, silence on removals-only
-- (the flat-set-under-sync case), auto mode applies by itself
local plan2 = sets.new('Watch');
sets.addEntry(plan2, 1, 603, nil, book);
sets.addEntry(plan2, 1, 529, nil, book);
host.onSettingsSwap(vcfg, 'Verb_101');
host.state.editingSet = plan2;
stubLive.lvl = 3;
stubLive.live = live20({});
said = nil;
host.checkReplan();
check(host.state.replanPending == nil, 'nothing activates at Lv.3 -> clean, no nudge');
stubLive.lvl = 4;
host.checkReplan();
check(host.state.replanPending ~= nil and host.state.replanPending.level == 4
    and type(said) == 'string' and said:find('Level 4', 1, true) ~= nil,
    'a level with new spells arms the nudge and says one line');
stubLive.lvl = 20;
stubLive.live = live20({ [1] = 529, [2] = 623 });   -- plan(20) plus an extra
host.state.replanPending = { level = 99 };
host.checkReplan();
check(host.state.replanPending == nil,
    'a removals-only diff stays quiet (the client\'s own disable handles it)');
vcfg.replan = 'auto';
stubLive.live = live20({});
stubLive.applied = nil;
host.checkReplan();
check(stubLive.applied ~= nil and stubLive.applied[1] == 529
    and vcfg.lastApplied.level == 20, 'replan=auto applies the plan for the settled level');
vcfg.replan = 'manual';

-- the backup ring DEEPENS through consecutive saves (review 2026-08-08:
-- cloning the editing set's selection-time ring reset the depth to one)
local rcfg = mkcfg();
local rst = { editingSet = nil, activeSet = 1, applyNote = nil };
local rctx = { state = rst, cfg = rcfg, sets = sets, book = book, blu = blu,
    save = function() end };
local ring0 = sets.new('Ring');
sets.addEntry(ring0, 1, 603, nil, book);
rcfg.sets = { ring0 };
rst.editingSet = sets.clone(ring0, 'Ring');
sets.addEntry(rst.editingSet, 1, 529, nil, book);
setsuiM.saveEditing(rctx);
check(#(rcfg.sets[1].backups or {}) == 1, 'the first save-over banks the original');
rst.editingSet = sets.clone(rcfg.sets[1], 'Ring');
sets.addEntry(rst.editingSet, 1, 0, 45, book);
setsuiM.saveEditing(rctx);
check(#(rcfg.sets[1].backups or {}) == 2,
    'the second save-over deepens the ring to two');
check(#rcfg.sets[1].backups[1].chains[1] == 2 and #rcfg.sets[1].backups[2].chains[1] == 1,
    'newest first: backup 1 is the two-entry state, backup 2 the original');

blu.currentSet, blu.effectiveLevel, blu.canApply, blu.onBlu, blu.applyDiff, blu.announce =
    _cur, _eff, _can, _onb, _diff, _ann;
blu.learnedBonus, blu.meritPts = nil, nil;

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
check(host.deps.cfg.sets[1].chains == nil
    and sets.kindOf(host.deps.cfg.sets[1]) == 'flat',
    'a legacy dlac store adopts as FLAT (kinds era: nothing converts)');
check(blu.learnedBonus == 24 and blu.meritPts == 10,
    'the budget halves now persist through the dlac store too');
-- a save now round-trips the real list, not the empty init snapshot --
-- and writes EVERY grammar: sets3 the truth, sets2 the timeline sets only
-- (this one is flat, so sets2 stays empty), sets the tolerant mirror
host.deps.save();
check(dm._codec.decodeSets(disk['A\\'].sets)[1].name == 'Solo',
    'a save after login keeps the character file (no empty-snapshot clobber)');
local v3rt = dm._codec.decodeSets3(disk['A\\'].sets3);
check(v3rt[1] ~= nil and v3rt[1].kind == 'flat' and v3rt[1].ids[1] == 700,
    'the save writes the kinds grammar (sets3) as the truth');
check(#dm._codec.decodeSets2(disk['A\\'].sets2) == 0,
    'and sets2 carries timeline sets only (a flat set has no line there)');
-- character B: their own file (none yet) -- nothing of A may leak
storeDir = 'B\\';
dm._syncStore();
check(#host.deps.cfg.sets == 0 and host.state.activeSet == nil,
    'character switch: B starts from their own file, not A\'s bridge');
check(blu.learnedBonus == nil and blu.meritPts == nil,
    'and A\'s budget is not inherited');
-- back to A: this login must decode the KINDS grammar (sets3 written by
-- the save above outranks both older keys) -- and the set is still flat
storeDir = 'A\\';
dm._syncStore();
check(sets.kindOf(host.deps.cfg.sets[1]) == 'flat'
    and host.deps.cfg.sets[1].ids[1] == 700,
    'a return to A decodes the kinds grammar directly, flat staying flat');
check(host.state.editingSet.name == 'Solo',
    'and the active set restores from it as before');
blu.forgetBudget();

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

print('smoke: the level-change rule (the levels kind\'s watcher)');
-- The one rule that sends packets on its own, so it is driven end to end
-- here with a stub client. What it must get right: fire only when the level
-- crosses into a band THAT HAS ITS OWN BUILD, equip that, and stay silent
-- otherwise -- a band change that costs a 60s cast lock for no reason is
-- the failure that matters. Everywhere else Lvl Set Switch behaves as
-- Restore does, adds-only (the restoreMissing path). And it runs ONLY when
-- the followed set is the LEVELS kind -- the timeline keeps its re-plan.
local fake;                      -- declared first: the stubs close over it
fake = {
    level = 75, live = {}, applied = nil, says = {}, applying = false,
    watchCap = function() end,
    watchJobState = function() return fake.jobChange; end,
    effectiveLevel = function() return fake.level; end,
    canApply = function() return true; end,
    onBlu = function() return true; end,
    currentSet = function() return fake.live; end,
    announce = function(s) fake.says[#fake.says + 1] = s; end,
    -- the adds-only path Restore (and Lvl Set Switch, off a band build) uses
    restoreMissing = function(ids) fake.restored = ids; return true; end,
    reportLevelDown = function() fake.downReports = (fake.downReports or 0) + 1; end,
    applyDiff = function(ids) fake.applied = ids; return true; end,
};
for i = 1, 20 do fake.live[i] = 0; end
local fcfg = {
    sets = {},
    lastApplied = {}, lastAppliedSet = 'Solo',
    capModelVer = 3, capLearnedBonus = 24, capMeritPoints = 10,
    activeSetName = '', replan = 'manual',
};
local flat20 = {}; for i = 1, 20 do flat20[i] = 0; end
flat20[1] = 623; flat20[2] = 513;                  -- the base build: 2 spells
local low  = {}; for i = 1, 20 do low[i] = 0; end
low[1] = 549;                                      -- the Lv.31 build: 1 spell
fcfg.sets[1] = { name = 'Solo', ids = flat20, builds = { { level = 31, ids = low } } };
host.init({ book = book, blu = fake, sets = sets, cfg = fcfg, save = function() end });
check(sets.kindOf(fcfg.sets[1]) == 'levels',
    'the adopt stamped the followed set as the levels kind');
host.lastRung, host.switchCheck, host.restoreChecks = nil, nil, nil;

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
check(#fake.says == 1 and fake.says[1]:find('Lv.31 build of "Solo"', 1, true) ~= nil,
    'and says which build it equipped, by name');
check(fcfg.lastApplied.ids ~= nil and fcfg.lastApplied.ids[1] == 549,
    'and the last-applied snapshot follows the switch');
fake.live = sets.sortedLayout(low, book);          -- the game now holds it
fake.applied = nil;
fake.level = 45;                                   -- up into the Lv.41 band
tickNow();
check(fake.applied == nil,
    'a band with no build of its own equips nothing outright...');
check(sets.groupPick(fcfg.sets[1], 45) == nil,
    '...it is the base build that serves there, restore-style');
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

-- THE RESTORE PATH rides a settled job-state change, adds-only, twice
fake.level = 75;
fake.jobChange = 'up'; host.tick(); fake.jobChange = nil;
check(host.restoreChecks ~= nil and host.replanCheck ~= nil,
    'a level up arms the restore checks (and the settle for the re-plan gate)');
host.restoreChecks = { 0 };
host.tick();
check(fake.restored ~= nil and fake.restored[1] == 623,
    'the restore targets the followed set\'s build for HERE (the base at 75)');
check(host.restoreChecks == nil, 'and the check queue drains');
host.replanCheck = 0; host.tick();
check(host.state.replanPending == nil,
    'the timeline re-plan STOOD DOWN: the armed levels rule owns the change');

-- a level DOWN sends nothing and keeps its report -- unless the switch is
-- about to act, whose own line makes the report noise
fake.restored = nil;
fake.level = 40;
fake.live = sets.sortedLayout(flat20, book);       -- wearing the base build
fake.jobChange = 'down'; host.tick(); fake.jobChange = nil;
check(host.restoreChecks == nil, 'a level down never arms the restore');
host.downCheck = 0; host.tick();
check((fake.downReports or 0) == 0,
    'the down report is suppressed while the switch is about to act');
fake.level = 45; host.lastRung = 41; host.switchCheck = nil;
fake.jobChange = 'down'; host.tick(); fake.jobChange = nil;
host.downCheck = 0; host.tick();
check((fake.downReports or 0) == 1,
    'and speaks when it is not (no band build at 41-50)');

-- the rule lives on the SET, and Manual means Manual
fake.applied = nil;
fcfg.sets[1].rule = 'manual';
fake.live = sets.sortedLayout(flat20, book);
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
-- a FLAT followed set arms nothing either -- the kind gate, not just the name
fcfg.lastAppliedSet = 'Plain';
fcfg.sets[2] = { kind = 'flat', name = 'Plain', ids = flat20 };
fake.level = 75; tickNow();
fake.level = 40; tickNow();
check(fake.applied == nil, 'a followed FLAT set arms no level rule (the kind gate)');

print('smoke: the Sets tab renders (the chooser and all three kinds)');
-- the same law as the Traits tab render: an unknown Lua name is a silent
-- nil GLOBAL until the line runs, and in game the tab draws inside pcall.
-- Drive the REAL render against the stub binding and let a typo throw HERE
-- -- the chooser, the flat planner, the levels draft and the timeline all
-- take their own code paths now.
do
    local sdrew = {};
    local sIm = {};
    for k, v in pairs(stubIm) do sIm[k] = v; end
    sIm.Text = function(s) sdrew[#sdrew + 1] = tostring(s); end
    sIm.TextColored = function(_, s) sdrew[#sdrew + 1] = tostring(s); end
    sIm.TextWrapped = function(s) sdrew[#sdrew + 1] = tostring(s); end
    sIm.SetTooltip = function(s) sdrew[#sdrew + 1] = tostring(s); end
    sIm.Selectable = function(label) sdrew[#sdrew + 1] = tostring(label); return false; end
    sIm.Button = function(label) sdrew[#sdrew + 1] = tostring(label); return false; end
    sIm.InputText = function() return false; end
    sIm.SliderInt = function() return false; end
    sIm.BeginChild = function() return true; end
    sIm.EndChild = function() end;

    local _cur2, _eff2, _onb2, _bud2, _sync2, _rc2 =
        blu.currentSet, blu.effectiveLevel, blu.onBlu, blu.budget,
        blu.syncStats, blu.rungCap;
    blu.currentSet = function() return {}; end
    blu.effectiveLevel = function() return 42; end
    blu.onBlu = function() return true; end
    blu.budget = function() return 60; end
    blu.syncStats = function() return nil; end

    local rcfg = mkcfg();
    local fset = sets.new('Flatty', 'flat');
    sets.add(fset, 623, book, 80);
    local lset = sets.new('Bandy', 'levels');
    sets.add(lset, 603, book, 80);
    sets.groupAdd(lset, 41);
    sets.groupPut(lset, 41, { [1] = 529 });
    local tset = sets.new('Chained');
    sets.addEntry(tset, 1, 603, nil, book);
    rcfg.sets = { fset, lset, tset };
    local function rctx(editing, active, pick, editLevel)
        return { im = sIm, book = book, blu = blu, sets = sets, cfg = rcfg,
            save = function() end,
            state = { editingSet = editing, activeSet = active,
                editLevel = editLevel, pickKind = pick,
                nameBuf = { '' }, open = { true } },
            budgetMax = function() return 60; end };
    end

    sdrew = {};
    setsuiM.render(rctx(sets.clone(fset, fset.name), 1));   -- unguarded ON PURPOSE
    local screen = table.concat(sdrew, '\n');
    check(#sdrew > 5, ('the flat editor drew (%d strings)'):format(#sdrew));
    check(screen:find('Flat', 1, true) ~= nil, 'the flat kind is named by the name box');
    check(screen:find('Convert', 1, true) ~= nil,
        'a saved set offers Convert under its name');
    check(screen:find('Share', 1, true) ~= nil,
        'and Share beside it');
    check(screen:find('Import from text', 1, true) ~= nil,
        'the left column offers Import from text');

    sdrew = {};
    setsuiM.render(rctx(sets.draft(lset, 41), 2, nil, 41));
    screen = table.concat(sdrew, '\n');
    check(screen:find('Editing Lv.41', 1, true) ~= nil, 'the levels draft names its band');
    check(screen:find('Lvl Subsets', 1, true) ~= nil, 'and its kind');

    sdrew = {};
    setsuiM.render(rctx(sets.clone(tset, tset.name), 3));
    check(#sdrew > 5, 'the timeline editor still renders');

    sdrew = {};
    setsuiM.render(rctx(sets.new('N', 'flat'), nil, true));
    screen = table.concat(sdrew, '\n');
    check(screen:find('Slotlist', 1, true) ~= nil
        and screen:find('Lvl Subsets', 1, true) ~= nil,
        'the chooser offers all three kinds by name');

    sdrew = {};
    local shctx = rctx(sets.clone(fset, fset.name), 1);
    shctx.state.shareOpen = true;
    setsuiM.render(shctx);
    screen = table.concat(sdrew, '\n');
    check(screen:find('Share "Flatty"', 1, true) ~= nil
        and screen:find('sent whole', 1, true) ~= nil,
        'the share pane renders, guidance wrapped');

    sdrew = {};
    local imctx = rctx(sets.clone(fset, fset.name), 1);
    imctx.state.importOpen = true;
    setsuiM.render(imctx);
    screen = table.concat(sdrew, '\n');
    check(screen:find('Import from text', 1, true) ~= nil
        and screen:find('blusets', 1, true) ~= nil,
        'the import pane renders, the blusets pull tucked inside it');

    blu.currentSet, blu.effectiveLevel, blu.onBlu, blu.budget,
        blu.syncStats, blu.rungCap =
        _cur2, _eff2, _onb2, _bud2, _sync2, _rc2;
end

print('smoke: all green');
