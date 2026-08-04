# Bludex — Session Handover

**Date:** 2026-08-04 (night build)
**Repo:** https://github.com/henkpoa/bludex — public, `main` + `dev` (all work on `dev`, dev→main only on Henrik's go, the dlac branch law)
**State:** v0.1.0 skeleton **live in game and rendering**. Codex confirmed working; Sets/Traits tabs built but not yet field-tested.

---

## 1. What exists and what is proven

| Piece | State |
|---|---|
| Icon grid (Codex tab), 135 spells, filters row, tab row | **FIELD-CONFIRMED** — screenshot 03:26, icons look great |
| Live set-point budget in the header | **FIELD-CONFIRMED** — showed `0 / 79`, exactly Henrik's real total, CEXI custom bonuses included (read from client memory via the blusets signature, `lib/blu.lua points()`) |
| Red frames behind icons | **FIXED** `cf661f1` — ImageButton frames drew the default theme's red Button color; now transparent with soft blue hover. **Not yet re-checked in game** (fix landed as Henrik logged off) |
| Detail panel (click a spell → 320px sprite + all data) | **UNKNOWN** — grid ran to the window edge in the screenshot; possibly cropped, possibly not rendering. **First thing to check next session.** |
| Sets tab (saved sets, 20 slots, meters, Apply/Read/Clear, quick-add) | Built, compiles, logic smoke-tested — **never opened in game** |
| Traits tab (ladders, feeders, add-for-next-tier) | Built, compiles — **never opened in game** |
| Apply-in-game (0x102 packets, safe mode, 1.1s delays, skips unlearned) | Ported from blusets, **NEVER FIRED**. Test deliberately: on BLU, a 2-3 spell set first, watch the chat log. It resets the current set before applying. |
| `/bludex` `/bdx` toggle, `list`, `apply <name>` | Toggle confirmed; list/apply untested |
| Headless smoke (`tools/smoke.lua`, 23 checks) | Green. Run from `Ashita/addons/`: `lua bludex/tools/smoke.lua` |

## 2. Bugs found and fixed tonight (the lessons)

1. **`package.path` bootstrap** — `require('bludex\\lib\\X')` needs
   `package.path = package.path .. ';' .. AshitaCore:GetInstallPath() .. 'addons\\?.lua'`
   in the entry file (dlac.lua:52 has the same line). Without it: module-not-found at load. `4428d09`.
2. **ImageButton frames are style-colored** — the red squares. Push transparent Button + blue Hovered/Active around every sprite ImageButton. `cf661f1`.
3. Carried dlac laws that prevented worse: printf-escape on ALL drawn text, presence-guard every widget, **no BeginTabBar** (not field-proven in this install — tabs are lit/unlit buttons), keep texture OBJECTS referenced or D3D frees them and imgui draws a dangling pointer.

## 3. Open items, in order

1. **Verify the detail panel renders** (click a spell). If missing: suspect the `BeginChild('bdxgrid', {gridW,0})` width math (`ui/spellsui.lua` `render`, `GetContentRegionAvail` handling).
2. **Confirm the red-frame fix** looks right.
3. **Field-test the Sets tab end to end**: build a small set → Save → relog-persistence → Read current → **Apply in game** (carefully, see §1) → verify in the game's own blue magic menu.
4. **Traits tab field pass.**
5. Cosmetic: filter combos clip their labels ("All eleme▼") — widen (`ui/spellsui.lua` combo widths 100-150 → ~130-170).
6. **UI chrome icons** — Henrik generates from `ICONS_WANTED.md` (all optional, everything has fallbacks; drop into `icons/ui/`, no code change).
7. Later: settings UI (applyDelay, budgetOverride), filter persistence, README screenshots, dev→main + version bump when Henrik approves.

## 4. Data state (unchanged tonight except MP)

- 136 spells (135 castable), coverage: 123 full public-SQL rows, Glutinous Dart commented-row + field, 8 SoA `field` (set cost 8 + MP 116 each, **"retail values" per Henrik** — raises confidence for seeding the rest from retail), 4 stubs (Thunderbolt + Unbridled trio; trio zeros are correct semantics).
- **Field facts banked:** Assimilation = +2/merit (CEXI custom); budget GROWS with spells learned, Henrik at 79 expecting 80; Thunderbolt = Unbridled + **Lengua Regia** food gate (full note on the row).
- **Remaining verify tail (thin, nothing blocks UI):** castTime for the 8 SoA spells + Carcharian Verve mpCost; which trait the 8 SoA spells feed; spellType eyeball-confirmation on the 24 scriptless rows (element law: None ⇒ Physical, else Magical — held for all 111 scripted spells).
- Regeneration is in the data as `castable=false` — whether the UI ever shows it is a filter decision, still Henrik's.

## 5. Architecture map

```
bludex.lua          entry: package.path bootstrap FIRST, settings lib, events, commands
lib/blu.lua         blusets port (GPL-3, credited): live budget, live set, 0x102 apply
lib/spellbook.lua   data service: indexes, learned(), filter engine, hints
lib/setmodel.lua    pure set logic: totals, stats, trait ladder (mirrors CalculateTraits)
ui/kit.lua          guarded widgets, printf-escape, blue palette, lit-button tabs
ui/filetex.lua      D3DX texture loader (KEEP the object or crash)
ui/host.lua         window shell, theme, header budget, tab dispatch (pcall per tab)
ui/spellsui.lua     Codex: filters + grid + detail (detail reused by Sets ctx)
ui/setsui.lua       Sets: saved list / slot grid + meters + game actions / stats+traits
ui/traitsui.lua     Traits: ladders + feeders + quick add
data/*.lua          GENERATED — never hand-edit; tools/generate_spells.py regenerates
                    (field values live in FIELD_* dicts INSIDE the generator)
icons/<Cat>/<Name>-320|-128-halo|-64-halo.png   408 files, complete
```

## 6. How to verify from scratch

```
/addon load bludex     (or /addon reload bludex)
/bdx                   → window; header should read "Blue Magic Points: <spent> / 79" on BLU
lua bludex/tools/smoke.lua   (from Ashita/addons/, headless: 23 checks)
python bludex/tools/generate_spells.py [--deploy-icons]   (regenerate data)
```

Asset masters + the icon-audit handover (authority map, the submodule trap, learn-vs-cast
gates) live in `C:\Users\Henrik Johansson\OneDrive\Bilder\BLU\HANDOVER.md`.
