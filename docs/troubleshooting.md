---
title: Troubleshooting
description: Answers for when an arch_guard result surprises you.
---

# Troubleshooting

Each entry starts with what you see. Still stuck? [Open an issue](https://github.com/creatorpiyush/arch_guard/issues) with the command and its output.

## Configuration

### `N file(s) belong to no layer and are not checked`

No layer's patterns match these files, so their imports are never checked. Either add a layer whose `patterns` cover them, or leave them out with `ignore:`. A file such as `lib/main.dart` often belongs to no layer on purpose. See [How layers are matched](configuration.md#how-layers-are-matched).

### Layer `x` matched no scanned files

Usually a typo, or a pattern written from the wrong folder. Patterns are matched against the path from the project root (`lib/features/auth/domain/user.dart`), so `domain/**` matches nothing; use `lib/**/domain/**`.

### A file is in the wrong layer

A file belongs to the **first** layer whose patterns match. Put narrow layers before broad ones. With a preset, layers you add are tried after the preset's layers.

### An import I expected to fail passes

- The imported file belongs to no layer. Imports into unlayered files are never violations, except through a barrel file that re-exports a layered one.
- The import has an `// ignore: arch_guard_lint/...` comment on the line above.
- It is in the baseline. Run with `--baseline none.json` to see every problem, known or not.
- With `--since`, only changed files are reported.

### `dep_graph.yaml is deprecated; rename it to arch_guard.yaml`

The tool used to be called `dep_graph_visualizer`. Rename the file, or the `dep_graph_visualizer:` key in `pubspec.yaml` to `arch_guard:`. Nothing else changes.

## Cycles

### A cycle I added to was not reported

A baseline cycle is known by its **files**, not its imports. A new import between files that are already in one known cycle doesn't change the group, so it passes. A cycle that gains a file, or merges two known cycles, fails. To cap the size of any cycle, set [`max_scc_size`](configuration.md#keys).

### A cycle marked `Platform-specific`

The loop only exists through a conditional import (`if (dart.library.io)`). It still fails the run, because on that platform it is real. Break it the same way: remove the import on the `Suggested fix:` line, or move the shared code into a third file.

## Changed files and CI

### `--since: cannot compare with "origin/main"`

Git cannot find the merge base. Check that the ref exists locally. In GitHub Actions, check out with full history:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
```

`--since` also needs git 2.30 or newer.

### `affected` printed nothing and every test ran

`dart test` with no paths runs everything. Guard the call:

```bash
t=$(arch_guard affected --since origin/main); [ -n "$t" ] && dart test $t
```

### `dart run arch_guard` is slow in CI

`dart run` adds about a second of Dart startup. The [GitHub Action](ci.md#github-action) and the [standalone binaries](cli.md#standalone-binaries) don't. A full run takes about 0.07 s per 1,000 files; see [How long a run takes](ci.md#how-long-a-run-takes).

## Unused files

### A file I use is reported as unused

Nothing reachable from an entry point imports it. Common reasons:

- It is used only from a folder that isn't scanned, such as `bin/` or `test/`. Scan that folder too (`--scan-dir lib --scan-dir bin`).
- Your app starts from a file that isn't a default entry point. Add it under `unused_files: entry_points`.
- It is reached only through code generation or reflection. Add it under `entry_points`.

### `unused_files: no scanned file matches an entry point`

No scanned file is `lib/main.dart`, `lib/<package>.dart`, a test or another [default entry point](configuration.md#default-entry-points), so nothing is reported. Add your app's entry file under `entry_points`.

## IDE plugin

### No warnings in the editor

- The plugin needs Dart 3.10 / Flutter 3.38 or later.
- Restart the analysis server after adding it (VS Code: *Dart: Restart Analysis Server*).
- Only files under `lib/` are checked, and problems in the baseline are hidden.

### The CLI finds a cycle the editor doesn't

The plugin checks one package's `lib/`. Cycles across workspace packages are found by the CLI only. See [IDE warnings](ide.md#circular-dependencies).
