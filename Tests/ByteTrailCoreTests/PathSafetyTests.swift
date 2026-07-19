import Foundation
import XCTest
@testable import ByteTrailCore

final class PathSafetyTests: XCTestCase {
    func testNormalizationContainmentAndPrefixCollision() throws {
        let fixture = try TemporaryFixture()
        let approved = try fixture.directory("approved")
        let child = approved.appendingPathComponent("one/../two").standardizedFileURL
        let collision = fixture.root.appendingPathComponent("approved-escape/file")
        let validator = PathContainmentValidator()
        XCTAssertTrue(validator.isContained(child, in: approved))
        XCTAssertFalse(validator.isContained(collision, in: approved))
        XCTAssertEqual(validator.standardized(child).lastPathComponent, "two")
    }

    func testSymbolicLinkEscapeAndNestedLinkRejected() throws {
        let fixture = try TemporaryFixture()
        let approved = try fixture.directory("approved")
        let outside = try fixture.directory("outside")
        _ = try fixture.file("outside/secret", bytes: 8)
        let link = approved.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let nested = try fixture.directory("approved/nested")
        let nestedLink = nested.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: nestedLink, withDestinationURL: outside)
        let rule = fixtureRule(root: approved)
        let validator = FileSystemValidator(homeDirectory: fixture.root)
        XCTAssertThrowsError(try validator.validateForScan(link, rule: rule, approvedRoot: approved))
        XCTAssertFalse(PathContainmentValidator().isResolvedContained(nestedLink.appendingPathComponent("secret"), in: approved))
    }

    func testBrokenSymbolicLinkRejected() throws {
        let fixture = try TemporaryFixture()
        let approved = try fixture.directory("approved")
        let link = approved.appendingPathComponent("broken")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: fixture.root.appendingPathComponent("missing").path)
        let rule = fixtureRule(root: approved)
        XCTAssertThrowsError(try FileSystemValidator(homeDirectory: fixture.root).validateForScan(link, rule: rule, approvedRoot: approved))
    }

    func testProtectedRootsAndProtectedDescendants() throws {
        let policy = ProtectedPathPolicy()
        XCTAssertTrue(policy.isAlwaysProtected(URL(fileURLWithPath: "/System/Library")))
        XCTAssertTrue(policy.isAlwaysProtected(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")))
        XCTAssertTrue(policy.intersectsProtectedDescendant(FileManager.default.homeDirectoryForCurrentUser))
        XCTAssertFalse(policy.isAlwaysProtected(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")))
    }

    func testChangedAndDeletedFilesFailRevalidation() async throws {
        let fixture = try TemporaryFixture()
        let approved = try fixture.directory("approved")
        let file = try fixture.file("approved/cache.bin", bytes: 20)
        let rule = fixtureRule(root: approved)
        var item = try await fixtureItem(url: file, root: approved, rule: rule)
        item.scanSnapshot.resourceIdentifier = "not-the-current-identifier"
        let validator = FileSystemValidator(homeDirectory: fixture.root)
        XCTAssertThrowsError(try validator.revalidateForCleanup(item, rule: rule))

        let second = try fixture.file("approved/deleted.bin", bytes: 12)
        let deletedItem = try await fixtureItem(url: second, root: approved, rule: rule)
        try FileManager.default.removeItem(at: second)
        XCTAssertThrowsError(try validator.revalidateForCleanup(deletedItem, rule: rule))
    }

    func testDebugMutationLockRefusesRealHome() {
        #if DEBUG
        XCTAssertFalse(DevelopmentSafetyLock.permitsMutation(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/file")))
        XCTAssertThrowsError(try DevelopmentSafetyLock.validateMutation(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/file")))
        #endif
    }
}
