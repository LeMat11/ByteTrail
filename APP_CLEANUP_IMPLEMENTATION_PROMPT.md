# ByteTrail App & Leftover Cleanup — Implementation Prompt

You are a senior macOS engineer, SwiftUI developer, product designer, file-system safety engineer, and privacy reviewer working on ByteTrail.

Implement ByteTrail 1.2 as a completely local macOS application-storage analyzer. Preserve the existing bilingual interface, deterministic rules, evidence display, scan snapshots, recovery history, and development-machine safety lock.

## Product goal

Keep the feature intentionally small:

1. Discover installed application bundles and calculate their local disk usage.
2. Associate only an installed application's exact Bundle-ID cache.
3. Continue detecting downloaded `.dmg` and `.pkg` installers.
4. Detect conservative **possible uninstall leftovers**: exact top-level entries whose Bundle-ID-shaped identifier has no matching installed application.

Do not implement full application-data cleanup for installed apps. In particular, do not offer active-app Preferences, Application Support, Saved State, Logs, full sandbox Containers, Group Containers, login items, launch agents, helpers, system extensions, or vendor uninstallers as ordinary associated cleanup components.

Do not add AI, Markdown manifests, cloud classification, remote rules, accounts, telemetry, analytics, advertising, update checks, or any network-backed feature.

## Privacy promise

Every operation must happen locally on the current Mac:

- Scan only local file-system metadata, application bundle metadata, and file sizes.
- Never upload file names, paths, Bundle IDs, installed-app lists, scan results, cleanup history, or recovery records.
- Do not add `URLSession`, `Network.framework`, sockets, WebSockets, web views, analytics SDKs, crash-upload SDKs, remote configuration, or HTTP endpoints.
- The application must remain fully functional while the Mac is offline.
- UI and privacy documentation must state that ByteTrail has no account, cloud service, telemetry, or network requests.
- Treat the absence of network behavior as a product feature and an acceptance criterion.

## Installed applications

Build a read-only inventory from:

- `/Applications`
- `/System/Applications`
- `~/Applications`

Read Bundle ID, display name, version, and build through `Bundle`. Calculate logical and allocated size while traversing package descendants without following symbolic links.

For an installed app with Bundle ID `<bundle-id>`, associate only this exact cache path:

- `~/Library/Caches/<bundle-id>`

Do not guess ownership from display names, vendor names, partial matches, fuzzy matches, or natural-language inference.

## Possible uninstall leftovers

Enumerate only immediate children of these local roots:

- `~/Library/Caches`
- `~/Library/Preferences`
- `~/Library/Logs`
- `~/Library/Saved Application State`
- `~/Library/Application Support`
- `~/Library/Containers`

Derive a candidate Bundle ID only through an exact filename convention:

- directory/file name exactly equals a Bundle-ID-shaped identifier;
- Preferences may remove one terminal `.plist` extension;
- Saved State may remove one terminal `.savedState` extension.

A candidate is a possible leftover only when:

- the normalized identifier has a conservative Bundle-ID shape;
- no installed application has that exact Bundle ID;
- it is not ByteTrail;
- it does not start with `com.apple.`;
- the target is one immediate child of the enumerated root;
- it is not a symbolic link or Finder alias;
- it is not inside a protected personal, system, cloud, mail, browser, credential, or media location.

Absence from `/Applications` is evidence only, not proof of safe deletion. Label every result as **Possible Leftover**, use Review risk, never preselect it, and explain that a background tool, helper, or removed app may still rely on the data.

Do not scan Group Containers. Do not recursively invent additional ownership. Do not combine multiple roots into one destructive target. Each exact top-level entry remains independently reviewable and recoverable.

## Risk policy

- Installed application bundle: Review, never preselected.
- Exact cache belonging to an installed app: Safe and may be preselected.
- Possible uninstall leftover: Review, never preselected, Recovery Vault cleanup.
- Downloaded `.dmg` or `.pkg`: existing Review behavior.
- `/System/Applications`: Protected and analysis-only.
- ByteTrail itself (`com.bytetrail.mac`): Protected and analysis-only.
- Running applications and their cache: not selectable; require quit and rescan.
- Application bundles not writable with current permissions: analysis-only. Do not add a privileged helper.
- Unknown, inaccessible, malformed, aliased, symbolic-link, changed, or ambiguous targets fail closed.

