#!/usr/bin/env python3
"""i18n_extract.py — collect every player-facing string into locale/messages.pot
and merge it into each locale/<lang>.po.

The message id is the English text itself, so English needs no catalog and a
missing translation falls back to English. Sources:

  * GDScript: string literals passed to tr(...), atr(...) or
    TranslationServer.translate(...). That's the convention: UI text goes
    through tr() (or TranslationServer.translate() in static functions).
  * Scenes (.tscn): text = "..." properties (Controls translate these
    automatically).
  * Data (data/*.json): the display fields listed in DATA_KEYS. Labels show
    them as-is, so Godot's auto-translation picks them up; code that embeds one
    in a sentence passes it through tr() first.

Merging keeps every existing translation, adds new ids with an empty msgstr
(which Godot treats as untranslated, so English shows), and drops ids that no
longer exist (kept at the bottom as #~ comments so a rename can reuse them).

    python3 tools/i18n_extract.py            # rewrite messages.pot and merge
    python3 tools/i18n_extract.py --check    # exit 1 if the pot is stale
"""
from __future__ import annotations

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALE = os.path.join(ROOT, "locale")
CODE_DIRS = ["autoload", "scenes", "scripts"]
DATA_KEYS = {"name", "desc", "title", "subtitle", "flavor", "post", "blurb",
             "one", "bar", "cart", "case", "kiosk", "tagline", "label"}
# Language names are written in their own language, never translated; the
# 2D floor no longer ships.
SKIP_FILES = {"scripts/ui/languages.gd"}
SKIP_DIRS = ("scenes/venue/floor/",)
DATA_SKIP = re.compile(r"\.backup-|city_districts|outdoor_spaces")
# A GDScript string literal: "..." with escapes.
LIT = r'"((?:[^"\\\n]|\\.)*)"'
CALL = re.compile(r'(?<![\w.])(?:tr|atr|TranslationServer\.translate)\(\s*' + LIT)
# Plain literals that reach a Control as-is (Godot auto-translates those): text
# assignments and the UI helpers whose first argument is the text. Not
# followed by % or +, which build a new string and so need tr() on the literal.
HELPERS = ("toast_requested.emit|_label|_toast|make_display_label|_button|make_button|"
           "make_label|_rail_item|_section_header|_section|_manager_button|_stat|"
           "_round_button|_header|_wrapped|_toggle|_row|_display|_case_button|"
           "_free_card|_float_text|_field|_choice|_chip|_pill|_title")
PLAIN = re.compile(r'(?:\btext\s*\+?=\s*|(?<![\w])(?:' + HELPERS + r')\(\s*)' + LIT + r'(?!\s*[%+])')
TSCN_TEXT = re.compile(r'^(?:text|tooltip_text|placeholder_text) = ' + LIT, re.M)


# Lines that handle ids, paths, nodes or logs rather than player text.
PLUMBING = re.compile(r"i18n-skip|\.replace\(|\bbus\b|find_child|get_node|has_node|\.name\s*=|^\s*name\s*=|Analytics\.|\bprint|push_error|"
                      r"push_warning|log_event|ad_event|\bload\(|preload\(|res://|user://|has_method|"
                      r"emit_signal|\bmatch\b|==|!=|\bin \[|_texture\(|theme_|override|\.has\(|\berase\(|"
                      r"get_setting|set_meta|get_meta|\bhash\(|is_connected|\.connect\(|OS\.|Engine\.")
CAMEL = re.compile(r"^[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+$")
IDENT = re.compile(CAMEL.pattern + r"|^[A-Z0-9_]+$")


def scan_literals(line: str) -> list[str]:
    """Every "..." literal on a GDScript line, before any comment, that isn't
    a dictionary key."""
    out = []
    i = 0
    while i < len(line):
        c = line[i]
        if c == "#":
            break
        if c in "\"'":
            j = i + 1
            while j < len(line) and line[j] != c:
                j += 2 if line[j] == "\\" else 1
            if c == '"' and not re.match(r"\s*:", line[j + 1:]):
                out.append(line[i + 1:j])
            i = j + 1
        else:
            i += 1
    return out


def looks_like_text(lit: str) -> bool:
    """A sentence, or a Capitalized word or two, not an identifier."""
    if not re.search(r"[A-Za-z]{2}", lit) or "%" in lit and not re.search(r"\s", lit):
        return False
    if IDENT.match(lit) or re.search(r"[_/\\]|\.(png|glb|gd|tscn|json|ogg|wav)\b", lit):
        return False
    if re.search(r"\s", lit):
        return bool(re.search(r"[A-Za-z]{2,}\s+[A-Za-z]{2,}|[A-Za-z]{3,}", lit))
    return bool(re.match(r"^[+]?[A-Z][a-z]+[!.…?]?$|^[A-Z]{3,}[!]?$", lit))


def unescape(s: str) -> str:
    return (s.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t")
            .replace("\\\\", "\\"))


def po_escape(s: str) -> str:
    return (s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            .replace("\t", "\\t"))


def worth(s: str) -> bool:
    """Skip ids, format-only strings and symbols."""
    if s.startswith("@"):
        return False
    t = re.sub(r"%[-+ 0#]*\d*(?:\.\d+)?[sdfxXcv%]", "", s)
    return bool(re.search(r"[A-Za-z]{2}", t))


