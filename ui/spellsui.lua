--[[
    bludex/ui/spellsui.lua -- the Codex tab: filter row, icon grid, and the
    spell detail panel (the 320 sprite plus everything the data layer knows).

    All imgui calls run through kit's guards; every icon draw has a text
    fallback so a failed texture never blanks the tab.
]]--

local kit     = require('bludex\\ui\\kit');
local filetex = require('bludex\\ui\\filetex');

local M = {};

local DETAIL_W = 352;

-- guarded PushID/PopID: a grid of ImageButtons re-uses texture handles as IDs,
-- so every button gets an explicit ID pushed around it.
local function pushId(im, id)
    if kit.isFn(im, 'PushID') then pcall(im.PushID, tostring(id)); return true; end
    return false;
end
local function popId(im, pushed)
    if pushed and kit.isFn(im, 'PopID') then pcall(im.PopID); end
end

-- One spell cell: ImageButton if the sprite loads, text button otherwise.
-- Returns true on click. `dimmed` greys the sprite (unlearned).
function M.spellButton(ctx, id, size, selected, dimmed)
    local im, book = ctx.im, ctx.book;
    local s = book.spells[id];
    local clicked = false;
    local pushed = pushId(im, 'bdxsp' .. id);
    local h = filetex.spell(book, s, size >= 96 and 'grid128' or 'grid64');
    if h ~= nil and kit.isFn(im, 'ImageButton') then
        local bg = selected and { 0.20, 0.42, 0.74, 0.85 } or { 0, 0, 0, 0 };
        local tint = dimmed and { 0.45, 0.45, 0.50, 0.85 } or { 1, 1, 1, 1 };
        local ok, r = pcall(im.ImageButton, h, { size, size }, { 0, 0 }, { 1, 1 }, 2, bg, tint);
        if not ok then
            ok, r = pcall(im.ImageButton, h, { size, size });
        end
        clicked = ok and r or false;
    else
        clicked = kit.litButton(im, s.name:sub(1, 10), selected, size, size);
    end
    popId(im, pushed);
    return clicked;
end

local function learnedText(ctx, id)
    if ctx.blu.onBlu() or ctx.book.learned(id) then
        if ctx.book.learned(id) then return 'learned', kit.COL.ok; end
        return 'not learned', kit.COL.err;
    end
    return nil, nil;
end

