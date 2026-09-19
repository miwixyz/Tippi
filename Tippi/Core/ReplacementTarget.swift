import AppKit
import ApplicationServices
import os

private let replacementLog = Logger(subsystem: "com.tippi.app", category: "replacement")

/// Where a produced result gets written back to.
///
/// Three call sites in `AppDelegate` each carried their own copy of the
/// "native Notes editor → Accessibility → clipboard" ladder: the selection
/// action bar (`applySnapshotResult`), the hotkey flow (`applyCapturedResult`)
/// and the translate panel (`replaceTranslationSource`). The duplication
/// produced the *same* bug twice — v2.8.3 (`a3c45ce`) added the native-Notes
/// branch to two of the three, and the audit of 2026-09-19 (`3532ca0`) found
/// the third one still writing translations into whatever app happened to be
/// in front. The audit's standards finder predicted the third miss before it
/// was found: the copies neither shared a name nor a signature, so nothing
/// tied them together.
///
/// This type exists so that "where does a result go" is decided in exactly one
/// place. Adding a fourth kind of destination, or changing the order, is now a
/// single edit rather than three that must be kept in sync by memory.
enum ReplacementTarget {
    /// Tippi's own Notes editor, written directly through AppKit.
    ///
    /// The Accessibility ladder structurally cannot serve this case:
    /// `resolvedSourceAppForCapture()` returns the last *non*-Tippi app by
    /// definition, so an AX write from here lands in the wrong process.
    case native(NSTextView, NSRange)

    /// Another app's text field, captured as element + range while the
    /// selection was still live (before a popup stole focus and collapsed it).
    case accessibility(AXUIElement, CFRange, NSRunningApplication?)

    /// Nothing usable was captured — replace the focused selection, or paste.
    case blind(NSRunningApplication?)
}

extension ReplacementTarget {
    /// Chooses the destination from whatever the caller managed to capture.
    ///
    /// Priority is native → accessibility → blind. That order is deliberately
    /// written down only here: a native text view and an AX element are never
    /// both populated (see `SelectionSnapshot` and `AppDelegate`'s `last*`
    /// state), but if a future capture path ever sets both, the native branch
    /// is the correct winner — it is the one that cannot target the wrong app.
    init(
        nativeTextView: NSTextView?,
        nativeRange: NSRange?,
        element: AXUIElement?,
        range: CFRange?,
        app: NSRunningApplication?
    ) {
        if let nativeTextView, let nativeRange {
            self = .native(nativeTextView, nativeRange)
        } else if let element, let range {
            self = .accessibility(element, range, app)
        } else {
            self = .blind(app)
        }
    }

    /// Destination for the auto-popup-on-selection path, which captures
    /// everything up front in a `SelectionSnapshot` instead of on `self`.
    init(snapshot: SelectionSnapshot) {
        self.init(
            nativeTextView: snapshot.nativeTextView,
            nativeRange: snapshot.nativeRange,
            element: snapshot.element,
            range: snapshot.range,
            app: snapshot.sourceApp
        )
    }
}

/// The single implementation of the replacement ladder. Every path that writes
/// a result back — local quick actions, AI replace/append, translate — goes
/// through `write(_:attributed:expecting:to:)`.
@MainActor
enum ReplacementWriter {
    /// Writes `plainText` to `target`, falling back down the ladder when the
    /// destination app ignores or refuses the Accessibility write.
    ///
    /// `attributed`, when present, is only used on the fallback paths — the
    /// native and AX writes are plain-text by nature. `originalText` is what
    /// the range contained at capture time; `replaceViaElement` logs a
    /// mismatch but still proceeds (see its comment on why it is diagnostic
    /// rather than a hard gate).
    static func write(
        _ plainText: String,
        attributed: NSAttributedString? = nil,
        expecting originalText: String? = nil,
        to target: ReplacementTarget
    ) async {
        switch target {
        case .native(let textView, let range):
            writeNative(plainText, in: textView, range: range)

        case .accessibility(let element, let range, let app):
            switch TextInsertion.replaceViaElement(element, range: range, with: plainText, expecting: originalText) {
            case .replaced:
                return
            case .ignored:
                // The AX write was silently discarded (Electron/Chromium). The
                // selection has collapsed, so it can no longer be replaced —
                // insert at the current cursor position as a best effort.
                await TextInsertion.insertViaClipboard(plainText, into: app)
            case .unavailable:
                await writeFallback(plainText, attributed: attributed, in: app)
            }

        case .blind(let app):
            await writeFallback(plainText, attributed: attributed, in: app)
        }
    }

    /// Replaces `range` in `textView` directly via AppKit — used for Tippi's
    /// own Notes editor instead of the Accessibility/clipboard machinery built
    /// for other apps' text fields. Bracketed with
    /// `shouldChangeText`/`didChangeText` (the correct way to make a
    /// programmatic edit look identical to a user-typed one) so undo and the
    /// SwiftUI text binding both update correctly.
    static func writeNative(_ text: String, in textView: NSTextView, range: NSRange) {
        // The range was captured when the trigger fired; an AI round-trip takes
        // seconds, and the user can edit — or delete — the very note being
        // rewritten while it runs. `NSTextView` does not bounds-check this:
        // `shouldChangeText(in:)` with a range past the end does not return
        // false, it aborts the process ("freed pointer was not the last
        // allocation"). Measured 2026-09-19 while merging the three ladders
        // into this one; the crash was reachable from all three before, and
        // fixable in only one place after.
        let length = (textView.string as NSString).length
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0,
              range.location <= length,
              length - range.location >= range.length
        else {
            replacementLog.notice(
                "writeNative → skipped (captured range \(range.location, privacy: .public)/\(range.length, privacy: .public) no longer fits a \(length, privacy: .public)-character document)")
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.replaceCharacters(in: range, with: text)
        textView.didChangeText()
    }

    private static func writeFallback(
        _ plainText: String,
        attributed: NSAttributedString?,
        in app: NSRunningApplication?
    ) async {
        if let attributed {
            await TextInsertion.replace(with: attributed, fallbackPlainText: plainText, in: app)
        } else {
            await TextInsertion.replace(with: plainText, in: app)
        }
    }
}
