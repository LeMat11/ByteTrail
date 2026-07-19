import ByteTrailCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var sidebarSelection: SidebarSection? = .overview

    var body: some View {
        HSplitView {
            sidebar
            NavigationStack {
                detail
                    .toolbar { ScanToolbar() }
            }
            .frame(minWidth: 390, maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(model.t("alert.rules.title"), isPresented: Binding(
            get: { model.configurationError != nil },
            set: { if !$0 { model.configurationError = nil } }
        )) {
            Button(model.t("action.ok"), role: .cancel) {}
        } message: {
            Text(model.configurationError.map(model.localizedMessage) ?? model.t("message.unknownConfiguration"))
        }
        .onChange(of: sidebarSelection) { newValue in
            let normalizedSelection = newValue ?? .overview
            if model.selection != normalizedSelection {
                model.selection = normalizedSelection
            }
        }
        .onChange(of: model.selection) { newValue in
            if sidebarSelection != newValue {
                sidebarSelection = newValue
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Text(AppConfiguration.productName)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            List(SidebarSection.allCases, selection: $sidebarSelection) { section in
                Label(model.t(section.localizationKey), systemImage: section.symbol)
                    .tag(section)
                    .accessibilityLabel(model.t(section.localizationKey))
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(model.t("app.tagline")).font(.caption).fontWeight(.medium)
                Text(model.t("app.localPrivacy")).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .frame(minWidth: 170, idealWidth: 180, maxWidth: 240, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private var detail: some View {
        switch sidebarSelection ?? .overview {
        case .overview: OverviewView()
        case .applications: ApplicationsView()
        case .cleanup: FindingsView(titleKey: "section.cleanup")
        case .systemData: SystemDataView()
        case .developerStorage: DeveloperStorageView()
        case .largeFiles: LargeFilesView()
        case .trash: TrashView()
        case .coverage: ScanCoverageView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

private struct ScanToolbar: ToolbarContent {
    @EnvironmentObject private var model: AppViewModel
    var body: some ToolbarContent {
        ToolbarItemGroup {
            if model.isScanning {
                ProgressView().controlSize(.small)
                Button(model.t("action.cancel"), role: .cancel) { model.cancelScan() }
            } else {
                Button { model.startScan() } label: { Label(model.t("action.scan"), systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
