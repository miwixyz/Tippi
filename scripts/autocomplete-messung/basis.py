#!/usr/bin/env python3
"""Gemma-4-GRUNDMODELL (mlx-community/gemma-4-e2b-4bit, mlx-lm 0.32.0, Port 8095)
gegen dieselben Fälle wie messung.py (80, Seed 7) und satzanfang.py (40, Seed 11).

  G-Roh   Zeile (≤400 Zeichen) als reiner Text, frei fortsetzen
  G-Heil  wie G-Roh, aber das angefangene Wort per Wortheilung (2 Stücke je Schritt)

Kein Chat-Format, keine Anweisung — das Grundmodell setzt nur Text fort.
Nutzung: ~/.local/share/uv/tools/mlx-lm/bin/python -I basis.py
"""
import json, random, re, statistics, sys, time
sys.argv = [sys.argv[0]]
sys.path.insert(0, ".")
import messung as m

m.MODEL = "mlx-community/gemma-4-e2b-4bit"
m.PORT = 8095
m.VOKABULAR = None


def roh(line):
    text, dt = m.completion_bias(line.rstrip(" "), None, 20), 0
    return text, dt


def g_roh(line):
    t0 = time.time()
    weiter = m.completion_bias(line.rstrip(" "), None, 20).split("\n")[0]
    if line.endswith(" ") and weiter[:1] not in (" ", ""):
        weiter = weiter  # Modell klebt an: wird unten als Fehlschlag gewertet
    return (weiter if not line.endswith(" ") else weiter.lstrip()), time.time() - t0


def g_heil(line):
    t0 = time.time()
    if line and not line[-1].isspace():
        angefangen = m.WORT.findall(line)[-1]
        basis = line[:len(line) - len(angefangen)]
    else:
        angefangen, basis = "", line
    text = basis.rstrip(" ")
    rest = (" " if basis.strip() else "") + angefangen if angefangen else ""
    wort = ""
    for _ in range(4):
        if not rest:
            break
        t = m.erstes_stueck(text, m.erlaubt(rest))
        if not t:
            break
        text += t
        if t.startswith(rest):
            wort += t[len(rest):]; rest = ""
        elif rest.startswith(t):
            rest = rest[len(t):]
        else:
            break
    weiter = m.completion_bias(text, None, 20).split("\n")[0]
    v = wort + weiter
    return (v.lstrip() if not angefangen else v), time.time() - t0


VARIANTEN = {"G-Roh": g_roh, "G-Heil": g_heil}

# --- 80 Fälle wie messung.py (Zeile ≤ 400 Zeichen) ---
korpus = json.load(open("korpus.json", encoding="utf-8"))
fs = m.faelle(korpus, 80)
for name, f in VARIANTEN.items():
    res, z = [], []
    for fall in fs:
        v, dt = f(m.ctx_heute(fall["before"]))
        z.append(dt)
        r = m.bewerte(fall, v); r["mitten"] = fall["mitten"]; res.append(r)
    w = [r for r in res if not r["mitten"]]; mi = [r for r in res if r["mitten"]]
    print(f"80 Fälle {name}: Wortgrenze {sum(r['t1'] for r in w)}/40 · mitten im Wort {sum(r['t1'] for r in mi)}/40 · "
          f"leer {sum(r['leer'] for r in res)} · Median {statistics.median(z):.2f} s")

# --- 40 Satzanfänge wie satzanfang.py (gleiche Auswahl, Seed 11) ---
LECK = re.compile(r"\b(sprache|stil|autovervollständigung|erklärung|nutzers?|fortsetzung|vervollständige)\b", re.I)


def satz_faelle(korpus, n=40, seed=11):
    rnd = random.Random(seed)
    out, saetze = [], []
    for doc in korpus:
        for absatz in doc.split("\n\n"):
            erster = re.split(r"(?<=[.!?])\s", absatz)[0]
            if len(erster) > 50:
                saetze.append(erster)
    rnd.shuffle(saetze)
    for satz in saetze:
        kandidaten = [w for w in list(m.WORT.finditer(satz))[2:] if len(w.group(0)) >= 4]
        if not kandidaten:
            continue
        w = rnd.choice(kandidaten)
        k = rnd.randint(2, min(len(w.group(0)) - 1, 4))
        out.append({"line": satz[:w.start() + k], "ziel": w.group(0)})
        if len(out) >= n:
            break
    return out


sf = satz_faelle(korpus)
v_heil = []
treffer, z = 0, []
for fall in sf:
    v, dt = g_heil(fall["line"])
    z.append(dt)
    ang = m.WORT.findall(fall["line"])[-1]
    wort = (ang + v).split()[0] if v and not v[0].isspace() else ang
    wort = m.WORT.match(wort).group(0) if m.WORT.match(wort) else wort
    treffer += m.norm(wort) == m.norm(fall["ziel"])
    v_heil.append((fall["line"][-35:], v[:45], fall["ziel"]))
print(f"40 Satzanfänge G-Heil: Treffer {treffer}/40 · Median {statistics.median(z):.2f} s")
for a, b, c in v_heil[:8]:
    print(f"   …{a!r} → {b!r} | Ziel {c!r}")