function M.tooltip(ctx, id)
    local im, book = ctx.im, ctx.book;
    if not (kit.isFn(im, 'IsItemHovered') and im.IsItemHovered()) then return; end
    local s = book.spells[id];
    local lines = { s.name };
    lines[#lines + 1] = ('%s - Lv.%s - %s'):format(s.category, s.level or '?', s.spellType or '?');
    if s.setPoints then lines[#lines + 1] = ('Set: %d pts'):format(s.setPoints); end
    if s.unbridled then lines[#lines + 1] = 'Unbridled Learning'; end
    local lt = learnedText(ctx, id);
    if lt then lines[#lines + 1] = lt; end
    kit.tip(im, table.concat(lines, '\n'));
end

-- ---------------------------------------------------------------------------
-- the detail panel (also reused by the Sets tab through ctx)
-- ---------------------------------------------------------------------------
function M.detail(ctx, id)
    local im, book = ctx.im, ctx.book;
    local s = book.spells[id];
    if s == nil then
        kit.ctext(im, kit.COL.dim, 'Select a spell.');
        return;
    end

    local h = filetex.spell(book, s, 'detail');
    if h ~= nil and kit.isFn(im, 'Image') then
        pcall(im.Image, h, { 320, 320 });
    end
    kit.ctext(im, kit.COL.head, s.name);
    local lt, ltc = learnedText(ctx, id);
    if lt then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, ltc, '[' .. lt .. ']');
    end
    if s.unbridled then
        kit.ctext(im, kit.COL.badge, 'Unbridled Learning');
    end
    if not s.castable then
        kit.ctext(im, kit.COL.err, 'Learnable but NEVER castable at the 75 cap.');
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    kit.kv(im, 'Type', ('%s%s'):format(s.spellType or '?',
        s.damageType and (' (' .. s.damageType .. ')') or ''));
    kit.kv(im, 'Element', s.element or 'None', kit.ELEMENT[s.element] or kit.COL.accent);
    if s.ecosystem then kit.kv(im, 'Monster', s.ecosystem); end
    kit.kv(im, 'Level', ('BLU %s%s'):format(s.level or '?',
        (s.stockLevel and s.stockLevel ~= s.level) and ('  (retail ' .. s.stockLevel .. ')') or ''));
    if s.mpCost then
        local t = ('%d MP'):format(s.mpCost);
        if s.castTime then t = t .. ('   cast %.1fs'):format(s.castTime); end
        if s.recastTime then t = t .. ('   recast %.0fs'):format(s.recastTime); end
        kit.kv(im, 'Cost', t);
    end
    if s.aoe then kit.kv(im, 'Area', 'AoE'); end
    if s.setPoints then
        kit.kv(im, 'Set cost', ('%d point%s'):format(s.setPoints, s.setPoints == 1 and '' or 's'));
    end
    if s.trait then
        kit.kv(im, 'Trait', ('%s  (weight %d)'):format(
            book.traitName(s.trait.category), s.trait.weight));
    end
    if s.skillchain and #s.skillchain > 0 then
        kit.kv(im, 'Skillchain', table.concat(s.skillchain, ', '));
    end
    if s.bursts and #s.bursts > 0 then
        kit.kv(im, 'Bursts on', table.concat(s.bursts, ', '));
    end
    if s.numhits and s.numhits > 1 then kit.kv(im, 'Hits', tostring(s.numhits)); end
    if s.mods and #s.mods > 0 then
        local parts = {};
        for _, m in ipairs(s.mods) do
            parts[#parts + 1] = ('%s%+d'):format(ctx.sets.prettyStat(m.stat), m.value);
        end
        kit.kv(im, 'Stats', table.concat(parts, '  '), kit.COL.ok);
    end
    if s.note then
        if kit.isFn(im, 'TextWrapped') then
            im.TextWrapped(kit.esc(s.note));
        else
            kit.ctext(im, kit.COL.warn, s.note);
        end
    end

    -- learn-location hints (retail-era data via blucheck)
    local hints = book.hintList(id);
    if hints then
        if kit.isFn(im, 'Separator') then im.Separator(); end
        kit.ctext(im, kit.COL.head, 'Learn from');
        local shown = 0;
        for _, hz in ipairs(hints) do
            if shown >= 6 then
                kit.ctext(im, kit.COL.dim, ('...and %d more zones'):format(#hints - shown));
                break;
            end
            kit.ctext(im, kit.COL.accent, hz.zone);
            kit.ctext(im, kit.COL.dim, '  ' .. table.concat(hz.mobs, ', '));
            shown = shown + 1;
        end
        kit.ctext(im, kit.COL.dim, '(retail-era data; CatsEyeXI can differ)');
    end

    -- add-to-set
    if s.castable and not s.unbridled and s.setPoints then
        if kit.isFn(im, 'Separator') then im.Separator(); end
        if kit.litButton(im, 'Add to current set', false, 180, 26) then
            local max = ctx.budgetMax();
            local ok, why = ctx.sets.add(ctx.state.editingSet, id, book, max);
            ctx.state.addNote = ok and ('Added %s.'):format(s.name) or ('Cannot add: %s.'):format(why);
            if ok and ctx.save then ctx.save(); end
        end
        if ctx.state.addNote then
            kit.ctext(im, kit.COL.dim, ctx.state.addNote);
        end
    end

    -- provenance, quietly
    local prov = 'data: ' .. (s.src or '?');
    if s.verify then prov = prov .. '  unverified: ' .. table.concat(s.verify, ', '); end
    kit.ctext(im, kit.COL.dim, prov);
end

-- ---------------------------------------------------------------------------
-- the tab
-- ---------------------------------------------------------------------------
function M.render(ctx)
    local im, book, st = ctx.im, ctx.book, ctx.state;
    local f = st.filters;

    -- filter row
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(160); end
    if kit.isFn(im, 'InputText') then
        pcall(im.InputText, '##bdxsearch', f.text, 64);
        kit.tip(im, 'Filter by name');
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxcat', f.category, book.categories, 'All types', 110);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxele', f.element, book.elements, 'All elements', 110);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxsty', f.spellType, book.types, 'All kinds', 100);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local traitNames = {};
    for _, t in ipairs(book.traitChoices) do traitNames[#traitNames + 1] = t.name; end
    kit.combo(im, '##bdxtrait', f.trait, traitNames, 'All traits', 150);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxlearn', f.learned, { 'Learned', 'Missing' }, 'All spells', 110);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if kit.litButton(im, 'Reset', false, 60, 22) then
        f.text[1] = ''; f.category.value = nil; f.element.value = nil;
        f.spellType.value = nil; f.trait.value = nil; f.learned.value = nil;
    end

    -- resolve filter spec
    local traitCat = nil;
    if f.trait.value then
        for _, t in ipairs(book.traitChoices) do
            if t.name == f.trait.value then traitCat = t.cat; break; end
        end
    end
    local learned = nil;
    if f.learned.value == 'Learned' then learned = true;
    elseif f.learned.value == 'Missing' then learned = false; end
    local ids = book.filter({
        text = f.text[1], category = f.category.value, element = f.element.value,
        spellType = f.spellType.value, traitCat = traitCat, learned = learned,
    });
    kit.ctext(im, kit.COL.dim, ('%d spells'):format(#ids));

    -- grid + detail, side by side
    local availW = 800;
    if kit.isFn(im, 'GetContentRegionAvail') then
        -- binding-dependent: returns (x, y) or a table {x,y}/{x=..}
        local ok, w = pcall(function()
            local v = { im.GetContentRegionAvail() };
            local first = v[1];
            if type(first) == 'table' then return first[1] or first.x; end
            return first;
        end);
        if ok and type(w) == 'number' and w > 200 then availW = w; end
    end
    local gridW = math.max(availW - DETAIL_W - 12, 240);

    if kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild') then
        if im.BeginChild('bdxgrid', { gridW, 0 }, false) then
            local cell = 52;
            local cols = math.max(math.floor(gridW / (cell + 10)), 3);
            for i, id in ipairs(ids) do
                if ((i - 1) % cols) ~= 0 and kit.isFn(im, 'SameLine') then im.SameLine(); end
                local dim = ctx.blu.onBlu() and not book.learned(id) or false;
                if M.spellButton(ctx, id, cell, st.selectedId == id, dim) then
                    st.selectedId = id;
                end
                M.tooltip(ctx, id);
            end
        end
        im.EndChild();
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        if im.BeginChild('bdxdetail', { DETAIL_W, 0 }, true) then
            M.detail(ctx, st.selectedId);
        end
        im.EndChild();
    else
        -- binding without children: detail only
        M.detail(ctx, st.selectedId);
    end
end

return M;
