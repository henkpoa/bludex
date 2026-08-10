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
        -- Saved sets, TIMELINE shape (setsModelVer 2, docs/timeline-sets-plan.md):
        -- { name, builtFor, chains = {20 x { {id, from}, ... }}, ids = {20},
        --   backups = {<=5} } -- ids is the derived level-75 mirror; a stored
        -- v1 entry ({ name, ids }) is upgraded in place by host.adoptCfg.
        sets = TT{ },
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
        activeSetName = '',       -- last selected saved set, reloaded at startup
        tooltipDelay = 0.5,       -- seconds the cursor must rest before a tooltip
        codexDensity = 'normal',  -- codex list size: 'big'|'medium'|'normal'|'compact'
        traitsDensity = 'normal', -- traits spell-row size, same four choices
        setsLayout = 'grid',      -- RETIRED (the grid is gone); kept one release
        -- Set model version: 2 = timeline chains. Bumped when the stored
        -- meaning changes; adoptCfg migrates older shapes in place.
        setsModelVer = 2,
        -- The point budget: cap = base(level) + learnedBonus + merits, with
        -- merits counting only at level 75. Bumped when the meaning changes,
        -- so readings taken under older rules are discarded, not reused.
        capModelVer = 3,
        capLearnedBonus = -1,     -- points from spells learned (Boruko); -1 = unknown
        capMeritPoints = -1,      -- Assimilation points; -1 = unknown
    };
end

return M;
