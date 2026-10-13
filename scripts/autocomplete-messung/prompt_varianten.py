#!/usr/bin/env python3
"""Liegt es am Prompt? Fünf Rahmen für dasselbe Modell (E4B, eigener Server :8096),
dieselben 80 Stellen (Seed 7), Wortheilung wie Tippi (2 Stücke je Schritt), Wortanfang
mit Neues-Wort-Regel und Wiederholungsfilter wie Tippi 2.26.1.

P0 heute: System-Anweisung, Text vor dem Satz als Nutzertext, Satzanfang als Antwortbeginn
P1 ohne System-Anweisung
P2 ganz ohne Gesprächsvorlage: nur der Text (wie ein Grundmodell)
P3 kurze Bitte als Nutzertext, ganzer Text (Zeile) als Antwortbeginn
P4 wie P0, aber mit bis zu 1200 Zeichen Kontext (auch Absätze darüber)
"""
import json, re, statistics, sys, time
sys.argv = [sys.argv[0]]
sys.path.insert(0, ".")
import messung as m
m.PORT = 8096; m.MODEL = "mlx-community/gemma-4-e4b-it-4bit"; m.VOKABULAR = None
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


def zerlegen(text):
    mm = m.SATZENDE.match(text)
    return (text[:mm.end()], text[mm.end():]) if mm else ("", text)


def rahmen(name, text):
    """Liefert (Präfix bis zum Antwortbeginn, Antwortbeginn) für den Kontext `text`."""
    davor, satz = zerlegen(text)
    if name == "P0" or name == "P4":
        return m.TEMPLATE.format(sys=SYS, user=davor.strip() or "(Textanfang)"), satz
    if name == "P1":
        return f"<|turn>user\n{davor.strip() or '(Textanfang)'}<turn|>\n<|turn>model\n", satz
    if name == "P2":
        return "", text
    if name == "P3":
        return "<|turn>user\nSchreibe meinen Text weiter.<turn|>\n<|turn>model\n", text
    raise ValueError(name)


def heilen(kopf, satz):
    angefangen = m.WORT.findall(satz)[-1]
    basis = satz[:len(satz) - len(angefangen)]
    text = basis.rstrip(" ")
    rest = (" " if basis.strip() else "") + angefangen
    wort = ""
    for _ in range(4):
        t = m.erstes_stueck(kopf + text, m.erlaubt(rest))
        if not t: return ""
        text += t
        if t.startswith(rest): wort += t[len(rest):]; rest = ""; break
        elif rest.startswith(t): rest = rest[len(t):]
        else: return ""
    if rest: return ""
    return wort + m.completion_bias(kopf + text, None, 20).split("<turn|>")[0].split("\n")[0]


fs = m.faelle(json.load(open("korpus.json", encoding="utf-8")), 80)
for name in ("P0", "P1", "P2", "P3", "P4"):
    mitte = anfang = leer = 0; z = []
    for f in fs:
        kontext = f["before"][-1200:] if name == "P4" else m.ctx_heute(f["before"])
        kopf, satz = rahmen(name, kontext)
        t0 = time.time()
        if f["mitten"]:
            v = heilen(kopf, satz); z.append(time.time() - t0)
            mitte += m.bewerte(f, v)["t1"]
        else:
            v = m.completion_bias(kopf + satz.rstrip(" "), None, 20).split("<turn|>")[0].split("\n")[0]
            z.append(time.time() - t0)
            if not neues_wort(v) or wiederholt(v, kontext): leer += 1; continue
            anfang += m.norm(m.WORT.search(v).group(0)) == m.norm(f["ziel"])
    print(f"{name}: mitten im Wort {mitte}/40 · Wortanfang {anfang}/40 (kein Vorschlag {leer}) · Median {statistics.median(z):.2f} s", flush=True)
