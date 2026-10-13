#!/usr/bin/env python3
"""Objektive Messung der Tippi-Autovervollständigung (13.10.2026).

Echte deutsche Absätze werden an Wortgrenzen bzw. mitten im Wort abgeschnitten.
Gemessen wird, ob der Vorschlag das tatsächlich folgende Wort trifft.

Varianten (alle temperature 0, gleiche Fälle):
  A  heute: nur aktuelle Zeile, höchstens 400 Zeichen, System-Prompt aus dem Code
  B  mehr Kontext: bis 1500 Zeichen inkl. Zeilen darüber
  weitere Varianten über --varianten

Nutzung: python3 -I messung.py KORPUS.json [--n 80] [--varianten A,B]
"""
import argparse, json, random, re, statistics, sys, time, urllib.request

PORT = 8094
MODEL = "mlx-community/gemma-4-e2b-it-4bit"

SYS_HEUTE = ("Setze den Text des Nutzers fort, in seiner Sprache. Gib NUR die Fortsetzung aus: "
             "den Rest des aktuellen Satzes, höchstens 8 Wörter. Wiederhole den Anfang nicht. "
             "Endet der Text mitten in einem Wort, beginne mit dem Rest dieses Wortes.")


def post(body, timeout=30):
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/chat/completions",
                                 data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    t = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.load(r)
    return data["choices"][0]["message"].get("content") or "", time.time() - t


def chat(system, user, max_tokens=40):
    return post({"model": MODEL, "messages": [{"role": "system", "content": system},
                                              {"role": "user", "content": user}],
                 "stream": False, "max_tokens": max_tokens, "temperature": 0.0,
                 "chat_template_kwargs": {"enable_thinking": False}})


def ctx_heute(before):
    tail = before[-400:]
    return tail.split("\n")[-1]


def ctx_lang(before, n=1500):
    return before[-n:]


SYS_C = ("Du bist eine Autovervollständigung. Schreibe den Text des Nutzers genau dort weiter, "
         "wo er aufhört, in seiner Sprache und seinem Stil. Nur den Rest des aktuellen Satzes, "
         "höchstens 8 Wörter, keine Erklärung.")
TEMPLATE = "<|turn>system\n{sys}<turn|>\n<|turn>user\n{user}<turn|>\n<|turn>model\n"
SATZENDE = re.compile(r"(?s).*[.!?:]\s+|.*\n")


def completion(prompt, max_tokens=24):
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/completions",
                                 data=json.dumps({"model": MODEL, "prompt": prompt, "max_tokens": max_tokens,
                                                  "temperature": 0.0, "stream": False}).encode(),
                                 headers={"Content-Type": "application/json"})
    t = time.time()
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.load(r)
    return data["choices"][0].get("text") or "", time.time() - t


def vorgabe(before, n=1500, sys_prompt=None):
    """Kontext bis zum aktuellen Satz als Nutzertext, der angefangene Satz als Beginn
    der Modellantwort. Das Modell kann dann nur weiterschreiben."""
    ctx = before[-n:]
    m = SATZENDE.match(ctx)
    davor, satz = (ctx[:m.end()], ctx[m.end():]) if m else ("", ctx)
    prefill = satz.rstrip(" ")
    roh, dt = completion(TEMPLATE.format(sys=sys_prompt or SYS_C, user=davor.strip() or "(Textanfang)") + prefill)
    roh = roh.split("<turn|>")[0].split("\n")[0]
    # Leerzeichen, das wir am Prefill abgeschnitten haben, wieder berücksichtigen
    if satz.endswith(" ") and roh and not roh.startswith(" "):
        roh = roh  # Modell hängt direkt an: als neues Wort werten
    return roh.lstrip() if satz.endswith(" ") or not satz else roh, dt


VOKABULAR = None


def vokabular():
    global VOKABULAR
    if VOKABULAR is None:
        from transformers import AutoTokenizer
        tok = AutoTokenizer.from_pretrained(MODEL, local_files_only=True)   # nur aus dem Zwischenspeicher, nie laden
        VOKABULAR = [(i, (p or "").replace("▁", " ")) for i, p in
                     enumerate(tok.convert_ids_to_tokens(list(range(len(tok)))))]
    return VOKABULAR


