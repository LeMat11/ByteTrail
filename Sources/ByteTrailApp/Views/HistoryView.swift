import ByteTrailCore
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(model.t("history.title")).font(.largeTitle.weight(.semibold))
                    Text(model.t("history.subtitle")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.t("action.clearHistory"), role: .destructive) { showingClearConfirmation = true }.disabled(model.history.isEmpty)
            }.padding(22)
            Divider()
            if model.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary)
                    Text(model.t("history.empty")).font(.title3.weight(.semibold))
                    Text(model.t("history.emptyHelp")).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.history) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.result == .failed ? "xmark.circle" : "clock.arrow.circlepath")
                            .foregroundStyle(entry.result == .failed ? .red : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: entry.itemName).fontWeight(.medium)
                            Text(verbatim: "\(entry.producedBy) · \(entry.originalURL?.path ?? model.t("evidence.originalUnavailable"))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(model.formatBytes(entry.size)).monospacedDigit()
                            Text(model.formatDate(entry.date)).font(.caption).foregroundStyle(.secondary)
                        }
                        if entry.restoreAvailable {
                            Button(model.t("action.restore")) { model.restore(entry) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(model.t("history.title"))
        .task { await model.refreshPersistence() }
        .confirmationDialog(model.t("history.clearPrompt"), isPresented: $showingClearConfirmation) {
            Button(model.t("action.clearHistory"), role: .destructive) { model.clearHistory() }
            Button(model.t("action.cancel"), role: .cancel) {}
        } message: {
            Text(model.t("history.clearHelp"))
        }
    }
}
