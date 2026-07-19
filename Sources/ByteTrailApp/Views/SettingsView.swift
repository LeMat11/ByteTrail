import AppKit
import ByteTrailCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppViewModel

    private let scanners: [(String, String, String)] = [
        ("scanner.applications", "settings.scanner.applications", "settings.scanner.applications.help"),
        ("scanner.application-leftovers", "settings.scanner.leftovers", "settings.scanner.leftovers.help"),
        ("scanner.xcode", "settings.scanner.xcode", "settings.scanner.xcode.help"),
        ("scanner.developer-tools", "settings.scanner.developer", "settings.scanner.developer.help"),
        ("scanner.user-cache", "settings.scanner.cache", "settings.scanner.cache.help"),
        ("scanner.user-logs", "settings.scanner.logs", "settings.scanner.logs.help"),
        ("scanner.installers", "settings.scanner.installers", "settings.scanner.installers.help"),
        ("scanner.large-files", "settings.scanner.largeFiles", "settings.scanner.largeFiles.help"),
        ("scanner.trash", "settings.scanner.trash", "settings.scanner.trash.help"),
        ("scanner.ios-backups", "settings.scanner.backups", "settings.scanner.backups.help")
    ]

    var body: some View {
        Form {
            Section(model.t("settings.language")) {
                Picker(model.t("settings.appLanguage"), selection: $model.language) {
                    Text(model.t("language.system")).tag(AppLanguage.system)
                    Text("简体中文").tag(AppLanguage.zhHans)
                    Text("English").tag(AppLanguage.english)
                }
                .onChange(of: model.language) { _ in model.persistSettings() }
                Text(model.t("settings.languageHelp")).font(.caption).foregroundStyle(.secondary)
            }

            Section(model.t("settings.scanning")) {
                ForEach(scanners, id: \.0) { scanner in
                    Toggle(isOn: scannerBinding(scanner.0)) {
                        VStack(alignment: .leading) {
                            Text(model.t(scanner.1))
                            Text(model.t(scanner.2)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(model.t("settings.showHidden"), isOn: $model.showHiddenFiles)
                HStack {
                    Text(model.t("settings.largeThreshold"))
                    Slider(value: $model.largeFileMinimumGB, in: 0.1...20, step: 0.1)
                    Text(model.t("settings.gigabytes", model.largeFileMinimumGB)).monospacedDigit().frame(width: 72)
                }
                Stepper(model.t("settings.oldFileDays", model.oldFileAgeDays), value: $model.oldFileAgeDays, in: 7...730)
                Stepper(model.t("settings.logDays", model.logAgeDays), value: $model.logAgeDays, in: 14...365)
            }

            Section(model.t("largeFiles.locations")) {
                Text(model.t("settings.locationsHelp")).font(.caption).foregroundStyle(.secondary)
                ForEach(model.authorizedFolders, id: \.path) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text(verbatim: folder.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { model.removeAuthorizedFolder(folder) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                            .accessibilityLabel(model.t("action.removeScanLocation"))
                    }
                }
                Button(model.t("action.addScanLocation")) { model.addAuthorizedFolder() }
            }

            Section(model.t("settings.exclusions")) {
                Text(model.t("settings.exclusionCount", model.excludedPaths.count, model.excludedSources.count))
                HStack {
                    Button(model.t("action.excludeFolder")) { model.addExclusionFolder() }
                    Button(model.t("action.resetExclusions"), role: .destructive) { model.resetExclusions() }
                        .disabled(model.excludedPaths.isEmpty && model.excludedSources.isEmpty)
                }
            }

            #if DEBUG
            Section(model.t("settings.developmentSafety")) {
                Label(model.t("settings.debugDryRun"), systemImage: "checkmark.shield")
                Text(model.t("settings.debugDryRunHelp")).font(.caption).foregroundStyle(.secondary)
            }
            #endif

            Section(model.t("settings.historyRecovery")) {
                Stepper(model.t("settings.historyRetention", model.historyRetentionDays), value: $model.historyRetentionDays, in: 30...1095, step: 30)
                Stepper(model.t("settings.recoveryRetention", model.recoveryRetentionDays), value: $model.recoveryRetentionDays, in: 7...180)
                Text(model.t("settings.recoveryAwareness")).font(.caption).foregroundStyle(.secondary)
            }

            Section(model.t("settings.permissions")) {
                LabeledContent(model.t("settings.appSandbox"), value: model.t("settings.appSandboxValue"))
                LabeledContent(model.t("settings.fullDiskAccess"), value: model.t("settings.fullDiskAccessValue"))
                Button(model.t("action.openFullDiskAccess")) { model.openFullDiskAccessSettings() }
                Text(model.t("settings.permissionsHelp")).font(.caption).foregroundStyle(.secondary)
            }

            Section(model.t("settings.documentation")) {
                ViewThatFits(in: .horizontal) {
                    HStack { documentationButtons }
                    VStack(alignment: .leading) { documentationButtons }
                }
                Text("ByteTrail \(AppConfiguration.version) (\(AppConfiguration.build)) · \(model.t("app.tagline"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
        .navigationTitle(model.t("section.settings"))
        .onDisappear { model.persistSettings() }
    }

    private var documentationButtons: some View {
        Group {
            Button(model.t("action.openPrivacy")) { model.openDocumentation(named: "PRIVACY") }
            Button(model.t("action.openSafety")) { model.openDocumentation(named: "SAFETY_MODEL") }
        }
    }

    private func scannerBinding(_ id: String) -> Binding<Bool> {
        Binding {
            model.enabledScannerIDs.isEmpty || model.enabledScannerIDs.contains(id)
        } set: { enabled in
            if model.enabledScannerIDs.isEmpty { model.enabledScannerIDs = Set(scanners.map(\.0)) }
            if enabled { model.enabledScannerIDs.insert(id) } else { model.enabledScannerIDs.remove(id) }
        }
    }
}
