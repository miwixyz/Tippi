#!/usr/bin/env python3
"""Experiment 1 (Wortschatz-Profil) + 2 (Alternativen) — 13.10.2026, offline, eigener Server :8094.

Testfälle: dieselben 80 Stellen wie messung.py (Seed 7, Zeile ≤ 400 Zeichen).
Profil: Wortzählung aus Vault-Texten, die NICHT Quelle der Testfälle sind (Notizen/ ausgeschlossen).
Gespeichert wird nur Wort → Anzahl, keine Sätze.

1  Profil: mitten im Wort bekommen erlaubte Stücke einen Zuschlag nach der Häufigkeit
   der Profilwörter, die mit ihnen beginnen (Gewicht w).
2  Alternativen: Wie oft liegt das Zielwort unter den Top-3-Kandidaten fürs erste Stück?
"""
import glob, json, math, os, re, statistics, sys, time, urllib.request
from collections import Counter
sys.argv = [sys.argv[0]]
sys.path.insert(0, ".")
import messung as m
m.PORT = 8094; m.MODEL = "mlx-community/gemma-4-e2b-it-4bit"
m.SYS_C = "Vervollständige den angefangenen Satz des Nutzers. Nur die Fortsetzung, höchstens 8 Wörter."
VAULT = os.path.expanduser(os.environ.get("NOTES_DIR", "~/Notes"))  # Ordner mit eigenen Markdown-Notizen

# --- Quellen der Testfälle (gleiche Auswahl wie korpus.py) ---
quellen = set(glob.glob(os.path.join(VAULT, "04 Ressourcen/KI-Wissen/*.md"))
              + glob.glob(os.path.join(VAULT, "00 Kontext/Schreibstil.md"))
              + glob.glob(os.path.join(VAULT, "03 Bereiche/CineSocial/**/*.md"), recursive=True))

# --- Profil aus allen anderen Vault-Texten ---
WORT = re.compile(r"[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß\-]+")
zaehler = Counter()
dateien = 0
for p in glob.glob(os.path.join(VAULT, "**/*.md"), recursive=True):
    rel = os.path.relpath(p, VAULT)
    if p in quellen or rel.startswith(("Notizen", ".", "06 Archiv", "09 Quellen")) or "/." in rel:
        continue
    try:
        text = open(p, encoding="utf-8").read()
    except Exception:
        continue
    text = re.sub(r"^---.*?---", "", text, flags=re.S)
    text = re.sub(r"`[^`]*`|\[\[[^\]]*\]\]|https?://\S+", " ", text)
    zaehler.update(w.lower() for w in WORT.findall(text))
    dateien += 1
print(f"Profil: {dateien} Dateien, {len(zaehler)} verschiedene Wörter")

# Präfix → Summe der Häufigkeiten (für schnellen Zuschlag)
praefix = Counter()
for w, n in zaehler.items():
    for k in range(1, min(len(w), 14) + 1):
        praefix[w[:k]] += n


def bias_mit_profil(rest, gewicht):
    out = {}
    for i, p in m.vokabular():
        if p and (p.startswith(rest) or (len(p) >= 2 and rest.startswith(p))):
            stamm = p.strip().lower()
            bonus = gewicht * math.log1p(praefix.get(stamm, 0)) if stamm else 0.0
            out[str(i)] = 100.0 + bonus
    return out


