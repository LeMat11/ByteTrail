import Foundation

public struct ResolvedSource: Sendable, Equatable {
    public var name: String
    public var bundleIdentifier: String?
    public var sourceType: SourceType
    public var evidence: [String]
    public var confidence: AttributionConfidence
    public var applicationURL: URL?

    public init(name: String, bundleIdentifier: String?, sourceType: SourceType, evidence: [String], confidence: AttributionConfidence, applicationURL: URL? = nil) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.sourceType = sourceType
        self.evidence = evidence
        self.confidence = confidence
        self.applicationURL = applicationURL
    }
}

public struct InstalledApplication: Sendable, Equatable {
    public var bundleIdentifier: String
    public var name: String
    public var url: URL
    public var version: String?
    public var buildNumber: String?

    public init(bundleIdentifier: String, name: String, url: URL, version: String? = nil, buildNumber: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.url = url.standardizedFileURL
        self.version = version
        self.buildNumber = buildNumber
    }
}

public actor ApplicationMetadataResolver {
    private var applicationsByIdentifier: [String: InstalledApplication]?
    private var applicationInventory: [InstalledApplication]?
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let applicationRoots: [URL]?

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationRoots: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.applicationRoots = applicationRoots?.map(\.standardizedFileURL)
    }

    public func resolve(bundleIdentifier: String) -> InstalledApplication? {
        prepareInventoryIfNeeded()
        return applicationsByIdentifier?[bundleIdentifier]
    }

    public func allApplications() -> [InstalledApplication] {
        prepareInventoryIfNeeded()
        return applicationInventory ?? []
    }

    private func prepareInventoryIfNeeded() {
        guard applicationInventory == nil else { return }
        let inventory = buildInventory().sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            return nameOrder == .orderedSame ? $0.url.path < $1.url.path : nameOrder == .orderedAscending
        }
        var index: [String: InstalledApplication] = [:]
        for application in inventory {
            guard let existing = index[application.bundleIdentifier] else {
                index[application.bundleIdentifier] = application
                continue
            }
            if priority(of: application.url) > priority(of: existing.url) {
                index[application.bundleIdentifier] = application
            }
        }
        applicationInventory = inventory
        applicationsByIdentifier = index
    }

    private func buildInventory() -> [InstalledApplication] {
        var result: [InstalledApplication] = []
        let roots = applicationRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if url.pathExtension.lowercased() != "app" { continue }
                enumerator.skipDescendants()
                guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                result.append(InstalledApplication(
                    bundleIdentifier: identifier,
                    name: name,
                    url: url,
                    version: version,
                    buildNumber: buildNumber
                ))
            }
        }
        return result
    }

    private func priority(of url: URL) -> Int {
        let containment = PathContainmentValidator()
        let userApplications = homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        if containment.isContained(url, in: userApplications, allowRootItself: false) { return 3 }
        if containment.isContained(url, in: URL(fileURLWithPath: "/Applications", isDirectory: true), allowRootItself: false) { return 2 }
        if containment.isContained(url, in: URL(fileURLWithPath: "/System/Applications", isDirectory: true), allowRootItself: false) { return 1 }
        return 0
    }
}

public actor SourceResolver {
    private let applicationResolver: ApplicationMetadataResolver

    public init(applicationResolver: ApplicationMetadataResolver = ApplicationMetadataResolver()) {
        self.applicationResolver = applicationResolver
    }

    public func resolve(rule: CleanupRule, itemURL: URL) async -> ResolvedSource {
        if rule.producedBy != "Unknown source" {
            return ResolvedSource(
                name: rule.producedBy,
                bundleIdentifier: rule.producedByIdentifier,
                sourceType: rule.sourceType,
                evidence: [rule.evidence],
                confidence: rule.producedByIdentifier == nil ? .high : .confirmed
            )
        }

        let candidateIdentifier = itemURL.lastPathComponent
        if candidateIdentifier.contains("."), let application = await applicationResolver.resolve(bundleIdentifier: candidateIdentifier) {
            let sourceType: SourceType = ApplicationPathPolicy().isSystemApplication(application.url) ? .systemComponent : .application
            return ResolvedSource(
                name: application.name,
                bundleIdentifier: candidateIdentifier,
                sourceType: sourceType,
                evidence: [rule.evidence, "Bundle identifier resolved to an installed application."],
                confidence: .confirmed,
                applicationURL: application.url
            )
        }

        return ResolvedSource(
            name: candidateIdentifier.isEmpty ? "Unknown source" : candidateIdentifier,
            bundleIdentifier: nil,
            sourceType: rule.sourceType,
            evidence: [rule.evidence, "No installed application identity could be resolved; the directory name is shown verbatim."],
            confidence: .unknown
        )
    }

    public func resolve(bundleIdentifier: String, rule: CleanupRule) async -> ResolvedSource {
        if let application = await applicationResolver.resolve(bundleIdentifier: bundleIdentifier) {
            let sourceType: SourceType = ApplicationPathPolicy().isSystemApplication(application.url) ? .systemComponent : .application
            return ResolvedSource(
                name: application.name,
                bundleIdentifier: bundleIdentifier,
                sourceType: sourceType,
                evidence: [rule.evidence, "Bundle identifier resolved to an installed application."],
                confidence: .confirmed,
                applicationURL: application.url
            )
        }
        return ResolvedSource(
            name: bundleIdentifier,
            bundleIdentifier: nil,
            sourceType: .application,
            evidence: [rule.evidence, "No installed application identity could be resolved; the identifier is shown verbatim."],
            confidence: .unknown
        )
    }
}
