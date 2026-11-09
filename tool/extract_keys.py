"""Lists every translation key used in lib/: t('...') calls plus the symbol catalog names.

Usage: python -I tool/extract_keys.py   (prints one key per line, sorted, to stdout as JSON list)
"""
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
BS = chr(92)
SKIP = {"lib/l10n/english.dart", "lib/l10n/app_strings.dart"}


def read_literal(src, i):
    """Reads adjacent Dart string literals starting at src[i] (a quote). Returns (text, end) or None."""
    out = []
    j = i
    while j < len(src) and src[j] in "'\"":
        q = src[j]
        j += 1
        while j < len(src) and src[j] != q:
            if src[j] == BS:
                nxt = src[j + 1]
                out.append({"n": "\n", "t": "\t"}.get(nxt, nxt))
                j += 2
            else:
                out.append(src[j])
                j += 1
        j += 1
        k = j
        while k < len(src) and src[k] in " \t\r\n":
            k += 1
        if k < len(src) and src[k] in "'\"":
            j = k
        else:
            break
    return "".join(out), j


keys = set()
call = re.compile(r"(?<![\w$.])t\(\s*(?=['\"])")
for p in sorted((ROOT / "lib").rglob("*.dart")):
    rel = p.relative_to(ROOT).as_posix()
    if rel in SKIP:
        continue
    src = p.read_text(encoding="utf-8")
    for m in call.finditer(src):
        text, _ = read_literal(src, m.end())
        keys.add(text)

# symbol catalog: `'<code>': ('<name>', SymbolCategory.x)` entries and the category labels
sym = (ROOT / "lib/core/symbols.dart").read_text(encoding="utf-8")
for m in re.finditer(r"^\s+\w+\('((?:[^'" + BS + r"\n]|" + BS + r".)*)'\)[,;]", sym, re.M):
    keys.add(m.group(1).replace(BS + "'", "'"))
# smart beacon presets
for name in ("Yürüyüş", "Bisiklet", "Araç"):
    keys.add(name)
print(json.dumps(sorted(keys), ensure_ascii=False, indent=0))
