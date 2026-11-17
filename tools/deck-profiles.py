#!/usr/bin/env python3
"""Builds the Stream Deck profiles the Tippi plugin ships (Michael 17.11.: "ein fertiges Profil mit allen Funktionen").

Format as Stream Deck's own export (measured by Gnotchi on the profile Elgato's Codex plugin ships): ZIP with `package.json`
and `Profiles/<UUID>.sdProfile/{manifest.json, Profiles/<page>/manifest.json}`. Fixed UUIDs, so every run gives the same file.
Two pages per device – eight keys cannot hold every function. Stream Deck + and Neo switch pages on the device itself
(touch strip swipe / Neo's page buttons).

Run:  python3 -I tools/deck-profiles.py TippiDeck/dev.mwlr.tippi.deck.sdPlugin/profiles
"""
import json
import sys
import uuid
import zipfile
from pathlib import Path

PLUGIN = {"Name": "Tippi", "UUID": "dev.mwlr.tippi.deck", "Version": "2.40.2.0"}
NS = uuid.UUID("2b7f0c4e-91d3-4f6a-8c55-0d3e7a1b9f42")   # namespace for fixed UUIDs
STAMP = (2026, 11, 17, 0, 0, 0)


def fixed(name):
    return str(uuid.uuid5(NS, name))


def key_state():
    return [{"FontFamily": "", "FontSize": 10, "FontStyle": "", "FontUnderline": False, "OutlineThickness": 2,
             "ShowTitle": True, "TitleAlignment": "top", "TitleColor": "#ffffff"}]


NAMES = {"dictation": "Diktat", "prompt": "Prompt", "tool": "Werkzeug", "toggle": "Schalter"}


def action(kind, settings, slot):
    return {"ActionID": fixed(f"{slot}-{kind}-{json.dumps(settings, sort_keys=True)}"), "LinkedTitle": True,
            "Name": NAMES[kind], "Plugin": PLUGIN, "Resources": None, "Settings": settings, "State": 0,
            "States": key_state(), "UUID": f"dev.mwlr.tippi.deck.{kind}"}


def dictation(slot, kind="dictation", press="toggle", mode="standard"):
    return action("dictation", {"kind": kind, "press": press, "mode": mode}, slot)


def prompt(slot, pid=""):
    return action("prompt", {"prompt": pid}, slot)


def tool(slot, name):
    return action("tool", {"tool": name}, slot)


def toggle(slot, name):
    return action("toggle", {"toggle": name}, slot)


def writing_keys(p):
    return {
        "0,0": dictation(p + "00"), "1,0": dictation(p + "10", kind="mail"), "2,0": dictation(p + "20", kind="voiceNote"),
        "3,0": prompt(p + "30"),
        "0,1": prompt(p + "01", "improve"), "1,1": prompt(p + "11", "translateEN"), "2,1": prompt(p + "21", "shorten"),
        "3,1": toggle(p + "31", "language"),
    }


def tool_keys(p):
    return {
        "0,0": tool(p + "00", "translate"), "1,0": tool(p + "10", "emoji"), "2,0": tool(p + "20", "notes"),
        "3,0": tool(p + "30", "quickNotes"),
        "0,1": tool(p + "01", "screenText"), "1,1": tool(p + "11", "password"), "2,1": toggle(p + "21", "autocomplete"),
        "3,1": toggle(p + "31", "pause"),
    }


def dials(p):
    return {"0,0": dictation(p + "d0"), "1,0": prompt(p + "d1", "improve")}


# Device models measured 17.11. in Michael's ProfilesV3 (Gnotchi): Stream Deck + = 20GBD9901, Stream Deck Neo = 20GBJ9901.
PROFILES = [
    {"file": "tippi-plus", "model": "20GBD9901", "second": "Encoder",
     "pages": [("Schreiben", writing_keys("pw"), dials("pw")), ("Werkzeuge", tool_keys("pt"), dials("pt"))]},
    {"file": "tippi-neo", "model": "20GBJ9901", "second": "Neo",
     "pages": [("Schreiben", writing_keys("nw"), None), ("Werkzeuge", tool_keys("nt"), None)]},
]


def build(p, target: Path):
    prof = fixed(p["file"] + "-profile").upper()
    pages = [fixed(f"{p['file']}-page-{i}") for i in range(len(p["pages"]))]
    default = fixed(p["file"] + "-default")
    manifest = {"Device": {"Model": p["model"], "UUID": fixed(p["file"] + "-device")}, "Name": "Tippi",
                "Pages": {"Current": "00000000-0000-0000-0000-000000000000", "Default": default, "Pages": pages},
                "Version": "3.0"}
    default_manifest = {"Controllers": [{"Actions": None, "Type": "Keypad"}, {"Actions": None, "Type": p["second"]}],
                        "Icon": "", "Name": ""}
    package = {"AppVersion": "7.6.1.23033", "DeviceModel": p["model"], "DeviceSettings": None, "FormatVersion": 1,
               "OSType": "macOS", "OSVersion": "27.2", "RequiredPlugins": [PLUGIN["UUID"]]}
    root = f"Profiles/{prof}.sdProfile"
    path = target / f"{p['file']}.streamDeckProfile"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as z:
        def add(name, obj):
            z.writestr(zipfile.ZipInfo(name, date_time=STAMP), json.dumps(obj, ensure_ascii=False, indent=2))

        def folder(name):
            z.writestr(zipfile.ZipInfo(name + "/", date_time=STAMP), "")

        add("package.json", package)
        folder("Profiles")
        folder(root)
        add(f"{root}/manifest.json", manifest)
        folder(f"{root}/Profiles")
        for page, (name, keys, second) in zip(pages, p["pages"]):
            folder(f"{root}/Profiles/{page.upper()}")
            add(f"{root}/Profiles/{page.upper()}/manifest.json",
                {"Controllers": [{"Actions": keys, "Type": "Keypad"}, {"Actions": second, "Type": p["second"]}],
                 "Icon": "", "Name": name})
        folder(f"{root}/Profiles/{default.upper()}")
        add(f"{root}/Profiles/{default.upper()}/manifest.json", default_manifest)
    return path


if __name__ == "__main__":
    target = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    target.mkdir(parents=True, exist_ok=True)
    for p in PROFILES:
        print("written:", build(p, target))
