import Foundation

public struct PathContainmentValidator: Sendable {
    public init() {}

    public func standardized(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    public func isContained(_ candidate: URL, in root: URL, allowRootItself: Bool = true) -> Bool {
        let candidateComponents = standardized(candidate).pathComponents
        let rootComponents = standardized(root).pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        guard Array(candidateComponents.prefix(rootComponents.count)) == rootComponents else { return false }
        return allowRootItself || candidateComponents.count > rootComponents.count
    }

    public func isResolvedContained(_ candidate: URL, in root: URL, allowRootItself: Bool = true) -> Bool {
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        return isContained(resolvedCandidate, in: resolvedRoot, allowRootItself: allowRootItself)
    }
}

public struct ProtectedPathPolicy: Sendable {
    public let homeDirectory: URL
    private let containment = PathContainmentValidator()

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public var protectedRoots: [URL] {
        let absolute = [
            "/System", "/bin", "/sbin", "/usr", "/private/etc", "/private/var/db",
            "/Library/Keychains", "/Library/Apple", "/Applications"
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let homeRelative = [
            "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Safari",
            "Library/Cookies", "Library/Accounts", "Library/Calendars", "Library/CloudStorage",
            "Library/Containers/com.apple.mail", "Library/Containers/com.apple.MobileSMS",
            "Library/Application Support/AddressBook", "Library/Application Support/CloudDocs",
            "Pictures", "Documents", "Desktop", "Movies", "Music", "Applications"
        ].map { homeDirectory.appendingPathComponent($0, isDirectory: true) }
        return absolute + homeRelative
    }

    public func isAlwaysProtected(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL
        if candidate.path == "/" || candidate == homeDirectory || candidate.path == "/Library" || candidate.path == "/Users" {
            return true
        }
        return protectedRoots.contains { containment.isContained(candidate, in: $0) }
    }

    public func intersectsProtectedDescendant(_ url: URL) -> Bool {
        protectedRoots.contains { containment.isContained($0, in: url) }
    }
}

public enum FileValidationError: Error, Equatable, LocalizedError {
    case doesNotExist
    case pathTraversal
    case outsideApprovedRoot
    case protectedPath
    case containsProtectedDescendant
    case symbolicLink
    case symbolicLinkEscape
    case aliasFile
    case unsupportedFileType
    case changedSinceScan(String)
    case ruleMismatch
    case riskMismatch
    case permissionDenied
    case developmentSafetyLock

    public var errorDescription: String? {
        switch self {
        case .doesNotExist: return "The item no longer exists."
        case .pathTraversal: return "The path is not in canonical form."
        case .outsideApprovedRoot: return "The item is outside the rule’s approved root."
        case .protectedPath: return "The item is protected and cannot be cleaned."
        case .containsProtectedDescendant: return "The target contains a protected location."
        case .symbolicLink: return "Symbolic links are not accepted by this rule."
        case .symbolicLinkEscape: return "Resolving symbolic links leaves the approved root."
        case .aliasFile: return "Finder aliases are analysis-only."
        case .unsupportedFileType: return "The target’s file type is unsupported."
        case let .changedSinceScan(reason): return "The item changed since scanning: \(reason)."
        case .ruleMismatch: return "The matched rule changed since scanning."
        case .riskMismatch: return "The risk classification changed since scanning."
        case .permissionDenied: return "The item is not writable with current permissions."
        case .developmentSafetyLock: return "Debug cleanup is restricted to a validated temporary fixture directory."
        }
    }
}

public struct FileSystemMetadata: Sendable, Equatable {
    public var standardizedURL: URL
    public var resourceIdentifier: String?
    public var fileType: String
    public var modificationDate: Date?
    public var logicalSize: Int64
    public var allocatedSize: Int64
    public var isSymbolicLink: Bool
    public var isAliasFile: Bool
    public var volumeIdentifier: String?
}

public struct FileSystemValidator: @unchecked Sendable {
    private let fileManager: FileManager
    private let containment = PathContainmentValidator()
    private let protectedPolicy: ProtectedPathPolicy

