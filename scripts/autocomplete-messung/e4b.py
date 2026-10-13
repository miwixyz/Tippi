#!/usr/bin/env python3
"""Gemma 4 E4B gegen E2B — dieselben 80 Stellen (Seed 7), dieselben Wege wie Tippi 2.26.1.
Aufruf mit Port und Modell: python -I e4b.py 8096 mlx-community/gemma-4-e4b-it-4bit"""
import json, re, statistics, sys, time
port, modell = int(sys.argv[1]), sys.argv[2]
sys.argv = [sys.argv[0]]
sys.path.insert(0, ".")
import messung as m
m.PORT = port; m.MODEL = modell; m.VOKABULAR = None
m.SYS_C = "Vervollständige den angefangenen Satz des Nutzers. Nur die Fortsetzung, höchstens 8 Wörter."


def woerter(t): return [w.lower() for w in re.findall(r"[\wäöüß]+", t)]


def wiederholt(v, z):
    s, t = woerter(v), woerter(z)
    if not s: return False
    if len(t) >= 3 and len(s) >= 3:
        runs = {" ".join(t[i:i+3]) for i in range(len(t)-2)}
        if any(" ".join(s[i:i+3]) in runs for i in range(len(s)-2)): return True
    return bool(t) and s[0] == t[-1]


def neues_wort(v): return len(v) > 1 and v[0].isspace() and (v[1].isalnum() or v[1] in "„\"'(")


fs = m.faelle(json.load(open("korpus.json", encoding="utf-8")), 80)
mitte = [f for f in fs if f["mitten"]]; anfang = [f for f in fs if not f["mitten"]]

tr = 0; z = []
for f in mitte:
    t0 = time.time(); v, _ = m.wortheilung2(m.ctx_heute(f["before"])); z.append(time.time() - t0)
    tr += m.bewerte(f, v)["t1"]
print(f"{modell}: mitten im Wort {tr}/40 · Median {statistics.median(z):.2f} s", flush=True)

tr = leer = 0; z = []
for f in anfang:
    zeile = m.ctx_heute(f["before"])
    mm = m.SATZENDE.match(zeile); davor, satz = (zeile[:mm.end()], zeile[mm.end():]) if mm else ("", zeile)
    kopf = m.TEMPLATE.format(sys=m.SYS_C, user=davor.strip() or "(Textanfang)")
    t0 = time.time()   # wie Tippi 2.26.1: Satz ohne Leerzeichen vorgeben, nur neues Wort zählt
    weiter = m.completion_bias(kopf + satz.rstrip(" "), None, 20).split("<turn|>")[0].split("\n")[0]
    z.append(time.time() - t0)
    if not neues_wort(weiter) or wiederholt(weiter, zeile): leer += 1; continue
    tr += m.norm(m.WORT.search(weiter).group(0)) == m.norm(f["ziel"])
print(f"{modell}: Wortanfang {tr}/40 · kein Vorschlag {leer}/40 · Median {statistics.median(z):.2f} s", flush=True)
