# Bludex as a library — embedding contract (dlac's BLU helper)

Bludex is one codebase with two doors:

- **Standalone addon** — this repo as `addons/bludex/`, entry `bludex.lua`.
  For people who do not run dlac.
- **Vendored library** — everything except `bludex.lua`/`tools/` copied into
  another addon (dlac) as `addons/dlac/bludexlib/`. dlac users get the BLU
  helper with **no separate bludex install**.

## Why a plain copy works: relocatable requires

Every module derives its require base from its own module name (Lua passes
it as `...`):

```lua
local ROOT = (...):sub(1, -#('ui\\host') - 1);
-- 'bludex\ui\host'          -> ROOT = 'bludex\'
-- 'dlac\bludexlib\ui\host'  -> ROOT = 'dlac\bludexlib\'
local kit = require(ROOT .. 'ui\\kit');
```

`ui/filetex.lua` builds icon paths from the same ROOT, so the vendored copy
uses its own `bludexlib/icons/`. **No paths are rewritten when vendoring** —
the sync is `cp -r lib ui data icons`.

## The CI sync

`.github/workflows/sync-dlac.yml`: every push to bludex `main` copies the
library into the dlac repo at `bludexlib/` and commits to dlac's **dev**
branch (the dev→main law holds in both repos).

One-time setup: create a fine-grained PAT with *Contents: read/write* on
`henkpoa/dlac`, save it as the **`DLAC_SYNC_TOKEN`** secret in
`henkpoa/bludex` → Settings → Secrets → Actions.

## What the embedding addon writes (once, ~40 lines)

```lua
-- dlac/bluhelper.lua (sketch; lives in the dlac repo, hand-written once)
local ok, host = pcall(require, 'dlac\\bludexlib\\ui\\host');
if not ok then return { available = false }; end   -- vendored copy missing
local M = { available = true };

function M.init(imgui, cfgSlice, save)
    -- cfgSlice: a table inside dlac's settings tree seeded from
    -- require('dlac\\bludexlib\\lib\\config').defaults()
    host.init({
        im   = imgui,
        book = require('dlac\\bludexlib\\lib\\spellbook'),
        blu  = require('dlac\\bludexlib\\lib\\blu'),
        sets = require('dlac\\bludexlib\\lib\\setmodel'),
        cfg  = cfgSlice,
        save = save,
    });
end

M.tick         = host.tick;            -- EVERY d3d_present frame, always
M.render       = host.renderEmbedded;  -- inside dlac's own window/panel
M.renderWindow = host.render;          -- or: the floating Bludex window
M.toggleWindow = host.toggle;          --     (pick one flavor)
return M;
```

Host API surface: `init(deps)`, `tick()`, `render()` (floating window,
checks its own open flag), `renderEmbedded()` (body only, no Begin/End,
pushes/pops its own panel theme), `toggle()`, `isOpen()`.

## Rules and caveats

- **Never hand-edit `bludexlib/`** in dlac — the sync overwrites it
  wholesale. Fix things here.
- **Do not run the standalone addon and the dlac helper at the same time**
  with `autoRestore` enabled in both: each would answer level changes with
  its own packets. One active BLU brain per client.
- Settings do not migrate between the two flavors automatically (Ashita
  settings are per-addon). Saved sets built in one live in that flavor's
  settings file.
- Chat output is prefixed `bludex` in both flavors (credit where due).
- License: GPL-3 (inherited via the blusets port) — the vendored copy
  carries the LICENSE file along; dlac must remain GPL-compatible.
- Commands (`/bludex ...`) are wired by `bludex.lua` and exist only in the
  standalone flavor; dlac wires its own (e.g. `/dlac blu ...`) if wanted.
