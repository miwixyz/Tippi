#!/usr/bin/env python3
"""Prüfstand für die Diktat-Glättung — VOR einem Wechsel des Anthropic-Standardmodells laufen lassen.

Warum (2026-10-28): modell-pruefstand.py prüft die eingebauten Prompts (Übersetzen, Kürzen …),
nicht die Glättung nach dem Diktat. Genau dort fiel Haiku 5.5 am 2026-10-09 an echten Diktaten
durch: Füllwörter („also“, „genau“) blieben stehen, „punkt“ wurde zu „Pünktlich“. Der andere
Prüfstand stand bei beiden Modellen auf 20/20 und hätte das nie gezeigt.

Zwei Fallsätze wie in modell-pruefstand.py:
  STEUERFÄLLE  — hier unten, sichtbar. Damit wird der Glättungs-Prompt angepasst.
  ABNAHMEFÄLLE — scripts/diktat-pruefstand-abnahme.json. Beim Anpassen NICHT ansehen.

Liest den Glättungs-Prompt live aus Tippi/Core/DictationController.swift
(`defaultPostProcessPrompt`) und baut die Anfrage wie AnthropicProvider: max_tokens 8192,
temperature 0.1 (TaskTemperature.transcriptCleanup) nur für Modelle, die sie annehmen,
Haiku 5.x mit effort low + thinking disabled. Glossar („Eigene Wörter“) ist nicht enthalten.

Aufruf:   python3 scripts/diktat-pruefstand.py                  # Standardmodell aus dem Code
          python3 scripts/diktat-pruefstand.py claude-haiku-5-5
          python3 scripts/diktat-pruefstand.py claude-haiku-5-5 --nur-steuer
Exit:     0 = alle Fälle bestanden · 1 = mindestens ein Fehler · 2 = Aufbaufehler
Kosten:   18 kurze Anthropic-Aufrufe (Schlüssel aus dem Vault-Schlüsselbund).
"""
import json
import os
import re
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request

HIER = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HIER, "..")
KEYS = os.path.expanduser("~/MWs2ndBrain/04 Ressourcen/KI-Wissen/keys.sh")
ABNAHME = os.path.join(HIER, "diktat-pruefstand-abnahme.json")

# nie = Wort/Wortfolge darf nicht vorkommen (ganze Wörter, ohne Groß/klein) · muss = Teilstring muss vorkommen
STEUERFAELLE = [
    {"text": "also ich wollte nur kurz sagen dass das meeting morgen ausfällt", "nie": ["also"], "muss": ["Meeting", "ausfällt"]},
    {"text": "genau also wir treffen uns dann um drei vor dem eingang genau", "nie": ["genau", "also"], "muss": ["drei", "Eingang"]},
    {"text": "bring es bitte einfach auf den punkt", "muss": ["auf den Punkt"], "nie": ["pünktlich"]},
    {"text": "der zug kommt punkt acht in münchen an", "muss": ["Punkt acht", "München"], "nie": ["pünktlich"]},
    {"text": "äh ich hab halt irgendwie keine zeit dafür", "nie": ["äh", "halt", "irgendwie"], "muss": ["keine Zeit"]},
    {"text": "genau das meine ich damit", "muss": ["Genau das"]},
    {"text": "kannst du mir sagen wie spät es ist", "muss": ["spät", "?"], "nie": ["uhr"]},
    {"text": "ähm schick mir die datei bitte bis morgen früh", "nie": ["ähm"], "muss": ["Datei", "morgen früh"]},
    {"text": "so um like i was thinking we could you know meet on friday", "nie": ["um", "like", "you know"], "muss": ["Friday"]},
    {"text": "wir haben drei punkte auf der agenda erstens budget zweitens personal", "muss": ["Punkte", "Budget", "Personal"]},
    {"text": "also das heißt wir müssen also früher anfangen", "muss": ["früher anfangen"]},
    {"text": "ich ich wollte dich fragen ob das passt", "nie": ["ich ich"], "muss": ["passt"]},
]


def swift_string(src, start):
    """Inhalt eines mehrzeiligen Swift-Strings ab Index von '\"\"\"' — mit Swifts Einrückungsregel."""
    a = src.index('"""', start) + 3
    e = src.index('"""', a)
    zeilen = src[a:e].split("\n")[1:]
    einzug = len(zeilen[-1]) - len(zeilen[-1].lstrip())
    return "\n".join(z[einzug:] for z in zeilen[:-1])


