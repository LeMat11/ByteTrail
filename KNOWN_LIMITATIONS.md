# ByteTrail 1.1 Known Limitations

- ByteTrail explains identifiable sources; it does not reproduce Apple’s internal System Data calculation and totals may differ substantially.
- Normal access covers many user locations, but macOS privacy controls may deny Trash, MobileSync backups, or other sources. Full Disk Access is not requested at first launch and permission must be verified after the user changes it.
- The distributed build is intentionally not App Sandbox-enabled because fixed developer caches and multiple user Library roots cannot be usefully enumerated with sandbox container access alone. It uses no privileged helper and requests no unrelated entitlement.
- Application caches are attributed only when an exact bundle identifier resolves to an installed app. Unknown cache/log names and group-container ownership remain Unknown confidence; ByteTrail never invents a producer.
- The original location of a pre-existing Trash item is shown only when reliable metadata exists. ByteTrail normally displays “Original location unavailable.”
- Application-leftover detection is not included because reliable uninstall attribution could not be guaranteed conservatively.
- Simulator cache usage is analysis-only. No simulator data is cleaned because robust active-simulator detection is not implemented.
- Downloads and user-selected folders or external volumes are scanned recursively for large regular files. Packages, links, aliases, cross-volume descendants, and undownloaded cloud placeholders are skipped. Protected personal locations remain analysis-only even when selected.
- A full-volume scan, hierarchical treemap, content inspection, and nested drill-down are not included. Results are capped so an extremely broad selection cannot grow without bound.
- `.zip` files are not assumed to be installers. Only `.dmg` and `.pkg` are recognized by the installer scanner.
- Permanent deletion, automatic Trash emptying, automatic Recovery Vault expiration, browser-data cleaning, `node_modules` cleanup, virtual-environment cleanup, installed-package cleanup, and system-wide scanning are not implemented.
- Cleanup history and Recovery Vault retention settings are displayed, but automatic pruning is not enabled so no recovered data disappears without awareness.
- ByteTrail reports validated bytes processed by an operation but does not yet calculate a before/after volume-capacity delta, so it does not claim an exact amount of immediately reclaimed space after moving an item to Trash or Recovery Vault.
- No real user caches, Trash, Downloads, Xcode data, package-manager data, or backups were scanned during automated release verification. Scanner integration was exercised only with synthetic temporary fixtures to preserve the development-machine safety boundary; per-location permission status must therefore be established on first user-initiated scan.
- Xcode 26.6 and its full macOS SDK compile the project successfully. The native Xcode test runner cannot communicate with `testmanagerd` inside the managed Codex sandbox; all 32 XCTest cases were therefore run successfully through Swift Package Manager, and the 20-check independent safety harness also passed.
- The GUI was not launched during release verification because even a non-scanning macOS launch may write window-state or preference files outside the workspace. Startup behavior therefore requires manual validation on a test account or isolated machine.
- No Developer ID Application identity or notarization credentials are installed. The delivered app is ad-hoc signed and the DMG is not notarized; Gatekeeper may require Control-click → Open on another Mac.
