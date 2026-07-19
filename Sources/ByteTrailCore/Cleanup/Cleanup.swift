import Foundation

public enum CleanupOperationError: Error, LocalizedError {
    case trashUnavailable
    case destinationExists
    case invalidRecoveryPath
    case missingRecoveryItem

    public var errorDescription: String? {
        switch self {
        case .trashUnavailable: return "Moving to Trash is unavailable in this build or environment."
        case .destinationExists: return "A file already exists at the restore destination."
        case .invalidRecoveryPath: return "The Recovery Vault destination is invalid."
        case .missingRecoveryItem: return "The Recovery Vault item no longer exists."
        }
    }
}

public struct TrashCleanupOperation: @unchecked Sendable {
    private let fileManager: FileManager
    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func execute(source: URL) throws -> URL? {
        try DevelopmentSafetyLock.validateMutation(at: source)
        #if DEBUG
        // FileManager.trashItem would move even a synthetic fixture into the real user Trash.
        // Debug builds refuse that boundary crossing and allow the coordinator to use its vault fallback.
        throw CleanupOperationError.trashUnavailable
        #else
        var resultingURL: NSURL?
        try fileManager.trashItem(at: source, resultingItemURL: &resultingURL)
        return resultingURL as URL?
        #endif
    }
}

public struct RecoveryVaultOperation: @unchecked Sendable {
    public let vaultRoot: URL
    private let fileManager: FileManager

    public init(vaultRoot: URL? = nil, fileManager: FileManager = .default) {
        self.vaultRoot = vaultRoot ?? Self.defaultVaultRoot
        self.fileManager = fileManager
    }

