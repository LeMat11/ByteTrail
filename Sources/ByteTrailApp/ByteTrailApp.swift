import ByteTrailCore
import SwiftUI

@main
struct ByteTrailApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.locale, model.language.locale)
                .id(model.language.rawValue)
                .frame(minWidth: 680, idealWidth: 1120, minHeight: 500, idealHeight: 760)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu(model.t("menu.scan")) {
                Button(model.t("action.scanStorage")) { model.startScan() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(model.isScanning)
                Button(model.t("action.cancelScan")) { model.cancelScan() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!model.isScanning)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environment(\.locale, model.language.locale)
                .id(model.language.rawValue)
                .frame(minWidth: 480, idealWidth: 620, minHeight: 480, idealHeight: 620)
        }
    }
}
