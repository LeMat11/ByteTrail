import Foundation

public actor ScanCoordinator {
    private let scanners: [any ScannerProtocol]

    public init(scanners: [any ScannerProtocol] = [
        XcodeScanner(), DeveloperToolScanner(), CacheScanner(), LogScanner(),
        InstallerScanner(), LargeFileScanner(), TrashScanner(), IOSBackupScanner()
    ]) {
        self.scanners = scanners
    }

    public func scan(context: ScanContext) -> AsyncStream<ScanEvent> {
        let selectedScanners = scanners.filter {
            context.settings.enabledScannerIDs.isEmpty || context.settings.enabledScannerIDs.contains($0.identifier)
        }
        return AsyncStream { continuation in
            let producer = Task {
                var seenPaths = Set<String>()
                for scanner in selectedScanners {
                    if Task.isCancelled { break }
                    for await event in scanner.scan(context: context) {
                        if Task.isCancelled { break }
                        switch event {
                        case let .finding(item):
                            if seenPaths.insert(item.standardizedPath).inserted { continuation.yield(.finding(item)) }
                        default:
                            continuation.yield(event)
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}
