--[[
    bludex/lib/setmodel.lua -- the set being edited and everything computable
    from it: point/MP totals, aggregated stat bonuses, and the trait ladder
    evaluation (the same math as the server's blueutils CalculateTraits: sum
    trait weights per category across set spells, highest tier with
    points <= total is active).

    Pure logic; no AshitaCore, no imgui.

    TWO SHAPES, and they are not the same thing:
      a BUILD (the thing being edited) is { name = s, level = 71, ids = {20} }
        with real spell ids (0 = empty slot). `level` is the level band it is
        for -- or NIL, which is the flat set bludex has always had: no level
        attached, all 20 slots, apply it wherever you are;
      a SAVED SET is { name = s, ids = {20}, builds = { {level, ids}, ... } } --
        its flat build, plus any level builds made under it, sorted by level.
    ("tier" in this file always means a TRAIT tier -- see traitEval.)
    NOTHING IS MIGRATED (Henrik 2026-08-06): a set with no level builds is
    exactly the flat set it was, and stays one until you build a level.
    Everything computable (points, slots, stats, traits) takes a BUILD.
]]--

local M = {};

-- ---------------------------------------------------------------------------
-- THE RUNGS. The server's two set rules -- how many slots and how many base
-- points -- both step every ten levels from 1, so one build serves a whole
-- band: a set made for Lv.41 is the same set at 50. Eight rungs, each named
-- for the level its band opens at. 71 is the last: 71-75 share a base, and
-- the Assimilation merits land inside that band, at 75.
-- ---------------------------------------------------------------------------
M.LEVELS = { 1, 11, 21, 31, 41, 51, 61, 71 };
M.TOP    = 71;

-- The rung a level belongs to: 40 -> 31, 75 -> 71, 1 -> 1. nil off BLU.
function M.rungFor(level)
    if level == nil or level < 1 then return nil; end
    local r = math.floor((level - 1) / 10) * 10 + 1;
    if r > M.TOP then r = M.TOP; end
    return r;
end

-- The top level a rung's band reaches: 41 -> 50, 71 -> 75 (the cap). A build
-- may hold any spell its band can cast, not only what the rung level can --
-- points and slots are flat across a band, spell levels are not.
function M.bandTop(level)
    if level == nil or level >= M.TOP then return 75; end
    return level + 9;
end

-- level nil = the flat build (no level attached), which is what a set is
-- until someone builds a level under it.
function M.new(name, level)
    local ids = {};
    for i = 1, 20 do ids[i] = 0; end
    return { name = name or 'New Set', level = level, ids = ids };
end

function M.clone(set, name)
    local c = M.new(name or (set.name .. ' copy'), set.level);
    for i = 1, 20 do c.ids[i] = set.ids[i] or 0; end
    return c;
end

-- Slots this build may fill: its band's server slot count. A level-less one is
-- the flat shape, and keeps all 20.
function M.slotMax(set)
    if set == nil or set.level == nil then return 20; end
    return M.slotsAtLevel(set.level);
end

function M.countIds(ids)
    local n = 0;
    for i = 1, 20 do if (ids[i] or 0) ~= 0 then n = n + 1; end end
    return n;
end

function M.count(set)
    return M.countIds(set.ids);
end

function M.contains(set, id)
    for i = 1, 20 do if set.ids[i] == id then return i; end end
    return nil;
end

function M.freeSlot(set)
    for i = 1, M.slotMax(set) do if (set.ids[i] or 0) == 0 then return i; end end
    return nil;
end

function M.pointsIds(ids, book)
    local n = 0;
    for i = 1, 20 do
        local s = book.spells[ids[i] or 0];
        if s and s.setPoints then n = n + s.setPoints; end
    end
    return n;
end

function M.usedPoints(set, book)
    return M.pointsIds(set.ids, book);
end

-- The level a build actually becomes usable at: the highest spell level in it.
-- nil when it holds nothing the data knows a level for.
function M.usableFrom(ids, book)
    local top = nil;
    for i = 1, 20 do
        local s = book.spells[ids[i] or 0];
        if s and s.level and (top == nil or s.level > top) then top = s.level; end
    end
    return top;
