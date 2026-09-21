# Secure Design — Bildschirm-OCR („Text aus Bildschirmausschnitt")

Stand: 2026-09-21 · Status: **Entwurf, vor der Implementierung**
Durchlauf nach `rafter-secure-design`: `data-storage` + `threat-modeling`.

## Was gebaut werden soll

Globaler Hotkey → Auswahlrechteck über dem Bildschirm → der markierte Bereich
wird per **ScreenCaptureKit** erfasst, lokal per **Vision** (`VNRecognizeTextRequest`)
in Text gewandelt, Ergebnis in die Zwischenablage. Kein Netzwerk, keine Cloud.

## 1. Klassifikation — was ist diese Datei eigentlich?

Das ist die Frage, an der die ganze Gestaltung hängt.

> **Ein Bildschirmausschnitt hat keine feste Datenklasse — er hat die höchste,
> die gerade auf dem Schirm steht.**

Im Rechteck kann alles liegen: ein sichtbares Passwort, ein API-Schlüssel in
einem Terminal, eine Patientenzeile aus Catis Dienstplan, eine Kundenmail, ein
Kontoauszug. Die App kann das **nicht unterscheiden** und darf es nicht versuchen.

**Folgerung:** Bild *und* erkannter Text werden wie eine **Zugangsinformation**
behandelt, nicht wie Nutzerinhalt. Nicht loggen, nicht zwischenspeichern, nicht
auf die Platte, kürzest mögliche Lebensdauer.

| Artefakt | Klasse | Wo | Lebensdauer |
|---|---|---|---|
| Erfasster Bildpuffer | wie Credential | **nur RAM** | bis OCR fertig, danach sofort freigeben |
| Erkannter Text | wie Credential | RAM → Zwischenablage | bis der Nutzer etwas anderes kopiert |
| Auswahlrechteck (Koordinaten) | unkritisch | RAM | Sitzung |
| Einstellungen (Hotkey, Sprache) | unkritisch | UserDefaults | dauerhaft |

**Keine Datei. Kein Cache. Kein Verlauf.** Ein Verlauf zuletzt erkannter Texte
wäre bequem — und eine dauerhafte Sammlung von allem, was jemals abfotografiert
wurde. Ausdrücklich **nicht** gebaut.

## 2. STRIDE auf die konkrete Gestalt

Datenfluss und Vertrauensgrenzen:

```
[Bildschirm aller Apps] ┆→ [ScreenCaptureKit] → [Bildpuffer RAM] → [Vision OCR]
                        ┆                                              ↓
                        ┆                                        [Text RAM]
                        ┆                                              ↓
                        ╎                                    [NSPasteboard] ┆→ [andere Apps]
                        ╎                                                   ┆→ [iCloud / iPhone]
   Grenze 1: fremde Apps → Tippi                    Grenze 2: Tippi → System/Netz
```

### I — Information Disclosure (die eigentliche Gefahr hier)

**I-1 — Die Zwischenablage ist eine Vertrauensgrenze, keine Ablage. 🔴**

Zwei Abflüsse, die man beim Wort „Zwischenablage" nicht mitdenkt:

1. **Universal Clipboard.** Bei aktiviertem Handoff synchronisiert macOS die
   Zwischenablage über iCloud auf iPhone und iPad. Ein per OCR erfasstes
   Passwort verlässt damit **das Gerät und das lokale Netz** — obwohl das
   Feature ausdrücklich „kein Netzwerk" verspricht.
2. **Verlaufs-Werkzeuge.** Raycast, Alfred, Paste und ähnliche lesen jede
   Änderung mit und legen sie **dauerhaft** ab. Was Tippi nach Sekunden
   vergisst, behält der Zwischenablage-Verlauf monatelang.

→ **Entschieden:** `NSPasteboard.general.prepareForNewContents(with: .currentHostOnly)`
vor dem Schreiben. Das unterdrückt Universal Clipboard (macOS 11+).
→ **Zur Entscheidung vorgelegt:** zusätzlich der Marker
`org.nspasteboard.ConcealedType`, mit dem Verlaufs-Werkzeuge den Inhalt
überspringen. Kostet Bequemlichkeit (der Text taucht im Verlauf nicht auf),
kauft Schutz. Siehe offene Punkte.

**I-2 — Logging. 🔴**

Der erkannte Text darf **nirgends** protokolliert werden: nicht als Erfolg
(„erkannt: …"), nicht als Fehler („konnte 'xyz' nicht deuten"), nicht in
Zeichenzahl-Statistiken mit Beispielen. Dasselbe gilt für Bildmaße plus Inhalt.

→ **Entschieden:** Geloggt werden ausschließlich Vorgang und Zustand —
„OCR gestartet", „OCR beendet, 142 Zeichen", „OCR fehlgeschlagen: <Fehlerkategorie>".
**Nie der Inhalt selbst.** Dafür in der Implementierung eine eigene Prüfung.

