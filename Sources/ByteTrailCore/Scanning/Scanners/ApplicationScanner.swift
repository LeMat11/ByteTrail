import Foundation

public struct ApplicationScanner: ScannerProtocol {
    public let identifier = "scanner.applications"
    public let displayName = "Applications"

    public init() {}

    public func coverageLocations(context: ScanContext) -> [ScanCoverageLocation] {
        let pathPolicy = ApplicationPathPolicy(homeDirectory: context.homeDirectory)
        let cacheRoot = context.homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true)
        return (pathPolicy.inventoryRoots + [cacheRoot]).map(coverageLocation)
    }

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let producer = Task.detached {
                let applications = await context.applicationResolver.allApplications()
                let pathPolicy = ApplicationPathPolicy(homeDirectory: context.homeDirectory)
                var inspected = 0
                var findings = 0

                for application in applications {
                    if Task.isCancelled { break }
                    inspected += 1
                    continuation.yield(.progress(ScanProgress(
                        scannerName: displayName,
                        category: ScanCategory.applicationBundle.label,
                        currentPath: application.url.path,
                        filesInspected: inspected,
                        findings: findings
                    )))

                    let isSystem = pathPolicy.isSystemApplication(application.url)
                    let isSelf = application.bundleIdentifier == AppConfiguration.bundleIdentifier
                    let isWritable = applicationIsWritable(application.url)
                    let protected = isSystem || isSelf
                    let source = ResolvedSource(
                        name: application.name,
                        bundleIdentifier: application.bundleIdentifier,
                        sourceType: isSystem ? .systemComponent : .application,
                        evidence: ["Bundle identifier read from the installed application bundle."],
                        confidence: .confirmed,
                        applicationURL: application.url
                    )
                    let bundleRule = applicationRule(
                        application: application,
                        protected: protected,
                        writable: isWritable
                    )

                    do {
                        try RuleValidator().validate([bundleRule], homeDirectory: context.homeDirectory)
                        var item = try await ScannerSupport.makeItem(
                            candidate: application.url,
                            root: application.url,
                            rule: bundleRule,
                            scannerIdentifier: identifier,
                            context: context,
                            sourceOverride: source,
                            riskOverride: protected ? .protected : .review,
                            traversePackageDescendants: true,
                            embeddedRule: bundleRule
                        )
                        item.displayName = application.name
                        item.sourceIconReference = application.url.path
                        item.selected = false
                        if !isWritable && !protected {
                            item.permissionStatus = .userAuthorizationRequired
                            item.cleanupMethod = .analysisOnly
                        }
                        if !ScannerSupport.isExcluded(application.url, source: application.name, settings: context.settings) {
                            continuation.yield(.finding(item))
                            findings += 1
                        }
                    } catch is CancellationError {
                        break
                    } catch {
                        continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: application.url, error: error)))
                    }

                    guard BundleIdentifierPolicy().isConservativeCandidate(application.bundleIdentifier) else {
                        continue
                    }
                    let cache = context.homeDirectory
                        .appendingPathComponent("Library/Caches", isDirectory: true)
                        .appendingPathComponent(application.bundleIdentifier, isDirectory: true)
                        .standardizedFileURL
                    guard FileManager.default.fileExists(atPath: cache.path) else { continue }
                    let cacheRule = installedCacheRule(
                        cache: cache,
                        application: application,
                        protected: protected
                    )
                    do {
                        try RuleValidator().validate([cacheRule], homeDirectory: context.homeDirectory)
                        var item = try await ScannerSupport.makeItem(
                            candidate: cache,
                            root: cache,
                            rule: cacheRule,
                            scannerIdentifier: identifier,
                            context: context,
                            sourceOverride: source,
                            riskOverride: protected ? .protected : .safe,
                            embeddedRule: cacheRule
                        )
                        item.sourceIconReference = application.url.path
                        if protected { item.selected = false }
                        if !ScannerSupport.isExcluded(cache, source: application.name, settings: context.settings) {
                            continuation.yield(.finding(item))
                            findings += 1
                        }
                    } catch is CancellationError {
                        break
                    } catch FileValidationError.protectedPath {
                        continue
                    } catch FileValidationError.containsProtectedDescendant {
                        continue
                    } catch {
                        continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: cache, error: error)))
                    }
                }

                continuation.yield(.finished(scannerIdentifier: identifier))
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    private func applicationIsWritable(_ url: URL) -> Bool {
        let applicationValues = try? url.resourceValues(forKeys: [.isWritableKey])
        let parentValues = try? url.deletingLastPathComponent().resourceValues(forKeys: [.isWritableKey])
        return applicationValues?.isWritable == true && parentValues?.isWritable == true
    }

    private func applicationRule(application: InstalledApplication, protected: Bool, writable: Bool) -> CleanupRule {
        CleanupRule(
            id: "application.bundle.\(ScannerSupport.stableIdentifier(application.url.path))",
            displayName: "Installed Application",
            producedBy: application.name,
            producedByIdentifier: application.bundleIdentifier,
            sourceType: protected ? .systemComponent : .application,
            category: .applicationBundle,
            approvedRoots: [application.url.path],
            risk: protected ? .protected : .review,
            regeneratable: false,
            cleanupMethod: protected || !writable ? .analysisOnly : .moveToTrash,
            reason: "The application can be removed when it is no longer needed and can be reinstalled later if still available.",
            impact: "The application bundle will leave its current location. User documents are not included.",
            evidence: "Matched one exact installed .app bundle and read its Bundle ID from Info.plist.",
            whatItIs: "The installed application bundle containing its executable, frameworks, and resources."
        )
    }

    private func installedCacheRule(cache: URL, application: InstalledApplication, protected: Bool) -> CleanupRule {
        CleanupRule(
            id: "application.cache.\(ScannerSupport.stableIdentifier(cache.path))",
            displayName: "Installed Application Cache",
            producedBy: application.name,
            producedByIdentifier: application.bundleIdentifier,
            sourceType: protected ? .systemComponent : .application,
            category: .userCache,
            approvedRoots: [cache.path],
            risk: protected ? .protected : .safe,
            regeneratable: true,
            cleanupMethod: protected ? .analysisOnly : .moveToTrash,
            reason: "The installed application can recreate its exact Bundle-ID cache.",
            impact: "The application may open more slowly while it recreates or downloads cached data.",
            evidence: "The cache directory name exactly matches the installed application's Bundle ID.",
            whatItIs: "Temporary data stored by the installed application to avoid repeating work."
        )
    }
}
