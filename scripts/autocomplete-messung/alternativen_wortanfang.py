#!/usr/bin/env python3
"""Experiment 2b: Alternativen am Wortanfang — liegt das Zielwort unter den Top 3?
Satz als Antwortbeginn (wie Tippi 2.26.1), erste Stücke per top_logprobs, je zum Wort ergänzt."""
import json, re, sys, urllib.request
sys.argv = [sys.argv[0]]
sys.path.insert(0, ".")
import messung as m
m.PORT = 8094; m.MODEL = "mlx-community/gemma-4-e2b-it-4bit"
SYS = "Vervollständige den angefangenen Satz des Nutzers. Nur die Fortsetzung, höchstens 8 Wörter."
VOK = None


def erste_stuecke(prompt, n=8):
    body = {"model": m.MODEL, "prompt": prompt, "max_tokens": 2, "temperature": 0.0, "logprobs": True, "top_logprobs": n}
    req = urllib.request.Request(f"http://127.0.0.1:{m.PORT}/v1/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    c = json.load(urllib.request.urlopen(req, timeout=30))["choices"][0]
    content = (c.get("logprobs") or {}).get("content") or []
    return [t.get("token", "").replace("▁", " ") for t in (content[0].get("top_logprobs") or [])] if content else []


fs = [f for f in m.faelle(json.load(open("korpus.json", encoding="utf-8")), 80) if not f["mitten"]]
top1 = top3 = 0
for f in fs:
    zeile = m.ctx_heute(f["before"])
    mm = m.SATZENDE.match(zeile)
    davor, satz = (zeile[:mm.end()], zeile[mm.end():]) if mm else ("", zeile)
    kopf = m.TEMPLATE.format(sys=SYS, user=davor.strip() or "(Textanfang)") + satz.rstrip(" ")
    woerter = []
    for st in erste_stuecke(kopf):
        if len(st) < 2 or st[0] != " " or not (st[1].isalpha()):
            continue                      # nur Stücke, die ein neues Wort beginnen
        weiter = m.completion_bias(kopf + st, None, 4).split("<turn|>")[0]
        tr = m.WORT.match((st + weiter).lstrip())
        w = m.norm(tr.group(0)) if tr else ""
        if w and w not in woerter:
            woerter.append(w)
        if len(woerter) == 3:
            break
    ziel = m.norm(f["ziel"])
    top1 += bool(woerter) and woerter[0] == ziel
    top3 += ziel in woerter
print(f"Wortanfang: Ziel als 1. Kandidat {top1}/40 · unter den Top 3 {top3}/40")