    public init(fileManager: FileManager = .default, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.fileManager = fileManager
        self.protectedPolicy = ProtectedPathPolicy(homeDirectory: homeDirectory)
    }

    public func metadata(for url: URL) throws -> FileSystemMetadata {
        let standardized = url.standardizedFileURL
        guard standardized.path == url.standardizedFileURL.path else { throw FileValidationError.pathTraversal }
        guard fileManager.fileExists(atPath: standardized.path) else { throw FileValidationError.doesNotExist }
        let keys: Set<URLResourceKey> = [
            .fileResourceIdentifierKey, .fileSizeKey, .fileAllocatedSizeKey,
            .totalFileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey,
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey,
            .volumeIdentifierKey, .isWritableKey
        ]
        let values: URLResourceValues
        do { values = try standardized.resourceValues(forKeys: keys) }
        catch { throw FileValidationError.permissionDenied }

        let fileType: String
        if values.isRegularFile == true { fileType = "regular" }
        else if values.isDirectory == true { fileType = "directory" }
        else if values.isSymbolicLink == true { fileType = "symbolic-link" }
        else { throw FileValidationError.unsupportedFileType }

        return FileSystemMetadata(
            standardizedURL: standardized,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
            fileType: fileType,
            modificationDate: values.contentModificationDate,
            logicalSize: Int64(values.totalFileSize ?? values.fileSize ?? 0),
            allocatedSize: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.totalFileSize ?? values.fileSize ?? 0),
            isSymbolicLink: values.isSymbolicLink == true,
            isAliasFile: values.isAliasFile == true,
            volumeIdentifier: values.volumeIdentifier.map { String(describing: $0) }
        )
    }

    public func validateForScan(_ url: URL, rule: CleanupRule, approvedRoot: URL) throws -> FileSystemMetadata {
        let standardized = url.standardizedFileURL
        guard containment.isContained(standardized, in: approvedRoot) else {
            throw FileValidationError.outsideApprovedRoot
        }
        if protectedPolicy.isAlwaysProtected(standardized) { throw FileValidationError.protectedPath }
        if protectedPolicy.intersectsProtectedDescendant(standardized) { throw FileValidationError.containsProtectedDescendant }
        let metadata = try metadata(for: standardized)
        if metadata.isAliasFile { throw FileValidationError.aliasFile }
        if metadata.isSymbolicLink && !rule.allowSymbolicLinks { throw FileValidationError.symbolicLink }
        guard containment.isResolvedContained(standardized, in: approvedRoot) else {
            throw FileValidationError.symbolicLinkEscape
        }
        return metadata
    }

    public func validateForAnalysis(_ url: URL, authorizedRoot: URL) throws -> FileSystemMetadata {
        let standardized = url.standardizedFileURL
        guard containment.isContained(standardized, in: authorizedRoot) else {
            throw FileValidationError.outsideApprovedRoot
        }
        let metadata = try metadata(for: standardized)
        if metadata.isAliasFile { throw FileValidationError.aliasFile }
        if metadata.isSymbolicLink { throw FileValidationError.symbolicLink }
        guard containment.isResolvedContained(standardized, in: authorizedRoot) else {
            throw FileValidationError.symbolicLinkEscape
        }
        return metadata
    }

    public func makeSnapshot(metadata: FileSystemMetadata, rule: CleanupRule, approvedRoot: URL, logicalSize: Int64, allocatedSize: Int64) -> FileSnapshot {
        FileSnapshot(
            standardizedPath: metadata.standardizedURL.path,
            resourceIdentifier: metadata.resourceIdentifier,
            fileType: metadata.fileType,
            modificationDate: metadata.modificationDate,
            logicalSize: logicalSize,
            allocatedSize: allocatedSize,
            isSymbolicLink: metadata.isSymbolicLink,
            isAliasFile: metadata.isAliasFile,
            volumeIdentifier: metadata.volumeIdentifier,
            approvedRoot: approvedRoot.standardizedFileURL.path,
            matchedRuleIdentifier: rule.id,
            riskLevel: rule.risk
        )
    }

