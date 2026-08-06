# Bludex — Session Handover

**Date:** 2026-08-04 (end of the full-day session; supersedes the night-build handover)
**Repo:** https://github.com/henkpoa/bludex — public, `main` + `dev` (all work on `dev`,
dev→main only on Henrik's explicit go; same law in dlac). Released at `4c91e41`+docs.
**State:** everything below is **FIELD-CONFIRMED on CatsEyeXI** unless marked otherwise.
`addon.version` is **1.0.1** — tagged `v1.0.1` on `main`. The point budget is
now MODELLED (`base(level) + learned bonus + Assimilation merits`, merits only
at 75) rather than read from the client's cache, which only recomputes when the
native Set Spells menu opens. See §7.

---

## 1. What exists (all field-proven today unless noted)

| Piece | State |
|---|---|
| Codex: icon+name list rows, 1-3 columns by width, filters + Sort (Name/Level/Type) + View densities (Big 64 / Medium 32 / Normal 24 / Compact no-icons), green = in set, dim = unlearned | Proven. Density + sort persisted (`codexDensity`; sort is session-state). |
| The row grammar (everywhere: codex, traits, sets-list): LEFT-click = Spell Info window, RIGHT-click = toggle in/out of set, hover = rich tooltip (centered 64 sprite, stats, trait + `set / next - for rank N` ladder progress) | Proven. Right-click uses `IsItemClicked(1)`. |
| Spell Info window: add/remove button at top (flips by membership), centered 320 sprite, wrapped long lines, learn-from hints | Proven. Draws from `host.renderBody` so traits/sets rows open it too. |
| Sets tab: saved sets (active set + which build remembered by NAME across loads), slot area as **Grid** (5x4 centered cells, empty = ring PNG) or **List** (codex rows + `(not active yet)` tags) — persisted `setsLayout`; live-state dimming; meters; quick add | Proven (the tree around it is new, below). |
| **A build per level band** (new 2026-08-06, NOT field-tested): eight rungs (1/11/…/71) under the selected set, each row `used / cap  filled / slots` + hover spell list; `>` marks your band; clicking one edits that build (its slot ceiling greys the grid, `canAdd` gates on its slots, its budget and its band's top spell level). Budget per rung = `blu.rungCap` (top rung planned at 75, where the merits land). **Nothing migrates**: the name row is the set's FLAT build and a set stays flat until a level is built. Storage `{name, ids, builds={{level, ids}}}`; the dlac codec writes the flat line byte-identically to before, level builds as extra `name<TAB>level<TAB>ids` lines | Suite-proven (`smoke: level builds`, `smoke: the Sets tab actions`), **field round owed**. |
| Header (all tabs): the band being edited (`Lv.71`), editing-build meters (`Set: x / max pts`, `Slots: n / that band's slots`), **Save / Apply / Revert** (green when they have work; slot-wise sorted-layout dirty compare), cast-lock countdown | Proven; the `Lv.` chip and the band-aware Slots max are new. |
| Apply engine (`lib/blu.lua`): **level-sorted slot layout** (slot 1 = lowest level; slot-wise diff, unsets first, adds ascend), skip-unlearned, full reset fallback, `/bludex reset` | Proven incl. the one-click re-sort of a patchwork set. Low-slot insertions shift the tail — inherent cost, documented in the commit. |
| Auto-restore on level change ("Level change: Restore / Manual", default Manual): adds-only via identity `planDiff` (NO reshuffle mid-sync), honest stuck-count report | Built + suite-proven; **field pass still thin** (mechanism proven via the job watcher, a real level-sync round-trip not yet observed). |
| Cast lock: every 0x102 restamps a 60s clock; header countdown + deferred-task chat line "Blue Magic is castable again." (fires window-closed too, generation-checked) | Countdown + announcement field-confirmed. **60s is retail-assumed — calibrate against CEXI once** (`M.castLock`, one number). |
| Points/live-set reads: blusets signatures; 0x061 self-heal (auto-nudge ≤3x10s + on window open + on job/level change; `/bludex refresh`) | Proven, including the original stale-struct regression and recovery. |
| Fast mode (`/bludex mode fast`, injected 0x102, delay to 0.2s) | Field verdict: **not worth it on CEXI — safe stays default.** Kept for experiments. |
| Learned gate: unlearned spells cannot be ADDED anywhere (`canAdd`); removal never gated | Proven. |
| Commands: `/bludex` `/bdx`, `list`, `apply <name> [level]`, `reset`, `refresh`, `delay <0.2-5>`, `mode safe|fast`, `debug` | Proven (debug was the regression workhorse). `apply` without a level picks the build for the level you are at — new, untested in the field. |

## 2. The two flavors + the pipeline (all field-proven end to end)

- **Standalone addon** = this repo at `addons/bludex/`.
- **dlac Job helper** = the library VENDORED at `dlac/jobhelpers/blu/bludex/` (api=2
  module; `dlacmodule/init.lua` + `README.md` here are the adapter + approval doc).
  The Panel is a **launcher**; the whole window rides dlac's `window` float hook
  (survives dlac's main box closing); `open` hook serves the quick-menu cascade.
  Settings live in dlac's scalar store via the adapter's codec (sets are encoded
  strings). **Do not run both flavors at once** (one BLU brain per client).
- **Pipeline:** commit dev → Henrik blesses bludex dev→main → `.github/workflows/
  sync-dlac.yml` (secret `DLAC_SYNC_TOKEN`, in place) copies lib/ui/data/icons +
  adapter into dlac dev → Henrik blesses dlac dev→main. Ran green all day (11-20s).
- **Dev loop:** `python bludex/tools/vendor_local.py` + `/addon reload dlac`. After a
  release, if dlac `git pull` refuses over the vendor: `git checkout -- jobhelpers/blu/bludex`
  then pull.
- dlac gained today (its own repo): the module `window`/`open` contract hooks + float
  draw site, the Job-helpers quick-menu cascade with the per-helper **Sub job** switch,
  and `liveJobs()` (memory-manager job reads — gData is absent in the addon state and
  degraded invisibly everywhere until the cascade exposed it).

## 3. Laws learned today (beyond the night build's)

1. **`gData` does not exist in dlac's addon state** — permissive-unknown guards hid it.
   Job reads go through AshitaCore's memory manager (`JOB_ABBR`, BLU=16).
2. **`SameLine` anchors to the PREVIOUS item's line** — a cursor-Y-offset name staggered
   multi-column lists 22px; columns must re-anchor to a captured row-top Y.
3. **`x and nil or false` stores false** — the and/or trap; explicit branches for
   clear-vs-set (caught by the JH19 roundtrip test before the field).
4. **The apply layout IS the deliverable** — identity diff left the game's list a
   patchwork; the sorted slot-wise diff costs shifts but the list reads right, and
   Apply-dirty must compare the same thing Apply sends.
5. **Deferred chat via `ashita.tasks.once` + generation counter** — UI-poll-driven
   announcements miss when the window is closed or the host tick is gated.
6. **Panels may not open windows** (dlac): containment is scoped to the Panel; floats
   need the one draw site — hence the `window` hook (ADR 0028 amendment, the why is in
   the authoring guide §2.5).

## 4. Open items

1. **Calibrate `castLock`** against CEXI (apply, wait out the timer, cast — adjust the
   one number in `lib/blu.lua` if 60s is wrong).
2. **Field-test the level-change Restore** with a real level sync (arm it on the Sets tab).
3. ~~Version bump + release notes~~ — done: approved, `1.0.0`, released `v1.0.0`.
4. Data verify tail (unchanged from the night build): castTime for the 8 SoA spells,
   Carcharian Verve mpCost, which trait the SoA spells feed, spellType eyeball on the
   24 scriptless rows. Nothing blocks UI.
5. Optional chrome icons (`ICONS_WANTED.md`) — everything has fallbacks; the empty-slot
   ring is now generated (`tools/make_slot_icon.py`).
6. Ideas parked: filter persistence, a settings panel (delay/override/castLock),
   README screenshots.

## 5. Architecture map

```
bludex.lua            standalone entry: package.path bootstrap, settings, events, commands
lib/config.lua        the settings shape, shared by both flavors (T{} headless-safe)
lib/blu.lua           game layer: signatures, 0x102 send (safe/fast), 0x061 nudge,
                      cast lock, applySet/applyDiff (SORTED slot-wise) /
                      restoreMissing (identity, adds-only), watchJobState
lib/spellbook.lua     data service; lib/setmodel.lua pure set logic + sortedLayout
ui/kit.lua            guarded widgets, esc, palettes (PAL.go/off), measure, availWidth
ui/filetex.lua        D3DX textures (KEEP the object); icon paths follow ROOT
ui/host.lua           tick (watch+restore), theme split, renderBody (header meters +
                      Save/Apply/Revert + countdown + tabs + Spell Info window),
                      render (standalone) / renderWindowFloat / renderEmbedded / open
ui/spellsui.lua       codex + listRow/tooltip/densityCombo/densityParams + detail window
ui/setsui.lua         sets + the shared verbs (save/apply/revert/unsaved) + slotList
ui/traitsui.lua       ladders + codex-grammar rows
dlacmodule/           the dlac adapter (init.lua contract + README approval doc)
.github/workflows/    sync-dlac.yml (vendors on push to main)
tools/                smoke.lua (headless suite), generate_spells.py,
                      make_slot_icon.py, vendor_local.py
ALL modules derive ROOT from their own module name -- relocatable (the vendoring law).
```

## 6. Verify from scratch

```
/addon load bludex          (standalone)   |   /addon reload dlac   (module flavor)
lua bludex/tools/smoke.lua                 (from Ashita/addons/)
lua tests/run_tests.lua && lua tests/smoke_ui.lua   (from dlac/, for dlac changes)
python bludex/tools/vendor_local.py        (refresh the live dlac module)
python bludex/tools/generate_spells.py     (regenerate data)
```

Asset masters + icon-audit handover: `C:\Users\Henrik Johansson\OneDrive\Bilder\BLU\HANDOVER.md`.

---

## 7. The point budget (1.0.1)

**The cap is client-side and cannot be fetched.** The server's `0x044` carries
`Job`, `IsSubJob`, `SetSpells[20]` and 132 bytes it never writes — the total
never crosses the wire. The client computes it and only recomputes when the
native **Magic → Blue Magic → Set** menu opens: not on zoning, not on a level
sync. A `0x102` "query" was tried (`4430c86`) and field-disproved; it also arms
a 60s recast on every set spell, so it is never free. Do not go there again.

So Bludex models it instead:

```
cap(level) = baseCapAtLevel(level) + learnedBonus + merits   (merits only at 75)
```

| part | where it comes from |
|---|---|
| base | `setmodel.baseCapAtLevel`, `clamp(((lvl-1)/10)*5+10, 0, 55)` — exact, from `blueutils.cpp` |
| merits | Assimilation, job group 2. Count off packet `0x08C` at every zone-in; ×2 on CEXI. Only applies at Lv75 |
| learned bonus | CEXI's award for spells learned (Boruko, Whitegate J-10, max 25). Applies at EVERY level |

Two equations settle it, and neither needs the per-merit rate:
`below 75: bonus = cap - base` (merits do not apply) — `at 75: merits = cap - base - bonus`.

Shortcuts on top: `0x08C` gives the merit count on any zone; `0x063`'s
`bluBonus` gives `bonus + merits` at Lv75 (CEXI folds the learned bonus in —
it is NOT merits alone, which is the `133` bug of 2026-08-06). Both are
standalone-only; the dlac flavor has no packet hook and derives everything from
two cap readings instead.

**The trap, three times over:** the cap is trivial to READ and often wrong.
`watchCap` only trusts a reading it watched CHANGE (`verified`), never one
merely found at load, and never the `nil → value` bounce of a zone handoff.
`/bludex forget` (undocumented) wipes everything learned.
