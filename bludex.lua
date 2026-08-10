--[[
    Bludex -- the Blue Mage codex + set planner for Ashita v4 on CatsEyeXI.
    https://github.com/henkpoa/bludex

    GPL-3.0. In-game set application is ported from `blusets` (atom0s /
    Ashita Development Team); learned-spell detection follows `blucheck`.
]]--

addon.name    = 'bludex';
addon.author  = 'Mindie';
addon.version = '1.1.0';
addon.desc    = 'Blue Magic codex + visual set planner (CatsEyeXI, level-75 cap).';
addon.link    = 'https://github.com/henkpoa/bludex';

require('common');
local chat     = require('chat');
local settings = require('settings');
local imgui    = require('imgui');

-- The dlac bootstrap: append <install>/addons/?.lua so require('bludex\\X')
-- resolves to addons/bludex/X.lua for every module in this addon's state.
package.path = package.path .. ';' .. AshitaCore:GetInstallPath() .. 'addons\\?.lua';

local book   = require('bludex\\lib\\spellbook');
local blu    = require('bludex\\lib\\blu');
local sets   = require('bludex\\lib\\setmodel');
local config = require('bludex\\lib\\config');
local blusetsimport = require('bludex\\lib\\blusetsimport');
local host   = require('bludex\\ui\\host');

local cfg = settings.load(config.defaults());

-- Where the settings library routes a load or save is decided by its own
-- login state: the character's folder while logged in, a shared 'defaults'
-- profile otherwise (title screen, character select). Nothing character-
-- owned may be read or written through the defaults profile -- a save made
-- there LOOKS saved and is thrown away at the next login -- so the save,
-- the commands and the render all gate on this.
local function loggedIn()
    return settings.logged_in == true;
end

-- The character the settings library is currently serving, as its folder
-- tag; nil while logged off. The host compares tags to tell a relog (keep
-- the working state) from a character switch (drop it).
local function charTag()
    if loggedIn() and (settings.server_id or 0) ~= 0
        and type(settings.name) == 'string' and #settings.name > 0 then
        return ('%s_%d'):format(settings.name, settings.server_id);
    end
    return nil;
end

local function saveSettings()
    if not loggedIn() then return; end
    settings.save();
end

host.init({
    im = imgui, book = book, blu = blu, sets = sets,
    cfg = cfg, save = saveSettings,
});
host.noteChar(charTag());
blu.delay = cfg.applyDelay or 1.1;
blu.mode  = cfg.applyMode or 'safe';

-- The library swaps the whole settings table at every login and logout
-- (and so on any character switch). Everything holding the old table must
-- rebind, and per-character state must not cross characters -- the host
-- owns that logic (host.onSettingsSwap).
settings.register('settings', 'bdx_settings_update', function(s)
    if s ~= nil then
        cfg = s;
        blu.delay = cfg.applyDelay or 1.1;
        blu.mode  = cfg.applyMode or 'safe';
        host.onSettingsSwap(cfg, charTag());
    end
end);

local function msg(s)
    print(chat.header(addon.name):append(chat.message(s)));
end

local function findSet(name)
    local want = book.norm(name);
    for _, entry in ipairs(cfg.sets) do
        if book.norm(entry.name) == want then return entry; end
    end
    return nil;
end

