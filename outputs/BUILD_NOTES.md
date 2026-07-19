# ByteTrail Build Notes

## Product

- Product: ByteTrail
- Tagline: Every byte has a source.
- Version: 1.1.0
- Build: 2
- Bundle identifier: `com.bytetrail.mac`
- Deployment target: macOS 13.0
- Architectures: Universal 2 (`arm64`, `x86_64`)
- Build host: macOS 26.5.2 (25F84), Apple Silicon
- Xcode: 26.6 (17F113)
- Swift: Apple Swift 6.3.3, Swift 5 language mode

## What changed in 1.1

- Complete English and Simplified Chinese UI with an in-app language selector.
- Exact bundle-ID attribution for installed-app caches, including sandbox cache leaves.
- Recursive large-file scanning for Downloads and explicitly selected folders or volumes.
- Responsive findings UI for narrow and wide windows.
- A direct two-step user flow: Review and select, then Clean Up Selected.
- Debug builds explicitly define `DEBUG`, default to simulation, and retain the non-configurable temporary-directory mutation lock.

## Verified build commands

Xcode can remain closed. Its full toolchain is selected per command, without changing the machine-wide `xcode-select` setting. Scratch and module-cache paths stay inside the project:

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
  -derivedDataPath .build/XcodeDerivedData CODE_SIGNING_ALLOWED=NO build
```

Release arm64 and x86_64 builds used the Xcode toolchain and separate project-local scratch directories. `scripts/package_dmg.sh` merged the executables with `lipo`, embedded the localization resource bundle, ad-hoc signed the app with Hardened Runtime, and assembled the DMG from a temporary staging directory.

## Tests and safety verification

- **32/32 XCTest cases passed** through `swift test`.
- **20/20 independent safety checks passed** through `ByteTrailVerification`.
- The Xcode test target and shared scheme compile. Running the native Xcode test process from the managed Codex sandbox is blocked when Apple’s `testmanagerd` connection is denied; this does not affect running tests normally from Xcode or Terminal outside that sandbox.
- Debug Xcode settings were verified as `DEBUG`, `-Onone`, and `ENABLE_TESTABILITY=YES`.
- English and Simplified Chinese `.strings` files passed `plutil` validation and have matching key sets.

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
- Developer ID/notarization: not configured

The distributed app uses normal user permissions, no privileged helper, and no automatic Full Disk Access request. Because it is ad-hoc signed and not notarized, another Mac may require Control-click → Open.

## Artifact

DMG SHA-256:

```text
82aaedced71aeb5576bc91b3fbc4e0d3e8b78ac5dd6c858659bd936f4c78b972  ByteTrail.dmg
```

The release DMG was verified without launching ByteTrail or mounting it for inspection. Its staged source contained `ByteTrail.app`, an `/Applications` symlink, the Universal 2 executable, `CleanupRules.json`, `AppIcon.icns`, privacy and safety documents, and English/Chinese localization resources.
