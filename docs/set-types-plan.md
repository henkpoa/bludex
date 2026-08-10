# Set types — the three systems under one roof

**Settled with Henrik 2026-08-10** (the merge that brought the timeline in
recorded the direction in HANDOVER §-1; this is the design). Every saved set
has a **kind**, chosen when the set is created and fixed for its life:

| kind | what it is | Henrik's recommendation (the chooser says this) |
|---|---|---|
| `flat` | one spell per slot, the original shape | "Recommended for level 75 when you are not interested in level sync. One spell per slot, applied as-is." |
| `levels` | a build per level band under one name, falling back to the flat base build where no band is defined | "Recommended when you want dedicated sets per level range. Falls back to the base build where no range is built." |
| `timeline` | a level-ordered chain of spells per slot (docs/timeline-sets-plan.md) | "Recommended when you want granular control over which spells go to which slot at specific levels. The most capable." |

## 1. The shapes

```lua
{ kind='flat',     name, ids={20} }
{ kind='levels',   name, ids={20},          -- the BASE build (the fallback)
                   builds={ {level,ids}.. }, rule=nil|'restore'|'switch'|'manual' }
{ kind='timeline', name, builtFor, chains={20}, ids={20 mirror}, backups<=5 }
```

`setmodel.kindOf(set)` answers for every table, stored or drafted: an explicit
valid `kind` wins; otherwise shape infers it — `chains` → timeline, `builds`
→ levels, else flat. **v1 sets stay flat.** The v2 adopt converted a flat set
into one-entry chains; v3 stops doing that — a set nobody asked to be a
timeline isn't one. A store already carrying chains (the timeline session's
smoke stores; no field store exists) keeps them, as kind timeline.

## 2. One model API, kind-dispatched

The editing surface (`canAdd/add/removeId/removeSlot/contains/count/freeSlot/
clear/clone/equal`) and the resolver (`resolveAtLevel`) dispatch on kind, so
the codex right-click, the traits tab, the meters and `applyDiff` never learn
which system they are speaking to:

* **flat** — the pre-timeline id-array ops. `resolveAtLevel` returns the ids
  verbatim: a flat set is level-independent, the client's own sync-disable
  handles the rest (the old, field-proven behavior).
* **levels** — the id-array ops against ONE BUILD at a time. The Sets tab
  edits a **draft** (`setmodel.draft(entry, level)` → `{kind, draft=true,
  name, level, ids}`), exactly the 2026-08-06 model: band ceilings (slots,
  band-top spell level, the rung's budget via `blu.rungCap`) gate the draft's
  adds. `resolveAtLevel(entry, L)` = `groupIds(entry, groupPick(entry, L))` —
  the band's own build, else the base build (else the nearest built band when
  the base is empty).
* **timeline** — untouched.

The whole group API returns from history (`163b102`): `LEVELS/rungFor/bandTop/
slotMax/countIds/normalizeGroup/groupBuild/groupIds/groupPut/groupAdd/
groupRemove/groupFree/groupLevels/groupTop/groupPick/copyInto/draft/usableFrom`,
plus `blu.rungCap`. `ruleOf/setRule` return too, armed by the watcher (§5).
Band-sweep enforcement (`bandViolations/enforcedViolations`) is timeline
math and answers `{}` for the other kinds.

## 3. Creation — the chooser, and the setting

**New** no longer creates a set; it opens the type chooser in the middle
column: three rows, each the kind's name plus its recommendation line,
`cfg.newSetKind` listed first and preselected (Enter/click = take it),
Cancel returns to what was being edited. `cfg.newSetKind` ('flat' default)
is on the Settings tab as **"New sets start as"** — this is the "which one
gets chosen first" setting: it orders and preselects the chooser, it never
converts anything.

A set's kind shows on its saved-set row tooltip and next to the name box.
There is deliberately NO convert-in-place in this slice; Read-current into a
new set of another kind is the escape hatch.

## 4. Persistence

* **Ashita settings (standalone):** tables, `kind` rides along; adoptCfg
  stamps missing kinds by shape (§1) and normalizes per kind
  (`normalizeGroup` for levels, chain completion for timeline).
  `setsModelVer = 3`.
