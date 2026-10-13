import AppKit
import ApplicationServices

/// Bedienungshilfen-Lesehilfen der Autovervollständigung — aus
/// `AutocompleteController.swift` ausgelagert (SwiftLint `type_body_length`),
/// unverändert. Jeder Aufruf läuft mit dem Zeitlimit, das der Aufrufer am
/// Element gesetzt hat.
extension AutocompleteController {
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let raw = ref, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
        return (raw as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    static func string(_ element: AXUIElement, forRange range: CFRange) -> String? {
        var mutable = range
        guard range.length > 0, let axRange = AXValueCreate(.cfRange, &mutable) else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, axRange, &ref
        ) == .success else { return nil }
        return ref as? String
    }

    static func isValueSettable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    static func selectedRangeViaTextMarkers(_ element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &ref) == .success,
              let raw = ref, CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
        let markers = raw as! AXTextMarkerRange
        guard let start = index(of: AXTextMarkerRangeCopyStartMarker(markers), in: element),
              let end = index(of: AXTextMarkerRangeCopyEndMarker(markers), in: element),
              start >= 0, end >= start else { return nil }
        return CFRange(location: start, length: end - start)
    }

    static func index(of marker: AXTextMarker, in element: AXUIElement) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, "AXIndexForTextMarker" as CFString, marker, &ref
        ) == .success else { return nil }
        return (ref as? NSNumber)?.intValue
    }

    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let raw = ref, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        // swiftlint:disable:next force_cast - CF-Typ oben per CFGetTypeID geprüft
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
}
