import ByteTrailCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $model.selection) { section in
                Label(model.t(section.localizationKey), systemImage: section.symbol)
                    .tag(section)
                    .accessibilityLabel(model.t(section.localizationKey))
            }
            .navigationTitle(AppConfiguration.productName)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.t("app.tagline")).font(.caption).fontWeight(.medium)
                    Text(model.t("app.localPrivacy")).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        } detail: {
            Group {
                switch model.selection ?? .overview {
                case .overview: OverviewView()
                case .cleanup: FindingsView(titleKey: "section.cleanup")
                case .systemData: SystemDataView()
                case .developerStorage: DeveloperStorageView()
                case .largeFiles: LargeFilesView()
                case .trash: FindingsView(titleKey: "section.trash", categories: [.trash])
                case .history: HistoryView()
                case .settings: SettingsView()
                }
            }
            .toolbar { ScanToolbar() }
        }
        .alert(model.t("alert.rules.title"), isPresented: Binding(
            get: { model.configurationError != nil },
            set: { if !$0 { model.configurationError = nil } }
        )) {
            Button(model.t("action.ok"), role: .cancel) {}
        } message: {
            Text(model.configurationError.map(model.localizedMessage) ?? model.t("message.unknownConfiguration"))
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
