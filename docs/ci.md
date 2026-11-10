---
title: CI & hooks
---

# CI & hooks

Run arch_guard where it stops problems early: on every pull request, and optionally before each commit. Exit codes are listed on the [CLI](cli.md#exit-codes) page.

## Adopting on an existing codebase (baseline)

Large projects rarely start clean. Record the problems you have today, commit the file, and from then on only *new* problems fail the run:

```bash
arch_guard --update-baseline        # writes arch_guard_baseline.json
git add arch_guard_baseline.json
```

How later runs compare against the baseline:

- A **layer violation** is known if the same `source -> target` import is listed.
- A **cycle** is known if all its files belong to one baseline cycle. A cycle that shrinks stays accepted; one that grows, or merges two known cycles, is new.
  - Only **membership** is compared, not the imports inside the cycle. With a baseline cycle `a -> b -> c -> a`, adding `a -> c` (or removing it again) still passes: the cycle has the same three files. To cap how big a cycle may get, use [`max_scc_size`](configuration.md).
  - Each new cycle says why it is new, e.g. `Why new: grew from a known 3-file cycle, adding lib/d.dart`, `merges 2 known cycles`, or `none of its files is in a baseline cycle`.
- An **unused file** is known if its path is listed. One that is used again or deleted counts as fixed.
- When baseline entries disappear, the run says so. Run `--update-baseline` again to lock in the improvement so the problems cannot come back.
- The run also says when a known problem got smaller without going away: a cycle group that lost files or split, or a metric value that dropped. Update the baseline to lock that in too. Otherwise a saved `{a, b, c}` still accepts `c` coming back after you shrank the group to `{a, b}`.
- Updating is always manual. "No regression" means no worse than the saved baseline file, not than the last passing run.

Use `--baseline path/to/file.json` to keep the file somewhere else (paths are relative to the scanned project).

## GitHub Action

```yaml
# .github/workflows/architecture.yml
name: Architecture
on: [pull_request]

permissions:
  contents: read
  pull-requests: write     # PR comment
  # security-events: write # only with upload-sarif: true

jobs:
  arch_guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: creatorpiyush/arch_guard@v1.14.0
        with:
          path: .                  # project to scan
          args: --scan-dir lib     # any extra CLI flags
          # upload-sarif: true     # show results in the Security tab / PR diff
```

The action downloads the release binary (checksum-verified, no Dart SDK needed), writes the Markdown summary to the job summary, keeps a single PR comment up to date, and fails the job when arch_guard exits non-zero. Inputs: `path`, `version`, `args`, `comment`, `upload-sarif`, `output-dir`, `token`. Outputs: `exit-code`, `sarif-file`, `markdown-file`. Prebuilt binaries cover Linux x64/arm64, macOS arm64 and Windows x64; on other runners install Dart and set `version: source`.

Code Scanning (`upload-sarif: true`) is free for public repositories; private repositories need GitHub Advanced Security.

The PR comment looks like this: a status line, a summary table, the new problems with the rule each one breaks, and the cycle graph in a collapsible Mermaid block.

### Large repositories: only changed files

`--since` reports only problems that touch files changed on the branch, so a PR in a big repository isn't blamed for old problems elsewhere. The whole project is still analysed (cycles need the full graph).

```yaml
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # --since needs the merge base
      - uses: creatorpiyush/arch_guard@v1.14.0
        with:
          args: --since origin/${{ github.base_ref }}
```

### Run only the tests a PR can affect

`arch_guard affected` lists the test files that the branch's changes can reach through imports, so a large repository can skip unrelated tests:

```yaml
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # affected needs the merge base
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - name: Affected tests
        run: |
          t=$(dart run arch_guard affected --since origin/${{ github.base_ref }})
          if [ -n "$t" ]; then dart test $t; else echo "No affected tests."; fi
```

Keep the empty check: `dart test` with no paths runs every test. Flutter projects use `flutter test`. See [Tests affected by a branch](cli.md#tests-affected-by-a-branch).

### How long a run takes

A full run, scan included, takes about 0.07 s per 1,000 files. Most of it is reading the files, which the operating system limits. The [unused-file check](configuration.md#unused-files) adds about 2 ms per 1,000 files. Measured on generated projects with about 6 imports per file, using the compiled CLI (median of 7 runs):

| Files | Workspace members | Unused-file check alone | Full run, check off | Full run, check on |
| ---: | ---: | ---: | ---: | ---: |
| 1,000 | none | 1.9 ms | 93 ms | 93 ms |
| 5,000 | none | 8.9 ms | 382 ms | 410 ms |
| 5,050 | 50 | 19 ms | 408 ms | 417 ms |
| 10,000 | none | 19 ms | 709 ms | 735 ms |
| 20,000 | none | 42 ms | 1,348 ms | 1,439 ms |
| 20,200 | 200 | 82 ms | 1,502 ms | 1,585 ms |

Differences of a few percent between runs are noise. `dart run arch_guard` adds about a second of Dart startup; the [GitHub Action](#github-action) and the [standalone binaries](cli.md#standalone-binaries-no-dart-sdk-needed) don't.

## GitLab CI

```yaml
arch_guard:
  image: dart:stable
  script:
    - dart pub global activate arch_guard
    - dart pub global run arch_guard . -f sarif -f markdown -o reports
  artifacts:
    when: always
    paths: [reports/]
```

GitLab does not read SARIF natively, so keep the reports as artifacts; `reports/arch_guard_report.md` can be posted to the merge request from a script.

## pre-commit

With [pre-commit](https://pre-commit.com) 2.15 or later:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/creatorpiyush/arch_guard
    rev: v1.14.0
    hooks:
      - id: arch_guard
        # args: [--no-fail-on-cycle]
```

## lefthook

```yaml
# lefthook.yml
pre-commit:
  commands:
    arch_guard:
      glob: "*.dart"
      run: dart run arch_guard --no-color
```

(Requires `arch_guard` as a dev dependency.)

## Plain git hook

Save as `.git/hooks/pre-commit` and make it executable (`chmod +x .git/hooks/pre-commit`):

```bash
#!/bin/sh
dart run arch_guard --no-color || {
  echo "arch_guard found new architecture problems; commit aborted."
  exit 1
}
```

With a committed baseline, hooks only block commits that introduce *new* problems.
