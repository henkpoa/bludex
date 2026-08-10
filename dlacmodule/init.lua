--[[
    Bludex as a dlac Job helper module -- the api = 2 contract adapter.

    THIS FILE IS AUTHORED IN THE BLUDEX REPO (dlacmodule/init.lua) and lands
    in dlac at jobhelpers\blu\bludex\init.lua via the sync workflow, next to
    the vendored library (lib/ ui/ data/ icons/). Do not hand-edit the copy
    in dlac; see VENDORED.md there.

    The approval envelope (what this module DOES) is documented for review
    in README.md beside this file. In one breath: it renders the Blue Magic
    codex/set-planner Panel, reads the client's own BLU structs, and -- only
    on the player's explicit Apply, or the level-change rule carried by the
    set they last applied (Restore / Lvl Set Switch / Manual) -- sets/unsets
    Blue Magic spells through the client's own 0x102 path, one spell per
    packet, paced. Nothing acts until a set has been applied by hand at least
    once. It never equips gear and never opens an Action sequence.

    Contract notes, per the authoring guide:
    - Panels may not open windows: the library renders with embedded = true
      (the codex detail becomes an in-panel pane).
    - The framework store is scalars-only: saved sets and the last-applied
      snapshot are encoded as strings by the codec below.
    - The library UI is bludex's own kit over ctx.imgui (the host's handle;
      never a required copy). The kit carries the same field laws as
      panelkit -- printf-escape on every drawn string, presence-guards,
      measured widths -- it is dlac's craftbar lineage, blue-shifted.
    - All player-facing strings: PROPOSED, pending maintainer sign-off.
]]--