ashita.events.register('command', 'bdx_command_cb', function(e)
    local args = e.command:args();
    if #args == 0 or not args[1]:any('/bludex', '/bdx') then return; end
    e.blocked = true;

    if not loggedIn() then
        msg('Asleep while no character is logged in: settings are per character, so nothing can be shown -- and a save made now would be lost at login.');
        return;
    end

    if #args == 1 then
        host.toggle();
        return;
    end

    if args[2]:any('help') then
        msg('/bludex (or /bdx) - toggle the window.');
        msg('/bludex list - list saved sets.');
        msg('/bludex import [name] - import blusets spell lists as saved sets.');
        msg('/bludex apply <name> - apply a saved set (its plan for your current level).');
        msg('/bludex replan - apply the editing set\'s plan for your current level.');
        msg('/bludex reset - unset every spell.');
        msg('/bludex refresh - re-request job data (wakes a stuck points read).');
        msg('/bludex delay <0.2-5> - seconds between set-spell packets.');
        msg('/bludex mode safe|fast - client-paced sends vs injected packets.');
        msg('/bludex debug - signature / points / live-set diagnostics.');
        return;
    end

    if args[2]:any('debug') then
        local st = blu.sigStatus();
        msg(('signatures: offset=%s points=%s equipex=%s'):format(
            st.offset and 'ok' or 'MISSING',
            st.points and 'ok' or 'MISSING',
            st.equipex and 'ok' or 'MISSING'));
        msg(('job: BLU main=%s sub=%s'):format(
            blu.isBluMain() and 'yes' or 'no', blu.isBluSub() and 'yes' or 'no'));
        local ok, pmax, pspent = blu.pointsRaw();
        if ok then
            msg(('points raw: max=%s spent=%s%s'):format(tostring(pmax), tostring(pspent),
                (pmax == 0) and '  <- struct is zero; open the native Set Spells menu once' or ''));
        else
            msg('points raw: read failed (signature missing or pointer chain dead)');
        end
        local bmax, bsrc = blu.budget();
        msg(('budget: %s from %s (client value computed at Lv.%s)'):format(
            tostring(bmax), tostring(bsrc), tostring(blu.capLevel())));
        msg(('budget parts: learned bonus=%s  Assimilation=%s  (server cross-check=%s)'):format(
            tostring(blu.learnedBonus or 'not known'),
            tostring(blu.meritPts or 'not known'),
            tostring(blu.wireTotal or 'none seen')));
        local live = blu.currentSet();
        if #live == 20 then
            local n = 0;
            for i = 1, 20 do if live[i] ~= 0 then n = n + 1; end end
            msg(('live set: readable, %d/20 slots filled'):format(n));
        else
            msg('live set: NOT readable');
        end
        msg(('mode=%s delay=%.2f applying=%s'):format(blu.mode, blu.delay, tostring(blu.applying)));
        return;
    end

    if args[2]:any('delay') and #args >= 3 then
        local d = tonumber(args[3]);
        if d == nil or d < 0.2 or d > 5 then
            msg('Usage: /bludex delay <seconds, 0.2-5>. Safe mode never runs below 1.0 - the client itself paces it; use fast mode to go lower.');
            return;
        end
        cfg.applyDelay = d;
        blu.delay = d;
        saveSettings();
        msg(('Apply delay set to %.2fs.'):format(d));
        return;
    end

    if args[2]:any('mode') and #args >= 3 then
        local m = args[3]:lower();
        if m ~= 'safe' and m ~= 'fast' then
            msg('Usage: /bludex mode safe|fast.');
            return;
        end
        cfg.applyMode = m;
        blu.mode = m;
        saveSettings();
        msg(('Apply mode: %s.'):format(m));
        if m == 'fast' then
            msg('fast = hand-injected 0x102 packets; the delay is honored below 1s. If spells go missing after an apply, the server dropped packets - go back to safe.');
        end
        return;
    end

    if args[2]:any('refresh') then
        if blu.requestJobData() then
            msg('Requested a job-data refresh from the server (packet 0x061) - the points header should fill within a second.');
        else
            msg('Could not send the refresh request.');
        end
        if blu.capStale() then
            msg(('The point total is stale (computed at Lv.%s): open the native Set Spells menu once. The cap is computed by the game client and never sent over the network, so no refresh can fetch it.'):format(
                tostring(blu.capLevel())));
        end
        return;
    end

    if args[2]:any('reset') then
        if blu.resetAll() then
            msg('Reset queued - all set spells unset.');
        else
            msg('Cannot reset: BLU is not your main or sub job (or signatures failed).');
        end
        return;
    end

    if args[2]:any('list') then
        if #cfg.sets == 0 then
            msg('No saved sets yet - build one in the Sets tab.');
            return;
        end
        for _, entry in ipairs(cfg.sets) do
            local kind = sets.kindOf(entry);
            local n = 0;
            for i = 1, 20 do if (entry.ids[i] or 0) ~= 0 then n = n + 1; end end
            if kind == 'levels' then
                local parts = { ('%d spells'):format(n) };
                for _, lvl in ipairs(sets.groupLevels(entry)) do
                    parts[#parts + 1] = ('Lv.%d: %d'):format(
                        lvl, sets.countIds(sets.groupIds(entry, lvl)));
                end
                msg(('  %s (%s - %s)'):format(entry.name, sets.KIND_LABELS[kind],
                    table.concat(parts, ', ')));
            else
                msg(('  %s (%s - %d spells)'):format(entry.name,
                    sets.KIND_LABELS[kind], n));
            end
        end
        return;
    end

    if args[2]:any('import') then
        local res = blusetsimport.importAll(cfg, book,
            #args >= 3 and table.concat(args, ' ', 3) or nil);
        if #res.imported > 0 then saveSettings(); end
        msg(blusetsimport.describe(res));
        for _, name in ipairs(res.imported) do msg(('  imported: %s'):format(name)); end
        for _, name in ipairs(res.skipped) do
            msg(('  skipped: %s - a bludex set by that name exists.'):format(name));
        end
        for _, u in ipairs(res.unknown) do msg(('  unknown spell - %s'):format(u)); end
        return;
    end

    if args[2]:any('apply') and #args >= 3 then
        local entry = findSet(table.concat(args, ' ', 3));
        if entry == nil then
            msg('No saved set by that name. /bludex list shows them.');
            return;
        end
        -- the same hard block the UI Apply wears (plan 2.6) -- the command
        -- must not be the back door around the band sweep
        local viol = sets.enforcedViolations(entry, book, function(L)
            local c = blu.expectedCap(L);
            if c ~= nil then return c; end
            if L >= 75 and (cfg.budgetOverride or 0) > 0 then return cfg.budgetOverride; end
            return nil;
        end);
        if #viol > 0 then
            msg(('Cannot apply %s: %s.'):format(entry.name, sets.bandText(viol[1])));
            return;
        end
        -- the timeline resolved for the level we stand at, like the button
        local lvl = blu.effectiveLevel() or 75;
        local ids = sets.resolveAtLevel(entry, lvl, book);
        if blu.applyDiff(ids, book) then
            local snap = {};
            for i = 1, 20 do snap[i] = ids[i] or 0; end
            cfg.lastApplied = { ids = snap, level = lvl };
            cfg.lastAppliedSet = entry.name;   -- the watcher follows this set
            saveSettings();
        end
        return;
    end

    if args[2]:any('replan') then
        host.replanNow();
        return;
    end

    -- UNDOCUMENTED, deliberately absent from /bludex help: wipe everything
    -- Bludex has worked out about this character's point budget so it
    -- re-derives from scratch. For when a character's numbers are wrong and
    -- you would rather watch them be relearned than reason about them.
    if args[2]:any('forget') then
        local had = blu.forgetBudget();
        cfg.capLearnedBonus, cfg.capMeritPoints = -1, -1;
        saveSettings();
        msg(('Forgot the point budget. Was: learned bonus=%s, Assimilation=%s (%s merit(s) at %s each%s), server total=%s.'):format(
            tostring(had.bonus or 'unknown'), tostring(had.merits or 'unknown'),
            tostring(had.count or '?'), tostring(had.rate),
            had.proven and ', measured' or ', assumed',
            tostring(had.wire or 'none seen')));
        msg('Zone once: that re-reads your merits and the server total. The learned bonus settles on the next level sync, or on your next Magic -> Blue Magic -> Set.');
        return;
    end

    msg('Unknown command - /bludex help.');
end);

-- The merit half of the point budget, read live off the wire. 0x063 MISCDATA
-- type 0x02 carries the server's own Assimilation total (already multiplied),
-- and it arrives by itself -- at login, on zoning, and whenever merits change.
-- Nothing is ever sent to ask for it. Standalone only: dlac's module contract
-- has no packet hook, and the library falls back to measuring without it.
-- Both budget packets arrive by themselves -- nothing is ever sent to ask.
--   0x08C  the merit ALLOCATIONS, full list at every zone-in: Assimilation
--   0x063  learned bonus + merits summed, a cross-check that completes
--          whichever half is already known
-- Standalone only; dlac's api=2 module contract has no packet hook.
ashita.events.register('packet_in', 'bdx_packet_cb', function(e)
    local moved = false;
    if e.id == 0x08C then
        moved = blu.setMeritCount(blu.parseMeritCount(e.data));
    elseif e.id == 0x063 then
        local n = blu.parseMeritBonus(e.data);
        moved = (n ~= nil) and blu.setWireTotal(n) or false;
    else
        return;
    end
    if moved then
        cfg.capLearnedBonus = blu.learnedBonus or -1;
        cfg.capMeritPoints  = blu.meritPts or -1;
        saveSettings();
    end
end);

ashita.events.register('d3d_present', 'bdx_present_cb', function()
    -- Logged off, the settings library serves the shared defaults profile:
    -- the window would show -- and save into -- data belonging to no
    -- character (with the Save button lit green against the empty defaults,
    -- inviting exactly the click that loses work). It sleeps instead; the
    -- working state is kept for the character coming back.
    if not loggedIn() then return; end
    host.render();
end);

ashita.events.register('unload', 'bdx_unload_cb', function()
    saveSettings();
end);
