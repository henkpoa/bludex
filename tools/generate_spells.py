#!/usr/bin/env python3
"""
generate_spells.py -- builds bludex/data/spells.lua + bludex/data/traits.lua

Sources (all local, never fetched):
  1. HANDOVER.md appendix        -> master list: the 136 icons (name/id/class/element/stock)
                                    THE availability authority (client-DAT-derived, field-checked)
  2. sql/spell_list.sql          -> mpCost, castTime, recastTime, AOE, range, element,
                                    validTargets, requirements (unbridled bit), slug->id
  3. sql/blue_spell_list.sql     -> set points, trait category+weight, skillchain props
  4. sql/blue_spell_mods.sql     -> stat bonuses while set
  5. sql/blue_traits.sql         -> trait ladder SHAPE only (which modifiers a
                                    category moves, which trait id owns a rung).
                                    The SCALE and the rung VALUES come from
                                    bg-wiki -- see WIKI_LADDER for why.
  6. sql/traits.sql              -> traitid -> display name
  7. src/map/modifier.h          -> mod id -> enum name
  8. scripts/enum/skillchain_type.lua -> sc id -> name (+ element comments -> burst map)
  9. scripts/actions/spells/blue/*.lua -> spellType/damageType/ecosystem + header cross-checks

PROVENANCE: every spell row carries src= 'sql' | 'sql-commented' | 'stub' | 'missing'.
All SQL values are BASE-LSB: CatsEyeXI's overrides live in private submodules
(modules/catseyexi, src/map/cexi) that the public clone never checks out.
Rows that need in-game confirmation carry a verify={...} list.
"""

import os
import re
import sys
import glob
import datetime
from collections import OrderedDict

CLONE  = r"C:\Users\Henrik Johansson\scripts\catseyexi"
ASSETS = r"C:\Users\Henrik Johansson\OneDrive\Bilder\BLU"
HERE   = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "..", "data")

HANDOVER = os.path.join(ASSETS, "HANDOVER.md")

# Icon sprite variants (per spell, under <Category>/sprites/): "<Name><suffix>"
VARIANTS = OrderedDict((("detail", "-320.png"),
                        ("grid128", "-128-halo.png"),
                        ("grid64", "-64-halo.png")))

# ---- FIELD-VERIFIED values (Henrik, in game, 2026-08-04) -------------------
# These fill/override base-LSB gaps; regeneration preserves them.
FIELD_SET_POINTS = {
    719: 8, 720: 8, 721: 8, 722: 8,      # Searing Tempest / Spectral Floe /
    725: 8, 726: 8, 727: 8, 728: 8,      #   Anvil Lightning / Entomb / Blinding
                                         #   Fulgor / Scouring Spate / Silent
                                         #   Storm / Tenebral Crush -- 8 each
    706: 2,                              # Glutinous Dart (confirms commented row)
}
FIELD_MP = {
    706: 16,                             # Glutinous Dart
    719: 116, 720: 116, 721: 116, 722: 116,   # the 8 SoA burst spells all
    725: 116, 726: 116, 727: 116, 728: 116,   #   cost 116 MP (retail values)
}
FIELD_UNBRIDLED = {736}                  # Thunderbolt: Unbridled + food gate
# base LSB has no blue_spell_mods rows for the cexi75 SoA spells; all eight
# read off the live stats in game (Henrik, 2026-08-04)
FIELD_MODS = {
    719: [("MP", 30), ("STR", 8)],                            # Searing Tempest
    720: [("MP", 30), ("INT", 8)],                            # Spectral Floe
    721: [("MP", 30), ("DEX", 8)],                            # Anvil Lightning
    722: [("MP", 30), ("VIT", 8)],                            # Entomb
    725: [("HP", 40), ("STR", 4), ("AGI", 4)],                # Blinding Fulgor
    726: [("MP", 30), ("MND", 8)],                            # Scouring Spate
    727: [("MP", 30), ("AGI", 8)],                            # Silent Storm
    728: [("MP", 30), ("VIT", 4), ("INT", 4), ("MND", 4)],    # Tenebral Crush
}
FIELD_NOTES = {
    736: "Granted by the food Lengua Regia -- never learned from a mob. "
         "With that food up AND Unbridled Learning active, a Lv.75 BLU can "
         "cast it; casting deactivates Unbridled Learning. AoE stun 10-15s, "
         "not subject to Anvil Lightning's level/NM scaling. "
         "Lengua Regia (Cooking 105 / Alchemy 60): Fire Crystal, Behemoth "
         "Tongue, Chimera Blood, Mithran Tomato, Dried Marjoram, Black "
         "Pepper -- and it carries DEX+4, MND+3, Refresh+1, Magic Accuracy "
         "+15% (max 25) and Blue magic recast -5%.",
}
# NOT LEARNED THE ORDINARY WAY (Henrik 2026-08-10, sixth round: "remove
# thunderbolt as a learnable spell ... only eating a certain food will give
# you the ability to cast it"). These stay in the codex -- they are real
# spells and worth reading about -- but they are not something you can go
# out and learn, so nothing counts them as missing or draws them in the
# unlearned red. The value names what DOES grant them.
FIELD_GRANTED = {
    736: "the food Lengua Regia (cooked from behemoth tongue)",
}

# ---- WIKI-SOURCED values (bg-wiki, 2026-08-08) -----------------------------
# The eight SoA burst spells' TRAIT CATEGORIES. Henrik's call: the wiki is the
# authority for everything but the level -- traits, MP cost etc. are the same
# on CatsEyeXI. Stat bonuses were cross-checked the same day and MATCH the
# 2026-08-04 field readings above, so FIELD_MODS stands as-is.
#   719 Searing Tempest  -> Attack Bonus      (cat 8)
#   720 Spectral Floe    -> Magic Atk. Bonus  (cat 6)
#   721 Anvil Lightning  -> Accuracy Bonus    (cat 16)
#   722 Entomb           -> Defense Bonus     (cat 11)
#   725 Blinding Fulgor  -> Magic Eva. Bonus  (cat 201 -- addendum below)
#   726 Scouring Spate   -> Magic Def. Bonus  (cat 13)
#   727 Silent Storm     -> Evasion Bonus     (cat 18)
#   728 Tenebral Crush   -> Magic Acc. Bonus  (cat 202 -- addendum below)
# The WEIGHT is no longer carried here: WIKI_FEEDER_POINTS below sets every
# feeder's trait points, these eight included (all 8, being lv99-tier spells).
WIKI_TRAIT_CATS = {
    719: 8, 720: 6, 721: 16, 722: 11,
    725: 201, 726: 13, 727: 18, 728: 202,
}

