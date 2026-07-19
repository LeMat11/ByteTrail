import Foundation

private struct CoverageAccumulator {
    let location: ScanCoverageLocation
    var findingCount = 0
    var issues: [ScanIssue] = []
}

public actor ScanCoordinator {
    private let scanners: [any ScannerProtocol]
    private var activeProducers: [UUID: Task<Void, Never>] = [:]

    public init(scanners: [any ScannerProtocol] = [
        ApplicationScanner(), ApplicationLeftoverScanner(),
        XcodeScanner(), DeveloperToolScanner(), CacheScanner(), LogScanner(),
        InstallerScanner(), LargeFileScanner(), TrashScanner(), IOSBackupScanner()
    ]) {
        self.scanners = scanners
    }

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        let scannerLocations = Dictionary(uniqueKeysWithValues: scanners.map { scanner in
            (scanner.identifier, Self.uniqueLocations(scanner.coverageLocations(context: context)))
        })
        let isEnabled: @Sendable (any ScannerProtocol) -> Bool = { scanner in
            context.settings.enabledScannerIDs.isEmpty || context.settings.enabledScannerIDs.contains(scanner.identifier)
        }
        let selectedScanners = scanners.filter(isEnabled)

        let (stream, continuation) = AsyncStream<ScanEvent>.makeStream()
        let scanID = UUID()
        let producer = Task {
            var seenPaths = Set<String>()

            for scanner in scanners {
                let status: ScanCoverageStatus = isEnabled(scanner) ? .pending : .disabled
                for location in scannerLocations[scanner.identifier, default: []] {
                    continuation.yield(.coverage(ScanCoverageEntry(location: location, status: status)))
                }
            }

            var finalizedLocationIDs = Set<String>()
            for scanner in selectedScanners {
                if Task.isCancelled { break }
                let locations = scannerLocations[scanner.identifier, default: []]
                var accumulators = Dictionary(uniqueKeysWithValues: locations.map {
                    ($0.id, CoverageAccumulator(location: $0))
                })

                for await event in scanner.scan(context: context) {
                    if Task.isCancelled { break }
                    switch event {
                    case let .finding(item):
                        if seenPaths.insert(item.standardizedPath).inserted {
                            if let location = Self.mostSpecificLocation(for: item.standardizedPath, in: locations) {
                                accumulators[location.id]?.findingCount += 1
                            }
                            continuation.yield(.finding(item))
                        }
                    case let .issue(issue):
                        if let location = Self.mostSpecificLocation(for: issue.path, in: locations)
                            ?? locations.first {
                            accumulators[location.id]?.issues.append(issue)
                        }
                        continuation.yield(event)
                    case .progress, .finished, .coverage:
                        continuation.yield(event)
                    }
                }

                let cancelled = Task.isCancelled
                for location in locations {
                    let accumulator = accumulators[location.id] ?? CoverageAccumulator(location: location)
                    let entry = Self.finalEntry(for: accumulator, cancelled: cancelled)
                    continuation.yield(.coverage(entry))
                    finalizedLocationIDs.insert(location.id)
                }
                if cancelled { break }
            }

            if Task.isCancelled {
                for scanner in selectedScanners {
                    for location in scannerLocations[scanner.identifier, default: []]
                        where !finalizedLocationIDs.contains(location.id) {
                        continuation.yield(.coverage(ScanCoverageEntry(location: location, status: .cancelled)))
                    }
                }
            }
            continuation.finish()
            scanDidFinish(scanID)
        }
        activeProducers[scanID] = producer
        continuation.onTermination = { [weak self] _ in
            producer.cancel()
            Task { await self?.scanDidFinish(scanID) }
        }
        return stream
    }

    public func cancelCurrentScan() {
        for producer in activeProducers.values {
            producer.cancel()
        }
    }

    private func scanDidFinish(_ scanID: UUID) {
        activeProducers[scanID] = nil
    }

    private nonisolated static func uniqueLocations(_ locations: [ScanCoverageLocation]) -> [ScanCoverageLocation] {
        var seen = Set<String>()
        return locations.filter { seen.insert($0.id).inserted }
    }

    private nonisolated static func mostSpecificLocation(
        for rawPath: String,
        in locations: [ScanCoverageLocation]
    ) -> ScanCoverageLocation? {
        let standardizedPath = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath).standardizedFileURL.path
        return locations
            .filter { location in
                standardizedPath == location.standardizedPath
                    || standardizedPath.hasPrefix(location.standardizedPath + "/")
            }
            .max { lhs, rhs in lhs.standardizedPath.count < rhs.standardizedPath.count }
    }

    private nonisolated static func finalEntry(
        for accumulator: CoverageAccumulator,
        cancelled: Bool
    ) -> ScanCoverageEntry {
        if cancelled {
            return ScanCoverageEntry(
                location: accumulator.location,
                status: .cancelled,
                findingCount: accumulator.findingCount
            )
        }

        if let deniedIssue = accumulator.issues.first(where: {
            $0.permissionStatus == .denied || $0.permissionStatus == .userAuthorizationRequired
        }) {
            return ScanCoverageEntry(
                location: accumulator.location,
                status: .permissionDenied,
                findingCount: accumulator.findingCount,
                message: deniedIssue.message
            )
        }

        guard FileManager.default.fileExists(atPath: accumulator.location.standardizedPath) else {
            return ScanCoverageEntry(
                location: accumulator.location,
                status: .notFound,
                findingCount: accumulator.findingCount
            )
        }

        if let issue = accumulator.issues.first {
            return ScanCoverageEntry(
                location: accumulator.location,
                status: .partial,
                findingCount: accumulator.findingCount,
                message: issue.message
            )
        }

        return ScanCoverageEntry(
            location: accumulator.location,
            status: accumulator.findingCount > 0 ? .scanned : .noFindings,
            findingCount: accumulator.findingCount
        )
    }
}
