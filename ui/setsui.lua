--[[
    bludex/ui/setsui.lua -- the Sets tab: the saved-set tree, the 20-slot
    editor, the live budget meters, apply/read/clear against the game, and the
    computed stats + traits panel for the build being edited.

    A SAVED SET CAN HOLD A BUILD PER LEVEL (Henrik 2026-08-06). One set that
    works at 75 and at 40 cannot exist -- the points and the slots are
    different, so it is a different build, not a different name. The left
    column lists the sets; the name row is the set's FLAT build (no level
    attached -- what bludex has always had, and what a set stays until you
    build a level), and under the selected one sit all eight level bands with
    what each costs and what each allows. Clicking either edits that build
    like any other set. Nothing is migrated: a flat set is still flat.

    The budget meter prefers the LIVE client value (lib/blu points signature;
    CatsEyeXI's custom merit/learning bonuses included). Everything degrades:
    no signature -> settings override -> '?'.
]]--

local ROOT = (...):sub(1, -#('ui\\setsui') - 1);     -- relocatable require base
local kit      = require(ROOT .. 'ui\\kit');
local filetex  = require(ROOT .. 'ui\\filetex');
local spellsui = require(ROOT .. 'ui\\spellsui');
local blusetsimport = require(ROOT .. 'lib\\blusetsimport');

local M = {};

local LEFT_W  = 210;
local MID_W   = 330;

-- ---------------------------------------------------------------------------
-- the set actions -- ONE definition each, shared by the Sets tab buttons and
-- the window header's Save / Apply / Revert (host.renderBody)
-- ---------------------------------------------------------------------------

-- The level band being edited -- nil for the flat build, which is a real
-- answer here and not a missing one.
local function editLevel(ctx)
    return ctx.state.editingSet.level;
end

-- 41 -> '41-50', 71 -> '71-75'
local function bandText(ctx, level)
    return ('%d-%d'):format(level, ctx.sets.bandTop(level));
end

-- 'the Lv.41 build' / 'the set' -- for notes, which must never format a nil
-- level as a number.
local function buildText(level)
    return (level == nil) and 'the set' or ('the Lv.%d build'):format(level);
end

-- Load one build of one saved set into the editor (level nil = its flat
-- build). This is the ONE way the editing draft is replaced, so every path
-- remembers the same two things.
local function loadBuild(ctx, index, level)
    local st, cfg = ctx.state, ctx.cfg;
    local entry = cfg.sets[index];
    if entry == nil then return; end
    ctx.sets.normalizeGroup(entry);
    st.activeSet, st.activeLevel = index, level;
    st.editingSet = ctx.sets.draft(entry, level);
    st.applyNote = nil;
    st.addNote = nil;
    cfg.activeSetName = entry.name;                -- remembered across loads
    cfg.activeSetLevel = level or 0;               -- 0 = the flat build
    if ctx.save then ctx.save(); end
end
M.loadBuild = loadBuild;

-- Save the editing build into its set, at its own level (the active set, or a
-- new one). The name box names the WHOLE set -- every build under it moves.
function M.saveEditing(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    local level = editLevel(ctx);
    local entry = st.activeSet and cfg.sets[st.activeSet] or nil;
    if entry == nil then
        entry = ctx.sets.newGroup(st.editingSet.name);
        table.insert(cfg.sets, entry);
        st.activeSet = #cfg.sets;
    end
    entry.name = st.editingSet.name;
    ctx.sets.groupPut(entry, level, st.editingSet.ids);
    st.activeLevel = level;
    cfg.activeSetName = entry.name;                -- remembered across loads
    cfg.activeSetLevel = level or 0;
    if ctx.save then ctx.save(); end
    st.applyNote = (level == nil) and 'Saved.'
        or ('Saved %s, Lv.%d.'):format(entry.name, level);
end

-- Revert the editing build to its saved copy (or to a fresh empty one when
-- nothing is saved yet) -- removes ALL unsaved changes to THIS build.
function M.revertEditing(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    local saved = st.activeSet and cfg.sets[st.activeSet] or nil;
    if saved ~= nil then
        st.editingSet = ctx.sets.draft(saved, editLevel(ctx));
        st.applyNote = (editLevel(ctx) == nil) and 'Reverted to the saved set.'
            or ('Reverted to the saved Lv.%d build.'):format(editLevel(ctx));
    else
        st.editingSet = ctx.sets.new(('Set %d'):format(#cfg.sets + 1), editLevel(ctx));
        st.applyNote = 'Reverted - empty set.';
    end
    st.addNote = nil;
end

-- Apply the editing set in game (diff), snapshotting the auto-restore
-- target. Says WHY when it cannot.
function M.applyEditing(ctx)
    local st = ctx.state;
    if ctx.blu.applying then return; end
    if not ctx.blu.canApply() then
        st.applyNote = ctx.blu.onBlu()
            and 'Cannot apply: the client memory signatures did not resolve.'
            or 'Cannot apply: BLU is not your main or sub job.';
        return;
    end
    if ctx.blu.applyDiff(st.editingSet.ids, ctx.book) then
        local snap = {};
        for k = 1, 20 do snap[k] = st.editingSet.ids[k] or 0; end
        ctx.cfg.lastApplied = { ids = snap };
        if ctx.save then ctx.save(); end
        st.applyNote = ('Applying %s, lowest level first - watch the chat log.'):format(
            buildText(st.editingSet.level));
    end
end

-- Does the editing build differ from its SAVED copy? Drives the header's
-- green Save and the Revert. With no active saved set, any content counts.
function M.unsaved(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    local entry = st.activeSet and cfg.sets[st.activeSet] or nil;
    if entry == nil then
        return ctx.sets.count(st.editingSet) > 0;
    end
    if tostring(entry.name) ~= tostring(st.editingSet.name) then return true; end
    ctx.sets.normalizeGroup(entry);
    local saved = ctx.sets.groupIds(entry, editLevel(ctx));
    for i = 1, 20 do
        if saved[i] ~= (st.editingSet.ids[i] or 0) then return true; end
    end
    return false;
end

-- ---------------------------------------------------------------------------
-- the saved-set tree: the set (its flat build) and, under the selected one,
-- the eight level bands
-- (persisted as { name = s, ids = {20}, builds = { { level, ids }, ... } })
-- ---------------------------------------------------------------------------

-- Selectable in a color of our choosing (a row's color IS its state here:
-- dim = nothing built, accent = a build that fits, red = one that cannot).
local function tintedSelectable(im, col, label, selected)
    local pushed = false;
    if col ~= nil and kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
        im.PushStyleColor(0, col);                 -- Text
        pushed = true;
    end
    local ok, clicked = pcall(im.Selectable, kit.esc(label), selected == true);
    if pushed then im.PopStyleColor(1); end
    return ok and clicked or false;
end

-- One rung under a set: what it costs, what it is allowed, and what is in it.
local function rungRow(ctx, index, entry, level, here)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local ids   = ctx.sets.groupIds(entry, level);
    local used  = ctx.sets.pointsIds(ids, book);
    local n     = ctx.sets.countIds(ids);
    local slots = ctx.sets.slotsAtLevel(level);
    local cap, src = ctx.rungBudget(level);
    -- '79' the number we stand behind, '45+' the base rule with this
    -- character's bonus still unmeasured, '?' nothing known at all
    local capTxt = (cap ~= nil and cap > 0)
        and (tostring(cap) .. (src == 'base' and '+' or '')) or '?';
    local over = (n > slots) or (cap ~= nil and cap > 0 and src ~= 'base' and used > cap);
    local col = kit.COL.dim;
    if over then col = kit.COL.err; elseif n > 0 then col = kit.COL.accent; end

    local label = ('%s%2d   %2d / %-4s %2d / %2d##bdxrung%d_%d'):format(
        (here == level) and '>' or ' ', level, used, capTxt, n, slots, index, level);
    local selected = (st.activeSet == index and st.editingSet.level == level);
    if tintedSelectable(im, col, label, selected) then
        loadBuild(ctx, index, level);
    end

    -- the hover: the rung's own rules first, then what is actually in it
    local lines = {
        ('Lv.%s -- the build for levels %s'):format(level, bandText(ctx, level)),
        ('%d point%s, %d slot%s'):format(cap or 0, (cap == 1) and '' or 's',
            slots, (slots == 1) and '' or 's'),
    };
    if src == 'base' then
        lines[2] = ('%d points (the base rule -- your learned bonus is not\n'
            .. 'measured yet, so the real total is higher), %d slots'):format(cap or 0, slots);
    elseif cap == nil then
        lines[2] = ('point total unknown, %d slots'):format(slots);
    end
    if n == 0 then
        lines[#lines + 1] = '';
        lines[#lines + 1] = 'Nothing built here yet -- click to start.';
    else
        local from = ctx.sets.usableFrom(ids, book);
        if from ~= nil and from > level then
            lines[#lines + 1] = ('complete from Lv.%d (its highest spell)'):format(from);
        end
        if over then
            lines[#lines + 1] = 'OVER what this level allows -- remove something.';
        end
        lines[#lines + 1] = '';
        for i = 1, 20 do
            local s = book.spells[ids[i] or 0];
            if s ~= nil then
                lines[#lines + 1] = ('  %s  (%d pts)'):format(s.name, s.setPoints or 0);
            elseif (ids[i] or 0) ~= 0 then
                lines[#lines + 1] = ('  #%d'):format(ids[i]);
            end
        end
    end
    kit.tip(im, table.concat(lines, '\n'));
end

local function savedList(ctx)
    local im, st, cfg = ctx.im, ctx.state, ctx.cfg;
    kit.header(im, 'Saved sets');
    local here = ctx.sets.rungFor(ctx.blu.effectiveLevel());
    if kit.isFn(im, 'Selectable') then
        for i, entry in ipairs(cfg.sets) do
            ctx.sets.normalizeGroup(entry);
            local built = ctx.sets.groupLevels(entry);
            local flat  = ctx.sets.countIds(entry.ids);
            -- the name row IS the flat build. It counts spells, exactly as it
            -- always has; the level builds are counted beside it only when
            -- there are any, so a set nobody has levelled reads unchanged.
            local tag = ('%d'):format(flat);
            if #built > 0 then
                tag = (flat > 0) and ('%d, %d level%s'):format(flat, #built,
                    (#built == 1) and '' or 's')
                    or ('%d level%s'):format(#built, (#built == 1) and '' or 's');
            end
            local label = ('%s (%s)##bdxset%d'):format(entry.name, tag, i);
            local open = (st.activeSet == i);
            if tintedSelectable(im, kit.COL.head, label, open) then
                loadBuild(ctx, i, nil);        -- the name row: the flat build
                open = true;
            end
            kit.tip(im, ('%s -- the set with no level attached (%d spell%s).\n'
                .. 'Apply it at any level; the game keeps what fits.%s\n\n'
                .. 'Click to edit it%s.'):format(
                entry.name, flat, (flat == 1) and '' or 's',
                (#built > 0) and ('\nLevel builds: Lv.' .. table.concat(built, ', Lv.')) or '',
                open and '' or ', and to see its levels'));
            if open then
                kit.ctext(im, kit.COL.dim, '  Lv    points     slots');
                kit.tip(im, 'A build of its own for a level band. The game hands out\n'
                    .. 'different points and different slots at each of these, so a\n'
                    .. 'set that works at 75 cannot be the set that works at 41.\n\n'
                    .. 'Click a level to build or edit it; ">" is where you are now.\n'
                    .. 'Leave them all empty and the set stays exactly as it is.');
                for _, lvl in ipairs(ctx.sets.LEVELS) do
                    rungRow(ctx, i, entry, lvl, here);
                end
                if kit.isFn(im, 'Separator') then im.Separator(); end
            end
        end
    end
    if #cfg.sets == 0 then
        kit.ctext(im, kit.COL.dim, 'none yet');
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    local rowW = kit.measure(im, { 'New', 'Save', 'Delete' }, 50);
    if kit.litButton(im, 'New', false, rowW, 22) then
        st.editingSet = ctx.sets.new(('Set %d'):format(#cfg.sets + 1));
        st.activeSet, st.activeLevel = nil, nil;
        st.applyNote = 'New set - Save it, then pick a level under its name to build one for that level.';
    end
    kit.tip(im, 'Start a new set with no level attached.\nOnce it is saved, its level bands are one click away under the name.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Save', false, rowW, 22) then
        M.saveEditing(ctx);
    end
    kit.tip(im, 'Save what you are editing back into the set.\nEvery other build under that name is untouched.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Delete', false, rowW, 22) then
        if st.activeSet and cfg.sets[st.activeSet] then
            table.remove(cfg.sets, st.activeSet);
            st.activeSet, st.activeLevel = nil, nil;
            cfg.activeSetName = '';
            cfg.activeSetLevel = 0;
            if ctx.save then ctx.save(); end
            st.applyNote = 'Deleted.';
        end
    end
    kit.tip(im, 'Delete the whole set, every level build under it.\nTo drop ONE level build: Clear it, then Save.');

    -- one-way pull from the blusets addon's saved lists; existing bludex
    -- names are skipped, never overwritten -- safe to click repeatedly
    if kit.litButton(im, 'Import blusets', false, LEFT_W - 20, 20) then
        local res = blusetsimport.importAll(cfg, ctx.book);
        if #res.imported > 0 and ctx.save then ctx.save(); end
        st.applyNote = blusetsimport.describe(res);
    end
    kit.tip(im, 'Import every blusets spell list\n'
        .. '(config/addons/blusets/*.txt) as bludex saved sets.\n'
        .. 'A set name that already exists here is skipped.');

    -- name box
    kit.ctext(im, kit.COL.dim, 'Name');
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(LEFT_W - 20); end
    if kit.isFn(im, 'InputText') then
        st.nameBuf[1] = st.editingSet.name;
        if pcall(im.InputText, '##bdxsetname', st.nameBuf, 48) then
            st.editingSet.name = st.nameBuf[1];
        end
    end
end

-- ---------------------------------------------------------------------------
-- the slot grid + meters + game actions
-- ---------------------------------------------------------------------------

-- The LIST flavor of the slot area (Henrik 2026-08-04): the set's spells as
-- codex-grammar rows -- left-click Spell Info, right-click removes, the
-- live state as a label tag. Empty slots collapse into one dim count.
local function slotList(ctx, liveIds)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    local nameW = math.max(kit.availWidth(im, MID_W) - 24 - 40, 120);
    local lvl = ctx.blu.effectiveLevel();
    local shown = 0;
    for i = 1, 20 do
        local id = set.ids[i] or 0;
        if id ~= 0 then
            shown = shown + 1;
            local s = book.spells[id];
            local liveTag = '';
            if liveIds ~= nil and not liveIds[id] then
                -- a sync-disabled spell is not WAITING for an apply -- the
                -- game holds it and returns it when the sync ends
                if lvl ~= nil and lvl < 75 and s ~= nil
                    and s.level ~= nil and s.level > lvl then
                    liveTag = '  (disabled by level sync)';
                else
                    liveTag = '  (not active yet)';
                end
            end
            local label = ((s ~= nil) and s.name or ('#' .. id)) .. liveTag;
            local lclick, rclick, hov = spellsui.listRow(ctx, id, 24, nameW,
                st.selectedId == id, true, { label = label });
            if lclick then
                st.selectedId = id;
                st.detailOpen[1] = true;
                st.detailFocus = true;
            end
            if rclick then
                ctx.sets.removeSlot(set, i);
                st.applyNote = nil;
            end
            spellsui.tooltip(ctx, id, hov);
        end
    end
    if shown == 0 then
        kit.ctext(im, kit.COL.dim, 'The set is empty - add spells from the Codex or Traits.');
    else
        local free = ctx.sets.slotMax(set) - ctx.sets.count(set);
        if free > 0 then
            kit.ctext(im, kit.COL.dim, ('%d free slot%s'):format(free, free == 1 and '' or 's'));
        end
    end
end
local function slotGrid(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    st.detailOpen = st.detailOpen or { false };
    local slotMax = ctx.sets.slotMax(set);

    -- WHICH BUILD this is. The set name lives in the box on the left; this is
    -- the one thing about it that changes what the editor allows.
    if set.level ~= nil then
        kit.ctext(im, kit.COL.dim, ('Editing Lv.%s of "%s"  --  levels %s'):format(
            set.level, set.name, bandText(ctx, set.level)));
        kit.tip(im, ('The game gives the same %d slots and the same points\n'
            .. 'anywhere in Lv.%s, so one build serves the whole band.\n\n'
            .. 'Other levels of this set are under its name on the left.'):format(
            slotMax, bandText(ctx, set.level)));
    end

    -- the layout choice on the header line (Henrik 2026-08-04): the spatial
    -- 5x4 grid, or codex-grammar rows with names. Persisted.
    kit.ctext(im, kit.COL.head, 'Slots');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local layout = ctx.cfg.setsLayout or 'grid';
    local lw = kit.measure(im, { 'Grid', 'List' }, 40);
    if kit.litButton(im, 'Grid', layout == 'grid', lw, 18) and layout ~= 'grid' then
        ctx.cfg.setsLayout = 'grid'; layout = 'grid';
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'The 5x4 slot cells.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'List', layout == 'list', lw, 18) and layout ~= 'list' then
        ctx.cfg.setsLayout = 'list'; layout = 'list';
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'Named rows, like the Codex: left-click for Spell Info,\nright-click removes from the set.');
    if kit.isFn(im, 'Separator') then im.Separator(); end

    -- what the CLIENT has set right now, refreshed every frame: spells not
    -- yet live draw dimmed and light up one by one as an apply lands them.
    -- nil when the live set is unreadable (then nothing is dimmed).
    local liveIds = nil;
    local live = ctx.blu.currentSet();
    if #live == 20 then
        liveIds = {};
        for i = 1, 20 do if live[i] ~= 0 then liveIds[live[i]] = true; end end
    end

    if layout == 'list' then
        slotList(ctx, liveIds);
    else
    -- center the 5-cell rows in the column: equal space both sides
    -- (the grid body keeps its original indent; the else wraps it)
    local cell = 48;
    local gridW = (cell + 4) * 5 + 8 * 4;      -- cell+frame padding, 8px gaps
    local pad = math.max(0, math.floor((kit.availWidth(im, MID_W) - gridW) / 2));
    for i = 1, 20 do
        if ((i - 1) % 5) ~= 0 and kit.isFn(im, 'SameLine') then im.SameLine(); end
        if ((i - 1) % 5) == 0 and pad > 0
            and kit.isFn(im, 'GetCursorPosX') and kit.isFn(im, 'SetCursorPosX') then
            local okx, cx = pcall(im.GetCursorPosX);
            if okx and type(cx) == 'number' then pcall(im.SetCursorPosX, cx + pad); end
        end
        local id = set.ids[i] or 0;
        local locked = (i > slotMax);          -- this level does not have it
        if id ~= 0 then
            local inGame = liveIds == nil or liveIds[id] == true;
            if spellsui.spellButton(ctx, id, cell, false, locked or not inGame) then
                ctx.sets.removeSlot(set, i);
                st.applyNote = nil;
            end
            local liveLine = '';
            if liveIds ~= nil then
                local s2 = book.spells[id];
                local lvl2 = ctx.blu.effectiveLevel();
                if inGame then
                    liveLine = '\nactive in game';
                elseif lvl2 ~= nil and lvl2 < 75 and s2 ~= nil
                    and s2.level ~= nil and s2.level > lvl2 then
                    liveLine = '\ndisabled by level sync (returns when it ends)';
                else
                    liveLine = '\nnot active in game (Apply sends it)';
                end
            end
            if locked then
                liveLine = liveLine .. ('\nBEYOND Lv.%s: that level has only %d slots'):format(
                    set.level, slotMax);
            end
            local s = book.spells[id];
            if s ~= nil then
                kit.tip(im, ('%s\n%d pts%s%s\nclick to remove'):format(
                    s.name, s.setPoints or 0,
                    s.mpCost and ('  ' .. s.mpCost .. ' MP') or '', liveLine));
            else
                kit.tip(im, ('slot %d: spell id %d is not in the data%s\nclick to remove'):format(i, id, liveLine));
            end
        else
            local pushed = false;
            if kit.isFn(im, 'PushID') then pcall(im.PushID, 'bdxslot' .. i); pushed = true; end
            local h = filetex.ui('slot-empty-64');
            if h ~= nil and kit.isFn(im, 'ImageButton') then
                local styled = false;
                if kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
                    im.PushStyleColor(21, { 0, 0, 0, 0 });
                    im.PushStyleColor(22, { 0.20, 0.42, 0.74, 0.30 });
                    im.PushStyleColor(23, { 0.20, 0.42, 0.74, 0.50 });
                    im.PushStyleColor(5,  { 0, 0, 0, 0 });   -- Border: no square outline
                    styled = true;
                end
                -- same call shape as spellButton (frame padding 2) so image
                -- cells always land at cell+4 regardless of which art loads.
                -- A slot this level does not have yet is drawn faint -- the
                -- grid stays 5x4 so the shape of the set never jumps, but
                -- what you may actually fill is visible at a glance.
                local tint = locked and { 1, 1, 1, 0.20 } or { 1, 1, 1, 0.9 };
                local okB = pcall(im.ImageButton, h, { cell, cell }, { 0, 0 }, { 1, 1 }, 2,
                    { 0, 0, 0, 0 }, tint);
                if not okB then pcall(im.ImageButton, h, { cell, cell }); end
                if styled then im.PopStyleColor(4); end
            else
                -- +4: match the image cells' 2px frame padding per side.
                -- '##e' = a blank cell (the '-' read as content in the field)
                kit.litButton(im, '##e', false, cell + 4, cell + 4);
            end
            if pushed and kit.isFn(im, 'PopID') then pcall(im.PopID); end
            if locked then
                kit.tip(im, ('slot %d -- Lv.%s does not have it.\n'
                    .. 'The game gives %d slots there; slot %d opens at Lv.%d.'):format(
                    i, set.level, slotMax, i, ctx.sets.levelForSlot(i) or 71));
            else
                kit.tip(im, ('slot %d (empty)'):format(i));
            end
        end
    end
    end

    if kit.isFn(im, 'Separator') then im.Separator(); end
    local used = ctx.sets.usedPoints(st.editingSet, book);
    local max = ctx.budgetMax();
    kit.meter(im, 'Points', used, max, '');
    if max == nil then
        kit.tip(im, 'Live budget appears when you are on BLU.\nSet an override in settings otherwise.');
    elseif set.level ~= nil then
        local _, src = ctx.rungBudget(set.level);
        kit.tip(im, (src == 'base')
            and ('The base rule for Lv.%s. Your learned bonus is not measured\n'
                .. 'yet, so your real total there is higher -- open\n'
                .. 'Magic -> Blue Magic -> Set once and it settles.'):format(set.level)
            or ('What the game gives you at Lv.%s.'):format(set.level));
    end
    kit.meter(im, 'Slots ', ctx.sets.count(st.editingSet), slotMax, '');
    if set.level ~= nil and slotMax < 20 then
        kit.tip(im, ('Lv.%s has %d of the 20 slots; the rest open every ten levels.'):format(
            set.level, slotMax));
    end
    kit.ctext(im, kit.COL.dim, ('Total MP %d'):format(ctx.sets.usedMP(st.editingSet, book)));
    -- the level-sync line: the meters above are the PLAN; this is what the
    -- client holds right now while synced under the cap (see host header)
    local ss = ctx.blu.syncStats(book);
    if ss ~= nil and ss.level < 75 then
        local liveMax = ctx.blu.budget();      -- the synced level's budget
        kit.ctext(im, kit.COL.warn, ('Sync Lv.%d: %d / %s pts, %d / %d slots'):format(
            ss.level, ss.activePoints, liveMax and tostring(liveMax) or '?',
            ss.active, ss.maxSlots));
        kit.tip(im, 'What the level sync leaves live right now - the game\n'
            .. 'disabled the rest itself and restores it when the sync ends.');
    end

    -- game actions (widths measured -- 'Apply in gam' clipped in the field).
    -- The Apply button wears the diff state: green = the live set differs
    -- (click me), inert = already matching, plain = live state unknown.
    if kit.isFn(im, 'Separator') then im.Separator(); end
    local applyW = kit.measure(im, { 'Apply in game', 'Applying...' }, 100);
    local readW  = kit.measure(im, { 'Read current' }, 90);
    local clearW = kit.measure(im, { 'Clear' }, 50);
    local dirty = nil;                     -- nil = unknown (live unreadable)
    if liveIds ~= nil then
        -- slot-wise against the SORTED layout (what Apply would send): the
        -- right spells in the wrong order count as pending too
        dirty = false;
        local T = ctx.sets.sortedLayout(set.ids, ctx.book);
        for i = 1, 20 do
            if (live[i] or 0) ~= T[i] then dirty = true; break; end
        end
    end
    local pal = nil;
    if not ctx.blu.applying then
        if dirty == true then pal = kit.PAL.go;
        elseif dirty == false then pal = kit.PAL.off; end
    end
    if kit.litButton(im, ctx.blu.applying and 'Applying...' or 'Apply in game', false, applyW, 26, pal) then
        if dirty == false then
            st.applyNote = 'Already up to date - nothing to apply.';
        else
            M.applyEditing(ctx);
        end
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Read current', false, readW, 26) then
        local live = ctx.blu.currentSet();
        if #live == 20 then
            local unknown = 0;
            for i = 1, 20 do
                st.editingSet.ids[i] = live[i];
                if live[i] ~= 0 and book.spells[live[i]] == nil then unknown = unknown + 1; end
            end
            -- unknown ids are kept (honest mirror of the client) -- the grid
            -- draws them as '#id' cells and the totals simply skip them.
            st.applyNote = unknown == 0 and 'Read the live set.'
                or ('Read the live set; %d slot(s) hold ids the data does not know.'):format(unknown);
            -- the live set was built at YOUR level, not at this build's: say so
            -- rather than letting the meters go quietly red
            local nLive = ctx.sets.count(st.editingSet);
            if nLive > slotMax then
                st.applyNote = ('Read the live set - %d spells, but Lv.%s only has %d slots.'):format(
                    nLive, set.level, slotMax);
            end
        else
            st.applyNote = 'Could not read the live set.';
        end
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Clear', false, clearW, 26) then
        ctx.sets.clear(st.editingSet);
        st.applyNote = nil;
    end
    if not ctx.blu.onBlu() then
        kit.ctext(im, kit.COL.warn, 'BLU is not your main or sub job.');
    end
    if st.applyNote then kit.ctext(im, kit.COL.dim, st.applyNote); end

    -- level-change behavior: restore the last-applied set automatically, or
    -- leave everything to the Apply button
    -- the naming law: name the rule for its condition, never 'Auto <thing>'
    kit.ctext(im, kit.COL.dim, 'Level change:');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local lvW = kit.measure(im, { 'Restore', 'Manual' }, 64);
    local auto = ctx.cfg.autoRestore == true;
    if kit.litButton(im, 'Restore', auto, lvW, 20) and not auto then
        ctx.cfg.autoRestore = true;
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'After a level UP or job change, any spells stripped from the\n'
        .. 'LAST APPLIED set are re-set automatically - lowest level first,\n'
        .. 'into the lowest open slots. Adds only; never removes.\n'
        .. 'A level DOWN (sync, delevel) never sends anything: the game\n'
        .. 'disables over-level spells itself and brings them back after.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Manual', not auto, lvW, 20) and auto then
        ctx.cfg.autoRestore = false;
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'Nothing is applied automatically - you click Apply.');

    -- quick add
    if kit.isFn(im, 'Separator') then im.Separator(); end
    kit.ctext(im, kit.COL.head, 'Add a spell');
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(MID_W - 30); end
    if kit.isFn(im, 'InputText') then
        pcall(im.InputText, '##bdxaddsearch', st.addBuf, 48);
    end
    if st.addBuf[1] ~= '' then
        local ids = ctx.book.filter({ text = st.addBuf[1] });
        local max2 = ctx.budgetMax();
        for i = 1, math.min(#ids, 7) do
            local id = ids[i];
            local s = book.spells[id];
            local okAdd = ctx.sets.canAdd(st.editingSet, id, book, max2);
            local pushed = false;
            if kit.isFn(im, 'PushID') then pcall(im.PushID, 'bdxadd' .. id); pushed = true; end
            if kit.litButton(im, '+', false, 22, 20) and okAdd then
                ctx.sets.add(st.editingSet, id, book, max2);
            end
            if pushed and kit.isFn(im, 'PopID') then pcall(im.PopID); end
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            kit.ctext(im, okAdd and kit.COL.accent or kit.COL.dim,
                ('%s  (%s pts)'):format(s.name, s.setPoints or '?'));
        end
    end
end

-- ---------------------------------------------------------------------------
-- stats + traits for the editing set
-- ---------------------------------------------------------------------------
local function statsPanel(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    kit.header(im, 'Set stats');
    local stats = ctx.sets.stats(st.editingSet, book);
    if #stats == 0 then
        kit.ctext(im, kit.COL.dim, 'no stat bonuses yet');
    else
        for _, e in ipairs(stats) do
            kit.ctext(im, e.value >= 0 and kit.COL.ok or kit.COL.err,
                ('%s %+d'):format(ctx.sets.prettyStat(e.stat), e.value));
        end
    end

    if kit.isFn(im, 'Separator') then im.Separator(); end
    kit.header(im, 'Traits');
    local evals = ctx.sets.traitEval(st.editingSet, book);
    if #evals == 0 then
        kit.ctext(im, kit.COL.dim, 'no trait weight yet');
    end
    for _, ev in ipairs(evals) do
        if ev.tier then
            kit.ctext(im, kit.COL.ok, ('%s: %s'):format(ev.name, ev.tierText));
        else
            kit.ctext(im, kit.COL.dim, ('%s: below tier 1'):format(ev.name));
        end
        if ev.nextPoints then
            kit.ctext(im, kit.COL.dim, ('   %d more weight -> %s'):format(
                ev.nextPoints - ev.weight, ev.nextText or 'next tier'));
        end
    end
end

function M.render(ctx)
    local im = ctx.im;
    -- child widths follow their widest measured rows (the clipping law --
    -- 'Clea', 'Man' and 'Dele' all clipped in the field at the old fixed
    -- widths)
    local rowW = kit.measure(im, { 'New', 'Save', 'Delete' }, 50);
    -- the left column must also hold a rung row whole ('>71  77 / 79+ 19 / 20')
    -- -- measured, never guessed (the clipping law)
    local rungW = kit.measure(im, { '>71   77 / 79+  19 / 20  ' }, 0) + 24;
    LEFT_W = math.max(210, rowW * 3 + 32, rungW);
    local gameRow = kit.measure(im, { 'Apply in game', 'Applying...' }, 100)
        + kit.measure(im, { 'Read current' }, 90)
        + kit.measure(im, { 'Clear' }, 50);
    local levelRow = kit.measure(im, { 'Level change:' }, 60)
        + kit.measure(im, { 'Restore', 'Manual' }, 64) * 2;
    MID_W = math.max(330, gameRow + 34, levelRow + 34);
    if kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild') then
        if im.BeginChild('bdxsaved', { LEFT_W, 0 }, true) then savedList(ctx); end
        im.EndChild();
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if im.BeginChild('bdxslots', { MID_W, 0 }, true) then slotGrid(ctx); end
        im.EndChild();
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if im.BeginChild('bdxstats', { 0, 0 }, true) then statsPanel(ctx); end
        im.EndChild();
    else
        savedList(ctx); slotGrid(ctx); statsPanel(ctx);
    end
end

return M;
