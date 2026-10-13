#!/usr/bin/env python3
"""Direktvergleich Cotypist vs. Tippi (13.10.2026): dieselben 40 Stellen
(20 Wortanfang, 20 mitten im Wort, Seed 7 wie messung.py), je einmal ⇥.
Nutzung: python3 -I vergleich.py <Name> [n]   → schreibt ergebnis-<Name>.json"""
import json, subprocess, sys, tempfile, time
sys.path.insert(0, ".")
sys_argv = sys.argv[:]
sys.argv = [sys.argv[0]]
import messung as m

name = sys_argv[1]
n = int(sys_argv[2]) if len(sys_argv) > 2 else 40
korpus = json.load(open("korpus.json", encoding="utf-8"))
faelle = m.faelle(korpus, 80)[:n]          # abwechselnd Wortgrenze / mitten im Wort
TIPPEN = 4                                 # so viele Zeichen am Ende werden echt getippt

import subprocess as _sp
_v = _sp.run(["/usr/bin/defaults", "read", "-g", "NSDocumentSaveNewDocumentsToCloud"], capture_output=True, text=True).stdout.strip()
if _v != "0":
    sys.exit("ABBRUCH: NSDocumentSaveNewDocumentsToCloud ist nicht 0 — TextEdit würde in iCloud speichern")
ORDNER = tempfile.mkdtemp(prefix="tippi-vergleich-")   # eigener, zufälliger Ordner
ergebnisse = []
for i, f in enumerate(faelle):
    text = f["before"][-1200:]
    zeile_start = text.rfind("\n") + 1
    k = min(TIPPEN, len(text) - zeile_start)
    davor, getippt = text[:-k], text[-k:]
    import os
    ordner = ORDNER   # nur Kontext-Übergabe an osascript; TextEdit öffnet die Datei NICHT
    datei = f"{ordner}/{name}-{i+1:02d}.txt"
    with open(datei, "w", encoding="utf-8") as tf:
        tf.write(davor)
    t0 = time.time()
    try:
        out = subprocess.run(["/usr/bin/osascript", "vergleich.applescript", datei, getippt],
                             capture_output=True, text=True, timeout=40)
    except subprocess.TimeoutExpired:
        print(f"{i+1}: Zeitüberschreitung (TextEdit blockiert?) — Test angehalten"); break
    doc = out.stdout.rstrip("\n")
    if doc.startswith("ABBRUCH") or out.returncode != 0:
        print(f"{i+1}: {doc or out.stderr.strip()} — Test angehalten"); break
    eingefuegt = doc[len(text):] if doc.startswith(text) else None
    if eingefuegt is None:
        wort, status = "", "Text verändert"
    elif eingefuegt in ("", "\t") or eingefuegt.startswith("\t"):
        wort, status = "", "kein Vorschlag"
    else:
        if f["mitten"]:
            angefangen = m.WORT.findall(text)[-1]
            treffer_wort = m.WORT.match(angefangen + eingefuegt)
        else:
            treffer_wort = m.WORT.search(eingefuegt)
        wort = treffer_wort.group(0) if treffer_wort else ""
        status = "✓" if m.norm(wort) == m.norm(f["ziel"]) else "✗"
    ergebnisse.append({"mitten": f["mitten"], "ziel": f["ziel"], "wort": wort, "eingefuegt": eingefuegt, "status": status})
    print(f"{i+1:2d} {'M' if f['mitten'] else 'W'} …{text[-30:]!r} → {(eingefuegt or '')[:25]!r} | Ziel {f['ziel']!r} {status}  ({time.time()-t0:.1f}s)", flush=True)

json.dump(ergebnisse, open(f"ergebnis-{name}.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
w = [e for e in ergebnisse if not e["mitten"]]; mi = [e for e in ergebnisse if e["mitten"]]
z = lambda rs, s: sum(e["status"] == s for e in rs)
print(f"\n{name}: Wortanfang {z(w,'✓')}/{len(w)} · mitten im Wort {z(mi,'✓')}/{len(mi)} · "
      f"kein Vorschlag {z(ergebnisse,'kein Vorschlag')} · Text verändert {z(ergebnisse,'Text verändert')}")
