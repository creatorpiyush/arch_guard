# Hybrid layout: Riverpod with Bloc leftovers

A Riverpod app that still has a `bloc/` folder from before the migration:

```text
lib/features/auth/
  domain/user.dart
  data/auth_repository.dart
  application/auth_service.dart
  bloc/auth_bloc.dart                    ← imports presentation/widgets/error_banner.dart
  presentation/login_page.dart           ← imports bloc/auth_bloc.dart
  presentation/widgets/error_banner.dart
```

No preset has a layer for `bloc/`, so with `preset: riverpod` alone those files would belong to no layer and go unchecked.

## Let `init` write the config

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard init example/cases/hybrid_layout --dry-run
```

`init` finds the Riverpod layout (`application/` plus a `flutter_riverpod` dependency) and the `bloc/` folder next to it. It adds a `bloc` layer that may import what the UI may, and lets the UI import it. The generated [`arch_guard.yaml`](arch_guard.yaml) contains:

```yaml
# Layout: found domain/, data/, presentation/, application/ folders and a Riverpod dependency, plus bloc/ folders.
preset: riverpod

layers:
  bloc:
    patterns: ["lib/**/bloc/**"]
    allowed_imports: [bloc, application, domain, data]
  presentation:
    allowed_imports: [presentation, application, domain, data, bloc]
```

```text
First scan: 6 files
  domain        1 file(s)
  data          1 file(s)
  application   1 file(s)
  presentation  2 file(s)
  bloc          1 file(s)
  1 layer violation(s), 0 circular dependency group(s)
```

`cubit/`, `blocs/` and `cubits/` folders are picked up the same way, and so is a `clean_architecture` layout with blocs.

## Check it

```bash
dart run arch_guard example/cases/hybrid_layout
```

```text
[!] LAYER BOUNDARY VIOLATIONS DETECTED (1):
  ❌ Layer Violation: [bloc] lib/features/auth/bloc/auth_bloc.dart:2 -> [presentation] lib/features/auth/presentation/widgets/error_banner.dart
     Rule: `bloc` may only import `bloc`, `application`, `domain`, `data`.
```

Exit code `1`. `login_page.dart` using the bloc is fine; the bloc reaching back into a widget is not. Fix it by having the bloc emit an error state that the page shows.

Blocs inside a `presentation/` folder (`presentation/bloc/`) still count as `presentation`: a file belongs to the first layer that matches, and the preset's layers come first.

Learn more: [Presets](https://creatorpiyush.github.io/arch_guard/presets.html)