end

function M.usedMP(set, book)
    local n = 0;
    for i = 1, 20 do
        local s = book.spells[set.ids[i] or 0];
        if s and s.mpCost then n = n + s.mpCost; end
    end
    return n;
end

-- Can this spell go into the build? Returns ok, reason. The three ceilings a
-- level build adds over a flat set are its band's: the slot count, the budget
-- the caller passes for that rung, and the highest spell level its band can
-- cast (a Lv.41 plan reaches 50, so a Lv.62 spell has no business in it).
function M.canAdd(set, id, book, budgetMax)
    local s = book.spells[id];
    if s == nil then return false, 'unknown spell'; end
    if not s.castable then return false, 'not castable at 75'; end
    if s.unbridled then return false, 'Unbridled spells cannot be set'; end
    if not book.learned(id) then return false, 'not learned'; end
    if s.setPoints == nil then return false, 'set cost unknown'; end
    if M.contains(set, id) then return false, 'already in set'; end
    local top = M.bandTop(set.level);
    if s.level ~= nil and s.level > top then
        return false, ('needs Lv.%d - this set stops at %d'):format(s.level, top);
    end
    if M.freeSlot(set) == nil then
        local n = M.slotMax(set);
        if n < 20 then return false, ('no free slot (Lv.%d has %d)'):format(set.level, n); end
        return false, 'no free slot';
    end
    if budgetMax and budgetMax > 0
        and M.usedPoints(set, book) + s.setPoints > budgetMax then
        return false, 'over the point budget';
    end
    return true;
end

function M.add(set, id, book, budgetMax)
    local ok, reason = M.canAdd(set, id, book, budgetMax);
    if not ok then return false, reason; end
    set.ids[M.freeSlot(set)] = id;
    return true;
end

function M.removeSlot(set, i)
    if i >= 1 and i <= 20 then set.ids[i] = 0; end
end

function M.removeId(set, id)
    local i = M.contains(set, id);
    if i then set.ids[i] = 0; end
end

function M.clear(set)
    for i = 1, 20 do set.ids[i] = 0; end
end

-- The APPLY layout (field 2026-08-04: the game's own set list should read
-- in level order): the set's learned spells sorted ascending by spell level
-- (ties by id) into slots 1..n, zeros after. This is exactly what applyDiff
-- sends and what the Apply-dirty compare measures -- low spells sit in the
-- low slots a level-down spares.
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

-- The inverse of slotsAtLevel: the lowest level that HAS slot i. Slots 1-6
-- come with the job; every pair after that costs ten levels (7-8 at 11,
-- 19-20 at 71).
function M.levelForSlot(i)
    if i == nil or i <= 6 then return 1; end
    if i > 20 then return nil; end
    return math.ceil((i - 6) / 2) * 10 + 1;
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
-- A SAVED SET HOLDS ITS FLAT BUILD AND ANY LEVEL BUILDS UNDER IT
--
-- One saved name, one build per level band under it -- because a set that
-- works at 75 cannot work at 40: the points and the slots are different, so
-- the answer is a different build, not a different name.
--
-- `level = nil` addresses the FLAT build everywhere in here -- the set as
-- bludex has always had it, no level attached. A set with no level builds is
-- that and nothing else; a level build exists only while it holds spells, and
-- clearing one removes it again.
-- ---------------------------------------------------------------------------
function M.newGroup(name)
    local ids = {};
    for i = 1, 20 do ids[i] = 0; end
    return { name = name or 'New Set', ids = ids, builds = {} };
end

local function sortBuilds(entry)
    table.sort(entry.builds, function(a, b) return (a.level or 0) < (b.level or 0); end);
end

