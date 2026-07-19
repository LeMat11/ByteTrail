import ByteTrailCore
import SwiftUI

private enum FindingsSort: String, CaseIterable, Identifiable {
    case size
    case age
    var id: String { rawValue }
}

private enum FindingsGrouping: String, CaseIterable, Identifiable {
    case risk
    case source
    case category
    var id: String { rawValue }
}

struct FindingsView: View {
    let titleKey: String
    let categories: Set<ScanCategory>?
    let scannerIDs: Set<String>?
    @EnvironmentObject private var model: AppViewModel
    @State private var search = ""
    @State private var sort: FindingsSort = .size
    @State private var grouping: FindingsGrouping = .risk
    @State private var selectedID: UUID?
    @State private var showingResults = false
    @State private var showingEvidence = false

    init(
        titleKey: String,
        categories: Set<ScanCategory>? = nil,
        scannerIDs: Set<String>? = nil,
        groupBySource: Bool = false
    ) {
        self.titleKey = titleKey
        self.categories = categories
        self.scannerIDs = scannerIDs
        _grouping = State(initialValue: groupBySource ? .source : .risk)
    }

    private var filtered: [CleanableItem] {
        var result = model.items.filter { item in
            (categories?.contains(item.category) ?? true)
                && (scannerIDs?.contains(item.scannerIdentifier) ?? true)
        }
        if !search.isEmpty {
            result = result.filter {
                $0.displayName.localizedCaseInsensitiveContains(search)
                || $0.provenance.producedByName.localizedCaseInsensitiveContains(search)
                || ($0.provenance.producedByIdentifier?.localizedCaseInsensitiveContains(search) ?? false)
                || $0.standardizedPath.localizedCaseInsensitiveContains(search)
            }
        }
        switch sort {
        case .size: result.sort { $0.allocatedSize > $1.allocatedSize }
        case .age: result.sort { ($0.modifiedDate ?? .distantFuture) < ($1.modifiedDate ?? .distantFuture) }
        }
        return result
    }

    private var grouped: [(String, [CleanableItem])] {
        let dictionary = Dictionary(grouping: filtered) { item in
            switch grouping {
            case .risk: return item.riskLevel.rawValue
            case .source: return item.provenance.producedByName
            case .category: return item.category.rawValue
            }
        }
        return dictionary.map { ($0.key, $0.value) }.sorted { lhs, rhs in
            if grouping == .risk {
                let order = [RiskLevel.safe.rawValue: 0, RiskLevel.review.rawValue: 1, RiskLevel.protected.rawValue: 2]
                return order[lhs.0, default: 9] < order[rhs.0, default: 9]
            }
            if grouping == .source && sort == .size {
                let lhsSize = lhs.1.reduce(Int64(0)) { $0 + $1.allocatedSize }
                let rhsSize = rhs.1.reduce(Int64(0)) { $0 + $1.allocatedSize }
                if lhsSize != rhsSize { return lhsSize > rhsSize }
            }
            return groupTitle(lhs.0).localizedCaseInsensitiveCompare(groupTitle(rhs.0)) == .orderedAscending
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 760
            Group {
                if compact {
                    findingsPane
                } else {
                    HSplitView {
                        findingsPane.frame(minWidth: 390, idealWidth: 580)
                        evidencePane.frame(minWidth: 290, idealWidth: 400)
                    }
                }
            }
            .onChange(of: selectedID) { newValue in
                if compact, newValue != nil { showingEvidence = true }
            }
        }
        .navigationTitle(model.t(titleKey))
        .sheet(isPresented: $showingEvidence) {
            if let selectedID, let item = model.items.first(where: { $0.id == selectedID }) {
                EvidenceDetailView(item: item)
                    .environmentObject(model)
                    .frame(minWidth: 420, idealWidth: 620, minHeight: 480, idealHeight: 640)
            }
        }
        .sheet(isPresented: $showingResults) {
            CleanupResultView().environmentObject(model)
        }
    }

