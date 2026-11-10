# Why does A depend on B (`why`)

`arch_guard why <from> <to>` prints the shortest import path from a file or folder to a file, folder or package. Use it when a layer rule or a forbidden package fires and you can't see where the import comes from.

`from` and `to` can be a file (`lib/domain/user.dart`), a folder (`lib/domain`), or a file name that matches one file (`user.dart`). `to` can also be a package: `package:http`, `http`, or `dart:io`.

## Try it

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
dart run arch_guard why lib/domain http example/cases/why
```

```text
lib/domain/user.dart reaches package:http in 2 step(s):
  lib/domain/user.dart:1  import  lib/data/user_repo.dart
  lib/data/user_repo.dart:2  import  package:http/http.dart
```

Each line is `file:line  directive  target`. Exit code `0`.

When there is no path, `why` exits `1`, so CI can assert that one never appears:

```bash
dart run arch_guard why lib/data lib/domain example/cases/why
```

```text
No import path from lib/data to lib/domain/.
```

Exit code `1`. An unknown file, or a file name that matches more than one file, exits `64`.
