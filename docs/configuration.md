---
title: Configuration
---

# Configuration

arch_guard reads `arch_guard.yaml` in the project root, or an `arch_guard:` section in `pubspec.yaml`. The quickest start is `arch_guard init`, which writes the file for you (see [Presets](presets.md)).

## Full example

```yaml
# arch_guard.yaml
ignore:
  - "**/*.g.dart"
  - "**/*.freezed.dart"
  - "**/*.mocks.dart"

# Use a preset, or define every layer yourself under layers:
# preset: clean_architecture

fail_on_layer_violation: true

# Optional: fail when any circular-dependency group grows beyond N files,
# even with --no-fail-on-cycle (useful for ratcheting down legacy cycles).
max_scc_size: 5

# Optional: packages or core libraries no file may import.
forbidden_packages:
  - "dart:mirrors"

layers:
  domain:
    patterns:
      - "lib/**/domain/**"
    allowed_imports:
      - "domain"
    # Only for files in this layer.
    forbidden_packages: [flutter, "dart:ui"]

  data:
    patterns:
      - "lib/**/data/**"
    allowed_imports:
      - "data"
      - "domain"

  presentation:
    patterns:
      - "lib/**/presentation/**"
    allowed_imports:
      - "presentation"
      - "domain"
```

## Keys

