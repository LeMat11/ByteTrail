import Foundation

public struct DeveloperToolScanner: ScannerProtocol {
    public let identifier = "scanner.developer-tools"
    public let displayName = "Developer Tool Caches"
    private let ruleIDs = ["homebrew.download-cache", "npm.cache", "yarn.cache", "pnpm.store", "pip.cache", "conda.package-cache"]
    public init() {}

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let producer = Task.detached {
                var inspected = 0
                for ruleID in ruleIDs {
                    if Task.isCancelled { break }
                    guard let rule = context.ruleEngine.rule(identifier: ruleID), let root = rule.expandedRoots(homeDirectory: context.homeDirectory).first,
                          FileManager.default.fileExists(atPath: root.path) else { continue }
                    inspected += 1
                    continuation.yield(.progress(ScanProgress(scannerName: displayName, category: rule.category.label, currentPath: root.path, filesInspected: inspected, findings: inspected - 1)))
                    do {
                        let source = ResolvedSource(name: rule.producedBy, bundleIdentifier: rule.producedByIdentifier, sourceType: .developerTool, evidence: [rule.evidence], confidence: .confirmed)
                        continuation.yield(.finding(try await ScannerSupport.makeItem(candidate: root, root: root, rule: rule, scannerIdentifier: identifier, context: context, sourceOverride: source)))
                    } catch is CancellationError { break }
                    catch { continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: root, error: error))) }
                }
                continuation.yield(.finished(scannerIdentifier: identifier)); continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}
