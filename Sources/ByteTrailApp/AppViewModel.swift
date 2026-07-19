import AppKit
import ByteTrailCore
import Foundation
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case cleanup
    case applications
    case largeFiles
    case systemData
    case developerStorage
    case trash
    case history
    case coverage
    case settings

    var id: String { rawValue }
    var localizationKey: String { "section.\(rawValue)" }
    var symbol: String {
        switch self {
        case .overview: return "chart.pie"
        case .applications: return "square.grid.2x2"
        case .cleanup: return "checklist"
        case .systemData: return "internaldrive"
        case .developerStorage: return "hammer"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .trash: return "trash"
        case .coverage: return "list.bullet.clipboard"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selection: SidebarSection? = .overview
    @Published var items: [CleanableItem] = []
    @Published var issues: [ScanIssue] = []
    @Published var scanCoverage: [ScanCoverageEntry] = []
    @Published var progress = ScanProgress()
    @Published var isScanning = false
    @Published var scanWasCancelled = false
    @Published var lastScanDate: Date?
    @Published var lastCleanupDate: Date?
    @Published var cleanupResults: [CleanupResult] = []
    @Published private(set) var isCleaning = false
    @Published private(set) var cleanupTargetCount = 0
    @Published private(set) var cleanupCancellationRequested = false
    @Published private(set) var isEmptyingTrash = false
    @Published var trashEmptyingResult: TrashEmptyingResult?
    @Published var trashEmptyingError: String?
    @Published var history: [CleanupHistoryEntry] = []
    @Published var recoveryEntries: [RecoveryEntry] = []
    @Published var configurationError: String?
    @Published var largeFileMinimumGB: Double = 0.5
    @Published var oldFileAgeDays = 90
    @Published var logAgeDays = 30
    @Published var showHiddenFiles = false
    @Published var dryRun = true
    @Published var enabledScannerIDs = Set<String>()
    @Published var excludedPaths = Set<String>()
    @Published var excludedSources = Set<String>()
    @Published var authorizedFolders: [URL] = []
    @Published var historyRetentionDays = 365
    @Published var recoveryRetentionDays = 30
    @Published var language: AppLanguage = .system
    @Published private(set) var runningApplicationIDs = Set<String>()

    let storage = StorageMonitor().snapshot()
    let historyStore: CleanupHistoryStore
    let recoveryStore: RecoveryStore
    let exclusionStore: ExclusionStore
    let settingsStore: SettingsStore
    private let ruleEngine: RuleEngine?
    private let trashEmptyingService: any TrashEmptying
    private let scanCoordinator = ScanCoordinator()
    private var cleanupCoordinator: CleanupCoordinator?
    private var scanTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var trashEmptyingTask: Task<Void, Never>?

    init(trashEmptyingService: any TrashEmptying = TrashEmptyingService()) {
        self.trashEmptyingService = trashEmptyingService
        historyStore = CleanupHistoryStore()
        recoveryStore = RecoveryStore()
        exclusionStore = ExclusionStore()
        settingsStore = SettingsStore()
        do {
            let engine = try RuleEngine()
            ruleEngine = engine
            cleanupCoordinator = CleanupCoordinator(ruleEngine: engine, historyStore: historyStore, recoveryStore: recoveryStore)
        } catch {
            ruleEngine = nil
            configurationError = error.localizedDescription
        }
        #if DEBUG
        dryRun = true
        #else
        dryRun = false
        #endif
        Task {
            await refreshPersistence()
            await loadPreferences()
        }
    }

    var safeItems: [CleanableItem] { items.filter { $0.riskLevel == .safe } }
    var reviewItems: [CleanableItem] { items.filter { $0.riskLevel == .review } }
    var protectedItems: [CleanableItem] { items.filter { $0.riskLevel == .protected } }
    var selectedItems: [CleanableItem] { items.filter(\.selected) }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.allocatedSize } }
    var reviewBytes: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }
    var safeBytes: Int64 { safeItems.reduce(0) { $0 + $1.allocatedSize } }
    var trashItems: [CleanableItem] { items.filter { $0.category == .trash } }
    var trashBytes: Int64 { trashItems.reduce(0) { $0 + $1.allocatedSize } }

    func startScan() {
        guard let ruleEngine, !isScanning else { return }
        refreshRunningApplications()
        isScanning = true
        scanWasCancelled = false
        items.removeAll()
        issues.removeAll()
        scanCoverage.removeAll()
        progress = ScanProgress(startedAt: Date())
        let settings = currentScanSettings()
        let context = ScanContext(ruleEngine: ruleEngine, settings: settings)
        Task { try? await settingsStore.save(settings) }
        scanTask = Task { [weak self] in
            guard let self else { return }
            let stream = await scanCoordinator.scan(context: context)
            for await event in stream {
                if Task.isCancelled { break }
                switch event {
                case let .finding(item):
                    items.append(item)
                    progress.findings = items.count
                    progress.reclaimableBytes = items.reduce(0) { $0 + $1.allocatedSize }
                case let .issue(issue): issues.append(issue)
                case let .coverage(entry): upsertCoverage(entry)
                case let .progress(next):
                    progress.scannerName = next.scannerName
                    progress.category = next.category
                    progress.currentPath = next.currentPath
                    progress.filesInspected = max(progress.filesInspected, next.filesInspected)
                case .finished: break
                }
            }
            scanWasCancelled = scanWasCancelled || Task.isCancelled
            if scanWasCancelled {
                for index in scanCoverage.indices where scanCoverage[index].status == .pending {
                    scanCoverage[index].status = .cancelled
                }
            }
            lastScanDate = Date()
            isScanning = false
            scanTask = nil
        }
    }

    func cancelScan() {
        scanWasCancelled = true
        Task { await scanCoordinator.cancelCurrentScan() }
    }

    private func upsertCoverage(_ entry: ScanCoverageEntry) {
        if let index = scanCoverage.firstIndex(where: { $0.id == entry.id }) {
            scanCoverage[index] = entry
        } else {
            scanCoverage.append(entry)
        }
    }

    func setSelected(_ id: UUID, selected: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }), canSelect(items[index]) else { return }
        if selected {
            let target = URL(fileURLWithPath: items[index].standardizedPath).standardizedFileURL
            for otherIndex in items.indices where otherIndex != index && items[otherIndex].selected {
                let other = URL(fileURLWithPath: items[otherIndex].standardizedPath).standardizedFileURL
                let overlaps = PathContainmentValidator().isContained(target, in: other, allowRootItself: false)
                    || PathContainmentValidator().isContained(other, in: target, allowRootItself: false)
                if overlaps { items[otherIndex].selected = false }
            }
        }
        items[index].selected = selected
    }

    func selectAllSafe() {
        for index in items.indices where items[index].riskLevel == .safe && canSelect(items[index]) {
            items[index].selected = true
        }
    }

    func deselectAll() {
        for index in items.indices { items[index].selected = false }
    }

    func exclude(_ item: CleanableItem) {
        excludedPaths.insert(item.standardizedPath)
        items.removeAll { $0.id == item.id }
        Task { try? await exclusionStore.exclude(path: item.standardizedPath) }
    }

    func excludeSource(_ source: String) {
        excludedSources.insert(source)
        items.removeAll { $0.provenance.producedByName == source }
        Task { try? await exclusionStore.exclude(source: source) }
    }

    @discardableResult
    func cleanSelected() -> Bool {
        guard let cleanupCoordinator, !selectedItems.isEmpty, !isCleaning else { return false }
        let targets = selectedItems
        let useDryRun = dryRun
        refreshRunningApplications()
        let running = targets.filter(isSourceRunning)
        let allowed = targets.filter { !isSourceRunning($0) }
        let skipped = running.map {
            CleanupResult(
                itemID: $0.id,
                status: .skipped,
                originalURL: $0.provenance.currentURL,
                resultingURL: nil,
                bytesProcessed: 0,
                message: "The source application is running. Quit it and scan again before cleanup."
            )
        }
        cleanupResults.removeAll()
        cleanupTargetCount = targets.count
        cleanupCancellationRequested = false
        isCleaning = true
        cleanupTask = Task { [weak self] in
            guard let self else { return }
            let completed = await cleanupCoordinator.clean(items: allowed, dryRun: useDryRun)
            let completedIDs = Set(completed.map(\.itemID))
            let cancelled = allowed.filter { !completedIDs.contains($0.id) }.map {
                CleanupResult(
                    itemID: $0.id,
                    status: .skipped,
                    originalURL: $0.provenance.currentURL,
                    resultingURL: nil,
                    bytesProcessed: 0,
                    message: "Cleanup was cancelled before this item was processed."
                )
            }
            cleanupResults = skipped + completed + cancelled
            if cleanupResults.contains(where: { [.movedToRecovery, .movedToTrash].contains($0.status) }) {
                lastCleanupDate = Date()
            }
            let movedIDs = Set(cleanupResults.compactMap { result in
                [.movedToRecovery, .movedToTrash].contains(result.status) ? result.itemID : nil
            })
            items.removeAll { movedIDs.contains($0.id) }
            let targetIDs = Set(targets.map(\.id))
            for index in items.indices where targetIDs.contains(items[index].id) {
                items[index].selected = false
            }
            isCleaning = false
            cleanupCancellationRequested = false
            cleanupTask = nil
            await refreshPersistence()
            if cleanupResults.contains(where: { $0.status == .movedToTrash }) {
                await refreshTrashItems()
            }
        }
        return true
    }

    func cancelCleanup() {
        guard isCleaning, !cleanupCancellationRequested else { return }
        cleanupCancellationRequested = true
        cleanupTask?.cancel()
    }

    func refreshPersistence() async {
        history = await historyStore.allEntries()
        recoveryEntries = await recoveryStore.allEntries()
    }

    func clearHistory() {
        Task {
            try? await historyStore.clear()
            await refreshPersistence()
        }
    }

    @discardableResult
    func emptyTrash() -> Bool {
        guard !isEmptyingTrash, !trashItems.isEmpty else { return false }
        trashEmptyingResult = nil
        trashEmptyingError = nil
        isEmptyingTrash = true
        let service = trashEmptyingService
        trashEmptyingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try service.emptyTrash()
                }.value
                trashEmptyingResult = result
                await refreshTrashItems()
            } catch {
                trashEmptyingError = error.localizedDescription
            }
            isEmptyingTrash = false
            trashEmptyingTask = nil
        }
        return true
    }

    func refreshTrash() {
        guard !isEmptyingTrash else { return }
        Task { await refreshTrashItems() }
    }

    func dismissTrashEmptyingResult() {
        trashEmptyingResult = nil
    }

    func reveal(_ item: CleanableItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.provenance.currentURL])
    }

    func addExclusionFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = t("action.exclude")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        excludedPaths.insert(url.standardizedFileURL.path)
        Task { try? await exclusionStore.exclude(path: url.standardizedFileURL.path) }
    }

    func addAuthorizedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = t("action.addScanLocation")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !authorizedFolders.contains(url.standardizedFileURL) {
            authorizedFolders.append(url.standardizedFileURL)
        }
        persistSettings()
    }

    func removeAuthorizedFolder(_ url: URL) {
        authorizedFolders.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        persistSettings()
    }

    func canSelect(_ item: CleanableItem) -> Bool {
        SafetyPolicy().canSelect(item) && !isSourceRunning(item)
    }

    func isSourceRunning(_ item: CleanableItem) -> Bool {
        guard let identifier = item.provenance.producedByIdentifier else { return false }
        return runningApplicationIDs.contains(identifier)
    }

    func refreshRunningApplications() {
        runningApplicationIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func restore(_ historyEntry: CleanupHistoryEntry) {
        guard let cleanupCoordinator,
              let recovery = recoveryEntries.first(where: { $0.recoveryURL == historyEntry.recoveryURL }) else { return }
        Task {
            cleanupResults = [await cleanupCoordinator.restore(recovery)]
            await refreshPersistence()
        }
    }

    func openDocumentation(named name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md") else { return }
        NSWorkspace.shared.open(url)
    }

    func openFullDiskAccessSettings() {
        guard let url = PermissionManager().fullDiskAccessSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func resetExclusions() {
        excludedPaths.removeAll()
        excludedSources.removeAll()
        Task { try? await exclusionStore.reset() }
    }

    func persistSettings() {
        let settings = currentScanSettings()
        Task {
            try? await settingsStore.save(settings)
            try? await exclusionStore.replace(paths: excludedPaths, sources: excludedSources)
        }
    }

    private func currentScanSettings() -> ScanSettings {
        ScanSettings(
            enabledScannerIDs: enabledScannerIDs,
            largeFileMinimumBytes: Int64(largeFileMinimumGB * 1_000_000_000),
            oldFileAgeDays: oldFileAgeDays,
            logAgeDays: logAgeDays,
            authorizedFolders: authorizedFolders,
            excludedPaths: excludedPaths,
            excludedSources: excludedSources,
            showHiddenFiles: showHiddenFiles,
            dryRun: dryRun,
            languageIdentifier: language.rawValue
        )
    }

    private func refreshTrashItems() async {
        guard let ruleEngine else { return }
        let context = ScanContext(ruleEngine: ruleEngine, settings: currentScanSettings())
        var refreshedItems: [CleanableItem] = []
        var refreshedIssues: [ScanIssue] = []
        for await event in TrashScanner().scan(context: context) {
            switch event {
            case let .finding(item): refreshedItems.append(item)
            case let .issue(issue): refreshedIssues.append(issue)
            default: break
            }
        }
        items.removeAll { $0.category == .trash }
        items.append(contentsOf: refreshedItems)
        issues.removeAll { $0.scannerIdentifier == "scanner.trash" }
        issues.append(contentsOf: refreshedIssues)
    }

    private func loadPreferences() async {
        if let settings = await settingsStore.load() {
            enabledScannerIDs = settings.enabledScannerIDs
            largeFileMinimumGB = Double(settings.largeFileMinimumBytes) / 1_000_000_000
            oldFileAgeDays = settings.oldFileAgeDays
            logAgeDays = settings.logAgeDays
            authorizedFolders = settings.authorizedFolders
            showHiddenFiles = settings.showHiddenFiles
            language = AppLanguage(rawValue: settings.languageIdentifier ?? "system") ?? .system
        }
        excludedPaths = await exclusionStore.excludedPaths()
        excludedSources = await exclusionStore.excludedSources()
    }
}
