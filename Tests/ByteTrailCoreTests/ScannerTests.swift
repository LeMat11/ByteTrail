import Foundation
import XCTest
@testable import ByteTrailCore

private struct FixtureEventScanner: ScannerProtocol {
    let identifier: String
    let displayName = "Fixture Scanner"
    let items: [CleanableItem]
    let issue: ScanIssue?
    let delayNanoseconds: UInt64

    func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let producer = Task {
                for item in items {
                    if Task.isCancelled { break }
                    continuation.yield(.finding(item))
                    if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
                }
                if let issue { continuation.yield(.issue(issue)) }
                continuation.yield(.finished(scannerIdentifier: identifier))
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}

final class ScannerTests: XCTestCase {
    func testApplicationScannerMeasuresExactBundleAndInstalledCache() async throws {
        let fixture = try TemporaryFixture()
        let applications = try fixture.directory("Applications")
        let application = try fixture.application(
            "Applications/Fixture.app",
            bundleIdentifier: "com.example.fixture",
            name: "Fixture App"
        )
        _ = try fixture.file("Applications/Fixture.app/Contents/MacOS/Fixture", bytes: 2_048)
        let cache = try fixture.directory("Library/Caches/com.example.fixture")
        _ = try fixture.file("Library/Caches/com.example.fixture/cache.bin", bytes: 512)
        _ = try fixture.file("Library/Caches/com.example.fixture-lookalike/cache.bin", bytes: 512)
        let applicationResolver = ApplicationMetadataResolver(
            homeDirectory: fixture.root,
            applicationRoots: [applications]
        )
        let context = ScanContext(
            ruleEngine: try RuleEngine(homeDirectory: fixture.root),
            settings: ScanSettings(),
            homeDirectory: fixture.root,
            applicationResolver: applicationResolver,
            fileSystemValidator: FileSystemValidator(homeDirectory: fixture.root)
        )
        var findings: [CleanableItem] = []

        for await event in ApplicationScanner().scan(context: context) {
            if case let .finding(item) = event { findings.append(item) }
        }

        let bundle = try XCTUnwrap(findings.first { $0.category == .applicationBundle })
        XCTAssertEqual(bundle.standardizedPath, application.path)
        XCTAssertEqual(bundle.displayName, "Fixture App")
        XCTAssertEqual(bundle.provenance.producedByIdentifier, "com.example.fixture")
        XCTAssertEqual(bundle.riskLevel, .review)
        XCTAssertFalse(bundle.selected)
        XCTAssertGreaterThanOrEqual(bundle.size, 2_048)
        XCTAssertGreaterThanOrEqual(bundle.fileCount, 2)
        XCTAssertEqual(bundle.approvedRoot, application.path)

        let coordinator = CleanupCoordinator(
            ruleEngine: try RuleEngine(rules: [], homeDirectory: fixture.root),
            validator: FileSystemValidator(homeDirectory: fixture.root),
            historyStore: CleanupHistoryStore(storageURL: fixture.root.appendingPathComponent("state/history.json")),
            recoveryStore: RecoveryStore(storageURL: fixture.root.appendingPathComponent("state/recovery.json")),
            vaultOperation: RecoveryVaultOperation(vaultRoot: fixture.root.appendingPathComponent("vault")),
            homeDirectory: fixture.root
        )
        let cleanupResults = await coordinator.clean(items: [bundle], dryRun: true)
        XCTAssertEqual(cleanupResults.first?.status, .dryRun)
        XCTAssertTrue(FileManager.default.fileExists(atPath: application.path))

        let exactCache = try XCTUnwrap(findings.first { $0.standardizedPath == cache.path })
        XCTAssertEqual(exactCache.category, .userCache)
        XCTAssertEqual(exactCache.provenance.sourceApplicationURL, application)
        XCTAssertEqual(exactCache.riskLevel, .safe)
        XCTAssertEqual(exactCache.approvedRoot, cache.path)
        XCTAssertFalse(findings.contains { $0.standardizedPath.hasSuffix("com.example.fixture-lookalike") })
    }

    func testByteTrailApplicationIsProtectedAndAnalysisOnly() async throws {
        let fixture = try TemporaryFixture()
        let applications = try fixture.directory("Applications")
        let application = try fixture.application(
            "Applications/ByteTrail.app",
            bundleIdentifier: AppConfiguration.bundleIdentifier,
            name: "ByteTrail"
        )
        let applicationResolver = ApplicationMetadataResolver(
            homeDirectory: fixture.root,
            applicationRoots: [applications]
        )
        let context = ScanContext(
            ruleEngine: try RuleEngine(homeDirectory: fixture.root),
            settings: ScanSettings(),
            homeDirectory: fixture.root,
            applicationResolver: applicationResolver,
            fileSystemValidator: FileSystemValidator(homeDirectory: fixture.root)
        )
        var findings: [CleanableItem] = []

        for await event in ApplicationScanner().scan(context: context) {
            if case let .finding(item) = event { findings.append(item) }
        }

        let item = try XCTUnwrap(findings.first { $0.standardizedPath == application.path })
        XCTAssertEqual(item.riskLevel, .protected)
        XCTAssertEqual(item.cleanupMethod, .analysisOnly)
        XCTAssertFalse(item.selected)
    }

