#!/usr/bin/env bash
set -e

# ANSI Color Codes
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BLUE}${BOLD}=== Running Pre-Commit Verification ===${NC}\n"

echo -e "${BLUE}1/3 Checking code formatting...${NC}"
if ! dart format --output=none --set-exit-if-changed .; then
  echo -e "${RED}✗ Formatting check failed! Run 'dart format .' to format code automatically.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Code formatting clean.${NC}\n"

echo -e "${BLUE}2/3 Running static analysis...${NC}"
if ! dart analyze --fatal-infos; then
  echo -e "${RED}✗ Static analysis failed! Please fix analyzer warnings/errors.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Static analysis passed with 0 warnings.${NC}\n"

echo -e "${BLUE}3/3 Running unit test suite...${NC}"
if ! dart test; then
  echo -e "${RED}✗ Unit tests failed! Please ensure all tests pass before committing.${NC}"
  exit 1
fi
echo -e "${GREEN}✓ All unit tests passed successfully.${NC}\n"

echo -e "${GREEN}${BOLD}🎉 Pre-commit check passed cleanly! Safe to commit.${NC}"
