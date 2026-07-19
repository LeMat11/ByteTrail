import Foundation

public struct ApplicationLeftoverScanner: ScannerProtocol {
    public let identifier = "scanner.application-leftovers"
    public let displayName = "Possible App Leftovers"

    public init() {}

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let producer = Task.detached {
                let applications = await context.applicationResolver.allApplications()
                let installedIdentifiers = Set(applications.map(\.bundleIdentifier))
                let identifierPolicy = BundleIdentifierPolicy()
                var inspected = 0
                var findings = 0

                for specification in rootSpecifications(homeDirectory: context.homeDirectory) {
                    if Task.isCancelled { break }
                    guard FileManager.default.fileExists(atPath: specification.root.path) else { continue }
                    do {
                        for candidate in try ScannerSupport.children(
                            of: specification.root,
                            showHidden: context.settings.showHiddenFiles
                        ) {
                            if Task.isCancelled { break }
                            inspected += 1
                            continuation.yield(.progress(ScanProgress(
                                scannerName: displayName,
                                category: ScanCategory.applicationLeftover.label,
                                currentPath: candidate.path,
                                filesInspected: inspected,
                                findings: findings
                            )))

                            guard let bundleIdentifier = specification.bundleIdentifier(for: candidate),
                                  identifierPolicy.isConservativeCandidate(bundleIdentifier),
                                  !installedIdentifiers.contains(bundleIdentifier),
                                  bundleIdentifier != AppConfiguration.bundleIdentifier,
                                  !bundleIdentifier.lowercased().hasPrefix("com.apple.") else {
                                continue
                            }

                            let source = ResolvedSource(
                                name: bundleIdentifier,
                                bundleIdentifier: bundleIdentifier,
                                sourceType: .application,
                                evidence: [
                                    "The top-level item has an exact Bundle-ID-shaped name.",
                                    "No installed application with that exact Bundle ID was found in the indexed application roots."
                                ],
                                confidence: .medium
                            )
                            let rule = leftoverRule(
                                candidate: candidate,
                                bundleIdentifier: bundleIdentifier,
                                locationName: specification.locationName
                            )
                            do {
                                try RuleValidator().validate([rule], homeDirectory: context.homeDirectory)
                                var item = try await ScannerSupport.makeItem(
                                    candidate: candidate,
                                    root: candidate,
                                    rule: rule,
                                    scannerIdentifier: identifier,
                                    context: context,
                                    sourceOverride: source,
                                    riskOverride: .review,
                                    embeddedRule: rule
                                )
                                item.selected = false
                                if !ScannerSupport.isExcluded(candidate, source: bundleIdentifier, settings: context.settings) {
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
                                continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: candidate, error: error)))
                            }
                        }
                    } catch {
                        continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: specification.root, error: error)))
                    }
                }

                continuation.yield(.finished(scannerIdentifier: identifier))
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    private func leftoverRule(candidate: URL, bundleIdentifier: String, locationName: String) -> CleanupRule {
        CleanupRule(
            id: "application.leftover.\(ScannerSupport.stableIdentifier(candidate.path))",
            displayName: "Possible Application Leftover",
            producedBy: bundleIdentifier,
            producedByIdentifier: bundleIdentifier,
            sourceType: .application,
            category: .applicationLeftover,
            approvedRoots: [candidate.path],
            risk: .review,
            regeneratable: false,
            cleanupMethod: .recoveryVault,
            reason: "No installed application with this exact Bundle ID was found, but absence is not proof that the data is unused.",
            impact: "A removed app, background helper, or command-line tool may still rely on this item. ByteTrail keeps it recoverable.",
            evidence: "Matched one exact Bundle-ID-shaped top-level item in \(locationName); no installed Bundle ID matched.",
            whatItIs: "A possible application leftover that requires individual review."
        )
    }
}

private struct LeftoverRootSpecification: Sendable {
    enum Naming: Sendable {
        case exact
        case removingExtension(String)
    }

    let root: URL
    let locationName: String
    let naming: Naming

    func bundleIdentifier(for candidate: URL) -> String? {
        switch naming {
        case .exact:
            return candidate.lastPathComponent
        case let .removingExtension(requiredExtension):
            guard candidate.pathExtension == requiredExtension else { return nil }
            return candidate.deletingPathExtension().lastPathComponent
        }
    }
}

private func rootSpecifications(homeDirectory: URL) -> [LeftoverRootSpecification] {
    let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
    return [
        LeftoverRootSpecification(root: library.appendingPathComponent("Caches", isDirectory: true), locationName: "Caches", naming: .exact),
        LeftoverRootSpecification(root: library.appendingPathComponent("Preferences", isDirectory: true), locationName: "Preferences", naming: .removingExtension("plist")),
        LeftoverRootSpecification(root: library.appendingPathComponent("Logs", isDirectory: true), locationName: "Logs", naming: .exact),
        LeftoverRootSpecification(root: library.appendingPathComponent("Saved Application State", isDirectory: true), locationName: "Saved Application State", naming: .removingExtension("savedState")),
        LeftoverRootSpecification(root: library.appendingPathComponent("Application Support", isDirectory: true), locationName: "Application Support", naming: .exact),
        LeftoverRootSpecification(root: library.appendingPathComponent("Containers", isDirectory: true), locationName: "Containers", naming: .exact)
    ]
}
