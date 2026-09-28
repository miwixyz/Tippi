# Secure Design — Währungsrechner und Passwortgenerator

Stand: 2026-09-28 · Status: **entschieden, vor der Implementierung**
Durchlauf nach `rafter-secure-design`: `ingestion` + `threat-modeling`.

## Was gebaut werden soll

1. **Währungsrechner** (Schnellaktion). Markierter Betrag wie `23 €`, `62,700 円`
   oder `USD 1,100` → Klick auf das Währungssymbol → zweite Reihe mit 3–5
   Lieblingswährungen → Umrechnung wird **angehängt**: `23 € (≈ 26,19 $)`.
2. **Passwortgenerator.** Menüleiste und Hotkey-Popup: „Passwort erzeugen“ setzt
   ein 12-stelliges Passwort **am Cursor** ein.

Entscheidungen von Michael (2026-09-28): anhängen statt ersetzen · Favoriten in
der Leiste · Passwort am Cursor · jede Zeichenklasse mindestens einmal, ohne
verwechselbare Zeichen.

## 1. Währungsrechner

### Datenfluss und Vertrauensgrenzen

```
[Markierter Text] → Parser (lokal) ┆
[Kurs-Cache, Application Support] ← ┆ HTTPS GET, feste URL → [open.er-api.com]
                → Umrechnung (lokal) → Ersetzen-Leiter → [Ziel-App]
```

Eine Grenze nach außen: Tippi ↔ open.er-api.com (ExchangeRate-API, Open Access,
kein Schlüssel). Gemessen 2026-09-28: 166 Währungen inkl. CRC, 3 KB, tägliche
Aktualisierung, `time_next_update_unix` in der Antwort.

### Entscheidungen

| Frage | Entscheidung | Warum |
|---|---|---|
| Was verlässt den Mac? | **Nichts vom Text.** Die URL ist eine Konstante mit fester Basis EUR (`/v6/latest/EUR`); weder Betrag noch Währung werden gesendet. | Die Auswahl kann alles enthalten. Die Anfrage verrät nur „diese IP nutzt Tippi-Umrechnung“. |
| SSRF? | Ausgeschlossen: keine nutzergesteuerte URL. Antwort-Host wird nach dem Abruf geprüft (`response.url?.host == "open.er-api.com"`), sonst verworfen. | Feste Konstante + Host-Prüfung fängt eine Weiterleitung ab. |
| Transport | HTTPS mit ATS-Standard, `timeoutInterval = 10`, `ephemeral`-Session (keine Cookies/Cache auf Platte). | |
| Antwort-Parser | `JSONDecoder` in ein Codable mit genau den benötigten Feldern. Grenzen: Antwort ≤ 256 KB, `result == "success"`, `base_code == "EUR"`, Codes `^[A-Z]{3}$`, Kurse endlich und > 0. Sonst verworfen. | Fremde Bytes; Größen- und Formgrenzen vor Nutzung. |
| Abrufhäufigkeit | Cache in `Application Support/Tippi/exchange-rates.json`. Neu abrufen erst ab `time_next_update` **und** frühestens 1 h nach dem letzten Versuch. HTTP 429 → 20 min Pause. | Anbieter: 1×/Tag reicht, 429 sperrt 20 min. Klick-Spam darf keine Anfragen auslösen. |
| Anbieter nicht erreichbar | Cache bis 7 Tage alt weiter nutzen; älter → Hinweis „Kein aktueller Kurs“, nichts wird geschrieben. | Ein alter Kurs mit `≈` ist brauchbar, ein uralter irreführend. |
| Eingabe-Parser | Auswahl getrimmt ≤ 40 Zeichen, sonst kein Betrag. Verankerter regulärer Ausdruck auf dieser kurzen Zeichenkette. Symbole/Codes gegen eine feste Liste. Mehrdeutig: `$` = USD, `¥` = JPY, `元` = CNY, `kr` wird nicht erkannt. | Kurze, begrenzte Eingabe → kein ReDoS. Nur bekannte Codes. |
| Zahlenformat | Ein Trennzeichen mit genau 3 Ziffern dahinter = Tausender (`1,100`, `1.100`, `62,700`); sonst Dezimal (`1,5`, `9.99`). Zwei verschiedene Trenner: der letzte ist dezimal. | Abgedeckt durch Tests. |
| Quellenhinweis | „Kurse: Exchange Rate API“ mit Link in den Einstellungen neben den Favoriten und in der Hilfe. | Pflicht laut Anbieter. |

### STRIDE

- **Spoofing/Tampering:** Wer die Antwort fälscht (kompromittierter Anbieter,
  TLS-Bruch), erzeugt eine falsche Zahl in Klammern. Kein Code, kein Pfad, keine
  Ausführung. **Restrisiko akzeptiert:** sichtbar, mit `≈` markiert, rückgängig
  mit ⌘Z.
