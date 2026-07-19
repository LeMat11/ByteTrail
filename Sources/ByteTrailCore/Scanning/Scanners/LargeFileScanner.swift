import Foundation

public struct LargeFileScanner: ScannerProtocol {
    public let identifier = "scanner.large-files"
    public let displayName = "Large Files"
    public var maximumResults: Int

    public init(maximumResults: Int = 1_000) {
        self.maximumResults = maximumResults
    }

    public func coverageLocations(context: ScanContext) -> [ScanCoverageLocation] {
        let defaultRoot = context.homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        return normalizedRoots([defaultRoot] + context.settings.authorizedFolders).map(coverageLocation)
    }

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let producer = Task.detached {
                guard let baseRule = context.ruleEngine.rule(identifier: "analysis.large-file") else {
                    continuation.yield(.issue(ScanIssue(
                        scannerIdentifier: identifier,
                        path: "~/Downloads",
                        message: "The large-file rule is unavailable.",
                        permissionStatus: .unavailable
                    )))
                    continuation.finish()
                    return
                }

                let defaultRoot = context.homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
                let roots = normalizedRoots([defaultRoot] + context.settings.authorizedFolders)
                var inspected = 0
                var found = 0
                var seenResources = Set<String>()

                for root in roots {
                    if Task.isCancelled || found >= maximumResults { break }
                    guard FileManager.default.fileExists(atPath: root.path) else {
                        continuation.yield(.issue(ScanIssue(
                            scannerIdentifier: identifier,
                            path: root.path,
                            message: "The authorized scan location is unavailable.",
                            permissionStatus: .unavailable
                        )))
                        continue
                    }

                    let rootVolume = (try? root.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier.map { String(describing: $0) }
                    let keys: [URLResourceKey] = [
                        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey,
                        .isPackageKey, .fileSizeKey, .totalFileSizeKey, .fileAllocatedSizeKey,
                        .totalFileAllocatedSizeKey, .fileResourceIdentifierKey, .volumeIdentifierKey,
                        .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
                    ]
                    var enumerationIssues: [(URL, Error)] = []
                    guard let enumerator = FileManager.default.enumerator(
                        at: root,
                        includingPropertiesForKeys: keys,
                        options: context.settings.showHiddenFiles ? [.skipsPackageDescendants] : [.skipsPackageDescendants, .skipsHiddenFiles],
                        errorHandler: { url, error in
                            enumerationIssues.append((url, error))
                            return true
                        }
                    ) else {
                        continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: root, error: CocoaError(.fileReadNoPermission))))
                        continue
                    }

