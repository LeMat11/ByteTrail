import ByteTrailCore
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .english: return Locale(identifier: "en")
        }
    }
    var localizationCode: String? {
        self == .system ? nil : rawValue
    }
}

enum L10n {
    #if SWIFT_PACKAGE
    private static let resourceBundle: Bundle = {
        let bundleName = "ByteTrail_ByteTrailApp"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("\(bundleName).bundle", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle", isDirectory: true),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("\(bundleName).bundle", isDirectory: true)
        ].compactMap { $0 }
        for url in candidates {
            if let bundle = Bundle(url: url) { return bundle }
        }
        return Bundle.module
    }()
    #else
    private static let resourceBundle = Bundle.main
    #endif

    static func string(_ key: String, language: AppLanguage, arguments: [CVarArg] = []) -> String {
        let bundle: Bundle
        if let code = language.localizationCode,
           let localizedBundle = localizedBundle(for: code) {
            bundle = localizedBundle
        } else {
            bundle = resourceBundle
        }
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    private static func localizedBundle(for requestedCode: String) -> Bundle? {
        // SwiftPM normalizes `zh-Hans.lproj` to `zh-hans.lproj` in Release resource
        // bundles. Xcode preserves the source spelling in Debug builds. Resolve the
        // localization advertised by the bundle so both layouts work on every volume.
        let resolvedCode = resourceBundle.localizations.first {
            $0.caseInsensitiveCompare(requestedCode) == .orderedSame
        } ?? requestedCode
        guard let path = resourceBundle.path(forResource: resolvedCode, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}

extension AppViewModel {
    func t(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.string(key, language: language, arguments: arguments)
    }

    func riskLabel(_ risk: RiskLevel) -> String { t("risk.\(risk.rawValue)") }
    func confidenceLabel(_ confidence: AttributionConfidence) -> String { t("confidence.\(confidence.rawValue)") }
    func cleanupMethodLabel(_ method: CleanupMethod) -> String { t("cleanup.method.\(method.rawValue)") }
    func categoryLabel(_ category: ScanCategory) -> String { t("category.\(category.rawValue)") }
    func cleanupStatusLabel(_ status: CleanupResultStatus) -> String { t("cleanup.status.\(status.rawValue)") }
    func coverageStatusLabel(_ status: ScanCoverageStatus) -> String { t("coverage.status.\(status.rawValue)") }

    func scannerName(_ value: String) -> String {
        let keys = [
            "Applications": "scanner.applications",
            "Possible App Leftovers": "scanner.applicationLeftovers",
            "Application Caches": "scanner.applicationCaches",
            "Application Logs": "scanner.applicationLogs",
            "Developer Tool Caches": "scanner.developerCaches",
            "Downloaded Installers": "scanner.installers",
            "Large Files": "scanner.largeFiles",
            "Trash": "scanner.trash",
            "Xcode Storage": "scanner.xcode",
            "iPhone & iPad Backups": "scanner.iosBackups",
            "Preparing": "scanner.preparing"
        ]
        return t(keys[value] ?? value)
    }

    func progressCategory(_ value: String) -> String {
        let category = ScanCategory.allCases.first { $0.label == value }
        return category.map(categoryLabel) ?? value
    }

    func sourceName(_ item: CleanableItem) -> String {
        if item.provenance.producedByName == "Unknown source" { return t("source.unknown") }
        if item.provenance.producedByName == "User file" { return t("source.userFile") }
        return item.provenance.producedByName
    }

    func ruleText(_ item: CleanableItem, field: String) -> String {
        let id: String
        if item.matchedRuleIdentifier.hasPrefix("application.bundle.") { id = "application.bundle" }
        else if item.matchedRuleIdentifier.hasPrefix("application.cache.") { id = "application.cache" }
        else if item.matchedRuleIdentifier.hasPrefix("application.leftover.") { id = "application.leftover" }
        else if item.matchedRuleIdentifier.hasPrefix("cache.sandbox.") { id = "cache.sandbox" }
        else if item.matchedRuleIdentifier.hasPrefix("cache.group.") { id = "cache.group" }
        else if item.matchedRuleIdentifier.hasPrefix("analysis.large-file") { id = "analysis.large-file" }
        else { id = item.matchedRuleIdentifier }
        let fallback: String
        switch field {
        case "what": fallback = item.whatItIs
        case "reason": fallback = item.cleanupReason
        case "impact": fallback = item.expectedImpact
        case "evidence": fallback = item.provenance.detectionReason
        default: fallback = ""
        }
        let key = "rule.\(id).\(field)"
        let localized = t(key)
        return localized == key ? fallback : localized
    }

    func localizedMessage(_ message: String) -> String {
        let keys = [
            "Duplicate cleanup target skipped.": "message.duplicateSkipped",
            "Overlapping cleanup target skipped.": "message.overlapSkipped",
            "Safety policy does not permit this item to be cleaned.": "message.safetySkipped",
            "Matched rule is no longer available.": "message.ruleUnavailable",
            "Validated. No file was moved because dry-run is enabled.": "message.dryRunValidated",
            "This item is analysis-only.": "message.analysisOnly",
            "Moved to Trash.": "message.movedToTrash",
            "Moved to the Recovery Vault.": "message.movedToRecovery",
            "Restored to the original location.": "message.restored",
            "The authorized scan location is unavailable.": "message.locationUnavailable",
            "The result limit was reached. Increase the size threshold or narrow the scan locations.": "message.resultLimit",
            "The source application is running. Quit it and scan again before cleanup.": "message.applicationRunning",
            "Cleanup was cancelled before this item was processed.": "message.cleanupCancelled",
            "The cache rule is unavailable.": "message.cacheRuleUnavailable",
            "The large-file rule is unavailable.": "message.largeFileRuleUnavailable",
            "The log rules are unavailable.": "message.logRulesUnavailable",
            "The item no longer exists.": "message.itemMissing",
            "The path is not in canonical form.": "message.pathCanonical",
            "The item is outside the rule’s approved root.": "message.outsideRoot",
            "The item is protected and cannot be cleaned.": "message.protectedPath",
            "The target contains a protected location.": "message.containsProtected",
            "Symbolic links are not accepted by this rule.": "message.symbolicLink",
            "Resolving symbolic links leaves the approved root.": "message.symbolicLinkEscape",
            "Finder aliases are analysis-only.": "message.aliasOnly",
            "The target’s file type is unsupported.": "message.unsupportedType",
            "The matched rule changed since scanning.": "message.ruleChanged",
            "The risk classification changed since scanning.": "message.riskChanged",
            "The item is not writable with current permissions.": "message.permissionDenied",
            "Debug cleanup is restricted to a validated temporary fixture directory.": "message.developmentLock",
            "Moving to Trash is unavailable in this build or environment.": "message.trashUnavailable",
            "The Trash location failed the safety check.": "message.invalidTrashRoot",
            "The Trash folder is unavailable or is not a directory.": "message.trashFolderUnavailable",
            "A file already exists at the restore destination.": "message.destinationExists",
            "The Recovery Vault destination is invalid.": "message.invalidRecovery",
            "The Recovery Vault item no longer exists.": "message.recoveryMissing"
        ]
        if message.hasPrefix("The item changed since scanning:") { return t("message.changedSinceScan") }
        guard let key = keys[message] else { return message }
        return t(key)
    }

    func formatBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(language.locale))
    }

    func formatDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(language.locale))
    }
}