# ---- THE TRAIT-POINT SCALE (bg-wiki, scraped 2026-08-11) -------------------
# WHY THIS EXISTS. base-LSB's blue trait data mixes TWO SCALES. The bulk of
# blue_spell_list carries a legacy "1 unit" weight and blue_traits asks for 2
# points per tier; but later rows were entered with the REAL bg-wiki trait
# points and never converted -- Auto Refresh (cat 14) matches the wiki exactly,
# Max Hp Boost's thresholds (8/16/24/32) are already wiki-scale, and stray rows
# like Embalming Earth sit at 8 inside an otherwise-legacy ladder. Mixing them
# is what made Searing Tempest alone out-weigh five era spells put together.
#
# It also cost every "Bonus" ladder its upper rungs: the wiki is explicit that
# a Blue Mage climbs Attack Bonus to tier V through spells. LSB ships one rung.
#
# So: the wiki is the authority for the whole scale, per Henrik's standing
# rule. EVERY trait costs 8 trait points per tier -- no exceptions across all
# 30 categories. What varies is what each spell CONTRIBUTES.
WIKI_POINTS_PER_TIER = 8

# category -> (trait points a feeder contributes, {spell name: override}).
# Most categories pay 4 per era spell and 8 per lv99 spell. Three do not:
# Skillchain Bonus and Mag. Burst Bonus pay 6, Gilfinder pays 6, and Auto
# Refresh is per-spell all the way down (which is exactly how LSB has it).
WIKI_FEEDER_POINTS = {
    1:  (4, {"Nectarous Deluge": 8}),
    2:  (4, {}),
    3:  (4, {"Sweeping Gouge": 8}),
    4:  (4, {}),
    5:  (4, {}),
    6:  (4, {"Subduction": 8, "Spectral Floe": 8}),
    7:  (4, {}),
    8:  (4, {"Embalming Earth": 8, "Searing Tempest": 8}),
    9:  (4, {}),
    10: (4, {}),
    11: (4, {"Atra. Libations": 8, "Entomb": 8}),
    12: (4, {}),
    13: (4, {"Rending Deluge": 8, "Scouring Spate": 8}),
    14: (1, {"Frightful Roar": 2, "Self-Destruct": 2, "Light of Penance": 2,
             "Voracious Trunk": 3, "Actinic Burst": 4, "Plasma Charge": 4,
             "Winds of Promyvion": 4}),
    15: (4, {"Restoral": 8}),
    16: (4, {"Nature's Meditation": 8, "Anvil Lightning": 8}),
    17: (4, {"Retinal Glare": 8}),
    18: (4, {"Tempestuous Upheaval": 8, "Silent Storm": 8}),
    19: (4, {}),
    20: (4, {"Diffusion Ray": 8}),
    21: (4, {}),
    22: (4, {"Erratic Flutter": 8}),
    23: (6, {"Paralyzing Triad": 8}),
    24: (4, {"Thrashing Assault": 8}),
    25: (4, {"Molting Plumage": 8}),
    26: (4, {}),
    27: (6, {"Rail Cannon": 8}),
    28: (6, {}),
    201: (8, {}),
    202: (8, {}),
}

# category -> (confidence, [rung values]). Rung N sits at N*8 trait points.
#
# WHERE A LADDER STOPS (Henrik, 2026-08-11, second pass -- he caught Auto
# Refresh advertising a rung 2 that does not exist for us). The cut is NOT
# "however many rungs the feeder spells can pay for". It is the wiki's job
# trait table, whose "Level Obtained" column names the jobs that can hold each
# tier, with two footnote markers that decide everything:
#
#     BLU63*   single asterisk -- "requires the setting of appropriate
#              spells": REACHABLE, this rung belongs on the ladder
#     BLU99**  double asterisk -- "requires the 100 or 1,200 Blue Mage job
#              gift": NOT reachable by setting spells, cut it
#     (absent) the tier is some other job's entirely -- Auto Refresh II is
#              SMN90 and nothing else, so blue magic stops at rung 1
#
# So: cut at the last tier carrying a SINGLE-asterisk BLU entry. The feeder
# arithmetic is kept only as a cross-check -- the two agree on eight of the
# twelve multi-rung ladders, and where they disagree the asterisk is right and
# tighter (Clear Mind's twelve feeders pay for six rungs; blue magic gets four).
#
# The value is in the SAME UNIT as LSB's modifier for that category, which is
# why the wiki's percentages are not always usable:
#   'wiki'   -- the wiki's ladder is in LSB's unit; taken as-is. Where LSB
#               shipped a rung, its value MATCHES (Attack Bonus 10, Dual Wield
#               10/15/25, Double Attack 7, Triple Attack 5, Zanshin 15 ...),
#               which is the cross-check that the whole scale is right.
#   'verify' -- unit mismatch or the wiki is silent. Rung 1 keeps LSB's
#               shipped value; anything above it is a reasoned guess and
#               every rung is flagged for the field.
WIKI_LADDER = {
    1:  ("wiki",   [8, 10, 12]),
    2:  ("wiki",   [1]),
    3:  ("wiki",   [8, 10]),
    4:  ("wiki",   [1, 2, 3, 4]),    # V/VI are BLU99** -- job gift, not spells
    5:  ("wiki",   [10, 15]),        # III/IV are BLU99**
    6:  ("wiki",   [20, 24, 28, 32]),      # V/VI are BLU99**
    7:  ("wiki",   [8]),
    8:  ("wiki",   [10, 22, 35, 48]),      # V/VI are BLU99**
    9:  ("wiki",   [25]),            # II/III are BLU99**
    10: ("wiki",   [10, 20]),
    11: ("wiki",   [10, 22, 35, 48]),
    12: ("wiki",   [8]),
    13: ("wiki",   [10, 12, 14]),
    14: ("wiki",   [1]),             # tier II is SMN90 ALONE -- no BLU entry
    15: ("wiki",   [30, 60, 120, 180]),
    16: ("wiki",   [10, 22, 35, 48]),
    17: ("wiki",   [25, 28, 31]),
    18: ("wiki",   [10, 22, 35]),
    19: ("wiki",   [10]),            # II/III are BLU99**
    20: ("wiki",   [10, 15, 20]),
    21: ("wiki",   [10, 12]),
    22: ("wiki",   [5, 10, 15]),     # BLU starts at the wiki's Tier 0 (5%) and
                                     # climbs 0/I/II; LSB's 15 on rung 2 had
                                     # skipped Tier I. III+ are BLU99**
    23: ("wiki",   [8, 12, 16]),
    24: ("wiki",   [(15, 7), (16, 5)]),   # Double Attack -> Triple Attack
    25: ("wiki",   [10, 15, 25, 30]),
    26: ("wiki",   [15]),
    27: ("wiki",   [5, 7, 9]),
    28: ("wiki",   [(20, 1), (19, 1)]),   # Gilfinder -> Treasure Hunter
    201: ("wiki",  [10]),
    202: ("wiki",  [10]),
}