                    while let candidate = enumerator.nextObject() as? URL {
                        if Task.isCancelled || found >= maximumResults { break }
                        inspected += 1
                        let values: URLResourceValues
                        do {
                            values = try candidate.resourceValues(forKeys: Set(keys))
                        } catch {
                            continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: candidate, error: error)))
                            continue
                        }

                        if values.isSymbolicLink == true {
                            enumerator.skipDescendants()
                            continue
                        }
                        if values.isPackage == true {
                            enumerator.skipDescendants()
                            continue
                        }
                        guard values.isRegularFile == true, values.isAliasFile != true else { continue }
                        if let volume = values.volumeIdentifier.map({ String(describing: $0) }),
                           let rootVolume, volume != rootVolume {
                            continue
                        }
                        if values.isUbiquitousItem == true,
                           values.ubiquitousItemDownloadingStatus != .current {
                            continue
                        }

                        let logicalSize = Int64(values.totalFileSize ?? values.fileSize ?? 0)
                        guard logicalSize >= context.settings.largeFileMinimumBytes else { continue }
                        let sourceName = "User file"
                        if ScannerSupport.isExcluded(candidate, source: sourceName, settings: context.settings) { continue }
                        if let resource = values.fileResourceIdentifier.map({ String(describing: $0) }),
                           !seenResources.insert(resource).inserted {
                            continue
                        }

                        if inspected == 1 || inspected.isMultiple(of: 100) {
                            continuation.yield(.progress(ScanProgress(
                                scannerName: displayName,
                                category: baseRule.category.label,
                                currentPath: candidate.path,
                                filesInspected: inspected,
                                findings: found
                            )))
                        }

                        do {
                            let item = try await makeItem(
                                candidate: candidate,
                                authorizedRoot: root,
                                baseRule: baseRule,
                                context: context
                            )
                            continuation.yield(.finding(item))
                            found += 1
                        } catch is CancellationError {
                            break
                        } catch {
                            continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: candidate, error: error)))
                        }
                    }

                    for (url, error) in enumerationIssues {
                        continuation.yield(.issue(ScannerSupport.issue(scanner: identifier, root: url, error: error)))
                    }
                }

                if found >= maximumResults {
                    continuation.yield(.issue(ScanIssue(
                        scannerIdentifier: identifier,
                        path: roots.map(\.path).joined(separator: ", "),
                        message: "The result limit was reached. Increase the size threshold or narrow the scan locations.",
                        permissionStatus: .accessible
                    )))
                }
                continuation.yield(.finished(scannerIdentifier: identifier))
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    private func makeItem(
        candidate: URL,
        authorizedRoot: URL,
        baseRule: CleanupRule,
        context: ScanContext
    ) async throws -> CleanableItem {
        let cleanupRoot = candidate.deletingLastPathComponent().standardizedFileURL
        let dynamicRule = CleanupRule(
            id: "analysis.large-file.authorized.\(stableIdentifier(cleanupRoot.path))",
            displayName: baseRule.displayName,
            producedBy: "User file",
            sourceType: .userFile,
            category: .largeFile,
            approvedRoots: [cleanupRoot.path],
            risk: .review,
            regeneratable: false,
            cleanupMethod: .moveToTrash,
            reason: baseRule.reason,
            impact: baseRule.impact,
            evidence: baseRule.evidence,
            whatItIs: baseRule.whatItIs
        )
        let source = ResolvedSource(
            name: "User file",
            bundleIdentifier: nil,
            sourceType: .userFile,
            evidence: [baseRule.evidence],
            confidence: .confirmed
        )

        if (try? RuleValidator().validate([dynamicRule], homeDirectory: context.homeDirectory)) != nil {
            var item = try await ScannerSupport.makeItem(
                candidate: candidate,
                root: cleanupRoot,
                rule: dynamicRule,
                scannerIdentifier: identifier,
                context: context,
                sourceOverride: source,
                riskOverride: .review,
                embeddedRule: dynamicRule
            )
            item.selected = false
            return item
        }

        let metadata = try context.fileSystemValidator.validateForAnalysis(candidate, authorizedRoot: authorizedRoot)
        let size = try context.fileSizeCalculator.calculate(candidate)
        let protectedRule = CleanupRule(
            id: "analysis.large-file.protected",
            displayName: baseRule.displayName,
            producedBy: "User file",
            sourceType: .userFile,
            category: .largeFile,
            approvedRoots: [authorizedRoot.path],
            risk: .protected,
            regeneratable: false,
            cleanupMethod: .analysisOnly,
            reason: baseRule.reason,
            impact: "This location is protected. ByteTrail will only reveal the file in Finder.",
            evidence: baseRule.evidence,
            whatItIs: baseRule.whatItIs
        )
        let snapshot = context.fileSystemValidator.makeSnapshot(
            metadata: metadata,
            rule: protectedRule,
            approvedRoot: authorizedRoot,
            logicalSize: size.logicalBytes,
            allocatedSize: size.allocatedBytes
        )
        return CleanableItem(
            displayName: candidate.lastPathComponent,
            provenance: SourceProvenance(
                producedByName: source.name,
                sourceType: .userFile,
                currentURL: candidate,
                detectionReason: baseRule.evidence,
                evidence: source.evidence,
                confidence: .confirmed
            ),
            standardizedPath: candidate.standardizedFileURL.path,
            category: .largeFile,
            size: size.logicalBytes,
            allocatedSize: size.allocatedBytes,
            fileCount: 1,
            modifiedDate: metadata.modificationDate,
            whatItIs: baseRule.whatItIs,
            cleanupReason: baseRule.reason,
            expectedImpact: protectedRule.impact,
            regeneratable: false,
            riskLevel: .protected,
            permissionStatus: .accessible,
            selected: false,
            scannerIdentifier: identifier,
            matchedRuleIdentifier: protectedRule.id,
            approvedRoot: authorizedRoot.path,
            scanSnapshot: snapshot,
            cleanupMethod: .analysisOnly,
            recoveryAvailable: false
        )
    }

    private func normalizedRoots(_ candidates: [URL]) -> [URL] {
        let roots = Array(Set(candidates.map { $0.standardizedFileURL.path }))
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            .sorted { $0.pathComponents.count < $1.pathComponents.count }
        var result: [URL] = []
        for root in roots where !result.contains(where: { PathContainmentValidator().isContained(root, in: $0) }) {
            result.append(root)
        }
        return result
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
