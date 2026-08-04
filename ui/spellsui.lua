--[[
    bludex/ui/spellsui.lua -- the Codex tab: filter row, a set-budget readout,
    and an icon+name LIST (1-3 columns by window width). Clicking a row opens
    the Spell Info window (the 320 sprite plus everything the data layer
    knows, with Add-to-set at the top).

    All imgui calls run through kit's guards; every icon draw has a text
    fallback so a failed texture never blanks the tab. spellButton (the icon
    cell) stays exported for the Sets tab slot grid.
]]--

local kit     = require('bludex\\ui\\kit');
local filetex = require('bludex\\ui\\filetex');

local M = {};

-- guarded PushID/PopID: a grid of ImageButtons re-uses texture handles as IDs,
-- so every button gets an explicit ID pushed around it.
local function pushId(im, id)
    if kit.isFn(im, 'PushID') then pcall(im.PushID, tostring(id)); return true; end
    return false;
end
local function popId(im, pushed)
    if pushed and kit.isFn(im, 'PopID') then pcall(im.PopID); end
end

-- content-region width, tolerant of binding return shapes; fallback when
-- unreadable or absurd
local function availWidth(im, fallback)
    if kit.isFn(im, 'GetContentRegionAvail') then
        local ok, w = pcall(function()
            local v = { im.GetContentRegionAvail() };
            local first = v[1];
            if type(first) == 'table' then return first[1] or first.x; end
            return first;
        end);
        if ok and type(w) == 'number' and w > 100 then return w; end
    end
    return fallback;
end

