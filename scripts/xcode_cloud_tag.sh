#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/xcode_cloud_tag.sh plan <dev|staging> <label|complete-tag>
  scripts/xcode_cloud_tag.sh create <complete-tag> <planned-commit-sha>

Tags trigger Xcode Cloud. `create` creates an annotated tag and pushes only
that tag to origin. It does not create or push a branch.
EOF
}

fail() {
  printf 'xcode_cloud_tag: %s\n' "$*" >&2
  exit 1
}

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || fail 'run this command inside the repository'
cd "$repo_root"

project=${GOURMEPP_XCODE_PROJECT:-グルメップ.xcodeproj}
project_file="$project/project.pbxproj"
[[ -f "$project_file" ]] || fail "Xcode project not found: $project_file"

versions=$(awk -F'= ' '/^[[:space:]]*MARKETING_VERSION = / { gsub(/;.*/, "", $2); print $2 }' "$project_file" | sort -u)
[[ -n "$versions" && "$versions" != *$'\n'* ]] || fail "expected one MARKETING_VERSION in $project_file"
version=$versions
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail "unsupported MARKETING_VERSION: $version"

require_clean_tree() {
  local changes
  changes=$(git status --porcelain --untracked-files=all)
  [[ -z "$changes" ]] || fail 'working tree has uncommitted changes; commit or remove them before planning a tag'
}

check_tag_available() {
  local tag=$1 ref="refs/tags/$1" remote_refs status
  git show-ref --verify --quiet "$ref" && fail "tag already exists locally: $tag"
  set +e
  remote_refs=$(git ls-remote --exit-code --refs origin "$ref" 2>&1)
  status=$?
  set -e
  case "$status" in
    0) fail "tag already exists on origin: $tag" ;;
    2) ;;
    *) fail "could not check origin for tag collisions: $remote_refs" ;;
  esac
}

resolve_tag() {
  local kind=$1 input=$2 tag
  if [[ "$input" == "$kind."* ]]; then
    tag=$input
  else
    local label
    label=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]_]+/-/g')
    [[ "$label" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || fail 'label must use English letters, numbers, and kebab-case separators'
    tag="$kind.$version-$label"
  fi

  [[ "$tag" =~ ^(dev|staging)\.([0-9]+(\.[0-9]+)*)-([a-z0-9]+(-[a-z0-9]+)*)$ ]] || fail "invalid dev/staging tag: $tag"
  [[ "${BASH_REMATCH[1]}" == "$kind" ]] || fail "tag type does not match requested type ($kind): $tag"
  [[ "${BASH_REMATCH[2]}" == "$version" ]] || fail "tag version must match MARKETING_VERSION ($version): $tag"
  printf '%s\n' "$tag"
}

command=${1:-}
case "$command" in
  plan)
    [[ $# -eq 3 ]] || { usage; exit 2; }
    kind=$2
    [[ "$kind" == dev || "$kind" == staging ]] || fail 'type must be dev or staging'
    require_clean_tree
    tag=$(resolve_tag "$kind" "$3")
    check_tag_available "$tag"
    commit=$(git rev-parse --verify HEAD^{commit})
    printf 'Tag: %s\nCommit: %s\nSubject: %s\n' "$tag" "$commit" "$(git log -1 --format=%s "$commit")"
    printf 'Project: %s\nMARKETING_VERSION: %s\n' "$project" "$version"
    printf 'Plan only. No tag was created or pushed.\n'
    ;;
  create)
    [[ $# -eq 3 ]] || { usage; exit 2; }
    tag=$2
    expected_commit=$3
    require_clean_tree
    [[ "$expected_commit" =~ ^[0-9a-f]{40}$ ]] || fail 'planned commit must be a full 40-character lowercase SHA'
    current_commit=$(git rev-parse --verify HEAD^{commit})
    [[ "$expected_commit" == "$current_commit" ]] || fail "HEAD changed since plan (planned $expected_commit, current $current_commit); run plan again"
    if [[ "$tag" == dev.* ]]; then
      kind=dev
    elif [[ "$tag" == staging.* ]]; then
      kind=staging
    else
      fail 'create only supports dev.* and staging.* tags; bare release tags use the release workflow'
    fi
    resolved=$(resolve_tag "$kind" "$tag")
    [[ "$resolved" == "$tag" ]] || fail "tag must be a complete tag name: $tag"
    check_tag_available "$tag"
    git tag -a "$tag" "$current_commit" -m "$tag"
    printf 'Created local tag %s at %s\n' "$tag" "$current_commit"
    for delay in 2 4 8 16; do
      if git push origin "refs/tags/$tag"; then
        printf 'Pushed origin tag %s at %s\n' "$tag" "$current_commit"
        exit 0
      fi
      printf 'Push failed; retrying in %ss.\n' "$delay" >&2
      sleep "$delay"
    done
    fail "push failed after four retries; local tag $tag remains at $current_commit"
    ;;
  *)
    usage
    exit 2
    ;;
esac
