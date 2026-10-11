# Circular dependencies and cycle-breaking hints

Two groups of files that import each other:

```text
lib/shop/     cart → checkout → cart, and cart → checkout → payment → cart
lib/account/  profile ⇄ settings ⇄ theme
```

For each group, arch_guard names the one import whose removal breaks it. When no single import does, it names the import that shrinks the group the most. [`arch_guard.yaml`](arch_guard.yaml) also sets `max_scc_size: 2`, so both 3-file groups are reported as too large.

## Try it

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard example/cases/cycles
```

```text
  Strongly Connected Component #1 (3 files)
    [Metrics: 4 internal edges | Avg Fan-In: 1.33 | Avg Fan-Out: 1.33 | Hub: lib/account/settings.dart]
    Representative Cycle Path:
    lib/account/settings.dart
    -> lib/account/profile.dart
    -> lib/account/settings.dart
    • Additional Files: lib/account/theme.dart
    Suggested fix: remove lib/account/profile.dart:1 -> lib/account/settings.dart (shrinks the group from 3 to 2 files)

  Strongly Connected Component #2 (3 files)
    [Metrics: 4 internal edges | Avg Fan-In: 1.33 | Avg Fan-Out: 1.33 | Hub: lib/shop/checkout.dart]
    Representative Cycle Path:
    lib/shop/cart.dart
    -> lib/shop/checkout.dart
    -> lib/shop/cart.dart
    • Additional Files: lib/shop/payment.dart
    Suggested fix: remove lib/shop/cart.dart:1 -> lib/shop/checkout.dart (breaks the cycle)

[!] SCC SIZE LIMIT EXCEEDED (max_scc_size: 2):
  Component #1 has 3 files
  Component #2 has 3 files
```

Exit code `1`. The `cart → checkout` import is on every loop of the shop group, which is why removing it breaks the whole group.

## Variations

```bash
# Report cycles but don't fail on them (max_scc_size still fails: exit 1)
dart run arch_guard example/cases/cycles --no-fail-on-cycle

# Why is payment.dart in a cycle? What does it import, what imports it?
dart run arch_guard example/cases/cycles --explain lib/shop/payment.dart
```

The hint is also in the Markdown, SARIF and JSON reports (`scc.suggestedBreak`); see [reports](../reports/README.md).

Learn more: [CLI recipes](https://creatorpiyush.github.io/arch_guard/cli.html#fix-a-cycle) · [`max_scc_size`](https://creatorpiyush.github.io/arch_guard/configuration.html#keys)