def erlaubt(rest):
    """Wortstücke, die mit dem noch offenen Wortanfang beginnen oder selbst ein Anfang davon sind."""
    return {str(i): 100.0 for i, p in vokabular()
            if p and (p.startswith(rest) or (len(p) >= 2 and rest.startswith(p)))}


def completion_bias(prompt, bias, max_tokens):
    body = {"model": MODEL, "prompt": prompt, "max_tokens": max_tokens, "temperature": 0.0, "stream": False}
    if bias:
        body["logit_bias"] = bias
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["choices"][0].get("text") or ""


def wortheilung(before, n=1500):
    """D: wie C, aber das angefangene Wort wird nicht als Text vorgegeben, sondern über
    erlaubte Wortstücke erzwungen (token healing)."""
    t0 = time.time()
    ctx = before[-n:]
    m = SATZENDE.match(ctx)
    davor, satz = (ctx[:m.end()], ctx[m.end():]) if m else ("", ctx)
    if satz and not satz[-1].isspace():
        angefangen = WORT.findall(satz)[-1]
        basis = satz[:len(satz) - len(angefangen)]
    else:
        angefangen, basis = "", satz
    kopf = TEMPLATE.format(sys=SYS_C, user=davor.strip() or "(Textanfang)")
    text = basis.rstrip(" ")
    rest = (" " if basis.strip() else "") + angefangen if angefangen else ""
    wort = ""
    for _ in range(4):                      # höchstens 4 Wortstücke, bis der Anfang verbraucht ist
        if not rest:
            break
        t = completion_bias(kopf + text, erlaubt(rest), 1)
        if not t:
            break
        text += t
        if t.startswith(rest):
            wort += t[len(rest):]
            rest = ""
        elif rest.startswith(t):
            rest = rest[len(t):]
        else:
            break
    weiter = completion_bias(kopf + text, None, 20).split("<turn|>")[0].split("\n")[0]
    vorschlag = wort + weiter
    if not angefangen:
        vorschlag = vorschlag.lstrip()
    return vorschlag, time.time() - t0


def erstes_stueck(prompt, bias):
    """Wie completion_bias(…, 1), aber mit max_tokens=2 und nur dem ersten Stück.
    Umgeht den mlx-lm-Fehler (Anfrage = vorige Anfrage + erzeugtes Stück hängt den
    Server auf): Der Zwischenspeicher hält dann vorige Anfrage + ZWEI Stücke."""
    body = {"model": MODEL, "prompt": prompt, "max_tokens": 2, "temperature": 0.0, "stream": False,
            "logprobs": True, "logit_bias": bias}
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        c = json.load(r)["choices"][0]
    ids = [x["id"] for x in (c.get("logprobs") or {}).get("content", [])]
    return dict(vokabular())[ids[0]] if ids else ""


def wortheilung2(before):
    t0 = time.time()
    ctx = before
    m = SATZENDE.match(ctx)
    davor, satz = (ctx[:m.end()], ctx[m.end():]) if m else ("", ctx)
    if satz and not satz[-1].isspace():
        angefangen = WORT.findall(satz)[-1]
        basis = satz[:len(satz) - len(angefangen)]
    else:
        angefangen, basis = "", satz
    kopf = TEMPLATE.format(sys=SYS_C, user=davor.strip() or "(Textanfang)")
    text = basis.rstrip(" ")
    rest = (" " if basis.strip() else "") + angefangen if angefangen else ""
    wort = ""
    for _ in range(4):
        if not rest:
            break
        t = erstes_stueck(kopf + text, erlaubt(rest))
        if not t:
            break
        text += t
        if t.startswith(rest):
            wort += t[len(rest):]
            rest = ""
        elif rest.startswith(t):
            rest = rest[len(t):]
        else:
            break
    weiter = completion_bias(kopf + text, None, 20).split("<turn|>")[0].split("\n")[0]
    vorschlag = wort + weiter
    if not angefangen:
        vorschlag = vorschlag.lstrip()
    return vorschlag, time.time() - t0


VARIANTEN = {
    "DZ2": lambda before: wortheilung2(ctx_heute(before)),
    "DZ": lambda before: wortheilung(ctx_heute(before)),
    "D": lambda before: wortheilung(before),
    "A": lambda before: chat(SYS_HEUTE, ctx_heute(before)),
    "B": lambda before: chat(SYS_HEUTE, ctx_lang(before)),
    "C": lambda before: vorgabe(before),
}