| Key | Type | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `ignore` | list of globs | none | Extra files to leave out of the scan. Generated files such as `*.g.dart` and `*.freezed.dart` are always skipped. |
| `preset` | string | none | One of `clean_architecture`, `feature_first`, `bloc`, `riverpod`. See [Presets](presets.md). |
| `layers` | map | none | Layer name → `patterns` (globs), `allowed_imports` (layer names) and optional `forbidden_packages`. With a preset, overrides or adds layers. |
| `forbidden_packages` | list | none | Packages (`dio`) or core libraries (`dart:io`) no scanned file may import. Globs allowed (`firebase_*`). Also valid inside a layer, where it applies only to that layer's files. |
| `fail_on_layer_violation` | bool | `true` | Whether layer violations make the run exit with `1`. |
| `workspace_rules` | map | none | In a workspace: member selector → `allowed:` members it may import. See [Workspace rules](#workspace-rules). |
| `metrics` | map | none | `max_fan_out` / `max_fan_in`: fail when a file imports, or is imported by, more project files than this. `hotspots`: how many most-coupled files reports list (default 10). See [Metric limits](#metric-limits). |
| `max_scc_size` | int | none | Fail when a circular-dependency group has more files than this, even with `--no-fail-on-cycle`. |

## How layers are matched

- Patterns are [globs](https://pub.dev/packages/glob) matched against the file path relative to the project root, such as `lib/features/auth/domain/user.dart`.
- In a workspace, each path is also matched from its package's `lib/` folder, so `lib/domain/**` matches `packages/auth/lib/domain/user.dart` as well.
- A file belongs to the **first** layer whose patterns match. Put narrow layers before broad ones.
- A layer may always import itself; list it in `allowed_imports` anyway to make the rule readable.
- `import`, `export` and `part` directives all count, including every URI of a conditional import.
- Imports between files with no layer, or from a layered file to an unlayered one, are never violations themselves. But when an unlayered file re-exports a layered one (a barrel such as `lib/exports.dart`), the import of the barrel is checked against what it re-exports. Chains of unlayered barrels are followed too:

  ```text
  ❌ Layer Violation: [domain] lib/domain/user.dart:1 -> [data] lib/data/dto.dart (via lib/exports.dart)
  ```

  A barrel inside a layer is checked as an ordinary file: its own `export` of another layer is the violation.

## Reading a layer violation

```text
❌ Layer Violation: [presentation] lib/features/auth/presentation/page.dart:3 -> [data] lib/features/auth/data/repo.dart
   Rule: `presentation` may only import `core`, `domain`, `presentation`.
```

The line shows the importing file and line, both layers, and the rule that was broken. To fix it:

1. **Invert the dependency.** Put an interface in a layer the importing file may use and implement it in the other layer.
2. **Move the code** to a layer the importing file may import.
3. **Allow it**, if the dependency is intended, by adding the layer to `allowed_imports`.

## Forbidden packages

`forbidden_packages` keeps packages and core libraries out of code that should not depend on them:

```yaml
forbidden_packages: ["dart:mirrors"]   # no file may import these
layers:
  domain:
    patterns: ["lib/**/domain/**"]
    forbidden_packages: [flutter, "flutter_*", "dart:ui", "dart:io"]
```

- Entries are **package names**, not URIs: `http`, not `package:http/http.dart` (a URI is shortened to its package name).
- Entries are globs on the whole name: `flutter` matches only `package:flutter/...`; `flutter*` also matches `flutter_bloc`.
- Core libraries are written as `dart:io`; `dart:*` matches all of them.
- `import` and `export` directives both count, including every URI of a conditional import. `part` directives don't.
- A file's own package is never forbidden. Other packages of the same workspace can be.
- A top-level entry wins over a layer entry when both match; each directive is reported once.

```text
❌ Forbidden Package: [domain] lib/features/auth/domain/user.dart:1 -> package:flutter/foundation.dart
   Rule: Layer `domain` may not import `flutter` (forbidden_packages: `flutter`).
```

Forbidden imports always fail the run (exit code `1`); `fail_on_layer_violation` does not apply to them. To adopt the rule on existing code, run `arch_guard --update-baseline` once.

## Metric limits

Keep files from turning into hubs that everything depends on, or that depend on everything:

```yaml
metrics:
  max_fan_out: 20   # a file may import at most 20 project files
  max_fan_in: 40    # at most 40 project files may import it
  hotspots: 10      # most-coupled files to list in reports (0 = none)
```

- Only files inside the scanned project count; `package:` imports of other packages don't.
- Each imported file counts once, however many directives point at it. `part` files don't count.
- A file over a limit fails the run (exit code `1`) and is reported with its numbers:

  ```text
  ❌ Metric Limit: lib/app/router.dart fan_out=27 (max 20)
     Rule: `lib/app/router.dart` imports 27 files (max_fan_out: 20).
  ```

- With a baseline, a known file passes while its number stays the same or drops, and **fails again if it grows**. That makes the limit a ratchet for legacy hubs.
- Markdown and JSON reports always list the most coupled files (fan-in + fan-out). The terminal lists the top five when `metrics:` limits are set.

## Warnings

Configuration problems are reported on stderr instead of being silently ignored:

- unparseable YAML, unknown keys, wrongly typed values,
- layers whose patterns match no files (often a typo),
- `allowed_imports` that name unknown layers,
- files that belong to no layer and so are never checked.

The legacy `dep_graph.yaml` file and `dep_graph_visualizer:` pubspec key are still read, with a deprecation warning.

## Workspaces and monorepos

With `--workspace` (the default), member packages come from the `workspace:` list in the root `pubspec.yaml`. Without one, packages under `packages/` and `apps/` are discovered automatically (ignoring `example/`, `test/` and `tool/` folders). Imports between packages become edges in the graph, so cross-package cycles are found too. A single-package project is scanned using `--scan-dir` (default `lib`).

See [Presets → Workspaces and monorepos](presets.md#workspaces-and-monorepos) for layering advice on large monorepos.

## Workspace rules

Layers govern folders inside a package. `workspace_rules` govern which **packages** of a workspace may depend on which:

```yaml
workspace_rules:
  "packages/core":
    allowed: []                  # core depends on no other member
  "packages/*":
    allowed: ["packages/core"]   # shared packages may only use core
  "apps/*":
    allowed: ["packages/*"]      # apps may use any shared package
```

- Selectors and `allowed` entries are globs matched against a member's path (`packages/core`) or name (`core`). The root package's path is `.`.
- The **first** selector that matches a member applies, so put specific rules before broad ones.
- A member may always import itself. Members no selector matches are unrestricted.
- Only imports and exports between members count. Use [`forbidden_packages`](#forbidden-packages) for pub.dev packages.
- Each offending import is reported with its line and fails the run (exit code `1`). Adopt on existing code with `--update-baseline`.

```text
❌ Workspace Violation: [mobile] apps/mobile/lib/main.dart:3 -> [ui] packages/ui/lib/ui.dart
   Rule: `mobile` (rule `apps/*`) may only import members matching `packages/core`.
```

You get a warning for a selector or `allowed` entry that matches no member, and when `workspace_rules` is set in a project that isn't a workspace.
