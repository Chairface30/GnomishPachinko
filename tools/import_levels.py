#!/usr/bin/env python3
"""Writes the owner's approved editor levels into CustomLevels.lua.

In game, the owner imports a player's level code in the level editor,
test-plays it and presses "Approve for level" (GnomishPachinkoDB.editor.approved[n]).
After a /reload (or logging out) the saved variables are on disk; this reads
them and writes every approved level into CustomLevels.lua, where it
replaces the generated level of that number for every player.

  python tools/import_levels.py              # show what would be written
  python tools/import_levels.py --write      # write CustomLevels.lua
  python tools/import_levels.py --sv PATH    # another SavedVariables file

Levels already in CustomLevels.lua stay unless the saved approvals have a
newer one for the same number. --only 12,40 limits the import to those
levels; --drop 12 removes a shipped level.
Needs: pip install lupa
"""
import argparse
import glob
import os
import re

import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WOW = os.path.dirname(os.path.dirname(os.path.dirname(ROOT)))   # .../_classic_beta_
OUT = os.path.join(ROOT, "CustomLevels.lua")

HEADER = '''--[[
    Gnomish Pachinko - CustomLevels.lua
    Levels built in the level editor and approved by the owner. Each
    replaces the generated level of the same number for every player.
    Written by tools/import_levels.py from the owner's saved approvals;
    edit through the editor, not by hand.
]]

local L = GnomishPachinko.Levels
L.CUSTOM = {
'''


def find_sv():
    hits = glob.glob(os.path.join(WOW, "WTF", "Account", "*", "SavedVariables", "GnomishPachinko.lua"))
    hits.sort(key=os.path.getmtime, reverse=True)
    return hits[0] if hits else None


def lua_to_py(v):
    if lupa.lua_type(v) == "table":
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [lua_to_py(v[k]) for k in range(1, len(keys) + 1)]
        return {k: lua_to_py(v[k]) for k in keys}
    return v


IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def ser(v, indent=""):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        if isinstance(v, float) and v.is_integer():
            return str(int(v))
        return repr(round(v, 3)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return '"' + re.sub(r'[\x00-\x1f"\\|]', "", v) + '"'
    if isinstance(v, list):
        if all(not isinstance(x, (dict, list)) for x in v):
            return "{ " + ", ".join(ser(x) for x in v) + " }"
        inner = indent + "    "
        return "{\n" + "".join(inner + ser(x, inner) + ",\n" for x in v) + indent + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        parts = []
        for k in sorted(v, key=str):
            key = k if isinstance(k, str) and IDENT.match(k) else "[" + ser(k) + "]"
            parts.append(key + " = " + ser(v[k], indent + "    "))
        flat = "{ " + ", ".join(parts) + " }"
        if len(flat) < 110 and "\n" not in flat:
            return flat
        inner = indent + "    "
        return "{\n" + "".join(inner + p + ",\n" for p in parts) + indent + "}"
    return "nil"


def shipped():
    """The levels already in CustomLevels.lua."""
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute("GnomishPachinko = { Levels = {} }")
    rt.execute(open(OUT, encoding="utf-8").read())
    return {int(k): lua_to_py(v) for k, v in rt.eval("GnomishPachinko.Levels.CUSTOM").items()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sv")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--only")
    ap.add_argument("--drop")
    a = ap.parse_args()
    sv = a.sv or find_sv()
    levels = shipped()
    approved = {}
    if sv and os.path.exists(sv):
        rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        rt.execute(open(sv, encoding="utf-8", errors="replace").read())
        db = rt.eval("GnomishPachinkoDB")
        ed = db and db["editor"]
        if ed and ed["approved"]:
            approved = {int(k): lua_to_py(v) for k, v in ed["approved"].items()}
        print("saved variables:", sv)
    else:
        print("no saved variables found")
    only = {int(x) for x in a.only.split(",")} if a.only else None
    for n, lvl in sorted(approved.items()):
        if only and n not in only:
            continue
        lvl = dict(lvl)
        lvl["level"] = n
        print(f"  level {n}: \"{lvl.get('name', '')}\" by {lvl.get('author', '?')}, {len(lvl.get('pieces', []))} pieces"
              + ("  (replaces the shipped one)" if n in levels else ""))
        levels[n] = lvl
    if a.drop:
        for n in (int(x) for x in a.drop.split(",")):
            if levels.pop(n, None) is not None:
                print(f"  level {n}: dropped")
    body = "".join(f"    [{n}] = {ser(levels[n], '    ')},\n" for n in sorted(levels))
    text = HEADER + body + "}\n"
    if a.write:
        with open(OUT, "w", encoding="utf-8", newline="\r\n") as f:
            f.write(text)
        print(f"wrote {OUT}: {len(levels)} level(s)")
    else:
        print(f"(dry run: {len(levels)} level(s) would ship; add --write)")


if __name__ == "__main__":
    main()