def schritt(prompt, bias, top=0):
    body = {"model": m.MODEL, "prompt": prompt, "max_tokens": 2, "temperature": 0.0, "stream": False,
            "logprobs": True, "logit_bias": bias}
    if top:
        body["top_logprobs"] = top
    req = urllib.request.Request(f"http://127.0.0.1:{m.PORT}/v1/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["choices"][0]


def heilen(zeile, gewicht=0.0, alternativen=0):
    """Wie wortheilung2 (Zeile ≤ 400), optional Profil-Zuschlag; liefert Vorschlag + Top-Kandidaten."""
    mm = m.SATZENDE.match(zeile)
    davor, satz = (zeile[:mm.end()], zeile[mm.end():]) if mm else ("", zeile)
    angefangen = m.WORT.findall(satz)[-1]
    basis = satz[:len(satz) - len(angefangen)]
    kopf = m.TEMPLATE.format(sys=m.SYS_C, user=davor.strip() or "(Textanfang)")
    text = basis.rstrip(" ")
    rest = (" " if basis.strip() else "") + angefangen
    wort, kandidaten = "", []
    for schritt_nr in range(4):
        if not rest:
            break
        c = schritt(kopf + text, bias_mit_profil(rest, gewicht), top=alternativen if schritt_nr == 0 else 0)
        content = (c.get("logprobs") or {}).get("content") or []
        if not content:
            break
        if schritt_nr == 0 and alternativen:
            tops = content[0].get("top_logprobs") or []
            kandidaten = [dict(m.vokabular())[t["id"]] for t in tops[:alternativen] if "id" in t]
        t = dict(m.vokabular())[content[0]["id"]]
        text += t
        if t.startswith(rest):
            wort += t[len(rest):]; rest = ""
        elif rest.startswith(t):
            rest = rest[len(t):]
        else:
            break
    weiter = m.completion_bias(kopf + text, None, 20).split("<turn|>")[0].split("\n")[0]
    return wort + weiter, kandidaten, kopf, basis.rstrip(" "), angefangen


def wort_aus_kandidat(kopf, basis, angefangen, stueck):
    """Kandidat fürs erste Stück zu einem ganzen Wort ergänzen (kurze freie Fortsetzung)."""
    rest = (" " if basis.strip() else "") + angefangen
    if not (stueck.startswith(rest) or rest.startswith(stueck)):
        return ""
    weiter = m.completion_bias(kopf + basis + stueck, None, 4).split("<turn|>")[0]
    voll = (basis + stueck + weiter)[len(basis):].lstrip()
    tr = m.WORT.match(voll)
    return tr.group(0) if tr else ""


fs = [f for f in m.faelle(json.load(open("korpus.json", encoding="utf-8")), 80) if f["mitten"]]
print(f"Testfälle mitten im Wort: {len(fs)}")

# --- Experiment 1 ---
for w in (0.0, 1.0, 2.0, 4.0):
    tr = 0; z = []
    for f in fs:
        t0 = time.time(); v, *_ = heilen(m.ctx_heute(f["before"]), gewicht=w); z.append(time.time() - t0)
        r = m.bewerte(f, v); tr += r["t1"]
    print(f"1 Profil Gewicht {w}: mitten im Wort {tr}/40 · Median {statistics.median(z):.2f} s", flush=True)

# --- Experiment 2 ---
top1 = top3 = 0
for f in fs:
    v, kand, kopf, basis, ang = heilen(m.ctx_heute(f["before"]), alternativen=3)
    top1 += m.bewerte(f, v)["t1"]
    woerter = {m.norm(wort_aus_kandidat(kopf, basis, ang, k)) for k in kand}
    top3 += m.bewerte(f, v)["t1"] or m.norm(f["ziel"]) in woerter
print(f"2 Alternativen: Ziel als 1. Vorschlag {top1}/40 · unter den Top 3 {top3}/40")

# --- Experiment 1b: Profil als Auswahl unter den Top-3 des Modells ---
daten = []
for f in fs:
    v, kand, kopf, basis, ang = heilen(m.ctx_heute(f["before"]), alternativen=3)
    woerter = []
    for k in kand:
        w_ = wort_aus_kandidat(kopf, basis, ang, k)
        if w_ and m.norm(w_) not in [m.norm(x) for x in woerter]:
            woerter.append(w_)
    erstes = m.norm(m.WORT.match((ang + v)).group(0)) if v and not v[0].isspace() and m.WORT.match(ang + v) else ""
    daten.append((m.norm(f["ziel"]), erstes, [m.norm(x) for x in woerter]))
for faktor in (1, 3, 10, 30):
    tr = 0
    for ziel, erstes, woerter in daten:
        wahl = erstes
        if woerter:
            beste = max(woerter, key=lambda x: zaehler.get(x, 0))
            if zaehler.get(beste, 0) > faktor * max(1, zaehler.get(erstes, 0)):
                wahl = beste
        tr += wahl == ziel
    print(f"1b Profil wählt unter Top 3, wenn {faktor}× häufiger: {tr}/40")
