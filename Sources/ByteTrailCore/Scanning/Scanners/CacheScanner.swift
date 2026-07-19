import Foundation

public struct CacheScanner: ScannerProtocol {
    public let identifier = "scanner.user-cache"
    public let displayName = "Application Caches"
    public init() {}

    public func coverageLocations(context: ScanContext) -> [ScanCoverageLocation] {
        let library = context.homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            library.appendingPathComponent("Caches", isDirectory: true),
            library.appendingPathComponent("Containers", isDirectory: true),
            library.appendingPathComponent("Group Containers", isDirectory: true)
        ].map(coverageLocation)
    }

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let producer = Task.detached {
                guard let baseRule = context.ruleEngine.rule(identifier: "cache.user-app") else {
                    continuation.yield(.issue(ScanIssue(
                        scannerIdentifier: identifier,
                        path: "~/Library/Caches",
                        message: "The cache rule is unavailable.",
                        permissionStatus: .unavailable
                    )))
                    continuation.finish()
                    return
                }

                var inspected = 0
                var findings = 0
                let directRoot = context.homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true)
                await scanDirectChildren(
                    of: directRoot,
                    rule: baseRule,
                    context: context,
                    inspected: &inspected,
                    findings: &findings,
                    continuation: continuation
                )

                let containersRoot = context.homeDirectory.appendingPathComponent("Library/Containers", isDirectory: true)
                await scanContainerCaches(
                    under: containersRoot,
                    groupContainer: false,
                    baseRule: baseRule,
                    context: context,
                    inspected: &inspected,
                    findings: &findings,
                    continuation: continuation
                )

                let groupsRoot = context.homeDirectory.appendingPathComponent("Library/Group Containers", isDirectory: true)
                await scanContainerCaches(
                    under: groupsRoot,
                    groupContainer: true,
                    baseRule: baseRule,
                    context: context,
                    inspected: &inspected,
                    findings: &findings,
                    continuation: continuation
                )

                continuation.yield(.finished(scannerIdentifier: identifier))
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    private func scanDirectChildren(
        of root: URL,
        rule: CleanupRule,
        context: ScanContext,
        inspected: inout Int,
        findings: inout Int,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        do {
            for child in try ScannerSupport.children(of: root, showHidden: context.settings.showHiddenFiles) {
                if Task.isCancelled { return }
                inspected += 1
                continuation.yield(.progress(ScanProgress(
                    scannerName: displayName,
                    category: rule.category.label,
                    currentPath: child.path,
                    filesInspected: inspected,
                    findings: findings
                )))
                do {
                    let item = try await ScannerSupport.makeItem(
                        candidate: child,
                        root: root,
                        rule: rule,
                        scannerIdentifier: identifier,
                        context: context
                    )
                    if !ScannerSupport.isExcluded(child, source: item.provenance.producedByName, settings: context.settings) {
                        continuation.yield(.finding(item))
                        findings += 1
                    }
                } catch is CancellationError {
                    return
                } catch {
                    continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: child, error: error)))
                }
            }
        } catch {
            continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: root, error: error)))
        }
    }

    private func scanContainerCaches(
        under root: URL,
        groupContainer: Bool,
        baseRule: CleanupRule,
        context: ScanContext,
        inspected: inout Int,
        findings: inout Int,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        do {
            for container in try ScannerSupport.children(of: root, showHidden: context.settings.showHiddenFiles) {
                if Task.isCancelled { return }
                let cache = groupContainer
                    ? container.appendingPathComponent("Library/Caches", isDirectory: true)
                    : container.appendingPathComponent("Data/Library/Caches", isDirectory: true)
                guard FileManager.default.fileExists(atPath: cache.path) else { continue }

                inspected += 1
                continuation.yield(.progress(ScanProgress(
                    scannerName: displayName,
                    category: baseRule.category.label,
                    currentPath: cache.path,
                    filesInspected: inspected,
                    findings: findings
                )))

                let containerIdentifier = container.lastPathComponent
                let source: ResolvedSource
                if groupContainer {
                    source = ResolvedSource(
                        name: containerIdentifier,
                        bundleIdentifier: nil,
                        sourceType: .application,
                        evidence: ["Matched a cache leaf inside a group container; no application ownership is assumed."],
                        confidence: .unknown
                    )
                } else {
                    source = await context.sourceResolver.resolve(bundleIdentifier: containerIdentifier, rule: baseRule)
                }

                let dynamicRule = cacheRule(
                    root: cache,
                    source: source,
                    groupContainer: groupContainer
                )
                do {
                    try RuleValidator().validate([dynamicRule], homeDirectory: context.homeDirectory)
                    let item = try await ScannerSupport.makeItem(
                        candidate: cache,
                        root: cache,
                        rule: dynamicRule,
                        scannerIdentifier: identifier,
                        context: context,
                        sourceOverride: source,
                        riskOverride: source.confidence == .confirmed ? .safe : .review,
                        embeddedRule: dynamicRule
                    )
                    if !ScannerSupport.isExcluded(cache, source: item.provenance.producedByName, settings: context.settings) {
                        continuation.yield(.finding(item))
                        findings += 1
                    }
                } catch is CancellationError {
                    return
                } catch FileValidationError.protectedPath {
                    continue
                } catch FileValidationError.containsProtectedDescendant {
                    continue
                } catch RuleValidationError.protectedApprovedRoot {
                    continue
                } catch {
                    continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: cache, error: error)))
                }
            }
        } catch {
            continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: root, error: error)))
        }
    }

    private func cacheRule(root: URL, source: ResolvedSource, groupContainer: Bool) -> CleanupRule {
        CleanupRule(
            id: "cache.\(groupContainer ? "group" : "sandbox").\(stableIdentifier(root.path))",
            displayName: groupContainer ? "Group Container Cache" : "Sandboxed Application Cache",
            producedBy: source.name,
            producedByIdentifier: source.bundleIdentifier,
            sourceType: .application,
            category: .userCache,
            approvedRoots: [root.standardizedFileURL.path],
            risk: source.confidence == .confirmed ? .safe : .review,
            regeneratable: true,
            cleanupMethod: .moveToTrash,
            reason: "Applications can recreate cache content when needed.",
            impact: "The source application may open more slowly while it recreates or downloads this cache.",
            evidence: groupContainer
                ? "Matched the exact Library/Caches leaf inside a group container."
                : "Matched the exact Data/Library/Caches leaf inside an application container.",
            whatItIs: "Temporary data stored by an application to avoid repeating work."
        )
    }

    private func stableIdentifier(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
