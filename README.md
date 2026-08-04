# Bludex

**The Blue Mage codex for [Ashita v4](https://www.ashitaxi.com/) on [CatsEyeXI](https://catseyexi.com/)** — a filterable
spell reference and visual set planner, with hand-made icons for every spell.

Bludex combines what `blucheck` and `blusets` did — and goes further:

- **Spell codex** — every blue magic spell castable at the level-75 cap (including all
  CatsEyeXI additions), filterable by name, category, element, spell type, trait, and
  learned/missing. Each spell shows its icon, stats, set-point cost, MP, cast/recast,
  skillchain properties, magic-burst windows, stat bonuses, trait contribution, and
  where to learn it.
- **Set planner** — build spell sets in a GUI: 20 slots, a live set-point budget read
  from the game (CatsEyeXI's custom merit/learning bonuses included), total stat and
  trait summaries for the set, and one click to apply the set in game.
- **Trait explorer** — see every blue trait ladder (Dual Wield, Attack Bonus, …), which
  of your spells feed it, and what to set for the next tier.

## Status

Work in progress — pre-release.

## Data provenance

`data/*.lua` are **generated** by `tools/generate_spells.py` from local sources: the
public CatsEyeXI server repository (base values), the client DAT (names, availability),
and in-game field verification on CatsEyeXI. Every spell row carries a `src` marker and,
where a value is still unconfirmed, a `verify` list. Do not hand-edit generated files —
fix the generator inputs instead.

Spell icons are original artwork (AI-assisted, hand-curated) — three sizes per spell.

## Credits

- **atom0s / Ashita Development Team** — the `blusets` memory/packet layer this addon's
  in-game set application is ported from, and `blucheck`'s learned-spell detection
  approach and learn-location data. Both GPL-3, gratefully reused.
- **CatsEyeXI** — the server that makes level-75 Blue Mage this interesting.

## License

GPL-3.0 — see [LICENSE](LICENSE).