# Trait categories base-LSB's blue_traits.sql does not know (the June 2015
# trait additions). These ids are BLUDEX-INTERNAL -- they never cross the wire,
# traitEval sums per category locally. They sit at 201/202 and NOT at 29/30
# because LSB already uses trait_category 29 for a real spell (Foul Waters);
# squatting on a live id would have mis-fed the ladder the day that spell
# landed. The traitIds are LSB trait.h's TRAIT_MAGIC_ACC_BONUS=125 /
# TRAIT_MAGIC_EVA_BONUS=126; bg-wiki confirms both ladders at 8 points for +10.
WIKI_TRAIT_CATEGORIES = [
    (201, "Magic Eva. Bonus", 126, "MEVA"),
    (202, "Magic Acc. Bonus", 125, "MACC"),
]

warnings = []
def warn(msg):
    warnings.append(msg)
    print("  [warn] " + msg)

# ---------------------------------------------------------------- 1. handover
def parse_handover():
    """Appendix tables: | Icon file | id | Class | Element | stock |"""
    text = open(HANDOVER, encoding="utf-8").read()
    spells = OrderedDict()
    section = None
    for line in text.splitlines():
        m = re.match(r"^### (Buff|Debuff|Healing|Offensive)\s", line)
        if m:
            section = m.group(1)
            continue
        if section is None or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 5 or cells[0] in ("Icon file", "---"):
            continue
        if set(cells[0]) <= set("- "):
            continue
        name, sid, klass, element, stock = cells
        if not sid.isdigit():
            continue
        sid = int(sid)
        spells[sid] = {
            "name": name, "id": sid, "category": section,
            "class": klass, "element": element,
            "stock": None if stock in ("n/a", "") else int(stock),
        }
    return spells

# ---------------------------------------------------------------- sql helpers
def sql_rows(path, table):
    """Yield (commented, [values]) for INSERT rows of `table`. Values split
    on top-level commas; quoted strings unquoted; @VARS kept symbolic."""
    rx = re.compile(r"^(--\s*)?INSERT INTO `" + table + r"` VALUES\s*\((.*)\);\s*(--.*)?$")
    for line in open(path, encoding="utf-8"):
        m = rx.match(line.strip())
        if not m:
            continue
        commented = bool(m.group(1))
        raw = m.group(2)
        vals, cur, inq = [], "", False
        for ch in raw:
            if ch == "'" :
                inq = not inq
                cur += ch
            elif ch == "," and not inq:
                vals.append(cur.strip()); cur = ""
            else:
                cur += ch
        vals.append(cur.strip())
        yield commented, vals

def unq(s):
    s = s.strip()
    if s.startswith("'") and s.endswith("'"):
        return s[1:-1]
    return s

# ---------------------------------------------------------------- 2. spell_list
# columns: spellid,name,jobs,group,family,element,zonemisc,validTargets,skill,
#          mpCost,castTime,recastTime,message,magicBurstMessage,animation,
#          animationTime,AOE,base,multiplier,CE,VE,requirements,spell_range,radius,content_tag
REQUIREMENT_UNBRIDLED = 16

def parse_spell_list():
    out = {}
    path = os.path.join(CLONE, "sql", "spell_list.sql")
    for commented, v in sql_rows(path, "spell_list"):
        if len(v) < 24:
            continue
        skill = v[8]
        if skill not in ("@SKILL_BLUE", "43"):
            continue
        sid = int(v[0])
        elem = v[5].replace("@ELEMENT_", "").title() if v[5].startswith("@") else v[5]
        out[sid] = {
            "slug": unq(v[1]), "element": elem,
            "validTargets": int(v[7]), "mpCost": int(v[9]),
            "castTime": int(v[10]) / 1000.0, "recastTime": int(v[11]) / 1000.0,
            "aoe": int(v[16]), "requirements": int(v[21]),
            "range": int(v[22]), "radius": int(v[23]),
            "commented": commented,
        }
    return out

# ---------------------------------------------------------------- 3-5. blue sql
def parse_blue_spell_list():
    out = {}
    path = os.path.join(CLONE, "sql", "blue_spell_list.sql")
    for commented, v in sql_rows(path, "blue_spell_list"):
        if len(v) != 8:
            continue
        sid = int(v[0])
        if sid in out:            # Plenilune Embrace has two mob_skill_id rows
            continue
        row = {
            "setPoints": int(v[2]), "traitCat": int(v[3]), "traitWeight": int(v[4]),
            "sc": [int(v[5]), int(v[6]), int(v[7])],
            "commented": commented,
        }
        row["stub"] = (row["setPoints"] == 0 and row["traitCat"] == 0
                       and row["sc"] == [0, 0, 0])
        out[sid] = row
    return out

def parse_blue_spell_mods():
    out = {}
    path = os.path.join(CLONE, "sql", "blue_spell_mods.sql")
    for commented, v in sql_rows(path, "blue_spell_mods"):
        if len(v) != 3:
            continue
        sid, modid, val = int(v[0]), int(v[1]), int(v[2])
        if modid == 0:
            continue                      # "No Stats" placeholder rows
        out.setdefault(sid, []).append((modid, val))
    return out