    func testApplicationLeftoversAreImmediateConservativeReviewCandidates() async throws {
        let fixture = try TemporaryFixture()
        let applications = try fixture.directory("Applications")
        _ = try fixture.application(
            "Applications/Installed.app",
            bundleIdentifier: "com.example.installed",
            name: "Installed"
        )
        _ = try fixture.file("Library/Caches/com.example.removed/cache.bin", bytes: 64)
        _ = try fixture.file("Library/Caches/com.example.installed/cache.bin", bytes: 64)
        _ = try fixture.file("Library/Caches/com.apple.synthetic/cache.bin", bytes: 64)
        _ = try fixture.file("Library/Caches/com.bytetrail.mac/cache.bin", bytes: 64)
        _ = try fixture.file("Library/Caches/Friendly App/cache.bin", bytes: 64)
        _ = try fixture.file("Library/Preferences/com.example.preference.plist", bytes: 64)
        _ = try fixture.file("Library/Preferences/com.example.wrong-extension.json", bytes: 64)
        _ = try fixture.file("Library/Application Support/com.example.parent/com.example.nested/data.bin", bytes: 64)
        let escapedTarget = try fixture.directory("Outside")
        let link = fixture.root.appendingPathComponent("Library/Logs/com.example.link")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: escapedTarget)
        let applicationResolver = ApplicationMetadataResolver(
            homeDirectory: fixture.root,
            applicationRoots: [applications]
        )
        let context = ScanContext(
            ruleEngine: try RuleEngine(homeDirectory: fixture.root),
            settings: ScanSettings(),
            homeDirectory: fixture.root,
            applicationResolver: applicationResolver,
            fileSystemValidator: FileSystemValidator(homeDirectory: fixture.root)
        )
        var findings: [CleanableItem] = []

        for await event in ApplicationLeftoverScanner().scan(context: context) {
            if case let .finding(item) = event { findings.append(item) }
        }

        let identifiers = Set(findings.compactMap(\.provenance.producedByIdentifier))
        XCTAssertTrue(identifiers.contains("com.example.removed"))
        XCTAssertTrue(identifiers.contains("com.example.preference"))
        XCTAssertTrue(identifiers.contains("com.example.parent"))
        XCTAssertFalse(identifiers.contains("com.example.installed"))
        XCTAssertFalse(identifiers.contains("com.apple.synthetic"))
        XCTAssertFalse(identifiers.contains("com.bytetrail.mac"))
        XCTAssertFalse(identifiers.contains("Friendly App"))
        XCTAssertFalse(identifiers.contains("com.example.wrong-extension"))
        XCTAssertFalse(identifiers.contains("com.example.nested"))
        XCTAssertFalse(identifiers.contains("com.example.link"))
        XCTAssertTrue(findings.allSatisfy { $0.riskLevel == .review && !$0.selected })
        XCTAssertTrue(findings.allSatisfy { $0.cleanupMethod == .recoveryVault })
    }

    func testBundleIdentifierPolicyRejectsAmbiguousDirectoryNames() {
        let policy = BundleIdentifierPolicy()
        XCTAssertTrue(policy.isConservativeCandidate("com.example.application"))
        XCTAssertTrue(policy.isConservativeCandidate("org.example.app-helper"))
        XCTAssertFalse(policy.isConservativeCandidate("Application Support"))
        XCTAssertFalse(policy.isConservativeCandidate("com..example"))
        XCTAssertFalse(policy.isConservativeCandidate(".com.example"))
        XCTAssertFalse(policy.isConservativeCandidate("com.example_legacy"))
        XCTAssertFalse(policy.isConservativeCandidate("com.example."))
    }

    func testInstalledApplicationResolverUsesExactBundleIdentifier() async throws {
        let fixture = try TemporaryFixture()
        let applications = try fixture.directory("Applications")
        let app = try fixture.application("Applications/Fixture.app", bundleIdentifier: "com.example.fixture", name: "Fixture App")
        let resolver = ApplicationMetadataResolver(homeDirectory: fixture.root, applicationRoots: [applications])

        let resolved = await resolver.resolve(bundleIdentifier: "com.example.fixture")

        XCTAssertEqual(resolved?.name, "Fixture App")
        XCTAssertEqual(resolved?.url, app)
        let missing = await resolver.resolve(bundleIdentifier: "com.example.fixtur")
        XCTAssertNil(missing)
    }

