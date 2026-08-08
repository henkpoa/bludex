--[[
    bludex/lib/setmodel.lua -- the set being edited and everything computable
    from it: point/MP totals, aggregated stat bonuses, and the trait ladder
    evaluation (the same math as the server's blueutils CalculateTraits: sum
    trait weights per category across set spells, highest tier with
    points <= total is active).

    Pure logic; no AshitaCore, no imgui.

    THE TIMELINE MODEL (design settled 2026-08-08, docs/timeline-sets-plan.md):
    a set is no longer a flat spell list -- each of the 20 slots holds a
    CHAIN, a level-ordered stack of entries, and the entry with the highest
    activation level at or below the current level is what the slot wears:

        { name     = 'Leveling',
          builtFor = 75,          -- budget enforcement floor (75 = endgame set)
          chains   = { [1..20] = { { id = 603, from = 4 },      -- Wild Oats
                                   { id = 529, from = 18 },     -- Bludgeon
                                   { id = 0,   from = 45 } } }, -- empty marker
          ids      = {20},        -- DERIVED resolveAtLevel(75) mirror, kept so
                                  -- older readers still see a usable flat set
          backups  = { { ts, name, builtFor, chains }, ... } }  -- cap 5

    resolveAtLevel collapses a set to the flat 20-id array the whole engine
    below this line already speaks (usedPoints/stats/traitEval/sortedLayout/
    applyDiff) -- nothing under the resolution line ever learns chains exist.
    A flat set is the degenerate case: one entry per chain, activating at the
    spell's own level -- exactly how the client treats a flat set today, so
    migration is lossless.

    Slot INDEX carries the unlock bracket: slots 1-6 open at level 1, each
    later pair at 11/21/31/41/51/61/71 (bracketFloor agrees with slotsAtLevel
    at every level -- the smoke suite pins it). A chain is inert below its
    slot's floor whatever its entries say.
]]--

local M = {};

M.BACKUP_CAP = 5;       -- backups kept per saved set, newest first

-- ---------------------------------------------------------------------------
-- construction, cloning, migration
-- ---------------------------------------------------------------------------

local function emptyChains()
    local c = {};
    for i = 1, 20 do c[i] = {}; end
    return c;
end

local function copyChains(chains)
    local c = {};
    for i = 1, 20 do
        c[i] = {};
        for j, e in ipairs(chains and chains[i] or {}) do
            c[i][j] = { id = e.id, from = e.from };
        end
    end
    return c;
end

function M.new(name)
    local ids = {};
    for i = 1, 20 do ids[i] = 0; end
    return {
        name = name or 'New Set',
        builtFor = 75,
        chains = emptyChains(),
        ids = ids,
    };
end

function M.clone(set, name)
    local c = M.new(name or (set.name .. ' copy'));
    c.builtFor = set.builtFor or 75;
    c.chains = copyChains(set.chains);
    for i = 1, 20 do c.ids[i] = set.ids and set.ids[i] or 0; end
    if set.backups ~= nil then
        c.backups = {};
        for i, b in ipairs(set.backups) do
            c.backups[i] = { ts = b.ts, name = b.name,
                builtFor = b.builtFor or 75, chains = copyChains(b.chains) };
        end
    end
    -- a set that never went through upgrade() clones as-is; the clone is
    -- upgraded the same way the original would be
    if set.chains == nil then c.chains = nil; end
    return c;
end