def parse_blue_traits(modnames):
    """category -> {traitId (the ladder's name-bearing id), tiers{points:{traitId,mods}}}

    THE TRAIT ID IS PER TIER, not per category: category 24 is trait 15
    (Double Attack) at 8 points and trait 16 (Triple Attack) at 16; category 28
    is 20 (Gilfinder) then 19 (Treasure Hunter). blueutils suppresses a blue
    trait by ID against the job traits, so a per-category id would answer for
    the wrong tier (see lib/traitsource.lua).

    LSB supplies the SHAPE -- which modifiers a category moves, and which trait
    id owns each rung. bg-wiki supplies the SCALE -- 8 trait points per rung --
    and the rung VALUES, including the upper rungs LSB never shipped. See the
    WIKI_LADDER header for why LSB's own numbers cannot be used directly."""
    lsb = {}
    path = os.path.join(CLONE, "sql", "blue_traits.sql")
    for commented, v in sql_rows(path, "blue_traits"):
        if commented or len(v) != 5:
            continue
        cat, pts, tid, mod, val = (int(x) for x in v)
        lsb.setdefault(cat, {})
        rung = lsb[cat].setdefault(pts, {"traitId": tid, "mods": []})
        if rung["traitId"] != tid:
            warn("blue_traits cat %d @%dpts mixes trait ids %d and %d"
                 % (cat, pts, rung["traitId"], tid))
        rung["mods"].append(mod)

    modids = {}
    for mid, mname in modnames.items():
        modids.setdefault(mname, mid)
    _MODNAMES_FOR_WARN.update(modnames)

    # the two categories LSB has no rows for at all
    for cat, tname, tid, stat in WIKI_TRAIT_CATEGORIES:
        mid = modids.get(stat)
        if mid is None:
            warn("modifier.h has no %s -- cat %d cannot be built" % (stat, cat))
            continue
        lsb[cat] = {WIKI_POINTS_PER_TIER: {"traitId": tid, "mods": [mid]}}

    # THE CROSS-CHECK. A blue rung and a job rank of the SAME trait move the
    # SAME modifier, so the blue rung's value must appear somewhere on that
    # trait's job ladder -- and sql/traits.sql's job side is well-maintained
    # where the blue side is not. This is what caught Resist Sleep sitting at
    # SLEEPRES 2 when the real ladder is 10/15/20/25/30 (Henrik 2026-08-11).
    # Exempt ladders carry their reason; everything else must reconcile.
    XCHECK_EXEMPT = {
        1:  "blue climbs to tier III (BLU99*); LSB's job table stops at BST's two ranks",
        4:  "job Clear Mind grants MPHEAL (mod 71), the blue ladder CLEAR_MIND "
            "(mod 295) -- different modifiers, so the values cannot compare",
        22: "rung 1 is the wiki's Tier 0 (5%), which no job holds; rungs 2/3 do "
            "match RDM's 10/15",
        24: "rung 1 is the wiki's Tier 0 (7%), BLU-only; rung 2 is Triple Attack",
    }

    out = {}
    for cat in sorted(lsb):
        shape = [lsb[cat][p] for p in sorted(lsb[cat])]
        if cat not in WIKI_LADDER:
            warn("cat %d has no WIKI_LADDER entry -- left on the LSB scale" % cat)
            out[cat] = {"traitId": shape[0]["traitId"], "confidence": "lsb",
                        "tiers": {p: {"traitId": lsb[cat][p]["traitId"],
                                      "mods": [(m, 0) for m in lsb[cat][p]["mods"]]}
                                  for p in lsb[cat]}}
            continue
        confidence, ladder = WIKI_LADDER[cat]
        tiers = {}
        for i, entry in enumerate(ladder):
            # a rung LSB never shipped reuses the shape of the last one it did
            base = shape[i] if i < len(shape) else shape[-1]
            tid, value = entry if isinstance(entry, tuple) else (base["traitId"], entry)
            tiers[(i + 1) * WIKI_POINTS_PER_TIER] = {
                "traitId": tid, "mods": [(m, value) for m in base["mods"]]}
        out[cat] = {"traitId": shape[0]["traitId"], "confidence": confidence,
                    "tiers": tiers}

    jobvals = job_trait_values()
    for cat, tinfo in sorted(out.items()):
        if cat in XCHECK_EXEMPT:
            continue
        for pts in sorted(tinfo["tiers"]):
            tier = tinfo["tiers"][pts]
            for mod, val in tier["mods"]:
                ladder = jobvals.get(tier["traitId"], {}).get(mod)
                if ladder and val not in ladder:
                    warn("cat %d @%dpts: %s %d is nowhere on trait %d's job "
                         "ladder %s -- blue and job move the SAME modifier, so "
                         "one of them is wrong (the job side is the reliable one)"
                         % (cat, pts, modname_of(mod), val, tier["traitId"],
                            sorted(ladder)))
    return out

def job_trait_values():
    """traitid -> mod -> {every value any job's rank grants}

    The job side of sql/traits.sql, used only to cross-check the blue ladder.
    Unlike blue_traits it is well-maintained and agrees with bg-wiki."""
    out = {}
    path = os.path.join(CLONE, "sql", "traits.sql")
    for commented, v in sql_rows(path, "traits"):
        if commented or len(v) < 7:
            continue
        try:
            tid, mod, val = int(v[0]), int(v[5]), int(v[6])
        except ValueError:
            continue
        out.setdefault(tid, {}).setdefault(mod, set()).add(val)
    return out

_MODNAMES_FOR_WARN = {}
def modname_of(mod):
    return _MODNAMES_FOR_WARN.get(mod, "mod %d" % mod)

# ------------------------------------------------------- 6b. job traits (collisions)
def parse_job_enum():
    """scripts/enum/job.lua -> id -> 'WAR'"""
    out = {}
    path = os.path.join(CLONE, "scripts", "enum", "job.lua")
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*([A-Z]{3})\s*=\s*(\d+),", line)
        if m and int(m.group(2)) > 0:
            out[int(m.group(2))] = m.group(1)
    return out

JOB_NAMES = {
    1: "Warrior", 2: "Monk", 3: "White Mage", 4: "Black Mage", 5: "Red Mage",
    6: "Thief", 7: "Paladin", 8: "Dark Knight", 9: "Beastmaster", 10: "Bard",
    11: "Ranger", 12: "Samurai", 13: "Ninja", 14: "Dragoon", 15: "Summoner",
    16: "Blue Mage", 17: "Corsair", 18: "Puppetmaster", 19: "Dancer",
    20: "Scholar", 21: "Geomancer", 22: "Rune Fencer",
}

def parse_job_traits(blue_ids):
    """sql/traits.sql -> job -> traitid -> [{level, rank, mods, merit, tag}]

    Only the trait ids blue magic can ALSO grant: those are the ones that can
    collide, and nothing else belongs in a blue-magic addon. Rows mirror the
    server's own gate (battleutils::AddTraits): level > 0 and level <= yours,
    highest rank wins per trait id."""
    out = {}
    path = os.path.join(CLONE, "sql", "traits.sql")
    for commented, v in sql_rows(path, "traits"):
        if commented or len(v) < 9:
            continue
        tid, job, level, rank = int(v[0]), int(v[2]), int(v[3]), int(v[4])
        mod, val, merit = int(v[5]), int(v[6]), int(v[8])
        tag = None if v[7].strip().upper() == "NULL" else unq(v[7])
        if tid not in blue_ids or job <= 0 or level <= 0:
            continue
        if merit != 0:
            warn("job trait %d (job %d) is merit-gated (merit %d) and collides "
                 "with a blue trait -- traitsource reports it as conditional"
                 % (tid, job, merit))
        row = (out.setdefault(job, {}).setdefault(tid, {})
                  .setdefault((level, rank),
                              {"level": level, "rank": rank, "mods": [],
                               "merit": merit, "tag": tag}))
        if mod != 0:
            row["mods"].append((mod, val))
    return out

# ---------------------------------------------------------------- 6. trait names
def parse_trait_names():
    names = {}
    path = os.path.join(CLONE, "sql", "traits.sql")
    for commented, v in sql_rows(path, "traits"):
        if commented or len(v) < 2:
            continue
        tid = int(v[0])
        if tid not in names:
            names[tid] = unq(v[1]).title()
    return names

# ---------------------------------------------------------------- 7. modifier.h
def parse_mods():
    path = os.path.join(CLONE, "src", "map", "modifier.h")
    text = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"enum class Mod\b.*?\{(.*?)\n\};", text, re.S)
    if not m:
        sys.exit("could not locate enum class Mod in modifier.h")
    out = {}
    for name, num in re.findall(r"^\s*([A-Z][A-Z_0-9]*)\s*=\s*(\d+)\s*,", m.group(1), re.M):
        out.setdefault(int(num), name)
    return out