    public static var defaultVaultRoot: URL {
        #if DEBUG
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ByteTrail-Debug", isDirectory: true)
            .appendingPathComponent("RecoveryVault", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(AppConfiguration.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("RecoveryVault", isDirectory: true)
        #endif
    }

    public func execute(source: URL, itemID: UUID) throws -> URL {
        try DevelopmentSafetyLock.validateMutation(at: source)
        try DevelopmentSafetyLock.validateMutation(at: vaultRoot)
        let itemDirectory = vaultRoot.appendingPathComponent(itemID.uuidString, isDirectory: true)
        try DevelopmentSafetyLock.validateMutation(at: itemDirectory)
        try fileManager.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        let destination = uniqueDestination(in: itemDirectory, preferredName: source.lastPathComponent)
        guard PathContainmentValidator().isContained(destination, in: vaultRoot, allowRootItself: false) else {
            throw CleanupOperationError.invalidRecoveryPath
        }
        try fileManager.moveItem(at: source, to: destination)
        return destination
    }

    private func uniqueDestination(in directory: URL, preferredName: String) -> URL {
        let initial = directory.appendingPathComponent(preferredName)
        guard fileManager.fileExists(atPath: initial.path) else { return initial }
        let base = initial.deletingPathExtension().lastPathComponent
        let ext = initial.pathExtension
        for index in 2...10_000 {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent(UUID().uuidString)
    }
}

public struct RestoreOperation: @unchecked Sendable {
    private let fileManager: FileManager
    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func execute(_ entry: RecoveryEntry) throws -> URL {
        try DevelopmentSafetyLock.validateMutation(at: entry.recoveryURL)
        try DevelopmentSafetyLock.validateMutation(at: entry.originalURL)
        guard fileManager.fileExists(atPath: entry.recoveryURL.path) else { throw CleanupOperationError.missingRecoveryItem }
        guard !fileManager.fileExists(atPath: entry.originalURL.path) else { throw CleanupOperationError.destinationExists }
        let parent = entry.originalURL.deletingLastPathComponent().standardizedFileURL
        guard fileManager.fileExists(atPath: parent.path) else { throw CleanupOperationError.invalidRecoveryPath }
        if ProtectedPathPolicy().isAlwaysProtected(entry.originalURL) { throw FileValidationError.protectedPath }
        try fileManager.moveItem(at: entry.recoveryURL, to: entry.originalURL)
        return entry.originalURL
    }
}

public actor CleanupCoordinator {
    private let ruleEngine: RuleEngine
    private let validator: FileSystemValidator
    private let historyStore: CleanupHistoryStore
    private let recoveryStore: RecoveryStore
    private let trashOperation: TrashCleanupOperation
    private let vaultOperation: RecoveryVaultOperation
    private let restoreOperation: RestoreOperation

    public init(
        ruleEngine: RuleEngine,
        validator: FileSystemValidator = FileSystemValidator(),
        historyStore: CleanupHistoryStore = CleanupHistoryStore(),
        recoveryStore: RecoveryStore = RecoveryStore(),
        trashOperation: TrashCleanupOperation = TrashCleanupOperation(),
        vaultOperation: RecoveryVaultOperation = RecoveryVaultOperation(),
        restoreOperation: RestoreOperation = RestoreOperation()
    ) {
        self.ruleEngine = ruleEngine
        self.validator = validator
        self.historyStore = historyStore
        self.recoveryStore = recoveryStore
        self.trashOperation = trashOperation
        self.vaultOperation = vaultOperation
        self.restoreOperation = restoreOperation
    }

    public func clean(items: [CleanableItem], dryRun: Bool) async -> [CleanupResult] {
        var results: [CleanupResult] = []
        var processedPaths = Set<String>()
        for item in items {
            if Task.isCancelled { break }
            guard processedPaths.insert(item.standardizedPath).inserted else {
                results.append(CleanupResult(itemID: item.id, status: .skipped, originalURL: item.provenance.currentURL, resultingURL: nil, bytesProcessed: 0, message: "Duplicate cleanup target skipped."))
                continue
            }
            results.append(await clean(item: item, dryRun: dryRun))
        }
        return results
    }

    private func clean(item: CleanableItem, dryRun: Bool) async -> CleanupResult {
        let original = item.provenance.currentURL
        guard SafetyPolicy().canSelect(item) else {
            return await record(item: item, result: CleanupResult(itemID: item.id, status: .skipped, originalURL: original, resultingURL: nil, bytesProcessed: 0, message: "Safety policy does not permit this item to be cleaned."))
        }
        guard let rule = ruleEngine.rule(identifier: item.matchedRuleIdentifier) ?? item.embeddedRule,
              rule.id == item.matchedRuleIdentifier,
              (try? RuleValidator().validate([rule])) != nil else {
            return await record(item: item, result: CleanupResult(itemID: item.id, status: .skipped, originalURL: original, resultingURL: nil, bytesProcessed: 0, message: "Matched rule is no longer available."))
        }
        do {
            _ = try validator.revalidateForCleanup(item, rule: rule)
            if dryRun {
                return await record(item: item, result: CleanupResult(itemID: item.id, status: .dryRun, originalURL: original, resultingURL: nil, bytesProcessed: 0, message: "Validated. No file was moved because dry-run is enabled."))
            }
            try DevelopmentSafetyLock.validateMutation(at: original)
            switch item.cleanupMethod {
            case .analysisOnly:
                return await record(item: item, result: CleanupResult(itemID: item.id, status: .skipped, originalURL: original, resultingURL: nil, bytesProcessed: 0, message: "This item is analysis-only."))
            case .recoveryVault:
                return try await moveToVault(item: item)
            case .moveToTrash:
                do {
                    let destination = try trashOperation.execute(source: original)
                    return await record(item: item, result: CleanupResult(itemID: item.id, status: .movedToTrash, originalURL: original, resultingURL: destination, bytesProcessed: item.allocatedSize, message: "Moved to Trash."))
                } catch {
                    return try await moveToVault(item: item)
                }
            }
        } catch {
            return await record(item: item, result: CleanupResult(itemID: item.id, status: .failed, originalURL: original, resultingURL: nil, bytesProcessed: 0, message: error.localizedDescription))
        }
    }

    private func moveToVault(item: CleanableItem) async throws -> CleanupResult {
        let destination = try vaultOperation.execute(source: item.provenance.currentURL, itemID: item.id)
        let recovery = RecoveryEntry(originalURL: item.provenance.currentURL, recoveryURL: destination, size: item.size, ruleIdentifier: item.matchedRuleIdentifier)
        do {
            try await recoveryStore.append(recovery)
        } catch {
            // A vault move is not considered successful unless its recovery index is durable.
            // Roll back immediately so the source is not stranded without a restore record.
            _ = try? RestoreOperation().execute(recovery)
            throw error
        }
        return await record(item: item, result: CleanupResult(itemID: item.id, status: .movedToRecovery, originalURL: item.provenance.currentURL, resultingURL: destination, bytesProcessed: item.allocatedSize, message: "Moved to the Recovery Vault."))
    }

    private func record(item: CleanableItem, result: CleanupResult) async -> CleanupResult {
        let entry = CleanupHistoryEntry(
            itemName: item.displayName,
            producedBy: item.provenance.producedByName,
            originalURL: item.provenance.currentURL,
            recoveryURL: result.status == .movedToRecovery ? result.resultingURL : nil,
            size: item.size,
            ruleIdentifier: item.matchedRuleIdentifier,
            cleanupMethod: item.cleanupMethod,
            result: result.status,
            restoreAvailable: result.status == .movedToRecovery,
            errorMessage: result.status == .failed ? result.message : nil
        )
        try? await historyStore.append(entry)
        return result
    }

    public func restore(_ entry: RecoveryEntry) async -> CleanupResult {
        do {
            let destination = try restoreOperation.execute(entry)
            try await recoveryStore.remove(id: entry.id)
            return CleanupResult(itemID: entry.id, status: .restored, originalURL: entry.originalURL, resultingURL: destination, bytesProcessed: entry.size, message: "Restored to the original location.")
        } catch {
            return CleanupResult(itemID: entry.id, status: .failed, originalURL: entry.originalURL, resultingURL: nil, bytesProcessed: 0, message: error.localizedDescription)
        }
    }
}
