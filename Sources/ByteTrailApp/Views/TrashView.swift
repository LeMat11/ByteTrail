import ByteTrailCore
import SwiftUI

struct TrashView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var showingConfirmation = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()
                FindingsView(
                    titleKey: "section.trash",
                    categories: [.trash],
                    allowsCleanupSelection: false
                )
            }

            if let result = model.trashEmptyingResult {
                Color.black.opacity(0.2).ignoresSafeArea()
                    .transition(.opacity)
                TrashCompletionCard(result: result) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        model.dismissTrashEmptyingResult()
                    }
                }
                .environmentObject(model)
                .transition(.scale(scale: 0.84).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.trashEmptyingResult != nil)
        .navigationTitle(model.t("section.trash"))
        .onAppear { model.refreshTrash() }
        .alert(model.t("trash.confirm.title"), isPresented: $showingConfirmation) {
            Button(model.t("action.cancel"), role: .cancel) {}
            Button(model.t("trash.action.empty"), role: .destructive) {
                _ = model.emptyTrash()
            }
        } message: {
            Text(model.t(
                "trash.confirm.message",
                model.trashItems.count,
                model.formatBytes(model.trashBytes)
            ))
        }
        .alert(model.t("trash.error.title"), isPresented: Binding(
            get: { model.trashEmptyingError != nil },
            set: { if !$0 { model.trashEmptyingError = nil } }
        )) {
            Button(model.t("action.ok"), role: .cancel) {}
        } message: {
            Text(model.trashEmptyingError.map(model.localizedMessage) ?? model.t("trash.error.unknown"))
        }
        .detailPaneStyle()
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 18) {
                headerCopy
                Spacer(minLength: 24)
                emptyButton
            }
            VStack(alignment: .leading, spacing: 12) {
                headerCopy
                emptyButton.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .background(DetailTheme.panelBackground)
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill").foregroundStyle(.secondary)
                Text(model.t("trash.summary", model.trashItems.count, model.formatBytes(model.trashBytes)))
                    .font(.headline)
                    .monospacedDigit()
            }
            Text(model.t("trash.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.dryRun {
                Label(model.t("trash.debugDisabled"), systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var emptyButton: some View {
        Button(role: .destructive) {
            showingConfirmation = true
        } label: {
            if model.isEmptyingTrash {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.t("trash.emptying"))
                }
            } else {
                Label(model.t("trash.action.empty"), systemImage: "trash.slash")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(model.trashItems.isEmpty || model.isEmptyingTrash || model.dryRun)
    }
}

private struct TrashCompletionCard: View {
    let result: TrashEmptyingResult
    let dismiss: () -> Void
    @EnvironmentObject private var model: AppViewModel
    @State private var burst = false

    var body: some View {
        VStack(spacing: 16) {
            celebration
                .frame(width: 150, height: 120)

            Text(model.t(result.failures.isEmpty ? "trash.result.title" : "trash.result.partialTitle"))
                .font(.title2.weight(.bold))

            Text(model.formatBytes(result.bytesFreed))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
                .monospacedDigit()

            Text(model.t("trash.result.detail", result.removedItemCount))
                .foregroundStyle(.secondary)

            if !result.failures.isEmpty {
                Text(model.t("trash.result.failures", result.failures.count))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button(model.t("action.done"), action: dismiss)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 30)
        .frame(minWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 26, y: 12)
        .onAppear {
            withAnimation(.easeOut(duration: 1.05)) { burst = true }
        }
    }

    private var celebration: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { index in
                let angle = Double(index) / 16.0 * Double.pi * 2
                let distance = CGFloat(48 + (index % 3) * 9)
                Capsule()
                    .fill([Color.green, .mint, .blue, .yellow][index % 4])
                    .frame(width: 7, height: 14)
                    .rotationEffect(.radians(angle + (burst ? 1.2 : 0)))
                    .offset(
                        x: burst ? CGFloat(cos(angle)) * distance : 0,
                        y: burst ? CGFloat(sin(angle)) * distance : 0
                    )
                    .opacity(burst ? 0 : 1)
            }

            Circle()
                .fill(Color.green.opacity(0.15))
                .frame(width: burst ? 104 : 56, height: burst ? 104 : 56)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 62, weight: .semibold))
                .foregroundStyle(.green)
                .scaleEffect(burst ? 1 : 0.45)
                .rotationEffect(.degrees(burst ? 0 : -18))
        }
    }
}
