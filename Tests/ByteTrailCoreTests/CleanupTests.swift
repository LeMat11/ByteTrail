import Foundation
import XCTest
@testable import ByteTrailCore

final class CleanupTests: XCTestCase {
    func testOverlappingParentAndChildAreNotProcessedTwice() async throws {
        let fixture = try TemporaryFixture()
        let approved = try fixture.directory("approved")
        let parent = try fixture.directory("approved/parent")
        let child = try fixture.file("approved/parent/cache.bin", bytes: 128)
        let rule = fixtureRule(root: approved)
        let parentItem = try await fixtureItem(url: parent, root: approved, rule: rule)
        let childItem = try await fixtureItem(url: child, root: approved, rule: rule)
        let coordinator = CleanupCoordinator(
            ruleEngine: try RuleEngine(rules: [rule]),
            validator: FileSystemValidator(homeDirectory: fixture.root),
            historyStore: CleanupHistoryStore(storageURL: fixture.root.appendingPathComponent("state/history.json")),
            recoveryStore: RecoveryStore(storageURL: fixture.root.appendingPathComponent("state/recovery.json")),
            vaultOperation: RecoveryVaultOperation(vaultRoot: fixture.root.appendingPathComponent("vault"))
        )

        let results = await coordinator.clean(items: [childItem, parentItem], dryRun: true)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.itemID, parentItem.id)
        XCTAssertEqual(results.first?.status, .dryRun)
        XCTAssertEqual(results.last?.itemID, childItem.id)
        XCTAssertEqual(results.last?.status, .skipped)
        XCTAssertEqual(results.last?.message, "Overlapping cleanup target skipped.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))
    }

    func testEmbeddedMoveToTrashRuleFailsClosedInDebug() async throws {
        let fixture = try TemporaryFixture()
        let root = try fixture.directory("authorized")
        let file = try fixture.file("authorized/large.bin", bytes: 256)
        let rule = fixtureRule(id: "fixture.dynamic.large", root: root, risk: .review, method: .moveToTrash, category: .largeFile)
        var item = try await fixtureItem(url: file, root: root, rule: rule)
        item.embeddedRule = rule
        let recoveryStore = RecoveryStore(storageURL: fixture.root.appendingPathComponent("state/recovery.json"))
        let coordinator = CleanupCoordinator(
            ruleEngine: try RuleEngine(rules: []),
            validator: FileSystemValidator(homeDirectory: fixture.root),
            historyStore: CleanupHistoryStore(storageURL: fixture.root.appendingPathComponent("state/history.json")),
            recoveryStore: recoveryStore,
            vaultOperation: RecoveryVaultOperation(vaultRoot: fixture.root.appendingPathComponent("vault"))
        )

        let results = await coordinator.clean(items: [item], dryRun: false)
        let result = try XCTUnwrap(results.first)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let recoveryEntries = await recoveryStore.allEntries()
        XCTAssertTrue(recoveryEntries.isEmpty)
    }

    func testDryRunDoesNotModifyFixtureAndRecordsHistory() async throws {
        let fixture = try TemporaryFixture()
        let root = try fixture.directory("approved")
        let file = try fixture.file("approved/cache", bytes: 64)
        let rule = fixtureRule(root: root)
        let item = try await fixtureItem(url: file, root: root, rule: rule)
        let historyURL = fixture.root.appendingPathComponent("state/history.json")
        let history = CleanupHistoryStore(storageURL: historyURL)
        let coordinator = CleanupCoordinator(
            ruleEngine: try RuleEngine(rules: [rule]),
            validator: FileSystemValidator(homeDirectory: fixture.root),
            historyStore: history,
            recoveryStore: RecoveryStore(storageURL: fixture.root.appendingPathComponent("state/recovery.json")),
            vaultOperation: RecoveryVaultOperation(vaultRoot: fixture.root.appendingPathComponent("vault"))
        )
        let results = await coordinator.clean(items: [item], dryRun: true)
        XCTAssertEqual(results.first?.status, .dryRun)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let entries = await history.allEntries()
        XCTAssertEqual(entries.count, 1)
    }

