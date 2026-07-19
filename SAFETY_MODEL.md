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

A rule cannot approve `/`, the home directory, `~/Library`, `/System`, or a protected root. Invalid and duplicate rules are rejected before scanning begins.

Runtime rules are generated only for two narrowly bounded cases: an exact `Data/Library/Caches` or `Library/Caches` leaf inside an enumerated app container, and the immediate parent of an individual large file found under Downloads or a user-authorized scan root. The generated rule is embedded in the finding, must pass the same validator, and is checked again immediately before cleanup. It never authorizes an entire container, selected volume, or broad personal folder.

## Protected categories

ByteTrail independently protects system files, installed applications, Keychain, Mail, Messages, Safari and browser profiles, cookies, account databases, cloud metadata, Photos and other media libraries, Documents, Desktop, source projects, application databases, and active development environments. It never bypasses SIP or modifies the sealed system volume.

## Path and link defenses

Containment is evaluated using standardized path components, not string prefixes. This rejects traversal and prefix-collision paths such as `Caches-escape`. Symbolic links are resolved and cannot escape an approved root; bundled cleanup rules disallow symbolic-link targets entirely. Finder aliases are analysis-only. Directory enumeration does not follow symbolic links or package descendants and is bounded by depth, item count, and time.

## Scan snapshot and TOCTOU mitigation

At scan time ByteTrail records the standardized path, file resource identifier, file type, modification date, logical and allocated size, symbolic-link and alias status, volume identifier, approved root, rule ID, and final risk. Immediately before cleanup it resolves and validates the target again. A changed identity, type, size, date, volume, rule, risk, permission, or containment result causes that item to be skipped and rescanned.

This reduces, but cannot mathematically eliminate, all time-of-check/time-of-use races in user-space software. ByteTrail fails closed when metadata is unavailable or inconsistent.

## Recovery

Normal Release behavior prefers the supported macOS Trash API. When Trash is unavailable, ByteTrail moves the item to an app-managed Recovery Vault and durably records its original path. If the recovery index cannot be saved, it attempts to roll the move back. Restore never overwrites an existing destination. Permanent deletion is not implemented.

## User cleanup flow

Cleanup has two visible steps: review the findings and explicitly select what to act on, then choose **Clean Up Selected**. There is no hidden automatic cleanup, background cleanup, or command-line cleanup trigger. The second step still performs rule, path, identity, risk, permission, and running-application checks before any move.

## Development-machine lock

Debug builds default to dry-run and enforce a second, non-configurable mutation boundary in the core cleanup layer: only a child of the standardized system temporary directory may be moved or modified. Debug Trash movement is disabled because it would cross into the real user Trash. Automated destructive-operation checks use a newly created UUID fixture directory, print its path, verify temporary-root containment, and populate it only with synthetic data.
