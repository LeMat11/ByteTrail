import ByteTrailCore
import Foundation

private enum VerificationFailure: Error, LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case let .failed(message) = self { return message }
        return nil
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw VerificationFailure.failed(message) }
}

private func requireThrows(_ message: String, _ body: () throws -> Void) throws {
    do { try body(); throw VerificationFailure.failed(message) }
    catch is VerificationFailure { throw VerificationFailure.failed(message) }
    catch { return }
}

private final class Fixture {
    let root: URL

    init() throws {
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).standardizedFileURL
        root = temporary.appendingPathComponent("ByteTrailVerification-\(UUID().uuidString)", isDirectory: true).standardizedFileURL
        print("FIXTURE \(root.path)")
        try require(PathContainmentValidator().isContained(root, in: temporary, allowRootItself: false), "Fixture is outside the system temporary directory")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        guard DevelopmentSafetyLock.permitsMutation(at: root) else {
            print("REFUSED FIXTURE CLEANUP \(root.path)")
            return
        }
        try? FileManager.default.removeItem(at: root)
    }

    func directory(_ path: String) throws -> URL {
        let result = root.appendingPathComponent(path, isDirectory: true).standardizedFileURL
        try require(PathContainmentValidator().isContained(result, in: root, allowRootItself: false), "Fixture child escaped its root")
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    func file(_ path: String, bytes: Int = 32) throws -> URL {
        let result = root.appendingPathComponent(path).standardizedFileURL
        try require(PathContainmentValidator().isContained(result, in: root, allowRootItself: false), "Fixture file escaped its root")
        try FileManager.default.createDirectory(at: result.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x43, count: bytes).write(to: result)
        return result
    }

    func application(_ path: String, bundleIdentifier: String, name: String) throws -> URL {
        let applicationURL = root.appendingPathComponent(path, isDirectory: true).standardizedFileURL
        try require(PathContainmentValidator().isContained(applicationURL, in: root, allowRootItself: false), "Fixture application escaped its root")
        let contents = applicationURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let propertyList: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        return applicationURL
    }
}

private func makeRule(_ root: URL, id: String = "fixture.cache", risk: RiskLevel = .safe, method: CleanupMethod = .recoveryVault, category: ScanCategory = .developerCache) -> CleanupRule {
    CleanupRule(
        id: id, displayName: "Fixture Cache", producedBy: "Fixture Tool", sourceType: .developerTool,
        category: category, approvedRoots: [root.path], risk: risk, regeneratable: true,
        cleanupMethod: method, reason: "Synthetic data can be recreated.", impact: "The synthetic fixture will be recreated.",
        evidence: "Matched a synthetic fixture root.", whatItIs: "Synthetic test data."
    )
}

private func makeItem(_ url: URL, root: URL, rule: CleanupRule) async throws -> CleanableItem {
    let context = ScanContext(
        ruleEngine: try RuleEngine(rules: [rule]), settings: ScanSettings(), homeDirectory: root,
        fileSystemValidator: FileSystemValidator(homeDirectory: root)
    )
    return try await ScannerSupport.makeItem(
        candidate: url, root: root, rule: rule, scannerIdentifier: "fixture.scanner", context: context,
        sourceOverride: ResolvedSource(name: "Fixture Tool", bundleIdentifier: nil, sourceType: .developerTool, evidence: [rule.evidence], confidence: .confirmed)
    )
}

private func run(_ name: String, _ body: () async throws -> Void) async throws {
    try await body()
    print("PASS \(name)")
}

