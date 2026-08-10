# Bludex — Session Handover

**Date:** 2026-08-08 (the TIMELINE session — remote maintainer build on Henrik's
authority, zero field time; supersedes the 2026-08-04 handover, which is kept
below as §H for everything it proved that still stands)
**Repo:** https://github.com/henkpoa/bludex — public, `main` + `dev` (all work on `dev`,
dev→main only on Henrik's explicit go; same law in dlac). `addon.version` is
**1.1.0 on dev** — NO release until the field pass below is green.

---

## -1. The merge of 2026-08-10 — the three systems, and where each one stands

Henrik's direction: BLUDEX keeps **all three** ways of building a set, chosen
**per set at creation** (with plain-words explanations), plus a setting for
which system answers first:

1. **Flat** — one spell per slot, the original shape. *Recommended at 75 when
   level sync doesn't matter.*
2. **Lvl Subsets** — a dedicated build per level band under one name, falling
   back to the flat build where no band is defined. *Recommended for dedicated
   per-band sets.*
3. **Slotlist (timeline)** — a level-ordered chain of spells per slot.
   *Recommended for granular control; the most advanced, Henrik's preferred.*

**What this merge did:** local dev (Lvl Subsets, commits `c3cf9a6..163b102`,
plus the trait-attribution work in `47ae622`) merged with `origin/dev` (the
timeline branch, which already carried main's 1.0.2 log-off save fix). Where
the two rewrote the same sets subsystem (`setmodel`, `setsui`,
`blusetsimport`, the codec/config/watcher parts of `config`/`dlacmodule`/
`host`/`bludex`), **the timeline side won wholesale** — a hunk-level splice
would have produced a hybrid that half-worked for both. The Lvl Subsets
implementation is NOT lost: it lives complete in the commits above (§0-old
row "A build per level band" describes it) and returns as the second set
type when the three-type model is built. Everything outside that subsystem
kept both sides: the trait attribution + hover gate + widget theme work,
the SoA wiki traits (now with per-tier `traitId` and `traitNames` entries —
generator unified), and the timeline's whole Sets tab.

**The work queue from here:** (a) ~~the per-set TYPE at creation + the
priority setting~~ and (b) ~~port Lvl Subsets back as a type~~ — **BUILT
2026-08-10, same day** (docs/set-types-plan.md is the design): `kind` on
every set (`setmodel.kindOf`, adopt stamps by shape, NOTHING converts — a
v1 store now adopts flat, the repeal of the v2 chains-for-everyone
migration), the whole group API back from history and kind-dispatched
through one editing surface, the New chooser (three kinds, Henrik's
wording, `cfg.newSetKind` = "New sets start as" in Settings orders it),
levels sets edited through drafts (`setmodel.draft`) with the band
ceilings and `blu.rungCap` restored, the dlac `sets3` grammar (truth;
sets2 = timeline-only; legacy stays the tolerant mirror, levels lines
included). Suite-proven end to end incl. real stub renders of the chooser
and all three editors (364 checks) — **field round owed on all of it**.
(c) ~~the LEVELS-KIND LEVEL-CHANGE WATCHER~~ — **BUILT, third slice same
day** (plan §5): ONE LAW — the behavior belongs to the set you last
APPLIED (`cfg.lastAppliedSet` is back, every apply path records it, an
unsaved draft clears it). A followed levels set arms ITS rule (the
per-set combo under the name box, Henrik's wording verbatim; `ruleOf`
derives restore-while-flat / switch-with-levels): Switch equips a band's
own build outright on a crossing (diff-checked, silent when worn, its
line replaces the down report), everything else restores adds-only
(`blu.restoreMissing` + `planDiff` un-retired). Level DOWN sends nothing.
The timeline `replan` check STANDS DOWN while a levels rule is armed —
never two writers on one change. The quiet-why line (watch alive /
nothing applied / another set followed) sits under the rule combo.
Driven end to end against a stub client (`smoke: the level-change rule`,
21 checks) — **this is the packet-sending feature: its field round is
the one that matters most**. AND (fourth slice, same day) **KIND
CONVERSION IN PLACE** (plan §6): Convert... under the name box, the flat
projection as the bridge (`setmodel.convertTo`/`convertLoss`), losses
named before the two-click confirm, unsaved edits must settle first,
source never mutated. AND (fifth slice, same day) **BACKUPS FOR EVERY
KIND** (plan §6b): kind-shaped backups, restoreBackup flips kinds --
Convert banks the old state as backup 1 with the ring carried across,
so a lossy conversion is UNDOABLE; save-over banks on every kind, the
right-click ring opens on every row, sets2bak grammar kind-tagged.
The plan has nothing parked left. Still queued: (d) the job-traits
field round, (e) the field checklist below (§0), once per kind, plus
one live band-crossing under Lvl Set Switch and one conversion + undo
round-trip.

---

## 0. The timeline session (2026-08-08) — READ THIS FIRST

**Design:** `docs/timeline-sets-plan.md` — settled with Henrik in a same-day
Q&A, then built to completion by the remote maintainer session under his
"you are the maintainer now" grant. **Everything is smoke-green (264 checks,
`lua bludex/tools/smoke_posix.lua` from the parent dir) and NOTHING is
field-confirmed yet.** The field checklist is plan §9; the concrete morning
list is at the end of this section.

### What a set IS now

`{ name, builtFor, chains[20], ids[20] (derived 75-mirror), backups<=5 }` —
each slot a level-ordered CHAIN of `{ id, from }` entries (id 0 = deliberate
empty marker). The entry with the highest `from` at or below the level is
worn; `setmodel.resolveAtLevel` collapses to the flat 20-id array everything
below the resolution line still speaks (sortedLayout/applyDiff untouched).
Slot index carries the unlock bracket (`bracketFloor`: 1-6 open at Lv.1,
pairs at 11/21/31/41/51/61/71 — pinned against `slotsAtLevel` at every
level). A flat set is the degenerate case; migration (adopt-time,
`setsModelVer 2`) is the sorted apply layout made visible and is lossless.

### The laws this session added (each smoke-pinned)

1. **One place at a time** — a spell's ranges may never overlap across
   chains; adds are refused with the collision named, and REMOVALS that
   would stretch a predecessor into a collision are refused too (the
   extension guard).
2. **No dead entries** — an edit may not leave any entry never-active
   (floor-shadowed or instantly replaced).
3. **The band sweep** — `bandViolations` checks points vs budget at every
   breakpoint 1-75; `builtFor` scopes ENFORCEMENT (75 = endgame set, only
   75 must fit; 1 = leveling set, everything must). Enforced+known bands
   hard-block Apply (UI, `/bdx apply`, `/bdx replan`, auto — all four);
   Save is never blocked, the set wears a badge instead. Unknown learned
   bonus ⇒ provisional bands, warn-only. THE MERIT CLIFF: a maxed 75 set is
   over budget at 71-74 by real math (merits count only at 75) — builtFor
   75 is what keeps every endgame set green.
4. **The slider previews, Apply resolves live** — the plain Apply always
   uses the real effective level; only the explicit **Apply for Lv.N**
   button (shown while previewing away from live) sends another level's
   plan, and `lastApplied` remembers the level so the header says
   "matches your Lv.N plan" instead of glowing green at it.
5. **The adds-only law is REPEALED** (Henrik 2026-08-08): level changes
   re-plan, which may unset. `restoreMissing`/`planDiff` are deleted;
   `cfg.autoRestore` → `cfg.replan` ('manual' default for everyone — auto's
   meaning changed). Manual = header note + nudge float (rides the dlac
   float hook too) + one chat line; auto = debounced self-apply. THE
   QUIET-FLAT RULE: a plan that would only REMOVE spells for the level
   stays silent — the client's own sync-disable already covers it.
6. **Mutation lives in the Sets tab alone** — codex/traits/Spell Info are
   reference-only (assignment status with ranges where the buttons were);
   the Assign pane (right column, opened by a slot's `+`) is the one add
   path; entries remove by right-click with the guards deciding.
7. **Backups** — every save-over and Read-current banks the replaced state
   (ring of `BACKUP_CAP=5` on the entry, restore via right-click on the
   saved row; restores bank first, so they undo too).

### Persistence

Standalone: new fields ride the settings table; `adoptCfg` migrates in
place. dlac: new keys `sets2` / `sets2bak` / `lastApplied2` (versioned
'#v2' grammar, `id@from` entries, empty-token-preserving splits, clamps and
re-sorts on decode) while the LEGACY `sets`/`lastApplied` keys keep being
written as each set's flat 75-mirror — the old decoder zeroes unknown
tokens, so the old grammar must never change shape or an older module
silently EMPTIES every set. Reader prefers v2. Retire the dual-write one
release after the field pass.

### The SoA burst spells (Henrik's parting task, done)

Traits added from bg-wiki (his call: wiki is truth for all but level):
719→Attack Bonus, 720→Magic Atk., 721→Accuracy, 722→Defense, 725→Magic
Eva. (NEW cat 29), 726→Magic Def., 727→Evasion, 728→Magic Acc. (NEW cat
30) — weight 8 each; stats cross-checked and they MATCH the 2026-08-04
field readings, so mods stand. Cats 29/30 are bludex-internal ids
(traitId = LSB trait.h 126/125, tier at 8 pts, +10 sibling convention —
the tier VALUES are the one assumption left; eyeball in game). bg-wiki
itself was egress-blocked from the cloud session — values came through
per-spell web-search extraction, cross-checked against upstream LSB where
it had anything. Generator carries `WIKI_TRAITS`/`WIKI_TRAIT_CATEGORIES`.

### Decisions made on maintainer authority (alternatives noted)

* **Assign pane is a lean picker** (search + category + level-sorted rows
  reusing `listRow`), NOT the extracted codex filter row the plan §6
  sketched — less churn, same UX; the full extraction remains open if the
  pane ever wants sort/density parity.
* **The nudge float rides the existing float surfaces** (standalone
  d3d hook + dlac `window` hook when the main window is closed); the
  embedded-Panel-only flavor degrades to header note + chat line.
* **`cfg.replan` defaults to 'manual' for everyone**, including old
  autoRestore=true users — auto now unsets, nobody inherits that silently.
* **Slot numbers never render** — bracket group headers only ("Lv.21-30"),
  since the engine re-sorts slots on every apply anyway.
* **builtFor edits live under the Name box** (left column), default 75 on
  everything migrated and new.
* An adversarial code review ran over the whole branch before merge; its
  13 findings (backup-ring reset, silent refusals, stale nudges, decode
  clamps, the /bdx apply back door, meter semantics, per-frame sweep cost)
  are all fixed and largely regression-pinned.

### Field checklist for the morning (plan §9 in short)

- [ ] Load on CEXI: saved sets migrate flat, look identical, no badges,
      Apply behaves byte-identically for a flat set.
- [ ] Build the Wild Oats → Bludgeon → empty-at-45 chain; slider sweep;
      stats/traits follow; bands paint.
- [ ] Preemptive apply: Apply for Lv.N at 75, sync, zero packets at sync,
      header reads "matches your Lv.N plan".
- [ ] Ding a level with a pending swap: Manual nudge (header + float +
      chat), then Auto mode, debounce not firing mid-bounce.
- [ ] Sync down with a builtFor=1 set: low entries return via re-plan, no
      server-rejected tail; flat set stays QUIET.
- [ ] Badge + Apply block on a deliberately overfilled leveling set;
      `/bdx apply` refuses too.
- [ ] dlac flavor: chains round-trip the store; an OLD dlac module still
      sees flat sets (nothing wiped).
- [ ] Read current: two clicks, backup banked, restore works.
- [ ] SoA: set Spectral Floe, check Magic Atk. Bonus appears (and the two
      addendum trait VALUES against the game's own trait menu).
- [ ] README + screenshots are STALE (grid, right-click add, quick-add) —
      rewrite after the field pass, not before.

---

# §H — the 2026-08-04 handover (previous session)

Everything below was field-confirmed for the PRE-TIMELINE addon. Still-true
laws: the packet layer, signatures, cast lock, cap staleness, budget model,
settings lifecycle, the kit laws. SUPERSEDED by §0: the Sets tab layout
(grid + quick-add are gone), right-click add/remove anywhere (gone), the
adds-only auto-restore (deleted), `applyDirty` duplication (consolidated
into `setsui.applyState`), flat `{ name, ids }` sets (now timelines).

**State as of 2026-08-04:** everything below **FIELD-CONFIRMED on CatsEyeXI**
unless marked otherwise. `addon.version` was **1.0.1**. The point budget is
MODELLED (`base(level) + learned bonus + Assimilation merits`, merits only
at 75) rather than read from the client's cache, which only recomputes when
the native Set Spells menu opens. See §7.

---

## 1. What exists (all field-proven today unless noted)

| Piece | State |
|---|---|
| Codex: icon+name list rows, 1-3 columns by width, filters + Sort (Name/Level/Type) + View densities (Big 64 / Medium 32 / Normal 24 / Compact no-icons), green = in set, dim = unlearned | Proven. Density + sort persisted (`codexDensity`; sort is session-state). |
| The row grammar (everywhere: codex, traits, sets-list): LEFT-click = Spell Info window, RIGHT-click = toggle in/out of set, hover = rich tooltip (centered 64 sprite, stats, trait + `set / next - for rank N` ladder progress) | Proven. Right-click uses `IsItemClicked(1)`. |
| **The hover gate** (new 2026-08-07, `cfg.tooltipDelay`, default 0.5s, Settings → Interface): the cursor must REST this long before ANY tooltip appears — `kit.hoverReady(key)` in front of `kit.tip` and `spellsui.tooltip`, keyed by tip text / spell id, one slot (only one item can be hovered) with a 0.25s gap meaning hover lost. imgui's own `DelayNormal` flags are 1.89+, this binding is older, so the dwell is timed in Lua. `host.tabCtx` carries the setting into the kit — NOT `tick()`, which an embedding host may gate (dlac rides an activity predicate). Tooltips also now carry the spell's **MP cost** | Suite-proven (`smoke: the hover gate`, `smoke: the spell tooltip`), **field round owed**. |
| **Trait attribution** (new 2026-08-07, `lib/traitsource.lua` + generated `data/jobtraits.lua`): a job trait and a blue trait can be the SAME trait, and the server does not stack them or keep the better one — it keeps the JOB one and discards the blue one outright, at any tier (`blueutils.cpp CalculateTraits`: *"Player has the real job trait, making them ineligible"*, with the `TODO remove the trait and add the blu trait if it's stronger` beside it proving the stronger-blue case was never written). Order is main job at main level → sub job at sub level → blue (`charutils.cpp BuildingCharTraitsTable`); blue traits load with `level == 0`, which is the discriminator. **The collision is by trait ID, not by ladder**: category 24 is trait 15 (Double Attack) at 2 weight and trait 16 (Triple Attack) at 4, category 28 is 20 (Gilfinder) then 19 (Treasure Hunter) — so a WAR sub kills the 2-weight rung and leaves the 4-weight one standing. `data/traits.lua` now carries a `traitId` PER TIER for exactly this. Surfaced on the Traits tab (job pair in the header, per-ladder source with `[SCH (sub job)]`, held rungs green, out-of-reach rungs red), in the spell tooltip + Spell Info (before you spend the points), and in the Sets trait summary | Suite-proven incl. a real stub render (`smoke: job traits`, `trait attribution`, `the per-tier trait id`, `the live bit is the referee`, `the Traits tab renders`), **field round owed**. |
| **TIERS CORRELATE, STAT VALUES DO NOT** (Henrik 2026-08-07, from the field — the tab read `Clear Mind  MpHeal +3 [SCH (sub job)]`): the two sides of a collision do not share a modifier. Job Clear Mind grants `MPHEAL` (mod 71, "MP recovered while healing", +3/+6/+9…); the blue ladder grants `CLEAR_MIND` (mod 295, +1/+2/+3/+4). A value read off one side means **nothing** against the other, so the UI never puts them side by side — it speaks in the trait's **rank**, which is the game's own counter and the number the rungs are indexed by. Every ladder rung is now in one of three states, judged PER RUNG by that rung's own trait id: **held** (`job.rank >= rungIndex` — green, annotated `<- SCH (sub job), rank 1: MP Heal +3` so the different modifier is never left implied), **blocked** (the job holds the trait at a lower rank, so the rung is out of reach — blue cannot lift a job trait), or open. Per-rung ranking is what makes category 24 come out right: a WAR at Double Attack rank 3 **holds** rung 1 and does not touch rung 2 at all, because that is Triple Attack, a different trait, and it comes through from the set. `data/traits.lua` gained `M.traitNames[id]` so a rung can be named as itself (`Triple Attack tier 2`) rather than as a tier of its ladder | Suite-proven (`smoke: tiers correlate, stat values do not`), **field round owed**. |
| **The referee**: `blu.hasTrait(id)` reads the client's own merged trait list — the server ships it on `0x0AC` and the client keeps it in the command table with job traits based at `0x600`, so ability id `1536 + traitId` is the live bit (dlac reads 1554 for Dual Wield the same way). It can confirm or contradict but **never attribute** — blue traits set the same bits, which is why `jobtraits.lua` exists at all. `data/jobtraits.lua` is base-LSB from the public clone and CEXI may override it, so a disagreement renders as `(game says no)` rather than a confident wrong answer. The bits are all zero until 0x0AC lands, so `host.tabCtx` hands the reader over only once a trait we EXPECT is lit | Suite-proven, **field round owed**. |
| Spell Info window: add/remove button at top (flips by membership), centered 320 sprite, wrapped long lines, learn-from hints | Proven. Draws from `host.renderBody` so traits/sets rows open it too. |
| Sets tab: saved sets (active set + which build remembered by NAME across loads), slot area as **Grid** (5x4 centered cells, empty = ring PNG) or **List** (codex rows + `(not active yet)` tags) — persisted `setsLayout`; live-state dimming; meters; quick add | Proven (the tree around it is new, below). |
| **A build per level band** (new 2026-08-06, NOT field-tested): a **Levels** section under the name box lists the bands this set HAS — added on purpose from an `Add a level` list (or all at once), `Remove` takes one back — each row `used / cap  filled / slots` + hover spell list; `>` marks your band; clicking one edits that build (its slot ceiling greys the grid, `canAdd` gates on its slots, its budget and its band's top spell level). Budget per rung = `blu.rungCap` (top rung planned at 75, where the merits land). **Nothing migrates**: the name row is the set's FLAT build and a set stays flat until a level is built. Storage `{name, ids, builds={{level, ids}}}`; the dlac codec writes the flat line byte-identically to before, level builds as extra `name<TAB>level<TAB>ids` lines | Suite-proven (`smoke: level builds`, `smoke: the Sets tab actions`), **field round owed**. |
| **THE SELECTION RULE** (`setmodel.groupPick`, Henrik 2026-08-06 from the field — "I walked out now, and I still have my level 31 set equipped"): the build for a level is that band's OWN build, else THE FLAT BUILD. A level build serves its band and **never fills forward**. Only exception: a set whose flat build is empty has no backup, so the nearest build below answers rather than nothing | Suite-proven, **field round owed**. |
| **Copy** (`setmodel.copyInto` + the `Copy from:` row, empty level builds only): fills a band from the flat build or the nearest built band — lowest spell levels first, nothing above what the band casts, no more than its slots. **Points are deliberately allowed to overflow** (trimming is the player's judgement, and a copy that silently dropped spells would hide the choice). This is also how a flat set becomes a level one | Suite-proven, **field round owed**. |
| **The level-change rule BELONGS TO THE SET** (Henrik 2026-08-07 — "Level Change should NOT be a setting for a Level Set, it should only be on a set"): `entry.rule` ∈ restore / switch / manual, picked from a combo under the Name box (each choice carries Henrik's own wording as its hover). Unset it is **derived** from the set's shape — `restore` while flat, `switch` once it has levels — so the default follows what you build and nothing is flipped behind your back; a stored pick stands. The **set last APPLIED** is the one whose rule runs (`cfg.lastAppliedSet`); the global `autoRestore`/`autoSwitch` keys are gone. **Lvl Set Switch = Restore behaviour on the normal set, UNLESS the band has its own build**, which is then equipped outright: `bandSwitch` acts only on a band that has one (silent when the live set already matches — a band change must not cost the 60s cast lock for nothing, and it suppresses the level-down report only when it will actually act), while `restoreNow` covers every other level move, adds-only, targeting the set's build for this band or its flat build. Fires 3s after the band moves (sync transitions bounce the structs). The dlac codec carries a picked rule as a `name<TAB>rule<TAB>key` line, written only when stored | Driven end-to-end against a stub client (`smoke: the level-change rule`), **field round owed — this is the one that sends packets on its own.** |
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
