--[[
    bludex/ui/setsui.lua -- the Sets tab, timeline flavor (2026-08-08,
    docs/timeline-sets-plan.md):

      left    saved sets (badges, backup rings, name, built-for floor)
      middle  the level slider (preview only) and the bracket-grouped chain
              list -- each slot's active spell at the preview level with the
              rest of its timeline beneath; then meters, the whole-curve
              band verdict, and the game actions (Apply / Apply for Lv.N /
              Read current / Clear, the level-change rule)
      right   Stats (at the preview level) | Assign (the picker for the
              selected slot -- ALL set mutation lives here now)

    The grid and the quick-add strip are gone; cfg.setsLayout is ignored.
    The budget meter prefers the LIVE client value at the live level and
    the measured model elsewhere. Everything degrades: no signature ->
    settings override -> '?'.
]]--

local ROOT = (...):sub(1, -#('ui\\setsui') - 1);     -- relocatable require base
local kit      = require(ROOT .. 'ui\\kit');
local spellsui = require(ROOT .. 'ui\\spellsui');
local blusetsimport = require(ROOT .. 'lib\\blusetsimport');

local M = {};

local LEFT_W  = 210;
local MID_W   = 330;

-- ---------------------------------------------------------------------------
-- the set actions -- ONE definition each, shared by the Sets tab buttons and
-- the window header's Save / Apply / Revert (host.renderBody)
-- ---------------------------------------------------------------------------

-- The budget for ANY level -- the band sweep's oracle. The model (base +
-- learned bonus, + merits only at 75) is the one source that can answer at
-- an arbitrary level; the client's live cap only ever describes the level
-- it was computed at. The level-75 settings override fills in when the
-- model has no learned bonus yet -- at 75 only, where its number means
-- what it says. nil = unknown (bandViolations then marks PROVISIONAL).
function M.budgetFn(ctx)
    return function(L)
        local c = ctx.blu.expectedCap(L);
        if c ~= nil then return c; end
        if L >= 75 and ctx.cfg.budgetOverride and ctx.cfg.budgetOverride > 0 then
            return ctx.cfg.budgetOverride;
        end
        return nil;
    end;
end

