# Baselines: adopt on an existing codebase

This project already had a cycle (`order_dto.dart` ⇄ `order_mapper.dart`). It was recorded in [`arch_guard_baseline.json`](arch_guard_baseline.json) with:

```bash
dart run arch_guard example/cases/baseline --update-baseline
```

After that, [`domain/order.dart`](lib/domain/order.dart) gained an import of `data`, which is a **new** layer violation.

## Try it

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard example/cases/baseline
```

```text
[!] NEW LAYER BOUNDARY VIOLATIONS DETECTED (1):
  ❌ Layer Violation: [domain] lib/domain/order.dart:1 -> [data] lib/data/order_dto.dart
     Rule: `domain` may only import `domain`.

Baseline: arch_guard_baseline.json
  Known (ignored): 1 cycle group(s), 0 layer violation(s), 0 forbidden package import(s)
  New:             0 cycle group(s), 1 layer violation(s), 0 forbidden package import(s)
```

The known cycle is still shown, but only the new violation makes the run fail (exit `1`). When a known problem is fixed, arch_guard says so. Run `--update-baseline` again to keep it from coming back.

Commit the baseline file. Use `--baseline <path>` to keep it elsewhere.

Learn more: [Baselines](https://creatorpiyush.github.io/arch_guard/ci.html#adopting-on-an-existing-codebase-baseline)
