#!/usr/bin/env bash
# concurrency-lint.sh — flags `MainActor.assumeIsolated` that is not demonstrably
# on the main queue.
#
# Why (2026-09-20, shipped and crashed in 2.11.5):
#
#   Thread: com.apple.usernotifications.UNUserNotificationServiceConnection.call-out
#   _dispatch_assert_queue_fail → MainActor.assumeIsolated → ProblemNotifier.swift:109
#
# `assumeIsolated` does not check-and-adapt, it ASSERTS. A false assertion is a
# hard trap, not a warning. Inside a `NotificationCenter.addObserver(queue: .main)`
# block the assumption holds; inside the completion handler of a system API
# (UNUserNotificationCenter, URLSession, CLLocationManager, …) it does not.
#
# The crash only fired when the app had a problem to announce, so neither the
# test suite nor the release pipeline's launch check ever reached it — the app
# starts fine as long as nothing is wrong. A grep is the cheap thing that would
# have caught it; this is that grep.
#
# Heuristic on purpose: a hit is "prove it is on main", not "this is broken".
# Silence a justified one with `// concurrency-lint: on-main <reason>`.

set -uo pipefail
cd "$(dirname "$0")/.."

# Optionales Scan-Verzeichnis, damit der Lint gegen einen alten Stand aus
# Git geprueft werden kann — ein Lint, der nie gegen echten Fehlercode lief,
# ist eine Behauptung.
SCAN_DIR="${1:-Tippi}"

FINDINGS=0
while IFS=: read -r file line _; do
    [ -n "$file" ] || continue
    # Look at the 10 lines above: a `queue: .main` registration or an explicit
    # waiver is the only accepted evidence.
    start=$(( line > 10 ? line - 10 : 1 ))
    context=$(sed -n "${start},${line}p" "$file")
    if grep -q 'queue: *\.main\|concurrency-lint: on-main' <<<"$context"; then
        continue
    fi
    echo "  ❌ $file:$line — MainActor.assumeIsolated without evidence it runs on the main queue"
    echo "       Use \`Task { @MainActor in … }\`, or add \`// concurrency-lint: on-main <reason>\`."
    FINDINGS=$((FINDINGS + 1))
# awk statt `grep -v '^\s*//'`: der Filter muss auf den INHALT hinter
# `datei:zeile:` schauen. Die erste Fassung prüfte die ganze grep-Zeile, die mit
# dem Dateipfad beginnt — und meldete prompt den Kommentar, der vor genau diesem
# Fehler warnt. Selbst gefunden, beim ersten Lauf (2026-09-20).
done < <(grep -rn 'MainActor\.assumeIsolated' "$SCAN_DIR" --include='*.swift' \
         | awk -F: '{ rest = substr($0, index($0, $3)); sub(/^[ \t]+/, "", rest); if (rest !~ /^\/\//) print }')

echo "▶ Concurrency lint (MainActor.assumeIsolated)"
if [ "$FINDINGS" -eq 0 ]; then
    echo "  ✓ every assumeIsolated is on a main-queue callback or explicitly waived"
    exit 0
fi
echo "  🛑 $FINDINGS unproven assumeIsolated — a false assumption here is a hard crash, not a warning"
exit 1
