# Layer rules

A layer-first project with `domain`, `data` and `presentation` layers. The rules live in [`arch_guard.yaml`](arch_guard.yaml):

- `domain` imports only `domain`.
- `data` may import `domain`.
- `presentation` may import `domain`, but **not** `data`.

[`profile_page.dart`](lib/presentation/profile_page.dart) breaks the last rule by importing a data DTO.

The config also shows two more keys:

- `fail_on_layer_violation: true` makes layer violations fail the run. Without it they are reported, but the exit code stays `0`.
- `ignore:` skips `lib/presentation/legacy/**`, so [`old_page.dart`](lib/presentation/legacy/old_page.dart) is not reported, although it imports `data` too.

## Try it

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard example/cases/layers
```

```text
[!] LAYER BOUNDARY VIOLATIONS DETECTED (1):
  ❌ Layer Violation: [presentation] lib/presentation/profile_page.dart:2 -> [data] lib/data/user_dto.dart
     Rule: `presentation` may only import `presentation`, `domain`.
```

Exit code `1`.

## Fixing it

Use the `domain` entity in the page (`User`), and map the DTO to it in the data layer (`UserDto.toEntity()`). If the dependency is intended, add `data` to `presentation`'s `allowed_imports`.

Not sure which layers fit your folders? See [presets](../presets/README.md).

Learn more: [Configuration](https://creatorpiyush.github.io/arch_guard/configuration.html) · [How layers are matched](https://creatorpiyush.github.io/arch_guard/configuration.html#how-layers-are-matched)
