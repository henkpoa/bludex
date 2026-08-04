# Bludex as a library — the two doors

One codebase, two first-class distributions:

- **Standalone addon** — this repo as `addons/bludex/`, entry `bludex.lua`.
  For players who do not run dlac.
- **dlac Job helper module** — vendored into dlac at
  `jobhelpers/blu/bludex/` per dlac's module framework
  (`docs/reference/jobhelper-authoring-guide.md`, `api = 2`). dlac users get
  the BLU helper with **no separate bludex install**.

**Do not run both flavors at once** — each is a full brain (level-change
watch, 0x061 refresh, packet sends); two active copies would both answer the
same events.

## Why a plain copy works: relocatable requires

Every module derives its require base from its own module name (Lua passes
it as `...`):

```lua
local ROOT = (...):sub(1, -#('ui\\host') - 1);
-- 'bludex\ui\host'                      -> ROOT = 'bludex\'
-- 'dlac\jobhelpers\blu\bludex\ui\host'  -> ROOT = 'dlac\jobhelpers\blu\bludex\'
local kit = require(ROOT .. 'ui\\kit');
```

`ui/filetex.lua` builds icon paths from the same ROOT, so the vendored copy
uses its own `icons/`. **Nothing is rewritten when vendoring** — the sync is
a pure copy. This is the same rename-safety `S.sibling` gives first-party
dlac modules, derived from the same authority (the loaded module name).

## The CI sync

`.github/workflows/sync-dlac.yml`: every push to bludex `main` copies

```
lib/ ui/ data/ icons/          the relocatable library
dlacmodule/init.lua            -> jobhelpers/blu/bludex/init.lua  (the contract)
dlacmodule/README.md           -> jobhelpers/blu/bludex/README.md (the approval doc)
```

into `henkpoa/dlac` on its **dev** branch (the dev→main law holds in both
repos), plus a `VENDORED.md` marker. One-time setup: a fine-grained PAT with
*Contents: read/write* on `henkpoa/dlac`, stored as the **`DLAC_SYNC_TOKEN`**
secret in `henkpoa/bludex`.

## The adapter (`dlacmodule/init.lua`) — how the contract is satisfied

| Guide requirement | How it is met |
|---|---|
| `api = 2`, `label`, `jobs`, `panel` | Contract table returned by `init.lua`; `jobs = { 'BLU' }`. |
| Panels may not open windows | `host.renderEmbedded()` renders body-only. Spell Info floats through the **sanctioned `window` hook** (ADR 0028 amendment 2026-08-04): `host.renderDetailFloat()` draws it at dlac's one float site, so it survives the main window closing. On an older dlac that ignores the hook, the codex detects the surface never ran and falls back to an **in-panel detail pane** by itself. |
| Settings: framework store, scalars only | The adapter's codec encodes saved sets (`name\tid,csv` lines) and the last-applied snapshot (`id` csv) as strings; the library keeps mutating its usual `cfg` table and `save()` re-encodes. Declared keys/defaults on the contract. |
| Act whether or not the Panel is open | `S.combat.subscribe` beat → `host.tick()` (level-change watch + armed Restore), gated `S.me.acting().active == true` — an unreadable world is not permission. |
| The host's imgui handle, never your own | `panel(ctx)` assigns `ctx.imgui` into the host deps each render. |
| Naming law | The rule is called **Restore** (condition-named), never 'Auto-…'. All strings PROPOSED for maintainer sign-off. |
| One unit of approval, legible from the folder | `dlacmodule/README.md` documents the full envelope: what is read, the two packet kinds sent and when, what is written. |
| Containment | Library load is pcall'd; a failed load leaves an inert module whose Panel says so. Every imgui call inside the library is guarded (the kit's laws are dlac's own, blue-shifted). |

Still manual on the dlac side (deliberately not synced): adding the module's
files to the test rosters (`JOBHELP` in `tests/run_tests.lua`) if wanted,
string sign-off, and the server-approval conversation itself.

## The generic embedding surface (any other host)

`ui/host.lua` exposes: `init(deps)` (`{ im, book, blu, sets, cfg, save }`),
`tick()` (call every frame), `render()` (standalone floating window),
`renderEmbedded()` (body-only, own theme pushes, `embedded` ctx),
`toggle()`, `isOpen()`. Settings defaults come from `lib/config.lua` so
flavors cannot drift. Chat is prefixed `bludex` everywhere.

## License

GPL-3.0 (inherited via the blusets port); the sync carries `LICENSE` into
the module folder. Saved sets do not migrate between flavors automatically
(different stores); rebuild or re-save them once when switching.
