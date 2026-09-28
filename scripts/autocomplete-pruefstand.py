#!/usr/bin/env python3
"""Prüfstand für die Autovervollständigung — Blindvergleich verschiedener Anfrage-Wege.

Warum (2026-09-28): Michael fand Tippis Vorschläge schwächer als Cotypists, obwohl
beide Gemma 4 E2B nutzen. Es gab kein Bewertungs-Set; jede Änderung am Prompt wäre
ein Bauchgefühl gewesen. Dieser Prüfstand schickt dieselben Textanfänge über mehrere
Wege an lokale mlx_lm.server und schreibt einen Blindvergleich (Markdown) plus die
Zuordnung (JSON) zum Auflösen.

Wege:
  A  heute:        Chat-Modell über /v1/chat/completions mit Tippis Systemanweisung
                   (wörtlich aus AutocompleteLogic.swift), 400 Zeichen, temperature 0.2
  D  chat-plus:    dasselbe Chat-Modell, aber App + Textart in der Anweisung, 2 Beispiele
                   (Few-Shot), 1500 Zeichen Kontext, temperature 0, Stopp an Zeilenende
  C  grundmodell:  Grundmodell (ohne Chat-Training) auf zweitem Port als reine
                   Textfortsetzung mit Dokumentkopf, temperature 0

Widerlegt (gemessen 2026-09-28, nicht erneut probieren): das Chat-Modell gemma-4-e2b-it
über /v1/completions als reine Textfortsetzung — mit und ohne <bos> Wiederholungsschleifen
(„die die die…"), Sprachwechsel ins Indonesische, Emojis. Es braucht das Chat-Format.
Das Gemma-4-Grundmodell mlx-community/gemma-4-e2b-4bit lädt mit mlx-lm 0.31.3 nicht
(„Received 140 parameters not in model").

Aufruf:
  python3 scripts/autocomplete-pruefstand.py --out pruefstand.md
      [--chat-port 8080 --chat-model mlx-community/gemma-4-e2b-it-4bit]
      [--base-port 8091 --base-model mlx-community/gemma-4-e2b-4bit]   # ohne --base-port: nur A/B

Nur Loopback (127.0.0.1). Schickt keine echten Nutzertexte — die Fälle unten sind erfunden.
"""
import argparse
import json
import random
import re
import time
import urllib.request

SYSTEM_PROMPT = (
    "Setze den Text des Nutzers fort, in seiner Sprache. Gib NUR die Fortsetzung aus: "
    "den Rest des aktuellen Satzes, höchstens 8 Wörter. Wiederhole den Anfang nicht. "
    "Endet der Text mitten in einem Wort, beginne mit dem Rest dieses Wortes."
)