def collect() -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}

    def add(msg: str, ref: str) -> None:
        if msg and worth(msg):
            found.setdefault(msg, [])
            if ref not in found[msg]:
                found[msg].append(ref)

    for d in CODE_DIRS:
        for path in sorted(glob.glob(os.path.join(ROOT, d, "**", "*.gd"), recursive=True)):
            rel = os.path.relpath(path, ROOT)
            if rel in SKIP_FILES or rel.startswith(SKIP_DIRS):
                continue
            with open(path, encoding="utf-8") as f:
                for n, line in enumerate(f, 1):
                    if re.search(r"\b(print|push_error|push_warning|printerr)\(", line):
                        continue
                    for m in CALL.finditer(line):
                        add(unescape(m.group(1)), f"{rel}:{n}")
                    for m in PLAIN.finditer(line):
                        lit = unescape(m.group(1))
                        if (re.search(r"\s", lit) or lit[:1].isupper()) and not CAMEL.match(lit):
                            add(lit, f"{rel}:{n}")
                    if not PLUMBING.search(line):
                        for lit in scan_literals(line):
                            if looks_like_text(unescape(lit)):
                                add(unescape(lit), f"{rel}:{n}")
        for path in sorted(glob.glob(os.path.join(ROOT, d, "**", "*.tscn"), recursive=True)):
            rel = os.path.relpath(path, ROOT)
            text = open(path, encoding="utf-8").read()
            for m in TSCN_TEXT.finditer(text):
                add(unescape(m.group(1)), rel)
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "*.json"))):
        if DATA_SKIP.search(path):
            continue
        rel = os.path.relpath(path, ROOT)
        data = json.load(open(path, encoding="utf-8"))

        def walk(x) -> None:
            if isinstance(x, dict):
                for k, v in x.items():
                    if k.startswith("_"):
                        continue
                    if k in DATA_KEYS and isinstance(v, str):
                        add(v, rel)
                    else:
                        walk(v)
            elif isinstance(x, list):
                for v in x:
                    walk(v)
        walk(data)
    return found


def read_po(path: str) -> dict[str, str]:
    """msgid -> msgstr (translated entries only matter; header skipped)."""
    out: dict[str, str] = {}
    if not os.path.exists(path):
        return out
    cur: dict[str, list[str]] = {}
    field = None

    def flush() -> None:
        if "msgid" in cur:
            mid = "".join(cur["msgid"])
            if mid:
                out[unescape_po(mid)] = unescape_po("".join(cur.get("msgstr", [])))
        cur.clear()

    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        obsolete = line.startswith("#~ ")
        if obsolete:
            line = line[3:]
        elif line.startswith("#") or not line:
            if not line:
                flush()
                field = None
            continue
        if line.startswith("msgid "):
            flush()
            field = "msgid"
            cur[field] = [line[6:].strip()[1:-1]]
        elif line.startswith("msgstr "):
            field = "msgstr"
            cur[field] = [line[7:].strip()[1:-1]]
        elif line.startswith('"') and field:
            cur[field].append(line[1:-1])
    flush()
    return out


def unescape_po(s: str) -> str:
    return (s.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t")
            .replace("\\\\", "\\"))


def header(lang: str | None) -> str:
    h = ['msgid ""', 'msgstr ""', '"Project-Id-Version: Grand Exhibit\\n"',
         '"MIME-Version: 1.0\\n"', '"Content-Type: text/plain; charset=UTF-8\\n"',
         '"Content-Transfer-Encoding: 8bit\\n"']
    if lang:
        h.append(f'"Language: {lang}\\n"')
    return "\n".join(h) + "\n"


def entry(msg: str, refs: list[str], tr: str = "") -> str:
    lines = []
    for r in refs[:4]:
        lines.append(f"#: {r}")
    if "%" in msg:
        lines.append("#, c-format")
    lines.append(f'msgid "{po_escape(msg)}"')
    lines.append(f'msgstr "{po_escape(tr)}"')
    return "\n".join(lines) + "\n"


def render(found: dict[str, list[str]], lang: str | None, old: dict[str, str]) -> str:
    parts = [header(lang)]
    for msg in sorted(found, key=lambda m: (found[m][0], m)):
        parts.append(entry(msg, found[msg], old.get(msg, "") if lang else ""))
    if lang:
        gone = [m for m in old if m not in found and old[m] and old[m] != m]
        for m in sorted(gone):
            parts.append(f'#~ msgid "{po_escape(m)}"\n#~ msgstr "{po_escape(old[m])}"\n')
    return "\n".join(parts)


def main() -> int:
    found = collect()
    pot_path = os.path.join(LOCALE, "messages.pot")
    pot = render(found, None, {})
    if "--check" in sys.argv:
        current = open(pot_path, encoding="utf-8").read() if os.path.exists(pot_path) else ""
        if current != pot:
            print("locale/messages.pot is stale: run python3 tools/i18n_extract.py")
            return 1
        return 0
    os.makedirs(LOCALE, exist_ok=True)
    with open(pot_path, "w", encoding="utf-8") as f:
        f.write(pot)
    for po in sorted(glob.glob(os.path.join(LOCALE, "*.po"))):
        lang = os.path.splitext(os.path.basename(po))[0]
        old = read_po(po)
        with open(po, "w", encoding="utf-8") as f:
            f.write(render(found, lang, old))
        done = sum(1 for m in found if old.get(m))
        print(f"{lang}: {done}/{len(found)} translated")
    print(f"{len(found)} strings -> locale/messages.pot")
    return 0


if __name__ == "__main__":
    sys.exit(main())
