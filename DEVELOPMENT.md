# ByteTrail Development Guide

Keep the source project; remove generated build artifacts when space matters.

## Keep in Git

- `ByteTrail.xcodeproj/`
- `Sources/`
- `Tests/`
- `Configuration/`
- `scripts/`
- `Package.swift`
- the root privacy, safety, rules, limitations, and development documentation
- text files in `outputs/`, including build notes and the DMG checksum

These files are small and are required to compile, test, debug, or add features. A Markdown summary alone cannot replace the Swift source, rules, tests, or Xcode project.

## Do not keep in Git

- `.build/`: Swift compiler outputs, module caches, indexes, Debug and Release objects
- `DerivedData/`: Xcode-generated build and index data
- `outputs/ByteTrail.app`: reproducible application bundle
- `outputs/ByteTrail.dmg`: reproducible installer image
- `xcuserdata/` and `*.xcuserstate`: machine-specific Xcode state

The ignored files can be regenerated from source. The final `.app` and `.dmg` may be kept locally for installation or attached to a release outside the Git repository.

## Local verification

The exact commands used for the current release are recorded in `outputs/BUILD_NOTES.md`. Xcode may remain closed: select its toolchain per command and keep all build and module caches inside the project:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift build --disable-sandbox --scratch-path .build/dev

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox --scratch-path .build/test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift run --disable-sandbox --scratch-path .build/verification ByteTrailVerification
```

On a Mac with full Xcode:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project ByteTrail.xcodeproj -scheme ByteTrail \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/XcodeDerivedData \
  CODE_SIGNING_ALLOWED=NO REGISTER_APP_WITH_LAUNCH_SERVICES=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project ByteTrail.xcodeproj -scheme ByteTrail \
  -configuration Debug -derivedDataPath .build/XcodeDerivedData test
```

Debug cleanup is locked to synthetic fixtures inside the system temporary directory. Never weaken that lock to test against real user data.
