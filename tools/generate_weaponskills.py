#!/usr/bin/env python3
"""
generate_weaponskills.py -- builds bludex/data/weaponskills.lua

Source (local, never fetched): sql/weapon_skills.sql from the public
CatsEyeXI clone (= base-LSB; the live server may override in private
submodules). Skillchain property ids follow scripts/enum/skillchain_type.lua.

Only weaponskills that can actually resonate ship (primary_sc > 0);
Spirits Within / Sanguine Blade have no properties and can never partner.

Tags (for the Skillchain-partners window's labels):
  quest    unlock_id 1-14   -- the skill-240 WSNM quest skills (Savage Blade...)
  mythic   unlock_id 15-34  -- mythic weapon skills (Expiacion...)
  empyrean unlock_id 35-49  -- empyrean weapon skills (Chant du Cygne...)
  merit    unlock_id 50-63  -- merit skills; the AEONIC weapons empower these
  relic    by name          -- relic weapon skills (Knights of Round...);
                              their jobs mask is zero (the weapon unlocks them)
Zero-jobs rows NOT in the relic list are mob-only (Uriel Blade, Knights of
Rotund...) and are dropped.
"""

import os
import re
import datetime

CLONE  = r"C:\Users\Henrik Johansson\scripts\catseyexi"
HERE   = os.path.dirname(os.path.abspath(__file__))
OUT    = os.path.join(HERE, "..", "data", "weaponskills.lua")

SQL    = os.path.join(CLONE, "sql", "weapon_skills.sql")

# skill type id -> weapon display name (scripts/enum + field order: Sword
# first -- BLU's weapon -- then the rest by skill id)
WEAPONS = {
    3: "Sword", 1: "Hand-to-Hand", 2: "Dagger", 4: "Great Sword", 5: "Axe",
    6: "Great Axe", 7: "Scythe", 8: "Polearm", 9: "Katana", 10: "Great Katana",
    11: "Club", 12: "Staff", 25: "Archery", 26: "Marksmanship",
}
WEAPON_ORDER = ["Sword", "Dagger", "Club", "Hand-to-Hand", "Great Sword",
                "Axe", "Great Axe", "Scythe", "Polearm", "Katana",
                "Great Katana", "Staff", "Archery", "Marksmanship"]

# scripts/enum/skillchain_type.lua
SC_NAMES = {
    1: "Transfixion", 2: "Compression", 3: "Liquefaction", 4: "Scission",
    5: "Reverberation", 6: "Detonation", 7: "Induration", 8: "Impaction",
    9: "Gravitation", 10: "Distortion", 11: "Fusion", 12: "Fragmentation",
    13: "Light", 14: "Darkness", 15: "Light II", 16: "Darkness II",
}

RELICS = {
    "final_heaven", "mercy_stroke", "knights_of_round", "scourge",
    "onslaught", "metatron_torment", "catastrophe", "geirskogul",
    "blade_metsu", "tachi_kaiten", "randgrith", "gate_of_tartarus",
    "namas_arrow", "coronach",
}

TAG_ORDER = {None: 0, "quest": 1, "relic": 2, "mythic": 3, "empyrean": 4, "merit": 5}

# slugs whose mechanical prettify loses retail punctuation
NAME_FIX = {
    "kings_justice": "King's Justice",
    "ukkos_fury": "Ukko's Fury",
    "rudras_storm": "Rudra's Storm",
    "jishnus_radiance": "Jishnu's Radiance",
    "camlanns_torment": "Camlann's Torment",
    "ascetics_fury": "Ascetic's Fury",
}
LOWER_WORDS = {"of", "du", "the", "no"}


def pretty(slug, wtype):
    """'red_lotus_blade' -> 'Red Lotus Blade'; katana/great katana skills
    carry their retail colon ('blade_ku' -> 'Blade: Ku')."""
    if slug in NAME_FIX:
        return NAME_FIX[slug]
    words = slug.replace("_", " ").split(" ")
    words = [w if (i > 0 and w in LOWER_WORDS) else w[:1].upper() + w[1:]
             for i, w in enumerate(words)]
    name = " ".join(words)
    if wtype == 9 and name.startswith("Blade "):
        name = "Blade: " + name[len("Blade "):]
    if wtype == 10 and name.startswith("Tachi "):
        name = "Tachi: " + name[len("Tachi "):]
    return name


