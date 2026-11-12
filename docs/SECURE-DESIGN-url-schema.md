# Secure Design — URL-Schema `tippi://schnellnotiz`

Stand: 2026-11-12 · Status: **entschieden vor dem Code**.
Durchlauf nach `rafter-secure-design`: `ingestion` + `threat-modeling`. Anlass: Porter (`~/Coding/Porter`) bekommt
einen Knopf, der Tippis Schnellnotizen öffnet, per `NSWorkspace.shared.open(URL(string: "tippi://schnellnotiz")!)`.
Eigene Datei statt `docs/SECURE-DESIGN.md`, weil Tippi je Funktion eine `SECURE-DESIGN-*.md` führt.

## U1 – Was gebaut wird

`CFBundleURLTypes` mit dem Schema `tippi` in `Tippi/Resources/Info.plist`. Der AppDelegate nimmt URLs über
`application(_:open:)` an und gibt sie an `TippiURLCommand.parse(_:)`. Genau **eine** Aktion ist erlaubt:
das Schnellnotiz-Panel unter dem Menüleisten-Symbol öffnen, so wie ein Linksklick aufs Symbol. Ist keine
Schnellnotiz markiert, öffnet sich das Notizfenster (nicht das Menü, siehe U5).

## U2 – Vertrauensgrenze

Jede App und jede Webseite kann `tippi://…` aufrufen. Die URL ist also **nicht vertrauenswürdig**, ohne Ausnahme.
Wer sie schickt, erfährt Tippi nicht verlässlich und braucht es auch nicht: die Aktion ist für jeden Absender gleich
harmlos.

| Entscheidung | Warum |
|---|---|
| **Allowlist statt Parser:** angenommen wird nur Schema `tippi` + Host `schnellnotiz` (Groß/Klein egal), Pfad leer oder `/` | Kein Raum für „versteckte“ Zusatzfunktionen |
| **Alles andere wird abgelehnt:** Query, Fragment, Benutzer, Passwort, Port, weiterer Pfad, anderer Host | „Keine Parameter auswerten“ heißt: gar nicht erst annehmen. Später ein Parameter = neue Design-Runde |
| Kein Text wird eingefügt, nichts gespeichert, nichts ausgeführt, kein Netz, keine Datei | Die URL trägt keine Daten in Tippi hinein |
| Abgelehnte URLs werden protokolliert **ohne Inhalt** (nur „abgelehnt“ + ob das Schema stimmte) | URLs können Text enthalten, den jemand nicht im Systemprotokoll haben will |
| Mehrere URLs in einem Aufruf: höchstens eine Aktion | Kein Mehrfach-Auslösen |

## U3 – STRIDE

- **S (Spoofing):** Absender nicht prüfbar. Bewusst hingenommen, weil die Aktion für jeden Absender dasselbe tut.
- **T (Tampering):** Die URL ändert keine Daten. Notizen werden erst geändert, wenn der Mensch im Panel tippt.
- **R (Repudiation):** entfällt, keine wertvolle Aktion.
- **I (Information disclosure):** Das Panel zeigt Notizen nur auf dem eigenen Bildschirm; der Aufrufer bekommt
  keine Antwort, keinen Rückkanal, keinen Inhalt. Protokoll ohne URL-Inhalt (U2).
- **D (Denial of service):** Eine Seite/App könnte das Schema in Schleife rufen. Ist das Panel offen, ist ein
  weiterer Aufruf wirkungslos (öffnen, nicht umschalten), es flackert also nicht auf und zu. Browser fragen vor
  fremden Schemata ohnehin nach („Tippi öffnen?“).
- **E (Elevation of privilege):** Keine Funktion hinter dem Schema außer „Panel zeigen“. Keine Diktat-, KI-,
  Einfüge- oder Einstellungsaktion erreichbar.

## U4 – Missbrauchsfall: Fokus klauen

„Ein Programm öffnet das Panel, während ich anderswo tippe, und meine Tasten landen in einer Schnellnotiz.“
Der Fall ist echt, aber klein: Die Tasten landen in Michaels **eigener** Notiz, nicht beim Angreifer, und ein
Programm, das schon auf dem Mac läuft, könnte Schlimmeres. Webseiten müssen erst durch die Browser-Nachfrage.
Restrisiko hingenommen; das Panel schließt bei Esc und bei jedem Klick in eine andere App.

## U5 – Kaltstart

Läuft Tippi nicht, startet macOS es über das Schema. Kommt die URL vor dem Aufbau des Menüleisten-Symbols an,
merkt sich Tippi nur „Panel offen wünschen“ (ein Bool, kein URL-Inhalt) und öffnet es, sobald das Symbol steht.

Gemessen 2026-11-12 am Developer-ID-Testbuild: Auch dann sind die Notizen noch nicht geladen (`NotesStore.refresh`
läuft im Hintergrund), die Liste ist leer, und „keine Schnellnotiz markiert“ wäre falsch. Deshalb wartet der
URL-Weg bei leerer Liste bis zu 3 s darauf, weitere Aufrufe in der Zeit werden verworfen. Der erste Entwurf
öffnete als Rückfall das Menü per `performClick`. Beim Kaltstart lag es außerhalb des Bildschirms
(Fensterliste: y = −74) und hielt den Hauptfaden fest, selbst „Beenden“ lief in eine Zeitüberschreitung (−1712).
Deshalb öffnet der Rückfall jetzt das Notizfenster.

## U6 – Testkopien und Schema-Besitz

Jede Tippi-Fassung mit dieser Info.plist meldet `tippi` bei LaunchServices an (Release, `make build`,
`Tippi Bild`). **Auch `make test`:** Gemessen 2026-11-12 stand danach
`~/Library/Developer/Xcode/DerivedData/Tippi-*/Build/Products/Debug/Tippi.app` (echte Kennung `com.tippi.app`,
Debug) als einziger Besitzer von `tippi:` in LaunchServices. Ein `tippi://`-Aufruf hätte diese Fassung gestartet,
neben dem installierten Release ohne Schema. Nach dem Release mit Schema gewinnt meist die neuere Version in
`/Applications`. Prüfen:
`lsregister -dump | grep -B40 "bindings:.*tippi:" | grep "^path:"`. Nach einem Sichttest die Testkopie mit `lsregister -u` abmelden, sonst startet Porters Knopf
später womöglich eine gelöschte oder alte Kopie.

## Abgelehnt

- **`NSAppleEventManager` mit `kAEGetURL` selbst registrieren:** SwiftUI installiert einen eigenen Handler und
  leitet an `application(_:open:)` weiter; ein eigener Handler könnte das still überschreiben oder überschrieben
  werden. Der Delegat-Weg ist der von Apple vorgesehene.
- **`onOpenURL` in SwiftUI:** Tippi hat keine Fenster-Szene, an der es hängen könnte (nur eine leere `Settings`).
- **Parameter wie `?text=` oder `tippi://notiz/<id>`:** jetzt nicht gebraucht, jeder Parameter wäre neue Angriffsfläche.
