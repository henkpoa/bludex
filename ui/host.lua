--[[
    bludex/ui/host.lua -- the window shell: blue theme, header with the live
    point budget, the tab row (lit/unlit buttons -- BeginTabBar is not
    field-proven in this install), and per-frame ctx wiring for the tabs.

    Frame discipline: each tab renders inside pcall; a tab error draws as text
    instead of tearing the frame. Style pushes pop on every path.
]]--

local ROOT = (...):sub(1, -#('ui\\host') - 1);       -- relocatable require base
local kit      = require(ROOT .. 'ui\\kit');
local filetex  = require(ROOT .. 'ui\\filetex');
local tsrc     = require(ROOT .. 'lib\\traitsource');
local spellsui = require(ROOT .. 'ui\\spellsui');
local setsui   = require(ROOT .. 'ui\\setsui');
local traitsui = require(ROOT .. 'ui\\traitsui');
local settingsui = require(ROOT .. 'ui\\settingsui');

local M = {};

M.state = nil;

local function freshState(sets)
    return {
        open = { false, },
        tab = 'Codex',
        selectedId = nil,
        detailOpen = { false, },
        detailFocus = nil,
        learnOpen = { false, },
        learnFocus = nil,
        scOpen = { false, },
        scFocus = nil,
        scWeapon = { value = 'Sword' },
        editingSet = sets.new('Set 1'),
        activeSet = nil,
        activeLevel = nil,             -- the level build being edited (nil = flat)
        addNote = nil,
        applyNote = nil,
        nameBuf = { '' },
        addBuf = { '' },
        openCat = {},
        filters = {
            text = { '' },
            category = {}, element = {}, spellType = {}, trait = {}, learned = {},
            sort = {}, stat = {},
        },
    };
end

function M.init(deps)
    M.deps = deps;                      -- { im, book, blu, sets, cfg, save }
    M.state = freshState(deps.sets);
    -- restore the measured point-budget gap and keep it saved. Both flavors
    -- come through here, so the dlac module gets this for free. 0 means
    -- never measured: blu treats that as unknown, not as a real zero gap.
    -- measurements taken under an older model meant something else: drop
    -- them rather than compute confidently from them (2026-08-06: a sub-75
    -- gap learned from a stale reading produced 133 points against a true 79)
    if (deps.cfg.capModelVer or 0) < 3 then
        deps.cfg.capModelVer = 3;
        deps.cfg.capLearnedBonus, deps.cfg.capMeritPoints = -1, -1;
        if deps.save then deps.save(); end
    end
    local function known(v) if v ~= nil and v >= 0 then return v; end return nil; end
    deps.blu.learnedBonus = known(deps.cfg.capLearnedBonus);
    deps.blu.meritPts     = known(deps.cfg.capMeritPoints);
    deps.blu.onCapLearn = function()
        deps.cfg.capLearnedBonus = deps.blu.learnedBonus or -1;
        deps.cfg.capMeritPoints  = deps.blu.meritPts or -1;
        if deps.save then deps.save(); end
    end;
    -- every saved set gets tidied to the current shape here, once, before
    -- anything draws or computes. Nothing is converted: a set with no level
    -- builds is the flat set it always was and stays one.
    for _, entry in ipairs(deps.cfg.sets) do deps.sets.normalizeGroup(entry); end
    -- restore the last active saved set (matched by name -- indices shift when
    -- sets are deleted) AND which of its builds was being edited, exactly as
    -- if both had been clicked. 0 (or a level build since deleted) = the flat
    -- build, which every set has.
    local want = deps.cfg.activeSetName;
    if want ~= nil and want ~= '' then
        for i, entry in ipairs(deps.cfg.sets) do
            if entry.name == want then
                local saved = tonumber(deps.cfg.activeSetLevel) or 0;
                local lvl = (saved > 0) and deps.sets.rungFor(saved) or nil;
                if lvl ~= nil and deps.sets.groupBuild(entry, lvl) == nil then lvl = nil; end
                M.state.activeSet = i;
                M.state.activeLevel = lvl;
                M.state.editingSet = deps.sets.draft(entry, lvl);
                break;
            end
        end
    end
end

function M.toggle()
    if M.state then
        M.state.open[1] = not M.state.open[1];
        -- every open re-asks the server for job data (field-confirmed cure
        -- for the stale points/set structs)
        if M.state.open[1] and M.deps then M.deps.blu.refreshIfOnBlu(); end
    end
end

function M.isOpen()
    return M.state and M.state.open[1] or false;
end

-- THE BUDGET FOR ONE RUNG, and where the number came from. A build is planned
-- at ITS OWN rung, not at the level you happen to be standing at -- that is
-- what makes a Lv.41 build a Lv.41 plan. Our model answers for every rung once
-- this character's learned bonus is known, which is exactly what measuring it
-- was for; the client's own number only ever describes the level it was
-- computed at, so it is allowed to speak for that rung and no other.
--   'model' ours, right at every rung        'live' the client's / the override
--   'base'  the server's base rule alone: a floor, the bonus not measured yet
local function rungBudget(deps, level)
    local cap, src = deps.blu.rungCap(level);
    if src == 'model' then return cap, 'model'; end
    local here = deps.sets.rungFor(deps.blu.effectiveLevel());
    if level == nil or here == nil or level == here then
        local live = deps.blu.budget();
        if live then return live, 'live'; end
        local ov = deps.cfg.budgetOverride;
        if ov and ov > 0 then return ov, 'live'; end
    end
    return cap, src;                   -- 'base', or nil,nil with no rung at all
end

local function budgetMax(deps)
    local st = M.state;
    local lvl = (st and st.editingSet) and st.editingSet.level or nil;
    return (rungBudget(deps, lvl));
end

local TABS = { 'Codex', 'Sets', 'Traits', 'Settings' };

-- The job/level watch and auto-restore, run once per frame whether or not
-- anything renders: a level change invalidates the BLU structs like a fresh
-- login (refresh fires inside the watch). BY DIRECTION (Henrik 2026-08-06):
--   level UP / job change -- if the setting is on, spells the change
--     stripped from the last-applied set are re-added (two delayed checks
--     so the 0x061 answer has landed; quiet when nothing is missing);
--   level DOWN (sync down, delevel) -- NOTHING is sent: the client disables
--     over-level spells itself and re-enables them when the level returns,
--     and the level-sorted layout keeps the survivors in the low slots.
--     One delayed chat line reports what the sync disabled, nothing more.
-- SWITCH replaces both when it is the armed rule: see bandSwitch below.
-- The standalone render calls this itself; an EMBEDDING host (dlac's BLU
-- helper) calls it directly every frame, even while its panel is hidden.

-- THE SET BEING FOLLOWED: the one last APPLIED, by name. Never what happens
-- to be selected in the UI -- the rule is about what you are wearing.
local function followedSet(deps)
    local name = deps.cfg.lastAppliedSet;
    if name == nil or name == '' then return nil; end
    for _, e in ipairs(deps.cfg.sets) do
        if e.name == name then return deps.sets.normalizeGroup(e); end
    end
    return nil;
end

-- The rule THAT SET carries (Henrik 2026-08-07: the rule belongs to the set).
-- No set to follow means nothing runs, whatever any other set says.
local function activeRule(deps)
    local entry = followedSet(deps);
    if entry == nil then return 'manual', nil; end
    return deps.sets.ruleOf(entry), entry;
end

-- The band's OWN build, when it has one worth wearing. nil means this level
-- has no build of its own -- and then Lvl Set Switch behaves as Restore does,
-- on the set's normal build (Henrik's wording: "will equip normal set with
-- restore behaviour, unless a level appropriate set has been defined").
local function bandBuild(deps, entry)
    local rung = deps.sets.rungFor(deps.blu.effectiveLevel());
    if entry == nil or rung == nil then return nil; end
    local b = deps.sets.groupBuild(entry, rung);
    if b == nil or deps.sets.countIds(b.ids) == 0 then return nil; end
    return b;
end

-- THE BAND SWITCH (Henrik 2026-08-06, from the field: "I walked out now, and
-- I still have my level 31 set equipped"). A level build serves ITS band and
-- no other, so crossing into a band that HAS one means the set you are
-- wearing is the wrong build of itself: equip that band's build outright.
--
-- A band with no build of its own is not this rule's business -- the restore
-- path below covers it, adds-only, exactly as a flat set has always behaved.
--
-- Deliberately quiet when it has nothing to do: a band change that does not
-- move a spell must not cost the game's 60s Blue Magic cast lock, so the diff
-- is checked here rather than left to applyDiff's chat line.
local function bandSwitch(deps)
    if deps.blu.applying or not deps.blu.canApply() then return; end
    local rule, entry = activeRule(deps);
    if rule ~= 'switch' then return; end
    local build = bandBuild(deps, entry);
    if build == nil then return; end
    local ids = build.ids;
    local live = deps.blu.currentSet();
    if #live ~= 20 then return; end
    local T = deps.sets.sortedLayout(ids, deps.book);
    local same = true;
    for i = 1, 20 do
        if (live[i] or 0) ~= T[i] then same = false; break; end
    end
    if same then return; end
    deps.blu.say(('Level %s: equipping the Lv.%d set of "%s".'):format(
        tostring(deps.blu.effectiveLevel()), build.level, entry.name));
    if deps.blu.applyDiff(ids, deps.book) then
        local snap = {};
        for i = 1, 20 do snap[i] = ids[i] or 0; end
        deps.cfg.lastApplied = { ids = snap };
        if deps.save then deps.save(); end
    end
end

-- THE RESTORE PATH: put back what a level change stripped, adds-only, never
-- removing anything. Under Lvl Set Switch it works from the followed set --
-- its build for this band if there is one, otherwise its normal build --
-- rather than from the raw last-applied snapshot, which may be some other
-- band's build entirely.
local function restoreNow(deps)
    local rule, entry = activeRule(deps);
    if rule == 'manual' then return; end
    local ids = nil;
    if rule == 'switch' and entry ~= nil then
        ids = deps.sets.groupIds(entry, deps.sets.groupPick(entry, deps.blu.effectiveLevel()));
        if deps.sets.countIds(ids) == 0 then ids = nil; end
    end
    if ids == nil then
        local last = deps.cfg.lastApplied;
        ids = (last ~= nil) and last.ids or nil;
    end
    if ids ~= nil then deps.blu.restoreMissing(ids, deps.book); end
end

function M.tick()
    local deps = M.deps;
    if deps == nil then return; end
    -- PROOF OF LIFE for the level rules. Both of them ride the host's beat --
    -- dlac's is gated on its own activity predicate -- and a rule that never
    -- runs looks exactly like a rule that decided not to act. The Sets tab
    -- reads this and says which of the two it is.
    M.tickedAt = os.clock();
    -- the cap-staleness watch runs every frame whether or not anything
    -- renders: the client recomputes the cap on its own schedule (the native
    -- Set Spells menu), and we have to catch the moment it does
    deps.blu.watchCap();
    -- the BAND watch: cheap, every frame, and independent of watchJobState --
    -- what matters here is not that the level moved but that it crossed into
    -- a band with a different build. An unreadable level (nil: mid-handoff,
    -- off BLU) is not a change; it holds the last band until one reads again.
    local rung = deps.sets.rungFor(deps.blu.effectiveLevel());
    if rung ~= nil then
        if M.lastRung == nil then
            M.lastRung = rung;
        elseif rung ~= M.lastRung then
            M.lastRung = rung;
            -- one delayed check: the client's structs are mid-flight through a
            -- sync transition, and the live set cannot be read honestly yet.
            -- The rule is re-read when it fires, not latched here.
            M.switchCheck = os.clock() + 3.0;
        end
    end
    if M.switchCheck ~= nil and os.clock() >= M.switchCheck then
        M.switchCheck = nil;
        pcall(bandSwitch, deps);
    end
    local change = deps.blu.watchJobState();
    if change == 'down' then
        M.downCheck = os.clock() + 2.0;
        M.restoreChecks = nil;             -- a pending restore is moot now
    elseif change ~= nil then
        local now = os.clock();
        M.restoreChecks = { now + 2.0, now + 8.0 };
        M.downCheck = nil;
    end
    if M.downCheck ~= nil and os.clock() >= M.downCheck then
        M.downCheck = nil;
        -- when a band build is about to be equipped outright its own line says
        -- so, and the what-the-sync-disabled report would be noise on top
        local rule, entry = activeRule(deps);
        if not (rule == 'switch' and bandBuild(deps, entry) ~= nil) then
            deps.blu.reportLevelDown(deps.book);
        end
    end
    if M.restoreChecks ~= nil then
        local due = M.restoreChecks[1];
        if due ~= nil and os.clock() >= due then
            table.remove(M.restoreChecks, 1);
            if #M.restoreChecks == 0 then M.restoreChecks = nil; end
            pcall(restoreNow, deps);
        end
    end
end

-- body theme: what embedded rendering needs (child panels + the blue
-- Selectable/combo highlight -- the default theme's Header is RED); the
-- standalone window adds its own chrome on top. Both return the push count.
local function pushBodyTheme(im)
    if not (kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor')) then return 0; end
    im.PushStyleColor(3,  { 0.06, 0.09, 0.15, 0.97 });     -- ChildBg
    im.PushStyleColor(24, { 0.16, 0.34, 0.62, 0.85 });     -- Header
    im.PushStyleColor(25, { 0.20, 0.42, 0.74, 0.85 });     -- HeaderHovered
    im.PushStyleColor(26, { 0.24, 0.48, 0.80, 1.00 });     -- HeaderActive
    -- THE RED IS THE DEFAULT THEME'S, AND IT LEAKS (field 2026-08-07: every
    -- filter combo wore a red arrow). Anything the kit does not style itself
    -- falls back to the host's theme, so the widget colors are set here once:
    -- a combo's arrow is a BUTTON, its body is a FRAME, and both were still
    -- Ashita's default red/grey while everything around them was blue.
    --
    -- The contrast that carries it: the FRAME sits a shade DARKER than the
    -- panel it is on, the ARROW a good deal lighter -- so the box reads as
    -- inset and the one part you click reads as raised, without a border and
    -- without either of them competing with the blue-white text on top.
    im.PushStyleColor(7,  { 0.10, 0.13, 0.20, 1.00 });     -- FrameBg
    im.PushStyleColor(8,  { 0.13, 0.18, 0.28, 1.00 });     -- FrameBgHovered
    im.PushStyleColor(9,  { 0.16, 0.22, 0.34, 1.00 });     -- FrameBgActive
    im.PushStyleColor(21, { 0.16, 0.34, 0.62, 1.00 });     -- Button = combo arrow
    im.PushStyleColor(22, { 0.20, 0.42, 0.74, 1.00 });     -- ButtonHovered
    im.PushStyleColor(23, { 0.24, 0.48, 0.80, 1.00 });     -- ButtonActive
    im.PushStyleColor(4,  { 0.05, 0.08, 0.14, 0.98 });     -- PopupBg: the open list
    im.PushStyleColor(14, { 0.05, 0.07, 0.12, 0.60 });     -- ScrollbarBg
    im.PushStyleColor(15, { 0.16, 0.34, 0.62, 0.90 });     -- ScrollbarGrab
    im.PushStyleColor(16, { 0.20, 0.42, 0.74, 0.95 });     -- ScrollbarGrabHovered
    im.PushStyleColor(17, { 0.24, 0.48, 0.80, 1.00 });     -- ScrollbarGrabActive
    return 15;
end

local function pushWindowTheme(im)
    if not (kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor')) then return 0; end
    im.PushStyleColor(2,  { 0.055, 0.075, 0.125, 0.97 });  -- WindowBg
    im.PushStyleColor(11, { 0.10, 0.18, 0.34, 1.00 });     -- TitleBgActive
    im.PushStyleColor(10, { 0.07, 0.11, 0.20, 1.00 });     -- TitleBg
    return 3 + pushBodyTheme(im);
end

-- the per-frame ctx handed to every tab (and to the detail float)
local function tabCtx(im, st, deps, embedded)
    -- the tooltip dwell belongs to the kit (every tooltip in Bludex goes
    -- through it) but the setting lives in cfg -- carried across here, at the
    -- one point every rendering flavor passes through. NOT in tick(): an
    -- embedding host may gate its beat (dlac's rides an activity predicate),
    -- and a tooltip can be hovered whether or not the beat is running.
    kit.hoverDelay = tonumber(deps.cfg.tooltipDelay) or 0.5;
    -- THE JOB SIDE OF THE TRAIT COLLISION, resolved once per render: which
    -- traits your two jobs already grant, and therefore which blue tiers the
    -- server will throw away (lib/traitsource.lua). An unreadable character
    -- gives an empty map -- nothing is claimed when nothing can be read.
    local jp = deps.blu.jobPair and deps.blu.jobPair() or nil;
    local jobTraits = jp and tsrc.jobs(jp.mainJob, jp.mainLevel, jp.subJob, jp.subLevel) or {};
    -- THE REFEREE, ONLY WHEN IT IS AWAKE. The client's trait bits arrive on
    -- 0x0AC and are all zero until they do (a fresh zone, a job change still
    -- in flight) -- and an empty table reads exactly like "you have none of
    -- these". Hand the live reader over only once a trait we EXPECT is lit;
    -- until then nothing is contradicted, because nothing has been read.
    local hasTrait = nil;
    if deps.blu.hasTrait ~= nil then
        for traitId in pairs(jobTraits) do
            if deps.blu.hasTrait(traitId) == true then
                hasTrait = deps.blu.hasTrait;
                break;
            end
        end
    end
    return {
        im = im, book = deps.book, blu = deps.blu, sets = deps.sets,
        cfg = deps.cfg, save = deps.save, state = st,
        embedded = embedded == true,
        tsrc = tsrc, jobPair = jp, jobTraits = jobTraits,
        -- one ladder's whole answer: active tiers and where each came from
        verdict = function(cat, weight)
            return tsrc.verdict(cat, weight, deps.book, jobTraits, hasTrait);
        end,
        -- true once an embedding host's sanctioned float surface has run:
        -- the codex then routes Spell Info there instead of its in-panel pane
        floatWindow = deps.floatWindow == true,
        budgetMax = function() return budgetMax(deps); end,
        -- the same answer for ANY rung, so the saved-set tree and the editor
        -- meters can never disagree about what a level is worth
        rungBudget = function(level) return rungBudget(deps, level); end,
        slotMax = function() return deps.sets.slotMax(st.editingSet); end,
        -- is the beat that drives the level rules actually reaching us?
        watchAlive = function()
            return M.tickedAt ~= nil and (os.clock() - M.tickedAt) < 5.0;
        end,
        -- arming Switch is a click, and a click may act: put the player on
        -- the right build now rather than at the next band change. Silent
        -- when they are already wearing it (bandSwitch checks the diff).
        armSwitch = function() M.switchCheck = os.clock() + 0.5; end,
    };
end

-- Does the LIVE in-game set differ from the editing set's SORTED layout
-- (slot-wise -- what applyDiff would send)? So a right-spells-wrong-order
-- set lights Apply green, and one click re-sorts it. true / false, nil
-- when the live set is unreadable.
local function applyDirty(deps, st)
    local live = deps.blu.currentSet();
    if #live ~= 20 then return nil; end
    local T = deps.sets.sortedLayout(st.editingSet.ids, deps.book);
    for i = 1, 20 do
        if (live[i] or 0) ~= T[i] then return true; end
    end
    return false;
end

-- header + tab row + the active tab: everything between Begin and End,
-- shared verbatim by the standalone window and the embedded flavor.
-- `embedded` reaches the tabs through ctx: a dlac Job helper Panel may not
-- open windows itself, so the codex either uses the host's float surface
-- (renderDetailFloat below) or falls back to an in-panel pane.
local function renderBody(im, st, deps, embedded)
    -- header: logo + budget
    local logo = filetex.ui('logo-64');
    if logo ~= nil and kit.isFn(im, 'Image') then
        pcall(im.Image, logo, { 22, 22 });
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
    end
    kit.ctext(im, kit.COL.head, 'BLUDEX');
    -- ONE PAIR OF METERS, AND THEY DESCRIBE WHERE YOU ARE (Henrik 2026-08-07:
    -- "only relevant is your current situation"). There used to be two -- the
    -- editing build against its own band, plus a separate Sync line for what
    -- the game held right now -- and between them they filled the header with
    -- numbers for levels the player was not at.
    --
    -- These are the editing build against ITS band's allowance, which IS the
    -- current situation whenever you are editing the build for the band you
    -- stand in (the normal case: they are the same numbers). When they are
    -- NOT -- planning a Lv.31 build while standing at 75 -- the level chip
    -- says so rather than the meters quietly switching meaning.
    local elvl = st.editingSet.level;
    local here = deps.sets.rungFor(deps.blu.effectiveLevel());
    if elvl ~= nil then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        local away = (here ~= nil and here ~= elvl);
        kit.ctext(im, away and kit.COL.warn or kit.COL.accent,
            away and ('  Lv.%d (you are %d)'):format(elvl, deps.blu.effectiveLevel())
                or ('  Lv.%d'):format(elvl));
        kit.tip(im, ('You are editing the Lv.%d build of "%s", for levels %d-%d.\n'
            .. 'The points and slots beside this are what the game gives you\n'
            .. 'there.%s\n\n'
            .. 'Pick another level under the set name in the Sets tab.'):format(
            elvl, st.editingSet.name, elvl, deps.sets.bandTop(elvl),
            away and ('\n\nYou are at Lv.%s right now, which is a different band --\n'
                .. 'so these are plans for later, not your situation now.'):format(
                tostring(deps.blu.effectiveLevel())) or ''));
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local max = budgetMax(deps);
    kit.meter(im, '   Set:', deps.sets.usedPoints(st.editingSet, deps.book), max, ' pts');
    kit.tip(im, max ~= nil
        and 'Points this set uses / what the game gives you at its level\n(CatsEyeXI merit and learning bonuses included).'
        or 'Points this set uses.\nThe total appears when you are on BLU (or set budgetOverride).');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.meter(im, '   Slots:', deps.sets.count(st.editingSet), deps.sets.slotMax(st.editingSet), '');
    kit.tip(im, 'Spells in this set / the slots the game gives you at its level.');
    -- the cap the client holds can belong to a level we have left (the client
    -- only recomputes it when the native Set Spells menu opens). Say so
    -- rather than showing a confident wrong number -- and name the one action
    -- that actually fixes it, because nothing Bludex can send does.
    local differs, watched = deps.blu.capDisagrees();
    if differs and not watched then
        -- The client's number was never seen to recompute -- Bludex has only
        -- found it sitting there. Almost always the level sync's leftover.
        -- Tell the player the two clicks that refresh it for good.
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.warn, '   refresh points');
        kit.tip(im, ('The game client still reports %s points; Bludex works your\n'
            .. 'total out as %s and is showing that.\n\n'
            .. 'To refresh the game\'s own number, open:\n'
            .. '    Magic  ->  Blue Magic  ->  Set\n'
            .. 'That is the only thing that makes the client recalculate it.\n\n'
            .. 'Also zone once after loading Bludex: your merits arrive with the\n'
            .. 'zone, and Bludex needs them to work the total out.'):format(
            tostring(deps.blu.capValue()), tostring(deps.blu.expectedCap())));
    elseif differs then
        -- we WATCHED it recompute at this level and it still disagrees:
        -- our own parts are wrong, and the game is the authority
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.err, '   check Settings');
        kit.tip(im, ('The game client recalculated its total for your current\n'
            .. 'level and got %s, but Bludex works it out as %s.\n\n'
            .. 'The game is right, and it is the number being shown. One of the\n'
            .. 'parts on the Settings tab is wrong -- most likely the learned\n'
            .. 'bonus, if you have collected more from Boruko since.'):format(
            tostring(deps.blu.capValue()), tostring(deps.blu.expectedCap())));
    elseif deps.blu.capStale() then
        local _, src = deps.blu.budget();
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if src == 'model' then
            -- we have measured this character's gap, so the number above is
            -- ours and correct -- say where it came from, quietly
            kit.ctext(im, kit.COL.dim, '   (computed)');
            kit.tip(im, ('The game client has not recomputed its point total since\n'
                .. 'your level changed -- it still holds the Lv.%s figure. The\n'
                .. 'total above is Bludex\'s own, from the parts on the Settings\n'
                .. 'tab: the base rule for Lv.%s plus your learned bonus, plus\n'
                .. 'Assimilation merits when you are at 75.\n\n'
                .. 'Open the native Blue Magic set menu to see the game agree.'):format(
                tostring(deps.blu.capLevel()),
                tostring(deps.blu.effectiveLevel())));
        else
            kit.ctext(im, kit.COL.warn, '   cap stale');
            kit.tip(im, ('The point total above was computed by the game at Lv.%s\n'
                .. 'and it has not recomputed since your level changed.\n\n'
                .. 'Open the native Set Spells menu once: it corrects the number\n'
                .. 'AND teaches Bludex your point bonus, after which Bludex can\n'
                .. 'work it out for itself at every level. The cap never crosses\n'
                .. 'the network, so this one look is the only way to learn it.'):format(
                tostring(deps.blu.capLevel())));
        end
    end
    if deps.blu.onBlu() and (deps.blu.points()) == nil then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   (live points: reading...)');
        kit.tip(im, 'The client has not filled the points struct yet.\n'
            .. 'Bludex is requesting the data from the server (the same\n'
            .. '0x061 ask the native menus send). If it stays stuck:\n'
            .. '/bludex refresh re-asks, /bludex debug shows details.');
        deps.blu.nudgePoints();
    elseif not deps.blu.onBlu() then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   (not on BLU)');
    end

    -- set actions on the header line, every tab (Henrik 2026-08-04): Save
    -- and Apply light GREEN when they have work, Revert discards the unsaved
    -- changes. One definition each -- setsui owns the verbs.
    local ctx = tabCtx(im, st, deps, embedded);
    local unsaved = setsui.unsaved(ctx);
    local dirty = applyDirty(deps, st);
    local bw = kit.measure(im, { 'Save', 'Apply', 'Revert', 'Applying...' }, 48);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Save', false, bw, 22, unsaved and kit.PAL.go or kit.PAL.off) then
        if unsaved then setsui.saveEditing(ctx);
        else st.applyNote = 'Nothing to save.'; end
    end
    kit.tip(im, unsaved and 'Save the editing set - it has unsaved changes.'
        or 'The editing set matches its saved copy.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local applyPal = nil;
    if not deps.blu.applying then
        if dirty == true then applyPal = kit.PAL.go;
        elseif dirty == false then applyPal = kit.PAL.off; end
    end
    if kit.litButton(im, deps.blu.applying and 'Applying...' or 'Apply', false, bw, 22, applyPal) then
        if dirty == false then
            st.applyNote = 'Already up to date - nothing to apply.';
        else
            setsui.applyEditing(ctx);
        end
    end
    kit.tip(im, 'Apply the editing set in game - only the changed slots are sent.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Revert', false, bw, 22, unsaved and nil or kit.PAL.off) then
        if unsaved then setsui.revertEditing(ctx); end
    end
    kit.tip(im, unsaved and 'Discard the unsaved changes - back to the saved set.'
        or 'No unsaved changes to revert.');

    -- the cast lock countdown: changing set spells locks Blue Magic casting
    -- for about a minute (the game's rule) -- count it down where the eye is
    local lockRem = deps.blu.castReadyIn();
    if lockRem > 0 then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.warn, ('   castable in %ds'):format(lockRem));
        kit.tip(im, 'Changing set spells locks Blue Magic casting for about a\n'
            .. 'minute. The countdown runs from the last set change Bludex sent.');
    end

    -- tab row
    local w = kit.measure(im, TABS, 90);
    for _, t in ipairs(TABS) do
        if kit.litButton(im, t, st.tab == t, w, 26) then st.tab = t; end
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
    end
    if kit.isFn(im, 'NewLine') then im.NewLine(); end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    local tabfn = (st.tab == 'Sets' and setsui.render)
        or (st.tab == 'Traits' and traitsui.render)
        or (st.tab == 'Settings' and settingsui.render)
        or spellsui.render;
    local tok, terr = pcall(tabfn, ctx);
    if not tok then
        kit.ctext(im, kit.COL.err, 'tab error: ' .. tostring(terr));
    end
    -- The Spell Info window serves EVERY tab (codex and traits rows both
    -- open it), so it draws once here after the active tab -- except in the
    -- embedded-Panel fallback, where a Panel may not open windows (the
    -- codex's in-panel pane covers it there).
    if not ctx.embedded then
        local dok, derr = pcall(spellsui.detailWindow, ctx);
        if not dok then
            kit.ctext(im, kit.COL.err, 'detail error: ' .. tostring(derr));
        end
        -- the Learn-from and Skillchain-partners windows ride along the
        -- same way (their open buttons live inside Spell Info)
        pcall(spellsui.learnWindow, ctx);
        pcall(spellsui.scWindow, ctx);
    end
end

-- the floating Bludex window itself (Begin/End + chrome), shared by the
-- standalone render and the dlac float surface
local function renderWindow(im, st, deps)
    if not kit.isFn(im, 'Begin') or not kit.isFn(im, 'End') then return; end
    local pushed = pushWindowTheme(im);
    if kit.isFn(im, 'SetNextWindowSizeConstraints') then
        -- 920 wide fits the measured filter row; below that the Reset button clips
        pcall(im.SetNextWindowSizeConstraints, { 920, 520 }, { 4096, 4096 });
    end
    local visible = false;
    local ok = pcall(function()
        visible = im.Begin('Bludex##bdxmain', st.open);
    end);
    if ok and visible then
        renderBody(im, st, deps, false);
    end
    if ok then im.End(); end
    if pushed > 0 then im.PopStyleColor(pushed); end
end

-- the standalone flavor (the bludex addon's own d3d_present hook)
function M.render()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil then return; end
    M.tick();
    if not st.open[1] then return; end
    renderWindow(deps.im, st, deps);
end

-- Open the window outright (the toggle flips; a launcher wants OPEN).
-- Same open-refresh as toggle: field-confirmed cure for stale structs.
function M.open()
    if M.state == nil then return; end
    if not M.state.open[1] then
        M.state.open[1] = true;
        if M.deps then M.deps.blu.refreshIfOnBlu(); end
    end
end

-- The WHOLE Bludex window through an embedding host's float surface (dlac's
-- `window` hook): the full codex/sets/traits experience in its own window,
-- alive independent of the host's main box. Self-gates on st.open -- the
-- host's Panel is the launcher. Marks the float surface live even while
-- closed, so the Panel knows the launcher flavor applies (and the Spell
-- Info window rides along exactly as in standalone, embedded = false).
-- Ticking stays with the host's beat subscription, not here.
function M.renderWindowFloat()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil or deps.im == nil then return; end
    deps.floatWindow = true;
    if not st.open[1] then return; end
    renderWindow(deps.im, st, deps);
end

-- The Spell Info window ALONE, for an embedding host's sanctioned float
-- surface (dlac's `window` contract hook, ADR 0028 amendment 2026-08-04):
-- the codex list stays in the Panel; the detail window draws from the
-- host's float site, so it survives the host's main window closing. It
-- self-gates -- spellsui.detailWindow returns unless a spell was clicked
-- open. Marks the float surface live so the embedded codex stops offering
-- its in-panel fallback pane.
function M.renderDetailFloat()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil or deps.im == nil then return; end
    deps.floatWindow = true;
    local im = deps.im;
    local pushed = pushWindowTheme(im);      -- a float owns its window chrome
    local ctx = tabCtx(im, st, deps, true);
    pcall(spellsui.detailWindow, ctx);
    pcall(spellsui.learnWindow, ctx);
    pcall(spellsui.scWindow, ctx);
    if pushed > 0 then im.PopStyleColor(pushed); end
end

-- The embedded flavor for a hosting addon's own window (dlac's BLU helper):
-- no Begin/End, no window chrome -- the body draws into whatever window or
-- child is current. The host addon calls M.init once, M.tick() every frame
-- (visible or not), and this when its panel shows. See INTEGRATION.md.
function M.renderEmbedded()
    local st = M.state;
    if st == nil then return; end
    local deps = M.deps;
    if deps == nil then return; end
    local im = deps.im;
    local pushed = pushBodyTheme(im);
    local ok, err = pcall(renderBody, im, st, deps, true);
    if not ok then
        kit.ctext(im, kit.COL.err, 'bludex error: ' .. tostring(err));
    end
    if pushed > 0 then im.PopStyleColor(pushed); end
end

return M;
