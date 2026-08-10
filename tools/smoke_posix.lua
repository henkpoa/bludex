--[[
    tools/smoke_posix.lua -- run the smoke suite on a POSIX Lua.

    The addon's require paths use Windows separators ('bludex\lib\...'),
    which POSIX filesystems treat as literal filename characters, so the
    stock package.path lookup never finds the files. This shim adds a
    searcher that translates the separators and hands the chunk the same
    module name the addon expects (ROOT extraction reads it from `...`).

    Run from the directory CONTAINING the repo checkout (which must be
    named 'bludex', as in an Ashita addons directory):

        lua bludex/tools/smoke_posix.lua
]]--

package.path = './?.lua;' .. package.path;

local searchers = package.searchers or package.loaders;
table.insert(searchers, 2, function(name)
    local path = './' .. name:gsub('\\', '/') .. '.lua';
    local f = io.open(path, 'r');
    if f == nil then return nil; end
    f:close();
    local chunk, err = loadfile(path);
    if chunk == nil then return nil, err; end
    return chunk, path;
end);

dofile('bludex/tools/smoke.lua');
