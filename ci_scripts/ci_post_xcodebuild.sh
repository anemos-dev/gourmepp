#!/bin/bash
set -euo pipefail

# Xcode Cloud runs this after xcodebuild and reads TestFlight notes from the
# repository's TestFlight directory before uploading the archived app.
[[ "${CI_XCODE_CLOUD:-}" == "TRUE" ]] || exit 0
[[ "${CI_XCODEBUILD_EXIT_CODE:-1}" == "0" ]] || exit 0
[[ -n "${CI_APP_STORE_SIGNED_APP_PATH:-}" && -d "$CI_APP_STORE_SIGNED_APP_PATH" ]] || exit 0
[[ -n "${CI_TAG:-}" ]] || exit 0

if [[ "$CI_TAG" =~ ^(dev|staging)\.[0-9]+(\.[0-9]+)*-[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  repository_path=${CI_PRIMARY_REPOSITORY_PATH:-"$(cd "$(dirname "$0")/.." && pwd)"}
  notes_dir="$repository_path/TestFlight"
  mkdir -p "$notes_dir"
  printf '%s' "$CI_TAG" > "$notes_dir/WhatToTest.ja.txt"
fi