# ---------------------------------------------------------------- 8. skillchains
def parse_skillchains():
    path = os.path.join(CLONE, "scripts", "enum", "skillchain_type.lua")
    names, burst = {}, {}
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*([A-Z_]+)\s*=\s*(\d+),\s*--\s*Lv(\d)\s*(.*)", line)
        if not m:
            continue
        name = m.group(1).title().replace("_Ii", " II")
        num, lv, elems = int(m.group(2)), int(m.group(3)), m.group(4)
        names[num] = name
        if lv >= 1 and num > 0:
            for e in re.split(r"[,&]| and ", elems):
                e = e.strip().title()
                if e:
                    burst.setdefault(e, []).append(name)
    return names, burst

# ---------------------------------------------------------------- 9. scripts
HDR_KEYS = {
    "spell type": "spellTypeHdr", "monster type": "monsterHdr",
    "magic bursts on": "burstsHdr", "combos": "combosHdr",
    "blue magic points": "pointsHdr", "stat bonus": "statHdr",
}

def parse_scripts():
    out = {}
    for f in glob.glob(os.path.join(CLONE, "scripts", "actions", "spells", "blue", "*.lua")):
        slug = os.path.splitext(os.path.basename(f))[0]
        text = open(f, encoding="utf-8", errors="replace").read()
        d = {"slug": slug}
        for line in text.splitlines():
            m = re.match(r"--\s*([^:]+):\s*(.+?)\s*$", line.strip())
            if m and m.group(1).strip().lower() in HDR_KEYS:
                d[HDR_KEYS[m.group(1).strip().lower()]] = m.group(2).strip()
        for key, rx in (("ecosystem", r"params\.ecosystem\s*=\s*xi\.ecosystem\.(\w+)"),
                        ("attackType", r"params\.attackType\s*=\s*xi\.attackType\.(\w+)"),
                        ("damageType", r"params\.damageType\s*=\s*xi\.damageType\.(\w+)"),
                        ("scattr", r"params\.scattr\s*=\s*xi\.skillchainType\.(\w+)"),
                        ("numhits", r"params\.numhits\s*=\s*(\d+)")):
            m = re.search(rx, text)
            if m:
                d[key] = m.group(1)
        out[slug] = d
    return out

