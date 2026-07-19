import Foundation

public struct ScanContext: Sendable {
    public var ruleEngine: RuleEngine
    public var settings: ScanSettings
    public var homeDirectory: URL
    public var sourceResolver: SourceResolver
    public var fileSystemValidator: FileSystemValidator
    public var fileSizeCalculator: FileSizeCalculator

    public init(
        ruleEngine: RuleEngine,
        settings: ScanSettings,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        sourceResolver: SourceResolver? = nil,
        fileSystemValidator: FileSystemValidator? = nil,
        fileSizeCalculator: FileSizeCalculator = FileSizeCalculator()
    ) {
        self.ruleEngine = ruleEngine
        self.settings = settings
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.sourceResolver = sourceResolver ?? SourceResolver(applicationResolver: ApplicationMetadataResolver(homeDirectory: homeDirectory))
        self.fileSystemValidator = fileSystemValidator ?? FileSystemValidator(homeDirectory: homeDirectory)
        self.fileSizeCalculator = fileSizeCalculator
    }
}

public enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case finding(CleanableItem)
    case issue(ScanIssue)
    case finished(scannerIdentifier: String)
}

public protocol ScannerProtocol: Sendable {
    var identifier: String { get }
    var displayName: String { get }
    func scan(context: ScanContext) -> AsyncStream<ScanEvent>
}

public enum ScannerSupport {
    public static func expandedURL(_ raw: String, homeDirectory: URL) -> URL? {
        if raw == "~" { return homeDirectory.standardizedFileURL }
        if raw.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(raw.dropFirst(2)), isDirectory: true).standardizedFileURL
        }
        guard raw.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
    }

    public static func children(of root: URL, showHidden: Bool, fileManager: FileManager = .default) throws -> [URL] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
        if !showHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: options
        ) else { throw CocoaError(.fileReadNoPermission) }
        return enumerator.compactMap { $0 as? URL }
    }

    public static func issue(scanner: String, root: URL, error: Error) -> ScanIssue {
        let nsError = error as NSError
        let permission = nsError.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileReadNoSuchFileError].contains(nsError.code)
            ? PermissionStatus.denied : PermissionStatus.unavailable
        return ScanIssue(scannerIdentifier: scanner, path: root.path, message: error.localizedDescription, permissionStatus: permission)
    }

    public static func makeItem(
        candidate: URL,
        root: URL,
        rule: CleanupRule,
        scannerIdentifier: String,
        context: ScanContext,
        sourceOverride: ResolvedSource? = nil,
        riskOverride: RiskLevel? = nil,
        embeddedRule: CleanupRule? = nil
    ) async throws -> CleanableItem {
        let metadata = try context.fileSystemValidator.validateForScan(candidate, rule: rule, approvedRoot: root)
        let size = try context.fileSizeCalculator.calculate(candidate)
        let source: ResolvedSource
        if let sourceOverride {
            source = sourceOverride
        } else {
            source = await context.sourceResolver.resolve(rule: rule, itemURL: candidate)
        }
        let declaredRisk = riskOverride ?? rule.risk
        let finalRisk = SafetyPolicy().finalRisk(rule: CleanupRule(
            id: rule.id,
            version: rule.version,
            displayName: rule.displayName,
            producedBy: rule.producedBy,
            producedByIdentifier: rule.producedByIdentifier,
            sourceType: rule.sourceType,
            category: rule.category,
            approvedRoots: rule.approvedRoots,
            risk: declaredRisk,
            regeneratable: rule.regeneratable,
            minimumAgeDays: rule.minimumAgeDays,
            cleanupMethod: rule.cleanupMethod,
            reason: rule.reason,
            impact: rule.impact,
            evidence: rule.evidence,
            whatItIs: rule.whatItIs,
            allowSymbolicLinks: rule.allowSymbolicLinks
        ), confidence: source.confidence, category: rule.category)
        let snapshot = context.fileSystemValidator.makeSnapshot(
            metadata: metadata,
            rule: rule,
            approvedRoot: root,
            logicalSize: size.logicalBytes,
            allocatedSize: size.allocatedBytes
        )
        let provenance = SourceProvenance(
            producedByName: source.name,
            producedByIdentifier: source.bundleIdentifier,
            sourceType: source.sourceType,
            currentURL: candidate,
            originalURL: nil,
            sourceApplicationURL: source.applicationURL,
            detectionReason: rule.evidence,
            evidence: source.evidence,
            confidence: source.confidence
        )
        return CleanableItem(
            displayName: candidate.lastPathComponent,
            provenance: provenance,
            sourceIconReference: source.bundleIdentifier,
            standardizedPath: candidate.standardizedFileURL.path,
            category: rule.category,
            size: size.logicalBytes,
            allocatedSize: size.allocatedBytes,
            fileCount: size.fileCount,
            modifiedDate: metadata.modificationDate,
            whatItIs: rule.whatItIs,
            cleanupReason: rule.reason,
            expectedImpact: rule.impact,
            regeneratable: rule.regeneratable,
            riskLevel: finalRisk,
            permissionStatus: .accessible,
            selected: SafetyPolicy().selectedByDefault(risk: finalRisk, confidence: source.confidence),
            scannerIdentifier: scannerIdentifier,
            matchedRuleIdentifier: rule.id,
            approvedRoot: root.path,
            scanSnapshot: FileSnapshot(
                standardizedPath: snapshot.standardizedPath,
                resourceIdentifier: snapshot.resourceIdentifier,
                fileType: snapshot.fileType,
                modificationDate: snapshot.modificationDate,
                logicalSize: snapshot.logicalSize,
                allocatedSize: snapshot.allocatedSize,
                isSymbolicLink: snapshot.isSymbolicLink,
                isAliasFile: snapshot.isAliasFile,
                volumeIdentifier: snapshot.volumeIdentifier,
                approvedRoot: snapshot.approvedRoot,
                matchedRuleIdentifier: snapshot.matchedRuleIdentifier,
                riskLevel: finalRisk
            ),
            cleanupMethod: rule.cleanupMethod,
            recoveryAvailable: rule.cleanupMethod == .moveToTrash || rule.cleanupMethod == .recoveryVault,
            embeddedRule: embeddedRule
        )
    }

    public static func isExcluded(_ url: URL, source: String, settings: ScanSettings) -> Bool {
        let path = url.standardizedFileURL.path
        if settings.excludedSources.contains(source) { return true }
        return settings.excludedPaths.contains { excluded in
            PathContainmentValidator().isContained(url, in: URL(fileURLWithPath: excluded, isDirectory: true))
                || path == URL(fileURLWithPath: excluded).standardizedFileURL.path
        }
    }
}
