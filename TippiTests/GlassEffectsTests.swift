import XCTest
@testable import Tippi

/// Rechenteile der Porter-Optik: Richtung eines Wechsels und Feder je Kante der Pille.
final class GlassEffectsTests: XCTestCase {
    func testDirectionFollowsIndexChange() {
        XCTAssertEqual(GlassMotion.direction(from: 0, to: 2), 1)
        XCTAssertEqual(GlassMotion.direction(from: 3, to: 1), -1)
        XCTAssertEqual(GlassMotion.direction(from: 1, to: 1), 0, "kein Wechsel")
        XCTAssertEqual(GlassMotion.direction(from: nil, to: 1), 0, "erster Auftritt gleitet nicht")
        XCTAssertEqual(GlassMotion.direction(from: 1, to: nil), 0)
    }

    func testLeadingEdgeIsTightTrailingEdgeIsSoft() {
        // Nach rechts: rechte Kante vorn (straff), linke hinten (weich) – die Pille dehnt sich.
        XCTAssertEqual(GlassMotion.role(direction: 1, rightEdge: true), .lead)
        XCTAssertEqual(GlassMotion.role(direction: 1, rightEdge: false), .trail)
        XCTAssertEqual(GlassMotion.role(direction: -1, rightEdge: false), .lead)
        XCTAssertEqual(GlassMotion.role(direction: -1, rightEdge: true), .trail)
        XCTAssertEqual(GlassMotion.role(direction: 0, rightEdge: true), .even)
        XCTAssertEqual(GlassMotion.role(direction: 0, rightEdge: false), .even)
    }
}