-- Chains from a flat id list: spells sorted ascending by level (ties by id,
-- unknown levels last) into slots 1..n, one entry each, activating at the
-- spell's own level. This IS today's engine behavior for a flat set -- the
-- sorted apply layout decides which spells a low level keeps -- so the
-- migration is faithful, including the level-8 spell that lands in slot 7
-- and therefore activates at 11 (at level 8 only six slots exist).
function M.buildChains(ids, book)
    local list = {};
    for i = 1, 20 do
        local id = ids and ids[i] or 0;
        if id ~= 0 then list[#list + 1] = id; end
    end
    table.sort(list, function(a, b)
        local la = (book and book.spells[a] and book.spells[a].level) or 999;
        local lb = (book and book.spells[b] and book.spells[b].level) or 999;
        if la ~= lb then return la < lb; end
        return a < b;
    end);
    local chains = emptyChains();
    for i, id in ipairs(list) do
        if i > 20 then break; end
        local s = book and book.spells[id] or nil;
        chains[i] = { { id = id, from = (s and s.level) or 1 } };
    end
    return chains;
end

-- A v2 set straight from a flat id list (blusets import, Read current).
function M.fromIds(name, ids, book)
    local set = M.new(name);
    set.chains = M.buildChains(ids, book);
    M.syncLegacyIds(set, book);
    return set;
end

-- Upgrade a stored set in place to the chain model. Returns true when it
-- changed anything. Two shapes need it: a v1 set (no chains field), and a
-- hand-built/legacy-decoded set whose chains are all empty while ids are
-- not (the ids are then the truth and the chains the artifact).
function M.upgrade(set, book)
    local hasChains = set.chains ~= nil;
    local chainCount = 0;
    if hasChains then
        for i = 1, 20 do
            if #(set.chains[i] or {}) > 0 then chainCount = chainCount + 1; end
        end
    end
    local idCount = 0;
    for i = 1, 20 do
        if (set.ids and set.ids[i] or 0) ~= 0 then idCount = idCount + 1; end
    end
    if hasChains and (chainCount > 0 or idCount == 0) then
        -- already v2; just make sure the shape is complete
        local changed = false;
        if set.builtFor == nil then set.builtFor = 75; changed = true; end
        for i = 1, 20 do
            if set.chains[i] == nil then set.chains[i] = {}; changed = true; end
        end
        return changed;
    end
    set.chains = M.buildChains(set.ids or {}, book);
    set.builtFor = set.builtFor or 75;
    M.syncLegacyIds(set, book);
    return true;
end

-- ---------------------------------------------------------------------------
-- the bracket rule and resolution
-- ---------------------------------------------------------------------------

-- The level at which a slot exists at all: slots 1-6 from level 1, each
-- later pair at 11/21/31/41/51/61/71. Must agree with slotsAtLevel at every
-- level (the smoke suite sweeps the pair).
function M.bracketFloor(slot)
    if slot <= 6 then return 1; end
    return math.ceil((slot - 6) / 2) * 10 + 1;
end

-- The bracket groups for the editor: { { floor, slots = {..} }, ... }
function M.brackets()
    local out = { { floor = 1, slots = { 1, 2, 3, 4, 5, 6 } } };
    for p = 0, 6 do
        out[#out + 1] = { floor = p * 10 + 11, slots = { 7 + p * 2, 8 + p * 2 } };
    end
    return out;
end

-- Collapse the timeline to the flat 20-id array for a level: per chain, the
-- entry with the highest activation at or below the level wins (an empty
-- marker wins as 0); a chain below its slot's floor is inert. Everything
-- downstream (points, stats, traits, sortedLayout, applyDiff) takes this.
function M.resolveAtLevel(set, level, book)
    level = level or 75;
    local chains = set.chains;
    if chains == nil then
        -- a set that never went through upgrade(): resolve the flat ids the
        -- same way the migration would have laid them out
        chains = M.buildChains(set.ids or {}, book);
    end
    local out = {};
    for slot = 1, 20 do
        out[slot] = 0;
        if M.bracketFloor(slot) <= level then
            local pick = nil;
            for _, e in ipairs(chains[slot] or {}) do
                if e.from <= level then pick = e; else break; end
            end
            if pick ~= nil then out[slot] = pick.id or 0; end
        end
    end
    return out;
end

-- Keep the legacy flat mirror (set.ids) equal to the level-75 resolution,
-- so every reader that still speaks ids sees a usable flat set.
function M.syncLegacyIds(set, book)
    set.ids = M.resolveAtLevel(set, 75, book);
end

-- The active range of one chain entry: lo..hi inclusive, floored by the
-- slot's bracket, ended by the next entry (or 75). lo > hi = a DEAD entry
-- that is never active (prevented at edit time, tolerated at read time).
function M.entryRange(set, slot, idx)
    local chain = set.chains and set.chains[slot] or nil;
    local e = chain and chain[idx] or nil;
    if e == nil then return nil, nil; end
    local floor = M.bracketFloor(slot);
    local lo = math.max(e.from, floor);
    local hi = 75;
    local nxt = chain[idx + 1];
    if nxt ~= nil then hi = math.max(nxt.from, floor) - 1; end
    return lo, hi;
end

-- Every level range where this spell is active, across all chains:
-- { { slot, idx, lo, hi }, ... } -- dead entries excluded.
function M.activeRanges(set, id)
    local out = {};
    if set.chains == nil or id == 0 then return out; end
    for slot = 1, 20 do
        for idx, e in ipairs(set.chains[slot]) do
            if e.id == id then
                local lo, hi = M.entryRange(set, slot, idx);
                if lo ~= nil and lo <= hi then
                    out[#out + 1] = { slot = slot, idx = idx, lo = lo, hi = hi };
                end
            end
        end
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- chain editing -- every mutation validates, then keeps the ids mirror true
-- ---------------------------------------------------------------------------

-- Can this entry join the chain? id = 0 adds an EMPTY MARKER (the slot goes
-- deliberately vacant from that level). Returns ok, reason. from = nil
-- defaults a spell to its own level. THE TWO GUARDS the timeline needs:
--   * no spell may be active at two places at once -- the new entry's range
--     is checked against every other placement of the same spell;
--   * no edit may leave any entry DEAD (never active) -- the neighbor an
--     insert shadows is checked, not just the newcomer.
function M.canAddEntry(set, slot, id, from, book)
    if set.chains == nil then return false, 'set not upgraded'; end
    if slot < 1 or slot > 20 then return false, 'no such slot'; end
    local chain = set.chains[slot];
    local floor = M.bracketFloor(slot);
    if id ~= 0 then
        local s = book.spells[id];
        if s == nil then return false, 'unknown spell'; end
        if not s.castable then return false, 'not castable at 75'; end
        if s.unbridled then return false, 'Unbridled spells cannot be set'; end
        if not book.learned(id) then return false, 'not learned'; end
        if s.setPoints == nil then return false, 'set cost unknown'; end
        from = from or s.level or 1;
        if s.level ~= nil and from < s.level then
            return false, ('cannot activate before its level (%d)'):format(s.level);
        end
    else
        if from == nil then return false, 'an empty marker needs a level'; end
        if #chain == 0 then return false, 'the slot is already empty'; end
    end
    if from < 1 or from > 75 then return false, 'level must be 1-75'; end

    -- the sorted insert position; equal activation levels cannot coexist
    local pos = #chain + 1;
    for i, e in ipairs(chain) do
        if e.from == from then
            return false, ('another entry already activates at Lv.%d'):format(from);
        end
        if e.from > from then pos = i; break; end
    end
    if id == 0 then
        local prev = chain[pos - 1];
        if prev == nil then return false, 'the slot is already empty there'; end
        if prev.id == 0 then
            return false, ('already empty from Lv.%d'):format(prev.from);
        end
        local nxt = chain[pos];
        if nxt ~= nil and nxt.id == 0 then
            return false, ('already empty from Lv.%d on'):format(nxt.from);
        end
    end

    -- simulate the insert: nobody in the chain may end up dead
    local sim = {};
    for i = 1, pos - 1 do sim[i] = chain[i]; end
    sim[pos] = { id = id, from = from };
    for i = pos, #chain do sim[i + 1] = chain[i]; end
    local newLo, newHi = nil, nil;
    for i, e in ipairs(sim) do
        local lo = math.max(e.from, floor);
        local hi = 75;
        if sim[i + 1] ~= nil then hi = math.max(sim[i + 1].from, floor) - 1; end
        if i == pos then newLo, newHi = lo, hi; end
        if lo > hi then
            if i == pos then
                if from < floor then
                    return false, ('never active here (the slot unlocks at Lv.%d)'):format(floor);
                end
                return false, ('replaced at Lv.%d before it ever activates'):format(hi + 1);
            end
            local nm = 'the empty marker';
            if e.id ~= 0 then
                nm = (book.spells[e.id] and book.spells[e.id].name) or ('#' .. e.id);
            end
            return false, ('%s would never be active in this slot'):format(nm);
        end
    end

    -- the one-place-at-a-time rule: the new range against every OTHER
    -- placement of the same spell (ranges inside this chain are disjoint by
    -- construction -- only other slots can collide)
    if id ~= 0 then
        for _, r in ipairs(M.activeRanges(set, id)) do
            if r.slot ~= slot and newLo <= r.hi and r.lo <= newHi then
                return false, ('already active at Lv.%d-%d in another slot'):format(r.lo, r.hi);
            end
        end
    end
    return true;
end

-- Drop leading empty markers (a chain starts empty anyway) and collapse
-- consecutive ones (the second says nothing the first did not).
local function normalizeChain(chain)
    while chain[1] ~= nil and chain[1].id == 0 do table.remove(chain, 1); end
    local i = 2;
    while chain[i] ~= nil do
        if chain[i].id == 0 and chain[i - 1].id == 0 then
            table.remove(chain, i);
        else
            i = i + 1;
        end
    end
end

function M.addEntry(set, slot, id, from, book)
    local ok, reason = M.canAddEntry(set, slot, id, from, book);
    if not ok then return false, reason; end
    if id ~= 0 and from == nil then
        local s = book.spells[id];
        from = (s and s.level) or 1;
    end
    local chain = set.chains[slot];
    local pos = #chain + 1;
    for i, e in ipairs(chain) do
        if e.from > from then pos = i; break; end
    end
    table.insert(chain, pos, { id = id, from = from });
    normalizeChain(chain);
    M.syncLegacyIds(set, book);
    return true;
end

-- Remove one entry. THE EXTENSION GUARD: removing an entry stretches its
-- predecessor's range over the removed span, and if that predecessor is a
-- spell that also lives elsewhere, the stretch can make it active in two
-- places at once -- the edit is rejected with the collision named, never
-- silently absorbed (docs/timeline-sets-plan.md 2.4).
function M.removeEntry(set, slot, idx, book)
    local chain = set.chains and set.chains[slot] or nil;
    local e = chain and chain[idx] or nil;
    if e == nil then return false, 'no such entry'; end
    local floor = M.bracketFloor(slot);
    local prev = chain[idx - 1];
    if prev ~= nil and prev.id ~= 0 then
        local nxt = chain[idx + 1];
        local newHi = 75;
        if nxt ~= nil then newHi = math.max(nxt.from, floor) - 1; end
        local prevLo = math.max(prev.from, floor);
        if prevLo <= newHi then
            for _, r in ipairs(M.activeRanges(set, prev.id)) do
                if not (r.slot == slot and r.idx == idx - 1)
                    and prevLo <= r.hi and r.lo <= newHi then
                    local nm = (book and book.spells[prev.id] and book.spells[prev.id].name)
                        or ('#' .. tostring(prev.id));
                    return false, ('%s would then be active twice (already Lv.%d-%d elsewhere)'):format(nm, r.lo, r.hi);
                end
            end
        end
    end
    table.remove(chain, idx);
    normalizeChain(chain);
    M.syncLegacyIds(set, book);
    return true;
end

-- Clear one whole chain. Always safe: nothing extends when a chain simply
-- disappears, and no other slot's ranges move.
function M.clearChain(set, slot, book)
    if set.chains == nil or set.chains[slot] == nil then return; end
    set.chains[slot] = {};
    M.syncLegacyIds(set, book);
end

function M.clear(set)
    set.chains = emptyChains();
    for i = 1, 20 do set.ids[i] = 0; end
end

-- A flat set: at most one entry per chain, no empty markers, every entry at
-- its spell's own level -- the degenerate case the editor shows without
-- timeline chrome (most endgame sets stay this shape forever).
function M.isFlat(set, book)
    if set.chains == nil then return true; end
    for slot = 1, 20 do
        local chain = set.chains[slot];
        if #chain > 1 then return false; end
        local e = chain[1];
        if e ~= nil then
            if e.id == 0 then return false; end
            local s = book and book.spells[e.id] or nil;
            if s ~= nil and s.level ~= nil and e.from ~= s.level then return false; end
        end
    end
    return true;
end

-- Deep equality of what the player authored: name, builtFor, chains.
-- Backups and the derived ids mirror are bookkeeping, not authorship.
function M.equal(a, b)
    if tostring(a.name) ~= tostring(b.name) then return false; end
    if (a.builtFor or 75) ~= (b.builtFor or 75) then return false; end
    local ca = a.chains or {};
    local cb = b.chains or {};
    for slot = 1, 20 do
        local x, y = ca[slot] or {}, cb[slot] or {};
        if #x ~= #y then return false; end
        for i = 1, #x do
            if x[i].id ~= y[i].id or x[i].from ~= y[i].from then return false; end
        end
    end
    return true;
end

-- ---------------------------------------------------------------------------
-- backups -- pushed on every destructive replace (save-over, read-current),
-- newest first, capped. ts is injected so this stays clock-free and testable.
-- ---------------------------------------------------------------------------
function M.pushBackup(set, source, ts)
    set.backups = set.backups or {};
    table.insert(set.backups, 1, {
        ts = ts,
        name = source.name,
        builtFor = source.builtFor or 75,
        chains = copyChains(source.chains),
    });
    while #set.backups > M.BACKUP_CAP do table.remove(set.backups); end
end

-- Restore backup i IN PLACE, pushing the current state as a backup first --
-- so a restore is itself undoable. The set keeps its current NAME (names
-- are identity keys: activeSetName restores by them). Returns true.
function M.restoreBackup(set, i, book, ts)
    local b = set.backups and set.backups[i] or nil;
    if b == nil then return false; end
    M.pushBackup(set, set, ts);
    set.builtFor = b.builtFor or 75;
    set.chains = copyChains(b.chains);
    M.syncLegacyIds(set, book);
    return true;
end

-- ---------------------------------------------------------------------------
-- flat readers -- every one takes a v2 set (reads its ids mirror = the
-- level-75 resolution) OR a plain 20-id array (a resolveAtLevel result),
-- so level-aware callers pass the resolution for the level they preview
-- ---------------------------------------------------------------------------

local function flatIds(setOrIds)
    return setOrIds.ids or setOrIds;
end

function M.count(set)
    -- spells assigned anywhere in the set (all chains, empty markers not
    -- counted); a flat array counts its nonzero slots
    if set.chains ~= nil then
        local n = 0;
        for slot = 1, 20 do
            for _, e in ipairs(set.chains[slot]) do
                if e.id ~= 0 then n = n + 1; end
            end
        end
        return n;
    end
    local ids = flatIds(set);
    local n = 0;
    for i = 1, 20 do if (ids[i] or 0) ~= 0 then n = n + 1; end end
    return n;
end

-- Membership for the codex green tint: assigned ANYWHERE in the timeline,
-- active at the current level or not (the assignment is what the player
-- needs to see). Returns the slot index or nil.
function M.contains(set, id)
    if set.chains ~= nil then
        for slot = 1, 20 do
            for _, e in ipairs(set.chains[slot]) do
                if e.id == id then return slot; end
            end
        end
        return nil;
    end
    local ids = flatIds(set);
    for i = 1, 20 do if ids[i] == id then return i; end end
    return nil;
end

function M.freeSlot(set)
    if set.chains ~= nil then
        for slot = 1, 20 do
            if #set.chains[slot] == 0 then return slot; end
        end
        return nil;
    end
    local ids = flatIds(set);
    for i = 1, 20 do if (ids[i] or 0) == 0 then return i; end end
    return nil;
end

function M.usedPoints(setOrIds, book)
    local ids = flatIds(setOrIds);
    local n = 0;
    for i = 1, 20 do
        local s = book.spells[ids[i] or 0];
        if s and s.setPoints then n = n + s.setPoints; end
    end
    return n;
end

function M.usedMP(setOrIds, book)
    local ids = flatIds(setOrIds);
    local n = 0;
    for i = 1, 20 do
        local s = book.spells[ids[i] or 0];
        if s and s.mpCost then n = n + s.mpCost; end
    end
    return n;
end

-- Can this spell go into the set at all? The convenience add: a NEW chain in
-- the lowest free slot (floors ascend with the index, so the first free slot
-- is also the earliest-activating home it can have). Deliberate stacking
-- onto an existing chain is addEntry with an explicit slot. Returns ok,
-- reason -- reasons match canAddEntry plus the whole-set gates.
function M.canAdd(set, id, book, budgetMax)
    local s = book.spells[id];
    if s == nil then return false, 'unknown spell'; end
    if M.contains(set, id) then return false, 'already in set'; end
    local slot = M.freeSlot(set);
    if slot == nil then return false, 'no free slot'; end
    if budgetMax and budgetMax > 0 and s.setPoints ~= nil
        and M.usedPoints(set, book) + s.setPoints > budgetMax then
        return false, 'over the point budget';
    end
    return M.canAddEntry(set, slot, id, nil, book);
end

function M.add(set, id, book, budgetMax)
    local ok, reason = M.canAdd(set, id, book, budgetMax);
    if not ok then return false, reason; end
    return M.addEntry(set, M.freeSlot(set), id, nil, book);
end

-- Remove a spell wherever it is assigned (every entry of it, all chains).
-- The extension guard cannot trip: with every placement of the spell gone,
-- no stretch can collide with one. Legacy flat arrays keep the old zero-out.
function M.removeId(set, id)
    if set.chains ~= nil then
        for slot = 1, 20 do
            local chain = set.chains[slot];
            local i = 1;
            while chain[i] ~= nil do
                if chain[i].id == id then table.remove(chain, i);
                else i = i + 1; end
            end
            normalizeChain(chain);
        end
        -- mirror sync without book: drop the id from the flat mirror too
        for i = 1, 20 do if set.ids[i] == id then set.ids[i] = 0; end end
        return;
    end
    local i = M.contains(set, id);
    if i then set.ids[i] = 0; end
end

function M.removeSlot(set, i)
    if set.chains ~= nil then
        if i >= 1 and i <= 20 then set.chains[i] = {}; set.ids[i] = 0; end
        return;
    end
    if i >= 1 and i <= 20 then set.ids[i] = 0; end
end

-- The APPLY layout (field 2026-08-04: the game's own set list should read
-- in level order): the given LEARNED spells sorted ascending by spell level
-- (ties by id) into slots 1..n, zeros after. This is exactly what applyDiff
-- sends and what the Apply-dirty compare measures -- low spells sit in the
-- low slots a level-down spares. Takes a flat 20-id array (for a timeline
-- set: resolveAtLevel first).
function M.sortedLayout(ids, book)
    local pick = {};
    for i = 1, 20 do
        local id = ids[i] or 0;
        if id ~= 0 and book.spells[id] ~= nil and book.learned(id) then
            pick[#pick + 1] = id;
        end
    end
    table.sort(pick, function(a, b)
        local la = book.spells[a].level or 999;
        local lb = book.spells[b].level or 999;
        if la ~= lb then return la < lb; end
        return a < b;
    end);
    local T = {};
    for i = 1, 20 do T[i] = pick[i] or 0; end
    return T;
end

-- The server's set-slot count for a BLU level (blueutils GetTotalSlots):
-- 6 slots through level 10, +2 every 10 levels after, capped at 20.
function M.slotsAtLevel(level)
    if level == nil or level < 1 then return 0; end
    local n = math.floor((level - 1) / 10) * 2 + 6;
    if n < 6 then n = 6; end
    if n > 20 then n = 20; end
    return n;
end

-- The server's BASE set-point budget for a BLU level, verbatim from
-- blueutils.cpp GetTotalBlueMagicPoints:
--     clamp(((level - 1) / 10) * 5 + 10, 0, 55)
-- 10 through Lv10, +5 every ten levels: 10/15/20/25/30/35/40/45 at the
-- bracket tops, 45 at the level-75 cap.
--
-- This is the BASE ONLY. Everything above it is character-specific and
-- cannot be derived: Assimilation merits (server-side, level >= 75 ONLY --
-- merits do not apply under a sync) and, on CatsEyeXI, a custom bonus for
-- spells learned that applies at EVERY level. Those are measured live --
-- see blu.learnedBonus / blu.meritPts / blu.expectedCap.
function M.baseCapAtLevel(level)
    if level == nil or level < 1 then return 0; end
    local n = math.floor((level - 1) / 10) * 5 + 10;
    if n < 0 then n = 0; end
    if n > 55 then n = 55; end
    return n;
end

-- ---------------------------------------------------------------------------
-- the band sweep -- the whole-curve point validation (plan 2.6):
-- at every level where anything changes (bracket steps, entry activations,
-- builtFor, 75), the resolved set's points against the budget for that
-- level. Returns merged violation bands:
--     { { lo, hi, over, provisional, enforced }, ... }
-- budgetFn(level) -> cap or nil; nil falls back to the BASE rule and marks
-- the band PROVISIONAL -- the base is a LOWER bound of the true budget, so
-- a provisional band may not be a real violation and must never hard-block.
-- enforced = the band lies at/above the set's builtFor level (bands are
-- never merged across that boundary, so the flag is band-wide).
-- ---------------------------------------------------------------------------
function M.bandViolations(set, book, budgetFn)
    local bf = set.builtFor or 75;
    local bpset = { [1] = true, [75] = true };
    for _, t in ipairs({ 11, 21, 31, 41, 51, 61, 71 }) do bpset[t] = true; end
    if bf >= 1 and bf <= 75 then bpset[bf] = true; end
    if set.chains ~= nil then
        for slot = 1, 20 do
            local floor = M.bracketFloor(slot);
            for _, e in ipairs(set.chains[slot]) do
                local lo = math.max(e.from, floor);
                if lo >= 1 and lo <= 75 then bpset[lo] = true; end
            end
        end
    end
    local bps = {};
    for l in pairs(bpset) do bps[#bps + 1] = l; end
    table.sort(bps);

    local out = {};
    for i, L in ipairs(bps) do
        local hi = (bps[i + 1] ~= nil) and (bps[i + 1] - 1) or 75;
        if hi >= L then
            local pts = M.usedPoints(M.resolveAtLevel(set, L, book), book);
            local cap = budgetFn and budgetFn(L) or nil;
            local provisional = false;
            if cap == nil then cap = M.baseCapAtLevel(L); provisional = true; end
            local over = pts - cap;
            if over > 0 then
                local last = out[#out];
                if last ~= nil and last.hi + 1 == L
                    and last.provisional == provisional
                    and (last.lo >= bf) == (L >= bf) then
                    last.hi = hi;
                    if over > last.over then last.over = over; end
                    if over < last.overMin then last.overMin = over; end
                else
                    out[#out + 1] = {
                        lo = L, hi = hi, over = over, overMin = over,
                        provisional = provisional, enforced = (L >= bf),
                    };
                end
            end
        end
    end
    return out;
end

-- The bands that BLOCK Apply: enforced (at/above builtFor) and not
-- provisional (the budget for the level is actually known).
function M.enforcedViolations(set, book, budgetFn)
    local out = {};
    for _, b in ipairs(M.bandViolations(set, book, budgetFn)) do
        if b.enforced and not b.provisional then out[#out + 1] = b; end
    end
    return out;
end

-- One violation band as the message the plan specifies verbatim. A merged
-- band's overage can vary inside it (the budget steps per bracket); when it
-- does, the message says 'up to' rather than overstating the whole range.
function M.bandText(b)
    local range = (b.lo == b.hi) and ('At level %d'):format(b.lo)
        or ('Between level %d and %d'):format(b.lo, b.hi);
    local amount = tostring(b.over);
    if b.overMin ~= nil and b.overMin ~= b.over then amount = 'up to ' .. amount; end
    local s = ('%s, you are %s point(s) above threshold'):format(range, amount);
    if b.provisional then s = s .. ' (assuming +0 learned bonus)'; end
    return s;
end

-- ---------------------------------------------------------------------------
-- display math (unchanged)
-- ---------------------------------------------------------------------------

-- 'DUAL_WIELD' -> 'Dual Wield', 'MND' stays 'MND' (<=4 chars = stat acronym)
function M.prettyStat(s)
    if #s <= 4 and not s:find('_') then return s; end
    return (s:lower():gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b)
        return a:upper() .. b;
    end));
end

-- Aggregate always-on stat bonuses from the set's spells:
-- returns sorted array of { stat = 'STR', value = 5 }.
-- Takes a set (its 75 mirror) or a flat resolveAtLevel array.
function M.stats(setOrIds, book)
    local ids = flatIds(setOrIds);
    local sum, order = {}, {};
    for i = 1, 20 do
        local s = book.spells[ids[i] or 0];
        if s and s.mods then
            for _, m in ipairs(s.mods) do
                if sum[m.stat] == nil then
                    sum[m.stat] = 0;
                    order[#order + 1] = m.stat;
                end
                sum[m.stat] = sum[m.stat] + m.value;
            end
        end
    end
    local out = {};
    for _, stat in ipairs(order) do
        if sum[stat] ~= 0 then out[#out + 1] = { stat = stat, value = sum[stat] }; end
    end
    return out;
end

-- Trait evaluation for the set. Returns sorted array of:
--   { cat, name, weight,           -- total weight the set feeds this category
--     tier,                        -- the active tier table or nil (below tier 1)
--     tierText,                    -- 'Dual Wield +10' style, or nil
--     nextPoints, nextText }       -- what the next tier needs, nil at cap
-- Takes a set (its 75 mirror) or a flat resolveAtLevel array.
function M.traitEval(setOrIds, book)
    local ids = flatIds(setOrIds);
    local weights, order = {}, {};
    for i = 1, 20 do
        local s = book.spells[ids[i] or 0];
        if s and s.trait then
            local c = s.trait.category;
            if weights[c] == nil then weights[c] = 0; order[#order + 1] = c; end
            weights[c] = weights[c] + (s.trait.weight or 0);
        end
    end
    local out = {};
    for _, cat in ipairs(order) do
        local info = book.traits.categories[cat];
        local total = weights[cat];
        local active, nextTier = nil, nil;
        if info then
            for _, tier in ipairs(info.tiers) do
                if total >= tier.points then
                    active = tier;
                elseif nextTier == nil then
                    nextTier = tier;
                end
            end
        end
        local function tierText(tier)
            if tier == nil then return nil; end
            local parts = {};
            for _, m in ipairs(tier.mods) do
                parts[#parts + 1] = ('%s %+d'):format(M.prettyStat(m.stat), m.value);
            end
            return table.concat(parts, ', ');
        end
        out[#out + 1] = {
            cat = cat,
            name = (info and info.name) or ('Trait ' .. cat),
            weight = total,
            tier = active,
            tierText = tierText(active),
            nextPoints = nextTier and nextTier.points or nil,
            nextText = tierText(nextTier),
        };
    end
    table.sort(out, function(a, b) return a.name < b.name; end);
    return out;
end

return M;
