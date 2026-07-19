import Foundation

public struct TrashScanner: ScannerProtocol {
    public let identifier = "scanner.trash"
    public let displayName = "Trash"
    public init() {}

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let producer = Task.detached {
                guard let rule = context.ruleEngine.rule(identifier: "trash.user-item"), let root = rule.expandedRoots(homeDirectory: context.homeDirectory).first else {
                    continuation.finish(); return
                }
                guard FileManager.default.fileExists(atPath: root.path) else { continuation.yield(.finished(scannerIdentifier: identifier)); continuation.finish(); return }
                do {
                    for (index, child) in try ScannerSupport.children(of: root, showHidden: context.settings.showHiddenFiles).enumerated() {
                        if Task.isCancelled { break }
                        continuation.yield(.progress(ScanProgress(scannerName: displayName, category: rule.category.label, currentPath: child.path, filesInspected: index, findings: index)))
                        do {
                            var item = try await ScannerSupport.makeItem(candidate: child, root: root, rule: rule, scannerIdentifier: identifier, context: context)
                            item.provenance.originalURL = nil
                            item.provenance.evidence.append("Original location unavailable")
                            item.selected = false
                            continuation.yield(.finding(item))
                        } catch { continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: child, error: error))) }
                    }
                } catch { continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: root, error: error))) }
                continuation.yield(.finished(scannerIdentifier: identifier)); continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}
