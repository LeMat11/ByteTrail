# ByteTrail Scan Coverage Report — Implementation Prompt

You are a senior macOS and Swift engineer extending ByteTrail, a local-only disk inspection and cleanup app. Implement a trustworthy scan coverage report that explains why a scan may produce few cleanable findings.

## Product objective

Add a dedicated **Scan Coverage** sidebar page. After or during a user-initiated scan, it must show every configured scanner and each concrete root it was expected to inspect. A user must be able to distinguish:

- waiting to scan;
- scanned and produced findings;
- scanned successfully but produced no eligible findings;
- location not present on this Mac;
- permission denied;
- partially scanned because one or more child paths failed;
- scanner disabled in Settings;
- scan cancelled before completion.

The report is explanatory only. It must never broaden cleanup authorization, make an item selectable, request Full Disk Access automatically, or perform a filesystem mutation.

## Required architecture

1. Add a Sendable/Codable coverage model in ByteTrailCore with a stable ID derived from scanner ID and standardized root path.
2. Extend `ScannerProtocol` with a coverage-location method and a safe default implementation for injected/test scanners.
3. Every built-in scanner must declare the exact top-level roots it can inspect:
   - installed applications and exact application caches;
   - possible app-leftover roots;
   - Xcode storage roots;
   - supported developer cache roots;
   - user caches and sandbox/group-container cache roots;
   - user logs;
   - Downloads installers;
   - Downloads plus user-authorized large-file roots;
   - Trash;
   - local iOS backups.
4. `ScanCoordinator` must emit initial pending/disabled coverage events, attribute progress/findings/issues to the most specific declared root, and emit one final status for every enabled root.
5. Missing optional directories are not errors. Report them as **Not Found**.
6. A permission issue takes priority over Not Found. A non-permission issue produces **Partial**. Cancellation produces **Cancelled** for roots not finalized.
7. Continue forwarding all existing progress, finding, issue, and finished events without changing deduplication or cleanup behavior.
8. `AppViewModel` must reset coverage at scan start and upsert entries by stable ID as events arrive.
9. Add a responsive SwiftUI coverage page with:
   - concise explanation that “no findings” differs from “not scanned”;
   - summary counts;
   - status filter;
   - scanner name, standardized path, status, and finding count for every location;
   - clear empty state before the first scan;
   - English and Simplified Chinese strings.

## Safety requirements

- All analysis and reporting remains local; add no network code, telemetry, analytics, cloud service, AI model, or remote rules.
- Do not add privileged helpers or automatic permission prompts.
- Do not read file contents for coverage classification.
- Do not change cleanup rules, risk levels, selection defaults, protected paths, or the two-step Review → Clean Up flow.
- Debug dry-run and the non-configurable temporary-directory mutation lock must remain intact.
- Command-line build and test must never trigger a real scan or cleanup automatically.
- Any destructive-operation test must use a newly created UUID-named synthetic fixture under the standardized system temporary directory, print and validate that path before populating it, and refuse to proceed when containment validation fails.
- Never test against real user caches, Trash, Downloads, Xcode data, backups, package-manager data, external volumes, network volumes, or cloud folders.

## Regression tests

Add deterministic injected-scanner tests covering at least:

- pending → scanned with findings;
- existing root → no findings;
- missing root → not found;
- permission issue → permission denied;
- non-permission issue plus findings → partial;
- disabled scanner → disabled without invoking its scan;
- cancellation finalizes unfinished roots as cancelled;
- stable IDs distinguish the same path used by different scanners.

Run all existing XCTest cases and the independent `ByteTrailVerification` harness. Validate both localization files with `plutil`, verify matching key sets, build the Xcode Debug scheme with project-local DerivedData, build both Release architectures, and verify the final app/DMG signature, architectures, resources, and SHA-256.

## Acceptance criteria

- A completed scan accounts for every declared root with a terminal status.
- A disabled scanner is visible as disabled without touching its filesystem roots.
- “No findings” is never represented as a permission failure.
- The report cannot initiate cleanup.
- Existing scan findings and cleanup safety behavior remain unchanged.
- The UI works in narrow and wide windows without collapsing the persistent sidebar.
- The final report explicitly confirms that every destructive-operation test was confined to temporary synthetic fixtures.
