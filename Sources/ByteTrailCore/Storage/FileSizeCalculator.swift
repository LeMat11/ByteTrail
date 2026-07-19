import Foundation

public struct FileSizeResult: Sendable, Equatable {
    public var logicalBytes: Int64
    public var allocatedBytes: Int64
    public var fileCount: Int
    public var inspectedCount: Int
    public var hitLimit: Bool

    public init(logicalBytes: Int64 = 0, allocatedBytes: Int64 = 0, fileCount: Int = 0, inspectedCount: Int = 0, hitLimit: Bool = false) {
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.inspectedCount = inspectedCount
        self.hitLimit = hitLimit
    }
}

public struct FileSizeCalculator: @unchecked Sendable {
    public var maximumFileCount: Int
    public var maximumDepth: Int
    public var maximumDuration: TimeInterval
    private let fileManager: FileManager

    public init(maximumFileCount: Int = 500_000, maximumDepth: Int = 64, maximumDuration: TimeInterval = 120, fileManager: FileManager = .default) {
        self.maximumFileCount = maximumFileCount
        self.maximumDepth = maximumDepth
        self.maximumDuration = maximumDuration
        self.fileManager = fileManager
    }

    public func calculate(_ root: URL, skipPackageDescendants: Bool = true) throws -> FileSizeResult {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
            .fileAllocatedSizeKey, .totalFileSizeKey, .totalFileAllocatedSizeKey,
            .fileResourceIdentifierKey
        ]
        let rootValues = try root.resourceValues(forKeys: Set(keys))
        if rootValues.isRegularFile == true {
            return FileSizeResult(
                logicalBytes: Int64(rootValues.totalFileSize ?? rootValues.fileSize ?? 0),
                allocatedBytes: Int64(rootValues.totalFileAllocatedSize ?? rootValues.fileAllocatedSize ?? rootValues.totalFileSize ?? rootValues.fileSize ?? 0),
                fileCount: 1,
                inspectedCount: 1
            )
        }
        guard rootValues.isDirectory == true else { return FileSizeResult() }

        var result = FileSizeResult()
        var seenResourceIdentifiers = Set<String>()
        let started = Date()
        let options: FileManager.DirectoryEnumerationOptions = skipPackageDescendants ? [.skipsPackageDescendants] : []
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: options) else {
            throw CocoaError(.fileReadNoPermission)
        }
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { throw CancellationError() }
            result.inspectedCount += 1
            if result.inspectedCount > maximumFileCount || Date().timeIntervalSince(started) > maximumDuration {
                result.hitLimit = true
                break
            }
            let relativeDepth = max(0, url.pathComponents.count - root.pathComponents.count)
            if relativeDepth > maximumDepth {
                enumerator.skipDescendants()
                result.hitLimit = true
                continue
            }
            let values: URLResourceValues
            do { values = try url.resourceValues(forKeys: Set(keys)) }
            catch { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            if let identifier = values.fileResourceIdentifier.map({ String(describing: $0) }),
               !seenResourceIdentifiers.insert(identifier).inserted {
                continue
            }
            result.fileCount += 1
            result.logicalBytes += Int64(values.totalFileSize ?? values.fileSize ?? 0)
            result.allocatedBytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.totalFileSize ?? values.fileSize ?? 0)
        }
        return result
    }
}

public struct StorageSnapshot: Sendable {
    public var capacity: Int64
    public var available: Int64
    public var used: Int64 { max(0, capacity - available) }
}

public struct StorageMonitor: Sendable {
    public init() {}

    public func snapshot(for url: URL = FileManager.default.homeDirectoryForCurrentUser) -> StorageSnapshot {
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let capacity = Int64(values?.volumeTotalCapacity ?? 0)
        let available = values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
        return StorageSnapshot(capacity: capacity, available: available)
    }
}
