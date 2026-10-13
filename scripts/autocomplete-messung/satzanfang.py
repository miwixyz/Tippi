#!/usr/bin/env python3
"""Wortheilung, wenn die Zeile nur aus dem aktuellen Satz besteht (kein Text davor).
Misst Treffer mitten im Wort und wie oft Wörter aus der Anweisung durchsickern."""
import json, random, re, statistics, sys, time
sys.path.insert(0, ".")
import messung as m

SYS_C = m.SYS_C
SYS_KURZ = "Vervollständige den angefangenen Satz des Nutzers. Nur die Fortsetzung, höchstens 8 Wörter."
LECK = re.compile(r"\b(sprache|stil|autovervollständigung|erklärung|nutzers?|fortsetzung|vervollständige)\b", re.I)


def variante(user_text, system):
    def lauf(line):
        split_m = m.SATZENDE.match(line)
        davor, satz = (line[:split_m.end()], line[split_m.end():]) if split_m else ("", line)
        angefangen = m.WORT.findall(satz)[-1]
        basis = satz[:len(satz) - len(angefangen)]
        user = user_text(davor, line)
        kopf = m.TEMPLATE.format(sys=system, user=user)
        text = basis.rstrip(" ")
        rest = (" " if basis.strip() else "") + angefangen
        wort = ""
        t0 = time.time()
        for _ in range(4):
            t = m.erstes_stueck(kopf + text, m.erlaubt(rest))
            if not t:
                break
            text += t
            if t.startswith(rest):
                wort += t[len(rest):]; rest = ""; break
            elif rest.startswith(t):
                rest = rest[len(t):]
            else:
                break
        weiter = m.completion_bias(kopf + text, None, 20).split("<turn|>")[0].split("\n")[0]
        return wort + weiter, time.time() - t0
    return lauf


VARIANTEN = {
    "U1 heute (Textanfang)": variante(lambda davor, line: davor.strip() or "(Textanfang)", SYS_C),
    "U2 kurze Anweisung":    variante(lambda davor, line: davor.strip() or "(Textanfang)", SYS_KURZ),
    "U3 Zeile als Nutzertext": variante(lambda davor, line: line, SYS_KURZ),
}


def faelle(korpus, n=40, seed=11):
    rnd = random.Random(seed)
    out = []
    saetze = []
    for doc in korpus:
        for absatz in doc.split("\n\n"):
            erster = re.split(r"(?<=[.!?])\s", absatz)[0]
            if len(erster) > 50:
                saetze.append(erster)
    rnd.shuffle(saetze)
    for s in saetze:
        woerter = [mm for mm in m.WORT.finditer(s)]
        kandidaten = [w for w in woerter[2:] if len(w.group(0)) >= 4]
        if not kandidaten:
            continue
        w = rnd.choice(kandidaten)
        k = rnd.randint(2, min(len(w.group(0)) - 1, 4))
        out.append({"line": s[:w.start() + k], "ziel": w.group(0)})
        if len(out) >= n:
            break
    return out


fs = faelle(json.load(open("korpus.json", encoding="utf-8")))
for name, f in VARIANTEN.items():
    treffer = leck = 0
    zeiten = []
    for fall in fs:
        v, dt = f(fall["line"])
        zeiten.append(dt)
        angefangen = m.WORT.findall(fall["line"])[-1]
        wort = (angefangen + v).split()[0] if v and not v[0].isspace() else angefangen
        wort = m.WORT.match(wort).group(0) if m.WORT.match(wort) else wort
        treffer += m.norm(wort) == m.norm(fall["ziel"])
        leck += bool(LECK.search(v))
    print(f"{name}: Treffer {treffer}/{len(fs)} · Anweisung durchgesickert {leck}/{len(fs)} · Median {statistics.median(zeiten):.2f} s")