WORT = re.compile(r"[\wäöüÄÖÜß\-]+", re.UNICODE)


def norm(w):
    return w.lower().strip("-")


def erstes_wort(text):
    m = WORT.search(text)
    return norm(m.group(0)) if m else ""


def zusammensetzen(before, vorschlag):
    """Vorschlag an den Text hängen wie Tippi: endet der Text mitten im Wort, setzt
    der Vorschlag das Wort fort (ohne Leerzeichen), sonst neues Wort."""
    v = vorschlag.strip().strip('"„“').split("\n")[0]
    if before and not before[-1].isspace() and vorschlag[:1].isspace():
        return before + " " + v               # Modell hält das Wort für fertig
    if before and not before[-1].isspace():
        # Modell wiederholt manchmal das angefangene Wort komplett
        angefangen = WORT.findall(before)[-1] if WORT.findall(before) else ""
        if angefangen and norm(v).startswith(norm(angefangen)):
            v = v[len(angefangen):]
        return before + v
    return before + " " + v if not before.endswith(" ") else before + v


def faelle(korpus, n, seed=7):
    rnd = random.Random(seed)
    out = []
    while len(out) < n:
        text = rnd.choice(korpus)
        spaces = [m.start() for m in re.finditer(r" ", text) if 300 <= m.start() < len(text) - 25]
        if not spaces:
            continue
        mitten = len(out) % 2 == 1
        pos = rnd.choice(spaces) + 1          # Cursor nach dem Leerzeichen
        rest = text[pos:]
        m = WORT.match(rest)
        if not m or len(m.group(0)) < 4:
            continue
        ziel = m.group(0)
        if mitten:
            k = rnd.randint(2, min(len(ziel) - 1, 4))
            before = text[:pos + k]
        else:
            before = text[:pos]
        naechste = WORT.findall(text[pos:])[:2]
        out.append({"before": before, "ziel": ziel, "zwei": [norm(w) for w in naechste], "mitten": mitten})
    return out


def bewerte(fall, vorschlag):
    voll = zusammensetzen(fall["before"], vorschlag)
    rest = voll[len(fall["before"]) - (0 if not fall["mitten"] else 0):]
    # Wort am Cursor nach dem Einsetzen
    start = len(fall["before"])
    if fall["mitten"]:
        start = len(fall["before"]) - len(WORT.findall(fall["before"])[-1])
    neue = WORT.findall(voll[start:])
    w1 = norm(neue[0]) if neue else ""
    w2 = [norm(w) for w in neue[:2]]
    return {"leer": not vorschlag.strip(), "t1": w1 == norm(fall["ziel"]), "t2": w2 == fall["zwei"], "w1": w1}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("korpus")
    ap.add_argument("--n", type=int, default=80)
    ap.add_argument("--varianten", default="A,B")
    ap.add_argument("--details", action="store_true")
    a = ap.parse_args()
    korpus = json.load(open(a.korpus, encoding="utf-8"))
    fs = faelle(korpus, a.n)
    for v in a.varianten.split(","):
        res, zeiten = [], []
        for f in fs:
            vorschlag, dt = VARIANTEN[v](f["before"])
            zeiten.append(dt)
            r = bewerte(f, vorschlag)
            r["mitten"] = f["mitten"]
            res.append(r)
            if a.details:
                print(f"  [{v}] {'M' if f['mitten'] else 'W'} …{f['before'][-45:]!r} → {vorschlag[:50]!r} | Ziel {f['ziel']!r} {'✓' if r['t1'] else '✗'}")
        def quote(rs, k):
            return f"{sum(r[k] for r in rs)}/{len(rs)} ({100 * sum(r[k] for r in rs) / max(1, len(rs)):.0f} %)"
        w = [r for r in res if not r["mitten"]]
        m = [r for r in res if r["mitten"]]
        print(f"Variante {v}: 1. Wort {quote(res, 't1')} · 2 Wörter {quote(res, 't2')} · leer {quote(res, 'leer')} · "
              f"Wortgrenze {quote(w, 't1')} · mitten im Wort {quote(m, 't1')} · "
              f"Median {statistics.median(zeiten):.2f} s")


if __name__ == "__main__":
    main()
