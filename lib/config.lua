--[[
    bludex/lib/config.lua -- the settings shape, shared by every host of the
    bludex library: the standalone addon (bludex.lua) and any embedding addon
    (e.g. dlac's BLU helper). One definition so the two can never drift.

    Headless-safe: uses Ashita's global T{} when present, plain tables when
    not (smoke test).
]]--

local M = {};

local function TT(t)
    if type(T) == 'function' or (type(T) == 'table' and getmetatable(T) and getmetatable(T).__call) then
        return T(t);
    end
    return t;
end

-- The full default tree. Call fresh per settings.load -- the settings lib
-- mutates what it is given.
function M.defaults()
    return TT{
        -- Saved sets, KIND-shaped (setsModelVer 3, docs/set-types-plan.md):
        --   { kind='flat',     name, ids={20} }
        --   { kind='levels',   name, ids, builds={{level,ids}..}, rule? }
        --   { kind='timeline', name, builtFor, chains, ids mirror, backups }
        -- host.adoptCfg stamps a missing kind by shape; nothing converts
        -- (a v1 entry stays flat).
        sets = TT{ },
        newSetKind = 'flat',      -- the type the New chooser offers first
                                  -- ('flat' | 'levels' | 'timeline')
        budgetOverride = 0,       -- shown when the live budget is unavailable
        applyDelay = 1.1,         -- seconds between set-spell packets
        applyMode = 'safe',       -- 'safe' (client-paced) | 'fast' (injected)
        replan = 'manual',        -- level change: 'auto' re-applies the plan
                                  -- for the new level (may UNSET); 'manual'
                                  -- nudges and waits for the click
        autoRestore = false,      -- RETIRED (pre-timeline adds-only restore);
                                  -- kept one release so old files read clean
        lastApplied = TT{ },      -- { ids = {20}, level = n } -- what the last
                                  -- apply sent, and the level it was FOR
        lastAppliedSet = '',      -- and its set BY NAME ('' = an unsaved
                                  -- draft): the FOLLOWED set -- the one
                                  -- whose kind and rule the level-change
                                  -- watcher obeys (docs/set-types-plan.md 5)
        activeSetName = '',       -- last selected saved set, reloaded at startup
        tooltipDelay = 0.5,       -- seconds the cursor must rest before a tooltip
        codexDensity = 'normal',  -- codex list size: 'big'|'medium'|'normal'|'compact'
        traitsDensity = 'normal', -- traits spell-row size, same four choices
        setsLayout = 'grid',      -- RETIRED (the grid is gone); kept one release
        -- Set model version: 3 = the three kinds (2 was timeline chains).
        -- Bumped when the stored meaning changes; adoptCfg migrates older
        -- shapes in place.
        setsModelVer = 3,
        -- The point budget: cap = base(level) + learnedBonus + merits, with
        -- merits counting only at level 75. Bumped when the meaning changes,
        -- so readings taken under older rules are discarded, not reused.
        capModelVer = 3,
        capLearnedBonus = -1,     -- points from spells learned (Boruko); -1 = unknown
        capMeritPoints = -1,      -- Assimilation points; -1 = unknown
    };
end

return M;
