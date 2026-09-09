#!/usr/bin/env python3
"""
Generates `Tippi/Resources/emoji-data.json` from Unicode data.

Two sources, each for what it is authoritative about:

  emoji-test.txt (unicode.org)  — WHICH characters are emoji, and in what order
      Only `fully-qualified` entries count. This is what keeps text symbols out
      of the picker: CLDR happily annotates `*`, `@`, `∉` and bare `♥` (the
      playing-card heart, U+2665 without VS16), none of which belong in an
      emoji picker. It also fixes presentation — `❤️` and `⚠️` arrive with
      their variation selector instead of rendering as monochrome glyphs.
      File order is the canonical Unicode grouping (smileys, people, animals,
      …), which is a far better default picker order than CLDR's.

  CLDR annotations              — WHAT each emoji is called, in de and en

Skin-tone variants (U+1F3FB..U+1F3FF) are dropped: they multiply every human
emoji by six and flood search results with near-duplicates. Tippi inserts the
neutral form.

CURATED_ALIASES exists because "first emoji whose keyword list contains this
word" is wrong surprisingly often. CLDR lists "Daumen" for 🫰 (finger heart)
before 👍, "Herz" for a dozen coloured hearts, "Stern" for several. These are
the everyday words where guessing wrong is most visible, so they are pinned by
hand rather than left to file order.

Usage:
    python3 scripts/generate-emoji-data.py            # writes the JSON
    python3 scripts/generate-emoji-data.py --check    # verifies it is current

Licensing: Unicode data (emoji-test.txt + CLDR) is under the Unicode License
v3 — see NOTICES.md.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path

CLDR_REF = "48.2.1"
# Pinned, not "latest": an unpinned URL silently changes the shipped database
# on the next run. (Emoji 17.0 currently exists only under `latest/`, which is
# exactly the kind of moving target this avoids.)
EMOJI_REF = "16.0"

CLDR_BASE = f"https://raw.githubusercontent.com/unicode-org/cldr-json/{CLDR_REF}/cldr-json"
EMOJI_TEST_URL = f"https://unicode.org/Public/emoji/{EMOJI_REF}/emoji-test.txt"

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = REPO_ROOT / "Tippi" / "Resources" / "emoji-data.json"

LANGUAGES = ("de", "en")

SKIN_TONES = {"\U0001F3FB", "\U0001F3FC", "\U0001F3FD", "\U0001F3FE", "\U0001F3FF"}
VARIATION_SELECTOR = "️"

# ä/ö/ü/ß -> ae/oe/ue/ss so ":gruen…" works without reaching for umlaut keys.
# MUST stay in lockstep with `EmojiSearch.normalize` in EmojiDatabase.swift —
# there is a unit test pinning both to the same expected output.
UMLAUT_MAP = {
    "ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss",
    "à": "a", "á": "a", "â": "a", "ã": "a", "å": "a",
    "è": "e", "é": "e", "ê": "e", "ë": "e",
    "ì": "i", "í": "i", "î": "i", "ï": "i",
    "ò": "o", "ó": "o", "ô": "o", "õ": "o",
    "ù": "u", "ú": "u", "û": "u",
    "ç": "c", "ñ": "n",
}

# Hand-pinned `:name:` shortcuts. Everyday words where picking the first
# keyword match lands on something surprising. Verified by eye, one by one.
CURATED_ALIASES = {
    # German
    "daumen": "👍", "daumenhoch": "👍", "daumen_runter": "👎",
    "herz": "❤️", "herzchen": "❤️", "liebe": "❤️",
    "stern": "⭐", "sterne": "⭐",
    "party": "🎉", "feier": "🎉", "konfetti": "🎉",
    "lachen": "😂", "lach": "😂", "weinen": "😢",
    "geld": "💰", "euro": "💶",
    "mail": "📧", "email": "📧", "brief": "✉️",
    "haken": "✅", "erledigt": "✅", "fertig": "✅",
    "kreuz": "❌", "falsch": "❌",
    "warnung": "⚠️", "achtung": "⚠️",
    "idee": "💡", "gluehbirne": "💡",
    "feuer": "🔥", "hundert": "💯",
    "kino": "🍿", "film": "🎬", "kamera": "📷",
    "telefon": "📞", "handy": "📱",
    "uhr": "⏰", "zeit": "⏰", "kalender": "📅",
    "auge": "👀", "augen": "👀",
    "ok": "👌", "okay": "👌",
    "zwinker": "😉", "grinsen": "😁", "cool": "😎",
    "traurig": "😢", "wut": "😡", "schock": "😱",
    "kuss": "😘", "verliebt": "😍",
    "winken": "👋", "hallo": "👋", "tschuess": "👋",
    "beten": "🙏", "danke": "🙏", "bitte": "🙏",
    "klatschen": "👏", "applaus": "👏",
    "denken": "🤔", "nachdenken": "🤔",
    "muede": "😴", "schlafen": "😴",
    "sonne": "☀️", "regen": "🌧️", "schnee": "❄️",
    "kaffee": "☕", "bier": "🍺", "wein": "🍷", "essen": "🍽️",
    "auto": "🚗", "zug": "🚆", "flugzeug": "✈️",
    "haus": "🏠", "buero": "🏢", "schule": "🏫",
    "buch": "📖", "stift": "✏️", "notiz": "📝",
    "musik": "🎵", "mikrofon": "🎤",
    "geschenk": "🎁", "geburtstag": "🎂",
    "punkt": "🔴", "pfeil_rechts": "➡️", "pfeil_links": "⬅️",
    # English
    "thumbsup": "👍", "thumbsdown": "👎",
    "heart": "❤️", "love": "❤️",
    "star": "⭐", "tada": "🎉", "confetti": "🎉",
    "laugh": "😂", "cry": "😢",
    "money": "💰", "check": "✅", "done": "✅",
    "cross": "❌", "warning": "⚠️", "idea": "💡",
    "fire": "🔥", "hundred": "💯",
    "movie": "🎬", "camera": "📷", "phone": "📞",
    "clock": "⏰", "calendar": "📅", "eyes": "👀",
    "wave": "👋", "pray": "🙏", "thanks": "🙏",
    "clap": "👏", "think": "🤔", "sleep": "😴",
    "sun": "☀️", "rain": "🌧️", "snow": "❄️",
    "coffee": "☕", "beer": "🍺", "wine": "🍷",
    "car": "🚗", "train": "🚆", "plane": "✈️",
    "house": "🏠", "book": "📖", "note": "📝",
    "music": "🎵", "gift": "🎁", "cake": "🎂",
    "smile": "😄", "grin": "😁", "wink": "😉",
    "sad": "😢", "angry": "😡", "kiss": "😘",
}
# "cool" is intentionally defined once, in the German block above — a repeated
# key in a dict literal is silently overwritten by the later one, which is a
# trap the next person to edit this table would not see.


def slugify(text: str) -> str:
    out: list[str] = []
    for ch in text.lower():
        if ch in UMLAUT_MAP:
            out.append(UMLAUT_MAP[ch])
        elif ch.isalnum() and ch.isascii():
            out.append(ch)
        else:
            out.append("_")
    slug = "".join(out)
    while "__" in slug:
        slug = slug.replace("__", "_")
    return slug.strip("_")


def fetch(url: str) -> bytes:
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            if response.status != 200:
                raise RuntimeError(f"HTTP {response.status}")
            return response.read()
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
        raise SystemExit(f"ERROR: could not fetch {url}\n       {exc}") from exc


def fetch_json(url: str) -> dict:
    return json.loads(fetch(url).decode("utf-8"))


def load_emoji_order() -> list[str]:
    """Fully-qualified, non-skin-tone emoji in canonical Unicode order."""
    text = fetch(EMOJI_TEST_URL).decode("utf-8")
    line_re = re.compile(r"^([0-9A-F ]+);\s*fully-qualified\s*#")

    ordered: list[str] = []
    seen: set[str] = set()
    current_group = ""

    for line in text.splitlines():
        if line.startswith("# group:"):
            current_group = line.split(":", 1)[1].strip()
            continue
        # "Component" holds skin-tone and hair modifiers on their own — not
        # things anyone picks from a list.
        if current_group == "Component":
            continue
        match = line_re.match(line)
        if not match:
            continue
        codepoints = match.group(1).split()
        char = "".join(chr(int(cp, 16)) for cp in codepoints)
        if any(tone in char for tone in SKIN_TONES):
            continue
        if char not in seen:
            seen.add(char)
            ordered.append(char)
    return ordered


def load_annotations(lang: str) -> dict[str, dict]:
    base = fetch_json(f"{CLDR_BASE}/cldr-annotations-full/annotations/{lang}/annotations.json")
    derived = fetch_json(f"{CLDR_BASE}/cldr-annotations-derived-full/annotationsDerived/{lang}/annotations.json")
    merged: dict[str, dict] = {}
    merged.update(base["annotations"]["annotations"])
    merged.update(derived["annotationsDerived"]["annotations"])
    return merged


def lookup(annotations: dict[str, dict], char: str) -> dict | None:
    """CLDR sometimes keys an emoji without its variation selector."""
    if char in annotations:
        return annotations[char]
    stripped = char.replace(VARIATION_SELECTOR, "")
    return annotations.get(stripped)


def build() -> dict:
    order = load_emoji_order()
    per_lang = {lang: load_annotations(lang) for lang in LANGUAGES}

    entries = []
    missing_annotation = 0

    for char in order:
        de = lookup(per_lang["de"], char)
        en = lookup(per_lang["en"], char)
        if not de or not en or not de.get("tts") or not en.get("tts"):
            missing_annotation += 1
            continue

        name_de = slugify(de["tts"][0])
        name_en = slugify(en["tts"][0])
        if not name_de or not name_en:
            missing_annotation += 1
            continue

        keywords: list[str] = []
        seen = {name_de, name_en}
        for source in (de.get("default", []), en.get("default", [])):
            for raw in source:
                kw = slugify(raw)
                if kw and kw not in seen:
                    seen.add(kw)
                    keywords.append(kw)

        entries.append({"c": char, "n": name_de, "e": name_en, "k": keywords})

    # Curated aliases are only useful if the emoji actually shipped.
    shipped = {entry["c"] for entry in entries}
    aliases = {alias: char for alias, char in CURATED_ALIASES.items() if char in shipped}
    dropped = sorted(set(CURATED_ALIASES) - set(aliases))
    if dropped:
        print(f"WARNING: {len(dropped)} curated alias(es) point at emoji not in the data set:")
        for alias in dropped:
            print(f"         :{alias}: -> {CURATED_ALIASES[alias]!r}")

    return {
        "cldrVersion": CLDR_REF,
        "emojiVersion": EMOJI_REF,
        "generated": date.today().isoformat(),
        "count": len(entries),
        "skippedWithoutAnnotation": missing_annotation,
        "aliases": aliases,
        "emoji": entries,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="exit 1 if the committed file differs from freshly generated data")
    args = parser.parse_args()

    data = build()
    rendered = json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"

    if args.check:
        if not OUTPUT_PATH.exists():
            print(f"FAIL: {OUTPUT_PATH.relative_to(REPO_ROOT)} does not exist")
            return 1
        current = json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))
        if current.get("emoji") != data["emoji"] or current.get("aliases") != data["aliases"]:
            print(f"FAIL: {OUTPUT_PATH.relative_to(REPO_ROOT)} is stale — re-run without --check")
            return 1
        print(f"OK: emoji data current ({data['count']} emoji, Emoji {EMOJI_REF}, CLDR {CLDR_REF})")
        return 0

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(rendered, encoding="utf-8")

    size_kb = len(rendered.encode("utf-8")) / 1024
    print(f"Wrote {OUTPUT_PATH.relative_to(REPO_ROOT)}")
    print(f"  Emoji {EMOJI_REF} · CLDR {CLDR_REF} · {data['count']} emoji · {size_kb:.0f} KB")
    print(f"  {len(data['aliases'])} curated aliases · {data['skippedWithoutAnnotation']} without annotation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
