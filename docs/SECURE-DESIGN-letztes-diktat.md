# Letztes Diktat erneut einfügen (⌃⌥⌘V) – Sicherheitsentwurf

Stand 2026-11-23. Wunsch Michael (Idee aus EnviousWispr „Paste Last Dictation“): Ist ein Diktat am falschen Ort
gelandet oder war kein Textfeld fokussiert, soll ein Kürzel denselben Text noch einmal an den Cursor schreiben.
Entscheidungen: ab Werk an, Kürzel ⌃⌥⌘V, Text nur im Arbeitsspeicher.

## Was gebaut ist

- `LastDictation` (`Tippi/Core/LastDictation.swift`): ein Eintrag, nur im Arbeitsspeicher. Ein neues Diktat ersetzt
  das alte. Nach 30 Minuten ist er weg (`recall()` löscht ihn dann auch), beim Beenden von Tippi sowieso.
- `DictationController.transcribeAndInsert`: nach dem Einfügen `LastDictation.shared.rememberDictation(…)`.
  Behalten wird der Text, der eingefügt wurde (`correction?.text ?? final`), nicht die Rohfassung.
- `AppDelegate.handleLastDictationHotkey`: holt den Text, schreibt ihn über `TextInsertion.insertViaClipboard` in
  die vorderste App. Wiederholbar (zweiter Druck fügt noch einmal ein).
- `LastDictationSettings`: Schalter (an) und Kürzel. Ausschalten löscht den gemerkten Text.

## Antworten (`rafter-secure-design`: Data Storage, Ingestion, Threat Model)

**Klassifikation.** Diktierter Text = Nutzerinhalt, kann Persönliches oder Vertrauliches enthalten.

**Speicherort und Dauer.** Nur Arbeitsspeicher des Tippi-Prozesses. Nicht auf die Platte, nicht in die Einstellungen,
nicht ins Protokoll (das Diktat-Protokoll nennt weiter nur Längen). Höchstens 30 Minuten, höchstens 100 000 Zeichen
(längere Texte werden nicht gemerkt, und der alte Eintrag fällt dabei weg, damit kein älteres Diktat zurückkommt).

**Was nie gemerkt wird.**
- Sprachnotiz-Diktat (`.inbox`): der Text liegt schon in der Notiz.
- „Antwort per Sprache“ (`.reply`): dort ist das Diktat nur die Absicht.
- Alles, während `IsSecureEventInputEnabled()` an ist (Passwortfeld im Fokus).

**Was nie geschieht.**
- Einfügen in ein Passwortfeld: der Hotkey prüft `IsSecureEventInputEnabled()` und meldet „Nicht in ein Passwortfeld“.
- Mehrzeiliger Text in einem Terminal: in Befehls-Apps (`DictationSettings.commandCapableBundleIDs`) geht der Text
  wie beim Diktat einzeilig hinein (`DictationController.singleLine`), damit ein Zeilenumbruch nichts ausführt.
- Return: das Einfügen drückt nie Return.
- Zwischenablage: `TextInsertion.insertViaClipboard` sichert und stellt sie wieder her, markiert den Inhalt als
  vertraulich (nspasteboard.org), so wie jedes Einfügen aus Tippi.

**Bedrohungen.**
| Bedrohung | Maßnahme |
|---|---|
| Fremdes Programm liest den Speicher | Gleiche Klasse wie alles, was Tippi im Speicher hält (Diktat, Zwischenablage-Rückgabe); keine neue Fläche außer der Dauer von 30 Minuten |
| Text bleibt lange liegen | 30 Minuten, beim Ausschalten und Beenden weg |
| Text landet in der falschen App | Es zählt die vorderste App beim Druck; die Prüfung `isExpectedFrontmost` in `paste` verhindert ⌘V in eine andere App, dann liegt der Text in der Zwischenablage (mit Meldung) |
| Hotkey kollidiert mit einem anderen Tippi-Kürzel | `MailDictationSettings.takenCombos` kennt ⌃⌥⌘V; Test `testDefaultComboCollidesWithNoOtherTippiHotkey` |

**Nicht geprüft (2026-11-23).** Ob ⌃⌥⌘V in Michaels anderen Apps belegt ist; das Einfügen in eine echte Fremd-App
(braucht Bedienungshilfen-Freigabe, Developer-ID-Testbuild `scripts/devid-testbuild.sh`).
