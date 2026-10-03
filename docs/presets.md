---
title: Presets
---

[Home](index.md) · [Presets](presets.md) · [Configuration](configuration.md) · [CI & hooks](ci.md) · [CLI](cli.md) · [Dart API](api.md)

# Presets

A preset is a ready-made set of layers. One line in `arch_guard.yaml` turns it on:

```yaml
preset: clean_architecture
```

`arch_guard init` picks a preset by looking at your folders and writes the expanded layers into the config as comments, so you can see exactly what is checked.

```bash
arch_guard init                      # detect the layout and write arch_guard.yaml
arch_guard init --preset bloc        # auto | none | clean_architecture | feature_first | bloc | riverpod
arch_guard init --dry-run            # print the config instead of writing it
arch_guard init --force              # overwrite an existing arch_guard.yaml
```

After writing the file, `init` scans the project and prints how many files fall into each layer, how many violations and cycles exist, and what to do next.

## How preset patterns match

- Patterns have the form `lib/**/<layer>/**`. Both layer-first (`lib/domain/user.dart`) and feature-first (`lib/features/auth/domain/user.dart`) layouts match.
- A file belongs to the **first** layer whose pattern matches. The order of the layers below is the order they are tried in.
- In a workspace, patterns are matched from each package's own `lib/` folder. A package *named* `core` or `data` is not mistaken for that layer; the `domain/`, `data/` and other folders inside it are checked as usual.
- Files that match no layer are listed in a warning and are never checked for layer violations.

## Clean Architecture

```text
lib/
  core/            # shared utilities, errors, DI helpers
  features/
    auth/
      domain/      # entities, repository interfaces, use cases
      data/        # models, data sources, repository implementations
      presentation/  # pages, widgets, blocs/notifiers
```

| Layer | Patterns | May import |
| :--- | :--- | :--- |
| `core` | `lib/**/core/**` | `core` |
| `domain` | `lib/**/domain/**` | `core`, `domain` |
| `data` | `lib/**/data/**` | `core`, `domain`, `data` |
| `presentation` | `lib/**/presentation/**`, `lib/**/ui/**` | `core`, `domain`, `presentation` |

Typical violation: a page imports a data model directly.

```text
❌ Layer Violation: [presentation] lib/features/auth/presentation/login_page.dart:5 -> [data] lib/features/auth/data/models/user_dto.dart
   Rule: `presentation` may only import `core`, `domain`, `presentation`.
```

Fix: expose a `User` entity from `domain` and map the DTO to it in the repository implementation. If your team deliberately lets the UI use data models, allow it instead:

```yaml
preset: clean_architecture
layers:
  presentation:
    allowed_imports: [core, domain, presentation, data]
```

## Riverpod

Follows the [Riverpod app architecture](https://codewithandrea.com/articles/flutter-app-architecture-riverpod-introduction/) with `domain`, `data`, `application` and `presentation` folders. `init` picks it when it finds an `application/` folder and a Riverpod dependency.

| Layer | Patterns | May import |
| :--- | :--- | :--- |
| `domain` | `lib/**/domain/**` | `domain` |
| `data` | `lib/**/data/**` | `data`, `domain` |
| `application` | `lib/**/application/**` | `application`, `domain`, `data` |
| `presentation` | `lib/**/presentation/**` | `presentation`, `application`, `domain`, `data` |

Typical violation: a domain model imports a repository.

```text
❌ Layer Violation: [domain] lib/src/features/cart/domain/cart.dart:3 -> [data] lib/src/features/cart/data/cart_repository.dart
   Rule: `domain` may only import `domain`.
```

Fix: keep `domain` free of I/O; move the logic that needs the repository into an `application` service.

## Bloc

For apps organised the way the [Bloc docs](https://bloclibrary.dev/architecture/) describe: UI → bloc/cubit → repository → data provider.

| Layer | Folders (each matched as `lib/**/<folder>/**`) | May import |
| :--- | :--- | :--- |
| `models` | `models`, `model` | `models` |
| `business_logic` | `bloc`, `blocs`, `cubit`, `cubits` | `business_logic`, `repository`, `models` |
| `repository` | `repository`, `repositories` | `repository`, `data_provider`, `models` |
| `data_provider` | `data_provider`, `data_providers`, `api`, `clients` | `data_provider`, `models` |
| `presentation` | `view`, `views`, `pages`, `screens`, `widgets` | `presentation`, `business_logic`, `models` |

Typical violation: a page calls a repository instead of going through its bloc.

```text
❌ Layer Violation: [presentation] lib/counter/view/counter_page.dart:4 -> [repository] lib/repositories/counter_repository.dart
   Rule: `presentation` may only import `presentation`, `business_logic`, `models`.
```

Fix: inject the repository into the bloc (for example with `RepositoryProvider`) and have the page talk only to the bloc.

## Feature-first

One layer per folder in `lib/features` (or `lib/modules` if there is no `lib/features`), plus a `shared` layer for `lib/core`, `lib/shared` and `lib/common`.

```text
lib/
  core/        # shared
  features/
    auth/      # layer feature_auth
    cart/      # layer feature_cart
```

| Layer | Patterns | May import |
| :--- | :--- | :--- |
| `shared` | `lib/core/**`, `lib/shared/**`, `lib/common/**` | `shared` |
| `feature_<name>` | `lib/features/<name>/**` | itself, `shared` |

Typical violation: one feature reaches into another.

```text
❌ Layer Violation: [feature_cart] lib/features/cart/cart_page.dart:6 -> [feature_auth] lib/features/auth/session.dart
   Rule: `feature_cart` may only import `feature_cart`, `shared`.
```

Fix: move what both features need into `lib/shared`, or let the features talk through an interface in `shared`.

The feature list is read from disk when arch_guard runs, so new feature folders are covered without editing the config. Feature folders inside workspace packages are not discovered yet; list them under `layers:` yourself.

## Workspaces and monorepos

All presets work in a Dart workspace: every package is matched from its own `lib/` folder. Two things are worth knowing on a large monorepo:

- **Shared packages often belong to no layer.** A package such as `packages/core` whose files are not inside `domain/`, `data/` and so on is reported as unassigned. Give it a layer of its own and let the others import it:

  ```yaml
  preset: clean_architecture
  layers:
    core_package:
      patterns: ["packages/core/lib/**"]
      allowed_imports: [core_package]
    domain:
      allowed_imports: [core, domain, core_package]
    data:
      allowed_imports: [core, domain, data, core_package]
    presentation:
      allowed_imports: [core, domain, presentation, core_package]
  ```

  New layers are tried after the preset's layers, so `packages/core/lib/domain/...` still counts as `domain`.

- **Start with a baseline.** The first scan of a big codebase usually finds dozens of violations. Run `arch_guard --update-baseline`, commit `arch_guard_baseline.json`, and only new problems will fail CI. See [CI & hooks](ci.md#adopting-on-an-existing-codebase-baseline).

## Adjusting a preset

List a layer under `layers:` with only the keys you want to change; the other keys keep the preset's values. New layer names are added after the preset's layers.

```yaml
preset: clean_architecture
layers:
  presentation:
    allowed_imports: [core, domain, presentation, data]   # allow UI -> data
  di:
    patterns: ["lib/di/**"]
    allowed_imports: [core, domain, data, presentation, di]
```
