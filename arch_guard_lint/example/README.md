# arch_guard_lint example

A small app whose `domain` layer must not depend on `data` or on `dart:io`.
With the plugin enabled, both mistakes show up as warnings in the IDE and in
`dart analyze`.

## 1. Enable the plugin

```yaml
# analysis_options.yaml
plugins:
  arch_guard_lint: ^0.1.1
```

Restart the Dart analysis server after changing `plugins:`.

## 2. Describe the architecture

```yaml
# arch_guard.yaml
layers:
  domain:
    patterns: ["lib/domain/**"]
    forbidden_packages: ["dart:io"]
  data:
    patterns: ["lib/data/**"]
    allowed_imports: [domain]
```

## 3. Write code that breaks the rules

```dart
// lib/data/user_repository.dart
class UserRepository {}
```

```dart
// lib/domain/user_service.dart
import 'dart:io'; // the domain layer may not use dart:io
import '../data/user_repository.dart'; // domain may not import data

class UserService {
  UserService(this.repository);

  final UserRepository repository;

  bool get cacheExists => File('cache.json').existsSync();
}
```

## 4. See the warnings

```console
$ dart analyze
warning - lib/domain/user_service.dart:1:8 - Layer `domain` may not import `dart:io` (forbidden_packages: `dart:io`). Depend on an interface declared in `domain` and implement it in a layer that may use `dart:io`, or, if this is intended, remove `dart:io` from the `forbidden_packages` of `domain`. - forbidden_package
warning - lib/domain/user_service.dart:2:8 - Layer `domain` imports `lib/data/user_repository.dart` from layer `data`. `domain` may not import other layers. Invert the dependency (e.g. an interface in `domain` that `data` implements), move the code to a layer `domain` may import, or, if this dependency is intended, add `data` to the `allowed_imports` of `domain`. - layer_violation
```

To accept one on purpose, add `// ignore: arch_guard_lint/layer_violation` above
the import. To accept everything that exists today, run
`dart run arch_guard --update-baseline`: the plugin skips problems listed in
`arch_guard_baseline.json`.
