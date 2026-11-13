# Secure Design — Datei-Aufgaben aus Porters Notizliste

Stand: 2026-11-13 · Status: **gebaut, vor dem Release**.
Gestaltung entschieden in Porters `/grill-me` vom 12.11. (Vault: `02 Projekte/Porter.md`, Block „Notizen an
Dateien/Ordnern entschieden“). Ort in Tippi: eigener Abschnitt in der Seitenleiste des Notizfensters (Michael, 13.11.).

## D1 – Was gebaut wird

Tippi zeigt die offenen Aufgaben (`isTask && !isDone && !deleted`) aus Porters Liste
`~/Library/Mobile Documents/com~apple~CloudDocs/Porter/Notizen.json`. Ein Klick öffnet die Datei in Porter
(`NSWorkspace.open([url], withApplicationAt: Porter.app)`); ohne Porter wird sie im Finder gezeigt.
Code: `Tippi/Core/Notes/PorterFileTasks.swift`, `Tippi/UI/Notes/FileTasksSection.swift`.
**Kein** neues `tippi://`-Kommando.

## D2 – Vertrauensgrenze

Die Liste kommt über iCloud Drive und wird von Porter auf beiden Macs geschrieben. Für Tippi ist sie **nicht
vertrauenswürdige Eingabe**: Jedes Programm des Nutzers kann die Datei schreiben, iCloud kann einen halben oder
fremden Stand liefern.

| Entscheidung | Warum |
|---|---|
| **Nur lesen.** Kein Schreiben, kein Anlegen des Ordners, kein Auflösen von iCloud-Konflikten | Porter ist der einzige Schreiber; zwei Schreiber hieße zwei Zusammenführungsregeln. Test `testLoadNeverWrites` |
| Einzige Nebenwirkung: `startDownloadingUbiquitousItem`, wenn die Liste nur als Platzhalter vorliegt | Ändert den Inhalt nicht, holt nur Porters Stand aufs Gerät |
| Koordiniertes Lesen (`NSFileCoordinator`), abseits des Hauptthreads | Kein halb geschriebener Stand, kein Hänger, wenn iCloud wartet |
| Größenlimit 5 MB, nur reguläre Datei | Porters Liste hat wenige KB; alles darüber gilt als nicht lesbar |
| Kaputte, zu große oder nicht dekodierbare Liste → ruhige Zeile „nicht lesbar“, keine Meldung, kein Teilergebnis | Porter ist zuständig; Tippi rät nichts |
| Schlüssel nur `~`, `~/…` oder absolut; alles andere (relativ, `file://`, `https://`, `~andere`, NUL) wird übergangen | Nur Porters Format, keine Adressen mit Schema |
| Klick öffnet **nie** mit dem Standardprogramm der Datei, sondern nur mit Porter oder im Finder (zeigen, nicht starten) | Ein Eintrag könnte auf ein Programm oder Skript zeigen. Porter navigiert nur dorthin; der Finder markiert nur |
| Porter: zuerst ein **laufendes** Porter (Kennung `dev.mwlr.porter`), sonst `/Applications` bzw. `~/Applications` mit geprüfter Kennung, zuletzt LaunchServices | Sonst startet ein zweites Porter, wenn eines aus einem anderen Ordner läuft (gemessen 13.11.). Eine fremde App, die sich als `dev.mwlr.porter` ausgibt, müsste schon laufen, also bereits Code auf dem Mac ausführen; sie bekommt nur einen Pfad |
| Bereich nur sichtbar, wenn Porter installiert ist oder der Ordner `iCloud Drive/Porter` existiert | Wer Porter nicht nutzt, sieht nichts davon |
| Kein Protokoll von Pfaden oder Notiztexten | Notizen können Persönliches enthalten |

## D3 – STRIDE

- **S:** Wer die Datei schreibt, ist nicht prüfbar. Hingenommen: Schlimmstenfalls zeigt Tippi falsche Zeilen,
  ein Klick zeigt eine Datei in Porter oder im Finder an, ausgeführt wird nichts.
- **T:** Tippi verändert die Liste nie (D2).
- **R:** entfällt, keine Aktion mit Folgen.
- **I:** Inhalte erscheinen nur im eigenen Notizfenster. Kein Netz, kein Protokoll, keine Weitergabe.
- **D:** Riesige oder kaputte Datei → Größenlimit und Zustand „nicht lesbar“, Lesen läuft nicht auf dem Hauptthread.
- **E:** Kein Weg von einem Eintrag zu einer Ausführung (D2, Öffnen nur mit Porter/Finder).

## D4 – Offen

- iCloud-Abgleich der Liste zwischen den Macs ist noch nicht gemessen (Porter-Projekt). Tippi zeigt, was auf
  diesem Mac angekommen ist, und liest beim Öffnen des Fensters und beim Zurückkehren zu Tippi neu.