    public func revalidateForCleanup(_ item: CleanableItem, rule: CleanupRule) throws -> FileSystemMetadata {
        guard item.permissionStatus == .accessible else { throw FileValidationError.permissionDenied }
        guard rule.id == item.matchedRuleIdentifier else { throw FileValidationError.ruleMismatch }
        let rank: [RiskLevel: Int] = [.safe: 0, .review: 1, .protected: 2]
        guard item.scanSnapshot.riskLevel == item.riskLevel,
              rank[item.riskLevel, default: 2] >= rank[rule.risk, default: 2],
              item.riskLevel != .protected else {
            throw FileValidationError.riskMismatch
        }
        let approvedRoot = URL(fileURLWithPath: item.approvedRoot, isDirectory: true).standardizedFileURL
        guard rule.expandedRoots().contains(where: { $0.standardizedFileURL == approvedRoot }) else {
            throw FileValidationError.ruleMismatch
        }
        let url = URL(fileURLWithPath: item.standardizedPath)
        let current = try validateForScan(url, rule: rule, approvedRoot: approvedRoot)
        let snapshot = item.scanSnapshot
        guard current.standardizedURL.path == snapshot.standardizedPath else {
            throw FileValidationError.changedSinceScan("path")
        }
        if let expected = snapshot.resourceIdentifier, current.resourceIdentifier != expected {
            throw FileValidationError.changedSinceScan("resource identifier")
        }
        guard current.fileType == snapshot.fileType else {
            throw FileValidationError.changedSinceScan("file type")
        }
        guard current.isSymbolicLink == snapshot.isSymbolicLink else {
            throw FileValidationError.changedSinceScan("symbolic-link status")
        }
        if let expected = snapshot.modificationDate, let actual = current.modificationDate,
           abs(expected.timeIntervalSince(actual)) > 1 {
            throw FileValidationError.changedSinceScan("modification date")
        }
        if snapshot.fileType == "regular", current.logicalSize != snapshot.logicalSize {
            throw FileValidationError.changedSinceScan("size")
        }
        if let expected = snapshot.volumeIdentifier, current.volumeIdentifier != expected {
            throw FileValidationError.changedSinceScan("volume")
        }
        return current
    }
}

public enum DevelopmentSafetyLock {
    public static func permitsMutation(at url: URL) -> Bool {
        #if DEBUG
        let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).standardizedFileURL
        let candidate = url.standardizedFileURL
        return PathContainmentValidator().isContained(candidate, in: temporaryRoot, allowRootItself: false)
        #else
        return true
        #endif
    }

    public static func validateMutation(at url: URL) throws {
        guard permitsMutation(at: url) else { throw FileValidationError.developmentSafetyLock }
    }
}

public struct SafetyPolicy: Sendable {
    public init() {}

    public func canSelect(_ item: CleanableItem) -> Bool {
        item.riskLevel != .protected && item.permissionStatus == .accessible && item.cleanupMethod != .analysisOnly
    }

    public func selectedByDefault(risk: RiskLevel, confidence: AttributionConfidence) -> Bool {
        risk == .safe && confidence != .low && confidence != .unknown
    }

    public func finalRisk(rule: CleanupRule?, confidence: AttributionConfidence, category: ScanCategory) -> RiskLevel {
        guard let rule else { return .protected }
        if rule.risk == .protected { return .protected }
        if confidence == .low || confidence == .unknown { return .review }
        if category == .largeFile || category == .xcodeArchive || category == .iosBackup || category == .applicationLeftover {
            return .review
        }
        return rule.risk
    }
}
