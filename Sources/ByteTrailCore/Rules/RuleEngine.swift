import Foundation

public struct CleanupRule: Codable, Hashable, Sendable {
    public var id: String
    public var version: Int
    public var displayName: String
    public var producedBy: String
    public var producedByIdentifier: String?
    public var sourceType: SourceType
    public var category: ScanCategory
    public var approvedRoots: [String]
    public var risk: RiskLevel
    public var regeneratable: Bool
    public var minimumAgeDays: Int
    public var cleanupMethod: CleanupMethod
    public var reason: String
    public var impact: String
    public var evidence: String
    public var whatItIs: String
    public var allowSymbolicLinks: Bool

    public init(
        id: String,
        version: Int = 1,
        displayName: String,
        producedBy: String,
        producedByIdentifier: String? = nil,
        sourceType: SourceType,
        category: ScanCategory,
        approvedRoots: [String],
        risk: RiskLevel,
        regeneratable: Bool,
        minimumAgeDays: Int = 0,
        cleanupMethod: CleanupMethod,
        reason: String,
        impact: String,
        evidence: String,
        whatItIs: String,
        allowSymbolicLinks: Bool = false
    ) {
        self.id = id
        self.version = version
        self.displayName = displayName
        self.producedBy = producedBy
        self.producedByIdentifier = producedByIdentifier
        self.sourceType = sourceType
        self.category = category
        self.approvedRoots = approvedRoots
        self.risk = risk
        self.regeneratable = regeneratable
        self.minimumAgeDays = minimumAgeDays
        self.cleanupMethod = cleanupMethod
        self.reason = reason
        self.impact = impact
        self.evidence = evidence
        self.whatItIs = whatItIs
        self.allowSymbolicLinks = allowSymbolicLinks
    }

    public func expandedRoots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        approvedRoots.compactMap { raw in
            if raw == "~" { return homeDirectory.standardizedFileURL }
            if raw.hasPrefix("~/") {
                return homeDirectory.appendingPathComponent(String(raw.dropFirst(2)), isDirectory: true).standardizedFileURL
            }
            guard raw.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        }
    }
}

public enum RuleValidationError: Error, Equatable, LocalizedError {
    case emptyIdentifier
    case invalidVersion(String)
    case duplicateIdentifier(String)
    case missingApprovedRoot(String)
    case invalidApprovedRoot(rule: String, root: String)
    case protectedApprovedRoot(rule: String, root: String)
    case unsafeRiskCombination(String)
    case missingExplanation(String)

    public var errorDescription: String? {
        switch self {
        case .emptyIdentifier: return "A rule identifier is empty."
        case let .invalidVersion(id): return "Rule \(id) has an invalid version."
        case let .duplicateIdentifier(id): return "Rule identifier \(id) is duplicated."
        case let .missingApprovedRoot(id): return "Rule \(id) has no approved root."
        case let .invalidApprovedRoot(rule, root): return "Rule \(rule) has invalid root \(root)."
        case let .protectedApprovedRoot(rule, root): return "Rule \(rule) attempts to approve protected root \(root)."
        case let .unsafeRiskCombination(id): return "Rule \(id) has an unsafe risk and cleanup combination."
        case let .missingExplanation(id): return "Rule \(id) is missing cleanup evidence or impact."
        }
    }
}

public struct RuleValidator: Sendable {
    public init() {}

