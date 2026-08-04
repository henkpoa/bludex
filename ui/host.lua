--[[
    bludex/ui/host.lua -- the window shell: blue theme, header with the live
    point budget, the tab row (lit/unlit buttons -- BeginTabBar is not
    field-proven in this install), and per-frame ctx wiring for the tabs.

    Frame discipline: each tab renders inside pcall; a tab error draws as text
    instead of tearing the frame. Style pushes pop on every path.
]]--

local kit      = require('bludex\\ui\\kit');
local filetex  = require('bludex\\ui\\filetex');
local spellsui = require('bludex\\ui\\spellsui');
local setsui   = require('bludex\\ui\\setsui');
local traitsui = require('bludex\\ui\\traitsui');

local M = {};

M.state = nil;

local function freshState(sets)
    return {
        open = { false, },
        tab = 'Codex',
        selectedId = nil,
        editingSet = sets.new('Set 1'),
        activeSet = nil,
        addNote = nil,
        applyNote = nil,
        nameBuf = { '' },
        addBuf = { '' },
        openCat = {},
        filters = {
            text = { '' },
            category = {}, element = {}, spellType = {}, trait = {}, learned = {},
        },
    };
end

function M.init(deps)
    M.deps = deps;                      -- { im, book, blu, sets, cfg, save }
    M.state = freshState(deps.sets);
end

function M.toggle()
    if M.state then M.state.open[1] = not M.state.open[1]; end
end

function M.isOpen()
    return M.state and M.state.open[1] or false;
end

local function budgetMax(deps)
    local max = deps.blu.points();
    if max then return max; end
    if deps.cfg.budgetOverride and deps.cfg.budgetOverride > 0 then
        return deps.cfg.budgetOverride;
    end
    return nil;
end

local TABS = { 'Codex', 'Sets', 'Traits' };

function M.render()
    local st = M.state;
    if st == nil or not st.open[1] then return; end
    local deps = M.deps;
    local im = deps.im;
    if not kit.isFn(im, 'Begin') or not kit.isFn(im, 'End') then return; end

    -- theme: dark navy window, blue title
    local pushed = 0;
    if kit.isFn(im, 'PushStyleColor') and kit.isFn(im, 'PopStyleColor') then
        im.PushStyleColor(2,  { 0.055, 0.075, 0.125, 0.97 });  -- WindowBg
        im.PushStyleColor(11, { 0.10, 0.18, 0.34, 1.00 });     -- TitleBgActive
        im.PushStyleColor(10, { 0.07, 0.11, 0.20, 1.00 });     -- TitleBg
        im.PushStyleColor(3,  { 0.06, 0.09, 0.15, 0.97 });     -- ChildBg
        pushed = 4;
    end
    if kit.isFn(im, 'SetNextWindowSizeConstraints') then
        -- 920 wide fits the measured filter row; below that the Reset button clips
        pcall(im.SetNextWindowSizeConstraints, { 920, 520 }, { 4096, 4096 });
    end

    local visible = false;
    local ok = pcall(function()
        visible = im.Begin('Bludex##bdxmain', st.open);
    end);
    if ok and visible then
        -- header: logo + budget
        local logo = filetex.ui('logo-64');
        if logo ~= nil and kit.isFn(im, 'Image') then
            pcall(im.Image, logo, { 22, 22 });
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
        end
        kit.ctext(im, kit.COL.head, 'BLUDEX');
        if kit.isFn(im, 'SameLine') then im.SameLine(); end
        local max, spent = deps.blu.points();
        if max then
            kit.ctext(im, kit.COL.accent,
                ('   Blue Magic Points: %d / %d'):format(spent or 0, max));
            kit.tip(im, 'Live from the game client -\nCatsEyeXI merit and learning bonuses included.');
        elseif deps.blu.onBlu() then
            kit.ctext(im, kit.COL.dim, '   points: reading...');
        else
            kit.ctext(im, kit.COL.dim, '   (not on BLU - budget shown when you are)');
        end

        -- tab row
        local w = kit.measure(im, TABS, 90);
        for _, t in ipairs(TABS) do
            if kit.litButton(im, t, st.tab == t, w, 26) then st.tab = t; end
            if kit.isFn(im, 'SameLine') then im.SameLine(); end
        end
        if kit.isFn(im, 'NewLine') then im.NewLine(); end
        if kit.isFn(im, 'Separator') then im.Separator(); end

        -- per-frame ctx for the tabs
        local ctx = {
            im = im, book = deps.book, blu = deps.blu, sets = deps.sets,
            cfg = deps.cfg, save = deps.save, state = st,
            budgetMax = function() return budgetMax(deps); end,
        };
        local tabfn = (st.tab == 'Sets' and setsui.render)
            or (st.tab == 'Traits' and traitsui.render)
            or spellsui.render;
        local tok, terr = pcall(tabfn, ctx);
        if not tok then
            kit.ctext(im, kit.COL.err, 'tab error: ' .. tostring(terr));
        end
    end
    if ok then im.End(); end
    if pushed > 0 then im.PopStyleColor(pushed); end
end

return M;