    func testCacheScannerAttributesExactSandboxCacheWithoutTargetingContainer() async throws {
        let fixture = try TemporaryFixture()
        let applications = try fixture.directory("Applications")
        let app = try fixture.application("Applications/Fixture.app", bundleIdentifier: "com.example.fixture", name: "Fixture App")
        let cache = try fixture.directory("Library/Containers/com.example.fixture/Data/Library/Caches")
        _ = try fixture.file("Library/Containers/com.example.fixture/Data/Library/Caches/content.bin", bytes: 64)
        let applicationResolver = ApplicationMetadataResolver(homeDirectory: fixture.root, applicationRoots: [applications])
        let sourceResolver = SourceResolver(applicationResolver: applicationResolver)
        let context = ScanContext(
            ruleEngine: try RuleEngine(homeDirectory: fixture.root),
            settings: ScanSettings(),
            homeDirectory: fixture.root,
            sourceResolver: sourceResolver,
            fileSystemValidator: FileSystemValidator(homeDirectory: fixture.root)
        )
        var findings: [CleanableItem] = []

        for await event in CacheScanner().scan(context: context) {
            if case let .finding(item) = event { findings.append(item) }
        }

        let item = try XCTUnwrap(findings.first {
            URL(fileURLWithPath: $0.standardizedPath).resolvingSymlinksInPath() == cache.resolvingSymlinksInPath()
        })
        XCTAssertEqual(item.provenance.producedByName, "Fixture App")
        XCTAssertEqual(item.provenance.producedByIdentifier, "com.example.fixture")
        XCTAssertEqual(item.provenance.sourceApplicationURL, app)
        XCTAssertEqual(item.riskLevel, .safe)
        XCTAssertEqual(URL(fileURLWithPath: item.approvedRoot).resolvingSymlinksInPath(), cache.resolvingSymlinksInPath())
        XCTAssertEqual(item.embeddedRule?.approvedRoots.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }, [cache.resolvingSymlinksInPath()])
        XCTAssertNotEqual(
            URL(fileURLWithPath: item.approvedRoot).resolvingSymlinksInPath(),
            fixture.root.appendingPathComponent("Library/Containers/com.example.fixture").resolvingSymlinksInPath()
        )
    }

    func testLargeFileScannerRecursesAuthorizedRootsAndDeduplicatesNestedRoots() async throws {
        let fixture = try TemporaryFixture()
        let scanRoot = try fixture.directory("ScanRoot")
        let nestedRoot = try fixture.directory("ScanRoot/Nested")
        let largeFile = try fixture.file("ScanRoot/Nested/archive.bin", bytes: 2_048)
        _ = try fixture.file("ScanRoot/small.bin", bytes: 128)
        let context = ScanContext(
            ruleEngine: try RuleEngine(homeDirectory: fixture.root),
            settings: ScanSettings(largeFileMinimumBytes: 1_024, authorizedFolders: [scanRoot, nestedRoot]),
            homeDirectory: fixture.root,
            fileSystemValidator: FileSystemValidator(homeDirectory: fixture.root)
        )
        var findings: [CleanableItem] = []

        for await event in LargeFileScanner().scan(context: context) {
            if case let .finding(item) = event { findings.append(item) }
        }

        let matching = findings.filter { $0.standardizedPath == largeFile.path }
        XCTAssertEqual(matching.count, 1)
        let item = try XCTUnwrap(matching.first)
        XCTAssertEqual(item.riskLevel, .review)
        XCTAssertEqual(item.cleanupMethod, .moveToTrash)
        XCTAssertFalse(item.selected)
        XCTAssertEqual(item.approvedRoot, nestedRoot.path)
        XCTAssertEqual(item.embeddedRule?.approvedRoots, [nestedRoot.path])
    }

    func testEmptyDirectoryProducesNoCacheFindings() async throws {
        let fixture = try TemporaryFixture()
        _ = try fixture.directory("Library/Caches")
        let engine = try RuleEngine(homeDirectory: fixture.root)
        let context = ScanContext(ruleEngine: engine, settings: ScanSettings(), homeDirectory: fixture.root)
        var findings: [CleanableItem] = []
        for await event in CacheScanner().scan(context: context) {
            if case let .finding(item) = event { findings.append(item) }
        }
        XCTAssertTrue(findings.isEmpty)
    }

    func testCacheScannerPreservesPerSourcePermissionOrValidationFailure() async throws {
        let fixture = try TemporaryFixture()
        let cacheRoot = try fixture.directory("Library/Caches")
        let outside = try fixture.directory("outside")
        let link = cacheRoot.appendingPathComponent("escaped.cache")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let engine = try RuleEngine(homeDirectory: fixture.root)
        let context = ScanContext(ruleEngine: engine, settings: ScanSettings(showHiddenFiles: true), homeDirectory: fixture.root)
        var issues: [ScanIssue] = []
        for await event in CacheScanner().scan(context: context) {
            if case let .issue(issue) = event { issues.append(issue) }
        }
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath() }, link.resolvingSymlinksInPath())
    }

    func testLargeSyntheticDirectoryAndHardLinkAreCountedConservatively() throws {
        let fixture = try TemporaryFixture()
        let root = try fixture.directory("tree")
        let original = try fixture.file("tree/original", bytes: 512)
        let hardLink = root.appendingPathComponent("hard-link")
        try FileManager.default.linkItem(at: original, to: hardLink)
        for index in 0..<250 { _ = try fixture.file("tree/sub/\(index).dat", bytes: 8) }
        let result = try FileSizeCalculator(maximumFileCount: 1_000).calculate(root)
        XCTAssertEqual(result.fileCount, 251)
        XCTAssertGreaterThanOrEqual(result.logicalBytes, 512 + 250 * 8)
        XCTAssertFalse(result.hitLimit)
    }

    func testCoordinatorDeduplicatesFindingsFromMultipleScanners() async throws {
        let fixture = try TemporaryFixture()
        let root = try fixture.directory("root")
        let file = try fixture.file("root/cache", bytes: 10)
        let rule = fixtureRule(root: root)
        let item = try await fixtureItem(url: file, root: root, rule: rule)
        let scanner1 = FixtureEventScanner(identifier: "one", items: [item], issue: nil, delayNanoseconds: 0)
        let scanner2 = FixtureEventScanner(identifier: "two", items: [item], issue: nil, delayNanoseconds: 0)
        let coordinator = ScanCoordinator(scanners: [scanner1, scanner2])
        let context = ScanContext(ruleEngine: try RuleEngine(rules: [rule]), settings: ScanSettings(), homeDirectory: fixture.root)
        var findings: [CleanableItem] = []
        for await event in await coordinator.scan(context: context) {
            if case let .finding(value) = event { findings.append(value) }
        }
        XCTAssertEqual(findings.count, 1)
    }

    func testCancellationKeepsPartialResults() async throws {
        let fixture = try TemporaryFixture()
        let root = try fixture.directory("root")
        let rule = fixtureRule(root: root)
        var sourceItems: [CleanableItem] = []
        for index in 0..<20 {
            let file = try fixture.file("root/\(index)", bytes: 1)
            sourceItems.append(try await fixtureItem(url: file, root: root, rule: rule))
        }
        let scanner = FixtureEventScanner(identifier: "slow", items: sourceItems, issue: nil, delayNanoseconds: 20_000_000)
        let coordinator = ScanCoordinator(scanners: [scanner])
        let context = ScanContext(ruleEngine: try RuleEngine(rules: [rule]), settings: ScanSettings(), homeDirectory: fixture.root)
        let stream = await coordinator.scan(context: context)
        var received: [CleanableItem] = []
        let task = Task {
            for await event in stream {
                if case let .finding(item) = event { received.append(item) }
                if received.count == 3 { break }
            }
        }
        await task.value
        XCTAssertEqual(received.count, 3)
        XCTAssertLessThan(received.count, sourceItems.count)
    }

    func testPartialIssueDoesNotDiscardFindings() async throws {
        let fixture = try TemporaryFixture()
        let root = try fixture.directory("root")
        let rule = fixtureRule(root: root)
        let item = try await fixtureItem(url: try fixture.file("root/a"), root: root, rule: rule)
        let issue = ScanIssue(scannerIdentifier: "fixture", path: root.path, message: "Permission denied", permissionStatus: .denied)
        let coordinator = ScanCoordinator(scanners: [FixtureEventScanner(identifier: "fixture", items: [item], issue: issue, delayNanoseconds: 0)])
        let context = ScanContext(ruleEngine: try RuleEngine(rules: [rule]), settings: ScanSettings(), homeDirectory: fixture.root)
        var findings = 0
        var issues = 0
        for await event in await coordinator.scan(context: context) {
            if case .finding = event { findings += 1 }
            if case .issue = event { issues += 1 }
        }
        XCTAssertEqual(findings, 1)
        XCTAssertEqual(issues, 1)
    }
}
