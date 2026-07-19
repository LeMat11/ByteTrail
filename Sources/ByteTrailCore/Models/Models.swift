import Foundation

public enum AppConfiguration {
    public static let productName = "ByteTrail"
    public static let bundleIdentifier = "com.bytetrail.mac"
    public static let version = "1.2.2"
    public static let build = "6"
    public static let deploymentTarget = "13.0"
    public static let tagline = "Every byte has a source."
}

public enum RiskLevel: String, Codable, CaseIterable, Sendable {
    case safe
    case review
    case protected

    public var label: String {
        switch self {
        case .safe: return "Safe"
        case .review: return "Review"
        case .protected: return "Protected"
        }
    }
}

public enum AttributionConfidence: String, Codable, CaseIterable, Sendable {
    case confirmed
    case high
    case medium
    case low
    case unknown

    public var label: String { rawValue.capitalized }
}

public enum CleanupMethod: String, Codable, CaseIterable, Sendable {
    case moveToTrash
    case recoveryVault
    case analysisOnly

    public var label: String {
        switch self {
        case .moveToTrash: return "Move to Trash"
        case .recoveryVault: return "Recovery Vault"
        case .analysisOnly: return "Analysis only"
        }
    }
}

public enum PermissionStatus: String, Codable, Sendable {
    case accessible
    case denied
    case unavailable
    case userAuthorizationRequired
    case unknown
}

public enum SourceType: String, Codable, Sendable {
    case application
    case developerTool
    case systemComponent
    case userFile
    case unknown
}

public enum ScanCategory: String, Codable, CaseIterable, Sendable {
    case applicationBundle = "application-bundle"
    case userCache = "user-cache"
    case userLog = "user-log"
    case trash
    case xcodeDerivedData = "xcode-derived-data"
    case xcodeArchive = "xcode-archive"
    case xcodeDeviceSupport = "xcode-device-support"
    case simulatorData = "simulator-data"
    case developerCache = "developer-cache"
    case installer
    case largeFile = "large-file"
    case iosBackup = "ios-backup"
    case applicationLeftover = "application-leftover"
    case unknown

    public var label: String {
        switch self {
        case .applicationBundle: return "Application"
        case .userCache: return "User Cache"
        case .userLog: return "Logs"
        case .trash: return "Trash"
        case .xcodeDerivedData: return "Xcode Derived Data"
        case .xcodeArchive: return "Xcode Archives"
        case .xcodeDeviceSupport: return "Xcode Device Support"
        case .simulatorData: return "Simulator Data"
        case .developerCache: return "Developer Cache"
        case .installer: return "Installer"
        case .largeFile: return "Large File"
        case .iosBackup: return "iOS Backup"
        case .applicationLeftover: return "Application Leftover"
        case .unknown: return "Unknown"
        }
    }
}

public struct SourceProvenance: Codable, Hashable, Sendable {
    public var producedByName: String
    public var producedByIdentifier: String?
    public var sourceType: SourceType
    public var currentURL: URL
    public var originalURL: URL?
    public var sourceApplicationURL: URL?
    public var detectionReason: String
    public var evidence: [String]
    public var confidence: AttributionConfidence

    public init(
        producedByName: String = "Unknown source",
        producedByIdentifier: String? = nil,
        sourceType: SourceType = .unknown,
        currentURL: URL,
        originalURL: URL? = nil,
        sourceApplicationURL: URL? = nil,
        detectionReason: String,
        evidence: [String] = [],
        confidence: AttributionConfidence = .unknown
    ) {
        self.producedByName = producedByName
        self.producedByIdentifier = producedByIdentifier
        self.sourceType = sourceType
        self.currentURL = currentURL
        self.originalURL = originalURL
        self.sourceApplicationURL = sourceApplicationURL
        self.detectionReason = detectionReason
        self.evidence = evidence
        self.confidence = confidence
    }
}

public struct FileSnapshot: Codable, Hashable, Sendable {
    public var standardizedPath: String
    public var resourceIdentifier: String?
    public var fileType: String
    public var modificationDate: Date?
    public var logicalSize: Int64
    public var allocatedSize: Int64
    public var isSymbolicLink: Bool
    public var isAliasFile: Bool
    public var volumeIdentifier: String?
    public var approvedRoot: String
    public var matchedRuleIdentifier: String
    public var riskLevel: RiskLevel

    public init(
        standardizedPath: String,
        resourceIdentifier: String?,
        fileType: String,
        modificationDate: Date?,
        logicalSize: Int64,
        allocatedSize: Int64,
        isSymbolicLink: Bool,
        isAliasFile: Bool,
        volumeIdentifier: String?,
        approvedRoot: String,
        matchedRuleIdentifier: String,
        riskLevel: RiskLevel
    ) {
        self.standardizedPath = standardizedPath
        self.resourceIdentifier = resourceIdentifier
        self.fileType = fileType
        self.modificationDate = modificationDate
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.isSymbolicLink = isSymbolicLink
        self.isAliasFile = isAliasFile
        self.volumeIdentifier = volumeIdentifier
        self.approvedRoot = approvedRoot
        self.matchedRuleIdentifier = matchedRuleIdentifier
        self.riskLevel = riskLevel
    }
}