- **Information disclosure:** siehe oben — nur IP und Zeitpunkt. README-Abschnitt
  „Privacy“ wird ergänzt: Tippi spricht außer dem gewählten KI-Anbieter jetzt
  auch open.er-api.com an, **nur** beim Umrechnen und ohne Textinhalt.
- **DoS:** Zeitlimit 10 s, Größenlimit, Abrufsperre. Die Leiste blockiert nicht,
  die Umrechnung läuft asynchron.
- **Elevation:** keine Rechte beteiligt.

**Missbrauchs-Zwilling:** „Nutzer rechnet um“ → „Nutzer klickt 50× schnell“ →
höchstens ein Abruf pro Stunde, danach Cache.

## 2. Passwortgenerator

### Klassifikation

Das erzeugte Passwort ist eine **Zugangsinformation**. Nur im RAM, nie loggen,
nie in den Verlauf, nie in eine Einblendung (die Einblendung sagt nur
„Passwort eingefügt“).

### Entscheidungen

| Frage | Entscheidung | Warum |
|---|---|---|
| Zufall | `SystemRandomNumberGenerator` — auf Apple-Plattformen kryptografisch sicher (`arc4random_buf`); `random(in:)` ist gleichverteilt, kein Modulo-Bias. | Kein eigener Zufall, kein `Int.random` mit Seed. |
| Zeichensatz | Groß ohne I/O, klein ohne l/o, Ziffern ohne 0/1, Sonderzeichen `/()=?&%$§"!-_:;` (Michaels Vorgabe). ≈ 72 Zeichen → 12 Stellen ≈ 74 Bit. | Reicht für jede Web-Anmeldung deutlich. |
| Klassen | Je ein Zeichen pro Klasse ziehen, Rest aus der Gesamtmenge, dann mischen (`shuffle(using:)` mit demselben Generator). | Erfüllt Website-Regeln, Position der Pflichtzeichen nicht vorhersagbar. |
| Einfügen | **Nur Einfügen** (`TextInsertion.insertSecret`): Zwischenablage mit `prepareForNewContents(with: .currentHostOnly)` + `org.nspasteboard.ConcealedType`, ⌘V, vorheriger Inhalt wird nach 400 ms wiederhergestellt. Geändert bei der Umsetzung: ursprünglich Bedienungshilfen zuerst. | Der Bedienungshilfen-Schreibversuch ist in Apps ohne lesbaren Inhalt „nicht prüfbar“; die Leiter fügt dann zusätzlich ein — ein **doppeltes Passwort** fiele niemandem auf. Passwortfelder verbergen ihren Inhalt ohnehin. **Handoff:** ohne `.currentHostOnly` würde macOS das Passwort per Universal Clipboard aufs iPhone spiegeln — dieselbe Lehre wie bei der OCR (2026-09-21). Concealed hält Verlaufs-Werkzeuge fern. Ist die Ziel-App beim Einfügen nicht mehr vorn, bleibt das Passwort (host-only, concealed) zur Wiederherstellung in der Zwischenablage. |

**Nachgetragen 2026-09-28 (Michaels Test):** Das Passwort bleibt nach dem
Einfügen **60 Sekunden** in der Zwischenablage — Formulare mit „Passwort
wiederholen“ brauchen ein zweites ⌘V. Danach stellt `PasteboardSnapshot.restore`
die vorherige Zwischenablage her; hat inzwischen jemand anderes kopiert, bleibt
dessen Inhalt (Restore prüft den `changeCount`). Restrisiko akzeptiert: 60 s lang
kann jede App auf diesem Mac die Zwischenablage lesen — Handoff und
Verlaufs-Werkzeuge bleiben ausgeschlossen.

**Restrisiken akzeptiert:** `§` ist kein ASCII — einzelne Websites lehnen es ab
(Michaels ausdrückliche Vorgabe, ein zweiter Klick liefert ein neues Passwort).
Die Ziel-App selbst sieht das Passwort natürlich; das ist der Zweck.

**Missbrauchs-Zwilling:** „Passwort in Formular einfügen“ → „Fokus liegt
inzwischen in einem Chatfenster“ → das Passwort landet dort. Gegenmittel wie bei
allen Einfüge-Wegen: Einfügen nur in die App, die beim Auslösen vorn war
(`expectedPID`-Prüfung der bestehenden Leiter). Aus der Menüleiste: Ist Tippi
selbst vorn (Einstellungen offen), wird nichts eingefügt.

**Offen, nur am echten System messbar:** ob ein synthetisches ⌘V in ein Feld mit
aktivem „Secure Event Input“ (Passwortfeld) ankommt.
