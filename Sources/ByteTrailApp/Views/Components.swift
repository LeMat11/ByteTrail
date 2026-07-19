import AppKit
import ByteTrailCore
import SwiftUI

enum DetailTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let panelBackground = Color(nsColor: .controlBackgroundColor)
}

private struct DetailPaneStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .background(DetailTheme.background)
    }
}

extension View {
    func detailPaneStyle() -> some View {
        modifier(DetailPaneStyle())
    }
}

struct FindingIcon: View {
    let item: CleanableItem
    let size: CGFloat

    var body: some View {
        Group {
            if let reference = item.sourceIconReference, reference.hasPrefix("/") {
                Image(nsImage: NSWorkspace.shared.icon(forFile: reference))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: symbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch item.category {
        case .applicationBundle: return "app"
        case .applicationLeftover: return "folder.badge.questionmark"
        case .xcodeDerivedData, .xcodeArchive, .xcodeDeviceSupport, .simulatorData: return "hammer"
        case .developerCache: return "terminal"
        case .trash: return "trash"
        case .largeFile: return "doc.text.magnifyingglass"
        case .installer: return "shippingbox"
        case .iosBackup: return "iphone"
        case .userCache: return "bolt.horizontal.circle"
        case .userLog: return "doc.text"
        case .unknown: return "folder"
        }
    }
}

struct RiskBadge: View {
    let risk: RiskLevel
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Label(model.riskLabel(risk), systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.13), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel(model.t("accessibility.risk", model.riskLabel(risk)))
    }

    private var color: Color {
        switch risk { case .safe: return .green; case .review: return .orange; case .protected: return .red }
    }
    private var symbol: String {
        switch risk { case .safe: return "checkmark.shield"; case .review: return "exclamationmark.triangle"; case .protected: return "lock.shield" }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String?
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(verbatim: value).font(.title2.weight(.semibold)).monospacedDigit()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DetailTheme.panelBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct EmptyFindingsView: View {
    let scanning: Bool
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: scanning ? "magnifyingglass" : "checkmark.circle")
                .font(.system(size: 36)).foregroundStyle(.secondary)
            Text(model.t(scanning ? "empty.scanning" : "empty.noFindings")).font(.title3.weight(.semibold))
            Text(model.t(scanning ? "empty.scanningHelp" : "empty.noFindingsHelp"))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(30)
    }
}

struct EvidenceDetailView: View {
    let item: CleanableItem
    var showsCloseButton = false
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if showsCloseButton {
                HStack {
                    Text(model.t("evidence.details")).font(.headline)
                    Spacer()
                    Button(model.t("action.close")) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        evidenceHeading
                        Spacer()
                        RiskBadge(risk: item.riskLevel)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        evidenceHeading
                        RiskBadge(risk: item.riskLevel)
                    }
                }
                Divider()
                EvidenceField(title: model.t("evidence.producedBy"), value: model.sourceName(item))
                if let identifier = item.provenance.producedByIdentifier {
                    EvidenceField(title: model.t("evidence.bundleID"), value: identifier, monospaced: true)
                }
                if let applicationURL = item.provenance.sourceApplicationURL {
                    EvidenceField(title: model.t("evidence.applicationLocation"), value: applicationURL.path, monospaced: true)
                }
                EvidenceField(title: model.t("evidence.category"), value: model.categoryLabel(item.category))
                EvidenceField(title: model.t("evidence.locatedAt"), value: item.standardizedPath, monospaced: true)
                EvidenceField(
                    title: model.t("evidence.originallyFrom"),
                    value: item.provenance.originalURL?.path ?? model.t("evidence.originalUnavailable"),
                    monospaced: true
                )
                EvidenceField(title: model.t("evidence.whatItIs"), value: model.ruleText(item, field: "what"))
                EvidenceField(title: model.t("evidence.whyRemovable"), value: model.ruleText(item, field: "reason"))
                EvidenceField(title: model.t("evidence.afterRemoval"), value: model.ruleText(item, field: "impact"))
                EvidenceField(title: model.t("evidence.detectedBecause"), value: model.ruleText(item, field: "evidence"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 16) {
                    EvidenceField(title: model.t("evidence.attribution"), value: model.confidenceLabel(item.provenance.confidence))
                    EvidenceField(title: model.t("evidence.regeneratable"), value: model.t(item.regeneratable ? "value.yes" : "value.no"))
                    EvidenceField(title: model.t("evidence.cleanup"), value: model.cleanupMethodLabel(item.cleanupMethod))
                    EvidenceField(title: model.t("evidence.logicalSize"), value: model.formatBytes(item.size))
                    EvidenceField(title: model.t("evidence.allocatedSize"), value: model.formatBytes(item.allocatedSize))
                    EvidenceField(title: model.t("evidence.files"), value: item.fileCount.formatted(.number.locale(model.language.locale)))
                }
                EvidenceField(
                    title: model.t("evidence.lastModified"),
                    value: item.modifiedDate.map(model.formatDate) ?? model.t("value.unavailable")
                )
                if model.isSourceRunning(item) {
                    Label(model.t("cache.runningCleanupBlocked"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                ViewThatFits(in: .horizontal) {
                    evidenceActions
                    VStack(alignment: .leading) { evidenceActions }
                }
                }
                .padding(20)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.t("accessibility.cleanupEvidence", item.displayName))
    }

    private var evidenceHeading: some View {
        HStack(alignment: .top) {
            FindingIcon(item: item, size: 42)
            VStack(alignment: .leading) {
                Text(verbatim: item.displayName).font(.title2.weight(.semibold))
                Text(verbatim: model.sourceName(item)).foregroundStyle(.secondary)
            }
        }
    }

    private var evidenceActions: some View {
        HStack {
            Button(model.t("action.revealFinder")) { model.reveal(item) }
            Button(model.t("action.excludePath")) { model.exclude(item) }
            Button(model.t("action.excludeSourceShort")) { model.excludeSource(item.provenance.producedByName) }
        }
    }

}

private struct EvidenceField: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(verbatim: value).font(monospaced ? .system(.body, design: .monospaced) : .body).textSelection(.enabled)
        }
    }
}
