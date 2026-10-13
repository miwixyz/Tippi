#!/usr/bin/env python3
"""Bekannte Problemfälle: Chat-Modell (Tippis Chat-Weg, Port 8080 NICHT — eigener :8094)
gegen Grundmodell (:8095). Wortgrenze, also ohne Wortheilung."""
import json, sys, urllib.request

SYS_HEUTE = ("Setze den Text des Nutzers fort, in seiner Sprache. Gib NUR die Fortsetzung aus: "
             "den Rest des aktuellen Satzes, höchstens 8 Wörter. Wiederhole den Anfang nicht. "
             "Endet der Text mitten in einem Wort, beginne mit dem Rest dieses Wortes.")
FAELLE = [
    "Kannst du mir sagen wie spät es ist ",
    "Was hältst du davon, wenn wir das Meeting ",
    "Erkläre mir bitte kurz, wie ",
    "Hallo Anna, anbei die Unterlagen für ",
    "Viele Grüße und ein schönes ",
    "Das Kino zeigt diese Woche ",
]


def post(port, path, body):
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


for f in FAELLE:
    chat = post(8094, "/v1/chat/completions", {"model": "mlx-community/gemma-4-e2b-it-4bit",
        "messages": [{"role": "system", "content": SYS_HEUTE}, {"role": "user", "content": f}],
        "max_tokens": 24, "temperature": 0, "chat_template_kwargs": {"enable_thinking": False}})["choices"][0]["message"]["content"]
    basis = post(8095, "/v1/completions", {"model": "mlx-community/gemma-4-e2b-4bit", "prompt": f.rstrip(" "),
        "max_tokens": 16, "temperature": 0})["choices"][0]["text"]
    print(f"{f!r}\n   Chat:  {chat.strip()[:70]!r}\n   Basis: {basis.split(chr(10))[0].strip()[:70]!r}")
