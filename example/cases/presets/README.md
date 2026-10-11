# Presets and `arch_guard init`

A feature-first Clean Architecture layout:

```text
lib/
  core/result.dart
  features/auth/
    domain/session.dart
    data/session_dto.dart
    presentation/login_page.dart   ← imports data/session_dto.dart
```

[`arch_guard.yaml`](arch_guard.yaml) is two lines long: `preset: clean_architecture` provides the `core`, `domain`, `data` and `presentation` layers.

## Try it

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard example/cases/presets
```

```text
[!] LAYER BOUNDARY VIOLATIONS DETECTED (1):
  ❌ Layer Violation: [presentation] lib/features/auth/presentation/login_page.dart:2 -> [data] lib/features/auth/data/session_dto.dart
     Rule: `presentation` may only import `core`, `domain`, `presentation`.
  (Using preset `clean_architecture`: to change a layer's rules, list it under `layers:` with only the keys to change, e.g. `allowed_imports`.)
```

Exit code `1`.

## Let `init` pick the preset

In your own project, `init` looks at the folders and writes `arch_guard.yaml` for you:

```bash
dart run arch_guard init --dry-run   # print the config instead of writing it
dart run arch_guard init             # write arch_guard.yaml
dart run arch_guard init --preset bloc --force   # choose a preset, overwrite
```

For this layout it prints:

```yaml
# Layout: found domain/, data/, presentation/ folders.
preset: clean_architecture
```

Presets: `clean_architecture`, `feature_first`, `bloc` and `riverpod`.

Learn more: [Presets](https://creatorpiyush.github.io/arch_guard/presets.html)