* **dlac store:** new key `sets3`, `#v3` header, one line per set,
  kind-tagged and tab-separated:
  * `flat<TAB>name<TAB>id,id,...`
  * `levels<TAB>name<TAB>id,id,...<TAB>41:id,id,...<TAB>71:id,...` (base
    first, then `level:csv` per build; a stored rule rides as `rule:key`)
  * `timeline<TAB>name<TAB>builtFor<TAB>chains` (the sets2 line, tagged)
  * Readers prefer `sets3` → `sets2` (timeline kinds) → `sets` (flat kinds).
    `sets2` (timeline sets as-is, other kinds as their 75-ids one-entry
    chains) and `sets` (every set's flat ids) stay dual-written so older
    modules still read something usable. Backups ride `sets2bak`,
    KIND-SHAPED since the fourth slice (a timeline backup's line is
    unchanged; flat/levels lines tag their kind in the third token).

## 5. The level-change watcher (built in the second slice, same day)

The old per-set rule returns, kind-gated. ONE LAW: **the level-change
behavior belongs to the set you last APPLIED** (`cfg.lastAppliedSet`, by
name — every successful apply of a saved set records it; an unsaved draft
clears it). When the level settles:

* followed set is the **levels kind** → its rule runs (`ruleOf`, derived
  restore-while-flat / switch-with-levels, a stored pick standing):
  **Switch** equips the band's own build outright on a band crossing
  (diff-checked — a change that moves nothing sends nothing, and its own
  chat line replaces the level-down report); everywhere a band has no
  build, and under **Restore**, the adds-only `blu.restoreMissing` path
  puts back what the change stripped (back from its 2026-08-08
  retirement). A level DOWN sends nothing — the client's own disable
  covers it.
* anything else → the timeline re-plan check, exactly as before — and it
  **stands down** while a levels rule is armed: never two writers on one
  level change.

The rule is picked per set from the combo under the name box (Henrik's
wording verbatim), and the quiet-why line beneath it says which of the
three silences is happening: the beat not arriving (`watchAlive`), nothing
applied yet, or another set being the followed one.

## 6. Kind conversion in place (built in the third slice, same day)

A SAVED set may become another kind — **Convert...** under the name box.
THE FLAT PROJECTION IS THE BRIDGE: what the set plans at the cap (a flat
set's ids, a levels set's BASE build, a timeline's Lv.75 mirror) crosses;
whatever it cannot carry is dropped, and `setmodel.convertLoss` NAMES it —
a levels set's band builds and stored rule, a timeline's beyond-the-plan
entries (or, when every spell survives, its activation timing) and its
backups — as warn lines under each target button and again in the note
after. A lossy convert takes two clicks (the 4s confirm, the Read-current
pattern); a lossless one takes one. Converting works from the SAVED set,
so unsaved edits must be settled first (the panel says so instead of
guessing). `convertTo` never mutates its source; flat → timeline lays out
by sorted placement, exactly the old v2 migration. The followed-set name
survives conversion, so the level-change watcher simply obeys the new
kind from then on.

This replaces the "Read current into a new set" escape hatch named in §3.

## 7. Backups for every kind (built in the fourth slice, same day)

The backup ring is no longer a timeline privilege. A backup is
**kind-shaped** — it banks its source's authorship as its kind holds it
(flat: ids; levels: base + builds + rule; timeline: builtFor + chains,
byte-compatible with the v2 lines) — and `restoreBackup` restores a
backup of ANY kind, flipping the set back when they differ and clearing
the other kinds' fields so nothing shadows. That is what closes the
conversion loop: **Convert carries the ring across and banks the state
being left as backup 1, so a lossy conversion is undoable** (and the
undo banks what it replaced, so it is undoable in turn). Save-over banks
for every kind now — a levels draft banks the whole entry before
groupPut lands — the right-click ring opens on every saved row, and
`convertLoss` no longer names backups, because they are not lost.

Nothing from the plan is parked anymore.

## 8. Share / Import from text (built in the fifth slice, same day)

The dlac friend-share flow, scaled to one set. **Share...** (beside
Convert..., saved sets only) shows the set as ONE line --
`BDXSET1|kind|name|payload|crc4`, no tabs anywhere, so chat, Discord and
clipboards carry it whole -- with a copy-source text box and a
Copy-to-clipboard button (degrading to select-and-Ctrl+C when the
binding has no clipboard). **Import from text** (under Import blusets)
parses a paste LIVE, dlac-style: the moment the line lands it is named
("Recognized: ... - a Slotlist set, 12 spells, built for Lv.75") or
refused with a reason; chat framing around the line is tolerated, a
failed checksum refuses the paste whole (never half a set), and a name
collision imports under a numbered name, never clobbering. Backups do
not travel -- the text is the set's authorship, not its history.
`setmodel.shareText` / `parseShare` are pure and smoke-pinned.

## 9. Proof

Smoke: the old `level builds` sections return (they test the group API,
which is back verbatim), plus a `set kinds` section: kindOf inference,
per-kind new/clone/equal, per-kind resolveAtLevel semantics (flat verbatim;
levels band-else-base; timeline chains), the v3 adopt stamping, and the
sets3 codec round-trip. The watcher is driven end to end against a stub
client (`smoke: the level-change rule`): the band switch and its silences,
the adds-only restore, the down-report suppression, the re-plan stand-down,
and the kind gate. Field: the checklist grows one line per kind — create
via the chooser, build, apply, relog, see it come back — plus one live
band-crossing under Lvl Set Switch, the packet-sending case.
