import Foundation

public struct InstallerScanner: ScannerProtocol {
    public let identifier = "scanner.installers"
    public let displayName = "Downloaded Installers"
    public init() {}

    public func coverageLocations(context: ScanContext) -> [ScanCoverageLocation] {
        [coverageLocation(context.homeDirectory.appendingPathComponent("Downloads", isDirectory: true))]
    }

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let producer = Task.detached {
                guard let rule = context.ruleEngine.rule(identifier: "installer.download"), let root = rule.expandedRoots(homeDirectory: context.homeDirectory).first,
                      FileManager.default.fileExists(atPath: root.path) else { continuation.yield(.finished(scannerIdentifier: identifier)); continuation.finish(); return }
                do {
                    let children = try ScannerSupport.children(of: root, showHidden: context.settings.showHiddenFiles)
                    var found = 0
                    for (index, child) in children.enumerated() {
                        if Task.isCancelled { break }
                        let ext = child.pathExtension.lowercased()
                        guard ext == "dmg" || ext == "pkg" else { continue }
                        continuation.yield(.progress(ScanProgress(scannerName: displayName, category: rule.category.label, currentPath: child.path, filesInspected: index, findings: found)))
                        do {
                            var item = try await ScannerSupport.makeItem(candidate: child, root: root, rule: rule, scannerIdentifier: identifier, context: context)
                            item.selected = false
                            continuation.yield(.finding(item)); found += 1
                        } catch { continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: child, error: error))) }
                    }
                } catch { continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: root, error: error))) }
                continuation.yield(.finished(scannerIdentifier: identifier)); continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}
