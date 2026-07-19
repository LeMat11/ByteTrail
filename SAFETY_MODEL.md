# ByteTrail Safety Model

## Final risk levels

- **Safe**: a confirmed or high-confidence, regeneratable item under an exact approved root. Safe items may be preselected, but always remain visible and are revalidated before cleanup.
- **Review**: data that may be useful, recent, difficult to regenerate, user-created, or attributed with insufficient confidence. Review items are never preselected and require explicit selection on the Review screen.
- **Protected**: personal, application, credential, database, system, or otherwise uncertain content that ByteTrail must not clean. The UI cannot override this decision.

Unknown rules fail closed as Protected. Unknown or low-confidence source attribution cannot produce a final Safe classification.

## Approved roots

Bundled rules are limited to these explicit roots:

- `~/Library/Caches`
- `~/Library/Logs`
- `~/.Trash` (analysis only)
- `~/Library/Developer/Xcode/DerivedData`
- `~/Library/Developer/Xcode/Archives`
- `~/Library/Developer/Xcode/iOS DeviceSupport`
- `~/Library/Developer/CoreSimulator/Caches` (analysis only in 1.0)
- `~/Library/Caches/Homebrew`
- `~/.npm/_cacache`
- `~/Library/Caches/Yarn`
- `~/Library/pnpm/store`
- `~/Library/Caches/pip`
- `~/.conda/pkgs`
- `~/Downloads`
- `~/Library/Application Support/MobileSync/Backup`

A rule cannot approve `/`, the home directory, `~/Library`, `/System`, or a protected root. The only protected-root exception is a runtime rule whose root is one exact recognized `.app` bundle under `/Applications`, `/System/Applications`, or `~/Applications`; it cannot authorize the containing Applications directory. Invalid and duplicate rules are rejected before scanning begins.

Runtime rules are generated only for narrowly bounded cases: one exact installed `.app` bundle; its exact `~/Library/Caches/<Bundle ID>` directory; one top-level Bundle-ID-shaped leftover candidate; an exact `Data/Library/Caches` or `Library/Caches` leaf inside an enumerated app container; and the immediate parent of an individual large file found under Downloads or a user-authorized scan root. Each generated rule is embedded in the finding, must pass the same validator, and is checked again immediately before cleanup. No generated rule authorizes an Applications directory, an entire container, a selected volume, or a broad personal folder.

Possible leftovers are enumerated only as immediate children of `~/Library/Caches`, `Preferences`, `Logs`, `Saved Application State`, `Application Support`, and `Containers`. The filename must conservatively resemble a Bundle ID, must not match an indexed installed app, ByteTrail itself, or `com.apple.*`, and is always **Review**, never preselected, and moved only to the recoverable vault. Group Containers are intentionally not inferred or grouped.

## Protected categories

ByteTrail independently protects system files and system applications, ByteTrail itself, Keychain, Mail, Messages, Safari and browser profiles, cookies, account databases, cloud metadata, Photos and other media libraries, Documents, Desktop, source projects, application databases, and active development environments. Ordinary application bundles are **Review**, never preselected, and are treated as one exact package. It never bypasses SIP or modifies the sealed system volume.

## Path and link defenses

Containment is evaluated using standardized path components, not string prefixes. This rejects traversal and prefix-collision paths such as `Caches-escape`. Symbolic links are resolved and cannot escape an approved root; bundled cleanup rules disallow symbolic-link targets entirely. Finder aliases are analysis-only. General directory enumeration does not follow symbolic links or package descendants and is bounded by depth, item count, and time. Application size measurement traverses only the already validated exact `.app` package so the reported size includes its executable and resources.

## Scan snapshot and TOCTOU mitigation

At scan time ByteTrail records the standardized path, file resource identifier, file type, modification date, logical and allocated size, symbolic-link and alias status, volume identifier, approved root, rule ID, and final risk. Immediately before cleanup it resolves and validates the target again. A changed identity, type, size, date, volume, rule, risk, permission, or containment result causes that item to be skipped and rescanned.

This reduces, but cannot mathematically eliminate, all time-of-check/time-of-use races in user-space software. ByteTrail fails closed when metadata is unavailable or inconsistent.

## Recovery

Normal Release behavior prefers the supported macOS Trash API. When Trash is unavailable, ordinary eligible items move to an app-managed Recovery Vault and durably record their original path. Application bundles fail closed instead of falling back to the vault because restoring into a protected Applications root is intentionally forbidden. If the recovery index cannot be saved, ByteTrail attempts to roll the move back. Restore never overwrites an existing destination. Permanent deletion is not implemented.

## User cleanup flow

Cleanup has two visible steps: review the findings and explicitly select what to act on, then choose **Clean Up Selected**. There is no hidden automatic cleanup, background cleanup, or command-line cleanup trigger. The second step still performs rule, path, identity, risk, permission, and running-application checks before any move.

When an application bundle and one of its descendant findings are both considered, selecting one deselects the overlapping target. The cleanup coordinator independently orders parent paths first and skips overlapping descendants so the same bytes cannot be processed twice.

## Development-machine lock

Debug builds default to dry-run and enforce a second, non-configurable mutation boundary in the core cleanup layer: only a child of the standardized system temporary directory may be moved or modified. Debug Trash movement is disabled because it would cross into the real user Trash. Automated destructive-operation checks use a newly created UUID fixture directory, print its path, verify temporary-root containment, and populate it only with synthetic data.