public struct CleanableItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String
    public var provenance: SourceProvenance
    public var sourceIconReference: String?
    public var standardizedPath: String
    public var category: ScanCategory
    public var size: Int64
    public var allocatedSize: Int64
    public var fileCount: Int
    public var modifiedDate: Date?
    public var lastAccessDate: Date?
    public var createdDate: Date?
    public var whatItIs: String
    public var cleanupReason: String
    public var expectedImpact: String
    public var regeneratable: Bool
    public var riskLevel: RiskLevel
    public var permissionStatus: PermissionStatus
    public var selected: Bool
    public var scannerIdentifier: String
    public var matchedRuleIdentifier: String
    public var approvedRoot: String
    public var scanSnapshot: FileSnapshot
    public var cleanupMethod: CleanupMethod
    public var recoveryAvailable: Bool
    public var embeddedRule: CleanupRule?

    public init(
        id: UUID = UUID(),
        displayName: String,
        provenance: SourceProvenance,
        sourceIconReference: String? = nil,
        standardizedPath: String,
        category: ScanCategory,
        size: Int64,
        allocatedSize: Int64,
        fileCount: Int,
        modifiedDate: Date?,
        lastAccessDate: Date? = nil,
        createdDate: Date? = nil,
        whatItIs: String,
        cleanupReason: String,
        expectedImpact: String,
        regeneratable: Bool,
        riskLevel: RiskLevel,
        permissionStatus: PermissionStatus,
        selected: Bool,
        scannerIdentifier: String,
        matchedRuleIdentifier: String,
        approvedRoot: String,
        scanSnapshot: FileSnapshot,
        cleanupMethod: CleanupMethod,
        recoveryAvailable: Bool,
        embeddedRule: CleanupRule? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.provenance = provenance
        self.sourceIconReference = sourceIconReference
        self.standardizedPath = standardizedPath
        self.category = category
        self.size = size
        self.allocatedSize = allocatedSize
        self.fileCount = fileCount
        self.modifiedDate = modifiedDate
        self.lastAccessDate = lastAccessDate
        self.createdDate = createdDate
        self.whatItIs = whatItIs
        self.cleanupReason = cleanupReason
        self.expectedImpact = expectedImpact
        self.regeneratable = regeneratable
        self.riskLevel = riskLevel
        self.permissionStatus = permissionStatus
        self.selected = selected
        self.scannerIdentifier = scannerIdentifier
        self.matchedRuleIdentifier = matchedRuleIdentifier
        self.approvedRoot = approvedRoot
        self.scanSnapshot = scanSnapshot
        self.cleanupMethod = cleanupMethod
        self.recoveryAvailable = recoveryAvailable
        self.embeddedRule = embeddedRule
    }
}

public struct ScanProgress: Codable, Sendable {
    public var scannerName: String
    public var category: String
    public var currentPath: String?
    public var filesInspected: Int
    public var findings: Int
    public var reclaimableBytes: Int64
    public var startedAt: Date
    public var isIndeterminate: Bool

    public init(scannerName: String = "Preparing", category: String = "", currentPath: String? = nil, filesInspected: Int = 0, findings: Int = 0, reclaimableBytes: Int64 = 0, startedAt: Date = Date(), isIndeterminate: Bool = true) {
        self.scannerName = scannerName
        self.category = category
        self.currentPath = currentPath
        self.filesInspected = filesInspected
        self.findings = findings
        self.reclaimableBytes = reclaimableBytes
        self.startedAt = startedAt
        self.isIndeterminate = isIndeterminate
    }
}

public struct ScanIssue: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var scannerIdentifier: String
    public var path: String
    public var message: String
    public var permissionStatus: PermissionStatus

    public init(scannerIdentifier: String, path: String, message: String, permissionStatus: PermissionStatus) {
        self.scannerIdentifier = scannerIdentifier
        self.path = path
        self.message = message
        self.permissionStatus = permissionStatus
    }
}

public enum ScanCoverageStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case scanned
    case noFindings
    case notFound
    case permissionDenied
    case partial
    case disabled
    case cancelled
}

public struct ScanCoverageLocation: Identifiable, Codable, Hashable, Sendable {
    public var scannerIdentifier: String
    public var scannerName: String
    public var standardizedPath: String

    public var id: String { "\(scannerIdentifier)::\(standardizedPath)" }

    public init(scannerIdentifier: String, scannerName: String, url: URL) {
        self.scannerIdentifier = scannerIdentifier
        self.scannerName = scannerName
        self.standardizedPath = url.standardizedFileURL.path
    }
}

