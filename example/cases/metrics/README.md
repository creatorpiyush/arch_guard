# Metric limits and hotspots

[`utils.dart`](lib/utils.dart) is imported by 4 files, and [`app.dart`](lib/app.dart) imports 4 files. [`arch_guard.yaml`](arch_guard.yaml) sets these limits:

```yaml
metrics:
  max_fan_out: 3   # a file may import at most 3 project files
  max_fan_in: 3    # at most 3 project files may import it
  hotspots: 3      # most-coupled files listed in reports
```

## Try it

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard example/cases/metrics
```

```text
[!] METRIC LIMITS EXCEEDED (2):
  ❌ Metric Limit: lib/app.dart fan_out=4 (max 3)
     Rule: `lib/app.dart` imports 4 files (max_fan_out: 3).
  ❌ Metric Limit: lib/utils.dart fan_in=4 (max 3)
     Rule: `lib/utils.dart` is imported by 4 files (max_fan_in: 3).

Most coupled files:
  lib/app.dart  in 0  out 4
  lib/utils.dart  in 4  out 0
  lib/cart.dart  in 1  out 1
```

Exit code `1`.

With a [baseline](../baseline/README.md), limits ratchet: a known file passes as long as it gets no worse. Only project files count; `package:` and `dart:` imports don't.

Learn more: [Metric limits](https://creatorpiyush.github.io/arch_guard/configuration.html#metric-limits)
