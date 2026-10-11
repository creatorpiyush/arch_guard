# What gets scanned: `--scan-dir`, `--exclude`, config in `pubspec.yaml`

This project has no `arch_guard.yaml`. Its rules are in an `arch_guard:` section of [`pubspec.yaml`](pubspec.yaml) instead:

- `domain` imports only `domain`.
- `data` may import `domain`.
- `app` (the files in `bin/`) may import `domain`.

```text
bin/main.dart                          → imports data (not allowed for app)
lib/domain/order.dart                  part 'order_total.dart'
lib/domain/order_total.dart            part of 'order.dart'
lib/domain/generated/order_mapper.dart → imports data (generated code)
lib/data/order_row.dart                → domain
```

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

## 1. Default: only `lib/`

```bash
dart run arch_guard example/cases/scan_options
```

```text
Files Scanned: 4
  ❌ Layer Violation: [domain] lib/domain/generated/order_mapper.dart:2 -> [data] lib/data/order_row.dart
     Rule: `domain` may only import `domain`.
```

Exit code `1`. `bin/` is not scanned. The `part` file is scanned together with its library. Part edges count when looking for cycles, but a cycle hint never suggests removing a `part`.

## 2. `--exclude`: skip generated code

```bash
dart run arch_guard example/cases/scan_options --exclude "lib/**/generated/**"
```

```text
Files Scanned: 3
```

Exit code `0`. `--exclude` can be repeated. For a permanent rule, use `ignore:` in the config; see [layers](../layers/README.md). Files ending in `.g.dart`, `.freezed.dart`, `.mocks.dart` or `.gr.dart` are always skipped.

## 3. `--scan-dir`: check `bin/` too

```bash
dart run arch_guard example/cases/scan_options --scan-dir lib --scan-dir bin --exclude "lib/**/generated/**"
```

```text
Files Scanned: 4
  ❌ Layer Violation: [app] bin/main.dart:1 -> [data] lib/data/order_row.dart
     Rule: `app` may only import `app`, `domain`.
```

Exit code `1`. `package:scan_options/...` imports resolve to `lib/`.

## Other everyday flags

```bash
dart run arch_guard --no-color          # plain output for CI logs
dart run arch_guard --version           # arch_guard 1.7.0
dart run arch_guard --help              # every option
```

Learn more: [CLI options](https://creatorpiyush.github.io/arch_guard/cli.html#options) · [Configuration](https://creatorpiyush.github.io/arch_guard/configuration.html)
