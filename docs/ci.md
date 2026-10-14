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
      - uses: creatorpiyush/arch_guard@v1.9.2
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
      - uses: creatorpiyush/arch_guard@v1.9.2
        with:
          args: --since origin/${{ github.base_ref }}
```

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
    rev: v1.9.2
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
