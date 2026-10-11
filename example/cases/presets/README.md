# Presets and `arch_guard init`

A feature-first Clean Architecture layout:

```text
lib/
  core/result.dart
  l10n/strings.dart                ← an extra layer, added below
  features/auth/
    domain/session.dart
    data/session_dto.dart
    presentation/login_page.dart   ← imports data/session_dto.dart and l10n/strings.dart
```

In [`arch_guard.yaml`](arch_guard.yaml), `preset: clean_architecture` provides the `core`, `domain`, `data` and `presentation` layers. The `layers:` section then changes only what this project needs:

```yaml
preset: clean_architecture
fail_on_layer_violation: true

layers:
  l10n:                       # new layer name: added
    patterns: ["lib/l10n/**"]
    allowed_imports: [l10n]
  presentation:               # existing layer: only allowed_imports changes
    allowed_imports: [core, domain, presentation, l10n]
```

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

Exit code `1`. The `l10n` import is allowed by the override; the `data` import is still reported.

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

Each preset's folder layout, layers and typical violation are described here: [`clean_architecture`](https://creatorpiyush.github.io/arch_guard/presets.html#clean-architecture) · [`feature_first`](https://creatorpiyush.github.io/arch_guard/presets.html#feature-first) · [`bloc`](https://creatorpiyush.github.io/arch_guard/presets.html#bloc) · [`riverpod`](https://creatorpiyush.github.io/arch_guard/presets.html#riverpod).

Learn more: [Presets](https://creatorpiyush.github.io/arch_guard/presets.html)
