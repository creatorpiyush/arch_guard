# Module boundaries

A feature-first app with Clean Architecture layers inside each feature:

```text
lib/features/
  auth/      auth.dart (public)      domain/session.dart
  cart/      cart.dart (public)      domain/cart_item.dart   data/cart_repository.dart
  checkout/  checkout.dart (public)  presentation/checkout_page.dart
```

Layers alone can't stop `checkout` from reaching into `cart/data/`, because they only see `presentation -> data`, and would allow `checkout -> cart/domain/` just as well. The `modules:` section in [`arch_guard.yaml`](arch_guard.yaml) adds a second, independent rule set:

```yaml
preset: clean_architecture

modules:
  roots: [lib/features/*]      # each folder is one module: auth, cart, checkout
  # public: ["*.dart"]         # default: files directly in the module folder
  allowed:
    checkout: [cart]           # checkout may use cart, nothing else
```

`checkout_page.dart` imports three files:

| Import | Layer rule | Module rule |
| --- | --- | --- |
| `cart/cart.dart` (public barrel) | ok | ok |
| `cart/data/cart_repository.dart` | ❌ presentation → data | ❌ private file of `cart` |
| `auth/auth.dart` | ok | ❌ `auth` is not in `allowed` |

## Try it

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard example/cases/modules
```

```text
[!] MODULE BOUNDARY VIOLATIONS (2):
  ❌ Module Violation: [checkout] lib/features/checkout/presentation/checkout_page.dart:1 -> [auth] lib/features/auth/auth.dart
     Rule: `checkout` may only import modules `cart`.
  ❌ Module Violation: [checkout] lib/features/checkout/presentation/checkout_page.dart:3 -> [cart] lib/features/cart/data/cart_repository.dart
     Rule: Other modules may import `cart` only through lib/features/cart/*.dart.
```

Exit code `1`. The layer violation on line 3 is reported too, in its own section.

A module's own barrel may re-export its private files: that is the intended way in. Files outside every module (`lib/main.dart`, shared code) may import and be imported by any module.

Learn more: [Module boundaries](https://creatorpiyush.github.io/arch_guard/configuration.html#module-boundaries)
