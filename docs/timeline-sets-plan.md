# Timeline Sets — design + implementation plan

**Date:** 2026-08-08 (design settled with Henrik over the full Q&A round; this doc is the
record and the build order). **Status: approved design, not yet built.** Nothing in this
plan is field-proven until the checklist in §9 says so.

## 1. What we are building, in one paragraph

One set that scales from level 1 to 75. Each of the 20 slots becomes a **chain**: a
level-ordered stack of entries where the highest entry at or below your level is the
spell you actually wear ("Wild Oats from 4, Bludgeon takes over at 18, slot goes empty
at 45"). Slots are presented grouped by their **unlock brackets** (6 slots at 1-10, +2
at 11/21/31/41/51/61/71), a **level slider** previews the whole set — spells, stats,
traits, budget — at any level without touching the game, and the point budget is
validated across the entire curve with concrete band messages. The codex becomes a pure
reference; all set mutation moves into the Sets tab, whose right column gains an
Assign picker. Today's flat sets are the degenerate case (every spell a one-entry chain
activating at its own level), so migration is lossless and most sets stay flat forever.

## 2. Decisions locked (the Q&A record)

1. **Brackets, not slot numbers.** The engine already destroys slot identity
   (`sortedLayout` re-sorts on every apply), so the editor groups chains under bracket
   headers: 1-10 (6 chains), 11-20, 21-30, ... 71-75 (2 each). Slot numbers never appear.
