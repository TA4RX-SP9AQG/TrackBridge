"""One-off helper: removes the `const` that encloses a t('...') call the analyzer rejects.

Reads `flutter analyze` output on stdin, removes the nearest enclosing `const` for each reported spot
(position = line:col of the t( call), re-run until clean. Prints how many it fixed.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
out = sys.stdin.read()
spots = {}
# `dart analyze --format=machine`: SEVERITY|TYPE|CODE|FILE|LINE|COL|LENGTH|MESSAGE
for line in out.splitlines():
    f = line.split("|")
    if len(f) >= 7 and f[0] == "ERROR":
        try:
            rel = Path(f[3]).resolve().relative_to(ROOT).as_posix()
        except ValueError:
            continue
        if rel.startswith("lib/"):
            spots.setdefault(rel, set()).add((int(f[4]), int(f[5])))

fixed = 0
for rel, lcs in spots.items():
    p = ROOT / rel
    src = p.read_text(encoding="utf-8")
    lines = src.split("\n")
    offs = [0]
    for l in lines:
        offs.append(offs[-1] + len(l) + 1)
    removals = set()
    for line, col in lcs:
        pos = offs[line - 1] + col - 1
        depth = 0
        i = pos - 1
        while i >= 0:
            c = src[i]
            if c in ")]}":
                depth += 1
            elif c in "([{":
                if depth == 0:
                    # an enclosing opener: is there a `const` right before the expression that owns it?
                    j = i - 1
                    while j >= 0 and src[j] in " \t\r\n":
                        j -= 1
                    # skip generic type arguments  <...>
                    if j >= 0 and src[j] == ">":
                        d = 0
                        while j >= 0:
                            if src[j] == ">":
                                d += 1
                            elif src[j] == "<":
                                d -= 1
                                if d == 0:
                                    j -= 1
                                    break
                            j -= 1
                        while j >= 0 and src[j] in " \t\r\n":
                            j -= 1
                    k = j
                    while k >= 0 and (src[k].isalnum() or src[k] in "_.$"):
                        k -= 1
                    before = src[max(0, k - 5) : k + 1].rstrip()
                    if before.endswith("const"):
                        cstart = src.rfind("const", 0, k + 1)
                        removals.add(cstart)
                        break
                else:
                    depth -= 1
            elif src[i : i + 6] == "const " and depth == 0 and False:
                pass
            i -= 1
    for cstart in sorted(removals, reverse=True):
        src = src[:cstart] + src[cstart + 6 :] if src[cstart : cstart + 6] == "const " else src
        fixed += 1
    p.write_text(src, encoding="utf-8")
print("removed", fixed, "const keywords")
