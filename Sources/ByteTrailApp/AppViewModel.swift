import AppKit
import ByteTrailCore
import Foundation
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview
    case cleanup
    case systemData
    case developerStorage
    case largeFiles
    case trash
    case history
    case settings

    var id: String { rawValue }
    var localizationKey: String { "section.\(rawValue)" }
    var symbol: String {
        switch self {
        case .overview: return "chart.pie"
        case .cleanup: return "checklist"
        case .systemData: return "internaldrive"
        case .developerStorage: return "hammer"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .trash: return "trash"
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
    @Published var progress = ScanProgress()
    @Published var isScanning = false
    @Published var scanWasCancelled = false
    @Published var lastScanDate: Date?
    @Published var lastCleanupDate: Date?
    @Published var cleanupResults: [CleanupResult] = []
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
    private let scanCoordinator = ScanCoordinator()
    private var cleanupCoordinator: CleanupCoordinator?
    private var scanTask: Task<Void, Never>?

    init() {
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

    func startScan() {
        guard let ruleEngine, !isScanning else { return }
        refreshRunningApplications()
        isScanning = true
        scanWasCancelled = false
        items.removeAll()
        issues.removeAll()
        progress = ScanProgress(startedAt: Date())
        let settings = ScanSettings(
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
                case let .progress(next):
                    progress.scannerName = next.scannerName
                    progress.category = next.category
                    progress.currentPath = next.currentPath
                    progress.filesInspected = max(progress.filesInspected, next.filesInspected)
                case .finished: break
                }
            }
            scanWasCancelled = Task.isCancelled
            lastScanDate = Date()
            isScanning = false
            scanTask = nil
        }
    }

    func cancelScan() {
        scanWasCancelled = true
        scanTask?.cancel()
    }

    func setSelected(_ id: UUID, selected: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }), canSelect(items[index]) else { return }
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

    func cleanSelected() {
        guard let cleanupCoordinator, !selectedItems.isEmpty else { return }
        let targets = selectedItems
        let useDryRun = dryRun
        refreshRunningApplications()
        cleanupResults.removeAll()
        Task {
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
            cleanupResults = skipped + (await cleanupCoordinator.clean(items: allowed, dryRun: useDryRun))
            if cleanupResults.contains(where: { [.movedToRecovery, .movedToTrash].contains($0.status) }) {
                lastCleanupDate = Date()
            }
            await refreshPersistence()
        }
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
        let settings = ScanSettings(
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
        Task {
            try? await settingsStore.save(settings)
            try? await exclusionStore.replace(paths: excludedPaths, sources: excludedSources)
        }
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