# (App, Art, Text vor dem Cursor). Bewusst typische Alltagstexte, teils mitten im Wort.
FAELLE = [
    ("Mail", "E-Mail", "Hallo Patrik,\n\nvielen Dank für die schnelle Rückmeldung zum Ticket. Ich habe mir die Änderungen angesehen und"),
    ("Mail", "E-Mail", "Liebe Frau Tastan,\n\nwie telefonisch besprochen schicke ich Ihnen anbei den"),
    ("Mail", "E-Mail", "Hallo zusammen,\n\nder Kinostart von „Corpus Delicti“ ist am Donnerstag. Könnt ihr mir bis Dienstag die"),
    ("Mail", "E-Mail", "Sehr geehrte Damen und Herren,\n\nhiermit kündige ich meinen Vertrag fristgerecht zum"),
    ("Mail", "E-Mail", "Hi Cati,\n\nich habe dir die Dienste für Oktober im Kalender eingetragen. Schau bitte kurz drüber, ob"),
    ("Nachrichten", "Chat-Nachricht", "Bin in 10 Minuten da, soll ich noch was"),
    ("Nachrichten", "Chat-Nachricht", "Danke dir! Das war echt ein schöner Abend, lass uns das bald"),
    ("WhatsApp", "Chat-Nachricht", "Hast du morgen Zeit? Ich würde gern mit dir über das neue Pro"),
    ("Notizen", "Notiz", "Einkaufsliste für Samstag: Brot, Milch, Tomaten und"),
    ("Notizen", "Notiz", "Ideen für den Instagram-Post vom Roxy Kino: Behind the Scenes im Vorführraum, dazu ein kurzes Video vom"),
    ("Notizen", "Notiz", "Meeting mit CINEWEB am Mittwoch. Themen: Relaunch-Zeitplan, offene Tickets und die Frage, wer"),
    ("Slack", "Chat-Nachricht", "Kurzes Update: Das Release ist raus, die Tests sind grün. Ich schaue mir heute Nachmittag noch"),
    ("Safari", "Formular", "Ich interessiere mich für Ihr Angebot und hätte gern weitere Informationen zu den Preisen für"),
    ("Pages", "Dokument", "Die Kinobranche steht vor einem tiefgreifenden Wandel. Streaming-Dienste haben das Verhalten der Zuschauer verändert, doch das gemeinsame Erlebnis auf der großen Leinwand"),
    ("Pages", "Dokument", "Zusammenfassend lässt sich sagen, dass die Umstellung auf das neue System sowohl Zeit als auch"),
    ("Mail", "E-Mail", "Hallo Antonio,\n\nich habe mich wegen deines Catering-Plans informiert. Für den Start brauchst du auf jeden Fall eine"),
    ("Mail", "E-Mail", "Guten Morgen,\n\nleider muss ich unseren Termin am Freitag absagen, da mir kurzfristig etwas dazwischen"),
    ("Nachrichten", "Chat-Nachricht", "Kannst du mir die Adresse vom Restaurant nochmal schi"),
    ("Mail", "E-Mail", "Hallo Herr Müller,\n\nanbei finden Sie die Rechnung für den Hausbesuch vom 24. September. Bitte überweisen Sie den Betrag inner"),
    ("Notizen", "Notiz", "To-do für die Woche: Reddit-Post vorbereiten, GIF der Autovervollständigung aufnehmen und danach"),
]


def post(url, body, timeout=20):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read())
    return data, time.monotonic() - t0


def kuerzen(text):
    """Grob wie Tippis Nachbearbeitung: erste Zeile, bis Satzende, höchstens 8 Wörter/80 Zeichen."""
    text = next((z for z in text.splitlines() if z.strip()), "")
    m = re.search(r"[.!?…](\s|$)", text)
    if m:
        text = text[: m.end()].rstrip()
    woerter = text.split(" ")
    if len([w for w in woerter if w]) > 8:
        text = " ".join(woerter[: 8 + (1 if woerter and woerter[0] == "" else 0)])
    return text[:80].rstrip()


def weg_a(port, model, ctx):
    body = {"model": model, "messages": [{"role": "system", "content": SYSTEM_PROMPT},
                                         {"role": "user", "content": ctx[-400:]}],
            "stream": False, "max_tokens": 40, "temperature": 0.2,
            "chat_template_kwargs": {"enable_thinking": False}}
    data, dt = post(f"http://127.0.0.1:{port}/v1/chat/completions", body)
    out = data["choices"][0]["message"].get("content", "")
    return kuerzen(out.lstrip()), dt


FEW_SHOT = [
    ("Ich komme heute etwas später, weil der Zug", "Verspätung hat."),
    ("Vielen Dank für Ihre Nachricht. Ich melde mich bis Frei", "tag bei Ihnen."),
]


