# Sprachnotiz (⌃⌥⌘N) – Sicherheitsentwurf

Stand 2026-11-14, Branch `feat/sprachnotiz`. Wunsch Michael (aus Mado/Kenzo Weiss): schnelle Notiz per Sprache,
schwebend über allem, mit Transparenz-Regler. Entscheidungen 14.11.: Kürzel öffnet das Schnellnotiz-Panel und
startet sofort das Diktat; Text mit Zeitstempel an eine feste Notiz „Eingang“; vorhandenes Panel erweitern.

## Was gebaut ist

- `DictationSource.inbox`. Abzweigung in `transcribeAndInsert` direkt nach Glättung und Korrekturen: kein Einfügen
  am Cursor, kein Return, keine Feldanpassung, kein Brief-Layout (`DictationLayout.layoutWanted`).
- `InboxNote` (`Tippi/Core/Notes/InboxNote.swift`): sucht „Eingang“ per Titel (ältester Treffer), legt sie bei Bedarf
  an, hängt `Zeitstempel – Text` an. Liest den Inhalt erst beim Anhängen frisch.
- `AppDelegate.handleVoiceNoteHotkey`: leer → Panel schwebend + Aufnahme; Aufnahme `.inbox` → Panel zu, dann
  stoppen; Transkription oder fremdes Diktat → ignorieren.
- Panel-Schwebe-Modus (`QuickNotesPopoverController.openFloating`): schließt nicht bei Klick daneben oder Fokusverlust,
  verschiebbar, ohne Menüleisten-Symbol oben mittig. Deckkraft-Regler in der Fußleiste (`NotesSettings.quickNotesOpacity`).

## Antworten (`rafter-secure-design`: Data Storage, Ingestion, Threat Model)

**Klassifikation.** Diktierter Text = Nutzerinhalt, gleiche Klasse wie jede Notiz (kann Persönliches enthalten).

**Speicher.** Keine neue Ablage: dieselbe `.txt`-Datei je Notiz im iCloud-Container wie alle Notizen (`NotesStore`).
Keine Verschlüsselung zusätzlich – gleiche Entscheidung wie für Notizen insgesamt. Einstellungen (Kürzel, Schalter,
Deckkraft) in `UserDefaults` über `NotesSettings.store` (injizierbar, Tests nie `.standard`).

**Kein stiller Verlust (entschieden).**
- Notizen noch nicht geladen (`NotesStore.hasLoaded`, neu) nach 5 s → nichts anlegen (sonst zweite „Eingang“),
  Text in die Zwischenablage, Hinweis.
- „Eingang“ gerade im Editor offen (`noteBeingEdited`) → nicht anhängen (der Editor würde mit seinem `@State`
  überschreiben), Text in die Zwischenablage, Hinweis.
- Panel wird beim zweiten Druck **vor** der Transkription geschlossen; `onDisappear` speichert den Editor synchron in
  die Liste (`save` ist synchron), das Anhängen kommt danach. Test `testEditorSaveBeforeAppendKeepsBoth`.

**Code-Audit 14.11.** Leerer Text (Whisper wirft bei Stille nicht) hängte einen leeren Eintrag an → jetzt
`.nothingToAdd`, Test `testBlankTextAddsNothing`. **Restrisiko (hingenommen):** „Eingang“ zugleich im Notizfenster
und im Panel offen – nach dem Schließen des Panels ist `noteBeingEdited` leer, obwohl das Notizfenster sie noch zeigt.
Tippt Michael genau dann dort und diktiert zugleich, kann dessen Autosave das Angehängte überschreiben
(`noteBeingEdited` kennt nur einen Editor).

**Zwei Macs.** Suche per Titel statt lokal gemerkter ID: Mac mini und MacBook finden dieselbe Notiz. Bei mehreren
gleichnamigen gewinnt die älteste. **Restrisiko (hingenommen):** Beide Macs legen sie gleichzeitig zum ersten Mal an,
bevor iCloud abgeglichen hat → zwei „Eingang“; danach schreibt jeder Mac in die ältere.

**Zwischenablage im Rückfall.** Normales `setString`, nicht vertraulich markiert: Es ist Michaels eigener Text, den er
gleich einfügen will. Zwischenablage-Verläufe nehmen ihn auf – gewollt, so geht er nicht verloren.

**Protokoll.** Nur Länge und Ausgang (`dictation to inbox 42 chars … appended(created: false)`), nie Text.

**Kürzel.** Carbon `RegisterEventHotKey` wie alle Tippi-Kürzel (ID 9), keine neue Berechtigung. Gleiche Voraussetzung
wie das Diktat (eingeschaltet, Modell bereit), neu gestartet aus `restartDictationHotkey`. ⌃⌥⌘N in
`MailDictationSettings.takenCombos()` für die Konfliktprüfung; in Michaels anderen Apps nicht belegt (`grep`, 14.11.).

**Deckkraft.** Begrenzt auf 0,35–1,0 (bei 0 unsichtbar und nicht bedienbar), nur endliche Zahlen, Unsinn per
`defaults write` → 1,0.

**Netz, Prozesse, Berechtigungen.** Keine neuen. Glättung läuft wie beim normalen Diktat über den eingestellten
Anbieter (lokal oder Cloud, wie bisher).

**STRIDE.** *S* nicht berührt (eigenes Kürzel, keine Fremdeingabe). *T* Diktat-Text wird als reiner Text gespeichert,
nichts ausgeführt. *R* nicht berührt. *I* Schwebendes Panel zeigt Notizen über einem Vollbild – nur auf Michaels
Kürzel; `sharingType` unverändert wie das bestehende Panel. *D* nicht berührt. *E* nicht berührt.

## Nicht gemessen bis zum Sichttest

Verschieben am Hintergrund (`isMovableByWindowBackground`) bei SwiftUI-Inhalt, Schweben über Vollbild-Video,
Kürzel am echten System, Mikrofon.