@main
private struct ByteTrailVerification {
    static func main() async {
        do {
            try await run("bundled rule validation and uniqueness") {
                let rules = try RuleLoader().loadBundled()
                try require(rules.count >= 16, "Too few bundled rules")
                try require(Set(rules.map(\.id)).count == rules.count, "Duplicate bundled rule identifier")
                _ = try RuleEngine(rules: rules)
            }

            try await run("invalid rules fail closed") {
                let fixture = try Fixture()
                var missing = makeRule(fixture.root)
                missing.approvedRoots = []
                try requireThrows("Missing root was accepted") { try RuleValidator().validate([missing]) }
                let duplicate = makeRule(fixture.root)
                try requireThrows("Duplicate ID was accepted") { try RuleValidator().validate([duplicate, duplicate]) }
                try requireThrows("Protected cleanup was accepted") {
                    try RuleValidator().validate([makeRule(fixture.root, risk: .protected, method: .moveToTrash)])
                }
                try requireThrows("System root was accepted") {
                    var system = makeRule(fixture.root)
                    system.approvedRoots = ["/System"]
                    try RuleValidator().validate([system])
                }
            }

            try await run("unknown enums fail decoding") {
                let fixture = try Fixture()
                let data = try JSONEncoder().encode([makeRule(fixture.root)])
                let json = String(decoding: data, as: UTF8.self)
                try requireThrows("Unknown risk decoded") {
                    _ = try RuleLoader().decode(data: Data(json.replacingOccurrences(of: "\"safe\"", with: "\"mystery\"").utf8))
                }
                try requireThrows("Unknown category decoded") {
                    _ = try RuleLoader().decode(data: Data(json.replacingOccurrences(of: "\"developer-cache\"", with: "\"junk\"").utf8))
                }
            }

            try await run("risk policy is conservative") {
                let fixture = try Fixture()
                let safe = makeRule(fixture.root)
                let policy = SafetyPolicy()
                try require(policy.finalRisk(rule: safe, confidence: .confirmed, category: .developerCache) == .safe, "Confirmed safe became non-safe")
                try require(policy.finalRisk(rule: safe, confidence: .unknown, category: .developerCache) == .review, "Unknown attribution became safe")
                try require(policy.finalRisk(rule: nil, confidence: .confirmed, category: .unknown) == .protected, "Unknown rule was not protected")
                for category in [ScanCategory.largeFile, .xcodeArchive, .iosBackup, .applicationLeftover] {
                    try require(policy.finalRisk(rule: safe, confidence: .confirmed, category: category) == .review, "Conservative category was not Review")
                }
            }

            try await run("containment rejects traversal and prefix collisions") {
                let fixture = try Fixture()
                let approved = try fixture.directory("approved")
                let containment = PathContainmentValidator()
                try require(containment.isContained(approved.appendingPathComponent("one/../two").standardizedFileURL, in: approved), "Normalized child rejected")
                try require(!containment.isContained(fixture.root.appendingPathComponent("approved-escape/file"), in: approved), "Prefix collision accepted")
            }

            try await run("symbolic-link escape is blocked") {
                let fixture = try Fixture()
                let approved = try fixture.directory("approved")
                let outside = try fixture.directory("outside")
                _ = try fixture.file("outside/secret")
                let link = approved.appendingPathComponent("escape")
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
                try requireThrows("Symbolic-link escape was accepted") {
                    _ = try FileSystemValidator(homeDirectory: fixture.root).validateForScan(link, rule: makeRule(approved), approvedRoot: approved)
                }
                try require(!PathContainmentValidator().isResolvedContained(link.appendingPathComponent("secret"), in: approved), "Nested symbolic-link escape was contained")
            }

            try await run("protected paths and Debug lock") {
                let policy = ProtectedPathPolicy()
                try require(policy.isAlwaysProtected(URL(fileURLWithPath: "/System/Library")), "/System was not protected")
                try require(policy.isAlwaysProtected(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")), "Mail was not protected")
                #if DEBUG
                try require(!DevelopmentSafetyLock.permitsMutation(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/file")), "Debug lock allowed user data")
                #endif
            }

            try await run("changed resource identity fails revalidation") {
                let fixture = try Fixture()
                let approved = try fixture.directory("approved")
                let file = try fixture.file("approved/cache")
                let rule = makeRule(approved)
                var finding = try await makeItem(file, root: approved, rule: rule)
                finding.scanSnapshot.resourceIdentifier = "mismatch"
                try requireThrows("Changed identity was accepted") {
                    _ = try FileSystemValidator(homeDirectory: fixture.root).revalidateForCleanup(finding, rule: rule)
                }
            }

            try await run("hard links are not double-counted") {
                let fixture = try Fixture()
                let tree = try fixture.directory("tree")
                let original = try fixture.file("tree/original", bytes: 512)
                try FileManager.default.linkItem(at: original, to: tree.appendingPathComponent("hard-link"))
                let result = try FileSizeCalculator().calculate(tree)
                try require(result.fileCount == 1 && result.logicalBytes == 512, "Hard link was double-counted")
            }

            try await run("known and unknown provenance") {
                let engine = try RuleEngine()
                let resolver = SourceResolver()
                guard let xcodeRule = engine.rule(identifier: "xcode.derived-data"), let brewRule = engine.rule(identifier: "homebrew.download-cache") else {
                    throw VerificationFailure.failed("Known rules missing")
                }
                let xcode = await resolver.resolve(rule: xcodeRule, itemURL: URL(fileURLWithPath: "/tmp/project"))
                let brew = await resolver.resolve(rule: brewRule, itemURL: URL(fileURLWithPath: "/tmp/Homebrew"))
                try require(xcode.name == "Xcode" && xcode.confidence == .confirmed, "Xcode attribution failed")
                try require(brew.name == "Homebrew" && brew.confidence == .confirmed, "Homebrew attribution failed")
                let fixture = try Fixture()
                var unknownRule = makeRule(fixture.root)
                unknownRule.producedBy = "Unknown source"
                let unknown = await SourceResolver(applicationResolver: ApplicationMetadataResolver(homeDirectory: fixture.root))
                    .resolve(rule: unknownRule, itemURL: fixture.root.appendingPathComponent("raw.vendor.cache"))
                try require(unknown.name == "raw.vendor.cache" && unknown.confidence == .unknown, "Unknown source was fabricated")
            }

            try await run("installed applications require an exact bundle identifier") {
                let fixture = try Fixture()
                let applications = try fixture.directory("Applications")
                let app = try fixture.application("Applications/Fixture.app", bundleIdentifier: "com.example.fixture", name: "Fixture App")
                let resolver = ApplicationMetadataResolver(homeDirectory: fixture.root, applicationRoots: [applications])
                let resolved = await resolver.resolve(bundleIdentifier: "com.example.fixture")
                try require(resolved?.name == "Fixture App", "Installed application name was not resolved")
                try require(resolved?.url.resolvingSymlinksInPath() == app.resolvingSymlinksInPath(), "Installed application URL was not resolved")
                let partial = await resolver.resolve(bundleIdentifier: "com.example.fixtur")
                try require(partial == nil, "Partial bundle identifier was accepted")
            }

            try await run("sandbox cache attribution targets only the cache leaf") {
                let fixture = try Fixture()
                let applications = try fixture.directory("Applications")
                let app = try fixture.application("Applications/Fixture.app", bundleIdentifier: "com.example.fixture", name: "Fixture App")
                let cache = try fixture.directory("Library/Containers/com.example.fixture/Data/Library/Caches")
                _ = try fixture.file("Library/Containers/com.example.fixture/Data/Library/Caches/content.bin", bytes: 64)
                let applicationResolver = ApplicationMetadataResolver(homeDirectory: fixture.root, applicationRoots: [applications])
                let context = ScanContext(
                    ruleEngine: try RuleEngine(homeDirectory: fixture.root), settings: ScanSettings(), homeDirectory: fixture.root,
                    sourceResolver: SourceResolver(applicationResolver: applicationResolver),
                    fileSystemValidator: FileSystemValidator(homeDirectory: fixture.root)
                )
                var match: CleanableItem?
                for await event in CacheScanner().scan(context: context) {
                    guard case let .finding(item) = event else { continue }
                    if URL(fileURLWithPath: item.standardizedPath).resolvingSymlinksInPath() == cache.resolvingSymlinksInPath() { match = item }
                }
                guard let match else { throw VerificationFailure.failed("Sandbox cache finding missing") }
                try require(match.provenance.producedByIdentifier == "com.example.fixture", "Sandbox cache bundle identifier missing")
                try require(match.provenance.sourceApplicationURL?.resolvingSymlinksInPath() == app.resolvingSymlinksInPath(), "Sandbox cache app URL missing")
                try require(URL(fileURLWithPath: match.approvedRoot).resolvingSymlinksInPath() == cache.resolvingSymlinksInPath(), "Container was targeted instead of the cache leaf")
            }

            try await run("large-file scan is recursive and deduplicates nested roots") {
                let fixture = try Fixture()
                let scanRoot = try fixture.directory("ScanRoot")
                let nested = try fixture.directory("ScanRoot/Nested")
                let large = try fixture.file("ScanRoot/Nested/archive.bin", bytes: 2_048)
                _ = try fixture.file("ScanRoot/small.bin", bytes: 128)
                let context = ScanContext(
                    ruleEngine: try RuleEngine(homeDirectory: fixture.root),
                    settings: ScanSettings(largeFileMinimumBytes: 1_024, authorizedFolders: [scanRoot, nested]),
                    homeDirectory: fixture.root,
                    fileSystemValidator: FileSystemValidator(homeDirectory: fixture.root)
                )
                var matches: [CleanableItem] = []
                for await event in LargeFileScanner().scan(context: context) {
                    guard case let .finding(item) = event else { continue }
                    if URL(fileURLWithPath: item.standardizedPath).resolvingSymlinksInPath() == large.resolvingSymlinksInPath() { matches.append(item) }
                }
                try require(matches.count == 1, "Nested roots produced duplicate large-file findings")
                try require(matches[0].riskLevel == .review && !matches[0].selected, "Large file bypassed Review")
                try require(matches[0].embeddedRule?.approvedRoots.count == 1, "Large-file cleanup rule was not embedded")
            }

            try await run("partial scanner failures preserve valid findings") {
                let fixture = try Fixture()
                let cacheRoot = try fixture.directory("Library/Caches")
                _ = try fixture.file("Library/Caches/com.fixture.valid/data")
                let outside = try fixture.directory("outside")
                try FileManager.default.createSymbolicLink(at: cacheRoot.appendingPathComponent("escaped.cache"), withDestinationURL: outside)
                let context = ScanContext(ruleEngine: try RuleEngine(homeDirectory: fixture.root), settings: ScanSettings(showHiddenFiles: true), homeDirectory: fixture.root)
                var findings = 0
                var issues = 0
                for await event in CacheScanner().scan(context: context) {
                    if case .finding = event { findings += 1 }
                    if case .issue = event { issues += 1 }
                }
                try require(findings == 1 && issues == 1, "Partial scan result was not preserved")
            }

            try await run("dry-run changes nothing and records history") {
                let fixture = try Fixture()
                let approved = try fixture.directory("approved")
                let file = try fixture.file("approved/cache", bytes: 64)
                let rule = makeRule(approved)
                let finding = try await makeItem(file, root: approved, rule: rule)
                let history = CleanupHistoryStore(storageURL: fixture.root.appendingPathComponent("state/history.json"))
                let coordinator = CleanupCoordinator(
                    ruleEngine: try RuleEngine(rules: [rule]), validator: FileSystemValidator(homeDirectory: fixture.root), historyStore: history,
                    recoveryStore: RecoveryStore(storageURL: fixture.root.appendingPathComponent("state/recovery.json")),
                    vaultOperation: RecoveryVaultOperation(vaultRoot: fixture.root.appendingPathComponent("vault"))
                )
                let result = await coordinator.clean(items: [finding], dryRun: true)
                try require(result.first?.status == .dryRun, "Dry-run did not report dry-run")
                try require(FileManager.default.fileExists(atPath: file.path), "Dry-run modified its fixture")
                let historyEntries = await history.allEntries()
                try require(historyEntries.count == 1, "Dry-run history missing")
            }

            try await run("Recovery Vault move and restore are temporary-only") {
                let fixture = try Fixture()
                let temporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).standardizedFileURL
                try require(PathContainmentValidator().isContained(fixture.root, in: temporary, allowRootItself: false), "Cleanup fixture escaped temporary root")
                let approved = try fixture.directory("approved")
                let file = try fixture.file("approved/cache", bytes: 128)
                let rule = makeRule(approved)
                let finding = try await makeItem(file, root: approved, rule: rule)
                let recoveryStore = RecoveryStore(storageURL: fixture.root.appendingPathComponent("state/recovery.json"))
                let coordinator = CleanupCoordinator(
                    ruleEngine: try RuleEngine(rules: [rule]), validator: FileSystemValidator(homeDirectory: fixture.root),
                    historyStore: CleanupHistoryStore(storageURL: fixture.root.appendingPathComponent("state/history.json")), recoveryStore: recoveryStore,
                    vaultOperation: RecoveryVaultOperation(vaultRoot: fixture.root.appendingPathComponent("vault"))
                )
                let results = await coordinator.clean(items: [finding], dryRun: false)
                try require(results.first?.status == .movedToRecovery, "Fixture was not moved to Recovery Vault")
                try require(!FileManager.default.fileExists(atPath: file.path), "Fixture source still exists")
                guard let recovery = await recoveryStore.allEntries().first else { throw VerificationFailure.failed("Recovery index missing") }
                try require(PathContainmentValidator().isContained(recovery.recoveryURL, in: fixture.root), "Recovery left fixture root")
                let restoreResult = await coordinator.restore(recovery)
                try require(restoreResult.status == .restored, "Restore failed")
                try require(FileManager.default.fileExists(atPath: file.path), "Restored fixture missing")
            }

            try await run("embedded dynamic cleanup rules remain temporary-only") {
                let fixture = try Fixture()
                let approved = try fixture.directory("authorized")
                let file = try fixture.file("authorized/large.bin", bytes: 256)
                let rule = makeRule(approved, id: "fixture.dynamic.large", risk: .review, method: .moveToTrash, category: .largeFile)
                var finding = try await makeItem(file, root: approved, rule: rule)
                finding.embeddedRule = rule
                let recoveryStore = RecoveryStore(storageURL: fixture.root.appendingPathComponent("state/recovery.json"))
                let coordinator = CleanupCoordinator(
                    ruleEngine: try RuleEngine(rules: []), validator: FileSystemValidator(homeDirectory: fixture.root),
                    historyStore: CleanupHistoryStore(storageURL: fixture.root.appendingPathComponent("state/history.json")),
                    recoveryStore: recoveryStore,
                    vaultOperation: RecoveryVaultOperation(vaultRoot: fixture.root.appendingPathComponent("vault"))
                )
                let results = await coordinator.clean(items: [finding], dryRun: false)
                try require(results.first?.status == .movedToRecovery, "Embedded dynamic rule was not honored")
                guard let recovery = await recoveryStore.allEntries().first else { throw VerificationFailure.failed("Dynamic recovery index missing") }
                try require(PathContainmentValidator().isContained(recovery.recoveryURL, in: fixture.root), "Dynamic cleanup left the fixture root")
            }

            try await run("restore collision does not overwrite") {
                let fixture = try Fixture()
                let original = try fixture.file("approved/original", bytes: 4)
                let recovery = try fixture.file("vault/recovery", bytes: 8)
                try requireThrows("Restore overwrote a collision") {
                    _ = try RestoreOperation().execute(RecoveryEntry(originalURL: original, recoveryURL: recovery, size: 8, ruleIdentifier: "fixture"))
                }
                let originalData = try Data(contentsOf: original)
                let recoveryData = try Data(contentsOf: recovery)
                try require(originalData.count == 4, "Original collision changed")
                try require(recoveryData.count == 8, "Recovery collision changed")
            }

            try await run("per-item cleanup failure does not stop later items") {
                let fixture = try Fixture()
                let approved = try fixture.directory("approved")
                let firstURL = try fixture.file("approved/first")
                let secondURL = try fixture.file("approved/second")
                let rule = makeRule(approved)
                var first = try await makeItem(firstURL, root: approved, rule: rule)
                first.scanSnapshot.resourceIdentifier = "changed"
                let second = try await makeItem(secondURL, root: approved, rule: rule)
                let coordinator = CleanupCoordinator(
                    ruleEngine: try RuleEngine(rules: [rule]), validator: FileSystemValidator(homeDirectory: fixture.root),
                    historyStore: CleanupHistoryStore(storageURL: fixture.root.appendingPathComponent("state/history.json")),
                    recoveryStore: RecoveryStore(storageURL: fixture.root.appendingPathComponent("state/recovery.json")),
                    vaultOperation: RecoveryVaultOperation(vaultRoot: fixture.root.appendingPathComponent("vault"))
                )
                let results = await coordinator.clean(items: [first, second], dryRun: false)
                try require(results.map(\.status) == [.failed, .movedToRecovery], "Partial cleanup status incorrect")
                try require(FileManager.default.fileExists(atPath: firstURL.path), "Failed item was modified")
                try require(!FileManager.default.fileExists(atPath: secondURL.path), "Later valid item was not processed")
            }

            try await run("Debug Trash boundary is never crossed") {
                #if DEBUG
                let fixture = try Fixture()
                let file = try fixture.file("trash-fixture")
                try requireThrows("Debug Trash operation crossed the boundary") { _ = try TrashCleanupOperation().execute(source: file) }
                try require(FileManager.default.fileExists(atPath: file.path), "Debug Trash test moved its fixture")
                #endif
            }

            print("VERIFICATION COMPLETE: 20 checks passed; all mutation fixtures were synthetic and under the system temporary directory.")
        } catch {
            fputs("VERIFICATION FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