    func testRecoveryVaultMoveAndRestoreStayInsideTemporaryFixture() async throws {
        let fixture = try TemporaryFixture()
        let systemTemporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).standardizedFileURL
        XCTAssertTrue(PathContainmentValidator().isContained(fixture.root, in: systemTemporary, allowRootItself: false))
        let root = try fixture.directory("approved")
        let file = try fixture.file("approved/cache", bytes: 128)
        let rule = fixtureRule(root: root)
        let item = try await fixtureItem(url: file, root: root, rule: rule)
        let recoveryStore = RecoveryStore(storageURL: fixture.root.appendingPathComponent("state/recovery.json"))
        let coordinator = CleanupCoordinator(
            ruleEngine: try RuleEngine(rules: [rule]),
            validator: FileSystemValidator(homeDirectory: fixture.root),
            historyStore: CleanupHistoryStore(storageURL: fixture.root.appendingPathComponent("state/history.json")),
            recoveryStore: recoveryStore,
            vaultOperation: RecoveryVaultOperation(vaultRoot: fixture.root.appendingPathComponent("vault"))
        )
        let cleanupResults = await coordinator.clean(items: [item], dryRun: false)
        let result = try XCTUnwrap(cleanupResults.first)
        XCTAssertEqual(result.status, .movedToRecovery)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let recoveryEntries = await recoveryStore.allEntries()
        let recovery = try XCTUnwrap(recoveryEntries.first)
        XCTAssertTrue(PathContainmentValidator().isContained(recovery.recoveryURL, in: fixture.root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.recoveryURL.path))
        let restored = await coordinator.restore(recovery)
        XCTAssertEqual(restored.status, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testRestoreNameCollisionFailsWithoutOverwrite() async throws {
        let fixture = try TemporaryFixture()
        let original = try fixture.file("approved/original", bytes: 4)
        let recovery = try fixture.file("vault/recovery", bytes: 8)
        let entry = RecoveryEntry(originalURL: original, recoveryURL: recovery, size: 8, ruleIdentifier: "fixture")
        XCTAssertThrowsError(try RestoreOperation().execute(entry)) { error in
            XCTAssertEqual(error as? CleanupOperationError, .destinationExists)
        }
        XCTAssertEqual(try Data(contentsOf: original).count, 4)
        XCTAssertEqual(try Data(contentsOf: recovery).count, 8)
    }

    func testChangedTargetIsSkipped() async throws {
        let fixture = try TemporaryFixture()
        let root = try fixture.directory("approved")
        let file = try fixture.file("approved/cache", bytes: 16)
        let rule = fixtureRule(root: root)
        let item = try await fixtureItem(url: file, root: root, rule: rule)
        try Data(repeating: 7, count: 1_024).write(to: file)
        let coordinator = CleanupCoordinator(
            ruleEngine: try RuleEngine(rules: [rule]),
            validator: FileSystemValidator(homeDirectory: fixture.root),
            historyStore: CleanupHistoryStore(storageURL: fixture.root.appendingPathComponent("state/history.json")),
            recoveryStore: RecoveryStore(storageURL: fixture.root.appendingPathComponent("state/recovery.json")),
            vaultOperation: RecoveryVaultOperation(vaultRoot: fixture.root.appendingPathComponent("vault"))
        )
        let cleanupResults = await coordinator.clean(items: [item], dryRun: false)
        let result = try XCTUnwrap(cleanupResults.first)
        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.message.contains("changed"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testPerItemFailureDoesNotStopLaterFixture() async throws {
        let fixture = try TemporaryFixture()
        let root = try fixture.directory("approved")
        let firstURL = try fixture.file("approved/first", bytes: 8)
        let secondURL = try fixture.file("approved/second", bytes: 8)
        let rule = fixtureRule(root: root)
        var first = try await fixtureItem(url: firstURL, root: root, rule: rule)
        first.scanSnapshot.resourceIdentifier = "changed"
        let second = try await fixtureItem(url: secondURL, root: root, rule: rule)
        let coordinator = CleanupCoordinator(
            ruleEngine: try RuleEngine(rules: [rule]), validator: FileSystemValidator(homeDirectory: fixture.root),
            historyStore: CleanupHistoryStore(storageURL: fixture.root.appendingPathComponent("state/history.json")),
            recoveryStore: RecoveryStore(storageURL: fixture.root.appendingPathComponent("state/recovery.json")),
            vaultOperation: RecoveryVaultOperation(vaultRoot: fixture.root.appendingPathComponent("vault"))
        )
        let results = await coordinator.clean(items: [first, second], dryRun: false)
        XCTAssertEqual(results.map(\.status), [.failed, .movedToRecovery])
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testTrashOperationIsNotExecutedInDebugTests() throws {
        #if DEBUG
        let fixture = try TemporaryFixture()
        let file = try fixture.file("trash-fixture", bytes: 4)
        XCTAssertThrowsError(try TrashCleanupOperation().execute(source: file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        #endif
    }

    func testTrashEmptyingPermanentlyRemovesOnlySyntheticFixtureChildren() throws {
        let fixture = try TemporaryFixture()
        let systemTemporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).standardizedFileURL
        let trashRoot = try fixture.directory("SyntheticTrash-\(UUID().uuidString)")
        print("ByteTrail synthetic Trash fixture: \(trashRoot.standardizedFileURL.path)")
        XCTAssertTrue(PathContainmentValidator().isContained(trashRoot, in: systemTemporary, allowRootItself: false))
        let first = try fixture.file("\(trashRoot.lastPathComponent)/first.bin", bytes: 4_096)
        let nested = try fixture.file("\(trashRoot.lastPathComponent)/folder/second.bin", bytes: 8_192)
        let outside = try fixture.file("must-remain.bin", bytes: 128)
        let service = TrashEmptyingService(trashRoot: trashRoot, homeDirectory: fixture.root)

        let result = try service.emptyTrash()

        XCTAssertEqual(result.removedItemCount, 2)
        XCTAssertGreaterThanOrEqual(result.bytesFreed, 12_288)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testTrashEmptyingRemovesSymlinkWithoutTouchingItsTarget() throws {
        let fixture = try TemporaryFixture()
        let systemTemporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).standardizedFileURL
        let trashRoot = try fixture.directory("SyntheticTrash-\(UUID().uuidString)")
        print("ByteTrail synthetic Trash fixture: \(trashRoot.standardizedFileURL.path)")
        XCTAssertTrue(PathContainmentValidator().isContained(trashRoot, in: systemTemporary, allowRootItself: false))
        let outside = try fixture.file("outside/keep.bin", bytes: 256)
        let link = trashRoot.appendingPathComponent("linked-item")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let service = TrashEmptyingService(trashRoot: trashRoot, homeDirectory: fixture.root)

        let result = try service.emptyTrash()

        XCTAssertEqual(result.removedItemCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testTrashEmptyingCannotTargetRealUserTrashInDebug() throws {
        #if DEBUG
        let realTrash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        let service = TrashEmptyingService(trashRoot: realTrash)
        XCTAssertThrowsError(try service.emptyTrash()) { error in
            XCTAssertEqual(error as? TrashEmptyingError, .invalidTrashRoot)
        }
        #endif
    }
}
