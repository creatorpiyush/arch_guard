# Unused files

[`main.dart`](lib/main.dart) imports [`used.dart`](lib/used.dart). Nothing imports [`old/legacy.dart`](lib/old/legacy.dart) any more. [`arch_guard.yaml`](arch_guard.yaml) turns on the check and makes it fail the run:

```yaml
unused_files:
  fail: true   # unused files fail the run (exit 1)
```

## Try it

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard example/cases/unused_files
```

```text
[!] Unused files (1): no entry point imports these, directly or indirectly.
  lib/old/legacy.dart

  How to fix: delete them, or add the file that uses them under `unused_files: entry_points`.
```

Exit code `1`. Without `fail: true` the files are listed and the run still passes.

A file counts as used when an entry point reaches it through imports, exports or `part` directives, however indirectly. `lib/main*.dart` and the package's `lib/<name>.dart` are entry points by default. Add your own under `entry_points:`.

Learn more: [Unused files](https://creatorpiyush.github.io/arch_guard/configuration.html#unused-files)
