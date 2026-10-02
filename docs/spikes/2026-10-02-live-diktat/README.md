# Spike: Live-Diktat mit dem vorhandenen Parakeet TDT v3 (2026-10-02)

Frage aus dem Task „Tippi: Live-Transkription im Aufnahmefenster“: Geht Live-Text ohne
zusätzliches Streaming-Modell (Nemotron, ~1,1 GB)? Anlass: Abgleich mit [Handy](https://github.com/cjpais/Handy).

## Ergebnis (Mac mini M2 Pro, Stimme „Anna“, FluidAudio 0.15.2)

| Weg | erster Text | Takt | Wortfehler Endtext | Umspringen beim Loslassen |
|---|---|---|---|---|
| Tippi heute (Batch nach Loslassen) | – | – | 5,7 % / 12,3 % | – |
| `SlidingWindowAsrManager` `.streaming` (11-s-Fenster) | 13,8 s | 6–9 s | 7 % / 12 % | 16–48 % |
| … eigenes 2-s-Fenster | 2,7 s | 2 s | 29 % / 30 % | 26–30 % |
| … eigenes 1,5-s-Fenster | 2,1 s | 1,5 s | 193–280 % (Doppelungen) | 14–31 % |
| **Batch jede Sekunde über alles bisher Gesagte** | **1,2 s** | **1 s** | **5,7 % / 12,3 % / 9,1 % (110 s)** | **0 % / 8,8 % (nur Satzende) / 0 %** |

Rechenzeit „jede Sekunde neu“: Ø 0,20 s (29 s Audio), Ø 0,40 s / max 0,80 s (110 s Audio).

**Befunde:**
- `SlidingWindowAsrManager` taugt nicht: erkannt wird erst nach vollem Fenster + Nachlauf;
  `hypothesisChunkSeconds` ist in 0.15.2 deklariert, aber nirgends verwendet. `.default`
  (10 + 15 + 2 s Fenster) liefert gar keinen Text — vermutlich zu großes Fenster (nicht geprüft).
- **„Jede Sekunde neu erkennen“ trägt:** gleiche Qualität wie heute, kein zweites Modell,
  kaum Umspringen. Der Recorder-Umbau (Live-Puffer) bleibt nötig.

**Grenzen:** synthetische Stimme statt echtem Diktat · nur M2 Pro gemessen (MacBook Air
langsamer?) · Rechenzeit wächst mit der Länge (bei ~2 min max 0,8 s; darüber Takt strecken
oder nur das Ende neu erkennen) · Energiebedarf nicht gemessen · Whisper bleibt ohne Live-Text.

## Selbst laufen lassen

```bash
cd docs/spikes/2026-10-02-live-diktat
for n in 1 2; do say -v Anna -f audio/text$n.txt -o audio/t$n.aiff && afconvert -f WAVE -d LEI16@16000 -c 1 audio/t$n.aiff audio/t$n.wav; done
swift build -c release
./.build/release/Spike "$PWD/audio"       # Batch vs. SlidingWindow (Echtzeit, dauert ~3 min)
./.build/release/Spike "$PWD/audio" neu   # „jede Sekunde neu erkennen“
```
Lädt Parakeet TDT v3 aus dem FluidAudio-Cache (`~/Library/Application Support/FluidAudio/Models/`), den Tippi ohnehin anlegt.
