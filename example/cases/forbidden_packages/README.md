# Forbidden packages

[`arch_guard.yaml`](arch_guard.yaml) forbids packages in two places:

- At the top level, `forbidden_packages: ["dart:mirrors"]` applies to the whole project.
- Under the `domain` layer, `forbidden_packages: ["dart:io", "flutter", "firebase_*"]` applies only to that layer. Globs are allowed.

| File | Import | Result |
| :--- | :--- | :--- |
| [`domain/clock.dart`](lib/domain/clock.dart) | `dart:io` | ❌ forbidden in `domain` |
| [`data/file_store.dart`](lib/data/file_store.dart) | `dart:io` | ✅ allowed in `data` |
| [`data/serializer.dart`](lib/data/serializer.dart) | `dart:mirrors` | ❌ forbidden everywhere |

## Try it

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard example/cases/forbidden_packages
```

```text
[!] FORBIDDEN PACKAGE IMPORTS (2):
  ❌ Forbidden Package: lib/data/serializer.dart:1 -> dart:mirrors
     Rule: `dart:mirrors` is forbidden in this project (forbidden_packages: `dart:mirrors`).
  ❌ Forbidden Package: [domain] lib/domain/clock.dart:1 -> dart:io
     Rule: Layer `domain` may not import `dart:io` (forbidden_packages: `dart:io`).
```

Exit code `1`. Forbidden packages always fail the run.

The [`arch_guard_lint`](https://pub.dev/packages/arch_guard_lint) analyzer plugin underlines these imports in your IDE as you type.

Learn more: [Forbidden packages](https://creatorpiyush.github.io/arch_guard/configuration.html#forbidden-packages)
