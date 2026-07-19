# ByteTrail Build Notes

## Product

- Product: ByteTrail
- Tagline: Every byte has a source.
- Version: 1.2.2
- Build: 6
- Bundle identifier: `com.bytetrail.mac`
- Deployment target: macOS 13.0
- Architectures: Universal 2 (`arm64`, `x86_64`)
- Build host: macOS 26.5.2 (25F84), Apple Silicon
- Xcode: 26.6 (17F113)
- Swift: Apple Swift 6.3.3, Swift 5 language mode

## What changed in 1.2.2

- Added a local-only Scan Coverage report for every configured scanner root, distinguishing findings, no findings, missing paths, permission failures, partial scans, disabled scanners, and cancellation.
- Added English and Simplified Chinese coverage labels, filtering, summary metrics, and per-location finding counts.
- Replaced the adaptive top-level navigation split with a persistent resizable sidebar so Applications and Scan Coverage cannot collapse the navigation column.
- Added a dedicated Trash page that refreshes after ordinary cleanup, reviews current Trash contents, and requires a separate destructive confirmation before permanent clearing.
- Ordinary Review → Clean Up now moves eligible items only to macOS Trash and fails closed if that move is unavailable; it no longer silently falls back to the Recovery Vault.
- Clear Trash removes only immediate children of the exact current-user Trash root, continues past per-item failures, and presents an animated completion card with measured allocated bytes reclaimed.
- Debug builds reject the real user Trash entirely. Permanent-removal tests can target only UUID-named synthetic Trash fixtures inside the standardized system temporary directory.
- Fixed explicit language switching in packaged Release builds. SwiftPM lowercases the Simplified Chinese resource directory, so ByteTrail now resolves the localization advertised by the bundle with a case-insensitive match.
- Fixed Release portability by embedding both the application localization bundle and the core cleanup-rules bundle. The packaged app no longer depends on a build-machine resource path.
- Replaced the ambiguous empty cleanup sheet with a visible progress state, selected-item count, stop-after-current-item action, explicit empty state, and final per-item results.
- Successfully moved findings are removed from the current scan results, while failed or skipped findings are deselected for safe review.
- Added a visible, localized Close button to compact-window item-detail sheets; Escape remains supported.

## Included since 1.2

- Installed applications are inventoried locally from `/Applications`, `/System/Applications`, and `~/Applications`, with exact application-package sizes.
- Exact `~/Library/Caches/<Bundle ID>` matches are attributed to installed applications.
- Downloaded `.dmg` and `.pkg` installers are identified for review.
- Conservative possible-uninstall-leftover detection covers only top-level, Bundle-ID-shaped items in selected user Library locations. Results are never preselected.
- Application packages can be reviewed and moved with the normal two-step Review → Clean Up flow; system applications and ByteTrail itself remain protected.
- Overlapping application and descendant findings cannot be selected or processed twice.
- All analysis and cleanup decisions are local. There is no AI model, cloud service, analytics, telemetry, or network client integration.
- Debug Xcode builds set `COPY_PHASE_STRIP=NO` for the app target. This prevents Xcode from trying to strip the already signed embedded `ByteTrailCore.framework` and removes the corresponding build warning.
- The packaging script compiles the asset catalog with Xcode's `actool`, embeds both SwiftPM resource bundles, merges both architectures, validates the core rules, and signs the final bundle.

## Verified build commands

Xcode can remain closed. Its full toolchain is selected per command, without changing the machine-wide `xcode-select` setting. Scratch, module-cache, and DerivedData paths stay inside the project:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox --scratch-path .build/test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift run --disable-sandbox --scratch-path .build/verification ByteTrailVerification

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project ByteTrail.xcodeproj -scheme ByteTrail \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/XcodeDerivedData \
  REGISTER_APP_WITH_LAUNCH_SERVICES=NO build
```

Release arm64 and x86_64 executables were built with the Xcode toolchain in separate project-local scratch directories. `scripts/package_dmg.sh` merged them with `lipo`, compiled and embedded the asset catalog, embedded localization and safety resources, ad-hoc signed the app with Hardened Runtime, and staged the DMG from a validated system-temporary directory.

## Tests and safety verification

- **47/47 XCTest cases passed** through `swift test`.
- **21/21 independent safety checks passed** through `ByteTrailVerification`.
- A signed Debug Xcode build completed successfully without the `not stripping binary because it is signed` framework warning.
- Debug Xcode settings were verified as `DEBUG`, `-Onone`, `ENABLE_TESTABILITY=YES`, and `COPY_PHASE_STRIP=NO` for the app target.
- English and Simplified Chinese `.strings` files passed `plutil` validation and have matching key sets. A packaged-resource probe resolved `zh-Hans` to SwiftPM's `zh-hans` directory and read the Chinese string successfully.

Every destructive-operation test created a UUID-named synthetic fixture under the standardized system temporary directory, printed and validated that path before populating it, and refused to proceed if containment failed. No destructive-operation test touched real user caches, Trash, Downloads, Desktop, Documents, Xcode data, package-manager data, backups, external volumes, or cloud folders. Debug Trash movement was never executed.

The GUI was not launched during automated verification because a normal macOS GUI launch may write preference or window-state files outside the allowed workspace. A command-line build, test, verification, or package step never starts a scan or cleanup automatically.

## Release verification

- `codesign --verify --deep --strict`: passed
- Signature: ad-hoc
- Hardened Runtime: enabled (`runtime` CodeDirectory flag)
- App Sandbox: disabled
- Entitlements: empty
- Executable: Universal 2 (`x86_64`, `arm64`)
- DMG checksum verification: passed
- Read-only DMG mount inspection: passed
- Developer ID/notarization: not configured

The distributed app uses normal user permissions, no privileged helper, and no automatic Full Disk Access request. Because it is ad-hoc signed and not notarized, another Mac may require Control-click → Open. Developer ID signing and Apple notarization remain necessary for a frictionless public release.

## Artifact

DMG SHA-256:

```text
4f595ef5f055abf3482df9210462edd5e6b4914b6a4ab6d41a3f26cc4bec7fcd  ByteTrail.dmg
```

The release DMG was mounted read-only at a validated `/private/tmp` mount point and inspected without launching ByteTrail. It contained only `ByteTrail.app` and an `/Applications` symlink; the mounted app passed strict code-signature verification and reported version 1.2.2 (build 6) with both `x86_64` and `arm64`. The app contains the SwiftPM core-rules and application-localization bundles, `AppIcon.icns`, the compiled asset catalog, and privacy and safety documents.