    public func validate(_ rules: [CleanupRule], homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        var identifiers = Set<String>()
        let applicationPolicy = ApplicationPathPolicy(homeDirectory: homeDirectory)
        for rule in rules {
            guard !rule.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RuleValidationError.emptyIdentifier
            }
            guard rule.version > 0 else { throw RuleValidationError.invalidVersion(rule.id) }
            guard identifiers.insert(rule.id).inserted else {
                throw RuleValidationError.duplicateIdentifier(rule.id)
            }
            guard !rule.approvedRoots.isEmpty else {
                throw RuleValidationError.missingApprovedRoot(rule.id)
            }
            guard !rule.reason.isEmpty, !rule.impact.isEmpty, !rule.evidence.isEmpty, !rule.whatItIs.isEmpty else {
                throw RuleValidationError.missingExplanation(rule.id)
            }
            if rule.risk == .protected && rule.cleanupMethod != .analysisOnly {
                throw RuleValidationError.unsafeRiskCombination(rule.id)
            }
            if rule.category == .applicationBundle && rule.approvedRoots.count != 1 {
                throw RuleValidationError.invalidApprovedRoot(rule: rule.id, root: rule.approvedRoots.joined(separator: ", "))
            }
            for (index, rawRoot) in rule.approvedRoots.enumerated() {
                guard index < rule.expandedRoots(homeDirectory: homeDirectory).count,
                      rawRoot == "~" || rawRoot.hasPrefix("~/") || rawRoot.hasPrefix("/") else {
                    throw RuleValidationError.invalidApprovedRoot(rule: rule.id, root: rawRoot)
                }
                let root = rule.expandedRoots(homeDirectory: homeDirectory)[index]
                let exactApplicationBundle = rule.category == .applicationBundle
                    && applicationPolicy.isRecognizedApplicationBundle(root)
                if rule.category == .applicationBundle && !exactApplicationBundle {
                    throw RuleValidationError.invalidApprovedRoot(rule: rule.id, root: rawRoot)
                }
                if applicationPolicy.isSystemApplication(root)
                    && (rule.risk != .protected || rule.cleanupMethod != .analysisOnly) {
                    throw RuleValidationError.unsafeRiskCombination(rule.id)
                }
                if ProtectedPathPolicy(homeDirectory: homeDirectory).isAlwaysProtected(root) && !exactApplicationBundle {
                    throw RuleValidationError.protectedApprovedRoot(rule: rule.id, root: rawRoot)
                }
            }
        }
    }
}

public enum RuleLoaderError: Error, LocalizedError {
    case missingResource
    case invalidRules(String)

    public var errorDescription: String? {
        switch self {
        case .missingResource: return "Bundled cleanup rules are missing."
        case let .invalidRules(message): return "Bundled cleanup rules are invalid: \(message)"
        }
    }
}

public struct RuleLoader: Sendable {
    private let decoder: JSONDecoder

    public init() { decoder = JSONDecoder() }

    public func decode(data: Data, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [CleanupRule] {
        do {
            let rules = try decoder.decode([CleanupRule].self, from: data)
            try RuleValidator().validate(rules, homeDirectory: homeDirectory)
            return rules
        } catch {
            throw RuleLoaderError.invalidRules(error.localizedDescription)
        }
    }

    public func loadBundled(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [CleanupRule] {
        if let appResource = Bundle.main.url(forResource: "CleanupRules", withExtension: "json") {
            return try decode(data: Data(contentsOf: appResource), homeDirectory: homeDirectory)
        }
        #if SWIFT_PACKAGE
        let resourceBundle = Bundle.module
        #else
        let resourceBundle = Bundle(for: ByteTrailBundleToken.self)
        #endif
        guard let url = resourceBundle.url(forResource: "CleanupRules", withExtension: "json") else {
            throw RuleLoaderError.missingResource
        }
        return try decode(data: Data(contentsOf: url), homeDirectory: homeDirectory)
    }
}

private final class ByteTrailBundleToken {}

public struct RuleEngine: Sendable {
    private let rulesByID: [String: CleanupRule]

    public init(rules: [CleanupRule], homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        try RuleValidator().validate(rules, homeDirectory: homeDirectory)
        rulesByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
    }

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        try self.init(rules: RuleLoader().loadBundled(homeDirectory: homeDirectory), homeDirectory: homeDirectory)
    }

    public func rule(identifier: String) -> CleanupRule? { rulesByID[identifier] }
    public var rules: [CleanupRule] { rulesByID.values.sorted { $0.id < $1.id } }
}
