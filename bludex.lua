--[[
    Bludex -- the Blue Mage codex + set planner for Ashita v4 on CatsEyeXI.
    https://github.com/henkpoa/bludex

    GPL-3.0. In-game set application is ported from `blusets` (atom0s /
    Ashita Development Team); learned-spell detection follows `blucheck`.
]]--

addon.name    = 'bludex';
addon.author  = 'henkpoa';
addon.version = '0.1.0';
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

local function saveSettings()
    settings.save();
end

host.init({
    im = imgui, book = book, blu = blu, sets = sets,
    cfg = cfg, save = saveSettings,
});
blu.delay = cfg.applyDelay or 1.1;
blu.mode  = cfg.applyMode or 'safe';

settings.register('settings', 'bdx_settings_update', function(s)
    if s ~= nil then
        cfg = s;
        host.deps.cfg = cfg;
        blu.delay = cfg.applyDelay or 1.1;
        blu.mode  = cfg.applyMode or 'safe';
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

    if #args == 1 then
        host.toggle();
        return;
    end

    if args[2]:any('help') then
        msg('/bludex (or /bdx) - toggle the window.');
        msg('/bludex list - list saved sets.');
        msg('/bludex import [name] - import blusets spell lists as saved sets.');
        msg('/bludex apply <name> - apply a saved set (only the changed slots).');
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
            local n = 0;
            for i = 1, 20 do if (entry.ids[i] or 0) ~= 0 then n = n + 1; end end
            msg(('  %s (%d spells)'):format(entry.name, n));
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
        if blu.applyDiff(entry.ids, book) then
            local snap = {};
            for i = 1, 20 do snap[i] = entry.ids[i] or 0; end
            cfg.lastApplied = { ids = snap };
            saveSettings();
        end
        return;
    end

    msg('Unknown command - /bludex help.');
end);

ashita.events.register('d3d_present', 'bdx_present_cb', function()
    host.render();
end);

ashita.events.register('unload', 'bdx_unload_cb', function()
    settings.save();
end);
