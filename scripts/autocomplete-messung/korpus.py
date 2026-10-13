#!/usr/bin/env python3
"""Sammelt deutsche Fließtext-Absätze aus dem Vault als Messkorpus.
Nutzung: python3 -I korpus.py VAULT AUSGABE.json"""
import glob, json, os, re, sys

vault, out = sys.argv[1], sys.argv[2]
quellen = (glob.glob(os.path.join(vault, "04 Ressourcen/KI-Wissen/*.md"))
           + glob.glob(os.path.join(vault, "00 Kontext/Schreibstil.md"))
           + glob.glob(os.path.join(vault, "03 Bereiche/CineSocial/**/*.md"), recursive=True))
deutsch = re.compile(r"\b(und|der|die|das|nicht|ist|mit|für|auf|ein|eine)\b")
dokumente = []
for p in quellen:
    try:
        text = open(p, encoding="utf-8").read()
    except Exception:
        continue
    text = re.sub(r"^---.*?---", "", text, flags=re.S)
    absaetze = []
    for zeile in text.split("\n"):
        z = zeile.strip().lstrip(">-* ").strip()
        if len(z) < 120 or any(s in z for s in ("|", "`", "[[", "http", "](", "<", "{")):
            continue
        z = re.sub(r"\*\*|__|\*", "", z)
        if len(deutsch.findall(z.lower())) < 4 or not z[0].isalpha():
            continue
        absaetze.append(z)
    # Aufeinanderfolgende Absätze einer Datei als ein Dokument (Kontext über Zeilen hinweg)
    for i in range(0, len(absaetze), 4):
        doc = "\n\n".join(absaetze[i:i + 4])
        if len(absaetze[i:i + 4]) >= 2 and len(doc) >= 700:
            dokumente.append(doc)
json.dump(dokumente, open(out, "w", encoding="utf-8"), ensure_ascii=False)
print(f"{len(dokumente)} Dokumente (je 2–4 Absätze) aus {len(quellen)} Dateien")
