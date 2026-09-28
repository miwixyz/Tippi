import Foundation

/// Random passwords for "Passwort erzeugen" (menu bar + hotkey popup).
/// Design: docs/SECURE-DESIGN-currency-password.md, section 2.
enum PasswordGenerator {
    /// Without the look-alikes I/O, l/o and 0/1 — a password that gets read
    /// off a screen or typed on a phone must not hinge on them.
    static let uppercase = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let lowercase = Array("abcdefghijkmnpqrstuvwxyz")
    static let digits = Array("23456789")
    /// Michael's set (2026-09-28). `§` is not ASCII; the rare site that
    /// refuses it gets a fresh password on the next click.
    static let symbols = Array("/()=?&%$§\"!-_:;")

    static let classes = [uppercase, lowercase, digits, symbols]
    static let defaultLength = 12

    /// One character from every class, the rest from all of them, then
    /// shuffled — so the mandatory characters sit at unpredictable positions.
    /// `random(in:)`/`randomElement(using:)` are uniform (no modulo bias).
    static func generate<G: RandomNumberGenerator>(length: Int = defaultLength, using generator: inout G) -> String {
        let all = classes.flatMap { $0 }
        var characters = classes.compactMap { $0.randomElement(using: &generator) }
        while characters.count < max(length, classes.count) {
            if let next = all.randomElement(using: &generator) { characters.append(next) }
        }
        characters.shuffle(using: &generator)
        return String(characters)
    }

    /// `SystemRandomNumberGenerator` is cryptographically secure on Apple
    /// platforms (backed by `arc4random_buf`).
    static func generate(length: Int = defaultLength) -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(length: length, using: &generator)
    }
}