public struct ScanCoverageEntry: Identifiable, Codable, Hashable, Sendable {
    public var location: ScanCoverageLocation
    public var status: ScanCoverageStatus
    public var findingCount: Int
    public var message: String?

    public var id: String { location.id }
    public var scannerIdentifier: String { location.scannerIdentifier }
    public var scannerName: String { location.scannerName }
    public var standardizedPath: String { location.standardizedPath }

    public init(
        location: ScanCoverageLocation,
        status: ScanCoverageStatus,
        findingCount: Int = 0,
        message: String? = nil
    ) {
        self.location = location
        self.status = status
        self.findingCount = findingCount
        self.message = message
    }
}

public struct ScanResult: Codable, Sendable {
    public var items: [CleanableItem]
    public var issues: [ScanIssue]
    public var startedAt: Date
    public var completedAt: Date?
    public var cancelled: Bool

    public init(items: [CleanableItem] = [], issues: [ScanIssue] = [], startedAt: Date = Date(), completedAt: Date? = nil, cancelled: Bool = false) {
        self.items = items
        self.issues = issues
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.cancelled = cancelled
    }
}

public enum CleanupResultStatus: String, Codable, Sendable {
    case dryRun
    case movedToTrash
    case movedToRecovery
    case restored
    case skipped
    case failed
}

public struct CleanupResult: Identifiable, Codable, Sendable {
    public var id: UUID = UUID()
    public var itemID: UUID
    public var status: CleanupResultStatus
    public var originalURL: URL
    public var resultingURL: URL?
    public var bytesProcessed: Int64
    public var message: String

    public init(itemID: UUID, status: CleanupResultStatus, originalURL: URL, resultingURL: URL?, bytesProcessed: Int64, message: String) {
        self.itemID = itemID
        self.status = status
        self.originalURL = originalURL
        self.resultingURL = resultingURL
        self.bytesProcessed = bytesProcessed
        self.message = message
    }
}

public struct CleanupHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var itemName: String
    public var producedBy: String
    public var originalURL: URL?
    public var recoveryURL: URL?
    public var size: Int64
    public var ruleIdentifier: String
    public var cleanupMethod: CleanupMethod
    public var result: CleanupResultStatus
    public var restoreAvailable: Bool
    public var errorMessage: String?

    public init(id: UUID = UUID(), date: Date = Date(), itemName: String, producedBy: String, originalURL: URL?, recoveryURL: URL?, size: Int64, ruleIdentifier: String, cleanupMethod: CleanupMethod, result: CleanupResultStatus, restoreAvailable: Bool, errorMessage: String? = nil) {
        self.id = id
        self.date = date
        self.itemName = itemName
        self.producedBy = producedBy
        self.originalURL = originalURL
        self.recoveryURL = recoveryURL
        self.size = size
        self.ruleIdentifier = ruleIdentifier
        self.cleanupMethod = cleanupMethod
        self.result = result
        self.restoreAvailable = restoreAvailable
        self.errorMessage = errorMessage
    }
}

public struct RecoveryEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var originalURL: URL
    public var recoveryURL: URL
    public var movedAt: Date
    public var size: Int64
    public var ruleIdentifier: String

    public init(id: UUID = UUID(), originalURL: URL, recoveryURL: URL, movedAt: Date = Date(), size: Int64, ruleIdentifier: String) {
        self.id = id
        self.originalURL = originalURL
        self.recoveryURL = recoveryURL
        self.movedAt = movedAt
        self.size = size
        self.ruleIdentifier = ruleIdentifier
    }
}

public struct ScanSettings: Codable, Sendable {
    public var enabledScannerIDs: Set<String>
    public var largeFileMinimumBytes: Int64
    public var oldFileAgeDays: Int
    public var logAgeDays: Int
    public var authorizedFolders: [URL]
    public var excludedPaths: Set<String>
    public var excludedSources: Set<String>
    public var showHiddenFiles: Bool
    public var dryRun: Bool
    public var languageIdentifier: String?

    public init(
        enabledScannerIDs: Set<String> = [],
        largeFileMinimumBytes: Int64 = 500_000_000,
        oldFileAgeDays: Int = 90,
        logAgeDays: Int = 30,
        authorizedFolders: [URL] = [],
        excludedPaths: Set<String> = [],
        excludedSources: Set<String> = [],
        showHiddenFiles: Bool = false,
        dryRun: Bool = true,
        languageIdentifier: String? = nil
    ) {
        self.enabledScannerIDs = enabledScannerIDs
        self.largeFileMinimumBytes = largeFileMinimumBytes
        self.oldFileAgeDays = oldFileAgeDays
        self.logAgeDays = logAgeDays
        self.authorizedFolders = authorizedFolders
        self.excludedPaths = excludedPaths
        self.excludedSources = excludedSources
        self.showHiddenFiles = showHiddenFiles
        self.dryRun = dryRun
        self.languageIdentifier = languageIdentifier
    }
}

public extension Int64 {
    var byteTrailFormatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
