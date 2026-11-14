#!/bin/sh
# Installs the arch_guard binary from a GitHub release. No Dart SDK needed.
#
#   curl -fsSL https://creatorpiyush.github.io/arch_guard/install.sh | sh
#
# ARCH_GUARD_VERSION      release to install, e.g. 1.15.0 or v1.15.0 (default: latest)
# ARCH_GUARD_INSTALL_DIR  where to put the binary (default: ~/.local/bin)
#
# Running it again replaces the installed binary, so it also upgrades.
set -eu

repo="https://github.com/creatorpiyush/arch_guard/releases"
version="${ARCH_GUARD_VERSION:-latest}"
install_dir="${ARCH_GUARD_INSTALL_DIR:-$HOME/.local/bin}"

fail() {
  echo "arch_guard install: $*" >&2
  exit 1
}

no_binary() {
  fail "no prebuilt binary for $1. Install Dart (https://dart.dev/get-dart) and run: dart pub global activate arch_guard"
}

os=$(uname -s)
arch=$(uname -m)
ext=""
case "$os" in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  MINGW* | MSYS* | CYGWIN*) os=windows ext=".exe" ;;
  *) no_binary "$os" ;;
esac
case "$arch" in
  x86_64 | amd64) arch=x64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) no_binary "$os/$arch" ;;
esac
target="$os-$arch"
case "$target" in
  linux-x64 | linux-arm64 | macos-arm64 | windows-x64) ;;
  *) no_binary "$target" ;;
esac

if [ "$version" = "latest" ]; then
  url="$repo/latest/download"
else
  url="$repo/download/v${version#v}"
fi

command -v curl >/dev/null 2>&1 || fail "curl is required."
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1"; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1"; }
else
  fail "sha256sum or shasum is required to verify the download."
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

asset="arch_guard-$target$ext"
echo "Downloading $asset ($version)..."
curl -fsSL --retry 3 -o "$tmp/$asset" "$url/$asset" ||
  fail "could not download $url/$asset. Check that release '$version' exists: $repo"
curl -fsSL --retry 3 -o "$tmp/SHA256SUMS.txt" "$url/SHA256SUMS.txt" ||
  fail "could not download $url/SHA256SUMS.txt."

expected=$(grep " $asset\$" "$tmp/SHA256SUMS.txt" | cut -d ' ' -f 1)
[ -n "$expected" ] || fail "SHA256SUMS.txt has no entry for $asset."
actual=$(sha256 "$tmp/$asset" | cut -d ' ' -f 1)
[ "$expected" = "$actual" ] ||
  fail "checksum mismatch for $asset (expected $expected, got $actual). Nothing was installed."

mkdir -p "$install_dir"
chmod +x "$tmp/$asset"
mv -f "$tmp/$asset" "$install_dir/arch_guard$ext"
echo "Installed $("$install_dir/arch_guard$ext" --version) to $install_dir/arch_guard$ext"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *) echo "Add $install_dir to your PATH to run arch_guard from anywhere." ;;
esac
