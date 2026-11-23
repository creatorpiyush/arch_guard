# Unused and misplaced dependencies

`pubspec_check:` reports `dependencies:` entries that no Dart file imports
(unused) and ones that only test code imports (misplaced, which belong under
`dev_dependencies:`).

```bash
dart run arch_guard example/cases/unused_dependencies
```

Here `collection` is never imported and `mocktail` is used only from
`test/`, so both are reported. `path` is used from `lib/`, and `test` is a
dev dependency, which is never checked. With `fail: true` the run exits `1`:

```text
[!] Unused or misplaced dependencies (2):
  pubspec.yaml:9 collection (unused)
     `collection` is under dependencies in pubspec.yaml but nothing imports it. Remove it, or add it to pubspec_check: ignore.
  pubspec.yaml:10 mocktail (misplaced)
     `mocktail` is used only from tests; move it to dev_dependencies in pubspec.yaml.
```

Without `fail: true` the same list is printed but the run passes.
