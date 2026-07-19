import Foundation

public struct LogScanner: ScannerProtocol {
    public let identifier = "scanner.user-logs"
    public let displayName = "Application Logs"
    public init() {}

    public func coverageLocations(context: ScanContext) -> [ScanCoverageLocation] {
        [coverageLocation(context.homeDirectory.appendingPathComponent("Library/Logs", isDirectory: true))]
    }

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let producer = Task.detached {
                guard let oldRule = context.ruleEngine.rule(identifier: "logs.user-old"),
                      let recentRule = context.ruleEngine.rule(identifier: "logs.user-recent"),
                      let root = oldRule.expandedRoots(homeDirectory: context.homeDirectory).first else {
                    continuation.yield(.issue(ScanIssue(scannerIdentifier: identifier, path: "~/Library/Logs", message: "The log rules are unavailable.", permissionStatus: .unavailable)))
                    continuation.finish(); return
                }
                guard FileManager.default.fileExists(atPath: root.path) else { continuation.yield(.finished(scannerIdentifier: identifier)); continuation.finish(); return }
                do {
                    let children = try ScannerSupport.children(of: root, showHidden: context.settings.showHiddenFiles)
                    for (index, child) in children.enumerated() {
                        if Task.isCancelled { break }
                        let values = try? child.resourceValues(forKeys: [.contentModificationDateKey])
                        let cutoff = Calendar.current.date(byAdding: .day, value: -context.settings.logAgeDays, to: Date()) ?? .distantPast
                        let rule = (values?.contentModificationDate ?? Date()) < cutoff ? oldRule : recentRule
                        continuation.yield(.progress(ScanProgress(scannerName: displayName, category: rule.category.label, currentPath: child.path, filesInspected: index, findings: index)))
                        do {
                            let item = try await ScannerSupport.makeItem(candidate: child, root: root, rule: rule, scannerIdentifier: identifier, context: context)
                            if !ScannerSupport.isExcluded(child, source: item.provenance.producedByName, settings: context.settings) { continuation.yield(.finding(item)) }
                        } catch is CancellationError { break }
                        catch { continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: child, error: error))) }
                    }
                } catch { continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: root, error: error))) }
                continuation.yield(.finished(scannerIdentifier: identifier)); continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}
