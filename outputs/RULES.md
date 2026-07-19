# ByteTrail Cleanup Rules

Rules are bundled as `Sources/ByteTrailCore/Resources/CleanupRules.json`. Remote downloading and remote rule updates are not implemented.

## Required fields

Each rule declares:

- a stable unique `id` and positive `version`;
- display name, produced-by source, source type, and category;
- one or more explicit `approvedRoots`;
- final declared `risk` (`safe`, `review`, or `protected`);
- whether the content is `regeneratable`;
- `minimumAgeDays` where age affects the decision;
- a `cleanupMethod` (`moveToTrash`, `recoveryVault`, or `analysisOnly`);
- removal reason, expected impact, detection evidence, and a plain-language description;
- whether symbolic links are allowed. Bundled rules set this to `false`.

Unknown enum values, relative roots, empty roots, duplicate identifiers, missing explanations, cleanup-capable Protected rules, and protected roots are rejected. Rule loading is all-or-nothing and fails closed.

## Finding traceability

Every finding carries its scanner identifier, matched rule identifier, exact approved root, final risk, source evidence, and scan snapshot. Scanner code discovers candidates; it does not make the final selection or cleanup decision. `SafetyPolicy` can conservatively raise risk based on attribution confidence and category. It cannot downgrade a rule’s declared risk.

## Root broadening

Changing or adding a bundled approved root is a security-sensitive rule change. Increment the rule version, explain the need in review, add containment and protected-path tests, and verify that the root does not include a protected descendant. A user-selected folder does not silently broaden an existing bundled cleanup rule: runtime rules cover only a verified cache leaf or one reviewed large file’s immediate parent, and remain subject to the protected-path policy.

## Adding a rule or scanner

1. Define the narrowest reliable approved root.
2. Identify content using documented directory semantics, not filename guesses alone.
3. Add a scanner conforming to `ScannerProtocol` and stream per-item findings and issues.
4. Add source evidence and an honest confidence level.
5. Default to Review or analysis-only when regeneration or active use is uncertain.
6. Add tests for rule validation, root containment, symbolic links, cancellation, duplicates, partial errors, default selection, changed targets, and recovery.
7. Use only unique synthetic fixtures under the system temporary directory for mutation tests.

New Safe rules require evidence that content is regeneratable, high-confidence attribution, a narrow root, a clear impact statement, and cleanup/recovery tests.
