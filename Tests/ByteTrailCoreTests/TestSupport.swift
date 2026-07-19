import Foundation
import XCTest
@testable import ByteTrailCore

final class TemporaryFixture {
    let root: URL

    init(function: StaticString = #function) throws {
        let systemTemporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).standardizedFileURL
        root = systemTemporary.appendingPathComponent("ByteTrailTests-\(UUID().uuidString)", isDirectory: true).standardizedFileURL
        print("ByteTrail temporary fixture [\(function)]: \(root.path)")
        guard PathContainmentValidator().isContained(root, in: systemTemporary, allowRootItself: false) else {
            XCTFail("Refusing fixture outside the system temporary directory: \(root.path)")
            throw FileValidationError.developmentSafetyLock
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        guard DevelopmentSafetyLock.permitsMutation(at: root) else {
            print("Refusing fixture cleanup outside temporary directory: \(root.path)")
            return
        }
        try? FileManager.default.removeItem(at: root)
    }

    func directory(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        guard PathContainmentValidator().isContained(url, in: root, allowRootItself: false) else { throw FileValidationError.pathTraversal }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func file(_ path: String, bytes: Int = 32, modified: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(path)
        guard PathContainmentValidator().isContained(url, in: root, allowRootItself: false) else { throw FileValidationError.pathTraversal }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x43, count: bytes).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    func application(_ path: String, bundleIdentifier: String, name: String) throws -> URL {
        let applicationURL = root.appendingPathComponent(path, isDirectory: true).standardizedFileURL
        guard PathContainmentValidator().isContained(applicationURL, in: root, allowRootItself: false) else {
            throw FileValidationError.pathTraversal
        }
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

func fixtureRule(
    id: String = "fixture.cache",
    root: URL,
    risk: RiskLevel = .safe,
    method: CleanupMethod = .recoveryVault,
    category: ScanCategory = .developerCache
) -> CleanupRule {
    CleanupRule(
        id: id,
        displayName: "Fixture Cache",
        producedBy: "Fixture Tool",
        sourceType: .developerTool,
        category: category,
        approvedRoots: [root.path],
        risk: risk,
        regeneratable: true,
        cleanupMethod: method,
        reason: "Synthetic data can be recreated.",
        impact: "The synthetic fixture will be recreated.",
        evidence: "Matched the synthetic fixture root.",
        whatItIs: "Synthetic test data."
    )
}

func fixtureItem(url: URL, root: URL, rule: CleanupRule) async throws -> CleanableItem {
    let engine = try RuleEngine(rules: [rule])
    let context = ScanContext(
        ruleEngine: engine,
        settings: ScanSettings(),
        homeDirectory: root,
        fileSystemValidator: FileSystemValidator(homeDirectory: root)
    )
    let source = ResolvedSource(name: "Fixture Tool", bundleIdentifier: nil, sourceType: .developerTool, evidence: [rule.evidence], confidence: .confirmed)
    return try await ScannerSupport.makeItem(candidate: url, root: root, rule: rule, scannerIdentifier: "fixture.scanner", context: context, sourceOverride: source)
}
