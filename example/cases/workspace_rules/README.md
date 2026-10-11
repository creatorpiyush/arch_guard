# Workspace rules (monorepos)

A [Dart workspace](https://dart.dev/tools/pub/workspaces) with three members:

```text
packages/core      ← imports feature (not allowed)
packages/feature   → core
apps/shop          → core, feature
```

The rules in [`arch_guard.yaml`](arch_guard.yaml):

```yaml
workspace_rules:
  "packages/core":
    allowed: []                  # core depends on no other member
  "packages/*":
    allowed: ["packages/core"]   # shared packages may only use core
  "apps/*":
    allowed: ["packages/*"]      # apps may use any shared package
```

## Try it

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard example/cases/workspace_rules
```

```text
  Strongly Connected Component #1 (2 files)
    Representative Cycle Path:
    packages/feature/lib/feature.dart
    -> packages/core/lib/core.dart
    -> packages/feature/lib/feature.dart
    Suggested fix: remove packages/core/lib/core.dart:1 -> packages/feature/lib/feature.dart (breaks the cycle)

[!] WORKSPACE RULE VIOLATIONS (1):
  ❌ Workspace Violation: [core] packages/core/lib/core.dart:1 -> [feature] packages/feature/lib/feature.dart
     Rule: `core` (rule `packages/core`) may not import other workspace members.
```

Exit code `1`. The forbidden import also closes a cycle across packages, and both checks point at the same line.

Workspaces are discovered automatically: Dart 3.6+ `workspace:`, or Melos-style `packages/` and `apps/` folders. Use `--no-workspace` to scan only the root package.

Learn more: [Workspace rules](https://creatorpiyush.github.io/arch_guard/configuration.html#workspace-rules)
