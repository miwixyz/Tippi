#!/usr/bin/env python3
"""Wortanfang: drei Wege, das Leerzeichen dem Modell klarzumachen. 40 Stellen (Seed 7).
V1 heute (Satz ohne Leerzeichen, Ergebnis muss mit neuem Wort beginnen)
V2 Leerzeichen bleibt im vorgegebenen Satz
V3 erstes Wortstück auf ' '+Buchstabe beschränkt (logit_bias)"""
import json, re, statistics, sys, time
sys.argv = [sys.argv[0]]
sys.path.insert(0, ".")
import messung as m
m.PORT = 8094; m.MODEL = "mlx-community/gemma-4-e2b-it-4bit"
SYS = "Vervollständige den angefangenen Satz des Nutzers. Nur die Fortsetzung, höchstens 8 Wörter."


def woerter(t): return [w.lower() for w in re.findall(r"[\wäöüß]+", t)]


def wiederholt(v, z):
    s, t = woerter(v), woerter(z)
    if not s: return False
    if len(t) >= 3 and len(s) >= 3:
        runs = {" ".join(t[i:i+3]) for i in range(len(t)-2)}
        if any(" ".join(s[i:i+3]) in runs for i in range(len(s)-2)): return True
    return bool(t) and s[0] == t[-1]


def neues_wort(v): return len(v) > 1 and v[0].isspace() and (v[1].isalnum() or v[1] in "„\"'(")


def kopf(zeile):
    mm = m.SATZENDE.match(zeile)
    davor, satz = (zeile[:mm.end()], zeile[mm.end():]) if mm else ("", zeile)
    return m.TEMPLATE.format(sys=SYS, user=davor.strip() or "(Textanfang)"), satz


ERLAUBT_LEER = None


def v1(z):
    k, satz = kopf(z); t = m.completion_bias(k + satz.rstrip(" "), None, 20)
    return t.split("<turn|>")[0].split("\n")[0]


def v2(z):
    k, satz = kopf(z); t = m.completion_bias(k + satz, None, 20)
    t = t.split("<turn|>")[0].split("\n")[0]
    return " " + t.lstrip() if t and not t[0].isspace() and t[0].isalnum() else t


def v3(z):
    global ERLAUBT_LEER
    if ERLAUBT_LEER is None:
        ERLAUBT_LEER = {str(i): 100.0 for i, p in m.vokabular() if len(p) >= 2 and p[0] == " " and (p[1].isalpha() or p[1] in "„\"'(")}
        print(f"  (V3: {len(ERLAUBT_LEER)} erlaubte Stücke)")
    k, satz = kopf(z); basis = k + satz.rstrip(" ")
    erstes = m.erstes_stueck(basis, ERLAUBT_LEER)
    weiter = m.completion_bias(basis + erstes, None, 20).split("<turn|>")[0].split("\n")[0]
    return erstes + weiter


fs = [f for f in m.faelle(json.load(open("korpus.json", encoding="utf-8")), 80) if not f["mitten"]]
for name, fn in [("V1 heute", v1), ("V2 Leerzeichen bleibt", v2), ("V3 Stück beschränkt", v3)]:
    tr = weg = 0; z = []
    for f in fs:
        zeile = m.ctx_heute(f["before"]); t0 = time.time(); v = fn(zeile); z.append(time.time() - t0)
        if not neues_wort(v) or wiederholt(v, zeile): weg += 1; continue
        tr += m.norm(m.WORT.search(v).group(0)) == m.norm(f["ziel"])
    print(f"{name}: Treffer {tr}/40 · kein Vorschlag {weg}/40 · Median {statistics.median(z):.2f} s")
