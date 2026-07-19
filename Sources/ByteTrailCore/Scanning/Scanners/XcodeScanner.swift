import Foundation

public struct XcodeScanner: ScannerProtocol {
    public let identifier = "scanner.xcode"
    public let displayName = "Xcode Storage"
    private let ruleIDs = ["xcode.derived-data", "xcode.archives", "xcode.device-support", "xcode.simulator-caches"]
    public init() {}

    public func coverageLocations(context: ScanContext) -> [ScanCoverageLocation] {
        ruleIDs.compactMap { ruleID in
            context.ruleEngine.rule(identifier: ruleID)?.expandedRoots(homeDirectory: context.homeDirectory).first
        }.map(coverageLocation)
    }

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let producer = Task.detached {
                var inspected = 0
                for ruleID in ruleIDs {
                    if Task.isCancelled { break }
                    guard let rule = context.ruleEngine.rule(identifier: ruleID), let root = rule.expandedRoots(homeDirectory: context.homeDirectory).first else { continue }
                    guard FileManager.default.fileExists(atPath: root.path) else { continue }
                    do {
                        for child in try ScannerSupport.children(of: root, showHidden: context.settings.showHiddenFiles) {
                            if Task.isCancelled { break }
                            inspected += 1
                            continuation.yield(.progress(ScanProgress(scannerName: displayName, category: rule.category.label, currentPath: child.path, filesInspected: inspected, findings: 0)))
                            do { continuation.yield(.finding(try await ScannerSupport.makeItem(candidate: child, root: root, rule: rule, scannerIdentifier: identifier, context: context))) }
                            catch is CancellationError { break }
                            catch { continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: child, error: error))) }
                        }
                    } catch { continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: root, error: error))) }
                }
                continuation.yield(.finished(scannerIdentifier: identifier)); continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}