**I-3 — Der Bildpuffer im Speicher.**

Swift gibt Speicher nicht deterministisch frei; ein `CVPixelBuffer` kann nach
dem letzten Gebrauch noch im Adressraum liegen. Relevant wird das bei einem
Absturzbericht mit Speicherauszug.

→ **Entschieden:** Puffer unmittelbar nach dem OCR-Aufruf auf `nil` setzen,
Gültigkeitsbereich so eng wie möglich. Tippi sendet keine Absturzberichte an
Dritte — das bleibt so, und dieses Feature ist ein zusätzlicher Grund dafür.

### E — Elevation of Privilege

**E-1 — Die Berechtigung selbst ist der größte Posten. 🔴**

„Bildschirmaufnahme" ist eine **Dauervollmacht**: einmal erteilt, kann Tippi
jederzeit im Hintergrund den gesamten Bildschirm lesen — auch ohne Hotkey, auch
ohne sichtbares Fenster. Tippi hat bereits Bedienungshilfen-Zugriff; zusammen
ergibt das „sieht alles und kann überall schreiben".

→ **Entschieden:** Die Berechtigung wird **nicht beim Start** angefordert,
sondern erst beim ersten bewussten Auslösen der Funktion, mit einer Erklärung,
was sie umfasst. Wer die Funktion nie benutzt, erteilt sie nie.
→ **Entschieden:** Erfasst wird ausschließlich im Moment der Nutzerauslösung.
Kein Timer, kein Hintergrund-Erfassen, keine Vorschau „auf Verdacht".

**E-2 — Das Auswahl-Overlay.**

Ein transparentes Fenster über dem gesamten Bildschirm. Es darf nur das
entgegennehmen, was es braucht (Maus-Ziehen, ESC), und keine Tastatureingaben
an sich binden, die anderswo hingehören.

### D — Denial of Service

**D-1 — Hängendes Overlay. 🟠**

Stürzt Tippi während der Auswahl ab oder bleibt die Schleife stehen, liegt ein
unsichtbares Fenster über allem und der Rechner wirkt eingefroren. Für eine App
im Autostart ist das ein ernster Fehlerfall.

→ **Entschieden:** ESC bricht immer ab. Zusätzlich eine harte Obergrenze
(60 Sekunden ohne Auswahl → Overlay schließt sich von selbst). Aufräumen im
`defer`, nicht im Erfolgspfad.

**D-2 — Riesige Auswahl.** Ein Rechteck über vier Bildschirme bei 5K ergibt ein
sehr großes Bild; Vision braucht dann lange und viel Speicher.
→ **Entschieden:** Obergrenze für die Pixelfläche, darüber wird herunterskaliert
statt abgelehnt — OCR braucht Kantenschärfe, nicht Auflösungsrekorde.

### S — Spoofing / T — Tampering / R — Repudiation

Lokale Einzelnutzer-App ohne Netzwerk und ohne Mehrbenutzerbetrieb. Kein
sinnvoller Angriff über diese Grenzen, keine Nachweispflicht. **N/A, begründet.**

## 3. Was bewusst NICHT gebaut wird

- **Kein Verlauf** erkannter Texte — wäre eine dauerhafte Sammlung von allem
  jemals Erfassten.
- **Keine Datei auf der Platte**, auch nicht temporär. Deshalb ScreenCaptureKit
  statt `screencapture -i`: Letzteres schreibt eine PNG-Datei, die bei einem
  Absturz zwischen Aufnahme und Löschen liegen bleibt.
- **Keine Cloud-OCR.** Vision ist offline, erkennt Deutsch und Englisch gut
  genug und verlässt das Gerät nie.
- **Keine automatische Einfügung** in das vorderste Fenster. Zwischenablage
  reicht; automatisches Tippen in ein fremdes Fenster ist eine eigene
  Fehlerquelle und hier nicht verlangt.

## 4. Entschieden am 2026-09-21

1. **Verlaufs-Werkzeuge:** `org.nspasteboard.ConcealedType` als **Option,
   standardmäßig AUS**. Der Normalfall bleibt bequem; wer etwas Heikles erfasst,
   schaltet für den Moment ein. Eine Dauer-Verbergung hätte den Text auch aus
   der eigenen Raycast-Suche entfernt, wo er meist gesucht wird.
2. **Universal Clipboard: fest unterdrückt, kein Schalter.** Das Feature
   verspricht „bleibt auf dem Gerät" — eine Einstellung, die das aufhebt, macht
   die Zusage unzuverlässig. Wer Text aufs iPhone will, kopiert ihn danach
   normal weiter; dann ist es eine bewusste Handlung statt einer Voreinstellung.
3. **Sprachen: Deutsch + Englisch, fest.** Deckt den realen Alltag ab. Jede
   zusätzliche Sprache senkt die Trefferquote der anderen, weil Vision mehr
   raten muss — Spanisch käme erst dazu, wenn ein konkreter Fall auftritt.