-- Save the editing set into the saved list (the active entry, or a new
-- one). Overwriting a DIFFERENT saved state banks it on the set's backup
-- ring first (cap 5, newest first) -- the save is undoable.
function M.saveEditing(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    local copy = ctx.sets.clone(st.editingSet, st.editingSet.name);
    copy.name = st.editingSet.name;
    if st.activeSet and cfg.sets[st.activeSet] then
        local old = cfg.sets[st.activeSet];
        if not ctx.sets.equal(old, copy) then
            ctx.sets.pushBackup(copy, old, os.time());
        end
        cfg.sets[st.activeSet] = copy;
    else
        table.insert(cfg.sets, copy);
        st.activeSet = #cfg.sets;
    end
    cfg.activeSetName = copy.name;                 -- remembered across loads
    if ctx.save then ctx.save(); end
    st.applyNote = 'Saved.';
end

-- Revert the editing set to its saved copy (or to a fresh empty set when
-- nothing is saved yet) -- removes ALL unsaved changes.
function M.revertEditing(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    local saved = st.activeSet and cfg.sets[st.activeSet] or nil;
    if saved ~= nil then
        st.editingSet = ctx.sets.clone(saved, saved.name);
        st.applyNote = 'Reverted to the saved set.';
    else
        st.editingSet = ctx.sets.new(('Set %d'):format(#cfg.sets + 1));
        st.applyNote = 'Reverted - empty set.';
    end
    st.addNote = nil;
end

-- Apply the editing set in game: the timeline RESOLVED for a level --
-- forLevel when given (the preemptive 'Apply for Lv.N'), else the live
-- effective level. Hard-blocked while an ENFORCED band violation exists
-- (at/above the set's builtFor, budget actually known -- plan 2.6); the
-- block message is the band message. Snapshots what was sent and the
-- level it was FOR, so the dirty compare can recognize a preemptive
-- apply instead of glowing green against it.
function M.applyEditing(ctx, forLevel)
    local st = ctx.state;
    if ctx.blu.applying then return; end
    if not ctx.blu.canApply() then
        st.applyNote = ctx.blu.onBlu()
            and 'Cannot apply: the client memory signatures did not resolve.'
            or 'Cannot apply: BLU is not your main or sub job.';
        return;
    end
    local viol = ctx.sets.enforcedViolations(st.editingSet, ctx.book, M.budgetFn(ctx));
    if #viol > 0 then
        st.applyNote = ('Cannot apply: %s.'):format(ctx.sets.bandText(viol[1]));
        return;
    end
    local lvl = forLevel or ctx.blu.effectiveLevel() or 75;
    local ids = ctx.sets.resolveAtLevel(st.editingSet, lvl, ctx.book);
    if ctx.blu.applyDiff(ids, ctx.book) then
        local snap = {};
        for k = 1, 20 do snap[k] = ids[k] or 0; end
        ctx.cfg.lastApplied = { ids = snap, level = lvl };
        st.replanPending = nil;
        if ctx.save then ctx.save(); end
        st.applyNote = forLevel
            and ('Applying the plan for Lv.%d - watch the chat log.'):format(lvl)
            or 'Applying the changes, lowest level first - watch the chat log.';
    end
end

-- Does the editing set differ from its SAVED copy? Drives the header's
-- green Save and the Revert. With no active saved set, any content counts.
-- Chains, builtFor and the name are authorship; backups are not.
function M.unsaved(ctx)
    local st, cfg = ctx.state, ctx.cfg;
    local saved = st.activeSet and cfg.sets[st.activeSet] or nil;
    if saved == nil then
        return ctx.sets.count(st.editingSet) > 0;
    end
    return not ctx.sets.equal(saved, st.editingSet);
end

-- The ONE live-vs-plan compare (formerly duplicated in host.renderBody and
-- the Sets tab, now consolidated -- plan 5). Against the SORTED layout of
-- the resolution, so right-spells-wrong-order still counts as pending.
-- Returns state, level:
--   'clean'   live matches the plan for the LIVE level
--   'planned' live matches the plan applied FOR another level (the
--             preemptive apply) -- level names it
--   'dirty'   live differs from both
--   nil       the live set is unreadable
function M.applyState(ctx)
    local live = ctx.blu.currentSet();
    if #live ~= 20 then return nil; end
    local st = ctx.state;
    local lvl = ctx.blu.effectiveLevel() or 75;
    local function matches(atLevel)
        local T = ctx.sets.sortedLayout(
            ctx.sets.resolveAtLevel(st.editingSet, atLevel, ctx.book), ctx.book);
        for i = 1, 20 do
            if (live[i] or 0) ~= T[i] then return false; end
        end
        return true;
    end
    if matches(lvl) then return 'clean', lvl; end
    local la = ctx.cfg.lastApplied;
    if la ~= nil and la.level ~= nil and la.level ~= lvl and matches(la.level) then
        return 'planned', la.level;
    end
    return 'dirty', lvl;
end


-- ---------------------------------------------------------------------------
-- shared helpers
-- ---------------------------------------------------------------------------

-- The PREVIEW level: the slider's explicit choice, else the live effective
-- level, else 75. The slider only previews -- the plain Apply never reads
-- it (plan 2.9); only the explicit 'Apply for Lv.N' button does.
local function previewLevel(ctx)
    local st = ctx.state;
    if st.preview ~= nil and st.preview.value ~= nil then return st.preview.value; end
    return ctx.blu.effectiveLevel() or 75;
end

local function bracketTop(floor)
    if floor == 1 then return 10; end
    return math.min(floor + 9, 75);
end

-- ---------------------------------------------------------------------------
-- saved sets (left column): select, badge, backups, name, built-for
-- ---------------------------------------------------------------------------
local function savedList(ctx)
    local im, st, cfg = ctx.im, ctx.state, ctx.cfg;
    kit.header(im, 'Saved sets');
    local budgetFn = M.budgetFn(ctx);
    if kit.isFn(im, 'Selectable') then
        for i, entry in ipairs(cfg.sets) do
            local label = ('%s (%d)##bdxset%d'):format(entry.name, ctx.sets.count(entry), i);
            local ok, clicked = pcall(im.Selectable, kit.esc(label), st.activeSet == i);
            local rclicked = false;
            if kit.isFn(im, 'IsItemClicked') then
                local okc, rc = pcall(im.IsItemClicked, 1);
                rclicked = okc and rc or false;
            end
            kit.tip(im, 'Left-click: edit this set.\nRight-click: its backups.');
            if ok and clicked then
                st.activeSet = i;
                st.editingSet = ctx.sets.clone(entry, entry.name);
                st.applyNote = nil;
                st.assignSlot = nil;
                cfg.activeSetName = entry.name;    -- remembered across loads
                if ctx.save then ctx.save(); end
            end
            if rclicked then
                st.backupsFor = (st.backupsFor == i) and nil or i;
            end
            -- the badge (plan 2.6): a saved set carrying an enforced band
            -- violation says so on its row; it saves fine, it cannot apply
            local viols = ctx.sets.enforcedViolations(entry, ctx.book, budgetFn);
            if #viols > 0 then
                if kit.isFn(im, 'SameLine') then im.SameLine(); end
                kit.ctext(im, kit.COL.err, '!');
                kit.tip(im, ctx.sets.bandText(viols[1])
                    .. '.\nApply is blocked for this set until it fits its built-for range.');
            end
            -- the backup ring, inline under the row (no popup: the embedded
            -- Panel may not open windows)
            if st.backupsFor == i then
                local backups = entry.backups or {};
                if #backups == 0 then
                    kit.ctext(im, kit.COL.dim, '   no backups yet');
                end
                for bi, b in ipairs(backups) do
                    local when = ('backup %d'):format(bi);
                    pcall(function()
                        local d = os.date('%m-%d %H:%M', b.ts);
                        if type(d) == 'string' then when = d; end
                    end);
                    local blabel = ('   restore %s##bdxbak%d_%d'):format(when, i, bi);
                    local okb, bclick = pcall(im.Selectable, kit.esc(blabel), false);
                    kit.tip(im, 'Restore this backup. The current saved state is banked\nfirst, so a restore is itself undoable.');
                    if okb and bclick then
                        ctx.sets.restoreBackup(entry, bi, ctx.book, os.time());
                        if st.activeSet == i then
                            st.editingSet = ctx.sets.clone(entry, entry.name);
                        end
                        if ctx.save then ctx.save(); end
                        st.applyNote = 'Backup restored (the replaced state is now backup 1).';
                        st.backupsFor = nil;
                        break;                     -- the ring just changed
                    end
                end
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
        st.activeSet = nil;
        st.assignSlot = nil;
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Save', false, rowW, 22) then
        M.saveEditing(ctx);
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Delete', false, rowW, 22) then
        if st.activeSet and cfg.sets[st.activeSet] then
            table.remove(cfg.sets, st.activeSet);
            st.activeSet = nil;
            st.backupsFor = nil;
            cfg.activeSetName = '';
            if ctx.save then ctx.save(); end
            st.applyNote = 'Deleted.';
        end
    end

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

    -- the built-for floor (plan 2.5): where budget ENFORCEMENT starts.
    -- 75 = an endgame set (nothing below is its problem); 1 = a leveling
    -- set that must fit everywhere.
    kit.helpLabel(im, 'Built for Lv.',
        'The level this set must actually FIT from. The point budget is\n'
        .. 'enforced from here up to 75: violations below only inform\n'
        .. '(grey bands), violations at or above BLOCK Apply (red).\n\n'
        .. '75 = an endgame set -- over-budget at lower levels is fine,\n'
        .. 'you never play it there. 1 = a leveling set that must fit at\n'
        .. 'every level. Anything between works too.', kit.COL.dim);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    st.builtForBuf = st.builtForBuf or { '' };
    st.builtForBuf[1] = tostring(st.editingSet.builtFor or 75);
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(40); end
    if kit.isFn(im, 'InputText') then
        if pcall(im.InputText, '##bdxbuiltfor', st.builtForBuf, 3) then
            local n = tonumber(st.builtForBuf[1]);
            if n ~= nil and n >= 1 and n <= 75 then
                n = math.floor(n);
                if n ~= st.editingSet.builtFor then st.editingSet.builtFor = n; end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- the middle column: the level slider and the bracket-grouped chain list
-- (the grid and the quick-add strip are GONE -- plan 2.15; cfg.setsLayout
-- is ignored). Slot numbers never show: the unlock bracket is the identity
-- that matters, and the engine re-sorts slots on every apply anyway.
-- ---------------------------------------------------------------------------

-- One slot's chain: the '+' assign target, the ACTIVE entry at the preview
-- level as a codex-grammar row (name + its level range + live tag), and
-- the rest of the timeline compact beneath -- retired dim, future blue.
local function chainRow(ctx, slot, shown, liveIds, locked, nameW)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    local chain = set.chains[slot];
    local floor = ctx.sets.bracketFloor(slot);
    local selected = st.assignSlot == slot;

    local pushed = false;
    if kit.isFn(im, 'PushID') then pcall(im.PushID, 'bdxchain' .. slot); pushed = true; end
    if kit.litButton(im, '+', selected, 22, 22) then
        if selected then
            st.assignSlot = nil;
        else
            st.assignSlot = slot;
            st.rightTab = 'Assign';
        end
    end
    kit.tip(im, selected
        and 'This slot is the Assign target (right pane). Click to deselect.'
        or 'Assign into this slot - the spell picker opens on the right.');
    if pushed and kit.isFn(im, 'PopID') then pcall(im.PopID); end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end

    if #chain == 0 then
        kit.ctext(im, kit.COL.dim, locked
            and ('(empty - opens at Lv.%d)'):format(floor) or '(empty)');
        return;
    end

    local activeIdx = nil;
    if not locked then
        for i, e in ipairs(chain) do
            if e.from <= shown then activeIdx = i; end
        end
    end

    if activeIdx == nil then
        local lo = ctx.sets.entryRange(set, slot, 1);
        kit.ctext(im, kit.COL.dim, ('(first at Lv.%d)'):format(lo or floor));
    else
        local e = chain[activeIdx];
        if e.id == 0 then
            kit.ctext(im, kit.COL.dim, ('(empty from Lv.%d)'):format(e.from));
        else
            local s = book.spells[e.id];
            local lo, hi = ctx.sets.entryRange(set, slot, activeIdx);
            local liveTag = '';
            if liveIds ~= nil and not liveIds[e.id] then
                -- a sync-disabled spell is not WAITING for an apply -- the
                -- game holds it and returns it when the sync ends
                local lvl = ctx.blu.effectiveLevel();
                if lvl ~= nil and lvl < 75 and s ~= nil
                    and s.level ~= nil and s.level > lvl then
                    liveTag = '  (disabled by level sync)';
                else
                    liveTag = '  (not active yet)';
                end
            end
            local label = ((s ~= nil) and s.name or ('#' .. e.id))
                .. ('  %d-%d'):format(lo or floor, hi or 75) .. liveTag;
            -- every row here is 'in the set', so the green tint says
            -- nothing -- head color instead, except unlearned stays loud
            local headCol = kit.COL.head;
            if ctx.blu.onBlu() and not book.learned(e.id) then headCol = kit.COL.err; end
            local lclick, rclick, hov = spellsui.listRow(ctx, e.id, 24, nameW,
                selected, true, { label = label, textCol = headCol });
            if lclick then
                st.selectedId = e.id;
                st.detailOpen[1] = true;
                st.detailFocus = true;
            end
            if rclick then
                local okR, whyR = ctx.sets.removeEntry(set, slot, activeIdx, book);
                st.applyNote = okR and nil or ('Cannot remove: %s.'):format(whyR);
                spellsui.tooltip(ctx, e.id, hov);
                return;                            -- the chain just changed
            end
            spellsui.tooltip(ctx, e.id, hov,
                { { 'right-click: remove this entry', kit.COL.dim } });
        end
    end

    -- the rest of the timeline, compact under the head
    for i, e in ipairs(chain) do
        if i ~= activeIdx then
            local lo, hi = ctx.sets.entryRange(set, slot, i);
            local nm = (e.id == 0) and 'empty'
                or ((book.spells[e.id] and book.spells[e.id].name) or ('#' .. e.id));
            local dead = (lo == nil or lo > hi);
            local future = (not dead) and lo > shown;
            local col = future and kit.COL.accent or kit.COL.dim;
            local text = dead and ('      (never)  %s'):format(nm)
                or ('      %d-%d  %s'):format(lo, hi, nm);
            if kit.isFn(im, 'Selectable') then
                local p2 = false;
                if kit.isFn(im, 'PushID') then
                    pcall(im.PushID, ('bdxsub%d_%d'):format(slot, i));
                    p2 = true;
                end
                local pcol = false;
                if kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
                    im.PushStyleColor(0, col);     -- Text
                    pcol = true;
                end
                local okS, sclick = pcall(im.Selectable, kit.esc(text), false);
                if pcol then im.PopStyleColor(1); end
                local rc = false;
                if kit.isFn(im, 'IsItemClicked') then
                    local okc, r = pcall(im.IsItemClicked, 1);
                    rc = okc and r or false;
                end
                if e.id ~= 0 then
                    spellsui.tooltip(ctx, e.id, nil,
                        { { 'right-click: remove this entry', kit.COL.dim } });
                else
                    kit.tip(im, 'The slot is deliberately empty over this range\n(the points go to other slots).\nright-click: remove the marker');
                end
                if p2 and kit.isFn(im, 'PopID') then pcall(im.PopID); end
                if okS and sclick and e.id ~= 0 then
                    st.selectedId = e.id;
                    st.detailOpen[1] = true;
                    st.detailFocus = true;
                end
                if rc then
                    local okR, whyR = ctx.sets.removeEntry(set, slot, i, book);
                    st.applyNote = okR and nil or ('Cannot remove: %s.'):format(whyR);
                    return;                        -- indices just shifted
                end
            else
                kit.ctext(im, col, text);
            end
        end
    end
end

local function slotPlanner(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    st.detailOpen = st.detailOpen or { false };
    st.preview = st.preview or {};

    -- the level slider: PREVIEW ONLY -- the plain Apply never reads it
    local liveLvl = ctx.blu.effectiveLevel();
    local shown = previewLevel(ctx);
    kit.ctext(im, kit.COL.head, 'Level');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local sbuf = { shown };
    if kit.sliderInt(im, '##bdxlevel', sbuf, 1, 75, math.max(120, MID_W - 170)) then
        st.preview.value = sbuf[1];
        shown = sbuf[1];
    end
    kit.tip(im, 'Preview the set at any level: the slot list, the meters and\n'
        .. 'the Stats pane all follow. Applying always uses your REAL\n'
        .. 'level -- except the explicit "Apply for Lv." button below.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Live', st.preview.value == nil,
        kit.measure(im, { 'Live' }, 40), 20) then
        st.preview.value = nil;
        shown = previewLevel(ctx);
    end
    kit.tip(im, 'Follow your real level (75 while off BLU).');
    if liveLvl ~= nil and shown ~= liveLvl then
        kit.ctext(im, kit.COL.warn, ('previewing Lv.%d - live Lv.%d'):format(shown, liveLvl));
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    -- what the CLIENT has set right now, for the per-row live tags
    local liveIds = nil;
    local live = ctx.blu.currentSet();
    if #live == 20 then
        liveIds = {};
        for i = 1, 20 do if live[i] ~= 0 then liveIds[live[i]] = true; end end
    end

    local nameW = math.max(kit.availWidth(im, MID_W) - 78, 120);
    for _, g in ipairs(ctx.sets.brackets()) do
        local locked = shown < g.floor;
        kit.ctext(im, locked and kit.COL.dim or kit.COL.head,
            ('Lv.%d-%d'):format(g.floor, bracketTop(g.floor)));
        if locked then
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            kit.ctext(im, kit.COL.dim, '  (locked at this level)');
        end
        for _, slot in ipairs(g.slots) do
            chainRow(ctx, slot, shown, liveIds, locked, nameW);
        end
    end

    if kit.isFn(im, 'Separator') then im.Separator(); end
    -- meters at the PREVIEW level. At the live level the client-preferred
    -- budget applies (ctx.budgetMax); elsewhere only the model can answer.
    local ids = ctx.sets.resolveAtLevel(set, shown, book);
    local capShown;
    if liveLvl ~= nil and shown == liveLvl then
        capShown = ctx.budgetMax();
    else
        capShown = M.budgetFn(ctx)(shown);
    end
    kit.meter(im, ('Points Lv.%d'):format(shown), ctx.sets.usedPoints(ids, book), capShown, '');
    if capShown == nil then
        kit.tip(im, 'The budget for this level is not known yet (learned bonus\nunmeasured). Bands below are provisional meanwhile.');
    end
    local activeN = 0;
    for i = 1, 20 do if (ids[i] or 0) ~= 0 then activeN = activeN + 1; end end
    kit.meter(im, 'Slots ', activeN, ctx.sets.slotsAtLevel(shown), '');
    kit.ctext(im, kit.COL.dim, ('Total MP %d'):format(ctx.sets.usedMP(ids, book)));

    -- the whole-curve verdict (plan 2.6): red = enforced and real (Apply
    -- blocked), orange = enforced but provisional, grey = below builtFor
    local bands = ctx.sets.bandViolations(set, book, M.budgetFn(ctx));
    for bi, b in ipairs(bands) do
        if bi > 4 then
            kit.ctext(im, kit.COL.dim, ('  ...and %d more band(s)'):format(#bands - 4));
            break;
        end
        local col = (b.enforced and not b.provisional) and kit.COL.err
            or (b.enforced and kit.COL.warn or kit.COL.dim);
        kit.ctext(im, col, '  ' .. ctx.sets.bandText(b));
    end

    -- the level-sync line: the meters above are the PLAN at the preview
    -- level; this is what the client holds right now while synced
    local ss = ctx.blu.syncStats(book);
    if ss ~= nil and ss.level < 75 then
        local liveMax = ctx.blu.budget();      -- the synced level's budget
        kit.ctext(im, kit.COL.warn, ('Sync Lv.%d: %d / %s pts, %d / %d slots'):format(
            ss.level, ss.activePoints, liveMax and tostring(liveMax) or '?',
            ss.active, ss.maxSlots));
        kit.tip(im, 'What the level sync leaves live right now - the game\n'
            .. 'disabled the rest itself and restores it when the sync ends.');
    end

    -- game actions (widths measured -- the clipping law)
    if kit.isFn(im, 'Separator') then im.Separator(); end
    local astate = M.applyState(ctx);
    local applyW = kit.measure(im, { 'Apply in game', 'Applying...' }, 100);
    local readW  = kit.measure(im, { 'Read current', 'Confirm read?' }, 90);
    local clearW = kit.measure(im, { 'Clear' }, 50);
    local pal = nil;
    if not ctx.blu.applying then
        if astate == 'dirty' then pal = kit.PAL.go;
        elseif astate ~= nil then pal = kit.PAL.off; end
    end
    if kit.litButton(im, ctx.blu.applying and 'Applying...' or 'Apply in game', false, applyW, 26, pal) then
        if astate == 'clean' then
            st.applyNote = 'Already up to date - nothing to apply.';
        else
            M.applyEditing(ctx);
        end
    end
    kit.tip(im, astate == 'planned'
        and 'The live set matches a plan you applied for another level.\nClicking applies the plan for your CURRENT level instead.'
        or 'Send the plan for your REAL level - only the changed slots.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    -- Read current: TWO clicks (plan 2.11 -- too easy to overwrite), and
    -- the replaced chains are banked as a backup first
    local confirming = st.readConfirm ~= nil and os.clock() < st.readConfirm;
    if not confirming then st.readConfirm = nil; end
    if kit.litButton(im, confirming and 'Confirm read?' or 'Read current', false, readW, 26,
        confirming and kit.PAL.go or nil) then
        if not confirming then
            st.readConfirm = os.clock() + 4.0;
        else
            st.readConfirm = nil;
            local liveNow = ctx.blu.currentSet();
            if #liveNow == 20 then
                ctx.sets.pushBackup(set, set, os.time());
                set.chains = ctx.sets.buildChains(liveNow, book);
                ctx.sets.syncLegacyIds(set, book);
                local unknown = 0;
                for i = 1, 20 do
                    if liveNow[i] ~= 0 and book.spells[liveNow[i]] == nil then
                        unknown = unknown + 1;
                    end
                end
                -- unknown ids are kept (honest mirror of the client) -- the
                -- rows draw them as '#id' and the totals simply skip them
                st.applyNote = unknown == 0
                    and 'Read the live set - the old chains are backup 1.'
                    or ('Read the live set (old chains backed up); %d slot(s) hold ids the data does not know.'):format(unknown);
            else
                st.applyNote = 'Could not read the live set.';
            end
        end
    end
    kit.tip(im, confirming
        and 'Click again to REPLACE the editing set with what the game\nholds (flat - the game knows nothing of chains). The current\nchains are banked as a backup first.'
        or 'Copy the in-game set here. Takes TWO clicks, because it\nreplaces your chains (a backup is banked first).');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Clear', false, clearW, 26) then
        ctx.sets.clear(st.editingSet);
        st.applyNote = nil;
    end

    -- the preemptive apply (plan 2.9): only offered while previewing away
    -- from the live level, and never bearing the plain Apply's label
    if liveLvl ~= nil and shown ~= liveLvl and not ctx.blu.applying then
        local aflLbl = ('Apply for Lv.%d'):format(shown);
        local aflW = kit.measure(im, { aflLbl }, 110);
        if kit.litButton(im, aflLbl, false, aflW, 24, kit.PAL.go) then
            M.applyEditing(ctx, shown);
        end
        kit.tip(im, ('Send the plan for Lv.%d NOW, at Lv.%d -- eat the 60s cast\n'
            .. 'lock before a level sync instead of during it. The header\n'
            .. 'then reads "matches your Lv.%d plan" instead of glowing.')
            :format(shown, liveLvl, shown));
    end
    if not ctx.blu.onBlu() then
        kit.ctext(im, kit.COL.warn, 'BLU is not your main or sub job.');
    end
    if st.applyNote then kit.ctext(im, kit.COL.dim, st.applyNote); end

    -- level-change behavior (plan 2.7-2.8): the timeline may plan different
    -- spells for a new level; auto applies by itself, manual nudges
    -- the naming law: name the rule for its condition, never 'Auto <thing>'
    kit.ctext(im, kit.COL.dim, 'Level change:');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local lvW = kit.measure(im, { 'Auto-apply', 'Manual' }, 64);
    local auto = ctx.cfg.replan == 'auto';
    if kit.litButton(im, 'Auto-apply', auto, lvW, 20) and not auto then
        ctx.cfg.replan = 'auto';
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'After a level change (up, down, or a sync), the plan for the\n'
        .. 'new level is applied by itself once the level settles. THIS MAY\n'
        .. 'UNSET SPELLS - the timeline replaces as you level. Stays quiet\n'
        .. 'when the change would only remove (the game\'s own disable\n'
        .. 'already covers that). Every change costs the 60s cast lock.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Manual', not auto, lvW, 20) and auto then
        ctx.cfg.replan = 'manual';
        if ctx.save then ctx.save(); end
    end
    kit.tip(im, 'Nothing applies by itself. A note in the header, a small\n'
        .. 'float window while Bludex is closed, and one chat line -\n'
        .. 'you click Apply when it suits.');
end

-- ---------------------------------------------------------------------------
-- the right column: Stats (default) | Assign (the picker for one slot)
-- ---------------------------------------------------------------------------
local function statsPanel(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local shown = previewLevel(ctx);
    local ids = ctx.sets.resolveAtLevel(st.editingSet, shown, book);
    kit.header(im, ('Set stats - Lv.%d'):format(shown));
    local stats = ctx.sets.stats(ids, book);
    if #stats == 0 then
        kit.ctext(im, kit.COL.dim, 'no stat bonuses at this level');
    else
        for _, e in ipairs(stats) do
            kit.ctext(im, e.value >= 0 and kit.COL.ok or kit.COL.err,
                ('%s %+d'):format(ctx.sets.prettyStat(e.stat), e.value));
        end
    end

    if kit.isFn(im, 'Separator') then im.Separator(); end
    kit.header(im, 'Traits');
    local evals = ctx.sets.traitEval(ids, book);
    if #evals == 0 then
        kit.ctext(im, kit.COL.dim, 'no trait weight at this level');
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

-- The picker for the selected slot: search + category over the codex data,
-- rows sorted by level, right-click assigns (the level control's choice or
-- the spell's own level), blocked rows dim with the reason in the tooltip.
local function assignPane(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    if st.assignSlot == nil then
        kit.ctext(im, kit.COL.dim, 'Pick a target first: the + on a slot row\nin the middle column.');
        return;
    end
    local slot = st.assignSlot;
    local floor = ctx.sets.bracketFloor(slot);
    kit.ctext(im, kit.COL.head, ('Assign - bracket Lv.%d-%d'):format(floor, bracketTop(floor)));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Close', false, kit.measure(im, { 'Close' }, 54), 20) then
        st.assignSlot = nil;
        st.rightTab = 'Stats';
        return;
    end

    -- the activation-level control (plan 2.3: default = the spell's level)
    st.assignLevel = st.assignLevel or { '' };
    kit.helpLabel(im, 'Activate at Lv.',
        'Blank = the spell\'s own level (the default, and the earliest\n'
        .. 'legal moment). Type a level to delay a swap -- or to place the\n'
        .. 'empty marker, which needs an explicit level.', kit.COL.dim);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(40); end
    if kit.isFn(im, 'InputText') then
        pcall(im.InputText, '##bdxassignlvl', st.assignLevel, 3);
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local lvOverride = tonumber(st.assignLevel[1]);
    if lvOverride ~= nil then lvOverride = math.floor(lvOverride); end
    local mw = kit.measure(im, { 'Empty from that Lv.' }, 120);
    if kit.litButton(im, 'Empty from that Lv.', false, mw, 20) then
        if lvOverride == nil then
            st.addNote = 'Type the level the slot should go empty at first.';
        else
            local okE, whyE = ctx.sets.addEntry(set, slot, 0, lvOverride, book);
            st.addNote = okE and ('The slot goes empty at Lv.%d.'):format(lvOverride)
                or ('Cannot: %s.'):format(whyE);
        end
    end
    kit.tip(im, 'End the chain deliberately: from that level the slot sits\n'
        .. 'vacant and its points go elsewhere. Shows as an entry;\n'
        .. 'remove it like one.');
    if st.addNote then kit.ctext(im, kit.COL.dim, st.addNote); end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    st.assignFilter = st.assignFilter or { text = { '' }, category = {} };
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(140); end
    if kit.isFn(im, 'InputText') then
        pcall(im.InputText, '##bdxassignsearch', st.assignFilter.text, 48);
        kit.tip(im, 'Filter by name');
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxassigncat', st.assignFilter.category, book.categories, 'All types',
        kit.measure(im, book.categories, 80) + 24);

    local ids = book.filter({
        text = st.assignFilter.text[1],
        category = st.assignFilter.category.value,
    });
    local sp = book.spells;
    table.sort(ids, function(a, b)
        local la, lb = sp[a].level or 999, sp[b].level or 999;
        if la ~= lb then return la < lb; end
        return sp[a].name < sp[b].name;
    end);

    if not (kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild')) then return; end
    if im.BeginChild('bdxassignlist', { 0, 0 }, false) then
        local nameW = math.max(kit.availWidth(im, 340) - 52, 120);
        for _, id in ipairs(ids) do
            local s = sp[id];
            local okA, whyA = ctx.sets.canAddEntry(set, slot, id, lvOverride, book);
            local label = ('%s  Lv.%s  %spt'):format(s.name, s.level or '?', s.setPoints or '?');
            local lclick, rclick, hov = spellsui.listRow(ctx, id, 24, nameW, false, true,
                okA and { label = label } or { label = label, textCol = kit.COL.dim });
            if lclick then
                st.selectedId = id;
                st.detailOpen[1] = true;
                st.detailFocus = true;
            end
            if rclick then
                if okA then
                    local okDo, whyDo = ctx.sets.addEntry(set, slot, id, lvOverride, book);
                    st.addNote = okDo and ('Assigned %s.'):format(s.name)
                        or ('Cannot assign %s: %s.'):format(s.name, whyDo);
                else
                    st.addNote = ('Cannot assign %s: %s.'):format(s.name, whyA);
                end
            end
            spellsui.tooltip(ctx, id, hov, okA
                and { { 'right-click: assign into the slot', kit.COL.dim } }
                or { { 'blocked: ' .. tostring(whyA), kit.COL.err } });
        end
    end
    im.EndChild();
end

local function rightPanel(ctx)
    local im, st = ctx.im, ctx.state;
    st.rightTab = st.rightTab or 'Stats';
    local w = kit.measure(im, { 'Stats', 'Assign' }, 64);
    if kit.litButton(im, 'Stats', st.rightTab ~= 'Assign', w, 20) then
        st.rightTab = 'Stats';
    end
    kit.tip(im, 'Stats and traits at the preview level.');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Assign', st.rightTab == 'Assign', w, 20) then
        st.rightTab = 'Assign';
    end
    kit.tip(im, 'The spell picker for the selected slot.');
    if kit.isFn(im, 'Separator') then im.Separator(); end
    if st.rightTab == 'Assign' then
        assignPane(ctx);
    else
        statsPanel(ctx);
    end
end

function M.render(ctx)
    local im = ctx.im;
    -- child widths follow their widest measured rows (the clipping law --
    -- 'Clea', 'Man' and 'Dele' all clipped in the field at the old fixed
    -- widths)
    local rowW = kit.measure(im, { 'New', 'Save', 'Delete' }, 50);
    LEFT_W = math.max(210, rowW * 3 + 32);
    local gameRow = kit.measure(im, { 'Apply in game', 'Applying...' }, 100)
        + kit.measure(im, { 'Read current', 'Confirm read?' }, 90)
        + kit.measure(im, { 'Clear' }, 50);
    local levelRow = kit.measure(im, { 'Level change:' }, 60)
        + kit.measure(im, { 'Auto-apply', 'Manual' }, 64) * 2;
    MID_W = math.max(340, gameRow + 34, levelRow + 34);
    if kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild') then
        if im.BeginChild('bdxsaved', { LEFT_W, 0 }, true) then savedList(ctx); end
        im.EndChild();
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if im.BeginChild('bdxslots', { MID_W, 0 }, true) then slotPlanner(ctx); end
        im.EndChild();
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if im.BeginChild('bdxstats', { 0, 0 }, true) then rightPanel(ctx); end
        im.EndChild();
    else
        savedList(ctx); slotPlanner(ctx); rightPanel(ctx);
    end
end

return M;
