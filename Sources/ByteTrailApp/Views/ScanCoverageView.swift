import ByteTrailCore
import SwiftUI

private enum CoverageFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case scanned
    case noFindings
    case notFound
    case permissionDenied
    case partial
    case disabled
    case cancelled

    var id: String { rawValue }

    var status: ScanCoverageStatus? {
        self == .all ? nil : ScanCoverageStatus(rawValue: rawValue)
    }
}

struct ScanCoverageView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var filter: CoverageFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if model.scanCoverage.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                summary
                filterBar
                Divider()
                List(filteredEntries) { entry in
                    CoverageRow(entry: entry)
                        .environmentObject(model)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .detailPaneStyle()
        .navigationTitle(model.t("section.coverage"))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.t("coverage.title"))
                .font(.largeTitle.weight(.semibold))
            Text(model.t("coverage.explanation"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(
                title: model.t("coverage.summary.locations"),
                value: model.scanCoverage.count.formatted(.number.locale(model.language.locale)),
                detail: nil,
                symbol: "folder"
            )
            MetricCard(
                title: model.t("coverage.summary.withFindings"),
                value: locationsWithFindings.formatted(.number.locale(model.language.locale)),
                detail: nil,
                symbol: "checkmark.circle"
            )
            MetricCard(
                title: model.t("coverage.summary.noFindings"),
                value: count(.noFindings).formatted(.number.locale(model.language.locale)),
                detail: nil,
                symbol: "checkmark.shield"
            )
            MetricCard(
                title: model.t("coverage.summary.needsAttention"),
                value: attentionCount.formatted(.number.locale(model.language.locale)),
                detail: nil,
                symbol: "exclamationmark.triangle"
            )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    private var filterBar: some View {
        HStack {
            Text(model.t("coverage.filter.label"))
                .foregroundStyle(.secondary)
            Picker(model.t("coverage.filter.label"), selection: $filter) {
                ForEach(CoverageFilter.allCases) { option in
                    Text(filterLabel(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer()
            Text(model.t("coverage.visibleCount", filteredEntries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(model.t("coverage.empty.title"))
                .font(.title3.weight(.semibold))
            Text(model.t("coverage.empty.help"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(model.t("action.scan")) { model.startScan() }
                .disabled(model.isScanning)
        }
        .padding(30)
    }

    private var filteredEntries: [ScanCoverageEntry] {
        model.scanCoverage
            .filter { filter.status == nil || $0.status == filter.status }
            .sorted {
                let leftName = model.scannerName($0.scannerName)
                let rightName = model.scannerName($1.scannerName)
                if leftName != rightName { return leftName.localizedStandardCompare(rightName) == .orderedAscending }
                return $0.standardizedPath.localizedStandardCompare($1.standardizedPath) == .orderedAscending
            }
    }

    private var attentionCount: Int {
        model.scanCoverage.filter {
            $0.status == .permissionDenied || $0.status == .partial || $0.status == .cancelled
        }.count
    }

    private var locationsWithFindings: Int {
        model.scanCoverage.filter { $0.findingCount > 0 }.count
    }

    private func count(_ status: ScanCoverageStatus) -> Int {
        model.scanCoverage.filter { $0.status == status }.count
    }

    private func filterLabel(_ option: CoverageFilter) -> String {
        guard let status = option.status else { return model.t("coverage.filter.all") }
        return model.coverageStatusLabel(status)
    }
}

private struct CoverageRow: View {
    let entry: ScanCoverageEntry
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                location
                Spacer(minLength: 16)
                findings
                statusBadge
            }
            VStack(alignment: .leading, spacing: 10) {
                location
                HStack {
                    findings
                    Spacer()
                    statusBadge
                }
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.scannerName(entry.scannerName))
                .font(.headline)
            Text(verbatim: entry.standardizedPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            if let message = entry.message {
                Text(model.localizedMessage(message))
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var findings: some View {
        Text(model.t("coverage.findingCount", entry.findingCount))
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var statusBadge: some View {
        Label(model.coverageStatusLabel(entry.status), systemImage: statusSymbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.13), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch entry.status {
        case .scanned: return .green
        case .noFindings: return .blue
        case .pending: return .secondary
        case .notFound, .disabled, .cancelled: return .secondary
        case .permissionDenied, .partial: return .orange
        }
    }

    private var statusSymbol: String {
        switch entry.status {
        case .pending: return "clock"
        case .scanned: return "checkmark.circle.fill"
        case .noFindings: return "checkmark.shield"
        case .notFound: return "questionmark.folder"
        case .permissionDenied: return "lock.fill"
        case .partial: return "exclamationmark.triangle"
        case .disabled: return "pause.circle"
        case .cancelled: return "xmark.circle"
        }
    }
}
