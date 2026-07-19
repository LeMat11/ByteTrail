import Foundation

public struct IOSBackupScanner: ScannerProtocol {
    public let identifier = "scanner.ios-backups"
    public let displayName = "iPhone & iPad Backups"
    public init() {}

    public func coverageLocations(context: ScanContext) -> [ScanCoverageLocation] {
        [coverageLocation(context.homeDirectory.appendingPathComponent("Library/Application Support/MobileSync/Backup", isDirectory: true))]
    }

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let producer = Task.detached {
                guard let rule = context.ruleEngine.rule(identifier: "ios.local-backup"), let root = rule.expandedRoots(homeDirectory: context.homeDirectory).first,
                      FileManager.default.fileExists(atPath: root.path) else { continuation.yield(.finished(scannerIdentifier: identifier)); continuation.finish(); return }
                do {
                    for (index, child) in try ScannerSupport.children(of: root, showHidden: true).enumerated() {
                        if Task.isCancelled { break }
                        continuation.yield(.progress(ScanProgress(scannerName: displayName, category: rule.category.label, currentPath: child.path, filesInspected: index, findings: index)))
                        do {
                            var item = try await ScannerSupport.makeItem(candidate: child, root: root, rule: rule, scannerIdentifier: identifier, context: context)
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
