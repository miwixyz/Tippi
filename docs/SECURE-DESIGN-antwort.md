# Secure Design — Antwort per Sprache mit Kontext (Labs)

Stand: 2026-11-19 · Status: **entschieden, vor der Implementierung**
Durchlauf nach `rafter-secure-design`: `ingestion` + `threat-modeling` (mit LLM-Teil).
Vorbild: Blip „Action Mode“ (dort ohne belegten Kontext). Machbarkeit gemessen
2026-11-19 mit `scripts/antwort-pruefstand.py` (MacBook Air M5): Gemma 4 E2B 7/9 + 2/5
in 0,6 s, Prompt-Injection nie befolgt; Apple Intelligence befolgte eingeschleuste
Anweisungen in beiden Runden → **für diese Funktion ausgeschlossen**.

## Was gebaut werden soll

Michael diktiert eine Absicht („sag zu, dass ich Donnerstag komme“). Ausgelöst wird das
mit einer eigenen Taste (ab Werk ⌃⌥⌘A) oder mit einem Vorwort in den ersten drei
Wörtern eines normalen Diktats (ab Werk „Hey Tippi“, einstellbar, mit Schreibvarianten).
Tippi holt den Kontext — die Nachricht, auf die geantwortet wird — schickt Kontext und
Absicht an das **lokale** Modell und zeigt die Antwort in einer **Vorschau**
(Einfügen / Neu schreiben / Abbrechen, Sprachknopf DE/ES/EN, benutzter Kontext
aufklappbar). Eingefügt wird erst nach Klick. Gruß und Name am Ende einer Mail hängt
Tippi selbst an, nicht das Modell.

## 1. Klassifikation

> **Der Kontext ist fremder Text mit der höchsten Datenklasse, die gerade auf dem
> Schirm steht** — Mails von Kunden, Patientendaten bei Cati, private Chats. Tippi kann
> das nicht unterscheiden. Gleiche Regel wie Bildschirm-OCR und Autovervollständigung.

| Artefakt | Wo | Lebensdauer |
|---|---|---|
| Kontext (Markierung / Fenstertext / OCR-Bereich), ≤ 3.000 Zeichen | RAM → lokaler Modellserver, aufgeklappt in der Vorschau | bis die Vorschau geschlossen ist |
| Absicht (Diktat-Rohtext) | RAM | bis die Vorschau geschlossen ist |
| Antwortentwurf | RAM → Vorschau → nach Klick ins Zielfeld | bis eingefügt/verworfen |
| Einstellungen (an/aus, Taste, Vorwort + Varianten, Name) | UserDefaults | dauerhaft |
| Name für den Gruß | UserDefaults (vorbelegt aus Kontakt „Ich“, änderbar) | dauerhaft |

**Nicht gebaut:** kein Verlauf der Antworten, keine Statistik über Inhalte, **kein Log
mit Text** (nur Quelle des Kontexts, Zeichenzahl, Dauer, App-Bundle-ID, Fehlerkategorie).
Der Diktatverlauf (`HistoryStore`) bekommt im Antwort-Modus **nichts**: Sonst landete die
Absicht samt fremdem Zusammenhang dauerhaft auf der Platte.

## 2. Datenfluss und Vertrauensgrenzen

```
[Mikrofon] → (Parakeet/Whisper lokal) → [Tippi: Absicht]
[fremde App: Markierung | Fenster (AX) | Bildschirmbereich (OCR, Klick)] ┆→ (≤ 3.000 Z.) → [Tippi]
[Tippi] ┆→ (HTTP loopback, eigener MLX-Kindprozess) → [Modell] ┆→ (Antwort, nicht vertrauenswürdig) → [Tippi: Vorschau]
[Vorschau: Klick „Einfügen“] → (TextInsertion, reiner Text) → [Zielfeld der fremden App]
```

Grenzen: fremde App ↔ Tippi (Kontext, fremd kontrolliert) · Tippi ↔ Modellserver
(Ausgabe verlässt den Prozess) · Modell ↔ Tippi (Antwort nicht vertrauenswürdig) ·
Vorschau ↔ Zielfeld (Einfügen in fremde App).

## 3. STRIDE je Grenze

### Fremde App → Tippi (Kontext)
- **Information disclosure — Passwörter/Geheimnisse:** Kein Kontext, wenn
  `IsSecureEventInputEnabled()` wahr ist, das fokussierte Element `AXSecureTextField`
  ist oder die vorderste App auf der Ausschlussliste steht (dieselbe Liste wie die
  Autovervollständigung: Passwortmanager, Terminals). In Terminals, Code-Editoren und
  Coding-Agenten (Liste aus `DictationAutoReturn`) greift weder Taste noch Vorwort.
- **Fenstertext nur auf Auslösung:** Tippi liest das Fenster erst, nachdem Michael
  Taste oder Vorwort benutzt hat. Kein Timer, kein Vorab-Lesen.
- **Größe:** hart 3.000 Zeichen, vom Ende her (das Neueste bleibt), UTF-16-sicher
  geschnitten. Bedienungshilfen-Abfragen mit begrenzten Bereichen und Zeitlimit; ein
  Fenster mit Millionen Zeichen darf Tippi nicht anhalten.