An installed application is a narrowly bounded exception to `/Applications` protection only when the cleanup target is one exact validated `.app` bundle. A runtime rule must never approve `/Applications`, `~/Applications`, `/System/Applications`, a home directory, a volume, or any application parent directory.

## User experience

Keep exactly two visible cleanup steps:

1. **Review**: the user inspects App size, cache, possible leftovers, installers, path, risk, ownership evidence, and removal impact, then explicitly selects targets.
2. **Cleanup**: the existing cleanup button immediately revalidates and processes selected targets. Do not add a third confirmation screen.

Add an Applications sidebar destination with:

- search by app name or Bundle ID;
- sorting by total size;
- local application icon;
- application-bundle size and exact-cache size;
- component checkboxes using existing eligibility;
- running, protected, and permission status;
- a visible local-only privacy message;
- the existing cleanup-results sheet.

Expose Possible Leftovers as a clear category in Review & Clean Up and the overview summary. Never describe a candidate as definitely safe merely because the app is not currently installed.

## Cleanup behavior

- Release builds move selected application bundles and installers with the supported macOS Trash API.
- Possible leftovers use the Recovery Vault so they can be restored.
- Never permanently delete files or empty Trash.
- Immediately before mutation, revalidate exact rule, standardized and resolved containment, resource identifier, type, modification date, symbolic-link status, volume, risk, and permission.
- Keep per-item history and report partial failures without stopping unrelated selected items.
- No cleanup may run automatically on launch, build, scan, test, or command-line invocation.

## Development-machine safety

During development and automated verification, never modify a real application, cache, Container, preference, log, user document, Trash item, Xcode directory, package-manager directory, external volume, network volume, or cloud-storage directory.

All destructive-operation tests must:

1. create a unique synthetic fixture under the standardized system temporary directory;
2. print the resolved fixture path;
3. verify containment inside the system temporary directory;
4. populate only synthetic `.app`, cache, installer, and leftover fixtures;
5. refuse mutation if containment validation fails.

Debug builds must default to dry-run. The core Debug mutation lock must remain non-configurable and reject every non-temporary mutation. Debug tests must never call the real Trash API.

## Engineering requirements

- Add explicit application-bundle and possible-leftover scan categories with bilingual labels.
- Add injectable `ApplicationScanner` and `ApplicationLeftoverScanner` implementations to the default coordinator and settings.
- Traverse package descendants only for application-size calculation; preserve enumeration limits and link avoidance.
- Generate exact runtime rules for each `.app`, installed-app cache, and individual leftover candidate.
- Preserve exclusions, cancellation, progress, per-source issues, evidence, and deduplication.
- Update privacy, safety, limitations, development, version, and the source documentation copied by future packaging runs.
- Do not add third-party packages.

## Required tests

Use only temporary synthetic fixtures to verify:

- exact installed-app Bundle ID discovery;
- application size includes nested package contents;
- only exact installed-app cache paths are attributed;
- lookalike cache paths are not attributed;
- Bundle-ID-shaped orphan entries become Review leftovers;
- installed IDs, `com.apple.*`, ByteTrail, malformed names, nested items, links, and aliases are excluded from cleanable leftovers;
- app bundle and leftovers are never preselected;
- system and self applications are Protected/analysis-only;
- runtime app rules approve only one exact `.app`, never its parent Applications directory;
- changed targets fail closed;
- Debug cleanup and recovery remain inside temporary fixtures;
- all existing tests still pass;
- source/dependency audit finds no network client or telemetry implementation.

## Acceptance criteria

- Scan results show installed apps, exact installed-app caches, downloaded installers, and conservative possible leftovers with allocated-size totals.
- Review → Cleanup remains a two-step flow.
- System, self, running, permission-denied, ambiguous, malformed, linked, or changed targets cannot be cleaned.
- Possible leftovers are individually reviewed and recoverable.
- No real user data is modified during development verification.
- The app contains no network feature and performs no data transmission.
- Swift Package tests, the independent verification harness, and an unsigned Xcode Debug build succeed.
