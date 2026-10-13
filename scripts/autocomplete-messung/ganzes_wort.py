#!/usr/bin/env python3
"""Bestes ganzes Wort statt bestes erstes Stück (E4B, :8096, dieselben 80 Stellen).
Für die K wahrscheinlichsten ersten Stücke: zum ganzen Wort ergänzen; Wort-Wert = Summe
der Log-Wahrscheinlichkeiten seiner Stücke. Gewählt wird das Maximum. Vergleich mit
„erstes Stück gierig" (heute). Rahmen P0 (Zeile) und P4 (1200 Zeichen)."""
import json, re, sys, urllib.request
sys.argv = [sys.argv[0]]
sys.path.insert(0, ".")
import messung as m
m.PORT = 8096; m.MODEL = "mlx-community/gemma-4-e4b-it-4bit"; m.VOKABULAR = None
SYS = "Vervollständige den angefangenen Satz des Nutzers. Nur die Fortsetzung, höchstens 8 Wörter."
K = 5


def frage(prompt, n, bias=None, top=0):
    body = {"model": m.MODEL, "prompt": prompt, "max_tokens": n, "temperature": 0.0, "logprobs": True}
    if bias: body["logit_bias"] = bias
    if top: body["top_logprobs"] = top
    req = urllib.request.Request(f"http://127.0.0.1:{m.PORT}/v1/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=60))["choices"][0]


def stueck(tid):
    return dict(m.vokabular())[tid]


VOK = None


def text_of(tid):
    global VOK
    if VOK is None: VOK = dict(m.vokabular())
    return VOK.get(tid, "")


def wort_wert(kopf, praefix, erstes_id, erstes_lp, schon):
    """Ganzes Wort ab `erstes` (+ was davor schon zum Wort gehört) und sein Log-Wert."""
    erstes = text_of(erstes_id)
    c = frage(kopf + praefix + erstes, 6)
    wert = erstes_lp
    wort = schon + erstes.lstrip()
    for e in (c.get("logprobs") or {}).get("content", []):
        t = text_of(e["id"])
        if not t or t[0] == " " or not re.match(r"[\wäöüÄÖÜß]", t): break
        teil = re.match(r"[\wäöüÄÖÜß]+", t).group(0)
        wort += teil; wert += e["logprob"]
        if len(teil) < len(t): break
    return wort, wert


def zerlegen(text):
    mm = m.SATZENDE.match(text)
    return (text[:mm.end()], text[mm.end():]) if mm else ("", text)


def kandidaten(kopf, praefix, rest):
    """Top-K erste Stücke (bei offenem Wortanfang beschränkt) mit Log-Wahrscheinlichkeit."""
    bias = m.erlaubt(rest) if rest else None
    c = frage(kopf + praefix, 2, bias=bias, top=K + 3)
    tops = ((c.get("logprobs") or {}).get("content") or [{}])[0].get("top_logprobs") or []
    out = []
    for t in tops:
        s = text_of(t["id"])
        if rest and not (s.startswith(rest)): continue           # nur Stücke, die den Anfang abdecken
        if not rest and not (len(s) > 1 and s[0] == " " and s[1].isalpha()): continue
        out.append((t["id"], t["logprob"]))
        if len(out) == K: break
    return out


fs = m.faelle(json.load(open("korpus.json", encoding="utf-8")), 80)
for rahmen in ("P0", "P4"):
    gierig = {"m": 0, "a": 0}; wort = {"m": 0, "a": 0}
    for f in fs:
        kontext = f["before"][-1200:] if rahmen == "P4" else m.ctx_heute(f["before"])
        davor, satz = zerlegen(kontext)
        kopf = m.TEMPLATE.format(sys=SYS, user=davor.strip() or "(Textanfang)")
        if f["mitten"]:
            ang = m.WORT.findall(satz)[-1]; basis = satz[:len(satz) - len(ang)].rstrip(" ")
            rest = (" " if basis.strip() else "") + ang
        else:
            basis = satz.rstrip(" "); rest = ""; ang = ""
        kand = kandidaten(kopf, basis, rest)
        if not kand: continue
        bewertet = [wort_wert(kopf, basis, tid, lp, "") for tid, lp in kand]
        # Wort ohne den getippten Anfang vergleichen: Ziel ist das ganze Wort
        g = bewertet[0][0]; b = max(bewertet, key=lambda x: x[1])[0]
        ziel = m.norm(f["ziel"]); k = "m" if f["mitten"] else "a"
        gierig[k] += m.norm(g) == ziel; wort[k] += m.norm(b) == ziel
    print(f"{rahmen}: erstes Stück gierig  → mitten {gierig['m']}/40 · Wortanfang {gierig['a']}/40", flush=True)
    print(f"{rahmen}: bestes ganzes Wort   → mitten {wort['m']}/40 · Wortanfang {wort['a']}/40", flush=True)
