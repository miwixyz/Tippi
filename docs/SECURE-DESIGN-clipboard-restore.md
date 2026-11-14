# Secure Design — Zurückgeschriebene Zwischenablage als „vorübergehend“ markieren

Stand: 2026-11-14 · Status: **entschieden vor dem Code**.
Durchlauf nach `rafter-secure-design`: `data-storage` (Fremdspeicher in anderen Apps) + `threat-modeling`.
Anlass: Messung an Gnotchi 0.26.1 (echter `ClipboardLink.tick()`, benannte Zwischenablage, Tippis Ablauf
nachgebaut). Nach jedem Diktat, Einfügen und Lesen der Markierung schreibt Tippi die alte Zwischenablage zurück.
Zwischenablage-Verläufe (Gnotchi, Maccy, Paste …) sehen eine neue Änderung und nehmen den alten Inhalt erneut auf.
Gemessen: gelöschte Einträge kommen zurück, Kopien aus ausgeschlossenen Apps und aus der Pause landen im Verlauf,
unabhängig davon, ob Diktat und Rückschreiben in denselben Abfragetakt fallen. Gleiche Meldung bei Hikidashi
(Issue #1, `Kenvoice/hikidashi`).

## R1 – Was gebaut wird

`PasteboardSnapshot.restore(to:)` setzt an jedem zurückgeschriebenen Element zusätzlich
`org.nspasteboard.TransientType` (leere Daten). Das ist die Markierung von nspasteboard.org für „nicht in einen
Verlauf aufnehmen“. Gnotchi lässt sie bereits aus (`ClipboardRules.swift`, `neverTypes`, gemessen), Maccy laut
Quellcode ebenso (`Maccy/Clipboard.swift:27–30`, nicht am Gerät gemessen). Paste ist Closed Source: vermutlich.
Wirkt an allen Stellen, die `restore()` rufen (Einfügen, Diktat, Geheimnis-Einfügen, Lesen der Markierung per ⌘C/AXCopy).

## R2 – Vertrauensgrenze

Tippi → `NSPasteboard.general`, das jede App auf dem Mac lesen kann. Was Tippi dort hinterlässt, landet in
fremden, dauerhaften Speichern (Verläufe), außerhalb von Tippis Kontrolle.

| Entscheidung | Warum |
|---|---|
| Markierung an **jedem** Element, nicht nur am ersten | Verlaufs-Apps prüfen teils nur die Typen des ersten Elements, teils alle |
| Inhalt bleibt unverändert, nur ein Typ kommt dazu | Einfügen in Ziel-Apps unverändert; unbekannte Typen werden ignoriert |
| War die Zwischenablage vorher leer → nichts schreiben (wie bisher) | Kein leeres Element nur für die Markierung |
| Vorhandene Markierungen (z. B. ConcealedType von 1Password) bleiben erhalten | Kommen aus dem Schnappschuss mit |
| Keine Erkennung „war der Inhalt schon im Verlauf?“ | Tippi kennt fremde Verläufe nicht; der Inhalt ist nie neu, also ist „nicht aufnehmen“ immer richtig |

## R3 – STRIDE

- **S/R/E:** entfällt. Keine Identität, keine Rechte, kein Protokoll mit Inhalt.
- **T:** Ziel-Apps sehen einen zusätzlichen Typ. Bekannt, harmlos: Typen ohne Abnehmer ignoriert macOS.
- **I (Kern):** Vorher gab Tippi Inhalte an Verläufe weiter, die der Nutzer dort ausgeschlossen, pausiert oder
  gelöscht hatte. Danach nicht mehr. Restrisiko: Verläufe, die TransientType nicht kennen, verhalten sich wie vorher.
- **D:** entfällt.
- **Bewusst hingenommen (gemessen 14.11., Fall E):** Kopiert der Nutzer X und löst Tippi innerhalb desselben
  Abfragetakts des Verlaufs aus (Gnotchi 0,5 s), sieht der Verlauf X nie unmarkiert, X fehlt dort. Vorher kam X
  hinein. Beim Diktat praktisch ausgeschlossen (man spricht Sekunden), bei Kürzel-Aktionen auf einer Markierung nur,
  wenn zwischen Kopieren und Kürzel unter einer halben Sekunde liegt. Kein Datenverlust: X liegt weiter in der
  Zwischenablage. Ein erneutes Kopieren nimmt es auf.

## R4 – Bewusst nicht

- **Wächter in Gnotchi** (Rückschreiben selbst erkennen): müsste Inhalte aus ausgeschlossenen Apps lesen und
  hashen, Konflikt mit Gnotchi G37 („Ausschluss vor dem Lesen“). Entschieden 2026-11-14 (Michael): Fix in Tippi.
- **Tippis eigene ⌘C-Kopie der Markierung** (Text lesen): diese Zwischenstufe ist nicht markiert und kann in
  einem Verlauf landen, wenn ein Abfragetakt in die ~80 ms fällt. Eigener Punkt, nicht Teil dieses Fixes.

## R5 – Prüfung

Unit-Test: Zurückgeschriebene Elemente tragen TransientType, der Inhalt ist unverändert, auch bei mehreren
Elementen. Gegenprobe gegen Gnotchis Regeln (`ClipboardCapture.decide` → `.skip(.confidential)`).
