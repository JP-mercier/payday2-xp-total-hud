"""Build lua/ehi_xp_names.lua from an Extra Heist Info (EHI) download, without installing EHI.

EHI's level files list the base XP of each objective (EHI:AddXPBreakdown) with a name whose English
text is in loc/english.json ("ehi_experience_<name>"). Mission XP elements award those same base
amounts, so XP Total HUD can name an award from (level id, base amount).

The output ships with the mod (base XP amounts are the game's own numbers; the names are EHI's short
labels, credited in the file header and the README). Rerun after an EHI update to pick up new heists:

    python -I tools/extract_ehi_xp.py "<folder that holds EHI's lua/ and loc/>"

The files are only read as text; nothing from EHI is executed.
"""

import json
import re
import sys
from pathlib import Path

# Keys inside the breakdown that hold numbers but aren't objectives.
PARAM_KEYS = {
    "amount", "times", "min", "max", "min_max", "ghost_bonus", "stealth", "loud", "timer", "pos",
    "start_chance", "kill_add_chance", "increase_escape_chance", "escape_after_alarm_in", "wave",
    "escape_ghost_bonus_only", "max_bags", "min_bags", "bags", "mandatory_bags", "secured_bags",
}
# Keys of an escape entry ({ amount = 8000, stealth = true, ... }).
ESCAPE_KEYS = ("stealth", "loud", "ghost_bonus", "escape_chance", "c4_used", "timer")


def strip_comments(src):
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", "", src, flags=re.S)
    return re.sub(r"--[^\n]*", "", src)


def calls(src, name):
    """Text inside each `name(...)` call, parentheses balanced."""
    for m in re.finditer(re.escape(name) + r"\s*\(", src):
        depth, i = 1, m.end()
        while i < len(src) and depth:
            depth += {"(": 1, ")": -1}.get(src[i], 0)
            i += 1
        yield src[m.end():i - 1]


def entries(src):
    found = []
    # { amount = N, name = "key", ... } anywhere (also local tables passed to the breakdown).
    for table in re.findall(r"\{([^{}]*)\}", src):
        amount = re.search(r"\bamount\s*=\s*(\d+)", table)
        name = re.search(r"\bname\s*=\s*\"(\w+)\"", table)
        if amount and name:
            found.append((int(amount.group(1)), name.group(1)))
    for call in calls(src, "AddXPBreakdown"):
        # Escape entries have no name.
        for table in re.findall(r"\{([^{}]*)\}", call):
            amount = re.search(r"\bamount\s*=\s*(\d+)", table)
            if amount and not re.search(r"\bname\s*=", table) and any(re.search(r"\b%s\s*=" % k, table) for k in ESCAPE_KEYS):
                found.append((int(amount.group(1)), "escape"))
        # key = N (objective = { vault_open = 4000 }, escape = 8000, loot_all = 1000).
        for key, amount in re.findall(r"\b([A-Za-z_]\w*)\s*=\s*(\d+)\b", call):
            if key not in PARAM_KEYS:
                found.append((int(amount), key))
        # key = { amount = N } (loot_all = { amount = 500, times = 4 }).
        for key, amount in re.findall(r"\b([A-Za-z_]\w*)\s*=\s*\{\s*amount\s*=\s*(\d+)", call):
            if key not in PARAM_KEYS and key != "objective":
                found.append((int(amount), key))
    # Plans kept in a local table and passed to the breakdown by name (First World Bank's custom_plan):
    # loot, loot_all and escape amounts outside the call.
    found += loot_entries(src)
    # Not "local escape = 23 + 7" (a timer on Jungle day 2).
    for amount in re.findall(r"(?<!local )\bescape\s*=\s*(\d+)\b", src):
        found.append((int(amount), "escape"))
    return found


def loot_entries(src):
    """(amount, key) for XP paid per secured bag: loot_all = N, loot_all = { amount = N },
    loot = { money = N, gold = N }."""
    found = []
    for amount in re.findall(r"\bloot_all\s*=\s*(\d+)\b", src):
        found.append((int(amount), "loot_all"))
    for amount in re.findall(r"\bloot_all\s*=\s*\{\s*amount\s*=\s*(\d+)", src):
        found.append((int(amount), "loot_all"))
    for table in re.findall(r"\bloot\s*=\s*\{([^{}]*)\}", src):
        for key, amount in re.findall(r"\b([A-Za-z_]\w*)\s*=\s*(\d+)\b", table):
            if key not in PARAM_KEYS:
                found.append((int(amount), key))
    return found


