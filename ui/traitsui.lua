--[[
    bludex/ui/traitsui.lua -- the Traits tab: every blue trait ladder, what the
    current editing set feeds it, and which spells to add for the next tier
    (the "I want more Dual Wield" answer).

    The spell rows speak the codex grammar (2026-08-04, reference-only since
    the timeline, 2026-08-08): icon+name rows in the chosen View density
    (own setting, cfg.traitsDensity), left-click opens the Spell Info
    window, hover shows the rich tooltip. In-set rows draw green, unlearned
    red. Assignment lives in the Sets tab's Assign pane.
]]--

local ROOT = (...):sub(1, -#('ui\\traitsui') - 1);   -- relocatable require base
local kit      = require(ROOT .. 'ui\\kit');
local tsrc     = require(ROOT .. 'lib\\traitsource');
local spellsui = require(ROOT .. 'ui\\spellsui');

local M = {};

-- 'Acc +10, R.Acc +10' -- a few job traits carry no direct modifier (the
-- server implements them in Lua), and an empty list must still say something.
local function modsText(ctx, mods)
    local parts = {};
    for _, m in ipairs(mods or {}) do
        parts[#parts + 1] = ('%s %+d'):format(ctx.sets.prettyStat(m.stat), m.value);
    end
    if #parts == 0 then return 'no direct stat bonus'; end
    return table.concat(parts, ', ');
end

-- WHERE IT CAME FROM, in as few words as fit on a row.
local function jobLabel(e)
    local who = e.code or ('job ' .. tostring(e.job));
    return ('%s (%s job)'):format(who, e.slot == 'sub' and 'sub' or 'main');
end

local function sourceLabel(a)
    if a.source ~= 'job' then return 'your set'; end
    return jobLabel(a.job);
end

-- WHAT YOU HAVE, IN THE LADDER'S OWN UNITS (Henrik 2026-08-07: "we wanna
-- correlate the trait tiers, not the actual stats"). The two sides of a
-- collision do not share a modifier -- job Clear Mind grants MPHEAL, the blue
-- ladder grants CLEAR_MIND -- so a stat value read off one side means nothing
-- against the other. The RANK does: it is the game's own counter for that
-- trait, and it is what the rungs below are numbered by.
--
-- The rung's own name comes along only when it differs from the ladder's, so
-- 'Triple Attack tier 2' never reads as a Double Attack tier.
local function tierLabel(v, a)
    local n = (a.traitName ~= nil and a.traitName ~= v.name)
        and (a.traitName .. ' tier ') or 'Tier ';
    return ('%s%d [%s]'):format(n, a.tier or 0, sourceLabel(a));
end

-- The sentence that matters: what the collision cost. Kept in one place --
-- the Traits tab says it long, the spell tooltip says it short.
function M.blockedTip(v)
    local e = v.blocker;
    if e == nil then return nil; end
    return ('%s already grants %s, and the server keeps the JOB trait -- the\n'
        .. 'blue one is discarded outright, whatever its tier. The %d weight\n'
        .. 'your set feeds this ladder buys nothing.'):format(
        jobLabel(e), v.name, v.weight);
end

function M.render(ctx)
    local im, book, st = ctx.im, ctx.book, ctx.state;
    local set = st.editingSet;
    st.detailOpen = st.detailOpen or { false };

    -- current weights by category, once per frame
    local evalByCat = {};
    for _, ev in ipairs(ctx.sets.traitEval(set, book)) do
        evalByCat[ev.cat] = ev;
    end

    -- a host without the job side still renders the ladders; it just cannot
    -- attribute (an empty job map = "nothing known", never "nothing granted")
    local verdict = ctx.verdict
        or function(c, w) return tsrc.verdict(c, w, book, {}, nil); end;

    kit.ctext(im, kit.COL.dim,
        'Weights come from spells in your CURRENT editing set (Sets tab).');
    -- WHOSE traits these are competing with -- the pair is the whole reason a
    -- ladder can be blocked, so it is named where the blocking is reported
    local jp = ctx.jobPair;
    if jp ~= nil then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        local sub = (jp.subJob or 0) > 0
            and ('%s%d'):format(tsrc.jobCode(jp.subJob) or '?', jp.subLevel or 0)
            or 'no sub';
        kit.helpLabel(im, ('   %s%d / %s'):format(
            tsrc.jobCode(jp.mainJob) or '?', jp.mainLevel or 0, sub),
            'Your jobs, and the reason a ladder can be blocked.\n\n'
            .. 'The server builds your job traits first -- main job at your main\n'
            .. 'level, then sub job at your sub level -- and only then adds blue\n'
            .. 'traits. A blue trait that matches one you already have is thrown\n'
            .. 'away, at any tier, so the set points feeding it buy nothing.\n\n'
            .. 'Job-trait data is the public CatsEyeXI source and can differ from\n'
            .. 'the live server; the game\'s own trait list has the last word.',
            kit.COL.accent);
    end
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.ctext(im, kit.COL.dim, '   View:');
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    local density = spellsui.densityCombo(ctx, 'traitsDensity');
    if st.addNote then
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        kit.ctext(im, kit.COL.dim, '   ' .. st.addNote);
    end
    if kit.isFn(im, 'Separator') then im.Separator(); end

    if not (kit.isFn(im, 'BeginChild') and kit.isFn(im, 'EndChild')) then return; end
    if im.BeginChild('bdxtraits', { 0, 0 }, false) then
        local iconSz, showIcon = spellsui.densityParams(density);
        local nameW = math.max(kit.availWidth(im, 600) - (showIcon and iconSz or 0) - 56, 120);
        for _, choice in ipairs(book.traitChoices) do
            local cat = choice.cat;
            local info = book.traits.categories[cat];
            local ev = evalByCat[cat];
            local weight = ev and ev.weight or 0;

            local open = st.openCat[cat] or false;
            if kit.isFn(im, 'Selectable') then
                local ok, clicked = pcall(im.Selectable, kit.esc((open and '[-] ' or '[+] ') .. choice.name), false);
                if ok and clicked then
                    st.openCat[cat] = not open;
                    open = not open;
                end
            else
                kit.ctext(im, kit.COL.head, choice.name);
                open = true;
            end
            -- WHAT IS ACTUALLY UP, and from where. A job trait beats a blue
            -- one outright, so the set's own ladder reading is not the answer
            -- on its own (lib/traitsource.lua).
            local v = verdict(cat, weight);
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
            if #v.active > 0 then
                for ai, a in ipairs(v.active) do
                    if ai > 1 and kit.isFn(im, 'SameLine') then im.SameLine(); end
                    -- green either way: you HAVE this. The tag says from whom.
                    kit.ctext(im, kit.COL.ok, tierLabel(v, a));
                    if a.source == 'job' then
                        kit.tip(im, ('%s grants %s at rank %d, from level %d.\n'
                            .. 'It gives %s -- which is NOT what the blue rungs below\n'
                            .. 'grant: the same trait, a different modifier, so only the\n'
                            .. 'tier number compares between them.\n\n'
                            .. 'Job traits are applied before blue ones, and a blue trait\n'
                            .. 'matching one you already have is discarded rather than\n'
                            .. 'added to it or upgraded.'):format(
                            a.job.name or sourceLabel(a), a.traitName or v.name,
                            a.job.rank, a.job.level, modsText(ctx, a.mods)));
                    else
                        kit.tip(im, ('Your set earns this: %s.'):format(modsText(ctx, a.mods)));
                    end
                end
                if v.deadWeight then
                    if kit.isFn(im, 'SameLine') then im.SameLine(); end
                    kit.ctext(im, kit.COL.err, ('  your %d weight is blocked'):format(weight));
                    kit.tip(im, M.blockedTip(v));
                end
            elseif weight > 0 then
                kit.ctext(im, kit.COL.warn, ('weight %d - below tier 1'):format(weight));
            else
                kit.ctext(im, kit.COL.dim, 'not in set');
            end
            -- the live 0x0AC bit is the referee: when the game disagrees with
            -- the table, say so rather than keep asserting
            if v.disagrees then
                if kit.isFn(im, 'SameLine') then im.SameLine(); end
                kit.ctext(im, kit.COL.warn, '  (game says no)');
                kit.tip(im, 'The game\'s own trait list does not have this trait up, though\n'
                    .. 'Bludex works out that it should be. The job-trait table is the\n'
                    .. 'public server source; CatsEyeXI can differ from it. Trust the game.');
            end

            if open and info then
                -- THE LADDER, with each rung in one of three states:
                --   held    a job's rank already reaches it -- green, named,
                --           and annotated with what the job ACTUALLY grants
                --           (different modifier, so never left implied)
                --   blocked the job holds this trait lower down; blue cannot
                --           lift a job trait, so the rung is out of reach
                --   open    the set's own, reached or not
                for ti, tier in ipairs(info.tiers) do
                    local reached = weight >= tier.points;
                    local heldBy, blockedBy = v.held[ti], v.blocked[ti];
                    local note, col = '', kit.COL.dim;
                    if heldBy ~= nil then
                        col = kit.COL.ok;
                        note = ('   <- %s, rank %d: %s'):format(
                            jobLabel(heldBy), heldBy.rank, modsText(ctx, heldBy.mods));
                    elseif blockedBy ~= nil then
                        col = kit.COL.err;
                        note = ('   -- out of reach: %s holds this trait at rank %d'):format(
                            jobLabel(blockedBy), blockedBy.rank);
                    elseif reached then
                        col = kit.COL.ok;
                    end
                    kit.ctext(im, col, ('   tier %d  (weight %d): %s%s'):format(
                        ti, tier.points, modsText(ctx, tier.mods), note));
                    if heldBy ~= nil then
                        kit.tip(im, ('You already have tier %d of %s, from %s.\n\n'
                            .. 'The job trait grants %s. The blue rung grants %s --\n'
                            .. 'the same trait through a different modifier, which is why\n'
                            .. 'only the tier number compares. You get the job\'s version;\n'
                            .. 'the blue one is discarded rather than added to it.'):format(
                            ti, v.name, jobLabel(heldBy),
                            modsText(ctx, heldBy.mods), modsText(ctx, tier.mods)));
                    elseif blockedBy ~= nil then
                        kit.tip(im, M.blockedTip(v));
                    end
                end
                -- contributing spells -- the codex row grammar (left-click =
                -- Spell Info, right-click = toggle in/out of the set)
                local indented = false;
                if kit.isFn(im, 'Indent') and kit.isFn(im, 'Unindent') then
                    pcall(im.Indent, 14);
                    indented = true;
                end
                -- reference rows, like the codex (Henrik 2026-08-08): the
                -- [in set] tag and the green tint report; assignment lives
                -- in the Sets tab alone
                for _, id in ipairs(book.byTrait[cat] or {}) do
                    local s = book.spells[id];
                    local inSet = ctx.sets.contains(set, id) ~= nil;
                    local label = ('%s  w%d / %spts  Lv.%s%s'):format(
                        s.name, s.trait.weight, s.setPoints or '?', s.level or '?',
                        inSet and '  [in set]' or '');
                    local lclick, _, hov = spellsui.listRow(ctx, id, iconSz, nameW,
                        st.selectedId == id, showIcon,
                        { label = label, dimColor = kit.COL.err });
                    if lclick then
                        st.selectedId = id;
                        st.detailOpen[1] = true;
                        st.detailFocus = true;
                    end
                    spellsui.tooltip(ctx, id, hov);
                end
                if indented then pcall(im.Unindent, 14); end
                if kit.isFn(im, 'Separator') then im.Separator(); end
            end
        end
    end
    im.EndChild();
end

return M;
