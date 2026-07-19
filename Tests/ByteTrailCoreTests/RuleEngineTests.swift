import Foundation
import XCTest
@testable import ByteTrailCore

final class RuleEngineTests: XCTestCase {
    func testBundledRulesLoadAndIdentifiersAreUnique() throws {
        let rules = try RuleLoader().loadBundled()
        XCTAssertGreaterThanOrEqual(rules.count, 16)
        XCTAssertEqual(Set(rules.map(\.id)).count, rules.count)
        XCTAssertNoThrow(try RuleEngine(rules: rules))
    }

    func testMissingApprovedRootRejected() throws {
        let fixture = try TemporaryFixture()
        var rule = fixtureRule(root: fixture.root)
        rule.approvedRoots = []
        XCTAssertThrowsError(try RuleValidator().validate([rule])) { error in
            XCTAssertEqual(error as? RuleValidationError, .missingApprovedRoot(rule.id))
        }
    }

    func testDuplicateIdentifierRejected() throws {
        let fixture = try TemporaryFixture()
        let rule = fixtureRule(root: fixture.root)
        XCTAssertThrowsError(try RuleValidator().validate([rule, rule]))
    }

    func testUnknownRiskAndCategoryFailDecodingClosed() throws {
        let fixture = try TemporaryFixture()
        let valid = fixtureRule(root: fixture.root)
        let data = try JSONEncoder().encode([valid])
        var json = String(decoding: data, as: UTF8.self)
        json = json.replacingOccurrences(of: "\"safe\"", with: "\"mystery\"")
        XCTAssertThrowsError(try RuleLoader().decode(data: Data(json.utf8)))

        let categoryData = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"developer-cache\"", with: "\"arbitrary-junk\"")
        XCTAssertThrowsError(try RuleLoader().decode(data: Data(categoryData.utf8)))
    }

    func testProtectedRuleCannotDeclareCleanup() throws {
        let fixture = try TemporaryFixture()
        let rule = fixtureRule(root: fixture.root, risk: .protected, method: .moveToTrash)
        XCTAssertThrowsError(try RuleValidator().validate([rule]))
    }

    func testSystemRootCannotBeApproved() {
        let rule = CleanupRule(id: "bad", displayName: "Bad", producedBy: "Bad", sourceType: .unknown, category: .unknown, approvedRoots: ["/System"], risk: .review, regeneratable: false, cleanupMethod: .analysisOnly, reason: "No", impact: "No", evidence: "No", whatItIs: "No")
        XCTAssertThrowsError(try RuleValidator().validate([rule]))
    }
}