def weg_d(port, model, app, art, ctx):
    system = (
        f"Du bist die Autovervollständigung einer Tastatur. Der Nutzer schreibt gerade eine {art} "
        f"auf Deutsch in {app}. Gib die wahrscheinlichste, natürliche Fortsetzung seines Textes aus: "
        "nur die nächsten 2 bis 6 Wörter, höchstens bis zum Satzende. Wiederhole nichts, was schon "
        "dasteht. Keine Anführungszeichen, keine Erklärung. Endet der Text mitten in einem Wort, "
        "setze genau dieses Wort fort."
    )
    msgs = [{"role": "system", "content": system}]
    for frage, antwort in FEW_SHOT:
        msgs += [{"role": "user", "content": frage}, {"role": "assistant", "content": antwort}]
    msgs.append({"role": "user", "content": ctx[-1500:]})
    body = {"model": model, "messages": msgs, "stream": False, "max_tokens": 24, "temperature": 0.0,
            "stop": ["\n"], "chat_template_kwargs": {"enable_thinking": False}}
    data, dt = post(f"http://127.0.0.1:{port}/v1/chat/completions", body)
    return kuerzen(data["choices"][0]["message"].get("content", "").lstrip()), dt


def kopf(app, art):
    return f"Der folgende Text ist eine {art} auf Deutsch, geschrieben in {app}.\n\n"


def weg_fortsetzung(port, model, app, art, ctx):
    body = {"model": model, "prompt": kopf(app, art) + ctx[-1500:], "max_tokens": 20,
            "temperature": 0.0, "stop": ["\n"], "stream": False}
    data, dt = post(f"http://127.0.0.1:{port}/v1/completions", body)
    return kuerzen(data["choices"][0].get("text", "")), dt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chat-port", type=int, default=8080)
    ap.add_argument("--chat-model", default="mlx-community/gemma-4-e2b-it-4bit")
    ap.add_argument("--base-port", type=int)
    ap.add_argument("--base-model", default="mlx-community/gemma-3n-E2B-4bit")
    ap.add_argument("--out", default="autocomplete-pruefstand.md")  # aktueller Ordner, nicht /tmp (Rafter R-B8507)
    ap.add_argument("--seed", type=int, default=28)
    a = ap.parse_args()

    rnd = random.Random(a.seed)
    zuordnung, zeilen, zeiten = [], [], {"A": [], "D": [], "C": []}
    for nr, (app, art, ctx) in enumerate(FAELLE, 1):
        erg = {}
        erg["A"], t = weg_a(a.chat_port, a.chat_model, ctx); zeiten["A"].append(t)
        erg["D"], t = weg_d(a.chat_port, a.chat_model, app, art, ctx); zeiten["D"].append(t)
        if a.base_port:
            erg["C"], t = weg_fortsetzung(a.base_port, a.base_model, app, art, ctx); zeiten["C"].append(t)
        wege = list(erg)
        rnd.shuffle(wege)
        labels = "XYZ"[: len(wege)]
        zuordnung.append({"fall": nr, **{labels[i]: w for i, w in enumerate(wege)}})
        sicht = ctx.replace("\n", " ⏎ ")
        zeilen.append(f"### {nr}. {app} ({art})\n\n> …{sicht[-160:]}▌\n")
        for i, w in enumerate(wege):
            zeilen.append(f"- **{labels[i]}:** {erg[w] or '— (kein Vorschlag)'}")
        zeilen.append("\n**Beste:** ___\n")
        print(f"{nr:2d}. " + " | ".join(f"{w}: {erg[w]!r}" for w in "ADC" if w in erg))

    kopfzeilen = [
        "# Autovervollständigung — Blindvergleich\n",
        "Pro Fall: welcher Vorschlag passt am besten? Buchstaben eintragen (auch „keiner“ ist erlaubt).",
        "Die Buchstaben sind pro Fall zufällig vertauscht.\n",
    ]
    with open(a.out, "w", encoding="utf-8") as f:
        f.write("\n".join(kopfzeilen + zeilen) + "\n")
    with open(a.out.rsplit(".", 1)[0] + "-zuordnung.json", "w", encoding="utf-8") as f:
        json.dump({"faelle": zuordnung,
                   "latenz_median_s": {k: sorted(v)[len(v) // 2] for k, v in zeiten.items() if v}}, f, indent=1)
    for k, v in zeiten.items():
        if v:
            print(f"Latenz {k}: Median {sorted(v)[len(v)//2]:.2f} s, max {max(v):.2f} s")
    print(f"→ {a.out}")


if __name__ == "__main__":
    main()