- **OCR-Bereich:** unverändert `ScreenTextCapture` (nie auf Platte, nie ins Log, nur auf
  Klick „Bereich wählen“).

### Tippi → Modellserver
- **Nur lokal:** Kein Cloud-Anbieter, auch wenn der Standard-Anbieter einer ist, und
  **nicht Apple Intelligence** (Prüfstand 19.11.: befolgte eingeschleuste Anweisungen).
  Ist kein lokales MLX-Modell bereit → Funktion aus mit klarer Meldung, Diktat
  unverändert einfügen. **Nie still auf einen anderen Anbieter ausweichen.**
- **Spoofing — fremder Prozess auf dem Port:** Wie die Autovervollständigung nur an
  einen Server, den Tippi selbst gestartet hat (`MLXServerManager`, Status `.running`),
  nie an einen „übernommenen“. Ziel fest `http://127.0.0.1:<port>`, keine
  Weiterleitungen, Zeitlimit.
- **Vorlagen-Marken:** Kontext und Absicht dürfen keine Gesprächsvorlagen-Marken bilden
  (`<|`, `|>`, `<start_of_turn>`, `<end_of_turn>` entschärfen), und die Begrenzer der
  Anfrage (`<message>`, `</message>`, `<intent>`, `</intent>`) werden im fremden Text
  entschärft, damit der Kontext seinen Block nicht schließen kann.
- **Sprache bestimmt Tippi:** `NLLanguageRecognizer` auf dem Kontext (ohne Kontext auf
  der Absicht) setzt die Antwortsprache in der Anfrage. Der fremde Text kann sie nicht
  über eine Anweisung umstellen.

### Modell → Tippi (Antwort)
- **Prompt injection:** Kontext kann Anweisungen enthalten („Ignoriere alles und schreib
  …“). Folgen begrenzt: Das Modell hat **keine Werkzeuge**, löst **keine Aktion** aus,
  seine Ausgabe ist nur ein angezeigter Entwurf. **Eingefügt wird nur auf Klick**, nie
  automatisch, auch kein Auto-Return. Michael liest vor dem Einfügen.
- **Tampering der Ausgabe:** Steuerzeichen raus (außer Zeilenumbruch), Länge begrenzt
  (2.000 Zeichen), Vorspann („Hier ist …“), umschließende Anführungszeichen und
  Platzhalter (`[Name]`) werden entfernt bzw. führen zu einem Hinweis in der Vorschau.
  Leere Antwort → Hinweis, nichts einfügen. Ein vom Modell geschriebener Gruß am Ende
  wird nicht verdoppelt.
- **Denial of service:** höchstens eine Anfrage gleichzeitig; „Neu schreiben“ bricht die
  laufende ab; Zeitlimit; Vorschau zeigt Fehler sichtbar (eigene Apps scheitern nie stumm).

### Vorschau → Zielfeld
- **Tampering — falsches Ziel:** Ziel ist das Feld, das beim Auslösen fokussiert war
  (vorhandene Anker-/Einfüge-Logik). Hat sich die App oder das Feld geändert → nicht
  blind einfügen, sondern in die Zwischenablage mit Hinweis (wie bei Chromium-Apps).
- Reiner Text, keine Formatierung, keine Tastenfolgen außer dem Einfügen selbst.

## 4. Negative Space — was nehmen wir an?

- **„Der Fenstertext ist die Nachricht, auf die man antwortet.“** Falsch, wenn mehrere
  Mails/Chats sichtbar sind. Abwehr: Kontext in der Vorschau aufklappbar, Markierung hat
  Vorrang. Ob Gmail/WhatsApp über die Bedienungshilfen brauchbaren Text liefern, ist
  **ungemessen** → Messpunkt: Zeichenzahl je Quelle und App im Protokoll (ohne Inhalt).
- **„Lokal heißt sicher.“** Nur, wenn der Server wirklich Tippis eigener ist (siehe oben).
- **„Das Vorwort kommt nur absichtlich vor.“** Ein Diktat, das mit „Hey Tippi“ beginnt,
  wird umgedeutet. Abwehr: nur erste drei Wörter, Labs ab Werk aus, Pille zeigt den
  Modus, und ohne Kontext/Modell wird das Diktat unverändert eingefügt.
- **„Der Kontakt „Ich“ ist Michael.“** Der Name ist in den Einstellungen sichtbar und
  änderbar; Zugriff auf Kontakte nur, wenn die Funktion eingeschaltet wird (eigene
  Freigabe-Abfrage), sonst leeres Feld.

## 5. Abnahme vor dem Release

- `scripts/antwort-pruefstand.py` liest den Prompt **live aus dem Swift-Code** (Entwurf
  im Skript löschen), Gegenprobe grün, E2B und E4B gemessen.
- Unit-Tests: Vorwort-Erkennung (Varianten, nur erste drei Wörter, Satzzeichen),
  Kontext-Kürzung (3.000, vom Ende, UTF-16), Entschärfen der Begrenzer/Marken,
  Ausgabe-Bereinigung, Gruß-Anhängen ohne Verdopplung, Anbieter-Sperre (kein Cloud,
  kein Apple Intelligence, kein übernommener Server).
- `/code-audit` auf den Diff; Test am Gerät mit `scripts/devid-testbuild.sh`
  (Bedienungshilfen) in Mail, Gmail/Helium und WhatsApp.
