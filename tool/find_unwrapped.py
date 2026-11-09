"""Lists string literals in lib/ that look like user-facing text but are not inside t('...')."""
import sys as _s
_s.stdout.reconfigure(encoding="utf-8")
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
ROOT = Path(__file__).resolve().parent.parent
SKIP = {"lib/l10n/english.dart", "lib/l10n/app_strings.dart"}

lit = re.compile(r"(?<![\w$])'((?:[^'\\\n]|\\.)*)'")
for p in sorted((ROOT / "lib").rglob("*.dart")):
    rel = p.relative_to(ROOT).as_posix()
    if rel in SKIP:
        continue
    for n, line in enumerate(p.read_text(encoding="utf-8").split("\n"), 1):
        s = line.strip()
        if s.startswith(("import ", "export ", "//", "///", "part ")):
            continue
        for m in lit.finditer(line):
            text = m.group(1)
            before = line[: m.start()]
            if before.rstrip().endswith("t("):
                continue
            # human text: letters, and either a space or an upper-case first letter followed by lowercase
            if not re.search(r"[A-Za-zçğıöşüÇĞİÖŞÜ]{3,}", text):
                continue
            if re.fullmatch(r"[a-z][A-Za-z0-9_.:/@$-]*", text) or re.fullmatch(r"[A-Z0-9_ ./:-]+", text):
                continue  # identifiers, keys, constants
            if re.search(r"(assets/|\.png|\.dart|https?://|google\.|geo:|[|]|^tb\.|monospace|Roboto)", text):
                continue
            print(f"{rel}:{n}: {text}")