def tag_for(slug, unlock, jobs_zero):
    if slug in RELICS:
        return "relic"
    if jobs_zero:
        return None  # mob-only; caller drops it
    if 1 <= unlock <= 14:
        return "quest"
    if 15 <= unlock <= 34:
        return "mythic"
    if 35 <= unlock <= 49:
        return "empyrean"
    if 50 <= unlock <= 63:
        return "merit"
    return None


def parse():
    row_re = re.compile(
        r"^INSERT INTO `weapon_skills` VALUES "
        r"\((\d+),'([^']+)',0x([0-9a-fA-F]+),(\d+),(\d+),\d+,\d+,\d+,\d+,\d+,\d+,"
        r"(\d+),(\d+),(\d+),\d+,(\d+)\);")
    out = []
    for line in open(SQL, encoding="utf-8"):
        m = row_re.match(line.strip())
        if m is None:
            continue
        wsid, slug, jobs, wtype, lvl, sc1, sc2, sc3, unlock = (
            int(m.group(1)), m.group(2), m.group(3), int(m.group(4)),
            int(m.group(5)), int(m.group(6)), int(m.group(7)),
            int(m.group(8)), int(m.group(9)))
        weapon = WEAPONS.get(wtype)
        if weapon is None:
            continue
        sc = [SC_NAMES[i] for i in (sc1, sc2, sc3) if i in SC_NAMES]
        if not sc:
            continue                      # cannot resonate; never a partner
        jobs_zero = set(jobs) <= {"0"}
        tag = tag_for(slug, unlock, jobs_zero)
        if jobs_zero and tag != "relic":
            continue                      # mob-only weaponskill
        out.append({"id": wsid, "name": pretty(slug, wtype), "weapon": weapon,
                    "lvl": lvl, "sc": sc, "tag": tag})
    # standard skills by skill level, then the specials in tag order
    out.sort(key=lambda w: (WEAPON_ORDER.index(w["weapon"]),
                            TAG_ORDER[w["tag"]] if w["tag"] in ("relic",) else 0,
                            w["lvl"] if w["lvl"] > 0 else 9999,
                            w["id"]))
    return out


def emit(ws):
    stamp = datetime.date.today().isoformat()
    lines = [
        "-- weaponskills.lua -- weaponskill skillchain properties (GENERATED %s" % stamp,
        "-- by tools/generate_weaponskills.py -- DO NOT EDIT). Source: the public",
        "-- CatsEyeXI clone's sql/weapon_skills.sql (= base-LSB). tag= quest (the",
        "-- WSNM quest skills) | relic | mythic | empyrean | merit (the skills the",
        "-- AEONIC weapons empower); no tag = a plain skill-up weaponskill.",
        "",
        "local M = { ws = {} }",
        "",
        "-- weapon display order for the chooser (Sword first -- BLU's weapon)",
        "M.weapons = { %s }" % ", ".join("'%s'" % w for w in WEAPON_ORDER),
        "",
    ]
    for w in ws:
        sc = ", ".join("'%s'" % p for p in w["sc"])
        tag = (", tag = '%s'" % w["tag"]) if w["tag"] else ""
        lines.append(
            "M.ws[#M.ws + 1] = { name = '%s', weapon = '%s', lvl = %d, sc = { %s }%s }"
            % (w["name"].replace("'", "\\'"), w["weapon"], w["lvl"], sc, tag))
    lines.append("")
    lines.append("return M")
    lines.append("")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    ws = parse()
    emit(ws)
    per = {}
    for w in ws:
        per[w["weapon"]] = per.get(w["weapon"], 0) + 1
    print("wrote %s: %d weaponskills" % (OUT, len(ws)))
    for wpn in WEAPON_ORDER:
        print("  %-14s %d" % (wpn, per.get(wpn, 0)))