    private var findingsPane: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if filtered.isEmpty {
                EmptyFindingsView(scanning: model.isScanning)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(grouped, id: \.0) { group in
                        Section {
                            ForEach(group.1) { item in row(item) }
                        } header: {
                            HStack {
                                Text(groupTitle(group.0))
                                Spacer()
                                Text(model.formatBytes(group.1.reduce(0) { $0 + $1.allocatedSize }))
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            selectionBar
        }
    }

    @ViewBuilder private var evidencePane: some View {
        if let selectedID, let item = model.items.first(where: { $0.id == selectedID }) {
            EvidenceDetailView(item: item).environmentObject(model)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                Text(model.t("findings.selectForEvidence"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                TextField(model.t("findings.search"), text: $search).textFieldStyle(.roundedBorder).frame(width: 230)
                groupingPicker.frame(width: 145)
                sortPicker.frame(width: 110)
                Spacer()
                selectionButtons
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(spacing: 8) {
                TextField(model.t("findings.search"), text: $search).textFieldStyle(.roundedBorder)
                HStack {
                    groupingPicker
                    sortPicker
                    Spacer()
                    selectionButtons
                }
            }
        }
        .padding(12)
    }

    private var groupingPicker: some View {
        Picker(model.t("findings.group"), selection: $grouping) {
            ForEach(FindingsGrouping.allCases) { Text(model.t("group.\($0.rawValue)")).tag($0) }
        }
    }

    private var sortPicker: some View {
        Picker(model.t("findings.sort"), selection: $sort) {
            ForEach(FindingsSort.allCases) { Text(model.t("sort.\($0.rawValue)")).tag($0) }
        }
    }

    private var selectionButtons: some View {
        HStack {
            Button(model.t("action.selectSafe")) { model.selectAllSafe() }
            Button(model.t("action.clearSelection")) { model.deselectAll() }
        }
    }

    private func row(_ item: CleanableItem) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.items.first(where: { $0.id == item.id })?.selected ?? false },
                set: { model.setSelected(item.id, selected: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(!model.canSelect(item))
            FindingIcon(item: item, size: 22)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.displayName).lineLimit(1)
                Text(verbatim: "\(model.sourceName(item)) · \(item.standardizedPath)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if model.isSourceRunning(item) {
                    Label(model.t("cache.applicationRunning"), systemImage: "play.circle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            RiskBadge(risk: item.riskLevel)
            Text(model.formatBytes(item.allocatedSize)).monospacedDigit().frame(width: 88, alignment: .trailing)
        }
        .tag(item.id)
        .contextMenu {
            Button(model.t("action.revealFinder")) { model.reveal(item) }
            Button(model.t("action.excludePath")) { model.exclude(item) }
            Button(model.t("action.excludeSource", model.sourceName(item))) { model.excludeSource(item.provenance.producedByName) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.t(
            "accessibility.finding",
            item.displayName,
            model.sourceName(item),
            model.riskLabel(item.riskLevel),
            model.formatBytes(item.allocatedSize)
        ))
    }

    private var selectionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                selectionStatus
                Spacer()
                cleanupButton
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 8) {
                selectionStatus
                cleanupButton.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var selectionStatus: some View {
        HStack(spacing: 8) {
            Text(model.t("findings.selectedCount", model.selectedItems.count))
            Text(model.formatBytes(model.selectedBytes)).fontWeight(.semibold).monospacedDigit()
            if model.selectedItems.contains(where: { $0.riskLevel == .review }) {
                Label(model.t("findings.includesReview"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
    }

    private var cleanupButton: some View {
        Button(model.dryRun ? model.t("action.simulateCleanup") : model.t("action.cleanUpSelected")) {
            model.cleanSelected()
            showingResults = true
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.selectedItems.isEmpty)
    }

    private func groupTitle(_ key: String) -> String {
        switch grouping {
        case .risk: return model.riskLabel(RiskLevel(rawValue: key) ?? .protected)
        case .category: return model.categoryLabel(ScanCategory(rawValue: key) ?? .unknown)
        case .source:
            if key == "Unknown source" { return model.t("source.unknown") }
            if key == "User file" { return model.t("source.userFile") }
            return key
        }
    }
}

struct ApplicationsView: View {
    @EnvironmentObject private var model: AppViewModel

    private var applicationItems: [CleanableItem] {
        model.items.filter { $0.scannerIdentifier == "scanner.applications" && $0.category == .applicationBundle }
    }

    private var exactCacheItems: [CleanableItem] {
        model.items.filter { $0.scannerIdentifier == "scanner.applications" && $0.category == .userCache }
    }

    private var leftoverItems: [CleanableItem] {
        model.items.filter { $0.scannerIdentifier == "scanner.application-leftovers" }
    }

    private var installerItems: [CleanableItem] {
        model.items.filter { $0.scannerIdentifier == "scanner.installers" }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        scopeDescription
                        Spacer(minLength: 24)
                        privacyLabel
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        scopeDescription
                        privacyLabel
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    compactMetric("applications.installed", items: applicationItems, symbol: "app")
                    compactMetric("applications.exactCaches", items: exactCacheItems, symbol: "bolt.horizontal.circle")
                    compactMetric("applications.leftovers", items: leftoverItems, symbol: "folder.badge.questionmark")
                    compactMetric("applications.installers", items: installerItems, symbol: "shippingbox")
                }
            }
            .padding(14)
            .background(.blue.opacity(0.06))
            Divider()
            FindingsView(
                titleKey: "section.applications",
                scannerIDs: ["scanner.applications", "scanner.application-leftovers", "scanner.installers"],
                groupBySource: true
            )
        }
        .navigationTitle(model.t("section.applications"))
    }

    private var scopeDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.t("applications.scopeTitle")).font(.headline)
            Text(model.t("applications.scopeHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyLabel: some View {
        Label(model.t("applications.localOnly"), systemImage: "hand.raised.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.blue)
    }

    private func compactMetric(_ key: String, items: [CleanableItem], symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t(key)).font(.caption).foregroundStyle(.secondary)
                Text(model.formatBytes(items.reduce(0) { $0 + $1.allocatedSize }))
                    .font(.headline).monospacedDigit()
            }
            Spacer(minLength: 4)
            Text(items.count.formatted(.number.locale(model.language.locale)))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SystemDataView: View {
    @EnvironmentObject private var model: AppViewModel
    var body: some View {
        VStack(spacing: 0) {
            Text(model.t("systemData.explanation"))
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(.blue.opacity(0.08))
            FindingsView(
                titleKey: "section.systemData",
                categories: [.userCache, .userLog, .xcodeDerivedData, .xcodeArchive, .xcodeDeviceSupport, .simulatorData, .developerCache, .iosBackup, .installer, .trash]
            )
        }
    }
}

struct DeveloperStorageView: View {
    var body: some View {
        FindingsView(
            titleKey: "section.developerStorage",
            categories: [.xcodeDerivedData, .xcodeArchive, .xcodeDeviceSupport, .simulatorData, .developerCache]
        )
    }
}

struct LargeFilesView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { locationHeading; Spacer(); addButton }
                    VStack(alignment: .leading, spacing: 8) { locationHeading; addButton }
                }
                if model.authorizedFolders.isEmpty {
                    Text(model.t("largeFiles.downloadsOnly")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(model.authorizedFolders, id: \.path) { folder in
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                    Text(verbatim: folder.path).lineLimit(1)
                                    Button { model.removeAuthorizedFolder(folder) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(model.t("action.removeScanLocation"))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(.blue.opacity(0.06))
            Divider()
            FindingsView(titleKey: "section.largeFiles", categories: [.largeFile, .installer])
        }
        .navigationTitle(model.t("section.largeFiles"))
    }

    private var locationHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.t("largeFiles.locations")).font(.headline)
            Text(model.t("largeFiles.locationsHelp")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var addButton: some View {
        Button(model.t("action.addScanLocation")) { model.addAuthorizedFolder() }
    }
}

struct CleanupResultView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.t(model.dryRun ? "cleanup.simulationResults" : "cleanup.results"))
                .font(.title2.weight(.semibold))
            if model.cleanupResults.isEmpty {
                ProgressView(model.t("cleanup.inProgress")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.cleanupResults) { result in
                    HStack {
                        Image(systemName: result.status == .failed ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(result.status == .failed ? .red : .green)
                        VStack(alignment: .leading) {
                            Text(verbatim: result.originalURL.lastPathComponent)
                            Text(model.localizedMessage(result.message)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(model.cleanupStatusLabel(result.status))
                    }
                }
            }
            HStack { Spacer(); Button(model.t("action.done")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 620, maxWidth: 700, minHeight: 340, idealHeight: 400, maxHeight: 560)
    }
}