local ROOT = (...):sub(1, -#('init') - 1);   -- rename-safe, like S.sibling

-- ---------------------------------------------------------------------------
-- the vendored library, loaded lazily and contained
-- ---------------------------------------------------------------------------
local lib = nil;

local function loadLib()
    if lib ~= nil then return lib; end
    local ok, t = pcall(function()
        return {
            host = require(ROOT .. 'ui\\host'),
            book = require(ROOT .. 'lib\\spellbook'),
            blu  = require(ROOT .. 'lib\\blu'),
            sets = require(ROOT .. 'lib\\setmodel'),
        };
    end);
    if ok then lib = t; end
    return lib;
end

-- ---------------------------------------------------------------------------
-- scalar codec: the framework store holds strings/numbers/booleans only.
--
-- TWO GRAMMARS live side by side (docs/timeline-sets-plan.md 7):
--
--   'sets' (legacy)   'name<TAB>id,id,...' per line -- a FLAT list. Still
--                     WRITTEN on every save (from each set's level-75 ids
--                     mirror) so an older module reading this store sees a
--                     usable flat set instead of nothing: the old decoder
--                     turns any unknown token into 0, so changing this
--                     grammar in place would silently EMPTY every set.
--   'sets2' (v2)      the timeline. '#v2' header line, then per set:
--                         name<TAB>builtFor<TAB>chains
--                     chains = 20 ';'-joined chain tokens (empties kept);
--                     chain  = ','-joined entries; entry = id@from
--                     (id 0 = the deliberate empty marker).
--   'sets2bak'        backups, per line: name<TAB>ts<TAB>builtFor<TAB>chains
--                     (newest first, <= 5 per set name).
--   'lastApplied2'    'level<TAB>id,id,...' -- the level the apply was FOR.
--                     'lastApplied' (bare csv) stays dual-written.
--
-- Readers prefer v2 and fall back; every decode is tolerant -- a bad token
-- drops the entry, never the file.
-- ---------------------------------------------------------------------------
local codec = {};

function codec.encodeIds(ids)
    local parts = {};
    for i = 1, 20 do parts[i] = tostring(tonumber(ids and ids[i]) or 0); end
    return table.concat(parts, ',');
end

function codec.decodeIds(s)
    local ids, i = {}, 0;
    for tok in tostring(s or ''):gmatch('[^,]+') do
        i = i + 1;
        if i > 20 then break; end
        ids[i] = tonumber(tok) or 0;
    end
    for k = i + 1, 20 do ids[k] = 0; end
    return ids;
end

function codec.encodeSets(list)
    local recs = {};
    for _, e in ipairs(list or {}) do
        local name = tostring(e.name or '?'):gsub('[\t\n]', ' ');
        recs[#recs + 1] = name .. '\t' .. codec.encodeIds(e.ids);   -- flat
        if e.rule ~= nil then
            recs[#recs + 1] = ('%s\trule\t%s'):format(name, tostring(e.rule));
        end
        for _, t in ipairs(e.builds or {}) do
            recs[#recs + 1] = ('%s\t%d\t%s'):format(
                name, tonumber(t.level) or 71, codec.encodeIds(t.ids));
        end
    end
    return table.concat(recs, '\n');
end

function codec.decodeSets(s)
    local out, byName = {}, {};
    local function group(name)
        local g = byName[name];
        if g == nil then
            g = { name = name, ids = codec.decodeIds(''), builds = {} };
            byName[name] = g;
            out[#out + 1] = g;
        end
        return g;
    end
    for line in tostring(s or ''):gmatch('[^\n]+') do
        local f = {};
        for tok in (line .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = tok; end
        local name = f[1];
        if name ~= nil and name ~= '' then
            local g = group(name);
            if #f >= 3 and f[2] == 'rule' then
                g.rule = f[3];                          -- the set's level rule
            elseif #f >= 3 then
                local lvl = tonumber(f[2]) or 0;
                if lvl > 0 then
                    g.builds[#g.builds + 1] = { level = lvl, ids = codec.decodeIds(f[3]) };
                end
            elseif #f == 2 then
                g.ids = codec.decodeIds(f[2]);          -- the flat build
            end
        end
    end
    return out;
end

-- split preserving EMPTY tokens (gmatch('[^;]+') would swallow them, and an
-- empty chain token is meaningful: that slot has no entries)
local function splitKeep(s, sep)
    local out, pos = {}, 1;
    s = tostring(s or '');
    while true do
        local i = s:find(sep, pos, true);
        if i == nil then
            out[#out + 1] = s:sub(pos);
            return out;
        end
        out[#out + 1] = s:sub(pos, i - 1);
        pos = i + 1;
    end
end

function codec.encodeChains(chains)
    local slots = {};
    for i = 1, 20 do
        local parts = {};
        for _, e in ipairs(chains and chains[i] or {}) do
            parts[#parts + 1] = ('%d@%d'):format(tonumber(e.id) or 0, tonumber(e.from) or 1);
        end
        slots[i] = table.concat(parts, ',');
    end
    return table.concat(slots, ';');
end

function codec.decodeChains(s)
    local chains = {};
    local slots = splitKeep(s, ';');
    for i = 1, 20 do
        chains[i] = {};
        local tok = slots[i] or '';
        if tok ~= '' then
            for entry in tok:gmatch('[^,]+') do
                local id, from = entry:match('^(%-?%d+)@(%-?%d+)$');
                id, from = tonumber(id), tonumber(from);
                if id ~= nil and from ~= nil and from >= 1 and from <= 75 then
                    chains[i][#chains[i] + 1] = { id = id, from = from };
                end
            end
            -- restore the ascending-activation invariant every consumer
            -- assumes (resolveAtLevel breaks at the first later entry) --
            -- a hand-edited or corrupted line must not misresolve silently
            table.sort(chains[i], function(a, b) return a.from < b.from; end);
        end
    end
    return chains;
end

function codec.encodeSets2(list)
    local recs = { '#v2' };
    for _, e in ipairs(list or {}) do
        local name = tostring(e.name or '?'):gsub('[\t\n]', ' ');
        recs[#recs + 1] = name .. '\t' .. tostring(tonumber(e.builtFor) or 75)
            .. '\t' .. codec.encodeChains(e.chains);
    end
    return table.concat(recs, '\n');
end

function codec.decodeSets2(s)
    local out = {};
    for line in tostring(s or ''):gmatch('[^\n]+') do
        if line:sub(1, 1) ~= '#' then
            local name, bf, chains = line:match('^(.-)\t(%d+)\t(.*)$');
            if name ~= nil and name ~= '' then
                -- clamp builtFor into 1-75: a corrupt 0 would enforce every
                -- band and a corrupt 200 would enforce none -- tolerance
                -- means neither flip, not garbage-in-semantics-out
                local n = tonumber(bf) or 75;
                if n < 1 or n > 75 then n = 75; end
                out[#out + 1] = {
                    name = name,
                    builtFor = n,
                    chains = codec.decodeChains(chains),
                };
            end
        end
    end
    return out;
end

-- backups travel on their own key, attached to sets by NAME (names are the
-- identity keys everywhere else too -- activeSetName restores by them)
function codec.encodeBackups(list)
    local recs = {};
    for _, e in ipairs(list or {}) do
        local name = tostring(e.name or '?'):gsub('[\t\n]', ' ');
        for _, b in ipairs(e.backups or {}) do
            recs[#recs + 1] = name .. '\t' .. tostring(tonumber(b.ts) or 0)
                .. '\t' .. tostring(tonumber(b.builtFor) or 75)
                .. '\t' .. codec.encodeChains(b.chains);
        end
    end
    return table.concat(recs, '\n');
end

-- the ring depth mirrors setmodel.BACKUP_CAP; read it from the vendored
-- library when it is loaded (the headless codec tests run before that and
-- fall back to the same number)
local function backupCap()
    if lib ~= nil and lib.sets ~= nil and lib.sets.BACKUP_CAP ~= nil then
        return lib.sets.BACKUP_CAP;
    end
    return 5;
end

function codec.attachBackups(list, s)
    local byName = {};
    -- FIRST match wins on a duplicate name -- the same rule activeSetName
    -- resolution uses -- so a name collision cannot silently move every
    -- backup onto the later set
    for _, e in ipairs(list or {}) do
        local key = tostring(e.name);
        if byName[key] == nil then byName[key] = e; end
    end
    local cap = backupCap();
    for line in tostring(s or ''):gmatch('[^\n]+') do
        local name, ts, bf, chains = line:match('^(.-)\t(%d+)\t(%d+)\t(.*)$');
        local e = name ~= nil and byName[name] or nil;
        if e ~= nil then
            e.backups = e.backups or {};
            if #e.backups < cap then
                e.backups[#e.backups + 1] = {
                    ts = tonumber(ts) or 0,
                    name = name,
                    builtFor = tonumber(bf) or 75,
                    chains = codec.decodeChains(chains),
                };
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- the cfg bridge: the library mutates one live table and calls save();
-- save() re-encodes into the framework store (mutation-only underneath)
-- ---------------------------------------------------------------------------
local cfg, Sref = nil, nil;
local _panelAt = nil;   -- last frame the Panel rendered: the fresh-click detector

local function loadCfg(S)
    -- v2 first; a store that predates the timeline (empty sets2) falls back
    -- to the legacy flat key, and host.adoptCfg upgrades the entries after
    -- the swap. The first save then writes both grammars.
    local sets2raw = S.cfg.get('sets2');
    local setsList;
    if type(sets2raw) == 'string' and sets2raw ~= '' then
        setsList = codec.decodeSets2(sets2raw);
        codec.attachBackups(setsList, S.cfg.get('sets2bak'));
    else
        setsList = codec.decodeSets(S.cfg.get('sets'));
    end
    local lastApplied;
    local la2 = S.cfg.get('lastApplied2');
    if type(la2) == 'string' and la2 ~= '' then
        local lvl, csv = la2:match('^(%d*)\t(.*)$');
        lastApplied = { ids = codec.decodeIds(csv), level = tonumber(lvl) };
    else
        lastApplied = { ids = codec.decodeIds(S.cfg.get('lastApplied')) };
    end
    cfg = {
        sets           = setsList,
        lastApplied    = lastApplied,
        activeSetName  = S.cfg.get('activeSetName'),
        tooltipDelay   = S.cfg.get('tooltipDelay'),
        codexDensity   = S.cfg.get('codexDensity'),
        traitsDensity  = S.cfg.get('traitsDensity'),
        setsLayout     = S.cfg.get('setsLayout'),
        applyMode      = S.cfg.get('applyMode'),
        applyDelay     = S.cfg.get('applyDelay'),
        budgetOverride = S.cfg.get('budgetOverride'),
        replan         = S.cfg.get('replan'),
        autoRestore    = S.cfg.get('autoRestore'),
        setsModelVer    = S.cfg.get('setsModelVer'),
        capModelVer     = S.cfg.get('capModelVer'),
        capLearnedBonus = S.cfg.get('capLearnedBonus'),
        capMeritPoints  = S.cfg.get('capMeritPoints'),
    };
    local any = false;
    for i = 1, 20 do
        if cfg.lastApplied.ids[i] ~= 0 then any = true; break; end
    end
    if not any then cfg.lastApplied = {}; end   -- 'never applied yet'
    return cfg;
end

local function saveCfg()
    if cfg == nil or Sref == nil or Sref.cfg == nil then return; end
    pcall(function()
        -- both grammars, every save: sets2 is the truth, the legacy key is
        -- each set's flat level-75 mirror so an OLDER module reading this
        -- store still sees usable sets (its decoder zeroes unknown tokens)
        Sref.cfg.set('sets2', codec.encodeSets2(cfg.sets));
        Sref.cfg.set('sets2bak', codec.encodeBackups(cfg.sets));
        Sref.cfg.set('sets', codec.encodeSets(cfg.sets));
        local la = cfg.lastApplied;
        Sref.cfg.set('lastApplied2', (la and la.ids)
            and (tostring(tonumber(la.level) or '') .. '\t' .. codec.encodeIds(la.ids)) or '');
        Sref.cfg.set('lastApplied',
            (la and la.ids) and codec.encodeIds(la.ids) or '');
        Sref.cfg.set('activeSetName', tostring(cfg.activeSetName or ''));
        Sref.cfg.set('tooltipDelay', tonumber(cfg.tooltipDelay) or 0.5);
        Sref.cfg.set('codexDensity', tostring(cfg.codexDensity or 'normal'));
        Sref.cfg.set('traitsDensity', tostring(cfg.traitsDensity or 'normal'));
        Sref.cfg.set('setsLayout', tostring(cfg.setsLayout or 'grid'));
        Sref.cfg.set('applyMode', tostring(cfg.applyMode or 'safe'));
        Sref.cfg.set('applyDelay', tonumber(cfg.applyDelay) or 1.1);
        Sref.cfg.set('budgetOverride', tonumber(cfg.budgetOverride) or 0);
        Sref.cfg.set('replan', tostring(cfg.replan or 'manual'));
        Sref.cfg.set('autoRestore', cfg.autoRestore == true);
        Sref.cfg.set('setsModelVer', tonumber(cfg.setsModelVer) or 2);
        Sref.cfg.set('capModelVer', tonumber(cfg.capModelVer) or 3);
        Sref.cfg.set('capLearnedBonus', tonumber(cfg.capLearnedBonus) or -1);
        Sref.cfg.set('capMeritPoints', tonumber(cfg.capMeritPoints) or -1);
    end);
end

-- ---------------------------------------------------------------------------
-- the store watch: the bridge is a snapshot, the store is per-character
-- ---------------------------------------------------------------------------
--
-- dlac loads modules at addon load -- BEFORE login -- and its store serves
-- declared defaults until the character directory exists. So the snapshot
-- loadCfg takes at init holds an EMPTY set list, and without a re-read the
-- session's first save would write that emptiness over the character's real
-- file: the dlac flavor of the save-after-logoff bug. Watch the one fact
-- that names the store's identity -- the file it would write (S.cfg.path(),
-- per-character, nil pre-login) -- and re-decode the bridge the moment it
-- changes: the first login, and every character switch. The fresh table
-- goes through host.onSettingsSwap, which keeps or drops the working state
-- by character exactly as the standalone flavor does. Runs at every beat
-- and at the top of every render, so no save-capable surface can act on a
-- stale bridge first.
local _storeAt = nil;   -- the store path the bridge was decoded from

local function syncStore()
    if Sref == nil or Sref.cfg == nil or lib == nil or cfg == nil then return; end
    local p = nil;
    pcall(function() p = Sref.cfg.path(); end);
    if p == nil or p == _storeAt then return; end
    _storeAt = p;
    loadCfg(Sref);
    lib.blu.delay = tonumber(cfg.applyDelay) or 1.1;
    lib.blu.mode  = tostring(cfg.applyMode or 'safe');
    if type(lib.host.onSettingsSwap) == 'function' then
        lib.host.onSettingsSwap(cfg, p);
    elseif lib.host.deps ~= nil then
        lib.host.deps.cfg = cfg;    -- an older vendored host: rebind at least
    end
end

-- ---------------------------------------------------------------------------
-- the contract
-- ---------------------------------------------------------------------------
return {
    api   = 2,
    label = 'Bludex',                    -- PROPOSED
    jobs  = { 'BLU' },

    config = {
        keys = {
            -- sets2/sets2bak/lastApplied2 are the timeline grammar; sets and
            -- lastApplied stay dual-written so an older module still reads a
            -- usable flat list (see the codec block). setsLayout and
            -- autoRestore are retired, kept one release for tolerance.
            sets = 'string', sets2 = 'string', sets2bak = 'string',
            lastApplied = 'string', lastApplied2 = 'string',
            activeSetName = 'string',
            tooltipDelay = 'number',
            codexDensity = 'string', traitsDensity = 'string', setsLayout = 'string',
            applyMode = 'string', replan = 'string',
            applyDelay = 'number', budgetOverride = 'number',
            autoRestore = 'boolean',
            setsModelVer = 'number',
            -- the point-budget model (see ui/settingsui.lua). This flavor
            -- has no packet hook, so the 0x063 cross-check never arrives
            -- here -- both figures come from readings or the Settings tab.
            capModelVer = 'number',
            capLearnedBonus = 'number', capMeritPoints = 'number',
        },
        defaults = {
            sets = '', sets2 = '', sets2bak = '',
            lastApplied = '', lastApplied2 = '',
            activeSetName = '',
            tooltipDelay = 0.5,
            codexDensity = 'normal', traitsDensity = 'normal', setsLayout = 'grid',
            applyMode = 'safe', replan = 'manual',
            applyDelay = 1.1, budgetOverride = 0,
            autoRestore = false,
            setsModelVer = 2,
            capModelVer = 3, capLearnedBonus = -1, capMeritPoints = -1,
        },
    },

    init = function(S)
        Sref = S;
        local L = loadLib();
        if L == nil then
            pcall(S.say.err, 'the vendored library failed to load; the Panel will say so.');
            return;
        end
        loadCfg(S);
        -- a mid-session load (/addon reload dlac) already has the character
        -- directory: record it so the watch only fires on a real change
        pcall(function() _storeAt = S.cfg.path(); end);
        L.blu.delay = tonumber(cfg.applyDelay) or 1.1;
        L.blu.mode  = tostring(cfg.applyMode or 'safe');
        L.host.init({
            im = nil,                    -- the host handle arrives with panel ctx
            book = L.book, blu = L.blu, sets = L.sets,
            cfg = cfg, save = saveCfg,
        });
        pcall(function()
            if type(L.host.noteChar) == 'function' then L.host.noteChar(_storeAt); end
        end);
        -- the level-change watch + armed Restore ride the framework beat,
        -- Panel open or not, gated on the one activity predicate. A read we
        -- could not make is not permission: '~= true' stays inert. The store
        -- watch runs FIRST and ungated -- login detection cannot depend on
        -- the module being 'active'.
        pcall(function()
            S.combat.subscribe('tick', function()
                syncStore();
                if S.me.acting().active == true then
                    pcall(L.host.tick);
                end
            end);
        end);
    end,

    panel = function(ctx)
        local L = lib;
        if L == nil then
            if ctx.ui and ctx.ui.err then
                ctx.ui.err('bludex: the vendored library did not load (see /dl check).');
            end
            return;
        end
        syncStore();                     -- never render (or save) a stale bridge
        L.host.deps.im = ctx.imgui;      -- always the HOST's handle
        if L.host.deps.floatWindow == true then
            -- The float surface is live (this dlac has the window hook), so
            -- Bludex runs as its OWN window and this Panel is the launcher.
            -- A FRESH row click (no Panel render for a while) pops the
            -- window; while the Panel stays selected, a window the player
            -- closed stays closed.
            local now = os.clock();
            if _panelAt == nil or (now - _panelAt) > 1.0 then L.host.open(); end
            _panelAt = now;
            local ui = ctx.ui;
            if ui == nil then return; end
            ui.dim('Bludex runs in its own window -- it stays up even while this one is closed.');
            ui.space();
            if L.host.isOpen() then
                if ui.button('bdxwin_close', 'Close the Bludex window',
                             'Close it; the row keeps working.', 220, 26) then
                    L.host.toggle();
                end
            else
                if ui.button('bdxwin_open', 'Open the Bludex window',
                             'Codex, sets and traits, in a window of its own.', 220, 26) then
                    L.host.open();
                end
            end
        else
            -- an older dlac without the hook: the full body renders here
            L.host.renderEmbedded();
        end
    end,

    -- The WHOLE Bludex window through the framework's float surface (ADR 0028
    -- amendment 2026-08-04): drawn at dlac's one float draw site, so it
    -- survives the main window closing. Self-gates on its own open flag --
    -- the Panel above is the launcher. On an older dlac that ignores this
    -- hook, deps.floatWindow never sets and the Panel renders the embedded
    -- body instead.
    window = function(ctx)
        local L = lib;
        if L == nil then return; end
        syncStore();                     -- never render (or save) a stale bridge
        L.host.deps.im = ctx.imgui;
        L.host.renderWindowFloat();
    end,

    -- The quick menu's verb (guide 2.9): choosing Bludex in the Job helpers
    -- cascade pops the window (with the usual open-refresh of the BLU structs).
    open = function(S)
        local L = lib;
        if L == nil then return; end
        L.host.open();
    end,

    status = function(ctx)
        local L = lib;
        if L == nil then return; end
        local ok, max, spent = pcall(L.blu.points);
        if ok and max then
            ctx.ui.dim(('%d / %d pts set'):format(spent or 0, max));
        end
    end,

    -- not part of the loader contract; exposed for the headless smoke suite
    -- (_forceLib seeds the lazy lib cache: the repo layout lacks the vendored
    -- sibling dirs, so require-based loadLib cannot resolve there)
    _codec = codec,
    _syncStore = syncStore,
    _forceLib = function(t) lib = t; end,
};
