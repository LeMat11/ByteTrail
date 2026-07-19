import Foundation

public actor CleanupHistoryStore {
    private let storageURL: URL
    private var entries: [CleanupHistoryEntry]

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        self.entries = (try? Self.load(from: self.storageURL)) ?? []
    }

    public static var defaultStorageURL: URL {
        #if DEBUG
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ByteTrail-Debug", isDirectory: true)
            .appendingPathComponent("CleanupHistory.json")
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(AppConfiguration.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("CleanupHistory.json")
        #endif
    }

    public func allEntries() -> [CleanupHistoryEntry] { entries.sorted { $0.date > $1.date } }

    public func append(_ entry: CleanupHistoryEntry) throws {
        entries.append(entry)
        try persist()
    }

    public func replace(_ entry: CleanupHistoryEntry) throws {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        try persist()
    }

    public func clear() throws {
        entries.removeAll()
        try persist()
    }

    public func prune(olderThan cutoff: Date) throws {
        entries.removeAll { $0.date < cutoff }
        try persist()
    }

    private func persist() throws {
        try DevelopmentSafetyLock.validateMutation(at: storageURL)
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.byteTrail.encode(entries)
        try data.write(to: storageURL, options: .atomic)
    }

    private static func load(from url: URL) throws -> [CleanupHistoryEntry] {
        try JSONDecoder.byteTrail.decode([CleanupHistoryEntry].self, from: Data(contentsOf: url))
    }
}

public actor RecoveryStore {
    private let storageURL: URL
    private var entries: [RecoveryEntry]

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        self.entries = (try? Self.load(from: self.storageURL)) ?? []
    }

    public static var defaultStorageURL: URL {
        #if DEBUG
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ByteTrail-Debug", isDirectory: true)
            .appendingPathComponent("RecoveryIndex.json")
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(AppConfiguration.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("RecoveryIndex.json")
        #endif
    }

    public func allEntries() -> [RecoveryEntry] { entries }

    public func append(_ entry: RecoveryEntry) throws {
        entries.append(entry)
        try persist()
    }

    public func remove(id: UUID) throws {
        entries.removeAll { $0.id == id }
        try persist()
    }

    private func persist() throws {
        try DevelopmentSafetyLock.validateMutation(at: storageURL)
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.byteTrail.encode(entries).write(to: storageURL, options: .atomic)
    }

    private static func load(from url: URL) throws -> [RecoveryEntry] {
        try JSONDecoder.byteTrail.decode([RecoveryEntry].self, from: Data(contentsOf: url))
    }
}

public actor ExclusionStore {
    private struct Payload: Codable {
        var paths: Set<String>
        var sources: Set<String>
    }

    private var paths: Set<String>
    private var sources: Set<String>
    private let storageURL: URL

    public init(paths: Set<String> = [], sources: Set<String> = [], storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
        if let payload = try? JSONDecoder.byteTrail.decode(Payload.self, from: Data(contentsOf: self.storageURL)) {
            self.paths = payload.paths
            self.sources = payload.sources
        } else {
            self.paths = paths
            self.sources = sources
        }
    }

    public static var defaultStorageURL: URL {
        #if DEBUG
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ByteTrail-Debug", isDirectory: true)
            .appendingPathComponent("Exclusions.json")
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(AppConfiguration.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Exclusions.json")
        #endif
    }

    public func excludedPaths() -> Set<String> { paths }
    public func excludedSources() -> Set<String> { sources }
    public func exclude(path: String) throws { paths.insert(URL(fileURLWithPath: path).standardizedFileURL.path); try persist() }
    public func exclude(source: String) throws { sources.insert(source); try persist() }
    public func replace(paths: Set<String>, sources: Set<String>) throws { self.paths = paths; self.sources = sources; try persist() }
    public func reset() throws { paths.removeAll(); sources.removeAll(); try persist() }

    private func persist() throws {
        try DevelopmentSafetyLock.validateMutation(at: storageURL)
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.byteTrail.encode(Payload(paths: paths, sources: sources)).write(to: storageURL, options: .atomic)
    }
}

public actor SettingsStore {
    private let storageURL: URL

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
    }

    public static var defaultStorageURL: URL {
        #if DEBUG
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ByteTrail-Debug", isDirectory: true)
            .appendingPathComponent("Settings.json")
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(AppConfiguration.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Settings.json")
        #endif
    }

    public func load() -> ScanSettings? {
        try? JSONDecoder.byteTrail.decode(ScanSettings.self, from: Data(contentsOf: storageURL))
    }

    public func save(_ settings: ScanSettings) throws {
        try DevelopmentSafetyLock.validateMutation(at: storageURL)
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.byteTrail.encode(settings).write(to: storageURL, options: .atomic)
    }
}

public extension JSONEncoder {
    static var byteTrail: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var byteTrail: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