def aufbau():
    src = open(os.path.join(ROOT, "Tippi/Core/DictationController.swift"), encoding="utf-8").read()
    prompt = swift_string(src, src.index("static let defaultPostProcessPrompt"))
    prov = open(os.path.join(ROOT, "Tippi/LLM/AnthropicProvider.swift"), encoding="utf-8").read()
    m = re.search(r'let defaultModel = "([^"]+)"', prov)
    if not m or "max_tokens: 8192" not in prov or 'hasPrefix("claude-haiku-5")' not in prov:
        sys.exit("✗ AnthropicProvider.swift hat sich geändert — Anfrageform im Prüfstand anpassen")
    return prompt, m.group(1)


def anfrage(modell, system, text):
    body = {"model": modell, "max_tokens": 8192, "system": system,
            "messages": [{"role": "user", "content": text}]}
    if modell.startswith("claude-haiku-5"):
        body.update(output_config={"effort": "low"}, thinking={"type": "disabled"})
    elif modell.startswith(("claude-haiku-4", "claude-sonnet-4", "claude-opus-4-5", "claude-opus-4-6",
                            "claude-opus-4-1", "claude-3")):
        body["temperature"] = 0.1
    return body


# Gilt für jeden Fall: Vorrede oder Anführungszeichen statt nur des Textes (Gegenprobe 2026-10-28:
# ohne diese Zeile rutschte „Hier ist der bereinigte Text: …“ durch).
VORREDE = re.compile(r"^\s*(hier ist|here is|here's|bereinigt|cleaned|output:)|^\s*[\"„“'«]", re.IGNORECASE)


def pruefe(fall, out):
    fehl = [f"„{w}“ steht noch da" for w in fall.get("nie", [])
            if re.search(r"(?<!\w)" + re.escape(w) + r"(?!\w)", out, re.IGNORECASE)]
    fehl += [f"„{w}“ fehlt" for w in fall.get("muss", []) if w not in out]
    if VORREDE.search(out):
        fehl.append("Vorrede oder Anführungszeichen statt nur des Textes")
    return fehl


def main():
    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    nur_steuer = "--nur-steuer" in sys.argv
    prompt, standard = aufbau()
    modell = argv[0] if argv else standard
    key = subprocess.run(["/bin/bash", KEYS, "get", "ANTHROPIC_API_KEY"], capture_output=True, text=True).stdout.strip()
    if not key:
        sys.exit("✗ ANTHROPIC_API_KEY nicht im Schlüsselbund")
    print(f"Modell {modell} · Standard im Code: {standard}\n")

    saetze = [("Steuerfälle", STEUERFAELLE)]
    if not nur_steuer:
        saetze.append(("Abnahmefälle", json.load(open(ABNAHME, encoding="utf-8"))["faelle"]))
    zeiten, ergebnis = [], {}
    for name, faelle in saetze:
        ok = 0
        print(f"── {name}")
        for f in faelle:
            req = urllib.request.Request("https://api.anthropic.com/v1/messages",
                                         data=json.dumps(anfrage(modell, prompt, f["text"])).encode(), method="POST",
                                         headers={"x-api-key": key, "anthropic-version": "2023-06-01",
                                                  "content-type": "application/json"})
            t = time.time()
            try:
                with urllib.request.urlopen(req, timeout=90) as r:
                    d = json.load(r)
            except urllib.error.HTTPError as e:
                print(f"✗ HTTP {e.code}: {e.read()[:300]!r}")
                sys.exit(2)
            zeiten.append(time.time() - t)
            out = "".join(b.get("text", "") for b in d.get("content", []) if b.get("type") == "text").strip()
            fehl = pruefe(f, out)
            ok += not fehl
            print(f"{'✓' if not fehl else '✗'} {f['text'][:40]!r:44} → {out.replace(chr(10), ' ⏎ ')[:80]!r}"
                  + (f"   [{'; '.join(fehl)}]" if fehl else ""))
        ergebnis[name] = (ok, len(faelle))
        print()
    bilanz = " · ".join(f"{n} {o}/{g}" for n, (o, g) in ergebnis.items())
    print(f"{modell}: {bilanz} · Median {statistics.median(zeiten):.2f} s")
    if nur_steuer:
        print("Hinweis: nur Steuerfälle — für eine Modellentscheidung ohne --nur-steuer laufen lassen.")
    sys.exit(0 if all(o == g for o, g in ergebnis.values()) else 1)


if __name__ == "__main__":
    main()
