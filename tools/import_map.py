#!/usr/bin/env python3
"""Writes the owner's hand-arranged map into MapLayout.lua.

In game, the owner presses Move levels on the map and drags each chapter's
level nodes where they should be (saved in GnomishPachinkoDB.mapLayout).
After a /reload the saved variables are on disk; this reads them and writes
every arranged chapter into MapLayout.lua (UI.MAP_PATHS), where it becomes
every player's map. Chapters already in MapLayout.lua stay unless arranged
again.

  python tools/import_map.py              # show what would be written
  python tools/import_map.py --write      # write MapLayout.lua
  python tools/import_map.py --sv PATH    # another SavedVariables file

Needs: pip install lupa
"""
import argparse
import glob
import os

import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WOW = os.path.dirname(os.path.dirname(os.path.dirname(ROOT)))
OUT = os.path.join(ROOT, "MapLayout.lua")

HEADER = '''--[[
    Gnomish Pachinko - MapLayout.lua
    Where each chapter's ten levels sit on the map, arranged by hand by the
    owner (Move levels on the map) and written here by tools/import_map.py.
    Chapters not listed keep the winding path made from their number.
]]

local UI = GnomishPachinko.UI
UI.MAP_PATHS = {
'''


def find_sv():
    hits = glob.glob(os.path.join(WOW, "WTF", "Account", "*", "SavedVariables", "GnomishPachinko.lua"))
    hits.sort(key=os.path.getmtime, reverse=True)
    return hits[0] if hits else None


def chapter_points(t):
    pts = []
    for k in range(1, 11):
        p = t[k]
        if p is None:
            return None
        x = p["x"] if p["x"] is not None else p[1]
        y = p["y"] if p["y"] is not None else p[2]
        pts.append((int(round(x)), int(round(y))))
    return pts


def shipped():
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute("GnomishPachinko = { UI = {} }")
    rt.execute(open(OUT, encoding="utf-8").read())
    out = {}
    for k, v in rt.eval("GnomishPachinko.UI.MAP_PATHS").items():
        pts = chapter_points(v)
        if pts:
            out[int(k)] = pts
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sv")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()
    sv = a.sv or find_sv()
    chapters = shipped()
    if sv and os.path.exists(sv):
        rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        rt.execute(open(sv, encoding="utf-8", errors="replace").read())
        db = rt.eval("GnomishPachinkoDB")
        layout = db and db["mapLayout"]
        n = 0
        if layout:
            for k, v in layout.items():
                pts = chapter_points(v)
                if pts:
                    chapters[int(k)] = pts
                    n += 1
        print("saved variables:", sv, f"({n} arranged chapter(s))")
    else:
        print("no saved variables found")
    body = ""
    for c in sorted(chapters):
        pts = ", ".join(f"{{ x = {x}, y = {y} }}" for x, y in chapters[c])
        body += f"    [{c}] = {{ {pts} }},\n"
    text = HEADER + body + "}\n"
    if a.write:
        with open(OUT, "w", encoding="utf-8", newline="\r\n") as f:
            f.write(text)
        print(f"wrote {OUT}: {len(chapters)} chapter(s)")
    else:
        print(f"(dry run: {len(chapters)} chapter(s) would ship; add --write)")


if __name__ == "__main__":
    main()
