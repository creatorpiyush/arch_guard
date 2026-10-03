# Contributing to arch_guard

Thanks for helping! Bug reports, preset ideas, docs fixes and code are all welcome.

## Before you start

- **Bugs:** open an issue with the [bug template](https://github.com/creatorpiyush/arch_guard/issues/new?template=bug_report.yml). A small folder layout and `arch_guard.yaml` that reproduce the problem help the most.
- **Features and new presets:** open an issue first so we can agree on the behaviour before you write code.
- Issues labelled [`good first issue`](https://github.com/creatorpiyush/arch_guard/labels/good%20first%20issue) are a good place to start.

## Setup

You need the Dart SDK 3.8 or later. The repository pins a Flutter version in `.fvmrc` for [FVM](https://fvm.app) users, but plain Dart works too.

```bash
git clone https://github.com/creatorpiyush/arch_guard.git
cd arch_guard
dart pub get
dart run bin/arch_guard.dart example/sample_project --no-fail-on-cycle
```

`example/sample_project` deliberately contains two cycles and a layer violation, so it is handy for trying changes.

## Checks

CI runs these on Linux, macOS and Windows; run them before you push:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

or all at once with `./tool/pre_commit.sh`. Public API members need a `///` doc comment (the `public_member_api_docs` lint is on).

## Making a change

1. Create a branch named `type/short-description`, for example `feat/hexagonal-preset` or `fix/windows-glob-paths`.
2. Add or update tests in `test/` for any behaviour change.
3. Add a line to the top section of `CHANGELOG.md` describing the change from a user's point of view.
4. Update the docs in `docs/` (and the README if it covers the topic).
5. Open a pull request; the template has a short checklist.

If you change the HTML report or the terminal output, regenerate the screenshots with `dart run tool/screenshots.dart` (needs Chrome).

## Where things live

| Path | What |
| :--- | :--- |
| `bin/arch_guard.dart`, `lib/src/cli/` | Command line entry point, flags, `init` |
| `lib/src/scanner/` | Finding files and packages, reading directives, layout detection |
| `lib/src/graph/` | Dependency graph, Tarjan SCCs, `--explain` |
| `lib/src/checker/`, `lib/src/models/` | Layer validation, config and presets |
| `lib/src/baseline/` | Baseline file |
| `lib/src/exporters/`, `lib/src/reporters/` | HTML, Mermaid, DOT, JSON, SARIF, Markdown and text output |
| `action.yml`, `.pre-commit-hooks.yaml` | GitHub Action and pre-commit hook |
| `docs/` | Documentation site (GitHub Pages) |

[ARCHITECTURE.md](ARCHITECTURE.md) describes the design in more depth.

## Releases

Releases are made by the maintainer: version bump in `pubspec.yaml` and `lib/src/version.dart`, `./tool/pre_release.sh`, then a `vX.Y.Z` tag, which publishes to pub.dev and builds the release binaries.
