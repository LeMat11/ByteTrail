import ByteTrailCore
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                    MetricCard(title: model.t("overview.totalCapacity"), value: model.formatBytes(model.storage.capacity), detail: nil, symbol: "internaldrive")
                    MetricCard(title: model.t("overview.used"), value: model.formatBytes(model.storage.used), detail: nil, symbol: "chart.pie.fill")
                    MetricCard(title: model.t("overview.available"), value: model.formatBytes(model.storage.available), detail: model.t("overview.reportedByMacOS"), symbol: "checkmark.circle")
                    MetricCard(title: model.t("overview.regeneratable"), value: model.formatBytes(model.safeBytes), detail: model.t("overview.reviewBeforeCleanup"), symbol: "arrow.triangle.2.circlepath")
                }
                if model.isScanning { ScanProgressView() }
                else if !model.items.isEmpty { summary }
                privacyCard
                if !model.issues.isEmpty { issueSummary }
            }
            .padding(20)
        }
        .navigationTitle(model.t("section.overview"))
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center) {
                overviewHeading
                Spacer()
                scanButton
            }
            VStack(alignment: .leading, spacing: 14) {
                overviewHeading
                scanButton
            }
        }
    }

    private var overviewHeading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.t("overview.heading")).font(.largeTitle.weight(.semibold))
            Text(model.t("overview.subheading"))
                .font(.title3).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scanButton: some View {
        Button { model.startScan() } label: {
            Label(model.t(model.items.isEmpty ? "action.scanStorage" : "action.scanAgain"), systemImage: "magnifyingglass")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.isScanning)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    summaryHeading
                    Spacer()
                    cleanupButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    summaryHeading
                    cleanupButton
                }
            }
            Divider()
            categoryLine("overview.safeRegeneratable", categories: [.userCache, .userLog, .xcodeDerivedData, .developerCache], symbol: "checkmark.shield")
            categoryLine("overview.developerData", categories: [.xcodeDerivedData, .xcodeArchive, .xcodeDeviceSupport, .simulatorData, .developerCache], symbol: "hammer")
            categoryLine("overview.installers", categories: [.installer], symbol: "shippingbox")
            categoryLine("section.trash", categories: [.trash], symbol: "trash")
            categoryLine("overview.largeFilesReview", categories: [.largeFile], symbol: "doc.text.magnifyingglass")
        }
        .padding(18).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var summaryHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.t("overview.foundReview", model.formatBytes(model.reviewBytes))).font(.title2.weight(.semibold))
            if let date = model.lastScanDate {
                Text(model.t("overview.lastScan", model.formatDate(date))).foregroundStyle(.secondary)
            }
        }
    }

    private var cleanupButton: some View {
        Button(model.t("section.cleanup")) { model.selection = .cleanup }
            .buttonStyle(.borderedProminent)
    }

    private func categoryLine(_ key: String, categories: Set<ScanCategory>, symbol: String) -> some View {
        let matching = model.items.filter { categories.contains($0.category) }
        return HStack {
            Label(model.t(key), systemImage: symbol)
            Spacer()
            Text(model.formatBytes(matching.reduce(0) { $0 + $1.allocatedSize })).monospacedDigit()
            Text(matching.count.formatted(.number.locale(model.language.locale))).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
        }
    }

    private var privacyCard: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.t("overview.localDesign")).font(.headline)
                Text(model.t("overview.localDesignHelp")).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "hand.raised.fill").foregroundStyle(.blue)
        }
        .padding(16).background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var issueSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.t("overview.sourcesUnavailable"), systemImage: "exclamationmark.circle").font(.headline)
            ForEach(model.issues.prefix(5)) { issue in
                Text(verbatim: "\(issue.path): \(model.localizedMessage(issue.message))")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(16).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ScanProgressView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.t("scan.scanningCategory", model.progressCategory(model.progress.category)), systemImage: "magnifyingglass")
                    .font(.headline)
                Spacer()
                Text(model.t("scan.seconds", Int(now.timeIntervalSince(model.progress.startedAt))))
                Button(model.t("action.cancel"), role: .cancel) { model.cancelScan() }
            }
            ProgressView()
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(model.scannerName(model.progress.scannerName))
                    Spacer()
                    scanMetrics
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.scannerName(model.progress.scannerName))
                    scanMetrics
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let path = model.progress.currentPath {
                Text(verbatim: path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(16).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .onReceive(timer) { now = $0 }
    }

    private var scanMetrics: some View {
        HStack {
            Text(model.t("scan.inspected", model.progress.filesInspected))
            Text(model.t("scan.findings", model.items.count))
            Text(model.formatBytes(model.reviewBytes))
        }
    }
}
