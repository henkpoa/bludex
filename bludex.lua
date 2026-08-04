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

local book = require('bludex\\lib\\spellbook');
local blu  = require('bludex\\lib\\blu');
local sets = require('bludex\\lib\\setmodel');
local host = require('bludex\\ui\\host');

local defaults = T{
    sets = T{ },              -- { { name = s, ids = {20 real ids} }, ... }
    budgetOverride = 0,       -- shown when the live budget is unavailable
    applyDelay = 1.1,         -- seconds between set-spell packets
};

local cfg = settings.load(defaults);

local function saveSettings()
    settings.save();
end

host.init({
    im = imgui, book = book, blu = blu, sets = sets,
    cfg = cfg, save = saveSettings,
});
blu.delay = cfg.applyDelay or 1.1;

settings.register('settings', 'bdx_settings_update', function(s)
    if s ~= nil then
        cfg = s;
        host.deps.cfg = cfg;
        blu.delay = cfg.applyDelay or 1.1;
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
        msg('/bludex apply <name> - apply a saved set in game.');
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

    if args[2]:any('apply') and #args >= 3 then
        local entry = findSet(table.concat(args, ' ', 3));
        if entry == nil then
            msg('No saved set by that name. /bludex list shows them.');
            return;
        end
        blu.applySet(entry.ids);
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
