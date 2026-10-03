---
title: Configuration
---

[Home](index.md) · [Presets](presets.md) · [Configuration](configuration.md) · [CI & hooks](ci.md) · [CLI](cli.md) · [Dart API](api.md)

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

layers:
  domain:
    patterns:
      - "lib/**/domain/**"
    allowed_imports:
      - "domain"

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
| `layers` | map | none | Layer name → `patterns` (globs) and `allowed_imports` (layer names). With a preset, overrides or adds layers. |
| `fail_on_layer_violation` | bool | `true` | Whether layer violations make the run exit with `1`. |
| `max_scc_size` | int | none | Fail when a circular-dependency group has more files than this, even with `--no-fail-on-cycle`. |

## How layers are matched

- Patterns are [globs](https://pub.dev/packages/glob) matched against the file path relative to the project root, such as `lib/features/auth/domain/user.dart`.
- In a workspace, each path is also matched from its package's `lib/` folder, so `lib/domain/**` matches `packages/auth/lib/domain/user.dart` as well.
- A file belongs to the **first** layer whose patterns match. Put narrow layers before broad ones.
- A layer may always import itself; list it in `allowed_imports` anyway to make the rule readable.
- Imports between files with no layer, or from a layered file to an unlayered one, are never violations.

## Reading a layer violation

```text
❌ Layer Violation: [presentation] lib/features/auth/presentation/page.dart:3 -> [data] lib/features/auth/data/repo.dart
   Rule: `presentation` may only import `core`, `domain`, `presentation`.
```

The line shows the importing file and line, both layers, and the rule that was broken. To fix it:

1. **Invert the dependency.** Put an interface in a layer the importing file may use and implement it in the other layer.
2. **Move the code** to a layer the importing file may import.
3. **Allow it**, if the dependency is intended, by adding the layer to `allowed_imports`.

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
