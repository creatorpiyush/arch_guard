# Only files changed on a branch (`--since`)

In a large repository, `--since <git-ref>` reports, and fails on, only problems that touch files changed since the merge base with that ref. Uncommitted and untracked files count too. The whole project is still analysed, because cycles need the full graph.

## Try it

This walkthrough copies the [layers](../layers/README.md) case, which already has one layer violation, into a fresh git repository.

Run from a clone of the repository (`git clone https://github.com/creatorpiyush/arch_guard && cd arch_guard && dart pub get`).

```bash
cp -r example/cases/layers /tmp/since-demo
(cd /tmp/since-demo && git init -q -b main && git add . && git commit -qm base)

# Nothing changed since main: the old violation is not reported.
dart run arch_guard /tmp/since-demo --since main
```

```text
Only problems touching 0 file(s) changed since main.
```

Exit code `0`. Now add a file with a bad import, as a branch would:

```bash
cat > /tmp/since-demo/lib/presentation/settings_page.dart <<'EOF'
import '../data/api_user_repository.dart';

class SettingsPage {
  final repo = ApiUserRepository();
}
EOF
dart run arch_guard /tmp/since-demo --since main
```

```text
Only problems touching 1 file(s) changed since main.

[!] LAYER BOUNDARY VIOLATIONS DETECTED (1):
  ❌ Layer Violation: [presentation] lib/presentation/settings_page.dart:1 -> [data] lib/data/api_user_repository.dart
```

Exit code `1`. Only the new file is reported.

## In CI

```yaml
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # --since needs the merge base
      - uses: creatorpiyush/arch_guard@v1.7.0
        with:
          args: --since origin/${{ github.base_ref }}
```

- A cycle counts when any of its files changed.
- A `max_fan_in` violation also counts when a changed file imports the over-limit file.
- `--since` cannot be combined with `--update-baseline` or `--explain`.
- In tests, use `expectArchitecture(since: 'origin/main')`; see [testing](../testing/README.md).

Learn more: [CLI](https://creatorpiyush.github.io/arch_guard/cli.html#only-files-changed-on-this-branch) · [CI](https://creatorpiyush.github.io/arch_guard/ci.html#large-repositories-only-changed-files)