# ---------------------------------------------------------------- lua writer
def lq(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"

def fmtnum(x):
    if isinstance(x, float):
        return ("%g" % x)
    return str(x)

def lua_list(items):
    return "{ " + ", ".join(items) + " }" if items else "{}"

# ---------------------------------------------------------------- main
def main():
    print("parsing sources...")
    handover   = parse_handover()
    slist      = parse_spell_list()
    blist      = parse_blue_spell_list()
    bmods      = parse_blue_spell_mods()
    traitnames = parse_trait_names()
    modnames   = parse_mods()
    btraits    = parse_blue_traits(modnames)
    scnames, burstmap = parse_skillchains()
    scripts    = parse_scripts()
    slug2id    = {v["slug"]: k for k, v in slist.items()}

    print(f"  handover spells: {len(handover)}   spell_list blue rows: {len(slist)}"
          f"   blue_spell_list: {len(blist)}   scripts: {len(scripts)}")

    # sprite inventory: every spell must have all three size variants
    sprites = set()
    for cat in ("Buff", "Debuff", "Healing", "Offensive"):
        for f in glob.glob(os.path.join(ASSETS, cat, "sprites", "*.png")):
            sprites.add((cat, os.path.basename(f)))

    norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())

    def canon(s):
        """Trait-name comparison: traits.sql uses the game's abbreviations
        ('Magic Atk. Bonus'); scripts spell them out. Same trait."""
        c = norm(s).replace("defense", "\x01").replace("def", "defense").replace("\x01", "defense")
        return c.replace("atk", "attack")

    seen_norm = {}

    rows = []
    counts = {"sql": 0, "sql-commented": 0, "stub": 0, "missing": 0}
    for sid, h in sorted(handover.items()):
        name, klass = h["name"], h["class"]
        castable  = klass != "LEARN-ONLY"
        unbridled = klass == "CEXI-75*"
        level     = 75 if klass.startswith("CEXI-75") else h["stock"]

        n = norm(name)
        if n in seen_norm:
            warn(f"normalized-name collision: {name} vs {seen_norm[n]}")
        seen_norm[n] = name

        for suffix in VARIANTS.values():
            if (h["category"], name + suffix) not in sprites:
                warn(f"sprite missing on disk: {h['category']}/sprites/{name}{suffix}")

        sl = slist.get(sid)
        bl = blist.get(sid)
        verify = []

        if bl is None:
            src = "missing"
            verify += ["setPoints", "trait", "skillchain"]
        elif bl["stub"]:
            src = "stub"
            if not unbridled:
                verify += ["setPoints", "trait"]   # trio zeros are correct semantics
        elif bl["commented"]:
            src = "sql-commented"
            verify += ["setPoints"]
        else:
            src = "sql"
        counts[src] += 1

        if sl is None:
            warn(f"no spell_list row (even commented): {name} ({sid})")
            verify += ["mpCost", "castTime"]
        elif sl["commented"]:
            verify += ["mpCost"]

        sc = scripts.get(sl["slug"]) if sl else None

        # spell type / damage type / ecosystem
        stype = dtype = eco = None
        if sc:
            at = sc.get("attackType")
            if at:
                stype = at.title()
            elif sc.get("spellTypeHdr"):
                stype = sc["spellTypeHdr"].split("(")[0].strip().title()
            if sc.get("damageType"):
                dtype = sc["damageType"].title()
            if sc.get("ecosystem"):
                eco = sc["ecosystem"].replace("_", " ").title()
            elif sc.get("monsterHdr"):
                eco = sc["monsterHdr"]
        if stype is None:
            # No public script (CEXI implements these privately). The DAT element
            # discriminates reliably: physical blue magic carries element None,
            # magical/breath carries its element. Flag for field confirmation.
            stype = "Physical" if h["element"] in ("None", "") else "Magical"
            verify.append("spellType")

        # skillchain properties (SQL authority; script scattr as cross-check)
        chains = []
        if bl and not bl["stub"]:
            chains = [scnames[x] for x in bl["sc"] if x]
            if sc and sc.get("scattr"):
                s_sc = scnames.get({v: k for k, v in scnames.items()}.get(
                    sc["scattr"].title().replace("_Ii", " II"), -1), None)
                first = chains[0] if chains else None
                script_name = sc["scattr"].title().replace("_Ii", " II")
                if first and script_name != first:
                    warn(f"sc mismatch {name}: sql={first} script={script_name}")

        # magic bursts: header if present, else derived from element for magical
        bursts = []
        if sc and sc.get("burstsHdr"):
            bursts = [b.strip() for b in
                      re.split(r",| and ", sc["burstsHdr"].replace("and,", ",")) if b.strip()]
        elif stype in ("Magical", "Breath") and h["element"] not in ("None", ""):
            # pure self-target = enhancing magic, which cannot magic burst
            # (heals/debuffs can -- they keep their derived burst windows)
            if not (sl and sl["validTargets"] == 1):
                bursts = burstmap.get(h["element"], [])

        # stat mods
        mods = []
        for modid, val in bmods.get(sid, []):
            mn = modnames.get(modid)
            if mn is None:
                warn(f"unknown modid {modid} on {name}")
                mn = "MOD%d" % modid
            mods.append((mn, val))

        # unbridled cross-check from spell_list requirements bit
        if sl and (sl["requirements"] & REQUIREMENT_UNBRIDLED) and not unbridled:
            verify.append("unbridled")   # public says JA-gated, DAT/field says plain

        trait = None
        if bl and not bl["stub"] and bl["traitCat"]:
            trait = (bl["traitCat"], bl["traitWeight"])
            if sc and sc.get("combosHdr") and sc["combosHdr"].lower() != "none":
                want = traitnames.get(btraits.get(bl["traitCat"], {}).get("traitId", -1), "?")
                if canon(sc["combosHdr"]) != canon(want):
                    warn(f"combo mismatch {name}: sql={want} script={sc['combosHdr']}")

        setpts = None if bl is None or bl["stub"] else bl["setPoints"]

        # ---- apply field-verified data (overrides base-LSB / fills gaps) ----
        if sid in FIELD_SET_POINTS:
            setpts = FIELD_SET_POINTS[sid]
            src = "field"
            verify = [v for v in verify if v != "setPoints"]
        if sid in FIELD_MP:
            if sl is None:
                sl = {"slug": None, "element": h["element"], "validTargets": 4,
                      "mpCost": FIELD_MP[sid], "castTime": None, "recastTime": None,
                      "aoe": 0, "requirements": 0, "range": 0, "radius": 0,
                      "commented": False}
            else:
                sl = dict(sl, mpCost=FIELD_MP[sid])
            src = "field"
            verify = [v for v in verify if v != "mpCost"]
        if sid in FIELD_UNBRIDLED:
            unbridled = True
            src = "field"
            # unbridled spells cannot be set: no set cost, no trait, and the
            # patch note settles the gating question and the spell's nature
            verify = [v for v in verify
                      if v not in ("setPoints", "trait", "unbridled", "spellType")]
        if sid in FIELD_MODS:
            mods = list(FIELD_MODS[sid])
            src = "field"
        elif klass.startswith("CEXI-75") and not mods and not unbridled:
            # base LSB carries no blue_spell_mods rows for the CatsEyeXI
            # custom spells; Spectral Floe proved they DO have stats in game
            verify.append("mods")
        if sid in WIKI_TRAIT_CATS:
            trait = (WIKI_TRAIT_CATS[sid], None)   # weight filled in below
            verify = [v for v in verify if v != "trait"]
        # THE TRAIT WEIGHT IS THE WIKI'S, NEVER LSB'S -- see WIKI_FEEDER_POINTS.
        # LSB's weight column mixes a legacy 1-unit scale with real wiki points,
        # which is what let one spell out-weigh five (Searing Tempest vs the
        # whole Attack Bonus era list).
        if trait:
            cat = trait[0]
            if cat in WIKI_FEEDER_POINTS:
                default, overrides = WIKI_FEEDER_POINTS[cat]
                trait = (cat, overrides.get(name, default))
            else:
                warn("spell %d (%s) feeds cat %d, which has no WIKI_FEEDER_POINTS"
                     % (sid, name, cat))
                trait = (cat, trait[1] or 0)
        if unbridled:
            setpts = None
        if bl is None and stype == "Magical":
            verify = [v for v in verify if v != "skillchain"]   # magical: no sc props

        rows.append({
            "id": sid, "name": name, "category": h["category"], "class": klass,
            "castable": castable, "unbridled": unbridled, "level": level,
            "stock": h["stock"], "element": h["element"],
            "spellType": stype, "damageType": dtype, "ecosystem": eco,
            "sl": sl, "setPoints": setpts,
            "trait": trait, "chains": chains, "bursts": bursts, "mods": mods,
            "numhits": int(sc["numhits"]) if sc and sc.get("numhits") else None,
            "note": FIELD_NOTES.get(sid),
            "grantedBy": FIELD_GRANTED.get(sid),
            "src": src, "verify": sorted(set(verify)),
        })

    # ------------------------------------------------------------ sanity
    hb = next(r for r in rows if r["id"] == 623)
    assert hb["setPoints"] == 3 and ("DEX", 2) in hb["mods"] and hb["chains"] == ["Impaction"]
    assert hb["sl"]["mpCost"] == 12 and hb["sl"]["castTime"] == 0.5
    sop = next(r for r in rows if r["id"] == 598)
    assert sop["element"] == "Dark" and sop["level"] == 24
    total_castable = sum(1 for r in rows if r["castable"])
    print(f"  rows: {len(rows)}  castable: {total_castable}  coverage: {counts}")
    assert len(rows) == 136 and total_castable == 135

    # ------------------------------------------------------------ spells.lua
    today = datetime.date.today().isoformat()
    L = []
    L.append("-- spells.lua -- bludex spell database (GENERATED %s by tools/generate_spells.py -- DO NOT EDIT)" % today)
    L.append("-- Availability: client-DAT truth via HANDOVER.md audit. Payload: public CatsEyeXI clone (= base-LSB;")
    L.append("-- live server may override in private submodules). src= sql | sql-commented | stub | missing.")
    L.append("-- Rows with verify={...} need in-game confirmation before their values are trusted.")
    L.append("")
    L.append("local M = { spells = {} }")
    L.append("")
    L.append("-- Icon sprites: three sizes per spell under icons/<Category>/.")
    L.append("-- Compose: M.meta.iconRoot .. '/' .. spell.iconBase .. M.meta.icons.<variant>")
    L.append("-- detail (320) = the spell info panel; grid128/grid64 adapt to window size.")
    L.append("M.meta = {")
    L.append("    iconRoot = 'icons',")
    L.append("    icons = { " + ", ".join("%s = %s" % (k, lq(v)) for k, v in VARIANTS.items()) + " },")
    L.append("}")
    L.append("")
    for r in rows:
        f = []
        f.append("id = %d" % r["id"])
        f.append("name = %s" % lq(r["name"]))
        f.append("iconBase = %s" % lq("%s/%s" % (r["category"], r["name"])))
        f.append("category = %s" % lq(r["category"]))
        klass_out = {"core": "core", "CEXI-75": "cexi75",
                     "CEXI-75*": "cexi75u", "LEARN-ONLY": "learnonly"}[r["class"]]
        if r["unbridled"]:
            klass_out = "cexi75u"
        f.append("class = %s" % lq(klass_out))
        f.append("castable = %s" % ("true" if r["castable"] else "false"))
        if r["unbridled"]:
            f.append("unbridled = true")
        if r["level"] is not None:
            f.append("level = %d" % r["level"])
        if r["stock"] is not None and r["stock"] != r["level"]:
            f.append("stockLevel = %d" % r["stock"])
        f.append("element = %s" % lq(r["element"]))
        f.append("spellType = %s" % lq(r["spellType"]))
        if r["damageType"]:
            f.append("damageType = %s" % lq(r["damageType"]))
        if r["ecosystem"]:
            f.append("ecosystem = %s" % lq(r["ecosystem"]))
        sl = r["sl"]
        if sl:
            f.append("mpCost = %d" % sl["mpCost"])
            if sl["castTime"] is not None:
                f.append("castTime = %s" % fmtnum(sl["castTime"]))
            if sl["recastTime"] is not None:
                f.append("recastTime = %s" % fmtnum(sl["recastTime"]))
            if sl["aoe"]:
                f.append("aoe = true")
            if sl["range"]:
                f.append("range = %d" % sl["range"])
            if sl["radius"]:
                f.append("radius = %d" % sl["radius"])
            f.append("targetsRaw = %d" % sl["validTargets"])
        if r["setPoints"] is not None:
            f.append("setPoints = %d" % r["setPoints"])
        if r["trait"]:
            f.append("trait = { category = %d, weight = %d }" % r["trait"])
        if r["chains"]:
            f.append("skillchain = %s" % lua_list([lq(c) for c in r["chains"]]))
        if r["bursts"]:
            f.append("bursts = %s" % lua_list([lq(b) for b in r["bursts"]]))
        if r["mods"]:
            f.append("mods = %s" % lua_list(
                ["{ stat = %s, value = %d }" % (lq(m), v) for m, v in r["mods"]]))
        if r["numhits"] and r["numhits"] > 1:
            f.append("numhits = %d" % r["numhits"])
        if r["grantedBy"]:
            f.append("grantedBy = %s" % lq(r["grantedBy"]))
        if r["note"]:
            f.append("note = %s" % lq(r["note"]))
        f.append("src = %s" % lq(r["src"]))
        if r["verify"]:
            f.append("verify = %s" % lua_list([lq(v) for v in r["verify"]]))
        L.append("M.spells[%d] = { %s }" % (r["id"], ", ".join(f)))
    L.append("")
    L.append("M.order = %s" % lua_list([str(r["id"]) for r in rows]))
    L.append("")
    L.append("return M")

    os.makedirs(OUTDIR, exist_ok=True)
    out = os.path.join(OUTDIR, "spells.lua")
    open(out, "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
    print("wrote " + os.path.abspath(out))

    # ------------------------------------------------------------ traits.lua
    T = []
    T.append("-- traits.lua -- bludex trait ladder (GENERATED %s by tools/generate_spells.py -- DO NOT EDIT)" % today)
    T.append("-- category -> tiers: set spells whose trait.category matches; sum their")
    T.append("-- trait points; the highest tier with points <= the total is active")
    T.append("-- (server: blueutils.cpp CalculateTraits).")
    T.append("--")
    T.append("-- THE SCALE IS bg-wiki's, NOT base-LSB's. Every ladder costs 8 trait points")
    T.append("-- per rung; a feeder spell pays 4 (6 for Skillchain/Mag. Burst/Gilfinder,")
    T.append("-- 8 for the lv99 spells, per-spell for Auto Refresh). base-LSB mixes that")
    T.append("-- scale with a legacy 1-unit one and ships only the FIRST rung of most")
    T.append("-- ladders -- see tools/generate_spells.py WIKI_LADDER for the whole story.")
    T.append("-- LSB still supplies the shape: which modifiers a ladder moves, and which")
    T.append("-- trait id owns each rung.")
    T.append("--")
    T.append("-- EACH TIER CARRIES ITS OWN traitId -- category 24 is Double Attack (15) at")
    T.append("-- 8 points and Triple Attack (16) at 16 -- and the id is what a job trait")
    T.append("-- suppresses. data/jobtraits.lua holds the other side of that collision.")
    T.append("--")
    T.append("-- confidence = 'verify' would mark rung values still wanting a field")
    T.append("-- reading. NO ladder carries it: every rung value is either bg-wiki's or")
    T.append("-- reconciles with the same trait's job ranks in sql/traits.sql, which the")
    T.append("-- generator checks on every run (blue and job move the SAME modifier).")
    T.append("-- Categories 201/202 are bludex-internal (never on the wire): base-LSB has")
    T.append("-- no blue_traits rows for Magic Eva./Magic Acc. Bonus. They are NOT 29/30 --")
    T.append("-- LSB already uses trait_category 29 for a real spell (Foul Waters).")
    T.append("")
    T.append("local M = { categories = {}, traitNames = {} }")
    T.append("")
    # seed the two names traits.sql has no row for, BEFORE anything reads them
    for cat, tname, tid, _stat in WIKI_TRAIT_CATEGORIES:
        traitnames.setdefault(tid, tname)
    for cat in sorted(btraits):
        tinfo = btraits[cat]
        tname = traitnames.get(tinfo["traitId"], "Trait %d" % tinfo["traitId"])
        tiers = []
        for pts in sorted(tinfo["tiers"]):
            tier = tinfo["tiers"][pts]
            mods = ", ".join("{ stat = %s, value = %d }" %
                             (lq(modnames.get(m, "MOD%d" % m)), v)
                             for m, v in tier["mods"])
            tiers.append("{ points = %d, traitId = %d, mods = { %s } }"
                         % (pts, tier["traitId"], mods))
        conf = ("" if tinfo["confidence"] == "wiki"
                else ", confidence = %s" % lq(tinfo["confidence"]))
        T.append("M.categories[%d] = { name = %s, traitId = %d%s, tiers = { %s } }"
                 % (cat, lq(tname), tinfo["traitId"], conf, ", ".join(tiers)))
    T.append("")
    # A rung's own name, because a ladder is not always ONE trait: category 24
    # runs Double Attack then Triple Attack. Needed wherever a rung is named
    # on its own (attribution) rather than as "tier N of <category>".
    blue_ids = set()
    for tinfo in btraits.values():
        for tier in tinfo["tiers"].values():
            blue_ids.add(tier["traitId"])
    T.append("-- each rung's OWN trait name (a ladder can change trait partway up)")
    for tid in sorted(blue_ids):
        T.append("M.traitNames[%d] = %s" % (tid, lq(traitnames.get(tid, "Trait %d" % tid))))
    T.append("")
    T.append("-- Set-point budget law (server: blueutils.cpp GetTotalBlueMagicPoints):")
    T.append("--   base = clamp(((level-1)/10)*5 + 10, 0, 55)  -- level 75 => 45")
    T.append("--   + Assimilation merits  + Job-Point gift bonus")
    T.append("-- The summed bonus arrives on packet 0x063 (misc merit data) -- read it live;")
    T.append("-- never hardcode a total. Field facts (Henrik, 2026-08-04, CEXI custom):")
    T.append("--   assimilationPerMerit = 2 (stock LSB: 1); expected total at 75 ~= 80.")
    T.append("M.rules = {")
    T.append("    baseCap = 55,")
    T.append("    baseAt75 = 45,")
    T.append("    assimilationPerMerit = 2,  -- field (CEXI custom, stock = 1)")
    T.append("    expectedTotalAt75 = 80,    -- field: 79 observed with spells still to learn;")
    T.append("                               -- learning spells contributes points (CEXI custom)")
    T.append("    slotCount = 20,")
    T.append("}")
    T.append("")
    T.append("return M")
    out2 = os.path.join(OUTDIR, "traits.lua")
    open(out2, "w", encoding="utf-8", newline="\n").write("\n".join(T) + "\n")
    print("wrote " + os.path.abspath(out2))

    # --------------------------------------------------------- jobtraits.lua
    # The OTHER side of the collision: which jobs grant a trait blue magic can
    # also grant, at which level and rank. A job trait beats a blue trait
    # outright (blueutils.cpp: "Player has the real job trait, making them
    # ineligible"), so this table is what lets Bludex say WHERE a trait came
    # from -- and which set points bought nothing.
    jobcodes = parse_job_enum()
    jtraits  = parse_job_traits(blue_ids)

    J = []
    J.append("-- jobtraits.lua -- job traits that COLLIDE with blue traits (GENERATED %s" % today)
    J.append("--                  by tools/generate_spells.py -- DO NOT EDIT)")
    J.append("-- Source: sql/traits.sql, filtered to the %d trait ids blue magic can also" % len(blue_ids))
    J.append("-- grant. A job trait SUPPRESSES the blue one outright, at any tier")
    J.append("-- (blueutils.cpp CalculateTraits: \"Player has the real job trait, making")
    J.append("-- them ineligible\" -- the TODO beside it is why the stronger-blue case does")
    J.append("-- not exist). Job traits are added first (charutils.cpp BuildingCharTraitsTable),")
    J.append("-- main job at your main level then sub job at your sub level.")
    J.append("--")
    J.append("-- BASE-LSB (public clone): CatsEyeXI may override these in the private")
    J.append("-- submodules. The live 0x0AC trait bit is the referee -- see lib/traitsource.lua.")
    J.append("-- content_tag is carried for the record only: CEXI runs RESTRICT_CONTENT = 0,")
    J.append("-- so every row here is live.")
    J.append("")
    J.append("local M = { jobs = {}, codes = {}, names = {} }")
    J.append("")
    for jid in sorted(jobcodes):
        J.append("M.codes[%d] = %s; M.names[%d] = %s"
                 % (jid, lq(jobcodes[jid]), jid, lq(JOB_NAMES.get(jid, jobcodes[jid]))))
    J.append("")
    for jid in sorted(jtraits):
        J.append("-- %s" % JOB_NAMES.get(jid, jobcodes.get(jid, "job %d" % jid)))
        J.append("M.jobs[%d] = {" % jid)
        for tid in sorted(jtraits[jid]):
            rungs = []
            for key in sorted(jtraits[jid][tid]):
                r = jtraits[jid][tid][key]
                mods = ", ".join("{ stat = %s, value = %d }" %
                                 (lq(modnames.get(m, "MOD%d" % m)), v)
                                 for m, v in r["mods"])
                extra = ""
                if r["merit"] != 0:
                    extra += ", merit = %d" % r["merit"]
                if r["tag"]:
                    extra += ", tag = %s" % lq(r["tag"])
                rungs.append("{ level = %d, rank = %d%s, mods = { %s } }"
                             % (r["level"], r["rank"], extra, mods))
            J.append("    [%d] = { %s },   -- %s"
                     % (tid, ", ".join(rungs), traitnames.get(tid, "trait %d" % tid)))
        J.append("}")
    J.append("")
    J.append("return M")
    out3 = os.path.join(OUTDIR, "jobtraits.lua")
    open(out3, "w", encoding="utf-8", newline="\n").write("\n".join(J) + "\n")
    print("wrote " + os.path.abspath(out3))

    # ------------------------------------------------------------ hints.lua
    # Learn-location hints from blucheck's data (spellid -> zoneId -> mobs).
    # Retail-era data; the UI labels it as such.
    bj = os.path.join(os.path.dirname(HERE), "..", "blucheck", "data", "spells.json")
    bj = os.path.normpath(os.path.join(HERE, "..", "..", "blucheck", "data", "spells.json"))
    if os.path.exists(bj):
        import json
        hd = json.load(open(bj, encoding="utf-8"))
        H = []
        H.append("-- hints.lua -- learn-location hints (GENERATED %s by tools/generate_spells.py -- DO NOT EDIT)" % today)
        H.append("-- Source: blucheck's data/spells.json (retail-era zones/mobs; CatsEyeXI can differ).")
        H.append("")
        H.append("local M = { hints = {} }")
        H.append("")
        for sid in sorted(int(k) for k in hd):
            zones = hd[str(sid)]
            parts = []
            for z in sorted(int(k) for k in zones):
                mobs = ", ".join(lq(m) for m in zones[str(z)])
                parts.append("[%d] = { %s }" % (z, mobs))
            H.append("M.hints[%d] = { %s }" % (sid, ", ".join(parts)))
        H.append("")
        H.append("return M")
        out3 = os.path.join(OUTDIR, "hints.lua")
        open(out3, "w", encoding="utf-8", newline="\n").write("\n".join(H) + "\n")
        print("wrote %s (%d spells with hints)" % (os.path.abspath(out3), len(hd)))
    else:
        warn("blucheck spells.json not found -- hints.lua not generated")

    # ------------------------------------------------------------ report
    print("\n=== verification needed (in game) ===")
    for r in rows:
        if r["verify"]:
            print("  %-22s %-6s %s" % (r["name"], r["src"], ",".join(r["verify"])))
    print("\n%d warnings" % len(warnings))

    # ------------------------------------------------------------ icons
    if "--deploy-icons" in sys.argv:
        import shutil
        dest_root = os.path.join(HERE, "..", "icons")
        n = miss = 0
        for sid, h in handover.items():
            dst = os.path.join(dest_root, h["category"])
            os.makedirs(dst, exist_ok=True)
            for suffix in VARIANTS.values():
                srcf = os.path.join(ASSETS, h["category"], "sprites", h["name"] + suffix)
                if os.path.exists(srcf):
                    shutil.copy2(srcf, os.path.join(dst, h["name"] + suffix))
                    n += 1
                else:
                    miss += 1
        print("deployed %d icon files -> %s (%d missing)"
              % (n, os.path.abspath(dest_root), miss))

if __name__ == "__main__":
    main()