-- One spell cell: ImageButton if the sprite loads, text button otherwise.
-- Returns true on click. `dimmed` greys the sprite (unlearned).
function M.spellButton(ctx, id, size, selected, dimmed)
    local im, book = ctx.im, ctx.book;
    local s = book.spells[id];
    local clicked = false;
    local pushed = pushId(im, 'bdxsp' .. id);
    if s == nil then
        -- an id the data does not know (a live-read slot can carry one):
        -- an inert-looking but still clickable cell, never an error.
        -- +4: image cells are size + 2px frame padding per side; text cells
        -- must match or mixed rows drift out of alignment.
        clicked = kit.litButton(im, '#' .. tostring(id), selected, size + 4, size + 4);
        popId(im, pushed);
        return clicked;
    end
    local h = filetex.spell(book, s, size >= 96 and 'grid128' or 'grid64');
    if h ~= nil and kit.isFn(im, 'ImageButton') then
        -- ImageButton's frame draws in the style Button color (red in the
        -- default Ashita theme) -- make it transparent so only the sprite
        -- shows; hover/active glow soft blue.
        local styled = false;
        if kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
            im.PushStyleColor(21, { 0, 0, 0, 0 });                 -- Button
            im.PushStyleColor(22, { 0.20, 0.42, 0.74, 0.45 });     -- Hovered
            im.PushStyleColor(23, { 0.20, 0.42, 0.74, 0.70 });     -- Active
            styled = true;
        end
        local bg = selected and { 0.20, 0.42, 0.74, 0.85 } or { 0, 0, 0, 0 };
        local tint = dimmed and { 0.45, 0.45, 0.50, 0.85 } or { 1, 1, 1, 1 };
        local ok, r = pcall(im.ImageButton, h, { size, size }, { 0, 0 }, { 1, 1 }, 2, bg, tint);
        if not ok then
            ok, r = pcall(im.ImageButton, h, { size, size });
        end
        if styled then im.PopStyleColor(3); end
        clicked = ok and r or false;
    else
        -- +4 to match the image cells' frame padding (see above)
        clicked = kit.litButton(im, s.name:sub(1, 10), selected, size + 4, size + 4);
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
    if s == nil then return; end
    local lines = { s.name };
    lines[#lines + 1] = ('%s - Lv.%s - %s'):format(s.category, s.level or '?', s.spellType or '?');
    if s.setPoints then lines[#lines + 1] = ('Set: %d pts'):format(s.setPoints); end
    if s.unbridled then lines[#lines + 1] = 'Unbridled Learning'; end
    local lt = learnedText(ctx, id);
    if lt then lines[#lines + 1] = lt; end
    if s.castable and not s.unbridled and s.setPoints then
        if ctx.sets.contains(ctx.state.editingSet, id) then
            lines[#lines + 1] = 'right-click: remove from set';
        elseif book.learned(id) then
            lines[#lines + 1] = 'right-click: add to set';
        end
    end
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

    -- add/remove FIRST -- the working button belongs at the top, not under
    -- a screen of lore. It flips to remove when the spell is in the set.
    if s.castable and not s.unbridled and s.setPoints then
        local btnW = kit.measure(im, { 'Add to current set', 'Remove from set' }, 150);
        if ctx.sets.contains(ctx.state.editingSet, id) then
            -- removal always works, even for spells that predate the
            -- learned gate (or came in from a live read)
            if kit.litButton(im, 'Remove from set', true, btnW, 26) then
                ctx.sets.removeId(ctx.state.editingSet, id);
                ctx.state.addNote = ('Removed %s.'):format(s.name);
                if ctx.save then ctx.save(); end
            end
        elseif not book.learned(id) then
            kit.ctext(im, kit.COL.err, 'Not learned - learn it before it can be set.');
        else
            if kit.litButton(im, 'Add to current set', false, btnW, 26) then
                local max = ctx.budgetMax();
                local ok, why = ctx.sets.add(ctx.state.editingSet, id, book, max);
                ctx.state.addNote = ok and ('Added %s.'):format(s.name) or ('Cannot add: %s.'):format(why);
                if ok and ctx.save then ctx.save(); end
            end
        end
        if ctx.state.addNote then
            kit.ctext(im, kit.COL.dim, ctx.state.addNote);
        end
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    local h = filetex.spell(book, s, 'detail');
    if h ~= nil and kit.isFn(im, 'Image') then
        -- center the sprite in the window
        local off = (availWidth(im, 352) - 320) / 2;
        if off > 0 and kit.isFn(im, 'GetCursorPosX') and kit.isFn(im, 'SetCursorPosX') then
            local okx, cx = pcall(im.GetCursorPosX);
            if okx and type(cx) == 'number' then pcall(im.SetCursorPosX, cx + off); end
        end
        pcall(im.Image, h, { 320, 320 });
    end

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
        kit.kvw(im, 'Skillchain', table.concat(s.skillchain, ', '));
    end
    if s.bursts and #s.bursts > 0 then
        kit.kvw(im, 'Bursts on', table.concat(s.bursts, ', '));
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
            kit.wrapped(im, kit.COL.dim, '  ' .. table.concat(hz.mobs, ', '));
            shown = shown + 1;
        end
        kit.ctext(im, kit.COL.dim, '(retail-era data; CatsEyeXI can differ)');
    end

    -- provenance, quietly
    local prov = 'data: ' .. (s.src or '?');
    if s.verify then prov = prov .. '  unverified: ' .. table.concat(s.verify, ', '); end
    kit.ctext(im, kit.COL.dim, prov);
end

-- ---------------------------------------------------------------------------
-- list rows and the Spell Info window
-- ---------------------------------------------------------------------------

-- One list row: small icon + the spell name as a Selectable. Returns
-- (leftClicked, rightClicked). In-set spells draw green; unlearned dim
-- (while on BLU); in-set wins.
function M.listRow(ctx, id, iconSz, nameW, selected)
    local im, book = ctx.im, ctx.book;
    local s = book.spells[id];
    local pushed = pushId(im, 'bdxrow' .. id);
    local clicked, rclicked = false, false;
    if s == nil then
        clicked = kit.litButton(im, '#' .. tostring(id), selected, nameW, iconSz);
        popId(im, pushed);
        return clicked, false;
    end
    local dim = ctx.blu.onBlu() and not book.learned(id) or false;
    local inSet = ctx.sets.contains(ctx.state.editingSet, id) ~= nil;
    local h = filetex.spell(book, s, 'grid64');
    if h ~= nil and kit.isFn(im, 'Image') then
        local tint = dim and { 0.45, 0.45, 0.50, 0.85 } or { 1, 1, 1, 1 };
        local okI = pcall(im.Image, h, { iconSz, iconSz }, { 0, 0 }, { 1, 1 }, tint);
        if not okI then pcall(im.Image, h, { iconSz, iconSz }); end
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
    end
    local textCol = inSet and kit.COL.ok or (dim and kit.COL.dim or nil);
    if kit.isFn(im, 'Selectable') then
        local pushedCol = false;
        if textCol and kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
            im.PushStyleColor(0, textCol);                     -- Text
            pushedCol = true;
        end
        local ok, r = pcall(im.Selectable, kit.esc(s.name), selected, 0, { nameW, iconSz });
        if not ok then ok, r = pcall(im.Selectable, kit.esc(s.name), selected); end
        if pushedCol then im.PopStyleColor(1); end
        clicked = ok and r or false;
    else
        clicked = kit.litButton(im, s.name, selected, nameW, iconSz);
    end
    if kit.isFn(im, 'IsItemClicked') then
        local okc, rc = pcall(im.IsItemClicked, 1);            -- right button
        rclicked = okc and rc or false;
    end
    popId(im, pushed);
    return clicked, rclicked;
end

-- The Spell Info window: opened by clicking a row, closable via the title
-- bar. Rendered inside the host's style pushes, so it inherits the theme.
function M.detailWindow(ctx)
    local im, st = ctx.im, ctx.state;
    if not st.detailOpen or not st.detailOpen[1] then return; end
    if st.selectedId == nil then st.detailOpen[1] = false; return; end
    if not (kit.isFn(im, 'Begin') and kit.isFn(im, 'End')) then return; end
    if kit.isFn(im, 'SetNextWindowSizeConstraints') then
        pcall(im.SetNextWindowSizeConstraints, { 380, 420 }, { 900, 1400 });
    end
    if st.detailFocus and kit.isFn(im, 'SetNextWindowFocus') then
        pcall(im.SetNextWindowFocus);
    end
    st.detailFocus = nil;
    local visible = false;
    local ok = pcall(function()
        visible = im.Begin('Spell Info##bdxspellinfo', st.detailOpen);
    end);
    if ok and visible then
        local dok, derr = pcall(M.detail, ctx, st.selectedId);
        if not dok then
            kit.ctext(im, kit.COL.err, 'detail error: ' .. tostring(derr));
        end
    end
    if ok then im.End(); end
end

-- ---------------------------------------------------------------------------
-- the tab
-- ---------------------------------------------------------------------------
function M.render(ctx)
    local im, book, st = ctx.im, ctx.book, ctx.state;
    local f = st.filters;
    st.detailOpen = st.detailOpen or { false };

    -- filter row -- combo widths measured over every label they can show
    -- (the kit law: a hardcoded width clips a trailing character; "All eleme").
    local function comboW(choices, allLabel)
        local labels = { allLabel };
        for _, c in ipairs(choices) do labels[#labels + 1] = c; end
        return kit.measure(im, labels, 96) + 24;    -- +24 for the arrow box
    end
    local traitNames = {};
    for _, t in ipairs(book.traitChoices) do traitNames[#traitNames + 1] = t.name; end
    if kit.isFn(im, 'SetNextItemWidth') then im.SetNextItemWidth(160); end
    if kit.isFn(im, 'InputText') then
        pcall(im.InputText, '##bdxsearch', f.text, 64);
        kit.tip(im, 'Filter by name');
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxcat', f.category, book.categories, 'All types',
        comboW(book.categories, 'All types'));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxele', f.element, book.elements, 'All elements',
        comboW(book.elements, 'All elements'));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxsty', f.spellType, book.types, 'All kinds',
        comboW(book.types, 'All kinds'));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxtrait', f.trait, traitNames, 'All traits',
        comboW(traitNames, 'All traits'));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.combo(im, '##bdxlearn', f.learned, { 'Learned', 'Missing' }, 'All spells',
        comboW({ 'Learned', 'Missing' }, 'All spells'));
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

    -- result count (the set/slot meters live in the window header now) plus
    -- the last add/remove result -- the right-click path has no window open
    kit.ctext(im, kit.COL.dim, ('%d spells'):format(#ids));
    if st.addNote then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   ' .. st.addNote);
    end

    -- the list: icon + name rows, 1-3 columns by available width
    local availW = availWidth(im, 800);
    local cols = math.max(1, math.min(3, math.floor(availW / 250)));
    local colW = math.floor((availW - 16) / cols);   -- -16: scrollbar margin
    local iconSz = 24;
    local nameW = math.max(colW - iconSz - 28, 80);

    local function rows()
        for i, id in ipairs(ids) do
            local col = (i - 1) % cols;
            if col ~= 0 and kit.isFn(im, 'SameLine') then im.SameLine(col * colW + 8); end
            local lclick, rclick = M.listRow(ctx, id, iconSz, nameW, st.selectedId == id);
            if lclick then
                st.selectedId = id;
                st.detailOpen[1] = true;
                st.detailFocus = true;
            end
            if rclick then
                -- toggle set membership without opening the window
                local s = book.spells[id];
                if s ~= nil then
                    if ctx.sets.contains(st.editingSet, id) then
                        ctx.sets.removeId(st.editingSet, id);
                        st.addNote = ('Removed %s.'):format(s.name);
                        if ctx.save then ctx.save(); end
                    else
                        local ok, why = ctx.sets.add(st.editingSet, id, book, ctx.budgetMax());
                        st.addNote = ok and ('Added %s.'):format(s.name)
                            or ('Cannot add %s: %s.'):format(s.name, why);
                        if ok and ctx.save then ctx.save(); end
                    end
                end
            end
            M.tooltip(ctx, id);
        end
    end

    if kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild') then
        if im.BeginChild('bdxlist', { 0, 0 }, false) then rows(); end
        im.EndChild();
    else
        rows();
    end

    M.detailWindow(ctx);
end

return M;
