#!/bin/sh
# Publishes arch_guard_lint from a clean export of HEAD.
# The repo-root .pubignore hides arch_guard_lint/ from the arch_guard package,
# and pub refuses pubspec_overrides.yaml, so publish from outside the repo.
# Publish the matching arch_guard version first.
set -eu
tmp=$(mktemp -d)
git archive HEAD arch_guard_lint | tar -x -C "$tmp"
rm "$tmp/arch_guard_lint/pubspec_overrides.yaml"
cd "$tmp/arch_guard_lint"
dart pub get
dart pub publish "$@"