# Keys with no English text in EHI that read better under another name.
NAME_OVERRIDES = {"loot_all": "Bag secured", "_else": "Bag secured", "diamonds_dah": "Diamonds",
                  "mus_artifact": "Artifact"}

# Base amounts EHI has wrong, checked in game: level id -> key -> amount the game pays.
# Alesso pays 2000 for each C4 taken from a closet (5 on Overkill and up), so EHI's 1000/2000 for
# find/place look swapped.
AMOUNT_FIXES = {"arena": {"alesso_find_c4": 2000, "c4_set_up": 1000}}


def pretty(key):
    if key in NAME_OVERRIDES:
        return NAME_OVERRIDES[key]
    text = key.replace("_", " ").strip()
    return text[:1].upper() + text[1:]


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(ehi_dir):
    ehi = Path(ehi_dir)
    loc = json.loads((ehi / "loc" / "english.json").read_text(encoding="utf-8-sig"))

    levels, loot = {}, {}
    for folder in ("levels", "custom_levels"):
        for path in sorted((ehi / "lua" / folder).glob("*.lua")):
            src = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
            # skm_* files pull in a shared base with dofile.
            for base in re.findall(r"levels/(\w+)\.lua", src):
                base_path = ehi / "lua" / "levels" / (base + ".lua")
                if base_path.exists() and base_path != path:
                    src += "\n" + strip_comments(base_path.read_text(encoding="utf-8", errors="replace"))
            by_amount = {}
            fixes = AMOUNT_FIXES.get(path.stem, {})
            for amount, key in entries(src):
                amount = fixes.get(key, amount)
                if amount <= 0:
                    continue
                name = loc.get("ehi_experience_" + key) or pretty(key)
                names = by_amount.setdefault(amount, [])
                if name not in names:
                    names.append(name)
            if by_amount:
                levels[path.stem] = by_amount
            # Amounts a secured bag pays, so the mod can tell bag XP from objective XP of the same size.
            loot_amounts = {amount for amount, _ in loot_entries(src) if amount > 0}
            loot_amounts |= {amount for amount, key in entries(src) if amount > 0 and key == "_else"}
            if loot_amounts:
                loot[path.stem] = loot_amounts

    # Level ids that use another level's file (from EHI's GameSetup.lua).
    redirect = {}
    setup = strip_comments((ehi / "lua" / "GameSetup.lua").read_text(encoding="utf-8", errors="replace"))
    block = re.search(r"local redirect\s*=\s*\{(.*?)\n\}", setup, flags=re.S)
    if block:
        for m in re.finditer(r"(?:\[\"([^\"]+)\"\]|(\w+))\s*=\s*\"(\w+)\"", block.group(1)):
            redirect[m.group(1) or m.group(2)] = m.group(3)

    out = ["-- Generated by tools/extract_ehi_xp.py. Objective names from Extra Heist Info by Dom",
           "-- (modworkshop.net/mod/31915). levels: level id -> base XP -> objective names. loot: level id ->",
           "-- base XP paid per secured bag. redirect: level id -> the level id whose tables it uses.",
           "return {", "\tlevels = {"]
    for level in sorted(levels):
        out.append("\t\t[%s] = {" % lua_string(level))
        for amount in sorted(levels[level]):
            out.append("\t\t\t[%d] = { %s }," % (amount, ", ".join(lua_string(n) for n in levels[level][amount])))
        out.append("\t\t},")
    out.append("\t},")
    out.append("\tloot = {")
    for level in sorted(loot):
        out.append("\t\t[%s] = { %s }," % (lua_string(level), ", ".join("[%d] = true" % a for a in sorted(loot[level]))))
    out.append("\t},")
    out.append("\tredirect = {")
    for key in sorted(redirect):
        out.append("\t\t[%s] = %s," % (lua_string(key), lua_string(redirect[key])))
    out.append("\t}")
    out.append("}")

    target = Path(__file__).resolve().parent.parent / "lua" / "ehi_xp_names.lua"
    target.write_text("\n".join(out) + "\n", encoding="utf-8")
    print("%d levels, %d redirects -> %s" % (len(levels), len(redirect), target))


if __name__ == "__main__":
    main(sys.argv[1])
