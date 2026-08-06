--[[
    bludex/ui/settingsui.lua -- the Settings tab.

    Mostly this is the POINT BUDGET, because that number is the one thing
    Bludex cannot simply read. The whole story, so the panel can be honest
    about which half is known and which is still being waited on:

      total = base(level)  +  Assimilation merits  +  learning bonus

    base           the server's rule, exact, known for every level
                   (setmodel.baseCapAtLevel, from blueutils.cpp)
      + merits     arrives BY ITSELF on packet 0x063 at login / zoning /
                   any merit change -- already multiplied, and the server
                   applies it only at level 75+
      + bonus      CatsEyeXI's custom award for spells learned. Nothing
                   reports it. It is MEASURED, the one moment the game
                   client recomputes its own total -- which happens when
                   the native Set Spells menu is opened, and at no other
                   time. Below 75 the measurement needs nothing else;
                   at 75 it needs the merit figure first, to subtract.

    Either number can be typed in here when the automatic route is not
    available (the dlac flavor cannot read packets) or looks wrong.
]]--

local M = {};

local ROOT = (...):sub(1, -#('ui\\settingsui') - 1);
local kit  = require(ROOT .. 'ui\\kit');
local sets = require(ROOT .. 'lib\\setmodel');

local AUTO = -1;   -- the "no manual override" sentinel in config

local function row(im, label)
    kit.ctext(im, kit.COL.head, label);
end

-- an int field with an Auto button; returns the new value or nil for auto
local function intField(im, id, value, isAuto, width)
    local buf = { tostring(isAuto and '' or (value or '')) };
    local out, cleared = nil, false;
    if kit.isFn(im, 'PushItemWidth') then im.PushItemWidth(width or 70); end
    if kit.isFn(im, 'InputText') then
        local ok = pcall(im.InputText, id, buf, 8);
        if ok and buf[1] ~= nil then
            local n = tonumber(buf[1]);
            if buf[1] == '' then cleared = true; else out = n; end
        end
    end
    if kit.isFn(im, 'PopItemWidth') then im.PopItemWidth(); end
    return out, cleared;
end

function M.render(ctx)
    local im, cfg, blu = ctx.im, ctx.cfg, ctx.blu;
    local lvl  = blu.effectiveLevel();
    local base = sets.baseCapAtLevel(lvl or 0);
    local total, src = blu.budget();

    row(im, 'Set-point budget');
    kit.ctext(im, kit.COL.dim,
        'The game client works your point total out for itself and only ever\n'
        .. 'recomputes it when you open the native Set Spells menu -- so after a\n'
        .. 'level sync its number describes the level you left. Bludex works the\n'
        .. 'total out too, from the three parts below, and shows its own answer\n'
        .. 'whenever the client\'s has gone out of date.');
    if kit.isFn(im, 'Separator') then im.Separator(); end

    -- what we are showing right now, and where it came from
    kit.ctext(im, kit.COL.head, ('Now: %s points at Lv.%s'):format(
        total and tostring(total) or '--', tostring(lvl or '?')));
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    if src == 'live' then
        kit.ctext(im, kit.COL.ok, '   (from the game client)');
    elseif src == 'model' then
        kit.ctext(im, kit.COL.warn, '   (computed by Bludex -- the client\'s number is out of date)');
    else
        kit.ctext(im, kit.COL.err, '   (not known yet)');
    end

    -- 1. base
    kit.ctext(im, kit.COL.dim, ('base for Lv.%s: %d   -- the server\'s rule, always known'):format(
        tostring(lvl or '?'), base));

    -- 2. merits
    local meritAuto  = (cfg.capMerits or 0);
    local meritManual = (cfg.capMeritsManual or AUTO);
    local meritUsed  = blu.meritPts;
    kit.ctext(im, kit.COL.head, 'Level 75 bonus (merits + spells learned)');
    kit.ctext(im, kit.COL.dim,
        'Read automatically -- the server sends it on packet 0x063 at login, on\n'
        .. 'every zone, and whenever you change a merit. Nothing is requested; it\n'
        .. 'simply arrives. On CatsEyeXI this one number carries EVERYTHING above\n'
        .. 'the base rule -- your Assimilation merits and the spells-learned bonus,\n'
        .. 'already added together -- so at level 75 no menu visit is needed at all.\n'
        .. 'The server applies it only at 75 and above: under a sync it does not\n'
        .. 'count, which is why the figure below is measured separately.');
    if meritUsed ~= nil then
        kit.ctext(im, kit.COL.ok, ('   read from the server: %d points%s'):format(
            meritUsed, (meritManual ~= AUTO) and ' (overridden below)' or ''));
    else
        kit.ctext(im, kit.COL.warn,
            '   not seen yet -- zone once, or type it in below.\n'
            .. '   (the dlac flavor cannot read packets: type it there)');
    end
    local mv, mCleared = intField(im, '##bdxmerits', meritManual ~= AUTO and meritManual or meritAuto,
        meritManual == AUTO, 70);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.ctext(im, kit.COL.dim, 'points (blank = automatic)');
    if mCleared and meritManual ~= AUTO then
        cfg.capMeritsManual = AUTO;
        if ctx.save then ctx.save(); end
    elseif mv ~= nil and mv >= 0 and mv ~= meritManual then
        cfg.capMeritsManual = mv;
        blu.meritPts = mv;
        blu.capExtra.at75 = mv;    -- this figure IS the Lv75 gap
        if ctx.save then ctx.save(); end
    end

    -- 3. the learning bonus
    kit.ctext(im, kit.COL.head, 'Under-sync bonus (spells learned only)');
    kit.ctext(im, kit.COL.dim,
        'Merits stop counting under a level sync, so the figure above does not\n'
        .. 'apply there -- only the spells-learned part survives, and nothing\n'
        .. 'reports it. Bludex MEASURES it: while synced BELOW 75, open the native\n'
        .. 'Set Spells menu once. The client recomputes its total for that level,\n'
        .. 'Bludex catches the change and subtracts the base rule. It re-measures\n'
        .. 'on every later visit, so learning new spells keeps it current.\n'
        .. 'The two figures are never added together -- each is the whole bonus\n'
        .. 'for its own side of level 75.');
    local bonus = blu.capExtra.sub;
    if bonus ~= nil then
        kit.ctext(im, kit.COL.ok, ('   measured: %d points'):format(bonus));
    elseif blu.capExtra.at75 ~= nil then
        kit.ctext(im, kit.COL.warn, ('   only a Lv.75 total is known (%d over base).\n'
            .. '   Supply the merits above, or open the menu once while synced,\n'
            .. '   and Bludex can split it.'):format(blu.capExtra.at75));
    else
        kit.ctext(im, kit.COL.warn, '   not measured yet -- open the native Set Spells menu once.');
    end
    local bonusManual = (cfg.capBonusManual or AUTO);
    local bv, bCleared = intField(im, '##bdxbonus', bonusManual ~= AUTO and bonusManual or (bonus or 0),
        bonusManual == AUTO, 70);
    if kit.isFn(im, 'SameLine') then im.SameLine(); end
    kit.ctext(im, kit.COL.dim, 'points (blank = measured automatically)');
    if bCleared and bonusManual ~= AUTO then
        cfg.capBonusManual = AUTO;
        if ctx.save then ctx.save(); end
    elseif bv ~= nil and bv >= 0 and bv ~= bonusManual then
        cfg.capBonusManual = bv;
        blu.capExtra.sub = bv;
        if ctx.save then ctx.save(); end
    end

    if kit.isFn(im, 'Separator') then im.Separator(); end
    local usingGap = ((lvl or 0) >= 75) and blu.capExtra.at75 or blu.capExtra.sub;
    kit.ctext(im, kit.COL.dim, ('check: %d base + %s bonus for Lv.%s = %s'):format(
        base, tostring(usingGap or '?'), tostring(lvl or '?'),
        tostring(blu.expectedCap(lvl) or '?')));
    local mb = blu.meritBonus();
    if mb ~= nil then
        kit.ctext(im, kit.COL.dim, ('your Assimilation merits work out at %d points '
            .. '(the difference between the two figures)'):format(mb));
    end
end

return M;
