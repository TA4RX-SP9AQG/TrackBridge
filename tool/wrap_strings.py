"""One-off helper that wraps user-facing Dart string literals in t('...') for the English translation.

Usage: python -I tool/wrap_strings.py [--write]
Without --write it only reports what it would change. It is idempotent: literals already inside t(...)
are skipped. The generated key is the Turkish text with {name} placeholders for interpolations.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WRITE = "--write" in sys.argv

# Files that need hand-made handling (const enums, map keys, mappings).
SKIP_FILES = {"lib/core/symbols.dart", "lib/core/ascii_text.dart", "lib/core/smart_beacon.dart", "lib/l10n/english.dart", "lib/l10n/app_strings.dart"}
UI_DIRS = ["lib/ui", "lib/state", "lib/core", "lib/background", "lib/ble"]

CONTEXT = re.compile(
    r"(?:\bconst\s+)?\b(?:Text|SectionHeader|StatusPill|HeroChip)\(\s*(?=['\"])"
    r"|\b(?:label|title|subtitle|tooltip|labelText|hintText|helperText|suffixText|message|semanticLabel)\s*:\s*(?=['\"])"
)
TURKISH = re.compile(r"[çğıöşüÇĞİÖŞÜ]")


def parse_literal(src: str, i: int):
    """Parse one Dart string literal starting at src[i] (a quote). Returns (end_index, parts) or None."""
    q = src[i]
    if i > 0 and src[i - 1] == "r":
        return None
    if src.startswith(q * 3, i):
        return None  # multi-line strings are left alone
    j = i + 1
    parts = []  # list of ("text", str) / ("expr", str)
    buf = []
    while j < len(src):
        c = src[j]
        if c == "\\":
            nxt = src[j + 1]
            mapping = {"n": "\n", "t": "\t", "'": "'", '"': '"', "\\": "\\", "$": "$"}
            if nxt in mapping:
                buf.append(mapping[nxt])
                j += 2
                continue
            return None
        if c == q:
            if buf:
                parts.append(("text", "".join(buf)))
            return j + 1, parts
        if c == "\n":
            return None
        if c == "$":
            if buf:
                parts.append(("text", "".join(buf)))
                buf = []
            if src[j + 1] == "{":
                depth, k = 1, j + 2
                while k < len(src) and depth:
                    if src[k] == "{":
                        depth += 1
                    elif src[k] == "}":
                        depth -= 1
                    k += 1
                parts.append(("expr", src[j + 2 : k - 1]))
                j = k
                continue
            m = re.match(r"[A-Za-z_]\w*", src[j + 1 :])
            if m:
                parts.append(("expr", m.group(0)))
                j += 1 + len(m.group(0))
                continue
        buf.append(c)
        j += 1
    return None


def parse_adjacent(src: str, i: int):
    """Parse one or more adjacent string literals (implicit concatenation)."""
    all_parts = []
    j = i
    while True:
        r = parse_literal(src, j)
        if r is None:
            return None if not all_parts else (j, all_parts)
        j, parts = r
        all_parts.extend(parts)
        k = j
        while k < len(src) and src[k] in " \t\r\n":
            k += 1
        if k < len(src) and src[k] in "'\"" and k != j:
            j = k
            continue
        return j, all_parts


def build(parts):
    key, args, seen = [], {}, {}
    n = 0
    for kind, value in parts:
        if kind == "text":
            key.append(value)
            continue
        expr = value.strip()
        if re.fullmatch(r"[A-Za-z_]\w*", expr):
            name = expr
        else:
            if expr not in seen:
                n += 1
                seen[expr] = f"v{n}"
            name = seen[expr]
        args.setdefault(name, expr)
        key.append("{" + name + "}")
    return "".join(key), args


def dart_quote(text: str) -> str:
    esc = text.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$").replace("\n", "\\n")
    return f"'{esc}'"


def process(path: Path):
    src = path.read_text(encoding="utf-8")
    edits, keys = [], []
    for m in CONTEXT.finditer(src):
        start = m.end()
        if src[max(0, m.start() - 2) : m.start()] == "t(":
            continue
        r = parse_adjacent(src, start)
        if r is None:
            continue
        end, parts = r
        key, args = build(parts)
        if not re.search(r"[A-Za-zçğıöşüÇĞİÖŞÜ]{2,}", re.sub(r"\{\w+\}", "", key)):
            continue
        call = f"t({dart_quote(key)}" + (", {" + ", ".join(f"'{k}': {v}" for k, v in args.items()) + "}" if args else "") + ")"
        edits.append((start, end, call))
        keys.append(key)
    # Stage B: any remaining literal with Turkish letters that is not already wrapped.
    covered = [(a, b) for a, b, _ in edits]
    for m in re.finditer(r"(?<![\w$])(['\"])", src):
        i = m.start()
        if any(a <= i < b for a, b in covered):
            continue
        line_start = src.rfind("\n", 0, i) + 1
        line = src[line_start : src.find("\n", i)]
        if line.lstrip().startswith(("import ", "export ", "part ", "//", "///")):
            continue
        if src[max(0, i - 2) : i] == "t(":
            continue
        r = parse_adjacent(src, i)
        if r is None:
            continue
        end, parts = r
        if not any(k == "text" and TURKISH.search(v) for k, v in parts):
            continue
        key, args = build(parts)
        call = f"t({dart_quote(key)}" + (", {" + ", ".join(f"'{k}': {v}" for k, v in args.items()) + "}" if args else "") + ")"
        edits.append((i, end, call))
        covered.append((i, end))
        keys.append(key)
    if WRITE and edits:
        out = src
        for a, b, call in sorted(edits, reverse=True):
            out = out[:a] + call + out[b:]
        if "import '../l10n/app_strings.dart';" not in out and "import 'package:trackbridge/l10n" not in out:
            rel = path.relative_to(ROOT / "lib")
            depth = len(rel.parts) - 1
            imp = "import '" + "../" * depth + "l10n/app_strings.dart';" if depth else "import 'l10n/app_strings.dart';"
            # insert after the last import line
            lines = out.split("\n")
            idx = max((n for n, l in enumerate(lines) if l.startswith("import ")), default=-1)
            lines.insert(idx + 1, imp)
            out = "\n".join(lines)
        path.write_text(out, encoding="utf-8")
    return keys


def main():
    total = {}
    for d in UI_DIRS:
        for p in sorted((ROOT / d).rglob("*.dart")):
            rel = p.relative_to(ROOT).as_posix()
            if rel in SKIP_FILES:
                continue
            ks = process(p)
            if ks:
                total[rel] = ks
    n = sum(len(v) for v in total.values())
    uniq = {k for v in total.values() for k in v}
    print(f"{'WROTE' if WRITE else 'would wrap'} {n} literals ({len(uniq)} unique) in {len(total)} files")
    for rel, ks in total.items():
        print(f"  {len(ks):3} {rel}")
    if "--keys" in sys.argv:
        out = ROOT / "tool" / "keys.txt"
        out.write_text("\n".join(sorted(uniq)), encoding="utf-8")
        print("keys written to", out)


main()