2. **Chain entries** are `{ id, from }` where `id = 0` means an **empty marker** (the
   slot is deliberately vacant from that level until the next entry, freeing points).
   An entry's active range is `[from, next entry's from - 1]`, or `[from, 75]` for the
   last entry, floored by the chain's bracket unlock level.
3. **The level picker exists in v1** (Henrik's call, reversing an earlier
   simplification): adding a spell asks for its activation level, **default = the
   spell's own level**, minimum = the spell's own level, and strictly greater than the
   previous entry in the chain. Empty markers always pick a level (they have no natural
   one).
4. **Re-adding is legal when ranges don't overlap.** A spell may appear multiple times
   across the set (same chain or another) as long as no two of its active ranges
   intersect — at no level is it worn twice. The picker must show *why* a spell is
   blocked (which range collides). Two rules this forces, both new:
   - **Overlap check on add:** the entry's resulting range is computed against every
     other range of the same spell id; intersection = rejected with the colliding range
     in the message.
   - **Extension-conflict check on remove/edit:** removing Bludgeon (18) from a chain
     extends Wild Oats' range from 4-17 to 4-75 — which may now collide with a second
     Wild Oats placement at 30 elsewhere. Any edit that *extends* a range re-runs the
     overlap check and is rejected with a concrete message ("removing Bludgeon would
     make Wild Oats active twice from 30") rather than silently corrupting the set.
5. **Per-set `builtFor` (default 75, migrated sets 75).** Budget enforcement applies
   only in `[builtFor, 75]`. Below it the slider still shows honest but dimmed,
   informational bands. This is what keeps every existing endgame set green: merits
   count only at exactly 75, so a maxed ~79-point set is "over budget" at 71-74 by
   construction — real math, wrong intent. A leveling set sets `builtFor = 1`.
6. **Band validation:** at every breakpoint (bracket thresholds ∪ entry activation
   levels ∪ 75), `usedPoints(resolveAtLevel(L)) <= budget(L)`. Violations inside the
   enforced range **hard-block Apply** and produce the message verbatim: *"Between
   level 37 and 40, you are 3 point(s) above threshold."* **Save is never blocked** —
   an invalid set saves fine but carries a loud badge ("⚠ over budget at 37-40") on its
   saved-list row and in the header until fixed. (Reason: budgets are *measured*;
   re-allocating Assimilation merits can invalidate an untouched saved set, so a save
   block only ever punishes work-in-progress.) Unknown learned bonus ⇒ warnings are
   provisional ("assuming +0 learned bonus") and never block.
7. **The adds-only law is repealed.** Re-planning on level change may unset. Both
   directions matter equally (sync down to a BCNM, dinging up while leveling). The old
   guarantee that hand-set native-menu spells survive is consciously given up.
8. **Re-plan trigger:** per-player **Auto / Manual, default Manual**. Manual = a small
   float window with an icon appears when the plan for the current level differs from
   live ("Plan changed at Lv 18 — Apply"), plus a chat line; ignore it mid-fight, click
   it when safe. Auto = debounced (level stable a few seconds, never while an apply is
   in flight). dlac flavor rides the existing float-window hook; degrades to the
   glowing header button + chat line where no float surface exists.
9. **Two apply verbs.** **Apply** always resolves at the live effective level — the
   slider can never touch it. **"Apply for Lv N"** (label follows the slider) is the
   deliberate preemptive apply: eat the 60s cast lock *before* the BCNM sync so the
   sync itself costs nothing. Corollary: the dirty compare must recognize "live
   matches your Lv 40 plan" and say so — otherwise Apply glows green after a
   preemptive apply and baits the player into wiping their own setup.
10. **Codex/Traits/Spell Info lose all mutation** (right-click toggle, the Add/Remove
    button). Compendium is for browsing. The green "assigned" tint **stays** and goes
    chain-aware: any spell present anywhere in any chain of the editing set shows
    green, even when inactive at the preview level. Tooltip hint lines rewritten.
11. **Read current = overwrite with confirmation + backup.** The client only knows a
    flat list, so reading into a chained set erases chains; the confirm says so, and
    the pre-read state is pushed onto the set's backup list first.
12. **Per-set backups, cap 5.** Every destructive replace (Save over an existing set,
    Read-current overwrite) pushes the prior saved state onto the set's backup ring
    (newest first, oldest dropped past 5). Restore via the saved-set row (right-click
    → backups list).
13. **Migration:** each flat set becomes chains by sorting its spells ascending by
    level into the bracket slots (exactly `sortedLayout` order — the editor finally
    shows what Apply sends), one entry per chain, `from` = spell level, `builtFor` =
    75. A level-8 spell landing in slot 7 (bracket 11-20) effectively starts at 11 —
    which is faithful: the flat set behaved that way already (only 6 slots exist at 8).
14. **Sets = purpose, chains = level scaling.** Dynamis/cleave/dragon sets stay flat
    and show no timeline chrome. The left column (multiple sets) is unchanged.
15. **Middle column:** grid mode and the quick-add strip are removed
    (`cfg.setsLayout` becomes dead and ignored). The column is 100% the bracket list.
    The game-action rows (Apply / Read current / Clear, the re-plan toggle) stay at its
    bottom for v1.

## 3. Data model (`lib/setmodel.lua` — pure, headless, smoke-testable)

```lua
-- A set (v2):
{
  name    = "Leveling",
  builtFor = 75,            -- budget enforcement floor; 1 for leveling sets
  chains  = {               -- array[1..20], index = slot; bracketFloor(i) gates it
    { { id = 603, from = 4 }, { id = 529, from = 18 }, { id = 0, from = 45 } },
    ...                     -- {} = never assigned
  },
  ids     = { ... },        -- DERIVED resolveAtLevel(75), kept for one release so
                            -- older bludex versions still read a usable flat set
  backups = { { ts=..., chains=..., builtFor=... }, ... },  -- cap 5, newest first
}
```

New pure functions (all with `smoke.lua` coverage before any UI exists):

- `bracketFloor(slot)` — 1 for slots 1-6, else `ceil((slot-6)/2)*10 + 1`
  (7-8→11 ... 19-20→71). Must agree with `slotsAtLevel` at every level 1-75 (pin it).
- `resolveAtLevel(set, L)` → flat `ids[20]`: per chain, the last entry with
  `from <= L`; empty markers and unassigned chains resolve to 0; a chain whose
  bracket floor `> L` resolves to 0 regardless of entries.
- `entryRange(set, slot, idx)` → `lo, hi` with the bracket floor applied to `lo`.
- `canAddEntry(set, slot, id, from, book)` → `ok, reason` — the v2 `canAdd`:
  known/castable/not-Unbridled/learned/setPoints (unchanged gates), `from >=
  spell.level`, `from >` previous entry's `from` in the chain, `from <= 75`, and the
  **overlap check** of §2.4 across all other placements of the same id. Budget is NOT
  checked here — bands are a whole-set property (§2.6), reported not gated.
- `removeEntry(set, slot, idx)` / `editEntry(...)` → guarded by the
  **extension-conflict check** of §2.4; return `ok, reason`.
- `bandViolations(set, book, budgetFn)` → array of `{ lo, hi, over, provisional }`
  evaluated at the finite breakpoints; caller scopes enforcement by `set.builtFor`.
  `budgetFn(L)` comes from `blu.budget`/`expectedCap`; nil learned bonus ⇒
  `provisional = true`.
- `containsAnywhere(set, id)` — chain-aware membership for the codex green tint.
- `migrateSet(oldSet)` per §2.13; `isFlat(set)` (every chain has ≤1 entry, no empties,
  every `from` == spell level) so the UI can skip timeline chrome.
- `usedPoints/usedMP/stats/traitEval` are **unchanged** — they take the flat array
  `resolveAtLevel` returns. That is the load-bearing design property: everything below
  the resolution line (including `sortedLayout`, `applyDiff`, the packet layer) never
  learns chains exist.

## 4. Budget semantics (unchanged facts, new consumer)

`budget(L)` = `baseCapAtLevel(L)` (10/15/.../45, stepping at 11/21/.../71) + measured
learned bonus (every level) + Assimilation merits (**only at L == 75**). All existing
laws hold: model-wins display rule, cap staleness, nil until measured. The band sweep
is the only new consumer, and it must go through `blu.budget`/`expectedCap` — never a
re-derived table.

## 5. Engine (`lib/blu.lua` + verbs in `ui/setsui.lua`)

- **Apply (live):** `applyDiff(resolveAtLevel(editingSet, blu.effectiveLevel()), book)`.
  Blocked while `bandViolations` has an enforced entry — the block message is the band
  message.
- **Apply for Lv N:** same call with the slider level. Requires the plan valid at N.
  Legal at any real level (a Lv-40 plan applied at 75 just leaves slots/points unused).
- **`cfg.lastApplied`** becomes `{ ids = {20}, level = N }` — the level a plan was
  applied *for*. The dirty compare gains a third state: live == `resolveAtLevel(live)`
  ⇒ clean; live == `resolveAtLevel(lastApplied.level)` ⇒ "matches your Lv N plan"
  (header says that, Apply does not glow); else dirty. The two duplicated applyDirty
  implementations (`ui/host.lua:256` and `ui/setsui.lua:351`) are **consolidated into
  one exported function** as part of this change — updating both forever is how bugs
  happen.
- **Level change:** `watchJobState` already reports up/down/jobs. New: compute
  `resolveAtLevel(newLevel)` vs live; if different, Manual ⇒ nudge float + chat line,
  Auto ⇒ debounced applyDiff (level stable ~3s, `M.applying` respected, never during
  the level-0 handoff bounce). `restoreMissing`/`planDiff` and `cfg.autoRestore` are
  retired; the setting migrates to `cfg.replan = 'manual' | 'auto'` (default manual).
  Sync-down note: a valid in-range plan fits the synced caps by construction, so the
  server-rejected-tail case disappears for validated sets.
- Cast lock, safe/fast mode, signatures, 0x061 nudge: untouched.

## 6. UI

**Middle column** — the bracket list (grid + quick-add deleted):
- Bracket header rows ("1-10 — 6 slots", dimmed when preview level below the floor).
- Chain row: active head at the preview level as a codex-grammar row (icon, name,
  "18-44"), sub-entries beneath at compact density (retired dimmed grey with their
  past range, future entries dimmed blue with "at 45"), empty markers as "(empty from
  45)". Unassigned chains render individually: "opens at 21 — click to assign".
- Selection: clicking a chain selects it and flips the right column to Assign. The
  `(not active yet)` / `(disabled by level sync)` live-state tags survive on heads.
- Left-click grammar change: rows select the chain (mutation context) — Spell Info
  moves to the tooltip's "click for info" affordance on the *sub-entry* rows only, or
  stays on left-click for head rows with selection on the chain frame; final call at
  build time with the field feel, but the row grammar table in §8 is the contract.

**Level slider** — top of the middle column: guarded `kit.slider` (new kit widget,
SliderInt with InputInt fallback), range 1-75, tick marks at 11/21/.../71/75, red band
marks from `bandViolations`, dim marks below `builtFor`. Tag when slider ≠ live:
"previewing Lv 40 — live Lv 75". Defaults to live effective level on BLU, else 75.

**Right column** — two tabs (litButton pair, same as everywhere):
- **Stats** (default): today's stats/traits panel fed by `resolveAtLevel(sliderLevel)`;
  meters go level-aware (points vs `budget(sliderLevel)`, chains-active vs
  `slotsAtLevel(sliderLevel)`).
- **Assign** (auto-selected when a chain is selected): the codex list, extracted. The
  filter row, sort, column layout, and row loop currently live inline in
  `spellsui.M.render` with the click action hardcoded — they are extracted into
  parameterized functions (own filter-state table, injected click handler + row
  decorator) and the codex tab becomes the first consumer of the extraction, the
  Assign pane the second. Rows show the level picker on add (default = spell level),
  and blocked spells render dimmed with the overlap reason in the tooltip
  (`canAddEntry` reason strings). Width fits: left ~210 + mid ~330 + picker ~372
  inside the 920px window minimum; embedded dlac uses the same in-panel pane (Panels
  may not open windows — the popup option is dead on arrival, which is why Assign is
  a tab).

**Codex / Traits / Spell Info:** right-click becomes inert; Add/Remove button removed;
tooltip hint lines rewritten; green tint switches to `containsAnywhere(editingSet, id)`.

**Header:** badge ("⚠ over budget at 37-40") next to the set name when enforced bands
exist; Save/Revert unchanged; Apply verbs per §5; meters follow the slider.

**Backups:** right-click a saved-set row → inline list of up to 5 timestamped backups
→ click restores (itself pushing the current state as a backup first, so restore is
undoable).

**Read current:** confirm ("This will replace the chains of 'Leveling' with the flat
in-game set — a backup will be kept"), push backup, then overwrite as today.

## 7. Persistence + the dlac codec (the wipe hazard)

- **Standalone:** Ashita settings round-trip tables. New fields ride along; `ids` is
  dual-written as the level-75 resolution so an older bludex reads a sane flat set.
  `adoptCfg` (the proven migration choke point, `capModelVer` precedent) gains
  `setsModelVer = 2`: entries without `chains` are migrated per §2.13 in place, saved
  once.
- **dlac:** the store is scalars-only and the **old decoder turns unknown tokens into
  0 — new-format data read by an old module silently EMPTIES every set.** Therefore a
  **new key**, not a new grammar on the old key:
  - `sets2` — versioned grammar, one string: records `\n`-joined;
    record = `name \t builtFor \t slot-chains`; chains `;`-joined over slots 1-20;
    chain = entries `,`-joined; entry = `id@from` (`0@45` = empty marker). Backups ride
    a `sets2bak` key with the same grammar plus a timestamp field.
  - `sets` (legacy) keeps being written as the flat level-75 resolution for one
    release, then retires. Old module + new data = usable flat sets, nothing wiped.
  - `lastApplied2` = `level \t 20-csv`. Reader prefers v2 keys, falls back to legacy.
  - `smoke.lua` round-trips all of it, including the tab/newline name sanitization and
    the empty/nil tolerances the current codec tests pin.
- **New working state** (selected chain, slider level, picker filters) goes through
  `freshState`/`resetCharState` with an explicit keep-vs-drop decision per field —
  slider level and filters are view state (keep), selection resets (drop).

## 8. Build order (each phase lands green on `smoke.lua` before the next)

1. **Model:** chains, `bracketFloor`, `resolveAtLevel`, `entryRange`, `canAddEntry`
   (overlap), remove/edit (extension conflict), `bandViolations`, `containsAnywhere`,
   `migrateSet`, `isFlat` — pure Lua + exhaustive smoke tests (including the
   bracketFloor↔slotsAtLevel agreement sweep and a band sweep against pinned budget
   tables).
2. **Persistence:** standalone `setsModelVer` migration in `adoptCfg`; dlac `sets2` /
   `sets2bak` / `lastApplied2` codec + legacy dual-write; smoke round-trips.
3. **Engine verbs:** resolution-based Apply, Apply-for-Lv-N, three-state dirty compare
   (consolidated), level-change nudge/auto, retire `restoreMissing`, `cfg.replan`.
4. **UI:** picker extraction from `spellsui.M.render` (codex re-consumes it first —
   zero behavior change proves the extraction); then the bracket list, slider (new
   `kit.slider`), Assign pane, mutation removal in codex/traits/Spell Info, badges,
   backups, nudge float, meter rewiring.
5. **Field pass** (§9) before any dev→main talk.

All the standing laws apply throughout: guarded imgui with text fallbacks, `kit.esc`
on every drawn string, measured widths never hardcoded, PushID/PopID on repeated
widgets, cell geometry `size+4`, embedded/float gating, `ctx.save` only after
successful mutation, model math only in `setmodel`.

## 9. Field checklist (nothing above is "done" until these are witnessed on CEXI)

- [ ] Migration: existing saved sets load as flat chain sets, zero visual regression,
      badges absent, Apply behavior byte-identical (same packets for a flat set).
- [ ] Preemptive apply: Apply-for-Lv-40 at 75 → sync to 40 → zero packets needed, no
      cast lock at sync; header shows "matches your Lv 40 plan" the whole way.
- [ ] Ding swap: level 17→18 with Wild Oats→Bludgeon chained; Manual nudge appears,
      one click swaps, lock counts down; Auto mode does it debounced.
- [ ] Sync down with a `builtFor=1` set: low-level entries return via re-plan, no
      server-rejected tail.
- [ ] Band block: a deliberately over-budget band blocks Apply with the exact message;
      badge shows and survives save/reload; merit re-allocation flips a saved set to
      badged without edits.
- [ ] dlac flavor: old module reading new store shows flat legacy sets (nothing
      wiped); new module round-trips chains + backups through the scalar store.
- [ ] Read-current confirm + backup + restore-from-backup round trip.
- [ ] Budget-unknown state: fresh character, bands provisional, nothing blocks.

## 10. Deliberately deferred

- Per-entry activation-level *editing* after the fact (v1: remove + re-add).
- Auto-suggest placement ("this spell could activate earlier in a lower slot") — soft
  hint only, maybe never.
- Retiring the legacy `sets` dual-write (one release later).
- Grid layout is gone, not hidden; `cfg.setsLayout` ignored, removed from defaults the
  release after.
