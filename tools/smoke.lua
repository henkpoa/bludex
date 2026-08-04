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

print('smoke: filters');
check(#book.filter({ category = 'Healing' }) == 6, '6 castable healing spells');
check(#book.filter({ text = 'head' }) >= 1, 'text filter finds Head Butt');
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
