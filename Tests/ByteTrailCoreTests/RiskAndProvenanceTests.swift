import Foundation
import XCTest
@testable import ByteTrailCore

final class RiskAndProvenanceTests: XCTestCase {
    func testRiskPolicy() throws {
        let fixture = try TemporaryFixture()
        let safe = fixtureRule(root: fixture.root)
        XCTAssertEqual(SafetyPolicy().finalRisk(rule: safe, confidence: .confirmed, category: .developerCache), .safe)
        XCTAssertEqual(SafetyPolicy().finalRisk(rule: safe, confidence: .unknown, category: .developerCache), .review)
        XCTAssertEqual(SafetyPolicy().finalRisk(rule: nil, confidence: .confirmed, category: .unknown), .protected)
        XCTAssertEqual(SafetyPolicy().finalRisk(rule: safe, confidence: .confirmed, category: .largeFile), .review)
    }

    func testKnownXcodeAndHomebrewProvenance() async throws {
        let rules = try RuleLoader().loadBundled()
        let engine = try RuleEngine(rules: rules)
        let resolver = SourceResolver()
        let xcode = try XCTUnwrap(engine.rule(identifier: "xcode.derived-data"))
        let xcodeResult = await resolver.resolve(rule: xcode, itemURL: URL(fileURLWithPath: "/tmp/DerivedData/project"))
        XCTAssertEqual(xcodeResult.name, "Xcode")
        XCTAssertEqual(xcodeResult.confidence, .confirmed)
        let brew = try XCTUnwrap(engine.rule(identifier: "homebrew.download-cache"))
        let brewResult = await resolver.resolve(rule: brew, itemURL: URL(fileURLWithPath: "/tmp/Homebrew"))
        XCTAssertEqual(brewResult.name, "Homebrew")
        XCTAssertEqual(brewResult.confidence, .confirmed)
    }

    func testUnknownSourceShowsRawNameWithoutInventingOriginalLocation() async throws {
        let fixture = try TemporaryFixture()
        var rule = fixtureRule(root: fixture.root)
        rule.producedBy = "Unknown source"
        rule.producedByIdentifier = nil
        let result = await SourceResolver(applicationResolver: ApplicationMetadataResolver(homeDirectory: fixture.root))
            .resolve(rule: rule, itemURL: fixture.root.appendingPathComponent("unresolved.vendor.cache"))
        XCTAssertEqual(result.name, "unresolved.vendor.cache")
        XCTAssertEqual(result.confidence, .unknown)
    }

    func testDefaultSelectionRules() {
        let policy = SafetyPolicy()
        XCTAssertTrue(policy.selectedByDefault(risk: .safe, confidence: .confirmed))
        XCTAssertFalse(policy.selectedByDefault(risk: .review, confidence: .confirmed))
        XCTAssertFalse(policy.selectedByDefault(risk: .safe, confidence: .unknown))
    }
}
