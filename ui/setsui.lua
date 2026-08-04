--[[
    bludex/ui/setsui.lua -- the Sets tab: saved sets, the 20-slot editor, the
    live budget meters, apply/read/clear against the game, and the computed
    stats + traits panel for the set being edited.

    The budget meter prefers the LIVE client value (lib/blu points signature;
    CatsEyeXI's custom merit/learning bonuses included). Everything degrades:
    no signature -> settings override -> '?'.
]]--

local kit      = require('bludex\\ui\\kit');
local filetex  = require('bludex\\ui\\filetex');
local spellsui = require('bludex\\ui\\spellsui');

local M = {};

local LEFT_W  = 210;
local MID_W   = 330;

-- ---------------------------------------------------------------------------
-- saved sets (persisted in settings as { name = s, ids = {20} })
-- ---------------------------------------------------------------------------
local function savedList(ctx)
    local im, st, cfg = ctx.im, ctx.state, ctx.cfg;
    kit.header(im, 'Saved sets');
    if kit.isFn(im, 'Selectable') then
        for i, entry in ipairs(cfg.sets) do
            local label = ('%s (%d)##bdxset%d'):format(entry.name, (function()
                local n = 0;
                for k = 1, 20 do if (entry.ids[k] or 0) ~= 0 then n = n + 1; end end
                return n;
            end)(), i);
            local ok, clicked = pcall(im.Selectable, kit.esc(label), st.activeSet == i);
            if ok and clicked then
                st.activeSet = i;
                st.editingSet = ctx.sets.clone(entry, entry.name);
                st.applyNote = nil;
            end
        end
    end
    if #cfg.sets == 0 then
        kit.ctext(im, kit.COL.dim, 'none yet');
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    if kit.litButton(im, 'New', false, 60, 22) then
        st.editingSet = ctx.sets.new(('Set %d'):format(#cfg.sets + 1));
        st.activeSet = nil;
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Save', false, 60, 22) then
        local copy = ctx.sets.clone(st.editingSet, st.editingSet.name);
        copy.name = st.editingSet.name;
        if st.activeSet and cfg.sets[st.activeSet] then
            cfg.sets[st.activeSet] = copy;
        else
            table.insert(cfg.sets, copy);
            st.activeSet = #cfg.sets;
        end
        if ctx.save then ctx.save(); end
        st.applyNote = 'Saved.';
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Delete', false, 60, 22) then
        if st.activeSet and cfg.sets[st.activeSet] then
            table.remove(cfg.sets, st.activeSet);
            st.activeSet = nil;
            if ctx.save then ctx.save(); end
            st.applyNote = 'Deleted.';
        end
    end

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
local function slotGrid(ctx)
    local im, st, book = ctx.im, ctx.state, ctx.book;
    local set = st.editingSet;
    kit.header(im, 'Slots');
    local cell = 48;
    for i = 1, 20 do
        if ((i - 1) % 5) ~= 0 and kit.isFn(im, 'SameLine') then im.SameLine(); end
        local id = set.ids[i] or 0;
        if id ~= 0 then
            if spellsui.spellButton(ctx, id, cell, false, false) then
                ctx.sets.removeSlot(set, i);
                st.applyNote = nil;
            end
            local s = book.spells[id];
            if s ~= nil then
                kit.tip(im, ('%s\n%d pts%s\nclick to remove'):format(
                    s.name, s.setPoints or 0, s.mpCost and ('  ' .. s.mpCost .. ' MP') or ''));
            else
                kit.tip(im, ('slot %d: spell id %d is not in the data\nclick to remove'):format(i, id));
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
                    styled = true;
                end
                pcall(im.ImageButton, h, { cell, cell });
                if styled then im.PopStyleColor(3); end
            else
                kit.litButton(im, '-', false, cell, cell);
            end
            if pushed and kit.isFn(im, 'PopID') then pcall(im.PopID); end
            kit.tip(im, ('slot %d (empty)'):format(i));
        end
    end

    if kit.isFn(im, 'Separator') then im.Separator(); end
    local used = ctx.sets.usedPoints(st.editingSet, book);
    local max = ctx.budgetMax();
    kit.meter(im, 'Points', used, max, '');
    if max == nil then
        kit.tip(im, 'Live budget appears when you are on BLU.\nSet an override in settings otherwise.');
    end
    kit.meter(im, 'Slots ', ctx.sets.count(st.editingSet), 20, '');
    kit.ctext(im, kit.COL.dim, ('Total MP %d'):format(ctx.sets.usedMP(st.editingSet, book)));

    -- game actions
    if kit.isFn(im, 'Separator') then im.Separator(); end
    local canApply = ctx.blu.canApply() and not ctx.blu.applying;
    if kit.litButton(im, ctx.blu.applying and 'Applying...' or 'Apply in game', false, 110, 26) then
        if canApply then
            ctx.blu.applySet(st.editingSet.ids);
            st.applyNote = 'Applying - watch the chat log.';
        elseif not ctx.blu.applying then
            -- a dead button with no reason is a field mystery -- say why
            st.applyNote = ctx.blu.onBlu()
                and 'Cannot apply: the client memory signatures did not resolve.'
                or 'Cannot apply: BLU is not your main or sub job.';
        end
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Read current', false, 100, 26) then
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
        else
            st.applyNote = 'Could not read the live set.';
        end
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Clear', false, 60, 26) then
        ctx.sets.clear(st.editingSet);
        st.applyNote = nil;
    end
    if not ctx.blu.onBlu() then
        kit.ctext(im, kit.COL.warn, 'BLU is not your main or sub job.');
    end
    if st.applyNote then kit.ctext(im, kit.COL.dim, st.applyNote); end

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
