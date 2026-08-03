#!/usr/bin/env bash
set -e

# ANSI Color Codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BLUE}${BOLD}=== Running Pre-Release Verification ===${NC}\n"

# 1. Regenerate offline asset bundle
echo -e "${BLUE}1/7 Regenerating offline asset bundle...${NC}"
if ! dart run tool/bundle_vis_network.dart; then
  echo -e "${RED}✗ Asset bundling failed! Please check tool/bundle_vis_network.dart.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Offline asset bundle up-to-date.${NC}\n"

# 2. Git working tree status check
echo -e "${BLUE}2/7 Checking git working directory status...${NC}"
if [ -n "$(git status --porcelain)" ]; then
  echo -e "${YELLOW}⚠️  Warning: You have uncommitted changes in your git repository.${NC}"
  echo -e "${YELLOW}Please commit or stash your changes before releasing.${NC}\n"
else
  echo -e "${GREEN}✓ Git working directory clean.${NC}\n"
fi

# 3. Version sync check between pubspec.yaml and CHANGELOG.md
echo -e "${BLUE}3/7 Verifying pubspec.yaml version in CHANGELOG.md...${NC}"
PUBSPEC_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | tr -d '\r')

if [ -z "$PUBSPEC_VERSION" ]; then
  echo -e "${RED}✗ Error: Could not find version in pubspec.yaml.${NC}"
  exit 1
fi

echo -e "Detected pubspec.yaml version: ${BOLD}${PUBSPEC_VERSION}${NC}"

if grep -q "# ${PUBSPEC_VERSION}" CHANGELOG.md || grep -q "## ${PUBSPEC_VERSION}" CHANGELOG.md; then
  echo -e "${GREEN}✓ CHANGELOG.md entry found for version ${PUBSPEC_VERSION}.${NC}\n"
else
  echo -e "${RED}✗ Error: CHANGELOG.md does not contain an entry for version '${PUBSPEC_VERSION}'.${NC}"
  echo -e "${RED}Please update CHANGELOG.md before releasing.${NC}"
  exit 1
fi

# 4. Formatting check
echo -e "${BLUE}4/7 Checking code formatting...${NC}"
if ! dart format --output=none --set-exit-if-changed .; then
  echo -e "${RED}✗ Formatting check failed! Run 'dart format .' to format code.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Code formatting clean.${NC}\n"

# 5. Static analysis
echo -e "${BLUE}5/7 Running static analysis...${NC}"
if ! dart analyze --fatal-infos; then
  echo -e "${RED}✗ Static analysis failed! Please fix analyzer warnings/errors.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Static analysis passed with 0 warnings.${NC}\n"

# 6. Unit test suite
echo -e "${BLUE}6/7 Running unit test suite...${NC}"
if ! dart test; then
  echo -e "${RED}✗ Unit tests failed! Please fix failing tests before releasing.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ All unit tests passed successfully.${NC}\n"

# 7. Pub publish dry run
echo -e "${BLUE}7/7 Running pub package dry-run validation...${NC}"
if ! dart pub publish --dry-run; then
  echo -e "${RED}✗ pub publish dry-run failed! Please fix pub package errors.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Package dry-run passed with zero warnings.${NC}\n"

echo -e "${GREEN}${BOLD}🚀 All pre-release checks passed! Package is ready for release v${PUBSPEC_VERSION}.${NC}"