-- Bring a saved entry to the shape above WITHOUT converting anything: a set
-- saved before levels existed is a flat set, and stays exactly that. All this
-- does is give it an empty build list and tidy any builds it does have --
-- levels snapped to real rungs, duplicates dropped -- so a hand-edited
-- settings file cannot surprise anything downstream.
--
-- An EMPTY build is kept: bands are added on purpose (groupAdd) and one you
-- added but have not filled yet is a real thing, not a leftover.
-- Idempotent: the UI runs it over every entry it draws.
function M.normalizeGroup(entry)
    if type(entry) ~= 'table' then return entry; end
    local ids = {};
    for i = 1, 20 do ids[i] = tonumber(entry.ids and entry.ids[i]) or 0; end
    entry.ids = ids;
    local seen, keep = {}, {};
    for _, t in ipairs(entry.builds or {}) do
        local lvl = M.rungFor(tonumber(t.level) or 0);
        if lvl ~= nil and type(t.ids) == 'table' and not seen[lvl] then
            local tids = {};
            for i = 1, 20 do tids[i] = tonumber(t.ids[i]) or 0; end
            seen[lvl] = true;
            keep[#keep + 1] = { level = lvl, ids = tids };
        end
    end
    entry.builds = keep;
    sortBuilds(entry);
    return entry;
end

function M.groupBuild(entry, level)
    for _, t in ipairs((entry and entry.builds) or {}) do
        if t.level == level then return t; end
    end
    return nil;
end

-- A build's ids, always 20 long -- level nil is the flat build, and an
-- unbuilt rung answers all zeros rather than nil.
function M.groupIds(entry, level)
    local src = (level == nil) and entry or M.groupBuild(entry, level);
    local ids = {};
    for i = 1, 20 do ids[i] = (src and src.ids and src.ids[i]) or 0; end
    return ids;
end

-- Write a build back, empty or not: emptying a band is not the same as not
-- having one, and only groupRemove takes a band away.
function M.groupPut(entry, level, ids)
    local copy = {};
    for i = 1, 20 do copy[i] = ids[i] or 0; end
    if level == nil then entry.ids = copy; return; end
    entry.builds = entry.builds or {};
    for _, t in ipairs(entry.builds) do
        if t.level == level then t.ids = copy; return; end
    end
    entry.builds[#entry.builds + 1] = { level = level, ids = copy };
    sortBuilds(entry);
end

-- BANDS ARE ADDED ON PURPOSE (Henrik 2026-08-06). Offering all eight under
-- every set reads as eight things you are behind on; a set has the levels you
-- said it has, and none to begin with. Returns true when this added one.
function M.groupAdd(entry, level)
    -- nil is the flat build, which every set already has, and a level that is
    -- not a band start is not a band at all
    if level == nil or M.rungFor(level) ~= level then return false; end
    if M.groupBuild(entry, level) ~= nil then return false; end
    entry.builds = entry.builds or {};
    local ids = {};
    for i = 1, 20 do ids[i] = 0; end
    entry.builds[#entry.builds + 1] = { level = level, ids = ids };
    sortBuilds(entry);
    return true;
end

function M.groupRemove(entry, level)
    for i, t in ipairs((entry and entry.builds) or {}) do
        if t.level == level then table.remove(entry.builds, i); return true; end
    end
    return false;
end

-- The bands not yet added, ascending -- what the Add list offers.
function M.groupFree(entry)
    local out = {};
    for _, lvl in ipairs(M.LEVELS) do
        if M.groupBuild(entry, lvl) == nil then out[#out + 1] = lvl; end
    end
    return out;
end

-- The rungs that HAVE a build, ascending, empty ones included (the flat build
-- is not one of them).
function M.groupLevels(entry)
    local out = {};
    for _, t in ipairs((entry and entry.builds) or {}) do out[#out + 1] = t.level; end
    table.sort(out);
    return out;
end

-- The highest built rung, or nil when only the flat build exists.
function M.groupTop(entry)
    local lv = M.groupLevels(entry);
    return lv[#lv];
end

-- The build to use AT a level -- the one rule the whole feature turns on
-- (Henrik 2026-08-06):
--
--   the band's OWN build when there is one; otherwise THE FLAT BUILD.
--
-- The flat build is the set's backup, and it stays the answer everywhere no
-- band build has been made. It does NOT fill forward: a Lv.31 build is for
-- Lv.31-40 and nowhere else, so walking out of a sync goes back to the flat
-- set rather than dragging a level-31 build to 75. Copy it up a band if you
-- want it to keep serving (setsui's Copy).
--
-- Returns the rung, or nil for the flat build. The one exception is the set
-- with an EMPTY flat build: there is no backup to fall back on, so the
-- nearest build below answers rather than nothing at all.
-- A band that was added but never filled is NOT a build to pick: it means
-- "I will get to this", not "wear nothing here".
function M.groupPick(entry, level)
    local rung = M.rungFor(level);
    if rung == nil then return nil; end
    local own = M.groupBuild(entry, rung);
    if own ~= nil and M.countIds(own.ids) > 0 then return rung; end
    if M.countIds((entry and entry.ids) or {}) > 0 then return nil; end
    local best = nil;
    for _, t in ipairs((entry and entry.builds) or {}) do
        if M.countIds(t.ids) > 0 and t.level <= rung
            and (best == nil or t.level > best) then best = t.level; end
    end
    if best == nil then
        for _, t in ipairs((entry and entry.builds) or {}) do
            if M.countIds(t.ids) > 0 and (best == nil or t.level < best) then
                best = t.level;
            end
        end
    end
    return best;
end

-- Copy a build's spells into another band, keeping what that band can
-- actually hold: nothing above the level it can cast, lowest levels first,
-- until its slots run out.
--
-- The POINT budget is deliberately NOT enforced. Coming in over budget is the
-- workflow -- you see the red meter and cut what you can spare, which is a
-- judgement only the player can make; a copy that quietly dropped the spells
-- it happened to like least would take that away and look tidy doing it.
--
-- Returns ids{20}, report { taken, tooHigh, noSlot }.
function M.copyInto(ids, level, book)
    local slots = (level == nil) and 20 or M.slotsAtLevel(level);
    local top = M.bandTop(level);
    local pick, tooHigh = {}, 0;
    for i = 1, 20 do
        local id = ids[i] or 0;
        if id ~= 0 then
            local s = book.spells[id];
            if s ~= nil and s.level ~= nil and s.level > top then
                tooHigh = tooHigh + 1;
            else
                pick[#pick + 1] = id;
            end
        end
    end
    table.sort(pick, function(a, b)
        local sa, sb = book.spells[a], book.spells[b];
        local la = (sa and sa.level) or 999;
        local lb = (sb and sb.level) or 999;
        if la ~= lb then return la < lb; end
        return a < b;
    end);
    local out = {};
    for i = 1, 20 do out[i] = pick[i] or 0; end
    local taken = #pick;
    if taken > slots then
        for i = slots + 1, 20 do out[i] = 0; end
        taken = slots;
    end
    return out, { taken = taken, tooHigh = tooHigh, noSlot = #pick - taken };
end

-- One build of a set as an editable draft (the shape every computation and
-- the whole Sets tab takes).
function M.draft(entry, level)
    return { name = entry.name, level = level, ids = M.groupIds(entry, level) };
end

-- 'DUAL_WIELD' -> 'Dual Wield', 'MND' stays 'MND' (<=4 chars = stat acronym)
function M.prettyStat(s)
    if #s <= 4 and not s:find('_') then return s; end
    return (s:lower():gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b)
        return a:upper() .. b;
    end));
end

-- Aggregate always-on stat bonuses from the set's spells:
-- returns sorted array of { stat = 'STR', value = 5 }.
function M.stats(set, book)
    local sum, order = {}, {};
    for i = 1, 20 do
        local s = book.spells[set.ids[i] or 0];
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
function M.traitEval(set, book)
    local weights, order = {}, {};
    for i = 1, 20 do
        local s = book.spells[set.ids[i] or 0];
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
