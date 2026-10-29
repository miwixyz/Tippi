#!/usr/bin/env python3
"""Versionshinweise fürs Update-Fenster: Abschnitt einer Version aus CHANGELOG.md als kleines HTML.

Sparkle zeigt eine Datei `<Archivname>.html` neben dem Archiv im Update-Fenster an, wenn
generate_appcast mit `--embed-release-notes` läuft. Vorbild: TippAI 1.6.0 (Michael 29.10.:
„Auflistung der neuen und verbesserten Funktionen – für alle Apps“). Gleiche Datei in Tippi,
Kalli, Gnotchi und Seam.

Versteht beide Kopfzeilen: `## [1.2.3] — 2026-10-29` und `## 1.2.3 - 2026-10-29`.
Einleitungssätze → Absatz, `### Neu` → Zwischentitel, `- **Fett.** Text` → Punkt
(auch über mehrere Zeilen). Kein Abschnitt für die Version → Exit 1, damit der Release stoppt.

Aufruf: release-notes.py <version> <CHANGELOG.md> <ausgabe.html>
"""
import html
import re
import sys


# Abschnitte für Entwickler (Testzahlen, Dateinamen, Scan-Kennungen) gehören nicht ins Update-Fenster.
INTERNAL = re.compile(r"^(intern|internal|technical|technisch|doku|documentation|build|nacharbeit|belegt"
                      r"|tests?\b|behoben während der entwicklung)", re.IGNORECASE)


def section(changelog: str, version: str) -> list[str]:
    head = re.compile(r"^##\s+\[?" + re.escape(version) + r"\]?(\s|$)")
    lines, take, skip = [], False, False
    for line in changelog.splitlines():
        if line.startswith("## "):
            if take:
                break
            take = bool(head.match(line))
            continue
        if not take:
            continue
        if line.startswith("### "):
            skip = bool(INTERNAL.match(line[4:].strip()))
        if not skip:
            lines.append(line.rstrip())
    return lines


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)          # Links: nur der Text
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return text


def render(lines: list[str]) -> str:
    blocks, current = [], None   # current = ["p"|"li", text]

    def flush():
        nonlocal current
        if current and current[1].strip():
            tag = "p" if current[0] == "p" else "li"
            blocks.append((tag, inline(current[1].strip())))
        current = None

    for line in lines:
        stripped = line.strip()
        if not stripped:
            flush()
        elif stripped.startswith("### "):
            flush()
            blocks.append(("h3", inline(stripped[4:])))
        elif stripped.startswith(("- ", "* ")):
            flush()
            current = ["li", stripped[2:]]
        elif current:                       # Fortsetzung eines Punkts oder Absatzes
            current[1] += " " + stripped
        else:
            current = ["p", stripped]
    flush()

    out, in_list = [], False
    for tag, text in blocks:
        if tag == "li" and not in_list:
            out.append("<ul>")
            in_list = True
        if tag != "li" and in_list:
            out.append("</ul>")
            in_list = False
        out.append(f"<{tag}>{text}</{tag}>")
    if in_list:
        out.append("</ul>")
    return "".join(out)


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    version, changelog_path, output = sys.argv[1:]
    with open(changelog_path, encoding="utf-8") as handle:
        lines = section(handle.read(), version)
    body = render(lines)
    if "<li>" not in body and "<p>" not in body:
        print(f"Kein CHANGELOG-Abschnitt mit Inhalt für {version}", file=sys.stderr)
        return 1
    with open(output, "w", encoding="utf-8") as handle:
        handle.write('<meta charset="utf-8">' + body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
