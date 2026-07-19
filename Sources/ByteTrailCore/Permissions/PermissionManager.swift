import Foundation

public struct PermissionReport: Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var status: PermissionStatus
    public var explanation: String
}

public struct PermissionManager: Sendable {
    public init() {}

    public func status(for url: URL) -> PermissionReport {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)
        let readable = fm.isReadableFile(atPath: url.path)
        if exists && readable {
            return PermissionReport(path: url.path, status: .accessible, explanation: "Accessible with normal file permissions.")
        }
        if exists {
            return PermissionReport(path: url.path, status: .denied, explanation: "The location exists but macOS did not grant read access.")
        }
        return PermissionReport(path: url.path, status: .unavailable, explanation: "The location is not present on this Mac.")
    }

    public var fullDiskAccessSettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }
}
